# 01.2 · Matrix Decompositions: SVD, PCA, and How LoRA & Matryoshka Embeddings Work

> **Folder 01 · Linear Algebra, Probability & Embedding Geometry**
> **Measured on:** NumPy 2.5.4, scikit-learn 1.9.1, PyTorch 2.14.1 (CPU, one thread), CPython 3.14.5, Intel i5-11260H, Windows 11. All data is synthetic and seeded, so the *mechanisms* reproduce exactly. Magnitudes on your model will differ, and the text says where.
> **Design sources:** Hu et al. (LoRA, 2021), the Hugging Face PEFT LoRA guide, Schulman et al. / Thinking Machines "LoRA Without Regret" (2025-09-29), Kusupati et al. (Matryoshka Representation Learning, NeurIPS 2022), the OpenAI and Gemini embedding docs, Eckart & Young (1936), Halko, Martinsson & Tropp (2011). Full list in §8.

---

## 0. Orientation: Low Rank Is Everywhere in AI Engineering

Andrew Ng often reduces a topic to one picture. For this file the picture is: **a matrix is a machine that rotates, stretches and rotates again, and most of the stretching happens along a handful of directions.** The singular value decomposition (SVD) finds those directions. Once you see that, a large part of modern AI engineering becomes one idea applied in different places:

| Where you meet it | The low-rank idea | The production consequence |
|---|---|---|
| **LoRA fine-tuning** | The *change* a fine-tune makes to a weight matrix has low rank, so learn it as `B·A` | 0.1–3% of the parameters train, adapters are megabytes, one base model serves hundreds of tenants |
| **Matryoshka embeddings** | Train so that the *first m coordinates* already carry the most useful information | One embedding call, many sizes: shortlist at 256 dims, rerank at 3072 |
| **PCA / whitening of embeddings** | Most of the variance of a corpus lives in a few directions | 768 → 64 dims at ~0.995 recall on structured data, 48× smaller at int8 |
| **Embedding-space migration** | Two models' spaces may differ by roughly a rotation | Orthogonal Procrustes (one SVD) bridges them during a migration |
| **Attention KV compression** (DeepSeek's MLA) | Keys and values are projected through a low-rank latent | KV cache shrinks by an order of magnitude (see the Production AI Engineering KB, Folder 01) |
| **Recommenders, topic models** | User × item or term × document matrices are approximately low rank | Matrix factorization, latent semantic analysis |

### The backend-engineer bridge

| You already know | Low-rank equivalent | Why it maps |
|---|---|---|
| A diff or patch over a large file | **A LoRA adapter ΔW = B·A over a frozen W₀** | Ship and version the small delta, not the whole artifact. Apply (merge) or overlay (unmerged) at load time |
| Per-tenant feature flags over one binary | **Per-tenant adapters over one base model** | One deployment, N behaviours, swapped per request |
| Columnar compression: dictionary encoding of a column | **Truncated SVD: a few basis vectors plus coefficients** | You store `k(m+n)` numbers instead of `mn`. Eckart–Young says no k-term code does better in squared error |
| Schema migration with a compatibility shim | **Procrustes alignment between embedding spaces** | Temporary, lossy, gated by tests. Never the end state |
| A fixed-width record with optional trailing fields | **A Matryoshka embedding** | Readers that need less can stop early, and the prefix still parses |

### Tier map for this file

| Subtopic | Tier |
|---|---|
| 1.1 Matrices as linear maps, rank, outer-product sums | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Symmetric eigendecomposition (spectral theorem) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.3 SVD: derivation and geometry | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Eckart–Young–Mirsky (best low-rank approximation) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 PCA = SVD of centred data; whitening; the centring subtlety | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Orthogonal Procrustes | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.7 Randomized SVD | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.8 LoRA: math, init, scaling, cost, merge, what the 2025 evidence says | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 The LoRA family: QLoRA, DoRA, PiSSA, rsLoRA, LoftQ, EVA | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Multi-LoRA serving | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Matryoshka Representation Learning | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.12 The embedding-compression decision matrix | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.13 Low rank in attention and recommenders | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.14 Perturbation theory (Davis–Kahan, Weyl in full) | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Matrices as linear maps, rank, and outer-product sums `[MUST-KNOW: Core AI Engineer Edge]`

A matrix `W ∈ ℝ^{m×n}` is a linear map from ℝⁿ to ℝᵐ. A linear layer in a network is exactly this, `h = W x`, and it accounts for almost all the parameters and FLOPs of a transformer.

- The **rank** of W is the dimension of its output space (the column space): how many independent directions it can produce.
- A rank-1 matrix is an outer product `u vᵀ`. It maps every input onto one output direction u, with strength `v·x`.
- Any rank-k matrix is a sum of k outer products: `W = Σᵢ₌₁ᵏ σᵢ uᵢ vᵢᵀ`.

**Cost arithmetic, the heart of LoRA.** If `W = U_k Σ_k V_kᵀ` with k ≪ min(m, n), you don't need to build W:

```text
W x  =  U_k ( Σ_k ( V_kᵀ x ) )
         └m×k┘ └k×k┘ └k×n┘
FLOPs ≈ 2(mk + nk)       instead of 2mn
params = k(m + n)        instead of mn
```

The SVD listing (§3.1) prints this ratio for real transformer shapes:

```text
  4096 x 4096, k=16: 131,072 vs 16,777,216 params (0.781%)
  4096 x 11008, k=16: 241,664 vs 45,088,768 params (0.536%)
  8192 x 28672, k=64: 2,359,296 vs 234,881,024 params (1.004%)
```

### 1.2 The spectral theorem for symmetric matrices `[GOOD-TO-KNOW: Architectural Literacy]`

A real symmetric matrix S (`S = Sᵀ`) can always be diagonalized by an orthogonal matrix: `S = Q Λ Qᵀ`. The columns of Q are orthonormal eigenvectors and Λ holds real eigenvalues. Covariance matrices `Σ = E[(x−μ)(x−μ)ᵀ]` are symmetric and positive semi-definite (all λ ≥ 0), and each eigenvalue is the **variance of the data along its eigenvector**. That's all of PCA (§1.5). It is also the reason Mahalanobis distance (Folder 03) is "Euclidean distance after rotating to the eigenbasis and rescaling each axis by 1/√λ".

### 1.3 The SVD: derivation and geometry `[MUST-KNOW: Core AI Engineer Edge]`

**Theorem.** Every real m×n matrix A factorizes as `A = U Σ Vᵀ`, with U (m×m) and V (n×n) orthogonal and Σ diagonal with σ₁ ≥ σ₂ ≥ … ≥ 0.

**Construction (enough to trust it).**

```text
1. AᵀA is symmetric PSD  →  AᵀA = V Λ Vᵀ  with λᵢ ≥ 0      (spectral theorem)
2. Define σᵢ = √λᵢ and, for σᵢ > 0,  uᵢ = A vᵢ / σᵢ
3. The uᵢ are orthonormal:
      uᵢ·uⱼ = vᵢᵀ AᵀA vⱼ / (σᵢσⱼ) = λⱼ (vᵢ·vⱼ) / (σᵢσⱼ) = δᵢⱼ
4. So A vᵢ = σᵢ uᵢ for every i, i.e. A V = U Σ, i.e. A = U Σ Vᵀ.      ∎
```

The listing checks it numerically: `‖A − UΣVᵀ‖_max = 1.29e-14`, U and V orthonormal to 3e-15, and `σᵢ² = eig(AᵀA)` to 2.4e-15 relative.

**Geometry: rotate, scale, rotate.** Read `A x = U(Σ(Vᵀx))` right to left. Vᵀ rotates the input so the special input directions vᵢ line up with the axes. Σ stretches axis i by σᵢ. U rotates the result into the output directions uᵢ. The unit circle therefore becomes an ellipse with semi-axes σᵢ along uᵢ:

```text
        input space                                output space
           ↑                                           ↑        σ₁u₁
        ·  ·  ·              A = U Σ Vᵀ           · · · · ·  ↗
     ·     v₂     ·         ─────────────→     ·       ↗       ·
    ·      ↑       ·                          ·   σ₂u₂  ↗        ·
    ·   ───┼───→ v₁·        Vᵀ: rotate        ·    ↖  ↗           ·
    ·      │       ·        Σ : stretch        ·    o            ·
     ·     │      ·         U : rotate           ·            ·
        ·  ·  ·                                     · · · · ·
     unit circle                                ellipse with semi-axes σ₁ ≥ σ₂
```

The listing measures it for `A = [[2, 1], [0.5, 1.5]]`. The maximum of ‖Ax‖ over the unit circle is exactly σ₁ = 2.5583, reached at x = v₁, and the minimum is σ₂ = 0.9772.

**Sign ambiguity, a production gotcha.** If (uᵢ, vᵢ) is a singular pair, so is (−uᵢ, −vᵢ), and the product is unchanged. Libraries pick signs by convention (scikit-learn applies `svd_flip`), and a refit on a different sample can flip any axis. The listing refits on a resampled matrix and gets sign pattern `[-1 -1 1 1 -1]` for the top five. **Never compare PCA projections from two independent fits.** Version the fitted projection matrix the way you version a schema.

### 1.4 Eckart–Young–Mirsky: truncated SVD is the best low-rank approximation `[MUST-KNOW: Core AI Engineer Edge]`

**Theorem.** Let `A_k = Σᵢ₌₁ᵏ σᵢ uᵢ vᵢᵀ`, the SVD truncated to k terms. For every matrix B of rank ≤ k:

```text
‖A − B‖₂ ≥ ‖A − A_k‖₂ = σ_{k+1}                    (spectral norm)
‖A − B‖_F ≥ ‖A − A_k‖_F = √(σ²_{k+1} + … + σ²_r)   (Frobenius norm)
```

**Proof sketch (spectral norm).** B has rank ≤ k, so its null space has dimension ≥ n − k. The span of v₁ … v_{k+1} has dimension k + 1. Two subspaces of ℝⁿ whose dimensions add to more than n intersect, so there is a unit vector w with Bw = 0 and `w = Σᵢ≤ₖ₊₁ cᵢ vᵢ`. Then

```text
‖(A − B) w‖² = ‖A w‖² = Σᵢ≤ₖ₊₁ σᵢ² cᵢ² ≥ σ²_{k+1} Σ cᵢ² = σ²_{k+1}
```

so ‖A − B‖₂ ≥ σ_{k+1}, and A_k achieves it. ∎ The Frobenius case follows from Weyl's inequality on singular values (§1.14 is the formal version you can skip).

**Why an AI engineer cares.**

1. **It is the denoising theorem.** When A = low-rank signal + noise, the tail singular values are mostly noise. Truncation keeps the signal and discards most of the noise. In the LoRA listing (§3.3), an SVD-extracted rank-4 adapter has test loss **0.0050**, *better* than the full fine-tune it was extracted from (**0.0053**), because the truncation throws away 252 noise directions.
2. **It tells you the rank you need before you train.** Look at the spectrum of a full fine-tune's ΔW (or of an embedding matrix). If the singular values fall off a cliff after k, rank k captures the change (§3.3: `3.0, 2.0, 1.5, 1.0`, then a noise floor at ~0.05).
3. **It is the yardstick for every compressor.** Random rank-k subspaces lose to it at every k. Best of 50 random tries at k = 20: residual 110.03 vs the optimum's 96.01.

The listing's table, for a 400×300 matrix of rank-20 signal plus noise:

```text
  k  ||A-A_k||_F  sqrt(tail s^2)  ||A-A_k||_2    s_k+1  best random energy kept
  1     130.0337        130.0337      42.8325  42.8325     134.2404      0.1343
 10     102.1069        102.1069      12.3824  12.3824     119.5872      0.4662
 20      96.0095         96.0095      10.2834  10.2834     110.0254      0.5281
```

Notice the residual barely moves after k = 20. The remaining ~96 is the noise floor (0.3 × √(400·300) ≈ 104, minus the small part of the noise that lies along the signal directions). "Energy kept" alone would tell you to keep adding dimensions forever. The *knee* in the residual tells you where signal ends.

### 1.5 PCA = SVD of the centred data, whitening, and the centring subtlety `[MUST-KNOW: Core AI Engineer Edge]`

**Derivation.** Given centred data X_c (rows = samples), find the unit direction w that maximizes the variance of the projection:

```text
maximize  Var(X_c w) = wᵀ S w,    S = X_cᵀX_c/(n−1),   subject to ‖w‖ = 1
Lagrangian:  wᵀSw − λ(wᵀw − 1)  →  ∂/∂w = 0  →  S w = λ w
```

The best direction is the top eigenvector of the covariance, the variance it captures is its eigenvalue, and each further component is the next eigenvector, orthogonal to the earlier ones. With the SVD `X_c = U Σ Vᵀ`, `S = V (Σ²/(n−1)) Vᵀ`. So **the principal axes are the right singular vectors of the centred data**, with explained variance `σᵢ²/(n−1)`. The PCA listing confirms that our SVD-PCA matches scikit-learn's `PCA` on all 64 components (min |cos| 0.999999; explained variance equal to 6e-8).

**Whitening.** `z = diag(1/σᵢ)·Vᵀ(x − μ)` (up to the √(n−1) scale) rescales every principal axis to unit variance. Su et al. (2021) showed that whitening sentence embeddings, keeping only the top components, can improve semantic-similarity scores. Our listing shows both sides:

```text
   k | PCA centred | ... |  PCA+whiten
     |   rec  prec | ... |   rec  prec
  32 | 0.895 0.865 | ... | 0.549 0.933
  64 | 0.956 0.891 | ... | 0.080 0.210
```

At k = 32, inside the signal subspace, whitening *raises* same-topic precision (0.933 vs 0.865). It equalizes the topic directions, which helps topic-level matching, even though recall against the original space's exact neighbours drops to 0.549. At k = 64 it collapses (precision 0.210): components 49–64 are noise with tiny variance, and dividing by a tiny σ amplifies that noise to unit scale. **Whiten only within the intrinsic dimension**, and evaluate on task labels.

**The centring subtlety, which few people notice.** Centring picks the *right subspace*: the directions of maximum variance rather than the mean direction. But if you then compare cosines of the centred projections, you have changed the metric: cos(P(x − μ), P(y − μ)) is not the cosine in the original space. Our measurements:

```text
   k | PCA centred | PCA + 1 mean |   uncentred | random proj |    truncate
  64 | 0.956 0.891 |  0.995 0.890 | 0.995 0.890 | 0.529 0.781 | 0.535 0.801
```

Centred PCA loses about 4 points of recall against the original-space neighbours (0.956), and uncentred SVD keeps them (0.995). The fix keeps both properties: store the k centred coordinates **plus one coordinate for the part of the mean that lies outside the PCA subspace**. Writing `m_∥ = W Wᵀ μ` and `m_⊥ = μ − m_∥`:

```text
x̂ = μ + W Wᵀ(x − μ) = W (Wᵀ(x − μ) + Wᵀμ) + m_⊥
    → coordinates [ Wᵀ(x − μ) + Wᵀμ ,  ‖m_⊥‖ ]      in the orthonormal basis [W, m_⊥/‖m_⊥‖]
```

That's k + 1 floats whose dot products are exactly the dot products of the PCA *reconstructions*. Measured: **0.995** recall at k = 64, matching uncentred SVD, and the best of the three at k = 32 (0.904).

**Random projection and naive truncation are equivalent here** (0.529 vs 0.535 at k = 64). That's rotation invariance (01.1 §1.1): for a non-Matryoshka embedding, "the first 64 coordinates" is just another random 64-dim projection.

**PCA has a shelf life.** Fit on yesterday's corpus, apply to a new topic family that lives partly outside the fitted subspace, and recall at k = 32 drops from 0.658 (basis refitted with the new data) to **0.243**. At k = 64 the old basis still covers everything (0.974). The listing builds this as a new topic family using latent directions the old corpus barely used. Monitor reconstruction error on incoming vectors: rising error is the drift alarm (Folder 07).

### 1.6 Orthogonal Procrustes: aligning two embedding spaces `[GOOD-TO-KNOW: Architectural Literacy]`

During a model migration you may need old-model documents to answer new-model queries for a while. Given paired embeddings of the same texts (X from the new model, Y from the old), find the rotation that best maps one onto the other:

```text
R* = argmin_{RᵀR = I} ‖X R − Y‖_F
   = U Vᵀ   where  XᵀY = U Σ Vᵀ          (one SVD of a d×d matrix)
```

*Why.* Expanding the norm, `‖XR − Y‖² = ‖X‖² + ‖Y‖² − 2 tr(Rᵀ XᵀY)`. So we maximize `tr(Rᵀ U Σ Vᵀ) = tr(Σ · VᵀRᵀU)`. `VᵀRᵀU` is orthogonal, so its diagonal entries are ≤ 1, and the trace is at most Σσᵢ, with equality when VᵀRᵀU = I, i.e. R = UVᵀ. ∎

Measured in the SVD listing (§3.1, part 6), with 2,000 paired documents and new-model queries against the *old* index:

```text
rotation + noise  recall@10 of new-model queries on the old index: no bridge 0.000, Procrustes 0.936
nonlinear warp    recall@10 of new-model queries on the old index: no bridge 0.001, Procrustes 0.859
```

With no bridge, recall is zero: the spaces are unrelated as stored. A rotation recovers most of it when the true difference is a rotation. Under a nonlinear warp, it only recovers part. Real model pairs differ nonlinearly, so Procrustes is a *temporary shim with an eval gate*, never the migration plan.

### 1.7 Randomized SVD `[GOOD-TO-KNOW: Architectural Literacy]`

Full SVD of an m×n matrix costs O(mn·min(m, n)). When you only need the top k, Halko, Martinsson and Tropp's randomized algorithm (what `sklearn.utils.extmath.randomized_svd`, `PCA(svd_solver="randomized")` and `TruncatedSVD` use) costs O(mn(k + p)):

```text
1. Ω ← random n×(k+p) Gaussian         (p ≈ 10 oversampling)
2. Y ← (A Aᵀ)^q A Ω                    (q ≈ 2–4 power iterations sharpen a slow-decaying spectrum)
3. Q ← orthonormal basis of Y (QR)     (Q spans ≈ the top-k column space)
4. B ← Qᵀ A   (small (k+p)×n);  SVD of B → Ũ Σ Vᵀ;  U ← Q Ũ
```

The listing, on a 2000×1000 matrix (one measured run, one thread): the full SVD takes 364 ms and randomized top-20 takes 81 ms, with a maximum relative error of **8.47e-08** on the top-20 singular values. That's the tool for PCA on a few million embeddings, and for computing PiSSA-style SVD initializations of large weight matrices (`init_lora_weights="pissa_niter_4"` in PEFT uses exactly this).

### 1.8 LoRA: the math, the init, the scaling, the cost, and what the 2025 evidence says `[MUST-KNOW: Core AI Engineer Edge]`

**The idea** (Hu et al., 2021). Full fine-tuning learns `W = W₀ + ΔW`, updating every entry. If ΔW has low *intrinsic* rank (Aghajanyan et al. showed fine-tuning lives in a very low-dimensional subspace), parameterize it directly as a rank-r product and freeze W₀:

```text
h = W₀ x + (α/r) · B (A x)          W₀ ∈ ℝ^{d_out×d_in} frozen
                                     A ∈ ℝ^{r×d_in},  B ∈ ℝ^{d_out×r}  trained,  r ≪ d
```

```text
          x ──────────────► W₀ (frozen, d_out × d_in) ───────────┐
          │                                                       ⊕ ──► h
          └──► A (r × d_in) ──► B (d_out × r) ──► × α/r ──────────┘
               "down-projection"   "up-projection"   (trainable: r(d_in + d_out) params)
```

**Initialization: why B = 0 and A ≠ 0.**

- `B = 0` makes ΔW = 0 at step 0, so the adapted model starts *exactly* as the base model. The LoRA listing asserts a max output difference of 0.0e+00 at init, in both NumPy and PyTorch.
- A must not also be zero. Look at the gradients:

```text
∂L/∂B = (α/r) · G (A x)ᵀ          G = ∂L/∂h (the upstream gradient)
∂L/∂A = (α/r) · Bᵀ G xᵀ
```

With B = 0, ∂L/∂A = 0, so on step 1 only B moves, driven by the random features Ax. From step 2 on, B ≠ 0 and A starts learning. If both were zero, both gradients would be zero forever. A has to be random to break the symmetry.

PEFT's default is "Kaiming-uniform for weight A and zeros for weight B", the same as Microsoft's reference implementation. Kaiming-uniform with a = √5 is exactly `U(±1/√d_in)`, which is what the NumPy listing uses. The original paper describes A as random Gaussian, and PEFT offers that as `init_lora_weights="gaussian"`.

**Parameters, memory, compute.**

| Quantity | Full fine-tune of one d×d matrix | LoRA rank r |
|---|---|---|
| Trainable params | d² | 2rd (r = 16, d = 4096: 131,072 = 0.78%) |
| fp32 weight + Adam m, v (12 B per trainable param) | 192 MiB (d = 4096) | 1.50 MiB (r = 16) |
| Forward FLOPs per token | 2d² | 2d² + 4rd |
| Backward | Activation gradients + **weight gradients for W₀** | Activation gradients only, plus the small A, B gradients |

LoRA Without Regret's per-matrix count is `2N² + 6NR` vs `3N²` FLOPs per pass, so LoRA costs "slightly more than two-thirds" of full fine-tuning compute (excluding attention). The bigger win is memory: no optimizer state and no weight gradients for W₀. **LoRA does not shrink activation memory**, because activations still flow through the frozen model and must be stored for backward. For long sequences, activations dominate, and you need gradient checkpointing or QLoRA on top.

**The scale α/r and why it exists.** Our NumPy listing trains three ranks with the same learning rate and compares early losses:

```text
        scale   r   loss@5  loss@20  loss@60
      alpha/r   4   0.0350   0.0203   0.0069
      alpha/r  16   0.0345   0.0156   0.0051
      alpha/r  64   0.0342   0.0141   0.0051
alpha/sqrt(r)   4   0.0344   0.0177   0.0071
alpha/sqrt(r)  16   0.0306   0.0087   0.0050
alpha/sqrt(r)  64   0.0228   0.0064   0.0049
loss@20 max/min across ranks: alpha/r 1.43x, alpha/sqrt(r) 2.74x
```

With α/r, the early curves are close across a 16× range of ranks (1.43× spread at step 20). With α/√r (rsLoRA), higher ranks move faster (2.74× spread). This is the property LoRA Without Regret relies on: "The 1/r factor makes the optimal LR approximately independent of the rank." In practice, you can sweep rank without re-tuning the learning rate. rsLoRA (Kalajdzievski, 2023) argues the opposite choice, α/√r, keeps *high-rank* adapters learning effectively instead of having their updates shrunk. PEFT exposes it as `use_rslora=True`. These are two defensible conventions. The bar-raiser point is to **re-tune the learning rate when you change both rank and convention**.

**Rank is a bias/variance knob.** The listing's task is a fine-tune whose true ΔW has rank 4, with noise floor 0.0050:

```text
  r  params  test (4096 rows)  train (192)  test (192)
  1     512            0.0192       0.0190      0.0290
  2    1024            0.0113       0.0111      0.0207
  4    2048            0.0050       0.0048      0.0167
  8    4096            0.0050       0.0045      0.0152
 16    8192            0.0050       0.0040      0.0171
 64   32768            0.0052       0.0017      0.0222
```

- **Below the intrinsic rank (r = 1, 2): bias.** Even with 4,096 rows the loss is stuck at 0.0192 / 0.0113, because the adapter cannot represent the change.
- **At or above it, with plenty of data:** every rank reaches the noise floor. Extra rank is harmless.
- **With little data (192 rows): variance.** Train loss keeps falling with rank (0.0017 at r = 64), test loss is U-shaped (best 0.0152 at r = 8, 0.0222 at r = 64). That's Ng's bias/variance diagnosis applied to one hyperparameter.

**Merging.** At inference, `W' = W₀ + (α/r)BA` is a single matrix, so a merged adapter adds **zero latency**. The NumPy listing measures merged vs unmerged outputs equal to 8.9e-15 in float64. Three production caveats from the listings:

1. **Unmerge is not bit-exact.** The PyTorch listing gets `max |W − W_original| = 1.86e-09` after merge then unmerge in fp32 (not bit-identical). Merge into a copy, or reload the base, when switching adapters on a merged model.
2. **Merging into bf16 loses part of a small delta.** With a realistic `|ΔW|` (median 5.7e-4 vs `|W|` median 1.6e-2), merging in bf16 rounds away **2.8%** of the delta's norm, because bf16's 8-bit mantissa can't represent small increments to larger weights. It is usually acceptable, but must be measured on your eval.
3. **Merging into a quantized base re-quantizes the base.** The QLoRA-style adapter was trained against `Q(W₀)`. Merging and re-quantizing, `Q(Q(W₀) + BA)`, produces a different base than the adapter was trained on. Output error vs the intended function: **4.7e-2**, vs 8.0e-15 unmerged. Serve quantized-base adapters unmerged, or merge into a high-precision base and re-evaluate before re-quantizing.

**What the 2025 evidence says about how to use LoRA.** Schulman and colleagues at Thinking Machines ("LoRA Without Regret", 2025-09-29) report:

- LoRA **matches full fine-tuning when it is not capacity-constrained**. That covers small-to-medium instruction-tuning and reasoning datasets. Beyond that, it learns less efficiently.
- **Apply it to all layers, especially the MLP/MoE layers.** Attention-only LoRA underperforms MLP-only LoRA even at matched parameter counts (attention-only rank 256 is worse than MLP-only rank 128). An independent reproduction found MLP + attention slightly better than MLP-only, so `target_modules="all-linear"` is the safe default.
- **The optimal LR is about 10× the full fine-tuning LR** (fitted multiplier 9.8, consistently across supervised and RL settings; about 15× suggested for very short runs).
- **RL needs very little capacity.** Rank-1 LoRA matched full fine-tuning for policy-gradient RL. Their argument: an episode carries roughly one bit of signal.
- LoRA tolerates **large batch sizes** less well than full fine-tuning, and raising the rank doesn't fix that.

Biderman et al. ("LoRA Learns Less and Forgets Less", 2024) add the complement. In heavy continued pre-training (code, math), full fine-tuning learns more, finding perturbations of much higher rank than typical LoRA configs. LoRA, in turn, better preserves the base model's other capabilities. **If forgetting matters (it usually does), keep a "nothing else broke" eval next to the task eval.**

### 1.9 The LoRA family `[GOOD-TO-KNOW: Architectural Literacy]`

| Variant | What changes | When it earns its keep | PEFT switch |
|---|---|---|---|
| **QLoRA** (Dettmers et al., 2023) | Frozen base stored in 4-bit NF4 (with double quantization and paged optimizers). The adapter trains in bf16 | Fits big models on small GPUs. The paper fine-tunes a 65B model on a single 48 GB GPU | Load the base with bitsandbytes 4-bit, then add LoRA |
| **rsLoRA** (Kalajdzievski, 2023) | Scale α/√r instead of α/r | High ranks that would otherwise learn too slowly | `use_rslora=True` |
| **DoRA** (Liu et al., 2024) | Split W into magnitude m and direction. LoRA updates the direction, and m is learned separately: `W' = m · (W₀ + BA)/‖W₀ + BA‖_col` | Closer to full-FT learning patterns. Costs more compute, so merge for inference | `use_dora=True` (incompatible with multi-adapter batching) |
| **PiSSA** (Meng et al., 2024) | Initialize A, B from the **top-r singular vectors of W₀** (Eckart–Young). The residual stays frozen | Faster convergence, lower quantization error than QLoRA, per the PEFT docs | `init_lora_weights="pissa"` or `"pissa_niter_[n]"` |
| **LoftQ** | Initialize LoRA so that `Q(W₀) + BA ≈ W₀` | Training on a quantized base | `init_lora_weights="loftq"` |
| **EVA** | Initialize from the SVD of *input activations*, and reallocate rank across layers by explained variance | Data-driven init, per-layer rank budgets | `init_lora_weights="eva"` |
| **OLoRA** | QR-based initialization (mutates the base weights before training) | Faster convergence in some reports | `init_lora_weights="olora"` |

**Intrinsic dimension** is the theory behind all of them. Aghajanyan et al. (2020) found that optimizing only a few hundred parameters, randomly projected into the full weight space, recovered about 90% of full fine-tuning performance on MRPC with RoBERTa. Pre-training is what makes downstream adaptation low-dimensional.

### 1.10 Multi-LoRA serving `[GOOD-TO-KNOW: Architectural Literacy]`

Because adapters are small, one GPU can hold one base model plus many tenants' adapters, and serve a batch where **each request uses a different adapter**:

```text
h_i = W₀ x_i + s · B_{a(i)} (A_{a(i)} x_i)        a(i) = adapter of request i

naive:    gather A_{a(i)}, B_{a(i)} per row  → materializes (batch × r × d) tensors
grouped:  sort/group rows by adapter, one small GEMM per adapter group
          (the SGMV kernel idea in Punica; S-LoRA adds paging of adapter weights)
```

The PyTorch listing (§3.4) checks both formulations against a per-row loop, agreeing to 1.9e-6. It also shows why kernels group rows: gathering `A[ids]` for just 64 rows materializes **4.0 MiB**, while grouping touches each of the 8 adapters once (64 KiB each).

**Capacity arithmetic** for a Llama-3-8B-shaped model (hidden 4096, MLP 14336, 32 layers, grouped-query K/V of 1024), with LoRA r = 16 on all seven linear maps per layer:

```text
q, o:            16·(4096+4096)  = 131,072 each   → 262,144
k, v:            16·(4096+1024)  =  81,920 each   → 163,840
gate, up, down:  16·(4096+14336) = 294,912 each   → 884,736
per layer = 1,310,720;  × 32 layers = 41,943,040 params ≈ 0.52% of 8.03B  ≈ 84 MB in bf16
```

So 100 tenants cost about **8.4 GB** of adapters on top of one ~16 GB base, instead of 100 × 16 GB separate fine-tunes. vLLM, S-LoRA-style servers and most managed fine-tuning platforms are built on this economics.

### 1.11 Matryoshka Representation Learning (MRL) `[MUST-KNOW: Core AI Engineer Edge]`

**Problem.** A standard embedding spreads information evenly across coordinates (rotation invariance again), so its first m coordinates are a random projection. Truncating it throws information away roughly in proportion.

**Kusupati et al.'s fix (NeurIPS 2022).** Train with a loss applied to **nested prefixes** of the same vector:

```text
L_MRL = Σ_{m ∈ M} c_m · L( f(x)_{1:m} )         M = {8, 16, 32, …, d}  (O(log d) sizes)
```

Each prefix gets its own head (or the shared contrastive objective), and the gradients from small prefixes push the most useful information into the first coordinates. Like nested dolls, the 64-dim prefix is a complete, coarser embedding.

```text
 f(x) = [ ■■■■ | ■■■■ | ■■■■■■■■ | ■■■■■■■■■■■■■■■■ | ... ]
          1:4    1:8      1:16          1:32
          └ coarse ───────────────────────────────→ fine ┘
 each prefix, renormalized, is a usable embedding
```

The paper reports up to **14× smaller embeddings** at the same ImageNet-1K classification accuracy, and up to **14× real-world speed-ups** for large-scale retrieval on ImageNet-1K and 4K. Per the authors' slides, the 14× retrieval figure is for ImageNet-1K (6× on 4K), with HNSW used for shortlisting. It also reports up to 2% accuracy gains for long-tail few-shot classification.

Our linear toy reproduces the mechanism (§3.5): same encoder, same data, standard loss vs MRL loss, scored by nearest-class-centroid accuracy on the first m dims:

```text
  m  standard: first m  standard: PCA to m  MRL: first m
  4              0.196               0.477         0.503
  8              0.528               0.857         0.851
 16              0.812               0.969         0.940
 64              0.988               0.988         0.977
```

What's honest about this table:

- **Truncating a standard embedding is bad** (0.528 at m = 8). MRL's prefix works (0.851).
- **PCA fitted on the corpus is a strong post-hoc baseline** in this linear toy (0.857 at m = 8). MRL's advantage here isn't accuracy. It's that MRL needs no fitted projection: no sign-ambiguity versioning (§1.3), no refit on drift (§1.5), and it works out of the box through a vendor API where you never see the training corpus. The paper's deep-network results show larger gaps over post-hoc compression.
- **MRL can cost a little at full dimension** (0.977 vs 0.988), since some capacity goes to making the prefixes useful.

**Funnel (adaptive) retrieval.** Shortlist with a short prefix, then rerank the shortlist at full dimension:

```text
precision@10 (same class): 64-d brute force 0.945 | 16-d only 0.898 | 16-d shortlist(100) -> 64-d rerank 0.944
funnel top-10 overlap with 64-d brute force 0.998; multiply-adds per query 102,400 vs 384,000 (3.8x fewer)
```

**Truncate, then renormalize. Always.** A prefix of a unit vector is not a unit vector (here, 16-dim prefixes have norms from 0.475 to 0.864). Rank prefixes by raw dot product and the top-10 differs from the renormalized cosine top-10 for **100.0%** of queries.

**Vendor reality (verified against current docs, 2026-10):**

| Provider / model | How to get a shorter vector | Normalization after shortening |
|---|---|---|
| OpenAI `text-embedding-3-small` / `-large` | `dimensions` parameter (default 1536 / 3072) | The guide recommends the `dimensions` parameter. If you truncate manually, "you need to be sure to normalize" |
| Google `gemini-embedding-001` | `output_dimensionality` (128–3072; recommended 768, 1536, 3072) | Only the 3072-d default is normalized: "you must manually normalize non-3072 dimensions" |
| Google `gemini-embedding-2` | `output_dimensionality` | "Automatic renormalization for non-default dimensions" |

OpenAI's January 2024 launch post reported that `text-embedding-3-large` shortened to 256 dims still scores higher on MTEB than `text-embedding-ada-002` at 1536 (62.0 vs 61.0, as quoted in Supabase's Matryoshka write-up; openai.com refuses automated fetches, so we couldn't re-read the original ⚠). The guide lists full-size MTEB averages of 64.6% for `-large`, 62.3% for `-small` and 61.0% for ada-002.

### 1.12 The embedding-compression decision matrix `[MUST-KNOW: Core AI Engineer Edge]`

| Method | Bytes/vector (from 1024-d fp32 = 4096 B) | Needs fitting? | Recall evidence in this KB | Failure mode |
|---|---:|---|---|---|
| fp16 / bf16 | 2048 | No | 1.000 recall@10 (01.1 §3.3) | None for ranking. Watch tight thresholds |
| int8 symmetric | 1024 | A scale (calibration sample) | 0.980 raw; affine without correction 0.629 | Affine offset bias (01.1 §1.10) |
| binary + rescoring | 128 + rescoring tier | No (centring optional) | 0.365 → 0.995 with ×10 rescoring | Using Hamming as the final ranker |
| MRL prefix (API `dimensions`) | 4·m | No (trained in) | Prefix 8 of 64: 0.851 vs 0.528 truncating a standard model | Forgetting to renormalize; truncating a non-MRL model |
| PCA (centred, + mean coordinate) | 4·(k+1) | Yes: fit, version, refit | 0.995 at k = 64 | Sign flips across refits; drift (0.243 on a new topic family) |
| MRL prefix + binary first stage → full-dim rerank | m/8 + rescoring tier | No | The composition of the rows above | Rescoring IO sized wrong |

The production recipe that keeps coming out of the measurements: **a cheap first stage (short MRL prefix and/or binary) for candidates, an exact-ish second stage (full-dim fp16 or int8) for the ranking, and a measured ceiling between them.**

### 1.13 Low rank in attention and recommenders `[GOOD-TO-KNOW: Architectural Literacy]`

- **Multi-head latent attention (MLA, DeepSeek-V2/V3)** compresses keys and values through a shared low-rank latent per token. The KV cache stores the latent, not full K/V. That's a learned low-rank factorization at the heart of long-context serving economics (the Production AI Engineering KB, Folder 01, works through the byte math).
- **Matrix factorization recommenders** approximate the user × item matrix by `U Vᵀ` with rank k. Two-tower retrieval is its neural descendant, and the dot-product MIPS issues of 01.1 §1.4 come from here.
- **Latent semantic analysis** is a truncated SVD of a term × document matrix. Historically important, and now mostly a baseline.

### 1.14 Perturbation theory: Weyl, Davis–Kahan `[SKIP: Academic/Research Only]`

How much singular values and subspaces move when the matrix is perturbed (Weyl's inequality for values, Davis–Kahan sin-θ for subspaces) is what formally justifies "PCA is stable when the spectral gap is large". For production, the empirical versions are enough: refit stability across bootstrap samples, and reconstruction-error monitoring.

---

## 2. Where It Beats an LLM in Production

### 2.1 A small adapted model vs prompting a frontier model

For narrow, high-volume tasks (classification, extraction into a fixed schema, routing, reformatting, short domain-specific generation), the economics favour **a small open model plus a LoRA adapter** over prompting a large model every time:

| Dimension | Prompting a frontier model | Small model + LoRA (self-hosted or managed) |
|---|---|---|
| Per-request cost | Every request pays for instructions + few-shot examples + the input, at frontier rates (01.1 §2: 113×–4,533× an embedding call, by tier) | The instructions are "baked in": short prompts on a small model |
| Latency | Long prompts mean long prefill. Generation runs at frontier-model speed | Short prompts, small model, often co-located |
| Behaviour control | Prompt-level. Format drift needs retries and validators | The output format is learned. Validators still run, but fail less often |
| Knowledge freshness | Best with RAG | Same: **fine-tuning is for behaviour, not for facts** (§4) |
| Multi-tenant customization | One prompt per tenant (prompt caching helps) | One adapter per tenant: ~84 MB each for an 8B model at r = 16 on all layers (§1.10) |
| Upfront cost | None | Labelled data, training runs, an eval suite, and the serving platform |

When it loses: open-ended reasoning, broad world knowledge, low volume (the fixed costs dominate), and tasks that change faster than you can retrain. A cascade (Folder 07) usually takes the cheap path on the easy majority and keeps the frontier model for the rest.

### 2.2 Compressed embeddings for routers, caches and first-stage retrieval

Every component in 01.1 §2 is memory- and bandwidth-bound in its scoring loop, and dimension cuts help linearly:

- A semantic cache holding 50M entries at 3072-d fp32 needs **614 GB**. At a 256-d MRL prefix in fp16 it needs **25.6 GB**, which fits in RAM on one node, and the scan is 12× cheaper. Re-derive the cache threshold at the new dimension, though (01.1 §1.7): the geometry changed.
- A router over 12 centroids doesn't need compression for speed (19 µs). It *does* benefit from MRL when the same embedding also feeds a cache and retrieval: one embedding call, three prefix lengths.
- First-stage retrieval: the funnel pattern (§1.11) keeps the full-dimension top-10 with 98–100% overlap at 3.8× fewer multiply-adds in our toy, and composes with binary codes (01.1 §1.10).

### 2.3 PCA/SVD as analytics instead of an LLM

- **Embedding drift visualization and alarms:** PCA reconstruction error of incoming vectors against a frozen basis is a cheap, interpretable drift score (§1.5, and Folder 07).
- **Corpus structure:** the top principal components of a corpus's embeddings often line up with its biggest axes of variation: language, document type, template boilerplate. That's a 5-minute diagnosis before you pay an LLM to "summarize what's in the corpus". Folder 03 adds clustering.

---

## 3. Production Code Blueprint

### 3.1 SVD geometry, Eckart–Young, randomized SVD, sign ambiguity, Procrustes

```python
"""svd_geometry_eckart_young.py - SVD as rotate-scale-rotate, and why truncated SVD is the best low-rank compression.

  1. A 2x2 matrix maps the unit circle to an ellipse whose semi-axes are the singular values.
  2. A = U S V^T exactly; U, V orthonormal; S^2 = eigenvalues of A^T A.
  3. Eckart-Young-Mirsky: ||A - A_k||_F = sqrt(sum_{i>k} s_i^2) and ||A - A_k||_2 = s_{k+1}; no rank-k matrix does better.
  4. Randomized SVD (Halko-Martinsson-Tropp, what sklearn uses) gets the top-k almost exactly at a fraction of the cost.
  5. Singular vectors are only defined up to sign: never compare projections from two independent fits.
  6. Orthogonal Procrustes (one SVD) aligns two embedding spaces, but only the linear part of the difference.
"""
import time

import numpy as np
from sklearn.utils.extmath import randomized_svd

rng = np.random.default_rng(1)

print("== 1. unit circle -> ellipse ==")
A2 = np.array([[2.0, 1.0], [0.5, 1.5]])
U, s, Vt = np.linalg.svd(A2)
t = np.linspace(0, 2 * np.pi, 3600, endpoint=False)
circle = np.stack([np.cos(t), np.sin(t)])
img = A2 @ circle
r = np.linalg.norm(img, axis=0)
print(f"singular values s = {s.round(4)}; max ||Ax|| on circle = {r.max():.4f}, min = {r.min():.4f}")
print(f"input direction achieving the max (v1) = {Vt[0].round(4)}, output direction (u1) = {U[:, 0].round(4)}")
assert abs(r.max() - s[0]) < 1e-4 and abs(r.min() - s[1]) < 1e-4
H, W = 15, 41
grid = [[" "] * W for _ in range(H)]
for x, y in img.T[::30]:
    gx, gy = int(round((x + 2.5) / 5 * (W - 1))), int(round((2.5 - y) / 5 * (H - 1)))
    if 0 <= gx < W and 0 <= gy < H:
        grid[gy][gx] = "*"
for k_, (x, y) in enumerate((U[:, 0] * s[0], U[:, 1] * s[1])):
    for f in np.linspace(0, 1, 12):
        gx, gy = int(round((f * x + 2.5) / 5 * (W - 1))), int(round((2.5 - f * y) / 5 * (H - 1)))
        if 0 <= gx < W and 0 <= gy < H and grid[gy][gx] == " ":
            grid[gy][gx] = "1" if k_ == 0 else "2"
grid[H // 2][W // 2] = "o"
print("image of the unit circle under A (1 = s1*u1 axis, 2 = s2*u2 axis):")
print("\n".join(("   " + "".join(row)).rstrip() for row in grid if "".join(row).strip()))

print("\n== 2. exact factorization ==")
A = rng.standard_normal((300, 200))
U, s, Vt = np.linalg.svd(A, full_matrices=False)
print(f"||A - U S V^T||_max = {np.abs(A - (U * s) @ Vt).max():.2e}   ||U^T U - I|| = {np.abs(U.T @ U - np.eye(200)).max():.2e}"
      f"   ||V^T V - I|| = {np.abs(Vt @ Vt.T - np.eye(200)).max():.2e}")
ev = np.sort(np.linalg.eigvalsh(A.T @ A))[::-1]
print(f"max |s_i^2 - eig_i(A^T A)| / s_1^2 = {np.abs(s ** 2 - ev).max() / s[0] ** 2:.2e}")
assert np.abs(A - (U * s) @ Vt).max() < 1e-10

print("\n== 3. Eckart-Young-Mirsky on low-rank signal + noise (400 x 300) ==")
m, n = 400, 300
sig = np.geomspace(50, 2, 20)
X = (np.linalg.qr(rng.standard_normal((m, 20)))[0] * sig) @ np.linalg.qr(rng.standard_normal((n, 20)))[0].T
A = X + 0.3 * rng.standard_normal((m, n))
U, s, Vt = np.linalg.svd(A, full_matrices=False)
fro = np.linalg.norm(A)
print(f"{'k':>3} {'||A-A_k||_F':>12} {'sqrt(tail s^2)':>15} {'||A-A_k||_2':>12} {'s_k+1':>8} {'best random':>12} {'energy kept':>11}")
for k in (1, 5, 10, 20, 40):
    Ak = (U[:, :k] * s[:k]) @ Vt[:k]
    e_f, e_2 = np.linalg.norm(A - Ak), np.linalg.norm(A - Ak, 2)
    tail = np.sqrt((s[k:] ** 2).sum())
    best_rand = min(np.linalg.norm(A - (Qr := np.linalg.qr(A @ rng.standard_normal((n, k)))[0]) @ (Qr.T @ A))
                    for _ in range(50))                               # best of 50 random rank-k subspaces
    print(f"{k:>3} {e_f:>12.4f} {tail:>15.4f} {e_2:>12.4f} {s[k]:>8.4f} {best_rand:>12.4f} {1 - e_f ** 2 / fro ** 2:>11.4f}")
    assert abs(e_f - tail) < 1e-8 * fro and abs(e_2 - s[k]) < 1e-8 * s[0] and best_rand >= e_f - 1e-9
print("storage of a rank-k factorization of an m x n matrix: k(m+n) vs mn")
for (mm, nn, k) in ((4096, 4096, 16), (4096, 11008, 16), (8192, 28672, 64)):
    print(f"  {mm} x {nn}, k={k}: {k * (mm + nn):,} vs {mm * nn:,} params ({k * (mm + nn) / (mm * nn):.3%})")

print("\n== 4. randomized SVD vs full SVD (2000 x 1000, top-20; one measured run) ==")
sig = np.geomspace(100, 1, 60)
Big = (np.linalg.qr(rng.standard_normal((2000, 60)))[0] * sig) @ np.linalg.qr(rng.standard_normal((1000, 60)))[0].T
Big += 0.05 * rng.standard_normal(Big.shape)
t0 = time.perf_counter()
s_full = np.linalg.svd(Big, compute_uv=False)
t_full = time.perf_counter() - t0
t0 = time.perf_counter()
_, s_rand, _ = randomized_svd(Big, n_components=20, n_oversamples=10, n_iter=4, random_state=0)
t_rand = time.perf_counter() - t0
rel = np.abs(s_rand - s_full[:20]) / s_full[:20]
print(f"full SVD {t_full * 1e3:.0f} ms, randomized top-20 {t_rand * 1e3:.0f} ms; max relative error of top-20 s = {rel.max():.2e}")
assert rel.max() < 1e-3

print("\n== 5. sign ambiguity ==")
U, s, Vt = np.linalg.svd(A, full_matrices=False)
U2, Vt2 = U.copy(), Vt.copy()
U2[:, 0] *= -1
Vt2[0] *= -1
print(f"flip u1 and v1 together: ||U S V^T - U' S V'^T||_max = {np.abs((U * s) @ Vt - (U2 * s) @ Vt2).max():.2e}"
      " -> both are valid SVDs")
_, _, Vb = np.linalg.svd(A[rng.permutation(m)][: m // 2 + 50], full_matrices=False)
print(f"refit on a different sample: sign(v_i . v_i') for the top-5 = {np.sign((Vt[:5] * Vb[:5]).sum(1)).astype(int)}"
      " -> projections from two fits are not comparable without alignment")

print("\n== 6. orthogonal Procrustes: bridging two embedding spaces with an SVD ==")
d, n_pair, n_doc = 128, 2000, 5000
l2n = lambda x: x / np.linalg.norm(x, axis=1, keepdims=True)
old = l2n(rng.standard_normal((n_doc, 16)) @ rng.standard_normal((16, d)) + 0.3 * rng.standard_normal((n_doc, d)))
Qtrue = np.linalg.qr(rng.standard_normal((d, d)))[0]
noise = 0.01 * rng.standard_normal((n_doc, d))                       # same noise for both "new models"
spaces = {"rotation + noise": l2n(l2n(old @ Qtrue) + noise),
          "nonlinear warp": l2n(l2n(np.tanh(12 * (old @ Qtrue))) + noise)}
qi = rng.choice(n_doc, 300, replace=False)
truth = np.argsort(-(old[qi] @ old.T), axis=1)[:, :10]
for name, new in spaces.items():
    pairs = rng.choice(n_doc, n_pair, replace=False)                  # docs embedded by BOTH models
    Uo, _, Vo = np.linalg.svd(new[pairs].T @ old[pairs])              # R = argmin ||new R - old||_F, R orthogonal
    R = Uo @ Vo
    found = np.argsort(-((new[qi] @ R) @ old.T), axis=1)[:, :10]      # new-model query vs OLD-model index
    raw = np.argsort(-(new[qi] @ old.T), axis=1)[:, :10]              # no bridge at all
    rec = lambda f: np.mean([len(set(a) & set(b)) / 10 for a, b in zip(f, truth)])
    print(f"{name:17s} recall@10 of new-model queries on the old index: no bridge {rec(raw):.3f}, Procrustes {rec(found):.3f}")
    if name == "rotation + noise":
        assert rec(found) > 0.8 > rec(raw) + 0.5
        rot_rec = rec(found)
    else:
        assert rec(found) < rot_rec
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the two timings in part 4, which are one measured run):

```text
== 1. unit circle -> ellipse ==
singular values s = [2.5583 0.9772]; max ||Ax|| on circle = 2.5583, min = 0.9772
input direction achieving the max (v1) = [-0.7678 -0.6407], output direction (u1) = [-0.8507 -0.5257]
image of the unit circle under A (1 = s1*u1 axis, 2 = s2*u2 axis):
                          ****************
                    ******               *
                ****2                  ***
            ****    222               **
         ****        12o          ****
       **        11 1          ****
     ***    1 11           ****
     * 1 11          ******
     ****************

== 2. exact factorization ==
||A - U S V^T||_max = 1.29e-14   ||U^T U - I|| = 3.11e-15   ||V^T V - I|| = 3.00e-15
max |s_i^2 - eig_i(A^T A)| / s_1^2 = 2.43e-15

== 3. Eckart-Young-Mirsky on low-rank signal + noise (400 x 300) ==
  k  ||A-A_k||_F  sqrt(tail s^2)  ||A-A_k||_2    s_k+1  best random energy kept
  1     130.0337        130.0337      42.8325  42.8325     134.2404      0.1343
  5     109.9301        109.9301      23.2369  23.2369     125.3249      0.3813
 10     102.1069        102.1069      12.3824  12.3824     119.5872      0.4662
 20      96.0095         96.0095      10.2834  10.2834     110.0254      0.5281
 40      85.7248         85.7248       9.0870   9.0870      99.9236      0.6238
storage of a rank-k factorization of an m x n matrix: k(m+n) vs mn
  4096 x 4096, k=16: 131,072 vs 16,777,216 params (0.781%)
  4096 x 11008, k=16: 241,664 vs 45,088,768 params (0.536%)
  8192 x 28672, k=64: 2,359,296 vs 234,881,024 params (1.004%)

== 4. randomized SVD vs full SVD (2000 x 1000, top-20; one measured run) ==
full SVD 331 ms, randomized top-20 68 ms; max relative error of top-20 s = 8.47e-08

== 5. sign ambiguity ==
flip u1 and v1 together: ||U S V^T - U' S V'^T||_max = 0.00e+00 -> both are valid SVDs
refit on a different sample: sign(v_i . v_i') for the top-5 = [-1 -1  1  1 -1] -> projections from two fits are not comparable without alignment

== 6. orthogonal Procrustes: bridging two embedding spaces with an SVD ==
rotation + noise  recall@10 of new-model queries on the old index: no bridge 0.000, Procrustes 0.936
nonlinear warp    recall@10 of new-model queries on the old index: no bridge 0.001, Procrustes 0.859

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 3 is the whole theorem in a table.** The Frobenius residual equals the tail-energy formula to every printed digit, the spectral residual equals σ_{k+1}, and the best of 50 random rank-k subspaces is always worse. Notice how flat the residual gets after k = 20: that's where the signal ends.
- **Part 5** is why fitted projections need versioning. A resampled refit flips three of the top five axes.
- **Part 6** is the migration bridge: zero recall without alignment, 0.936 with Procrustes when the difference is a rotation, and 0.859 when it isn't.

### 3.2 PCA for embedding compression: centring, whitening, drift

```python
"""pca_embedding_compression.py - compressing 768-d embeddings: PCA vs uncentred SVD vs random projection vs truncation.

  1. PCA = SVD of the CENTRED data; our own SVD-PCA matches sklearn's PCA (up to sign).
  2. Recall@10 against exact full-dimension search, and same-topic precision@10, at k = 32..256 dims.
  3. Centring picks a better subspace, but cosines in the CENTRED space are a different metric; one extra
     coordinate (the mean's off-subspace part) restores the original geometry exactly.
  4. Whitening past the intrinsic dimension amplifies noise and destroys both recall and topic precision.
  5. A PCA basis fitted on yesterday's corpus loses directions that a new topic family needs.
"""
import numpy as np
from sklearn.decomposition import PCA

rng = np.random.default_rng(21)
D, LAT, N, Q, K = 768, 48, 20_000, 300, 10


def l2n(x):
    return x / np.linalg.norm(x, axis=-1, keepdims=True)


def topk(s, k):
    idx = np.argpartition(-s, k, axis=1)[:, :k]
    return np.take_along_axis(idx, np.take_along_axis(-s, idx, axis=1).argsort(axis=1, kind="stable"), axis=1)


P = np.linalg.qr(rng.standard_normal((D, LAT)))[0]
mu = l2n(rng.standard_normal(D))
scale_old = np.r_[np.geomspace(3.0, 0.6, 40), np.full(8, 0.05)]       # old topics barely use latent dims 40..47
scale_new = np.r_[np.full(32, 0.3), np.full(16, 2.5)]                 # a new topic family lives in dims 32..47


def corpus(n, n_topics, scale, seed):
    r = np.random.default_rng(seed)
    centres = r.standard_normal((n_topics, LAT)) * scale
    lab = r.integers(0, n_topics, n)
    z = centres[lab] + 0.9 * r.standard_normal((n, LAT)) * np.maximum(scale, 0.3)
    x = z @ P.T + 0.02 * r.standard_normal((n, D)) + 1.2 * mu * np.linalg.norm(scale) / 4
    return l2n(x).astype(np.float32), lab


docs, lab = corpus(N, 150, scale_old, 1)
qi = rng.integers(0, N, Q)
qs = l2n(docs[qi] + 0.01 * rng.standard_normal((Q, D))).astype(np.float32)
truth = topk(qs @ docs.T, K)
fit = docs[rng.choice(N, 5000, replace=False)]


def evaluate(proj_d, proj_q, truth, lab_d, lab_q):
    found = topk(l2n(proj_q) @ l2n(proj_d).T, K)
    rec = np.mean([len(set(f) & set(t)) / K for f, t in zip(found, truth)])
    prec = np.mean(lab_d[found] == lab_q[:, None])
    return rec, prec


print("== 1. our SVD-PCA vs sklearn PCA ==")
mean = fit.mean(0)
_, s, Vt = np.linalg.svd(fit - mean, full_matrices=False)
sk = PCA(n_components=64, svd_solver="full").fit(fit)
align = np.abs((Vt[:64] * sk.components_).sum(1))
print(f"min |<v_i, sklearn_i>| over 64 components = {align.min():.6f}; "
      f"max |explained variance diff| = {np.abs(s[:64] ** 2 / (len(fit) - 1) - sk.explained_variance_).max():.2e}")
cum = np.cumsum(s ** 2) / (s ** 2).sum()
print("cumulative explained variance: " + "  ".join(f"k={k}: {cum[k - 1]:.3f}" for k in (8, 16, 32, 48, 64, 128)))
assert align.min() > 0.9999

print(f"\nfull {D}-d exact search: same-topic precision@10 = {np.mean(lab[truth] == lab[qi][:, None]):.3f}")
_, s_u, Vt_u = np.linalg.svd(fit, full_matrices=False)                  # NOT centred (TruncatedSVD-style)
print(f"corpus mean norm ||mean|| = {np.linalg.norm(mean):.3f} (unit vectors, so this is the anisotropy); "
      f"uncentred SVD |<v1, mean direction>| = {abs(Vt_u[0] @ l2n(mean)):.3f}")
print(f"\n{'k':>4} | {'PCA centred':>11} | {'PCA + 1 mean':>12} | {'uncentred':>11} | {'random proj':>11} | "
      f"{'truncate':>11} | {'PCA+whiten':>11}")
print(f"{'':>4} | {'rec  prec':>11} | {'rec  prec':>12} | " + " | ".join(f"{'rec  prec':>11}" for _ in range(4)))


def with_mean(x, W):
    """k+1 coords of mean + W W^T (x - mean) in the orthonormal basis [W, m_perp / |m_perp|]."""
    m_in = W.T @ mean
    m_perp = mean - W @ m_in
    return np.hstack([(x - mean) @ W + m_in, np.full((len(x), 1), np.linalg.norm(m_perp))])


res = {}
for k in (32, 64, 128, 256):
    W = Vt[:k].T
    R = rng.standard_normal((D, k)) / np.sqrt(k)
    variants = {
        "pca": ((docs - mean) @ W, (qs - mean) @ W),
        "pcm": (with_mean(docs, W), with_mean(qs, W)),
        "unc": (docs @ Vt_u[:k].T, qs @ Vt_u[:k].T),
        "rnd": (docs @ R, qs @ R),
        "trn": (docs[:, :k], qs[:, :k]),
        "wht": ((docs - mean) @ W / s[:k], (qs - mean) @ W / s[:k]),
    }
    row = {name: evaluate(d_, q_, truth, lab, lab[qi]) for name, (d_, q_) in variants.items()}
    res[k] = row
    cells = [f"{row[n][0]:.3f} {row[n][1]:.3f}" for n in ("pca", "pcm", "unc", "rnd", "trn", "wht")]
    print(f"{k:>4} | {cells[0]:>11} | {cells[1]:>12} | " + " | ".join(f"{c:>11}" for c in cells[2:]))
assert res[64]["pcm"][0] >= max(res[64]["pca"][0], res[64]["unc"][0]) - 0.005 and res[64]["pca"][0] > res[64]["rnd"][0] + 0.2
assert res[128]["wht"][1] < res[32]["wht"][1] - 0.2
print(f"bytes per vector: {D * 4} (fp32 {D}-d) vs {64 * 4} (fp32 64-d) vs {64} (int8 64-d) -> {D * 4 // 64}x smaller at int8 64-d")

print("\n== 5. distribution shift: PCA basis fitted on the old corpus, new topic family arrives ==")
new_docs, new_lab = corpus(5000, 30, scale_new, 2)
nq = rng.integers(0, 5000, Q)
new_qs = l2n(new_docs[nq] + 0.01 * rng.standard_normal((Q, D))).astype(np.float32)
new_truth = topk(new_qs @ new_docs.T, K)
both = np.vstack([fit, new_docs[:2000]])
mean2 = both.mean(0)
_, _, Vt2 = np.linalg.svd(both - mean2, full_matrices=False)
print(f"{'k':>4} {'old basis on new docs':>22} {'refit basis on new docs':>24}")
for k in (32, 64):
    old = evaluate((new_docs - mean) @ Vt[:k].T, (new_qs - mean) @ Vt[:k].T, new_truth, new_lab, new_lab[nq])
    ref = evaluate((new_docs - mean2) @ Vt2[:k].T, (new_qs - mean2) @ Vt2[:k].T, new_truth, new_lab, new_lab[nq])
    print(f"{k:>4} {old[0]:>14.3f} recall {ref[0]:>16.3f} recall")
    if k == 32:
        assert ref[0] > old[0] + 0.1
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. our SVD-PCA vs sklearn PCA ==
min |<v_i, sklearn_i>| over 64 components = 0.999999; max |explained variance diff| = 6.33e-08
cumulative explained variance: k=8: 0.502  k=16: 0.758  k=32: 0.960  k=48: 0.998  k=64: 0.998  k=128: 0.999

full 768-d exact search: same-topic precision@10 = 0.890
corpus mean norm ||mean|| = 0.232 (unit vectors, so this is the anisotropy); uncentred SVD |<v1, mean direction>| = 0.205

   k | PCA centred | PCA + 1 mean |   uncentred | random proj |    truncate |  PCA+whiten
     |   rec  prec |    rec  prec |   rec  prec |   rec  prec |   rec  prec |   rec  prec
  32 | 0.895 0.865 |  0.904 0.866 | 0.895 0.862 | 0.347 0.630 | 0.376 0.677 | 0.549 0.933
  64 | 0.956 0.891 |  0.995 0.890 | 0.995 0.890 | 0.529 0.781 | 0.535 0.801 | 0.080 0.210
 128 | 0.955 0.891 |  0.994 0.890 | 0.994 0.890 | 0.665 0.832 | 0.668 0.849 | 0.030 0.059
 256 | 0.956 0.891 |  0.996 0.891 | 0.996 0.891 | 0.758 0.881 | 0.783 0.886 | 0.033 0.050
bytes per vector: 3072 (fp32 768-d) vs 256 (fp32 64-d) vs 64 (int8 64-d) -> 48x smaller at int8 64-d

== 5. distribution shift: PCA basis fitted on the old corpus, new topic family arrives ==
   k  old basis on new docs  refit basis on new docs
  32          0.243 recall            0.658 recall
  64          0.974 recall            0.972 recall

ALL ASSERTIONS PASSED
```

How to read it:

- **Recall vs precision.** "rec" is recall@10 against exact full-dimension neighbours. "prec" is same-topic precision@10, a stand-in for task quality. The two can disagree (whitening at k = 32), so a compression decision needs both.
- **The k + 1 trick** (PCA + 1 mean) is the best or tied for best at every k. One extra float buys the original geometry back.
- **The drift block.** At k = 32 the old basis gets 0.243 recall on a new topic family vs 0.658 refitted. If you compress with PCA, monitoring reconstruction error is not optional.

### 3.3 LoRA from scratch: hand-written gradients, rank sweep, scaling, merge, extraction

```python
"""lora_from_scratch_numpy.py - LoRA's matrix math with hand-written gradients: rank as a bias/variance knob, merge, extraction.

Task: a frozen W0 must become W0 + dW*, where dW* has rank 4 (the "intrinsic rank" of the fine-tune).
  1. B = 0 at init, so the adapted layer starts exactly equal to the base layer.
  2. Rank r < 4 underfits (bias floor); r >= 4 reaches the noise floor; with little data a big r overfits (variance).
  3. The alpha/r scale makes early training nearly rank-independent; alpha/sqrt(r) (rsLoRA) does not.
  4. Merging W0 + s*B@A is exact in float64 and free at inference; re-quantizing after the merge is not.
  5. The singular spectrum of a full fine-tune's delta tells you the rank you need; truncated SVD extracts a LoRA.
"""
import numpy as np

rng = np.random.default_rng(42)
DIN = DOUT = 256
TRUE_RANK, NOISE, ALPHA = 4, 0.1, 16.0

W0 = rng.standard_normal((DOUT, DIN)) / np.sqrt(DIN)
Ut = np.linalg.qr(rng.standard_normal((DOUT, TRUE_RANK)))[0]
Vt_ = np.linalg.qr(rng.standard_normal((DIN, TRUE_RANK)))[0]
dW_true = (Ut * np.array([3.0, 2.0, 1.5, 1.0])) @ Vt_.T


def data(n, seed):
    r = np.random.default_rng(seed)
    X = r.standard_normal((n, DIN))
    return X, X @ (W0 + dW_true).T + NOISE * r.standard_normal((n, DOUT))


def mse(X, Y, W):
    return 0.5 * np.mean(np.sum((X @ W.T - Y) ** 2, axis=1)) / DOUT


def train_lora(X, Y, r, steps=400, lr=2e-3, scale="alpha/r", log_at=()):
    s = ALPHA / r if scale == "alpha/r" else ALPHA / np.sqrt(r)
    A = rng.uniform(-1, 1, (r, DIN)) / np.sqrt(DIN)              # PEFT default: kaiming-uniform(a=sqrt(5)) == U(+-1/sqrt(fan_in))
    B = np.zeros((DOUT, r))
    base = X @ W0.T
    m = [np.zeros_like(A), np.zeros_like(B)]
    v = [np.zeros_like(A), np.zeros_like(B)]
    logs = {}
    for t in range(1, steps + 1):
        H = X @ A.T                                                # (n, r)
        R = (base + s * H @ B.T - Y) / (len(X) * DOUT)            # dL/dY_hat
        gB = s * R.T @ H
        gA = (s * R @ B).T @ X
        for i, (p, g) in enumerate(((A, gA), (B, gB))):          # Adam, bias-corrected
            m[i] = 0.9 * m[i] + 0.1 * g
            v[i] = 0.999 * v[i] + 0.001 * g * g
            p -= lr * (m[i] / (1 - 0.9 ** t)) / (np.sqrt(v[i] / (1 - 0.999 ** t)) + 1e-8)
        if t in log_at:
            logs[t] = mse(X, Y, W0 + s * B @ A)
    return A, B, s, logs


Xtr, Ytr = data(4096, 1)
Xte, Yte = data(2048, 2)
floor = 0.5 * NOISE ** 2
print(f"noise floor {floor:.4f}; frozen base (no adapter) test loss {mse(Xte, Yte, W0):.4f}")

print("\n== 1. B = 0 at init ==")
A0 = rng.uniform(-1, 1, (8, DIN)) / np.sqrt(DIN)
B0 = np.zeros((DOUT, 8))
print(f"max |adapted - base| output at step 0 = {np.abs(Xte @ (W0 + 2.0 * B0 @ A0).T - Xte @ W0.T).max():.1e}")

print("\n== 2. rank sweep: 4096 training rows vs 192 training rows ==")
Xs, Ys = Xtr[:192], Ytr[:192]
print(f"{'r':>3} {'params':>7} {'test (4096 rows)':>17} {'train (192)':>12} {'test (192)':>11}")
big, small = {}, {}
for r in (1, 2, 4, 8, 16, 64):
    A, B, s, _ = train_lora(Xtr, Ytr, r)
    big[r] = mse(Xte, Yte, W0 + s * B @ A)
    A2, B2, s2, _ = train_lora(Xs, Ys, r, steps=600)
    small[r] = (mse(Xs, Ys, W0 + s2 * B2 @ A2), mse(Xte, Yte, W0 + s2 * B2 @ A2))
    print(f"{r:>3} {r * (DIN + DOUT):>7} {big[r]:>17.4f} {small[r][0]:>12.4f} {small[r][1]:>11.4f}")
    if r == 16:
        A16, B16, s16 = A, B, s
assert big[1] > 3 * big[4] and abs(big[4] - floor) < 0.2 * floor
assert small[64][0] < small[4][0] and small[64][1] > small[4][1]

print("\n== 3. early training: alpha/r vs alpha/sqrt(r), same learning rate ==")
print(f"{'scale':>13} {'r':>3} {'loss@5':>8} {'loss@20':>8} {'loss@60':>8}")
curves = {}
for scale in ("alpha/r", "alpha/sqrt(r)"):
    for r in (4, 16, 64):
        *_, logs = train_lora(Xtr, Ytr, r, steps=60, scale=scale, log_at=(5, 20, 60))
        curves[(scale, r)] = logs
        print(f"{scale:>13} {r:>3} {logs[5]:>8.4f} {logs[20]:>8.4f} {logs[60]:>8.4f}")
spread = lambda sc: max(curves[(sc, r)][20] for r in (4, 16, 64)) / min(curves[(sc, r)][20] for r in (4, 16, 64))
print(f"loss@20 max/min across ranks: alpha/r {spread('alpha/r'):.2f}x, alpha/sqrt(r) {spread('alpha/sqrt(r)'):.2f}x")
assert spread("alpha/r") < spread("alpha/sqrt(r)")

print("\n== 4. merge ==")
W_merged = W0 + s16 * B16 @ A16
unmerged = Xte @ W0.T + s16 * (Xte @ A16.T) @ B16.T
print(f"float64: max |merged - unmerged| = {np.abs(Xte @ W_merged.T - unmerged).max():.2e}  (merge is free and exact)")


def q8(W):                                                       # per-row absmax int8, then dequantize
    sc = np.abs(W).max(1, keepdims=True) / 127
    return np.round(W / sc).clip(-127, 127) * sc


Wq = q8(W0)                                                      # QLoRA-style: the adapter is trained on the quantized base
target = Xte @ (Wq + s16 * B16 @ A16).T
print(f"quantized base: |unmerged Q(W0) + BA - target| = {np.abs(Xte @ Wq.T + s16 * (Xte @ A16.T) @ B16.T - target).max():.2e}; "
      f"|Q(Q(W0) + BA) - target| = {np.abs(Xte @ q8(Wq + s16 * B16 @ A16).T - target).max():.2e}")
assert np.abs(Xte @ q8(Wq + s16 * B16 @ A16).T - target).max() > 1e-3

print("\n== 5. spectrum of the learned delta and LoRA extraction from a full fine-tune ==")
sv_lora = np.linalg.svd(s16 * B16 @ A16, compute_uv=False)
print(f"true dW singular values: {np.linalg.svd(dW_true, compute_uv=False)[:6].round(3)}")
print(f"r=16 LoRA delta s.v.:    {sv_lora[:6].round(3)}")
dW_full = np.linalg.lstsq(Xtr, Ytr - Xtr @ W0.T, rcond=None)[0].T   # "full fine-tune": every weight free
U, sv, Vh = np.linalg.svd(dW_full)
print(f"full-FT delta s.v.:      {sv[:6].round(3)}  ... s_10 = {sv[9]:.3f} (noise)")
print(f"full fine-tune test loss {mse(Xte, Yte, W0 + dW_full):.4f}")
for r in (2, 4, 8):
    Bx, Ax = U[:, :r] * np.sqrt(sv[:r]), np.sqrt(sv[:r])[:, None] * Vh[:r]
    print(f"  SVD-extracted LoRA r={r}: test loss {mse(Xte, Yte, W0 + Bx @ Ax):.4f}, "
          f"||dW_full - BA||_F / ||dW_full||_F = {np.linalg.norm(dW_full - Bx @ Ax) / np.linalg.norm(dW_full):.3f}")
assert sv_lora[4] < 0.05 * sv_lora[3]

print("\n== LLM-scale parameter and optimizer-state arithmetic (one 4096 x 4096 projection) ==")
for r in (8, 16, 64):
    p = r * (4096 + 4096)
    print(f"r={r:>2}: {p:>9,} trainable ({p / 4096 ** 2:.2%}); fp32 weight + Adam m,v {p * 12 / 2 ** 20:6.2f} MiB "
          f"vs {4096 ** 2 * 12 / 2 ** 20:.0f} MiB for full fine-tuning")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
noise floor 0.0050; frozen base (no adapter) test loss 0.0363

== 1. B = 0 at init ==
max |adapted - base| output at step 0 = 0.0e+00

== 2. rank sweep: 4096 training rows vs 192 training rows ==
  r  params  test (4096 rows)  train (192)  test (192)
  1     512            0.0192       0.0190      0.0290
  2    1024            0.0113       0.0111      0.0207
  4    2048            0.0050       0.0048      0.0167
  8    4096            0.0050       0.0045      0.0152
 16    8192            0.0050       0.0040      0.0171
 64   32768            0.0052       0.0017      0.0222

== 3. early training: alpha/r vs alpha/sqrt(r), same learning rate ==
        scale   r   loss@5  loss@20  loss@60
      alpha/r   4   0.0350   0.0203   0.0069
      alpha/r  16   0.0345   0.0156   0.0051
      alpha/r  64   0.0342   0.0141   0.0051
alpha/sqrt(r)   4   0.0344   0.0177   0.0071
alpha/sqrt(r)  16   0.0306   0.0087   0.0050
alpha/sqrt(r)  64   0.0228   0.0064   0.0049
loss@20 max/min across ranks: alpha/r 1.43x, alpha/sqrt(r) 2.74x

== 4. merge ==
float64: max |merged - unmerged| = 8.88e-15  (merge is free and exact)
quantized base: |unmerged Q(W0) + BA - target| = 7.99e-15; |Q(Q(W0) + BA) - target| = 4.71e-02

== 5. spectrum of the learned delta and LoRA extraction from a full fine-tune ==
true dW singular values: [3.  2.  1.5 1.  0.  0. ]
r=16 LoRA delta s.v.:    [3.001 1.998 1.501 1.002 0.04  0.038]
full-FT delta s.v.:      [3.001 1.999 1.501 1.002 0.051 0.051]  ... s_10 = 0.049 (noise)
full fine-tune test loss 0.0053
  SVD-extracted LoRA r=2: test loss 0.0113, ||dW_full - BA||_F / ||dW_full||_F = 0.456
  SVD-extracted LoRA r=4: test loss 0.0050, ||dW_full - BA||_F / ||dW_full||_F = 0.100
  SVD-extracted LoRA r=8: test loss 0.0050, ||dW_full - BA||_F / ||dW_full||_F = 0.097

== LLM-scale parameter and optimizer-state arithmetic (one 4096 x 4096 projection) ==
r= 8:    65,536 trainable (0.39%); fp32 weight + Adam m,v   0.75 MiB vs 192 MiB for full fine-tuning
r=16:   131,072 trainable (0.78%); fp32 weight + Adam m,v   1.50 MiB vs 192 MiB for full fine-tuning
r=64:   524,288 trainable (3.12%); fp32 weight + Adam m,v   6.00 MiB vs 192 MiB for full fine-tuning

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 2** is the bias/variance picture of rank (§1.8). With plenty of data, any r ≥ the intrinsic rank reaches the noise floor. With little data, the test loss is U-shaped in r.
- **Part 4** is the quantized-merge trap: an exact merge in float64, but a 4.7e-2 output error when you re-quantize after merging.
- **Part 5** reads the rank off the spectrum. The full fine-tune's ΔW has singular values 3.001, 1.999, 1.501, 1.002, then a noise floor at ~0.05. The SVD-extracted rank-4 LoRA *beats* the full fine-tune on test loss (0.0050 vs 0.0053), which is Eckart–Young denoising. That's also how "LoRA extraction" tools turn a full fine-tune into an adapter.

### 3.4 A production-shaped `LoRALinear` in PyTorch, plus multi-adapter batching

```python
"""lora_linear_torch.py - a production-shaped LoRALinear (PEFT semantics) and multi-adapter batched serving, on CPU.

  1. Wraps a frozen nn.Linear: A ~ kaiming_uniform(a=sqrt(5)), B = 0, scale alpha/r (or rsLoRA alpha/sqrt(r)).
  2. Only A and B get gradients; the base weight is bit-identical after training; the checkpoint is tiny.
  3. merge() removes the adapter's matmuls; unmerge() is NOT bit-exact, so merge into a copy, or reload the base.
  4. bf16 merge error vs fp32; merged vs unmerged latency.
  5. Multi-LoRA serving: every request in a batch uses its own adapter (the S-LoRA / Punica idea).
"""
import math
import time

import torch
import torch.nn as nn

torch.manual_seed(0)
torch.set_num_threads(1)


class LoRALinear(nn.Module):
    def __init__(self, base: nn.Linear, r=16, alpha=32.0, dropout=0.0, rslora=False):
        super().__init__()
        self.base = base
        for p in self.base.parameters():
            p.requires_grad_(False)
        self.r = r
        self.scaling = alpha / math.sqrt(r) if rslora else alpha / r
        self.lora_A = nn.Parameter(torch.empty(r, base.in_features))
        self.lora_B = nn.Parameter(torch.zeros(base.out_features, r))
        nn.init.kaiming_uniform_(self.lora_A, a=math.sqrt(5))          # same as PEFT's default init
        self.dropout = nn.Dropout(dropout) if dropout > 0 else nn.Identity()
        self.merged = False

    def forward(self, x):
        y = self.base(x)
        if self.merged:
            return y
        return y + (self.dropout(x) @ self.lora_A.T @ self.lora_B.T) * self.scaling

    @torch.no_grad()
    def merge(self):
        if not self.merged:
            self.base.weight += self.scaling * (self.lora_B @ self.lora_A)
            self.merged = True

    @torch.no_grad()
    def unmerge(self):
        if self.merged:
            self.base.weight -= self.scaling * (self.lora_B @ self.lora_A)
            self.merged = False


D_IN, D_OUT, R = 1024, 1024, 16
base = nn.Linear(D_IN, D_OUT)
w_before = base.weight.detach().clone()
layer = LoRALinear(base, r=R, alpha=32.0)
x = torch.randn(64, D_IN)

print("== 1. init is a no-op ==")
print(f"max |lora(x) - base(x)| at init = {(layer(x) - base(x)).abs().max().item():.1e}")
assert torch.equal(layer(x), base(x))

print("\n== 2. train only the adapter ==")
with torch.no_grad():                                               # teacher = base + a rank-4 change
    dW = (torch.randn(D_OUT, 4) @ torch.randn(4, D_IN)) * 0.0005
    teacher = lambda z: base(z) + z @ dW.T
trainable = [p for p in layer.parameters() if p.requires_grad]
opt = torch.optim.AdamW(trainable, lr=2e-3, weight_decay=0.0)
for step in range(300):
    xb = torch.randn(128, D_IN)
    loss = ((layer(xb) - teacher(xb)) ** 2).mean()
    opt.zero_grad(set_to_none=True)
    loss.backward()
    opt.step()
    if step == 0:
        first = loss.item()
    if step in (0, 299):
        print(f"step {step:>3}: mse {loss.item():.3e}")
n_train = sum(p.numel() for p in trainable)
n_total = n_train + sum(p.numel() for p in base.parameters())
print(f"trainable {n_train:,} of {n_total:,} params ({n_train / n_total:.2%}); base.weight.grad is {base.weight.grad}")
print(f"base weight bit-identical after training: {torch.equal(base.weight, w_before)}")
adapter_bytes = sum(v.numel() * v.element_size() for k, v in layer.state_dict().items() if "lora_" in k)
base_bytes = sum(v.numel() * v.element_size() for k, v in base.state_dict().items())
print(f"adapter checkpoint {adapter_bytes / 1024:.0f} KiB vs base layer {base_bytes / 2 ** 20:.1f} MiB")
assert base.weight.grad is None and torch.equal(base.weight, w_before) and loss.item() < 0.01 * first

print("\n== 3. merge / unmerge ==")
with torch.no_grad():
    y_unmerged = layer(x)
    layer.merge()
    y_merged = layer(x)
    layer.unmerge()
print(f"max |merged - unmerged| output = {(y_merged - y_unmerged).abs().max().item():.2e}")
print(f"after unmerge, max |W - W_original| = {(base.weight - w_before).abs().max().item():.2e} "
      f"(bit-identical: {torch.equal(base.weight, w_before)})")
assert (y_merged - y_unmerged).abs().max() < 1e-4

print("\n== 4. bf16 merge error and latency (one measured run) ==")
with torch.no_grad():
    ref_W = w_before + layer.scaling * layer.lora_B @ layer.lora_A
    delta = layer.scaling * layer.lora_B @ layer.lora_A
    bf_merged = (w_before.bfloat16() + delta.bfloat16()).float()
    print(f"|delta| median {delta.abs().median().item():.2e} vs |W| median {w_before.abs().median().item():.2e}")
    print(f"bf16 merged weight: max |W_bf16 - W_fp32| = {(bf_merged - ref_W).abs().max().item():.2e}, "
          f"fraction of the delta lost to rounding = {((bf_merged - w_before.bfloat16().float()) - delta).norm().item() / delta.norm().item():.3f}")
xb = torch.randn(32, D_IN)
for name, merged in (("unmerged (3 matmuls)", False), ("merged (1 matmul)", True)):
    if merged:
        layer.merge()
    with torch.no_grad():
        for _ in range(5):
            layer(xb)
        t0 = time.perf_counter()
        for _ in range(200):
            layer(xb)
    print(f"{name:22s} {(time.perf_counter() - t0) / 200 * 1e6:8.1f} us per batch of 32")
layer.unmerge()

print("\n== 5. multi-LoRA batch: 8 tenants, one batch ==")
NA = 8
A_stack = torch.randn(NA, R, D_IN) * 0.02
B_stack = torch.randn(NA, D_OUT, R) * 0.02
ids = torch.randint(0, NA, (64,))
xs = torch.randn(64, D_IN)
with torch.no_grad():
    loop = torch.stack([base(xs[i]) + layer.scaling * (B_stack[ids[i]] @ (A_stack[ids[i]] @ xs[i])) for i in range(64)])
    gathered = base(xs) + layer.scaling * torch.einsum("br,bor->bo", torch.einsum("bi,bri->br", xs, A_stack[ids]), B_stack[ids])
    grouped = base(xs)
    for a in ids.unique():                                          # group rows by adapter: what SGMV kernels do
        rows = ids == a
        grouped[rows] += layer.scaling * (xs[rows] @ A_stack[a].T) @ B_stack[a].T
print(f"max |gathered - per-row loop| = {(gathered - loop).abs().max().item():.2e}; "
      f"max |grouped - loop| = {(grouped - loop).abs().max().item():.2e}")
print(f"gathered A[ids] materializes {A_stack[ids].numel() * 4 / 2 ** 20:.1f} MiB for 64 rows; "
      f"grouping by adapter touches each adapter once ({NA} x {A_stack[0].numel() * 4 / 1024:.0f} KiB)")
assert (gathered - loop).abs().max() < 1e-4 and (grouped - loop).abs().max() < 1e-4
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the latency lines, which are one measured run):

```text
== 1. init is a no-op ==
max |lora(x) - base(x)| at init = 0.0e+00

== 2. train only the adapter ==
step   0: mse 1.003e-03
step 299: mse 3.624e-09
trainable 32,768 of 1,082,368 params (3.03%); base.weight.grad is None
base weight bit-identical after training: True
adapter checkpoint 128 KiB vs base layer 4.0 MiB

== 3. merge / unmerge ==
max |merged - unmerged| output = 2.09e-06
after unmerge, max |W - W_original| = 1.86e-09 (bit-identical: False)

== 4. bf16 merge error and latency (one measured run) ==
|delta| median 5.72e-04 vs |W| median 1.56e-02
bf16 merged weight: max |W_bf16 - W_fp32| = 1.83e-04, fraction of the delta lost to rounding = 0.028
unmerged (3 matmuls)     1273.8 us per batch of 32
merged (1 matmul)        1021.7 us per batch of 32

== 5. multi-LoRA batch: 8 tenants, one batch ==
max |gathered - per-row loop| = 1.91e-06; max |grouped - loop| = 1.91e-06
gathered A[ids] materializes 4.0 MiB for 64 rows; grouping by adapter touches each adapter once (8 x 64 KiB)

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 2** proves the freezing contract. `base.weight.grad is None`, the base weight is bit-identical after 300 AdamW steps, and the adapter checkpoint is 128 KiB vs 4.0 MiB for the base layer.
- **Part 3:** merge is exact to fp32 rounding (2.1e-6 on outputs), but unmerge is not bit-exact (1.86e-9 drift). Treat merge as one-way unless you keep the original weights.
- **Part 4** quantifies bf16 merge loss for a realistic delta (2.8% of ‖ΔW‖). The latency gap between unmerged (3 matmuls) and merged (1 matmul) is small on CPU at r = 16. It grows on GPU with many small layers and kernel-launch overhead, which is what fused multi-LoRA kernels address.
- **Part 5** is the multi-tenant serving primitive. Gathered and grouped formulations both match the per-row loop, and grouping avoids materializing per-row adapter copies.

### 3.5 Matryoshka on a linear encoder: nested losses, funnel retrieval, renormalization

```python
"""matryoshka_linear_toy.py - Matryoshka Representation Learning (MRL) on a linear encoder, with hand-written gradients.

Same encoder, same data, two losses:
  standard: CE( softmax(z[:, :64] @ H) )
  MRL:      sum over m in {4, 8, 16, 32, 64} of CE( softmax(z[:, :m] @ H_m) )
  1. Truncating a standard embedding to its first m dims destroys it; an MRL prefix stays useful.
  2. PCA fitted on the standard embedding (for THIS corpus) is a strong post-hoc baseline, even with
     high-variance nuisance directions in the input; MRL gets there with no fitted projection to version.
  3. Funnel retrieval: shortlist with 16 dims, rerank with 64 -> full-dim quality at a fraction of the FLOPs.
  4. Truncate THEN renormalize: dot product on raw prefixes is not cosine.
"""
import numpy as np

rng = np.random.default_rng(8)
D, C, E, NTR, NTE = 128, 64, 64, 6000, 3000
PREFIXES = (4, 8, 16, 32, 64)


def l2n(x):
    return x / np.linalg.norm(x, axis=-1, keepdims=True)


basis = np.linalg.qr(rng.standard_normal((D, 56)))[0]
sig, nuis = basis[:, :40], basis[:, 40:]                            # class signal in 40 dims, nuisance in 16 others
means = (rng.standard_normal((C, 40)) * np.geomspace(2.0, 0.5, 40)) @ sig.T


def data(n, seed):
    r = np.random.default_rng(seed)
    y = r.integers(0, C, n)
    return means[y] + 1.0 * r.standard_normal((n, D)) + 4.0 * r.standard_normal((n, 16)) @ nuis.T, y


Xtr, ytr = data(NTR, 1)
Xte, yte = data(NTE, 2)
Ytr = np.eye(C)[ytr]


def softmax(z):
    z = z - z.max(1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(1, keepdims=True)


def train(prefixes, steps=300, lr=0.01, seed=0):
    r = np.random.default_rng(seed)
    params = {"W": r.standard_normal((D, E)) / np.sqrt(D)}
    for m in prefixes:
        params[m] = np.zeros((m, C))
    m1 = {k: np.zeros_like(v) for k, v in params.items()}
    m2 = {k: np.zeros_like(v) for k, v in params.items()}
    for t in range(1, steps + 1):
        Z = Xtr @ params["W"]
        grads = {k: None for k in params}
        dZ = np.zeros_like(Z)
        loss = 0.0
        for m in prefixes:
            P = softmax(Z[:, :m] @ params[m])
            loss += -np.mean(np.log(P[np.arange(NTR), ytr] + 1e-12))
            G = (P - Ytr) / NTR
            grads[m] = Z[:, :m].T @ G
            dZ[:, :m] += G @ params[m].T
        grads["W"] = Xtr.T @ dZ
        for k in params:                                            # Adam
            m1[k] = 0.9 * m1[k] + 0.1 * grads[k]
            m2[k] = 0.999 * m2[k] + 0.001 * grads[k] ** 2
            params[k] -= lr * (m1[k] / (1 - 0.9 ** t)) / (np.sqrt(m2[k] / (1 - 0.999 ** t)) + 1e-8)
    return params, loss


def centroid_acc(emb_tr, emb_te):
    cents = l2n(np.stack([emb_tr[ytr == c].mean(0) for c in range(C)]))
    return np.mean((l2n(emb_te) @ cents.T).argmax(1) == yte)


std, std_loss = train((64,))
mrl, mrl_loss = train(PREFIXES)
Ztr_s, Zte_s = Xtr @ std["W"], Xte @ std["W"]
Ztr_m, Zte_m = Xtr @ mrl["W"], Xte @ mrl["W"]
print(f"final training loss: standard {std_loss:.3f} (1 head); MRL {mrl_loss:.3f} (sum of {len(PREFIXES)} heads)")

print("\n== 1-2. nearest-class-centroid accuracy (cosine) using only m dimensions ==")
mean_s = Ztr_s.mean(0)
_, _, Vt = np.linalg.svd(Ztr_s - mean_s, full_matrices=False)
print(f"{'m':>3} {'standard: first m':>18} {'standard: PCA to m':>19} {'MRL: first m':>13}")
acc = {}
for m in PREFIXES:
    a_tr = centroid_acc(Ztr_s[:, :m], Zte_s[:, :m])
    a_pca = centroid_acc((Ztr_s - mean_s) @ Vt[:m].T, (Zte_s - mean_s) @ Vt[:m].T)
    a_mrl = centroid_acc(Ztr_m[:, :m], Zte_m[:, :m])
    acc[m] = (a_tr, a_pca, a_mrl)
    print(f"{m:>3} {a_tr:>18.3f} {a_pca:>19.3f} {a_mrl:>13.3f}")
assert acc[8][2] > acc[8][0] + 0.1 and acc[64][2] > acc[64][0] - 0.02

print("\n== 3. funnel retrieval with the MRL embedding (corpus = 6000 train vectors) ==")
docs, qs = l2n(Ztr_m), l2n(Zte_m)


def prec10(found):
    return np.mean(ytr[found] == yte[:, None])


full = np.argsort(-(qs @ docs.T), axis=1)[:, :10]
d16, q16 = l2n(Ztr_m[:, :16]), l2n(Zte_m[:, :16])
short = np.argpartition(-(q16 @ d16.T), 100, axis=1)[:, :100]
rerank = np.array([s[np.argsort(-(docs[s] @ q))[:10]] for s, q in zip(short, qs)])
only16 = np.argsort(-(q16 @ d16.T), axis=1)[:, :10]
flops_full, flops_funnel = NTR * 64, NTR * 16 + 100 * 64
overlap = np.mean([len(set(a) & set(b)) / 10 for a, b in zip(rerank, full)])
print(f"precision@10 (same class): 64-d brute force {prec10(full):.3f} | 16-d only {prec10(only16):.3f} | "
      f"16-d shortlist(100) -> 64-d rerank {prec10(rerank):.3f}")
print(f"funnel top-10 overlap with 64-d brute force {overlap:.3f}; multiply-adds per query {flops_funnel:,} vs {flops_full:,} "
      f"({flops_full / flops_funnel:.1f}x fewer)")
assert prec10(rerank) >= prec10(full) - 0.01

print("\n== 4. truncate, then renormalize ==")
pref = docs[:, :16]                                                 # prefix of unit vectors: norms now vary
qn = qs[:, :16]
print(f"norms of 16-d prefixes of unit 64-d vectors: min {np.linalg.norm(pref, axis=1).min():.3f}, "
      f"max {np.linalg.norm(pref, axis=1).max():.3f}")
top_dot = np.argsort(-(qn @ pref.T), axis=1)[:, :10]
top_cos = np.argsort(-(l2n(qn) @ l2n(pref).T), axis=1)[:, :10]
differ = np.mean([set(a) != set(b) for a, b in zip(top_dot, top_cos)])
print(f"queries whose top-10 differs between raw-prefix dot and renormalized cosine: {differ:.1%}")
assert differ > 0.05
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
final training loss: standard 0.000 (1 head); MRL 1.413 (sum of 5 heads)

== 1-2. nearest-class-centroid accuracy (cosine) using only m dimensions ==
  m  standard: first m  standard: PCA to m  MRL: first m
  4              0.196               0.477         0.503
  8              0.528               0.857         0.851
 16              0.812               0.969         0.940
 32              0.945               0.986         0.964
 64              0.988               0.988         0.977

== 3. funnel retrieval with the MRL embedding (corpus = 6000 train vectors) ==
precision@10 (same class): 64-d brute force 0.945 | 16-d only 0.898 | 16-d shortlist(100) -> 64-d rerank 0.944
funnel top-10 overlap with 64-d brute force 0.998; multiply-adds per query 102,400 vs 384,000 (3.8x fewer)

== 4. truncate, then renormalize ==
norms of 16-d prefixes of unit 64-d vectors: min 0.475, max 0.864
queries whose top-10 differs between raw-prefix dot and renormalized cosine: 100.0%

ALL ASSERTIONS PASSED
```

How to read it:

- **The gradient code is the whole method.** `dZ[:, :m] += G @ H_m.T` for each prefix m: smaller prefixes receive gradient from more heads, so the first coordinates are pushed to carry the most label information.
- **Training loss** isn't comparable across the two models: MRL's is a sum of 5 heads' losses. Compare them on the evaluation table.
- **Part 4** is the one-liner bug: 100% of top-10 lists differ when you rank raw prefixes by dot product instead of renormalized cosine.

---

## 4. The Andrew Ng Lens: Adaptation as Bias–Variance, Driven by Error Analysis

### 4.1 The adaptation ladder

Andrew Ng's courses and letters keep returning to the same order of operations for adapting a model to a task: start with prompting, add retrieval when the model lacks knowledge, and fine-tune when you need behaviour that prompting can't reliably produce, or when you need to cut cost or latency. The order follows from cost of iteration: prompting changes ship in minutes, RAG changes in hours, fine-tunes in days. Error analysis tells you which rung you're on:

| Error-analysis finding (tag counts from the spreadsheet) | Diagnosis | Rung |
|---|---|---|
| Correct behaviour, but facts missing, stale or proprietary | Knowledge gap | **RAG** (Folder 04), not fine-tuning |
| Right facts in context, wrong format, tone or policy adherence, inconsistent structure | Behaviour gap | **Fine-tune** (LoRA), or structured outputs first |
| Fails even with perfect context and clear instructions, on multi-step reasoning | Capability gap | Bigger model, agentic decomposition, or tools |
| Fine on most traffic, fails on a narrow slice | Data coverage | More or better examples for that slice (data-centric), regardless of rung |
| Works, but too slow or expensive at volume | Cost/latency | Distil into a small model + LoRA, or a cascade (Folder 07) |

### 4.2 LoRA rank through the bias/variance lens

Ng's diagnostic is to compare training error against the achievable error, then compare held-out error against training error. Applied to rank:

- **High training loss at small r:** avoidable bias. The adapter can't represent the change. Raise r, apply LoRA to more layers (MLP layers first, per LoRA Without Regret), or check the learning rate (LoRA wants ~10× the full-fine-tuning LR).
- **Low training loss, high held-out loss at large r:** variance. More data, fewer trainable parameters, or earlier stopping. The 192-row experiment in §3.3 shows the U-curve directly.
- **Both fine, but production is worse:** data mismatch. Your fine-tuning data doesn't look like traffic. Ng's dev/test-from-the-same-distribution rule applies verbatim.

### 4.3 Data-centric before rank-centric

Before sweeping rank, audit the labels. Inconsistent labels (two annotators, two conventions) put a floor under the loss that no rank fixes, and a bigger adapter just memorizes the inconsistency. That's Ng's data-centric AI argument in one sentence: **improving label consistency on a few hundred examples often beats any model-side change**. The cheapest check is to have two people label the same 100 examples and measure agreement before training anything.

### 4.4 Eval-driven development for adapters

1. **The task eval**, frozen before training: the target slice, with the metric you'll ship on.
2. **The "nothing else broke" eval:** general capabilities you rely on. LoRA forgets less than full fine-tuning (Biderman et al.), but "less" isn't "none".
3. **The merge eval:** run both evals again *after* merging and after any re-quantization (§1.8: bf16 merge loses 2.8% of the delta; re-quantizing after a merge changes the base).
4. **Per-adapter regression tests in multi-tenant serving:** a tenant's adapter must pass its own eval against the exact base-model build in production. A base upgrade invalidates every adapter, just as a model upgrade invalidates every similarity threshold.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Shortened embeddings rank worse than expected | Prefix norms < 1; dot-product index | Truncated without renormalizing (100% of top-10 lists changed in §3.5) | Renormalize after every truncation; prefer the API's `dimensions` / `output_dimensionality` | Contract field `normalized`; ingest assertion |
| F2 | "We truncated to 256 and recall fell off a cliff" | The model isn't Matryoshka-trained | Truncating a standard embedding is a random projection (§1.11) | Use an MRL model, or fit PCA | Check the model card for MRL before planning dims |
| F3 | PCA-compressed index degrades over weeks | Rising reconstruction error on new vectors | Basis fitted on an old corpus; new content outside the subspace (0.243 vs 0.658 recall) | Refit on recent data, re-project, version the basis | Reconstruction-error drift alarm (Folder 07) |
| F4 | Two PCA-compressed indexes "don't match" | Component sign flips between fits | SVD sign ambiguity (§1.3) | Never compare across fits; align with Procrustes or recompute | Store the projection matrix with the index version |
| F5 | Whitened embeddings retrieve garbage | Whitening applied past the intrinsic dimension | Dividing by tiny σ amplifies noise (precision 0.210 at k = 64) | Whiten only the top components; evaluate on task labels | A whitening dimension chosen from the spectrum's knee |
| F6 | LoRA run doesn't learn | Loss flat; A gradients zero | Both A and B zero-initialized, or LR tuned for full fine-tuning (LoRA wants ~10×) | B = 0, A random (PEFT default); LR sweep | Use PEFT defaults; a sanity check that loss falls within ~50 steps |
| F7 | A new rank needs a new LR | Higher r with α/√r trains faster or unstably | Scale convention changes the effective step size (2.74× spread) | Keep α/r for rank sweeps; re-tune LR when switching conventions | Record (r, α, convention, LR) together in experiment metadata |
| F8 | Quality drop after merging a QLoRA adapter | Merged + re-quantized model differs from the unmerged one | Re-quantization changes the base the adapter was trained on (4.7e-2 vs 8e-15) | Serve unmerged, or merge into a high-precision base and re-evaluate | A merge eval in the release checklist |
| F9 | Slight regressions after merge in bf16 | Small deltas partly rounded away | bf16 mantissa (2.8% of ‖ΔW‖ lost in §3.4) | Merge in fp32, then cast; or serve unmerged | Compare merged vs unmerged on the eval |
| F10 | Adapter swaps on a merged model accumulate drift | Weights differ from the original after merge/unmerge cycles | Unmerge is not bit-exact (1.86e-9 per cycle in fp32) | Reload the base, or keep a pristine copy | Never unmerge in place in long-running servers |
| F11 | LoRA underperforms full fine-tuning on a big dataset | Gap grows with dataset size | Capacity-constrained regime, or attention-only targeting | Apply to all linear layers (MLP first), raise r, or full fine-tune | Check capacity: dataset tokens vs adapter params |
| F12 | Fine-tuned model "knows" stale facts or hallucinates new ones | The fine-tune was used to inject knowledge | Fine-tuning shapes behaviour. Facts belong in retrieval | Move the facts to RAG; fine-tune on format and behaviour | Error-analysis tag "knowledge gap" → RAG, never a fine-tune |
| F13 | Tenant adapter breaks after a base-model patch | Adapter trained on base v1, served on v1.1 | ΔW is defined relative to a specific W₀ | Retrain or re-validate every adapter on base upgrades | Pin the base build in adapter metadata; CI per adapter |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain LoRA to me from the matrix up. Why does it work at all?"</b></summary>

**Initial Prompt.** The interviewer wants the mechanism, not the acronym.

**L5 Answer.** "LoRA adds small trainable matrices to the model and freezes the rest, so it trains faster and uses less memory."

**Why L5 Fails in Production.** It doesn't explain *why* a rank-r update is enough, when it isn't, or the init and scaling details that make training work. So the engineer can't debug a LoRA run that doesn't learn, or decide between LoRA and full fine-tuning.

**L7 Principal Defense.** "Fine-tuning changes W₀ by ΔW. Empirically, ΔW has low intrinsic rank: Aghajanyan et al. recovered about 90% of full fine-tuning on MRPC by optimizing a few hundred parameters. So parameterize ΔW = (α/r)·BA with B ∈ ℝ^{d×r} and A ∈ ℝ^{r×k}, and freeze W₀. B starts at zero so the model starts as the base. A starts random, because with B = 0 the gradient of A is zero, and if A were also zero nothing would ever move. Trainable parameters drop from dk to r(d+k): 0.78% at d = k = 4096, r = 16. The α/r scale keeps the optimal learning rate roughly rank-independent. Eckart–Young is the guarantee underneath: if the true ΔW's spectrum falls off after r, a rank-r factorization captures it optimally. In our toy, the extracted rank-4 adapter even generalizes better than the full fine-tune (0.0050 vs 0.0053), because truncation discards noise directions."

**Bar-Raiser Follow-ups.**
- *"When doesn't it work?"* When the task needs capacity beyond r (large continued pre-training, per Biderman et al.), with attention-only targeting, or at very large batch sizes (LoRA Without Regret).
- *"Does LoRA cut activation memory?"* No. Activations through the frozen network are still stored for backward. LoRA cuts optimizer state and weight gradients. For long sequences you also need gradient checkpointing.
- *"Compute per step vs full fine-tuning?"* About two-thirds. There are no weight gradients for W₀ (2N² + 6NR vs 3N² per matrix).

</details>

<details><summary><b>Q2 · "Our LoRA fine-tune isn't learning. Loss is flat. Debug it."</b></summary>

**Initial Prompt.** A team ported LoRA into their own training stack.

**L5 Answer.** "Increase the rank and train longer."

**Why L5 Fails in Production.** A flat loss from step 0 is almost never a rank problem. Raising r doesn't help if the gradients are zero or the step size is 10× too small, and it burns GPU time.

**L7 Principal Defense.** "Check in this order. (1) **Init:** if A and B are both zero, ∂L/∂A = s·BᵀGxᵀ = 0 and ∂L/∂B = s·G(Ax)ᵀ = 0, so nothing moves. PEFT uses Kaiming-uniform A and zero B. (2) **Learning rate:** LoRA's optimum is about 10× the full-fine-tuning LR (LoRA Without Regret's fitted 9.8×), so a full-FT LR looks flat. (3) **Freezing scope:** confirm `requires_grad` is set on A and B and that the optimizer received them. Our PyTorch test asserts base grads are `None` and the adapter's loss falls. (4) **Scale:** α/r with a tiny α makes ΔW negligible. (5) **Targets:** attention-only adapters learn less than MLP adapters at matched parameters. Only then look at rank."

**Bar-Raiser Follow-ups.**
- *"How do you tell an LR problem from a capacity problem?"* Capacity shows as a plateau *above* the full-FT loss after a normal descent. An LR or init problem shows as no descent at all.
- *"And if the loss goes NaN instead?"* LR too high for the scale convention (α/√r at high rank), or mixed precision without loss scaling (Folder 05).

</details>

<details><summary><b>Q3 · "Should we merge the adapter for serving?"</b></summary>

**Initial Prompt.** One adapter for one product, served at high QPS.

**L5 Answer.** "Yes, merging removes the extra latency."

**Why L5 Fails in Production.** It's right for the fp16/fp32 single-tenant case and wrong for three common ones: quantized bases, multi-tenant serving, and adapter hot-swapping.

**L7 Principal Defense.** "For a single adapter on a full-precision base: merge. W′ = W₀ + (α/r)BA is exact (8.9e-15 in float64) and removes two matmuls per layer. But: (a) **quantized base**, where merging and re-quantizing changes the base the adapter was trained against. We measured a 4.7e-2 output error vs ~1e-14 unmerged, so serve unmerged, or merge in high precision and re-evaluate. (b) **bf16 merge**, where small deltas partially round away (2.8% of ‖ΔW‖), so merge in fp32 and run the merge eval. (c) **Multi-tenant**, where you keep adapters unmerged and batch by adapter (S-LoRA / Punica-style grouping). (d) **Hot-swap**, where unmerge isn't bit-exact (1.86e-9 drift per cycle), so reload the base instead of unmerging in place."

**Bar-Raiser Follow-ups.**
- *"DoRA adapters?"* Merge them for inference. PEFT warns DoRA's overhead is larger than LoRA's, and it's incompatible with multi-adapter batching.
- *"How big is the unmerged overhead?"* 4·r·(d_in + d_out) extra FLOPs per token per layer, small next to 2·d_in·d_out at r = 16. The real cost on GPU is kernel launches, which fused multi-LoRA kernels remove.

</details>

<details><summary><b>Q4 · "How do we serve 200 customer-specific fine-tunes without 200 GPUs?"</b></summary>

**Initial Prompt.** An enterprise SaaS wants a per-customer model for tone and format.

**L5 Answer.** "Fine-tune a model per customer and autoscale the deployments."

**Why L5 Fails in Production.** 200 full copies of an 8B model is 200 × 16 GB of weights, mostly idle, with cold starts measured in minutes. The economics don't close.

**L7 Principal Defense.** "One base model and 200 LoRA adapters. At r = 16 on all seven linear maps of a Llama-3-8B-shaped model, an adapter is 41.9M parameters, ~84 MB in bf16. 200 adapters are ~17 GB next to one ~16 GB base. Requests carry an adapter id. The server keeps hot adapters on the GPU and pages cold ones from host memory (S-LoRA's design), and batches mixed-adapter requests with grouped kernels (Punica's SGMV idea; our grouped formulation matches the per-row loop to 1.9e-6). Each adapter has its own eval, pinned to the base build. A base upgrade triggers retraining or re-validation of every adapter."

**Bar-Raiser Follow-ups.**
- *"Where does it break?"* Very skewed traffic (one tenant dominates a batch, which is fine), adapters of very different ranks (padding waste), and variants like DoRA that don't batch.
- *"Isolation?"* Adapters are data. Validate the base build pin and the tenant id on every load, and never let one tenant's id select another's adapter.

</details>

<details><summary><b>Q5 · "We want 256-dim embeddings instead of 3072. Can we just slice the vector?"</b></summary>

**Initial Prompt.** Storage costs push the team toward smaller vectors.

**L5 Answer.** "Yes, slice the first 256 values."

**Why L5 Fails in Production.** It works only if the model is Matryoshka-trained, *and* only after renormalization. Without MRL, slicing is a random projection. Without renormalization, dot-product ranking changes for essentially every query (100% in our test).

**L7 Principal Defense.** "First, is the model MRL-trained? OpenAI `text-embedding-3` and Gemini embeddings are, and both expose an API parameter (`dimensions`, `output_dimensionality`) that's the preferred path. Second, normalization: OpenAI tells you to renormalize after manual truncation. Gemini's `-001` returns normalized vectors only at 3072 dims, and `-2` renormalizes automatically. Third, re-derive every threshold at 256 dims. Fourth, measure on our eval: recall@k and the task metric at 256 vs 3072. If the model isn't MRL, fit PCA instead, centred plus one mean coordinate (0.995 recall at 64 dims in our structured test), and version the projection. A funnel (256-d shortlist, full-dim rerank) often gets full-dim quality at a fraction of the scan cost."

**Bar-Raiser Follow-ups.**
- *"Why does MRL work?"* The training loss sums over nested prefixes, so the gradient from small prefixes concentrates useful information in the leading coordinates.
- *"Is MRL free at full dimension?"* Not always. In our toy, full-dim accuracy was 0.977 vs 0.988 for the standard model. Check the model card's full-size numbers.

</details>

<details><summary><b>Q6 · "PCA or Matryoshka for compressing our embeddings?"</b></summary>

**Initial Prompt.** The model isn't MRL-trained, but a new MRL model is available.

**L5 Answer.** "PCA. It's the optimal linear compression."

**Why L5 Fails in Production.** "Optimal" is Eckart–Young for reconstruction error *on the fitted data*. Retrieval quality on drifting data is a different objective, and PCA carries operational baggage the L5 answer leaves out.

**L7 Principal Defense.** "PCA is optimal for squared reconstruction error on the data it was fitted on. In our toy it matched MRL at 8 dims (0.857 vs 0.851). But it has a lifecycle: you fit it, version it (sign flips across refits), monitor it (drift took recall from 0.658 to 0.243 at k = 32), and refit and re-project. It also changes the metric if you centre without the mean coordinate (0.956 vs 0.995 recall). MRL moves that work into training, so the prefix is just a parameter and there's no projection artifact. Choice: if we're staying on the current model, PCA with the k + 1 trick and a drift alarm. If we're migrating anyway, pick an MRL model and use API-side truncation. Either way, the decision comes from recall plus task metrics on our own eval at the target dims."

**Bar-Raiser Follow-ups.**
- *"Why not whitening, if it improves similarity scores?"* It helped topic precision inside the signal subspace (0.933 vs 0.865 at k = 32) and destroyed it past the knee (0.210 at k = 64). Use it only with k chosen from the spectrum.
- *"Fit PCA on what?"* A representative sample of the corpus *and* of queries. If queries come from a different distribution, the basis should see them.

</details>

<details><summary><b>Q7 · "Prove that truncated SVD is the best rank-k approximation, and tell me why I should care."</b></summary>

**Initial Prompt.** A whiteboard question at a research-adjacent team.

**L5 Answer.** "Because it keeps the largest singular values, which hold most of the information."

**Why L5 Fails in Production.** That's a restatement, not a proof, and it misses the production uses: denoising, choosing a rank, and benchmarking compressors.

**L7 Principal Defense.** "Spectral norm: any rank-k B has a null space of dimension ≥ n − k, which must intersect span(v₁ … v_{k+1}) (dimension k + 1). Take a unit w in both: ‖(A − B)w‖ = ‖Aw‖ ≥ σ_{k+1}, and A_k achieves σ_{k+1}. Frobenius follows from Weyl's inequality. Why I care: (1) it lets me read the rank a fine-tune needs off the singular spectrum of ΔW. Ours shows 3, 2, 1.5, 1, then a 0.05 floor, so rank 4. (2) Truncation denoises: the extracted rank-4 adapter beats the full fine-tune on test loss. (3) It's the yardstick: no random rank-20 subspace got within 14% of the optimal residual."

**Bar-Raiser Follow-ups.**
- *"Cost of computing it for a 4096 × 14336 matrix?"* Full SVD is O(mn·min(m, n)), seconds on a GPU. For the top 64, randomized SVD is O(mn·k): 81 ms vs 364 ms in our 2000×1000 test with 8e-8 relative error.

</details>

<details><summary><b>Q8 · "We're migrating embedding models. Can we avoid re-embedding 200M documents up front?"</b></summary>

**Initial Prompt.** Re-embedding takes two weeks of quota.

**L5 Answer.** "Train a small neural network to map old embeddings to new ones."

**Why L5 Fails in Production.** A learned mapper is a new model to train, validate and serve. Without a quality gate, it silently returns worse results during the most fragile phase of the migration.

**L7 Principal Defense.** "Default: dual-write, backfill, switch atomically after the eval gate (01.1 Q7). If we need a bridge in the meantime, start with the simplest one that has a closed-form answer: orthogonal Procrustes on a few thousand documents embedded by both models, R = UVᵀ from the SVD of XᵀY. In our test it took cross-model recall from 0.000 to 0.936 when the spaces differ by a rotation, but only to 0.859 under a nonlinear warp. Real model pairs are somewhere in between, so the bridge gets its own recall threshold on our eval, and we backfill the most-queried documents first, so the bridge matters for less traffic every day."

**Bar-Raiser Follow-ups.**
- *"Why orthogonal and not a general linear map?"* Orthogonality preserves norms and angles (unit vectors stay unit), needs fewer pairs, and can't collapse dimensions. A general least-squares map can overfit and distort the geometry.
- *"How many pairs?"* Several times d is a reasonable start (we used 2,000 for d = 128). Validate on held-out pairs, not on the fitting pairs.

</details>

<details><summary><b>Q9 · "LoRA or full fine-tuning for our domain adaptation?"</b></summary>

**Initial Prompt.** 50M tokens of domain text plus 20k instruction pairs, on an 8B model.

**L5 Answer.** "LoRA, it's cheaper."

**Why L5 Fails in Production.** Cost isn't the deciding variable. Capacity relative to the data is, along with how much forgetting you can tolerate and how you'll serve the result.

**L7 Principal Defense.** "Split the workload. The 20k instruction pairs are a behaviour task, well inside LoRA's capacity, where LoRA matches full fine-tuning when not capacity-constrained (LoRA Without Regret). So: LoRA on all linear layers, LR about 10× the full-FT LR, rank swept with α/r. The 50M tokens of domain text are continued pre-training, which Biderman et al. found favours full fine-tuning (higher-rank perturbations), at the cost of more forgetting. So first ask whether that text should be *retrieved* (RAG) rather than trained in. If it must be trained in, full fine-tune or high-rank LoRA, with a general-capability eval to measure forgetting. Serving drives the final call: a LoRA keeps the multi-tenant option open."

**Bar-Raiser Follow-ups.**
- *"For RL fine-tuning?"* LoRA, even at very low rank: rank-1 matched full fine-tuning for policy-gradient RL in LoRA Without Regret, because RL carries little information per episode.

</details>

<details><summary><b>Q10 · "Why does whitening sometimes improve sentence-similarity scores and sometimes ruin retrieval?"</b></summary>

**Initial Prompt.** A team read Su et al. (2021) and whitened their production embeddings.

**L5 Answer.** "Whitening removes anisotropy, so it should always help."

**Why L5 Fails in Production.** Whitening rescales *every* kept component to unit variance, including noise components. It also changes the metric, so the old thresholds and recall measurements no longer apply.

**L7 Principal Defense.** "Whitening equalizes the principal axes. Inside the intrinsic dimension that helps topic-level matching (precision 0.933 vs 0.865 at k = 32 in our test). Past the knee, components are noise with tiny σ, and dividing by σ inflates them to the same scale as the signal, so precision collapsed to 0.210 at k = 64. Recall against the original space's neighbours drops in both cases, because the metric changed. Production rule: whiten only within the top-k chosen from the spectrum's knee, re-derive thresholds, and evaluate on task labels, not recall against the old space."

**Bar-Raiser Follow-ups.**
- *"Is mean-centring the same thing?"* No. Centring removes the common direction and keeps relative variances. Whitening also rescales them. Centring is the gentler fix for anisotropy (01.1 §1.7).

</details>

<details><summary><b>Q11 · "What's the singular spectrum of a fine-tune's ΔW good for in practice?"</b></summary>

**Initial Prompt.** You have a full fine-tune checkpoint and the base model.

**L5 Answer.** "It's mostly of academic interest."

**Why L5 Fails in Production.** It's one of the cheapest diagnostics you have: one SVD per layer tells you the rank budget, which layers changed, and whether an adapter could replace the full checkpoint.

**L7 Principal Defense.** "Compute ΔW = W_ft − W₀ per layer and its singular values. (1) **Rank budget:** where the spectrum hits its noise floor. Ours: 3.001, 1.999, 1.501, 1.002, then ~0.05, so r = 4 suffices. (2) **Layer budget:** layers whose ΔW has tiny norm don't need adapters (EVA-style per-layer rank allocation follows the same idea). (3) **Extraction:** truncated SVD gives B = U_r√Σ_r and A = √Σ_r V_rᵀ, turning a 16 GB checkpoint into an adapter that may generalize better (0.0050 vs 0.0053 in our toy). (4) **Initialization:** PiSSA initializes from the top singular vectors of W₀ itself."

**Bar-Raiser Follow-ups.**
- *"Cost on an 8B model?"* 32 layers × 7 matrices, each with a randomized SVD for the top 64. Minutes on one GPU.

</details>

---

## 7. Invariants Checklist

- [ ] Every truncated embedding is renormalized. Truncation goes through the provider's API parameter when one exists.
- [ ] Truncation is applied only to Matryoshka-trained models. Others use fitted PCA, centred plus the mean coordinate.
- [ ] Every fitted projection (PCA basis, whitening, Procrustes R) is versioned with the index, and never compared across fits.
- [ ] PCA-compressed indexes have a reconstruction-error drift alarm and a refit procedure.
- [ ] Whitening uses only components inside the spectrum's knee, and is validated on task labels.
- [ ] LoRA init is B = 0 and A random (PEFT default). Rank sweeps keep α/r and re-tune the LR when the convention changes.
- [ ] Adapters target all linear layers (MLP first) unless an ablation on your eval says otherwise. The LR starts around 10× the full-FT LR.
- [ ] Every adapter release runs the task eval, a "nothing else broke" eval, and a post-merge eval (and post-re-quantization if relevant).
- [ ] QLoRA adapters are served unmerged, or merged in high precision and re-evaluated.
- [ ] Merged weights are never unmerged in place in long-running servers. Reload the base instead.
- [ ] Each adapter's metadata pins the exact base-model build. A base upgrade re-validates every adapter.
- [ ] Knowledge goes into retrieval, behaviour into fine-tunes (error-analysis tag → rung).

---

## 8. References

1. E. Hu et al., *LoRA: Low-Rank Adaptation of Large Language Models*, 2021. https://arxiv.org/abs/2106.09685
2. Hugging Face PEFT, *LoRA developer guide* (init options, rsLoRA, DoRA, PiSSA, LoftQ, EVA, OLoRA, `merge_and_unload`, `all-linear`). https://huggingface.co/docs/peft/developer_guides/lora
3. J. Schulman and Thinking Machines Lab, *LoRA Without Regret*, 2025-09-29. https://thinkingmachines.ai/blog/lora/
4. D. Biderman et al., *LoRA Learns Less and Forgets Less*, 2024. https://arxiv.org/abs/2405.09673
5. A. Aghajanyan, L. Zettlemoyer, S. Gupta, *Intrinsic Dimensionality Explains the Effectiveness of Language Model Fine-Tuning*, 2020. https://arxiv.org/abs/2012.13255
6. T. Dettmers et al., *QLoRA: Efficient Finetuning of Quantized LLMs*, 2023. https://arxiv.org/abs/2305.14314
7. D. Kalajdzievski, *A Rank Stabilization Scaling Factor for Fine-Tuning with LoRA* (rsLoRA), 2023. https://arxiv.org/abs/2312.03732
8. S.-Y. Liu et al., *DoRA: Weight-Decomposed Low-Rank Adaptation*, 2024. https://arxiv.org/abs/2402.09353
9. F. Meng, Z. Wang, M. Zhang, *PiSSA: Principal Singular Values and Singular Vectors Adaptation of Large Language Models*, 2024. https://arxiv.org/abs/2404.02948
10. Y. Sheng et al., *S-LoRA: Serving Thousands of Concurrent LoRA Adapters*, 2023. https://arxiv.org/abs/2311.03285
11. L. Chen et al., *Punica: Multi-Tenant LoRA Serving*, 2023. https://arxiv.org/abs/2310.18547
12. A. Kusupati et al., *Matryoshka Representation Learning*, NeurIPS 2022. https://arxiv.org/abs/2205.13147 (code: https://github.com/RAIVNLab/MRL)
13. OpenAI, *Embeddings guide* (`dimensions`, normalization after manual truncation). https://developers.openai.com/api/docs/guides/embeddings
14. Google, *Gemini API embeddings* (MRL, `output_dimensionality`, normalization per model). https://ai.google.dev/gemini-api/docs/embeddings
15. Supabase, *Matryoshka embeddings: faster OpenAI vector search using Adaptive Retrieval* (quotes OpenAI's 256-d vs ada-002 MTEB comparison). https://supabase.com/blog/matryoshka-embeddings
16. C. Eckart, G. Young, *The approximation of one matrix by another of lower rank*, Psychometrika 1(3), 1936. DOI 10.1007/BF02288367.
17. N. Halko, P.-G. Martinsson, J. Tropp, *Finding Structure with Randomness: Probabilistic Algorithms for Constructing Approximate Matrix Decompositions*, 2011. https://arxiv.org/abs/0909.4061
18. J. Su et al., *Whitening Sentence Representations for Better Semantics and Faster Retrieval*, 2021. https://arxiv.org/abs/2103.15316
19. P. Schönemann, *A generalized solution of the orthogonal Procrustes problem*, Psychometrika 31, 1966. DOI 10.1007/BF02289451.
20. scikit-learn, *PCA* and *randomized_svd* documentation. https://scikit-learn.org/stable/modules/generated/sklearn.decomposition.PCA.html
21. DeepSeek-AI, *DeepSeek-V2: A Strong, Economical, and Efficient Mixture-of-Experts Language Model* (multi-head latent attention), 2024. https://arxiv.org/abs/2405.04434
