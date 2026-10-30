# 06.2 · Retrieval & Ranking Metrics: Recall@k, MRR, MAP & nDCG Math

> **Folder 06 · Evaluation Statistics, Error Analysis & LLM-as-a-Judge**
> **Measured on:** NumPy 2.5.4, scikit-learn 1.9.1 (`ndcg_score` cross-check), three real retrievers on BEIR SciFact (BM25, MiniLM dense, hybrid; built in 04.1–04.2), Windows 11.
> **Design sources:** Järvelin & Kekäläinen (nDCG, 2002), Voorhees (TREC pooling), Buckley & Voorhees (bpref, 2004), Moffat & Zobel (RBP, 2008), Chapelle et al. (ERR, 2009), Thakur et al. (BEIR, 2021), Thomas et al. (LLM relevance labels, 2024), Es et al. (RAGAS, 2023). Full list in §8.

---

## 0. Orientation: In RAG, Retrieval Metrics Are the Ceiling on Answer Quality

An LLM can't cite a document it was never shown. So in a retrieval-augmented system, **Recall@k of the retriever is an upper bound on answer correctness**. Retrieval metrics are also deterministic, free to compute (no LLM in the loop) and fast to iterate on. They're the cheapest eval layer you'll ever own. This file derives each metric, shows where they disagree, and measures them on real systems:

- **One table, three retrievers, real data** (SciFact, 300 test claims): the hybrid wins every metric (nDCG@10 0.7257 vs BM25 0.6711 vs dense 0.6451). But **dense beats BM25 on Recall@100** (0.925 vs 0.905) while losing on nDCG@10. Which is "better" depends on whether a re-ranker sits downstream.
- **Means hide failures:** per-query nDCG@10 has a standard deviation of ~0.39. Even the best system scores **zero** on 12.7% of claims, and BM25 on 17.7%. Those are the queries your users complain about.
- **Metrics disagree by design:** system A (one perfect answer, one at rank 10) beats B on MRR (0.550 vs 0.333). B (both answers at rank 3) beats A on Recall@5 (1.0 vs 0.5). The right metric is the one that matches the *consumer* of the ranking.
- **Incomplete labels can reverse a comparison:** a new system that surfaces six relevant documents nobody had judged scores **0.087** on the old qrels vs the old system's 0.366. With complete labels it's **0.797 vs 0.293**.

### The backend-engineer bridge

| You already know | Ranking-metric equivalent |
|---|---|
| Cache hit rate for the top-N hot keys | **Recall@k**: did the needed item make it into the first k? |
| Time-to-first-useful-byte | **Reciprocal rank**: how far down is the first useful result? |
| Weighted SLO across tiers (gold > silver > bronze) | **Graded relevance with gain 2^rel − 1** |
| Attention decays down a log file or a search page | **The log₂(rank + 1) discount** |
| A golden test suite that was written against the old implementation | **Pooled qrels**: biased toward the systems that built them |
| p50 hides the p99 | **Mean nDCG hides zero-recall queries** |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Ranked lists, qrels, binary vs graded relevance | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Recall@k and Precision@k | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Reciprocal rank and MRR | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Average precision and MAP | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.5 DCG and nDCG: gain, discount, ideal ordering | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Choosing k and the metric from the consumer of the ranking | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Per-query distributions and the zero-recall rate | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Incomplete judgments, pooling bias, and LLM-labelled qrels | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 RAG metrics (context recall/precision, faithfulness) and how they map onto IR metrics | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 User-model metrics: ERR and RBP | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Online evaluation: CTR, interleaving | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.12 Metric axiomatics and unbiased click-model theory | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Ranked lists, qrels, binary vs graded relevance `[MUST-KNOW: Core AI Engineer Edge]`

The unit of evaluation is a **query** q with a **ranked list** of documents d₁, d₂, …, and a set of **relevance judgments** (qrels): rel(q, d) ∈ {0, 1} (binary) or {0, 1, 2, 3} (graded). The metric is computed per query, then averaged over queries. Two facts matter in practice:

- **Unjudged = non-relevant.** Standard tooling (trec_eval, pytrec_eval, ir_measures) treats any document missing from the qrels as rel = 0. This drives §1.8.
- **The ideal ordering uses all judged relevant documents**, including the ones your system never retrieved. That's why the single-query example below has nDCG < 1 even with a perfect first result: one relevant document (label 2) was never retrieved.

### 1.2 Recall@k and Precision@k `[MUST-KNOW: Core AI Engineer Edge]`

```text
Recall@k(q)    = |relevant ∩ top-k| / |relevant|
Precision@k(q) = |relevant ∩ top-k| / k
```

Recall@k ignores order inside the top-k. That is exactly right when the consumer is an **LLM context window**: whether the supporting chunk is at position 2 or 7 of the context matters much less than whether it's there at all. Position effects inside the context ("lost in the middle", Liu et al., 2023) are a second-order concern you measure separately. Precision@k penalizes padding the context with irrelevant chunks, which costs tokens and can distract the generator.

Listing §3.1, section 1: 10 ranked documents with labels [3, 0, 2, 0, 0, 1, 0, …], 4 relevant documents in total. **Recall@5 = 2/4 = 0.500, Precision@5 = 2/5 = 0.400.**

### 1.3 Reciprocal rank and MRR `[MUST-KNOW: Core AI Engineer Edge]`

```text
RR(q) = 1 / rank of the first relevant document   (0 if none retrieved)
MRR   = mean over queries of RR(q)
```

MRR models a user who reads down the list and stops at the first useful result: a known-item search, a "the answer is in one FAQ" bot, or the top-1 intent a router acts on. It ignores everything after the first hit, so it's the wrong metric when the consumer needs **several** relevant documents (multi-hop questions, a summary across sources). RR is also very coarse: ranks 1, 2 and 3 give 1, 0.5 and 0.33.

### 1.4 Average precision and MAP `[GOOD-TO-KNOW: Architectural Literacy]`

```text
AP(q) = (1 / |relevant|) · Σ_{k : d_k relevant} Precision@k
MAP   = mean over queries of AP(q)
```

Single-query example: hits at ranks 1, 3 and 6, so AP = (1/1 + 2/3 + 3/6)/4 = 2.1667/4 = **0.5417**. The denominator is 4, not 3, so the unretrieved relevant document counts as a miss. AP is the area under the per-query PR curve (06.1 §1.4) and rewards putting *all* relevant documents high. It was TREC's workhorse. In RAG work it's mostly replaced by nDCG (graded labels) and Recall@k (context-window consumers).

### 1.5 DCG and nDCG: gain, discount, ideal ordering `[MUST-KNOW: Core AI Engineer Edge]`

```text
DCG@k(q)  = Σ_{i=1..k} gain(rel_i) / log₂(i + 1)          gain = 2^rel − 1 (exponential) or rel (linear)
nDCG@k(q) = DCG@k(q) / IDCG@k(q)                          IDCG = DCG of the ideal ordering of ALL judged docs
```

Three design choices are packed into this formula:

1. **Graded gain.** With exponential gain, a "perfectly relevant" label 3 is worth 7 and a "partially relevant" label 1 is worth 1. Demoting the best document costs a lot: in §3.1, section 2, swapping a 3 and a 1 at ranks 1–2 gives nDCG@3 **0.710** with exponential gain vs **0.797** with linear.
2. **Log discount.** Position i is worth 1/log₂(i+1): 1, 0.63, 0.5, 0.43, … The discount is gentle, so nDCG still rewards relevant documents at rank 8–10, unlike RR.
3. **Normalization per query.** Dividing by IDCG makes every query's score lie in [0, 1], so easy and hard queries count equally in the mean.

Single-query example (exponential gain): DCG = 7/1 + 3/log₂4 + 1/log₂7 = 7 + 1.5 + 0.356 = 8.856. IDCG over [3, 2, 2, 1] = 7 + 3/log₂3 + 3/2 + 1/log₂5 = 10.823. **nDCG@10 = 0.8182.** The listing also checks the linear-gain variant against `sklearn.metrics.ndcg_score` to 1e-12 (0.765249). Two implementations agreeing is the minimum bar before you trust any eval harness.

> **Gotcha:** BEIR and most leaderboards report nDCG@10 with **linear** gain via pytrec_eval, while the classic Burges formulation uses exponential gain. On binary labels they're identical. On graded labels they aren't, so state which one you use.

### 1.6 Choosing k and the metric from the consumer of the ranking `[MUST-KNOW: Core AI Engineer Edge]`

The metric should model what reads the ranking:

| Consumer of the ranking | What matters | Metric |
|---|---|---|
| An LLM context window of k chunks | Is the evidence anywhere in the k? | **Recall@k** (k = the context budget), plus Precision@k for token cost |
| A re-ranker that sees the top-N | Is the evidence in the candidate set at all? | **Recall@N** (N = the re-ranker's input, e.g. 50–100) |
| A UI page of 10 results | Graded usefulness near the top | **nDCG@10** |
| A bot that acts on the top-1 | The first result | **MRR** or **Precision@1** |
| A router's top intent | Classification accuracy | 06.1 |

This explains the SciFact table: dense MiniLM has **higher Recall@100** (0.925 vs 0.905) but **lower nDCG@10** (0.645 vs 0.671) than BM25. As stage 1 for a re-ranker over the top 100, dense is the better candidate generator. As the only ranker, BM25 is better at the top. The hybrid's gain over BM25 is about the same at every depth (+0.047 at k=1, +0.055 at k=10, +0.055 at k=50), so it's a uniform improvement, not a reshuffle at one depth.

**Two-stage systems need two metrics:** Recall@N for stage 1 (the ceiling) and nDCG@k for the final order. 06.3 §3 makes this quantitative with a ceiling analysis: on a BM25 → MiniLM pipeline, a perfect stage 2 is worth +0.21 nDCG@10 and perfect stage-1 recall only +0.04.

### 1.7 Per-query distributions and the zero-recall rate `[MUST-KNOW: Core AI Engineer Edge]`

The mean over queries hides the shape. From the SciFact suite (§3.2, section 2):

| System | Mean nDCG@10 | Std | Queries with nDCG@10 = 0 | Queries with nDCG@10 = 1 |
|---|---|---|---|---|
| BM25 | 0.671 | 0.392 | 17.7% | 52.0% |
| Dense MiniLM | 0.645 | 0.398 | 20.7% | 47.3% |
| Hybrid 0.3/0.7 | 0.726 | 0.361 | 12.7% | 55.7% |

Per-query nDCG is **bimodal**: most queries are either solved or completely missed. The useful operational metric is the **zero-recall rate** (queries where nothing relevant reaches the context), because those produce confidently wrong RAG answers or refusals. The hybrid's biggest win is moving 5 points of queries out of the zero bucket. That's also the population to read in error analysis (06.3): sort by per-query score and read the bottom 30.

A standard deviation of 0.39 over 300 queries puts the standard error of the mean at ≈ 0.39/√300 = 0.023. Two systems are compared *per query* (paired), which shrinks this a lot (06.4 §1.3).

### 1.8 Incomplete judgments, pooling bias, and LLM-labelled qrels `[MUST-KNOW: Core AI Engineer Edge]`

TREC-style test collections judge only a **pool**: the union of the top-k from the systems that took part. Documents outside the pool are unjudged and treated as non-relevant. That's harmless when the pool is deep and diverse. It's systematically **biased against a new system** that retrieves different documents. Listing §3.1, section 4, builds the cleanest case:

```text
old system: nDCG@10 with complete labels 0.293; with only the old pool judged 0.366
new system: nDCG@10 with complete labels 0.797; with only the old pool judged 0.087
```

The new system surfaces six relevant documents the old one ranked below 100. Under the old pool those six look non-relevant, and **the comparison reverses**. In production terms: your eval set was labelled by reading the *old* retriever's results. A new embedding model that finds different-but-correct chunks will look worse, and you'll reject the upgrade.

Fixes, in order of strength:

1. **Judge the new system's top-k before comparing** (re-pool). This is the only real fix, and it's the cheapest moment to label: just the documents the new system adds.
2. **Report the judged fraction at k** ("judged@10") for every system. A low value warns that the metric is unreliable for that system.
3. **Condensed lists** (Sakai, 2007): drop unjudged documents before scoring. This removes the penalty but can't reward the novel documents. In this example it scores the new system exactly like the old one (0.366), because the rest of the new ranking is the old order.
4. **bpref** (Buckley & Voorhees, 2004) uses only judged documents. It's robust to incompleteness but less discriminative.

**LLM-labelled qrels.** Thomas et al. (2024) showed LLM relevance labels can match crowd-worker quality at Bing scale, and UMBRELA reproduces that setup with open tooling. The economics are compelling. Pooling top-10 from 3 systems over 300 queries is ~6,000 judgments: ~50 hours of human time at 30 s each, vs ≈ 4.8 M input tokens with a Haiku-class model, about **$0.50** at $0.10/MTok. The catch is the same as every LLM-as-judge setup (06.3): measure agreement against a human-labelled subset (κ, not raw agreement), audit for bias toward the systems or the model family that generated the candidates, and keep the human subset as the ground truth for the judge.

### 1.9 RAG metrics and how they map onto IR metrics `[MUST-KNOW: Core AI Engineer Edge]`

RAG evaluation frameworks (RAGAS, ARES, TruLens-style "RAG triad") add generation-side metrics to the retrieval ones:

| RAG metric | What it measures | IR analogue | Needs an LLM? |
|---|---|---|---|
| Context recall | Are the facts needed for the reference answer present in the retrieved context? | Recall@k with "relevant" = supports the answer | Usually (claim matching) |
| Context precision | Are the retrieved chunks relevant, and ranked first? | Precision@k / AP | Usually |
| Faithfulness (groundedness) | Is every claim in the answer supported by the context? | none (a generation property) | Yes, or an NLI model |
| Answer relevance | Does the answer address the question? | none | Yes |

The practical layering (Ng-style: cheap evals first):

1. **Retrieval with labelled qrels**: Recall@k, nDCG@10 and the zero-recall rate. Deterministic, free, runs on every commit.
2. **Generation given gold context**: does the LLM answer correctly when handed the right chunks? This isolates generator errors from retriever errors (a component-level eval).
3. **End-to-end with an LLM judge** for faithfulness and correctness, calibrated against humans (06.3), run on a sample.

If step 2 is fine and end-to-end is bad, the problem is retrieval, and step 1 is the cheap place to iterate. This is the ceiling-analysis logic of 06.3 applied to RAG.

### 1.10 User-model metrics: ERR and RBP `[GOOD-TO-KNOW: Architectural Literacy]`

- **Rank-biased precision** (Moffat & Zobel, 2008): RBP = (1 − p)·Σ rel_i·p^(i−1). The user goes to the next result with probability p (patience). Its residual (the maximum possible contribution of unjudged documents) is computable, which is a principled handle on incompleteness.
- **Expected reciprocal rank** (Chapelle et al., 2009): a cascade model where the user stops at a result with probability that grows with its relevance. A highly relevant document at rank 1 makes the rest of the list matter much less, unlike nDCG.

Both make the user model explicit. For LLM consumers that read the whole context, neither model is right, and Recall@k is the honest choice.

### 1.11 Online evaluation: CTR, interleaving `[GOOD-TO-KNOW: Architectural Literacy]`

Offline metrics need labels; online metrics need traffic. **Interleaving** merges two rankers' results into one list (team-draft interleaving) and credits clicks to the ranker that contributed the clicked result. Each user effectively compares both systems, so it typically needs **an order of magnitude or more less traffic** than an A/B test on CTR to detect the same preference (Chapelle et al., 2012; ⚠ the factor is product-specific, so measure it on your own logs). For RAG systems, user clicks are often missing (users read the answer, not the sources). Then online signals are thumbs-up/down, follow-up rephrasing rates and citation clicks, all noisy and position-biased. Treat them as A/B metrics with the statistics of 06.4.

### 1.12 Metric axiomatics and unbiased click-model theory `[SKIP: Academic/Research Only]`

Formal axioms for IR metrics (which properties a metric should satisfy) and unbiased learning-to-rank from click logs with propensity estimation are active research areas. Know that click logs are position-biased and need correction before training or evaluating on them. The formal theory isn't needed to ship.

---

## 2. Where It Beats an LLM in Production

Two different "beats an LLM" stories run through retrieval evaluation.

**1. Deterministic retrieval metrics beat LLM-judged end-to-end evals as the inner loop.** The SciFact suite in §3.2 scores three retrievers on 300 queries in seconds, with no API calls and the same answer every time. An end-to-end RAG eval with an LLM judge costs money per run, has judge noise on top of system noise, and confounds retrieval with generation. Since Recall@k bounds answer quality, the retrieval layer is where you iterate 50 times a day. The LLM-judged layer runs nightly, on a sample.

**2. Cheap rankers measured this way often beat LLM re-rankers on cost per nDCG point.** In 04.3, LambdaMART on cheap features re-ranked in 0.51 ms. A cross-encoder took ~900–1,900 ms per 20 pairs on CPU and, zero-shot, *hurt* SciFact (0.6818 vs the hybrid's 0.7257). An LLM listwise re-ranker is slower and costlier still. Without per-query nDCG and a paired test (06.4), you can't see whether the expensive stage is buying anything. With them, the answer was "not on this domain without fine-tuning".

**Where an LLM genuinely helps:** **producing the labels**. LLM relevance judgments at ~$0.50 per 6,000 judgments (§1.8) make deep, re-pooled qrels affordable, provided you calibrate the judge against a human subset.

---

## 3. Production Code Blueprint

### 3.1 Ranking metrics from scratch, cross-checked, with the classic traps

```python
"""ranking_metrics_from_scratch.py - Recall@k, Precision@k, MRR, MAP and nDCG implemented and cross-checked.

  1. Definitions on one ranked list; nDCG matches sklearn.metrics.ndcg_score.
  2. Linear vs exponential gain for graded relevance.
  3. Metrics disagree: two systems, opposite winners depending on the metric.
  4. Incomplete judgments: unjudged documents count as non-relevant, which penalizes NEW systems.
"""
import numpy as np
from sklearn.metrics import ndcg_score


def recall_at(rel_sorted, n_rel, k):
    return np.sum(rel_sorted[:k] > 0) / n_rel


def precision_at(rel_sorted, k):
    return np.sum(rel_sorted[:k] > 0) / k


def rr(rel_sorted):
    hits = np.flatnonzero(rel_sorted > 0)
    return 1.0 / (hits[0] + 1) if len(hits) else 0.0


def ap(rel_sorted, n_rel):
    hits = np.flatnonzero(rel_sorted > 0)
    return np.sum((np.arange(len(hits)) + 1) / (hits + 1)) / n_rel


def dcg(rel_sorted, k, gain="exp"):
    g = (2.0 ** rel_sorted[:k] - 1) if gain == "exp" else rel_sorted[:k].astype(float)
    return np.sum(g / np.log2(np.arange(2, len(g) + 2)))


def ndcg(rel_sorted, all_rels, k, gain="exp"):
    ideal = dcg(np.sort(all_rels)[::-1], k, gain)
    return dcg(rel_sorted, k, gain) / ideal if ideal > 0 else 0.0


print("== 1. one query: 10 ranked documents, graded labels (0-3), 4 relevant documents exist in total ==")
labels_ranked = np.array([3, 0, 2, 0, 0, 1, 0, 0, 0, 0])
all_rels = np.array([3, 2, 1, 2])                                 # one relevant doc (label 2) was never retrieved
n_rel = len(all_rels)
print(f"Recall@5 {recall_at(labels_ranked, n_rel, 5):.3f}  Precision@5 {precision_at(labels_ranked, 5):.3f}  "
      f"RR {rr(labels_ranked):.3f}  AP {ap(labels_ranked, n_rel):.4f}  nDCG@10 {ndcg(labels_ranked, all_rels, 10):.4f}")
# sklearn needs scores for every candidate: give the ranked docs descending scores, the missing doc the lowest
true = np.r_[labels_ranked, 2][None]
scores = np.r_[np.arange(10, 0, -1), 0][None].astype(float)
ours = ndcg(labels_ranked, all_rels, 10, gain="lin")
print(f"nDCG@10 with linear gain: ours {ours:.6f}  sklearn ndcg_score(k=10) {ndcg_score(true, scores, k=10):.6f}")
assert abs(ours - ndcg_score(true, scores, k=10)) < 1e-12

print("\n== 2. linear vs exponential gain ==")
for name, lr in (("label 3 at rank 1, label 1 at rank 2", np.array([3, 1, 0])), ("label 1 at rank 1, label 3 at rank 2", np.array([1, 3, 0]))):
    print(f"{name:38s} nDCG@3 linear {ndcg(lr, np.array([3, 1]), 3, 'lin'):.4f}  exponential {ndcg(lr, np.array([3, 1]), 3, 'exp'):.4f}")
print("exponential gain (2^rel - 1) punishes demoting the BEST document much harder")

print("\n== 3. two systems, 2 queries each with one relevant document ==")
A = [np.array([1, 0, 0, 0, 0, 0, 0, 0, 0, 0]), np.array([0] * 9 + [1])]   # perfect on q1, rank 10 on q2
B = [np.array([0, 0, 1, 0, 0, 0, 0, 0, 0, 0]), np.array([0, 0, 1] + [0] * 7)]  # rank 3 on both
for name, runs in (("A", A), ("B", B)):
    print(f"system {name}: MRR {np.mean([rr(r) for r in runs]):.3f}  Recall@5 {np.mean([recall_at(r, 1, 5) for r in runs]):.3f}  "
          f"nDCG@10 {np.mean([ndcg(r, np.array([1]), 10) for r in runs]):.3f}")
print("MRR prefers A (one perfect answer); Recall@5 prefers B (both answers on page one) -> choose the metric that")
print("matches the product: one answer shown (MRR/P@1) vs a top-5 context window for an LLM (Recall@5)")

print("\n== 4. incomplete judgments ==")
true_rel = np.zeros(200, int)
true_rel[[1, 4, 7, 15, 30, 55, 80]] = 1                             # relevant docs inside the old system's top-100
novel = np.array([120, 135, 150, 170, 185, 199])                    # relevant docs the old system ranked below 100
true_rel[novel] = 1
judged = np.arange(200) < 100                                       # only the OLD system's top-100 was ever judged
old_order = np.arange(200)                                          # the old system ranks docs 0..199 in order
new_order = np.r_[novel, np.setdiff1d(np.arange(200), novel)]       # the new system surfaces the novel docs first
seen_labels = np.where(judged, true_rel, 0)                         # unjudged = "not relevant" in the qrels file
res = {}
for name, order in (("old system", old_order), ("new system", new_order)):
    res[name] = (ndcg(true_rel[order], true_rel, 10), ndcg(seen_labels[order], seen_labels, 10))
    print(f"{name}: nDCG@10 with complete labels {res[name][0]:.3f}; with only the old pool judged {res[name][1]:.3f}")
print("the incomplete qrels REVERSE the comparison: unjudged relevant documents count as misses, so pooled")
print("judgments are biased toward the systems that built the pool -> judge the new system's top-k before comparing")
assert res["new system"][0] > res["old system"][0] and res["new system"][1] < res["old system"][1]
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. one query: 10 ranked documents, graded labels (0-3), 4 relevant documents exist in total ==
Recall@5 0.500  Precision@5 0.400  RR 1.000  AP 0.5417  nDCG@10 0.8182
nDCG@10 with linear gain: ours 0.765249  sklearn ndcg_score(k=10) 0.765249

== 2. linear vs exponential gain ==
label 3 at rank 1, label 1 at rank 2   nDCG@3 linear 1.0000  exponential 1.0000
label 1 at rank 1, label 3 at rank 2   nDCG@3 linear 0.7967  exponential 0.7098
exponential gain (2^rel - 1) punishes demoting the BEST document much harder

== 3. two systems, 2 queries each with one relevant document ==
system A: MRR 0.550  Recall@5 0.500  nDCG@10 0.645
system B: MRR 0.333  Recall@5 1.000  nDCG@10 0.500
MRR prefers A (one perfect answer); Recall@5 prefers B (both answers on page one) -> choose the metric that
matches the product: one answer shown (MRR/P@1) vs a top-5 context window for an LLM (Recall@5)

== 4. incomplete judgments ==
old system: nDCG@10 with complete labels 0.293; with only the old pool judged 0.366
new system: nDCG@10 with complete labels 0.797; with only the old pool judged 0.087
the incomplete qrels REVERSE the comparison: unjudged relevant documents count as misses, so pooled
judgments are biased toward the systems that built the pool -> judge the new system's top-k before comparing

ALL ASSERTIONS PASSED
```

### 3.2 One evaluation table for three real retrievers (SciFact)

```python
"""scifact_metric_suite.py - one evaluation table for three real retrievers on SciFact, and what each metric sees.

Systems: BM25, dense MiniLM (04.2's cached embeddings), hybrid (convex 0.3 / 0.7 of min-max scores).
  1. Recall@10, Recall@100, MRR@10, MAP@100, nDCG@10 per system.
  2. Per-query spread: the mean hides failures (queries with nDCG@10 = 0).
  3. Metric depth: how the hybrid-vs-BM25 gap changes with the cutoff k.
Saves per-query results for 06.3 (ceiling analysis) and 06.4 (bootstrap).
"""
import json
import math
import os
import re
from collections import defaultdict

import numpy as np

DL, DATA = os.environ["KB_DL"], os.environ["KB_DATA"]
D = os.path.join(DL, "scifact", "x", "scifact")
docs = [json.loads(l) for l in open(os.path.join(D, "corpus.jsonl"), encoding="utf-8")]
queries = {q["_id"]: q["text"] for q in map(json.loads, open(os.path.join(D, "queries.jsonl"), encoding="utf-8"))}
qrels = defaultdict(dict)
for line in list(open(os.path.join(D, "qrels", "test.tsv"), encoding="utf-8"))[1:]:
    a, b, s = line.split()
    qrels[a][b] = int(s)
doc_ids = [d["_id"] for d in docs]
Z = np.load(os.path.join(DATA, "scifact_minilm.npz"))
E_doc, E_q = Z["E_doc"], Z["E_q"]
qpos = {str(q): i for i, q in enumerate(Z["qids"])}
STOP = set("a an and are as at be by for from has have in into is it its of on or that the their this to was were "
           "which with we our these those than not no can may also between both".split())


def light_stem(w):
    for suf in ("ations", "ation", "ingly", "ing", "edly", "ed", "ies", "es", "s"):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            return w[: -len(suf)] + ("y" if suf == "ies" else "")
    return w


tokenize = lambda s: [light_stem(t) for t in re.findall(r"[a-z0-9]+", s.lower()) if t not in STOP]
post = defaultdict(lambda: defaultdict(int))
dl = np.zeros(len(docs))
for i, d in enumerate(docs):
    toks = tokenize(d["title"] + " " + d["text"])
    dl[i] = len(toks)
    for w in toks:
        post[w][i] += 1
P = {w: (np.fromiter(p.keys(), int), np.fromiter(p.values(), float)) for w, p in post.items()}
N, avgdl = len(docs), dl.mean()
idf = {w: math.log(1 + (N - len(d) + 0.5) / (len(d) + 0.5)) for w, (d, _) in P.items()}


def bm25(q):
    acc = np.zeros(N)
    for w in set(tokenize(q)):
        if w in P:
            d, tf = P[w]
            acc[d] += idf[w] * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * dl[d] / avgdl))
    return acc


mm = lambda x: (x - x.min()) / (x.max() - x.min() + 1e-12)
test_q = sorted(qrels, key=int)
runs = {"BM25": [], "dense MiniLM": [], "hybrid 0.3/0.7": []}
for qid in test_q:
    sb, sd = bm25(queries[qid]), E_doc @ E_q[qpos[qid]]
    for name, s in (("BM25", sb), ("dense MiniLM", sd), ("hybrid 0.3/0.7", 0.3 * mm(sb) + 0.7 * mm(sd))):
        runs[name].append(np.argsort(-s, kind="stable")[:100])


def metrics(top, rel):
    g = np.array([1 if doc_ids[j] in rel else 0 for j in top])
    n = len(rel)
    hits = np.flatnonzero(g)
    ideal = sum(1 / math.log2(r + 2) for r in range(min(10, n)))
    return {"R@10": g[:10].sum() / n, "R@100": g.sum() / n,
            "MRR@10": 1 / (hits[0] + 1) if len(hits) and hits[0] < 10 else 0.0,
            "MAP@100": np.sum((np.arange(len(hits)) + 1) / (hits + 1)) / n,
            "nDCG@10": np.sum(g[:10] / np.log2(np.arange(2, 12))) / ideal,
            **{f"nDCG@{k}": np.sum(g[:k] / np.log2(np.arange(2, k + 2))) / sum(1 / math.log2(r + 2) for r in range(min(k, n)))
               for k in (1, 3, 5, 20, 50)}}


per = {name: [metrics(t, qrels[q]) for t, q in zip(tops, test_q)] for name, tops in runs.items()}
cols = ("R@10", "R@100", "MRR@10", "MAP@100", "nDCG@10")
print(f"== 1. 300 test claims ==\n{'system':16s} " + " ".join(f"{c:>8}" for c in cols))
for name, rows in per.items():
    print(f"{name:16s} " + " ".join(f"{np.mean([r[c] for r in rows]):>8.4f}" for c in cols))

print("\n== 2. per-query nDCG@10 distribution ==")
print(f"{'system':16s} {'mean':>6} {'std':>6} {'zero (miss)':>11} {'perfect':>8}")
for name, rows in per.items():
    v = np.array([r["nDCG@10"] for r in rows])
    print(f"{name:16s} {v.mean():>6.3f} {v.std():>6.3f} {np.mean(v == 0):>11.3f} {np.mean(v >= 0.999):>8.3f}")

print("\n== 3. hybrid minus BM25 at different depths ==")
for k in (1, 3, 5, 10, 20, 50):
    key = f"nDCG@{k}"
    diff = np.mean([a[key] for a in per["hybrid 0.3/0.7"]]) - np.mean([b[key] for b in per["BM25"]])
    print(f"  nDCG@{k:<3} hybrid - BM25 = {diff:+.4f}")
np.savez_compressed(os.path.join(DATA, "scifact_runs.npz"), test_q=np.array(test_q),
                    **{f"top_{i}": np.array(runs[n]) for i, n in enumerate(runs)},
                    **{f"ndcg_{i}": np.array([r["nDCG@10"] for r in per[n]]) for i, n in enumerate(runs)})
json.dump({"systems": list(runs), "qrels": {q: list(qrels[q]) for q in test_q}}, open(os.path.join(DATA, "scifact_runs.json"), "w"))
h, b = np.mean([r["nDCG@10"] for r in per["hybrid 0.3/0.7"]]), np.mean([r["nDCG@10"] for r in per["BM25"]])
assert h > b
print("saved per-query runs for 06.3 / 06.4")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. 300 test claims ==
system               R@10    R@100   MRR@10  MAP@100  nDCG@10
BM25               0.8016   0.9053   0.6367   0.6294   0.6711
dense MiniLM       0.7833   0.9250   0.6047   0.6031   0.6451
hybrid 0.3/0.7     0.8633   0.9583   0.6867   0.6813   0.7257

== 2. per-query nDCG@10 distribution ==
system             mean    std zero (miss)  perfect
BM25              0.671  0.392       0.177    0.520
dense MiniLM      0.645  0.398       0.207    0.473
hybrid 0.3/0.7    0.726  0.361       0.127    0.557

== 3. hybrid minus BM25 at different depths ==
  nDCG@1   hybrid - BM25 = +0.0467
  nDCG@3   hybrid - BM25 = +0.0488
  nDCG@5   hybrid - BM25 = +0.0548
  nDCG@10  hybrid - BM25 = +0.0545
  nDCG@20  hybrid - BM25 = +0.0512
  nDCG@50  hybrid - BM25 = +0.0545
saved per-query runs for 06.3 / 06.4

ALL ASSERTIONS PASSED
```

**Reading the output.** The hybrid wins every column, so for this pair the choice is easy. The interesting row is dense vs BM25: dense wins R@100 and loses everything at the top. Per-query, all three systems are bimodal (std ≈ 0.36–0.40), and the zero-score bucket is where the user-visible failures live. The saved per-query arrays feed 06.3's ceiling analysis and 06.4's paired bootstrap. **Never average away the per-query vector; it's the raw material for every downstream statistical question.**

### 3.3 The eval-harness contract

```python
# eval_retrieval.py: the shape every retrieval eval in a codebase should have (design sketch)
@dataclass(frozen=True)
class RetrievalEvalResult:
    system: str                      # retriever name + version + index snapshot id
    qrels_version: str               # which judgments, and when they were last re-pooled
    k_context: int                   # the LLM context budget the Recall@k refers to
    per_query: dict[str, dict]       # qid -> {"recall@k": ..., "ndcg@10": ..., "rr": ..., "judged@10": ...}

    def summary(self):
        m = lambda key: float(np.mean([r[key] for r in self.per_query.values()]))
        zero = float(np.mean([r[f"recall@{self.k_context}"] == 0 for r in self.per_query.values()]))
        return {"recall@k": m(f"recall@{self.k_context}"), "ndcg@10": m("ndcg@10"), "mrr": m("rr"),
                "zero_recall_rate": zero, "judged@10": m("judged@10"), "n_queries": len(self.per_query)}
```

The non-obvious fields are `qrels_version` (so a pooling change can't masquerade as a model change), `k_context` (so "Recall@k" always means the real context budget), and `judged@10` (so incompleteness is visible per system, §1.8).

---

## 4. The Andrew Ng Lens: Evaluate the Components Separately, Then Fund the Bottleneck

### 4.1 Component-level evals before end-to-end evals

Ng's agentic-workflow guidance (The Batch, 2025; the *Agentic AI* course) is to build evals for **individual components** as well as the end-to-end system, because component evals are cheaper, faster and say *where* the problem is. For RAG, the retriever is the most measurable component in the stack: a labelled qrels file and the code in §3.1 give a deterministic score for every change to chunking, embeddings, hybrid weights or the re-ranker.

### 4.2 Ceiling analysis decides what to work on

Ng's ceiling analysis asks: if this component were perfect, how much would the end-to-end metric improve? 06.3 §3 runs it on SciFact with BM25 top-50 → MiniLM re-ordering. Perfect stage-1 recall is worth +0.043 nDCG@10; a perfect stage 2 is worth +0.212. A team that spends the quarter on "better embeddings for recall" would be optimizing the smaller ceiling. Run this analysis before writing the roadmap.

### 4.3 Error analysis on the bottom of the per-query distribution

The 38 hybrid queries with nDCG@10 = 0 (12.7% of 300) are the error-analysis spreadsheet for retrieval. Read them, tag each with a cause (vocabulary mismatch, a negation or numeric claim, a missing document, a wrong or incomplete label), count the tags, and fix the biggest bucket (06.3 §1.2). On SciFact-like data, expect a visible share to be **label gaps**, not retrieval failures. That's §1.8 again, and another reason to re-judge before concluding.

### 4.4 Bias and variance for retrieval

If training-query Recall@k is low, the model is **biased** (the embedding or lexical model can't represent the match): change the model class, add the hybrid, or fine-tune. If training recall is high but held-out recall is low (an adapter fitted on 500 queries, 04.2), it's **variance**: more queries, regularization, early stopping. The same diagnosis applies to every learned stage in the pipeline.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | New embedding model "loses" offline, wins with users | Low judged@10 for the new system | Pooled qrels from the old system (§1.8) | Re-pool: judge the new system's top-k | Report judged@k per system; re-pool on every candidate |
| F2 | nDCG@10 up, RAG answers not better | Gain concentrated at ranks 6–10 | Metric depth ≠ context budget | Report Recall@k_context | `k_context` is a field of the eval result |
| F3 | Re-ranker shows no gain | Stage-1 Recall@N is the ceiling | Evidence not in the candidate set | Measure Recall@N of stage 1; deepen N or improve stage 1 | Two-stage metric pair: Recall@N + nDCG@k |
| F4 | Mean improves, complaints don't drop | Zero-recall rate unchanged | Gains on already-solved queries | Track the zero-recall rate; error-analyze the bottom | Zero-recall rate in the release gate |
| F5 | Leaderboard number doesn't reproduce | Different nDCG values for the same run | Linear vs exponential gain, k, or tie-breaking | Pin the implementation (pytrec_eval / ir_measures) and the gain | Cross-check two implementations (§3.1) |
| F6 | "Significant" improvement disappears next week | Unpaired comparison, small query set | Query variance dwarfs the system delta | Paired bootstrap / permutation (06.4) | Every delta reported with a paired CI |
| F7 | LLM-labelled qrels flatter one system | Judge agreement measured overall, not per system | Judge biased toward one system's style or model family | Per-system κ against a human subset | Human-labelled calibration subset, refreshed |
| F8 | MRR used for a multi-document task | High MRR, incomplete answers | Metric stops at the first hit | Recall@k or nDCG@k | Metric chosen from the consumer table (§1.6) |
| F9 | Eval queries don't look like traffic | Great offline, poor online | Synthetic or hand-written queries only | Sample real queries and label them; keep synthetic as a separate slice | Production query sampling in the eval pipeline |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "What's the right metric for the retriever in our RAG system?"</b></summary>

**Initial Prompt.** A design review for a support-docs RAG bot that puts 8 chunks in the context.

**L5 Answer.** "nDCG@10; it's the standard."

**Why L5 Fails in Production.** It's the standard for a 10-result UI page. The consumer here is an LLM reading 8 chunks, so what matters is whether the evidence is anywhere in those 8.

**L7 Principal Defense.** "I'd pick the metric from the consumer. The headline is **Recall@8**, plus the **zero-recall rate** (queries where nothing relevant reached the context), since those produce wrong answers or refusals. Precision@8 is a secondary metric for token cost and distraction. If there's a re-ranker, stage 1 gets Recall@N at the re-ranker's input size, and nDCG@8 measures the final order. And I'd tie it to an end-to-end check: answer accuracy with *gold* context, so we know the generator isn't the bottleneck."

**Bar-Raiser Follow-ups.**
- *"Does order inside the 8 matter?"* Some ("lost in the middle"), so measure it separately by shuffling the context order on a sample. It's second-order next to presence.
- *"What if the answer needs two documents?"* Then report Recall@8 = 1.0 (*all* needed docs present) as its own metric, because averaged recall hides partial context.

</details>

<details><summary><b>Q2 · "Dense has higher Recall@100 but lower nDCG@10 than BM25. Which is better?"</b></summary>

**Initial Prompt.** The SciFact table from §3.2.

**L5 Answer.** "BM25: it wins the main metric."

**Why L5 Fails in Production.** There is no main metric without a consumer. As a candidate generator for a re-ranker, dense's higher R@100 (0.925 vs 0.905) is the relevant number.

**L7 Principal Defense.** "It depends on the pipeline. Single stage, BM25 is better at the top (0.671 vs 0.645 nDCG@10). Two-stage with a re-ranker over the top 100, dense's candidate set contains more of the evidence, so the ceiling is higher. But the measured answer is neither: the hybrid beats both on every column (0.726 nDCG@10, 0.958 R@100), because lexical and dense errors are partly uncorrelated. I'd check that with per-query scatter, and the paired bootstrap says the hybrid gain over BM25 is +0.055 with CI [+0.030, +0.079] (06.4)."

**Bar-Raiser Follow-ups.**
- *"Why are the errors uncorrelated?"* BM25 nails exact rare terms (gene names, numbers). Dense handles paraphrase. SciFact has both.
- *"Would you tune the 0.3/0.7 weight on test?"* No. It was chosen on train queries (04.2). Tuning on test inflates the number you report.

</details>

<details><summary><b>Q3 · "Our new retriever scores worse on the eval set, but users seem to like it. What's going on?"</b></summary>

**Initial Prompt.** A team upgraded embeddings; offline nDCG dropped from 0.62 to 0.55.

**L5 Answer.** "Trust the offline eval; roll back."

**Why L5 Fails in Production.** If the qrels were built by labelling the old system's results, the new system is penalized for every relevant document the old one missed. §3.1 shows this can *reverse* a comparison: 0.797 vs 0.293 with complete labels became 0.087 vs 0.366 on the old pool.

**L7 Principal Defense.** "First check judged@10 for both systems. If the new system's is much lower, the eval is measuring label coverage, not quality. Then judge the documents the new system adds to its top-10 (a small, cheap batch), and re-score both systems on the merged qrels. Only then compare, with a paired test. If an LLM does the labelling, I'd spot-check it with humans on exactly these new documents, because that's where a judge's bias would decide the outcome. Going forward, every candidate system gets re-pooled before evaluation."

**Bar-Raiser Follow-ups.**
- *"Condensed lists?"* They remove the penalty but can't credit the new documents. Here they'd score the new system exactly like the old one.
- *"How deep should the pool be?"* At least the context budget, ideally 2×, for every system being compared.

</details>

<details><summary><b>Q4 · "Why exponential gain in nDCG, and when does it matter?"</b></summary>

**Initial Prompt.** A team with graded labels (0–3) asks which nDCG to use.

**L5 Answer.** "They're the same."

**Why L5 Fails in Production.** They're the same only on binary labels. With grades, exponential gain makes demoting the best document much costlier: 0.710 vs 0.797 for the same swap (§1.5).

**L7 Principal Defense.** "Gain encodes how much better 'perfect' is than 'partially relevant'. With 2^rel − 1, a 3 is worth 7× a 1. With linear gain it's 3×. Pick the one that matches the product. For a support bot where one exact procedure document answers the question and 'related' docs barely help, exponential is right. Then pin it in the harness and report it, because leaderboards (BEIR via pytrec_eval) typically use the label value directly, and numbers across conventions aren't comparable."

**Bar-Raiser Follow-ups.**
- *"Do graded labels pay for themselves?"* For re-ranker training (LambdaMART uses ΔnDCG with these gains, 04.3), yes. For a pass/fail RAG eval, binary is cheaper and more consistent between labellers.

</details>

<details><summary><b>Q5 · "Mean nDCG@10 improved by 0.05. Is that real, and is it the right improvement?"</b></summary>

**Initial Prompt.** The hybrid vs BM25 result on 300 queries.

**L5 Answer.** "0.05 is a big jump; it's real."

**Why L5 Fails in Production.** Per-query nDCG has std ≈ 0.39, so each system's mean has a standard error of ≈ 0.023. Whether +0.05 is real depends on the *paired* variance, which wasn't computed. And "the right improvement" depends on where it happened.

**L7 Principal Defense.** "Two questions. **Real?** Use a paired bootstrap over queries (resample query IDs, recompute the mean difference) and a sign-flip permutation test. In 06.4, +0.0545 has a 95% CI of [+0.030, +0.079], and none of 10,000 sign flips was as extreme. **Right?** Look at *where* it came from: the zero-score bucket fell from 17.7% to 12.7%, so the gain includes rescued queries, which is the user-visible kind. I'd also slice by query type (claims with numbers, negations) to make sure no slice regressed."

**Bar-Raiser Follow-ups.**
- *"Why not a t-test?"* Per-query nDCG is bimodal and bounded. The bootstrap makes no normality assumption, and with 300 paired queries both usually agree anyway.
- *"Multiple metrics, multiple slices?"* Then correct for multiple comparisons, or pre-register one primary metric.

</details>

<details><summary><b>Q6 · "Can we use an LLM to label relevance instead of humans?"</b></summary>

**Initial Prompt.** Labelling budget for a 500-query eval set.

**L5 Answer.** "Yes, LLMs are as good as humans now."

**Why L5 Fails in Production.** That's true in some published settings, not automatically in yours, and the judge's errors land directly inside every metric you'll report.

**L7 Principal Defense.** "Yes, with calibration. The economics are overwhelming: ~6,000 pooled judgments cost about $0.50 with a Haiku-class model vs ~50 human-hours. The protocol: (1) a human-labelled subset of ~300–500 query-document pairs, stratified across systems and score bands. (2) Cohen's κ between the judge and humans, compared with human-human κ (06.3). (3) A **per-system** agreement check, because a judge that prefers one retriever's style biases the comparison. (4) A rubric prompt with the relevance definition and examples, versioned with the qrels. Then the LLM labels at scale, humans re-audit a sample every time the judge model or prompt changes."

**Bar-Raiser Follow-ups.**
- *"Same model family as the generator?"* Avoid it if you can. Self-preference bias is documented for LLM judges.
- *"What κ is good enough?"* Close to the human-human κ on the same task. If humans only reach 0.6, demanding 0.9 from the judge is meaningless.

</details>

<details><summary><b>Q7 · "We have no labelled queries. How do we evaluate retrieval at all?"</b></summary>

**Initial Prompt.** A new RAG product on an internal wiki.

**L5 Answer.** "Generate questions from documents with an LLM and check that the source document comes back."

**Why L5 Fails in Production.** That's a reasonable start, but synthetic questions copy the document's wording, which flatters lexical retrieval, and they don't look like user traffic.

**L7 Principal Defense.** "Three tiers. (1) **Synthetic known-item queries** (generate a question per chunk, expect that chunk back), with prompts that force paraphrase and remove exact terms. It's cheap and catches indexing and chunking bugs, but it's a separate slice, not the headline. (2) **Real queries from logs**, sampled, with the top-k from every candidate system judged by an LLM calibrated on a human subset. That's the headline metric. (3) **Implicit signals** (citation clicks, reformulations within 60 s, thumbs-down) as online A/B metrics. Day one is tier 1 plus 100 human-labelled real queries, growing weekly."

**Bar-Raiser Follow-ups.**
- *"How many queries for a stable estimate?"* With per-query std ≈ 0.4, paired comparisons on 200–300 queries resolve differences of ~0.03–0.05 (06.4).
- *"What do reformulations tell you?"* A rephrase within a minute is a weak negative label for the first result list.

</details>

<details><summary><b>Q8 · "MRR or MAP for our FAQ bot?"</b></summary>

**Initial Prompt.** One FAQ entry answers each question; the bot shows the top answer.

**L5 Answer.** "MAP, because it considers all relevant documents."

**Why L5 Fails in Production.** There's one relevant document per query and the user sees one result, so MAP's extra machinery adds nothing, and Precision@1 is the actual user experience.

**L7 Principal Defense.** "With exactly one relevant document, AP = RR, so MAP = MRR. The real question is whether to report MRR or Precision@1. The bot acts on the top-1 only, so **P@1** is the user-facing metric and MRR is a diagnostic that also credits near-misses at ranks 2–3. Those are useful if we add a 'did you mean…' list. §3.1 shows how MRR and Recall@5 can pick opposite winners, so the metric has to come from the UI."

**Bar-Raiser Follow-ups.**
- *"And if some questions have no FAQ answer?"* Then it's also a classification problem: measure abstention precision and recall like OOS detection (06.1), not just ranking.

</details>

---

## 7. Invariants Checklist

- [ ] The retrieval metric is chosen from the consumer: Recall@k_context for LLM context, Recall@N for re-ranker input, nDCG@k for UI pages, P@1/MRR for top-1 actions.
- [ ] Every eval result records the system version, index snapshot, `qrels_version`, `k_context` and gain convention.
- [ ] Per-query metric vectors are stored, never only means. The zero-recall rate is reported next to the mean.
- [ ] Two implementations agree (ours vs pytrec_eval/sklearn) before a harness is trusted.
- [ ] Candidate systems are re-pooled before comparison, and judged@k is reported per system.
- [ ] LLM-produced qrels have per-system κ against a human subset, refreshed when the judge model or prompt changes.
- [ ] Comparisons use paired bootstrap or permutation tests over queries (06.4).
- [ ] Retrieval is evaluated separately from generation (generation with gold context is its own eval).
- [ ] Eval queries are sampled from real traffic; synthetic queries are a separate slice.

---

## 8. References

1. K. Järvelin, J. Kekäläinen, *Cumulated Gain-Based Evaluation of IR Techniques*, ACM TOIS 20(4), 2002. https://doi.org/10.1145/582415.582418
2. C. Buckley, E. Voorhees, *Retrieval Evaluation with Incomplete Information* (bpref), SIGIR 2004. https://doi.org/10.1145/1008992.1009000
3. T. Sakai, *Alternatives to Bpref* (condensed lists), SIGIR 2007.
4. A. Moffat, J. Zobel, *Rank-Biased Precision for Measurement of Retrieval Effectiveness*, ACM TOIS 27(1), 2008. https://doi.org/10.1145/1416950.1416952
5. O. Chapelle, D. Metzler, Y. Zhang, P. Grinspan, *Expected Reciprocal Rank for Graded Relevance*, CIKM 2009. https://doi.org/10.1145/1645953.1646033
6. O. Chapelle, T. Joachims, F. Radlinski, Y. Yue, *Large-Scale Validation and Analysis of Interleaved Search Evaluation*, ACM TOIS 30(1), 2012. https://doi.org/10.1145/2094072.2094074
7. N. Thakur et al., *BEIR: A Heterogeneous Benchmark for Zero-shot Evaluation of Information Retrieval Models*, NeurIPS Datasets & Benchmarks 2021. https://arxiv.org/abs/2104.08663
8. P. Thomas, S. Spielman, N. Craswell, B. Mitra, *Large Language Models Can Accurately Predict Searcher Preferences*, SIGIR 2024. https://arxiv.org/abs/2309.10621
9. S. Upadhyay et al., *UMBRELA: UMbrela is the (Open-Source Reproduction of the) Bing RELevance Assessor*, 2024. https://arxiv.org/abs/2406.06519
10. S. Es, J. James, L. Espinosa-Anke, S. Schockaert, *RAGAS: Automated Evaluation of Retrieval Augmented Generation*, 2023. https://arxiv.org/abs/2309.15217
11. J. Saad-Falcon, O. Khattab, C. Potts, M. Zaharia, *ARES: An Automated Evaluation Framework for Retrieval-Augmented Generation Systems*, 2023. https://arxiv.org/abs/2311.09476
12. N. Liu et al., *Lost in the Middle: How Language Models Use Long Contexts*, TACL 2024. https://arxiv.org/abs/2307.03172
13. NIST, `trec_eval`. https://github.com/usnistgov/trec_eval
14. A. Ng, *Improve Agentic Performance with Evals and Error Analysis, Part 1*, The Batch, 2025-10-15. https://www.deeplearning.ai/the-batch/improve-agentic-performance-with-evals-and-error-analysis-part-1/
15. D. Wadden et al., *Fact or Fiction: Verifying Scientific Claims* (SciFact), EMNLP 2020. https://aclanthology.org/2020.emnlp-main.609/
