# 08.3 · Red-Flag Phrases to Ban, and Power Vocabulary for Staff Engineers

> **Folder 08 · File 3 of 3.** Interviewers write down your words. A packet that quotes "I was involved in the migration" and "we kind of aligned with the other teams" reads as L5 no matter what the project was. One that quotes "I proposed the cutover order, and the director approved it after I showed the rollback test" reads as ownership.
>
> Language isn't a substitute for scope; it's how scope gets *recorded*. This file covers:
> - red-flag phrases by category, why each hurts, and its replacement;
> - four grammar transformations that fix most weak sentences;
> - power vocabulary, and the rule that makes it work: every term must be backed by a specific;
> - `story_lint.py`, a small script that scans your story drafts for red flags;
> - a rubric, two before-and-after blueprints and the probes that exploit vague language.
>
> This is the full list promised in the README: the KB's own gate checks every L7 telling against the red-flag phrases below.

---

## 1. Red-flag phrases

### 1.1 Passenger phrases: you were near the work, not driving it

| Phrase | What the interviewer writes | Replace with |
|---|---|---|
| "I helped…" | Contribution unclear | The specific action: "I wrote", "I designed", "I negotiated" |
| "I was involved in…" | Passenger | What you decided and did |
| "I was part of…" | Passenger | Your role, then your decisions |
| "I was responsible for…" | A job description, not an action | "I owned X, and the call I made was…" |
| "I was asked to…" / "My manager asked me to…" | Assigned problem; no origin | How you found or framed it, or "I took on X because…" |
| "I was tasked with…" | Assigned | As above |
| "I participated in…" | Attendance | What you contributed |
| "I tried to…" | It didn't work, or you're not sure | What you did, and what happened |

### 1.2 Collective fog: the decision has no owner

| Phrase | Problem | Replace with |
|---|---|---|
| "We decided…" | Who decided? | "I proposed X; the director decided after…" |
| "The team decided…" | Same | Name the decider and your part |
| "It was decided…" | Passive, ownerless | Active voice, named decider |
| "We came up with…" | Whose idea? | "Priya's idea was X; I extended it to Y" |

### 1.3 Hedges: low conviction

| Phrase | Problem | Replace with |
|---|---|---|
| "kind of", "sort of" | Imprecision | Delete, or be precise |
| "basically" | Signals simplification of something you can't explain | Delete |
| "I guess", "I think maybe" | Low confidence about your own story | State it; if unsure, say what you'd check |
| "pretty much", "more or less" | Vague | The number |

### 1.4 Vague impact: no number, no baseline

| Phrase | Problem | Replace with |
|---|---|---|
| "significantly", "greatly improved", "huge impact" | Unmeasured | The metric, baseline, window and result |
| "a lot of", "many teams", "various stakeholders" | Uncounted | The count, and the names that matter |
| "improved performance", "made it better" | Which property? | "p99 from 450 to 120 ms on replayed peak" |

### 1.5 Blame and disparagement

| Phrase | What the interviewer writes | Replace with |
|---|---|---|
| "The legacy team…", "the old system was a mess" | Disrespects what came before (02.1 §1.2) | Why it was built that way, and what changed |
| "They didn't understand…" | Low empathy | Their priority, stated fairly |
| "It wasn't my fault" | Defensive | Your part, owned |
| "The business didn't…" | Us-versus-them | The business constraint, as a legitimate input |

### 1.6 Inflation

| Phrase | Why it backfires | Replace with |
|---|---|---|
| "single-handedly" | Invites "who else worked on it?" and an Earn Trust concern | Your part, plus named credit |
| "revolutionized", "transformed" | Unfalsifiable | The before and after |
| "I led the entire…" (when you led part) | Collapses on the first probe | The workstream you led |

### 1.7 Process fog and filler

| Phrase | Problem | Replace with |
|---|---|---|
| "we aligned", "synergy", "touched base", "circled back" | Describes meetings, not decisions | Who agreed to what |
| "to be honest", "honestly" | Implies the rest wasn't | Delete |
| "obviously" | Dismisses the listener, or the alternatives | Delete, and state the reasoning |

---

## 2. Four grammar transformations

Most weak sentences are fixed by one of these:

| Transformation | Before | After |
|---|---|---|
| **Passive → active** | "A decision was made to migrate in cohorts." | "I proposed migrating in cohorts; the director approved it." |
| **We → I + named credit** | "We built the reconciler." | "Priya built the reconciler's diffing engine; I defined what 'equivalent' meant." |
| **Adjective → number** | "Latency improved significantly." | "p99 fell from 450 ms to 120 ms over comparable weeks." |
| **Process → decision** | "We had several alignment meetings." | "The pricing TL agreed to migrate last after my replay prototype cut his cost estimate by 70%." |

---

## 3. Power vocabulary

### 3.1 The rule

Every term below is a **claim**. Used without a specific behind it, it reads as jargon, and experienced interviewers probe it immediately ("what was the mechanism, exactly?"). Use a term only when you can follow it with the concrete thing.

### 3.2 Verbs of ownership

| Verb | Use it for | The specific that must follow |
|---|---|---|
| **framed / reframed** | Changing how a problem was understood | The old framing and the new one |
| **proposed** | Your recommendation, with someone else deciding | Who decided |
| **decided** | A call that was yours | What you decided between |
| **sequenced** | Ordering work by risk | The order, and why |
| **retired / deprecated** | Removing systems | What, and what it saved |
| **unblocked** | Removing a constraint for many | Who was blocked, and on what |
| **negotiated** | Trading something real | What each side gave |
| **sponsored** | Spending your credibility on someone | The person and the opportunity |
| **delegated** | Giving away decisions | Which decisions, and which you kept |
| **instituted / codified** | Creating a mechanism | The mechanism, and who owns it now |

### 3.3 Nouns that signal senior operating context

| Term | Meaning | Taught in |
|---|---|---|
| **mechanism** | A complete process (tool, adoption, audit) that makes the right behavior the default | 02.1 §1.3 |
| **tenet** | A short, ordered principle for making trade-offs | 02.1 §1.3 |
| **one-way / two-way door** | Irreversible vs reversible decisions | 04.2 |
| **tripwire / kill criteria** | A pre-agreed condition that triggers a stop or a revisit | 04.2 §4 |
| **blast radius** | How much is affected when something fails | 05.2, 06.1 |
| **error budget** | The allowed unreliability under an SLO | 04.3 §6 |
| **unit cost** | Cost per unit of business output | 06.2 §3 |
| **paved road** | A supported default path, easier than the alternatives | 03.3, 06.2 |
| **decision record** | A written record of what was decided, why, and what would reopen it | 03.1, 04.2 |
| **lead time to fix vs time to impact** | Why a not-yet-broken problem is urgent | 04.1 §3 |

### 3.4 Phrases that carry L7 meaning

- "The decision I owned was…"
- "The trade-off was… and what we gave up was…"
- "Their strongest argument was…, and they were right about…"
- "What would change my mind is…"
- "The first phase paid for the second."
- "I sequenced it by blast radius."
- "That's the irreversible part, so I slowed down only that."
- "It now runs without me; [name] owns it."

---

## 4. `story_lint.py`: scan your own drafts

Paste your story drafts into a text file and run this. **Red** phrases should not appear in a story you intend to tell at L7. **Amber** phrases are usually vague; keep them only when a number or name follows immediately.

```python
"""story_lint.py - flag red-flag phrases in behavioral story drafts.

Usage: python story_lint.py draft.txt [more.txt ...]
Red   = passenger, ownerless, hedging, blaming or inflating phrases: remove them.
Amber = usually vague: keep only if a number or a name follows.
Exit code 1 if any red phrase is found.
"""
import re
import sys

RED = {
    "passenger": [r"i helped", r"i was involved in", r"i was part of", r"i was responsible for",
                  r"i was asked to", r"my manager asked me", r"i was tasked with", r"i tried to",
                  r"i participated in"],
    "ownerless": [r"we decided", r"the team decided", r"it was decided"],
    "hedge": [r"kind of", r"sort of", r"basically", r"i guess", r"i think maybe", r"pretty much"],
    "blame": [r"the legacy team", r"they didn't understand", r"it wasn't my fault"],
    "inflation": [r"single-handedly", r"revolutioni[sz]ed"],
    "fog": [r"synergy", r"touched base", r"circled back", r"to be honest"],
}
AMBER = {
    "vague impact": [r"significantly", r"greatly improved", r"huge impact", r"a lot of",
                     r"various stakeholders", r"improved performance"],
    "collective": [r"we came up with", r"we aligned"],
    "filler": [r"honestly", r"obviously"],
}


def scan(text, table):
    hits = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for category, patterns in table.items():
            for pattern in patterns:
                for m in re.finditer(r"\b" + pattern + r"\b", line, flags=re.I):
                    hits.append((lineno, category, m.group(0)))
    return hits


def main():
    red_total = 0
    for name in sys.argv[1:]:
        with open(name, encoding="utf-8") as f:
            text = f.read()
        red, amber = scan(text, RED), scan(text, AMBER)
        red_total += len(red)
        for lineno, category, phrase in red:
            print(f"{name}:{lineno}: RED   [{category}] '{phrase}'")
        for lineno, category, phrase in amber:
            print(f"{name}:{lineno}: AMBER [{category}] '{phrase}'")
        print(f"{name}: {len(red)} red, {len(amber)} amber")
    sys.exit(1 if red_total else 0)


if __name__ == "__main__":
    main()
```

A clean lint doesn't make a story L7: the scope has to be real. It does stop the language from hiding scope that is.

---

## 5. Hiring Committee Scoring Rubric (language signals)

| Signal | Strong Hire at L7 | Down-level to L5 |
|---|---|---|
| **Agency** | Active voice; "I" on decisions and actions; deciders named | Passive voice; passenger verbs |
| **Credit** | Named credit to others, specific to their contribution | "We" throughout, or "I" for everything |
| **Precision** | Numbers with baselines and windows | Adjectives |
| **Conviction** | Clear statements; uncertainty stated as what you'd check | Hedges |
| **Respect** | Counterparts and predecessors described fairly | Blame or disparagement |
| **Vocabulary** | Senior terms, each backed by a specific | Jargon without substance, or no senior vocabulary at all |
| **Consistency** | Same numbers and roles in every round | Numbers drift between interviewers |

---

## 6. Story Blueprints: before and after

### 6.1 The same paragraph, before and after the lint (composite: a cutover story)

#### How an L5 tells it

> "I was involved in the cutover planning for the order migration. We decided to kind of do it in phases, and I helped coordinate with the various stakeholders. Basically, we aligned with operations and security, and the cutover went significantly better than the last migration. I was responsible for the data part."

**Lint result:** six red phrases (involved in, we decided, kind of, helped, basically, responsible for) and three amber (various stakeholders, we aligned, significantly). The interviewer can't quote a single decision.

#### How an L7 tells it

> "I owned the data and cutover workstream for the order migration. I proposed cutting over by store cohort rather than in one weekend, because a failed big-bang cutover meant rolling back a database that had already taken new orders. The program director approved it after I showed her that cohorts didn't extend the critical path. Operations and security each signed off per cohort, against a readiness checklist I wrote. We had zero order-capture outages across 1,200 stores, against two four-hour outages in the previous migration."

**What separates them:** every sentence has an owner and an action; the decider is named; the stakeholders are counted and their role is specific; the result has a baseline.

### 6.2 Fixing a failure story's language (composite: a retry-storm outage)

#### How an L5 tells it

> "We had an outage that was sort of caused by retries. To be honest, the retry logic was written by another team originally, but I was part of the group that fixed it. We came up with a better approach and things greatly improved."

**Lint result:** red (sort of, to be honest, I was part of), amber (we came up with, greatly improved), plus implicit blame ("written by another team originally"). This reads as a candidate avoiding ownership.

#### How an L7 tells it

> "A retry policy I designed turned a provider slowdown into a 47-minute checkout outage. I'd set three fast retries as the default in our shared client; with 300 services retrying at once, that tripled the load on a struggling dependency. I redesigned it around retry budgets, at most 10% of requests per client, with jitter. In the eighteen months since, three similar slowdowns have caused no outages."

**What separates them:** ownership in the first sentence, the mechanism stated precisely, the fix named, and the result measured over time (05.1 §7.1).

---

## 7. Bar-Raiser Follow-Up Chains: the probes that exploit vague language

Interviewers are trained to pull on exactly these threads:

| Vague phrase | The probe | What it exposes |
|---|---|---|
| "We decided" | "Who decided? What did you recommend?" | Decision rights |
| "I helped" | "What did you do yourself?" | Contribution |
| "Significantly" | "By how much? From what baseline? Over what window?" | Measurement |
| "Various stakeholders" | "Who, specifically? Who disagreed?" | Influence |
| "We aligned" | "Who agreed to what? What did it cost them?" | Real negotiation |
| "The legacy system was a mess" | "Why was it built that way?" | Respect what came before |
| "Single-handedly" | "Who else worked on it?" | Credibility |
| "Basically" | "Walk me through the detail." | Depth |
| "Mechanism" (with nothing behind it) | "What exactly was the mechanism, and who owns it now?" | Substance |

---

## 8. Checklist

- [ ] Every story card run through `story_lint.py` with zero red phrases.
- [ ] Every amber phrase followed by a number or a name, or removed.
- [ ] Every decision in your stories has a named decider.
- [ ] Every counterpart and predecessor described fairly.
- [ ] Every senior term backed by a specific you can expand for five minutes.
- [ ] Your numbers are identical on every story card and in every rehearsal.

## 9. References

- In this KB: [01.3 §3 The grammar of ownership](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/03-beyond-star-the-l7-executive-storytelling-architecture.md) · [02.1 §2 The "I" vs "we" probe](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md) · [08.1 The story bank](01-the-8-core-stories-matrix-mapping-to-every-faang-question.md) · [08.2 The pitch](02-2-minute-elevator-pitch-and-reverse-interview-questions-for-vp-directors.md)
- Amazon, *Leadership Principles* (Earn Trust: "vocally self-critical"). <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
