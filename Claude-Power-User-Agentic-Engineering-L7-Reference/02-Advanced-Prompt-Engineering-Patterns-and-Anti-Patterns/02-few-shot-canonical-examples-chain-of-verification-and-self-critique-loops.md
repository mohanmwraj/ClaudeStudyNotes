# Few-Shot Canonical Examples, Chain-of-Verification and Self-Critique Loops

> **Folder 02 · File 2 of 3** · verified 2026-10-30
> **Listings:** `few_shot_selector.py` (schema-valid, diverse, recency-aware example selection) · `CritiqueLoopDynamics.java` (when critique loops help or hurt, in closed form; a refine harness that enforces the invariants)

---

## 0. Orientation

Two of the most reused prompting techniques are also the most misunderstood:

- **Few-shot examples.** People treat them as teaching the task. The research says they mostly teach **format and the label prior**.
- **"Review and improve your answer" loops.** People treat them as free accuracy. The research and the algebra say they help only under conditions you can state, and can make a strong model *worse*.

This file explains both mechanically, then turns them into tools: an example selector (L1) and a loop model plus harness (L2).

### 0.1 The twelve rules

1. **Examples teach format and label distribution first.** Replacing demonstration labels with random ones barely hurts in-context accuracy on many tasks. [research: Min et al. 2022]
2. **So validate every example's output against the schema.** One malformed example teaches malformed output. L1 rejected 2 of 18. [measured]
3. **Balance labels.** Models over-predict labels that are frequent in the demonstrations, and the label of the final example. [research: Zhao et al. 2021]
4. **Pick for relevance *and* diversity.** Naive similarity put 4 of 5 examples on one label; MMR covered 5 labels. [measured: L1]
5. **Include an abstention example** (a "no finding" case). Without one, the model learns that every input has a finding. [measured + inference]
6. **Use 3–5 examples, wrapped in `<example>` tags inside `<examples>`.** [doc]
7. **Keep the canonical set static and cached. Dynamic, retrieved examples go after the breakpoint.** [doc + Folder 01]
8. **With thinking on, examples still work.** Show the problem, the method and the answer. [doc]
9. **Ungated self-critique converges to p\* = t·r / (f·b + t·r).** If your model starts above p\*, critique pulls it *down*. [measured: L2]
10. **Gate every revision on an external verifier** (tests, a schema, a checker). Only then does a loop monotonically add correct answers, up to the verifier's blind spots. [measured: L2]
11. **Answer verification questions without the draft in context** (factored chain-of-verification), so the verifier can't inherit the draft's errors. [research: Dhuliawala et al. 2023]
12. **Judges have biases (position, verbosity, self-preference).** Use fresh contexts, swapped orderings and evidence requirements. [research: Zheng et al. 2023; doc]

---

## 1. First principles

### 1.1 What in-context examples actually teach [research, doc]

Brown et al. (2020) established few-shot prompting. Later work showed *what* transfers from the demonstrations:

- **Min et al. (2022).** Across classification and multiple-choice tasks, replacing the gold labels in demonstrations with *random* labels caused only a small drop. What mattered was the **label space**, the **input distribution** and the **format**. Demonstrations mostly tell the model *what kind of answer is expected and in what shape*.
- **Zhao et al. (2021).** Few-shot predictions are biased toward:
  - labels that are frequent among the examples (**majority-label bias**)
  - the label of the *last* example (**recency bias**)
  - tokens common in pre-training (**common-token bias**)

  Accuracy swung widely with example order alone.

Anthropic's guidance matches this. Examples "are one of the most reliable ways to steer Claude's output format, tone, and structure". Make them relevant, diverse and structured ("wrap examples in `<example>` tags"), and "include 3–5 examples for best results" [doc]. With thinking on, "worked examples in your prompt shape how Claude approaches similar problems in its own thinking blocks. Present each example as a problem, the method to apply, and the expected answer" [doc].

**Corollary.** Your examples are a **training signal for format and prior**, injected at inference time. Treat them like training data: validate, balance and deduplicate them.

### 1.2 Canonical examples: one per decision boundary

A canonical set for a classifier-like task, such as code-review findings or incident severity, has:

1. **One example per label that matters**, chosen to sit near the decision boundary rather than at the easy centre.
2. **Contrastive near-misses.** An input that *looks* like a positive but isn't. L1's MMR set picked a batched `findByOrderIdIn` load as the NO_FINDING example. It is lexically close to the N+1 query, but correct, so it teaches the boundary, not the keyword.
3. **An abstention example.** It teaches that "nothing to flag" is a legal output.
4. **Schema-valid outputs**, byte-for-byte the shape you will parse.
5. **An ordering that doesn't end on the majority label.**

### 1.3 When examples overpower instructions

Examples are high-salience exact patterns (Folder 01 §1.4, induction heads), so the model copies their surface: field names, length, tone, even specific values.

- If your examples always contain a `severity: high` finding, the model over-reports `high`.
- If they use `OrderService`, unrelated code reviews start mentioning orders.

Mitigations:
- Tag them illustrative: "Examples show format only; do not reuse names or values".
- Vary the irrelevant surface (domains, identifiers).
- Keep examples shorter than the real inputs, so they don't anchor length.

### 1.4 Static canonical sets vs. retrieved examples: the cache trade-off [doc, inference]

Dynamic retrieval (pick the k most similar examples per request) improves relevance. But it makes the example block unique per request, and anything after it uncacheable (Folder 01 file 01 §1.2). The split that keeps both:

- **A static canonical set** (3–5 boundary examples) in the system prompt, cached.
- **0–2 retrieved examples** in the final user turn, after the last breakpoint.

L1 implements the selection rules for either: schema validation, MMR, abstention, and recency-aware ordering.

### 1.5 Chain-of-Verification: why the verifier must not see the draft [research]

Dhuliawala et al. (2023) proposed **Chain-of-Verification (CoVe)**:

1. Draft a response.
2. Plan verification questions about its factual claims.
3. Answer those questions independently.
4. Produce a revised response.

The variant that works best is **factored**: each verification question is answered in a context that **does not contain the draft**. When the draft is visible, the model tends to *repeat its own mistakes* while "checking" them. Separate contexts break that conditioning.

For engineering work, the analogue is concrete:
- "What is the retry cap in ADR-0042?" is answered from the ADR, not from the draft that claimed 10 s.
- "Does `OrderService.create` hold a transaction across `fraud.check`?" is answered by reading the code, not by re-reading the agent's own summary.

L2's harness makes the factored property a **type-level guarantee**. `IndependentAnswerer.answer(String question)` has no parameter through which the draft could be passed.

### 1.6 The algebra of self-critique [measured: L2; research]

Model a single answer as correct or wrong. Each round, a critic reviews it, then a reviser acts:

| Current state | Critic flags it with prob. | Reviser then… |
|---|---|---|
| correct | **f** (false alarm) | breaks it with prob. **b** |
| wrong | **t** (detection) | fixes it with prob. **r** |

Accuracy evolves as

```
p_{k+1} = p_k · (1 − f·b) + (1 − p_k) · t·r          fixed point   p* = t·r / (f·b + t·r)
```

Ungated self-critique converges to p\* from *any* start. With L2's illustrative rates (f = 0.25, b = 0.40, t = 0.60, r = 0.50), p\* = **0.750**:

- a **strong** model starting at 0.80 drifts **down** to 0.7565 after 4 rounds (Monte Carlo 0.7563)
- a **weak** model starting at 0.50 drifts **up** to 0.7176

Self-critique helps a model at p₀ only if **f·b < t·r·(1 − p₀)/p₀**. For p₀ = 0.80 that threshold is 0.075, and here f·b = 0.100.

This reconciles two literatures:
- Huang et al. (2023) found LLMs "cannot self-correct reasoning yet" without external feedback: performance often fell after self-correction.
- Madaan et al. (2023, Self-Refine) reported gains on tasks where feedback was informative.

Both are the same equation at different (f, b, t, r).

**The verifier gate changes the dynamics.** Revise only when an external check (tests) fails, and accept a revision only if the check then passes. Correct answers are never touched:

```
p_{k+1} = p_k + (1 − p_k) · (1 − m) · r       (m = probability the tests pass a wrong answer)
```

The gated curve is monotone non-decreasing. With m = 0.20 it climbs 0.80 → 0.9299 in 4 rounds. Its limit is **0.9333**, not 1: wrong answers that the tests *miss* are frozen forever. **The loop is only as good as the verifier's coverage**, which is the argument for strong tests, contract checkers (file 01 L2) and fresh-context reviewers.

Where current Claude models sit in this table is model- and task-specific:
- Anthropic's docs say "Before you finish, verify your answer against [test criteria]" "catches errors reliably, especially for coding and math".
- They also say Opus 5 verifies its own work well unprompted, and extra verification instructions there cause over-verification [doc].

The algebra tells you what to measure (f, b, t, r on your tasks), not what the numbers are.

### 1.7 Fresh-context verifiers and judge bias [doc, research]

- **Fresh context beats self-critique.** Anthropic's long-running-agent guidance says "separate fresh-context verifier sub-agents tend to outperform self-critique" [doc]. In Claude Code that is a reviewer **subagent** with its own context (Folder 04), or `/review` run in a new session.
- **LLM-as-judge has measurable biases.** Zheng et al. (2023, MT-Bench) documented position bias (preferring the first or second answer), verbosity bias (preferring longer answers) and self-enhancement bias (preferring one's own outputs). Mitigations:
  - **Swap positions** and require agreement across both orders.
  - **Score against a rubric** with evidence quotes.
  - **Cap length** or score it separately.
  - **Use a different context or model** from the generator.
- **Require evidence.** A judge that must quote the failing line or the spec clause is easier to audit and harder to talk into agreement (file 03, sycophancy).

### 1.8 Loop engineering

A production refine loop has the properties L2's harness encodes:

1. **Bounded rounds.** If no candidate passes after N rounds, end with an *explicit failure*, never silently accept the last candidate.
2. **Verifier-gated acceptance.** Never accept a candidate that fails the check.
3. **Factored verification.** Verification questions are answered without the draft.
4. **A trace.** Log every candidate, verdict and question, so failures can be debugged and turned into eval cases.
5. **Cache-aware calls.** Every round reuses the same static prefix, and only the tail changes (Folder 01).

In Claude Code, the production version of the gate is a **Stop hook** that runs the test suite and blocks the turn from ending while tests fail (Folder 05). That makes the verifier deterministic and impossible to skip.

---

## 2. Practice

### 2.1 A canonical example block (code-review findings)

```xml
<examples>
<!-- Examples show FORMAT and decision boundaries only. Do not reuse names, values, or severities from them. -->
<example index="1">
<diff>List<OrderLine> lines = lineRepo.findByOrderIdIn(orderIds); Map<Long, List<OrderLine>> byOrder = group(lines);</diff>
<review>{"category": "NO_FINDING", "comment": "Batched load and in-memory grouping; nothing to flag.", "severity": "none"}</review>
</example>
<example index="2">
<diff>orders.forEach(o -> o.setCustomer(customerRepo.findById(o.getCustomerId()).orElseThrow()));</diff>
<review>{"category": "N_PLUS_ONE", "comment": "Per-row findById in a loop; batch-load customers by id set.", "severity": "high"}</review>
</example>
<!-- ... one per label that matters, contrastive where possible; never end on the majority label ... -->
</examples>
```

### 2.2 Factored chain-of-verification as four calls

```text
Call 1 (draft)        <task/> -> draft answer
Call 2 (plan)         "List the factual claims in this draft that could be wrong, each as a standalone question
                       answerable from the repository or the documents. Output JSON: {questions: [...]}"
Call 3..n (verify)    ONE question per call, in a FRESH context with only the sources (files/docs) and the question.
                       Never include the draft.
Call n+1 (revise)     <draft/> + <verification_answers/> -> "Revise the draft so every claim agrees with the
                       verification answers; mark any claim you could not verify."
Gate                  run tests / checkers; accept only if they pass; else repeat at most N times, then fail loudly.
```

In Claude Code, run the verify calls as a subagent with read-only tools (Folder 04). Its context is separate by construction.

### 2.3 A rubric judge with position swap

```xml
<rubric>
1. Correctness against <spec_invariants> (quote the violated invariant id, or "none").
2. Edge cases covered (list EC ids with the test that covers each).
3. Unrequested changes (list files/lines outside the requested scope).
</rubric>
<candidate_a>{{A}}</candidate_a>
<candidate_b>{{B}}</candidate_b>
Score each candidate per rubric item with evidence (file:line). Length is not a criterion.
Output JSON: {"a": {...}, "b": {...}, "preferred": "a"|"b"|"tie"}.
```

Run it twice with A and B swapped, and accept a preference only if both orders agree.

### 2.4 The minimal verification instruction, per model

| Model | What to put in the prompt |
|---|---|
| Opus 5.5, Fable 5.1, Sonnet 5.5 | A `<verification>` block with concrete checks (Folder 01 file 02 §2.1), gated by tests in the harness |
| Opus 5 | **No** verification boilerplate; it verifies unprompted, and extra instructions cause over-verification [doc]. Keep the external gate. |
| Haiku 5.5 | Concrete, checkable criteria, and an external validator on every output (structured outputs plus a schema) |

---

## 3. Verified listings

### L1 · `few_shot_selector.py`: choose examples like training data

**What it shows.** From an 18-example pool of Java review findings:
- 2 examples are rejected for breaking the output schema.
- Naive top-5 similarity collapses onto the query's look-alike label (4 of 5 N_PLUS_ONE).
- MMR (λ = 0.55) plus a required abstention example plus recency-aware ordering yields 5 distinct labels, including a contrastive NO_FINDING example.
- The rendered `<examples>` block is printed.

**What it does not show.** Accuracy gains on Claude. That needs an eval on your own labelled set.

Run: `python few_shot_selector.py`.

```python
"""few_shot_selector.py - choose canonical few-shot examples the way the research says they work.

Few-shot examples teach FORMAT and the LABEL PRIOR more than they teach the task (Min et al. 2022; Zhao et
al. 2021: majority-label and recency bias). So a selector must (1) reject examples whose output breaks the
schema - a malformed example teaches malformed output; (2) trade relevance against diversity (MMR) so the
set does not collapse onto one label; (3) include an abstention ("no finding") example; and (4) not end
on the majority label. Pool: 18 Java code-review examples; query: a diff with a repository call in a loop.

Run: python few_shot_selector.py   (stdlib only; prints ALL ASSERTIONS PASSED)
"""
import json
import math
import re
from collections import Counter

SCHEMA_KEYS = {"category", "severity", "comment"}
CATEGORIES = {"N_PLUS_ONE", "MISSING_TIMEOUT", "TX_SPANS_IO", "RACE_CONDITION", "RESOURCE_LEAK", "NO_FINDING"}


def ex(code, category, severity, comment):
    return {"input": code, "output": {"category": category, "severity": severity, "comment": comment}}


POOL = [
    ex("for (Order o : orders) { o.setLines(lineRepo.findByOrderId(o.getId())); }", "N_PLUS_ONE", "high",
       "One query per order; fetch lines with a single IN query or a join fetch."),
    ex("orders.forEach(o -> o.setCustomer(customerRepo.findById(o.getCustomerId()).orElseThrow()));", "N_PLUS_ONE", "high",
       "Per-row findById in a loop; batch-load customers by id set."),
    ex("for (Order o : orderRepo.findAll()) { total += lineRepo.findByOrderId(o.getId()).size(); }", "N_PLUS_ONE", "high",
       "findAll plus a query per order; aggregate in SQL."),
    ex("for (Long id : ids) { results.add(orderRepo.findById(id).orElseThrow()); }", "N_PLUS_ONE", "medium",
       "Use findAllById(ids) - one round trip."),
    ex("for (Order o : orders) { o.getLines().size(); } // lazy collection touched per order", "N_PLUS_ONE", "medium",
       "Lazy initialization per entity; use an entity graph or a fetch join."),
    ex("RestClient client = RestClient.create(); client.get().uri(fraudUrl).retrieve().body(String.class);", "MISSING_TIMEOUT", "high",
       "No connect/read timeout; a slow fraud service stalls request threads."),
    ex("HttpClient.newHttpClient().send(HttpRequest.newBuilder(uri).build(), BodyHandlers.ofString());", "MISSING_TIMEOUT", "high",
       "JDK HttpRequest has no timeout unless set; add .timeout(Duration.ofSeconds(2))."),
    ex("@Transactional public void pay(Order o) { repo.save(o); kafkaTemplate.send(\"payments\", o.id()); }", "TX_SPANS_IO", "high",
       "Kafka send inside the transaction; use a transactional outbox."),
    ex("@Transactional public void ship(Order o) { repo.lock(o.id()); carrierClient.book(o); repo.markShipped(o.id()); }", "TX_SPANS_IO", "high",
       "Row lock held across an HTTP call; book outside the transaction or via a saga step."),
    ex("if (!repo.existsByKey(key)) { repo.save(new Payment(key)); }", "RACE_CONDITION", "high",
       "Check-then-insert races under retries; rely on a unique index and handle the conflict."),
    ex("private int counter; public void hit() { counter++; }  // called from request threads", "RACE_CONDITION", "medium",
       "Unsynchronized increment; use AtomicInteger or LongAdder."),
    ex("lockA.lock(); lockB.lock();  // elsewhere: lockB.lock(); lockA.lock();", "RACE_CONDITION", "high",
       "Inconsistent lock order can deadlock; acquire in a global order."),
    ex("Connection c = dataSource.getConnection(); PreparedStatement ps = c.prepareStatement(sql); ps.executeQuery();", "RESOURCE_LEAK", "high",
       "Connection and statement never closed; use try-with-resources."),
    ex("InputStream in = Files.newInputStream(path); return new String(in.readAllBytes());", "RESOURCE_LEAK", "medium",
       "Stream not closed; use try-with-resources or Files.readString."),
    ex("List<OrderLine> lines = lineRepo.findByOrderIdIn(orderIds); Map<Long, List<OrderLine>> byOrder = group(lines);", "NO_FINDING", "none",
       "Batched load and in-memory grouping; nothing to flag."),
    ex("try (var conn = dataSource.getConnection(); var ps = conn.prepareStatement(sql)) { ps.executeUpdate(); }", "NO_FINDING", "none",
       "Resources are closed by try-with-resources."),
    {"input": "for (Order o : orders) { audit.log(o); }", "output": {"category": "N_PLUS_ONE", "comment": "maybe slow"}},  # malformed
    {"input": "client.call()", "output": "looks fine to me"},                                                                 # malformed
]

QUERY = "for (Invoice inv : invoices) { inv.setPayments(paymentRepo.findByInvoiceId(inv.getId())); }"


def tokens(text):
    text = re.sub(r"([a-z])([A-Z])", r"\1 \2", text)                     # camelCase -> words
    return [t for t in re.split(r"[^a-z0-9]+", text.lower()) if len(t) > 1]


def tfidf_vectors(docs):
    df = Counter(t for d in docs for t in set(tokens(d)))
    n = len(docs)
    vecs = []
    for d in docs:
        tf = Counter(tokens(d))
        v = {t: (c / len(tf)) * math.log((1 + n) / (1 + df[t])) + 1e-9 for t, c in tf.items()}
        norm = math.sqrt(sum(x * x for x in v.values()))
        vecs.append({t: x / norm for t, x in v.items()})
    return vecs


def cos(a, b):
    return sum(x * b.get(t, 0.0) for t, x in a.items())


def valid(example):
    out = example["output"]
    return (isinstance(out, dict) and set(out) == SCHEMA_KEYS and out["category"] in CATEGORIES
            and out["severity"] in {"high", "medium", "low", "none"})


def select(pool, query, k, lam=None, require_abstain=False):
    vecs = tfidf_vectors([e["input"] for e in pool] + [query])
    q, items = vecs[-1], list(zip(pool, vecs[:-1]))
    rel = {id(e): cos(v, q) for e, v in items}
    chosen = []
    if require_abstain:
        abstain = max((ev for ev in items if ev[0]["output"]["category"] == "NO_FINDING"), key=lambda ev: rel[id(ev[0])])
        chosen.append(abstain)
    while len(chosen) < k:
        def score(ev):
            if lam is None:
                return rel[id(ev[0])]                                    # naive top-k by similarity
            redundancy = max((cos(ev[1], c[1]) for c in chosen), default=0.0)
            return lam * rel[id(ev[0])] - (1 - lam) * redundancy        # maximal marginal relevance
        chosen.append(max((ev for ev in items if ev not in chosen), key=score))
    return [e for e, _ in chosen]


def order_for_recency(examples):
    """Put the majority label first and a minority label last (models over-weight the final example)."""
    counts = Counter(e["output"]["category"] for e in examples)
    return sorted(examples, key=lambda e: (-counts[e["output"]["category"]], e["output"]["category"]))


def render(examples):
    parts = ["<examples>"]
    for i, e in enumerate(examples, 1):
        parts.append(f'<example index="{i}">\n<diff>\n{e["input"]}\n</diff>\n'
                     f'<review>{json.dumps(e["output"], sort_keys=True)}</review>\n</example>')
    parts.append("</examples>")
    return "\n".join(parts)


valid_pool = [e for e in POOL if valid(e)]
rejected = [e for e in POOL if not valid(e)]
print(f"pool {len(POOL)} examples: {len(valid_pool)} valid, {len(rejected)} rejected for breaking the output schema")
for e in rejected:
    print(f"  rejected: {e['input'][:45]!r} -> output {json.dumps(e['output'])[:60]}")
assert len(rejected) == 2

K = 5
naive = select(valid_pool, QUERY, K)
mmr = order_for_recency(select(valid_pool, QUERY, K, lam=0.55, require_abstain=True))
for label, chosen in [("naive top-5 by similarity", naive), ("MMR(0.55) + abstention + recency order", mmr)]:
    labels = [e["output"]["category"] for e in chosen]
    print(f"--- {label}: {dict(Counter(labels))}; last example = {labels[-1]}")
    for e in chosen:
        print(f"    {e['output']['category']:<15} {e['input'][:70]}")

naive_labels = Counter(e["output"]["category"] for e in naive)
mmr_labels = [e["output"]["category"] for e in mmr]
assert naive_labels.most_common(1)[0] == ("N_PLUS_ONE", 4), "naive similarity collapses onto the look-alike label"
assert len(set(mmr_labels)) >= 4 and "NO_FINDING" in mmr_labels
counts = Counter(mmr_labels)
assert counts[mmr_labels[-1]] == min(counts.values()), "the last example carries a minority (or tied) label"
print("--- rendered <examples> block (MMR set):")
print(render(mmr))
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
pool 18 examples: 16 valid, 2 rejected for breaking the output schema
  rejected: 'for (Order o : orders) { audit.log(o); }' -> output {"category": "N_PLUS_ONE", "comment": "maybe slow"}
  rejected: 'client.call()' -> output "looks fine to me"
--- naive top-5 by similarity: {'N_PLUS_ONE': 4, 'TX_SPANS_IO': 1}; last example = TX_SPANS_IO
    N_PLUS_ONE      for (Order o : orders) { o.setLines(lineRepo.findByOrderId(o.getId()))
    N_PLUS_ONE      for (Order o : orderRepo.findAll()) { total += lineRepo.findByOrderId(
    N_PLUS_ONE      for (Long id : ids) { results.add(orderRepo.findById(id).orElseThrow()
    N_PLUS_ONE      orders.forEach(o -> o.setCustomer(customerRepo.findById(o.getCustomerI
    TX_SPANS_IO     @Transactional public void pay(Order o) { repo.save(o); kafkaTemplate.
--- MMR(0.55) + abstention + recency order: {'NO_FINDING': 1, 'N_PLUS_ONE': 1, 'RACE_CONDITION': 1, 'RESOURCE_LEAK': 1, 'TX_SPANS_IO': 1}; last example = TX_SPANS_IO
    NO_FINDING      List<OrderLine> lines = lineRepo.findByOrderIdIn(orderIds); Map<Long, 
    N_PLUS_ONE      orders.forEach(o -> o.setCustomer(customerRepo.findById(o.getCustomerI
    RACE_CONDITION  if (!repo.existsByKey(key)) { repo.save(new Payment(key)); }
    RESOURCE_LEAK   Connection c = dataSource.getConnection(); PreparedStatement ps = c.pr
    TX_SPANS_IO     @Transactional public void pay(Order o) { repo.save(o); kafkaTemplate.
--- rendered <examples> block (MMR set):
<examples>
<example index="1">
<diff>
List<OrderLine> lines = lineRepo.findByOrderIdIn(orderIds); Map<Long, List<OrderLine>> byOrder = group(lines);
</diff>
<review>{"category": "NO_FINDING", "comment": "Batched load and in-memory grouping; nothing to flag.", "severity": "none"}</review>
</example>
<example index="2">
<diff>
orders.forEach(o -> o.setCustomer(customerRepo.findById(o.getCustomerId()).orElseThrow()));
</diff>
<review>{"category": "N_PLUS_ONE", "comment": "Per-row findById in a loop; batch-load customers by id set.", "severity": "high"}</review>
</example>
<example index="3">
<diff>
if (!repo.existsByKey(key)) { repo.save(new Payment(key)); }
</diff>
<review>{"category": "RACE_CONDITION", "comment": "Check-then-insert races under retries; rely on a unique index and handle the conflict.", "severity": "high"}</review>
</example>
<example index="4">
<diff>
Connection c = dataSource.getConnection(); PreparedStatement ps = c.prepareStatement(sql); ps.executeQuery();
</diff>
<review>{"category": "RESOURCE_LEAK", "comment": "Connection and statement never closed; use try-with-resources.", "severity": "high"}</review>
</example>
<example index="5">
<diff>
@Transactional public void pay(Order o) { repo.save(o); kafkaTemplate.send("payments", o.id()); }
</diff>
<review>{"category": "TX_SPANS_IO", "comment": "Kafka send inside the transaction; use a transactional outbox.", "severity": "high"}</review>
</example>
</examples>
ALL ASSERTIONS PASSED
```

### L2 · `CritiqueLoopDynamics.java`: when critique loops help, and a harness that can't cheat

**What it shows.**
- The two-state model in closed form, matched by a 200,000-task Monte Carlo to within 0.005 at every round.
- A strong start (0.80) decays toward p\* = 0.75 under ungated critique.
- A weak start (0.50) rises toward it.
- A test-gated loop is monotone, with an analytic limit (0.9333 and 0.8333) set by the tests' miss rate.
- The help condition f·b < t·r·(1−p₀)/p₀.
- A refine harness whose types enforce factored verification and verifier-gated acceptance, and which fails loudly when nothing passes.

**What it does not show.** The rates for Claude on your tasks. The rates are ILLUSTRATIVE, so measure f, b, t, r from your own loop logs.

Run: `java CritiqueLoopDynamics.java`.

```java
// CritiqueLoopDynamics.java - when does "draft -> critique -> revise" help, and when does it make a strong
// model WORSE? A two-state Markov model of self-critique (closed form + Monte Carlo), versus a loop gated by
// an external verifier (tests), plus a small refine-loop harness whose types enforce the two invariants that
// matter: a candidate that fails the verifier is never accepted, and verification questions are answered
// WITHOUT the draft in context (factored chain-of-verification).
//
// Rates below are ILLUSTRATIVE; the algebra is exact.  Java 21.  Run: java CritiqueLoopDynamics.java
import java.util.ArrayList;
import java.util.List;
import java.util.SplittableRandom;
import java.util.function.Function;
import java.util.function.Predicate;

public final class CritiqueLoopDynamics {

    /**
     * f: critic flags a CORRECT answer (false alarm)   b: reviser then breaks it
     * t: critic flags a WRONG answer (detection)       r: reviser then fixes it
     * m: verifier (test suite) passes a WRONG answer (miss); it never fails a correct one here.
     */
    record Rates(double f, double b, double t, double r, double m) {}

    /** Ungated self-critique: p' = p(1 - f b) + (1 - p) t r; fixed point p* = t r / (f b + t r). */
    static double ungatedStep(double p, Rates x) {
        return p * (1 - x.f() * x.b()) + (1 - p) * x.t() * x.r();
    }

    static double fixedPoint(Rates x) {
        return x.t() * x.r() / (x.f() * x.b() + x.t() * x.r());
    }

    /** Verifier-gated: revise only when tests fail; accept a revision only if tests pass. Correct answers are never touched. */
    static double gatedStep(double p, Rates x) {
        return p + (1 - p) * (1 - x.m()) * x.r();
    }

    static double[] simulate(Rates x, double p0, int rounds, boolean gated, int n, long seed) {
        SplittableRandom rnd = new SplittableRandom(seed);
        boolean[] correct = new boolean[n];
        boolean[] frozen = new boolean[n];                      // gated: tests passed (a wrong answer slipped through)
        for (int i = 0; i < n; i++) correct[i] = rnd.nextDouble() < p0;
        double[] acc = new double[rounds + 1];
        acc[0] = frac(correct);
        for (int k = 1; k <= rounds; k++) {
            for (int i = 0; i < n; i++) {
                if (!gated) {
                    if (correct[i]) { if (rnd.nextDouble() < x.f() && rnd.nextDouble() < x.b()) correct[i] = false; }
                    else if (rnd.nextDouble() < x.t() && rnd.nextDouble() < x.r()) correct[i] = true;
                } else if (!correct[i] && !frozen[i]) {
                    if (rnd.nextDouble() < x.m()) frozen[i] = true;   // tests pass a wrong answer: loop stops here
                    else if (rnd.nextDouble() < x.r()) correct[i] = true;
                }
            }
            acc[k] = frac(correct);
        }
        return acc;
    }

    static double frac(boolean[] a) {
        int c = 0;
        for (boolean v : a) if (v) c++;
        return (double) c / a.length;
    }

    /** Analytic gated curve with the "frozen" mass: a wrong answer the tests pass is never revisited. */
    static double[] gatedAnalytic(Rates x, double p0, int rounds) {
        double[] acc = new double[rounds + 1];
        double correct = p0, live = 1 - p0;                     // live = wrong and still being revised
        acc[0] = correct;
        for (int k = 1; k <= rounds; k++) {
            double fixed = live * (1 - x.m()) * x.r();
            live = live * (1 - x.m()) * (1 - x.r());
            correct += fixed;
            acc[k] = correct;
        }
        return acc;
    }

    // ---- a refine-loop harness whose signatures encode the invariants -------------------------------------
    interface Drafter<T> { T draft(String task); }
    interface Planner { List<String> verificationQuestions(String task); }
    interface IndependentAnswerer { String answer(String question); }      // NO draft parameter: factored CoVe
    interface Reviser<T> { T revise(T draft, List<String> questionsAndAnswers); }

    record Trace<T>(T accepted, int rounds, List<String> log) {}

    static <T> Trace<T> refine(String task, Drafter<T> d, Planner p, IndependentAnswerer a, Reviser<T> rv,
                               Predicate<T> verifier, int maxRounds) {
        List<String> log = new ArrayList<>();
        T current = d.draft(task);
        log.add("draft: " + current);
        for (int round = 1; round <= maxRounds; round++) {
            if (verifier.test(current)) {
                log.add("verifier passed at round " + (round - 1));
                return new Trace<>(current, round - 1, log);
            }
            List<String> qa = new ArrayList<>();
            for (String q : p.verificationQuestions(task)) qa.add(q + " => " + a.answer(q));
            T candidate = rv.revise(current, qa);
            log.add("round " + round + " candidate: " + candidate + (verifier.test(candidate) ? " (passes)" : " (fails, kept for next round)"));
            current = candidate;
        }
        if (!verifier.test(current)) throw new IllegalStateException("no candidate passed the verifier in " + maxRounds + " rounds");
        return new Trace<>(current, maxRounds, log);
    }

    static void check(boolean ok, String msg) {
        if (!ok) throw new AssertionError(msg);
    }

    public static void main(String[] args) {
        Rates x = new Rates(0.25, 0.40, 0.60, 0.50, 0.20);
        int rounds = 4, n = 200_000;
        double pStar = fixedPoint(x);
        System.out.printf("rates: false-alarm f=%.2f, break b=%.2f, detect t=%.2f, fix r=%.2f, test-miss m=%.2f -> self-critique fixed point p* = %.3f%n",
                x.f(), x.b(), x.t(), x.r(), x.m(), pStar);
        System.out.println("round | strong start p0=0.80: ungated (analytic / MC)  gated (analytic / MC) | weak start p0=0.50: ungated  gated");
        double[] su = simulate(x, 0.80, rounds, false, n, 1), sg = simulate(x, 0.80, rounds, true, n, 2);
        double[] wu = simulate(x, 0.50, rounds, false, n, 3), wg = simulate(x, 0.50, rounds, true, n, 4);
        double[] ga = gatedAnalytic(x, 0.80, rounds), gw = gatedAnalytic(x, 0.50, rounds);
        double pu = 0.80, pw = 0.50;
        for (int k = 0; k <= rounds; k++) {
            if (k > 0) { pu = ungatedStep(pu, x); pw = ungatedStep(pw, x); }
            System.out.printf("  %d   |        %.4f / %.4f                %.4f / %.4f       |        %.4f   %.4f%n",
                    k, pu, su[k], ga[k], sg[k], pw, gw[k]);
            check(Math.abs(pu - su[k]) < 0.005 && Math.abs(ga[k] - sg[k]) < 0.005 && Math.abs(pw - wu[k]) < 0.005
                    && Math.abs(gw[k] - wg[k]) < 0.005, "Monte Carlo agrees with the closed form at round " + k);
        }
        check(pu < 0.80 && pu > pStar, "a strong model drifts DOWN toward p* under self-critique");
        check(pw > 0.50 && pw < pStar, "a weak model drifts UP toward p*");
        for (int k = 1; k <= rounds; k++) check(ga[k] >= ga[k - 1] && gw[k] >= gw[k - 1], "a verifier gate only ever adds correct answers");
        double reach = (1 - x.m()) * x.r() / (1 - (1 - x.m()) * (1 - x.r()));   // share of wrong answers the loop can ever fix
        double limStrong = 0.80 + 0.20 * reach, limWeak = 0.50 + 0.50 * reach;
        System.out.printf("gated limits: p0=0.80 -> %.4f, p0=0.50 -> %.4f (wrong answers the tests miss are frozen: the verifier's blind spots cap the loop)%n",
                limStrong, limWeak);
        check(ga[rounds] < limStrong && limStrong - ga[rounds] < 0.01, "gated curve approaches its analytic limit");
        double fbCritical = x.t() * x.r() * (1 - 0.80) / 0.80;
        System.out.printf("self-critique helps a model with p0=0.80 only if f*b < t*r*(1-p0)/p0 = %.3f (here f*b = %.3f)%n",
                fbCritical, x.f() * x.b());

        System.out.println("--- refine harness on a toy task (fake components, deterministic)");
        // Task: the outbox relay's retry schedule must be exponential with base 200 ms, factor 2, capped at 5 s.
        Drafter<List<Integer>> drafter = task -> List.of(200, 400, 800, 1600, 3200, 6400);   // forgets the cap
        Planner planner = task -> List.of("What is the cap?", "What is the factor?");
        IndependentAnswerer answerer = q -> q.contains("cap") ? "5000 ms" : "2";             // sees only the question
        Reviser<List<Integer>> reviser = (draft, qa) -> draft.stream().map(v -> Math.min(v, 5000)).toList();
        Predicate<List<Integer>> tests = s -> s.equals(List.of(200, 400, 800, 1600, 3200, 5000));
        Trace<List<Integer>> trace = refine("retry schedule", drafter, planner, answerer, reviser, tests, 3);
        trace.log().forEach(l -> System.out.println("  " + l));
        check(tests.test(trace.accepted()) && trace.rounds() == 1, "accepted only after the verifier passed");
        Function<Integer, Boolean> neverPasses = k -> {
            try {
                refine("x", t -> List.of(1), t -> List.of(), q -> "", (dr, qa) -> dr, s -> false, k);
                return false;
            } catch (IllegalStateException e) {
                return true;
            }
        };
        check(neverPasses.apply(3), "a loop that never passes ends in an explicit failure, not a silent accept");
        System.out.println("ALL ASSERTIONS PASSED");
    }
}
```

**Output (verified):**

```text
rates: false-alarm f=0.25, break b=0.40, detect t=0.60, fix r=0.50, test-miss m=0.20 -> self-critique fixed point p* = 0.750
round | strong start p0=0.80: ungated (analytic / MC)  gated (analytic / MC) | weak start p0=0.50: ungated  gated
  0   |        0.8000 / 0.7980                0.8000 / 0.7997       |        0.5000   0.5000
  1   |        0.7800 / 0.7792                0.8800 / 0.8797       |        0.6000   0.7000
  2   |        0.7680 / 0.7678                0.9120 / 0.9130       |        0.6600   0.7800
  3   |        0.7608 / 0.7607                0.9248 / 0.9255       |        0.6960   0.8120
  4   |        0.7565 / 0.7563                0.9299 / 0.9308       |        0.7176   0.8248
gated limits: p0=0.80 -> 0.9333, p0=0.50 -> 0.8333 (wrong answers the tests miss are frozen: the verifier's blind spots cap the loop)
self-critique helps a model with p0=0.80 only if f*b < t*r*(1-p0)/p0 = 0.075 (here f*b = 0.100)
--- refine harness on a toy task (fake components, deterministic)
  draft: [200, 400, 800, 1600, 3200, 6400]
  round 1 candidate: [200, 400, 800, 1600, 3200, 5000] (passes)
  verifier passed at round 1
ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Every input gets a finding | No "none" outputs, even on clean code | No abstention example; majority label in the examples | Add a NO_FINDING example; balance labels | L1 checks |
| F2 | Output JSON breaks intermittently | Missing keys, prose instead of JSON | A malformed example in the set; examples in an inconsistent shape | Validate examples against the schema; use structured outputs | L1 `valid()` in CI |
| F3 | Answers echo example names and values | `OrderService` in unrelated reviews | Surface copying from examples | "Format only" note; vary the irrelevant surface; shorter examples | Diversity check |
| F4 | The cache dies when retrieved examples were added | A unique example block at the top of every request | Dynamic examples in the cached prefix | Static set in system; dynamic ones after the breakpoint | Folder 01 L3 PS04 |
| F5 | "Improve your answer" lowered accuracy | Correct first answers changed to wrong | Ungated critique; f·b > t·r(1−p₀)/p₀ | Gate on tests; or don't loop | Log f, b, t, r |
| F6 | The verification step confirms the draft's error | The verifier quotes the draft | Verification run with the draft in context | Factored verification: fresh context, sources only | Harness types (L2) |
| F7 | The judge prefers whichever answer comes first, or the longer one | The verdict flips when order is swapped | Judge position and verbosity bias | Swap and require agreement; length-blind rubric | A judge eval with known pairs |
| F8 | The loop "finishes" with a failing candidate | The last candidate accepted after max rounds | No explicit failure path | Throw or mark failed; route to a human | Harness invariant |
| F9 | Opus 5 burns tokens re-verifying | Long verification tails | Carried-over verification boilerplate | Remove it on Opus 5; keep the external gate | Folder 01 L4 TP05 |

---

## 5. Staff-level drills

<details><summary><b>D1 · "We added 'review your answer and fix any mistakes' and accuracy went down. How is that possible?"</b></summary>

**Staff answer.** Ungated self-critique drives accuracy to p\* = t·r/(f·b + t·r), whatever the starting point. A strong model with a nonzero false-alarm rate (f), and a reviser that sometimes breaks correct answers (b), starts *above* p\* and drifts down. L2 shows 0.80 → 0.7565.

Fixes:
- Gate revisions on an external check, and only revise when it fails.
- Or measure (f, b, t, r) on your logs, and keep the loop only if f·b < t·r·(1−p₀)/p₀.
</details>

<details><summary><b>D2 · "Our tests gate the loop, but accuracy plateaus at 93%. More rounds don't help."</b></summary>

**Staff answer.** The plateau is the verifier's blind spot. Wrong answers that pass the tests freeze, and L2's analytic limit p₀ + (1−p₀)·(1−m)r / (1 − (1−m)(1−r)) gives 0.9333 for m = 0.2. More rounds can't fix what the tests can't see.

Raise coverage instead: contract checkers, property-based tests, mutation testing of the critical paths, or a fresh-context reviewer for what tests can't express.
</details>

<details><summary><b>D3 · "Few-shot examples taught the model our task. Why do the docs say they mostly teach format?"</b></summary>

**Staff answer.** Both are true at different strengths. Demonstrations convey the label space, input distribution and output format. Min et al. found random labels barely hurt on many tasks, so the input→label mapping carries less signal than people assume.

The practical consequences are what matter. Validate the format, balance the labels, add an abstention example, and don't end on the majority label (Zhao et al.). If you need the task *learned*, write the decision rule in the instructions and use examples to show the boundary.
</details>

<details><summary><b>D4 · "Why not pick the five most similar examples to each input? That's what RAG does."</b></summary>

**Staff answer.** Similarity alone collapses onto the look-alike label: L1's naive top-5 had 4 of 5 N_PLUS_ONE examples for an N+1-looking query. That teaches the model to answer N+1 before it reads the input.

Use MMR (relevance minus redundancy) with a required abstention example. For caching, keep a static canonical set in the prefix and append at most two retrieved examples after the breakpoint.
</details>

<details><summary><b>D5 · "Chain-of-verification is just asking the model to double-check. What's special about it?"</b></summary>

**Staff answer.** The *factored* part. Verification questions are answered in a fresh context that contains the sources but **not the draft**. With the draft visible, models tend to repeat their own mistakes while "checking" (Dhuliawala et al.).

In an agent, run the verify step as a read-only subagent that receives only the question and the file paths. L2's harness enforces this in the type signature.
</details>

<details><summary><b>D6 · "We use Claude as a judge to pick the better of two patches. How do we trust it?"</b></summary>

**Staff answer.** Known judge biases include position, verbosity and self-preference (Zheng et al.). Countermeasures:

- Run both orders and require agreement.
- Use a rubric tied to spec invariants, with file:line evidence.
- Make length explicitly not a criterion.
- Judge in a fresh context, not the generator's.
- Calibrate on pairs where you know the answer, and track the agreement rate over time.
</details>

<details><summary><b>D7 · "Should the static examples go in CLAUDE.md?"</b></summary>

**Staff answer.** Only if they apply to *every* task in the repo. CLAUDE.md is loaded into every session, and examples are expensive context. Task-family examples (code-review findings, migration style) belong in a **skill** (Folder 04), which loads on demand, or in the specific prompt template. Keep CLAUDE.md for conventions and pointers.
</details>

<details><summary><b>D8 · "How many verification rounds should an agent loop allow?"</b></summary>

**Staff answer.** Use as many as the gated curve still pays for. Each round's marginal gain is (1−p_k)(1−m)r, and its cost is one more turn on a mostly cached prefix. With the illustrative rates, rounds 3→4 added 0.005. Stop at 2–3 rounds, then fail loudly to a human with the trace. Measure your own curve from loop logs.
</details>

---

## 6. Invariants checklist

- [ ] Every few-shot example validates against the output schema used in production.
- [ ] The canonical set has one example per important label, a contrastive near-miss and an abstention example, and doesn't end on the majority label.
- [ ] Static examples are cached; retrieved examples come after the last breakpoint.
- [ ] Examples are labelled "format only", and their irrelevant surface is varied.
- [ ] Refine loops are verifier-gated, bounded, factored and traced, and fail explicitly.
- [ ] Self-critique without an external check is used only when measured to help (f·b < t·r(1−p₀)/p₀).
- [ ] Judges run position-swapped, against a rubric with evidence, in a fresh context.

---

## 7. References

- Anthropic, Prompting best practices ("Use examples effectively", "Leverage thinking", "Chain complex prompts"): <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Brown et al., "Language Models are Few-Shot Learners" (2020): <https://arxiv.org/abs/2005.14165>
- Zhao et al., "Calibrate Before Use: Improving Few-Shot Performance of Language Models" (2021): <https://arxiv.org/abs/2102.09690>
- Min et al., "Rethinking the Role of Demonstrations: What Makes In-Context Learning Work?" (2022): <https://arxiv.org/abs/2202.12837>
- Dhuliawala et al., "Chain-of-Verification Reduces Hallucination in Large Language Models" (2023): <https://arxiv.org/abs/2309.11495>
- Madaan et al., "Self-Refine: Iterative Refinement with Self-Feedback" (2023): <https://arxiv.org/abs/2303.17651>
- Huang et al., "Large Language Models Cannot Self-Correct Reasoning Yet" (2023): <https://arxiv.org/abs/2310.01798>
- Zheng et al., "Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena" (2023): <https://arxiv.org/abs/2306.05685>

Previous: [01 · Spec-driven prompting](01-spec-driven-prompting-invariants-anti-goals-and-verification-contracts.md) · Next: [03 · Compaction, hallucination and sycophancy](03-context-compaction-strategies-preventing-hallucination-and-sycophancy-traps.md) · [KB README](../README.md)
