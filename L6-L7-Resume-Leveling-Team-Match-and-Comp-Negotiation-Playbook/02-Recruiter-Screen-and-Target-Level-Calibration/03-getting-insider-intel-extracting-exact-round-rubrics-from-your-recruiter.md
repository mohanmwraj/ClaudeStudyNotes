# 02.3 · Getting insider intel: extracting exact round rubrics from your recruiter

> Folder 02 · Recruiter screen and target-level calibration · File 3 of 3 · [KB home](../README.md) · Previous: [02.2 Comp anchoring and timeline sync](02-deflecting-early-comp-anchoring-and-timeline-synchronization-across-5-loops.md) · Next folder: [03.1 The hiring-manager sell call](../03-Hiring-Manager-Screen-and-Team-Match-Mastery/01-the-hiring-manager-sell-call-diagnosing-their-pain-in-the-first-10-minutes.md)

<!-- lint-pack: recruiter -->

| | |
|---|---|
| **Reader** | A candidate whose loop is scheduled, who wants to know exactly what each round assesses and at what level, before preparing |
| **Running exhibit** | Candidate V's loops G (committee-based) and A (bar-raiser, leadership principles), with V's story bank (§5) |
| **Listing** | `intel_ledger.py`: turns what the recruiter said about each round into a prep plan, assigns a primary story per round, and lists the questions still unanswered (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run over three round tables: the raw notes from a rushed call raise 8 asks and a gap; the prepped Loop G and Loop A tables come back clean. The 8 pairs in §7 are checked with `script_lint.py` (recruiter pack). |
| **Marks** | ⚠ = field practice, not published policy. Never ask for interview questions; this file is about the *shape* of the loop. |

**Integrity rule.** Ask for everything a recruiter is allowed to share: rounds, focus, format, level, competencies, prep materials. Never ask for the questions, and never use questions someone leaked to you. Beyond the ethics, a leaked question you "know" invites a performance that interviewers are trained to probe past, and it's grounds for disqualification.

---

## 0. The 60-second version

1. **Recruiters want you to pass.** Most will share far more than candidates ask for: round count, focus, format, the competencies each round scores, prep guides, and what usually separates the levels ⚠.
2. **Ask in four layers:** the loop's shape; each round's focus and signals; the level bar and who interviews; and where candidates at your level usually lose the level.
3. **Read the shape as a level signal.** Two design rounds plus a leadership or deep-dive round is an L6+ shape; one design round is usually a Senior shape ⚠.
4. **Map every signal to a story or a practice plan.** Give each behavioral or design round its own *primary* story, so the committee doesn't read the same story four times.
5. **Unknowns are questions, not guesses.** Every "?" in your notes becomes a specific ask in your follow-up email.
6. **Run `intel_ledger.py`** on your notes. It prints the gaps and the asks.
7. **Ask after the loop too:** for the timeline, the committee date, and whatever feedback the company shares.

---

## 1. What recruiters can share, and what they can't ⚠

| Usually shareable | Sometimes shareable | Not shareable |
|---|---|---|
| Number, type and order of rounds | Interviewers' names, teams and levels | The questions |
| Each round's focus area | How the committee or debrief weighs rounds | Other candidates' feedback |
| Format: length, tool, whiteboard or shared doc | Feedback after the loop | Anything that identifies a past candidate |
| The competencies or principles the loop assesses | Where candidates at your level commonly lose the level | — |
| Prep guides and practice materials | A prep call with the recruiter or a coordinator | — |
| Timeline, committee date, team-match steps | Whether a round can be swapped or rescheduled | — |

Some of the competency frameworks are public. Amazon publishes its Leadership Principles, and its interviewers ask behavioral questions mapped to them ([Amazon Leadership Principles](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)). Google has published guidance on structured interviewing, which is the reason its interviewers score against defined attributes rather than impressions ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). Knowing that a loop is structured tells you to prepare *evidence per signal*, not a general impression.

---

## 2. The intel question bank

Ask these on a dedicated 15-minute "prep call" after scheduling. Recruiters often offer one; if not, ask for it (Script 1).

### 2.1 The loop's shape

1. "How many rounds, of which types, and in what order?"
2. "Is this the standard shape for an L6 loop here?"
3. "Is there a past-project deep dive, and how is it run?"
4. "Is there a round with a senior leader, such as a director, and what is it for?"

### 2.2 Each round

5. "What's the focus of each design round: product-facing, infrastructure, data-intensive?"
6. "Which competencies or principles does each behavioral round assess?"
7. "What's the format: length, tool, whiteboard or shared doc, language choice for coding?"
8. "Are coding rounds run in a plain editor or an IDE? Is running code expected?"

### 2.3 Level and people

9. "Is each round calibrated at L6? Are the interviewers L6 or above?"
10. "Which teams are the interviewers from: the hiring team, or across the company?"
11. "Is there a bar raiser or equivalent, and what's their role?"

### 2.4 Where the level is decided

12. "Where do strong candidates at my level usually lose the level?"
13. "What separates an L6 outcome from an L5 outcome in the design rounds?"
14. "How much does the leadership round weigh relative to the design rounds?"
15. "Who decides the level after the loop, and when do they meet?"

### 2.5 After the loop

16. "When is the committee or debrief, and when should I expect to hear?"
17. "Is team matching before or after the offer?"
18. "If the outcome is a different level, will I hear why?"
19. "Do you share feedback with candidates?"
20. "Is there anything else in your prep materials I should read?"

---

## 3. Reading between the lines ⚠

| What you hear | What it often means | What to do |
|---|---|---|
| "Two design rounds and a leadership round" | An L6+ shape | Prepare two distinct design areas and a leadership story set |
| "One design round, two coding" | A Senior shape | Revisit the level (02.1, Script 3) before the loop, not after |
| "A deep dive on a past project" | Staff/Principal consideration; ownership is being tested | Prepare the deep dive with the [Past-Project playbook](../../Past-Project-Deep-Dive-L7-Defense-Playbook/README.md) |
| "A conversation with a director" | A scope and judgment check | Prepare direction-setting stories, and questions about the org's problems |
| "Interviewers from across the company" | Calibration is general, not team-specific | Don't rely on the team's domain; show general Staff signal |
| "Candidates often struggle to show cross-team impact" | The leadership round is where levels are lost | Over-prepare it (Folder 04 explains why) |
| "The bar raiser may ask anything" | An independent judgment of the bar | Prepare principles depth, and keep every story true at depth |

---

## 4. Turning intel into a prep plan

1. **One row per round:** focus, signals, level bar, format. Mark unknowns with "?".
2. **Split signals into practice and stories.** Coding and design mechanics are practice; influence, conflict, ownership and direction are stories.
3. **Give each story-based round a primary story,** a different one for each round. A committee reading four write-ups of the same story concludes you have one story.
4. **Keep backups.** Each signal should have at least two stories that could cover it, in case the interviewer asks for "another example".
5. **Turn every "?" into a question** for your follow-up email.

That's exactly what `intel_ledger.py` does with your notes (§9).

---

## 5. Candidate V's notes and story bank

### 5.1 The story bank

The stories come from V's exhibits ([01.1 §2.4](../01-L6-L7-Resume-Engineering-and-Narrative-Positioning/01-anatomy-of-a-faang-l6-l7-resume-impact-density-and-scope-markers.md#24-the-running-exhibit-candidate-v-composite)). Signal names include general Staff signals and Amazon's Leadership Principles, so one bank serves every loop. The first version lacks a mentoring story; the second adds one.

<!-- stories:start name=v-bank-v1 -->
| Story | Signals |
|---|---|
| Beacon RFC | direction; influence; ambiguity; conflict; system design; think big; have backbone; earn trust |
| Beacon INC-B7 | failure; ownership; operational excellence; dive deep; insist on the highest standards |
| Tillpoint PCI program | influence; cross-team delivery; conflict; prioritization; deliver results; earn trust |
| Tidewater reconciliation | correctness; data; ambiguity; are right a lot; insist on the highest standards |
| Tillpoint idempotency | system design; correctness; customer impact; customer obsession; dive deep |
| Quickset cache | performance; trade-offs; dive deep; invent and simplify; frugality |
| Flightline memo | trade-offs; influence; constraints; frugality; invent and simplify; bias for action |
| Lodestar eval gate | ai systems; measurement; influence; learn and be curious; think big |
<!-- stories:end -->

<!-- stories:start name=v-bank-v2 -->
| Story | Signals |
|---|---|
| Beacon RFC | direction; influence; ambiguity; conflict; system design; think big; have backbone; earn trust |
| Beacon INC-B7 | failure; ownership; operational excellence; dive deep; insist on the highest standards |
| Tillpoint PCI program | influence; cross-team delivery; conflict; prioritization; deliver results; earn trust |
| Tidewater reconciliation | correctness; data; ambiguity; are right a lot; insist on the highest standards |
| Tillpoint idempotency | system design; correctness; customer impact; customer obsession; dive deep |
| Quickset cache | performance; trade-offs; dive deep; invent and simplify; frugality |
| Flightline memo | trade-offs; influence; constraints; frugality; invent and simplify; bias for action |
| Lodestar eval gate | ai systems; measurement; influence; learn and be curious; think big |
| Design apprenticeship | mentoring; raising the bar; hire and develop the best |
<!-- stories:end -->

The "design apprenticeship" story: at the marketplace, V paired two engineers with RFCs they led end to end, reviewed every draft, and both later led cross-team designs on their own (composite).

### 5.2 Loop G: raw notes from a rushed call

<!-- rounds:start name=raw-loop-g stories=v-bank-v1 -->
| Round | Focus | Signals | Level bar | Format |
|---|---|---|---|---|
| R1 Coding | ? | practice: problem solving; practice: code quality | ? | ? |
| R2 Coding | algorithms | practice: problem solving; practice: testing | L6 | shared doc |
| R3 Design | ? | system design; trade-offs | ? | ? |
| R4 Design | data systems | system design; correctness; data | L6 | ? |
| R5 Leadership | leadership | influence; conflict; mentoring | ? | video |
<!-- rounds:end -->

### 5.3 Loop G: after the prep call

<!-- rounds:start name=prepped-loop-g stories=v-bank-v2 -->
| Round | Focus | Signals | Level bar | Format |
|---|---|---|---|---|
| R1 Coding | data structures, graphs | practice: problem solving; practice: code quality | L6 | 45 min, shared doc, no execution |
| R2 Coding | algorithms with tests | practice: problem solving; practice: testing | L6 | 45 min, shared doc |
| R3 Design | large-scale serving system | system design; trade-offs | L6 | 45 min, drawing tool |
| R4 Design | data-intensive pipeline | system design; correctness; data | L6 | 45 min, drawing tool |
| R5 Leadership | leadership and collaboration | influence; conflict; mentoring | L6 | 45 min, behavioral |
<!-- rounds:end -->

### 5.4 Loop A: leadership principles per interviewer ⚠

In bar-raiser loops, each interviewer is commonly assigned a few Leadership Principles to probe ⚠. V asked the recruiter which principles each round would emphasize; this is what V was told:

<!-- rounds:start name=prepped-loop-a stories=v-bank-v2 -->
| Round | Focus | Signals | Level bar | Format |
|---|---|---|---|---|
| R1 Coding + LPs | coding, then principles | practice: problem solving; customer obsession; dive deep | L7 | 60 min |
| R2 Design + LPs | distributed system design | system design; think big; invent and simplify | L7 | 60 min |
| R3 Deep dive + LPs | a past project | dive deep; are right a lot; have backbone | L7 | 60 min |
| R4 Bar raiser | principles | earn trust; hire and develop the best; insist on the highest standards | L7 | 60 min |
| R5 Hiring manager | principles and scope | ownership; deliver results; think big | L7 | 60 min |
<!-- rounds:end -->

---

## 6. After the loop: the intel you can still gather

- **The decision date:** "When does the committee meet, and when should I expect to hear?"
- **The level question:** "If the outcome is a different level than we targeted, will you tell me why?" (This sets up Folder 04.)
- **Feedback:** many large companies don't share detailed feedback ⚠. Ask anyway, once, politely.
- **Team match:** "Is team matching before or after the offer, and how many teams usually take part?" (Folder 03.2).

---

## 7. Before → After: intel questions

#### S21 · Asking about the rounds

| Version | Answer |
|---|---|
| **Weak** | Sorry to bother you, but I was wondering if maybe you could tell me a bit about the interviews? |
| **Strong** | Could you walk me through the loop: how many rounds, their focus and format, and which competencies each one assesses? I'd like to prepare against exactly what you'll be scoring. |

#### S22 · Asking about the questions

| Version | Answer |
|---|---|
| **Weak** | Is there any way you could share the actual questions, off the record? |
| **Strong** | I won't ask for questions, of course. What would help is the focus of each design round: product-facing, infrastructure or data-intensive? |

#### S23 · Asking where the level is decided

| Version | Answer |
|---|---|
| **Weak** | I guess I'm kind of nervous about the level, is it hard to get Staff? |
| **Strong** | Where do strong candidates at L6 usually lose the level in this loop? I'd like to put my preparation where it matters most. |

#### S24 · When the loop looks like a Senior loop

| Version | Answer |
|---|---|
| **Weak** | Only one design round? Okay, whatever level the panel decides is fine. |
| **Strong** | I noticed there's one design round. For an L6 loop I'd expect two, or a deep dive. Can we confirm the loop is calibrated at L6 before it's scheduled? |

#### S25 · Asking about interviewers

| Version | Answer |
|---|---|
| **Weak** | Do you know if the interviewers are nice? I hope they're not too tough. |
| **Strong** | Are the interviewers L6 or above, and are they from the hiring team or across the company? It changes how much I should lean on the team's domain. |

#### S26 · Asking for prep materials

| Version | Answer |
|---|---|
| **Weak** | Just wanted to check if there's anything at all I could read, if that's okay. |
| **Strong** | Do you have a prep guide for the L6 loop? And if there's a prep call with a coordinator, I'd like to book it. |

#### S27 · After the loop

| Version | Answer |
|---|---|
| **Weak** | Sorry for asking again, do you have any update at all? |
| **Strong** | Thanks again for organizing the loop. When does the committee meet, and if the level differs from what we targeted, will you be able to tell me why? |

#### S28 · Asking about a principles-based loop

| Version | Answer |
|---|---|
| **Weak** | I don't really know the principles that well, is that a problem? |
| **Strong** | Which Leadership Principles will each interviewer focus on? I have stories for all of them and I'd like to bring the strongest for each round. |

---

## 8. Using the intel without over-fitting

- **Intel is about shape, not content.** Prepare for the focus area broadly; don't memorize three designs and hope.
- **Don't announce your intel in the room.** "The recruiter said you'd ask about…" makes an interviewer change course.
- **Plan for a different interviewer.** Schedules change on the day; your plan should survive a swapped round.
- **Keep a story fresh for the last round.** The hiring-manager or bar-raiser round often asks "tell me something you haven't told the others."

---

## 9. The listing: `intel_ledger.py`

### 9.1 What it does

For each round table, it:

- turns every "?" into a specific question to ask;
- picks a primary story per round, preferring stories not already used as another round's primary;
- checks that every non-practice signal is covered by at least one story, and lists all candidates per signal as backups.

To use it: copy the two table formats from §5 into `loop.md`, one story bank and one round table per loop, and run `python -I intel_ledger.py loop.md`. Resolve every ASK, GAP and REUSE before the loop.

### 9.2 Listing

<!-- include:intel_ledger.py -->
```python
#!/usr/bin/env python3
"""intel_ledger.py: turn what the recruiter told you about each round into a prep plan, and list what to ask.

Reads two kinds of block from a Markdown file:

  <!-- stories:start name=my-bank -->
  | Story | Signals |
  |---|---|
  | Config RFC | direction; influence; system design |
  <!-- stories:end -->

  <!-- rounds:start name=loop-g stories=my-bank -->
  | Round | Focus | Signals | Level bar | Format |
  |---|---|---|---|---|
  | R3 Design | large-scale serving | system design; trade-offs | L6 | 45 min |
  | R1 Coding | ? | practice: problem solving | ? | ? |
  <!-- rounds:end -->

'?' marks something you don't know yet; each one becomes a question to ask. Signals starting 'practice:' are
covered by practice, not by a story. For the rest, each round gets a primary story (the unused story covering
the most of its signals) and every signal must be covered by at least one story.

Flags: ASK (an unknown field), GAP (a signal no story covers), REUSE (a round whose only candidates are
already some other round's primary story).
Usage: python -I intel_ledger.py FILE.md [--kb]
  --kb  rounds blocks named 'raw-*' must raise flags; every other rounds block must be clean.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*(stories|rounds):start\s+(.*?)-->")
END = re.compile(r"<!--\s*(stories|rounds):end\s*-->")
ASKS = {
    "Focus": "What's the focus of {r}?",
    "Signals": "Which signals or competencies does {r} assess?",
    "Level bar": "Is {r} calibrated at the target level, and who interviews (level, team)?",
    "Format": "What's the format of {r}: length, tool, whiteboard or shared doc?",
}


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def read(path):
    banks, rounds, cur, fenced = {}, [], None, False
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if fenced:
            continue
        m = START.search(line)
        if m:
            cur = {"kind": m.group(1), "attrs": dict(re.findall(r"(\w+)=(\S+)", m.group(2))), "rows": []}
            continue
        if cur is not None and END.search(line):
            if cur["kind"] == "stories":
                banks[cur["attrs"]["name"]] = cur["rows"]
            else:
                rounds.append(cur)
            cur = None
            continue
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] in ("Story", "Round"):
                continue
            cur["rows"].append(c)
    return banks, rounds


def sig(text):
    return [s.strip().lower() for s in text.split(";") if s.strip() and s.strip() != "?"]


def ledger(block, banks):
    a = block["attrs"]
    bank = [(s, set(sig(t))) for s, t in banks.get(a.get("stories", ""), [])]
    flags, used = [], set()
    print(f"rounds {a.get('name', '?')} (story bank: {a.get('stories', '-')}, {len(bank)} stories)")
    for rnd, focus, signals, level, fmt in block["rows"]:
        for field, val in (("Focus", focus), ("Signals", signals), ("Level bar", level), ("Format", fmt)):
            if val == "?":
                flags.append(f"ASK {ASKS[field].format(r=rnd)}")
        need = [s for s in sig(signals) if not s.startswith("practice:")]
        practice = [s.split(":", 1)[1].strip() for s in sig(signals) if s.startswith("practice:")]
        if not need:
            print(f"  {rnd}: practice only ({', '.join(practice) or 'unknown'})")
            continue
        scored = sorted(((len(set(need) & sigs), -i, name) for i, (name, sigs) in enumerate(bank)
                         if set(need) & sigs), reverse=True)
        fresh = [x for x in scored if x[2] not in used]
        if fresh:
            primary = fresh[0][2]
            used.add(primary)
        elif scored:
            primary = scored[0][2]
            flags.append(f"REUSE {rnd}: every candidate story is already a primary elsewhere ({primary})")
        else:
            primary = "-"
        print(f"  {rnd}: primary = {primary}" + (f"; practice: {', '.join(practice)}" if practice else ""))
        for s in need:
            cover = [name for name, sigs in bank if s in sigs]
            if cover:
                print(f"    {s:<34} <- {', '.join(cover)}")
            else:
                print(f"    {s:<34} <- (none)")
                flags.append(f"GAP {rnd}: no story shows '{s}'")
    for f in flags:
        print(f"  {f}")
    print(f"  result: {'clean' if not flags else str(len(flags)) + ' item(s) to resolve'}")
    return a.get("name", "?"), flags


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    banks, rounds = read(argv[1])
    bad = []
    for block in rounds:
        name, flags = ledger(block, banks)
        if kb and name.startswith("raw-") != bool(flags):
            bad.append(name)
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's three round tables

<!-- run:intel_ledger.py SELF --kb -->
```text
rounds raw-loop-g (story bank: v-bank-v1, 8 stories)
  R1 Coding: practice only (problem solving, code quality)
  R2 Coding: practice only (problem solving, testing)
  R3 Design: primary = Beacon RFC
    system design                      <- Beacon RFC, Tillpoint idempotency
    trade-offs                         <- Quickset cache, Flightline memo
  R4 Design: primary = Tidewater reconciliation
    system design                      <- Beacon RFC, Tillpoint idempotency
    correctness                        <- Tidewater reconciliation, Tillpoint idempotency
    data                               <- Tidewater reconciliation
  R5 Leadership: primary = Tillpoint PCI program
    influence                          <- Beacon RFC, Tillpoint PCI program, Flightline memo, Lodestar eval gate
    conflict                           <- Beacon RFC, Tillpoint PCI program
    mentoring                          <- (none)
  ASK What's the focus of R1 Coding?
  ASK Is R1 Coding calibrated at the target level, and who interviews (level, team)?
  ASK What's the format of R1 Coding: length, tool, whiteboard or shared doc?
  ASK What's the focus of R3 Design?
  ASK Is R3 Design calibrated at the target level, and who interviews (level, team)?
  ASK What's the format of R3 Design: length, tool, whiteboard or shared doc?
  ASK What's the format of R4 Design: length, tool, whiteboard or shared doc?
  ASK Is R5 Leadership calibrated at the target level, and who interviews (level, team)?
  GAP R5 Leadership: no story shows 'mentoring'
  result: 9 item(s) to resolve

rounds prepped-loop-g (story bank: v-bank-v2, 9 stories)
  R1 Coding: practice only (problem solving, code quality)
  R2 Coding: practice only (problem solving, testing)
  R3 Design: primary = Beacon RFC
    system design                      <- Beacon RFC, Tillpoint idempotency
    trade-offs                         <- Quickset cache, Flightline memo
  R4 Design: primary = Tidewater reconciliation
    system design                      <- Beacon RFC, Tillpoint idempotency
    correctness                        <- Tidewater reconciliation, Tillpoint idempotency
    data                               <- Tidewater reconciliation
  R5 Leadership: primary = Tillpoint PCI program
    influence                          <- Beacon RFC, Tillpoint PCI program, Flightline memo, Lodestar eval gate
    conflict                           <- Beacon RFC, Tillpoint PCI program
    mentoring                          <- Design apprenticeship
  result: clean

rounds prepped-loop-a (story bank: v-bank-v2, 9 stories)
  R1 Coding + LPs: primary = Tillpoint idempotency; practice: problem solving
    customer obsession                 <- Tillpoint idempotency
    dive deep                          <- Beacon INC-B7, Tillpoint idempotency, Quickset cache
  R2 Design + LPs: primary = Beacon RFC
    system design                      <- Beacon RFC, Tillpoint idempotency
    think big                          <- Beacon RFC, Lodestar eval gate
    invent and simplify                <- Quickset cache, Flightline memo
  R3 Deep dive + LPs: primary = Beacon INC-B7
    dive deep                          <- Beacon INC-B7, Tillpoint idempotency, Quickset cache
    are right a lot                    <- Tidewater reconciliation
    have backbone                      <- Beacon RFC
  R4 Bar raiser: primary = Tillpoint PCI program
    earn trust                         <- Beacon RFC, Tillpoint PCI program
    hire and develop the best          <- Design apprenticeship
    insist on the highest standards    <- Beacon INC-B7, Tidewater reconciliation
  R5 Hiring manager: primary = Lodestar eval gate
    ownership                          <- Beacon INC-B7
    deliver results                    <- Tillpoint PCI program
    think big                          <- Beacon RFC, Lodestar eval gate
  result: clean

VERDICT: OK
```

The raw notes produce 8 asks and one gap: nothing in story bank v1 shows mentoring, which the leadership round assesses. Adding the apprenticeship story (v2) and a 15-minute prep call clears both. In the Loop A plan, every principle is covered, and the five rounds get five different primary stories.

---

## 10. Word-for-word scripts

#### Script 1 · Email: asking for a prep call

```text
Subject: Prep call before the [Company] loop?

Hi [Recruiter name],

Thanks for scheduling the loop. Could we do a 15-minute prep call this week? I'd like to
understand each round's focus, format and the competencies it assesses, so I can prepare
against exactly what the panel will be scoring. [Two time slots.]

Best,
[Your Name]
```

#### Script 2 · Verbal: the prep call, in four layers

```text
"Thanks for making time. Four areas, and I'll be quick.

First, the shape: how many rounds, which types, in what order, and is this the standard L6
shape here?

Second, each round: the focus of each design round, which competencies each behavioral round
assesses, and the format, meaning length, tool, and whether code is executed.

Third, level and people: is each round calibrated at L6, and are the interviewers from the
hiring team or across the company?

Fourth, where the level is decided: where do strong L6 candidates usually lose the level,
and who decides after the loop?"
```

#### Script 3 · Verbal: when the loop has a Senior shape

```text
"I noticed the loop has one design round and two coding rounds. In my experience an L6 loop
has two design rounds or a deep dive, because that's where Staff signal shows up. Before we
schedule, can we confirm the loop is calibrated at L6? If the plan is a Senior loop, I'd
rather we talk about that now than discover it in the committee."
```

#### Script 4 · Verbal: asking about Leadership Principles per round

```text
"In a principles-based loop, it helps me to know which principles each interviewer will
focus on, so I bring my strongest, most relevant story to each round rather than repeating
the same one. Is that something you can share? I'm not asking about questions, just the
principles."
```

#### Script 5 · Email: the follow-up with every open question

```text
Subject: Three quick questions before the loop

Hi [Recruiter name],

Thanks for the prep call; it helped a lot. Three things I didn't get to:
1. [The focus of R3: product-facing, infrastructure or data-intensive?]
2. [Is R5 calibrated at L6, and who runs it: a peer or a manager?]
3. [The format of R1: shared doc or IDE, and is code executed?]

No rush; anytime before [date] works.

Best,
[Your Name]
```

#### Script 6 · Verbal: asking where the level is decided

```text
"One question I find really useful: where do strong candidates at L6 usually lose the level
here? Is it the second design round, the leadership round, the depth of the project
discussion? I'd like to put my preparation where it matters most."
```

#### Script 7 · Verbal: declining leaked material

```text
"Thanks, but I'd rather not see that. I want my answers to be my own, and I'd be
uncomfortable if anything I said in the room came from a list of past questions. What
would really help is understanding the focus areas, and I'm working on those."
```

#### Script 8 · Email: after the loop, setting up the decision

```text
Subject: Thank you, and next steps

Hi [Recruiter name],

Thank you for organizing today's loop; I enjoyed the conversations, especially [one
specific thing].

Two questions when you have a moment: when does the committee meet, and when should I
expect to hear? And if the outcome is a different level than we targeted, will you be able
to tell me what drove it?

My timeline hasn't changed: I expect to make a decision around [date].

Best,
[Your Name]
```

#### Script 9 · Verbal: asking about the deep-dive format

```text
"For the past-project round, how is it run? Do I choose the project, or does the interviewer?
Is it whiteboard-based, and roughly how much time is spent on the overview versus drilling
into details? I want to pick a project that gives the interviewer the most to work with."
```

---

## 11. Probe chains

<details><summary><b>P1 · "I can't share details about the interview."</b></summary>

**Probe:** (A cautious recruiter) "Sorry, I can't tell you anything about the interviews."

**What they're testing:** usually nothing; it's caution, or a misunderstanding of what you're asking.

**Executor answer:** "Oh, okay, no problem, I'll just prepare generally."

**Staff/Principal answer:** "Understood, and I'm not asking about questions. Could you share just the shape: how many design rounds, and the competencies assessed? That's in most companies' prep materials. If there's a prep guide, that would cover it."

</details>

<details><summary><b>P2 · "Every round is general. Just be yourself."</b></summary>

**Probe:** "Don't overthink it. Just be yourself in every round."

**What they're testing:** nothing; it's a reassurance. But it leaves you blind.

**Executor answer:** "Okay, thanks, I'll do my best."

**Staff/Principal answer:** "Thanks, I will. To prepare well, could you tell me which round assesses leadership and cross-team influence? At L6 that's often where the level is decided, and I'd like to bring the right examples."

</details>

<details><summary><b>P3 · "Why do you want to know the interviewers' levels?"</b></summary>

**Probe:** "That's unusual. Why does it matter who's interviewing?"

**What they're testing:** whether you're gaming the process, or calibrating seriously.

**Executor answer:** "Just curious."

**Staff/Principal answer:** "It changes how I pitch my answers. With a Staff or Principal interviewer, I'll go deeper on trade-offs and org impact. With a mid-level interviewer, I'll make sure the reasoning is explicit. Either way I want the panel to see L6 signal, and knowing the audience helps."

</details>

<details><summary><b>P4 · "Someone sent me the questions they got last year. Want them?"</b></summary>

**Probe:** (A friend, not the recruiter) "I have the exact questions from my loop last year."

**What they're testing:** your integrity, even if nobody's watching.

**Executor answer:** "Sure, send them over."

**Staff/Principal answer:** "Thanks, but I'll pass. If I recognized a question, I'd either have to tell the interviewer or give an answer that isn't really mine. What would help is your view of the focus areas, and what the interviewers seemed to care about."

</details>

<details><summary><b>P5 · "There are two design rounds, but they're both product design."</b></summary>

**Probe:** (Loop G recruiter) "Both design rounds are product-facing designs."

**What they're testing:** nothing; it's information. The question is whether you notice that your strongest area isn't covered.

**Executor answer:** "Okay, I'll prepare product design then."

**Staff/Principal answer:** "Thanks. My strongest depth is platforms and data infrastructure. Is it possible for one of the rounds to be infrastructure-oriented, given the team? If not, I'll prepare both as product designs and bring platform depth where it fits."

</details>

<details><summary><b>P6 · "The bar raiser can ask about anything."</b></summary>

**Probe:** (Loop A recruiter) "The bar raiser isn't from this team, and they can probe any principle."

**What they're testing:** whether your stories hold at depth under an independent interviewer.

**Executor answer:** "Okay, I'll memorize answers for all the principles."

**Staff/Principal answer:** "Understood. My plan is to make sure every principle has at least two true stories I can go five levels deep on, rather than memorized answers. Is there a principle you'd suggest I over-prepare for an L7 loop?"

</details>

<details><summary><b>P7 · "We don't give feedback after loops."</b></summary>

**Probe:** "Our policy is not to share interview feedback."

**What they're testing:** nothing, but how you respond affects whether they'll share the one thing they can.

**Executor answer:** "That's frustrating, I really wanted to know."

**Staff/Principal answer:** "Understood. If the outcome differs from the level we targeted, could you at least tell me which area drove it, design, coding or leadership? It would help me decide whether to ask for anything further."

</details>

<details><summary><b>P8 · "Why do you care where people lose the level?"</b></summary>

**Probe:** "That's a strange question. Just do well everywhere."

**What they're testing:** whether you think about leveling as a system.

**Executor answer:** "Sorry, I just meant I want to do well."

**Staff/Principal answer:** "I will try to do well everywhere. But levels are usually decided in one or two rounds, often design and leadership, and preparation time is finite. Knowing where the line is drawn here helps me put my hours where they matter."

</details>

---

## 12. Checklist

- [ ] A 15-minute prep call booked (Script 1).
- [ ] The four layers asked (Script 2); answers written into a round table with "?" for unknowns (§5).
- [ ] The loop's shape checked against L6 (§3); raised before scheduling if it's a Senior shape (Script 3).
- [ ] A story bank with signals; `intel_ledger.py` run until clean.
- [ ] A different primary story per story-based round, plus backups.
- [ ] A follow-up email with every remaining question (Script 5).
- [ ] After the loop: the committee date and the level-explanation ask (Script 8).

---

## 13. References

- Amazon's Leadership Principles: [amazon.jobs](https://www.amazon.jobs/content/en/our-workplace/leadership-principles); the Bar Raiser program: [About Amazon](https://www.aboutamazon.com/news/workplace/amazon-bar-raiser).
- Structured interviewing: [Google re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices).
- Mapping stories to the 16 principles and to Google and Meta signals: [Behavioral playbook, Folder 02](../../Staff-Principal-Behavioral-L7-Playbook/02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md).
- Preparing the past-project deep dive: [Past-Project Deep-Dive playbook](../../Past-Project-Deep-Dive-L7-Defense-Playbook/README.md).
