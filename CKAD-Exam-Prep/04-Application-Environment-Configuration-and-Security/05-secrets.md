# Secrets

**Competency:** *Create & consume Secrets*

**Why it matters / what the exam expects:** very frequent. Create generic, TLS and docker-registry Secrets imperatively; write YAML with `data` (base64) or `stringData`; decode a value into a file; consume Secrets as env vars, `envFrom`, volumes with specific file names and modes, and `imagePullSecrets`. Know the security limits of Secrets.

---

## Core concepts

- A Secret works like a ConfigMap (namespaced, key/value, max **1 MiB**, Pods must be in the same namespace) but is meant for sensitive data and is handled more carefully: values are **base64-encoded** in the API, mounted on **tmpfs**, only sent to nodes that run Pods using them, and excluded from the `view` role.
- **base64 is an encoding, not encryption.** Anyone who can read the Secret object can read the value.

### Types

| `type` | Required keys | Created with |
|---|---|---|
| `Opaque` (default) | Any | `kubectl create secret generic` |
| `kubernetes.io/tls` | `tls.crt`, `tls.key` | `kubectl create secret tls --cert --key` |
| `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` (valid JSON) | `kubectl create secret docker-registry` |
| `kubernetes.io/dockercfg` | `.dockercfg` (legacy format) | YAML |
| `kubernetes.io/basic-auth` | `username` and/or `password` | `generic --type=kubernetes.io/basic-auth` or YAML |
| `kubernetes.io/ssh-auth` | `ssh-privatekey` | `generic --type=kubernetes.io/ssh-auth` or YAML |
| `kubernetes.io/service-account-token` | filled in by the control plane; needs annotation `kubernetes.io/service-account.name` | YAML ([06](06-serviceaccounts.md)) |
| `bootstrap.kubernetes.io/token` | `token-id`, `token-secret`, ... in `kube-system`, named `bootstrap-token-<id>` | kubeadm |

The API server checks that a built-in type has its required keys; it does not check that a TLS key is valid (kubectl does check the cert/key pair when you use `kubectl create secret tls`).

### `data` vs `stringData`

| Field | You write | API returns | Notes |
|---|---|---|---|
| `data` | base64 values | base64 values | Must be valid base64 |
| `stringData` | plain text | **never** (merged into `data`) | Write-only convenience; wins over `data` for the same key |

### Consumption

| Mode | Pod spec | Updates live? |
|---|---|---|
| One env var | `env[].valueFrom.secretKeyRef {name, key, optional}` | No |
| All keys as env | `envFrom[].secretRef {name, optional}` (+ `prefix`) | No |
| Volume | `volumes[].secret {secretName, items, defaultMode, optional}` | Yes, eventually (not with `subPath`) |
| Projected volume | `projected.sources[].secret {name, items}` | Yes, eventually |
| Image pulls | `spec.imagePullSecrets[].name` or the ServiceAccount's `imagePullSecrets` | Used at pull time |
| Other objects | Ingress `spec.tls[].secretName`, Gateway listeners, operators | - |

Missing Secret or key (not `optional`): env -> `CreateContainerConfigError`; volume -> Pod stuck `ContainerCreating` with a `FailedMount` event.

---

## Key fields / syntax

Files: [yaml/secret-opaque.yaml](yaml/secret-opaque.yaml), [yaml/secret-stringdata.yaml](yaml/secret-stringdata.yaml), [yaml/pod-secret-env.yaml](yaml/pod-secret-env.yaml), [yaml/pod-secret-volume.yaml](yaml/pod-secret-volume.yaml), [yaml/pod-projected-volume.yaml](yaml/pod-projected-volume.yaml), [yaml/pod-imagepullsecrets.yaml](yaml/pod-imagepullsecrets.yaml), [yaml/secret-tls-example.yaml](yaml/secret-tls-example.yaml).

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  username: YWRtaW4=                 # echo -n 'admin' | base64
stringData:
  password: S3cr3t-Passw0rd          # plain text, encoded by the API server
```

```yaml
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
    envFrom:
    - secretRef:
        name: app-api-keys
    volumeMounts:
    - name: db-creds
      mountPath: /etc/db
      readOnly: true
  volumes:
  - name: db-creds
    secret:
      secretName: db-credentials     # secretName, not name
      defaultMode: 0400              # octal; files readable by the owner only
      items:
      - key: password
        path: db-password            # -> /etc/db/db-password
  imagePullSecrets:
  - name: regcred
```

With `defaultMode: 0400` and a non-root container user, add `fsGroup` (and use `0440`) so the process can read the files - see [07](07-security-contexts-and-capabilities.md).

---

## Imperative commands

```bash
# --- generic (Opaque) ---
kubectl create secret generic db-credentials --from-literal=username=admin --from-literal=password='S3cr3t-Passw0rd'
kubectl create secret generic db-credentials --from-file=username=./user.txt --from-file=password=./pass.txt
kubectl create secret generic app-files --from-file=./secrets-dir/            # one key per file
kubectl create secret generic app-env --from-env-file=secret.env              # one key per KEY=VALUE line
kubectl create secret generic basic --type=kubernetes.io/basic-auth --from-literal=username=u --from-literal=password=p
kubectl create secret generic ssh-key --type=kubernetes.io/ssh-auth --from-file=ssh-privatekey=$HOME/.ssh/id_ed25519
kubectl create secret generic db-credentials --from-literal=password=x --dry-run=client -o yaml > secret.yaml

# --- TLS ---
# openssl is for your own lab: exam hosts only guarantee kubectl, yq, curl, wget and man,
# and TLS tasks normally hand you the cert/key files.
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=app.example.com"
kubectl create secret tls app-tls --cert=tls.crt --key=tls.key

# --- docker-registry (type kubernetes.io/dockerconfigjson, key .dockerconfigjson) ---
kubectl create secret docker-registry regcred --docker-server=registry.example.com \
  --docker-username=demo-user --docker-password='REPLACE-ME' --docker-email=demo@example.com
kubectl create secret docker-registry regcred --from-file=.dockerconfigjson=$HOME/.docker/config.json
kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"regcred"}]}'   # all new Pods using "default"

# --- decode ---
kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d > /opt/course/5/password.txt
kubectl get secret db-credentials -o go-template='{{.data.password | base64decode}}{{"\n"}}'
kubectl get secret db-credentials -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'
kubectl get secret app-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate
kubectl get secret regcred -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d; echo

# --- encode by hand ---
echo -n 'admin' | base64                    # YWRtaW4=   (-n: no trailing newline!)
printf '%s' 'admin' | base64                # same
base64 -w0 < tls.crt                        # no line wrapping (GNU) for long values

# --- update / rotate ---
kubectl create secret generic db-credentials --from-literal=username=admin --from-literal=password='N3w-Pass' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl patch secret db-credentials -p '{"stringData":{"password":"N3w-Pass"}}'
kubectl rollout restart deploy/web          # env-var consumers need a restart

# --- consume imperatively / inspect ---
kubectl set env deploy/web --from=secret/db-credentials            # one secretKeyRef per key
kubectl set env deploy/web --from=secret/db-credentials --keys=password --prefix=DB_
kubectl get secrets                          # TYPE and DATA (number of keys)
kubectl describe secret db-credentials       # key names and sizes only, never values
kubectl exec secret-volume-demo -- cat /etc/db/db-password
```

---

## Exam traps & tips

> **Exam tip:** `echo 'admin' | base64` gives `YWRtaW4K` = `admin` **plus a newline**, and the app's login fails. Always `echo -n` (or `printf '%s'`). The same applies to files used with `--from-file`: `echo admin > pass.txt` stores the newline too.

> **Exam tip:** "write the decoded value to a file" -> `kubectl get secret <s> -n <ns> -o jsonpath='{.data.<key>}' | base64 -d > <file>`. Keys with dots need escaping: `{.data.tls\.crt}`.

> **Exam tip:** `kubectl describe secret` never shows values; use `-o jsonpath` + `base64 -d`, or the `base64decode` go-template function.

> **Exam tip:** Secret volume = `secret.secretName`; ConfigMap volume = `configMap.name`. Mixing them up is a common apply error.

> **Exam tip:** `kubectl create secret docker-registry` produces type `kubernetes.io/dockerconfigjson`. Pods reference it in `spec.imagePullSecrets` (a list of `{name: ...}`), **not** in containers.

- Imperative `--from-literal` values with special characters: wrap in single quotes (`'p@ss$word!'`).
- Secrets and the Pods/Ingresses that use them must be in the **same namespace**.
- Changing a Secret never restarts Pods; env vars keep the old value until a restart.
- `stringData` is never returned by `kubectl get -o yaml` - look under `data`.
- Patching the default ServiceAccount's `imagePullSecrets` affects only Pods created afterwards.

---

## Encryption at rest (awareness)

By default Secrets are stored **unencrypted** in etcd. The cluster admin enables encryption with an `EncryptionConfiguration` file passed to the API server via `--encryption-provider-config` (static Pod manifest on kubeadm, plus a volume mount for the file).

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:                          # first provider = used for new writes
      keys:
      - name: key1
        secret: <BASE64-ENCODED-32-BYTE-KEY>   # head -c 32 /dev/urandom | base64
  - identity: {}                     # still able to read data written before encryption
```

Existing Secrets are only encrypted when rewritten: `kubectl get secrets -A -o json | kubectl replace -f -`. In production prefer the **KMS v2** provider (GA v1.29) so the key lives in an external KMS, not on the control-plane disk.

---

## Architect notes

- **Threat model first:** Secrets are readable by anyone with `get`/`list`/`watch` on secrets in the namespace, by anyone who can **create Pods** there (they can mount any Secret), by the `edit`/`admin` roles, by nodes running consuming Pods, by etcd readers and by whoever holds etcd backups.
- **Enable encryption at rest** (KMS v2 preferred), restrict etcd access, and encrypt and protect etcd backups.
- **Least-privilege RBAC:** apps rarely need to read Secrets through the API; if they do, use `resourceNames`. Remember that `list` returns full contents.
- **Prefer files over env vars** for sensitive values: env vars leak through `/proc/<pid>/environ`, crash dumps, debug endpoints and child processes. Mount with `0400`/`0440` plus `fsGroup`.
- **External secret managers** keep the source of truth outside the cluster: External Secrets Operator (syncs from Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault into Secrets), Secrets Store CSI Driver (mounts directly, optional sync), Vault Agent injection.
- **GitOps:** never commit plain Secrets; use Sealed Secrets or SOPS-encrypted manifests, or reference external stores.
- **Rotation:** design apps to reload mounted files, or use versioned immutable Secrets plus a rollout; set expiry/rotation policies for registry credentials and TLS (cert-manager renews TLS Secrets automatically).
- Use `immutable: true` for Secrets that should never change in place (prevents accidental edits, reduces API watch load).

---

## Docs to bookmark

- https://kubernetes.io/docs/concepts/configuration/secret/
- https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/
- https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-config-file/
- https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/
- https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
- https://kubernetes.io/docs/concepts/security/secrets-good-practices/
- https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
- https://kubernetes.io/docs/reference/kubectl/quick-reference/ (go-template `base64decode` one-liner)

---

## Quick self-check

1. What is wrong with `echo 'P@ss' | base64` for a Secret value?
2. Give the command that writes the decoded `password` key of Secret `db` in namespace `shop` to `/tmp/pw.txt`.
3. Which Secret type and key does `kubectl create secret docker-registry` produce, and where is it referenced?
4. How do you mount only the key `password` of Secret `db` as `/etc/creds/pw` with mode `0400`?
5. Who can read a Secret's value besides users with `get secrets`?

<details><summary>Answers</summary>

1. `echo` adds a trailing newline, so the stored value is `P@ss\n`. Use `echo -n` or `printf '%s'`.
2. `kubectl get secret db -n shop -o jsonpath='{.data.password}' | base64 -d > /tmp/pw.txt`.
3. Type `kubernetes.io/dockerconfigjson`, key `.dockerconfigjson`; referenced in `spec.imagePullSecrets` of the Pod (or in the ServiceAccount's `imagePullSecrets`).
4. `volumes: [{name: creds, secret: {secretName: db, defaultMode: 0400, items: [{key: password, path: pw}]}}]` and a `volumeMount` with `mountPath: /etc/creds`.
5. Anyone who can create Pods in the namespace (mount it), anyone with `list`/`watch` on secrets, the `edit`/`admin` roles, nodes running Pods that use it, and anyone with access to etcd or its backups (unless encrypted at rest).

</details>
