# Services and Networking — Command Reference

Grouped by job. Add `-n <namespace>` to every command when the task names a namespace (or set it once: `kubectl config set-context --current --namespace=<ns>`). Placeholders are in `<angle brackets>`.

---

## Create — workloads to expose (quick)

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=2 --port=80        # Deployment, Pods labelled app=web
kubectl create deployment api --image=busybox:1.36 --port=8080 -- sh -c 'mkdir -p /www && echo api-ok > /www/index.html && httpd -f -p 8080 -h /www'   # tiny HTTP server on 8080
kubectl run nginx --image=nginx:1.27 --port=80                                  # single Pod, labelled run=nginx
kubectl run nginx --image=nginx:1.27 --port=80 --expose                         # Pod + ClusterIP Service "nginx" (selector run=nginx)
kubectl run db --image=redis:7.2 --labels=app=db --port=6379                    # Pod with explicit labels
```

## Create — Services

```bash
kubectl expose deployment web --port=80 --target-port=80                        # ClusterIP; selector copied from the Deployment
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80          # NodePort (random nodePort)
kubectl expose deployment web --name=web-lb --type=LoadBalancer --port=80 --target-port=80      # LoadBalancer (+ nodePort + ClusterIP)
kubectl expose deployment web --name=web-hl --cluster-ip=None --port=80 --target-port=80        # headless
kubectl expose deployment web --name=web-sticky --port=80 --session-affinity=ClientIP           # session affinity
kubectl expose deployment web --name=web-udp --port=514 --protocol=UDP                          # UDP Service
kubectl expose pod nginx --name=nginx-svc --port=80 --target-port=80            # selector = the Pod's labels
kubectl expose service web --name=web-alt --port=8080 --target-port=80          # new Service from an existing Service's selector
kubectl expose deployment web --port=80 --selector=app=web,tier=frontend        # override the inferred selector
kubectl create service clusterip web --tcp=80:8080                              # selector app=web, port name "80-8080"
kubectl create service clusterip shop --tcp=80:80,9090:9090                     # multi-port (auto-named)
kubectl create service clusterip web-hl --clusterip=None --tcp=80:80            # headless via create service
kubectl create service nodeport web-np --tcp=80:80 --node-port=30080            # fixed nodePort (selector app=web-np!)
kubectl create service loadbalancer web-lb --tcp=80:80                          # LoadBalancer (selector app=web-lb!)
kubectl create service externalname my-db --external-name=db.example.com        # CNAME alias
kubectl apply -f yaml/svc-without-selector-endpointslice.yaml                   # selector-less Service + manual EndpointSlice
```

## Create — Ingress and TLS

```bash
kubectl create ingress single --class=nginx --rule="/*=app-svc:80"                                  # catch-all, Prefix /
kubectl create ingress exact --class=nginx --rule="shop.example.com/status=status-svc:80"           # no * = Exact
kubectl create ingress fanout --class=nginx --rule="shop.example.com/*=app-svc:80" --rule="shop.example.com/api*=api-svc:8080"   # path fan-out
kubectl create ingress named-port --class=nginx --rule="shop.example.com/api*=api-svc:http"         # Service port by name
kubectl create ingress vhosts --class=nginx --rule="app.example.com/*=app-svc:80" --rule="api.example.com/*=api-svc:8080"        # host-based
kubectl create ingress secure --class=nginx --rule="secure.example.com/*=app-svc:80,tls=secure-tls" # TLS with a Secret
kubectl create ingress secure-default-cert --class=nginx --rule="secure.example.com/*=app-svc:80,tls" # TLS, controller default cert
kubectl create ingress with-default --class=nginx --default-backend=fallback-svc:80 --rule="shop.example.com/api*=api-svc:8080"  # defaultBackend
kubectl create ingress annotated --class=nginx --rule="shop.example.com/*=app-svc:80" --annotation nginx.ingress.kubernetes.io/ssl-redirect=false   # annotation
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=secure.example.com" -addext "subjectAltName=DNS:secure.example.com"   # self-signed cert (LAB ONLY: openssl is not guaranteed on exam hosts)
kubectl create secret tls secure-tls --cert=tls.crt --key=tls.key               # TLS Secret (type kubernetes.io/tls)
```

## Create — NetworkPolicy (no generator: apply YAML)

```bash
kubectl apply -f yaml/netpol-default-deny-ingress.yaml                         # from a file
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
# ^ inline heredoc: quickest way to type a short policy in the terminal
kubectl explain networkpolicy.spec.ingress.from --recursive                    # field names when memory fails
```

## Generate YAML (dry-run)

```bash
kubectl expose deployment web --port=80 --target-port=8080 --dry-run=client -o yaml > svc.yaml                  # Service skeleton
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --dry-run=client -o yaml > svc-np.yaml    # then add nodePort: under ports
kubectl create service nodeport web-np --tcp=80:8080 --node-port=30080 --dry-run=client -o yaml > svc-np.yaml   # nodePort included
kubectl create service clusterip web-hl --clusterip=None --tcp=80:80 --dry-run=client -o yaml > svc-hl.yaml     # headless skeleton
kubectl create ingress fanout --class=nginx --rule="shop.example.com/api*=api-svc:8080" --dry-run=client -o yaml > ing.yaml   # Ingress skeleton
kubectl create secret tls secure-tls --cert=tls.crt --key=tls.key --dry-run=client -o yaml > tls-secret.yaml    # Secret manifest
kubectl run client --image=busybox:1.36 --labels=app=frontend --dry-run=client -o yaml -- sleep 3600 > client.yaml   # labelled test Pod
```

## Modify

```bash
kubectl patch svc web-np -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'         # set/change nodePort (ports merge on "port")
kubectl patch svc web -p '{"spec":{"type":"NodePort"}}'                                  # change type
kubectl patch svc web --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'   # fix targetPort (number)
kubectl patch svc web --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":"http"}]' # targetPort by name
kubectl patch svc web -p '{"spec":{"externalTrafficPolicy":"Local"}}'                    # NodePort/LB only
kubectl patch svc web -p '{"spec":{"sessionAffinity":"ClientIP"}}'                       # sticky sessions
kubectl set selector svc web app=web,tier=frontend                                       # replace a Service selector
kubectl edit svc web                                                                     # interactive edit
kubectl get svc web -o yaml > svc.yaml && kubectl replace --force -f svc.yaml            # recreate (immutable fields, e.g. clusterIP)
kubectl edit ingress fanout                                                              # fix rules / class / ports
kubectl annotate ingress fanout nginx.ingress.kubernetes.io/ssl-redirect="false" --overwrite   # add/change an annotation
kubectl label pod newpod web-access=true db-access=true                                  # fit a Pod to existing policies
kubectl label pod newpod role-                                                           # remove a label
kubectl label ns monitoring team=ops                                                     # namespace label for namespaceSelector
kubectl patch deploy web -p '{"spec":{"template":{"metadata":{"labels":{"web-access":"true"}}}}}'   # label future Pods (rollout)
kubectl edit netpol api-policy                                                           # fix AND/OR, ports, selectors
```

## Inspect

```bash
kubectl get svc -o wide                                                    # TYPE, CLUSTER-IP, EXTERNAL-IP, PORT(S), SELECTOR
kubectl get svc web -o jsonpath='{.spec.selector}{"\n"}'                   # the selector only
kubectl get svc web -o jsonpath='{.spec.ports}{"\n"}'                      # port / targetPort / nodePort / protocol
kubectl get svc web -o jsonpath='{.spec.ports[0].nodePort}{"\n"}'          # the allocated nodePort
kubectl get svc web -o jsonpath='{.spec.clusterIP}{"\n"}'                  # ClusterIP (None = headless)
kubectl describe svc web                                                   # Selector, TargetPort, Endpoints, Events
kubectl get endpointslices -l kubernetes.io/service-name=web               # endpoint addresses + ports
kubectl get endpointslices -l kubernetes.io/service-name=web -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{"\n"}{end}'   # readiness per endpoint
kubectl get endpointslices -l kubernetes.io/service-name=web -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | wc -w   # count endpoints
kubectl get endpoints web                                                  # legacy view (deprecated v1.33+, prints a warning)
kubectl get pods -l app=web -o wide --show-labels                          # Pods the selector should match, IPs, labels
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].ports}{"\n"}'      # containerPorts and their names
kubectl get ingress -A                                                     # CLASS, HOSTS, ADDRESS, PORTS
kubectl describe ingress fanout                                            # rules, backends with Pod IPs, TLS, events
kubectl get ingress fanout -o jsonpath='{.spec.rules[*].http.paths[*].pathType}{"\n"}'   # pathTypes
kubectl get ingressclass                                                   # available classes (and the default)
kubectl get secret secure-tls -o jsonpath='{.type}{"\n"}'                  # kubernetes.io/tls?
kubectl get netpol -A                                                      # all policies, POD-SELECTOR column
kubectl describe netpol -n prod                                            # rules in plain words (From blocks = OR)
kubectl get netpol api-policy -o yaml                                      # exact YAML (AND/OR by indentation)
kubectl get ns --show-labels                                               # namespace labels (kubernetes.io/metadata.name)
kubectl get nodes -o wide                                                  # node InternalIPs for NodePort tests
kubectl explain service.spec.ports                                         # field docs
kubectl explain ingress.spec.rules.http.paths.backend                      # field docs
```

## Verify connectivity

```bash
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://web          # HTTP via Service name
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://web.prod:80  # other namespace
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget --spider --timeout=2 http://web      # reachability only
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nc -zv -w 2 db 6379                       # TCP port check
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -s -o /dev/null -w '%{http_code}\n' http://web   # status code
kubectl run tmp --rm -it -n prod --labels=app=frontend --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://api  # test AS a labelled Pod
kubectl exec client -- wget -qO- --timeout=2 http://web > /opt/course/1/out.html                           # clean output for files
kubectl exec -n prod deploy/web -- wget -qO- --timeout=2 http://api                                        # from an app Pod (if it has wget)
curl -s http://<nodeIP>:30080                                                                              # NodePort from outside
curl -s -H "Host: shop.example.com" http://<ingress-address>/api                                           # Ingress host routing
curl -sk --resolve secure.example.com:443:<ingress-ip> https://secure.example.com/                         # Ingress TLS (SNI)
kubectl port-forward svc/web 8080:80                                                                       # local 8080 -> Service (one Pod)
kubectl port-forward svc/web 8080:80 --address 0.0.0.0                                                     # listen on all interfaces
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80                                 # reach the Ingress controller locally
```

## DNS

```bash
kubectl run dns --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.prod.svc.cluster.local       # Service A record
kubectl run dns --rm -it --image=busybox:1.36 --restart=Never -- nslookup web-hl.prod.svc.cluster.local    # headless: one IP per ready Pod
kubectl run dns --rm -it --image=busybox:1.36 --restart=Never -- nslookup web-sts-0.web-hl.prod.svc.cluster.local   # StatefulSet Pod record
kubectl run dns --rm -it --image=busybox:1.36 --restart=Never -- nslookup -type=srv _http._tcp.web.prod.svc.cluster.local   # SRV for a named port
kubectl run dns --rm -it --image=busybox:1.36 --restart=Never -- nslookup my-db.prod.svc.cluster.local     # ExternalName -> CNAME
kubectl exec client -- cat /etc/resolv.conf                                  # nameserver, search domains, ndots
kubectl exec client -- nslookup kubernetes.default                           # is cluster DNS working at all?
kubectl -n kube-system get svc kube-dns                                      # cluster DNS ClusterIP
kubectl -n kube-system get pods -l k8s-app=kube-dns                          # CoreDNS Pods
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50                    # CoreDNS logs
kubectl -n kube-system get configmap coredns -o yaml                         # Corefile
```

## Debug

```bash
kubectl describe pod <pod> | grep -i -A3 readiness                           # failing readiness = no ready endpoints
kubectl get events -n prod --sort-by=.lastTimestamp | tail -n 20             # recent events
kubectl debug -it <pod> --image=busybox:1.36 -- netstat -tln                 # which address/port the app really listens on
kubectl debug -it <pod> --image=busybox:1.36 -- wget -qO- --timeout=2 http://127.0.0.1:8080   # test from inside the Pod's netns
kubectl logs <pod> --tail=50                                                 # app errors (bind failures, crashes)
kubectl -n ingress-nginx get pods                                            # Ingress controller healthy?
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50      # Ingress sync / admission errors
kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx                  # which clusters still run ingress-nginx
kubectl -n kube-system get ds kube-proxy                                     # kube-proxy running on all nodes?
kubectl -n kube-system get configmap kube-proxy -o yaml | grep -i "mode"     # proxy mode (kubeadm clusters; "" = default iptables)
kubectl -n kube-system logs ds/kube-proxy | grep -iE "proxier|proxy mode|using (iptables|ipvs|nftables)"   # which proxier is in use
```

## Gateway API (bonus)

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/<version>/standard-install.yaml   # CRDs
kubectl api-resources --api-group=gateway.networking.k8s.io                  # installed kinds and versions
kubectl get gatewayclass                                                     # ACCEPTED = a controller owns it
kubectl get gateway -A                                                       # ADDRESS, PROGRAMMED
kubectl get httproute -A                                                     # HOSTNAMES
kubectl describe httproute <route> -n <ns>                                   # Accepted / ResolvedRefs + reason
kubectl get referencegrant -A                                                # cross-namespace permissions
kubectl explain httproute.spec.rules --recursive                             # schema help
ingress2gateway print --providers=ingress-nginx -A > gateway.yaml            # convert existing Ingresses
```

## Cleanup

```bash
kubectl delete svc web web-np web-lb web-hl                                  # Services (Pods unaffected)
kubectl delete ingress fanout secure                                         # Ingresses
kubectl delete secret secure-tls                                             # TLS Secret
kubectl delete netpol --all -n netpol-demo                                   # all policies in a namespace (lab only!)
kubectl delete pod tmp --force --grace-period=0                              # stuck test Pod
kubectl delete -f yaml/test-pods.yaml                                        # NetworkPolicy lab
kubectl delete ns sn-q1 sn-q2 sn-q3                                          # practice namespaces
```
