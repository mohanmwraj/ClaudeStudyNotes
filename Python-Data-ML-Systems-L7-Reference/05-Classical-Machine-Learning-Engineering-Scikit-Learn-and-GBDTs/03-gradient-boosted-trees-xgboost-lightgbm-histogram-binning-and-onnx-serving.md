# 05.3 · Gradient-Boosted Trees: XGBoost, LightGBM, Histogram Binning & ONNX Serving

> **Folder 05 · Classical Machine Learning Engineering: scikit-learn & GBDTs**
> **Measured on:** XGBoost 3.4.1 (CUDA build, CPU and **NVIDIA RTX 3050 Laptop GPU**), LightGBM 4.7.0, scikit-learn 1.9.1 `HistGradientBoostingClassifier`, onnxmltools 1.16.0, skl2onnx 1.20.0, ONNX 1.23.2, ONNX Runtime 1.31.1 (CPU provider), i5-11260H (6C/12T), Windows 11.
> **Design sources:** XGBoost paper and docs (`tree_method="hist"`, `device="cuda"`), the LightGBM paper (histogram, leaf-wise growth, GOSS/EFB), ONNX-ML operator spec (`TreeEnsembleClassifier`).

---

## 0. Orientation & the JVM/C++ Bridge

Gradient-boosted decision trees are still the default for tabular data in 2026. The modern implementations are fast because of one systems idea: **discretize every feature once into ≤ 256 bins (1 byte), then grow trees from per-bin gradient histograms**. Split finding goes from sorting n values per feature per node to summing into 256 buckets, with cache-resident uint8 data. Serving is a separate engineering problem (single-row latency, language portability, training/serving parity), and ONNX solves it with a portable graph and a C++ runtime.

| Concept | Python stack | JVM analogue | C++ analogue |
|---|---|---|---|
| Histogram GBDT | XGBoost `hist`, LightGBM, sklearn HGB | XGBoost4J / LightGBM JNI, Spark MLlib GBT (exact, slower) | the libraries are C++ |
| GPU training | XGBoost `device="cuda"`, LightGBM CUDA | XGBoost4J-Spark GPU | CUDA kernels |
| Portable model | ONNX (`TreeEnsembleClassifier`) | ONNX Runtime Java API | ONNX Runtime C/C++ API |
| Compiled trees | Treelite, lleaves (⚠ not run here) | — | generated C |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Boosting in one equation

Each round fits a tree to the loss's first and second derivatives (gradient gᵢ and Hessian hᵢ per row). For a candidate split of a node into L and R, XGBoost's gain is

```text
 gain = 1/2 [ G_L²/(H_L + λ) + G_R²/(H_R + λ) - (G_L + G_R)²/(H_L + H_R + λ) ] - γ
 where G = Σ g_i, H = Σ h_i over the rows in each child.  Leaf value = -G/(H + λ)
```

Everything per split is a **sum of g and h over rows**, which is exactly what a histogram computes.

### 1.2 Histogram construction

```text
 once per dataset (quantile sketch): feature j -> ≤255 bin edges; X (n x d, float32/64) -> B (n x d, uint8)
     500k x 30: float64 114 MiB / float32 57 MiB -> 14.3 MiB of bins (measured)
 per node, per feature: hist[b] = (Σ g_i, Σ h_i) for rows with B[i, j] == b    O(rows_in_node)
     best split = one left-to-right scan of 256 cumulative sums                   O(256), not a sort of n values
 histogram subtraction: hist(child_big) = hist(parent) - hist(child_small) -> build only the smaller child
 parallelism: OpenMP over features / row blocks (CPU); thread blocks per feature-bin on GPU
 missing values: each split learns a default direction (sent left or right) from the gradients
```

**`max_bin`** is the resolution knob. Measured: 16–64 bins trained fastest (5.5 s) with the same AUC as 256 (7.6 s); 1,024 bins took 12.6 s for no gain. Fewer bins also make data smaller and histograms more cache-friendly.

### 1.3 Growth policy and LightGBM extras

```text
 depth-wise (XGBoost default, sklearn HGB: max_depth / max_leaf_nodes): grow all nodes level by level
 leaf-wise / lossguide (LightGBM default; XGBoost grow_policy="lossguide"): split the leaf with max gain
   -> fewer leaves for the same loss, but deeper, riskier trees; cap with num_leaves / min_data_in_leaf
 LightGBM: GOSS (keep large-gradient rows, sample the rest), EFB (bundle mutually exclusive sparse features)
```

The listing uses lossguide with 63 leaves everywhere for a like-for-like comparison.

### 1.4 Serving trees: what ONNX does

```text
 model.onnx = protobuf graph: input "input" float[N, 30]
   -> TreeEnsembleClassifier (ai.onnx.ml): flattened arrays of node feature ids, thresholds, modes, child ids, leaf weights
   -> probabilities float[N, 2], label int64[N]
 ONNX Runtime: InferenceSession parses the graph once, allocates an arena, runs a C++ kernel per op
   intra_op_num_threads=1 for latency (no thread fan-out per request)
 float32 graph vs float64 native: max probability difference 2.6e-7 (LightGBM), 1.8e-7 (sklearn) measured
```

Converter pitfalls found here: onnxmltools declared the LightGBM `label` output with a fixed shape `[1]`, so ONNX Runtime warned on every batch until the dimension was patched to symbolic (`N`). skl2onnx needs an explicit `[None, 30]` input type for a dynamic batch. Validate exported signatures and outputs before shipping.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Histogram physics and four implementations of one job

```python
"""gbdt_histogram_physics.py - why histogram GBDTs are fast: 1-byte bins, gradient histograms, and the hardware.

A: quantile binning of 500k x 30 float64 into uint8 bins (what HGB/XGBoost-hist/LightGBM do before training).
B: the same boosting job in scikit-learn HGB, XGBoost hist (CPU and CUDA) and LightGBM: fit time and holdout AUC.
C: max_bin (histogram resolution) vs speed and accuracy.  D: thread scaling.
"""
import time
import warnings

import lightgbm as lgb
import numpy as np
import xgboost as xgb
from sklearn.datasets import make_classification
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split

warnings.filterwarnings("ignore")
X, y = make_classification(n_samples=625_000, n_features=30, n_informative=15, n_redundant=5, flip_y=0.05,
                           random_state=0)
X = X.astype(np.float32)
Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=0)
ROUNDS, LEAVES, LR = 200, 63, 0.1
print(f"train {Xtr.shape[0]:,} x {Xtr.shape[1]}, {ROUNDS} rounds, {LEAVES} leaves, lr {LR}")

print("== A. quantile binning to 255 bins per feature")
t0 = time.perf_counter()
edges = [np.quantile(Xtr[:, j], np.linspace(0, 1, 256)[1:-1]) for j in range(Xtr.shape[1])]
bins = np.empty(Xtr.shape, dtype=np.uint8)
for j, e in enumerate(edges):
    bins[:, j] = np.searchsorted(e, Xtr[:, j])
t_bin = time.perf_counter() - t0
print(f"  float64 {Xtr.size * 8 / 2**20:.1f} MiB / float32 {Xtr.nbytes / 2**20:.1f} MiB -> uint8 bins {bins.nbytes / 2**20:.1f} "
      f"MiB (8x / 4x smaller; one cache line holds 64 rows of a feature), binning {t_bin * 1e3:.0f} ms")
g = np.random.default_rng(0).standard_normal(Xtr.shape[0]).astype(np.float32)
t0 = time.perf_counter()
hist = np.bincount(bins[:, 0], weights=g, minlength=256)    # one split search = 256 sums, not a sort of 500k values
print(f"  gradient histogram of one feature: {(time.perf_counter() - t0) * 1e3:.1f} ms; best split scans "
      f"{hist.size} bins instead of sorting {Xtr.shape[0]:,} values")


def timed(fn):
    t0 = time.perf_counter()
    m = fn()
    return m, time.perf_counter() - t0


def auc_of(model, kind):
    if kind == "xgb":
        return roc_auc_score(yte, model.predict(xgb.DMatrix(Xte)))
    if kind == "lgb":
        return roc_auc_score(yte, model.predict(Xte))
    return roc_auc_score(yte, model.predict_proba(Xte)[:, 1])


def fit_xgb(device="cpu", max_bin=256, nthread=12):
    params = {"objective": "binary:logistic", "tree_method": "hist", "max_leaves": LEAVES, "grow_policy": "lossguide",
              "max_depth": 0, "eta": LR, "max_bin": max_bin, "device": device, "nthread": nthread}
    return xgb.train(params, xgb.DMatrix(Xtr, label=ytr), num_boost_round=ROUNDS)


def fit_lgb(max_bin=255, threads=12):
    params = {"objective": "binary", "num_leaves": LEAVES, "learning_rate": LR, "max_bin": max_bin,
              "num_threads": threads, "verbose": -1}
    return lgb.train(params, lgb.Dataset(Xtr, label=ytr, params={"max_bin": max_bin}), num_boost_round=ROUNDS)


def fit_hgb():
    return HistGradientBoostingClassifier(max_iter=ROUNDS, max_leaf_nodes=LEAVES, learning_rate=LR,
                                          early_stopping=False, random_state=0).fit(Xtr, ytr)


print("== B. same job, four implementations")
fit_xgb(device="cuda").predict(xgb.DMatrix(Xte[:10]))     # warm up the CUDA context outside the timing
results = {}
for label, fn, kind in [("scikit-learn HistGradientBoosting", fit_hgb, "skl"),
                        ("XGBoost hist, CPU 12 threads", fit_xgb, "xgb"),
                        ("XGBoost hist, CUDA (RTX 3050 Laptop)", lambda: fit_xgb(device="cuda"), "xgb"),
                        ("LightGBM, 12 threads", fit_lgb, "lgb")]:
    model, dt = timed(fn)
    results[label] = auc_of(model, kind)
    print(f"  {label:40} fit {dt:6.2f} s   holdout AUC {results[label]:.4f}")
assert max(results.values()) - min(results.values()) < 0.01

print("== C. max_bin: histogram resolution (XGBoost CPU)")
for mb in (16, 64, 256, 1024):
    model, dt = timed(lambda: fit_xgb(max_bin=mb))
    print(f"  max_bin={mb:>5}: fit {dt:6.2f} s   AUC {auc_of(model, 'xgb'):.4f}")

print("== D. thread scaling (LightGBM)")
base = None
for th in (1, 2, 4, 12):
    _, dt = timed(lambda: fit_lgb(threads=th))
    base = base or dt
    print(f"  num_threads={th:>2}: {dt:6.2f} s  ({base / dt:4.1f}x)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
train 500,000 x 30, 200 rounds, 63 leaves, lr 0.1
== A. quantile binning to 255 bins per feature
  float64 114.4 MiB / float32 57.2 MiB -> uint8 bins 14.3 MiB (8x / 4x smaller; one cache line holds 64 rows of a feature), binning 1561 ms
  gradient histogram of one feature: 3.6 ms; best split scans 256 bins instead of sorting 500,000 values
== B. same job, four implementations
  scikit-learn HistGradientBoosting        fit   9.50 s   holdout AUC 0.9731
  XGBoost hist, CPU 12 threads             fit   6.97 s   holdout AUC 0.9731
  XGBoost hist, CUDA (RTX 3050 Laptop)     fit   4.54 s   holdout AUC 0.9732
  LightGBM, 12 threads                     fit   4.81 s   holdout AUC 0.9729
== C. max_bin: histogram resolution (XGBoost CPU)
  max_bin=   16: fit   5.49 s   AUC 0.9732
  max_bin=   64: fit   5.46 s   AUC 0.9731
  max_bin=  256: fit   7.63 s   AUC 0.9731
  max_bin= 1024: fit  12.60 s   AUC 0.9731
== D. thread scaling (LightGBM)
  num_threads= 1:  16.54 s  ( 1.0x)
  num_threads= 2:   8.95 s  ( 1.8x)
  num_threads= 4:   6.25 s  ( 2.6x)
  num_threads=12:   4.77 s  ( 3.5x)
ALL ASSERTIONS PASSED
```

* All four implementations reach the same holdout AUC (0.973). The differences are systems differences. On 12 threads LightGBM (~4.3–4.8 s) and XGBoost-CUDA (~4.3–4.5 s) were fastest, then XGBoost CPU (~6–7 s) and scikit-learn HGB (~8.4–9.5 s).
* **The laptop GPU gave only ~1.4–1.5× over 12 CPU threads** at this size (500 k × 30). That covers host-to-device copies, a small dataset and a 4 GB entry-level GPU. GPU gains grow with rows, features and depth. Measure before buying GPUs for GBDTs.
* LightGBM scaled 3.5–3.6× from 1 to 12 threads, sublinear because histogram building is memory-bandwidth-bound and hyperthreads share cores.
* `max_bin=16` matched `max_bin=256` accuracy here at ~70 % of the time. For noisy real data the right resolution is a tuning decision, not a default.

### 2.2 Serving: native predict vs ONNX Runtime

```python
"""onnx_serving.py - export a LightGBM model and a scikit-learn pipeline to ONNX and serve them with ONNX Runtime.

Checks numerical agreement, then measures single-row latency (p50/p99 over 2,000 requests: the online-serving
case) and batch throughput (10,000 rows) for native predict vs onnxruntime InferenceSession.run.
"""
import time
import warnings

import lightgbm as lgb
import numpy as np
import onnxruntime as ort
from onnxmltools import convert_lightgbm
from onnxmltools.convert.common.data_types import FloatTensorType
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType as SklFloat
from sklearn.datasets import make_classification
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

warnings.filterwarnings("ignore")
X, y = make_classification(n_samples=100_000, n_features=30, n_informative=12, random_state=0)
X = X.astype(np.float32)
booster = lgb.train({"objective": "binary", "num_leaves": 63, "verbose": -1}, lgb.Dataset(X, label=y),
                    num_boost_round=200)
pipe = make_pipeline(StandardScaler(), LogisticRegression(max_iter=500)).fit(X, y)

lgb_onnx = convert_lightgbm(booster, initial_types=[("input", FloatTensorType([None, 30]))], zipmap=False)
skl_onnx = convert_sklearn(pipe, initial_types=[("input", SklFloat([None, 30]))],   # dynamic batch dimension
                           options={id(pipe): {"zipmap": False}})
declared = [d.dim_value or d.dim_param for d in lgb_onnx.graph.output[0].type.tensor_type.shape.dim]
dim = lgb_onnx.graph.output[0].type.tensor_type.shape.dim[0]
dim.ClearField("dim_value")
dim.dim_param = "N"                                          # converter declares label as [1]; the batch is dynamic
print(f"onnxmltools LightGBM export declared output 'label' with shape {declared}; patched to ['N']")
opts = ort.SessionOptions()
opts.intra_op_num_threads = 1                                # latency-oriented: no intra-op thread fan-out
sess_lgb = ort.InferenceSession(lgb_onnx.SerializeToString(), opts, providers=["CPUExecutionProvider"])
sess_skl = ort.InferenceSession(skl_onnx.SerializeToString(), opts, providers=["CPUExecutionProvider"])
in_lgb, in_skl = sess_lgb.get_inputs()[0].name, sess_skl.get_inputs()[0].name
print(f"onnxruntime {ort.__version__}; LightGBM 200 trees -> {len(lgb_onnx.SerializeToString()) / 2**20:.1f} MiB ONNX; "
      f"sklearn pipeline -> {len(skl_onnx.SerializeToString()) / 1024:.1f} KiB ONNX")
print(f"  LightGBM ONNX ops: {sorted({n.op_type for n in lgb_onnx.graph.node})}")
print(f"  sklearn  ONNX ops: {sorted({n.op_type for n in skl_onnx.graph.node})}")

probe = X[:5_000]
d_lgb = np.abs(sess_lgb.run(None, {in_lgb: probe})[1][:, 1] - booster.predict(probe)).max()
d_skl = np.abs(sess_skl.run(None, {in_skl: probe})[1][:, 1] - pipe.predict_proba(probe)[:, 1]).max()
print(f"  max |ONNX - native| probability: LightGBM {d_lgb:.2e}, sklearn {d_skl:.2e} (float32 graph vs float64 native)")
assert d_lgb < 1e-4 and d_skl < 1e-4


def latency(fn, rows):
    for i in range(200):
        fn(rows[i:i + 1])
    t = []
    for i in range(2000):
        r = rows[i:i + 1]
        t0 = time.perf_counter()
        fn(r)
        t.append(time.perf_counter() - t0)
    t = np.sort(np.array(t)) * 1e6
    return t[len(t) // 2], t[int(len(t) * 0.99)]


def throughput(fn, rows):
    fn(rows)
    t0 = time.perf_counter()
    fn(rows)
    return rows.shape[0] / (time.perf_counter() - t0)


cases = [("LightGBM native Booster.predict", lambda r: booster.predict(r, num_threads=1)),
         ("LightGBM via ONNX Runtime", lambda r: sess_lgb.run(None, {in_lgb: r})),
         ("sklearn pipeline predict_proba", lambda r: pipe.predict_proba(r)),
         ("sklearn pipeline via ONNX Runtime", lambda r: sess_skl.run(None, {in_skl: r}))]
print(f"{'model / runtime':38} {'p50 1-row':>10} {'p99 1-row':>10} {'batch rows/s':>14}")
for label, fn in cases:
    p50, p99 = latency(fn, X)
    print(f"  {label:36} {p50:8.1f}us {p99:8.1f}us {throughput(fn, X[:10_000]):14,.0f}")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
onnxmltools LightGBM export declared output 'label' with shape [1]; patched to ['N']
onnxruntime 1.31.1; LightGBM 200 trees -> 0.9 MiB ONNX; sklearn pipeline -> 1.0 KiB ONNX
  LightGBM ONNX ops: ['Cast', 'Identity', 'Mul', 'TreeEnsembleClassifier']
  sklearn  ONNX ops: ['LinearClassifier', 'Scaler']
  max |ONNX - native| probability: LightGBM 2.58e-07, sklearn 1.79e-07 (float32 graph vs float64 native)
model / runtime                         p50 1-row  p99 1-row   batch rows/s
  LightGBM native Booster.predict          48.7us     86.2us         66,733
  LightGBM via ONNX Runtime                29.8us     39.9us        114,280
  sklearn pipeline predict_proba          254.6us    368.5us      7,312,614
  sklearn pipeline via ONNX Runtime        15.9us     20.9us      8,086,689
ALL ASSERTIONS PASSED
```

| Model | Native p50 (1 row) | ONNX Runtime p50 (1 row) | Native batch | ORT batch |
|---|---:|---:|---:|---:|
| LightGBM, 200 trees | ~45–49 µs | **~26–30 µs** | ~67–77 k rows/s | **~114–143 k rows/s** |
| sklearn scaler + logistic | ~220–255 µs | **~13–16 µs** | ~7.3–7.9 M rows/s | ~8.1–9.6 M rows/s |

* For single-row online scoring, **scikit-learn's per-call Python overhead (input validation, dispatch) dominates**: 15–17× slower than the same math in ONNX Runtime. In batch the gap closes, because the work is in NumPy.
* ONNX Runtime also roughly doubled LightGBM throughput on one thread, and it serves from C++, Java, C# or JavaScript with the same artifact, which removes training/serving skew by construction.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 ⚡ | Training slower than expected on a big box | Threads idle or oversubscribed | `nthread` default vs container CPU limit; nested joblib (05.1) | Set `nthread`/`num_threads` to the CPU quota | Thread budget per job |
| F2 | GPU training no faster than CPU | Small data; PCIe copies dominate | Problem too small for the GPU | Stay on CPU, or batch many models per GPU; larger data on GPU | Benchmark at production size (1.4–1.5× here) |
| F3 🔥 | Model degrades after a feature-distribution shift | Many rows hit extreme bins | Bin edges fixed at training; out-of-range values collapse into end bins | Retrain on fresh data; monitor feature drift | Drift monitors per feature |
| F4 🔥 | ONNX model returns wrong shapes or warns per batch | `Expected shape ... {1} does not match ...` | Converter declared static output dims | Patch to symbolic dims; specify `initial_types` with `None` batch | Signature tests on export |
| F5 🔥 | Online predictions differ slightly from offline | 1e-7 differences flip decisions at a threshold | float32 ONNX graph vs float64 native training | Accept and test tolerance; thresholds with margin; keep float32 end to end | Golden-file parity tests with tolerance |
| F6 | Overfitting with LightGBM defaults on small data | Train ≫ validation; very deep trees | Leaf-wise growth with large `num_leaves` | `min_data_in_leaf`, `max_depth`, lower `num_leaves`, early stopping | Validation curves in training reports |
| F7 ⚡ | p99 latency spikes in a scoring service | Thread pools per request | ORT intra-op threads × request concurrency | `intra_op_num_threads=1`, one session per process, process-level parallelism | Load-test under production concurrency |
| F8 | Categorical handling inconsistent across libraries | Different results for the same model spec | Native categorical splits (LightGBM/XGBoost) vs one-hot vs ordinal | Choose one encoding and export it consistently | Document categorical handling in the model card |

**Debugging toolkit.** `xgb.Booster.get_dump()` / `trees_to_dataframe()`, `lgb.Booster.dump_model()`, `feature_importance(importance_type="gain")`, and SHAP via `pred_contribs=True` (XGBoost) / `pred_contrib=True` (LightGBM). For ONNX, `onnx.checker.check_model`, `[(o.name, o.shape) for o in session.get_outputs()]` and `onnxruntime.SessionOptions().enable_profiling`.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why are histogram GBDTs 10× faster than the exact algorithm?"</b></summary>

**Initial Prompt.** Explain XGBoost `hist` vs `exact` at the level of memory and CPU.

**L5 Answer.** "They approximate splits, so they do less work."

**Why L5 Crashes at Scale.** "Approximate" suggests a quality trade-off and hides the systems win, which comes from data layout and memory traffic, not just fewer candidate splits.

**L7 Principal Defense.** Exact split finding needs feature values sorted per node, which means random access to float columns and O(n log n) work. `hist` quantizes each feature once into ≤ 256 bins stored as uint8: 4–8× less memory than float32/64 (14.3 MiB against 57–114 MiB measured), with one cache line holding 64 rows of a feature. Then, per node, it sums gradients into 256 buckets in one sequential pass, and split search scans those 256 cumulative sums (measured: 3 ms to histogram 500 k rows of one feature). The subtraction trick builds only the smaller child. Accuracy is usually indistinguishable (`max_bin` 16 → 1,024 all gave AUC 0.973 here), and the speedup comes from bandwidth and cache efficiency.

</details>

<details><summary><b>Q2 · "Should we buy GPUs for our GBDT training?"</b></summary>

**Initial Prompt.** Nightly XGBoost retraining on 2 M rows × 200 features takes 40 minutes on CPU.

**L5 Answer.** "Yes. GPUs are always faster for ML."

**Why L5 Crashes at Scale.** For GBDTs the GPU win depends on size and shape. Measured at 500 k × 30 on a laptop RTX 3050: only ~1.4–1.5× over 12 CPU threads. Host-to-device transfer and kernel launch overhead dominate small problems, while big wide datasets with deep trees can see 5–20× on datacenter GPUs.

**L7 Principal Defense.** First fix CPU efficiency: right thread count, `max_bin` tuning (16–64 matched 256 here at ~70 % of the time), early stopping, feature selection. Then benchmark `device="cuda"` on the real dataset and hyperparameters, end to end including data loading. If retraining runs many models (hyperparameter search, per-segment models), a GPU's throughput across concurrent jobs often matters more than single-model speed. Decide on cost per trained model, not peak speedup.

</details>

<details><summary><b>Q3 · "Serving a scikit-learn model takes 250 µs per request. The math is a dot product. Why?"</b></summary>

**Initial Prompt.** A logistic regression behind an API has p50 220–255 µs per single-row prediction.

**L5 Answer.** "Python is slow; rewrite the service in Go."

**Why L5 Crashes at Scale.** Rewriting the service while reimplementing preprocessing in another language invites training/serving skew, and the cost isn't "Python" in general. It's scikit-learn's per-call validation and dispatch around a 30-element dot product.

**L7 Principal Defense.** Export the fitted pipeline to ONNX (skl2onnx) and serve it with ONNX Runtime: measured ~13–16 µs p50 for the same scaler + logistic pipeline, 15–17×, with probabilities within 1.8e-7. Use one `InferenceSession` per process with `intra_op_num_threads=1`, and scale with processes. ONNX Runtime has Java, C#, C++ and JavaScript APIs, so the same artifact serves anywhere. Keep a parity test on a golden dataset at every release.

</details>

<details><summary><b>Q4 · "LightGBM or XGBoost?"</b></summary>

**Initial Prompt.** Standardize the team's GBDT library.

**L5 Answer.** "LightGBM, because it's faster."

**Why L5 Crashes at Scale.** On this benchmark, with the same leaf-wise settings, LightGBM and XGBoost-CPU differed by ~1.5× and reached identical AUC. The bigger differences are operational: categorical handling, GPU support, distributed training integrations, ONNX converter quality and model-format stability.

**L7 Principal Defense.** Choose by ecosystem fit and keep the training config portable. XGBoost has strong CUDA support (measured working on this laptop's GPU), Spark/Dask/Ray integrations and a stable JSON model format. LightGBM is fast on CPU, with native categoricals and GOSS/EFB for very wide sparse data. Both convert to ONNX (watch the converter quirks, F4). Benchmark both on your data with matched growth policies (lossguide, equal leaves) and pick on the cost-quality-latency triple.

</details>

<details><summary><b>Q5 · "What does `max_bin` trade off?"</b></summary>

**Initial Prompt.** A team sets `max_bin=1024` "for accuracy".

**L5 Answer.** "More bins means more precise splits, so better accuracy."

**Why L5 Crashes at Scale.** Measured: 1,024 bins took 12.6 s against 5.5 s at 16–64 bins with *no* AUC change. Finer bins increase histogram size (more memory traffic per node), and with noisy features they can overfit split thresholds.

**L7 Principal Defense.** `max_bin` sets the precision of candidate thresholds against histogram cost. Gradient boosting compensates for coarse thresholds over many trees, so 64–256 is usually enough. Tune it like any hyperparameter on validation data and watch training time. Also, bins are fixed at training time, so drifted features pile into the end bins (F3); monitor feature distributions against training quantiles.

</details>

<details><summary><b>Q6 · "How do you guarantee the model in production is the model you validated?"</b></summary>

**Initial Prompt.** Training in Python, serving in a Java service, retrained weekly.

**L5 Answer.** "Save the model with pickle and load it in the service."

**Why L5 Crashes at Scale.** Pickles are Python-only, version-fragile and a security risk (arbitrary code on load). Reimplementing scoring in Java drifts silently.

**L7 Principal Defense.** Ship one portable artifact: ONNX for trees and pipelines (or the library's JSON format with its native runtime), versioned with its feature schema and a golden input/output file. CI runs the golden file through ONNX Runtime and asserts tolerance (1e-6 here, since float32 vs float64 differences were ~2e-7). It also asserts output signatures (catching the static `[1]` label dim found here) and records latency. The service loads only artifacts that passed, and logs the model hash with each prediction.

</details>

<details><summary><b>Q7 · "Why did 12 threads give only 3.5× over 1 thread in LightGBM?"</b></summary>

**Initial Prompt.** Thread scaling: 16.5 s at 1 thread, 4.8 s at 12.

**L5 Answer.** "Python overhead."

**Why L5 Crashes at Scale.** There's no Python in the training loop. The limits are hardware and algorithmic, and misattributing them leads to useless optimizations.

**L7 Principal Defense.** Histogram construction streams uint8 bins and gradient arrays: it's memory-bandwidth-bound once a few cores saturate DRAM. The 12 "threads" are 6 physical cores with hyperthreading, sharing execution units and caches. Per-iteration serial parts (gradient computation, tree finalization) cap speedup by Amdahl's law. Expect 3–4× on this class of laptop. On servers, scaling continues further with more memory channels. Benchmark threads per job and run several jobs in parallel when cores are plentiful.

</details>

<details><summary><b>Q8 · "Should we compile trees to native code (Treelite/lleaves) instead of ONNX?"</b></summary>

**Initial Prompt.** A latency-critical service needs < 10 µs p99 for a 500-tree model.

**L5 Answer.** "ONNX is always the best serving option."

**Why L5 Crashes at Scale.** ONNX Runtime interprets the tree ensemble from flattened arrays (measured ~26–30 µs p50 for 200 trees). For extreme latency budgets, compiling trees into branchy native code can be faster, at the cost of build complexity and per-model compilation.

**L7 Principal Defense.** Pick by budget. ONNX Runtime for portability and good latency (tens of µs). Compiled trees (Treelite to C, lleaves via LLVM; ⚠ not benchmarked here) when single-digit µs matters and the platform is fixed. Batch requests when throughput matters more than single-row latency (ORT reached ~114–143 k rows/s on one thread). Either way, validate parity against the training model, and prune trees (fewer and shallower trees via early stopping) before micro-optimizing the runtime.

</details>

---

## 5. Invariants Checklist

- [ ] Histogram GBDTs quantize features once to ≤ 256 bins (1 byte) and grow trees from per-bin (Σg, Σh) sums.
- [ ] Split gain and leaf values are functions of gradient/Hessian sums; histograms compute exactly those.
- [ ] `max_bin` trades threshold precision for histogram cost. 16–256 matched here, and 1,024 was 2× slower for nothing.
- [ ] GPU training helps with size. On 500 k × 30 the laptop GPU was only ~1.4–1.5× faster than 12 CPU threads.
- [ ] Thread scaling is bandwidth-limited (3.5× on 6C/12T). Set threads to the CPU quota.
- [ ] Serve through ONNX Runtime for portability and latency: 15–17× faster single-row than scikit-learn, ~2× faster LightGBM.
- [ ] Validate exported signatures (dynamic batch dims) and parity (float32 vs float64 tolerance) on every release.

---

## 6. References

- T. Chen, C. Guestrin, "XGBoost: A Scalable Tree Boosting System", KDD 2016, DOI 10.1145/2939672.2939785.
- G. Ke et al., "LightGBM: A Highly Efficient Gradient Boosting Decision Tree", NeurIPS 2017 — https://papers.nips.cc/paper/6907-lightgbm-a-highly-efficient-gradient-boosting-decision-tree
- XGBoost tree methods (`hist`, GPU) — https://xgboost.readthedocs.io/en/stable/treemethod.html
- XGBoost GPU support (`device="cuda"`) — https://xgboost.readthedocs.io/en/stable/gpu/index.html
- LightGBM parameters tuning — https://lightgbm.readthedocs.io/en/latest/Parameters-Tuning.html
- scikit-learn histogram-based gradient boosting — https://scikit-learn.org/stable/modules/ensemble.html#histogram-based-gradient-boosting
- ONNX-ML operators (`TreeEnsembleClassifier`) — https://onnx.ai/onnx/operators/onnx_aionnxml_TreeEnsembleClassifier.html
- ONNX Runtime Python API — https://onnxruntime.ai/docs/api/python/api_summary.html
- skl2onnx — https://onnx.ai/sklearn-onnx/
- onnxmltools (LightGBM/XGBoost converters) — https://github.com/onnx/onnxmltools
- Treelite — https://treelite.readthedocs.io/
