# 03 — Ingress: HTTP(S) Routing into the Cluster

**Why it matters:** "Use Ingress rules to expose applications" is one of the three competencies of this domain. Typical tasks: create an Ingress for given hosts/paths/backends (fastest with `kubectl create ingress`), add TLS from a Secret, or repair an Ingress that returns 404/503.

**What the exam expects:** the `networking.k8s.io/v1` schema by heart (`ingressClassName`, `pathType`, `backend.service.name` + `port.number|name`), Prefix vs Exact semantics, a TLS Secret, and testing with `curl -H "Host: ..."`.

---

## Core concepts

### Ingress vs Ingress controller

| | Ingress (API object) | Ingress controller |
|---|---|---|
| What | Rules: host + path → Service:port, plus TLS settings | Software that watches Ingresses of **its class** and configures a proxy (NGINX, Envoy, HAProxy, Traefik, a cloud LB, ...) |
| Provided by | Kubernetes API, `networking.k8s.io/v1` (GA since v1.19) | You (or the platform) install it; not part of kube-controller-manager |
| Alone | Does nothing — the ADDRESS column stays empty | Serves only its own default backend (typically 404) |

```text
client --HTTP(S)--> controller entry point (LoadBalancer IP / NodePort / hostPort)
                      +-> controller Pod (e.g. ingress-nginx) evaluates the rules of its IngressClass
                            |- Host shop.example.com, path /api  -> Service api-svc:8080 -> EndpointSlices -> Pod IPs
                            '- nothing matched                   -> spec.defaultBackend, else controller 404
```

Many controllers (ingress-nginx included) send traffic **straight to the Pod IPs** from the EndpointSlices; the Service is used for discovery. Consequences: readiness still matters (only ready endpoints), and a NetworkPolicy on the backends must allow traffic **from the controller Pods**.

Ingress handles HTTP/HTTPS only (ports 80/443). For arbitrary TCP/UDP use a Service of type NodePort/LoadBalancer (or Gateway API routes).

### Status of the Ingress API and ingress-nginx (2026)

- The **Ingress API is GA, stable and stays**: the Kubernetes project has no plans to remove it. But it is **frozen** — no new features — and the docs recommend **Gateway API** instead (see [05-gateway-api.md](05-gateway-api.md)).
- The **ingress-nginx controller project was retired**: Kubernetes SIG Network and the Security Response Committee announced it in November 2025; best-effort maintenance ended in March 2026, after which there are no further releases, bug fixes or security updates. Existing deployments keep working and the published Helm charts/images remain available — so it is still fine for practice labs, and the `nginx.ingress.kubernetes.io/*` annotations below still apply to clusters that run it.
- Check whether a cluster runs it: `kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx`.

### IngressClass and `ingressClassName`

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
```

- `IngressClass` is cluster-scoped; `spec.controller` names the implementation, optional `spec.parameters` (`scope: Cluster` default, or `Namespace` + `namespace`) points at controller config.
- An Ingress selects its controller with **`spec.ingressClassName: <class>`**.
- **Default class:** an IngressClass annotated `ingressclass.kubernetes.io/is-default-class: "true"` is assigned to new Ingresses created **without** `ingressClassName`. With more than one default, the admission controller rejects new class-less Ingresses — keep at most one.
- The pre-1.18 annotation `kubernetes.io/ingress.class` is deprecated; use the field.
- `kubectl get ingressclass` shows which classes exist — use exactly the one the task names.

File: [yaml/ingressclass.yaml](yaml/ingressclass.yaml).

### Rules

| Part | Rules |
|---|---|
| `host` (optional) | Precise (`shop.example.com`) or wildcard (`*.example.com` = exactly **one** extra DNS label: matches `foo.example.com`, not `example.com`, not `a.b.example.com`). No host = applies to all hosts. Matched against the HTTP `Host` header. Quote wildcards in YAML. |
| `http.paths[].path` | Must start with `/` (for Exact/Prefix) |
| `http.paths[].pathType` | **Required**: `Exact` · `Prefix` · `ImplementationSpecific` (controller decides, e.g. regex) |
| `backend.service.name` | A Service in the **same namespace** as the Ingress |
| `backend.service.port.number` / `.name` | The **Service** port (not targetPort), by number or by Service port name |
| `backend.resource` | Alternative to `service` (an object ref such as a storage bucket CRD); mutually exclusive with `service` |

### defaultBackend

- `spec.defaultBackend` handles requests that match **no rule** of the Ingress (same shape as a path backend).
- An Ingress with **no rules** must have a `defaultBackend` — it then receives all traffic.
- Without one, unmatched requests are up to the controller (ingress-nginx answers 404 from its own default backend).

File: [yaml/ingress-default-backend.yaml](yaml/ingress-default-backend.yaml).

### Path matching precedence

- `Exact`: the URL path must match exactly (case-sensitive). `/foo` does not match `/foo/`.
- `Prefix`: matched **element by element** on `/`-separated segments (case-sensitive); a trailing slash is ignored. `/foo` matches `/foo`, `/foo/` and `/foo/bar` — but **not** `/foobar`.
- Several paths match → the **longest matching path wins**; on equal length, **Exact beats Prefix**.

| Path(s) in the Ingress | Request | Result |
|---|---|---|
| `/` (Prefix) | anything | match |
| `/foo` (Exact) | `/foo` | match |
| `/foo` (Exact) | `/foo/` | **no** |
| `/foo/` (Exact) | `/foo` | **no** |
| `/foo` (Prefix) | `/foo`, `/foo/` | match |
| `/aaa/bbb` (Prefix) | `/aaa/bbb/ccc` | match (sub-path) |
| `/aaa/bbb` (Prefix) | `/aaa/bbbxyz` | **no** (not a string prefix match) |
| `/aaa/bb` (Prefix) | `/aaa/bbb` | **no** |
| `/`, `/aaa` (Prefix) | `/aaa/ccc` | `/aaa` wins (longest) |
| `/aaa` (Prefix) | `/ccc` | no rule → default backend |
| `/foo` (Prefix) and `/foo` (Exact) | `/foo` | **Exact** wins (tie) |

Demo with all of these: [yaml/ingress-path-fanout.yaml](yaml/ingress-path-fanout.yaml).

### TLS

```yaml
spec:
  tls:
  - hosts:
    - secure.example.com          # must match a rules[].host
    secretName: secure-tls        # same namespace as the Ingress
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-svc
            port:
              number: 80
```

- The Secret must be type `kubernetes.io/tls` with keys `tls.crt` and `tls.key`, in the Ingress's namespace.
- Ingress supports a single TLS port, **443**, and terminates TLS at the controller (traffic to the Pods is plain HTTP unless controller annotations say otherwise). Several hosts share 443 via **SNI**.
- TLS does not apply to host-less rules: `tls.hosts` must match `rules[].host`.
- Missing / wrong Secret → the controller serves its default certificate (ingress-nginx: "Kubernetes Ingress Controller Fake Certificate").

Self-signed certificate + Secret. `openssl` is **not** among the tools guaranteed on exam hosts (kubectl, yq, curl, wget, man — see [00](../00-Exam-Overview-and-Setup/README.md)); TLS tasks normally hand you the `.crt`/`.key` files, and `kubectl create secret tls` is all you need. The `openssl` line is for your lab:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=secure.example.com" \
  -addext "subjectAltName=DNS:secure.example.com"          # SAN; needs OpenSSL 1.1.1+
kubectl create secret tls secure-tls --cert=tls.crt --key=tls.key -n <ns>
kubectl get secret secure-tls -n <ns> -o jsonpath='{.type}{"\n"}'   # kubernetes.io/tls
```

File: [yaml/ingress-tls.yaml](yaml/ingress-tls.yaml).

### Controller-specific annotations (ingress-nginx)

Annotations are **per controller** — Traefik, HAProxy or cloud controllers use different keys. Values are strings: quote `"true"` and numbers.

| Annotation | Effect |
|---|---|
| `nginx.ingress.kubernetes.io/rewrite-target` | Rewrites the path sent upstream. Alone with `/` it maps **every** matched path to `/`; to keep the remainder use a regex path with capture groups and `/$2` |
| `nginx.ingress.kubernetes.io/use-regex: "true"` | Treat paths as regular expressions (with `pathType: ImplementationSpecific`) |
| `nginx.ingress.kubernetes.io/ssl-redirect: "false"` | Disable the HTTP→HTTPS redirect that is on by default when the Ingress has `tls` |
| `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"` | Redirect to HTTPS even without a `tls` section (TLS terminated in front of the controller) |
| `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` | Talk HTTPS (or `GRPC`, ...) to the backend Pods |
| `nginx.ingress.kubernetes.io/canary: "true"` + `canary-weight: "10"` | A second Ingress for the same host/path sends ~10% to a canary Service (see [02 Application Deployment](../02-Application-Deployment/README.md)) |

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: "/$2"
spec:
  rules:
  - host: apps.example.com
    http:
      paths:
      - path: "/legacy(/|$)(.*)"          # /legacy/orders/7 -> upstream /orders/7
        pathType: ImplementationSpecific
        backend:
          service:
            name: app-svc
            port:
              number: 80
```

File: [yaml/ingress-nginx-rewrite.yaml](yaml/ingress-nginx-rewrite.yaml).

---

## Key fields / syntax

```yaml
apiVersion: networking.k8s.io/v1          # extensions/v1beta1 and networking.k8s.io/v1beta1 were removed in v1.22
kind: Ingress
metadata:
  name: shop
  namespace: prod
  annotations: {}                         # controller-specific knobs
spec:
  ingressClassName: nginx                 # which controller
  defaultBackend:                         # optional: unmatched requests
    service:
      name: fallback-svc
      port:
        number: 80
  tls:                                    # optional
  - hosts:
    - shop.example.com
    secretName: shop-tls
  rules:
  - host: shop.example.com                # optional; "*.example.com" wildcard allowed (quoted)
    http:
      paths:
      - path: /api
        pathType: Prefix                  # REQUIRED: Exact | Prefix | ImplementationSpecific
        backend:
          service:
            name: api-svc                 # v1: service.name (not serviceName)
            port:
              name: http                  # v1: port.number or port.name (not servicePort)
```

| File | Shows |
|---|---|
| [yaml/ingress-backends.yaml](yaml/ingress-backends.yaml) | Demo backends `app-svc`, `api-svc`, `fallback-svc` that echo pod name + URI |
| [yaml/ingress-single-backend.yaml](yaml/ingress-single-backend.yaml) | One Prefix `/` rule, no host |
| [yaml/ingress-path-fanout.yaml](yaml/ingress-path-fanout.yaml) | Paths → Services, Prefix vs Exact, longest match, port by name |
| [yaml/ingress-host-based.yaml](yaml/ingress-host-based.yaml) | Virtual hosts incl. wildcard host |
| [yaml/ingress-tls.yaml](yaml/ingress-tls.yaml) | TLS with a Secret, ssl-redirect annotation |
| [yaml/ingress-default-backend.yaml](yaml/ingress-default-backend.yaml) | `spec.defaultBackend` |
| [yaml/ingress-nginx-rewrite.yaml](yaml/ingress-nginx-rewrite.yaml) | rewrite-target with regex capture groups |
| [yaml/ingressclass.yaml](yaml/ingressclass.yaml) | IngressClass + default-class annotation |

---

## Imperative commands

`kubectl create ingress NAME --rule="host/path=service:port[,tls[=secret]]" [--rule=...] [--class=...] [--default-backend=svc:port] [--annotation key=value]`

| Piece | Meaning |
|---|---|
| path ending in `*` | `pathType: Prefix` (the `*` is stripped): `shop.example.com/api*` → `/api` Prefix |
| path without `*` | `pathType: Exact`: `shop.example.com/api` → `/api` Exact. Careful: `host/=svc:80` is Exact `/` = root only; use `host/*=svc:80` for a catch-all |
| no host | `--rule="/api*=api-svc:8080"` (rule applies to all hosts) |
| `svc:80` / `svc:http` | numeric → `port.number`, text → `port.name` |
| `,tls=secret` | adds a `tls` entry for that host with `secretName: secret`; `,tls` alone uses the controller's default certificate |
| repeated `--rule` with the same host | merged into one rule with several paths |
| `--default-backend=svc:port` | sets `spec.defaultBackend` |
| `--annotation k=v` | repeatable; e.g. `--annotation nginx.ingress.kubernetes.io/ssl-redirect=false` |

```bash
# single catch-all backend (Prefix /)
kubectl create ingress single --class=nginx --rule="/*=app-svc:80"

# fan-out on one host (Prefix) + an Exact path
kubectl create ingress fanout --class=nginx \
  --rule="shop.example.com/*=app-svc:80" \
  --rule="shop.example.com/api*=api-svc:http" \
  --rule="shop.example.com/api/health=fallback-svc:80"

# virtual hosts
kubectl create ingress vhosts --class=nginx \
  --rule="app.example.com/*=app-svc:80" \
  --rule="api.example.com/*=api-svc:8080"

# TLS with a Secret
kubectl create ingress secure --class=nginx --rule="secure.example.com/*=app-svc:80,tls=secure-tls"

# default backend + annotation
kubectl create ingress with-default --class=nginx \
  --default-backend=fallback-svc:80 \
  --rule="shop.example.com/api*=api-svc:8080" \
  --annotation nginx.ingress.kubernetes.io/ssl-redirect=false

# generate YAML instead (then edit: regex paths, extra annotations, ...)
kubectl create ingress fanout --class=nginx --rule="shop.example.com/api*=api-svc:http" \
  --dry-run=client -o yaml > ingress.yaml
```

Output of `kubectl create ingress demo --class=nginx --rule="shop.example.com/*=app-svc:80" --rule="shop.example.com/api*=api-svc:http,tls=shop-tls" --dry-run=client -o yaml` (trimmed):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo
spec:
  ingressClassName: nginx
  rules:
  - host: shop.example.com
    http:
      paths:
      - backend:
          service:
            name: app-svc
            port:
              number: 80
        path: /
        pathType: Prefix
      - backend:
          service:
            name: api-svc
            port:
              name: http
        path: /api
        pathType: Prefix
  tls:
  - hosts:
    - shop.example.com
    secretName: shop-tls
```

---

## Testing an Ingress

```bash
kubectl get ingress -A                                  # CLASS, HOSTS, ADDRESS (filled once the controller accepts it), PORTS
kubectl get svc -A | grep -i ingress                    # controller entry point, e.g. 80:31080/TCP,443:31443/TCP

# HTTP: put the hostname in the Host header
curl -s -H "Host: shop.example.com" http://<ADDRESS>/api
curl -s -H "Host: shop.example.com" http://<nodeIP>:<httpNodePort>/api          # via the controller's NodePort

# HTTPS: the certificate is chosen by SNI (= URL host), so use --resolve instead of -H Host
curl -sk --resolve secure.example.com:443:<ADDRESS> https://secure.example.com/
curl -sk --resolve secure.example.com:<httpsNodePort>:<nodeIP> https://secure.example.com:<httpsNodePort>/
curl -vk --resolve secure.example.com:443:<ADDRESS> https://secure.example.com/ 2>&1 | grep -i "subject:"   # which cert?

# No external reachability (laptop lab): port-forward to the controller Service
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80
curl -s -H "Host: shop.example.com" http://127.0.0.1:8080/api

# From inside the cluster
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- \
  curl -s -H "Host: shop.example.com" http://ingress-nginx-controller.ingress-nginx/api
```

If the task gives a URL or hostname (for example one already present in `/etc/hosts`), test exactly that.

---

## Troubleshooting

```bash
kubectl describe ingress <name> -n <ns>        # Rules -> Host / Path / Backends (Pod IPs or an <error: ...>), Events
kubectl get ingress <name> -n <ns> -o yaml     # class, pathType, port number vs name
kubectl get ingressclass                       # does the class exist? which one is (default)?
kubectl get svc <backend> -n <ns>              # Service name and PORT the Ingress must use
kubectl get endpointslices -n <ns> -l kubernetes.io/service-name=<backend>   # ready Pod IPs?
kubectl -n ingress-nginx get pods              # controller running?
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50      # admission / sync errors
```

| Symptom | Typical cause | Check |
|---|---|---|
| ADDRESS empty for minutes, nothing works | No controller for that class: missing/misspelled `ingressClassName`, no default class | `kubectl get ingressclass`, controller Pods |
| 404 from the controller | Host header mismatch, Exact vs Prefix, path typo, request sent without a Host header | `kubectl describe ingress`, your `curl -H` |
| 503 (Service Temporarily Unavailable) | Service missing/typo, no ready endpoints | Backends column, EndpointSlices, Pod readiness |
| 502 (Bad Gateway) | Endpoint port wrong or app not listening; backend expects HTTPS | Service `targetPort`, app logs, `backend-protocol` |
| Fake / wrong certificate | TLS Secret missing, other namespace, wrong type/keys, host not in `tls.hosts` | `kubectl get secret -n <ns>`, `kubectl describe ingress` |
| Unexpected 308 redirect to HTTPS | `tls` set → ingress-nginx redirects by default | use HTTPS or `ssl-redirect: "false"` |
| Request lands on the wrong backend | Longest-match / Exact-vs-Prefix precedence | path table above |
| Backend reachable via Service but not via Ingress | NetworkPolicy blocks the controller Pods | allow from the controller namespace (`kubernetes.io/metadata.name: ingress-nginx`) |

---

## Exam traps & tips

> **Exam tip:** `kubectl create ingress --rule="host/path=svc:port"` produces **Exact**. If the task says "and all sub-paths" or "path prefix", append `*`: `--rule="host/path*=svc:port"`.

> **Exam tip:** the backend port is the **Service** port. Service `80 → targetPort 8080` means `port.number: 80` (or the Service port name) in the Ingress — never 8080.

> **Exam tip:** set `ingressClassName` to the class the task (or `kubectl get ingressclass`) gives you. A perfect Ingress without a matching class is ignored.

- `pathType` is mandatory in `networking.k8s.io/v1`; `serviceName`/`servicePort` are the removed v1beta1 schema.
- Service and TLS Secret must be in the **same namespace** as the Ingress — no cross-namespace backends.
- Quote wildcard hosts: `host: "*.example.com"`.
- With `curl`, `-H "Host: ..."` tests HTTP routing; for HTTPS use `--resolve` (SNI).
- Annotation values are strings; `true` unquoted is a YAML boolean and is rejected.
- Editing vs recreating: `kubectl edit ingress` is fine; deleting + `kubectl create ingress` is often faster, but re-add any annotations the original had.
- The ADDRESS can take 30–60 s to appear — don't "fix" a correct Ingress while the controller is still syncing.

---

## Architect notes

- **Plan the Gateway API move:** the Ingress API is frozen and ingress-nginx is retired (no security fixes after March 2026). Inventory Ingresses and annotations, pick a supported controller or Gateway implementation, convert with `ingress2gateway`, run both side by side, then shift DNS.
- **Controller HA:** at least 2 replicas, a PodDisruptionBudget, anti-affinity/topology spread, autoscaling; `externalTrafficPolicy: Local` or PROXY protocol on its Service to keep real client IPs.
- **TLS automation:** cert-manager with ACME (HTTP-01/DNS-01), short-lived certificates, HSTS; wildcard certificates via DNS-01.
- **Separate classes/controllers** for internet-facing and internal traffic; restrict who may create Ingresses for which hosts (RBAC + admission policy), or hostnames can be hijacked across teams.
- **Annotations are a security and portability risk:** snippet-style annotations let tenants inject proxy config, and ingress-nginx had critical admission-webhook CVEs in 2025 ("IngressNightmare", e.g. CVE-2025-1974). Gateway API replaces many annotations with typed, portable filters.
- **Edge concerns** (WAF, rate limiting, auth, bot protection) usually live in the controller or a CDN in front — keep them declarative and observable (per-host/path metrics, access logs).

---

## Docs to bookmark

- Ingress: https://kubernetes.io/docs/concepts/services-networking/ingress/
- Ingress controllers: https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/
- `kubectl create ingress`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_ingress/
- Ingress API reference: https://kubernetes.io/docs/reference/kubernetes-api/service-resources/ingress-v1/
- Ingress NGINX retirement (blog, Nov 2025): https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/
- Gateway API (successor): https://kubernetes.io/docs/concepts/services-networking/gateway/

---

## Quick self-check

1. `--rule="shop.example.com/api=api:80"` — which `pathType` is generated, and does `/api/v1` match?
2. Paths `/foo` (Prefix) and `/foo/bar` (Exact). Where do `/foo/bar`, `/foo/bar/x` and `/foobar` go?
3. An Ingress has no `ingressClassName` and the cluster has no default IngressClass. What happens?
4. Where must the TLS Secret live, and which type and keys must it have?
5. Service `api` maps port 80 → targetPort 8080. Which port goes into the Ingress backend?
6. Why can `curl -k -H "Host: secure.example.com" https://<ip>/` show the wrong certificate?

<details><summary>Answers</summary>

1. `Exact`; `/api/v1` does not match (use `/api*` for Prefix).
2. `/foo/bar` → the Exact rule (longest match); `/foo/bar/x` → `/foo` Prefix (Exact does not cover sub-paths); `/foobar` → no match → default backend (Prefix matches whole path elements).
3. No controller picks it up (ADDRESS stays empty) unless a controller is configured to watch class-less Ingresses. Set `ingressClassName`.
4. Same namespace as the Ingress; `type: kubernetes.io/tls` with `tls.crt` and `tls.key` (`kubectl create secret tls`).
5. 80 (or the Service port name) — never the targetPort.
6. The certificate is selected by SNI from the URL host (`<ip>`), not by the Host header. Use `curl -k --resolve secure.example.com:443:<ip> https://secure.example.com/`.

</details>
