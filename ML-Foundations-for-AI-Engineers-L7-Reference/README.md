# ML Foundations for AI Engineers — L7 Reference

A first-principles knowledge base for a Senior/Staff backend engineer becoming a Staff/Principal **AI engineer**. It covers the math, classical ML, deep-learning mechanics and statistical evaluation that sit underneath production LLM systems: semantic routers, hybrid search re-ranking, embedding compression, guardrail classifiers, hallucination detection, cost/latency cascades and systematic evals. It isn't a research curriculum. Every formula is tied to a production decision, and every subtopic is tagged:

- `[MUST-KNOW: Core AI Engineer Edge]`
- `[GOOD-TO-KNOW: Architectural Literacy]`
- `[SKIP: Academic/Research Only]`

Every quantitative claim is either **measured by a listing that ships in the file**, **quoted from a verified source** (listed in each file's §8), or marked ⚠.

## Status

**Complete (2026-10-30): 8 folders, 26 files, ~214k words (prose + 63 verified listings), 244 bar-raiser Q&A chains. Every folder passed its gate.**

| # | Folder | Files | Status |
|---|---|---|---|
| 01 | [Linear Algebra, Probability & Embedding Geometry](01-Linear-Algebra-Probability-and-Embedding-Geometry/) | 3 | ✅ ~48k words, 14 listings (synthetic, seeded), 33 chains; gate: 10 outputs byte-identical, 4 timing-only |
| 02 | [Classical Supervised ML for AI Engineers: Fast Routers & Rankers](02-Classical-Supervised-ML-for-AI-Engineers-Fast-Routers-and-Rankers/) | 3 | ✅ ~24k words, 9 listings on real CLINC150 + prompt-injection data, 24 chains; gate: 4 identical, 5 timing-only |
| 03 | [Unsupervised Learning, Clustering & Anomaly Detection in AI Systems](03-Unsupervised-Learning-Clustering-and-Anomaly-Detection-in-AI-Systems/) | 3 | ✅ ~21k words, 8 listings, 24 chains; gate: 4 identical, 4 timing-only |
| 04 | [Classical-to-Neural Information Retrieval & Ranking Algorithms](04-Classical-to-Neural-Information-Retrieval-and-Ranking-Algorithms/) | 3 | ✅ ~19k words, 7 listings on real BEIR SciFact, 24 chains; gate: 4 identical, 3 timing-only |
| 05 | [Deep Learning Foundations to Transformers, First Principles](05-Deep-Learning-Foundations-to-Transformers-First-Principles/) | 4 | ✅ ~25k words, 8 listings (incl. a MiniLM forward pass from raw weights and a SmolLM2 decoder), 32 chains; gate: 3 identical, 5 timing-only |
| 06 | [Evaluation Statistics, Error Analysis & LLM-as-a-Judge](06-Evaluation-Statistics-Error-Analysis-and-LLM-as-a-Judge/) | 4 | ✅ ~32k words, 8 listings (real CLINC150 + SciFact runs, seeded judge and A/B simulations), 35 chains; gate: all 8 byte-identical |
| 07 | [Hybrid ML + LLM Production Design Patterns](07-Hybrid-ML-Plus-LLM-Production-Design-Patterns/) | 3 | ✅ ~24k words, 6 listings (a real CLINC150 cascade and retraining loop, feature-store and skew simulations), 26 chains; gate: all 6 byte-identical |
| 08 | [Andrew Ng Curriculum, Certifications & Bar-Raiser Interview Playbook](08-Andrew-Ng-Curriculum-Certifications-and-Bar-Raiser-Interview-Playbook/) | 3 | ✅ ~21k words, 3 listings (study planner, certification ROI matrix, napkin-math key), 46 chains (30 in 08.3); course and certification facts verified 2026-10-30; gate: all 3 byte-identical |

**Suggested reading order:** 06.3 (error analysis) → 01.1 → 02.3 → 04 → 06.1–06.2 → 07.1 → the rest in order. 08.1 has a computed 90-day plan that pairs each week with a folder.

## Files

**01 · Linear Algebra, Probability & Embedding Geometry**
1. [01.1 · Vector spaces, dot product, cosine similarity & the L2-distance equivalence](01-Linear-Algebra-Probability-and-Embedding-Geometry/01-vector-spaces-dot-product-cosine-similarity-and-l2-distance-equivalence.md): unit-sphere proofs, anisotropy and threshold transfer, MIPS→L2, int8/binary quantization geometry, SimHash, a centroid router with an abstain-to-LLM cost model.
2. [01.2 · Matrix decompositions: SVD, PCA, LoRA & Matryoshka](01-Linear-Algebra-Probability-and-Embedding-Geometry/02-matrix-decompositions-svd-pca-and-how-lora-and-matryoshka-embeddings-work.md): Eckart–Young, PCA with the k + 1 mean-coordinate trick, Procrustes migrations, LoRA from hand-written gradients to multi-tenant serving, Matryoshka funnels.
3. [01.3 · Probability, Bayes, entropy, KL, softmax temperature & cross-entropy](01-Linear-Algebra-Probability-and-Embedding-Geometry/03-probability-bayes-entropy-kl-divergence-softmax-temperature-and-cross-entropy.md): guardrail base rates, cost-optimal thresholds, prior shift, forward vs reverse KL, temperature and sampling, calibration, semantic entropy.

**02 · Classical Supervised ML: Fast Routers & Rankers**
1. [02.1 · Linear & logistic regression, gradient descent, L1/L2, calibration](02-Classical-Supervised-ML-for-AI-Engineers-Fast-Routers-and-Rankers/01-linear-and-logistic-regression-gradient-descent-regularization-l1-l2-and-calibration.md)
2. [02.2 · Decision trees, random forests & gradient-boosted trees (XGBoost, LightGBM)](02-Classical-Supervised-ML-for-AI-Engineers-Fast-Routers-and-Rankers/02-decision-trees-random-forests-and-gradient-boosted-trees-xgboost-lightgbm.md)
3. [02.3 · Building 2 ms semantic intent routers & guardrails on frozen embeddings](02-Classical-Supervised-ML-for-AI-Engineers-Fast-Routers-and-Rankers/03-building-2ms-semantic-intent-routers-and-guardrails-on-frozen-embeddings.md)

**03 · Unsupervised Learning, Clustering & Anomaly Detection**
1. [03.1 · k-means & HDBSCAN for semantic caching, topic discovery & RAPTOR RAG](03-Unsupervised-Learning-Clustering-and-Anomaly-Detection-in-AI-Systems/01-kmeans-and-hdbscan-for-semantic-caching-topic-discovery-and-raptor-rag.md)
2. [03.2 · PCA, t-SNE & UMAP for embedding-drift visualization](03-Unsupervised-Learning-Clustering-and-Anomaly-Detection-in-AI-Systems/02-dimensionality-reduction-pca-t-sne-umap-for-embedding-drift-visualization.md)
3. [03.3 · Isolation Forests & Mahalanobis distance for out-of-distribution queries](03-Unsupervised-Learning-Clustering-and-Anomaly-Detection-in-AI-Systems/03-anomaly-detection-isolation-forests-and-mahalanobis-distance-for-out-of-distribution-queries.md)

**04 · Classical-to-Neural Information Retrieval & Ranking**
1. [04.1 · TF-IDF, BM25 saturation & inverted-index scoring](04-Classical-to-Neural-Information-Retrieval-and-Ranking-Algorithms/01-lexical-math-tf-idf-bm25-saturation-and-inverted-index-scoring.md)
2. [04.2 · Contrastive learning, InfoNCE, hard negatives & bi-encoder training](04-Classical-to-Neural-Information-Retrieval-and-Ranking-Algorithms/02-contrastive-learning-infonce-loss-hard-negatives-and-how-bi-encoders-are-trained.md)
3. [04.3 · Learning to rank: pointwise, pairwise, listwise, cross-encoders & LambdaMART](04-Classical-to-Neural-Information-Retrieval-and-Ranking-Algorithms/03-learning-to-rank-pointwise-pairwise-listwise-cross-encoders-and-lambda-mart.md)

**05 · Deep Learning Foundations to Transformers**
1. [05.1 · MLPs, backpropagation, GELU/SwiGLU & LayerNorm vs RMSNorm](05-Deep-Learning-Foundations-to-Transformers-First-Principles/01-mlp-backpropagation-activations-gelu-swiglu-and-layernorm-vs-rmsnorm.md)
2. [05.2 · Optimization physics: SGD, momentum, AdamW, weight decay & LR schedules](05-Deep-Learning-Foundations-to-Transformers-First-Principles/02-optimization-physics-sgd-momentum-adamw-weight-decay-and-lr-schedulers.md)
3. [05.3 · Why RNNs/LSTMs lost, and self-attention QKV matrix math](05-Deep-Learning-Foundations-to-Transformers-First-Principles/03-sequence-models-why-rnns-lstms-failed-and-self-attention-qkv-matrix-math.md)
4. [05.4 · Encoders (BERT/DeBERTa) vs decoders (GPT/Llama): when a small BERT beats an LLM](05-Deep-Learning-Foundations-to-Transformers-First-Principles/04-encoder-bert-deberta-vs-decoder-gpt-llama-when-to-use-small-bert-over-llms.md)

**06 · Evaluation Statistics, Error Analysis & LLM-as-a-Judge**
1. [06.1 · Precision, recall, F1, PR-AUC vs ROC-AUC & threshold tuning](06-Evaluation-Statistics-Error-Analysis-and-LLM-as-a-Judge/01-classification-metrics-precision-recall-f1-pr-auc-vs-roc-auc-and-threshold-tuning.md)
2. [06.2 · Recall@k, MRR, MAP & nDCG math](06-Evaluation-Statistics-Error-Analysis-and-LLM-as-a-Judge/02-retrieval-and-ranking-metrics-recall-at-k-mrr-map-and-ndcg-math.md)
3. [06.3 · Ng's error analysis, bias/variance in AI systems & calibrating LLM-as-a-judge](06-Evaluation-Statistics-Error-Analysis-and-LLM-as-a-Judge/03-andrew-ng-error-analysis-bias-variance-in-ai-and-calibrating-llm-as-a-judge.md)
4. [06.4 · A/B testing, p-values, bootstrapping & multi-armed bandits](06-Evaluation-Statistics-Error-Analysis-and-LLM-as-a-Judge/04-ab-testing-hypothesis-testing-p-values-bootstrapping-and-multi-armed-bandits.md)

**07 · Hybrid ML + LLM Production Design Patterns**
1. [07.1 · The model cascade: regex, BERT, XGBoost & LLMs](07-Hybrid-ML-Plus-LLM-Production-Design-Patterns/01-the-model-cascade-pattern-combining-regex-bert-xgboost-and-llms-for-90-percent-cost-cut.md)
2. [07.2 · Feature stores (Feast), online/offline parity & training/serving skew](07-Hybrid-ML-Plus-LLM-Production-Design-Patterns/02-feature-stores-feast-online-offline-parity-and-preventing-training-serving-skew.md)
3. [07.3 · Data drift, embedding drift, PSI & automated retraining loops](07-Hybrid-ML-Plus-LLM-Production-Design-Patterns/03-detecting-data-drift-embedding-drift-psi-and-automated-retraining-loops.md)

**08 · Andrew Ng Curriculum, Certifications & Bar-Raiser Interview Playbook**
1. [08.1 · Curated Ng / DeepLearning.AI courses, books & a 90-day study sequence](08-Andrew-Ng-Curriculum-Certifications-and-Bar-Raiser-Interview-Playbook/01-curated-andrew-ng-deeplearning-ai-courses-books-and-90-day-study-sequence.md)
2. [08.2 · 2026–2027 cloud & AI certifications ROI matrix](08-Andrew-Ng-Curriculum-Certifications-and-Bar-Raiser-Interview-Playbook/02-2026-2027-cloud-and-ai-certifications-roi-matrix-aws-gcp-databricks.md)
3. [08.3 · 30 ML-for-AI-engineers bar-raiser questions & defenses](08-Andrew-Ng-Curriculum-Certifications-and-Bar-Raiser-Interview-Playbook/03-30-ml-for-ai-engineers-bar-raiser-interview-questions-and-defenses.md)

## How every file is built

The spine is identical in each file, and the gate enforces it:

| Section | Content |
|---|---|
| `## 0.` Orientation | Why an AI engineer cares, a backend-engineer bridge table, and the tier map |
| `## 1.` First-Principles Math & Geometric Intuition | Derivations and proofs, ASCII diagrams. Every `### 1.x` heading carries a tier tag |
| `## 2.` Where It Beats an LLM in Production | Cost, latency and accuracy trade-offs, plus when the LLM is the right tool |
| `## 3.` Production Code Blueprint | Runnable listings spliced byte-for-byte from the verified sources, with their captured outputs |
| `## 4.` The Andrew Ng Lens | Error-analysis spreadsheets, bias/variance translated to LLM-era systems, evaluation-driven development |
| `## 5.` Failure Modes | Symptom → signature → root cause → fix → prevention |
| `## 6.` Bar-Raiser Q&A Chains | `<details>` blocks: **Initial Prompt / L5 Answer / Why L5 Fails in Production / L7 Principal Defense / Bar-Raiser Follow-ups** |
| `## 7.` Invariants Checklist | What must always be true in a system that uses the topic |
| `## 8.` References | Primary sources with URLs (or DOIs where publishers block automated checks) |

**Output labels.** "Output (verified)" means the gate regenerated the output from the listing as it appears in the KB, and it matched. Lines described as "one measured run" are timings from this laptop (Intel i5-11260H, Windows 11; one BLAS thread unless stated; an RTX 3050 Laptop GPU where a listing says so). Expect different absolute numbers on your hardware, with the same shape.

## Verification harness and data

- CPython 3.14.5. NumPy 2.5.4, SciPy 1.18.1, scikit-learn 1.9.1, LightGBM 4.7.0, XGBoost 3.4.1, ONNX Runtime 1.31.1, pandas 3.1, PyArrow 26, umap-learn 0.5.12 + numba 0.68.1, transformers 5.22.0, tokenizers 0.23.3, PyTorch 2.14.1+cu130.
- Listings run one at a time as `python -I -X utf8 run_i.py listing.py` (isolated mode, explicit site dirs), with `OPENBLAS_NUM_THREADS=1`. One BLAS thread keeps laptop load low *and* fixes the floating-point reduction order, so seeded outputs reproduce byte for byte. Downloaded data and models live in their own directory and are read only by isolated-mode Python.
- **Real data and models** (Folders 02–07):
  - [CLINC150](https://github.com/clinc/oos-eval) (`data_full`: 150 intents + out-of-scope), embedded with [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2).
  - [BEIR](https://github.com/beir-cellar/beir) SciFact (5,183 abstracts, 300 test claims with qrels).
  - [cross-encoder/ms-marco-MiniLM-L6-v2](https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2).
  - [SmolLM2-135M-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct).
  - [deepset/prompt-injections](https://huggingface.co/datasets/deepset/prompt-injections).
- **Simulations** are seeded and say so in their docstrings: Folder 01's geometry toys, 06.3's judge, 06.4's A/B tests and bandits, 07.1's fallback LLM accuracy and serving clock, 07.2's event streams, and 07.3's pipeline incident. Their mechanisms are exact. Their magnitudes are assumptions, labelled where they appear.
- **Gate:** listings are extracted from the markdown, checked byte-identical to the sources, rerun sequentially from the KB copies, and compared with the recorded outputs (exact for deterministic listings, digit-masked for timing listings). Structure checks: sections 0–8, an exact tier tag on every `### 1.x`, all five chain parts, ≥ 8 chains per file.

## Listing index

| Folder | Listings (file → what it measures) |
|---|---|
| 01 | `unit_sphere_identities`, `high_dim_concentration` (threshold transfer 0.95 → 0.253), `embedding_quantization_recall` (int8 affine 0.629 vs symmetric 0.980; binary 0.365 → 0.995 with ×10 rescoring), `semantic_router_kernel` (01.1); `svd_geometry_eckart_young` (Procrustes 0.000 → 0.936), `pca_embedding_compression` (k + 1 trick, 0.995 @ 64), `lora_from_scratch_numpy`, `lora_linear_torch` (bf16 merge loses 2.8% of ΔW), `matryoshka_linear_toy` (01.2); `bayes_guardrail_base_rates`, `softmax_temperature_lab`, `entropy_kl_ce_identities`, `temperature_scaling_calibration` (ECE 0.182 → 0.009), `semantic_entropy_blueprint` (AUROC 0.896 vs 0.843) (01.3) |
| 02 | `encode_clinc_minilm` (the shared embedding cache), `linear_logistic_from_scratch`, `logreg_head_on_clinc` (0.955; T = 0.63; 15.7 µs NumPy vs 116 µs sklearn) (02.1); `tree_split_and_forest_variance`, `gbdt_second_order_from_scratch` (leaves match XGBoost; its gain omits ½), `gbdt_vs_linear_and_latency` (LightGBM 0.760 vs LR 0.718 tabular; LR 0.985 vs 0.952 on embeddings) (02.2); `clinc_router_heads_and_oos` (cosine gate 0.966 vs softmax 0.945), `onnx_int8_router_latency` (11.4 ms eager → 2.18 ms ONNX int8), `prompt_injection_guardrail_head` (TF-IDF 0.975 vs MiniLM 0.938) (02.3) |
| 03 | `kmeans_on_embeddings` (ARI 0.715 at k = 150), `hdbscan_topic_discovery` (22 of 30 unseen intents), `semantic_cache_ivf_and_raptor_tree` (wrong hits at cos 0.93; IVF 0.999 recall at 3.7× less work) (03.1); `tsne_umap_neighborhood_preservation`, `embedding_drift_detectors` (fixed reference 7/20 false alarms vs 1/20) (03.2); `mahalanobis_shrinkage_math` (condition number ~10¹⁶ → 268), `ood_detectors_clinc` (relative Mahalanobis 0.972), `isolation_forest_mechanics` (03.3) |
| 04 | `bm25_inverted_index_scifact` (0.6711), `bm25_saturation_and_maxscore` (53% fewer postings, same top-10; train-tuned k1/b hurt test) (04.1); `infonce_from_scratch`, `dense_and_hybrid_scifact` (dense 0.6451, RRF 0.6929, convex 0.7257), `bi_encoder_adapter_training` (0.6968) (04.2); `ltr_losses_from_scratch`, `rerank_cross_encoder_and_lambdamart` (LambdaMART 0.7191 at 0.51 ms; zero-shot CE 0.6818) (04.3) |
| 05 | `autograd_from_scratch`, `activations_and_norms` (LayerNorm 7.2 ms vs unfused RMSNorm 20.9 ms) (05.1); `optimizer_physics` (GD 709 / momentum 95 / Adam 351 steps), `adamw_and_lr_schedules` (L2-in-Adam 17× weaker decay) (05.2); `rnn_lstm_vs_attention`, `self_attention_from_scratch` (KV cache to 7.7e-7) (05.3); `minilm_forward_from_weights` (2.55e-15), `encoder_vs_decoder_classification` (0.9867 at 19.6 ms vs 0.1717 at 12,118 ms) (05.4) |
| 06 | `classification_metrics_from_scratch` (precision 0.88 → 0.0067 as prevalence falls, ROC-AUC flat), `clinc_multiclass_metrics` (accuracy 0.855, macro-F1 0.898, OOS recall 0.414) (06.1); `ranking_metrics_from_scratch` (pooled qrels reverse a comparison), `scifact_metric_suite` (06.2); `error_analysis_and_ceiling` (stage 2 +0.212 vs stage 1 +0.043), `llm_judge_calibration` (κ 0.43 vs 0.71; Platt 0.655 → 0.421) (06.3); `ab_testing_power_and_peeking` (14,313 per arm; peeking 24.2%; CUPED 22%), `bootstrap_and_bandits` (paired CI 0.049 vs 0.120 wide; Thompson regret 60.6) (06.4) |
| 07 | `cascade_router_clinc` (parity at 72.5% lower cost; tuning at the wrong OOS share −4.3 points), `cascade_service_blueprint` (breaker: 2,101 → 16 stuck requests) (07.1); `point_in_time_feature_store` (leaky 0.912 offline vs 0.653 served; streaming parity), `training_serving_skew_detector` (three bugs; PSI 12.4 / 0.432 / 0.140) (07.2); `psi_ks_drift_metrics` (null 99th pct 0.879 at n = 200, 50 bins; KS p = 1e-26 on a trivial shift), `retraining_loop_simulation` (weekly+gate 0.822 vs ungated drift-triggered 0.480) (07.3) |
| 08 | `study_plan_scheduler` (what fits in 90 days at 8–15 h/week) (08.1); `cert_roi_matrix` (per-platform picks + robustness) (08.2); `interview_napkin_math` (28/28 checks) (08.3) |

## The AI-engineering skills map used in this KB

The brief asked for Andrew Ng's "AI Engineering Skills Map". We couldn't find a canonical Ng document by that name. Ng's verifiable frameworks are used where they apply, and cited: the evals + error-analysis discipline (*The Batch*, 2025-10-15; the *Agentic AI* course), ceiling analysis, bias/variance against human-level performance, data-centric AI, and dev/test sets from the deployment distribution. The skills map below is this KB's own synthesis, so you can see where each skill is built:

| Skill | What "good" looks like | Built in |
|---|---|---|
| Embedding geometry and vector-index contracts | Picks the operator, normalization, dtype and thresholds, and can prove the equivalences | 01.1 |
| Representation compression | Chooses among MRL, PCA, int8/binary and rescoring from measured recall per byte | 01.1, 01.2 |
| Model adaptation | Diagnoses knowledge vs behaviour vs capability gaps; runs LoRA correctly; serves adapters at scale | 01.2, 05, 07 |
| Probabilistic decision-making | Base rates, cost thresholds, prior shift, calibration | 01.3, 02, 06 |
| Cheap models on frozen embeddings | Logistic/GBDT heads, routers and guardrails at a small fraction of an LLM call's cost | 01.1, 02 |
| Retrieval and ranking | BM25, bi-encoders, cross-encoders, learning-to-rank, hybrid fusion | 04 |
| Evaluation and error analysis | Spreadsheets, ceiling analysis, metric math, judge calibration, A/B statistics | every §4; 06 |
| Production ML systems | Cascades, feature stores, drift detection, retraining loops | 07 |
| Career and interview execution | A measured 90-day plan, platform-fit certification choices, numbers-first defenses | 08 |

## Where this KB refines the brief

1. **Files are written straight to disk**, so the per-file `### FILE:` chat headers aren't needed: the folder *is* the repository.
2. **Folder names follow the brief's tree** (`01-Linear-Algebra-Probability-and-Embedding-Geometry/` …), not the shorter names in the role text.
3. **The research ran inline and sequentially** instead of the stock multi-agent deep-research fan-out, to respect the standing no-parallel-local-agents rule on this laptop. Sources were fetched and checked one at a time.
4. **"1/1000th the cost of GPT/Claude" is a range, not a constant.** On published prices (2026-10), a classification call costs **113×** an embedding call on Claude Haiku 5.5, **2,267×** on Sonnet 5.5 and **4,533×** on Opus 5.5 (01.1 §2). A self-hosted head on ~2 ms of CPU is ~340× cheaper than a Haiku call (08.3 §1.8).
5. **Temperature is no longer an API knob on current Claude models.** API version 2026-10-21 rejects `temperature`/`top_p`/`top_k`. 01.3 therefore teaches temperature for self-hosted sampling, post-hoc calibration and training losses.
6. **Log-prob-based hallucination detection is availability-limited** (no log-probs from Claude, and inconsistent support on reasoning models elsewhere ⚠). 01.3 centres sampling + semantic clustering and grounding checks.
7. **Matryoshka vs PCA is reported honestly.** In the linear toy, corpus-fitted PCA matches MRL at small dims (01.2 §1.11).
8. **Binary-quantization speedups depend on the engine.** NumPy's popcount path is only ~2× faster than BLAS float32. The 32× memory saving holds either way.
9. **Chains add a fifth part, "Bar-Raiser Follow-ups"**, because the brief asked for Q&A *chains*.
10. **The "2 ms router" is real only with ONNX int8.** Eager PyTorch MiniLM measured 11.4 ms end to end on one thread, and ONNX int8 2.18 ms (02.3).
11. **Embeddings don't always win.** TF-IDF beat MiniLM on prompt injection (0.975 vs 0.938, 02.3). Logistic regression beat LightGBM on embeddings (02.2) and beat an MLP head (05.2).
12. **Re-rankers can hurt.** A zero-shot MS MARCO cross-encoder *lowered* SciFact nDCG@10 below the hybrid (0.6818 vs 0.7257, 04.3). Tuning BM25 on training queries hurt test (04.1).
13. **Fewer FLOPs isn't faster.** Unfused RMSNorm was ~3× slower than PyTorch's fused LayerNorm on CPU (05.1).
14. **The "90% cost cut" in 07.1's title is a traffic property.** On CLINC test traffic (18% out-of-scope), the cascade reached parity with LLM-only at **72.5%** lower cost. 90% needs ≤ 9.7% deferral. Tuning thresholds on the raw 3%-OOS validation split silently lost 4.3 points (07.1 §1.4).
15. **Retraining automation can be worse than none.** An ungated drift-triggered loop deployed a broken model and stayed broken for 7 weeks (mean 0.480 vs 0.686 for never retraining). The fix is a serving-path promotion gate (07.3 §1.10).
16. **Certification facts changed in 2026** (AWS MLS-C01 retired, MLA-C01 → C02; Microsoft AI-102 → AI-103; Google's Vertex AI rename). 08.2's matrix is dated 2026-10-30 and must be re-verified before registering.

## Related KBs in this workspace

- [Production AI Engineering L7 Reference](../Production-AI-Engineering-L7-Reference/README.md): LLM inference physics, vector-DB internals (HNSW/DiskANN/PQ), RAG pipelines, MCP and agents. This KB supplies the math underneath.
- [Python Data/ML Systems L7 Reference](../Python-Data-ML-Systems-L7-Reference/README.md): PyTorch internals, GPU physics, distributed training, LoRA/QLoRA kernels on a real GPU.
- [Live PR Code Review Bug-Hunt L7 Reference](../Live-PR-Code-Review-Bug-Hunt-L7-Reference/) and the Staff/Principal behavioral playbook for the interview loop around these technical questions.
