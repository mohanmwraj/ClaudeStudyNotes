# 03 · Alertmanager Architecture: Gossip HA, De-duplication, Grouping, Inhibition and Silences

> **Folder 04 — Recording Rules, Alertmanager and SLO Error-Budget Math · File 3 of 4.**
> Pinned to **Alertmanager v0.34.2** (2026-10-29; `dispatch/route.go`, `notify/dedup_stage.go`, `notify/cluster_stages.go`, `inhibit/inhibit.go`, `cluster/cluster.go` and `cmd/alertmanager/main.go` read at that tag).
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L3 `alertmanager_lab.py` | Ports `Route.Match` (depth-first, first matching child wins unless `continue`), the dedup stage's `needsUpdate` decision and inhibition with `equal`: a 5-alert routing table through a production-shaped tree; a 60-alert storm under three `group_by` choices (32 vs 13 vs 120 notifications in 2 h); 15 of 60 warnings muted by 5 `NodeDown` sources; and duplicate-notification rates for an HA pair under healthy, degraded and partitioned gossip | <1 s |

**Verification.** Routing and dedup are line-level ports of the pinned source; their expected outcomes for the sample alerts are asserted. Timing uses the pinned defaults (`group_wait` 30 s, `group_interval` 5 m, `repeat_interval` 4 h, `--cluster.peer-timeout` 15 s). The HA duplicate rates are a model [E] of "peer *n* waits *n* × peer-timeout before consulting the replicated notification log". No live Alertmanager was run.

---

## 0. Orientation

**What this file answers.** What happens between "Prometheus says an alert is firing" and "a human gets one useful page": routing, grouping, timing, de-duplication across HA replicas, inhibition, silences and mute timings — and the configuration patterns that turn an alert storm into one actionable notification.

**Division of labour.**

```text
 Prometheus (each replica)          Alertmanager cluster (2-3 replicas, gossip mesh)
 ──────────────────────────         ─────────────────────────────────────────────────────────
 evaluate rules → alerts            receive alerts from ALL Prometheus replicas (POST /api/v2/alerts)
 send firing alerts every           │ inhibition / silence / mute-time checks (per alert)
 --rules.alert.resend-delay (1m)    │ route tree → aggregation groups (route × group_by labels)
 with endsAt = now + 4×eval/resend  │ group_wait → first flush; group_interval → batched updates
 to EVERY configured Alertmanager   │ dedup against the replicated notification log (nflog)
                                    │ cluster wait: replica at position p waits p × peer_timeout
                                    ▼ receivers: PagerDuty, Slack, email, webhook, OpsGenie …
```

Prometheus never deduplicates across its own HA replicas — it sends to all Alertmanagers, and the Alertmanager cluster deduplicates both identical alerts (same label set → same fingerprint) and notifications (via the gossiped notification log).

---

## 1. First principles: from alerts to notifications

### 1.1 The routing tree [D]

`Route.Match(labels)` in `dispatch/route.go`:

```text
 match(route, alert):
   if not route.matchers(alert): return []
   results = []
   for child in route.routes:              # in order
       m = match(child, alert)
       results += m
       if m and not child.continue: break  # first matching child wins
   return results or [route]               # no child matched → this route handles it
 options (receiver, group_by, timings) inherit from the parent unless overridden
```

L3 §1 routes five alerts through a tree with a `continue: true` team route above severity routes [M]: a payments page reaches both `payments-slack` and `payments-pager`; a search page reaches the generic PagerDuty receiver; `Watchdog` goes to the heartbeat receiver; unmatched alerts fall to the root. Tooling: `amtool config routes test --config.file=alertmanager.yml severity=page team=payments` prints the same answer from the real binary.

### 1.2 Aggregation groups and the three timers [D]

- An **aggregation group** = (route, values of the route's `group_by` labels). `group_by: ['...']` groups by *all* labels (one group per alert); omitting `group_by` (or `[]`) makes one group per route.
- **`group_wait`** (30 s): after a group's first alert arrives, wait to collect siblings before the first notification.
- **`group_interval`** (5 m): minimum time between notifications for the *same* group when its content changes (new alerts, resolutions).
- **`repeat_interval`** (4 h): re-send an unchanged group's notification.

The dedup stage's `needsUpdate` decides on each flush [D]: notify if this is the first notification with firing alerts; if the firing set contains alerts not in the last notification; if everything resolved (to clear the receiver's state); if new resolutions exist and `send_resolved` is on; otherwise only after `repeat_interval`.

L3 §2: 60 node alerts across 3 clusters arriving over 3 minutes and resolving over an hour [M]:

| `group_by` | Groups | Notifications in 2 h |
|---|---|---|
| `[alertname, cluster]` | 3 | 32 |
| `[alertname]` | 1 | 13 |
| `['...']` | 60 | **120** |

One notification per *cluster incident*, updated as members arrive and resolve, is usually the right granularity; `'...'` turns every member into its own page.

### 1.3 Inhibition, silences and time intervals [D]

- **Inhibition rule**: if a firing *source* alert matches `source_matchers`, then *target* alerts matching `target_matchers` are muted when every label in `equal` has the same value on both (a missing label equals the empty string on both sides). An alert matching both sides cannot inhibit itself. L3 §3: 5 `NodeDown` sources mute exactly the 15 warnings on those nodes, delivering the other 45.
- **Silences**: label matchers with a time range, created by humans or automation (`amtool silence add`, API); replicated by gossip; they mute matching alerts at notification time.
- **`time_intervals`** with `mute_time_intervals` / `active_time_intervals` on routes: scheduled muting (maintenance windows, business-hours-only routes) without silences.

### 1.4 High availability: gossip, nflog and at-least-once delivery [D]

```text
 AM-0 (position 0)                    AM-1 (position 1)                 AM-2 (position 2)
 receives alert ── flush ──► send     receives alert ── flush ──►       receives alert ── flush ──►
 nflog entry gossiped ─────────────►  wait 1 × 15 s, check nflog:       wait 2 × 15 s, check nflog:
                                      entry present → DROP              entry present → DROP
 if gossip is late (> 15 s) or partitioned: AM-1 sends too → DUPLICATE, never silence
```

- Peers form a memberlist mesh (`--cluster.peer`, gossip interval 200 ms, push-pull 60 s, settle timeout 60 s defaults); silences and the notification log (nflog) are replicated.
- Each replica waits `position × --cluster.peer-timeout` (15 s) before deciding, then consults the nflog. Delivery is **at-least-once** by design: L3 §4 shows 0% duplicates with healthy gossip, 63% with 5–30 s gossip delay, 100% under partition.
- Prometheus must send to **all** replicas (static list or service discovery of each pod) — never through a load balancer, which would split alert state.
- Receivers should de-duplicate on the group key (PagerDuty `dedup_key` is set by Alertmanager from the group key).

<!-- listing:alertmanager_lab.py -->
```python
"""alertmanager_lab.py - Alertmanager v0.34.2 routing, grouping, notification timing, inhibition and
HA de-duplication, ported from dispatch/route.go (Route.Match), notify/dedup_stage.go (needsUpdate),
inhibit/inhibit.go (Mutes) and the cluster wait stage (peer position x --cluster.peer-timeout).

Sections: (1) routing table for sample alerts through a production-shaped tree (continue, nested
routes, regex matchers); (2) an alert storm (60 alerts over 3 minutes, resolved over an hour)
under three group_by choices; (3) inhibition of warnings by a NodeDown source with equal labels;
(4) a two-replica HA pair: duplicate notifications vs gossip delay.
Deterministic, stdlib only.

Usage: python alertmanager_lab.py [target.md]
"""
import random
import re
import sys

DEFAULTS = {"group_wait": 30, "group_interval": 300, "repeat_interval": 4 * 3600, "group_by": None}


def matches(ms, labels):
    for name, op, val in ms:
        have = labels.get(name, "")
        hit = re.fullmatch(val, have) is not None if op in ("=~", "!~") else have == val
        if (op in ("=", "=~") and not hit) or (op in ("!=", "!~") and hit):
            return False
    return True


class Route:
    def __init__(self, cfg, parent=None):
        opts = dict(parent.opts) if parent else dict(DEFAULTS)
        for k in DEFAULTS:
            if k in cfg:
                opts[k] = cfg[k]
        opts["receiver"] = cfg.get("receiver", parent.opts["receiver"] if parent else None)
        self.opts, self.cfg = opts, cfg
        self.matchers = cfg.get("matchers", [])
        self.cont = cfg.get("continue", False)
        self.key = (parent.key + "/" if parent else "") + opts["receiver"]
        self.routes = [Route(c, self) for c in cfg.get("routes", [])]

    def match(self, labels):  # dispatch/route.go Route.Match
        if not matches(self.matchers, labels):
            return []
        out = []
        for child in self.routes:
            m = child.match(labels)
            out += m
            if m and not child.cont:
                break
        return out or [self]


TREE = Route({
    "receiver": "default-slack", "group_by": ["alertname", "cluster"],
    "routes": [
        {"receiver": "watchdog-heartbeat", "matchers": [("alertname", "=", "Watchdog")],
         "group_wait": 0, "group_interval": 60, "repeat_interval": 60},
        {"receiver": "payments-slack", "matchers": [("team", "=", "payments")], "continue": True},
        {"receiver": "pagerduty", "matchers": [("severity", "=", "page")],
         "routes": [{"receiver": "payments-pager", "matchers": [("team", "=", "payments")]}]},
        {"receiver": "jira", "matchers": [("severity", "=~", "ticket|warning")], "group_by": ["alertname", "namespace"],
         "group_interval": 900, "repeat_interval": 24 * 3600},
    ]})


def notify_count(alerts, route, group_by, horizon):
    """alerts: list of (labels, start, end). Simulates groups, flushes and dedup over [0, horizon]."""
    groups = {}
    for lbl, s, e in alerts:
        if group_by == "...":
            key = tuple(sorted(lbl.items()))
        else:
            key = tuple((k, lbl.get(k, "")) for k in group_by)
        groups.setdefault(key, []).append((lbl, s, e))
    o = route.opts
    sent = 0
    for key, members in groups.items():
        first = min(s for _, s, _ in members)
        t = first + o["group_wait"]
        log = None  # (firing set, resolved set, timestamp) of the last notification
        while t <= horizon:
            firing = {i for i, (_, s, e) in enumerate(members) if s <= t < e}
            resolved = {i for i, (_, s, e) in enumerate(members) if e <= t}
            if log is None:
                need = bool(firing)
            elif not firing <= log[0]:
                need = True
            elif not firing:
                need = bool(log[0])
            elif not resolved <= log[1]:
                need = True  # send_resolved: true
            else:
                need = log[2] < t - o["repeat_interval"]
            if need:
                sent += 1
                log = (firing, resolved, t)
            if not firing and log is not None and not log[0]:
                break
            t += o["group_interval"]
    return sent, len(groups)


def main():
    checks = []
    print("== 1. Routing (Route.Match: depth-first, first matching child wins unless continue: true) ==")
    samples = [
        {"alertname": "HighErrorRatio", "severity": "page", "team": "payments", "cluster": "eu1"},
        {"alertname": "HighErrorRatio", "severity": "page", "team": "search", "cluster": "eu1"},
        {"alertname": "DiskWillFill", "severity": "warning", "team": "payments", "namespace": "pay"},
        {"alertname": "Watchdog", "severity": "none"},
        {"alertname": "Unrouted", "severity": "info"},
    ]
    expected = [["payments-slack", "payments-pager"], ["pagerduty"], ["payments-slack", "jira"],
                ["watchdog-heartbeat"], ["default-slack"]]
    for s, exp in zip(samples, expected):
        got = [r.opts["receiver"] for r in TREE.match(s)]
        checks.append((f"route {s['alertname']}", got == exp))
        print(f"{str(s):<92} -> {got}")
    print()

    print("== 2. Alert storm: 60 alerts in 3 min (3 clusters x 20 nodes), resolving over 60 min ==")
    rng = random.Random(1)
    storm = []
    for c in range(3):
        for nd in range(20):
            start = rng.randint(0, 180)
            storm.append(({"alertname": "NodeFilesystemFull", "cluster": f"c{c}", "node": f"n{nd}", "severity": "page"},
                          start, start + rng.randint(600, 3600)))
    route = TREE.match(storm[0][0])[0]
    print(f"{'group_by':<28} {'groups':>6} {'notifications in 2h':>20}")
    res = {}
    for gb in (["alertname", "cluster"], ["alertname"], "..."):
        n, g = notify_count(storm, route, gb, 7200)
        res[str(gb)] = n
        print(f"{str(gb):<28} {g:>6} {n:>20}")
    checks.append(("'...' is noisiest", res["..."] > res[str(["alertname", "cluster"])] > res[str(["alertname"])]))
    print("-> group_by [alertname, cluster] keeps one page per cluster incident; '...' sends one per node (and per")
    print("   resolve); group_interval (5 min) batches new members so a storm costs a handful of notifications.")
    print()

    print("== 3. Inhibition: NodeDown(cluster, node) mutes warnings with equal cluster and node ==")
    source = [{"alertname": "NodeDown", "cluster": "c0", "node": f"n{k}", "severity": "page"} for k in range(5)]
    targets = []
    for k in range(20):
        for an in ("KubeletDown", "ContainerOOM", "NodeExporterDown"):
            targets.append({"alertname": an, "cluster": "c0", "node": f"n{k}", "severity": "warning"})
    rule = {"source": [("alertname", "=", "NodeDown")], "target": [("severity", "=", "warning")], "equal": ["cluster", "node"]}

    def muted(t):
        if not matches(rule["target"], t):
            return False
        return any(matches(rule["source"], s) and all(s.get(e, "") == t.get(e, "") for e in rule["equal"])
                   and not (matches(rule["target"], s) and s == t) for s in source)
    m = sum(muted(t) for t in targets)
    print(f"{len(targets)} warning alerts, {len(source)} NodeDown sources -> {m} muted, {len(targets) - m} delivered")
    checks.append(("15 muted", m == 15))
    print("-> 'equal' labels make inhibition surgical: only the 5 dead nodes' symptoms are muted. A missing label")
    print("   counts as equal-empty on both sides, so an inhibit rule with equal: [node] and source alerts WITHOUT a")
    print("   node label mutes every target that also lacks it.")
    print()

    print("== 4. HA pair: peer 0 notifies at once, peer 1 waits 1 x peer_timeout (15 s), then checks the nflog ==")
    rng = random.Random(9)
    fracs = {}
    for label, delays in (("healthy gossip (0.2-2 s)", [rng.uniform(0.2, 2) for _ in range(1000)]),
                          ("degraded gossip (5-30 s)", [rng.uniform(5, 30) for _ in range(1000)]),
                          ("partitioned (never)", [1e9] * 1000)):
        dup = sum(1 for d in delays if d > 15.0)  # peer 1 sends iff peer 0's nflog entry has not arrived
        fracs[label] = dup / len(delays)
        print(f"{label:<26} duplicate notifications for {dup / len(delays):.0%} of groups")
    checks.append(("healthy: no duplicates", fracs["healthy gossip (0.2-2 s)"] == 0.0))
    checks.append(("partition: always duplicates", fracs["partitioned (never)"] == 1.0))
    print("-> Alertmanager HA is at-least-once: a partition yields duplicates, never silence. Receivers must")
    print("   tolerate duplicates (PagerDuty dedup_key = group key).")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:alertmanager_lab.py -->
```text
== 1. Routing (Route.Match: depth-first, first matching child wins unless continue: true) ==
{'alertname': 'HighErrorRatio', 'severity': 'page', 'team': 'payments', 'cluster': 'eu1'}    -> ['payments-slack', 'payments-pager']
{'alertname': 'HighErrorRatio', 'severity': 'page', 'team': 'search', 'cluster': 'eu1'}      -> ['pagerduty']
{'alertname': 'DiskWillFill', 'severity': 'warning', 'team': 'payments', 'namespace': 'pay'} -> ['payments-slack', 'jira']
{'alertname': 'Watchdog', 'severity': 'none'}                                                -> ['watchdog-heartbeat']
{'alertname': 'Unrouted', 'severity': 'info'}                                                -> ['default-slack']

== 2. Alert storm: 60 alerts in 3 min (3 clusters x 20 nodes), resolving over 60 min ==
group_by                     groups  notifications in 2h
['alertname', 'cluster']          3                   32
['alertname']                     1                   13
...                              60                  120
-> group_by [alertname, cluster] keeps one page per cluster incident; '...' sends one per node (and per
   resolve); group_interval (5 min) batches new members so a storm costs a handful of notifications.

== 3. Inhibition: NodeDown(cluster, node) mutes warnings with equal cluster and node ==
60 warning alerts, 5 NodeDown sources -> 15 muted, 45 delivered
-> 'equal' labels make inhibition surgical: only the 5 dead nodes' symptoms are muted. A missing label
   counts as equal-empty on both sides, so an inhibit rule with equal: [node] and source alerts WITHOUT a
   node label mutes every target that also lacks it.

== 4. HA pair: peer 0 notifies at once, peer 1 waits 1 x peer_timeout (15 s), then checks the nflog ==
healthy gossip (0.2-2 s)   duplicate notifications for 0% of groups
degraded gossip (5-30 s)   duplicate notifications for 63% of groups
partitioned (never)        duplicate notifications for 100% of groups
-> Alertmanager HA is at-least-once: a partition yields duplicates, never silence. Receivers must
   tolerate duplicates (PagerDuty dedup_key = group key).

checks: 9/9 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 `alertmanager.yml` (v0.34)

```yaml
global:
  resolve_timeout: 5m
route:
  receiver: default-slack
  group_by: [alertname, cluster, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - receiver: watchdog-heartbeat          # dead man's switch (File 4)
      matchers: ['alertname="Watchdog"']
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1m
    - receiver: payments-slack              # team visibility for everything they own
      matchers: ['team="payments"']
      continue: true
    - receiver: pagerduty-sre
      matchers: ['severity="page"']
      routes:
        - receiver: pagerduty-payments
          matchers: ['team="payments"']
        - receiver: pagerduty-search
          matchers: ['team="search"']
    - receiver: jira-tickets
      matchers: ['severity=~"ticket|warning"']
      group_by: [alertname, namespace]
      group_interval: 15m
      repeat_interval: 24h
      active_time_intervals: [business-hours]
time_intervals:
  - name: business-hours
    time_intervals:
      - weekdays: ['monday:friday']
        times: [{start_time: '08:00', end_time: '18:00'}]
        location: Europe/Berlin
inhibit_rules:
  - name: node-down-hides-node-symptoms
    source_matchers: ['alertname="NodeDown"']
    target_matchers: ['severity=~"warning|ticket"']
    equal: [cluster, node]
  - name: cluster-unreachable-hides-everything-in-it
    source_matchers: ['alertname="ClusterUnreachable"']
    target_matchers: ['severity!="none"', 'alertname!="ClusterUnreachable"']
    equal: [cluster]
receivers:
  - name: default-slack
    slack_configs:
      - api_url_file: /etc/alertmanager/secrets/slack-default
        channel: '#alerts'
        send_resolved: true
        title: '{{ template "slack.title" . }}'
        text: '{{ template "slack.text" . }}'
  - name: payments-slack
    slack_configs:
      - api_url_file: /etc/alertmanager/secrets/slack-payments
        channel: '#payments-alerts'
        send_resolved: true
  - name: pagerduty-sre
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pd-sre
        send_resolved: true
  - name: pagerduty-payments
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pd-payments
        send_resolved: true
  - name: pagerduty-search
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pd-search
  - name: jira-tickets
    webhook_configs:
      - url: http://jiralert.monitoring:9097/alert
        send_resolved: true
  - name: watchdog-heartbeat
    webhook_configs:
      - url_file: /etc/alertmanager/secrets/heartbeat-url
        send_resolved: false
templates:
  - /etc/alertmanager/templates/*.tmpl
```

### 2.2 Running the cluster (StatefulSet args) and pointing Prometheus at every replica

```yaml
# Alertmanager container args
args:
  - --config.file=/etc/alertmanager/alertmanager.yml
  - --storage.path=/alertmanager
  - --cluster.listen-address=0.0.0.0:9094
  - --cluster.peer=alertmanager-0.alertmanager.monitoring.svc:9094
  - --cluster.peer=alertmanager-1.alertmanager.monitoring.svc:9094
  - --cluster.peer=alertmanager-2.alertmanager.monitoring.svc:9094
  - --cluster.peer-timeout=15s
  - --web.external-url=https://alertmanager.example.internal
---
# Prometheus side: discover each pod, never a load-balanced VIP
alerting:
  alert_relabel_configs:
    - action: labeldrop
      regex: __replica__|prometheus_replica    # HA Prometheus pairs send identical alerts
  alertmanagers:
    - scheme: http
      api_version: v2
      kubernetes_sd_configs:
        - role: pod
          namespaces: {names: [monitoring]}
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
          regex: alertmanager
          action: keep
        - source_labels: [__meta_kubernetes_pod_container_port_number]
          regex: "9093"
          action: keep
```

### 2.3 Tests and operations (amtool)

```bash
amtool check-config alertmanager.yml
amtool config routes test --config.file=alertmanager.yml --verify.receivers=pagerduty-payments severity=page team=payments
amtool config routes show --config.file=alertmanager.yml
amtool silence add 'cluster="eu1"' 'alertname=~"Node.*"' --duration=2h --comment="kernel upgrade CHG-1234"
amtool alert query --alertmanager.url=https://alertmanager.example.internal 'severity="page"'
```

---

## 3. Failure modes and FinOps debugging

### F1. Pager storm: one incident, 120 pages

**Symptom.** A cluster-wide node problem pages on-call dozens of times within minutes.

**Signature.** `group_by: ['...']` or per-instance grouping; `alertmanager_notifications_total` spikes for one receiver; no inhibition between cause and symptom alerts.

**Root cause.** Grouping granularity equals alert granularity (L3 §2: 120 notifications vs 32).

**Fix.** Group by incident-shaped labels (`alertname, cluster` or `cluster, namespace`); add inhibition from causes (NodeDown, ClusterUnreachable) to symptoms.

**Prevention.** Storm drills: replay a recorded storm into a staging Alertmanager and count notifications.

### F2. Duplicate pages from an HA pair

**Symptom.** Every page arrives twice, a few seconds apart.

**Signature.** Gossip errors (`alertmanager_cluster_messages_*`), `alertmanager_cluster_members` less than replicas, peers can't reach port 9094 (NetworkPolicy, DNS), or Prometheus labels differ between its HA replicas so alerts have different fingerprints.

**Root cause.** Either the nflog isn't replicated within the peer timeout (at-least-once kicks in), or the *alerts* differ (e.g. a `replica` external label not dropped in `alert_relabel_configs`).

**Fix.** Repair gossip connectivity; drop replica labels from alerts.

**Prevention.** Alert on `alertmanager_cluster_members < 3` and on failed peer messages; a test alert that must arrive once.

### F3. Silence that silenced too much

**Symptom.** During maintenance, a real unrelated outage was silent.

**Signature.** A silence with a broad matcher (`cluster="eu1"`) and a long duration; the outage's alerts matched it.

**Root cause.** Silences mute by label match, not intent.

**Fix.** Narrow matchers (alertname + instance/node), short durations, automation that creates and expires silences around changes.

**Prevention.** Policy: silences > 4 h require a ticket; audit `alertmanager_silences{state="active"}` and expire stale ones.

### F4. Inhibition that hides the real problem

**Symptom.** A severe alert never paged because an unrelated "source" alert inhibited it.

**Signature.** `equal` list empty or missing labels that both sides lack (empty equals empty), so any source inhibits all targets.

**Root cause.** Inhibition with too-broad `equal` semantics.

**Fix.** Always include topology labels in `equal` (`cluster`, `node`, `namespace`), and ensure both sides carry them.

**Prevention.** Unit-test inhibition with representative alert pairs; review inhibit rules like code.

### F5. Alerts that never resolve in the receiver

**Symptom.** Slack/Jira shows alerts as firing hours after recovery.

**Signature.** `send_resolved: false` on the receiver, or Prometheus stopped sending (rule removed, Prometheus down) and `endsAt` handling delayed by `resolve_timeout`.

**Root cause.** Resolution is a notification like any other; disabled or lost resolutions leave stale state.

**Fix.** `send_resolved: true` where the receiver tracks state; check Prometheus→Alertmanager connectivity (`prometheus_notifications_dropped_total`).

**Prevention.** Alert on notification failures (`alertmanager_notifications_failed_total`) and dropped notifications.

### F6. Prometheus behind a load balancer to Alertmanager

**Symptom.** Alerts flap between firing and resolved; groups re-notify randomly.

**Signature.** Prometheus `alertmanagers` points at a single Service VIP; each alert resend lands on a random replica.

**Root cause.** Each Alertmanager holds its own alert state; spreading resends across replicas makes each see intermittent alerts.

**Fix.** Discover and send to every replica (§2.2).

**Prevention.** Config lint: `alertmanagers` must use pod-level discovery or a static list of all peers.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "How does Alertmanager avoid duplicate pages with two Prometheus and three Alertmanager replicas?"</b></summary>

**Initial Prompt.** Walk through dedup end to end.

**L5 Textbook Answer.** Alertmanager deduplicates identical alerts and the cluster shares state.

**Why L5 Fails at 3 AM or on the Bill.** Misses the two distinct mechanisms and their failure modes (label differences between Prometheus replicas; gossip delay vs peer timeout), so duplicates can't be debugged.

**L7 Principal Defense.** Layer 1: both Prometheus replicas send identical label sets (replica labels dropped in `alert_relabel_configs`) to all three Alertmanagers; each AM merges them by fingerprint. Layer 2: notification dedup — each AM flushes groups, waits position × 15 s, consults the gossiped nflog, and only the first sender notifies. Delivery is at-least-once: partitions produce duplicates (L3 §4), so receivers dedupe on group key.
</details>

<details><summary><b>Q2 · "Design group_by for a microservices platform."</b></summary>

**Initial Prompt.** What should we group by?

**L5 Textbook Answer.** By alertname so similar alerts are together.

**Why L5 Fails at 3 AM or on the Bill.** `alertname` alone merges unrelated incidents across clusters/teams into one notification and one PagerDuty incident; `'...'` explodes storms (L3 §2).

**L7 Principal Defense.** Group by the *incident boundary* each receiver acts on: paging routes by `alertname, cluster, service` (one incident per broken thing), ticket routes by `alertname, namespace` with longer `group_interval`. Validate with storm replays and track notifications per incident.
</details>

<details><summary><b>Q3 · "Explain group_wait, group_interval and repeat_interval with a timeline."</b></summary>

**Initial Prompt.** An alert fires at 10:00:00, a sibling at 10:00:20, a third at 10:03:00, all resolve at 10:40. When are notifications sent?

**L5 Textbook Answer.** One at 10:00:30 and then every 5 minutes.

**Why L5 Fails at 3 AM or on the Bill.** Notifications are only sent when the group *changes* (or repeat_interval elapses); "every 5 minutes" would mean a 4-hour incident pages ~50 times.

**L7 Principal Defense.** 10:00:30 first notification (both alerts, after group_wait); 10:05:30 update with the third alert (group_interval tick, firing set changed); nothing more until resolution: the 10:40:30 flush sends the resolution (all resolved). If nothing changed for 4 h, a repeat would fire. That's `needsUpdate` in `dedup_stage.go`.
</details>

<details><summary><b>Q4 · "When do you use inhibition vs routing vs silences?"</b></summary>

**Initial Prompt.** Three ways to suppress — when each?

**L5 Textbook Answer.** Inhibition for dependent alerts, silences for maintenance, routing to send to the right team.

**Why L5 Fails at 3 AM or on the Bill.** Correct categories, but without the mechanics teams build broad inhibitions and long silences that hide outages (F3, F4).

**L7 Principal Defense.** Routing decides *who*; it never suppresses. Inhibition suppresses *derived* symptoms when a firing cause exists, scoped by `equal` topology labels. Silences are temporary, human or automation-driven, narrowly matched and short. Scheduled suppression uses `time_intervals`. Each is code-reviewed and tested; silences are audited.
</details>

<details><summary><b>Q5 · "Why must Prometheus send alerts to every Alertmanager?"</b></summary>

**Initial Prompt.** Can't we use a load balancer like any other service?

**L5 Textbook Answer.** For high availability, if one is down the others receive alerts.

**Why L5 Fails at 3 AM or on the Bill.** Misses state consistency: alert state lives per replica; a load balancer distributes resends, so each replica sees alerts appear and expire (F6).

**L7 Principal Defense.** Alertmanager replicas are not stateless backends: each must see the full alert stream; only notification decisions are coordinated via gossip. Prometheus discovers all replicas (pod SD/static) and fans out; HA comes from redundancy plus nflog dedup.
</details>

<details><summary><b>Q6 · "How would you test an Alertmanager configuration change?"</b></summary>

**Initial Prompt.** Someone wants to restructure the routing tree.

**L5 Textbook Answer.** Run `amtool check-config`.

**Why L5 Fails at 3 AM or on the Bill.** Syntax checks don't catch routing regressions — e.g. a new route without `continue` stealing alerts from a team.

**L7 Principal Defense.** Golden routing tests: a table of representative label sets → expected receivers, executed with `amtool config routes test --verify.receivers` in CI for both old and new configs (L3 implements the same algorithm). Storm replay in staging for grouping, inhibition tests with alert pairs, and a canary receiver.
</details>

<details><summary><b>Q7 · "Alertmanager went down for 10 minutes. What was lost?"</b></summary>

**Initial Prompt.** Impact analysis.

**L5 Textbook Answer.** Alerts during those 10 minutes were lost.

**Why L5 Fails at 3 AM or on the Bill.** Prometheus keeps resending firing alerts every minute; nothing is lost if at least one replica stays up, and even a full outage delays rather than loses alerts that are still firing — but resolved-in-between alerts and silences created then may be affected.

**L7 Principal Defense.** With ≥ 1 healthy replica: no impact (HA). Full outage: still-firing alerts notify after recovery (resend), alerts that fired and resolved during the outage are never notified, persisted silences/nflog survive restart via `--storage.path`. The dead man's switch (File 4) detects this whole class of failure.
</details>

<details><summary><b>Q8 · "What metrics tell you Alertmanager is healthy?"</b></summary>

**Initial Prompt.** Meta-monitoring for the alerting pipeline.

**L5 Textbook Answer.** `up` for Alertmanager.

**Why L5 Fails at 3 AM or on the Bill.** `up` doesn't show broken receivers, gossip partitions or dropped notifications from Prometheus.

**L7 Principal Defense.** Per receiver: `alertmanager_notifications_failed_total` / `_total`, notification latency; cluster: `alertmanager_cluster_members`, peer message failures; config: `alertmanager_config_last_reload_successful`; Prometheus side: `prometheus_notifications_dropped_total`, queue length, errors per Alertmanager; plus the end-to-end Watchdog heartbeat.
</details>

---

## 5. Invariants checklist

- [ ] Prometheus sends to every Alertmanager replica via discovery; replica labels are dropped from alerts.
- [ ] Paging routes group by incident-shaped labels; `'...'` is never used for paging receivers.
- [ ] Inhibition rules always include topology labels in `equal`, and both sides carry them.
- [ ] Silences are narrow, short, ticket-linked and audited; scheduled muting uses `time_intervals`.
- [ ] Routing changes pass golden `amtool config routes test` cases in CI.
- [ ] Receivers tolerate duplicates; HA is at-least-once.
- [ ] Notification failures, dropped notifications, cluster membership and config reload are alerted, plus the Watchdog heartbeat.

---

## 6. References

- Alertmanager configuration: <https://prometheus.io/docs/alerting/latest/configuration/>
- Alertmanager overview (grouping, inhibition, silences, HA): <https://prometheus.io/docs/alerting/latest/alertmanager/>
- Routing source (`Route.Match`): <https://github.com/prometheus/alertmanager/blob/v0.34.2/dispatch/route.go>
- Dedup stage (`needsUpdate`): <https://github.com/prometheus/alertmanager/blob/v0.34.2/notify/dedup_stage.go>
- Inhibition: <https://github.com/prometheus/alertmanager/blob/v0.34.2/inhibit/inhibit.go>
- High availability README: <https://github.com/prometheus/alertmanager#high-availability>
- amtool: <https://github.com/prometheus/alertmanager#amtool>
