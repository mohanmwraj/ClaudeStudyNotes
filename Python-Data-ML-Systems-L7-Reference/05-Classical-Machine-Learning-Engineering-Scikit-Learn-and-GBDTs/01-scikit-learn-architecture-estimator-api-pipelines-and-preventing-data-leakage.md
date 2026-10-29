# 05.1 · scikit-learn Architecture: the Estimator API, Pipelines & Preventing Data Leakage

> **Folder 05 · Classical Machine Learning Engineering: scikit-learn & GBDTs**
> **Measured on:** scikit-learn 1.9.1, NumPy 2.5.4, SciPy 1.18.1, threadpoolctl, CPython 3.14.5, i5-11260H (6C/12T), Windows 11.
> **Design sources:** the scikit-learn developer guide (estimator API, `clone`, `get_params`), the Common pitfalls guide (data leakage), joblib and threadpoolctl documentation.

---

## 0. Orientation & the JVM/C++ Bridge

scikit-learn is less a bag of algorithms than a **contract**. Every estimator stores hyperparameters verbatim in `__init__`, learns state in `fit` (attributes ending in `_`) and exposes `transform`/`predict`. That contract is what lets `Pipeline`, `ColumnTransformer`, `GridSearchCV` and `clone` compose arbitrary steps, and it's also the tool that prevents data leakage. Anything that learns from data, a scaler's mean included, must be refit inside each training fold, and only a pipeline guarantees that.

| Concept | scikit-learn | JVM analogue | C++ analogue |
|---|---|---|---|
| Estimator | object with `fit`/`predict`/`transform`, params in `__init__` | Spark ML `Estimator` → `Model` | mlpack / Shark models |
| Hyperparameters vs state | `get_params()` vs `attr_` (fitted) | `Params` vs fitted `Model` | config struct vs trained weights |
| Composition | `Pipeline`, `ColumnTransformer`, `FeatureUnion` | Spark ML `Pipeline` | — |
| Model selection | `GridSearchCV`, `cross_validate` with splitters | `CrossValidator`, `TrainValidationSplit` | — |
| Parallelism | joblib (processes or threads) + OpenMP/BLAS threads inside estimators | Spark tasks | OpenMP / TBB |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The estimator contract

```text
 __init__(**hyperparams): store them as attributes, unmodified, no validation, no data
 get_params(deep=True)  : introspect __init__ signature -> {"C": 1.0, ...}; nested "step__param" names
 set_params(**p)        : what GridSearchCV calls for each candidate
 fit(X, y)              : validate, learn, set attributes with a trailing underscore (coef_, n_features_in_)
                          -> return self
 clone(est)             : new object of the same class with the same PARAMS and NO fitted state
 check_is_fitted(est)   : looks for trailing-underscore attributes
```

`GridSearchCV` doesn't reuse estimators across folds. It `clone`s them (measured: the clone keeps `C=2.0` but has no `coef_`) and refits per fold and candidate. That's the mechanism that keeps one fold's learned state out of another, as long as every learning step is *inside* the cloned object, which means inside the pipeline.

### 1.2 Pipeline and ColumnTransformer execution

```text
 Pipeline([("prep", ColumnTransformer([...])), ("clf", Model())]).fit(X_train, y_train)
   prep.fit_transform(X_train)   each sub-transformer fits ONLY on the training rows of this fold
     num: StandardScaler on [amount, age]       -> mean_, scale_
     cat: OneHotEncoder on [country, device]    -> categories_
     hstack outputs (sparse or dense; pandas if set_output(transform="pandas"))
   clf.fit(Xt, y_train)
 Pipeline.predict(X_test): prep.transform(X_test) (no refitting) -> clf.predict
 Pipeline(memory=joblib.Memory(dir)): caches fit_transform of each step, keyed by a hash of (step params, inputs)
```

`set_output(transform="pandas")` keeps column names through the pipeline (`num__amount`, `cat__country_DE`, …), the difference between debuggable feature importances and anonymous columns. `handle_unknown="ignore"` turns unseen categories into all-zero one-hot columns instead of an exception at serving time.

### 1.3 Data leakage: anything fitted on rows the model is evaluated on

| Leak | Mechanism | Measured inflation |
|---|---|---|
| Feature selection before CV | `SelectKBest` sees labels of the test folds and picks noise that correlates by chance | accuracy **0.845 on random labels** vs 0.605 inside the pipeline |
| Shuffled K-fold on temporal data | test rows have neighbours in time in the training fold; the model interpolates | ROC-AUC **0.973 vs 0.503** with `TimeSeriesSplit` |
| Entity overlap | the same user in train and test; the model memorizes a per-user fingerprint | ROC-AUC **0.770 vs 0.483** with `GroupKFold` |
| Target encoding fit on training rows | each row's encoding contains its own label | train − holdout AUC gap 0.145 vs 0.038 cross-fitted (05.2) |

The rule: the splitter must match how the model will be used (future data → time-based, new entities → group-based), and every data-dependent transformation must live inside the object that gets cloned per fold.

### 1.4 Parallelism: two layers that multiply

```text
 GridSearchCV(n_jobs=4)        -> joblib, loky backend: 4 worker PROCESSES (data pickled or memory-mapped to workers)
   each fit: HistGradientBoosting -> OpenMP threads (default: all cores) over features/rows
             numpy/scipy BLAS     -> OpenBLAS threads
 4 processes x 12 OpenMP threads = 48 runnable threads on 12 logical cores -> oversubscription
 threadpoolctl.threadpool_limits(limits=k, user_api="openmp") caps the inner layer
```

Measured on 8 candidates × 3 folds: `n_jobs=1` with 12 OpenMP threads took 16.3 s; `n_jobs=4` with 12 threads each took 13.6 s (oversubscribed); `n_jobs=4` with 3 threads each took **10.2 s**. Size `outer × inner ≈ cores`.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Three leaks, reproduced and fixed

```python
"""sklearn_leakage_lab.py - three ways a cross-validation score lies, each reproduced and then fixed.

A: selection bias - feature selection fit on ALL data before CV finds "signal" in pure noise.
B: temporal leakage - shuffled K-fold on time-dependent data interpolates; TimeSeriesSplit must extrapolate.
C: group leakage - rows of the same entity in train and test; GroupKFold keeps entities disjoint.
"""
import warnings

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.feature_selection import SelectKBest, f_classif
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GroupKFold, KFold, TimeSeriesSplit, cross_val_score
from sklearn.pipeline import make_pipeline

warnings.filterwarnings("ignore")
rng = np.random.default_rng(0)

print("== A. selection bias: 200 samples, 10,000 pure-noise features, random labels")
X = rng.standard_normal((200, 10_000))
y = rng.integers(0, 2, 200)
leaky_X = SelectKBest(f_classif, k=20).fit_transform(X, y)          # looked at the labels of every row
leaky = cross_val_score(LogisticRegression(max_iter=1000), leaky_X, y, cv=5).mean()
honest = cross_val_score(make_pipeline(SelectKBest(f_classif, k=20), LogisticRegression(max_iter=1000)),
                         X, y, cv=5).mean()
print(f"  select on all rows, then CV        : accuracy {leaky:.3f}   <- labels are coin flips")
print(f"  Pipeline(select, model) inside CV : accuracy {honest:.3f}")
assert leaky > 0.8 and abs(honest - 0.5) < 0.15

print("== B. temporal leakage: label regime drifts over time; features = (t, noise)")
n = 6_000
t = np.arange(n)
regime = np.sin(t / 300.0)
Xt = np.column_stack([t, rng.standard_normal(n)])
yt = (regime + 0.3 * rng.standard_normal(n) > 0).astype(int)
model = HistGradientBoostingClassifier(max_iter=100)
shuffled = cross_val_score(model, Xt, yt, cv=KFold(5, shuffle=True, random_state=0), scoring="roc_auc").mean()
forward = cross_val_score(model, Xt, yt, cv=TimeSeriesSplit(5), scoring="roc_auc").mean()
print(f"  KFold(shuffle=True)  ROC-AUC {shuffled:.3f}   <- neighbours of every test row are in train")
print(f"  TimeSeriesSplit      ROC-AUC {forward:.3f}   <- what predicting the future actually scores")
assert shuffled > forward + 0.1

print("== C. group leakage: 400 users x 15 rows; each user has a fingerprint feature and a personal label rate")
users = np.repeat(np.arange(400), 15)
fingerprint = rng.standard_normal((400, 4))[users]                  # identifies the user, not the outcome
user_rate = rng.random(400)[users]
yg = (rng.random(users.size) < user_rate).astype(int)
Xg = np.column_stack([fingerprint, rng.standard_normal(users.size)])
gb = HistGradientBoostingClassifier(max_iter=200)
by_row = cross_val_score(gb, Xg, yg, cv=KFold(5, shuffle=True, random_state=0), scoring="roc_auc").mean()
by_user = cross_val_score(gb, Xg, yg, cv=GroupKFold(5), groups=users, scoring="roc_auc").mean()
print(f"  KFold by row  ROC-AUC {by_row:.3f}   <- memorized users")
print(f"  GroupKFold    ROC-AUC {by_user:.3f}   <- new users: the fingerprint says nothing")
assert by_row > by_user + 0.1
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. selection bias: 200 samples, 10,000 pure-noise features, random labels
  select on all rows, then CV        : accuracy 0.845   <- labels are coin flips
  Pipeline(select, model) inside CV : accuracy 0.605
== B. temporal leakage: label regime drifts over time; features = (t, noise)
  KFold(shuffle=True)  ROC-AUC 0.973   <- neighbours of every test row are in train
  TimeSeriesSplit      ROC-AUC 0.503   <- what predicting the future actually scores
== C. group leakage: 400 users x 15 rows; each user has a fingerprint feature and a personal label rate
  KFold by row  ROC-AUC 0.770   <- memorized users
  GroupKFold    ROC-AUC 0.483   <- new users: the fingerprint says nothing
ALL ASSERTIONS PASSED
```

Each "leaky" number would pass a code review as a great result. The fixes are structural: the pipeline puts selection inside CV, `TimeSeriesSplit` matches the forecasting use, and `GroupKFold` matches "new users". On only 200 samples the honest pipeline still scored 0.605 by chance; the leaky version claims 0.845 on coin flips.

### 2.2 The contract, ColumnTransformer, caching and thread limits

```python
"""sklearn_pipeline_internals.py - the estimator contract, ColumnTransformer plumbing, caching, and thread limits.

A: get_params/set_params/clone: hyperparameters vs fitted state (trailing underscore).
B: ColumnTransformer + set_output(transform="pandas"): named, typed outputs instead of anonymous arrays.
C: Pipeline(memory=...) caching transformers across a grid search: a loss for cheap steps, a win for expensive ones.
D: nested parallelism: GridSearchCV(n_jobs) x OpenMP threads inside each fit, with and without threadpoolctl.
"""
import os
import shutil
import tempfile
import time
import warnings

import numpy as np
import pandas as pd
from joblib import Memory
from sklearn import clone
from sklearn.compose import ColumnTransformer
from sklearn.decomposition import PCA
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.exceptions import NotFittedError
from sklearn.kernel_approximation import Nystroem
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.utils.validation import check_is_fitted
from threadpoolctl import threadpool_info, threadpool_limits

warnings.filterwarnings("ignore")
rng = np.random.default_rng(0)

print("== A. the estimator contract")
lr = LogisticRegression(C=0.5, max_iter=200)
print(f"  get_params()['C'] = {lr.get_params()['C']}; set_params(C=2.0) -> {lr.set_params(C=2.0).C}")
try:
    check_is_fitted(lr)
except NotFittedError:
    print("  check_is_fitted before fit -> NotFittedError")
X = rng.standard_normal((500, 5))
y = (X[:, 0] > 0).astype(int)
lr.fit(X, y)
twin = clone(lr)
print(f"  after fit: coef_ shape {lr.coef_.shape}; clone(lr) keeps C={twin.C} but has coef_: {hasattr(twin, 'coef_')}")
assert not hasattr(twin, "coef_")

print("== B. ColumnTransformer with pandas output and feature names")
df = pd.DataFrame({"amount": rng.random(1000) * 100, "age": rng.integers(18, 80, 1000),
                   "country": rng.choice(["US", "IN", "DE"], 1000), "device": rng.choice(["ios", "android"], 1000)})
ct = ColumnTransformer([("num", StandardScaler(), ["amount", "age"]),
                        ("cat", OneHotEncoder(sparse_output=False, handle_unknown="ignore"), ["country", "device"])])
ct.set_output(transform="pandas")
out = ct.fit_transform(df)
print(f"  output type {type(out).__name__}, columns {list(out.columns)}")
unseen = ct.transform(df.head(1).assign(country="BR"))
print(f"  unseen category 'BR' with handle_unknown='ignore' -> all-zero country columns: "
      f"{unseen.filter(like='country').to_numpy().tolist()}")

print("== C. Pipeline(memory=...) across a 6-point grid x 3 folds: when caching pays")
Xc = rng.standard_normal((20_000, 300))
yc = (Xc[:, :5].sum(1) > 0).astype(int)
grid = {"clf__C": [0.01, 0.1, 1.0, 10.0, 100.0, 1000.0]}
for tname, make_tr in (("cheap: PCA(50)", lambda: PCA(n_components=50, random_state=0)),
                       ("expensive: Nystroem(800)", lambda: Nystroem(n_components=800, random_state=0))):
    times = {}
    for label, cached in (("no cache", False), ("joblib.Memory cache", True)):
        cache_dir = tempfile.mkdtemp()
        pipe = Pipeline([("tr", make_tr()), ("clf", LogisticRegression(max_iter=300))],
                        memory=Memory(cache_dir, verbose=0) if cached else None)
        t0 = time.perf_counter()
        GridSearchCV(pipe, grid, cv=3, n_jobs=1).fit(Xc, yc)
        times[label] = time.perf_counter() - t0
        shutil.rmtree(cache_dir, ignore_errors=True)
    print(f"  {tname:26} no cache {times['no cache']:6.2f} s (18 transformer fits)   cached "
          f"{times['joblib.Memory cache']:6.2f} s (3 fits + hashing ~46 MB per call)")

print("== D. nested parallelism: 4 joblib workers x OpenMP threads per HistGradientBoosting fit")
Xd = rng.standard_normal((60_000, 40))
yd = (Xd[:, :3].sum(1) + 0.5 * rng.standard_normal(60_000) > 0).astype(int)
gs_grid = {"learning_rate": [0.05, 0.1, 0.2, 0.3], "max_leaf_nodes": [15, 31]}
omp = [p for p in threadpool_info() if p["user_api"] == "openmp"]
print(f"  OpenMP runtime threads available: {omp[0]['num_threads'] if omp else 'n/a'}; cores: {os.cpu_count()}")


def search(n_jobs, omp_threads=None):
    gs = GridSearchCV(HistGradientBoostingClassifier(max_iter=100, early_stopping=False), gs_grid, cv=3,
                      n_jobs=n_jobs)
    t0 = time.perf_counter()
    if omp_threads is None:
        gs.fit(Xd, yd)
    else:
        with threadpool_limits(limits=omp_threads, user_api="openmp"):
            gs.fit(Xd, yd)
    return time.perf_counter() - t0


for label, n_jobs, omp_threads in [("n_jobs=1, all OpenMP threads per fit", 1, None),
                                   ("n_jobs=4, all OpenMP threads per fit", 4, None),
                                   ("n_jobs=4, 3 OpenMP threads per fit", 4, 3)]:
    print(f"  {label:40} {search(n_jobs, omp_threads):6.2f} s")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. the estimator contract
  get_params()['C'] = 0.5; set_params(C=2.0) -> 2.0
  check_is_fitted before fit -> NotFittedError
  after fit: coef_ shape (1, 5); clone(lr) keeps C=2.0 but has coef_: False
== B. ColumnTransformer with pandas output and feature names
  output type DataFrame, columns ['num__amount', 'num__age', 'cat__country_DE', 'cat__country_IN', 'cat__country_US', 'cat__device_android', 'cat__device_ios']
  unseen category 'BR' with handle_unknown='ignore' -> all-zero country columns: [[0.0, 0.0, 0.0]]
== C. Pipeline(memory=...) across a 6-point grid x 3 folds: when caching pays
  cheap: PCA(50)             no cache   1.15 s (18 transformer fits)   cached   1.50 s (3 fits + hashing ~46 MB per call)
  expensive: Nystroem(800)   no cache  13.65 s (18 transformer fits)   cached   8.90 s (3 fits + hashing ~46 MB per call)
== D. nested parallelism: 4 joblib workers x OpenMP threads per HistGradientBoosting fit
  OpenMP runtime threads available: 12; cores: 12
  n_jobs=1, all OpenMP threads per fit      16.27 s
  n_jobs=4, all OpenMP threads per fit      13.58 s
  n_jobs=4, 3 OpenMP threads per fit        10.15 s
ALL ASSERTIONS PASSED
```

* **Caching is not free.** `joblib.Memory` hashes each step's inputs (~46 MB here) on every call. For a cheap PCA it made the search *slower* (1.15 → 1.50 s). For an expensive Nystroem transformer it saved ~35 % (13.7 → 8.9 s). Cache only steps whose fit costs much more than hashing their input.
* **Nested parallelism needs a budget.** Capping inner OpenMP threads (3 per worker × 4 workers) beat both serial and oversubscribed configurations.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Offline metrics great, production poor | CV ≫ live performance | Leakage: preprocessing or selection fit outside CV; wrong splitter | Everything in a `Pipeline`; time/group splitters | Leakage checklist in model review; a shuffled-label sanity check (should score chance) |
| F2 🔥 | Model breaks on new category values | `ValueError: Found unknown categories` in serving | Encoder fit without `handle_unknown` | `handle_unknown="ignore"` / `"infrequent_if_exist"` | Contract tests with unseen values |
| F3 ⚡ | Grid search slower with `n_jobs=-1` | Load average ≫ cores | Joblib processes × OpenMP/BLAS threads oversubscribe | `threadpool_limits` or `n_jobs` × threads ≈ cores | Document the thread budget per job |
| F4 | Custom estimator breaks `GridSearchCV`/`clone` | Params lost, or state leaking between folds | `__init__` modifies or validates params, or fits in `__init__` | Store params verbatim; learn only in `fit` | `sklearn.utils.estimator_checks.check_estimator` in CI |
| F5 | Feature importances unreadable | `x17` style names | NumPy outputs from transformers | `set_output(transform="pandas")`, `get_feature_names_out()` | Standardize on named outputs |
| F6 | Pickled model fails after a library upgrade | Unpickling warnings or errors | Pickles tie you to library versions | Export to ONNX (05.3) or pin versions; `skops` for safer serialization | Version the model with its environment |
| F7 | Caching fills the disk or slows the search | Big `joblib` cache directories | Caching cheap steps on large inputs | Cache only expensive steps; clean up cache dirs | Measure with and without caching (§2.2) |
| F8 | Thread explosion in a web service | Latency spikes under concurrency | Each request's predict uses all BLAS/OpenMP threads | Limit threads per worker process at startup | Set `OMP_NUM_THREADS`/`threadpoolctl` in the service entry point |

**Debugging toolkit.** `est.get_params()`, `clone(est)`, `check_is_fitted`. For pipelines, `pipe.named_steps` and `pipe[:-1].transform(X)` (inspect features), `get_feature_names_out()` and `sklearn.set_config(display="diagram")`. For threads, `threadpoolctl.threadpool_info()`. Validate custom estimators with `check_estimator`.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Our model scored 0.92 AUC offline and 0.61 in production. Where do you look first?"</b></summary>

**Initial Prompt.** A churn model with heavy feature engineering underperforms after launch.

**L5 Answer.** "Data drift. Retrain on recent data."

**Why L5 Crashes at Scale.** Retraining with the same pipeline reproduces the same optimistic estimate. The most common cause of a 30-point gap is *leakage*: preprocessing, selection or encodings fit on all data; random splits on temporal or entity data; features computed with future information. Drift doesn't produce that gap overnight.

**L7 Principal Defense.** Audit the evaluation before the model. Is every data-dependent step inside the cross-validated `Pipeline`? Does the splitter match deployment (`TimeSeriesSplit` for forecasting, `GroupKFold` for new customers)? Are features point-in-time correct (03.4)? Run the shuffled-label sanity check: on permuted labels, the full pipeline must score chance, while the leaky selection-before-CV scored 0.845 accuracy on pure noise here. Then compare the CV estimate under the corrected protocol with production. If they agree, the model was never good, and that's the finding.

</details>

<details><summary><b>Q2 · "Why must hyperparameters be stored unmodified in `__init__`?"</b></summary>

**Initial Prompt.** A teammate's custom transformer normalizes its `columns` argument in `__init__` and validates data there.

**L5 Answer.** "It's a style convention."

**Why L5 Crashes at Scale.** It's what `clone`, `get_params`/`set_params` and grid search rely on. If `__init__` transforms params, `clone` produces a different object, `set_params` bypasses the transformation, and parallel CV workers get inconsistent estimators. If `__init__` touches data, cloning leaks state across folds.

**L7 Principal Defense.** `clone` reconstructs an estimator from `get_params()`, which introspects the `__init__` signature (measured: the clone kept `C` and had no `coef_`). Hence store params verbatim, validate and derive in `fit`, put learned state in trailing-underscore attributes, and return `self`. Enforce it with `check_estimator` in CI. This is what makes pipelines composable and leakage-safe.

</details>

<details><summary><b>Q3 · "GridSearchCV with `n_jobs=-1` got slower on a bigger machine. Why?"</b></summary>

**Initial Prompt.** Moving from 16 to 64 cores made a HistGradientBoosting grid search slower.

**L5 Answer.** "Python can't use many cores; use fewer jobs."

**Why L5 Crashes at Scale.** The machine *is* used, but oversubscribed: 64 joblib workers × 64 OpenMP threads each is 4,096 runnable threads fighting for caches and memory bandwidth, plus 64 copies of data shipped to workers.

**L7 Principal Defense.** Treat parallelism as a two-level budget. Joblib processes (embarrassingly parallel candidates and folds) times OpenMP/BLAS threads inside each fit should roughly equal cores. Measured on 12 logical cores: 4 workers × 3 threads beat both 1 × 12 and 4 × 12 (10.2 s vs 16.3 and 13.6 s). Set inner limits with `threadpool_limits` (or `OMP_NUM_THREADS` before import) and use large inputs as memory-mapped arrays (joblib auto-memmaps big NumPy inputs). Prefer HalvingGridSearchCV or Bayesian search to cut candidate count.

</details>

<details><summary><b>Q4 · "When does `Pipeline(memory=...)` help?"</b></summary>

**Initial Prompt.** A team enables caching on every pipeline "for speed".

**L5 Answer.** "Always. It avoids recomputing transformers."

**Why L5 Crashes at Scale.** Caching hashes each step's inputs and pickles outputs to disk on every call. For cheap steps over large data that costs more than recomputing: measured, 1.15 → 1.50 s (slower) for PCA on 20 k × 300.

**L7 Principal Defense.** Cache only steps whose fit time ≫ (hash + serialize) time of their input and output, typically kernel approximations, text vectorizers on large corpora, or expensive feature extraction. Measured: Nystroem(800) went from 13.7 to 8.9 s with caching. Put the cache on local SSD, clean it per experiment, and remember that the cache keys on parameters, so search spaces that vary early steps get no reuse.

</details>

<details><summary><b>Q5 · "How do you evaluate a model that will predict next month's demand?"</b></summary>

**Initial Prompt.** A demand forecast uses gradient boosting on calendar and lag features.

**L5 Answer.** "5-fold cross-validation with shuffling."

**Why L5 Crashes at Scale.** Shuffled folds put the days around each test day into training, so the model interpolates. Measured on drifting data: 0.973 AUC with shuffled K-fold against 0.503 forward-chaining. Deployment never gets to see the future.

**L7 Principal Defense.** Use forward-chaining splits (`TimeSeriesSplit`, optionally with a `gap` equal to the label horizon to prevent label overlap), compute lag features strictly from data available at prediction time, and evaluate on the most recent periods as a final holdout. Report per-period performance, not one averaged number, to see degradation over time. Retrain on a schedule set by measured decay.

</details>

<details><summary><b>Q6 · "Design the feature preprocessing for a mixed tabular model that must run in a Java service."</b></summary>

**Initial Prompt.** Numeric, categorical and missing values; training in Python, serving on the JVM.

**L5 Answer.** "Reimplement the preprocessing in Java."

**Why L5 Crashes at Scale.** Two implementations drift (different rounding, category ordering, missing-value handling), producing training/serving skew that no unit test catches until model quality silently drops.

**L7 Principal Defense.** Keep one definition: a scikit-learn `Pipeline` with `ColumnTransformer` (named pandas outputs, `handle_unknown="ignore"`), exported as a single ONNX graph with skl2onnx (05.3), and run by ONNX Runtime's Java API in the service. Measured, a converted scikit-learn pipeline agreed with native predictions to 1.8e-7 and served single rows in ~15 µs. Add a parity test that scores a golden dataset in both runtimes on every model release.

</details>

<details><summary><b>Q7 · "What does `set_output(transform='pandas')` buy you in production?"</b></summary>

**Initial Prompt.** A feature-importance dashboard shows features named `x0…x57`.

**L5 Answer.** "Map the indices back to names manually."

**Why L5 Crashes at Scale.** Manual maps break when a pipeline changes (a new category, a dropped column), so importances get attributed to the wrong features: worse than no names.

**L7 Principal Defense.** Use `set_output(transform="pandas")` (or `"polars"`) so every step emits named columns (measured: `num__amount`, `cat__country_DE`, …), and `get_feature_names_out()` stays consistent end to end. Log the feature-name list with the model artifact, and assert at serving time that the input schema matches. That turns column-order bugs into immediate errors.

</details>

<details><summary><b>Q8 · "Your custom transformer passes unit tests but breaks inside GridSearchCV. Why?"</b></summary>

**Initial Prompt.** A transformer caches statistics in a module-level dict for speed.

**L5 Answer.** "Joblib's multiprocessing breaks globals; use `n_jobs=1`."

**Why L5 Crashes at Scale.** It isn't the processes. Module-level state shared across clones leaks statistics between folds (leakage), and across processes it silently differs (non-determinism). `n_jobs=1` hides one symptom and keeps the leak.

**L7 Principal Defense.** All learned state belongs on the instance in trailing-underscore attributes set in `fit`. Clones must be independent. Run `check_estimator`, which tests clone-ability, idempotent fit, no state in `__init__` and pickle round-trips. For expensive shared computations use `Pipeline(memory=...)` or precompute features outside CV only when they don't depend on labels or fold statistics.

</details>

---

## 5. Invariants Checklist

- [ ] Estimators store hyperparameters verbatim in `__init__` and learn state in `fit` (`attr_`); `clone` copies params, not state.
- [ ] Every data-dependent step (scaling, selection, encoding, imputation) lives inside the cross-validated `Pipeline`.
- [ ] The splitter matches deployment: time-based for forecasting, group-based for new entities.
- [ ] A shuffled-label run must score chance. Leaky selection scored 0.845 on coin flips here.
- [ ] `handle_unknown="ignore"` and named outputs (`set_output`) for serving robustness and debuggability.
- [ ] Parallelism is two-level: joblib workers × OpenMP/BLAS threads ≈ cores. Use threadpoolctl.
- [ ] Cache only expensive steps; caching cheap ones costs more than it saves.

---

## 6. References

- scikit-learn developer guide, Developing estimators — https://scikit-learn.org/stable/developers/develop.html
- Common pitfalls and recommended practices (data leakage) — https://scikit-learn.org/stable/common_pitfalls.html
- Pipelines and composite estimators — https://scikit-learn.org/stable/modules/compose.html
- `set_output` API — https://scikit-learn.org/stable/auto_examples/miscellaneous/plot_set_output.html
- Cross-validation iterators (TimeSeriesSplit, GroupKFold) — https://scikit-learn.org/stable/modules/cross_validation.html
- Parallelism, resource management and configuration — https://scikit-learn.org/stable/computing/parallelism.html
- threadpoolctl — https://github.com/joblib/threadpoolctl
- C. Ambroise, G. McLachlan, "Selection bias in gene extraction on the basis of microarray gene-expression data", PNAS 99(10), 2002, DOI 10.1073/pnas.102102699.
- S. Kaufman et al., "Leakage in Data Mining: Formulation, Detection, and Avoidance", ACM TKDD 6(4), 2012, DOI 10.1145/2382577.2382579.
