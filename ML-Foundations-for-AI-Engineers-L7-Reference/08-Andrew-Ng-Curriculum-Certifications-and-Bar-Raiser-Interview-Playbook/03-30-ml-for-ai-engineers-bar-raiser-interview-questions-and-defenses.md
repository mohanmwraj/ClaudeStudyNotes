# 08.3 · 30 ML-for-AI-Engineers Bar-Raiser Interview Questions & Defenses

> **Folder 08 · Andrew Ng Curriculum, Certifications & Bar-Raiser Interview Playbook**
> **Measured on:** every number in the 30 defenses comes from a gated listing in Folders 01–07 or from the napkin-math key in §3.1, which recomputes and checks the arithmetic (28/28 checks).
> **Design sources:** Folders 01–07 of this KB and their references; the companion Staff/Principal behavioral playbook for the story format. Full list in §8.

---

## 0. Orientation: What a Bar-Raiser Is Actually Testing

A bar-raiser in an AI engineering loop isn't checking whether you know what cosine similarity is. They're checking whether you can **make a production decision under uncertainty and defend it with numbers**: when a cheap model beats an LLM, what metric to trust, what breaks at scale, and how you'd know. Every chain below has the same five parts as the rest of this KB, and the pattern in the L5 → L7 gap is consistent:

| L5 answers… | L7 answers… |
|---|---|
| Name the technique | Name the technique, **the number it produced**, and **the condition under which it fails** |
| Assume the eval is right | Ask **what the eval measures** (prevalence, pooling, leakage, judge bias) |
| Optimize the metric | **Constrain** on what matters, optimize cost within it, and add a **margin** |
| Pick the bigger model | **Measure the cheap baseline first**, then pay for the LLM only where it earns its price |
| Ship and monitor | Ship through a **gate**, monitor with a **fixed reference**, and say what would page |

The 30 questions are grouped in six areas of five, matching Folders 01–07. Practise them by answering out loud *before* expanding the defense (08.1 §1.12). The defenses are dense on purpose: in an interview you'd say a third of this, and the rest is your follow-up ammunition.

### The backend-engineer bridge

| You already know (system design interviews) | ML-for-AI-engineers equivalent |
|---|---|
| Back-of-envelope QPS, storage and bandwidth | **Napkin math**: $ per 1M calls, vector-store GB, KV-cache MB, users per A/B arm |
| "What happens when this dependency fails?" | "What happens when the **distribution** changes?" |
| Consistency trade-offs (CAP) | **Precision/recall trade-offs**, thresholds at a base rate |
| Load tests prove capacity | **Paired evals with CIs** prove quality |
| Postmortem with a timeline and root cause | **Error analysis** with tagged buckets and shares |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Embedding geometry and retrieval math (Q1–Q5) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Classical ML for routers and guardrails (Q6–Q10) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Deep learning and transformers for engineers (Q11–Q15) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Evaluation statistics and LLM-as-a-judge (Q16–Q20) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Hybrid ML + LLM system design (Q21–Q25) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Production ML operations: leakage, skew, drift, retraining (Q26–Q30) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 How answers are scored: the L5 → L7 rubric | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Napkin math to do in your head | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Telling past work with numbers (the behavioral overlay) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Frontier questions and how to answer them honestly | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Proof-heavy theory questions (VC dimension, convergence proofs) | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Embedding geometry and retrieval math (Q1–Q5) `[MUST-KNOW: Core AI Engineer Edge]`

What's tested: ‖a − b‖² = 2 − 2·cos(a, b) on the unit sphere (01.1), so cosine, dot product and L2 rank identically only after normalization. Compression trade-offs: int8 is 4× smaller, binary 32×, both with rescoring (01.1). BM25's saturation and length normalization (04.1). Why hybrid fusion wins (04.2: 0.7257 vs 0.6711 nDCG@10 on SciFact). Contrastive training with hard negatives (04.2). When cross-encoders help or hurt (04.3).

### 1.2 Classical ML for routers and guardrails (Q6–Q10) `[MUST-KNOW: Core AI Engineer Edge]`

What's tested: heads on frozen embeddings (02.1, 02.3), with ONNX int8 at ~2 ms end to end. Linear vs tree models by data type: LR 0.985 vs LightGBM 0.952 on embeddings, but LightGBM 0.760 vs LR 0.718 on tabular data (02.2). Calibration (01.3 §1.13, 02.1 §1.7). OOD gates (02.3, 03.3). Cheap features that beat embeddings: TF-IDF 0.975 vs MiniLM 0.938 on prompt injection (02.3).

### 1.3 Deep learning and transformers for engineers (Q11–Q15) `[MUST-KNOW: Core AI Engineer Edge]`

What's tested: attention's O(n²) memory and the KV cache (05.3), encoder vs decoder trade-offs (05.4: a frozen encoder + LR head at 0.9867 and 19.6 ms vs a 135M decoder zero-shot at 0.1717 and 12,118 ms), optimizer semantics (05.2: AdamW vs L2-in-Adam), normalization folklore vs measurement (05.1), and when to fine-tune (01.2, 05.2).

### 1.4 Evaluation statistics and LLM-as-a-judge (Q16–Q20) `[MUST-KNOW: Core AI Engineer Edge]`

What's tested: precision's dependence on prevalence (06.1), metric choice by the consumer of the ranking (06.2), paired comparisons (06.4), judges as instruments (06.3), A/B power and peeking (06.4).

### 1.5 Hybrid ML + LLM system design (Q21–Q25) `[MUST-KNOW: Core AI Engineer Edge]`

What's tested: cascade cost and accuracy algebra with the base-rate trap and safety margins (07.1), semantic caching risks (03.1), mixture-latency quantiles and resilience (07.1), hallucination signals (01.3 §1.16), and routing between LLM tiers (07.1 §1.8).

### 1.6 Production ML operations: leakage, skew, drift, retraining (Q26–Q30) `[MUST-KNOW: Core AI Engineer Edge]`

What's tested: point-in-time joins (07.2), skew bugs and their detection (07.2), calibrated drift thresholds (07.3), gated retraining and the self-referential monitor trap (07.3), and embedding versions as feature versions (07.2 §1.7).

### 1.7 How answers are scored: the L5 → L7 rubric `[MUST-KNOW: Core AI Engineer Edge]`

A reasonable mental model of how interviewers score these answers (a synthesis, not any company's published rubric):

```text
L5  correct concept, generic                         "use a classifier with a confidence threshold"
L6  + concrete design and one trade-off              "... calibrated, with an OOD gate; LLM for the rest"
L7  + numbers from experience or napkin math         "... deferral 27% → $18.70 vs $68 per 1M"
    + the failure mode and how you'd detect it       "... tuned at 3% OOS it loses 4.3 points on 18% traffic"
    + the measurement plan and the gate              "... re-weight to the deployment share, +1-point margin, shadow first"
```

The single most reliable L7 move is to **name the condition under which your own answer fails**. It shows you've run the thing, not read about it.

### 1.8 Napkin math to do in your head `[MUST-KNOW: Core AI Engineer Edge]`

| Quantity | Formula | Value (checked in §3.1) |
|---|---|---|
| LLM classification cost, 630 tokens in / 10 out | tokens × $/MTok | Haiku 5.5 $68, Sonnet 5.5 $1,360, Opus 5.5 $2,720 per 1M calls |
| Local head on ~2 ms of CPU | 2 ms × $0.36/vCPU-h (assumed) | ~$0.20 per 1M (340× cheaper than Haiku) |
| Cascade cost | deferral share × LLM price + local cost | 27.2% → $18.70 per 1M |
| Deferral share needed for a 90% cut | (0.1·LLM − local)/LLM | ≤ 9.7% |
| Vector storage, 10M × 384-d | n × d × bytes | fp32 15.4 GB, int8 3.8 GB, binary 0.48 GB |
| KV cache per token (30 layers, 3 KV heads, d 64, bf16) | 2·L·h_kv·d·2 B | 23,040 B → 47 MB per 2,048-token sequence |
| Naive attention scores, n = 8,192, fp16 | n² × 2 B | 134 MB per head per layer |
| A/B users per arm, 10% → 11% | [z_α√(2p(1−p)) + z_β√(…)]²/δ² | 14,313 (napkin 16p(1−p)/δ² = 14,400) |
| Labels to measure 70% agreement ±3 pts | 1.96²·a(1−a)/h² | 897 |
| PSI no-drift 99th pct, n = 1,000, 10 bins | χ²₉(0.99)·(1/n + 1/m) | 0.022 |
| Mixture p99 at 35% LLM share | LLM's (1 − 0.01/0.35) quantile | ~1,810 ms (lognormal, median 700 ms) |

### 1.9 Telling past work with numbers (the behavioral overlay) `[GOOD-TO-KNOW: Architectural Literacy]`

Technical questions often turn into "tell me about a time…". Use the same structure as the companion behavioral playbook: situation in one sentence, *your* decision and its alternatives, the measured outcome, and what you'd do differently. The numbers in these defenses come from this KB's experiments. In an interview, replace them with your own, or say explicitly "in a benchmark I ran…". **Never present someone else's numbers, or this KB's simulations, as production results from a past job.**

### 1.10 Frontier questions and how to answer them honestly `[GOOD-TO-KNOW: Architectural Literacy]`

"What do you think of [the newest method]?" The L7 answer separates what's established from what's claimed: "The paper reports X on Y. I'd want to see it on our distribution, with a paired comparison against our current baseline, before changing anything." Then say how you'd test it cheaply. Confidently summarizing a paper you haven't read is the fastest way to fail a bar-raiser.

### 1.11 Proof-heavy theory questions (VC dimension, convergence proofs) `[SKIP: Academic/Research Only]`

They're rare in AI *engineering* loops. If asked, give the intuition (capacity vs data; why SGD converges on convex problems, and the conditions), and steer to how it informs a decision (more data vs regularization; learning-rate schedules). Don't fake a proof.

---

## 2. Where It Beats an LLM in Production: The Question Behind Every Question

Almost every AI engineering design question contains a hidden one: **"would you use an LLM for this?"** A framework that consistently scores well:

1. **What's the label space?** Fixed classes (routing, guardrails, extraction into a schema) point to a cheap scorer first. Open-ended generation points to the LLM.
2. **What's the volume and the latency budget?** $68 per 1M Haiku-class calls vs ~$0.20 for a head. ~700 ms vs ~2 ms.
3. **What does the cheap baseline score on a representative eval set?** Measure it before arguing.
4. **Where does the cheap model fail?** Error-analyze its confident errors and its deferrals.
5. **Design the hybrid:** cascade with calibrated gates, thresholds at the deployment base rate with a margin, the LLM for the remainder, distillation over time.

Across Folders 02–07 the cheap baseline was often closer to the LLM than expected. A cascade matched LLM-only accuracy at 72.5% lower cost. TF-IDF beat a transformer on prompt injection. Logistic regression beat an MLP head. Saying "I'd measure the cheap baseline first, and here's what I've seen it achieve" is the most reliable way to sound like someone who has shipped.

---

## 3. Production Code Blueprint

### 3.1 The napkin-math answer key

```python
"""interview_napkin_math.py - the answer key for every number quoted in 08.3's 30 bar-raiser defenses.

Prices: Claude list prices per million tokens (Haiku 5.5 $0.10 in / $0.50 out, Sonnet 5.5 $2 / $10, Opus 5.5 $4 / $20).
CPU cost of the local stage is an ASSUMPTION ($0.36 per fully loaded vCPU-hour, ~2 ms per request). Everything else is
arithmetic or a closed-form statistic, checked here so the interview answers never drift from the math.
"""
import math

from scipy import stats

checks = []


def show(label, value, expect, tol=1e-3):
    ok = abs(value - expect) <= tol * max(1.0, abs(expect))
    checks.append(ok)
    txt = f"{value:,.0f}" if abs(value) >= 1000 else f"{value:.4g}"
    print(f"  {'OK ' if ok else 'BAD'} {label:66s} {txt}")


print("== cost: LLM classification vs a head on frozen embeddings (630 tokens in, 10 out per call) ==")
price = {"Haiku 5.5": (0.10, 0.50), "Sonnet 5.5": (2.0, 10.0), "Opus 5.5": (4.0, 20.0)}
per_m = {m: (630 * i + 10 * o) for m, (i, o) in price.items()}     # $ per 1M calls = tokens x $/MTok
show("Haiku 5.5, $ per 1M calls", per_m["Haiku 5.5"], 68.0)
show("Sonnet 5.5, $ per 1M calls", per_m["Sonnet 5.5"], 1360.0)
show("Opus 5.5, $ per 1M calls", per_m["Opus 5.5"], 2720.0)
head = 0.002 * 0.36 / 3600 * 1e6                                      # 2 ms at $0.36 per vCPU-hour
show("local head, $ per 1M requests (assumed CPU price)", head, 0.20)
show("Haiku-to-head cost ratio", per_m["Haiku 5.5"] / head, 340.0)
show("cascade $ per 1M at 27.2% deferral (encoder on 98.1%)", 0.272 * 68 + 0.981 * head, 18.70, tol=2e-3)
show("max deferral share for a 90% cut vs Haiku-only", (0.1 * 68 - head) / 68, 0.0971, tol=2e-3)

print("\n== vectors and memory ==")
show("10M x 384-d fp32 embeddings, GB", 10e6 * 384 * 4 / 1e9, 15.36)
show("same, int8, GB", 10e6 * 384 / 1e9, 3.84)
show("same, binary (1 bit/dim), GB", 10e6 * 384 / 8 / 1e9, 0.48)
show("brute-force kNN multiply-adds per query, billions", 10e6 * 384 / 1e9, 3.84)
kv_per_token = 2 * 30 * 3 * 64 * 2                                     # K and V x layers x KV heads x head dim x bf16
show("SmolLM2-135M KV-cache bytes per token (30 L, 3 KV heads, d 64)", kv_per_token, 23040)
show("  ... per 2,048-token sequence, MB", kv_per_token * 2048 / 1e6, 47.19)
show("naive attention score matrix, n = 8,192, fp16, one head, MB", 8192 ** 2 * 2 / 1e6, 134.2)

print("\n== statistics ==")
p, d = 0.10, 0.01
za, zb = stats.norm.ppf(0.975), stats.norm.ppf(0.8)
n_ab = math.ceil((za * math.sqrt(2 * p * (1 - p)) + zb * math.sqrt(p * (1 - p) + (p + d) * (1 - p - d))) ** 2 / d ** 2)
show("A/B users per arm, 10% -> 11%, alpha 0.05, power 0.8", n_ab, 14313, tol=0)
show("napkin 16 p(1-p) / d^2", 16 * p * (1 - p) / d ** 2, 14400)
k, n, z = 297, 300, 1.96
ph = k / n
wil = (ph + z * z / (2 * n) - z * math.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n))) / (1 + z * z / n)
show("Wilson 95% lower bound, 297 correct of 300", wil, 0.9710, tol=2e-3)
show("rule of three: 0 failures in 300 -> 95% upper bound", 3 / 300, 0.01)
show("labels to estimate 70% agreement within +-3 points", math.ceil(1.96 ** 2 * 0.7 * 0.3 / 0.03 ** 2), 897, tol=0)
show("+-half-width of accuracy at n = 1,000, p = 0.9", 1.96 * math.sqrt(0.9 * 0.1 / 1000), 0.0186, tol=5e-3)
b, c = 45, 25
chi = (abs(b - c) - 1) ** 2 / (b + c)
show("McNemar chi-square, 45 vs 25 disagreements", chi, 5.157, tol=2e-3)
show("  ... p-value", stats.chi2.sf(chi, 1), 0.0232, tol=2e-2)
show("precision at prevalence 0.1%, TPR 0.5, FPR 0.0668", 0.001 * 0.5 / (0.001 * 0.5 + 0.999 * 0.0668), 0.00744, tol=5e-3)
show("PSI null 99th pct: chi2_9(0.99) x (1/1000 + 1/50000)", stats.chi2.ppf(0.99, 9) * (1 / 1000 + 1 / 50000), 0.0221, tol=5e-3)
show("PSI of a 0.5-sd mean shift (Jeffreys divergence = delta^2)", 0.5 ** 2, 0.25)
show("KS 5% noise level at n = 10,000 per side", 1.36 * math.sqrt(2 / 10_000), 0.0192, tol=5e-3)
q = stats.norm.ppf(1 - 0.01 / 0.35)
show("cascade p99 = LLM (1 - 0.01/0.35) quantile, lognormal(700 ms, 0.5)", 700 * math.exp(0.5 * q), 1811, tol=2e-3)
show("P(>= 1 false positive) across 12 independent slices at 5%", 1 - 0.95 ** 12, 0.4596, tol=2e-3)
print(f"\n{sum(checks)}/{len(checks)} checks agree with the numbers quoted in 08.3")
assert all(checks)
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== cost: LLM classification vs a head on frozen embeddings (630 tokens in, 10 out per call) ==
  OK  Haiku 5.5, $ per 1M calls                                          68
  OK  Sonnet 5.5, $ per 1M calls                                         1,360
  OK  Opus 5.5, $ per 1M calls                                           2,720
  OK  local head, $ per 1M requests (assumed CPU price)                  0.2
  OK  Haiku-to-head cost ratio                                           340
  OK  cascade $ per 1M at 27.2% deferral (encoder on 98.1%)              18.69
  OK  max deferral share for a 90% cut vs Haiku-only                     0.09706

== vectors and memory ==
  OK  10M x 384-d fp32 embeddings, GB                                    15.36
  OK  same, int8, GB                                                     3.84
  OK  same, binary (1 bit/dim), GB                                       0.48
  OK  brute-force kNN multiply-adds per query, billions                  3.84
  OK  SmolLM2-135M KV-cache bytes per token (30 L, 3 KV heads, d 64)     23,040
  OK    ... per 2,048-token sequence, MB                                 47.19
  OK  naive attention score matrix, n = 8,192, fp16, one head, MB        134.2

== statistics ==
  OK  A/B users per arm, 10% -> 11%, alpha 0.05, power 0.8               14,313
  OK  napkin 16 p(1-p) / d^2                                             14,400
  OK  Wilson 95% lower bound, 297 correct of 300                         0.971
  OK  rule of three: 0 failures in 300 -> 95% upper bound                0.01
  OK  labels to estimate 70% agreement within +-3 points                 897
  OK  +-half-width of accuracy at n = 1,000, p = 0.9                     0.01859
  OK  McNemar chi-square, 45 vs 25 disagreements                         5.157
  OK    ... p-value                                                      0.02315
  OK  precision at prevalence 0.1%, TPR 0.5, FPR 0.0668                  0.007437
  OK  PSI null 99th pct: chi2_9(0.99) x (1/1000 + 1/50000)               0.0221
  OK  PSI of a 0.5-sd mean shift (Jeffreys divergence = delta^2)         0.25
  OK  KS 5% noise level at n = 10,000 per side                           0.01923
  OK  cascade p99 = LLM (1 - 0.01/0.35) quantile, lognormal(700 ms, 0.5) 1,812
  OK  P(>= 1 false positive) across 12 independent slices at 5%          0.4596

28/28 checks agree with the numbers quoted in 08.3

ALL ASSERTIONS PASSED
```

### 3.2 The answer skeleton for any design question

```text
1. Clarify the decision and its consumer   (what reads the output? what does an error cost? what base rate?)
2. Baseline first                           (cheapest model that could work; how you'd measure it)
3. Design                                   (stages, gates, thresholds; the napkin cost and latency)
4. Failure modes                            (the one that breaks YOUR design; how it's detected)
5. Measurement and rollout                  (eval set, paired test, shadow, gate, monitors with fixed references)
```

---

## 4. The Andrew Ng Lens: Show the Loop, Not the Vocabulary

Ng's frameworks give interview answers their structure: **error analysis** (find the bucket before the fix), **bias/variance** (diagnose before prescribing), **dev/test from the deployment distribution** (base rates), **ceiling analysis** (fund the bottleneck), and **evaluation-driven development** (build fast, measure, iterate). An answer that walks the loop ("I'd pull 100 failures, tag them, and the biggest bucket decides") is more convincing than one that lists techniques, because it's how strong teams actually work.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix |
|---|---|---|---|---|
| F1 | "Sounds right, but L5" feedback | Technique names, no numbers | No napkin math or measured results | Learn §1.8. Quote a number and its condition |
| F2 | Interviewer keeps asking "how would you know?" | No measurement plan | Design without evaluation | Always end with eval, gate and monitor |
| F3 | Answer collapses under one follow-up | Memorized defense | No understanding of the failure mode | Answer chains out loud; re-derive the numbers |
| F4 | "Just use GPT/Claude" | No cost, latency or eval reasoning | Skipping the hidden question (§2) | Baseline first, then hybrid |
| F5 | Overclaiming past results | Can't explain how a number was measured | Borrowed or simulated numbers presented as production | Say where every number comes from |
| F6 | Frontier question bluffed | Confident claims about unread papers | Fear of saying "I don't know" | Separate established from claimed; propose a test |
| F7 | Ran out of time | 10-minute monologue on one part | No answer skeleton | §3.2: clarify → baseline → design → failures → measurement |

---

## 6. Bar-Raiser Q&A Chains

The 30 chains follow, grouped by area. Each one cites the KB folder where the numbers were measured.

### Area 1 · Embedding geometry and retrieval (Q1–Q5)

<details><summary><b>Q1 · "Cosine similarity, dot product or L2 distance: which do you use for vector search?"</b></summary>

**Initial Prompt.** Configuring a vector index for a RAG system.

**L5 Answer.** "Cosine, because it's the standard for embeddings."

**Why L5 Fails in Production.** The three are equivalent only under a condition (normalization), and choosing without checking it silently changes rankings. Some models are trained for dot product with meaningful norms.

**L7 Principal Defense.** "On unit vectors they're the same ranking: ‖a − b‖² = 2 − 2·cos(a, b), and the dot product equals cosine. So I'd check whether the model's embeddings are normalized (some APIs return normalized vectors only at full dimension, so truncation needs re-normalization), normalize once at write time, and use the index's inner-product operator, which is the cheapest. If the model was trained with dot product and norms carry information, I keep raw dot product. Thresholds don't transfer between spaces either: in 01.1 a cosine threshold re-used on an anisotropic space dropped precision from 0.95 to 0.25."

**Bar-Raiser Follow-ups.**
- *"Why does anisotropy matter?"* Embeddings occupy a narrow cone, so absolute cosine values are inflated and thresholds must be re-derived per model, ideally after mean-centering (01.1).

</details>

<details><summary><b>Q2 · "Our vector store will hold 10M chunks. How do you make it 30× smaller without wrecking recall?"</b></summary>

**Initial Prompt.** A cost review of a growing RAG index.

**L5 Answer.** "Use product quantization."

**Why L5 Fails in Production.** It names one technique without the storage math, the recall cost, or the standard fix (rescoring).

**L7 Principal Defense.** "Napkin first: 10M × 384 dims × fp32 is 15.4 GB. int8 is 3.8 GB (4×), binary is 0.48 GB (32×). The recall cost depends on doing it right. In 01.1, naive affine int8 got recall@10 of 0.629 while symmetric int8 got 0.980. Binary alone gave 0.365, but binary search with a ×10 candidate rescoring against higher-precision vectors recovered 0.995. Matryoshka truncation or PCA (with the mean-coordinate trick, 0.995 at 64 dims in 01.2) cut dimensions as well. So: binary or int8 for the first pass, rescore the top-k×10 with full vectors from cheap storage, and measure recall@k at our context budget before and after."

**Bar-Raiser Follow-ups.**
- *"Where do the full vectors live?"* On disk or object storage. Only the top candidates are fetched, so it's an I/O budget question.

</details>

<details><summary><b>Q3 · "Why does hybrid search beat dense retrieval alone?"</b></summary>

**Initial Prompt.** A team wants to drop BM25 to simplify the stack.

**L5 Answer.** "Dense embeddings capture meaning, so BM25 is obsolete."

**Why L5 Fails in Production.** On SciFact, BM25 (0.6711 nDCG@10) *beats* MiniLM dense retrieval (0.6451), and the hybrid beats both.

**L7 Principal Defense.** "Lexical and dense errors are partly uncorrelated. BM25 nails rare exact terms (gene names, numbers, product codes), and dense handles paraphrase. On SciFact: BM25 0.6711, dense 0.6451, RRF 0.6929, and a convex combination of normalized scores with α tuned on training queries 0.7257. RRF is the zero-label default. Convex fusion wins once you have labelled queries, because it uses score margins. The paired bootstrap puts the hybrid gain over BM25 at +0.055 [+0.030, +0.079], so it's real. Dropping BM25 would cost us about 8 points over the hybrid on this kind of corpus."

**Bar-Raiser Follow-ups.**
- *"Would you tune α on the test set?"* Never. Ours was tuned on 809 training claims. Tuning BM25's k1/b on train actually *hurt* test (0.6665).

</details>

<details><summary><b>Q4 · "We added a cross-encoder re-ranker and quality went down. How is that possible?"</b></summary>

**Initial Prompt.** A zero-shot MS MARCO cross-encoder over hybrid top-20.

**L5 Answer.** "It must be a bug; cross-encoders are always better."

**Why L5 Fails in Production.** It's domain shift, and we measured it: on SciFact, the zero-shot cross-encoder scored 0.6818 vs the hybrid's 0.7257.

**L7 Principal Defense.** "A cross-encoder trained on web search queries is out of domain on scientific claims, so it can re-rank good hybrid results into worse ones. It's also slow: 900–1,900 ms per 20 pairs on CPU in 04.3. Before re-ranking I'd run a ceiling analysis: how much is a perfect re-ranker worth on our candidates? Then compare cheap options. LambdaMART on lexical, dense and metadata features reached 0.7191 in 0.51 ms. Then try a cross-encoder *fine-tuned* on in-domain pairs, and combine its score with the first-stage scores rather than replacing them. LambdaMART + CE got 0.7212."

**Bar-Raiser Follow-ups.**
- *"When is a cross-encoder clearly right?"* In-domain, fine-tuned, on a small candidate set, with GPU serving and a latency budget that allows it.

</details>

<details><summary><b>Q5 · "How are bi-encoders trained, and why do hard negatives matter?"</b></summary>

**Initial Prompt.** A team wants to adapt embeddings to their domain.

**L5 Answer.** "Train on query-document pairs with a contrastive loss."

**Why L5 Fails in Production.** It's correct but empty: no loss, no negatives strategy, no measured effect, no risk.

**L7 Principal Defense.** "InfoNCE: for each query, a softmax over its positive document and the negatives (in-batch plus mined hard negatives), with a temperature τ. That's a lower bound on mutual information, and it pushes positives up and nearby negatives down. Random in-batch negatives are mostly easy and teach little. Hard negatives (BM25 or dense near-misses that aren't relevant) teach the boundary that matters. In 04.2, a small query-side adapter trained with hard negatives took MiniLM from 0.6451 to 0.6968 nDCG@10 (+5.2). The risks are false negatives among mined 'hard negatives' (unlabelled positives), so filter by a cross-encoder or by score margins, and overfitting a small query set. Evaluate on held-out queries with a paired test."

**Bar-Raiser Follow-ups.**
- *"Why adapt only the query side?"* The document index doesn't need re-embedding. It's cheap to deploy and to roll back.

</details>

### Area 2 · Classical ML for routers and guardrails (Q6–Q10)

<details><summary><b>Q6 · "Design a 2 ms intent router."</b></summary>

**Initial Prompt.** 150 intents, currently classified by an LLM call.

**L5 Answer.** "Fine-tune BERT and deploy it."

**Why L5 Fails in Production.** It doesn't say where the 2 ms comes from, how out-of-scope queries are handled, or how confidence is calibrated.

**L7 Principal Defense.** "A frozen small encoder (MiniLM), exported to ONNX and int8-quantized: in 02.3 that's ~2 ms p50 end to end on one CPU thread, vs ~11 ms eager PyTorch. A logistic-regression head on the embeddings, temperature-calibrated (it was under-confident, T = 0.63). An OOD gate: max cosine to class centroids, which beat softmax confidence at detecting out-of-scope queries (0.966 vs 0.945 in 02.3). Thresholds tuned at the deployment OOS share, and the uncertain remainder deferred to the LLM (07.1). The int8 step cost 0.7 points of accuracy (0.955 → 0.948), which I'd accept after checking per-intent floors."

**Bar-Raiser Follow-ups.**
- *"Why not fine-tune the encoder?"* Start frozen: it's cheaper, easier to version, and the head already reached 0.955. Fine-tune if error analysis shows representation errors.

</details>

<details><summary><b>Q7 · "Logistic regression or gradient boosting for the router head?"</b></summary>

**Initial Prompt.** A team defaults to XGBoost for everything.

**L5 Answer.** "XGBoost; it wins Kaggle."

**Why L5 Fails in Production.** It wins on tabular data. On dense embeddings, a linear model is usually better and far cheaper.

**L7 Principal Defense.** "It depends on the feature space. In 02.2, on MiniLM embeddings, LR scored 0.985 vs LightGBM 0.952. Embedding dimensions are dense, roughly linearly separable, and individually meaningless, which suits a linear model. On tabular features (counts, categories, thresholds), LightGBM beat LR 0.760 vs 0.718, because trees capture interactions and monotone thresholds. So: LR on embeddings, GBDT on tabular metadata, and stack them if both feature types matter (re-ranking, 04.3). I'd confirm on a paired comparison, since McNemar on the disagreements is the right test for two classifiers on the same items."

**Bar-Raiser Follow-ups.**
- *"Latency?"* An LR head is a matrix-vector product: 15.7 µs in NumPy vs 116 µs through sklearn's `predict_proba` (02.1). Framework overhead dominates.

</details>

<details><summary><b>Q8 · "Would you use embeddings or TF-IDF for a prompt-injection classifier?"</b></summary>

**Initial Prompt.** A guardrail for user inputs to an agent.

**L5 Answer.** "Embeddings; they understand semantics."

**Why L5 Fails in Production.** On the deepset prompt-injection dataset, TF-IDF beat MiniLM: 0.975 vs 0.938 (02.3).

**L7 Principal Defense.** "Injection attacks carry lexical signatures (instruction phrases, role markers, specific tokens) that sparse features capture directly, while a general-purpose sentence embedding smooths them away. I'd baseline both, and TF-IDF + LR won here. Then I'd error-analyze by language: German error rates were about 2× English, a data-coverage gap. And I'd treat the classifier as one layer: a high-precision blocker at a threshold set for the deployment base rate, an LLM or human review band for the uncertain middle, and output-side checks for what gets through."

**Bar-Raiser Follow-ups.**
- *"Adversarial robustness?"* Lexical models are easier to evade with paraphrase, so red-team continuously, add character n-grams, and monitor the flag rate for prior shift.

</details>

<details><summary><b>Q9 · "Why does calibration matter if accuracy is fine?"</b></summary>

**Initial Prompt.** A router with 95% accuracy and uncalibrated scores.

**L5 Answer.** "Calibration is cosmetic if the top-1 is right."

**Why L5 Fails in Production.** Every threshold, cascade gate and cost rule consumes the *probability*, not the argmax. Miscalibration silently moves the deferral share and the bill.

**L7 Principal Defense.** "Three consumers need calibrated probabilities. (1) The cost-optimal threshold p > C_FP/(C_FP + C_FN) assumes them (06.1 §1.5). (2) A cascade gate at 'confidence ≥ 0.9' only means 90% if calibrated. Otherwise every retrain shifts the deferral share and the cost (07.1). (3) Aggregate estimates such as an expected pass rate. Temperature scaling is one parameter fitted on validation NLL: in 01.3 it took ECE from 0.182 to 0.009 without changing accuracy. I'd re-fit it on every retrain and track ECE in the release gate."

**Bar-Raiser Follow-ups.**
- *"Platt or isotonic?"* Platt or temperature with little data. Isotonic with thousands of validation examples and a non-sigmoid miscalibration shape.

</details>

<details><summary><b>Q10 · "How do you detect out-of-scope queries for a router?"</b></summary>

**Initial Prompt.** Users ask things the router has no intent for.

**L5 Answer.** "Add an 'other' class to the classifier."

**Why L5 Fails in Production.** An 'other' class only learns the out-of-scope examples you collected. Novel out-of-scope traffic still gets routed confidently to an intent.

**L7 Principal Defense.** "Combine a trained OOS class with distance-based detectors that don't need examples of every unknown. In 03.3, relative Mahalanobis distance on embeddings scored AUROC 0.972 with FPR95 0.116, best of the methods tested, versus 0.706 for Isolation Forest. Ledoit–Wolf shrinkage made the covariance usable: its condition number fell from ~10¹⁶ to 268. A cosine-to-centroid gate is the cheap version (0.966 in 02.3). Thresholds come from the deployment OOS share: CLINC's validation split is 3.2% OOS vs 18.2% in test, and tuning at the wrong share cost 4.3 points in 07.1."

**Bar-Raiser Follow-ups.**
- *"Why does plain Mahalanobis underperform the relative version?"* Distance to the in-domain classes is confounded by general 'typicality'. Subtracting a background-distribution distance removes it.

</details>

### Area 3 · Deep learning and transformers for engineers (Q11–Q15)

<details><summary><b>Q11 · "Explain the memory cost of attention and the KV cache."</b></summary>

**Initial Prompt.** Sizing GPU memory for a long-context deployment.

**L5 Answer.** "Attention is quadratic, so long contexts are expensive."

**Why L5 Fails in Production.** It's true, but it doesn't separate the two different costs (prefill attention scores vs the decode-time KV cache), and gives no numbers.

**L7 Principal Defense.** "Two costs. **Prefill:** naive attention materializes an n×n score matrix per head per layer. At n = 8,192 in fp16 that's 134 MB per head per layer, which is why fused kernels (FlashAttention) compute it in tiles without storing it. **Decode:** each generated token attends to cached K and V for all previous tokens. KV cache per token = 2 × layers × KV heads × head dim × bytes. For SmolLM2-135M (30 layers, 3 KV heads from grouped-query attention, head dim 64, bf16) that's 23,040 bytes, or 47 MB per 2,048-token sequence. Multiply by concurrent sequences to get the serving memory. GQA (3 KV heads instead of 9) cut it 3×. In 05.3 the KV cache reproduced full recomputation to 7.7e-7."

**Bar-Raiser Follow-ups.**
- *"How else do you cut KV memory?"* Quantized KV caches, paged allocation (vLLM-style), sliding-window attention, and shorter contexts via better retrieval.

</details>

<details><summary><b>Q12 · "Why use a small encoder instead of a decoder LLM for classification?"</b></summary>

**Initial Prompt.** A team prompts a 135M-parameter decoder to classify intents.

**L5 Answer.** "Decoders are more capable, so they classify better."

**Why L5 Fails in Production.** In 05.4, on a 20-intent task, frozen MiniLM + LR scored 0.9867 at a p50 of 19.6 ms, while the 135M decoder scored 0.1717 zero-shot at a p50 of 12,118 ms, and 0.9067 even with its frozen features feeding an LR head.

**L7 Principal Defense.** "For fixed-label classification, a bidirectional encoder sees the whole input at once and produces one pooled representation: one forward pass, no generation. A decoder used zero-shot scores every label by likelihood, paying a forward pass per label. In 05.4: frozen MiniLM + LR 0.9867 (fine-tuning MiniLM for 3 epochs added nothing: also 0.9867), SmolLM2-135M frozen features + LR 0.9067 with 6× the parameters, and SmolLM2 zero-shot 0.1717 at 12 s per query over 20 labels. With a few labelled examples per class, the encoder head dominates on accuracy, latency and cost. Use a decoder when the task is generative or the label space is open, and then a much larger hosted one."

**Bar-Raiser Follow-ups.**
- *"What about a large decoder zero-shot?"* It can be accurate, at $68+ per million calls and ~700 ms. Use it as the cascade's fallback, not the default.

</details>

<details><summary><b>Q13 · "What's the difference between Adam with weight_decay and AdamW, and why care?"</b></summary>

**Initial Prompt.** A fine-tuning recipe uses `Adam(params, weight_decay=0.01)`.

**L5 Answer.** "AdamW is just the newer name."

**Why L5 Fails in Production.** They're different algorithms. L2 inside Adam is divided by √v, so large-gradient weights get much less decay.

**L7 Principal Defense.** "Adam with weight_decay adds λw to the gradient, then normalizes by √v̂, so the effective decay depends on gradient statistics. We read the optimizer state in 05.2 and measured 1.46e-3 per step for large-gradient weights vs 2.50e-2 for the rest, a 17× difference. AdamW decouples it: w ← w − ηλw for every weight, a uniform 1.00e-2 per step in the same run. So use AdamW, exclude biases and norm gains through parameter groups, and match the optimizer *class* when reproducing a paper."

**Bar-Raiser Follow-ups.**
- *"First thing to tune?"* The learning rate, on a log scale with a range test. The step-0 loss should be ≈ ln K (5.01 for 150 classes).

</details>

<details><summary><b>Q14 · "RMSNorm is cheaper than LayerNorm, right?"</b></summary>

**Initial Prompt.** A performance discussion about a custom model.

**L5 Answer.** "Yes, it skips the mean, so it's faster."

**Why L5 Fails in Production.** Fewer FLOPs isn't faster in practice. Measured unfused on CPU in 05.1, RMSNorm took 20.9 ms vs LayerNorm's 7.2 ms, because LayerNorm has an optimized fused kernel and the hand-written RMSNorm doesn't.

**L7 Principal Defense.** "In FLOPs, yes. In wall-clock, it depends on the kernel. Normalization is memory-bound, so the number of passes over memory matters more than arithmetic. PyTorch's LayerNorm is a single fused kernel, while a composed RMSNorm (pow, mean, rsqrt, mul) launches several passes. With a fused RMSNorm kernel (as in production LLM stacks), it is faster. The general lesson for interviews and for work: measure on the target hardware with the actual kernels before trusting an operation-count argument."

**Bar-Raiser Follow-ups.**
- *"Why do LLMs use RMSNorm then?"* Comparable quality, simpler, and slightly cheaper *when fused*. The re-centering in LayerNorm turned out to be unnecessary.

</details>

<details><summary><b>Q15 · "When do you fine-tune, when do you train a head, and when do you just prompt?"</b></summary>

**Initial Prompt.** A team wants to fine-tune an LLM for ticket classification.

**L5 Answer.** "Fine-tuning always beats prompting."

**Why L5 Fails in Production.** It skips the cheapest options that often win, and ignores what kind of gap you're fixing.

**L7 Principal Defense.** "Diagnose the gap first (06.3 §1.5). Missing knowledge → RAG. Wrong format or behaviour, persistently → few-shot examples, then fine-tuning. A fixed label space with labelled data → a head on frozen embeddings first. For classification, the head usually wins on cost and is competitive on accuracy. In 05.2 even an MLP head (0.9493) didn't beat plain logistic regression (0.9600) on frozen MiniLM embeddings. If the head isn't enough, fine-tune the encoder or use LoRA (01.2: scale updates by α/r, merge carefully, since a bf16 merge lost 2.8% of ΔW). Prompting a large LLM is the fallback for the uncertain slice, not the default."

**Bar-Raiser Follow-ups.**
- *"LoRA rank?"* Small (4–16) for narrow tasks. In 01.2 an SVD-extracted rank-4 adapter matched a full fine-tune on the toy task.

</details>

### Area 4 · Evaluation statistics and LLM-as-a-judge (Q16–Q20)

<details><summary><b>Q16 · "Our guardrail has ROC-AUC 0.95 and 99% precision on the test set. Ship it?"</b></summary>

**Initial Prompt.** The test set was balanced; production prevalence is ~1 in 1,000.

**L5 Answer.** "Those are excellent numbers; ship."

**Why L5 Fails in Production.** Precision depends on prevalence. A classifier with TPR 0.5 and FPR 0.067 has precision 0.88 at 50% prevalence and 0.0074 at 0.1% (06.1).

**L7 Principal Defense.** "ROC-AUC is conditioned on the class, so it's blind to the base rate. Precision isn't: precision = π·TPR / (π·TPR + (1 − π)·FPR). I'd re-estimate it at the deployment π *before* labelling anything. Then I'd validate on the flagged stream, since that's where precision lives. To claim ≥ 99% with confidence, the Wilson lower bound must clear the bar. 297 correct of 300 flags gives a lower bound of 0.971, not 0.99, so 99% needs more flags or zero errors on ~300 (rule of three). Then pick the threshold from costs or a block-rate budget, and ship in shadow mode first."

**Bar-Raiser Follow-ups.**
- *"Comparing two guardrails on the same set?"* Use a paired test. McNemar on disagreements, e.g. 45 vs 25, gives χ² = 5.16, p ≈ 0.023.

</details>

<details><summary><b>Q17 · "What metric would you use to evaluate retrieval for our RAG bot?"</b></summary>

**Initial Prompt.** The bot puts 8 chunks in the context.

**L5 Answer.** "nDCG@10."

**Why L5 Fails in Production.** nDCG@10 models a user scanning a ranked page. The consumer here is an LLM reading 8 chunks, where *presence* matters more than position.

**L7 Principal Defense.** "Choose the metric from the consumer: **Recall@8** as the headline, the **zero-recall rate** (queries with nothing relevant in context, which produce wrong answers or refusals), and Precision@8 for token cost. On SciFact the best system still had 12.7% zero-score queries vs BM25's 17.7%: that's the user-visible improvement, not the mean. With a re-ranker, stage 1 gets Recall@N at the re-ranker's input size. I'd also make sure the qrels were pooled from *all* candidate systems: in 06.2, incomplete judgments reversed a comparison (0.797 vs 0.293 with complete labels; 0.087 vs 0.366 on the old pool)."

**Bar-Raiser Follow-ups.**
- *"LLM-labelled relevance?"* Fine, at ~$0.50 per 6,000 judgments with a Haiku-class model, after measuring κ against a human subset per system.

</details>

<details><summary><b>Q18 · "The new retriever is +0.05 nDCG@10 on 300 queries. Is that significant?"</b></summary>

**Initial Prompt.** Hybrid vs BM25 on SciFact.

**L5 Answer.** "Bootstrap each system's mean; the intervals overlap, so no."

**Why L5 Fails in Production.** Both systems ran on the same queries. The unpaired CI includes query-difficulty variance that cancels in the difference: [−0.006, +0.114] unpaired vs [+0.030, +0.079] paired.

**L7 Principal Defense.** "Paired. Per-query differences dᵢ, a bootstrap over queries for the CI, and a sign-flip permutation test for the p-value: +0.0545 [+0.030, +0.079], and none of 10,000 sign flips was as extreme, so p ≤ 1e-4. The paired interval is 2.5× narrower because a query both systems fail contributes 0 to the difference. BM25 vs dense on the same queries is +0.026 [−0.012, +0.064], p = 0.18: not established, so I wouldn't claim it either way. Also, 'overlapping CIs' isn't a valid test even for unpaired data. Test the difference itself."

**Bar-Raiser Follow-ups.**
- *"Resampling unit?"* The independent unit: queries, not query-document pairs. Conversations, not turns.

</details>

<details><summary><b>Q19 · "How do you know your LLM judge is right?"</b></summary>

**Initial Prompt.** An LLM judge scores answer correctness for weekly evals.

**L5 Answer.** "We checked it agrees with us on 50 examples."

**Why L5 Fails in Production.** Fifty examples give ±8–13 points, raw agreement isn't chance-corrected (an always-pass judge scored 41% agreement at κ = 0), and nothing checks for its known biases.

**L7 Principal Defense.** "Validate it like an instrument (06.3). Two humans on a stratified set give the ceiling (human-human κ 0.71 in our simulation). Judge-human κ was 0.43, a weak instrument. For agreement ±3 points at ~70%, that's 897 labels; ±5 needs 324. Bias audits: pass rate by length at matched quality (the simulated judge went 0.87 → 1.00 across length quartiles while humans stayed flat), a position-swap flip rate in pairwise mode (it picked the first-shown answer 55.1% of the time), and per-system κ for self-preference. Its raw pass rate was 0.655 vs humans' 0.400, so absolute numbers need calibration (Platt brought it to 0.421) or PPI."

**Bar-Raiser Follow-ups.**
- *"Cheapest improvement?"* Binary, criterion-specific judges, one per error-analysis bucket, with the reference answer in the prompt.

</details>

<details><summary><b>Q20 · "How long should we run the A/B test, and can we stop early?"</b></summary>

**Initial Prompt.** Detecting a lift in task success from 10% to 11%.

**L5 Answer.** "A week, and we'll stop when it's significant."

**Why L5 Fails in Production.** Duration comes from power, and "stop when significant" is peeking: 24.2% false positives with 20 looks in 06.4.

**L7 Principal Defense.** "n per arm ≈ 14,313 for 10% → 11% at α = 0.05 and power 0.8 (napkin 16p(1−p)/δ² = 14,400). Duration = n × 2 / eligible daily traffic, rounded up to whole weeks. Early stopping only with a planned sequential design (O'Brien–Fleming looks, or an always-valid test). Harm guardrails can stop it early; success can't. To shorten it legitimately, use CUPED with a pre-period covariate: in 06.4 it cut the variance to 22%, turning z = 1.92 into 5.35 for the same true effect. Check SRM automatically, and pre-register the primary metric. With 12 slices tested post hoc, the chance of at least one false positive is 46%."

**Bar-Raiser Follow-ups.**
- *"Bandit instead?"* Only if we don't need a clean effect estimate. Thompson sampling lost 60.6 successes vs 200 for a fixed split in 06.4, at the cost of a biased estimate.

</details>

### Area 5 · Hybrid ML + LLM system design (Q21–Q25)

<details><summary><b>Q21 · "Design a system that cuts our LLM classification bill by 90%."</b></summary>

**Initial Prompt.** 20M requests a month through a Haiku-class classifier.

**L5 Answer.** "Put a BERT model in front and send low-confidence cases to the LLM."

**Why L5 Fails in Production.** No deferral math, no base-rate check, no margin, and 90% may be impossible at parity.

**L7 Principal Defense.** "Cost ≈ deferral share × $68 per 1M + ~$0.20 local, so a 90% cut needs ≤ 9.7% deferral. Measure how much traffic *should* defer first. On CLINC, 18% is out of scope, so 90% at parity is impossible there: we got 72.5% at parity ($18.70 vs $68) and 82.9% at −4.3 points. The design: rules for auditable intents, a calibrated head with a confidence *and* a similarity gate, the LLM for the rest. Thresholds from min cost s.t. accuracy ≥ LLM-only + margin, on a tuning set re-weighted to the deployment OOS share. Tuning on the raw 3%-OOS validation split lost 4.3 points on 18%-OOS test traffic; re-weighting recovered 3.1, and a +1-point margin reached parity. Then deadlines, a breaker, a cache, and distillation from LLM labels to shrink the deferral share."

**Bar-Raiser Follow-ups.**
- *"How does it fail silently?"* Base-rate shift or a retrain changing confidence scales. Monitor the deferral share and sampled per-stage accuracy.

</details>

<details><summary><b>Q22 · "Should we add a semantic cache in front of the LLM?"</b></summary>

**Initial Prompt.** Many users ask similar questions.

**L5 Answer.** "Yes, cache by embedding similarity above 0.9."

**Why L5 Fails in Production.** Similar questions can need different answers. In 03.1, same-intent queries with different dates ("PTO in March" vs "PTO in April") hit at cosine 0.93 and would have served wrong answers.

**L7 Principal Defense.** "Exact-match first: normalized text → answer. It's safe, and in 07.1's simulation it cut cost 29% at 30% repeat traffic. A semantic cache only with a measured **wrong-hit rate**: label a sample of would-be hits, and add slot checks (dates, numbers, entities must match; we normalized 'four' → '4' and still found wrong PTO-date hits). Choose the similarity threshold from that precision, not a round number. For scale, IVF with nprobe 16 reached 0.999 recall at 3.7× less work than brute force (03.1). And never cache answers that depend on user state, or fallbacks served during an outage."

**Bar-Raiser Follow-ups.**
- *"TTL?"* By answer type. Policy answers expire on policy change, and account-state answers shouldn't be cached at all.

</details>

<details><summary><b>Q23 · "Our cascade fixed p50 latency but not p99. Why?"</b></summary>

**Initial Prompt.** p50 ~2 ms, p99 still ~1.8 s.

**L5 Answer.** "Scale up the LLM service."

**Why L5 Fails in Production.** The p99 is the provider's tail, and a mixture's quantiles follow its slow component.

**L7 Principal Defense.** "Latency is a mixture: P(latency > t) = s·P(LLM > t) for deferral share s. So the mixture's p99 is the LLM's (1 − 0.01/s) quantile. At s = 0.35 with a lognormal LLM (median 700 ms, σ 0.5), that's ~1,810 ms (we measured 1,786 vs 2,216 for LLM-only). Fixes: a deadline with a fallback (p99 becomes the deadline), a faster tier on the deferral path, or hedged requests. Resilience matters too: in a simulated 2-minute outage, a circuit breaker cut requests stuck for the full 1.5 s deadline from 2,101 to 16."

**Bar-Raiser Follow-ups.**
- *"Cost of the deadline?"* You pay for abandoned calls: $24.14 vs $23.35 per 1M in the simulation.

</details>

<details><summary><b>Q24 · "How would you detect hallucinations in a RAG answer?"</b></summary>

**Initial Prompt.** Customer-facing answers about policies.

**L5 Answer.** "Ask the LLM if its answer is correct."

**Why L5 Fails in Production.** Self-verification shares the generator's blind spots, and verbalized confidence is poorly calibrated.

**L7 Principal Defense.** "Layered signals, each measured. (1) **Retrieval ceiling:** if Recall@k is zero for a query, the answer can't be grounded, so the zero-recall rate predicts a class of hallucinations upfront. (2) **Groundedness:** an NLI cross-encoder checks each answer claim against the retrieved chunks. It's a cheap classifier with a full operating curve. (3) **Uncertainty:** semantic entropy over sampled answers, clustered by meaning, scored AUROC 0.896 vs 0.843 for naive string entropy in 01.3. It costs k samples, so use it on the high-stakes slice. (4) A calibrated judge for correctness against references in offline evals. Each signal feeds a threshold chosen at the deployment base rate, with abstention as the action."

**Bar-Raiser Follow-ups.**
- *"Cheapest first step?"* Log the retrieved context and measure the zero-recall rate. It needs no new model.

</details>

<details><summary><b>Q25 · "Should we route between a small and a large LLM?"</b></summary>

**Initial Prompt.** A generative summarization feature on the largest model.

**L5 Answer.** "Keep the large model; quality matters most."

**Why L5 Fails in Production.** It ignores a 40× price spread and the fact that most requests are easy.

**L7 Principal Defense.** "At 630 tokens in and 10 out, list prices give $68 per 1M calls on Haiku 5.5, $1,360 on Sonnet 5.5 and $2,720 on Opus 5.5. A router that sends 80% of traffic to the small model cuts cost ~78% versus Opus-only, *if* quality holds. I'd build a post-hoc scorer (FrugalGPT-style): the small model answers, a cheap classifier or a validated judge decides whether to escalate, with a threshold tuned on a pairwise-judged eval set (position-swapped) at the deployment mix, plus a margin. Cost = small price + escalation share × large price. Then monitor judged quality by slice, because regressions concentrate in the hard slice."

**Bar-Raiser Follow-ups.**
- *"Router before generation instead?"* Cheaper on escalations but blind. RouteLLM-style routers trained on preference data are the option when latency rules out a second call.

</details>

### Area 6 · Production ML operations (Q26–Q30)

<details><summary><b>Q26 · "Offline AUC is 0.91, production is 0.65. What happened?"</b></summary>

**Initial Prompt.** An escalation-prediction model, days after launch.

**L5 Answer.** "Data drift since launch; retrain."

**Why L5 Fails in Production.** A gap that large on day one is almost always leakage, and retraining through the same pipeline reproduces it.

**L7 Principal Defense.** "Suspect the join. If each label got the entity's *latest* features, the training data included events after the label, such as post-escalation tickets. In 07.2 that gave 0.912 offline vs 0.653 served. A point-in-time join (feature event_time ≤ label_time: merge_asof, Feast's historical retrieval, or a SQL window) gave 0.657 both offline and served, and slightly *beat* the leaky model in production. I'd assert feature_ts ≤ label_ts in the pipeline, split by time, and ask for every high-importance feature when it gets written."

**Bar-Raiser Follow-ups.**
- *"Proof it's leakage?"* Rebuild the training set point-in-time and re-evaluate. If offline drops to the production level, it was leakage.

</details>

<details><summary><b>Q27 · "How do you catch training/serving skew?"</b></summary>

**Initial Prompt.** Two teams compute the same features in different services.

**L5 Answer.** "Write unit tests for the feature code."

**Why L5 Fails in Production.** Each implementation can pass its own tests and still disagree. In 07.2, a daily-bucket window mismatched an exact sliding window for 83 of 2,992 users.

**L7 Principal Defense.** "Three layers. (1) **Prevention:** one shared feature implementation, or train on logged serving features. (2) **Parity tests** between *independent* implementations, run continuously on a sample. (3) **Detection:** replay logged raw inputs through the offline code and diff per feature. That pinned all three of our bugs (ms vs s units, a 0-vs-median default, skipped lowercasing) to the exact feature and rows. Per-feature PSI is a cheaper screen, but it flagged the lowercasing bug only as 'moderate' (0.140), even though that bug cost more AUC (0.809 → 0.776) than the default bug did (→ 0.794, PSI 0.432). So set per-feature thresholds from noise, and use PSI to trigger replays."

**Bar-Raiser Follow-ups.**
- *"Embeddings?"* The model version is part of the feature definition. Query/index version mismatch is skew (Q30).

</details>

<details><summary><b>Q28 · "How do you set drift alert thresholds?"</b></summary>

**Initial Prompt.** PSI alerts fire daily and on-call ignores them.

**L5 Answer.** "Use the standard 0.1 / 0.25 thresholds."

**Why L5 Fails in Production.** PSI's no-drift distribution depends on window size and bins. At 200 samples and 50 bins its 99th percentile is 0.879, "major drift" from noise alone.

**L7 Principal Defense.** "Calibrate against the null. PSI_null ≈ χ²_{B−1}·(1/n + 1/m): with 10 bins at n = 1,000 the 99th percentile is 0.022, matching our simulation exactly. Alert at a multiple of it, keep ≥ 10 expected samples per bin, and size windows to the decision (hourly for pipeline bugs, daily or weekly for retraining). Alert on effect sizes, not p-values: KS gave p = 1e-26 for a 0.02-sd shift at a million samples. A PSI of 0.25 corresponds to a ~0.5-sd mean shift. Prefer model-native signals: the router's confidence PSI went 0.011 → 0.168 → 0.617 as OOS traffic rose 0% → 20% → 40%."

**Bar-Raiser Follow-ups.**
- *"Gradual drift?"* CUSUM-style sequential detection accumulates small excesses that fixed thresholds miss.

</details>

<details><summary><b>Q29 · "Design automated retraining for the router."</b></summary>

**Initial Prompt.** The team wants retraining without humans in the loop.

**L5 Answer.** "Retrain nightly on new labels and deploy if training succeeds."

**Why L5 Fails in Production.** Without a promotion gate, a broken pipeline deploys itself. Without a fixed-reference monitor, nobody notices.

**L7 Principal Defense.** "In 07.3's 16-week simulation, a retraining job used the wrong encoder version at weeks 8–9. Ungated policies all deployed the broken model (~10% accuracy). The drift-triggered one then reset its reference to the broken model's own outputs and stayed broken for 7 weeks: mean 0.480, worse than never retraining (0.686). With a gate (a golden set scored through the *serving* path, allowing at most a 0.5-point loss), weekly retraining averaged 0.822 and rejected both broken candidates. So: trigger (schedule + drift) → point-in-time snapshot → train → golden-set gate → paired champion comparison → shadow → canary. Reset drift references only after promotion, and keep one monitor with a fixed reference."

**Bar-Raiser Follow-ups.**
- *"What limits recovery?"* Labels. New intents need labelled examples. Drift is detectable without labels, but only fixable with them.

</details>

<details><summary><b>Q30 · "We upgraded the embedding model and search broke. Walk me through the migration you should have done."</b></summary>

**Initial Prompt.** The query service was upgraded; the index wasn't.

**L5 Answer.** "Roll back and re-try later."

**Why L5 Fails in Production.** A rollback fixes today, but without a migration plan the next upgrade breaks the same way. Query and document vectors must come from the same model version.

**L7 Principal Defense.** "Embeddings are features, and the model version is part of their definition (07.2 §1.7). Mixing versions makes cosine meaningless: the analogous pipeline bug in 07.3 dropped accuracy to ~10%. The migration: (1) re-embed the corpus with v2 into a new index; (2) dual-read, scoring the eval set on both indexes with a paired comparison of Recall@k and nDCG; (3) re-derive thresholds, since cosine scales differ between models (01.1: a re-used threshold dropped precision 0.95 → 0.25); (4) re-baseline the drift references; (5) cut over with a canary, keeping v1 for rollback. Store (model ID, revision, normalization, dtype, dimension) with the index and assert it at query time, so a mismatch fails loudly."

**Bar-Raiser Follow-ups.**
- *"Can you avoid re-embedding?"* A learned linear map between spaces can bridge temporarily (01.2's Procrustes bridge recovered 0.936 recall on a rotation). Measure it, and treat it as a stopgap.

</details>

---

## 7. Invariants Checklist

- [ ] Every defense names a number, the condition under which the design fails, and how you'd detect it.
- [ ] Numbers are attributed honestly: your production results, or "in a benchmark I ran", never borrowed or simulated numbers presented as production.
- [ ] The napkin-math table (§1.8) can be reproduced from memory; the key (§3.1) re-checks it.
- [ ] Every design answer follows clarify → baseline → design → failure modes → measurement.
- [ ] "Would you use an LLM for this?" is answered with the label space, volume, latency, cheap-baseline score and a hybrid design.
- [ ] Chains are practised out loud before reading the defense; misses are logged and tagged by area.

---

## 8. References

1. This KB, Folders 01–07: each defense cites the file and section where its numbers were measured.
2. A. Ng, *Machine Learning Yearning* (error analysis, bias/variance, dev/test sets, ceiling analysis). https://www.deeplearning.ai/resources/
3. A. Ng, *Improve Agentic Performance with Evals and Error Analysis, Part 1*, The Batch, 2025-10-15. https://www.deeplearning.ai/the-batch/improve-agentic-performance-with-evals-and-error-analysis-part-1/
4. L. Zheng et al., *Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena*, NeurIPS 2023. https://arxiv.org/abs/2306.05685
5. L. Chen, M. Zaharia, J. Zou, *FrugalGPT*, 2023. https://arxiv.org/abs/2305.05176
6. I. Ong et al., *RouteLLM: Learning to Route LLMs with Preference Data*, 2024. https://arxiv.org/abs/2406.18665
7. S. Farquhar, J. Kossen, L. Kuhn, Y. Gal, *Detecting Hallucinations in Large Language Models Using Semantic Entropy*, Nature 630, 2024. https://doi.org/10.1038/s41586-024-07421-0
8. T. Dao et al., *FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness*, NeurIPS 2022. https://arxiv.org/abs/2205.14135
9. W. Kwon et al., *Efficient Memory Management for Large Language Model Serving with PagedAttention* (vLLM), SOSP 2023. https://arxiv.org/abs/2309.06180
10. J. Ainslie et al., *GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints*, EMNLP 2023. https://arxiv.org/abs/2305.13245
11. R. Kohavi, D. Tang, Y. Xu, *Trustworthy Online Controlled Experiments*, Cambridge University Press, 2020. https://doi.org/10.1017/9781108653985
12. Anthropic, *Pricing* (Claude list prices used in the napkin math). https://www.anthropic.com/pricing
