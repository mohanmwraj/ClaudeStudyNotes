# 01.2 · Framing silicon-to-cloud polyglot experience (C, C++, Java, Beam, AI) as a moat

> Folder 01 · L6/L7 resume engineering and narrative positioning · File 2 of 3 · [KB home](../README.md) · Previous: [01.1 Resume anatomy](01-anatomy-of-a-faang-l6-l7-resume-impact-density-and-scope-markers.md) · Next: [01.3 Breaks, tenures, transitions](03-handling-career-breaks-short-tenures-and-service-to-product-transitions.md)

| | |
|---|---|
| **Reader** | An engineer whose career spans low-level C/C++/embedded **and** cloud Java, distributed data pipelines and AI engineering, and whose resume currently reads as two half-careers |
| **Running exhibit** | Candidate V (composite, [01.1 §2.4](01-anatomy-of-a-faang-l6-l7-resume-impact-density-and-scope-markers.md#24-the-running-exhibit-candidate-v-composite)): avionics firmware → C++ ranking cache → Beam pipeline → payments → config platform + LLM triage |
| **Listing** | `yoe_ledger.py`: an honest years-of-experience ledger for multi-domain careers, standard-library Python (§10) |
| **Verification** | The listing is byte-identical to the file that was run. §10.3 is a real run over V's two ledgers in §6. The bullet pairs in §8 are checked with `bullet_lint.py` from 01.1. |
| **Marks** | ⚠ = field practice, not published policy · [M] measured · [E] estimated · [D] design target |

**Integrity rule.** The moat is real only where the depth is real. This file shows how to present breadth you actually have as one coherent capability. It never helps you claim depth you can't show in an interview. §7 sets a "depth floor" for every domain you list.

---

## 0. The 60-second version

1. **Readers divide your years by your domains.** Fourteen years across five domains reads as "under three years in each", which reads as "Senior in nothing". That's the split-resume penalty.
2. **The fix is a throughline, not a list.** Name the one invariant you've optimized at every layer. For V: *data that is never silently lost, at a cost per unit you can state.* Then prove it at three or more layers with numbers.
3. **Transfer stories are the proof.** "The overflow policy I wrote for an avionics ring buffer is the same reasoning as the fail-static config SDK" is worth more than any skills section, provided the second half has a number.
4. **One master resume, three variants.** Cloud/data platform, silicon/embedded/edge, and AI systems. Same facts, same titles and dates; only selection and order change.
5. **Answer years-of-experience questions with a ledger.** There are three honest ways to count years; know all three for each skill and never round up (§6, `yoe_ledger.py`).
6. **Set a depth floor.** Every language or domain under "production depth" may be tested at depth. If you can't pass that floor, list it as "working" instead.
7. **Aim where the intersection is the job:** edge-to-cloud platforms, silicon and hardware data platforms, inference serving and ML infrastructure, performance engineering. For a pure product-backend role, lead with one half and keep the other as a single line.

---

## 1. Why polyglot resumes get down-leveled

### 1.1 The arithmetic readers do

A recruiter filling a Staff data-platform req looks for "years in data platforms". On V's unframed resume, the answer is about two years (R3) plus some of R4 and R5. A recruiter filling a Staff embedded req finds four years of firmware, the most recent in 2016. Both see a 14-year engineer whose relevant depth looks like a mid-level candidate's. Neither is wrong about the arithmetic; they're wrong about the unit. The unit they need is "years solving *this kind of problem*", and the resume never told them what V's kind of problem is.

### 1.2 The three committee worries

| Worry | How it shows up in feedback ⚠ | What actually answers it |
|---|---|---|
| **Depth in neither** | "Breadth over depth", "jack of all trades", "didn't go deep when pushed" | One domain shown at Staff depth (design, failure, numbers), with the others as amplifiers |
| **Ramp risk** | "Will need time on our stack" | A record of ramping fast, with dates: "shipped the first production change in week 3 on a new stack" |
| **Retention and fit** | "Will they be happy doing only Java?" | A stated reason the target role *uses* the breadth, and evidence you've stayed long enough to finish things |

The first worry is the leveling killer. At Staff and above, most ladders expect depth in at least one area plus the breadth to work across others ⚠. Breadth alone is read as a Senior who moved around.

### 1.3 Horizontal versus vertical

| Horizontal (a list of domains) | Vertical (one problem class, down the stack) |
|---|---|
| "Experience in embedded systems, C++, Java, Beam, Kafka, payments, Kubernetes, LLMs" | "I make data move correctly and cheaply at every layer it crosses" |
| Each domain is measured against specialists, and loses | The combination is measured against specialists who can't cross layers, and wins |
| The reader has to find the connection, and usually doesn't | The resume states the connection and every bullet supports it |

"Silicon-to-cloud vertical mastery" means the second column: you understand the cost and failure model of a unit of work all the way from the hardware it starts on to the fleet or model it ends in.

---

## 2. The reframe: find your invariant

### 2.1 Candidate invariants

An invariant is a property you've protected at every layer. Pick the one that's truest for you; most careers have one or two.

| Invariant | What it looks like low in the stack | What it looks like high in the stack |
|---|---|---|
| **No silent data loss** | Counted ring-buffer overflow; CRC/parity on a bus | Dead-letter queues, reconciliation, idempotency |
| **Cost per unit of work** | Cycles per interrupt, allocations per request | $ per million events, $ per ticket, hosts in audit scope |
| **Latency under a hard budget** | WCET, frame budgets, ISR time | p99 SLOs, per-hop latency budgets, time to first token |
| **Safe change** | A/B partitions, rollback, a watchdog | Staged rings, auto-halt, canaries, eval gates |
| **Evidence over assertion** | MC/DC coverage, HIL rigs | Shadow diffing, golden sets, control totals |

### 2.2 Candidate V's throughline map

V's thesis: **"I make data move correctly and cheaply at every layer it crosses."** Here's the evidence, by layer:

| Layer | Exhibit | No silent loss | Cost per unit | Bounded blast radius |
|---|---|---|---|---|
| MCU firmware | D Flightline | Ring overflow counted in the health word; 256 → 512 slots after HIL showed 44 drops [M] | ~6 µs per word in the ISR → DMA blocks of 32 words; interrupt CPU ~20% → <2% | Every minor frame inside its 8,000 µs budget (worst 7,700 µs) |
| C++ service | C Quickset | Misses fall back with AUC −0.0004 at 3% misses [M] | 0 allocations on the read path; 12 GB byte cap | Fan-out tail 27.5% removed by going in-process |
| Streaming pipeline | A Tidewater | DLQ, 7-day dedup, control totals per partition-day | $10.60 per million events at launch [M] | Hot key 9% → <2% per partition by salting |
| Payments | B Tillpoint | Idempotency: 1,214 duplicate captures → 0 | PCI scope 140 → 12 hosts (~$230k/yr) | Critical path ≤ 2 synchronous dependencies |
| Platform | P-0 Beacon | Fail-static: two signed last-known-good generations | 4 MB snapshot cap; 18 KB median | Rings: worst bad change reached 1.1% of instances for 4 min |
| AI system | E Lodestar | Abstain-to-human below a confidence floor (~6%) | $0.0021 per ticket blended | LLM runs on only ~18% of tickets |

Three columns, six layers, and a number in almost every cell. That table is the moat. You won't put it on the resume, but every resume variant, every pitch and every transfer story in this file is drawn from it.

### 2.3 The three-layer rule

A throughline claim needs evidence at **three or more layers**, each with a number. Two layers is a coincidence; three is a pattern a committee can believe. If you can only fill two, your throughline is too narrow or your evidence is missing. Go back to the inventory in 01.1 §13.

---

## 3. The translation table: embedded ↔ cloud ↔ AI

This is the table you use live: when an interviewer asks a cloud question, you answer with cloud vocabulary and borrow the embedded rigor; when a hardware team asks how cloud experience helps, you translate the other way. Use it to explain, never to dodge: answer in the interviewer's vocabulary first.

| Embedded or low-level concept | Cloud or distributed equivalent | AI-systems equivalent | How to use it in an interview |
|---|---|---|---|
| WCET and interrupt latency budget | p99 SLO and a per-hop latency budget | Time to first token; per-stage latency budget | "I budget latency per hop the way I budgeted an ISR: worst case first, then the mean" |
| Cyclic-executive frame budget | Batch window; watermark deadline | Batch deadline for dynamic batching | Frame overrun ↔ batch-window overflow: both are capacity planning against a hard deadline |
| DMA offload | Zero-copy, batching, kernel bypass | Request batching; KV-cache reuse | Move the per-item cost out of the hot path; pay it per batch |
| Hardware label filtering | Predicate pushdown; filter at the source | A cheap classifier in front of the LLM | V's Lodestar design is literally this: the expensive stage sees only what the cheap stage can't decide |
| SPSC ring with an overflow policy | Kafka retention, consumer lag, backpressure | Request queue with load shedding | Every bounded buffer needs a stated policy for "full": block, drop oldest, drop newest; always counted |
| Watchdog timer | Liveness and readiness probes | Timeouts with a fallback model | A watchdog that resets a healthy-but-slow task is the same bug as a liveness probe that kills a GC-pausing JVM |
| A/B firmware partitions with rollback | Blue/green; staged rings | Shadow evaluation; canary prompt rollout | Never update in place without a known-good path back |
| MC/DC coverage | Shadow diffing; reconciliation; contract tests | Golden sets; regression gates in CI | Evidence that each decision condition matters, rather than trust that it does |
| Memory ordering and atomics | Consistency models; idempotency | — | Reasoning about what another observer can see, and when |
| Static allocation after init | Pre-provisioned capacity; bounded queues | A fixed KV-cache budget | No unbounded growth on the hot path |
| Cache lines and false sharing | Partitioning and hot keys | Memory-bandwidth-bound inference | Contention moves up the stack, but it's the same shape |
| Flash wear leveling, write amplification | LSM compaction, write amplification | — | Background work that competes with foreground I/O |
| Fixed-point precision | Exact decimal for money | Quantization (int8, fp8) | Precision is a budget you spend deliberately |
| Bus parity and CRC | Checksums; content-addressed, signed snapshots | Hashes on eval sets to detect leakage | Detect corruption at the boundary, not three hops later |
| HIL test rig | Staging with replayed production traffic | Offline replay evaluation | Test against recorded reality, not synthetic happy paths |
| DO-178C certification evidence | SOC 2 and PCI evidence | AI governance: eval evidence, audit trails | Producing evidence an outsider accepts is a skill that transfers intact |

Where a cell says "—", don't force an analogy. A strained analogy costs more credibility than it earns.

---

## 4. Building the narrative: thesis, proof, target

### 4.1 The thesis sentence

**Formula:** *[Level] engineer who [protects invariant] across [layers]: [proof 1], [proof 2], [proof 3].*

Rules:

- One sentence for the thesis, two for proof. Three lines in total on the resume.
- Each proof has a number and comes from a different layer.
- No adjectives about yourself ("passionate", "results-driven", "seasoned").
- No list of more than three technologies.

### 4.2 Summary transformations

These are summaries, not bullets, so the linter doesn't grade them.

| | Summary |
|---|---|
| **Was** | Software engineer with 14 years of experience in C, C++, Java, Python, Go, Apache Beam, Kafka, Kubernetes, embedded systems, avionics, payments and machine learning. Seeking a challenging role in a reputed organization. |
| **Now (cloud/data platform)** | Staff software engineer for platforms that must not lose data or take the fleet down: led the config platform for 48,000 instances and its org-wide safety policy, a PCI program across 14 teams, and a streaming replacement for a 6-hour batch. Firmware and C++ roots: I size systems from the cost of one unit of work upward. |
| **Now (silicon/embedded/edge)** | Staff engineer who started in DO-178C avionics firmware and took its discipline to fleet scale: hard real-time budgets, data loss that is counted rather than silent, updates that are staged and reversible. Now running a 48,000-instance config platform; looking to bring cloud-scale data and rollout systems back to devices. |
| **Now (AI systems)** | Staff engineer for production AI systems where latency, cost and correctness are all budgets: LLM triage at $0.0021 per ticket behind an eval gate five teams adopted, a 0.9 ms p99 C++ feature cache for ranking, and streaming pipelines that feed models within minutes. |

What changed: the "Was" lists inputs; each "Now" states an invariant, proves it three times, and points at a target.

### 4.3 Three target variants

| | A · Cloud/data platform | B · Silicon/embedded/edge | C · AI systems and ML infrastructure |
|---|---|---|---|
| **Typical teams** | Infrastructure, data platform, config/deploy, payments platform | Device platforms, automotive and edge software, silicon validation, firmware-to-cloud | Inference serving, ML platform, evaluation infrastructure, feature stores |
| **Lead with** | Beacon (L7 bullet), Tillpoint PCI, Tidewater | Flightline (T3, T4), Quickset, Beacon's fail-static design | Lodestar (both bullets), Quickset (latency), Tidewater (fresh data for models) |
| **Demote to one line** | Flightline mechanism (in Selected Impact only if it's your sharpest) | Payments | Payments, firmware |
| **Selected Impact picks** | T6 L7, T5 L7, T3 L6 | T3 L6, T25 L6, T2 L6 | T7 L7, T2 L6, T6 L6 |
| **Honest weakness to own** | Firmware is old; say why it's still relevant | V's last C/C++ as the main language was 2018 (§6) | No GPU-kernel or model-training depth: target serving, platform and evaluation, not kernels or research |
| **Headline** | Staff Software Engineer · Distributed platforms & streaming data · Led config platform for 48k instances · Embedded C/C++ roots | Staff Engineer · Embedded C/C++ to fleet scale · DO-178C firmware + 48k-instance config platform | Staff Engineer · Production AI systems: latency, cost, evaluation · 0.9 ms p99 C++ feature cache · org LLM eval gate |

### 4.4 One master, three variants: the rules

1. **Keep a master bullet bank** with every bullet you can defend, each tagged with role, layer, invariant and variant (A/B/C).
2. **Facts never change between variants:** titles, dates, employers, numbers.
3. **Only selection, order and emphasis change.** A Beacon bullet for variant B may lead with "fail-static" and "signed last-known-good"; for variant A, with "1,200 services" and the RFC.
4. **LinkedIn shows the master,** because everyone sees it. Use the variant closest to most of your targets, and let the About section name the intersection.
5. **Track which variant went to which company.** A recruiter at the same company may see two variants months apart. Differences in emphasis are fine; differences in fact are not.

---

## 5. Where the moat is real, and where it isn't

| Role family | Why the combination wins | The "ticket" (must be strong) | The "moat" (your edge) | Risk to manage |
|---|---|---|---|---|
| **Edge-to-cloud platforms** (OTA, fleet telemetry, device management) | The hard bugs live at the boundary: flaky links, constrained devices, rollouts that can brick hardware | Cloud platform and data-pipeline depth | You know what the device can and can't do, and what a bad rollout costs in hardware | Embedded hiring managers may still test current C toolchains |
| **Silicon and hardware data platforms** (validation logs, test data, telemetry from labs and fabs) | Hardware teams need pipelines built by someone who reads their data like they do | Streaming and batch pipeline depth | You speak register dumps, bus traces and test-equipment output | Domain vocabulary differs by company; learn theirs fast |
| **Inference serving and ML infrastructure** | Serving cost is dominated by memory, batching and tail latency, which are systems problems | Distributed systems and performance | C++ and memory intuition; latency budgeting; evaluation discipline | Some roles expect GPU-kernel or CUDA depth. Ask, and don't claim it if you don't have it |
| **Performance engineering, runtimes, storage engines** | You can follow a cost from the CPU cache line to the cloud bill | C++ or JVM internals | The full-stack cost model | Deep specialists compete here; lead with your strongest single layer |
| **Developer platforms for devices** (build, CI and test for firmware plus cloud) | Few people know both toolchains' failure modes | Build and CI systems | Cross-compilation, HIL rigs and cloud CI under one roof | Smaller teams; check the scope supports L6/L7 |
| **Safety- or compliance-critical platforms** (payments, health, automotive cloud) | Verification culture transfers: MC/DC thinking becomes reconciliation and evidence | Domain platform depth | Producing evidence auditors accept | Make sure the role values it; some teams see compliance as overhead |

**Where it's neutral:** product-backend feature teams, front-end work and ML research. There, lead with the relevant half and keep the other as one line under "Earlier". The moat doesn't hurt; it just isn't the reason they hire you, so don't spend page 1 on it.

---

## 6. Years of experience: the honest ledger

### 6.1 Three meanings of "N years of X"

When a job description says "8+ years of C++", it could mean three different things:

| Counting basis | Definition | When a reader means it |
|---|---|---|
| **FTE-years** | Months × the share of your time spent on X, summed | Rarely stated, but the most conservative and the most defensible |
| **Primary-years** | Months in roles where X had at least half your time | What most hiring managers mean by "N years of X" |
| **Hands-on-years** | Months in roles where X had at least a fifth of your time | What an application form often accepts |

**Rules:**

- **State the basis when it matters:** "8 years with Java as my primary language" or "6 years hands-on, 4 as primary".
- **Don't double-count.** A month at 50% Java and 50% Go isn't a month of each, by FTE.
- **Never round up.** If the ledger says 5.8, say "nearly six", not "eight-ish".
- **Total experience is calendar time.** V can say "14 years, including a six-month break" (2012-07 to 2026-10). Saying "14 years of work" would round up the 13.8 the ledger shows.

### 6.2 Candidate V's ledgers

The share estimates are V's honest view of where engineering time went in each role. The `require=` attributes are knockout lines from three real-looking job descriptions: a cloud platform role (Java 8+), an automotive edge role (C/C++ 8+) and an ML-platform role (Python 5+).

<!-- yoe:start name=v-languages asof=2026-10 require=Java:8;C/C++:8;Python:5 expect=clean -->
| Role | Start | End | Shares |
|---|---|---|---|
| R1 Avionics supplier | 2012-07 | 2016-06 | C=80, C++=10, Python=10 |
| R2 Ad-ranking company | 2016-07 | 2018-03 | C++=85, Python=15 |
| R3 IT services firm (insurer) | 2018-04 | 2020-02 | Java=80, Python=10, SQL=10 |
| Career break | 2020-03 | 2020-08 | - |
| R4 Omnichannel retailer | 2020-09 | 2023-01 | Java=85, SQL=10, Go=5 |
| R5 Consumer marketplace | 2023-02 | present | Java=50, Go=20, Python=20, C++=10 |
<!-- yoe:end -->

<!-- yoe:start name=v-domains asof=2026-10 expect=split -->
| Role | Start | End | Shares |
|---|---|---|---|
| R1 Avionics supplier | 2012-07 | 2016-06 | Embedded=100 |
| R2 Ad-ranking company | 2016-07 | 2018-03 | LowLatency=90, Streaming=10 |
| R3 IT services firm (insurer) | 2018-04 | 2020-02 | Streaming=85, Backend=15 |
| Career break | 2020-03 | 2020-08 | - |
| R4 Omnichannel retailer | 2020-09 | 2023-01 | Payments=70, Platform=30 |
| R5 Consumer marketplace | 2023-02 | present | Platform=65, AI=35 |
<!-- yoe:end -->

### 6.3 Reading V's results

The run is in §10.3. What it says:

- **By language, V isn't split.** Java was the primary language for about 8.1 years (R3, R4 and R5), so "8+ years of Java" is literally true, on the primary-years basis. The cloud-platform knockout is met.
- **By domain, V looks split:** the deepest single domain (embedded) is 4 primary-years of 13.8. That's the split-resume penalty in numbers, and it's why the throughline (§2) has to do the work. No single domain will.
- **The C/C++ 8+ knockout isn't met:** about 5.8 primary-years. V doesn't answer "yes" on the form. V answers with the number and the adjacent depth (Script 7).
- **The Python 5+ knockout isn't met either** (about 3.8 hands-on-years). For an ML-platform role, V leads with the systems and evaluation work and says plainly that Python is a working language, not the core one.

That last point is the honest boundary of the AI-systems variant: V can credibly target serving, platform and evaluation roles, and shouldn't target roles whose core is Python model development.

---

## 7. The depth floor per domain

Anything under "Production depth" in your skills section (01.1 §7.5) can be tested at depth. The floor is the minimum you should be able to do cold:

| Domain | The floor (be able to do this without notes) | Prep in your companion KBs |
|---|---|---|
| **C and embedded** | Explain volatile vs atomics vs memory barriers; size an ISR budget; design a bounded ring with an overflow policy; read a linker map | [Silicon Systems C L7](../../Silicon-Systems-C-L7-Reference/README.md); [Embedded Linux secure boot/OTA](../../Embedded-Linux-Secure-Boot-OTA-Wireless-L7-Reference/README.md) |
| **C++** | Object lifetimes, move semantics, allocator behavior, the memory model, why a container's layout matters to the cache | [Modern C++ ABI/STL/concurrency L7](../../Modern-Cpp-ABI-STL-Concurrency-L7-Reference/README.md) |
| **Java services** | GC behavior under load, thread pools vs virtual threads, transaction boundaries, connection pools, idempotency | [Java Backend Master Reference](../../Java-Backend-Master-Reference/README.md) |
| **Streaming data** | Event time vs processing time, watermarks, exactly-once (and where it ends), backfills, hot keys | [Unified Dataflow/Beam/Flink L7](../../Unified-Dataflow-Beam-Flink-L7-Reference/README.md) |
| **Distributed systems** | Consistency models, consensus at a whiteboard level, failure detection, fencing | [Distributed Systems Design L7](../../Distributed-Systems-Design-L7-Reference/README.md) |
| **AI systems** | Building an eval set without leakage, cost and latency budgets, abstention, retrieval trade-offs | [Production AI Engineering L7](../../Production-AI-Engineering-L7-Reference/README.md); [ML Foundations L7](../../ML-Foundations-for-AI-Engineers-L7-Reference/README.md) |

**If you can't pass a floor, demote the item** to "Working" in your skills. "Working: Python, Go" is honest and costs nothing. "Production depth: Python" that falls apart in round two costs the level.

---

## 8. Before → After: polyglot bullets

Each pair rewrites one of V's bullets for a reader on the *other* side of the stack: a firmware bullet for a cloud reader, a cloud bullet for an embedded reader. The facts don't change; the emphasis does. Pairs are numbered T21 onward so they don't collide with 01.1.

#### T21 · Firmware, written for a cloud or platform reader (R1, variant A)

| Version | Bullet |
|---|---|
| **Before** | Developed embedded software in C for avionics systems following DO-178C. |
| **After (L6)** | Owned word acceptance and validity monitoring for 12 ARINC 429 channels on a DO-178C avionics unit; designed the 6-test MC/DC set that took the validity monitor's coverage from 1 of 5 conditions to 5 of 5. |

**Why it works for a cloud reader:** "validity monitoring" and "coverage from 1 of 5 to 5 of 5" read as evidence discipline, which every platform team wants.

#### T22 · C++ cache, written for an AI-infrastructure reader (R2, variant C)

| Version | Bullet |
|---|---|
| **Before** | Worked on C++ performance optimization for ranking service using Redis. |
| **After (L6)** | Cut ranking p99 from 41 ms to 22 ms for a model served at ~2,000 requests/s per host by moving ~3,000 feature lookups per request into an in-process C++ cache with zero allocations on the read path. |

**Why:** "model served", "feature lookups" and "p99" are the inference-serving vocabulary. Nothing in it is new; the 2017 work just gets described in the words a 2026 ML-infra manager uses.

#### T23 · Streaming pipeline, written for an embedded or edge reader (R3, variant B)

| Version | Bullet |
|---|---|
| **Before** | Created Beam pipelines in Java on GCP Dataflow for streaming data. |
| **After (L6)** | Architected a CDC → Beam/Dataflow pipeline with a zero-silent-loss budget — dead-letter queue, 7-day stateful dedup, per-partition reconciliation — moving 180M records/night from a 6-hour batch window to a 3-minute p95 freshness. |

**Why:** "zero-silent-loss budget" is the embedded engineer's instinct, stated in pipeline terms. A device-platform manager sees someone who'll treat fleet telemetry the same way.

#### T24 · Payments, written for a hardware-company reader (R4, variant B)

| Version | Bullet |
|---|---|
| **Before** | Fixed bugs in payment service related to retries and timeouts. |
| **After (L6)** | Eliminated double charges under retries at 2,400 orders/s peak — idempotency keys checked inside the capture transaction, retry budgets at a single layer — taking duplicate captures from 1,214 in one incident to zero across the next two peak seasons. |

**Why:** retries and duplicate side effects are exactly the failure class of firmware update and device-command systems. Say "payments" once; the reader hears "exactly-once commands".

#### T25 · Config platform, written for an embedded reader (R5, variant B)

| Version | Bullet |
|---|---|
| **Before** | Worked on feature flag platform for microservices. |
| **After (L6)** | Brought firmware-style fail-static design to a 48,000-instance config platform by making reads never block on the network and keeping two signed last-known-good generations on disk; staged rings auto-halted 3 bad changes at ≤1.1% blast radius. |
| **After (L7)** | Set the org-wide rule that config reads never block on the control plane — written into the cross-org RFC and enforced in the SDK — so a control-plane outage now means no new changes, never missing config, for 1,200 services. |

**Why:** "two signed last-known-good generations" is A/B partitioning in cloud clothing. An embedded hiring manager recognizes it instantly.

#### T26 · LLM triage, written for a systems reader (R5, variant C)

| Version | Bullet |
|---|---|
| **Before** | Used machine learning and LLMs to automate ticket routing. |
| **After (L6)** | Cut seller-ticket misroutes from 23% to 8.5% on a 2,400-ticket held-out set by gating the LLM behind a small classifier, so it runs on only ~18% of ~41,000 daily tickets at $0.0021 per ticket blended. |

**Why:** a systems reader values the gating design (the cheap stage filters for the expensive stage) and the unit cost more than the model name.

---

## 9. LinkedIn for a polyglot

- **Headline:** the variant closest to most of your targets (§4.3). Don't try to fit all three.
- **About:** the full master narrative: thesis, the throughline in three proofs, what you want next (Script 6 is V's).
- **Experience:** per role, lead with the bullet that best supports the throughline, not the one most native to that role's domain.
- **Featured:** one artifact per layer if you have them: a firmware or C++ talk, a pipeline design write-up, an LLM evaluation post.
- **Skills:** order the top skills by the variant you're targeting. Endorsements matter less than the match with what sourcers search for ⚠.

---

## 10. The listing: `yoe_ledger.py`

### 10.1 What it does

It reads one or more ledger tables from a Markdown file and reports, for every skill, the three counting bases from §6.1, plus:

- **`SPLIT-RISK`** when your deepest single skill (by primary-years) covers less than half your working years: the signal that a throughline has to carry the narrative.
- **A knockout check** for each `require=` line, with an honest sentence to say: `MEETS`, `MEETS-AS-HANDS-ON`, or `SHORT by N y`.

To use it: copy V's table format into `ledger.md` with your roles and honest share estimates, add `require=` lines from the job description, and run `python -I yoe_ledger.py ledger.md`.

### 10.2 Listing

<!-- include:yoe_ledger.py -->
```python
#!/usr/bin/env python3
"""yoe_ledger.py: honest years-of-experience ledger for multi-domain careers.

Reads every block like this from a Markdown file:

  <!-- yoe:start name=languages asof=2026-10 require=Java:8;C/C++:8 -->
  | Role | Start | End | Shares |
  |---|---|---|---|
  | R1 Avionics supplier | 2012-07 | 2016-06 | C=80, C++=10, Python=10 |
  | Career break | 2020-03 | 2020-08 | - |
  | R5 Marketplace | 2023-02 | present | Java=50, Go=20, Python=20, C++=10 |
  <!-- yoe:end -->

Shares are your honest estimate of where your engineering time went in that role (they sum to 100).
A '-' share marks a break. For each skill it reports three numbers a recruiter might mean:
  FTE-y      months x share, summed (the most conservative)
  primary-y  months in roles where the skill had >= 50% of your time
  hands-on-y months in roles where the skill had >= 20% of your time
'require=' checks knockout lines from a job description. 'C/C++' sums the shares of C and C++.

Usage: python -I yoe_ledger.py FILE.md [--kb]
  --kb  also check each block's 'expect=split' or 'expect=clean' attribute against the SPLIT-RISK result.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*yoe:start\s+(.*?)-->")
END = re.compile(r"<!--\s*yoe:end\s*-->")
ROW = re.compile(r"^\|\s*(.+?)\s*\|\s*(\d{4}-\d{2})\s*\|\s*(\d{4}-\d{2}|present)\s*\|\s*(.+?)\s*\|\s*$")


def months(start, end, asof):
    if end == "present":
        end = asof
    sy, sm = map(int, start.split("-"))
    ey, em = map(int, end.split("-"))
    return (ey - sy) * 12 + (em - sm) + 1


def parse_attrs(text):
    return dict(re.findall(r"(\w+)=(\S+)", text))


def read_blocks(path):
    blocks, cur, fenced = [], None, False
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.lstrip().startswith("```"):
                fenced = not fenced
            if fenced:
                continue
            m = START.search(line)
            if m:
                cur = {"attrs": parse_attrs(m.group(1)), "rows": []}
                continue
            if cur is not None and END.search(line):
                blocks.append(cur)
                cur = None
                continue
            if cur is not None:
                r = ROW.match(line.strip())
                if r:
                    cur["rows"].append(r.groups())
    return blocks


def share_map(text):
    if text.strip() == "-":
        return None
    out = {}
    for part in text.split(","):
        k, v = part.split("=")
        out[k.strip()] = int(v)
    if sum(out.values()) != 100:
        raise ValueError(f"shares must sum to 100: {text}")
    return out


def share_of(shares, skill):
    return sum(shares.get(s, 0) for s in skill.split("/"))


def ledger(block):
    a = block["attrs"]
    asof = a.get("asof", "2026-10")
    rows = []
    work = brk = 0
    for role, start, end, shares in block["rows"]:
        n = months(start, end, asof)
        sm = share_map(shares)
        rows.append((role, start, end, n, sm))
        if sm is None:
            brk += n
        else:
            work += n
    skills = []
    for _, _, _, _, sm in rows:
        for k in (sm or {}):
            if k not in skills:
                skills.append(k)
    reqs = []
    if "require" in a:
        for item in a["require"].split(";"):
            k, v = item.rsplit(":", 1)
            reqs.append((k, float(v)))
            if k not in skills:
                skills.append(k)

    def stats(skill):
        fte = prim = hand = 0.0
        first = last = None
        for role, start, end, n, sm in rows:
            if sm is None:
                continue
            s = share_of(sm, skill)
            if s <= 0:
                continue
            fte += n * s / 100
            if s >= 50:
                prim += n
            if s >= 20:
                hand += n
            first = first or start
            last = end
        return fte / 12, prim / 12, hand / 12, first, last

    name = a.get("name", "?")
    print(f"ledger {name} (as of {asof}): {work / 12:.1f} y of work, {brk / 12:.1f} y of breaks")
    print(f"  {'skill':<14}{'FTE-y':>7}{'primary-y':>11}{'hands-on-y':>12}  span")
    table = {}
    for sk in skills:
        f, p, h, first, last = stats(sk)
        table[sk] = (f, p, h)
        span = f"{first} -> {last}" if first else "-"
        print(f"  {sk:<14}{f:>7.1f}{p:>11.1f}{h:>12.1f}  {span}")
    flags = []
    single = [s for s in skills if "/" not in s]
    top = max(single, key=lambda s: table[s][1]) if single else None
    if top is not None and work and table[top][1] < 0.5 * work / 12:
        flags.append("SPLIT-RISK")
        print(f"  SPLIT-RISK: the deepest single skill ({top}, {table[top][1]:.1f} primary-y) is under half of "
              f"{work / 12:.1f} y of work; lead with a throughline, not a list (01.2 section 2)")
    for skill, need in reqs:
        f, p, h = table[skill]
        if p >= need:
            verdict = "MEETS"
            say = f"\"{p:.0f}+ years with {skill} as my primary language.\""
        elif h >= need:
            verdict = "MEETS-AS-HANDS-ON"
            say = f"\"{h:.0f} years hands-on with {skill}, {p:.1f} of them as my primary language.\""
        else:
            verdict = f"SHORT by {need - max(p, h):.1f} y"
            say = (f"\"{max(p, h):.1f} years with {skill}; I won't round that up. "
                   f"Here is the adjacent depth that covers the gap: ...\"")
        print(f"  require {skill} >= {need:g} y: {verdict}")
        print(f"    say: {say}")
    return name, flags


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    bad = []
    for block in read_blocks(argv[1]):
        name, flags = ledger(block)
        expect = block["attrs"].get("expect")
        if kb and expect and (expect == "split") != ("SPLIT-RISK" in flags):
            bad.append(name)
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 10.3 Output: V's two ledgers

<!-- run:yoe_ledger.py SELF --kb -->
```text
ledger v-languages (as of 2026-10): 13.8 y of work, 0.5 y of breaks
  skill           FTE-y  primary-y  hands-on-y  span
  C                 3.2        4.0         4.0  2012-07 -> 2016-06
  C++               2.3        1.8         1.8  2012-07 -> present
  Python            1.6        0.0         3.8  2012-07 -> present
  Java              5.5        8.1         8.1  2018-04 -> present
  SQL               0.4        0.0         0.0  2018-04 -> 2023-01
  Go                0.9        0.0         3.8  2020-09 -> present
  C/C++             5.5        5.8         5.8  2012-07 -> present
  require Java >= 8 y: MEETS
    say: "8+ years with Java as my primary language."
  require C/C++ >= 8 y: SHORT by 2.2 y
    say: "5.8 years with C/C++; I won't round that up. Here is the adjacent depth that covers the gap: ..."
  require Python >= 5 y: SHORT by 1.2 y
    say: "3.8 years with Python; I won't round that up. Here is the adjacent depth that covers the gap: ..."

ledger v-domains (as of 2026-10): 13.8 y of work, 0.5 y of breaks
  skill           FTE-y  primary-y  hands-on-y  span
  Embedded          4.0        4.0         4.0  2012-07 -> 2016-06
  LowLatency        1.6        1.8         1.8  2016-07 -> 2018-03
  Streaming         1.8        1.9         1.9  2016-07 -> 2020-02
  Backend           0.3        0.0         0.0  2018-04 -> 2020-02
  Payments          1.7        2.4         2.4  2020-09 -> 2023-01
  Platform          3.2        3.8         6.2  2020-09 -> present
  AI                1.3        0.0         3.8  2023-02 -> present
  SPLIT-RISK: the deepest single skill (Embedded, 4.0 primary-y) is under half of 13.8 y of work; lead with a throughline, not a list (01.2 section 2)

VERDICT: OK
```

---

## 11. Word-for-word scripts

#### Script 1 · Verbal: the 45-second pitch, cloud or data-platform target

```text
"I'm a Staff engineer at [marketplace], where I lead our config and rollout platform: about
1,200 services and 48,000 instances. I wrote the RFC that set our org-wide rules for safe
config changes, and config-caused Sev-1s went to zero. Before that I led checkout payments
at a large retailer and built a streaming replacement for an insurer's nightly batch.

What's unusual about me is where I started: avionics firmware and low-latency C++. That's
why I design platforms from the cost and failure mode of one unit of work upward. I'm
looking for a Staff role on a platform many teams depend on, and [team] looks like that."
```

#### Script 2 · Verbal: the 45-second pitch, silicon, embedded or edge target

```text
"I started in DO-178C avionics firmware: ARINC 429, cyclic executives, MC/DC. Then I spent
ten years taking that discipline to cloud scale. Today I run a config platform for 48,000
instances that's built like firmware: reads never block on the network, there are two signed
last-known-good copies on disk, and updates roll through staged rings that halt themselves.

I'm looking to bring that back toward devices, where fleet-scale data and safe rollout
matter most, because a bad update there costs hardware, not just a page. [Team]'s work on
[OTA / fleet telemetry / validation data] is exactly that boundary."
```

#### Script 3 · Verbal: the 45-second pitch, AI systems target

```text
"I build production AI systems the way I built low-latency systems: with budgets. At
[marketplace] I designed LLM triage for about 41,000 tickets a day. A small classifier goes
first, the LLM sees only the 18% it can't decide, and anything below a confidence floor goes
to a human. Misroutes dropped from 23% to 8.5% at about a fifth of a cent per ticket. I also
built the evaluation gate five teams now use.

Before that: a C++ feature cache that took ranking p99 from 41 to 22 milliseconds, and
streaming pipelines that feed models within minutes. To be precise about my edges: my
depth is the serving, data and evaluation path, not GPU kernels or model research."
```

#### Script 4 · Verbal: "So are you a C++ person or a Java person?"

```text
"Java has been my primary language for the last eight years, and it's the one I'd interview
in for a services role. C and C++ are where I learned how machines actually work, and I still
use C++ when latency or memory is the problem. The more useful answer is what I'm for: I take
a unit of work, a message, a request, a ticket, and make it correct and cheap at every layer
it crosses. The language follows the layer."
```

#### Script 5 · Verbal: "Why did you move from embedded to cloud?"

```text
"Deliberately, and in steps. In avionics I'd learned to build things that can't fail
silently, but the scale was one unit at a time. I wanted the same problems at fleet scale,
so I went to low-latency C++ first, which kept me close to the hardware, and then to
streaming data and platforms. Each move bought a specific capability. The embedded habits
came with me: the config platform I run today is designed like firmware, with fail-static
reads, two known-good copies and staged updates."
```

#### Script 6 · LinkedIn About (V's master version, ~1,900 characters)

```text
I make data move correctly and cheaply at every layer it crosses: from interrupt budgets on
a 300 MHz microcontroller to a 48,000-instance config platform and LLM systems priced per
ticket.

Today I'm a Staff engineer at [marketplace]. I led the team that replaced our ZooKeeper flag
store for 1,200 services and wrote the cross-org RFC that sets config-safety policy for about
2,000 engineers: staged rings, automatic halts, reads that never block on the control plane.
Config-caused Sev-1s went from 2 a year to 0, and we retired the old ensemble two weeks
before a colocation lease would have cost over $1M to extend. I also designed our LLM ticket
triage and the evaluation gate that five product teams now use.

Before that:
• Payments (retail): led the checkout-payments redesign (idempotency, outbox, saga) and a
  PCI scope program across 14 teams, cutting in-scope hosts from 140 to 12.
• Streaming data (insurance): replaced a 6-hour nightly batch with CDC → Kafka → Beam on
  Dataflow, with reconciliation that regulatory reports rely on.
• Low-latency C++ (ad ranking): an in-process feature cache that took ranking p99 from
  41 ms to 22 ms.
• Avionics firmware: ARINC 429 data acquisition under DO-178C, where I learned that every
  dropped message must be counted.

What I'm looking for: Staff or Principal roles where the hard problems sit between layers,
such as edge-to-cloud platforms, data infrastructure, or AI serving and evaluation.

Based in Bengaluru; open to Hyderabad and relocation.
```

#### Script 7 · Verbal: "The role needs 8+ years of C++. Do you have that?"

```text
"Not by the usual definition, and I'd rather be precise. I have about five and three-quarter
years with C and C++ as my main language, in avionics firmware and a low-latency ranking
cache, and I've used C++ in production since then for performance-critical pieces.

What I'd ask you to weigh: the hard parts of this role, from your description, are
[latency budgets / memory behavior / concurrency]. That's exactly what I did in those years,
at a hard real-time level. I'm comfortable being tested on modern C++ at depth in the loop."
```

#### Script 8 · Email: a cold note to a hiring manager at an edge-to-cloud team

```text
Subject: Firmware-to-fleet engineer: [their team / product] rollout safety

Hi [HM name],

I read [their post / talk / job description] on [OTA updates / fleet telemetry]. The line
about [specific problem, e.g. "rollouts that must never brick a device"] is the problem I've
spent my career on from both ends:

• Firmware: DO-178C avionics data acquisition (ARINC 429), where I cut interrupt CPU from
  ~20% to <2% without a board respin.
• Fleet: today I run a config platform for 48,000 instances, built on firmware rules: two
  signed last-known-good copies, reads that never block, staged rings that halt themselves.

I'm exploring Staff-level roles, and yours is the first I'm writing to directly. Would a
20-minute call be useful? If it isn't the right time, a pointer to the right person would
be very kind.

[Your Name] · [LinkedIn] · [Phone]
```

#### Script 9 · Verbal: "You seem to be all over the place. What are you, really?"

```text
"Fair question; on paper it looks like five careers. It's one problem at five layers. In
firmware, a dropped bus word had to be counted, not ignored. In the pipeline, the same rule
became a dead-letter queue and reconciliation. In payments, it was idempotency: 1,214 double
charges to zero. On the config platform, it's fail-static reads. In the LLM system, it's
abstaining to a human instead of guessing.

So what I am is the person you put on a system where correctness and cost both matter and
the problem crosses layers. If you want a pure specialist in one layer, I'm the wrong hire.
If the hard part is the seams, I'm the right one."
```

#### Script 10 · Verbal: the transfer story (when asked "How would your background help here?")

```text
"Let me give you one concrete transfer. In avionics we had a ring buffer between the bus
interrupt and the processing task. The question every reviewer asked was: what happens when
it's full? Block, drop the oldest, drop the newest? Whatever the answer, it has to be counted
and reported, because a silent drop is a safety problem.

Years later, our config SDK had the same question in a different form: what happens when
the control plane is down? The answer we chose was the firmware answer: never block, serve
the last known-good version, count and alert on every fallback. When we found a gap, a
truncated last-known-good file that served defaults for 6 minutes on 0.3% of instances,
the fix was firmware discipline again: write, fsync, rename, keep two generations.

For your [system], I'd ask the same question on day one: where are the bounded buffers,
and what's their policy when full?"
```

---

## 12. Probe chains

<details><summary><b>P1 · "Breadth is clear. Where's the depth?"</b></summary>

**Probe:** "You've done a bit of everything. What's the deepest you've gone in one area?"

**What they're testing:** whether there is one domain at Staff depth, the first worry in §1.2.

**Executor answer:** "I'm a fast learner, so I go deep wherever the project needs."

**Staff/Principal answer:** "Config and rollout safety. I can take you from the snapshot format and the signature check, through the SDK's atomic swap and last-known-good semantics, to the ring controller's halt criteria and the incident where our fsync assumption failed. Pick any layer and I'll go as deep as you want. The other domains are where that depth came from, not substitutes for it."

</details>

<details><summary><b>P2 · "You haven't written C professionally in eight years."</b></summary>

**Probe:** (Embedded hiring manager) "Your firmware work is from 2016. Toolchains and practice have moved. Why should we believe you're current?"

**What they're testing:** currency, and whether you'll overclaim.

**Executor answer:** "C hasn't changed much; I could pick it right back up."

**Staff/Principal answer:** "You're right that it's not my current main language, and I won't pretend it is. What's current: I write performance-critical C++ in production, and I've been rebuilding firmware fluency deliberately, [specific, true example: e.g. cross-compiling for Cortex-M with Clang and working through secure boot on an embedded Linux board]. I'd expect you to test me on modern C and on concurrency at the ISR boundary. If I fall short there, that should count."

</details>

<details><summary><b>P3 · "Will you be bored doing only Java?"</b></summary>

**Probe:** "This team is a Java services team. Your background suggests you'll want to move on fast."

**What they're testing:** retention risk and motivation.

**Executor answer:** "No, no, I'm very happy to do just Java."

**Staff/Principal answer:** "The language won't bore me; the problem might. What keeps me is a hard system with a long arc. I stayed four years in avionics and I'm nearly four years into the config platform, because both had multi-year problems. From what you've described, this team's problem is [X], which is a multi-year problem. That's the part I care about."

</details>

<details><summary><b>P4 · "Is the AI work real, or resume decoration?"</b></summary>

**Probe:** "Everyone has an LLM bullet now. What did you actually build?"

**What they're testing:** whether the AI claim has evaluation, cost and failure handling behind it.

**Executor answer:** "We built a RAG pipeline with a vector database and prompt engineering."

**Staff/Principal answer:** "A routing system with three stages: a small classifier, an LLM for the ~18% the classifier can't decide, and abstention to humans below a confidence floor. The part I'm proudest of is the evaluation: a frozen 2,400-ticket held-out set, a CI check that none of those tickets appear as retrieval examples, and cost and latency budgets that fail the build. Misroutes went from 23% to 8.5% at $0.0021 a ticket. Five teams now use the gate."

</details>

<details><summary><b>P5 · "Why so many domain switches?"</b></summary>

**Probe:** "Avionics, ad-tech, insurance, retail, a marketplace. Is there a plan, or did you just take what came?"

**What they're testing:** whether the career is a story or a series of accidents, which predicts whether you'll be deliberate in the role.

**Executor answer:** "Each time a better opportunity came up, I took it."

**Staff/Principal answer:** "Each move bought one capability I didn't have: real-time low-level work, then low-latency services, then streaming data at scale, then cross-team programs in payments, then org-level platform direction. The industries changed because those problems lived in different places. The thread didn't: correctness and cost of data at every layer. This role is the next step: [what it adds]."

</details>

<details><summary><b>P6 · "How exactly does embedded help on a cloud team?"</b></summary>

**Probe:** "I hear 'embedded discipline' a lot. Give me something concrete that changed a design."

**What they're testing:** whether the moat is a slogan or a mechanism.

**Executor answer:** "Embedded taught me to write efficient code and care about memory."

**Staff/Principal answer:** "One concrete case: when we designed the config SDK, the default proposal was to block startup until the control plane answered. My firmware reflex was 'never block on something you don't control'. So we made reads fail-static: serve the last known-good snapshot, verify its signature, count every fallback. When the control plane browned out later, services kept running on known-good config instead of failing to start. That design choice came from the ring-buffer overflow reviews I sat through in avionics."

</details>

<details><summary><b>P7 · "Can you pass our C++ bar?"</b></summary>

**Probe:** (Performance team) "Our loop has a hard C++ round. Your recent work is mostly Java."

**What they're testing:** whether your skills section matches what you'll do in the room.

**Executor answer:** "I'm sure I'll be fine; I've done a lot of C++."

**Staff/Principal answer:** "I'd like to be tested on it. My C++ depth is memory and latency: allocation-free read paths, epoch-based reclamation, cache-friendly layouts. That's what the feature cache was. My gaps are the newest standard features I haven't used in production. I'm preparing for those specifically, and I'd rather you find the gap in the loop than after the offer."

</details>

<details><summary><b>P8 · The committee reads "breadth over depth" in the packet</b></summary>

**Probe:** (Committee member) "Two interviewers wrote 'impressive breadth'. One wrote 'didn't go deep on the data question'. Staff or Senior?"

**What they're testing:** whether the packet contains one undeniable depth signal. You aren't in the room, so the depth has to be in the feedback already.

**Executor answer:** (What an unframed polyglot produces) Breadth noted in three rounds, depth in none. The packet reads as a strong generalist: L5.

**Staff/Principal answer:** (What a framed candidate produces) The resume announced the depth area (config and rollout safety), the deep-dive round went there, and the interviewer wrote "went five layers deep on the SDK and ring controller, including a self-identified failure". The "didn't go deep on data" note reads as one round off the candidate's center, not a ceiling. You make this happen by steering the deep dive to your depth area: pick it in the resume, name it in the HM screen, and offer it when asked "what should we dig into?"

</details>

<details><summary><b>P9 · "Why not stay a specialist?"</b></summary>

**Probe:** "Wouldn't you have reached Principal faster by staying in one domain?"

**What they're testing:** self-awareness about the trade-off you made.

**Executor answer:** "Maybe, but I like learning new things."

**Staff/Principal answer:** "Possibly faster on one ladder, yes. I chose depth in a problem class instead of a domain, and that costs something in the first screen, which is why I'm careful to show the depth. What it buys is the ability to own systems that cross layers, which most orgs struggle to staff. I think that's where Principal-level problems actually are."

</details>

---

## 13. Checklist

- [ ] Write your invariant in one sentence (§2.1). Test it: can you fill a three-layer evidence table with numbers (§2.2)?
- [ ] Build your translation table: five rows minimum, from your own work (§3).
- [ ] Write the thesis summary and three variant summaries (§4.2).
- [ ] Tag every bullet in your bank by layer, invariant and variant (§4.4).
- [ ] Fill your ledger and run `yoe_ledger.py`; write down the honest sentence for each common knockout (§6).
- [ ] Check every "production depth" item against its floor; demote what fails (§7).
- [ ] Rewrite at least one bullet per role for the other side of the stack, and lint it (§8).
- [ ] Rehearse Scripts 4, 5, 9 and 10 aloud until they're under 60 seconds each.
- [ ] Decide which depth area you'll steer the deep dive toward, and make sure your resume points at it.

---

## 14. References

- Will Larson, [StaffEng: Staff archetypes](https://staffeng.com/guides/staff-archetypes/) (the "Solver" and "Architect" archetypes are where deep cross-layer engineers usually fit).
- Tanya Reilly, *The Staff Engineer's Path* (O'Reilly, 2022), ISBN 9781098118730: on the "big-picture thinking" that makes breadth valuable.
- The exhibits' fact sheets and numbers cards: [Past-Project Deep-Dive playbook, Folder 03](../../Past-Project-Deep-Dive-L7-Defense-Playbook/03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/04-archetype-d-embedded-systems-safety-critical-firmware-and-bus-protocol-defense.md) (Flightline shown; Tidewater, Tillpoint and Quickset are its siblings).
- Translating backgrounds into Staff stories: [Behavioral playbook, Folder 06](../../Staff-Principal-Behavioral-L7-Playbook/06-Translating-Technical-Backgrounds-into-L7-Stories/03-handling-the-lack-of-faang-scale-objection-with-complexity-depth.md).
- Depth-floor prep: the companion KBs linked in §7.
