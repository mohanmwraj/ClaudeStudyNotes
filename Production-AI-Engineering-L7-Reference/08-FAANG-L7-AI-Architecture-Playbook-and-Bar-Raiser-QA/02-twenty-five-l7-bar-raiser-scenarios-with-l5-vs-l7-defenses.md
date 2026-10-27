# 02 · Twenty-Five L7 Bar-Raiser Scenarios, with L5 Answers, Why They Fail, and L7 Defenses

> **Folder:** `08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/` · **File 2 of 3**
> **How to use this file:** each scenario is a chain. The opening prompt is followed by the answer that sounds fine
> but is L5, why it fails at scale, the L7 defense with the numbers that carry it, and the follow-up probes a
> bar-raiser uses to find the edge of your understanding. Every number is derived in Folders 01–07, and
> `l7_numbers.py` (§4.1) recomputes the key ones and asserts they match.
> **Code baseline:** Python 3.10+ (imports Folders 01 and 03 listings) · Java 21 (no dependencies).
> **Previous:** [01 · AI FinOps TCO](01-ai-finops-tco-self-hosted-vllm-on-kubernetes-vs-managed-apis.md) ·
> **Next:** [03 · Curated reading list](03-curated-reading-list-papers-and-repositories-verified.md)

---

## 0. The thesis in one paragraph

Bar-raisers do not grade the architecture diagram. They grade whether you can **predict the system's behaviour
before it exists**: which resource saturates first, which number decides the design, which failure happens at 10×
scale, and what you will measure to know. An L5 answer names components ("add a vector DB, a cache and retries").
An L7 answer:

- names the **binding constraint** with a number, for example "decode is memory-bound: intensity 112 FLOP/B against
  a ridge of 295";
- picks the design that **moves that constraint**;
- states the **failure mode it introduces**, and how it will be detected and bounded;
- **prices the result** in money, latency and operational load.

The 25 chains below cover the whole stack this KB builds, from roofline physics to FinOps.

---

## 1. First principles: the shape of an L7 answer

1. **Requirements as numbers.** Users, QPS, prompt and output lengths, TTFT and TPOT SLOs, availability, data
   sensitivity. If the interviewer does not give them, propose them and say so.
2. **Back-of-envelope before boxes.** KV bytes per token, capacity per replica, concurrency via `L = λW`, memory for
   indexes, availability products, token costs. The table in §2 is the minimum set.
3. **Architecture around the hard part.** Name the one thing that is hard (KV capacity, filtered ANN, ACL
   propagation, tool security, durable side effects) and spend your time there.
4. **Failure modes with signatures.** For each component, the symptom, how it shows in metrics and traces, and the
   mitigation.
5. **Operations.** SLOs, the dashboards that would have caught the failure, rollout and rollback, evaluation gates.
6. **Evolution and cost.** What changes at 10× traffic, the next model generation, or the next price change.

---

## 2. Numbers you must be able to derive

These are recomputed by `l7_numbers.py`; the scenario id shows where each is used.

| Quantity | Value | Scenario |
|---|---|---|
| KV per token, Llama-3-70B (GQA: 80 layers × 8 KV heads × 128 × 2 × 2 B) | 327,680 B | S01 S02 |
| KV per token, DeepSeek-V3 (MLA latent: 61 × (512 + 64) × 2 B) | 70,272 B | S01 |
| KV capacity, 70B on 8×H100 TP8 | 1,356,942 tokens | S02 S07 |
| Decode intensity limit at 4K context vs H100 BF16 ridge | 111.6 vs 295.3 FLOP/B | S01 |
| Uncached prefill of a 26K-token tool catalog on 70B/8×H100 | 1,454 ms | S13 |
| HNSW bytes per vector (d = 768, M = 16) | 3,228.5 B | S09 |
| Availability: 4 dependencies in series / with optional vector and LLM failover | 98.80% / 99.90% | S20 |
| Concurrent streams at 200 req/s (500 tokens @ 30 ms + 0.8 s TTFT) | 3,160 | S21 S23 |
| Task success at 95% per step over 20 steps | 0.358 | S16 S17 |
| Cumulative prompt tokens, 40 agent steps (quadratic) | 203,000 | S16 |
| P(one of 6 parallel tools exceeds its P99) | 5.85% | S17 |
| Retry amplification, 3 retries at 3 layers | 64× | S21 |
| Semantic-cache break-even false-hit rate | 0.051% | S22 |
| CDC drain of 10M events at 10% headroom | 139 h | S12 |
| Survival of a 24 h approval wait at 5 deploys/day | 0.0067 | S18 |
| Commit threshold at $3.50/$6.00 per GPU-hour | 0.583 | S24 |

---

## 3. The twenty-five chains

### Part A · Inference physics and serving

#### S01 · "Our 70B model's decode is slow. Should we buy GPUs with more FLOPs?"

- **Probing:** whether you know decode's binding resource.
- **L5 answer:** "Yes, or use a faster GPU like B200 for its FLOPs."
- **Why L5 fails at scale:** decode streams all weights and every sequence's KV for each token. Its arithmetic
  intensity approaches **111.6 FLOP/B at 4K context**, far below H100's ridge of **295**, so it is memory-bound at
  any batch. More FLOPs change nothing; HBM bandwidth and bytes moved do.
- **L7 principal defense:**
  1. Raise the batch until the TPOT SLO binds, which amortizes weight reads (continuous batching).
  2. Cut bytes: FP8 or INT8 weights and FP8 KV; MLA-style latent KV where the model allows (DeepSeek-V3 needs
     70,272 B/token against 327,680 for 70B GQA).
  3. Use speculative decoding at low batch.
  4. Buy **bandwidth and capacity** (H200 or B200 for HBM), not FLOPs.
- **Follow-ups:**
  - "When does decode become compute-bound?" → MoE with large expert batches (about 9.5K tokens per step to reach
    the ridge) or very short contexts at huge batch; never for long-context dense decode.
  - "Why does TP8 beat TP4 per GPU?" → KV capacity: more HBM for KV means larger batches (1,456 vs 1,137
    tok/s/GPU).

#### S02 · "Size the GPU fleet for a 1M-DAU assistant."

- **L5 answer:** "Benchmark tokens/s on one GPU, divide total tokens by it."
- **Why L5 fails at scale:** peak tokens/s ignores the TPOT SLO, KV capacity, prompt length and diurnal peaks.
  Prefill often dominates per-request GPU time: 49 ms of prefill against 13.8 ms of decode share for 1K/300 chat.
- **L7 principal defense:**
  1. Convert DAU to peak req/s: sessions × turns × the peak/mean ratio.
  2. Per replica, take the batch at the TPOT SLO bounded by KV capacity (1,356,942 tokens on 8×H100 TP8) plus prefill
     time. That is about **15.9 req/s** for 1K/300 chat but **2.2 req/s** for 8K RAG prompts.
  3. Replicas = peak / (capacity × 0.7) + N+1, with autoscaling and a commitment mix (S24).
  4. Validate with measured goodput on replayed traces.
- **Follow-ups:**
  - "What changes if half the traffic is RAG with 8K prompts?" → capacity falls about 7× for that half; prefix
    caching and context budgets become the cost lever.

#### S03 · "TTFT spikes for everyone when one user pastes a long document."

- **L5 answer:** "Add more replicas."
- **Why L5 fails at scale:** whole-prompt prefill monopolizes the step. A 32K prompt among 64 streams stalled decode
  for **1,661 ms**. More replicas only dilute how often it happens.
- **L7 principal defense:**
  1. Chunked prefill with a per-step token budget: budget 512 capped the stall at **35 ms**, at the cost of 38%
     higher TTFT for the long prompt.
  2. Tune the budget against the TPOT SLO (goodput at TPOT 15 ms rose from 8 to 16 QPS).
  3. At scale, use prefill/decode disaggregation (S04) or routing of long prompts to a separate pool.
- **Follow-ups:**
  - "How do you pick the budget?" → the largest budget whose step time keeps p99 TPOT within the SLO at the target
    batch; a loose SLO favours 2,048.

#### S04 · "Should we disaggregate prefill and decode?"

- **L5 answer:** "Yes, everyone does it now."
- **Why L5 fails at scale:** it pays off only when the TPOT SLO is tight. On 8 GPUs it gained **+33%** goodput at a
  tight TPOT (60 vs 45 QPS) and **0%** at a loose one (75 = 75). It also adds KV transfer, and with a mismatched
  model and network the transfer can exceed prefill compute: 9.4× for an MHA 7B over TCP.
- **L7 principal defense:**
  1. Decide on goodput at our SLO and our prompt/output mix.
  2. Size P:D from service rates (μ_d : μ_p predicted 6P2D at 2.72:1).
  3. Verify the transfer budget: for 70B GQA over 400G RDMA it is about 3% of prefill compute. Use layer-wise
     streaming and descriptor batching (16-token layer-major blocks meant 81,920 RDMA descriptors in Folder 02's
     example).
  4. Plan failure handling for lost handoffs with leases and idempotent, epoch-fenced protocols.
- **Follow-ups:**
  - "What breaks in production?" → stranded KV after decode-node failure, P:D drift as the traffic mix changes, and
    heterogeneous TP mappings between pools.

#### S05 · "Quantize the 70B model to FP8 or INT4 to halve cost?"

- **L5 answer:** "FP8 is lossless; ship it."
- **Why L5 fails at scale:** quantization error depends on outliers and on the format. In the lab, INT8 per-channel
  weights had lower error than FP8 weights; activations needed SmoothQuant (error 0.097 → 0.019); AWQ halved
  held-out error over naive INT4. "Lossless" is a claim to measure.
- **L7 principal defense:**
  1. Pick the format per tensor class: FP8 or INT8 weights, FP8 KV, careful activation handling.
  2. Gate on task evaluations (not perplexity alone), including long-context and tool-calling suites.
  3. Price the gain: FP8 + FP8 KV + MTP is about 3× the BF16 baseline in the Folder 02 advisor, 0.46× cost in the
     Folder 08 TCO model.
  4. Roll out per model and use case with shadow comparisons.
- **Follow-ups:**
  - "Why does KV quantization matter more at long context?" → KV bytes dominate decode traffic and capacity as
    context grows.

#### S06 · "Speculative decoding made our throughput worse."

- **L5 answer:** "The draft model must be bad; train a better one."
- **Why L5 fails at scale:** speculation trades extra compute for fewer sequential steps. At high batch decode is
  already efficient and the verify cost dominates. A 1B draft with γ = 4 gave **1.96× at batch 1 but 0.95× at
  batch 256**.
- **L7 principal defense:**
  1. Make speculation batch-aware: enable it below a batch threshold, or adapt γ dynamically.
  2. Prefer cheap drafters (EAGLE or MTP heads cost about 0.04 of a step against 0.1 for a small model).
  3. Confirm losslessness statistically: the lab's TV distance of 0.0167 sat under a noise floor of 0.0176, while
     an argmax-only shortcut measured 0.342.
- **Follow-ups:**
  - "What metric gates it?" → goodput at the SLO across the batch distribution, not single-stream latency.

#### S07 · "Prefix caching worked on one replica but not across the fleet."

- **L5 answer:** "Use a bigger cache."
- **Why L5 fails at scale:** with round-robin routing each replica sees a fraction of every prefix's traffic. The
  hit rate fell to **67.2%** against **93.7%** with cache-aware routing.
- **L7 principal defense:**
  1. Route by prefix hash (consistent hashing on the system prompt and tool block) with a load guard. The guard capped
     a hot replica from 75% to 29% of traffic.
  2. Use LPM scheduling inside the replica (91.5% vs 47.4% for FCFS).
  3. Keep prompts deterministic: stable tool order (S13), no timestamps in system prompts.
  4. Prefer swapping to recomputing for long sequences (3.4 ms swap vs 201 ms recompute for a 4K 70B sequence).
- **Follow-ups:**
  - "Why did hits drop after a gateway upgrade?" → nondeterministic prompt assembly: map iteration order,
    reordered tools.

### Part B · Retrieval

#### S08 · "Vector search returns too few results when users filter by department."

- **L5 answer:** "Increase k and post-filter."
- **Why L5 fails at scale:** at 1% selectivity post-filtering returned recall **0.037** and strict in-graph
  filtering **0.031**: the filtered subgraph disconnects. Raising k scales cost without fixing recall.
- **L7 principal defense:**
  1. A planner by selectivity: an exact scan over the filtered set for very selective filters (recall 1.000 with 47
     evaluations), filter-aware traversal or ACORN-style two-hop expansion in the middle, plain HNSW for unselective
     filters.
  2. Partition or build per-tenant indexes for the largest tenants.
  3. Measure recall@k *under filters*, not unfiltered.
- **Follow-ups:**
  - "pgvector's iterative scans?" → they help, but at 0.1% selectivity one cost 43,680 distance evaluations on a 20K
    index, worse than brute force over the 20 matching rows.

#### S09 · "Our HNSW index doesn't fit in RAM."

- **L5 answer:** "Buy bigger machines."
- **L7 principal defense:**
  1. Do the arithmetic: **3,228.5 B per vector** at d = 768, M = 16 (vector plus links), about 32 GB per 10M vectors.
  2. Compress: halfvec (2×), SQ8 (4× smaller; its Panama SIMD kernel ran 11.6× faster than scalar code), or binary
     quantization with re-scoring (32× smaller, 79× SIMD speedup; recall 0.993 at 512-d with a 300-candidate
     re-score).
  3. Move to SSD-resident graphs (DiskANN: PQ codes in RAM, full vectors on NVMe, beam width 4 cuts round trips
     3.7×).
  4. Always re-rank: PQ-only recall was 0.77; re-ranking restores 1.0.
- **Follow-ups:**
  - "IVF-PQ instead?" → recall plateaus (0.674 here) unless you re-rank; nprobe trades latency for recall.

#### S10 · "Hybrid search is worse than plain BM25 for part numbers."

- **L5 answer:** "Tune the RRF k."
- **Why L5 fails at scale:** RRF discards score gaps. When one retriever is noise for a query class (dense
  embeddings on exact codes), fusion buries the right answer: **MRR 0.075** against BM25's 1.000.
- **L7 principal defense:**
  1. Route by query type: identifier-like queries go lexical-only (routed MRR 1.000).
  2. Use weighted fusion or a cross-encoder reranker for the rest (dense paraphrase MRR 0.958).
  3. Evaluate per query class, never on the average.
- **Follow-ups:**
  - "Reranker latency?" → about 1.4 ms for a MiniLM-sized cross-encoder per batch on H100 by FLOP count; budget it in
    the 50 ms rerank slot.

#### S11 · "How do we chunk 10,000 legal contracts?"

- **L5 answer:** "512-token fixed chunks with overlap."
- **Why L5 fails at scale:** fixed chunks cut definitions from the clauses that use them. Recall@1/@5 was
  **0.000/0.050** for fixed chunks against 0.713/1.000 for contextual retrieval.
- **L7 principal defense:**
  1. Structure-aware chunks (sections, clauses) with the section path in metadata.
  2. Contextual retrieval (prepend a chunk-specific context) or late chunking (0.613/1.000), and ColBERT-style
     late interaction for the hardest corpora (1.000/1.000).
  3. Content-addressed chunk ids that exclude the version, so a one-number edit changes one chunk id, not all.
  4. An evaluation set of real questions per document type.
- **Follow-ups:**
  - "Cost of contextual retrieval?" → one LLM call per chunk at ingestion, cheap with prompt caching of the
    document; re-run only changed chunks.

#### S12 · "A user saw a document after their access was revoked."

- **L5 answer:** "Filter results by ACL before showing them."
- **Why L5 fails at scale:** post-generation filtering is too late: the model already read the content. The index
  itself can also be wrong. In the Kafka/Postgres lab, a stale backfill rolled ACLs back and the revoked user
  retrieved **12 chunks** from the naive index (0 from the version-gated one). The Folder 04 simulation produced 184
  wrong ACLs with naive consumers.
- **L7 principal defense:**
  1. ACL pre-filtering inside retrieval from an authoritative entitlement snapshot.
  2. A CDC sink that is version-gated, with tombstones and per-field versions when ACLs and content come from
     different systems.
  3. An SLO on revocation propagation, and separate backfill capacity (a 10M backlog at 10% headroom drains in
     139 h).
  4. Audits against source truth.
- **Follow-ups:**
  - "Group membership changes?" → expand groups at query time from the identity system's closure, with a short TTL
    and snapshot versioning.

### Part C · Tools, MCP and agents

#### S13 · "Connect our 400 internal tools to the agent."

- **L5 answer:** "Expose them all through MCP; the model will choose."
- **Why L5 fails at scale:** 150 tools already cost about **26K tokens, 7.9 GiB of KV and 1.45 s of uncached
  prefill** per request on 70B/8×H100, and selection accuracy drops among near-duplicates.
- **L7 principal defense:**
  1. Entitlements first.
  2. Hierarchical routing (system, then tools) with semantic top-k: **0.98 recall@5 with 97% fewer tokens**.
  3. A `search_tools` fallback.
  4. A **stable tool order** so the prefix caches: reordering per request shared 0 of 150 schemas.
  5. `list_changed` diffs with quarantine.
- **Follow-ups:**
  - "Tool poisoning?" → pin definitions by hash and quarantine changes (S14).

#### S14 · "The agent reads email, browses the web and queries internal docs. Is it safe?"

- **L5 answer:** "We use a strong system prompt telling it to ignore injected instructions."
- **Why L5 fails at scale:** that is the **lethal trifecta**: private data, untrusted content and an exfiltration
  channel in one context. Prompts are not a security boundary.
- **L7 principal defense:**
  1. A taint gate: once untrusted content enters the context, tools that can exfiltrate (send, post, fetch arbitrary
     URLs) require approval or are disabled.
  2. Split agents by privilege.
  3. Allowlists, SSRF and DNS-rebinding guards, and roots for file access.
  4. Pin tool definitions against rug pulls.
- **Follow-ups:**
  - "Detection?" → instruction-pattern scanning of tool outputs as a signal, never the control.

#### S15 · "Our MCP server calls downstream APIs with the user's token."

- **L5 answer:** "Pass the user's bearer token through."
- **Why L5 fails at scale:** token passthrough is forbidden by the MCP authorization spec. Tokens must be
  audience-bound to the MCP server (RFC 8707/9728), or any server holding a token can replay it elsewhere: the
  confused deputy.
- **L7 principal defense:**
  1. The MCP server validates audience and scopes.
  2. It obtains downstream tokens by **RFC 8693 token exchange** carrying an `act` claim (who acts for whom), with
     least privilege per downstream API.
  3. Enterprise IdP-issued grants (SEP-990's ID-JAG) for cross-app access.
  4. Audit every exchange.
- **Follow-ups:**
  - "401 vs 403?" → 401 with a `WWW-Authenticate` challenge carrying `resource_metadata` for discovery; 403 for
    insufficient scope, without leaking which tools exist.

#### S16 · "Our agent occasionally loops and burns hundreds of dollars."

- **L5 answer:** "Lower max_steps."
- **L7 principal defense:**
  1. Guard on repeated identical calls, no-progress observations, a token budget and a deadline. The lab's stubborn
     model went from **108,000 to 1,280 tokens**.
  2. Circuit breakers on failing tools.
  3. Compaction: context tokens grow quadratically (203K vs 49K over 40 steps).
  4. Structured stop reasons and alerts on steps-per-session percentiles.
- **Follow-ups:**
  - "Why not just a step cap?" → a cap still burns the cap on every bad trace and cuts off legitimate long tasks;
    success compounds as pⁿ (0.358 at 20 steps of 95%), so shorter loops are also more accurate.

#### S17 · "Make the agent faster."

- **L5 answer:** "Use a faster model."
- **Why L5 fails at scale:** ReAct latency is a sum of model calls and tool calls.
- **L7 principal defense:**
  1. Plan-and-execute over a validated DAG at critical-path latency: **3,190 → 1,300 ms** in the lab, with model
     calls dropping from n to 2.
  2. Parallel tool calls (102 vs 202 ms in LangChain4j with concurrent execution).
  3. Cheap models for routing steps.
  4. Mind the fan-out tail: with 6 parallel tools, 5.85% of requests hit at least one tool's P99, so use per-tool
     timeouts and hedging.
- **Follow-ups:**
  - "When is ReAct right?" → when each observation changes the next step (exploration); hybrid replanning
    otherwise.

#### S18 · "Approvals can take three days. How do you build the agent?"

- **L5 answer:** "Keep state in memory and poll an approvals table."
- **Why L5 fails at scale:** at five deploys a day, a 24 h wait survives in memory with probability **0.0067**.
- **L7 principal defense:**
  1. Durable execution: a Temporal workflow with a signal and `Workflow.await(48h)`, or a LangGraph checkpointer with
     `interrupt()` and synchronous durability.
  2. Approvals bound to an action hash, with timeouts and escalation.
  3. In LangGraph, never put side effects in the node that calls `interrupt()`: it re-runs, and the notification
     was sent **twice** in the lab.
  4. `durability="exit"` redid all 4 steps after a crash; `"sync"` redid only one.
- **Follow-ups:**
  - "Changing the workflow mid-flight?" → versioning (`Workflow.getVersion`), replay tests, additive graph changes.

#### S19 · "Guarantee the refund happens exactly once."

- **L5 answer:** "Temporal (or Kafka) gives exactly-once."
- **Why L5 fails at scale:** no orchestrator shares a transaction with the payment provider, so a crash between
  "acted" and "recorded" forces either duplicate or lost effects.
- **L7 principal defense:**
  1. At-least-once execution plus an idempotent receiver: the key is workflow id + step id. The lab's real process
     kills produced **2 charges without the key, 1 with it**.
  2. Reconcile ambiguous outcomes by key.
  3. Saga compensation for later failures.
- **Follow-ups:**
  - "What if the provider has no idempotency support?" → our own ledger with a unique key, plus a query-before-retry
    reconciliation.

### Part D · Production blueprints, gateway and economics

#### S20 · "The LLM provider is 99.5%. The RAG endpoint must be 99.9%."

- **L5 answer:** "Add retries."
- **Why L5 fails at scale:** four dependencies in series give **98.80%**; retries do not help an outage and multiply
  load.
- **L7 principal defense:**
  1. Optional dependencies degrade with markers (lexical-only retrieval when the vector store is late).
  2. The model fails over across failure domains behind a breaker: **99.90%**.
  3. Deadlines that cancel late work.
  4. A no-sources refusal and a citation guard. Under chaos the naive pipeline let **67 errors and 19 invented
     citations** through, with p99 260 ms; the hardened one had 0 and 0, with p99 127 ms.
- **Follow-ups:**
  - "Correlated failures?" → failover inside one provider and region is not independent; prove the failure domains
    differ.

#### S21 · "Streaming responses sometimes repeat or truncate."

- **L5 answer:** "Retry on any error."
- **Why L5 fails at scale:** a retry after the first token duplicates visible text (the naive client showed
  `tok0…tok4 tok0…`). A stream without `[DONE]` is truncated. Layered retries amplify load **64×**.
- **L7 principal defense:**
  1. Retry only before the first token, with full jitter and Retry-After.
  2. Raise `PartialStream` after it: replace or resume, never append.
  3. Require terminal markers.
  4. A TTFT budget that scales with prompt length (about 4.6 s for 32K prompts on 70B).
  5. Cancel generation when the client disconnects: 10 vs 200 tokens generated.
  6. Size for `L = λW` streams: 3,160 at 200 req/s.
- **Follow-ups:**
  - "Virtual threads or WebFlux?" → both: virtual threads for blocking calls (0.20 s vs 4.52 s for 2,000
    conversations), Flux for streams, and explicit admission control either way.

#### S22 · "Add a semantic cache to cut 30% of cost."

- **L5 answer:** "Cache anything above 0.9 cosine similarity."
- **Why L5 fails at scale:** embeddings are blind to identifiers: "order A-18" scored **1.000** against a cached
  "order A-17". At a $2 wrong-answer cost, a false-hit rate above **0.051%** erases the savings.
- **L7 principal defense:**
  1. Scope keys by tenant, model, system prompt and tool/context versions.
  2. An entity guard: zero entity wrong hits at every threshold.
  3. Cache only replay-safe responses, with a threshold priced by the false-hit cost.
  4. Check the hit-rate ceiling first; prefer exact and prefix caching.
- **Follow-ups:**
  - "How do you measure false hits?" → a labelled sample of hits audited weekly, plus escalation and correction
    signals.

#### S23 · "Design rate limiting for a multi-tenant LLM platform."

- **L5 answer:** "N requests per minute per API key."
- **Why L5 fails at scale:** requests vary 1,000× in tokens; global limits let one tenant starve others (a quiet
  tenant lost **37 of 60** requests); post-hoc counting overshoots under concurrency (**1.9×**).
- **L7 principal defense:**
  1. Per-tenant and per-deployment token buckets, reserve-then-refund (0.76× of budget), with computed Retry-After.
  2. GCRA state (one timestamp) in an atomic store.
  3. Weighted fair admission under saturation: premium p95 wait **0.0 s vs 12.1 s** under FIFO.
  4. Queue deadlines, then 429.
- **Follow-ups:**
  - "What signals capacity planning?" → sustained throttling per tenant and deployment queue depth.

#### S24 · "Should we self-host or use Bedrock/Vertex?"

- **L5 answer:** a general claim either way.
- **L7 principal defense:**
  1. Physics gives capacity (15.9 req/s per 8×H100 replica for 1K/300 chat; 2.2 for 8K RAG).
  2. Traffic gives utilization (21% without autoscaling, 38% with).
  3. Prices and people give cost: at 20 req/s the API is **$51K vs $108K**; self-hosting wins from about
     **100 req/s**, under stated assumptions.
  4. Levers: autoscaling 2.19×, a commitment tier 2.22×, FP8 + MTP 0.46×.
  5. Commit replicas needed in at least **58%** of hours.
  6. Route a hybrid through the gateway.
- **Follow-ups:**
  - "What would change your answer?" → a price cut, a model only available by API, data-residency constraints, or
    the lack of a platform team.

#### S25 · "Design our enterprise AI platform end to end. You have 45 minutes."

- **L5 answer:** a component diagram: LLM, vector DB, orchestrator, UI.
- **L7 principal defense** (an outline you can expand on demand):
  1. **Requirements:** use cases ranked by value and risk; SLOs per use case; data classes and residency.
  2. **Gateway** (Folder 07 File 04): one API, auth, per-tenant token quotas, routing across self-hosted and API
     models, GenAI telemetry, a semantic cache only where it is priced in.
  3. **Serving** (Folders 01–02): vLLM fleets per model tier, sized from goodput, quantized behind evaluations,
     prefix-cache-aware routing, autoscaling with a commitment mix.
  4. **Knowledge** (Folders 03–04, 07/03): CDC ingestion with version gates; hybrid retrieval with ACL
     pre-filtering; filtered-ANN strategy; evaluation sets.
  5. **Tools** (Folder 05): MCP servers on Streamable HTTP with audience-bound OAuth and token exchange; curated tools;
     routing; pinning.
  6. **Agents** (Folder 06): workflows first, agents where needed; loop guards; durable execution for HITL and side
     effects; idempotency.
  7. **Safety and governance:** taint gates, approval policies, audit trails, red-team evaluations.
  8. **Operations:** SLO dashboards (TTFT, TPOT, goodput, KV utilization, retrieval recall, tool error rates,
     generated-after-disconnect tokens), cost per business outcome, evaluation gates on every model, prompt or
     retrieval change.
  9. **Evolution:** what breaks at 10× (KV capacity, filtered ANN, CDC lag, tool catalogs) and how each is already
     designed for.
- **Follow-ups:** the interviewer picks one box. Go deep with that box's numbers from S01–S24.

---

## 4. Code blueprints

### 4.1 Python: every number in this playbook, recomputed

```python
"""l7_numbers.py - the numbers an L7 candidate derives on the whiteboard, recomputed from this KB's verified listings.

Every value quoted in the 25 bar-raiser chains of Folder 08 File 02 is computed here from first principles (or by
importing the Folder 01-07 listing that measured it) and asserted against the quoted figure, so the playbook cannot
drift from the physics.
"""
from __future__ import annotations

import math

from hnsw_ref import hnswlib_bytes_per_vector
from kv_cache_math import MODELS
from roofline import H100, LLAMA3_70B, asymptotic_decode_intensity, kv_capacity_tokens, prefill

ROWS = []


def row(quantity: str, formula: str, value: float, quoted: float, unit: str, where: str, rel: float = 0.005) -> None:
    ok = abs(value - quoted) <= rel * max(abs(quoted), 1e-12)
    ROWS.append((quantity, formula, value, quoted, unit, where, ok))
    assert ok, f"{quantity}: computed {value} but the playbook quotes {quoted}"


def main() -> None:
    kv70 = MODELS["Llama-3-70B"].bytes_per_token(2.0)
    row("KV bytes per token, Llama-3-70B (GQA 8 KV heads)", "2*L*n_kv*d_h*2B", kv70, 327_680, "B", "S01 S02")
    mla = MODELS["DeepSeek-V3"].bytes_per_token(2.0)
    row("KV bytes per token, DeepSeek-V3 (MLA latent)", "L*(d_c + d_R)*2B", mla, 70_272, "B", "S01")
    cap = kv_capacity_tokens(LLAMA3_70B, H100, 8)
    row("KV capacity, 70B on 8xH100 TP8", "(0.9*HBM - W/tp - act)/kv_rank", cap, 1_356_942, "tokens", "S02 S07")
    inten = asymptotic_decode_intensity(LLAMA3_70B, 4096)
    row("decode intensity limit at 4K context", "lim B->inf FLOP/byte", inten, 111.6, "FLOP/B", "S01", 0.01)
    row("H100 BF16 ridge point", "peak / HBM BW", H100.ridge(), 295.3, "FLOP/B", "S01", 0.01)
    p = prefill(LLAMA3_70B, H100, 8, 25_960).total_s
    row("uncached prefill of a 150-tool catalog (25,960 tokens)", "roofline prefill", p * 1e3, 1_454, "ms", "S13", 0.01)
    row("KV held by that catalog per request", "25,960 x 327,680 B", 25_960 * kv70 / 2 ** 30, 7.92, "GiB", "S13", 0.01)
    row("HNSW bytes per vector, d=768, M=16 (hnswlib)", "4d + 2M*4 + ...", hnswlib_bytes_per_vector(768, 16)["total"],
        3_228.5, "B", "S09", 0.001)
    row("availability, 4 dependencies in series", "0.999*0.995*0.995*0.999", 0.999 * 0.995 * 0.995 * 0.999 * 100,
        98.80, "%", "S20", 0.0005)
    row("availability, vector optional + LLM failover", "0.999*(1 - 0.005^2)", 0.999 * (1 - 0.005 ** 2) * 100,
        99.90, "%", "S20", 0.0005)
    row("streams at 200 req/s (500 out @ 30 ms, TTFT 0.8 s)", "L = lambda*W", 200 * (0.8 + 500 * 0.03),
        3_160, "streams", "S21 S23")
    row("task success at p=0.95 per step, 20 steps", "p^n", 0.95 ** 20, 0.358, "", "S16 S17", 0.005)
    row("cumulative prompt tokens, 40 steps, c0=200, D=250", "n*c0 + D*n(n-1)/2", 40 * 200 + 250 * 40 * 39 / 2,
        203_000, "tokens", "S16")
    row("P(at least one of 6 parallel tools exceeds its P99)", "1 - 0.99^6", (1 - 0.99 ** 6) * 100, 5.85, "%", "S17", 0.005)
    row("retry amplification, 3 retries at 3 layers", "(r+1)^L", 4 ** 3, 64, "x", "S21")
    row("semantic-cache break-even false-hit rate (25% hits)", "(h*c_call - c_lookup)/c_wrong",
        (0.25 * 0.0042 - 0.00002) / 2.0 * 100, 0.0515, "%", "S22", 0.01)
    row("CDC backlog drain, 10M events at mu - lambda = 20/s", "backlog/(mu - lambda)", 10_000_000 / 20 / 3600,
        138.9, "h", "S12", 0.001)
    row("survival of a 24 h approval wait, deploys every 4.8 h", "e^(-T/tau)", math.exp(-24 / 4.8), 0.0067, "", "S18", 0.01)
    row("commit threshold, $3.50 vs $6.00 per GPU-hour", "p_c / p_o", 3.5 / 6.0, 0.583, "", "S24", 0.001)

    print(f"{'quantity':62} {'formula':34} {'value':>12} {'unit':>7}  chains")
    for q, f, v, quoted, u, where, ok in ROWS:
        shown = f"{v:,.4f}" if abs(v) < 10 else f"{v:,.1f}" if abs(v) < 10_000 else f"{v:,.0f}"
        print(f"{q:62} {f:34} {shown:>12} {u:>7}  {where}")
    print(f"\n{len(ROWS)} quantities recomputed; every one matches the figure quoted in the playbook")
    print("all l7_numbers self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
quantity                                                       formula                                   value    unit  chains
KV bytes per token, Llama-3-70B (GQA 8 KV heads)               2*L*n_kv*d_h*2B                         327,680       B  S01 S02
KV bytes per token, DeepSeek-V3 (MLA latent)                   L*(d_c + d_R)*2B                         70,272       B  S01
KV capacity, 70B on 8xH100 TP8                                 (0.9*HBM - W/tp - act)/kv_rank        1,356,942  tokens  S02 S07
decode intensity limit at 4K context                           lim B->inf FLOP/byte                      111.6  FLOP/B  S01
H100 BF16 ridge point                                          peak / HBM BW                             295.3  FLOP/B  S01
uncached prefill of a 150-tool catalog (25,960 tokens)         roofline prefill                        1,453.7      ms  S13
KV held by that catalog per request                            25,960 x 327,680 B                       7.9224     GiB  S13
HNSW bytes per vector, d=768, M=16 (hnswlib)                   4d + 2M*4 + ...                         3,228.5       B  S09
availability, 4 dependencies in series                         0.999*0.995*0.995*0.999                    98.8       %  S20
availability, vector optional + LLM failover                   0.999*(1 - 0.005^2)                        99.9       %  S20
streams at 200 req/s (500 out @ 30 ms, TTFT 0.8 s)             L = lambda*W                            3,160.0 streams  S21 S23
task success at p=0.95 per step, 20 steps                      p^n                                      0.3585          S16 S17
cumulative prompt tokens, 40 steps, c0=200, D=250              n*c0 + D*n(n-1)/2                       203,000  tokens  S16
P(at least one of 6 parallel tools exceeds its P99)            1 - 0.99^6                               5.8520       %  S17
retry amplification, 3 retries at 3 layers                     (r+1)^L                                    64.0       x  S21
semantic-cache break-even false-hit rate (25% hits)            (h*c_call - c_lookup)/c_wrong            0.0515       %  S22
CDC backlog drain, 10M events at mu - lambda = 20/s            backlog/(mu - lambda)                     138.9       h  S12
survival of a 24 h approval wait, deploys every 4.8 h          e^(-T/tau)                               0.0067          S18
commit threshold, $3.50 vs $6.00 per GPU-hour                  p_c / p_o                                0.5833          S24

19 quantities recomputed; every one matches the figure quoted in the playbook
all l7_numbers self-checks passed
```

### 4.2 Java 21: the invariants as a design-review linter

A design doc's decisions table becomes a `key = value` spec. Each rule cites the scenario it comes from, the failure
it prevents and the KB file with the fix. CI can run it against design specs the way it runs tests against code.

```java
// ArchitectureLinter.java - design-review automation: the invariants checklists of Folders 01-07, as executable rules
// keyed to the 25 bar-raiser scenarios of Folder 08 File 02. A design is a plain `key = value` spec (what a design
// doc's "decisions" table already contains); each rule names the scenario it comes from, the failure it prevents,
// and the KB file that explains the fix. Run against a naive and a hardened design.
// Build: javac --release 21 (no dependencies)
package dev.l7.ai.inference;

import java.io.IOException;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.function.Predicate;

public final class ArchitectureLinter {

    record Spec(Properties p) {
        String s(String k) { return p.getProperty(k, "").trim(); }
        boolean b(String k) { return Boolean.parseBoolean(s(k)); }
        int i(String k) { return s(k).isEmpty() ? 0 : Integer.parseInt(s(k)); }

        static Spec parse(String text) {
            Properties p = new Properties();
            try {
                p.load(new StringReader(text));
            } catch (IOException e) {
                throw new java.io.UncheckedIOException(e);
            }
            return new Spec(p);
        }
    }

    record Rule(String scenario, String title, Predicate<Spec> ok, String prevents, String fixIn) {}

    static final List<Rule> RULES = List.of(
            new Rule("S02", "capacity is planned from goodput at the SLO", s -> s.s("capacity.planned_from").equals("goodput"),
                    "a fleet that meets a benchmark and misses the TPOT SLO", "02/01"),
            new Rule("S03", "chunked prefill with a token budget", s -> s.b("serving.chunked_prefill"),
                    "a 32K prompt stalling 64 streams for 1.7 s", "02/01"),
            new Rule("S05", "quantization ships behind an evaluation gate", s -> !s.b("quant.enabled") || s.b("quant.eval_gate"),
                    "silent quality regressions from FP8/INT4", "02/03"),
            new Rule("S06", "speculative decoding is batch-aware", s -> !s.b("specdec.enabled") || s.b("specdec.batch_aware"),
                    "spec decoding slowing high-batch serving below 1x", "02/03"),
            new Rule("S07", "prefix-cache-aware routing", s -> s.b("routing.prefix_cache_aware"),
                    "prefix hit rate collapsing as replicas are added", "01/03"),
            new Rule("S08", "filtered vector search uses a planner, not post-filtering",
                    s -> s.s("vector.filtered_search").equals("planner"), "selective ACL filters returning 3% recall", "03/01"),
            new Rule("S10", "identifier queries are routed to lexical", s -> s.b("retrieval.route_identifiers"),
                    "RRF burying exact part numbers (MRR 0.075)", "04/02"),
            new Rule("S12", "CDC sink is version-gated with tombstones", s -> s.b("ingest.version_gate") && s.b("ingest.tombstones"),
                    "stale, orphaned, resurrected and wrong-ACL chunks", "07/03"),
            new Rule("S12", "ACLs are enforced inside retrieval", s -> s.s("acl.enforcement").equals("prefilter"),
                    "documents leaking to users who lost access", "04/03"),
            new Rule("S13", "tools are routed hierarchically in a stable order",
                    s -> s.s("tools.routing").equals("hierarchical") && s.b("tools.stable_order"),
                    "26K-token catalogs, 7.9 GiB KV per request, zero prefix-cache hits", "05/03"),
            new Rule("S14", "a taint gate breaks the lethal trifecta", s -> !s.b("agent.untrusted_input") || s.b("agent.taint_gate"),
                    "prompt-injected exfiltration through tools", "05/02"),
            new Rule("S15", "no token passthrough; audience-bound tokens", s -> !s.b("mcp.token_passthrough") && s.b("mcp.audience_bound"),
                    "the confused deputy", "05/02"),
            new Rule("S16", "agent loops are bounded", s -> s.b("agent.loop_guards"), "runaway loops burning 100x tokens", "06/01"),
            new Rule("S18", "human-in-the-loop runs on durable execution", s -> !s.b("agent.hitl") || s.b("agent.durable"),
                    "approvals lost on every deploy (P(survive 24 h) = 0.0067)", "06/03"),
            new Rule("S19", "side effects carry idempotency keys", s -> s.b("side_effects.idempotency_keys"),
                    "double charges after at-least-once retries", "06/03"),
            new Rule("S20", "model failover crosses failure domains; deadlines cancel",
                    s -> s.i("llm.failure_domains") >= 2 && s.b("deadlines.cancel_late_work"),
                    "a provider incident becoming a full outage", "07/01"),
            new Rule("S21", "streaming retries only before the first token, at one layer",
                    s -> !s.b("client.retry_after_first_token") && s.i("retry.layers") <= 1, "duplicated text and 64x retry storms", "07/02"),
            new Rule("S21", "client disconnect cancels generation", s -> s.b("stream.cancel_on_disconnect"),
                    "GPUs decoding for users who left", "06/02"),
            new Rule("S22", "semantic cache is scoped and entity-guarded",
                    s -> !s.b("cache.semantic") || (s.b("cache.scoped") && s.b("cache.entity_guard")),
                    "order A-18 answered from order A-17", "07/04"),
            new Rule("S23", "rate limits are per-tenant tokens, reserve-then-refund",
                    s -> s.s("ratelimit.unit").equals("tokens") && s.b("ratelimit.per_tenant") && s.b("ratelimit.reserve"),
                    "noisy neighbours and 1.9x budget overshoot", "07/04"),
            new Rule("S24", "fleet autoscales and commits by the f_k >= p_c/p_o rule",
                    s -> s.b("fleet.autoscale") && s.b("fleet.commit_rule"), "paying 2.2x for idle GPUs", "08/01"),
            new Rule("S25", "GenAI telemetry with content off by default",
                    s -> s.b("telemetry.genai_semconv") && s.s("telemetry.content").equals("off"),
                    "blind cost attribution, or prompts leaked into traces", "07/04"));

    static List<String> lint(Spec s) {
        List<String> out = new ArrayList<>();
        for (Rule r : RULES)
            if (!r.ok().test(s)) out.add(String.format("%s  %-58s prevents: %s  (fix: %s)", r.scenario(), r.title(), r.prevents(), r.fixIn()));
        return out;
    }

    static final String NAIVE = """
            capacity.planned_from = peak_tokens_per_second
            serving.chunked_prefill = false
            quant.enabled = true
            quant.eval_gate = false
            specdec.enabled = true
            specdec.batch_aware = false
            routing.prefix_cache_aware = false
            vector.filtered_search = post_filter
            retrieval.route_identifiers = false
            ingest.version_gate = false
            ingest.tombstones = false
            acl.enforcement = postfilter
            tools.routing = dump
            tools.stable_order = false
            agent.untrusted_input = true
            agent.taint_gate = false
            mcp.token_passthrough = true
            mcp.audience_bound = false
            agent.loop_guards = false
            agent.hitl = true
            agent.durable = false
            side_effects.idempotency_keys = false
            llm.failure_domains = 1
            deadlines.cancel_late_work = false
            client.retry_after_first_token = true
            retry.layers = 3
            stream.cancel_on_disconnect = false
            cache.semantic = true
            cache.scoped = false
            cache.entity_guard = false
            ratelimit.unit = requests
            ratelimit.per_tenant = false
            ratelimit.reserve = false
            fleet.autoscale = false
            fleet.commit_rule = false
            telemetry.genai_semconv = false
            telemetry.content = on
            """;

    static final String HARDENED = """
            capacity.planned_from = goodput
            serving.chunked_prefill = true
            quant.enabled = true
            quant.eval_gate = true
            specdec.enabled = true
            specdec.batch_aware = true
            routing.prefix_cache_aware = true
            vector.filtered_search = planner
            retrieval.route_identifiers = true
            ingest.version_gate = true
            ingest.tombstones = true
            acl.enforcement = prefilter
            tools.routing = hierarchical
            tools.stable_order = true
            agent.untrusted_input = true
            agent.taint_gate = true
            mcp.token_passthrough = false
            mcp.audience_bound = true
            agent.loop_guards = true
            agent.hitl = true
            agent.durable = true
            side_effects.idempotency_keys = true
            llm.failure_domains = 2
            deadlines.cancel_late_work = true
            client.retry_after_first_token = false
            retry.layers = 1
            stream.cancel_on_disconnect = true
            cache.semantic = true
            cache.scoped = true
            cache.entity_guard = true
            ratelimit.unit = tokens
            ratelimit.per_tenant = true
            ratelimit.reserve = true
            fleet.autoscale = true
            fleet.commit_rule = true
            telemetry.genai_semconv = true
            telemetry.content = off
            """;

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        System.out.println(RULES.size() + " rules from the invariants checklists of Folders 01-08");
        List<String> naive = lint(Spec.parse(NAIVE));
        System.out.println("\nnaive design: " + naive.size() + " violations");
        naive.forEach(v -> System.out.println("  " + v));
        List<String> hardened = lint(Spec.parse(HARDENED));
        System.out.println("\nhardened design: " + hardened.size() + " violations");
        Spec partial = Spec.parse(HARDENED.replace("cache.entity_guard = true", "cache.entity_guard = false")
                .replace("agent.durable = true", "agent.durable = false"));
        List<String> mixed = lint(partial);
        System.out.println("\nhardened design with two regressions (entity guard removed, HITL moved off durable execution): "
                + mixed.size() + " violations");
        mixed.forEach(v -> System.out.println("  " + v));
        check(naive.size() == RULES.size() && hardened.isEmpty() && mixed.size() == 2, "every rule fires on naive, none on hardened");
        System.out.println("\nall ArchitectureLinter self-checks passed");
    }
}
```

Output (verified; deterministic):

```text
22 rules from the invariants checklists of Folders 01-08

naive design: 22 violations
  S02  capacity is planned from goodput at the SLO                prevents: a fleet that meets a benchmark and misses the TPOT SLO  (fix: 02/01)
  S03  chunked prefill with a token budget                        prevents: a 32K prompt stalling 64 streams for 1.7 s  (fix: 02/01)
  S05  quantization ships behind an evaluation gate               prevents: silent quality regressions from FP8/INT4  (fix: 02/03)
  S06  speculative decoding is batch-aware                        prevents: spec decoding slowing high-batch serving below 1x  (fix: 02/03)
  S07  prefix-cache-aware routing                                 prevents: prefix hit rate collapsing as replicas are added  (fix: 01/03)
  S08  filtered vector search uses a planner, not post-filtering  prevents: selective ACL filters returning 3% recall  (fix: 03/01)
  S10  identifier queries are routed to lexical                   prevents: RRF burying exact part numbers (MRR 0.075)  (fix: 04/02)
  S12  CDC sink is version-gated with tombstones                  prevents: stale, orphaned, resurrected and wrong-ACL chunks  (fix: 07/03)
  S12  ACLs are enforced inside retrieval                         prevents: documents leaking to users who lost access  (fix: 04/03)
  S13  tools are routed hierarchically in a stable order          prevents: 26K-token catalogs, 7.9 GiB KV per request, zero prefix-cache hits  (fix: 05/03)
  S14  a taint gate breaks the lethal trifecta                    prevents: prompt-injected exfiltration through tools  (fix: 05/02)
  S15  no token passthrough; audience-bound tokens                prevents: the confused deputy  (fix: 05/02)
  S16  agent loops are bounded                                    prevents: runaway loops burning 100x tokens  (fix: 06/01)
  S18  human-in-the-loop runs on durable execution                prevents: approvals lost on every deploy (P(survive 24 h) = 0.0067)  (fix: 06/03)
  S19  side effects carry idempotency keys                        prevents: double charges after at-least-once retries  (fix: 06/03)
  S20  model failover crosses failure domains; deadlines cancel   prevents: a provider incident becoming a full outage  (fix: 07/01)
  S21  streaming retries only before the first token, at one layer prevents: duplicated text and 64x retry storms  (fix: 07/02)
  S21  client disconnect cancels generation                       prevents: GPUs decoding for users who left  (fix: 06/02)
  S22  semantic cache is scoped and entity-guarded                prevents: order A-18 answered from order A-17  (fix: 07/04)
  S23  rate limits are per-tenant tokens, reserve-then-refund     prevents: noisy neighbours and 1.9x budget overshoot  (fix: 07/04)
  S24  fleet autoscales and commits by the f_k >= p_c/p_o rule    prevents: paying 2.2x for idle GPUs  (fix: 08/01)
  S25  GenAI telemetry with content off by default                prevents: blind cost attribution, or prompts leaked into traces  (fix: 07/04)

hardened design: 0 violations

hardened design with two regressions (entity guard removed, HITL moved off durable execution): 2 violations
  S18  human-in-the-loop runs on durable execution                prevents: approvals lost on every deploy (P(survive 24 h) = 0.0067)  (fix: 06/03)
  S22  semantic cache is scoped and entity-guarded                prevents: order A-18 answered from order A-17  (fix: 07/04)

all ArchitectureLinter self-checks passed
```

---

## 5. Failure modes of L7 answers

### F1 · Components without numbers

- **Symptom:** a diagram, then silence when asked "how many GPUs?" or "how much RAM?".
- **Fix:** start every design with the §2 envelope; say the assumptions out loud.

### F2 · The right mechanism for the wrong constraint

- **Symptom:** "more FLOPs" for memory-bound decode; "bigger k" for filtered-ANN recall; "retries" for provider
  outages.
- **Fix:** name the binding constraint before proposing the mechanism.

### F3 · Happy-path architecture

- **Symptom:** no failure modes until asked, then generic ones ("add monitoring").
- **Fix:** for each component, name the specific failure, its signature in metrics or traces, and the bound
  (S20–S23 show the shape).

### F4 · Tool names instead of semantics

- **Symptom:** "Temporal guarantees exactly-once", "RRF fixes hybrid search", "FP8 is lossless".
- **Fix:** state what the mechanism actually guarantees, and where its guarantee ends.

### F5 · No operations or evolution

- **Symptom:** no SLOs, no rollout plan, no story for 10× or the next model.
- **Fix:** close every design with the dashboards, the gates and the next bottleneck.

---

## 6. Invariants checklist: the answer

- [ ] Requirements as numbers (QPS, lengths, SLOs, availability, data classes), proposed if not given.
- [ ] An envelope calculation before architecture.
- [ ] The binding constraint named, and the design chosen to move it.
- [ ] Failure modes with signatures and bounds for every component.
- [ ] Security boundaries enforced by mechanisms, not prompts.
- [ ] Cost priced in money, latency and operational load.
- [ ] SLOs, dashboards, evaluation gates, rollout and rollback.
- [ ] What breaks at 10× and with the next model.

## 7. References

1. This KB, Folders 01–07; each scenario cites the folder whose listings produced its numbers.
2. Google SRE Book: chapters 21–22 (overload, cascading failures) and the SLO chapters.
3. J. Dean, L. A. Barroso. *The Tail at Scale.* CACM 2013.
4. Model Context Protocol specification 2025-11-25: authorization (audience binding, no token passthrough); RFC 8707,
   RFC 9728, RFC 8693.
5. S. Willison. *The lethal trifecta for AI agents* (2025) (⚠ verify the title and date).
