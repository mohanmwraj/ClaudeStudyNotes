# 03.3 · Driving Multi-Team Migrations and Adoption Without Mandates

> **Folder 03 · File 3 of 3.** Migrations are the most common L6/L7 story, and the most commonly told at L5 scope. "I migrated our services to the new platform" describes execution. What a committee wants to hear is how you got **forty teams who didn't report to you, each with its own roadmap, to move**, and how you finished, which is the part most migrations never reach.
>
> Will Larson calls migrations "the sole scalable fix to tech debt". They're also the purest test of influence without authority: the migrating teams pay the cost, while the benefit lands somewhere else.
>
> This file covers:
> - why migrations stall, in economic terms;
> - Larson's three phases (de-risk, enable, finish), with the senior additions;
> - the adoption playbook without a mandate;
> - resolving an apparent contradiction: hardest cases first for the design, lowest blast radius first for the cutover;
> - when a mandate is right, and how to make one that isn't a tax;
> - a rubric, three story blueprints and five follow-up chains.
>
> Folder 06 covers telling a legacy-to-cloud migration as a strangler-fig, zero-downtime, multi-stakeholder story. Stories are **illustrative composites**.

---

## 1. Why migrations stall

### 1.1 The economics

| Party | Pays | Gets |
|---|---|---|
| **Migrating team** | Engineering time, risk of an incident, a delayed roadmap item | Little that's visible to *their* stakeholders, at least at first |
| **Platform team** | Building the new system, supporting two systems during the transition | Lower operating cost and fewer incidents, *after the last team moves* |
| **The company** | Duplicate systems until the end | Lower cost, less risk, faster development |

That asymmetry explains the familiar curve: the first 60% of teams move in a couple of quarters, the next 30% take a year, and the last 10% never move, so the old system can never be turned off, and the company pays for both indefinitely.

### 1.2 The stall causes

| Cause | What it looks like | The counter |
|---|---|---|
| **Cost lands on the wrong team** | "It's not on our roadmap" | Make migration nearly free for them (tooling, embedded help) |
| **No forcing function** | Teams wait for a deadline that never firms up | A date set from evidence, once the path is proven |
| **The new path is worse at something** | One feature or performance property is missing | Fix it, or offer a published escape hatch |
| **Fear** | A team had an incident in a previous migration | Dual-run comparators; rollback in minutes; you own the cutover risk |
| **The long tail** | Unusual services with special needs | The platform team migrates them itself |
| **New usage keeps arriving** | New services still start on the old system | Stop the bleeding: block new adoption of the old path |

---

## 2. Larson's three phases, with the senior additions

Larson's essay *Migrations: the sole scalable fix to tech debt* describes three phases:

| Phase | Larson's core idea | What a senior story adds |
|---|---|---|
| **De-risk** | Write the design; test it with the most demanding teams before broad rollout | Find the requirement that would break the design, early; write down kill criteria for the migration itself |
| **Enable** | Build tooling and documentation so most teams can migrate themselves cheaply | Measure cost per migration and drive it down; make the new path cheaper than staying |
| **Finish** | Stop new usage of the old system; track progress; nudge; then migrate the remainder yourselves, and turn the old system off | Treat "turned off" as the only definition of done, and plan the long tail from the start |

### 2.1 An apparent contradiction, resolved

Larson advises starting with the most demanding teams, so you don't get false confidence from easy ones. Folder 01's L7 story migrated the highest-risk team *last*. Both are right, because they're about different things:
- **De-risk the design against the hardest requirements first**: in shadow mode, in prototypes, by embedding with the most demanding team before anyone commits.
- **Sequence production cutovers by blast radius**: lower-risk traffic first, until the cutover tooling and the operational runbooks are proven.

An L7 answer can state this distinction. It's one of the clearest signs that someone has run a large migration rather than read about one.

---

## 3. The adoption playbook without a mandate

### 3.1 Make the new path cheaper than the old one

Teams don't adopt platforms because they're better; they adopt them because **staying becomes more expensive than moving**. Two levers:
- **Lower the cost of moving**: tooling, templates, embedded engineers, compatibility shims.
- **Make the cost of staying visible**: the old system's incidents, the features it will never get, its operational burden on the team, shown on a dashboard.

This is the **paved road** idea: the supported path is so much easier that leaving it requires a reason.

### 3.2 Do the first migrations yourself

Your first two or three migrations should be done **with your own hands, embedded in the migrating team**, for three reasons:
1. you find the problems the design missed;
2. the migrating engineers become advocates, which spreads adoption team to team rather than by decree;
3. you earn the standing to ask the next teams to move.

### 3.3 Automate the bulk

At scale, a migration is a software project in its own right:
- **codemods and automated refactoring** (for example, OpenRewrite recipes for Java upgrades), which open pull requests teams only need to review;
- **compatibility shims** so teams can migrate in small steps;
- **dual-run comparators** that send traffic to both systems and diff the results;
- **one-command cutover and rollback**.

Track the **cost per migration** in engineer-days. A senior migration story shows that number falling, from weeks for the first team to hours for the fortieth.

### 3.4 Stop the bleeding

Before the long push, make sure nothing new starts on the old system: a CI check, a lint rule, a template change, a review gate. Otherwise the count of things to migrate keeps growing as you work.

### 3.5 A public scoreboard

A dashboard showing every team's migration status changes behaviour without a mandate. Nobody wants to be the last red row in the quarterly review. Use it as information, not as shame: pair it with an offer of help for every red row.

### 3.6 Finish: the platform migrates the long tail

The last 10% of services are unusual, owned by busy or disbanded teams, or both. The senior move is to **plan for the platform team to migrate them itself**, budgeted from the start. Then **turn the old system off**, announce it, report the saving, and thank the teams by name.

---

## 4. When a mandate is right, and how to make one that isn't a tax

Some migrations need a mandate: a security vulnerability, a compliance deadline, a vendor end of life. Even then, the L7 difference is in how the mandate is built:

| Weak mandate | L7 mandate |
|---|---|
| Announced by email with a date | Date set from evidence, after the tooling has proven a cheap path on several teams |
| Every team does the work themselves | Automation does most of it; teams review and deploy |
| Exceptions handled ad hoc | A published exception process, with an owner and an expiry |
| Progress tracked in spreadsheets | A live scoreboard, with help offered for every red row |
| Done when the deadline passes | Done when the old path is gone and the risk is closed |

**A mandate without tooling is a tax.** It transfers the platform team's cost to every product team, and they remember.

---

## 5. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Scope** | Tens of teams across orgs; multiple quarters; to completion | Several teams; landed | Migrated own team's services | A task in someone else's migration |
| **Adoption mechanism** | Made staying more expensive than moving; adoption spread team to team; mandate only where justified, with tooling | Tooling and documentation; active persuasion | Asked teams to migrate | Relied on a mandate alone |
| **Economics** | Measured cost per migration and drove it down by an order of magnitude | Reduced migration effort | Didn't measure | Unaware of the cost to others |
| **Risk** | Design de-risked on hardest requirements; cutover sequenced by blast radius; comparators and rollback | Cutover plan with rollback | Careful in own services | Incidents caused by the migration |
| **Finish** | Old system turned off, long tail planned and migrated by the platform team; saving reported | Most teams migrated | Partially migrated | Never finished |
| **Leverage** | Reusable migration tooling; owners grown; the playbook used for later migrations | Documented the approach | None | None |

**Most common down-level:** the story ends at "80% of services migrated". The committee hears: two systems running indefinitely.

---

## 6. Story Blueprints

### 6.1 Without a mandate (composite: 140 services from a homegrown RPC framework to gRPC)

**The facts (composite):**
- 140 services across 30 teams use a homegrown RPC framework written eight years ago.
- It has no deadline propagation, which caused two cascading outages last year.
- Its original authors have left.
- There's no executive mandate; the infrastructure VP supports the change but won't force teams' roadmaps.

#### How an L5 tells it

> "Our homegrown RPC framework was old and caused some outages, so I led the migration to gRPC. I wrote a migration guide and a client library, presented it at the engineering all-hands, and teams started migrating. We got about 80% of services over in a year. A few legacy services are still on the old framework."

**What the committee extracts:** a guide, a library and a presentation; 80%; the old system still running. **L5–L6.**

#### How an L7 tells it

> "140 services across 30 teams ran on a homegrown RPC framework with no deadline propagation, and that had caused both of our cascading outages the previous year. There was no mandate, and the VP was clear she wouldn't force roadmaps. So the plan had to make moving cheaper than staying.
>
> I de-risked the design first against the hardest case: the search team's fan-out service, which calls forty backends per request. I embedded with them for three weeks and found that our gRPC defaults would have broken their hedged requests, so we fixed the interceptor before anyone else depended on it. Their engineers then advocated for it to other teams, which carried more weight than anything I could say.
>
> For production cutovers I went the other way, lowest blast radius first. I built three tools: a codemod that rewrote client and server stubs and opened a pull request, a compatibility proxy so a service could migrate without its callers changing, and a dual-run comparator that diffed responses on shadow traffic. The first migration took two engineer-weeks. By the twentieth, with the codemod handling most of it, it was about a day, mostly review.
>
> I also stopped the bleeding: a CI check blocked new services from importing the old framework. And I put every team's status on a public dashboard, next to an offer of an embedded engineer for any team that asked.
>
> After three quarters, 118 services had moved, nearly all by their own teams. The remaining 22 were the long tail, many owned by teams that had since been reorganized. I'd budgeted for that from the start: two engineers from my team migrated all 22 over one quarter. Then we turned the old framework off.
>
> We've had no cascading outages from missing deadlines since, the framework's maintenance cost went away, and the codemod-plus-comparator approach became the org's playbook. Two later migrations, including a logging library, reused the tooling, and one of the engineers who built the comparator led them."

**What the committee extracts:** no mandate; de-risked on the hardest case; cutover by blast radius; tooling that cut cost per migration from weeks to a day; stop-the-bleeding; public scoreboard with help; planned the long tail; turned the old system off; reusable playbook and a grown owner. **Strong L7.**

### 6.2 Adoption of a standard (composite: OpenTelemetry tracing across 30 teams)

#### How an L5 tells it

> "I championed distributed tracing in our org. I set up OpenTelemetry for my team's services and showed how it helped debug latency issues. I gave some talks and a few other teams adopted it too."

**What the committee extracts:** advocacy and a good local example; adoption by goodwill. **L5.**

#### How an L7 tells it

> "Our mean time to diagnose cross-service incidents was over two hours, mostly spent finding which service in a chain was slow. Tracing existed in four teams, each instrumented differently, so traces broke at every team boundary, which made them useless exactly where we needed them.
>
> A standard only works if nearly everyone adopts it, so I treated adoption as the product. I made the cost of adopting near zero: our shared service template got OpenTelemetry instrumentation by default, with propagation through the gateway, the queues and the job scheduler, which were the three places traces broke. Teams on the template got tracing by upgrading a dependency.
>
> Then I made the value visible where people would feel it. In the next three major incidents, I posted the trace showing exactly where time went, in the incident channel, while the incident was running. After the third, requests to adopt came to us.
>
> For teams not on the template, I wrote a one-page adoption guide and held office hours. I didn't push the six teams with unusual stacks; I left them until the platform team could support them properly. Within two quarters, 27 of 30 teams were instrumented, mean time to diagnose cross-service incidents fell from about two hours to twenty minutes, and the incident process now starts with the trace. The three remaining teams were migrated by the platform team the following quarter."

**What the committee extracts:** framed the cost of the status quo; adoption cost driven to zero through the template; value shown at the moment of pain; respected teams with unusual needs; outcome measured in incident terms; finished. **L7 adoption without mandate.**

### 6.3 A mandate done right (composite: Java 8 to Java 21 across 200 services)

**The facts (composite):** a security review requires all services off Java 8 by a date tied to a compliance audit. Two hundred services, 45 teams.

#### How an L5 tells it

> "We had a deadline to move off Java 8 for a security audit. I made a spreadsheet of services, sent reminders to the teams, and answered questions in a Slack channel. Most teams finished by the deadline, and a few got exceptions."

**What the committee extracts:** coordination of a mandate; cost landed on every team. **L5.**

#### How an L7 tells it

> "A compliance audit required all 200 services across 45 teams off Java 8 by a fixed date. The mandate was real, but if every team did the work by hand it would cost roughly two engineer-weeks per service, about eight engineer-years in total.
>
> Before any announcement, I proved a cheaper path. I used OpenRewrite migration recipes plus a handful of our own for internal libraries, and ran them against ten representative services. Eight of them compiled and passed tests with no manual change; the other two needed a day each, for reflection-heavy code. With that evidence I set the date six weeks earlier than the audit, so there was buffer, and published it alongside the tooling.
>
> The tooling opened a pull request against every repository, with the upgrade applied and the test results attached. Teams only had to review and deploy. A published exception process, with an owner and a 60-day expiry, handled the services with real blockers. Every red row on the scoreboard came with an offer of help.
>
> 190 services were upgraded by their own teams within two months, at an average of under half a day of team time each. The last ten needed real work, and my team did them. We passed the audit with no findings on runtime versions, and the services got the JDK's garbage-collector improvements for free: p99 latency fell about 15% across the fleet. The recipe set is now how we do every JDK upgrade."

**What the committee extracts:** a justified mandate made cheap with tooling, proven before the announcement; a date set from evidence with buffer; review-and-deploy instead of rewrite; an exception process; the long tail done by the platform team; a side benefit measured; reusable mechanism. **L7 mandate.**

---

## 7. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "How did you get teams to move?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Why would a team with a full roadmap migrate?" | Economics | "It was a priority" | "Because moving cost a day, and staying cost them their outage risk" |
| 2 | "Which team resisted most, and why?" | Empathy | "Legacy teams" | The specific team and its legitimate reason |
| 3 | "What did you do for them?" | Influence | "Escalated" | Embedded help, a shim, or left them for the long-tail plan |
| 4 | "Was there a mandate?" | Authority | Unclear | "No; the VP wouldn't force roadmaps" |
| 5 | "How many migrated without being asked?" | Pull vs push | Unknown | A number, and when the pull started |

### Chain B · Cost per migration

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How long did the first migration take?" | Measurement | Unsure | Two engineer-weeks |
| 2 | "And the last?" | Improvement | Unsure | About a day |
| 3 | "What made the difference?" | Tooling | "Experience" | The codemod, the proxy, the comparator |
| 4 | "Who built the tooling?" | Contribution | "The team" | Who built which piece |

### Chain C · "Is it finished?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Is the old system turned off?" | Finishing | "Mostly" | "Yes, on a specific date" |
| 2 | "Who migrated the last services?" | Long tail | "The owning teams, eventually" | "My team, as planned from the start" |
| 3 | "How did you stop new usage?" | Bleeding | Nothing | The CI check |
| 4 | "What did turning it off save?" | Result | Unknown | Cost, risk and maintenance, quantified |

### Chain D · Risk

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Did the migration cause any incidents?" | Honesty | "No" (if untrue) | The incidents, and what changed after them |
| 2 | "How did you know a migrated service behaved the same?" | Verification | "Tests" | The dual-run comparator |
| 3 | "Which order did teams go in, and why?" | Sequencing | "Whoever was ready" | Hardest case first for design, lowest blast radius first for cutover |
| 4 | "How fast could you roll back?" | Reversibility | Unsure | A number, and evidence it worked |

### Chain E · Mandates

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Why was a mandate justified here?" | Judgment | "Leadership said so" | The compliance reason |
| 2 | "How did you set the date?" | Evidence | "The audit date" | From tooling results on ten services, with buffer |
| 3 | "What did it cost each team?" | Care for others | Unknown | Under half a day on average |
| 4 | "What happened with exceptions?" | Governance | Ad hoc | Owner and expiry |

---

## 8. Checklist

- [ ] Your migration story names the number of teams that didn't report to you.
- [ ] You can explain why a busy team would choose to migrate (the economics).
- [ ] You did the first migrations yourself, embedded.
- [ ] You can give the cost per migration at the start and at the end.
- [ ] You stopped new usage of the old path.
- [ ] The old system is turned off, and you know what that saved.
- [ ] You can state the hardest-first (design) vs lowest-risk-first (cutover) distinction.
- [ ] If there was a mandate: justified, tooling-backed, date from evidence, exception process.

## 9. References

- Will Larson, "Migrations: the sole scalable fix to tech debt". <https://lethain.com/migrations/>
- Martin Fowler, "Strangler Fig Application". <https://martinfowler.com/bliki/StranglerFigApplication.html>
- OpenRewrite documentation (automated refactoring and migration recipes). <https://docs.openrewrite.org/>
- OpenTelemetry. <https://opentelemetry.io/>
- In this KB: [03.1 Architectural wars](01-resolving-architectural-wars-between-competing-principal-engineers.md) · [03.2 Influencing executives](02-influencing-product-and-execs-killing-bad-projects-and-saying-no.md) · Folder 06 reframes migration stories as strangler-fig and zero-downtime cutover narratives.
- Technical depth: the cell, multi-region and cutover material in the [Distributed Systems Design L7 Reference](../../Distributed-Systems-Design-L7-Reference/).
