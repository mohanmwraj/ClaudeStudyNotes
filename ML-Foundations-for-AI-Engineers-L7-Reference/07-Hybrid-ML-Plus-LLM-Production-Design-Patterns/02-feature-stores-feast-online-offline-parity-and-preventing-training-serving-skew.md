# 07.2 · Feature Stores (Feast), Online/Offline Parity & Preventing Training/Serving Skew

> **Folder 07 · Hybrid ML + LLM Production Design Patterns**
> **Measured on:** pandas 3.1 (`merge_asof` point-in-time joins), NumPy 2.5.4, scikit-learn 1.9.1 (logistic regression, HistGradientBoosting), seeded event-stream simulations with explicit, swappable bugs. Windows 11.
> **Design sources:** Sculley et al. (hidden technical debt in ML systems, 2015), Zinkevich (*Rules of ML*), Breck et al. (*The ML Test Score*, 2017), Kaufman et al. (leakage, 2012), Uber Michelangelo (2017), the Feast documentation (point-in-time joins, materialization). Full list in §8.

---

## 0. Orientation: The Model Is Only as Correct as the Features It's Served

A cheap model in a cascade (07.1) often needs context the request doesn't carry: how many tickets this user filed in 30 days, their recent sentiment, their plan tier. Computing those features **identically** for training (from history, offline) and for serving (from live state, online) is the problem feature stores exist to solve. Getting it wrong doesn't throw errors. It silently produces a model that looked great offline and underperforms in production. Measured results:

- **Leakage through a naive join:** training on each user's *latest* feature values (which include tickets filed *after* the escalation being predicted) gives an offline test AUC of **0.912**. Served with the features as they actually exist at prediction time, the same model scores **0.653**. A point-in-time (as-of) join gives **0.657 offline and 0.657 served**: an honest number, and slightly better in production than the leaky model.
- **Three classic skew bugs, measured.** On a model with parity AUC 0.809: a unit mismatch (milliseconds online vs seconds offline) gives AUC **0.756**; a default mismatch (missing → 0 online vs median offline) gives **0.794**; a skipped lowercasing step gives **0.776**. No exceptions, no alerts, just worse predictions.
- **Detection:** a replay diff (recompute offline features for logged online requests and compare) pins every bug to its feature and rows. Feature-distribution PSI flags two bugs as "major" (12.4 and 0.43) but the lowercasing bug only as **"moderate" (0.140)**, a band many teams log without paging.
- **Parity testing needs two implementations.** An independent streaming materializer matched the batch features for **all 2,992 users**. A variant using 30 calendar-day buckets instead of an exact 30-day window mismatched **83 users (2.8%)**. Each path looks correct on its own; only the cross-path comparison finds the boundary difference.

### The backend-engineer bridge

| You already know | Feature-store equivalent |
|---|---|
| Event sourcing: state at time t = fold over events ≤ t | **Point-in-time feature values** |
| Reading a replica that's behind the primary | **Feature staleness**: online values lag the event stream |
| A cache (Redis) in front of a warehouse | **Online store** (low-latency lookups) vs **offline store** (history for training) |
| Two services re-implementing the same business rule | **Training/serving skew**: two code paths for one feature |
| Shadow traffic / dual-write comparison during a migration | **Online/offline parity tests** |
| Schema registry and contracts | **Feature registry**: definitions, owners, types, TTLs |
| "Works in staging" because staging data is from tomorrow's backfill | **Temporal leakage** |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 What a feature store is: offline store, online store, registry, materialization | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Point-in-time correctness and the as-of join | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 A leakage taxonomy: temporal, target, and split contamination | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Training/serving skew: definition and the three classic bugs | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Online/offline parity testing with two implementations | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Detecting skew without replay: feature-distribution monitoring | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Embeddings as features: model versions are feature versions | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Freshness, TTLs, and staleness as a form of skew | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.9 Feast's model: entities, feature views, historical retrieval, materialization | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Feature stores for LLM applications: prompt-time context and "prompt skew" | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Streaming semantics: watermarks, late data, exactly-once | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 What a feature store is: offline store, online store, registry, materialization `[MUST-KNOW: Core AI Engineer Edge]`

```text
            events (clicks, tickets, messages)
                         │
          ┌──────────────┴───────────────┐
          ▼                              ▼
   OFFLINE STORE (warehouse/Parquet)   STREAM / BATCH MATERIALIZATION
   full history of feature values      ──────────────▶  ONLINE STORE (Redis, DynamoDB, …)
   keyed by (entity, event_time)                        latest value per entity, ms lookups
          │                                                      │
   point-in-time join with labels                         request-time lookup
          ▼                                                      ▼
      TRAINING SET                                         SERVING FEATURES
                    ▲                                   ▲
                    └──────── REGISTRY: one definition ─┘
                         (entity, transformation, TTL, owner, version)
```

The three things that matter:

1. **One definition, two materializations.** The feature "tickets in the last 30 days" is defined once. The offline store holds its value at every point in history, and the online store holds its current value.
2. **The offline store is temporal.** Every value carries an event timestamp, so training can ask "what was this feature *at* time t?".
3. **Materialization moves values from the definition to the online store**, either by batch jobs ("materialize the last day") or by stream processors. Its correctness is what parity tests check (§1.5).

A feature store is not required for this. Plenty of teams implement the same contract with a warehouse table, a stream job and Redis. The contract (temporal history, one definition, a parity check) is what matters. The product is a convenience.

### 1.2 Point-in-time correctness and the as-of join `[MUST-KNOW: Core AI Engineer Edge]`

A training example is (entity, label timestamp t, label). The features must be **the values that would have been visible at t**, never later ones:

```text
feature(entity, t) = value from the latest event with event_time ≤ t   (and, with a TTL, event_time ≥ t − TTL)

events for one user:   ●───────●──────────●─────[label at t]────●────●
                       d1      d9         d20                   d26  d28   (post-escalation follow-ups)
naive join  (latest):  uses the state after d28   ← includes the future
as-of join  (t):       uses the state after d20   ← what the model would actually have seen
```

In pandas this is `merge_asof(labels, features, left_on="label_ts", right_on="feat_ts", by="user")`, with both frames sorted by time. In Feast, `get_historical_features(entity_df, features)` performs the same join, bounded by each feature view's TTL. In SQL it's a window function picking the last row per entity with `event_time <= label_time`.

**Measured cost of getting it wrong** (listing §3.1): escalations generate follow-up tickets with negative sentiment *after* the label time. The naive join hands those to the model, which learns "users with many recent angry tickets escalate", true only because the escalation caused them:

| Training features | Offline test AUC | AUC when served (point-in-time) |
|---|---|---|
| Naive (latest values) | **0.9118** | **0.6531** |
| Point-in-time (as-of) | 0.6570 | 0.6570 |

The leaky model's offline number is inflated by 0.26 AUC. And because it learned to rely on a signal that doesn't exist at serving time, it's slightly *worse* in production than the honest model. Leakage doesn't just lie about quality. It can make the model worse.

### 1.3 A leakage taxonomy: temporal, target, and split contamination `[MUST-KNOW: Core AI Engineer Edge]`

Kaufman et al. (2012) define leakage as information in training that won't be available at prediction time. The forms you'll meet:

| Form | Example | Detection |
|---|---|---|
| **Temporal leakage** | Latest-value joins (§1.2); aggregates computed over windows that extend past the label time | As-of joins only; assert feature_ts ≤ label_ts in the training pipeline |
| **Target leakage** | A "resolution_code" feature that's only filled in after escalation | Ask for each feature: when is it written, and by whom? A feature whose importance is suspiciously high |
| **Split contamination** | Random train/test split over time-ordered data, so the test set has earlier events of the same users | Split by time (the listing trains before day 80, tests after) or by entity |
| **Duplicate leakage** | The same query text in train and test (common in intent and RAG eval sets) | Exact and near-duplicate detection across splits (03.1 clustering, MinHash) |
| **Eval-set leakage into prompts** | Few-shot examples drawn from the eval set | Separate pools for prompt examples and eval items |

**The tell:** an offline metric that's much better than anything comparable, or a single feature with outsized importance. Before celebrating, ask when each feature's value becomes known.

### 1.4 Training/serving skew: definition and the three classic bugs `[MUST-KNOW: Core AI Engineer Edge]`

Training/serving skew is any difference between the feature values a model was trained on and the values it receives for the *same* underlying input in production. Zinkevich's *Rules of ML* devotes a whole section to it. It comes from **two code paths** computing one feature (a batch pipeline in SQL/Spark, a service in Go/Java/Python) or from **two data sources** (a warehouse snapshot vs a live database).

Listing §3.2 trains a gradient-boosted classifier on offline features, then serves it through an "online path" with one bug at a time:

| Bug | What happened | Rows affected | AUC (parity: 0.8089) |
|---|---|---|---|
| Unit mismatch | Online sends session duration in **ms**, training used **s** | 100% | 0.7562 |
| Default mismatch | Missing account age → **0** online vs the training **median** | 14.4% | 0.7939 |
| Normalization mismatch | The online keyword counter skips **lowercasing**, missing upper-case text | 18.3% | 0.7755 |

Why a tree model degrades this way: a unit bug multiplies every duration by 1,000, so every request lands above every learned split threshold, and the feature becomes a constant. The model falls back on the other features, which is why AUC drops but doesn't collapse to 0.5. A linear model would react differently (a huge logit shift, likely far worse). Either way, **nothing errors**: the service returns predictions with normal latency.

**Prevention, in order of strength:**

1. **One implementation for both paths.** Compute features in one library called from both the batch pipeline and the service, or log the features the service actually used and train on those logs (Zinkevich's Rule #29).
2. **Typed feature contracts.** Units in the name (`session_duration_s`), explicit null semantics, value ranges, all checked at both write and read.
3. **Parity tests** (§1.5) and **monitoring** (§1.6) for what slips through.

### 1.5 Online/offline parity testing with two implementations `[MUST-KNOW: Core AI Engineer Edge]`

A parity test compares the online path's values with the offline path's values for the same entities at the same time. It's only meaningful if the two are **independent implementations**. Rebuilding the online store from the offline table and comparing it to the offline table is a tautology.

Listing §3.1, section 3, implements the online path as a **streaming materializer**: consume events in time order, keep per-user state (a deque of timestamps in the last 30 days, the last 5 sentiments), emit current values. It then compares against the batch pandas features:

| Online implementation | Users | Mismatched users |
|---|---|---|
| Exact sliding window (t − 30 d, t] | 2,992 | **0** |
| 30 calendar-day buckets (a common shortcut) | 2,992 | **83 (2.8%)**, e.g. user 283: online 3 vs offline 4 |

The daily-bucket variant isn't "wrong" in any way a unit test would catch. It implements a *different definition* of "the last 30 days", and the boundary events land differently. That's typical of real skew: both sides are internally correct and disagree on semantics. Parity tests should run **continuously in production** on a sample of entities, not just once before launch, because streaming jobs, schemas and backfills change.

**What to compare:** exact equality for counts and categorical features, a tolerance for floats (sums in different orders differ in the last bits), and freshness (the online value's event time vs the offline value's) as a separate metric (§1.8).

### 1.6 Detecting skew without replay: feature-distribution monitoring `[MUST-KNOW: Core AI Engineer Edge]`

Replay diffs need the raw inputs of online requests logged and re-runnable through the offline code. That's the gold standard, but not always available. The cheaper signal is to **compare the distribution of each feature as served against its training distribution**, using PSI or KS (07.3):

| Bug | Replay: rows that differ | PSI (train vs online) per feature | PSI verdict |
|---|---|---|---|
| Unit mismatch | duration 100% | duration **12.43** | major |
| Default mismatch | account_age 14.4% | account_age **0.432** | major |
| No lowercasing | keyword_count 18.3% | keyword_count **0.140** | **moderate** |

Two observations. First, **replay localizes exactly**: which feature, which rows. That makes it the debugging tool. Second, **PSI's sensitivity depends on how much the bug moves the distribution**, not on how much it hurts the model. The lowercasing bug cost more AUC (−0.033) than the default bug (−0.015) but has a smaller PSI. Thresholds like "page at 0.25" would have missed it. Use per-feature PSI as a **screen** that triggers a replay diff, and set thresholds per feature from their historical noise (07.3 §1.3).

**Logging features at serving time** is what makes both possible. Log the feature vector the model actually saw, with the model version and the feature-definition version, for a sample of requests. It doubles as training data with zero skew.

### 1.7 Embeddings as features: model versions are feature versions `[MUST-KNOW: Core AI Engineer Edge]`

In AI systems the most important "feature" is often an **embedding**: the query embedding fed to a router head, the document embeddings in a vector index. Every rule above applies, with a twist: **changing the embedding model changes every feature value at once**. Common skew bugs:

- **Index built with model v1, queries embedded with v2.** Cosine similarities become meaningless, and recall collapses without errors. 07.3's retraining simulation makes this concrete: a retraining job that embedded its data with a different encoder version produced a model at ~10% accuracy.
- **Normalization mismatch.** The index stores normalized vectors but the query path doesn't normalize (or the reverse). Dot-product rankings change, and 01.1's equivalence proof only holds on the unit sphere.
- **Quantization or truncation mismatch.** An int8 or Matryoshka-truncated index (01.1, 01.2) queried with full-precision, full-length vectors, or vice versa, without the matching rescoring step.
- **Tokenizer or preprocessing drift.** Different text cleaning before embedding at index time vs query time. It's the embedding version of the lowercasing bug.

**Defence:** treat `(embedding model ID, revision, normalization, dtype, dimension)` as part of the feature's version, store it with every index and every head, and assert it matches at query time. Re-embedding the corpus is a migration, with dual-read, parity checks and cutover, not a deploy.

### 1.8 Freshness, TTLs, and staleness as a form of skew `[GOOD-TO-KNOW: Architectural Literacy]`

The online store's value is only as fresh as its last materialization. If training used exact as-of values but serving sees values up to an hour stale, that's skew too: the model was trained on information fresher than it gets. Two consistent fixes: **match training to serving** (simulate the serving lag in the as-of join: use feature_ts ≤ t − lag), or **make serving fresher** (streaming materialization). A **TTL** bounds how old a value may be before it's treated as missing. It must be the same in the offline join (Feast applies the feature view's TTL in historical retrieval) and online, and the "missing" default must match on both paths (bug 2 above).

### 1.9 Feast's model: entities, feature views, historical retrieval, materialization `[GOOD-TO-KNOW: Architectural Literacy]`

Feast is an open-source feature store that implements the §1.1 contract on top of your existing storage:

- **Entity:** the join key (`user_id`).
- **Feature view:** a set of features from one source with an event-timestamp column and a TTL.
- **On-demand feature view:** request-time transformations defined once and executed in both the training and serving paths. This is the "one implementation" defence (§1.4) for features that depend on the request itself.
- **`get_historical_features(entity_df, features)`:** the point-in-time join for training. `entity_df` holds (entity, event_timestamp) rows, like the listing's labels.
- **`materialize` / `materialize_incremental`:** load values from the offline source into the online store up to a timestamp.
- **`get_online_features(features, entity_rows)`:** low-latency serving lookups.
- **Offline stores** include BigQuery, Snowflake, Redshift, Spark and files. **Online stores** include Redis, DynamoDB, Bigtable, Postgres and SQLite (see the docs for the current list).

What Feast does *not* do for you: guarantee that a separately written streaming job computes the same values (parity is still your test), or monitor skew (logging and PSI are still your job).

### 1.10 Feature stores for LLM applications: prompt-time context and "prompt skew" `[GOOD-TO-KNOW: Architectural Literacy]`

LLM applications assemble **context** at request time: the user's plan, recent orders, open tickets, retrieved documents. That context is a feature vector rendered as text, and it has every problem above:

- **Prompt skew.** An eval set built by *re-fetching* each user's context today (instead of the context as it was when the conversation happened) evaluates the LLM on information it didn't have. That's temporal leakage in a prompt. Store the rendered context with each logged conversation, and evaluate on that.
- **Context freshness.** "Your order shipped" from a stale cache is a hallucination-shaped bug caused by a feature-store problem.
- **Embeddings for retrieval** are features with versions (§1.7).

The same platform that serves features to a cascade's head can serve prompt context to its LLM stage, with the same point-in-time and parity guarantees.

### 1.11 Streaming semantics: watermarks, late data, exactly-once `[SKIP: Academic/Research Only]`

Streaming materializers must decide when a time window is complete (watermarks), what to do with late events, and how to avoid double-counting on retries (exactly-once processing). These questions are real for whoever builds the stream job, and covered in depth by the companion Dataflow/Beam/Flink KB. For this file, the essential point is that **late or replayed events are another way the online and offline values can disagree**, so parity tests should tolerate a defined lateness window and alert beyond it.

---

## 2. Where It Beats an LLM in Production

**1. Context the LLM can't compute cheaply.** "Tickets in the last 30 days" and "mean sentiment of the last 5 messages" are a sub-millisecond key-value lookup from an online store. An LLM can only get them through tool calls (a database round trip plus tokens to describe the result) or by reading the raw history in its context window (thousands of tokens per request). A cheap model with feature-store features answers "will this escalate?" in ~1 ms. The LLM version costs a call *and* still needs the same features to be correct.

**2. A trained model with honest features is measurable; a prompt with live context often isn't.** The point-in-time join gives you a training and evaluation set where every example has exactly the information available at the time. Most LLM eval sets for context-dependent tasks quietly re-fetch context at eval time (§1.10's prompt skew), so their numbers carry the same inflation as the naive join (0.912 vs 0.653 here).

**3. Skew detection is classical tooling.** Replay diffs and per-feature PSI are cheap, deterministic, and run on every request sample. No LLM can tell you that your duration feature switched units.

---

## 3. Production Code Blueprint

### 3.1 Point-in-time joins, leakage, and a two-implementation parity test

```python
"""point_in_time_feature_store.py - the feature-store problem in miniature: point-in-time joins and online/offline parity.

Scenario: predict whether a support conversation escalates, using per-user aggregate features
(tickets in the last 30 days, mean sentiment of the last 5 messages).
  1. Naive join (each label row gets the user's LATEST feature values) leaks the future: offline AUC is inflated.
  2. Point-in-time (as-of) join: each label row gets the values as they were at the label timestamp.
  3. Online/offline parity: an independent STREAMING materializer (the online path) vs the batch pandas features
     (the offline path), compared per user; plus a streaming variant with daily buckets, a common window bug.
"""
from collections import defaultdict, deque

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score

rng = np.random.default_rng(221)
n_users, days = 3000, 120
t0 = pd.Timestamp("2026-06-01")

# events: each user has a latent "frustration" that rises before an escalation
rows = []
for u in range(n_users):
    k = rng.poisson(6)
    times = np.sort(rng.uniform(0, days, k))
    frustration = rng.normal(0, 1)
    for t in times:
        rows.append((u, t0 + pd.Timedelta(days=float(t)), rng.normal(-0.3 * frustration, 1)))
def add_features(df):
    """Per-user rolling features. groupby().rolling(on=...) returns rows ordered by (user, time), so sort that way
    first and assign positionally; then restore time order (merge_asof needs it)."""
    df = df.sort_values(["user", "ts"], kind="stable").reset_index(drop=True)
    df["tickets_30d"] = df.groupby("user").rolling("30D", on="ts")["sentiment"].count().to_numpy()
    df["sent_last5"] = df.groupby("user")["sentiment"].transform(lambda s: s.rolling(5, min_periods=1).mean())
    return df.sort_values("ts", kind="stable").reset_index(drop=True)


ev = add_features(pd.DataFrame(rows, columns=["user", "ts", "sentiment"]))
feats = ev[["user", "ts", "tickets_30d", "sent_last5"]]

# labels: a conversation at time t; escalation depends on the features AS OF t, and escalations themselves
# generate follow-up tickets with negative sentiment AFTER t (the future that a naive join leaks)
lab = ev.sample(4000, random_state=1)[["user", "ts"]].rename(columns={"ts": "label_ts"}).sort_values("label_ts")
asof = pd.merge_asof(lab, feats.rename(columns={"ts": "feat_ts"}), left_on="label_ts", right_on="feat_ts", by="user")
z = 0.25 * asof["tickets_30d"] - 0.9 * asof["sent_last5"] - 2.0
lab["y"] = (rng.random(len(lab)) < 1 / (1 + np.exp(-z.values))).astype(int)
follow = lab[lab["y"] == 1]
post = pd.DataFrame({"user": np.repeat(follow["user"].values, 3),
                     "ts": np.repeat(follow["label_ts"].values, 3) + pd.to_timedelta(rng.uniform(0.1, 5, 3 * len(follow)), "D"),
                     "sentiment": rng.normal(-1.5, 0.7, 3 * len(follow))})
ev2 = add_features(pd.concat([ev[["user", "ts", "sentiment"]], post]))
feats2 = ev2[["user", "ts", "tickets_30d", "sent_last5"]]

lab = lab.sort_values("label_ts")
train, test = lab[lab["label_ts"] < t0 + pd.Timedelta(days=80)], lab[lab["label_ts"] >= t0 + pd.Timedelta(days=80)]
latest = feats2.groupby("user").tail(1).set_index("user")[["tickets_30d", "sent_last5"]]


def naive(df):
    return df.join(latest, on="user")


def point_in_time(df):
    return pd.merge_asof(df, feats2.rename(columns={"ts": "feat_ts"}), left_on="label_ts", right_on="feat_ts",
                         by="user", allow_exact_matches=True)


print(f"{len(ev2):,} events, {len(lab):,} labelled conversations ({lab['y'].mean():.1%} escalate); "
      f"train before day 80 ({len(train)}), test after ({len(test)})")
print(f"\n{'training features':22s} {'offline test AUC':>16} {'AUC when served (point-in-time)':>32}")
cols = ["tickets_30d", "sent_last5"]
res = {}
for name, build in (("naive (latest values)", naive), ("point-in-time (as-of)", point_in_time)):
    tr, te = build(train), build(test)
    m = LogisticRegression().fit(tr[cols], tr["y"])
    offline = roc_auc_score(te["y"], m.predict_proba(te[cols])[:, 1])
    served = roc_auc_score(test["y"], m.predict_proba(point_in_time(test)[cols])[:, 1])
    res[name] = (offline, served)
    print(f"{name:22s} {offline:>16.4f} {served:>32.4f}")
print("the naive model 'knows' about post-escalation tickets; in production those don't exist yet")
assert res["naive (latest values)"][0] > res["naive (latest values)"][1] + 0.05

print("\n== online/offline parity: a streaming materializer vs the batch features ==")


def stream(events, daily_buckets=False):
    """Online path: consume events in time order, keep per-user state, emit the latest feature values."""
    win, last5, out = defaultdict(deque), defaultdict(lambda: deque(maxlen=5)), {}
    for r in events.itertuples(index=False):
        w = win[r.user]
        w.append(r.ts)
        if daily_buckets:                                            # "last 30 days" as 30 calendar-day buckets
            start = r.ts.normalize() - pd.Timedelta(days=29)
            while w[0] < start:
                w.popleft()
        else:                                                        # exact (t - 30 days, t], like pandas "30D"
            while w[0] <= r.ts - pd.Timedelta(days=30):
                w.popleft()
        last5[r.user].append(r.sentiment)
        out[r.user] = (len(w), sum(last5[r.user]) / len(last5[r.user]))
    return out


offline_latest = feats2.groupby("user").tail(1).set_index("user")
for name, daily in (("exact sliding window", False), ("daily buckets (bug)", True)):
    online = stream(ev2[["user", "ts", "sentiment"]], daily)
    bad = [u for u, r in offline_latest.iterrows()
           if abs(online[u][0] - r.tickets_30d) > 1e-9 or abs(online[u][1] - r.sent_last5) > 1e-9]
    print(f"{name:22s} users {len(online):,}; mismatched users {len(bad):4d} ({len(bad) / len(online):.1%})"
          + (f"; e.g. user {bad[0]}: online {online[bad[0]][0]} vs offline {offline_latest.loc[bad[0], 'tickets_30d']:.0f}"
             if bad else ""))
    if not daily:
        assert not bad
    else:
        assert bad
print("each path looks correct on its own; only the cross-path comparison finds the window-boundary difference")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
20,642 events, 4,000 labelled conversations (22.4% escalate); train before day 80 (2641), test after (1359)

training features      offline test AUC  AUC when served (point-in-time)
naive (latest values)            0.9118                           0.6531
point-in-time (as-of)            0.6570                           0.6570
the naive model 'knows' about post-escalation tickets; in production those don't exist yet

== online/offline parity: a streaming materializer vs the batch features ==
exact sliding window   users 2,992; mismatched users    0 (0.0%)
daily buckets (bug)    users 2,992; mismatched users   83 (2.8%); e.g. user 283: online 3 vs offline 4
each path looks correct on its own; only the cross-path comparison finds the window-boundary difference

ALL ASSERTIONS PASSED
```

### 3.2 Three skew bugs, their cost, and two ways to detect them

```python
"""training_serving_skew_detector.py - three classic training/serving skew bugs, their cost, and how to catch them.

A guardrail-style model trained on offline features. The online path recomputes the features in a different
service, with three bugs that each happen in real systems:
  (a) a unit mismatch: session duration in milliseconds online vs seconds offline
  (b) a default mismatch: missing account age filled with 0 online vs the training median offline
  (c) a text-normalization mismatch: the online path skips lowercasing before a keyword-count feature
  1. Accuracy cost of each bug.
  2. Detection: replay a sample of logged online requests through the offline feature code and diff per feature,
     plus a per-feature distribution check (PSI) that needs no replay.
"""
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score

rng = np.random.default_rng(231)
n = 20_000
dur_s = rng.lognormal(4, 1, n)
age = np.where(rng.random(n) < 0.15, np.nan, rng.uniform(1, 1500, n))
texts_upper = rng.random(n) < 0.3                                   # 30% of users type in caps
kw_true = rng.poisson(1.0, n)
z = 0.8 * np.log(dur_s) - 0.002 * np.nan_to_num(age, nan=700) + 0.9 * kw_true - 4
y = rng.random(n) < 1 / (1 + np.exp(-z))
median_age = np.nanmedian(age)


def offline(d, a, kw):
    return np.c_[d, np.where(np.isnan(a), median_age, a), kw]


def online(d, a, kw, bug):
    f = offline(d, a, kw)
    if bug == "unit (ms vs s)":
        f[:, 0] = d * 1000
    if bug == "default (0 vs median)":
        f[:, 1] = np.where(np.isnan(a), 0, a)
    if bug == "no lowercasing":
        f[:, 2] = np.where(texts_upper[idx_test], 0, kw)            # keyword matcher misses uppercase text
    return f


idx = rng.permutation(n)
idx_train, idx_test = idx[:14_000], idx[14_000:]
Xtr = offline(dur_s[idx_train], age[idx_train], kw_true[idx_train])
m = HistGradientBoostingClassifier(random_state=0).fit(Xtr, y[idx_train])
ref = offline(dur_s[idx_test], age[idx_test], kw_true[idx_test])
print(f"== 1. AUC on the same 6,000 test requests ==")
print(f"{'online path':24s} {'AUC':>7}")
base = roc_auc_score(y[idx_test], m.predict_proba(ref)[:, 1])
print(f"{'no bug (parity)':24s} {base:>7.4f}")
res = {}
for bug in ("unit (ms vs s)", "default (0 vs median)", "no lowercasing"):
    on = online(dur_s[idx_test], age[idx_test], kw_true[idx_test], bug)
    res[bug] = (roc_auc_score(y[idx_test], m.predict_proba(on)[:, 1]), on)
    print(f"{bug:24s} {res[bug][0]:>7.4f}")


def psi(a, b, bins=10):
    edges = np.unique(np.quantile(a, np.linspace(0, 1, bins + 1)))
    pa = np.histogram(a, np.r_[-np.inf, edges[1:-1], np.inf])[0] / len(a) + 1e-6
    pb = np.histogram(b, np.r_[-np.inf, edges[1:-1], np.inf])[0] / len(b) + 1e-6
    return float(np.sum((pb - pa) * np.log(pb / pa)))


print("\n== 2. detection: replay diff (needs logged raw inputs) vs PSI (needs only feature logs) ==")
names = ["duration", "account_age", "keyword_count"]
short = {"duration": "dur", "account_age": "age", "keyword_count": "kw"}
band = lambda p: "major" if p > 0.25 else "moderate" if p > 0.1 else "stable"
print(f"{'bug':24s} {'replay: rows that differ, per feature':>38}   {'PSI(train vs online), per feature':>40}")
verdicts = {}
for bug, (auc, on) in res.items():
    mism = np.mean(np.abs(on - ref) > 1e-9, axis=0)
    ps = [psi(Xtr[:, j], on[:, j]) for j in range(3)]
    verdicts[bug] = (names[int(np.argmax(mism))], band(max(ps)))
    print(f"{bug:24s} " + "  ".join(f"{short[nm]:>3} {r:6.1%}" for nm, r in zip(names, mism)) + "   "
          + "  ".join(f"{short[nm]:>3} {p:6.3f}" for nm, p in zip(names, ps)))
for bug, (feat, b) in verdicts.items():
    print(f"  {bug:24s} replay pins it on '{feat}'; PSI alone says '{b}'")
print("replay localizes every bug to the feature and the rows; PSI's verdict depends on how much the bug moves")
print("the distribution, so a bug can sit in the 'moderate' band that many teams only log, not page on")
assert res["unit (ms vs s)"][0] < base - 0.03 and all(v[0] for v in verdicts.values())
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. AUC on the same 6,000 test requests ==
online path                  AUC
no bug (parity)           0.8089
unit (ms vs s)            0.7562
default (0 vs median)     0.7939
no lowercasing            0.7755

== 2. detection: replay diff (needs logged raw inputs) vs PSI (needs only feature logs) ==
bug                       replay: rows that differ, per feature          PSI(train vs online), per feature
unit (ms vs s)           dur 100.0%  age   0.0%   kw   0.0%   dur 12.434  age  0.003   kw  0.000
default (0 vs median)    dur   0.0%  age  14.4%   kw   0.0%   dur  0.002  age  0.432   kw  0.000
no lowercasing           dur   0.0%  age   0.0%   kw  18.3%   dur  0.002  age  0.003   kw  0.140
  unit (ms vs s)           replay pins it on 'duration'; PSI alone says 'major'
  default (0 vs median)    replay pins it on 'account_age'; PSI alone says 'major'
  no lowercasing           replay pins it on 'keyword_count'; PSI alone says 'moderate'
replay localizes every bug to the feature and the rows; PSI's verdict depends on how much the bug moves
the distribution, so a bug can sit in the 'moderate' band that many teams only log, not page on

ALL ASSERTIONS PASSED
```

### 3.3 The equivalent Feast definitions

A design sketch (not run in this KB's harness) of how §3.1's features map onto Feast's API. Check names against the Feast version you deploy.

```python
from datetime import timedelta
from feast import Entity, FeatureView, Field, FileSource
from feast.types import Float32, Int64

user = Entity(name="user", join_keys=["user_id"])
events = FileSource(path="data/user_support_features.parquet", timestamp_field="event_ts")

support_stats = FeatureView(
    name="support_stats",
    entities=[user],
    ttl=timedelta(days=30),                 # the same TTL bounds historical joins and online freshness
    schema=[Field(name="tickets_30d", dtype=Int64), Field(name="sent_last5", dtype=Float32)],
    source=events,
)

# training: point-in-time join of labels (user_id, event_timestamp, label) against feature history
training_df = store.get_historical_features(
    entity_df=labels_df, features=["support_stats:tickets_30d", "support_stats:sent_last5"]).to_df()

# serving: materialize the latest values, then low-latency lookups
store.materialize_incremental(end_date=now)
online = store.get_online_features(
    features=["support_stats:tickets_30d", "support_stats:sent_last5"],
    entity_rows=[{"user_id": 283}]).to_dict()
```

The parity test from §3.1 still applies when a stream processor (not Feast's batch materialization) writes the online store: compare `get_online_features` for a sample of users against `get_historical_features` at "now".

---

## 4. The Andrew Ng Lens: Data-Centric AI Includes the Data Pipeline

### 4.1 Data quality is a systems property

Ng's data-centric AI argument is that improving the data often beats improving the model. Training/serving skew is the systems version of bad data: the model is fine, the *data it's served* is wrong. The three bugs in §1.4 cost 1.5–5.3 AUC points each. That's more than most model changes buy, and no hyperparameter search would have found them.

### 4.2 Error analysis that reaches into features

When error analysis (06.3) finds a cluster of confident errors, one tag should always be "**features differ from training**". For a sample of those errors, pull the logged online feature vector, recompute it offline, and diff. If the bucket is large, it's a skew bug, and no amount of retraining will fix it.

### 4.3 Dev sets must be built the way production sees data

Ng's rule that dev and test sets come from the deployment distribution has a temporal corollary: they must be built with **point-in-time features**. A dev set assembled with latest-value joins measures a model that doesn't exist in production. Here it overstated AUC by 0.26.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Offline AUC far above production | 0.91 offline vs 0.65 served | Latest-value join (temporal leakage) | As-of joins | Assert feature_ts ≤ label_ts in the training pipeline |
| F2 | One feature dominates importance | A "too good" feature | Target leakage (written after the outcome) | Remove it; document when each feature is written | Feature registry records the write time and writer |
| F3 | Quality drops after a service rewrite | No errors, lower AUC | Unit or default mismatch between paths | Fix the path; retrain or align | One feature library for both paths; typed units in names |
| F4 | Parity test always passes | Online store rebuilt from offline data | Tautological test | Compare two independent implementations | Parity test owned by a different code path |
| F5 | 2–3% of users get slightly wrong features | Boundary mismatches | Window semantics differ (calendar buckets vs sliding) | Align definitions in the registry | Continuous parity sampling in production |
| F6 | PSI dashboard green, model degraded | A "moderate" PSI on one feature | Thresholds blind to small but harmful shifts | Replay diff on PSI screens; per-feature thresholds | Log served features; scheduled replay diffs |
| F7 | Retrieval recall collapses after a deploy | Cosine scores shifted for all queries | Query and index embedded with different model versions | Re-embed or roll back | Embedding version asserted at query time |
| F8 | Model worse on fresh users | Missing features handled differently | Default/TTL semantics differ online vs offline | One null policy, applied in both paths | Null semantics in the feature contract |
| F9 | LLM eval great, production answers wrong about account state | Eval re-fetched context at eval time | Prompt skew (temporal leakage in context) | Evaluate on logged rendered context | Store the rendered context with every logged conversation |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Our churn/escalation model has AUC 0.91 offline and 0.65 in production. What happened?"</b></summary>

**Initial Prompt.** A model trained on a warehouse join underperforms after launch.

**L5 Answer.** "The data drifted after launch; retrain on recent data."

**Why L5 Fails in Production.** A gap that large on day one is almost never drift. It's the training set containing information that doesn't exist at prediction time, and retraining on the same pipeline reproduces it.

**L7 Principal Defense.** "First suspect leakage. How were features joined to labels? If each label row got the entity's *latest* feature values, the features include events after the label. In our simulation, follow-up tickets after an escalation gave the naive model 0.912 offline AUC vs 0.653 served. The fix is an as-of join: each label gets the feature values with event_time ≤ label_time (merge_asof, Feast's get_historical_features, or a window function). The honest model scored 0.657 offline *and* served, and slightly beat the leaky one in production. I'd add a pipeline assertion that feature_ts ≤ label_ts, and a time-based train/test split."

**Bar-Raiser Follow-ups.**
- *"How would you prove it's leakage, not drift?"* Rebuild the training set point-in-time and re-evaluate. If offline AUC drops to the production level, it was leakage.
- *"Any other suspects?"* Target leakage (a field written after the outcome) and a random split over time-ordered data.

</details>

<details><summary><b>Q2 · "What is training/serving skew, and how do you prevent it?"</b></summary>

**Initial Prompt.** A platform design review.

**L5 Answer.** "When production data is different from training data."

**Why L5 Fails in Production.** That's drift. Skew is when the *same* input produces different feature values in the two paths. The causes and fixes are different.

**L7 Principal Defense.** "Skew means the feature computation differs between training and serving for the same event. It comes from two implementations or two data sources. Classic bugs we measured: a ms-vs-s unit mismatch (AUC 0.809 → 0.756), a 0-vs-median default for missing values (→ 0.794), a skipped lowercasing step (→ 0.776). None of them raised errors. Prevention in order: one feature implementation shared by both paths (or train on logged serving features, Rules of ML #29), typed contracts with units and null semantics, continuous parity tests between independent implementations, and per-feature monitoring that triggers replay diffs."

**Bar-Raiser Follow-ups.**
- *"Why does the tree model not collapse completely on the unit bug?"* The feature becomes constant (all values above every split), so the model leans on the other features. A linear model would shift its logits far more.
- *"Who owns parity?"* The platform team owns the harness, and each feature's owner owns its definition.

</details>

<details><summary><b>Q3 · "Our parity test always passes. Is that good?"</b></summary>

**Initial Prompt.** A test compares the online store with the offline table.

**L5 Answer.** "Yes, it means the stores are consistent."

**Why L5 Fails in Production.** If the online store is loaded *from* the offline table, the test compares a copy with its source, which can't fail. Real skew lives in a separately written stream job or service.

**L7 Principal Defense.** "A parity test is only meaningful across independent implementations. In our listing, the online path is a streaming materializer that consumes events and keeps per-user state, compared against batch pandas features: 0 mismatches over 2,992 users with an exact sliding window. A variant using 30 calendar-day buckets mismatched 83 users (2.8%), and nothing else would have caught that: each implementation is internally correct. I'd run it continuously on a sample in production, with exact equality for counts, a tolerance for floats, a lateness window, and freshness tracked separately."

**Bar-Raiser Follow-ups.**
- *"Sample size?"* Enough to see a 1% mismatch rate: a few thousand entities per day, stratified by activity level, since heavy users hit window boundaries more.
- *"Where do you run it?"* As a scheduled job reading the online store and the offline store at the same "as of" time.

</details>

<details><summary><b>Q4 · "Can feature-distribution monitoring catch skew without replay?"</b></summary>

**Initial Prompt.** Logging raw inputs for replay is expensive, so the team proposes PSI dashboards.

**L5 Answer.** "Yes, PSI above 0.25 means something is wrong."

**Why L5 Fails in Production.** PSI measures how much a distribution moved, not how much the model is hurt. The lowercasing bug hurt AUC more than the default bug but had PSI 0.140 vs 0.432.

**L7 Principal Defense.** "Partly. Per-feature PSI between training and served values caught the unit bug (12.4) and the default bug (0.43) as 'major', but the lowercasing bug only as 'moderate' (0.14), below the usual paging threshold. I'd use PSI as a cheap screen with **per-feature thresholds calibrated on each feature's own noise** (07.3), and a scheduled **replay diff** on a small logged sample as the ground truth. Replay localized every bug to the exact feature and rows. Logging 1% of served feature vectors is cheap, and it doubles as zero-skew training data."

**Bar-Raiser Follow-ups.**
- *"Which features first?"* The ones with the highest importance, and the ones computed by more than one code path.
- *"Model-output monitoring?"* Yes, the score distribution too. It integrates all features, but can't tell you which one moved.

</details>

<details><summary><b>Q5 · "We upgraded our embedding model and search quality collapsed. Why?"</b></summary>

**Initial Prompt.** A new embedding model was deployed to the query service.

**L5 Answer.** "The new model is worse; roll back."

**Why L5 Fails in Production.** The new model may be better. The likely problem is that the index still holds vectors from the old model, so query and document vectors live in different spaces.

**L7 Principal Defense.** "Embeddings are features, and the model version is part of the feature's definition. Querying a v1 index with v2 query vectors makes cosine similarity meaningless. 07.3's simulation shows the same failure in a retraining pipeline: ~10% accuracy. The fix is a migration, not a deploy: re-embed the corpus with v2 into a new index, dual-read and compare recall on the eval set, then cut over. Prevention: store (model ID, revision, normalization, dtype, dimension) with the index and assert it at query time, so a mismatch fails loudly instead of silently."

**Bar-Raiser Follow-ups.**
- *"Can you avoid re-embedding?"* With a learned linear map between the two spaces you can approximate it (01.2), measured on recall. It's usually a stopgap.
- *"Other silent embedding skews?"* Normalization on one side only, int8 or truncated index vectors without rescoring, and different text preprocessing.

</details>

<details><summary><b>Q6 · "Do we need a feature store like Feast?"</b></summary>

**Initial Prompt.** A team with three models and a warehouse.

**L5 Answer.** "Yes, every ML team needs a feature store."

**Why L5 Fails in Production.** A feature store is an implementation of a contract. The contract is what's needed, and small teams can implement it without a platform.

**L7 Principal Defense.** "We need the contract: (1) temporal history of every feature, so training uses as-of joins; (2) one definition per feature, used by both paths; (3) a low-latency online read path; (4) parity tests and monitoring. With three models, a warehouse table with event timestamps, one shared feature library, Redis and a scheduled parity job can do that. Feast becomes worth it when several teams share features, when there's a registry and reuse problem, or when we need point-in-time retrieval and materialization at scale. I'd decide on the number of shared features and teams, not on fashion."

**Bar-Raiser Follow-ups.**
- *"What would you build first?"* Point-in-time training-set generation. It prevents the most expensive error (leakage) and needs no online infrastructure.
- *"Managed options?"* Cloud feature stores exist. Evaluate them on the same contract, plus cost and lock-in.

</details>

<details><summary><b>Q7 · "How do you evaluate an LLM feature that uses account context in the prompt?"</b></summary>

**Initial Prompt.** An assistant answers "where's my order?" using order data injected into the prompt.

**L5 Answer.** "Take past conversations, fetch each user's orders, and run them through the new prompt."

**Why L5 Fails in Production.** Fetching orders *now* gives the model information it didn't have at the time of the conversation: delivered orders, later refunds. That's temporal leakage in the prompt, so the eval overstates accuracy.

**L7 Principal Defense.** "Treat prompt context as a feature vector with point-in-time semantics. Either log the rendered context with every production conversation and evaluate on exactly that, or reconstruct it with an as-of query at the conversation's timestamp. The same skew risks apply in production: the context service and the eval pipeline must use one definition of 'recent orders', the same staleness, and the same null handling. I'd also add a freshness check: answers about order state should cite the context timestamp, so staleness is visible."

**Bar-Raiser Follow-ups.**
- *"What's the cheapest fix?"* Log the rendered prompt context (redacted as needed) for a sample of conversations. It's the zero-skew eval set.
- *"Privacy?"* Log references or hashed IDs plus a point-in-time reconstruction path if raw context can't be stored.

</details>

<details><summary><b>Q8 · "Online features are an hour stale. Is that a problem?"</b></summary>

**Initial Prompt.** Batch materialization runs hourly.

**L5 Answer.** "An hour is fine for most features."

**Why L5 Fails in Production.** It might be fine for the product, but if training used exact as-of values, the model was trained on fresher information than it's served. That's skew, and it's worst for fast-moving features.

**L7 Principal Defense.** "Two consistent options. Either simulate the serving lag in training (as-of join at t − 1 h, so the model learns with the information it will actually have), or make serving fresher with streaming materialization for the features that move fast (tickets in the last hour, session activity). Which one depends on how much the model gains from fresh values: measure it by training both ways and comparing on a point-in-time test set. Freshness itself becomes a monitored metric per feature, with the TTL and the missing-value default identical on both paths."

**Bar-Raiser Follow-ups.**
- *"Which features need streaming?"* Those whose value changes within the staleness window for a meaningful share of requests, measured from the event log.

</details>

---

## 7. Invariants Checklist

- [ ] Training sets are built with point-in-time (as-of) joins; the pipeline asserts feature_ts ≤ label_ts.
- [ ] Train/test splits are by time (or by entity) for any time-ordered data.
- [ ] Every feature has one definition in a registry: transformation, units in the name, null/default semantics, TTL, owner, and when it's written.
- [ ] Training and serving share one feature implementation, or the model trains on logged serving features.
- [ ] Parity tests compare **independent** online and offline implementations, continuously, on a sample in production.
- [ ] Served feature vectors are logged (with model and feature versions) for a sample of requests; replay diffs run on a schedule.
- [ ] Per-feature distribution monitoring uses thresholds calibrated on each feature's noise, and triggers replay diffs.
- [ ] Embedding model version, normalization, dtype and dimension are stored with every index and head, and asserted at query time.
- [ ] Serving lag is either simulated in training or eliminated by streaming materialization.
- [ ] LLM evals use logged or point-in-time-reconstructed prompt context, never context re-fetched at eval time.

---

## 8. References

1. D. Sculley et al., *Hidden Technical Debt in Machine Learning Systems*, NeurIPS 2015. https://proceedings.neurips.cc/paper/2015/hash/86df7dcfd896fcaf2674f757a2463eba-Abstract.html
2. M. Zinkevich, *Rules of Machine Learning: Best Practices for ML Engineering* (training-serving skew; Rule #29). https://developers.google.com/machine-learning/guides/rules-of-ml
3. E. Breck, S. Cai, E. Nielsen, M. Salib, D. Sculley, *The ML Test Score: A Rubric for ML Production Readiness and Technical Debt Reduction*, IEEE Big Data 2017. https://research.google/pubs/the-ml-test-score-a-rubric-for-ml-production-readiness-and-technical-debt-reduction/
4. S. Kaufman, S. Rosset, C. Perlich, O. Stitelman, *Leakage in Data Mining: Formulation, Detection, and Avoidance*, ACM TKDD 6(4), 2012. https://doi.org/10.1145/2382577.2382579
5. J. Hermann, M. Del Balso, *Meet Michelangelo: Uber's Machine Learning Platform*, Uber Engineering, 2017. https://www.uber.com/blog/michelangelo-machine-learning-platform/
6. Feast documentation. https://docs.feast.dev/
7. Feast, *Point-in-time joins*. https://docs.feast.dev/getting-started/concepts/point-in-time-joins
8. pandas, `merge_asof`. https://pandas.pydata.org/docs/reference/api/pandas.merge_asof.html
9. E. Strickland, *Andrew Ng: Unbiggen AI* (interview on data-centric AI), IEEE Spectrum, 2022. https://spectrum.ieee.org/andrew-ng-data-centric-ai
