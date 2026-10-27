# 03 · The Curated Reading List: Papers, Specifications and Repositories, Each Link Verified

> **Folder:** `08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/` · **File 3 of 3**
> **What this is:** 60 primary sources behind Folders 01–07. Each entry says what to extract and which KB file
> exercises it. Every URL was fetched one at a time on **2026-10-27** by `verify_reading_list.py` (§3): HTTP 200
> after redirects, and the expected keywords in the page title. Rerun it before relying on the list.
> **Code baseline:** Python 3.10+ (stdlib `urllib`).
> **Previous:** [02 · 25 bar-raiser scenarios](02-twenty-five-l7-bar-raiser-scenarios-with-l5-vs-l7-defenses.md) ·
> **Back to:** [the KB README](../README.md)

---

## 0. The thesis in one paragraph

A principal engineer's reading is selective and operational: read the paper that **defines the mechanism**, the
specification that **defines the contract**, and the repository that **defines the behaviour you will actually
run**. Read each with one question: what number or invariant does this give me?

The verification run found that sources move, which is itself a lesson:

- the OpenTelemetry GenAI conventions page now redirects readers to a **separate repository**;
- the SRE book's overload chapter is now titled after **client-side throttling**;
- a classic paper's institutional archive sat behind **TLS and bot walls** and had to be replaced by a verifiable
  source.

Treat links like dependencies: pinned, checked and replaceable.

---

## 1. How to read for L7

1. **Mechanism papers.** Find the cost model: what grows with batch, context, k or selectivity. Reproduce one figure
   with a back-of-envelope calculation before reading the evaluation.
2. **Specifications** (MCP, RFCs, OpenTelemetry). Read the MUST and MUST NOT lines and the error model; that is where
   production incidents come from.
3. **Repositories.** Read the scheduler, the configuration defaults and the changelog. Defaults change behaviour
   between minor versions (Folder 06 File 02 found deprecations and silent behaviours by compiling against the jars).
4. **Order.** Folder 01's physics first, because everything else is priced in those units.

---

## 2. The list

### 2.1 Folder 01 · Inference physics and the KV cache

| Source | Extract | Used in |
|---|---|---|
| [Williams, Waterman, Patterson. *Roofline* (UC Berkeley TR, 2008)](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2008/EECS-2008-134.html) | arithmetic intensity vs ridge point; reading kernels as memory- or compute-bound | 01/01 |
| [Pope et al. *Efficiently Scaling Transformer Inference* (2022)](https://arxiv.org/abs/2211.05102) | partitioning, latency vs throughput, KV memory at scale | 01/01, 02/03 |
| [Ainslie et al. *GQA* (2023)](https://arxiv.org/abs/2305.13245) | KV heads as the memory lever: 327,680 B/token for 70B | 01/02 |
| [DeepSeek-AI. *DeepSeek-V2* (2024)](https://arxiv.org/abs/2405.04434) | Multi-head Latent Attention: a compressed latent KV with decoupled RoPE | 01/02 |
| [Dao et al. *FlashAttention* (2022)](https://arxiv.org/abs/2205.14135) | IO-aware tiling; why attention is memory-bound without it | 01/02 |
| [Dao. *FlashAttention-2* (2023)](https://arxiv.org/abs/2307.08691) | work partitioning and parallelism on modern GPUs | 01/02 |
| [Kwon et al. *PagedAttention / vLLM* (SOSP 2023)](https://arxiv.org/abs/2309.06180) | block tables, fragmentation, copy-on-write sharing | 01/03 |
| [Zheng et al. *SGLang / RadixAttention* (2023)](https://arxiv.org/abs/2312.07104) | prefix trees, LRU over the radix tree, cache-aware scheduling | 01/03 |

### 2.2 Folder 02 · High-throughput serving

| Source | Extract | Used in |
|---|---|---|
| [Yu et al. *Orca* (OSDI 2022)](https://www.usenix.org/conference/osdi22/presentation/yu) | iteration-level scheduling (continuous batching) | 02/01 |
| [Agrawal et al. *Sarathi-Serve* (2024)](https://arxiv.org/abs/2403.02310) | chunked prefill and stall-free batching; the token budget | 02/01 |
| [Zhong et al. *DistServe* (2024)](https://arxiv.org/abs/2401.09670) | goodput under SLOs; prefill/decode disaggregation | 02/02 |
| [Patel et al. *Splitwise* (2023)](https://arxiv.org/abs/2311.18677) | phase splitting across heterogeneous hardware; KV transfer | 02/02 |
| [Leviathan et al. *Speculative Decoding* (2022)](https://arxiv.org/abs/2211.17192) | lossless rejection sampling; expected tokens per step | 02/03 |
| [Li et al. *EAGLE* (2024)](https://arxiv.org/abs/2401.15077) | feature-level drafting; cheap drafters | 02/03 |
| [Xiao et al. *SmoothQuant* (2022)](https://arxiv.org/abs/2211.10438) | migrating activation outliers into weights | 02/03 |
| [Lin et al. *AWQ* (2023)](https://arxiv.org/abs/2306.00978) | activation-aware weight scaling for low-bit weights | 02/03 |
| [DeepSeek-AI. *DeepSeek-V3 Technical Report* (2024)](https://arxiv.org/abs/2412.19437) | MLA at scale, MoE serving, FP8 training/inference, multi-token prediction | 01/02, 02/03 |
| [vLLM](https://github.com/vllm-project/vllm) · [SGLang](https://github.com/sgl-project/sglang) · [TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM) | scheduler, KV manager, prefix caching, quantization paths: the behaviour you run | Folders 01–02 |

### 2.3 Folder 03 · Vector search internals

| Source | Extract | Used in |
|---|---|---|
| [Malkov, Yashunin. *HNSW* (2016)](https://arxiv.org/abs/1603.09320) | layer probability, the neighbour-selection heuristic, memory per element | 03/01 |
| [Patel et al. *ACORN* (2024)](https://arxiv.org/abs/2403.04871) | predicate-agnostic filtered search; two-hop expansion | 03/01 |
| [Douze et al. *The Faiss library* (2024)](https://arxiv.org/abs/2401.08281) | PQ, IVF and HNSW trade-offs in one framework (Jégou et al.'s 2011 PQ paper is the original; its archive link failed verification) | 03/02, 03/03 |
| [DiskANN](https://github.com/microsoft/DiskANN) · [hnswlib](https://github.com/nmslib/hnswlib) · [Faiss](https://github.com/facebookresearch/faiss) · [pgvector](https://github.com/pgvector/pgvector) | Vamana and beam search on SSD; the exact HNSW memory layout; IVF-PQ; HNSW and iterative scans in Postgres | 03/01–03, 07/03 |

### 2.4 Folder 04 · Enterprise RAG

| Source | Extract | Used in |
|---|---|---|
| [Lewis et al. *Retrieval-Augmented Generation* (2020)](https://arxiv.org/abs/2005.11401) | the retrieve-then-generate formulation | 04/01 |
| [Khattab, Zaharia. *ColBERT* (2020)](https://arxiv.org/abs/2004.12832) | late interaction and MaxSim | 04/01 |
| [Formal et al. *SPLADE* (2021)](https://arxiv.org/abs/2107.05720) | learned sparse retrieval | 04/02 |
| [Cormack, Clarke, Büttcher. *Reciprocal Rank Fusion* (SIGIR 2009)](https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf) | `1/(k + r)`; why it discards score gaps | 04/02, 07/03 |
| [Günther et al. *Late Chunking* (2024)](https://arxiv.org/abs/2409.04701) | embedding the document first, pooling per chunk | 04/01 |
| [Anthropic. *Contextual Retrieval* (2024)](https://www.anthropic.com/news/contextual-retrieval) | chunk-specific context prepended before embedding and BM25 | 04/01 |
| [Edge et al. *GraphRAG* (2024)](https://arxiv.org/abs/2404.16130) | community summaries for global questions | 04/03 |
| [Liu et al. *Lost in the Middle* (2023)](https://arxiv.org/abs/2307.03172) | position effects in long contexts | 04/02, 06/01 |

### 2.5 Folder 05 · Model Context Protocol and security

| Source | Extract | Used in |
|---|---|---|
| [MCP specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25) | lifecycle, transports, tools and `isError`, authorization (no token passthrough) | 05/01–03 |
| [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) · [MCP Java SDK](https://github.com/modelcontextprotocol/java-sdk) | `MCPServer`, the 2026-07-28 envelope, error semantics (they differ: 07/01 vs 07/02) | 05/01, 07/01–02 |
| [RFC 8693 *Token Exchange*](https://www.rfc-editor.org/rfc/rfc8693) · [RFC 8707 *Resource Indicators*](https://www.rfc-editor.org/rfc/rfc8707) · [RFC 9728 *Protected Resource Metadata*](https://www.rfc-editor.org/rfc/rfc9728) | audience binding, delegation with `act`, discovery | 05/02 |
| [Greshake et al. *Indirect Prompt Injection* (2023)](https://arxiv.org/abs/2302.12173) | injection through retrieved and tool content | 05/02 |
| [Willison. *The lethal trifecta for AI agents* (2025)](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) | private data + untrusted content + exfiltration = breach | 05/02, 08/02 S14 |
| [Gan, Sun. *RAG-MCP* (2025)](https://arxiv.org/abs/2505.03275) | retrieval over tool catalogs against prompt bloat | 05/03 |

### 2.6 Folder 06 · Agents and durable execution

| Source | Extract | Used in |
|---|---|---|
| [Yao et al. *ReAct* (2022)](https://arxiv.org/abs/2210.03629) | interleaved reasoning and acting | 06/01 |
| [Xu et al. *ReWOO* (2023)](https://arxiv.org/abs/2305.18323) | planning without observations; token savings | 06/01 |
| [Kim et al. *LLMCompiler* (2023)](https://arxiv.org/abs/2312.04511) | DAG planning, parallel function calling, the joiner | 06/01 |
| [Shinn et al. *Reflexion* (2023)](https://arxiv.org/abs/2303.11366) · [Madaan et al. *Self-Refine* (2023)](https://arxiv.org/abs/2303.17651) | reflection loops and their stop conditions | 06/01 |
| [Huang et al. *LLMs Cannot Self-Correct Reasoning Yet* (2023)](https://arxiv.org/abs/2310.01798) | why reflection needs external signals | 06/01 |
| [Anthropic. *Building effective agents* (2024)](https://www.anthropic.com/engineering/building-effective-agents) | workflows vs agents; the composable patterns | 06/01 |
| [LangGraph](https://github.com/langchain-ai/langgraph) · [Temporal Java SDK](https://github.com/temporalio/sdk-java) · [Spring AI](https://github.com/spring-projects/spring-ai) · [LangChain4j](https://github.com/langchain4j/langchain4j) | checkpointers and `interrupt`; replay and versioning; advisors and tool calling; AI services | 06/02–03, 07/01–02 |

### 2.7 Folder 07 · Production blueprints

| Source | Extract | Used in |
|---|---|---|
| [OpenTelemetry GenAI semantic conventions (own repository since semconv 1.44)](https://github.com/open-telemetry/semantic-conventions-genai) | `gen_ai.*` span attributes, token and duration metrics, opt-in content | 07/04 |
| [Brooker. *Exponential Backoff and Jitter*](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/) | full jitter; why synchronized retries make waves | 07/02 |
| [Google SRE Book: *Handling Overload* (client-side throttling)](https://sre.google/sre-book/handling-overload/) · [*Addressing Cascading Failures*](https://sre.google/sre-book/addressing-cascading-failures/) | per-customer quotas, retry budgets, deadline propagation | 07/01–04 |
| [Dean, Barroso. *The Tail at Scale* (CACM 2013)](https://research.google/pubs/the-tail-at-scale/) | fan-out tails, hedged requests | 06/01, 07/01 |

---

## 3. The verification listing

```python
"""verify_reading_list.py - the curated reading list as data, verified one URL at a time (stdlib only).

Each entry is fetched sequentially (never in parallel), redirects are followed, and the entry passes only if the
final response is HTTP 200 AND every expected keyword appears in the page's <title> (or, for pages without a useful
title, in the first 400 KB of the body). A link rot check you can rerun before an interview loop or a design review.
"""
from __future__ import annotations

import html
import re
import sys
import time
import urllib.error
import urllib.request

# (section, label, url, keywords that must appear in the title/body, case-insensitive)
READING = [
    ("01 inference physics", "Williams, Waterman, Patterson - Roofline (UCB TR 2008)",
     "https://www2.eecs.berkeley.edu/Pubs/TechRpts/2008/EECS-2008-134.html", ["roofline"]),
    ("01 inference physics", "Pope et al. - Efficiently Scaling Transformer Inference", "https://arxiv.org/abs/2211.05102",
     ["efficiently scaling transformer inference"]),
    ("01 inference physics", "Ainslie et al. - GQA", "https://arxiv.org/abs/2305.13245", ["gqa"]),
    ("01 inference physics", "DeepSeek-V2 (Multi-head Latent Attention)", "https://arxiv.org/abs/2405.04434", ["deepseek-v2"]),
    ("01 inference physics", "Dao et al. - FlashAttention", "https://arxiv.org/abs/2205.14135", ["flashattention"]),
    ("01 inference physics", "Dao - FlashAttention-2", "https://arxiv.org/abs/2307.08691", ["flashattention-2"]),
    ("01 inference physics", "Kwon et al. - PagedAttention / vLLM (SOSP 2023)", "https://arxiv.org/abs/2309.06180", ["pagedattention"]),
    ("01 inference physics", "Zheng et al. - SGLang / RadixAttention", "https://arxiv.org/abs/2312.07104", ["sglang"]),
    ("02 serving", "Yu et al. - Orca (OSDI 2022)", "https://www.usenix.org/conference/osdi22/presentation/yu", ["orca"]),
    ("02 serving", "Agrawal et al. - Sarathi-Serve (chunked prefill)", "https://arxiv.org/abs/2403.02310", ["sarathi-serve"]),
    ("02 serving", "Zhong et al. - DistServe", "https://arxiv.org/abs/2401.09670", ["distserve"]),
    ("02 serving", "Patel et al. - Splitwise", "https://arxiv.org/abs/2311.18677", ["splitwise"]),
    ("02 serving", "Leviathan et al. - Speculative Decoding", "https://arxiv.org/abs/2211.17192", ["speculative decoding"]),
    ("02 serving", "Li et al. - EAGLE", "https://arxiv.org/abs/2401.15077", ["eagle"]),
    ("02 serving", "Xiao et al. - SmoothQuant", "https://arxiv.org/abs/2211.10438", ["smoothquant"]),
    ("02 serving", "Lin et al. - AWQ", "https://arxiv.org/abs/2306.00978", ["awq"]),
    ("02 serving", "DeepSeek-V3 Technical Report", "https://arxiv.org/abs/2412.19437", ["deepseek-v3"]),
    ("02 serving", "vLLM", "https://github.com/vllm-project/vllm", ["vllm"]),
    ("02 serving", "SGLang", "https://github.com/sgl-project/sglang", ["sglang"]),
    ("02 serving", "TensorRT-LLM", "https://github.com/NVIDIA/TensorRT-LLM", ["tensorrt-llm"]),
    ("03 vector search", "Malkov, Yashunin - HNSW", "https://arxiv.org/abs/1603.09320", ["hierarchical navigable small world"]),
    ("03 vector search", "Douze et al. - The Faiss library (PQ, IVF, HNSW in one framework)",
     "https://arxiv.org/abs/2401.08281", ["faiss library"]),
    ("03 vector search", "Patel et al. - ACORN (filtered ANN)", "https://arxiv.org/abs/2403.04871", ["acorn"]),
    ("03 vector search", "DiskANN", "https://github.com/microsoft/DiskANN", ["diskann"]),
    ("03 vector search", "hnswlib", "https://github.com/nmslib/hnswlib", ["hnswlib"]),
    ("03 vector search", "Faiss", "https://github.com/facebookresearch/faiss", ["faiss"]),
    ("03 vector search", "pgvector", "https://github.com/pgvector/pgvector", ["pgvector"]),
    ("04 RAG", "Lewis et al. - Retrieval-Augmented Generation", "https://arxiv.org/abs/2005.11401", ["retrieval-augmented generation"]),
    ("04 RAG", "Khattab, Zaharia - ColBERT", "https://arxiv.org/abs/2004.12832", ["colbert"]),
    ("04 RAG", "Formal et al. - SPLADE", "https://arxiv.org/abs/2107.05720", ["splade"]),
    ("04 RAG", "Cormack, Clarke, Buettcher - Reciprocal Rank Fusion (SIGIR 2009)",
     "https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf", ["reciprocal rank fusion"]),
    ("04 RAG", "Guenther et al. - Late Chunking", "https://arxiv.org/abs/2409.04701", ["late chunking"]),
    ("04 RAG", "Anthropic - Contextual Retrieval", "https://www.anthropic.com/news/contextual-retrieval", ["contextual retrieval"]),
    ("04 RAG", "Edge et al. - GraphRAG", "https://arxiv.org/abs/2404.16130", ["graph rag"]),
    ("04 RAG", "Liu et al. - Lost in the Middle", "https://arxiv.org/abs/2307.03172", ["lost in the middle"]),
    ("05 MCP", "Model Context Protocol specification (2025-11-25)",
     "https://modelcontextprotocol.io/specification/2025-11-25", ["specification"]),
    ("05 MCP", "MCP Python SDK", "https://github.com/modelcontextprotocol/python-sdk", ["python-sdk"]),
    ("05 MCP", "MCP Java SDK", "https://github.com/modelcontextprotocol/java-sdk", ["java-sdk"]),
    ("05 MCP", "RFC 8693 - OAuth 2.0 Token Exchange", "https://www.rfc-editor.org/rfc/rfc8693", ["token exchange"]),
    ("05 MCP", "RFC 8707 - Resource Indicators for OAuth 2.0", "https://www.rfc-editor.org/rfc/rfc8707", ["resource indicators"]),
    ("05 MCP", "RFC 9728 - OAuth 2.0 Protected Resource Metadata", "https://www.rfc-editor.org/rfc/rfc9728",
     ["protected resource metadata"]),
    ("05 MCP", "Greshake et al. - Indirect Prompt Injection", "https://arxiv.org/abs/2302.12173", ["indirect prompt injection"]),
    ("05 MCP", "Willison - The lethal trifecta for AI agents", "https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/",
     ["lethal trifecta"]),
    ("05 MCP", "Gan, Sun - RAG-MCP", "https://arxiv.org/abs/2505.03275", ["rag-mcp"]),
    ("06 agents", "Yao et al. - ReAct", "https://arxiv.org/abs/2210.03629", ["react"]),
    ("06 agents", "Xu et al. - ReWOO", "https://arxiv.org/abs/2305.18323", ["rewoo"]),
    ("06 agents", "Kim et al. - LLMCompiler", "https://arxiv.org/abs/2312.04511", ["llm compiler"]),
    ("06 agents", "Shinn et al. - Reflexion", "https://arxiv.org/abs/2303.11366", ["reflexion"]),
    ("06 agents", "Madaan et al. - Self-Refine", "https://arxiv.org/abs/2303.17651", ["self-refine"]),
    ("06 agents", "Huang et al. - LLMs Cannot Self-Correct Reasoning Yet", "https://arxiv.org/abs/2310.01798",
     ["cannot self-correct"]),
    ("06 agents", "Anthropic - Building effective agents", "https://www.anthropic.com/engineering/building-effective-agents",
     ["building effective", "agents"]),
    ("06 agents", "LangGraph", "https://github.com/langchain-ai/langgraph", ["langgraph"]),
    ("06 agents", "Temporal Java SDK", "https://github.com/temporalio/sdk-java", ["sdk-java"]),
    ("06 agents", "Spring AI", "https://github.com/spring-projects/spring-ai", ["spring-ai"]),
    ("06 agents", "LangChain4j", "https://github.com/langchain4j/langchain4j", ["langchain4j"]),
    ("07 production", "OpenTelemetry GenAI semantic conventions (own repository since semconv 1.44)",
     "https://github.com/open-telemetry/semantic-conventions-genai", ["semantic-conventions-genai"]),
    ("07 production", "Brooker - Exponential Backoff and Jitter",
     "https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/", ["exponential backoff and jitter"]),
    ("07 production", "Google SRE Book - Handling Overload (client-side throttling)",
     "https://sre.google/sre-book/handling-overload/", ["client side throttling"]),
    ("07 production", "Google SRE Book - Addressing Cascading Failures",
     "https://sre.google/sre-book/addressing-cascading-failures/", ["cascading failures"]),
    ("07 production", "Dean, Barroso - The Tail at Scale", "https://research.google/pubs/the-tail-at-scale/", ["tail at scale"]),
]

UA = "Mozilla/5.0 (KB link checker; production-ai-engineering-l7-reference)"


def fetch(url: str) -> tuple[int, str, str]:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,application/pdf;q=0.9,*/*;q=0.8"})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            body = r.read(400_000)
            return r.status, r.geturl(), body.decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, url, ""
    except Exception as e:                                                     # DNS, TLS, timeout
        return 0, url, type(e).__name__


def title_of(body: str) -> str:
    m = re.search(r"<title[^>]*>(.*?)</title>", body, flags=re.S | re.I)
    return re.sub(r"\s+", " ", html.unescape(m.group(1))).strip() if m else ""


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")                                  # page titles are not cp1252-safe
    passed, failed = 0, []
    for section, label, url, keys in READING:                                  # strictly one request at a time
        status, final, body = fetch(url)
        title = title_of(body)
        hay = (title + " " + (body if not title or url.endswith(".pdf") else "")).lower()
        ok = status == 200 and all(k.lower() in hay for k in keys)
        if url.endswith(".pdf") and status == 200 and not title:
            ok = body.startswith("%PDF") or all(k.lower() in body.lower() for k in keys)
        passed += ok
        if not ok:
            failed.append(label)
        shown = title[:70] if title else ("(pdf)" if url.endswith(".pdf") else "")
        print(f"{'OK  ' if ok else 'FAIL'} {status:>3} {section:22} {label[:58]:58} | {shown}")
        time.sleep(0.5)                                                        # be polite to every host
    print(f"\n{passed}/{len(READING)} links verified (HTTP 200 + expected keywords)")
    if failed:
        print("FAILED: " + "; ".join(failed))
        sys.exit(1)
    print("all verify_reading_list self-checks passed")


if __name__ == "__main__":
    main()
```

Output (one run on 2026-10-27; link state changes over time, so rerun before relying on it):

```text
OK   200 01 inference physics   Williams, Waterman, Patterson - Roofline (UCB TR 2008)     | Roofline: An Insightful Visual Performance Model for Floating-Point Pr
OK   200 01 inference physics   Pope et al. - Efficiently Scaling Transformer Inference    | [2211.05102] Efficiently Scaling Transformer Inference
OK   200 01 inference physics   Ainslie et al. - GQA                                       | [2305.13245] GQA: Training Generalized Multi-Query Transformer Models 
OK   200 01 inference physics   DeepSeek-V2 (Multi-head Latent Attention)                  | [2405.04434] DeepSeek-V2: A Strong, Economical, and Efficient Mixture-
OK   200 01 inference physics   Dao et al. - FlashAttention                                | [2205.14135] FlashAttention: Fast and Memory-Efficient Exact Attention
OK   200 01 inference physics   Dao - FlashAttention-2                                     | [2307.08691] FlashAttention-2: Faster Attention with Better Parallelis
OK   200 01 inference physics   Kwon et al. - PagedAttention / vLLM (SOSP 2023)            | [2309.06180] Efficient Memory Management for Large Language Model Serv
OK   200 01 inference physics   Zheng et al. - SGLang / RadixAttention                     | [2312.07104] SGLang: Efficient Execution of Structured Language Model 
OK   200 02 serving             Yu et al. - Orca (OSDI 2022)                               | Orca: A Distributed Serving System for Transformer-Based Generative Mo
OK   200 02 serving             Agrawal et al. - Sarathi-Serve (chunked prefill)           | [2403.02310] Taming Throughput-Latency Tradeoff in LLM Inference with 
OK   200 02 serving             Zhong et al. - DistServe                                   | [2401.09670] DistServe: Disaggregating Prefill and Decoding for Goodpu
OK   200 02 serving             Patel et al. - Splitwise                                   | [2311.18677] Splitwise: Efficient generative LLM inference using phase
OK   200 02 serving             Leviathan et al. - Speculative Decoding                    | [2211.17192] Fast Inference from Transformers via Speculative Decoding
OK   200 02 serving             Li et al. - EAGLE                                          | [2401.15077] EAGLE: Speculative Sampling Requires Rethinking Feature U
OK   200 02 serving             Xiao et al. - SmoothQuant                                  | [2211.10438] SmoothQuant: Accurate and Efficient Post-Training Quantiz
OK   200 02 serving             Lin et al. - AWQ                                           | [2306.00978] AWQ: Activation-aware Weight Quantization for LLM Compres
OK   200 02 serving             DeepSeek-V3 Technical Report                               | [2412.19437] DeepSeek-V3 Technical Report
OK   200 02 serving             vLLM                                                       | GitHub - vllm-project/vllm: A high-throughput and memory-efficient inf
OK   200 02 serving             SGLang                                                     | GitHub - sgl-project/sglang: SGLang is a high-performance serving fram
OK   200 02 serving             TensorRT-LLM                                               | GitHub - NVIDIA/TensorRT-LLM: TensorRT LLM provides users with an easy
OK   200 03 vector search       Malkov, Yashunin - HNSW                                    | [1603.09320] Efficient and robust approximate nearest neighbor search 
OK   200 03 vector search       Douze et al. - The Faiss library (PQ, IVF, HNSW in one fra | [2401.08281] The Faiss library
OK   200 03 vector search       Patel et al. - ACORN (filtered ANN)                        | [2403.04871] ACORN: Performant and Predicate-Agnostic Search Over Vect
OK   200 03 vector search       DiskANN                                                    | GitHub - microsoft/DiskANN: A vector indexing library to bring fast, f
OK   200 03 vector search       hnswlib                                                    | GitHub - nmslib/hnswlib: Header-only C++/python library for fast appro
OK   200 03 vector search       Faiss                                                      | GitHub - facebookresearch/faiss: A library for efficient similarity se
OK   200 03 vector search       pgvector                                                   | GitHub - pgvector/pgvector: Open-source vector similarity search for P
OK   200 04 RAG                 Lewis et al. - Retrieval-Augmented Generation              | [2005.11401] Retrieval-Augmented Generation for Knowledge-Intensive NL
OK   200 04 RAG                 Khattab, Zaharia - ColBERT                                 | [2004.12832] ColBERT: Efficient and Effective Passage Search via Conte
OK   200 04 RAG                 Formal et al. - SPLADE                                     | [2107.05720] SPLADE: Sparse Lexical and Expansion Model for First Stag
OK   200 04 RAG                 Cormack, Clarke, Buettcher - Reciprocal Rank Fusion (SIGIR | (pdf)
OK   200 04 RAG                 Guenther et al. - Late Chunking                            | [2409.04701] Late Chunking: Contextual Chunk Embeddings Using Long-Con
OK   200 04 RAG                 Anthropic - Contextual Retrieval                           | Contextual retrieval in AI systems \ Anthropic
OK   200 04 RAG                 Edge et al. - GraphRAG                                     | [2404.16130] From Local to Global: A Graph RAG Approach to Query-Focus
OK   200 04 RAG                 Liu et al. - Lost in the Middle                            | [2307.03172] Lost in the Middle: How Language Models Use Long Contexts
OK   200 05 MCP                 Model Context Protocol specification (2025-11-25)          | Specification - Model Context Protocol
OK   200 05 MCP                 MCP Python SDK                                             | GitHub - modelcontextprotocol/python-sdk: The official Python SDK for 
OK   200 05 MCP                 MCP Java SDK                                               | GitHub - modelcontextprotocol/java-sdk: The official Java SDK for Mode
OK   200 05 MCP                 RFC 8693 - OAuth 2.0 Token Exchange                        | RFC 8693: OAuth 2.0 Token Exchange | RFC Editor
OK   200 05 MCP                 RFC 8707 - Resource Indicators for OAuth 2.0               | RFC 8707: Resource Indicators for OAuth 2.0 | RFC Editor
OK   200 05 MCP                 RFC 9728 - OAuth 2.0 Protected Resource Metadata           | RFC 9728: OAuth 2.0 Protected Resource Metadata | RFC Editor
OK   200 05 MCP                 Greshake et al. - Indirect Prompt Injection                | [2302.12173] Not what you've signed up for: Compromising Real-World LL
OK   200 05 MCP                 Willison - The lethal trifecta for AI agents               | The lethal trifecta for AI agents: private data, untrusted content, an
OK   200 05 MCP                 Gan, Sun - RAG-MCP                                         | [2505.03275] RAG-MCP: Mitigating Prompt Bloat in LLM Tool Selection vi
OK   200 06 agents              Yao et al. - ReAct                                         | [2210.03629] ReAct: Synergizing Reasoning and Acting in Language Model
OK   200 06 agents              Xu et al. - ReWOO                                          | [2305.18323] ReWOO: Decoupling Reasoning from Observations for Efficie
OK   200 06 agents              Kim et al. - LLMCompiler                                   | [2312.04511] An LLM Compiler for Parallel Function Calling
OK   200 06 agents              Shinn et al. - Reflexion                                   | [2303.11366] Reflexion: Language Agents with Verbal Reinforcement Lear
OK   200 06 agents              Madaan et al. - Self-Refine                                | [2303.17651] Self-Refine: Iterative Refinement with Self-Feedback
OK   200 06 agents              Huang et al. - LLMs Cannot Self-Correct Reasoning Yet      | [2310.01798] Large Language Models Cannot Self-Correct Reasoning Yet
OK   200 06 agents              Anthropic - Building effective agents                      | Building effective AI agents \ Anthropic
OK   200 06 agents              LangGraph                                                  | GitHub - langchain-ai/langgraph: Build resilient agents. · GitHub
OK   200 06 agents              Temporal Java SDK                                          | GitHub - temporalio/sdk-java: Temporal Java SDK · GitHub
OK   200 06 agents              Spring AI                                                  | GitHub - spring-projects/spring-ai: An Application Framework for AI En
OK   200 06 agents              LangChain4j                                                | GitHub - langchain4j/langchain4j: LangChain4j is an idiomatic, open-so
OK   200 07 production          OpenTelemetry GenAI semantic conventions (own repository s | GitHub - open-telemetry/semantic-conventions-genai · GitHub
OK   200 07 production          Brooker - Exponential Backoff and Jitter                   | Exponential Backoff And Jitter | AWS Architecture Blog
OK   200 07 production          Google SRE Book - Handling Overload (client-side throttlin | Google SRE: Load Balancing with Client Side Throttling
OK   200 07 production          Google SRE Book - Addressing Cascading Failures            | Google SRE - Cascading Failures: Reducing System Outage
OK   200 07 production          Dean, Barroso - The Tail at Scale                          | The Tail at Scale

60/60 links verified (HTTP 200 + expected keywords)
all verify_reading_list self-checks passed
```

What the first run found, before the corrections above:

- `inria.hal.science` failed TLS verification from this machine (an incomplete certificate chain for Python's
  default trust store), and `hal.inria.fr` answered with a bot challenge. *The Faiss library* replaced it as the
  linked source.
- Anthropic's article title changed to "Building effective AI agents", so the keyword check was relaxed to its
  stable words.
- The SRE chapter URL now titles itself "Load Balancing with Client Side Throttling"; the entry is labelled
  accordingly.
- The OpenTelemetry GenAI page on opentelemetry.io now says the conventions "have moved to the OpenTelemetry GenAI
  semantic conventions repository". The entry links the new repository, and Folder 07 File 04 was updated.

---

## 4. Failure modes of a reading list

### F1 · Link rot and silent moves

- **Symptom:** a link that returns 200 but now points to a stub ("Moved") or a different chapter.
- **Fix:** verify titles as well as status codes, as this listing does, and rerun on a schedule.

### F2 · Reading the abstract, missing the cost model

- **Fix:** for every mechanism paper, derive one number from its cost model before reading its benchmarks.

### F3 · Trusting a version you are not running

- **Fix:** read the repository at the tag you deploy. Folder 06 File 02 found deprecations (`maxSequentialToolsInvocations`)
  and silent behaviours (tool dropping, `arg0` schemas) only by compiling against the exact jars.

---

## 5. Invariants checklist

- [ ] Every source in a design doc is pinned (paper version, spec revision, repository tag).
- [ ] Links are verified by status and title before publication and on a schedule.
- [ ] Each mechanism adopted from a paper is accompanied by its cost model, recomputed for our workload.
- [ ] Specifications are read for MUST/MUST NOT and the error model; repositories for defaults and changelogs.

## 6. References

All sources are listed in §2. The verification method is §3.
