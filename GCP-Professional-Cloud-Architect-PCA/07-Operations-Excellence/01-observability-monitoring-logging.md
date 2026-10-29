# 07/01 · Google Cloud Observability: Monitoring, Logging, Profiling and Alerting

**Exam guide:** 6.2 (familiarity with Google Cloud Observability solutions: monitoring and logging, profiling and benchmarking, alerting strategies). Also 1.1 (observability) and the case-study requirements about monitoring. **Principle:** P13.

---

## 1. The suite at a glance

| Signal | Product | Key capabilities |
|---|---|---|
| **Metrics** | **Cloud Monitoring** | 6,500+ built-in service metrics, custom metrics, **Ops Agent** for VM OS/app metrics, dashboards, **uptime checks** and synthetic monitors, **SLO monitoring**, alerting (metric, log-based, PromQL), **metrics scopes** across projects |
| Prometheus metrics | **Google Cloud Managed Service for Prometheus** | Managed, global Prometheus-compatible collection and storage; PromQL; works with existing Grafana dashboards and Prometheus alerting rules. Fits Altostrat's and EHR's existing tooling |
| **Logs** | **Cloud Logging** | Log Router, **sinks**, **log buckets** with retention, exclusions, **Log Analytics** (SQL), log-based metrics, CMEK |
| **Traces** | **Cloud Trace** | Distributed latency analysis; OpenTelemetry-native |
| **Profiles** | **Cloud Profiler** | Continuous, low-overhead CPU and heap profiling in production |
| **Errors** | **Error Reporting** | Groups exceptions, tracks first and last seen, notifies on new errors |
| Google incidents | **Personalized Service Health** | Incidents affecting *your* projects; alertable |
| Application view | **App Hub** + Application Monitoring | Group resources into applications; app-centric dashboards |
| AI assistance | **Gemini Cloud Assist** | Investigations, query generation, explanations |

**Instrumentation standard:** **OpenTelemetry** (traces, metrics and logs) exports to Google Cloud Observability without vendor lock-in.

---

## 2. Cloud Logging architecture

```text
 Log sources (services, Ops Agent, GKE, Cloud Run, audit logs)
         │
         ▼
   Log Router  ── evaluates every sink's inclusion/exclusion filter ──┐
         │                                                           │
   ├─▶ _Required bucket (Admin Activity, System Event, Access Transparency audit logs; 400 days; can't change)
   ├─▶ _Default bucket (everything else; default 30 days; configurable 1–3650 days; exclusions allowed)
   └─▶ user sinks ──▶ user-defined log buckets (any project; Log Analytics; locked retention)
                  ──▶ BigQuery datasets (analytics, long-term SQL)
                  ──▶ Cloud Storage (cheap archival, WORM with Bucket Lock)
                  ──▶ Pub/Sub (stream to SIEM / third parties / Splunk)
```

| Need | Configuration |
|---|---|
| Centralize logs from every project, including future ones | **Aggregated sink** at the org or folder (`--include-children`) → central log bucket |
| SQL over logs without exporting | **Log Analytics** on a log bucket (optionally linked BigQuery dataset) |
| Keep audit logs for years, immutably | Sink → log bucket with long retention + **locked** bucket, or → Cloud Storage with Bucket Lock |
| Stream to an external SIEM | Sink → Pub/Sub → SIEM (or native Google SecOps ingestion) |
| Reduce cost | **Exclusion filters** for noisy, low-value logs (debug, health checks); sample VPC Flow Logs. Never exclude required audit logs |
| Metrics from log content | **Log-based metrics** (counter or distribution), which can drive alerts |
| Restrict who sees which logs | Log views on buckets + IAM; `privateLogViewer` for Data Access logs |

---

## 3. Cloud Monitoring essentials

| Feature | Use |
|---|---|
| **Metrics scope** | One "scoping project" views metrics from many projects. Central visibility for an operations team (EHR "centralized visibility") |
| **Dashboards** | Predefined per service plus custom (JSON, Terraform); dashboards-as-code |
| **Uptime checks** | HTTP/HTTPS/TCP probes from multiple global locations; alert on failure |
| **Synthetic monitors** | Scripted user-journey tests (Cloud Run functions-based) |
| **Ops Agent** | Single agent for VM metrics and logs (replaces the legacy agents) |
| **Custom metrics** | Application KPIs via OpenTelemetry / API |
| **Alerting policies** | Conditions: metric threshold, metric absence, forecast, **PromQL**, log-match (log-based alerts); documentation field for runbooks; severity |
| **Notification channels** | Email, SMS, mobile app, **PagerDuty**, **Slack**, **webhooks**, **Pub/Sub** (for automation), Google Chat |
| **SLOs** | Define request-based or windows-based SLIs on services (Cloud Run, GKE, App Engine, Istio/Cloud Service Mesh, custom); **error budget** tracking; **burn-rate alerts** |

---

## 4. Alerting strategy (exam guide 6.2)

| Principle | Practice |
|---|---|
| **Alert on symptoms, not causes** | Page on user-visible SLO burn (errors, latency), not on CPU 80%. Cause metrics go on dashboards and tickets |
| **Multi-window, multi-burn-rate** | Fast burn (for example, 2% of a 30-day budget in 1 hour) pages immediately; slow burn (for example, 10% in 3 days) opens a ticket. Catches big outages fast and slow leaks without noise |
| **Every page is actionable** | Each alert has an owner, a severity and a **runbook link** (alert documentation field) |
| **Route by severity** | Critical → on-call paging (PagerDuty); warning → chat or ticket; informational → dashboard only |
| **Fight alert fatigue** | Delete or tune noisy alerts; group related alerts; use notification rate limits and auto-close |
| **Automate known fixes** | Pub/Sub notification → Cloud Run function remediation for well-understood conditions (with safeguards) |
| **Monitor the monitors** | Absence alerts for missing metrics, and uptime checks independent of the app's own infrastructure |

**Case mapping:**

* EHR ("alerts sent via email and often ignored") and Altostrat ("alerts primarily via email") → SLO burn-rate alerts routed to on-call tooling with runbooks, plus centralized dashboards and Managed Prometheus.
* Cymbal (Grafana, Nagios, Elastic) → Managed Prometheus (Grafana keeps working), uptime checks (replace Nagios), Cloud Logging and Log Analytics (replace Elastic queries).

---

## 5. Profiling and benchmarking

| Activity | Tool | When |
|---|---|---|
| Find hot code paths in production (CPU, heap, contention) | **Cloud Profiler** | Latency or cost regressions; rightsizing compute |
| Find slow spans across services | **Cloud Trace** | Microservice latency, tail latency |
| Database query analysis | Cloud SQL **Query Insights**, AlloyDB / Spanner query statistics, BigQuery execution graph | Slow queries |
| Benchmark infrastructure choices | **PerfKit Benchmarker** (open source), custom load tests | Choosing machine families, disk types, regions |
| Load and capacity testing | Distributed load testing (Locust/JMeter on GKE) | Before launches and peaks; validating autoscaling |
| Network performance | Network Intelligence Center Performance Dashboard | Latency and packet loss between regions and zones |

**Benchmarking rules:** test with production-like data and configuration, warm up first, measure percentiles (p95/p99) and not just averages, and change one variable at a time.

---

## 6. Observability for each platform

| Platform | Built-in | Add |
|---|---|---|
| Compute Engine | Hypervisor metrics | **Ops Agent** for memory, disk, process and app logs |
| GKE | System metrics and logs, control-plane metrics, Managed Prometheus (enabled by default on new clusters) | App metrics via PodMonitoring; Cloud Service Mesh telemetry |
| Cloud Run / Cloud Run functions | Request metrics, logs, traces | Custom metrics via OpenTelemetry |
| Databases | Service metrics, Query Insights | Alerts on CPU, storage, replication lag, connections |
| Load balancers | Request count, latency, backend errors | Logging (sampled) for analysis |

---

## 7. Worked scenarios

**A. "Operations needs one place to see metrics for 120 projects and get paged only when customers are affected."**
A metrics scope in a central monitoring project (adding the 120 projects); SLOs on customer-facing services; multi-window burn-rate alerts to PagerDuty; dashboards as code.

**B. "Security wants all Data Access logs from every project for 3 years, queryable with SQL, at low cost."**
Enable Data Access logs for the relevant services. Use an aggregated org sink to a central log bucket with 3-year retention and Log Analytics, or to BigQuery (partitioned) if heavy analytics is needed. Lock retention if it must be immutable.

**C. "The team already has hundreds of Prometheus rules and Grafana dashboards."**
**Managed Service for Prometheus**: keep PromQL, rules and Grafana; managed storage and global querying; alert through Cloud Monitoring or the managed rule evaluator.

**D. "After a deployment, p99 latency doubled but CPU is normal."**
Trace to find the slow span (a downstream call or lock contention), and Profiler to compare revisions. Roll back first if the SLO is burning.

---

## References

* Google Cloud Observability overview: <https://cloud.google.com/stackdriver/docs>
* Routing and storage overview (Log Router, sinks, buckets): <https://cloud.google.com/logging/docs/routing/overview>
* Log Analytics: <https://cloud.google.com/logging/docs/log-analytics>
* Managed Service for Prometheus: <https://cloud.google.com/stackdriver/docs/managed-prometheus>
* SLO monitoring: <https://cloud.google.com/stackdriver/docs/solutions/slo-monitoring>
* Alerting on burn rate: <https://cloud.google.com/stackdriver/docs/solutions/slo-monitoring/alerting-on-budget-burn-rate>
* Cloud Profiler: <https://cloud.google.com/profiler/docs/about-profiler>
* Metrics scopes: <https://cloud.google.com/monitoring/settings>
