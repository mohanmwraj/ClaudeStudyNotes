# 01 · Agentic Design Patterns: ReAct, Plan-and-Execute, Reflection, and Tool DAGs

> **Folder:** `06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/` · **File 1 of 3**
> **Anchoring research:** Yao et al., *ReAct* (ICLR 2023) · Xu et al., *ReWOO* (2023) · Kim et al., *An LLM
> Compiler for Parallel Function Calling* (ICML 2024) · Shinn et al., *Reflexion* (NeurIPS 2023) · Madaan et al.,
> *Self-Refine* (NeurIPS 2023) · Huang et al., *Large Language Models Cannot Self-Correct Reasoning Yet* (ICLR 2024) ·
> Liu et al., *Lost in the Middle* (TACL 2024) · Anthropic, *Building effective agents* (2024).
> **Code baseline:** Python 3.10+ (CPython 3.14.5, stdlib only) · Java 21 (JDK 25.0.4, `--release 21`, no
> dependencies).
> **Previous folder:** [05 · Dynamic tool discovery and context bloat](../05-Model-Context-Protocol-MCP-Architecture/03-dynamic-tool-discovery-sampling-roots-and-context-bloat-mitigation.md) ·
> **Next:** [02 · Spring AI, LangChain4j, virtual threads, SSE and advisors](02-spring-ai-langchain4j-virtual-threads-sse-streaming-and-advisors.md)

---

## 0. The thesis in one paragraph

An agent is a **control loop whose controller is a stochastic model**. Everything hard about agents follows from
three properties of that loop:

- **It is sequential.** ReAct pays one model call per tool step, so latency is the *sum* of every step.
- **Its context grows.** Each step appends an observation and the model re-reads all of it, so cumulative prompt
  tokens grow **quadratically** with steps (40 steps: 203K tokens; with compaction: 49K).
- **It does not reliably terminate.** A model that "retries" a 429 forever burned 108K tokens in the lab; a
  three-line guard stopped it at 1,280.

The production patterns are all ways to take control back from the model:

- **plan-and-execute** turns the loop into a validated DAG that runs at critical-path latency (3,190 → 1,300 ms);
- **guards** bound steps, tokens, repeats and wall time;
- **idempotency classes** decide what a retry may touch;
- **reflection** helps only when the critic has an *external* signal.

The L7 framing, which Anthropic's taxonomy also makes: **prefer a workflow (code decides the control flow) and use
an agent (the model decides) only where the path genuinely cannot be known in advance.**

---

## 1. First principles: the agent as a control loop

### 1.1 The loop

Every agent framework, from LangGraph to Spring AI's tool-calling advisor, implements this loop:

```text
context = system_prompt + tools + user_message
repeat:
    step = model(context)                  # one prefill of the whole context + a short decode
    if step is a final answer: return it
    observation = execute(step.tool, step.args)
    context += step + observation          # append-only
```

ReAct (Yao et al.) made the `Thought → Action → Observation` interleaving explicit: the model writes its reasoning
before each action, which improves action choice and makes traces debuggable. Function-calling APIs are the same
loop with the action emitted as structured JSON instead of parsed text.

### 1.2 Latency: the sum of the steps

Let `m` be the model-call time per step and `t_i` the latency of tool `i`. For a task needing `n` tool calls:

```text
L_ReAct = Σ_{i=1..n} (m + t_i) + m_final
L_plan  = m_plan + CP(DAG) + m_synth            CP = critical path = max over root-to-leaf paths of Σ t_i
```

With the lab's tools (120, 80, 80, 300, 150, 60 ms) and `m = 400 ms`:

- sequential ReAct: `790 + 6 × 400 = 3,190 ms`;
- plan-and-execute: `400 + 500 + 400 = 1,300 ms`, because the critical path `orders → o17 → eta` is 500 ms and the
  other branches overlap it.

The saving has two independent sources. Tool latency drops from the sum (790) to the critical path (500), and model
calls drop from `n` to 2. The second dominates whenever `m ≫ t`, which is the usual case: a 400 ms model call is a
short thought on a fast model, and a reasoning model's step is often seconds.

`m` itself is a Folder 01 quantity: `m ≈ TTFT(context) + k × TPOT`, where `k` is the tokens of thought plus the
tool call. The context grows every step, so TTFT grows too unless the prefix is cached (§1.3).

### 1.3 Tokens: the quadratic context

If the context starts at `c₀` tokens and each step appends `Δ` tokens, step `i` reads `c₀ + iΔ`. Over `n` steps:

```text
T(n) = Σ_{i=0..n-1} (c₀ + iΔ) = n·c₀ + Δ·n(n−1)/2
```

With `c₀ = 200`, `Δ = 250` and `n = 40`: `8,000 + 250 × 780 = 203,000` tokens, exactly what the lab prints. The
`n²/2` term is 96% of it. Summarizing history into ~600 tokens whenever the context passes 2K caps the per-step
read and makes `T(n)` linear: **49,450** tokens, 4.1× less.

Two refinements separate an L7 answer from the formula:

1. **Prefix caching changes the compute, not the memory.** The loop is append-only, so with a prefix cache
   (Folder 01 File 03) each step prefills only `Δ` new tokens and compute becomes linear. But KV residency still
   grows linearly. At step 40 the uncompacted session holds 10,200 tokens: **3.11 GiB of KV** for Llama-3-70B
   (327,680 B/token), against 0.67 GiB at the compacted peak of 2,200 tokens (the moment before the first
   compaction). On 8×H100 (1,356,942 KV tokens) that is **133 vs 616 concurrent sessions**. Compaction is a capacity lever, not just a cost lever. Decode attention
   per token also grows with context, so TPOT degrades with the uncompacted session.
2. **Compaction breaks the prefix.** Rewriting history invalidates the cache from the compaction point, so the next
   step re-prefills the new summary. Compact rarely and at a threshold, never every step, and keep the system
   prompt and tool block *before* the compacted region so they stay cached (Folder 05 File 03 §3.4).

Billing follows the same shape: providers that discount cached input still bill it, so an uncompacted agent loop is
a quadratic bill with a discount factor (⚠ verify per-provider cache pricing).

Long contexts also cost accuracy. Liu et al. (*Lost in the Middle*) showed retrieval accuracy drops for facts in the
middle of long contexts, so a 40-step trace with the key observation at step 7 is a worse prompt as well as a more
expensive one.

### 1.4 Reliability: errors compound

If each step is correct with probability `p` and a task needs `n` correct steps with no recovery, success is `pⁿ`:

| p \ n | 5 | 10 | 20 | 50 |
|---|---|---|---|---|
| 0.99 | 0.951 | 0.904 | 0.818 | 0.605 |
| 0.95 | 0.774 | 0.599 | 0.358 | 0.077 |
| 0.90 | 0.590 | 0.349 | 0.122 | 0.005 |

A 95%-reliable step is a 36% task at 20 steps. This is the strongest first-principles argument for:

- **short loops**: make each model decision cover more work (a plan) and push deterministic work into code;
- **verification**: a validator that catches a bad step turns "fail" into "retry", which raises the effective `p`;
- **checkpoints**: durable state means a failure at step 18 resumes at 18, not at 1 (File 03).

### 1.5 Termination: the loop has no natural bound

A model asked to accomplish something will keep trying. Observed loop triggers in production:

- a tool returns an error the model believes is transient (429, timeout), so it retries forever;
- two tools disagree and the model alternates between them;
- the model "verifies" its work by calling the same read tool repeatedly;
- a planner emits a cycle.

The guard is control-theory common sense: **bound every resource the loop consumes.**

- step count and wall-clock deadline;
- token budget (cumulative prompt plus completion tokens);
- repeated identical calls: hash `(tool, canonicalized args)`;
- no progress: identical observations several times in a row.

The lab's stubborn policy runs 50 steps, 25 s and **108,000 prompt tokens** when only `max_steps` stops it. The
guard trips on the fourth identical call: 3 steps, 1.5 s, **1,280 tokens** (84× less). When a guard trips, the
agent must return a *structured* failure ("stopped: flaky_api returned 429 three times"), so the caller can escalate
instead of receiving a hallucinated answer.

---

## 2. The patterns

### 2.1 Workflows vs agents

Anthropic's *Building effective agents* draws the line that matters in design reviews:

- **Workflows**: the code fixes the control flow and the model fills in steps. Variants are prompt chaining,
  routing, parallelization (sectioning or voting), orchestrator-workers and evaluator-optimizer.
- **Agents**: the model chooses the next step at run time.

Workflows are testable, cheaper and predictable. Use an agent where the number and kind of steps truly depend on
what the tools return (open-ended research, debugging, ticket triage across unknown systems), and wrap it in a
workflow for everything else (authentication, policy, side effects, delivery).

### 2.2 ReAct

**Mechanics:** interleave thought, action and observation. One model call per step.

**Use when:** the next step depends on the last observation and steps are few.

**Weaknesses:** sequential latency, quadratic context, and loops. In the lab the scripted ReAct agent answers in 4
tool steps, 2,160 ms of virtual latency and 1,771 cumulative prompt tokens. Every additional step adds both latency
and the full context again.

### 2.3 Plan-and-execute, ReWOO and LLMCompiler

**Mechanics:** a planner call emits the whole tool plan, with placeholders for results of earlier steps (ReWOO's
`#E1`, LLMCompiler's task-fetching unit). An executor runs it *without the model*, in parallel where the
dependencies allow. A solver call turns results into the answer.

- ReWOO (Xu et al.) decouples reasoning from observations and reports large token savings on multi-hop QA (⚠ verify
  the exact factor).
- LLMCompiler (Kim et al.) adds a DAG scheduler that dispatches tasks as their dependencies resolve, plus a
  *joiner* that decides whether to finish or replan, and reports latency speedups up to several times over ReAct
  (⚠ verify the paper's figures).

**The weakness is plan staleness.** A plan is a bet on what the tools will return. When `get_order` says the order
was cancelled, the steps after it are wrong. Production planners therefore:

1. validate the plan before any side effect: known tools, argument schemas, entitlements, no unknown dependencies,
   no cycles (the lab rejects a planner-emitted cycle before executing anything);
2. execute until a step fails or returns something outside the plan's assumptions;
3. replan from the current state with the results so far, under a replan budget.

### 2.4 Reflection: Reflexion and Self-Refine

**Mechanics:** generate, critique, revise. Self-Refine (Madaan et al.) iterates within one task; Reflexion (Shinn
et al.) stores verbal lessons across trials.

**The caveat that matters:** Huang et al. showed that *intrinsic* self-correction, where the model critiques
itself with no external feedback, does not reliably improve reasoning and can make answers worse. Reflection pays
off when the critic has a real signal:

- unit tests, compilers, type checkers and linters for code;
- schema validators and business-rule checks for structured output;
- retrieval checks for grounding ("is every claim supported by a cited chunk?");
- a different, stronger, or specialised judge model, calibrated against human labels.

**Stop conditions are the design.** The lab's critic improves with diminishing returns (0.55 → 0.846). With a 0.85
threshold it never succeeds, so convergence detection (improvement < 0.005) stops it after 6 rounds and 9,000
tokens. A 0.80 threshold stops at round 3 (4,500 tokens). Without one of these, reflection is an expensive loop.

### 2.5 Multi-agent systems

A supervisor routes to specialist agents, or agents hand off to each other. What it buys:

- separate contexts, so each specialist sees a short prompt;
- parallel exploration (research fan-out);
- separate permissions per agent, which helps containment (Folder 05 File 02).

What it costs:

- **tokens multiply.** Anthropic reported its multi-agent research system used roughly 15× the tokens of a chat
  interaction (⚠ verify);
- **every hand-off is lossy serialization.** The sub-agent sees a summary, not the parent's context;
- **failures multiply** (§1.4), and debugging needs distributed tracing across agents.

Use it for breadth-first problems where parallel exploration is the point. A single agent with good tools is
usually better for depth-first tasks.

---

## 3. Executing tool DAGs safely

### 3.1 Idempotency classes decide what a retry may touch

| Class | Examples | Automatic retry? |
|---|---|---|
| Read-only | search, get, list | Yes, with backoff and a budget |
| Idempotent write | upsert by key, a charge with an idempotency key | Yes, with the *same* key |
| Non-idempotent | send email, charge without a key, post a message | **No.** Reconcile first: did it happen? |

The executor needs this class *in the plan*, not in the model's head. The lab's charge step fails with "gateway
reset after charge request sent". That is the ambiguous case: the request may have been processed. The executor
does not retry it (1 attempt), skips the dependent `email` step, and still runs the independent `audit` branch
under continue-on-error.

### 3.2 Timeouts, deadlines and cancellation

- **Per-step timeouts** stop one slow tool from consuming the whole budget.
- **A global deadline** is propagated: each step gets `min(step timeout, deadline − elapsed)`. A step that starts
  after the deadline is skipped, not started.
- **Cancellation is local.** Interrupting a virtual thread stops *waiting*; it does not undo a remote side effect.
  A timed-out write is in the ambiguous state of §3.1.

### 3.3 Fan-out tail latency

A DAG step waiting on `k` parallel tools finishes at the *maximum* of their latencies. If each tool independently
exceeds its P99 with probability 0.01, then at least one of `k` does so with probability `1 − 0.99ᵏ`: 5.9% for
`k = 6`, 18.2% for `k = 20`. **A parallel agent's P99 is set by its tools' P99.9.** The levers are the same as any
fan-out service: per-tool timeouts with partial results, hedged requests for idempotent reads, and dropping
optional branches under deadline pressure (Folder 04 File 02's hedged retriever).

### 3.4 Failure policies

- **Fail-fast:** a failure aborts steps that have not started yet. Use it when the answer is useless without every
  branch.
- **Continue-on-error:** independent branches complete and the result is partial and labelled. Use it when partial
  answers have value, and always for audit or compensation steps.
- **Dependents of a failed step are always skipped**, with the reason recorded, never run with missing inputs.

---

## 4. Production code blueprints

### 4.1 Python: the patterns as state machines, with their costs measured

The model is a scripted policy so the run is deterministic and the costs are exact. Swap `react_policy` for a real
model call and the loop, guards, scheduler and stop conditions are unchanged.

```python
"""agent_patterns.py - agentic design patterns as state machines, with their failure modes measured (stdlib only).

Models are SCRIPTED policies (deterministic stand-ins for an LLM's next-action choice) so every run is reproducible;
time is virtual. Covered: ReAct, the infinite tool loop and its guards, plan-and-execute DAG scheduling vs sequential
ReAct latency, reflection with convergence stops, and context growth (quadratic token cost) vs compaction.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field


# ---------------------------------------------------------------------- tools (virtual latency in ms)
TOOLS = {
    "search_orders": (120, lambda a: {"orders": ["A-17", "A-18"]} if a.get("customer") == "acme" else {"orders": []}),
    "get_order": (80, lambda a: {"id": a["id"], "status": "delayed" if a["id"] == "A-17" else "shipped"}),
    "carrier_eta": (300, lambda a: {"id": a["id"], "eta_days": 3}),
    "refund_policy": (60, lambda a: {"max_refund_pct": 20}),
    "inventory": (150, lambda a: {"sku": a["sku"], "on_hand": 0}),
    "flaky_api": (100, lambda a: {"error": "429 rate limited, retry later"}),
}


def call(tool: str, args: dict):
    ms, fn = TOOLS[tool]
    return ms, fn(args)


# ---------------------------------------------------------------------- ReAct
@dataclass
class Step:
    thought: str
    action: str | None
    args: dict = field(default_factory=dict)
    final: str | None = None


def react_policy(history: list) -> Step:
    """Scripted 'model': reasons over observations so far and picks the next action."""
    obs = [h[2] for h in history]
    if not obs:
        return Step("find the customer's orders", "search_orders", {"customer": "acme"})
    if len(obs) == 1:
        return Step("check the first order", "get_order", {"id": obs[0]["orders"][0]})
    if obs[-1].get("status") == "delayed" and len(obs) == 2:
        return Step("it is delayed; ask the carrier", "carrier_eta", {"id": "A-17"})
    if len(obs) == 3:
        return Step("what refund can I offer?", "refund_policy", {})
    return Step("enough information", None, final="A-17 is delayed ~3 days; offer up to a 20% refund.")


def run_react(policy, max_steps: int = 20, guard=None):
    history, t_ms, tokens, ctx_tokens = [], 0, 0, 200        # 200-token system prompt
    for i in range(max_steps):
        tokens += ctx_tokens                                  # every step re-reads the whole context
        step = policy(history)
        if step.final:
            return {"answer": step.final, "steps": i, "latency_ms": t_ms, "tokens": tokens, "stopped": "final answer"}
        if guard and (reason := guard.check(step.action, step.args)):
            return {"answer": None, "steps": i, "latency_ms": t_ms, "tokens": tokens, "stopped": reason}
        ms, out = call(step.action, step.args)
        t_ms += ms + 400                                      # + one model call (~400 ms) per step
        obs_tokens = len(json.dumps(out)) // 4 + 40
        ctx_tokens += 30 + obs_tokens                         # thought + action + observation appended
        history.append((step.action, step.args, out))
        if guard:
            guard.observe(out)
    return {"answer": None, "steps": max_steps, "latency_ms": t_ms, "tokens": tokens, "stopped": "max_steps"}


# ---------------------------------------------------------------------- the infinite loop and its guards
def stubborn_policy(history: list) -> Step:
    """A model that 'retries' a failing tool forever - the classic agent loop."""
    return Step("the API failed, retry", "flaky_api", {"q": "status"})


class LoopGuard:
    """Trip on: repeated identical calls, observations that stop changing, or a token budget."""

    def __init__(self, max_repeats: int = 3, token_budget: int = 20_000):
        self.max_repeats, self.token_budget = max_repeats, token_budget
        self.calls: dict[str, int] = {}
        self.last_obs = None
        self.same_obs = 0
        self.spent = 0

    def check(self, tool, args) -> str | None:
        key = hashlib.sha256(json.dumps([tool, args], sort_keys=True).encode()).hexdigest()
        self.calls[key] = self.calls.get(key, 0) + 1
        if self.calls[key] > self.max_repeats:
            return f"guard: {tool} called {self.calls[key] - 1}x with identical args"
        if self.same_obs >= self.max_repeats:
            return "guard: no progress (identical observations)"
        return None

    def observe(self, obs) -> None:
        self.same_obs = self.same_obs + 1 if obs == self.last_obs else 0
        self.last_obs = obs


# ---------------------------------------------------------------------- plan-and-execute DAG
PLAN = {   # step -> (tool, args, depends_on)
    "orders": ("search_orders", {"customer": "acme"}, []),
    "o17": ("get_order", {"id": "A-17"}, ["orders"]),
    "o18": ("get_order", {"id": "A-18"}, ["orders"]),
    "eta": ("carrier_eta", {"id": "A-17"}, ["o17"]),
    "stock": ("inventory", {"sku": "SKU-9"}, []),
    "policy": ("refund_policy", {}, []),
}


def topo(plan: dict) -> list[str]:
    indeg = {k: len(v[2]) for k, v in plan.items()}
    ready = sorted(k for k, d in indeg.items() if d == 0)
    order = []
    while ready:
        k = ready.pop(0)
        order.append(k)
        for j, v in plan.items():
            if k in v[2]:
                indeg[j] -= 1
                if indeg[j] == 0:
                    ready.append(j)
        ready.sort()
    if len(order) != len(plan):
        raise ValueError("plan has a cycle")
    return order


def schedule(plan: dict, parallel: bool) -> tuple[int, dict]:
    """Virtual-time execution: with parallelism each step starts when its deps finish (critical path)."""
    finish, clock = {}, 0
    for k in topo(plan):
        tool, args, deps = plan[k]
        ms = TOOLS[tool][0]
        start = max((finish[d] for d in deps), default=0) if parallel else clock
        finish[k] = start + ms
        clock = finish[k]
    return max(finish.values()), finish


# ---------------------------------------------------------------------- reflection
def reflect(max_iters: int, threshold: float = 0.85):
    """Generate -> critique -> revise. The critic's score improves with diminishing returns, then plateaus."""
    quality = [0.55, 0.72, 0.81, 0.84, 0.845, 0.846]
    trace, tokens = [], 0
    for i in range(max_iters):
        q = quality[min(i, len(quality) - 1)]
        tokens += 1500                                        # draft + critique per round
        trace.append(round(q, 3))
        if q >= threshold:
            return trace, tokens, "critic satisfied"
        if i > 0 and abs(trace[-1] - trace[-2]) < 0.005:
            return trace, tokens, "converged (improvement < 0.005)"
    return trace, tokens, "max_iters"


def main() -> None:
    r = run_react(react_policy)
    print("== ReAct (Thought -> Action -> Observation) ==")
    print(f"  {r['stopped']} after {r['steps']} tool steps: {r['answer']!r}")
    print(f"  virtual latency {r['latency_ms']} ms, cumulative prompt tokens {r['tokens']:,}")

    naive = run_react(stubborn_policy, max_steps=50)
    guarded = run_react(stubborn_policy, max_steps=50, guard=LoopGuard())
    print("\n== The infinite tool loop (a model that retries a 429 forever) ==")
    print(f"  naive : stopped by {naive['stopped']} after {naive['steps']} steps, {naive['latency_ms'] / 1000:.1f} s, "
          f"{naive['tokens']:,} prompt tokens")
    print(f"  guarded: {guarded['stopped']} after {guarded['steps']} steps, {guarded['latency_ms'] / 1000:.1f} s, "
          f"{guarded['tokens']:,} prompt tokens")
    assert guarded["steps"] <= 4 and naive["tokens"] > 20 * guarded["tokens"]

    seq, _ = schedule(PLAN, parallel=False)
    par, fin = schedule(PLAN, parallel=True)
    crit = ["orders", "o17", "eta"]
    print("\n== Plan-and-execute: one planner call, then a DAG of tool steps ==")
    print(f"  topological order {topo(PLAN)}")
    print(f"  sequential execution {seq} ms; parallel DAG {par} ms = critical path {' -> '.join(crit)} "
          f"({sum(TOOLS[PLAN[c][0]][0] for c in crit)} ms)")
    react_like = seq + 400 * len(PLAN)                        # ReAct pays one model call per step
    print(f"  model calls: ReAct-style {len(PLAN)} (+{400 * len(PLAN)} ms) vs plan-and-execute 2 (plan + synthesize) "
          f"-> {react_like} ms vs {par + 800} ms end to end")
    assert par == sum(TOOLS[PLAN[c][0]][0] for c in crit) and par < seq
    bad = dict(PLAN, orders=("search_orders", {"customer": "acme"}, ["eta"]))
    try:
        topo(bad)
        raise SystemExit("cycle not detected")
    except ValueError as e:
        print(f"  planner emitted a cycle (orders <- eta <- o17 <- orders): rejected before execution ({e})")

    print("\n== Reflection (generate -> critique -> revise) ==")
    for iters, thr in ((10, 0.85), (10, 0.80), (2, 0.85)):
        trace, tokens, why = reflect(iters, thr)
        print(f"  max_iters={iters:2d} threshold={thr}: quality {trace} -> {why}, {tokens:,} tokens")

    print("\n== Context growth: cumulative prompt tokens over a long loop ==")
    for compaction in (False, True):
        ctx, total = 200, 0
        for step in range(40):
            total += ctx
            ctx += 250                                        # each observation appends ~250 tokens
            if compaction and ctx > 2_000:
                ctx = 200 + 600                               # summarize history into ~600 tokens
        print(f"  {'with compaction' if compaction else 'no compaction  '}: 40 steps -> {total:,} prompt tokens")
    print("\nall agent pattern self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== ReAct (Thought -> Action -> Observation) ==
  final answer after 4 tool steps: 'A-17 is delayed ~3 days; offer up to a 20% refund.'
  virtual latency 2160 ms, cumulative prompt tokens 1,771

== The infinite tool loop (a model that retries a 429 forever) ==
  naive : stopped by max_steps after 50 steps, 25.0 s, 108,000 prompt tokens
  guarded: guard: flaky_api called 3x with identical args after 3 steps, 1.5 s, 1,280 prompt tokens

== Plan-and-execute: one planner call, then a DAG of tool steps ==
  topological order ['orders', 'o17', 'eta', 'o18', 'policy', 'stock']
  sequential execution 790 ms; parallel DAG 500 ms = critical path orders -> o17 -> eta (500 ms)
  model calls: ReAct-style 6 (+2400 ms) vs plan-and-execute 2 (plan + synthesize) -> 3190 ms vs 1300 ms end to end
  planner emitted a cycle (orders <- eta <- o17 <- orders): rejected before execution (plan has a cycle)

== Reflection (generate -> critique -> revise) ==
  max_iters=10 threshold=0.85: quality [0.55, 0.72, 0.81, 0.84, 0.845, 0.846] -> converged (improvement < 0.005), 9,000 tokens
  max_iters=10 threshold=0.8: quality [0.55, 0.72, 0.81] -> critic satisfied, 4,500 tokens
  max_iters= 2 threshold=0.85: quality [0.55, 0.72] -> max_iters, 3,000 tokens

== Context growth: cumulative prompt tokens over a long loop ==
  no compaction  : 40 steps -> 203,000 prompt tokens
  with compaction: 40 steps -> 49,450 prompt tokens

all agent pattern self-checks passed
```

### 4.2 Java 21: a plan-and-execute runtime for tool DAGs

The executor validates the plan with Kahn's algorithm before any step runs, then schedules each step on a virtual
thread as soon as its dependencies finish. Each attempt has a timeout, and retries happen only for steps declared
idempotent, with exponential backoff. The `LoopGuard` is the Java twin of the Python guard, for ReAct-style loops
that run outside a DAG.

```java
// AgentDagExecutor.java - Java 21 plan-and-execute runtime for agent tool DAGs: plans validated before execution
// (unknown deps, cycles), steps run on virtual threads as soon as their dependencies finish, per-step timeouts and
// retries for IDEMPOTENT steps only, fail-fast vs continue-on-error policies, a global deadline, and a LoopGuard for
// ReAct-style loops (repeated identical calls, step and token budgets).
// Build & self-test:  javac --release 21 -Xlint:all -Werror -d out AgentDagExecutor.java
//                     java -ea -cp out dev.l7.ai.inference.AgentDagExecutor
package dev.l7.ai.inference;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;

public final class AgentDagExecutor implements AutoCloseable {

    public record StepSpec(String id, List<String> deps, Duration timeout, int maxAttempts, boolean idempotent,
                           Function<Map<String, Object>, Object> action) {}

    public enum Policy { FAIL_FAST, CONTINUE_ON_ERROR }

    public sealed interface Outcome permits Ok, Failed, Skipped {}

    public record Ok(Object value, int attempts, long startMs, long endMs) implements Outcome {}

    public record Failed(String error, int attempts) implements Outcome {}

    public record Skipped(String reason) implements Outcome {}

    private final ExecutorService vt = Executors.newVirtualThreadPerTaskExecutor();

    /** Kahn's algorithm: reject unknown dependencies and cycles BEFORE any side effect runs. */
    static List<String> topo(Map<String, StepSpec> plan) {
        Map<String, Integer> indeg = new HashMap<>();
        plan.values().forEach(s -> {
            for (String d : s.deps()) if (!plan.containsKey(d)) throw new IllegalArgumentException(s.id() + " depends on unknown " + d);
            indeg.put(s.id(), s.deps().size());
        });
        ArrayDeque<String> ready = new ArrayDeque<>(plan.keySet().stream().filter(k -> indeg.get(k) == 0).sorted().toList());
        List<String> order = new ArrayList<>();
        while (!ready.isEmpty()) {
            String k = ready.poll();
            order.add(k);
            plan.values().stream().filter(s -> s.deps().contains(k)).map(StepSpec::id).sorted()
                    .forEach(j -> { if (indeg.merge(j, -1, Integer::sum) == 0) ready.add(j); });
        }
        if (order.size() != plan.size()) throw new IllegalArgumentException("plan has a cycle");
        return order;
    }

    public Map<String, Outcome> run(Map<String, StepSpec> plan, Policy policy, Duration deadline) {
        topo(plan);
        long t0 = System.nanoTime();
        AtomicBoolean abort = new AtomicBoolean();
        Map<String, CompletableFuture<Outcome>> futures = new ConcurrentHashMap<>();
        Map<String, Outcome> results = new ConcurrentHashMap<>();
        for (String id : topo(plan)) {
            StepSpec s = plan.get(id);
            CompletableFuture<?>[] deps = s.deps().stream().map(futures::get).toArray(CompletableFuture[]::new);
            futures.put(id, CompletableFuture.allOf(deps).thenApplyAsync(v -> {
                for (String d : s.deps()) {
                    if (!(results.get(d) instanceof Ok)) return new Skipped("dependency " + d + " did not succeed");
                }
                if (abort.get()) return new Skipped("fail-fast: an earlier step failed");
                long left = deadline.toMillis() - (System.nanoTime() - t0) / 1_000_000;
                if (left <= 0) return new Skipped("global deadline exceeded");
                Map<String, Object> inputs = new LinkedHashMap<>();
                for (String d : s.deps()) inputs.put(d, ((Ok) results.get(d)).value());
                Outcome o = attempt(s, inputs, Math.min(left, s.timeout().toMillis()), t0);
                if (o instanceof Failed && policy == Policy.FAIL_FAST) abort.set(true);
                return o;
            }, vt).whenComplete((o, e) -> results.put(id, o != null ? o : new Failed(String.valueOf(e), 0))));
        }
        CompletableFuture.allOf(futures.values().toArray(CompletableFuture[]::new)).join();
        Map<String, Outcome> ordered = new LinkedHashMap<>();
        topo(plan).forEach(k -> ordered.put(k, results.get(k)));
        return ordered;
    }

    /** Timeout per attempt; retries ONLY for idempotent steps (a retried non-idempotent call may act twice). */
    private Outcome attempt(StepSpec s, Map<String, Object> inputs, long budgetMs, long t0) {
        int max = s.idempotent() ? s.maxAttempts() : 1;
        String last = "";
        for (int a = 1; a <= max; a++) {
            long start = (System.nanoTime() - t0) / 1_000_000;
            Future<Object> f = vt.submit(() -> s.action().apply(inputs));
            try {
                Object v = f.get(budgetMs, TimeUnit.MILLISECONDS);
                return new Ok(v, a, start, (System.nanoTime() - t0) / 1_000_000);
            } catch (TimeoutException e) {
                f.cancel(true);                                         // interrupt the virtual thread
                last = "timeout after " + budgetMs + " ms";
            } catch (Exception e) {
                last = Objects.requireNonNullElse(e.getCause(), e).getMessage();
            }
            if (a < max) sleepQuietly(20L * (1L << (a - 1)));            // exponential backoff
        }
        return new Failed(last, max);
    }

    static void sleepQuietly(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("interrupted");
        }
    }

    @Override
    public void close() { vt.close(); }

    // ------------------------------------------------------------------ ReAct loop guard
    public static final class LoopGuard {
        private final int maxRepeats, maxSteps;
        private final long tokenBudget;
        private final Map<String, Integer> seen = new HashMap<>();
        private int steps;
        private long tokens;

        public LoopGuard(int maxRepeats, int maxSteps, long tokenBudget) {
            this.maxRepeats = maxRepeats;
            this.maxSteps = maxSteps;
            this.tokenBudget = tokenBudget;
        }

        /** Returns a stop reason, or null to continue. Args are canonicalized by sorting keys. */
        public String check(String tool, Map<String, Object> args, long promptTokens) {
            steps++;
            tokens += promptTokens;
            String key = tool + new java.util.TreeMap<>(args);
            int n = seen.merge(key, 1, Integer::sum);
            if (n > maxRepeats) return "repeated identical call x" + (n - 1) + ": " + key;
            if (steps > maxSteps) return "step budget " + maxSteps + " exhausted";
            if (tokens > tokenBudget) return "token budget " + tokenBudget + " exhausted";
            return null;
        }
    }

    // ------------------------------------------------------------------ self-test
    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    static StepSpec step(String id, List<String> deps, long ms) {
        return new StepSpec(id, deps, Duration.ofSeconds(2), 3, true, in -> {
            sleepQuietly(ms);
            return id + "-done";
        });
    }

    public static void main(String[] args) {
        Map<String, StepSpec> plan = new LinkedHashMap<>();
        plan.put("orders", step("orders", List.of(), 120));
        plan.put("o17", step("o17", List.of("orders"), 80));
        plan.put("o18", step("o18", List.of("orders"), 80));
        plan.put("eta", step("eta", List.of("o17"), 300));
        plan.put("stock", step("stock", List.of(), 150));
        plan.put("policy", step("policy", List.of(), 60));
        try (AgentDagExecutor ex = new AgentDagExecutor()) {
            ex.run(Map.of("w", step("w", List.of(), 5)), Policy.FAIL_FAST, Duration.ofSeconds(5));   // warm up
            long t0 = System.nanoTime();
            Map<String, Outcome> r = ex.run(plan, Policy.FAIL_FAST, Duration.ofSeconds(5));
            long ms = (System.nanoTime() - t0) / 1_000_000;
            long sum = 120 + 80 + 80 + 300 + 150 + 60;
            System.out.printf("DAG: %d ms wall vs %d ms if sequential (critical path orders->o17->eta = 500 ms)%n", ms, sum);
            r.forEach((k, v) -> System.out.printf("  %-7s %s%n", k, v));
            check(r.values().stream().allMatch(o -> o instanceof Ok) && ms < 0.8 * sum, "parallel DAG");

            AtomicInteger tries = new AtomicInteger();
            Map<String, StepSpec> flaky = Map.of("fetch", new StepSpec("fetch", List.of(), Duration.ofSeconds(1), 3, true, in -> {
                if (tries.incrementAndGet() < 3) throw new IllegalStateException("503 from upstream");
                return "ok";
            }));
            Outcome f = ex.run(flaky, Policy.FAIL_FAST, Duration.ofSeconds(5)).get("fetch");
            System.out.println("idempotent flaky step: " + f);
            check(f instanceof Ok ok && ok.attempts() == 3, "retries for idempotent steps");

            AtomicInteger charges = new AtomicInteger();
            Map<String, StepSpec> pay = new LinkedHashMap<>();
            pay.put("charge", new StepSpec("charge", List.of(), Duration.ofSeconds(1), 3, false, in -> {
                charges.incrementAndGet();
                throw new IllegalStateException("gateway reset after charge request sent");
            }));
            pay.put("email", step("email", List.of("charge"), 10));
            pay.put("audit", step("audit", List.of(), 30));
            Map<String, Outcome> ff = ex.run(pay, Policy.FAIL_FAST, Duration.ofSeconds(5));
            Map<String, Outcome> ce = ex.run(pay, Policy.CONTINUE_ON_ERROR, Duration.ofSeconds(5));
            System.out.println("non-idempotent charge (fail-fast): " + ff);
            System.out.println("continue-on-error: audit=" + ce.get("audit").getClass().getSimpleName()
                    + ", email=" + ce.get("email") + "; charge attempts total=" + charges.get());
            check(ff.get("charge") instanceof Failed fl && fl.attempts() == 1 && ff.get("email") instanceof Skipped, "no retry, dependents skipped");
            check(ce.get("audit") instanceof Ok && charges.get() == 2, "independent branch still runs; never double-charged per run");

            Map<String, StepSpec> slow = Map.of("slow", new StepSpec("slow", List.of(), Duration.ofMillis(100), 2, true, in -> {
                sleepQuietly(1_000);
                return "late";
            }));
            Outcome to = ex.run(slow, Policy.FAIL_FAST, Duration.ofSeconds(5)).get("slow");
            System.out.println("slow step with a 100 ms timeout: " + to);
            check(to instanceof Failed tf && tf.error().startsWith("timeout"), "timeouts");

            Map<String, StepSpec> cyc = new LinkedHashMap<>();
            cyc.put("a", step("a", List.of("b"), 1));
            cyc.put("b", step("b", List.of("a"), 1));
            try {
                ex.run(cyc, Policy.FAIL_FAST, Duration.ofSeconds(1));
                check(false, "cycle must be rejected");
            } catch (IllegalArgumentException e) {
                System.out.println("planner emitted a cycle: rejected before execution (" + e.getMessage() + ")");
            }
        }
        LoopGuard g = new LoopGuard(3, 25, 50_000);
        String stop = null;
        int i = 0;
        while (stop == null) stop = g.check("flaky_api", Map.of("q", "status"), 600 + 250L * i++);
        System.out.println("ReAct loop guard: stopped at step " + i + " -> " + stop);
        check(i == 4, "guard trips on the 4th identical call");
        System.out.println("all AgentDagExecutor self-checks passed");
    }
}
```

Output (one measured run on the i5-11260H; the millisecond figures vary by a few ms, and the invariants are
asserted):

```text
DAG: 505 ms wall vs 790 ms if sequential (critical path orders->o17->eta = 500 ms)
  orders  Ok[value=orders-done, attempts=1, startMs=0, endMs=120]
  policy  Ok[value=policy-done, attempts=1, startMs=0, endMs=62]
  stock   Ok[value=stock-done, attempts=1, startMs=0, endMs=151]
  o17     Ok[value=o17-done, attempts=1, startMs=121, endMs=202]
  o18     Ok[value=o18-done, attempts=1, startMs=121, endMs=202]
  eta     Ok[value=eta-done, attempts=1, startMs=202, endMs=503]
idempotent flaky step: Ok[value=ok, attempts=3, startMs=62, endMs=63]
non-idempotent charge (fail-fast): {audit=Ok[value=audit-done, attempts=1, startMs=0, endMs=32], charge=Failed[error=gateway reset after charge request sent, attempts=1], email=Skipped[reason=dependency charge did not succeed]}
continue-on-error: audit=Ok, email=Skipped[reason=dependency charge did not succeed]; charge attempts total=2
slow step with a 100 ms timeout: Failed[error=timeout after 100 ms, attempts=2]
planner emitted a cycle: rejected before execution (plan has a cycle)
ReAct loop guard: stopped at step 4 -> repeated identical call x3: flaky_api{q=status}
all AgentDagExecutor self-checks passed
```

The DAG finishes in ~505 ms against a 500 ms critical path, so scheduling overhead is ~1%. `o17` and `o18` start
together at 121 ms, the moment `orders` finishes.

---

## 5. Production failure modes and P99 debugging

### F1 · Runaway loop and token burn

- **Symptom:** one session costs 100× the median, and a spend alert fires overnight.
- **Signature:** a trace with dozens of identical tool calls, usually against a failing or rate-limited tool.
- **Root cause:** no bound on repeats, steps or tokens. The model treats the error as transient.
- **Fix:** the four guards of §1.5, a structured failure result, and a circuit breaker on the tool so the agent sees
  "unavailable" instead of "retry later".
- **Prevention:** per-session and per-tenant token budgets enforced at the gateway (Folder 07 File 04), and alerts
  on steps per session.

### F2 · P99 latency grows with task complexity

- **Symptom:** simple questions are fast, but multi-entity questions take 10–30 s.
- **Signature:** traces show strictly sequential tool spans with a model span between each.
- **Root cause:** ReAct on work that is a static DAG; latency is `Σ(m + t)`.
- **Fix:** plan-and-execute with parallel dispatch; batch independent lookups into one tool call; a cheaper model for
  routing steps.

### F3 · A side effect happened twice

- **Symptom:** a customer is refunded twice; two identical emails go out.
- **Root cause:** a generic retry wrapper around a non-idempotent tool, or a model that "retries" after a timeout.
- **Fix:** idempotency classes in the tool registry, idempotency keys derived from the workflow and step
  (File 03), and reconciliation before any retry of an ambiguous write.

### F4 · The plan references a tool or argument that does not exist

- **Symptom:** executor errors such as "unknown tool `lookup_order_v2`" or schema violations.
- **Root cause:** the planner hallucinated, or the catalog changed (Folder 05 File 03 F4).
- **Fix:** validate the full plan against the live catalog and schemas before execution and feed validation errors
  back to the planner as a bounded repair loop.

### F5 · Accuracy drops on long sessions

- **Symptom:** the agent forgets constraints given early, or repeats work it already did.
- **Signature:** failures correlate with context length, and the needed fact sits mid-context.
- **Root cause:** lost-in-the-middle and distractor-heavy traces.
- **Fix:** threshold compaction that keeps decisions, open items and constraints; a scratchpad or state object
  outside the prompt; re-injecting constraints near the end of the prompt.

### F6 · Reflection made it worse, or never stopped

- **Symptom:** quality is flat or lower with reflection on, and tokens are 3–5× higher.
- **Root cause:** intrinsic self-critique with no external signal, and no convergence stop.
- **Fix:** give the critic a verifier (tests, schemas, citations); stop on threshold, convergence or a round cap;
  measure with and without reflection on a held-out set.

### F7 · Parallel fan-out has a fat tail

- **Symptom:** median latency improved after moving to a DAG, but P99 got worse.
- **Root cause:** the step waits for the slowest of `k` tools (§3.3).
- **Fix:** per-tool timeouts with partial results, hedging for idempotent reads, optional branches dropped under
  deadline pressure.

---

## 6. FAANG L7 bar-raiser Q&A chains

### Q1 · "Design an agent that handles refund requests end to end."

- **L5 answer:** "A ReAct agent with tools for orders, policy and payments. The model decides what to call and
  issues the refund."
- **Why L5 fails at scale:** money moves on a stochastic decision; a retry can refund twice; latency is the sum of
  every step; nothing bounds a loop; there is no audit trail of who approved what.
- **L7 principal defense:**
  1. Make it a workflow with an agentic core. Code owns authentication, entitlement and policy; the model
     classifies the request, gathers facts and drafts the decision.
  2. Fact gathering runs as a validated plan (orders, carrier ETA, policy) in parallel at critical-path latency.
  3. The refund is a non-idempotent side effect behind an idempotency key, executed only after a policy check and,
     above a threshold, a human approval (File 03's durable signal).
  4. Bound everything: steps, tokens, deadline, repeats. Failures return structured reasons.
  5. Trace every step (model call, tool call, approval) for audit, and evaluate on a labelled set of refund cases
     before each prompt or model change.

### Q2 · "Our agent occasionally loops and burns hundreds of dollars. Fix it."

- **L5 answer:** "Lower `max_steps` to 10."
- **Why L5 fails at scale:** a step cap alone still lets each session burn the cap on every bad trace, cuts off
  legitimate long tasks, and gives the caller no reason for the failure.
- **L7 principal defense:**
  1. Find the trigger in traces: usually one failing tool and a model treating its error as transient.
  2. Guard on repeated identical calls and on no-progress observations, which catch the loop in 3–4 steps while
     leaving a generous step cap for real work.
  3. Add per-session and per-tenant token budgets at the gateway.
  4. Put a circuit breaker on the failing tool, so the model sees a terminal "unavailable" error.
  5. Return a structured stop reason, alert on steps-per-session percentiles, and replay the bad traces as
     regression tests.

### Q3 · "ReAct or plan-and-execute?"

- **L5 answer:** "Plan-and-execute is faster, so always use it."
- **Why L5 fails at scale:** plans go stale; open-ended tasks cannot be planned up front; a bad plan executes many
  steps of wasted or harmful work.
- **L7 principal defense:**
  1. The choice depends on how much each observation changes the next step. Static fan-out (look up these five
     things) is a plan. Exploration (debug this failure) is ReAct.
  2. The usual answer is a hybrid: plan, execute in parallel, and replan on failure or on an observation that
     breaks the plan's assumptions, under a replan budget.
  3. Quantify it: `L_ReAct = Σ(m + tᵢ)` vs `m_plan + CP + m_synth`. The lab is 3,190 vs 1,300 ms; model calls drop
     from `n` to 2.
  4. Validate plans before side effects, and keep side-effecting steps late in the plan, after reads have confirmed
     the assumptions.

### Q4 · "Should we add self-reflection to improve accuracy?"

- **L5 answer:** "Yes, Reflexion shows reflection improves results. Let it critique itself three times."
- **Why L5 fails at scale:** intrinsic self-critique has no new information (Huang et al.); it triples cost and
  latency and can talk the model out of a correct answer.
- **L7 principal defense:**
  1. Reflection works when the critic has a signal: tests, schemas, citations, business rules, or a calibrated
     judge.
  2. Prefer a verifier in code over a critic in prompt wherever the check is mechanical.
  3. Stop on threshold, convergence or a round cap. The lab's critic plateaus at 0.846, and convergence stops it
     after 6 rounds instead of 10.
  4. Measure accuracy, cost and latency with and without it on held-out tasks, and enable it only for task types
     where it wins.

### Q5 · "Single agent or multi-agent?"

- **L5 answer:** "Multi-agent: specialists are better than generalists."
- **Why L5 fails at scale:** tokens multiply (~15× chat in one published system, ⚠ verify), every hand-off loses
  context, failure probability compounds across agents, and debugging needs cross-agent tracing.
- **L7 principal defense:**
  1. Start with one agent and good tools; split only on evidence.
  2. Split when the work is breadth-first and parallel (research fan-out), when contexts would otherwise overflow,
     or when permissions must differ (a read-only browsing agent vs a write-capable executor, which also breaks
     the lethal trifecta of Folder 05 File 02).
  3. Define hand-off contracts as typed state, not prose, and trace across agents with one trace id.
  4. Budget tokens per agent and per task.

---

## 7. Invariants checklist

- [ ] Every loop has a step cap, a token budget, a wall-clock deadline, a repeat detector and a no-progress
      detector, and returns a structured stop reason.
- [ ] Plans are validated against the live catalog (tools, schemas, entitlements, dependencies, cycles) before any
      side effect.
- [ ] Every tool declares an idempotency class. Automatic retries touch only read-only and keyed idempotent tools.
- [ ] Deadlines propagate into every step. Steps that start after the deadline are skipped.
- [ ] Dependents of a failed step are skipped with a recorded reason. Audit and compensation steps run under any
      policy.
- [ ] Context is compacted at a threshold, after the cached system and tool prefix.
- [ ] Reflection runs only with an external signal and a convergence stop.
- [ ] Agent changes ship behind an evaluation set measuring task success, steps, tokens and latency.

## 8. References

1. S. Yao et al. *ReAct: Synergizing Reasoning and Acting in Language Models.* ICLR 2023. arXiv:2210.03629.
2. B. Xu et al. *ReWOO: Decoupling Reasoning from Observations for Efficient Augmented Language Models.*
   arXiv:2305.18323, 2023.
3. S. Kim et al. *An LLM Compiler for Parallel Function Calling.* ICML 2024. arXiv:2312.04511.
4. L. Wang et al. *Plan-and-Solve Prompting.* ACL 2023. arXiv:2305.04091.
5. N. Shinn et al. *Reflexion: Language Agents with Verbal Reinforcement Learning.* NeurIPS 2023. arXiv:2303.11366.
6. A. Madaan et al. *Self-Refine: Iterative Refinement with Self-Feedback.* NeurIPS 2023. arXiv:2303.17651.
7. J. Huang et al. *Large Language Models Cannot Self-Correct Reasoning Yet.* ICLR 2024. arXiv:2310.01798.
8. N. F. Liu et al. *Lost in the Middle: How Language Models Use Long Contexts.* TACL 2024. arXiv:2307.03172.
9. C. Packer et al. *MemGPT: Towards LLMs as Operating Systems.* arXiv:2310.08560, 2023.
10. Anthropic. *Building effective agents* (December 2024) and *How we built our multi-agent research system* (2025)
    (⚠ verify the token figures).
