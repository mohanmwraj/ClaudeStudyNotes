# Model Routing, Limits and Token Economics: Opus vs Sonnet vs Haiku, and Advisor Mode

> **Folder 01 · File 3 of 3** · prices read from Anthropic's pricing page on 2026-10-30 · Claude Code facts from code.claude.com on 2026-10-30
> **Listings:** `claude_token_economics.py` · `ModelRoutingPolicy.java` · `CacheProbe.java` (compiled against anthropic-java 3.3.0; the free multi-JVM check was run)

---

## 0. Orientation

Choosing a model is the *last* cost lever, not the first. Anthropic's own cost guidance orders the levers like this [doc]:

1. **Free wins first:** caching, input hygiene, loop hygiene, output hygiene, batch.
2. **Then the first trade-offs:** effort and budgets.
3. **Model selection last.**

The reason is that every lever before model choice keeps the intelligence ceiling, and model choice moves it.

This file gives you the numbers to reason about all of it: what each model costs per token and per *solved task*, which limits bite, why switching models mid-conversation is usually a loss, when an advisor or orchestrator pays for itself, and how each of these maps onto Claude Code's `/model`, `/effort`, `/advisor` and `/fast`.

Claim labels as in [file 01 §0](01-transformer-attention-lost-in-the-middle-and-xml-tag-grammar.md#0-orientation).

### 0.1 The twelve rules

1. **Default to Opus 5.5 at an explicit effort, and sweep effort before changing models.** Lower effort on the newest model often matches or beats an older model at high effort. [doc]
2. **Price cost per *completed* task, on the hard tail.** A cheaper request that needs retries isn't cheaper, and the hardest tenth of the work decides the bill. [doc]
3. **Caches are model-scoped. Never switch models mid-conversation for "one cheap turn".** On a 120K-token context, moving one turn from Opus 5.5 to Sonnet 5.5 costs **7× more**. The switch pays back only after **14 turns**. [measured: L9]
4. **Know the per-model cache-read multiplier**: 0.1× by default, **0.05×** on Opus 5.5 and Sonnet 5.5, **0.025×** on Fable 5.1. The cheaper the read, the more a miss costs relative to a hit. [doc]
5. **Haiku 5.5 has a price cliff at 100K prompt tokens.** The *whole* request bills at 5×, cache reads included: $0.00690 vs $0.00138 for nearly the same request. [doc + measured: L8]
6. **Agent loops are quadratic in turns.** Every turn resends everything. Caching turned a 40-turn loop from $9.44 into $1.38. [measured: L8]
7. **Stagger fan-out.** A cache entry is readable only once the first response starts streaming. Sending one request, then seven more after its first token, is 3.6× cheaper than eight at once. [doc + measured: L8]
8. **Choose the TTL from your gap distribution, not from intuition.** Keep-alive pings won the tight session and the 1h TTL won the loose one, on both Opus 5.5 and Fable 5.1. [measured: L8]
9. **The MCP tool-schema tax is real.** 200 tool schemas cost 30,000 tokens per request: $120 per 1,000 Opus 5.5 requests uncached, $6 cached, $0.49 with deferred loading. [measured: L8]
10. **An advisor pays only with a wide capability gap and an executor that actually consults.** Benchmark it against simply raising the executor's effort. [doc]
11. **Tokenizers differ between generations.** Compare cost with `count_tokens` on your own text, not price lists. Sonnet 5/5.5 and Haiku 5.5 count the same text as about 30% more tokens than their 4.x predecessors. [doc]
12. **Your prompt builder must be byte-deterministic across JVMs.** `Map.copyOf`-built tool schemas gave 4 distinct cached prefixes in 5 JVMs; sorted maps gave 1. CacheProbe checks this for free in CI. [measured: L10]

---

## 1. First principles

### 1.1 The three meters, and why agent loops are quadratic

Every request is billed on three meters, which `usage` reports separately:

- **input**, split into `input_tokens` (uncached), `cache_creation_input_tokens` (writes) and `cache_read_input_tokens` (reads)
- **output** (`output_tokens`, which *includes* thinking)
- **time**, which isn't billed but is what users feel: time-to-first-token (prefill-bound) and output tokens per second (decode-bound)

"Total prompt size = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`" [doc]. Don't mistake a small `input_tokens` for a small prompt.

An agent turn resends the whole conversation. With a fixed prefix F that grows by g tokens per turn, the input sent over n turns is n·F + g·n(n+1)/2, which is quadratic. L8's 40-turn example sends **2,240,000 input tokens**. Caching doesn't stop the resending; it reprices the resent prefix at the cache-read rate. That is why it is "the largest single lever on every model and benchmark Anthropic measured" [doc].

### 1.2 Prices (Anthropic API, USD per million tokens, read 2026-10-30) [doc]

| Model | Base input | 5m cache write | 1h cache write | Cache read | Output | Batch in / out |
|---|---|---|---|---|---|---|
| **Claude Fable 5.1** | $10.00 | $12.50 | $20.00 | **$0.25** (0.025×) | $50.00 | $5.00 / $25.00 |
| **Claude Opus 5.5** | $4.00 | $5.00 | $8.00 | **$0.20** (0.05×) | $20.00 | $2.00 / $10.00 |
| Claude Opus 5 / Opus 4.8 / 4.7 / 4.6 | $5.00 | $6.25 | $10.00 | $0.50 | $25.00 | $2.50 / $12.50 |
| **Claude Sonnet 5.5** | $2.00 | $2.50 | $4.00 | **$0.10** (0.05×) | $10.00 | $1.00 / $5.00 |
| Claude Sonnet 5 | $2.00 | $2.50 | $4.00 | $0.20 | $10.00 | $1.00 / $5.00 |
| Claude Sonnet 4.6 | $3.00 | $3.75 | $6.00 | $0.30 | $15.00 | $1.50 / $7.50 |
| **Claude Haiku 5.5**, prompt ≤ 100K | $0.10 | $0.125 | $0.20 | $0.01 | $0.50 | $0.05 / $0.25 |
| Claude Haiku 5.5, prompt > 100K | $0.50 | $0.625 | $1.00 | $0.05 | $2.50 | $0.25 / $1.25 |
| Claude Haiku 4.5 | $1.00 | $1.25 | $2.00 | $0.10 | $5.00 | $0.50 / $2.50 |

Modifiers [doc]:

- **Batch API:** 50% off input *and* output. It stacks with the caching multipliers and with data residency. It isn't available with fast mode.
- **Data residency:** `inference_geo: "us"` costs **1.1×** on every token category, on Claude 4.6 and later.
- **Long context:** 4.6+ models other than Haiku 5.5 bill the full 1M-token window at standard per-token rates ("a 900k-token request is billed at the same per-token rate as a 9k-token request"). Haiku 5.5 is priced by prompt length, which counts *all* input tokens including cache reads. A request over 100K pays the higher price for everything.
- **Fast mode:** Opus 5.5 costs $8 / $40, which is 2× standard, and the docs describe it as up to 2.5× higher output speed. Opus 5 and 4.8 cost $10 / $50 (research preview). Caching and data-residency multipliers apply on top.

> **A discrepancy worth knowing.** The Claude API skill bundled with Claude Code 2.1.312 (cached 2026-10-06) lists Sonnet 5.5 cache reads at $0.20. The live pricing page lists **$0.10, i.e. 0.05×**, with a footnote naming Opus 5.5 and Sonnet 5.5. This KB uses the live page. Always price from the pricing page, not from memory or cached tables. ⚠ verify

### 1.3 The limits that bite [doc]

| Limit | Value | Consequence |
|---|---|---|
| Context window | 1M tokens on every current model; Haiku 4.5 has 200K | Capacity is not salience (file 01 §1.4). The Haiku 5.5 price tier still caps the economical size at 100K. |
| Max output | 128K on current models (Haiku 4.5: 64K); Batch up to 300K with beta `output-300k-2026-03-24` ⚠ verify | Large caps need streaming in the SDKs. Thinking counts toward the cap. |
| Minimum cacheable prefix | 512 tokens: Fable 5/5.1, Opus 5/5.5, Sonnet 5.5, Haiku 5.5 ⚠ verify · 1,024: Opus 4.8, Sonnet 5, Sonnet 4.6 · 2,048: Opus 4.7 · 4,096: Opus 4.6, Opus 4.5, Haiku 4.5 | Shorter prefixes silently don't cache, and the minimum isn't monotonic across generations. |
| Cache breakpoints | ≤ 4 per request; top-level automatic caching uses one | Spend them on stability boundaries. |
| Breakpoint lookback | 20 positions | A turn that appends more than 20 positions of text or images can miss the previous entry. Runs of tool_use and runs of tool_result each count as one position. |
| TTL | 5 min default, or 1 h. Lifetime runs from the *start* of the request that writes or reads; each read refreshes it free. | A 4-minute generation leaves about 1 minute before a 5-minute entry expires. |
| Cache isolation | Per workspace (Claude API, Claude Platform on AWS, Foundry); per organisation (Bedrock, Google-managed) | Traffic split across workspaces writes separate entries. |
| Rate limits | Per-model pools (Opus 5.5 is separate from Opus 5; Fable 5.x share a pool). Cache reads don't count toward input-token rate limits on most models. | Caching raises effective throughput as well as cutting cost. |
| Priority Tier | Not supported on Opus 5.5, Opus 5, Sonnet 5, Sonnet 5.5 or Fable 5.1 | Don't design around it on those models. |

### 1.4 The lineup and what each model is for [doc]

| Model | Role | API behaviour that affects routing |
|---|---|---|
| **Fable 5.1** | Most capable widely released model. Hardest reasoning and long-horizon autonomous work. 15-minute single requests are normal on hard tasks. | Thinking is always on; forced `tool_choice` is a 400; thinking blocks are bound to the model; 30-day retention is required (no ZDR unless authorised); $10 / $50. |
| **Opus 5.5** | **The default.** Long-running agentic coding and knowledge work. Output is more than 30% faster than Opus 5, and it is cheaper per solved task. | Thinking is always on and effort defaults to `medium`; forced `tool_choice` is a 400; computer use needs `computer_toolset_20260801`; classifiers cover cyber, bio and reasoning extraction; fast mode is available. |
| **Sonnet 5.5** | Everyday coding, agent and enterprise work at $2 / $10. | Thinking can only be lowered to `between_tools`; forced `tool_choice` is a 400; it accepts fewer advisors; effort defaults to `high`, but the levels are recalibrated. |
| **Haiku 5.5** | Fast, low-cost: classification, routing, extraction, sub-agent work. | Thinking is on by default, effort defaults to `medium`, and there's a 100K price tier. There is no server-side refusal fallback. Its tokenizer counts about 30% more tokens than Haiku 4.5's. |
| Opus 5 / Opus 4.8 | Previous Opus; still served | Opus 5 allows thinking `disabled` only at ≤ `high`; on Opus 4.8, thinking is off when the parameter is omitted. |

**Tokenizers change between generations.** The Opus 4.7+ tokenizer "uses ~1×–1.35× as many tokens" as earlier models, and Sonnet 5/5.5 and Haiku 5.5 count the same text as about 30% more tokens than Sonnet 4.6 / Haiku 4.5 [doc]. So a per-token price comparison across generations is off by up to a third. Re-baseline with `POST /v1/messages/count_tokens` on *your* text: Java source, logs, YAML. Never use `tiktoken` for Claude; it is a different tokenizer.

### 1.5 Effort before model: the escalation algebra [doc, measured: L6, L9]

Anthropic's measured guidance [doc]:

- **Sweep effort on the current model first.** On research and knowledge work, curves were nearly flat: `low` gave up a few points for a third to a half off the cost, and `medium` matched `high`. On long-horizon coding the trade-off was real: each step down cost a few points of pass rate for a substantially lower cost.
- **Re-run failures at a higher effort** when you have a failure signal (tests, a checker). It "held the pass rate of running everything at the higher setting, or slightly beat it, for a little over half the cost".
- **Check for an upgrade before a step-down.** The cheapest move is often the *newer* model at a lower effort.
- **Price the tail.** "On one 20-problem research run, two problems carried 43% of the spend."

L6 reproduces the escalation shape with illustrative numbers. Low-then-high reaches high's 0.75 pass rate at 67% of its cost. L9 encodes the ladder as code: raise effort on the same model up to `high`, and only then step one model tier up, at that model's default effort, **in a new conversation**, because the cache does not survive a model change.

### 1.6 Caching economics, measured [measured: L8]

**Break-even.** With the 5-minute TTL, caching pays from the 2nd request (1.25 + 0.1 < 2). With the 1-hour TTL it pays from the 3rd (2 + 0.2 < 3). L8 confirms this holds on every current model; the cheaper reads on the 5.5 models and Fable 5.1 only widen the margin.

**"90% cheaper", decomposed.** A 100K-token static document plus a 300-token question and a 700-token answer, asked 50 times within the TTL:

| Model | No cache | Cached | Input cost saved | Total cost saved |
|---|---|---|---|---|
| Opus 5.5 | $20.76 | $2.24 | 92.3% | **89.2%** |
| Sonnet 5.5 | $10.38 | $1.12 | 92.3% | 89.2% |
| Fable 5.1 | $51.90 | $4.38 | 94.8% | 91.6% |
| Haiku 5.5 | $2.60 | $0.40 | 87.4% | 84.5% |

The total saving is always below the input saving, because output is never discounted. The Haiku 5.5 row hides a trap: 100,300 tokens puts *every* request in the >100K tier. Trimming 301 tokens makes each warm request bill **5.0× less** ($0.00138 vs $0.00690).

**Choosing the TTL for human-paced sessions** (a growing conversation, 30 requests):

| Session shape | Opus 5.5: 5m / 1h / 5m + keep-alive | Fable 5.1: 5m / 1h / 5m + keep-alive |
|---|---|---|
| Tight (median gap 3 min, 8/29 gaps > 5 min, 21 pings) | $5.666 / $2.414 / **$2.407** | $13.635 / $5.316 / **$4.783** |
| Loose (median gap 9 min, 24/29 gaps > 5 min, 57 pings) | $13.538 / **$2.414** / $3.165 | $33.726 / **$5.316** / $5.730 |

The algebra behind the table:

- A keep-alive costs `pings × context × read price`.
- The 1h TTL costs `(1h − 5m write price) × every token written in the session`.

Cheap reads (Fable 5.1's 0.025×) favour pings, and long idle stretches favour 1h. Anthropic's guidance says that on Fable 5.1 a keep-alive "usually" beats 1h "unless pauses regularly approach an hour". The loose session shows the other side of "usually". Re-send the previous request with `max_tokens: 0` to ping; it bills a cache read and no output [doc].

In Claude Code, subscribers within plan usage get a 1h TTL for the main conversation by default, while API and usage-credit users get 5m. Override with `promptCacheTtl` / `CLAUDE_CODE_PROMPT_CACHE_TTL` [doc: code.claude.com].

**Fan-out.** Eight sub-agents sharing a 40K prefix: launched all at once they cost $0.928, because no request can read an entry until the first response starts streaming. Launch one, await its first token, then the other seven, and the cost is $0.256, **3.6× cheaper**.

**Batch + cache.** For 10,000 nightly classifications on Haiku 5.5: sync uncached $3.75, sync cached $1.05, batch + cache at an *assumed* 70% hit rate $1.04. The batch discount is real, but cache hits inside a batch are best-effort [doc], so measure your hit rate before counting on both discounts.

**The MCP tool-schema tax.** 10 servers × 20 tools × ~150 tokens = **30,000 tokens per request** before you type a word:

| Configuration | Tokens/request | Per 1,000 Opus 5.5 requests |
|---|---|---|
| All schemas, uncached | 30,000 | $120.00 |
| All schemas, cached | 30,000 | $6.00 |
| Tool search / `defer_loading` (~2,450 tokens) | 2,450 | $0.49 |

Caching fixes the bill but not the attention budget (file 01 §1.4) or tool-selection noise. Scope servers per project, and Folder 06 covers this in depth. Anthropic's guidance puts the break-even for tool search at "roughly 10K tokens" of schemas [doc].

### 1.7 Switching models mid-conversation: the cache namespace [doc, measured: L9]

"Caches are model-scoped", and a model switch "has no escape hatch" [doc]. The new model has never seen your prefix, so it writes the whole context at its write price before it can answer. On a 120K-token context with a 1K-token answer:

- **staying on Opus 5.5:** $0.0440 (a cache read plus output)
- **switching to Sonnet 5.5:** $0.3106 (a cold write plus output), about **7× more**
- **switching to Haiku 5.5:** $0.0776, still more than staying, because 120K is in its >100K tier

L9 computes the break-even: a switch from Opus 5.5 to Sonnet 5.5 pays back only if the conversation has at least **14** more turns. Its router therefore keeps a conversation on its warm model when few turns remain, and allows a switch only when the remaining tail amortises the cold write. Even then the switch should happen at a compaction boundary.

Three consequences:

1. **Cheap sub-tasks belong in sub-agents, not in model switches.** A sub-agent starts a *fresh, small* prefix on the cheap model and hands back one line. It shares no cache with the parent, but it doesn't need to re-write the parent's context either [doc].
2. **Claude Code's `opusplan` alias uses `opus` in plan mode and `sonnet` for execution.** Every plan-mode toggle is a model switch and starts a fresh cache [doc: code.claude.com]. It's worth it for a long execution phase after a short plan, and it is waste for frequent toggling on a large context.
3. **Thinking blocks don't transfer either.** A block written by Opus 5.5 is read only by Fable 5.1 / Mythos 5.1 on the Claude API. Other models drop it, unbilled, and run without that reasoning [doc].

### 1.8 Advisor mode: a cheap executor with an expensive consultant [doc]

**On the API.** The advisor is a server-side tool. The request's top-level `model` is the **executor**, which does most of the generation. The tool's `model` is the **advisor**, which the executor consults mid-generation for planning.

```json
{
  "model": "claude-sonnet-5-5",
  "max_tokens": 64000,
  "stream": true,
  "output_config": {"effort": "medium"},
  "tools": [
    {"type": "advisor_20260301", "name": "advisor", "model": "claude-opus-5-5",
     "max_uses": 3, "max_tokens": 4000, "caching": {"type": "ephemeral", "ttl": "5m"}}
  ],
  "messages": [{"role": "user", "content": "Plan and implement the outbox relay; consult the advisor before choosing the concurrency design."}]
}
```

Send this with header `anthropic-beta: advisor-tool-2026-03-01`. The rules:

- **The advisor must be at least as capable as the executor**, and an invalid pair is a 400. Sonnet 5.5 accepts Fable 5.1, Fable 5, Opus 5.5, Opus 5 and Sonnet 5.5 advisors, and rejects Opus 4.8, 4.7 and 4.6, Sonnet 5 and Sonnet 4.6. Opus 5.5 accepts Fable 5.1, Fable 5, Opus 5.5 and Opus 5. Haiku 5.5 accepts Fable, Opus 4.7 and later, Sonnet 5 and later, and Haiku 5.5. Haiku 4.5 can call an advisor but cannot be one. L9 encodes the table and checks five pairs.
- **The advice payload is a discriminated union.**
  - `advisor_result` carries plaintext `text`.
  - `advisor_redacted_result` carries `encrypted_content`; every 5.x advisor returns this.
  - `advisor_tool_result_error` carries an `error_code`, such as `max_uses_exceeded`.

  Code that reads `.text` unconditionally gets nothing from an Opus 5.5 advisor. Switch on the content type and replay what you can't read.
- **Append the full `response.content`**, including `advisor_tool_result` blocks. Removing the advisor tool on a later turn while those blocks remain in history is a 400.
- **Sonnet 5.5, Opus 5.5 and Fable 5.1 executors reject forced `tool_choice`.** Nudge the consultation from the prompt instead.

**In Claude Code** [doc: code.claude.com advisor]:

- **Commands:** `/advisor [model|off]`, with a picker when no argument is given. It accepts `fable`, `opus`, `sonnet` or a full model ID.
- **Persistence:** the `advisorModel` setting, or the `claude --advisor opus` flag (which doesn't appear in `--help`). Turn it off with `/advisor off` or `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`.
- **Behaviour:** Claude decides when to consult. No setting caps or forces consultations. The advisor sees the full transcript.
- **Cost:** advisor tokens bill at the advisor's rates. Toggling the advisor mid-session doesn't invalidate the main conversation's cache.
- **Status:** experimental, and Claude API only (not Bedrock, Claude Platform on AWS, Agent Platform or Foundry).

**When it pays [doc].** "Pays when the capability gap between the two models is wide and the executor actually consults." The consult rate is fragile: "lowering effort can drop a pairing from consulting on most tasks to almost none, and then it scores below the executor alone". On Anthropic's coding benchmark, the flagship pairing "landed about on the executor model's own effort curve: the advisor bought roughly what more effort did".

So run the cheap test first. Sweep the executor's effort, and price the stronger model alone. Add the advisor only if it beats both on your eval.

### 1.9 Orchestrator and workers [doc]

A frontier model that plans and delegates bulk work to cheaper workers "buys something only when there is bulk to hand off": many independent pieces, ideally too many for one context window.

- **Where it helped:** on work larger than any context window, it cost about half as much as the frontier model solo, though it scored lower. On routine search it acted as tail insurance.
- **Where it lost:** on one dependent chain, or work that fits one context, "the coordinator's model alone at lower effort came out ahead".

Claude Code exposes the worker model as `CLAUDE_CODE_SUBAGENT_MODEL`. An agent's frontmatter `model` wins unless `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set [doc: code.claude.com]. Folder 04 builds subagents.

### 1.10 Claude Code's model controls in one table [doc: code.claude.com, 2026-10-30]

| Control | What it does |
|---|---|
| `/model <alias\|id>`, `--model` | Aliases: `default`, `best`, `fable`, `opus`, `sonnet`, `haiku`, `opus[1m]`, `sonnet[1m]`, `opusplan`. On the Anthropic API, `opus` = Opus 5.5, `sonnet` = Sonnet 5.5 and `haiku` = Haiku 5.5. Other providers map differently (Foundry: `opus` = Opus 4.6). |
| Precedence | `/model` > `--model` > `ANTHROPIC_MODEL` > settings `model` > `ANTHROPIC_DEFAULT_MODEL` (v2.1.236+) |
| `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL` | Re-point an alias. For `opusplan`, the opus/sonnet pair is what plan mode and execution use. |
| Default model | Opus 5.5 on Pro, Max, Team, Enterprise and the Anthropic API (and on Bedrock / Agent Platform / Claude Platform on AWS); Sonnet 4.5 on Foundry |
| `/effort`, `effortLevel`, `CLAUDE_CODE_EFFORT_LEVEL` | File 02 §2.5. Defaults: `medium` on Opus 5.5 / Sonnet 5.5 / Haiku 5.5, `xhigh` on Opus 4.7, `high` elsewhere. |
| `/advisor`, `advisorModel` | §1.8 |
| `/fast [on\|off]`, `fastMode` | Opus 5.5 (default fast model since v2.1.280), Opus 5, Opus 4.8; up to 2.5× faster at higher per-token price; not on Bedrock / Agent Platform / Foundry / Claude Platform on AWS |
| `/usage` (aliases `/cost`, `/stats`) | Session cost (API users) or plan usage bars (subscribers); a `Prompt cache (main)` line from v2.1.251 |
| `/context [all]` | Coloured grid of what fills the context window, with optimisation suggestions |
| `DISABLE_PROMPT_CACHING[_OPUS\|_SONNET\|_HAIKU\|_FABLE]` | Turns caching off (debugging only); the per-alias variants apply to the model the alias resolves to |
| Context window and compaction | 1M by default on Sonnet 5+, Haiku 5.5, Fable and Opus 4.7+; auto-compact at about 967K on native-1M models. Tune with `/autocompact`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW` or `autoCompactWindow` (100K–1M). `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` holds sessions to 200K. |

Folder 03 is the full command reference. Folder 08 turns this into dotfiles.

---

## 2. Practice

### 2.1 A starting routing table for a Java backend organisation

These are starting points to sweep from, not answers. Every row should be re-validated on your own eval after each model release.

| Work | Model | Effort | `max_tokens` | Notes |
|---|---|---|---|---|
| Log/alert triage, ticket classification, PII tagging | Haiku 5.5 | `low` | 2–4K | Structured outputs; keep prompts ≤ 100K; no server-side refusal fallback, so handle `refusal` yourself |
| Chat over internal docs | Sonnet 5.5 | `low` | 16K | Docs-first layout (file 01); cache the corpus prefix |
| Small code edits, test generation, Javadoc, Spring config | Sonnet 5.5 | `medium` | 64K, streamed | Anthropic's suggested start for agentic coding and multistep tool use |
| Multi-file features, migrations, debugging in a real repo | **Opus 5.5** | `medium` → `high` on test failure | 128K, streamed | The default model; re-run failures one level up (L9 ladder) |
| PR review for concurrency, transactions, data loss | Opus 5.5 | `high` | 64K | A fresh context per review; a verification contract (file 02 §2.1) |
| Architecture / RFC review, incident post-mortem analysis | Opus 5.5 | `high` | 64K | Devil's-advocate contract (file 02 §2.4); escalate to Fable 5.1 only on measured gaps |
| Hardest long-horizon autonomous work (multi-hour audits) | Fable 5.1 | `high` (`xhigh` if measured) | 128K, streamed | Long single turns; async check-ins; 30-day retention required |
| Bulk reading across many repos/documents | Opus 5.5 orchestrator + Haiku 5.5 workers | `medium` / `low` | — | Only when there is bulk to hand off (§1.9) |
| Nightly backfills, eval runs, bulk summaries | Any of the above via **Batch API** | as per route | — | 50% off, stacking with caching; results within 24 h; no mid-batch tool loop |

### 2.2 The cost-per-solved-task worksheet

Run this before any model change.

1. **Sample.** Take 30–100 *real* tasks of one route, each with a pass/fail signal: tests, a validator, or a rubric graded by a separate model. Include the 10% of tasks you know are hard.
2. **Sweep effort on the current model.** Run each level in a **separate session**, because changing effort mid-session invalidates the cache and distorts the comparison. Keep requests byte-identical except `output_config.effort` [doc].
3. **Record** `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`, `output_tokens_details.thinking_tokens`, `stop_reason` and pass/fail per task.
4. **Compute** $/attempt, pass rate, $/solved (= Σ cost / #passed), and the same numbers for the hardest decile.
5. **Try the escalation policy:** run low, re-run failures one level up (L6 §3). Count the failed cheap attempts in the cost.
6. **Only then try another model**, at *its* default effort, and re-sweep. Compare $/solved on the hard decile.
7. **Write down** the decision, the numbers, and the date. Re-run on the next model release.

### 2.3 Claude Code: a "Sonnet executor + Opus advisor" profile ⚠ verify keys

Use these in project `.claude/settings.json` or user `~/.claude/settings.json`. The key names are from code.claude.com's model-config, advisor and prompt-caching pages (2026-10-30). The full settings reference is in Folder 03.

```json
{
  "model": "sonnet",
  "effortLevel": "medium",
  "advisorModel": "opus",
  "promptCacheTtl": "1h"
}
```

```bash
# environment (shell profile or CI)
export CLAUDE_CODE_SUBAGENT_MODEL=haiku     # cheap default for subagents without their own `model`
# export CLAUDE_CODE_EFFORT_LEVEL=high      # overrides every other effort source - use sparingly
```

When to use this profile: day-to-day work where Sonnet 5.5 is enough and you want Opus 5.5 consulted on hard decisions. Benchmark it against plain `opus` at `medium` on your own tasks before standardising (§1.8).

### 2.4 What to put on the dashboard

| Metric | Formula | Alert when |
|---|---|---|
| Cache read share | `cache_read / (input + cache_write + cache_read)` | It falls more than 20 points after a deploy, which points at a silent invalidator (file 01 F1/F2) |
| Write share per turn | `cache_write / total input` in agent loops | It sits near 1.0: the prefix is being rewritten upstream |
| $/solved task per route | Σ cost / #passed | It rises after a model or prompt change |
| `max_tokens` stop rate | Count of `stop_reason == "max_tokens"` / requests | It is above 1% on agentic routes |
| Refusal rate by category | `stop_details.category` | Any `reasoning_extraction` (fix the prompt); a spike in others (check fallbacks) |
| Thinking share | `thinking_tokens / output_tokens` | It drifts after a migration (re-sweep effort) |
| Haiku 5.5 >100K share | Requests with total prompt > 100K / requests | Above 0 on routes designed to stay under |

---

## 3. Verified listings

### L8 · `claude_token_economics.py`: price the scenarios

**What it shows.**
- Break-even request counts per TTL.
- The "90%" claim decomposed into input versus total savings.
- The Haiku 5.5 100K cliff.
- Agent-loop growth.
- TTL choice for tight and loose human-paced sessions, as a growing conversation with per-turn writes.
- Fan-out staggering.
- Batch plus cache.
- The MCP schema tax.
- The cost of a mid-conversation model switch.

The prices are the live list prices. **What it does not show.** Your workload. Shapes, gap distributions and the 70% batch hit rate are ILLUSTRATIVE.

Run: `python claude_token_economics.py` (NumPy).

```python
"""claude_token_economics.py - a cost model for Claude requests: prompt-cache writes/reads by TTL,
batch and data-residency multipliers, Haiku 5.5's 100K-token price tier, and the scenarios a staff
engineer actually has to price: the "90% cheaper" claim decomposed, agent-loop growth, TTL choice
for human-paced sessions, parallel fan-out, the MCP tool-schema tax, and mid-conversation model switches.

Prices: Anthropic pricing page, read 2026-10-30 (USD per million tokens). Workload shapes are
ILLUSTRATIVE - plug in your own usage logs. Run: python claude_token_economics.py (needs numpy).
"""
import numpy as np

# model: (base input, 5m cache write, 1h cache write, cache read, output)
PRICES = {
    "claude-fable-5-1": (10.00, 12.50, 20.00, 0.25, 50.00),
    "claude-opus-5-5": (4.00, 5.00, 8.00, 0.20, 20.00),
    "claude-opus-5": (5.00, 6.25, 10.00, 0.50, 25.00),
    "claude-sonnet-5-5": (2.00, 2.50, 4.00, 0.10, 10.00),
    "claude-haiku-5-5": (0.10, 0.125, 0.20, 0.01, 0.50),          # prompt <= 100K tokens
    "claude-haiku-5-5>100k": (0.50, 0.625, 1.00, 0.05, 2.50),     # prompt  > 100K tokens (whole request)
    "claude-haiku-4-5": (1.00, 1.25, 2.00, 0.10, 5.00),
}


def cost(model, uncached=0, write5=0, write1h=0, read=0, out=0, batch=False, us_only=False):
    """Dollar cost of one request. Prompt length for Haiku 5.5's tier counts ALL input incl. cache reads."""
    if model == "claude-haiku-5-5" and uncached + write5 + write1h + read > 100_000:
        model = "claude-haiku-5-5>100k"
    pin, pw5, pw1, pr, pout = PRICES[model]
    usd = (uncached * pin + write5 * pw5 + write1h * pw1 + read * pr + out * pout) / 1e6
    return usd * (0.5 if batch else 1.0) * (1.1 if us_only else 1.0)


rng = np.random.default_rng(1030)

print("=== 0. Break-even: how many requests must share a prefix before caching pays? ===")
for model in ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1", "claude-opus-5"]:
    pin, pw5, pw1, pr, _ = PRICES[model]
    n5 = next(n for n in range(1, 50) if pw5 + (n - 1) * pr < n * pin)
    n1 = next(n for n in range(1, 50) if pw1 + (n - 1) * pr < n * pin)
    print(f"{model:<18} read = {pr / pin:.3f}x input | 5m TTL pays from request {n5} | 1h TTL pays from request {n1}")
    assert (n5, n1) == (2, 3)

print("\n=== 1. 'Caching cuts cost 90%' decomposed: 100K static docs + 300-token question, 50 requests in TTL ===")
P, Q, OUT, N = 100_000, 300, 700, 50
print(f"{'model':<18} | {'no cache':>9} | {'cached':>8} | {'input saved':>11} | {'total saved':>11}")
for model in ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-haiku-5-5"]:
    cold = N * cost(model, uncached=P + Q, out=OUT)
    warm = cost(model, write5=P, uncached=Q, out=OUT) + (N - 1) * cost(model, read=P, uncached=Q, out=OUT)
    in_cold = N * cost(model, uncached=P + Q)
    in_warm = cost(model, write5=P, uncached=Q) + (N - 1) * cost(model, read=P, uncached=Q)
    print(f"{model:<18} | ${cold:8.2f} | ${warm:7.2f} | {100 * (1 - in_warm / in_cold):10.1f}% | {100 * (1 - warm / cold):10.1f}%")
    if model == "claude-opus-5-5":
        assert 1 - in_warm / in_cold > 0.90 and 1 - warm / cold < 1 - in_warm / in_cold
print("note: 100,300 tokens puts EVERY Haiku 5.5 request in the >100K tier; trim 301 tokens and it bills 5x less")
h_over = cost("claude-haiku-5-5", read=100_000, uncached=300, out=700)
h_under = cost("claude-haiku-5-5", read=99_699, uncached=300, out=700)
print(f"Haiku 5.5 warm request at 100,300 tokens ${h_over:.5f} vs 99,999 tokens ${h_under:.5f} ({h_over / h_under:.1f}x)")
assert h_over / h_under > 4.9

print("\n=== 2. Agent loop: 40 turns, 15K fixed prefix (system+tools+CLAUDE.md), +2K per turn, 600 out/turn ===")
turns, prefix, grow, out_t = 40, 15_000, 2_000, 600
no_cache = sum(cost("claude-opus-5-5", uncached=prefix + grow * t, out=out_t) for t in range(1, turns + 1))
cached = cost("claude-opus-5-5", write5=prefix + grow, out=out_t)
cached += sum(cost("claude-opus-5-5", read=prefix + grow * (t - 1), write5=grow, out=out_t) for t in range(2, turns + 1))
billed_in = sum(prefix + grow * t for t in range(1, turns + 1))
print(f"input tokens sent: {billed_in:,} (quadratic in turns); Opus 5.5 cost uncached ${no_cache:.2f} vs cached ${cached:.2f} "
      f"({no_cache / cached:.1f}x)")
assert no_cache / cached > 3

print("\n=== 3. TTL for a human-paced session: a GROWING conversation, 30 requests, 60K starting context ===")


def session_cost(model, gaps, policy, pre=60_000, q=1_500, o=1_200):
    """Each request reads the cached context and WRITES its new tail (last answer + new question) at the
    TTL's write price; a gap longer than the TTL turns the read into a full re-write. 'keep' = 5m TTL plus
    a max_tokens:0 re-send of the previous request every 4.5 idle minutes (bills a cache read, no output)."""
    ttl = 60 if policy == "1h" else 5
    wkey = "write1h" if policy == "1h" else "write5"
    total, ctx, pings = cost(model, **{wkey: pre + q}, out=o), pre + q, 0
    for g in gaps:
        if policy == "keep" and g <= 60:
            n = int(g // 4.5)
            pings += n
            total += n * cost(model, read=ctx)
            g = 0.0
        if g > ttl:
            total += cost(model, **{wkey: ctx + o + q}, out=o)
        else:
            total += cost(model, read=ctx, **{wkey: o + q}, out=o)
        ctx += o + q
    return total, pings


for shape, median in [("tight: median gap 3 min", 3.0), ("loose: median gap 9 min", 9.0)]:
    gaps = rng.lognormal(np.log(median), 0.8, 29)            # minutes between request STARTS
    print(f"-- {shape}: {np.sum(gaps > 5)}/29 gaps > 5 min, {np.sum(gaps > 60)} > 60 min, idle total {gaps.sum():.0f} min")
    for model in ["claude-opus-5-5", "claude-fable-5-1"]:
        c5, _ = session_cost(model, gaps, "5m")
        c1, _ = session_cost(model, gaps, "1h")
        ck, pings = session_cost(model, gaps, "keep")
        best = min((c5, "5m"), (c1, "1h"), (ck, "5m+keep-alive"))[1]
        print(f"   {model:<18} 5m ${c5:6.3f} | 1h ${c1:6.3f} | 5m + {pings:3d} pings ${ck:6.3f} -> cheapest: {best}")
        assert min(c1, ck) < c5, "any warm-keeping policy beats a cold 5m cache once gaps exceed 5 min"
print("=> keep-alive costs (pings x context x read price); 1h costs (1h - 5m write price) x every token written.\n"
      "   Cheap reads (Fable 5.1 0.025x) favour pings; long idle stretches favour 1h. Price YOUR gap distribution.")

print("\n=== 4. Fan-out: 8 sub-agents sharing a 40K prefix ===")
k, pre = 8, 40_000
burst = k * cost("claude-sonnet-5-5", write5=pre, uncached=500, out=1_500)
stagger = cost("claude-sonnet-5-5", write5=pre, uncached=500, out=1_500) + (k - 1) * cost(
    "claude-sonnet-5-5", read=pre, uncached=500, out=1_500)
print(f"all 8 at once: ${burst:.3f} (no request can read an entry until the first response starts streaming)")
print(f"1, await first token, then 7: ${stagger:.3f} ({burst / stagger:.1f}x cheaper)")
assert burst > stagger

print("\n=== 5. Nightly batch: 10,000 classifications, 3K shared prefix + 500 unique + 50 out (Haiku 5.5) ===")
sync_cold = 10_000 * cost("claude-haiku-5-5", uncached=3_500, out=50)
sync_warm = cost("claude-haiku-5-5", write5=3_000, uncached=500, out=50) + 9_999 * cost(
    "claude-haiku-5-5", read=3_000, uncached=500, out=50)
hit = 0.7                                                   # ILLUSTRATIVE: cache hits inside a batch are best-effort
batch_warm = 10_000 * (hit * cost("claude-haiku-5-5", read=3_000, uncached=500, out=50, batch=True)
                       + (1 - hit) * cost("claude-haiku-5-5", write5=3_000, uncached=500, out=50, batch=True))
print(f"sync uncached ${sync_cold:.2f} | sync cached ${sync_warm:.2f} | batch + cache @70% hits ${batch_warm:.2f}")
assert batch_warm < sync_warm < sync_cold

print("\n=== 6. The MCP tool-schema tax: tools render first, in EVERY request ===")
servers, tools_each, tok_per_tool, reqs = 10, 20, 150, 1_000
schema = servers * tools_each * tok_per_tool
deferred = 2_000 + 3 * tok_per_tool                         # tool-search tool + ~3 surfaced schemas
for label, tok, cached_ok in [("all schemas, uncached", schema, False), ("all schemas, cached", schema, True),
                              ("tool search / defer_loading", deferred, True)]:
    c = reqs * (cost("claude-opus-5-5", read=tok) if cached_ok else cost("claude-opus-5-5", uncached=tok))
    print(f"{label:<28}: {tok:>6,} tokens/request -> ${c:7.2f} per 1,000 Opus 5.5 requests")
print(f"=> {schema:,} schema tokens/request before you type a word; caching fixes the bill, not the "
      "attention budget or tool-selection noise - scope servers per project")

print("\n=== 7. Mid-conversation model switch: is the 'cheaper' model cheaper for one turn? ===")
ctx, out1 = 120_000, 1_000
stay = cost("claude-opus-5-5", read=ctx, uncached=300, out=out1)
switch = cost("claude-sonnet-5-5", write5=ctx, uncached=300, out=out1)
haiku = cost("claude-haiku-5-5", write5=ctx, uncached=300, out=out1)
print(f"stay on Opus 5.5 (cache read): ${stay:.4f} | switch to Sonnet 5.5 (cold write): ${switch:.4f} | "
      f"switch to Haiku 5.5 (cold, >100K tier): ${haiku:.4f}")
assert stay < switch
print("=> caches are model-scoped: switch models at a conversation/compaction boundary, or delegate to a sub-agent "
      "with a small fresh context")
print("\nALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
=== 0. Break-even: how many requests must share a prefix before caching pays? ===
claude-opus-5-5    read = 0.050x input | 5m TTL pays from request 2 | 1h TTL pays from request 3
claude-sonnet-5-5  read = 0.050x input | 5m TTL pays from request 2 | 1h TTL pays from request 3
claude-haiku-5-5   read = 0.100x input | 5m TTL pays from request 2 | 1h TTL pays from request 3
claude-fable-5-1   read = 0.025x input | 5m TTL pays from request 2 | 1h TTL pays from request 3
claude-opus-5      read = 0.100x input | 5m TTL pays from request 2 | 1h TTL pays from request 3

=== 1. 'Caching cuts cost 90%' decomposed: 100K static docs + 300-token question, 50 requests in TTL ===
model              |  no cache |   cached | input saved | total saved
claude-opus-5-5    | $   20.76 | $   2.24 |       92.3% |       89.2%
claude-sonnet-5-5  | $   10.38 | $   1.12 |       92.3% |       89.2%
claude-fable-5-1   | $   51.90 | $   4.38 |       94.8% |       91.6%
claude-haiku-5-5   | $    2.60 | $   0.40 |       87.4% |       84.5%
note: 100,300 tokens puts EVERY Haiku 5.5 request in the >100K tier; trim 301 tokens and it bills 5x less
Haiku 5.5 warm request at 100,300 tokens $0.00690 vs 99,999 tokens $0.00138 (5.0x)

=== 2. Agent loop: 40 turns, 15K fixed prefix (system+tools+CLAUDE.md), +2K per turn, 600 out/turn ===
input tokens sent: 2,240,000 (quadratic in turns); Opus 5.5 cost uncached $9.44 vs cached $1.38 (6.8x)

=== 3. TTL for a human-paced session: a GROWING conversation, 30 requests, 60K starting context ===
-- tight: median gap 3 min: 8/29 gaps > 5 min, 0 > 60 min, idle total 143 min
   claude-opus-5-5    5m $ 5.666 | 1h $ 2.414 | 5m +  21 pings $ 2.407 -> cheapest: 5m+keep-alive
   claude-fable-5-1   5m $13.635 | 1h $ 5.316 | 5m +  21 pings $ 4.783 -> cheapest: 5m+keep-alive
-- loose: median gap 9 min: 24/29 gaps > 5 min, 0 > 60 min, idle total 317 min
   claude-opus-5-5    5m $13.538 | 1h $ 2.414 | 5m +  57 pings $ 3.165 -> cheapest: 1h
   claude-fable-5-1   5m $33.726 | 1h $ 5.316 | 5m +  57 pings $ 5.730 -> cheapest: 1h
=> keep-alive costs (pings x context x read price); 1h costs (1h - 5m write price) x every token written.
   Cheap reads (Fable 5.1 0.025x) favour pings; long idle stretches favour 1h. Price YOUR gap distribution.

=== 4. Fan-out: 8 sub-agents sharing a 40K prefix ===
all 8 at once: $0.928 (no request can read an entry until the first response starts streaming)
1, await first token, then 7: $0.256 (3.6x cheaper)

=== 5. Nightly batch: 10,000 classifications, 3K shared prefix + 500 unique + 50 out (Haiku 5.5) ===
sync uncached $3.75 | sync cached $1.05 | batch + cache @70% hits $1.04

=== 6. The MCP tool-schema tax: tools render first, in EVERY request ===
all schemas, uncached       : 30,000 tokens/request -> $ 120.00 per 1,000 Opus 5.5 requests
all schemas, cached         : 30,000 tokens/request -> $   6.00 per 1,000 Opus 5.5 requests
tool search / defer_loading :  2,450 tokens/request -> $   0.49 per 1,000 Opus 5.5 requests
=> 30,000 schema tokens/request before you type a word; caching fixes the bill, not the attention budget or tool-selection noise - scope servers per project

=== 7. Mid-conversation model switch: is the 'cheaper' model cheaper for one turn? ===
stay on Opus 5.5 (cache read): $0.0452 | switch to Sonnet 5.5 (cold write): $0.3106 | switch to Haiku 5.5 (cold, >100K tier): $0.0776
=> caches are model-scoped: switch models at a conversation/compaction boundary, or delegate to a sub-agent with a small fresh context

ALL ASSERTIONS PASSED
```

### L9 · `ModelRoutingPolicy.java`: routing as testable code

**What it shows.** Task-class routes; an escalation ladder that raises effort before changing model, and marks every model step-up as a new conversation; advisor-pair validation (two accepted, three 400s); a cache-aware switch rule with its break-even (14 turns for Opus 5.5 → Sonnet 5.5 at 120K tokens); and the Claude Code alias table.

**What it does not show.** Quality. The routes are starting points to sweep from (§2.2), not measured optima.

Run: `java ModelRoutingPolicy.java`.

```java
// ModelRoutingPolicy.java - a routing policy for Claude models written as code you can test:
// task class -> (model, effort, max_tokens, stream); an escalation ladder that raises EFFORT before
// it changes MODEL; advisor-pairing validation (the API 400s on an invalid executor/advisor pair);
// and a cache-aware rule for switching models mid-conversation (caches are model-scoped).
// Model rows, prices and pairings are data from Anthropic's docs/pricing page as of 2026-10-30.
//
// Java 21, no dependencies.  Run:  java ModelRoutingPolicy.java   (prints ALL ASSERTIONS PASSED)
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

public final class ModelRoutingPolicy {

    enum Effort { LOW, MEDIUM, HIGH, XHIGH, MAX }

    /** tier orders capability for escalation; prices are $/MTok (input, 5m write, cache read, output). */
    record Model(String id, int tier, Effort defaultEffort, double in, double write5m, double read, double out) {}

    static final Model HAIKU_5_5 = new Model("claude-haiku-5-5", 1, Effort.MEDIUM, 0.10, 0.125, 0.01, 0.50);
    static final Model SONNET_5_5 = new Model("claude-sonnet-5-5", 2, Effort.HIGH, 2.00, 2.50, 0.10, 10.00);
    static final Model OPUS_5_5 = new Model("claude-opus-5-5", 3, Effort.MEDIUM, 4.00, 5.00, 0.20, 20.00);
    static final Model FABLE_5_1 = new Model("claude-fable-5-1", 4, Effort.HIGH, 10.00, 12.50, 0.25, 50.00);
    static final List<Model> LADDER = List.of(HAIKU_5_5, SONNET_5_5, OPUS_5_5, FABLE_5_1);

    /** Advisor tool (advisor_20260301): executor -> advisors the API accepts. Others return 400. */
    static final Map<String, Set<String>> ADVISORS = Map.of(
            "claude-haiku-4-5", Set.of("claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8",
                    "claude-sonnet-5-5", "claude-sonnet-5", "claude-haiku-5-5", "claude-sonnet-4-6"),
            "claude-haiku-5-5", Set.of("claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8",
                    "claude-sonnet-5-5", "claude-sonnet-5", "claude-haiku-5-5"),
            "claude-sonnet-5-5", Set.of("claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"),
            "claude-opus-4-8", Set.of("claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-sonnet-5-5"),
            "claude-opus-5-5", Set.of("claude-fable-5-1", "claude-opus-5-5", "claude-opus-5"),
            "claude-fable-5-1", Set.of("claude-fable-5-1"));

    /** Claude Code aliases on the Anthropic API (code.claude.com model-config, 2026-10-30). */
    static final Map<String, String> CLAUDE_CODE_ALIAS = Map.of(
            "opus", "claude-opus-5-5", "sonnet", "claude-sonnet-5-5", "haiku", "claude-haiku-5-5",
            "opusplan", "plan mode -> opus, execution -> sonnet (each toggle is a model switch: fresh cache)");

    enum TaskClass { CLASSIFY_EXTRACT, CHAT, CODE_EDIT_SMALL, AGENTIC_CODING_LONG, ARCHITECTURE_REVIEW, BULK_FANOUT_READ }

    record Route(Model model, Effort effort, long maxTokens, boolean stream, Optional<Model> workers,
                 boolean newConversation, String why) {}

    /** What the router knows about the conversation it is joining (empty = fresh). */
    record Conversation(Model model, long contextTokens, int remainingTurns, long outPerTurn) {}

    static Route route(TaskClass task, Optional<Conversation> conv) {
        Route r = switch (task) {
            case CLASSIFY_EXTRACT -> new Route(HAIKU_5_5, Effort.LOW, 4_096, false, Optional.empty(), false,
                    "high volume, checkable output; low effort keeps thinking short");
            case CHAT -> new Route(SONNET_5_5, Effort.LOW, 16_000, true, Optional.empty(), false,
                    "Sonnet 5.5 guidance: start chat at low");
            case CODE_EDIT_SMALL -> new Route(SONNET_5_5, Effort.MEDIUM, 64_000, true, Optional.empty(), false,
                    "Sonnet 5.5 guidance: start agentic coding / multistep tool use at medium");
            case AGENTIC_CODING_LONG -> new Route(OPUS_5_5, Effort.MEDIUM, 128_000, true, Optional.empty(), false,
                    "Opus 5.5 at its medium default matched Opus 5 at high on repo-scale tasks; 128K cap worked well");
            case ARCHITECTURE_REVIEW -> new Route(OPUS_5_5, Effort.HIGH, 64_000, true, Optional.empty(), false,
                    "one-shot, expensive-to-be-wrong; escalate to Fable 5.1 only on measured gaps");
            case BULK_FANOUT_READ -> new Route(OPUS_5_5, Effort.MEDIUM, 64_000, true, Optional.of(HAIKU_5_5), false,
                    "orchestrator plans and merges; cheap workers absorb the reading in their own contexts");
        };
        if (conv.isPresent() && !conv.get().model().equals(r.model())) {
            Conversation c = conv.get();
            if (!switchPays(c.model(), r.model(), c.contextTokens(), c.remainingTurns(), c.outPerTurn())) {
                return new Route(c.model(), r.effort(), r.maxTokens(), r.stream(), r.workers(), false,
                        "stay on " + c.model().id() + ": a switch re-writes " + c.contextTokens()
                        + " tokens of cache; change effort per message instead");
            }
            return new Route(r.model(), r.effort(), r.maxTokens(), r.stream(), r.workers(), true,
                    r.why() + " (switch pays back over " + c.remainingTurns() + " turns; start at a compaction boundary)");
        }
        return r;
    }

    /** Raise effort on the same model first; only past HIGH move one model tier up, at its default effort. */
    static Route escalate(Route r) {
        if (r.effort().ordinal() < Effort.HIGH.ordinal())
            return new Route(r.model(), Effort.values()[r.effort().ordinal() + 1], r.maxTokens(), r.stream(), r.workers(),
                    false, "re-run the failure one effort level up on the same model (cache stays warm)");
        int next = LADDER.indexOf(r.model()) + 1;
        if (next >= LADDER.size())
            return new Route(r.model(), Effort.MAX, r.maxTokens(), true, r.workers(), false, "top of ladder: max effort");
        Model up = LADDER.get(next);
        return new Route(up, up.defaultEffort(), Math.max(r.maxTokens(), 64_000), true, r.workers(), true,
                "model step-up: new conversation, new cache namespace");
    }

    static void validateAdvisor(String executor, String advisor) {
        Set<String> ok = ADVISORS.get(executor);
        if (ok == null || !ok.contains(advisor))
            throw new IllegalArgumentException("400: advisor " + advisor + " is not valid for executor " + executor);
    }

    /** Cost over the remaining turns of staying (cache reads) vs. switching (one cold write, then reads). */
    static double stayCost(Model m, long ctx, int turns, long out) {
        return turns * (ctx * m.read() + out * m.out()) / 1e6;
    }

    static double switchCost(Model to, long ctx, int turns, long out) {
        return (ctx * to.write5m() + Math.max(0, turns - 1) * ctx * to.read() + turns * out * to.out()) / 1e6;
    }

    static boolean switchPays(Model from, Model to, long ctx, int turns, long out) {
        return switchCost(to, ctx, turns, out) < stayCost(from, ctx, turns, out);
    }

    static int breakEvenTurns(Model from, Model to, long ctx, long out) {
        for (int t = 1; t <= 100_000; t++) if (switchPays(from, to, ctx, t, out)) return t;
        return -1;
    }

    static void check(boolean ok, String msg) {
        if (!ok) throw new AssertionError(msg);
    }

    static String show(Route r) {
        return String.format("%-18s %-6s max_tokens=%-7d stream=%-5b%s%s | %s", r.model().id(), r.effort(), r.maxTokens(),
                r.stream(), r.workers().map(w -> " workers=" + w.id()).orElse(""), r.newConversation() ? " NEW-CONV" : "", r.why());
    }

    public static void main(String[] args) {
        System.out.println("--- routes for a fresh conversation");
        for (TaskClass t : TaskClass.values()) System.out.printf("%-20s -> %s%n", t, show(route(t, Optional.empty())));

        Route agentic = route(TaskClass.AGENTIC_CODING_LONG, Optional.empty());
        check(agentic.model() == OPUS_5_5 && agentic.effort() == Effort.MEDIUM && agentic.maxTokens() == 128_000, "agentic route");
        check(route(TaskClass.CLASSIFY_EXTRACT, Optional.empty()).model() == HAIKU_5_5, "classify route");

        System.out.println("--- escalation ladder from Sonnet 5.5 / LOW (effort first, then model)");
        Route r = new Route(SONNET_5_5, Effort.LOW, 64_000, true, Optional.empty(), false, "start");
        for (int i = 0; i < 6; i++) {
            r = escalate(r);
            System.out.println("  " + show(r));
        }
        Route e1 = escalate(new Route(OPUS_5_5, Effort.MEDIUM, 128_000, true, Optional.empty(), false, ""));
        Route e2 = escalate(new Route(OPUS_5_5, Effort.HIGH, 128_000, true, Optional.empty(), false, ""));
        check(e1.model() == OPUS_5_5 && e1.effort() == Effort.HIGH && !e1.newConversation(), "effort before model");
        check(e2.model() == FABLE_5_1 && e2.newConversation(), "model step-up starts a new conversation");

        System.out.println("--- advisor pairings");
        String[][] pairs = {{"claude-sonnet-5-5", "claude-opus-5-5"}, {"claude-haiku-5-5", "claude-opus-5-5"},
                {"claude-sonnet-5-5", "claude-opus-4-8"}, {"claude-opus-5-5", "claude-sonnet-5-5"}, {"claude-haiku-5-5", "claude-haiku-4-5"}};
        boolean[] expected = {true, true, false, false, false};
        for (int i = 0; i < pairs.length; i++) {
            boolean ok;
            try {
                validateAdvisor(pairs[i][0], pairs[i][1]);
                ok = true;
            } catch (IllegalArgumentException ex) {
                ok = false;
            }
            System.out.printf("  executor %-18s advisor %-18s -> %s%n", pairs[i][0], pairs[i][1], ok ? "accepted" : "400");
            check(ok == expected[i], "pairing " + pairs[i][0] + "/" + pairs[i][1]);
        }

        System.out.println("--- mid-conversation switch (120K context, 1K output/turn)");
        int be = breakEvenTurns(OPUS_5_5, SONNET_5_5, 120_000, 1_000);
        System.out.printf("  Opus 5.5 -> Sonnet 5.5: stay $%.4f vs switch $%.4f for 1 turn; switch pays from turn %d%n",
                stayCost(OPUS_5_5, 120_000, 1, 1_000), switchCost(SONNET_5_5, 120_000, 1, 1_000), be);
        Route stay = route(TaskClass.CHAT, Optional.of(new Conversation(OPUS_5_5, 150_000, 3, 800)));
        Route go = route(TaskClass.CHAT, Optional.of(new Conversation(OPUS_5_5, 150_000, 400, 800)));
        System.out.println("  3 turns left:   " + show(stay));
        System.out.println("  400 turns left: " + show(go));
        check(stay.model() == OPUS_5_5 && !stay.newConversation(), "short tail stays on the warm model");
        check(go.model() == SONNET_5_5 && go.newConversation(), "long tail amortises the cold write");
        check(be > 1 && be < 400, "break-even between 1 and 400 turns");

        System.out.println("--- Claude Code aliases");
        CLAUDE_CODE_ALIAS.entrySet().stream().sorted(Map.Entry.comparingByKey())
                .forEach(en -> System.out.printf("  %-9s -> %s%n", en.getKey(), en.getValue()));
        System.out.println("ALL ASSERTIONS PASSED");
    }
}
```

**Output (verified):**

```text
--- routes for a fresh conversation
CLASSIFY_EXTRACT     -> claude-haiku-5-5   LOW    max_tokens=4096    stream=false | high volume, checkable output; low effort keeps thinking short
CHAT                 -> claude-sonnet-5-5  LOW    max_tokens=16000   stream=true  | Sonnet 5.5 guidance: start chat at low
CODE_EDIT_SMALL      -> claude-sonnet-5-5  MEDIUM max_tokens=64000   stream=true  | Sonnet 5.5 guidance: start agentic coding / multistep tool use at medium
AGENTIC_CODING_LONG  -> claude-opus-5-5    MEDIUM max_tokens=128000  stream=true  | Opus 5.5 at its medium default matched Opus 5 at high on repo-scale tasks; 128K cap worked well
ARCHITECTURE_REVIEW  -> claude-opus-5-5    HIGH   max_tokens=64000   stream=true  | one-shot, expensive-to-be-wrong; escalate to Fable 5.1 only on measured gaps
BULK_FANOUT_READ     -> claude-opus-5-5    MEDIUM max_tokens=64000   stream=true  workers=claude-haiku-5-5 | orchestrator plans and merges; cheap workers absorb the reading in their own contexts
--- escalation ladder from Sonnet 5.5 / LOW (effort first, then model)
  claude-sonnet-5-5  MEDIUM max_tokens=64000   stream=true  | re-run the failure one effort level up on the same model (cache stays warm)
  claude-sonnet-5-5  HIGH   max_tokens=64000   stream=true  | re-run the failure one effort level up on the same model (cache stays warm)
  claude-opus-5-5    MEDIUM max_tokens=64000   stream=true  NEW-CONV | model step-up: new conversation, new cache namespace
  claude-opus-5-5    HIGH   max_tokens=64000   stream=true  | re-run the failure one effort level up on the same model (cache stays warm)
  claude-fable-5-1   HIGH   max_tokens=64000   stream=true  NEW-CONV | model step-up: new conversation, new cache namespace
  claude-fable-5-1   MAX    max_tokens=64000   stream=true  | top of ladder: max effort
--- advisor pairings
  executor claude-sonnet-5-5  advisor claude-opus-5-5    -> accepted
  executor claude-haiku-5-5   advisor claude-opus-5-5    -> accepted
  executor claude-sonnet-5-5  advisor claude-opus-4-8    -> 400
  executor claude-opus-5-5    advisor claude-sonnet-5-5  -> 400
  executor claude-haiku-5-5   advisor claude-haiku-4-5   -> 400
--- mid-conversation switch (120K context, 1K output/turn)
  Opus 5.5 -> Sonnet 5.5: stay $0.0440 vs switch $0.3100 for 1 turn; switch pays from turn 14
  3 turns left:   claude-opus-5-5    LOW    max_tokens=16000   stream=true  | stay on claude-opus-5-5: a switch re-writes 150000 tokens of cache; change effort per message instead
  400 turns left: claude-sonnet-5-5  LOW    max_tokens=16000   stream=true  NEW-CONV | Sonnet 5.5 guidance: start chat at low (switch pays back over 400 turns; start at a compaction boundary)
--- Claude Code aliases
  haiku     -> claude-haiku-5-5
  opus      -> claude-opus-5-5
  opusplan  -> plan mode -> opus, execution -> sonnet (each toggle is a model switch: fresh cache)
  sonnet    -> claude-sonnet-5-5
ALL ASSERTIONS PASSED
```

### L10 · `CacheProbe.java`: the free CI check and the paid live probe (official Java SDK)

**What it shows.** In free mode, it launches five child JVMs per variant. Each child builds the request with the same assembly code and serializes the cached prefix (`tools` + `system`) through the SDK's own JSON mapper.

| Variant | Distinct cached prefixes across 5 JVMs | Why |
|---|---|---|
| `NAIVE_MAP_OF` (schema properties from `Map.copyOf`) | more than 1, varying by run (4 in the recorded run, 5 in the gate's re-run) | Iteration order is randomised per JVM, so every pod and every restart writes its own cache entry |
| `SORTED` (`TreeMap` at every level) | **exactly 1** | Deterministic |
| `TIMESTAMPED` (`Instant.now()` in `system`) | 5 | Every request differs |

The listing was compiled with `-Werror` against anthropic-java 3.3.0. In `--live` mode it sends one representative request twice, prints the four usage meters, and exits 1 if the second request read nothing from the cache.

**What it does not show.** A live cache hit, because `--live` was not run for this KB: it spends tokens.

Two output lines vary between runs by design:
- the `NAIVE_MAP_OF` count
- the `TIMESTAMPED` prefix length, because `Instant.toString()` drops trailing zeros

The program itself asserts what matters (SORTED is exactly 1, TIMESTAMPED is more than 1), and the KB gate accepts only those two lines differing.

```java
// CacheProbe.java - two prompt-cache checks for a Java service that calls Claude (anthropic-java 3.3.0).
//
//  1. FREE, run it in CI: the cached prefix (tools + system render first) must serialize to the SAME
//     BYTES in every JVM - every pod, every restart. The probe launches child JVMs, builds the request
//     with your assembly code, and compares the wire JSON. It catches two silent invalidators:
//     tool schemas built from Map.of(...) (iteration order is randomized per JVM) and a timestamp
//     interpolated into the system prompt.
//  2. PAID, with --live: send one representative request twice and print the four usage meters;
//     exit 1 if the second request read nothing from the cache.
//
//   java -cp <sdk-jars> CacheProbe.java            # free prefix-stability check
//   java -cp <sdk-jars> CacheProbe.java --live     # spends tokens; needs ANTHROPIC_API_KEY
import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.JsonValue;
import com.anthropic.core.ObjectMappers;
import com.anthropic.models.messages.CacheControlEphemeral;
import com.anthropic.models.messages.Message;
import com.anthropic.models.messages.MessageCountTokensParams;
import com.anthropic.models.messages.MessageCreateParams;
import com.anthropic.models.messages.OutputConfig;
import com.anthropic.models.messages.TextBlockParam;
import com.anthropic.models.messages.Tool;
import com.anthropic.models.messages.Usage;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public final class CacheProbe {

    static final String MODEL = "claude-opus-5-5";

    static final String RULES = """
            <role>Order-service assistant for a Java 21 / Spring Boot 3.5 / PostgreSQL 17 platform.</role>
            <invariants>
            - Read order data only through the get_order tool; never guess field values.
            - Money is NUMERIC(12,2) in EUR; never round in intermediate steps.
            </invariants>
            <output_contract>JSON: {"order_id": string, "status": string, "explanation": string}</output_contract>
            """;

    enum Variant { NAIVE_MAP_OF, SORTED, TIMESTAMPED }

    static final String[][] FIELDS = {
            {"order_id", "string", "UUIDv7 of the order"}, {"include_lines", "boolean", "return line items"},
            {"currency", "string", "ISO-4217 code"}, {"as_of", "string", "ISO-8601 instant"},
            {"tenant", "string", "tenant slug"}, {"max_lines", "integer", "page size"}};

    static Map<String, JsonValue> schemaProperties(Variant v) {
        if (v == Variant.NAIVE_MAP_OF) {                         // Map.of/Map.copyOf: per-JVM randomized order
            Map<String, JsonValue> props = new java.util.HashMap<>();
            for (String[] f : FIELDS) props.put(f[0], JsonValue.from(Map.of("type", f[1], "description", f[2])));
            return Map.copyOf(props);
        }
        Map<String, JsonValue> props = new TreeMap<>();          // deterministic at every level
        for (String[] f : FIELDS) {
            Map<String, String> inner = new TreeMap<>(Map.of("type", f[1], "description", f[2]));
            props.put(f[0], JsonValue.from(inner));
        }
        return props;
    }

    static MessageCreateParams request(Variant v, String question) {
        String system = v == Variant.TIMESTAMPED ? "Current time: " + Instant.now() + "\n" + RULES : RULES;
        Tool getOrder = Tool.builder()
                .name("get_order")
                .description("Fetch one order by id.")
                .inputSchema(Tool.InputSchema.builder()
                        .properties(Tool.InputSchema.Properties.builder().putAllAdditionalProperties(schemaProperties(v)).build())
                        .addRequired("order_id")
                        .build())
                .build();
        return MessageCreateParams.builder()
                .model(MODEL)
                .maxTokens(8_000L)
                .outputConfig(OutputConfig.builder().effort(OutputConfig.Effort.LOW).build())
                .addTool(getOrder)
                .systemOfTextBlockParams(List.of(TextBlockParam.builder().text(system)
                        .cacheControl(CacheControlEphemeral.builder().build()).build()))
                .addUserMessage(question)
                .build();
    }

    /** The cached prefix is everything up to the breakpoint: tools, then system. */
    static String prefixJson(MessageCreateParams p) throws IOException {
        JsonMapper mapper = ObjectMappers.jsonMapper();
        JsonNode body = mapper.valueToTree(p._body());
        ObjectNode prefix = mapper.createObjectNode();
        prefix.set("tools", body.get("tools"));
        prefix.set("system", body.get("system"));
        return mapper.writeValueAsString(prefix);
    }

    static String runChild(Variant v) throws IOException, InterruptedException {
        String java = ProcessHandle.current().info().command().orElse("java");
        Process p = new ProcessBuilder(java, "-cp", System.getProperty("java.class.path"), "CacheProbe", "--child", v.name())
                .redirectErrorStream(true).start();
        String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8).strip();
        if (p.waitFor() != 0) throw new IllegalStateException("child failed: " + out);
        return out;
    }

    static int firstDivergence(String a, String b) {
        int n = Math.min(a.length(), b.length());
        for (int i = 0; i < n; i++) if (a.charAt(i) != b.charAt(i)) return i;
        return a.length() == b.length() ? -1 : n;
    }

    static void live() {
        AnthropicClient client = AnthropicOkHttpClient.fromEnv();
        MessageCreateParams params = request(Variant.SORTED, "What is the status of order 0192f3c4?");
        long prefixTokens = client.messages().countTokens(MessageCountTokensParams.builder()
                .model(MODEL).systemOfTextBlockParams(params.system().orElseThrow().asTextBlockParams())
                .addUserMessage("x").build()).inputTokens();
        System.out.println("system prefix ~" + prefixTokens + " tokens (cache minimum on " + MODEL + ": 512)");
        Usage[] u = new Usage[2];
        for (int i = 0; i < 2; i++) {
            Message m = client.messages().create(params);
            u[i] = m.usage();
            System.out.printf("request %d: input=%d cache_write=%d cache_read=%d output=%d%n", i + 1, u[i].inputTokens(),
                    u[i].cacheCreationInputTokens().orElse(0L), u[i].cacheReadInputTokens().orElse(0L), u[i].outputTokens());
        }
        if (u[1].cacheReadInputTokens().orElse(0L) == 0L) {
            System.out.println("FAIL: second identical request read nothing from cache - diff the payloads");
            System.exit(1);
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 2 && args[0].equals("--child")) {
            System.out.println(prefixJson(request(Variant.valueOf(args[1]), "q")));
            return;
        }
        if (args.length == 1 && args[0].equals("--live")) {
            live();
            return;
        }
        int jvms = 5;
        for (Variant v : Variant.values()) {
            List<String> outs = new ArrayList<>();
            for (int i = 0; i < jvms; i++) outs.add(runChild(v));
            Set<String> distinct = new LinkedHashSet<>(outs);
            String where = distinct.size() > 1
                    ? ", first divergence at char " + firstDivergence(List.copyOf(distinct).get(0), List.copyOf(distinct).get(1))
                    : "";
            System.out.printf("%-13s %d JVMs -> %d distinct cached prefixes (%d chars)%s%n",
                    v, jvms, distinct.size(), outs.get(0).length(), where);
            if (v == Variant.SORTED && distinct.size() != 1)
                throw new AssertionError("deterministic assembly produced different prefixes");
            if (v == Variant.TIMESTAMPED && distinct.size() == 1)
                throw new AssertionError("timestamped prefix should differ between JVMs");
        }
        System.out.println("prefix stability check done (free); run with --live to measure real cache reads");
    }
}
```

**Output (verified, free mode):**

```text
NAIVE_MAP_OF  5 JVMs -> 4 distinct cached prefixes (963 chars), first divergence at char 70
SORTED        5 JVMs -> 1 distinct cached prefixes (963 chars)
TIMESTAMPED   5 JVMs -> 5 distinct cached prefixes (1009 chars), first divergence at char 558
prefix stability check done (free); run with --live to measure real cache reads
```

---

## 4. Failure modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Bill rose after "routing easy turns to a cheaper model" | `cache_creation_input_tokens` ≈ the full context on the switched turns | Caches are model-scoped; every switch is a cold write | Keep the conversation on its model; delegate cheap sub-tasks to sub-agents with small contexts | L9 `switchPays` |
| F2 | Haiku 5.5 RAG cost jumped ~5× | Prompts just over 100K tokens | Haiku 5.5's tier applies to the *whole* request, cache reads included | Retrieve fewer or shorter chunks; cap the prompt below 100K | L5 RQ19; a dashboard on the >100K share |
| F3 | Cache hit rate fell to about 1/N after scaling to N pods | Each pod reads its own entry; payloads differ only in key order | Tool schemas or system fragments built from `Map.of`/`HashMap`/sets | Sorted maps; sorted tools | L10 free mode in CI |
| F4 | `400 invalid_request_error` when enabling the advisor | The executor/advisor pair is outside the table | The advisor is less capable than the executor, or not accepted by it (e.g. Sonnet 5.5 + Opus 4.8) | Choose an accepted pair | L9 `validateAdvisor` |
| F5 | The advisor "returns nothing" | Code reads `.text`; the block is `advisor_redacted_result` | 5.x advisors return encrypted advice | Switch on the content type; replay the blocks | Typed handling of the union |
| F6 | 400 on a later turn after turning the advisor off | History contains `advisor_tool_result` blocks | The tool was removed from `tools` while its results remain | Keep the tool declared for the conversation | Freeze tools per conversation |
| F7 | Parallel reviewers cost N× | N simultaneous writes, zero reads | Entries become readable only once the first response streams | One request, await the first token, then fan out | L8 §4 |
| F8 | The 1h TTL costs more than expected | Every turn's new tokens are written at 2× | 1h pays per written token, not once | Price the gap distribution; consider keep-alive pings | L8 §3 |
| F9 | `opusplan` sessions cost more than plain `sonnet` | A cold write after every plan-mode toggle | Plan mode and execution use different models, so different caches | Plan once, then execute; avoid frequent toggling on large contexts | — |
| F10 | Fast mode 429s, and the fallback is slow *and* expensive | Retrying without `speed` re-writes the cache | Fast mode has its own rate limit; a speed change invalidates the cache | Back off on `retry-after` first; fall back deliberately | Separate dashboards for fast and standard |
| F11 | Per-token comparison said Sonnet 5.5 is cheaper; the invoice disagreed | More tokens per task than expected | Tokenizer differences (about 30% more tokens than 4.x) and a different task length | Compare $/solved with `count_tokens` on real inputs | §2.2 worksheet |
| F12 | Opus 5.5 at the same effort as Opus 5 costs more | Longer turns at `xhigh`/`max` | At a given level Opus 5.5 thinks more per turn | Start at `medium`; reserve `xhigh`/`max` for measured gains | Re-sweep on migration |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Haiku 5.5 is 40× cheaper per token than Opus 5.5. Move everything to Haiku."</b></summary>

**Naive answer.** "Yes, 97% saving." Or, just as naively: "No, Haiku is dumb."

**Why it fails.** Per-token price isn't cost per solved task. Haiku 5.5's tokenizer counts more tokens. Its 100K tier quintuples the price above that size. It has no server-side refusal fallback. And on long agentic loops a weaker model can take more turns and fail more, and the failures are where the money goes.

**Staff answer.** Split by route:
- **Checkable, high-volume work** (classification, extraction, routing, sub-agent reading) goes to Haiku 5.5 at `low`, with structured outputs and validators.
- **Everything else** first gets an effort sweep on Opus 5.5. Anthropic found the frontier model at low effort sometimes out-solves a smaller model for less per solved task.

Decide with the §2.2 worksheet on the hard decile, not on the median.
</details>

<details><summary><b>D2 · "Our router sends follow-up questions to Sonnet 5.5 mid-conversation because they're easy."</b></summary>

**Staff answer.** On a 120K-token conversation, that turn costs $0.3106 instead of $0.0440: a cold write of the whole context on a model that has never seen it (L9). It pays back only if the conversation then stays on Sonnet 5.5 for 14+ turns, and even then you lose Opus 5.5's thinking blocks.

Keep the conversation on its model and lower effort per message instead (file 02 §2.3). If a sub-task is truly separable, give it to a sub-agent with a small fresh context.
</details>

<details><summary><b>D3 · "Set the 1-hour TTL everywhere. It can't be worse."</b></summary>

**Staff answer.** It can. The 1h TTL writes every new token at 2× instead of 1.25×, so in a growing conversation the premium recurs every turn.

- With traffic under 5 minutes apart, the 5-minute cache stays warm on its own and the 1h TTL is pure overhead.
- In L8's tight session, keep-alive pings beat 1h on both Opus 5.5 and Fable 5.1.
- In the loose session, 1h wins.

Price your actual start-to-start gap distribution. Remember the lifetime runs from the *start* of each request, so generation time counts against it.
</details>

<details><summary><b>D4 · "Eight parallel review sub-agents cost about 3.6× what we budgeted."</b></summary>

**Staff answer.** All eight wrote the same 40K-token prefix, because none could read an entry before the first response started streaming [doc]. Send one, await its first token, then fan out the other seven: $0.256 instead of $0.928 (L8).

In Claude Code, sub-agents start fresh contexts anyway. Keep their prompts small and their shared prefix byte-identical.
</details>

<details><summary><b>D5 · "We paired a Sonnet 5.5 executor with an Opus 4.8 advisor and got a 400. Opus is bigger, so why?"</b></summary>

**Staff answer.** The executor decides which advisors it accepts, not raw size. Sonnet 5.5 rejects Opus 4.8, 4.7 and 4.6, Sonnet 5 and Sonnet 4.6 advisors, and accepts Fable 5.1, Fable 5, Opus 5.5, Opus 5 and Sonnet 5.5.

Any accepted 5.x advisor returns *encrypted* advice (`advisor_redacted_result`). Code must switch on the content type and replay the blocks unchanged. Then benchmark: the advisor often buys about what more executor effort would.
</details>

<details><summary><b>D6 · "Fable 5.1 is the best model. Use it for every architecture review."</b></summary>

**Staff answer.** Fable 5.1 is 2.5× Opus 5.5's price per token. Its turns run long (minutes per request on hard tasks), and it requires 30-day data retention.

It earns its price on the hardest long-horizon work, and its 0.025× cache reads make long sessions over a big context cheap per turn. Route reviews to Opus 5.5 at `high` with a Devil's-advocate contract. Escalate to Fable 5.1 where an eval shows Opus misses, for example cross-system failure analysis over large inputs. Measure on your review set; don't decide by reputation.
</details>

<details><summary><b>D7 · "Batch is 50% off and caching is 90% off, so batch plus cache is 95% off?"</b></summary>

**Staff answer.** The multipliers do stack [doc]. But cache hits inside a concurrent batch are best-effort, and requests in a batch can't wait for each other's first token.

L8's example on Haiku 5.5 gave sync cached $1.05 and batch + cache (at an assumed 70% hit rate) $1.04: the batch discount was eaten by misses. Measure the batch's real hit rate from the results' `usage` before promising savings.
</details>

<details><summary><b>D8 · "Our Haiku 5.5 RAG bill quintupled after we added two documents to the context."</b></summary>

**Staff answer.** The prompt crossed 100K tokens, and above that line the *entire* request (cache reads included) bills at $0.50 / $2.50 instead of $0.10 / $0.50. L8: $0.00690 vs $0.00138 for requests 301 tokens apart.

Cap retrieval to stay below 100K, or move that route to Sonnet 5.5, whose 1M window is billed at a flat rate.
</details>

<details><summary><b>D9 · "Explain the cost profile of Claude Code's <code>opusplan</code>."</b></summary>

**Staff answer.** Plan mode runs `opus` (Opus 5.5) and execution runs `sonnet` (Sonnet 5.5). Each toggle is a model switch with a fresh cache [doc]. Toggle once (a short plan, a long execution) and you get Opus-quality planning for one cold write. Toggle often on a large context and every toggle re-writes it.

Alternatives: `opus` at `medium` throughout (one cache), or `sonnet` plus `/advisor opus` (the advisor's toggling doesn't invalidate the main cache).
</details>

<details><summary><b>D10 · "Is fast mode worth it?"</b></summary>

**Staff answer.** It is the same model at up to 2.5× output speed for 2× the per-token price ($8 / $40 on Opus 5.5).

- **Worth it:** latency-critical interactive work, such as live pairing or incident response, where human time dominates.
- **Not worth it:** batch or background agents. It isn't available with Batch at all.
- **Operations:** it has its own rate limit, and switching `speed` invalidates the cache. Keep a session on one speed and handle 429s with `retry-after` before falling back.
</details>

---

## 6. Invariants checklist

- [ ] Model choices are justified by $/solved on the hard decile, measured with the §2.2 worksheet. The date and model versions are recorded.
- [ ] Every route sets effort explicitly, and an effort sweep preceded any model change.
- [ ] Conversations stay on one model. Cheap sub-tasks go to sub-agents, and model step-ups start new conversations.
- [ ] Prompt builders are byte-deterministic across JVMs, and L10's free check runs in CI.
- [ ] Fan-out sends one request first and waits for its first token.
- [ ] The TTL was chosen from the measured gap distribution.
- [ ] Haiku 5.5 routes keep prompts below 100K tokens, and a dashboard watches the >100K share.
- [ ] Advisor pairs are validated in code, and advice blocks are handled as a union and replayed.
- [ ] MCP servers are scoped per project, with tool search or `defer_loading` once schemas pass about 10K tokens.
- [ ] Dashboards track cache-read share, $/solved, `max_tokens` stops, refusals by category, and thinking share.
- [ ] Prices come from the live pricing page, never from memory. This KB's table is dated 2026-10-30.

---

## 7. References

Anthropic documentation (read 2026-10-30):
- Pricing (models, cache multipliers, batch, long context, data residency, fast mode): <https://platform.claude.com/docs/en/about-claude/pricing>
- Optimizing for cost and intelligence (lever order, effort curves, advisor and orchestrator measurements): <https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence>
- Models overview: <https://platform.claude.com/docs/en/models/overview>
- Prompt caching: <https://platform.claude.com/docs/en/build-with-claude/prompt-caching>
- Batch processing: <https://platform.claude.com/docs/en/build-with-claude/batch-processing>
- Token counting: <https://platform.claude.com/docs/en/build-with-claude/token-counting>
- Fast mode: <https://platform.claude.com/docs/en/build-with-claude/fast-mode>
- Data residency: <https://platform.claude.com/docs/en/manage-claude/data-residency>
- Claude Code model configuration: <https://code.claude.com/docs/en/model-config>
- Claude Code advisor: <https://code.claude.com/docs/en/advisor>
- Claude Code fast mode: <https://code.claude.com/docs/en/fast-mode>
- Claude Code prompt caching: <https://code.claude.com/docs/en/prompt-caching>
- Claude Code costs and `/usage`: <https://code.claude.com/docs/en/costs>
- Claude Code context window and compaction: <https://code.claude.com/docs/en/context-window>
- Claude Code environment variables: <https://code.claude.com/docs/en/env-vars>

SDK:
- Anthropic Java SDK (`com.anthropic:anthropic-java`), used here at 3.3.0: <https://github.com/anthropics/anthropic-sdk-java>

Previous: [02 · Extended thinking physics](02-extended-thinking-physics-when-to-use-and-how-to-prompt-reasoning-models.md) · [01 · Attention and XML grammar](01-transformer-attention-lost-in-the-middle-and-xml-tag-grammar.md) · [KB README](../README.md)
