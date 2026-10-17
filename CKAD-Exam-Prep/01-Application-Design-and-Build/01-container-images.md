# Container Images: Define, Build and Modify

**Why it matters:** *"Define, build and modify container images"* is an official competency. Expect one task where you **edit a Dockerfile**, **build** it with podman or docker, **tag** it, and then **push** it to a registry or **save** it as a tarball at an exact path, sometimes in **OCI format**. The image concepts (ENTRYPOINT/CMD → `command`/`args`, `imagePullPolicy`) also come up in almost every Pod task.

What the exam expects you to do from memory:

- read and change a Dockerfile (`FROM` tag, `ENV`, `COPY`, `USER`, `CMD`/`ENTRYPOINT`);
- run `build`, `tag`, `push`, `save` (docker-archive **and** OCI), `load`, `images`, `inspect`, `history`, `run`, `logs` and `ps` with **podman and docker**. The syntax is almost identical.
- predict what runs when a Pod overrides `command`/`args`;
- know the `imagePullPolicy` defaults and how to use a private registry.

> **Exam tip:** Docker and Podman docs are **not** on the allowed-docs list (see [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md)). Learn the commands below; in the exam rely on `podman build --help`, `docker save --help` and `man podman-save`. Use `sudo` if the task environment requires it.

> **Exam tip:** podman/docker are not on the guaranteed exam tool list. A task that needs them provides them on its host. **Check first** with `which podman docker`, then use the tool the task names, or whichever one is installed. Every command below is shown for both.

---

## Core concepts

### What an image is

| Part | Content |
|---|---|
| **Layers** | ordered, read-only filesystem diffs (tar). One layer per filesystem-changing instruction (`RUN`, `COPY`, `ADD`) |
| **Config** | ENTRYPOINT, CMD, ENV, USER, WORKDIR, ExposedPorts, Labels, StopSignal, Volumes, (Healthcheck in Docker format) |
| **Manifest** | references the config + layers by digest. A multi-arch image adds an **index** (manifest list) that points to one manifest per platform |
| **Tag** | mutable, human-friendly pointer (`1.27`, `v2`, `latest`) |
| **Digest** | `sha256:<64 hex>` hash of the manifest: **immutable**, identifies exact content |

At runtime a container gets a thin writable layer on top. The image itself never changes.

### Image references

`[registry[:port]/][namespace/]repository[:tag][@digest]`

| You write | Means |
|---|---|
| `nginx:1.27` | `docker.io/library/nginx:1.27` |
| `nginx` | `docker.io/library/nginx:latest` (implicit `latest`) |
| `myteam/api:1.4.2` | `docker.io/myteam/api:1.4.2` |
| `registry.k8s.io/pause:3.10` | registry `registry.k8s.io`, repository `pause`, tag `3.10` |
| `localhost:5000/team/app:v2` | registry on localhost port 5000 |
| `nginx@sha256:<digest>` | exact content (if tag and digest are both given, **only the digest is used**) |
| `localhost/app:v1` | what **podman** calls an image you built as `app:v1` and never pushed |

Rules: repository names are **lowercase**. A tag matches `[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}`. Kubernetes assumes Docker Hub when no registry is given and `latest` when no tag is given.

### Dockerfile instruction reference

| Instruction | What it does | Example | Gotchas |
|---|---|---|---|
| `FROM` | base image, starts a build stage; `AS name` names the stage | `FROM nginx:1.27-alpine AS web` | pin a tag/digest; `FROM scratch` = empty image |
| `ARG` | build-time variable, set with `--build-arg K=V` | `ARG VERSION=1.0` | not in the container env; an ARG before the first `FROM` works only in `FROM` lines; must be re-declared in every stage; shows in `history`, so never use it for secrets |
| `ENV` | env var for later build steps **and** runtime | `ENV PORT=8080` | stored in the image config; the Pod `env` overrides it |
| `RUN` | runs a command at build time and creates a new layer | `RUN apk add --no-cache curl` | chain with `&&` and clean up in the **same** RUN |
| `COPY` | copies from the build context (or `--from=<stage\|image>`) | `COPY --chown=10001:10001 app/ /app/` | source must be inside the context; respects `.dockerignore` |
| `ADD` | COPY + remote URLs + **auto-extracts local tar archives** | `ADD rootfs.tar.gz /` | prefer `COPY` unless you need the extraction |
| `WORKDIR` | sets the cwd (creates it if missing) | `WORKDIR /app` | use it instead of `RUN cd ...` (each RUN is a new shell) |
| `USER` | user[:group] for later RUN / ENTRYPOINT / CMD | `USER 10001:10001` | use a **numeric** UID so `runAsNonRoot` can be verified |
| `EXPOSE` | documents a port | `EXPOSE 8080/tcp` | publishes nothing; Kubernetes ignores it |
| `LABEL` | metadata | `LABEL org.opencontainers.image.version="1.0"` | visible in `inspect` |
| `VOLUME` | marks a mount point | `VOLUME /data` | later build changes inside it are discarded; Kubernetes creates **no** volume from it, so declare a Kubernetes volume instead |
| `HEALTHCHECK` | health command for docker/podman | `HEALTHCHECK CMD wget -qO- localhost:8080 \|\| exit 1` | **ignored by Kubernetes** (use probes); podman's default OCI format drops it unless you build with `--format docker` |
| `STOPSIGNAL` | signal sent on stop | `STOPSIGNAL SIGQUIT` | honoured by containerd/CRI-O; otherwise SIGTERM |
| `ENTRYPOINT` | the executable | `ENTRYPOINT ["/app/server"]` | the Pod `command` replaces it |
| `CMD` | default args for ENTRYPOINT (or the whole command when there is no ENTRYPOINT) | `CMD ["--port=8080"]` | the Pod `args` replace it; only the **last** CMD counts; setting ENTRYPOINT resets a CMD inherited from the base image |
| `SHELL` | shell used by shell-form instructions | `SHELL ["/bin/bash", "-c"]` | Docker format only |
| `ONBUILD` | trigger for child images | rarely used | Docker format only |

### Shell form vs exec form

| | Exec form `["exe", "arg"]` | Shell form `exe arg` |
|---|---|---|
| Runs as | the executable directly (PID 1) | `/bin/sh -c "exe arg"` (sh is PID 1) |
| SIGTERM on stop | reaches your process | goes to `sh` and is usually not forwarded, so the app is SIGKILLed after the grace period |
| `$VAR` expansion | none (no shell) | yes |
| Needs a shell in the image | no (works in scratch/distroless) | yes |
| ENTRYPOINT + CMD | CMD is appended as arguments | a shell-form ENTRYPOINT **ignores** CMD and all runtime args |
| Use for | ENTRYPOINT and CMD | RUN |

> **Exam tip:** exec form must be valid JSON with **double quotes**. `CMD ['nginx', '-g', 'daemon off;']` (single quotes) is not JSON, so it is silently treated as shell form.

### Layer caching

- For each instruction the builder reuses a cached layer if the parent layer is the same **and** the instruction text (RUN) or the file checksums (COPY/ADD) are the same.
- The first cache miss rebuilds **every later step**.
- Put things that rarely change first: base, OS packages, dependency manifest, dependency install, **then** source code, then build.
- Deleting a file in a later layer does **not** make the image smaller. Remove it in the same `RUN` that created it.
- `--no-cache` forces a full rebuild. `--pull` (docker) / `--pull=always` (podman) refreshes the base image.

```dockerfile
# Bad: any source change re-runs the dependency install
COPY . .
RUN npm ci

# Good: dependencies stay cached until package*.json changes
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
```

### `.dockerignore`

- Lives in the **root of the build context**. Same idea as `.gitignore` (`*`, `**`, `!exception`, `#` comments).
- Gives a faster build, a more stable cache, and keeps `.git`, `.env`, keys and old tarballs **out of the image**.
- Podman reads `.containerignore`, or `.dockerignore` if that is the only one. Example: [yaml/images/.dockerignore](yaml/images/.dockerignore).

### Multi-stage builds

- Several `FROM` lines. Build in a fat toolchain stage, then `COPY --from=<stage>` **only the artefact** into a small runtime stage.
- The final image is the **last** stage, unless you pass `--target <stage>`.
- Benefits: no compiler or source code in production, fewer CVEs, smaller pulls. Example: [yaml/images/Dockerfile.multistage](yaml/images/Dockerfile.multistage) (Go builder, then `scratch`).

### Podman vs Docker

| | Docker | Podman |
|---|---|---|
| Architecture | client + `dockerd` daemon | daemonless (fork/exec), rootless-friendly |
| Name of a local build `app:v1` | `app:v1` (`docker.io/library/app:v1`) | `localhost/app:v1` |
| Default build format | Docker image format (OCI when the containerd image store is enabled) | **OCI** (`--format docker` keeps `HEALTHCHECK`, `SHELL`, `ONBUILD`) |
| `save` default | Engine 25+: OCI-compliant tar (Docker's 25.0 release notes) that `docker load` reads | **docker-archive**; use `--format oci-archive` for OCI |
| Short names (`nginx`) | always Docker Hub | resolved via `/etc/containers/registries.conf` and may prompt. Use fully-qualified names like `docker.io/library/nginx:1.27` |
| Plain-HTTP registry | `insecure-registries` in `daemon.json` (`localhost` is allowed by default) | `--tls-verify=false`, or `insecure = true` in `registries.conf` |
| Kubernetes YAML helpers | none | `podman kube generate <ctr>` / `podman kube play file.yaml` |

### Image archive formats

| Command | Writes | `tar -tf` shows | Load with |
|---|---|---|---|
| `podman save -o x.tar img:tag` | docker-archive (default) | `manifest.json`, config + layer blobs | `podman load -i`, `docker load -i` |
| `podman save --format oci-archive -o x.tar img:tag` | OCI image layout as a tar | `oci-layout`, `index.json`, `blobs/sha256/...` | `podman load -i` |
| `podman save --format oci-dir -o dir/ img:tag` | OCI layout as a directory | same files, unpacked | `podman load -i dir/` |
| `podman save -m -o x.tar img1 img2` | multi-image docker-archive | | `podman load -i` |
| `docker save -o x.tar img:tag` | Engine 25+: OCI-compliant tar (keeps `manifest.json` for older loaders) | `index.json`, `oci-layout`, `blobs/`, `manifest.json` | `docker load -i`, `podman load -i` |

`load` restores a **saved image** (layers + tags). `import` is something else: it creates a flat image from a container filesystem tarball made by `export`. Do not mix them up.

### ENTRYPOINT/CMD ↔ Pod `command`/`args`

`command` replaces the image **ENTRYPOINT**; `args` replaces the image **CMD**.

| Image ENTRYPOINT | Image CMD | Pod `command` | Pod `args` | What runs |
|---|---|---|---|---|
| `[/ep-1]` | `[foo, bar]` | not set | not set | `/ep-1 foo bar` |
| `[/ep-1]` | `[foo, bar]` | `[/ep-2]` | not set | `/ep-2` (**image CMD is dropped too**) |
| `[/ep-1]` | `[foo, bar]` | not set | `[zoo, boo]` | `/ep-1 zoo boo` |
| `[/ep-1]` | `[foo, bar]` | `[/ep-2]` | `[zoo, boo]` | `/ep-2 zoo boo` |

The same rules with real images:

| Image (ENTRYPOINT / CMD) | Pod sets | Result |
|---|---|---|
| `nginx:1.27` (`/docker-entrypoint.sh` / `nginx -g "daemon off;"`) | `args: ["nginx-debug", "-g", "daemon off;"]` | entrypoint kept, runs `nginx-debug` |
| `nginx:1.27` | `command: ["nginx"]` | CMD dropped, so nginx **daemonizes**, PID 1 exits, the container restarts → CrashLoopBackOff |
| `busybox:1.36` (none / `sh`) | `args: ["sleep", "3600"]` | runs `sleep 3600` (no ENTRYPOINT, so args are the whole command) |
| `busybox:1.36` | `command: ["sh", "-c", "echo $HOME"]` | the shell expands `$HOME` |

| Docker / Podman CLI | Kubernetes equivalent | `kubectl run` |
|---|---|---|
| `podman run img a b` | `args: [a, b]` | `kubectl run x --image=img -- a b` |
| `podman run --entrypoint sleep img 3600` | `command: [sleep]`, `args: ["3600"]` | `kubectl run x --image=img --command -- sleep 3600` (puts both words in `command`) |

> **Exam tip:** Kubernetes expands `$(VAR)` in `command`/`args` from the container's env, with no shell needed. `$VAR` is only expanded if you run a shell (`sh -c`). An unknown `$(name)` is left as-is; `$$(name)` escapes it. Shell syntax (loops, pipes, `>`, `&&`) **needs** `["sh", "-c", "..."]`.

### `imagePullPolicy`

| Value | Behaviour |
|---|---|
| `IfNotPresent` | pull only if the image is not on the node |
| `Always` | ask the registry every time a container starts (cheap: cached layers are reused) |
| `Never` | never pull; the container fails with `ErrImageNeverPull` if the image is missing |

| Image reference (policy omitted) | Defaulted to |
|---|---|
| `nginx` (no tag) | `Always` |
| `nginx:latest` | `Always` |
| `nginx:1.27` | `IfNotPresent` |
| `nginx@sha256:...` | `IfNotPresent` |

The default is filled in **when the object is created** and is **not** updated if you later change the tag.

### Private registries (brief)

```bash
kubectl create secret docker-registry regcred -n app \
  --docker-server=registry.example.com:5000 --docker-username=dev --docker-password='S3cret!' --docker-email=dev@example.com
```

```yaml
spec:
  imagePullSecrets:          # must be in the pod's namespace; type kubernetes.io/dockerconfigjson
  - name: regcred
  containers:
  - name: app
    image: registry.example.com:5000/team/app:1.4.2
```

You can also attach `imagePullSecrets` to a ServiceAccount so every pod using it inherits them. Details, ServiceAccounts and Secret types are in [../04-Application-Environment-Configuration-and-Security/README.md](../04-Application-Environment-Configuration-and-Security/README.md). Without the secret you get `ErrImagePull` → `ImagePullBackOff` (back-off capped at 5 minutes).

### Image best practices

- **Minimal base:** `-alpine`, distroless or `scratch` for static binaries, which means fewer CVEs and faster pulls.
- **Non-root:** `USER 10001:10001` (numeric). Pair it with `securityContext.runAsNonRoot: true`.
- **Pin versions:** `FROM nginx:1.27-alpine` or `FROM nginx@sha256:...`; never `latest` in production.
- **No secrets in layers:** `ARG`, `ENV` and `COPY`'d files stay in the image and its `history` forever. Inject secrets at runtime (Secret volumes/env), or use BuildKit secret mounts at build time.
- **One process per container**, logs to stdout/stderr, exec-form ENTRYPOINT so SIGTERM reaches the app.
- **Small context:** `.dockerignore`. Clean caches in the same `RUN`; use multi-stage builds.
- **Labels:** `org.opencontainers.image.*` (version, source, revision) for traceability.

---

## Key fields / syntax

Annotated reference files:

| File | Shows |
|---|---|
| [yaml/images/Dockerfile](yaml/images/Dockerfile) | every common instruction, non-root busybox httpd on port 8080 |
| [yaml/images/Dockerfile.nginx](yaml/images/Dockerfile.nginx) | the typical 3-line exam Dockerfile (`FROM nginx`, `COPY`, `EXPOSE`) |
| [yaml/images/Dockerfile.multistage](yaml/images/Dockerfile.multistage) | multi-stage Go build into `scratch`, `ARG` per stage, `--target` |
| [yaml/images/app/main.go](yaml/images/app/main.go) | the tiny app used by the multi-stage build |
| [yaml/images/.dockerignore](yaml/images/.dockerignore) | build-context exclusions |
| [yaml/images/pod-local-image.yaml](yaml/images/pod-local-image.yaml) | running a locally built image (`localhost/` prefix, `imagePullPolicy`) |
| [yaml/pod-command-args.yaml](yaml/pod-command-args.yaml) | the command/args combinations as runnable pods |

Core Dockerfile skeleton (what you most often edit):

```dockerfile
FROM busybox:1.36
ENV APP_VERSION=2.0
WORKDIR /www
COPY index.html .
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["httpd", "-f", "-v"]
CMD ["-p", "8080", "-h", "/www"]
```

Pod side (image-related fields):

```yaml
spec:
  containers:
  - name: app
    image: registry.example.com:5000/team/app:1.4.2   # registry/repo:tag
    imagePullPolicy: IfNotPresent
    command: ["/app/server"]                            # replaces ENTRYPOINT
    args: ["--port=8080", "--log-level=$(LOG_LEVEL)"]   # replaces CMD; $(VAR) expanded by Kubernetes
    env:
    - name: LOG_LEVEL
      value: debug
  imagePullSecrets:
  - name: regcred
```

---

## Imperative commands

### The exam workflow: modify an existing Dockerfile and rebuild

```bash
cd /opt/course/1/image                 # 1. go to the build context named in the task
cat Dockerfile                         # 2. read it: base image, ENV, CMD/ENTRYPOINT, USER
vi Dockerfile                          # 3. make the change (e.g. ENV APP_VERSION=2.0, USER 10001)
podman build -t ckad-web:2.0 .         # 4. build; the trailing "." is the build context
podman images | grep ckad-web          # 5. verify name + tag (podman shows localhost/ckad-web)
podman save --format oci-archive -o /opt/course/1/ckad-web-2.0.tar ckad-web:2.0   # 6. deliver as asked
tar -tf /opt/course/1/ckad-web-2.0.tar | head   # 7. prove it: oci-layout, index.json, blobs/...
```

### Podman

```bash
podman build -t app:v1 .                                  # build ./Containerfile or ./Dockerfile
podman build -t app:v1 -f Dockerfile.multistage .         # other Dockerfile name; context is still "."
podman build -t app:v1 -t app:latest .                    # several tags in one build
podman build --build-arg VERSION=1.2 -t app:1.2 .         # set an ARG
podman build --target build -t app:builder -f Dockerfile.multistage .   # stop at a named stage
podman build --no-cache --pull=always -t app:v1 .         # ignore cache, refresh base image
podman build --format docker -t app:v1 .                  # keep HEALTHCHECK/SHELL/ONBUILD
podman images                                             # list (podman image ls)
podman images --digests                                   # include digests
podman tag app:v1 localhost:5000/team/app:v1              # add a registry-qualified name
podman push localhost:5000/team/app:v1 --tls-verify=false # push to a plain-HTTP registry
podman login registry.example.com:5000                    # credentials for push/pull
podman save -o app.tar app:v1                             # docker-archive (default)
podman save --format oci-archive -o app-oci.tar app:v1    # OCI archive
podman load -i app.tar                                    # import a saved archive
podman image inspect app:v1 --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'   # entrypoint + cmd
podman image inspect app:v1 --format '{{.Config.User}} {{.Config.Env}}'         # user + env
podman history app:v1                                     # layers + the instruction that created each
podman rmi app:v1                                         # remove a tag/image
```

### Docker

```bash
docker build -t app:v1 .                                  # build ./Dockerfile
docker build -t app:v1 -f Dockerfile.multistage --build-arg VERSION=1.2 .
docker images                                             # list
docker tag app:v1 localhost:5000/team/app:v1              # retag for a registry
docker push localhost:5000/team/app:v1                    # push (localhost registries may use HTTP)
docker push --all-tags localhost:5000/team/app            # push every local tag of that repository
docker save -o app.tar app:v1                             # Engine 25+: OCI-compliant tarball
docker save app:v1 | gzip > app.tar.gz                    # compressed
docker load -i app.tar                                    # import (gzip is accepted too)
docker image inspect app:v1 --format '{{json .Config}}'   # full config
docker history app:v1                                     # layers
docker buildx build --platform linux/amd64,linux/arm64 -t reg/app:v1 --push .   # multi-arch (nice to know)
```

### Run and test the image locally

```bash
podman run -d --name web -p 8080:8080 app:v1              # detached; host 8080 -> container 8080
podman run -d --name web --user 1000 -e APP_ENV=dev app:v1   # run as UID 1000, set env
podman run --rm -it --entrypoint sh app:v1                # override ENTRYPOINT to poke around
podman run --rm app:v1 --help                             # trailing words REPLACE CMD (appended to ENTRYPOINT)
podman run --rm --entrypoint id app:v1 -u                 # replace ENTRYPOINT too: prints the UID the image runs as
podman ps                                                 # running containers (-a = all)
podman logs web > /opt/course/x/logs 2>&1                 # capture stdout AND stderr
podman exec -it web sh                                    # shell inside the running container
curl -s localhost:8080                                    # test from the host
podman stop web && podman rm web                          # clean up (podman rm -f web)
```

### A local registry for practice

```bash
podman run -d --name registry -p 5000:5000 docker.io/library/registry:2   # or: docker run -d -p 5000:5000 registry:2
curl -s localhost:5000/v2/_catalog                        # {"repositories":["team/app"]}
curl -s localhost:5000/v2/team/app/tags/list              # {"name":"team/app","tags":["v1"]}
```

### Get the image into a lab cluster

```bash
kind load docker-image app:v1 --name <cluster>            # docker-built image into kind nodes
kind load image-archive app.tar --name <cluster>          # any saved archive (podman workflow)
minikube image load app:v1                                # minikube
sudo ctr -n k8s.io images import app.tar                  # containerd node (kubeadm)
sudo crictl images | grep app                             # what the kubelet's runtime can see
```

### Use the new image from Kubernetes

```bash
kubectl run web --image=localhost:5000/team/app:v1 --port=8080 --dry-run=client -o yaml > web.yaml
kubectl create deployment web --image=localhost:5000/team/app:v1 --replicas=2 --dry-run=client -o yaml > deploy.yaml
kubectl set image deployment/web app=localhost:5000/team/app:v2   # roll to the rebuilt tag
kubectl get pod web -o jsonpath='{.status.containerStatuses[0].imageID}{"\n"}'   # digest actually running
```

---

## Exam traps & tips

> **Exam tip:** Build from the directory the task names. The final `.` is the **context**; `-f` only says which Dockerfile to use. `COPY` cannot reach files outside the context.

> **Exam tip:** "Save the image as a tar in OCI format" means `podman save --format oci-archive -o <path> <image>`. Plain `podman save` writes **docker-archive**. Check with `tar -tf file | head`: you should see `oci-layout` and `index.json`.

> **Exam tip:** podman shows a local build `app:v1` as `localhost/app:v1`. Both names work with podman commands. In a Pod on a node that imported a podman archive, the image name is `localhost/app:v1`.

> **Exam tip:** Use the exact name **and** tag from the task (`registry:5000/repo:tag`). A missing tag silently becomes `latest`. Build with several `-t` flags if two tags are required, then verify with `podman images`.

> **Exam tip:** `podman logs` / `docker logs` send the container's stderr to your stderr. When writing logs to a file use `> file 2>&1`.

> **Exam tip:** A Pod that sets only `command` loses the image CMD. If the container exits immediately after you "only changed the command", that is why. Add the missing arguments to `args`.

> **Exam tip:** `kubectl run x --image=img -- a b` sets **args**. `kubectl run x --image=img --command -- a b` sets **command**. `kubectl create deployment|job|cronjob ... -- a b` always sets **command**.

- `USER appuser` (a name) combined with `runAsNonRoot: true` gives `CreateContainerConfigError: ... image has non-numeric user (appuser), cannot verify user is non-root`. Use a numeric UID in the Dockerfile or set `runAsUser`.
- `HEALTHCHECK` does nothing in Kubernetes. If a task says "health check" for a Pod, write a probe.
- `EXPOSE` is not `-p`. With podman/docker you still need `-p host:container`.
- `imagePullPolicy: Always` with an image that exists only on the node (loaded tarball) → `ErrImagePull`. Use `IfNotPresent` or `Never`.
- Exec-form `CMD ["echo", "$HOME"]` prints `$HOME` literally (no shell).
- `podman push` to a plain-HTTP registry fails with a TLS error until you add `--tls-verify=false`.

---

## Architect notes

- **Promote by digest, not tag.** Build once, push, then deploy the same `@sha256:` digest to dev, staging and prod. Tags are mutable; enforce tag immutability in the registry.
- **Supply chain:** generate an SBOM, scan in CI (Trivy/Grype), sign images (cosign/Sigstore) and verify signatures at admission with Kyverno, Gatekeeper or a ValidatingAdmissionPolicy that also restricts allowed registries.
- **Minimal runtime images** (distroless/scratch) remove shells and package managers, which shrinks the attack surface. Debug them with `kubectl debug` ephemeral containers instead of baking tools in.
- **Reproducible, cache-efficient builds:** pin base images by digest (updated by Renovate/Dependabot), order layers by change frequency, and use BuildKit cache mounts plus a remote cache in CI.
- **Rootless, daemonless builders in CI** (Buildah/Podman, BuildKit rootless) avoid privileged Docker-in-Docker on shared runners.
- **Multi-arch images** (`linux/amd64` + `linux/arm64` behind one index) let the same tag run on Graviton/ARM nodes and save cost.
- **Pull performance:** image size drives pod start latency and node disk pressure. Use registry mirrors or pull-through caches and consider pre-pulling on large clusters. Kubelet image GC uses disk thresholds.
- **Runtime config, not build config:** one image for all environments; inject config via ConfigMaps, Secrets and env (12-factor). Never rebuild per environment.

---

## Docs to bookmark

- Images, pull policy, private registries: <https://kubernetes.io/docs/concepts/containers/images/>
- Command and args: <https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/>
- Pull from a private registry: <https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/>
- Container fields (API reference): <https://kubernetes.io/docs/reference/kubernetes-api/core/pod-v1/>
- Not allowed in the exam, but useful when studying: Dockerfile reference <https://docs.docker.com/reference/dockerfile/>, multi-stage <https://docs.docker.com/build/building/multi-stage/>, `podman build` <https://docs.podman.io/en/latest/markdown/podman-build.1.html>, `podman save` <https://docs.podman.io/en/latest/markdown/podman-save.1.html>

---

## Quick self-check

1. An image has `ENTRYPOINT ["python", "app.py"]` and `CMD ["--port", "8000"]`. The Pod sets `args: ["--port", "9000"]`. What runs? And what if the Pod sets only `command: ["python"]`?
2. What does `podman save -o img.tar app:v1` produce, and how do you produce an OCI archive instead?
3. A Pod uses `image: myapp` (no tag, no pull policy) after you loaded `myapp` into the node with `ctr import`. Why does it fail, and what two changes fix it?
4. Why can `runAsNonRoot: true` fail with an image that declares `USER app`?
5. You changed one line of application source code and every `RUN apt-get install` layer rebuilt. What is wrong with the Dockerfile?
6. Name two Dockerfile instructions that Kubernetes ignores and what to use instead.

<details><summary>Answers</summary>

1. `python app.py --port 9000` (ENTRYPOINT kept, CMD replaced). With only `command: ["python"]`, the process is just `python`: the image CMD is dropped as well, so no `app.py` and no port.
2. A **docker-archive** tarball (`manifest.json` + layers). For OCI: `podman save --format oci-archive -o img.tar app:v1`.
3. No tag means `:latest`, so `imagePullPolicy` defaults to `Always` and the kubelet tries to pull `docker.io/library/myapp:latest` (ErrImagePull). Use the real tag (e.g. `myapp:v1`, or `localhost/myapp:v1` for podman builds) **and** `imagePullPolicy: IfNotPresent` (or `Never`).
4. The kubelet cannot prove a user **name** is non-root, so the container fails with `CreateContainerConfigError`. Use `USER 10001` or set `securityContext.runAsUser`.
5. `COPY . .` (or similar) comes **before** the package installation, so any source change invalidates the cache for all later steps. Install dependencies first, copy the source last.
6. `HEALTHCHECK` (use liveness/readiness/startup probes), `EXPOSE` (use `containerPort` + a Service), `VOLUME` (declare a Kubernetes volume + `volumeMounts`).

</details>
