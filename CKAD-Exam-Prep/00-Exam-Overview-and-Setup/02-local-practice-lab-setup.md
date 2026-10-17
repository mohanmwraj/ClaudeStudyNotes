# Practice Lab Setup (Windows-friendly)

You pass CKAD by **typing**, not reading. Build a lab today and do every practice question and mock exam in it.

*Versions below were checked on 2026-10-17: Kubernetes stable v1.37.1, kind v0.33.0, Helm 4.3.1, Gateway API v1.6.3, cloud-provider-kind v0.12.0.*

---

## 1. Pick a lab

| Option | Setup time | Good for | Notes |
|---|---|---|---|
| **killer.sh simulator** (two sessions come with a standard exam registration) | 0 min | Final dress rehearsal | Each session gives 36 h of access from activation; the two CKAD sessions have different questions. Candidates commonly find it harder than the real exam. Activate one ~2–3 days before the exam and the second the day before. See [README](README.md). |
| **Killercoda** (browser, free) — https://killercoda.com/killer-shell-ckad | 0 min | Quick drills on any machine | Short-lived playgrounds; re-run setup each time. |
| **kind in WSL2** (recommended local lab) | 15–25 min | Mock exams 01–06 in this kit, unlimited practice | Multi-node, NetworkPolicy enforced out of the box (kind ≥ v0.24.0), fast reset. |
| **minikube** | 10–20 min | If you already use it | Use `--cni=calico` for NetworkPolicy and the `ingress` + `metrics-server` addons. |

The exam terminal is Linux bash. Practise in **WSL2 Ubuntu** (or any Linux/macOS shell), not PowerShell, so your muscle memory matches.

---

## 2. Windows → WSL2 → container runtime

```powershell
# PowerShell as Administrator (one time, then reboot if asked)
wsl --install -d Ubuntu
```

Inside Ubuntu, install **one** container runtime:

```bash
# Option A: Docker Engine inside WSL2 (or install Docker Desktop on Windows and enable WSL integration)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker
docker run --rm hello-world

# Option B: Podman (also what you will use for image-build practice)
sudo apt-get update && sudo apt-get install -y podman
```

> kind works with Docker (default) or Podman (`KIND_EXPERIMENTAL_PROVIDER=podman`). Docker is the smoother path for kind; install Podman too so you can practise `podman build/save`.

---

## 3. Install kubectl, kind, Helm (inside WSL2)

```bash
# kubectl — current stable
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl
kubectl version --client

# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64
sudo install -m 0755 kind /usr/local/bin/kind && rm kind
kind version

# Helm (Helm 4 is current; the exam may ship Helm 3 or 4 — core commands are the same)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
helm version

# Handy extras that also exist in the exam environment
sudo apt-get install -y jq vim tmux bash-completion
```

---

## 4. Create the CKAD practice cluster (kind)

Save as `kind-ckad.yaml`:

```yaml
# kind-ckad.yaml — 1 control plane + 2 workers; host ports 8080/8443 reach the ingress controller
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ckad
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80       # ingress-nginx hostPort 80 on this node
    hostPort: 8080          # -> http://localhost:8080 on your machine
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
- role: worker
- role: worker
```

```bash
kind create cluster --config kind-ckad.yaml
# Optional: match the exam's Kubernetes minor version (see README for the current exam version).
# kind v0.33.0 publishes these node images (use the digest):
#   kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5   (default)
#   kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
#   kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
#   kindest/node:v1.34.11@sha256:44e222ee2132dab25ff87301682f89eb82c7880ea3a1bf543bfe9708fd08d67d
# kind create cluster --config kind-ckad.yaml --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed

kubectl get nodes -o wide
kubectl get storageclass          # kind ships "standard" (local-path, default, WaitForFirstConsumer)
```

### 4a. Ingress controller (needed for Ingress questions)

The mock exams use `ingressClassName: nginx`. **ingress-nginx was retired by the Kubernetes project in March 2026** (no more fixes or security patches). That makes it a bad choice for production, but it still installs and works fine in a throw-away practice cluster, and its class name (`nginx`) matches most practice material:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
# The controller listens on hostPort 80/443 of whatever node it lands on. Pin it to the control-plane
# node, the only node whose ports are mapped to your machine in kind-ckad.yaml (it already tolerates the taint):
kubectl -n ingress-nginx patch deployment ingress-nginx-controller \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"ckad-control-plane"}}}}}'
kubectl wait -n ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
kubectl -n ingress-nginx get pod -l app.kubernetes.io/component=controller -o wide   # NODE = ckad-control-plane
kubectl get ingressclass                                       # expect: nginx
# test later with:  curl -s -H "Host: app.example.com" http://localhost:8080/
```

**Alternative: cloud-provider-kind.** Since cloud-provider-kind v0.9.0 it implements Ingress *and* Gateway API natively, plus `type: LoadBalancer` Services. Install it with `go install sigs.k8s.io/cloud-provider-kind@latest` (or use its container image). Keep it running in a separate terminal; on WSL2 run it with `sudo`. Check the class it registers with `kubectl get ingressclass,gatewayclass`, and use that class name in your practice Ingresses. The GatewayClass is `cloud-provider-kind`.

### 4b. metrics-server (needed for `kubectl top`)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind's kubelet certs are self-signed -> allow insecure TLS (lab only!)
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deploy/metrics-server
sleep 60; kubectl top nodes
```

### 4c. NetworkPolicy enforcement

kind ≥ v0.24.0 enforces NetworkPolicy out of the box: kindnetd uses `sigs.k8s.io/kube-network-policies`. Prove it once, so you trust your lab:

```bash
kubectl create ns np-test
kubectl -n np-test run web --image=nginx:1.27 --port=80 --expose
kubectl -n np-test wait --for=condition=Ready pod/web --timeout=90s
kubectl -n np-test run c1 --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 3 http://web   # works
kubectl -n np-test apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
EOF
kubectl -n np-test run c2 --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 3 http://web   # must time out
kubectl delete ns np-test
```

### 4d. Gateway API CRDs (bonus topics only)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml
kubectl get crd | grep gateway.networking.k8s.io
# CRDs alone do nothing; you also need an implementation (cloud-provider-kind, Envoy Gateway, NGINX Gateway Fabric, Istio, Cilium, Traefik ...)
```

---

## 5. minikube alternative

```bash
minikube start --nodes=2 --cni=calico --kubernetes-version=stable
minikube addons enable ingress           # ingress-nginx, class "nginx"
minikube addons enable metrics-server
minikube ip                              # use with the ingress NodePort / port 80
```

---

## 6. Make the lab feel like the exam

```bash
cat >> ~/.bashrc <<'EOF'
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
EOF
printf 'set expandtab\nset tabstop=2\nset shiftwidth=2\nset autoindent\nset number\n' >> ~/.vimrc
source ~/.bashrc
```

Then practise with **only** the documentation sites the exam allows open in your browser (see [README](README.md)) — learn where things live in the docs *now*, not on exam day.

---

## 7. Using this kit's mock exams in the lab

```bash
cd /mnt/c/Users/<you>/Documents/Claude/CKAD-Exam-Prep/07-Mock-Exams/mock-exam-01
bash setup.sh            # creates namespaces m01-*, broken objects, files under ~/ckad-mocks/exam-01/
# ... take the exam (120 min timer) ...
bash cleanup.sh          # removes everything the exam created
```

Fast full reset: `kind delete cluster --name ckad && kind create cluster --config kind-ckad.yaml`, then redo steps 4a–4b. That takes about 3 minutes.

---

## 8. Troubleshooting the lab itself

| Problem | Fix |
|---|---|
| `kubectl top` → `Metrics API not available` | Wait 60 s; check the `--kubelet-insecure-tls` patch; `kubectl -n kube-system logs deploy/metrics-server` |
| Ingress returns 404 | `ingressClassName` must match `kubectl get ingressclass`; the Host header must match the rule; the backend Service needs endpoints |
| `curl localhost:8080` refused | Controller pod is not on `ckad-control-plane` (re-run the nodeSelector patch in 4a), or `kind-ckad.yaml` has no port mapping |
| NetworkPolicy has no effect | You replaced kindnet with a CNI that doesn't enforce policies, or you're on an old kind (< v0.24.0); upgrade kind or use minikube `--cni=calico` |
| Images fail to pull | Corporate proxy / rate limit; pre-pull with `docker pull` then `kind load docker-image <img> --name ckad` |
| A podman-built image is "not found" in the cluster | The cluster can't see local images: `podman save -o img.tar myapp:1.0 && kind load image-archive img.tar --name ckad` |
