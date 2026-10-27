# Control Plane vs Data Plane, Static Stability, and Graceful Degradation

> **Folder 05 · File 03** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:** [file 01](01-cellular-architecture-shuffle-sharding-and-blast-radius-isolation.md) (blast
> radius), [file 02](02-metastable-failures-retry-storms-load-shedding-and-adaptive-lifo.md) (overload).
> **Listing:** `static_stability_lab.py` covers:
> - a 4-hour control-plane outage under host churn (fetch-at-boot vs last-known-good);
> - reconnect storms vs jitter vs constant work;
> - a bad config pushed globally vs in waves.
>
> The output is deterministic.

---

## 0. The split

| | Control plane | Data plane |
|---|---|---|
| Does | Provisioning, configuration, membership, placement, policy, deploys, credentials issuance | Serves requests: forwards packets, answers queries, stores and returns bytes |
| Rate | Low (changes per minute) | High (requests per second, ×10³–10⁶) |
| Complexity | High (workflows, validation, many dependencies) | Deliberately low |
| Availability target | Lower is acceptable | Highest in the system |
| Examples | EC2 `RunInstances`, Kubernetes API server + controllers, xDS server, DNS management API, IAM policy edits | Running instances, kubelet/kube-proxy/containers, Envoy, DNS resolution, IAM authorization checks |

AWS states the principle bluntly: data planes are designed to be considerably more available than control planes,
because they are simpler and don't change often (Builders' Library, *Static stability using Availability Zones*;
*Avoiding fallback*).

**The L7 design rule: the data plane must not depend on the control plane to keep doing what it is already doing.**
A control-plane outage may block *changes* (new deploys, scaling, new tenants). It must never take down *existing*
traffic.

---

## 1. Static stability

**Definition (AWS):** a system is statically stable if it keeps working when a dependency is impaired, *without
having to make changes*. It does not need to launch capacity, fetch configuration, or call the impaired service.

### 1.1 The two classic forms

1. **Pre-provisioned capacity across failure domains.** Run 3 AZs at ≤ 2/3 utilization, so losing one needs no
   scaling actions, which would themselves depend on a control plane under stress. The capacity price is the
   multiplier table in Folder 01 file 02 §7.7: 1.76× at 3 AZs including 85% max utilization.
2. **Last-known-good (LKG) state on the data plane.**
   - Config, routes, certificates, credentials and the tenant → cell map are persisted locally and used at boot.
   - Credentials are long-lived enough to outlast plausible control-plane outages, rotated well before expiry.

### 1.2 Measured (§A of the output): a 4-hour control-plane outage, 1,000 hosts restarting at 10%/hour

| Data-plane design | Capacity after 1 h | After 4 h | Lost host-hours |
|---|---|---|---|
| Fetch config from the control plane at boot | 89.8% | **69.1%** | **668** |
| **Boot from local last-known-good** | **100%** | **100%** | **0** |
| Fetch-at-boot during a rolling deploy (50%/h restarts) | **58.8% after 1 h** | — | — |

- With fetch-at-boot, a control-plane outage becomes a **slow-motion data-plane outage**. Every routine restart
  (crash, deploy, autoscale, kernel patch) removes a server that cannot come back.
- During a deploy, it is fast-motion: 41% of capacity is gone in an hour.
- Boot-from-LKG makes the outage invisible to traffic.

### 1.3 Where hidden control-plane dependencies hide

| Hidden dependency | Example failure |
|---|---|
| Fetching secrets or certs at startup | Secrets manager down → new pods crash-loop |
| DNS lookups of internal services on every connection | DNS control or update path issues → nothing can connect |
| Service discovery with no cache | Registry down → clients have no endpoints |
| Auth-token minting per request | Token service down → all requests 401 |
| Feature-flag / config service called synchronously | Flag service slow → every request slow |
| Logging/metrics agents blocking the request path | Telemetry backend outage → app threads blocked |
| Autoscaling as the recovery plan for zonal loss | Zonal event + regional control-plane load → no capacity |
| Container image pulls on node replacement | Registry outage → replacement nodes can't start |

The audit question for every dependency: **"If this were down for 4 hours, would a host that restarts during that
time serve traffic?"**

---

## 2. Configuration is the most dangerous data

Several of the largest public outages were configuration changes propagated faster than they could be validated:

| Incident (public post-mortems; ⚠ verify the details) | What propagated | Lesson |
|---|---|---|
| Cloudflare, July 2019 | A WAF rule with a regex that backtracked catastrophically, deployed globally at once; CPU exhausted on every edge | Staged rollout for "data" too; safe regex engines; CPU guards |
| Facebook, October 2021 | A backbone maintenance command, plus DNS servers auto-withdrawing BGP | Automated health actions with global blast radius; break-glass independence |
| CrowdStrike, July 2024 | A content (channel) file update to the Falcon sensor, pushed broadly; a parser fault crashed Windows hosts at boot | Content/config updates need the same canarying as code; the data plane must reject what it can't parse |
| Google Cloud, June 2025 | A new Service Control policy path, replicated globally via its policy store, hit a null-pointer bug without a feature flag | Every new code path behind a flag; config replicated globally must be validated and staged |

The design principles that follow:

1. **Config goes through a pipeline like code:**
   - schema validation;
   - semantic validation (dry run against real traffic samples);
   - canary;
   - waves by cell and region;
   - bake;
   - automatic rollback.
2. **Data planes validate before applying,** and keep LKG if validation fails. A bad config may fail to *apply*; it
   must never crash the data plane by *arriving*.
3. **Feature flags and kill switches** for every new behavior, defaulting to off and staged on.
4. **Version and sign configs;** reject older versions (monotonic acceptance) to prevent flip-flopping.

§C of the output (a bad config, detected 5 minutes after it first lands):

| Rollout | Hosts that received it | Impacted host-minutes |
|---|---|---|
| Global push | 1,000 | **5,000** |
| **Waves 1% → 10% → 50% → 100%, 15 min bake** | **10** | **50** |

---

## 3. Distribution patterns: push, pull, and constant work

### 3.1 The reconnect storm (§B of the output)

When the control plane comes back after an outage, 10,000 data-plane hosts need a full sync:

| Pattern | Peak control-plane load | Steady load |
|---|---|---|
| All reconnect immediately | **10,000 req/s** (a self-DDoS on recovery) | 0 |
| Jittered reconnect over 60 s | 192 req/s | 0 |
| **Constant work** (every host pulls a full snapshot every 30 s, changed or not) | **359 req/s** | 333 req/s |

### 3.2 Constant work

From the AWS Builders' Library article *Reliability, constant work, and a good cup of coffee*: some AWS systems (e.g.
health-check and configuration propagation) **do the same amount of work all the time**.
- They push or pull the *entire* state on a fixed period, whether or not it changed.
- The system's load is therefore **independent of the failure or change rate**.

It looks wasteful, at a steady 333 req/s instead of ~0. But:
- the worst case equals the normal case, so there is no surprise load during incidents;
- there are no "delta" code paths that only run during recovery, and so are never tested;
- the cost is predictable and provisioned.

**Delta-push systems are efficient on good days and dangerous on bad ones.** Mass reconnects, full resyncs and
backfills all arrive when the system is least healthy. If you must use deltas:
- jitter the reconnects;
- rate-limit full syncs;
- make the full-sync path the one exercised regularly.

---

## 4. Graceful degradation

A statically stable system still loses *something* during big failures. Design what it loses.

| Degradation lever | Example |
|---|---|
| Serve stale | Product catalog from cache with `stale-if-error`; last-known-good recommendations |
| Reduce quality | Lower video bitrate; skip personalization; smaller result pages |
| Disable non-critical features | Turn off "people also bought", typeahead, exports |
| Read-only mode | Accept reads, queue or reject writes with a clear message |
| Shed by criticality | Batch and prefetch first, interactive last (file 02 §3.3) |
| Regional independence | A region keeps serving its users even if others or the global control plane are down |

The rules that make it work:
- **Degraded modes are tested continuously.** Game days and regular brownout drills. An untested fallback is a new
  failure mode (*Avoiding fallback in distributed systems*).
- **Degradation is triggered automatically** by SLO/overload signals, with human override, and is visible in the
  product ("some features are temporarily unavailable").
- **Avoid bimodal behavior.** Systems that behave completely differently under failure (a different code path, a
  different dependency) fail in untested ways. Prefer designs where the failure mode is "less of the same": constant
  work, stale data, fewer features.

---

## 5. Example: Kubernetes through this lens

| Component | Plane | If it fails |
|---|---|---|
| etcd + API server | Control | No changes: no new pods, no rescheduling, no scaling. **Existing pods keep running** |
| Controllers / scheduler | Control | Same; reconciliation pauses |
| kubelet | Data (node-local) | Keeps running containers; restarts crashed containers from local state |
| kube-proxy / CNI dataplane rules | Data | Existing iptables/IPVS/eBPF rules keep forwarding |
| CoreDNS | Data, with control inputs | Cached answers continue; new services not resolvable |
| Image registry | Control-ish dependency | New pods on new nodes can't start: **pre-pull, cache images on nodes** |
| Secrets / cert issuers | Control | Pods restarting may lack fresh secrets: **long-lived, pre-rotated credentials** |

This is static stability by design, and it is undone by apps that call the API server on their request path or fetch
secrets on every start.

---

## 6. The listing

```python
"""static_stability_lab.py - control-plane outages vs data-plane designs (Folder 05, file 03).

  A. 1,000 data-plane hosts; the control plane (config/credentials service) is down for 4 hours while hosts keep
     restarting (deploys, crashes, autoscaling). Design 1 fetches config at boot; design 2 boots from a locally
     persisted last-known-good config.
  B. Control-plane recovery: all hosts reconnect at once vs jittered reconnect vs constant work (every host pulls a
     full snapshot on a fixed schedule, whether or not anything changed).
  C. A bad config pushed globally vs in validated waves: hosts serving bad config, and host-minutes of impact.
Standard library only; seeded, deterministic.
"""
import random


def outage_capacity(design: str, hosts: int = 1000, restart_per_hour: float = 0.10, hours: float = 4.0,
                    seed: int = 4) -> dict:
    """Each minute, each host restarts w.p. restart_per_hour/60. A restarting host needs config to serve."""
    rng = random.Random(seed)
    serving = [True] * hosts
    curve = []
    for minute in range(int(hours * 60)):
        for h in range(hosts):
            if rng.random() < restart_per_hour / 60:
                serving[h] = design == "boot from local last-known-good"
        curve.append(sum(serving) / hosts)
    return {"min_capacity": min(curve), "end_capacity": curve[-1],
            "capacity_at_1h": curve[59], "lost_host_hours": sum(1 - c for c in curve) * hosts / 60}


def reconnect_peak(mode: str, hosts: int = 10_000, window_s: int = 60, period_s: int = 30, seed: int = 5) -> dict:
    """Peak control-plane requests per second right after it recovers (each host needs one full sync)."""
    rng = random.Random(seed)
    per_sec = [0] * 600
    if mode == "all reconnect immediately":
        per_sec[0] = hosts
    elif mode == "jittered reconnect (uniform over 60 s)":
        for _ in range(hosts):
            per_sec[int(rng.uniform(0, window_s))] += 1
    else:                                                # constant work: same load before, during and after
        for h in range(hosts):
            phase = rng.uniform(0, period_s)
            t = phase
            while t < 600:
                per_sec[int(t)] += 1
                t += period_s
    return {"peak": max(per_sec), "steady": sum(per_sec[300:600]) / 300}


def bad_push(plan: list, hosts: int = 1000, detect_min: float = 5.0, bake_min: float = 15.0) -> dict:
    """A config that breaks the data plane is detected detect_min after the first wave lands; wave i starts at
    i * bake_min only if nothing was detected yet. Impact on a host lasts from its wave's start until detection."""
    affected, impacted = 0, 0.0
    for i, frac in enumerate(plan):
        start = i * bake_min
        if start >= detect_min:
            break                                        # detected during the bake: rollout halted and reverted
        newly = int(frac * hosts) - affected
        affected += newly
        impacted += newly * (detect_min - start)
    return {"hosts_affected": affected, "host_minutes": impacted}


def main() -> None:
    print("== A. 4 h control-plane outage, 1,000 hosts, 10%/h restarts (deploys, crashes, scale events)")
    oc = {}
    for design in ("fetch config at boot", "boot from local last-known-good"):
        oc[design] = outage_capacity(design)
        r = oc[design]
        print(f"  {design:<34} capacity after 1 h {r['capacity_at_1h'] * 100:5.1f}%  after 4 h "
              f"{r['end_capacity'] * 100:5.1f}%  lost host-hours {r['lost_host_hours']:7.1f}")
    burst = outage_capacity("fetch config at boot", restart_per_hour=0.5, hours=1.0)
    print(f"  same outage during a rolling deploy (50%/h restarts), fetch-at-boot: capacity after 1 h "
          f"{burst['end_capacity'] * 100:5.1f}%")

    print("\n== B. control plane comes back: 10,000 hosts each need a full sync")
    rc = {}
    for mode in ("all reconnect immediately", "jittered reconnect (uniform over 60 s)",
                 "constant work (full snapshot every 30 s)"):
        rc[mode] = reconnect_peak(mode)
        print(f"  {mode:<42} peak {rc[mode]['peak']:>6} req/s   steady {rc[mode]['steady']:>6.0f} req/s")

    print("\n== C. a bad config, detected 5 min after it first lands; 15 min bake between waves")
    bp = {}
    for name, plan in (("global push", [1.0]), ("waves 1% -> 10% -> 50% -> 100%", [0.01, 0.10, 0.5, 1.0])):
        bp[name] = bad_push(plan)
        print(f"  {name:<34} hosts that received it {bp[name]['hosts_affected']:>5}   "
              f"impacted host-minutes {bp[name]['host_minutes']:>7.0f}")

    a, b = oc["fetch config at boot"], oc["boot from local last-known-good"]
    assert b["end_capacity"] == 1.0 and a["end_capacity"] < 0.75 and burst["end_capacity"] < 0.7
    assert rc["all reconnect immediately"]["peak"] > 50 * rc["jittered reconnect (uniform over 60 s)"]["peak"]
    cw = rc["constant work (full snapshot every 30 s)"]
    assert cw["peak"] < 1.5 * cw["steady"]
    assert bp["waves 1% -> 10% -> 50% -> 100%"]["host_minutes"] < bp["global push"]["host_minutes"] / 50
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. 4 h control-plane outage, 1,000 hosts, 10%/h restarts (deploys, crashes, scale events)
  fetch config at boot               capacity after 1 h  89.8%  after 4 h  69.1%  lost host-hours   668.1
  boot from local last-known-good    capacity after 1 h 100.0%  after 4 h 100.0%  lost host-hours     0.0
  same outage during a rolling deploy (50%/h restarts), fetch-at-boot: capacity after 1 h  58.8%

== B. control plane comes back: 10,000 hosts each need a full sync
  all reconnect immediately                  peak  10000 req/s   steady      0 req/s
  jittered reconnect (uniform over 60 s)     peak    192 req/s   steady      0 req/s
  constant work (full snapshot every 30 s)   peak    359 req/s   steady    333 req/s

== C. a bad config, detected 5 min after it first lands; 15 min bake between waves
  global push                        hosts that received it  1000   impacted host-minutes    5000
  waves 1% -> 10% -> 50% -> 100%     hosts that received it    10   impacted host-minutes      50

self-test: all assertions passed
```

---

## 7. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Plane separation | — | Knows control vs data plane | Audits every dependency for "would a restarting host serve traffic during a 4 h outage?"; makes the data plane boot from LKG |
| Capacity | Autoscaling | Multi-AZ with headroom | Pre-provisioned static stability, priced as a multiplier; never relies on scaling to recover from zonal loss |
| Config | "Use a config service" | Versioned configs; canaries | Config pipelines equal to code pipelines; data-plane validation with LKG; monotonic signed versions; kill switches |
| Distribution | Push deltas | Pull with caching; jittered reconnect | Constant work to make the worst case equal the normal case; no recovery-only code paths |
| Degradation | Error pages | Fallbacks and stale data | Designed degradation ladders, triggered automatically, exercised continuously; avoids bimodal behavior |

---

## 8. Bar-raiser probing chains

### Chain A: "Our config service is down. What happens?"

1. **L5:** "Services use cached config."
2. **Probe:** "A host reboots." **L6:** "It reads config from local disk (LKG) and starts."
3. **Probe:** "It also needs a TLS cert and a DB password from the secrets service, which is also down." **L7:**
   - "Credentials are persisted, encrypted at rest, with validity far longer than any plausible outage (days), and
     rotated proactively."
   - "Startup has zero synchronous control-plane calls. That's verified by a test that boots a host with the control
     plane firewalled off."
   - "The secrets service failing can delay *rotation*, not *serving*."

### Chain B: "Design the configuration push for 50,000 edge servers."

1. **L5:** "Push changes from a central server to all servers."
2. **Probe:** "A bad config crashes the proxy." **L6:** "Canary first, then roll out gradually with health checks."
3. **Probe:** "Some configs must reach every server within 60 s (blocking an attack)." **L7:**
   - Two classes:
     - normal changes take hours of waves with bake;
     - emergency changes have a narrow, pre-validated schema (IP/ASN block lists), still staged in minute-scale waves
       across PoP groups.
   - Every server validates before applying and keeps LKG.
   - Distribution is constant-work pull of the full snapshot, so the system doesn't melt during attacks.
   - Every change is signed and monotonically versioned.
   - Kill switch: a single flag that freezes all config changes fleet-wide, itself distributed by the same robust
     path.

### Chain C: "Make our API survive a regional control-plane failure in the cloud provider."

1. **L5:** "Fail over to another region."
2. **Probe:** "Failover itself needs the control plane: launching instances, changing DNS." **L6:** "Keep warm
   capacity in the second region, and use data-plane DNS health checks rather than control-plane API calls to
   shift traffic."
3. **Probe:** "Prove it works." **L7:**
   - Every region runs active-active at ≤ 50% (or N+1 across 3+ regions), so evacuation needs no launches.
   - Traffic shifting uses data-plane mechanisms only: health-checked DNS failover, or routing controls built for
     this (AWS ARC).
   - Quarterly evacuation drills with the provider's control-plane APIs blocked by IAM deny policies during the
     drill.
   - Prices the capacity (2× for 2 regions, 1.5× for 3) against the revenue at risk.

---

## 9. Invariants checklist

- [ ] Every dependency is classified as control or data plane; no synchronous control-plane calls on the request path
      or at boot.
- [ ] Data planes persist LKG config, routes, maps and credentials; restart-under-outage is tested.
- [ ] Capacity for zonal/regional loss is pre-provisioned; recovery does not depend on scaling APIs.
- [ ] Configs flow through validated, staged, auto-rolled-back pipelines; data planes validate before apply; versions
      are monotonic and signed; kill switches exist.
- [ ] Distribution is constant-work or jittered; full resyncs are rate-limited and exercised regularly.
- [ ] Degradation ladders are defined, automatic, visible and drilled; fallbacks are exercised in normal operation or
      removed.

---

## 10. References

- AWS Builders' Library:
  - *Static stability using Availability Zones* (B. Vig, M. Brooker et al.);
  - *Avoiding fallback in distributed systems* (J. Ernst);
  - *Reliability, constant work, and a good cup of coffee* (C. MacCárthaigh);
  - *Minimizing correlated failures in distributed systems*.
- AWS Fault Isolation Boundaries whitepaper (control planes and data planes; static stability).
- Cloudflare Blog. *Details of the Cloudflare outage on July 2, 2019.*
- Meta Engineering. *More details about the October 4 outage*, 2021.
- CrowdStrike. *Preliminary Post Incident Review* / *Root Cause Analysis*, July–August 2024.
- Google Cloud. *Incident report*, Service Control, June 2025 (⚠ verify the URL).
- B. Beyer et al. *The Site Reliability Workbook* (2018): configuration design, canarying.
