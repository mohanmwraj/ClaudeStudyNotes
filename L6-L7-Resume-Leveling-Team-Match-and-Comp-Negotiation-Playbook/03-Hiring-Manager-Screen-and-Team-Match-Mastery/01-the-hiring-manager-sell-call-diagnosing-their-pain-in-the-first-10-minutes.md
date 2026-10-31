# 03.1 · The hiring-manager sell call: diagnosing their pain in the first 10 minutes

> Folder 03 · Hiring-manager screen and team-match mastery · File 1 of 3 · [KB home](../README.md) · Next: [03.2 Team-matching strategy](02-team-matching-strategy-evaluating-org-health-promo-velocity-and-scope.md)

<!-- lint-pack: hm -->

| | |
|---|---|
| **Reader** | A Staff or Principal candidate about to speak with a hiring manager, director or team-match manager |
| **Running exhibit** | Candidate V's call with the hiring manager of Loop N, an edge and AI-infrastructure team (§8) |
| **Listing** | `pain_match.py`: ranks the manager's pains, matches each to your evidence, and flags what you haven't diagnosed or can't honestly match (§10) |
| **Verification** | The listing is byte-identical to the file that was run. §10.3 is a real run: the pains V guessed from the job description raise 3 issues (two undiagnosed, one unmatched); the pains diagnosed on the call match cleanly, with one honest "no evidence yet". The 8 pairs in §9 are checked with `script_lint.py` (hm pack). |
| **Marks** | ⚠ = field practice, not published policy. |

**Integrity rule.** Matching a pain means showing evidence you really have. When you don't have it, say so and name the nearest true evidence. A hiring manager who later discovers a faked match doesn't just lower your level; they stop trusting everything you said.

---

## 0. The 60-second version

1. **The manager is deciding four things:** can you solve *my* problem, will you raise my team, will you be easy to work with, and will you stay. Your pitch only works if it answers the first one in their terms.
2. **Diagnose before you pitch.** Spend the first 10 minutes asking, not telling. Five questions surface the real pain (§2).
3. **Mirror the pain back with numbers,** then match it with **one** proof. Then ask a deeper question. Repeat for the top two or three pains.
4. **Don't prescribe.** "The first thing I'd do is rewrite X" is the classic outsider mistake. Offer how you'd *find out*, and a hypothesis framed as a question.
5. **When you can't match a pain, say so,** and offer adjacent evidence. Honest gaps cost little; faked matches cost everything.
6. **Sell the role to yourself too.** Half your questions should test whether this team is worth joining (03.2).
7. **Run `pain_match.py`** on your notes after the call: it gives you the pitch order for the next conversation and the questions still open.

---

## 1. What the manager is really deciding

| Risk in the manager's head | What they listen for | What reassures them |
|---|---|---|
| **"Can they solve my problem?"** | Whether you understand *their* problem, in their terms | Your restatement of their pain, then one matched proof with a number |
| **"Will they raise my team?"** | Whether others got better around you | A story where other engineers' work changed because of you |
| **"Will they be easy to work with?"** | How you talk about past managers, conflicts and constraints | Generous descriptions of other people; clear handling of disagreement |
| **"Will they stay?"** | Why you're moving; how long you've stayed before | A problem-based reason for the move; at least one long arc |

For L7 roles there's a fifth risk: **"Will they compete with me, or with my managers?"** Principal engineers who want the manager's job, or who treat managers as obstacles, are a known failure. Show that you know where a Principal's authority ends.

---

## 2. The first 10 minutes: the diagnostic protocol

### 2.1 The five questions

Ask about the past and the present, not hypotheticals. People describe real problems accurately and imagined ones optimistically.

| # | Question | What it surfaces |
|---|---|---|
| 1 | "What made you open this role now?" | The trigger: an incident, a launch, a departure, a reorg |
| 2 | "If this hire goes well, what's different in 12 months?" | Their success criteria, in their words |
| 3 | "What's the most expensive problem on your plate right now?" | The real pain, often different from the job description |
| 4 | "What have you tried so far, and what got in the way?" | Constraints, politics and what *not* to propose |
| 5 | "Who else does this role need to work with to succeed?" | The org around the role, and the influence it will need |

### 2.2 Mirror, match, deepen

After each answer:

1. **Mirror** the pain back, with their numbers if they gave any: "So a bad build reached about 300 devices before anyone could stop it, and recovery meant truck rolls."
2. **Match** with one proof, briefly: "On our config platform, bad changes stop themselves in the first ring; the worst one reached 1.1% of instances for four minutes."
3. **Deepen** with a question that shows you understand the mechanism: "Do your devices have an A/B partition to roll back to, or does recovery need physical access?"

Three cycles of this beat ten minutes of résumé. The manager hears you think about *their* system.

### 2.3 What "diagnosed" means

A pain is diagnosed when you know four things: **what happens**, **how often**, **what it costs** (money, people, customers, risk) and **why it hasn't been fixed**. If you don't know all four, keep asking. The tool in §10 flags any pain without a category and a severity.

---

## 3. A pain taxonomy for platform, data and AI teams

| Category | How it sounds | How to quantify it |
|---|---|---|
| **Safe change** | "Deploys keep breaking things", "a bad rollout bricked devices" | Incidents per quarter caused by change; blast radius; recovery time |
| **Data loss or correctness** | "We found a gap only when a customer complained" | Fraction of data lost or wrong; time to detection |
| **Performance or cost** | "Inference is too expensive", "p99 is killing us" | Unit cost; latency at the percentile that matters; headroom |
| **Technical leadership** | "Nobody writes designs others follow" | Cross-team designs per quarter; decisions re-litigated |
| **Operational load** | "On-call is burning people out" | Pages per week; repeat-cause incidents |
| **Scale** | "We'll be at 10× next year" | Growth rate; date the current design breaks |
| **Org friction** | "The platform team and the product teams don't agree" | Blocked projects; escalations |

---

## 4. Matching honestly

### 4.1 The evidence bank

Before the call, write your evidence in the same categories: each piece of evidence, the categories it covers, and its proof with a number. V's bank is in §8.1.

### 4.2 When you don't have the match

Sometimes the manager's pain is something you haven't done. V has never written GPU kernels. The honest move has three parts:

1. **Say so plainly:** "I haven't written CUDA kernels."
2. **Name the nearest true evidence:** "My depth is the serving path around them: memory, batching, latency budgets. I took a feature cache's p99 from 41 to 22 milliseconds with zero allocations on the read path."
3. **Ask how the team covers it:** "Is kernel work something this role would own, or is there a specialist on the team?"

Often the answer is "We have people for that." Sometimes it isn't, and then you've learned the role isn't yours, which is worth knowing before a loop.

---

## 5. The 45-minute call plan

| Minutes | You | Goal |
|---|---|---|
| 0–2 | A 30-second introduction, scope-first, then a question | Hand them the floor quickly |
| 2–12 | The five diagnostic questions; mirror and deepen | Find the top two or three pains |
| 12–25 | Mirror–match–deepen on the top pains | One proof per pain, with numbers |
| 25–35 | Your questions about the team (03.2) | Decide whether you want the job |
| 35–42 | The manager's questions | Answer with stories, not adjectives |
| 42–45 | Close: next steps and a recap of what you heard | Set up the follow-up note (03.3) |

---

## 6. Don't prescribe

The most common way strong candidates lose a hiring manager is by **solving the problem on the call**. It feels like showing value. To the manager it signals three bad things: you'll change things before understanding them, you'll ignore the people who've been working on it, and you think it's easy.

| Instead of | Say |
|---|---|
| "I'd rewrite the OTA pipeline first." | "Before proposing anything, I'd want to see the last three bad rollouts end to end. My hypothesis would be [X], but I'd want to test it." |
| "You should move to Kafka." | "How does telemetry get from device to storage today, and where can it be dropped?" |
| "I'd replace your on-call setup." | "What fraction of pages are repeat causes? That usually tells you where to start." |

A **hypothesis framed as a question** shows expertise without overreach.

---

## 7. Manager types ⚠

| Type | Tell-tale | What they need from you | Adjust |
|---|---|---|---|
| **Builder** | Talks about the roadmap and what's next | A partner who can design the next thing | Lead with design and direction stories |
| **Firefighter** | Talks about incidents and pressure | Someone who stabilizes and frees their time | Lead with reliability and operational stories; promise diagnosis, not heroics |
| **New-org manager** | "We just formed this team" | Structure, standards, first designs | Lead with "established" and "first" stories |
| **Director or skip-level (L7)** | Talks about strategy, other orgs, headcount | A Principal who sets direction across teams without needing them to | Lead with cross-org stories; show where your authority ends |
| **Remote manager** (common in Indian GCCs reporting to the US) | Time zones, context gaps | Someone who closes the context gap | Show how you've led across time zones |

---

## 8. Candidate V's call with Loop N

### 8.1 V's evidence bank

<!-- evidence:start name=v-evidence -->
| Evidence | Categories | Proof |
|---|---|---|
| Beacon rings and auto-halt | safe change; platform; direction | 3 bad changes auto-halted at <= 1.1% of instances; config Sev-1s 2 -> 0 in 12 months |
| Beacon fail-static last-known-good | safe change; resilience | after 0.3% of instances served defaults for 6 min: fsync-and-rename, 2 generations, fail-readiness |
| Tidewater reconciliation and DLQ | data loss; data pipelines; correctness | per-partition control totals caught a dropped event before 9 regulatory reports shipped |
| Flightline ring overflow policy | data loss; embedded; real-time | HIL rig found 44 drops at 256 slots; 512 slots, every drop counted and reported |
| Quickset cache | performance; cost; latency | ranking p99 41 -> 22 ms; 0 allocations on the read path |
| Flightline DMA filtering | performance; cost; embedded | interrupt CPU ~20% -> <2% with no board respin |
| Lodestar gating | cost; ai systems | LLM runs on ~18% of tickets; $0.0021 per ticket |
| Beacon RFC | technical leadership; direction; influence | config-safety policy for ~2,000 engineers |
| Design apprenticeship | technical leadership; mentoring | 2 engineers went on to lead cross-team designs |
| Beacon on-call | operational load | config pages ~11 -> ~2 per month |
<!-- evidence:end -->

### 8.2 Before the call: pains guessed from the job description

<!-- pains:start name=raw-n-from-jd evidence=v-evidence -->
| Pain (their words) | Category | Severity |
|---|---|---|
| "Drive technical excellence" | ? | ? |
| "Scale our edge platform" | platform | ? |
| "Mentor engineers" | mentoring | 2 |
| "Experience with CUDA kernels" | gpu kernels | 2 |
<!-- pains:end -->

### 8.3 After the first 10 minutes

The manager's answers to the five questions, in their words. The trigger was a bad OTA build last quarter; the CUDA line in the job description turned out to be a nice-to-have, because another engineer owns kernels.

<!-- pains:start name=n-diagnosed evidence=v-evidence -->
| Pain (their words) | Category | Severity |
|---|---|---|
| "One bad OTA build bricked about 300 devices last quarter" | safe change | 3 |
| "Device telemetry drops data silently; we found a 4% gap only when a customer complained" | data loss | 3 |
| "We want to run two models on the edge box where we run one today" | performance; cost | 2 |
| "Strong individuals, but nobody writes designs the other teams follow" | technical leadership | 2 |
| "On-call is about 25 pages a week" | operational load | 1 |
| "Kernel tuning help would be nice" | gpu kernels | 1 |
<!-- pains:end -->

The run (§10.3) turns this into V's pitch order for the next conversation: safe change and data loss first, each with a numbered proof; the edge-inference cost next; and the kernel item marked "no evidence yet", which V acknowledged on the call.

---

## 9. Before → After: hiring-manager answers

#### S31 · The opening

| Version | Answer |
|---|---|
| **Weak** | I've always wanted to work at a great company like this one, so I'm really excited. |
| **Strong** | Thanks for making time. Quick context: I lead config and rollout safety for 1,200 services. Before I go further, what made you open this role now? |

#### S32 · The manager describes a bad rollout

| Version | Answer |
|---|---|
| **Weak** | The first thing I'd do is rewrite your OTA pipeline with staged rollouts. |
| **Strong** | So one bad build reached about 300 devices before anyone could stop it. On our platform, bad changes stop themselves in the first ring. Do your devices have an A/B partition to roll back to? |

#### S33 · "Have you done kernel work?"

| Version | Answer |
|---|---|
| **Weak** | Kind of, I've sort of looked at CUDA a bit, I'm sure I could pick it up. |
| **Strong** | No, I haven't written kernels. My depth is the serving path around them: memory, batching, latency budgets. Is kernel work part of this role, or does someone on the team own it? |

#### S34 · "Why are you leaving?"

| Version | Answer |
|---|---|
| **Weak** | My current org is clueless about platform work and the politics are exhausting. |
| **Strong** | The config platform is stable and handed to a strong team. I want the next multi-year problem, and rollout safety for devices is the hardest version of the problem I know. |

#### S35 · "What would you do in your first 90 days?"

| Version | Answer |
|---|---|
| **Weak** | I'd replace the telemetry pipeline right away and rebuild the rollout system. |
| **Strong** | First, learn: walk through the last three bad rollouts and the telemetry path end to end. Then propose one change with a measurable target, probably on rollout safety, and review it with the team before building. |

#### S36 · "How do you work with managers?"

| Version | Answer |
|---|---|
| **Weak** | Honestly I prefer when managers stay out of technical decisions. |
| **Strong** | I own the technical direction and the trade-offs; my manager owns priorities, people and the org's commitments. When they conflict, I bring the options and the costs, and we decide together. |

#### S37 · The manager asks about team leadership

| Version | Answer |
|---|---|
| **Weak** | I'm just a senior IC, I don't really manage people. |
| **Strong** | I don't manage people, but I raise the team's design bar. Two engineers I paired with on RFCs now lead cross-team designs on their own. |

#### S38 · Closing the call

| Version | Answer |
|---|---|
| **Weak** | I hope that went okay, sorry if I talked too much. |
| **Strong** | Here's what I heard: rollout safety and silent telemetry loss are the two expensive problems, and design leadership is the gap. I'll send a short note on how I'd approach the first 90 days. |

---

## 10. The listing: `pain_match.py`

### 10.1 What it does

It reads your evidence bank and one or more pain tables. For each table, it prints the **pitch order** (highest severity first, each with your best evidence) and flags:

| Flag | Meaning |
|---|---|
| `UNDIAGNOSED` | A pain without a category or severity: ask more |
| `UNMATCHED` | A severity-2 or -3 pain with no evidence in that category: name adjacent evidence honestly, or learn more |
| `THIN` | A severity-3 pain whose best evidence has no number |

To use it: copy the two table formats from §8 into `call.md`, fill them in after the call, and run `python -I pain_match.py call.md`.

### 10.2 Listing

<!-- include:pain_match.py -->
```python
#!/usr/bin/env python3
"""pain_match.py: match a hiring manager's pains to your evidence, and find what you still need to learn.

Reads two kinds of block from a Markdown file:

  <!-- evidence:start name=my-evidence -->
  | Evidence | Categories | Proof |
  |---|---|---|
  | Config rings + auto-halt | safe change; platform | 3 bad changes halted at <= 1.1% of instances |
  <!-- evidence:end -->

  <!-- pains:start name=hm-call evidence=my-evidence -->
  | Pain (their words) | Category | Severity |
  |---|---|---|
  | "Rollouts keep bricking a few hundred devices" | safe change | 3 |
  <!-- pains:end -->

Severity is 1-3 (3 = the reason the req exists). Category '?' or severity '?' means you haven't diagnosed it.
Flags: UNDIAGNOSED (a '?'), UNMATCHED (severity >= 2 and no evidence in that category),
THIN (the best evidence for a severity-3 pain has no number in its proof).
Prints the pitch order: severity-3 pains first, each with its best evidence.
Usage: python -I pain_match.py FILE.md [--kb]
  --kb  pains blocks named 'raw-*' must raise flags; every other pains block must be clean.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*(evidence|pains):start\s+(.*?)-->")
END = re.compile(r"<!--\s*(evidence|pains):end\s*-->")


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def read(path):
    banks, pains, cur, fenced = {}, [], None, False
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
            (banks.__setitem__(cur["attrs"]["name"], cur["rows"]) if cur["kind"] == "evidence"
             else pains.append(cur))
            cur = None
            continue
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] not in ("Evidence", "Pain (their words)"):
                cur["rows"].append(c)
    return banks, pains


def cats(text):
    return {c.strip().lower() for c in text.split(";") if c.strip() and c.strip() != "?"}


def check(block, banks):
    a = block["attrs"]
    ev = [(name, cats(c), proof) for name, c, proof in banks.get(a.get("evidence", ""), [])]
    flags, rows = [], []
    for pain, cat, sev in block["rows"]:
        if cat == "?" or sev == "?":
            flags.append(f"UNDIAGNOSED {pain}: ask what it costs them and how often")
        s = int(sev) if sev.isdigit() else 0
        want = cats(cat)
        match = [(name, proof) for name, c, proof in ev if want & c]
        best = max(match, key=lambda m: bool(re.search(r"\d", m[1]))) if match else None
        if s >= 2 and not match and want:
            flags.append(f"UNMATCHED {pain} (sev {s}): name adjacent evidence honestly, or ask to learn more")
        if s == 3 and best and not re.search(r"\d", best[1]):
            flags.append(f"THIN {pain}: the best evidence ({best[0]}) has no number")
        rows.append((s, pain, best))
    print(f"pains {a.get('name', '?')} (evidence: {a.get('evidence', '-')})")
    print("  pitch order:")
    for s, pain, best in sorted(rows, key=lambda r: -r[0]):
        tag = f"sev {s}" if s else "sev ?"
        print(f"    [{tag}] {pain}")
        print(f"           -> {best[0]}: {best[1]}" if best else "           -> (no evidence yet)")
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
    banks, pains = read(argv[1])
    bad = []
    for block in pains:
        name, flags = check(block, banks)
        if kb and name.startswith("raw-") != bool(flags):
            bad.append(name)
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 10.3 Output: V's two pain tables

<!-- run:pain_match.py SELF --kb -->
```text
pains raw-n-from-jd (evidence: v-evidence)
  pitch order:
    [sev 2] "Mentor engineers"
           -> Design apprenticeship: 2 engineers went on to lead cross-team designs
    [sev 2] "Experience with CUDA kernels"
           -> (no evidence yet)
    [sev ?] "Drive technical excellence"
           -> (no evidence yet)
    [sev ?] "Scale our edge platform"
           -> Beacon rings and auto-halt: 3 bad changes auto-halted at <= 1.1% of instances; config Sev-1s 2 -> 0 in 12 months
  UNDIAGNOSED "Drive technical excellence": ask what it costs them and how often
  UNDIAGNOSED "Scale our edge platform": ask what it costs them and how often
  UNMATCHED "Experience with CUDA kernels" (sev 2): name adjacent evidence honestly, or ask to learn more
  result: 3 item(s) to resolve

pains n-diagnosed (evidence: v-evidence)
  pitch order:
    [sev 3] "One bad OTA build bricked about 300 devices last quarter"
           -> Beacon rings and auto-halt: 3 bad changes auto-halted at <= 1.1% of instances; config Sev-1s 2 -> 0 in 12 months
    [sev 3] "Device telemetry drops data silently; we found a 4% gap only when a customer complained"
           -> Tidewater reconciliation and DLQ: per-partition control totals caught a dropped event before 9 regulatory reports shipped
    [sev 2] "We want to run two models on the edge box where we run one today"
           -> Quickset cache: ranking p99 41 -> 22 ms; 0 allocations on the read path
    [sev 2] "Strong individuals, but nobody writes designs the other teams follow"
           -> Beacon RFC: config-safety policy for ~2,000 engineers
    [sev 1] "On-call is about 25 pages a week"
           -> Beacon on-call: config pages ~11 -> ~2 per month
    [sev 1] "Kernel tuning help would be nice"
           -> (no evidence yet)
  result: clean

VERDICT: OK
```

---

## 11. Word-for-word scripts

#### Script 1 · Verbal: the 30-second opening that hands over the floor

```text
"Thanks for making time. Quick context: I'm the Staff engineer for config and rollout safety
at [marketplace], the platform 1,200 services ship through. Before that, payments, streaming
data, and avionics firmware at the very start.

Before I go further, I'd love to hear it from you: what made you open this role now?"
```

#### Script 2 · Verbal: the five diagnostic questions, chained

```text
"What made you open this role now?
...
If this hire goes really well, what's different in twelve months?
...
What's the most expensive problem on your plate right now?
...
What have you tried so far, and what got in the way?
...
And who would this person need to work with closely to succeed?"
```

#### Script 3 · Verbal: mirror, match, deepen

```text
"Let me make sure I've got it: one bad OTA build reached about 300 devices before anyone could
stop it, and recovery needed physical access to some of them.

On our config platform we had the same class of problem at a different layer. Every change now
goes through rings, and the controller halts automatically on health signals. The worst bad
change since then reached 1.1% of instances for four minutes.

For your devices, the question I'd want to answer first: is there an A/B partition to fall
back to, or does a failed update need hands on the device?"
```

#### Script 4 · Verbal: the honest gap

```text
"I haven't written GPU kernels, and I don't want to pretend otherwise. Where I'm strong is the
serving path around them: memory behavior, batching, latency budgets, and evaluating whether a
change actually helped. I took a feature cache's p99 from 41 to 22 milliseconds with no
allocations on the read path. Is kernel work something this role would own, or does someone on
the team cover it?"
```

#### Script 5 · Verbal: a hypothesis framed as a question

```text
"I'd want to see the data before proposing anything. My hypothesis, from the telemetry
systems I've built, would be that the 4% gap comes from a bounded buffer on the device that
drops when the uplink is slow, without counting the drops. Do you know whether the device
side reports what it drops?"
```

#### Script 6 · Verbal: questions that test the team (bridge to 03.2)

```text
"A few questions about the team, if that's okay with you.
How many engineers, and how long has the team existed in this shape?
What did the last person who was promoted to Staff here do to get there?
How is on-call split, and what's the weekly page count?
What would make you say, a year from now, that this hire was a mistake?"
```

#### Script 7 · Verbal: the close and recap

```text
"Thank you, this was really useful. Here's what I heard: rollout safety and silent telemetry
loss are the two problems that cost you most, edge inference cost is next, and the team needs
someone whose designs other teams follow.

I'll send you a short note in the next day or two on how I'd approach the first 90 days,
mostly how I'd learn before proposing anything. What are the next steps on your side?"
```

#### Script 8 · Email: the same-day thank-you that carries the diagnosis

```text
Subject: Thank you, and what I heard

Hi [HM name],

Thank you for the conversation today. To check I understood:
• The trigger: a bad OTA build last quarter that reached ~300 devices.
• The two expensive problems: rollout safety, and telemetry that drops data silently (~4%).
• The gap: design leadership that other teams follow.

Both problems are ones I've worked on at other layers: staged rings with auto-halt on our config
platform, and reconciliation that catches dropped events before reports ship. I'll send a
one-page note on how I'd approach the first 90 days by [day].

Best,
[Your Name]
```

#### Script 9 · Verbal: a director or skip-level conversation (L7)

```text
"From your side, what's the problem across your teams that no single team can solve? I ask
because the work I'm proudest of is the config-safety policy: no one team owned the problem,
and the fix had to be adopted by everyone. I'd want to understand where this role's authority
ends, and what you'd expect me to leave to the managers."
```

---

## 12. Probe chains

<details><summary><b>P1 · "Walk me through your background."</b></summary>

**Probe:** "Why don't you start by walking me through your background?"

**What they're testing:** whether you can be concise, and whether you'll make it about them.

**Executor answer:** A ten-minute chronological tour, from the first job onward.

**Staff/Principal answer:** "The short version: I'm the Staff engineer for config and rollout safety for 1,200 services; before that, payments, streaming data, and firmware. I'd rather spend our time on your problem. What made you open this role now?" Then use the background as evidence when each pain comes up.

</details>

<details><summary><b>P2 · "So how would you fix our rollout problem?"</b></summary>

**Probe:** "You've heard the problem. What would you do?"

**What they're testing:** whether you'll prescribe before diagnosing, and how you think.

**Executor answer:** "I'd build staged rollouts with canaries and automatic rollback."

**Staff/Principal answer:** "My starting hypothesis would be staged rings with a health-gated halt, because that's what worked for us. But I'd want to know three things first: whether devices can fall back to a known-good partition, what health signal you can trust within minutes of an update, and how rollouts are triggered today. The answers change the design a lot."

</details>

<details><summary><b>P3 · "We need someone who's done exactly this."</b></summary>

**Probe:** "Honestly, we're looking for someone who's run OTA for devices before."

**What they're testing:** whether adjacent experience is enough, and whether you'll overclaim.

**Executor answer:** "I've done something very similar, it's basically the same thing."

**Staff/Principal answer:** "I haven't run OTA for a device fleet. I've run the same problem one layer up, for 48,000 service instances, and the problem one layer down, A/B firmware updates in avionics. What I'd bring is the rollout-safety design; what I'd need to learn quickly is your device constraints. Which of those matters more to you?"

</details>

<details><summary><b>P4 · "How do you handle disagreement with your manager?"</b></summary>

**Probe:** "Tell me about a time you disagreed with your manager."

**What they're testing:** whether you'll be easy to work with, and where you draw lines.

**Executor answer:** "I don't really disagree with managers, I'm easy to work with."

**Staff/Principal answer:** A real story: "My manager wanted to delay the ZooKeeper cutover to protect a launch. I disagreed, because the lease deadline made a delay expensive. I wrote down both options with their costs, we took it to our director together, and we split the cutover so the launch's namespaces moved last. We both changed our position a bit."

</details>

<details><summary><b>P5 · "Why should I hire a Staff engineer instead of two Seniors?"</b></summary>

**Probe:** "Honestly, two strong Seniors might get more done."

**What they're testing:** whether you understand Staff value as leverage, not output.

**Executor answer:** "I can do the work of two engineers."

**Staff/Principal answer:** "For shipping features, maybe. Your problems are different: a rollout design every team has to adopt, and a telemetry correctness standard that crosses the device and cloud teams. Two Seniors would each improve their part. The hire you need makes the parts agree. That's what the config-safety RFC did across about 2,000 engineers."

</details>

<details><summary><b>P6 · "What would make this hire a mistake?"</b></summary>

**Probe:** (The manager turns your question back on you) "You asked what would make this a mistake. What do you think?"

**What they're testing:** self-awareness.

**Executor answer:** "I don't think it would be a mistake."

**Staff/Principal answer:** "Two risks I'd watch. If the role turns out to be mostly kernel tuning, I'm the wrong person. And if I propose changes before I understand why things are the way they are, I'd lose the team. That's why my first month would be learning, and why I'd want you to tell me early if you see either happening."

</details>

<details><summary><b>P7 · "We're a small team. Will you be bored?"</b></summary>

**Probe:** "You come from a 2,000-engineer company. We're a team of nine."

**What they're testing:** retention, and whether you need a big org to be effective.

**Executor answer:** "No, I like small teams too."

**Staff/Principal answer:** "The size isn't what keeps me; the problem is. Rollout safety for devices touches the device team, the cloud team and support. That's cross-team work even with nine engineers. And I've done the small version: in avionics I was one of a handful of engineers on a unit, and that's where I learned most."

</details>

<details><summary><b>P8 · (L7) "How would you work with my managers?"</b></summary>

**Probe:** (Director) "I have three managers. How would a Principal work with them without stepping on them?"

**What they're testing:** whether you know where a Principal's authority ends.

**Executor answer:** "I'd help them make the right technical decisions."

**Staff/Principal answer:** "They own people, priorities and delivery; I'd own the technical direction across their teams and the quality of the big decisions. In practice: I'd write the cross-team designs, review the important ones from their teams, and bring trade-offs to them as options, not verdicts. If I disagree with a priority, I'd say it to the manager first, never around them."

</details>

---

## 13. Checklist

**Before**
- [ ] Your evidence bank in categories, each with a numbered proof (§8.1).
- [ ] Pains guessed from the job description, marked with "?" (§8.2).
- [ ] The five questions and your 30-second opening (Scripts 1–2).

**During**
- [ ] Ask before you pitch; mirror, match, deepen (Script 3).
- [ ] No prescriptions; hypotheses as questions (Script 5).
- [ ] Say so when you can't match a pain (Script 4).
- [ ] Your team questions (Script 6).
- [ ] Close with a recap (Script 7).

**After**
- [ ] Fill the diagnosed pain table and run `pain_match.py`.
- [ ] Send the thank-you with the diagnosis the same day (Script 8).
- [ ] Draft the 30-60-90 note (03.3).

---

## 14. References

- Asking about past behavior rather than hypotheticals: Rob Fitzpatrick, *The Mom Test* (2013), ISBN 9781492180746.
- Staff archetypes and how a Staff engineer's leverage differs from a Senior's: Will Larson, [StaffEng](https://staffeng.com/guides/staff-archetypes/).
- Influence without authority across teams: [Behavioral playbook 03.3, multi-team migrations without mandates](../../Staff-Principal-Behavioral-L7-Playbook/03-Influence-Without-Authority-and-Cross-Org-Alignment/03-driving-multi-team-migrations-and-adoption-without-mandates.md).
- The evidence behind V's bank: [Past-Project Deep-Dive playbook](../../Past-Project-Deep-Dive-L7-Defense-Playbook/README.md).
