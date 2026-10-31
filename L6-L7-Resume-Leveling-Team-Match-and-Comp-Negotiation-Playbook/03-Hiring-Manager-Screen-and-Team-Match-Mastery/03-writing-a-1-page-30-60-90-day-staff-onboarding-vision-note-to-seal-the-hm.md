# 03.3 · Writing a one-page 30-60-90-day Staff onboarding vision note to seal the hiring manager

> Folder 03 · Hiring-manager screen and team-match mastery · File 3 of 3 · [KB home](../README.md) · Previous: [03.2 Team-matching strategy](02-team-matching-strategy-evaluating-org-health-promo-velocity-and-scope.md) · Next folder: [04.1 Why committees down-level](../04-Preventing-and-Reversing-Hiring-Committee-Down-Levels/01-why-hiring-committees-down-level-and-how-packets-are-debated.md)

<!-- lint-pack: hm -->

| | |
|---|---|
| **Reader** | A candidate who has had a good hiring-manager or team-match conversation and wants to turn it into a decision |
| **Running exhibit** | Candidate V's note to the Loop N hiring manager, written after the call in 03.1 (§6) |
| **Listing** | `vision_note_check.py`: checks a 30-60-90 note for length, the five sections, premature fixes, vague milestones and overreach (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run: V's first draft raises 9 issues; the sent version is ready to send. The 8 pairs in §7 are checked with `script_lint.py` (hm pack). |
| **Marks** | ⚠ = field practice, not published policy. |

**Integrity rule.** The note repeats what the manager told you and proposes how you'd learn. It never invents knowledge of their systems, promises results you can't control, or uses anything confidential from your current employer.

---

## 0. The 60-second version

1. **A short note after a good conversation does three jobs:** it shows Staff behavior (writing, structure, learning before acting), it gives the manager words to argue for you, and it confirms the scope you'd own.
2. **One page, five sections:** What I heard; 30 days (learn); 60 days (propose); 90 days (first milestone); How we'll know.
3. **Start from their words.** The first section quotes the pains they described. If you got the diagnosis wrong, the note invites the correction early.
4. **The first 30 days are for learning.** Committing to a rewrite in month one is the fastest way to lose a manager's trust.
5. **Every 60- and 90-day item names a deliverable or a number.** "Improve reliability" is a wish; "an RFC with three options, reviewed with both teams" is a plan.
6. **Don't overreach:** no "owning the roadmap", no "taking over" anything.
7. **Run `vision_note_check.py`** before you send it.

---

## 1. Why a note works, and when it backfires

### 1.1 What it does for you

| Job | How |
|---|---|
| **It shows Staff behavior** | Staff engineers write things down, structure ambiguity and learn before acting. The note is a sample of that work |
| **It arms the manager** | Managers have to justify hires and levels to their own managers ⚠; a crisp note gives them the words |
| **It confirms scope** | Writing down what you'd own makes it concrete for both of you, and becomes a record for later (03.2 Script 6) |
| **It differentiates** | Few candidates send one ⚠, and fewer send a good one |

### 1.2 When it backfires

| Failure | Why it hurts |
|---|---|
| **A wrong diagnosis** stated as fact | Shows you didn't listen |
| **Prescriptions** in month one | Signals you'll change things before understanding them |
| **Length** (three pages, a slide deck) | Signals you can't prioritize; nobody reads it |
| **Overreach** ("I'll own the roadmap") | Threatens the manager and the team's leads |
| **Promises** ("I'll cut incidents by 80%") | Commits you to results you don't control yet |
| **Confidential detail** from your current employer | A judgment red flag, whatever its content |

---

## 2. When to send it ⚠

| Process | When | Who |
|---|---|---|
| HM-driven (N-style) | Within two days of the HM call, before or after the loop | The hiring manager |
| Committee, then team match (G-style) | After a team-match conversation, before you choose | The team's manager |
| Bar-raiser (A-style) | After the hiring-manager round, if you had a real conversation about the problem | The hiring manager, via the recruiter if that's the norm |
| Offer stage | When choosing between offers, to confirm scope | The manager of the team you're choosing |

Don't send it to committees or to people you haven't spoken with. It's a follow-up to a conversation, not a cover letter.

---

## 3. The five sections

| Section | Content | Length |
|---|---|---|
| **What I heard** | Two to four pains, quoted or closely paraphrased, with their numbers | 3–4 lines |
| **30 days: learn** | Whose systems you'd walk through, which incidents you'd read, who you'd meet; optionally one small fix to learn the path to production | 3–4 bullets |
| **60 days: propose** | One or two proposals as reviewable documents (an RFC, a plan), each with a measurable target | 2–3 bullets |
| **90 days: first milestone** | Something live or measured, small enough to be real | 2–3 bullets |
| **How we'll know** | The measures that would tell both of you it's working | 2–3 bullets |

Under 450 words in total. If it doesn't fit, you're explaining too much.

### 3.1 Writing rules

- **Their numbers, not yours.** "About 300 devices" because they said it.
- **Hypotheses are labeled:** "My working hypothesis is… I'd want to test it against…"
- **Name roles, not people,** unless they named them first.
- **Respect the team's past work.** "Building on what's there" beats "fixing what's broken".
- **Targets are set with the team.** "A target we'd agree on" is better than a number you invent.

---

## 4. The L7 variant

For a Principal role, the note changes in three ways:

1. **"What I heard" spans orgs:** the cross-team decision that's stuck, not just the team's pain.
2. **30 days includes the other orgs' leads** and the decision history: why the problem hasn't been solved.
3. **90 days ends with a strategy draft,** a document the orgs can disagree with, rather than a single system milestone.

Keep the same rule: learning first, no overreach. Principal engineers who announce strategies in week two rarely get a second chance.

---

## 5. Notes when you know too little

If the conversation didn't surface enough to write a credible 30-60-90, **don't fake one.** Send three questions instead (Script 8). A good question note is better than an invented plan, and it often earns a second conversation.

---

## 6. Candidate V's note to Loop N

### 6.1 The first draft

V wrote this an hour after the call, while enthusiastic:

<!-- note:start name=raw-v-first-draft -->
**What I heard**
- Rollouts are unsafe and telemetry is unreliable.

**30 days**
- Rewrite the OTA pipeline with staged rings and automatic rollback.
- Replace the telemetry agent's buffer with a counted ring.

**60 days**
- Improve reliability across the device fleet.
- Make telemetry trustworthy.

**90 days**
- Own the roadmap for edge platform and set the team's priorities.
- Drive excellence in design reviews.
<!-- note:end -->

It has the right instincts and almost every failure in §1.2: one vague line of diagnosis, rewrites in month one, wishes instead of deliverables, no measures, and claims on the manager's job. The checker finds 9 issues (§9.3).

### 6.2 The note V sent

<!-- note:start name=v-sent-note -->
Subject: How I'd approach the first 90 days on [team]

Thank you again for the conversation. Here's how I'd approach the first 90 days, based on what you told me. I'd expect parts of it to be wrong, and I'd like to hear where.

**What I heard**
- "One bad OTA build bricked about 300 devices last quarter," and recovery needed hands on some devices.
- "Device telemetry drops data silently; we found a 4% gap only when a customer complained."
- "Strong individuals, but nobody writes designs the other teams follow."

**30 days: learn**
- Walk through the last three bad rollouts end to end with the engineers who handled them.
- Map the telemetry path from the device buffer to storage, and every place it can drop data.
- Meet the device, cloud and support leads, and read the last year of incident reviews.
- Ship one small fix to learn the path to production.

**60 days: propose**
- A rollout-safety RFC with 2-3 options, reviewed with the device and cloud teams, aiming for a bad build to reach under 1% of devices.
- A telemetry loss budget: every drop counted on the device, and a dashboard that shows the gap daily.

**90 days: first milestone**
- The first staged ring live for 1 device class, with an automatic halt on health signals.
- The telemetry gap tracked daily on the dashboard, with a target agreed as a team by day 90.
- A weekly design review running, with 2 engineers presenting their own designs.

**How we'll know**
- Bad builds stop in the first ring; no fleet-wide incident from a single build.
- The telemetry gap is visible every day, and shrinking.
- Designs from this team are adopted by the device and cloud teams.

My working hypothesis on telemetry is a bounded buffer that drops without counting when the uplink is slow; I'd want to test that before proposing anything.
<!-- note:end -->

About 320 words. The manager forwarded it to the director with one line: "This is the person." (In V's composite story. Results vary; the note raises your odds, it doesn't decide them.)

---

## 7. Before → After: note lines

#### S51 · The opening line

| Version | Answer |
|---|---|
| **Weak** | Sorry for the long email, I just wanted to share some kind of thoughts. |
| **Strong** | Here's how I'd approach the first 90 days, based on what you told me. I'd expect parts of it to be wrong, and I'd like to hear where. |

#### S52 · The first 30 days

| Version | Answer |
|---|---|
| **Weak** | The first thing I'd do is rewrite the OTA pipeline with staged rings. |
| **Strong** | Walk through the last three bad rollouts end to end with the engineers who handled them, before proposing anything. |

#### S53 · A 60-day item

| Version | Answer |
|---|---|
| **Weak** | Improve reliability across the fleet, hopefully a lot. |
| **Strong** | A rollout-safety RFC with two or three options, reviewed with the device and cloud teams, aiming for a bad build to reach under 1% of devices. |

#### S54 · Scope

| Version | Answer |
|---|---|
| **Weak** | I'd take over the edge roadmap and set the team's priorities, whatever you need. |
| **Strong** | I'd own the rollout-safety design across the device and cloud teams, and bring priorities and trade-offs to you as options. |

#### S55 · A hypothesis

| Version | Answer |
|---|---|
| **Weak** | Your telemetry agent is clearly badly designed and I'd replace it right away. |
| **Strong** | My working hypothesis is a bounded buffer that drops without counting when the uplink is slow. I'd want to test that before proposing anything. |

#### S56 · Targets

| Version | Answer |
|---|---|
| **Weak** | I guarantee I can cut incidents by 80% in my first quarter. |
| **Strong** | The telemetry gap measured daily, with a target we agree on as a team once we see the baseline. |

#### S57 · Mentioning the team

| Version | Answer |
|---|---|
| **Weak** | Honestly the team seems to need someone to tell them how to design things. |
| **Strong** | A weekly design review, with two engineers presenting their own designs by day 90. |

#### S58 · Closing the note

| Version | Answer |
|---|---|
| **Weak** | I hope this is okay, I'm not sure if it makes sense, it's my dream job. |
| **Strong** | I'd be glad to walk through this or change it after a second conversation. What did I get wrong? |

---

## 8. Using the note after you're hired

The note isn't only a sales document. If you join:

- **Day 1:** reread it with the manager and correct it. It becomes your first-quarter plan.
- **Day 30:** compare what you learned with the hypotheses.
- **Day 90:** the "How we'll know" section is the start of your first review, and of the case for the next level.

---

## 9. The listing: `vision_note_check.py`

### 9.1 What it does

| Check | Fails when |
|---|---|
| `LENGTH` | Over 450 words |
| `MISSING` | One of the five sections is absent |
| `ECHO` | "What I heard" has fewer than two points |
| `PREMATURE` | The 30-day section commits to rewriting, replacing or migrating (a small fix to learn the path to production is fine) |
| `NO-LEARNING` | The 30-day section has no learning verb |
| `VAGUE` | A 60- or 90-day bullet has no number, date or named deliverable |
| `OVERREACH` | Claims on the manager's role or the team ("own the roadmap", "take over") |

To use it: put your draft between `<!-- note:start name=my-note -->` and `<!-- note:end -->` in `note.md`, with the five section labels at the start of their lines, and run `python -I vision_note_check.py note.md`.

### 9.2 Listing

<!-- include:vision_note_check.py -->
```python
#!/usr/bin/env python3
"""vision_note_check.py: check a one-page 30-60-90 onboarding note before you send it to a hiring manager.

Reads every note between markers in a Markdown file:

  <!-- note:start name=my-note -->
  ...the note, with lines starting 'What I heard', '30 days', '60 days', '90 days' and 'How we'll know'...
  <!-- note:end -->

Checks:
  LENGTH       over 450 words (it stops being one page)
  MISSING      one of the five sections is absent
  ECHO         'What I heard' has fewer than 2 bullet points (the note must start from their words)
  PREMATURE    the 30-day section commits to rewriting, replacing or migrating before learning
               (shipping a small fix to learn the path to production is fine)
  NO-LEARNING  the 30-day section has no learning verb (listen, learn, map, shadow, read, meet, review)
  VAGUE        a 60- or 90-day bullet without a number, a date or a named deliverable
  OVERREACH    claims on the manager's role or the team ('own the roadmap', 'take over', 'run the team')
Usage: python -I vision_note_check.py FILE.md [--kb]
  --kb  notes named 'raw-*' must raise flags; every other note must be clean.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*note:start\s+(.*?)-->")
END = re.compile(r"<!--\s*note:end\s*-->")
SECTIONS = ["What I heard", "30 days", "60 days", "90 days", "How we'll know"]
LEARN = re.compile(r"\b(?:listen|learn|map|shadow|read|meet|review|interview|walk through|sit with)\w*\b", re.I)
BUILD = re.compile(r"\b(?:rewrite|re-architect|rearchitect|replace|migrate|rebuild|overhaul)\w*\b", re.I)
DELIVERABLE = re.compile(r"\d|\b(?:RFC|design doc|proposal|runbook|dashboard|SLO|plan|review|pilot|prototype)\b", re.I)
OVERREACH = re.compile(r"\b(?:own the roadmap|take over|run the team|set the team's priorities)\b", re.I)


def read(path):
    notes, cur, fenced = [], None, False
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if fenced:
            continue
        m = START.search(line)
        if m:
            cur = {"attrs": dict(re.findall(r"(\w+)=(\S+)", m.group(1))), "lines": []}
            continue
        if cur is not None and END.search(line):
            notes.append(cur)
            cur = None
            continue
        if cur is not None:
            cur["lines"].append(line.rstrip("\n"))
    return notes


def split(lines):
    parts, key = {}, None
    for ln in lines:
        bare = ln.strip().lstrip("#*> ").strip()
        hit = next((s for s in SECTIONS if bare.lower().startswith(s.lower())), None)
        if hit:
            key = hit
            parts[key] = []
            continue
        if key:
            parts[key].append(ln)
    return parts


def check(note):
    name = note["attrs"].get("name", "?")
    text = "\n".join(note["lines"])
    words = len(re.findall(r"\S+", text))
    parts = split(note["lines"])
    flags = []
    if words > 450:
        flags.append(f"LENGTH {words} words (> 450)")
    for s in SECTIONS:
        if s not in parts:
            flags.append(f"MISSING section '{s}'")
    bullets = lambda key: [ln.strip()[2:] for ln in parts.get(key, []) if ln.strip().startswith(("- ", "* "))]
    if "What I heard" in parts and len(bullets("What I heard")) < 2:
        flags.append("ECHO 'What I heard' needs at least 2 points in the manager's words")
    day30 = "\n".join(parts.get("30 days", []))
    if "30 days" in parts:
        if BUILD.search(day30):
            flags.append(f"PREMATURE 30 days commits to '{BUILD.search(day30).group(0)}' before learning")
        if not LEARN.search(day30):
            flags.append("NO-LEARNING 30 days has no learning verb")
    for key in ("60 days", "90 days"):
        for b in bullets(key):
            if not DELIVERABLE.search(b):
                flags.append(f"VAGUE {key}: '{b[:50]}'")
    m = OVERREACH.search(text)
    if m:
        flags.append(f"OVERREACH '{m.group(0)}'")
    print(f"note {name}: {words} words, sections {sum(s in parts for s in SECTIONS)}/5")
    for f in flags:
        print(f"  {f}")
    print(f"  result: {'ready to send' if not flags else str(len(flags)) + ' issue(s)'}")
    return name, flags


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    bad = []
    for note in read(argv[1]):
        name, flags = check(note)
        if kb and name.startswith("raw-") != bool(flags):
            bad.append(name)
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's two drafts

<!-- run:vision_note_check.py SELF --kb -->
```text
note raw-v-first-draft: 67 words, sections 4/5
  MISSING section 'How we'll know'
  ECHO 'What I heard' needs at least 2 points in the manager's words
  PREMATURE 30 days commits to 'Rewrite' before learning
  NO-LEARNING 30 days has no learning verb
  VAGUE 60 days: 'Improve reliability across the device fleet.'
  VAGUE 60 days: 'Make telemetry trustworthy.'
  VAGUE 90 days: 'Own the roadmap for edge platform and set the team'
  VAGUE 90 days: 'Drive excellence in design reviews.'
  OVERREACH 'Own the roadmap'
  result: 9 issue(s)

note v-sent-note: 324 words, sections 5/5
  result: ready to send

VERDICT: OK
```

---

## 10. Word-for-word scripts

#### Script 1 · Email: sending the note

```text
Subject: How I'd approach the first 90 days on [team]

Hi [Manager name],

Thank you again for [day]'s conversation. I found it easier to think about the role by
writing down how I'd approach the first 90 days, based on what you told me. It's below,
and it's short.

I'd expect parts of it to be wrong; that's the point of sending it now. I'd be glad to hear
where.

[the note]

Best,
[Your Name]
```

#### Script 2 · Verbal: walking the manager through the note on a follow-up call

```text
"I'll take two minutes, and then I'd rather hear your corrections. The first section is what
I heard; tell me if I've got the pains wrong. The first 30 days are deliberately all
learning, plus one small fix to learn how code gets to devices. At 60 days I'd bring
proposals as documents for the device and cloud teams to review, not decisions. And the
last section is how we'd both know it's working. What would you change?"
```

#### Script 3 · Verbal: the manager corrects your diagnosis

```text
"That's really useful, thank you. So the bigger problem is the rollout trigger, not the
staging: builds go out automatically when CI passes, with no human gate. That changes my
first month: I'd start with how releases are triggered and who can stop one. I'll update
the note and send it back."
```

#### Script 4 · Email: the note after a team-match conversation (G-style)

```text
Subject: Before I choose a team

Hi [Manager name],

Thank you for the time today. I'm close to choosing a team, and it helped me to write down
how I'd approach the first 90 days on [team], based on what you told me. It's short, below.

If it matches how you see the role, that will make my decision easy. If it doesn't, I'd
really like to know before I choose.

[the note]

Best,
[Your Name]
```

#### Script 5 · Email: the L7 variant to a director

```text
Subject: How I'd approach the first 90 days as Principal

Hi [Director name],

Thank you for the conversation. Here's how I'd approach the first 90 days, based on what you
described: the cross-org decision on [topic] that's been stuck for two quarters.

What I heard: [2–3 points across the orgs].
30 days: meet the leads of [org A, B, C]; read the decision history; understand why previous
attempts stalled.
60 days: a problem statement and options document the three orgs can disagree with.
90 days: a strategy draft with an owner per workstream, reviewed by the three org leads.
How we'll know: the decision is made and holds for two quarters; each org's plan reflects it.

I'd expect parts of this to be wrong, and I'd welcome your corrections.

Best,
[Your Name]
```

#### Script 6 · Verbal: asking for honest feedback on the note

```text
"Before we finish: was the note useful, or too much? I ask because I'd write the same kind
of document in my first month, and I'd like to calibrate to how you and your team like to
work."
```

#### Script 7 · Email: confirming scope at the offer stage using the note

```text
Subject: Confirming the first-quarter plan

Hi [Manager name],

As I finalize my decision, I'd like to confirm that the plan we discussed still holds,
especially the scope: owning the rollout-safety design across the device and cloud teams,
and the telemetry loss budget. If anything's changed since we spoke, I'd rather know now.

Best,
[Your Name]
```

#### Script 8 · Email: when you know too little for a note

```text
Subject: Three questions before I'd write a plan

Hi [Manager name],

Thank you for the conversation. I'd like to send you a first-90-days note, but I don't think I
know enough yet to write a credible one. Three questions would get me there:
1. [What made you open the role now?]
2. [What's the most expensive problem on your plate?]
3. [What would make you say this hire was a success in a year?]

Happy to do this over a 15-minute call if that's easier.

Best,
[Your Name]
```

---

## 11. Probe chains

<details><summary><b>P1 · "You don't know our systems yet. Isn't this presumptuous?"</b></summary>

**Probe:** "This is a nice note, but you haven't seen our code."

**What they're testing:** whether you know the note's limits.

**Executor answer:** "I'm pretty confident about most of it, I've seen these problems before."

**Staff/Principal answer:** "Completely fair, and that's why the first 30 days are all learning. The note is how I'd approach it, not what I'd conclude. The part I'm most likely wrong about is the telemetry hypothesis, and I'd test it before proposing anything."

</details>

<details><summary><b>P2 · "Why staged rings? Our problem is different."</b></summary>

**Probe:** "We've considered staged rollouts. Devices aren't servers; half are offline at any time."

**What they're testing:** whether you'll defend your idea or learn from theirs.

**Executor answer:** "Staged rollouts work everywhere, it's best practice."

**Staff/Principal answer:** "That's exactly the constraint I didn't know. If half the fleet is offline, rings need to be defined by who has checked in, and the halt signal has to work on partial data. That makes the health signal the hard part. What do devices report after an update today?"

</details>

<details><summary><b>P3 · "Can you commit to the 1% target?"</b></summary>

**Probe:** "You wrote under 1% of devices. Can you commit to that?"

**What they're testing:** whether you'll promise what you don't control.

**Executor answer:** "Yes, absolutely."

**Staff/Principal answer:** "I'd commit to the design aiming for it, and to measuring it honestly. Whether 1% is the right target depends on things I haven't seen yet, like how quickly a device reports a failed update. I'd rather set the number with the team in month two than promise it now."

</details>

<details><summary><b>P4 · "My team leads might find this threatening."</b></summary>

**Probe:** "I like it, but my two senior engineers might feel you're taking over their areas."

**What they're testing:** whether you'll make it about yourself or about the team.

**Executor answer:** "They'll get used to it once they see results."

**Staff/Principal answer:** "That matters to me. I'd want to meet them in the first two weeks and ask what they'd want from a Staff engineer. The design review at 90 days is meant to give their designs more reach, not mine. If you think the note should say that more clearly, I'll change it."

</details>

<details><summary><b>P5 · "Why should I believe you'll follow this plan?"</b></summary>

**Probe:** "Lots of people write plans. Have you done this before?"

**What they're testing:** evidence of the learning-first behavior.

**Executor answer:** "I'm very disciplined."

**Staff/Principal answer:** "At my current company, my first month on the config platform was reading every config incident of the previous year. That's where the three incidents that shaped the RFC came from. I proposed nothing until week six. The note is the same approach."

</details>

<details><summary><b>P6 · "This is great. Can you start with the rewrite anyway?"</b></summary>

**Probe:** "Honestly, I'd love it if you just rewrote the OTA pipeline in the first month."

**What they're testing:** sometimes nothing; sometimes whether you'll drop your principles to please them.

**Executor answer:** "Sure, I can do that."

**Staff/Principal answer:** "I can move faster than the note suggests, and if something is on fire I'll help put it out on day one. But I'd still want two weeks with the last three incidents before changing the design, because a rewrite built on the wrong diagnosis would cost you more than the two weeks."

</details>

<details><summary><b>P7 · "Did you write this with AI?"</b></summary>

**Probe:** "This is very polished. Did you use AI to write it?"

**What they're testing:** authenticity, and whether the thinking is yours.

**Executor answer:** "No, of course not." (If that isn't true.)

**Staff/Principal answer:** Answer truthfully. If you used a tool for editing: "I used a tool to tighten the wording, but the structure and the content come from our conversation and my own experience. I'm glad to go through any line of it with you." Then be ready to defend every line.

</details>

<details><summary><b>P8 · (L7) "This reads like a Staff plan, not a Principal plan."</b></summary>

**Probe:** (Director) "This is team-level. Where's the cross-org thinking?"

**What they're testing:** whether you understand the L7 difference.

**Executor answer:** "I can add more cross-org items."

**Staff/Principal answer:** "You're right; I wrote it at the level of the conversation I had with the hiring manager. For the Principal version, the 60-day output would be a problem statement the three orgs agree on, and the 90-day output a strategy draft each org's plan reflects. I'll rewrite it that way. Which cross-org decision would you most want unblocked?"

</details>

---

## 12. Checklist

- [ ] Written within two days of the conversation, from your call notes (03.1).
- [ ] Five sections, under 450 words; `vision_note_check.py` says "ready to send".
- [ ] "What I heard" in their words, with their numbers.
- [ ] 30 days are learning (plus, at most, a small fix to learn the path to production).
- [ ] Every 60- and 90-day item names a deliverable or a number.
- [ ] Hypotheses labeled; targets to be set with the team; no overreach.
- [ ] Sent with an invitation to correct it (Script 1).
- [ ] If you know too little, three questions instead (Script 8).

---

## 13. References

- Writing as a Staff behavior, and design documents as the unit of influence: [StaffEng guides](https://staffeng.com/guides/staff-archetypes/).
- Diagnosing before prescribing: [03.1 §6 of this KB](01-the-hiring-manager-sell-call-diagnosing-their-pain-in-the-first-10-minutes.md#6-dont-prescribe).
- Influence without authority across teams, which the 90-day design review depends on: [Behavioral playbook 03.3](../../Staff-Principal-Behavioral-L7-Playbook/03-Influence-Without-Authority-and-Cross-Org-Alignment/03-driving-multi-team-migrations-and-adoption-without-mandates.md).
