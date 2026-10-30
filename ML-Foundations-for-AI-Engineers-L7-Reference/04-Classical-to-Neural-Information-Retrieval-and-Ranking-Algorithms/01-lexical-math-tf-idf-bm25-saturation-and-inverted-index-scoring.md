# 04.1 · Lexical Retrieval Math: TF-IDF, BM25 Saturation & Inverted-Index Scoring

> **Folder 04 · Classical-to-Neural Information Retrieval & Ranking Algorithms**
> **Measured on:** pure NumPy/Python inverted index, scikit-learn 1.9.1 (`TfidfVectorizer`), CPython 3.14.5, Intel i5-11260H (one thread), Windows 11.
> **Real data:** BEIR SciFact (Wadden et al., 2020): 5,183 scientific abstracts, 809 train and 300 test claims with expert relevance judgments.
> **Design sources:** Robertson & Zaragoza (*The Probabilistic Relevance Framework: BM25 and Beyond*, 2009), Spärck Jones (1972), Thakur et al. (BEIR, 2021), Turtle & Flood (MaxScore, 1995), Broder et al. (WAND, 2003), Manning, Raghavan & Schütze (*Introduction to Information Retrieval*). Full list in §8.

---

## 0. Orientation: The 50-Year-Old Algorithm Your RAG Stack Still Needs

Here's the Andrew Ng-style summary. **BM25 counts how often the query's words appear in a document, discounts words that appear everywhere, stops rewarding repetition after a few occurrences, and corrects for document length.** That's all of it. And on SciFact, our 120-line implementation (**nDCG@10 0.671**) *beats* the 22M-parameter MiniLM dense retriever (**0.645**, 04.2). Fused with it, it lifts hybrid search to 0.726.

Lexical retrieval wins wherever *exact tokens* carry meaning: product codes, error messages, drug names, gene symbols, legal citations, and rare technical terms the encoder never saw in training. Every serious RAG system runs it next to dense retrieval (Production AI Engineering KB, Folder 04). This file builds it from the inverted index up, measures each design choice on real relevance judgments, and implements the exact MaxScore pruning that lets search engines skip half the work.

### The backend-engineer bridge

| You already know | IR equivalent |
|---|---|
| A secondary index: value → row ids | **Inverted index**: term → postings (doc id, term frequency) |
| A full table scan vs an index range scan | **Scoring all documents** vs touching only the postings of the query's terms (0.63× the corpus per query here) |
| Query-planner short-circuiting (`LIMIT 10` with an ordered index) | **MaxScore/WAND**: stop considering documents that can't reach the top 10 (53% fewer postings, same results) |
| Log compression with dictionary/delta encoding | **Postings compression** (delta-encoded doc ids, variable-byte integers) |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The inverted index and term-at-a-time scoring | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 TF-IDF and the vector-space model | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.3 BM25: the formula, term by term | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Saturation (k1) and length normalization (b) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 IDF variants, and why Lucene adds 1 | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.6 Tokenization and stemming as relevance decisions | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Tuning k1 and b: the train/test reality | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Dynamic pruning: MaxScore and WAND | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.9 Learned sparse retrieval (SPLADE) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 The probabilistic derivation (binary independence model, 2-Poisson) | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The inverted index and term-at-a-time scoring `[MUST-KNOW: Core AI Engineer Edge]`

```text
documents ─► tokenize ─► for each term t: postings(t) = [(doc_id, tf), ...] sorted by doc_id
                         plus per-document length |d| and corpus stats (N, avgdl, df(t) = |postings(t)|)

query "aspirin reduces stroke risk"
  └─► terms {aspirin, reduc, stroke, risk}
        for each term: walk its postings, add the term's score contribution to acc[doc]   ← term-at-a-time (TAAT)
        top-k of acc
```

For SciFact the index has **30,485 terms and 512,051 postings** (about 2.9 MiB as int32 doc ids plus uint16 tf), and builds in about a second. A query touches **3,266 postings** on average, 0.63× the corpus size, because claims contain common scientific words. Scoring takes **0.19 ms** per query in NumPy. Production engines (Lucene/Elasticsearch/OpenSearch, Tantivy, Vespa) do the same thing with compressed postings, skip lists and document-at-a-time traversal, which enables the pruning in §1.8.

### 1.2 TF-IDF and the vector-space model `[GOOD-TO-KNOW: Architectural Literacy]`

Represent each document as a sparse vector with weight `tf(t, d) · idf(t)` per term (often with sublinear tf = 1 + log tf), normalize to unit length, and rank by cosine with the query vector. It's the "embedding" of the pre-neural era: sparse, vocabulary-sized, and interpretable. On SciFact, sublinear TF-IDF cosine reaches nDCG@10 **0.647**, below BM25's 0.671 because cosine normalization over-penalizes long documents. Plain term-overlap counting (how many distinct query terms appear) reaches only **0.538**: weighting terms by rarity is worth 13 points.

### 1.3 BM25: the formula, term by term `[MUST-KNOW: Core AI Engineer Edge]`

```text
BM25(q, d) = Σ_{t ∈ q}  idf(t) · tf(t,d)·(k1 + 1) / ( tf(t,d) + k1·(1 − b + b·|d|/avgdl) )
             └──┬──┘    └─────────────────────────┬─────────────────────────────────┘
          rarity of t      saturating, length-normalized term frequency
idf(t) = ln(1 + (N − df(t) + 0.5)/(df(t) + 0.5))           (Lucene's form; §1.5)
defaults: k1 = 1.2, b = 0.75
```

Each piece is a modelling decision you can defend:

- **idf**: a term that appears in every document carries no information about which document is relevant.
- **Saturation (k1)**: the 10th mention of "stroke" is far weaker evidence than the 1st. Relevance doesn't grow linearly with repetition (§1.4).
- **Length normalization (b)**: a long abstract mentions everything more often by chance. Scale tf by how long the document is relative to the average (§1.4).
- **A sum over query terms**: terms contribute independently. That's the "bag of words" assumption, and the reason word order and negation are invisible to BM25.

### 1.4 Saturation (k1) and length normalization (b) `[MUST-KNOW: Core AI Engineer Edge]`

```text
  tf   k1=0.5   k1=1.2   k1=2.0   raw tf
   1    1.000    1.000    1.000        1
   2    1.200    1.375    1.500        2
   5    1.364    1.774    2.143        5
  20    1.463    2.075    2.727       20
(the limit as tf -> infinity is k1 + 1: repeating a word stops paying)
```

```text
 contribution
   k1+1 ┤· · · · · · · · · · · · · · · · · ·  asymptote
        │             ___________________ k1 = 1.2
        │        ____/
        │     __/
      1 ┼───●/                     raw tf would be a straight diagonal line → keyword stuffing wins
        │  /
        └──┴──┴──┴──┴──┴──┴──┴──┴──► tf
           1  2  3  4  5  ...
```

This is also BM25's built-in defence against **keyword stuffing**: no document can buy unlimited score by repeating a term. With k1 = 1.2, 20 repetitions are worth 2.08× one mention, not 20×.

Length normalization, for tf = 3:

```text
|d|/avgdl   b=0.0  b=0.75   b=1.0
      0.5   1.571   1.760   1.833       ← short document: each mention counts more
      2.0   1.571   1.294   1.222
      4.0   1.571   0.957   0.846       ← long document: mentions are expected by chance
```

b = 0 ignores length entirely. b = 1 normalizes fully. Chunked RAG corpora with uniform chunk lengths make b matter less, while heterogeneous corpora (short FAQ entries next to long manuals) make it matter a lot.

### 1.5 IDF variants, and why Lucene adds 1 `[GOOD-TO-KNOW: Architectural Literacy]`

The classic Robertson–Spärck Jones idf, log((N − n + 0.5)/(n + 0.5)), comes from the binary independence model. It goes **negative** once a term appears in more than half the documents:

```text
     n  RSJ log((N-n+.5)/(n+.5))  Lucene log(1 + ...)
     1                     8.148                8.148
   500                     2.236                2.338
  2591                     0.000                0.693
  4000                    -1.218                0.259
```

A negative idf means a document is *penalized* for containing a query term, which is absurd for users. Lucene's `BM25Similarity` uses log(1 + …), which stays positive. Our implementation uses the Lucene form. Stop-word lists address the same problem upstream.

### 1.6 Tokenization and stemming as relevance decisions `[MUST-KNOW: Core AI Engineer Edge]`

The analyzer (lowercase, split, drop stop words, stem) decides which strings count as "the same term". A 9-suffix light stemmer ("reduces", "reduced", "reducing" → "reduc"):

```text
ranker                                nDCG@10   R@100  MRR@10
BM25 (k1=1.2, b=0.75, light stem)      0.6711  0.9053  0.6367
BM25, no stemming                      0.6670  0.8859  0.6353
```

Stemming helps mostly with **recall** (+1.9 points at R@100). Production analyzers go further: language-specific stemmers (Porter/Snowball), synonym expansion, and *domain* tokenization. Don't split "COVID-19" or "IL-6" into meaningless pieces, and keep SKUs and error codes intact. Each choice must match at index time and query time, or the index silently misses: an analyzer mismatch is the lexical equivalent of an embedding-model mismatch.

### 1.7 Tuning k1 and b: the train/test reality `[MUST-KNOW: Core AI Engineer Edge]`

```text
best on train: k1=1.2, b=0.5 (0.6822); default 1.2/0.75 on train 0.6803
TEST nDCG@10: default 0.6711 | tuned 0.6665
```

Over a 20-point grid, the train nDCG@10 surface is almost flat (0.674–0.682), and the "best" setting is **worse on test** than the default. That's Ng's variance lesson in a 2-parameter model: a 0.2-point gain on 809 queries is within noise, and selecting the maximum of a noisy surface overfits. Rules: keep defaults unless the tuned gain is large *and* confirmed on held-out queries, report confidence intervals (Folder 06), and spend the effort on the analyzer and on hybrid fusion instead, which moved nDCG by 5 points (04.2).

### 1.8 Dynamic pruning: MaxScore and WAND `[GOOD-TO-KNOW: Architectural Literacy]`

Exhaustive TAAT scores every document that contains any query term, which is wasteful when you only need the top 10. **MaxScore** (Turtle & Flood, 1995):

1. Precompute each term's *upper bound*: the largest contribution it can make to any document (max tf, shortest document).
2. Process terms in decreasing upper-bound order, keeping θ = the current 10th-best partial score (a lower bound on the final 10th score).
3. Once the sum of the remaining terms' upper bounds is < θ, a document not yet seen can never reach the top 10, so stop admitting new documents, and only finish scoring the ones already in the accumulator.

```text
queries with identical top-10: 300/300; postings scored: exhaustive 979,769 vs MaxScore 460,056 (53.0% fewer)
```

The results are exactly the same and the work is halved. Rare, high-idf terms come first and establish θ quickly. Common terms ("study", "effect") then only update existing candidates. **WAND** (Broder et al., 2003) and Block-Max WAND apply the same upper-bound idea document-at-a-time, with per-block bounds. That's what Lucene does since version 8 when the total hit count isn't requested. It's why `track_total_hits=false` can make Elasticsearch queries much faster: exact counts force exhaustive scoring.

### 1.9 Learned sparse retrieval (SPLADE) `[GOOD-TO-KNOW: Architectural Literacy]`

SPLADE-style models use a transformer to predict a weight for every vocabulary term, including terms *not* in the text (expansion), then serve the result from an ordinary inverted index. You keep lexical infrastructure, interpretability and exact-match behaviour, and gain learned term importance and synonyms. The cost: GPU encoding at index time, and denser postings, so pruning matters more. It's a strong middle ground when a team already runs Elasticsearch/OpenSearch and wants neural gains without a vector database.

### 1.10 The probabilistic derivation `[SKIP: Academic/Research Only]`

BM25 descends from the binary independence model (the RSJ weight) and the 2-Poisson model of term frequencies (eliteness), approximated by the saturating tf function. Robertson & Zaragoza (2009) give the full story. Production needs §1.3–1.7: what each term in the formula does, and how to tune it.

---

## 2. Where It Beats an LLM in Production

| Need | BM25 / inverted index | LLM or dense-only alternative |
|---|---|---|
| Exact identifiers: SKUs, error codes, gene symbols, citations | Exact token match, ~0.2 ms per query over 5k docs, milliseconds at scale | Dense retrievers blur rare tokens. An LLM can't search a corpus at all without retrieval |
| A retrieval baseline on a new domain, day 0 | No training: nDCG@10 0.671 on SciFact out of the box | Dense models need domain fit: MiniLM 0.645 here, and fine-tuning adds work (04.2) |
| Explainability ("why did this document match?") | Matched terms and their idf/tf contributions | Opaque similarity scores |
| Cost at billions of documents | Compressed postings on disk, mature sharding | Vector memory: 01.1 §1.10's 41 GB per 10M × 1024 fp32 |

The production answer is almost never "BM25 *or* dense". It's **hybrid**: run both, fuse, rerank (04.2, 04.3). BM25's job in an AI system is the high-precision lexical half of first-stage retrieval.

---

## 3. Production Code Blueprint

### 3.1 Inverted index + BM25 from scratch, evaluated on SciFact

```python
"""bm25_inverted_index_scifact.py - an inverted index and BM25 from scratch, evaluated on BEIR SciFact (real qrels).

  1. Tokenize, build postings (term -> doc ids + term frequencies), compute document lengths.
  2. Score term-at-a-time with BM25: idf(t) * tf (k1 + 1) / (tf + k1 (1 - b + b |d| / avgdl)).
  3. Compare: BM25 with/without light stemming, TF-IDF cosine (sklearn), raw term-overlap counting.
  4. Metrics: nDCG@10, Recall@100, MRR@10 on the 300 test claims; index size and query cost.
"""
import json
import math
import os
import re
import time
from collections import defaultdict

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer

D = os.path.join(os.environ["KB_DL"], "scifact", "x", "scifact")
docs = [json.loads(l) for l in open(os.path.join(D, "corpus.jsonl"), encoding="utf-8")]
queries = {q["_id"]: q["text"] for q in map(json.loads, open(os.path.join(D, "queries.jsonl"), encoding="utf-8"))}
qrels = defaultdict(dict)
for line in list(open(os.path.join(D, "qrels", "test.tsv"), encoding="utf-8"))[1:]:
    qid, did, s = line.split()
    qrels[qid][did] = int(s)
doc_ids = [d["_id"] for d in docs]
texts = [d["title"] + " " + d["text"] for d in docs]
test_q = sorted(qrels, key=int)
print(f"SciFact: {len(docs):,} abstracts, {len(test_q)} test claims, {sum(len(v) for v in qrels.values())} relevance judgments")

STOP = set("a an and are as at be by for from has have in into is it its of on or that the their this to was were "
           "which with we our these those than not no can may also between both".split())


def light_stem(w):
    for suf in ("ations", "ation", "ingly", "ing", "edly", "ed", "ies", "es", "s"):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            return w[: -len(suf)] + ("y" if suf == "ies" else "")
    return w


def tokenize(s, stem=True):
    toks = [t for t in re.findall(r"[a-z0-9]+", s.lower()) if t not in STOP]
    return [light_stem(t) for t in toks] if stem else toks


class BM25Index:
    def __init__(self, texts, k1=1.2, b=0.75, stem=True):
        self.k1, self.b, self.stem = k1, b, stem
        post = defaultdict(lambda: defaultdict(int))
        self.dl = np.zeros(len(texts))
        for i, t in enumerate(texts):
            toks = tokenize(t, stem)
            self.dl[i] = len(toks)
            for w in toks:
                post[w][i] += 1
        self.N, self.avgdl = len(texts), self.dl.mean()
        self.post = {w: (np.fromiter(p.keys(), int), np.fromiter(p.values(), float)) for w, p in post.items()}
        # Lucene-style idf: never negative, even for terms in more than half the documents
        self.idf = {w: math.log(1 + (self.N - len(d) + 0.5) / (len(d) + 0.5)) for w, (d, _) in self.post.items()}

    def score(self, q):
        acc = np.zeros(self.N)
        for w in set(tokenize(q, self.stem)):
            if w in self.post:
                d, tf = self.post[w]
                norm = self.k1 * (1 - self.b + self.b * self.dl[d] / self.avgdl)
                acc[d] += self.idf[w] * tf * (self.k1 + 1) / (tf + norm)
        return acc


def evaluate(score_fn):
    nd, rec, mrr = [], [], []
    for qid in test_q:
        s = score_fn(queries[qid])
        top = np.argsort(-s, kind="stable")[:100]
        rel = qrels[qid]
        gains = [rel.get(doc_ids[j], 0) for j in top]
        dcg = sum(g / math.log2(r + 2) for r, g in enumerate(gains[:10]))
        idcg = sum(1 / math.log2(r + 2) for r in range(min(10, len(rel))))
        nd.append(dcg / idcg)
        rec.append(sum(1 for j in top if doc_ids[j] in rel) / len(rel))
        first = next((r for r, g in enumerate(gains[:10]) if g > 0), None)
        mrr.append(0 if first is None else 1 / (first + 1))
    return np.mean(nd), np.mean(rec), np.mean(mrr)


t0 = time.perf_counter()
idx = BM25Index(texts)
t_build = time.perf_counter() - t0
idx_ns = BM25Index(texts, stem=False)
n_post = sum(len(d) for d, _ in idx.post.values())
print(f"index: {len(idx.post):,} terms, {n_post:,} postings, avgdl {idx.avgdl:.1f} tokens, built in {t_build:.1f} s; "
      f"postings as int32 doc ids + uint16 tf ~ {n_post * 6 / 2**20:.1f} MiB")

tfidf = TfidfVectorizer(tokenizer=tokenize, lowercase=False, token_pattern=None, sublinear_tf=True).fit(texts)
Dm = tfidf.transform(texts)
overlap = lambda q: np.array((Dm[:, tfidf.transform([q]).indices] > 0).sum(1)).ravel().astype(float)
runs = {
    "BM25 (k1=1.2, b=0.75, light stem)": idx.score,
    "BM25, no stemming": idx_ns.score,
    "TF-IDF cosine (sublinear tf)": lambda q: (Dm @ tfidf.transform([q]).T).toarray().ravel(),
    "term overlap count": overlap,
}
print(f"\n{'ranker':36s} {'nDCG@10':>8} {'R@100':>7} {'MRR@10':>7}")
res = {}
for name, f in runs.items():
    res[name] = evaluate(f)
    print(f"{name:36s} {res[name][0]:>8.4f} {res[name][1]:>7.4f} {res[name][2]:>7.4f}")
bm = res["BM25 (k1=1.2, b=0.75, light stem)"]
assert bm[0] > res["term overlap count"][0] + 0.05 and bm[0] > 0.6

t0 = time.perf_counter()
work = 0
for qid in test_q:
    idx.score(queries[qid])
    work += sum(len(idx.post[w][0]) for w in set(tokenize(queries[qid])) if w in idx.post)
dt = (time.perf_counter() - t0) / len(test_q)
print(f"\nterm-at-a-time BM25: {dt * 1e3:.2f} ms/query (one measured run), {work / len(test_q):,.0f} postings touched per query "
      f"({work / len(test_q) / len(docs):.2f}x the corpus size)")
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except build time and ms/query, which are one measured run):

```text
SciFact: 5,183 abstracts, 300 test claims, 339 relevance judgments
index: 30,485 terms, 512,051 postings, avgdl 157.8 tokens, built in 1.1 s; postings as int32 doc ids + uint16 tf ~ 2.9 MiB

ranker                                nDCG@10   R@100  MRR@10
BM25 (k1=1.2, b=0.75, light stem)      0.6711  0.9053  0.6367
BM25, no stemming                      0.6670  0.8859  0.6353
TF-IDF cosine (sublinear tf)           0.6467  0.9099  0.6061
term overlap count                     0.5382  0.7927  0.5148

term-at-a-time BM25: 0.19 ms/query (one measured run), 3,266 postings touched per query (0.63x the corpus size)

ALL ASSERTIONS PASSED
```

How to read it: our BM25 lands at **0.671** nDCG@10, close to BEIR's published SciFact BM25 baseline (0.665, Elasticsearch with its own analyzer). The ~0.6-point difference comes from analyzer choices (stop words, stemming), which §1.6 shows are worth points either way.

### 3.2 Saturation, length normalization, IDF, tuning, and exact MaxScore

```python
"""bm25_saturation_and_maxscore.py - BM25's two knobs, its IDF, tuning on train queries, and exact MaxScore pruning.

  1. Term-frequency saturation: contribution vs tf for k1 in {0.5, 1.2, 2.0} and raw tf.
  2. Length normalization: the same tf in short vs long documents at b = 0, 0.75, 1.
  3. IDF: classic Robertson-Sparck Jones goes negative for very common terms; the Lucene "+1" form does not.
  4. Tune (k1, b) on SciFact TRAIN queries, report once on TEST.
  5. MaxScore: once the remaining terms cannot lift an unseen document into the top 10, stop admitting new
     documents. Same top-10 as exhaustive scoring, fewer postings touched.
"""
import json
import math
import os
import re
from collections import defaultdict

import numpy as np

D = os.path.join(os.environ["KB_DL"], "scifact", "x", "scifact")
docs = [json.loads(l) for l in open(os.path.join(D, "corpus.jsonl"), encoding="utf-8")]
queries = {q["_id"]: q["text"] for q in map(json.loads, open(os.path.join(D, "queries.jsonl"), encoding="utf-8"))}


def load_qrels(split):
    q = defaultdict(dict)
    for line in list(open(os.path.join(D, "qrels", f"{split}.tsv"), encoding="utf-8"))[1:]:
        a, b_, s = line.split()
        q[a][b_] = int(s)
    return q


qr_train, qr_test = load_qrels("train"), load_qrels("test")
doc_ids = [d["_id"] for d in docs]
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
N, avgdl = len(docs), dl.mean()
P = {w: (np.fromiter(p.keys(), int), np.fromiter(p.values(), float)) for w, p in post.items()}
idf = {w: math.log(1 + (N - len(d) + 0.5) / (len(d) + 0.5)) for w, (d, _) in P.items()}

print("== 1. tf saturation: tf (k1+1)/(tf + k1) at |d| = avgdl ==")
print(f"{'tf':>4} " + " ".join(f"{'k1=' + str(k):>8}" for k in (0.5, 1.2, 2.0)) + f" {'raw tf':>8}")
for tf in (1, 2, 5, 10, 20):
    print(f"{tf:>4} " + " ".join(f"{tf * (k + 1) / (tf + k):>8.3f}" for k in (0.5, 1.2, 2.0)) + f" {tf:>8}")
print("(the limit as tf -> infinity is k1 + 1: repeating a word stops paying)")

print("\n== 2. length normalization: contribution of tf = 3 (k1 = 1.2) ==")
print(f"{'|d|/avgdl':>9} " + " ".join(f"{'b=' + str(b):>7}" for b in (0.0, 0.75, 1.0)))
for ratio in (0.5, 1.0, 2.0, 4.0):
    print(f"{ratio:>9} " + " ".join(f"{3 * 2.2 / (3 + 1.2 * (1 - b + b * ratio)):>7.3f}" for b in (0.0, 0.75, 1.0)))

print("\n== 3. IDF for a term in n of N = 5,183 documents ==")
print(f"{'n':>6} {'RSJ log((N-n+.5)/(n+.5))':>25} {'Lucene log(1 + ...)':>20}")
for n in (1, 50, 500, 2591, 4000):
    r = (N - n + 0.5) / (n + 0.5)
    print(f"{n:>6} {math.log(r):>25.3f} {math.log(1 + r):>20.3f}")


def score(q, k1, b):
    acc = np.zeros(N)
    for w in set(tokenize(q)):
        if w in P:
            d, tf = P[w]
            acc[d] += idf[w] * tf * (k1 + 1) / (tf + k1 * (1 - b + b * dl[d] / avgdl))
    return acc


def ndcg10(qr, k1, b):
    out = []
    for qid, rel in qr.items():
        top = np.argsort(-score(queries[qid], k1, b), kind="stable")[:10]
        dcg = sum(rel.get(doc_ids[j], 0) / math.log2(r + 2) for r, j in enumerate(top))
        out.append(dcg / sum(1 / math.log2(r + 2) for r in range(min(10, len(rel)))))
    return float(np.mean(out))


print("\n== 4. tuning (k1, b) on 809 TRAIN claims ==")
grid = [(k1, b) for k1 in (0.6, 0.9, 1.2, 1.6, 2.0) for b in (0.3, 0.5, 0.75, 0.9)]
tr = {kb: ndcg10(qr_train, *kb) for kb in grid}
best = max(tr, key=tr.get)
print("train nDCG@10 by (k1, b): " + ", ".join(f"{k}/{b}={v:.3f}" for (k, b), v in sorted(tr.items()) if b in (0.3, 0.75)))
print(f"best on train: k1={best[0]}, b={best[1]} ({tr[best]:.4f}); default 1.2/0.75 on train {tr[(1.2, 0.75)]:.4f}")
print(f"TEST nDCG@10: default {ndcg10(qr_test, 1.2, 0.75):.4f} | tuned {ndcg10(qr_test, *best):.4f}")

print("\n== 5. MaxScore pruning vs exhaustive term-at-a-time (k1=1.2, b=0.75, top-10) ==")
k1, b = 1.2, 0.75
ub = {w: idf[w] * (k1 + 1) * P[w][1].max() / (P[w][1].max() + k1 * (1 - b + b * dl.min() / avgdl)) for w in P}
same, full_work, pruned_work = 0, 0, 0
for qid in sorted(qr_test, key=int):
    terms = sorted({w for w in tokenize(queries[qid]) if w in P}, key=lambda w: -ub[w])
    exact = set(np.argsort(-score(queries[qid], k1, b), kind="stable")[:10])
    full_work += sum(len(P[w][0]) for w in terms)
    acc = np.zeros(N)
    seen = np.zeros(N, bool)
    for i, w in enumerate(terms):
        d, tf = P[w]
        contrib = idf[w] * tf * (k1 + 1) / (tf + k1 * (1 - b + b * dl[d] / avgdl))
        theta = np.sort(acc)[-10] if seen.sum() >= 10 else -1.0
        remaining = sum(ub[x] for x in terms[i:])
        if remaining < theta:                                       # an unseen doc can't reach the top 10 now
            m = seen[d]
            acc[d[m]] += contrib[m]
            pruned_work += int(m.sum())
        else:
            acc[d] += contrib
            seen[d] = True
            pruned_work += len(d)
    got = set(np.argsort(-acc, kind="stable")[:10])
    same += got == exact
print(f"queries with identical top-10: {same}/{len(qr_test)}; postings scored: exhaustive {full_work:,} vs MaxScore "
      f"{pruned_work:,} ({1 - pruned_work / full_work:.1%} fewer)")
assert same == len(qr_test) and pruned_work < full_work
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. tf saturation: tf (k1+1)/(tf + k1) at |d| = avgdl ==
  tf   k1=0.5   k1=1.2   k1=2.0   raw tf
   1    1.000    1.000    1.000        1
   2    1.200    1.375    1.500        2
   5    1.364    1.774    2.143        5
  10    1.429    1.964    2.500       10
  20    1.463    2.075    2.727       20
(the limit as tf -> infinity is k1 + 1: repeating a word stops paying)

== 2. length normalization: contribution of tf = 3 (k1 = 1.2) ==
|d|/avgdl   b=0.0  b=0.75   b=1.0
      0.5   1.571   1.760   1.833
      1.0   1.571   1.571   1.571
      2.0   1.571   1.294   1.222
      4.0   1.571   0.957   0.846

== 3. IDF for a term in n of N = 5,183 documents ==
     n  RSJ log((N-n+.5)/(n+.5))  Lucene log(1 + ...)
     1                     8.148                8.148
    50                     4.622                4.631
   500                     2.236                2.338
  2591                     0.000                0.693
  4000                    -1.218                0.259

== 4. tuning (k1, b) on 809 TRAIN claims ==
train nDCG@10 by (k1, b): 0.6/0.3=0.675, 0.6/0.75=0.674, 0.9/0.3=0.678, 0.9/0.75=0.678, 1.2/0.3=0.680, 1.2/0.75=0.680, 1.6/0.3=0.680, 1.6/0.75=0.677, 2.0/0.3=0.674, 2.0/0.75=0.675
best on train: k1=1.2, b=0.5 (0.6822); default 1.2/0.75 on train 0.6803
TEST nDCG@10: default 0.6711 | tuned 0.6665

== 5. MaxScore pruning vs exhaustive term-at-a-time (k1=1.2, b=0.75, top-10) ==
queries with identical top-10: 300/300; postings scored: exhaustive 979,769 vs MaxScore 460,056 (53.0% fewer)

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Error Analysis on Retrieval Misses

### 4.1 The retrieval error spreadsheet

For each test query whose relevant document isn't in BM25's top 10, record: the query, the relevant document's title, its BM25 rank, the query terms it contains, and a tag. On SciFact-style data the recurring tags are:

| Tag | Example pattern | Fix |
|---|---|---|
| `vocabulary-mismatch` | The claim says "heart attack", the abstract says "myocardial infarction" | Dense retrieval (hybrid), synonym expansion, SPLADE |
| `tokenization` | "IL-6", "COVID-19", "TNF-α" split or normalized differently in the query and the index | Domain analyzer; match normalization at index and query time |
| `common-term dominance` | Matches on "study", "patients" outrank the specific term | Stop-word list, idf floor, phrase/proximity boosting |
| `negation / direction` | "X does *not* increase Y" vs "X increases Y" | Inherent to bag-of-words. Use a cross-encoder or LLM verification downstream |
| `label gap` | A clearly relevant document isn't in the qrels | Add it to the eval set (a data-centric fix) |

The counts tell you whether to invest in the analyzer, the dense side, or reranking. On SciFact, BM25 and dense each win on about a quarter of queries (74 vs 67 of 300, 04.2), which is the quantitative argument for hybrid.

### 4.2 Variance in retrieval tuning

§1.7 is a cautionary tale for every IR team: tuning on a flat surface overfits. Ng's prescription: before tuning, measure noise. Bootstrap the nDCG difference between two settings over queries. If its interval spans zero, the "improvement" isn't one.

### 4.3 Eval first, analyzer second

Build the relevance-judged eval set before touching the analyzer. Every analyzer change (stemmer, stop words, tokenization) is then a measured experiment, not a debate.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Searches for SKUs or error codes fail | Token split or lowercased differently at index and query time | Analyzer mismatch or generic tokenizer | Domain tokenizer; the same analyzer at both ends | Golden queries for identifier-shaped inputs |
| F2 | Keyword-stuffed documents rank first | A linear-tf scorer | No saturation | BM25 (k1 ≈ 1.2) | Never ship raw tf or TF-IDF without saturation |
| F3 | Long documents always lose | Full length normalization, or cosine-normalized TF-IDF | b too high for the corpus | Lower b; chunk documents to similar lengths | Length-stratified evaluation |
| F4 | Common query terms *hurt* matching documents | Negative idf | RSJ idf with df > N/2 | Lucene "+1" idf; stop words | Unit-test idf for a very common term |
| F5 | Tuned k1/b look great, production gets worse | Gain < noise on the tuning set | Overfitting a flat surface (test 0.6665 < default 0.6711) | Keep defaults; require held-out confirmation and CIs | Report bootstrap CIs on every tuning claim |
| F6 | Search latency spikes on long queries | Exhaustive TAAT over common-term postings | No dynamic pruning, or exact hit counting forced | MaxScore/WAND; disable exact total-hit counts | Latency tests with long, common-term queries |
| F7 | "Heart attack" misses "myocardial infarction" | Vocabulary mismatch | Bag-of-words semantics | Hybrid with dense; synonyms; SPLADE | Error-analysis tag counts |
| F8 | Negated claims retrieve their opposites | Same bag of words | BM25 ignores word order and negation | Downstream cross-encoder or LLM verification | Contrast pairs in the eval set |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why does our RAG system still need BM25 when we have embeddings?"</b></summary>

**Initial Prompt.** A team proposes removing Elasticsearch to simplify the stack.

**L5 Answer.** "Embeddings understand meaning, so BM25 is obsolete."

**Why L5 Fails in Production.** On SciFact, BM25 (0.671) beats the MiniLM dense retriever (0.645), and each wins on about a quarter of queries. Removing it loses exact-match behaviour for identifiers and rare terms, plus the hybrid gain (0.726 fused).

**L7 Principal Defense.** "They fail differently. Dense retrieval handles vocabulary mismatch ('heart attack' vs 'myocardial infarction'). BM25 handles exact tokens the encoder blurs (codes, rare terms, names) and needs no training on a new domain. Measured on SciFact: BM25 0.671, dense 0.645, RRF 0.693, tuned convex fusion 0.726. BM25 better on 74 queries, dense on 67. Keep both, fuse, and rerank. If operating two systems is the real concern, consider one engine that does both (OpenSearch/Elasticsearch with vector fields, Vespa, or pgvector plus Postgres full-text search) rather than dropping lexical retrieval."

**Bar-Raiser Follow-ups.**
- *"When would you drop it?"* If error analysis shows zero lexical-only wins on a large eval set, *and* identifier queries don't exist in the traffic. Rare in practice.

</details>

<details><summary><b>Q2 · "Walk me through the BM25 formula and what k1 and b do."</b></summary>

**Initial Prompt.** Whiteboard.

**L5 Answer.** "It's TF-IDF with some tuning parameters."

**Why L5 Fails in Production.** It hides the two design decisions (saturation and length normalization) that make BM25 robust, and that you tune per corpus.

**L7 Principal Defense.** "Sum over query terms of idf × tf(k1 + 1)/(tf + k1(1 − b + b|d|/avgdl)). The idf rewards rarity, using the Lucene log(1 + …) form so it never goes negative. The tf part saturates toward k1 + 1: with k1 = 1.2, 20 mentions are worth 2.08× one, which also defeats keyword stuffing. b scales tf by relative document length: at b = 0.75 a document 4× the average length gets 0.957 for tf = 3, vs 1.760 for a half-length one. Defaults (1.2, 0.75) are robust. Tuning on SciFact train was flat and didn't transfer to test."

**Bar-Raiser Follow-ups.**
- *"What happens at b = 0 and k1 = 0?"* b = 0 ignores length. k1 = 0 makes tf binary (presence only). Both are useful special cases, for uniform chunks or for very short documents.

</details>

<details><summary><b>Q3 · "Our Elasticsearch queries got slow when we started returning total hit counts. Why?"</b></summary>

**Initial Prompt.** A product feature needs "about N results".

**L5 Answer.** "Counting is expensive. Add more nodes."

**Why L5 Fails in Production.** It misses the mechanism: exact counts disable dynamic pruning, so every matching document must be scored.

**L7 Principal Defense.** "Top-k retrieval can skip documents that provably can't make the top k: MaxScore, WAND, Block-Max WAND. Our MaxScore implementation scores 53% fewer postings with identical top-10 on all 300 SciFact queries. An exact total-hit count forces exhaustive traversal, which throws that away. Fix: approximate counts (Elasticsearch's `track_total_hits` defaults to counting accurately only up to 10,000), or compute counts asynchronously or from a cheaper query. Then load-test long queries made of common terms, the worst case for pruning."

**Bar-Raiser Follow-ups.**
- *"Why does term order matter in MaxScore?"* High-upper-bound (rare) terms first establish a strong top-k threshold early. Common terms then only update existing candidates.

</details>

<details><summary><b>Q4 · "We tuned BM25 parameters and gained 0.2 points. Ship it?"</b></summary>

**Initial Prompt.** A grid search over k1 and b on 809 training queries.

**L5 Answer.** "Yes, any improvement helps."

**Why L5 Fails in Production.** Our identical experiment: the best train setting (k1 = 1.2, b = 0.5, +0.2 points on train) was *worse* on test (0.6665 vs 0.6711). The surface is flat, and its maximum is noise.

**L7 Principal Defense.** "Before tuning, estimate the noise: a paired bootstrap of nDCG differences across queries (Folder 06). A 0.2-point gain on 809 queries is well inside it. Keep the defaults unless a held-out set confirms a gain larger than the interval. Spend the effort where measurements show leverage: the analyzer (stemming +1.9 points of recall), hybrid fusion (+5.5 points nDCG over BM25 alone), and reranking (04.3)."

**Bar-Raiser Follow-ups.**
- *"When does tuning matter?"* Corpora with extreme length heterogeneity (b), or very short fields like titles and tags (k1, b near 0). Tune per field in multi-field (BM25F-style) setups.

</details>

<details><summary><b>Q5 · "TF-IDF cosine or BM25?"</b></summary>

**Initial Prompt.** A team uses scikit-learn's TfidfVectorizer for search.

**L5 Answer.** "They're basically the same."

**Why L5 Fails in Production.** Measured: TF-IDF cosine 0.647 vs BM25 0.671 on SciFact. Cosine normalization over-penalizes long documents, and without saturation repeated terms dominate.

**L7 Principal Defense.** "BM25 is the better default for ranking: saturating tf, length normalization relative to avgdl, and a robust idf. TF-IDF vectors remain useful as *features*: the TF-IDF + LR prompt-injection head in 02.3 beat embeddings (AUC 0.975). But for retrieval ranking, use BM25 from a real engine, with compressed postings, pruning and analyzers."

**Bar-Raiser Follow-ups.**
- *"Sublinear tf?"* 1 + log tf is a weaker saturation, and it helps TF-IDF, which is why the listing uses it. BM25's k1 controls saturation explicitly.

</details>

<details><summary><b>Q6 · "How would you handle product codes like 'X-200-B' in search?"</b></summary>

**Initial Prompt.** E-commerce search returns irrelevant products for model numbers.

**L5 Answer.** "Use semantic search; it understands products."

**Why L5 Fails in Production.** Embeddings treat 'X-200-B' and 'X-200-C' as near-identical strings. The user needs the exact one.

**L7 Principal Defense.** "That's an analyzer problem. Index identifier fields with a keyword (non-tokenized) analyzer plus an n-gram sub-field for partial matches, normalize case and separators the same way at index and query time, and boost exact identifier matches above full-text BM25. Route identifier-shaped queries (a regex) to the exact path first, which is the lexical stage of a cascade (Folder 07). Keep dense retrieval for descriptive queries, and fuse."

**Bar-Raiser Follow-ups.**
- *"Typos in codes?"* Edit-distance (fuzzy) matching on the keyword field, bounded to 1–2 edits, with exact matches always ranked first.

</details>

<details><summary><b>Q7 · "What does stemming buy, and when does it hurt?"</b></summary>

**Initial Prompt.** An analyzer design review.

**L5 Answer.** "Stemming always improves recall."

**Why L5 Fails in Production.** It's mostly true for recall (+1.9 points of R@100 here), but aggressive stemming conflates distinct terms ("university" / "universe", "organ" / "organization") and hurts precision on domain vocabularies.

**L7 Principal Defense.** "Measured on SciFact: light stemming gives nDCG@10 0.6711 vs 0.6670 and R@100 0.9053 vs 0.8859, mostly a recall effect. Choose per field: stem descriptive text, never stem identifiers or names, and test language-specific stemmers on your eval set. Index both stemmed and unstemmed fields and boost exact (unstemmed) matches, so precision isn't lost."

**Bar-Raiser Follow-ups.**
- *"Lemmatization?"* More precise and slower. It's worth it for morphologically rich languages, so measure.

</details>

<details><summary><b>Q8 · "Explain learned sparse retrieval and when you'd use it."</b></summary>

**Initial Prompt.** The team runs OpenSearch and wants neural gains without a vector DB.

**L5 Answer.** "Just add a vector field."

**Why L5 Fails in Production.** It's an option, but it ignores a path that keeps the existing inverted-index infrastructure and its exact-match strengths.

**L7 Principal Defense.** "SPLADE-style models predict per-vocabulary-term weights with a transformer, including expansion terms not in the text, and the result is indexed as ordinary sparse postings. You keep BM25-style infrastructure, interpretability and pruning, and gain learned term importance and synonyms. Costs: GPU encoding at index time, larger postings (so pruning matters more), and a model to version. I'd A/B it against BM25 + dense hybrid on our eval, since hybrid is often as good and simpler if a vector field is already available."

**Bar-Raiser Follow-ups.**
- *"Interpretability?"* Each document's top weighted terms are inspectable, unlike a dense vector, which is valuable for debugging.

</details>

---

## 7. Invariants Checklist

- [ ] The same analyzer (tokenization, case, stop words, stemming) runs at index and query time, and is versioned with the index.
- [ ] Identifier fields use keyword analyzers and get exact-match boosts. Identifier-shaped queries have a dedicated path.
- [ ] BM25 uses saturation (k1 ≈ 1.2) and a non-negative idf. Raw-tf scoring is never shipped.
- [ ] Parameter tuning claims come with held-out confirmation and bootstrap intervals.
- [ ] Top-k queries allow dynamic pruning. Exact total-hit counts are opt-in.
- [ ] Lexical retrieval runs alongside dense retrieval (hybrid) unless error analysis shows no lexical-only wins.
- [ ] The relevance-judged eval set exists before analyzer changes, and label gaps found in error analysis are fed back into it.

---

## 8. References

1. S. Robertson, H. Zaragoza, *The Probabilistic Relevance Framework: BM25 and Beyond*, Foundations and Trends in IR 3(4), 2009. DOI 10.1561/1500000019.
2. K. Spärck Jones, *A statistical interpretation of term specificity and its application in retrieval*, Journal of Documentation 28(1), 1972. DOI 10.1108/eb026526.
3. N. Thakur et al., *BEIR: A Heterogeneous Benchmark for Zero-shot Evaluation of Information Retrieval Models*, NeurIPS 2021 Datasets & Benchmarks. https://arxiv.org/abs/2104.08663
4. D. Wadden et al., *Fact or Fiction: Verifying Scientific Claims* (SciFact), EMNLP 2020. https://arxiv.org/abs/2004.14974
5. H. Turtle, J. Flood, *Query evaluation: Strategies and optimizations* (MaxScore), Information Processing & Management 31(6), 1995. DOI 10.1016/0306-4573(95)00020-H.
6. A. Broder et al., *Efficient query evaluation using a two-level retrieval process* (WAND), CIKM 2003. DOI 10.1145/956863.956944.
7. C. Manning, P. Raghavan, H. Schütze, *Introduction to Information Retrieval*, Cambridge 2008 (free online). https://nlp.stanford.edu/IR-book/
8. Apache Lucene, `BM25Similarity` (idf = log(1 + (N − n + 0.5)/(n + 0.5))). https://lucene.apache.org/core/9_0_0/core/org/apache/lucene/search/similarities/BM25Similarity.html
9. T. Formal et al., *SPLADE: Sparse Lexical and Expansion Model for First Stage Ranking*, SIGIR 2021. https://arxiv.org/abs/2107.05720
