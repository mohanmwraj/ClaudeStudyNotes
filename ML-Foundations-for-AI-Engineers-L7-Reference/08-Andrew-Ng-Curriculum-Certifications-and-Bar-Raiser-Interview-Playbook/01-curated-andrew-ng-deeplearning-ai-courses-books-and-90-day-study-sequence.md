# 08.1 · Curated Andrew Ng / DeepLearning.AI Courses, Books & a 90-Day Study Sequence

> **Folder 08 · Andrew Ng Curriculum, Certifications & Bar-Raiser Interview Playbook**
> **Verified on:** the DeepLearning.AI course catalog and course pages, and Coursera course pages, read on 2026-10-30 (titles, instructors, listed durations). The plan is computed by a listing from those durations plus explicitly marked assumptions.
> **Design sources:** Ng (*Machine Learning Yearning*; *How to Build Your Career in AI*; the *Agentic AI*, *Machine Learning in Production* and Deep Learning Specialization courses), Cepeda et al. (spacing effect, 2006), Roediger & Karpicke (testing effect, 2006). Full list in §8.

---

## 0. Orientation: Learn the Measurement Skills First

The brief asked for "Andrew Ng's AI Engineering Skills Map". No canonical Ng document by that name could be found, so this KB uses its own synthesis (README), built from Ng's verifiable frameworks. What those frameworks agree on, and what Folders 01–07 measured repeatedly, is that **the scarce skill is measurement**: error analysis, evaluation design, base rates, drift, and knowing when a cheap model beats an LLM. So the curriculum below is ordered by *leverage for a senior backend engineer moving into AI engineering*, not by the order a university would teach it:

- **The 7 MUST items total ~90 hours** at listed durations and estimated reading times, or ~106 hours with a 1.3× practice multiplier on courses (an assumption). They fit in 90 days at **12 h/week**, with 2 h/week reserved for this KB's folders. At 8 h/week only 5 of the 7 fit, so a 90-day goal at 8 h/week means cutting scope, not cramming.
- **Two Ng courses are short and disproportionately valuable.** *Structuring Machine Learning Projects* (DLS Course 3) is **7 hours** (3 + 4, per Coursera) and is the canonical source for error analysis and data mismatch. *Agentic AI* is **9 h 55 m** and covers evals, error analysis and component-level evals for LLM systems.
- **Beginner courses are mostly skippable for this audience.** The full *Mathematics for ML and Data Science* (94 h 29 m) and *Machine Learning Specialization* (94 h 58 m) are excellent for first exposure. A senior engineer working through Folders 01–05 gets the math in context, and should cherry-pick (MLS Course 2, *Advanced Learning Algorithms*: 34 h by its module estimates).
- **Everything is paired with a KB folder**, so each week's course material is immediately exercised against real data (CLINC150, SciFact) with listings you can re-run.

### The backend-engineer bridge

| You already know | Learning-plan equivalent |
|---|---|
| Capacity planning: hours of work vs hours available | **Budget = hours/week × 12.9 weeks**; scope is cut to fit, not stretched |
| A dependency graph for a migration | **Prerequisite order**: measurement → retrieval → models → production |
| Load-testing on production-shaped traffic | **Exercising every course on real data** (the KB listings) |
| Postmortems and runbooks | **Error-analysis spreadsheets on your own projects** |
| Reading the RFC vs the blog post | **Primary sources** (MLY, papers) over summaries |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 *Machine Learning Yearning* (book, A. Ng) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 *Agentic AI* (A. Ng) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 *Machine Learning in Production* (A. Ng) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 *Retrieval Augmented Generation (RAG)* (Z. Hasan) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 *Structuring Machine Learning Projects* (DLS Course 3) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 *Trustworthy Online Controlled Experiments* (Kohavi, Tang, Xu) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 *AI Engineering* (C. Huyen) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 MLS Course 2: *Advanced Learning Algorithms* | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.9 LLM training and post-training courses | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Short courses: guardrails, MCP, coding agents, DSPy | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Free textbooks for depth | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.12 The learning science behind the plan: spacing and retrieval practice | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.13 Full beginner specializations and "for Everyone" courses | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

The "math" of a study plan is simple and worth doing explicitly: **budget = hours/week × weeks − reserved hours**, **effort = listed hours × practice multiplier**, and a priority-ordered fill. Listing §3.1 runs it. Each item below says what it teaches, why it matters for production AI engineering, and which KB folder exercises it.

### 1.1 *Machine Learning Yearning* (book, A. Ng) `[MUST-KNOW: Core AI Engineer Edge]`

**What:** Ng's short, practical book on ML strategy: dev/test sets from the deployment distribution, single-number metrics with satisficing constraints, error analysis by eyeballing and tagging dev-set errors, bias/variance against human-level performance, learning curves, and pipeline (ceiling) analysis. It's free from DeepLearning.AI's resources page, and written in one-to-two-page chapters.

**Why it's first:** every measurement result in this KB is an application of it. 06.1's prevalence trap is "dev/test from the deployment distribution". 06.3's spreadsheet, learning curve and ceiling analysis are its chapters run on real data. 07.1's base-rate failure is its warning about mismatched dev sets. **Effort (assumed):** ~6 h. **KB pairing:** 06.

### 1.2 *Agentic AI* (A. Ng) `[MUST-KNOW: Core AI Engineer Edge]`

**What (listed):** intermediate, 9 h 55 m, 31 video lessons, 7 code examples, 8 graded assignments; updated 2026-10-30. Five modules: agentic workflows and evals; the reflection pattern; tool use (including MCP); **practical tips: evals, error analysis, component-level evaluations, cost and latency optimization**; planning and multi-agent patterns.

**Why:** Module 4 is the LLM-era version of MLY: build quick, measure, error-analyze, fix the biggest bucket, with component-level evals to localize problems. That's the loop behind 06.3 §4.1 and 07.1's cascade design. **KB pairing:** 06, 07.

### 1.3 *Machine Learning in Production* (A. Ng) `[MUST-KNOW: Core AI Engineer Edge]`

**What (listed on Coursera):** intermediate, standalone, three modules (ML lifecycle and deployment; modeling challenges and strategies; data definition and baseline), with module estimates of 3 + 3 + 5 hours. It covers concept drift, error analysis and data-centric AI development.

**Why:** it frames deployment as the start of a monitoring loop, the backbone of 07.2–07.3 (point-in-time features, skew, drift, gated retraining). **KB pairing:** 07.

### 1.4 *Retrieval Augmented Generation (RAG)* (Z. Hasan) `[MUST-KNOW: Core AI Engineer Edge]`

**What (listed):** intermediate, 26 h 3 m, 49 video lessons, 9 code examples, 10 graded assignments; updated 2026-07-23. Modules: RAG overview; information-retrieval and search foundations; vector databases (Weaviate); LLMs and text generation; RAG systems in production. A lab compares semantic search, BM25 and Reciprocal Rank Fusion, and monitoring uses Arize Phoenix.

**Why:** it's the most complete course on the retrieval side of AI engineering. Pair it with 04 (BM25 math, InfoNCE, LambdaMART on SciFact) and 06.2 (metric math, pooling bias) for the parts the course page doesn't cover in depth: retrieval metrics and re-ranking. **KB pairing:** 04, 06.

### 1.5 *Structuring Machine Learning Projects* (DLS Course 3) `[MUST-KNOW: Core AI Engineer Edge]`

**What (listed on Coursera):** 7 hours in two modules (ML Strategy weeks 1 and 2, ~3 h and ~4 h), taught by Andrew Ng with Younes Bensouda Mourri and Kian Katanforoosh. Topics: carrying out error analysis, training and testing on different distributions, bias and variance with mismatched data, addressing data mismatch, transfer and multi-task learning, end-to-end learning.

**Why:** seven hours for the clearest treatment of data mismatch anywhere. It's the exact failure 07.1 measured (validation 3% OOS vs test 18% OOS: −4.3 points). It can be taken without the rest of the specialization. **KB pairing:** 06, 07.1.

### 1.6 *Trustworthy Online Controlled Experiments* (Kohavi, Tang, Xu) `[MUST-KNOW: Core AI Engineer Edge]`

**What:** the standard practitioner book on A/B testing from people who ran experimentation at Microsoft, Amazon, Google and LinkedIn: the OEC, A/A tests, sample-ratio mismatch, variance reduction, pitfalls of peeking and multiple comparisons. **Suggested chapters (assumed effort ~10 h):** 1–3 (motivation, running and analyzing experiments, Twyman's law and trustworthiness) and 17–22 (the statistics, variance estimation and sensitivity, A/A tests, triggering, sample-ratio mismatch, leakage and interference). ⚠ Chapter numbers per the 2020 edition; check your copy.

**Why:** 06.4's measurements (24% false positives from peeking, CUPED cutting the variance to 22%, SRM) are its core lessons, and LLM features need them more, not less, because outputs are non-deterministic and cost is a first-class metric. **KB pairing:** 06.4.

### 1.7 *AI Engineering* (C. Huyen) `[MUST-KNOW: Core AI Engineer Edge]`

**What:** an engineering book on building applications on foundation models: evaluation methodology, prompt engineering, RAG and agents, fine-tuning, dataset engineering, inference optimization, and architecture with user feedback. **Assumed effort:** ~20 h.

**Why:** it's the broadest single map of the production LLM stack, and the right complement to this KB's depth on the ML side. Read it alongside 06 and 07, and treat its evaluation chapters as the LLM-side companion to 06.1–06.3. **KB pairing:** 06, 07.

### 1.8 MLS Course 2: *Advanced Learning Algorithms* `[GOOD-TO-KNOW: Architectural Literacy]`

**What (listed on Coursera):** four modules, neural networks (7 h), neural network training (11 h), advice for applying ML (8 h), decision trees (8 h): 34 h by the module estimates (the page header says ~30 h). It covers softmax, Adam, bias/variance and error analysis for skewed data, random forests and XGBoost.

**Why GOOD, not MUST:** Folders 02 and 05 cover the same ground with production data and from-scratch implementations. Take it if you prefer video-first learning, or to fill gaps found while reading those folders. **KB pairing:** 02, 05.

### 1.9 LLM training and post-training courses `[GOOD-TO-KNOW: Architectural Literacy]`

| Course (DeepLearning.AI catalog, listed durations) | Partner | Length | Why |
|---|---|---|---|
| *Generative AI with Large Language Models* | AWS | 13 h 18 m | Transformer training, PEFT, RLHF: the vocabulary behind 05 and 01.2 |
| *Post-training of LLMs* | University of Washington, NexusFlow | 1 h 26 m | SFT, DPO and online RL in under two hours |
| *Fine-tuning & RL for LLMs: Intro to Post-training* | AMD | 13 h 19 m | The longer, hands-on version |
| *Reinforcement Fine-Tuning LLMs With GRPO* | Predibase | 1 h 53 m | Reward functions for reasoning tasks |
| *Transformers in Practice* | AMD (S. Zhou) | 11 h 1 m | Debugging and deploying transformer models |

For an AI engineer the goal is **architectural literacy**: knowing what SFT, DPO and RL fine-tuning change, what they cost, and when a LoRA adapter (01.2) or a small fine-tuned encoder (05.4) beats prompting a large model. Start with *Post-training of LLMs* (1.4 h). It fits in the 12 h/week plan.

### 1.10 Short courses: guardrails, MCP, coding agents, DSPy `[GOOD-TO-KNOW: Architectural Literacy]`

All are short (under 2 h each, listed): *Safe and reliable AI via guardrails* (GuardrailsAI, 1 h 42 m), *MCP: Build Rich-Context AI Apps with Anthropic* (1 h 58 m), *Claude Code: A Highly Agentic Coding Assistant* (Anthropic, 2 h), *DSPy: Build and Optimize Agentic Apps* (Databricks, 59 m), *Pydantic for LLM Workflows* (1 h 50 m). They're tool-specific, so treat them as a weekend each when you need the tool. They're not foundations. The guardrails course pairs with 02.3's prompt-injection head, which is a reminder that a TF-IDF model beat MiniLM there (0.975 vs 0.938).

### 1.11 Free textbooks for depth `[GOOD-TO-KNOW: Architectural Literacy]`

| Book | Author(s) | Use it for | KB pairing |
|---|---|---|---|
| *Introduction to Information Retrieval* (free online) | Manning, Raghavan, Schütze | Inverted indexes, scoring, evaluation (ch. 1–8) | 04, 06.2 |
| *Understanding Deep Learning* (free PDF) | S. Prince | Clear modern DL theory, transformers | 05 |
| *Dive into Deep Learning* (free, executable) | Zhang, Lipton, Li, Smola | Code-first DL | 05 |
| *Mathematics for Machine Learning* (free PDF) | Deisenroth, Faisal, Ong | Linear algebra and probability refresh | 01 |

These are reference books, not plan items. Look things up when a KB section assumes more than you remember.

### 1.12 The learning science behind the plan: spacing and retrieval practice `[GOOD-TO-KNOW: Architectural Literacy]`

Two well-replicated findings shape the weekly structure:

- **Spacing effect** (Cepeda et al., 2006 meta-analysis): the same study time spread over sessions beats massed study for long-term retention. That's why the plan interleaves two items per week where possible, and keeps 2 h/week for the KB rather than one KB marathon at the end.
- **Testing effect / retrieval practice** (Roediger & Karpicke, 2006): recalling material beats re-reading it. For this KB that means **answering the bar-raiser chains out loud before expanding them**, and re-deriving a listing's key number (06.4's 14,313 users per arm, 07.1's $18.70) before checking the output.

### 1.13 Full beginner specializations and "for Everyone" courses `[SKIP: Academic/Research Only]`

For a senior engineer on this path, the full *Mathematics for ML and Data Science* (94 h 29 m), the rest of the *Machine Learning Specialization*, the remaining four DLS courses (~120 h, TensorFlow-based), and the "for Everyone" courses (*AI for Everyone*, *Generative AI for Everyone*, *AI Prompting for Everyone*) are low-leverage inside a 90-day window. They're tagged SKIP for *this* plan, not for everyone. Take the math specialization if Folder 01 feels hard, and the full DLS after day 90 if you want depth in deep-learning training.

---

## 2. Where It Beats an LLM in Production: What This Curriculum Buys You

The curriculum is chosen to make you the engineer who can **prove** when an LLM isn't needed, and who can make it cheaper and safer when it is. Each MUST item maps to a measured win in this KB:

| Curriculum item | The production skill | Measured in this KB |
|---|---|---|
| MLY, DLS Course 3 | Dev/test from the deployment distribution | Tuning at 3% OOS vs 18% cost 4.3 points (07.1) |
| *Agentic AI*, Module 4 | Error analysis before fixing | 27% of router errors were OOS acceptance, a cheap gate fixes them (06.3) |
| *ML in Production* | Monitoring and retraining loops | Ungated retraining averaged 0.480 vs 0.822 gated (07.3) |
| *RAG* course + 04 | Hybrid retrieval | Hybrid 0.7257 vs BM25 0.6711 nDCG@10, paired CI [+0.030, +0.079] (06.4) |
| Kohavi | Honest online experiments | Peeking: 24% false positives (06.4) |
| Huyen | The LLM stack's cost and evaluation | Cascade at parity, 72.5% cheaper (07.1) |

**Why not just learn from an LLM chat?** A chat assistant is a good tutor for explanations, and a poor substitute for measured practice on real data. The KB listings and course labs are where intuition gets corrected: an MLP head losing to logistic regression (05.2), a cross-encoder *hurting* SciFact (04.3), RMSNorm being slower than LayerNorm without a fused kernel (05.1). Use the assistant to explain; use the listings to check.

---

## 3. Production Code Blueprint

### 3.1 The plan, computed from durations, a budget, and priorities

```python
"""study_plan_scheduler.py - a 90-day plan computed from verified course durations, a weekly hour budget, and priorities.

Durations marked "listed" were read from the DeepLearning.AI / Coursera pages on 2026-10-30 (module estimates summed
where a page gives them). Durations marked "est" are this KB's ASSUMPTIONS (book reading time; the DLS remainder =
listed total - Course 3) - replace them with your own.
  1. Which items fit in 90 days at 8 / 10 / 12 / 15 hours a week (priority order, MUST items first).
  2. A week-by-week schedule for the chosen budget, pairing each item with the KB folder to read alongside it.
"""
import math

DAYS = 90
WEEKS = DAYS / 7
KB_HOURS_PER_WEEK = 2.0                      # est: reading this KB's folder for the week and re-running its listings
PRACTICE = 1.3                               # est: listed course time x 1.3 for labs, notes and re-watching

# (name, provider / author, hours, source, tier, KB folders, why)
ITEMS = [
    ("Machine Learning Yearning (book)", "A. Ng", 6.0, "est", "MUST", "06", "error analysis, bias/variance, dev/test sets"),
    ("Agentic AI", "A. Ng, DeepLearning.AI", 9 + 55 / 60, "listed", "MUST", "06, 07", "evals, error analysis, component evals"),
    ("Machine Learning in Production", "A. Ng, DeepLearning.AI/Coursera", 3 + 3 + 5, "listed", "MUST", "07", "deployment loop, concept drift, data-centric AI"),
    ("Retrieval Augmented Generation (RAG)", "Z. Hasan, DeepLearning.AI", 26 + 3 / 60, "listed", "MUST", "04, 06", "BM25, hybrid search, RAG evaluation"),
    ("DLS Course 3: Structuring ML Projects", "A. Ng et al., Coursera", 3 + 4, "listed", "MUST", "06", "single-number metrics, error analysis, data mismatch"),
    ("Trustworthy Online Controlled Experiments (book, ch. 1-3, 17-22)", "Kohavi, Tang, Xu", 10.0, "est", "MUST", "06", "A/B tests, SRM, variance reduction"),
    ("AI Engineering (book)", "C. Huyen", 20.0, "est", "MUST", "06, 07", "evaluation, RAG, inference cost, feedback loops"),
    ("Post-training of LLMs", "UW / NexusFlow, DeepLearning.AI", 1 + 26 / 60, "listed", "GOOD", "05, 01", "SFT, DPO, online RL"),
    ("Safe and reliable AI via guardrails", "GuardrailsAI, DeepLearning.AI", 1 + 42 / 60, "listed", "GOOD", "02, 07", "guardrail design"),
    ("Generative AI with Large Language Models", "AWS, DeepLearning.AI", 13 + 18 / 60, "listed", "GOOD", "05", "transformer training, PEFT, RLHF"),
    ("MLS Course 2: Advanced Learning Algorithms", "A. Ng et al., Coursera", 7 + 11 + 8 + 8, "listed", "GOOD", "02, 05", "trees, XGBoost, neural nets, advice for applying ML"),
    ("Introduction to Information Retrieval (book, ch. 1-8)", "Manning, Raghavan, Schutze", 15.0, "est", "GOOD", "04", "inverted index, scoring, evaluation"),
    ("Fine-tuning & RL for LLMs: Intro to Post-training", "AMD, DeepLearning.AI", 13 + 19 / 60, "listed", "GOOD", "05, 01", "fine-tuning and RL in depth"),
    ("Deep Learning Specialization (remaining 4 courses)", "A. Ng, DeepLearning.AI", 127.5 - 7, "est", "GOOD", "05", "full DL foundations (TensorFlow)"),
    ("Mathematics for ML and Data Science", "L. Serrano, DeepLearning.AI", 94 + 29 / 60, "listed", "SKIP", "01", "only if linear algebra / probability is rusty"),
]
RANK = {"MUST": 0, "GOOD": 1, "SKIP": 2}


def effort(item):
    name, _, hours, source, *_ = item
    return hours * (PRACTICE if "book" not in name else 1.0)


print(f"== 1. what fits in {DAYS} days ({WEEKS:.1f} weeks), {KB_HOURS_PER_WEEK:.0f} h/week reserved for this KB ==")
print(f"{'h/week':>6} {'budget h':>8} {'items that fit':>14}  {'MUST covered':>12}  {'slack h':>7}")
fits = {}
for per_week in (8, 10, 12, 15):
    budget = per_week * WEEKS - KB_HOURS_PER_WEEK * WEEKS
    used, chosen = 0.0, []
    for it in sorted(ITEMS, key=lambda it: RANK[it[4]]):            # stable: keeps the listed order inside a tier
        if used + effort(it) <= budget:
            chosen.append(it)
            used += effort(it)
    must = [it for it in ITEMS if it[4] == "MUST"]
    fits[per_week] = chosen
    print(f"{per_week:>6} {budget:>8.1f} {len(chosen):>14}  {sum(it in chosen for it in must):>6}/{len(must):<5}  {budget - used:>7.1f}")
print(f"(effort = listed hours x {PRACTICE} for courses, as-is for books; both multipliers are assumptions)")

PER_WEEK = 12
print(f"\n== 2. week-by-week plan at {PER_WEEK} h/week ({PER_WEEK - KB_HOURS_PER_WEEK:.0f} h courses/books + "
      f"{KB_HOURS_PER_WEEK:.0f} h this KB) ==")
cap = PER_WEEK - KB_HOURS_PER_WEEK
queue = [[it, effort(it)] for it in fits[PER_WEEK]]
week, left, rows = 1, cap, []
while queue and week <= math.ceil(WEEKS):
    it, rem = queue[0]
    take = min(rem, left)
    rows.append((week, it[0], take, it[5]))
    queue[0][1] -= take
    left -= take
    if queue[0][1] <= 1e-9:
        queue.pop(0)
    if left <= 1e-9:
        week, left = week + 1, cap
by_week = {}
for w, name, h, kb in rows:
    by_week.setdefault(w, []).append(f"{name} ({h:.1f} h; KB {kb})")
for w in sorted(by_week):
    print(f"week {w:>2}: " + " + ".join(by_week[w]))
done_week = max(by_week)
print(f"finishes in week {done_week} of {math.ceil(WEEKS)}; deferred to after day 90: "
      + ", ".join(it[0] for it in ITEMS if it not in fits[PER_WEEK]))
assert all(it in fits[PER_WEEK] for it in ITEMS if it[4] == "MUST") and done_week <= math.ceil(WEEKS)
assert not all(it in fits[8] for it in ITEMS if it[4] == "MUST")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. what fits in 90 days (12.9 weeks), 2 h/week reserved for this KB ==
h/week budget h items that fit  MUST covered  slack h
     8     77.1              5       5/7          1.0
    10    102.9              8       6/7         12.6
    12    128.6             10       7/7          1.1
    15    167.1             12       7/7          7.3
(effort = listed hours x 1.3 for courses, as-is for books; both multipliers are assumptions)

== 2. week-by-week plan at 12 h/week (10 h courses/books + 2 h this KB) ==
week  1: Machine Learning Yearning (book) (6.0 h; KB 06) + Agentic AI (4.0 h; KB 06, 07)
week  2: Agentic AI (8.9 h; KB 06, 07) + Machine Learning in Production (1.1 h; KB 07)
week  3: Machine Learning in Production (10.0 h; KB 07)
week  4: Machine Learning in Production (3.2 h; KB 07) + Retrieval Augmented Generation (RAG) (6.8 h; KB 04, 06)
week  5: Retrieval Augmented Generation (RAG) (10.0 h; KB 04, 06)
week  6: Retrieval Augmented Generation (RAG) (10.0 h; KB 04, 06)
week  7: Retrieval Augmented Generation (RAG) (7.1 h; KB 04, 06) + DLS Course 3: Structuring ML Projects (2.9 h; KB 06)
week  8: DLS Course 3: Structuring ML Projects (6.2 h; KB 06) + Trustworthy Online Controlled Experiments (book, ch. 1-3, 17-22) (3.8 h; KB 06)
week  9: Trustworthy Online Controlled Experiments (book, ch. 1-3, 17-22) (6.2 h; KB 06) + AI Engineering (book) (3.8 h; KB 06, 07)
week 10: AI Engineering (book) (10.0 h; KB 06, 07)
week 11: AI Engineering (book) (6.2 h; KB 06, 07) + Post-training of LLMs (1.9 h; KB 05, 01) + Safe and reliable AI via guardrails (2.0 h; KB 02, 07)
week 12: Safe and reliable AI via guardrails (0.2 h; KB 02, 07) + Generative AI with Large Language Models (9.8 h; KB 05)
week 13: Generative AI with Large Language Models (7.5 h; KB 05)
finishes in week 13 of 13; deferred to after day 90: MLS Course 2: Advanced Learning Algorithms, Introduction to Information Retrieval (book, ch. 1-8), Fine-tuning & RL for LLMs: Intro to Post-training, Deep Learning Specialization (remaining 4 courses), Mathematics for ML and Data Science

ALL ASSERTIONS PASSED
```

**Reading the output.** At 12 h/week everything MUST fits, with 1.1 h of slack, so there's no room for slippage. Either start at 13–14 h/week or accept that *Generative AI with LLMs* slides past day 90. At 10 h/week, one MUST item doesn't fit; the listing tells you which, so cut it deliberately rather than discovering it in week 11. Change `PRACTICE`, `KB_HOURS_PER_WEEK` or the book estimates to match how you actually work, and re-run.

### 3.2 The weekly cadence that makes it stick

Each week of the plan has the same shape:

```text
Mon–Thu  course / book time (the plan's hours for that week)
Fri      KB folder paired with the week: read one file, re-run its listings, change ONE assumption and predict the
         new output before running it (retrieval practice, §1.12)
Sat      answer 3 bar-raiser chains from that folder OUT LOUD before expanding them; write the miss in a log
Sun      off (spacing)
```

### 3.3 The 90-day map at 12 h/week, with deliverables

| Weeks | Focus | KB folder | Deliverable (your own project or work data) |
|---|---|---|---|
| 1–2 | MLY + *Agentic AI* | 06.3 | An error-analysis spreadsheet on 100 real failures of a system you own |
| 2–4 | *ML in Production* | 07.2, 07.3 | A point-in-time training set and a drift dashboard with a calibrated null |
| 4–7 | *RAG* course | 04, 06.2 | A retrieval eval: Recall@k at your context budget, zero-recall rate, paired bootstrap of two retrievers |
| 7–8 | DLS Course 3 | 06.1, 07.1 | A threshold chosen at deployment prevalence with a margin, plus a written metric spec |
| 8–9 | Kohavi | 06.4 | An experiment plan with a sample-size calculation, SRM check and guardrails |
| 9–11 | Huyen | 07.1 | A cascade design doc for one LLM call path, with a measured deferral share and cost model |
| 11–13 | Post-training, guardrails, GenAI with LLMs | 05, 02.3 | A small fine-tuned or head-based replacement for one LLM classification call, gated |

The deliverables are the point. Each one is an artifact you can show in a design review or describe in an interview (08.3) with your own numbers.

---

## 4. The Andrew Ng Lens: Learn, Build, Repeat

### 4.1 Foundations, projects, career

Ng's *How to Build Your Career in AI* (DeepLearning.AI, free) frames growth as three repeating activities: **learning foundational skills, working on projects, and finding the right job**, with T-shaped knowledge (broad across AI, deep in an area). The 90-day plan follows that shape: the courses are the learning, the §3.3 deliverables are the projects, and 08.2–08.3 are about the job.

### 4.2 Projects should be small, measured, and iterated

Ng's guidance on projects matches his guidance on models: start small, measure, iterate. A 90-day plan with seven small, measured deliverables beats one ambitious project that never ships. Each deliverable above has a numeric outcome (a recall, a cost, a deferral share) because a number is what makes a project legible to a reviewer.

### 4.3 Error analysis on your own learning

Apply the spreadsheet to yourself. Log every bar-raiser chain you miss, tag it (math, statistics, systems, product judgement), and count every two weeks. Spend the next week's KB hours on the biggest bucket. That's the same loop, applied to a different system.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Week 6 and 30% behind | Plan assumed listed video time | No practice multiplier | Re-run the planner with your measured multiplier; cut scope | Track actual hours from week 1 |
| F2 | Finished courses, can't answer design questions | Watched, didn't build | No deliverables | The §3.3 artifact per phase | No phase is "done" without its artifact |
| F3 | Spent the quarter on math refreshers | Beginner specializations first | Ordering by textbook order, not leverage | Start with measurement (MLY, DLS C3, *Agentic AI*) | Plan ordered by production leverage |
| F4 | Knowledge fades by month 3 | Massed study at the end | No spacing or retrieval practice | Weekly KB slot, chains answered out loud | Fixed weekly cadence (§3.2) |
| F5 | Tool courses but no foundations | Many short framework courses | Chasing tools | Foundations first; tools when needed | Tool courses are GOOD, never MUST |
| F6 | Plan cites stale course content | A course was retired or renamed | Catalog churn | Re-verify the catalog quarterly | Date-stamp the plan's sources (this file: 2026-10-30) |
| F7 | Can quote frameworks, not numbers | No exposure to real data | Toy examples only | Re-run KB listings, change one assumption, predict | Every week touches real data |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "How did you ramp up on ML as a backend engineer?"</b></summary>

**Initial Prompt.** A Staff AI engineering interview, career section.

**L5 Answer.** "I took Andrew Ng's courses and built some projects."

**Why L5 Fails in Production.** It's unfalsifiable and says nothing about judgement: which courses, why that order, what was built, and what was learned from it.

**L7 Principal Defense.** "I ordered it by production leverage. Measurement first: *Machine Learning Yearning*, the 7-hour *Structuring ML Projects*, and *Agentic AI*'s evals and error-analysis module, because the scarce skill on AI teams is knowing what's wrong. Then retrieval (the *RAG* course plus BM25 and LTR math), then experiments (Kohavi), then the LLM stack (Huyen). Each phase ended with an artifact on real data. For example, a cascade where tuning the gate on a 3%-OOS validation split lost 4.3 points on 18%-OOS traffic. Re-weighting and a margin got parity at 72.5% lower cost. That mistake taught me more than any lecture."

**Bar-Raiser Follow-ups.**
- *"What did you skip, and why?"* The beginner math specialization: I learned the math in context, and only went back when a derivation stalled me.
- *"How do you stay current?"* The Batch weekly, a paper a week tied to a live problem, and re-verifying vendor docs before any design decision.

</details>

<details><summary><b>Q2 · "How would you upskill a team of backend engineers onto AI engineering in one quarter?"</b></summary>

**Initial Prompt.** A Staff engineer is asked to lead an internal transition.

**L5 Answer.** "Give everyone a Coursera license and a few weeks to complete the ML Specialization."

**Why L5 Fails in Production.** 95 hours of beginner material in a few weeks, no connection to the team's systems, and no measurable outcome.

**L7 Principal Defense.** "Twelve weeks at ~12 h/week, ordered by leverage: measurement, retrieval, experiments, the LLM stack (this file's plan). Every phase ends with a deliverable *on our own systems*: an error-analysis spreadsheet on real failures, a retrieval eval with our context budget, an experiment plan with a power calculation, a cascade design for one LLM call path. Weekly: one paired session where someone presents their numbers and the group tries to break them. The success metric isn't course completion. It's whether, by week 12, each engineer has shipped one measured improvement (lower cost, higher recall, fewer incidents)."

**Bar-Raiser Follow-ups.**
- *"What if people fall behind?"* Cut scope per person with the planner (the MUST list shrinks at 8 h/week), not the deliverables.
- *"How do you measure the programme?"* Before/after on the team's own metrics: eval coverage, cost per request, incident rate from model changes.

</details>

<details><summary><b>Q3 · "Is the Deep Learning Specialization worth it for an AI engineer today?"</b></summary>

**Initial Prompt.** A mentee asks whether to spend ~127 hours on it.

**L5 Answer.** "Yes, it's the gold standard."

**Why L5 Fails in Production.** It's excellent, and mostly about training networks, while most AI engineering work is evaluating, retrieving, routing and serving around pre-trained models. Its highest-leverage course is 7 hours long.

**L7 Principal Defense.** "Take Course 3, *Structuring Machine Learning Projects*, now: 7 hours, error analysis and data mismatch, directly applicable to LLM systems. Defer the rest (~120 hours, TensorFlow-based) until you need training depth, for example to fine-tune encoders or debug training runs. For transformer internals, 05's from-weights MiniLM forward pass and *Understanding Deep Learning* get you further per hour."

**Bar-Raiser Follow-ups.**
- *"And the ML Specialization?"* Course 2 (*Advanced Learning Algorithms*, ~34 h) if you prefer video; otherwise Folders 02 and 05 cover it with production data.

</details>

<details><summary><b>Q4 · "What's the one Andrew Ng idea you use most?"</b></summary>

**Initial Prompt.** A culture-fit question with technical depth expected.

**L5 Answer.** "Data-centric AI: data matters more than models."

**Why L5 Fails in Production.** It's a slogan without a procedure. The interviewer wants to hear what you actually *do*.

**L7 Principal Defense.** "Error analysis: pull ~100 failures, tag them, count, and quote each bucket's share as the ceiling for fixing it. On a CLINC router, auto-tagging 171 validation errors showed 27% were out-of-scope queries accepted as intents. That's fixable with a cheap similarity gate. The 'very short query' bucket the team suspected was only 5%. The 28% residual was the reading list. Ceiling analysis is the pipeline version: on BM25 → MiniLM retrieval, a perfect re-ranker was worth +0.21 nDCG and perfect recall only +0.04, which decided the roadmap."

**Bar-Raiser Follow-ups.**
- *"And for LLM agents?"* Component-level evals. Ng's *Agentic AI* course covers exactly this: oracle-swap a component, measure end to end.

</details>

<details><summary><b>Q5 · "How do you evaluate whether a course or book is worth your time?"</b></summary>

**Initial Prompt.** A question about self-directed learning.

**L5 Answer.** "I read the reviews and pick the highest-rated ones."

**Why L5 Fails in Production.** Ratings measure enjoyment for the average learner, not marginal value for *you*, given what you already know.

**L7 Principal Defense.** "The same way I'd evaluate a model: against a target. I write down which skills I'm missing (from my own error log on interview chains or design reviews), check each candidate's syllabus against that list, and estimate new-learning hours: total hours × (1 − overlap with what I know). A 7-hour course that fills my biggest bucket beats a 95-hour one that's 70% review. Then I time-box it and require an artifact at the end."

**Bar-Raiser Follow-ups.**
- *"Example of a course you dropped?"* A long beginner course where the first two modules were all review. I dropped it for the 7-hour strategy course.

</details>

<details><summary><b>Q6 · "You have 90 days and 8 hours a week. What do you cut?"</b></summary>

**Initial Prompt.** A constraint-driven follow-up.

**L5 Answer.** "I'd just study harder on weekends."

**Why L5 Fails in Production.** It's a plan that ignores its own capacity: at 8 h/week the budget is ~77 h after the KB slot, and the MUST list needs ~106 h with practice time.

**L7 Principal Defense.** "The planner says 5 of 7 MUST items fit at 8 h/week. I'd keep the measurement core (MLY, DLS Course 3, *Agentic AI*, *ML in Production*) and the retrieval course, and defer the two books (Kohavi and Huyen) to targeted chapters: SRM and variance reduction from Kohavi, the evaluation chapters from Huyen. Each deferral is a conscious trade: I'd note which interview topics or design decisions I'm weaker on as a result, so I don't over-claim."

**Bar-Raiser Follow-ups.**
- *"Which single item would you keep at 4 h/week?"* *Structuring ML Projects* plus MLY: ~13 hours, the highest leverage per hour.

</details>

<details><summary><b>Q7 · "Courses teach toy problems. How do you make sure you can do it on real systems?"</b></summary>

**Initial Prompt.** A skeptical interviewer.

**L5 Answer.** "I do the labs carefully."

**Why L5 Fails in Production.** Labs are designed to work. Production data has prevalence shifts, label noise, leakage and skew, which is exactly where lab-trained intuition breaks.

**L7 Principal Defense.** "I re-run every idea on real data with adversarial checks. For example: does the threshold transfer from validation to test? (No: 3% vs 18% OOS cost 4.3 points.) Does the offline metric survive a point-in-time join? (A naive join gave 0.912 AUC vs 0.653 served.) Does the drift monitor catch a broken model? (Not when its reference resets to that model.) Each phase of my plan ends with an artifact on my own system's data, and I write down what surprised me. The surprises are the learning."

**Bar-Raiser Follow-ups.**
- *"What's the most common surprise?"* That the cheap baseline is closer to the LLM than expected, and that evaluation design moves the number more than model choice.

</details>

<details><summary><b>Q8 · "How do you keep a learning plan from going stale in a field this fast?"</b></summary>

**Initial Prompt.** Courses and certifications change every quarter.

**L5 Answer.** "Follow the newest courses as they come out."

**Why L5 Fails in Production.** Chasing new tool courses produces breadth without foundations, and the foundations (measurement, retrieval, statistics) don't go stale.

**L7 Principal Defense.** "Split the plan into a stable core and a volatile shell. The core is error analysis, metrics, retrieval math, experiments and drift. It changes slowly, and this KB and MLY cover it. The shell is tools, frameworks, vendor APIs and certifications. It changes quarterly, so I date-stamp it (this plan's sources were verified 2026-10-30) and re-verify before acting. Example: AWS retired the ML Specialty exam (last date 2026-03-31) and moved its ML Engineer Associate exam to a new version. A plan written a year earlier would point people at a dead exam."

**Bar-Raiser Follow-ups.**
- *"How often do you re-verify?"* Quarterly for the shell, and always before recommending something to someone else.

</details>

---

## 7. Invariants Checklist

- [ ] The plan is computed from durations, a weekly budget and priorities (listing §3.1); assumptions (practice multiplier, reading hours) are explicit and re-measured after week 2.
- [ ] Measurement items (MLY, DLS Course 3, *Agentic AI*) come first.
- [ ] Every phase ends with a deliverable on real data from a system you own or can access.
- [ ] Two hours a week are reserved for the paired KB folder: re-run listings, change one assumption, predict before running.
- [ ] Bar-raiser chains are answered out loud before reading the defenses; misses are logged and tagged.
- [ ] Course and certification facts are date-stamped and re-verified quarterly.
- [ ] Beginner specializations and tool courses are taken deliberately, not by default.

---

## 8. References

1. A. Ng, *Machine Learning Yearning* and *How to Build Your Career in AI* (free ebooks). https://www.deeplearning.ai/resources/
2. DeepLearning.AI, *Agentic AI* (A. Ng). https://www.deeplearning.ai/courses/agentic-ai
3. DeepLearning.AI / Coursera, *Machine Learning in Production* (A. Ng). https://www.coursera.org/learn/introduction-to-machine-learning-in-production
4. DeepLearning.AI, *Retrieval Augmented Generation (RAG)* (Z. Hasan). https://www.deeplearning.ai/courses/retrieval-augmented-generation-rag/
5. Coursera, *Structuring Machine Learning Projects* (Deep Learning Specialization, Course 3). https://www.coursera.org/learn/machine-learning-projects
6. Coursera, *Advanced Learning Algorithms* (Machine Learning Specialization, Course 2). https://www.coursera.org/learn/advanced-learning-algorithms
7. DeepLearning.AI, *Machine Learning Specialization*. https://www.deeplearning.ai/specializations/machine-learning
8. DeepLearning.AI, *Deep Learning Specialization*. https://www.deeplearning.ai/courses/deep-learning-specialization/
9. DeepLearning.AI course catalog (short courses and partner courses listed in §1.9–§1.10). https://www.deeplearning.ai/courses
10. R. Kohavi, D. Tang, Y. Xu, *Trustworthy Online Controlled Experiments*, Cambridge University Press, 2020. https://doi.org/10.1017/9781108653985
11. C. Huyen, *AI Engineering: Building Applications with Foundation Models*, O'Reilly, 2025. https://www.oreilly.com/library/view/ai-engineering/9781098166298/
12. C. Manning, P. Raghavan, H. Schütze, *Introduction to Information Retrieval*, Cambridge University Press, 2008 (free online). https://nlp.stanford.edu/IR-book/ (publisher record: https://doi.org/10.1017/CBO9780511809071)
13. S. Prince, *Understanding Deep Learning*, MIT Press, 2023 (free PDF). https://udlbook.github.io/udlbook/
14. A. Zhang, Z. Lipton, M. Li, A. Smola, *Dive into Deep Learning*. https://d2l.ai/
15. M. Deisenroth, A. Faisal, C. Ong, *Mathematics for Machine Learning*, Cambridge University Press, 2020 (free PDF). https://mml-book.github.io/
16. N. Cepeda, H. Pashler, E. Vul, J. Wixted, D. Rohrer, *Distributed Practice in Verbal Recall Tasks: A Review and Quantitative Synthesis*, Psychological Bulletin 132(3), 2006. https://doi.org/10.1037/0033-2909.132.3.354
17. H. Roediger, J. Karpicke, *Test-Enhanced Learning: Taking Memory Tests Improves Long-Term Retention*, Psychological Science 17(3), 2006. https://doi.org/10.1111/j.1467-9280.2006.01693.x
