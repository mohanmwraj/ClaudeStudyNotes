# 04.3 · Attacks on Security, Compliance, Multi-Tenancy and Day-2 Operations (Questions 18–25)

> **Folder:** `04-Surviving-the-25-Brutal-Bar-Raiser-Cross-Examination-Questions` · file 3 of 3
> **Question this file answers:** the last third of a deep dive often leaves the happy path entirely. What happens when one tenant floods you, when an auditor asks who changed a value, when a customer demands erasure from an immutable log, when it's 3 a.m.? These 8 questions test whether you operated the system or just shipped it.
> **Exhibits:** P-0 Beacon, A·Tidewater, B·Tillpoint, C·Quickset, D·Flightline.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L13 `tenant_sim.py` | Python 3, standard library | Part 1 is a seeded 1 ms-step simulation: 10 tenants share a 1,000 req/s pool while 1 of them bursts 20×. It compares 4 admission policies: shared FIFO, fair queueing (DRR), per-tenant token-bucket quota, and quota + DRR, reporting quiet and noisy tenants' p50/p99 and the rejections. Part 2 lints cache-key templates for missing tenant scope. | [§6](#6-the-tenant-simulator), on this file's two key tables |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, re-runs it on this file, and compares the result with §6. The tool's verdict confirms that FIFO lets 1 tenant hurt all of them, that fair queueing and quotas isolate them, and that the l5 key table is flagged. Tellings are checked by the Folder 01 lints. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

Questions 18–25 come from the **operator's** point of view: the person who will be paged, audited or blamed. Interviewers use them to tell candidates who *ran* their systems in production from those who handed them off. Several have regulatory dimensions (erasure, audit). ⚠ Legal and compliance specifics vary by jurisdiction and program. The answers here show engineering mechanisms; they are not legal advice.

---

## 1. First principles: day 2 is most of a system's life

### 1.1 Four properties operators need, and the questions that test them

| Property | Question it answers | Questions here |
|---|---|---|
| **Isolation** | Can one tenant, team or workload hurt the others? | Q18, Q19 |
| **Control of secrets and identity** | Can credentials change without downtime or exposure? | Q20 |
| **Accountability** | Can we prove who did what, and undo or erase it? | Q21, Q22 |
| **Operability** | Can a tired human understand and fix it at 3 a.m.? Can it evolve without a flag day? Can its cost be explained? | Q23, Q24, Q25 |

### 1.2 The operator's answer pattern

1. **Name the mechanism,** not the intention ("per-tenant quotas at the edge", not "we ensure fairness").
2. **Name the evidence** that it works: a test, a simulation, a drill, an audit result.
3. **Name the residual risk** and who accepted it.
4. **Name your role in operating it:** on-call, runbook author, incident commander.

---

## 2. Defense cards: Questions 18–25

### Q18 · "One tenant sends 20× their normal traffic. What happens to everyone else?"

| | |
|---|---|
| **Tests** | Whether isolation is designed or assumed |
| **Trap** | "We autoscale", when the burst arrives faster than capacity, and autoscaling spends money on one tenant's spike |
| **Skeleton** | Admission control at the edge: per-tenant token buckets (rate + burst) → fair queueing inside the shared pool so one tenant's backlog doesn't delay others → shed with 429 and a retry-after → report per-tenant usage. The simulation in §6 shows quiet tenants' p99 at **4,401 ms under FIFO**, **6 ms under DRR**, **171 ms with a quota alone** (a transient set by the burst allowance), and **5 ms with quota + DRR** |
| **Numbers** | Per-tenant rate and burst; pool capacity; quiet-tenant p99 during a burst |
| **Variants** | Tillpoint: per-merchant quotas at the API edge. Beacon: per-namespace publish rate limits. Quickset: per-feature-group byte budgets (memory isolation). Shuffle sharding ([AWS Builders' Library](https://aws.amazon.com/builders-library/workload-isolation-using-shuffle-sharding/)) bounds the blast radius further. |

### Q19 · "Could tenant A ever see tenant B's data? Prove it can't."

| | |
|---|---|
| **Tests** | Defense in depth for the worst multi-tenant bug |
| **Trap** | "Every query filters by tenant id", which is enforced by convention, not by mechanism |
| **Skeleton** | Layers: (1) tenant identity from the authenticated token, never from the request body; (2) database enforcement, for example PostgreSQL row-level security policies keyed on a session tenant setting ([PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)); (3) **cache keys always tenant-scoped first** (§6 Part 2 lints templates); (4) a cross-tenant test suite that logs in as A and tries to read B everywhere; (5) per-tenant encryption keys where the data class warrants it |
| **Numbers** | Endpoints covered by cross-tenant tests; RLS policies per table; flagged key templates |
| **Variants** | Tillpoint: merchant id from the token; RLS on order tables. Quickset: feature keys are model-scoped, and the tenant is part of the key. Beacon: namespace ACLs, and SDK subscriptions limited by workload identity. |

### Q20 · "Rotate your signing keys and database credentials today, without downtime."

| | |
|---|---|
| **Tests** | Whether rotation was designed in or is a project |
| **Trap** | "We'd schedule a maintenance window" |
| **Skeleton** | **Signing keys:** signatures carry a key id; verifiers trust a *set* of keys; add the new key to the trusted set → wait longer than the longest verification-key cache (Beacon: 24 h) → start signing with the new key → retire the old one after its last signature can no longer be served. **DB credentials:** two valid credentials overlap (a secret manager with versioned secrets, or two DB roles); clients pick up the new one on their refresh interval; the old one is revoked after the max refresh interval. NIST SP 800-57 ([CSRC](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)) is the general reference for key management lifecycles |
| **Numbers** | Cache lifetimes; refresh intervals; overlap duration; time to rotate in an emergency |
| **Variants** | Beacon: KMS-held Ed25519 keys with key ids in snapshot headers; the SDK verification-key cache sets the overlap. Tillpoint: per-service DB roles rotated by the secret manager every 30 days. |

### Q21 · "A customer invokes their right to erasure. Their data is in your immutable log, your backups and your warehouse."

| | |
|---|---|
| **Tests** | Whether immutability and erasure were reconciled by design (⚠ the obligations depend on jurisdiction; GDPR Article 17 is the usual reference, [EUR-Lex](https://eur-lex.europa.eu/eli/reg/2016/679/oj)) |
| **Trap** | "We'd delete it from the database", forgetting logs, archives, backups and caches |
| **Skeleton** | **Inventory** every store holding personal data. **Warehouse/OLTP:** delete by subject key; partition rewrite where needed. **Immutable archives and logs:** crypto-shredding, with per-subject envelope keys, so deleting the key makes the data unreadable (Tidewater T2). **Backups:** retention-bounded expiry plus a suppression list applied on restore. **Caches:** TTL bound. **Prevention:** keep personal data out of logs; tokenize identifiers. Then document each store's erasure path and its deadline |
| **Numbers** | Stores in the inventory; time to complete an erasure; backup retention |
| **Variants** | Tidewater: per-policyholder envelope encryption after month 9; history handled by quarterly compaction. Tillpoint: tokenized card data; order PII in 2 stores. |

### Q22 · "An auditor asks who changed this config value on March 3rd and why. Show me."

| | |
|---|---|
| **Tests** | Accountability as a designed property |
| **Trap** | "We'd check the logs" (application logs rotate, and can be altered) |
| **Skeleton** | An append-only change log as the source of truth (who, when, diff, ticket, approver) → signed, versioned artifacts derived from it, so what was *deployed* is provably what was *approved* → access to the log is itself logged → tamper-evidence (hash-chaining entries, or write-once storage) where the audit demands it |
| **Numbers** | Retention; time to answer an audit query; fraction of changes with a ticket link |
| **Variants** | Beacon G5: every change attributable and reversible; the PCI namespaces' change policy requires a ticket (01.3 K3). Flightline: the configuration of the protocol IC's filter tables is under the same configuration management as the code. |

### Q23 · "It's 3 a.m. and you're paged. What paged you, and what does the runbook say?"

| | |
|---|---|
| **Tests** | Whether you were on call, and whether alerts are symptoms or noise |
| **Trap** | Describing dashboards, or alerts on CPU |
| **Skeleton** | Pages on **user-facing symptoms** tied to SLOs: error-budget **burn-rate** alerts at two windows (fast and slow), as in the SRE workbook ([Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)) → cause-level signals go to dashboards and tickets, not pages → each page links a runbook: first 5 minutes (assess the blast radius, the known-safe mitigations such as rollback or a kill switch), escalation, and what not to do → a page budget, with a review of every page |
| **Numbers** | Pages per week per rotation; % actionable; time to mitigate |
| **Variants** | Beacon: pages dropped from 11 to 2 a month; `config_defaults_served` > 0 pages (INC-B7). Tidewater: watermark lag > 10 min pages (INC-T7). Tillpoint: checkout error-budget burn. |

### Q24 · "You need to change a schema used by 300 services. How do you roll it out?"

| | |
|---|---|
| **Tests** | Evolution without a flag day |
| **Trap** | "Coordinate a release with all the teams" |
| **Skeleton** | **Expand → migrate → contract** (Fowler's parallel change, [martinfowler.com](https://martinfowler.com/bliki/ParallelChange.html)): add the new form alongside the old (backward compatible); make consumers read both, then the new; make producers write both, then the new; remove the old form when telemetry shows no readers → compatibility rules enforced by a registry → consumer-driven contract tests → staged rollout with a kill switch |
| **Numbers** | Readers of the old form (from telemetry); migration duration; teams outstanding |
| **Variants** | Beacon's ZooKeeper migration: compat shims as the expand step, with deletion dates as the contract step. Tidewater's NOT NULL column (03.1 Q6). Tillpoint's money-type retrofit (02.3 §3.1). |

### Q25 · "Finance wants per-tenant cost. How do you attribute a shared system's cost?"

| | |
|---|---|
| **Tests** | Whether cost is observable at the unit that matters (02.2 §6) |
| **Trap** | "Divide by the number of tenants" |
| **Skeleton** | **Meter usage per tenant** at the resource that drives cost: requests, bytes stored, CPU-seconds, bytes transferred → allocate **variable cost** proportionally to metered usage → allocate **fixed or shared cost** by an agreed key (reserved capacity, or usage share), stated explicitly → **showback first, chargeback later** → unit costs per tenant reveal outliers, which feed back into quotas (Q18) ([FinOps Framework](https://www.finops.org/framework/)) |
| **Numbers** | Metered dimensions; % of cost directly attributable vs allocated; top-tenant share |
| **Variants** | Tidewater: cost per million events, per source system. Quickset: bytes per feature group (the same counters that enforce the memory cap). Beacon: per-namespace snapshot bytes × fan-out. |

---

## 3. Two cache-key tables (for Part 2 of the simulator)

<!-- cachekeys:start name=l5-cachekeys -->
| Key template | Value |
|---|---|
| `user:{user_id}:profile` | profile JSON |
| `order:{order_id}` | order summary |
| `{tenant_id}:catalog:{sku}` | catalog entry |
| `report:{report_id}:pdf` | rendered report |
<!-- cachekeys:end -->

<!-- cachekeys:start name=tillpoint-cachekeys -->
| Key template | Value |
|---|---|
| `{tenant_id}:user:{user_id}:profile` | profile JSON |
| `{tenant_id}:order:{order_id}` | order summary |
| `{tenant_id}:catalog:{sku}` | catalog entry |
| `{tenant_id}:report:{report_id}:pdf` | rendered report |
<!-- cachekeys:end -->

**Why this matters.** In the first table, `user:{user_id}` and `order:{order_id}` are safe *only if* ids are globally unique across tenants, and `report:{report_id}` is exactly the kind of key that, after an id-scheme change or a migration that restarts sequences, serves tenant B's report to tenant A. Scoping every key by tenant first removes the dependency on id uniqueness.

---

## 4. Tellings

### 4.1 The noisy neighbor

#### How an L5 tells it

> If one customer sends a lot of traffic, we autoscale, so everyone else is basically unaffected. The system is designed to be highly scalable for spikes like that.

#### How an L7 tells it

> Isolation is at 2 layers, and I can show why both are needed. In a simulation of 10 tenants sharing 1,000 requests a second, where 1 bursts to 20 times its normal rate, a shared FIFO queue puts the quiet tenants' p99 at about 4.4 seconds. Fair queueing across per-tenant queues keeps them at 6 milliseconds, but lets the noisy tenant build an 8-second backlog. A per-tenant token bucket alone still lets its 400-request burst allowance through, which costs the quiet tenants about 170 milliseconds. The combination holds them at 5 milliseconds and sheds about 7,600 of the noisy tenant's requests with 429s and a retry-after. Tillpoint runs exactly that pairing at the API edge, per merchant, and autoscaling, which takes about 3 minutes to add capacity, is the third layer for real growth, not the answer to a burst.

### 4.2 Erasure in an immutable archive

#### How an L5 tells it

> For GDPR deletion requests we delete the customer's records from the database. The archive is immutable, so we kind of just leave it, since it's only used for analytics.

#### How an L7 tells it

> I treat erasure as a property of every store, not of the database. For Tidewater I inventoried 6 stores holding policyholder data. The operational tables and the warehouse delete by subject key, with a partition rewrite in the warehouse. The raw GCS archive is immutable by design, so since month 9 each policyholder's records are encrypted under their own envelope key, and erasure deletes that key, which makes every archived copy unreadable. History from before month 9 is handled by a quarterly compaction. Backups expire within their 35-day retention, and a suppression list is applied on any restore. Every erasure request is tracked to completion across all 6 stores, and the longest path is the backup expiry.

### 4.3 The 3 a.m. page

#### How an L5 tells it

> We have dashboards and alerts on CPU, memory and errors, so if something goes wrong we get paged and the on-call engineer investigates it. The team was responsible for on-call, and it was pretty much fine.

#### How an L7 tells it

> I was on the Beacon rotation for 18 months, and I rewrote its alerts in month 4. Pages are on user-facing symptoms only: the error-budget burn rate for propagation latency at a 1-hour and a 6-hour window, and config_defaults_served above 0, which was the INC-B7 signal. CPU and relay restarts go to a dashboard and a ticket queue, because they never needed a human at 3 a.m. Every page links a runbook whose first 5 minutes are the same: check the blast radius in the version-skew dashboard, then pick from 2 safe mitigations, halting the rollout controller or rolling back the last relay deploy. Pages fell from about 11 a month to about 2, and every page gets a 15-minute review the next morning.

---

## 5. Hiring-committee scoring rubric: day-2 attacks

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Isolation** | "We autoscale" | Rate limits mentioned | Per-tenant quotas + fair scheduling | Quantified isolation; layered defenses; blast-radius bounds |
| **Data separation** | "We filter by tenant" | Tenant in every query | DB-enforced (RLS) + scoped cache keys | Plus a cross-tenant test suite and per-tenant keys where warranted |
| **Rotation** | Maintenance window | Manual procedure | Overlapping validity, key ids | Overlap derived from cache lifetimes; an emergency rotation time |
| **Erasure and audit** | "Delete from the DB" | Mentions backups | Store inventory, crypto-shredding | Each store's path and deadline; tamper-evident change log |
| **On-call** | Dashboards | Alerts exist | SLO burn-rate pages with runbooks | Was on call; tuned pages; measured the page reduction |
| **Evolution and cost** | Flag days; "divide by tenants" | Coordinated releases | Expand/migrate/contract; metered usage | Telemetry-driven contraction; showback → chargeback with stated allocation keys |

---

## 6. The tenant simulator

### 6.1 Listing L13: `tenant_sim.py`

<!-- listing:tenant_sim.py -->
```python
#!/usr/bin/env python3
"""tenant_sim.py - noisy neighbors and cross-tenant leaks, made measurable.

Part 1 - a seeded 1 ms-step simulation of one shared worker pool
(capacity 1,000 requests/s) serving 10 tenants at 50 requests/s each, when one
tenant bursts to 1,000 requests/s (20x) for 10 s. Three admission policies:
  FIFO       one shared queue: everyone waits behind the burst
  DRR        round robin across per-tenant queues (deficit round robin, equal quanta)
  QUOTA      per-tenant token bucket (200/s, burst 400) in front of FIFO; excess -> 429
  QUOTA+DRR  the bucket in front of the fair queue (the usual production pairing)
Reports p50/p99 latency for the quiet tenants and the noisy one, and rejections.

Part 2 - lint cache-key templates between
    <!-- cachekeys:start name=<label> -->  ...  <!-- cachekeys:end -->
(one template per table row, first column). A template whose first segment is
not {tenant_id} can collide across tenants: CROSS-TENANT RISK. Tables named
l5-* are negative examples expected to be flagged.
Usage: python -I tenant_sim.py <file.md>
"""
import random
import re
import sys
from collections import deque

TENANTS, NOISY, CAP_PER_MS = 10, 0, 1
SIM_MS, BURST = 30_000, (5_000, 15_000)


def arrivals(seed=11):
    rng = random.Random(seed)
    out = []
    for t in range(SIM_MS):
        for k in range(TENANTS):
            if k == NOISY and BURST[0] <= t < BURST[1]:
                n = 1                                    # 1,000 requests/s during the burst
            else:
                n = 1 if rng.random() < 0.05 else 0      # ~50 requests/s (Bernoulli per ms)
            out.append((t, k, n))
    return out


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else 0


def run(policy, arr):
    lat = {k: [] for k in range(TENANTS)}
    rejected = 0
    fifo = deque()
    queues = [deque() for _ in range(TENANTS)]
    tokens = [400.0] * TENANTS
    rr, deficit = 0, [0] * TENANTS
    idx = 0
    for t in range(SIM_MS + 20_000):
        while idx < len(arr) and arr[idx][0] == t:
            _, k, n = arr[idx]
            idx += 1
            for _ in range(n):
                if policy in ("QUOTA", "QUOTA+DRR"):
                    if tokens[k] < 1:
                        rejected += 1
                        continue
                    tokens[k] -= 1
                if policy in ("FIFO", "QUOTA"):
                    fifo.append((t, k))
                else:
                    queues[k].append(t)
        for k in range(TENANTS):
            tokens[k] = min(400.0, tokens[k] + 0.2)          # 200 per second
        for _ in range(CAP_PER_MS):
            if policy in ("FIFO", "QUOTA"):
                if fifo:
                    t0, k = fifo.popleft()
                    lat[k].append(t - t0)
            else:
                for _ in range(TENANTS):                     # DRR with a quantum of 1 request
                    k = rr
                    rr = (rr + 1) % TENANTS
                    if queues[k]:
                        deficit[k] += 1
                        if deficit[k] >= 1:
                            deficit[k] -= 1
                            lat[k].append(t - queues[k].popleft())
                            break
                    else:
                        deficit[k] = 0
    quiet = [x for k in range(TENANTS) if k != NOISY for x in lat[k]]
    return pct(quiet, 0.5), pct(quiet, 0.99), pct(lat[NOISY], 0.5), pct(lat[NOISY], 0.99), rejected


def keylint(md):
    out = []
    for name, body in re.findall(r"<!-- cachekeys:start name=(\S+) -->\n(.*?)<!-- cachekeys:end -->", md, re.S):
        rows = [r for r in body.splitlines() if r.strip().startswith("|")][2:]
        flags = []
        for r in rows:
            tpl = r.strip().strip("|").split("|")[0].strip().strip("`")
            if not tpl.startswith("{tenant_id}"):
                flags.append(tpl)
        out.append((name, len(rows), flags))
    return out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    md = open(sys.argv[1], encoding="utf-8").read().replace("\r\n", "\n")
    arr = arrivals()
    total = sum(n for _, _, n in arr)
    noisy = sum(n for _, k, n in arr if k == NOISY)
    print(f"Part 1: {total:,} requests in {SIM_MS // 1000} s; noisy tenant {noisy:,}; capacity 1,000/s")
    print("  policy   quiet p50   quiet p99   noisy p50   noisy p99   rejected (429)")
    res = {}
    for policy in ("FIFO", "DRR", "QUOTA", "QUOTA+DRR"):
        q50, q99, n50, n99, rej = run(policy, arr)
        res[policy] = (q99, rej, n99)
        print(f"  {policy:<9} {q50:>6} ms {q99:>8} ms {n50:>8} ms {n99:>8} ms   {rej:>8,}")
    ok = (res["FIFO"][0] > 1000 and res["DRR"][0] < 50 and res["QUOTA"][0] < res["FIFO"][0] / 10
          and res["QUOTA"][1] > 0 and res["QUOTA+DRR"][0] < 50 and res["QUOTA+DRR"][2] < res["DRR"][2])
    print()
    print("Part 2: cache-key templates")
    for name, n, flags in keylint(md):
        print(f"  {name}: {n} template(s), {len(flags)} without a leading tenant scope")
        for f in flags:
            print(f"    CROSS-TENANT RISK: {f}")
        ok &= bool(flags) == name.startswith("l5")
    print()
    print("verdict:", "OK (FIFO lets one tenant hurt all; fair queueing isolates; quota bounds the noisy tenant; l5 key table flagged)" if ok else "CHECK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 6.2 Output

<!-- output:tenant_sim.py -->
```text
Part 1: 24,534 requests in 30 s; noisy tenant 10,999; capacity 1,000/s
  policy   quiet p50   quiet p99   noisy p50   noisy p99   rejected (429)
  FIFO         911 ms     4401 ms     2139 ms     4427 ms          0
  DRR            0 ms        6 ms     3795 ms     8020 ms          0
  QUOTA          0 ms      171 ms        0 ms      216 ms      7,601
  QUOTA+DRR      0 ms        5 ms        0 ms      425 ms      7,601

Part 2: cache-key templates
  l5-cachekeys: 4 template(s), 3 without a leading tenant scope
    CROSS-TENANT RISK: user:{user_id}:profile
    CROSS-TENANT RISK: order:{order_id}
    CROSS-TENANT RISK: report:{report_id}:pdf
  tillpoint-cachekeys: 4 template(s), 0 without a leading tenant scope

verdict: OK (FIFO lets one tenant hurt all; fair queueing isolates; quota bounds the noisy tenant; l5 key table flagged)
```

**Reading the output.**
- **FIFO:** the quiet tenants inherit the burst (p99 4.4 s).
- **DRR:** isolates the quiet tenants (6 ms), but the noisy tenant's own backlog grows to an 8 s p99.
- **QUOTA alone:** bounds the noisy tenant by rejecting ~7,600 requests, but its burst allowance still costs the quiet tenants a 171 ms transient.
- **QUOTA+DRR:** gives both properties.
- **Part 2:** flags the three unscoped templates in `l5-cachekeys`.

---

## 7. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | Autoscaling as isolation | Everyone slows during one tenant's burst | Quotas + fair queueing (Q18) |
| F2 | Tenant filter by convention | One missed `WHERE` leaks data | RLS + token-derived tenant + tests (Q19) |
| F3 | Unscoped cache keys | Cross-tenant cache hits after an id change | Tenant-first keys, linted (§3, §6) |
| F4 | Rotation as a project | Keys never rotate | Key ids, trusted sets, overlap by design (Q20) |
| F5 | Erasure from the database only | PII persists in archives, backups, caches | Store inventory; crypto-shredding (Q21) |
| F6 | Audit from application logs | Can't prove who changed what | Append-only change log; signed artifacts (Q22) |
| F7 | Cause-based pages | Alert fatigue | Symptom/SLO burn-rate pages (Q23) |
| F8 | Flag-day migrations | Coordinated releases across 300 services | Expand → migrate → contract (Q24) |
| F9 | Equal cost splits | Finance distrusts the numbers | Metered usage + stated allocation keys (Q25) |

---

## 8. Bar-raiser chains

<details><summary><b>Q18 · "One tenant sends 20× their normal traffic. What happens to everyone else?"</b></summary>

**Initial Prompt.** On Tillpoint: "A merchant runs a flash sale and sends 20 times their usual traffic. Your other merchants?"

**L5 Answer.** "We autoscale based on load, so we'd add capacity and everyone would be fine."

**Why L5 Stalls.** The burst arrives in seconds and autoscaling takes minutes. Meanwhile one shared queue delays every merchant. And autoscaling spends money on one tenant's spike without consent.

**L7 Answer.** "Admission control decides it before capacity does. At the API edge each merchant has a token bucket sized to their plan, so a 20 times burst beyond the bucket's allowance gets 429s with a retry-after, not queue time. Inside the shared worker pool, requests are scheduled fair-share across merchants, so whatever the bucket admits can't push other merchants back. A simulation of exactly this shape puts the quiet tenants' p99 at about 4.4 seconds with a shared FIFO and about 5 milliseconds with quota plus fair queueing. The flash-sale merchant sees rejections, and their account team sees it in the usage report. If they need more, the bucket is raised deliberately, ahead of the sale."

</details>

<details><summary><b>Q19 · "Could tenant A ever see tenant B's data? Prove it can't."</b></summary>

**Initial Prompt.** "Not 'we're careful'. Prove it."

**L5 Answer.** "Every query includes the tenant id in the WHERE clause, and we review code to make sure of it."

**Why L5 Stalls.** Review-enforced filtering fails the first time someone writes a new query and the reviewer misses it. The interviewer asked for proof, which means mechanisms and tests, not care.

**L7 Answer.** "I can't prove a negative, but I can show the layers and the test that would catch a hole. The tenant id comes from the authenticated token, never the request body. The database enforces it: row-level security policies on every tenant table check a session variable set from the token at connection checkout, so a query missing its WHERE clause returns nothing rather than everything. Cache keys are tenant-scoped first, and a lint fails the build on any template that isn't. And a cross-tenant suite logs in as merchant A and tries every read endpoint with merchant B's ids. It runs in CI on every change, and it found 2 endpoints before launch that returned B's data from a shared cache."

</details>

<details><summary><b>Q20 · "Rotate your signing keys and database credentials today, without downtime."</b></summary>

**Initial Prompt.** On Beacon: "Your snapshot signing key is compromised. Rotate it now. Walk me through the next 24 hours."

**L5 Answer.** "We'd generate a new key in KMS, update the publisher to use it, and redeploy the SDKs with the new public key."

**Why L5 Stalls.** Redeploying 1,200 services' SDKs isn't a rotation plan, and switching signers before verifiers trust the new key makes every new snapshot unverifiable: a fleet-wide config freeze.

**L7 Answer.** "Rotation was designed in, so it's a procedure, not a project. Snapshots carry a key id, and the SDK trusts a set of keys fetched from the control plane and cached for up to 24 hours. For a compromise: first, add the new key to the trusted set and revoke the old one in it at the same moment. That alone stops new SDK fetches trusting the old key, and the cache bounds the window to 24 hours. Then start signing with the new key; the SDK verifies by key id. Then republish every namespace under the new key, so no client depends on an old signature. Because versions only go up, a replayed old snapshot can't move clients backwards even within the 24 hours. A routine rotation is the same steps without the revocation, done every 90 days."

</details>

<details><summary><b>Q21 · "A customer invokes their right to erasure. Their data is in your immutable log, your backups and your warehouse."</b></summary>

**Initial Prompt.** On Tidewater: "Policyholder requests erasure. Walk me through every copy."

**L5 Answer.** "We delete their rows from the database and the warehouse. The archive is immutable, so it can't be changed."

**Why L5 Stalls.** "Can't be changed" isn't an answer to an erasure obligation (⚠ jurisdiction-dependent). The candidate hasn't inventoried backups, caches or logs, and the archive is left holding the data.

**L7 Answer.** "Six stores, each with its own path. The operational tables and the warehouse delete by policyholder key; the warehouse partitions are rewritten by a batch job. The raw GCS archive is immutable, so since month 9 every policyholder's records are encrypted under their own envelope key, and erasure is deleting that key, which makes every archived copy unreadable. That's the design change I'd have made on day 1, as I said in hindsight. Pre-month-9 history goes through a quarterly compaction that rewrites the affected files. Backups aren't edited: they expire within 35 days, and a suppression list is applied on any restore. Caches expire by TTL within 24 hours. Logs don't contain policyholder data, by a lint on log statements. Each request is tracked to completion, and the backup expiry is the longest path."

</details>

<details><summary><b>Q22 · "An auditor asks who changed this config value on March 3rd and why. Show me."</b></summary>

**Initial Prompt.** On Beacon: "Auditor's question: a payments flag changed on March 3rd. Who, why, approved by whom, and was what got deployed what got approved?"

**L5 Answer.** "We'd look at the API logs and the deployment history to see who made the change."

**Why L5 Stalls.** API logs rotate and aren't evidence of what was deployed. The second half of the question, whether the deployed artifact matched the approved one, isn't addressed at all.

**L7 Answer.** "One query, because the change log is the source of truth rather than a log of it. Every change is an append-only row: author, time, diff, ticket and approver. For PCI namespaces, the change policy refuses a change without a ticket and a second approver. The snapshot that reached clients is content-addressed and signed, and its header records the change-log sequence it was built from. So I can show the March 3rd row, its ticket and approver, the snapshot digest built from that row, and the SDK reports of which instances applied that digest and when. Reads of the change log are themselves logged. For this auditor's scope, the log's storage is write-once, so entries can't be altered after the fact."

</details>

<details><summary><b>Q23 · "It's 3 a.m. and you're paged. What paged you, and what does the runbook say?"</b></summary>

**Initial Prompt.** "Tell me about the last time you were paged on this system. What was the alert?"

**L5 Answer.** "Usually it was a CPU or memory alert on one of the services, and we'd look at the dashboards to figure out what was going on."

**Why L5 Stalls.** CPU pages are cause-level noise that rarely need a human at 3 a.m., and "look at the dashboards" suggests there's no runbook. The answer also suggests the candidate wasn't on call, or didn't own the alerting.

**L7 Answer.** "The last real page was the INC-B7 signal: config_defaults_served above 0 in the canary cell. That's one of 2 page-worthy alerts I kept when I rewrote Beacon's alerting in month 4. The other is the error-budget burn rate for propagation latency, at a 1-hour and a 6-hour window, so a fast burn pages within minutes and a slow one within hours. The runbook's first 5 minutes are fixed: open the version-skew dashboard to bound the blast radius, then choose between 2 known-safe mitigations, halting the rollout controller or rolling back the last relay deploy. It also lists what not to do, like restarting SDKs fleet-wide during a control-plane outage. Pages went from about 11 a month to about 2, and every page is reviewed the next morning."

</details>

<details><summary><b>Q24 · "You need to change a schema used by 300 services. How do you roll it out?"</b></summary>

**Initial Prompt.** "A field in your shared event schema has the wrong type. 300 consumers. Go."

**L5 Answer.** "We'd coordinate with all the teams, agree on a date, and release the change together."

**Why L5 Stalls.** A 300-team flag day fails on the first team that isn't ready, and rollback means another flag day. The interviewer wants an evolution strategy, not a meeting.

**L7 Answer.** "Expand, migrate, contract, with telemetry deciding each step. Expand: add a new field with the right type alongside the old one. Producers write both. That's backward compatible, so the schema registry accepts it and no consumer breaks. Migrate: consumers move to the new field on their own schedule. Telemetry from the client libraries reports which consumers still read the old field, and a dashboard shows the 300 burning down. Contract: when the old field has had 0 readers for 30 days, producers stop writing it, then it's removed. In Beacon's ZooKeeper migration the same pattern took 5 months for 300 services, with a deletion date on each compat shim. The 8 stragglers each had a named owner and a date."

</details>

<details><summary><b>Q25 · "Finance wants per-tenant cost. How do you attribute a shared system's cost?"</b></summary>

**Initial Prompt.** On Quickset: "Five model teams share your cache fleet. Finance wants each team's cost."

**L5 Answer.** "We'd split the cost evenly between the teams, or based on how many requests each one makes."

**Why L5 Stalls.** An even split ignores the cost driver, and requests aren't what drives a memory-bound cache's cost. Finance will challenge the allocation, and the candidate has no basis to defend it.

**L7 Answer.** "Attribute by the resource that drives the cost, and state the key for whatever can't be metered. Quickset is memory-bound, so the main driver is bytes held. The cache already counts bytes per feature group to enforce the 12-gigabyte cap, so each team's share of host memory over the month is metered exactly. CPU follows lookups, which are counted per caller. That covers about 85% of the fleet's cost directly. The remaining 15%, idle headroom and the update pipeline, is allocated in proportion to the metered shares, and I state that rule in the report rather than burying it. We ran it as showback for 2 quarters before chargeback. The first report showed 1 team at 41% of memory for 9% of lookups, which led to a model change, not a bill dispute."

</details>

---

## 9. Checklist

- [ ] Per-tenant admission control and fair scheduling, with a measured or simulated isolation number (Q18, §6).
- [ ] Layers of data separation, and the cross-tenant test that would catch a hole (Q19).
- [ ] Rotation procedures for every key and credential, with overlap derived from cache lifetimes, and an emergency path (Q20).
- [ ] A personal-data store inventory, with each store's erasure path and deadline (Q21, ⚠).
- [ ] The audit query you'd run, and the evidence that deployed = approved (Q22).
- [ ] Your page-worthy alerts, the runbook's first 5 minutes, and your page rate (Q23).
- [ ] Schema evolution by expand/migrate/contract, with telemetry on old-form readers (Q24).
- [ ] Cost attribution by driver, with stated allocation keys (Q25).
- [ ] `tenant_sim.py` re-run with your tenants' shapes; your cache-key templates linted (§6).

---

## 10. References

- Amazon Builders' Library, "Workload isolation using shuffle-sharding". <https://aws.amazon.com/builders-library/workload-isolation-using-shuffle-sharding/>
- PostgreSQL documentation, Row Security Policies. <https://www.postgresql.org/docs/current/ddl-rowsecurity.html>
- NIST SP 800-57 Part 1 Rev. 5, *Recommendation for Key Management*. <https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final>
- Google Cloud KMS, key rotation. <https://cloud.google.com/kms/docs/key-rotation>
- Regulation (EU) 2016/679 (GDPR), including Article 17 (right to erasure). <https://eur-lex.europa.eu/eli/reg/2016/679/oj>
- Google SRE Workbook, "Alerting on SLOs" (multiwindow burn-rate alerts). <https://sre.google/workbook/alerting-on-slos/>
- Danilo Sato (on martinfowler.com), "Parallel Change". <https://martinfowler.com/bliki/ParallelChange.html>
- FinOps Foundation, FinOps Framework. <https://www.finops.org/framework/>
