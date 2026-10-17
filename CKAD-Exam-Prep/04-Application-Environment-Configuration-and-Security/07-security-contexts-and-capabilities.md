# Security Contexts and Capabilities

**Competency:** *Understand Application Security (SecurityContexts, Capabilities, etc.)*

**Why it matters / what the exam expects:** set the user/group a container runs as, `fsGroup` for volumes, add or drop Linux capabilities (`NET_ADMIN`, `SYS_TIME`, `drop: ["ALL"]`), disable privilege escalation, make the root filesystem read-only (with writable `emptyDir` paths), and make a Pod pass the **restricted** Pod Security Standard. You must know **which field goes at which level** - a field at the wrong level is rejected as an unknown field.

---

## Core concepts

### Where each field is allowed, and who wins

`spec.securityContext` (PodSecurityContext) sets defaults for all containers plus volume settings; `spec.containers[].securityContext` (SecurityContext) applies to one container. **For a field available at both levels, the container value wins.**

| Field | Pod level | Container level | Notes |
|---|---|---|---|
| `runAsUser` | Yes | Yes | Container wins |
| `runAsGroup` | Yes | Yes | Primary GID; if unset the GID is 0 (root group) |
| `runAsNonRoot` | Yes | Yes | Kubelet refuses to start a container that would run as UID 0 |
| `seccompProfile` | Yes | Yes | `RuntimeDefault`, `Localhost`, `Unconfined` |
| `appArmorProfile` | Yes | Yes | Field is GA since v1.30 (replaces the annotation) |
| `seLinuxOptions` | Yes | Yes | `user`, `role`, `type`, `level` |
| `windowsOptions` | Yes | Yes | Windows nodes only |
| `fsGroup` | **Yes** | No | Group owner of supported volumes; added to every process's groups |
| `fsGroupChangePolicy` | **Yes** | No | `Always` (default) or `OnRootMismatch` |
| `supplementalGroups` | **Yes** | No | Extra GIDs for all processes |
| `supplementalGroupsPolicy` | **Yes** | No | `Merge` (default) or `Strict`; beta since v1.33 |
| `sysctls` | **Yes** | No | Namespaced kernel parameters |
| `privileged` | No | **Yes** | Full host access - avoid |
| `allowPrivilegeEscalation` | No | **Yes** | `false` sets `no_new_privs` |
| `capabilities` | No | **Yes** | `add` / `drop` lists |
| `readOnlyRootFilesystem` | No | **Yes** | Container image filesystem mounted read-only |
| `procMount` | No | **Yes** | `Default` or `Unmasked` |

Security-related fields that are **not** in `securityContext` but directly in the Pod spec: `hostNetwork`, `hostPID`, `hostIPC`, `shareProcessNamespace`, `hostUsers`, `automountServiceAccountToken`.

### Users and groups

- `runAsUser` / `runAsGroup` set the process UID/GID; image `USER` is used when they are unset.
- `runAsNonRoot: true` makes the kubelet verify the effective UID is not 0. With an image that runs as root and no `runAsUser`, the container fails with `CreateContainerConfigError: container has runAsNonRoot and image will run as root`. With a non-numeric image user (e.g. `USER nginx`) it fails with `image has non-numeric user (nginx), cannot verify user is non-root` - set a numeric `runAsUser`.
- `fsGroup`: supported volumes (emptyDir, most PVCs/CSI drivers, configMap/secret/projected) are made group-owned by this GID with the setgid bit, and new files get this group. `hostPath` is not changed. `fsGroupChangePolicy: OnRootMismatch` skips the recursive `chown` when the volume root already matches - much faster start-up for large volumes.
- `supplementalGroups` adds GIDs; with the default `Merge` policy, groups defined for the user in the image's `/etc/group` are also added (`Strict` prevents that).

### Privilege controls

| Field | Effect |
|---|---|
| `privileged: true` | All capabilities, access to host devices, no seccomp/AppArmor confinement - effectively root on the node. Forbidden by `baseline` |
| `allowPrivilegeEscalation: false` | Sets the `no_new_privs` flag: setuid binaries (e.g. `sudo`) and file capabilities cannot raise privileges. Implicitly `true` when `privileged: true` or with `CAP_SYS_ADMIN`; the API rejects `privileged: true` together with `allowPrivilegeEscalation: false` |
| `readOnlyRootFilesystem: true` | Writes to the image filesystem fail with `Read-only file system`; mount `emptyDir` volumes for paths that must be writable (`/tmp`, caches, pid files) |

### Linux capabilities

Root's powers are split into capabilities. The container runtime grants a default set (containerd/Docker: CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, SETGID, SETUID, SETPCAP, NET_BIND_SERVICE, NET_RAW, SYS_CHROOT, MKNOD, AUDIT_WRITE, SETFCAP). You `drop` and `add` relative to it. Names in YAML have **no `CAP_` prefix**.

| Capability | Allows | Typical use / note |
|---|---|---|
| `NET_BIND_SERVICE` | Bind ports below 1024 | The only capability `restricted` allows to add back |
| `NET_ADMIN` | Configure interfaces, routes, iptables in the Pod's network namespace | Service-mesh / VPN init containers |
| `NET_RAW` | Raw sockets (`ping`) | In the default set; drop it to prevent spoofing |
| `SYS_TIME` | Set the system clock | The clock is **not namespaced** - it changes the node's time |
| `CHOWN` | Change file ownership | Entrypoints that `chown` directories |
| `KILL` | Signal processes of other users | Process supervisors |
| `SYS_PTRACE` | Trace/inspect other processes | Debugging (with `shareProcessNamespace`) |
| `SYS_ADMIN` | Mounts and many admin operations ("the new root") | Avoid |

Important nuance: added capabilities become **effective for root (UID 0) processes**. A non-root process does not get them in its effective set (Kubernetes does not set ambient capabilities); such binaries need file capabilities (`setcap`) in the image, or use an alternative such as the safe sysctl `net.ipv4.ip_unprivileged_port_start`.

### seccomp, AppArmor, SELinux, sysctls

| Mechanism | Field | Values |
|---|---|---|
| seccomp (syscall filter) | `seccompProfile.type` | `RuntimeDefault` (runtime's default filter), `Localhost` + `localhostProfile: profiles/x.json` (relative to the kubelet's `/var/lib/kubelet/seccomp`), `Unconfined`. Without a profile Pods run `Unconfined` unless the kubelet runs with `--seccomp-default` |
| AppArmor | `appArmorProfile.type` | `RuntimeDefault`, `Localhost` + `localhostProfile: <profile-name>` (must be loaded on the node), `Unconfined`. The old `container.apparmor.security.beta.kubernetes.io/<container>` annotation is deprecated |
| SELinux | `seLinuxOptions` | `level: "s0:c123,c456"`, `type: container_t`, ... |
| sysctls (Pod level) | `sysctls: [{name, value}]` | Safe set allowed by default (e.g. `net.ipv4.ip_local_port_range`, `net.ipv4.ip_unprivileged_port_start`, `kernel.shm_rmid_forced`); unsafe ones need the kubelet flag `--allowed-unsafe-sysctls` |

### User namespaces (`hostUsers: false`)

With `spec.hostUsers: false` the container's UIDs/GIDs are mapped to an unprivileged range on the host, so root in the container is not root on the node. Beta (on by default) in v1.33-v1.35 and **stable since v1.36** (so part of v1.37), but it still needs node support: Linux 6.3+ and a recent runtime (containerd 2.0+ or CRI-O 1.25+, with runc 1.2+ or crun 1.9+). Check feature state for your cluster version before relying on it.

```yaml
spec:
  hostUsers: false
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
```

---

## Key fields / syntax

Files: [yaml/pod-securitycontext.yaml](yaml/pod-securitycontext.yaml), [yaml/pod-capabilities.yaml](yaml/pod-capabilities.yaml), [yaml/pod-readonly-rootfs.yaml](yaml/pod-readonly-rootfs.yaml), [yaml/pod-restricted-compliant.yaml](yaml/pod-restricted-compliant.yaml), [yaml/namespace-pod-security-labels.yaml](yaml/namespace-pod-security-labels.yaml).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
spec:
  securityContext:                   # POD level
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    supplementalGroups: [4000]
    seccompProfile:
      type: RuntimeDefault
    sysctls:
    - name: net.ipv4.ip_unprivileged_port_start
      value: "0"                     # lets non-root processes bind low ports in this Pod
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    securityContext:                 # CONTAINER level
      runAsUser: 1001                # overrides 1000 for this container only
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
        add: ["NET_BIND_SERVICE"]
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

### Restricted-profile-compliant template

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-demo
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "id; sleep 3600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

That is the minimum for `restricted`; the full file adds `readOnlyRootFilesystem`, resources and an `emptyDir`. The image must be able to run as a non-root UID - `nginx:1.27`, for example, expects root (it binds port 80 and writes to root-owned paths), so it fails under `restricted` unless you switch to an unprivileged image variant.

---

## Imperative commands

`kubectl run` and `kubectl create` have no securityContext flags - generate YAML and edit:

```bash
kubectl run secure-app --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'sleep 3600' > pod.yaml
vi pod.yaml                                   # add spec.securityContext / containers[].securityContext
kubectl apply -f pod.yaml
kubectl replace --force -f pod.yaml           # securityContext of a running Pod is immutable: recreate
kubectl create deployment web --image=nginx:1.27 --dry-run=client -o yaml > web.yaml   # edit template.spec

# Verify what was applied
kubectl get pod secure-app -o jsonpath='{.spec.securityContext}{"\n"}'
kubectl get pod secure-app -o jsonpath='{.spec.containers[0].securityContext}{"\n"}'
kubectl explain pod.spec.securityContext                  # pod-level fields
kubectl explain pod.spec.containers.securityContext       # container-level fields
```

### Verification inside the container

| Check | Command | Expected |
|---|---|---|
| Identity | `kubectl exec <pod> -- id` | `uid=1000 gid=3000 groups=2000,3000,4000` (docs example with fsGroup 2000, supplementalGroups 4000) |
| Process owner | `kubectl exec <pod> -- ps` | busybox shows the UID (e.g. `1000`) in the USER column |
| Capabilities | `kubectl exec <pod> -- grep Cap /proc/1/status` | `CapEff` bitmask, see below |
| no_new_privs | `kubectl exec <pod> -- grep NoNewPrivs /proc/1/status` | `NoNewPrivs: 1` when `allowPrivilegeEscalation: false` |
| seccomp | `kubectl exec <pod> -- grep Seccomp /proc/1/status` | `Seccomp: 2` (filter active) for RuntimeDefault/Localhost; `0` = unconfined |
| Read-only root | `kubectl exec <pod> -- touch /test` | `touch: /test: Read-only file system` |
| Writable emptyDir | `kubectl exec <pod> -- touch /tmp/ok` | Succeeds |
| fsGroup on a volume | `kubectl exec <pod> -- ls -ld /data/demo` | Group `2000`, setgid bit (`drwxrwsrwx`) |
| A capability works | `kubectl exec <pod> -- ip addr add 10.200.0.1/32 dev lo` | Works with NET_ADMIN; `Operation not permitted` without |

`CapEff` values you will see: `00000000a80425fb` = the runtime default set (root container); `0000000000000000` = nothing (`drop: ["ALL"]`, or a non-root process); `0000000000001000` = `NET_ADMIN` only; `0000000002000000` = `SYS_TIME` only; `0000000000000400` = `NET_BIND_SERVICE` only. Decode on a machine with libcap: `capsh --decode=00000000a80425fb`.

---

## Exam traps & tips

> **Exam tip:** `fsGroup`, `supplementalGroups`, `sysctls` are **Pod-level only**; `capabilities`, `privileged`, `allowPrivilegeEscalation`, `readOnlyRootFilesystem` are **container-level only**. Wrong placement fails with `unknown field "spec.containers[0].securityContext.fsGroup"` (or similar).

> **Exam tip:** capability names are written without `CAP_`: `add: ["NET_ADMIN", "SYS_TIME"]`, not `CAP_NET_ADMIN`.

> **Exam tip:** "The container must run as user 1000 and group 3000, files on the volume owned by group 2000" -> pod-level `runAsUser: 1000`, `runAsGroup: 3000`, `fsGroup: 2000`.

> **Exam tip:** securityContext changes on a bare Pod require recreating it: `kubectl get pod x -o yaml > x.yaml`, edit, `kubectl replace --force -f x.yaml`. On a Deployment, edit the template (rollout).

> **Exam tip:** after enabling `readOnlyRootFilesystem`, check the Pod actually runs. If it crashes, `kubectl logs` shows which path needs an `emptyDir` (`/tmp`, `/var/cache/...`, `/var/run`).

- `runAsNonRoot: true` alone does not change the user; it only **checks**. Combine it with `runAsUser` for images that default to root.
- `privileged: true` + `allowPrivilegeEscalation: false` is rejected by validation.
- Do not test `SYS_TIME` with `date -s` on a shared lab node - it changes the node's clock.
- `drop: ["ALL"]` then `add: [...]` is the pattern; adding capabilities to a non-root process does not make them effective.
- Pod Security Admission `restricted` also requires an explicit `seccompProfile` - easy to forget.

---

## Architect notes

- **Secure by default:** non-root, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem: true`. Bake it into Helm/Kustomize bases so teams inherit it.
- **Build images for it:** numeric `USER` in the Dockerfile, writable directories owned by that user, listen on high ports (8080/8443), minimal or distroless bases.
- **Enforce, then exempt deliberately:** PSA `restricted` on application namespaces; node agents and CNI/CSI components live in dedicated namespaces labelled `privileged` or `baseline`.
- Turn on the kubelet's `--seccomp-default` so even unlabeled workloads get `RuntimeDefault`.
- **User namespaces** (`hostUsers: false`) add strong defense in depth against container breakouts; adopt as node kernels and runtimes allow.
- Avoid `privileged`, `hostPath`, `hostNetwork`, `hostPID`; if an exception is needed, document it and constrain it with admission policy.
- Use `fsGroupChangePolicy: OnRootMismatch` for large persistent volumes to avoid slow Pod starts.
- Layer runtime protection where risk justifies it: AppArmor/SELinux profiles, runtime detection (e.g. Falco), sandboxed runtimes via RuntimeClass (gVisor, Kata) for untrusted code, signed images verified at admission.

---

## Docs to bookmark

- https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ (users, fsGroup, capabilities, seccomp, AppArmor, SELinux examples)
- https://kubernetes.io/docs/concepts/security/pod-security-standards/
- https://kubernetes.io/docs/concepts/security/linux-kernel-security-constraints/
- https://kubernetes.io/docs/tutorials/security/seccomp/
- https://kubernetes.io/docs/tutorials/security/apparmor/
- https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/
- https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/
- https://kubernetes.io/docs/reference/kubernetes-api/core/pod-v1/ (PodSecurityContext / SecurityContext field reference)

---

## Quick self-check

1. Which of these are valid at container level: `fsGroup`, `capabilities`, `runAsUser`, `sysctls`, `readOnlyRootFilesystem`?
2. Pod level sets `runAsUser: 1000`; container level sets `runAsUser: 2000`. Which UID does the container use?
3. A container with `runAsNonRoot: true` (image runs as root, no `runAsUser`) does not start. What is the error and the fix?
4. Write the container securityContext that removes all capabilities and adds only `NET_ADMIN` and `SYS_TIME`.
5. How do you prove inside a Pod that privilege escalation is disabled?
6. Which four settings does the `restricted` profile require beyond `baseline`, for a typical Pod?

<details><summary>Answers</summary>

1. `capabilities`, `runAsUser` and `readOnlyRootFilesystem`. (`fsGroup` and `sysctls` are pod-level only.)
2. 2000 - the container-level value wins.
3. `CreateContainerConfigError: container has runAsNonRoot and image will run as root`. Set a non-zero `runAsUser` (pod or container level) or use an image with a numeric non-root `USER`.
4. `securityContext: {capabilities: {drop: ["ALL"], add: ["NET_ADMIN", "SYS_TIME"]}}`.
5. `grep NoNewPrivs /proc/1/status` shows `NoNewPrivs: 1`.
6. `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, and `seccompProfile.type: RuntimeDefault` (or `Localhost`); also only the allowed volume types and no `runAsUser: 0`.

</details>
