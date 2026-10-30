# 07.1 · The Model Cascade Pattern: Combining Regex, BERT, XGBoost & LLMs for a 90% Cost Cut

> **Folder 07 · Hybrid ML + LLM Production Design Patterns**
> **Measured on:** NumPy 2.5.4 and scikit-learn 1.9.1, the real CLINC150 test traffic (4,500 in-scope + 1,000 out-of-scope queries) with MiniLM embeddings and an LR head (02.3), a **simulated** fallback LLM with stated accuracy assumptions, and a deterministic discrete-event simulation of the serving shell. Windows 11.
> **Design sources:** Viola & Jones (attentional cascades, 2001), Geifman & El-Yaniv (selective classification, 2017), Chen, Zaharia & Zou (FrugalGPT, 2023), Ong et al. (RouteLLM, 2024), Mozannar & Sontag (learning to defer, 2020), Hinton et al. (distillation, 2015), Nygard (*Release It!*: circuit breakers), Google SRE (cascading failures). Full list in §8.

---

## 0. Orientation: Pay for the LLM Only Where It Earns Its Price

A cascade sends each request through increasingly expensive stages and **stops at the first stage that's confident enough**. Regex rules cost microseconds, a frozen-encoder head costs ~2 ms of CPU (02.3), and an LLM call costs ~$68 per million requests and ~700 ms. Viola–Jones used this idea to make face detection real-time in 2001. FrugalGPT and RouteLLM apply it to LLMs. The engineering is in the **deferral rule** and the **thresholds**, and this file shows on real data how easy they are to get wrong:

- **The headline number depends on the tuning set's base rate.** Thresholds tuned on CLINC's validation split (3% out-of-scope) cut cost **82.9%** but lose **4.3 points** of accuracy on test traffic (18% out-of-scope). Re-weighting validation to the deployment share recovers most of it (−1.2 points, 74.9% cheaper). Adding a **+1-point safety margin** to the constraint reaches **parity with LLM-only (0.9602 vs 0.9600) at 72.5% lower cost**: $18.70 vs $68.00 per million requests.
- **The "90% cost cut" in this file's title is a traffic property, not a pattern property.** Cost ≈ (share reaching the LLM) × $68, so a 90% cut needs ≤ 10% of traffic to defer. Here 18% of traffic is out-of-scope and *should* defer, so 90% is only reachable by giving up accuracy (82.9% cheaper at −4.3 points). On head-heavy traffic (FAQ bots, where the top intents dominate and out-of-scope traffic is rare) 90% is realistic. Measure your deferral share before promising it.
- **The serving shell matters as much as the model.** In a simulated 2-minute LLM outage, a 1,500 ms deadline alone made **2,101** requests each wait the full 1.5 s (3,152 user-seconds). Adding a circuit breaker cut that to **16** requests (24 user-seconds), fast-failing the rest in ~2 ms. An exact-match cache on 30% repeat traffic cut cost from $24.14 to $17.25 per million.

### The backend-engineer bridge

| You already know | Cascade equivalent |
|---|---|
| L1 cache → L2 → database | **Rules → encoder head → LLM**: each tier slower and costlier, consulted on a miss |
| A fast path with a slow-path fallback | **Deferral**: the cheap stage answers or hands off |
| Cache-hit ratio drives the bill | **Deferral share** drives the bill: cost ≈ share × LLM price |
| Timeouts + circuit breakers + fallbacks (Hystrix, resilience4j) | The same, around the LLM stage |
| Load tests use production traffic mixes | **Tune thresholds at the deployment base rate** |
| SLO error budget | **The accuracy constraint** the thresholds must satisfy (with a margin) |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The cascade's expected cost and accuracy | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Deferral rules: confidence, margin, similarity gates | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Choosing thresholds as constrained optimization | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 The base-rate trap and safety margins | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Stage 0: rules with measured precision | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Latency of a cascade: mixture distributions | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 The reliability shell: deadlines, breakers, fallbacks, caches | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Routing between LLM tiers (FrugalGPT, RouteLLM) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.9 Distillation: training the cheap stage from the expensive one | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Learning-to-defer theory and consistent surrogate losses | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The cascade's expected cost and accuracy `[MUST-KNOW: Core AI Engineer Edge]`

Stages k = 0, 1, …, K. Each stage has a per-request cost c_k, and answers a request with probability a_k (given that the request reached it). Each stage answers with accuracy α_k on the requests it chooses to answer. Then:

```text
P(reach k)       = Π_{j<k} (1 − a_j)
share answered k = s_k = P(reach k) · a_k
E[cost]          = Σ_k P(reach k) · c_k            (every stage you pass through is paid for)
accuracy         = Σ_k s_k · α_k
```

Policy D in §3.1: rules answer 1.9% (α = 0.9717), the encoder answers 70.9% (α = 0.9687), and the LLM answers 27.2% (α = 0.9372):

```text
accuracy = 0.019·0.9717 + 0.709·0.9687 + 0.272·0.9372 = 0.9602       (LLM-only: 0.9600)
E[cost]  = 0.981·$0.0000002 (encoder) + 0.272·$0.000068 (LLM) = $0.0000187 → $18.70 per 1M   (LLM-only: $68.00)
```

Two structural facts fall out:

1. **The cheap stage can be more accurate than the LLM on what it answers** (0.9687 vs the LLM's 0.96 overall), because the gate **selects** the easy requests. That's selective classification (Geifman & El-Yaniv): trade coverage for accuracy. The LLM's accuracy on the deferred slice is *lower* (0.9372), because it receives the hard ones, mostly out-of-scope.
2. **Cost is almost exactly (deferral share) × (LLM price).** The local stages are ~300× cheaper per request, so they barely register. The only lever that matters for the bill is the deferral share, and the only constraint is accuracy.

> ⚠ **The fallback LLM is simulated** (97% accurate on in-scope, flags 90% of out-of-scope, independent of difficulty). A real LLM is also worse on hard cases, so measure its accuracy **on the deferred slice specifically**. That's the number that enters the formula above.

### 1.2 Deferral rules: confidence, margin, similarity gates `[MUST-KNOW: Core AI Engineer Edge]`

The cheap stage needs a score that says "I'm likely right". Common choices:

| Deferral signal | Defers when | Catches | Requires |
|---|---|---|---|
| Max probability | max_c p(c|x) < τ_conf | Ambiguous in-scope queries | **Calibrated** probabilities (temperature scaling, 02.1 §1.7) |
| Margin | p₍₁₎ − p₍₂₎ < τ_margin | Sibling-intent confusion | Calibration helps |
| Similarity / OOD gate | max_c cos(x, μ_c) < τ_cos | Out-of-scope queries that the head answers confidently anyway | Embedding geometry (01.1, 03.3) |
| Entropy | H(p) > τ_H | Spread-out uncertainty | Calibration |
| A learned deferral model | g(x) < τ | Anything correlated with errors | Labels of where the cheap stage fails |

**Why two gates.** A softmax head trained without OOS examples can be confidently wrong on out-of-scope inputs. That's 06.1 §3.2's finding: 586 of 798 router errors were OOS queries routed to an intent. A probability threshold alone doesn't catch them. A similarity gate on the embedding does, because OOS queries sit far from every class centroid. The listing uses both: answer locally only if calibrated confidence ≥ τ_conf **and** max centroid cosine ≥ τ_cos.

**Calibration is not optional.** The listing fits a temperature T on in-scope validation logits (minimizing NLL), so τ_conf means the same thing across retrains. Without it, a retrain that makes the head sharper silently changes the deferral share and the bill.

### 1.3 Choosing thresholds as constrained optimization `[MUST-KNOW: Core AI Engineer Edge]`

The business question is "the cheapest cascade that's as good as the LLM", which is a constrained optimization on a tuning set:

```text
minimize   E[cost](τ_conf, τ_cos)
subject to accuracy(τ_conf, τ_cos) ≥ accuracy(LLM-only) + margin
```

It's a satisficing constraint plus an optimizing metric, Ng's framing from 06.1 §4.1. The listing grid-searches 8 × 9 threshold pairs. With two parameters, a grid is fine. With more stages, sweep each gate's operating curve (accuracy vs coverage) and combine them. Three cautions:

- **Evaluate the constraint on held-out data** (validation) and **report on test**. The listing does both, and the gap between them is the subject of §1.4.
- **The constraint and the LLM baseline must be computed on the same items**, which is a paired comparison (06.4 §1.3).
- **The cost-optimal point is usually at the edge of the constraint**, so any optimism in the validation estimate turns directly into a constraint violation in production.

### 1.4 The base-rate trap and safety margins `[MUST-KNOW: Core AI Engineer Edge]`

This is the most important measured result in the folder. Same model, same grid, same objective. The only difference is how the tuning set represents production:

| Policy | Thresholds (conf/cos) | Test accuracy | $ per 1M | LLM share | Gap to LLM-only |
|---|---|---|---|---|---|
| LLM for everything | – | 0.9600 | 68.00 | 100% | – |
| A: tuned on raw validation (3% OOS) | 0.5 / 0.4 | 0.9171 | 11.63 | 16.8% | **−0.0429** |
| B: validation re-weighted to 18% OOS | 0.6 / 0.5 | 0.9482 | 17.08 | 24.8% | −0.0118 |
| C: B + 100 unused OOS training queries | 0.7 / 0.45 | 0.9478 | 15.69 | 22.8% | −0.0122 |
| D: C with a +1-point safety margin | 0.9 / 0.4 | **0.9602** | **18.70** | 27.2% | **+0.0002** |

**Why A fails.** CLINC's validation split has 100 OOS queries out of 3,100 (3%). Test traffic has 1,000 of 5,500 (18%). A threshold that lets through some OOS queries costs little accuracy on a 3%-OOS set and a lot on an 18%-OOS set. It's 06.1 §1.4's prevalence proof, applied to a deferral gate. **Fix (B):** weight the tuning set's OOS rows by (deployment share / tuning share). That needs an estimate of the deployment share from a labelled traffic sample, here 18%.

**Why B still misses by 1.2 points, and why more OOS data (C) didn't help.** The remaining gap comes from the *in-scope* side: the head is slightly less accurate on test queries than on validation queries, and the cost-optimal thresholds sit exactly on the constraint, so any optimism turns into a miss. **Fix (D):** require the tuning-set accuracy to beat the baseline by a margin. One point was enough here. In production, size the margin from the CI on the tuning-set estimate (06.1 §1.7) or from the val→test gap observed on past retrains.

The general rule: **a constraint that binds at the optimum needs a margin.** The optimizer will find every bit of optimism in your validation estimate and spend it.

### 1.5 Stage 0: rules with measured precision `[MUST-KNOW: Core AI Engineer Edge]`

Regex or keyword rules are the cheapest classifier there is, and the most dangerous to trust untested. The listing proposes 9 candidate patterns ("set … timer", "flip a coin", "weather", …) and **keeps a rule only if it's ≥ 99% precise on validation with ≥ 5 hits**. Seven pass. `weather` and `tell_joke` fail the bar. A plausible mechanism is the keyword collision 06.3 §1.2 found in the router's errors: "how do i ask about the weather in chinese" is a `translate` query.

On test, the kept rules answer 106 requests (1.9%) at **97.2% accuracy**, below the 99% bar they passed on validation: the same val→test optimism as §1.4, at small n (a 99% claim on a few dozen validation hits has a wide interval). Rules earn their place for **deterministic, auditable intents** (legal-required responses, account actions with exact phrases, safety blocks) more than for cost, since at 1.9% coverage the cost saving is negligible. Treat each rule as a classifier with a precision SLA, monitored like one.

### 1.6 Latency of a cascade: mixture distributions `[MUST-KNOW: Core AI Engineer Edge]`

End-to-end latency is a **mixture**: with probability 1 − s_LLM, a request takes ~2 ms; with probability s_LLM, it takes ~2 ms plus the LLM's latency. Quantiles of a mixture behave very differently from its mean:

```text
p50: if more than half the traffic is local, p50 ≈ the local path (2.3 ms measured, vs 700.9 ms LLM-only)
p99: P(latency > t) = s_LLM · P(LLM > t)  ⇒  the mixture's p99 is the LLM's (1 − 0.01/s_LLM) quantile
     at s_LLM = 0.35: the LLM's 97.1th percentile (z = 1.90). For a lognormal(ln 700, 0.5): 700·e^{0.5·1.90} ≈ 1,810 ms
     measured: 1,786 ms (LLM-only p99: 2,216 ms)
```

So **the cascade fixes p50 and the bill, but barely moves p99**: the tail is still the LLM's tail. If the product has a p99 SLO, you need a **deadline** (cap the LLM wait and serve a fallback) or a faster model on the deferral path. With a 1,500 ms deadline, p99 = 1,500 ms by construction, at a small extra cost ($24.14 vs $23.35 per million) for calls that were paid for but not used.

### 1.7 The reliability shell: deadlines, breakers, fallbacks, caches `[MUST-KNOW: Core AI Engineer Edge]`

The LLM is a remote dependency with its own latency distribution, rate limits and outages. The cascade gives you something most LLM apps lack: **a cheap local answer you can fall back to**. The shell around it (listing §3.2):

- **Deadline per request.** Bound the wait, then serve the best local answer or a safe fallback ("Let me connect you with an agent"). Set it from the product's latency SLO, not from the LLM's p99.
- **Circuit breaker.** After N consecutive failures (deadline misses count), stop calling for a cooldown, then let one trial request through (half-open): success closes the breaker, failure re-opens it. In the 2-minute outage simulation: **2,101 → 16** requests stuck waiting 1.5 s, with **2,292** fast-failed in ~2 ms. About 190 of those fast-fails happened in the first cooldown *after* the outage ended. That's the price of the cooldown granularity, so keep the cooldown short relative to typical outages.
- **Fallback quality.** Fast-failing is only good if the fallback is acceptable. For a router, the fallback can be the head's top intent with a confirmation question, which degrades gracefully rather than failing.
- **Cache in front.** Exact-match first (normalized text → answer): 27.5% hit rate when 30% of traffic repeats 500 popular queries, with cost down 29%. A semantic cache (03.1) raises hit rates and adds wrong-hit risk, so it needs its own precision measurement.
- **Rate limits and backpressure.** Cap concurrent LLM calls per tenant, and shed load to the local path before the provider's 429s do it for you (Google SRE's guidance on cascading failures applies directly).

### 1.8 Routing between LLM tiers (FrugalGPT, RouteLLM) `[GOOD-TO-KNOW: Architectural Literacy]`

The same pattern works *between* LLMs: a small model first, escalating to a larger one when a scorer says the answer is unreliable. **FrugalGPT** (Chen et al., 2023) learns a scorer that judges a cheap model's answer and escalates if needed, reporting large cost reductions at matched quality on their benchmarks. **RouteLLM** (Ong et al., 2024) trains routers on preference data to choose between a strong and a weak model *before* generation. The pricing spread makes this compelling: per the current Claude price list, Haiku 5.5 at $0.10/$0.50 per MTok vs Opus 5.5 at $4/$20, a **40× spread**. ⚠ Published savings are benchmark-specific. Measure on your traffic, with the deferred-slice accuracy of each tier.

A router *before* generation saves the cheap model's latency on escalated requests but has less information. A scorer *after* generation sees the answer but pays for both calls on escalations. With a fast cheap model, the post-hoc scorer usually wins on quality per dollar.

### 1.9 Distillation: training the cheap stage from the expensive one `[GOOD-TO-KNOW: Architectural Literacy]`

The cascade's cheap stage needs labels. The LLM stage produces them for free on deferred traffic. That's the **distillation flywheel**:

1. Log the LLM's answers on deferred requests, with a validated judge or human spot checks for quality (06.3).
2. Periodically retrain the cheap stage on those labels (soft labels if you have probabilities: Hinton et al., 2015).
3. The cheap stage covers more traffic and the deferral share falls, and so does the bill.

Guardrails: the student learns the teacher's errors too, so hold out a human-labelled test set. Deferred traffic is biased toward hard cases, so mix it with a random sample. And re-tune the thresholds (with the margin) after every retrain, because the deferral share is a function of the model. 07.3 covers the retraining loop and the promotion gate this needs.

### 1.10 Learning-to-defer theory and consistent surrogate losses `[SKIP: Academic/Research Only]`

Learning to defer (Mozannar & Sontag, 2020) trains the classifier and the deferral decision jointly, with surrogate losses that are consistent for the combined system's 0-1 loss. It's elegant, and it matters if you train the cheap stage specifically to defer well. In practice, a calibrated head plus an OOD gate plus thresholds tuned at the deployment base rate with a margin gets you most of the way.

---

## 2. Where It Beats an LLM in Production

The cascade *is* this KB's "beats an LLM" pattern in its purest form: the LLM is kept, but it only sees the requests where it adds value.

| Measured on CLINC test traffic | LLM only | Cascade (policy D) |
|---|---|---|
| Accuracy | 0.9600 | 0.9602 |
| Cost per 1M requests | $68.00 | $18.70 (−72.5%) |
| p50 latency (service simulation, 65% local) | 700.9 ms | 2.3 ms |
| Requests stuck 1.5 s during a 2-min outage | 2,101 (deadline only) | 16 (with breaker) |

Three reasons it wins, each structural:

1. **Selective prediction.** The cheap stage only answers what it's confident about, and on that slice it's *more* accurate than the LLM's average (0.9687 vs 0.96).
2. **The local stage is a fallback.** When the LLM is slow or down, a cascade degrades to the local answer. An LLM-only app degrades to an error page.
3. **The LLM's outputs become training data.** Distillation (§1.9) shrinks the deferral share over time. An LLM-only system's cost per request is flat forever.

**Where an LLM-only design is the honest choice:** low volume (the engineering isn't worth it under ~10k requests a day), no stable label space (open-ended generation), or a deferral share that would stay above ~70%, where the local stages cost latency on most requests and save little.

---

## 3. Production Code Blueprint

### 3.1 A rules → encoder → LLM cascade on real CLINC150 traffic

```python
"""cascade_router_clinc.py - a rules -> encoder -> LLM cascade on real CLINC150 traffic, with thresholds bought by cost.

Traffic: CLINC test set (4,500 in-scope + 1,000 out-of-scope). Stages:
  0. regex rules, kept only if >= 99% precise on VALIDATION
  1. MiniLM embedding + calibrated LR head + cosine OOS gate (02.3's hybrid): answer if confident and in scope
  2. LLM classifier for everything else. SIMULATED: it is right on 97% of in-scope queries and flags 90% of
     out-of-scope queries (assumptions - replace with your measured LLM accuracy); priced at Claude Haiku 5.5
     rates for a 630-token-in / 10-token-out call (01.1 s2)
Thresholds are chosen on VALIDATION (min cost s.t. accuracy >= the LLM-only accuracy), then reported on TEST.
CLINC's validation split is 3% out-of-scope; the test traffic is 18%. Tuning on the raw split vs tuning with the
OOS rows re-weighted to the deployment share (estimated from a labelled traffic sample) is the experiment.
"""
import json
import os
import re

import numpy as np
from sklearn.linear_model import LogisticRegression

DATA = os.environ["KB_DATA"]
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
meta = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))
labels = meta["labels"]
OOS = 150
LLM_COST, ENC_COST = 0.000068, 0.0000002                          # $/call: LLM (01.1); encoder CPU time (assumed)
LLM_ACC_IN, LLM_OOS_RECALL = 0.97, 0.90                            # ASSUMPTIONS about the fallback LLM


def split(name):
    X = np.vstack([Z[f"X_{name}"], Z[f"X_oos_{name}"]])
    y = np.r_[Z[f"y_{name}"], np.full(len(Z[f"X_oos_{name}"]), OOS)]
    return X, y, meta["texts"][name] + meta["texts"][f"oos_{name}"]


Xva, yva, Tva = split("val")
Xte, yte, Tte = split("test")
lab = {l: i for i, l in enumerate(labels)}
RULES = {                                                           # candidate high-precision patterns
    "timer": r"\b(set|start)\b.*\btimer\b", "alarm": r"\bset\b.*\balarm\b", "translate": r"\bhow (do|would) (i|you) say\b",
    "weather": r"\bweather\b", "flip_coin": r"\bflip a coin\b", "roll_dice": r"\broll\b.*\bdi(c)?e\b",
    "change_ai_name": r"\bchange your name\b", "tell_joke": r"\btell me a joke\b", "pto_request": r"\bpto request\b",
}
kept = {}
for intent, pat in RULES.items():
    hit = np.array([bool(re.search(pat, t)) for t in Tva])
    prec = np.mean(yva[hit] == lab[intent]) if hit.any() else 0
    if prec >= 0.99 and hit.sum() >= 5:
        kept[intent] = pat
print(f"stage 0: {len(kept)} of {len(RULES)} candidate rules pass the 99% validation-precision bar: {sorted(kept)}")


def rule_stage(texts):
    out = np.full(len(texts), -1)
    for intent, pat in kept.items():
        for i, t in enumerate(texts):
            if out[i] < 0 and re.search(pat, t):
                out[i] = lab[intent]
    return out


lr = LogisticRegression(C=10, max_iter=3000).fit(Z["X_train"], Z["y_train"])
logits_va = lr.decision_function(Xva[yva < OOS])
Ts = np.geomspace(0.2, 5, 100)
sm = lambda z: np.exp(z - z.max(1, keepdims=True)) / np.exp(z - z.max(1, keepdims=True)).sum(1, keepdims=True)
T = Ts[int(np.argmin([-np.mean(np.log(sm(logits_va / t)[np.arange(len(logits_va)), yva[yva < OOS]])) for t in Ts]))]
cent = np.stack([Z["X_train"][Z["y_train"] == c].mean(0) for c in range(150)])
cent /= np.linalg.norm(cent, axis=1, keepdims=True)
sim = np.random.default_rng(7)


def llm(y_true, r):
    """Simulated fallback LLM: right on in-scope w.p. LLM_ACC_IN; flags OOS w.p. LLM_OOS_RECALL."""
    out = np.where(r.random(len(y_true)) < LLM_ACC_IN, y_true, (y_true + 1) % 150)
    oos = y_true == OOS
    out[oos] = np.where(r.random(oos.sum()) < LLM_OOS_RECALL, OOS, r.integers(0, 150, oos.sum()))
    return out


def cascade(X, y, texts, tau_conf, tau_cos, seed, w=None):
    r = np.random.default_rng(seed)
    w = np.ones(len(y)) if w is None else w
    pred = np.full(len(y), -1)
    stage = np.full(len(y), 2)
    rule = rule_stage(texts)
    pred[rule >= 0], stage[rule >= 0] = rule[rule >= 0], 0
    p = sm(lr.decision_function(X) / T)
    ok = (rule < 0) & (p.max(1) >= tau_conf) & ((X @ cent.T).max(1) >= tau_cos)
    pred[ok], stage[ok] = p.argmax(1)[ok], 1
    rest = stage == 2
    pred[rest] = llm(y[rest], r)
    acc = np.average(pred == y, weights=w)
    cost = np.average(np.where(stage >= 1, ENC_COST, 0) + np.where(stage == 2, LLM_COST, 0), weights=w)
    return acc, cost, stage, pred


grid = [(tc, to) for tc in (0.3, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99)
        for to in (0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70)]
# the LR head never saw CLINC's 100 out-of-scope TRAIN queries, so they can join the threshold-tuning set
Xtu = np.vstack([Xva, Z["X_oos_train"]])
ytu = np.r_[yva, np.full(len(Z["X_oos_train"]), OOS)]
Ttu = Tva + meta["texts"]["oos_train"]


def tune(oos_share, X, y, texts, margin=0.0):
    """Cheapest thresholds whose tuning-set accuracy (OOS rows weighted to `oos_share`) beats LLM-only by `margin`."""
    is_oos = y == OOS
    w = np.where(is_oos, oos_share / is_oos.mean(), (1 - oos_share) / (1 - is_oos.mean()))
    llm_acc = np.average(llm(y, np.random.default_rng(1)) == y, weights=w)
    best = None
    for tc, to in grid:
        acc, cost, _, _ = cascade(X, y, texts, tc, to, seed=1, w=w)
        if acc >= llm_acc + margin and (best is None or cost < best[2]):
            best = (tc, to, cost, acc)
    assert best is not None, "no threshold pair matches LLM-only accuracy on the tuning set"
    return best, llm_acc


DEPLOY_OOS = 0.18                                                    # from a labelled sample of production traffic
acc_llm = np.mean(llm(yte, np.random.default_rng(2)) == yte)
print(f"\n== TEST traffic ({len(yte):,} requests, {np.mean(yte == OOS):.1%} out-of-scope) ==")
print(f"{'policy':44s} {'thresholds':>11} {'accuracy':>8} {'$ per 1M':>9} {'rules':>6} {'encoder':>8} {'LLM':>6}")
print(f"{'LLM for everything':44s} {'-':>11} {acc_llm:>8.4f} {LLM_COST * 1e6:>9.2f} {0:>6.1%} {0:>8.1%} {1:>6.1%}")
res = {}
for key, name, share, data, margin in (
        ("raw", "A: tuned on raw validation (3% OOS)", np.mean(yva == OOS), (Xva, yva, Tva), 0.0),
        ("weighted", f"B: validation re-weighted to {DEPLOY_OOS:.0%} OOS", DEPLOY_OOS, (Xva, yva, Tva), 0.0),
        ("weighted+", "C: B + 100 unused OOS train queries", DEPLOY_OOS, (Xtu, ytu, Ttu), 0.0),
        ("margin", "D: C with a +1-point safety margin", DEPLOY_OOS, (Xtu, ytu, Ttu), 0.01)):
    best, _ = tune(share, *data, margin=margin)
    acc_c, cost_c, stage, pred_c = cascade(Xte, yte, Tte, best[0], best[1], seed=2)
    res[key] = (acc_c, cost_c, stage, pred_c)
    print(f"{name:44s} {f'{best[0]}/{best[1]}':>11} {acc_c:>8.4f} {cost_c * 1e6:>9.2f} {np.mean(stage == 0):>6.1%} "
          f"{np.mean(stage == 1):>8.1%} {np.mean(stage == 2):>6.1%}")
acc_c, cost_c, stage, pred_c = res["margin"]
print(f"policy D: cost reduction vs LLM-only {1 - cost_c / LLM_COST:.1%}; accuracy change {acc_c - acc_llm:+.4f}")
for name, k in (("rules", 0), ("encoder", 1), ("LLM (simulated)", 2)):
    m = stage == k
    print(f"  accuracy on what the {name} stage answered: {np.mean(pred_c[m] == yte[m]):.4f} ({m.sum():,} requests, "
          f"{np.mean(yte[m] == OOS):.1%} of them out-of-scope)")
print("accuracy gap to LLM-only on test: " + ", ".join(f"{k} {res[k][0] - acc_llm:+.4f}" for k in res))
assert res["raw"][0] < acc_llm - 0.02 and res["weighted"][0] > res["raw"][0]
assert 1 - cost_c / LLM_COST > 0.5 and acc_c >= acc_llm - 0.005
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
stage 0: 7 of 9 candidate rules pass the 99% validation-precision bar: ['alarm', 'change_ai_name', 'flip_coin', 'pto_request', 'roll_dice', 'timer', 'translate']

== TEST traffic (5,500 requests, 18.2% out-of-scope) ==
policy                                        thresholds accuracy  $ per 1M  rules  encoder    LLM
LLM for everything                                     -   0.9600     68.00   0.0%     0.0% 100.0%
A: tuned on raw validation (3% OOS)              0.5/0.4   0.9171     11.63   1.9%    81.3%  16.8%
B: validation re-weighted to 18% OOS             0.6/0.5   0.9482     17.08   1.9%    73.2%  24.8%
C: B + 100 unused OOS train queries             0.7/0.45   0.9478     15.69   1.9%    75.3%  22.8%
D: C with a +1-point safety margin               0.9/0.4   0.9602     18.70   1.9%    70.9%  27.2%
policy D: cost reduction vs LLM-only 72.5%; accuracy change +0.0002
  accuracy on what the rules stage answered: 0.9717 (106 requests, 0.0% of them out-of-scope)
  accuracy on what the encoder stage answered: 0.9687 (3,897 requests, 2.2% of them out-of-scope)
  accuracy on what the LLM (simulated) stage answered: 0.9372 (1,497 requests, 61.2% of them out-of-scope)
accuracy gap to LLM-only on test: raw -0.0429, weighted -0.0118, weighted+ -0.0122, margin +0.0002

ALL ASSERTIONS PASSED
```

**Reading the output.** Policy A is what most teams ship: thresholds tuned on whatever validation split exists. It looks great on cost and silently loses 4.3 points. Policies B → D are the fix in order of importance: base-rate re-weighting first, then a margin on the binding constraint. Note how the optimizer *moves* between policies: D defers on confidence (0.9) instead of similarity (0.4), because once the constraint is tight, the cheapest way to meet it changes.

### 3.2 The serving shell: deadlines, a circuit breaker, a cache, metrics

Stage latencies here are **assumptions** shaped like this KB's measurements: rules ~0.05 ms, encoder ~2 ms (02.3), LLM lognormal around 700 ms. The simulated clock makes the run deterministic.

```python
"""cascade_service_blueprint.py - the serving shell around a model cascade: budgets, timeouts, breaker, cache, metrics.

Deterministic discrete-event simulation (a simulated clock, no sleeps). Stage latencies are ASSUMPTIONS chosen
to resemble this KB's measurements: rules ~0.05 ms, encoder ~2 ms (02.3), LLM lognormal around ~700 ms.
  1. p50 / p99 latency and cost: LLM-only vs cascade (65% handled before the LLM).
  2. A per-request deadline with a safe fallback answer: bounds p99 when the LLM is slow.
  3. A circuit breaker during a 2-minute LLM outage: fail fast instead of piling up timeouts.
  4. An exact-match cache in front of everything.
"""
import math
from collections import Counter

import numpy as np

rng = np.random.default_rng(211)


class Breaker:
    """Opens after `threshold` consecutive failures. After `cooldown_ms` the next call is a trial (half-open):
    success closes the breaker, failure re-opens it at once."""

    def __init__(self, threshold=5, cooldown_ms=10_000):
        self.threshold, self.cooldown, self.fails, self.open_until = threshold, cooldown_ms, 0, -math.inf
        self.half_open = False

    def allow(self, now):
        return now >= self.open_until

    def record(self, ok, now):
        if ok:
            self.fails, self.half_open = 0, False
            return
        self.fails += 1
        if self.half_open or self.fails >= self.threshold:
            self.open_until, self.fails, self.half_open = now + self.cooldown, 0, True


class Cascade:
    def __init__(self, local_share, deadline_ms=None, breaker=None, cache=False):
        self.local_share, self.deadline, self.breaker = local_share, deadline_ms, breaker
        self.cache = {} if cache else None
        self.metrics = Counter()

    def handle(self, req_key, now, llm_up=True):
        if self.cache is not None and req_key in self.cache:
            self.metrics["cache_hit"] += 1
            return 0.02, 0.0
        lat = 0.0
        if self.local_share > 0:                                     # LLM-only skips the local stages entirely
            lat = 0.05                                               # rules
            if rng.random() < 0.10:
                self.metrics["rules"] += 1
                return self._store(req_key, lat, 0.0)
            lat += max(0.5, rng.normal(2.0, 0.4))                     # encoder + head + gate
            if rng.random() < (self.local_share - 0.10) / 0.90:
                self.metrics["encoder"] += 1
                return self._store(req_key, lat, 0.0)
        if self.breaker and not self.breaker.allow(now):
            self.metrics["breaker_fast_fail"] += 1                   # safe fallback: "let me connect you" etc.
            return lat + 0.1, 0.0
        llm_lat = rng.lognormal(math.log(700), 0.5) if llm_up else 30_000.0   # an outage looks like a hang
        if self.deadline and lat + llm_lat > self.deadline:
            self.metrics["deadline_fallback"] += 1
            self.metrics["deadline_fallback_in_outage"] += not llm_up
            if self.breaker:
                self.breaker.record(False, now)
            return self.deadline, 0.000068                           # paid for the call, served the fallback
        if self.breaker:
            self.breaker.record(llm_up, now)
        self.metrics["llm"] += 1
        return self._store(req_key, lat + llm_lat, 0.000068)

    def _store(self, key, lat, cost):
        if self.cache is not None:
            self.cache[key] = True
        return lat, cost


def simulate(c, n=20_000, outage=None, repeat_share=0.0):
    lats, cost = [], 0.0
    for i in range(n):
        now = i * 20.0                                               # one request every 20 ms
        key = int(rng.integers(0, 500)) if rng.random() < repeat_share else 10_000 + i
        up = not (outage and outage[0] <= now < outage[1])
        lat, cst = c.handle(key, now, up)
        lats.append(lat)
        cost += cst
    lats = np.array(lats)
    return np.percentile(lats, 50), np.percentile(lats, 99), cost / n * 1e6, c.metrics


print("== 1-2. latency and cost per 1M requests (no outage) ==")
print(f"{'configuration':40s} {'p50 ms':>8} {'p99 ms':>9} {'$ / 1M':>8}")
rows = {}
for name, c in (("LLM for everything", Cascade(local_share=0.0)), ("cascade, 65% local", Cascade(local_share=0.65)),
                ("cascade + 1,500 ms deadline", Cascade(local_share=0.65, deadline_ms=1500))):
    p50, p99, cst, m = simulate(c)
    rows[name] = (p50, p99, cst)
    print(f"{name:40s} {p50:>8.1f} {p99:>9.1f} {cst:>8.2f}")
assert rows["cascade, 65% local"][0] < 10 and rows["cascade + 1,500 ms deadline"][1] <= 1500.0001

print("\n== 3. a 2-minute LLM outage in the middle of 10 minutes of traffic ==")
waits = {}
for name, c in (("deadline only", Cascade(0.65, deadline_ms=1500)),
                ("deadline + circuit breaker", Cascade(0.65, deadline_ms=1500, breaker=Breaker()))):
    p50, p99, cst, m = simulate(c, n=30_000, outage=(240_000, 360_000))
    waits[name] = m["deadline_fallback_in_outage"]
    print(f"{name:28s} during the outage: {waits[name]:5d} requests waited the full 1,500 ms "
          f"({waits[name] * 1.5:,.0f} user-seconds), {m['breaker_fast_fail']:5d} fast-failed in ~2 ms; "
          f"slow-call fallbacks outside it {m['deadline_fallback'] - waits[name]}")
print("the deadline bounds each request; the breaker stops paying that bound thousands of times")
assert waits["deadline + circuit breaker"] < 0.05 * waits["deadline only"]

print("\n== 4. exact-match cache when 30% of requests repeat one of 500 popular queries ==")
p50, p99, cst, m = simulate(Cascade(0.65, deadline_ms=1500, cache=True), repeat_share=0.3)
print(f"cache hits {m['cache_hit'] / 20_000:.1%}; LLM calls {m['llm'] / 20_000:.1%}; $ / 1M {cst:.2f} "
      f"(vs {rows['cascade + 1,500 ms deadline'][2]:.2f} without the cache)")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1-2. latency and cost per 1M requests (no outage) ==
configuration                              p50 ms    p99 ms   $ / 1M
LLM for everything                          700.9    2215.8    68.00
cascade, 65% local                            2.3    1786.4    23.35
cascade + 1,500 ms deadline                   2.3    1500.0    24.14

== 3. a 2-minute LLM outage in the middle of 10 minutes of traffic ==
deadline only                during the outage:  2101 requests waited the full 1,500 ms (3,152 user-seconds),     0 fast-failed in ~2 ms; slow-call fallbacks outside it 549
deadline + circuit breaker   during the outage:    16 requests waited the full 1,500 ms (24 user-seconds),  2292 fast-failed in ~2 ms; slow-call fallbacks outside it 525
the deadline bounds each request; the breaker stops paying that bound thousands of times

== 4. exact-match cache when 30% of requests repeat one of 500 popular queries ==
cache hits 27.5%; LLM calls 23.9%; $ / 1M 17.25 (vs 24.14 without the cache)

ALL ASSERTIONS PASSED
```

### 3.3 The cascade config a reviewer should see

```yaml
cascade: support-router
version: 2026-10-30.1
stages:
  - name: rules
    patterns_file: rules/v14.yaml           # each rule: precision on validation >= 0.99 with >= 5 hits, re-checked weekly
  - name: encoder_head
    encoder: all-MiniLM-L6-v2@onnx-int8       # 02.3: ~2 ms p50 on CPU
    head: lr-c10@2026-10-28  temperature: 1.31
    defer_if: { max_prob_lt: 0.90, max_centroid_cos_lt: 0.40 }
  - name: llm
    model: claude-haiku-5-5   max_tokens: 10   deadline_ms: 1500
    breaker: { consecutive_failures: 5, cooldown_ms: 10000, half_open_trials: 1 }
    fallback: head_top1_with_confirmation
tuning:
  objective: min_cost
  constraint: accuracy >= llm_only_accuracy + 0.01     # margin: binding constraint (07.1 §1.4)
  base_rate_oos: 0.18                                   # from the 2026-10-21 labelled traffic sample
  tuning_set: val+oos_train   test_set: test           # thresholds never tuned on test
monitoring: [deferral_share, accuracy_by_stage_sampled, breaker_state, cache_hit_rate, cost_per_1k]
```

Values are illustrative. The fields that prevent this file's failure modes are `base_rate_oos`, the margin in `constraint`, the `temperature`, and `deferral_share` in monitoring. The bill is a function of the deferral share, so a jump in it is a cost incident *and* a drift signal (07.3).

---

## 4. The Andrew Ng Lens: Build the Cheap Thing, Measure, Then Spend

### 4.1 Evaluation-driven design of the cascade

Ng's evaluation-driven loop (06.3 §4.1) gives the build order: (1) measure the LLM-only baseline on a representative eval set, which is your accuracy constraint. (2) Build the cheapest stage (rules, a head on frozen embeddings) and measure its accuracy-coverage curve. (3) Tune thresholds against the constraint, at the deployment base rate, with a margin. (4) Error-analyze what the cheap stage gets wrong *while confident*: those are the requests that cost you accuracy without costing money, and the most important bucket to fix.

### 4.2 Bias and variance of the cheap stage

If the head's errors are many even at high confidence, that's **bias**: it can't represent the distinction, so it needs a better encoder, more features, or a GBDT on richer inputs (02.2). If it's good on validation but worse on test (the 1.2-point gap in §1.4), that's **variance plus distribution mismatch**: you need more and more representative tuning data, and a margin until you have it.

### 4.3 Data-centric improvement of the deferral share

The cheapest way to cut the bill further is usually not a better model. It's **more labelled examples of what currently defers**. That's exactly what the LLM stage produces (distillation, §1.9). Ng's data-centric framing applies directly: improve the data for the cheap model, and the system improves without touching the architecture.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Cheaper than planned, accuracy quietly down | Deferral share low, OOS answered locally | Thresholds tuned at the wrong base rate (−4.3 points here) | Re-weight the tuning set to the deployment share | `base_rate` field in the cascade config, refreshed from traffic samples |
| F2 | Constraint met on validation, missed in production | Gap ≈ size of the val→test optimism | Binding constraint, no margin | Margin from the CI or past gaps | Margin is a required config field |
| F3 | Bill jumps after a retrain | Deferral share changed | New model's confidence scale differs | Calibrate (temperature) and re-tune thresholds per model version | Threshold re-tune in the retraining pipeline |
| F4 | Confidently wrong answers on off-topic queries | High-confidence errors, all OOS | Probability-only gate | Add a similarity/OOD gate (02.3, 03.3) | OOS slice in the eval set |
| F5 | p99 unchanged after the cascade launch | p50 great, p99 ~ LLM tail | Mixture quantiles | Deadline + fallback, faster model on the deferral path | p99 SLO tracked per stage |
| F6 | Outage turns into user-visible hangs | Thousands of deadline waits | No circuit breaker | Breaker with half-open trials | Chaos test: kill the LLM endpoint in staging |
| F7 | A rule starts misfiring | Rule precision drops | Traffic changed; the rule was never re-measured | Re-validate rule precision on fresh samples | Weekly rule-precision job |
| F8 | Cache serves stale or wrong answers | Complaints about outdated responses | No TTL or invalidation; semantic-cache wrong hits | TTL per answer type; precision-measured semantic cache | Cache precision in the eval suite |
| F9 | Cascade "saves" money but the LLM slice is unmeasured | Overall accuracy looks fine | LLM accuracy on the *deferred* slice never measured | Sample and label deferred requests | Per-stage accuracy on sampled traffic in the dashboard |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Design a system that cuts our intent-classification LLM bill by 90%."</b></summary>

**Initial Prompt.** 20M requests a month go to an LLM classifier.

**L5 Answer.** "Put a BERT classifier in front and send low-confidence requests to the LLM."

**Why L5 Fails in Production.** It's the right shape with none of the numbers: no deferral-share estimate, no accuracy constraint, no calibration, no OOD gate, no base-rate check. And 90% may not be reachable.

**L7 Principal Defense.** "Cost ≈ deferral share × LLM price, so a 90% cut means ≤ 10% of traffic reaches the LLM. First I'd measure how much traffic *should* defer: on CLINC-like traffic, 18% is out-of-scope, so 90% at parity is impossible there. We measured 72.5% at parity and 82.9% at −4.3 points. The design: rules for auditable intents, a calibrated head on frozen embeddings with a confidence *and* a similarity gate, and the LLM for the rest. Thresholds come from min cost subject to accuracy ≥ LLM-only + margin, on a tuning set re-weighted to the deployment base rate. Then a deadline and circuit breaker around the LLM, a cache in front, and distillation from LLM labels to push the deferral share down over time. I'd commit to the number after measuring the deferral share on a week of traffic."

**Bar-Raiser Follow-ups.**
- *"What's the cost of the local stage?"* ~2 ms of CPU, ~$0.20 per million in this KB's estimate: noise next to $68.
- *"How does it fail?"* Silently: thresholds drift with the base rate or a retrain. So monitor the deferral share and sampled per-stage accuracy.

</details>

<details><summary><b>Q2 · "Our cascade met the accuracy bar offline but users see more wrong answers. Why?"</b></summary>

**Initial Prompt.** Offline: matched LLM accuracy at 80% lower cost. Production: complaints up.

**L5 Answer.** "The offline eval set was too small."

**Why L5 Fails in Production.** Possibly, but the most common specific cause is that the tuning set's class mix differs from production, especially for out-of-scope traffic.

**L7 Principal Defense.** "I'd check the base rate first. In our CLINC run, thresholds tuned on a 3%-OOS validation split lost 4.3 points on 18%-OOS traffic. The gate let through OOS queries that cost little on validation and a lot in production. Estimate the production OOS share from a labelled sample, re-weight the tuning set, re-tune: that recovered 3.1 of the 4.3 points. Then add a margin, because the cost-optimal point sits on the constraint: +1 point brought us to parity. Finally, sample and label requests answered *locally* in production, since that's where accuracy is lost silently."

**Bar-Raiser Follow-ups.**
- *"Could it be the LLM stage?"* Check its accuracy on the deferred slice. It gets the hard cases, so it was 0.937 here vs 0.96 overall.
- *"How do you catch this before users do?"* Shadow-mode the cascade against the LLM-only path on live traffic for a week.

</details>

<details><summary><b>Q3 · "Why do you need both a confidence threshold and a similarity gate?"</b></summary>

**Initial Prompt.** The cheap stage is a softmax head over 150 intents.

**L5 Answer.** "Confidence is enough; low confidence means uncertain."

**Why L5 Fails in Production.** A softmax head trained without out-of-scope data is often *confidently* wrong on OOS inputs: probability mass has to go somewhere. In 06.1, 586 of 798 router errors were OOS queries routed to an intent.

**L7 Principal Defense.** "They catch different errors. Confidence (calibrated, after temperature scaling) catches ambiguous in-scope queries between sibling intents. The similarity gate (max cosine to class centroids, or a Mahalanobis/energy score, 03.3) catches inputs far from *all* classes, which the head may still assign high probability. In the listing, the cost-optimal policy used both. Which one binds shifts with the constraint: D tightened confidence (0.9) and relaxed similarity (0.4)."

**Bar-Raiser Follow-ups.**
- *"Why calibrate?"* So a threshold of 0.9 means the same thing after every retrain, which keeps the deferral share and the bill stable.
- *"A learned deferral model?"* Yes, once you have labels of where the cheap stage fails. Train it on those, not on generic confidence.

</details>

<details><summary><b>Q4 · "The cascade fixed our p50 but not our p99. Why, and what do you do?"</b></summary>

**Initial Prompt.** p50 fell from ~700 ms to ~2 ms; p99 barely moved.

**L5 Answer.** "Add more replicas of the LLM service."

**Why L5 Fails in Production.** The p99 is the LLM provider's tail, which replicas on your side don't change.

**L7 Principal Defense.** "Latency is a mixture. The mixture's p99 is the LLM's (1 − 0.01/s) quantile, where s is the deferral share. At s = 0.35 that's the LLM's 97.1th percentile: ~1,800 ms in our simulation, vs 2,216 ms LLM-only. To fix the tail: (1) a deadline with a fallback. p99 becomes the deadline (1,500 ms), at a small cost for abandoned calls. (2) Reduce s, which pushes the mixture quantile further into the LLM tail but affects fewer users. (3) A faster model tier for the deferral path. (4) Hedged requests if the provider's tail is independent across calls, at extra cost. Choose by the SLO: if p99 must be under 1 s, only the deadline or a faster tier gets there."

**Bar-Raiser Follow-ups.**
- *"What does the deadline cost?"* You pay for calls you abandon: $24.14 vs $23.35 per million here.
- *"Streaming?"* It improves time-to-first-token, not total latency, and only helps if the UI can use partial output.

</details>

<details><summary><b>Q5 · "The LLM provider has a 2-minute outage. What happens to your system?"</b></summary>

**Initial Prompt.** A resilience review.

**L5 Answer.** "Requests time out and we return an error; we have retries."

**Why L5 Fails in Production.** Retries during an outage multiply load and latency. Without a breaker, every deferred request waits the full timeout.

**L7 Principal Defense.** "In the simulation: deadline-only meant 2,101 requests each waited 1.5 s during the outage. With a circuit breaker (open after 5 consecutive failures, 10 s cooldown, one half-open trial), only 16 waited, and 2,292 were fast-failed in ~2 ms to a fallback. ~190 of those were in the cooldown after recovery, which is the breaker's cost. The fallback matters most: for a router, it's the head's top intent with a confirmation, so users still get a reasonable answer. Locally answered traffic (65–73%) is unaffected. Retries: at most one, with jitter, and never while the breaker is open."

**Bar-Raiser Follow-ups.**
- *"Multi-provider failover?"* Yes, if prompts are portable and the second provider's accuracy is measured on the deferred slice. Otherwise failover silently changes quality.
- *"How do you test it?"* Fault injection in staging: kill or slow the LLM endpoint and check the breaker state, fallback rate and p99.

</details>

<details><summary><b>Q6 · "Should we route between a small and a large LLM instead of using a classifier?"</b></summary>

**Initial Prompt.** A generative task (summaries) where there's no label space for a head.

**L5 Answer.** "Always use the large model for quality."

**Why L5 Fails in Production.** It ignores a 40× price spread (Haiku 5.5 vs Opus 5.5 list prices) and the fact that many requests are easy.

**L7 Principal Defense.** "Same cascade logic, LLM tiers as stages. Two designs: a router *before* generation (RouteLLM-style, trained on preference data: cheap, but it decides blind), or a scorer *after* the small model answers (FrugalGPT-style: sees the answer, pays twice on escalations). I'd start with the post-hoc scorer: a validated judge or a small classifier on the small model's output, a threshold tuned for 'large-model-equivalent quality' on a pairwise-judged eval set (06.3), and a margin. Then measure the escalation share: cost ≈ small price + escalation share × large price."

**Bar-Raiser Follow-ups.**
- *"What's the scorer?"* Ideally a cheap classifier trained on judged pairs (did the large model do better?), which is the same distillation idea.
- *"Risk?"* Quality regressions concentrated in a slice. Monitor judged quality by slice.

</details>

<details><summary><b>Q7 · "How do you keep the cascade cheap as traffic changes?"</b></summary>

**Initial Prompt.** Six months in, the deferral share crept from 27% to 41%.

**L5 Answer.** "Lower the thresholds so fewer requests go to the LLM."

**Why L5 Fails in Production.** Lowering thresholds without re-checking the constraint trades accuracy for cost, exactly the policy-A failure.

**L7 Principal Defense.** "A rising deferral share is a drift signal. New intents, new phrasing, or a changed OOS share are making the cheap stage less confident. First diagnose: cluster the newly deferred requests (03.1). Is it a new topic (needs labels and maybe a new intent) or the same intents phrased differently (needs more training data)? The LLM stage has been labelling exactly these requests, so retrain the head on validated LLM labels plus a human-checked sample, re-calibrate, and re-tune thresholds with the margin. Promote only through a gate (07.3). The deferral share should fall back without touching the accuracy constraint."

**Bar-Raiser Follow-ups.**
- *"Automate it?"* Yes, with a promotion gate on a frozen golden set. 07.3 shows an ungated drift-triggered retrain deploying a broken model and staying broken.
- *"Alert threshold?"* On the deferral share relative to its trailing baseline, with a cost alert attached.

</details>

<details><summary><b>Q8 · "Are regex rules worth it in a cascade?"</b></summary>

**Initial Prompt.** A team wants to delete the rules stage as tech debt.

**L5 Answer.** "Yes, rules are brittle; the model handles everything."

**Why L5 Fails in Production.** It treats rules as a cost optimization, when their real value is determinism and auditability for a small set of intents.

**L7 Principal Defense.** "On cost, rules barely matter: 1.9% coverage here. Their value is elsewhere: legally required responses, account actions with exact phrasing, and safety blocks that must never depend on a model's confidence. Keep a rule only with measured precision. The listing kept 7 of 9 candidates at ≥ 99% validation precision, and those 7 scored 97.2% on test, so the bar itself needs a margin and a weekly re-check. I'd delete rules that exist only for cost, keep the auditable ones with precision monitoring, and version them like code."

**Bar-Raiser Follow-ups.**
- *"Rules after the model, as a guardrail?"* Yes, for outputs: a deterministic check that the action matches policy, independent of the model.

</details>

<details><summary><b>Q9 · "How would you distill the LLM into the cheap stage safely?"</b></summary>

**Initial Prompt.** 2M LLM-labelled requests have accumulated.

**L5 Answer.** "Train the head on all of them."

**Why L5 Fails in Production.** The LLM's labels contain its errors. Deferred traffic is biased toward hard cases. And the cascade's thresholds become wrong for the new model.

**L7 Principal Defense.** "Four controls. (1) **Label quality:** estimate the LLM's error on the deferred slice with human labels, and filter or down-weight low-confidence LLM labels. (2) **Distribution:** mix deferred requests with a random traffic sample, so the head doesn't overfit to hard cases. (3) **Evaluation:** a human-labelled test set the LLM never labelled, with per-intent floors (06.1). (4) **Deployment:** re-calibrate, re-tune thresholds at the current base rate with a margin, and promote through a gate (07.3). The KPI is the deferral share at fixed accuracy, tracked release over release."

**Bar-Raiser Follow-ups.**
- *"Soft labels?"* If the LLM exposes probabilities, yes: they carry more information. Otherwise use self-consistency votes as soft labels on a sample.

</details>

---

## 7. Invariants Checklist

- [ ] The LLM-only baseline is measured on the same eval items as the cascade (paired), and it defines the accuracy constraint.
- [ ] Thresholds come from min cost subject to accuracy ≥ baseline + **margin**, on a tuning set **re-weighted to the deployment base rate**. They are never tuned on test.
- [ ] The cheap stage is calibrated (temperature) and has both a confidence and a similarity/OOD gate.
- [ ] Every rule has measured precision on fresh data, re-checked on a schedule.
- [ ] The LLM stage has a deadline, a circuit breaker with half-open trials, a fallback with measured quality, and capped retries.
- [ ] Per-stage accuracy on **sampled production traffic** is monitored, including the LLM's deferred slice.
- [ ] The deferral share is monitored as both a cost metric and a drift signal.
- [ ] Every retrain re-calibrates and re-tunes thresholds, and is promoted only through a gate (07.3).
- [ ] Cost claims state the deferral share and the traffic mix they were measured on.

---

## 8. References

1. P. Viola, M. Jones, *Rapid Object Detection using a Boosted Cascade of Simple Features*, CVPR 2001. https://doi.org/10.1109/CVPR.2001.990517
2. Y. Geifman, R. El-Yaniv, *Selective Classification for Deep Neural Networks*, NeurIPS 2017. https://arxiv.org/abs/1705.08500
3. L. Chen, M. Zaharia, J. Zou, *FrugalGPT: How to Use Large Language Models While Reducing Cost and Improving Performance*, 2023. https://arxiv.org/abs/2305.05176
4. I. Ong et al., *RouteLLM: Learning to Route LLMs with Preference Data*, 2024. https://arxiv.org/abs/2406.18665
5. H. Mozannar, D. Sontag, *Consistent Estimators for Learning to Defer to an Expert*, ICML 2020. https://arxiv.org/abs/2006.01862
6. G. Hinton, O. Vinyals, J. Dean, *Distilling the Knowledge in a Neural Network*, 2015. https://arxiv.org/abs/1503.02531
7. C. Guo, G. Pleiss, Y. Sun, K. Weinberger, *On Calibration of Modern Neural Networks* (temperature scaling), ICML 2017. https://arxiv.org/abs/1706.04599
8. M. Nygard, *Release It! Design and Deploy Production-Ready Software*, 2nd ed., Pragmatic Bookshelf, 2018 (circuit breaker, bulkheads, timeouts).
9. M. Fowler, *CircuitBreaker*. https://martinfowler.com/bliki/CircuitBreaker.html
10. Google SRE Book, *Addressing Cascading Failures*. https://sre.google/sre-book/addressing-cascading-failures/
11. S. Larson et al., *An Evaluation Dataset for Intent Classification and Out-of-Scope Prediction* (CLINC150), EMNLP 2019. https://aclanthology.org/D19-1131/
12. Anthropic, *Pricing* (Claude model prices used for the cost model). https://www.anthropic.com/pricing
