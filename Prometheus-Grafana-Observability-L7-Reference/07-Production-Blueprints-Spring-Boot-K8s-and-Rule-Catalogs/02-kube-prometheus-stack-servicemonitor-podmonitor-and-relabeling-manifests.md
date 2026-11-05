# 02 · kube-prometheus-stack: ServiceMonitor, PodMonitor and Relabeling Manifests

> **Folder 07 — Production Blueprints: Spring Boot, Kubernetes and Rule Catalogs · File 2 of 3.**
> Pinned to **Prometheus Operator v0.94.2** and **kube-prometheus-stack chart 92.18.0** (appVersion v0.94.2; default Prometheus image `v3.15.1-distroless`), with relabel semantics of **Prometheus v3.15.1**.
> Labels: **[D]** documented / read in pinned source · **[M]** measured · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L6 `servicemonitor_lab.py` | **Port.** Ports the operator's ServiceMonitor and PodMonitor relabel-chain generators (`pkg/prometheus/promcfg.go` @ v0.94.2) and executes them with Folder 01's oracle-tested relabel engine on synthetic discovery targets. **Result.** The 18-rule chain keeps exactly the 3 running `management` endpoints out of 10 and produces `namespace/service/pod/container/endpoint/job` plus target labels. The `EndpointSlice` role gives identical labels, but a hand-written `__meta_kubernetes_endpoint_*` rule empties it. **Misconfigurations.** A port-name typo or selector mismatch yields 0 targets, and `filterRunning: false` scrapes a Failed pod. **Sharding.** `hashmod` across 3 shards owns each of 300 targets exactly once. **PodMonitor.** Its job label is `<ns>/<name>` | <1 s |

**Verification.**
- **Port and engine.** The relabel chains are line-by-line ports of `generateServiceMonitorConfig`, `generatePodMonitorConfig` and `appendShardingRelabelingWithLabel` at v0.94.2. They run through `relabel_engine.py`, which passes Prometheus's own `relabel_test.go` vectors (Folder 01) [M].
- **Chart and CRDs.** Chart defaults come from `values.yaml` at `kube-prometheus-stack-92.18.0`. CRD field names come from `pkg/apis/monitoring/v1` at v0.94.2 [D].
- **Not run.** No cluster was run.

---

## 0. Orientation

**What this file answers.**
- How a Spring Boot pod (File 01) becomes a set of correctly labelled Prometheus targets in a kube-prometheus-stack cluster.
- Every layer that can silently drop it.
- How to shard and limit scraping safely.

**The reconcile path.**

```text
 Helm values (kube-prometheus-stack 92.18.0)
   └─► Prometheus CR  ─┬─ serviceMonitorSelector / podMonitorSelector / ruleSelector  (+ *NamespaceSelector)
                       │    chart default *SelectorNilUsesHelmValues: true  ⇒ only objects labelled release=<release>
                       ├─ shards × replicas, scrapeClasses, enforced limits, serviceDiscoveryRole (default Endpoints)
 ServiceMonitor / PodMonitor / ScrapeConfig / Probe / PrometheusRule CRs (namespaces you allow)
   └─► prometheus-operator v0.94.2 ── generates ──► Secret prometheus-<name> (prometheus.yaml.gz)
                                                 └► config-reloader substitutes $(SHARD) and reloads Prometheus
 Prometheus StatefulSet prometheus-<name>-shard-N-<replica>
   └─ job "serviceMonitor/shop/checkout/0": kubernetes_sd(role: endpoints|endpointslice) → relabel chain (L6 §1)
      → targets {namespace, service, pod, container, endpoint, job, instance, …} → scrape /actuator/prometheus
```

---

## 1. First principles

### 1.1 Three selection layers, three ways to silently lose a target [D][M]

1. **Object selection.** Does the Prometheus CR read this ServiceMonitor at all?
   - `serviceMonitorSelector` plus `serviceMonitorNamespaceSelector`.
   - With the chart default `serviceMonitorSelectorNilUsesHelmValues: true`, an empty selector becomes "objects labelled `release: <helm release>`".
   - An unlabelled ServiceMonitor is never read. Nothing errors; the operator simply doesn't select it.
2. **Service selection.** The relabel `keep` rules on `__meta_kubernetes_service_label_<k>` **and** `…labelpresent_<k>` (regex `(<v>);true`).
   - A ServiceMonitor selecting `app: checkout`, on a Service that carries only `app.kubernetes.io/name: checkout`, yields **0 targets** (L6 §3).
3. **Port selection.** `keep` on `__meta_kubernetes_endpoint_port_name` (or `…endpointslice_port_name`) equal to `endpoints[].port`.
   - The **Service port name**, not the container port name.
   - A typo yields **0 targets** (L6 §3).

Layers 2 and 3 show up as "dropped targets" in the Prometheus UI (with `keepDroppedTargets`). Layer 1 shows up nowhere in the targets view. The only evidence is the missing `serviceMonitor/<ns>/<name>/<i>` job in the generated configuration Secret and in `prometheus_sd_discovered_targets` (§2.4).

### 1.2 The generated chain, rule by rule [D][M]

For `endpoints: [{port: management}]` with `targetLabels: [team]`, `podTargetLabels: [app.kubernetes.io/version]` and one custom relabeling, the operator emits 18 rules (L6 §1):

```text
  1 job → __tmp_prometheus_job_name          (preserve the generated job name)
  2 keep service label app.kubernetes.io/name = checkout (label AND labelpresent)
  3 keep endpoint port name = management
  4 node ← address target Node;<name>          5 pod ← address target Pod;<name>
  6 namespace  7 service  8 pod  9 container   (from SD meta labels)
 10 drop pod phase (Failed|Succeeded)          (filterRunning, default true)
 11 team ← service label team                  12 app_kubernetes_io_version ← pod label
 13 job ← service name                         (jobLabel would override from a Service label)
 14 endpoint = management
 15 user relabelings (ours: node ← __meta_kubernetes_pod_node_name)
 16–18 sharding: __tmp_hash ← __address__; hashmod N; keep $(SHARD)  (or __tmp_disable_sharding set)
 then: metricRelabelings → metric_relabel_configs; limits → sample_limit/label_limit/…
```

Resulting target (L6): `{app_kubernetes_io_version="4.12.0", container="checkout", endpoint="management", instance="10.1.0.11:8081", job="checkout", namespace="shop", pod="checkout-7d9f-abcde", service="checkout", team="payments"}`.

**`job` is the Service name.** It is not the ServiceMonitor name. Dashboards keyed on `job` follow the Service. A **PodMonitor's** job is `<namespace>/<name>` [D], so moving a workload from a ServiceMonitor to a PodMonitor renames `job` and breaks every rule keyed on it. Set `jobLabel` deliberately.

### 1.3 Endpoints vs EndpointSlice [D][M]

- **Default role.** `serviceDiscoveryRole` defaults to **`Endpoints`** in v0.94.2: "If unset, the operator assumes the 'Endpoints' role".
- **Kubernetes deprecation.** Kubernetes deprecated the v1 Endpoints API in 1.33. EndpointSlice scales better, with sharded objects instead of one Endpoints object per Service.
- **Generated rules switch automatically.** They move to `__meta_kubernetes_endpointslice_*`, and L6 §2 shows identical target labels.
- **Hand-written rules do not.** Any custom relabeling that references `__meta_kubernetes_endpoint_*` silently stops matching: 0 targets in L6 §2.
- **Migration.** Grep all `relabelings` for `endpoint_` before flipping the role, at Prometheus-CR level or per ServiceMonitor (`spec.serviceDiscoveryRole`).

### 1.4 Sharding, replicas and what rules see [D][M]

- **Sharding is per target.** `shards: N` creates N StatefulSets. The tail of every generated chain hashes `__address__` (`hashmod N`) and keeps the shard number substituted for `$(SHARD)`. L6 §4: 300 targets split 91/108/101, each owned exactly once.
- **Replicas are HA, not scale.** `replicas: 2` duplicates every shard. The external labels `prometheus=<ns>/<name>` and `prometheus_replica=<pod>` (operator defaults) let Thanos or the Mimir HA tracker deduplicate (Folder 06 file 02).
- **Rules on a sharded Prometheus see partial data** ⚠.
  - Every shard loads the same PrometheusRules but holds only its targets' series.
  - `sum by (job) (rate(...))` on shard 0 is a *partial* sum, so SLO ratios are wrong and absence alerts fire on shards that don't own the target.
  - With shards > 1, evaluate global rules in a central ruler (Mimir ruler, Thanos ruler) over the merged data. Keep only shard-local rules (per-target `up`) on the shards.

### 1.5 Limits and protocols that protect the server [D]

**Per-object limits** (ServiceMonitor `spec`): `sampleLimit`, `targetLimit`, `labelLimit`, `labelNameLengthLimit`, `labelValueLengthLimit`, `keepDroppedTargets`, `bodySizeLimit`.
- The Prometheus CR's `enforced*` fields put a ceiling on all of them.
- Exceeding `sampleLimit` fails the **whole scrape**: no samples are ingested and `up` is 0. That is a loud failure, which is better than a silent cardinality explosion.

**Protocols** (`scrapeProtocols`, `fallbackScrapeProtocol`): put `OpenMetricsText1.0.0` first so exemplars are scraped (File 01). Prometheus 3 also supports `PrometheusProto`, which carries native histograms.

**Native histograms per endpoint** [D]: `scrapeNativeHistograms`, `scrapeClassicHistograms` and `convertClassicHistogramsToNHCB` exist on `Endpoint` in v0.94.2. Prometheus 3.x still defaults native-histogram scraping off (Folder 01).

**Scrape classes** (Prometheus CR `scrapeClasses`, one marked `default: true`) inject TLS, authorization, relabelings and metric relabelings into every selected monitor. That is the platform team's lever to enforce cluster-wide labels and drops without editing every ServiceMonitor.

<!-- listing:servicemonitor_lab.py -->
```python
"""servicemonitor_lab.py - what the Prometheus Operator (v0.94.2) turns a ServiceMonitor / PodMonitor into,
and what that scrape config then does to real Kubernetes service-discovery targets.

  * Port of generateServiceMonitorConfig / generatePodMonitorConfig relabel chains from
    pkg/prometheus/promcfg.go @ v0.94.2: job->__tmp_prometheus_job_name, selector keep rules
    (label + labelpresent), port keep, node/pod from address target, namespace/service/pod/container,
    the Failed|Succeeded running filter, targetLabels/podTargetLabels, job (service name or jobLabel),
    endpoint, user relabelings, and the hashmod sharding tail with $(SHARD).
  * The chains are executed by relabel_engine.relabel (Folder 01, a port of Prometheus v3.15.1
    model/relabel, oracle-tested against relabel_test.go) on synthetic SD targets of both the
    'endpoints' and 'endpointslice' roles.

Deterministic, stdlib only. Usage: python servicemonitor_lab.py [target.md]
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from relabel_engine import finalize, relabel  # noqa: E402


def sanitize(name):
    return "".join(c if c.isalnum() or c == "_" else "_" for c in name)


def selector_rules(sel, kind):
    meta = f"__meta_kubernetes_{kind}_label_"
    present = f"__meta_kubernetes_{kind}_labelpresent_"
    rules = []
    for k in sorted(sel.get("matchLabels", {})):
        rules.append(dict(action="keep", source_labels=[meta + sanitize(k), present + sanitize(k)],
                          regex=f"({sel['matchLabels'][k]});true"))
    for e in sel.get("matchExpressions", []):
        if e["operator"] in ("In", "NotIn"):
            rules.append(dict(action="keep" if e["operator"] == "In" else "drop",
                              source_labels=[meta + sanitize(e["key"]), present + sanitize(e["key"])],
                              regex=f"({'|'.join(e['values'])});true"))
        else:
            rules.append(dict(action="keep" if e["operator"] == "Exists" else "drop",
                              source_labels=[present + sanitize(e["key"])], regex="true"))
    return rules


def sharding_tail(shards):
    return [dict(source_labels=["__address__", "__tmp_hash"], target_label="__tmp_hash", regex="(.+);",
                 replacement="$1", action="replace"),
            dict(source_labels=["__tmp_hash"], target_label="__tmp_hash", modulus=shards, action="hashmod"),
            dict(source_labels=["__tmp_hash", "__tmp_disable_sharding"], regex="$(SHARD);|.+;.+", action="keep")]


def service_monitor_chain(sm, ep, role="endpoints", shards=1):
    r = [dict(source_labels=["job"], target_label="__tmp_prometheus_job_name")]
    r += selector_rules(sm["selector"], "service")
    if ep.get("port"):
        src = "__meta_kubernetes_endpointslice_port_name" if role == "endpointslice" else "__meta_kubernetes_endpoint_port_name"
        r.append(dict(action="keep", source_labels=[src], regex=ep["port"]))
    kind, name = (("__meta_kubernetes_endpointslice_address_target_kind", "__meta_kubernetes_endpointslice_address_target_name")
                  if role == "endpointslice" else
                  ("__meta_kubernetes_endpoint_address_target_kind", "__meta_kubernetes_endpoint_address_target_name"))
    r += [dict(source_labels=[kind, name], separator=";", regex="Node;(.*)", replacement="${1}", target_label="node"),
          dict(source_labels=[kind, name], separator=";", regex="Pod;(.*)", replacement="${1}", target_label="pod"),
          dict(source_labels=["__meta_kubernetes_namespace"], target_label="namespace"),
          dict(source_labels=["__meta_kubernetes_service_name"], target_label="service"),
          dict(source_labels=["__meta_kubernetes_pod_name"], target_label="pod"),
          dict(source_labels=["__meta_kubernetes_pod_container_name"], target_label="container")]
    if ep.get("filterRunning", True):
        r.append(dict(action="drop", source_labels=["__meta_kubernetes_pod_phase"], regex="(Failed|Succeeded)"))
    for l in sm.get("targetLabels", []):
        r.append(dict(source_labels=["__meta_kubernetes_service_label_" + sanitize(l)], target_label=sanitize(l),
                      regex="(.+)", replacement="${1}"))
    for l in sm.get("podTargetLabels", []):
        r.append(dict(source_labels=["__meta_kubernetes_pod_label_" + sanitize(l)], target_label=sanitize(l),
                      regex="(.+)", replacement="${1}"))
    r.append(dict(source_labels=["__meta_kubernetes_service_name"], target_label="job", replacement="${1}"))
    if sm.get("jobLabel"):
        r.append(dict(source_labels=["__meta_kubernetes_service_label_" + sanitize(sm["jobLabel"])], target_label="job",
                      regex="(.+)", replacement="${1}"))
    if ep.get("port"):
        r.append(dict(target_label="endpoint", replacement=ep["port"]))
    r += ep.get("relabelings", [])
    r += sharding_tail(shards)
    return r


def pod_monitor_chain(pm, ep, shards=1):
    r = [dict(source_labels=["job"], target_label="__tmp_prometheus_job_name")]
    if ep.get("filterRunning", True):
        r.append(dict(action="drop", source_labels=["__meta_kubernetes_pod_phase"], regex="(Failed|Succeeded)"))
    r += selector_rules(pm["selector"], "pod")
    if ep.get("port"):
        r.append(dict(action="keep", source_labels=["__meta_kubernetes_pod_container_port_name"], regex=ep["port"]))
    r += [dict(source_labels=["__meta_kubernetes_namespace"], target_label="namespace"),
          dict(source_labels=["__meta_kubernetes_pod_container_name"], target_label="container"),
          dict(source_labels=["__meta_kubernetes_pod_name"], target_label="pod")]
    for l in pm.get("podTargetLabels", []):
        r.append(dict(source_labels=["__meta_kubernetes_pod_label_" + sanitize(l)], target_label=sanitize(l),
                      regex="(.+)", replacement="${1}"))
    r.append(dict(target_label="job", replacement=f"{pm['namespace']}/{pm['name']}"))
    if ep.get("port"):
        r.append(dict(target_label="endpoint", replacement=ep["port"]))
    r += ep.get("relabelings", [])
    r += sharding_tail(shards)
    return r


def run_chain(chain, targets, shard=0):
    rules = [dict(c, regex=c["regex"].replace("$(SHARD)", str(shard))) if "regex" in c else c for c in chain]
    out = []
    for t in targets:
        got = finalize(relabel(t, rules))
        if got is not None:
            out.append(got)
    return out


def sd_targets(role="endpoints"):
    """Service checkout (ports http:8080, management:8081) with 4 pods (one Succeeded job pod is not
    behind a Service; one pod is Failed), plus service cart that the selector must not match."""
    pre = "endpointslice" if role == "endpointslice" else "endpoint"
    out = []
    pods = [("checkout-7d9f-abcde", "10.1.0.11", "Running"), ("checkout-7d9f-fghij", "10.1.0.12", "Running"),
            ("checkout-7d9f-klmno", "10.1.0.13", "Running"), ("checkout-7d9f-pqrst", "10.1.0.14", "Failed")]
    for svc, svc_labels, plist in (("checkout", {"app_kubernetes_io_name": "checkout", "team": "payments"}, pods),
                                   ("cart", {"app_kubernetes_io_name": "cart", "team": "basket"},
                                    [("cart-55c-uvwxy", "10.1.1.21", "Running")])):
        for pod, ip, phase in plist:
            for port_name, port in (("http", 8080), ("management", 8081)):
                t = {"__address__": f"{ip}:{port}", "job": "", "__metrics_path__": "/metrics",
                     "__meta_kubernetes_namespace": "shop", "__meta_kubernetes_service_name": svc,
                     f"__meta_kubernetes_{pre}_port_name": port_name,
                     f"__meta_kubernetes_{pre}_address_target_kind": "Pod",
                     f"__meta_kubernetes_{pre}_address_target_name": pod,
                     "__meta_kubernetes_pod_name": pod, "__meta_kubernetes_pod_container_name": svc,
                     "__meta_kubernetes_pod_phase": phase,
                     "__meta_kubernetes_pod_container_port_name": port_name,
                     "__meta_kubernetes_pod_label_app_kubernetes_io_version": "4.12.0",
                     "__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name": "true",
                     "__meta_kubernetes_pod_label_app_kubernetes_io_name": svc}
                for k, v in svc_labels.items():
                    t[f"__meta_kubernetes_service_label_{k}"] = v
                    t[f"__meta_kubernetes_service_labelpresent_{k}"] = "true"
                out.append(t)
    return out


SM = {"name": "checkout", "namespace": "shop",
      "selector": {"matchLabels": {"app.kubernetes.io/name": "checkout"}},
      "targetLabels": ["team"], "podTargetLabels": ["app.kubernetes.io/version"]}
EP = {"port": "management", "path": "/actuator/prometheus", "interval": "15s",
      "relabelings": [dict(action="replace", source_labels=["__meta_kubernetes_pod_node_name"], target_label="node")]}


def main():
    checks = []
    print("== 1. ServiceMonitor shop/checkout, endpoint port 'management' -> generated relabel chain ==")
    chain = service_monitor_chain(SM, EP)
    for i, r in enumerate(chain, 1):
        desc = ", ".join(f"{k}={v}" for k, v in r.items() if k != "action")
        print(f"{i:>2}. {r.get('action', 'replace'):<8} {desc[:104]}")
    tg = run_chain(chain, sd_targets())
    print(f"\nSD offered {len(sd_targets())} targets (2 services x pods x 2 ports); kept {len(tg)}:")
    for t in tg:
        print("   " + ", ".join(f"{k}={v}" for k, v in sorted(t.items())))
    want = {("checkout-7d9f-abcde", "10.1.0.11:8081"), ("checkout-7d9f-fghij", "10.1.0.12:8081"),
            ("checkout-7d9f-klmno", "10.1.0.13:8081")}
    got = {(t["pod"], t["instance"]) for t in tg}
    checks.append(("only running management endpoints of checkout", got == want and
                   all(t["job"] == "checkout" and t["endpoint"] == "management" and t["team"] == "payments"
                       and t["app_kubernetes_io_version"] == "4.12.0" and t["namespace"] == "shop" for t in tg)))
    print()

    print("== 2. The same ServiceMonitor under serviceDiscoveryRole: EndpointSlice ==")
    tg_es = run_chain(service_monitor_chain(SM, EP, role="endpointslice"), sd_targets("endpointslice"))
    print(f"generated chain keeps on __meta_kubernetes_endpointslice_port_name -> {len(tg_es)} targets, identical "
          f"labels: {sorted(map(sorted, (t.items() for t in tg_es))) == sorted(map(sorted, (t.items() for t in tg)))}")
    hand = [dict(action="keep", source_labels=["__meta_kubernetes_endpoint_port_name"], regex="management")]
    tg_bad = run_chain(service_monitor_chain(SM, dict(EP, relabelings=hand), role="endpointslice"), sd_targets("endpointslice"))
    print(f"a hand-written relabeling on __meta_kubernetes_endpoint_port_name under EndpointSlice: {len(tg_bad)} targets")
    checks.append(("role switch", len(tg_es) == 3 and len(tg_bad) == 0))
    print("-> the operator default role is still 'Endpoints' (Kubernetes deprecated v1 Endpoints in 1.33);")
    print("   switching to EndpointSlice is safe for generated rules but silently empties hand-written ones.")
    print()

    print("== 3. Classic misconfigurations, measured ==")
    typo = run_chain(service_monitor_chain(SM, dict(EP, port="managment")), sd_targets())
    sel = run_chain(service_monitor_chain(dict(SM, selector={"matchLabels": {"app": "checkout"}}), EP), sd_targets())
    nofilter = run_chain(service_monitor_chain(SM, dict(EP, filterRunning=False)), sd_targets())
    joblbl = run_chain(service_monitor_chain(dict(SM, jobLabel="app.kubernetes.io/name"), EP), sd_targets())
    print(f"port name typo 'managment'            -> {len(typo)} targets (no error anywhere; they only show as dropped)")
    print(f"selector on 'app' (Service has app.kubernetes.io/name only) -> {len(sel)} targets")
    print(f"filterRunning: false                   -> {len(nofilter)} targets (the Failed pod is scraped and 'up'==0 alerts)")
    print(f"jobLabel: app.kubernetes.io/name       -> job={sorted({t['job'] for t in joblbl})}")
    checks.append(("misconfigs", len(typo) == 0 and len(sel) == 0 and len(nofilter) == 4))
    print("-> and the most common one is not in the chain at all: kube-prometheus-stack's Prometheus selects")
    print("   ServiceMonitors by label (release=<helm release>) when serviceMonitorSelectorNilUsesHelmValues")
    print("   is true (the chart default), so an unlabelled ServiceMonitor is never even read.")
    print()

    print("== 4. Sharding: shards: 3 -> every target is owned by exactly one Prometheus shard ==")
    many = []
    for i in range(300):
        t = dict(sd_targets()[1])
        t["__address__"] = f"10.2.{i // 250}.{i % 250 + 1}:8081"
        t["__meta_kubernetes_pod_name"] = t["__meta_kubernetes_endpoint_address_target_name"] = f"checkout-{i:04d}"
        many.append(t)
    chain3 = service_monitor_chain(SM, EP, shards=3)
    owned = [run_chain(chain3, many, shard=s) for s in range(3)]
    insts = [t["instance"] for o in owned for t in o]
    print(f"targets per shard {[len(o) for o in owned]}; total {len(insts)}; duplicates {len(insts) - len(set(insts))}")
    checks.append(("each target exactly once", len(insts) == 300 and len(set(insts)) == 300))
    print()

    print("== 5. PodMonitor shop/checkout-jobs for pods with no Service (batch workers) ==")
    pm = {"name": "checkout-jobs", "namespace": "shop",
          "selector": {"matchExpressions": [{"key": "app.kubernetes.io/name", "operator": "In", "values": ["checkout"]}]},
          "podTargetLabels": ["app.kubernetes.io/version"]}
    tp = run_chain(pod_monitor_chain(pm, {"port": "management"}), sd_targets())
    print(f"kept {len(tp)} pod targets; job label = {sorted({t['job'] for t in tp})}; no 'service' label: "
          f"{all('service' not in t for t in tp)}")
    checks.append(("podmonitor", len(tp) == 3 and {t["job"] for t in tp} == {"shop/checkout-jobs"}))
    print("-> PodMonitor job defaults to <namespace>/<name>, ServiceMonitor job to the Service name: dashboards")
    print("   and rules keyed on job break when a workload moves between the two; set jobLabel explicitly.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:servicemonitor_lab.py -->
```text
== 1. ServiceMonitor shop/checkout, endpoint port 'management' -> generated relabel chain ==
 1. replace  source_labels=['job'], target_label=__tmp_prometheus_job_name
 2. keep     source_labels=['__meta_kubernetes_service_label_app_kubernetes_io_name', '__meta_kubernetes_service_labe
 3. keep     source_labels=['__meta_kubernetes_endpoint_port_name'], regex=management
 4. replace  source_labels=['__meta_kubernetes_endpoint_address_target_kind', '__meta_kubernetes_endpoint_address_tar
 5. replace  source_labels=['__meta_kubernetes_endpoint_address_target_kind', '__meta_kubernetes_endpoint_address_tar
 6. replace  source_labels=['__meta_kubernetes_namespace'], target_label=namespace
 7. replace  source_labels=['__meta_kubernetes_service_name'], target_label=service
 8. replace  source_labels=['__meta_kubernetes_pod_name'], target_label=pod
 9. replace  source_labels=['__meta_kubernetes_pod_container_name'], target_label=container
10. drop     source_labels=['__meta_kubernetes_pod_phase'], regex=(Failed|Succeeded)
11. replace  source_labels=['__meta_kubernetes_service_label_team'], target_label=team, regex=(.+), replacement=${1}
12. replace  source_labels=['__meta_kubernetes_pod_label_app_kubernetes_io_version'], target_label=app_kubernetes_io_
13. replace  source_labels=['__meta_kubernetes_service_name'], target_label=job, replacement=${1}
14. replace  target_label=endpoint, replacement=management
15. replace  source_labels=['__meta_kubernetes_pod_node_name'], target_label=node
16. replace  source_labels=['__address__', '__tmp_hash'], target_label=__tmp_hash, regex=(.+);, replacement=$1
17. hashmod  source_labels=['__tmp_hash'], target_label=__tmp_hash, modulus=1
18. keep     source_labels=['__tmp_hash', '__tmp_disable_sharding'], regex=$(SHARD);|.+;.+

SD offered 10 targets (2 services x pods x 2 ports); kept 3:
   app_kubernetes_io_version=4.12.0, container=checkout, endpoint=management, instance=10.1.0.11:8081, job=checkout, namespace=shop, pod=checkout-7d9f-abcde, service=checkout, team=payments
   app_kubernetes_io_version=4.12.0, container=checkout, endpoint=management, instance=10.1.0.12:8081, job=checkout, namespace=shop, pod=checkout-7d9f-fghij, service=checkout, team=payments
   app_kubernetes_io_version=4.12.0, container=checkout, endpoint=management, instance=10.1.0.13:8081, job=checkout, namespace=shop, pod=checkout-7d9f-klmno, service=checkout, team=payments

== 2. The same ServiceMonitor under serviceDiscoveryRole: EndpointSlice ==
generated chain keeps on __meta_kubernetes_endpointslice_port_name -> 3 targets, identical labels: True
a hand-written relabeling on __meta_kubernetes_endpoint_port_name under EndpointSlice: 0 targets
-> the operator default role is still 'Endpoints' (Kubernetes deprecated v1 Endpoints in 1.33);
   switching to EndpointSlice is safe for generated rules but silently empties hand-written ones.

== 3. Classic misconfigurations, measured ==
port name typo 'managment'            -> 0 targets (no error anywhere; they only show as dropped)
selector on 'app' (Service has app.kubernetes.io/name only) -> 0 targets
filterRunning: false                   -> 4 targets (the Failed pod is scraped and 'up'==0 alerts)
jobLabel: app.kubernetes.io/name       -> job=['checkout']
-> and the most common one is not in the chain at all: kube-prometheus-stack's Prometheus selects
   ServiceMonitors by label (release=<helm release>) when serviceMonitorSelectorNilUsesHelmValues
   is true (the chart default), so an unlabelled ServiceMonitor is never even read.

== 4. Sharding: shards: 3 -> every target is owned by exactly one Prometheus shard ==
targets per shard [91, 108, 101]; total 300; duplicates 0

== 5. PodMonitor shop/checkout-jobs for pods with no Service (batch workers) ==
kept 3 pod targets; job label = ['shop/checkout-jobs']; no 'service' label: True
-> PodMonitor job defaults to <namespace>/<name>, ServiceMonitor job to the Service name: dashboards
   and rules keyed on job break when a workload moves between the two; set jobLabel explicitly.

checks: 5/5 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 kube-prometheus-stack values (the platform side)

```yaml
# values-prod.yaml for kube-prometheus-stack 92.18.0 (keys from the chart's values.yaml)
prometheus:
  prometheusSpec:
    replicas: 2
    shards: 1
    retention: 15d
    retentionSize: 450GB
    scrapeInterval: 30s
    evaluationInterval: 30s
    serviceDiscoveryRole: EndpointSlice
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelector:
      matchLabels:
        monitoring.acme.io/scrape: "true"
    podMonitorSelector:
      matchLabels:
        monitoring.acme.io/scrape: "true"
    ruleSelector:
      matchLabels:
        monitoring.acme.io/rules: "true"
    serviceMonitorNamespaceSelector: {}
    podMonitorNamespaceSelector: {}
    ruleNamespaceSelector: {}
    enforcedSampleLimit: 50000
    enforcedLabelLimit: 40
    enforcedLabelValueLengthLimit: 512
    enforcedKeepDroppedTargets: 50
    externalLabels:
      cluster: prod-use1
    scrapeClasses:
      - name: platform-default
        default: true
        metricRelabelings:
          - sourceLabels: [__name__]
            regex: 'go_gc_duration_seconds.*|go_memstats_.*_total'
            action: drop
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 500Gi
    resources:
      requests:
        cpu: "4"
        memory: 24Gi
      limits:
        memory: 24Gi
    remoteWrite:
      - url: http://mimir-distributor.mimir.svc:8080/api/v1/push
        headers:
          X-Scope-OrgID: prod
        sendExemplars: true
        queueConfig:
          capacity: 10000
          maxShards: 100
          maxSamplesPerSend: 2000
          retryOnRateLimit: true
```

**Why.**
- **Explicit selectors.** `*SelectorNilUsesHelmValues: false` with explicit `monitoring.acme.io/*` selectors decouples teams' objects from the Helm release name. Renaming the release can no longer orphan every ServiceMonitor (F1).
- **`EndpointSlice` from day one** (§1.3).
- **`enforced*` limits.** These ceilings apply to every team's monitors.
- **A default scrape class.** It applies platform-wide metric drops.
- **`retryOnRateLimit: true`.** This `QueueConfig` field exists in the v0.94.2 types and maps to `retry_on_http_429`, whose Prometheus default is false (Folder 01 file 04) [D].

### 2.2 The application side: Service, ServiceMonitor, PodMonitor

```yaml
apiVersion: v1
kind: Service
metadata:
  name: checkout
  namespace: shop
  labels:
    app.kubernetes.io/name: checkout
    team: payments
spec:
  selector:
    app.kubernetes.io/name: checkout
  ports:
    - name: http
      port: 80
      targetPort: http
    - name: management
      port: 8081
      targetPort: management
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: checkout
  namespace: shop
  labels:
    monitoring.acme.io/scrape: "true"
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: checkout
  targetLabels: [team]
  podTargetLabels: [app.kubernetes.io/version]
  sampleLimit: 40000
  labelLimit: 30
  scrapeProtocols: [OpenMetricsText1.0.0, PrometheusText0.0.4]
  endpoints:
    - port: management
      path: /actuator/prometheus
      interval: 15s
      scrapeTimeout: 10s
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_node_name]
          targetLabel: node
      metricRelabelings:
        - sourceLabels: [__name__]
          regex: 'jvm_compilation_.*|executor_idle_seconds_.*'
          action: drop
        - sourceLabels: [__name__, le]
          regex: 'http_server_requests_seconds_bucket;(0\.00[1-4].*)'
          action: drop
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: checkout-jobs
  namespace: shop
  labels:
    monitoring.acme.io/scrape: "true"
spec:
  selector:
    matchExpressions:
      - key: app.kubernetes.io/name
        operator: In
        values: [checkout-reconciler]
  jobLabel: app.kubernetes.io/name
  podMetricsEndpoints:
    - port: management
      path: /actuator/prometheus
      interval: 30s
```

**Why.**
- **Port names everywhere.** Service port `management` → container port `management` → ServiceMonitor `port: management` (§1.1, layer 3).
- **`targetLabels: [team]`.** It copies the owning team onto every series, which is what Alertmanager routes on (File 03).
- **Bucket-dropping `metricRelabelings`.** These are the ingest-side backstop for File 01 §1.5. They drop `le` buckets below 5 ms if a service forgot to clamp.
  - The regex runs on `__name__;le` and is an exact full match.
  - Dropping buckets keeps `histogram_quantile` valid, because the remaining buckets are still cumulative, but it lowers resolution in that range.
- **PodMonitor for workers without a Service.** `jobLabel` keeps `job` stable (§1.2).

### 2.3 PrometheusRule wrapper for the File 03 catalog

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-slo
  namespace: shop
  labels:
    monitoring.acme.io/rules: "true"
spec:
  groups:
    - name: checkout-sli-recording
      interval: 30s
      rules:
        - record: job:http_server_requests:rate5m
          expr: sum by (job) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[5m]))
    # ... the remaining groups of microservice-rules.yaml (File 03), unchanged
```

### 2.4 PromQL to debug discovery and scraping

```promql
# Targets per job and health (layer 2/3 problems show as missing jobs here)
count by (job) (up)
sum by (job) (up == 0)

# Samples per scrape vs sampleLimit (approaching the limit means imminent whole-scrape failure)
max by (job) (scrape_samples_post_metric_relabeling) / 40000

# Series added per scrape (churn) and scrape duration vs timeout
topk(10, max by (job) (scrape_series_added))
max by (job) (scrape_duration_seconds) / 10

# Discovered (pre-relabel) targets per generated scrape config: a missing config is layer 1,
# discovered-but-not-up is layers 2/3 (compare with count by (job) (up))
sum by (config) (prometheus_sd_discovered_targets{name="scrape"})
```

`prometheus_sd_discovered_targets` is labelled with the scrape-config name (`serviceMonitor/shop/checkout/0`). Comparing it with `up` separates the three selection layers of §1.1 without opening the UI.

---

## 3. Failure modes and FinOps debugging

### F1. "My ServiceMonitor does nothing"

**Symptom.** A new service has no targets. No errors anywhere.

**Signature.** The ServiceMonitor lacks the label the Prometheus CR selects (`release: <release>` with chart defaults), or sits in a namespace outside `serviceMonitorNamespaceSelector`. The generated Secret has no `serviceMonitor/shop/checkout/0` job.

**Root cause.** Object-level selection (§1.1, layer 1). The chart's `serviceMonitorSelectorNilUsesHelmValues: true` default turns an empty selector into a release-label selector.

**Fix.** Add the label, or set explicit platform selectors (§2.1).

**Prevention.**
- An admission policy (Kyverno or Gatekeeper) that requires the selection label on every ServiceMonitor and PodMonitor.
- A CI check that renders the operator config.

### F2. Targets discovered but all dropped

**Symptom.** The Prometheus UI lists the job with 0 active targets and N dropped.

**Signature.** The Service has no label matching `spec.selector`, or `endpoints[].port` doesn't equal a Service port **name**. L6 §3: 0 of 10.

**Root cause.** Service or port selection (§1.1, layers 2 and 3).

**Fix.** Align labels and port names. Use `targetPort` only for a container port name or number, with a PodMonitor-like intent.

**Prevention.** Template Services and ServiceMonitors together (one Helm library chart). Alert on `absent(up{job="checkout"})` (File 03).

### F3. Targets vanish after switching to EndpointSlice

**Symptom.** After the platform flips `serviceDiscoveryRole`, a few teams lose all targets.

**Signature.** Their custom `relabelings` reference `__meta_kubernetes_endpoint_port_name` or similar. Generated rules still work. L6 §2: 0 targets.

**Root cause.** Meta-label names differ by SD role (§1.3).

**Fix.** Rewrite the custom rules to `__meta_kubernetes_endpointslice_*`, or remove them: the generated chain already does the port selection.

**Prevention.** Grep all monitors for `endpoint_` before the switch, and run L6-style simulation in CI.

### F4. SLO alerts wrong after enabling shards

**Symptom.** After `shards: 3`, burn-rate alerts fire on one shard and not others. Ratios are inconsistent.

**Signature.** The same PrometheusRule loaded on all shards. Each shard's `sum by (job)` covers about a third of the pods.

**Root cause.** Rules evaluate on shard-local data (§1.4) ⚠.

**Fix.** Move global rules to a central ruler (Mimir or Thanos), and keep per-target rules local. Or don't shard: scale vertically, or use the agent mode plus a central TSDB.

**Prevention.** Document rule placement. Add an `ALERTS` deduplication check per shard in staging.

### F5. Scrapes fail after a release: `sample_limit` exceeded

**Symptom.** `up == 0` for every pod of a service right after deploy. The application is healthy.

**Signature.** `scrape_samples_scraped` exceeds `sampleLimit`. The new release added histograms or per-tenant tags (File 01 F6).

**Root cause.** The limit protects Prometheus by failing the whole scrape [D].

**Fix.**
- Short term: raise the limit for this ServiceMonitor within the enforced ceiling.
- Real fix: fix the cardinality in the app.

**Prevention.** Alert at 80% of the limit (§2.4). Run the File 01 series-budget test in CI.

### F6. Job label changed, dashboards and alerts blank

**Symptom.** After moving a worker from a ServiceMonitor to a PodMonitor, every panel and rule for it is empty.

**Signature.** Series now have `job="shop/checkout-jobs"` instead of `job="checkout-jobs"`.

**Root cause.** Different `job` defaults: Service name vs `<ns>/<name>` (§1.2) [D].

**Fix.** Set `jobLabel` (or a relabeling) to keep the old value.

**Prevention.** A contract that `job` is set explicitly in every monitor. Rules use `job` only through a recording layer.

### F7. Failed and completed pods scraped, `up` alerts flap

**Symptom.** TargetDown alerts for pods in `Failed` or `Succeeded` phase (CronJob pods, evicted pods).

**Signature.** `filterRunning: false` on the endpoint. L6 §3 shows the Failed pod kept.

**Root cause.** The running filter (`drop pod phase (Failed|Succeeded)`) was disabled.

**Fix.** Keep `filterRunning` at its default `true`. Use a Pushgateway or OTLP for batch jobs, not scrapes of terminated pods.

**Prevention.** Lint monitors for `filterRunning: false`.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "A team's metrics never showed up. Walk the debug path."</b></summary>

**Initial Prompt.** They created a ServiceMonitor yesterday.

**L5 Textbook Answer.** Check the Prometheus targets page and the pod's `/metrics` endpoint.

**Why L5 Fails at 3 AM or on the Bill.** The targets page can't show a ServiceMonitor that was never selected (layer 1), so the L5 path dead-ends in "nothing there".

**L7 Principal Defense.** Debug layer by layer.
1. **Was the object selected?** Compare its labels and namespace against the Prometheus CR selectors (chart default: `release` label). Look for the job in the generated Secret.
2. **Is the job present with dropped targets?** Then it is layer 2 or 3: Service label selector, or Service *port name*.
3. **Are targets present but `up == 0`?** Then it is the path, the TLS, `sampleLimit`, or a NetworkPolicy on the management port.
4. **Are series present but labels wrong?** Then it is relabelings or `honorLabels`.

L6 reproduces each layer's failure. I'd turn the first two into admission and CI checks so the question never reaches on-call.
</details>

<details><summary><b>Q2 · "ServiceMonitor or PodMonitor?"</b></summary>

**Initial Prompt.** We have services, workers and DaemonSets.

**L5 Textbook Answer.** ServiceMonitor for services, PodMonitor otherwise.

**Why L5 Fails at 3 AM or on the Bill.** It misses that the choice changes `job` (F6), the meta labels available (Service labels vs pod labels), and the discovery cost. Endpoints/EndpointSlice watches vs pod watches matter at 50k pods.

**L7 Principal Defense.**
- **ServiceMonitor** when a Service exists and you want Service-level labels (`targetLabels`) and `job` = Service name.
- **PodMonitor** for headless workers, DaemonSets and sidecars, with `jobLabel` set explicitly.
- **Either way:** a single platform convention for `job`, `team` and `app` labels, enforced by a default scrape class and admission policy.
- **Large clusters:** EndpointSlice role, and namespace selectors that keep each Prometheus's watch set bounded.
</details>

<details><summary><b>Q3 · "How do you scale Prometheus in a 3,000-node cluster?"</b></summary>

**Initial Prompt.** One Prometheus is at 60 GB RAM.

**L5 Textbook Answer.** Use `shards: 4`.

**Why L5 Fails at 3 AM or on the Bill.** Sharding splits targets, so every rule over a job spanning shards is wrong (F4). Queries also need a global view to merge shards.

**L7 Principal Defense.**
- Shard by *ownership* first: separate Prometheus CRs per domain (platform/infra vs each large tenant). Their rules then stay local and correct.
- Use `shards` only within a domain whose rules are per-target or are evaluated centrally.
- Remote-write everything to Mimir, and run SLO rules in the Mimir ruler.
- Cut the input: drop unused series (Folder 08), clamp histograms (File 01), enforce limits.
- Consider Prometheus agent mode or Alloy clustering, with the TSDB in Mimir, when local querying isn't needed.
</details>

<details><summary><b>Q4 · "What do the generated relabel rules actually do?"</b></summary>

**Initial Prompt.** Explain a ServiceMonitor without hand-waving.

**L5 Textbook Answer.** It tells Prometheus which services to scrape.

**Why L5 Fails at 3 AM or on the Bill.** Without the mechanics you can't debug dropped targets, label collisions or shard ownership.

**L7 Principal Defense.** Walk the 18 rules from L6 §1.
- Preserve the generated job name.
- Two-part selector keeps (label value **and** label presence).
- Port-name keep.
- Pod and node from the address target.
- Namespace, service, pod and container.
- Running filter.
- Target and pod target labels.
- `job` from the Service name or `jobLabel`.
- `endpoint`.
- User relabelings.
- Hashmod sharding with `$(SHARD)` substituted by the config-reloader.
- Metric relabelings run *after* the scrape, on series.

Each step has a failure mode I can name and a meta label to inspect on the dropped-targets page.
</details>

<details><summary><b>Q5 · "How do you stop one team's deploy from taking Prometheus down?"</b></summary>

**Initial Prompt.** A release added 2M series and OOMed Prometheus.

**L5 Textbook Answer.** Ask teams to be careful with labels.

**Why L5 Fails at 3 AM or on the Bill.** Asking doesn't scale. One bad deploy takes down monitoring for everyone, during the incident it caused.

**L7 Principal Defense.** Defence in depth.
- **Limits.** Per-monitor `sampleLimit` and `labelLimit` under Prometheus-CR `enforced*` ceilings. A violating scrape fails alone and loudly (F5).
- **Platform drops.** A default scrape class drops known-bad patterns.
- **CI.** Series-budget tests per service (File 01).
- **Central storage.** Per-tenant limits in Mimir (Folder 06).
- **Alerting.** Alert on `scrape_samples_post_metric_relabeling` at 80% of the limit.
- **Prometheus itself.** Memory requests sized with headroom, and the WAL on fast disks so restart replay is quick.
</details>

<details><summary><b>Q6 · "HA Prometheus pairs: what labels and how is dedup done?"</b></summary>

**Initial Prompt.** We run `replicas: 2`.

**L5 Textbook Answer.** Both scrape everything; Grafana shows one.

**Why L5 Fails at 3 AM or on the Bill.** Both replicas remote-write, so Mimir stores double series and every `sum` doubles. Both also fire alerts, which Alertmanager must deduplicate.

**L7 Principal Defense.**
- The operator adds `prometheus_replica` (and `prometheus`) external labels.
- Mimir's HA tracker uses `cluster` plus a replica label to accept one replica's stream. Set `ha_replica_label` to `prometheus_replica` or rename via `replicaExternalLabelName`.
- Thanos dedups at query time with `--query.replica-label=prometheus_replica`.
- Alertmanager dedups identical alerts from both replicas by label set, so `prometheus_replica` must **not** be in alert labels. The operator generates an `alert_relabel_configs` `labeldrop` for the replica label "to enable proper deduplication on the Alertmanager side" [D].
- I'd verify each of these with a `count by (cluster, __replica__)` style check after rollout.
</details>

<details><summary><b>Q7 · "How do you migrate 400 ServiceMonitors to EndpointSlice safely?"</b></summary>

**Initial Prompt.** Kubernetes 1.33 deprecated Endpoints.

**L5 Textbook Answer.** Set `serviceDiscoveryRole: EndpointSlice` in the chart.

**Why L5 Fails at 3 AM or on the Bill.** Custom relabelings referencing `__meta_kubernetes_endpoint_*` silently drop all targets (L6 §2), and it happens for many teams at once.

**L7 Principal Defense.**
- **Inventory.** Grep monitors for `endpoint_` meta labels.
- **Simulate.** Run the L6 approach in CI against real SD dumps, and compare target sets before and after.
- **Override per object first.** `spec.serviceDiscoveryRole` on individual ServiceMonitors flips a canary set.
- **Watch the signals.** `count by (job) (up)` before and after, plus absence alerts.
- **Then flip globally**, and keep `keepDroppedTargets` raised during the window for debugging.
</details>

<details><summary><b>Q8 · "Where should label normalisation happen: app, relabeling, or backend?"</b></summary>

**Initial Prompt.** Teams emit `team`, `owner`, `squad` inconsistently.

**L5 Textbook Answer.** Fix it in the application code.

**Why L5 Fails at 3 AM or on the Bill.** Hundreds of services and libraries won't converge. Some labels, like the Kubernetes context, aren't knowable in the app at all.

**L7 Principal Defense.**
- **App:** domain labels only (outcome, method, tenant class).
- **Discovery relabeling:** infrastructure labels, from Service and pod metadata via `targetLabels` and `podTargetLabels`, plus a default scrape class for normalisation.
- **Backend:** only last-resort fixes (Mimir relabeling per tenant).
- **Contract:** documented and enforced by admission. Ownership (`team`) comes from the Service, not the app, so routing (File 03) never depends on developers remembering a label.
</details>

---

## 5. Invariants checklist

- [ ] Prometheus CR selectors are explicit (not the Helm release label); admission requires the selection label on every monitor.
- [ ] Service port names are the contract: Service `management` → ServiceMonitor `port: management` → container `management`.
- [ ] `serviceDiscoveryRole: EndpointSlice`, and no custom relabeling references `__meta_kubernetes_endpoint_*`.
- [ ] `job` is set deliberately (Service name or `jobLabel`) and never changes when switching monitor kinds.
- [ ] Every monitor has `sampleLimit` and `labelLimit` under `enforced*` ceilings; 80%-of-limit alerts exist.
- [ ] `filterRunning` stays true; batch pods aren't scraped after completion.
- [ ] Global SLO rules run where the data is complete (an unsharded Prometheus, or a central ruler).
- [ ] OpenMetrics is the first scrape protocol where exemplars matter; HA replica labels are deduplicated downstream.

---

## 6. References

- Prometheus Operator `promcfg.go` (v0.94.2): <https://github.com/prometheus-operator/prometheus-operator/blob/v0.94.2/pkg/prometheus/promcfg.go>
- ServiceMonitor and Endpoint types (v0.94.2): <https://github.com/prometheus-operator/prometheus-operator/blob/v0.94.2/pkg/apis/monitoring/v1/servicemonitor_types.go>
- Prometheus Operator API reference: <https://prometheus-operator.dev/docs/api-reference/api/>
- Prometheus Operator sharding: <https://prometheus-operator.dev/docs/platform/sharding/>
- kube-prometheus-stack values (92.18.0): <https://github.com/prometheus-community/helm-charts/blob/kube-prometheus-stack-92.18.0/charts/kube-prometheus-stack/values.yaml>
- Prometheus `kubernetes_sd_config`: <https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config>
- Kubernetes EndpointSlices: <https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/>
- Prometheus relabeling: <https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config>
