# 02 · Python Blueprint: an MCP Tool Server, a LangGraph Agent, and a Hardened vLLM Streaming Client

> **Folder:** `07-Production-Code-Blueprints-Java-and-Python/` · **File 2 of 4**
> **Anchoring code and specifications:** OpenAI-compatible Chat Completions streaming (`chat.completion.chunk`,
> `stream_options.include_usage`, `[DONE]`), as served by vLLM, SGLang and TGI · MCP Python SDK **2.3.0**
> (`MCPServer`, `Client`, `ToolError`) · LangGraph **1.2.18** (`StateGraph`, `interrupt`, `recursion_limit`) ·
> httpx 0.28.1 · M. Brooker, *Exponential Backoff and Jitter* (AWS Architecture Blog, 2015).
> **Code baseline:** Python 3.10+ (CPython 3.14.5). The model server is a local fake that speaks the vLLM/OpenAI wire
> format and injects faults; no GPU or API key.
> **Previous:** [01 · Java MCP server and resilient RAG orchestrator](01-java-mcp-server-official-sdk-and-resilient-spring-ai-rag-orchestrator.md) ·
> **Next:** [03 · Hybrid search SQL and Kafka ingestion](03-hybrid-search-sql-postgres-and-kafka-cdc-ingestion-pipeline.md)

---

## 0. The thesis in one paragraph

The Python agent stack has three layers:

- **LangGraph** owns control flow and state;
- **an OpenAI-compatible model server** (vLLM in production) decides the next step;
- **MCP** supplies the tools.

The layer people under-engineer is the one in the middle: the *streaming client*. Its central rule is that **a
request is retryable only until the first token has been shown.**

- Before the first token, a 429, a 503 or a stalled prefill is safely retried, with Retry-After or full-jitter
  backoff.
- After the first token, a retry duplicates text the user already read. The naive client in the lab showed
  `tok0 … tok4 tok0 … tok11`. The hardened client raises `PartialStream` so the UI can replace rather than append.

A stream that ends without `finish_reason` and `[DONE]` is truncated, whatever HTTP says. Tool-call arguments arrive
in fragments that must be assembled and validated before anything executes. Around the client, the agent is wired
so that MCP annotations drive policy: read-only tools run directly, and a destructive tool waits for a durable human
approval. Two guards bound runaway loops: a tool budget and `recursion_limit`.

---

## 1. First principles

### 1.1 The streaming wire format

An OpenAI-compatible server answers `"stream": true` with `text/event-stream` over HTTP/1.1 chunked encoding. Each
event is one JSON chunk:

```text
data: {"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}
data: {"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"tok0 "}}]}
data: {"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"order"}}]}}]}
data: {"object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
data: {"object":"chat.completion.chunk","choices":[],"usage":{"prompt_tokens":9,"completion_tokens":13,"total_tokens":22}}
data: [DONE]
```

Rules a client must follow:

1. **Content is the concatenation of deltas.** Tool calls are keyed by `index`; `id` and `function.name` arrive
   once; `function.arguments` arrives in fragments. Concatenate, then `json.loads`, then validate against the
   tool's schema. In the lab the arguments `{"order_id": "A-17"}` arrived in 3 fragments.
2. **Completion is explicit.** `finish_reason` (`stop`, `length`, `tool_calls`, `content_filter`) and `[DONE]` mark
   the end. With chunked encoding a dropped connection surfaces as `RemoteProtocolError`. With close-delimited
   bodies, a drop looks exactly like a normal end, so the terminal markers are the only reliable signal.
3. **Usage needs asking for.** `stream_options: {"include_usage": true}` adds a final chunk with empty `choices` and
   the token counts. Billing, rate limiting (File 04) and FinOps (Folder 08) depend on it.
4. **`length` is not success.** It means the answer was cut at `max_tokens`; agents should treat it as a failure or
   continue deliberately.

### 1.2 Retry safety is defined by what the user has seen

| Failure | Tokens delivered | Safe action |
|---|---|---|
| connect error, 503 before the body | 0 | retry with jittered backoff |
| 429 with Retry-After | 0 | wait Retry-After, then retry (the server knows its queue) |
| no first token within the TTFT budget | 0 | cancel and retry (another replica, or later) |
| connection dropped mid-stream | > 0 | **do not silently retry.** Raise `PartialStream` |
| idle timeout between tokens | > 0 | the same |

After `PartialStream` there are three honest options:

- **replace:** clear the bubble and regenerate. Sampling makes the new answer differ, so never splice it onto the
  partial;
- **resume:** send the partial back as the assistant's prefix and ask the server to continue it (vLLM exposes this
  in its chat API; ⚠ verify the parameter for your server and version);
- **show the partial with a "continue" control.**

Agents should usually replace: a truncated tool-call JSON or a half-sentence plan is worse than a clean retry.

### 1.3 Timeouts are budgets with physics behind them

- **Connect:** about 1 s. Anything slower is an infrastructure failure, not load.
- **Time to first token** is queueing plus prefill, and prefill scales with prompt length. For Llama-3-70B on
  8×H100, uncached prefill runs about 17,850 tokens/s (Folder 05 File 03: 25,960 tokens in 1,454 ms), so a 32K-token
  prompt needs about 1.8 s before the first token *on an idle server*. A fixed 1 s TTFT timeout fails every long-RAG
  request. Scale the budget:

  ```text
  ttft_timeout = base + safety × prompt_tokens / prefill_rate      e.g. 1 s + 2 × 32,000 / 17,850 ≈ 4.6 s
  ```

- **Inter-token idle:** a few times the p99 TPOT. A server that stops emitting mid-answer has preempted the
  sequence (Folder 02 File 01) or died.
- **Total deadline:** the caller's remaining budget (File 01 §1.2).

In the lab, a first token stalled for 1 s. The 300 ms TTFT budget cancelled it and the retry succeeded, for a total
of 567 ms against the full stall.

### 1.4 Backoff, jitter and retry amplification

- **Full jitter.** `sleep = U(0, min(cap, base·2ᵃ))` spreads retrying clients so they do not re-synchronize into
  waves (Brooker). For 429, honour `Retry-After`: the lab waited exactly 0.2 s for the 429 and a jittered 32 ms for
  the 503.
- **Amplification.** If each of `L` layers retries `r` times, one user request can become `(r+1)ᴸ` calls at the
  bottom: 3 retries at 3 layers is **64×** load on a model server that is already returning 429. Retry at **one**
  layer, the client closest to the model, and give it a **retry budget** (for example, retries ≤ 10% of requests per
  client) so retries cannot exceed a fraction of traffic.
- **Bounded attempts.** The lab's persistent-503 case gives up after 3 attempts; the breaker and fallback of File 01
  take it from there.

### 1.5 Composing LangGraph, the model and MCP

1. **Tool schemas translate directly.** MCP `inputSchema` is JSON Schema, which is what the OpenAI `tools[].function.
   parameters` field wants. The Python SDK generates it from type hints (with pydantic `title` fields). It does not
   add `additionalProperties: false`, so set it yourself if extra arguments must be rejected.
2. **Annotations drive policy, but the host decides.** `destructiveHint` routes `issue_credit` through an
   `interrupt()` approval; `readOnlyHint` tools run directly. Annotations from third-party servers are claims, so
   the host's allowlist, not the server's annotation, is authoritative (Folder 05 File 02).
3. **Identity is bound at connection time.** The tool server is built for tenant `acme`; nothing in the tool
   arguments can change that.
4. **Errors are tool results.** The Python SDK 2.3.0 passes a `ToolError`'s message to the model ("unknown order
   Z-1; order ids look like A-17"), so the model can correct itself, and reduces an unexpected exception to "Error
   executing tool inventory_level" with no internal address. The Java SDK 2.1.0 does the opposite by default
   (File 01 §2), so hosts should normalize errors from both.
5. **Two loop guards.** A per-turn tool budget returns a structured `stop_reason`; `recursion_limit` is the backstop
   that raises `GraphRecursionError`. File 06/01 §1.5 explains why both exist.

---

## 2. Production code blueprints

### 2.1 Python: the hardened streaming client against a fault-injecting fake vLLM

The fake server is a real HTTP/1.1 server (chunked transfer encoding, SSE framing). It selects faults per request with
an `x-fault` header: `429-once`, `503-once`, `drop-once` (abort after 5 tokens), `slow-ttft-once` (1 s stall) and
`503-always`. The naive client has no timeouts and retries by appending, the way a UI that already rendered tokens
would.

```python
"""vllm_stream_client.py - a hardened streaming client for OpenAI-compatible servers (vLLM, SGLang, TGI), tested
against a local fake server that speaks the same wire format and injects the faults production sees.

The fake server streams `chat.completion.chunk` SSE events with HTTP chunked encoding, streams tool-call arguments in
fragments, sends a usage chunk when `stream_options.include_usage` is set, and can return 429 + Retry-After, return
503 before the first byte, drop the connection mid-stream, or stall before the first token.

The hardened client (httpx):
  * separate budgets for connect, time to first token, inter-token idle, and the whole request;
  * retries with full-jitter backoff (or Retry-After) ONLY while no token has been delivered - a retry after the
    first token would duplicate text the user already saw, so it raises PartialStream instead;
  * treats a stream without finish_reason / [DONE] as truncated, whatever the HTTP layer says;
  * assembles tool-call argument fragments by index and validates the JSON.
Requires: pip install httpx
"""
from __future__ import annotations

import asyncio
import json
import random
import time
from dataclasses import dataclass, field

import httpx


# ---------------------------------------------------------------------- the fake OpenAI-compatible server
class FakeVllm:
    def __init__(self, tpot_s: float = 0.004):
        self.tpot_s = tpot_s
        self.fault_hits: dict[str, int] = {}
        self.requests = 0
        self.generated = 0

    def script(self, body: dict) -> tuple[list[dict], str]:
        """Return (deltas, finish_reason) for the request: tool calls, an answer from tool output, or plain text."""
        msgs = body["messages"]
        last = msgs[-1]
        if body.get("tools") and last["role"] == "user" and "order" in last["content"].lower():
            frags = ['{"order', '_id": "A', '-17"}']
            deltas = [{"role": "assistant", "tool_calls": [{"index": 0, "id": "call_1", "type": "function",
                                                            "function": {"name": "get_order", "arguments": ""}}]}]
            deltas += [{"tool_calls": [{"index": 0, "function": {"arguments": f}}]} for f in frags]
            return deltas, "tool_calls"
        if last["role"] == "tool":
            facts = " ".join(m["content"] for m in msgs if m["role"] == "tool")
            words = f"Based on the tools: {facts}".split()
            return [{"role": "assistant", "content": ""}] + [{"content": w + " "} for w in words], "stop"
        n = int(body.get("max_tokens", 20))
        return [{"role": "assistant", "content": ""}] + [{"content": f"tok{i} "} for i in range(n)], "length"

    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        head = await reader.readuntil(b"\r\n\r\n")
        lines = head.decode().split("\r\n")
        headers = {k.lower(): v.strip() for k, v in (l.split(":", 1) for l in lines[1:] if ":" in l)}
        body = json.loads(await reader.readexactly(int(headers.get("content-length", "0"))) or b"{}")
        self.requests += 1
        fault = headers.get("x-fault", "")
        hits = self.fault_hits[fault] = self.fault_hits.get(fault, 0) + 1
        once = fault.endswith("-once")
        active = fault and (not once or hits == 1)

        if active and fault.startswith("429"):
            writer.write(b"HTTP/1.1 429 Too Many Requests\r\nRetry-After: 0.2\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            await writer.drain()
            writer.close()
            return
        if active and fault.startswith("503"):
            writer.write(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            await writer.drain()
            writer.close()
            return
        writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n"
                     b"Connection: close\r\n\r\n")

        async def send(obj) -> None:
            data = (f"data: {obj}\n\n" if isinstance(obj, str) else f"data: {json.dumps(obj)}\n\n").encode()
            writer.write(f"{len(data):X}\r\n".encode() + data + b"\r\n")
            await writer.drain()

        if active and fault.startswith("slow-ttft"):
            await asyncio.sleep(1.0)
        deltas, finish = self.script(body)
        base = {"id": "chatcmpl-1", "object": "chat.completion.chunk", "model": body.get("model", "m")}
        try:
            for i, d in enumerate(deltas):
                if active and fault.startswith("drop") and i == 6:
                    writer.transport.abort()                                  # no terminal chunk, no [DONE]
                    return
                self.generated += 1
                await send({**base, "choices": [{"index": 0, "delta": d, "finish_reason": None}]})
                await asyncio.sleep(self.tpot_s)
            await send({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": finish}]})
            if body.get("stream_options", {}).get("include_usage"):
                prompt_tokens = sum(len(str(m.get("content", "")).split()) for m in body["messages"]) + 8
                await send({**base, "choices": [], "usage": {"prompt_tokens": prompt_tokens,
                                                              "completion_tokens": len(deltas),
                                                              "total_tokens": prompt_tokens + len(deltas)}})
            await send("[DONE]")
            writer.write(b"0\r\n\r\n")
            await writer.drain()
        except (ConnectionError, OSError):
            pass                                                              # the client went away
        writer.close()

    async def start(self) -> tuple[asyncio.AbstractServer, str]:
        srv = await asyncio.start_server(self.handle, "127.0.0.1", 0)
        return srv, f"http://127.0.0.1:{srv.sockets[0].getsockname()[1]}"


# ---------------------------------------------------------------------- the hardened client
class StreamError(Exception):
    pass


class PartialStream(StreamError):
    """The stream broke after tokens were delivered: the caller must REPLACE what it showed, not append a retry."""

    def __init__(self, text: str, tokens: int, cause: str):
        super().__init__(f"stream broke after {tokens} tokens: {cause}")
        self.text, self.tokens = text, tokens


class _Retryable(Exception):
    def __init__(self, why: str, retry_after: float | None = None):
        super().__init__(why)
        self.retry_after = retry_after


@dataclass
class Result:
    text: str = ""
    tool_calls: list = field(default_factory=list)
    finish_reason: str | None = None
    usage: dict | None = None
    ttft_ms: float = 0.0
    tpot_ms: float = 0.0
    attempts: int = 0
    waits: list = field(default_factory=list)


async def stream_chat(client: httpx.AsyncClient, base: str, body: dict, *, headers: dict | None = None,
                      ttft_timeout: float = 2.0, idle_timeout: float = 1.0, deadline_s: float = 10.0,
                      max_attempts: int = 4, rng: random.Random | None = None, on_token=None) -> Result:
    rng = rng or random.Random(7)
    body = {**body, "stream": True, "stream_options": {"include_usage": True}}
    t_start = time.perf_counter()
    res = Result()
    for attempt in range(1, max_attempts + 1):
        res.attempts = attempt
        delivered, text, calls = 0, [], {}
        t0 = time.perf_counter()
        first_at = last_at = None
        try:
            remaining = deadline_s - (time.perf_counter() - t_start)
            if remaining <= 0:
                raise StreamError("deadline exceeded before a successful attempt")
            timeout = httpx.Timeout(connect=1.0, read=idle_timeout, write=1.0, pool=1.0)
            async with asyncio.timeout(remaining):
                async with client.stream("POST", f"{base}/v1/chat/completions", json=body, headers=headers or {},
                                         timeout=timeout) as r:
                    if r.status_code == 429 or r.status_code >= 500:
                        ra = r.headers.get("retry-after")
                        raise _Retryable(f"HTTP {r.status_code}", float(ra) if ra else None)
                    if r.status_code >= 400:
                        raise StreamError(f"HTTP {r.status_code}: {(await r.aread())[:200]!r}")
                    lines = r.aiter_lines()
                    done = False
                    while True:
                        budget = ttft_timeout if first_at is None else idle_timeout
                        try:
                            line = await asyncio.wait_for(anext(lines), budget)
                        except StopAsyncIteration:
                            break
                        except TimeoutError:
                            raise _Retryable(f"no token within {budget * 1000:.0f} ms") if delivered == 0 else \
                                PartialStream("".join(text), delivered, "idle timeout")
                        if not line.startswith("data: "):
                            continue
                        payload = line[6:]
                        if payload == "[DONE]":
                            done = True
                            break
                        chunk = json.loads(payload)
                        if chunk.get("usage"):
                            res.usage = chunk["usage"]
                        for ch in chunk.get("choices", []):
                            d = ch.get("delta", {})
                            if d.get("content"):
                                now = time.perf_counter()
                                first_at = first_at or now
                                last_at = now
                                delivered += 1
                                text.append(d["content"])
                                if on_token:
                                    on_token(d["content"])
                            for tc in d.get("tool_calls", []):
                                first_at = first_at or time.perf_counter()
                                slot = calls.setdefault(tc["index"], {"id": None, "name": None, "arguments": ""})
                                slot["id"] = tc.get("id") or slot["id"]
                                fn = tc.get("function", {})
                                slot["name"] = fn.get("name") or slot["name"]
                                slot["arguments"] += fn.get("arguments", "")
                            if ch.get("finish_reason"):
                                res.finish_reason = ch["finish_reason"]
            if not done or res.finish_reason is None:
                raise _Retryable("stream ended without finish_reason/[DONE]") if delivered == 0 else \
                    PartialStream("".join(text), delivered, "stream ended without [DONE]")
            res.text = "".join(text)
            res.tool_calls = []
            for i in sorted(calls):
                c = calls[i]
                c["arguments_json"] = json.loads(c["arguments"])                  # validate before anyone executes it
                res.tool_calls.append(c)
            res.ttft_ms = ((first_at or time.perf_counter()) - t0) * 1000
            if delivered > 1 and last_at and first_at:
                res.tpot_ms = (last_at - first_at) / (delivered - 1) * 1000
            return res
        except PartialStream:
            raise
        except (httpx.RemoteProtocolError, httpx.ReadError) as e:
            if delivered:
                raise PartialStream("".join(text), delivered, type(e).__name__) from e
            why, ra = type(e).__name__, None
        except (httpx.ConnectError, httpx.ConnectTimeout) as e:
            why, ra = type(e).__name__, None
        except _Retryable as e:
            why, ra = str(e), e.retry_after
        if attempt == max_attempts:
            raise StreamError(f"gave up after {attempt} attempts: {why}")
        wait = ra if ra is not None else rng.uniform(0, min(2.0, 0.05 * 2 ** attempt))   # full jitter
        res.waits.append((why, round(wait, 3)))
        await asyncio.sleep(wait)
    raise StreamError("unreachable")


async def naive_stream(client: httpx.AsyncClient, base: str, body: dict, headers: dict, shown: list) -> None:
    """No timeouts; on any failure retry the whole request and keep appending to what the user already saw."""
    for _ in range(3):
        try:
            async with client.stream("POST", f"{base}/v1/chat/completions", json={**body, "stream": True},
                                     headers=headers, timeout=None) as r:
                async for line in r.aiter_lines():
                    if line.startswith("data: {"):
                        for ch in json.loads(line[6:]).get("choices", []):
                            if ch.get("delta", {}).get("content"):
                                shown.append(ch["delta"]["content"])
            return
        except httpx.HTTPError:
            continue


# ---------------------------------------------------------------------- experiments
async def main_async() -> None:
    fake = FakeVllm()
    srv, base = await fake.start()
    plain = {"model": "llama-3-70b", "messages": [{"role": "user", "content": "count"}], "max_tokens": 12}
    async with srv, httpx.AsyncClient() as client:
        await stream_chat(client, base, plain)                                # warm-up: client + connection setup
        r = await stream_chat(client, base, plain)
        print(f"1. normal: finish={r.finish_reason}, {len(r.text.split())} tokens, TTFT {r.ttft_ms:.1f} ms, "
              f"TPOT {r.tpot_ms:.1f} ms, usage={r.usage}, attempts={r.attempts}")
        assert r.finish_reason == "length" and r.usage["completion_tokens"] == 13

        waits = {}
        for fault in ("429-once", "503-once"):
            r = await stream_chat(client, base, plain, headers={"x-fault": fault})
            waits[fault] = r.waits[0][1]
            print(f"2. {fault}: attempts={r.attempts}, waits={r.waits}, finish={r.finish_reason}")
            assert r.attempts == 2 and r.finish_reason == "length"
        assert waits["429-once"] == 0.2 and waits["503-once"] < 0.2, "429 honours Retry-After; 503 uses full jitter"

        shown: list = []
        await naive_stream(client, base, plain, {"x-fault": "drop-once"}, shown)
        print(f"\n3. connection dropped after 5 tokens, then the retry succeeds")
        print(f"   naive (retry + append): user saw {''.join(shown).strip()!r}")
        try:
            await stream_chat(client, base, plain, headers={"x-fault": "drop-once-b"})
            raise SystemExit("expected PartialStream")
        except PartialStream as p:
            print(f"   hardened: PartialStream({p}); partial={p.text.strip()!r} -> caller replaces the bubble or resumes")
        assert "".join(shown).count("tok0") == 2

        t0 = time.perf_counter()
        r = await stream_chat(client, base, plain, headers={"x-fault": "slow-ttft-once"}, ttft_timeout=0.3)
        print(f"\n4. first token stalls 1 s: TTFT budget 300 ms -> waits={r.waits}, attempts={r.attempts}, "
              f"total {(time.perf_counter() - t0) * 1000:.0f} ms (naive would wait the full stall)")
        assert r.attempts == 2

        tool_body = {"model": "llama-3-70b", "messages": [{"role": "user", "content": "where is my order A-17?"}],
                     "tools": [{"type": "function", "function": {"name": "get_order", "parameters": {"type": "object"}}}]}
        r = await stream_chat(client, base, tool_body)
        print(f"\n5. tool call streamed in {len(fake.script(tool_body)[0]) - 1} argument fragments -> "
              f"finish={r.finish_reason}, assembled={r.tool_calls[0]['name']}({r.tool_calls[0]['arguments_json']})")
        assert r.tool_calls[0]["arguments_json"] == {"order_id": "A-17"} and r.finish_reason == "tool_calls"

        try:
            await stream_chat(client, base, plain, headers={"x-fault": "503-always"}, max_attempts=3)
        except StreamError as e:
            print(f"\n6. persistent 503: {e}  (bounded attempts, then the breaker/fallback of File 01 takes over)")
    print("\nall vllm_stream_client self-checks passed")


def main() -> None:
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
```

Output (one measured run; TTFT/TPOT are measured, everything else is asserted):

```text
1. normal: finish=length, 12 tokens, TTFT 14.4 ms, TPOT 15.0 ms, usage={'prompt_tokens': 9, 'completion_tokens': 13, 'total_tokens': 22}, attempts=1
2. 429-once: attempts=2, waits=[('HTTP 429', 0.2)], finish=length
2. 503-once: attempts=2, waits=[('HTTP 503', 0.032)], finish=length

3. connection dropped after 5 tokens, then the retry succeeds
   naive (retry + append): user saw 'tok0 tok1 tok2 tok3 tok4 tok0 tok1 tok2 tok3 tok4 tok5 tok6 tok7 tok8 tok9 tok10 tok11'
   hardened: PartialStream(stream broke after 5 tokens: RemoteProtocolError); partial='tok0 tok1 tok2 tok3 tok4' -> caller replaces the bubble or resumes

4. first token stalls 1 s: TTFT budget 300 ms -> waits=[('no token within 300 ms', 0.032)], attempts=2, total 569 ms (naive would wait the full stall)

5. tool call streamed in 3 argument fragments -> finish=tool_calls, assembled=get_order({'order_id': 'A-17'})

6. persistent 503: gave up after 3 attempts: HTTP 503  (bounded attempts, then the breaker/fallback of File 01 takes over)

all vllm_stream_client self-checks passed
```

The measured TPOT (~16 ms against the server's 4 ms pacing) is Windows' default timer granularity (~15.6 ms)
applied to `asyncio.sleep`, not the client. On Linux the same code measures about 4 ms. The lesson carries over:
check the measuring instrument before trusting a latency number.

### 2.2 Python: a LangGraph agent with MCP tools, approval for destructive tools, and loop guards

The model is `AgentVllm`, the fake server scripted to plan `get_order → search_docs → issue_credit → answer` in the
OpenAI tool-calling format, with arguments streamed in 12-character fragments. The tools are a real `MCPServer`
reached through the SDK's in-process `Client`.

```python
"""mcp_langgraph_agent.py - the Python agent stack end to end: LangGraph orchestrates, an OpenAI-compatible model
server (vLLM's wire format; the fake from vllm_stream_client) decides, and an MCPServer (mcp 2.3.0) provides tools.

* Tools come from MCP `list_tools` and are converted to the OpenAI `tools` format; their annotations drive policy:
  read-only tools run directly, a destructiveHint tool goes through a human approval (`interrupt()`) first.
* Tool results come back as `structuredContent`; tool errors (`isError`) are fed to the model as tool messages.
* The server-side identity (tenant) is bound when the MCP client is created, never taken from model arguments.
* Guards: a per-turn tool-call budget and LangGraph's recursion_limit, with a structured failure instead of a crash.
Requires: pip install "mcp>=2.3,<3" "langgraph==1.2.18" httpx
"""
from __future__ import annotations

import asyncio
import json
import logging
import operator
from typing import Annotated, TypedDict

import httpx
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.errors import GraphRecursionError
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, interrupt
from mcp import Client
from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import ToolAnnotations

from vllm_stream_client import FakeVllm, stream_chat


# ---------------------------------------------------------------------- the MCP tool server
class Order(TypedDict):
    order_id: str
    status: str
    carrier_delay_days: int


class Hits(TypedDict):
    hits: list[str]


class Credit(TypedDict):
    credit_id: str
    order_id: str
    pct: int
    created: bool


def build_tool_server(tenant: str) -> tuple[MCPServer, dict]:
    server = MCPServer("support-tools", instructions=f"Support tools for tenant {tenant}.")
    ledger: dict[str, Credit] = {}

    @server.tool(annotations=ToolAnnotations(read_only_hint=True))
    def get_order(order_id: str) -> Order:
        """Look up one order's shipping status."""
        if not order_id.startswith("A-"):
            raise ToolError(f"unknown order {order_id}; order ids look like A-17")   # intended for the model
        return {"order_id": order_id, "status": "delayed", "carrier_delay_days": 6}

    @server.tool(annotations=ToolAnnotations(read_only_hint=True))
    def inventory_level(sku: str) -> int:
        """Units in stock for a SKU."""
        raise ValueError("inventory db at 10.0.0.5:5432 refused connection")       # unexpected: must not leak

    @server.tool(annotations=ToolAnnotations(read_only_hint=True))
    def search_docs(query: str, top_k: int = 2) -> Hits:
        """Search the support policy knowledge base."""
        kb = ["[kb-102] Carrier delays over 5 days qualify for a 10 percent shipping credit.",
              "[kb-101] Damaged items are refunded in full within 30 days."]
        return {"hits": [h for h in kb if any(w in h.lower() for w in query.lower().split())][:top_k]}

    @server.tool(annotations=ToolAnnotations(destructive_hint=True, idempotent_hint=True))
    def issue_credit(order_id: str, pct: int, request_id: str) -> Credit:
        """Issue a shipping credit (side effect; pass the same request_id on retries)."""
        created = request_id not in ledger
        if created:
            ledger[request_id] = {"credit_id": f"CR-{len(ledger) + 1:03d}", "order_id": order_id, "pct": pct, "created": True}
        return {**ledger[request_id], "created": created}

    return server, ledger


# ---------------------------------------------------------------------- the model (scripted, OpenAI wire format)
class AgentVllm(FakeVllm):
    """get_order -> search_docs -> issue_credit -> answer; the `stubborn` variant asks for get_order forever."""

    stubborn = False

    def script(self, body: dict):
        msgs = body["messages"]
        done = [m["name"] for m in msgs if m["role"] == "tool"]
        plan = [("get_order", {"order_id": "A-17"}),
                ("search_docs", {"query": "carrier delays credit"}),
                ("issue_credit", {"order_id": "A-17", "pct": 10, "request_id": "conv-9:turn-1:credit"})]
        nxt = plan[0] if self.stubborn else next((p for p in plan if p[0] not in done), None)
        if nxt:
            args = json.dumps(nxt[1])
            call = {"role": "assistant", "tool_calls": [{"index": 0, "id": f"call_{len(done) + 1}", "type": "function",
                                                         "function": {"name": nxt[0], "arguments": ""}}]}
            frags = [{"tool_calls": [{"index": 0, "function": {"arguments": args[i:i + 12]}}]} for i in range(0, len(args), 12)]
            return [call] + frags, "tool_calls"
        facts = " ".join(m["content"] for m in msgs if m["role"] == "tool")
        return [{"role": "assistant", "content": ""}] + [{"content": w + " "} for w in
                                                          f"Done: A-17 was delayed 6 days; a 10% credit was issued ({facts[-60:]})".split()], "stop"


# ---------------------------------------------------------------------- the LangGraph agent
class AgentState(TypedDict, total=False):
    messages: Annotated[list, operator.add]
    tool_calls_this_turn: int
    stop_reason: str


def openai_tools(mcp_tools) -> tuple[list, set]:
    tools, destructive = [], set()
    for t in mcp_tools:
        tools.append({"type": "function", "function": {"name": t.name, "description": t.description or "",
                                                       "parameters": t.input_schema}})
        if t.annotations and t.annotations.destructive_hint:
            destructive.add(t.name)
    return tools, destructive


def build_graph(http: httpx.AsyncClient, base: str, mcp: Client, tools: list, destructive: set, trace: list,
                max_tool_calls: int = 6):
    async def agent(state: AgentState):
        r = await stream_chat(http, base, {"model": "llama-3-70b", "messages": state["messages"], "tools": tools})
        trace.append(f"llm: finish={r.finish_reason} ttft={r.ttft_ms:.0f}ms tool_calls={[c['name'] for c in r.tool_calls]}")
        msg = {"role": "assistant", "content": r.text}
        if r.tool_calls:
            msg["tool_calls"] = [{"id": c["id"], "type": "function",
                                  "function": {"name": c["name"], "arguments": c["arguments"]}} for c in r.tool_calls]
        return {"messages": [msg]}

    def route(state: AgentState):
        last = state["messages"][-1]
        if not last.get("tool_calls"):
            return END
        if state.get("tool_calls_this_turn", 0) >= max_tool_calls:
            return "budget_exceeded"
        names = {c["function"]["name"] for c in last["tool_calls"]}
        return "approval" if names & destructive else "tools"

    def approval(state: AgentState):
        calls = [c["function"] for c in state["messages"][-1]["tool_calls"]]
        decision = interrupt({"approve": calls})                              # durable HITL (Folder 06 File 03)
        if decision != "approve":
            return Command(goto=END, update={"stop_reason": f"rejected by human: {decision}"})
        return Command(goto="tools")

    async def run_tools(state: AgentState):
        out = []
        for c in state["messages"][-1]["tool_calls"]:
            args = json.loads(c["function"]["arguments"])
            res = await mcp.call_tool(c["function"]["name"], args)
            body = json.dumps(res.structured_content) if res.structured_content and not res.is_error else \
                " ".join(getattr(x, "text", "") for x in res.content)
            trace.append(f"mcp: {c['function']['name']}({args}) isError={res.is_error} -> {body[:70]}")
            out.append({"role": "tool", "tool_call_id": c["id"], "name": c["function"]["name"],
                        "content": ("ERROR: " if res.is_error else "") + body})
        return {"messages": out, "tool_calls_this_turn": state.get("tool_calls_this_turn", 0) + len(out)}

    def budget_exceeded(state: AgentState):
        return {"stop_reason": f"tool-call budget of {max_tool_calls} exhausted"}

    g = StateGraph(AgentState)
    g.add_node("agent", agent)
    g.add_node("approval", approval, destinations=("tools", END))
    g.add_node("tools", run_tools)
    g.add_node("budget_exceeded", budget_exceeded)
    g.add_edge(START, "agent")
    g.add_conditional_edges("agent", route, ["tools", "approval", "budget_exceeded", END])
    g.add_edge("tools", "agent")
    g.add_edge("budget_exceeded", END)
    return g.compile(checkpointer=InMemorySaver())


async def main_async() -> None:
    model = AgentVllm()
    srv, base = await model.start()
    server, ledger = build_tool_server(tenant="acme")
    async with srv, httpx.AsyncClient() as http, Client(server) as mcp:
        listed = (await mcp.list_tools()).tools
        tools, destructive = openai_tools(listed)
        print(f"MCP tools -> OpenAI tools: {[t['function']['name'] for t in tools]}; destructive (needs approval): "
              f"{sorted(destructive)}")
        print(f"  get_order parameters schema: {json.dumps(tools[0]['function']['parameters'])}")
        bad = await mcp.call_tool("get_order", {"order_id": "Z-1"})
        print(f"  ToolError (intended message)  -> isError={bad.is_error}: {bad.content[0].text}")
        boom = await mcp.call_tool("inventory_level", {"sku": "SKU-9"})
        print(f"  unexpected ValueError         -> isError={boom.is_error}: {boom.content[0].text}")
        assert "A-17" in bad.content[0].text and "10.0.0.5" not in boom.content[0].text

        trace: list = []
        graph = build_graph(http, base, mcp, tools, destructive, trace)
        cfg = {"configurable": {"thread_id": "conv-9"}, "recursion_limit": 20}
        out = await graph.ainvoke({"messages": [{"role": "user", "content": "My order A-17 is late. Can I get anything?"}]}, cfg)
        print("\nrun 1 (until a destructive tool needs approval):")
        for t in trace:
            print("  " + t)
        print(f"  paused: interrupt={out['__interrupt__'][0].value}")
        assert "__interrupt__" in out and not ledger

        trace.clear()
        out = await graph.ainvoke(Command(resume="approve"), cfg)
        print("\nrun 2 (resumed with the manager's approval):")
        for t in trace:
            print("  " + t)
        print(f"  final answer: {out['messages'][-1]['content'].strip()}")
        print(f"  credits ledger: {list(ledger.values())}")
        assert len(ledger) == 1 and out["messages"][-1]["content"].startswith("Done")

        model.stubborn = True
        trace.clear()
        g2 = build_graph(http, base, mcp, tools, destructive, trace, max_tool_calls=3)
        out = await g2.ainvoke({"messages": [{"role": "user", "content": "order A-17?"}]},
                               {"configurable": {"thread_id": "loop"}, "recursion_limit": 50})
        print(f"\nstubborn model, tool budget 3: {len(trace)} trace events -> stop_reason={out.get('stop_reason')!r}")
        assert out.get("stop_reason", "").startswith("tool-call budget")
        try:
            await build_graph(http, base, mcp, tools, destructive, [], max_tool_calls=99).ainvoke(
                {"messages": [{"role": "user", "content": "order A-17?"}]}, {"configurable": {"thread_id": "loop2"}, "recursion_limit": 8})
            raise SystemExit("expected GraphRecursionError")
        except GraphRecursionError as e:
            print(f"without a tool budget, recursion_limit=8 is the backstop: GraphRecursionError ({str(e)[:60]}...)")
    print("\nall mcp_langgraph_agent self-checks passed")


def main() -> None:
    logging.getLogger("httpx").setLevel(logging.WARNING)                     # per-request INFO lines
    logging.getLogger("mcp").setLevel(logging.CRITICAL)                      # the expected tool traceback (stderr)
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
```

Output (one measured run; the per-call TTFT values vary, everything else is deterministic):

```text
MCP tools -> OpenAI tools: ['get_order', 'inventory_level', 'search_docs', 'issue_credit']; destructive (needs approval): ['issue_credit']
  get_order parameters schema: {"type": "object", "properties": {"order_id": {"title": "Order Id", "type": "string"}}, "required": ["order_id"], "title": "get_orderArguments"}
  ToolError (intended message)  -> isError=True: Error executing tool get_order: unknown order Z-1; order ids look like A-17
  unexpected ValueError         -> isError=True: Error executing tool inventory_level

run 1 (until a destructive tool needs approval):
  llm: finish=tool_calls ttft=3ms tool_calls=['get_order']
  mcp: get_order({'order_id': 'A-17'}) isError=False -> {"order_id": "A-17", "status": "delayed", "carrier_delay_days": 6}
  llm: finish=tool_calls ttft=3ms tool_calls=['search_docs']
  mcp: search_docs({'query': 'carrier delays credit'}) isError=False -> {"hits": ["[kb-102] Carrier delays over 5 days qualify for a 10 percen
  llm: finish=tool_calls ttft=3ms tool_calls=['issue_credit']
  paused: interrupt={'approve': [{'name': 'issue_credit', 'arguments': '{"order_id": "A-17", "pct": 10, "request_id": "conv-9:turn-1:credit"}'}]}

run 2 (resumed with the manager's approval):
  mcp: issue_credit({'order_id': 'A-17', 'pct': 10, 'request_id': 'conv-9:turn-1:credit'}) isError=False -> {"credit_id": "CR-001", "order_id": "A-17", "pct": 10, "created": true
  llm: finish=stop ttft=20ms tool_calls=[]
  final answer: Done: A-17 was delayed 6 days; a 10% credit was issued (": "CR-001", "order_id": "A-17", "pct": 10, "created": true})
  credits ledger: [{'credit_id': 'CR-001', 'order_id': 'A-17', 'pct': 10, 'created': True}]

stubborn model, tool budget 3: 7 trace events -> stop_reason='tool-call budget of 3 exhausted'
without a tool budget, recursion_limit=8 is the backstop: GraphRecursionError (Recursion limit of 8 reached without hitting a stop conditio...)

all mcp_langgraph_agent self-checks passed
```

What the run shows:

- **Run 1** stops at `issue_credit` because its `destructiveHint` routes it to `approval`, which calls
  `interrupt()`. The checkpointed state carries the exact arguments to approve.
- **Run 2** resumes with `Command(resume="approve")`. The credit is issued once, keyed by `request_id`, and the model
  answers from the tool results.
- **The stubborn model** (always `get_order`) is stopped by the tool budget with a structured reason. Without a
  budget, `recursion_limit=8` stops it with `GraphRecursionError`.

---

## 3. Production failure modes and P99 debugging

### F1 · Users see repeated text after a network blip

- **Signature:** duplicated prefixes in transcripts; retry counters rising with no user-visible error.
- **Root cause:** a retry after tokens were delivered, appended to what was shown.
- **Fix:** retry only before the first token; after it, `PartialStream` and replace-or-resume semantics in the UI.

### F2 · Truncated answers presented as complete

- **Root cause:** the client stops at EOF without checking `finish_reason` and `[DONE]`, or treats `length` as
  success.
- **Fix:** require the terminal markers; surface `length` and `content_filter` explicitly; alert on the truncation
  rate.

### F3 · Long-context requests time out, or hang forever

- **Root cause:** a fixed TTFT timeout below the prefill time of long prompts, or no TTFT timeout at all.
- **Fix:** a TTFT budget that scales with prompt tokens (§1.3) plus an idle timeout and a total deadline.

### F4 · A 429 storm turns into an outage

- **Signature:** request rate at the model server is a multiple of user traffic during an incident.
- **Root cause:** retries at several layers, without jitter, ignoring Retry-After.
- **Fix:** one retrying layer, full jitter, honoured Retry-After, retry budgets, and the breaker of File 01.

### F5 · Tool execution fails on malformed arguments

- **Root cause:** fragment assembly bugs (concatenating across indexes) or the model emitting invalid JSON.
- **Fix:** assemble by index, parse and validate against the schema before executing, and feed validation errors
  back as tool messages.

### F6 · An agent loops until the token budget is gone

- **Fix:** a per-turn tool budget with a structured stop reason, `recursion_limit` as the backstop, and the guards
  of File 06/01.

### F7 · A destructive tool ran without approval

- **Root cause:** policy keyed on annotations that were missing or false, or on tool names.
- **Fix:** a host-side allowlist of tools that need approval, defaulting to "needs approval" for unknown tools;
  approval bound to the exact arguments (File 06/03 §1.5).

### F8 · Local latency tests disagree with production

- **Root cause:** the measuring environment (Windows timer granularity, debug logging, a cold client and TLS setup on
  the first request).
- **Fix:** warm up, measure server-side and client-side together, and check the instrument's resolution.

---

## 4. FAANG L7 bar-raiser Q&A chains

### Q1 · "Design the client library every team uses to call our vLLM fleet."

- **L5 answer:** "A thin wrapper around the OpenAI SDK with retries."
- **Why L5 fails at scale:** naive retries duplicate streamed text, amplify 429 storms, and hide truncation. Fixed
  timeouts break long-context traffic. No usage accounting means no rate limiting or chargeback.
- **L7 principal defense:**
  1. Streaming-first API with explicit states: retrying (no tokens), streaming, complete, partial, failed.
  2. Budgets for connect, TTFT (scaled by prompt length), idle and total deadline.
  3. Retry only before the first token, with full jitter and Retry-After, under a retry budget; the breaker and
     fallback at the same layer.
  4. Mandatory usage capture, `finish_reason` checks, tool-call assembly and validation.
  5. OTel GenAI spans and metrics for TTFT, TPOT, tokens and finish reasons (File 04).

### Q2 · "The stream broke after 200 tokens. Do we retry?"

- **L5 answer:** "Yes, automatically."
- **L7 principal defense:**
  1. Not transparently: the user has seen 200 tokens, and a regenerated answer will differ.
  2. Either replace (clear and regenerate, the default for agents and tool calls), resume (send the partial as the
     assistant prefix where the server supports continuation), or show the partial with a "continue" control.
  3. Find out why it broke: preemption under KV pressure (Folder 02), a replica crash, or a proxy timeout (File
     06/02 F4).

### Q3 · "How do you wire MCP tools into a LangGraph agent safely?"

- **L7 principal defense:**
  1. Bind identity when the MCP client is created; never accept tenant or user arguments.
  2. Translate schemas and add `additionalProperties: false`; validate arguments before calling.
  3. Use a host-side policy for which tools need approval (default deny for unknown), with `interrupt()` approval
     bound to the arguments.
  4. Return tool errors as tool messages, normalized across SDKs, and never raw exceptions.
  5. Bound loops with a tool budget and `recursion_limit`, and checkpoint with a durable saver (File 06/03).

### Q4 · "How do you set timeouts for LLM calls?"

- **L5 answer:** "30 seconds."
- **L7 principal defense:** separate budgets.
  - **Connect:** about 1 s.
  - **TTFT:** `base + safety × prompt_tokens / prefill_rate`, from the deployment's measured prefill throughput;
    about 4.6 s for a 32K prompt on 70B/8×H100.
  - **Idle:** a few × p99 TPOT.
  - **Total:** derived from the caller's deadline.

  A single 30 s timeout is too long for short prompts (users wait on a dead replica) and too short for long
  reasoning outputs.

### Q5 · "We get 429 storms at peak."

- **L7 principal defense:**
  1. Stop amplification: one retry layer, jitter, Retry-After, retry budgets.
  2. Admission control at the gateway with token-aware rate limits per tenant (File 04), so overload is rejected
     early and fairly instead of inside the model server.
  3. Capacity: the goodput curve (Folder 02) tells you where the deployment saturates. Scale on queue depth and KV
     utilisation, not CPU.

---

## 5. Invariants checklist

- [ ] Streams are accepted only with `finish_reason` and `[DONE]`; `length` and `content_filter` are surfaced.
- [ ] Retries happen only before the first token, at one layer, with full jitter or Retry-After, under a retry
      budget.
- [ ] TTFT budgets scale with prompt length; idle and total deadlines exist.
- [ ] Tool-call fragments are assembled by index and validated before execution.
- [ ] Usage is requested and recorded for every call.
- [ ] MCP identity is bound at connection time; tool schemas reject unknown arguments.
- [ ] Tools needing approval are decided by host policy; approvals bind to arguments.
- [ ] Tool errors reach the model as sanitized tool messages; loops are bounded by a tool budget and
      `recursion_limit`.

## 6. References

1. OpenAI API reference: Chat Completions streaming, `stream_options.include_usage`, tool calls (the de facto wire
   format; ⚠ verify field details against your server).
2. vLLM documentation: OpenAI-compatible server (chat completions, streaming, tool calling, continuation of the final
   message) (⚠ verify for your version).
3. MCP Python SDK 2.3.0: `MCPServer`, `Client`, `ToolError`, `ToolAnnotations`.
4. LangGraph 1.2.18: `StateGraph`, `interrupt`, `Command`, `recursion_limit`, `InMemorySaver`.
5. M. Brooker. *Exponential Backoff and Jitter.* AWS Architecture Blog, 2015.
6. Google SRE Book, chapter 22 *Addressing Cascading Failures* (retry budgets and amplification).
