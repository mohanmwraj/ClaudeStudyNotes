# Extended Thinking Physics: When to Use It and How to Prompt Reasoning Models

> **Folder 01 · File 2 of 3** · verified 2026-10-30 · API surface: `thinking: {type: "adaptive"}` + `output_config.effort`; `budget_tokens` is removed on every current 5.x model
> **Listings:** `ThinkingPromptAuditor.java` · `request_shape_linter.py` · `thinking_economics.py` · `AdaptiveThinkingClient.java` (compiled against anthropic-java 3.3.0 and dry-run)

---

## 0. Orientation

"Extended thinking" started life in 2025 as a per-request token budget. By late 2026 it is something different. On Claude Opus 5.5 and Fable 5.1, **thinking is always on**. The model decides per request whether and how much to think, and the main dial is **effort** [doc].

Most thinking advice in circulation predates that change, and some of it now returns HTTP 400. `budget_tokens`, `thinking: {type: "disabled"}` on Opus 5.5, and `temperature` on API version 2026-10-21 all fail. Some of it now hurts quality: hand-written step-by-step reasoning scripts, and verification instructions on Opus 5. And one piece can now get your request *declined*: asking the model to write its reasoning in the response.

This file explains what thinking is mechanically and what it costs. It shows how to prompt for it with **constraints and verification criteria instead of scripts**, how it interacts with caching and conversation history, and where the model's "default answer" comes from when you under-specify. The last point is the real reason vague prompts produce tutorial-grade Java.

Claim labels as in [file 01 §0](01-transformer-attention-lost-in-the-middle-and-xml-tag-grammar.md#0-orientation): **[doc]**, **[measured]**, **[research]**, **[inference]**, ⚠ verify.

### 0.1 The twelve rules

1. **On Opus 5.5 and Fable 5.1 you cannot turn thinking off. Effort is the control.** Opus 5.5 defaults to `medium`, one level below Opus 5, so set it explicitly per route. [doc]
2. **State the goal, invariants, edge cases and verification criteria; don't script the reasoning.** "Prefer general instructions over prescriptive steps … Claude's reasoning frequently exceeds what a human would prescribe." [doc]
3. **Keep numbered steps for required *actions*** (a mandated order of operations), never for *thoughts*. [doc + inference]
4. **Never ask for reasoning in the response** ("show your reasoning in `<thinking>` tags"). On Opus 5.5, Opus 5, Fable 5.1 and Sonnet 5.5 it may be declined as `reasoning_extraction`, and server-side fallback does not retry those declines. Read `display: "summarized"` thinking blocks instead. [doc]
5. **Lower effort before you write "think less".** Prose steering is wording-sensitive, and on Sonnet 5.5 and Haiku 5.5 it does not reliably reduce thinking. [doc]
6. **Size `max_tokens` for thinking plus answer, and stream.** Thinking counts toward the cap. With illustrative token distributions, a 4,096 cap truncates 61.7% of high-effort turns. Use 64K for agentic work, and up to 128K on Opus 5.5 for long coding turns. [doc + measured: L6]
7. **Thinking is billed in full as output**, whatever `display` shows. 6,000 thinking tokens on Opus 5.5 cost as much as 30,000 input tokens. [doc + measured: L6]
8. **Pin the thinking config and top-level effort per conversation.** Changing either invalidates the messages cache. On models that support it, change effort with a per-message system message (beta), which keeps the cache. [doc]
9. **Pass thinking blocks back unchanged, and keep history append-only.** On Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1, editing earlier turns invalidates thinking blocks, and accounts created on or after 2026-08-31 get a 400 on edited history. [doc]
10. **Model-specific exception: on Opus 5, remove carried-over "verify your work" instructions.** They cause over-verification. [doc]
11. **Multishot examples still work with thinking.** Show the problem, the method and the answer. [doc]
12. **In Claude Code, `ultrathink` deepens one turn and `/effort` sets the session.** "think hard" is now passed through as ordinary text. [doc]

---

## 1. First principles

### 1.1 What thinking is, mechanically [research, doc]

A transformer does a **fixed amount of computation per generated token**: one pass through L layers. Problems that need more serial steps than the network's depth can be solved only by writing intermediate results into the sequence and reading them back. That is what reasoning tokens are: **test-time compute expressed as text the model conditions on.**

- **Theory.** Merrill & Sabharwal (ICLR 2024) prove that a linear number of chain-of-thought steps lets transformers recognise every regular language, and that polynomially many steps reach exactly P. Without intermediate steps, bounded-depth transformers sit in a much weaker class. Feng et al. (NeurIPS 2023) show the same separation concretely for arithmetic and dynamic programming. [research]
- **Practice.** Models trained with reinforcement learning on verifiable tasks learn search behaviours inside that scratch space: proposing, checking, backtracking, re-deriving. The public record of this is the open DeepSeek-R1 report (2025). Anthropic has not published Claude's thinking-training recipe. [research; Claude-specific details unpublished]

Thinking on the API differs from "chain-of-thought in the answer" in four ways [doc]:

1. **It is a separate content block** (`thinking`). The raw chain of thought is never returned on current models. `display: "summarized"` returns a summary; `display: "omitted"` is the default on 4.7+/5.x and returns an empty `thinking` field.
2. **It is adaptive.** "On each request, Claude evaluates the complexity of the input and determines whether deeper reasoning would improve the answer." A simple question gets no thinking block at all, so never assume a response starts with one.
3. **It interleaves with tools.** Claude thinks between tool calls without any beta header. "The first request after new user input typically carries most of the reasoning, and follow-up requests that only process tool results can skip thinking, including at `xhigh` and `max`."
4. **A specialized system prompt is added automatically when thinking is active.** Expect input-token counts slightly above what you sent.

### 1.2 Why scripted reasoning hurts reasoning models [doc, inference]

Compare these two prompts:

```text
A (scripted)      Think step by step. Step 1: think about the entities. Step 2: consider the API.
                  Step 3: analyze concurrency. Then write the service.
B (contract)      Goal + invariants + edge cases + "before outputting code, verify X and Y".
```

Prompt A imposes **your decomposition** on a search procedure that was trained to find its own. If your decomposition is right, it adds nothing. If it is wrong, it actively misleads. The classic failure is asking for concurrency analysis *after* the API is designed, when concurrency is what should shape the API. Anthropic's guidance says it plainly: "A prompt such as 'think thoroughly' often produces better reasoning than a hand-written step-by-step plan" [doc]. Its migration guidance for Fable 5.1 goes further: prompts written for prior models "are often too prescriptive … and *reduce* output quality … prefer stating the goal and constraints over enumerating the steps" [doc].

**The backend analogy [inference].** A reasoning model is a query planner. You give a planner a declarative query (the result you need, its constraints and indexes) and let it choose the join order. Plan hints help only when you know something the planner cannot. "Step 1: think about entities" is a join-order hint from someone who hasn't seen the statistics.

**What survives: process constraints.** Ordered steps remain correct when the *order of actions* is itself a requirement: "run Flyway before starting the app", "acquire the account lock before the ledger lock", "open the PR only after tests pass". Anthropic's "be clear and direct" guidance keeps numbered steps "when the order or completeness of steps matters" [doc]. The distinction is simple:

| Keep (process constraint) | Delete (reasoning script) |
|---|---|
| "1. Write the migration. 2. Run it against Testcontainers PG17. 3. Only then change the entity." | "Step 1: Think about the schema. Step 2: Consider the entity." |
| "Acquire locks in ascending account id order." | "First reason about locking, then reason about deadlocks." |
| "Return the diff, then the test list." | "Let's think step by step." |

L4 (`ThinkingPromptAuditor`) encodes exactly this split. Numbered lines whose verb is *think / consider / analyze / reason / reflect / brainstorm* are flagged. Numbered *actions* are not.

### 1.3 What to give instead: the verification contract [doc, inference]

Thinking needs an **objective** and **stopping criteria**. Give them as named blocks:

| Block | Role in the model's search | Java example |
|---|---|---|
| `<goal>` | What "done" means | "POST /orders creates an order exactly once per Idempotency-Key." |
| `<context>` | Why it matters, so the model can generalise | "Mobile clients retry on timeout; duplicates cost real money." |
| `<invariants>` | Properties every candidate must satisfy | "Never hold a JDBC connection across Kafka/HTTP I/O. Locks in ascending PK order." |
| `<edge_cases>` | Concrete adversarial inputs to test candidates against | "50 concurrent retries with one key; broker down 30 s; 10,000 line items." |
| `<anti_goals>` | Tempting but wrong moves | "No distributed locks; no read-then-insert idempotency check." |
| `<verification>` | The checks to run before answering | "Before outputting code, verify no transaction spans an outbound call and that each edge case maps to a named test." |
| `<output_contract>` | The shape of the answer | "Diffs, then an invariant→test table." |

This works for three reasons:

- Invariants **prune** the space of candidate solutions.
- Edge cases are **test vectors** the model can mentally execute.
- Verification criteria are a **stopping rule**: a candidate that fails them sends the search back to work.

Anthropic documents the last move: "Append something like 'Before you finish, verify your answer against [test criteria].' This catches errors reliably, especially for coding and math" [doc].

**Two exceptions to know:**

1. **Claude Opus 5 over-verifies.** It "verifies its own work well without explicit instruction, and verification instructions carried over from prompts tuned for earlier models can cause over-verification." On Opus 5, *remove* them rather than rewriting them [doc]. L4 downgrades the rule to an INFO "remove" on that model.
2. **"Verify in your thinking" is fine; "show your verification" is not.** The first asks the model to think. The second pushes reasoning into the response (§1.8).

### 1.4 Adaptive thinking and the effort dial [doc]

Effort is set at `output_config.effort`, not inside `thinking`. Per the docs:

| Effort | Thinking behaviour |
|---|---|
| `max` | Thinks most readily and most deeply; no constraint on length. |
| `xhigh` | More readily and more deeply than `high`; suited to extended exploration. |
| `high` | Thinks on most requests that benefit; deep reasoning on complex tasks. **Default on most models.** |
| `medium` | Moderate thinking; may skip it for simple queries. **Default on Opus 5.5 and Haiku 5.5.** |
| `low` | Minimises thinking; skips it for simple tasks where speed matters. |

Effort shapes more than thinking: "lower effort means fewer and more-consolidated tool calls, less preamble, and terser confirmations" [doc]. Effort names also **don't transfer across models**. "Claude Opus 5.5 at `medium` matches or exceeds Claude Opus 5 at `high` on coding and knowledge-work evaluations, and on several coding evaluations `low` comes close to it at much lower cost" [doc]. Re-run your effort sweep on every model migration.

**Per-model thinking configuration (2026-10-30)** [doc]:

| Model | Omit `thinking` → | Can thinking be turned off? | `budget_tokens` | `temperature`/`top_p`/`top_k` | Effort levels (default) |
|---|---|---|---|---|---|
| Fable 5.1 | adaptive (always on) | **No**: `disabled` is a 400 | 400 | 400 | low–max (`high`) |
| Opus 5.5 | adaptive (always on) | **No**: `disabled` is a 400 at every effort | 400 | 400 | low–max (**`medium`**) |
| Opus 5 | adaptive | `disabled` only at effort ≤ `high` | 400 | 400 | low–max (`high`) |
| Opus 4.8 / 4.7 | **no thinking** | yes | 400 | 400 | low–max (`high`) |
| Sonnet 5.5 | adaptive | only via `{type: "between_tools"}`, at ≤ `high`, no other fields | 400 | non-default values 400 | low–max (`high`, recalibrated) |
| Haiku 5.5 | adaptive | `disabled` only at ≤ `high` | 400 | non-default values 400 | low–max (**`medium`**) |
| Opus 4.6 / Sonnet 4.6 | no thinking (set adaptive) | yes | deprecated, still works | 400 on API `2026-10-21` | low, medium, high, max (`high`) |
| Haiku 4.5 | no thinking | — | **required** for thinking (≥ 1,024, < `max_tokens`) | 400 on API `2026-10-21` | none |

On API version `2026-10-21`, sending `temperature`, `top_p` or `top_k` returns a 400 on every model [doc]. L5 (`request_shape_linter.py`) encodes this table, and all 16 of its checks pass.

**Claude Code's defaults differ from the API's ⚠ verify.** In Claude Code, effort defaults to `medium` on Opus 5.5, Sonnet 5.5 and Haiku 5.5, `xhigh` on Opus 4.7, and `high` elsewhere. On the raw API, Sonnet 5.5 defaults to `high`.

The resolution order in Claude Code is:
1. `CLAUDE_CODE_EFFORT_LEVEL`
2. the session pick (`/effort` or the `/model` picker)
3. `--effort`
4. settings (`effortLevel`)
5. the model default

`/effort` also accepts `auto` (send no level), and `max` is session-only [doc: code.claude.com model-config, commands].

### 1.5 Thinking in agent loops: interleaving and progress updates [doc]

In a tool loop, Claude can think after every tool result and decide what to do next. No configuration is needed. Two consequences for harness authors:

1. **Long agentic turns can look silent.** On Opus 5.5 and Fable 5.1, the short notes the model writes between tool calls arrive as *progress-update `thinking` blocks*, and their text is empty under the default `display: "omitted"`. A client that renders only `text` blocks goes quiet for minutes. Set `display: "updates"` (beta `thinking-display-updates-2026-08-18`) to receive a short summary of each note [doc].
2. **Don't treat a text-only end of turn as task completion** in unattended agents. Opus 5.5 sometimes ends a turn with a status report. Keep a checklist, send a short "your task list still has open items" continuation, and cap automatic continuations at two or three [doc].

### 1.6 What thinking costs, and how `max_tokens` bounds it [doc, measured: L6]

- **Billing.** You pay output price for every thinking token the model generates, plus input price for prior-turn thinking blocks kept in context. "What you're billed for is the same regardless of the `display` setting." `usage.output_tokens_details.thinking_tokens` gives the split; `output_tokens` stays the billing total [doc].

  L6 prices it: 6,000 thinking tokens plus an 800-token answer cost **$0.136** on Opus 5.5 and **$0.340** on Fable 5.1. In each case the thinking alone equals **30,000 input tokens**, because output is 5× input on every current model.
- **The cap.** "`max_tokens` is a hard cap on total output for the request, thinking and response text combined" [doc]. With illustrative lognormal thinking distributions per effort level, L6 measures truncation probability [measured]:

| Effort | P(truncated) at 4,096 | at 16,000 | at 64,000 | at 128,000 |
|---|---|---|---|---|
| low | 2.27% | 0.01% | 0.00% | 0.00% |
| medium | 26.00% | 1.08% | 0.01% | 0.00% |
| high | **61.70%** | 9.43% | 0.30% | 0.03% |
| xhigh | 86.05% | 30.82% | 2.59% | 0.41% |
| max | 95.07% | 52.89% | 8.62% | 1.94% |

  The distributions are placeholders, but the shape is general: **a cap sized for thinking-off answers silently truncates reasoning-heavy turns.** Anthropic's guidance gives 64K as a reasonable start for long agentic coding turns, and says that on Opus 5.5 "a `max_tokens` of 128,000, the model's maximum, has worked well" [doc]. Large caps need streaming to avoid SDK HTTP timeouts.

  On `stop_reason: "max_tokens"`, either raise the cap (if the truncated requests needed the reasoning) or lower effort (if they were over-thought) [doc]. Treat the truncated attempt as a failure, not a partial success.

### 1.7 Thinking, caching and conversation history [doc]

1. **Thinking config and effort are part of the prompt.** "The resolved effort value is rendered into the prompt, so changing it between requests invalidates cache breakpoints." Setting effort explicitly *to the model's default* is equivalent to omitting it [doc]. The docs show it directly: changing effort from `medium` to `low` on turn 3 turned a 3,546-token cache read into a 3,546-token cache write.
2. **Per-message effort (beta) keeps the cache.** On Fable 5.1, Opus 5.5, Opus 5, Sonnet 5.5 and Haiku 5.5 (with thinking on), a `{"role": "system", "content": [], "output_config": {"effort": "low"}}` message changes effort for later turns without invalidating the messages cache (beta `mid-conversation-output-config-2026-07-01`) [doc]. Claude Code keeps the cache across `/effort` changes on Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1; on other models the change invalidates it [doc: code.claude.com prompt-caching].
3. **Prior-turn thinking blocks stay in context** on "keep-all" models: Opus 4.5 and later, Sonnet 4.6 and later, Haiku 5.5, and Fable. They are billed as input, which on a warm cache means mostly at cache-read price. L6 shows a 20-turn session carrying 1,000,000 input tokens with thinking kept versus 430,000 with it stripped. That is $4.00 vs $1.72 uncached, but only $0.20 vs $0.09 at Opus 5.5's read price [measured]. Keep the blocks; the cache absorbs them.
4. **Preserved thinking: history is append-only.** On Fable 5.1, Opus 5.5, Sonnet 5.5 and Haiku 5.5, thinking blocks are bound to the model and to the conversation that produced them. Editing `system`, `tools` or earlier messages invalidates later thinking blocks, and accounts created on or after 2026-08-31 get a 400 on edited history (enforcement is decided per model ⚠ verify).
   - Server-side compaction and context editing don't count as edits.
   - Inject-then-delete reminders do count. Use appended, turn-scoped system messages (`clear_at: "next_user_message"`, beta) instead [doc].
   - Pass blocks back unchanged even after a model switch. The API silently drops, unbilled, any block the new model can't read [doc].

### 1.8 The reasoning-extraction safeguard [doc]

Opus 5.5 runs safety classifiers that include *reasoning extraction*. So do Opus 5, Fable 5.1 and Sonnet 5.5, where the docs name the same risk. "Requests that push the model to reproduce its internal reasoning in the response text might be declined with the `reasoning_extraction` category."

A decline is an HTTP 200 with `stop_reason: "refusal"` and `stop_details.category`. Server-side fallback returns `reasoning_extraction` declines to you instead of retrying them [doc]. What to do:

- Delete "show your reasoning", "write your chain of thought" and "put your reasoning in `<thinking>` tags" from prompts that target these models.
- Set `display: "summarized"` and read the thinking blocks.
- You may still ask for "a short explanation of the answer or a summary of the actions taken" [doc]. That is a deliverable, not a transcript of reasoning.

This is a breaking change for 2024-era "manual CoT" prompts. The docs now say: "On Claude Fable 5.1, Claude Fable 5, Claude Opus 5.5, Claude Opus 5, and Claude Sonnet 5.5, rely on thinking instead" [doc].

### 1.9 When thinking pays, and when it is pure latency [doc]

| Workload | Effort guidance | Source / reason |
|---|---|---|
| Classification, extraction, routing | `low` (Haiku 5.5) | Checkable output; thinking rarely changes the label |
| Chat | `low` on Sonnet 5.5; on Opus 5.5 remove "think carefully before answering" lines | [doc] In a chat product, removing that line made Opus 5.5 replies start sooner "with no clear decline in the quality" |
| Research / knowledge work | `medium` often matches `high` | [doc] Nearly flat effort curves in Anthropic's runs |
| Long-horizon agentic coding | Start `medium` on Opus 5.5; raise on measured failures | [doc] A real trade-off; each step down gave up a few points of pass rate for a much lower cost |
| Concurrency proofs, design review, hard debugging | `high`/`xhigh`, with a verification contract | Serial reasoning depth is the product |
| Latency-critical replies | `low`, and measure "Answer directly without deliberating." | [doc] Steering wording matters; measure quality |

Two Opus 5.5 behaviours worth prompting around [doc]:

- **Re-examining settled answers in multi-turn chat.** It sometimes re-thinks earlier answers, which adds latency. "Once you have answered something, treat that answer as done …" reduces it, but may also make the model less likely to volunteer a correction.
- **Longer turns at `xhigh`/`max`** than Opus 5. Lower effort before prompting for brevity.

### 1.10 Why vague prompts produce tutorial-grade Java: the prior fills every open degree of freedom [inference]

A model's output is a sample from p(code | prompt). For "Build a Spring Boot Order Service", the conditioning is weak, so the distribution is dominated by the documents that most resemble that request in training data: tutorials, starter projects and blog posts. Those are written to be *short*, not to survive production. Thinking helps the model reason about consequences, but **every decision you leave unstated is a decision you have delegated to that prior.** Current models often choose better defaults than 2019-era tutorials did. You cannot rely on it, and you cannot review what you didn't specify.

Each constraint you state conditions away a region of tutorial space:

| Tutorial-space default | Production constraint to state | Why it matters (verifiable fact) |
|---|---|---|
| `@Autowired` field injection | Constructor injection, `final` fields | Immutability, and testability without a container |
| `@GeneratedValue(strategy = IDENTITY)` | `SEQUENCE` with a pooled optimizer (`allocationSize` > 1) | Hibernate disables JDBC insert batching for IDENTITY generators |
| `spring.jpa.open-in-view` left at its default (`true`) | `open-in-view: false` | Lazy loading during view rendering holds a connection per request; Boot logs a warning for this |
| `ddl-auto: update` | Flyway migrations + `ddl-auto: validate` | Reviewable, versioned, reversible schema changes |
| HTTP clients without explicit timeouts | Connect + read timeouts, bounded retries with jitter | The JDK `HttpClient` has no request timeout unless you set one |
| `catch (Exception e)` → 500 | Typed exceptions → RFC 9457 `ProblemDetail` | Clients can act on error types; nothing leaks |
| Kafka `send()` inside a DB `@Transactional` | Transactional outbox + relay | A dual write is not atomic; the broker and the DB diverge |
| Lombok `@Data` on JPA entities | Explicit `equals`/`hashCode` (or identity-only) | Generated methods touch lazy associations and mutable state |
| `findAll()` | Keyset pagination, bounded page size | Unbounded memory and lock footprint |
| POST without idempotency | `Idempotency-Key` + a unique index | Retries create duplicates |
| "Use virtual threads" with `synchronized` around blocking I/O | Target the JDK explicitly | On JDK 21, virtual threads pin in `synchronized` blocks; JEP 491 (JDK 24) removes most of that pinning |

The full method (spec-first prompting, anti-goals, verification contracts, and evals that measure the difference on your own codebase) is [Folder 02, file 01](../02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns/01-spec-driven-prompting-invariants-anti-goals-and-verification-contracts.md).

### 1.11 Sycophancy: why the model agrees with you, and the shape of the fix [research, doc]

Sharma et al. (Anthropic, 2023) found sycophancy across RLHF-trained assistants. Their account of why: human preference data, and the preference models trained on it, sometimes favour convincingly written agreement over correct disagreement. When you present *your* design and ask "is this good?", you put a strong cue in the prompt about which answer will be preferred.

Structural fixes, each of which removes or counter-weights the cue:

1. **Don't reveal your preference.** Present alternatives neutrally (A/B, not "my design vs. the alternative").
2. **Demand failure modes before verdicts.** For example: "Assume this design fails in production at 50,000 QPS. Identify the three most likely failure modes, each with its mechanism and the metric that would show it, before stating anything it does well."
3. **Separate generation from critique.** Run the critique in a different call or subagent with a fresh context. Anthropic's long-running-agent guidance notes that "separate fresh-context verifier sub-agents tend to outperform self-critique" [doc].
4. **Ask what evidence would change the conclusion,** and for a confidence level.
5. **Forbid praise inside the critique contract.** Strengths go in a separate, later section.

The full Devil's Advocate protocol, with templates and an eval for it, is in [Folder 02, file 03](../02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns/03-context-compaction-strategies-preventing-hallucination-and-sycophancy-traps.md). §2.4 below gives the compact version.

---

## 2. Practice: copy-paste templates

### 2.1 The verification contract for a concurrency-sensitive Java change

```xml
<goal>
Implement transfer(fromAccountId, toAccountId, amount) in LedgerService (Java 21, Spring Boot 3.5,
PostgreSQL 17, JDBC via Spring's JdbcClient). It must be correct under concurrent transfers in both directions.
</goal>

<context>
Transfers A->B and B->A run concurrently at peak (~3,000/s). We had a deadlock storm last quarter from
inconsistent lock order, and a pool-exhaustion incident from a transaction held open across a fraud-check HTTP call.
</context>

<invariants>
- Lock both account rows with SELECT ... FOR UPDATE in ascending account_id order, regardless of direction.
- NEVER hold a JDBC connection or open transaction while calling FraudClient (HTTP) or publishing to Kafka.
- Balance never goes negative; amount > 0; from != to.
- Exactly one ledger_entry pair per transfer_id (unique index), so retries are idempotent.
</invariants>

<edge_cases>
from == to; amount = 0; amount > balance; 200 concurrent A->B and B->A transfers;
FraudClient times out after 2 s; the same transfer_id submitted twice concurrently.
</edge_cases>

<anti_goals>
No application-level locks (synchronized, ReentrantLock, Redis locks). No SERIALIZABLE isolation as a substitute for
lock ordering. No read-then-insert idempotency check.
</anti_goals>

<verification>
Before writing the final code, check in your reasoning that:
(1) every code path acquires row locks in ascending id order;
(2) no transaction boundary encloses FraudClient or KafkaTemplate calls;
(3) each edge case above maps to a named test.
If any check fails, change the design before writing code.
</verification>

<output_contract>
Changed files as unified diffs; then a table "invariant -> enforcing code line / test name"; then the test list.
At most three sentences of prose. No restatement of these instructions.
</output_contract>
```

This states *what must be true* and *how to check it*, and leaves the order of thought to the model. Note what the `<verification>` block says: "check in your reasoning", which asks for thinking. It never says "show your checks", which would push reasoning into the response.

### 2.2 Rewriting a 2024-style scripted prompt

**Before.** Fails L4 on TP01 and TP02 (an ERROR on Opus 5.5), and on TP04, TP05 and TP09:

```text
Think step by step.
Step 1: Think about the entities an order service needs.
Step 2: Consider the REST API.
Step 3: Analyze the concurrency issues.
Show your full reasoning in <thinking> tags before the code, then write the service.
```

**After.** Clean on Opus 5.5:
- The goal says what, the invariants say what must hold, and the edge cases say what to test.
- The verification block gives the stopping rule.
- The output contract asks for diffs plus "a short explanation of the design choice", which is allowed.
- The model's reasoning is read from `display: "summarized"` blocks if anyone needs it.

### 2.3 Request shapes per route (JSON bodies)

**Long agentic coding turn on Opus 5.5.** Streamed, explicit effort, room for thinking:

```json
{
  "model": "claude-opus-5-5",
  "max_tokens": 128000,
  "stream": true,
  "thinking": {"type": "adaptive", "display": "summarized"},
  "output_config": {"effort": "medium"},
  "system": [{"type": "text", "text": "<role>...</role><invariants>...</invariants>", "cache_control": {"type": "ephemeral"}}],
  "cache_control": {"type": "ephemeral"},
  "messages": [{"role": "user", "content": "..."}]
}
```

**Lower effort for routine follow-up turns without breaking the cache.** Beta header `mid-conversation-output-config-2026-07-01`; append this message, never edit the top-level `output_config`:

```json
{"role": "system", "content": [], "output_config": {"effort": "low"}}
```

**High-volume extraction on Haiku 5.5.** Thinking is on by default, so keep effort low and get JSON back with structured outputs (no prefill: prefill is a 400 on every current model):

```json
{
  "model": "claude-haiku-5-5",
  "max_tokens": 2048,
  "output_config": {"effort": "low", "format": {"type": "json_schema", "schema": {"type": "object", "properties": {"service": {"type": "string"}, "severity": {"type": "string", "enum": ["S1","S2","S3","S4"]}}, "required": ["service","severity"], "additionalProperties": false}}},
  "messages": [{"role": "user", "content": "<external_content id=\"...\">...</external_content id=\"...\">\nClassify per <severity_rubric>."}]
}
```

**A route that must stay thinking-off on Sonnet 5.5.** `between_tools` is the lowest setting. It is accepted only at effort `high` or below, with no other fields alongside it. Prefer `low` effort with thinking on, and measure [doc]:

```json
{"model": "claude-sonnet-5-5", "max_tokens": 8000, "thinking": {"type": "between_tools"}, "output_config": {"effort": "medium"}, "messages": [...]}
```

### 2.4 The compact Devil's Advocate prompt

```xml
<design_under_review>
{{DESIGN_DOC}}
</design_under_review>

<review_contract>
Assume this design is deployed and fails in production at 50,000 requests/s and a p99 budget of 150 ms.
1. Name the three most likely failure modes. For each give: the mechanism, the first metric that would show it,
   and the load or condition at which it appears.
2. For each, the cheapest design change that removes it, and what that change costs.
3. Only after 1 and 2: what in the design is sound, in at most three bullets.
State your confidence in each failure mode (low/medium/high) and what evidence would lower it.
Do not soften findings; do not praise before section 3.
</review_contract>
```

Run it in a **fresh** call or subagent, without the conversation in which you argued for the design. The numbered list here is a process constraint on the *output order* (findings before verdict), not a reasoning script.

### 2.5 Claude Code: thinking controls you will actually use [doc: code.claude.com]

| Control | Effect |
|---|---|
| `/effort [low\|medium\|high\|xhigh\|max\|auto]` | Sets session effort; no argument opens a slider. `max` is session-only; `auto` sends no level. |
| `--effort <level>` | Sets effort for one launch. |
| `effortLevel` (settings) / `CLAUDE_CODE_EFFORT_LEVEL` (env) | Persistent default. The env var wins over everything. ⚠ verify `max` support per key: the docs disagree. |
| `ultrathink` in a prompt (v2.1.311+) | Deeper reasoning for that turn only, without changing session effort; typed in the terminal, it can raise the turn to `xhigh`. |
| "think", "think hard", "think more" | **No longer keywords**: passed through as ordinary prompt text. |
| Alt+T (Windows/Linux), Option+T (macOS) | Toggles thinking for the session where the model allows it. `/config` persists the choice as `alwaysThinkingEnabled`. |
| Ctrl+O | Toggles verbose mode, showing reasoning as grey italic text. Interactive API sessions show redacted blocks unless `showThinkingSummaries: true`. |
| `MAX_THINKING_TOKENS` | Ignored (non-zero) on adaptive-reasoning models; `=0` cannot disable thinking on Opus 5.5, Sonnet 5.5, Haiku 5.5 or Fable. |

---

## 3. Verified listings

### L4 · `ThinkingPromptAuditor.java`: lint prompts for patterns that fight a reasoning model

**What it shows.** Nine rules (TP01–TP09), with per-model rows covering reasoning-extraction risk, over-verification, prose-steering weakness, and the chat "think carefully" line. Results across the sample prompts:

- The vague one-liner trips the missing-invariants, missing-verification and missing-edge-cases rules.
- The 2024-style scripted prompt trips five rules; TP02 is an ERROR on Opus 5.5 but a WARN on Opus 4.8.
- The invariant-first contract is clean on Opus 5.5. On Opus 5 it gets one INFO telling you to *remove* the verification block.

**What it does not show.** Whether your rewrite actually scores better. That takes an eval on your own tasks (Folder 02).

Run: `java ThinkingPromptAuditor.java`.

```java
// ThinkingPromptAuditor.java - audits a prompt for patterns that fight a reasoning model:
// scripted "Step 1: think about X" chains, requests to reproduce reasoning in the response
// (declined as reasoning_extraction on several 5.x models), thinking-steering by prose instead of
// effort, legacy Claude Code keywords, and missing invariants / edge cases / verification criteria.
// Rules mirror Anthropic's prompting docs as of 2026-10-30; per-model rows are data, update them.
//
// Java 21, no dependencies.  Run:  java ThinkingPromptAuditor.java   (prints ALL ASSERTIONS PASSED)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class ThinkingPromptAuditor {

    enum Surface { API, CLAUDE_CODE }
    enum TaskKind { CODE_GEN, ANALYSIS, CHAT }
    enum Severity { ERROR, WARN, INFO }

    /**
     * reasoningExtraction: prompts that push the model to write its reasoning into the response may be
     * declined (stop_reason "refusal", category reasoning_extraction). overVerifies: the docs say to
     * REMOVE verification instructions (Claude Opus 5). proseSteeringWeak: asking in prose to think
     * less does not reliably reduce thinking (Sonnet 5.5, Haiku 5.5) - lower effort instead.
     */
    record ModelProfile(String id, boolean reasoningExtraction, boolean overVerifies,
                        boolean proseSteeringWeak, boolean chatThinkLineHurtsLatency) {}

    static final Map<String, ModelProfile> MODELS = Map.of(
            "claude-opus-5-5", new ModelProfile("claude-opus-5-5", true, false, false, true),
            "claude-fable-5-1", new ModelProfile("claude-fable-5-1", true, false, false, false),
            "claude-opus-5", new ModelProfile("claude-opus-5", true, true, false, false),
            "claude-sonnet-5-5", new ModelProfile("claude-sonnet-5-5", true, false, true, false),
            "claude-haiku-5-5", new ModelProfile("claude-haiku-5-5", false, false, true, false),
            "claude-opus-4-8", new ModelProfile("claude-opus-4-8", false, false, false, false));

    record PromptUnderAudit(String label, String model, Surface surface, TaskKind kind, String text) {}

    record Finding(String rule, Severity severity, String message) {}

    static final int F = Pattern.CASE_INSENSITIVE | Pattern.MULTILINE;
    static final Pattern STEP_REASONING = Pattern.compile(
            "^\\s*(step\\s*\\d+|\\d+[.)])\\s*[:.\\-]?\\s*(first,?\\s*)?(think|consider|analy[sz]e|reason|brainstorm|reflect|"
            + "evaluate|weigh|ponder|figure out|work out)\\b", F);
    static final Pattern CHAIN_PHRASE = Pattern.compile(
            "think step[- ]by[- ]step|let'?s think|first,? think about|then think about|reason step by step", F);
    static final Pattern EXTRACTION = Pattern.compile(
            "(show|write( out)?|output|print|include|reproduce|explain)\\s+(all\\s+)?(of\\s+)?(your|the)\\s+(full\\s+|complete\\s+|entire\\s+)?"
            + "(reasoning|thinking|chain[- ]of[- ]thought|thought process)(?!\\s+(block|blocks))"
            + "|in\\s+<(thinking|scratchpad|reasoning)>\\s*tags", F);
    static final Pattern THINK_CAREFULLY = Pattern.compile("think (carefully|deeply|hard) before (answering|responding|you answer)", F);
    static final Pattern LESS_THINKING = Pattern.compile(
            "don'?t (over)?think|do not (over)?think|think less|without thinking|no need to think|skip (the )?thinking", F);
    static final Pattern LEGACY_KEYWORD = Pattern.compile("\\b(think harder|think hard|megathink|think more)\\b", F);
    static final Pattern TOKEN_PROSE = Pattern.compile("(use|spend)\\s+(up to\\s+)?\\d+\\s*[kK]?\\s+(thinking\\s+)?tokens", F);
    static final Pattern HARD_RULE = Pattern.compile("\\b(MUST|NEVER|ALWAYS|MUST NOT)\\b");
    static final Pattern INVARIANT_TAG = Pattern.compile("<(invariants|constraints|hard_constraints)>", F);
    static final Pattern EDGE_TAG = Pattern.compile("<edge_cases>|edge cases?:|boundary (cases|conditions)", F);
    static final Pattern VERIFY = Pattern.compile(
            "<verification>|before (you finish|outputting|returning|answering|you answer)[^.\\n]{0,40}(verify|check|confirm)", F);

    static int count(Pattern p, String s) {
        Matcher m = p.matcher(s);
        int n = 0;
        while (m.find()) n++;
        return n;
    }

    static List<Finding> audit(PromptUnderAudit p) {
        ModelProfile mp = MODELS.get(p.model());
        if (mp == null) throw new IllegalArgumentException("unknown model " + p.model());
        String t = p.text();
        List<Finding> out = new ArrayList<>();

        if (count(STEP_REASONING, t) >= 2 || CHAIN_PHRASE.matcher(t).find())
            out.add(new Finding("TP01", Severity.WARN, "scripted reasoning chain - state the goal, invariants, edge cases and "
                    + "verification criteria and let thinking search; keep numbered steps only for required ACTIONS"));
        if (EXTRACTION.matcher(t).find())
            out.add(new Finding("TP02", mp.reasoningExtraction() ? Severity.ERROR : Severity.WARN,
                    (mp.reasoningExtraction() ? p.model() + " may decline this (reasoning_extraction). " : "")
                    + "Read reasoning from thinking blocks (display: \"summarized\"); ask only for a short explanation of the answer"));
        if (mp.chatThinkLineHurtsLatency() && p.kind() == TaskKind.CHAT && THINK_CAREFULLY.matcher(t).find())
            out.add(new Finding("TP03", Severity.INFO, "chat system prompt tells the model to think carefully - on "
                    + p.model() + " removing it made replies start sooner with no clear quality loss; effort is the control"));
        if (LESS_THINKING.matcher(t).find())
            out.add(new Finding("TP06", Severity.WARN, "steering thinking down in prose - lower effort first"
                    + (mp.proseSteeringWeak() ? "; on " + p.model() + " prose does not reliably reduce thinking" : "")));
        if (p.surface() == Surface.CLAUDE_CODE && LEGACY_KEYWORD.matcher(t).find())
            out.add(new Finding("TP07", Severity.INFO, "Claude Code passes 'think hard'/'think more' through as plain text; "
                    + "only 'ultrathink' (v2.1.311+) raises one turn; use /effort for the session"));
        if (TOKEN_PROSE.matcher(t).find())
            out.add(new Finding("TP08", Severity.INFO, "token budgets in prose do nothing - effort steers thinking, max_tokens caps output"));

        if (p.kind() != TaskKind.CHAT) {
            if (!INVARIANT_TAG.matcher(t).find() && count(HARD_RULE, t) < 2)
                out.add(new Finding("TP04", Severity.WARN, "no hard invariants - the model will fill gaps with its training prior"));
            boolean verifies = VERIFY.matcher(t).find();
            if (mp.overVerifies() && verifies)
                out.add(new Finding("TP05", Severity.INFO, p.model() + " verifies its own work unprompted; the docs say remove "
                        + "carried-over verification instructions (they cause over-verification)"));
            else if (!mp.overVerifies() && !verifies)
                out.add(new Finding("TP05", Severity.WARN, "no verification criteria - say what must be checked before finishing"));
            if (p.kind() == TaskKind.CODE_GEN && !EDGE_TAG.matcher(t).find())
                out.add(new Finding("TP09", Severity.WARN, "no edge cases named - list the boundary conditions the code must survive"));
        }
        return out;
    }

    static Set<String> rules(List<Finding> fs) {
        Set<String> r = new TreeSet<>();
        fs.forEach(f -> r.add(f.rule()));
        return r;
    }

    static void expect(PromptUnderAudit p, String... expected) {
        List<Finding> fs = audit(p);
        System.out.println("--- " + p.label() + " [" + p.model() + ", " + p.surface() + ", " + p.kind() + "]: " + rules(fs));
        fs.forEach(f -> System.out.printf("  %-5s %s %s%n", f.severity(), f.rule(), f.message()));
        Set<String> want = new TreeSet<>(List.of(expected));
        if (!rules(fs).equals(want)) throw new AssertionError(p.label() + ": expected " + want + " got " + rules(fs));
    }

    static final String VAGUE = "Build a Spring Boot Order Service.";

    static final String SCRIPTED = """
            Think step by step.
            Step 1: Think about the entities an order service needs.
            Step 2: Consider the REST API.
            Step 3: Analyze the concurrency issues.
            Show your full reasoning in <thinking> tags before the code, then write the service.
            """;

    static final String INVARIANT_FIRST = """
            <goal>Implement POST /orders in the existing order-service (Java 21, Spring Boot 3.5, PostgreSQL 17).</goal>
            <invariants>
            - NEVER hold a JDBC connection while calling Kafka or any HTTP client.
            - MUST be idempotent on the Idempotency-Key header (unique index, not a read-then-write check).
            - Constructor injection only; DTOs are records; errors are RFC 9457 ProblemDetail.
            </invariants>
            <edge_cases>duplicate key under 50 concurrent retries; broker down for 30 s; total = 0; 10,000 line items</edge_cases>
            <verification>
            Before outputting code, verify that no transaction spans an outbound call and that every
            edge case above maps to a named test. If one does not, fix the design first.
            </verification>
            <output_contract>Changed files as unified diffs, then the test list. No prose beyond three sentences.</output_contract>
            """;

    static final String CHAT_SYSTEM = """
            You are the support assistant for the payments API. Think carefully before answering.
            Don't overthink simple questions.
            """;

    static final String CLAUDE_CODE_ASK = "think hard about the race in OutboxRelay and fix it; use up to 32k thinking tokens";

    public static void main(String[] args) {
        expect(new PromptUnderAudit("vague one-liner", "claude-opus-5-5", Surface.API, TaskKind.CODE_GEN, VAGUE),
                "TP04", "TP05", "TP09");
        expect(new PromptUnderAudit("scripted chain + extraction", "claude-opus-5-5", Surface.API, TaskKind.CODE_GEN, SCRIPTED),
                "TP01", "TP02", "TP04", "TP05", "TP09");
        expect(new PromptUnderAudit("same scripted prompt on Opus 4.8", "claude-opus-4-8", Surface.API, TaskKind.CODE_GEN, SCRIPTED),
                "TP01", "TP02", "TP04", "TP05", "TP09");
        expect(new PromptUnderAudit("invariant-first spec", "claude-opus-5-5", Surface.API, TaskKind.CODE_GEN, INVARIANT_FIRST));
        expect(new PromptUnderAudit("invariant-first spec on Opus 5", "claude-opus-5", Surface.API, TaskKind.CODE_GEN, INVARIANT_FIRST),
                "TP05");
        expect(new PromptUnderAudit("chat system prompt", "claude-opus-5-5", Surface.API, TaskKind.CHAT, CHAT_SYSTEM),
                "TP03", "TP06");
        expect(new PromptUnderAudit("chat system prompt on Sonnet 5.5", "claude-sonnet-5-5", Surface.API, TaskKind.CHAT, CHAT_SYSTEM),
                "TP06");
        expect(new PromptUnderAudit("Claude Code ask", "claude-opus-5-5", Surface.CLAUDE_CODE, TaskKind.CODE_GEN, CLAUDE_CODE_ASK),
                "TP04", "TP05", "TP07", "TP08", "TP09");
        Severity onOpus55 = audit(new PromptUnderAudit("x", "claude-opus-5-5", Surface.API, TaskKind.CODE_GEN, SCRIPTED)).stream()
                .filter(f -> f.rule().equals("TP02")).findFirst().orElseThrow().severity();
        Severity onOpus48 = audit(new PromptUnderAudit("x", "claude-opus-4-8", Surface.API, TaskKind.CODE_GEN, SCRIPTED)).stream()
                .filter(f -> f.rule().equals("TP02")).findFirst().orElseThrow().severity();
        if (onOpus55 != Severity.ERROR || onOpus48 != Severity.WARN) throw new AssertionError("TP02 severity by model");
        System.out.println("ALL ASSERTIONS PASSED");
    }
}
```

**Output (verified):**

```text
--- vague one-liner [claude-opus-5-5, API, CODE_GEN]: [TP04, TP05, TP09]
  WARN  TP04 no hard invariants - the model will fill gaps with its training prior
  WARN  TP05 no verification criteria - say what must be checked before finishing
  WARN  TP09 no edge cases named - list the boundary conditions the code must survive
--- scripted chain + extraction [claude-opus-5-5, API, CODE_GEN]: [TP01, TP02, TP04, TP05, TP09]
  WARN  TP01 scripted reasoning chain - state the goal, invariants, edge cases and verification criteria and let thinking search; keep numbered steps only for required ACTIONS
  ERROR TP02 claude-opus-5-5 may decline this (reasoning_extraction). Read reasoning from thinking blocks (display: "summarized"); ask only for a short explanation of the answer
  WARN  TP04 no hard invariants - the model will fill gaps with its training prior
  WARN  TP05 no verification criteria - say what must be checked before finishing
  WARN  TP09 no edge cases named - list the boundary conditions the code must survive
--- same scripted prompt on Opus 4.8 [claude-opus-4-8, API, CODE_GEN]: [TP01, TP02, TP04, TP05, TP09]
  WARN  TP01 scripted reasoning chain - state the goal, invariants, edge cases and verification criteria and let thinking search; keep numbered steps only for required ACTIONS
  WARN  TP02 Read reasoning from thinking blocks (display: "summarized"); ask only for a short explanation of the answer
  WARN  TP04 no hard invariants - the model will fill gaps with its training prior
  WARN  TP05 no verification criteria - say what must be checked before finishing
  WARN  TP09 no edge cases named - list the boundary conditions the code must survive
--- invariant-first spec [claude-opus-5-5, API, CODE_GEN]: []
--- invariant-first spec on Opus 5 [claude-opus-5, API, CODE_GEN]: [TP05]
  INFO  TP05 claude-opus-5 verifies its own work unprompted; the docs say remove carried-over verification instructions (they cause over-verification)
--- chat system prompt [claude-opus-5-5, API, CHAT]: [TP03, TP06]
  INFO  TP03 chat system prompt tells the model to think carefully - on claude-opus-5-5 removing it made replies start sooner with no clear quality loss; effort is the control
  WARN  TP06 steering thinking down in prose - lower effort first
--- chat system prompt on Sonnet 5.5 [claude-sonnet-5-5, API, CHAT]: [TP06]
  WARN  TP06 steering thinking down in prose - lower effort first; on claude-sonnet-5-5 prose does not reliably reduce thinking
--- Claude Code ask [claude-opus-5-5, CLAUDE_CODE, CODE_GEN]: [TP04, TP05, TP07, TP08, TP09]
  INFO  TP07 Claude Code passes 'think hard'/'think more' through as plain text; only 'ultrathink' (v2.1.311+) raises one turn; use /effort for the session
  INFO  TP08 token budgets in prose do nothing - effort steers thinking, max_tokens caps output
  WARN  TP04 no hard invariants - the model will fill gaps with its training prior
  WARN  TP05 no verification criteria - say what must be checked before finishing
  WARN  TP09 no edge cases named - list the boundary conditions the code must survive
ALL ASSERTIONS PASSED
```

### L5 · `request_shape_linter.py`: catch the 400s before production does

**What it shows.** Sixteen checks: fourteen requests that are each wrong in a documented way, one correct Opus 5.5 agent turn that must come back clean, and one pair of consecutive turns that differ only in effort. Each produces exactly its expected codes. Between them they cover:

- removed `budget_tokens`
- disabled thinking where it is always on
- malformed `between_tools`
- sampling parameters on API 2026-10-21
- forced `tool_choice`
- assistant prefill
- unsupported effort levels
- non-streaming large caps
- tiny caps with thinking on
- pre-warm combinations that are rejected
- five breakpoints
- a 1h entry after a 5m one
- misplaced mid-conversation system messages
- `inference_geo` on an old model
- the Haiku 5.5 100K price tier
- cache invalidation from an effort change between turns

**What it does not show.** New models. The table is data, so in production derive it from `GET /v1/models` capabilities at startup.

Run: `python request_shape_linter.py`.

```python
"""request_shape_linter.py - catch Messages API request shapes that 400 (or silently cost more) on the
current Claude models BEFORE they reach production: removed thinking budgets, disabled thinking where
it is always on, sampling parameters under API version 2026-10-21, forced tool_choice, assistant
prefill, cache-breakpoint limits and TTL ordering, max_tokens traps, and cache-invalidating
effort/thinking changes between turns.

The per-model table is DATA transcribed from Anthropic's docs (2026-10-30). When a model ships,
update MODELS - or better, read capabilities from GET /v1/models at startup.
Run: python request_shape_linter.py   (stdlib only; prints ALL ASSERTIONS PASSED)
"""
import json

FULL = ("low", "medium", "high", "xhigh", "max")
# omit_on: omitting `thinking` runs adaptive; thinking_off: how thinking can be turned off;
# sampling: "removed" -> any value 400s
MODELS = {
    "claude-fable-5-1": dict(omit_on=True, effort=FULL, default="high", thinking_off=None, budget="removed",
                             sampling="removed", forced_tool=False, prefill=False, max_out=128_000, geo=True),
    "claude-opus-5-5": dict(omit_on=True, effort=FULL, default="medium", thinking_off=None, budget="removed",
                            sampling="removed", forced_tool=False, prefill=False, max_out=128_000, geo=True),
    "claude-opus-5": dict(omit_on=True, effort=FULL, default="high", thinking_off="disabled<=high", budget="removed",
                          sampling="removed", forced_tool=True, prefill=False, max_out=128_000, geo=True),
    "claude-opus-4-8": dict(omit_on=False, effort=FULL, default="high", thinking_off="disabled", budget="removed",
                            sampling="removed", forced_tool=True, prefill=False, max_out=128_000, geo=True),
    "claude-sonnet-5-5": dict(omit_on=True, effort=FULL, default="high", thinking_off="between_tools<=high", budget="removed",
                              sampling="non-default", forced_tool=False, prefill=False, max_out=128_000, geo=True),
    "claude-haiku-5-5": dict(omit_on=True, effort=FULL, default="medium", thinking_off="disabled<=high", budget="removed",
                             sampling="non-default", forced_tool=True, prefill=False, max_out=128_000, geo=True),
    "claude-sonnet-4-6": dict(omit_on=False, effort=("low", "medium", "high", "max"), default="high", thinking_off="disabled",
                              budget="deprecated", sampling="allowed", forced_tool=True, prefill=False,
                              max_out=128_000, geo=True),
    "claude-haiku-4-5": dict(omit_on=False, effort=(), default=None, thinking_off="disabled", budget="required",
                             sampling="allowed", forced_tool=True, prefill=True, max_out=64_000, geo=False),
}
MID_CONV_SYSTEM = {"claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8",
                   "claude-sonnet-5-5", "claude-haiku-5-5"}
LEVEL = {e: i for i, e in enumerate(FULL)}


def cache_markers(req):
    """Yield the TTL of every cache_control marker in render order: tools -> system -> messages."""
    blocks = list(req.get("tools", []))
    sysv = req.get("system", [])
    blocks += sysv if isinstance(sysv, list) else []
    for m in req.get("messages", []):
        c = m.get("content")
        blocks += c if isinstance(c, list) else []
    for b in blocks:
        if isinstance(b, dict) and "cache_control" in b:
            yield b["cache_control"].get("ttl", "5m")
    if "cache_control" in req:                       # top-level automatic caching = last slot
        yield req["cache_control"].get("ttl", "5m")


def est_prompt_tokens(req):
    return len(json.dumps({k: req.get(k) for k in ("tools", "system", "messages")})) // 4


def lint(req, version="2026-10-21", prev=None):
    out = []

    def add(code, sev, msg):
        out.append((code, sev, msg))

    model = req["model"]
    m = MODELS[model]
    th = req.get("thinking") or {}
    ttype = th.get("type")
    effort = (req.get("output_config") or {}).get("effort")
    eff_resolved = effort or m["default"]
    max_tokens = req.get("max_tokens")
    stream = bool(req.get("stream"))
    msgs = req.get("messages", [])

    if ttype == "enabled" or "budget_tokens" in th:
        if m["budget"] == "removed":
            add("RQ01", "ERROR", f"budget_tokens is removed on {model} (400) - use adaptive thinking + output_config.effort")
        elif m["budget"] == "deprecated":
            add("RQ20", "WARN", f"budget_tokens is deprecated on {model} - transitional only; move to effort")
    if ttype == "adaptive" and m["budget"] == "required":
        add("RQ01", "ERROR", f"{model} has no adaptive thinking - it still takes thinking.budget_tokens")
    if ttype == "disabled":
        off = m["thinking_off"]
        if off is None or off.startswith("between_tools"):
            add("RQ02", "ERROR", f"thinking cannot be disabled on {model} (400) - lower effort instead"
                + ("; the lowest setting is {type: between_tools}" if off else ""))
        elif off == "disabled<=high" and LEVEL.get(eff_resolved, 0) > LEVEL["high"]:
            add("RQ02", "ERROR", f"disabled thinking on {model} is accepted only at effort high or below")
    if ttype == "between_tools":
        if not (m["thinking_off"] or "").startswith("between_tools"):
            add("RQ03", "ERROR", f"between_tools is a Claude Sonnet 5.5 setting; {model} rejects it")
        elif set(th) - {"type"} or LEVEL.get(eff_resolved, 0) > LEVEL["high"]:
            add("RQ03", "ERROR", "between_tools takes no other field and only effort high or below")

    if effort is not None and effort not in m["effort"]:
        add("RQ04", "ERROR", f"effort '{effort}' not supported on {model} (accepts {m['effort'] or 'none'})")
    if effort is None and m["default"] == "medium":
        add("RQ05", "WARN", f"effort omitted: {model} defaults to medium - set it explicitly per route")

    sampling = [k for k in ("temperature", "top_p", "top_k") if k in req]
    if sampling:
        if version >= "2026-10-21" or m["sampling"] == "removed":
            add("RQ06", "ERROR", f"{sampling} rejected ({'API ' + version if version >= '2026-10-21' else model})")
        elif m["sampling"] == "non-default":
            add("RQ06", "WARN", f"{sampling}: non-default values 400 on {model}")

    tc = (req.get("tool_choice") or {}).get("type")
    if tc in ("any", "tool") and not m["forced_tool"]:
        add("RQ07", "ERROR", f"forced tool_choice '{tc}' 400s on {model} - use auto + strict tools + a prompt instruction")

    if msgs and msgs[-1].get("role") == "assistant" and not m["prefill"]:
        add("RQ08", "ERROR", f"assistant prefill 400s on {model} - use output_config.format or instructions")

    if max_tokens is None or max_tokens < 0 or max_tokens > m["max_out"]:
        add("RQ09", "ERROR", f"max_tokens={max_tokens} outside [0, {m['max_out']}] for {model}")
    elif max_tokens == 0:
        bad = [n for n, cond in [("stream", stream), ("thinking.enabled", ttype == "enabled"),
                                 ("output_config.format", "format" in (req.get("output_config") or {})),
                                 ("forced tool_choice", tc in ("any", "tool"))] if cond]
        if bad:
            add("RQ12", "ERROR", f"max_tokens: 0 (cache pre-warm) cannot combine with {bad}")
    else:
        if not stream and max_tokens > 16_000:
            add("RQ10", "WARN", f"max_tokens={max_tokens} without streaming risks SDK HTTP timeouts - stream it")
        thinking_on = (ttype == "enabled" or (ttype == "adaptive" and m["budget"] != "required")
                       or (ttype is None and m["omit_on"]))
        if thinking_on and LEVEL.get(eff_resolved, LEVEL["high"]) >= LEVEL["medium"] and max_tokens < 8_000:
            add("RQ11", "WARN", f"max_tokens={max_tokens} with thinking on - thinking counts toward max_tokens; "
                                "expect stop_reason max_tokens on hard requests")

    ttls = list(cache_markers(req))
    if len(ttls) > 4:
        add("RQ13", "ERROR", f"{len(ttls)} cache breakpoints (max 4, top-level automatic caching uses one)")
    if "1h" in ttls and "5m" in ttls and ttls.index("5m") < len(ttls) - 1 - ttls[::-1].index("1h"):
        add("RQ14", "ERROR", "a 1h cache entry appears after a 5m entry - longer TTLs must come first")

    for i, msg in enumerate(msgs):
        if msg.get("role") == "system":
            if model not in MID_CONV_SYSTEM:
                add("RQ15", "ERROR", f"role 'system' inside messages is not supported on {model}")
            elif i == 0 or msgs[i - 1].get("role") != "user":
                add("RQ15", "ERROR", "a mid-conversation system message must follow a user message (and cannot be messages[0])")

    if "inference_geo" in req and not m["geo"]:
        add("RQ16", "ERROR", f"inference_geo is not supported on {model}")
    if "output_format" in req:
        add("RQ17", "WARN", "output_format is deprecated - use output_config.format")
    if prev is not None:
        pe = (prev.get("output_config") or {}).get("effort") or MODELS[prev["model"]]["default"]
        if prev.get("model") != model:
            add("RQ18", "INFO", "model switch - caches are model-scoped; the whole prefix is re-written")
        elif pe != eff_resolved or (prev.get("thinking") or {}) != th:
            add("RQ18", "INFO", f"top-level effort/thinking changed ({pe} -> {eff_resolved}): the messages cache is invalidated; "
                                "use a per-message effort change (beta) on models that support it")
    if model == "claude-haiku-5-5" and est_prompt_tokens(req) > 100_000:
        add("RQ19", "INFO", "Haiku 5.5 prompt over 100K tokens: the WHOLE request bills at $0.50/$2.50 instead of $0.10/$0.50")
    return out


def U(text):
    return {"role": "user", "content": text}


CASES = [
    ("legacy budget on Opus 5.5", dict(model="claude-opus-5-5", max_tokens=16000,
        thinking={"type": "enabled", "budget_tokens": 10000}, messages=[U("hi")]), {"RQ01", "RQ05"}),
    ("disabled thinking on Opus 5.5", dict(model="claude-opus-5-5", max_tokens=2000, thinking={"type": "disabled"},
        output_config={"effort": "low"}, messages=[U("hi")]), {"RQ02"}),
    ("disabled at xhigh on Opus 5", dict(model="claude-opus-5", max_tokens=16000, thinking={"type": "disabled"},
        output_config={"effort": "xhigh"}, messages=[U("hi")]), {"RQ02"}),
    ("between_tools with display", dict(model="claude-sonnet-5-5", max_tokens=16000,
        thinking={"type": "between_tools", "display": "summarized"}, messages=[U("hi")]), {"RQ03"}),
    ("temperature on 2026-10-21", dict(model="claude-sonnet-4-6", max_tokens=1024, temperature=0.2,
        output_config={"effort": "low"}, thinking={"type": "disabled"}, messages=[U("classify")]), {"RQ06"}),
    ("forced tool + prefill", dict(model="claude-opus-5-5", max_tokens=16000, output_config={"effort": "medium"},
        tool_choice={"type": "tool", "name": "emit"}, messages=[U("go"), {"role": "assistant", "content": "{"}]),
        {"RQ07", "RQ08"}),
    ("xhigh on Sonnet 4.6", dict(model="claude-sonnet-4-6", max_tokens=8000, output_config={"effort": "xhigh"},
        thinking={"type": "adaptive"}, messages=[U("hi")]), {"RQ04"}),
    ("big non-streaming + small thinking room", dict(model="claude-opus-5-5", max_tokens=64000,
        output_config={"effort": "high"}, messages=[U("refactor")]), {"RQ10"}),
    ("tiny max_tokens, thinking always on", dict(model="claude-opus-5-5", max_tokens=1024,
        output_config={"effort": "medium"}, messages=[U("design")]), {"RQ11"}),
    ("pre-warm with stream", dict(model="claude-opus-5-5", max_tokens=0, stream=True, output_config={"effort": "medium"},
        system=[{"type": "text", "text": "S", "cache_control": {"type": "ephemeral"}}], messages=[U("warmup")]), {"RQ12"}),
    ("five markers, 1h after 5m", dict(model="claude-opus-5-5", max_tokens=8000, stream=True,
        output_config={"effort": "medium"}, cache_control={"type": "ephemeral"},
        system=[{"type": "text", "text": "a", "cache_control": {"type": "ephemeral"}},
                {"type": "text", "text": "b", "cache_control": {"type": "ephemeral", "ttl": "1h"}},
                {"type": "text", "text": "c", "cache_control": {"type": "ephemeral"}},
                {"type": "text", "text": "d", "cache_control": {"type": "ephemeral"}}], messages=[U("q")]),
        {"RQ13", "RQ14"}),
    ("system message as messages[0]", dict(model="claude-opus-5-5", max_tokens=8000, output_config={"effort": "medium"},
        messages=[{"role": "system", "content": "terse"}, U("q")]), {"RQ15"}),
    ("Haiku 4.5 adaptive + geo + output_format", dict(model="claude-haiku-4-5", max_tokens=4000,
        thinking={"type": "adaptive"}, inference_geo="us", output_format={"type": "json_schema"},
        messages=[U("x")]), {"RQ01", "RQ16", "RQ17"}),
    ("Haiku 5.5 over 100K tokens", dict(model="claude-haiku-5-5", max_tokens=4000, output_config={"effort": "low"},
        messages=[U("x" * 420_000)]), {"RQ19"}),
    ("clean Opus 5.5 agent turn", dict(model="claude-opus-5-5", max_tokens=64000, stream=True,
        output_config={"effort": "high"}, thinking={"type": "adaptive", "display": "summarized"},
        system=[{"type": "text", "text": "frozen", "cache_control": {"type": "ephemeral", "ttl": "1h"}}],
        cache_control={"type": "ephemeral", "ttl": "1h"}, messages=[U("ship it")]), set()),
]

all_ok = True
for name, req, want in CASES:
    got = lint(req)
    codes = {c for c, _, _ in got}
    status = "ok " if codes == want else "BAD"
    all_ok &= codes == want
    print(f"[{status}] {name}: {sorted(codes) or '-'}")
    for c, sev, msg in got:
        print(f"        {sev:<5} {c} {msg}")

turn1 = dict(model="claude-opus-5-5", max_tokens=64000, stream=True, output_config={"effort": "high"}, messages=[U("a")])
turn2 = dict(turn1, output_config={"effort": "low"})
drift = lint(turn2, prev=turn1)
print(f"[{'ok ' if {c for c, _, _ in drift} == {'RQ18'} else 'BAD'}] effort change between turns: {[c for c, _, _ in drift]}")
print(f"        {drift[0][1]} {drift[0][0]} {drift[0][2]}")
all_ok &= {c for c, _, _ in drift} == {"RQ18"}
assert all_ok
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
[ok ] legacy budget on Opus 5.5: ['RQ01', 'RQ05']
        ERROR RQ01 budget_tokens is removed on claude-opus-5-5 (400) - use adaptive thinking + output_config.effort
        WARN  RQ05 effort omitted: claude-opus-5-5 defaults to medium - set it explicitly per route
[ok ] disabled thinking on Opus 5.5: ['RQ02']
        ERROR RQ02 thinking cannot be disabled on claude-opus-5-5 (400) - lower effort instead
[ok ] disabled at xhigh on Opus 5: ['RQ02']
        ERROR RQ02 disabled thinking on claude-opus-5 is accepted only at effort high or below
[ok ] between_tools with display: ['RQ03']
        ERROR RQ03 between_tools takes no other field and only effort high or below
[ok ] temperature on 2026-10-21: ['RQ06']
        ERROR RQ06 ['temperature'] rejected (API 2026-10-21)
[ok ] forced tool + prefill: ['RQ07', 'RQ08']
        ERROR RQ07 forced tool_choice 'tool' 400s on claude-opus-5-5 - use auto + strict tools + a prompt instruction
        ERROR RQ08 assistant prefill 400s on claude-opus-5-5 - use output_config.format or instructions
[ok ] xhigh on Sonnet 4.6: ['RQ04']
        ERROR RQ04 effort 'xhigh' not supported on claude-sonnet-4-6 (accepts ('low', 'medium', 'high', 'max'))
[ok ] big non-streaming + small thinking room: ['RQ10']
        WARN  RQ10 max_tokens=64000 without streaming risks SDK HTTP timeouts - stream it
[ok ] tiny max_tokens, thinking always on: ['RQ11']
        WARN  RQ11 max_tokens=1024 with thinking on - thinking counts toward max_tokens; expect stop_reason max_tokens on hard requests
[ok ] pre-warm with stream: ['RQ12']
        ERROR RQ12 max_tokens: 0 (cache pre-warm) cannot combine with ['stream']
[ok ] five markers, 1h after 5m: ['RQ13', 'RQ14']
        ERROR RQ13 5 cache breakpoints (max 4, top-level automatic caching uses one)
        ERROR RQ14 a 1h cache entry appears after a 5m entry - longer TTLs must come first
[ok ] system message as messages[0]: ['RQ15']
        ERROR RQ15 a mid-conversation system message must follow a user message (and cannot be messages[0])
[ok ] Haiku 4.5 adaptive + geo + output_format: ['RQ01', 'RQ16', 'RQ17']
        ERROR RQ01 claude-haiku-4-5 has no adaptive thinking - it still takes thinking.budget_tokens
        ERROR RQ16 inference_geo is not supported on claude-haiku-4-5
        WARN  RQ17 output_format is deprecated - use output_config.format
[ok ] Haiku 5.5 over 100K tokens: ['RQ19']
        INFO  RQ19 Haiku 5.5 prompt over 100K tokens: the WHOLE request bills at $0.50/$2.50 instead of $0.10/$0.50
[ok ] clean Opus 5.5 agent turn: -
[ok ] effort change between turns: ['RQ18']
        INFO RQ18 top-level effort/thinking changed (high -> low): the messages cache is invalidated; use a per-message effort change (beta) on models that support it
ALL ASSERTIONS PASSED
```

### L6 · `thinking_economics.py`: billing, truncation, and cost per solved task

**What it shows.**
1. The billing identity: thinking is output at 5× the input price.
2. Truncation probability per effort level and `max_tokens` cap.
3. That "run low, re-run failures at high" reaches high effort's pass rate at **67%** of its cost under a monotone-difficulty assumption. Anthropic's measured version of this was "a little over half the cost".
4. Why keeping prior-turn thinking is cheap on a warm cache.

**What it does not show.** Real distributions. Every token count and pass rate is an ILLUSTRATIVE placeholder. Feed it your own `usage` logs and sweep results.

Run: `python thinking_economics.py` (NumPy).

```python
"""thinking_economics.py - what thinking tokens cost, when max_tokens truncates them, and how an
effort-escalation policy changes cost per SOLVED task.

Prices are Anthropic list prices read from the pricing page on 2026-10-30 (USD per million tokens).
Token distributions and pass rates below are ILLUSTRATIVE placeholders - replace them with your own
measurements: usage.output_tokens, usage.output_tokens_details.thinking_tokens, and your test results
from an effort sweep. The mechanics (billing rules, truncation, escalation algebra) are exact.

Run: python thinking_economics.py   (needs numpy; prints ALL ASSERTIONS PASSED)
"""
import numpy as np

PRICE = {  # input, output, cache_read  ($/MTok)
    "claude-opus-5-5": (4.00, 20.00, 0.20),
    "claude-sonnet-5-5": (2.00, 10.00, 0.10),
    "claude-haiku-5-5": (0.10, 0.50, 0.01),     # prompts <= 100K tokens
    "claude-fable-5-1": (10.00, 50.00, 0.25),
}
rng = np.random.default_rng(42)

print("=== 1. Billing: thinking is output, billed in full whatever `display` shows ===")
thinking, visible = 6_000, 800
for model, (pin, pout, _) in PRICE.items():
    cost = (thinking + visible) * pout / 1e6
    print(f"{model:<18} thinking {thinking:,} + answer {visible} = ${cost:.4f}/request; "
          f"the thinking alone costs as much as {thinking * pout / pin:,.0f} input tokens")
print("display='omitted' or 'summarized' changes what you SEE, not output_tokens (read "
      "usage.output_tokens_details.thinking_tokens for the split)")

print("\n=== 2. max_tokens truncation: thinking + answer must fit under ONE cap ===")
# ILLUSTRATIVE lognormal medians of thinking tokens per effort level on a hard-coding route.
THINK_MEDIAN = {"low": 300, "medium": 1_500, "high": 4_000, "xhigh": 9_000, "max": 16_000}
ANSWER_MEDIAN = 900
N = 200_000
answer = rng.lognormal(np.log(ANSWER_MEDIAN), 0.6, N)
caps = [4_096, 16_000, 64_000, 128_000]
print(f"{'effort':<7} | " + " | ".join(f"P(trunc) @ {c:>7,}" for c in caps))
trunc = {}
for effort, med in THINK_MEDIAN.items():
    total = rng.lognormal(np.log(med), 1.0, N) + answer
    trunc[effort] = [float(np.mean(total > c)) for c in caps]
    print(f"{effort:<7} | " + " | ".join(f"{100 * p:17.2f}%" for p in trunc[effort]))
assert trunc["high"][0] > 0.25 and trunc["high"][2] < 0.01, "4K cap sized for thinking-off truncates high effort"
print("=> a cap sized for thinking-off answers silently truncates reasoning-heavy turns; size it for "
      "thinking + answer (64K is the docs' starting point for long agentic coding turns) and stream")

print("\n=== 3. Cost per SOLVED task: fixed effort vs. 'run low, re-run failures high' ===")
# ILLUSTRATIVE sweep on a 200-task coding eval with a test-suite checker (Opus 5.5 prices).
pin, pout, pread = PRICE["claude-opus-5-5"]
SWEEP = {  # effort: (pass_rate, input_tokens_uncached, cached_read_tokens, output_tokens) per attempt
    "low": (0.62, 6_000, 60_000, 4_000),
    "medium": (0.71, 6_000, 70_000, 9_000),
    "high": (0.75, 6_000, 85_000, 18_000),
    "xhigh": (0.76, 6_000, 95_000, 30_000),
}


def attempt_cost(e):
    _, tin, tread, tout = SWEEP[e]
    return (tin * pin + tread * pread + tout * pout) / 1e6


print(f"{'policy':<22} | {'pass rate':>9} | {'$/attempt-set':>13} | {'$/solved':>8}")
results = {}
for e, (p, *_ ) in SWEEP.items():
    c = attempt_cost(e)
    results[e] = (p, c, c / p)
    print(f"{'fixed ' + e:<22} | {p:9.2f} | {c:13.4f} | {c / p:8.4f}")
for lo, hi in [("low", "high"), ("medium", "xhigh")]:
    # Monotone assumption: the higher level solves every task the lower level solves, so re-running the
    # lower level's failures at the higher level reaches the higher level's pass rate exactly.
    p_lo, p_hi = SWEEP[lo][0], SWEEP[hi][0]
    c = attempt_cost(lo) + (1 - p_lo) * attempt_cost(hi)
    results[f"{lo}->{hi}"] = (p_hi, c, c / p_hi)
    print(f"{lo + ' -> re-run ' + hi:<22} | {p_hi:9.2f} | {c:13.4f} | {c / p_hi:8.4f}")
esc, fixed = results["low->high"], results["high"]
print(f"=> escalation keeps high's pass rate ({esc[0]:.2f}) at {100 * esc[1] / fixed[1]:.0f}% of its cost")
assert esc[0] == fixed[0] and esc[1] < fixed[1]
print("   (the docs report the same shape on Anthropic's coding runs: the higher setting's pass rate for a "
      "little over half the cost - but only with a usable failure signal)")

print("\n=== 4. Prior-turn thinking kept in context: input tokens, and why caching makes it cheap ===")
turns, think_per_turn, base_ctx = 20, 3_000, 12_000
kept = sum(base_ctx + t * (think_per_turn + 1_000) for t in range(turns))
stripped = sum(base_ctx + t * 1_000 for t in range(turns))
for label, total in [("thinking kept (keep-all models)", kept), ("thinking stripped", stripped)]:
    uncached = total * pin / 1e6
    cached = total * pread / 1e6          # upper bound on the saving: nearly all of it is prefix reads
    print(f"{label:<32}: {total:>9,} input tokens over {turns} turns -> ${uncached:.3f} uncached, ~${cached:.3f} at cache-read price")
assert kept > stripped
print("=> keep thinking blocks unmodified (they carry the reasoning behind tool calls); the cache absorbs the cost")
print("\nALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
=== 1. Billing: thinking is output, billed in full whatever `display` shows ===
claude-opus-5-5    thinking 6,000 + answer 800 = $0.1360/request; the thinking alone costs as much as 30,000 input tokens
claude-sonnet-5-5  thinking 6,000 + answer 800 = $0.0680/request; the thinking alone costs as much as 30,000 input tokens
claude-haiku-5-5   thinking 6,000 + answer 800 = $0.0034/request; the thinking alone costs as much as 30,000 input tokens
claude-fable-5-1   thinking 6,000 + answer 800 = $0.3400/request; the thinking alone costs as much as 30,000 input tokens
display='omitted' or 'summarized' changes what you SEE, not output_tokens (read usage.output_tokens_details.thinking_tokens for the split)

=== 2. max_tokens truncation: thinking + answer must fit under ONE cap ===
effort  | P(trunc) @   4,096 | P(trunc) @  16,000 | P(trunc) @  64,000 | P(trunc) @ 128,000
low     |              2.27% |              0.01% |              0.00% |              0.00%
medium  |             26.00% |              1.08% |              0.01% |              0.00%
high    |             61.70% |              9.43% |              0.30% |              0.03%
xhigh   |             86.05% |             30.82% |              2.59% |              0.41%
max     |             95.07% |             52.89% |              8.62% |              1.94%
=> a cap sized for thinking-off answers silently truncates reasoning-heavy turns; size it for thinking + answer (64K is the docs' starting point for long agentic coding turns) and stream

=== 3. Cost per SOLVED task: fixed effort vs. 'run low, re-run failures high' ===
policy                 | pass rate | $/attempt-set | $/solved
fixed low              |      0.62 |        0.1160 |   0.1871
fixed medium           |      0.71 |        0.2180 |   0.3070
fixed high             |      0.75 |        0.4010 |   0.5347
fixed xhigh            |      0.76 |        0.6430 |   0.8461
low -> re-run high     |      0.75 |        0.2684 |   0.3578
medium -> re-run xhigh |      0.76 |        0.4045 |   0.5322
=> escalation keeps high's pass rate (0.75) at 67% of its cost
   (the docs report the same shape on Anthropic's coding runs: the higher setting's pass rate for a little over half the cost - but only with a usable failure signal)

=== 4. Prior-turn thinking kept in context: input tokens, and why caching makes it cheap ===
thinking kept (keep-all models) : 1,000,000 input tokens over 20 turns -> $4.000 uncached, ~$0.200 at cache-read price
thinking stripped               :   430,000 input tokens over 20 turns -> $1.720 uncached, ~$0.086 at cache-read price
=> keep thinking blocks unmodified (they carry the reasoning behind tool calls); the cache absorbs the cost

ALL ASSERTIONS PASSED
```

### L7 · `AdaptiveThinkingClient.java`: the request shape in the official Java SDK

**What it shows.** The request builder for an Opus 5.5 reasoning call:
- adaptive thinking with `display: summarized` and an explicit `effort`
- a 64K cap and streaming via `MessageAccumulator`
- a frozen, cached system block
- blocks read by type
- refusal and `max_tokens` handled before reading text
- the thinking/answer token split read from `usage.output_tokens_details`

It was compiled with `javac --release 21 -Xlint:all -Werror` against `com.anthropic:anthropic-java-core:3.3.0` and run in dry-run mode, which prints the exact wire JSON the SDK would send.

**What it does not show.** A live response. `--live` spends tokens and needs a key, so it was not run for this KB.

```java
// AdaptiveThinkingClient.java - the request shape a reasoning model wants, in the official Java SDK
// (com.anthropic:anthropic-java 3.3.0): adaptive thinking with an EXPLICIT effort, max_tokens sized for
// thinking + answer, streaming, a frozen cached system prompt, blocks read by TYPE (a turn may or may
// not start with a thinking block), refusal and max_tokens handled before reading text, and the
// thinking/answer token split logged from usage.
//
// Compile-checked in this KB; it calls the API only with --live (that spends money and needs a key):
//   java -cp anthropic-java-3.3.0-all.jar AdaptiveThinkingClient.java --live
import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.ObjectMappers;
import com.anthropic.core.http.StreamResponse;
import com.anthropic.helpers.MessageAccumulator;
import com.anthropic.models.messages.CacheControlEphemeral;
import com.anthropic.models.messages.ContentBlock;
import com.anthropic.models.messages.Message;
import com.anthropic.models.messages.MessageCreateParams;
import com.anthropic.models.messages.OutputConfig;
import com.anthropic.models.messages.RawMessageStreamEvent;
import com.anthropic.models.messages.StopReason;
import com.anthropic.models.messages.TextBlockParam;
import com.anthropic.models.messages.ThinkingConfigAdaptive;
import java.util.List;

public final class AdaptiveThinkingClient {

    // Frozen: no dates, ids or per-user values - it is the cached prefix (Folder 01, file 01).
    static final String SYSTEM = """
            <role>Principal engineer reviewing Java 21 / Spring Boot 3.5 services.</role>
            <invariants>
            - Never hold a JDBC connection across Kafka or HTTP I/O.
            - Multi-row locks are taken in ascending primary-key order.
            </invariants>
            <output_contract>Findings as a numbered list: file:line, defect, failing scenario, fix.</output_contract>
            """;

    static MessageCreateParams request(String model, OutputConfig.Effort effort, String task) {
        return MessageCreateParams.builder()
                .model(model)
                .maxTokens(64_000L)                                    // thinking counts toward this cap
                .thinking(ThinkingConfigAdaptive.builder()
                        .display(ThinkingConfigAdaptive.Display.SUMMARIZED)   // default is OMITTED (empty text)
                        .build())
                .outputConfig(OutputConfig.builder().effort(effort).build())  // Opus 5.5 defaults to MEDIUM
                .systemOfTextBlockParams(List.of(TextBlockParam.builder()
                        .text(SYSTEM)
                        .cacheControl(CacheControlEphemeral.builder().build())
                        .build()))
                .addUserMessage(task)
                .build();
    }

    static Message stream(AnthropicClient client, MessageCreateParams params) {
        MessageAccumulator acc = MessageAccumulator.create();
        try (StreamResponse<RawMessageStreamEvent> events = client.messages().createStreaming(params)) {
            events.stream().forEach(acc::accumulate);
        }
        return acc.message();
    }

    static void print(Message msg) {
        StopReason stop = msg.stopReason().orElse(StopReason.END_TURN);
        if (stop.equals(StopReason.REFUSAL)) {                         // HTTP 200, not an exception
            msg.stopDetails().ifPresent(d -> System.out.println("REFUSAL: " + d));
            return;
        }
        if (stop.equals(StopReason.MAX_TOKENS))
            System.out.println("WARNING: hit max_tokens - raise the cap or lower effort; treat as a failed attempt");
        for (ContentBlock block : msg.content()) {                     // select by type, never by position
            block.thinking().ifPresent(t -> System.out.println("[thinking summary] " + t.thinking()));
            block.text().ifPresent(t -> System.out.println(t.text()));
        }
        long out = msg.usage().outputTokens();
        long thinking = msg.usage().outputTokensDetails().map(d -> d.thinkingTokens()).orElse(0L);
        System.out.printf("output_tokens=%d (thinking %d, answer ~%d) cache_read=%d cache_write=%d%n",
                out, thinking, out - thinking,
                msg.usage().cacheReadInputTokens().orElse(0L), msg.usage().cacheCreationInputTokens().orElse(0L));
    }

    public static void main(String[] args) throws Exception {
        MessageCreateParams params = request("claude-opus-5-5", OutputConfig.Effort.HIGH,
                "Review OutboxRelay.java for lock-ordering and connection-holding defects.");
        if (args.length == 0 || !args[0].equals("--live")) {
            System.out.println("dry run - pass --live to call the API. Wire body the SDK would send:");
            System.out.println(ObjectMappers.jsonMapper().writerWithDefaultPrettyPrinter()
                    .writeValueAsString(params._body()));
            return;
        }
        AnthropicClient client = AnthropicOkHttpClient.fromEnv();
        print(stream(client, params));
    }
}
```

**Output (verified, dry run):**

```text
dry run - pass --live to call the API. Wire body the SDK would send:
{
  "max_tokens" : 64000,
  "messages" : [ {
    "content" : "Review OutboxRelay.java for lock-ordering and connection-holding defects.",
    "role" : "user"
  } ],
  "model" : "claude-opus-5-5",
  "output_config" : {
    "effort" : "high"
  },
  "system" : [ {
    "text" : "<role>Principal engineer reviewing Java 21 / Spring Boot 3.5 services.</role>\n<invariants>\n- Never hold a JDBC connection across Kafka or HTTP I/O.\n- Multi-row locks are taken in ascending primary-key order.\n</invariants>\n<output_contract>Findings as a numbered list: file:line, defect, failing scenario, fix.</output_contract>\n",
    "type" : "text",
    "cache_control" : {
      "type" : "ephemeral"
    }
  } ],
  "thinking" : {
    "type" : "adaptive",
    "display" : "summarized"
  }
}
```

---

## 4. Failure modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | HTTP 400 after a "model string only" upgrade | `budget_tokens` / `thinking.disabled` / `temperature` in the body | 4.x-era request shape on a 5.x model or on API `2026-10-21` | Adaptive thinking + `output_config.effort`; drop sampling parameters | L5 in CI; derive capabilities from `/v1/models` |
| F2 | `stop_reason: "refusal"` on harmless prompts | `stop_details.category: "reasoning_extraction"` | The prompt asks for written-out reasoning or `<thinking>` tags | Delete the instruction; use `display: "summarized"`; ask for a short explanation | L4 TP02 |
| F3 | Answers cut off mid-diff | `stop_reason: "max_tokens"`; high `thinking_tokens` | Cap sized for thinking-off | Raise to 64K–128K and stream, or lower effort | L5 RQ11; dashboards on `max_tokens` stops |
| F4 | Quality dropped after migrating Opus 5 → Opus 5.5 | Effort omitted in requests | Opus 5.5 defaults to `medium` (Opus 5: `high`) | Set effort explicitly, then re-sweep | L5 RQ05 |
| F5 | Cache hit rate drops whenever the "planner" step runs | Top-level `effort` differs between turns | Effort is rendered into the prompt | Per-message effort (beta) or per-message steering phrases | L5 RQ18 |
| F6 | The UI looks frozen during long agent turns | Only `thinking` blocks with empty text between tool calls | Progress updates arrive as thinking blocks; default `display: "omitted"` | `display: "updates"` (beta); render thinking blocks before each tool call | Harness test on block types |
| F7 | 400 on a conversation that worked yesterday | History was edited (reminder deleted, tool list changed, summary rewritten client-side) | Preserved thinking binds blocks to the conversation | Append-only history; turn-scoped `clear_at` reminders; server-side compaction | Payload diff of consecutive requests |
| F8 | Opus 5 burns tokens re-checking finished work | Long tails of verification after the answer is right | Carried-over "verify your work" instructions | Remove them on Opus 5 | L4 TP05 (INFO on `claude-opus-5`) |
| F9 | Chat replies start slowly on Opus 5.5 | Long thinking on trivial turns | "Think carefully before answering" in the system prompt, or re-examination of settled answers | Remove the line; add the "treat earlier answers as done" sentence where appropriate; lower effort | L4 TP03 |
| F10 | Tool call never runs on an Opus 5 route with thinking disabled | A tool call written as *text*; stray `<thinking>` tags | Disabled-thinking failure modes on Opus 5 | Turn thinking on and lower effort, or use the documented mitigation sentence | Prefer effort over disabling |

---

## 5. Staff-level drills

<details><summary><b>D1 · "We changed <code>claude-opus-4-6</code> to <code>claude-opus-5-5</code> and every request 400s. The code sets <code>budget_tokens: 10000</code>."</b></summary>

**Naive answer.** "Set `budget_tokens` lower," or "pin the old model."

**Why it fails.** `budget_tokens` is removed on every 5.x model and returns a 400 at any value. And there is no budget-to-effort formula.

**Staff answer.**
- Replace it with `thinking: {type: "adaptive"}` (or omit `thinking`, since it is always on for Opus 5.5) plus `output_config.effort`.
- Start at `medium`, the Opus 5.5 default, and set it *explicitly*.
- Size `max_tokens` for thinking plus answer (64K–128K, streamed).
- Run an effort sweep on a sample of real requests (`low`/`medium`/`high`), comparing cost per solved task.
- Also check the rest of the request: temperature, forced `tool_choice` and prefill all 400 on Opus 5.5. L5 finds them in one pass.
</details>

<details><summary><b>D2 · "Product wants the model's reasoning shown to users. How?"</b></summary>

**Staff answer.** Set `thinking.display: "summarized"` and render the `thinking` blocks. They are summaries; the raw chain of thought is never returned on current models. Do **not** prompt for reasoning in the response: on 5.x models that can be declined as `reasoning_extraction`, and fallback won't retry it.

For "show your work" in a product sense, ask for a short explanation of the answer or a summary of the actions taken. Both are explicitly allowed [doc]. For long agent turns, `display: "updates"` streams progress notes.
</details>

<details><summary><b>D3 · "We need deterministic output, so set temperature 0."</b></summary>

**Staff answer.** On API version `2026-10-21`, any sampling parameter is a 400 on every model, and on 4.7+/5.x models they are removed regardless.

Determinism comes from the contract and from controls on the output:
- structured outputs for shape
- explicit invariants and edge cases for substance
- tests and validators on the output
- caching, which never changes the computation (file 01, L1-C)

Where you need repeatability for audits, store the full response. A pinned model plus a pinned effort reduces variance but does not eliminate it.
</details>

<details><summary><b>D4 · "Thinking is expensive. Disable it on simple endpoints."</b></summary>

**Staff answer.** On Opus 5.5 and Fable 5.1 you can't. On Sonnet 5.5 the off-switch is `between_tools`, at ≤ `high`. The documented levers, in order:

1. Lower effort: at `low` the model "skips thinking for simple tasks".
2. Route the endpoint to Haiku 5.5 at `low`.
3. Only then consider prose steering ("Answer directly without deliberating."), and measure it, because it is wording-sensitive and unreliable on Sonnet 5.5 and Haiku 5.5.

Price cost per *completed* task. A cheaper request that fails more often isn't cheaper.
</details>

<details><summary><b>D5 · "After moving to Opus 5.5 our architecture reviews got shallower."</b></summary>

**Staff answer.** Check whether effort was omitted. Opus 5.5 defaults to `medium` where Opus 5 defaulted to `high`. Set it explicitly for that route (`high` for one-shot reviews) and compare on your review eval.

Don't simply carry over Opus 5's `high`: at a given level, Opus 5.5 "tends to think more per turn". Measure both quality and tokens, and reserve `xhigh`/`max` for measured gains [doc].
</details>

<details><summary><b>D6 · "Is 'think step by step' harmful now?"</b></summary>

**Staff answer.** On a thinking model it is redundant at best. The model already thinks adaptively, and a scripted chain can steer its search badly (§1.2).

Paired with "write it out", it becomes reasoning extraction, which is declinable on 5.x. Manual chain-of-thought remains a documented *fallback* only for older models with thinking off. Replace it with a verification contract.
</details>

<details><summary><b>D7 · "Our agent plans at high effort and executes at low. Is that a good idea?"</b></summary>

**Staff answer.** The idea is good, but the implementation matters:

- Changing the top-level `effort` between requests invalidates the messages cache. On a 100K-token agent context, that is a full re-write every time you flip.
- Use per-message effort changes (beta) on Fable 5.1, Opus 5.5, Opus 5, Sonnet 5.5 and Haiku 5.5. They hold for every later turn until replaced, and keep the cache.
- Or use per-message steering phrases ("Please think hard before responding." on planning turns, "Answer directly without deliberating." on routine ones), which touch no request parameters.

In Claude Code, `/effort` changes keep the cache on the 5.5 models and Fable 5.1.
</details>

<details><summary><b>D8 · "We strip old thinking blocks from history to save tokens."</b></summary>

**Staff answer.** On Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1, that is a history edit. It invalidates later thinking blocks, can 400 on newer accounts, and restarts the cache from the edit point.

The saving is small anyway: kept blocks are mostly cache reads. L6 shows $0.20 vs $0.09 over 20 turns at Opus 5.5's read price. If context is the constraint, use server-side context editing (`clear_thinking_20251015`) or compaction, which the check does not count as edits.
</details>

<details><summary><b>D9 · "How do I get verification without the model printing its verification?"</b></summary>

**Staff answer.** Put the checks in a `<verification>` block phrased as "check in your reasoning that …; if any check fails, change the design before writing code". Then make the *result* of verification part of the output contract: for example, an invariant → test table.

That is a deliverable, not a reasoning transcript. On Opus 5, drop the block entirely; it over-verifies on its own.
</details>

<details><summary><b>D10 · "Our design review agent says every design is good."</b></summary>

**Staff answer.** That is sycophancy: the prompt carries your preference, and preference-trained models lean toward agreement (Sharma et al.). Fixes:

- Run review in a fresh context, without your advocacy.
- Require failure modes with mechanisms and metrics *before* any verdict (§2.4).
- Ask for confidence levels and for the evidence that would change them.
- Measure it: seed known-bad designs into the eval and track the detection rate.

Folder 02 file 03 builds the full protocol.
</details>

---

## 6. Invariants checklist

- [ ] No `budget_tokens`, `thinking.disabled` (on Opus 5.5 / Fable 5.1 / Sonnet 5.5) or sampling parameters in any 5.x request.
- [ ] Every route sets `output_config.effort` explicitly; effort was chosen by a sweep, not copied from the previous model.
- [ ] `max_tokens` covers thinking plus answer (64K–128K for agentic work), and large caps are streamed.
- [ ] Prompts state goal, invariants, edge cases, verification and output contract. Numbered steps describe actions only.
- [ ] No prompt asks for reasoning in the response; reasoning, if needed, is read from `display: "summarized"`.
- [ ] Thinking config and top-level effort are fixed per conversation; mid-conversation changes use per-message effort.
- [ ] History is append-only: thinking blocks are passed back unchanged, and reminders are appended (turn-scoped), never deleted.
- [ ] `stop_reason` is checked (`refusal`, `max_tokens`) before content is read; blocks are read by type.
- [ ] Opus 5 routes carry no "verify your work" boilerplate; Opus 5.5 chat prompts carry no "think carefully" line.
- [ ] L4 and L5 run in CI on prompt and request-builder changes.

---

## 7. References

Anthropic documentation (read 2026-10-30):
- Prompting best practices, "Thinking and reasoning": <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Steering thinking (effort levels, steering, caching, cost control, pricing): <https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost>
- Thinking overview: <https://platform.claude.com/docs/en/build-with-claude/thinking>
- Effort: <https://platform.claude.com/docs/en/build-with-claude/effort>
- Prompting Claude Opus 5.5 (effort calibration, thinking-disabled prompts, unattended runs, safeguards, progress updates): <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>
- Refusals and fallback, "Keep reasoning in thinking blocks": <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>
- Preserved thinking: <https://platform.claude.com/docs/en/build-with-claude/preserved-thinking>
- Migration guide: <https://platform.claude.com/docs/en/about-claude/models/migration-guide>
- Claude Code model configuration (aliases, effort, thinking): <https://code.claude.com/docs/en/model-config>
- Claude Code commands: <https://code.claude.com/docs/en/commands>

Research:
- Wei et al., "Chain-of-Thought Prompting Elicits Reasoning in Large Language Models" (2022): <https://arxiv.org/abs/2201.11903>
- Feng et al., "Towards Revealing the Mystery behind Chain of Thought: A Theoretical Perspective" (2023): <https://arxiv.org/abs/2305.15408>
- Merrill & Sabharwal, "The Expressive Power of Transformers with Chain of Thought" (2023): <https://arxiv.org/abs/2310.07923>
- Snell et al., "Scaling LLM Test-Time Compute Optimally can be More Effective than Scaling Model Parameters" (2024): <https://arxiv.org/abs/2408.03314>
- DeepSeek-AI, "DeepSeek-R1: Incentivizing Reasoning Capability in LLMs via Reinforcement Learning" (2025): <https://arxiv.org/abs/2501.12948>
- Sharma et al., "Towards Understanding Sycophancy in Language Models" (Anthropic, 2023): <https://arxiv.org/abs/2310.13548>
- JEP 491, "Synchronize Virtual Threads without Pinning" (JDK 24): <https://openjdk.org/jeps/491>

Previous: [01 · Attention and XML grammar](01-transformer-attention-lost-in-the-middle-and-xml-tag-grammar.md) · Next: [03 · Model routing and token economics](03-model-routing-limits-token-economics-opus-vs-sonnet-vs-haiku-and-advisor-mode.md) · [KB README](../README.md)
