# Claude Power-User & Agentic Engineering: L7 Reference

A modular Markdown knowledge base for Staff/Principal backend engineers who want to use Claude well:
- on the web and desktop (Projects)
- through the API
- in Claude Code (CLI/IDE)

It is grounded in two things:
- **Context-window physics:** causal attention, KV/prefix caching, XML boundary grammar, and the allocation of adaptive-thinking tokens.
- **Practical agentic engineering:** CLAUDE.md, skills, subagents, deterministic hooks, MCP servers, and end-to-end Java 21 / Spring Boot project scaffolding.

Every factual claim is labelled with its source. Every code listing was run, or compiled and dry-run, for this KB, and its output is pasted verbatim.

## Status

| Folder | Topic | Status |
|---|---|---|
| [01-First-Principles-of-Claude-Attention-and-Prompt-Physics](01-First-Principles-of-Claude-Attention-and-Prompt-Physics/) | Attention, prefix caching, XML grammar · thinking physics · routing & token economics | **DONE 2026-10-30**: 3 files, 10 listings, gate passed |
| 02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns | Spec-driven prompting · few-shot & self-critique · compaction, hallucination & sycophancy | pending |
| 03-Claude-Code-CLI-and-IDE-Master-Command-Reference | Commands, flags, shortcuts · explore→plan→execute→verify, worktrees · CLAUDE.md & memory | pending |
| 04-Skills-Subagents-and-Multi-Agent-Orchestration | Skills & slash commands · isolated subagents · batch/background/headless CI | pending |
| 05-Deterministic-Hooks-Guardrails-and-Auto-Verification | Hook architecture & exit code 2 · production hook scripts for Java | pending |
| 06-MCP-Model-Context-Protocol-Setup-and-Custom-Servers | Client config & schema bloat · essential servers · custom servers (Spring AI, FastMCP) | pending |
| 07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch | Scaffolding · Kafka outbox/saga · Beam/Dataflow & SQL · Testcontainers/ArchUnit/legacy | pending |
| 08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint | Production `.claude/` for Java monorepos · pro tips & degradation troubleshooting | pending |

Folders are written one at a time, each in its own turn.

## Folder 01 files

| File | What you get |
|---|---|
| [01 · Transformer attention, lost-in-the-middle, XML tag grammar](01-First-Principles-of-Claude-Attention-and-Prompt-Physics/01-transformer-attention-lost-in-the-middle-and-xml-tag-grammar.md) | Why prefix caching is exact (causal mask); the edit blast radius; why caching saves what it saves; softmax dilution; RoPE decay; what is known about lost-in-the-middle; Markdown vs XML boundary recovery measured; tag grammar G1–G10; the canonical layout; a CI linter |
| [02 · Extended thinking physics](01-First-Principles-of-Claude-Attention-and-Prompt-Physics/02-extended-thinking-physics-when-to-use-and-how-to-prompt-reasoning-models.md) | Thinking as serial test-time compute; why scripted chains hurt; the verification contract; effort per model; billing and `max_tokens` truncation; caching and preserved thinking; reasoning-extraction refusals; why vague prompts give tutorial-grade Java; sycophancy |
| [03 · Model routing, limits, token economics, advisor mode](01-First-Principles-of-Claude-Attention-and-Prompt-Physics/03-model-routing-limits-token-economics-opus-vs-sonnet-vs-haiku-and-advisor-mode.md) | The live price table; limits that bite; the model lineup; effort before model; measured caching economics (break-even, TTL, fan-out, batch, MCP tax, Haiku 100K cliff); the cost of model switches; advisor (API and Claude Code); Claude Code model controls |

## Conventions

| Label | Meaning |
|---|---|
| **[doc]** | Anthropic documentation or pricing page, read on the date stated in the file |
| **[measured]** | Output of a listing in this KB, pasted under **Output (verified)** |
| **[research]** | A published paper, usually on open-weight models |
| **[inference]** | Reasoned from mechanism; not verified on Claude (whose architecture is unpublished) |
| ⚠ verify | Release-dependent; re-check before relying on it |

- Illustrative workload numbers (token distributions, pass rates, gap distributions) are marked **ILLUSTRATIVE** in the code. Prices are not illustrative: they are the live list prices from 2026-10-30.
- Each file follows the same spine: §0 orientation and twelve rules → §1 first principles → §2 copy-paste practice → §3 verified listings → §4 failure modes → §5 staff-level drills → §6 invariants checklist → §7 references.

## Listing index (Folder 01)

| # | Listing | Lang | What it verifies | How it was verified |
|---|---|---|---|---|
| L1 | `causal_prefix_kv_lab.py` | Python + NumPy | Prefix K/V bit-identical; one-token edit → layer 0: 1 position, layers 1–2: 44/64; cached reuse = full pass (≤ 3.1e-15); 99.2% of prefill FLOPs avoided; softmax dilution margins; RoPE decay | Run; asserts pass |
| L2 | `boundary_ambiguity_lab.py` | Python stdlib | Markdown 45.0% exact recovery (benign) vs XML 100%; hostile: plain XML 77.3% / 22.6% spoofed, nonce-XML with skeleton-first parsing 100% / 0% | Run; asserts pass |
| L3 | `PromptStructureLinter.java` | Java 21 | 12 assembly rules (PS01–PS12); BAD/MARKDOWN/OVER-MARKED trip exactly their rules, GOOD is clean | `javac --release 21 -Xlint:all -Werror`; run |
| L4 | `ThinkingPromptAuditor.java` | Java 21 | 9 thinking-prompt rules (TP01–TP09) with per-model rows | `-Werror`; run |
| L5 | `request_shape_linter.py` | Python stdlib | 16 checks of documented 400s and cache traps (removed `budget_tokens`, disabled thinking, sampling on `2026-10-21`, forced `tool_choice`, prefill, breakpoints/TTL order, Haiku 100K tier …) | Run; asserts pass |
| L6 | `thinking_economics.py` | Python + NumPy | Thinking billing; `max_tokens` truncation by effort; escalation 67% of high's cost at equal pass rate; kept-thinking cost on a warm cache | Run; asserts pass |
| L7 | `AdaptiveThinkingClient.java` | Java 21 + anthropic-java 3.3.0 | The Opus 5.5 reasoning request shape; the exact wire JSON | `-Werror` against the SDK; dry-run (no API call) |
| L8 | `claude_token_economics.py` | Python + NumPy | Break-even 2/3 requests; "90%" = 92.3% input / 89.2% total; Haiku 5.5 cliff 5.0×; agent loop 6.8×; TTL by session shape; fan-out 3.6×; MCP tax $120/$6/$0.49 per 1K; model switch 7× | Run; asserts pass |
| L9 | `ModelRoutingPolicy.java` | Java 21 | Routes, effort-first escalation ladder, advisor pairs (2 accepted / 3 rejected), switch break-even 14 turns, Claude Code aliases | `-Werror`; run |
| L10 | `CacheProbe.java` | Java 21 + anthropic-java 3.3.0 | Cached prefix across 5 JVMs: `Map.copyOf` → 4 distinct (varies), sorted → 1, timestamped → 5; `--live` paid probe | `-Werror` against the SDK; free mode run |

## Re-running the listings

```bash
# Python listings (NumPy needed for L1, L6, L8)
python causal_prefix_kv_lab.py
# Java listings without dependencies (JDK 21+)
java PromptStructureLinter.java
# SDK listings: put anthropic-java 3.3.0 (+ client-okhttp, kotlin-stdlib, jackson) on the classpath
java -cp "<sdk-jars>" CacheProbe.java          # free multi-JVM prefix check
java -cp "<sdk-jars>" CacheProbe.java --live   # PAID: needs ANTHROPIC_API_KEY
```

How this KB was verified: Python 3.14.5 with NumPy 2.5.4; Temurin JDK 25.0.4 compiling with `--release 21`; `com.anthropic:anthropic-java-core:3.3.0` plus SHA-1-verified Jackson 2.19.4 and Kotlin 1.9.0 jars from Maven Central. A gate script extracts every listing from the Markdown, checks it byte-for-byte against its source, re-runs it, and diffs the output.

## Where this KB refines the brief

1. **Folder names.** The brief's role section names the folders `01-First-Principles-of-Claude-Prompting/` … `08-Java21-Spring-Boot-Zero-to-Production-Prompts/`, while its repository blueprint uses the more specific names. This KB follows the **blueprint**. The files are written directly to disk, so the requested `### FILE:` extraction headers aren't needed.
2. **"Caching cuts latency 80% and cost 90%."**
   - *Cost:* the cached portion is 90% cheaper on 0.1× models, 95% on Opus 5.5 / Sonnet 5.5, and 97.5% on Fable 5.1. The whole bill always saves less, because output isn't discounted: L8 measured 89.2% total vs 92.3% input on Opus 5.5.
   - *Latency:* the current docs give no percentage. The 2024 launch post claims "up to 85%", and its own table shows −79% TTFT at 100K tokens but only −31% at 10K. The latency gain scales with the cached share.
3. **"Extended thinking budget."** `budget_tokens` now returns 400 on every current 5.x model. On Opus 5.5 and Fable 5.1, thinking can't be disabled, and effort is the control. Opus 5.5 defaults to `medium`.
4. **"Don't write step-by-step when thinking is on."** Confirmed by Anthropic's docs, with a distinction the brief misses: numbered steps for required *actions* are still correct; only reasoning scripts hurt. Two newer twists: asking for written-out reasoning can now be *declined* (`reasoning_extraction`), and on Opus 5 even verification instructions should be removed.
5. **"XML outperforms Markdown because of how Claude is trained."** Anthropic recommends XML and says it helps Claude "parse complex prompts unambiguously". Its training details are unpublished. This KB argues the case from delimiter grammar and measures it (L2), rather than asserting training facts.
6. **"Vague prompts produce 2019 Baeldung code."** Framed as a mechanism (the prior fills every unstated decision), not as a measured fact about current Claude. Current models often choose better defaults. Folder 02 builds an eval that measures this on your own codebase.
7. **Claude Code commands.** `/advisor`, `/effort` (low…max, plus `auto` and `ultracode`), `/btw`, `opusplan` and `ultrathink` were verified on code.claude.com on 2026-10-30. The rest of the brief's command list is verified in Folder 03. "think hard" is no longer a keyword. The docs disagree on whether `effortLevel` accepts `max` ⚠ verify.
8. **Price-table drift.** The Claude API skill bundled with Claude Code 2.1.312 (cached 2026-10-06) lists Sonnet 5.5 cache reads at $0.20. The live pricing page lists $0.10 (0.05×). This KB uses the live page.
9. **The MCP "30,000+ token tax".** Reproduced as a parameterised model (10 servers × 20 tools × ~150 tokens) and priced in L8. Real schema sizes vary; measure yours. Folder 06 goes deeper.

## Sources

Anthropic documentation at platform.claude.com and code.claude.com, the Anthropic pricing page, the prompt-caching launch post, and the papers cited in each file's §7. All were read on 2026-10-30. Prices and model behaviour change; re-check anything marked ⚠ verify.
