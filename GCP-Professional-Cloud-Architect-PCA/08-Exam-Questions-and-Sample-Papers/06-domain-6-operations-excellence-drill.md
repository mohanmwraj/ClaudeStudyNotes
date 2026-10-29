# Domain 6 Drill · Ensuring Solution and Operations Excellence (20 questions)

Original exam-style questions for objectives 6.1–6.6 (~12.5% of the exam). The notes for this domain are in [07-Operations-Excellence](../07-Operations-Excellence/).

---

### Q1 · Task 6.1 · Single answer

A new customer-facing service is two weeks from launch. The team has written the code and passed functional tests, but hasn't yet defined how it will operate the service.

Following the operational excellence principles of the Google Cloud Well-Architected Framework, what should happen before launch?

- **A.** Launch on schedule, and add monitoring after the first incident shows what's needed.
- **B.** Run an operational readiness review: define SLOs; create dashboards and actionable alerts linked to runbooks; load-test to expected peak; verify backups and DR; and staff an on-call rotation.
- **C.** Complete a security review only, because operations can be improved later.
- **D.** Rely on Google Cloud's service SLAs, because they cover the application.

<details><summary>Answer</summary>

**Answer: B**

**Why (P13, P2):** Operational readiness means proving, before launch, that the service can be observed, supported, scaled and recovered.

- **A** — wrong: learning to operate during an incident is the costliest way to learn.
- **B** — correct: SLOs, observability, capacity, recovery and people.
- **C** — wrong: security is necessary but not sufficient.
- **D** — wrong: Google's SLAs cover Google's services, not your application's design or operations.

**Reference:** <https://cloud.google.com/architecture/framework/operational-excellence>

</details>

### Q2 · Task 6.1 · Single answer

An operations team spends about 60% of its time manually restarting hung VMs, resizing instance groups before predictable peaks, and rotating certificates.

What should you recommend?

- **A.** Hire more operations engineers to keep up with the manual work.
- **B.** Write detailed checklists for each manual task.
- **C.** Accept the workload, because it's normal for operations teams.
- **D.** Treat the work as toil and automate it: MIG autohealing with health checks, scheduled or predictive autoscaling, and Google-managed certificates. Then track toil as a metric with a target to reduce it.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12, P5):** Repetitive, automatable work that grows with load is toil. SRE practice caps it and automates it away, frequently with managed features that already exist.

- **A** — wrong: scales cost linearly and fixes nothing.
- **B** — wrong: still manual.
- **C** — wrong: toil crowds out engineering work and causes errors.
- **D** — correct: native automation plus measurement.

**Reference:** <https://sre.google/sre-book/eliminating-toil/>

</details>

### Q3 · Task 6.1 · Single answer

The same class of incident, expired credentials in a batch pipeline, has occurred four times in six months. Each postmortem listed sensible action items, but none were completed.

What should you recommend?

- **A.** Track postmortem action items as prioritized work with owners and due dates, review their status in a regular operations meeting, and use the error-budget policy to prioritize reliability work over features when needed.
- **B.** Make postmortems longer and more detailed.
- **C.** Stop writing postmortems, because they don't change anything.
- **D.** Identify which engineer is responsible and reprimand them.

<details><summary>Answer</summary>

**Answer: A**

**Why (P13, P12):** Continuous improvement depends on follow-through. Action items must become owned, prioritized work, and error budgets give reliability work a legitimate claim on capacity.

- **A** — correct: closes the learning loop.
- **B** — wrong: documentation without execution changes nothing.
- **C** — wrong: discards learning.
- **D** — wrong: blame doesn't fix systems or process.

**Reference:** <https://sre.google/sre-book/postmortem-culture/>

</details>

### Q4 · Task 6.2 · Single answer

On-call engineers are paged several times a night by "CPU above 80%" alerts that rarely correspond to user impact. Meanwhile, a real outage last month was reported first by customers.

How should you redesign the alerting?

- **A.** Raise the CPU alert threshold to 95%.
- **B.** Add more CPU and memory alerts on every instance.
- **C.** Define SLOs for the user-facing services and page on multi-window SLO burn-rate alerts; move CPU metrics to dashboards and non-paging notifications.
- **D.** Send all alerts by email only, so nobody is woken at night.

<details><summary>Answer</summary>

**Answer: C**

**Why (P13):** Page on symptoms users feel (SLO burn), not on causes that may not matter. Multi-window burn rates catch fast outages and slow degradations while staying quiet otherwise.

- **A** — wrong: still cause-based. It may still miss real outages and still page needlessly.
- **B** — wrong: more noise.
- **C** — correct: symptom-based, actionable paging.
- **D** — wrong: email alerts get ignored, which is a known anti-pattern.

**Reference:** <https://cloud.google.com/stackdriver/docs/solutions/slo-monitoring/alerting-on-budget-burn-rate>

</details>

### Q5 · Task 6.2 · Single answer

A company has 300 projects, and new projects are created weekly. The security team needs every project's logs in one place, retained for one year and queryable with SQL, with the least ongoing effort.

What should you configure?

- **A.** A log sink in each project, created manually when the project is created.
- **B.** An aggregated log sink at the organization (including child resources) that routes logs to a central log bucket with one-year retention and Log Analytics enabled.
- **C.** A nightly job that downloads logs from each project to a VM.
- **D.** A self-managed Elasticsearch cluster, with an agent installed on every resource.

<details><summary>Answer</summary>

**Answer: B**

**Why (P13, P7, P5):** An aggregated sink inherits to all current and future projects. Log Analytics adds SQL over log buckets without exporting.

- **A** — wrong: misses projects, and adds toil.
- **B** — correct: complete, automatic and queryable.
- **C** — wrong: delayed, fragile and self-managed.
- **D** — wrong: heavy infrastructure that duplicates native features.

**Reference:** <https://cloud.google.com/logging/docs/export/aggregated_sinks>

</details>

### Q6 · Task 6.2 · Single answer

A media company runs Prometheus servers on each GKE cluster and has hundreds of Grafana dashboards and PromQL alert rules. Retention, scaling and high availability of the Prometheus servers have become a burden.

What should you recommend?

- **A.** Google Cloud Managed Service for Prometheus, keeping PromQL, the existing rules and the Grafana dashboards, with globally queryable managed storage.
- **B.** Rewrite every dashboard and alert in a different query language.
- **C.** Run a larger, self-managed Prometheus deployment with additional open-source components for HA and long-term storage.
- **D.** Stop collecting application metrics.

<details><summary>Answer</summary>

**Answer: A**

**Why (P5, P13):** The managed service removes the operational burden while preserving the existing Prometheus ecosystem investments.

- **A** — correct: least change, with managed scale and retention.
- **B** — wrong: needless rework.
- **C** — wrong: more self-managed complexity.
- **D** — wrong: loses observability.

**Reference:** <https://cloud.google.com/stackdriver/docs/managed-prometheus>

</details>

### Q7 · Task 6.2 · Single answer

A Java service's compute costs have grown 40% since the last release, with no traffic increase. Engineers want to find which methods consume the most CPU and memory in production, with minimal overhead.

Which tool should they use?

- **A.** Cloud Trace.
- **B.** Error Reporting.
- **C.** VPC Flow Logs.
- **D.** Cloud Profiler.

<details><summary>Answer</summary>

**Answer: D**

**Why (P13, P9):** Continuous production profiling attributes CPU and heap usage to code paths, which is exactly what's needed to find a resource regression.

- **A** — wrong: shows latency across requests and services, not per-method CPU and heap use.
- **B** — wrong: groups exceptions.
- **C** — wrong: network flow metadata.
- **D** — correct: low-overhead CPU and heap profiling in production.

**Reference:** <https://cloud.google.com/profiler/docs/about-profiler>

</details>

### Q8 · Task 6.2 · Select TWO

After a new release, p99 latency of a checkout flow that spans five microservices has doubled. CPU and memory metrics look normal, and the SLO is burning slowly.

Which two actions are most appropriate? (Select TWO.)

- **A.** Use Cloud Trace to find which service or downstream call contributes the added latency.
- **B.** Move all five services to larger machine types.
- **C.** Disable request logging to reduce overhead.
- **D.** Compare latency between the new and previous revisions, and roll back if the error budget is at risk.
- **E.** Add CPU alerts on all five services.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P13, P12):** Distributed tracing localizes latency in multi-service flows. Correlating the regression with the release, and rolling back when the budget is threatened, limits user impact.

- **A** — correct: pinpoints the slow span.
- **B** — wrong: resources aren't the bottleneck, according to the metrics.
- **C** — wrong: removes diagnostic data, and unlikely to be the cause.
- **D** — correct: release correlation plus a safe mitigation.
- **E** — wrong: CPU isn't the symptom.

**Reference:** <https://cloud.google.com/trace/docs/overview>

</details>

### Q9 · Task 6.2 · Single answer

A central SRE team must view metrics and build dashboards and alerts spanning 120 projects without switching between projects.

What should you configure?

- **A.** Switch between projects in the console as needed.
- **B.** A weekly export of each project's metrics to spreadsheets.
- **C.** A metrics scope in a dedicated monitoring (scoping) project that includes all 120 projects.
- **D.** Merge all workloads into a single project.

<details><summary>Answer</summary>

**Answer: C**

**Why (P13, P7):** A metrics scope lets one project view and alert on metrics from many monitored projects, keeping project isolation intact.

- **A** — wrong: manual and fragmented.
- **B** — wrong: stale and manual.
- **C** — correct: centralized visibility, designed for this need.
- **D** — wrong: destroys isolation, quota and billing boundaries.

**Reference:** <https://cloud.google.com/monitoring/settings>

</details>

### Q10 · Task 6.3 · Single answer

A team wants to release a new version of a stateless web application with zero downtime. Before any users see it, they want to validate it in a complete, identical environment, then switch all traffic at once, with the ability to switch back instantly. Briefly running double capacity is acceptable.

Which deployment strategy fits?

- **A.** Blue/green deployment.
- **B.** Recreate: stop the old version, then start the new one.
- **C.** Rolling update with 50% of instances unavailable at a time.
- **D.** Shadow deployment that never serves user responses.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12):** Blue/green keeps two full environments. You validate green, then switch all traffic, and rolling back means switching back to blue.

- **A** — correct: full validation, atomic switch, instant rollback.
- **B** — wrong: causes downtime.
- **C** — wrong: mixed versions and reduced capacity, with no all-at-once switch.
- **D** — wrong: shadowing never actually releases the new version.

**Reference:** <https://cloud.google.com/architecture/application-deployment-and-testing-strategies>

</details>

### Q11 · Task 6.3 · Single answer

A team runs an API on Cloud Run. It wants each new revision to receive 5% of traffic first, be evaluated against error-rate and latency SLOs, then be promoted progressively, or rolled back automatically.

What should you recommend?

- **A.** Deploy the new revision as a separate service with its own URL, and email 5% of customers the new URL.
- **B.** Use Cloud Run traffic splitting between revisions, orchestrated by Cloud Deploy's canary strategy with automated verification against the SLO metrics.
- **C.** Use DNS weighted records with a 24-hour TTL to send 5% of traffic to the new revision.
- **D.** Deploy each revision to 100% of traffic, and roll back if customers complain.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12, P13):** Revision-level traffic splitting is native to Cloud Run, and Cloud Deploy adds managed canary phases, verification and rollback.

- **A** — wrong: not controlled traffic splitting.
- **B** — correct: native, measured, automated canary.
- **C** — wrong: DNS caching makes splits imprecise and rollback slow.
- **D** — wrong: no blast-radius control.

**Reference:** <https://cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration>

</details>

### Q12 · Task 6.3 · Single answer

A rolling deployment means old and new application versions run at the same time for about 20 minutes. The new version renames a database column.

How should the schema change be released without downtime?

- **A.** Rename the column in the same release as the code change.
- **B.** Schedule a downtime window for every schema change.
- **C.** Deploy the new code first, then rename the column afterwards.
- **D.** Use an expand/contract approach: add the new column (and keep both in sync) while the old code still works, deploy code that uses the new column, migrate the data, and remove the old column in a later release.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12, P3):** During rolling or canary releases both versions must work against the same schema. Expand/contract makes each step backward compatible.

- **A** — wrong: the old version breaks mid-rollout.
- **B** — wrong: unnecessary downtime.
- **C** — wrong: the new code fails until the column exists.
- **D** — correct: compatible at every step.

**Reference:** <https://cloud.google.com/architecture/application-deployment-and-testing-strategies>

</details>

### Q13 · Task 6.3 · Single answer

A regional managed instance group serves production traffic at full capacity. A new instance template must be rolled out without ever reducing serving capacity.

Which rolling-update settings should you use?

- **A.** `maxUnavailable` set to 100%, to finish quickly.
- **B.** Delete the MIG and create a new one from the new template.
- **C.** `maxSurge` greater than 0 (for example, 3) and `maxUnavailable` set to 0.
- **D.** SSH into each VM and update the application manually.

<details><summary>Answer</summary>

**Answer: C**

**Why (P12, P2):** Surging new instances before removing old ones keeps capacity at or above target throughout the update.

- **A** — wrong: takes all capacity down at once.
- **B** — wrong: causes an outage.
- **C** — correct: no capacity loss during the rollout.
- **D** — wrong: manual and non-reproducible, and it bypasses the template.

**Reference:** <https://cloud.google.com/compute/docs/instance-groups/updating-migs>

</details>

### Q14 · Task 6.4 · Single answer

A bank runs revenue-critical systems on Google Cloud. It wants the fastest response times for critical issues, a named Technical Account Manager, and proactive guidance.

Which support offering fits?

- **A.** Basic support, included free with every account.
- **B.** Premium Support.
- **C.** Community forums and Stack Overflow.
- **D.** Standard Support, opening cases at the lowest priority.

<details><summary>Answer</summary>

**Answer: B**

**Why (P13):** Support plans should match workload criticality. Premium is the tier with the fastest critical response and a Technical Account Manager.

- **A** — wrong: billing support only.
- **B** — correct: fastest response, TAM and proactive services.
- **C** — wrong: no guaranteed response.
- **D** — wrong: slower response, and low priority for critical issues is the wrong choice.

**Reference:** <https://cloud.google.com/support>

</details>

### Q15 · Task 6.4 · Single answer

An engineer needs to open a support case about an unexpected Cloud SQL failover that caused errors in production.

Which case content will get the fastest, most useful response?

- **A.** The project ID, instance name, exact time window in UTC, error messages and affected operations, business impact, troubleshooting steps already taken, and a priority that matches the impact.
- **B.** "Our database is broken, please fix ASAP," marked with the highest priority.
- **C.** Database usernames and passwords, so the support engineer can log in.
- **D.** Nothing yet: wait 24 hours to see whether the problem recurs before opening a case.

<details><summary>Answer</summary>

**Answer: A**

**Why (P13):** Precise identifiers, timestamps, symptoms and impact let support correlate with internal telemetry immediately. Accurate priority routes the case correctly.

- **A** — correct: actionable, complete information.
- **B** — wrong: vague, and misprioritized.
- **C** — wrong: never share credentials.
- **D** — wrong: delays help during production impact.

**Reference:** <https://cloud.google.com/support>

</details>

### Q16 · Task 6.5 · Single answer

Leadership asks how to tell whether the engineering organization's quality-control and release practices are actually improving over time.

What should you measure?

- **A.** Lines of code written per developer each month.
- **B.** The number of tickets closed per sprint.
- **C.** The number of review meetings held.
- **D.** The DORA metrics (deployment frequency, lead time for changes, change failure rate, time to restore service), together with SLO attainment and error-budget trends.

<details><summary>Answer</summary>

**Answer: D**

**Why (P13, P12):** DORA metrics capture delivery speed and stability together, and SLO trends show user-perceived reliability. Activity counts don't measure quality.

- **A** — wrong: rewards volume, not quality.
- **B** — wrong: an activity metric that's easy to game.
- **C** — wrong: process theater.
- **D** — correct: outcome-based speed, stability and reliability.

**Reference:** <https://dora.dev/>

</details>

### Q17 · Task 6.5 · Select THREE

A regulated payments service is defining quality gates for its delivery pipeline. Which three gates should it include? (Select THREE.)

- **A.** Skip code review for changes under 50 lines, to save time.
- **B.** Require automated unit and integration tests to pass before a change can merge.
- **C.** Scan images for vulnerabilities and block deployment of images with critical findings, enforced with Binary Authorization attestations.
- **D.** Deploy every commit straight to production with no verification.
- **E.** Roll out to production as a canary with automated verification against SLO metrics before full rollout.
- **F.** Rely solely on a manual spot check of production once a week.

<details><summary>Answer</summary>

**Answer: B, C, E**

**Why (P12, P6):** Effective quality control is automated and layered: correctness before merge, security before deploy, and real-traffic verification during release.

- **A** — wrong: small changes can still break production, and review is a key control.
- **B** — correct: an automated correctness gate.
- **C** — correct: an enforced security gate.
- **D** — wrong: no gate at all.
- **E** — correct: production verification with a limited blast radius.
- **F** — wrong: too late and too sparse.

**Reference:** <https://cloud.google.com/binary-authorization/docs/overview>

</details>

### Q18 · Task 6.6 · Single answer

A company wants to start practicing chaos engineering on its GKE-based platform. The team has never done it.

What's the best first step?

- **A.** Randomly delete production databases without warning, to see what happens.
- **B.** Run random failure scripts in the development environment indefinitely, without defining what "healthy" means.
- **C.** Define steady-state SLIs, form a hypothesis (for example, "losing one zone's nodes won't breach the SLO"), run a small-blast-radius experiment in pre-production, then graduate to controlled, monitored production experiments.
- **D.** Skip chaos engineering and rely on Google's SLAs.

<details><summary>Answer</summary>

**Answer: C**

**Why (P2, P13):** Chaos engineering is a disciplined experiment: steady state, hypothesis, minimal blast radius, observation and improvement, expanding scope as confidence grows.

- **A** — wrong: reckless and destructive.
- **B** — wrong: without hypotheses or measurements it teaches little.
- **C** — correct: the structured approach.
- **D** — wrong: Google's SLAs don't validate your architecture's failure handling.

**Reference:** <https://cloud.google.com/architecture/framework/reliability>

</details>

### Q19 · Task 6.6 · Single answer

A company wants to commission a penetration test of its web application hosted on Google Cloud.

What does it need to do regarding Google?

- **A.** Nothing beyond following Google Cloud's Acceptable Use Policy and Terms of Service, and testing only its own projects and resources. No prior notification to Google is required.
- **B.** Submit a written request to Google at least 30 days in advance and wait for approval.
- **C.** Nothing, because penetration testing is prohibited on Google Cloud.
- **D.** Include Google's underlying infrastructure in the test scope.

<details><summary>Answer</summary>

**Answer: A**

**Why (P6):** Customers may pen-test their own Google Cloud resources without notifying Google, provided they stay within the AUP and Terms of Service.

- **A** — correct: matches Google's published guidance.
- **B** — wrong: no prior approval is required.
- **C** — wrong: testing your own resources is permitted.
- **D** — wrong: Google's infrastructure is out of scope.

**Reference:** <https://support.google.com/cloud/answer/6262505>

</details>

### Q20 · Task 6.6 · Single answer

Leadership wants evidence that a regional GKE application really tolerates the loss of a zone, and that enough capacity remains in the other zones.

What should you do?

- **A.** Assume it does, because the cluster is regional.
- **B.** Run a game day: in a controlled window, drain or cordon one zone's nodes (or simulate the zone's loss), watch SLIs and autoscaling, verify capacity headroom in the remaining zones, and document the findings.
- **C.** Move to a zonal cluster, to simplify testing.
- **D.** Increase the replica counts without testing.

<details><summary>Answer</summary>

**Answer: B**

**Why (P2, P13):** Resilience claims must be verified under realistic failure. A game day shows whether replicas, spreading and capacity actually hold.

- **A** — wrong: regional control planes don't guarantee workload spread or capacity.
- **B** — correct: an empirical test with measurement.
- **C** — wrong: reduces resilience.
- **D** — wrong: may help, but proves nothing.

**Reference:** <https://cloud.google.com/architecture/infra-reliability-guide/building-blocks>

</details>
