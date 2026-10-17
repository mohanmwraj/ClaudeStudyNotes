# Services and Networking — Practice Questions

> These are exam-style tasks modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

**How to use:** attempt each task against the clock before opening the solution. Ordered by how often the pattern shows up (🔥 High → ⚡ Medium → 🧊 Low). Each task uses its own namespace `sn-q<N>`.

**Lab prerequisites** (details in [00 Exam Overview and Setup](../00-Exam-Overview-and-Setup/README.md)):

- A CNI that **enforces** NetworkPolicy (prove it: apply a default-deny and check that traffic stops).
- For Ingress tasks: an Ingress controller with IngressClass `nginx` (ingress-nginx is retired but fine for practice). Set the address once:

```bash
INGRESS=<ADDRESS-of-the-Ingress>                  # LoadBalancer IP, or <nodeIP>:<httpNodePort> of the controller Service
# no direct reachability (laptop lab): port-forward the controller and use localhost
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 8443:443 &
INGRESS=127.0.0.1:8080
```

- For Q26–Q27 only: Gateway API CRDs + an implementation (see [05-gateway-api.md](05-gateway-api.md)).
- Run setup commands **from this chapter folder** (paths like `yaml/broken/...`). Output paths mimic the exam: `sudo mkdir -p /opt/course/{1..27} && sudo chown -R "$USER" /opt/course`.
- Solutions only rely on what exam hosts are guaranteed to have (kubectl, yq, curl, wget, man) plus busybox/curl **Pods** for in-cluster tests. Anything else (`openssl`, `helm` installs, `sudo`) appears only in lab setup steps.
- Clean up a task with `kubectl delete ns sn-q<N>` (extra namespaces are named in the task).

---

### Q1. Expose a Deployment with a ClusterIP Service
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Provide and troubleshoot access to applications via services

In namespace `sn-q1` (create it):

1. Create Deployment `frontend`, image `nginx:1.27`, 3 replicas, container port 80.
2. Expose it with a ClusterIP Service `frontend-svc` on port **8080** that forwards to container port 80.
3. From inside the cluster, fetch `http://frontend-svc.sn-q1:8080` and save the HTML to `/opt/course/1/index.html`.

<details><summary>Solution</summary>

```bash
kubectl create namespace sn-q1
kubectl -n sn-q1 create deployment frontend --image=nginx:1.27 --replicas=3 --port=80
kubectl -n sn-q1 expose deployment frontend --name=frontend-svc --port=8080 --target-port=80
kubectl -n sn-q1 get endpointslices -l kubernetes.io/service-name=frontend-svc   # 3 addresses

# long-lived client: kubectl exec output is clean, safe to redirect
kubectl -n sn-q1 run client --image=busybox:1.36 -- sleep 3600
kubectl -n sn-q1 wait --for=condition=Ready pod/client --timeout=60s
kubectl -n sn-q1 exec client -- wget -qO- --timeout=3 http://frontend-svc.sn-q1:8080 > /opt/course/1/index.html
```

**Verify:**

```bash
kubectl -n sn-q1 get svc frontend-svc -o jsonpath='{.spec.type} {.spec.ports[0].port}->{.spec.ports[0].targetPort}{"\n"}'   # ClusterIP 8080->80
grep -c "Welcome to nginx" /opt/course/1/index.html                                                                          # >= 1
```

</details>

### Q2. NodePort Service on a fixed port
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Provide and troubleshoot access to applications via services

Setup:

```bash
kubectl create namespace sn-q2
kubectl -n sn-q2 create deployment api --image=httpd:2.4 --replicas=2 --port=80
```

Create a NodePort Service `api-np` in `sn-q2` for Deployment `api`: Service port 80, container port 80, node port **30080**. Write the URL that reaches it from outside the cluster, using the first node's InternalIP, to `/opt/course/2/url.txt` (format `http://<ip>:30080`).

<details><summary>Solution</summary>

Route A — expose, then patch the nodePort (expose cannot set it):

```bash
kubectl -n sn-q2 expose deployment api --name=api-np --type=NodePort --port=80 --target-port=80
kubectl -n sn-q2 patch svc api-np -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'
```

Route B — `create service nodeport` sets the nodePort but its selector is `app=api-np`; fix it before applying:

```bash
kubectl -n sn-q2 create service nodeport api-np --tcp=80:80 --node-port=30080 --dry-run=client -o yaml > q2.yaml
# edit q2.yaml: selector app: api-np  ->  app: api
kubectl apply -f q2.yaml
```

Resulting Service (either route):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-np
  namespace: sn-q2
spec:
  type: NodePort
  selector:
    app: api
  ports:
  - name: http
    port: 80
    targetPort: 80
    nodePort: 30080
```

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$NODE_IP:30080" > /opt/course/2/url.txt
```

**Verify:**

```bash
kubectl -n sn-q2 get svc api-np                                        # PORT(S) 80:30080/TCP
kubectl -n sn-q2 get endpointslices -l kubernetes.io/service-name=api-np
curl -s "$(cat /opt/course/2/url.txt)"                                 # <h1>It works!</h1>
# node IPs not reachable from your machine (kind / Docker Desktop)? test from a Pod:
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -s "http://$NODE_IP:30080"
```

</details>

### Q3. Fix a Service that has no endpoints
**Frequency:** 🔥 High · **Est. time:** 4 min · **Competency:** Provide and troubleshoot access to applications via services

Setup: `kubectl apply -f yaml/broken/q03-svc-no-endpoints.yaml`

In `sn-q3`, Service `orders` should load-balance across the Pods of Deployment `orders`, but every request fails. Fix the **Service** (do not change the Deployment), then write the number of endpoint addresses to `/opt/course/3/endpoints.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q3 get endpointslices -l kubernetes.io/service-name=orders    # no addresses
kubectl -n sn-q3 get svc orders -o jsonpath='{.spec.selector}{"\n"}'        # {"app":"order","tier":"backend"}
kubectl -n sn-q3 get pods --show-labels                                      # app=orders,tier=backend  -> typo in the Service
kubectl -n sn-q3 set selector svc orders app=orders,tier=backend             # or: kubectl -n sn-q3 edit svc orders
kubectl -n sn-q3 get endpointslices -l kubernetes.io/service-name=orders \
  -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | wc -w > /opt/course/3/endpoints.txt
```

**Verify:**

```bash
cat /opt/course/3/endpoints.txt                                              # 2
kubectl -n sn-q3 run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://orders
```

</details>

### Q4. Fix a wrong targetPort and a wrong named port
**Frequency:** 🔥 High · **Est. time:** 5 min · **Competency:** Provide and troubleshoot access to applications via services

Setup: `kubectl apply -f yaml/broken/q04-svc-wrong-ports.yaml`

In `sn-q4`, Deployment `billing` runs nginx. Service `billing` (port 80) refuses connections, and Service `billing-named` (port 8080) does not deliver traffic either. Fix both Services without changing the Deployment or the Services' `port` values. `billing-named` must keep using a **named** targetPort.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q4 get pod -l app=billing -o jsonpath='{.items[0].spec.containers[0].ports}{"\n"}'
#   [{"containerPort":80,"name":"web","protocol":"TCP"}]
kubectl -n sn-q4 get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,TARGET:.spec.ports[0].targetPort
#   billing         80     8080   <- nothing listens on 8080
#   billing-named   8080   http   <- no container port is NAMED http
kubectl -n sn-q4 patch svc billing --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'
kubectl -n sn-q4 patch svc billing-named --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":"web"}]'
```

**Verify:**

```bash
kubectl -n sn-q4 run tmp --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -c 'wget -qO- --timeout=2 http://billing | head -n 4; wget -qO- --timeout=2 http://billing-named:8080 | head -n 4'
kubectl -n sn-q4 get endpointslices -l kubernetes.io/service-name=billing-named -o jsonpath='{.items[*].ports}{"\n"}'   # port 80
```

</details>

### Q5. NetworkPolicy: only the API may reach the database
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Demonstrate basic understanding of NetworkPolicies

Setup:

```bash
kubectl create namespace sn-q5
kubectl -n sn-q5 run db --image=redis:7.2 --labels=app=db --port=6379
kubectl -n sn-q5 expose pod db --port=6379
kubectl -n sn-q5 run api --image=busybox:1.36 --labels=app=api -- sleep 86400
kubectl -n sn-q5 run other --image=busybox:1.36 --labels=app=other -- sleep 86400
```

Create NetworkPolicy `db-allow-api` in `sn-q5`: Pods labelled `app=db` accept ingress **only** from Pods labelled `app=api` in the same namespace, on TCP 6379. Do not restrict egress.

<details><summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-api
  namespace: sn-q5
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 6379
```

```bash
kubectl apply -f q5.yaml
```

No separate default-deny is needed: selecting `app=db` with `policyTypes: [Ingress]` already isolates it.

**Verify:**

```bash
kubectl -n sn-q5 exec api   -- nc -zv -w 2 db 6379        # open
kubectl -n sn-q5 exec other -- nc -zv -w 2 db 6379        # timed out
kubectl -n sn-q5 describe netpol db-allow-api             # From PodSelector app=api, To Port 6379/TCP
```

</details>

### Q6. Default deny, then allow exactly one flow
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Demonstrate basic understanding of NetworkPolicies

Setup:

```bash
kubectl create namespace sn-q6
kubectl -n sn-q6 create deployment web --image=nginx:1.27-alpine
kubectl -n sn-q6 create deployment backend --image=nginx:1.27-alpine
kubectl -n sn-q6 expose deployment backend --port=80
kubectl -n sn-q6 run tester --image=busybox:1.36 --labels=app=tester -- sleep 86400
```

In `sn-q6`: (1) NetworkPolicy `default-deny-ingress` blocks all incoming traffic to every Pod in the namespace. (2) NetworkPolicy `backend-allow-web` lets the Pods of Deployment `web` reach the Pods of Deployment `backend` on TCP 80. Nothing else may reach `backend`.

<details><summary>Solution</summary>

`kubectl create deployment` labels Pods `app=<name>`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: sn-q6
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-web
  namespace: sn-q6
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 80
```

```bash
kubectl apply -f q6.yaml
```

**Verify:**

```bash
kubectl -n sn-q6 exec deploy/web -- wget -qO- --timeout=2 http://backend | head -n 4   # nginx page
kubectl -n sn-q6 exec tester -- wget -qO- --timeout=2 http://backend                   # download timed out
kubectl -n sn-q6 get netpol                                                            # 2 policies
```

</details>

### Q7. Make traffic work by labelling a Pod — do not touch the policies
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Demonstrate basic understanding of NetworkPolicies

Setup: `kubectl apply -f yaml/practice-setup/q07-netpol-label-pods.yaml`

In namespace `sn-q7`, Pod `newpod` must be able to connect to Service `web` on port 80 and Service `db` on port 6379. Several NetworkPolicies exist. Do **not** create, modify or delete any NetworkPolicy, and do not modify Pods `web` and `db`.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q7 get netpol                       # 5 policies incl. default-deny-all
kubectl -n sn-q7 describe netpol
#   web-ingress:       Pods app=web     <- From PodSelector web-access=true, To Port 80/TCP
#   db-ingress:        Pods app=db      <- From PodSelector db-access=true,  To Port 6379/TCP
#   web-client-egress: Pods web-access=true -> To app=web:80 + kube-dns:53
#   db-client-egress:  Pods db-access=true  -> To app=db:6379 + kube-dns:53
kubectl -n sn-q7 get pod newpod --show-labels     # app=newpod only
kubectl -n sn-q7 label pod newpod web-access=true db-access=true
```

The labels satisfy **both** ends: egress from `newpod` (incl. DNS) and ingress into `web`/`db`. Full walk-through: [04-network-policies.md](04-network-policies.md).

**Verify:**

```bash
kubectl -n sn-q7 exec newpod -- wget -qO- --timeout=2 http://web | head -n 4    # nginx page
kubectl -n sn-q7 exec newpod -- nc -zv -w 2 db 6379                             # open
kubectl -n sn-q7 get netpol --no-headers | wc -l                                # still 5
```

</details>

### Q8. Ingress with path-based routing
**Frequency:** 🔥 High · **Est. time:** 6 min · **Competency:** Use Ingress rules to expose applications

Setup:

```bash
kubectl create namespace sn-q8
kubectl -n sn-q8 create deployment shop --image=nginx:1.27 --port=80
kubectl -n sn-q8 expose deployment shop --port=80
kubectl -n sn-q8 create deployment cart --image=busybox:1.36 --port=80 -- \
  sh -c 'mkdir -p /www/cart && echo cart-ok > /www/cart/index.html && httpd -f -p 80 -h /www'
kubectl -n sn-q8 expose deployment cart --port=8080 --target-port=80
```

Create Ingress `shop-ingress` in `sn-q8` with IngressClass `nginx` for host `shop.example.com`:

- `/cart` and everything below it → Service `cart` (port 8080)
- everything else → Service `shop` (port 80)

<details><summary>Solution</summary>

```bash
kubectl -n sn-q8 create ingress shop-ingress --class=nginx \
  --rule="shop.example.com/*=shop:80" \
  --rule="shop.example.com/cart*=cart:8080"
```

Equivalent YAML:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-ingress
  namespace: sn-q8
spec:
  ingressClassName: nginx
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: shop
            port:
              number: 80
      - path: /cart
        pathType: Prefix
        backend:
          service:
            name: cart
            port:
              number: 8080
```

The path is forwarded unchanged (`/cart/` arrives at the cart Pod as `/cart/`), which is why the backend serves `/www/cart/index.html`.

**Verify:**

```bash
kubectl -n sn-q8 get ingress shop-ingress \
  -o jsonpath='{range .spec.rules[0].http.paths[*]}{.path} {.pathType} {.backend.service.name}:{.backend.service.port.number}{"\n"}{end}'
#   / Prefix shop:80
#   /cart Prefix cart:8080
kubectl -n sn-q8 describe ingress shop-ingress                                 # backends list Pod IPs
curl -s -H "Host: shop.example.com" http://$INGRESS/cart/                       # cart-ok
curl -s -H "Host: shop.example.com" http://$INGRESS/ | grep -i "<title>"        # Welcome to nginx!
```

</details>

### Q9. Host-based Ingress with TLS
**Frequency:** 🔥 High · **Est. time:** 7 min · **Competency:** Use Ingress rules to expose applications

Setup (the `openssl` step is lab-only — exam TLS tasks provide the files, and openssl is not guaranteed on exam hosts):

```bash
kubectl create namespace sn-q9
kubectl -n sn-q9 create deployment secure-app --image=nginx:1.27 --port=80
kubectl -n sn-q9 expose deployment secure-app --port=80
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/course/9/tls.key -out /opt/course/9/tls.crt \
  -subj "/CN=secure.example.com" -addext "subjectAltName=DNS:secure.example.com"
```

A certificate and key for `secure.example.com` are in `/opt/course/9/tls.crt` and `/opt/course/9/tls.key`.

1. Create a TLS Secret `secure-tls` from them in namespace `sn-q9`.
2. Create Ingress `secure` (class `nginx`) that terminates TLS for `secure.example.com` and sends all paths to `secure-app:80`.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q9 create secret tls secure-tls --cert=/opt/course/9/tls.crt --key=/opt/course/9/tls.key
kubectl -n sn-q9 create ingress secure --class=nginx --rule="secure.example.com/*=secure-app:80,tls=secure-tls"
```

Equivalent YAML:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure
  namespace: sn-q9
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - secure.example.com
    secretName: secure-tls
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: secure-app
            port:
              number: 80
```

**Verify:**

```bash
kubectl -n sn-q9 get ingress secure                                    # PORTS 80, 443
kubectl -n sn-q9 get secret secure-tls -o jsonpath='{.type}{"\n"}'     # kubernetes.io/tls
# HTTPS needs SNI -> --resolve (with the port-forward from the intro: port 8443 on 127.0.0.1)
curl -sk --resolve secure.example.com:8443:127.0.0.1 https://secure.example.com:8443/ | grep -i "<title>"
curl -vk --resolve secure.example.com:8443:127.0.0.1 https://secure.example.com:8443/ 2>&1 | grep -i "subject:"   # CN=secure.example.com
# with a LoadBalancer address instead: curl -sk --resolve secure.example.com:443:<ip> https://secure.example.com/
```

</details>

### Q10. Egress lockdown: database and DNS only
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Demonstrate basic understanding of NetworkPolicies

Setup:

```bash
kubectl create namespace sn-q10
kubectl -n sn-q10 run db --image=redis:7.2 --labels=app=db --port=6379
kubectl -n sn-q10 expose pod db --port=6379
kubectl -n sn-q10 create deployment api --image=busybox:1.36 -- sleep 86400
```

Create NetworkPolicy `api-egress` in `sn-q10` so that Pods labelled `app=api` can open connections **only** to Pods labelled `app=db` on TCP 6379, plus DNS (UDP and TCP 53) to the cluster DNS Pods (`k8s-app=kube-dns` in `kube-system`). Ingress to the api Pods must not be affected.

<details><summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
  namespace: sn-q10
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: db
    ports:
    - protocol: TCP
      port: 6379
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

```bash
kubectl apply -f q10.yaml
```

`policyTypes: [Egress]` is essential — without it, `Ingress` would be assumed as well and all ingress to the api Pods would be dropped.

**Verify:**

```bash
kubectl -n sn-q10 exec deploy/api -- nslookup db.sn-q10.svc.cluster.local      # resolves
kubectl -n sn-q10 exec deploy/api -- nc -zv -w 2 db 6379                       # open
kubectl -n sn-q10 exec deploy/api -- nc -zv -w 2 kubernetes.default 443        # timed out
kubectl -n sn-q10 describe netpol api-egress                                   # "Not affecting ingress traffic"
```

</details>

### Q11. Allow from one namespace and from labelled Pods in any namespace
**Frequency:** ⚡ Medium · **Est. time:** 7 min · **Competency:** Demonstrate basic understanding of NetworkPolicies

Setup:

```bash
kubectl create namespace sn-q11
kubectl create namespace sn-q11-mon
kubectl create namespace sn-q11-other
kubectl -n sn-q11 create deployment metrics-api --image=nginx:1.27-alpine
kubectl -n sn-q11 expose deployment metrics-api --port=80
kubectl -n sn-q11-mon run scraper --image=busybox:1.36 -- sleep 86400
kubectl -n sn-q11-other run probe --image=busybox:1.36 --labels=role=probe -- sleep 86400
kubectl -n sn-q11-other run random --image=busybox:1.36 --labels=role=random -- sleep 86400
```

In `sn-q11`, create NetworkPolicy `metrics-ingress` for Pods `app=metrics-api` that allows TCP 80 from (a) **any** Pod in namespace `sn-q11-mon` and (b) Pods labelled `role=probe` in **any** namespace. All other ingress to these Pods must be denied. Do not add labels to namespaces.

<details><summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: metrics-ingress
  namespace: sn-q11
spec:
  podSelector:
    matchLabels:
      app: metrics-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:                       # peer 1: the whole namespace, by its built-in name label
        matchLabels:
          kubernetes.io/metadata.name: sn-q11-mon
    - namespaceSelector: {}                    # peer 2: any namespace ...
      podSelector:                             # ... AND Pods with role=probe
        matchLabels:
          role: probe
    ports:
    - protocol: TCP
      port: 80
```

```bash
kubectl apply -f q11.yaml
```

Without `namespaceSelector: {}`, peer 2 would only match `role=probe` Pods in `sn-q11` itself.

**Verify:**

```bash
kubectl -n sn-q11-mon   exec scraper -- wget -qO- --timeout=2 http://metrics-api.sn-q11 | head -n 4   # allowed
kubectl -n sn-q11-other exec probe   -- wget -qO- --timeout=2 http://metrics-api.sn-q11 | head -n 4   # allowed
kubectl -n sn-q11-other exec random  -- wget -qO- --timeout=2 http://metrics-api.sn-q11               # timed out
```

</details>

### Q12. Fix a broken Ingress
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Use Ingress rules to expose applications

Setup: `kubectl apply -f yaml/broken/q12-ingress-broken.yaml`

In `sn-q12`, Ingress `catalog` should route `catalog.example.com/catalog` **and all sub-paths** (e.g. `/catalog/items`) to Service `catalog`, using IngressClass `nginx`. It does not work. The Deployment and Service are correct — fix the Ingress and keep its name.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q12 get svc catalog              # PORT(S) 80/TCP (port name http -> targetPort 8080)
kubectl -n sn-q12 describe ingress catalog     # backend catalogue:8080 -> error; no class
kubectl get ingressclass                       # nginx exists
```

Four bugs: no `ingressClassName`; Service name typo `catalogue`; port 8080 is the **container** port (the Service port is 80); `pathType: Exact` does not cover `/catalog/items`.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: catalog
  namespace: sn-q12
spec:
  ingressClassName: nginx
  rules:
  - host: catalog.example.com
    http:
      paths:
      - path: /catalog
        pathType: Prefix
        backend:
          service:
            name: catalog
            port:
              number: 80
```

```bash
kubectl apply -f q12.yaml          # or kubectl -n sn-q12 edit ingress catalog
# alternative: kubectl -n sn-q12 delete ingress catalog && \
#   kubectl -n sn-q12 create ingress catalog --class=nginx --rule="catalog.example.com/catalog*=catalog:80"
```

**Verify:**

```bash
kubectl -n sn-q12 describe ingress catalog                                # catalog:80 (<podIP>:8080)
curl -s -H "Host: catalog.example.com" http://$INGRESS/catalog/items       # items-ok
curl -s -H "Host: catalog.example.com" http://$INGRESS/catalog/            # catalog-ok
```

</details>

### Q13. Headless Service for a StatefulSet + DNS lookups to files
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Provide and troubleshoot access to applications via services

Setup: `kubectl apply -f yaml/practice-setup/q13-statefulset-no-service.yaml`

StatefulSet `db` in `sn-q13` (2 replicas, Pods `app=db`, container port 6379 named `redis`) references a governing Service `db-hl` that does not exist. Create it as a **headless** Service on port 6379. Then, from a Pod in `sn-q13`, save the `nslookup` output for `db-hl.sn-q13.svc.cluster.local` to `/opt/course/13/headless.txt` and for the stable DNS name of the first replica to `/opt/course/13/db-0.txt`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-hl
  namespace: sn-q13
spec:
  clusterIP: None
  selector:
    app: db
  ports:
  - name: redis
    port: 6379
    targetPort: redis
```

(Imperative start: `kubectl -n sn-q13 create service clusterip db-hl --clusterip=None --tcp=6379:6379 --dry-run=client -o yaml > q13.yaml`, then change the selector `app: db-hl` → `app: db`.)

```bash
kubectl apply -f q13.yaml
kubectl -n sn-q13 run dnsclient --image=busybox:1.36 -- sleep 3600
kubectl -n sn-q13 wait --for=condition=Ready pod/dnsclient --timeout=60s
kubectl -n sn-q13 exec dnsclient -- nslookup db-hl.sn-q13.svc.cluster.local > /opt/course/13/headless.txt
kubectl -n sn-q13 exec dnsclient -- nslookup db-0.db-hl.sn-q13.svc.cluster.local > /opt/course/13/db-0.txt
```

**Verify:**

```bash
kubectl -n sn-q13 get svc db-hl                       # CLUSTER-IP None
kubectl -n sn-q13 get pods -l app=db -o wide          # Pod IPs to compare
cat /opt/course/13/headless.txt                       # two Address lines = both Pod IPs (plus the server line)
cat /opt/course/13/db-0.txt                           # Name db-0.db-hl.sn-q13.svc.cluster.local -> the IP of db-0 only
```

</details>

### Q14. Multi-port Service with named targetPorts
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Provide and troubleshoot access to applications via services

Setup: `kubectl apply -f yaml/practice-setup/q14-shop-deployment.yaml`

In `sn-q14`, create ClusterIP Service `shop` for Deployment `shop` with two ports: `http` (port 80 → container port named `http-web`) and `metrics` (port 9100 → container port named `metrics`). Use **named** targetPorts.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop
  namespace: sn-q14
spec:
  selector:
    app: shop
  ports:
  - name: http
    port: 80
    targetPort: http-web
  - name: metrics
    port: 9100
    targetPort: metrics
```

```bash
kubectl apply -f q14.yaml
```

**Verify:**

```bash
kubectl -n sn-q14 get endpointslices -l kubernetes.io/service-name=shop -o jsonpath='{.items[0].ports}{"\n"}'   # 80 and 9090 resolved
kubectl -n sn-q14 run tmp --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -c 'wget -qO- --timeout=2 http://shop | head -n 4; wget -qO- --timeout=2 http://shop:9100/metrics'   # ... shop_up 1
```

</details>

### Q15. Expose a Pod in one command and reach it from another namespace
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Provide and troubleshoot access to applications via services

In namespace `sn-q15-a`, create Pod `echo` (image `nginx:1.27-alpine`, label `app=echo`, port 80) **and** a ClusterIP Service `echo` for it with a single command. From a Pod in namespace `sn-q15-b`, request the Service by its fully qualified name. Write the FQDN to `/opt/course/15/fqdn.txt` and the HTTP status code to `/opt/course/15/status.txt`.

<details><summary>Solution</summary>

```bash
kubectl create namespace sn-q15-a
kubectl create namespace sn-q15-b
kubectl -n sn-q15-a run echo --image=nginx:1.27-alpine --labels=app=echo --port=80 --expose
echo "echo.sn-q15-a.svc.cluster.local" > /opt/course/15/fqdn.txt
kubectl -n sn-q15-b run client --image=curlimages/curl:8.10.1 --command -- sleep 3600
kubectl -n sn-q15-b wait --for=condition=Ready pod/client --timeout=60s
kubectl -n sn-q15-b exec client -- curl -s -o /dev/null -w '%{http_code}' \
  http://echo.sn-q15-a.svc.cluster.local > /opt/course/15/status.txt
```

**Verify:**

```bash
kubectl -n sn-q15-a get svc echo -o jsonpath='{.spec.selector}{"\n"}'     # {"app":"echo"}
cat /opt/course/15/fqdn.txt /opt/course/15/status.txt                     # FQDN, 200
```

</details>

### Q16. Ingress with a default backend, an Exact path and an annotation
**Frequency:** ⚡ Medium · **Est. time:** 6 min · **Competency:** Use Ingress rules to expose applications

Setup:

```bash
kubectl create namespace sn-q16
kubectl -n sn-q16 create deployment fallback --image=nginx:1.27 --port=80
kubectl -n sn-q16 expose deployment fallback --port=80
kubectl -n sn-q16 create deployment status --image=busybox:1.36 --port=80 -- \
  sh -c 'mkdir -p /www && echo status-ok > /www/status && httpd -f -p 80 -h /www'
kubectl -n sn-q16 expose deployment status --port=80
```

Create Ingress `portal` in `sn-q16` (class `nginx`):

- exactly `/status` on host `portal.example.com` → Service `status:80` (sub-paths must **not** match)
- every other request → default backend `fallback:80`
- annotation `nginx.ingress.kubernetes.io/ssl-redirect: "false"`

<details><summary>Solution</summary>

```bash
kubectl -n sn-q16 create ingress portal --class=nginx \
  --default-backend=fallback:80 \
  --rule="portal.example.com/status=status:80" \
  --annotation nginx.ingress.kubernetes.io/ssl-redirect=false
```

No `*` after `/status` → `pathType: Exact`.

**Verify:**

```bash
kubectl -n sn-q16 get ingress portal -o jsonpath='{.spec.rules[0].http.paths[0].pathType} {.spec.defaultBackend.service.name} {.metadata.annotations}{"\n"}'
curl -s -H "Host: portal.example.com" http://$INGRESS/status                       # status-ok
curl -s -H "Host: portal.example.com" http://$INGRESS/ | grep -i "<title>"         # Welcome to nginx! (fallback)
curl -s -H "Host: portal.example.com" http://$INGRESS/status/x                     # NOT status-ok
```

</details>

### Q17. No endpoints because readiness fails
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Provide and troubleshoot access to applications via services

Setup: `kubectl apply -f yaml/broken/q17-readiness-no-endpoints.yaml`

Service `inventory` in `sn-q17` has no ready endpoints although its selector is correct. Find the cause and fix it **without** modifying the Service. Write a one-line explanation of the cause to `/opt/course/17/cause.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q17 get pods                                         # 0/1 Running
kubectl -n sn-q17 describe pod -l app=inventory | grep -i -A2 readiness
#   Readiness: http-get http://:8080/ready ...   Warning Unhealthy ... connection refused
kubectl -n sn-q17 get endpointslices -l kubernetes.io/service-name=inventory \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{"\n"}{end}'   # ready=false
kubectl -n sn-q17 patch deployment inventory --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'
echo "readinessProbe checked :8080/ready but nginx serves on :80, so Pods never became Ready and the Service had no ready endpoints" > /opt/course/17/cause.txt
```

**Verify:**

```bash
kubectl -n sn-q17 rollout status deployment inventory
kubectl -n sn-q17 get endpointslices -l kubernetes.io/service-name=inventory \
  -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{" "}{end}{"\n"}'          # true true
kubectl -n sn-q17 run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://inventory
```

</details>

### Q18. Fix a NetworkPolicy that is too permissive (OR instead of AND)
**Frequency:** ⚡ Medium · **Est. time:** 5 min · **Competency:** Demonstrate basic understanding of NetworkPolicies

Setup: `kubectl apply -f yaml/broken/q18-netpol-or-instead-of-and.yaml`

NetworkPolicy `allow-prometheus` in `sn-q18` should allow TCP 80 to Pods `app=metrics-api` **only** from Pods labelled `app=prometheus` that run in namespaces labelled `team=ops`. Right now Pod `grafana` in `sn-q18-ops` can connect too. Fix the policy and keep its name.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q18 describe netpol allow-prometheus
#   From:
#     NamespaceSelector: team=ops
#   From:
#     PodSelector: app=prometheus        <- two peers = OR
kubectl -n sn-q18 edit netpol allow-prometheus   # delete the "-" before podSelector, align it under namespaceSelector
```

Fixed spec:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus
  namespace: sn-q18
spec:
  podSelector:
    matchLabels:
      app: metrics-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: ops
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 80
```

**Verify:**

```bash
kubectl -n sn-q18 describe netpol allow-prometheus                                                   # ONE From: with both selectors
kubectl -n sn-q18-ops exec prometheus -- wget -qO- --timeout=2 http://metrics-api.sn-q18 | head -n 4  # allowed
kubectl -n sn-q18-ops exec grafana    -- wget -qO- --timeout=2 http://metrics-api.sn-q18             # timed out
kubectl -n sn-q18-dev exec prometheus -- wget -qO- --timeout=2 http://metrics-api.sn-q18             # timed out
```

</details>

### Q19. ExternalName Service
**Frequency:** ⚡ Medium · **Est. time:** 3 min · **Competency:** Provide and troubleshoot access to applications via services

In namespace `sn-q19` (create it), create Service `ext-db` that makes `ext-db.sn-q19.svc.cluster.local` an alias (CNAME) for `database.prod.example.com`. Save an `nslookup` of the Service name, run from a Pod in `sn-q19`, to `/opt/course/19/nslookup.txt`.

<details><summary>Solution</summary>

```bash
kubectl create namespace sn-q19
kubectl -n sn-q19 create service externalname ext-db --external-name=database.prod.example.com
kubectl -n sn-q19 run dnsclient --image=busybox:1.36 -- sleep 3600
kubectl -n sn-q19 wait --for=condition=Ready pod/dnsclient --timeout=60s
kubectl -n sn-q19 exec dnsclient -- nslookup ext-db.sn-q19.svc.cluster.local > /opt/course/19/nslookup.txt || true
```

`|| true`: the target name does not exist publicly, so `nslookup` may exit non-zero — the CNAME line is what counts.

**Verify:**

```bash
kubectl -n sn-q19 get svc ext-db                           # TYPE ExternalName, EXTERNAL-IP database.prod.example.com
grep -i "canonical name" /opt/course/19/nslookup.txt       # ext-db.sn-q19.svc.cluster.local canonical name = database.prod.example.com
```

</details>

### Q20. LoadBalancer Service that preserves the client IP
**Frequency:** ⚡ Medium · **Est. time:** 4 min · **Competency:** Provide and troubleshoot access to applications via services

Setup:

```bash
kubectl create namespace sn-q20
kubectl -n sn-q20 create deployment edge --image=nginx:1.27 --replicas=2 --port=80
```

Expose Deployment `edge` with a LoadBalancer Service `edge-lb` on port 80 that preserves the client source IP. Write the allocated nodePort to `/opt/course/20/nodeport.txt`. (Without an LB implementation EXTERNAL-IP stays `<pending>` — that is acceptable.)

<details><summary>Solution</summary>

```bash
kubectl -n sn-q20 expose deployment edge --name=edge-lb --type=LoadBalancer --port=80 --target-port=80
kubectl -n sn-q20 patch svc edge-lb -p '{"spec":{"externalTrafficPolicy":"Local"}}'
kubectl -n sn-q20 get svc edge-lb -o jsonpath='{.spec.ports[0].nodePort}' > /opt/course/20/nodeport.txt
```

**Verify:**

```bash
kubectl -n sn-q20 get svc edge-lb -o jsonpath='{.spec.type} {.spec.externalTrafficPolicy} {.spec.healthCheckNodePort}{"\n"}'   # LoadBalancer Local <port>
cat /opt/course/20/nodeport.txt
```

</details>

### Q21. ipBlock with an exception and an egress port range
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Demonstrate basic understanding of NetworkPolicies

Setup:

```bash
kubectl create namespace sn-q21
kubectl -n sn-q21 create deployment reports --image=nginx:1.27-alpine
```

Create NetworkPolicy `reports-net` in `sn-q21` for Pods `app=reports`:

- Ingress: only TCP 443 from `172.16.0.0/16`, except `172.16.99.0/24`.
- Egress: only TCP ports 32000–32100 to `10.50.0.0/24`, plus DNS (UDP and TCP 53) to any destination.

<details><summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: reports-net
  namespace: sn-q21
spec:
  podSelector:
    matchLabels:
      app: reports
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - ipBlock:
        cidr: 172.16.0.0/16
        except:
        - 172.16.99.0/24
    ports:
    - protocol: TCP
      port: 443
  egress:
  - to:
    - ipBlock:
        cidr: 10.50.0.0/24
    ports:
    - protocol: TCP
      port: 32000
      endPort: 32100
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

```bash
kubectl apply -f q21.yaml
```

**Verify:**

```bash
kubectl -n sn-q21 describe netpol reports-net          # IPBlock CIDR 172.16.0.0/16, Except 172.16.99.0/24
kubectl -n sn-q21 get netpol reports-net -o jsonpath='{.spec.egress[0].ports[0].port}-{.spec.egress[0].ports[0].endPort}{"\n"}'   # 32000-32100
```

</details>

### Q22. Service without a selector + a manual EndpointSlice
**Frequency:** 🧊 Low · **Est. time:** 7 min · **Competency:** Provide and troubleshoot access to applications via services

Setup:

```bash
kubectl create namespace sn-q22
kubectl -n sn-q22 run legacy-backend --image=busybox:1.36 --labels=app=legacy -- \
  sh -c 'mkdir -p /www && echo legacy-ok > /www/index.html && httpd -f -p 8080 -h /www'
```

Pretend `legacy-backend` is an external machine you only know by IP. In `sn-q22`, create Service `legacy-api` **without a selector** (port 80, port name `http`, targetPort 8080) and an EndpointSlice `legacy-api-1` that points the Service at the Pod's current IP on port 8080. `http://legacy-api.sn-q22` must return `legacy-ok`.

<details><summary>Solution</summary>

```bash
IP=$(kubectl -n sn-q22 get pod legacy-backend -o jsonpath='{.status.podIP}'); echo "$IP"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: legacy-api
  namespace: sn-q22
spec:
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-api-1
  namespace: sn-q22
  labels:
    kubernetes.io/service-name: legacy-api
    endpointslice.kubernetes.io/managed-by: cluster-admins
addressType: IPv4
ports:
- name: http
  protocol: TCP
  port: 8080
endpoints:
- addresses:
  - "$IP"
  conditions:
    ready: true
EOF
```

The EndpointSlice port **name** must equal the Service port name (`http`), and its `port` is the backend port (8080).

**Verify:**

```bash
kubectl -n sn-q22 get endpointslices -l kubernetes.io/service-name=legacy-api         # <IP>, port 8080
kubectl -n sn-q22 run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://legacy-api   # legacy-ok
```

</details>

### Q23. Session affinity and port-forward
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Provide and troubleshoot access to applications via services

Setup:

```bash
kubectl create namespace sn-q23
kubectl -n sn-q23 create deployment sticky --image=busybox:1.36 --replicas=3 --port=8080 -- \
  sh -c 'mkdir -p /www && hostname > /www/index.html && httpd -f -p 8080 -h /www'
kubectl -n sn-q23 run client --image=busybox:1.36 -- sleep 3600
```

Create Service `sticky` (port 80 → 8080) with `ClientIP` session affinity and a stickiness timeout of 600 seconds. Then use `kubectl port-forward` on the Service (local port 8088) to save one response to `/opt/course/23/pf.txt`.

<details><summary>Solution</summary>

```bash
kubectl -n sn-q23 expose deployment sticky --port=80 --target-port=8080 --session-affinity=ClientIP
kubectl -n sn-q23 patch svc sticky -p '{"spec":{"sessionAffinityConfig":{"clientIP":{"timeoutSeconds":600}}}}'
kubectl -n sn-q23 port-forward svc/sticky 8088:80 > /dev/null &
sleep 2
curl -s http://127.0.0.1:8088 > /opt/course/23/pf.txt
kill %1
```

`port-forward` always tunnels into **one** Pod and bypasses Service load balancing — it does not test affinity; the loop below does.

**Verify:**

```bash
kubectl -n sn-q23 get svc sticky -o jsonpath='{.spec.sessionAffinity} {.spec.sessionAffinityConfig.clientIP.timeoutSeconds}{"\n"}'   # ClientIP 600
for i in 1 2 3 4 5; do kubectl -n sn-q23 exec client -- wget -qO- --timeout=2 http://sticky; done                                   # same Pod name 5x
cat /opt/course/23/pf.txt                                                                                                         # a sticky-... Pod name
```

</details>

### Q24. Strip a path prefix with an ingress-nginx annotation
**Frequency:** 🧊 Low · **Est. time:** 6 min · **Competency:** Use Ingress rules to expose applications

Setup:

```bash
kubectl create namespace sn-q24
kubectl -n sn-q24 create deployment legacy-app --image=nginx:1.27 --port=80
kubectl -n sn-q24 expose deployment legacy-app --port=80
```

Create Ingress `rewrite` in `sn-q24` (class `nginx`) so that `http://apps.example.com/legacy/<anything>` is served by `legacy-app:80` as `/<anything>` — e.g. `/legacy/` → `/` and `/legacy/index.html` → `/index.html`.

<details><summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rewrite
  namespace: sn-q24
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: "/$2"
spec:
  ingressClassName: nginx
  rules:
  - host: apps.example.com
    http:
      paths:
      - path: "/legacy(/|$)(.*)"
        pathType: ImplementationSpecific
        backend:
          service:
            name: legacy-app
            port:
              number: 80
```

```bash
kubectl apply -f q24.yaml
```

Without the rewrite, nginx would look for `/usr/share/nginx/html/legacy/` and answer 404.

**Verify:**

```bash
curl -s -H "Host: apps.example.com" http://$INGRESS/legacy/ | grep -i "<title>"             # Welcome to nginx!
curl -s -H "Host: apps.example.com" http://$INGRESS/legacy/index.html | grep -i "<title>"   # Welcome to nginx!
```

</details>

### Q25. Custom DNS settings for a Pod
**Frequency:** 🧊 Low · **Est. time:** 4 min · **Competency:** Provide and troubleshoot access to applications via services

In namespace `sn-q25` (create it), create Pod `custom-dns` (image `busybox:1.36`, command `sleep 3600`) that keeps cluster DNS but additionally searches `corp.example.com` and uses `ndots: 2`. Save its `/etc/resolv.conf` to `/opt/course/25/resolv.conf`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-dns
  namespace: sn-q25
spec:
  dnsPolicy: ClusterFirst            # keep cluster DNS; dnsConfig is merged in
  dnsConfig:
    searches:
    - corp.example.com
    options:
    - name: ndots
      value: "2"                     # string
  containers:
  - name: main
    image: busybox:1.36
    command: ["sleep", "3600"]
```

```bash
kubectl create namespace sn-q25
kubectl apply -f q25.yaml
kubectl -n sn-q25 wait --for=condition=Ready pod/custom-dns --timeout=60s
kubectl -n sn-q25 exec custom-dns -- cat /etc/resolv.conf > /opt/course/25/resolv.conf
```

**Verify:**

```bash
cat /opt/course/25/resolv.conf
#   nameserver <kube-dns ClusterIP>
#   search sn-q25.svc.cluster.local svc.cluster.local cluster.local ... corp.example.com
#   options ndots:2
kubectl -n sn-q25 exec custom-dns -- nslookup kubernetes.default.svc.cluster.local    # cluster DNS still works
```

</details>

### Q26. Gateway API: Gateway + HTTPRoute (bonus)
**Frequency:** 🧊 Low · **Est. time:** 8 min · **Competency:** Use Ingress rules to expose applications (bonus: Gateway API — not named in the CKAD curriculum)

Prerequisite: Gateway API CRDs and an implementation; `kubectl get gatewayclass` must list a class. Practise it with exam constraints: in the CKAD only https://kubernetes.io/docs/concepts/services-networking/gateway/ and `kubectl explain` would be available (`gateway-api.sigs.k8s.io` is allowed for the CKA only).

Setup:

```bash
GWC=$(kubectl get gatewayclass -o jsonpath='{.items[0].metadata.name}'); echo "$GWC"
kubectl create namespace sn-q26
kubectl -n sn-q26 create deployment web --image=nginx:1.27 --port=80
kubectl -n sn-q26 expose deployment web --port=80
kubectl -n sn-q26 create deployment api --image=busybox:1.36 --port=8080 -- \
  sh -c 'mkdir -p /www/api && echo api-ok > /www/api/index.html && httpd -f -p 8080 -h /www'
kubectl -n sn-q26 expose deployment api --port=8080
```

In `sn-q26`, create Gateway `web-gw` using the cluster's GatewayClass with one HTTP listener named `http` on port 80 that accepts Routes from the same namespace only. Create HTTPRoute `web-route` for host `gw.example.com`: path prefix `/api` → `api:8080`, everything else → `web:80`.

<details><summary>Solution</summary>

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gw
  namespace: sn-q26
spec:
  gatewayClassName: eg                  # replace with the value of $GWC
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: sn-q26
spec:
  parentRefs:
  - name: web-gw
    sectionName: http
  hostnames:
  - gw.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api
      port: 8080
  - backendRefs:
    - name: web
      port: 80
```

```bash
kubectl apply -f q26.yaml
```

**Verify:**

```bash
kubectl -n sn-q26 get gateway web-gw                                    # PROGRAMMED True + ADDRESS
kubectl -n sn-q26 describe httproute web-route | grep -E -A2 "Accepted|ResolvedRefs"
GW=$(kubectl -n sn-q26 get gateway web-gw -o jsonpath='{.status.addresses[0].value}')
curl -s -H "Host: gw.example.com" http://$GW/api/                       # api-ok
curl -s -H "Host: gw.example.com" http://$GW/ | grep -i "<title>"       # Welcome to nginx!
```

</details>

### Q27. Gateway API: canary weights with a header override (bonus)
**Frequency:** 🧊 Low · **Est. time:** 7 min · **Competency:** Use Ingress rules to expose applications (bonus: Gateway API — not named in the CKAD curriculum)

Setup (after Q26):

```bash
for v in v1 v2; do
  kubectl -n sn-q26 create deployment checkout-$v --image=busybox:1.36 --port=8080 -- \
    sh -c "mkdir -p /www && echo $v > /www/index.html && httpd -f -p 8080 -h /www"
  kubectl -n sn-q26 expose deployment checkout-$v --port=80 --target-port=8080
done
```

Create HTTPRoute `checkout` in `sn-q26`, attached to `web-gw`, for host `checkout.example.com`: requests carrying header `x-canary: true` always go to `checkout-v2`; all other requests are split 80/20 between `checkout-v1` and `checkout-v2`.

<details><summary>Solution</summary>

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: checkout
  namespace: sn-q26
spec:
  parentRefs:
  - name: web-gw
  hostnames:
  - checkout.example.com
  rules:
  - matches:
    - headers:
      - name: x-canary
        value: "true"
    backendRefs:
    - name: checkout-v2
      port: 80
  - backendRefs:
    - name: checkout-v1
      port: 80
      weight: 80
    - name: checkout-v2
      port: 80
      weight: 20
```

```bash
kubectl apply -f q27.yaml
```

The header rule wins for matching requests (a header match is more specific than the catch-all rule).

**Verify:**

```bash
curl -s -H "Host: checkout.example.com" -H "x-canary: true" http://$GW/                                 # v2, every time
for i in $(seq 1 50); do curl -s -H "Host: checkout.example.com" http://$GW/; done | sort | uniq -c     # roughly 40 v1 / 10 v2
```

</details>

---

## Must-know summary

- `kubectl expose` copies the selector from the object; `kubectl create service <type> <name>` always sets `app=<name>` — fix it with `kubectl set selector`.
- Always pass `--target-port`: `targetPort` defaults to `port`. `kubectl expose` cannot set `nodePort` (patch it, or use `create service nodeport --node-port`).
- After creating or fixing a Service, check `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` before anything else: no addresses = selector or readiness problem.
- Clients call `port`, Pods receive on `targetPort` (number or containerPort **name**), outsiders use `nodePort` (30000–32767); `containerPort` is informational.
- DNS: `<svc>.<ns>.svc.cluster.local`; short names work only in the same namespace; headless/StatefulSet Pods: `<pod>.<svc>.<ns>.svc.cluster.local`; ExternalName = CNAME.
- Test from a busybox/curl Pod in the right namespace with the right labels and short timeouts: refused = reached but nothing there; timeout = dropped (policy).
- Ingress v1: `ingressClassName`, mandatory `pathType`, `backend.service.name` + `port.number|name` — the **Service** port, Service and Secret in the same namespace.
- `kubectl create ingress --rule="host/path*=svc:port,tls=secret"`: `*` → Prefix, no `*` → Exact (even `host/` alone is Exact `/`).
- Prefix matches whole path elements (`/foo` ≠ `/foobar`); the longest match wins; Exact beats Prefix on a tie.
- TLS: `kubectl create secret tls`, `tls.hosts` must match `rules[].host`; test HTTPS with `curl -k --resolve host:443:<ip>`.
- NetworkPolicy: a Pod is isolated per direction once any policy selects it; policies are additive allow-lists; both source egress and destination ingress must allow.
- One `from` element with `namespaceSelector` + `podSelector` = AND; separate `-` elements = OR. Confirm with `kubectl describe netpol`.
- Write `policyTypes` explicitly; when restricting egress, allow DNS on UDP **and** TCP 53.
- Select namespaces by name with `kubernetes.io/metadata.name`; "don't touch the policies" tasks are solved by labelling Pods (or namespaces).
- Gateway API (bonus): GatewayClass → Gateway (listeners, allowedRoutes) → HTTPRoute (matches, filters, weighted backendRefs); ReferenceGrant for cross-namespace backends.
