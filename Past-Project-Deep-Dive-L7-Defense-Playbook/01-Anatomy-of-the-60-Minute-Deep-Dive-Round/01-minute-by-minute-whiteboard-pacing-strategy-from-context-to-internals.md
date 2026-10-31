# 01.1 · Minute-by-Minute Whiteboard Pacing Strategy: From Context to Internals

> **Folder:** `01-Anatomy-of-the-60-Minute-Deep-Dive-Round` · file 1 of 3
> **Question this file answers:** how do I spend 60 minutes so that two skeptical Principal Engineers see the context, the architecture, the internals of the part I built, how it failed, and what I learned, and still have the time they need to grill me?
> **Running exhibit:** P-0 "Beacon", a composite configuration and feature-flag distribution platform (fact sheet in [§3](#3-the-running-exhibit-p-0-beacon-fact-sheet)). Files [01.2](02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md) and [01.3](03-framing-constraints-legacy-tech-debt-client-politics-and-tight-deadlines.md) use the same exhibit.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff. Amazon's L7 is Principal; Google's and Meta's L7 is Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L1 `pace_check.py` | Python 3, standard library | Estimates the time each section of a scripted plan takes. Flags over-budget sections, monologues with no checkpoint, a context section with no numbers, a headline over 90 s, more than 7 min of context, a first deep dive after 20:00, and gaps in the timeline. | [§8](#8-the-scripted-plans-and-the-pacing-check), on the two plans in this file |

**Verification.** The gate extracts the listing from this file and checks it byte for byte against the source that was run. It then re-runs the listing on this file and compares the result with the output block in §8. Every `#### How an L5/L7 tells it` blockquote is linted by [`ownership_lint.py`](02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md#13-the-ownership-lint) and [`constraint_check.py`](03-framing-constraints-legacy-tech-debt-client-politics-and-tight-deadlines.md#12-the-constraint-checker). Every L5 telling must be flagged and every L7 telling must be clean. Relative links and external URLs are checked too. The results are in the [README](../README.md#gate-results).

---

## 0. Orientation

The "Past Project Technical Deep-Dive", also called the "Architecture Retrospective" or "Project Deep Dive", is the round where a senior candidate's résumé is cross-examined. Other rounds ask you to design something hypothetical. This one asks you to explain something you really built, under questions from people who have built bigger versions of it and know where such systems break. At L6 and L7 it is often the round that decides the level. It is also the round where an inflated résumé comes apart.

The goal of this file is mechanical: control of the clock. Files 01.2 and 01.3 cover what the interviewers test (authorship) and how to frame the constraints that shaped your design. Folder 02 covers trade-off defense, Folder 03 four full archetype blueprints, Folder 04 the 25 hardest cross-examination questions, and Folder 05 your own dossier and a stress-test harness.

**How to use this file.**
1. Read §1–§2 to understand what is measured and how the hour divides.
2. Read §3, the exhibit, so the worked examples make sense.
3. Choose your project with §4.
4. Build your board (§5–§6) and your plan (§7–§8).
5. Rehearse with `pace_check.py` and a recorder until your spoken timings match the budget.
6. Drill §9–§11 (interrupts, re-budgeting, depth reserves) with a partner who interrupts you on purpose.

**Conventions used throughout the knowledge base.**
- **⚠** marks a mechanic that is not publicly documented: a reported pattern, a composite of common practice, or a reasonable inference. Treat it as a planning assumption, not a fact about a particular company.
- **Companies are domain lenses.** Nothing here is a leaked question bank. Every question is an original formulation of the kind of probe the round uses.
- **Every exhibit is a composite.** The numbers are placeholders chosen to be internally consistent. Do not copy them. Replace them with your own measured numbers (Folder 05 gives you the template).
- **Integrity rule.** This playbook teaches you to present work you really did, at its true scope, as clearly as possible. It never helps you claim decisions you did not make. That is an ethical line, and it is also tactical: the round is built to find out where your knowledge stops, and a claim you cannot defend at depth costs more than a smaller claim you can defend.

---

## 1. First principles: what the round actually measures

### 1.1 The round is evidence collection, not conversation

Each interviewer leaves the room needing to write feedback that someone else can act on: a hiring committee, a debrief led by a Bar Raiser, a hiring manager. Google's published guidance on structured interviewing names four practices: vetted, role-relevant questions; *recording comprehensive feedback* so evaluators can review responses; scoring with standardized rubrics; and interviewer training and calibration. Its rubrics describe what "a poor, borderline, solid, and outstanding answer would cover" ([re:Work guide](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). Amazon publicly describes Bar Raisers as "objective third-party advisers" who "facilitate debrief conversations to ensure data-driven conversations" and make the final decision with the hiring manager, aiming for hires better than 50% of their would-be peers ([About Amazon: Bar Raisers](https://www.aboutamazon.com/news/workplace/amazon-bar-raiser)).

Two consequences follow, and they drive every pacing decision in this file.

1. **Your job is to produce quotable evidence.** "Candidate designed a monotonic, signed snapshot protocol and could explain why rollback is a roll-forward (replay defense)" is a sentence that helps a committee. "Candidate seemed very knowledgeable" helps nobody, and an outstanding hour can collapse into that if your evidence came out too fast to write down.
2. **What you leave unsaid scores zero.** If you run out of time before the failure story, the notes have no failure story. Interviewers rarely give credit for "they probably would have." Pacing decides which of your evidence makes it into the notes.

### 1.2 The seven signals (composite rubric ⚠)

No company publishes its deep-dive rubric. The signals below are a composite of what L6/L7 deep-dive feedback tends to cover. File [01.2](02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md) turns them into a scoring grid.

| # | Signal | The interviewer's private question | Where in the hour it gets evidence |
|---|---|---|---|
| S1 | **Scope and ambiguity** | How big and how ill-defined was the problem this person owned? | Headline, context |
| S2 | **Personal ownership** | Which decisions were theirs, and could they have made them? | Architecture (ownership marks), deep dive, provenance probes |
| S3 | **Technical depth** | Where is their *depth floor*, the level below which they stop knowing? | Deep dives |
| S4 | **Trade-off judgment** | Did they consider real alternatives and choose for stated reasons? | Trade-offs, "why not simpler" |
| S5 | **Operational maturity** | Do they know how it fails, how they would know, and what they did when it did? | Failure story, day-2 probes |
| S6 | **Impact and learning** | Did it matter, measured how, and what would they change? | Impact, hindsight |
| S7 | **Communication structure** | Can they build a shared mental model in layers, under interruption? | The whole hour (a multiplier on S1–S6) |

S7 is a multiplier, not just one more score. A candidate with real L7 depth and poor structure often gets an L6 outcome, because the interviewers never reach the depth: they spend 30 minutes rebuilding the context the candidate skipped.

### 1.3 The depth-floor model

Everyone has a depth floor on every component, a level below which they don't know. Interviewers are searching for it on purpose. They descend until you stop knowing, then note the floor's location and how you behaved when you reached it. Three behaviors are possible at the floor.

| Behavior at the floor | What the notes say | Level signal |
|---|---|---|
| Keeps talking with the same confidence, gets vaguer, uses more buzzwords | "Bluffed below their depth; concerns about the accuracy of other claims" | Negative for every level. This retroactively discounts everything above it. |
| Stops, says "I don't know", silence | "Limited depth on X" | Neutral to slightly negative |
| Names the floor, says who owned the layer below, gives the reasoning they do have, and says how they would find out | "Calibrated; clear boundary between own work and team's; reasoned soundly from first principles past their boundary" | Positive. It is often scored *above* a candidate who answered everything with less precision. |

**A deep floor on the starred components plus an honest floor elsewhere is the L7 profile.** You don't need to know the relay team's gRPC flow-control settings. You do need to know your own snapshot protocol down to the byte layout, the fsync ordering and the failure cases. §11 shows how to prepare those depths ("wells").

### 1.4 Two interviewers: why the room has two people in it

When two senior interviewers share the round (⚠ formats vary: some companies use one interviewer, some use two, and some add a shadowing trainee), they usually split roles, explicitly or by habit:

- **The driver** asks most questions, steers the depth, and keeps time.
- **The prober / scribe** writes notes and comes in sideways: consistency checks ("earlier you said 27 relays, so how many streams per relay?"), the second-order "what did that cost?", and ownership challenges.

Consequences for pacing:
- **Address both.** The scribe's notes are half the evidence. When the scribe's pen moves fast, you have just said something quotable; slow down and let it land.
- **Expect the scribe's consistency checks 15–25 minutes after you state a number.** A number you derived survives. A number you memorized from a slide does not. §12 is the defense.
- **Expect them to divide the territory.** One may own architecture and depth, the other ownership and leadership (⚠ reported). If one interviewer has been silent for 20 minutes, invite them in ("Is there an area you'd like me to cover?"). That gives them a way into the hour and gives you information.

### 1.5 Why pacing is a technical skill

The interviewer's mental model of your system forms in the first ten minutes. If the model is wrong or missing, every later deep question goes through a broken map: they ask about a component they don't know exists, you answer with context they lack, and the exchange degrades into clarification. When that happens, interviewers take control of the hour to protect their own evidence collection, and you lose the narrative. **Pacing is information architecture under a time limit.** The layered disclosure in §6 is the same discipline as good API design: present the interface before the implementation.

### 1.6 The curse of knowledge

You have lived inside this system for months or years; the interviewers met it 90 seconds ago. Every acronym, team name, internal tool and "the usual path" you mention is a small tax on their working memory. Rules that pay for themselves:
- **Rename internal things generically on first mention:** "our config service (internally 'Beacon')"; "the stream processor"; "the platform's object store".
- **One concept per sentence in the context phase.** Density comes later.
- **Put every number on the board** in the numbers column (§5) so nobody has to hold it in memory.

---

## 2. The 60-minute clock: the canonical budget

The budget below assumes a 60-minute round with a short introduction and a candidate-questions block at the end. Many rounds are 45 minutes (scale every window by 0.75, and drop P5's prepared speech first). Some teams use a presentation format: 20–30 minutes of your talk, then questions (⚠ ask the recruiter which format, and whether a prepared diagram is allowed).

| Phase | Window | Goal | On the board at exit | Evidence produced | Cut priority (1 = cut first) |
|---|---|---|---|---|---|
| P0 Intros | 00:00–02:00 | Two-sentence self-introduction; agree which project to discuss | Nothing | none | 1 |
| P1 Headline | 02:00–04:00 | System, scale, pain, your role, outcome, two hooks, in at most 90 s | Title, one-line role | S1, S2 preview | never (compress to 40 s) |
| P2 Context (C4 L1) | 04:00–09:00 | Users, before-state, why it hurt (with numbers), constraints, success criteria | Context strip, numbers column started | S1 | 3 |
| P3 Architecture (C4 L2) | 09:00–16:00 | Write path, read path, control and data plane, ownership marks, labeled rates | Full container diagram | S2, S3 preview | 4 |
| P4 Deep dive 1 (C4 L3/L4) | 16:00–28:00 | Your main component: invariants, data structures, protocol, failure cases, numbers | Zoomed sub-diagram | S2, S3 | never |
| P5 Deep dive 2 / failure archaeology | 28:00–38:00 | A real failure: detection, bounding, mitigation, root cause, systemic fix | Failure timeline | S3, S5 | 2 (compress to 90 s) |
| P6 Trade-offs | 38:00–44:00 | 2–3 real alternatives and why each was rejected | Options table | S4 | 5 |
| P7 Impact and drive | 44:00–49:00 | Before and after numbers, adoption, how you moved the organization | Results in the numbers column | S1, S6 | 3 |
| P8 Hindsight | 49:00–52:00 | What you would change today, and why it wasn't knowable then | One annotated box | S6 | never (compress to 30 s) |
| P9 Their questions and yours | 52:00–60:00 | Buffer for their remaining probes; 1–2 questions from you | Unchanged | S7 | absorbs overruns |

### 2.1 Three time zones

The table above is a plan. The real hour divides into three zones of control:

- **Your clock (00:00–~16:00).** The interviewers want you to build the map. They interrupt mostly to clarify. Deliver P0–P3 nearly as scripted.
- **Shared clock (~16:00–~44:00).** You offer a depth menu and they choose. Typically 40–60% of this zone is spent answering their questions, not giving your prepared speech (⚠ estimate). Your plan becomes a list of evidence you still need to surface.
- **Their clock (~44:00–60:00).** They fill gaps in their notes. Expect rapid-fire probes on whatever they didn't get: ownership, numbers, failure, hindsight. P7–P8 are often delivered as answers to their questions.

**Design implication.** Prepare P4–P8 as modules, not a speech. Each module needs a 100% version, a 50% version, and a one-sentence version (§10), because you won't know until minute 16 how much of the shared clock will be yours.

### 2.2 The checkpoints

Glance at a clock at three fixed points and compare with the plan:

| Checkpoint | You should be | If you're late by more than 3 minutes |
|---|---|---|
| **16:00** | Finishing the architecture and offering the depth menu | Stop drawing. Offer the menu now; the unfinished parts of the diagram become "I'll add that when we get there". |
| **28:00** | Leaving deep dive 1 | Use the 90-second failure story (§10), not the 10-minute one |
| **44:00** | Entering impact | Deliver impact as three numbers in 30 s, then hindsight in 30 s, then hand the time to them |

---

## 3. The running exhibit: P-0 "Beacon" fact sheet

> **Composite.** Beacon is not a description of any real company's system. The numbers are placeholders made internally consistent so the worked examples can be checked. The incidents echo public postmortems of config-propagation failures, cited in §3.6, because those show the round's favorite failure class with primary sources.

### 3.1 Organization and before-state

- **Company:** a consumer marketplace with ~2,000 engineers, ~1,200 production services, 3 regions (`us-east`, `us-west`, `eu-west`) and ~48,000 service instances at daily peak.
- **Static configuration:** YAML files in each service's repository, baked into the container image. A change means a rebuild and a redeploy: median lead time 55 minutes.
- **Dynamic flags:** one ZooKeeper ensemble (5 voting members) in the `us-east` colocation facility. ~9,000 znodes; read directly by ~300 services through 4 homegrown client libraries (two Java, one Go, one Python); ~14,000 client sessions at peak.

### 3.2 The 12 months before the project (the "why now")

| ID | Severity | Duration | What happened |
|---|---|---|---|
| INC-A1 | Sev-1 | 38 min | A rollout-percentage typo (`100` instead of `10`) on a recommendations flag reached every instance in every region in about 2 s. The recommendation backend saturated, and checkout p99 latency spiked. |
| INC-A2 | Sev-1 | 52 min | A ZooKeeper leader election during a colo network flap caused a session-expiry storm. Two of the four client libraries fell back to compiled-in defaults, and one default disabled the public API's rate limiter. |
| INC-A3 | Sev-2 | 20 min | The ensemble's disk filled with uncompacted snapshots and transaction logs, so writes were rejected. During an unrelated incident, a kill switch could not be flipped. |

**Two forcing functions.**
- **Hard deadline.** The `us-east` colo lease ended 9 months after the RFC was approved. The ensemble had to be gone by then: an extension meant a 6-month minimum term at about $190k a month.
- **Compliance.** A SOC 2 audit finding said the ensemble had open ACLs and no client authentication. Remediation was due in month 6.

### 3.3 Goals and SLOs (the RFC's success criteria)

| ID | Goal | Target |
|---|---|---|
| G1 | **Safety:** every non-emergency change moves through rings: ring0 (one canary cell ≈ 1% of instances, `us-west`) → ring1 (all of `us-west`) → ring2 (all regions), with an automated halt | Blast radius of a bad change ≤ 1% of instances for ≤ 5 min |
| G2 | **Propagation:** from ring advance to applied on 99% of the ring's instances | p99 ≤ 30 s |
| G3 | **Fail-static:** a control-plane outage means *no new changes*, never *no config*. Reads never block on the network. | 0 reads failing because the control plane is unavailable |
| G4 | **Read cost:** an in-process lookup | p99 < 1 µs; no allocation on the Java hot path |
| G5 | **Auditability:** every change attributable (who, ticket, diff) and reversible by rolling forward | 100% of changes |

### 3.4 Architecture after (ownership marked)

Legend: **★** = I designed it and led or wrote it · **◆** = I reviewed it or contributed to it · **○** = built by the team or another team; I consumed it.

| # | Component | Owner mark | What it does |
|---|---|---|---|
| C1 | Config API + UI | ○ | CRUD, review workflow, role-based access |
| C2 | Postgres (platform DB service) | ○ | Source of truth: an append-only `config_change` log plus a namespace table |
| C3 | Validator | ★ contract, ◆ plugins | Schema plus semantic checks. Rule: *parse with the same parser the consumer uses* |
| C4 | Publisher | ★ | Builds an immutable snapshot per (namespace, environment): content-addressed (SHA-256), monotonic version per namespace, Ed25519 signature through KMS, 4 MB hard cap. Writes to regional object storage and announces `(namespace, version, digest)` to the relays. |
| C5 | Relay tier | ○, ◆ protocol review | Regional and stateless. A gRPC stream `Watch(namespace, have_version)` returns the newest version pointer. 27 relays (3 regions × 3 AZs × 3). |
| C6 | SDK | ★ semantics + Java reference, ○ Go/Python/Node ports (language-platform teams) | Immutable in-memory snapshot with an atomic reference swap; last-known-good (LKG) kept on disk in 2 generations; signature and monotonic-version check; reports the applied version |
| C7 | Rollout controller | ★ (co-written with one engineer) | Advances rings after a bake time (ring0 5 min, ring1 15 min) if the health gates pass; auto-halts and auto-reverts by rolling forward |
| C8 | Break-glass lane | ★ policy | Boolean kill switches only; 2-person approval; skips bake times; pages the on-call |
| C9 | ZooKeeper bridge + shadow diff | ★ (led the migration) | Dual-read in shadow mode, mismatch metrics, a compatibility shim for legacy client semantics, cutover per namespace |
| C10 | Propagation observability | ○ SRE partner | Version-skew and propagation-lag dashboards fed by the SDK's applied-version reports |

### 3.5 Scale, team, timeline, outcomes

| Fact | Value | Provenance |
|---|---|---|
| Instances at peak | ~48,000 | [M] platform inventory |
| Namespaces | ~2,100 | [M] |
| Change rate | ~1,900/week (~270/day); peak ~40/min in release windows | [M] audit log |
| Snapshot size | median 18 KB, p99 1.2 MB, hard cap 4 MB | [M] / [D] |
| Relay streams | ~48,000 total, ~1,800 per relay | [M] |
| Widest namespace fan-out | 48,000 fetches × 18 KB ≈ 864 MB per change, spread by 0–5 s client jitter | [E] derived |
| "Why not Postgres polling" load | 48,000 instances ÷ 10 s = 4,800 QPS; one replica load-tested at 12,000 QPS on the point read | [E] derived, [M] load test |
| Team | 6 engineers (me as tech lead, Staff level), 1 EM, PM at 50%, SRE partner at 50% | — |
| Timeline | M0–M1 RFC (3 alternatives, 2 major revisions); M1–M4 build; M3–M6 shadow mode; M5 interim ZK hardening (mTLS proxy + ACLs) to meet the M6 compliance date; M6–M8 cutover by namespace; M8.5 ZK write freeze; M9 decommission, ~2 weeks before the lease end | — |
| Propagation after launch | p50 9 s, p99 24 s within the target ring | [M] SDK reports |
| Config-caused Sev-1s | 2 in the 12 months before → 0 in the 12 months after | [M] incident tracker |
| Bad changes halted | 3 auto-halted in ring0; worst blast radius 1.1% of instances for 4 min | [M] |
| Config-infra pages | ~11/month → ~2/month | [M] paging tool |
| Shadow-diff findings | 212 semantic mismatches across 37 services, found before cutover | [M] |

[M] = measured, [E] = estimate derived from measured inputs, [D] = design target. §12 explains why every number you say aloud needs one of these labels in your head.

### 3.6 The post-launch failure (used in P5)

**INC-B7 (Sev-2, 6 min).**
- **Trigger:** during a control-plane brownout (a bad relay deploy), a node-pool upgrade restarted ~140 instances in ring0.
- **What they found:** a truncated LKG file. The SDK wrote LKG in place, without fsync, and a node had been hard-stopped mid-write.
- **Impact:** the signature check failed, so the SDK fell back to compiled-in defaults for 6 minutes, until the relays recovered. About 0.3% of instances served with defaults.
- **Fix:**
  - write to a temp file, fsync, rename, then fsync the directory;
  - keep two LKG generations;
  - add a per-namespace `on_missing` policy (`defaults` | `fail_readiness`): critical namespaces fail readiness, so the instance never takes traffic with defaults.
- **Systemic changes:**
  - a CI chaos test that kills the process during an LKG write;
  - a `config_defaults_served` metric with an alert on it.

The atomic-rename discipline is POSIX `rename()` semantics ([POSIX `rename`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/rename.html)). The fsync-before-rename lesson has a long public history ([LWN: ext4 and data loss](https://lwn.net/Articles/322823/)).

**Why this failure class is the exhibit's spine.** Fast, global propagation of bad configuration or content is one of the best-documented outage classes in public postmortems:
- **Cloudflare, 2025-11-18.** A database permission change doubled the rows in a generated feature file. The file was regenerated every five minutes and propagated network-wide, and it exceeded a 200-feature limit, so the proxy panicked ([Cloudflare](https://blog.cloudflare.com/18-november-2025-outage/)).
- **Google Cloud, 2025-06-12.** A policy change with unintended blank fields replicated globally within seconds. It hit a code path that "did not have appropriate error handling nor was it feature flag protected", and the binary crashed ([Google Cloud incident report](https://status.cloud.google.com/incidents/ow5i3PPK96RduMcb1SsW)).
- **CrowdStrike, July 2024.** A content update made the sensor read a 21st input field when only 20 were supplied. One of the published findings was that template instances "should have staged deployment" ([CrowdStrike RCA](https://www.crowdstrike.com/wp-content/uploads/2024/08/Channel-File-291-Incident-Root-Cause-Analysis-08.06.2024.pdf)).

An interviewer who has read these will push exactly where Beacon is designed to hold: validation with the consumer's own parser, size caps at the producer, staged rollout, and fail-static behavior.

---

## 4. Choosing the project (before the clock starts)

### 4.1 The selection matrix

Score each candidate project 1–5 per criterion, multiply by the weight, and pick the highest total *that you can defend at depth*. The weights reflect what the seven signals reward.

| Criterion | Weight | 5 looks like | 1 looks like |
|---|---|---|---|
| Ownership depth: you designed the core | 5 | You wrote the RFC and the core algorithm | You implemented tickets from someone else's design |
| Technical depth available | 4 | You can go 5 levels down on 2+ components | The interesting parts belonged to a vendor or another team |
| Scope: cross-team, multi-quarter | 4 | 3+ teams, a migration, an organizational change | One service, one team, one sprint |
| Ambiguity at the start | 3 | The problem was not yet defined; you defined it | The requirements arrived fully specified |
| A real failure story | 3 | A production incident you debugged and fixed systemically | Nothing ever broke (or you don't know) |
| Quantified outcomes | 3 | Measured before and after on 3+ metrics | "Everyone liked it" |
| Recency (≤ 3 years) | 2 | You remember the numbers and the code | 6+ years ago; the details are reconstructed |
| Explainable in ≤ 5 min of context | 2 | The domain is graspable from one sentence | It needs 15 minutes of domain teaching |
| Confidentiality risk (inverse) | 2 | Can be described with generic names | Its core is a trade secret, or it is classified |
| Fit to the role | 2 | The same class of problem as the target team's | Unrelated domain |

**Worked example (composite).** A candidate weighs three projects.

| Project | Own | Depth | Scope | Ambig | Fail | Quant | Recent | Explain | Conf | Fit | **Total /150** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Beacon config platform | 5 | 5 | 4 | 4 | 5 | 4 | 5 | 4 | 4 | 4 | **134** |
| Checkout service rewrite | 3 | 4 | 5 | 2 | 3 | 5 | 4 | 5 | 4 | 4 | **114** |
| Internal ML feature store | 4 | 4 | 3 | 5 | 2 | 2 | 3 | 2 | 3 | 5 | **101** |

The checkout rewrite had the bigger scope, but the candidate implemented a design led by someone else (ownership 3). Beacon wins on ownership and depth, which carry the most weight because they are what the round verifies. **Choose the project where you were the architect, even if a different project was bigger.**

### 4.2 Primary, backup, and the résumé surface

- **Prepare one primary and one backup.** Interviewers sometimes say "pick something else", "something with more scale", "something that failed", or "something where you led without authority". The backup should differ from the primary on the dimension they are most likely to ask about (often: a failure, or a different technical domain).
- **Every line on your résumé is fair game.** Prepare a 60-second headline (§7.2) for every project listed. An interviewer who picks the third bullet is testing whether the résumé is real.
- **Map your projects to the archetypes in Folder 03** (A: data migration and streaming, B: commerce or financial microservices, C: C++ low latency, D: embedded and safety-critical). An archetype gives you a pre-built set of the probes that class of system attracts.

### 4.3 Confidentiality without evasion

- **Generic names and rounded numbers are fine; say so once.** "I'll use generic names and round the numbers; the ratios are accurate."
- **Never share internal documents, screenshots or exact customer names.** Interviewers at large companies are trained to stop a candidate who is leaking (⚠ common practice); leaking is itself a negative signal about judgment.
- **Don't use confidentiality as an escape hatch for depth.** "I can't say how the dedup works" in a round about how the dedup works ends the round. Explain the *technique* generically ("a two-level bloom filter in front of an exact store") even when the parameters are secret.

### 4.4 Too old, too small, or too shared

- **Too old (5+ years):** usable if you can still reconstruct the numbers and decisions. Say what would differ today; that converts age into a hindsight signal.
- **Too small:** L7 needs cross-team scope somewhere. A small system with a large *organizational* footprint (a library adopted by 40 teams; a protocol other teams built on) qualifies. Frame the scope you really had.
- **Too shared:** if the project's design was a committee's, focus the hour on the slice you owned and draw the rest as ○. File 01.2 shows how. Don't inflate the ★ marks: the provenance probes (01.2 §3) will find them.

---

## 5. The whiteboard as a spatial contract

The board is a shared external memory. Lay it out so the interviewers can find anything you said earlier without asking, and so a third person walking in at minute 20 could understand the system from the board alone.

### 5.1 Board zones

```text
+---------------------------------------------------------------------------------+
| CONTEXT STRIP (top-left)          | ARCHITECTURE (center, ~60% of board)  | NUM |
| users -> pain -> constraints      |                                       | BER |
| G1..G5 goals                      |  write path: left -> right            | S   |
|-----------------------------------|  read path:  right -> left (below)    |     |
| OWNERSHIP LEGEND                  |  control plane above the line         | col |
| ★ designed/led  ◆ reviewed        |  data plane below the line            | umn |
| ○ team/other    ⚡ failure point   |                                       |     |
|-----------------------------------+---------------------------------------+-----|
| ZOOM AREA (bottom-left): deep-dive sub-diagram   | PARKING LOT (bottom-right)   |
| timeline of the failure story                    | questions deferred -> ticked |
+---------------------------------------------------------------------------------+
```

- **The context strip and the numbers column are permanent.** Never erase them. They let the scribe check consistency without asking.
- **The zoom area is scratch space.** Erase and reuse it for each deep dive.
- **The parking lot is a promise.** Every item written there must be ticked before minute 55 (§9.3).

### 5.2 Notation

| Element | Draw as | Always label with |
|---|---|---|
| Deployable service | Rectangle | Name, and ★/◆/○ |
| Datastore | Cylinder | Engine, and what it stores (truth? cache? log?) |
| Queue, log or stream | Rectangle with vertical stripes | Engine, partitions, retention if relevant |
| Synchronous call | Solid arrow | Protocol + rate ("gRPC, 4.8k QPS") |
| Asynchronous flow | Dashed arrow | Mechanism + lag ("watch, p99 24 s") |
| Trust or region boundary | Dotted box | Boundary name ("PCI zone", "eu-west") |
| Failure point discussed | ⚡ next to the element | Incident ID |

**Label every arrow with a rate or latency.** Unlabeled arrows invite the question "how much traffic is on that?", which you then answer from memory under pressure. A labeled arrow answers it before it's asked and shows the interviewer you think in quantities.

### 5.3 Draw order follows the data

1. Draw the **actor** (who causes the first event): for Beacon, an engineer changing a flag.
2. Follow the **write path** left to right: API → Postgres → validator → publisher → object store and relays.
3. Draw the **read path** back right to left, beneath it: relay → SDK → application code.
4. Add the **control loops** last (rollout controller, observability) because they connect to things already drawn.
5. **Mark ownership as you draw** ("this one is ★, I designed it"). Adding marks at the end looks like decoration; adding them during the walk-through reads as a factual statement.

Drawing in flow order lets the interviewer simulate the system as you speak. Drawing everything first and narrating afterwards (the "big reveal") forces them to parse a finished diagram with no guide.

### 5.4 Virtual whiteboards

- **Practice in the exact tool** the company uses (ask the recruiter: shared drawing tools such as Excalidraw, Miro or tldraw, a plain shared document, or the interview platform's built-in canvas). Learn the shortcuts for rectangle, arrow, text and duplicate. Fumbling with the tool costs 5–10 seconds per element, which across 25 elements is three minutes of the hour.
- **A pre-drawn diagram needs permission** (⚠ policies differ). Some interviewers welcome it in presentation formats. Others want to watch you build the model, because the order of drawing is itself evidence. Ask: "I have a rough diagram prepared, or I can draw it live. Which do you prefer?"
- **Mouse drawing:** use boxes and text, not freehand. Keep a legend box you can copy.
- **Make the text large.** Shared screens are often viewed at reduced zoom.

---

## 6. The zoom ladder: C4 levels as a pacing device

The [C4 model](https://c4model.com/) describes software at four levels: system **Context**, **Containers** (deployables and datastores), **Components** (the major parts inside one container) and **Code**. It works well as a pacing device because each level answers a different interviewer question:

| C4 level | Interviewer's question it answers | Beacon at this level | Phase |
|---|---|---|---|
| L1 Context | Why does this exist and for whom? | Engineers change config; 1,200 services consume it; ZooKeeper and YAML are being replaced | P2 |
| L2 Containers | What runs where, and what talks to what? | API, Postgres, publisher, object store, relays, SDK, rollout controller | P3 |
| L3 Components | How does your part work inside? | Publisher: snapshot builder, signer, size guard, announcer. SDK: watcher, verifier, swapper, LKG store | P4 |
| L4 Code / data | Exactly what happens? | Snapshot header layout; the atomic reference swap; the fsync ordering; the version comparison | P4–P5 |

**Three rules.**
1. **Signpost every zoom.** "I'm going to zoom into the SDK, because its fail-static semantics are the decision I'd most like you to challenge." The signpost tells them why you're spending their time there, and it shows that you chose the depth deliberately.
2. **Never skip two levels.** Jumping from containers to a byte layout loses the listener. Go L2 → L3 (the parts of the SDK) → L4 (the swap).
3. **Zoom back out after every deep answer.** "So at the container level, the consequence is that the relay can stay stateless." The return reconnects the detail to the whole and shows you know why the detail matters.

**The usual L5 failure is starting at L4.** "So we had this gRPC stream with a version field, and on each message the client…": the interviewer doesn't yet know what a client is, or why there's a stream. L7 candidates start at L1 and earn the right to descend.

---

## 7. Minute-by-minute playbook

Each phase lists its goal, what to draw, the speech skeleton, the checkpoint question, typical interrupts, and the exit criterion. Five phases include a paired L5/L7 telling. The L5 version is what interviewers often hear; the L7 version is what produces evidence.

### 7.1 00:00–02:00 · Intros

- **Goal:** spend no more than 30 seconds on yourself; agree on the project.
- **Say:** your current role in one sentence, the domain you work in, and the transition to the project. Do not narrate your résumé; they have read it.
- **Checkpoint:** "I'd suggest my config distribution platform, because it's where I made the core design decisions. Or is there something on my résumé you'd prefer?"
- **Why ask:** some interviewers have a project in mind (⚠ some are asked to probe a particular résumé line). Finding out at minute 1 beats finding out at minute 25.

### 7.2 02:00–04:00 · The headline (at most 90 seconds of speech)

The headline is the abstract of a paper. After it, the interviewers should know what you built, how big it was, why it mattered, what you personally did, and what is worth digging into. **The template:**

> [System] for [users] at [scale]. Before it, [pain, with a number]. I was [exact role]: I [designed X], [led Y], [wrote Z]. [Time] after launch, [metric] went from [before] to [after]. The two parts worth going deep on are [hook 1] and [hook 2].

#### How an L5 tells it

> So I worked on a config platform at my last company. It was basically a replacement for ZooKeeper, which was kind of a mess. We decided to build a push-based system and it was highly scalable and robust. It improved deployment speed a lot and the team was really happy with it. I was responsible for the backend part and also helped with the migration.

#### How an L7 tells it

> The project is Beacon, the configuration and feature-flag distribution platform for about 1,200 services and 48,000 instances across 3 regions. Before it, a flag change either took 55 minutes through a redeploy or hit every instance in every region within 2 seconds through ZooKeeper, and that second path caused 2 Sev-1 incidents in 12 months. I was the tech lead of a 6-engineer team: I wrote the RFC, designed the snapshot protocol, the SDK's fail-static semantics and the ring-based rollout controller, and I led the migration of 300 ZooKeeper-dependent services ahead of a hard data-center exit date. Twelve months after launch, p99 propagation was 24 seconds inside the target ring, 3 bad changes were halted in a 1% canary ring, and config pushes caused 0 Sev-1s. The two parts worth going deep on are the snapshot protocol and a failure we had in the last-known-good path.

**What makes the L7 version work.**
- **Scale has units** (services, instances, regions).
- **The pain is quantified,** and it has two sides (too slow *and* too fast). That previews the core tension.
- **The role is a list of artifacts** (RFC, protocol, semantics, controller, migration), each one probe-able.
- **The outcome restates the pain metric,** so before and after line up.
- **The hooks steer the deep dive** toward ground you have prepared.
- **The failure is volunteered.** Offering a failure in the headline is a strong maturity signal, and it saves you from having it extracted.

### 7.3 04:00–09:00 · Context (C4 L1)

- **Goal:** the interviewers understand who suffered, how badly, under what constraints, and what success meant, *before* they see any boxes.
- **Draw:** the context strip. Actors (engineers, services), the two legacy paths (YAML redeploy, ZooKeeper), the incident IDs, the deadline, G1–G5. Start the numbers column.
- **Speech skeleton:**
  1. Who uses it and how often.
  2. Before-state: path 1 and path 2.
  3. Three incidents in one line each.
  4. The forcing functions (deadline, compliance).
  5. The goals, with numbers.
  6. What was explicitly out of scope.
- **Checkpoint:** "Is the problem clear enough that I can show you the architecture?"
- **Typical interrupts:** "Why not just fix ZooKeeper?" (a preview of the "why not simpler" attack; answer in one sentence and park the full version for P6). "Who decided the deadline?" (01.3 covers how to frame it).

#### How an L5 tells it

> So the old system had a lot of problems. ZooKeeper was really old and kind of fragile, and the YAML stuff was slow. There were some big outages and leadership wanted it fixed. We had a deadline because the data center was going away. Basically the requirements were to make it fast, reliable and secure, and to use best practices for rollout.

#### How an L7 tells it

> Two paths existed. Static config lived in YAML inside each image, so a change meant a rebuild and redeploy, median 55 minutes. Dynamic flags lived in a single 5-node ZooKeeper ensemble in our us-east colo, read directly by about 300 services through 4 different client libraries. That second path had no notion of stages: a write reached every instance in every region in about 2 seconds. In the 12 months before the project it produced 3 incidents, which I'll call A1 to A3: a percentage typo that went global in 2 seconds, a session-expiry storm where 2 libraries fell back to defaults and 1 default disabled the API rate limiter, and a full disk that blocked a kill switch during an unrelated incident. Two dates bounded the work: the colo lease ended 9 months after approval, and an audit finding about open ACLs on the ensemble was due in month 6. I wrote the success criteria as 5 goals: a bad change touches at most 1% of instances for at most 5 minutes; p99 propagation within a ring of 30 seconds or less; a control-plane outage stops changes but never config reads; in-process reads under 1 microsecond; and every change attributable and reversible. Secrets and per-request experiment assignment were explicitly out of scope; they had their own systems.

**Why the explicit out-of-scope line matters.** It pre-empts "why didn't Beacon handle secrets?", and it shows you drew the system boundary on purpose. Scope is a design decision, and saying what you excluded is evidence of S1.

### 7.4 09:00–16:00 · Architecture (C4 L2)

- **Goal:** the full container diagram on the board, every arrow labeled, ownership marked, and the depth menu offered.
- **Draw (in order):** engineer → API (○) → Postgres (○) → validator (★/◆) → publisher (★) → object store (○) and relays (○/◆) → SDK (★) → application. Then the rollout controller (★) reading health metrics and driving the publisher's ring pointer. Then the break-glass lane (★) as a dashed bypass. Then the ZooKeeper bridge (★) as a temporary box with a dotted "M3–M8" label.
- **Speech skeleton:**
  1. One sentence per box: what it is, who owns it, and what invariant it holds.
  2. Write path, then read path.
  3. The single most important design idea in one line: "the publisher produces immutable, versioned, signed snapshots; everything downstream only moves pointers."
- **Checkpoint (the depth menu):** offer two or three areas and recommend one. This is the moment you shape the shared clock.

#### How an L5 tells it

> So here's the whole architecture. We had the API, the database, the publisher, the relays, the SDK and the rollout piece. We used gRPC for streaming and the SDK caches everything. I worked on most of these. Where do you want me to go deeper? I can talk about any of it.

#### How an L7 tells it

> Before you choose where to go deep, here is how the work divides. The API and Postgres belong to the platform team; I consumed them, and Postgres stays the source of truth. The 3 boxes with stars are mine: I designed the publisher and wrote its core, I designed the SDK semantics and wrote the Java reference SDK, and I designed the rollout controller and co-wrote it with one engineer. The relays are the team's; I reviewed their protocol. I'd suggest 3 possible deep dives. First, the snapshot protocol between publisher and SDK, which is where the key invariants live. Second, the rollout controller's gating, which has an interesting statistics problem with a 1% canary. Third, the ZooKeeper migration, where the shadow diff found 212 behavioral mismatches. My recommendation is the first, because that's where I'd most like my decisions challenged. Which would you prefer?

**Why "the depth menu with a recommendation" works.**
- **It is honest about ownership** before anyone asks.
- **It gives the interviewers a real choice,** which they value, and it doesn't hand them a blank check ("any of it") that invites them into the relay team's flow-control settings, below your floor.
- **Each option comes with a reason to care.**
- **The recommendation shows confidence.** The phrase "where I'd most like my decisions challenged" signals that you expect to survive the challenge.

### 7.5 16:00–28:00 · Deep dive 1 (C4 L3 → L4)

The deep-dive structure that interviewers find easiest to follow and hardest to fault:

1. **Invariants first.** "Three invariants: snapshots are immutable; versions per namespace only increase; a client never applies a snapshot it can't verify."
2. **Data structures.** The snapshot header (namespace, version, digest, created_at, signature, schema id) and the body (canonical serialized key-value map).
3. **Protocol steps.** Publish: build → canonicalize → hash → size check → sign → write blob → announce. Consume: watch → receive pointer → fetch → verify digest and signature → check version > applied → parse → atomic swap → write LKG → report the applied version.
4. **Failure cases for each step,** and the invariant that saves you in each case.
5. **Numbers.** Sizes, rates, latencies, and how each was measured.

**Prepared depth for Beacon (excerpt).**
- **Why rollback is a roll-forward.** Versions only increase, so a lagging relay or a replayed old pointer can't move clients backwards. A "rollback" publishes the old *content* under a *new* version. The design came out of security review: the reviewer pointed out that a decrementing rollback would let anyone who could replay an old signed pointer downgrade the fleet. That is provenance you can state (01.2 §3).
- **Why content-addressing.** The digest makes the blob fetch idempotent and cacheable at any layer. A relay never has to understand the content, so it can stay stateless.
- **Why the size cap lives at the publisher.** A consumer that discovers an oversized file at runtime has only bad options (the Cloudflare postmortem in §3.6 shows one). The publisher rejects anything over 4 MB, and the validator warns at 1 MB.
- **Why "parse with the consumer's parser".** The validator runs the SDK's own parsing code in a sandbox, so "valid per the schema but crashes the consumer" can't pass. That is the class of failure in CrowdStrike's findings (§3.6).
- **The atomic swap.** The parsed snapshot is an immutable map. Readers hold no lock: they dereference one atomic reference. The writer builds the whole new map and then swaps the reference. Readers in flight finish on the old map, which the garbage collector reclaims. Measured lookup p99: 180 ns.

### 7.6 28:00–38:00 · Deep dive 2: failure archaeology

Interviewers rate a well-told failure story highly, because it is the hardest evidence to fake: it requires knowing the detection signal, the timeline, and the fix. **The structure:**

1. **Detection signal:** what told you, and how fast.
2. **Bounding:** what was the blast radius, and how did you know it wasn't bigger?
3. **Mitigation:** what stopped the bleeding, and who did it.
4. **Root cause:** the actual mechanism, stated precisely.
5. **Fix:** the code-level change.
6. **Systemic change:** what makes the whole class of failure less likely (tests, alerts, policy).
7. **Your role in each step,** stated plainly, including the parts you got wrong.

#### How an L5 tells it

> We had one incident where some pods came up with the wrong config. It was kind of a weird edge case with the disk. The team fixed it pretty quickly and we added some tests. After that it was robust and we never had the issue again.

#### How an L7 tells it

> The failure I learned most from was INC-B7, a Sev-2 that lasted 6 minutes. A bad relay deploy had put the control plane in a brownout, and at the same time a node-pool upgrade restarted about 140 instances in our canary cell. Our dashboard showed the defaults-served signal jump from 0 to 0.3% of instances, and the on-call paged me within 2 minutes. The bound was clear from the applied-version reports: only restarted instances in ring0 were affected, because running instances keep their in-memory snapshot. Mitigation was rolling back the relay deploy, which took 6 minutes. The root cause was mine. I had written the LKG file in place without an fsync, so an instance stopped mid-write left a truncated file, the signature check rejected it, and with the relays unreachable the SDK fell back to compiled-in defaults. I changed the write to temp file, fsync, rename and directory fsync, kept 2 generations, and added a per-namespace on_missing policy so critical namespaces fail readiness instead of serving defaults. The systemic part was a CI chaos test that kills the process during an LKG write, plus an alert on defaults served above 0.

**What the L7 telling does that the L5 doesn't.**
- **It names the detection signal and the latency** (defaults-served metric, 2-minute page).
- **It explains the bound mechanistically:** running instances keep their in-memory snapshot.
- **It owns the root cause in the first person** ("the root cause was mine").
- **It gives the precise fix,** an ordering that an experienced interviewer will recognize as correct.
- **It includes a policy decision with a trade-off** (fail readiness vs serve defaults) that the interviewer can probe.
- **It never claims the problem "never happened again".** That claim is unfalsifiable, and an experienced interviewer will discount it.

### 7.7 38:00–44:00 · Trade-offs: the three options

Present the 2–3 real alternatives you considered for the central decision, each with the reason it lost. For Beacon, the distribution mechanism:

| Option | What it would have meant | Why it lost | What I kept from it |
|---|---|---|---|
| O1 Postgres + polling every 10 s | 48,000 pollers → 4,800 QPS of point reads on a replica set | Not throughput: one replica handled 12,000 QPS in a load test. It lost on *coupling* (a database brownout becomes a config brownout unless clients cache and keep LKG, at which point you have rebuilt half of Beacon anyway) and on *semantics* (no atomic multi-key snapshot, no ring pointer). | Postgres stays the source of truth |
| O2 Reuse the service mesh's xDS control plane | Config pushed over the mesh's existing streams | 18% of instances (batch jobs, legacy VMs) had no sidecar; config pushes would be tied to the mesh's release train and its blast radius | Relays authenticate with the mesh's workload identities |
| O3 Dedicated relay tier + immutable snapshots (chosen) | 27 stateless relays, blob fetch from regional object storage | Costs a new tier to operate; accepted because relays are stateless and content-addressed blobs are cacheable anywhere | — |

**The honest-throughput point is the most important line in this phase.** Saying "Postgres could have handled the load; that's not why we rejected it" disarms the "why not simpler" attack before it's made, and it signals that you don't invent scale to justify complexity. Folder 02 develops this framework in full; Folder 04 file 01 drills the attack.

### 7.8 44:00–49:00 · Impact and how you drove it

- **Three outcome numbers,** each paired with its before-number and its measurement source: propagation 55 min / uncontrolled → p99 24 s within ring; config Sev-1s 2 → 0 over 12 months; pages ~11 → ~2 per month.
- **Adoption mechanics:** how 300 ZooKeeper services and 410 static-config services moved (the shadow-mode gate, per-namespace cutover, the compatibility shim, office hours, a migration dashboard per team).
- **Organizational drive:** the RFC review (9 reviewers across 4 teams, 2 major revisions), the disagreement with the SRE lead about xDS and how you resolved it (a one-week prototype with explicit exit criteria), and how the payments team's change-approval requirement became a feature (per-namespace change policy). File 01.3 covers how to frame these.

### 7.9 49:00–52:00 · Hindsight

One or two changes, each with *why it wasn't knowable or wasn't affordable then*. For Beacon:
1. **"I would have made `on_missing` policy mandatory at namespace creation from day one."** It existed only after INC-B7. The cost of asking every namespace owner one question at creation is trivial, while the cost of discovering the policy gap in production was a Sev-2.
2. **"If mesh coverage had been above 95%, I'd have pushed harder on the xDS option."** In month 0 it was 82%; it reached 97% by month 14. The relay tier is now a cost we might not have needed. The decision was right on the information available, and I would revisit it now.

File [02.3](../02-The-3-Viable-Options-Tradeoff-Defense-Framework/03-answering-what-would-you-redesign-today-with-hindsight.md) treats hindsight in depth.

### 7.10 52:00–60:00 · Their questions, then yours

- **Leave this time open.** It's where interviewers fill the gaps in their notes. If they have nothing left, they'll hand the time to you.
- **Your questions should show technical curiosity about their systems,** not benefits: "How does your team handle config or content propagation safety? Do you stage it the way you stage code?"; "What's the hardest operational problem your team owns right now?"
- **Never use this time to restate your achievements.** Thank them and stop.

---

## 8. The scripted plans and the pacing check

Writing your plan as a script, then timing it, is the fastest way to find out that your "5-minute" context section takes 11 minutes. The notation:

| Line | Meaning | Time cost in `pace_check.py` |
|---|---|---|
| `== mm:ss-mm:ss \| Title` | A section and its time window | Budget = end − start |
| `SAY:` | Words you will speak (continuation lines allowed) | words ÷ wpm |
| `DRAW:` | One pen action not covered by speech | `--draw-sec` (default 8 s) |
| `ASK:` | A checkpoint question | words ÷ wpm + `--reply-sec` (default 15 s); resets the monologue counter |
| `RESERVE:` | Seconds held for interviewer-driven questions | as written; resets the monologue counter |

**Measure your own speaking rate.** Record one rehearsal, count the words in the transcript, and divide by the minutes. The default of 130 wpm is only a planning assumption. Pass your measured rate with `--wpm`.

### 8.1 Plan A: the context dump (what an L5 plan often looks like)

```script
# plan: A - context dump (L5)
== 00:00-02:00 | Intros
SAY: Hi, thanks for having me. So I started my career at a services company where I did a lot of Java
work on banking projects, then I moved into a product company, and there I was on the platform team for
about four years. Before that I was also on a data team for a while, which was where I first learned about
Kafka and streaming. On the platform team we owned a lot of things, like the deployment tooling and the
service templates and the config systems, and that's what I want to talk about today. I was one of the
senior engineers on the team, and I worked on many of the projects the team did over those years, some of
which I'll mention as we go along.
== 02:00-04:00 | Headline
SAY: So the project I want to talk about is our config platform. It was basically a replacement for the
ZooKeeper-based flag system and also the static YAML files that every service had. It was a really big
project and it touched almost every team in the company, so there was a lot of coordination involved.
We built a new service with an API and a database and a publishing component and a streaming layer, and
an SDK that services used to read the config. There was also a rollout system that controlled how changes
went out. The project went really well and the system has been very reliable since we launched it. It also
made engineers a lot happier because they could change things without deploying. I was responsible for a
lot of the backend and I helped with the migration too. The migration was a big part of the work, because
every team had to move over, and some teams were faster than others, so there was a long tail at the end
where we had to chase people. We also had to keep the old system running for a while during that time, and
there were some issues with that as well, which I can talk about later if there's time.
== 04:00-14:00 | Context and history
SAY: To understand why we did this you need some history. The company grew really quickly and the platform
team was always behind. ZooKeeper had been set up a long time ago by people who had since left, and nobody
really understood it any more. The client libraries were all different because each team wrote their own
when they needed one. The YAML files were in every repo and they all had slightly different formats, so it
was hard to know what config a service was actually running with. We also had a lot of outages related to
config. One of them was when someone made a typo in a flag and it went everywhere, which was really bad
because it took down part of checkout. Another one was when ZooKeeper had problems and the clients did
strange things. Leadership was frustrated, and there was a lot of pressure from the product teams too,
because they wanted to move faster and the config system was slowing them down. There were also security
concerns that came up in an audit, and the data center that ZooKeeper ran in was being shut down, so there
was a deadline as well. All of these things together meant that we had to do something, and the
architecture team asked us to come up with a proposal. We looked at a few options and spent a long time
discussing them with other teams, and eventually we came up with the design that I'll show you next. There
was a lot of back and forth with the SRE team in particular, because they had their own ideas about how it
should work, and with the payments team, who had special requirements because of compliance.
DRAW: box for ZooKeeper
DRAW: box for YAML
== 14:00-30:00 | Architecture tour
DRAW: API box
DRAW: database
DRAW: publisher
DRAW: relays
DRAW: SDK
DRAW: rollout controller
SAY: So this is the architecture. Engineers use the API, it stores changes in the database, the publisher
builds the config and sends it out through the relays, and the SDK in each service gets it. The rollout
controller decides where the change goes first. Each of these pieces has a lot of detail, so let me go
through them one by one, starting with the API.
RESERVE: 600
== 30:00-50:00 | Deep dive
RESERVE: 900
== 50:00-55:00 | Wrap up
SAY: So overall the project was a big success and I learned a lot about leading a large migration.
RESERVE: 120
```

### 8.2 Plan B: the layered plan for Beacon (L7)

```script
# plan: B - layered (L7)
== 00:00-02:00 | Intros
SAY: Thanks. I'm a staff engineer on a platform team; for the last three years my work has been
configuration, deployment safety and the service runtime.
ASK: I'd suggest my config distribution platform, because it's where I made the core design decisions.
Or is there something on my resume you'd prefer?
RESERVE: 60
== 02:00-04:00 | Headline
DRAW: title "Beacon: config + flag distribution" and my role line
SAY: The project is Beacon, the configuration and feature-flag distribution platform for about 1,200
services and 48,000 instances across 3 regions. Before it, a flag change either took 55 minutes through
a redeploy or hit every instance in every region within 2 seconds through ZooKeeper, and that second path
caused 2 Sev-1 incidents in 12 months. I was the tech lead of a 6-engineer team: I wrote the RFC, designed
the snapshot protocol, the SDK's fail-static semantics and the ring-based rollout controller, and I led the
migration of 300 ZooKeeper-dependent services ahead of a hard data-center exit date. Twelve months after
launch, p99 propagation was 24 seconds inside the target ring, 3 bad changes were halted in a 1% canary
ring, and config pushes caused 0 Sev-1s. The two parts worth going deep on are the snapshot protocol and a
failure we had in the last-known-good path.
ASK: Does that work as the project, or would you prefer something else?
== 04:00-09:00 | Context (C4 L1)
DRAW: context strip - engineers, 1,200 services, two legacy paths
DRAW: numbers column - 48,000 instances, 3 regions, 55 min, 2 s
SAY: Two paths existed. Static config lived in YAML inside each image, so a change meant a rebuild and
redeploy, median 55 minutes. Dynamic flags lived in a single 5-node ZooKeeper ensemble in our us-east colo,
read directly by about 300 services through 4 different client libraries. That second path had no notion
of stages: a write reached every instance in every region in about 2 seconds.
DRAW: incident list A1, A2, A3
SAY: In the 12 months before the project it produced 3 incidents. A1: a rollout percentage typed as 100
instead of 10 went global in 2 seconds and saturated the recommendation backend, 38 minutes of Sev-1. A2: a
leader election during a network flap caused a session-expiry storm; 2 of the 4 libraries fell back to
compiled-in defaults, and 1 of those defaults disabled the public API rate limiter, 52 minutes of Sev-1. A3:
the ensemble's disk filled up, writes were rejected, and during an unrelated incident nobody could flip a
kill switch.
DRAW: deadline and audit dates
SAY: Two dates bounded the work. The colo lease ended 9 months after approval, and an audit finding about
open ACLs and missing client authentication was due in month 6.
DRAW: goals G1 to G5
SAY: I wrote the success criteria as 5 goals. G1: a bad change touches at most 1% of instances for at most
5 minutes. G2: p99 propagation within a ring of 30 seconds or less. G3: a control-plane outage stops changes
but never config reads. G4: in-process reads under 1 microsecond. G5: every change attributable and
reversible. Secrets and per-request experiment assignment were out of scope; they had their own systems.
ASK: Is the problem clear enough that I can show you the architecture?
== 09:00-16:00 | Architecture (C4 L2)
DRAW: engineer and API box (team)
DRAW: Postgres cylinder - source of truth, append-only change log
SAY: The write path starts with the config API and Postgres, which belong to the platform team. Postgres
holds the append-only change log and is the source of truth; nothing downstream is authoritative.
DRAW: validator box, star on the contract
DRAW: publisher box, star
SAY: Every change goes through the validator. The contract I wrote has one unusual rule: the validator
parses the candidate config with the same parser the SDK uses, in a sandbox, so a config that is valid by
schema but crashes the consumer cannot pass. Then the publisher, which I designed and wrote the core of,
turns the namespace into an immutable snapshot: canonical serialization, a SHA-256 digest, a version
number that only increases per namespace, an Ed25519 signature from KMS, and a hard 4 megabyte cap.
DRAW: regional object store cylinders x3
DRAW: relay boxes x3 per region, labeled 27 relays, about 1,800 streams each
SAY: The publisher writes the blob to object storage in each region and announces namespace, version and
digest to the relays. The relays are the team's work; I reviewed their protocol. They are stateless: a
client opens one stream, says which version it has, and the relay answers with the newest pointer.
DRAW: SDK box inside an application instance, star
SAY: The SDK is mine in design and in the Java reference implementation; the language-platform teams
ported it to Go, Python and Node. It fetches the blob, checks the digest and signature, refuses any version lower than the one it
has applied, swaps one atomic reference so reads never take a lock, writes a last-known-good copy to disk,
and reports the applied version back.
ASK: Any questions on the data path before I add the control loop?
DRAW: rollout controller box, star, arrows from metrics and to the ring pointer
DRAW: break-glass dashed path, star on the policy
DRAW: ZooKeeper bridge box, dotted, labeled months 3 to 8
SAY: The rollout controller, which I designed and co-wrote with one engineer, owns the ring pointer. A
change goes to ring0, one canary cell of about 1% of instances, bakes 5 minutes, then to all of us-west
for 15 minutes, then everywhere, and it advances only if the canary's error ratio and p99 latency stay
within bounds compared with the baseline. Kill switches have a break-glass lane that skips the bake times
but needs 2 approvers and pages the on-call. The dotted box is the ZooKeeper bridge I led for the
migration; it existed from month 3 to month 8.
ASK: I'd suggest 3 possible deep dives: the snapshot protocol, the rollout gating statistics, or the
ZooKeeper migration. My recommendation is the protocol, because that's where I'd most like my decisions
challenged. Which would you prefer?
== 16:00-28:00 | Deep dive 1: snapshot protocol (C4 L3/L4)
DRAW: zoom area - publisher components: builder, canonicalizer, hasher, size guard, signer, announcer
SAY: Three invariants drive everything. Snapshots are immutable. Versions per namespace only increase.
A client never applies a snapshot it cannot verify. Each component exists to protect one of them.
SAY: The header carries namespace, version, digest, schema id, creation time and signature; the body is a
canonical map, sorted keys, so the same content always has the same digest. Content addressing makes the
fetch idempotent and cacheable anywhere, which is why the relay can stay ignorant of content.
ASK: Do you want the publish side or the consume side first?
DRAW: zoom area - SDK components: watcher, fetcher, verifier, version gate, swapper, LKG writer
SAY: On the consume side the order matters: verify digest, verify signature, check that the version is
greater than the applied one, parse, swap, then persist the last-known-good copy. Rollback is a roll
forward: the old content republished under a new, higher version. I first designed rollback as a version
decrement, and the security reviewer pointed out that anyone able to replay an old signed pointer could
then downgrade the fleet. Monotonic versions close that, and they also make a lagging relay harmless.
SAY: The read path is one atomic reference to an immutable map. Readers take no lock; the writer builds the
whole new map before the swap; in-flight reads finish on the old map. Measured lookup p99 is 180
nanoseconds.
RESERVE: 330
ASK: Shall I cover the size cap and the validator rule, or move to the failure we had?
== 28:00-38:00 | Deep dive 2: failure INC-B7
DRAW: failure timeline - brownout, restarts, defaults served, relay rollback
SAY: The failure I learned most from was INC-B7, a Sev-2 that lasted 6 minutes. A bad relay deploy had put
the control plane in a brownout, and at the same time a node-pool upgrade restarted about 140 instances in
our canary cell. The defaults-served signal jumped from 0 to 0.3% of instances and the on-call paged me
within 2 minutes. The bound was clear from the applied-version reports: only restarted instances in ring0,
because running instances keep their in-memory snapshot.
DRAW: lightning mark on the LKG writer
SAY: The root cause was mine. I had written the last-known-good file in place without an fsync, so an
instance stopped mid-write left a truncated file; the signature check rejected it, and with the relays
unreachable the SDK fell back to compiled-in defaults. I changed the write to temp file, fsync, rename and
directory fsync, kept 2 generations, and added a per-namespace on_missing policy so critical namespaces fail
readiness instead of serving defaults. The systemic part was a CI chaos test that kills the process during
the write, and an alert on defaults served above zero.
RESERVE: 330
ASK: Do you want to go further into the readiness policy trade-off, or move to the alternatives?
== 38:00-44:00 | Trade-offs: three options
DRAW: options table O1, O2, O3
SAY: For distribution I compared 3 options. Option 1 was Postgres plus polling every 10 seconds: 48,000
pollers is 4,800 queries per second, and one replica handled 12,000 in a load test, so throughput was not
the reason it lost. It lost on coupling and semantics: a database brownout becomes a config brownout unless
every client caches and keeps a last-known-good copy, and then I have rebuilt half of Beacon; and polling
rows gives no atomic multi-key snapshot and no ring pointer. Option 2 was reusing the service mesh's xDS
control plane. The SRE lead favored it; I prototyped it for a week with exit criteria we agreed on, and it
failed 2 of them: 18% of instances had no sidecar, and config pushes would ride the mesh's release train and
blast radius. Option 3, the relay tier with immutable snapshots, costs a new tier to operate, which I
accepted because the relays are stateless. From option 2 I kept the mesh's workload identities for relay
authentication.
RESERVE: 100
ASK: Want me to go deeper on any of the three?
== 44:00-49:00 | Impact and how I drove it
DRAW: results in numbers column
SAY: Three numbers, each from a source I can name. Propagation went from 55 minutes for static config, and
uncontrolled for ZooKeeper, to p99 24 seconds inside the target ring, from the SDK's applied-version
reports. Config-caused Sev-1s went from 2 in the prior 12 months to 0 in the 12 months after, from the
incident tracker. Config-infrastructure pages went from about 11 a month to about 2. Adoption: 300 ZooKeeper
services and 410 static-config services moved by month 12, through a shadow-mode gate, per-namespace
cutover and a migration dashboard per team. The RFC went through 9 reviewers in 4 teams and 2 major
revisions; the payments team's approval requirement became a per-namespace change policy instead of an
exception.
RESERVE: 75
ASK: Is there an area either of you wants more on?
== 49:00-52:00 | Hindsight
SAY: Two things I'd change. I'd make the on_missing policy a required field at namespace creation from day
one; asking one question per namespace is trivial next to finding the gap through a Sev-2. And if service
mesh coverage had been above 95%, I'd have pushed the xDS option harder. In month 0 it was 82 percent, by
month 14 it was 97, so the relay tier is now a cost we might not need. The decision was right on the
information we had, and I would revisit it today.
RESERVE: 40
ASK: That's the project. What else would be useful for you?
== 52:00-60:00 | Their questions, then mine
RESERVE: 360
ASK: How does your team stage config and content changes, compared with code?
ASK: What is the hardest operational problem your team owns right now?
```

### 8.3 Listing L1: `pace_check.py`

<!-- listing:pace_check.py -->
```python
#!/usr/bin/env python3
"""pace_check.py - time-budget a 60-minute deep-dive whiteboard script.

Reads every ```script fenced block in a Markdown file and estimates how long
each section takes to deliver, then flags the pacing failures that sink the
round: over-budget sections, monologues with no checkpoint, a context section
with no numbers, a headline that runs past 90 seconds, more than 7 minutes
budgeted for context/history, a first deep dive that starts after 20:00, and
timeline gaps.

Script format (one plan per fence):
    # plan: <name>
    == 05:00-10:00 | Context (C4 L1)
    SAY: words you will actually speak (continuation lines allowed)
    DRAW: one pen action you take while not speaking (box, arrow, label)
    ASK: a checkpoint question to the interviewers (+ reply allowance)
    RESERVE: 120  seconds held back for interviewer-driven questions

Usage: python -I pace_check.py <file.md> [--wpm 130] [--draw-sec 8]
       [--reply-sec 15] [--max-monologue 300] [--total 60:00]
Standard library only. Exit code 0 always; the verdict is in the output.
"""
import argparse
import re
import sys


def mmss(text):
    m, s = text.split(":")
    return int(m) * 60 + int(s)


def fmt(sec):
    sec = int(round(sec))
    return f"{sec // 60:02d}:{sec % 60:02d}"


def words(text):
    return len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'%./-]*", text))


def parse_plans(md):
    plans = []
    for block in re.findall(r"^```script\n(.*?)^```", md, re.S | re.M):
        plan = {"name": "unnamed", "sections": []}
        last = None
        for raw in block.splitlines():
            line = raw.rstrip()
            if not line.strip():
                continue
            if line.startswith("# plan:"):
                plan["name"] = line.split(":", 1)[1].strip()
                continue
            m = re.match(r"==\s*(\d+:\d\d)\s*-\s*(\d+:\d\d)\s*\|\s*(.+)", line)
            if m:
                sec = {"start": mmss(m.group(1)), "end": mmss(m.group(2)),
                       "title": m.group(3).strip(), "say": [], "draw": 0,
                       "ask": [], "reserve": 0, "events": []}
                plan["sections"].append(sec)
                last = None
                continue
            if not plan["sections"]:
                continue
            sec = plan["sections"][-1]
            m = re.match(r"(SAY|DRAW|ASK|RESERVE):\s*(.*)", line)
            if m:
                kind, body = m.groups()
                if kind == "SAY":
                    sec["say"].append(body)
                    sec["events"].append(("SAY", body))
                elif kind == "DRAW":
                    sec["draw"] += 1
                    sec["events"].append(("DRAW", body))
                elif kind == "ASK":
                    sec["ask"].append(body)
                    sec["events"].append(("ASK", body))
                else:
                    sec["reserve"] += int(re.match(r"\d+", body).group(0))
                    sec["events"].append(("RESERVE", body))
                last = kind
            elif last in ("SAY", "ASK"):
                target = sec["say"] if last == "SAY" else sec["ask"]
                target[-1] += " " + line.strip()
                kind, body = sec["events"][-1]
                sec["events"][-1] = (kind, body + " " + line.strip())
        plans.append(plan)
    return plans


def analyse(plan, a):
    flags = []
    rows = []
    spw = 60.0 / a.wpm
    run = 0.0          # spoken seconds since the last checkpoint
    worst = (0.0, "")
    prev_end = 0
    context_budget = 0
    first_deep = None
    for sec in plan["sections"]:
        say_w = sum(words(s) for s in sec["say"])
        ask_w = sum(words(s) for s in sec["ask"])
        est = (say_w + ask_w) * spw + sec["draw"] * a.draw_sec \
            + len(sec["ask"]) * a.reply_sec + sec["reserve"]
        budget = sec["end"] - sec["start"]
        status = "ok"
        if est > budget * 1.10:
            status = "OVER"
            flags.append(f"OVER: '{sec['title']}' needs {fmt(est)} of a {fmt(budget)} budget")
        elif est < budget * 0.50:
            status = "thin"
        if sec["start"] != prev_end:
            flags.append(f"TIMELINE: '{sec['title']}' starts at {fmt(sec['start'])}, previous section ended {fmt(prev_end)}")
        prev_end = sec["end"]
        title = sec["title"].lower()
        if re.search(r"context|history|background", title):
            context_budget += budget
        if "deep" in title and first_deep is None:
            first_deep = sec
        if "context" in title:
            nums = sum(len(re.findall(r"\d[\d,.]*", s)) for s in sec["say"])
            if nums < 3:
                flags.append(f"NUMBERS: '{sec['title']}' states {nums} numbers; the context layer needs at least 3 (scale, SLO, deadline)")
        if "headline" in title:
            say_sec = say_w * spw
            if say_sec > 90:
                flags.append(f"LONG-HEADLINE: headline speech is {fmt(say_sec)}; keep it under 01:30")
        for kind, body in sec["events"]:
            if kind == "SAY":
                run += words(body) * spw
                if run > worst[0]:
                    worst = (run, sec["title"])
            elif kind in ("ASK", "RESERVE"):
                run = 0.0
        rows.append((sec, budget, est, say_w, status))
    if context_budget > 7 * 60:
        flags.append(f"CONTEXT-HEAVY: {fmt(context_budget)} budgeted for context/history; keep it at or under 07:00")
    if first_deep is None:
        flags.append("LATE-DEPTH: no deep-dive section in the plan")
    elif first_deep["start"] > 20 * 60:
        flags.append(f"LATE-DEPTH: first deep dive starts at {fmt(first_deep['start'])}; aim for 16:00-18:00, never after 20:00")
    if worst[0] > a.max_monologue:
        flags.append(f"MONOLOGUE: {fmt(worst[0])} of uninterrupted speech ending in '{worst[1]}' (limit {fmt(a.max_monologue)}); add an ASK checkpoint")
    total = mmss(a.total)
    if prev_end != total:
        flags.append(f"TIMELINE: plan ends at {fmt(prev_end)}, the round is {fmt(total)}")
    return rows, flags, worst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("md")
    ap.add_argument("--wpm", type=float, default=130.0)
    ap.add_argument("--draw-sec", type=float, default=8.0)
    ap.add_argument("--reply-sec", type=float, default=15.0)
    ap.add_argument("--max-monologue", type=float, default=300.0)
    ap.add_argument("--total", default="60:00")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    md = open(a.md, encoding="utf-8").read().replace("\r\n", "\n")
    plans = parse_plans(md)
    print(f"pace_check: {len(plans)} plan(s); wpm={a.wpm:g} draw={a.draw_sec:g}s "
          f"reply={a.reply_sec:g}s monologue-limit={fmt(a.max_monologue)}")
    for plan in plans:
        rows, flags, worst = analyse(plan, a)
        print()
        print(f"plan: {plan['name']}")
        print(f"  {'window':<13} {'section':<38} {'budget':>6} {'est':>6} {'words':>5} {'draw':>4} {'ask':>3}  status")
        for sec, budget, est, say_w, status in rows:
            window = f"{fmt(sec['start'])}-{fmt(sec['end'])}"
            print(f"  {window:<13} {sec['title'][:38]:<38} {fmt(budget):>6} {fmt(est):>6} "
                  f"{say_w:>5} {sec['draw']:>4} {len(sec['ask']):>3}  {status}")
        print(f"  longest monologue: {fmt(worst[0])} (ends in '{worst[1]}')")
        if flags:
            print(f"  verdict: {len(flags)} flag(s)")
            for f in flags:
                print(f"    - {f}")
        else:
            print("  verdict: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 8.4 Output on the two plans above

<!-- output:pace_check.py -->
```text
pace_check: 2 plan(s); wpm=130 draw=8s reply=15s monologue-limit=05:00

plan: A - context dump (L5)
  window        section                                budget    est words draw ask  status
  00:00-02:00   Intros                                  02:00  01:00   130    0   0  ok
  02:00-04:00   Headline                                02:00  01:38   213    0   0  ok
  04:00-14:00   Context and history                     10:00  02:28   287    2   0  thin
  14:00-30:00   Architecture tour                       16:00  11:18    66    6   0  ok
  30:00-50:00   Deep dive                               20:00  15:00     0    0   0  ok
  50:00-55:00   Wrap up                                 05:00  02:08    18    0   0  thin
  longest monologue: 05:21 (ends in 'Architecture tour')
  verdict: 6 flag(s)
    - LONG-HEADLINE: headline speech is 01:38; keep it under 01:30
    - NUMBERS: 'Context and history' states 0 numbers; the context layer needs at least 3 (scale, SLO, deadline)
    - CONTEXT-HEAVY: 10:00 budgeted for context/history; keep it at or under 07:00
    - LATE-DEPTH: first deep dive starts at 30:00; aim for 16:00-18:00, never after 20:00
    - MONOLOGUE: 05:21 of uninterrupted speech ending in 'Architecture tour' (limit 05:00); add an ASK checkpoint
    - TIMELINE: plan ends at 55:00, the round is 60:00

plan: B - layered (L7)
  window        section                                budget    est words draw ask  status
  00:00-02:00   Intros                                  02:00  01:38    25    0   1  ok
  02:00-04:00   Headline                                02:00  01:37   148    1   1  ok
  04:00-09:00   Context (C4 L1)                         05:00  02:59   257    5   1  ok
  09:00-16:00   Architecture (C4 L2)                    07:00  04:44   331   10   2  ok
  16:00-28:00   Deep dive 1: snapshot protocol (C4 L3/  12:00  08:00   197    2   2  ok
  28:00-38:00   Deep dive 2: failure INC-B7             10:00  07:30   176    2   1  ok
  38:00-44:00   Trade-offs: three options               06:00  03:26   169    1   1  ok
  44:00-49:00   Impact and how I drove it               05:00  02:37   117    1   1  ok
  49:00-52:00   Hindsight                               03:00  01:41    90    0   1  ok
  52:00-60:00   Their questions, then mine              08:00  06:41     0    0   2  ok
  longest monologue: 01:59 (ends in 'Context (C4 L1)')
  verdict: PASS
```

**Reading the output.**
- **Plan A is flagged six times.** Each flag is a real failure mode:
  - the headline runs past 90 s;
  - the context section states no numbers at all;
  - 10 minutes are budgeted for context and history;
  - the first deep dive starts at minute 30, so the most valuable evidence is gathered in the least time;
  - more than 5 minutes go by with no checkpoint (the interviewers will cut in, and take the hour with them);
  - the plan ends at 55:00, with no time left for the interviewers.
  Notice what the tool does *not* say: Plan A's context section isn't over its own budget. The candidate gave it 10 minutes on purpose. Pacing failures are usually planning failures, which is why you write the plan down and check it.
- **Plan B passes.** Note where its time goes: about 22 minutes of the hour are explicitly `RESERVE` for interviewer-driven questions, in the sections where interviewers take over anyway. A plan with zero reserve is a lecture, and lectures get interrupted.

---

## 9. Interrupt handling: keeping the spine while they steer

### 9.1 Interrupt taxonomy

| Type | Sounds like | What it signals | Response pattern | Time limit | Return move |
|---|---|---|---|---|---|
| **Clarify** | "What's a namespace here?" | They lost the map | One-sentence definition; add it to the board | 15 s | Continue mid-sentence |
| **Challenge** | "Why not just use Postgres?" | Testing judgment or overengineering | Answer first, give one reason with a number, offer depth | 60 s | "I'll show the full comparison in the trade-offs section" (park it) |
| **Redirect** | "Skip ahead to the failure" | They value their time differently than your plan | Accept immediately; use the 50% version | — | Re-budget (§10) |
| **Depth probe** | "What exactly happens on fsync failure?" | Searching for the floor | Go down one level; signpost; declare the floor if you reach it | 2–4 min | Zoom back out (§6) |
| **Breadth probe** | "What other teams depended on this?" | Testing scope (S1) | List, with numbers | 45 s | Continue |
| **Consistency check** | "So how many streams per relay?" | Verifying a number stated earlier | Derive it aloud from the numbers column | 30 s | Continue |
| **Hypothetical** | "What if you had 10× namespaces?" | Testing whether you understand *why* the design works | Name the first thing that breaks, and why | 2 min | Tie back to the actual design |
| **Silence** | (they stop talking, keep writing) | Capturing a quote, or waiting to see whether you fill the gap | Stop. Let them write. Then: "Shall I go on?" | — | — |

### 9.2 Answer first, then evidence, then anchor

Under challenge, the most common mistake is building up to the answer ("Well, to understand that you have to know that in 2021..."). Interviewers take the build-up as evasion. **The pattern:**
1. **Answer** in one sentence.
2. **Evidence:** one reason, with a number.
3. **Anchor:** offer more depth or return to the plan.

#### How an L5 tells it

> Well, that's a good question. There were a lot of factors. Basically Postgres could work but we wanted something more scalable and robust, and the team felt that a streaming approach was best practice for this kind of system, so we decided to go with relays.

#### How an L7 tells it

> Short answer: Postgres polling would have handled the load, and that is not why I rejected it. 48,000 instances polling every 10 seconds is 4,800 queries per second, and one replica took 12,000 in our load test. It lost on 2 properties: a database brownout would become a config brownout unless every client kept a last-known-good copy, and polling rows gives no atomic multi-key snapshot to stage through rings. I can go through the full comparison now, or when I reach the trade-offs section in a few minutes. Which do you prefer?

### 9.3 The parking lot

When a question would derail the phase you're in, write it in the parking lot (bottom-right), say "I'll come back to that in the failure section", and *come back to it* by name: "You asked earlier about fsync failures; here's where that connects." Returning to a parked question unprompted shows control of the conversation (S7) that few candidates show. An item left un-ticked is a broken promise the scribe will note.

### 9.4 When they take the hour completely

Some interviewers drive the whole round as rapid questions (⚠ a common style for "skeptic" interviewers). Don't fight it. Your plan turns into a **checklist of evidence still unsurfaced**: the ownership statement, one deep mechanism, one failure, one trade-off with a rejected option, one number derivation, one hindsight item. Weave the missing items into answers: "Before we leave this, one thing worth knowing: the root cause of our worst post-launch failure was in this exact component, and it was mine." That turns their question into the opening for your failure story.

---

## 10. Re-budgeting when you fall behind: the cut order

At each checkpoint (16:00, 28:00, 44:00), compare where you are with where the plan says you should be, and compress the remaining phases in cut-priority order (§2's last column). Prepare each phase in three sizes:

| Phase | 100% (planned) | 50% | One sentence (≈ 20–30 s) |
|---|---|---|---|
| P2 Context | 5 min: both paths, 3 incidents, 2 dates, 5 goals | 2.5 min: the two paths, A1 only, both dates, G1 + G3 | "Flags went global in 2 s through ZooKeeper, causing 2 Sev-1s in a year, and the ensemble's data center was closing in 9 months." |
| P3 Architecture | 7 min, full diagram | 3.5 min: write path + SDK only, skip the controller and bridge | "Postgres is truth; my publisher makes signed, versioned, immutable snapshots; stateless relays announce pointers; my SDK verifies and swaps atomically." |
| P5 Failure | 10 min with probes | 4 min: detection, root cause, fix | "A truncated last-known-good file, my bug, caused 0.3% of a canary cell to serve defaults for 6 minutes; the fix was temp-fsync-rename plus a fail-readiness policy." |
| P6 Trade-offs | 6 min, three options | 2 min: O1 only, with the honest-throughput point | "Postgres polling would have carried the load; it lost on coupling and on the lack of atomic snapshots." |
| P7 Impact | 5 min | 1.5 min: three numbers | "p99 24 s within ring, 0 config Sev-1s in 12 months against 2 before, pages from 11 to 2 a month." |
| P8 Hindsight | 3 min, two items | 1 min, one item | "I'd make the on_missing policy mandatory at namespace creation." |

**Never cut to zero:** the ownership statement, one deep dive, one failure (at least its one-sentence version), one hindsight item. Those four give a committee most of the evidence it needs to place a level. Everything else is compressible.

**The 10-minute detour.** If the interviewers spend 10 unplanned minutes in one place, that is usually good news: they found something worth probing. Recalculate from where you are. Count the remaining minutes, subtract 6 for P9's buffer, and fit the remaining phases in their compressed sizes, in priority order.

---

## 11. Depth reserves: prepare three wells

A **well** is a component you can descend into for 15 minutes without reaching your floor. Prepare three, one per hook you offer in the depth menu. Each well has five levels:

| Level | Question it answers | Well 1: snapshot protocol | Well 2: rollout gating | Well 3: ZooKeeper migration |
|---|---|---|---|---|
| 1 What | What is it? | Immutable, versioned, signed snapshots | Ring pointer advanced by health gates | Dual-read shadow, then per-namespace cutover |
| 2 How | How does it work? | Build → canonicalize → hash → cap → sign → blob → announce; verify → version gate → swap → LKG | Bake ring0 5 min, ring1 15 min; compare canary with baseline on error ratio and p99 | SDK reads both systems; compat shim maps legacy semantics; mismatch metrics per key |
| 3 Why | Why this, and not that? | Monotonic versions for replay defense; content addressing for stateless relays | Health-gated rings, because a static schedule can't stop a bad change; comparison with the baseline, because absolute thresholds false-alarm during traffic swings | Shadow mode, because Hyrum's law: consumers depended on quirks (empty znode = false, missing znode = true) |
| 4 What breaks | Edge cases and failures | Truncated LKG (INC-B7); clock skew in `created_at` (not used for ordering); a KMS outage (the publisher halts, clients keep LKG) | A 1% canary is ~480 instances: low-traffic namespaces give too few requests for a meaningful error ratio, so a minimum request count gates the decision and "insufficient signal" holds the ring | Mismatch noise from intentionally changed keys; a flapping namespace during cutover; a library that cached znodes forever |
| 5 Numbers | How much, measured how? | 18 KB median, 4 MB cap, 180 ns lookup p99, p99 24 s propagation | 3 auto-halts in 12 months; worst 1.1% for 4 min; ~4% of changes held for insufficient signal | 212 mismatches in 37 services; 300 services in 5 months; 0 rollbacks after cutover |

**Hyrum's law**, "with a sufficient number of users of an API, it does not matter what you promise in the contract: all observable behaviors of your system will be depended on by somebody" ([hyrumslaw.com](https://www.hyrumslaw.com/)), is the first-principles reason Well 3 needed a shadow mode at all. Stating the principle and then the specific quirk (empty znode treated as `false`) is the shape of an L7 answer: the general law, then the concrete case.

### 11.1 Declaring the floor

Some probes will go below your floor: the relay team's gRPC keepalive settings, the KMS's internal HSM topology, the Postgres replica's vacuum tuning. **Declare the floor and keep reasoning.**

#### How an L5 tells it

> Yeah, so the relays use gRPC streaming with flow control, and we tuned it to be highly scalable. I think the team set the window sizes and stuff like that, and it worked well with the load.

#### How an L7 tells it

> That's below where I worked. The relay team owned the gRPC flow-control and keepalive tuning, and I only reviewed the protocol. Here is what I can reason about: each relay held about 1,800 streams and the messages are tiny pointers, so per-stream flow control matters much less than connection churn after a relay restart. That's why I asked for jittered reconnects in the SDK, from 0 to 5 seconds. If I needed the actual window settings, I'd read the relay's config and its load-test report, and I'd ask the relay lead which setting they changed first after the 2 relay incidents.

The L7 version does four things in about 30 seconds:
1. **Names the boundary.**
2. **Names who owned the layer below.**
3. **Reasons from first principles** using numbers already on the board.
4. **Says how it would find out.**

It also connects to a decision the candidate did own (jittered reconnects). The Google Cloud June 2025 report lists missing "randomized exponential backoff" as a contributor to its herd effect ([incident report](https://status.cloud.google.com/incidents/ow5i3PPK96RduMcb1SsW)), so the interviewer is likely to respect that connection.

---

## 12. The numbers card

Carry 12–15 numbers in your head, each with a provenance label: **[M]** measured (and where), **[E]** estimated from measured inputs (and how), **[D]** design target. The label matters because the scribe *will* ask a derived question 20 minutes later, and a number you can't re-derive looks memorized.

| # | Number | Value | Label | How to re-derive it on the spot |
|---|---|---|---|---|
| 1 | Instances | ~48,000 | [M] | Platform inventory at daily peak |
| 2 | Services / namespaces | ~1,200 / ~2,100 | [M] | — |
| 3 | Relays / streams per relay | 27 / ~1,800 | [M] | 48,000 ÷ 27 ≈ 1,778 |
| 4 | Polling alternative | 4,800 QPS | [E] | 48,000 ÷ 10 s |
| 5 | Replica load test | 12,000 QPS | [M] | Load test of the point read |
| 6 | Snapshot sizes | 18 KB median / 1.2 MB p99 / 4 MB cap | [M]/[D] | — |
| 7 | Widest fan-out | ~864 MB per change | [E] | 48,000 × 18 KB |
| 8 | Fan-out rate | ~173 MB/s for ~5 s across 3 regions | [E] | 864 MB ÷ 5 s of jitter |
| 9 | Propagation | p50 9 s / p99 24 s | [M] | SDK applied-version reports |
| 10 | Canary size | ~480 instances (1%) | [E] | 48,000 × 1% |
| 11 | Lookup | p99 180 ns | [M] | JMH microbenchmark plus a production sampling profiler |
| 12 | Incidents | 2 config Sev-1s before → 0 after | [M] | Incident tracker, 12-month windows |
| 13 | INC-B7 | ~140 instances, 0.3%, 6 min | [M] | 140 ÷ 48,000 ≈ 0.29% |
| 14 | Migration | 300 ZK + 410 static services; 212 mismatches / 37 services | [M] | Migration dashboard |
| 15 | Team / timeline | 6 engineers; 9 months to decommission | — | — |

**Precision honesty.**
- **Say "about 48,000 at daily peak", not "48,213".** False precision invites the question "how did you measure that exactly?". A rounded number with a stated source invites trust.
- **If you don't know, give the order of magnitude and how you'd find out.** "Low thousands of QPS, I'd confirm from the load-test report" is better than a made-up number. A made-up number is a fabrication, and it is the single most damaging thing you can be caught doing in this round.

---

## 13. Remote and hybrid logistics

- **Clock:** keep a visible clock in view (not your phone). Glance at it only at the three checkpoints; constant glancing reads as anxiety.
- **Camera and voice:** when you draw, narrate. Silence while drawing is dead air on a call, and the interviewers can't tell whether you're thinking or lost.
- **Notes:** many companies disallow reading from notes, and policies vary (⚠ ask). Plan as if you can't use them. The numbers card should be memorized and derivable.
- **Screen:** close notifications, use a clean browser profile, increase the zoom, and test the drawing tool's sharing beforehand.
- **Latency:** on a laggy connection, interviewers interrupt less smoothly. Add more explicit checkpoints ("I'll pause here") so they don't have to cut across your speech.
- **Two interviewers on a call:** address them by name when you answer, so the scribe knows whose question you're answering. Their notes will be clearer.

---

## 14. Domain lenses: how the six companies' public material shapes the probe mix (⚠)

None of these companies publishes a "past-project deep-dive" rubric. The table connects each company's **public** statements to the kind of probe you should prepare for, and labels everything else as inference. Formats vary by organization and team, so ask your recruiter what the round covers and how long it is.

| Company | Public anchor you can cite | What it suggests the round probes (inference ⚠) | Prep emphasis |
|---|---|---|---|
| **Amazon** | Bar Raisers as objective third-party advisers who facilitate data-driven debriefs and aim for hires better than 50% of would-be peers ([About Amazon](https://www.aboutamazon.com/news/workplace/amazon-bar-raiser)); the Leadership Principles, including "Dive Deep" ("stay connected to the details, audit frequently"), "Ownership" and "Are Right, A Lot" ([Amazon LPs](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)) | Mechanism-level depth on your component; metrics you audited yourself; ownership past your boundary ("they never say 'that's not my job'"); disagreement and commitment | Number derivations; a "Dive Deep" story where metrics and anecdote disagreed; one Have Backbone moment |
| **Google** | Structured interviewing: vetted questions, comprehensive written feedback, standardized rubrics from poor to outstanding, calibrated interviewers ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)) | Feedback is written for reviewers who weren't in the room, so precise, quotable claims matter more than charisma; consistent probing across candidates | Make each claim note-able: one sentence, one number, one owner |
| **Netflix** | Culture memo: "context not control", "informed captain" per significant decision, "farming for dissent", judgment as making "wise decisions despite ambiguity" ([Netflix culture](https://jobs.netflix.com/culture)) | Decisions you captained, what dissent you sought out, judgment under ambiguity, candor about mistakes | A decision you were the informed captain for; the dissent you sought and what changed |
| **NVIDIA** | No public description of this round that we can cite | Domain lens: performance and the hardware-software boundary; expect probes to the memory, interconnect or driver level if your project touches it | Archetypes C and D (Folder 03): latency budgets, memory hierarchy, verification |
| **Uber** | No public description of this round that we can cite | Domain lens: high-volume real-time marketplaces across many cities; expect probes on multi-region behavior, consistency, and failure under peak events | Peak-event numbers; multi-region failure modes; on-call and day-2 (Folder 04 file 03) |
| **Apple** | No public description of this round that we can cite | Domain lens: device constraints, privacy, cross-functional schedules with hardware; expect team-specific depth | Constraints framing (01.3), especially hard hardware or schedule constraints; privacy-by-design decisions |

**The lens matters less than the evidence.** A strong deep dive is strong at every company in this list. The lens changes which evidence to bring forward first, not whether to bring it.

---

## 15. Hiring-committee scoring rubric: structure and pacing

The four bands follow the poor / borderline / solid / outstanding vocabulary from Google's public structured-interviewing guidance. The anchors are a composite (⚠), not any company's internal rubric.

| Dimension | Poor | Borderline | Solid | Outstanding (L7 signal) |
|---|---|---|---|---|
| **Narrative structure** | No arc; starts in the middle; listener lost by minute 5 | Arc exists but context arrives after the architecture | Context → architecture → depth → failure → hindsight, in order | Same, *and* the headline previews the deep-dive hooks so the depth was chosen deliberately |
| **Layered disclosure** | Jumps straight to code | Some layering; skips levels under pressure | Signposted zooms; returns to the container view | Every zoom signposted with *why this part*; deep answers tied back to system-level consequences |
| **Board quality** | No diagram, or an unreadable one | Boxes without labels or rates | Labeled arrows; ownership legend | Permanent context and numbers zones; a stranger could read the system at minute 16 |
| **Interrupt handling** | Defensive, or ignores the question | Answers, but loses the thread | Answers first, then returns to the plan | Parks questions and returns to them unprompted; turns interviewer probes into openings for unsurfaced evidence |
| **Time management** | Never reaches the depth | Depth reached after minute 30 | Depth by minute 16–18; failure covered | Depth by minute 16; re-budgets visibly after detours; leaves the last 8 minutes for the interviewers |
| **Depth access** | Bluffs at the floor | Stops at the floor | Deep on own components; honest floor elsewhere | Deep on 3 prepared wells; declares the floor and reasons past it from first principles |

**What the notes look like (composite ⚠).**
- *Poor:* "Spent 20 min on history. Never saw the design in detail. Couldn't tell what candidate personally did."
- *Solid:* "Clear architecture. Candidate owned publisher and SDK. Good depth on snapshot verification. Failure story OK."
- *Outstanding:* "By min 15 had full diagram with rates and ownership. Candidate recommended deep dive on own protocol; explained monotonic versions as replay defense, attributed the change to security review. Volunteered own root-cause bug (non-atomic LKG write), precise fix ordering. Conceded Postgres would carry load; rejected on coupling. Hindsight: xDS reconsideration with mesh coverage numbers."

The outstanding note is long *because the candidate made it easy to write*. That is the real goal of pacing.

---

## 16. Failure modes

| # | Failure mode | Symptom | Why it hurts | Fix |
|---|---|---|---|---|
| F1 | **Context dump** | 15+ min before the first box | Depth evidence squeezed into the last third | P2 limited to 5 min; script the 50% and one-sentence versions |
| F2 | **Architecture tour** | Every box gets equal time, none gets depth | No S3 evidence; reads as describing, not designing | Depth menu at 16:00 with a recommendation |
| F3 | **Premature descent** | Byte layouts at minute 3 | Listener has no map, so they take control | Start at C4 L1; signpost every zoom |
| F4 | **Monologue** | 5+ min without a checkpoint | Interviewer cuts in and keeps the floor | An ASK every 3–5 min (`pace_check` flags this) |
| F5 | **No board** | Speaking without drawing | Scribe can't anchor notes; consistency checks get harder | Draw during speech, in data-flow order |
| F6 | **Unlabeled arrows** | "And this talks to that" | Invites "how much?" under pressure | Rate or latency on every arrow |
| F7 | **No numbers** | Adjectives instead of quantities | S1 and S6 can't be scored | The numbers card (§12) |
| F8 | **Bluffing at the floor** | Confidence constant while precision drops | Discounts every earlier claim | Declare the floor (§11.1) |
| F9 | **Hindsight squeezed out** | Time runs out at the impact phase | Missing S6, a key L7 signal | Hindsight is "never cut"; the 30-second version exists |
| F10 | **Fighting the redirect** | "Let me just finish this part first" | Signals rigidity; costs their trust | Accept at once; re-budget |
| F11 | **Ownership marked at the end, or never** | Stars added as decoration | Ownership reads as an afterthought | Mark as you draw (§5.3) |
| F12 | **Filling silences** | Talking while the scribe writes | Buries the quotable line under filler | Stop; let them write; "Shall I go on?" |
| F13 | **The victory lap** | Ending on "it was a huge success" | Unfalsifiable; reads as L5 | End on hindsight and an open question |

---

## 17. Bar-raiser chains

<details><summary><b>Q1 · "We're 12 minutes in and I still don't know what you built."</b></summary>

**Initial Prompt.** Twelve minutes into the round, the driver interrupts the context section: "Let me stop you. I still don't know what you actually built."

**L5 Answer.** "Sorry, I'm getting to it. It's just important to understand the history first, because otherwise the design won't make sense. So, as I was saying, the ZooKeeper cluster…"

**Why L5 Stalls.** It defends the plan instead of the listener. The interviewer has just said the plan is failing, and continuing it confirms the failure (F1). The note will read "poor structure; needed redirection twice".

**L7 Answer.** "Fair. In one sentence: I designed and led a config distribution system: a publisher that makes signed, versioned snapshots, stateless relays, and an SDK that swaps them atomically and fails static. Let me draw it now and bring in the history only where a decision needs it." The candidate then goes straight to the 50% architecture (§10) and skips the remaining context entirely. Context that matters (the incidents) comes back later as the reason for specific decisions: "this cap exists because of A1." Recovering in one sentence, without defensiveness, is itself evidence of S7.

</details>

<details><summary><b>Q2 · "Skip the architecture. What's the hardest bug you hit?"</b></summary>

**Initial Prompt.** At minute 6, before any diagram: "Let's skip the architecture. Tell me the hardest bug you hit on this."

**L5 Answer.** "OK, so there was this issue with the disk where pods came up with the wrong config. It was kind of a weird edge case. Basically the file got corrupted, and we fixed it."

**Why L5 Stalls.** Without the architecture, "the file" and "pods came up with the wrong config" mean nothing to the interviewer, and the answer has no mechanism. They now have to dig for every detail, and the candidate looks shallow on the very thing they chose to highlight.

**L7 Answer.** "Happy to. I need 30 seconds of architecture for it to make sense." The candidate draws three boxes: relay, SDK with an in-memory snapshot, and an LKG file on disk. "Each instance keeps the current config in memory and a last-known-good copy on disk for cold starts. The hardest bug was mine: I wrote that disk copy in place with no fsync…" Then the full INC-B7 structure: detection, bound, mitigation, root cause, fix, systemic change. Afterwards: "That bug sits in the SDK, which I designed. Want me to fill in the rest of the system around it?" The redirect is accepted *and* the minimum context gets in, so the story lands.

</details>

<details><summary><b>Q3 · "How does the relay handle backpressure when 48,000 clients reconnect at once?"</b></summary>

**Initial Prompt.** The prober goes after a ○ component: "Your relays restart. 48,000 clients reconnect. Walk me through the backpressure."

**L5 Answer.** "The relays use gRPC, which has built-in flow control, so it handles backpressure automatically. We also had autoscaling, so it was highly scalable."

**Why L5 Stalls.** "Built-in flow control" answers per-stream message backpressure, not a reconnect storm; it's the wrong mechanism. "Autoscaling" doesn't help in the first 30 seconds of a storm. The interviewer has found the floor and the bluff in one answer.

**L7 Answer.** "The relay internals belong to the team; I reviewed the protocol. But the reconnect storm is a client-side behavior and that part is mine. 48,000 ÷ 27 is about 1,800 streams per relay, so one relay restarting sheds about 1,800 clients onto the other 8 relays in its region. That's fine. A full regional restart is the real case: 16,000 clients at once. Three things in the SDK handle it. Reconnects are jittered from 0 to 5 seconds, which spreads the storm to roughly 3,200 per second across the region. Every client already holds a valid snapshot, so a reconnect is urgent only for ring advances, not for serving. And the first message after a reconnect is just the version pointer, so if `have_version` is current, the cost is one small message. What I don't know is the relay's accept-queue and per-connection memory settings. I'd check the relay load test for its connection-setup rate per second, because that number decides whether 3,200 per second is safe."

</details>

<details><summary><b>Q4 · "Why is this a separate service at all? It's a key-value lookup."</b></summary>

**Initial Prompt.** In the architecture phase, the driver says: "This whole thing is a key-value lookup. Why isn't it a table and a cache library?"

**L5 Answer.** "Because at our scale a table wouldn't be scalable, and we needed real-time updates, which you can't do with a database."

**Why L5 Stalls.** Both claims are false and easy to refute: 4,800 QPS of point reads is modest for one replica, and polling every few seconds is near real time. The interviewer now doubts every scale claim the candidate makes.

**L7 Answer.** "The lookup itself is a key-value read, and in our design it *is* an in-memory map. The service exists for the write side, not the read side. A table plus a cache gives you a read path. It doesn't give you three things that caused our incidents: staging a change through rings with an automatic halt (A1 went global in 2 seconds), atomic multi-key snapshots so a service never sees half a change, and fail-static behavior when the store is down (A2 was clients falling back to defaults). We did build a table-plus-polling prototype first. It carried the load fine, and I rejected it because I'd have had to rebuild versioning, verification and LKG in every client library anyway." Then: "Folder 02 depth is available if you want the numbers." The concession is honest, and the rejection rests on the incident history, not on scale.

</details>

<details><summary><b>Q5 · "Walk me through the first 200 milliseconds after someone flips a flag."</b></summary>

**Initial Prompt.** "An engineer clicks 'save' on a flag change. Walk me through the first 200 milliseconds."

**L5 Answer.** "It goes to the API, gets saved in the database, then the publisher picks it up and sends it to the relays, and the clients get it. It's pretty much instant."

**Why L5 Stalls.** It describes boxes, not a timeline, and "pretty much instant" contradicts the design: nothing about a staged system is instant. The probe was testing whether the candidate knows the *sequence and its latencies*. A passenger knows the boxes; the author knows the clock.

**L7 Answer.** "In the first 200 ms, nothing reaches a client, by design. Roughly: the API validates permissions and writes the change row in one transaction, a few ms. The publisher is notified through Postgres LISTEN/NOTIFY and also polls the log every second as a backstop, because NOTIFY isn't durable. It loads the namespace, canonicalizes and runs the validator's sandboxed parse, tens of ms for a median 18 KB namespace. Then it hashes, signs through KMS (the slowest step, typically 20–50 ms), writes the blob to three regional object stores in parallel, 50–100 ms, and only then advances the version for ring0. So at 200 ms we're about at 'the ring0 pointer is announced'. Ring0 clients fetch over the next few seconds with jitter, and ring1 doesn't see it for 5 minutes, the bake. If you want a change to be instant, the only way is the break-glass lane: booleans only, 2 approvers." (These sub-step latencies are composite placeholders; in your dossier use measured values from traces.)

</details>

<details><summary><b>Q6 · "You said p99 24 seconds. Measured how, from where to where?"</b></summary>

**Initial Prompt.** The scribe, 20 minutes after the headline: "You said p99 24 seconds. Measured from what event to what event, and by whom?"

**L5 Answer.** "It was on our dashboard; the SRE team set it up. It was around 24 seconds, I think."

**Why L5 Stalls.** The candidate quoted a headline number they can't define, and the definition is everything here. "Propagation" could mean publish-to-fetch, publish-to-apply, or ring advance to 99% applied, and those differ by an order of magnitude. Owning a number means owning its definition.

**L7 Answer.** "From the rollout controller advancing a ring pointer to an SDK reporting that version as applied, meaning verified, parsed and swapped, not just fetched. Each SDK reports `(namespace, version, applied_at)` and the controller logs `advanced_at`, both on the same NTP-disciplined fleet clock. Skew is small next to seconds, but I excluded negative deltas, which come from clock steps. The p99 is over instances in the target ring, per change, then the median of those per-change p99s over 12 months. The tail is dominated by instances under GC pressure at swap time and by the 0–5 s reconnect jitter after relay restarts. The SRE partner built the dashboard; I defined the metric in the RFC, because G2 was my success criterion."

</details>

<details><summary><b>Q7 · "Ten minutes left. What's the one thing you'd change?"</b></summary>

**Initial Prompt.** At minute 50, before the planned hindsight phase: "We have ten minutes. If you could change one thing about this system, what would it be?"

**L5 Answer.** "Honestly I think the design was pretty solid. Maybe I'd add more tests, and maybe use a newer version of gRPC."

**Why L5 Stalls.** "The design was pretty solid" signals low self-critique (Amazon's "Earn Trust" asks leaders to be "vocally self-critical"). "More tests" is generic and could apply to any project. A hindsight answer must be specific to this design and include *why it wasn't done then*.

**L7 Answer.** "I'd make the readiness behavior on a missing config a required decision per namespace from day one. We added the `on_missing` policy only after INC-B7, and asking each namespace owner one question at creation costs nothing compared with a Sev-2. It wasn't done originally because I treated 'fall back to compiled-in defaults' as safe by default. INC-A2 should have taught me otherwise, since one of those defaults disabled a rate limiter. Defaults can be unsafe. The second-order lesson I took is that any 'safe fallback' needs an owner who has decided it is safe." Stopping there leaves the interviewers time to use.

</details>

<details><summary><b>Q8 · "Pick a different project, one where you failed."</b></summary>

**Initial Prompt.** At minute 35, the driver changes course: "This went well. Pick a different project, one that failed."

**L5 Answer.** "I don't think I've really had a project fail. There were some delays on one, but we delivered in the end."

**Why L5 Stalls.** At L6/L7, "no failures" reads either as a lack of self-awareness or as never having taken real risk. Both are disqualifying for a role whose job is taking calculated risks. A pivot request also tests preparation: did they bring a backup (§4.2)?

**L7 Answer.** The candidate pivots to the prepared backup, in the headline template, in 60 seconds: "An earlier project: I proposed and led a move of our deployment tool from a push model to a pull-based agent. I set a 2-quarter plan; we stopped at 60% adoption after 3 quarters. I underestimated how many teams depended on push-side hooks that the agent model removed, about 40 integrations, and I discovered it through adoption friction instead of an inventory up front. The decision to stop was mine: I wrote the memo recommending we run both models and freeze new push features. What I do differently now is exactly what Beacon's shadow diff did: measure dependence on observable behavior *before* committing to a cutover date." Then the candidate offers the depth: "Want the details of how I decided to stop?" The failure is real, owned, quantified, and connected to a later improvement. That is the learning signal.

</details>

<details><summary><b>Q9 · "Redraw it: only the boxes you personally changed."</b></summary>

**Initial Prompt.** The prober hands over a fresh board: "Erase the diagram. Redraw only the components you personally designed or wrote code in."

**L5 Answer.** The candidate redraws nearly everything, hesitates on the relays, then draws them too: "I touched most of it."

**Why L5 Stalls.** This is a direct authorship test (01.2). Redrawing everything contradicts a team of 6 and makes every earlier claim suspect. Hesitating on a box and then drawing it anyway is exactly the signal the probe exists to find.

**L7 Answer.** The candidate draws four boxes and stops: publisher, SDK (Java), rollout controller, ZooKeeper bridge. Then, for each: "Publisher: designed it, wrote the snapshot builder, signer and size guard; another engineer wrote the announcer. SDK: designed the semantics, wrote the Java reference; I reviewed the Go port and didn't touch Python or Node. Controller: designed it and co-wrote it with one engineer; she wrote the metrics adapter. Bridge: designed it and wrote the shadow-diff comparator; the compat shims were written by each owning team from my template." Then: "The validator contract is mine but the plugins aren't, so I've left it off; I can speak to its interface and not to every plugin." The precision, including what was excluded, is the evidence.

</details>

<details><summary><b>Q10 · "eu-west is partitioned from the control plane for 2 hours. What happens?"</b></summary>

**Initial Prompt.** A hypothetical on the diagram: "A network partition cuts eu-west off from the publisher and controller for 2 hours. Its local relays and object store are up. What happens?"

**L5 Answer.** "The SDK caches the config, so services in eu-west keep working with the cached version. When the partition heals they get the new config."

**Why L5 Stalls.** It's correct but shallow: it doesn't address changes made *during* the partition, ring semantics, kill switches, or the reconciliation when the partition heals. The interviewer was looking for second-order effects.

**L7 Answer.** "Reads are unaffected. Every instance keeps its in-memory snapshot, which is G3. Four second-order effects. First, changes stall in eu-west: the controller sees no applied-version reports from eu-west, and ring2 rollouts treat that as 'insufficient signal', so they hold rather than mark the change complete. Global changes can still finish in the other two regions, and the dashboard shows eu-west skew. Second, kill switches are the real risk. Break-glass can't reach eu-west either, so the runbook has a regional override: an operator in eu-west can publish a signed kill-switch snapshot from the regional standby publisher, which holds a separate KMS key that can sign only boolean kill switches. Third, on heal, clients see a version jump of maybe several versions. That's safe, because snapshots are complete states, not deltas: they apply only the newest. Fourth, the regional override publishes into a separate overlay namespace with its own version sequence, so it can't collide with the primary's versions. On heal, the primary absorbs the overlay's values as a normal change and the overlay is cleared, again by rolling forward. We tested the partition in a game day; the 2-hour mark mattered only for the SDK's verification-key cache lifetime, which I set to 24 hours for that reason." Placeholder mechanisms: in your own dossier, describe only what really existed.

</details>

---

## 18. Checklist

**Before the day**
- [ ] Project chosen with the §4.1 matrix; backup prepared; 60-second headlines for every résumé line.
- [ ] Headline written, timed at ≤ 90 s, and it names role artifacts and two hooks.
- [ ] Context script names users, the before-state, 3+ numbers, forcing functions, goals and the out-of-scope line.
- [ ] Board layout rehearsed: context strip, numbers column, legend, zoom area, parking lot.
- [ ] Draw order rehearsed in data-flow order with ownership marks drawn as you go.
- [ ] Plan written in `script` notation; `pace_check.py --wpm <your measured rate>` passes.
- [ ] Three wells prepared, five levels each.
- [ ] Numbers card memorized with [M]/[E]/[D] labels and a re-derivation for each.
- [ ] 100% / 50% / one-sentence versions of P2, P3, P5, P6, P7, P8.
- [ ] Failure story in the 7-step structure, with your own role named honestly.
- [ ] Hindsight: 2 items, each with why it wasn't done then.
- [ ] Format confirmed with the recruiter: length, number of interviewers, tool, pre-drawn diagrams allowed or not.

**In the room**
- [ ] Project agreed at minute 1.
- [ ] Depth menu offered by minute 16, with a recommendation.
- [ ] Checkpoints at 16:00, 28:00, 44:00; re-budget if more than 3 minutes late.
- [ ] Every interrupt: answer first, then evidence, then anchor.
- [ ] Parking lot fully ticked by minute 55.
- [ ] Floor declared out loud wherever you reach it.
- [ ] Last 8 minutes left to the interviewers.

---

## 19. References

- Google re:Work, "A guide to structured interviewing for better hiring practices": the four practices and the rubric bands. <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
- About Amazon, "Amazon Bar Raisers": the Bar Raiser role and the 50% bar. <https://www.aboutamazon.com/news/workplace/amazon-bar-raiser>
- Amazon Leadership Principles. <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
- Netflix culture memo. <https://jobs.netflix.com/culture>
- Simon Brown, The C4 model for visualising software architecture. <https://c4model.com/>
- Hyrum Wright, Hyrum's Law. <https://www.hyrumslaw.com/>
- Cloudflare, "Cloudflare outage on November 18, 2025" (primary postmortem). <https://blog.cloudflare.com/18-november-2025-outage/>
- Google Cloud, incident report for the June 12, 2025 Service Control outage. <https://status.cloud.google.com/incidents/ow5i3PPK96RduMcb1SsW>
- CrowdStrike, "Channel File 291 Incident Root Cause Analysis" (2024-08-06). <https://www.crowdstrike.com/wp-content/uploads/2024/08/Channel-File-291-Incident-Root-Cause-Analysis-08.06.2024.pdf>
- The Open Group, POSIX `rename()` (IEEE Std 1003.1-2024). <https://pubs.opengroup.org/onlinepubs/9799919799/functions/rename.html>
- LWN, "ext4 and data loss" (2009). <https://lwn.net/Articles/322823/>
- Amazon Builders' Library, "Automating safe, hands-off deployments": waves, bake time, automatic rollback. <https://aws.amazon.com/builders-library/automating-safe-hands-off-deployments/>
- Google SRE Book, "Service Level Objectives". <https://sre.google/sre-book/service-level-objectives/>
