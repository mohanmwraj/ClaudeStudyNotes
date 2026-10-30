# 06.4 · A/B Testing, Hypothesis Testing, p-Values, Bootstrapping & Multi-Armed Bandits

> **Folder 06 · Evaluation Statistics, Error Analysis & LLM-as-a-Judge**
> **Measured on:** NumPy 2.5.4 and SciPy 1.18.1 (closed-form tests checked by simulation), real per-query SciFact nDCG from 06.2 (paired bootstrap and permutation tests), and a seeded 3-arm bandit simulation. Windows 11.
> **Design sources:** Kohavi, Tang & Xu (*Trustworthy Online Controlled Experiments*, 2020), Deng et al. (CUPED, 2013), Johari et al. (always-valid p-values, 2017), Efron & Tibshirani (the bootstrap, 1993), Benjamini & Hochberg (FDR, 1995), Auer et al. (UCB1, 2002), Russo et al. (Thompson sampling tutorial, 2018), Li et al. (contextual bandits, 2010). Full list in §8.

---

## 0. Orientation: Every Eval Delta Is a Statistical Claim

"The new prompt is 2 points better." "Hybrid beats BM25." "Variant B converts more." Each is a claim about a population, made from a sample, and each can be wrong in ways a backend engineer already understands: you're comparing noisy measurements. This file gives you the tools for **offline** comparisons (paired bootstrap and permutation tests over eval items) and **online** comparisons (A/B tests with power, peeking and variance reduction), then the adaptive alternative (bandits). Measured results:

- **Sample size scales as 1/MDE².** Detecting +1 point on a 10% conversion rate needs **14,313 users per arm**; +0.5 points needs 56,886; +0.2 points needs 354,139. The simulated power at the designed n is 0.785 (designed 0.80).
- **Peeking breaks the test.** Checking after every 500 users per arm and stopping at the first p < 0.05 gives a **24.2% false-positive rate**, not 5%. Twenty A/A tests are enough to fool yourself.
- **CUPED shrinks variance to 22%.** Subtracting the pre-period covariate cut the standard error from 0.286 to 0.134. The same true effect (+0.6) goes from z = 1.92 (not significant) to z = 5.35.
- **Pairing is free power offline.** On SciFact, hybrid − BM25 = +0.0545 nDCG@10. The paired 95% CI is [+0.030, +0.079], width 0.049. Treated as unpaired, the CI is [−0.006, +0.114], width 0.120, which would wrongly call the result inconclusive.
- **Bandits trade clarity for reward.** Over 20,000 requests across 3 prompt variants (true success rates 0.10/0.12/0.11), Thompson sampling lost **60.6** expected successes vs 200 for a fixed 3-way split, and sent 76% of traffic to the best arm.

### The backend-engineer bridge

| You already know | Experimentation equivalent |
|---|---|
| Canary vs baseline fleet comparison | **A/B test**: randomized control vs treatment |
| "Error rate looks higher on the canary": is it noise? | **Hypothesis test**: is the difference larger than chance? |
| Load-testing until you can see a 1% latency regression | **Power and sample size** |
| Re-running a flaky test until it passes | **Peeking / optional stopping** |
| Comparing the same requests replayed on two builds | **Paired comparison** (offline eval on the same items) |
| Normalizing a metric by a per-host baseline | **CUPED**: subtract the pre-period covariate |
| Gradually shifting traffic toward the healthier backend | **Multi-armed bandit** |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Hypothesis testing: null, p-value, α, power, and what a p-value is not | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 The two-proportion z-test and sample size: n ∝ 1/MDE² | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Offline comparisons: paired bootstrap and sign-flip permutation tests | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 A/A tests: p-values are uniform under the null | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Peeking and sequential testing | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Variance reduction with CUPED | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Multiple comparisons: Bonferroni, Holm, Benjamini–Hochberg | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Randomization units, interference, and sample-ratio mismatch | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 What's different when A/B testing LLM features | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 Multi-armed bandits: ε-greedy, UCB1, Thompson sampling | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Contextual bandits and off-policy evaluation | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.12 Bayesian A/B analysis | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.13 SPRT optimality and regret lower bounds (Lai–Robbins) | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Hypothesis testing: null, p-value, α, power, and what a p-value is not `[MUST-KNOW: Core AI Engineer Edge]`

The setup: a **null hypothesis** H₀ (no difference between A and B), a **test statistic** T (e.g. the difference in means divided by its standard error), and the distribution of T *if H₀ were true*.

```text
p-value = P( |T| ≥ |t_observed|  given H₀ )          "how surprising is this data if there's no effect?"
α       = the false-positive rate you accept           (reject H₀ when p < α)
power   = P( reject H₀ given a true effect of size δ )  = 1 − β
```

What a p-value is **not**:

- **Not P(H₀ is true).** p = 0.03 doesn't mean a 3% chance of no effect. That needs a prior (§1.12).
- **Not the size of the effect.** At n = 10⁶ a negligible effect gives a tiny p (07.3's KS demo: a 0.02 sd shift is "significant" at a million samples). Always report the effect and its CI.
- **Not a measure of replicability on its own.** A result with p = 0.04 at low power is likely to be an overestimate if it's real ("winner's curse"), and ~a coin flip to replicate.

> **The operational rule:** decide α, the minimum detectable effect (MDE) and power *before* collecting data, run to the planned sample, and report the effect with a confidence interval. Everything else in this file is about the ways teams break that rule.

### 1.2 The two-proportion z-test and sample size: n ∝ 1/MDE² `[MUST-KNOW: Core AI Engineer Edge]`

For conversion-type metrics (success rate, thumbs-up rate, escalation rate):

```text
z = (p̂_B − p̂_A) / √( p̂(1 − p̂)(1/n_A + 1/n_B) )        p̂ = pooled rate

n per arm = [ z_{1−α/2}·√(2p(1−p)) + z_{1−β}·√(p(1−p) + p₂(1−p₂)) ]² / δ²       p₂ = p + δ
```

The δ² in the denominator is the whole story: **halving the effect you want to detect quadruples the sample.** From listing §3.1, section 1 (α = 0.05 two-sided, power 0.8):

| Baseline | MDE (absolute) | Relative | n per arm |
|---|---|---|---|
| 0.100 | 0.010 | 10% | 14,313 |
| 0.100 | 0.005 | 5% | 56,886 |
| 0.100 | 0.002 | 2% | 354,139 |
| 0.020 | 0.002 | 10% | 78,040 |

The same *relative* lift on a rarer metric needs more users: 10% relative at a 2% baseline needs 5.5× the sample of 10% relative at a 10% baseline. That matters for LLM features whose key metric is rare (escalation to a human, a safety flag, a complaint). The listing then *simulates* 4,000 experiments at n = 14,313 with a true +0.01 effect: **power 0.785**, matching the design value of 0.80 within simulation error. Do this check whenever you hand-roll a power calculation.

**Napkin math for a product review:** n per arm ≈ 16·σ²/δ² (from (1.96 + 0.84)² ≈ 7.85, times 2 for two arms' variance). For a rate p, σ² = p(1−p). At p = 0.1 and δ = 0.01: 16 × 0.09 / 0.0001 = 14,400. Close to 14,313, and good enough to say "we need ~15k per arm, so ~3 days at our traffic" in a meeting.

### 1.3 Offline comparisons: paired bootstrap and sign-flip permutation tests `[MUST-KNOW: Core AI Engineer Edge]`

Offline evals compare two systems on **the same items**. That's a paired design, and ignoring the pairing throws away most of the statistical power, because item difficulty is usually the largest source of variance.

**Paired bootstrap** (Efron): let dᵢ = score_B(qᵢ) − score_A(qᵢ) for each of n items. Resample n items with replacement B times, take the mean of d each time, and use the 2.5th and 97.5th percentiles as the 95% CI.

**Sign-flip permutation test:** under H₀ (the systems are exchangeable), each dᵢ is equally likely to be +dᵢ or −dᵢ. Flip signs at random B times and count how often |mean| ≥ |observed mean|. That fraction, with the +1 correction p = (1 + count)/(B + 1), is an exact-in-the-limit p-value with no normality assumption.

From listing §3.2, on 300 SciFact claims (per-query nDCG@10 from 06.2):

| Comparison | Mean Δ | 95% paired CI | Permutation p |
|---|---|---|---|
| Hybrid − BM25 | +0.0545 | [+0.0302, +0.0792] | ≤ 0.0001 (none of 10,000 flips as extreme) |
| Hybrid − dense | +0.0806 | [+0.0548, +0.1069] | ≤ 0.0001 |
| BM25 − dense | +0.0261 | [−0.0124, +0.0641] | 0.1845 |

**Paired vs unpaired, same data:** the hybrid − BM25 CI is **0.049 wide paired vs 0.120 unpaired**, and the unpaired interval crosses zero ([−0.006, +0.114]). An engineer who bootstraps each system's mean separately and checks whether the intervals overlap would wrongly call this inconclusive. Pairing removes query difficulty: a query both systems fail costs both equally and contributes 0 to dᵢ.

```text
per-query nDCG@10
1.0 ┤ ●──●     ●──●         paired: look at each line's slope (dᵢ)
    │      ●──●      ●──●   unpaired: compare the clouds of left vs right dots,
0.5 ┤ ●──●       ●──●         whose spread is dominated by query difficulty
    │   ●──●  ●──●
0.0 ┼ ●──●  ●──●            (a query both fail adds 0 to the paired difference)
      A  B
```

Two details matter in practice. **Report "p ≤ 1/(B+1)", not "p = 0"**, when no permutation is as extreme. And **the unit of resampling is the independent unit**: queries, not query-document pairs; conversations, not turns. Otherwise the CI is too narrow.

### 1.4 A/A tests: p-values are uniform under the null `[MUST-KNOW: Core AI Engineer Edge]`

If H₀ is true and the test is correct, the p-value is **uniformly distributed** on [0, 1]: P(p < x) = x. Listing §3.1, section 2, runs 20,000 A/A experiments: the fraction with p < 0.05 is **0.0496**, and the fractions below 0.1/0.3/0.5/0.7/0.9 are **0.10/0.31/0.50/0.71/0.91**. Exactly uniform, within noise.

Running A/A tests on your **real** experimentation pipeline is the standard health check (Kohavi et al.). If 15% of your A/A tests are "significant", the assignment, logging or analysis is broken: non-random bucketing, a cache shared across arms, the wrong variance formula for clustered data. Fix that before trusting any A/B result.

### 1.5 Peeking and sequential testing `[MUST-KNOW: Core AI Engineer Edge]`

A fixed-horizon test controls the false-positive rate only if you look **once**, at the planned n. Looking repeatedly and stopping at the first p < 0.05 gives the null hypothesis many chances to look significant. From listing §3.1, section 3 (20 looks, every 500 users per arm, no true effect, 4,000 simulated experiments):

| Policy | False-positive rate |
|---|---|
| One look at the end | 0.050 (by design) |
| Stop at the first look with p < 0.05 | **0.242** |
| Stop at the first look with p < 0.05/20 (Bonferroni) | 0.016 (valid but conservative) |

Correct ways to look early:

- **Group-sequential designs** with α-spending (O'Brien–Fleming, Pocock): pre-plan K looks with stricter thresholds early. O'Brien–Fleming spends almost nothing early, so the final look is close to the fixed-horizon threshold.
- **Always-valid inference** (Johari et al., mSPRT): p-values and CIs that stay valid under continuous monitoring. Many commercial experimentation platforms use variants of this. ⚠ Check your platform's documentation for its exact method.
- **A guardrail-only early stop.** Allow stopping early for *harm* (latency, errors, safety flags) with a strict threshold, but not for success.

### 1.6 Variance reduction with CUPED `[MUST-KNOW: Core AI Engineer Edge]`

CUPED (Deng et al., 2013, from Microsoft's experimentation platform) uses a pre-experiment covariate X that is correlated with the outcome Y but unaffected by the treatment (e.g. the user's activity last month):

```text
Y_cuped = Y − θ·(X − mean(X))         θ = Cov(X, Y) / Var(X)     (the OLS slope)
Var(Y_cuped) = Var(Y)·(1 − ρ²)         ρ = corr(X, Y)
```

Because X is measured *before* randomization, it's independent of the assignment, so the adjusted difference in means is still unbiased. Only the noise shrinks. From listing §3.1, section 4 (true effect +0.6):

| Estimator | Effect | Std error | z |
|---|---|---|---|
| Raw metric | +0.549 | 0.286 | 1.92 |
| CUPED-adjusted | +0.716 | 0.134 | 5.35 |

Remaining variance is 1 − ρ² = **0.220** of the raw, so **the same power with ~22% of the users**, or detecting a ~2.1× smaller effect with the same users (√(1/0.22) ≈ 2.1). Both estimates are unbiased draws around +0.6. The CUPED one is just much less noisy. For LLM features, good covariates are the user's pre-period usage, their pre-period satisfaction rate, or the query-difficulty score of their typical queries.

### 1.7 Multiple comparisons: Bonferroni, Holm, Benjamini–Hochberg `[MUST-KNOW: Core AI Engineer Edge]`

Test 20 metrics at α = 0.05 with no true effects and you expect one "significant" result. With m tests:

- **Bonferroni:** use α/m. It controls the family-wise error rate (FWER), and it's conservative.
- **Holm:** sort the p-values ascending and compare the k-th to α/(m − k + 1), stopping at the first failure. Same FWER guarantee, uniformly more powerful.
- **Benjamini–Hochberg:** find the largest k with p₍ₖ₎ ≤ (k/m)·α, and reject the first k. It controls the false discovery rate (the expected share of false positives among discoveries). Use it for exploratory metric sets and slice analyses.

The structural fix beats any correction: **pre-register one primary metric** (06.1 §4.1's optimizing metric), a small set of guardrail metrics with harm-only thresholds, and treat everything else as exploratory, to be confirmed in a follow-up test.

### 1.8 Randomization units, interference, and sample-ratio mismatch `[MUST-KNOW: Core AI Engineer Edge]`

- **The randomization unit is the analysis unit.** Randomize by user and the user is the independent unit. Analysing per request treats correlated requests as independent and understates the variance. Use the delta method or a user-level bootstrap.
- **Interference.** If treatment users affect control users (a shared cache, a shared semantic cache of LLM answers, marketplace effects, a rate limit), the arms aren't independent. Isolate shared state per arm, or randomize at a coarser unit (region, tenant).
- **Sample-ratio mismatch (SRM).** If a 50/50 test has 50,812 vs 49,188 users, a χ² test gives p ≈ 3e-7: something in assignment or logging is broken (bots filtered in one arm, a crash before logging in treatment). An SRM invalidates the result, whatever the metric shows. Check it automatically on every experiment.

### 1.9 What's different when A/B testing LLM features `[MUST-KNOW: Core AI Engineer Edge]`

| Issue | Why it matters for LLM features | Mitigation |
|---|---|---|
| Non-determinism | The same input gives different outputs, which adds within-unit variance | Larger n, or average several samples per item offline; fix model and prompt versions per arm |
| Cost and latency are first-class metrics | A "better" variant may cost 3× | Guardrail metrics: $/request, p95 latency, tokens per conversation |
| Judged metrics | Quality is measured by an LLM judge with its own error and biases | Validated judge (06.3); pairwise judging on matched inputs; human audit of flips |
| Novelty and learning effects | Users explore a new assistant, then settle | Run long enough (≥ 1–2 weekly cycles); look at the effect by days since exposure |
| Rare key outcomes | Escalations and safety flags are rare (n ∝ 1/p for rare rates) | CUPED, longer tests, or offline evals as the primary evidence |
| Provider model updates mid-test | A hosted model version changes under one arm | Pin model versions; log the model ID per request |

**Offline first, online to confirm.** For most LLM changes, a paired offline eval (§1.3) on a few hundred items resolves the quality question at near-zero cost. The online test confirms user-level outcomes and cost, with a power calculation based on the effect the offline eval predicted.

### 1.10 Multi-armed bandits: ε-greedy, UCB1, Thompson sampling `[GOOD-TO-KNOW: Architectural Literacy]`

An A/B test spends a fixed share of traffic on every arm until the end. A **bandit** shifts traffic toward better arms *during* the experiment, trading statistical clarity for reward. **Regret** = (best arm's expected reward − the chosen arm's) summed over requests.

```text
ε-greedy : with probability ε explore uniformly, else exploit argmax(mean)
UCB1     : choose argmax( mean_a + √(2 ln t / n_a) )                  optimism in the face of uncertainty
Thompson : sample θ_a ~ Beta(1 + successes_a, 1 + failures_a), choose argmax θ_a   (probability matching)
```

From listing §3.2, section 3 (3 prompt variants with true success rates 0.10/0.12/0.11, 20,000 requests, 50 runs):

| Policy | Mean regret | Share of traffic to the best arm |
|---|---|---|
| Fixed A/B/C split | 200.0 | 0.333 |
| UCB1 | 150.9 | 0.467 |
| ε-greedy (ε = 0.1) | 81.0 | 0.679 |
| Thompson sampling | **60.6** | **0.761** |

UCB1's exploration bonus √(2 ln t / n) is large compared with gaps of 1–2 points, so it keeps exploring for most of the horizon. That's a known weakness of UCB1 on small gaps and short horizons. Thompson sampling adapts its exploration to the posterior's actual uncertainty and wins here, consistent with the empirical literature (Chapelle & Li, 2011).

**When to use a bandit:** many variants, short-lived decisions (headline or prompt variants, promotions), when the cost of showing a bad variant is high, or for *continuous* optimization (routing between models by measured success). **When not to:** when you need an unbiased estimate of the effect for a decision or a report, when the metric is delayed (bandits need fast rewards), or when the reward is non-stationary and you haven't added discounting.

### 1.11 Contextual bandits and off-policy evaluation `[GOOD-TO-KNOW: Architectural Literacy]`

A **contextual bandit** picks an arm given features of the request: "for this query type, which model or prompt?" That's literally the model-routing problem of 07.1, with exploration. LinUCB (Li et al., 2010) and Thompson sampling with a linear or GBDT reward model are the standard approaches.

**Off-policy evaluation** asks how a *new* routing policy would have done, using logs collected under the old one. Inverse propensity scoring: V̂ = (1/n) Σ rᵢ · π_new(aᵢ|xᵢ) / π_log(aᵢ|xᵢ). It's unbiased only if the logging policy **randomized** (every action had a known, non-zero propensity), so **log the propensities**. A deterministic router (always the cheapest confident model) can't be evaluated off-policy. Add a little exploration (1–5%) if you want this option later.

### 1.12 Bayesian A/B analysis `[GOOD-TO-KNOW: Architectural Literacy]`

With Beta priors on each arm's rate, the posterior is Beta(1 + successes, 1 + failures), and you can report **P(B > A | data)** and the **expected loss** of choosing B, which is what product managers usually think a p-value means. It doesn't make peeking free: optional stopping still affects frequentist error rates. And the prior matters for small samples. It's a good presentation layer, and Thompson sampling (§1.10) is its adaptive version.

### 1.13 SPRT optimality and regret lower bounds (Lai–Robbins) `[SKIP: Academic/Research Only]`

Wald's sequential probability ratio test minimizes the expected sample size for given error rates. Lai & Robbins showed that any consistent bandit policy has regret growing at least logarithmically in T, with a constant set by the KL divergence between arms. Both explain *why* the practical tools work. You don't need the proofs to use them correctly.

---

## 2. Where It Beats an LLM in Production

**1. Statistics replace opinions, including the LLM's.** "Ask the model which prompt is better" is not an experiment. A paired bootstrap over 300 eval items (§1.3) runs in under a second, gives an interval, and can't be swayed by answer length or position (06.3). Every "beats an LLM" claim elsewhere in this KB (a 2 ms router, a GBDT re-ranker, a cascade that cuts cost 90%) is only credible because it was measured with a paired comparison against the LLM baseline on the same items.

**2. Bandits are cheap online learners for model routing.** A Thompson-sampling allocator over "small model / medium model / large model" per query cluster is a few lines of code and microseconds per decision. It learns where the cheap model is good enough from live rewards (thumbs-up, resolution, no escalation), without an LLM in the decision loop. Contextual bandits are the online-learning version of the cascade in 07.1.

**3. Variance reduction is cheaper than a bigger model.** CUPED gave the same power with 22% of the users (§1.6). If your experiment can't detect the effect of a prompt change, a better estimator is usually cheaper than a longer test, and much cheaper than "just ship the bigger model to be safe".

---

## 3. Production Code Blueprint

### 3.1 Power, A/A uniformity, peeking, and CUPED

```python
"""ab_testing_power_and_peeking.py - the statistics of an online A/B test, by formula and by simulation.

  1. Two-proportion z-test; sample size for a target minimum detectable effect (MDE) and power.
  2. Under the null (A/A tests), p-values are uniform: 5% of tests are "significant" at alpha = 0.05.
  3. Peeking: checking after every batch and stopping at the first p < 0.05 inflates false positives.
  4. CUPED: subtracting a pre-period covariate cuts variance and the sample you need.
"""
import math

import numpy as np
from scipy import stats

rng = np.random.default_rng(191)


def z_test(x1, n1, x2, n2):
    p1, p2, p = x1 / n1, x2 / n2, (x1 + x2) / (n1 + n2)
    z = (p2 - p1) / math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2))
    return z, 2 * (1 - stats.norm.cdf(abs(z)))


def n_per_arm(p, mde, alpha=0.05, power=0.8):
    za, zb = stats.norm.ppf(1 - alpha / 2), stats.norm.ppf(power)
    p2 = p + mde
    return math.ceil((za * math.sqrt(2 * p * (1 - p)) + zb * math.sqrt(p * (1 - p) + p2 * (1 - p2))) ** 2 / mde ** 2)


print("== 1. sample size per arm (alpha 0.05 two-sided, power 0.8) ==")
print(f"{'baseline':>8} {'MDE (abs)':>9} {'relative':>8} {'n per arm':>10}")
for p, mde in ((0.10, 0.01), (0.10, 0.005), (0.10, 0.002), (0.02, 0.002)):
    print(f"{p:>8.3f} {mde:>9.3f} {mde / p:>8.0%} {n_per_arm(p, mde):>10,}")
print("halving the MDE quadruples the sample: n ~ 1/MDE^2")
n = n_per_arm(0.10, 0.01)
hits = sum(z_test(rng.binomial(n, 0.10), n, rng.binomial(n, 0.11), n)[1] < 0.05 for _ in range(4000))
print(f"simulated power at that n with a true +0.01 effect: {hits / 4000:.3f} (designed 0.80)")
assert abs(hits / 4000 - 0.8) < 0.03

print("\n== 2. A/A tests: 20,000 experiments with NO true difference ==")
pv = np.array([z_test(rng.binomial(5000, 0.1), 5000, rng.binomial(5000, 0.1), 5000)[1] for _ in range(20_000)])
print(f"fraction p < 0.05: {np.mean(pv < 0.05):.4f}; fraction of p below 0.1 / 0.3 / 0.5 / 0.7 / 0.9 (uniform => the same numbers): " + " ".join(f"{np.mean(pv < q):.2f}" for q in (0.1, 0.3, 0.5, 0.7, 0.9)))
assert abs(np.mean(pv < 0.05) - 0.05) < 0.006

print("\n== 3. peeking: look after every 500 users per arm, up to 20 looks, stop at the first p < 0.05 ==")
fp_peek, fp_bonf = 0, 0
trials = 4000
for _ in range(trials):
    a = rng.random((20, 500)) < 0.1
    b = rng.random((20, 500)) < 0.1
    ca, cb = np.cumsum(a.sum(1)), np.cumsum(b.sum(1))
    ns = 500 * np.arange(1, 21)
    ps = [z_test(ca[i], ns[i], cb[i], ns[i])[1] for i in range(20)]
    fp_peek += any(p < 0.05 for p in ps)
    fp_bonf += any(p < 0.05 / 20 for p in ps)
print(f"false-positive rate: one look at the end 0.050 (by design) | peeking every look {fp_peek / trials:.3f} | "
      f"peeking with Bonferroni alpha/20 {fp_bonf / trials:.3f}")
assert fp_peek / trials > 0.15

print("\n== 4. CUPED: adjust a continuous metric by its pre-experiment value ==")
m = 4000
pre = rng.gamma(2.0, 10.0, (2, m))                                  # e.g. last month's queries per user
post = 0.8 * pre + rng.normal(0, 6, (2, m))
post[1] += 0.6                                                      # true treatment effect +0.6
theta = np.cov(np.r_[pre[0], pre[1]], np.r_[post[0], post[1]])[0, 1] / np.var(np.r_[pre[0], pre[1]])
adj = post - theta * (pre - pre.mean())
for name, y in (("raw metric", post), ("CUPED-adjusted", adj)):
    diff = y[1].mean() - y[0].mean()
    se = math.sqrt(y[0].var() / m + y[1].var() / m)
    print(f"{name:15s} effect {diff:+.3f}, std error {se:.3f}, z {diff / se:.2f}")
r2 = np.corrcoef(np.r_[pre[0], pre[1]], np.r_[post[0], post[1]])[0, 1] ** 2
print(f"true effect +0.600; remaining variance = 1 - rho^2 = {1 - r2:.3f} of the raw variance -> the same power with ~{1 - r2:.0%} of the users")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. sample size per arm (alpha 0.05 two-sided, power 0.8) ==
baseline MDE (abs) relative  n per arm
   0.100     0.010      10%     14,313
   0.100     0.005       5%     56,886
   0.100     0.002       2%    354,139
   0.020     0.002      10%     78,040
halving the MDE quadruples the sample: n ~ 1/MDE^2
simulated power at that n with a true +0.01 effect: 0.785 (designed 0.80)

== 2. A/A tests: 20,000 experiments with NO true difference ==
fraction p < 0.05: 0.0496; fraction of p below 0.1 / 0.3 / 0.5 / 0.7 / 0.9 (uniform => the same numbers): 0.10 0.31 0.50 0.71 0.91

== 3. peeking: look after every 500 users per arm, up to 20 looks, stop at the first p < 0.05 ==
false-positive rate: one look at the end 0.050 (by design) | peeking every look 0.242 | peeking with Bonferroni alpha/20 0.016

== 4. CUPED: adjust a continuous metric by its pre-experiment value ==
raw metric      effect +0.549, std error 0.286, z 1.92
CUPED-adjusted  effect +0.716, std error 0.134, z 5.35
true effect +0.600; remaining variance = 1 - rho^2 = 0.220 of the raw variance -> the same power with ~22% of the users

ALL ASSERTIONS PASSED
```

### 3.2 Paired bootstrap and permutation tests on real eval data, then bandits

```python
"""bootstrap_and_bandits.py - offline significance for eval deltas, and online allocation with bandits.

  1. Paired bootstrap CI and a paired permutation test for "hybrid beats BM25" on SciFact (real per-query nDCG).
  2. The same delta judged UNPAIRED: wider interval, weaker evidence.
  3. Bandits for choosing among 3 prompt variants (true success rates 0.10 / 0.12 / 0.11):
     epsilon-greedy vs UCB1 vs Thompson sampling: cumulative regret and traffic to the best arm.
"""
import json
import os

import numpy as np

DATA = os.environ["KB_DATA"]
R = np.load(os.path.join(DATA, "scifact_runs.npz"))
systems = json.load(open(os.path.join(DATA, "scifact_runs.json")))["systems"]
bm25, dense, hyb = R["ndcg_0"], R["ndcg_1"], R["ndcg_2"]
rng = np.random.default_rng(201)
B = 10_000

print("== 1. paired comparison on 300 claims (nDCG@10) ==")
for name, a, b in ((f"{systems[2]} - {systems[0]}", hyb, bm25), (f"{systems[2]} - {systems[1]}", hyb, dense),
                   (f"{systems[0]} - {systems[1]}", bm25, dense)):
    d = a - b
    idx = rng.integers(0, len(d), (B, len(d)))
    boot = d[idx].mean(1)
    lo, hi = np.percentile(boot, [2.5, 97.5])
    signs = rng.choice([-1, 1], (B, len(d)))                         # paired permutation: flip each query's sign
    perm = (signs * d).mean(1)
    p = (1 + np.sum(np.abs(perm) >= abs(d.mean()))) / (B + 1)
    ptxt = f"<= {1 / (B + 1):.4f} (none of {B:,} sign-flips as extreme)" if p <= 1 / (B + 1) else f"{p:.4f}"
    print(f"{name:32s} mean delta {d.mean():+.4f}  95% CI [{lo:+.4f}, {hi:+.4f}]  permutation p {ptxt}")

print("\n== 2. the same comparison, unpaired (pretending the queries were different) ==")
d_un = [hyb[rng.integers(0, 300, 300)].mean() - bm25[rng.integers(0, 300, 300)].mean() for _ in range(B)]
lo_u, hi_u = np.percentile(d_un, [2.5, 97.5])
d = hyb - bm25
lo_p, hi_p = np.percentile(d[rng.integers(0, 300, (B, 300))].mean(1), [2.5, 97.5])
print(f"hybrid - BM25: paired CI width {hi_p - lo_p:.4f} vs unpaired CI width {hi_u - lo_u:.4f} "
      f"(unpaired CI [{lo_u:+.4f}, {hi_u:+.4f}])")
print("pairing removes query difficulty, the largest source of variance in IR evals")
assert hi_p - lo_p < hi_u - lo_u

print("\n== 3. bandits: 3 prompt variants, 20,000 requests, 50 runs ==")
true_p = np.array([0.10, 0.12, 0.11])
T, RUNS = 20_000, 50


def run(policy, seed):
    r = np.random.default_rng(seed)
    succ, pulls = np.zeros(3), np.zeros(3)
    regret, best_pulls = 0.0, 0
    for t in range(1, T + 1):
        if policy == "epsilon-greedy (0.1)":
            arm = r.integers(3) if r.random() < 0.1 or pulls.min() == 0 else int(np.argmax(succ / pulls))
        elif policy == "UCB1":
            arm = t - 1 if t <= 3 else int(np.argmax(succ / pulls + np.sqrt(2 * np.log(t) / pulls)))
        else:                                                         # Thompson sampling with Beta(1, 1) priors
            arm = int(np.argmax(r.beta(1 + succ, 1 + pulls - succ)))
        reward = r.random() < true_p[arm]
        succ[arm] += reward
        pulls[arm] += 1
        regret += true_p.max() - true_p[arm]
        best_pulls += arm == 1
    return regret, best_pulls / T


print(f"{'policy':22s} {'mean regret':>11} {'share to best arm':>17}")
res = {}
for policy in ("epsilon-greedy (0.1)", "UCB1", "Thompson sampling"):
    out = np.array([run(policy, s) for s in range(RUNS)])
    res[policy] = out.mean(0)
    print(f"{policy:22s} {out[:, 0].mean():>11.1f} {out[:, 1].mean():>17.3f}")
print(f"{'fixed A/B/C split':22s} {T * (true_p.max() - true_p.mean()):>11.1f} {1 / 3:>17.3f}")
print("regret = expected successes lost vs always using the best arm; bandits trade statistical clarity for it")
assert res["Thompson sampling"][0] < res["epsilon-greedy (0.1)"][0]
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. paired comparison on 300 claims (nDCG@10) ==
hybrid 0.3/0.7 - BM25            mean delta +0.0545  95% CI [+0.0302, +0.0792]  permutation p <= 0.0001 (none of 10,000 sign-flips as extreme)
hybrid 0.3/0.7 - dense MiniLM    mean delta +0.0806  95% CI [+0.0548, +0.1069]  permutation p <= 0.0001 (none of 10,000 sign-flips as extreme)
BM25 - dense MiniLM              mean delta +0.0261  95% CI [-0.0124, +0.0641]  permutation p 0.1845

== 2. the same comparison, unpaired (pretending the queries were different) ==
hybrid - BM25: paired CI width 0.0487 vs unpaired CI width 0.1200 (unpaired CI [-0.0060, +0.1140])
pairing removes query difficulty, the largest source of variance in IR evals

== 3. bandits: 3 prompt variants, 20,000 requests, 50 runs ==
policy                 mean regret share to best arm
epsilon-greedy (0.1)          81.0             0.679
UCB1                         150.9             0.467
Thompson sampling             60.6             0.761
fixed A/B/C split            200.0             0.333
regret = expected successes lost vs always using the best arm; bandits trade statistical clarity for it

ALL ASSERTIONS PASSED
```

### 3.3 The experiment record a reviewer should demand

```python
@dataclass(frozen=True)
class ExperimentPlan:                      # written BEFORE launch, immutable afterwards
    hypothesis: str                        # "prompt v7 raises resolution rate"
    unit: str                              # "user" (= analysis unit; per-request needs the delta method)
    primary_metric: str                    # one optimizing metric
    guardrails: tuple                      # ("p95_latency_ms", "cost_per_request_usd", "safety_flag_rate")
    baseline_rate: float
    mde_abs: float                         # the smallest effect worth shipping
    alpha: float = 0.05
    power: float = 0.80
    n_per_arm: int = 0                     # from the formula in §1.2, checked by simulation
    looks: str = "fixed horizon"           # or "O'Brien-Fleming, 4 looks" / "mSPRT always-valid"
    covariate: str | None = None           # CUPED pre-period metric
    pinned_versions: tuple = ()            # model IDs and prompt hashes per arm

# at analysis time, in this order: SRM check -> A/A-validated pipeline -> primary metric with CI
# -> guardrails (harm-only) -> pre-registered slices with BH correction -> decision
```

---

## 4. The Andrew Ng Lens: Fast Offline Iteration, Then Rigorous Online Confirmation

### 4.1 Speed of iteration is the meta-metric

Ng's advice for AI teams is that the speed of the experiment loop determines the speed of progress. Statistically, that argues for **paired offline evals as the inner loop**: hundreds of items, a paired bootstrap, an answer in seconds (§1.3). Online A/B tests are the outer loop: slower, more expensive, and reserved for confirming user-level impact and cost on changes that already won offline.

### 4.2 The dev set must be big enough to see the improvements you care about

*Machine Learning Yearning* makes the point directly: the dev set must be large enough to detect the differences between the ideas you try. A 100-example dev set can't tell 90% from 91%. The paired-bootstrap width in §1.3 (±0.025 nDCG on 300 queries) tells you exactly what your set can resolve. If your ideas produce smaller deltas, grow the set before running more experiments. Otherwise you're picking winners at random.

### 4.3 Don't let the test set become a dev set

Every peek at the test set to choose between variants leaks information, exactly like peeking in §1.5. Ng's separation applies: iterate on dev, confirm once on test. In experimentation terms, that's the difference between exploratory and confirmatory analysis. Pre-register the confirmatory test, including the metric, n and α.

### 4.4 Bias/variance for the *measurement*

There's a bias/variance trade-off in the evaluation itself. LLM-judged metrics have **bias** (leniency, verbosity; 06.3), and small samples have **variance**. CUPED, pairing and larger samples reduce variance. Calibration against humans reduces bias. A trustworthy eval stack attacks both, and reports which one limits the decision.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | "Significant" wins that don't replicate | Stopped as soon as p < 0.05 | Peeking (24% false positives with 20 looks) | Fixed horizon, group-sequential, or always-valid tests | Planned n and looks in the experiment record |
| F2 | Test can't detect anything | Wide CIs at the end | Underpowered: no sample-size calculation | n from the formula; CUPED; longer test | Power check in the launch review |
| F3 | A/A tests are "significant" 15% of the time | Non-uniform A/A p-values | Broken assignment, logging, or variance formula | Fix the pipeline; per-user analysis | Scheduled A/A tests on the real pipeline |
| F4 | Result invalid despite a big effect | 50,812 vs 49,188 in a 50/50 split | Sample-ratio mismatch (bots, crashes, filters) | Find the asymmetry; re-run | Automatic SRM check, blocking |
| F5 | Offline delta "inconclusive" when it isn't | Unpaired CIs overlap | Ignoring the pairing over items | Paired bootstrap / sign-flip test | Eval harness only offers paired comparisons |
| F6 | One of 20 metrics "won" | No primary metric declared | Multiple comparisons | Holm / BH; confirm in a follow-up | One pre-registered primary metric |
| F7 | CI too narrow; effect flips next week | Requests analyzed as independent units | Unit of analysis ≠ unit of randomization | User-level bootstrap or delta method | Unit field in the experiment record |
| F8 | Treatment "wins" on quality, loses money | Only the quality metric checked | Missing cost and latency guardrails | Add $/request and p95 guardrails | Guardrails mandatory for LLM features |
| F9 | Bandit result can't be used to report the effect | Adaptive allocation biased the estimate | Using a bandit where inference was needed | A/B for decisions you must justify; bandit for continuous allocation | Choose bandit vs A/B in the plan |
| F10 | Off-policy estimate impossible | Router was deterministic | No propensities logged | Add 1–5% exploration; log propensities | Propensity logging in the router |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "What does p = 0.03 mean for our prompt experiment?"</b></summary>

**Initial Prompt.** A PM reads an experiment summary.

**L5 Answer.** "There's a 97% chance the new prompt is better."

**Why L5 Fails in Production.** That's P(H₁ | data), which a p-value doesn't give. It also says nothing about the size of the effect or whether it's worth shipping.

**L7 Principal Defense.** "It means: *if* the prompts were truly equivalent, data at least this extreme would occur 3% of the time. It's evidence against 'no difference', not a probability that the new prompt is better. For the decision I'd report the effect and its 95% CI, say +0.8 points [+0.1, +1.5], against the MDE we planned for, plus the guardrails (cost, latency). If the planned MDE was 1 point and the CI's lower end is 0.1, the result is 'probably positive, possibly too small to matter'. For a probability statement, I'd give a Bayesian P(B > A) next to it, with the prior stated."

**Bar-Raiser Follow-ups.**
- *"Was the test run to its planned n?"* If not (peeking), the 0.03 isn't valid. §3.1 shows 24% false positives with 20 looks.
- *"How many metrics were tested?"* If it's one of many, adjust (Holm/BH) or treat it as exploratory.

</details>

<details><summary><b>Q2 · "How long do we need to run the test?"</b></summary>

**Initial Prompt.** A team wants to detect a lift in task-success rate from 10% to 10.5%.

**L5 Answer.** "A week should be enough."

**Why L5 Fails in Production.** Duration comes from the required sample and the traffic, not from habit. +0.5 points on 10% needs 56,886 users per arm.

**L7 Principal Defense.** "n per arm = [z_{α/2}√(2p(1−p)) + z_β√(p(1−p) + p₂(1−p₂))]²/δ². For p = 0.10, δ = 0.005, α = 0.05, power 0.8: 56,886 per arm (napkin: 16σ²/δ² ≈ 57,600). At 20,000 eligible users a day split 50/50, that's ~6 days, rounded up to 2 full weekly cycles for day-of-week and novelty effects. With a pre-period covariate at ρ² ≈ 0.5, CUPED would halve it. If the business can only wait 3 days, the honest answer is that we can detect ~0.7 points, not 0.5, so is that useful?"

**Bar-Raiser Follow-ups.**
- *"Why whole weeks?"* Usage patterns vary by weekday. A test that runs Mon–Thu estimates a weekday effect.
- *"Can we stop early if it's clearly winning?"* Only with a sequential design planned up front.

</details>

<details><summary><b>Q3 · "Is hybrid search significantly better than BM25 on our 300-query eval?"</b></summary>

**Initial Prompt.** Offline eval results from 06.2.

**L5 Answer.** "Bootstrap each system's mean nDCG; the intervals overlap, so it's not significant."

**Why L5 Fails in Production.** The systems ran on the same queries. Unpaired intervals include query-difficulty variance that cancels in the difference. Here the unpaired CI is [−0.006, +0.114], but the paired one is [+0.030, +0.079].

**L7 Principal Defense.** "Paired. Compute dᵢ = nDCG_hybrid(qᵢ) − nDCG_BM25(qᵢ), bootstrap the mean of d over queries, and run a sign-flip permutation test. Result: +0.0545 [+0.030, +0.079], and none of 10,000 sign flips was as extreme (p ≤ 1e-4). The paired CI is 2.5× narrower because a query both systems fail adds nothing to d. Also, 'overlapping intervals' isn't even the right test for unpaired data: two 95% CIs can overlap while the difference is significant. Test the difference directly."

**Bar-Raiser Follow-ups.**
- *"And BM25 vs dense?"* +0.026 [−0.012, +0.064], p = 0.18: not established on 300 queries. Don't claim it either way.
- *"How would you get more power?"* More queries, especially from the slices where the systems disagree.

</details>

<details><summary><b>Q4 · "The dashboard shows treatment winning since day 2. Can we stop?"</b></summary>

**Initial Prompt.** A team checks the experiment daily.

**L5 Answer.** "Yes, it's been significant for 3 days in a row."

**Why L5 Fails in Production.** Daily peeking with a fixed-horizon test inflates false positives (24.2% with 20 looks in §3.1). "Significant three days in a row" doesn't fix it: the looks are correlated.

**L7 Principal Defense.** "Not on a fixed-horizon test. Every look is another chance for noise to cross the line. If early stopping matters, plan it: an O'Brien–Fleming design with a few looks (strict thresholds early, near-nominal at the end), or an always-valid test (mSPRT) if the platform supports it. Early stopping for *harm* on guardrails is different: that's a safety mechanism, set strictly, and I'd keep it. For this test I'd hold to the planned n, and in the meantime check for SRM and novelty (the effect by days since exposure)."

**Bar-Raiser Follow-ups.**
- *"Bonferroni across looks?"* Valid but wasteful (0.016 actual rate vs the 0.05 budget). α-spending uses the budget better.
- *"Bayesian monitoring?"* It reports P(B > A) continuously, but optional stopping still changes its frequentist error rates. Simulate the stopping rule before relying on it.

</details>

<details><summary><b>Q5 · "Our experiments never reach significance. What can we do besides running longer?"</b></summary>

**Initial Prompt.** LLM assistant experiments on a low-traffic enterprise product.

**L5 Answer.** "Lower α to 0.1."

**Why L5 Fails in Production.** It trades false positives for power instead of reducing noise, and it makes shipped "wins" less trustworthy.

**L7 Principal Defense.** "Reduce variance first. (1) **CUPED** with a pre-period covariate: in §3.1 it cut the variance to 22%, turning z = 1.92 into z = 5.35 for the same true effect. (2) **Pair offline**: most quality questions can be answered with a paired eval on the same items before any user sees the change. (3) **Better metrics**: per-user means instead of per-request, and metrics closer to the change (task success on the affected flow, not overall retention). (4) **Fewer, bigger bets**: test changes whose predicted effect clears the MDE we can afford. Only then trade α, and say so."

**Bar-Raiser Follow-ups.**
- *"Good covariates for an assistant?"* Pre-period usage, pre-period satisfaction, and the user's historical query difficulty.
- *"Stratified randomization?"* Yes, by tenant size or plan. It balances arms and reduces variance on small populations.

</details>

<details><summary><b>Q6 · "Should we A/B test our three prompt variants or use a bandit?"</b></summary>

**Initial Prompt.** Choosing a system prompt for a high-traffic summarization feature.

**L5 Answer.** "Bandits are strictly better; they waste less traffic."

**Why L5 Fails in Production.** They waste less *reward*, at the price of a biased effect estimate and no clean answer to "how much better is B?". And the result depends on the policy: UCB1 lost 151 successes vs Thompson's 61 in §3.2.

**L7 Principal Defense.** "It depends on what we need afterwards. If we must *justify* a decision with an effect size (a launch review, a cost-quality trade-off), I'd run an A/B/C test with a planned n. If the goal is just to *serve the best variant* and keep adapting (prompts change weekly, the feedback is fast and reliable), Thompson sampling: in the simulation it sent 76% of traffic to the best arm and lost 60.6 successes over 20,000 requests vs 200 for a fixed split. Practical guardrails: a minimum exploration floor, discounting for non-stationarity, propensity logging for off-policy analysis, and a fixed holdout slice so we can still estimate the effect."

**Bar-Raiser Follow-ups.**
- *"Delayed rewards (resolution after 24 h)?"* Bandits degrade with delay. Use a fast proxy reward, validated against the slow one.
- *"Why did UCB1 do worse?"* Its √(2 ln t/n) bonus is large next to 1–2-point gaps, so it over-explores at this horizon.

</details>

<details><summary><b>Q7 · "How do you A/B test a change that's evaluated by an LLM judge?"</b></summary>

**Initial Prompt.** Quality is measured by a Claude-based judge on sampled conversations.

**L5 Answer.** "Compare the judge's average score between arms."

**Why L5 Fails in Production.** The judge adds its own noise and bias. Biases that interact with the treatment (a longer-answer variant and a verbosity-biased judge) masquerade as effects.

**L7 Principal Defense.** "Treat the judge as part of the measurement system. (1) Use a validated judge (06.3) with its version pinned for the whole experiment. (2) Where possible, judge **pairs**: for sampled inputs, generate both arms' outputs and judge A vs B in both orders. That's a paired, position-corrected comparison with much less variance than two independent means. (3) Audit treatment-correlated nuisance variables: if the treatment changes length, compare within length bins. (4) Have humans label a sample of items where the arms differ, and estimate the effect with PPI or calibrated judge scores. (5) Primary user-level metrics (resolution, escalation) stay as the decision metric, with the judged metric as supporting evidence."

**Bar-Raiser Follow-ups.**
- *"Unit of analysis?"* Conversations sampled per user. Bootstrap by user if users contribute several.
- *"What if the judge and the treatment model are the same family?"* Use a different family or validate per-arm agreement (self-preference).

</details>

<details><summary><b>Q8 · "We tested 12 slices and two show significant regressions. Do we block the launch?"</b></summary>

**Initial Prompt.** A post-hoc slice analysis by language and region.

**L5 Answer.** "Yes, any significant regression blocks the launch."

**Why L5 Fails in Production.** With 12 slices at α = 0.05 and no true effects, the chance of at least one false positive is 1 − 0.95¹² ≈ 46%. Two "significant" slices may be noise.

**L7 Principal Defense.** "First, correct for multiplicity. Benjamini–Hochberg at FDR 10% across the 12 slices, or Holm if we need family-wise control. Second, look at effect sizes and CIs, not just p: a −0.3-point regression with a CI of [−0.5, −0.1] on a small slice might be acceptable, while −3 points on a key market isn't. Third, a regression in a slice we *pre-registered* as a guardrail (say, the top-5 languages) gets more weight than one found by fishing. If a slice survives correction and matters, block for that slice (ship elsewhere, or behind a flag) and run a targeted follow-up test."

**Bar-Raiser Follow-ups.**
- *"Why not just Bonferroni?"* It's valid but conservative across many slices. BH keeps more power when you expect some real effects.
- *"How to avoid this next time?"* Pre-register the guardrail slices and their thresholds in the experiment plan.

</details>

<details><summary><b>Q9 · "Our 50/50 test has 50,812 vs 49,188 users. Does it matter?"</b></summary>

**Initial Prompt.** A result looks great, but the arms are unequal.

**L5 Answer.** "1.6% imbalance is small; the result stands."

**Why L5 Fails in Production.** The imbalance is tiny relative to the expectation but statistically extreme (χ² = 26.4, p ≈ 3e-7). Something in assignment or logging differs between arms, and the metric is likely biased by it.

**L7 Principal Defense.** "That's a sample-ratio mismatch, and it invalidates the analysis until explained. Common causes: the treatment crashes or times out before logging for some users (slower LLM path), bot filtering applied unevenly, a redirect dropping users, or assignment keyed on something correlated with the treatment. I'd find the asymmetry by segmenting the SRM (by platform, browser, first-seen date). The users missing from one arm are rarely random, so neither is the metric. Fix it and re-run. Automated SRM checks should block results from being shown at all."

**Bar-Raiser Follow-ups.**
- *"Why is an LLM feature especially prone to this?"* Higher latency and timeouts in the treatment path drop sessions before logging.

</details>

---

## 7. Invariants Checklist

- [ ] Every online experiment has an `ExperimentPlan` written before launch: hypothesis, unit, one primary metric, guardrails, MDE, α, power, n, look schedule, pinned versions.
- [ ] Sample sizes come from the formula and are checked by simulation; durations are rounded up to whole weekly cycles.
- [ ] Fixed-horizon tests are read once; early looks use group-sequential or always-valid methods.
- [ ] SRM is checked automatically and blocks analysis.
- [ ] A/A tests run regularly on the real pipeline; p-values must look uniform.
- [ ] Offline comparisons of two systems on the same items are always paired (paired bootstrap or sign-flip permutation), resampling the independent unit.
- [ ] Results are reported as effect + CI vs the MDE, never as a bare p-value. "p ≤ 1/(B+1)" is written when no permutation is as extreme.
- [ ] Multiple metrics or slices are corrected (Holm/BH) or labelled exploratory.
- [ ] LLM features carry cost and latency guardrails; judged metrics use a validated, pinned judge.
- [ ] Bandit-based allocation logs propensities and keeps a holdout slice for effect estimation.

---

## 8. References

1. R. Kohavi, D. Tang, Y. Xu, *Trustworthy Online Controlled Experiments: A Practical Guide to A/B Testing*, Cambridge University Press, 2020. https://doi.org/10.1017/9781108653985
2. A. Deng, Y. Xu, R. Kohavi, T. Walker, *Improving the Sensitivity of Online Controlled Experiments by Utilizing Pre-Experiment Data* (CUPED), WSDM 2013. https://doi.org/10.1145/2433396.2433413
3. R. Johari, P. Koomen, L. Pekelis, D. Walsh, *Peeking at A/B Tests: Why It Matters, and What to Do About It*, KDD 2017. https://doi.org/10.1145/3097983.3097992
4. P. O'Brien, T. Fleming, *A Multiple Testing Procedure for Clinical Trials*, Biometrics 35(3), 1979. https://doi.org/10.2307/2530245
5. B. Efron, R. Tibshirani, *An Introduction to the Bootstrap*, Chapman & Hall, 1993.
6. Y. Benjamini, Y. Hochberg, *Controlling the False Discovery Rate*, JRSS B 57(1), 1995. https://doi.org/10.1111/j.2517-6161.1995.tb02031.x
7. S. Holm, *A Simple Sequentially Rejective Multiple Test Procedure*, Scandinavian Journal of Statistics 6(2), 1979.
8. P. Auer, N. Cesa-Bianchi, P. Fischer, *Finite-time Analysis of the Multiarmed Bandit Problem* (UCB1), Machine Learning 47, 2002. https://doi.org/10.1023/A:1013689704352
9. O. Chapelle, L. Li, *An Empirical Evaluation of Thompson Sampling*, NeurIPS 2011.
10. D. Russo, B. Van Roy, A. Kazerouni, I. Osband, Z. Wen, *A Tutorial on Thompson Sampling*, 2018. https://arxiv.org/abs/1707.02038
11. L. Li, W. Chu, J. Langford, R. Schapire, *A Contextual-Bandit Approach to Personalized News Article Recommendation* (LinUCB), WWW 2010. https://arxiv.org/abs/1003.0146
12. T. Lai, H. Robbins, *Asymptotically Efficient Adaptive Allocation Rules*, Advances in Applied Mathematics 6, 1985. https://doi.org/10.1016/0196-8858%2885%2990002-8
13. A. Ng, *Machine Learning Yearning* (dev-set size, iteration speed, dev vs test). https://www.deeplearning.ai/resources/
