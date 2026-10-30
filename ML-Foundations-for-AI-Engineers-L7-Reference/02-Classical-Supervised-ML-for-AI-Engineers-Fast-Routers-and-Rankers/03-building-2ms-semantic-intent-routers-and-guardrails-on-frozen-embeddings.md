# 02.3 · Building 2 ms Semantic Intent Routers & Guardrails on Frozen Embeddings

> **Folder 02 · Classical Supervised ML for AI Engineers: Fast Routers & Rankers**
> **Measured on:** ONNX Runtime 1.31.1 (CPU), PyTorch 2.14.1 (legacy TorchScript ONNX exporter), transformers 5.22.0, scikit-learn 1.9.1, LightGBM 4.7.0, Intel i5-11260H, Windows 11.
> **Real data:** CLINC150 (150 intents + out-of-scope) and `deepset/prompt-injections` (546 train / 116 test prompts, English and German), both encoded with `all-MiniLM-L6-v2`.
> **Design sources:** Larson et al. (CLINC150), Hendrycks & Gimpel (2017), the ONNX Runtime quantization docs, the PyTorch ONNX export docs, Tunstall et al. (SetFit). Full list in §8.

---

## 0. Orientation: The Brief Said "2 ms". We Measured It.

A semantic router is three stages. Each has a budget, and the first one dominates:

```text
 request text
     │  tokenize (WordPiece, Rust)          0.09 ms
     ▼
 [ encoder ]  MiniLM-L6, 384-d             1.9–11 ms   ← where the time goes; runtime + precision decide it
     │ unit vector x
     ▼
 [ head ]     W·x + b → softmax            0.016 ms    (NumPy; 02.1)
     │ p(intent), confidence
     ▼
 [ policy ]   confidence ≥ τ ?  ── yes ──► handle locally (intent i)
                  │ no
                  └──────────────────────► escalate (LLM classifier / human / "I can't help with that")
```

Measured end to end on this laptop CPU (tokenize + encode + head, 200 real CLINC queries, §3.2):

| Runtime | Threads | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| PyTorch eager fp32 | 1 | 11.42 ms | 13.73 ms | 14.58 ms |
| ONNX Runtime fp32 | 1 | 4.94 ms | 6.37 ms | 6.73 ms |
| **ONNX Runtime int8** | 1 | **2.18 ms** | 3.01 ms | 3.38 ms |
| **ONNX Runtime int8** | 4 | **1.95 ms** | 2.79 ms | 3.02 ms |

So yes: **a 2 ms semantic router is real on a laptop CPU**, with ONNX export plus dynamic int8 quantization. The cost is 0.6 points of routing accuracy (0.9547 → 0.9484). Eager PyTorch at 1 thread is 5× slower. The rest of this file is about making the router *correct*: picking the head, catching out-of-scope traffic, choosing thresholds you can defend, and building a guardrail on the same encoder.

### The backend-engineer bridge

| You already know | Router equivalent |
|---|---|
| An API gateway with route rules and a default backend | Head = route rules learned from data. Escalation = the default backend (the LLM) |
| 404 for unknown paths, not a random handler | **Out-of-scope detection**: refuse to route what doesn't match any intent |
| Choosing an alert threshold on staging, then confirming in prod | **Threshold chosen on validation, reported once on test**, with prevalence matched to production |
| A WAF rule set plus an anomaly model | **Guardrail head**: lexical features (rules-like) plus semantic features (embedding) |
| Precompiled, ahead-of-time builds for hot paths | **ONNX export + int8 quantization** of the encoder |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The latency budget and why the encoder dominates | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 ONNX export and dynamic int8 quantization | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Choosing the head: centroid, kNN, LR, LR + OOS class, hybrid | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Out-of-scope detection: softmax confidence vs distance | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Thresholds on validation, prevalence on test | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Guardrail heads: lexical vs semantic features, language coverage | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Small evaluation sets need intervals | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Serving architecture: batching, versioning, shadowing | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.9 When to fine-tune the encoder (SetFit) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Energy-based and density-ratio OOD theory | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The latency budget and why the encoder dominates `[MUST-KNOW: Core AI Engineer Edge]`

FLOPs per query for MiniLM-L6 (6 layers, hidden 384, MLP 1536) on a 12-token query, ignoring attention's small n² term:

```text
per layer:  QKV + output projections  4·384·384      = 589,824 MACs/token
            MLP 384→1536→384          2·384·1536     = 1,179,648 MACs/token
            ≈ 1.77M MACs/token × 6 layers ≈ 10.6M MACs/token
12 tokens → ~127M MACs ≈ 0.25 GFLOP per query
head:       150 × 384 = 57,600 MACs  (≈ 2,200× less than the encoder)
```

At a few tens of GFLOP/s of effective single-core throughput, the encoder math alone is a few milliseconds. Everything around it (Python dispatch, per-op overhead, allocation) is what separates 11.4 ms in eager PyTorch from 4.9 ms in ONNX Runtime fp32 at one thread. **Optimize the encoder runtime first.** The head and policy are rounding error.

The listing also measures the **tokenizer alone at 0.091 ms per query** (the Rust `tokenizers` library), so it's never the bottleneck.

### 1.2 ONNX export and dynamic int8 quantization `[MUST-KNOW: Core AI Engineer Edge]`

**Export.** Wrap the encoder *and* the pooling and normalization in one `nn.Module`, so the exported graph returns the final sentence embedding. Pooling outside the graph is a classic source of training/serving skew. Two practical notes from this run:

- PyTorch 2.9+ defaults to the torch.export-based exporter. We used the legacy TorchScript exporter (`dynamo=False`), which still works in 2.14.1 but emits a deprecation warning.
- `transformers` 5.x changed `BertModel.forward`'s positional arguments, so the wrapper passes `input_ids=` and `attention_mask=` by keyword. Exporting the bare model positionally failed with "got multiple values for argument 'use_cache'".

The ONNX fp32 graph reproduces PyTorch exactly (mean cosine 1.000000, min 1.0000, identical accuracy).

**Dynamic int8 quantization** (`onnxruntime.quantization.quantize_dynamic`, `QInt8` weights):

- **Weights** of every MatMul and Gemm are quantized offline to int8 with a scale per tensor.
- **Activations** are quantized on the fly, per batch, from their observed range. No calibration dataset is needed, which is the "dynamic" part.
- The MatMuls then run as int8 × int8 → int32 accumulation (the same symmetric-quantization algebra as 01.1 §1.10), followed by a rescale.

```text
                    file size     cos vs torch: mean    min      test acc   OOS AUROC
torch fp32              —              1.000000        1.0000     0.9547     0.9656
onnx fp32           86.2 MiB           1.000000        1.0000     0.9547     0.9656
onnx int8           21.8 MiB           0.960520        0.7837     0.9484     0.9619
```

That's 4× smaller and 2.3× faster at one thread (4.94 → 2.18 ms p50), for −0.63 points of accuracy and −0.004 OOS AUROC. Note the **min cosine of 0.78**: a few embeddings move a lot. Dynamic quantization uses a single scale per weight tensor and quantizes activations with outliers poorly. If those rare large distortions matter, the levers are:

- per-channel quantization;
- excluding sensitive layers (attention output, the final projection) from quantization;
- static quantization with a calibration set;
- the ONNX Runtime pre-processing pass that the quantizer itself recommends (the "consider to run pre-processing before quantization" warning in the run log).

**Gate any quantized encoder on your task metric, not on average cosine.**

### 1.3 Choosing the head `[MUST-KNOW: Core AI Engineer Edge]`

Five heads on the same CLINC embeddings (§3.1, test set):

```text
head                                   in-scope acc  OOS AUROC  FPR@95%TPR
centroid (max cosine)                        0.9167     0.9656       0.173
5-NN (mean top-5 cosine)                     0.8953     0.9655       0.168
LR + temperature T=0.62 (max prob)           0.9547     0.9451       0.314
LR with 'oos' class (1 - P(oos))             0.9544     0.9559       0.179
hybrid: LR intent, cosine OOS gate           0.9547     0.9656       0.173
```

- **For picking the intent, LR wins** (0.955 vs 0.917 for centroids). It learns discriminative directions between sibling intents (02.1 §1.5).
- **For deciding whether to route at all, distance wins.** Max cosine to the nearest centroid separates out-of-scope traffic better (AUROC 0.966) than LR's max softmax probability (0.945). At the threshold that keeps 95% of in-scope traffic, softmax lets **31.4%** of OOS through, cosine 17.3%.
- **The hybrid takes the best of both:** LR chooses the intent, centroid cosine gates the decision. Same in-scope accuracy as LR, same OOS detection as centroids, and the best end-to-end score (next section).
- **A trained "oos" class** (from only 100 out-of-scope examples) helps LR's detection (0.956), but you can never enumerate everything out of scope.

### 1.4 Out-of-scope detection: softmax confidence vs distance `[MUST-KNOW: Core AI Engineer Edge]`

Why does max-probability underperform? Softmax normalizes over the *known* classes only. Its confidence measures how much one known class beats the others, not how close the input is to *any* of them. An out-of-scope query far from every intent can still be closer to one than to the rest, and softmax turns that relative win into high confidence. Hendrycks & Gimpel (2017) established max softmax probability as the standard *baseline* for this problem precisely because it's simple and only moderately good.

```text
      intent A ●                        ● intent B
                  ╲                   ╱
                    ╲  in-scope     ╱
                      ●  query (close to A, far from B → high softmax, high cosine)

                                           ★ out-of-scope query: far from BOTH,
                                             but a bit closer to B → softmax still says "B, 0.8"
                                             max cosine is low → the distance gate catches it
```

**Distance-based scores** (max cosine to class centroids, kNN similarity, and Mahalanobis distance in Folder 03) measure absolute closeness to the training distribution, which is the question an OOS gate is asking. The listing's numbers are one dataset with one encoder. The *direction* of the result is consistent with the OOD literature, but the size of the gap is data-dependent, so measure it on yours.

### 1.5 Thresholds on validation, prevalence on test `[MUST-KNOW: Core AI Engineer Edge]`

The deployable protocol: pick τ on validation, then report **once** on test. The metric that matters is 151-class accuracy, where in-scope queries must be answered correctly and OOS queries must be escalated:

```text
head                                      thr in-scope acc OOS recall 151-class acc escalated
LR + temperature T=0.62 (max prob)      0.414       0.9504     0.4010        0.8505     0.082
LR with 'oos' class (1 - P(oos))        0.894       0.9507     0.5020        0.8691     0.095
hybrid: LR intent, cosine OOS gate      0.340       0.9511     0.5260        0.8738     0.101
```

Two production lessons hide in this table:

1. **The hybrid wins end to end** (0.874) for the reason in §1.4.
2. **OOS recall is low for every head (0.40–0.63)**, and the cause is the validation set, not the models. CLINC's validation split is **3.2%** out-of-scope (100 of 3,100), while its test split is **18.2%** (1,000 of 5,500). A threshold that maximizes accuracy on 3% OOS traffic sacrifices OOS recall cheaply, and that bill comes due when OOS is 18%. This is 01.3 §4.1 in practice: **choose thresholds on data with production prevalence, or reweight the validation set to it.** If your production OOS rate is 15%, weight the 100 OOS validation examples to 15% of the objective before picking τ.

### 1.6 Guardrail heads: lexical vs semantic features, and language coverage `[MUST-KNOW: Core AI Engineer Edge]`

The same frozen-embedding recipe gives a prompt-injection guardrail. On the real `deepset/prompt-injections` data (§3.3):

```text
head                                    ROC-AUC          avg precision
TF-IDF word+char + LR       0.975 [0.951, 0.993]    0.980 [0.958, 0.994]
MiniLM + LR                 0.938 [0.897, 0.974]    0.949 [0.907, 0.979]
MiniLM + LightGBM           0.960 [0.926, 0.987]    0.963 [0.928, 0.989]
```

**Lexical features beat the semantic encoder here.** Injections share *surface forms* ("ignore all previous instructions", "forget everything", "vergiss alles"), and character n-grams catch them, along with misspellings and German compounds, without needing an encoder to understand them. MiniLM averages a whole prompt into one vector, which dilutes a short injected clause inside a long benign request. And for once, LightGBM on embeddings beats LR (0.960 vs 0.938). With only 546 examples and a lexically driven target, the GBDT picks up a few informative directions. Overlapping intervals mean the comparison isn't settled (§1.7).

**Language coverage is an error-analysis finding, not a footnote.** A stop-word heuristic tags 27.5% of training and 32.8% of test prompts as German:

```text
head                      EN errors  DE errors  DE injections missed
TF-IDF word+char + LR         0.090      0.211              8 of 23
MiniLM + LR                   0.141      0.184              7 of 23
```

Every head errs about twice as often on German. all-MiniLM-L6-v2 is an English model, and the German slice is a third of the data but under-represented in what the features capture. The data-centric fix is clear: a multilingual encoder, more German training data, or a language-routed pair of heads. A bigger English model wouldn't help.

**Production design for a guardrail.** Combine both feature families: TF-IDF char n-grams plus embedding plus a few regex rules for known attack strings, feeding one calibrated head with a cost-derived threshold (01.3 §1.3). Escalate the uncertain band to an LLM judge.

### 1.7 Small evaluation sets need intervals `[MUST-KNOW: Core AI Engineer Edge]`

With 116 test prompts, the 95% bootstrap interval for MiniLM + LR's AUC is **[0.897, 0.974]**, a 7.7-point span. The TF-IDF head's interval [0.951, 0.993] overlaps the LightGBM head's [0.926, 0.987]. So "TF-IDF is better than MiniLM + LightGBM" isn't established by this test set, while "TF-IDF beats MiniLM + LR" is suggestive at best. Rules:

- Always report intervals for evals under a few thousand examples. A paired bootstrap of the *difference* is the right test for "A beats B" (Folder 06).
- Small test sets also make threshold estimates noisy. The listing picks thresholds from **out-of-fold training scores** (5-fold cross-validated predictions), not from the test set, then reports test FPR and recall once: for example, TF-IDF at threshold 0.502 gives FPR 0.000 and recall 0.733 on test.
- Note the prevalence again: 37.2% injections in train vs 51.7% in test. Precision computed on either split isn't production precision.

### 1.8 Serving architecture: batching, versioning, shadowing `[GOOD-TO-KNOW: Architectural Literacy]`

- **One encoder, many heads.** The router, the OOS gate, the guardrail and the semantic-cache key all reuse one embedding call per request. The encoder version is the contract every head pins (02.1 F4).
- **Micro-batching.** At high QPS, collect requests for 1–2 ms and run them as one ONNX batch: per-query cost falls, at the price of a little latency.
- **Shadow deployment.** Run a new head (or a quantized encoder) on live traffic without acting on it, and compare decisions and calibration before switching. Encoder changes require re-deriving every threshold (01.1 §1.7).
- **Log for the flywheel.** Store (embedding version, head version, scores, decision, LLM fallback answer). Escalated traffic labelled by the LLM, audited by humans, is the next training set.

### 1.9 When to fine-tune the encoder (SetFit) `[GOOD-TO-KNOW: Architectural Literacy]`

Freeze first, and fine-tune when error analysis shows representational failure: sibling intents the encoder can't separate, a language it doesn't cover, domain jargon. SetFit (Tunstall et al., 2022) is the few-shot recipe:

1. Generate positive and negative *pairs* from the few labelled examples.
2. Contrastively fine-tune the sentence encoder on those pairs (Folder 04 explains the loss).
3. Train a logistic head on the new embeddings.

It keeps this file's serving architecture intact: still an encoder plus a linear head, still exportable to ONNX int8.

### 1.10 Energy-based and density-ratio OOD theory `[SKIP: Academic/Research Only]`

Energy scores (log-sum-exp of logits), likelihood ratios against background models, and OOD generalization bounds are active research. For production routers, the distance-based gates here and the Mahalanobis gate in Folder 03, evaluated on a labelled OOS set at production prevalence, are what to ship.

---

## 2. Where It Beats an LLM in Production

| Dimension | 2 ms router + guardrail on one encoder | LLM classifier per request |
|---|---|---|
| Latency | 1.95–2.18 ms p50 end to end on a laptop CPU (int8 ONNX) | A generation round trip, typically far slower than an encoder pass (measure your provider) |
| Cost | CPU time only; the encoder is shared by every head | Tokens per request, 113×–4,533× an embedding API call by tier (01.1 §2) |
| Calibrated confidence | Yes (temperature, 02.1), so it supports thresholds and cascades | No log-probs on some APIs (01.3 §1.16) |
| OOS handling | A measured gate (AUROC 0.966) with a chosen operating point | Prompt-dependent, hard to audit |
| Retraining | Seconds (head), minutes (SetFit encoder) | A prompt change re-validated by hand |
| Where it loses | Multi-clause requests, negation, day-0 intents with no data, non-English text for an English encoder | Handles all of these, at a price |

The production pattern is the **cascade**: the router answers the confident in-scope majority locally, and everything below τ (out of scope, ambiguous, multi-intent) escalates. Folder 07 optimizes the thresholds against cost.

---

## 3. Production Code Blueprint

### 3.1 Five router heads, OOS detection, and a deployable threshold

```python
"""clinc_router_heads_and_oos.py - four router heads on frozen MiniLM embeddings, scored the way production needs.

CLINC150: 150 in-scope intents plus out-of-scope (OOS) queries that must NOT be routed to any intent.
  1. Heads: nearest centroid, 5-NN, logistic regression (+ temperature), LR with an explicit 'oos' class
     trained on the 100 OOS training examples, and a hybrid (LR picks the intent, centroid cosine gates OOS).
  2. OOS detection from each head's confidence: AUROC and FPR at 95% in-scope recall.
  3. A deployable policy: the escalation threshold is chosen on VALIDATION, then reported once on TEST
     (in-scope accuracy, OOS recall, accuracy over all 151 classes).
"""
import os

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score

Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
Xtr, ytr = Z["X_train"], Z["y_train"]
Xva, yva, Xte, yte = Z["X_val"], Z["y_val"], Z["X_test"], Z["y_test"]
Ova, Ote, Otr = Z["X_oos_val"], Z["X_oos_test"], Z["X_oos_train"]
K = 150
sm = lambda z: np.exp(z - z.max(1, keepdims=True)) / np.exp(z - z.max(1, keepdims=True)).sum(1, keepdims=True)

C_ = np.stack([Xtr[ytr == c].mean(0) for c in range(K)])
C_ /= np.linalg.norm(C_, axis=1, keepdims=True)
lr = LogisticRegression(C=10, max_iter=3000).fit(Xtr, ytr)
Ts = np.geomspace(0.2, 5, 120)
T = Ts[int(np.argmin([-np.mean(np.log(sm(lr.decision_function(Xva) / t)[np.arange(len(yva)), yva])) for t in Ts]))]
lr_oos = LogisticRegression(C=10, max_iter=3000).fit(np.vstack([Xtr, Otr]), np.r_[ytr, np.full(len(Otr), K)])


def head_scores(X):
    """Return {head: (predicted intent, confidence)}; higher confidence = more in-scope."""
    cos = X @ C_.T
    nn = np.argsort(-(X @ Xtr.T), axis=1)[:, :5]
    nn_lab = ytr[nn]
    knn_pred = np.array([np.bincount(r, minlength=K).argmax() for r in nn_lab])
    knn_conf = np.sort(X @ Xtr.T, axis=1)[:, -5:].mean(1)
    p = sm(lr.decision_function(X) / T)
    q = lr_oos.predict_proba(X)
    return {"centroid (max cosine)": (cos.argmax(1), cos.max(1)),
            "5-NN (mean top-5 cosine)": (knn_pred, knn_conf),
            f"LR + temperature T={T:.2f} (max prob)": (p.argmax(1), p.max(1)),
            "LR with 'oos' class (1 - P(oos))": (q[:, :K].argmax(1), 1 - q[:, K]),
            "hybrid: LR intent, cosine OOS gate": (p.argmax(1), cos.max(1))}


S_va_in, S_va_oos = head_scores(Xva), head_scores(Ova)
S_te_in, S_te_oos = head_scores(Xte), head_scores(Ote)

print("== 1-2. in-scope accuracy (no abstention) and OOS detection on TEST ==")
print(f"{'head':38s} {'in-scope acc':>12} {'OOS AUROC':>10} {'FPR@95%TPR':>11}")
for h in S_te_in:
    pred, conf_in = S_te_in[h]
    _, conf_oos = S_te_oos[h]
    auroc = roc_auc_score(np.r_[np.ones(len(conf_in)), np.zeros(len(conf_oos))], np.r_[conf_in, conf_oos])
    thr95 = np.quantile(conf_in, 0.05)                            # keeps 95% of in-scope traffic
    print(f"{h:38s} {np.mean(pred == yte):>12.4f} {auroc:>10.4f} {np.mean(conf_oos >= thr95):>11.3f}")

print("\n== 3. escalation policy: threshold chosen on VALIDATION, reported on TEST ==")
print(f"{'head':38s} {'thr':>6} {'in-scope acc':>12} {'OOS recall':>10} {'151-class acc':>13} {'escalated':>9}")
best = {}
for h in S_va_in:
    pv, cv = S_va_in[h]
    _, co = S_va_oos[h]
    grid = np.quantile(np.r_[cv, co], np.linspace(0.01, 0.6, 120))
    # 151-way accuracy on validation: in-scope must be answered correctly, OOS must be escalated
    acc151 = [((np.sum((cv >= t) & (pv == yva)) + np.sum(co < t)) / (len(cv) + len(co))) for t in grid]
    t = grid[int(np.argmax(acc151))]
    pt, ct = S_te_in[h]
    _, cot = S_te_oos[h]
    ins = np.mean((ct >= t) & (pt == yte))
    oos_rec = np.mean(cot < t)
    a151 = (np.sum((ct >= t) & (pt == yte)) + np.sum(cot < t)) / (len(ct) + len(cot))
    esc = (np.sum(ct < t) + np.sum(cot < t)) / (len(ct) + len(cot))
    best[h] = a151
    print(f"{h:38s} {t:>6.3f} {ins:>12.4f} {oos_rec:>10.4f} {a151:>13.4f} {esc:>9.3f}")
lr_key = [k for k in best if k.startswith("LR + temperature")][0]
assert best[lr_key] > best["centroid (max cosine)"] and best["hybrid: LR intent, cosine OOS gate"] == max(best.values())
print("\nin-scope acc = answered locally AND correct (an escalated in-scope query counts as not-correct here,")
print("because the LLM fallback's accuracy is unknown); OOS recall = OOS queries escalated instead of misrouted.")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1-2. in-scope accuracy (no abstention) and OOS detection on TEST ==
head                                   in-scope acc  OOS AUROC  FPR@95%TPR
centroid (max cosine)                        0.9167     0.9656       0.173
5-NN (mean top-5 cosine)                     0.8953     0.9655       0.168
LR + temperature T=0.62 (max prob)           0.9547     0.9451       0.314
LR with 'oos' class (1 - P(oos))             0.9544     0.9559       0.179
hybrid: LR intent, cosine OOS gate           0.9547     0.9656       0.173

== 3. escalation policy: threshold chosen on VALIDATION, reported on TEST ==
head                                      thr in-scope acc OOS recall 151-class acc escalated
centroid (max cosine)                   0.340       0.9138     0.5260        0.8433     0.101
5-NN (mean top-5 cosine)                0.447       0.8847     0.6260        0.8376     0.127
LR + temperature T=0.62 (max prob)      0.414       0.9504     0.4010        0.8505     0.082
LR with 'oos' class (1 - P(oos))        0.894       0.9507     0.5020        0.8691     0.095
hybrid: LR intent, cosine OOS gate      0.340       0.9511     0.5260        0.8738     0.101

in-scope acc = answered locally AND correct (an escalated in-scope query counts as not-correct here,
because the LLM fallback's accuracy is unknown); OOS recall = OOS queries escalated instead of misrouted.

ALL ASSERTIONS PASSED
```

How to read it:

- **Section 1–2** separates two jobs that people conflate: *which intent* (LR is best) and *whether to route* (distance is best).
- **Section 3's thresholds** come from validation only. Re-running with a production-prevalence-weighted objective is the single most valuable change for a real deployment (§1.5).

### 3.2 The 2 ms path: ONNX export, int8 quantization, end-to-end latency

```python
"""onnx_int8_router_latency.py - is a "2 ms" semantic router real on a laptop CPU? Measure the whole path.

  1. Export the sentence encoder (MiniLM + mean pooling + L2 normalize, one graph) to ONNX; check it against PyTorch.
  2. Dynamic int8 quantization (onnxruntime.quantization): file size, embedding fidelity, router accuracy.
  3. End-to-end single-query latency = tokenize + encode + LR head, for PyTorch eager, ORT fp32 and ORT int8,
     at 1 and 4 intra-op threads.
"""
import os
import time
import warnings

import numpy as np
import onnxruntime as ort
import torch
from onnxruntime.quantization import QuantType, quantize_dynamic
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from transformers import AutoModel, AutoTokenizer

warnings.filterwarnings("ignore")
DL, DATA = os.environ["KB_DL"], os.environ["KB_DATA"]
mdir = os.path.join(DL, "models", "minilm")
tok = AutoTokenizer.from_pretrained(mdir)
bert = AutoModel.from_pretrained(mdir, use_safetensors=True).eval()
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
import json
texts = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))["texts"]


class SentenceEncoder(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, input_ids, attention_mask):
        h = self.m(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
        mask = attention_mask.unsqueeze(-1).to(h.dtype)
        e = (h * mask).sum(1) / mask.sum(1).clamp(min=1e-9)
        return torch.nn.functional.normalize(e, dim=-1)


enc_mod = SentenceEncoder(bert).eval()
fp32_path, int8_path = os.path.join(DATA, "minilm_sentence.onnx"), os.path.join(DATA, "minilm_sentence.int8.onnx")
ex = tok(["how would you say fly in italian"], return_tensors="pt")
torch.onnx.export(enc_mod, (ex["input_ids"], ex["attention_mask"]), fp32_path, dynamo=False, opset_version=17,
                  input_names=["input_ids", "attention_mask"], output_names=["embedding"],
                  dynamic_axes={"input_ids": {0: "b", 1: "s"}, "attention_mask": {0: "b", 1: "s"}, "embedding": {0: "b"}})
quantize_dynamic(fp32_path, int8_path, weight_type=QuantType.QInt8)
print(f"== 1-2. model files: fp32 {os.path.getsize(fp32_path) / 2**20:.1f} MiB, int8 {os.path.getsize(int8_path) / 2**20:.1f} MiB")


def session(path, threads):
    so = ort.SessionOptions()
    so.intra_op_num_threads = threads
    so.inter_op_num_threads = 1
    return ort.InferenceSession(path, so, providers=["CPUExecutionProvider"])


def ort_encode(sess, batch_texts):
    e = tok(batch_texts, padding=True, truncation=True, max_length=128, return_tensors="np")
    return sess.run(None, {"input_ids": e["input_ids"].astype(np.int64), "attention_mask": e["attention_mask"].astype(np.int64)})[0]


def encode_all(sess, ts, bs=64):
    order = np.argsort([len(t) for t in ts])
    out = np.zeros((len(ts), 384), np.float32)
    for i in range(0, len(ts), bs):
        idx = order[i:i + bs]
        out[idx] = ort_encode(sess, [ts[j] for j in idx])
    return out


lr = LogisticRegression(C=10, max_iter=3000).fit(Z["X_train"], Z["y_train"])
cent = np.stack([Z["X_train"][Z["y_train"] == c].mean(0) for c in range(150)])
cent /= np.linalg.norm(cent, axis=1, keepdims=True)
print(f"{'encoder':14s} {'cos vs torch: mean':>18} {'min':>7} {'test acc':>9} {'OOS AUROC':>10}")
rows = {}
for name, X_in, X_oos in (("torch fp32", Z["X_test"], Z["X_oos_test"]),) + tuple(
        (n, encode_all(session(p, 4), texts["test"]), encode_all(session(p, 4), texts["oos_test"]))
        for n, p in (("onnx fp32", fp32_path), ("onnx int8", int8_path))):
    cs = np.sum(X_in * Z["X_test"], 1)
    acc = lr.score(X_in, Z["y_test"])
    auroc = roc_auc_score(np.r_[np.ones(len(X_in)), np.zeros(len(X_oos))],
                          np.r_[(X_in @ cent.T).max(1), (X_oos @ cent.T).max(1)])
    rows[name] = (cs.min(), acc, auroc)
    print(f"{name:14s} {cs.mean():>18.6f} {cs.min():>7.4f} {acc:>9.4f} {auroc:>10.4f}")
assert rows["onnx fp32"][0] > 0.9999 and abs(rows["onnx int8"][1] - rows["torch fp32"][1]) < 0.01

print("\n== 3. end-to-end single query: tokenize + encode + LR head (200 test queries, one measured run) ==")
W, b = lr.coef_.astype(np.float32), lr.intercept_.astype(np.float32)
qs = texts["test"][:200]


@torch.inference_mode()
def torch_route(q):
    e = tok([q], return_tensors="pt")
    v = enc_mod(e["input_ids"], e["attention_mask"]).numpy()
    return int(np.argmax(v @ W.T + b))


print(f"{'path':20s} {'threads':>7} {'p50 ms':>7} {'p95 ms':>7} {'p99 ms':>7}")
p50 = {}
for name, path in (("pytorch eager fp32", None), ("onnxruntime fp32", fp32_path), ("onnxruntime int8", int8_path)):
    for th in (1, 4):
        if path is None:
            torch.set_num_threads(th)
            fn = torch_route
        else:
            s = session(path, th)
            fn = lambda q, s=s: int(np.argmax(ort_encode(s, [q]) @ W.T + b))
        for q in qs[:20]:
            fn(q)
        ts = []
        for q in qs:
            t0 = time.perf_counter()
            fn(q)
            ts.append((time.perf_counter() - t0) * 1e3)
        p50[(name, th)] = np.percentile(ts, 50)
        print(f"{name:20s} {th:>7} {np.percentile(ts, 50):>7.2f} {np.percentile(ts, 95):>7.2f} {np.percentile(ts, 99):>7.2f}")
assert p50[("onnxruntime int8", 1)] < p50[("pytorch eager fp32", 1)]
t0 = time.perf_counter()
for _ in range(200):
    tok([qs[0]], return_tensors="np")
print(f"tokenizer alone: {(time.perf_counter() - t0) / 200 * 1e3:.3f} ms per query")
print("\nALL ASSERTIONS PASSED")
```

Output (verified; the latency table is one measured run):

```text
== 1-2. model files: fp32 86.2 MiB, int8 21.8 MiB
encoder        cos vs torch: mean     min  test acc  OOS AUROC
torch fp32               1.000000  1.0000    0.9547     0.9656
onnx fp32                1.000000  1.0000    0.9547     0.9656
onnx int8                0.960520  0.7837    0.9484     0.9619

== 3. end-to-end single query: tokenize + encode + LR head (200 test queries, one measured run) ==
path                 threads  p50 ms  p95 ms  p99 ms
pytorch eager fp32         1   11.42   13.73   14.58
pytorch eager fp32         4    7.98   10.39   11.41
onnxruntime fp32           1    4.94    6.37    6.73
onnxruntime fp32           4    3.10    3.96    4.57
onnxruntime int8           1    2.18    3.01    3.38
onnxruntime int8           4    1.95    2.79    3.02
tokenizer alone: 0.091 ms per query

ALL ASSERTIONS PASSED
```

How to read it:

- **Fidelity before speed.** ONNX fp32 is bit-for-bit equivalent in task terms. int8 trades 0.6 points of accuracy for 2.3× speed and 4× size.
- **Threads matter less after quantization.** int8 goes from 2.18 ms at 1 thread to 1.95 ms at 4. For a CPU fleet, one thread per worker process with more processes usually beats fewer, wider workers.
- **p99 stays tight** (3.02–3.38 ms for int8). Short queries, a fixed model and no Python graph overhead give a narrow tail.

### 3.3 A prompt-injection guardrail on real data

```python
"""prompt_injection_guardrail_head.py - a prompt-injection guardrail on real labelled data (deepset/prompt-injections).

  1. Three cheap heads: TF-IDF (word + char n-grams) + LR, frozen MiniLM + LR, frozen MiniLM + LightGBM.
  2. ROC-AUC and average precision with bootstrap 95% intervals: the test set is only 116 prompts.
  3. Error analysis by language: the dataset mixes English and German, and all-MiniLM-L6-v2 is an English model.
  4. A threshold chosen from out-of-fold training scores for a target false-positive rate, then applied to test.
"""
import os

import lightgbm as lgb
import numpy as np
import pyarrow.parquet as pq
import torch
from scipy.sparse import hstack
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.model_selection import cross_val_predict
from transformers import AutoModel, AutoTokenizer

DL = os.environ["KB_DL"]
files = sorted(os.listdir(os.path.join(DL, "pinj")))
tr = pq.read_table(os.path.join(DL, "pinj", [f for f in files if f.startswith("train")][0])).to_pydict()
te = pq.read_table(os.path.join(DL, "pinj", [f for f in files if f.startswith("test")][0])).to_pydict()
Ttr, ytr, Tte, yte = tr["text"], np.array(tr["label"]), te["text"], np.array(te["label"])
print(f"train {len(Ttr)} ({ytr.mean():.1%} injections), test {len(Tte)} ({yte.mean():.1%} injections)")

GERMAN = {"und", "der", "die", "das", "ich", "nicht", "ist", "sie", "wie", "mit", "auf", "für", "ein", "eine", "zu", "du"}
is_de = lambda t: len(GERMAN & set(t.lower().replace("?", " ").replace(".", " ").split())) >= 2
de_tr, de_te = np.array([is_de(t) for t in Ttr]), np.array([is_de(t) for t in Tte])
print(f"German (stop-word heuristic): train {de_tr.mean():.1%}, test {de_te.mean():.1%}")

mdir = os.path.join(DL, "models", "minilm")
tok = AutoTokenizer.from_pretrained(mdir)
model = AutoModel.from_pretrained(mdir, use_safetensors=True).eval()
torch.set_num_threads(4)


@torch.inference_mode()
def embed(texts):
    out = []
    for i in range(0, len(texts), 64):
        e = tok(texts[i:i + 64], padding=True, truncation=True, max_length=256, return_tensors="pt")
        h = model(**e).last_hidden_state
        m = e["attention_mask"].unsqueeze(-1).float()
        out.append(torch.nn.functional.normalize((h * m).sum(1) / m.sum(1), dim=-1).numpy())
    return np.vstack(out)


Etr, Ete = embed(Ttr), embed(Tte)
word = TfidfVectorizer(ngram_range=(1, 2), min_df=2, sublinear_tf=True).fit(Ttr)
char = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), min_df=2, sublinear_tf=True).fit(Ttr)
Ftr, Fte = hstack([word.transform(Ttr), char.transform(Ttr)]).tocsr(), hstack([word.transform(Tte), char.transform(Tte)]).tocsr()
heads = {
    "TF-IDF word+char + LR": (LogisticRegression(C=10, max_iter=5000), Ftr, Fte),
    "MiniLM + LR": (LogisticRegression(C=10, max_iter=5000), Etr, Ete),
    "MiniLM + LightGBM": (lgb.LGBMClassifier(n_estimators=300, learning_rate=0.05, num_leaves=7, min_child_samples=5,
                                             verbose=-1, num_threads=1, seed=0), Etr, Ete),
}
rng = np.random.default_rng(0)
boot = [rng.integers(0, len(yte), len(yte)) for _ in range(1000)]

print(f"\n== 1-2. test metrics (95% bootstrap intervals) ==")
print(f"{'head':24s} {'ROC-AUC':>22} {'avg precision':>22}")
scores, oof = {}, {}
for name, (clf, A, B) in heads.items():
    clf.fit(A, ytr)
    s = clf.predict_proba(B)[:, 1]
    scores[name] = s
    oof[name] = cross_val_predict(clf, A, ytr, cv=5, method="predict_proba")[:, 1]
    aucs = [roc_auc_score(yte[i], s[i]) for i in boot if 0 < yte[i].sum() < len(i)]
    aps = [average_precision_score(yte[i], s[i]) for i in boot if yte[i].sum() > 0]
    print(f"{name:24s} {roc_auc_score(yte, s):>8.3f} [{np.percentile(aucs, 2.5):.3f}, {np.percentile(aucs, 97.5):.3f}]"
          f" {average_precision_score(yte, s):>8.3f} [{np.percentile(aps, 2.5):.3f}, {np.percentile(aps, 97.5):.3f}]")

print("\n== 3. error analysis by language (test, threshold 0.5) ==")
print(f"{'head':24s} {'EN errors':>10} {'DE errors':>10} {'DE injections missed':>21}")
err = {}
for name, s in scores.items():
    wrong = (s >= 0.5) != yte
    err[name] = (wrong[~de_te].mean(), wrong[de_te].mean())
    missed = np.sum(de_te & (yte == 1) & (s < 0.5))
    print(f"{name:24s} {wrong[~de_te].mean():>10.3f} {wrong[de_te].mean():>10.3f} {missed:>14} of {np.sum(de_te & (yte == 1)):>2}")
assert err["MiniLM + LR"][1] > err["MiniLM + LR"][0]

print("\n== 4. threshold for <= 5% false positives, chosen on out-of-fold TRAIN scores, applied to TEST ==")
print(f"{'head':24s} {'threshold':>9} {'test FPR':>9} {'test recall':>12}")
for name in heads:
    neg = np.sort(oof[name][ytr == 0])
    t = neg[int(np.ceil(0.95 * len(neg))) - 1]
    s = scores[name]
    print(f"{name:24s} {t:>9.3f} {np.mean(s[yte == 0] > t):>9.3f} {np.mean(s[yte == 1] > t):>12.3f}")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
train 546 (37.2% injections), test 116 (51.7% injections)
German (stop-word heuristic): train 27.5%, test 32.8%

== 1-2. test metrics (95% bootstrap intervals) ==
head                                    ROC-AUC          avg precision
TF-IDF word+char + LR       0.975 [0.951, 0.993]    0.980 [0.958, 0.994]
MiniLM + LR                 0.938 [0.897, 0.974]    0.949 [0.907, 0.979]
MiniLM + LightGBM           0.960 [0.926, 0.987]    0.963 [0.928, 0.989]

== 3. error analysis by language (test, threshold 0.5) ==
head                      EN errors  DE errors  DE injections missed
TF-IDF word+char + LR         0.090      0.211              8 of 23
MiniLM + LR                   0.141      0.184              7 of 23
MiniLM + LightGBM             0.103      0.184              7 of 23

== 4. threshold for <= 5% false positives, chosen on out-of-fold TRAIN scores, applied to TEST ==
head                     threshold  test FPR  test recall
TF-IDF word+char + LR        0.502     0.000        0.733
MiniLM + LR                  0.596     0.036        0.683
MiniLM + LightGBM            0.632     0.036        0.733

ALL ASSERTIONS PASSED
```

How to read it:

- **The interval columns** are as important as the point estimates: 116 test prompts can't rank three similar heads with confidence.
- **The language table** is the error analysis that tells you what to build next (§4).
- **The threshold table** is the honest way to set an operating point on small data: pick it out-of-fold on training data, then check it once on test. TF-IDF reaches recall 0.733 at test FPR 0.000; the MiniLM heads give recall 0.683–0.733 at FPR 0.036.

---

## 4. The Andrew Ng Lens: Error Analysis Drives the Next Sprint

### 4.1 The router's error spreadsheet

Run the router on validation, keep every error, and tag it. On CLINC the tags fall into a few buckets, and each points to a different fix:

| Tag | Example pattern (CLINC-style) | Fix |
|---|---|---|
| `sibling-intent` | "say fly in italian" → `change_language` vs `translate` | Clarify intent definitions; more contrastive examples; SetFit |
| `oos-accepted` | An off-topic request lands in its nearest intent | Distance gate (hybrid head); a production-prevalence threshold |
| `in-scope-escalated` | A valid but unusually phrased request falls below τ | More phrasing variety in training; check the threshold isn't too strict |
| `label-noise` | The "true" label itself is debatable | Fix the label (data-centric), don't train around it |
| `multi-intent` | "cancel my card and check my balance" | Split clauses or escalate by design |

Count the tags. The biggest bucket decides the sprint. This is the "single biggest predictor" discipline from Ng's evals letter (01.1 §4), applied to a 2 ms component.

### 4.2 Slice analysis is error analysis by metadata

The guardrail's language split is the general lesson: compute the metric per **slice** (language, channel, tenant, query length, time of day). An overall AUC of 0.94–0.98 hid an error rate on German prompts twice the English one. Slices with high error *and* high traffic share are where data collection pays most.

### 4.3 Bias, variance and the data budget for routers

- **Avoidable bias** shows up as errors even on training utterances, usually sibling intents. Representation is the bottleneck, so fine-tune the encoder (SetFit) or change the encoder.
- **Variance** shows up as a train/validation gap with a flattening learning curve (02.1 §1.8). More data helps slowly here; better labels may help more.
- **Data mismatch** shows up as a validation/production gap: prevalence of OOS (3% vs 18%), new phrasing, new languages. Collect validation data from production traffic and re-derive thresholds.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Router "2 ms" in the benchmark, 10+ ms in production | Eager PyTorch, one thread, Python overhead | Wrong runtime for the hot path | ONNX export (+ int8), pooling inside the graph | Latency SLO measured end to end in CI |
| F2 | Accuracy drops slightly after quantization, with occasional wild errors | int8 min cosine 0.78 vs fp32 | Dynamic per-tensor quantization of outlier-heavy activations | Pre-processing, per-channel or static quantization, exclude sensitive layers | Gate quantized encoders on the task metric and worst-case slices |
| F3 | Off-topic requests confidently routed to intents | High softmax confidence on OOS queries | Softmax measures relative, not absolute, fit (§1.4) | A distance gate (max cosine / Mahalanobis); an explicit OOS class | A labelled OOS set in every router eval |
| F4 | OOS recall collapses after launch | Threshold tuned on a low-OOS validation split | Prevalence mismatch (3.2% vs 18.2%) | Re-weight validation to production prevalence; re-derive τ | Sample validation sets from production traffic |
| F5 | Export to ONNX fails after a transformers upgrade | "got multiple values for argument" | Positional-argument changes in `forward` | Wrap with keyword arguments | Export test in CI on dependency bumps |
| F6 | Training/serving mismatch after export | ONNX returns token states, pooling done in app code | Pooling outside the graph | Export encoder + pooling + normalize as one graph | Golden-embedding parity test (cos ≥ 0.9999) |
| F7 | Guardrail misses non-English attacks | Error rate on DE ~2× EN | English-only encoder; under-represented language | Multilingual encoder, more data, language-routed heads | Slice metrics by language in the eval report |
| F8 | "Model A beats B" reversed on the next test set | Point estimates on ~100 examples | Sampling noise | Paired bootstrap CIs; larger eval sets | Never ship a decision without an interval |
| F9 | Guardrail threshold over-blocks in production | Threshold picked on a test set with 52% injections | Prevalence and selection bias | Out-of-fold thresholds; production-prevalence precision | Threshold provenance documented with the model |
| F10 | Embedding-based guardrail misses short injected clauses in long prompts | One vector per long prompt | Mean pooling dilutes a short span | Add lexical features; chunk long inputs and take the max over chunks | Test with injections at varying positions and lengths |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Design a 2 ms intent router for 150 intents. Prove the 2 ms."</b></summary>

**Initial Prompt.** CPU-only fleet, p50 ≤ 2 ms, out-of-scope traffic must not be routed.

**L5 Answer.** "Use a small BERT model and a classifier head. BERT-small is fast."

**Why L5 Fails in Production.** "Fast" isn't a number, and the runtime choice is where the 5× lives. Eager PyTorch measured 11.4 ms at one thread for the same model that runs in 2.2 ms under ONNX Runtime int8. And with no out-of-scope gate, every off-topic query is routed somewhere.

**L7 Principal Defense.** "MiniLM-L6 (22.7M parameters), exported with pooling and normalization inside the ONNX graph, then dynamic int8 quantization. Measured end to end, including the 0.09 ms tokenizer and a 16 µs NumPy LR head: p50 2.18 ms at one thread, 1.95 ms at four, p99 ~3 ms. The cost is −0.6 points of accuracy (0.955 → 0.948). The head is LR for intent selection, gated by max cosine to the intent centroids for out-of-scope traffic. The hybrid has the best 151-class accuracy (0.874), because softmax confidence is a weaker OOS detector (AUROC 0.945 vs 0.966). τ is set on validation re-weighted to production OOS prevalence, and everything below τ escalates to the LLM."

**Bar-Raiser Follow-ups.**
- *"Where does the remaining time go?"* The encoder: ~0.25 GFLOP for a 12-token query. The head is ~2,200× cheaper. Further cuts come from fewer layers (distillation), shorter max length, or a GPU/NPU if the fleet has one.
- *"What breaks the 2 ms?"* Long inputs (attention and MLP cost grow with tokens), cold starts, CPU contention from co-located workloads. Cap the max length and pin threads.

</details>

<details><summary><b>Q2 · "Why not just use the classifier's max softmax probability to detect out-of-scope queries?"</b></summary>

**Initial Prompt.** The team's router escalates when max probability < 0.5.

**L5 Answer.** "Low confidence means the model doesn't know, so it works."

**Why L5 Fails in Production.** Softmax confidence is normalized over the known classes. An OOS query that's slightly closer to one intent than to the others gets high confidence anyway. At 95% in-scope retention, it let 31.4% of OOS traffic through in our test.

**L7 Principal Defense.** "Measure OOS detection separately from intent accuracy. On CLINC, max cosine to class centroids gives AUROC 0.966 vs 0.945 for LR's max probability, with FPR@95%TPR of 0.173 vs 0.314. So the intent comes from LR and the route/escalate decision from distance: the hybrid. Folder 03 adds Mahalanobis distance with shrinkage as a stronger gate. An explicit 'oos' class trained on whatever OOS examples you have helps too (0.956), but you can't enumerate the open world, so keep the distance gate."

**Bar-Raiser Follow-ups.**
- *"Why does distance work better?"* It measures absolute closeness to the training distribution, which is exactly the OOS question. Softmax answers 'which known class is most likely', a relative question.

</details>

<details><summary><b>Q3 · "Our OOS recall was 60% in testing and 40% in production. Same model. Why?"</b></summary>

**Initial Prompt.** The threshold was tuned on validation data.

**L5 Answer.** "Production data is different. Retrain the model."

**Why L5 Fails in Production.** The model may be fine. The threshold was optimized for a different mix: optimizing 151-class accuracy on a 3%-OOS validation set rationally sacrifices OOS recall, and production has far more OOS traffic.

**L7 Principal Defense.** "Prevalence mismatch. CLINC itself shows it: 3.2% OOS in validation, 18.2% in test, and accuracy-optimal thresholds chosen on validation give OOS recall of only 0.40–0.63 on test. Fix the objective, not the model. Re-weight the validation set so OOS carries its production share (or collect a validation sample from production traffic), make the cost asymmetry explicit (a misrouted OOS query vs an escalated in-scope one, 01.3 §1.3), and re-derive τ. Then monitor the escalation rate and a labelled OOS sample weekly."

**Bar-Raiser Follow-ups.**
- *"How do you estimate production OOS prevalence?"* Label a random sample of traffic, refreshed periodically. EM on the router's scores is a cross-check (01.3 Q11).

</details>

<details><summary><b>Q4 · "Is int8 quantization of the encoder safe?"</b></summary>

**Initial Prompt.** The infra team wants int8 everywhere for cost.

**L5 Answer.** "Yes, int8 loses less than 1% accuracy."

**Why L5 Fails in Production.** Average accuracy hides worst cases. Our int8 encoder's mean cosine to fp32 was 0.961, but the minimum was 0.784, so a few inputs move a lot. Every downstream consumer (cache thresholds, guardrail scores) sees those shifts.

**L7 Principal Defense.** "Measured: −0.63 points of routing accuracy, OOS AUROC 0.966 → 0.962, 4× smaller, 2.3× faster. That's acceptable for this router. But: (1) gate on task metrics *per slice*, not on average cosine; (2) re-derive every threshold on int8 embeddings, since the geometry shifted; (3) never mix fp32 and int8 embeddings in one index, because they're different spaces for thresholds; (4) if the worst cases matter, try per-channel or static quantization, or exclude sensitive layers, and re-measure."

**Bar-Raiser Follow-ups.**
- *"Why is dynamic quantization 'dynamic'?"* Weights are quantized offline, activations per batch at runtime from their observed range, so no calibration data is needed. Static quantization fixes activation ranges from a calibration set, which is faster and sometimes more accurate, but needs representative data.

</details>

<details><summary><b>Q5 · "Embeddings or TF-IDF for a prompt-injection detector?"</b></summary>

**Initial Prompt.** The security team asks for a cheap first-stage injection filter.

**L5 Answer.** "Embeddings. They understand meaning, and TF-IDF is outdated."

**Why L5 Fails in Production.** Injection attempts are largely *lexical* ("ignore previous instructions" and its variants). Mean-pooled embeddings dilute a short injected clause inside a long prompt. Measured: TF-IDF word + char n-grams AUC 0.975 vs MiniLM + LR 0.938.

**L7 Principal Defense.** "Both, in one head. Char n-grams catch the surface forms, misspellings and other-language variants. Embeddings catch paraphrases with no shared vocabulary. Add a few regexes for known strings, and calibrate the combined score for a cost-derived threshold. Two caveats from the data: with 116 test prompts, the AUC intervals overlap, so collect more evaluation data before claiming a winner. And every head errs about twice as often on German prompts, so add a multilingual encoder or German training data. Long prompts get chunked, with the maximum chunk score taken, so an injection in paragraph 5 isn't averaged away."

**Bar-Raiser Follow-ups.**
- *"Adversaries will evade lexical features."* Yes, which is why the semantic features and an LLM-judge second stage exist. The cheap stage's job is high recall at low cost, and its misses feed the training set.

</details>

<details><summary><b>Q6 · "Your guardrail eval has 116 examples. How confident are you that model A beats model B?"</b></summary>

**Initial Prompt.** A head-to-head AUC comparison at 0.975 vs 0.960.

**L5 Answer.** "A is 1.5 points better, so ship A."

**Why L5 Fails in Production.** The 95% intervals are [0.951, 0.993] and [0.926, 0.987]. They overlap heavily, and a different 116 examples could reverse the ranking.

**L7 Principal Defense.** "Report intervals, and test the *difference* with a paired bootstrap: resample the same examples for both models and look at the distribution of AUC_A − AUC_B (Folder 06). If it includes 0, we don't know. Then either collect more labelled data (the cheapest fix), or decide on secondary criteria such as latency, explainability and slice performance. The German slice favours the embedding heads slightly. And pick thresholds out-of-fold on training data, never on the 116 test examples."

**Bar-Raiser Follow-ups.**
- *"How many examples would you want?"* Enough that the interval on the *difference* is narrower than the effect you care about. For a 1–2 point AUC effect, that's typically a few thousand labelled examples. Run a power calculation (Folder 06).

</details>

<details><summary><b>Q7 · "How do you roll out a new encoder version without breaking every head?"</b></summary>

**Initial Prompt.** A better embedding model is available. The router, OOS gate, guardrail and semantic cache all use the old one.

**L5 Answer.** "Swap the model and redeploy."

**Why L5 Fails in Production.** Every head and threshold was fitted to the old geometry (01.1 §1.7): router weights, OOS τ, guardrail calibration, cache τ. Swapping silently breaks all four.

**L7 Principal Defense.** "Treat the encoder version as a schema version. (1) Re-embed the training sets and retrain every head (seconds each). (2) Refit temperatures and re-derive every threshold on validation data with production prevalence. (3) Re-embed or dual-write the cache and retrieval indexes. (4) Shadow-deploy the new stack on live traffic and compare decisions, escalation rates and slice metrics. (5) Switch atomically, keeping the old stack for rollback. Thresholds and heads are artifacts versioned with the encoder."

**Bar-Raiser Follow-ups.**
- *"Can you avoid re-embedding the cache?"* Only with a validated bridge (Procrustes, 01.2 §1.6) and its own recall gate. Usually it's cheaper to let the cache refill.

</details>

<details><summary><b>Q8 · "When would you fine-tune the encoder instead of keeping it frozen?"</b></summary>

**Initial Prompt.** The router plateaus at 95.5% in-scope accuracy.

**L5 Answer.** "Fine-tune the whole BERT on the intents with cross-entropy."

**Why L5 Fails in Production.** Full fine-tuning per task breaks encoder sharing across heads, needs GPU training pipelines, and may not target the actual failure mode. That's unknown until you do error analysis.

**L7 Principal Defense.** "First, the error spreadsheet: if the remaining errors are sibling intents the encoder can't separate, or a language it doesn't cover, the representation is the bottleneck. Then SetFit-style contrastive fine-tuning on pairs built from the labelled data, which keeps the encoder-plus-linear-head architecture and the ONNX int8 path. If several heads need different fine-tunes, weigh one shared multi-task fine-tune against separate encoders, since each extra encoder is another ~2 ms and another version to manage. If the errors are label noise or prevalence, fine-tuning won't help: fix the data and the threshold."

**Bar-Raiser Follow-ups.**
- *"Expected gain?"* Unknown until measured on your error buckets. Run SetFit on a held-out split and compare per-bucket error counts, not just the overall accuracy.

</details>

---

## 7. Invariants Checklist

- [ ] The router's latency SLO is measured end to end (tokenize + encode + head + policy) on production hardware, at p50/p95/p99.
- [ ] The encoder is served from an exported graph that includes pooling and normalization, with a golden-embedding parity test.
- [ ] Quantized encoders are gated on task metrics per slice, and every threshold is re-derived on quantized embeddings.
- [ ] The router separates *intent selection* (LR) from the *route/escalate decision* (distance gate and/or calibrated confidence).
- [ ] Every router eval includes a labelled out-of-scope set. Thresholds are chosen on validation re-weighted to production prevalence.
- [ ] Guardrail heads combine lexical and semantic features, calibrated, with cost-derived thresholds, and long inputs are scored per chunk.
- [ ] Evals under a few thousand examples report bootstrap intervals. Head-to-head claims use paired tests.
- [ ] Metrics are reported per slice (language, channel, tenant, length).
- [ ] Heads, temperatures and thresholds are versioned with the encoder, and encoder upgrades go through shadow deployment.
- [ ] Escalated traffic is logged with its LLM decision for audited relabelling.

---

## 8. References

1. S. Larson et al., *An Evaluation Dataset for Intent Classification and Out-of-Scope Prediction* (CLINC150), EMNLP 2019. https://arxiv.org/abs/1909.02027
2. deepset, *prompt-injections* dataset card. https://huggingface.co/datasets/deepset/prompt-injections
3. D. Hendrycks, K. Gimpel, *A Baseline for Detecting Misclassified and Out-of-Distribution Examples in Neural Networks*, ICLR 2017. https://arxiv.org/abs/1610.02136
4. K. Lee et al., *A Simple Unified Framework for Detecting Out-of-Distribution Samples and Adversarial Attacks* (Mahalanobis), NeurIPS 2018. https://arxiv.org/abs/1807.03888
5. ONNX Runtime, *Quantize ONNX models* (dynamic vs static, QInt8, pre-processing). https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html
6. PyTorch, *torch.onnx export* documentation (torch.export-based exporter default since 2.9). https://docs.pytorch.org/docs/stable/onnx_export.html
7. L. Tunstall et al., *Efficient Few-Shot Learning Without Prompts* (SetFit), 2022. https://arxiv.org/abs/2209.11055
8. `sentence-transformers/all-MiniLM-L6-v2` model card. https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
9. Hugging Face `tokenizers` (Rust tokenizer library). https://github.com/huggingface/tokenizers
10. A. Ng, *Improve Agentic Performance with Evals and Error Analysis, Part 1*, The Batch, 2025-10-15. https://www.deeplearning.ai/the-batch/improve-agentic-performance-with-evals-and-error-analysis-part-1/
