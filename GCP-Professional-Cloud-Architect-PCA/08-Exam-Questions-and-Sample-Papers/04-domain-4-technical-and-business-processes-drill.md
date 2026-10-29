# Domain 4 Drill · Analyzing and Optimizing Technical and Business Processes (20 questions)

Original exam-style questions for objectives 4.1–4.2 (~15% of the exam). The notes for this domain are in [05-Technical-and-Business-Processes](../05-Technical-and-Business-Processes/). Business-process questions reward answers that are **collaborative, incremental, data-driven and people-aware**.

---

### Q1 · Task 4.1 · Single answer

A product team releases once a month, and about a third of releases are rolled back. Leadership wants releases that are both more frequent and safer.

What should you recommend?

- **A.** CI that runs automated tests on every change, a single artifact built once, and Cloud Deploy releases that use canary deployment with automated verification and rollback, delivered in smaller batches.
- **B.** More manual approval steps, with releases moved to a quarterly schedule.
- **C.** A freeze on all changes until the defect rate improves.
- **D.** Let developers deploy directly from their laptops, to remove pipeline delays.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12, P13):** Small batches, automated testing and progressive delivery with automated verification improve speed **and** stability together, as DORA research shows.

- **A** — correct: faster feedback, smaller blast radius and automatic rollback.
- **B** — wrong: bigger, rarer releases carry more risk per release.
- **C** — wrong: freezing indefinitely halts the business and fixes nothing.
- **D** — wrong: no traceability, testing or separation of duties.

**Reference:** <https://cloud.google.com/deploy/docs/overview>

</details>

### Q2 · Task 4.1 · Single answer

A pipeline builds a container image for staging, runs tests, and then rebuilds the image from the same commit for production. Several defects have appeared in production that never appeared in staging.

What should you change?

- **A.** Rebuild for production more carefully, with the exact same Dockerfile and flags.
- **B.** Add more tests that run only in production.
- **C.** Build the image once, promote the same image digest from staging to production, and supply environment-specific configuration at deploy time.
- **D.** Deploy the `latest` tag in every environment, so they always match.

<details><summary>Answer</summary>

**Answer: C**

**Why (P12):** Rebuilding can pull different dependency versions or base layers. Promoting the exact tested artifact, by digest, guarantees production runs what staging tested.

- **A** — wrong: rebuilds are inherently non-reproducible when dependencies float.
- **B** — wrong: testing in production after deployment doesn't prevent the drift.
- **C** — correct: build once, promote immutably, configure per environment.
- **D** — wrong: `latest` is mutable, so environments can silently diverge.

**Reference:** <https://cloud.google.com/artifact-registry/docs/overview>

</details>

### Q3 · Task 4.1 · Single answer

Integration tests for a microservice use a shared Pub/Sub topic and a shared Spanner database in a staging project. Tests from different developers interfere with each other, runs are slow, and the staging costs keep growing.

What should you recommend?

- **A.** Point the integration tests at the production Pub/Sub topic and Spanner database instead.
- **B.** Run integration tests in CI against the Pub/Sub and Spanner emulators, and run a smaller set of end-to-end tests in ephemeral test projects created and destroyed by the pipeline.
- **C.** Stop running integration tests, and rely on unit tests.
- **D.** Replace all integration tests with mocks inside the unit-test suite.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12):** Emulators give each test run isolated, fast, free dependencies. Ephemeral projects keep the end-to-end tests realistic without shared state.

- **A** — wrong: testing against production risks real data and customers.
- **B** — correct: isolation and speed, with realism where it matters.
- **C** — wrong: removes coverage of service interactions.
- **D** — wrong: mocks miss real behavior and integration defects.

**Reference:** <https://cloud.google.com/pubsub/docs/emulator>

</details>

### Q4 · Task 4.1 · Single answer

Twice this quarter, a Terraform change opened a firewall rule to `0.0.0.0/0` on a database port. Changes are reviewed by peers but merged quickly. Security wants such changes blocked automatically.

What should you implement?

- **A.** A weekly manual review of all firewall rules by the security team.
- **B.** Stop using Terraform and make firewall changes only in the console.
- **C.** Apply changes first, then have a nightly script remove any open rules.
- **D.** A policy-as-code check on the Terraform plan in CI (for example, `gcloud beta terraform vet` with a constraint that rejects internet-open ingress), plus a hierarchical firewall policy that denies that traffic as a runtime guardrail.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12, P7):** Preventive checks before apply stop bad changes from merging, and an organization-level guardrail blocks them even if someone bypasses the pipeline. That's defense in depth.

- **A** — wrong: slow, manual and detective only.
- **B** — wrong: removes review and reproducibility.
- **C** — wrong: the exposure exists until the script runs.
- **D** — correct: shift-left prevention plus a runtime guardrail.

**Reference:** <https://cloud.google.com/docs/terraform/policy-validation>

</details>

### Q5 · Task 4.1 · Single answer

Five minutes after a new release of the checkout service, the error rate rises from 0.2% to 6%, and the SLO burn-rate alert pages the on-call engineer.

What should the engineer do first?

- **A.** Roll back to the previous release, by shifting traffic to the prior revision or using the deployment tool's rollback, then investigate.
- **B.** Start reading production logs to find the bug while users continue to see errors.
- **C.** Double the number of instances to absorb the errors.
- **D.** Open a support case with Google and wait for a response.

<details><summary>Answer</summary>

**Answer: A**

**Why (P13, P12):** In an incident, mitigate first. The release correlates with the spike, and rollback to a known-good artifact restores service fastest.

- **A** — correct: restore service, then diagnose calmly.
- **B** — wrong: prolongs customer impact.
- **C** — wrong: more instances of a broken release produce more errors.
- **D** — wrong: the cause is your release, not a Google issue, and waiting extends the outage.

**Reference:** <https://sre.google/sre-book/managing-incidents/>

</details>

### Q6 · Task 4.1 · Single answer

An operator mistyped a value in the console and deleted a production load balancer backend, causing a 40-minute outage. Some managers want the operator disciplined.

How should the organization respond?

- **A.** Discipline the operator, so others are more careful.
- **B.** Require that two people watch each other make console changes.
- **C.** Hold a blameless postmortem focused on systemic causes, with action items such as managing the load balancer through IaC with peer review, restricting console write access in production, and adding alerting on backend health.
- **D.** Skip the postmortem, because service has been restored.

<details><summary>Answer</summary>

**Answer: C**

**Why (P12, P13):** Blameless postmortems surface systemic weaknesses. Fixing the system, through IaC, least privilege and detection, prevents recurrence far better than blaming a person.

- **A** — wrong: blame discourages reporting, and the system stays fragile.
- **B** — wrong: still manual, and still error-prone.
- **C** — correct: systemic fixes plus a learning culture.
- **D** — wrong: loses the learning and invites recurrence.

**Reference:** <https://sre.google/sre-book/postmortem-culture/>

</details>

### Q7 · Task 4.1 · Select TWO

After an application VM was moved into a new VPC network, it can no longer connect to a Cloud SQL instance's private IP address, which uses private services access. Other connectivity works.

Which two steps best diagnose or resolve the problem? (Select TWO.)

- **A.** Increase the VM's machine type.
- **B.** Run a Connectivity Tests analysis from the VM to the Cloud SQL private IP.
- **C.** Delete and recreate the Cloud SQL instance.
- **D.** Check that the new VPC network has private services access configured for Cloud SQL (or uses a Private Service Connect endpoint), and that routes and firewall rules allow the traffic.
- **E.** Disable all firewall rules in the new network.

<details><summary>Answer</summary>

**Answer: B, D**

**Why (P14, P13):** Connectivity Tests pinpoints the blocking configuration. Private services access is configured per VPC network, so a new network needs its own connection (or a PSC endpoint) before it can reach the instance's private IP.

- **A** — wrong: machine size doesn't affect reachability.
- **B** — correct: diagnoses routes, firewalls and peering along the path.
- **C** — wrong: destructive, and the problem is in the network.
- **D** — correct: the likely root cause, a missing private connection or route.
- **E** — wrong: insecure and unrelated.

**Reference:** <https://cloud.google.com/network-intelligence-center/docs/connectivity-tests/concepts/overview>

</details>

### Q8 · Task 4.1 · Single answer

A company's DR plan states an RTO of 2 hours for its order system. The plan was written 18 months ago, and the architecture has changed twice since. It has never been tested.

What should you recommend?

- **A.** Assume the plan still works, because it was approved.
- **B.** Schedule a DR drill that fails over to the DR region, measure the achieved RTO and RPO, automate the manual steps you find, and set a recurring test cadence.
- **C.** Buy additional reserved capacity in the DR region.
- **D.** Rewrite the DR document with the new architecture diagrams.

<details><summary>Answer</summary>

**Answer: B**

**Why (P2, P12):** A DR plan is only real once it has been tested. Measuring the achieved RTO/RPO exposes gaps, and automation makes recovery repeatable.

- **A** — wrong: architecture drift almost certainly invalidated parts of it.
- **B** — correct: test, measure, automate, repeat.
- **C** — wrong: capacity without a validated procedure doesn't guarantee recovery.
- **D** — wrong: documentation alone remains untested.

**Reference:** <https://cloud.google.com/architecture/dr-scenarios-planning-guide>

</details>

### Q9 · Task 4.1 · Single answer

Application teams wait up to three weeks for the central platform team to create projects, networks and databases. Security insists that every environment be configured consistently and compliantly.

What should you recommend?

- **A.** Grant every team the Owner role on a shared folder so they can create what they need.
- **B.** Add another review board that approves each infrastructure request.
- **C.** Have the central team build each request manually, with a checklist.
- **D.** Offer self-service provisioning from a catalog of approved Terraform modules (for example, a project factory and standard database and service modules) run through CI or Infrastructure Manager, enforced by organization-policy guardrails.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12, P7):** A catalog of vetted IaC building blocks gives teams speed, and guardrails make it safe. Consistency is encoded in the modules rather than reviewed by hand.

- **A** — wrong: fast but uncontrolled and non-compliant.
- **B** — wrong: adds more delay.
- **C** — wrong: manual builds are slow and drift-prone.
- **D** — correct: self-service with governance built in.

**Reference:** <https://cloud.google.com/infrastructure-manager/docs/overview>

</details>

### Q10 · Task 4.1 · Select THREE

An online retailer's order system failed during last year's biggest sales event. The team has never load-tested. Which three activities should be part of preparing for this year's event? (Select THREE.)

- **A.** Run distributed load tests (for example, Locust on GKE) against an environment with production-like configuration and data volumes.
- **B.** Load-test against the small staging database, to save cost.
- **C.** Verify autoscaling limits, connection limits and quotas under load, and request quota increases ahead of the event.
- **D.** Disable monitoring during the load test, to reduce noise.
- **E.** Define pass criteria from the SLOs (for example, p95 latency and error rate at the expected peak) before testing.
- **F.** Skip testing and watch production closely on the day of the event.

<details><summary>Answer</summary>

**Answer: A, C, E**

**Why (P13, P2, P9):** Realistic load, explicit SLO-based success criteria and validation of scaling limits are what turn a load test into confidence.

- **A** — correct: realistic, scalable load generation.
- **B** — wrong: a tiny database gives false confidence.
- **C** — correct: limits and quotas are common failure points under peak load.
- **D** — wrong: monitoring is how you learn from the test.
- **E** — correct: objective pass/fail criteria tied to user experience.
- **F** — wrong: repeats last year's failure.

**Reference:** <https://cloud.google.com/architecture/distributed-load-testing-using-gke>

</details>

### Q11 · Task 4.2 · Single answer

During migration planning, the security team blocks progress, citing concerns about data exfiltration from managed data services. The program sponsor is frustrated with the delay.

What should the architect do?

- **A.** Engage the security team early to co-design controls (VPC Service Controls perimeters, organization policies, CMEK where required), and demonstrate them in a pilot before the main migration.
- **B.** Escalate to the CEO to override the security team.
- **C.** Proceed with the migration, and address security findings after go-live.
- **D.** Migrate the workloads without informing the security team.

<details><summary>Answer</summary>

**Answer: A**

**Why (P6):** Stakeholders who can veto should be partners. Co-designing and demonstrating controls turns their concern into confidence, and usually speeds things up.

- **A** — correct: collaborative, evidence-based stakeholder management.
- **B** — wrong: damages trust and may override legitimate risk.
- **C** — wrong: deferring security creates risk and rework.
- **D** — wrong: unethical, and likely non-compliant.

**Reference:** <https://cloud.google.com/architecture/framework>

</details>

### Q12 · Task 4.2 · Single answer

An operations team has only VM experience. Leadership wants the company's applications running in containers within six months.

What is the best approach?

- **A.** Have the team build and operate self-managed Kubernetes clusters on Compute Engine VMs starting next week.
- **B.** Hire contractors to run the platform, and exclude the existing team.
- **C.** Combine a training plan with a pilot on managed container platforms (GKE Autopilot or Cloud Run), with partner support, followed by phased migration as skills grow.
- **D.** Cancel the container initiative, because the team lacks skills.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5, P15):** Managed platforms reduce what the team must learn. Training and a pilot build skills safely, and phased waves manage the change.

- **A** — wrong: maximizes operational risk for an untrained team.
- **B** — wrong: no knowledge transfer, and it creates lasting dependency and morale problems.
- **C** — correct: skills, a lower-ops platform and incremental change.
- **D** — wrong: skills gaps can be closed.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview>

</details>

### Q13 · Task 4.2 · Single answer

A manufacturer is about to start a five-year modernization program that will introduce Kubernetes, data engineering and ML workloads. Leadership asks what to do first about the workforce.

What should you recommend?

- **A.** Buy certification vouchers for every employee immediately.
- **B.** Assess current skills against the skills the target architecture requires, then build targeted training paths, hiring plans for critical gaps, and a cloud center of excellence.
- **C.** Wait until after the migration to think about skills.
- **D.** Outsource all cloud operations permanently.

<details><summary>Answer</summary>

**Answer: B**

**Why (P15):** Readiness starts with a gap analysis. Targeted training, selective hiring and a CCoE then build lasting capability.

- **A** — wrong: unfocused spend with no link to the needs.
- **B** — correct: assess, then plan training, hiring and enablement.
- **C** — wrong: staff can't operate what they weren't prepared for.
- **D** — wrong: abandons internal capability.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

</details>

### Q14 · Task 4.2 · Single answer

Two engineering teams disagree about whether a new service should run on GKE or Cloud Run, and the debate has stalled the project for a month.

How should the architect resolve it?

- **A.** Let the most senior engineer pick the option they prefer.
- **B.** Have both teams build the service on both platforms all the way to production.
- **C.** Choose whichever platform was released most recently.
- **D.** Agree the requirements and evaluation criteria (NFRs, operations burden, cost), run a short proof of concept, record the decision in an architecture decision record, and let the accountable owner decide.

<details><summary>Answer</summary>

**Answer: D**

**Why (P5, P9):** Structured, criteria-based decisions backed by evidence and recorded in an ADR end debates and leave an audit trail.

- **A** — wrong: preference-based, and alienates the other team.
- **B** — wrong: wastes effort, with a duplicate production build.
- **C** — wrong: novelty isn't a requirement.
- **D** — correct: evidence, criteria, documentation and clear accountability.

**Reference:** <https://cloud.google.com/architecture/architecture-decision-records>

</details>

### Q15 · Task 4.2 · Single answer

After migrating, the CFO complains that monthly cloud bills fluctuate, while the old data center was a predictable capital expense. About 70% of compute usage is steady around the clock, and 30% follows daily peaks.

What should you recommend?

- **A.** Cover the steady baseline with committed use discounts, keep autoscaling on-demand capacity for peaks, and add budgets, alerts and forecasting from billing data.
- **B.** Return to buying on-premises hardware, to restore predictability.
- **C.** Run everything on Spot VMs to minimize cost.
- **D.** Turn off autoscaling and run peak capacity around the clock, so bills are flat.

<details><summary>Answer</summary>

**Answer: A**

**Why (P9):** Commitments bring predictability and discounts to the steady 70%, elasticity keeps the peaks cheap, and budgets and forecasts give finance visibility.

- **A** — correct: matches the pricing model to each part of the load curve.
- **B** — wrong: gives up cloud benefits to solve a governance problem.
- **C** — wrong: Spot can be preempted at any time, so it's unsuitable for steady production serving.
- **D** — wrong: flat but wasteful, paying for peak capacity all day.

**Reference:** <https://cloud.google.com/docs/cuds>

</details>

### Q16 · Task 4.2 · Select TWO

Finance can't attribute Google Cloud costs to departments or environments, so chargeback is impossible.

Which two actions should you take? (Select TWO.)

- **A.** Email one consolidated billing PDF to every department each month.
- **B.** Remove labels from resources, to simplify billing.
- **C.** Require cost-allocation labels (for example `team`, `env`, `cost-center`) on all resources, enforced through IaC modules and policy checks.
- **D.** Create a separate billing account for every virtual machine.
- **E.** Export Cloud Billing data to BigQuery, and build per-department cost dashboards from it.

<details><summary>Answer</summary>

**Answer: C, E**

**Why (P9, P13):** Attribution needs consistent metadata (labels) and detailed, queryable cost data (billing export). Together they enable showback and chargeback.

- **A** — wrong: consolidated totals can't be split by department.
- **B** — wrong: removes the information needed for attribution.
- **C** — correct: consistent allocation keys on every resource.
- **D** — wrong: absurd administrative overhead.
- **E** — correct: detailed cost data for analysis and dashboards.

**Reference:** <https://cloud.google.com/billing/docs/how-to/export-data-bigquery>

</details>

### Q17 · Task 4.2 · Single answer

Leadership asks for a 20% reduction in cloud spend this quarter, without affecting production reliability.

Which approach is most appropriate?

- **A.** Cut the machine size of every production instance in half.
- **B.** Act on Recommender findings (idle resources, VM rightsizing), stop non-production environments outside working hours, apply storage lifecycle rules, use Spot for batch jobs, and commit to steady usage with CUDs.
- **C.** Buy the largest possible 3-year commitment for all current usage.
- **D.** Delete monitoring and logging to save their cost.

<details><summary>Answer</summary>

**Answer: B**

**Why (P9):** Combine waste removal, scheduling, data lifecycle, discounted capacity for suitable workloads and commitments for steady usage. Each targets cost without touching production reliability.

- **A** — wrong: blind downsizing risks production performance.
- **B** — correct: targeted, low-risk savings from several levers.
- **C** — wrong: commits to waste before optimizing usage.
- **D** — wrong: removes the visibility needed to operate safely.

**Reference:** <https://cloud.google.com/recommender/docs/overview>

</details>

### Q18 · Task 4.2 · Single answer

Developers' sandbox projects regularly overspend their budgets. The company wants overspending stopped automatically in sandboxes, with **no** risk to production projects.

What should you implement?

- **A.** Budgets on all projects that disable billing on any project, including production, when it exceeds its threshold.
- **B.** Quotas set to zero for every service in every project.
- **C.** Sandbox budgets with programmatic notifications to Pub/Sub, triggering a Cloud Run function that notifies the owner and disables billing (or stops resources) only on sandbox projects.
- **D.** A monthly manual review of sandbox spending.

<details><summary>Answer</summary>

**Answer: C**

**Why (P9, P12):** Budget notifications can drive automation. Scoping the drastic action to sandboxes protects production, because disabling billing stops or deletes resources.

- **A** — wrong: risks a production outage.
- **B** — wrong: blocks all work.
- **C** — correct: automated cost control with a safe scope.
- **D** — wrong: too slow to prevent overruns.

**Reference:** <https://cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications>

</details>

### Q19 · Task 4.2 · Single answer

A retailer is launching an AI shopping assistant. The steering committee asks how it will know whether the project is a success.

What should you recommend?

- **A.** Count the number of conversational intents the team has built.
- **B.** Track only the assistant's uptime.
- **C.** Wait for informal feedback from store managers.
- **D.** Agree business KPIs with stakeholders before launch (conversion rate, call-center deflection, customer satisfaction, return rate), track them on dashboards alongside SLOs, and review them regularly with feedback loops into the backlog.

<details><summary>Answer</summary>

**Answer: D**

**Why (P13):** Customer success management means outcome-based measures agreed up front, measured continuously and acted on.

- **A** — wrong: an output metric, not an outcome.
- **B** — wrong: uptime is necessary but says nothing about business value.
- **C** — wrong: anecdotal and late.
- **D** — correct: measurable business outcomes with regular reviews.

**Reference:** <https://cloud.google.com/architecture/framework>

</details>

### Q20 · Task 4.2 · Single answer

During a business-continuity review, the company discovers that only one engineer knows how to fail the payment system over to the DR region, and that the procedure isn't written down.

What should you recommend?

- **A.** Cross-train several engineers, document the failover runbook, automate the steps where possible, and rehearse them in regular DR drills with rotating participants.
- **B.** Give that engineer a pager and require them to be available around the clock.
- **C.** Accept the risk, because the engineer has been reliable so far.
- **D.** Outsource DR to a vendor, without changing internal processes.

<details><summary>Answer</summary>

**Answer: A**

**Why (P2, P12):** A single person is a single point of failure, just like a single server. Documentation, automation and practiced rotation remove it.

- **A** — correct: redundancy in people and process, verified by drills.
- **B** — wrong: still a single point of failure, and leads to burnout.
- **C** — wrong: an unmanaged risk.
- **D** — wrong: transfers the problem without building resilience.

**Reference:** <https://cloud.google.com/architecture/dr-scenarios-planning-guide>

</details>
