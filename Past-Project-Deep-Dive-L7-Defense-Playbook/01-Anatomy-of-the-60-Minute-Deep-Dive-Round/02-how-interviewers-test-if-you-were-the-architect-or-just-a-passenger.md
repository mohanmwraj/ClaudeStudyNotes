# 01.2 · How Interviewers Test Whether You Were the Architect or Just a Passenger

> **Folder:** `01-Anatomy-of-the-60-Minute-Deep-Dive-Round` · file 2 of 3
> **Question this file answers:** how do two skeptical Principal Engineers work out, in 60 minutes and without access to your company, which parts of the system you designed? And how do you draw a large enterprise architecture while making your own components, RFCs, algorithms and recovery mechanisms impossible to miss, without claiming a single decision that wasn't yours?
> **Running exhibit:** P-0 "Beacon" (fact sheet in [01.1 §3](01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md#3-the-running-exhibit-p-0-beacon-fact-sheet)).
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L2 `ownership_lint.py` | Python 3, standard library | Flags passenger language in tellings: vague contribution verbs, agentless decisions ("we decided"), hedges, buzzwords, unquantified claims, and "we" with no "I" | [§13](#13-the-ownership-lint), on every telling in this file. The gate also runs it on every telling in Folder 01. |

**Verification.** The gate extracts the listing from this file and checks it byte for byte against the source that was run. It then re-runs the listing on this file and compares the result with the output block in §13. Across Folder 01, every `#### How an L5 tells it` blockquote must be flagged and every `#### How an L7 tells it` blockquote must be clean. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

[File 01.1](01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md) covered the clock. This file covers the round's real purpose: **verifying authorship**. Résumés and promotion packets describe projects. This round exists to find out which decisions in those projects the candidate actually made. The interviewers can't phone your colleagues during the hour, so they rely on probes that only the person who made a decision can pass. This file catalogs those probes and the passenger tells they listen for. It then gives you two tools: the **ownership map**, a way to draw the whole system while highlighting your slice, and the **attribution grammar**, a way to describe shared work precisely.

**The integrity rule applies with full force here.** Everything below helps you present real authorship clearly. None of it helps you claim authorship you don't have. That restraint is also the effective strategy: the probes in §3 are designed to expose claimed authorship, and an exposed claim usually sinks the whole round, not just the claim.

---

## 1. First principles: the authorship problem

### 1.1 Why the résumé can't be taken at face value

Large systems are built by teams, but résumés and promotion packets are written by individuals. Every engineer on a 6-person team can truthfully write "built a config platform serving 48,000 instances". Only some of them made its key decisions, and the round is designed to tell which. Honest résumés create the same ambiguity: "led" can mean "was the technical decision-maker" or "ran the stand-ups"; "designed" can mean "wrote the RFC" or "drew the diagram in the RFC someone else wrote". Interviewers treat every ownership verb as a hypothesis to test.

### 1.2 Decision knowledge versus description knowledge

Two kinds of knowledge are hard to fake, because only one kind of person acquires them:

| Description knowledge (anyone on the team, or anyone who read the docs) | Decision knowledge (only the person who decided) |
|---|---|
| What the components are | Why these components and not others: the alternatives, and the reason each lost |
| How data flows | Which flow was redesigned, after what discovery |
| The current numbers | How the numbers were derived *before* they were measured, and what was wrong about the estimate |
| The SLOs | Who argued for a different SLO, and why this one won |
| The incident's root cause (from the postmortem) | What the on-call saw first, the false leads, and the debate over the fix |
| The design's strengths | The design's costs and regrets, and the decisions you would now reverse |
| The final design | The *first* design, and what killed it |

Every probe in §3 tests decision knowledge. An onboarding document carries description knowledge, so a passenger can be fluent in the left column. Only the decision-maker reliably has the right column, because nobody writes it down. (Even good RFCs record the alternatives, but rarely the arguments in the review meeting, or the first draft that was abandoned.)

### 1.3 Ownership expectations by level

Under-claiming at L7 is as costly as over-claiming. If you present L7 work at L5 granularity ("I implemented the SDK"), interviewers will level you at L5. The goal is *accurate* attribution, at the level of the decisions you really made.

| Level | Typical scope of personally owned decisions | Typical evidence |
|---|---|---|
| L5 Senior | Design and implementation of a component inside a design set by someone else; local trade-offs | Code, component design, tests, on-call fixes |
| L6 Staff | Design of a system or a major cross-team component; the RFC; the cross-team interfaces; the migration plan | RFC authorship, a cross-team contract, a migration plan you led, incident leadership |
| L7 Principal / Senior Staff | Direction across multiple systems or teams; the irreversible decisions; setting the constraints others design within; organizational risk | Multi-team architecture, a strategy document, decisions that outlived the project, others' designs you reshaped |

Beacon is an L6 project with L7 elements:
- **L6:** the RFC, the protocol, the cross-team migration.
- **L7:** setting the "parse with the consumer's parser" rule and the fail-static semantics, which became the standard other platform teams adopted for content distribution. (In a real dossier, include that kind of claim only if it really happened, and be ready to name the teams that adopted it.)

---

## 2. The passenger tells

Interviewers rarely conclude "passenger" from one answer. They collect tells. Each one alone is weak evidence, and three or four together become a note.

| # | Tell | Sounds like | What the interviewer infers | The author's counter-signal |
|---|---|---|---|---|
| T1 | **Vocabulary without mechanism** | "We used event sourcing with CQRS for scalability" | Knows the names, not the reasons | States the mechanism and why it was needed here: "the append-only change log is the audit trail G5 required" |
| T2 | **"We" fog** | "We decided… we built… we found…" with no "I" anywhere | Can't separate own work | "I" for own decisions, named roles for others' |
| T3 | **Numbers without derivation** | "It handled 4,800 QPS" (can't say why 4,800) | Number memorized from a slide | Derives it aloud: "48,000 instances ÷ 10 s" |
| T4 | **Outcome without causal chain** | "Latency dropped 40% after the migration" | Unclear what *caused* the drop | Names the mechanism and the evidence that it caused the change |
| T5 | **No alternatives** | "That was the obvious design" | Didn't make the choice | Names 2–3 alternatives and the reasons each lost |
| T6 | **Present-tense design** | Describes the system as it is now, never as it evolved | Joined after the decisions | Knows version 1, what broke, and version 2 |
| T7 | **Defaults unexplained** | "We used a 5-minute bake" (can't say why 5) | Didn't choose the parameter | Knows the trade-off: shorter bakes miss slow failures, longer ones slow every change |
| T8 | **No costs** | Every decision is described as a pure win | Didn't own the downside | Names the cost and who paid it |
| T9 | **Failure knowledge from the postmortem only** | Recites the root cause; knows nothing about detection or the debate | Read the doc; wasn't in the incident | Knows the first signal, the false leads, the timeline |
| T10 | **Boundary blur** | Can't say where their component ended | Didn't own an interface | States the contract: inputs, outputs, guarantees, error semantics |
| T11 | **Disagreement-free history** | "Everyone was aligned" | Wasn't in the rooms where it was contested | Names who disagreed, about what, and how it resolved |
| T12 | **Uniform depth** | Equally shallow on every box | Has a tour guide's view | Deep on the starred boxes, honestly shallow elsewhere |
| T13 | **Inconsistent recall** | Different numbers for the same quantity 20 minutes apart | Reconstructing, not remembering | Same number, re-derivable |
| T14 | **Over-claim then retreat** | "I designed it… well, the architecture was mostly set by the time I…" | Résumé inflation | States the scope correctly the first time |

**T14 is the most damaging tell,** because it converts every other claim into a suspected over-claim. A retreat is far worse than stating the smaller scope up front.

---

## 3. The authorship probes

Each probe below is an original formulation of a probe class. For each one: what it detects, how a passenger responds, and how an author responds, using Beacon. Six probes include a full L5/L7 telling pair.

### 3.1 The provenance probe: "Whose idea was it, and what was the first version?"

- **Detects:** whether you were present when the decision was made (T6). Authors remember the abandoned first version, because they wrote it.
- **The question behind the question:** "Was this decision shaped by feedback, and did you absorb the feedback well?" A design that never changed suggests either a passenger or an author who doesn't take review.

#### How an L5 tells it

> The rollback design was basically roll-forward, because that's best practice. We decided early on that versions should only go up, and it worked well.

#### How an L7 tells it

> My first RFC draft made rollback a version decrement: publish the previous snapshot under its old version number and let clients move back. In the security review, the reviewer asked what stops someone who can replay an old signed pointer from downgrading the fleet, and the draft had no answer. I rewrote the section so each namespace's version number is strictly monotonic, and a rollback republishes old content under a new version. That change also made a lagging relay harmless, a property I hadn't designed for. It cost 1 thing: a rollback now has to go through the publisher, so publisher availability matters during incidents, which is why the publisher runs 3 replicas behind a leader lease.

**What the L7 telling proves.** The first version, the reviewer's objection, the redesign, the side benefit and the cost are all decision knowledge. Crediting the reviewer *raises* the author's credibility: it shows the candidate was in the review and absorbed the feedback.

### 3.2 The alternatives probe: "What else did you consider?"

- **Detects:** T5. Authors considered alternatives; passengers inherited a decision.
- **Strong answers name 2–3 real alternatives,** each with the specific reason it lost and what was kept from it (01.1 §7.7's options table). "We considered Kafka but it was overkill" is a weak answer. "Kafka would have given us durable fan-out, but 2,100 namespaces with mostly-idle keys meant either 2,100 topics or a shared topic with client-side filtering, and both made 'latest snapshot for namespace X' a scan" is a strong one.
- **The follow-up to expect:** "Who argued for the losing option?" (→ §3.9).

### 3.3 The mechanism probe: "Walk me through exactly what happens when…"

- **Detects:** T1 and T12. It forces a sequence with latencies, ordering and failure behavior.
- **The author's advantage:** you know the *order* of steps and why the order matters. Beacon's consumer order is verify digest → verify signature → version gate → parse → swap → persist the LKG. Ask why LKG persistence comes *after* the swap: because the swap is the user-visible effect, and the LKG exists only for cold starts, so a slow disk must never delay the swap. (The INC-B7 bug lived in that LKG write; 01.1 §7.6.)
- **Typical depth target:** two levels below the container diagram.

### 3.4 The derivation probe: "How did you get that number?"

- **Detects:** T3. Every number you state is fair game.
- **Answer with the derivation, then the measurement:** "Estimated as 48,000 instances ÷ 10 s = 4,800 QPS; then load-tested one replica at 12,000 on the point read." The order shows that you estimated before you built, which is an L6+ habit.
- **If the estimate was wrong, say how wrong and why.** "I estimated a median snapshot of 4 KB; it was 18 KB, because teams stored JSON blobs as values. That's why the 1 MB warning exists." A wrong estimate you corrected is better evidence than one that was right by luck.

### 3.5 The counterfactual probe: "What would change if…"

- **Detects:** whether you understand *why* the design works, not just *that* it works. Passengers can describe; only authors can re-derive under changed assumptions.
- **Beacon examples:**
  - "What if snapshots were 100× larger?" At a 1.8 MB median, the 864 MB fan-out per change becomes ~86 GB: a delta protocol becomes necessary and the content-addressed full-snapshot design is no longer right.
  - "What if you needed per-request consistency between two namespaces?" Snapshots are per namespace, so cross-namespace atomicity would need a multi-namespace manifest version.
  - "What if mesh coverage were 100%?" Option O2 revives (01.1 §7.9).
- **A strong answer names the first thing that breaks,** not a redesign of everything.

### 3.6 The failure-archaeology probe: "Tell me about the worst production issue."

- **Detects:** T9. Authors and operators know the timeline from the inside.
- **The tell-tale details that only participants know:**
  - the *first* signal, and how long after the trigger it arrived;
  - the false lead ("we first suspected the relay deploy itself was serving stale pointers");
  - who did what during mitigation;
  - the argument over the fix ("the SRE partner wanted `fail_readiness` as the global default; I argued for per-namespace policy, because a global readiness failure during a control-plane outage would take down 48,000 instances at once").
- **Owning a root cause in your own component is a strong positive.** Claiming an incident you only read about is a severe negative if probed.

### 3.7 The boundary probe: "Where did your part end?"

- **Detects:** T10 and over-claiming. Interfaces are where ownership is clearest. Whoever owned an interface can state its contract: inputs, outputs, guarantees, errors, versioning.

#### How an L5 tells it

> The relays were sort of shared between us and the platform team. I worked on the SDK side and the relay side, and we kind of figured out the protocol together as we went.

#### How an L7 tells it

> My side ended at the Watch contract. I specified it in the RFC: the client sends namespace and have_version; the relay replies with the newest version and digest when one exists, otherwise holds the stream open; the relay never sends content, only pointers; and a client must treat any pointer as untrusted until the digest and signature verify. The relay team owned everything behind that contract, including stream limits, keepalive and autoscaling, and I reviewed their design doc against it. When they asked to add content inlining for tiny snapshots under 2 KB, I said no, because it would make the relay content-aware and break the 'relays are untrusted' assumption in the threat model.

**What the L7 telling proves.** The candidate can state the contract field by field, names the owner on the other side, and describes a boundary decision they defended. That one sentence of "no" is strong evidence that the candidate *held* the interface.

### 3.8 The cost probe: "What did that decision cost later?"

- **Detects:** T8. Every real decision has a cost someone paid. Passengers describe decisions as free.
- **Beacon examples:**
  - The relay tier costs about 0.5 engineers of ongoing operations. That is the price of option O3 (01.1 §7.7).
  - Monotonic versions mean a rollback needs the publisher (§3.1).
  - "Parse with the consumer's parser" means the validator must ship every SDK parser version still in use: 4 languages × up to 3 supported versions = 12 parsers in the sandbox. Retiring an old SDK version is now a validator change too.
- **The second-order version:** "Who paid it?" ("The relay team carries the on-call; I negotiated that by moving the SDK's support load to my team.")

### 3.9 The disagreement probe: "Who disagreed with you, and about what?"

- **Detects:** T11. Real architecture work involves contested decisions. "Everyone was aligned" means either a trivial project or a candidate who wasn't in the decision rooms.

#### How an L5 tells it

> There was some disagreement with the SRE team about using the mesh, but we talked it through and eventually we went with relays. The team felt it was the more robust option.

#### How an L7 tells it

> The SRE lead wanted config delivered over the service mesh's xDS control plane, and the argument was strong: no new tier to operate, and the mesh already had streams to every sidecar. I thought it would fail on coverage and coupling, but I couldn't prove it on paper, so I proposed a 1-week prototype with 3 exit criteria the SRE lead and I wrote together: reach at least 95% of instances, add no release coupling to the mesh, and keep p99 propagation under 30 seconds. It met the propagation target and failed the other 2: 18% of instances were batch jobs and legacy VMs without sidecars, and config pushes would have shipped on the mesh's release train. The SRE lead signed off on the relay design, and I took 1 thing from the xDS proposal: relays authenticate with the mesh's workload identities, so I didn't build a second identity system.

**What the L7 telling proves.**
- It credits the opposing argument fairly. Steelmanning shows judgment.
- It converts an opinion fight into an experiment with exit criteria written jointly.
- It reports a mixed result honestly: one criterion passed.
- It keeps part of the losing proposal, which is the mark of a decision optimized for the system rather than for winning.

Netflix's culture memo describes this behavior as an "informed captain" who is expected to be "farming for dissent" ([Netflix culture](https://jobs.netflix.com/culture)). Amazon's "Have Backbone; Disagree and Commit" principle is the other half: once the decision is made, everyone commits.

### 3.10 The consistency probe: the same question, 20 minutes later, in a different form

- **Detects:** T13. The scribe notes your numbers and dates, and later asks a question whose answer depends on them.
- **Defense:** derive, don't recall. See §9 for Beacon's consistency web.

### 3.11 The redraw probe: "Draw only what you built."

- **Detects:** inflated ★ marks. It is the most direct authorship test, and it is covered in 01.1 §17 Q9. The answer must be *smaller* than the full diagram, and you should say aloud what you left out and why.

### 3.12 The teach-back probe: "Explain it to me as if I'm the engineer who'll maintain it."

- **Detects:** whether your knowledge is operational. A maintainer needs the non-obvious things: the invariants that must not be broken, the tests that guard them, the alerts that fire, the runbooks.
- **A strong answer is a short list of invariants and tripwires:**
  - "Never let the LKG write happen before the swap, or slow disks delay config."
  - "Never accept a version ≤ the applied version, except through the documented emergency reset, which needs 2 approvers."
  - "The chaos test `lkg_kill_during_write` is the guard; if it's flaky, something changed in the write path."

### 3.13 Probe-to-tell map

| Probe | Primary tells it detects | Time it usually takes | When it usually comes |
|---|---|---|---|
| Provenance | T6, T14 | 2–4 min | Deep dive |
| Alternatives | T5 | 3–5 min | Architecture, trade-offs |
| Mechanism | T1, T12 | 5–10 min | Deep dive |
| Derivation | T3 | 30–90 s | Any time after a number |
| Counterfactual | T1, T7 | 2–4 min | Deep dive, trade-offs |
| Failure archaeology | T9 | 5–10 min | Deep dive 2 |
| Boundary | T10, T14 | 2–3 min | Architecture |
| Cost | T8 | 1–2 min | Trade-offs, hindsight |
| Disagreement | T11 | 3–5 min | Impact, organization |
| Consistency | T13 | 30 s | 15–25 min after the number |
| Redraw | T12, T14 | 3–5 min | Their clock |
| Teach-back | T1, T9 | 3–5 min | Their clock |

---

## 4. The ownership map: drawing the enterprise system and highlighting your part

### 4.1 The legend and the verb ladder

Use three ownership marks on the board. Behind each mark is a precise verb you can defend:

| Mark | Verbs it covers | What you must be able to do for that box |
|---|---|---|
| **★** | Designed (wrote the design or RFC section) · Decided (made the call between alternatives) · Led (directed others' work on it) · Wrote (the core code) | Five depth levels (§8); alternatives; costs; first version; failure modes |
| **◆** | Reviewed (formally approved or shaped it) · Contributed (a defined piece) · Operated (on-call owner) | Its contract with your ★ parts; your specific contribution; its major failure modes |
| **○** | Consumed · Integrated with | What it guarantees you; how you handled its failures |

**Rules.**
- **One mark per box,** the strongest one that is true. For a split box, write both, with the split: "★ contract, ◆ plugins".
- **If you can't pass the five-level test (§8) on a ★ box, it isn't a ★ box.** Downgrade it before the interview, not during.

### 4.2 The ownership ledger (prepare it; never show it)

The ownership ledger is your private source of truth for every mark. It lists the artifact that proves the mark, what you can speak to at depth, and where your floor is.

| Component | Mark | My verbs | Artifact | I can speak to at depth | My floor (say so if probed) |
|---|---|---|---|---|---|
| C3 Validator | ★ contract, ◆ plugins | Designed the contract; decided the "consumer parser" rule | RFC §5; sandbox design doc | The interface, the rule, the sandbox's resource limits, the 12-parser matrix | Individual type plugins (each owning team wrote theirs) |
| C4 Publisher | ★ | Designed; wrote builder, canonicalizer, signer, size guard | RFC §3–4; ~6k lines in 41 PRs | Header layout, canonicalization rules, KMS signing flow, leader lease | The announcer's retry tuning (another engineer) |
| C5 Relays | ◆ | Reviewed the protocol; specified the Watch contract | RFC §6; review comments on the relay design doc | The contract, the threat model, why relays never carry content | Flow control, keepalive, autoscaling |
| C6 SDK | ★ semantics + Java, ○ ports | Designed the semantics; wrote the Java reference; reviewed the Go port | RFC §7; Java SDK | Verification order, swap, LKG, `on_missing`, reconnect jitter | Python and Node ports |
| C7 Rollout controller | ★ | Designed; co-wrote | RFC §8; controller code | Ring model, bake times, gates, insufficient-signal hold | The metrics adapter (co-author's) |
| C8 Break-glass | ★ policy | Designed the policy | Runbook; policy doc | Booleans only, 2-person rule, audit, paging | — |
| C9 ZK bridge | ★ | Designed; wrote the shadow-diff comparator; led the migration | Migration plan; comparator | Shadow mode, the compat-shim template, per-namespace cutover, write freeze | Individual teams' shims |
| C1, C2, C10 | ○ | Consumed | — | What they guarantee Beacon | Internals |

### 4.3 Drawing a large enterprise architecture without drowning your contribution

Real projects sit inside enterprises with dozens of systems. If you draw them all at the same weight, your contribution disappears. If you omit them, the interviewers can't see the scope. **Draw in two weights.**

1. **The enterprise band (thin lines, about 60 seconds).** Draw a single strip with the platform services your system depends on or serves, each a small labeled rectangle marked ○. Never deep-dive these. Their only job is to show scope and give interfaces somewhere to point.
2. **Your system (thick lines, minutes 9–16).** Draw the containers of the project itself, with ★/◆/○ marks.
3. **Your slice (bold or double outline).** The ★ boxes get a heavier outline, so they are visible from across the room.
4. **The overlay (added in the deep dive).** Next to each ★ box, write the *specific* artifact: the RFC section, the algorithm, the recovery mechanism.

```text
 ENTERPRISE BAND  (thin, ~60 s, never deep-dived)
 +------------------------------------------------------------------------------------+
 | CI/CD (o) | Service mesh (o) | Metrics+alerting (o) | KMS (o) | Object storage (o)  |
 | Identity (o) | Incident tooling (o) | 1,200 consuming services (o)                  |
 +------------------------------------------------------------------------------------+
        |               | identities          | health signals      | sign       | blobs
 PROJECT  (normal weight, ownership-marked)                                       
   Config API (o) --> Postgres (o) ==> [[ VALIDATOR *contract ]] ==> [[ PUBLISHER * ]] ==> object store (o)
                                                                       | announce (ns, ver, digest)
                                                                       v
                                                          Relays x27 (o, <> protocol)
                                                                       | Watch(ns, have_version)
                                                                       v
   [[ ROLLOUT CONTROLLER * ]] <-- metrics (o)             [[ SDK *  (Java ref) ]] <-- app code (o)
   [[ ZK BRIDGE * ]]  (dotted, M3-M8)

 OVERLAY  (written beside each [[ * ]] box during the deep dive)
   VALIDATOR   : RFC s5 - "parse with the consumer's parser"; 12-parser sandbox
   PUBLISHER   : RFC s3-4 - canonical map -> SHA-256 -> 4 MB cap -> Ed25519 -> monotonic version
   SDK         : RFC s7 - verify -> version gate -> swap -> LKG (temp+fsync+rename); on_missing policy
   CONTROLLER  : RFC s8 - rings 1% / region / all; bake 5/15 min; insufficient-signal hold
   ZK BRIDGE   : migration plan - shadow diff (212 mismatches / 37 services); per-namespace cutover
   Legend: [[ ]] = bold outline, * = designed/led, <> = reviewed, (o) = team/other, ==> = my data path
```

**The 20/80 rule.** About 20% of the boxes on the board (your ★ boxes) should get about 80% of the deep-dive time. If an interviewer steers you into a ○ box, answer its contract and its failure behavior as they affect your system, then offer to return to your own: "That's the platform team's; what matters for Beacon is that it guarantees X. Want me to show how the publisher handles it when X fails?"

### 4.4 The "surgical highlight" sequence

When you reach the deep dive, walk the interviewers down a fixed path. Each step narrows the frame and strengthens the ownership evidence:

| Step | Frame | Beacon | Ownership evidence produced |
|---|---|---|---|
| 1 | Whole system | The diagram above | Scope (S1) |
| 2 | My box | Publisher + SDK | The mark itself |
| 3 | My RFC section | RFC §3–4 and §7, with the three invariants | Design authorship |
| 4 | My algorithm | Canonicalize → hash → cap → sign → monotonic version; the consumer's verification order | Mechanism knowledge (decision knowledge) |
| 5 | My failure recovery | LKG generations, `on_missing`, fail-static on control-plane loss | Operational authorship |
| 6 | My regret | `on_missing` should have been mandatory from day one | Self-critique, which only authors can make credibly |

### 4.5 When your system is one stage of a much larger pipeline

If your project is one stage in a 40-service enterprise pipeline (common in Archetype A data migrations and Archetype B commerce flows; Folder 03), draw the pipeline as **one band with three labeled points**: where data enters your stage, where it leaves, and the one upstream or downstream behavior your design had to tolerate. Then spend the time on your stage. "Upstream, the order service emits events at-least-once with no ordering across partitions; that's the property my dedup stage exists to absorb." This shows you understood the enterprise context without claiming any of it.

---

## 5. "I" versus "we": calibrated attribution

### 5.1 The four attribution rules

1. **"I" for decisions and actions you personally took.** "I wrote the RFC." "I proposed the prototype." "I rolled the relay back." (Only if you did.)
2. **"We" for team outcomes and shared execution.** "We migrated 300 services in 5 months." "We hit the colo deadline with 2 weeks to spare."
3. **Named roles for other people's decisions.** "The SRE lead decided…", "The security reviewer found…", "Our EM negotiated…". Use roles, not names: the interviewers don't know your colleagues, and names add nothing.
4. **Never "we decided" for a decision you made, and never "I decided" for one you didn't.** "We decided" hides the author. Interviewers hear it as a passenger tell (T2), and the lint in §13 flags it.

**The ratio of "I" to "we" is not the metric; specificity is.** A candidate who says "I" 40 times about vague actions ("I worked on the SDK") is less convincing than one who says "I" 10 times, each about a specific decision.

### 5.2 The verb ladder

| Weak (passenger-sounding) | Why it's weak | Strong (if true) |
|---|---|---|
| helped with | No defined contribution | wrote / designed / reviewed / tested [specific thing] |
| worked on | Activity, not outcome | built / shipped / rewrote [component] |
| was involved in | Presence, not action | led / decided / proposed |
| was responsible for | A title, not an action | owned [the interface / the on-call / the migration of 300 services] |
| contributed to | Unbounded | wrote [section 5 of] / implemented [the comparator in] |
| participated in | Presence | presented / argued for / facilitated |
| supported | Ambiguous direction | unblocked [team X] by [action] |
| was part of | Membership | — (describe the action instead) |

### 5.3 Attribution grammar: templates for shared work

| Situation | Template |
|---|---|
| You proposed it; someone approved or modified it | "I proposed X. [Role] approved it with one change, Y, because Z." |
| You argued for it; someone else decided otherwise | "I argued for X because of A. [Role] decided Y because of B. In hindsight, [B was right / A was right, and here's what it cost]." |
| Someone else designed it; you implemented part of it and changed it | "[Role] designed X. I implemented Y within it, and changed Z after finding W." |
| You inherited it | "When I joined at month 4, X was already decided. I owned Y from that point; the first thing I changed was Z." |
| You led it, others built it | "I set the direction and the interfaces: X and Y. [N] engineers built the parts; I reviewed every interface change and wrote Z myself." |
| Joint decision with a peer | "[Role] and I designed X together. I wrote the A half; they wrote the B half; we argued about C and settled on D because E." |

### 5.4 A worked pair: describing a team decision you influenced

Postgres as the source of truth was the platform architect's decision, not the candidate's. The candidate influenced one aspect of it.

#### How an L5 tells it

> We decided to keep Postgres as the source of truth because it was the industry standard approach. I was involved in the discussions about the schema and helped with the change log design.

#### How an L7 tells it

> Keeping Postgres as the source of truth was the platform architect's call, made before my RFC, and I agreed with it: 2,100 namespaces and about 270 changes a day is a small transactional workload. What I changed was the schema's shape. The first proposal stored the current value per key, and I argued for an append-only change log with the current state as a view, because G5 needed every change attributable and the publisher needed a monotonic sequence to build versions from. The architect accepted the log on 1 condition, that I own the compaction job, which I wrote: it keeps 13 months of history online and archives the rest.

**Why it works.** The decision-maker is named by role. The candidate's agreement comes with a reason and a number. The specific change is the candidate's, and so is the condition they accepted. The condition also adds credibility: real influence usually comes with obligations attached.

---

## 6. Scope integrity: when your part was smaller than the project

### 6.1 Honest scoping beats inflation, even tactically

Interviewers place your level from the **depth and density of decisions inside your slice**, not from the size of the project. A candidate who owned one component of a large system, and shows L7-quality reasoning about it (alternatives, costs, failure modes, influence on adjacent teams), is often scored higher than a candidate who claims the whole system and is shallow everywhere. There is also risk beyond the hour: references and back-channel checks happen at some companies for senior hires (⚠ practice varies widely). A deep-dive claim that contradicts a reference is a serious problem.

### 6.2 Common scoping situations

| Situation | How to frame it | What to emphasize |
|---|---|---|
| **Joined late** | "I joined at month 4; the protocol was set. I owned the migration from that point." | What you changed after joining; decisions you *would* have made differently, and why |
| **Left early** | "I led it through the shadow phase, then moved teams; the cutover was led by [role]." | Your design's behavior in the phase you didn't see, and what you learned from the handoff |
| **Your piece was small** | "My part was the dedup stage, one of 9 stages." | Decision density in the stage; the enterprise contract it absorbed (§4.5) |
| **You were the TL, wrote little code** | "I wrote the RFC and reviewed every interface PR; I wrote the comparator myself." | Design-review depth: what you caught in others' designs |
| **The project failed or was canceled** | "We stopped at 60%; the decision to stop was mine." | Why, what the signal was, what you'd do differently (01.1 §17 Q8) |
| **A committee design** | "The architecture came out of a 4-person design group; I owned the consistency model." | The part of the group's output that was yours |

#### How an L5 tells it

> I was on the platform team during the whole project, and I was part of the core group that built the system. The migration was a big effort and I helped the other teams move over, which was a lot of work. Overall I'd say I worked on most of the major pieces.

#### How an L7 tells it

> I should scope this precisely, because my part was narrower than the project. I joined Beacon at month 4, after the protocol and the publisher were done, so those decisions belong to the original tech lead. I owned the ZooKeeper migration: 300 services in 5 months. My decisions were the shadow-mode design, the compat-shim template that let each owning team map their library's quirks, and the per-namespace cutover order. The shadow diff found 212 mismatches in 37 services before cutover; the worst was a library that treated a missing znode as true, which would have enabled 14 unfinished features at once. If you want the deep dive, the migration is where I can go 5 levels down; on the protocol I can describe the design but not defend its alternatives as the author.

**Why it works.** It volunteers the scope boundary before any probe. It claims a well-defined slice with specific decisions and numbers. It tells the interviewers where to spend the deep dive. The final sentence is a pre-emptive floor declaration, a strong calibration signal. Notice that this alternative telling describes a *different candidate* on the same project: in Beacon's fact sheet, the candidate led the whole thing. Use the version that is true for you.

---

## 7. Evidence artifacts: RFCs, ADRs, postmortems, reviews

Artifacts are the strongest ownership evidence you can mention, and the most dangerous if you can't answer the follow-ups. Before mentioning an artifact, be ready for the probes it invites.

| Artifact | How to mention it | The follow-ups to expect | What you must know |
|---|---|---|---|
| **RFC / design doc** | "I wrote the RFC: 3 alternatives, 9 reviewers in 4 teams, 2 major revisions." | "What feedback changed the design most?" "Which section was most contested?" "What did you cut?" | The revisions and why; the strongest objection; the rejected alternatives in detail |
| **ADR** (title, context, decision, status, consequences, in Michael Nygard's format, [Cognitect](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)) | "Each major decision has an ADR; the one I'd point to is ADR-007, roll-forward rollback." | "Which ADR would you supersede today?" | The *consequences* sections, which are your hindsight material |
| **Postmortem** | "I wrote the postmortem for INC-B7; the root cause was my code." | "What action items didn't get done?" "What did the review push back on?" | The action items and their status. A blameless format ([Google SRE: postmortem culture](https://sre.google/sre-book/postmortem-culture/)) is about systems, but you should still own your part. |
| **Design reviews you gave** | "I reviewed the relay team's design against the Watch contract and blocked content inlining." | "What else did you push back on?" "Were you ever wrong in a review?" | Your review comments, especially the ones that changed the outcome. This is L7 influence evidence. |
| **Code** | "I wrote the canonicalizer and the signer, about 6k lines in 41 PRs." | "What was the hardest PR?" "What did reviewers catch?" | The tricky parts: canonical ordering of nested maps, the signing-key rotation path |
| **Strategy or vision doc** | "I wrote the content-distribution safety standard that 3 other platform teams adopted." | "Which team pushed back? What did you change for them?" | Adoption details: who, when, and what changed. Unverifiable "adoption" is a red flag. |

#### How an L5 tells it

> I wrote a lot of the design doc for the project, which covered pretty much everything about the architecture. It went through review and the reviewers were happy with it, so we went ahead and built it.

#### How an L7 tells it

> I wrote the RFC, 14 pages with 3 alternatives, and it went through 2 major revisions. Revision 1 came from security review: rollback by version decrement allowed replay downgrades, so versions became monotonic. Revision 2 came from the payments team: PCI-scoped services needed ticketed change approval, and my draft assumed every change could auto-advance through rings. I added per-namespace change policy as a first-class field instead of carving payments out as an exception, and that field now also carries the on_missing behavior. The most contested section was the relay tier versus xDS, which I settled with the prototype I described earlier. What I cut was delta snapshots: with an 18 KB median, full snapshots cost 864 MB per change at the widest fan-out, and I judged that cheaper than the complexity of deltas.

---

## 8. The depth-ladder self-test

Before the interview, run every ★ box through five levels. Answer each one aloud, from memory, in under 60 seconds. Any ★ box that fails Level 4 or 5 should be downgraded to ◆ on your board, or you should do the preparation to earn the ★.

| Level | Question | Pass criterion | Beacon publisher (example pass) |
|---|---|---|---|
| 1 What | What is it, in one sentence? | No jargon | "It turns a namespace's current state into a signed, versioned, immutable snapshot." |
| 2 How | How does it work, step by step? | Correct order, no gaps | Load → canonicalize → hash → cap → sign → write blob ×3 → announce |
| 3 Why | Why this design? | Each step tied to a goal or invariant | Canonical form → stable digest → stateless relays; cap → protects consumers (Cloudflare-class failure) |
| 4 Why not | What were the alternatives for each major choice? | ≥ 2 alternatives with reasons | Deltas (rejected on complexity at 18 KB median); per-key versions (rejected: no atomic multi-key change); version decrement rollback (rejected: replay downgrade) |
| 5 What breaks | Failure modes, edge cases, numbers | ≥ 3 failure modes with detection and handling | KMS outage → publisher halts, clients keep LKG, alert after 2 min; leader lease loss mid-publish → the digest makes a re-publish idempotent; oversized namespace → rejected at 4 MB, warned at 1 MB |

---

## 9. The consistency web: surviving cross-checks

The scribe will check your numbers against each other. Before the interview, write out the arithmetic web connecting your numbers and confirm that it closes. In Beacon's web, each line is a check the interviewers could run:

| Check | Arithmetic | Closes? |
|---|---|---|
| Streams per relay | 48,000 instances ÷ 27 relays ≈ 1,778 ≈ "about 1,800" | Yes. Note: one *multiplexed* stream per instance, carrying all its namespaces. If you say "per namespace", the numbers break. |
| Canary size | 1% × 48,000 = 480 instances; INC-B7's 140 instances = 29% of ring0 | Yes, and it explains why INC-B7 hit 0.3% of the fleet, not 1% |
| Polling load | 48,000 ÷ 10 s = 4,800 QPS < 12,000 tested | Yes |
| Fan-out | 48,000 × 18 KB ≈ 864 MB per change on the widest namespace | Yes. Only `platform/global` hits all instances; the median namespace reaches ~60. |
| Team capacity | 6 engineers × 9 months = 54 engineer-months | Must cover: publisher, Java SDK, controller, validator contract, the bridge, and *supporting* 300 migrations (owning teams wrote their own shims). Plausible only because the Go, Python and Node ports and the API/UI came from other people. |
| Timeline | Compliance due M6 < migration complete M8, so the interim fix (mTLS proxy + ACLs) had to land by M5 | Yes, and it's a constraint story (01.3) |
| Change rate | 270 changes/day × 365 ≈ 98,500/year; 3 auto-halts = 1 per ~33,000 changes | Yes. A good number to have if asked "how often does the halt fire?" |

**The team-capacity check deserves attention.** Interviewers sometimes do rough math on whether the claimed work fits the claimed team and time (⚠ reported). If you claim that you personally wrote the publisher, the SDK, the controller and the bridge in 9 months while leading the team, the arithmetic says you're over-claiming. Beacon's ledger (§4.2) shows co-authors and ports by others for exactly this reason. Run your own capacity check.

---

## 10. What interviewers write: passenger notes versus architect notes (composite ⚠)

| Signal | A passenger's notes | An architect's notes |
|---|---|---|
| Ownership | "Used 'we' throughout; when asked directly, described attending design meetings." | "Clear split: designed publisher and SDK semantics, consumed API and Postgres, reviewed relays. Redraw matched the claims." |
| Provenance | "Couldn't describe alternatives to the snapshot model." | "Described the v1 decrement rollback, the security reviewer's objection, and the change to monotonic versions." |
| Numbers | "Quoted 4,800 QPS; couldn't explain where it came from." | "Derived the poll load and the fan-out on the spot; consistent with numbers stated 20 minutes earlier." |
| Failure | "Described an incident from the postmortem; unclear on detection." | "Owned the root cause in own code; precise fsync/rename ordering; argued per-namespace policy against a global default." |
| Boundary | "Unclear where their component ended." | "Stated the Watch contract field by field; blocked content inlining on threat-model grounds." |
| Overall | "Strong communicator; could not verify personal design ownership. Lean no-hire at L6; possible L5." | "Owned a cross-team protocol end to end with operational depth. Strong L6, L7 elements in standard-setting." |

---

## 11. Hiring-committee scoring rubric: ownership and authorship

The bands follow the poor / borderline / solid / outstanding vocabulary of Google's public structured-interviewing guidance ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). The anchors are a composite (⚠).

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Attribution clarity** | Can't separate own work from the team's | Separates when pushed, inconsistently | Clear ★/◆/○ split stated unprompted | Clear split, *and* precise about joint work, inherited decisions and the work of others |
| **Decision knowledge** | Description only | Knows the alternatives, not the reasons | Alternatives, reasons, costs | Plus the first version, what killed it, and which decisions should now be reversed |
| **Interface ownership** | Boundaries blurred | Names the boundary | States the contract | States the contract and the boundary decisions defended in review |
| **Derivation** | Numbers memorized | Some derivable | All stated numbers derivable | Numbers form a consistent web; estimate-vs-actual errors explained |
| **Disagreement and influence** | "Everyone agreed" | Mentions disagreement vaguely | Names the disagreement and the resolution | Converted opinion to experiment; credited the opposing view; kept part of it |
| **Scope integrity** | Inflates, then retreats (T14) | Accurate when probed | Accurate unprompted | Accurate unprompted, with floors declared before they are probed |

---

## 12. Company lenses on ownership (⚠ inference from public material)

- **Amazon.** "Ownership" in the Leadership Principles: "Leaders are owners… They never say 'that's not my job'" ([LPs](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)). Expect the boundary probe to be followed by "and when the relay failed, what did *you* do?". Owners act past their boundary in an incident even when someone else owns the box.
- **Google.** Feedback is written for reviewers who weren't in the room ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). Attribution precision becomes literal sentences in that feedback, so a vague attribution becomes a vague note.
- **Netflix.** "Informed captain" plus "farming for dissent" ([culture](https://jobs.netflix.com/culture)): expect the disagreement probe, and expect it to reward the dissent you *sought*, not just the dissent you survived.
- **NVIDIA, Uber, Apple.** We can't cite public descriptions of this round. Expect the mechanism and counterfactual probes to go to the domain's hard layer: memory and interconnect (NVIDIA), multi-region real-time behavior (Uber), device and hardware schedule constraints (Apple).

---

## 13. The ownership lint

`ownership_lint.py` is a smell detector for the language in §2 and §5: vague verbs, agentless decisions, hedges, buzzwords, unquantified claims and "we" fog. It doesn't judge truth. A clean telling can still be false, and only you know which of your claims are real. Use it on the written tellings in your dossier (Folder 05) to find phrasing that will read as passenger language in an interviewer's notes.

**How to use it on your own dossier.** Write each telling under a heading `#### How an L7 tells it` followed by a `>` blockquote, then run `python -I ownership_lint.py dossier.md`. Fix every flag in your L7 tellings, either by making the claim specific or by deleting it. Then say each telling aloud: written precision has to survive speech.

### 13.1 Listing L2: `ownership_lint.py`

<!-- listing:ownership_lint.py -->
```python
#!/usr/bin/env python3
"""ownership_lint.py - flag "passenger" language in deep-dive answers.

Extracts every telling written as
    #### How an L5 tells it        (or L6 / L7)
    > blockquote lines ...
from a Markdown file and checks each one for the phrasings that make an
interviewer write "could not separate own contribution from the team's":

  VAGUE-VERB          helped / worked on / was involved in / contributed to ...
  AGENTLESS-DECISION  "we decided", "it was decided", "the team went with"
  HEDGE               basically / kind of / sort of / pretty much / etc.
  BUZZWORD            robust / seamless / best practices / highly scalable ...
  UNQUANTIFIED        an improvement or size claim with no digit in the sentence
  OWNERSHIP-FOG       4+ uses of "we" and no "I"/"my" anywhere in the telling

The lint is a smell detector, not a grader: a clean answer can still be wrong.
Usage: python -I ownership_lint.py <file.md> [<file.md> ...] [--quiet]
Standard library only.
"""
import re
import sys

RULES = [
    ("VAGUE-VERB", re.compile(
        r"\b(helped( with| to| out)?|was involved in|were involved in|worked on|"
        r"participated in|contributed to|was part of|assisted( with| in)?|"
        r"supported the|played a (key |big )?role in|took part in|"
        r"was responsible for|had a hand in)\b", re.I)),
    ("AGENTLESS-DECISION", re.compile(
        r"\b(we (decided|chose|picked|went with|opted|settled on|agreed)|"
        r"(it|this|that) was (decided|chosen|agreed)|was (decided|chosen) to|"
        r"the team (decided|chose|picked|went with|opted|settled on))\b", re.I)),
    ("HEDGE", re.compile(
        r"\b(basically|kind of|sort of|pretty much|more or less|i guess|"
        r"stuff like that|things like that|and so on|somehow|etc)\b", re.I)),
    ("BUZZWORD", re.compile(
        r"\b(robust|seamless(ly)?|best practices?|industry[- ]standard|"
        r"cutting[- ]edge|state[- ]of[- ]the[- ]art|world[- ]class|"
        r"enterprise[- ]grade|next[- ]gen|blazing(ly)? fast|"
        r"(highly|very|more|super) scalable|scalable (solution|architecture|system))\b", re.I)),
]
CLAIM = re.compile(
    r"\b(improv\w*|reduc\w*|increas\w*|faster|slower|cut|lower(ed)?|boost\w*|"
    r"sav(ed|ing)|optimi[sz]\w*|huge|massive|a lot of|lots of|significant(ly)?|"
    r"dramatic(ally)?|drastic(ally)?|tons of)\b", re.I)
HEADING = re.compile(r"^#### How an? (L\d) tells it\s*$")


def tellings(md):
    out = []
    lines = md.splitlines()
    context = ""
    in_fence = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            in_fence = not in_fence
        if not in_fence and re.match(r"^#{2,3} ", line):
            context = re.sub(r"^#+\s*", "", line).strip()
        m = HEADING.match(line) if not in_fence else None
        if m:
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            body = []
            while j < len(lines) and lines[j].startswith(">"):
                body.append(lines[j][1:].strip())
                j += 1
            out.append({"level": m.group(1), "context": context,
                        "text": " ".join(b for b in body if b)})
            i = j
            continue
        i += 1
    return out


def sentences(text):
    return [s for s in re.split(r"(?<=[.!?])\s+(?=[A-Z\"'(*])", text) if s.strip()]


def lint(text):
    plain = re.sub(r"[*_`]", "", text)
    flags = []
    for name, rx in RULES:
        for m in rx.finditer(plain):
            flags.append((name, m.group(0)))
    for s in sentences(plain):
        m = CLAIM.search(s)
        if m and not re.search(r"\d", s):
            flags.append(("UNQUANTIFIED", m.group(0) + ": " + s[:60].strip()))
    we = len(re.findall(r"\bwe\b|\bour\b|\bus\b(?!-)", plain, re.I))
    me = len(re.findall(r"\bI\b|\bI'(d|ve|m|ll)\b|\bmy\b|\bme\b", plain))
    if we >= 4 and me == 0:
        flags.append(("OWNERSHIP-FOG", f"{we} x we/our/us, 0 x I/my/me"))
    return flags, we, me


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    quiet = "--quiet" in argv
    paths = [p for p in argv if not p.startswith("--")]
    total = {"L5": [0, 0], "L6": [0, 0], "L7": [0, 0]}
    n = 0
    for path in paths:
        md = open(path, encoding="utf-8").read().replace("\r\n", "\n")
        name = re.split(r"[\\/]", path)[-1]
        for t in tellings(md):
            n += 1
            flags, we, me = lint(t["text"])
            total[t["level"]][0] += 1
            total[t["level"]][1] += 1 if flags else 0
            if not quiet:
                state = f"{len(flags)} flag(s)" if flags else "clean"
                print(f"T{n:02d} {t['level']} [{t['context'][:56]}] we={we} I={me} -> {state}")
                for rule, hit in flags:
                    print(f"      {rule}: {hit}")
        if quiet:
            print(f"{name}: scanned")
    print()
    for lvl in ("L5", "L6", "L7"):
        seen, flagged = total[lvl]
        if seen:
            print(f"{lvl}: {seen} telling(s), {flagged} flagged, {seen - flagged} clean")
    ok = total["L7"][1] == 0 and total["L5"][0] == total["L5"][1]
    print("verdict:", "OK (every L5 telling flagged, every L7 telling clean)" if ok
          else "CHECK (an L7 telling is flagged or an L5 telling is clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

### 13.2 Output on this file's tellings

<!-- output:ownership_lint.py -->
```text
T01 L5 [3.1 The provenance probe: "Whose idea was it, and what w] we=1 I=0 -> 3 flag(s)
      AGENTLESS-DECISION: We decided
      HEDGE: basically
      BUZZWORD: best practice
T02 L7 [3.1 The provenance probe: "Whose idea was it, and what w] we=0 I=2 -> clean
T03 L5 [3.7 The boundary probe: "Where did your part end?"] we=3 I=1 -> 3 flag(s)
      VAGUE-VERB: worked on
      HEDGE: sort of
      HEDGE: kind of
T04 L7 [3.7 The boundary probe: "Where did your part end?"] we=0 I=3 -> clean
T05 L5 [3.9 The disagreement probe: "Who disagreed with you, and] we=2 I=0 -> 2 flag(s)
      AGENTLESS-DECISION: we went with
      BUZZWORD: robust
T06 L7 [3.9 The disagreement probe: "Who disagreed with you, and] we=0 I=6 -> clean
T07 L5 [5.4 A worked pair: describing a team decision you influe] we=1 I=1 -> 4 flag(s)
      VAGUE-VERB: was involved in
      VAGUE-VERB: helped with
      AGENTLESS-DECISION: We decided
      BUZZWORD: industry standard
T08 L7 [5.4 A worked pair: describing a team decision you influe] we=0 I=6 -> clean
T09 L5 [6.2 Common scoping situations] we=0 I=5 -> 4 flag(s)
      VAGUE-VERB: was part of
      VAGUE-VERB: helped
      VAGUE-VERB: worked on
      UNQUANTIFIED: a lot of: The migration was a big effort and I helped the other teams
T10 L7 [6.2 Common scoping situations] we=0 I=6 -> clean
T11 L5 [7. Evidence artifacts: RFCs, ADRs, postmortems, reviews] we=1 I=1 -> 2 flag(s)
      HEDGE: pretty much
      UNQUANTIFIED: a lot of: I wrote a lot of the design doc for the project, which cover
T12 L7 [7. Evidence artifacts: RFCs, ADRs, postmortems, reviews] we=0 I=7 -> clean

L5: 6 telling(s), 6 flagged, 0 clean
L7: 6 telling(s), 0 flagged, 6 clean
verdict: OK (every L5 telling flagged, every L7 telling clean)
```

**Reading the output.**
- **Every L5 telling trips at least one rule,** usually several. The most common are VAGUE-VERB and AGENTLESS-DECISION, the two tells (T2, and the "helped with" family in §5.2) that interviewers most often write up as "could not separate own contribution".
- **Every L7 telling is clean,** although several contain "we". Clean means the "we" sits next to specific "I" statements, every claim carries a number, and no decision is agentless.
- **The gate runs the same lint over all of Folder 01** (README), so the tellings in 01.1 and 01.3 are held to the same standard.

---

## 14. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | **Inflated stars** | ★ on boxes you can't take five levels deep | Run §8; downgrade before the interview |
| F2 | **Retreat under probing** (T14) | "Well, actually the architecture was mostly set…" | State the scope precisely in the first sentence (§6) |
| F3 | **"We" fog** | No "I" for 10 minutes | Attribution rules (§5.1); lint your tellings |
| F4 | **Over-correction** | "I" for everything, including team work | "We" for shared outcomes; named roles for others' decisions |
| F5 | **Erasing collaborators** | Credits no one, even for obvious team work | Credit by role. It *raises* credibility (§3.1). |
| F6 | **Artifact name-dropping** | "I wrote the RFC" with no knowledge of the revisions | Prepare the §7 follow-ups for every artifact you mention |
| F7 | **Postmortem knowledge only** | Recites a root cause; nothing about detection or the debate | Use incidents you were actually in; say so if you weren't |
| F8 | **Uniform depth** | Equal (shallow) depth everywhere | 20/80 rule (§4.3): deep on ★ boxes, honest floor on ○ boxes |
| F9 | **Inconsistent numbers** | 27 relays at minute 12, "about 30" at minute 35 | Consistency web (§9) |
| F10 | **Capacity-implausible claims** | Personally built 4 systems in 9 months while leading | Team-capacity check (§9); credit the co-authors |
| F11 | **Disagreement-free history** | "Everyone was aligned" | Prepare one real disagreement with its resolution |
| F12 | **Confidentiality as a dodge** | "Can't say" about your own mechanism | Describe the technique generically (01.1 §4.3) |

---

## 15. Bar-raiser chains

<details><summary><b>Q1 · "Whose idea was the snapshot model?"</b></summary>

**Initial Prompt.** In deep dive 1: "Immutable signed snapshots. Whose idea was that? Did it exist before you?"

**L5 Answer.** "It was the team's idea really. We all kind of agreed it was the right approach, since snapshots are a common pattern."

**Why L5 Stalls.** It's a direct provenance probe and the answer gives nothing: no first version, no author, no alternative. "Common pattern" signals that the candidate didn't choose it. If the candidate *did* originate the model, they have just thrown away their strongest evidence; if they didn't, the vagueness is still worse than a clear "no".

**L7 Answer.** "The idea of distributing complete snapshots wasn't new to me. Several public config and content systems ship whole files, and the Cloudflare and CrowdStrike postmortems show both the strength and the risk of that. What I designed was the specific combination: content addressing so the relays stay stateless, monotonic versions as a replay defense (which came from the security reviewer's objection to my first draft), and verification before swap on the client. Before Beacon, ZooKeeper clients read individual znodes, so there was no snapshot at all; the per-key model is what made A1's partial and global propagation possible. I chose snapshots over per-key versions because a flag change often touches 3–5 keys that must change together, and per-key versions can't express that."

</details>

<details><summary><b>Q2 · "What were the two losing options in your RFC, and who argued for each?"</b></summary>

**Initial Prompt.** "You said three alternatives. Name the two that lost and the person, by role, who championed each."

**L5 Answer.** "One was using Kafka, and the other was just using the database. I don't think anyone strongly argued for them; we evaluated them and they didn't fit."

**Why L5 Stalls.** Real alternatives have champions, because people propose them. "Nobody argued for them" suggests a strawman list written to make the chosen option look good, which is a common RFC smell that experienced interviewers recognize.

**L7 Answer.** "Option 1, Postgres plus polling, was championed by the platform architect, partly as a 'prove we need more' challenge, and fairly so: it carried the load in a test. It lost on coupling and on the missing atomic snapshot and ring pointer. Option 2, xDS through the mesh, was the SRE lead's, and it lost 2 of the 3 exit criteria we wrote together. I'll add a fourth that never made the RFC: Kafka with a compacted topic per namespace. I rejected it in my notes before the draft, because 2,100 mostly idle namespaces would be either 2,100 topics or one shared topic where 'latest snapshot for namespace X' needs a scan or a separate index. That's why it isn't in the RFC, and I'd add it to the appendix if I wrote it again, because reviewers asked about it twice."

</details>

<details><summary><b>Q3 · "Six engineers, nine months. Where did the 54 engineer-months go?"</b></summary>

**Initial Prompt.** The scribe does the arithmetic aloud: "Six engineers, nine months: 54 engineer-months. Break it down."

**L5 Answer.** "Most of it was building the system, and then the migration took a lot of time too. I'm not sure of the exact split."

**Why L5 Stalls.** A tech lead who doesn't know where the team's time went didn't plan the work. It's a capacity-fit check (§9), and "not sure" lets the interviewer conclude that the candidate's claimed scope may not fit the team.

**L7 Answer.** "Roughly: publisher, 8 engineer-months, of which I wrote about 5. Java SDK, 6, mostly mine. Rollout controller, 6, split with one engineer. Validator contract plus sandbox, 5. The relay tier belonged to the platform team, so 0 of ours. The bridge and comparator, 6. Migration support, 15: office hours, the compat-shim template, debugging 212 mismatches with owning teams. Interim ZooKeeper hardening for the audit, 3. Operations, on-call and the INC-B7 follow-ups, 5. That leaves no slack, which matches reality: we hit the colo date with 2 weeks to spare by dropping delta snapshots and the UI's diff viewer from scope. The Go, Python and Node ports came from the language-platform teams, outside our 54."

</details>

<details><summary><b>Q4 · "Which part of this system do you understand least?"</b></summary>

**Initial Prompt.** At minute 40: "Of everything on this board, which part do you understand least?"

**L5 Answer.** "I'd say I understand all of it pretty well, since I was on the project from the start."

**Why L5 Stalls.** Every senior engineer has a weakest area. Claiming none is either a lack of self-awareness or a bluff, and either one costs credibility on everything else. The probe rewards calibration.

**L7 Answer.** "The relay tier's behavior under a full regional restart. I know the client side, the jittered reconnects and the pointer-only first message, but not the relay's accept-queue or per-connection memory limits. We've never had a full regional restart in production, so my 3,200 reconnects per second estimate has never been tested against reality. Second weakest: the KMS's internal failure modes. I know our behavior when signing fails (the publisher halts and clients keep LKG), but not how the KMS degrades. Partial latency degradation in signing would slow publishes without failing them, and I don't have an alert for that. That's a gap I'd close."

</details>

<details><summary><b>Q5 · "If I called your SRE partner, what would they say you got wrong?"</b></summary>

**Initial Prompt.** "Suppose I phone your SRE partner tonight. What will they say you got wrong on this project?"

**L5 Answer.** "I think they'd say it went well. We had a good working relationship."

**Why L5 Stalls.** It's a self-critique probe framed as a reference check. Deflecting signals either low self-awareness or a fear of what the reference would say. Amazon's "Earn Trust" principle asks leaders to be "vocally self-critical, even when doing so is awkward or embarrassing".

**L7 Answer.** "Two things, and they'd be right on both. First, INC-B7: the non-atomic LKG write was my bug, and they'd point out that they had asked in the design review what happens if the process dies mid-write. I answered 'the signature check catches it', which was true and incomplete, because catching it led to serving defaults. Second, I under-invested in operator tooling early. For the first 2 months, diagnosing 'why is this instance on an old version' meant reading SDK logs, and the version-skew dashboard came from them, not from me. I'd also expect them to say the per-namespace `on_missing` policy was the right call over their global default, and we still disagree a little on that."

</details>

<details><summary><b>Q6 · "You keep saying 'we'. What did you, personally, do on the controller?"</b></summary>

**Initial Prompt.** The driver interrupts: "You've said 'we' about the rollout controller six times. What did *you* do on it?"

**L5 Answer.** "I mean, I was the tech lead, so I was involved in all of it. It was really a team effort."

**Why L5 Stalls.** "Involved in all of it" is the most common passenger phrase (§5.2). Being tech lead doesn't answer the question; it raises the stakes, because a TL who can't name their own contribution looks like a coordinator.

**L7 Answer.** "Fair catch. I designed the ring model and the gate logic, and wrote the gate evaluator. That covers comparing canary against baseline on error ratio and p99, plus the insufficient-signal hold: a ring doesn't advance if the canary saw fewer than 2,000 requests in the bake window. My co-author wrote the metrics adapter and the state machine's persistence. The 5 and 15 minute bake times were my proposal; the 2,000-request minimum came from her analysis of low-traffic namespaces, which showed about 4% of changes would otherwise advance on noise. So: model, gates, evaluator and bake times are mine; the adapter, the persistence and the minimum-signal threshold are hers."

</details>

<details><summary><b>Q7 · "Streams per relay: 1,800. But each instance watches several namespaces."</b></summary>

**Initial Prompt.** The scribe, 25 minutes after the architecture phase: "You said 1,800 streams per relay. But an instance watches several namespaces, the median being 3 or so. So isn't it 5,400?"

**L5 Answer.** "Oh, right, maybe it's more like 5,000 then. I'd have to check."

**Why L5 Stalls.** The candidate abandoned a correct number under mild pressure, which suggests they never understood its derivation. Now *both* numbers are suspect, and so is every other number on the board.

**L7 Answer.** "It's 1,800, because the stream is per instance, not per namespace. The SDK opens one multiplexed stream and sends a list of `(namespace, have_version)` pairs, and the relay answers with pointers for whichever ones changed. I chose that in the RFC because 3–4 streams per instance would have meant ~170,000 streams fleet-wide and 4× the reconnect storm after a relay restart. The cost is head-of-line effects: one stream carries all of an instance's namespaces, and a slow fetch of one big snapshot can delay applying another. The SDK handles that by fetching blobs concurrently, outside the stream."

</details>

<details><summary><b>Q8 · "Your manager set the deadline. So whose plan was the migration?"</b></summary>

**Initial Prompt.** "The colo date was fixed by facilities, and your EM owned the delivery. So who actually planned the migration, you or the EM?"

**L5 Answer.** "It was kind of both of us. The EM did the planning stuff and I did the technical side."

**Why L5 Stalls.** "Planning stuff" versus "technical side" is a fuzzy split that hides the real question: who decided the cutover order, the gates and the descoping? Those are architecture decisions with schedule consequences, and an L6+ candidate should own them.

**L7 Answer.** "The EM owned the dates, the staffing and the conversations with other teams' managers. I owned the technical plan inside those dates: the shadow-mode gate (a namespace can cut over only after 7 days with zero unexplained mismatches), the cutover order (lowest blast radius first, starting with internal tools, then the 37 services with known mismatches once they were fixed, payments last), the interim ZooKeeper hardening to meet the month-6 audit date, and the 2 scope cuts. When we were 3 weeks behind at month 6, the EM and I went to the director together. I brought the technical options, a shorter shadow window for low-risk namespaces or dropping the diff viewer; the EM brought the staffing option, and the director chose my first option for namespaces under 100 instances."

</details>

<details><summary><b>Q9 · "Show me something in this design you'd reject in code review today."</b></summary>

**Initial Prompt.** "Pick one thing in your own design that you'd reject if a junior engineer proposed it to you today."

**L5 Answer.** "Hmm, I'm not sure there's anything I'd reject. Maybe some naming in the code."

**Why L5 Stalls.** Only an author can criticize their own design specifically, so this probe is designed to separate authors from passengers. Naming is a non-answer. It also suggests the candidate hasn't grown since the project.

**L7 Answer.** "The break-glass lane's 'booleans only' rule, as I implemented it. I enforced it by the namespace type field, so any namespace typed `killswitch` could skip the bake. That's a convention, not a guarantee: a team typed a namespace `killswitch` and stored a rollout percentage in it as a string, so a percentage change could skip the bake. It happened once, harmlessly. Today I'd reject my own design in review, because a safety property shouldn't depend on naming. The fix is a schema-enforced kill-switch type whose values are literally `true`/`false`, validated by the same consumer-parser rule as everything else."

</details>

<details><summary><b>Q10 · "Explain the version gate to me as the engineer who'll maintain it."</b></summary>

**Initial Prompt.** "I'm the new owner of your SDK. Explain the version gate: what I must never break, and how I'd know if I broke it."

**L5 Answer.** "It checks that the new version is higher than the current one, and if it is, it applies the config. It's pretty straightforward."

**Why L5 Stalls.** "Pretty straightforward" is a description, not a handover. A maintainer needs the invariants, the exceptions, the guards and the history of why. Without those, the next owner will "simplify" it into a bug.

**L7 Answer.** "Three rules. One: never apply a version less than or equal to the applied version. That's the replay defense and the lagging-relay defense; the test `rejects_replayed_pointer` guards it. Two: the only exception is the emergency reset, a signed reset marker carrying 2 approver signatures that sets the floor back. It exists because a corrupted version counter in Postgres would otherwise freeze a namespace forever; it was used once, in a game day. Three: the gate runs after signature verification and before parsing, never before verification, or an attacker could raise the floor with an unsigned pointer and freeze the namespace. That's a denial of service, and `gate_after_verify` guards it. The alert is `config_version_rejected_total` rising; normally it's near 0, and a spike means a relay is serving stale pointers or something is replaying."

</details>

---

## 16. Checklist

- [ ] Every ★/◆/○ mark is backed by a row in your private ownership ledger (§4.2), with the artifact and your floor.
- [ ] Every ★ box passes the five-level self-test (§8) aloud in under 60 s per level.
- [ ] For each ★ box: the first version, what killed it, and who objected (§3.1).
- [ ] For each major decision: 2–3 real alternatives, each with a champion and a reason it lost (§3.2).
- [ ] Every interface you owned: its contract, field by field, and one boundary decision you defended (§3.7).
- [ ] One real disagreement, with its resolution and what you kept from the losing side (§3.9).
- [ ] The consistency web closes (§9), including the team-capacity check.
- [ ] Attribution grammar (§5.3) prepared for joint, inherited and influenced decisions.
- [ ] Scope stated precisely in your first sentence if your part was smaller than the project (§6).
- [ ] Every artifact you plan to mention has its follow-ups prepared (§7).
- [ ] Your written tellings pass `ownership_lint.py` (§13), and still sound natural spoken aloud.
- [ ] You can name the part of the system you understand least, and how you'd close the gap (Q4).

---

## 17. References

- Google re:Work, "A guide to structured interviewing for better hiring practices". <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
- Amazon Leadership Principles (Ownership; Earn Trust; Have Backbone; Disagree and Commit). <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
- About Amazon, "Amazon Bar Raisers". <https://www.aboutamazon.com/news/workplace/amazon-bar-raiser>
- Netflix culture memo (informed captains, farming for dissent). <https://jobs.netflix.com/culture>
- Michael Nygard, "Documenting Architecture Decisions" (2011). <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
- Google SRE Book, "Postmortem Culture: Learning from Failure". <https://sre.google/sre-book/postmortem-culture/>
- Cloudflare, "Cloudflare outage on November 18, 2025". <https://blog.cloudflare.com/18-november-2025-outage/>
- CrowdStrike, "Channel File 291 Incident Root Cause Analysis". <https://www.crowdstrike.com/wp-content/uploads/2024/08/Channel-File-291-Incident-Root-Cause-Analysis-08.06.2024.pdf>
- Will Larson, StaffEng, "Staff archetypes". <https://staffeng.com/guides/staff-archetypes/>
