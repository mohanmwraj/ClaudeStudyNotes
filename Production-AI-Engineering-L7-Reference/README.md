# Production AI Engineering — L7 Reference

A Principal/Staff-level (L6/L7) knowledge base on production AI systems, built from first principles:

- high-throughput LLM inference physics (roofline, KV cache, FlashAttention, PagedAttention/RadixAttention);
- distributed serving (continuous batching, chunked prefill, disaggregation, speculative decoding, quantization);
- vector-database internals (HNSW, DiskANN/Vamana, IVF-PQ);
- enterprise RAG;
- the Model Context Protocol;
- agentic microservices in Java 21+ (Spring AI, LangChain4j) and Python (vLLM, FastMCP, LangGraph).

It is meant to be both a permanent engineering reference and a FAANG L7 interview playbook.

## Layout and build status

| # | Folder | Status |
|---|--------|--------|
| 01 | [`01-LLM-Inference-Physics-and-KV-Cache/`](01-LLM-Inference-Physics-and-KV-Cache/) | ✅ Written 2026-10-27 |
| 02 | `02-High-Throughput-Serving-and-Distributed-Inference/` | ⏳ Next |
| 03 | `03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/` | ⏳ Planned |
| 04 | `04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/` | ⏳ Planned |
| 05 | `05-Model-Context-Protocol-MCP-Architecture/` | ⏳ Planned |
| 06 | `06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/` | ⏳ Planned |
| 07 | `07-Production-Code-Blueprints-Java-and-Python/` | ⏳ Planned |
| 08 | `08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/` | ⏳ Planned |

### Folder 01 contents

1. [The roofline model: prefill compute-bound vs decode memory-bound](01-LLM-Inference-Physics-and-KV-Cache/01-roofline-model-prefill-compute-bound-vs-decode-memory-bound.md)
   covers arithmetic intensity of GEMMs, the critical batch, $I_\infty(L)$, per-kernel decode/prefill pricing for
   Llama-3-70B on 8×H100, the MoE "experts touched" effect, a measured CPU roofline, and a Java SLO-aware admission
   controller.
2. [KV cache math (MHA, GQA, MLA) and FlashAttention SRAM tiling](01-LLM-Inference-Physics-and-KV-Cache/02-kv-cache-math-mha-gqa-mla-and-flashattention-sram-tiling.md)
   covers exact bytes for 8 model families, DeepSeek-V3 MLA (absorption, intensity ≈ 242 FLOP/B, TP replication), the
   online softmax proof, FA1→FA2→FA3, SRAM budgets, Flash-Decoding, and cascade merges.
3. [PagedAttention: block tables, copy-on-write, prefix caching, and RadixAttention](01-LLM-Inference-Physics-and-KV-Cache/03-pagedattention-block-tables-copy-on-write-and-radixattention.md)
   covers fragmentation, slot mapping, CoW, preemption storms (swap vs recompute), hash-chained prefix caching and its
   side channel, the radix tree with LPM scheduling, and a Java cache-aware fleet router.

## How every file is structured

1. **First-principles math and hardware/memory mechanics:** equations, byte layouts, kernel execution flows, state
   machines.
2. **Production code blueprints:** Python and Java 21. Each pairs a naive bottleneck with a hardened pattern and ships
   a self-test.
3. **Production failure modes and P99 debugging:** symptom → metric signature → root-cause physics → fix → prevention.
4. **FAANG L7 bar-raiser Q&A chains:** initial prompt → L5 textbook answer → why L5 fails at scale → L7 principal
   defense.
5. **Invariants checklist and references.**

## Notation used throughout

| Symbol | Meaning |
|--------|---------|
| $I = F/Q$ | Arithmetic intensity, FLOPs per byte moved to/from HBM |
| $I^{*} = P_{\text{peak}} / B_{\text{HBM}}$ | Ridge point (H100 BF16 dense: 295 FLOP/B) |
| $P$ | Parameters streamed per forward step (all layers + LM head; the embedding gather excluded) |
| $n_\ell, n_h, n_{kv}, d_h$ | Layers, query heads, KV heads, head dim (`num_hidden_layers`, `num_attention_heads`, `num_key_value_heads`, `head_dim`) |
| $g = n_h / n_{kv}$ | GQA group size. Also the decode attention intensity in BF16 |
| $\kappa$ | KV bytes per token across all layers (Llama-3-70B BF16: 327,680 B) |
| $d_c, d_h^R$ | MLA latent width (512) and decoupled RoPE key width (64) |
| $B$ (context-dependent) | Batch size (sequences or tokens per step), or block size in paging sections |
| TTFT / ITL (TPOT) | Time to first token / inter-token latency (time per output token) |
| MBU / MFU | Model bandwidth / FLOPs utilization: achieved ÷ peak |

## Version baseline and verification method

- **Python 3.10+**, verified on **CPython 3.14.5** with **NumPy 2.5.4**. Pure-stdlib listings run anywhere.
  NumPy-based listings need `pip install numpy`.
- **Java 21**, compiled with **JDK 25.0.4** using `javac --release 21 -Xlint:all -Werror`, so every listing is
  Java-21-compatible and warning-free. Code uses records, sealed interfaces, record patterns, pattern-matching
  `switch`, and virtual threads.
- **No GPU was available while writing.** GPU timings are **analytic**: a per-kernel roofline model with every input
  printed. The *physics* is reproduced on CPU, as a measured single-core roofline and NumPy reference kernels checked
  against naive implementations to ~1e-15. Labels:
  - **"Output (verified …)"**: deterministic, re-run during the folder gate.
  - **"one measured run"**: timing- or concurrency-dependent. The numbers vary while the asserted invariants hold.
- Claims that depend on a release (vLLM/SGLang flags, metric names, defaults, vendor deployment figures) are marked
  **⚠ verify**. Pin to the exact release you run before relying on them.
- **Folder gate:** every listing whose first line is `"""<name>.py - …` or `// <Name>.java - …` is extracted from the
  Markdown, re-run, and its output compared with the embedded output.

### Runnable listings in Folder 01

| Listing | Where | Proves |
|---------|-------|--------|
| `roofline.py` | 01 §3.2 | ridge points, GEMM intensity and critical batch, decode/prefill per-kernel times, KV capacity, SLO batch, TP=4 vs TP=8, MoE experts touched |
| `cpu_roofline_bench.py` | 01 §3.3 | measured memory and compute roofs on one CPU core; unbatched vs batched decode |
| `RooflinePlanner.java` | 01 §3.4 | Java port cross-checked against Python; static-limit vs roofline admission; virtual-thread race |
| `kv_cache_math.py` | 02 §4.1 | exact KV bytes (MHA/GQA/MQA/MLA/SWA), TP replication, int32 wrap to 0 |
| `flash_attention_ref.py` | 02 §4.2 | FA2 forward = naive (1e-15), Flash-Decoding and cascade merges, FP16 overflow, HBM/SRAM budgets |
| `KvCacheSizer.java` | 02 §4.3 | sealed layouts + record patterns, overflow trap vs `multiplyExact`, TP/DP-attention capacity |
| `paged_kv_manager.py` | 03 §5.1 | block pool, CoW, chained-hash prefix cache, salting, LRU revival, fragmentation, preemption storms |
| `paged_attention_ref.py` | 03 §5.2 | paged decode attention on scrambled blocks; CoW correctness; the naive in-place corruption |
| `radix_cache.py` | 03 §5.3 | radix split/insert/lock/evict; LPM vs FCFS hit rate |
| `PrefixAwareRouter.java` | 03 §5.4 | cache-aware vs round-robin routing, load guard, 20K virtual-thread routes |

`paged_attention_ref.py` imports `paged_kv_manager.py`; keep them in the same directory. Java listings declare
`package dev.l7.ai.inference;`. Run them with `javac --release 21 -d out X.java && java -ea -cp out dev.l7.ai.inference.X`.

## Where this KB refines the brief

The kit corrects or sharpens a claim when first principles demand it:

- **FlashAttention-3's** first author is Jay Shah, with Tri Dao as senior author (NeurIPS 2024). FlashAttention-1/2
  are Dao et al. / Dao.
- **The KV formula's leading "2"** (separate K and V) does not apply to **MLA**. It caches one shared 512-wide latent
  plus a 64-wide RoPE key (576 elements per token per layer), and both K and V derive from the latent. The formula's
  $d_{\text{head}}$ must be read from `head_dim` when present.
- **"Decode is strictly memory-bound"** holds per step at realistic context lengths. Per kernel, the picture is finer.
  Decode GEMMs become compute-bound past ~318 tokens per step on H100. GQA decode attention is memory-bound at *any*
  batch (intensity $= g$). MLA decode attention (≈ 242 FLOP/B) sits at the ridge. And $I_\infty(L) < I^*$ explains
  why batching stops helping.
- **The 60–80% fragmentation figure** agrees with the vLLM paper's measurement that only 20.4–38.2% of KV memory held
  token states in prior systems. File 03 reproduces the shape on a synthetic trace (14.5% / 66.1% / 97.5%).
