# 01.3 · Framing Constraints: Legacy Tech Debt, Client Politics, and Tight Deadlines

> **Folder:** `01-Anatomy-of-the-60-Minute-Deep-Dive-Round` · file 3 of 3
> **Question this file answers:** every real architecture is bent by constraints: inherited systems, stakeholders with their own incentives, dates you didn't choose. How do I present those constraints so the interviewers hear *judgment under constraint* rather than *excuses for a compromised design*?
> **Running exhibit:** P-0 "Beacon" ([01.1 §3](01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md#3-the-running-exhibit-p-0-beacon-fact-sheet)), plus one composite consulting engagement (§4.5).
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L3 `constraint_check.py` | Python 3, standard library | Validates constraint-ledger tables: nine columns, valid category and hardness, evidence rather than belief for Hard constraints, a quantified cost and a revisit trigger. Also lints tellings for blame, excuse, absolute and "politics" language. | [§12](#12-the-constraint-checker), on the two ledgers and all tellings in this file. The gate also runs it on every telling in Folder 01. |

**Verification.** The gate extracts the listing from this file and checks it byte for byte against the source that was run. It then re-runs the listing on this file and compares the result with the output block in §12. The gate requires the L5 ledger to fail and the Beacon ledger to pass. Across Folder 01, every L5 telling must be flagged by this checker or by [`ownership_lint.py`](02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md#13-the-ownership-lint), and every L7 telling must be clean in both. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

Constraints are where deep-dive rounds are won and lost in a particular way. They explain every decision that looks suboptimal from outside: the interim proxy, the shortened test window, the system of record you would never have chosen. That makes them the most useful context you have. They are also the easiest place to hide weak judgment, which is why experienced interviewers probe them hard. A constraint stated as a fact ("we had a deadline") invites three questions: was it real, what did it cost, and what did you do about it? This file shows how to answer those questions before they are asked.

The three classes the round cares about most:
- **Legacy and tech debt** (§3): the systems and quirks you inherited, and the debt you took on.
- **Stakeholder constraints**, colloquially "client politics" (§4): the people and teams whose incentives bounded your design, including clients in consulting engagements.
- **Deadlines** (§5): dates you didn't choose.

Regulatory constraints get a short treatment in §6. Folder 04 file 03 covers them in depth.

---

## 1. First principles: constraints are design inputs, not excuses

### 1.1 Why interviewers probe constraints

Every system on the whiteboard is the unconstrained optimum minus what the constraints took away. Interviewers know that. What they're testing is whether **you** know it:
- **Do you know what the unconstrained design would have been?** If not, you can't explain what the constraint cost.
- **Did you test whether the constraint was real?** Many constraints are folklore: "payments never allows that", "the client will never accept it".
- **Did you price it?** Cost of honoring versus cost of breaking.
- **Did you design around it intelligently,** or simply comply?
- **Did you change it?** At L7, some constraints are things you remove, negotiate or turn into a standard.

### 1.2 The six properties of a well-framed constraint

| Property | Question it answers | Beacon example (colo deadline) |
|---|---|---|
| **Source** | Who or what imposes it? | The facilities lease; finance owns the extension decision |
| **Hardness** | Hard, Soft or Negotiable, and how do you know? | Hard: a contract end date, and an extension quote of a 6-month minimum at ~$190k/month |
| **Cost of honoring** | What did respecting it take away? | Delta snapshots and the diff viewer descoped; a shorter shadow window for ~60% of namespaces |
| **Cost of breaking** | What would ignoring it have cost? | ~$1.14M of lease (6 × $190k), plus another 6 months of ZooKeeper risk |
| **Design consequence** | What did you do because of it? | The interim compliance control; per-namespace cutover; descoping |
| **Revisit trigger** | When does it stop applying, or need re-examination? | It expired with the lease at M9. The descoped items had their own triggers (§5.4). |

A constraint that you can describe on all six properties is evidence. A constraint you can describe only by name is an excuse waiting to be challenged.

### 1.3 Context or excuse: how the same fact reads two ways

| Constraint stated as an excuse | The same constraint stated as context |
|---|---|
| "We had a hard deadline so we couldn't do proper testing." | "The lease ended at M9. The critical path was the 7-day shadow window, so I shortened it to 3 days for namespaces under 100 instances, with the director's sign-off and a risk-register entry." |
| "The legacy system was a mess." | "The ZooKeeper design fit its 2016 constraints: about 20 services and 1 region. By 2023 its per-key, single-region model produced A1 and A2." |
| "Payments blocked us." | "Payments is accountable for PCI scope; their change control needed an approver and a ticket for each change. I made change policy a per-namespace field." |
| "Management forced us to use Oracle." | "The client owned the decision and chose Oracle because their support contract covered it. I priced the alternative, they signed the risk register, and I isolated Oracle behind a CDC boundary." |

**The pattern.** An excuse ends at the constraint. Context *starts* at the constraint and goes on to the decision, the cost and the trigger. §8 turns that into a sentence template.

### 1.4 Chesterton's fence and Hyrum's law: test before you remove

G. K. Chesterton's parable of the fence (*The Thing*, 1929, in the chapter "The Drift from Domesticity") gives the first rule of legacy work: before you remove something whose purpose you don't know, find out why it was put there. Hyrum's law ([hyrumslaw.com](https://www.hyrumslaw.com/)) gives the second: even when you know why it was put there, consumers may depend on behaviors nobody intended. Beacon's shadow diff (212 mismatches in 37 services) was the engineering answer to both. Saying so names a principle and then gives the evidence, which is the L7 pattern.

### 1.5 What each level does with a constraint

| Level | Typical behavior | How it sounds |
|---|---|---|
| L5 | Lists constraints and complies | "We had to use Oracle." |
| L6 | Designs around constraints and prices them | "Oracle was required, so I isolated it behind CDC; that cost 3 weeks and saved a later migration." |
| L7 | Also changes constraints: tests them, negotiates them, removes them, converts them into reusable requirements or standards | "I found that PCI change control allowed retroactive approval for emergency kill switches, so break-glass works for payments too. Then I made change policy a namespace field that 6 other teams adopted." |

---

## 2. The constraint ledger

The ledger is your private, structured record of every constraint that shaped the design. It has nine columns, and `constraint_check.py` (§12) enforces the rules for each.

| Column | Rule |
|---|---|
| **ID** | Short label you can refer to aloud ("K3") |
| **Constraint** | One sentence, specific |
| **Category** | Legacy · Stakeholder · Deadline · Regulatory · Budget · Skills · Scale |
| **Source** | A person (by role), a document, a contract or a system |
| **Hardness** | Hard (cannot be moved by you or your management chain) · Soft (could be moved at some cost) · Negotiable (moved by asking) |
| **Evidence it was real** | What you checked. For Hard, it must be evidence, not belief: never "everyone knew", "assumed", "we were told". |
| **Design consequence** | What you did because of it |
| **Cost paid** | Quantified: engineer-months, weeks, dollars, latency, features deferred |
| **Revisit trigger** | The event that would make you re-examine it, or its expiry |

### 2.1 A ledger that fails (typical L5 preparation)

<!-- ledger:start name=l5-ledger -->
| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| C1 | ZooKeeper is legacy | Legacy | — | Hard | everyone knew it was bad | Replace it | lots of effort | — |
| C2 | Deadline from management | Deadline | Management | Hard | we were told it was fixed | Rush the migration | overtime | TBD |
| C3 | Payments team politics | Politics | Payments | Hard | assumed | Exception for payments | some delay | never |
<!-- ledger:end -->

Every row fails, and each failure maps to an interviewer probe:
- C1 has no source and no cost ("what did it cost?").
- C2's evidence is hearsay ("was the date real?").
- C3 uses "politics" as a category and as an explanation ("what was payments actually accountable for?").

### 2.2 The Beacon ledger (passes)

<!-- ledger:start name=p0-beacon -->
| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| K1 | ZooKeeper ensemble must be gone before the us-east colo lease ends (M9) | Deadline | Facilities lease; finance owns any extension | Hard | Lease end date in the contract; extension quote: 6-month minimum at ~$190k/month | Interim compliance control; per-namespace cutover by M8; descoped deltas and the diff viewer | 2 features deferred ~2 quarters; 3-day shadow window accepted for ~60% of namespaces | Expires at decommission (M9) |
| K2 | SOC 2 finding: open ACLs and no client authentication on the ensemble | Regulatory | External auditor, through the security team | Hard | Written audit finding with remediation due at M6 | mTLS proxy plus per-path ACLs as a compensating control, shipped M5 | 3 engineer-months of deliberately throwaway work | Deleted with the ensemble at M9 |
| K3 | PCI-scoped services need a ticketed approval for every production change | Regulatory | Payments compliance lead (PCI change-management policy) | Hard | Policy clause read with the compliance lead; emergency clause allows retroactive approval within 24 h | Per-namespace change policy: approval, ticket link, manual ring advance | Payments changes take ~1 business day instead of ~20 min; 1 more required field per namespace | Any change to payments' change-management policy or PCI scope |
| K4 | ~300 services depend on observable quirks of 4 ZooKeeper client libraries | Legacy | Consuming teams' code (Hyrum's law) | Hard | Shadow diff: 212 semantic mismatches in 37 services | Shadow mode, a compat-shim template, a 7-day zero-unexplained-mismatch gate | ~15 engineer-months of migration support | Each shim carries a deletion date; delete when the owning team's last legacy reader migrates |
| K5 | 18% of instances (batch, legacy VMs) have no service-mesh sidecar | Legacy | Mesh inventory | Soft | Mesh coverage 82% at M0, rising ~1 point a month | Dedicated relay tier instead of xDS (option O2 rejected) | ~0.5 engineer of ongoing relay operations | Mesh coverage at or above 95% (reached 97% at M14: revisit) |
| K6 | 6 engineers; no headcount for non-Java SDKs | Budget | Director's annual headcount plan | Negotiable | Headcount plan; 1 open requisition, unfilled until M5 | Java reference SDK plus a conformance suite; ports by the language-platform teams | Go/Python/Node SDKs ~2 months behind Java at launch | A port falling more than 1 minor version behind the reference |
| K7 | SRE will not take on-call for a new tier without runbooks and SLOs | Stakeholder | SRE lead (team on-call charter) | Negotiable | The on-call charter document; confirmed with the SRE lead in week 2 | Relay on-call stays with the relay team; SLOs and runbooks shipped before GA | ~3 weeks added before GA | Charter revision, or the relay tier changing hands |
<!-- ledger:end -->

### 2.3 Speaking a ledger row aloud

Never recite the ledger; it's preparation, not a slide. When a constraint comes up, deliver one row as one sentence (§8): "Because the audit finding was due in month 6 and the migration would finish in month 8, I shipped a compensating control in month 5: an mTLS proxy and per-path ACLs. It cost 3 engineer-months of deliberately throwaway work, and it was deleted with the ensemble in month 9."

---

## 3. Legacy and tech debt

### 3.1 Respect the legacy, even when you replace it

Interviewers are almost always people who have *built* legacy systems. They will hear "the old system was garbage" as "this candidate will call my system garbage in two years". Describe legacy in terms of the constraints it was designed under and the constraints that changed:

> "It was right for [its original constraints]. [What changed] made it wrong for us. Here is the evidence."

This framing is also more accurate. Most legacy systems were reasonable answers to past constraints. Treating them as stupidity means misunderstanding why they look the way they do, and that misunderstanding is how migrations break hidden dependencies.

### 3.2 A taxonomy of debt you can speak to

Ward Cunningham's original debt metaphor compared shipping first-time code to taking on debt: a little speeds development, *as long as it is paid back*. The danger is debt that is never repaid ([Cunningham, OOPSLA '92](http://c2.com/doc/oopsla92.html)). Martin Fowler's [Technical Debt Quadrant](https://martinfowler.com/bliki/TechnicalDebtQuadrant.html) adds a useful classification: **deliberate or inadvertent**, crossed with **prudent or reckless**.

| Quadrant | What it means | Beacon example | How to talk about it |
|---|---|---|---|
| Prudent, deliberate | "We know this is a shortcut; we'll pay it back" | The interim mTLS proxy (K2); full snapshots instead of deltas | Name the interest rate and the payoff plan |
| Prudent, inadvertent | "Now we know how we should have done it" | Writing the LKG in place (INC-B7). The fsync discipline was known; I didn't apply it. | Own it; describe what you learned and the systemic fix |
| Reckless, deliberate | "No time for design" | (Not in Beacon.) If yours has one, own it and show what changed. | Never present it as normal; show the consequence and the correction |
| Reckless, inadvertent | "What's layering?" | Inherited: the 4 client libraries, each defaulting differently on failure | Describe it neutrally, as inherited; show how you discovered and contained it |

### 3.3 Debt you took on deliberately: interest and payoff

For every piece of debt you created on purpose, have three numbers: **principal** (what it saved you), **interest** (what it costs per period while it exists) and **payoff** (when and how it gets removed).

| Debt | Principal (saved) | Interest (ongoing cost) | Payoff plan | What happened |
|---|---|---|---|---|
| Interim mTLS proxy for ZooKeeper | Met the M6 audit date without finishing the migration | 3 engineer-months to build, plus ~2 pages/month of proxy alerts | Delete at decommission (M9) | Deleted at M9 |
| Full snapshots, no deltas | ~4 engineer-months of delta-protocol work before the deadline | ~864 MB per change at the widest fan-out | Revisit if the median snapshot exceeds 256 KB or fan-out egress exceeds 5% of the object-store bill | The median was 18 KB at M14, so it hadn't been triggered |
| Compat shims (37 services) | Migrated without forcing 37 teams to change semantics first | Each shim is code that translates legacy quirks | Each shim has a deletion date; tracked on the migration dashboard | 29 of 37 deleted by M14; 8 open, with owners |
| 3-day shadow window for small namespaces | ~3 weeks of schedule | Less mismatch-detection time for ~60% of namespaces | Expired with the migration | 0 cutover rollbacks |

### 3.4 Hyrum's law in practice: the behavior inventory

Before replacing a legacy system, inventory what consumers depend on, not what the documentation promises. Beacon's dual-read shadow mode is one technique. Others:
- **Traffic capture and replay** against the new system, comparing responses.
- **Contract tests** generated from observed production calls.
- **Schema or field usage analysis:** which fields are read by whom.
- **A deliberate brownout** of a legacy behavior in a staging or canary environment, to see who complains.

Beacon's most dangerous finding was in one Python library that treated an *empty* znode as `false` and a *missing* one as `true`. Fourteen unfinished features were switched off by empty znodes. The first version of the exporter skipped empty znodes, so in Beacon those keys were simply missing. The library's semantics, faithfully emulated by its compat shim, would then have read them as `true` and enabled all 14 features at once. The shadow diff flagged all 14 as mismatches within the first hour. The fix had two parts: the exporter writes empty znodes as an explicit `false`, and each owning team replaced the implicit semantics with an explicit value before its shim could be deleted.

### 3.5 Migration patterns as answers to constraints

| Pattern | What it is | The constraint it answers | Beacon use |
|---|---|---|---|
| **Strangler fig** ([Fowler](https://martinfowler.com/bliki/StranglerFigApplication.html)) | Grow the new system around the old one, moving functionality piece by piece until the old one can be removed | "Can't stop the world": a big-bang cutover is too risky | Per-namespace cutover |
| **Branch by abstraction** ([Fowler](https://martinfowler.com/bliki/BranchByAbstraction.html)) | Put an abstraction in front of the old implementation, build the new one behind it, switch | Many call sites; can't change them all at once | The SDK's config interface fronted both the ZooKeeper and Beacon readers |
| **Parallel change** (expand / migrate / contract) ([Fowler](https://martinfowler.com/bliki/ParallelChange.html)) | Add the new form, migrate the consumers, remove the old form | Breaking interface changes with many consumers | Compat shims: expand (shim), migrate (owning team fixes), contract (delete shim) |
| **Shadow / dual-read** | Read both, serve the old, compare | Unknown consumer dependencies (Hyrum's law) | 212 mismatches found before cutover |
| **Dual-write vs CDC** | Write to both systems, or stream changes from the old one | System of record can't move yet | Used in the consulting case (§4.5): CDC out of Oracle |

### 3.6 Describing the legacy system

#### How an L5 tells it

> The old ZooKeeper setup was garbage, honestly. It was built years ago by people who had left, and nobody understood it. The client libraries were a total mess. We had no choice but to replace the whole thing.

#### How an L7 tells it

> The ZooKeeper design fit the company when it was built in 2016: about 20 services, 1 region, flags changed a few times a week, and a per-key model was the simplest thing that worked. By 2023 it served 300 services in 3 regions through 4 client libraries, and 2 of its properties caused our incidents: per-key writes had no staging, which gave us A1, and a single-region ensemble with library-specific failure defaults gave us A2. Before replacing it, I ran a 2-month shadow diff to inventory what consumers depended on beyond the documented behavior, and it found 212 mismatches in 37 services, including a library that treated a missing znode as true. The design wasn't wrong for 2016. It was wrong for 2023, and I needed proof of what it was doing before I removed it.

---

## 4. Stakeholder constraints ("client politics")

### 4.1 Rename "politics" to incentives and accountability

"Politics" is a red-flag word in this round (§10). It frames other people's legitimate incentives as obstacles, and it suggests you can't operate across an organization, which is the core L6/L7 skill. Replace it with a question: **what is this stakeholder accountable for, and what are they afraid of?** Almost every "political" conflict turns out to be a mismatch between two legitimate accountabilities.

### 4.2 The Beacon stakeholder map

| Stakeholder (by role) | Accountable for | Feared | Needed from me | I needed from them | Outcome |
|---|---|---|---|---|---|
| Payments compliance lead | PCI scope and audit evidence | Uncontrolled changes in in-scope systems | An approval trail per change | Agreement that per-namespace policy satisfies the control | Change policy field; payments onboarded M7 with 0 exceptions |
| SRE lead | Fleet reliability; on-call health | A new tier with no runbooks; on-call load | Runbooks, SLOs, a clear on-call owner | Fair evaluation of the relay tier against xDS | Joint exit criteria; prototype; relay on-call stays with the relay team (K7) |
| Security reviewer | Threat model; audit findings | Replay and downgrade attacks; open ACLs | Monotonic versions; signed snapshots; the K2 control | Timely review | Revision 1 of the RFC |
| Director | Delivery date; risk | Missing the lease; a migration outage | Options with prices when behind | Decisions on scope and risk acceptance | The shortened window approved (§5.5) |
| 37 owning teams with mismatches | Their services' behavior | Being forced to change semantics under deadline | A shim template, a dashboard, office hours | Fixes on their own schedule, within the gate | 29 of 37 shims deleted by M14 |
| Platform architect | Platform data strategy | Yet another datastore | Postgres staying the source of truth | Acceptance of the change-log schema | The log, with me owning compaction (01.2 §5.4) |

### 4.3 The conversion technique: turn a demand into a typed requirement

The most powerful L7 move with stakeholder constraints is to **convert a one-off demand into a general, typed requirement**: policy as data rather than an exception. The payments team's demand could have been handled with an exception ("payments namespaces skip the rollout controller"). That would have been fast, and it would have created a second code path, an unaudited special case, and a precedent for every other team to request one. Converting it into a per-namespace `change_policy` field had three effects:
1. It satisfied payments without special-casing them.
2. It made the policy visible and auditable for everyone.
3. Six other teams later used the same field, for reasons that had nothing to do with PCI.

The same move produced `on_missing` after INC-B7. **A constraint handled as data scales; a constraint handled as an exception multiplies.**

### 4.4 Pre-wiring, escalation and losing gracefully

- **Pre-wire.** Before the formal review of a contested design, meet the key stakeholders one-on-one: ask what evidence they need, and show them the section that affects them. Beacon's payments outcome came from a 30-minute meeting with the compliance lead *before* the RFC review, not from the review.
- **Escalate with options, not complaints.** When you need a decision above you, bring 2–3 priced options and a recommendation (§5.5). "We're blocked by payments" is a complaint; "here are two ways to satisfy payments' control, with costs, and I recommend the first" is an escalation.
- **Disagree, then commit.** Amazon's principle names it ("Have Backbone; Disagree and Commit": leaders "respectfully challenge decisions when they disagree… Once a decision is determined, they commit wholly", [LPs](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)). When you lost a decision, say so, say what you did to make the chosen option succeed, and say in hindsight who was right.
- **Credit the stakeholder whose constraint improved the design.** K3 made Beacon better. Saying so shows you understand that constraints carry information.

### 4.5 Client constraints in consulting and services engagements

Many strong candidates come from consulting, outsourcing or professional-services backgrounds, where the **client** owns the architecture decision, a statement of work bounds the scope, and the commercial model (fixed bid or time and materials) shapes incentives. Interviewers sometimes discount such projects: "the client decided, so what did *you* architect?" (⚠ reported). The defense is to show architecture judgment **inside** the client's authority:

| Move | What it shows | Example (composite engagement) |
|---|---|---|
| **Options memo** | You framed the decision, even if you didn't make it | 3 options for the system of record, each with cost, risk and timeline |
| **Priced recommendation** | Judgment, stated in the client's terms | "Managed Postgres: 11 weeks faster; ~$140k/year lower license cost for the new schema" |
| **Risk register with sign-off** | You made the risk visible and transferred the decision properly | The client's architect signed the register's Oracle entry |
| **Design for the chosen option** | Professionalism: you made their choice succeed | Isolated Oracle behind a CDC boundary so new services never queried it |
| **Outcome tracking** | You care about the client's long-term outcome, not being right | 14 months later the client moved to Postgres in 6 weeks, because only 1 service touched the database |

#### How an L5 tells it

> The client's architect insisted on using their old Oracle setup, which was stupid, and it wasn't my call, so we just did what they said. It made everything slower and it was really political.

#### How an L7 tells it

> The client owned the platform decision, and their chief architect required the existing Oracle cluster as the system of record because their DBA team's support contract covered only Oracle. I wrote a 3-option memo recommending managed Postgres and priced both paths: Oracle added about 11 weeks of integration work and roughly $140k a year in licenses for the new schema. The client chose Oracle and signed the risk register entry I wrote. I then designed for their choice: a CDC feed out of Oracle so the 9 new services never queried it directly, which kept the license footprint on the existing cores. 14 months later the client moved to Postgres in 6 weeks, because the CDC boundary meant only 1 service touched the database.

### 4.6 The payments constraint in Beacon

#### How an L5 tells it

> The payments team was really political and blocked us for weeks because of PCI. Management made us carve out an exception for them, which was a mess to maintain.

#### How an L7 tells it

> The payments team is accountable for PCI scope, and their change-management control required a ticketed approval for any production change to an in-scope service. My first draft auto-advanced every change through rings, which their control couldn't accept. Before the RFC review I met their compliance lead and asked what an auditor needs to see: an approver, a ticket and a record of what changed. I added a per-namespace change policy as a first-class field, with approval required, a ticket link required and manual ring advance. Payments onboarded in month 7 with 0 exceptions, and 6 other teams later used the same field for their own reasons.

---

## 5. Deadlines

### 5.1 A deadline taxonomy, and the test that sorts them

| Type | Examples | Typical hardness | The test |
|---|---|---|---|
| **External, contractual** | Lease end, license expiry, a contract go-live, a regulator's date | Hard | What happens the day after? Who pays, and how much? |
| **External, event** | A peak sales event, a product launch, a sporting event | Hard (the event moves for nobody) | What's the cost of being late versus being wrong on the day? |
| **Internal dependency** | Another team's launch that needs your system | Soft to Hard | Can they launch without you, at what cost? |
| **Internal planning** | A quarter's OKR, a roadmap commitment | Soft | Who set it, and what did they base it on? |
| **Arbitrary** | "End of month sounds right" | Negotiable | Ask what it's protecting; often nothing |

**The test is "what happens the day after we miss it, and who pays?"** For Beacon's colo date, the answer was a $190k/month lease extension for a 6-month minimum, plus 6 more months running the system that had caused two Sev-1s. Hard, and priced. For an OKR date, the answer is usually "a yellow status on a slide", and saying so (politely) is a legitimate move.

### 5.2 The levers, and the one you never pull

Under a date you can't move, there are five levers:
1. **Scope:** cut or defer features (§5.4).
2. **Sequence:** reorder the work so the critical path starts earlier.
3. **Staffing:** adding people, with the caveat in Brooks's law that "adding manpower to a late software project makes it later" (Fred Brooks, *The Mythical Man-Month*, anniversary edition, ISBN 0-201-83595-9). Staffing helps only on parallelizable work that newcomers can ramp onto fast.
4. **Risk acceptance:** interim mitigations, shortened validation, explicitly approved (§5.5).
5. **Reversibility:** favor decisions that are cheap to undo. Amazon's 2015 shareholder letter distinguishes "one-way doors" from "two-way doors", and calls for very different care with each ([Amazon 2015 letter](https://s2.q4cdn.com/299287126/files/doc_financials/annual/2015-Letter-to-Shareholders.PDF)). Under a deadline, push your risk into the two-way doors.

**The lever you never pull is safety.** You may shorten a validation window, with sign-off and a bound. You may not remove the rollout halt or the validator. Interviewers listen for this line. "We skipped the safety checks to make the date" is disqualifying at L6+.

### 5.3 Deadline math: find the real critical path

Most deadline stories fail because the candidate describes effort ("we worked really hard") rather than structure ("the critical path was X, and here is what I did to it"). For Beacon:

| Work stream | Duration | Parallelizable? | On the critical path? |
|---|---|---|---|
| Build publisher, SDK, controller | M1–M4 | Yes (3 owners) | No: finished early |
| Shadow mode per namespace | ≥ 7 clean days each | Across namespaces, yes; within one, no (calendar time) | **Yes.** Calendar time, not effort. |
| Mismatch fixes by 37 owning teams | Their backlog | Across teams, yes | **Yes,** for those 37 |
| Interim audit control | 3 engineer-months, due M6 | Independent | A separate hard date |
| Cutover waves | M6–M8 | Limited by the blast-radius ordering | Follows the shadow window |

**Insight:** the critical path was calendar time (the 7-day shadow window) and other teams' backlogs, not Beacon engineering effort. More engineers on Beacon would not have moved the date (Brooks). The real levers were a shorter shadow window where the risk was low, and earlier engagement with the 37 owning teams (the shim template shipped in M3 so they could start before cutover). This is the analysis interviewers want: the constraint, its structure, and the lever that actually acts on it.

### 5.4 Descoping as a decision, with a revisit trigger

| Cut | Saved | Why it was safe to cut | Revisit trigger | Status at M14 |
|---|---|---|---|---|
| Delta snapshots | ~4 engineer-months | 18 KB median; full snapshots cost ~864 MB at the widest fan-out | Median > 256 KB, or egress > 5% of the object-store bill | Not triggered |
| UI diff viewer | ~6 engineer-weeks | Diffs were available through the CLI and in the audit log | 3+ teams asking, or a change-review incident | Built in M11 after 5 team requests |
| Python port parity at launch | (another team's work) | Python services were 9% of instances, and all had LKG | Port more than 1 minor version behind | Reached parity at M7 |

### 5.5 A deliberate, bounded shortcut

#### How an L5 tells it

> The deadline was impossible, honestly, because management just picked a date. We had no time to do proper testing, so we cut corners on the shadow phase and shipped it anyway.

#### How an L7 tells it

> The colo lease ended 9 months after approval, and missing it meant a 6-month extension at about $190k a month, so the date was hard. In month 6 I was 3 weeks behind on cutovers. The critical path was the shadow window, 7 clean days per namespace, so adding engineers would not have moved the date. I took 2 options to the director: shorten the shadow window to 3 days for namespaces under 100 instances, about 60% of them, or drop the diff viewer and delta snapshots from scope. The director approved both. We finished 2 weeks before the lease end with 0 cutover rollbacks, and I recorded the shortened window in the risk register with an expiry: it ended with the migration.

**Why it works.**
- **The date's hardness has a price.**
- **The behind-ness is quantified** (3 weeks at month 6).
- **The critical path is identified,** and with it the reason staffing wouldn't act on it.
- **The shortcut is bounded:** only small namespaces, only during the migration.
- **It was approved at the right level** and recorded, so the risk was explicit rather than silent.
- **The outcome is stated,** with the risk acceptance's own expiry.

### 5.6 If you missed the deadline

Missing a date isn't disqualifying. Hiding it is, and so is blaming it on others. The structure:
1. State the miss plainly: by how much, and the cost.
2. Say what you saw coming, and when.
3. Say what you did when you saw it.
4. Name the root cause in planning, including your own part.
5. Say what you do differently now.

"We missed the cutover date by 5 weeks. I saw it at the halfway point, when the mismatch rate wasn't falling. I raised it with 2 options then, not at the deadline. The root cause was my estimate: I planned for mismatches in 10 services and found 37. Now I run the dependency inventory before I commit to a date." That answer scores well, because it shows the planning maturity the interviewers are looking for.

---

## 6. Regulatory and compliance constraints (preview)

Regulatory constraints are usually the hardest and the least negotiable, and they come with someone else's evidence requirements. Folder 04 file 03 covers security, compliance, multi-tenancy and day-2 operations in depth. For framing purposes, three rules:
1. **Know the control, not just the regulation.** "PCI" is a regime. "Ticketed approval for changes to in-scope systems, with emergency retroactive approval within 24 hours" is a control you can design for.
2. **Distinguish remediation from compensating controls.** K2's mTLS proxy was a compensating control accepted until the permanent remediation (decommission). Say which is which.
3. **Know what the auditor sees.** Design the evidence (access logs, approval records, the audit trail in G5) along with the control.

#### How an L5 tells it

> Security came in at the last minute with audit stuff and made us add mTLS in front of ZooKeeper, which was a total distraction from the real work.

#### How an L7 tells it

> The audit finding was due in month 6 and the migration would finish in month 8, so deleting ZooKeeper could not close it in time. I proposed a compensating control: an mTLS proxy in front of the ensemble plus per-path ACLs, 3 engineer-months, shipped in month 5. The security lead accepted it as the interim remediation, with decommission as the permanent fix, and the auditor received the proxy's access logs as evidence. It was throwaway work by design, so I gave it a deletion date of month 9, and it was deleted in month 9.

---

## 7. Constraint stress tests: the probes interviewers use

| Probe | What it tests | Strong answer pattern |
|---|---|---|
| "Was that constraint real?" | Whether you tested it | The evidence column: what you read, who you asked, and what turned out softer than believed |
| "Who imposed it? Did you push back?" | Source and agency | The source by role; what you negotiated; what you accepted and why |
| "What would you have built without it?" | Whether you know the unconstrained optimum | §9: the unconstrained design and the delta |
| "What did honoring it cost?" | Quantification | The cost-paid column, in units |
| "Is it still there?" | Whether constraints expire | The revisit trigger, and what happened when it fired |
| "Isn't that just an excuse for X?" | Separating constraint from choice | "The constraint forced A. The choice of B within A was mine, for this reason." |
| "Would you make the same call today?" | Hindsight | Same call, or different, with the reason (Folder 02 file 03) |

### 7.1 Testing a constraint

#### How an L5 tells it

> Everyone knows you can't touch the payments services without a change ticket, so we didn't even try to include them in the automatic rollout.

#### How an L7 tells it

> I checked it rather than assuming it. I read the change-management policy with the payments compliance lead and asked which clause applied. It required approval for any change to an in-scope system, and config that alters runtime behavior counted, so the constraint was real. One part was softer than the team believed: emergency kill switches could proceed with retroactive approval within 24 hours. That is why the break-glass lane works for payments too, and it was used twice in the first year.

---

## 8. The constraint-decision-cost-trigger sentence

The single most useful sentence shape for this round:

> **Because** [constraint, with its source and evidence], **I** [decision], **which cost** [quantified cost]. **I'd revisit it when** [trigger].

| Constraint | The sentence |
|---|---|
| K1 deadline | "Because the colo lease ended at M9 and an extension cost ~$190k a month for at least 6 months, I descoped deltas and the diff viewer, which deferred 2 features by about 2 quarters. I revisit the deltas if the median snapshot passes 256 KB." |
| K4 legacy quirks | "Because 300 services depended on undocumented library behavior, I required 7 clean shadow days per namespace, which cost about 15 engineer-months of migration support. Each shim is deleted when its team's last legacy reader goes." |
| K5 mesh coverage | "Because 18% of instances had no sidecar, I built a relay tier instead of using xDS, which costs about half an engineer of operations. I'm revisiting it now, since coverage passed 95%." |
| K3 PCI | "Because PCI change control requires a ticketed approval per change, I made change policy a per-namespace field, which makes payments changes take about a day instead of 20 minutes. It changes if their policy or scope changes." |
| Consulting Oracle | "Because the client's support contract covered only Oracle, I put Oracle behind a CDC boundary, which cost 11 weeks of integration. That boundary is what let them leave Oracle in 6 weeks later." |

**Keep the "I".** Constraints are often phrased in the passive ("it was decided that…"). The sentence template forces a first-person decision inside the constraint. That is exactly the distinction interviewers are scoring (01.2 §5).

---

## 9. The unconstrained design: know your ideal and the delta

For every major constraint, know what you'd have built without it. Interviewers ask this to find out whether your design was shaped by judgment or merely by circumstance.

| Constraint | What it forced | Without it, I would have… | When the ideal becomes worth it |
|---|---|---|---|
| K1 (deadline) | Full snapshots; no diff viewer; a shorter shadow window | Built delta snapshots behind a size threshold; a 7-day window everywhere | Median > 256 KB (deltas); never for the window (it was a deadline-only risk) |
| K5 (mesh coverage) | The relay tier | Distributed config over xDS, with a small fallback poller for sidecar-less jobs | Now: coverage is 97% |
| K6 (headcount) | Java first; ports by other teams | Generated SDKs from one core (a shared Rust or C core with bindings), to remove port drift | When port drift causes an incident, or a 5th language arrives |
| K3 (PCI) | Manual ring advance for payments | (Nothing different: K3 improved the design) | — |

**K3's row is worth saying aloud.** Some constraints make the design *better*. Recognizing that, and saying it, shows you treat constraints as information rather than as opposition.

---

## 10. Red-flag language, and what to say instead

| Red flag | What the interviewer hears | Say instead |
|---|---|---|
| "Management forced us to…" | No agency; blames up | "The director set the date because of the lease cost; within it, I chose…" |
| "We had no choice." | Didn't look for options | "The options were A and B; I chose A because…" |
| "The legacy system was garbage." | Will trash my systems too; didn't understand the history | "It fit its 2016 constraints; these changed…" |
| "It was very political." | Can't work across an organization | "Team X is accountable for Y, so they needed Z…" |
| "They blocked us." | Adversarial framing | "Their control required X; I designed for it by…" |
| "It was impossible." | Didn't price it | "It would have cost X weeks / $Y, which I judged not worth it because…" |
| "That wasn't my call." | Disowns the outcome | "The decision belonged to [role]. I argued for X; here's how I made the chosen option work." |
| "There was no time to test." | Skipped safety | "I shortened validation for low-risk namespaces, with sign-off; the safety checks stayed." |
| "Everyone knows payments won't allow it." | Didn't test the constraint | "I read the policy with their compliance lead; here's what it actually required." |
| "The client was clueless." | Contempt for the customer | "The client's priority was X; I priced the alternative; they chose; I designed for their choice." |

---

## 11. Hiring-committee scoring rubric: constraint framing

Bands follow the poor / borderline / solid / outstanding vocabulary of Google's public structured-interviewing guidance ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). The anchors are a composite (⚠).

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Constraint as context** | Constraints as excuses or grievances | Constraints stated neutrally, no costs | Each constraint with source, hardness and cost | All six properties, plus a revisit trigger, unprompted |
| **Testing constraints** | Assumed | Accepted what was said | Verified the hard ones | Verified, and found softness others missed (the emergency clause) |
| **Pricing** | No numbers | Some costs | Cost of honoring and cost of breaking | The unconstrained design and the delta, in numbers |
| **Stakeholder framing** | "Politics"; blame | Neutral, but adversarial ("we vs they") | Accountabilities understood; designs for them | Converts demands into reusable, typed requirements; credits constraints that improved the design |
| **Deadline handling** | "No time", skipped safety | Worked harder | Found the critical path; descoped explicitly | Priced options escalated at the right time; bounded shortcuts with expiry; safety untouched |
| **Legacy respect** | Trashes predecessors | Neutral | Explains why the legacy made sense once | Inventoried actual dependencies (Hyrum) before removal (Chesterton) |
| **Agency** | Passive voice throughout | Agency on own tasks only | "I" for decisions within constraints | Also changed constraints: negotiated, removed, standardized |

---

## 12. The constraint checker

`constraint_check.py` does two jobs.
1. **It validates ledger tables** marked with `<!-- ledger:start name=… -->` / `<!-- ledger:end -->`: the column set and order, categories, hardness, empty cells, belief-backed Hard constraints, unquantified costs.
2. **It lints tellings** for blame, excuse, absolute and "politics" language.

Use it on your dossier's ledger (Folder 05 provides the template). A ledger that passes is not necessarily *true*; only you can verify the evidence column. A ledger that fails is guaranteed to give you trouble when the interviewers probe it.

### 12.1 Listing L3: `constraint_check.py`

<!-- listing:constraint_check.py -->
```python
#!/usr/bin/env python3
"""constraint_check.py - validate a constraint ledger and lint constraint framing.

Part 1 - ledger. Every Markdown table between
    <!-- ledger:start name=<label> -->  ...  <!-- ledger:end -->
must have the nine ledger columns, and each row must:
  * use a Category from CATEGORIES and a Hardness of Hard / Soft / Negotiable;
  * fill every cell (no "", "-", "TBD", "?", "n/a");
  * back a Hard constraint with evidence, not belief ("assumed", "everyone knew");
  * quantify the cost paid (at least one digit);
  * name a revisit trigger, so the constraint can expire.

Part 2 - framing. Every "#### How an L5/L7 tells it" blockquote is checked for
language that turns a constraint into an excuse or a grievance:
  BLAME     forced us / made us / their fault / incompetent / garbage ...
  EXCUSE    had no choice / no time to / not my call / out of my hands ...
  ABSOLUTE  impossible / no way / nobody / everyone knows / always fails ...
  POLITICS  "politics" / "political" used as the explanation

Usage: python -I constraint_check.py <file.md> [<file.md> ...]
Standard library only.
"""
import re
import sys

COLUMNS = ["ID", "Constraint", "Category", "Source", "Hardness",
           "Evidence it was real", "Design consequence", "Cost paid",
           "Revisit trigger"]
CATEGORIES = {"Legacy", "Stakeholder", "Deadline", "Regulatory", "Budget",
              "Skills", "Scale"}
HARDNESS = {"Hard", "Soft", "Negotiable"}
EMPTY = {"", "-", "—", "tbd", "?", "n/a", "na", "none"}
BELIEF = re.compile(r"\b(assumed|we thought|everyone knew|obviously|it was known|"
                    r"we were told|common knowledge)\b", re.I)

FRAMING = [
    ("BLAME", re.compile(
        r"\b(forced (us|me)|made us|didn't let us|wouldn't let us|their fault|"
        r"not my fault|stupid|incompetent|clueless|idiots?|garbage|crap|lazy|"
        r"blocked us|over the wall|dumped on us|useless)\b", re.I)),
    ("EXCUSE", re.compile(
        r"\b(had no choice|no choice but|no time to|there was no time|"
        r"didn't have time|(not|wasn't|was not|isn't) my (call|decision)|out of my hands|"
        r"above my pay grade|nothing (I|we) could do)\b", re.I)),
    ("ABSOLUTE", re.compile(
        r"\b(impossible|no way|nobody|everyone knows|always fails|"
        r"never works|completely broken|totally broken)\b", re.I)),
    ("POLITICS", re.compile(r"\b(politics|political)\b", re.I)),
]
HEADING = re.compile(r"^#### How an? (L\d) tells it\s*$")


def ledgers(md):
    out = []
    for m in re.finditer(r"<!-- ledger:start name=(\S+) -->\n(.*?)<!-- ledger:end -->", md, re.S):
        rows = [r for r in m.group(2).splitlines() if r.strip().startswith("|")]
        cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
        out.append((m.group(1), cells))
    return out


def check_ledger(name, cells):
    problems = []
    if len(cells) < 3:
        return [f"{name}: table has no data rows"]
    header, body = cells[0], cells[2:]
    if header != COLUMNS:
        missing = [c for c in COLUMNS if c not in header]
        problems.append(f"{name}: header mismatch; missing {missing or 'none'}, order must be {COLUMNS}")
        return problems
    col = {c: i for i, c in enumerate(header)}
    for row in body:
        rid = row[0] if row else "?"
        if len(row) != len(header):
            problems.append(f"{name}/{rid}: {len(row)} cells, expected {len(header)}")
            continue
        for c in COLUMNS:
            v = re.sub(r"[*_`]", "", row[col[c]]).strip()
            if v.lower() in EMPTY:
                problems.append(f"{name}/{rid}: empty '{c}'")
        cat, hard = row[col["Category"]], row[col["Hardness"]]
        if cat not in CATEGORIES:
            problems.append(f"{name}/{rid}: Category '{cat}' not in {sorted(CATEGORIES)}")
        if hard not in HARDNESS:
            problems.append(f"{name}/{rid}: Hardness '{hard}' not in {sorted(HARDNESS)}")
        ev = row[col["Evidence it was real"]]
        if hard == "Hard" and BELIEF.search(ev):
            problems.append(f"{name}/{rid}: Hard constraint backed by belief ('{BELIEF.search(ev).group(0)}')")
        if not re.search(r"\d", row[col["Cost paid"]]):
            problems.append(f"{name}/{rid}: 'Cost paid' has no number")
    return problems


def tellings(md):
    out, lines, i, in_fence = [], md.splitlines(), 0, False
    while i < len(lines):
        if lines[i].startswith("```"):
            in_fence = not in_fence
        m = None if in_fence else HEADING.match(lines[i])
        if m:
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            body = []
            while j < len(lines) and lines[j].startswith(">"):
                body.append(lines[j][1:].strip())
                j += 1
            out.append((m.group(1), " ".join(body)))
            i = j
            continue
        i += 1
    return out


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    seen = {"L5": [0, 0], "L6": [0, 0], "L7": [0, 0]}
    ledger_report = []
    n = 0
    for path in argv:
        md = open(path, encoding="utf-8").read().replace("\r\n", "\n")
        for name, cells in ledgers(md):
            probs = check_ledger(name, cells)
            ledger_report.append((name, max(len(cells) - 2, 0), probs))
        for level, text in tellings(md):
            n += 1
            plain = re.sub(r"[*_`]", "", text)
            hits = [(r, m.group(0)) for r, rx in FRAMING for m in rx.finditer(plain)]
            seen[level][0] += 1
            seen[level][1] += 1 if hits else 0
            if hits:
                print(f"T{n:02d} {level} framing: " + "; ".join(f"{r}: {h}" for r, h in hits))
    print()
    for name, nrows, probs in ledger_report:
        state = "PASS" if not probs else f"{len(probs)} problem(s)"
        print(f"ledger {name}: {nrows} row(s) -> {state}")
        for p in probs:
            print(f"    - {p}")
    print()
    for lvl in ("L5", "L6", "L7"):
        total, flagged = seen[lvl]
        if total:
            print(f"{lvl}: {total} telling(s), {flagged} with framing flags")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

### 12.2 Output on this file

<!-- output:constraint_check.py -->
```text
T01 L5 framing: BLAME: garbage; EXCUSE: had no choice; ABSOLUTE: nobody
T03 L5 framing: BLAME: stupid; EXCUSE: wasn't my call; POLITICS: political
T05 L5 framing: BLAME: blocked us; BLAME: made us; POLITICS: political
T07 L5 framing: EXCUSE: no time to; ABSOLUTE: impossible
T09 L5 framing: BLAME: made us
T11 L5 framing: ABSOLUTE: Everyone knows

ledger l5-ledger: 3 row(s) -> 10 problem(s)
    - l5-ledger/C1: empty 'Source'
    - l5-ledger/C1: empty 'Revisit trigger'
    - l5-ledger/C1: Hard constraint backed by belief ('everyone knew')
    - l5-ledger/C1: 'Cost paid' has no number
    - l5-ledger/C2: empty 'Revisit trigger'
    - l5-ledger/C2: Hard constraint backed by belief ('we were told')
    - l5-ledger/C2: 'Cost paid' has no number
    - l5-ledger/C3: Category 'Politics' not in ['Budget', 'Deadline', 'Legacy', 'Regulatory', 'Scale', 'Skills', 'Stakeholder']
    - l5-ledger/C3: Hard constraint backed by belief ('assumed')
    - l5-ledger/C3: 'Cost paid' has no number
ledger p0-beacon: 7 row(s) -> PASS

L5: 6 telling(s), 6 with framing flags
L7: 6 telling(s), 0 with framing flags
```

**Reading the output.**
- **The L5 ledger fails on every row.** Missing source, belief as evidence, an invalid category ("Politics" isn't a category; *Stakeholder* is), unquantified costs and empty triggers. Each failure is an interviewer probe you would have lost.
- **The Beacon ledger passes all 7 rows.**
- **Every L5 telling in this file trips the framing lint;** no L7 telling does. The gate (README) also checks that every L5 telling in Folder 01 is flagged by at least one of the two lints, and that every L7 telling is clean in both.

---

## 13. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | **Constraint as alibi** | "We had a deadline" explains every weakness | The six properties (§1.2); the sentence template (§8) |
| F2 | **Untested constraint** | "Everyone knew…" | Evidence column; test the hard ones (§7.1) |
| F3 | **Trashing the legacy** | "Garbage", "mess", "nobody understood it" | Its original constraints, then what changed (§3.1) |
| F4 | **"Politics"** | Stakeholders as obstacles | Accountabilities (§4.1); the stakeholder map (§4.2) |
| F5 | **Exception sprawl** | A special case per demanding team | Convert demands into typed requirements (§4.3) |
| F6 | **Effort instead of structure** | "We worked weekends" | Critical-path analysis (§5.3) |
| F7 | **Silent shortcuts** | Risk taken without sign-off or bound | Bounded, approved, recorded, with an expiry (§5.5) |
| F8 | **Safety traded for the date** | "We skipped the checks" | Never; say what you kept (§5.2) |
| F9 | **Debt with no payoff plan** | "We'll clean it up eventually" | Principal, interest, payoff (§3.3) |
| F10 | **No unconstrained design** | Can't answer "what would you have built?" | §9 table |
| F11 | **Disowning a lost decision** | "Not my call" | Disagree, then commit; say how you made it work (§4.4) |
| F12 | **Consulting discount** | "The client decided everything" | Options memo, priced recommendation, risk register, design for their choice (§4.5) |

---

## 14. Bar-raiser chains

<details><summary><b>Q1 · "Was the colo date real, or did someone just pick it?"</b></summary>

**Initial Prompt.** "Lots of 'hard' deadlines are made up. Was yours real? How do you know?"

**L5 Answer.** "It was definitely real. Leadership was very clear that it couldn't move, and the data center was closing."

**Why L5 Stalls.** "Leadership was very clear" is hearsay, not evidence. The candidate never priced the alternative, which suggests they never tested the date. A deadline you didn't test can't justify the shortcuts you took under it.

**L7 Answer.** "I tested it in week 3, because two of my design decisions depended on it. I asked finance what an extension would cost: a 6-month minimum term at about $190k a month, so roughly $1.14M, plus 6 more months of running the system behind 2 Sev-1s. That made it hard in practice, though not in principle: if the migration had been at risk of a Sev-1, $1.14M would have been the right price to pay, and I said so in the RFC's risk section. Knowing the price was what let me make the shortcut decision in month 6 rationally. A 3-day shadow window on small namespaces was a much cheaper risk than $1.14M."

</details>

<details><summary><b>Q2 · "Without the deadline, what would you have built differently?"</b></summary>

**Initial Prompt.** "Remove the colo deadline entirely. What changes in your design?"

**L5 Answer.** "We would have had more time for testing and probably made it more polished overall."

**Why L5 Stalls.** "More polished" says nothing about the design. Either the deadline changed no design decisions (in which case why mention it?) or the candidate doesn't know which ones it changed.

**L7 Answer.** "Three things, and one that wouldn't change. First, delta snapshots behind a size threshold. Full snapshots were fine at an 18 KB median, but I cut deltas for schedule, not on merit, and I'd have built them in a version 2 regardless. Second, a 7-day shadow window everywhere instead of 3 days for small namespaces. Third, the diff viewer at launch rather than in month 11. What wouldn't change: the protocol, the rings and the fail-static semantics. Those came from the incident history, not the date. So the deadline cost features and validation time; it didn't shape the architecture, and I kept it that way on purpose."

</details>

<details><summary><b>Q3 · "You keep criticizing ZooKeeper. Who built it, and were they wrong?"</b></summary>

**Initial Prompt.** The prober, who has clearly run ZooKeeper themselves: "You've blamed ZooKeeper for two Sev-1s. Who built that setup, and were they wrong?"

**L5 Answer.** "It was built before my time. I think they just didn't think about multi-region, which was a mistake."

**Why L5 Stalls.** It judges the past against today's constraints, and it blames the technology for what was a usage pattern. Both errors are visible to an experienced interviewer. "They didn't think about it" is unfalsifiable and uncharitable.

**L7 Answer.** "They weren't wrong for 2016: about 20 services in 1 region, a few flag changes a week. ZooKeeper was a reasonable, well-understood choice, and ZooKeeper itself did what it promises. Our incidents came from how it was used. A1 came from per-key writes with no staging layer above them; that's an application-level gap, not a ZooKeeper fault. A2 came from 4 client libraries each choosing a different failure default on session expiry. A properly configured client handles session expiry; ours didn't agree on what to do. A staged publisher in front of ZooKeeper could have fixed A1 without replacing it. The reasons to replace rather than repair were the colo exit, which was moving the ensemble anyway, and the cross-region client topology. Honestly, if the colo weren't closing, I'd have seriously considered fixing the clients and adding a staging layer on ZooKeeper."

</details>

<details><summary><b>Q4 · "Isn't payments' change policy just an exception with a nicer name?"</b></summary>

**Initial Prompt.** "You say you turned payments' demand into a 'typed requirement'. Isn't that just an exception with a nicer name?"

**L5 Answer.** "No, because it's in the data model, so it's cleaner than a hard-coded exception."

**Why L5 Stalls.** "Cleaner" is aesthetics. The interviewer is asking what's *functionally* different, and the answer must show properties an exception lacks.

**L7 Answer.** "Three functional differences. First, one code path. The rollout controller always evaluates `change_policy`; payments namespaces just have `approval: required`. An exception would be a second path, tested separately, and the first thing to rot. Second, it's auditable. Every namespace's policy is visible in one query, so the auditor gets evidence for all in-scope namespaces at once instead of trusting that the exception list is complete. Third, it's reusable: 6 other teams set `manual_advance` for reasons unrelated to PCI. One was a team whose canary cell had too little traffic for the gates to mean anything. If it were an exception, each of them would have asked for their own. The test I use is whether a second, unrelated team can use it without a code change. If they can, it's a requirement; if not, it's an exception."

</details>

<details><summary><b>Q5 · "Three engineer-months on a throwaway proxy. Why not spend them finishing the migration?"</b></summary>

**Initial Prompt.** "The mTLS proxy was deleted 4 months after it shipped. Why not put those 3 engineer-months into finishing the migration before the audit date?"

**L5 Answer.** "Because the audit was due and we had to show something to the auditors."

**Why L5 Stalls.** It doesn't answer the actual question, which was whether the migration could have been accelerated to meet M6 instead. The candidate hasn't shown they analyzed that alternative.

**L7 Answer.** "I analyzed exactly that. The migration's critical path was calendar time: 7 clean shadow days per namespace, plus 37 teams' mismatch fixes. 3 more engineer-months on Beacon would have moved the end date by days, not the 2 months needed. And closing the finding by M6 meant every namespace off ZooKeeper by M6, including payments, whose own change process put them last. So the real choice was the proxy or a missed audit finding. The proxy was cheap insurance. It also bought a second benefit: once the ACLs were in, the proxy's access logs gave us the first complete list of who read which znodes. That list was an input to the shadow diff, so not all of it was thrown away."

</details>

<details><summary><b>Q6 · "A shorter shadow window under deadline pressure is exactly how outages happen."</b></summary>

**Initial Prompt.** "You shortened validation to hit a date. That's the textbook way outages happen. Defend it."

**L5 Answer.** "It worked out fine, we had zero rollbacks, so I think it was the right decision."

**Why L5 Stalls.** Outcome bias: a good result doesn't prove a good decision. The interviewer wants the *reasoning at the time*, and evidence that the risk was bounded before the outcome was known.

**L7 Answer.** "The outcome doesn't defend it; the bound does. Four things made it a bounded risk rather than a corner cut. First, scope: only namespaces under 100 instances, so a missed mismatch hits at most 100 instances, and the canary ring is about 480. Second, the mismatch data itself: by month 6, 91% of mismatches had appeared in the first 48 hours of shadowing, so 3 days caught most of the expected yield. Third, the safety layers stayed: every cutover still went through rings with auto-halt, so a missed mismatch would surface as a canary regression and not a fleet event. Fourth, it was explicit: director sign-off, a risk-register entry, and an expiry. If the first-48-hours yield had been 50% rather than 91%, I would have recommended paying for the lease extension instead."

</details>

<details><summary><b>Q7 · "The client chose Oracle against your advice. Why credit you with the architecture?"</b></summary>

**Initial Prompt.** About the consulting engagement: "The client made the key decision, against your recommendation. Why should I credit you with the architecture?"

**L5 Answer.** "Because I designed everything else around it, and I did recommend Postgres, so I had the right idea."

**Why L5 Stalls.** "I had the right idea" asks for credit for a recommendation that wasn't taken, which is the weakest form of architecture evidence. The interviewer wants to see what the candidate *built* given the decision.

**L7 Answer.** "Don't credit me with the Oracle decision; that was theirs, and it was defensible given their support contract. Credit me with three things. The decision framing: the 3-option memo with prices was what their architect used to decide, and they told me it was the first time the license cost was quantified. The boundary: I designed the CDC feed so the 9 new services never touched Oracle, which limited the decision's blast radius to 1 service. And reversibility: I made their one-way door into a two-way door, which is why leaving Oracle 14 months later took 6 weeks rather than 6 months. In a consulting role, the client owns the one-way doors. My architecture job was to make as many of them two-way as I could."

</details>

<details><summary><b>Q8 · "Tell me about a constraint you were wrong about."</b></summary>

**Initial Prompt.** "Which constraint did you misjudge on this project, too hard, too soft, or not real at all?"

**L5 Answer.** "I don't think we misjudged any; we were pretty careful about requirements."

**Why L5 Stalls.** Misjudging at least one constraint is nearly universal on a 9-month project. Claiming none signals either no reflection or no testing.

**L7 Answer.** "Two. I treated K6, the headcount limit, as hard, and it wasn't. The director had 1 open requisition I didn't know about until month 5. If I'd asked in month 1, the Python port could have been ours, and parity would have come 4 months earlier. Lesson: I now ask about headcount as explicitly as I ask about dates. The other went the opposite way: I treated mesh coverage (K5) as roughly static, and it rose about 1 point a month. At M0 the right call was the relay tier. But I didn't write the 95% revisit trigger until month 10, so for the first 9 months nobody was watching for the moment xDS became viable. Every Soft constraint now gets its trigger when it's written down, not later."

</details>

<details><summary><b>Q9 · "Which of these constraints did you remove rather than honor?"</b></summary>

**Initial Prompt.** "You've told me how you honored constraints. Which one did you get rid of?"

**L5 Answer.** "I guess none, really. We had to work within what we were given."

**Why L5 Stalls.** At L7, changing constraints is part of the job description (§1.5). "Work within what we were given" caps the candidate at L5–L6 on this dimension.

**L7 Answer.** "Two constraints existed before Beacon and are gone because of it. First, 'dynamic config changes are instant and global'. That wasn't written anywhere, but every team assumed it, and two incident reviews had treated it as a law of nature. Beacon made staging the default and instant the exception, behind break-glass. Second, 'payments can't use shared platform tooling'. That folklore came from an older audit. Reading the policy with their compliance lead showed the actual requirement was an approval trail, which a platform can provide. After Beacon, 2 more platform services onboarded payments using the same change-policy pattern. The third I tried to remove and couldn't: the director wouldn't move the 6-engineer cap, and I committed to the plan that fit it."

</details>

<details><summary><b>Q10 · "What if the auditor had rejected your compensating control?"</b></summary>

**Initial Prompt.** A counterfactual: "Suppose the auditor had rejected the mTLS proxy as remediation. What then?"

**L5 Answer.** "Then I guess we would have had to accelerate the migration somehow."

**Why L5 Stalls.** "Somehow" means no plan. Q5 already established that the migration couldn't be accelerated enough, so this answer contradicts the candidate's own critical-path analysis.

**L7 Answer.** "I planned for that case, because a rejected control in month 6 would have left no time to react. Before building the proxy, I had the security lead walk the control description past the auditor in month 3, 2 months before we shipped it. If they had rejected it then, the fallback was a narrower permanent fix: migrate only the namespaces holding sensitive data, 41 of them, by month 6, using full 7-day shadow windows, and accept a finding scoped to the remaining non-sensitive namespaces with a documented plan. I'd priced that at about 2 more engineer-months and a 3-week slip on the general migration. The general lesson: when a control's acceptance is someone else's decision, get that decision before you build, not after."

</details>

---

## 15. Checklist

- [ ] Every constraint in your project is in a ledger row with all nine columns, and `constraint_check.py` passes.
- [ ] Every Hard constraint has evidence (a document, a price, a person you asked), not belief.
- [ ] Every constraint has a cost of honoring *and* a cost of breaking.
- [ ] Every Soft and Negotiable constraint has a revisit trigger, written when the constraint was recorded.
- [ ] Legacy described by its original constraints and what changed; no trashing language.
- [ ] A behavior inventory exists for anything you replaced (Hyrum), and you can name its most surprising finding.
- [ ] Debt you created: principal, interest, payoff plan, status.
- [ ] Stakeholder map with each stakeholder's accountability and fear; no use of the word "politics".
- [ ] At least one demand converted into a typed, reusable requirement, if true for your project.
- [ ] Deadline: hardness tested and priced; the critical path identified; descopes with triggers; shortcuts bounded, approved and expired.
- [ ] Your unconstrained design and the delta for each major constraint (§9).
- [ ] One constraint you misjudged, and what you do differently now (Q8).
- [ ] One constraint you removed rather than honored, if true (Q9).
- [ ] Consulting background: options memo, priced recommendation, risk register, design for the client's choice (§4.5).

---

## 16. References

- G. K. Chesterton, *The Thing* (1929), chapter "The Drift from Domesticity": the parable of the fence.
- Hyrum Wright, Hyrum's Law. <https://www.hyrumslaw.com/>
- Ward Cunningham, "The WyCash Portfolio Management System", OOPSLA '92 experience report (the debt metaphor). <http://c2.com/doc/oopsla92.html>
- Martin Fowler, "Technical Debt Quadrant". <https://martinfowler.com/bliki/TechnicalDebtQuadrant.html>
- Martin Fowler, "Strangler Fig Application". <https://martinfowler.com/bliki/StranglerFigApplication.html>
- Martin Fowler, "Branch By Abstraction". <https://martinfowler.com/bliki/BranchByAbstraction.html>
- Danilo Sato (on martinfowler.com), "Parallel Change". <https://martinfowler.com/bliki/ParallelChange.html>
- Frederick P. Brooks Jr., *The Mythical Man-Month: Essays on Software Engineering*, Anniversary Edition, Addison-Wesley, 1995, ISBN 0-201-83595-9 (Brooks's law).
- Amazon, 2015 Letter to Shareholders (Type 1 and Type 2 decisions; one-way and two-way doors). <https://s2.q4cdn.com/299287126/files/doc_financials/annual/2015-Letter-to-Shareholders.PDF>
- Amazon Leadership Principles (Have Backbone; Disagree and Commit). <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
- Google re:Work, "A guide to structured interviewing for better hiring practices". <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
