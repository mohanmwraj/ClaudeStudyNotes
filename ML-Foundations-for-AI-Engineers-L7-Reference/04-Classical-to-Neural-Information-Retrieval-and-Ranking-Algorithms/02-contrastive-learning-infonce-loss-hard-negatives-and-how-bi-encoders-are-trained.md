# 04.2 · Contrastive Learning: InfoNCE Loss, Hard Negatives & How Bi-Encoders Are Trained

> **Folder 04 · Classical-to-Neural Information Retrieval & Ranking Algorithms**
> **Measured on:** PyTorch 2.14.1 (CUDA on an RTX 3050 Laptop GPU for corpus encoding; CPU for adapter training), transformers 5.22.0, NumPy 2.5.4, Windows 11.
> **Real data:** BEIR SciFact (5,183 abstracts; 809 train / 300 test claims), `all-MiniLM-L6-v2`.
> **Design sources:** van den Oord et al. (InfoNCE, 2018), Karpukhin et al. (DPR, 2020), Xiong et al. (ANCE, 2020), Qu et al. (RocketQA, 2021), Wang & Isola (2020), Gao et al. (SimCSE, 2021), Cormack et al. (RRF, SIGIR 2009). Full list in §8.

---

## 0. Orientation: How an Embedding Model Learns What "Similar" Means

Andrew Ng's framing: **a bi-encoder is trained by showing it a question, the right answer, and a crowd of wrong answers, and making the right one's score stand out.** That's InfoNCE: a softmax over similarities, cross-entropy on the correct item. Everything that makes embedding models good or bad follows from four choices:

- **Which positives** (query–passage pairs; labels or clicks).
- **Which negatives**: random, in-batch, or *hard* (lookalikes that are wrong).
- **How many**: the batch size bounds what the loss can learn.
- **The temperature**: who gets the gradient.

This file derives the loss, measures those choices, then does what production teams do. It **fine-tunes a query-side adapter on SciFact while keeping the 5,183-document index frozen**: +5.2 nDCG@10 points without re-embedding a single document. It also measures dense vs lexical vs hybrid retrieval on the same data.

### The backend-engineer bridge

| You already know | Contrastive-learning equivalent |
|---|---|
| A unit test with one correct output and many incorrect ones | **One positive, many negatives** per query |
| Testing against realistic adversarial inputs, not random noise | **Hard negatives**: near-misses the system confuses today |
| A versioned API where only the client adapter changes | **A query-side adapter over a frozen document index** |
| Merging ranked results from two backends | **Rank fusion** (RRF) or score fusion |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Bi-encoders vs cross-encoders: the architecture split | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 InfoNCE: the loss and its gradient | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Temperature decides which negatives teach | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 In-batch negatives and the log N bound | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Hard negatives, and the false-negative trap | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Alignment and uniformity: what training does to geometry | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.7 Adapting without re-embedding: query-side adapters | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Dense vs BM25 vs hybrid: measured | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Rank fusion (RRF) vs score fusion | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 Late interaction (ColBERT) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Mutual-information estimation theory | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Bi-encoders vs cross-encoders: the architecture split `[MUST-KNOW: Core AI Engineer Edge]`

```text
 bi-encoder (this file)                         cross-encoder (04.3)
 query ──► encoder ──► q ┐                      [CLS] query [SEP] document [SEP] ──► encoder ──► score
 doc   ──► encoder ──► d ┴─► score = q·d        reads both together: full token-level attention
 docs embedded ONCE, offline → ANN index        nothing precomputable: one forward pass PER (q, d) pair
 query cost: 1 encode + vector search           query cost: k forward passes for k candidates
```

The bi-encoder's factorization (score = f(q)·g(d)) is what makes retrieval over millions of documents possible: documents are encoded once, and search is a dot product (Folder 01). It costs accuracy, because the query and document never "see" each other. That's why the standard pipeline is **bi-encoder (and BM25) for recall, cross-encoder for precision on the top k** (04.3).

### 1.2 InfoNCE: the loss and its gradient `[MUST-KNOW: Core AI Engineer Edge]`

For a query with similarity s⁺ to its positive and s_j to each candidate (the positive included), at temperature τ:

```text
L = −log [ exp(s⁺/τ) / Σⱼ exp(sⱼ/τ) ]          = cross-entropy of a softmax over candidates
∂L/∂sⱼ = (pⱼ − 1[j = +]) / τ                    pⱼ = softmax(s/τ)ⱼ
```

It's 01.3's p − y gradient, scaled by 1/τ. Every negative is pushed down in proportion to how much probability it currently steals, and the positive is pulled up by 1 − p⁺. The listing checks the analytic gradient against finite differences to 1.4e-09.

### 1.3 Temperature decides which negatives teach `[MUST-KNOW: Core AI Engineer Edge]`

One positive at 0.80, one hard negative at 0.75, and 62 ordinary negatives around 0.30:

```text
   tau     loss p(positive)  share of neg-gradient on hardest  on top-5 negatives
   1.0   3.6770      0.0253                             0.025               0.098
   0.2   1.9861      0.1372                             0.124               0.236
  0.05   0.3206      0.7257                             0.973               0.985
  0.02   0.0789      0.9241                             1.000               1.000
```

At τ = 1, the gradient is spread evenly across 63 negatives (the hardest gets 2.5%), so the model mostly learns to push away easy negatives it already handles. At τ = 0.05, **97.3%** of the negative-side gradient goes to the single hard negative. Small τ concentrates learning on the confusions that matter. That's why embedding models train with τ around 0.01–0.07 (SimCSE uses 0.05; CLIP learns τ, initialized at 0.07). It's also why τ that's too small is dangerous: training is driven by a handful of negatives, and if any of those is mislabelled (§1.5), it steers the model wrong. The adapter experiment confirms it on real data: τ = 0.05 → **0.6968** nDCG@10, τ = 0.5 → **0.6555** (§1.7).

### 1.4 In-batch negatives and the log N bound `[MUST-KNOW: Core AI Engineer Edge]`

Encoding separate negatives is expensive, so the standard trick (Henderson et al., 2017; DPR) reuses the *other queries' positives in the same batch* as negatives. A batch of B pairs yields B − 1 negatives per query for free: one B × B similarity matrix, and the diagonal holds the positives.

```text
          d₁   d₂   d₃   d₄
   q₁  [  ●    ○    ○    ○ ]      ● positive (diagonal)
   q₂  [  ○    ●    ○    ○ ]      ○ in-batch negatives (other queries' positives)
   q₃  [  ○    ○    ●    ○ ]      loss = row-wise cross-entropy with target = diagonal
   q₄  [  ○    ○    ○    ● ]
```

Oord et al. (2018) show I(q; d) ≥ log N − L_InfoNCE with N candidates. The loss can certify at most log N nats of shared information:

```text
batch N  log N (max MI bound, nats)  ...
      8                       2.079
   1024                       6.931
```

So larger batches allow sharper representations, which is why embedding models are trained with batches of thousands (and techniques like gradient caching to fit them in memory). More negatives also means more chances to include a *hard* one by accident. In-batch negatives are mostly random and easy, though, which is why mined hard negatives matter (§1.5).

### 1.5 Hard negatives, and the false-negative trap `[MUST-KNOW: Core AI Engineer Edge]`

**Hard negatives** are documents the current model ranks highly that aren't relevant. DPR mined them with BM25. ANCE (Xiong et al., 2020) mines them from the dense model itself, refreshed during training. On SciFact, adding mined hard negatives (top-30 dense hits not labelled relevant) to in-batch training:

```text
query encoder                                 nDCG@10   R@100
frozen MiniLM (no adapter)                     0.6451  0.9250
adapter, in-batch negatives, tau 0.05          0.6587  0.9450
adapter, + mined hard negatives, tau 0.05      0.6968  0.9550
```

In-batch negatives alone gain +1.4 points, and hard negatives +5.2. The model learns most from the documents it currently confuses.

**The false-negative trap.** A "hard negative" may actually be relevant but unlabelled: relevance judgments are incomplete in every real dataset. InfoNCE then actively pushes a relevant document away, and with a small τ almost as hard as it pulls the positive in:

```text
gradient on the true positive -8.474; on the mislabelled relevant doc +7.726; on a typical negative +0.00040
```

The mislabelled document receives **19,000×** the gradient of a typical negative. Mitigations used in practice:

- Mask other known positives in the batch (the listing does this when a batch contains two relevant documents for one query).
- Skip the very top of the mined list. RocketQA filters likely false negatives with a cross-encoder before using them.
- Use a slightly larger τ, or label-smoothing-like soft targets.

### 1.6 Alignment and uniformity: what training does to geometry `[GOOD-TO-KNOW: Architectural Literacy]`

Wang & Isola (2020) decompose contrastive objectives into:

- **Alignment**: positives close together.
- **Uniformity**: embeddings spread evenly over the sphere.

Uniformity is the antidote to the anisotropy of 01.1 §1.7. Pre-trained language-model representations sit in a narrow cone, and contrastive fine-tuning spreads them out. That's part of why sentence-embedding models (SimCSE, Sentence-BERT descendants) behave far better under cosine than raw BERT outputs. It's also why every new contrastive fine-tune changes the similarity distribution, so every threshold must be re-derived (01.1 §1.7).

### 1.7 Adapting without re-embedding: query-side adapters `[MUST-KNOW: Core AI Engineer Edge]`

Fine-tuning the encoder means **re-embedding the whole corpus**, which is the expensive step at scale (01.1 Q7). A cheaper production pattern: freeze the document index and learn a linear map on the query side,

```text
q' = normalize(q · W),   W ∈ ℝ^{384×384},  W₀ = I,   loss = InfoNCE + λ‖W − I‖²
```

The λ term keeps W near the identity, which regularizes it with only 809 training claims (Ng's variance concern, 01.2 §4.2). With hard negatives and τ = 0.05, test nDCG@10 rises from **0.6451 to 0.6968**, more than BM25 alone (0.6711), and **no document was re-embedded**. The trade-offs:

- The adapter can only rotate and stretch the query space, so it can't fix documents the encoder represents badly.
- It must be retrained when the base encoder changes.
- Its gains are domain-specific, so validate it on held-out queries from the deployment distribution.

### 1.8 Dense vs BM25 vs hybrid: measured `[MUST-KNOW: Core AI Engineer Edge]`

```text
TEST (300 claims)               nDCG@10   R@100
BM25                             0.6711  0.9053
dense MiniLM                     0.6451  0.9250
RRF (k=60)                       0.6929  0.9617
convex a=0.30 (min-max)          0.7257  0.9583

per-query nDCG@10: BM25 better on 74, dense better on 67, tied on 159
```

- **Dense has better recall@100 (0.925 vs 0.905), BM25 better precision at the top.** Scientific claims share rare technical terms with their abstracts, which BM25 rewards.
- **They fail on different queries** (74 vs 67), which is exactly the condition under which fusion helps. Both fusions beat both inputs on nDCG@10 and recall.
- Our dense number (0.645) matches the commonly reported all-MiniLM-L6-v2 SciFact score, a sanity check that the pipeline (pooling, normalization, truncation at 256 tokens) is right.
- Encoding the corpus took **20.3 s on the RTX 3050 GPU** (5,183 abstracts at up to 256 tokens, plus 1,109 claims). On CPU, the same job would be minutes, which matters for re-indexing plans.

### 1.9 Rank fusion (RRF) vs score fusion `[MUST-KNOW: Core AI Engineer Edge]`

**Reciprocal Rank Fusion** (Cormack et al., 2009): score(d) = Σ_rankers 1/(k + rank_r(d)), with k = 60. It uses only ranks: no score calibration, no tuning, robust to incomparable scales (BM25 scores are unbounded, cosines lie in [−1, 1]). It's the right default when you have no labelled data: **0.6929** here.

**Convex score fusion**: α·norm(BM25) + (1 − α)·norm(cos), with per-query min–max normalization and α tuned on labelled training queries (α = 0.30 here). It uses score *margins*, not just order, so a document that is much better on one signal can win. **0.7257** here, +3.3 points over RRF. That's consistent with the Production AI Engineering KB's finding that RRF discards the score gap that matters for exact-match queries. It needs labelled queries to tune α, and normalization choices (min–max vs z-score) must be validated.

Rule: **start with RRF on day 0, and move to tuned score fusion once you have a labelled eval set.** The convex weights then become part of the versioned retrieval config.

### 1.10 Late interaction (ColBERT) `[GOOD-TO-KNOW: Architectural Literacy]`

ColBERT keeps one vector *per token* and scores with MaxSim: for each query token, take the max similarity over document tokens, then sum. It sits between bi-encoders (one vector, cheap) and cross-encoders (full attention, expensive), with much better accuracy than single-vector models on many benchmarks, at a large storage cost (one vector per token, mitigated by compression in ColBERTv2). Consider it when the bi-encoder plus reranker pipeline can't meet a precision target at your latency budget.

### 1.11 Mutual-information estimation theory `[SKIP: Academic/Research Only]`

InfoNCE as a variational MI lower bound, its bias at high MI, and alternative estimators (MINE, NWJ) matter for representation-learning research. For production retrieval, the log N intuition (§1.4) and the temperature behaviour (§1.3) are what you need.

---

## 2. Where It Beats an LLM in Production

| Need | Bi-encoder + fusion | LLM alternative |
|---|---|---|
| Retrieve from 10⁶–10⁹ documents in milliseconds | Precomputed document vectors + ANN; the query costs one ~2 ms encode (02.3) | No LLM can read the corpus per query |
| Domain adaptation | A query-side adapter trained in minutes on CPU (+5.2 nDCG@10), no re-indexing | Prompt-based query rewriting: an LLM call per query |
| Robustness to vocabulary mismatch and exact terms | Hybrid fusion (0.726 vs 0.671 / 0.645 alone) | Query expansion via LLM (HyDE-style) costs a generation per query, and must still be fused |

LLMs belong *after* retrieval: answer synthesis, and, when budget allows, reranking or verification of the top few candidates (04.3, Folder 07).

---

## 3. Production Code Blueprint

### 3.1 InfoNCE from first principles

```python
"""infonce_from_scratch.py - the contrastive loss that trains bi-encoders, derived and checked numerically.

For a query q with one positive d+ and negatives d1..dn (cosine similarities s, temperature tau):
    L = -log( exp(s+ / tau) / sum_j exp(s_j / tau) )        dL/ds_j = (p_j - 1[j = +]) / tau
  1. Gradient check against finite differences.
  2. Temperature decides who gets the gradient: the share of negative-side gradient on the hardest negative.
  3. In-batch negatives: the loss floor and the log(N) mutual-information bound.
  4. False negatives: a relevant document sitting in the batch as a "negative" is pushed away as hard as a
     true hard negative.
"""
import numpy as np

rng = np.random.default_rng(111)


def infonce(s, pos, tau):
    z = s / tau
    z = z - z.max()
    p = np.exp(z) / np.exp(z).sum()
    return -np.log(p[pos]), (p - np.eye(len(s))[pos]) / tau, p


print("== 1. gradient check ==")
s = rng.uniform(-0.2, 0.9, 16)
L, g, _ = infonce(s, 0, 0.05)
fd = np.array([(infonce(s + 1e-6 * e, 0, 0.05)[0] - infonce(s - 1e-6 * e, 0, 0.05)[0]) / 2e-6 for e in np.eye(16)])
print(f"loss {L:.4f}; max |analytic - finite difference| = {np.abs(g - fd).max():.1e}")
assert np.abs(g - fd).max() < 1e-5

print("\n== 2. temperature and hard negatives (1 positive at 0.80, 63 negatives) ==")
neg = np.sort(rng.normal(0.30, 0.10, 63))[::-1]
neg[0] = 0.75                                                     # one hard negative, nearly as similar as the positive
s = np.r_[0.80, neg]
print(f"{'tau':>6} {'loss':>8} {'p(positive)':>11} {'share of neg-gradient on hardest':>33} {'on top-5 negatives':>19}")
shares = {}
for tau in (1.0, 0.2, 0.05, 0.02):
    L, g, p = infonce(s, 0, tau)
    gneg = g[1:]
    shares[tau] = gneg[0] / gneg.sum()
    print(f"{tau:>6} {L:>8.4f} {p[0]:>11.4f} {shares[tau]:>33.3f} {gneg[:5].sum() / gneg.sum():>19.3f}")
assert shares[0.02] > shares[1.0] * 5

print("\n== 3. in-batch negatives: the loss floor and the log N bound ==")
print(f"{'batch N':>7} {'log N (max MI bound, nats)':>27} {'loss, random embeddings':>24} {'loss, perfect separation':>25}")
for n in (8, 64, 256, 1024):
    s_rand = rng.normal(0, 0.05, n)
    s_perf = np.r_[1.0, np.full(n - 1, 0.0)]
    print(f"{n:>7} {np.log(n):>27.3f} {infonce(s_rand, 0, 0.05)[0]:>24.3f} {infonce(s_perf, 0, 0.05)[0]:>25.6f}")
print("I(q; d) >= log N - L: a larger batch raises the ceiling on what the loss can certify.")

print("\n== 4. a false negative in the batch ==")
s = np.r_[0.80, 0.78, rng.normal(0.30, 0.10, 62)]                # index 1 is ALSO relevant, but labelled negative
_, g, _ = infonce(s, 0, 0.05)
print(f"gradient on the true positive {g[0]:+.3f}; on the mislabelled relevant doc {g[1]:+.3f}; "
      f"on a typical negative {np.median(g[2:]):+.5f}")
print("-> gradient descent lowers s for the relevant doc almost as hard as it raises the positive.")
assert g[1] > 100 * np.median(g[2:])
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. gradient check ==
loss 18.3753; max |analytic - finite difference| = 1.4e-09

== 2. temperature and hard negatives (1 positive at 0.80, 63 negatives) ==
   tau     loss p(positive)  share of neg-gradient on hardest  on top-5 negatives
   1.0   3.6770      0.0253                             0.025               0.098
   0.2   1.9861      0.1372                             0.124               0.236
  0.05   0.3206      0.7257                             0.973               0.985
  0.02   0.0789      0.9241                             1.000               1.000

== 3. in-batch negatives: the loss floor and the log N bound ==
batch N  log N (max MI bound, nats)  loss, random embeddings  loss, perfect separation
      8                       2.079                    3.692                  0.000000
     64                       4.159                    2.942                  0.000000
    256                       5.545                    6.934                  0.000001
   1024                       6.931                    6.016                  0.000002
I(q; d) >= log N - L: a larger batch raises the ceiling on what the loss can certify.

== 4. a false negative in the batch ==
gradient on the true positive -8.474; on the mislabelled relevant doc +7.726; on a typical negative +0.00040
-> gradient descent lowers s for the relevant doc almost as hard as it raises the positive.

ALL ASSERTIONS PASSED
```

### 3.2 Dense vs BM25 vs hybrid on SciFact

```python
"""dense_and_hybrid_scifact.py - bi-encoder (MiniLM) vs BM25 vs hybrid fusion on SciFact, with per-query analysis.

  1. Encode 5,183 abstracts and all claims with all-MiniLM-L6-v2 (GPU if present), cache for later listings.
  2. Dense retrieval vs BM25: nDCG@10, Recall@100; per-query wins and losses.
  3. Fusion: Reciprocal Rank Fusion (k = 60) vs a convex combination of normalized scores (alpha tuned on TRAIN).
"""
import json
import math
import os
import re
import time
from collections import defaultdict

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

DL, DATA = os.environ["KB_DL"], os.environ["KB_DATA"]
D = os.path.join(DL, "scifact", "x", "scifact")
docs = [json.loads(l) for l in open(os.path.join(D, "corpus.jsonl"), encoding="utf-8")]
queries = {q["_id"]: q["text"] for q in map(json.loads, open(os.path.join(D, "queries.jsonl"), encoding="utf-8"))}


def load_qrels(split):
    q = defaultdict(dict)
    for line in list(open(os.path.join(D, "qrels", f"{split}.tsv"), encoding="utf-8"))[1:]:
        a, b, s = line.split()
        q[a][b] = int(s)
    return q


qr = {"train": load_qrels("train"), "test": load_qrels("test")}
doc_ids = [d["_id"] for d in docs]
texts = [d["title"] + " " + d["text"] for d in docs]
dev = "cuda" if torch.cuda.is_available() else "cpu"
torch.manual_seed(0)
mdir = os.path.join(DL, "models", "minilm")
tok = AutoTokenizer.from_pretrained(mdir)
model = AutoModel.from_pretrained(mdir, use_safetensors=True).eval().to(dev)


@torch.inference_mode()
def encode(ts, max_len, bs=64):
    order = np.argsort([len(t) for t in ts])
    out = np.zeros((len(ts), 384), np.float32)
    for i in range(0, len(ts), bs):
        idx = order[i:i + bs]
        e = tok([ts[j] for j in idx], padding=True, truncation=True, max_length=max_len, return_tensors="pt").to(dev)
        h = model(**e).last_hidden_state
        m = e["attention_mask"].unsqueeze(-1).float()
        out[idx] = torch.nn.functional.normalize((h * m).sum(1) / m.sum(1), dim=-1).cpu().numpy()
    return out


t0 = time.perf_counter()
E_doc = encode(texts, 256)
qids_all = sorted(set(qr["train"]) | set(qr["test"]), key=int)
E_q = encode([queries[q] for q in qids_all], 64)
print(f"encoded {len(texts):,} abstracts (max 256 tokens) + {len(qids_all)} claims on {dev} in {time.perf_counter() - t0:.1f} s")
np.savez_compressed(os.path.join(DATA, "scifact_minilm.npz"), E_doc=E_doc, E_q=E_q, qids=np.array(qids_all))
qpos = {q: i for i, q in enumerate(qids_all)}

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


def bm25(q):
    acc = np.zeros(N)
    for w in set(tokenize(q)):
        if w in P:
            d, tf = P[w]
            acc[d] += idf[w] * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * dl[d] / avgdl))
    return acc


def metrics(rank, rel):
    gains = [rel.get(doc_ids[j], 0) for j in rank[:10]]
    nd = sum(g / math.log2(r + 2) for r, g in enumerate(gains)) / sum(1 / math.log2(r + 2) for r in range(min(10, len(rel))))
    return nd, sum(1 for j in rank[:100] if doc_ids[j] in rel) / len(rel)


def rrf(*ranks, k=60):
    s = np.zeros(N)
    for r in ranks:
        s[r] += 1.0 / (k + np.arange(1, len(r) + 1))
    return s


def minmax(x):
    return (x - x.min()) / (x.max() - x.min() + 1e-12)


def run(split, alpha=None):
    rows = []
    for qid in sorted(qr[split], key=int):
        sb, sd = bm25(queries[qid]), E_doc @ E_q[qpos[qid]]
        rb, rd = np.argsort(-sb, kind="stable"), np.argsort(-sd, kind="stable")
        out = {"BM25": rb, "dense MiniLM": rd, "RRF (k=60)": np.argsort(-rrf(rb[:1000], rd[:1000]), kind="stable")}
        if alpha is not None:
            out[f"convex a={alpha:.2f} (min-max)"] = np.argsort(-(alpha * minmax(sb) + (1 - alpha) * minmax(sd)), kind="stable")
        rows.append({k: metrics(v, qr[split][qid]) for k, v in out.items()})
    return rows


alphas = np.linspace(0, 1, 11)
train_scores = {}
for a in alphas:
    rows = run("train", a)
    train_scores[a] = np.mean([r[f"convex a={a:.2f} (min-max)"][0] for r in rows])
best_a = max(train_scores, key=train_scores.get)
print(f"convex-combination alpha tuned on 809 TRAIN claims: alpha={best_a:.2f} (train nDCG@10 {train_scores[best_a]:.4f})")
rows = run("test", best_a)
print(f"\n{'TEST (300 claims)':30s} {'nDCG@10':>8} {'R@100':>7}")
res = {}
for k in rows[0]:
    res[k] = (np.mean([r[k][0] for r in rows]), np.mean([r[k][1] for r in rows]))
    print(f"{k:30s} {res[k][0]:>8.4f} {res[k][1]:>7.4f}")
nb = np.array([r["BM25"][0] for r in rows])
nd = np.array([r["dense MiniLM"][0] for r in rows])
print(f"\nper-query nDCG@10: BM25 better on {np.sum(nb > nd + 1e-9)}, dense better on {np.sum(nd > nb + 1e-9)}, "
      f"tied on {np.sum(np.abs(nb - nd) <= 1e-9)}")
assert max(res["RRF (k=60)"][0], res[f"convex a={best_a:.2f} (min-max)"][0]) > max(res["BM25"][0], res["dense MiniLM"][0])
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the GPU encoding time, which is one measured run):

```text
encoded 5,183 abstracts (max 256 tokens) + 1109 claims on cuda in 20.3 s
convex-combination alpha tuned on 809 TRAIN claims: alpha=0.30 (train nDCG@10 0.7301)

TEST (300 claims)               nDCG@10   R@100
BM25                             0.6711  0.9053
dense MiniLM                     0.6451  0.9250
RRF (k=60)                       0.6929  0.9617
convex a=0.30 (min-max)          0.7257  0.9583

per-query nDCG@10: BM25 better on 74, dense better on 67, tied on 159

ALL ASSERTIONS PASSED
```

### 3.3 A query-side adapter trained with InfoNCE and hard negatives (frozen index)

```python
"""bi_encoder_adapter_training.py - contrastive fine-tuning of a query-side adapter on SciFact (frozen document index).

Production constraint: re-embedding the corpus is expensive, so keep document vectors frozen and learn a linear
map W on the QUERY side: q' = normalize(q W), W initialized to the identity, trained with InfoNCE.
  1. In-batch negatives only (other queries' positives).
  2. In-batch + mined hard negatives (top dense hits that are not labelled relevant).
  3. Temperature ablation (tau = 0.05 vs 0.5).
  4. Eval on the 300 TEST claims; the index is never re-embedded.
"""
import json
import math
import os
from collections import defaultdict

import numpy as np
import torch

DL, DATA = os.environ["KB_DL"], os.environ["KB_DATA"]
D = os.path.join(DL, "scifact", "x", "scifact")
Z = np.load(os.path.join(DATA, "scifact_minilm.npz"))
E_doc, E_q, qids = Z["E_doc"], Z["E_q"], [str(q) for q in Z["qids"]]
qpos = {q: i for i, q in enumerate(qids)}
doc_ids = [json.loads(l)["_id"] for l in open(os.path.join(D, "corpus.jsonl"), encoding="utf-8")]
dpos = {d: i for i, d in enumerate(doc_ids)}


def load_qrels(split):
    q = defaultdict(dict)
    for line in list(open(os.path.join(D, "qrels", f"{split}.tsv"), encoding="utf-8"))[1:]:
        a, b, s = line.split()
        q[a][b] = int(s)
    return q


qr_tr, qr_te = load_qrels("train"), load_qrels("test")
pairs = [(qpos[q], dpos[d]) for q in sorted(qr_tr, key=int) for d in qr_tr[q] if d in dpos]
pos_sets = defaultdict(set)
for qi, di in pairs:
    pos_sets[qi].add(di)
print(f"training pairs: {len(pairs)} (from {len(qr_tr)} train claims); document index frozen: {E_doc.shape}")

Dt = torch.tensor(E_doc)
hard = {}
for qi in pos_sets:                                               # mine hard negatives once, from the base model
    top = np.argsort(-(E_doc @ E_q[qi]))[:30]
    hard[qi] = [int(j) for j in top if j not in pos_sets[qi]][:20]


def evaluate(W):
    Q = torch.nn.functional.normalize(torch.tensor(E_q) @ W, dim=-1).numpy() if W is not None else E_q
    nd, rec = [], []
    for q, rel in qr_te.items():
        top = np.argsort(-(E_doc @ Q[qpos[q]]))[:100]
        gains = [rel.get(doc_ids[j], 0) for j in top[:10]]
        nd.append(sum(g / math.log2(r + 2) for r, g in enumerate(gains)) /
                  sum(1 / math.log2(r + 2) for r in range(min(10, len(rel)))))
        rec.append(sum(1 for j in top if doc_ids[j] in rel) / len(rel))
    return np.mean(nd), np.mean(rec)


def train(use_hard, tau, epochs=30, bs=64, lam=0.1, seed=0):
    g = torch.Generator().manual_seed(seed)
    W = torch.eye(384, requires_grad=True)
    opt = torch.optim.Adam([W], lr=1e-3)
    P = torch.tensor(pairs)
    for _ in range(epochs):
        for idx in torch.randperm(len(P), generator=g).split(bs):
            qi, di = P[idx, 0], P[idx, 1]
            q = torch.nn.functional.normalize(torch.tensor(E_q[qi.numpy()]) @ W, dim=-1)
            cand = [di]
            if use_hard:
                cand.append(torch.tensor([hard[int(x)][int(torch.randint(len(hard[int(x)]), (1,), generator=g))]
                                          for x in qi]))
            C = Dt[torch.cat(cand)]                               # positives of the batch + hard negatives
            logits = q @ C.T / tau
            for r, x in enumerate(qi.tolist()):                    # mask other in-batch docs that are ALSO relevant
                for c, d in enumerate(torch.cat(cand).tolist()):
                    if c != r and d in pos_sets[x]:
                        logits[r, c] = -1e9
            loss = torch.nn.functional.cross_entropy(logits, torch.arange(len(qi))) + lam * ((W - torch.eye(384)) ** 2).sum()
            opt.zero_grad()
            loss.backward()
            opt.step()
    return W.detach()


torch.manual_seed(0)
torch.set_num_threads(2)
print(f"\n{'query encoder':44s} {'nDCG@10':>8} {'R@100':>7}")
base = evaluate(None)
print(f"{'frozen MiniLM (no adapter)':44s} {base[0]:>8.4f} {base[1]:>7.4f}")
res = {}
for name, use_hard, tau in (("adapter, in-batch negatives, tau 0.05", False, 0.05),
                            ("adapter, + mined hard negatives, tau 0.05", True, 0.05),
                            ("adapter, + mined hard negatives, tau 0.5", True, 0.5)):
    res[name] = evaluate(train(use_hard, tau))
    print(f"{name:44s} {res[name][0]:>8.4f} {res[name][1]:>7.4f}")
best = max(res.values(), key=lambda v: v[0])
print(f"\nbest adapter vs frozen: {best[0] - base[0]:+.4f} nDCG@10, with zero documents re-embedded")
assert best[0] > base[0]
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
training pairs: 919 (from 809 train claims); document index frozen: (5183, 384)

query encoder                                 nDCG@10   R@100
frozen MiniLM (no adapter)                     0.6451  0.9250
adapter, in-batch negatives, tau 0.05          0.6587  0.9450
adapter, + mined hard negatives, tau 0.05      0.6968  0.9550
adapter, + mined hard negatives, tau 0.5       0.6555  0.9267

best adapter vs frozen: +0.0517 nDCG@10, with zero documents re-embedded

ALL ASSERTIONS PASSED
```

How to read it: the three adapter rows isolate one change each. Hard negatives provide most of the gain (0.6587 → 0.6968), and a large temperature wipes out most of it (0.6555). The masking loop in `train` is the false-negative guard of §1.5.

---

## 4. The Andrew Ng Lens: Hard Negatives Are Error Analysis, Automated

### 4.1 Mining hard negatives = collecting the model's current mistakes

Ng's advice is to find where the system fails and focus there. Hard-negative mining does exactly that, automatically: the negatives the model ranks highest are its current confusions. Training on them is targeted data collection. The +3.8-point jump from in-batch to hard negatives is the measured value of "focus on the errors".

### 4.2 Label quality is the ceiling

The false-negative analysis (§1.5) is a data-centric warning: incomplete relevance labels turn into wrong gradients, about 19,000× stronger than a typical negative's at τ = 0.05. Before scaling hard-negative training, audit a sample of the mined negatives. If many are actually relevant, fix the labels or filter with a cross-encoder. Data quality beats loss engineering.

### 4.3 Bias, variance and the adapter

809 training claims is a small dataset for a 147k-parameter adapter. The identity initialization plus the ‖W − I‖² penalty is the variance control. The evaluation on 300 *held-out* claims is what makes the +5.2 points credible. Repeat with other seeds and report the spread before relying on the exact number (Folder 06).

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Fine-tuned retriever gets *worse* on some topics | Mined negatives include unlabelled relevant documents | False negatives (19,000× gradient) | Filter mined negatives (cross-encoder), mask known positives, skip the top ranks | Audit a sample of mined negatives |
| F2 | Contrastive training barely improves | Only random or in-batch negatives (+1.4 points) | Easy negatives carry little gradient at low τ | Add mined hard negatives (+5.2 points) | Track the hard-negative share per batch |
| F3 | Training unstable or collapses | τ too small with noisy labels | A few negatives dominate | τ 0.02–0.07; filter labels; gradient clipping | τ swept as a hyperparameter |
| F4 | Fine-tuning requires a week-long re-index | Document encoder changed | Coupled query/document towers | Query-side adapter over a frozen index | Plan the adapter path in the retrieval design |
| F5 | Hybrid fusion worse than its best input | Raw BM25 scores added to cosines | Incomparable score scales | RRF, or normalized convex fusion with tuned α | Fusion evaluated per release |
| F6 | Fusion weights tuned on test queries | Optimistic numbers | Leakage into the eval | Tune α on train queries only (as here) | A held-out query set never used for tuning |
| F7 | Similarity thresholds break after fine-tuning | Score distribution shifted | Contrastive training changes the geometry (§1.6) | Re-derive every threshold | Thresholds versioned with the encoder/adapter |
| F8 | Dense retrieval misses exact identifiers | High recall@100, poor top-10 for code-like queries | Single-vector semantics blur rare tokens | Hybrid with BM25; identifier routing (04.1) | Identifier queries in the eval set |
| F9 | Re-indexing cost estimate off by 10× | CPU vs GPU encoding throughput | 20 s on GPU vs minutes on CPU for 5k abstracts | Plan encoding capacity explicitly (GPU batch jobs) | Benchmark encoding throughput per hardware tier |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain how a bi-encoder is trained, from the loss up."</b></summary>

**Initial Prompt.** Whiteboard, for an ML-platform role.

**L5 Answer.** "It's trained on pairs so that similar texts get similar embeddings."

**Why L5 Fails in Production.** Without the loss, the negatives and the temperature, you can't debug a fine-tune that stalls or degrades.

**L7 Principal Defense.** "InfoNCE: for each query, a softmax over similarities to its positive and a set of negatives, divided by τ, with cross-entropy on the positive. The gradient on each candidate is (p_j − 1[j = +])/τ, so negatives are pushed in proportion to how much probability they steal. Negatives come free from the batch (other queries' positives: B − 1 per query), plus mined hard negatives. The batch size bounds what's learnable (I ≥ log N − L). τ decides who gets the gradient: at 0.05, 97% of the negative gradient went to the single hard negative in our test. On SciFact, a query adapter trained this way with hard negatives gained +5.2 nDCG@10."

**Bar-Raiser Follow-ups.**
- *"Why normalize the embeddings?"* So the dot product is a cosine in [−1, 1] and τ has a consistent meaning. Unnormalized dot products let the model cheat by growing norms.

</details>

<details><summary><b>Q2 · "Our fine-tuned retriever got worse on some queries after we added hard negatives. Why?"</b></summary>

**Initial Prompt.** Hard negatives mined from BM25 top-20.

**L5 Answer.** "Too many hard negatives; use fewer."

**Why L5 Fails in Production.** The likely cause is *false* negatives: relevant but unlabelled documents mined as negatives, which InfoNCE then pushes away very hard.

**L7 Principal Defense.** "Relevance labels are incomplete, so the top of a mined list contains relevant documents. Our gradient check shows a mislabelled relevant document gets 7.7 units of gradient vs 0.0004 for a typical negative at τ = 0.05: it's actively unlearned. Fixes: mask in-batch documents known to be relevant (the listing does), skip the top-k of the mined list, filter candidates with a cross-encoder threshold (RocketQA's denoising), and audit 100 mined negatives by hand to estimate the false-negative rate. Then re-run, and report the change per query segment."

**Bar-Raiser Follow-ups.**
- *"Dynamic mining (ANCE)?"* Refreshing negatives from the improving model finds harder ones, and more false negatives. Pair it with filtering.

</details>

<details><summary><b>Q3 · "We can't afford to re-embed 500M documents. How do we adapt the retriever to our domain?"</b></summary>

**Initial Prompt.** The base encoder underperforms on internal jargon.

**L5 Answer.** "Fine-tune the encoder and re-index over a few weeks."

**Why L5 Fails in Production.** It may be necessary eventually, but there's a cheaper first step that keeps the index frozen.

**L7 Principal Defense.** "Train a query-side adapter: q' = normalize(qW), W initialized to the identity, with InfoNCE plus mined hard negatives and a ‖W − I‖² penalty. On SciFact it lifted nDCG@10 from 0.645 to 0.697 with zero documents re-embedded, beating BM25 alone. Training ran in minutes on CPU on 919 pairs. It also deploys like any query-side change, with a flag, an A/B test and instant rollback. Its limit: it can't fix documents the encoder represents badly. If error analysis shows document-side failures, then plan a re-index, and size it (5k abstracts took 20 s on one laptop GPU, so 500M is a GPU-fleet batch job)."

**Bar-Raiser Follow-ups.**
- *"Thresholds?"* The adapter changes query-side geometry, so re-derive any similarity thresholds (cache, OOD gates) that use adapted queries.

</details>

<details><summary><b>Q4 · "RRF or weighted score fusion for hybrid search?"</b></summary>

**Initial Prompt.** Combining BM25 and dense retrieval.

**L5 Answer.** "Weighted sum of the scores."

**Why L5 Fails in Production.** Raw BM25 scores are unbounded and query-dependent, while cosines lie in [−1, 1]. Summing them without normalization lets one signal dominate arbitrarily.

**L7 Principal Defense.** "Day 0, with no labels: RRF with k = 60, rank-based and tuning-free, gave 0.693 vs 0.671/0.645 for the inputs. With a labelled query set: convex fusion of per-query min–max normalized scores, α tuned on *train* queries (α = 0.30), gave 0.726, +3.3 over RRF, because it uses score margins that RRF discards. Version α with the retrieval config, re-tune when either retriever changes, and keep RRF as the fallback."

**Bar-Raiser Follow-ups.**
- *"Why does RRF lose?"* It treats rank 1 vs rank 2 the same whether the score gap is huge or tiny. When one retriever is very confident (an exact identifier match), RRF can't express that.

</details>

<details><summary><b>Q5 · "What does the temperature in contrastive training actually control?"</b></summary>

**Initial Prompt.** A team uses τ = 1 "to be safe".

**L5 Answer.** "It's a scaling factor; 1 is neutral."

**Why L5 Fails in Production.** At τ = 1, the gradient is spread across easy negatives the model already handles (the hardest got 2.5%), so learning is slow and unfocused. Our adapter at τ = 0.5 lost most of the gain (0.6555 vs 0.6968 at 0.05).

**L7 Principal Defense.** "τ scales logits before the softmax over candidates, so it controls how peaked the distribution is, and therefore which negatives receive gradient. Small τ (0.02–0.07) concentrates learning on hard negatives (97% at 0.05 in our test), which is what improves ranking. Too small, and a few possibly mislabelled negatives dominate. Sweep τ on a validation set. CLIP-style setups learn τ as a parameter."

**Bar-Raiser Follow-ups.**
- *"Same τ at inference?"* No. τ only shapes training. Retrieval ranks by raw cosine, and τ doesn't change the ordering.

</details>

<details><summary><b>Q6 · "Why does batch size matter so much for training embedding models?"</b></summary>

**Initial Prompt.** GPU memory limits the batch to 32.

**L5 Answer.** "Bigger batches just train faster."

**Why L5 Fails in Production.** With in-batch negatives, batch size is the number of negatives per query, and log N bounds what the loss can certify.

**L7 Principal Defense.** "Each query sees B − 1 in-batch negatives, and InfoNCE certifies at most log B nats of mutual information: 3.5 at 32, 6.9 at 1,024. Larger B also raises the chance that some negative is hard. With memory limits, use gradient caching (compute embeddings in chunks, then backpropagate), a memory bank of recent document embeddings, or mined hard negatives, which add difficulty without needing huge batches. Mind the false-negative rate, which grows with B on datasets with near-duplicates."

**Bar-Raiser Follow-ups.**
- *"Distributed training?"* Gather embeddings across GPUs so every query sees all devices' documents as negatives. That's standard in large-scale embedding training.

</details>

<details><summary><b>Q7 · "Dense retrieval has better recall@100 but worse nDCG@10 than BM25 here. Explain."</b></summary>

**Initial Prompt.** The SciFact numbers: dense R@100 0.925 vs 0.905; nDCG@10 0.645 vs 0.671.

**L5 Answer.** "Dense is just worse on this dataset."

**Why L5 Fails in Production.** "Worse" depends on the metric and the stage. For a pipeline with a reranker, dense's recall advantage is what matters.

**L7 Principal Defense.** "Dense retrieval finds more relevant documents somewhere in the top 100 (semantic matches BM25 misses), but ranks them less precisely at the very top, where shared rare technical terms (BM25's strength) are decisive for scientific claims. In a two-stage pipeline, the first stage is judged on recall@k and the reranker on nDCG@10. Fusion gets both: R@100 0.962 and nDCG@10 0.693–0.726. Choose first-stage retrievers by recall at the candidate depth the reranker will see."

**Bar-Raiser Follow-ups.**
- *"Which k for candidates?"* The smallest k at which recall plateaus, traded against reranker cost per candidate (04.3: a cross-encoder costs about 45–95 ms per pair on CPU here).

</details>

<details><summary><b>Q8 · "Bi-encoder, cross-encoder or ColBERT?"</b></summary>

**Initial Prompt.** An architecture review for a 50M-document search system.

**L5 Answer.** "Cross-encoders are most accurate, so use them."

**Why L5 Fails in Production.** A cross-encoder needs a forward pass per (query, document) pair. On 50M documents that's impossible at query time, and it's only viable on a few dozen candidates.

**L7 Principal Defense.** "Pipeline them. First stage: a bi-encoder (one vector per document, ANN search) fused with BM25, for recall. Second stage: rerank the top 20–100 with a cross-encoder, or a cheaper LambdaMART over features (04.3 measures both). ColBERT is the middle option when the bi-encoder + reranker pipeline can't hit the precision target within budget: better than single vectors, at much higher storage. Measure on our queries, because our zero-shot MS MARCO cross-encoder actually *underperformed* the hybrid on SciFact (04.3)."

**Bar-Raiser Follow-ups.**
- *"Storage for ColBERT?"* One vector per token: for 50M documents × ~200 tokens, tens of billions of vectors before compression. Budget it explicitly.

</details>

---

## 7. Invariants Checklist

- [ ] Contrastive training uses normalized embeddings, a swept temperature (typically 0.02–0.07), in-batch negatives, and filtered mined hard negatives.
- [ ] Mined negatives are audited for false negatives, and known positives are masked within each batch.
- [ ] Domain adaptation starts with a query-side adapter over the frozen index before any re-indexing.
- [ ] First-stage retrievers are chosen by recall at the reranker's candidate depth.
- [ ] Hybrid search runs by default: RRF without labels, tuned normalized score fusion with labels. Fusion weights are tuned on train queries only and versioned.
- [ ] Any encoder or adapter change re-derives similarity thresholds and re-runs the retrieval eval.
- [ ] Re-indexing plans are sized from measured encoding throughput on the target hardware.

---

## 8. References

1. A. van den Oord, Y. Li, O. Vinyals, *Representation Learning with Contrastive Predictive Coding* (InfoNCE), 2018. https://arxiv.org/abs/1807.03748
2. V. Karpukhin et al., *Dense Passage Retrieval for Open-Domain Question Answering* (DPR), EMNLP 2020. https://arxiv.org/abs/2004.04906
3. L. Xiong et al., *Approximate Nearest Neighbor Negative Contrastive Learning for Dense Text Retrieval* (ANCE), 2020. https://arxiv.org/abs/2007.00808
4. Y. Qu et al., *RocketQA: An Optimized Training Approach to Dense Passage Retrieval*, NAACL 2021. https://arxiv.org/abs/2010.08191
5. T. Wang, P. Isola, *Understanding Contrastive Representation Learning through Alignment and Uniformity on the Hypersphere*, ICML 2020. https://arxiv.org/abs/2005.10242
6. T. Gao, X. Yao, D. Chen, *SimCSE*, EMNLP 2021. https://arxiv.org/abs/2104.08821
7. M. Henderson et al., *Efficient Natural Language Response Suggestion for Smart Reply* (in-batch negatives), 2017. https://arxiv.org/abs/1705.00652
8. G. Cormack, C. Clarke, S. Büttcher, *Reciprocal Rank Fusion outperforms Condorcet and individual Rank Learning Methods*, SIGIR 2009. DOI 10.1145/1571941.1572114.
9. O. Khattab, M. Zaharia, *ColBERT: Efficient and Effective Passage Search via Contextualized Late Interaction over BERT*, SIGIR 2020. https://arxiv.org/abs/2004.12832
10. N. Thakur et al., *BEIR*, 2021. https://arxiv.org/abs/2104.08663
11. N. Reimers, I. Gurevych, *Sentence-BERT*, EMNLP 2019. https://arxiv.org/abs/1908.10084
