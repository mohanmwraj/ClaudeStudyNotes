# 03.2 · Team-matching strategy: evaluating org health, promo velocity and scope

> Folder 03 · Hiring-manager screen and team-match mastery · File 2 of 3 · [KB home](../README.md) · Previous: [03.1 The HM sell call](01-the-hiring-manager-sell-call-diagnosing-their-pain-in-the-first-10-minutes.md) · Next: [03.3 The 30-60-90 note](03-writing-a-1-page-30-60-90-day-staff-onboarding-vision-note-to-seal-the-hm.md)

<!-- lint-pack: hm -->

| | |
|---|---|
| **Reader** | A candidate choosing between teams, in a formal team-match round or across several offers, who wants the team that makes the next level possible |
| **Running exhibit** | Candidate V after passing Loop G's committee, with three teams to choose from: T1, T2 and T3 (§7) |
| **Listing** | `team_score.py`: weighted team comparison with kill criteria, where an unknown scores as a weakness and becomes a question (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run: on the first pass, T2's unknown manager kills it and T1 wins by default; after the skip-level and peer calls, T2 wins clearly. The 8 pairs in §8 are checked with `script_lint.py` (hm pack). |
| **Marks** | ⚠ = field practice, not published policy. Team-match rules differ by company and change; confirm them with your recruiter. |

**Integrity rule.** Ask hard questions, but ask them fairly: about the team's situation, not gossip about people. And tell teams the truth about where you are in the process; team-match managers talk to each other.

---

## 0. The 60-second version

1. **Your team matters as much as your level.** The level gets you in; the team decides whether the next level is reachable. A Staff engineer on a team without Staff-sized problems stays where they are.
2. **Score five things:** scope at your level, the manager, promotion evidence, org health and roadmap funding. Add on-call load and time zones if they matter to you.
3. **Set kill criteria before you meet anyone.** For an L6 target: no clear Staff-sized problem, or a manager you don't trust, ends the conversation regardless of everything else.
4. **An unknown is not a strength.** Score it low and turn it into a question. Most bad team choices come from filling unknowns with optimism.
5. **Talk to three people per team:** the manager, a peer, and the skip-level. Each sees something the others can't.
6. **Promotion velocity is anecdotal; ask for anecdotes.** "What did the last person promoted to Staff here actually do?" beats any statistic.
7. **You can say no to a team,** and usually ask for more options ⚠. Do it warmly; team-match managers talk.

---

## 1. Team-match mechanics by process type ⚠

| Process type | When you choose a team | What you can influence | The trap |
|---|---|---|---|
| **Committee, then match** (Google-style) | After the committee approves; often several conversations | Which teams you speak to; asking for more; declining | Taking the first team because the process is long |
| **Team selection before the offer** (reported at Meta since ~2023) | After candidate review, before the offer | Which teams; sometimes timing | Optimizing for speed over fit |
| **Req-based** (Amazon-style) | Before the loop: you interview for one team | Which req you're mapped to | Discovering after joining that the team isn't what the req said |
| **HM-driven** (NVIDIA-, Apple-style, most product companies) | Before the loop | Everything about the team, before you interview | Not asking because "it's obviously this team" |

Two general points:
- **The level is usually fixed before the team match** ⚠. A team can't normally change it, though some can sponsor a re-evaluation (Folder 04).
- **Comp is usually set by level and location,** not team ⚠. Choose the team on its merits.

---

## 2. The five things to score

| Criterion | What "5" looks like | What "1" looks like | Who tells you |
|---|---|---|---|
| **Scope at your level** | A named, unowned problem that crosses teams and lasts years | Feature work on a mature system | The manager, then the skip-level |
| **Manager** | Has grown people to your level and beyond; stable; describes past departures generously | New, or a high-turnover history; vague about what success looks like | Peers, the skip-level, and how the manager talks |
| **Promotion evidence** | Recent promotions to and beyond your level, with concrete stories | "We'll see"; nobody promoted to Staff in years | The manager and peers |
| **Org health** | Stable or growing headcount; no reorg in the last year; low attrition | Repeated reorgs; shrinking headcount; several managers in two years | Peers and the skip-level |
| **Roadmap funding** | Funded for the next year; tied to a company priority | "Keep the lights on"; unfunded ideas | The skip-level |
| *On-call load* | Sustainable, with repeat causes being fixed | Heavy and growing | Peers |
| *Time zones* | Decision-makers in your time zone, or good overlap | Decisions made while you sleep | The manager |

**Scope at your level** is the criterion people under-weight most. Ask the manager directly: "What's the problem this hire would own that nobody owns today?" If the answer is a list of features, the role is Senior-shaped whatever its level.

---

## 3. Questions for the three people

### 3.1 The manager

1. "What would this person own that nobody owns today?"
2. "What did the last person promoted to Staff on this team do to get there?"
3. "How do you decide what goes in a promotion packet, and who writes it?"
4. "What's the team's biggest risk this year?"
5. "Who were the last two people to leave the team, and why?" (Listen for generosity, not details.)

### 3.2 A peer (ask the manager to connect you)

1. "What does a normal week look like, including on-call?"
2. "How are big technical decisions made here, and who makes them?"
3. "What would you change about the team if you could?"
4. "How does the manager handle disagreement?"

### 3.3 The skip-level

1. "How does this team's work connect to the org's priorities this year?"
2. "Is the roadmap funded beyond the next two quarters?"
3. "What would you need from a Staff engineer here that you don't have today?"
4. "Is there a path to Principal-level scope from this team, or would that mean moving?"

---

## 4. Promotion velocity, honestly ⚠

You won't get statistics. Companies rarely share promotion rates, and a single team's numbers are too small to mean much anyway. What you can get are **anecdotes**, and anecdotes are informative:

| Anecdote | What it suggests |
|---|---|
| "Two people were promoted to Staff last year; one led the storage migration, one built the eval platform." | Staff-sized problems exist and are recognized |
| "Our last Staff promotion was three years ago." | Either few Staff-sized problems, or a manager who doesn't build packets |
| "Promotions are decided by a committee outside the org." | The manager's packet-writing matters a lot; ask how they write them |
| "We had a Principal, but they moved teams." | Ask why: was the scope gone? |

Two realities to keep in mind:
- **The L6 → L7 step at large companies is slow and scope-dependent** ⚠. It usually needs a problem that crosses orgs and a sponsor above the manager. Choose teams where such problems exist.
- **New teams create scope; mature teams consume it.** A newly funded team with a good manager is often the fastest path to the next level, and also the riskiest.

---

## 5. Kill criteria and weights

Set these **before** your first team conversation, so a charismatic manager can't talk you out of them.

| Setting | V's choice | Why |
|---|---|---|
| Kill: scope below 3 | Yes | An L6 hire on a Senior-shaped team won't stay L6-shaped for long |
| Kill: manager below 3 | Yes | A weak manager can stall a promotion indefinitely |
| Weights | Scope 5, manager 4, promotion evidence 3, org health 3, roadmap funding 3, on-call 2, time zone 1 | V's priorities; yours may differ |
| Unknown cells | Score as 1 | An unknown is a risk until resolved |

The last rule has a consequence: **an unknown on a kill criterion kills the team** until you resolve it. That's deliberate. It forces you to ask before you choose.

---

## 6. India-specific realities

- **Where does design authority sit?** In captive centers and India-based teams of global companies, some teams own their systems end to end and some execute designs from elsewhere ⚠. Ask: "Who approves designs for this system, and where are they?"
- **Is L7 scope available in-country?** Principal-level roles in India sometimes have org-wide scope, and sometimes a satellite scope under a US-based Principal ⚠. Ask the skip-level directly.
- **Time-zone overlap.** If decisions happen in a US morning meeting, ask how India-based engineers take part, and how often.
- **Team stability.** India teams of global companies are sometimes the first affected by reorganizations ⚠. Ask about the last two years.

---

## 7. Candidate V's team match (Loop G)

V passed Loop G's committee at L6 and has three teams to consider:

- **T1:** the cloud config and deploy team. Familiar work, a strong and stable manager, a mature system, few recent Staff promotions.
- **T2:** a newly funded edge-AI serving team. Big scope, strong funding, a new manager V knows nothing about yet.
- **T3:** a data-platform team in maintenance mode with heavy on-call.

**First pass,** after one call with each manager:

<!-- teams:start name=g-match-first-pass kill=scope:3,manager:3 expect=winner:T1 -->
| Criterion | Weight | T1 | T2 | T3 |
|---|---|---|---|---|
| scope | 5 | 3 | 5 | 2 |
| manager | 4 | 4 | ? | 3 |
| promotion evidence | 3 | 2 | ? | 2 |
| org health | 3 | 4 | 3 | 3 |
| roadmap funding | 3 | 3 | 5 | 2 |
| on-call | 2 | 3 | 4 | 1 |
| time zone | 1 | 3 | 4 | 4 |
<!-- teams:end -->

The run (§9.3) kills T3 on scope and T2 on its unknown manager, so T1 "wins" by default. That's not a decision; it's a list of questions. V asks the T2 manager for a peer call and a skip-level conversation (Scripts 1–2).

**After the calls.** The peer describes the T2 manager as someone who built the last team's promotion packets carefully and handled disagreement well; the skip-level confirms that two engineers on the manager's previous team were promoted to Staff:

<!-- teams:start name=g-match-after-calls kill=scope:3,manager:3 expect=winner:T2 -->
| Criterion | Weight | T1 | T2 | T3 |
|---|---|---|---|---|
| scope | 5 | 3 | 5 | 2 |
| manager | 4 | 4 | 4 | 3 |
| promotion evidence | 3 | 2 | 3 | 2 |
| org health | 3 | 4 | 3 | 3 |
| roadmap funding | 3 | 3 | 5 | 2 |
| on-call | 2 | 3 | 4 | 1 |
| time zone | 1 | 3 | 4 | 4 |
<!-- teams:end -->

T2 wins clearly. V accepts T2 and declines T1 warmly (Script 5), and asks the T2 manager to confirm the scope in writing (Script 6).

---

## 8. Before → After: team-match conversations

#### S41 · Asking about scope

| Version | Answer |
|---|---|
| **Weak** | I'm sure there's lots of interesting work, so whatever you need is fine with me. |
| **Strong** | What would this person own that nobody owns today? I'm looking for a problem that crosses teams and runs for a couple of years. |

#### S42 · Asking about promotions

| Version | Answer |
|---|---|
| **Weak** | I was wondering if maybe people get promoted here, if that's okay to ask? |
| **Strong** | What did the last person promoted to Staff on this team do to get there, and who wrote the packet? |

#### S43 · Asking about departures

| Version | Answer |
|---|---|
| **Weak** | Between you and me, is the manager the reason people leave? |
| **Strong** | Who were the last two people to leave the team, and what did they go on to do? |

#### S44 · Declining a team

| Version | Answer |
|---|---|
| **Weak** | Sorry, I'm afraid your team just isn't really what I want, the work looks kind of boring. |
| **Strong** | Thank you for the time. I'm going to choose a team where the scope is closer to new systems work, which fits what I want to build next. I'd be glad to collaborate if our paths cross. |

#### S45 · Asking for more teams

| Version | Answer |
|---|---|
| **Weak** | I guess I could take one of these if there's nothing else, I don't want to be difficult. |
| **Strong** | None of the three is a clear fit for Staff scope yet. Are there one or two more teams I could speak with, ideally on serving or data infrastructure? |

#### S46 · The manager oversells

| Version | Answer |
|---|---|
| **Weak** | Wow, that sounds amazing, I'm in, it's my dream job. |
| **Strong** | That sounds like a real opportunity. Could I speak with someone on the team and with your manager, so I understand how it connects to the org's priorities? |

#### S47 · Raising on-call

| Version | Answer |
|---|---|
| **Weak** | I'm kind of worried the on-call might be too much for me. |
| **Strong** | How many pages does the rotation get in a typical week, and what share are repeat causes? I'd want to know where the load comes from. |

#### S48 · Asking about decision rights (India)

| Version | Answer |
|---|---|
| **Weak** | I'm a bit worried the India team just follows orders from the US. Is that the case here? |
| **Strong** | Who approves designs for this system, and where are they? I'd like to understand where design authority sits for the work this role would own. |

---

## 9. The listing: `team_score.py`

### 9.1 What it does

It computes a weighted total per team, applies your kill criteria, and prints a ranking. Unknown scores count as 1 and are listed as questions. If the top two surviving teams are within 5% of the maximum score, it says so: that's a close call, and the open questions should decide it, not the arithmetic.

To use it: copy the table format from §7 into `teams.md`, set your weights and kill criteria **before** your first call, fill scores as you learn, and run `python -I team_score.py teams.md`.

### 9.2 Listing

<!-- include:team_score.py -->
```python
#!/usr/bin/env python3
"""team_score.py: compare teams in a team-match round with weights, kill criteria and open questions.

Reads every block like this from a Markdown file:

  <!-- teams:start name=match kill=scope:3,manager:3 -->
  | Criterion | Weight | T1 | T2 | T3 |
  |---|---|---|---|---|
  | scope | 5 | 4 | 3 | 5 |
  | manager | 4 | ? | 4 | 3 |
  <!-- teams:end -->

Scores are 1-5 from your own evidence (what the manager, skip-level and peers told you). '?' means you don't
know yet; it scores as 1 (an unknown is not a strength) and becomes a question to ask.
'kill=crit:min,...' eliminates any team scoring below min on that criterion, whatever its total.
Usage: python -I team_score.py FILE.md [--kb]
  --kb  check each block's expect=winner:TEAM against the result.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*teams:start\s+(.*?)-->")
END = re.compile(r"<!--\s*teams:end\s*-->")


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
            cur = {"attrs": dict(re.findall(r"(\w+)=(\S+)", m.group(1))), "head": None, "rows": []}
            continue
        if cur is not None and END.search(line):
            blocks.append(cur)
            cur = None
            continue
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] == "Criterion":
                cur["head"] = c[2:]
            else:
                cur["rows"].append(c)
    return blocks


def score(block):
    a = block["attrs"]
    teams = block["head"]
    kill = {}
    for item in a.get("kill", "").split(","):
        if ":" in item:
            k, v = item.split(":")
            kill[k] = int(v)
    total = {t: 0 for t in teams}
    maxw = 0
    killed = {t: [] for t in teams}
    asks = []
    for row in block["rows"]:
        crit, w, vals = row[0], int(row[1]), row[2:]
        maxw += 5 * w
        for t, v in zip(teams, vals):
            s = 1 if v == "?" else int(v)
            if v == "?":
                asks.append(f"ASK {t}: {crit}")
            total[t] += s * w
            if crit in kill and s < kill[crit]:
                killed[t].append(f"{crit} {s} < {kill[crit]}" + (" (unknown)" if v == "?" else ""))
    print(f"teams {a.get('name', '?')} (kill: {a.get('kill', '-')})")
    ranked = sorted(teams, key=lambda t: -total[t])
    for t in ranked:
        pct = 100 * total[t] / maxw
        state = "KILLED: " + "; ".join(killed[t]) if killed[t] else "alive"
        print(f"  {t:<4} {total[t]:>4}/{maxw} ({pct:4.1f}%)  {state}")
    alive = [t for t in ranked if not killed[t]]
    winner = alive[0] if alive else None
    if len(alive) > 1 and total[alive[0]] - total[alive[1]] <= 0.05 * maxw:
        print(f"  close call: {alive[0]} vs {alive[1]} within 5%; resolve the open questions before choosing")
    for x in asks:
        print(f"  {x}")
    print(f"  pick: {winner or 'none (every team killed)'}")
    return winner


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    bad = []
    for block in read(argv[1]):
        winner = score(block)
        exp = block["attrs"].get("expect", "")
        if kb and exp.startswith("winner:") and exp.split(":", 1)[1] != (winner or "none"):
            bad.append(block["attrs"].get("name", "?"))
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's two passes

<!-- run:team_score.py SELF --kb -->
```text
teams g-match-first-pass (kill: scope:3,manager:3)
  T2     68/105 (64.8%)  KILLED: manager 1 < 3 (unknown)
  T1     67/105 (63.8%)  alive
  T3     49/105 (46.7%)  KILLED: scope 2 < 3
  ASK T2: manager
  ASK T2: promotion evidence
  pick: T1

teams g-match-after-calls (kill: scope:3,manager:3)
  T2     86/105 (81.9%)  alive
  T1     67/105 (63.8%)  alive
  T3     49/105 (46.7%)  KILLED: scope 2 < 3
  pick: T2

VERDICT: OK
```

---

## 10. Word-for-word scripts

#### Script 1 · Email: asking a manager for a peer conversation

```text
Subject: A short call with someone on the team?

Hi [Manager name],

Thank you for the conversation yesterday; [the edge-serving problem] is exactly the kind of
work I want to do next. Before I decide, would you be open to connecting me with an engineer
on the team for 20 minutes? I'd like to hear how the team works day to day, including on-call.

Best,
[Your Name]
```

#### Script 2 · Email: asking for a skip-level conversation

```text
Subject: 20 minutes with [Skip-level name]?

Hi [Recruiter or Manager name],

I'm close to a decision between two teams. Would it be possible to speak with [Skip-level
name] for 20 minutes? I'd like to understand how [team]'s roadmap connects to the org's
priorities beyond the next two quarters, and what they'd need from a Staff engineer.

Best,
[Your Name]
```

#### Script 3 · Verbal: the manager questions, in order

```text
"Five questions, if that's all right.
What would this person own that nobody owns today?
What did the last person promoted to Staff on this team do to get there?
How do promotion packets get written here, and who writes them?
What's the team's biggest risk this year?
And who were the last two people to leave the team, and what did they go on to do?"
```

#### Script 4 · Email: asking the recruiter for more team options

```text
Subject: Team options

Hi [Recruiter name],

Thank you for setting up the team conversations. I enjoyed all three. None is yet a clear fit
for Staff-level scope in the areas I'm strongest in, so I'd like to ask: are there one or two
more teams I could speak with, ideally in [serving infrastructure / data infrastructure]?

I'm keeping my overall decision date of [date] in mind, so I'm happy to move quickly.

Best,
[Your Name]
```

#### Script 5 · Email: declining a team warmly

```text
Subject: Thank you

Hi [Manager name],

Thank you for the time you spent with me, and for being so open about the team. I've decided
to join [other team], where the scope is closer to the new-systems work I want to do next.
That's no reflection on your team; I came away impressed by [specific thing].

I hope our paths cross, and I'd be glad to help with [area] if it's ever useful.

Best,
[Your Name]
```

#### Script 6 · Email: confirming the scope in writing

```text
Subject: Confirming what I'd own

Hi [Manager name],

I'm excited to choose [team]. To make sure we start aligned, here's my understanding of the
scope we discussed:
• Own the rollout-safety design for [system], across the device and cloud teams.
• Lead the telemetry-correctness work, with a measurable target we'd set in the first 60 days.
• Contribute to the team's design-review practice.

Does that match your view? If anything's different, I'd rather know now.

Best,
[Your Name]
```

#### Script 7 · Verbal: telling a team-match manager where you are in the process

```text
"To be transparent about timing: I'm speaking with two other teams this week and I expect to
decide by Friday. I'm not running an auction; I want to choose the team where the scope fits
best, and I'll tell you either way."
```

#### Script 8 · Verbal: the skip-level questions

```text
"How does this team's work connect to the org's priorities this year?
Is the roadmap funded beyond the next two quarters?
What would you need from a Staff engineer here that you don't have today?
And is there a path to Principal-level scope from this team, or would that mean moving?"
```

---

## 11. Probe chains

<details><summary><b>P1 · "Why do you want to talk to my manager?"</b></summary>

**Probe:** (A team-match manager) "Why do you need a skip-level call? I can answer your questions."

**What they're testing:** whether you trust them, and whether you're difficult.

**Executor answer:** "Oh, never mind, that's fine, I'll just go with what you said."

**Staff/Principal answer:** "You've answered most of them, thank you. What I can't ask you fairly is how the org sees this team's roadmap a year out, and that's the biggest factor for Staff scope. It's not about doubting you; I'd ask the same on any team."

</details>

<details><summary><b>P2 · "Every team here has Staff scope."</b></summary>

**Probe:** "Don't worry about scope. Any team here has plenty of Staff-level work."

**What they're testing:** nothing; it's reassurance. Your job is to make it concrete.

**Executor answer:** "Great, then I'm happy with any team."

**Staff/Principal answer:** "Good to hear. To make it concrete for this team: what's one problem I'd own that nobody owns today? If you can name it, that's the strongest reason to choose this team."

</details>

<details><summary><b>P3 · "We haven't had a Staff promotion recently, but we will."</b></summary>

**Probe:** "We haven't promoted anyone to Staff in a while, but there's lots of opportunity."

**What they're testing:** nothing; but the answer tells you a lot.

**Executor answer:** "Okay, that sounds fine."

**Staff/Principal answer:** "Thanks for being straight. What do you think has made it hard? Is it the kind of problems the team has had, or how promotions are decided in the org? It would help me understand what would be different now."

</details>

<details><summary><b>P4 · "You need to decide by tomorrow."</b></summary>

**Probe:** (Recruiter) "The team needs an answer tomorrow, or the slot goes to another candidate."

**What they're testing:** whether pressure will make you choose without information.

**Executor answer:** "Okay, I'll take it."

**Staff/Principal answer:** "I understand there's pressure on the slot. I need one more conversation, with the skip-level, to decide well. Could we do it today or tomorrow morning, so I can answer by end of day tomorrow? If that's impossible, I'd rather lose the slot than choose blind."

</details>

<details><summary><b>P5 · "Why didn't you pick the team closest to your experience?"</b></summary>

**Probe:** (Later, from the chosen manager) "T1 was basically your current job. Why us?"

**What they're testing:** motivation, and whether you'll stay.

**Executor answer:** "Your team seemed more interesting."

**Staff/Principal answer:** "T1 was the safe choice: I'd have been productive in a week. I chose your team because the problem is bigger and newer, and because rollout safety for devices is where my firmware and platform experience combine. That's also why I'll stay: it's a multi-year problem."

</details>

<details><summary><b>P6 · "Can the team change my level?"</b></summary>

**Probe:** (Candidate's own question) "If the team thinks I'm L7-scope, can they change the level?"

**What they're testing:** (the recruiter) whether you understand the process.

**Executor answer:** (A candidate pushing) "I'd like the team to re-level me before I accept."

**Staff/Principal answer:** "I understand the level is set by the committee and usually doesn't change at team match. What I'd ask instead is that the manager confirm the scope in writing, so if the work turns out to be larger, there's a clear record for the next promotion cycle."

</details>

<details><summary><b>P7 · "This team had a reorg six months ago."</b></summary>

**Probe:** (Peer) "We were reorganized six months ago, and our manager is new to the team."

**What they're testing:** nothing; it's information you asked for.

**Executor answer:** "Oh, okay, I'm sure it's fine."

**Staff/Principal answer:** "Thanks for telling me. What changed in the reorg, and has the roadmap settled since? And how is the new manager approaching promotion packets for the team so far?"

</details>

<details><summary><b>P8 · (L7) "Principal scope here means working across three orgs."</b></summary>

**Probe:** (Skip-level) "For Principal, you'd be expected to drive alignment across three orgs, not just this team."

**What they're testing:** whether you understand L7 scope, and want it.

**Executor answer:** "Sure, I can do that."

**Staff/Principal answer:** "That's the scope I'm looking for. Can you tell me which decision across the three orgs is currently stuck, and who would be my counterparts? That's where I'd start, and it would tell me whether the role has the authority it needs."

</details>

---

## 12. Checklist

- [ ] Weights and kill criteria set **before** the first conversation (§5).
- [ ] Manager, peer and skip-level conversations for every serious team (§3; Scripts 1–3, 8).
- [ ] Every unknown scored low and listed as a question; `team_score.py` re-run after each call.
- [ ] Promotion anecdotes, not statistics (§4).
- [ ] India: design authority, in-country L7 scope, time-zone overlap (§6).
- [ ] Scope confirmed in writing with the chosen manager (Script 6).
- [ ] Every other team declined warmly (Script 5).

---

## 13. References

- Meta's pre-offer team matching (reported practice, not official documentation): [IGotAnOffer on Meta team matching](https://igotanoffer.com/en/advice/meta-team-matching).
- What Staff work looks like in different archetypes, which helps judge scope: [StaffEng: Staff archetypes](https://staffeng.com/guides/staff-archetypes/).
- How committees and leveling reviews read scope after you join: [Behavioral playbook 01.1](../../Staff-Principal-Behavioral-L7-Playbook/01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md).
