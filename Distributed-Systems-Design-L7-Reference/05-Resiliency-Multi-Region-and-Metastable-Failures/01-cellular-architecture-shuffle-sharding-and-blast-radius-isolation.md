# Cellular Architecture, Shuffle Sharding, and Blast-Radius Isolation

> **Folder 05 · File 01** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:**
> - [Folder 01 file 01 §6.3](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/01-l5-vs-l6-vs-l7-interview-evaluation-rubric-and-signals.md#63-availability-composition-and-why-redundancy-lies)
>   (shared fate caps availability);
> - [§6.5](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/01-l5-vs-l6-vs-l7-interview-evaluation-rubric-and-signals.md#65-queueing-knees-and-the-cell-tax)
>   (the cell tax);
> - [Folder 01 file 02 §7.7](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/02-hardware-network-physics-latency-numbers-and-finops-math.md#77-the-price-of-static-stability)
>   (static-stability multipliers).
>
> **Listing:** `blast_radius_lab.py` covers:
> - exact shuffle-sharding combinatorics, checked by Monte Carlo;
> - no isolation vs cells vs shuffle shards;
> - deployment-wave exposure when a defect manifests in only some cells.
>
> The output is deterministic.

---

## 0. Why this is the most L7 topic in the KB

File 01 §6.3 of Folder 01 showed that **availability past ~4 nines is set by the shared-fate fraction ρ**, not by
replica count. Ten percent of outages being common-mode caps you at 99.99%, regardless of redundancy. Shared fate
comes from:
- the same software version (bad deploys);
- the same configuration (bad pushes);
- the same dependencies (a database, IAM, DNS);
- the same "poison" inputs (a request that crashes every worker that parses it);
- the same tenants: a noisy neighbor consuming shared capacity.

**Blast-radius engineering** is the discipline of shrinking ρ by design. It has two tools:
- **Cells:** independent, complete copies of the stack, each serving a subset of tenants.
- **Shuffle sharding:** each tenant spread over a random subset of resources, so tenants rarely share their whole
  fate.

Together with control-plane/data-plane separation (file 03) and overload discipline (file 02), these are what the
brief means by "a poison-pill request can only impact < 0.5% of tenants".

---

## 1. Failure domains

| Domain | Typical blast radius | Isolation mechanism |
|---|---|---|
| Process / host | 1 host | Redundancy + health checks |
| Rack / power / ToR | 1 rack | Spread replicas across racks |
| AZ | 1/3 of a region | Multi-AZ, static stability (pre-provisioned 1.5×) |
| Region | Everything in a region | Multi-region, regional independence |
| **Deployment** | Everything running the version | Waves, bake time, automatic rollback |
| **Configuration** | Everything reading the config | Staged config rollout, validation, last-known-good |
| **Dependency** | Everything calling it | Per-cell dependencies, timeouts, fallbacks with care |
| **Tenant / input** | Everything that processes the input | **Cells, shuffle sharding**, per-tenant quotas |
| **Control plane** | Everything that needs changes | Static stability (file 03) |

Most large outages are in the bold rows, not the hardware rows. Infrastructure redundancy does nothing for them.

---

## 2. Cellular architecture

### 2.1 The shape

```
                         ┌───────────────────────────────┐
  request ──► edge ──►   │  CELL ROUTER (thin, stateless) │  tenant → cell map (cached; data plane)
                         └──────┬───────────┬────────────┘
                 ┌──────────────┘           └─────────────┐
        ┌────────▼─────────┐  ┌──────────────────┐  ┌─────▼────────────┐
        │ CELL 1           │  │ CELL 2           │  │ CELL N           │   each cell: full stack
        │ LB · services    │  │ LB · services    │  │ LB · services    │   (compute, DB, cache, queues)
        │ DB · cache · MQ  │  │ DB · cache · MQ  │  │ DB · cache · MQ  │   fixed MAX size
        │ tenants A..F     │  │ tenants G..M     │  │ tenants ...      │   deployed independently
        └──────────────────┘  └──────────────────┘  └──────────────────┘
  control plane: cell provisioning, tenant placement/migration, deploy orchestration (waves by cell)
```

### 2.2 Design rules

1. **The router must be the most boring component in the system.**
   - It is stateless.
   - It uses a cached `tenant → cell` map, with a static default and a fallback hash for unknown tenants.
   - It has no dependencies on the request path.
   - It is deployed *last* and *most carefully*. A bug in it has the blast radius the cells were built to avoid.
2. **Cells have a maximum size.** Limits are the point: a cell that only grows is a monolith. A fixed max size (hosts,
   tenants, QPS, data) means:
   - load tests of one cell describe every cell;
   - scaling = adding cells;
   - unknown scale ceilings are not discovered in production.
3. **No cross-cell calls on the request path.** Cross-cell needs (global search, admin views, billing) go through
   asynchronous aggregation, or through a separate global service with its own isolation.
4. **Each cell has its own data stores and dependencies.** A shared database undoes the cell. A shared dependency
   such as auth must itself be cellular or statically stable.
5. **Deploy by cell, in waves** (§5), and **rebalance tenants by migration**:
   1. copy;
   2. dual-write or catch up via CDC;
   3. freeze writes briefly;
   4. flip the map entry;
   5. unfreeze.

   The map flip is the only control-plane action, and it is reversible.
6. **Whales get their own cells.** The largest tenants are the most likely noisy neighbors. Isolating them protects
   everyone else, and them.

### 2.3 Sizing: the two opposing taxes

- **Queueing tax** (Folder 01 file 01 §6.5): smaller pools must run cooler. 16 servers per cell is safe to ~92%
  utilization at 1.5× service time; 4 servers only to ~75%.
- **Static-stability tax** (Folder 01 file 02 §7.7): surviving the loss of one of $z$ zones needs $z/(z-1)$ headroom,
  applied *inside every cell* that spans AZs.
- **Operational tax:** each cell is something to deploy, monitor and patch. Hundreds of cells need full automation.

The typical industry landing zone is tens to low hundreds of cells, each large enough (tens to hundreds of hosts) to
keep the queueing tax small. Public examples: AWS services' internal cells; Slack's cellular migration (2023), which
was AZ-aligned; DoorDash; Roblox. ⚠ verify the specifics in Folder 10.

---

## 3. Shuffle sharding: the math

### 3.1 The construction

- $N$ workers (servers, queues, partitions, name servers).
- Each tenant is assigned a **random subset of $k$ workers** (its shuffle shard) and may use any of them.
- Clients retry across the shard's members.

A **poison-pill tenant**, whose requests crash the workers that handle them, takes down only its own $k$ workers.
Another tenant's experience depends on how many of its $k$ workers overlap with the poisoned set. The overlap $J$ is
hypergeometric:

$$P(J = j) = \frac{\binom{k}{j}\binom{N-k}{k-j}}{\binom{N}{k}}, \qquad P(\text{fully down}) = P(J = k) = \frac{1}{\binom{N}{k}}$$

§A of the output checks the formula by Monte Carlo (N = 20, k = 4, 200k tenants). Exact and simulated agree to
~0.002 at every j.

### 3.2 Strategies compared (§B: 10,000 tenants, 100 workers, one poison tenant)

| Strategy | Tenants fully down | Lost > half their workers | Any impact |
|---|---|---|---|
| No isolation (every worker serves every tenant) | **100%** | 100% | 100% |
| Fixed cells of 5 (20 cells) | **5%** (500 tenants) | 5% | 5% |
| **Shuffle shards, 5 of 100** | **1.3×10⁻⁸ per tenant** (0.00013 tenants expected) | **0.06%** | 23% (lose 1–2 of 5 workers, absorbed by retries) |

- Fixed cells bound the blast radius at $k/N$ = 5%.
- **Shuffle sharding makes "fully down" a one-in-75-million event**, because the poison tenant's exact combination is
  shared by essentially no one.
- Only 0.06% of tenants lose more than half their capacity. **That is the brief's "< 0.5% of tenants", achieved with
  one order of magnitude of margin.**
- The 23% with "any impact" lose one or two of five workers, which client retries across the shard absorb.
- At **Route 53-style** scale (2,048 virtual name servers, 4 per customer), there are **730,862,190,080** possible
  shards (AWS Builders' Library).

Choosing $k$:
- **Larger $k$** shrinks full overlap super-exponentially (k = 8: 5×10⁻¹²). But it increases the number of tenants
  that see *some* impact, and every tenant's dependence on more workers.
- **Smaller $k$** limits each tenant's capacity and resilience.
- The practical range is k = 2–8. Choose it so that "lost a majority" is below the target and per-tenant capacity
  (k workers) covers the tenant's peak.

### 3.3 Making shuffle sharding real

- **Clients must retry on a *different* shard member.** Without that, partial overlap is full impact for the requests
  that land on a dead worker.
- **Stable assignment** (a deterministic hash of the tenant ID → combination, or a stored assignment) keeps caches
  warm and makes debugging possible.
- **Poison detection still matters.** Shuffle sharding limits *who* is hurt; you must still quarantine the poison
  input:
  - crash-loop detection keyed by tenant and request signature;
  - dead-letter queues;
  - per-tenant circuit breakers.
- **It applies to anything with N interchangeable resources:**
  - queue workers;
  - SQS-style queues per tenant;
  - DNS name servers;
  - API frontends;
  - partitions;
  - even *cells*: a tenant can be in two cells of a larger set.

---

## 4. Noisy neighbors: capacity isolation

Shuffle sharding limits *crash* blast radius. *Resource* abuse also needs:

| Mechanism | Granularity | Notes |
|---|---|---|
| Per-tenant rate limits and quotas | Requests, bytes, concurrency | Token buckets at the edge and in each service (Folder 06 problem 5) |
| Per-tenant concurrency limits | In-flight requests | Bounds the queue share a tenant can take (Little's law) |
| Weighted fair queueing | Per-tenant queues, round-robin service | Prevents one tenant's burst from adding latency to others |
| Cost-based admission | Expensive queries count more | Search and analytics workloads |
| Isolation of whales | Dedicated cells/shards | The top 1% of tenants often drive 50% of load |

---

## 5. Deployments and configuration: the shared-fate killers

### 5.1 Waves

§C of the output (100 cells; a defect detected 10 min after it first manifests; 30 min bake between waves):

| Defect manifests in | All at once | 1% → 10% → 100% | 1 → 2 → 5 → 10 → 25 → 50 → 100% |
|---|---|---|---|
| 100% of cells | **1,000** cell-minutes | **10** | 10 |
| 20% of cells | 199 | 36 | 14 |
| 5% of cells | 50 | 32 | 14 |

- If the defect shows up everywhere, a single one-cell canary catches it: 100× less impact.
- **Defects that manifest in only some cells** (a data-dependent bug, a single tenant's input, one hardware type)
  slip past a single canary. **More, smaller early waves** keep the expected impact low (14 cell-minutes) even at 5%
  manifestation.
- **Bake time must exceed the time to detect.** Detection needs SLO-based automated alarms per cell, not humans
  watching dashboards.

### 5.2 Waves over time *and* space

The AWS deployment practice that is widely described publicly:
1. **One box** (a single host), then one AZ of one region.
2. One region at a time.
3. Never two regions concurrently early on.
4. Increasing wave sizes, with bake times of hours early and less later.
5. **Automatic rollback** on alarm.

Configuration changes follow the *same* pipeline as code, because a config is code. Folder 05 file 03 covers the
outages that skipped this.

---

## 6. The listing

```python
"""blast_radius_lab.py - shuffle sharding, cells, and deployment waves, computed exactly (Folder 05, file 01).

  A. Shuffle sharding: each tenant gets a random k-subset of N workers. A poison-pill tenant crashes its k workers.
     Exact hypergeometric overlap distribution for any other tenant, checked by Monte Carlo.
  B. Isolation strategies for 10,000 tenants on 100 workers: none vs fixed cells vs shuffle shards.
  C. Deployment waves: expected impacted cell-minutes of a bad change, all-at-once vs staged waves with bake time,
     when the defect manifests in only some cells.
Standard library only; seeded, deterministic.
"""
import math
import random


def overlap_pmf(n: int, k: int) -> list[float]:
    """P(another tenant's k-subset shares exactly j workers with the poison tenant's k-subset)."""
    total = math.comb(n, k)
    return [math.comb(k, j) * math.comb(n - k, k - j) / total for j in range(k + 1)]


def monte_carlo(n: int, k: int, tenants: int, rng: random.Random) -> list[float]:
    poison = set(rng.sample(range(n), k))
    counts = [0] * (k + 1)
    for _ in range(tenants):
        counts[len(poison & set(rng.sample(range(n), k)))] += 1
    return [c / tenants for c in counts]


def strategies(n: int, k: int, tenants: int) -> dict:
    pmf = overlap_pmf(n, k)
    lose_majority = sum(pmf[j] for j in range(k // 2 + 1, k + 1))
    return {
        "no isolation (every worker serves every tenant)": {"full": 1.0, "any": 1.0, "majority": 1.0},
        f"fixed cells of {k} ({n // k} cells)": {"full": k / n, "any": k / n, "majority": k / n},
        f"shuffle shards, {k} of {n}": {"full": pmf[k], "any": 1 - pmf[0], "majority": lose_majority},
    }


def waves(cells: int, p_manifest: float, detect_min: float, plan: list[float], bake_min: float,
          trials: int, rng: random.Random) -> float:
    """Expected impacted cell-minutes. A defect manifests in each exposed cell independently with p_manifest and is
    detected detect_min after it first manifests; the rollout halts at detection. Waves are fractions of the fleet;
    each wave bakes bake_min before the next starts. Impact ends at detection (rollback is assumed instant)."""
    total = 0.0
    for _ in range(trials):
        manifests = [rng.random() < p_manifest for _ in range(cells)]
        order = list(range(cells))
        rng.shuffle(order)
        t, exposed, start_of = 0.0, 0, {}
        detect_at = math.inf
        for frac in plan:
            upto = max(exposed + 1, round(frac * cells))
            for c in order[exposed:upto]:
                start_of[c] = t
                if manifests[c]:
                    detect_at = min(detect_at, t + detect_min)
            exposed = upto
            if detect_at <= t + bake_min or exposed >= cells:
                break
            t += bake_min
        total += sum(max(0.0, min(detect_at, 240.0) - s) for c, s in start_of.items() if manifests[c])
    return total / trials


def main() -> None:
    rng = random.Random(53)
    print("== A. overlap with a poison tenant's workers: exact vs Monte Carlo (N=20, k=4, 200k tenants)")
    exact, mc = overlap_pmf(20, 4), monte_carlo(20, 4, 200_000, rng)
    for j, (e, m) in enumerate(zip(exact, mc)):
        print(f"  shares {j} workers: exact {e:.6f}   simulated {m:.6f}")
    print(f"  Route 53-style: 2048 virtual servers, 4 per customer -> C(2048,4) = {math.comb(2048, 4):,} shuffle shards")

    print("\n== B. 10,000 tenants on 100 workers; one poison tenant crashes its workers")
    print(f"{'strategy':<48} {'fully down':>12} {'lost majority':>14} {'any impact':>11}")
    st = strategies(100, 5, 10_000)
    for name, r in st.items():
        print(f"{name:<48} {r['full'] * 100:>11.6f}% {r['majority'] * 100:>13.4f}% {r['any'] * 100:>10.2f}%")
    full_tenants = st["shuffle shards, 5 of 100"]["full"] * 10_000
    print(f"  expected tenants fully down with shuffle sharding: {full_tenants:.5f} (vs 500 with fixed cells)")
    for k in (2, 3, 4, 5, 8):
        pmf = overlap_pmf(100, k)
        print(f"  k={k}: P(another tenant fully overlaps) = {pmf[k]:.3e}; P(loses > half its workers) = "
              f"{sum(pmf[j] for j in range(k // 2 + 1, k + 1)):.3e}")

    print("\n== C. bad change across 100 cells, detected 10 min after it first manifests (impact cell-minutes)")
    plans = {"all at once": [1.0], "1% -> 10% -> 100%, 30 min bake": [0.01, 0.10, 1.0],
             "1 -> 2 -> 5 -> 10 -> 25 -> 50 -> 100%, 30 min bake": [0.01, 0.02, 0.05, 0.10, 0.25, 0.5, 1.0]}
    wv = {}
    for pm in (1.0, 0.2, 0.05):
        for name, plan in plans.items():
            wv[(pm, name)] = waves(100, pm, 10.0, plan, 30.0, 4000, rng)
            print(f"  manifests in {pm * 100:>4.0f}% of cells | {name:<48} {wv[(pm, name)]:>8.1f} cell-minutes")

    for e, m in zip(exact, mc):
        assert abs(e - m) < 0.003
    assert abs(sum(exact) - 1) < 1e-12 and math.comb(2048, 4) > 7e11
    assert st["shuffle shards, 5 of 100"]["majority"] < 0.005 < st["fixed cells of 5 (20 cells)"]["full"]
    for pm in (1.0, 0.2):
        assert wv[(pm, "1% -> 10% -> 100%, 30 min bake")] < wv[(pm, "all at once")] / 5
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. overlap with a poison tenant's workers: exact vs Monte Carlo (N=20, k=4, 200k tenants)
  shares 0 workers: exact 0.375645   simulated 0.374155
  shares 1 workers: exact 0.462332   simulated 0.464435
  shares 2 workers: exact 0.148607   simulated 0.147790
  shares 3 workers: exact 0.013209   simulated 0.013375
  shares 4 workers: exact 0.000206   simulated 0.000245
  Route 53-style: 2048 virtual servers, 4 per customer -> C(2048,4) = 730,862,190,080 shuffle shards

== B. 10,000 tenants on 100 workers; one poison tenant crashes its workers
strategy                                           fully down  lost majority  any impact
no isolation (every worker serves every tenant)   100.000000%      100.0000%     100.00%
fixed cells of 5 (20 cells)                         5.000000%        5.0000%       5.00%
shuffle shards, 5 of 100                            0.000001%        0.0599%      23.04%
  expected tenants fully down with shuffle sharding: 0.00013 (vs 500 with fixed cells)
  k=2: P(another tenant fully overlaps) = 2.020e-04; P(loses > half its workers) = 2.020e-04
  k=3: P(another tenant fully overlaps) = 6.184e-06; P(loses > half its workers) = 1.806e-03
  k=4: P(another tenant fully overlaps) = 2.550e-07; P(loses > half its workers) = 9.818e-05
  k=5: P(another tenant fully overlaps) = 1.328e-08; P(loses > half its workers) = 5.994e-04
  k=8: P(another tenant fully overlaps) = 5.374e-12; P(loses > half its workers) = 3.842e-05

== C. bad change across 100 cells, detected 10 min after it first manifests (impact cell-minutes)
  manifests in  100% of cells | all at once                                        1000.0 cell-minutes
  manifests in  100% of cells | 1% -> 10% -> 100%, 30 min bake                       10.0 cell-minutes
  manifests in  100% of cells | 1 -> 2 -> 5 -> 10 -> 25 -> 50 -> 100%, 30 min bake     10.0 cell-minutes
  manifests in   20% of cells | all at once                                         199.2 cell-minutes
  manifests in   20% of cells | 1% -> 10% -> 100%, 30 min bake                       36.2 cell-minutes
  manifests in   20% of cells | 1 -> 2 -> 5 -> 10 -> 25 -> 50 -> 100%, 30 min bake     14.1 cell-minutes
  manifests in    5% of cells | all at once                                          49.9 cell-minutes
  manifests in    5% of cells | 1% -> 10% -> 100%, 30 min bake                       32.3 cell-minutes
  manifests in    5% of cells | 1 -> 2 -> 5 -> 10 -> 25 -> 50 -> 100%, 30 min bake     14.1 cell-minutes

self-test: all assertions passed
```

---

## 7. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Isolation | Redundant servers | Multi-AZ; per-tenant rate limits | Shared fate (ρ) as the availability ceiling; cells and shuffle sharding to shrink it; quantified blast radius |
| Cells | — | Knows the pattern | Router design (boring, cached, no deps), max cell size, no cross-cell calls, tenant migration, cell sizing between the queueing and static-stability taxes |
| Shuffle sharding | — | "Random subsets of workers" | Hypergeometric math; choosing k against "lost majority" targets; retries across shard members; poison quarantine still required |
| Deploys | "CI/CD" | Canaries and rollbacks | Wave plans sized for partial-manifestation defects; bake > time-to-detect; config through the same pipeline |

---

## 8. Bar-raiser probing chains

### Chain A: "A customer's malformed request crashes our parsing workers."

1. **L5:** "Fix the parser and add input validation."
2. **Probe:** "There will always be another bug. What limits the damage next time?" **L6:**
   - Crash-loop detection quarantines that tenant's traffic.
   - Retries are capped, so the request doesn't hop worker to worker killing each.
   - Big tenants are isolated in dedicated pools.
3. **Probe:** "We have 10,000 tenants and 100 workers. Bound the impact." **L7:**
   - Shuffle-shard: each tenant on 5 of 100 workers, with retries across them.
   - The poison tenant can only crash its 5 workers. Any other tenant fully overlaps with probability 1.3×10⁻⁸, and
     only 0.06% lose a majority.
   - Plus quarantine keyed by request signature, so even the poison tenant's healthy requests keep flowing.
   - "Our SLO for 'one tenant can harm others' becomes measurable."

### Chain B: "Move our monolithic SaaS to cells."

1. **L5:** "Shard the database by tenant."
2. **Probe:** "Only the database?" **L6:** "Every stateful component and dependency goes per cell, with a cell router
   and per-cell deploys."
3. **Probe:** "Plan the migration and the hard parts." **L7:**
   - The router comes first, with every tenant mapped to "cell 0" (today's stack), so routing is in place before
     anything moves.
   - Build cell 1, migrate internal and test tenants via copy → CDC catch-up → freeze → flip, then low-risk tenants.
   - Hard parts:
     - cross-tenant features (global search, admin) become async aggregates;
     - global uniqueness (usernames) becomes a separate small global service with its own isolation;
     - billing reads from per-cell event streams.
   - Size cells at tens of hosts to keep the queueing tax small.
   - Success metric: max blast radius, which for us means the % of tenants impacted per incident.

### Chain C: "Our last outage was a config push that took down every region."

1. **L5:** "Review config changes more carefully."
2. **Probe:** "Reviews don't scale." **L6:** "Validate configs automatically and roll them out like code: canary,
   bake, waves."
3. **Probe:** "Some configs must propagate fast (security blocks)." **L7:**
   - Two pipelines:
     - normal configs: staged by cell and region, with bake and auto-rollback;
     - urgent configs: a narrow schema, a small blast-radius-reviewed set of keys, still staged but with minute-level
       waves, plus a kill switch.
   - Data planes reject configs that fail local validation, and keep running last-known-good.
   - "In every case, a config can never take the data plane down by *arriving*; at worst it fails to apply."

---

## 9. Invariants checklist

- [ ] The shared-fate sources (deploy, config, dependency, tenant input, control plane) are listed, and each has an
      isolation mechanism.
- [ ] Cells: boring cached router, max size, no cross-cell request paths, per-cell dependencies, migration tooling.
- [ ] Shuffle sharding: k chosen against the "lost majority" target; clients retry across shard members; poison
      quarantine.
- [ ] Per-tenant quotas, concurrency limits and fair queueing; whales isolated.
- [ ] Deployments and configs flow through waves with bake > time-to-detect and automatic rollback.
- [ ] Blast radius is a measured SLI per incident (% of tenants affected).

---

## 10. References

- AWS Builders' Library. *Workload isolation using shuffle-sharding* (C. MacCárthaigh); *Automating safe, hands-off
  deployments*; *Static stability using Availability Zones*.
- AWS Well-Architected. *Reducing the Scope of Impact with Cell-Based Architecture*, 2023.
- Slack Engineering. *Slack's Migration to a Cellular Architecture*, 2023.
- N. Bronson et al. *Metastable Failures in Distributed Systems.* HotOS 2021 (why isolation matters for recovery).
- B. Beyer et al. *The Site Reliability Workbook* (2018), canarying releases and configuration management.
