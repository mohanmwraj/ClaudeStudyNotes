# 05.1 · Fill-in-the-Blank L7 Project RFC and Whiteboard Script Template

> **Folder:** `05-Personal-Project-Dossier-Template-and-Stress-Test-Harness` · file 1 of 2
> **Question this file answers:** how do I turn everything in Folders 01–04 into one document about *my* project, the RFC I'd have written had I known I'd be cross-examined on it, and check mechanically that it's ready before a human or an LLM grills me on it ([05.2](02-adversarial-mock-interviewer-prompt-to-grill-my-filled-dossier.md))?
> **Contents:** a blank 12-section dossier template (§2), field-by-field guidance (§3), a fully filled example for P-0 Beacon (§4), and the stress-test harness that checks both (§9).
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L14 `dossier_check.py` | Python 3, standard library | The stress-test harness. Six structural checks: sections, placeholders, the ownership ledger, the numbers card's provenance labels, deep wells, the 7-step failure story. Then it imports the knowledge base's own tools to run five more: the pacing check on the script, ownership and framing lints on the tellings, the constraint ledger, the options matrix, and the hindsight ledger with its time anchor. | [§9](#9-the-stress-test-harness), on the blank template and the filled Beacon dossier |

**Verification.** The gate extracts every listing in the knowledge base into one directory, so the harness can import its five sibling tools exactly as a reader would after copying them out. It checks the harness byte for byte against the source, re-runs it on this file, and compares the result with §9. The verdict requires the blank template to be NOT READY and the filled dossier READY. This file's own L5/L7 tellings are linted by the Folder 01 tools. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

**The workflow:**
1. **Copy the blank template** (§2) into a new file, `my-dossier.md`.
2. **Fill it with real facts** from your project, using the guidance in §3 and the Beacon example in §4 as a model of density.
3. **Copy the knowledge base's listings into one folder:** `pace_check.py`, `ownership_lint.py`, `constraint_check.py`, `options_matrix.py`, `hindsight_check.py` and `dossier_check.py`. Then run `python -I dossier_check.py my-dossier.md`.
4. **Fix every FAIL.** Each one maps to an interviewer probe you would otherwise meet unprepared.
5. **Generate a probe plan** with `grill_plan.py` and run an adversarial mock with the prompt in [05.2](02-adversarial-mock-interviewer-prompt-to-grill-my-filled-dossier.md).
6. **Iterate:** the mock's weakest-signal list tells you which section to deepen.

**Integrity rule, restated where it matters most.** Fill the dossier with what you actually did and measured. Where you don't know a number, write how you'd find out, not a guess. A dossier that passes the harness with invented content is worse than one that fails honestly: the interviewers' probes (01.2 §3) are designed to find invented content, and finding it ends the round.

---

## 1. First principles: why a dossier, and why these twelve sections

### 1.1 The dossier is the RFC you'd defend

An RFC records a decision for reviewers who weren't there. A deep-dive round is a hostile review of that decision by reviewers who weren't there. The dossier is the same document, re-cut for an oral defense:
- **ordered by the 60-minute clock** (01.1);
- **annotated with ownership** (01.2);
- **constraints made explicit** (01.3);
- **alternatives made real** (02.1);
- **numbers derived** (02.2);
- **hindsight classified** (02.3);
- **a failure story ready.**

### 1.2 Why each section exists

| Section | What it answers | Folder it comes from | Harness check |
|---|---|---|---|
| D1 Headline | What, how big, why, my role, outcome, hooks | 01.1 §7.2 | via D12 |
| D2 Context and forcing functions | Who suffered, how badly, under what dates | 01.1 §7.3, 01.3 §5 | S2 |
| D3 Goals and kill criteria | What success meant, with thresholds and sources | 02.1 §3 | S2 |
| D4 Ownership ledger | Which boxes are mine, the artifact for each, my floor | 01.2 §4.2 | S3 |
| D5 Constraint ledger | What bounded the design, and what it cost | 01.3 §2 | T3 |
| D6 Options matrix | Three real options, kill criteria, champions, concessions | 02.1 §8 | T4 |
| D7 Numbers card | Every number I'll say, labeled and derivable | 01.1 §12, 02.2 | S4 |
| D8 Deep wells | Three components I can descend into for 15 minutes | 01.1 §11 | S5 |
| D9 Failure story | One incident in 7 steps, my role honest | 01.1 §7.6 | S6 |
| D10 Hindsight ledger | Decisions classified by decision vs outcome quality | 02.3 §6 | T5 |
| D11 Whiteboard script | The timed plan in `script` notation | 01.1 §8 | T1 |
| D12 Tellings | The 4 spoken answers that carry the most evidence | 01.2 §13 | T2 |

---

## 2. The blank template

Copy everything between the two horizontal rules into your own file, and replace every `{{…}}`. The harness reports every placeholder left behind.

---

<!-- dossier:start name=blank-template -->
### D1. Headline

{{One paragraph, at most 90 seconds spoken: system, users, scale with units; the before-state pain with a number; your exact role as a list of artifacts; the outcome restating the pain metric; two hooks for the deep dive. Write it as the D12 headline telling.}}

### D2. Context and forcing functions

- **Users and scale:** {{who uses it, how many, how often}}
- **Before-state:** {{the old way, with one number per pain}}
- **Incidents or pain events:** {{ID, severity, duration, one line each}}
- **Forcing functions:** {{the dates, prices or regulations that made it happen now}}
- **Out of scope:** {{what you deliberately excluded}}

### D3. Goals and kill criteria

| ID | Goal | Threshold | Measurement | Source | Kind |
|---|---|---|---|---|---|
| {{K1}} | {{property}} | {{threshold}} | {{how measured}} | {{who or what requires it}} | {{Kill or Scored}} |

### D4. Ownership ledger

| Component | Mark | My verbs | Artifact | I can speak to at depth | My floor |
|---|---|---|---|---|---|
| {{component}} | {{★ / ◆ / ○}} | {{designed / decided / led / wrote / reviewed / consumed}} | {{RFC section, PRs, runbook}} | {{the mechanisms you can explain 5 levels down}} | {{where your knowledge stops, and who owns below it}} |

### D5. Constraint ledger

| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| {{C1}} | {{constraint}} | {{Legacy / Stakeholder / Deadline / Regulatory / Budget / Skills / Scale}} | {{source}} | {{Hard / Soft / Negotiable}} | {{what you checked}} | {{what you did}} | {{quantified cost}} | {{when to revisit}} |

### D6. Options matrix

| Criterion | Weight | {{Option 1}} | {{Option 2}} | {{Option 3}} |
|---|---|---|---|---|
| {{hard requirement}} | KILL | {{pass/fail: why}} | {{pass/fail: why}} | {{pass/fail: why}} |
| {{preference}} | {{1-5}} | {{1-5}} | {{1-5}} | {{1-5}} |
| Champion | - | {{role}} | {{role}} | {{role}} |
| Chosen | - | {{yes/-}} | {{yes/-}} | {{yes/-}} |

### D7. Numbers card

| Number | Value | Label | Re-derive |
|---|---|---|---|
| {{name}} | {{value with units}} | {{[M] / [E] / [D]}} | {{the arithmetic from inputs on the board, or where it was measured}} |

### D8. Deep wells

| Level | Well 1: {{component}} | Well 2: {{component}} | Well 3: {{component}} |
|---|---|---|---|
| 1 What | {{one sentence}} | {{one sentence}} | {{one sentence}} |
| 2 How | {{steps in order}} | {{steps in order}} | {{steps in order}} |
| 3 Why | {{the goal or invariant each step serves}} | {{...}} | {{...}} |
| 4 Why not | {{2+ alternatives and why they lost}} | {{...}} | {{...}} |
| 5 What breaks | {{3 failure modes, with detection and handling}} | {{...}} | {{...}} |

### D9. Failure story

1. **Detection.** {{the signal, and how fast}}
2. **Bounding.** {{the blast radius, and how you knew}}
3. **Mitigation.** {{what stopped it, and who did it}}
4. **Root cause.** {{the mechanism, precisely; whose it was}}
5. **Fix.** {{the code-level change}}
6. **Systemic change.** {{what makes the whole class less likely}}
7. **My role.** {{what you did in each step, including what you got wrong}}

### D10. Hindsight ledger

| ID | Decision | Known then | Known now | Class | Change today | Cost of current design | Trigger to act |
|---|---|---|---|---|---|---|---|
| {{H1}} | {{decision}} | {{what was known at the time}} | {{what is known now}} | {{Good/Bad decision, good/bad outcome}} | {{specific change}} | {{quantified}} | {{when}} |

### D11. Whiteboard script

```script
# plan: {{project}} - 60 minutes
== {{00:00-02:00}} | Intros
SAY: {{...}}
```

### D12. Tellings

#### My telling: headline

> {{the D1 headline as you will say it}}

#### My telling: decision

> {{the most important decision: options, kill criterion, concession, what you kept}}

#### My telling: failure

> {{the D9 story in 60-90 seconds}}

#### My telling: hindsight

> {{the change, why it wasn't done then (a time anchor), its cost, its trigger}}
<!-- dossier:end -->

---

## 3. Field-by-field guidance

| Section | What "good" looks like | Common failure | Where to read more |
|---|---|---|---|
| D1 | ≤ 90 s; scale with units; the role as artifacts; a volunteered failure hook | Résumé tour; "worked on" | 01.1 §7.2 |
| D2 | One number per pain; forcing functions priced | "Leadership wanted it" | 01.3 §5.1 |
| D3 | Thresholds with measurements and sources | "Fast", "reliable" | 02.1 §3.2 |
| D4 | ★ only where you pass the five-level test; the floor named | Stars everywhere | 01.2 §4, §8 |
| D5 | Hard constraints backed by evidence; costs quantified; triggers | "Everyone knew" | 01.3 §2 |
| D6 | Kill criteria decide; the chosen option concedes something; champions named | Strawmen | 02.1 §7–§8 |
| D7 | Every number labeled; every [E] re-derivable from inputs | Memorized precision | 02.2 §11 |
| D8 | 5 levels × 3 wells; level 5 has real failure modes | Level 3 masquerading as 5 | 01.1 §11 |
| D9 | Detection signal and latency; your own root cause if true | "We fixed it" | 01.1 §7.6 |
| D10 | At least one bad decision owned; time anchors | "Nothing" | 02.3 |
| D11 | Passes `pace_check.py`; RESERVE where interviewers take over | A lecture | 01.1 §8 |
| D12 | Clean under both lints; sounds natural spoken aloud | Written, not spoken | 01.2 §13 |

---

## 4. A filled example: P-0 Beacon

This is the composite exhibit from Folder 01 in dossier form. It shows the density the harness expects. It is a composite, so don't copy its facts.

<!-- dossier:start name=beacon-filled -->
### D1. Headline

Beacon is the configuration and feature-flag distribution platform for about 1,200 services and 48,000 instances in 3 regions. It replaced 55-minute redeploys and ZooKeeper's global 2-second pushes, which caused 2 Sev-1s in 12 months. I was tech lead of 6 engineers: I wrote the RFC and designed the snapshot protocol, the fail-static SDK and the ring-based rollout controller, and I led the migration of 300 ZooKeeper services before a hard data-center exit. Outcome: p99 24 s propagation within ring, 3 bad changes halted in a 1% ring, 0 config Sev-1s in 12 months. Hooks: the snapshot protocol and the last-known-good failure.

### D2. Context and forcing functions

- **Users and scale:** ~1,200 services, ~48,000 instances at peak, ~270 config changes a day.
- **Before-state:** static YAML redeploys (median 55 min); dynamic flags in one 5-node ZooKeeper ensemble in us-east, read by ~300 services through 4 client libraries; every write global in ~2 s.
- **Incidents or pain events:**
  - A1, Sev-1, 38 min: a global percentage typo.
  - A2, Sev-1, 52 min: a session-expiry storm; a default disabled the rate limiter.
  - A3, Sev-2, 20 min: a full disk blocked a kill switch.
- **Forcing functions:**
  - the colo lease ended at M9 (extension: 6-month minimum at ~$190k/month);
  - a SOC 2 finding on open ACLs, due M6.
- **Out of scope:** secrets; per-request experiment assignment.

### D3. Goals and kill criteria

| ID | Goal | Threshold | Measurement | Source | Kind |
|---|---|---|---|---|---|
| G1 | Blast radius of a bad change | ≤ 1% of instances for ≤ 5 min | Ring membership × time to halt | Incident history A1 | Kill |
| G2 | Propagation within a ring | p99 ≤ 30 s | SDK applied-version reports | Platform SLO | Kill |
| G3 | Fail-static reads | 0 reads failing on control-plane outage | Chaos test + SDK metrics | Incident history A2 | Kill |
| G4 | Read cost | p99 < 1 µs in process | JMH + production sampling | Ranking and checkout latency budgets | Kill |
| G5 | Auditability | 100% of changes attributable and reversible | Change-log completeness query | SOC 2 / PCI change control | Kill |

### D4. Ownership ledger

| Component | Mark | My verbs | Artifact | I can speak to at depth | My floor |
|---|---|---|---|---|---|
| Publisher | ★ | Designed; wrote builder, canonicalizer, signer, size guard | RFC §3–4; ~6k lines in 41 PRs | Header layout, canonical form, KMS signing, leader lease | Announcer retry tuning (another engineer) |
| SDK (Java) | ★ | Designed semantics; wrote the reference | RFC §7; Java SDK | Verification order, swap, LKG, on_missing, reconnect jitter | Python and Node ports |
| Rollout controller | ★ | Designed; co-wrote | RFC §8 | Rings, bake times, gates, insufficient-signal hold | Metrics adapter (co-author) |
| ZooKeeper bridge | ★ | Designed; wrote the comparator; led the migration | Migration plan | Shadow mode, compat-shim template, cutover order | Individual teams' shims |
| Relay tier | ◆ | Reviewed the protocol; specified Watch | RFC §6 | The contract and threat model | Flow control, keepalive, autoscaling |
| Config API, Postgres | ○ | Consumed | — | What they guarantee Beacon | Internals |

### D5. Constraint ledger

| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| K1 | ZooKeeper ensemble gone before the colo lease ends (M9) | Deadline | Facilities lease; finance | Hard | Contract end date; extension quote of ~$190k/month, 6-month minimum | Per-namespace cutover by M8; deltas and diff viewer descoped | 2 features deferred ~2 quarters | Expires at decommission |
| K2 | SOC 2 finding: open ACLs on the ensemble | Regulatory | Auditor via security team | Hard | Written finding due M6 | mTLS proxy + ACLs as a compensating control by M5 | 3 engineer-months of throwaway work | Deleted at M9 |
| K3 | PCI services need ticketed approval per change | Regulatory | Payments compliance lead | Hard | Policy clause read with the compliance lead | Per-namespace change policy field | ~1 business day per payments change | Policy or scope change |
| K5 | 18% of instances have no mesh sidecar | Legacy | Mesh inventory | Soft | 82% coverage at M0 | Relay tier instead of xDS | ~0.5 engineer of relay operations | Coverage ≥ 95% |

### D6. Options matrix

| Criterion | Weight | O1 Postgres polling | O2 Mesh xDS | O3 Relay tier + snapshots |
|---|---|---|---|---|
| Atomic multi-key snapshot + ring pointer | KILL | fail: per-row reads | pass | pass |
| Reaches at least 95% of instances | KILL | pass | fail: 82% coverage | pass |
| Operational cost | 3 | 5 | 4 | 2 |
| Implementation effort | 3 | 4 | 3 | 2 |
| Blast-radius control | 4 | 2 | 3 | 5 |
| Champion | - | platform architect | SRE lead | me (tech lead) |
| Chosen | - | - | - | yes |

### D7. Numbers card

| Number | Value | Label | Re-derive |
|---|---|---|---|
| Instances at peak | ~48,000 | [M] | Platform inventory |
| Polling load | 4,800 QPS | [E] | 48,000 ÷ 10 s |
| Replica load test | 12,000 QPS | [M] | Point-read load test |
| Streams per relay | ~1,800 | [E] | 48,000 ÷ 27 relays |
| Widest fan-out | ~864 MB per change | [E] | 48,000 × 18 KB |
| Canary ring size | ~480 instances | [E] | 1% × 48,000 |
| Propagation | p99 24 s | [M] | SDK applied-version reports |
| Snapshot cap | 4 MB | [D] | Publisher size guard |
| INC-B7 exposure | ~140 instances, 0.3% | [E] | 140 ÷ 48,000 |
| Exposure reduction | ~860× | [E] | 48,000 × 38 min ÷ (528 × 4 min) |

### D8. Deep wells

| Level | Well 1: snapshot protocol | Well 2: rollout gating | Well 3: ZooKeeper migration |
|---|---|---|---|
| 1 What | Immutable, versioned, signed snapshots | A ring pointer advanced by health gates | Dual-read shadow, then per-namespace cutover |
| 2 How | Canonicalize → hash → cap → sign → blob → announce; verify → version gate → swap → LKG | Ring0 5 min, ring1 15 min; canary vs baseline on error ratio and p99 | SDK reads both; compat shim; mismatch metrics per key |
| 3 Why | Monotonic versions for replay defense; content addressing for stateless relays | Static schedules can't stop a bad change; baselines absorb traffic swings | Hyrum's law: consumers depended on quirks |
| 4 Why not | Deltas (complexity at 18 KB); per-key versions (no atomic change); decrement rollback (replay) | Fixed timers; absolute thresholds; manual approval for all | Big-bang cutover; dual-write |
| 5 What breaks | Truncated LKG; KMS outage halts publishes; lagging relay pointers rejected | Low-traffic namespaces lack signal (2,000-request minimum); correlated regressions | Intentional changes create mismatch noise; flapping namespaces; forever-cached znodes |

### D9. Failure story

1. **Detection.** The defaults-served signal jumped from 0 to 0.3% of instances; the on-call paged me within 2 minutes.
2. **Bounding.** Applied-version reports showed only restarted ring0 instances, about 140, were affected.
3. **Mitigation.** The relay deploy was rolled back; recovery took 6 minutes.
4. **Root cause.** I wrote the LKG file in place without fsync, so a hard stop left a truncated file, and the SDK fell back to defaults.
5. **Fix.** Temp file, fsync, rename, directory fsync; 2 generations; a per-namespace on_missing policy.
6. **Systemic change.** A CI chaos test kills the process during the LKG write; an alert fires on defaults served above 0.
7. **My role.** I owned the root cause, the fix and the postmortem; the SRE partner had asked about mid-write failure in review, and I answered incompletely.

### D10. Hindsight ledger

| ID | Decision | Known then | Known now | Class | Change today | Cost of current design | Trigger to act |
|---|---|---|---|---|---|---|---|
| B1 | Compiled-in defaults as the fallback | A2 showed 1 default disabling a rate limiter | INC-B7: 140 instances served defaults for 6 min | Bad decision, bad outcome | Required on_missing policy at namespace creation | 1,340 namespaces on an inferred policy | Now: 1-quarter campaign |
| B2 | Relay tier instead of xDS | Sidecar coverage 82% at M0 | Coverage 97% at M14 | Good decision, good outcome | Re-run the xDS prototype | ~0.5 engineer of relay operations | Coverage at or above 95% (met) |
| B3 | Break-glass enforced by naming | Safety-by-naming was a known weak pattern in month 4 | 1 harmless misuse in 14 months | Bad decision, good outcome | Schema-enforced kill-switch type | ~2 engineer-weeks; 1 misuse | Before the next safety review |

### D11. Whiteboard script

```script
# plan: Beacon - dossier version (compact)
== 00:00-02:00 | Intros
SAY: I'm a staff engineer on a platform team, working on configuration and deployment safety.
ASK: I'd suggest my config distribution platform, where I made the core decisions. Does that work?
RESERVE: 60
== 02:00-04:00 | Headline
DRAW: title and role line
SAY: Beacon is the configuration and feature-flag distribution platform for about 1,200 services and
48,000 instances in 3 regions. It replaced 55-minute redeploys and ZooKeeper's global 2-second pushes,
which caused 2 Sev-1s in 12 months. I was tech lead of 6 engineers: I wrote the RFC and designed the
snapshot protocol, the fail-static SDK and the ring-based rollout controller, and I led the migration of
300 ZooKeeper services before a hard data-center exit. The outcome: p99 24 seconds within a ring, 3 bad
changes halted in a 1% ring, and 0 config Sev-1s in 12 months. The 2 parts worth going deep on are the
snapshot protocol and a failure in the last-known-good path.
ASK: Shall I start with the context?
== 04:00-09:00 | Context (C4 L1)
DRAW: context strip
DRAW: numbers column
DRAW: incidents A1 to A3 and the 2 dates
SAY: Static config needed a redeploy, median 55 minutes. Dynamic flags lived in 1 ZooKeeper ensemble
read by 300 services through 4 libraries, and every write reached every region in about 2 seconds. That
produced 3 incidents: a global typo, a session-expiry storm where a default disabled the rate limiter, and
a full disk that blocked a kill switch. The colo lease ended at month 9, and an audit finding was due at
month 6. My goals were a blast radius of at most 1% for at most 5 minutes, p99 propagation of 30 seconds
or less within a ring, reads that survive a control-plane outage, sub-microsecond in-process reads, and
every change attributable.
ASK: Clear enough to show the architecture?
RESERVE: 90
== 09:00-16:00 | Architecture (C4 L2)
DRAW: API and Postgres, team-owned
DRAW: validator and publisher, starred
DRAW: object store and 27 relays
DRAW: SDK, starred
DRAW: rollout controller, starred
DRAW: ZooKeeper bridge, dotted
SAY: Postgres is the source of truth. My publisher turns a namespace into an immutable snapshot with a
SHA-256 digest, a version that only goes up, an Ed25519 signature and a 4-megabyte cap, writes it to
regional object storage and announces a pointer to stateless relays. My SDK verifies the digest and
signature, refuses older versions, swaps 1 atomic reference and keeps a last-known-good copy on disk. My
rollout controller moves the ring pointer from a 1% canary to a region to everywhere, only while the
canary's error ratio and latency hold against the baseline.
ASK: Any questions on the data path?
ASK: I'd suggest the snapshot protocol for the deep dive. Which would you prefer?
RESERVE: 120
== 16:00-28:00 | Deep dive 1: snapshot protocol
DRAW: publisher components
DRAW: SDK verification order
SAY: 3 invariants: snapshots are immutable, versions per namespace only go up, and a client never applies
what it cannot verify. Rollback publishes old content under a new version, a change I made after the
security reviewer showed that a decrement would let a replayed pointer downgrade the fleet.
ASK: Publish side or consume side first?
RESERVE: 420
ASK: Shall I move to the failure?
== 28:00-38:00 | Deep dive 2: failure INC-B7
DRAW: failure timeline
SAY: INC-B7: a relay brownout and a node-pool restart hit at once, and about 140 canary instances found a
truncated last-known-good file. The root cause was mine: I wrote it in place without fsync. The fix was
temp file, fsync, rename and directory fsync, 2 generations, and a per-namespace readiness policy.
ASK: Want more on the readiness trade-off?
RESERVE: 360
== 38:00-44:00 | Trade-offs: three options
DRAW: options table
SAY: Postgres polling carried the load at 40% of 1 replica, and it lost on atomic snapshots and staging.
The mesh option lost on 82% sidecar coverage. The relay tier costs about half an engineer to operate.
ASK: Deeper on any of the 3?
RESERVE: 180
== 44:00-49:00 | Impact and how I drove it
SAY: Propagation p99 24 seconds within a ring, 0 config Sev-1s in 12 months against 2 before, and pages
from about 11 to about 2 a month. 300 ZooKeeper services moved by month 8 through a shadow gate.
ASK: More on the migration?
RESERVE: 180
== 49:00-52:00 | Hindsight
SAY: I'd make the readiness policy mandatory at namespace creation, and I'd re-run the mesh prototype now
that coverage is 97 percent.
ASK: What else would help you?
RESERVE: 60
== 52:00-60:00 | Their questions, then mine
RESERVE: 360
ASK: How does your team stage config changes compared with code?
ASK: What is the hardest operational problem your team owns?
```

### D12. Tellings

#### My telling: headline

> Beacon is the configuration and feature-flag distribution platform for about 1,200 services and 48,000 instances in 3 regions. Before it, a change took 55 minutes through a redeploy or reached every instance in 2 seconds through ZooKeeper, which caused 2 Sev-1s in 12 months. I was tech lead of 6 engineers: I wrote the RFC, designed the snapshot protocol, the fail-static SDK and the rollout controller, and led the migration of 300 services before a hard data-center exit. Twelve months later, p99 propagation inside a ring was 24 seconds, 3 bad changes stopped in a 1% ring, and config pushes caused 0 Sev-1s.

#### My telling: decision

> I compared 3 options. Postgres polling would have carried the load, at about 40% of 1 replica in my load test, so I rejected it on semantics, not scale: it has no atomic multi-key snapshot and no ring pointer, so the 1% blast-radius goal would mean rebuilding staging in 4 client libraries. The SRE lead's mesh option failed on 82% sidecar coverage in a 1-week prototype we scoped together. The relay tier I chose is the most expensive to run, about half an engineer, and I kept 2 things from the losers: Postgres as the source of truth and the mesh's workload identities.

#### My telling: failure

> INC-B7 was a Sev-2 of 6 minutes, and the root cause was mine. A relay brownout and a node-pool restart coincided, and about 140 canary instances found a truncated last-known-good file, because I had written it in place without an fsync. The defaults-served signal paged the on-call within 2 minutes, and the applied-version reports bounded it to restarted canary instances. I changed the write to temp file, fsync, rename and directory fsync, kept 2 generations, and added a per-namespace readiness policy, and a CI chaos test now kills the process mid-write.

#### My telling: hindsight

> I'd make the on_missing policy a required field when a namespace is created. At the time, I treated compiled-in defaults as a safe fallback, although A2 had already shown 1 default disabling a rate limiter, so INC-B7 in month 7 was the cost of a missed inference. 1,340 namespaces still run on an inferred policy, and I'd close that now with a 1-quarter campaign that requires the field on the next edit of each namespace.
<!-- dossier:end -->

---

## 5. From dossier to RFC (and back)

If your project never had a written RFC, the dossier *is* the reconstruction. Present it as "the design as I'd document it today" and never as a document that existed. If an RFC did exist, map its sections to the dossier's to find the gaps:

| RFC section | Dossier section | Typical gap the dossier exposes |
|---|---|---|
| Background / motivation | D2 | Pain without numbers |
| Goals / non-goals | D3, D2 (out of scope) | Goals without thresholds or sources |
| Design | D4, D8 | Design without ownership marks or failure modes |
| Alternatives considered | D6 | Strawmen; no champions |
| Risks / constraints | D5 | Constraints without costs or triggers |
| Rollout / migration | D8 Well 3, D11 | No two-writer rules, no shadow phase |
| Operations | D9, D10 | No failure story; no hindsight |

---

## 6. The whiteboard script skeleton

The D11 script uses the notation from 01.1 §8. For your own plan, keep the canonical windows from 01.1 §2 and adjust them only with a reason. The non-negotiables, all checked by `pace_check.py`:
- a headline under 90 s;
- ≥ 3 numbers in the context section;
- ≤ 7 min of context;
- a deep dive starting by 20:00 at the latest;
- a checkpoint at least every 5 min;
- a timeline that ends at 60:00.

Put RESERVE time where interviewers take over: the deep dives and the trade-offs.

---

## 7. Tellings: how you describe your preparation

Interviewers occasionally ask how you prepared, or whether you "have notes". Both are ways of asking whether your knowledge is yours.

### 7.1 "Did you write this down beforehand?"

#### How an L5 tells it

> Yeah, I basically memorized a script for this project so I wouldn't forget anything. I have most of the numbers written down somewhere.

#### How an L7 tells it

> I wrote it down the way I'd write an RFC: the goals with their thresholds, the 3 options with who argued for each, every number with how it was measured or derived, and the decisions I'd change. Writing it showed me 2 numbers I couldn't re-derive, so I went back to the load-test report and the incident tracker for them. I don't read from it in the room; I prepared it so that whatever you ask, I either know the answer or know exactly where my knowledge stops.

### 7.2 "Which number are you least sure of?"

#### How an L5 tells it

> I'm pretty confident in all of them. They're basically from our dashboards, so they should be accurate.

#### How an L7 tells it

> The fan-out figure, 864 megabytes per change on the widest namespace, is the one I'd hedge. It's derived from the 18-kilobyte median snapshot, and the widest namespace's snapshot is about 22 kilobytes, so the real number is closer to 1 gigabyte; I quote the derivation rather than a measurement because egress was never instrumented per change. Everything I labeled as measured comes from the inventory, the SDK reports or the incident tracker, and I can name the query for each.

---

## 8. Hiring-committee scoring rubric: dossier readiness

| Dimension | Not ready | Borderline | Ready (L6) | Ready (L7) |
|---|---|---|---|---|
| **Completeness** | Placeholders remain | Sections filled, thin | All 12 sections pass the harness | Plus every FAIL fixed with real facts, not by deleting rows |
| **Ownership** | Stars everywhere | Stars with artifacts | Stars with artifacts and floors | Floors named before they're probed; co-authors credited |
| **Numbers** | Unlabeled | Labeled | Labeled + re-derivable | Plus the least-certain number named, with why |
| **Decisions** | One option | Three options | Kill criteria, champions, concessions | Plus close calls and their tie-breakers |
| **Failure and hindsight** | None | One story | 7 steps; one bad decision owned | Root cause in own work if true; a lesson applied since |

---

## 9. The stress-test harness

### 9.1 Listing L14: `dossier_check.py`

<!-- listing:dossier_check.py -->
```python
#!/usr/bin/env python3
"""dossier_check.py - the stress-test harness for a filled project dossier.

A dossier is Markdown with twelve sections headed exactly "### D1. ..." to
"### D12. ...". Dossiers may be embedded in a larger file between
    <!-- dossier:start name=<label> -->  ...  <!-- dossier:end -->
or the whole file is treated as one dossier. For each dossier:

  structural checks (built in)
    S1 all twelve sections present          S2 no {{placeholder}} left
    S3 ownership ledger: >= 1 star row, each star row names an artifact and a floor
    S4 numbers card: every row labeled [M]/[E]/[D]; every [E] row has a re-derivation
    S5 deep wells: 3 wells x 5 levels, all filled
    S6 failure story: the 7 numbered steps
  tool checks (the knowledge base's own listings, imported from this directory)
    T1 pace_check.py        D11 script passes
    T2 ownership_lint.py    D12 tellings ("#### My telling: ...") are clean
       constraint_check.py  ... and free of blame/excuse framing
    T3 constraint_check.py  D5 constraint ledger passes
    T4 options_matrix.py    D6 options matrix has no structural flags
    T5 hindsight_check.py   D10 hindsight ledger passes; the hindsight telling has a time anchor

Verdict per dossier: READY only if every check passes. Dossiers whose name
starts with "blank" are expected to be NOT READY (an unfilled template).
Usage: python -I dossier_check.py <file.md>   (all tool listings in the same directory)
"""
import importlib.util
import pathlib
import re
import sys
from types import SimpleNamespace

HERE = pathlib.Path(__file__).resolve().parent
SECTIONS = 12


def tool(name):
    path = HERE / f"{name}.py"
    if not path.exists():
        return None
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def split_sections(text):
    parts = re.split(r"^### (D\d+)\. .*$", text, flags=re.M)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts) - 1, 2)}


def first_table(body):
    rows = [r for r in body.splitlines() if r.strip().startswith("|")]
    return [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]


def check(name, text, mods):
    res = []
    sec = split_sections(text)
    missing = [f"D{i}" for i in range(1, SECTIONS + 1) if f"D{i}" not in sec]
    res.append(("S1 sections", not missing, f"missing {missing}" if missing else "12/12"))
    holes = re.findall(r"\{\{[^}]+\}\}", text)
    res.append(("S2 placeholders", not holes, f"{len(holes)} unfilled" if holes else "none"))

    t = first_table(sec.get("D4", ""))
    stars = [r for r in t[2:] if len(r) >= 6 and "★" in r[1]]
    bad = [r[0] for r in stars if any(not c or "{{" in c for c in (r[3], r[5]))]
    res.append(("S3 ownership", bool(stars) and not bad,
                f"{len(stars)} star row(s)" + (f"; missing artifact/floor: {bad}" if bad else "")))

    t = first_table(sec.get("D7", ""))
    rows = t[2:]
    unlabeled = [r[0] for r in rows if len(r) < 4 or not re.search(r"\[(M|E|D)\]", r[2])]
    underived = [r[0] for r in rows if len(r) >= 4 and "[E]" in r[2] and len(r[3].strip("—- ")) < 3]
    res.append(("S4 numbers", bool(rows) and not unlabeled and not underived,
                f"{len(rows)} number(s); unlabeled {len(unlabeled)}; [E] without derivation {len(underived)}"))

    t = first_table(sec.get("D8", ""))
    filled = [r for r in t[2:] if len(r) >= 4 and all(c and "{{" not in c for c in r[1:4])]
    res.append(("S5 deep wells", len(filled) >= 5 and len(t[0]) >= 4 if t else False,
                f"{len(filled)}/5 levels filled for 3 wells"))

    steps = re.findall(r"^\s*([1-7])\. \*\*", sec.get("D9", ""), re.M)
    res.append(("S6 failure story", sorted(set(steps)) == [str(i) for i in range(1, 8)],
                f"{len(set(steps))}/7 steps"))

    if mods.pace:
        plans = mods.pace.parse_plans(sec.get("D11", ""))
        if plans:
            a = SimpleNamespace(wpm=130.0, draw_sec=8.0, reply_sec=15.0, max_monologue=300.0, total="60:00")
            _, flags, _ = mods.pace.analyse(plans[0], a)
            res.append(("T1 pacing", not flags, "PASS" if not flags else "; ".join(f.split(":")[0] for f in flags)))
        else:
            res.append(("T1 pacing", False, "no ```script block in D11"))

    tells = re.findall(r"^#### My telling: (\S+).*\n\n((?:>.*\n?)+)", sec.get("D12", "") + "\n", re.M)
    if mods.own and mods.con:
        dirty = []
        for label, block in tells:
            body = " ".join(l[1:].strip() for l in block.splitlines())
            flags, _, _ = mods.own.lint(body)
            plain = re.sub(r"[*_`]", "", body)
            framing = [r for r, rx in mods.con.FRAMING if rx.search(plain)]
            if flags or framing or "{{" in body:
                dirty.append(label)
        res.append(("T2 tellings", bool(tells) and not dirty,
                    f"{len(tells)} telling(s)" + (f"; flagged: {dirty}" if dirty else "; all clean")))

    if mods.con:
        t = first_table(sec.get("D5", ""))
        probs = mods.con.check_ledger("D5", t) if len(t) >= 3 else ["no ledger rows"]
        res.append(("T3 constraints", not probs, f"{max(len(t) - 2, 0)} row(s), {len(probs)} problem(s)"))

    if mods.opt:
        block = "\n".join("| " + " | ".join(r) + " |" for r in first_table(sec.get("D6", "")))
        try:
            opts, scored, kills, meta = mods.opt.parse(block + "\n")
            _, _, _, flags, _ = mods.opt.audit("D6", opts, scored, kills, meta)
            res.append(("T4 options", not flags, "no flags" if not flags else "; ".join(f.split(":")[0] for f in flags)))
        except (ValueError, IndexError, AttributeError) as e:
            res.append(("T4 options", False, f"unparseable matrix ({type(e).__name__})"))

    if mods.hind:
        t = first_table(sec.get("D10", ""))
        probs = mods.hind.check_ledger("D10", t) if len(t) >= 3 else ["no ledger rows"]
        anchor = [b for l, b in tells if l.lower().startswith("hindsight")]
        anchored = bool(anchor) and bool(mods.hind.ANCHOR.search(anchor[0]))
        res.append(("T5 hindsight", not probs and anchored,
                    f"{len(probs)} ledger problem(s); time anchor {'present' if anchored else 'missing'}"))
    return res


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    md = open(sys.argv[1], encoding="utf-8").read().replace("\r\n", "\n")
    mods = SimpleNamespace(pace=tool("pace_check"), own=tool("ownership_lint"), con=tool("constraint_check"),
                           opt=tool("options_matrix"), hind=tool("hindsight_check"))
    found = [n for n, m in vars(mods).items() if m]
    print(f"dossier_check: tools loaded {len(found)}/5 ({', '.join(found)})")
    dossiers = re.findall(r"<!-- dossier:start name=(\S+) -->\n(.*?)<!-- dossier:end -->", md, re.S) or [("file", md)]
    ok = True
    for name, text in dossiers:
        res = check(name, text, mods)
        fails = [r for r in res if not r[1]]
        print()
        print(f"dossier {name}")
        for label, passed, detail in res:
            print(f"  {'PASS' if passed else 'FAIL'}  {label:<17} {detail}")
        state = "READY" if not fails else f"NOT READY ({len(fails)} of {len(res)} checks failing)"
        print(f"  => {state}")
        ok &= (not fails) != name.startswith("blank")
    print()
    print("verdict:", "OK (blank templates NOT READY, filled dossiers READY)" if ok else "CHECK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 9.2 Output on the blank template and the filled Beacon dossier

<!-- output:dossier_check.py -->
```text
dossier_check: tools loaded 5/5 (pace, own, con, opt, hind)

dossier blank-template
  PASS  S1 sections       12/12
  FAIL  S2 placeholders   89 unfilled
  FAIL  S3 ownership      1 star row(s); missing artifact/floor: ['{{component}}']
  PASS  S4 numbers        1 number(s); unlabeled 0; [E] without derivation 0
  FAIL  S5 deep wells     0/5 levels filled for 3 wells
  PASS  S6 failure story  7/7 steps
  FAIL  T1 pacing         LATE-DEPTH; TIMELINE
  FAIL  T2 tellings       4 telling(s); flagged: ['headline', 'decision', 'failure', 'hindsight']
  FAIL  T3 constraints    1 row(s), 3 problem(s)
  PASS  T4 options        no flags
  FAIL  T5 hindsight      3 ledger problem(s); time anchor present
  => NOT READY (7 of 11 checks failing)

dossier beacon-filled
  PASS  S1 sections       12/12
  PASS  S2 placeholders   none
  PASS  S3 ownership      4 star row(s)
  PASS  S4 numbers        10 number(s); unlabeled 0; [E] without derivation 0
  PASS  S5 deep wells     5/5 levels filled for 3 wells
  PASS  S6 failure story  7/7 steps
  PASS  T1 pacing         PASS
  PASS  T2 tellings       4 telling(s); all clean
  PASS  T3 constraints    4 row(s), 0 problem(s)
  PASS  T4 options        no flags
  PASS  T5 hindsight      0 ledger problem(s); time anchor present
  => READY

verdict: OK (blank templates NOT READY, filled dossiers READY)
```

**Reading the output.**
- **The blank template fails almost everything.** That's the point: each FAIL is a section an interviewer would find empty.
- **The Beacon dossier is READY:**
  - all twelve sections are present, with no placeholders;
  - the ownership ledger has 4 starred rows, each with an artifact and a floor;
  - every number is labeled;
  - 3 wells × 5 levels are filled, and the failure story has all 7 steps;
  - the script passes the pacing check;
  - the 4 tellings are clean;
  - the constraint ledger, options matrix and hindsight ledger pass, and the hindsight telling has its time anchor.

Run it on your own dossier until it says READY. Then go to 05.2.

---

## 10. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | Invented numbers to pass S4 | A number you can't defend under derivation | "Unknown; I'd check X" beats a fabrication (§0) |
| F2 | Deleting rows to pass | A thin ledger that passes | Fix the row, don't remove it |
| F3 | Stars to look senior | ★ without depth | Downgrade to ◆ (01.2 §8) |
| F4 | Reading the dossier aloud | Written prose, unnatural speech | Rehearse the tellings spoken; re-lint after |
| F5 | One dossier for every company | Same emphasis everywhere | Re-order for the lens (01.1 §14) |
| F6 | Never updated | Stale numbers from 2 years ago | Re-verify the numbers card before each loop |
| F7 | A fictional RFC | Claiming a document existed | Present it as a reconstruction (§5) |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "Give me the 90-second version."</b></summary>

**Initial Prompt.** Minute 2: "Before anything else: 90 seconds, the whole project."

**L5 Answer.** The candidate starts with the company's history and the team structure, reaches the architecture at minute 3, and never states their own role.

**Why L5 Stalls.** There's no scale, no pain number, no role and no outcome in the first 90 seconds, which are exactly the 4 things the interviewers need to calibrate every later question.

**L7 Answer.** The candidate delivers D1 as written: the system with its scale in units, the two-sided pain (55 minutes / 2 seconds) with its incident count, the role as a list of artifacts, the outcome restating the pain metrics, and the 2 hooks. They stop at 80 seconds and ask whether the project suits the interviewers' goals. The dossier made it possible to say exactly this much and no more.

</details>

<details><summary><b>Q2 · "Which of your numbers are you least sure of?"</b></summary>

**Initial Prompt.** "You've given me a dozen numbers. Which one would you bet least on?"

**L5 Answer.** "I'm confident in all of them. They came from our monitoring."

**Why L5 Stalls.** Every numbers card has a weakest entry. Claiming none signals that the candidate doesn't know which numbers were measured and which were derived.

**L7 Answer.** "The widest-namespace fan-out, 864 megabytes per change. It's derived, from 48,000 instances times the 18-kilobyte median, and the widest namespace is closer to 22 kilobytes, so the real figure is nearer 1 gigabyte. Egress per change was never instrumented. The measured ones (instances, propagation p99, incident counts) each come from a specific system, and I can name it."

</details>

<details><summary><b>Q3 · "Recite your RFC's alternatives section."</b></summary>

**Initial Prompt.** "If I opened your design doc to the alternatives section, what would I read?"

**L5 Answer.** "We considered a couple of other approaches but they didn't fit as well."

**Why L5 Stalls.** No names, no champions, no kill criteria. It's a strawman section, recited as one.

**L7 Answer.** "3 options and Option Zero. Option Zero, fixing the ZooKeeper clients plus a staging layer, died on the colo exit. Postgres polling, the platform architect's option, carried the load and failed on atomic snapshots and staging. Mesh xDS, the SRE lead's option, failed on 82% sidecar coverage in a prototype we scoped together. The relay tier won and is the most expensive to run. And there's a fourth I'd add today: Kafka compacted topics, rejected in my notes before the draft, because reviewers asked about it twice."

</details>

<details><summary><b>Q4 · "Remove one constraint. Which changes your design most?"</b></summary>

**Initial Prompt.** "Pick the constraint that, if it vanished, would change Beacon the most."

**L5 Answer.** "Probably the deadline, since we'd have had more time."

**Why L5 Stalls.** "More time" isn't a design change, and the deadline (by the candidate's own ledger) changed features, not architecture.

**L7 Answer.** "K5, mesh coverage. Without it, the relay tier, the biggest piece of new infrastructure, isn't needed, and config rides the mesh's existing streams. The deadline cost 2 features but no architecture. The PCI change policy improved the design, so I wouldn't remove it. That's also why K5 is the one with a live revisit trigger, now met at 97% coverage."

</details>

<details><summary><b>Q5 · "List what you personally wrote."</b></summary>

**Initial Prompt.** "Code and documents, by name. What came out of your keyboard?"

**L5 Answer.** "A lot of the core system. I was involved in most of the components."

**Why L5 Stalls.** "Involved in most" is the passenger tell (01.2 §5.2), and the interviewer asked for names.

**L7 Answer.** "The RFC, sections 3 to 8. The publisher's builder, canonicalizer, signer and size guard, about 6,000 lines in 41 PRs. The Java SDK reference. The rollout controller's gate evaluator, co-written. The shadow-diff comparator. The INC-B7 postmortem. Not the relays, not the Go, Python or Node SDKs, not the API, and not the metrics adapter, which was my co-author's."

</details>

<details><summary><b>Q6 · "Your failure story. What was the false lead?"</b></summary>

**Initial Prompt.** "Every real incident has a wrong first hypothesis. What was yours in INC-B7?"

**L5 Answer.** "We figured out pretty quickly it was the file, so there wasn't really a false lead."

**Why L5 Stalls.** Real incidents almost always have one. "Pretty quickly" without a timeline suggests the story was learned from the postmortem, not lived (01.2 T9).

**L7 Answer.** "That the relays were serving stale pointers. The brownout started with a relay deploy, so for the first 3 minutes I assumed the bad deploy had published old versions, and I checked the version gate's rejection counter. It was flat, which ruled that out. Then the defaults-served metric pointed at instances that had restarted, and the SDK logs showed signature failures on the LKG file at startup, which led to the in-place write."

</details>

<details><summary><b>Q7 · "Which of your three deep wells is the shallowest?"</b></summary>

**Initial Prompt.** "You offered 3 areas to go deep on. Which one would I get to the bottom of fastest?"

**L5 Answer.** "I know them all equally well."

**Why L5 Stalls.** Uniform depth is the tour guide's profile (01.2 T12). The honest answer locates the floor, which is the calibration signal.

**L7 Answer.** "The rollout gating. I designed the model and the evaluator, but the statistics of the low-traffic hold, the 2,000-request minimum, came from my co-author's analysis. I can explain why it exists and what it costs, about 4% of changes held, but not the power calculation behind the exact threshold. The protocol and the migration I can take 5 levels down."

</details>

<details><summary><b>Q8 · "If I read your design doc, what would surprise me?"</b></summary>

**Initial Prompt.** "Tell me something in the RFC that I wouldn't guess from your diagram."

**L5 Answer.** "Probably how much detail went into the error handling."

**Why L5 Stalls.** It's generic. The question rewards a specific, non-obvious decision that only the author would think to mention.

**L7 Answer.** "That the validator runs the consumer's own parser. It's 1 paragraph of the RFC and it shapes a lot: 12 parser versions in a sandbox, a validator change whenever an SDK version is retired, and it's the reason a config can't be 'valid by schema but crash the consumer', the class of failure in the CrowdStrike findings. And that rollback is a roll-forward, which surprises people until they see the replay argument."

</details>

---

## 12. Checklist

- [ ] The blank template (§2) copied and every `{{…}}` replaced with real facts.
- [ ] `dossier_check.py` reports READY, with every FAIL fixed rather than deleted (§9).
- [ ] The 4 D12 tellings rehearsed aloud, and re-linted after rephrasing.
- [ ] The least-certain number identified, with why (Q2, §7.2).
- [ ] The shallowest well identified, with your floor (Q7).
- [ ] The numbers card re-verified within a week of the interview.
- [ ] The dossier re-ordered for each company's lens (01.1 §14).
- [ ] The probe plan generated and a mock run (05.2).

---

## 13. References

- Michael Nygard, "Documenting Architecture Decisions" (ADRs, the decision-record form behind D6 and D10). <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
- Simon Brown, The C4 model (the zoom levels behind D11). <https://c4model.com/>
- Google re:Work, "A guide to structured interviewing for better hiring practices" (the evidence the dossier is built to produce). <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
- Will Larson, StaffEng, "Staff archetypes" (scope and role vocabulary for D4). <https://staffeng.com/guides/staff-archetypes/>
