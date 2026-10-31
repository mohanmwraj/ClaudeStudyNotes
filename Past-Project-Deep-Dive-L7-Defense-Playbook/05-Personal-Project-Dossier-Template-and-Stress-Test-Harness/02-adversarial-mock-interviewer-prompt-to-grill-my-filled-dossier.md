# 05.2 · Adversarial Mock-Interviewer Prompt to Grill My Filled Dossier

> **Folder:** `05-Personal-Project-Dossier-Template-and-Stress-Test-Harness` · file 2 of 2
> **Question this file answers:** how do I get a realistic, hostile, 60-minute cross-examination of *my* dossier before the real one, from an LLM in a chat window or from a human partner, and score it against the same signals a hiring committee uses?
> **Contents:** a copy-paste mock-interviewer prompt (§2), the probe library it draws on (§3), a deterministic probe-plan generator (§4, §9), the protocol for running and scoring mocks (§5–§6), and a sample plan generated from the Beacon dossier in [05.1](01-fill-in-the-blank-l7-project-rfc-and-whiteboard-script-template.md).
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L15 `grill_plan.py` | Python 3, standard library | Turns a filled dossier into a timed probe plan for two interviewers:<br>- provenance and boundary probes for every ★ component;<br>- a derivation probe for every [E] number, re-asked in another form 15–25 minutes later;<br>- a measurement probe for every [M] number;<br>- "was it real?" for every Hard constraint;<br>- the champion's case for every rejected option;<br>- floor probes into each well;<br>- archaeology, hindsight and a late redraw probe. | [§9](#9-the-probe-plan-generator), on the Beacon dossier in 05.1 |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, re-runs it against the final 05.1 file, and compares the result with §9. Its verdict checks that every ★ component, estimate, Hard constraint, rejected option and hindsight row is probed, and that every consistency re-ask lands at least 15 minutes after its number. This file's tellings are linted by the Folder 01 tools. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

There are two ways to run the grill:
- **With an LLM:** paste the prompt in §2 into a new chat with Claude (or another capable model), then paste your filled dossier and, optionally, the probe plan from `grill_plan.py`. Answer in writing or by voice. No API access or code is needed. This knowledge base never calls a paid API on your behalf.
- **With a human partner,** ideally a senior engineer who doesn't know your project: give them the probe plan (§4) and the scoring sheet (§6). The plan lets someone who has never seen your system ask the questions a skeptical Principal Engineer would.

Run at least two mocks: one with the LLM to find the gaps cheaply, and one with a human to test delivery under real social pressure.

---

## 1. First principles: what makes a mock worth doing

### 1.1 Five properties of a useful mock

| Property | Why it matters | How the prompt enforces it |
|---|---|---|
| **Adversarial** | Friendly mocks rehearse the happy path, and the real round won't | Instructed skepticism; no praise during the round; every claim probed |
| **Evidence-seeking** | Committees score evidence, not fluency (01.1 §1.1) | Derivation for numbers, provenance for ownership, archaeology for failures |
| **Consistent** | The scribe's re-asks catch reconstruction (01.2 §9) | Scheduled consistency checks 15–25 minutes after a number |
| **Time-boxed** | Pacing is a scored skill (01.1) | A simulated clock with phase targets; monologues interrupted |
| **Scored** | Without a score you can't tell whether the second mock was better | The 7-signal scorecard with verbatim quotes as evidence (§6) |

### 1.2 The sycophancy problem

Language models tend to be agreeable by default, and a mock that compliments you has failed. The prompt therefore:
- forbids praise and coaching until the debrief;
- requires the interviewer to name the *weakest* evidence for each signal;
- instructs it to challenge claims that contradict the dossier.

If your mock still feels comfortable, tell it so: "You are being too easy; probe harder on ownership and numbers." Prompting guidance from model providers recommends being explicit about role, rules and output format, and structuring long prompts with tags ([Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)). The prompt below follows that structure.

---

## 2. The prompt (copy everything inside the fence)

```xml
<mock_interview>
  <role>
    You are two senior interviewers running a 60-minute "past project technical deep dive"
    for an L6/L7 (Staff/Principal) engineering candidate.
    Interviewer A (driver): a Principal Engineer who has built larger versions of the
    candidate's system. A steers depth, keeps time, and asks most questions.
    Interviewer B (prober/scribe): a Principal Engineer who takes notes, checks consistency,
    and probes ownership, cost and second-order effects.
    Both are skeptical by default: complexity is guilty until proven necessary, and every
    claim is a hypothesis to test. You are evaluating evidence, not encouraging the candidate.
  </role>

  <inputs>
    The candidate's dossier follows in <dossier>. A probe plan may follow in <probe_plan>.
    Target level: <target_level>. Company lens (optional): <lens>.
    Treat the dossier as the candidate's claims, not as facts. Contradictions between the
    dossier and what the candidate says in the room are evidence; note them.
  </inputs>

  <format>
    - Simulate a 60:00 clock. Prefix every interviewer turn with [mm:ss] and A: or B:.
    - Ask ONE question per turn, then stop and wait for the candidate's answer.
    - Advance the clock by your estimate of how long the candidate's answer would take spoken.
    - Never answer for the candidate, never hint at the answer, never coach, never praise
      during the round. Neutral acknowledgements ("Go on.") are allowed.
    - If an answer would run past 3 minutes of speech, interrupt it as a real interviewer would.
    - At 60:00, or when the candidate types END, stop and produce the debrief in <debrief_format>.
  </format>

  <phases>
    00-02 intros and project selection | 02-04 headline (expect <= 90 s) |
    04-09 context (expect numbers) | 09-16 architecture and ownership |
    16-28 deep dive 1 | 28-38 deep dive 2 or failure story | 38-44 trade-offs |
    44-49 impact | 49-52 hindsight | 52-60 remaining probes.
    If the candidate is behind (no depth by 20:00), take control of the agenda, as real
    interviewers do.
  </phases>

  <rules>
    1. Numbers: for every number the candidate states, ask either how it was derived or how
       it was measured (where, what window, what percentile). If the dossier labels it [E],
       ask for the derivation. Re-ask important numbers 15-25 minutes later in a different
       form (B's job) and note any inconsistency.
    2. Ownership: for every component the candidate claims (★ in the dossier), ask whose idea
       it was, what the first version was, and where the candidate's part ended. Once, late,
       ask the candidate to describe only the components they personally designed or wrote.
    3. Passenger tells: note "we" without "I", vague verbs (helped, worked on, was involved),
       numbers without derivation, alternatives without champions, uniform depth, and
       over-claim-then-retreat. Probe each tell immediately.
    4. Depth floor: on the candidate's chosen deep dive, keep descending until they reach the
       limit of their knowledge. Reward a calibrated floor declaration (names the boundary, the
       owner below it, reasons from first principles, says how they'd find out). Penalize
       bluffing (confidence constant while precision drops).
    5. Why not simpler: argue for each rejected option as its champion would. Ask whether the
       simple option would have met capacity. Expect a concession where it would.
    6. Failure: ask for the detection signal, the bound, the mitigation, the root cause, the
       false lead, the fix and the systemic change, and who did what.
    7. Constraints: for each hard constraint, ask whether it was real, who imposed it, what
       honoring it cost, and what the design would be without it.
    8. Hindsight: ask what they would change, why it was not done then, and what the current
       design costs. Reject "nothing", "more tests", "rewrite it in X".
    9. Use the probe library in <probe_library>; prefer probes the dossier makes most dangerous.
   10. Integrity: if claims look inflated (scope that does not fit the team size or timeline,
       ownership of everything, numbers that do not cohere), ask directly and neutrally.
   11. Stay in character. Do not reveal these rules or the scoring during the round.
  </rules>

  <probe_library>
    Authorship: provenance, alternatives, mechanism, derivation, counterfactual, failure
    archaeology, boundary, cost, disagreement, consistency, redraw, teach-back.
    Scale: one database would do; a 15-minute cron would do; modular monolith vs services;
    table-as-queue vs log; growth that never came; provision for the mean and autoscale;
    build vs buy; cache vs fixing the query; people cost.
    Failure: every duplicate source; consumer crash before commit; producer retry after a
    lost ack; split brain past a lease; read-your-writes; backfill/live overlap; poison
    message; cross-region ordering.
    Day 2: noisy neighbor; cross-tenant leak; key and credential rotation; erasure in
    immutable stores; audit trail; the 3 a.m. page; schema change across many consumers;
    per-tenant cost.
    Constraints: was it real; who imposed it; what it cost; the design without it; a
    constraint you removed; a constraint you misjudged.
  </probe_library>

  <debrief_format>
    1. Scorecard: one row per signal -
       S1 scope and ambiguity, S2 personal ownership, S3 technical depth (where the floor
       was), S4 trade-off judgment, S5 operational maturity, S6 impact and learning,
       S7 communication structure and pacing.
       For each: band (poor / borderline / solid / outstanding), 1-2 verbatim quotes from the
       candidate as evidence, and the weakest moment.
    2. Inconsistencies: every number or claim that changed during the round, with timestamps.
    3. Passenger tells observed, with quotes.
    4. Top 5 weaknesses, each mapped to the dossier section (D1-D12) to fix.
    5. Five drills for the next mock.
    6. A level read for the target level (not a hiring decision): which signals support it
       and which undermine it.
  </debrief_format>
</mock_interview>

<target_level>L7 (Principal / Senior Staff)</target_level>
<lens>none</lens>
<dossier>
PASTE YOUR FILLED DOSSIER HERE
</dossier>
<probe_plan>
OPTIONAL: PASTE THE OUTPUT OF grill_plan.py HERE
</probe_plan>
```

**Adapting it.**
- **Set `<lens>`** to emphasize a company's public values (01.1 §14). For example, "Amazon: dive deep, ownership, disagree and commit".
- **Set `<target_level>`** to L6 for a Staff loop. The interviewers will then expect less organizational scope.
- **For a 45-minute round,** scale the phase windows by 0.75.
- **To drill a single area,** add one line: "Spend 70% of the round on failure modes (Q10–Q17)."

---

## 3. Which dossier fields trigger which probes

| Dossier field | Probes it triggers | Where the answers are |
|---|---|---|
| D1 headline | Scope, role precision, "give me the 90-second version" | 01.1 §7.2 |
| D3 kill criteria | "Was that threshold real? Who set it?" | 02.1 §3 |
| D4 ★ rows | Provenance, boundary, redraw, teach-back | 01.2 §3 |
| D4 floor column | Depth-floor descent; the calibrated declaration | 01.1 §11.1 |
| D5 Hard rows | Constraint stress tests | 01.3 §7 |
| D6 rejected options | Why-not-simpler from the champion's side; close calls | 02.1, 04.1 |
| D7 [E] rows | Derivation, then consistency 15–25 minutes later | 02.2 §11, 01.2 §9 |
| D7 [M] rows | "Measured where, over what window?" | 02.2 §1.1 |
| D8 level 5 | "What breaks first?" | Folder 03 failure sections |
| D9 failure | Archaeology, the false lead, your role | 01.1 §7.6 |
| D10 rows | "Why not then?"; decision vs outcome | 02.3 |
| D11 script | Pacing: interrupts if you run long | 01.1 §8–§10 |

---

## 4. The deterministic probe plan

An LLM varies its questions from run to run, which is good for breadth and bad for measuring progress. `grill_plan.py` produces the *same* plan from the same dossier every time, so you can compare your answers across mocks. It also gives a human partner a script. §9 shows the plan for the Beacon dossier: 36 probes over 60 minutes, split between A and B. The consistency re-asks are scheduled 15 to 25 minutes after the derivation of the same number, the window in which reconstructed answers drift.

---

## 5. The protocol

| Step | What to do | Why |
|---|---|---|
| 1 | Run `dossier_check.py` until READY | Don't spend a mock discovering empty sections |
| 2 | Generate the plan with `grill_plan.py` | Repeatable questions |
| 3 | Mock 1 (LLM), answering by voice if you can, timed | Finds gaps cheaply |
| 4 | Score with the debrief; fix the dossier sections named | Close the gaps |
| 5 | Mock 2 (human), same plan plus their own probes | Delivery under social pressure |
| 6 | Compare the two scorecards signal by signal | Measure progress |
| 7 | Mock 3 a week before the loop, with the company lens set | Lens-specific emphasis |

**Record yourself.** The transcript is the evidence, and listening back is when you hear the "we decided" you didn't notice saying. Paste your written answers into `ownership_lint.py` (01.2 §13) as tellings: the passenger tells it flags are the ones the scribe would write down.

---

## 6. Scoring sheet (for a human interviewer)

| Signal | Poor | Borderline | Solid | Outstanding | Quote (evidence) |
|---|---|---|---|---|---|
| S1 Scope | | | | | |
| S2 Ownership | | | | | |
| S3 Depth (floor at: ___) | | | | | |
| S4 Trade-offs | | | | | |
| S5 Operations | | | | | |
| S6 Impact and learning | | | | | |
| S7 Structure and pacing | | | | | |

Anchors for each band: 01.1 §15 (structure), 01.2 §11 (ownership), 01.3 §11 (constraints), 02.1 §11 (trade-offs), 02.2 §12 (quantification), 02.3 §11 (hindsight), and the archetype rubrics in Folder 03. **Only quotes count as evidence.** A cell without a quote is an impression, and committees discount impressions.

---

## 7. Tellings: answering the grill's two hardest moves

### 7.1 The consistency re-ask

#### How an L5 tells it

> Hmm, I think the canary was maybe around 500 instances or so. It was basically 1% of the fleet, roughly, I'd have to check.

#### How an L7 tells it

> 480: it's 1% of the 48,000 instances, and ring0 is 1 canary cell in us-west sized to that. It's consistent with INC-B7, too: the 140 restarted instances were about 29% of the canary cell, which is why that incident touched 0.3% of the fleet rather than 1%.

### 7.2 The floor, under pressure

#### How an L5 tells it

> I'm not totally sure, but I think the relays basically just handle reconnects with gRPC flow control, so it should be fine.

#### How an L7 tells it

> That's below where I worked: the relay team owned connection handling, and I reviewed only the protocol. What I can reason about is the client side, which is mine. About 1,800 streams per relay, reconnects jittered from 0 to 5 seconds, and a first message that's only a version pointer, so a regional restart is about 3,200 reconnects a second of tiny messages. To answer properly I'd read the relay load test's connection-setup rate, because that number decides whether 3,200 a second is safe.

---

## 8. Hiring-committee scoring rubric: mock readiness

| Dimension | Not ready | Borderline | Ready (L6) | Ready (L7) |
|---|---|---|---|---|
| **Mock count** | 0 | 1 friendly | 2 adversarial (LLM + human) | 3, the last with the lens set |
| **Consistency** | Numbers drift | Mostly stable | Stable under re-asks | Stable, and re-derived on the spot |
| **Floor behavior** | Bluffs | Stops | Declares the floor | Declares it, reasons past it, names how to find out |
| **Scorecard trend** | Not tracked | Tracked | Improving on the weakest signals | All signals solid; 3+ outstanding with quotes |
| **Dossier loop** | Unchanged after mocks | Patched | Sections rewritten from the debriefs | The harness re-run READY after each rewrite |

---

## 9. The probe-plan generator

### 9.1 Listing L15: `grill_plan.py`

<!-- listing:grill_plan.py -->
```python
#!/usr/bin/env python3
"""grill_plan.py - turn a filled dossier into a timed, adversarial probe plan.

Reads the first dossier whose name does not start with "blank" (from the
second argument if given, else the first) and schedules probes over a
60-minute round for two interviewers, A (driver) and B (prober/scribe):

  provenance + boundary   one each per starred (★) component in D4
  derivation              every [E] number in D7, asked by A when it is stated
  consistency             the same number re-asked by B 15-25 minutes later, in another form
  measurement             every [M] number: "measured where, over what window?"
  constraint test         every Hard constraint in D5: "was it real?"
  why-not-simpler         every rejected option in D6, from its champion's side
  floor                   every well in D8 at level 5 ("what breaks")
  archaeology             the D9 failure story's root cause
  hindsight               every D10 row: "why not then?"
  redraw                  "erase it; draw only what you built" (once, late)

The plan is deterministic, so a human partner or an LLM (05.2) can run the
same grill twice and compare the candidate's answers.
Usage: python -I grill_plan.py <file.md> [<dossier file.md>]
"""
import re
import sys


def table(body):
    rows = [r for r in body.splitlines() if r.strip().startswith("|")]
    return [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows][2:]


def mmss(s):
    return f"{s // 60:02d}:{s % 60:02d}"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    path = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1]
    md = open(path, encoding="utf-8").read().replace("\r\n", "\n")
    dossiers = [(n, t) for n, t in re.findall(r"<!-- dossier:start name=(\S+) -->\n(.*?)<!-- dossier:end -->", md, re.S)
                if not n.startswith("blank")] or [("file", md)]
    name, text = dossiers[0]
    parts = re.split(r"^### (D\d+)\. .*$", text, flags=re.M)
    sec = {parts[i]: parts[i + 1] for i in range(1, len(parts) - 1, 2)}

    probes = []   # (minute, who, kind, text)
    stars = [r for r in table(sec.get("D4", "")) if len(r) >= 6 and "★" in r[1]]
    for i, r in enumerate(stars):
        m = 17 + 3 * i
        probes.append((m * 60, "A", "provenance", f"Whose idea was the {r[0]} design, and what was its first version?"))
        probes.append((m * 60 + 90, "B", "boundary", f"Where exactly did your part of {r[0]} end? State the contract."))
    nums = table(sec.get("D7", ""))
    pairs = []    # (derivation time, consistency re-ask time) per estimated number
    for i, r in enumerate(nums):
        stated = 5 * 60 + 40 * i
        if "[E]" in r[2]:
            probes.append((stated, "A", "derivation", f"You said {r[1]} for {r[0].lower()}. Derive it."))
            later = stated + 15 * 60 + (i % 3) * 5 * 60
            probes.append((later, "B", "consistency", f"Earlier you gave {r[0].lower()} as {r[1]}. What does that imply for the inputs?"))
            pairs.append((stated, later))
        elif "[M]" in r[2]:
            probes.append((stated + 20, "B", "measurement", f"{r[0]} = {r[1]}: measured where, over what window, by whom?"))
    hard = [r for r in table(sec.get("D5", "")) if len(r) >= 9 and r[4] == "Hard"]
    for i, r in enumerate(hard):
        probes.append(((7 + i) * 60, "B", "constraint test", f"{r[0]}: '{r[1][:60]}'. Was that real? What did honoring it cost?"))
    opt = [r for r in [[c.strip() for c in row.strip().strip("|").split("|")]
                       for row in sec.get("D6", "").splitlines() if row.strip().startswith("|")]]
    if opt:
        header = opt[0][2:]
        chosen_row = [r for r in opt if r and r[0].lower() == "chosen"]
        champ_row = [r for r in opt if r and r[0].lower() == "champion"]
        for j, o in enumerate(header):
            is_chosen = chosen_row and chosen_row[0][2 + j].lower().startswith("yes")
            if not is_chosen:
                champ = champ_row[0][2 + j] if champ_row else "its champion"
                probes.append(((39 + 2 * j) * 60, "A", "why-not-simpler",
                               f"Argue for '{o}' as {champ} would. Why did it lose, with a number?"))
    wells = table(sec.get("D8", ""))
    if len(wells) >= 5:
        for j in range(1, min(4, len(wells[4]))):
            probes.append(((24 + 2 * j) * 60, "A", "floor", f"Go one level below '{wells[4][j][:50]}'. What breaks first?"))
    m = re.search(r"\*\*Root cause[^*]*\*\*\s*(.+)", sec.get("D9", ""))
    if m:
        probes.append((30 * 60, "B", "archaeology", f"Root cause: '{m.group(1)[:70]}'. What did you see first, and what was the false lead?"))
    for i, r in enumerate(table(sec.get("D10", ""))):
        if len(r) >= 8:
            probes.append(((49 + i) * 60, "A", "hindsight", f"{r[0]}: '{r[1][:55]}'. Why wasn't the change made then?"))
    probes.append((53 * 60, "B", "redraw", "Erase the board. Draw only the components you personally designed or wrote."))
    probes.sort(key=lambda p: (p[0], p[1], p[2]))

    print(f"grill_plan for dossier '{name}': {len(probes)} probes over 60 minutes (A = driver, B = prober)")
    print()
    for t, who, kind, q in probes:
        print(f"  {mmss(t)}  {who}  {kind:<16} {q}")
    kinds = {}
    for _, _, k, _ in probes:
        kinds[k] = kinds.get(k, 0) + 1
    print()
    print("  by kind: " + ", ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
    estimates = sum(1 for r in nums if "[E]" in r[2])
    ok = (len(stars) > 0 and kinds.get("provenance", 0) == len(stars)
          and kinds.get("derivation", 0) == estimates == len(pairs)
          and all(later - stated >= 15 * 60 for stated, later in pairs)
          and kinds.get("constraint test", 0) == len(hard)
          and kinds.get("redraw", 0) == 1 and max(p[0] for p in probes) <= 60 * 60)
    print("verdict:", "OK (every starred component, estimate, hard constraint, rejected option and hindsight row is probed; "
          "consistency re-asks land 15+ min after the number)" if ok else "CHECK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 9.2 Output: the plan for the Beacon dossier in 05.1

<!-- output:grill_plan.py 01-fill-in-the-blank-l7-project-rfc-and-whiteboard-script-template.md -->
```text
grill_plan for dossier 'beacon-filled': 36 probes over 60 minutes (A = driver, B = prober)

  05:20  B  measurement      Instances at peak = ~48,000: measured where, over what window, by whom?
  05:40  A  derivation       You said 4,800 QPS for polling load. Derive it.
  06:40  B  measurement      Replica load test = 12,000 QPS: measured where, over what window, by whom?
  07:00  A  derivation       You said ~1,800 for streams per relay. Derive it.
  07:00  B  constraint test  K1: 'ZooKeeper ensemble gone before the colo lease ends (M9)'. Was that real? What did honoring it cost?
  07:40  A  derivation       You said ~864 MB per change for widest fan-out. Derive it.
  08:00  B  constraint test  K2: 'SOC 2 finding: open ACLs on the ensemble'. Was that real? What did honoring it cost?
  08:20  A  derivation       You said ~480 instances for canary ring size. Derive it.
  09:00  B  constraint test  K3: 'PCI services need ticketed approval per change'. Was that real? What did honoring it cost?
  09:20  B  measurement      Propagation = p99 24 s: measured where, over what window, by whom?
  10:20  A  derivation       You said ~140 instances, 0.3% for inc-b7 exposure. Derive it.
  11:00  A  derivation       You said ~860× for exposure reduction. Derive it.
  17:00  A  provenance       Whose idea was the Publisher design, and what was its first version?
  18:30  B  boundary         Where exactly did your part of Publisher end? State the contract.
  20:00  A  provenance       Whose idea was the SDK (Java) design, and what was its first version?
  21:30  B  boundary         Where exactly did your part of SDK (Java) end? State the contract.
  22:00  B  consistency      Earlier you gave streams per relay as ~1,800. What does that imply for the inputs?
  23:00  A  provenance       Whose idea was the Rollout controller design, and what was its first version?
  24:30  B  boundary         Where exactly did your part of Rollout controller end? State the contract.
  25:40  B  consistency      Earlier you gave polling load as 4,800 QPS. What does that imply for the inputs?
  26:00  A  floor            Go one level below 'Truncated LKG; KMS outage halts publishes; lagging'. What breaks first?
  26:00  A  provenance       Whose idea was the ZooKeeper bridge design, and what was its first version?
  26:00  B  consistency      Earlier you gave exposure reduction as ~860×. What does that imply for the inputs?
  27:30  B  boundary         Where exactly did your part of ZooKeeper bridge end? State the contract.
  27:40  B  consistency      Earlier you gave widest fan-out as ~864 MB per change. What does that imply for the inputs?
  28:00  A  floor            Go one level below 'Low-traffic namespaces lack signal (2,000-request '. What breaks first?
  30:00  A  floor            Go one level below 'Intentional changes create mismatch noise; flappin'. What breaks first?
  30:00  B  archaeology      Root cause: 'I wrote the LKG file in place without fsync, so a hard stop left a tru'. What did you see first, and what was the false lead?
  33:20  B  consistency      Earlier you gave canary ring size as ~480 instances. What does that imply for the inputs?
  35:20  B  consistency      Earlier you gave inc-b7 exposure as ~140 instances, 0.3%. What does that imply for the inputs?
  39:00  A  why-not-simpler  Argue for 'O1 Postgres polling' as platform architect would. Why did it lose, with a number?
  41:00  A  why-not-simpler  Argue for 'O2 Mesh xDS' as SRE lead would. Why did it lose, with a number?
  49:00  A  hindsight        B1: 'Compiled-in defaults as the fallback'. Why wasn't the change made then?
  50:00  A  hindsight        B2: 'Relay tier instead of xDS'. Why wasn't the change made then?
  51:00  A  hindsight        B3: 'Break-glass enforced by naming'. Why wasn't the change made then?
  53:00  B  redraw           Erase the board. Draw only the components you personally designed or wrote.

  by kind: archaeology 1, boundary 4, consistency 6, constraint test 3, derivation 6, floor 3, hindsight 3, measurement 3, provenance 4, redraw 1, why-not-simpler 2
verdict: OK (every starred component, estimate, hard constraint, rejected option and hindsight row is probed; consistency re-asks land 15+ min after the number)
```

**Reading the plan.**
- **Ownership:** each of the 4 starred components gets a provenance probe from A and a boundary probe from B.
- **Estimates:** each of the 6 [E] numbers is derived when stated and re-asked by B 15–25 minutes later.
- **Constraints and options:** the 3 Hard constraints are tested, and both rejected options are argued from their champions' side.
- **Depth:** the 3 wells are probed at level 5.
- **Late probes:** the round ends with the hindsight rows and the redraw.

Hand this to a partner as-is, or paste it into the prompt's `<probe_plan>`.

---

## 10. Failure modes (of mock practice)

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | The friendly mock | You finish feeling good | Tell the mock it's too easy; use the human partner |
| F2 | Memorized answers | Perfect phrasing, drift under re-asks | Practice derivations, not sentences (02.2 §11) |
| F3 | Overfitting to the LLM | Answers tuned to one model's question style | The deterministic plan plus a human mock |
| F4 | No recording | "I think I did fine" | Transcripts; quotes in the scorecard |
| F5 | Fixing delivery, not content | Smoother, but the same weak sections | Map each weakness to a D-section and rewrite it |
| F6 | Mocking with invented facts | Rehearsing a project you didn't do | The integrity rule (05.1 §0): the mock only helps with real facts |

---

## 11. Bar-raiser chains (from the Beacon probe plan)

<details><summary><b>Q1 · [17:00] A: "Whose idea was the Publisher design, and what was its first version?"</b></summary>

**Initial Prompt.** The first provenance probe from the plan.

**L5 Answer.** "It was a team design. We iterated on it in a few meetings and landed on snapshots."

**Why L5 Stalls.** No first version, no author, and "iterated in meetings" contains no decision knowledge (01.2 §1.2).

**L7 Answer.** "Mine, and its first version was wrong in an instructive way. The draft made rollback a version decrement. The security reviewer asked what stops a replay of an old signed pointer, and the draft had no answer, so versions became monotonic and rollback became a roll-forward. That also made lagging relays harmless, which I hadn't designed for."

</details>

<details><summary><b>Q2 · [18:30] B: "Where exactly did your part of the Publisher end? State the contract."</b></summary>

**Initial Prompt.** The boundary probe that follows provenance.

**L5 Answer.** "I owned the whole publishing side, so I'm not sure there was a boundary as such."

**Why L5 Stalls.** Every component has interfaces. "No boundary" means the candidate didn't own one, or over-claims the whole system.

**L7 Answer.** "Input: the Postgres change log, read in sequence order. Output: a blob in each regional object store plus an announcement to relays of namespace, version and digest. Guarantees: blobs are immutable and content-addressed, versions per namespace only go up, nothing over 4 megabytes is published. Not mine: the announcer's retry tuning, which another engineer wrote, and everything relay-side after the announcement."

</details>

<details><summary><b>Q3 · [05:40] A: "You said 4,800 QPS for polling load. Derive it."</b></summary>

**Initial Prompt.** The first derivation probe, early in the context phase.

**L5 Answer.** "That's what the capacity planning showed for the polling option."

**Why L5 Stalls.** Pointing at a document isn't a derivation. B will now distrust every number.

**L7 Answer.** "48,000 instances polling every 10 seconds is 4,800 a second. Each is a point read on an indexed key, about 2 milliseconds, so by Little's law roughly 10 queries are in flight. The load test sustained 12,000 a second on 1 replica, so polling would run it at about 40%, which is why I never argued against Postgres on load."

</details>

<details><summary><b>Q4 · [22:00] B: "Earlier you gave streams per relay as ~1,800. What does that imply for the inputs?"</b></summary>

**Initial Prompt.** A consistency re-ask, 15+ minutes after the number was first stated.

**L5 Answer.** "It means each relay handled a lot of connections, so we needed enough relays."

**Why L5 Stalls.** It doesn't connect the number to the inputs. The probe tests whether the candidate knows that 1,800 assumes one stream per instance.

**L7 Answer.** "It implies 1 stream per instance, not per namespace: 48,000 instances over 27 relays. If streams were per namespace, at 3 to 4 namespaces per instance, it would be about 6,000 per relay and 4 times the reconnect storm. That's why the SDK multiplexes all of an instance's namespaces on 1 stream."

</details>

<details><summary><b>Q5 · [07:00] B: "K1: 'ZooKeeper ensemble gone before the colo lease ends'. Was that real? What did honoring it cost?"</b></summary>

**Initial Prompt.** The first constraint stress test.

**L5 Answer.** "Yes, leadership was clear the data center was closing, so it was a hard deadline."

**Why L5 Stalls.** "Leadership was clear" is hearsay (01.3 Q1). The cost of honoring the date is never stated.

**L7 Answer.** "Real and priced: an extension was a 6-month minimum at about $190,000 a month, and I asked finance for that quote in week 3. Honoring it cost 2 deferred features, delta snapshots and the diff viewer, and a 3-day shadow window for about 60% of namespaces, approved by the director with an expiry. I'd have paid for the extension if the migration had been at risk of a Sev-1."

</details>

<details><summary><b>Q6 · [39:00] A: "Argue for O1 Postgres polling as the platform architect would. Why did it lose, with a number?"</b></summary>

**Initial Prompt.** The champion's case for the first rejected option.

**L5 Answer.** "The architect wanted it to be simple, but it wouldn't have scaled to our needs."

**Why L5 Stalls.** It contradicts the load test (40% of 1 replica) and strawmans the architect.

**L7 Answer.** "The architect's case is strong: no new tier, no new on-call, and the load fits at about 40% of 1 replica. I agree with all of it. It lost on 1 kill criterion: there's no atomic multi-key snapshot or ring pointer, so holding a bad change to 1% of instances for 5 minutes would mean rebuilding staging in 4 client libraries. On the scored rows it was close, 55 to 50, and with blast radius weighted lower, polling wins."

</details>

<details><summary><b>Q7 · [28:00] A: "Go one level below 'Low-traffic namespaces lack signal'. What breaks first?"</b></summary>

**Initial Prompt.** The floor probe into Well 2.

**L5 Answer.** "Then the canary might not catch problems, but that's pretty rare."

**Why L5 Stalls.** "Pretty rare" doesn't describe a mechanism, and the probe is designed to find the floor.

**L7 Answer.** "A 1% canary of about 480 instances can't see a meaningful error ratio for a namespace whose services get only a few requests a minute, so the gate holds the ring for insufficient signal, about 4% of changes. What breaks first is the human workaround: owners ask for manual advances. My floor is the statistics: my co-author derived the 2,000-request minimum and I can't reproduce the power calculation. For a low-traffic namespace I'd want synthetic probes in the canary, which I proposed and didn't build."

</details>

<details><summary><b>Q8 · [53:00] B: "Erase the board. Draw only the components you personally designed or wrote."</b></summary>

**Initial Prompt.** The redraw probe, late in the round.

**L5 Answer.** The candidate redraws almost everything.

**Why L5 Stalls.** Redrawing everything contradicts a 6-person team and the dossier's own ledger. It's the clearest over-claim signal (01.2 §3.11).

**L7 Answer.** The candidate draws 4 boxes, the same 4 as the dossier's ★ rows: the publisher, the Java SDK, the rollout controller and the ZooKeeper bridge. They name each co-author and what they didn't write, and leave the relays, the ports, the API and the metrics adapter off, saying why.

</details>

---

## 12. Checklist

- [ ] Dossier READY under `dossier_check.py` (05.1 §9).
- [ ] Probe plan generated with `grill_plan.py` and saved with the dossier.
- [ ] Mock 1 with the §2 prompt; debrief saved; weaknesses mapped to D-sections.
- [ ] Dossier sections rewritten; harness re-run READY.
- [ ] Mock 2 with a human partner using the plan and the §6 scoring sheet.
- [ ] Scorecards compared signal by signal.
- [ ] Mock 3 with the company lens set, a week before the loop.
- [ ] Your answers to the consistency re-asks stable across all mocks (§7.1).

---

## 13. References

- Anthropic, "Prompting best practices" (role, explicit instructions, XML structure). <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Anthropic, "Prompt engineering overview". <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview>
- Google re:Work, "A guide to structured interviewing for better hiring practices" (structured questions, written evidence, calibrated rubrics). <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
- About Amazon, "Amazon Bar Raisers" (debriefs driven by data). <https://www.aboutamazon.com/news/workplace/amazon-bar-raiser>
