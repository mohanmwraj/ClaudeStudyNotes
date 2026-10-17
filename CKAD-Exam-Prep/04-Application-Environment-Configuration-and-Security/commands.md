# Commands - Application Environment, Configuration and Security

Grouped reference for this chapter. Every command has a one-line comment. Placeholders: `<ns>`, `<pod>`, `<sa>`, etc. Start **every** exam task with the context switch shown in the task header.

Tool note: exam hosts are only guaranteed to have `kubectl` (with the `k` alias and completion), `yq`, `curl`, `wget` and `man` plus standard Linux utilities (`base64`, `grep`, `awk`, ...). `jq` is not guaranteed - use `-o jsonpath` / `-o go-template`. `openssl` and `capsh` lines are for your own lab. See [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md).

---

## 0. Context and kubeconfig

```bash
kubectl config use-context <ctx>                                   # switch cluster/user (first thing in every task)
kubectl config current-context                                     # print the current context name
kubectl config get-contexts                                        # table of contexts, * = current
kubectl config get-contexts -o name                                # context names only
kubectl config get-contexts -o name > /opt/course/1/contexts       # typical "write all contexts to a file"
kubectl config set-context --current --namespace=<ns>              # default namespace for the current context
kubectl config set-context <ctx> --cluster=<cluster> --user=<user> --namespace=<ns>   # create/modify a context
kubectl config view                                                # merged kubeconfig (secrets redacted)
kubectl config view --minify                                       # only the current context's cluster/user/context
kubectl config view --raw                                          # include cert/key data and tokens
kubectl config view -o jsonpath='{.contexts[*].name}'              # any field via JSONPath
kubectl config view -o jsonpath='{.contexts[?(@.name=="<ctx>")].context.user}'   # user of one context
kubectl config view --raw -o jsonpath='{.users[?(@.name=="<user>")].user.client-certificate-data}' | base64 -d > user.crt   # decode a client cert
openssl x509 -in user.crt -noout -subject -enddate                 # show CN/O (user/groups) and expiry
kubectl config get-clusters                                        # cluster entries
kubectl config get-users                                           # user entries
kubectl config set-cluster <c> --server=https://<ip>:6443 --certificate-authority=ca.crt --embed-certs=true   # add a cluster
kubectl config set-credentials <u> --client-certificate=<u>.crt --client-key=<u>.key --embed-certs=true       # add a cert user
kubectl config set-credentials <u> --token=<token>                 # add a token user
kubectl config rename-context <old> <new>                          # rename a context
kubectl config delete-context <ctx>                                # remove a context
kubectl config unset users.<u>                                     # remove an entry by path
kubectl --context=<ctx> get pods                                   # one-off command against another context
KUBECONFIG=~/.kube/config:/tmp/other.conf kubectl config view --flatten > merged.conf   # merge kubeconfig files
grep 'current-context:' ~/.kube/config | awk '{print $2}'          # current context WITHOUT kubectl
```

## 1. CRDs and operators

```bash
kubectl get crd                                                    # list all CustomResourceDefinitions
kubectl get crd | grep -i <word>                                   # find an extension by name
kubectl get crd <plural>.<group> -o yaml                           # full CRD (names, versions, schema)
kubectl describe crd <plural>.<group>                              # incl. Established/NamesAccepted conditions
kubectl get crd <plural>.<group> -o jsonpath='{.spec.versions[*].name}{"\n"}'   # served versions
kubectl get crd -o custom-columns=NAME:.metadata.name,GROUP:.spec.group,SCOPE:.spec.scope   # overview
kubectl api-resources --api-group=<group>                          # kinds, short names, namespaced? for one group
kubectl api-resources -o wide | grep -i <kind>                     # incl. supported verbs
kubectl api-resources --namespaced=false                           # cluster-scoped kinds
kubectl api-versions | grep <group>                                # served group/versions
kubectl explain <kind>                                             # schema-driven docs of a custom kind
kubectl explain <kind>.spec --recursive                            # whole field tree under spec
kubectl explain <kind> --api-version=<group>/<version>             # pick a specific group/version
kubectl apply -f crd.yaml                                          # create/update a CRD
kubectl wait --for=condition=Established crd/<plural>.<group> --timeout=60s   # wait before creating CRs
kubectl get <plural> -A                                            # list custom resources in all namespaces
kubectl get <plural>.<group> -n <ns>                               # fully qualified (avoids short-name clashes)
kubectl get <shortname> <name> -o yaml > cr.yaml                   # export a CR as a template
kubectl apply -f cr.yaml --dry-run=server                          # validate a CR against the CRD schema
kubectl apply -f cr.yaml                                           # create/update a CR
kubectl edit <kind> <name>                                         # edit a CR
kubectl patch <kind> <name> --type=merge -p '{"spec":{"replicas":3}}'   # patch a CR
kubectl scale <kind> <name> --replicas=3                           # needs subresources.scale
kubectl get <kind> <name> -o jsonpath='{.status}{"\n"}'            # what the operator reported
kubectl get pods -A | grep -i operator                             # find operator controllers
kubectl logs -n <operator-ns> deploy/<operator> --tail=50          # why a CR is not reconciled
kubectl get apiservices                                            # aggregated APIs (e.g. metrics.k8s.io)
kubectl get <plural> -A -o yaml > backup.yaml                      # back up CRs before touching the CRD
kubectl patch <kind> <name> --type=merge -p '{"metadata":{"finalizers":null}}'   # LAST RESORT: unblock a stuck CR
kubectl delete crd <plural>.<group>                                # DANGER: deletes all CRs of that kind
```

## 2. RBAC

```bash
# create / generate
kubectl create role <r> -n <ns> --verb=get,list,watch --resource=pods                       # namespaced Role
kubectl create role <r> -n <ns> --verb=get --resource=pods,pods/log                         # with a subresource
kubectl create role <r> -n <ns> --verb=create --resource=pods/exec                          # allow kubectl exec (plus get pods)
kubectl create role <r> -n <ns> --verb=get,list,watch,create,update,patch,delete --resource=deployments.apps   # group-qualified
kubectl create role <r> -n <ns> --verb=get,patch,update --resource=deployments/scale        # scale subresource
kubectl create role <r> -n <ns> --verb=get --resource=secrets --resource-name=<secret>      # one object only
kubectl create role <r> -n <ns> --verb='*' --resource=configmaps --dry-run=client -o yaml > role.yaml   # generate YAML
kubectl create clusterrole <cr> --verb=get,list,watch --resource=nodes,persistentvolumes    # cluster-scoped resources
kubectl create clusterrole <cr> --verb=get --non-resource-url=/healthz --non-resource-url=/version   # non-resource URLs
kubectl create clusterrole <cr> --aggregation-rule="rbac.example.com/aggregate-to-<x>=true"  # aggregated ClusterRole
kubectl create rolebinding <rb> -n <ns> --role=<r> --serviceaccount=<sa-ns>:<sa>             # Role -> SA
kubectl create rolebinding <rb> -n <ns> --role=<r> --user=<user> --group=<group>             # Role -> user + group
kubectl create rolebinding <rb> -n <ns> --clusterrole=<cr> --serviceaccount=<sa-ns>:<sa>     # ClusterRole scoped to one ns
kubectl create rolebinding <rb> -n <ns> --clusterrole=view --group=<group>                   # built-in read-only role
kubectl create clusterrolebinding <crb> --clusterrole=<cr> --serviceaccount=<ns>:<sa>        # cluster-wide grant to an SA
kubectl create clusterrolebinding <crb> --clusterrole=<cr> --user=<user> --dry-run=client -o yaml > crb.yaml   # generate
kubectl auth reconcile -f rbac.yaml                                # create/extend RBAC objects without clobbering

# inspect
kubectl get roles,rolebindings -n <ns>                             # namespaced RBAC objects
kubectl get rolebindings -n <ns> -o wide                           # ROLE, USERS, GROUPS, SERVICEACCOUNTS columns
kubectl get clusterrolebindings -o wide | grep <subject>           # cluster-wide grants for a subject
kubectl describe role <r> -n <ns>                                  # rules table
kubectl describe rolebinding <rb> -n <ns>                          # role + subjects
kubectl get clusterrole <cr> -o yaml                               # full rules (incl. aggregated rules)
kubectl get rolebinding <rb> -n <ns> -o jsonpath='{.roleRef.name}{"\n"}'   # which role a binding grants

# verify
kubectl auth can-i <verb> <resource> -n <ns>                       # yourself
kubectl auth can-i <verb> <resource> -n <ns> --as=<user>           # impersonate a user
kubectl auth can-i <verb> <resource> -n <ns> --as=<user> --as-group=<group>   # user + group
kubectl auth can-i <verb> <resource> -n <ns> --as=system:serviceaccount:<ns>:<sa>   # impersonate an SA
kubectl auth can-i get pods --subresource=log -n <ns> --as=<user>  # subresource check
kubectl auth can-i get secrets/<name> -n <ns> --as=<user>          # one named object
kubectl auth can-i --list -n <ns> --as=system:serviceaccount:<ns>:<sa>   # everything the SA may do
kubectl auth can-i '*' '*' -A                                      # effectively cluster-admin?
kubectl auth can-i delete pods -n <ns> -q --as=<user>; echo $?     # exit code only (0 = yes)

# change
kubectl edit role <r> -n <ns>                                      # rules are editable
kubectl delete rolebinding <rb> -n <ns> && kubectl create rolebinding <rb> -n <ns> --role=<new> --serviceaccount=<ns>:<sa>   # roleRef is immutable
```

## 3. Authentication and identity

```bash
kubectl auth whoami                                                # current username and groups
kubectl auth whoami --as=system:serviceaccount:<ns>:<sa>           # impersonated identity
openssl genrsa -out <u>.key 2048                                   # private key for a new user
openssl req -new -key <u>.key -out <u>.csr -subj "/CN=<u>/O=<group>"   # CSR: CN = user, O = group
kubectl get csr                                                    # CertificateSigningRequests
kubectl certificate approve <csr>                                  # approve a CSR
kubectl certificate deny <csr>                                     # deny a CSR
kubectl get csr <csr> -o jsonpath='{.status.certificate}' | base64 -d > <u>.crt   # fetch the signed cert
sudo grep -E 'authorization-mode|client-ca-file|oidc' /etc/kubernetes/manifests/kube-apiserver.yaml   # authn/authz flags (kubeadm)
```

## 4. Admission control and Pod Security

```bash
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -E -- '--(enable|disable)-admission-plugins'   # configured plugins
kubectl -n kube-system exec kube-apiserver-<node> -- kube-apiserver -h | grep -- '--enable-admission-plugins'            # compiled-in defaults
sudo grep -- --enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml     # on the control plane
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak       # back up OUTSIDE manifests/
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml                                    # edit flags; kubelet restarts the Pod
sudo crictl ps --name kube-apiserver                               # wait for the new API server container
sudo crictl ps -a --name kube-apiserver && sudo crictl logs <id>   # debug an API server that does not come back
sudo journalctl -u kubelet --since "5 min ago" | tail -30          # kubelet view of static Pod errors
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations   # installed webhooks
kubectl get validatingadmissionpolicies,validatingadmissionpolicybindings   # CEL policies (GA v1.30)
kubectl label namespace <ns> pod-security.kubernetes.io/enforce=restricted    # enforce PSA level
kubectl label namespace <ns> pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/audit=restricted   # warn + audit
kubectl label --overwrite namespace <ns> pod-security.kubernetes.io/enforce=baseline   # change level
kubectl label namespace <ns> pod-security.kubernetes.io/enforce-version=v1.33          # pin policy version
kubectl label namespace <ns> pod-security.kubernetes.io/enforce-                       # remove the label
kubectl label --dry-run=server --overwrite namespace <ns> pod-security.kubernetes.io/enforce=restricted   # preview violations
kubectl get ns --show-labels | grep pod-security                   # which namespaces enforce what
kubectl describe rs -n <ns> -l app=<app> | grep -A3 FailedCreate   # why a Deployment has no Pods (PSA/quota)
kubectl get events -n <ns> --field-selector reason=FailedCreate    # same, via events
```

## 5. Requests, limits and QoS

```bash
kubectl run <pod> --image=nginx:1.27 --dry-run=client -o yaml | kubectl set resources --local -f - --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi -o yaml > pod.yaml   # generate a Pod with resources
kubectl set resources deploy/<d> --requests=cpu=100m,memory=128Mi --limits=cpu=250m,memory=256Mi   # all containers (rollout)
kubectl set resources deploy/<d> -c=<container> --limits=memory=512Mi                               # one container
kubectl set resources --local -f deploy.yaml --limits=cpu=500m -o yaml > deploy-res.yaml            # edit a file offline
kubectl patch pod <pod> --subresource resize --patch '{"spec":{"containers":[{"name":"<c>","resources":{"requests":{"cpu":"800m"},"limits":{"cpu":"800m"}}}]}}'   # in-place resize (kubectl v1.32+)
kubectl get pod <pod> -o jsonpath='{.status.qosClass}{"\n"}'       # QoS class of one Pod
kubectl get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass   # QoS of all Pods
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources}{"\n"}'     # declared requests/limits
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'   # OOMKilled?
kubectl describe pod <pod> | grep -A5 'Last State'                 # exit code 137 / OOMKilled
kubectl top pod -n <ns> --containers                               # live usage (needs metrics-server)
kubectl top node                                                   # node usage
kubectl describe node <node> | grep -A8 'Allocated resources'      # requested vs allocatable on a node
kubectl get pods -A --field-selector=status.phase=Pending          # Pods that did not schedule
```

## 6. ResourceQuota and LimitRange

```bash
kubectl create quota <q> -n <ns> --hard=requests.cpu=2,requests.memory=2Gi,limits.cpu=4,limits.memory=4Gi,pods=10   # compute quota
kubectl create quota <q> -n <ns> --hard=configmaps=10,secrets=10,services=5,count/deployments.apps=5               # object counts
kubectl create quota <q> -n <ns> --hard=requests.storage=20Gi,persistentvolumeclaims=4                              # storage
kubectl create quota <q> -n <ns> --hard=pods=3 --scopes=BestEffort                                                  # scoped quota
kubectl create quota <q> -n <ns> --hard=cpu=1,memory=1Gi --dry-run=client -o yaml > quota.yaml                      # generate YAML
kubectl get resourcequota -n <ns>                                  # short name: quota
kubectl describe quota -n <ns>                                     # Used vs Hard
kubectl get quota <q> -n <ns> -o jsonpath='{.status.used}{"\n"}'   # usage as JSON
kubectl edit quota <q> -n <ns>                                     # change hard limits
kubectl apply -f limitrange.yaml                                   # no imperative generator for LimitRange
kubectl get limitrange -n <ns>                                     # short name: limits
kubectl describe limitrange <lr> -n <ns>                           # Min/Max/Default Request/Default Limit per type
kubectl run lr-test -n <ns> --image=nginx:1.27 && kubectl get pod lr-test -n <ns> -o jsonpath='{.spec.containers[0].resources}{"\n"}'   # see defaults applied
kubectl rollout restart deploy/<d> -n <ns>                         # re-create Pods so new defaults apply
```

## 7. ConfigMaps

```bash
kubectl create configmap <cm> --from-literal=KEY1=v1 --from-literal=KEY2=v2      # literals
kubectl create configmap <cm> --from-file=app.properties                         # key = file name
kubectl create configmap <cm> --from-file=<key>=path/to/file                     # custom key
kubectl create configmap <cm> --from-file=dir/                                   # one key per regular file
kubectl create configmap <cm> --from-env-file=app.env                            # one key per KEY=VALUE line
kubectl create configmap <cm> --from-literal=K=v --dry-run=client -o yaml > cm.yaml   # generate YAML
kubectl create configmap <cm> --from-file=app.properties --dry-run=client -o yaml | kubectl apply -f -   # update in place
kubectl create configmap <cm> --from-literal=K=v --append-hash                   # name with content hash suffix
kubectl edit configmap <cm>                                        # edit values
kubectl patch configmap <cm> --type=merge -p '{"data":{"K":"new"}}'   # patch one key
kubectl get cm                                                     # list ConfigMaps
kubectl describe cm <cm>                                           # keys and values
kubectl get cm <cm> -o jsonpath='{.data.K}{"\n"}'                  # one value
kubectl get cm <cm> -o jsonpath='{.data.app\.properties}'          # key containing dots
kubectl set env deploy/<d> --from=configmap/<cm>                   # all keys as env (configMapKeyRef each)
kubectl set env deploy/<d> --from=configmap/<cm> --keys=K1,K2 --prefix=APP_   # selected keys with prefix
kubectl rollout restart deploy/<d>                                 # env consumers pick up changes
kubectl exec <pod> -- ls -la /etc/config                           # mounted keys (symlinks into ..data)
kubectl exec <pod> -- cat /etc/config/<key>                        # file content
kubectl delete cm <cm>                                             # delete
```

## 8. Secrets

```bash
kubectl create secret generic <s> --from-literal=username=admin --from-literal=password='S3cr3t!'   # Opaque from literals
kubectl create secret generic <s> --from-file=password=./pass.txt                                  # from a file (custom key)
kubectl create secret generic <s> --from-env-file=secret.env                                       # from an env-file
kubectl create secret generic <s> --type=kubernetes.io/basic-auth --from-literal=username=u --from-literal=password=p   # typed generic
kubectl create secret generic <s> --type=kubernetes.io/ssh-auth --from-file=ssh-privatekey=$HOME/.ssh/id_ed25519      # SSH key
kubectl create secret generic <s> --from-literal=k=v --dry-run=client -o yaml > secret.yaml        # generate YAML
kubectl create secret tls <s> --cert=tls.crt --key=tls.key                                         # TLS Secret
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=<host>"   # self-signed cert for practice
kubectl create secret docker-registry <s> --docker-server=<reg> --docker-username=<u> --docker-password=<p> --docker-email=<e>   # registry creds
kubectl create secret docker-registry <s> --from-file=.dockerconfigjson=$HOME/.docker/config.json  # from an existing docker config
kubectl get secrets                                                # TYPE and number of keys
kubectl describe secret <s>                                        # key names and byte sizes only
kubectl get secret <s> -o jsonpath='{.data.password}' | base64 -d; echo          # decode one key
kubectl get secret <s> -o jsonpath='{.data.password}' | base64 -d > /opt/course/x/pw.txt   # decode into a file
kubectl get secret <s> -o go-template='{{.data.password | base64decode}}{{"\n"}}'           # decode without base64 tool
kubectl get secret <s> -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'   # decode all keys
kubectl get secret <s> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate   # inspect a TLS cert
kubectl get secret <s> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d; echo           # inspect registry creds
echo -n 'value' | base64                                           # encode (no trailing newline!)
echo 'dmFsdWU=' | base64 -d                                        # decode
kubectl patch secret <s> -p '{"stringData":{"password":"N3w"}}'    # update one value with plain text
kubectl set env deploy/<d> --from=secret/<s>                       # all keys as env (secretKeyRef each)
kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"<s>"}]}'   # registry creds for all new Pods using "default"
kubectl delete secret <s>                                          # delete
```

## 9. ServiceAccounts and tokens

```bash
kubectl create serviceaccount <sa> -n <ns>                         # create (short: sa)
kubectl create sa <sa> -n <ns> --dry-run=client -o yaml > sa.yaml  # generate YAML
kubectl get sa -n <ns>                                             # list
kubectl describe sa <sa> -n <ns>                                   # pull secrets, tokens (none since v1.24 is normal)
kubectl set serviceaccount deploy/<d> <sa> -n <ns>                 # change a Deployment's SA (rollout)
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.serviceAccountName}{"\n"}'   # SA used by a Pod
kubectl get pods -n <ns> -o custom-columns=NAME:.metadata.name,SA:.spec.serviceAccountName   # SA of every Pod
kubectl patch sa <sa> -n <ns> -p '{"automountServiceAccountToken": false}'      # disable token automount for the SA
kubectl patch sa <sa> -n <ns> -p '{"imagePullSecrets":[{"name":"regcred"}]}'     # attach a pull secret
kubectl create token <sa> -n <ns>                                  # short-lived token to stdout
kubectl create token <sa> -n <ns> --duration=1h > /opt/course/x/token          # token with lifetime, saved to a file
kubectl create token <sa> -n <ns> --audience=<aud>                 # token for another audience
kubectl create token <sa> -n <ns> --bound-object-kind=Pod --bound-object-name=<pod>   # token dies with the Pod
kubectl get secret <sa>-token -n <ns> -o jsonpath='{.data.token}' | base64 -d   # long-lived token from a manual Secret
kubectl exec -n <ns> <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token   # the Pod's mounted token
kubectl exec -n <ns> <pod> -- sh -c 'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/<ns>/pods'   # call the API as the SA
kubectl auth can-i --list -n <ns> --as=system:serviceaccount:<ns>:<sa>          # what the SA may do
```

## 10. Security contexts and capabilities (verify)

```bash
kubectl run <pod> --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'sleep 3600' > pod.yaml   # generate, then add securityContext
kubectl explain pod.spec.securityContext                           # pod-level fields
kubectl explain pod.spec.containers.securityContext                # container-level fields
kubectl replace --force -f pod.yaml                                # recreate a Pod after changing securityContext
kubectl get pod <pod> -o jsonpath='{.spec.securityContext}{"\n"}'  # applied pod-level settings
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].securityContext}{"\n"}'   # applied container-level settings
kubectl exec <pod> -- id                                           # uid / gid / groups
kubectl exec <pod> -- ps                                           # process owners
kubectl exec <pod> -- grep Cap /proc/1/status                      # capability bitmasks (CapEff = effective)
kubectl exec <pod> -- grep NoNewPrivs /proc/1/status               # 1 = allowPrivilegeEscalation false
kubectl exec <pod> -- grep Seccomp /proc/1/status                  # 2 = seccomp filter active
kubectl exec <pod> -- touch /test                                  # fails on a read-only root filesystem
kubectl exec <pod> -- ls -ld /data                                 # fsGroup ownership of a volume
kubectl exec <pod> -c <container> -- ip addr add 10.200.0.1/32 dev lo   # works only with NET_ADMIN
capsh --decode=00000000a80425fb                                    # decode a bitmask (machine with libcap)
```

## 11. Environment variables and Downward API

```bash
kubectl set env deploy/<d> KEY=value KEY2=value2                   # add/update env vars (rollout)
kubectl set env deploy/<d> -c <container> KEY=value                # one container only
kubectl set env deploy/<d> KEY-                                    # remove a variable
kubectl set env deploy/<d> --list                                  # list declared env
kubectl set env deploy/<d> --list --resolve                        # list incl. resolved ConfigMap/Secret refs
kubectl set env pods --all --list                                  # env of every Pod
kubectl set env deploy/<d> KEY=v --dry-run=client -o yaml          # preview
kubectl run tmp --image=busybox:1.36 --env=A=1 --env=B=2 --rm -it --restart=Never -- env   # quick env test
kubectl exec <pod> -- env | sort                                   # effective environment
kubectl exec <pod> -- printenv KEY                                 # one variable
kubectl exec <pod> -- sh -c 'echo $KEY'                            # expanded inside the container (single quotes)
kubectl exec <pod> -- cat /etc/podinfo/labels                      # downwardAPI volume file
kubectl label pod <pod> version=v2                                 # labels file updates, env does not
kubectl get pod <pod> -o jsonpath='{.spec.containers[0].env}{"\n"}'   # declared env in the spec
```

## 12. Debug by symptom

```bash
kubectl describe pod <pod> | tail -20                              # CreateContainerConfigError: missing ConfigMap/Secret/key, runAsNonRoot
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20     # FailedMount, FailedCreate, quota, PSA
kubectl describe rs -n <ns> -l app=<app>                           # Deployment at 0/N: quota or PodSecurity rejection
kubectl logs <pod> --previous                                      # crash before restart (e.g. read-only fs, permissions)
kubectl logs deploy/<d> | grep -i forbidden                        # app lacks RBAC: check its SA and bindings
kubectl auth can-i <verb> <resource> -n <ns> --as=system:serviceaccount:<ns>:<sa>   # confirm an RBAC theory
kubectl get pod <pod> -o yaml | grep -A10 securityContext          # what was actually applied
kubectl run dbg --rm -it --image=busybox:1.36 --restart=Never -n <ns> -- sh   # throwaway shell in the namespace
```

## 13. Cleanup

```bash
kubectl delete pod <pod> --grace-period=0 --force                  # remove a test Pod immediately
kubectl delete -f yaml/                                            # delete everything created from this folder
kubectl delete role,rolebinding -n <ns> -l <label>                 # RBAC by label
kubectl delete quota,limitrange --all -n <ns>                      # remove namespace policies
kubectl delete cm,secret -n <ns> -l app=<app>                      # config objects by label
kubectl delete namespace <ns>                                      # everything in the namespace
kubectl delete crd crontabs.stable.example.com                     # removes the CRD AND all CronTabs
kubectl label namespace <ns> pod-security.kubernetes.io/enforce-   # remove a PSA label
```
