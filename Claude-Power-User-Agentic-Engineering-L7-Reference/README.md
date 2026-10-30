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
| [02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns](02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns/) | Spec-driven prompting · few-shot & self-critique · compaction, hallucination & sycophancy | **DONE 2026-10-30**: 3 files, 7 listings, gate passed |
| [03-Claude-Code-CLI-and-IDE-Master-Command-Reference](03-Claude-Code-CLI-and-IDE-Master-Command-Reference/) | Commands, flags, shortcuts · explore→plan→execute→verify, worktrees · CLAUDE.md & memory | **DONE 2026-10-30**: 3 files, 4 listings, gate passed; every command, flag and env var cross-checked against the docs snapshot |
| [04-Skills-Subagents-and-Multi-Agent-Orchestration](04-Skills-Subagents-and-Multi-Agent-Orchestration/) | Skills & slash commands · isolated subagents · batch/background/headless CI | **DONE 2026-10-30**: 3 files, 6 listings, gate passed |
| [05-Deterministic-Hooks-Guardrails-and-Auto-Verification](05-Deterministic-Hooks-Guardrails-and-Auto-Verification/) | Hook architecture & exit code 2 · production hook scripts for Java | **DONE 2026-10-30**: 2 files, 12 listings (10 hooks + contract lab + 40-case harness), gate passed |
| [06-MCP-Model-Context-Protocol-Setup-and-Custom-Servers](06-MCP-Model-Context-Protocol-Setup-and-Custom-Servers/) | Client config & schema bloat · essential servers · custom servers (Python, Java SDK, Spring AI) | **DONE 2026-10-30**: 3 files, 7 listings (3 servers run under one conformance client), gate passed |
| [07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch](07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch/) | Scaffolding · Kafka outbox/saga · Beam/Dataflow & SQL · Testcontainers/ArchUnit/legacy | **DONE 2026-10-30**: 4 files, 7 linted XML templates + 7 listings (real Beam DirectRunner and ArchUnit runs), gate passed |
| [08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint](08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint/) | Production `.claude/` for Java monorepos · pro tips & degradation troubleshooting | **DONE 2026-10-30**: 2 files, a 35-file installable blueprint, 2 listings, gate passed |

**Complete.** 8 folders, 23 files, 55 code listings plus 7 XML templates. Every listing is extracted from the Markdown, byte-checked against its source and re-run by the gate. A final pass re-ran the gate on all eight folders after the last harness change.

## Where to start

| If you want to… | Read |
|---|---|
| understand why prompts behave as they do | Folder 01, then Folder 02 file 01 |
| set up a team repository today | Folder 08 file 01: copy [`blueprint/`](08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint/blueprint/), then customise per its §1.4 |
| fix "Claude got worse" | Folder 08 file 02, run `session_health.py` on the session |
| scaffold or refactor Java services | Folder 07: T1 → T2 per slice; T3/T4/T7 for Kafka, Beam and SQL; T5/T6 for concurrency and legacy |
| connect databases, GitHub and docs safely | Folder 06 files 01–02 |
| build guardrails | Folder 05, then Folder 04 for subagents and CI |

## All files

| Folder | File | What you get |
|---|---|---|
| 01 | [01 · Transformer attention, lost-in-the-middle, XML tag grammar](01-First-Principles-of-Claude-Attention-and-Prompt-Physics/01-transformer-attention-lost-in-the-middle-and-xml-tag-grammar.md) | Why prefix caching is exact (causal mask); the edit blast radius; softmax dilution; RoPE decay; lost-in-the-middle; Markdown vs XML boundary recovery measured; tag grammar G1–G10; a CI linter |
| 01 | [02 · Extended thinking physics](01-First-Principles-of-Claude-Attention-and-Prompt-Physics/02-extended-thinking-physics-when-to-use-and-how-to-prompt-reasoning-models.md) | Thinking as serial test-time compute; why scripted chains hurt; the verification contract; effort per model; billing and truncation; preserved thinking; reasoning-extraction refusals |
| 01 | [03 · Model routing, limits, token economics, advisor mode](01-First-Principles-of-Claude-Attention-and-Prompt-Physics/03-model-routing-limits-token-economics-opus-vs-sonnet-vs-haiku-and-advisor-mode.md) | Live prices; limits; effort before model; measured caching economics; the cost of model switches; advisor |
| 02 | [01 · Spec-driven prompting](02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns/01-spec-driven-prompting-invariants-anti-goals-and-verification-contracts.md) | Invariants, anti-goals, verification contracts; a spec checker that caught a real `@Transactional` self-invocation bug |
| 02 | [02 · Few-shot, chain of verification, self-critique](02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns/02-few-shot-canonical-examples-chain-of-verification-and-self-critique-loops.md) | Example selection; the self-critique fixed point; gated loops |
| 02 | [03 · Compaction, hallucination, sycophancy](02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns/03-context-compaction-strategies-preventing-hallucination-and-sycophancy-traps.md) | State files vs compaction (measured); grounding guards; the Devil's Advocate protocol |
| 03 | [01 · Commands, flags, shortcuts](03-Claude-Code-CLI-and-IDE-Master-Command-Reference/01-complete-slash-commands-cli-flags-and-keyboard-shortcuts-cheat-sheet.md) | The cheat sheet, checked against the docs; a settings validator |
| 03 | [02 · Explore → plan → execute → verify, worktrees](03-Claude-Code-CLI-and-IDE-Master-Command-Reference/02-the-explore-plan-execute-verify-workflow-and-git-worktree-parallel-agents.md) | The workflow; parallel worktrees and their cleanup |
| 03 | [03 · The under-200-line CLAUDE.md](03-Claude-Code-CLI-and-IDE-Master-Command-Reference/03-crafting-the-perfect-under-200-line-claude-md-and-hierarchical-memory.md) | What belongs in memory; imports and rules; a CLAUDE.md linter |
| 04 | [01 · Skills and slash commands](04-Skills-Subagents-and-Multi-Agent-Orchestration/01-designing-reusable-skills-and-custom-slash-commands-with-frontmatter.md) | Frontmatter that triggers correctly; `/new-slice`; a skill linter |
| 04 | [02 · Isolated subagents](04-Skills-Subagents-and-Multi-Agent-Orchestration/02-building-isolated-subagents-architect-security-auditor-and-test-runner.md) | Architect, security auditor, test runner, reviewer; read-only by construction |
| 04 | [03 · Batch, background, headless CI](04-Skills-Subagents-and-Multi-Agent-Orchestration/03-batch-migrations-background-agents-and-headless-ci-cd-automation.md) | A guarded `claude -p` batch runner; GitHub workflows checked against the schema |
| 05 | [01 · Hooks architecture and exit code 2](05-Deterministic-Hooks-Guardrails-and-Auto-Verification/01-claude-hooks-architecture-pretooluse-posttooluse-stop-and-exit-code-2.md) | The decision contract as executable test vectors |
| 05 | [02 · Ten production hooks](05-Deterministic-Hooks-Guardrails-and-Auto-Verification/02-10-production-hook-scripts-for-java-maven-gradle-git-safety-and-secret-blocking.md) | Guards, formatter, build gate, context, audit; 40 tested cases |
| 06 | [01 · MCP client configuration and schema bloat](06-MCP-Model-Context-Protocol-Setup-and-Custom-Servers/01-mcp-client-configuration-stdio-vs-sse-http-and-preventing-tool-schema-bloat.md) | Transports, scopes, expansion, tool search; a `.mcp.json` linter; the token tax priced |
| 06 | [02 · Essential servers: PostgreSQL, GitHub, Docker, docs](06-MCP-Model-Context-Protocol-Setup-and-Custom-Servers/02-essential-mcp-servers-for-backend-engineers-postgres-github-docker-and-docs.md) | Least-privilege setups; why read-only must be enforced by the engine (measured) |
| 06 | [03 · Custom MCP servers in Java and Python](06-MCP-Model-Context-Protocol-Setup-and-Custom-Servers/03-building-a-custom-mcp-server-in-java-spring-ai-and-python-fastmcp.md) | One server three ways (Python, Java SDK, Spring AI) under a conformance client |
| 07 | [01 · Scaffolding prompts (T1, T2)](07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch/01-zero-to-production-java21-spring-boot-microservice-scaffolding-prompt.md) | Template anatomy; Phase 0 RFC/spec; hexagonal vertical slice; a template linter |
| 07 | [02 · Kafka outbox, saga, Resilience4j (T3)](07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch/02-kafka-outbox-saga-and-resilience4j-implementation-prompt-templates.md) | Outbox + idempotent consumer; why, measured by fault injection |
| 07 | [03 · Beam/Dataflow and SQL tuning (T4, T7)](07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch/03-apache-beam-dataflow-pipeline-and-sql-performance-tuning-prompts.md) | Evidence-first audits; real DirectRunner failures; a plan digester |
| 07 | [04 · Concurrency, Testcontainers, ArchUnit, legacy (T5, T6)](07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch/04-testcontainers-integration-testing-archunit-and-legacy-refactoring-prompts.md) | Race tests that must fail first; the ArchUnit freeze ratchet |
| 08 | [01 · The production `.claude/` blueprint](08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint/01-complete-production-dot-claude-folder-blueprint-for-java-monorepos.md) | 35 installable files assembled from the tested artifacts, validated together |
| 08 | [02 · 25 pro tips and degradation troubleshooting](08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint/02-25-pro-tips-hidden-shortcuts-and-troubleshooting-claude-degradation.md) | Context, cache, steering, recovery, keys, automation; a session-health doctor |

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

## Listing index (Folder 02)

| # | Listing | Lang | What it verifies |
|---|---|---|---|
| L1 | `SpecContract.java` | Java 21 | Spec linter SC01–SC09 (vague spec: 11 findings; full spec: 0); deterministic XML rendering; traceability matrix |
| L2 | `spec_output_checker.py` | Python | 11 Spring Boot contract checks; tutorial fixture 1/11, production first draft 10/11 (caught a `@Transactional` self-invocation bug), fixed 11/11 |
| L3 | `few_shot_selector.py` | Python | Schema validation rejects 2/18 examples; naive top-5 collapses to 4/5 on one label, MMR + abstention gives 5 labels; recency-aware order |
| L4 | `CritiqueLoopDynamics.java` | Java 21 | Self-critique fixed point p* = t·r/(f·b+t·r): strong start 0.80 → 0.7565, weak 0.50 → 0.7176; gated loop monotone to 0.9333 (verifier blind spots cap it); MC within 0.005; factored-CoVe harness |
| L5 | `compaction_budget_sim.py` | Python + NumPy | 400-turn session: unmanaged dies at turn 240; compact@150K $25.87 / 36% facts; compact@967K $51.55; clear@150K 353 passes $537; state files $22.94 / 97% facts |
| L6 | `grounding_guard.py` | Python | Quote, citation and number checks G1–G5 on 7 cases |
| L7 | `sycophancy_eval.py` | Python | Framing-paired seeded-flaw eval; sycophancy delta +1.00 vs 0.00 on stand-ins |

## Listing index (Folder 03)

| # | Listing | Lang | What it verifies |
|---|---|---|---|
| L1 | `settings_validator.py` | Python + jsonschema | Official schemastore schema (142 properties) + 247 settings-reference keys; 10 checks SV01–SV10 (schema, typo keys, deny-shadowed allows, `:*` mid-pattern, MCP rules with parentheses, primary-field parameter rules, `Bash(ls*)`, bypass in shared settings, no secret denies, unanchored hook paths); GOOD Java settings clean |
| L2 | `worktree_cleanup.sh` + `test_worktree_cleanup.sh` | bash + git | Removes only clean, merged, unlocked worktrees under `.claude/worktrees/`; the test builds 5 worktrees and asserts exactly 1 is removed |
| L3 | `claude_md_lint.py` | Python | 10 rules CM01–CM10 from the memory and best-practices docs; the 219-line BAD file trips all 10; the 31-line GOOD Java CLAUDE.md is clean |

## Listing index (Folder 04)

| # | Listing | Lang | What it verifies |
|---|---|---|---|
| L1 | `skill_lint.py` | Python + PyYAML | 11 SKILL.md checks (frontmatter fields, 1,536-char description cap, side effects without `disable-model-invocation`, bare Bash, undeclared `$args`, missing supporting files, fork-only fields, reserved names); `/new-slice` clean, BAD trips 9 |
| L2 | `agent_lint.py` | Python + PyYAML | 10 subagent checks (required fields, reserved `:`, tool names, read-only roles with Edit, the `disallowedTools` whole-tool trap, enums, bypass mode, unguarded Bash); code-reviewer, security-auditor, test-runner and architect are clean |
| L3 | `headless_batch.py` + `fake_claude.py` + `test_headless_batch.py` | Python | Guarded `claude -p` batch (json-schema, max-turns, budget, dontAsk, worktree per unit, one transient retry, timeout); 7 outcomes classified correctly; $1.75 total |
| L4 | `ci_workflow_check.py` | Python + PyYAML + jsonschema | GitHub workflows vs the official schema + 8 policy checks (pwn request, unpinned action, inlined key, skip-permissions, no turn cap, no `if:` guard, no permissions); 2 GOOD workflows clean |

## Listing index (Folder 05)

| # | Listing | Lang | What it verifies |
|---|---|---|---|
| L1 | `hook_contract_lab.py` | Python | The documented exit-code × stdout table (14 vectors), deny > defer > ask > allow plus rules-after-hooks, the 8-continuation Stop cap, matcher semantics |
| L2 | `guard_bash.py`, `protect_paths.py`, `secret_scan.py`, `block_secret_reads.py`, `dependency_guard.py`, `readonly_git.py`, `format_java.py`, `verify_build.py`, `session_context.py`, `audit_log.py` | Python (stdlib) | The ten production hooks (fail closed, Windows-path aware) |
| L3 | `test_hooks.py` | Python | 40 cases in a real temp git project, all passing; caught a real Stop-gate bug (untracked dirs collapsed by `--porcelain`); wiring validated against the schema (5 errors = `onFailure`, which the schema lags) |

## Listing index (Folder 06)

| # | File | Listing | Lang | What it verifies |
|---|---|---|---|---|
| L1 | 01 | `mcp_config_lint.py` | Python | 12 `.mcp.json` rules from the docs + supply-chain practice (url without type, SSE, literal secrets, covered credentials read as empty, `${CLAUDE_PROJECT_DIR}` default, unset/empty vars, unpinned launchers, whitespace, reserved names, non-read-only DB roles, cross-scope conflicts, `alwaysLoad` sprawl); BAD trips all 12, GOOD 0 |
| L2 | 01 | `mcp_token_tax.py` | Python | The token tax priced per session, tool search off vs on: published 5-server fleet $3.02 → $0.25 per Opus 5.5 session; a 55K tool block pushes every Haiku 5.5 request into the 5× tier |
| L1 | 02 | `sql_readonly_gate_lab.py` | Python (sqlite3) | 7 attacks + 3 benign queries against a real DB: SELECT-prefix filter 7/7 damaged, keyword denylist 3/7 + 1 false positive, engine-enforced (ro + one statement + authorizer + step budget + row cap) 0/7 and 0 |
| L1–L3 | 03 | `order_platform_mcp.py`, `OrderPlatformMcpServer.java`, `OrderPlatformSpringMcp.java` | Python `mcp` 2.3.0; MCP Java SDK 2.1.0; Spring AI 2.0.2 on Boot 4.1.2 | The same read-only server (architecture rules, schema from Flyway migrations, surefire build health, a prompt) three ways |
| L4 | 03 | `mcp_stdio_conformance.py` | Python (stdlib) | Raw JSON-RPC client: handshake, 2026-07-28 probe, tool and error semantics, prompt role, stdout purity, exit on EOF; all three servers pass and agree 3/3; two negative controls (Boot defaults: 23 junk stdout lines) |

## Listing index (Folder 07)

Templates (XML, extracted and byte-checked like code): T1 `t1_phase0_rfc_spec.xml`, T2 `t2_vertical_slice_scaffolder.xml`, T3 `t3_kafka_outbox_idempotent.xml`, T4 `t4_beam_pipeline_auditor.xml`, T5 `t5_adversarial_concurrency.xml`, T6 `t6_testcontainers_archunit_legacy.xml`, T7 `t7_sql_explain_tuning.xml`.

| # | File | Listing | Lang | What it verifies |
|---|---|---|---|---|
| L1 | 01 | `prompt_template_check.py` | Python | 12 template rules (skeleton, data-first/task-last, declared and used placeholders, data only in context, output contract, verification commands, every INV checked, anti-goals, no reasoning scripts or shouting, size); all 7 templates clean; the BAD control trips 11 of 12 |
| L1 | 02 | `OutboxIdempotencyLab.java` | Java 21 | Seeded fault injection, 10,000 orders: dual write lost 55 and ghosted 181; outbox + naive consumer double-applied 181; idempotent 0; 1 h dedup vs a 2 h outage double-applied 83, 24 h 0 |
| L1 | 03 | `beam_fusion_coder_audit.py` | Python | 9 static Beam rules (fusion, SerializableCoder, non-deterministic keys, GBK-then-loop, unwindowed unbounded grouping, DoFn client fields, per-element clients, side inputs, sink semantics); BAD 9/9, GOOD 0 |
| L2 | 03 | `BeamCoderLab.java` | Java 21 + Beam 2.77.0 DirectRunner | Real construction-time rejections (non-deterministic key coder, unwindowed unbounded GroupByKey); a non-serializable DoFn fails only at `run()`; TestStream on-time 15 / late 22 / too-late dropped, PAssert passed |
| L3 | 03 | `explain_plan_triage.py` | Python | Digest of `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`: hottest nodes, ≥10× misestimates (LIMIT-aware), spills; synthetic before/after plans |
| L1 | 04 | `RaceHarness.java` | Java 21 | CyclicBarrier × 200 rounds: check-then-act fails 200/200 with the seam and 1–2/200 without; `compute` and CAS loop 0/200 |
| L2 | 04 | `ArchRuleLab.java` | Java 21 + ArchUnit 1.5.1 | Layer and purity rules on in-process compiled bytecode; `FreezingArchRule`: legacy passes with 5 stored, a new violation fails alone, a fix shrinks the store to 3 |

## Listing index (Folder 08)

| # | File | Listing | Lang | What it verifies |
|---|---|---|---|---|
| L1 | 01 | `blueprint_check.py` | Python + PyYAML + jsonschema | Installs the blueprint under real names. Every KB linter, extracted from the published Markdown, passes on it (16 artifacts, 0 findings). 13 cross-references pass, among them: 18 copies byte-identical to their tested listings; hook wiring; `.mcp.json` ↔ `enabledMcpjsonServers` ↔ `mcp__` rules; `.gitignore`; hook inputs. Four planted drifts are each caught |
| L1 | 02 | `session_health.py` | Python | Degradation doctor over session transcripts: context pressure, compactions, cache share and prefix busts, retry loops, edit churn, output floods. Synthetic session shown; two real 18–35 h sessions quoted (peaks 965.7K/965.9K tokens, 4 compactions each, 99%+ cache) |

The blueprint itself (35 files under disarmed names, so it never loads into a session opened on this repository) is in [`08-…/blueprint/`](08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint/blueprint/).

**Docs cross-check.** `tools/doc_tokens_check.py` extracts every backticked `/command`, `claude --flag` and Claude Code environment variable from the KB and confirms each appears in the code.claude.com snapshot (54 pages, 2026-10-30). All eight folders: 82 commands, 46 flags, 23 env vars, 0 unknown.

## Re-running the listings

```bash
# Python listings (NumPy needed for L1, L6, L8)
python causal_prefix_kv_lab.py
# Java listings without dependencies (JDK 21+)
java PromptStructureLinter.java
# SDK listings: put anthropic-java 3.3.0 (+ client-okhttp, kotlin-stdlib, jackson) on the classpath
java -cp "<sdk-jars>" CacheProbe.java          # free multi-JVM prefix check
java -cp "<sdk-jars>" CacheProbe.java --live   # PAID: needs ANTHROPIC_API_KEY
# Folders 03-04, 08: PyYAML + jsonschema, and the schemas the validators read
export CLAUDE_SETTINGS_SCHEMA=claude-code-settings.json GITHUB_WORKFLOW_SCHEMA=github-workflow.json   # from schemastore
# Folder 06: pip install "mcp==2.3.0"; Java classpaths from Maven
mvn dependency:build-classpath -Dmdep.outputFile=cp.txt   # in a pom with io.modelcontextprotocol.sdk:mcp:2.1.0,
                                                          # or spring-ai-starter-mcp-server (Spring AI BOM 2.0.2, Boot 4.1.2)
MCP_JAVA_CP="$(cat cp.txt)" SPRING_MCP_CP="..." python mcp_stdio_conformance.py
# Folder 07: Beam 2.77.0 (core + DirectRunner + junit 4.13.2 + hamcrest) and ArchUnit 1.5.1 on the classpath
javac --release 21 -Xlint:all,-path,-classfile -Werror -cp "$BEAM_CP" BeamCoderLab.java
java --enable-native-access=ALL-UNNAMED --sun-misc-unsafe-memory-access=allow -cp ".;$BEAM_CP" BeamCoderLab
```

How this KB was verified:
- **Runtimes:** Python 3.14.5 with NumPy 2.5.4; Temurin JDK 25.0.4 compiling with `--release 21`.
- **Libraries, by folder:**
  - Folder 01: `com.anthropic:anthropic-java-core:3.3.0`, plus SHA-1-verified Jackson 2.19.4 and Kotlin 1.9.0 jars.
  - Folder 06: MCP Python SDK `mcp` 2.3.0, MCP Java SDK 2.1.0, Spring AI 2.0.2 on Spring Boot 4.1.2.
  - Folder 07: Apache Beam 2.77.0 with the DirectRunner, ArchUnit 1.5.1.
  - All resolved from Maven Central and PyPI on 2026-10-30.
- **The gate:** a script extracts every listing and template from the Markdown, checks it byte-for-byte against its source, re-runs it, diffs the output, and checks links. Separate scripts check every external URL and every Claude Code command, flag and environment variable against the docs snapshot.
- **No paid API calls were made.** SDK listings compile and dry-run.

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
10. **The token tax, revisited (Folder 06).** Claude Code now defers MCP tool definitions by default (tool search). Only names and server instructions load upfront, so the brief's tax applies only when deferral is off: `ENABLE_TOOL_SEARCH=false`, `auto` below its 10% threshold, `alwaysLoad`, old models, or Foundry on Azure. When it does apply, it is *larger* than the brief's figure. Anthropic's published example is 58 tools ≈ 55K tokens, and GitHub alone ≈ 743 tokens per tool, not 150.
11. **"Python FastMCP".** In the official `mcp` 2.x SDK the class is `MCPServer` (`mcp.server.mcpserver`); `mcp.server.fastmcp` doesn't exist in 2.3.0. The separately maintained `fastmcp` package is a different project.
12. **"Custom Java 21 + Spring AI MCP server".** Built and run, plus a plain MCP-Java-SDK twin and a Python twin, under one conformance client. Each found a first-draft contract bug a compiler couldn't:
    - Python: `ValueError` hid the message from the model.
    - Spring AI: a `String` prompt rendered as an assistant message.
    - Spring AI: without `-parameters`, every call failed on `arg0`.

    One piece of folklore was disproved: `from __future__ import annotations` does not break `mcp` 2.3.0 schemas.
13. **"6 battle-tested templates".** Seven, counting the SQL tuning prompt that the title of Folder 07 file 03 implies. "Battle-tested" here means mechanically checked: each template is linted and rendered, and the invariants it demands are measured by a lab that shows what breaks without them. Your codebase is the remaining test; Folder 02's eval method is how to run it.
14. **"JMH + CyclicBarrier race tests".** The CyclicBarrier harness is run here. JMH (1.37) is specified in T5 but not executed, because benchmark numbers from this laptop would mislead. Running the harness also showed that a barrier alone is not enough: without a widening seam the real bug was caught in only 1–2 of 200 rounds.
15. **"`.claude/` blueprint: CLAUDE.md < 150 lines, code-reviewer agent, new-slice skill, PreToolUse exit-2 guards, PostToolUse `spotless:apply`".** All delivered as installable files, plus the rest a production setup needs:
    - path rules and a dependency allowlist;
    - `.mcp.json` and the MCP server;
    - prompt templates and a CI workflow;
    - `.gitignore` lines.

    The CLAUDE.md is 33 lines; the docs' own guidance is under 200. Two gaps surfaced only when the pieces were checked *together*, and both are fixed. The audit hook writes to `.claude/audit/`, which needed a `.gitignore` line. The dependency guard needs `.claude/allowed-deps.txt`; without it, every new dependency asks.
16. **"Troubleshooting Claude degradation".** Treated as measurement, not folklore: `session_health.py` reads the session transcript. Two real long sessions both peaked just under the ~967K auto-compaction point, with 99%+ of input from cache. The risk in long sessions is context pressure and compaction loss, not cost.

## Sources

Anthropic documentation at platform.claude.com and code.claude.com, the Anthropic pricing page, the prompt-caching launch post, and the papers cited in each file's §7. All were read on 2026-10-30. Prices and model behaviour change; re-check anything marked ⚠ verify.
