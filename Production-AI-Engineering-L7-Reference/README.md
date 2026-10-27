# Production AI Engineering — L7 Reference

A Principal/Staff-level (L6/L7) knowledge base on production AI systems, built from first principles:

- high-throughput LLM inference physics (roofline, KV cache, FlashAttention, PagedAttention/RadixAttention);
- distributed serving (continuous batching, chunked prefill, disaggregation, speculative decoding, quantization);
- vector-database internals (HNSW, DiskANN/Vamana, IVF-PQ);
- enterprise RAG;
- the Model Context Protocol;
- agentic microservices in Java 21+ (Spring AI, LangChain4j) and Python (vLLM clients, MCPServer, LangGraph), with
  durable execution;
- production blueprints: MCP servers, a resilient RAG orchestrator, streaming clients, hybrid SQL over Kafka CDC, and
  an LLM gateway;
- AI FinOps, 25 bar-raiser scenarios, and a verified reading list.

It is meant to be both a permanent engineering reference and a FAANG L7 interview playbook. All eight folders are
written (25 files, 58 runnable listings), and the whole KB passed a final gate on 2026-10-27 (see the verification
method below).

## Layout and build status

| # | Folder | Status |
|---|--------|--------|
| 01 | [`01-LLM-Inference-Physics-and-KV-Cache/`](01-LLM-Inference-Physics-and-KV-Cache/) | ✅ Written 2026-10-27 |
| 02 | [`02-High-Throughput-Serving-and-Distributed-Inference/`](02-High-Throughput-Serving-and-Distributed-Inference/) | ✅ Written 2026-10-27 |
| 03 | [`03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/`](03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/) | ✅ Written 2026-10-27 |
| 04 | [`04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/`](04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/) | ✅ Written 2026-10-27 |
| 05 | [`05-Model-Context-Protocol-MCP-Architecture/`](05-Model-Context-Protocol-MCP-Architecture/) | ✅ Written 2026-10-27 |
| 06 | [`06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/`](06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/) | ✅ Written 2026-10-27 |
| 07 | [`07-Production-Code-Blueprints-Java-and-Python/`](07-Production-Code-Blueprints-Java-and-Python/) | ✅ Written 2026-10-27 |
| 08 | [`08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/`](08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/) | ✅ Written 2026-10-27 |

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

### Folder 02 contents

1. [Continuous batching: Orca, chunked prefill, and Sarathi-Serve](02-High-Throughput-Serving-and-Distributed-Inference/01-continuous-batching-orca-chunked-prefill-and-sarathi.md)
   covers the convoy effect of static batching, iteration-level scheduling with selective batching, and the scheduler
   state machine. It prices prefill–decode interference: one 32K prompt stalls 64 streams for 1.66 s, and a 512-token
   budget caps the stall at 35 ms. It derives the token budget from the ITL SLO, and shows goodput doubling under a
   tight TPOT. A Java token-budget micro-batcher covers embedders and rerankers.
2. [Disaggregated serving: the prefill/decode split and KV transfer over RDMA](02-High-Throughput-Serving-and-Distributed-Inference/02-disaggregated-serving-prefill-decode-split-and-kv-cache-rdma.md)
   asks when splitting wins: +33% goodput at a tight TPOT, none at a loose one. It derives the P:D ratio in closed form
   (which predicts the simulator's optimum) and gives the KV transfer/compute ratio per network. It covers layer-wise
   streaming, descriptor storms vs KV layout, heterogeneous-TP transfer plans, and Mooncake's KV-centric design. A
   Java leak-free handoff protocol uses leases, idempotent releases and epoch fencing.
3. [Speculative decoding, quantization (FP8, AWQ), and tensor parallelism](02-High-Throughput-Serving-and-Distributed-Inference/03-speculative-decoding-quantization-fp8-awq-and-tensor-parallelism.md)
   proves speculative sampling exact (TV at the noise floor; greedy-match verification is biased) and shows speedup
   collapsing with batch. It builds the FP8 E4M3/E5M2 grids from bits, compares INT8/FP8/INT4 schemes, SmoothQuant
   and AWQ (−50% W4 error), and covers Megatron TP with ring all-reduce and sequence parallelism, latency-bound decode
   collectives, and a Java deployment advisor searching TP × format × speculation per SLO.

### Folder 03 contents

1. [HNSW: skip-list graphs, memory math, and the filtered-search traps](03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/01-hnsw-skip-list-graphs-memory-math-and-filtered-search-traps.md)
   derives exact RAM per vector; the brief's rule of thumb is within 1% at d=768, M=16 and 11% high at d=128, M=48.
   It shows why strict in-graph filtering disconnects (expected passing degree $sM_0$), why post-filtering returns
   nothing, and why iterative scans can exceed brute force. It covers ACORN-style two-hop expansion, exact bitmap
   scans and a cardinality planner, ending with a Java flat-array HNSW.
2. [DiskANN: Vamana, RobustPrune, PQ in RAM, and NVMe beam search](03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/02-diskann-vamana-robust-prune-pq-ram-and-nvme-beam-search.md)
   covers the effect of α on degree and hops, PQ/ADC (alone 0.77 recall, with re-ranking 1.0), sector co-location,
   and beam width W (3.7× fewer round trips), with billion-scale RAM/IOPS budgets. A Java listing runs a real sector
   file with concurrent positional reads on virtual threads.
3. [IVF-PQ, scalar and binary quantization, SIMD scans, and pgvector vs Qdrant vs Milvus](03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/03-ivf-pq-scalar-binary-quantization-and-pgvector-vs-qdrant-milvus.md)
   covers IVF recall vs nprobe and the PQ plateau (0.674 → 0.998 with re-ranking). It shows SQ8 near-lossless and
   binary quantization as an oversampled first stage, then Panama SIMD kernels (5.3× float, 11.6× int8, 79× binary).
   It closes with an engine decision matrix and pgvector patterns.

### Folder 04 contents

1. [Chunking: semantic splits, late chunking, Contextual Retrieval, and ColBERT](04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/01-semantic-chunking-late-chunking-contextual-retrieval-and-colbert.md) covers the coreference failure (paragraph recall@1 0.287, fixed windows 0.000) and its fixes. Contextual prefixes and late chunking lift recall@5 to 1.0, and ColBERT MaxSim on contextual chunks reaches recall@1 1.0. A Java chunker provides exact offsets, atomic code blocks and content-addressed IDs, so a one-number edit re-embeds 1 of 5 chunks.
2. [Hybrid search: BM25, SPLADE, dense, RRF, and cross-encoder reranking](04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/02-hybrid-search-bm25-splade-dense-rrf-and-cross-encoder-reranking.md) covers complementary blind spots (exact-code MRR: BM25 1.0, dense 0.002). It shows RRF's measured failure mode: it discards the score gap, giving 0.075 at k=60, which routing fixes. It sweeps k, shows reranking reaching ≥ 0.89 on every query class, and costs rerankers in FLOPs. A Java retriever handles deadline, hedging, degradation and ACL-in-backend.
3. [GraphRAG, streaming ingestion (Kafka CDC), and ACL security trimming](04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/03-graphrag-streaming-ingestion-kafka-cdc-and-acl-security-trimming.md) shows prompt-level trimming leaking while bitmap pre-filters don't, and CDC convergence under replays, async embedding and backfills. Per-field versions are needed because a single row version left 6 stale docs. GraphRAG global search covers 5/5 themes vs 4/5 for top-k. A Java zero-trust trimmer uses immutable snapshots and assembly-time re-checks.

### Folder 05 contents

1. [MCP on the wire: JSON-RPC, the lifecycle state machine, host/client/server, and transports](05-Model-Context-Protocol-MCP-Architecture/01-mcp-jsonrpc-state-machine-host-client-server-and-transports.md) is observed against the official Python SDK `mcp` 2.3.0, in which FastMCP is renamed `MCPServer`. It covers the error model (tool failures are `isError` results), handshake negotiation and counter-offers, and the 2026-07-28 stateless per-request envelope (`server/discover`, `_meta` keys, new error codes). A zero-dependency Java stdio host drives the Python SDK server.
2. [Enterprise MCP security: OAuth 2.1, the confused deputy, tool poisoning, and sandboxing](05-Model-Context-Protocol-MCP-Architecture/02-enterprise-mcp-security-oauth2-confused-deputy-and-sandboxing.md) covers audience-bound tokens (RFC 8707/9728), why passthrough is forbidden, and the confused deputy reproduced and fixed with RFC 8693 token exchange. It adds SEP-990 ID-JAG, tool pinning, the lethal-trifecta taint gate, roots/SSRF/DNS-rebinding guards, and a Java authorization gateway.
3. [Dynamic tool discovery, sampling, roots, elicitation, and context-bloat mitigation](05-Model-Context-Protocol-MCP-Architecture/03-dynamic-tool-discovery-sampling-roots-and-context-bloat-mitigation.md) shows SDK round trips for sampling, roots and elicitation, which the SDK deprecates as of 2026-07-28 (SEP-2577). It prices 150 tools at ~26K tokens, 7.9 GiB KV and 1.45 s prefill, measures hierarchical tool search at 0.98 recall@5 with 97% fewer tokens, and shows that tool order decides prefix-cache hits. A Java registry and router handles diffs, quarantine and budgets.

### Folder 06 contents

1. [Agentic design patterns: ReAct, plan-and-execute, reflection, and tool DAGs](06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/01-agentic-design-patterns-react-plan-execute-reflection-and-dags.md) treats the agent as a control loop. ReAct latency is a sum while plan-and-execute runs at critical-path latency (3,190 vs 1,300 ms), context tokens grow quadratically (203K vs 49K with compaction, which also changes KV capacity 133 → 616 sessions), and success compounds as pⁿ. Covered: loop guards (108K → 1,280 tokens), idempotency classes, deadlines, fan-out tail latency, reflection that only works with external signals, and a Java DAG executor on virtual threads.
2. [Spring AI, LangChain4j, virtual threads, SSE streaming, and advisors](06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/02-spring-ai-langchain4j-virtual-threads-sse-streaming-and-advisors.md) is compiled and run against the real Spring AI 2.0.2, LangChain4j 1.22.0 and Boot 4.1.2 jars. It records silently dropped tools, `arg0` schemas without `-parameters`, the lazy `call()`, tool-limit finish reasons, PII leaking through advisor order, and raw tool exceptions reaching the model. It sizes streams with Little's law and measures virtual threads at 0.20 s vs a pool at 4.52 s, plus a real WebFlux SSE gateway in which a disconnect cancels generation (10 vs 200 tokens) and asyncio backpressure.
3. [Durable agent execution: Temporal, LangGraph checkpointers, and human-in-the-loop](06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/03-durable-agent-execution-temporal-langgraph-checkpointers-and-hitl.md) argues why exactly-once is impossible and how at-least-once plus idempotency keys gives effectively-once. It compares event-sourced replay with checkpoints and walks through a Java replay engine with non-determinism detection. LangGraph 1.2.18 is crashed with real process kills: the `interrupt()` node re-runs, a crash after the charge gives 2 unkeyed payments vs 1 keyed, `durability` sync vs exit, and pending writes. It closes with the Temporal Java blueprint and approvals bound to action hashes.

### Folder 07 contents

1. [Java blueprint: an MCP server on the official SDK and a resilient RAG orchestrator on Spring AI](07-Production-Code-Blueprints-Java-and-Python/01-java-mcp-server-official-sdk-and-resilient-spring-ai-rag-orchestrator.md). On the MCP Java SDK 2.1.0, schema validation returns model-correctable `isError` results, while a throwing handler becomes a JSON-RPC error carrying the raw exception (an internal IP). One stray stdout line hangs the session for 10 s, and side effects need a `request_id`. Under a deterministic chaos schedule the naive RAG pipeline let 67 errors and 19 invented citations through; the hardened one (cancelling deadlines, degraded retrieval, a no-sources refusal, a citation guard, breaker failover) had 0 and 0, with p99 cut from 260 to 127 ms.
2. [Python blueprint: an MCP tool server, a LangGraph agent and a hardened vLLM streaming client](07-Production-Code-Blueprints-Java-and-Python/02-python-mcpserver-langgraph-agent-and-vllm-streaming-client.md). A fake OpenAI-compatible server injects 429, 503, mid-stream drops and stalled prefill. The client retries only before the first token (the naive one showed duplicated text), treats a stream without `[DONE]` as truncated, scales the TTFT budget with prompt length, and assembles tool-call fragments. A LangGraph agent uses MCPServer tools, routes destructive tools through an `interrupt()` approval, and has two loop guards.
3. [Hybrid search in SQL and CDC ingestion: PostgreSQL 18, a pgvector-style operator and Kafka](07-Production-Code-Blueprints-Java-and-Python/03-hybrid-search-sql-postgres-and-kafka-cdc-ingestion-pipeline.md) runs an embedded Kafka 4.2 broker into an embedded PostgreSQL 18.6, with a consumer crash and stale replays. A per-chunk upsert sink drifts (332 stale, 258 orphan, 21 resurrected and 50 wrong-ACL chunks; a revoked user retrieves 12), while a version-gated, tombstoned, whole-document sink converges exactly. Hybrid FTS + vector + RRF with tenant and ACL pre-filters runs in one SQL statement, alongside capacity, lag and re-embedding arithmetic.
4. [The LLM gateway: semantic caching, token-aware rate limiting and OpenTelemetry GenAI](07-Production-Code-Blueprints-Java-and-Python/04-llm-gateway-semantic-cache-token-rate-limiting-and-otel-genai.md). Similarity is blind to identifiers (A-17 vs A-18 at 1.000), so scoped keys and an entity guard are required; the break-even false-hit rate is 0.051%. Per-tenant reserve-then-refund token buckets stop a noisy neighbour (37 → 0 rejections) and burst overshoot (1.9× → 0.76×). GCRA is equivalent to the token bucket, DRR gives fair admission, and real OTel SDK GenAI spans and metrics are emitted with content off by default.

### Folder 08 contents

1. [AI FinOps: the TCO of self-hosted vLLM on Kubernetes vs managed APIs](08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/01-ai-finops-tco-self-hosted-vllm-on-kubernetes-vs-managed-apis.md) derives capacity from Folder 01's roofline (15.9 req/s per 8×H100 replica for 1K/300 chat, 2.2 for 8K RAG; prefill dominates). Diurnal utilization runs 21% without autoscaling and 38% with it. Under stated price assumptions self-hosting breaks even against a hosted open-model API at about 100 req/s. Sensitivity: autoscaling 2.19×, on-demand pricing 2.22×, FP8 + MTP 0.46×. Commitment has a closed-form rule (commit replica k iff it is needed in ≥ p_c/p_o of hours), confirmed by brute force.
2. [Twenty-five L7 bar-raiser scenarios](08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/02-twenty-five-l7-bar-raiser-scenarios-with-l5-vs-l7-defenses.md): chains from roofline physics to FinOps. Each has the prompt, the L5 answer, why it fails, the L7 defense with the KB's measured numbers, and follow-up probes. `l7_numbers.py` recomputes 19 quoted figures from the Folder 01/03 listings, and `ArchitectureLinter.java` turns the invariants into 22 executable design-review rules.
3. [The curated reading list, each link verified](08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/03-curated-reading-list-papers-and-repositories-verified.md): 60 papers, specifications and repositories mapped to the KB files that use them, each fetched one at a time on 2026-10-27 (HTTP 200 plus expected title keywords). The run found that the OpenTelemetry GenAI conventions moved to their own repository, and that one archive was unreachable behind TLS and bot walls and was replaced.

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
- **Folders 06–08 run against real software, not mocks of it.** The Java listings compile against jars resolved
  offline by Maven:
  - Spring AI 2.0.2, LangChain4j 1.22.0, Spring Boot 4.1.2 (WebFlux on Reactor Netty), MCP Java SDK 2.1.0;
  - spring-kafka-test 4.1.2 with an **embedded Kafka 4.2.2 KRaft broker**, and zonky embedded-postgres 2.2.2 with an
    **embedded PostgreSQL 18.6**;
  - PostgreSQL JDBC 42.7.14 and the OpenTelemetry SDK 1.62.0.

  Python uses `mcp` 2.3.0, `langgraph` 1.2.18 with `langgraph-checkpoint-sqlite`, and `httpx` 0.28.1. Model servers
  are local fakes that speak the OpenAI-compatible wire format; no GPU or API key is needed. The classpath exceeds
  the Windows command-line limit, so the harness passes a pathing jar (a manifest `Class-Path`).
- **Final whole-KB gate (2026-10-27):** all **58** listings extracted from the Markdown were byte-identical to their
  sources and all passed their self-checks when re-run from the extracted copies.
  - **39** outputs were byte-identical to the embedded ones.
  - The other **19** differ only in measured values: latencies, throughputs, build times, SIMD speedups, counts from
    deliberately concurrent chaos runs, and re-fetched page titles. Each is labelled "one measured run" in its file.

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

### Runnable listings in Folder 02

| Listing | Where | Proves |
|---------|-------|--------|
| `batching_sim.py` | 02/01 §3.1 | marginal cost of piggybacked prefill (TP=1 vs TP=8), the 32K-prompt stall, static vs Orca vs chunked, goodput by budget × TPOT SLO |
| `TokenBudgetBatcher.java` | 02/01 §3.2 | continuous micro-batching vs per-request and fixed-size batching; backpressure, cancellation, no stranded futures |
| `kv_transfer_math.py` | 02/02 §6.1 | KV transfer vs prefill compute per network, layer-wise streaming, RDMA descriptor counts by layout, heterogeneous-TP plans, P:D ratio |
| `disagg_sim.py` | 02/02 §6.2 | colocated vs P/D splits on 8 GPUs (discrete-event), goodput at loose vs tight TPOT, KV path impact |
| `PdHandoffCoordinator.java` | 02/02 §6.3 | leased, idempotent, epoch-fenced handoff under chaos (zero leaks) vs a naive push protocol (leaks ~16K blocks) |
| `spec_decoding.py` | 02/03 §A.6 | exactness of speculative sampling (TV at the noise floor), the bias of argmax verification, expected tokens, speedup vs batch |
| `quantization_lab.py` | 02/03 §B.6 | FP8 grids from bits, INT8/FP8/INT4 weight error, outliers + SmoothQuant, AWQ on held-out tokens, bytes per format |
| `tensor_parallel_ref.py` | 02/03 §C.7 | Megatron MLP/GQA attention sharded = unsharded, ring all-reduce traffic, sequence parallelism, collective cost model, TP degree |
| `DeploymentAdvisor.java` | 02/03 Part D | TP × weight format × KV format × speculation search per SLO, asserted equal to Folder 01's `RooflinePlanner` on the BF16 path |

### Runnable listings in Folder 03

| Listing | Where | Proves |
|---------|-------|--------|
| `hnsw_ref.py` | 03/01 §4.1 | HNSW per the paper, exact memory math vs the brief's formula, six filtered strategies by selectivity |
| `HnswFilteredSearch.java` | 03/01 §4.2 | flat-array HNSW; post-filter, iterative scan, filter-aware, ACORN-1, exact, planner; concurrent virtual-thread search |
| `diskann_ref.py` | 03/02 §5.1 | Vamana (α), PQ/ADC, SSD beam search I/O accounting, sector layouts, billion-scale budgets |
| `DiskBeamSearch.java` | 03/02 §5.2 | real 4 KB sector file, PQ in RAM, W concurrent positional reads, naive no-PQ comparison |
| `ivf_pq_lab.py` | 03/03 §6.1 | IVF-Flat/IVF-PQ vs nprobe, re-ranking, SQ8 and binary quantization by dimension, byte budgets |
| `VectorKernels.java` | 03/03 §6.2 | Panama SIMD float/int8/binary kernels vs scalar, recall of quantized scans, filtered exact scan |

`VectorKernels.java` needs the incubator module: compile with `--add-modules jdk.incubator.vector -Xlint:all,-incubating`
and run with `--add-modules jdk.incubator.vector`. The other Java listings compile fine with the same flags.

### Runnable listings in Folder 04

| Listing | Where | Proves |
|---------|-------|--------|
| `chunking_lab.py` | 04/01 §3.1 | fixed vs paragraph vs contextual vs late chunking vs ColBERT MaxSim on a coreference-heavy corpus |
| `ChunkingPipeline.java` | 04/01 §3.2 | structure-aware chunking, exact offsets, atomic code blocks, contextual headers, content-addressed IDs |
| `hybrid_search_lab.py` | 04/02 §3.1 | BM25, dense, learned sparse, four fusion rules, routing, RRF k sweep, reranking, reranker FLOPs |
| `HybridRetriever.java` | 04/02 §3.2 | deadline-bounded fan-out, hedging, degraded results, weighted RRF, reranker fallback, ACL in backends |
| `rag_acl_ingest_lab.py` | 04/03 §4.1 | ACL trimming strategies, CDC convergence (per-field versions, tombstones), GraphRAG coverage |
| `AclSecurityTrimmer.java` | 04/03 §4.2 | nested groups, allow/deny bitset snapshots, versioned ACL events, assembly re-check, concurrent revocation |

### Runnable listings in Folder 05

| Listing | Where | Proves |
|---------|-------|--------|
| `mcp_wire_lab.py` | 05/01 §6.1 | SDK MCPServer over stdio driven by a raw JSON-RPC client: lifecycle, errors, progress, envelope probe |
| `McpStdioClient.java` | 05/01 §6.2 | zero-dependency Java host: JSON codec, lifecycle, id correlation, cancellation; interop with the Python SDK |
| `mcp_security_lab.py` | 05/02 §5.1 | audience validation, passthrough, confused deputy vs token exchange, poisoning, taint gate, roots, SSRF |
| `McpAuthorizationGateway.java` | 05/02 §5.2 | resource-server JWT policy with 401/403 challenges, RFC 8693 exchange, canonical tool pinning, audit |
| `tool_router_lab.py` | 05/03 §4.1 | SDK sampling/roots/elicitation callbacks, catalog cost via roofline, tool search recall, cache-order effects |
| `ToolRegistryRouter.java` | 05/03 §4.2 | list_changed diffs (SHA-256), quarantine, tenant allowlists, hierarchical routing under a token budget |

Folder 05's Python listings need the MCP SDK: `pip install "mcp>=2.3,<3"`. On Windows with `--target` installs, process `.pth` files (`site.addsitedir`) so pywin32 loads. `McpStdioClient` launches `python mcp_wire_lab.py --serve`, so run it from the listings directory with the SDK importable.

### Runnable listings in Folder 06

| Listing | Where | Proves |
|---------|-------|--------|
| `agent_patterns.py` | 06/01 §4.1 | ReAct, loop guards, DAG scheduling vs sequential, reflection stop rules, quadratic context vs compaction |
| `AgentDagExecutor.java` | 06/01 §4.2 | validated plans (Kahn), virtual-thread DAG execution, idempotent-only retries, timeouts, fail-fast vs continue, LoopGuard |
| `SpringAiAdvisorPipeline.java` | 06/02 §4.1 | Spring AI 2.0.2: advisor onion and order constants, tool loop, limits, PII ordering, memory window, budget short-circuit, stream cancel |
| `Lc4jAgentService.java` | 06/02 §4.2 | LangChain4j 1.22.0: AiServices tools + memory, round-trip guard, hallucinated tools, tool errors, parallel tools, virtual threads vs pool |
| `SseStreamingGateway.java` | 06/02 §4.3 | Boot 4.1.2 WebFlux SSE from ChatClient.stream(): heartbeats, TTFT, gaps, disconnect cancels generation vs naive bridge |
| `sse_gateway_lab.py` | 06/02 §4.4 | Little's law sizing, asyncio SSE cancellation vs worker-thread bridge, drain() backpressure |
| `DurableWorkflowEngine.java` | 06/03 §3.1 | Temporal-style replay journal: no re-execution of completed steps, idempotency keys across a crash, durable signals, non-determinism detection |
| `langgraph_durable_lab.py` | 06/03 §3.2 | LangGraph 1.2.18 + SQLite checkpointer under real process kills: interrupt re-run, keyed vs unkeyed payments, durability modes, pending writes |

Folder 06's Java listings compile against a classpath resolved offline by Maven (`spring-ai-client-chat` 2.0.2, `langchain4j` 1.22.0, `spring-boot-starter-webflux` 4.1.2; `mvn dependency:build-classpath`) and need `javac -parameters`. `langgraph_durable_lab.py` needs `pip install "langgraph==1.2.18" langgraph-checkpoint-sqlite` and launches itself as child processes.

### Runnable listings in Folder 07

| Listing | Where | Proves |
|---------|-------|--------|
| `McpJavaKnowledgeServer.java` | 07/01 §3.1 | MCP Java SDK 2.1.0 server + SDK client over stdio: schemas, annotations, validation, error semantics, request_id idempotency, stdout trap |
| `ResilientRagOrchestrator.java` | 07/01 §3.2 | Spring AI RAG under chaos: cancelling deadlines, degraded retrieval, ACL pre-filter, no-source refusal, citation guard, breaker failover |
| `vllm_stream_client.py` | 07/02 §2.1 | fault-injecting OpenAI-compatible SSE server + hardened httpx client: retry-before-first-token, PartialStream, TTFT budget, tool-call assembly |
| `mcp_langgraph_agent.py` | 07/02 §2.2 | LangGraph agent over MCPServer tools and the streaming client: annotation-driven approval interrupt, ToolError semantics, tool budget, recursion_limit |
| `HybridSearchCdcPipeline.java` | 07/03 §3.1 | embedded Kafka 4.2 + PostgreSQL 18.6: naive vs version-gated CDC sinks through a crash and replays; hybrid FTS+vector RRF in one SQL statement |
| `pg_hybrid_capacity_lab.py` | 07/03 §3.2 | pgvector-style storage and HNSW memory, exact-scan cost, CDC drain time, re-embedding cost |
| `LlmGateway.java` | 07/04 §2.1 | scoped, entity-guarded semantic cache sweep; per-tenant reserve-then-refund token buckets; OTel SDK GenAI spans and metrics |
| `gateway_economics_lab.py` | 07/04 §2.2 | GCRA == token bucket, FIFO vs weighted DRR under overload, semantic-cache break-even false-hit rate |

Folder 07's Java listings compile and run against the offline Maven classpath of Folder 06, extended with spring-kafka-test 4.1.2 (Kafka 4.2.2), zonky embedded-postgres 2.2.2 (PostgreSQL 18.6 binaries), PostgreSQL JDBC 42.7.14 and OpenTelemetry SDK 1.62.0. That classpath exceeds the Windows command-line limit, so the harness passes a pathing jar (`tools/make_pathing_jar.py`: a manifest `Class-Path`). `ResilientRagOrchestrator` uses `AgentDagExecutor.sleepQuietly` from Folder 06; `mcp_langgraph_agent.py` imports `vllm_stream_client.py`.

### Runnable listings in Folder 08

| Listing | Where | Proves |
|---------|-------|--------|
| `llm_tco_model.py` | 08/01 §2.1 | capacity from the roofline, monthly self-host vs API cost, break-even volume, sensitivity |
| `CapacityMixPlanner.java` | 08/01 §2.2 | committed vs on-demand replica mix on a weekly curve: closed form f_k >= p_c/p_o equals brute force |
| `l7_numbers.py` | 08/02 §4.1 | 19 whiteboard numbers recomputed from the KB's listings and asserted against the playbook |
| `ArchitectureLinter.java` | 08/02 §4.2 | the invariants checklists as 22 design-review rules keyed to the 25 scenarios |
| `verify_reading_list.py` | 08/03 §3 | the 60-entry reading list as data, each URL fetched sequentially and checked for status and title keywords |

`llm_tco_model.py` imports `roofline.py`; `CapacityMixPlanner.java` uses `RooflinePlanner.java`; `l7_numbers.py` imports `roofline.py`, `kv_cache_math.py` and `hnsw_ref.py`. `verify_reading_list.py` needs network access, and its output is dated.

**Cross-folder imports.** Listings build on each other: `paged_attention_ref.py` imports `paged_kv_manager.py`; Folder
02's Python imports `roofline.py` / `kv_cache_math.py` (Folder 01) and `batching_sim.py`; `DeploymentAdvisor.java`
uses `RooflinePlanner.java`. Put all listings in one directory. Java listings declare `package dev.l7.ai.inference;`:
compile them together with `javac --release 21 -d out *.java`, then run `java -ea -cp out dev.l7.ai.inference.<Name>`.

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
- **"Durable agents give exactly-once side effects"** is not achievable by any orchestrator. Temporal and LangGraph
  re-execute the step in flight. Effectively-once is at-least-once plus an idempotent receiver, measured under real
  process kills: 2 charges without a key, 1 with it (06/03). LangGraph's node that calls `interrupt()` re-runs from
  its first line on resume.
- **Framework defaults are not neutral.** On the real Spring AI 2.0.2 jars:
  - a custom `ChatModel` without `ToolCallingChatOptions` silently drops tools;
  - `-parameters` decides whether the tool schema says `orderId` or `arg0`;
  - `call()` is lazy;
  - a `THROW` tool limit *returns* a finish reason.

  LangChain4j 1.22.0 sends raw tool exceptions to the model by default. The MCP Java SDK 2.1.0 turns a throwing
  handler into a JSON-RPC error carrying the raw message; the Python SDK sanitizes it (06/02, 07/01–02).
- **The brief's "FastMCP"** is `MCPServer` in the official Python SDK 2.x (05/01).
- **"Hybrid search in pgvector"** needs two caveats. `ts_rank_cd` is not BM25, and without an ANN index the vector
  leg scans every row the filter admits (07/03; pgvector itself was emulated with a `<=>` operator on `float8[]`).
- **Semantic caching by similarity threshold alone is unsafe.** Embeddings scored "order A-18" at 1.000 against
  "order A-17", so a scope and an entity guard are required, and the threshold is priced by the false-hit cost
  (07/04).
- **OpenTelemetry GenAI conventions** moved to their own repository (`open-telemetry/semantic-conventions-genai`)
  as of semconv 1.44.0, and `gen_ai.system` became `gen_ai.provider.name` (07/04, 08/03).
- **"Self-hosting is cheaper at scale"** holds only past a break-even that depends on utilization, prompt length and
  people cost: about 100 req/s under this KB's stated price assumptions (08/01).
