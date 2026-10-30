# 04.3 · Learning to Rank: Pointwise, Pairwise, Listwise, Cross-Encoders & LambdaMART

> **Folder 04 · Classical-to-Neural Information Retrieval & Ranking Algorithms**
> **Measured on:** LightGBM 4.7.0 (`LGBMRanker`, lambdarank), PyTorch 2.14.1 (cross-encoder on the RTX 3050 GPU for bulk scoring; CPU for latency), transformers 5.22.0, NumPy 2.5.4, Windows 11.
> **Real data:** SciFact (809 train / 300 test claims), candidates from 04.2's hybrid retriever; `cross-encoder/ms-marco-MiniLM-L6-v2`. The loss comparison uses seeded synthetic ranking data.
> **Design sources:** Burges (*From RankNet to LambdaRank to LambdaMART*, MSR-TR-2010-82), Cao et al. (ListNet, ICML 2007), Järvelin & Kekäläinen (nDCG, 2002), Nogueira & Cho (BERT reranking, 2019), the LightGBM ranking docs. Full list in §8.

---

## 0. Orientation: The Second Stage Decides What the LLM Reads

In RAG, the generator only sees the top 5–10 passages. **Ranking quality at the top is the product.** The two-stage pattern:

```text
query ─► stage 1: recall (BM25 + dense, fused)  → top 50–100 candidates     (cheap per document, 04.1–04.2)
      ─► stage 2: precision (rerank)            → top 5–10 to the LLM        (expensive per candidate)
```

This file measures the stage-2 options on SciFact's top-50 hybrid candidates (test recall@50 = **0.944**, so the right document is almost always present, and ordering is the problem):

```text
TEST reranking of the top-50            nDCG@10
stage 1 only: RRF hybrid                 0.6929
dense MiniLM order                       0.6470
LambdaMART (8 cheap features)            0.7191     0.51 ms per query (CPU, 20 candidates)
cross-encoder (zero-shot MS MARCO)       0.6818     897–1905 ms per query (CPU, 20 candidates)
LambdaMART + cross-encoder feature       0.7212
```

The headline is uncomfortable, and that makes it useful. **A popular off-the-shelf cross-encoder made the ranking *worse* (0.682 < 0.693) on this domain and cost ~2,000× more CPU time than a LambdaMART model trained on our own labels (0.719).** Domain fit and labelled data beat model size. This file builds the theory behind both.

### The backend-engineer bridge

| You already know | Ranking equivalent |
|---|---|
| A sort comparator | **Pairwise ranking loss** (learn "a before b") |
| Weighting incidents by customer impact | **LambdaRank's ΔNDCG weights**: errors at the top of the list matter more |
| A cheap filter before an expensive check | **Two-stage retrieval** (recall, then rerank) |
| Feature flags in a scoring rule | **LambdaMART features** (BM25, cosine, ranks, freshness, clicks) |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 nDCG and why the top positions dominate | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Pointwise losses | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.3 Pairwise: RankNet | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Listwise: ListNet | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.5 LambdaRank and LambdaMART | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Cross-encoders: full attention over (query, document) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Domain shift: when a reranker hurts | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Feature design for LambdaMART in RAG | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Reranking cost and latency budgets | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 LLM rerankers (pointwise, listwise prompting) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Ranking-metric optimization theory (consistency, surrogate bounds) | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 nDCG and why the top positions dominate `[MUST-KNOW: Core AI Engineer Edge]`

```text
DCG@k = Σ_{r=1..k} (2^{rel_r} − 1) / log₂(r + 1)          nDCG@k = DCG@k / ideal DCG@k ∈ [0, 1]
discount: rank 1 → 1.000, rank 2 → 0.631, rank 5 → 0.387, rank 10 → 0.289
```

The logarithmic discount means a relevant document's contribution drops by 37% from rank 1 to rank 2. So *swapping* the same pair of labels costs very differently depending on where they are:

```text
positions  1<->2 : |delta DCG@40| = 2.583
positions 21<->22: |delta DCG@40| = 0.022
```

That's a **117×** difference for the same mistake. Any loss that treats all mis-ordered pairs equally spends its effort in the wrong place. (Folder 06 covers the metric in depth: graded relevance, ties, Recall@k, MRR, MAP.)

### 1.2 Pointwise losses `[GOOD-TO-KNOW: Architectural Literacy]`

Treat ranking as regression or classification on each (query, document) independently: predict the label, sort by prediction. MSE or log-loss. It's simple, any model works, and probabilities can be calibrated (useful when the score must mean something, like "show only answers above P = 0.7"). The weakness: it optimizes absolute scores, while ranking only needs the order *within a query*, and it gives equal weight to the top and the bottom of the list.

### 1.3 Pairwise: RankNet `[MUST-KNOW: Core AI Engineer Edge]`

For each pair with yᵢ > yⱼ in the same query, model P(i ranked above j) = σ(sᵢ − sⱼ), and minimize log(1 + exp(−(sᵢ − sⱼ))). The gradient on the scores is

```text
λᵢⱼ = −σ(−(sᵢ − sⱼ))        push sᵢ up and sⱼ down, with strength ≈ how wrong the pair currently is
∂L/∂sᵢ = Σ_{j: yᵢ>yⱼ} λᵢⱼ − Σ_{j: yⱼ>yᵢ} λⱼᵢ
```

It learns order directly and is invariant to per-query score offsets. On our synthetic ranking data it was the best of the four losses with a linear scorer (test NDCG@10 **0.8728**). But it counts every mis-ordered pair equally, including pairs deep in the list that no user sees (§1.1).

### 1.4 Listwise: ListNet `[GOOD-TO-KNOW: Architectural Literacy]`

Turn each query's scores into a probability distribution (softmax, the "top-one probability") and minimize cross-entropy against the label distribution (softmax of the labels). It's the InfoNCE pattern of 04.2 with graded targets. It considers the whole list at once (test **0.8687** here). Its weakness is the same as RankNet's: no explicit focus on the top ranks.

### 1.5 LambdaRank and LambdaMART `[MUST-KNOW: Core AI Engineer Edge]`

Burges' observation: you don't need a differentiable NDCG. You only need *gradients* (the "lambdas") that point in a direction that improves it. Take RankNet's pairwise gradient and scale it by how much NDCG would change if the pair were swapped at the current ranking:

```text
λᵢⱼ^Lambda = λᵢⱼ^RankNet · |ΔNDCG_ij|          (ΔNDCG uses the current positions of i and j)
```

Pairs at the top get large weights, and pairs below the cutoff get almost none. **LambdaMART** plugs these lambdas into gradient-boosted trees (02.2) as the per-document gradients (with matching second-order terms), which is LightGBM's `objective="lambdarank"`. It's been the dominant learning-to-rank method in production search for over a decade.

What the synthetic experiment shows honestly: with a *linear* scorer and the same features, LambdaRank (0.8647) was no better than pointwise (0.8644) and slightly below RankNet (0.8728). With limited capacity, all losses converge to similar directions. LambdaRank's advantage appears with **flexible models**, where capacity can be spent on getting the top right: trees (LambdaMART), and on real data. On SciFact, LambdaMART lifted the hybrid ranking from 0.6929 to **0.7191**.

### 1.6 Cross-encoders: full attention over (query, document) `[MUST-KNOW: Core AI Engineer Edge]`

```text
"[CLS] query tokens [SEP] document tokens [SEP]" ──► BERT-style encoder ──► linear head on [CLS] ──► relevance logit
```

Every query token attends to every document token in every layer, so the model can check whether *this* claim is supported by *this* abstract: negation, the specific entity, the direction of an effect. Bi-encoders can't do that, because they compress each side independently (04.2 §1.1). Nogueira & Cho (2019) showed BERT cross-encoders reranking BM25 candidates set new highs on MS MARCO. The cost is one full forward pass per pair. `ms-marco-MiniLM-L6-v2` (6 layers, the same size as our bi-encoder) is trained on MS MARCO, i.e. web search questions and Bing passages.

### 1.7 Domain shift: when a reranker hurts `[MUST-KNOW: Core AI Engineer Edge]`

On SciFact, the zero-shot MS MARCO cross-encoder scored **0.6818**, below the RRF hybrid it was reranking (0.6929). Likely reasons, each testable with error analysis:

- **Task mismatch.** MS MARCO pairs a *question* with an *answer passage*. SciFact pairs a *claim* with an abstract that may support *or contradict* it. A passage contradicting a claim is still relevant here, while the model learned "does this passage answer the question?".
- **Domain vocabulary.** Biomedical abstracts vs web pages.
- **Length.** Abstracts truncated at 256 tokens (query plus document) lose evidence that BM25 and the bi-encoder can still see in their own indexes.

The measured fix in this file is cheap: use the cross-encoder score as **one feature** in a LambdaMART model trained on in-domain labels (0.7212, the best result). The model learns how much to trust the cross-encoder relative to BM25 and cosine. The structural fix is to fine-tune the cross-encoder on in-domain pairs. **Never ship a reranker without measuring it against the ranking it replaces, on your own queries.**

### 1.8 Feature design for LambdaMART in RAG `[MUST-KNOW: Core AI Engineer Edge]`

The listing's eight features are cheap and already computed by stage 1:

| Feature | Why it helps |
|---|---|
| BM25 score, dense cosine | Two complementary relevance signals |
| BM25 rank, dense rank | Rank-normalized versions, comparable across queries |
| RRF score | The stage-1 consensus |
| Document length | Interacts with the BM25 length normalization |
| Query–title token Jaccard | Titles are high-precision evidence |
| Query length | Lets the model weigh lexical vs semantic signals by query type |

Production adds behavioural and business features: click-through and dwell priors (debiased for position), freshness, authority, document-quality scores, user/tenant affinity, and, when affordable, a cross-encoder or LLM-judge score. Train on in-domain labels with query-grouped splits (no query in both train and test), and early-stop on validation nDCG@10, as the listing does with 20% of training queries held out.

### 1.9 Reranking cost and latency budgets `[MUST-KNOW: Core AI Engineer Edge]`

```text
cross-encoder, 1 thread(s): p50 1905 ms per query (20 pairs, <=256 tokens)
cross-encoder, 4 thread(s): p50 897 ms per query (20 pairs, <=256 tokens)
LambdaMART, 1 thread: 0.51 ms per query (20 candidates)
cross-encoder scored 55,450 pairs on cuda in 137.7 s      (≈ 400 pairs/s, fp16, laptop GPU)
```

A cross-encoder over 20 full abstracts costs about **1–2 s per query on CPU**: each pair is a ~256-token forward pass, about 20× the tokens of a short router query (02.3). On a laptop GPU it's ~2.5 ms per pair. Budget rules:

- Rerank only as deep as the metric needs (nDCG@10 needs a good top 10, so 20–50 candidates).
- Truncate documents to the passage most likely to matter (rerank *chunks*, not whole documents).
- Batch pairs on a GPU.
- Cache scores for repeated (query, chunk) pairs.
- Consider a cheaper LambdaMART-first stage that only sends uncertain queries to the cross-encoder: a cascade again (Folder 07).

### 1.10 LLM rerankers (pointwise, listwise prompting) `[GOOD-TO-KNOW: Architectural Literacy]`

LLMs can rerank, either pointwise (score each passage, possibly with yes/no log-probs) or listwise (give the model 20 passages and ask for a permutation, RankGPT-style, with sliding windows for longer lists). They're strong zero-shot across domains, but they cost a generation per query (or per window), are sensitive to passage order in the prompt, and score inconsistently across calls without calibration (01.3 §1.13). In production they work best as the *last* stage on a short list, or as a teacher whose judgments train a cheap cross-encoder or LambdaMART model (distillation), which brings latency back to milliseconds.

### 1.11 Ranking-metric optimization theory `[SKIP: Academic/Research Only]`

Consistency of surrogate losses for NDCG, the theoretical justification of lambda gradients as an implicit cost function, and listwise generalization bounds. Production needs §1.1 (the metric's shape) and §1.5 (weight the gradients by the metric's sensitivity).

---

## 2. Where It Beats an LLM in Production

| Need | LambdaMART / small cross-encoder | LLM reranker |
|---|---|---|
| Rerank 50 candidates per query at high QPS | LambdaMART 0.51 ms per query (CPU); a cross-encoder ~2.5 ms per pair on a GPU | A generation per query or window; hundreds of ms to seconds |
| In-domain accuracy | LambdaMART on in-domain labels: 0.719 (vs 0.693 stage-1) | Strong zero-shot, but unmeasured until you run the eval |
| Stable, auditable scores | Deterministic, with feature importances and SHAP | Order-sensitive and call-to-call variance |
| Cost scaling | Linear in candidates, with tiny constants | Linear in tokens × candidates, at LLM prices |

Use LLM judgments where they shine: **labelling** training data for the cheap rankers (audited), and final-stage verification on a handful of passages for high-value queries.

---

## 3. Production Code Blueprint

### 3.1 Four ranking losses from first principles

```python
"""ltr_losses_from_scratch.py - pointwise, pairwise (RankNet), listwise (ListNet) and LambdaRank, from first principles.

Synthetic but realistic learning-to-rank data: 400 queries x 40 candidates, 9 features, graded labels 0-3
assigned per query from a hidden scoring function. One linear scorer, four losses, same optimizer budget.
  1. Why |delta NDCG| matters: swapping ranks 1<->2 vs 20<->21 for the same label pair.
  2. Test NDCG@10 per loss.
"""
import numpy as np

rng = np.random.default_rng(121)
NQ, ND, F = 400, 40, 9


def make():
    X = rng.standard_normal((NQ, ND, 8))
    X = np.concatenate([X, (X[..., 1] * X[..., 2])[..., None]], -1)  # give the linear model the interaction feature
    true = 1.5 * X[..., 0] + X[..., 8] + 0.8 * np.maximum(X[..., 3], 0) - 0.5 * X[..., 4] ** 2 + 0.7 * rng.standard_normal((NQ, ND))
    q = np.quantile(true, [0.65, 0.85, 0.95], axis=1).T             # per-query cut points
    y = (true[..., None] > q[:, None, :]).sum(-1).astype(float)    # 0..3
    return X, y


X, Y = make()
tr, te = slice(0, 300), slice(300, 400)


def dcg_at(labels_in_rank_order, k=10):
    g = (2 ** labels_in_rank_order[:k] - 1)
    return float(np.sum(g / np.log2(np.arange(2, len(g) + 2))))


def ndcg(scores, labels, k=10):
    ideal = dcg_at(np.sort(labels)[::-1], k)
    return dcg_at(labels[np.argsort(-scores, kind="stable")], k) / ideal if ideal > 0 else 0.0


print("== 1. |delta NDCG| of swapping a label-3 and a label-0 document ==")
lab = np.array([3, 0] + [1] * 18 + [3, 0] + [0] * 18, float)
base = dcg_at(lab, 40)
for i, j in ((0, 1), (20, 21)):
    sw = lab.copy()
    sw[[i, j]] = sw[[j, i]]
    print(f"positions {i + 1:>2}<->{j + 1:<2}: |delta DCG@40| = {abs(dcg_at(sw, 40) - base):.3f}")
print("RankNet treats both pairs identically; LambdaRank weights each pair's gradient by this delta.")


def grads(w, loss, Xq, yq):
    s = Xq @ w
    if loss == "pointwise (MSE)":
        return Xq.T @ (s - yq) / len(yq)
    if loss == "listwise (ListNet)":
        p_true = np.exp(yq) / np.exp(yq).sum()
        e = np.exp(s - s.max())
        return Xq.T @ (e / e.sum() - p_true)
    i, j = np.nonzero(yq[:, None] > yq[None, :])                    # all pairs with y_i > y_j
    sig = 1 / (1 + np.exp(s[i] - s[j]))                             # dL/ds_i of log(1 + exp(-(s_i - s_j))), sign flipped
    lam = sig
    if loss == "LambdaRank":
        order = np.argsort(-s, kind="stable")
        rank = np.empty(len(s), int)
        rank[order] = np.arange(len(s))
        ideal = dcg_at(np.sort(yq)[::-1], 10)
        gain = 2 ** yq - 1
        disc = lambda r: np.where(r < 10, 1 / np.log2(r + 2), 0.0)
        delta = np.abs((gain[i] - gain[j]) * (disc(rank[i]) - disc(rank[j]))) / ideal
        lam = sig * delta
    g_s = np.zeros(len(s))
    np.add.at(g_s, i, -lam)
    np.add.at(g_s, j, lam)
    return Xq.T @ g_s / max(len(i), 1)


print("\n== 2. one linear scorer, four losses (Adam, 150 epochs over 300 train queries) ==")
res = {}
for loss in ("pointwise (MSE)", "pairwise (RankNet)", "listwise (ListNet)", "LambdaRank"):
    w = np.zeros(F)
    m, v = np.zeros(F), np.zeros(F)
    t = 0
    for epoch in range(150):
        for qi in rng.permutation(300):
            t += 1
            g = grads(w, loss, X[qi], Y[qi])
            m = 0.9 * m + 0.1 * g
            v = 0.999 * v + 0.001 * g * g
            w -= 0.01 * (m / (1 - 0.9 ** t)) / (np.sqrt(v / (1 - 0.999 ** t)) + 1e-8)
    res[loss] = np.mean([ndcg(X[q] @ w, Y[q]) for q in range(300, 400)])
    print(f"{loss:22s} test NDCG@10 {res[loss]:.4f}")
print(f"{'random order':22s} test NDCG@10 {np.mean([ndcg(rng.standard_normal(ND), Y[q]) for q in range(300, 400)]):.4f}")
assert res["LambdaRank"] >= res["pointwise (MSE)"] - 0.005
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. |delta NDCG| of swapping a label-3 and a label-0 document ==
positions  1<->2 : |delta DCG@40| = 2.583
positions 21<->22: |delta DCG@40| = 0.022
RankNet treats both pairs identically; LambdaRank weights each pair's gradient by this delta.

== 2. one linear scorer, four losses (Adam, 150 epochs over 300 train queries) ==
pointwise (MSE)        test NDCG@10 0.8644
pairwise (RankNet)     test NDCG@10 0.8728
listwise (ListNet)     test NDCG@10 0.8687
LambdaRank             test NDCG@10 0.8647
random order           test NDCG@10 0.2095

ALL ASSERTIONS PASSED
```

### 3.2 Reranking SciFact: LambdaMART vs a cross-encoder vs both

```python
"""rerank_cross_encoder_and_lambdamart.py - second-stage reranking on SciFact: LambdaMART features vs a cross-encoder.

Stage 1: hybrid candidates (RRF of BM25 + dense MiniLM), top-50 per claim.
Stage 2 options:
  (a) LightGBM LambdaMART on cheap features (BM25, cosine, ranks, lengths, overlap), trained on TRAIN claims;
  (b) cross-encoder ms-marco-MiniLM-L6-v2 (query and document read together), zero-shot from MS MARCO;
  (c) LambdaMART with the cross-encoder score as one more feature.
Also: CPU latency of reranking 20 candidates with the cross-encoder.
"""
import json
import math
import os
import re
import time
from collections import defaultdict

import lightgbm as lgb
import numpy as np
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

DL, DATA = os.environ["KB_DL"], os.environ["KB_DATA"]
D = os.path.join(DL, "scifact", "x", "scifact")
docs = [json.loads(l) for l in open(os.path.join(D, "corpus.jsonl"), encoding="utf-8")]
queries = {q["_id"]: q["text"] for q in map(json.loads, open(os.path.join(D, "queries.jsonl"), encoding="utf-8"))}
texts = [d["title"] + " " + d["text"] for d in docs]
doc_ids = [d["_id"] for d in docs]
Z = np.load(os.path.join(DATA, "scifact_minilm.npz"))
E_doc, E_q = Z["E_doc"], Z["E_q"]
qpos = {str(q): i for i, q in enumerate(Z["qids"])}


def load_qrels(split):
    q = defaultdict(dict)
    for line in list(open(os.path.join(D, "qrels", f"{split}.tsv"), encoding="utf-8"))[1:]:
        a, b, s = line.split()
        q[a][b] = int(s)
    return q


qr = {"train": load_qrels("train"), "test": load_qrels("test")}
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
for i, t in enumerate(texts):
    toks = tokenize(t)
    dl[i] = len(toks)
    for w in toks:
        post[w][i] += 1
P = {w: (np.fromiter(p.keys(), int), np.fromiter(p.values(), float)) for w, p in post.items()}
N, avgdl = len(docs), dl.mean()
idf = {w: math.log(1 + (N - len(d) + 0.5) / (len(d) + 0.5)) for w, (d, _) in P.items()}
title_toks = [set(tokenize(d["title"])) for d in docs]


def bm25(q):
    acc = np.zeros(N)
    for w in set(tokenize(q)):
        if w in P:
            d, tf = P[w]
            acc[d] += idf[w] * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * dl[d] / avgdl))
    return acc


def candidates(split, k=50):
    out = []
    for qid in sorted(qr[split], key=int):
        sb, sd = bm25(queries[qid]), E_doc @ E_q[qpos[qid]]
        rb, rd = np.argsort(-sb, kind="stable"), np.argsort(-sd, kind="stable")
        rank_b, rank_d = np.empty(N), np.empty(N)
        rank_b[rb], rank_d[rd] = np.arange(N), np.arange(N)
        rrf = 1 / (60 + rank_b + 1) + 1 / (60 + rank_d + 1)
        cand = np.argsort(-rrf, kind="stable")[:k]
        qt = set(tokenize(queries[qid]))
        feats = np.c_[sb[cand], sd[cand], rank_b[cand], rank_d[cand], rrf[cand], dl[cand],
                      [len(qt & title_toks[j]) / (len(qt | title_toks[j]) or 1) for j in cand], np.full(k, len(qt))]
        labels = np.array([qr[split][qid].get(doc_ids[j], 0) for j in cand])
        out.append((qid, cand, feats, labels))
    return out


C_tr, C_te = candidates("train"), candidates("test")
recall50 = np.mean([lab.sum() / len(qr["test"][q]) for q, _, _, lab in C_te])
print(f"stage 1: RRF(BM25, dense) top-50 for {len(C_tr)} train / {len(C_te)} test claims; test recall@50 = {recall50:.4f}")

dev = "cuda" if torch.cuda.is_available() else "cpu"
cdir = os.path.join(DL, "models", "ce-minilm")
ctok = AutoTokenizer.from_pretrained(cdir)
ce = AutoModelForSequenceClassification.from_pretrained(cdir, use_safetensors=True).eval().to(dev)


@torch.inference_mode()
def ce_scores(q, cand, device=dev, bs=50):
    out = []
    for i in range(0, len(cand), bs):
        e = ctok([q] * len(cand[i:i + bs]), [texts[j] for j in cand[i:i + bs]], padding=True, truncation="only_second",
                 max_length=256, return_tensors="pt").to(device)
        with torch.autocast("cuda", dtype=torch.float16, enabled=device == "cuda"):
            out.append(ce.to(device)(**e).logits.float().squeeze(-1).cpu().numpy())
    return np.concatenate(out)


t0 = time.perf_counter()
CE_tr = [ce_scores(queries[q], cand) for q, cand, _, _ in C_tr]
CE_te = [ce_scores(queries[q], cand) for q, cand, _, _ in C_te]
print(f"cross-encoder scored {sum(len(c) for _, c, _, _ in C_tr + C_te):,} pairs on {dev} in {time.perf_counter() - t0:.1f} s")


def ndcg10(order, labels, qid, split):
    gains = labels[order][:10]
    ideal = sum(1 / math.log2(r + 2) for r in range(min(10, len(qr[split][qid]))))
    return float(np.sum(gains / np.log2(np.arange(2, len(gains) + 2))) / ideal)


def fit_ranker(extra):
    Xs = [np.c_[f, ce_s] if extra else f for (_, _, f, _), ce_s in zip(C_tr, CE_tr)]
    ys = [lab for *_, lab in C_tr]
    cut = int(0.8 * len(Xs))
    rk = lgb.LGBMRanker(objective="lambdarank", n_estimators=500, learning_rate=0.05, num_leaves=15,
                        min_child_samples=20, verbose=-1, num_threads=1, seed=0)
    rk.fit(np.vstack(Xs[:cut]), np.concatenate(ys[:cut]), group=[len(y) for y in ys[:cut]],
           eval_set=[(np.vstack(Xs[cut:]), np.concatenate(ys[cut:]))], eval_group=[[len(y) for y in ys[cut:]]],
           eval_at=[10], callbacks=[lgb.early_stopping(50, verbose=False)])
    return rk


rk_plain, rk_ce = fit_ranker(False), fit_ranker(True)
rows = defaultdict(list)
for (qid, cand, f, lab), ce_s in zip(C_te, CE_te):
    rows["stage 1 only: RRF hybrid"].append(ndcg10(np.arange(len(cand)), lab, qid, "test"))
    rows["dense MiniLM order"].append(ndcg10(np.argsort(-f[:, 1], kind="stable"), lab, qid, "test"))
    rows["LambdaMART (8 cheap features)"].append(ndcg10(np.argsort(-rk_plain.predict(f), kind="stable"), lab, qid, "test"))
    rows["cross-encoder (zero-shot MS MARCO)"].append(ndcg10(np.argsort(-ce_s, kind="stable"), lab, qid, "test"))
    rows["LambdaMART + cross-encoder feature"].append(ndcg10(np.argsort(-rk_ce.predict(np.c_[f, ce_s]), kind="stable"), lab, qid, "test"))
print(f"\n{'TEST reranking of the top-50':38s} {'nDCG@10':>8}")
res = {k: np.mean(v) for k, v in rows.items()}
for k, v in res.items():
    print(f"{k:38s} {v:>8.4f}")
assert res["LambdaMART + cross-encoder feature"] > res["stage 1 only: RRF hybrid"]

print("\n== CPU latency: rerank 20 candidates for one claim (fp32, one measured run) ==")
ce_cpu = ce.to("cpu")
for th in (1, 4):
    torch.set_num_threads(th)
    ts = []
    for q, cand, _, _ in C_te[:30]:
        t0 = time.perf_counter()
        ce_scores(queries[q], cand[:20], device="cpu", bs=20)
        ts.append((time.perf_counter() - t0) * 1e3)
    print(f"cross-encoder, {th} thread(s): p50 {np.percentile(ts[5:], 50):.0f} ms per query (20 pairs, <=256 tokens)")
_, _, f, _ = C_te[0]
t0 = time.perf_counter()
for _ in range(200):
    rk_plain.predict(f[:20], num_threads=1)
print(f"LambdaMART, 1 thread: {(time.perf_counter() - t0) / 200 * 1e3:.2f} ms per query (20 candidates)")
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the GPU scoring time and the latency lines, which are one measured run):

```text
stage 1: RRF(BM25, dense) top-50 for 809 train / 300 test claims; test recall@50 = 0.9443
cross-encoder scored 55,450 pairs on cuda in 137.7 s

TEST reranking of the top-50            nDCG@10
stage 1 only: RRF hybrid                 0.6929
dense MiniLM order                       0.6470
LambdaMART (8 cheap features)            0.7191
cross-encoder (zero-shot MS MARCO)       0.6818
LambdaMART + cross-encoder feature       0.7212

== CPU latency: rerank 20 candidates for one claim (fp32, one measured run) ==
cross-encoder, 1 thread(s): p50 1905 ms per query (20 pairs, <=256 tokens)
cross-encoder, 4 thread(s): p50 897 ms per query (20 pairs, <=256 tokens)
LambdaMART, 1 thread: 0.51 ms per query (20 candidates)

ALL ASSERTIONS PASSED
```

How to read it:

- **Stage-1 recall@50 = 0.944** caps what any reranker can do: 5.6% of relevant documents never reach stage 2.
- **The cross-encoder row is the cautionary result.** "State of the art" on its training distribution, worse than the cheap hybrid on ours.
- **The last row** shows the pragmatic fix: let a model trained on *your* labels decide how much to trust each signal.

---

## 4. The Andrew Ng Lens: Measure the Reranker Against What It Replaces

### 4.1 Error analysis on reranking regressions

For queries where the cross-encoder lowered nDCG, put the claim, the relevant abstract, and the passages the CE promoted side by side. Tag them: *contradiction-as-relevant* (the CE demoted an abstract that refutes the claim), *truncation* (the evidence sat past 256 tokens), *vocabulary* (biomedical terms), *label gap*. The tag counts decide the fix: fine-tune on in-domain pairs, rerank chunks instead of whole abstracts, or keep the CE as a feature only.

### 4.2 Avoidable bias vs data mismatch, for rerankers

A model that is excellent on MS MARCO and mediocre on SciFact has a **data-mismatch** problem in Ng's taxonomy, not a capacity problem. A bigger MS MARCO cross-encoder may not help. In-domain data does: LambdaMART on 809 in-domain training claims beat it. The cheapest in-domain data is often LLM-labelled (query, passage) pairs, audited on a sample, which then train or fine-tune the small reranker.

### 4.3 Evaluation-driven reranking

Every reranker change gets the same three numbers on held-out queries: nDCG@10 (precision at the top), stage-1 recall@k (the ceiling), and p50/p99 latency per query on production hardware. A reranker that improves nDCG by 0.2 points at 2,000× the latency usually isn't a win. The trade-off table should be in the design doc.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Off-the-shelf cross-encoder lowers quality | nDCG below stage 1 (0.682 vs 0.693) | Domain/task mismatch (MS MARCO QA vs claims) | Use as a feature in LambdaMART; fine-tune in-domain | Measure against the replaced ranking before launch |
| F2 | Reranking blows the latency budget | ~1–2 s per query on CPU for 20 abstracts | A full forward pass per long pair | Fewer candidates, chunk-level reranking, GPU batching, a cascade | p99 latency in the reranker eval |
| F3 | Reranker can't fix bad results | Relevant docs absent from the candidates | Stage-1 recall ceiling (0.944 at 50) | Improve stage 1 (hybrid, adapters); deeper candidate lists | Report stage-1 recall@k with every reranker result |
| F4 | LTR model looks great offline, fails online | Same queries in train and test | Query leakage across splits | Group splits by query (as in the listing) | Split by query id, and by time where relevant |
| F5 | Ranking loss improves, but user-visible quality doesn't | Gains concentrated below rank 10 | Pairwise/pointwise loss ignores the top | LambdaRank/LambdaMART weighting by ΔNDCG | Optimize and report the metric at the cutoff users see |
| F6 | Click-trained ranker reinforces position bias | Top results get clicks because they're on top | Position-biased implicit feedback | Debias (randomization, propensity weighting) | Never train on raw clicks |
| F7 | LLM reranker gives different orders for the same input | Order-sensitivity, sampling variance | Prompted listwise ranking is stochastic | Sliding windows with multiple passes; distil into a stable model | Measure ranking stability across repeated calls |
| F8 | Truncated documents rerank badly | Evidence past the max length | 256-token cap on (query + document) | Rerank chunks; the max over chunk scores | Track where in the document the evidence sits |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain LambdaMART: why the 'lambda', why the 'MART'?"</b></summary>

**Initial Prompt.** A ranking-team interview.

**L5 Answer.** "It's a gradient-boosted model for ranking that optimizes NDCG."

**Why L5 Fails in Production.** NDCG is piecewise constant in the scores, so it isn't differentiable. The answer must say how it's optimized anyway.

**L7 Principal Defense.** "Start from RankNet: for each pair with yᵢ > yⱼ, the loss log(1 + exp(−(sᵢ − sⱼ))) gives a gradient λᵢⱼ. Burges' insight was to scale each λᵢⱼ by |ΔNDCG| for swapping i and j at their current positions. You never differentiate NDCG, you just push hardest where NDCG is most sensitive, at the top. In our toy, swapping ranks 1 and 2 changes DCG 117× more than swapping 21 and 22. 'MART' means those lambdas are the per-document gradients fed to gradient-boosted regression trees, LightGBM's lambdarank objective. On SciFact, LambdaMART over eight cheap features lifted the hybrid from 0.693 to 0.719 nDCG@10, at 0.5 ms per query."

**Bar-Raiser Follow-ups.**
- *"Why didn't LambdaRank beat RankNet in your linear toy?"* With a linear scorer and the same features, all losses find similar directions, so there's no capacity to reallocate to the top. The weighting pays off with flexible models like trees.

</details>

<details><summary><b>Q2 · "We added a popular cross-encoder reranker and quality went down. How is that possible?"</b></summary>

**Initial Prompt.** `ms-marco-MiniLM-L6-v2` on a scientific-claims corpus.

**L5 Answer.** "There must be a bug; cross-encoders are always better."

**Why L5 Fails in Production.** It isn't necessarily a bug. We measured the same thing: 0.682 vs the stage-1 hybrid's 0.693 on SciFact.

**L7 Principal Defense.** "Cross-encoders learn the relevance notion of their training data. MS MARCO is 'does this web passage answer this question'. Here relevance includes abstracts that *contradict* the claim, the vocabulary is biomedical, and 256-token truncation drops evidence. Error analysis on the regressed queries will say which dominates. Immediate fix: feed the CE score as a feature into LambdaMART trained on in-domain labels (0.721, the best we measured). Structural fix: fine-tune the cross-encoder on in-domain pairs, possibly LLM-labelled and audited. Process fix: no reranker ships without beating the ranking it replaces on our held-out queries."

**Bar-Raiser Follow-ups.**
- *"Wouldn't a bigger cross-encoder fix it?"* It's a data-mismatch problem, not capacity. A bigger MS MARCO model learns the same notion of relevance. Measure before assuming.

</details>

<details><summary><b>Q3 · "Design the reranking stage for a RAG system with a 300 ms p99 budget."</b></summary>

**Initial Prompt.** CPU-only serving, ~50 candidates from hybrid retrieval.

**L5 Answer.** "Run a cross-encoder on all 50 candidates."

**Why L5 Fails in Production.** Measured on CPU: ~0.9–1.9 s for just 20 full abstracts, far over budget.

**L7 Principal Defense.** "A cascade. LambdaMART over cheap stage-1 features on all 50 candidates (~0.5 ms), which already gives most of the quality gain on SciFact (0.719). Then, for queries where its top results are close in score (uncertain), a cross-encoder on the top 5–10 *chunks* (not whole documents), with short max lengths and a cache, or on a small GPU pool. Budget it: about 45 ms per pair at 4 CPU threads for 256-token pairs, so 5 chunk pairs of ~128 tokens fit. Measure p99 with production queries, and track what fraction of traffic takes the expensive path."

**Bar-Raiser Follow-ups.**
- *"GPU?"* ~400 pairs/s for 256-token pairs in fp16 on a laptop RTX 3050. A small server GPU makes 50-candidate cross-encoding feasible at moderate QPS.

</details>

<details><summary><b>Q4 · "Pointwise, pairwise or listwise: which do you use and why?"</b></summary>

**Initial Prompt.** A learning-to-rank design question.

**L5 Answer.** "Listwise is the most advanced, so listwise."

**Why L5 Fails in Production.** The right choice depends on the model, the data and what the score is used for. In our linear experiment, the ranking was RankNet > ListNet > LambdaRank ≈ pointwise, within 1 point.

**L7 Principal Defense.** "For ranking quality at the top with flexible models: LambdaMART, which is pairwise with listwise (ΔNDCG) weighting. It won on real SciFact data. Pointwise when the score must be a *calibrated probability* (an answer-confidence threshold, or a cascade decision), possibly next to a ranker. Pairwise when labels are preferences (A better than B) rather than grades. Listwise softmax losses when training neural rankers end to end, which is the InfoNCE family (04.2). Whichever loss, validate at the cutoff users see (nDCG@10, Folder 06)."

**Bar-Raiser Follow-ups.**
- *"Labels from clicks?"* Pairwise preferences from clicks (a clicked result over a skipped one above it), with position-bias correction.

</details>

<details><summary><b>Q5 · "Your reranker can only reorder the candidates. How do you know stage 1 isn't the bottleneck?"</b></summary>

**Initial Prompt.** A reranking project is proposed to fix poor answers.

**L5 Answer.** "The reranker will put the best documents on top."

**Why L5 Fails in Production.** It can't promote documents that aren't in the candidate list.

**L7 Principal Defense.** "Measure the stage-1 recall@k at the candidate depth: 0.944 at 50 on SciFact, so 5.6% of relevant documents never reach the reranker. That's a hard ceiling. Do a ceiling analysis (Ng): (1) oracle-rerank the candidates (perfect ordering) to see the reranker's maximum gain, (2) oracle-retrieve (inject the relevant document) to see stage 1's. Invest in whichever gap is bigger: often stage-1 improvements such as hybrid and adapters (04.2: +5.2 points) beat reranker work."

**Bar-Raiser Follow-ups.**
- *"Deeper candidate lists?"* They raise the ceiling, but reranking cost grows linearly. Plot recall@k vs k and pick the knee.

</details>

<details><summary><b>Q6 · "How would you use an LLM in the ranking stack without paying for it on every query?"</b></summary>

**Initial Prompt.** Leadership wants "LLM-quality ranking".

**L5 Answer.** "Have the LLM rerank the top 20 for every query."

**Why L5 Fails in Production.** It costs a generation per query, adds order-sensitivity and variance, and its quality on your domain is unmeasured.

**L7 Principal Defense.** "Use the LLM as a *teacher*. Sample queries, have the LLM judge (query, passage) relevance (calibrated against a human-labelled subset, 01.3 §1.13), and train LambdaMART or fine-tune a small cross-encoder on those labels. Serving stays at milliseconds. Reserve live LLM reranking for a small, high-value slice (low-confidence queries, a premium tier) behind a cascade. Measure everything against the current ranking on held-out queries."

**Bar-Raiser Follow-ups.**
- *"Label noise from the LLM?"* Audit agreement with humans and calibrate. LambdaMART is fairly robust to moderate label noise, but systematic LLM bias (verbosity, position) must be checked.

</details>

<details><summary><b>Q7 · "What features would you give a LambdaMART reranker for RAG?"</b></summary>

**Initial Prompt.** Designing the feature set.

**L5 Answer.** "The BM25 score and the embedding similarity."

**Why L5 Fails in Production.** Two scores leave most of the signal on the table, and the model can't learn when to trust which.

**L7 Principal Defense.** "Start with what stage 1 already computed: BM25 and cosine scores *and ranks*, the RRF score, document length, query–title overlap and query length. These eight lifted SciFact from 0.693 to 0.719. Then add freshness, source authority, document quality, debiased click priors, tenant affinity, and an expensive signal (a cross-encoder or LLM-judge score) where affordable: as a feature, it reached 0.721, the best result. Group splits by query, early-stop on validation nDCG@10, and check feature importances for leakage (a feature that's 'too good' usually is)."

**Bar-Raiser Follow-ups.**
- *"Monotone constraints?"* Reasonable for features like BM25 score (more is never worse), and it improves robustness (02.2 §1.9).

</details>

<details><summary><b>Q8 · "How does a cross-encoder differ from a bi-encoder mathematically, and what does that buy?"</b></summary>

**Initial Prompt.** An architecture deep-dive.

**L5 Answer.** "The cross-encoder is a more powerful model."

**Why L5 Fails in Production.** Same size here (both 6-layer MiniLMs). The difference is the *factorization*, not the power.

**L7 Principal Defense.** "A bi-encoder scores f(q)·g(d): the two sides never interact, so documents are precomputed and search is a dot product. That factorization is what enables ANN over millions of documents. A cross-encoder computes h([q; d]), with attention between every query and document token in every layer, so it can check entailment, negation and specific entities, but nothing is precomputable, and each pair costs a forward pass (~45–95 ms per 256-token pair on CPU). Same parameter count, very different cost model. That's why they're stacked: bi-encoder for recall, cross-encoder for precision on a few candidates."

**Bar-Raiser Follow-ups.**
- *"Middle ground?"* ColBERT's late interaction (token-level vectors, MaxSim scoring) precomputes the document side while keeping token-level matching (04.2 §1.10).

</details>

---

## 7. Invariants Checklist

- [ ] Every reranker is evaluated against the ranking it replaces on held-out, in-domain queries (nDCG@10, plus stage-1 recall@k, plus p50/p99 latency).
- [ ] Off-the-shelf rerankers are used as features until in-domain evidence shows they help as the sole ranker.
- [ ] Learning-to-rank training splits by query (and by time where relevant). Early stopping uses validation nDCG at the user-visible cutoff.
- [ ] Cross-encoder cost is budgeted per query (candidates × tokens). Reranking runs on chunks with capped lengths and caching.
- [ ] Click-derived labels are debiased for position before training.
- [ ] LLM rerankers are teachers for cheap models by default. Live LLM reranking runs only on a cascaded slice.
- [ ] A ceiling analysis (oracle reranking vs oracle retrieval) precedes any reranking investment.

---

## 8. References

1. C. Burges, *From RankNet to LambdaRank to LambdaMART: An Overview*, Microsoft Research Technical Report MSR-TR-2010-82, 2010. https://www.microsoft.com/en-us/research/publication/from-ranknet-to-lambdarank-to-lambdamart-an-overview/
2. Z. Cao et al., *Learning to Rank: From Pairwise Approach to Listwise Approach* (ListNet), ICML 2007. DOI 10.1145/1273496.1273513.
3. K. Järvelin, J. Kekäläinen, *Cumulated Gain-Based Evaluation of IR Techniques* (nDCG), ACM TOIS 20(4), 2002. DOI 10.1145/582415.582418.
4. R. Nogueira, K. Cho, *Passage Re-ranking with BERT*, 2019. https://arxiv.org/abs/1901.04085
5. `cross-encoder/ms-marco-MiniLM-L6-v2` model card. https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2
6. P. Bajaj et al., *MS MARCO: A Human Generated MAchine Reading COmprehension Dataset*, 2016. https://arxiv.org/abs/1611.09268
7. LightGBM documentation, *Parameters* (`lambdarank` objective, `label_gain`, `lambdarank_truncation_level`). https://lightgbm.readthedocs.io/en/stable/Parameters.html
8. W. Sun et al., *Is ChatGPT Good at Search? Investigating Large Language Models as Re-Ranking Agents* (RankGPT), EMNLP 2023. https://arxiv.org/abs/2304.09542
9. T. Joachims et al., *Unbiased Learning-to-Rank with Biased Feedback*, WSDM 2017. https://arxiv.org/abs/1608.04468
10. D. Wadden et al., *SciFact*, EMNLP 2020. https://arxiv.org/abs/2004.14974
