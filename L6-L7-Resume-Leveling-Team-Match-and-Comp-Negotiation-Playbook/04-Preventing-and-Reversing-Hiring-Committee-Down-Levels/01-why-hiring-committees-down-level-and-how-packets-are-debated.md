# 04.1 · Why hiring committees down-level, and how packets are debated

> Folder 04 · Preventing and reversing hiring-committee down-levels · File 1 of 2 · [KB home](../README.md) · Next: [04.2 Tie-breaker and re-evaluation scripts](02-exact-scripts-to-request-a-tie-breaker-round-or-split-level-re-evaluation.md)

<!-- lint-pack: hc -->

| | |
|---|---|
| **Reader** | A candidate preparing for an L6 or L7 loop who wants to understand how the level is actually decided, and how to stop a down-level before it happens |
| **Running exhibit** | Candidate V's packets from Loop G (prepared and unprepared versions) and Loop A (§6) |
| **Listing** | `packet_sim.py`: an **illustrative** model of how a committee reads verdicts and level reads, which shows the swing round that decides your level (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run over four packets: unprepared G lands at L5, prepared G at L6, Loop A at L6 with two swing rounds, and one strong no-hire vetoes an otherwise strong packet. The 8 pairs in §8 are checked with `script_lint.py` (hc pack). |
| **Marks** | ⚠ = field practice, not published policy. **No company publishes its leveling algorithm.** The model in §5 is a teaching device, not a description of any company's committee. |

**Integrity rule.** You prevent a down-level by making real scope visible, never by inflating it. Committees read every round together; an inflated story in one round and an honest one in the next is the fastest route to "no hire".

---

## 0. The 60-second version

1. **Most down-levels are decided in one or two rounds:** usually a design round and the leadership or behavioral round. Find yours before the loop (02.3), and over-prepare them.
2. **Committees level on evidence they can attribute to you.** "We decided" is invisible; "I proposed X, wrote the design, and the director approved it" is levelable.
3. **A split packet usually resolves downward.** If half the level-critical rounds say L7 and half say L6, expect L6 ⚠.
4. **One strong no-hire can sink a packet** that is otherwise strong ⚠. Consistency across rounds matters more than one brilliant round.
5. **Interviewers write what you make easy to write.** End stories with your scope and outcome in one sentence, so the line that ends up in their feedback is the right one.
6. **The resume frames the packet.** If it claims more than the rounds showed, the committee discounts both (01.1).
7. **Know your swing round.** `packet_sim.py` shows which round would change your level, and therefore where a tie-breaker request would aim (04.2).

---

## 1. Who decides the level ⚠

| Process type | Who decides | What they read | What it means for you |
|---|---|---|---|
| **Committee** (Google-style) | A committee of people who generally didn't interview you; Google's former people chief has described this design publicly | Written feedback with scores, your resume, recruiter notes | Feedback quality is everything: they only know what interviewers wrote |
| **Debrief with a bar raiser** (Amazon-style) | The interviewers in a debrief; the bar raiser, an "objective third-party adviser", makes the final hiring decision with the hiring manager | Each interviewer's written feedback, discussed live | A down-level often means being offered a lower-level req ⚠ |
| **Candidate review** (Meta-style) | A review group, then team selection ⚠ | Written feedback, calibrated by level | Down-leveling after review is commonly reported ⚠ |
| **Hiring manager** (HM-driven) | The HM, sometimes with their manager | Feedback plus the HM's own impression | More negotiable, and more dependent on the HM call (03.1) |

Amazon's own description of the Bar Raiser role includes taking part in "the interview, feedback, reference checking, and debrief / hiring meeting decision process" and, "with hiring manager", making the final hiring decision ([About Amazon](https://www.aboutamazon.com/news/workplace/amazon-bar-raiser)).

---

## 2. Why down-levels happen

| Cause | What the packet shows | Prevention |
|---|---|---|
| **No level-specific signal** | Strong rounds, but every story and design stayed inside one team | Stories with cross-team scope; designs that handle ambiguity and evolution (§4) |
| **A split packet** | Design reads L7, leadership reads L6, or the reverse | Over-prepare the weaker area; know your swing round |
| **Attribution gaps** | "Candidate described the team's work well; unclear what they personally drove" | First-person decision grammar (§4.3) |
| **Scope that's too old or too small** | The best stories are five years old, or are one system | Recent cross-team stories first; old ones as mechanism examples |
| **Resume–interview mismatch** | Resume says "org-wide", stories say "my team" | Make the resume claim exactly what the stories show (01.1 §9) |
| **Interviewer calibration** | Interviewers below the target level struggle to judge it ⚠ | Ask about interviewer levels (02.3); make your reasoning explicit |
| **Req constraints** | Only a lower-level req is open | Ask about the req band on the first call (02.1) |
| **Risk aversion** | "Hire at L5 and let them prove L6 inside" ⚠ | Give the committee nothing to be unsure about; you can't fully control this one |

---

## 3. How packets are debated ⚠

### 3.1 What a packet contains

Typically: each interviewer's written feedback (what was asked, what you said, their assessment, a hire recommendation, often a level recommendation), your resume, and recruiter notes. Some processes add references or the hiring manager's view.

### 3.2 How the discussion tends to go

1. **Read for consistency.** Do the rounds tell one story about this person?
2. **Find the outliers.** A strong no-hire, or a round far above the others, gets discussed first.
3. **Look for the level evidence.** Which rounds show the target level's signal? Committees prefer quoted evidence ("candidate proposed three options and chose…") to adjectives ("strong").
4. **Resolve splits.** When rounds disagree on level, the committee weighs which rounds speak to level most (usually design and leadership), and doubt tends to resolve to the lower level.
5. **Decide, or ask for more.** Some committees request an additional round when the packet is close ⚠. That's the opening 04.2 uses.

### 3.3 What moves a committee

| Moves it | Doesn't |
|---|---|
| Specific evidence in the feedback: decisions, numbers, trade-offs | Adjectives ("brilliant", "very senior") |
| Consistency across rounds | One exceptional round among weak ones |
| Scope you clearly own | Scope you were near |
| A self-identified failure, owned | A story with no mistakes |

---

## 4. Preventing a down-level: before and during the loop

### 4.1 Before

- **A loop set up at the target level** (02.1): two design rounds or a deep dive, a leadership round.
- **A story bank with level-appropriate scope** (02.3), with a different primary story per round.
- **A steered deep dive:** pick the project that shows your depth area (01.2 §8 P8).
- **A resume that claims exactly what you'll show.**

### 4.2 During: what each round needs to show

| Round | L5 signal | L6 signal | L7 signal |
|---|---|---|---|
| **Coding** | Correct, clean, tested | The same, plus production concerns and trade-offs stated unprompted | The same; coding rarely decides L7, but a weak round can block it |
| **Design** | A working design for given requirements | Drives the requirements; several options with trade-offs; failure modes; how it evolves | Multi-system or org-level design; migration strategy; cost; what *not* to build |
| **Leadership / behavioral** | Delivered well within a team | Influenced across teams without authority; resolved conflict; grew others | Set direction across orgs; changed how many teams work; sustained over years |
| **Deep dive** | Knows the system well | Made the key decisions and can defend them, including mistakes | Shaped the system's direction and the org around it |

### 4.3 First-person decision grammar

Interviewers write down what you say. Give them sentences that carry your level:

| Instead of | Say |
|---|---|
| "We decided to use CDC." | "I proposed CDC over a faster batch, because the 30-minute freshness requirement ruled batch out. The data director approved the design." |
| "I was asked to build the reconciliation job." | "I noticed nothing verified the regulatory reports, so I proposed a reconciliation job and wrote it." |
| "The team migrated 14 teams off the release train." | "I wrote the migration plan the 14 teams followed and ran the weekly review where they reported blockers." |

### 4.4 End every story with a scope line

Close each behavioral story with one sentence that states your scope and the outcome: "So the policy I wrote now governs how about 2,000 engineers ship config, and config-caused Sev-1s went to zero." That sentence tends to end up in the feedback, close to verbatim ⚠.

### 4.5 Ask a Staff-level question at the end

"What would you want a Staff engineer on this team to change in their first year?" is a better closing question than "What's the culture like?" It's one more data point for the interviewer.

---

## 5. A transparent model of packet reading

To reason about *where* your level is decided, `packet_sim.py` uses a deliberately simple model. **It is not any company's algorithm.** It makes three common patterns explicit:

| Rule | Model | The real-world pattern it imitates ⚠ |
|---|---|---|
| **Hire** | No strong no-hire, and the average verdict is at least "lean hire" | A strong no-hire is hard to overcome; a packet of lukewarm yeses is fragile |
| **Level** | Only level-critical rounds (design, leadership, deep dive) vote; the level is the highest one supported by **more than half** of them | Committees weigh the rounds that speak to level; splits resolve downward |
| **Swing** | A critical round whose read, if one level higher, would change the outcome | Where one more piece of evidence would change the decision |

Verdicts use a common six-point scale: strong no-hire (SNH), no-hire (NH), lean no-hire (LNH), lean hire (LH), hire (H), strong hire (SH).

---

## 6. Candidate V's packets

### 6.1 Loop G, unprepared

Suppose V had walked into Loop G with team-scope stories and without driving the data-design requirements:

<!-- packet:start name=g-unprepared target=L6 expect=hire:L5 -->
| Round | Critical | Verdict | Level read |
|---|---|---|---|
| R1 Coding | no | H | L6 |
| R2 Coding | no | LH | L5 |
| R3 Design (serving) | yes | H | L6 |
| R4 Design (data) | yes | LH | L5 |
| R5 Leadership | yes | LH | L5 |
<!-- packet:end -->

### 6.2 Loop G, prepared

With the prep from 02.3 (two design areas, a different primary story per round, scope lines at the end of each story):

<!-- packet:start name=g-prepared target=L6 expect=hire:L6 -->
| Round | Critical | Verdict | Level read |
|---|---|---|---|
| R1 Coding | no | H | L6 |
| R2 Coding | no | LH | L5 |
| R3 Design (serving) | yes | H | L6 |
| R4 Design (data) | yes | H | L6 |
| R5 Leadership | yes | SH | L6 |
<!-- packet:end -->

The weaker coding round doesn't change the level: it isn't level-critical in this model, and the average stays well above "lean hire".

### 6.3 Loop A, the L7 attempt

<!-- packet:start name=a-l7-attempt target=L7 expect=hire:L6 -->
| Round | Critical | Verdict | Level read |
|---|---|---|---|
| R1 Coding + LPs | no | H | L6 |
| R2 Design + LPs | yes | SH | L7 |
| R3 Deep dive + LPs | yes | H | L7 |
| R4 Bar raiser | yes | LH | L6 |
| R5 Hiring manager | yes | H | L6 |
<!-- packet:end -->

Two critical rounds read L7 and two read L6, so the model resolves to L6, and it names R4 and R5 as swing rounds. That's the factual basis for the request in 04.2: one additional leadership-focused round reading L7 would make it three of five.

### 6.4 One strong no-hire

<!-- packet:start name=strong-no-veto target=L6 expect=no-hire -->
| Round | Critical | Verdict | Level read |
|---|---|---|---|
| R1 Coding | no | SNH | L5 |
| R2 Coding | no | H | L6 |
| R3 Design | yes | SH | L6 |
| R4 Design | yes | H | L6 |
| R5 Leadership | yes | SH | L6 |
<!-- packet:end -->

In this model, a single strong no-hire ends the packet regardless of the others. Real committees debate it, and sometimes overrule it ⚠, but the lesson holds: **don't treat coding as a formality at L6 and L7.**

---

## 7. What you can still do after the loop

- **Ask for the date and process** (02.3 Script 8).
- **Don't send "additional context" unprompted** unless the process invites it ⚠. A long email after the loop reads as anxiety.
- **If the level comes back lower,** go to 04.2, and run `packet_sim.py` with what the recruiter tells you to find the swing round.

---

## 8. Before → After: what goes into the feedback

#### S61 · Ending a story

| Version | Answer |
|---|---|
| **Weak** | So yeah, we decided to go with CDC and it worked out fine. |
| **Strong** | I proposed CDC over a faster batch, wrote the design with three options, and the data director approved it. Worst-case staleness went from 29.6 hours to a 3-minute p95. |

#### S62 · Opening a design round

| Version | Answer |
|---|---|
| **Weak** | I guess I'll just start drawing the main boxes and we can see. |
| **Strong** | Before I draw anything: who are the users, what's the scale, and what must never happen? I'll write down the three numbers that will drive the design. |

#### S63 · A conflict question

| Version | Answer |
|---|---|
| **Weak** | My manager was terrible at decisions, so I just did it my way. |
| **Strong** | My manager wanted to delay the cutover for a launch. I wrote down both options with their costs, we took them to our director together, and we split the cutover so the launch moved last. |

#### S64 · "What did you own?"

| Version | Answer |
|---|---|
| **Weak** | I was only a small part of a big team, everyone contributed. |
| **Strong** | I designed the snapshot format and the SDK semantics and wrote the Java reference SDK. The relay tier was another engineer's design that I reviewed. |

#### S65 · A failure question

| Version | Answer |
|---|---|
| **Weak** | Honestly, nothing really failed on that project. |
| **Strong** | We wrote the last-known-good file without an fsync. When a node was hard-stopped mid-write, 0.3% of instances served defaults for six minutes. That was my design; here's what we changed. |

#### S66 · The recruiter shares a lower level

| Version | Answer |
|---|---|
| **Weak** | The design interviewer was wrong about my approach, that's unfair. |
| **Strong** | Thanks for telling me. Which signal was missing for L7: scope, ambiguity or depth? I'd like to understand it before deciding anything. |

#### S67 · Describing how a project started

| Version | Answer |
|---|---|
| **Weak** | I was told to build a reconciliation job for the reports. |
| **Strong** | I noticed nothing verified the regulatory reports against the source, so I proposed a reconciliation job and wrote it. |

#### S68 · Closing a round

| Version | Answer |
|---|---|
| **Weak** | I hope I did okay, sorry I ran out of time on the last part. |
| **Strong** | What would you want a Staff engineer on this team to change in their first year? |

---

## 9. The listing: `packet_sim.py`

### 9.1 What it does

It applies the illustrative rules in §5 to each packet table: hire or no hire, the level, the swing rounds, and the gap to the target level. Use it in two ways:

- **Before the loop,** to see which rounds can decide your level, and how much one weak critical round costs.
- **After a down-level,** with whatever the recruiter tells you, to find the swing round your tie-breaker request should target (04.2).

To use it: copy the table format from §6 into `packet.md`, mark which rounds are level-critical, and run `python -I packet_sim.py packet.md`. Remember that the model's rules are a simplification.

### 9.2 Listing

<!-- include:packet_sim.py -->
```python
#!/usr/bin/env python3
"""packet_sim.py: an ILLUSTRATIVE model of how a committee might read an interview packet.

No company publishes its leveling algorithm, and real committees argue about evidence rather than compute.
This model only makes one common pattern explicit, so you can see which round decides your level:

  verdicts  SNH -3 · NH -2 · LNH -1 · LH +1 · H +2 · SH +3
  hire      no SNH anywhere, and mean verdict >= 1.0
  level     each round also records the level its evidence supports (L5/L6/L7). Only rounds marked
            critical (design, leadership, deep dive) vote on level. The level is the highest one that
            more than half of the critical rounds support, so a tie goes to the lower level.
  swing     a critical round whose read, if one level higher, would raise the outcome level

Reads every block like this from a Markdown file:

  <!-- packet:start name=my-loop target=L6 -->
  | Round | Critical | Verdict | Level read |
  |---|---|---|---|
  | R3 Design | yes | H | L6 |
  <!-- packet:end -->

Usage: python -I packet_sim.py FILE.md [--kb]
  --kb  check each block's expect=hire:LEVEL or expect=no-hire against the result.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*packet:start\s+(.*?)-->")
END = re.compile(r"<!--\s*packet:end\s*-->")
SCORE = {"SNH": -3, "NH": -2, "LNH": -1, "LH": 1, "H": 2, "SH": 3}
LEVELS = ["L4", "L5", "L6", "L7", "L8"]


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def read(path):
    blocks, cur, fenced = [], None, False
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if fenced:
            continue
        m = START.search(line)
        if m:
            cur = {"attrs": dict(re.findall(r"(\w+)=(\S+)", m.group(1))), "rows": []}
            continue
        if cur is not None and END.search(line):
            blocks.append(cur)
            cur = None
            continue
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] != "Round":
                cur["rows"].append(c)
    return blocks


def level_of(reads):
    best = None
    for lv in LEVELS:
        if sum(1 for r in reads if LEVELS.index(r) >= LEVELS.index(lv)) * 2 > len(reads):
            best = lv
    return best


def simulate(block):
    a = block["attrs"]
    rows = block["rows"]
    scores = [SCORE[r[2]] for r in rows]
    crit = [(r[0], r[3]) for r in rows if r[1].lower() == "yes"]
    mean = sum(scores) / len(scores)
    hire = "SNH" not in [r[2] for r in rows] and mean >= 1.0
    level = level_of([lv for _, lv in crit]) if hire and crit else None
    print(f"packet {a.get('name', '?')} (target {a.get('target', '?')}): mean verdict {mean:+.2f}")
    for r in rows:
        print(f"  {r[0]:<22} {'critical' if r[1].lower() == 'yes' else '        '}  {r[2]:<4} reads {r[3]}")
    if not hire:
        print("  outcome: no hire")
        return "no-hire"
    reads = [lv for _, lv in crit]
    print(f"  outcome: hire at {level}  (critical reads: {', '.join(reads)})")
    swings = []
    for i, (name, lv) in enumerate(crit):
        if lv == LEVELS[-1]:
            continue
        bumped = reads[:i] + [LEVELS[LEVELS.index(lv) + 1]] + reads[i + 1:]
        if LEVELS.index(level_of(bumped)) > LEVELS.index(level):
            swings.append(name)
    if swings:
        nxt = LEVELS[LEVELS.index(level) + 1]
        extra = LEVELS.index(level_of(reads + [nxt])) > LEVELS.index(level)
        print(f"  swing round(s): {', '.join(swings)}")
        print(f"  one additional critical round reading {nxt}: "
              + ("would change the outcome" if extra else "would not be enough on its own"))
    target = a.get("target")
    if target and target != level:
        print(f"  gap to target: {target} requested, {level} supported")
    return f"hire:{level}"


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    bad = []
    for block in read(argv[1]):
        outcome = simulate(block)
        exp = block["attrs"].get("expect")
        if kb and exp and exp != outcome:
            bad.append(block["attrs"].get("name", "?"))
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's four packets

<!-- run:packet_sim.py SELF --kb -->
```text
packet g-unprepared (target L6): mean verdict +1.40
  R1 Coding                        H    reads L6
  R2 Coding                        LH   reads L5
  R3 Design (serving)    critical  H    reads L6
  R4 Design (data)       critical  LH   reads L5
  R5 Leadership          critical  LH   reads L5
  outcome: hire at L5  (critical reads: L6, L5, L5)
  swing round(s): R4 Design (data), R5 Leadership
  one additional critical round reading L6: would not be enough on its own
  gap to target: L6 requested, L5 supported

packet g-prepared (target L6): mean verdict +2.00
  R1 Coding                        H    reads L6
  R2 Coding                        LH   reads L5
  R3 Design (serving)    critical  H    reads L6
  R4 Design (data)       critical  H    reads L6
  R5 Leadership          critical  SH   reads L6
  outcome: hire at L6  (critical reads: L6, L6, L6)

packet a-l7-attempt (target L7): mean verdict +2.00
  R1 Coding + LPs                  H    reads L6
  R2 Design + LPs        critical  SH   reads L7
  R3 Deep dive + LPs     critical  H    reads L7
  R4 Bar raiser          critical  LH   reads L6
  R5 Hiring manager      critical  H    reads L6
  outcome: hire at L6  (critical reads: L7, L7, L6, L6)
  swing round(s): R4 Bar raiser, R5 Hiring manager
  one additional critical round reading L7: would change the outcome
  gap to target: L7 requested, L6 supported

packet strong-no-veto (target L6): mean verdict +1.40
  R1 Coding                        SNH  reads L5
  R2 Coding                        H    reads L6
  R3 Design              critical  SH   reads L6
  R4 Design              critical  H    reads L6
  R5 Leadership          critical  SH   reads L6
  outcome: no hire

VERDICT: OK
```

---

## 10. Word-for-word scripts

#### Script 1 · Verbal: the scope line at the end of a behavioral story

```text
"So, to summarize my part: I wrote the RFC, I chose the ring design over two alternatives,
and I ran the cutover across about 2,000 engineers' services. The outcome was zero
config-caused Sev-1s in the following year, and the policy is still how every team ships
config."
```

#### Script 2 · Verbal: opening a design round at Staff level

```text
"Before I draw anything, let me pin down three things. Who uses this, and what do they need
in the first version? What's the scale now and in two years? And what must never happen:
data loss, double charges, a fleet-wide outage? I'll write the numbers down, because they'll
drive every choice that follows. Then I'll give you two or three options and pick one."
```

#### Script 3 · Verbal: making attribution explicit in a deep dive

```text
"Let me separate what I did from what the team did, so it's clear. I designed the snapshot
format, the signature check and the SDK semantics, and wrote the Java reference SDK. I co-wrote
the rollout controller with one engineer. The relay tier was another engineer's design, which
I reviewed. The Go and Python ports were the language-platform teams'."
```

#### Script 4 · Verbal: the closing question that adds signal

```text
"One question for you: what would you want a Staff engineer on this team to change in their
first year? I ask because I'd want to know where I'd start, and what you'd consider a real
contribution."
```

#### Script 5 · Verbal: when you know a round went badly

```text
"Thanks for working through that with me. I didn't get to the failure handling in the time we
had. If it's useful, the approach I'd take is [one sentence]. Either way, I appreciated the
problem."
```

(Say it once, briefly, in the room. Don't send a follow-up email to the interviewer.)

#### Script 6 · Email: after the loop, to the recruiter

```text
Subject: Thank you for today

Hi [Recruiter name],

Thank you for organizing the loop. I enjoyed it, especially the design discussion on
[topic].

When does the committee meet? And if the outcome is a different level than the one we
targeted, could you tell me which area drove it? It would help me decide on next steps
quickly.

Best,
[Your Name]
```

#### Script 7 · Verbal: asking the hiring manager what they saw (HM-driven processes)

```text
"Thank you for the loop. Before you decide, is there anything from the rounds where you'd
like more evidence? If there's a question about scope in a particular area, I'd rather
address it now than have it decide the level by default."
```

#### Script 8 · Verbal: the recruiter shares a lower level

```text
"Thank you for telling me, and for the work on the packet. Before I react, can you help me
understand it? Which areas read below the target level: design, leadership, or the deep
dive? And was it a split, with some rounds at the target level, or consistent across rounds?
I'll come back to you within a day."
```

#### Script 9 · Verbal: describing the start of a project with ownership

```text
"Nobody asked for it at first. I noticed that nothing verified the regulatory reports against
the source systems, so I wrote a one-page proposal for a reconciliation job, got the data
director to agree, and wrote it myself. It caught a dropped event before a report shipped."
```

---

## 11. Probe chains

<details><summary><b>P1 · "What was your role, specifically?"</b></summary>

**Probe:** "You keep saying 'we'. What did you personally do?"

**What they're testing:** attribution, the most common reason for a level gap in feedback.

**Executor answer:** "It was really a team effort; we all did everything together."

**Staff/Principal answer:** Script 3: separate your decisions and your code from the team's, with the ownership marks from the Past-Project playbook.

</details>

<details><summary><b>P2 · "Why is this a Staff-level problem?"</b></summary>

**Probe:** (Design interviewer) "This design is solid. What makes it Staff-level rather than Senior?"

**What they're testing:** whether you can name the level signal yourself.

**Executor answer:** "It's quite complex, with many components."

**Staff/Principal answer:** "Three things: the requirements were mine to define, because nobody had written them down; the design crosses four teams' systems, so the hard part is the contract between them; and I've designed for evolution, with a migration path from today's system that doesn't need a big-bang cutover."

</details>

<details><summary><b>P3 · "Tell me about a time you failed."</b></summary>

**Probe:** "What's the biggest mistake you've made in a design?"

**What they're testing:** ownership and learning, a Staff expectation at most companies.

**Executor answer:** "I'm a perfectionist, so I sometimes over-engineer."

**Staff/Principal answer:** The INC-B7 story (S65): a real design mistake with a number, owned, and the systemic changes it led to.

</details>

<details><summary><b>P4 · "This sounds more like your manager's decision."</b></summary>

**Probe:** (Bar raiser) "Wasn't the cutover timing really your manager's call?"

**What they're testing:** whether you'll overclaim when pushed, or underclaim.

**Executor answer:** "No, it was definitely my decision."

**Staff/Principal answer:** "The timing was a joint decision with my manager and our director. My part was the options document: I laid out three sequencing options with their costs, and recommended the split that moved the launch's namespaces last. They chose my recommendation."

</details>

<details><summary><b>P5 · "Why do you think you're L7?"</b></summary>

**Probe:** (Hiring manager, Loop A) "What makes you a Principal rather than a strong Senior SDE III?"

**What they're testing:** whether your L7 case survives a direct challenge.

**Executor answer:** "I have 14 years of experience and I've worked on many large systems."

**Staff/Principal answer:** "One example clearly at the Principal bar: the config-safety policy changed how every team in a 2,000-engineer company ships, and it's held for two years. I have fewer sustained cross-org examples than I'd like, and I know that's the question. The rest of my work, like the PCI program, is strong Staff scope."

</details>

<details><summary><b>P6 · "Why didn't you finish the design?"</b></summary>

**Probe:** "We ran out of time before failure handling. Why?"

**What they're testing:** time management and prioritization, which at L6 includes managing the interview itself.

**Executor answer:** "The question was really big; there wasn't enough time."

**Staff/Principal answer:** "I spent too long on requirements. Next time I'd timebox them to ten minutes. The failure handling I'd have covered: [two sentences]."

</details>

<details><summary><b>P7 · (Committee view) "The leadership round was lean hire at L6."</b></summary>

**Probe:** (A committee member, reading the packet) "Design reads L7, but leadership reads L6. Which do we believe?"

**What they're testing:** (you're not in the room) whether the packet contains enough leadership evidence at the target level.

**Executor answer:** (What a thin packet produces) The committee resolves the split downward. The leadership feedback says "good collaborator"; there's no cross-org evidence to quote.

**Staff/Principal answer:** (What a prepared packet produces) The leadership feedback quotes a specific cross-org decision with dissenters and an outcome, and the design feedback notes "drove requirements, chose between three options". The split narrows, and a tie-breaker request has a basis (04.2).

</details>

<details><summary><b>P8 · "Your resume says org-wide. Your stories say team."</b></summary>

**Probe:** (Committee member) "The resume claims org-wide policy, but every story was about one team."

**What they're testing:** consistency between paper and loop.

**Executor answer:** (What an inflated resume produces) The member discounts both; the packet lands at L5.

**Staff/Principal answer:** (What a consistent candidate produces) At least one story is the org-wide one, told with names, dissent and adoption numbers, so the resume and the loop corroborate each other. Prepare that before the loop: for each L7-style resume bullet, a story in the bank (02.3).

</details>

---

## 12. Checklist

**Before the loop**
- [ ] Your likely swing rounds identified (02.3 prep call, `packet_sim.py`).
- [ ] At least two stories with cross-team scope for the leadership round, and one at the L7 bar if targeting L7.
- [ ] A scope line rehearsed for every story (Script 1).
- [ ] First-person decision grammar practiced (§4.3).
- [ ] Coding prepared as seriously as design (§6.4).

**During**
- [ ] Requirements driven in every design round (Script 2).
- [ ] Attribution explicit in the deep dive (Script 3).
- [ ] A Staff-level closing question (Script 4).

**After**
- [ ] The committee date asked; no unprompted follow-ups (Script 6).
- [ ] If the level is lower: understand before reacting (Script 8), then 04.2.

---

## 13. References

- Amazon's Bar Raiser role in the debrief and hiring decision: [About Amazon](https://www.aboutamazon.com/news/workplace/amazon-bar-raiser).
- Structured interviewing and evidence-based feedback: [Google re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices).
- Google's committee design, described by its former head of People Operations: Laszlo Bock, *Work Rules!* (Twelve, 2015), ISBN 9781455554799.
- How committees detect scope by level: [Behavioral playbook 01.1](../../Staff-Principal-Behavioral-L7-Playbook/01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md).
- How interviewers test ownership: [Past-Project playbook 01.2](../../Past-Project-Deep-Dive-L7-Defense-Playbook/01-Anatomy-of-the-60-Minute-Deep-Dive-Round/02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md).
