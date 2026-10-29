# 09/01 · Numbers and Limits Worth Memorizing

The PCA exam rarely asks for a raw number, but numbers decide many options: "is VPN enough?", "does this meet 99.99%?", "can this storage class be read weekly?". Everything here was checked against Google's documentation on 2026-10-29. Confirm decimals on the live SLA pages; the *ratios* are what matter.

---

## Exam

| Item | Value |
|---|---|
| Duration / questions | 2 hours / 50–60 |
| Case studies per exam | 2 of 4 (Altostrat Media, Cymbal Retail, EHR Healthcare, KnightMotives Automotive) |
| Case-study share | 20–30% |
| Section weights | 25 / 17.5 / 17.5 / 15 / 12.5 / 12.5 |
| Fee / validity | USD 200 / 2 years |
| Renewal exam | 1 hour, 25 questions, USD 100; 1 generative-AI case study (Cymbal or Altostrat), 90–100% of the questions |

## Availability arithmetic

| SLA | Downtime per 30-day month |
|---|---|
| 99% | ~7.2 h |
| 99.5% | ~3.6 h |
| 99.9% | ~43 min |
| 99.95% | ~22 min |
| 99.99% | ~4.3 min |
| 99.999% | ~26 s |

* **Components in series:** multiply their availabilities.
* **Components in parallel:** 1 − Π(1 − Aᵢ).

## Selected SLAs

| Service | SLA |
|---|---|
| Compute Engine, instances in multiple zones / single instance | 99.99% / 99.9% (memory-optimized single: 99.95%) |
| GKE regional / zonal control plane | 99.95% / 99.5% |
| Cloud Run | 99.95% |
| Cloud SQL Enterprise HA / Enterprise Plus HA (includes maintenance) | 99.95% / 99.99% |
| AlloyDB | 99.99% |
| Spanner regional / multi-region | 99.99% / 99.999% |
| Firestore regional / multi-region | 99.99% / 99.999% |
| Bigtable single cluster / replicated multi-cluster routing | 99.9% / up to 99.999% |
| Cloud Storage Standard regional / dual- and multi-region | 99.9% / 99.95% |
| BigQuery | 99.99% |
| HA VPN | 99.99% |
| Interconnect, 2 connections in 1 metro / critical topologies | 99.9% / 99.99% |

## Hybrid connectivity

| Item | Value |
|---|---|
| HA VPN per tunnel | ~3 Gbps (packet-rate bound); add tunnels to scale |
| Dedicated Interconnect circuits | 10, 100, **400 Gbps** (400 GA 2026-03-03) |
| Dedicated / Cross-Cloud VLAN attachment capacity | 50 Mbps – 400 Gbps |
| Partner Interconnect attachments | 50 Mbps – 50 Gbps |
| 99.9% Interconnect topology | 2 connections, same metro, different edge availability domains |
| 99.99% multi-region topology | 4 connections, 2 metros, 2 regions, ≥ 2 Cloud Routers, global dynamic routing |
| 99.99% single-region topology (GA 2026-06-02) | 4 connections in 1 supported metro (2 per facility/EAD pair), `PRODUCTION_CRITICAL` connection group |
| IAP TCP forwarding source range | 35.235.240.0/20 |
| Load-balancer health-check ranges | 35.191.0.0/16, 130.211.0.0/22 |
| Private Google Access VIPs | `private.googleapis.com` 199.36.153.8/30; `restricted.googleapis.com` 199.36.153.4/30 |

## Data transfer time (full, sustained utilization)

| Data | 100 Mbps | 1 Gbps | 10 Gbps |
|---|---|---|---|
| 1 TB | ~1 day | ~2.5 h | ~15 min |
| 10 TB | ~10 days | ~1 day | ~2.5 h |
| 100 TB | ~100 days | ~10 days | ~1 day |
| 1 PB | years | ~100 days | ~10 days |

Rule of thumb: if the network would take more than about a week, use **Transfer Appliance**.

## Cloud Storage

| Class | Minimum storage duration |
|---|---|
| Standard | none |
| Nearline | 30 days |
| Coldline | 90 days |
| Archive | 365 days |

* **Soft delete:** default retention of deleted objects is 7 days.
* **Turbo replication** (dual-region): 15-minute RPO target.
* **Locked retention policies** can't be shortened or removed.

## Logging

| Bucket | Retention |
|---|---|
| `_Required` (Admin Activity, System Event, Access Transparency) | 400 days, can't be changed |
| `_Default` | 30 days by default, configurable 1–3,650 days |
| Data Access audit logs | Off by default (except BigQuery). Enable per service |

## Databases and compute

| Item | Value |
|---|---|
| Cloud SQL maximum storage | 64 TB (storage can't shrink; use auto-increase with a limit) |
| BigQuery time travel | up to 7 days (+ 7-day fail-safe) |
| BigQuery long-term storage pricing | table or partition unmodified for 90 days |
| Spanner / Firestore point-in-time recovery | up to 7 days |
| Spot VM preemption notice | ~30 seconds; no maximum runtime |
| Cloud Run concurrency | default 80, maximum 1000 per instance |
| Cloud Run request timeout | up to 60 minutes |

## Retirement and change dates

| Item | Date |
|---|---|
| Cloud IoT Core retired | 2023-08-16 |
| Cloud Functions renamed Cloud Run functions | August 2024 |
| GKE Enterprise tier removed (features in GKE) | September 2025 |
| Memorystore for Memcached deprecated / shutdown | 2026-01-20 / 2029-01-31 |
| Cloud Deployment Manager end of support | 2026-03-31 |
| Dataproc renamed Managed Service for Apache Spark | 2026-04-03 |
| Dataplex renamed Knowledge Catalog | 2026-04-10 |
| Cloud Composer renamed Managed Service for Apache Airflow | 2026-04-15 |
| BigLake renamed Google Cloud Lakehouse | 2026-04-20 |
| Vertex AI renamed Gemini Enterprise Agent Platform | 2026-04-22 |
