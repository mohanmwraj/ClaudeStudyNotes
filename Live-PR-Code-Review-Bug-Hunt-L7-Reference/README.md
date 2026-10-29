# Live PR Code Review & Bug-Hunt: L7 Reference

A first-principles training manual and PR simulation bank for the **live pull-request review / bug-hunt** interview round at the Staff and Principal level (FAANG L6–L7). It covers Java 21+ (Spring Boot, Hibernate, Kafka, concurrency) and C/C++20/23 (systems, memory safety, DMA, lock-free concurrency). Every PR simulation is a realistic multi-file `git diff` that compiles and passes its author's tests while hiding 7–10 high-severity defects. Each comes with a timed 3-pass diagnostic guide and a line-by-line L7 answer key.

## Status

| Folder | Files | Status |
|---|---|---|
| [01-The-L7-Code-Review-Mental-Model-and-Rubric](01-The-L7-Code-Review-Mental-Model-and-Rubric/) | 3 | ✅ Done 2026-10-29, gated |
| [02-Java-Spring-Hibernate-and-Microservices-PR-Simulations](02-Java-Spring-Hibernate-and-Microservices-PR-Simulations/) | 3 (PR01–PR03) | ✅ Done 2026-10-30, gated |
| [03-Kafka-Beam-Dataflow-and-Distributed-Streaming-PR-Simulations](03-Kafka-Beam-Dataflow-and-Distributed-Streaming-PR-Simulations/) | 3 (PR04–PR06) | ✅ Done 2026-10-30, gated |
| [04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations](04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/) | 3 (PR07–PR09) | ✅ Done 2026-10-30, gated |
| [05-AI-Engineering-RAG-and-MCP-Server-PR-Simulations](05-AI-Engineering-RAG-and-MCP-Server-PR-Simulations/) | 2 (PR10–PR11) | ✅ Done 2026-10-30, gated |
| [06-Anti-Pattern-Cheat-Sheets-and-Self-Audit-Checklists](06-Anti-Pattern-Cheat-Sheets-and-Self-Audit-Checklists/) | 2 | ✅ Done 2026-10-30, gated |

**In numbers.** 16 modules, about 161k words. Eleven PR simulations hide 83 planted defects (43 Sev-1), each one demonstrated by a probe on the PR's code and shown absent on the fix. The PRs compile with `-Werror` on the JVM and on two C/C++ compilers, and every author test suite passes on the buggy code. There are 100 red flags, with a scanner measured against all 83 defects.

### The PR bank

| PR | Domain | Stack (verified) | Diff | Defects (Sev-1) | Author's tests on the PR | Probe lines |
|---|---|---|---|---|---|---|
| [PR01](02-Java-Spring-Hibernate-and-Microservices-PR-Simulations/01-pr01-fintech-wallet-transfer-transactional-proxy-and-deadlock-traps.md) | Wallet transfers | Spring 7 `@Transactional`, embedded PostgreSQL 18 | 181 lines | 8 (4) | 4/4 | 8 |
| [PR02](02-Java-Spring-Hibernate-and-Microservices-PR-Simulations/02-pr02-high-throughput-order-api-n-plus-1-connection-exhaustion-and-virtual-threads.md) | Order dashboard | Hibernate 7.4, HikariCP, JDK 21 virtual threads | 249 lines | 7 (3) | 4/4 | 8 (incl. decoy) |
| [PR03](02-Java-Spring-Hibernate-and-Microservices-PR-Simulations/03-pr03-multi-tenant-auth-cache-stampede-idor-and-jwt-security-flaws.md) | Multi-tenant docs API | JWT (RFC 7519/8725), permission cache | 232 lines | 8 (4) | 5/5 | 7 (F8 argued) |
| [PR04](03-Kafka-Beam-Dataflow-and-Distributed-Streaming-PR-Simulations/01-pr04-kafka-consumer-offset-commit-race-poison-pill-and-rebalance-storm.md) | Payment events | Kafka client `MockConsumer` | 167 lines | 8 (4) | 3/3 | 7 |
| [PR05](03-Kafka-Beam-Dataflow-and-Distributed-Streaming-PR-Simulations/02-pr05-apache-beam-stateful-dofn-watermark-stall-and-coder-non-determinism.md) | Card-velocity alerts | Apache Beam DirectRunner, `TestStream` | 235 lines | 7 (3) | 3/3 | 8 |
| [PR06](03-Kafka-Beam-Dataflow-and-Distributed-Streaming-PR-Simulations/03-pr06-transactional-outbox-and-redis-distributed-lock-fencing-bugs.md) | Shipment events | Transactional outbox, PostgreSQL 18, lease lock | 225 lines | 7 (3) | 3/3 | 6 |
| [PR07](04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md) | Thumbnail service | C++23 coroutines, GCC 16 + Clang 21 | 202 lines | 7 (3) | 4/4 | 7 |
| [PR08](04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md) | Market-data hand-off | SPSC ring + Treiber stack; AArch64/x86-64 codegen | 226 lines | 8 (6) | 6/6 | 6 + asm |
| [PR09](04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md) | Motor-controller link | C17, host D-cache/DMA/IRQ model; Cortex-M7 codegen | 269 lines | 7 (4) | 7/7 | 7 + asm |
| [PR10](05-AI-Engineering-RAG-and-MCP-Server-PR-Simulations/01-pr10-spring-ai-rag-pipeline-sse-thread-starvation-and-acl-leakage.md) | Enterprise assistant | Spring AI 2.0.2, Reactor 3.8 | 266 lines | 8 (4) | 5/5 | 8 + lemma |
| [PR11](05-AI-Engineering-RAG-and-MCP-Server-PR-Simulations/02-pr11-mcp-tool-server-confused-deputy-and-non-idempotent-agent-retries.md) | Support copilot tools | MCP Java SDK 2.1.0 | 157 lines | 8 (5) | 5/5 | 8 |

### Folders 02–06 at a glance

| File | Words | What's in it |
|---|---|---|
| 02/01 · PR01 wallet transfer | ~9.9k | Self-invoked `REQUIRES_NEW`, checked-exception commit, lock order, HTTP in the transaction, pre-commit events, idempotency last, currency, negative amounts |
| 02/02 · PR02 order API | ~10.2k | N+1, `equals` on generated ids, pooled connections across remote calls, `EntityManager` leak, `synchronized` pinning (JDK 21), `ThreadLocal`, whole-table job; decoy: join fetch + pagination is safe on Hibernate 7.4 |
| 02/03 · PR03 multi-tenant auth | ~9.0k | Token-chosen `alg`, tenant from a header, user-only cache key, fail-open, stampede, optional `exp`, no `aud`, `String.equals` (argued) |
| 03/01 · PR04 Kafka consumer | ~8.4k | Commit before processing, shared-pool reordering, poison-pill infinite retry, no backpressure, auto-commit deleted, no rebalance listener, `shutdownNow`, swallowed interrupts |
| 03/02 · PR05 Beam | ~9.0k | Non-deterministic coder, content dedupe, 24 h watermark hold, fixed windows, lateness deleted (masked by the hold), constant idempotency key, processing-time fallback |
| 03/03 · PR06 outbox + lock | ~8.6k | Outbox outside the transaction, `id > cursor`, unacknowledged publish, no event id, lease < work, unconditional release, unfenced cursor |
| 04/01 · PR07 coroutines | ~7.8k | Reference parameters, leaked frames, swallowed exceptions, non-`noexcept` move, unpruned `weak_ptr`, `shared_from_this` cycle, moved-from ownership |
| 04/02 · PR08 lock-free ring | ~12.0k | Relaxed publish/hand-back (AArch64 `str` vs `stlr`), wrap compare, false sharing, ABA (scripted interleaving), pointer after release, mask with N = 1000 on an unchanged line, silent drops |
| 04/03 · PR09 embedded C | ~13.0k | DMA buffer sharing a cache line (a STOP undone by a replay), missing TX clean, ISR spinlock deadlock, plain flag (GCC hangs, Clang deletes the loop), `uint8_t` length wrap, tick-wrap failsafe trip, struct on the wire |
| 05/01 · PR10 Spring AI RAG | ~11.6k | Threads pinned by streams, no cancel, ACL on citations only, cross-tenant cache, partial answers cached, `retry` on a single-use `ChatClient` stream, filter-expression injection, unused timeout |
| 05/02 · PR11 MCP tools | ~9.7k | Confused deputy, token passthrough, non-idempotent refund under agent retries, path traversal, SSRF to cloud metadata, errors as successes, unit-less amounts, refund annotated read-only |
| 06/01 · 50 Java red flags | ~9.1k | J01–J50 with smell, mechanism, question, fix and proof link; scanner results over 8 PRs |
| 06/02 · 50 C/C++/kernel red flags | ~6.4k | C01–C50 incl. kernel-driver flags from the kernel's own docs; scanner results over 3 PRs |

### Folder 01 at a glance

| File | Words | What's in it |
|---|---|---|
| [01 · How companies grade live PR review rounds: L5 vs L6 vs L7](01-The-L7-Code-Review-Mental-Model-and-Rubric/01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md) | ~10.2k | Round formats; the 8-dimension rubric with L5/L6/L7 anchors; severity-weighted scoring; **PR-00** (ticket, 158-line diff, the author's 6 passing tests); three graded transcripts; the 45-minute plan; company/domain lenses; 10 chains |
| [02 · The 7-layer fault scan](01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md) | ~18.3k | Severity model; what tools catch vs what humans must; four 2024–2025 outages mapped to layers; the 3-pass procedure; seven layers with tells, questions and false positives; `FaultScan.java` + `fault_scan.cpp` (16 + 14 demos); **the full PR-00 answer key** with probes, refactor and tests; 10 chains |
| [03 · High-leverage communication](01-The-L7-Code-Review-Mental-Model-and-Rubric/03-high-leverage-communication-mentoring-tone-vs-blocking-nitpicks.md) | ~8.2k | Conventional Comments taxonomy; the O-I-E-P-O blocking comment; all PR-00 comments rewritten L5 → L7; tone, pushback, mentoring and narration scripts; the summary comment; `review_lint.py`; 10 chains |

## How to use this KB

1. **Read Folder 01 in order.** File 01 teaches the grading, 02 the hunting procedure, 03 the delivery. PR-00 runs through all three, so you see one PR graded, scanned and commented.
2. **For every PR in Folders 02–05**, do the review cold against a 45-minute timer: scratch list → ranked findings → summary comment. Only then open the diagnostic guide and answer key.
3. **Score yourself** with the severity-weighted method in [01 §4](01-The-L7-Code-Review-Mental-Model-and-Rubric/01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#4-scoring-mechanics-) and run your comments through `review_lint.py` ([03 §11](01-The-L7-Code-Review-Mental-Model-and-Rubric/03-high-leverage-communication-mentoring-tone-vs-blocking-nitpicks.md#11-the-linter-review_lintpy)).
4. **Before the interview**, re-read the checklists (§12–14 of each Folder 01 file) and Folder 06's red-flag cheat sheets.

## Conventions

- **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff (Google and Meta call L7 "Senior Staff"; Amazon's L7 is "Principal").
- **⚠** marks anything not publicly documented (internal rubrics, weights, hiring-committee mechanics). Those parts are composites from public sources and the structure of the round, never claims about a specific company's process. Company names from the brief are used as *domain lenses*. Questions and PRs are original; nothing here is a "leaked" interview question.
- **Severity:** Sev-1 (money/data/security/deployed-consumer breakage, possibly silent), Sev-2 (outage or corruption needing an unlikely-but-real trigger), Sev-3 (compounding cost/observability damage), Nit.
- **Layers:** L1 Correctness · L2 Concurrency · L3 Resources and failure paths · L4 I/O boundaries · L5 Compatibility · L6 Security · L7 Operability. "L5/L7" means a *level* in candidate contexts and a *layer* in finding tags (e.g. "F8 · L5 · Sev-1"); the context always disambiguates.
- **Review comments** use [Conventional Comments](https://conventionalcomments.org/) labels and decorations.
- **Output labels:** "Output (verified)" is spliced verbatim from a real run. "One measured run" marks timing- or scheduling-dependent values; the gate reruns them and compares structure with numbers masked.
- **PR line numbers** refer to the new (`+`) side of the diff.
- Files are written to disk as a folder tree, so they carry no `### FILE:` chat headers.

## Repository tree

```text
Live-PR-Code-Review-Bug-Hunt-L7-Reference/
├── README.md
├── 01-The-L7-Code-Review-Mental-Model-and-Rubric/
│   ├── 01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md
│   ├── 02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md
│   └── 03-high-leverage-communication-mentoring-tone-vs-blocking-nitpicks.md
├── 02-Java-Spring-Hibernate-and-Microservices-PR-Simulations/
│   ├── 01-pr01-fintech-wallet-transfer-transactional-proxy-and-deadlock-traps.md
│   ├── 02-pr02-high-throughput-order-api-n-plus-1-connection-exhaustion-and-virtual-threads.md
│   └── 03-pr03-multi-tenant-auth-cache-stampede-idor-and-jwt-security-flaws.md
├── 03-Kafka-Beam-Dataflow-and-Distributed-Streaming-PR-Simulations/
│   ├── 01-pr04-kafka-consumer-offset-commit-race-poison-pill-and-rebalance-storm.md
│   ├── 02-pr05-apache-beam-stateful-dofn-watermark-stall-and-coder-non-determinism.md
│   └── 03-pr06-transactional-outbox-and-redis-distributed-lock-fencing-bugs.md
├── 04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/
│   ├── 01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md
│   ├── 02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md
│   └── 03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md
├── 05-AI-Engineering-RAG-and-MCP-Server-PR-Simulations/
│   ├── 01-pr10-spring-ai-rag-pipeline-sse-thread-starvation-and-acl-leakage.md
│   └── 02-pr11-mcp-tool-server-confused-deputy-and-non-idempotent-agent-retries.md
└── 06-Anti-Pattern-Cheat-Sheets-and-Self-Audit-Checklists/
    ├── 01-50-instant-red-flags-in-java-and-spring-pull-requests.md
    └── 02-50-instant-red-flags-in-c-cpp-and-kernel-driver-pull-requests.md
```

## Gate

Every folder passes the same gate before it is marked done:

1. **Byte-identical listings.** Every runnable listing is extracted back out of the published Markdown and compared byte-for-byte with the source that was compiled.
2. **Independent rerun.** All listings, PR builds, the PRs' own test suites, probes and diffs are rebuilt and rerun into a separate directory. Outputs are compared with the spliced ones: *identical*, *numbers-only* (only measured values differ) or *DIFFERENT* (investigated; must be zero).
3. **Diff fidelity.** Each PR diff is regenerated with `git diff --no-index` from the compiled sources and must match the published diff byte-for-byte. The fixed-code fragments quoted in answer keys must each appear verbatim in the compiled fixed source.
4. **Structure.** Each file has Orientation → First principles → … → Failure modes → Bar-raiser chains (≥ 8, each with Initial Prompt / L5 Answer / Why L5 Stalls / L7 Answer) → Checklist → References, plus a Verification line and balanced fences.
5. **Comment lint.** Every L7 review comment and summary passes `review_lint.py`; every L5 counterpart is flagged.
6. **Links.** All relative links and heading anchors resolve; every external URL is fetched.

**Toolchain.**
- **Java:** JDK 25.0.4.1 (`javac --release 21 -Xlint:all -Werror`; Folders 02–05 add `-path,-classfile` for third-party jars), plus JDK 21.0.12 for PR02's pinning runs. JUnit Platform console 1.13.4 (SHA-1 verified against Maven Central).
- **Java libraries** (resolved by Maven 3.10 into a local repository): Spring Framework 7.0.10, Hibernate 7.4, HikariCP, embedded PostgreSQL 18 (zonky), Kafka clients, Apache Beam (DirectRunner), Spring AI 2.0.2, MCP Java SDK 2.1.0, Reactor 3.8.8.
- **C/C++:** GCC 16.2 (MinGW-w64) and Clang 21.1 (Zig 0.16), both at `-O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion` (`-std=c++23`, or `-std=c17` for PR09). Assembly via Clang for `aarch64-linux-gnu`, `x86_64-linux-gnu` and Cortex-M7 Thumb-2, and via GCC for x86-64.
- **Scripts:** Python 3.14 (`-I`).
- **Platform:** Windows 11, everything run sequentially.

### Folder 01 gate results (2026-10-29)

| Check | Result |
|---|---|
| 1 · Listings extracted from the KB vs compiled sources | **3/3 byte-identical** (`FaultScan.java`, `fault_scan.cpp`, `review_lint.py`) |
| 2 · Rebuild from templates + outputs vs published files | **3/3 byte-identical** |
| 3 · Independent rerun (listings on JDK 25 / GCC 16.2 / Clang 21.1; PR-00 base, PR and fixed builds; 4 JUnit runs; 18 probes; 2 diffs; lint) | 11 outputs identical, 3 numbers-only (timings and queue depths), **0 structurally different** |
| 3 · PR-00 diffs, fixed source, probe source, JUnit trees, lint output | **8/8 identical** across runs |
| 3 · PR-00 JUnit | base 2/2 pass · PR 6/6 pass · fixed 9/9 pass · PR's tests vs fix: 4 pass, 2 fail (the two that assert defects) |
| 4 · Fixed-code fragments quoted in the 02 answer key | 6 fragments, **0 lines missing** from the compiled fixed source |
| 5 · Structure | 3/3 files OK; 10 chains each (30 total) |
| 5 · Comment lint | L7: 13/13 comments and 1/1 summary clean · L5: 13/13 and 1/1 flagged |
| 6 · Links | 30/30 relative links and anchors OK; 33/34 external URLs OK; 1 bot-blocked (1Point3Acres returns 403 to scripts; the page was confirmed via web search) |

**What the gate caught.** The first version of the Java lock-ordering deadlock demo passed every run during authoring. Then the gate's independent rerun printed `true/false` instead of `false/false`: the first thread to time out released its lock and let the other through. The demo now scripts the interleaving with two latches and is deterministic (5/5 extra reruns plus the gate). The episode is written up in [02 §4 and §10.3](01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#103-what-the-demos-teach-beyond-their-layer) as a review lesson: ask for a test that forces the interleaving.

### Folders 02–06 gate results (2026-10-30)

| Check | Result |
|---|---|
| 1 · Rebuild every module from templates + outputs vs published files | **13/13 byte-identical** |
| 2 · Independent rerun: all 11 PRs (before, PR and fixed builds; author's tests, fixed tests and the PR's tests against the fix; probes; assembly listings; both diffs), on JDK 25/21 and on GCC 16.2 + Clang 21.1, then `redflags.py` | **11/11 PRs and the scanner rerun cleanly** |
| 3 · Every output spliced into a module, published vs rerun | 111 outputs: **108 identical, 3 numbers-only** (PR02 and PR04 timing probes, labeled "one measured run"), **0 different** |
| 3 · PR diffs regenerated with `git diff --no-index` | identical (inside the 108) |
| 4 · Fixed-code fragments quoted in the 11 answer keys | **331 lines, 0 missing** from the compiled fixed sources |
| 5 · Structure | 13/13 modules OK; ≥ 8 bar-raiser chains each |
| 5 · Comment lint | **96/96 L7 review comments clean** |
| 6 · Links (all 17 files incl. README) | **186/186 relative links and anchors OK**; external URLs **103 OK + 1 bot-blocked** (1Point3Acres, Folder 01) of 104 |

**What verification changed.**
- **PR09:** the failsafe finding was rewritten after re-deriving it with a continuous 1 kHz tick.
- **PR10:** the fixed retry was rebuilt around `Flux.defer` after a probe showed Spring AI 2.0.2's stream can't be re-subscribed.
- **PR02:** the expected pagination bug turned out not to exist on Hibernate 7.4, so it became a decoy.
- **PR04:** a hung probe became defect F8.
- **Folder 06:** the scanner first missed deleted test files and diff-aligned deletions; both were fixed before its numbers went into the cheat sheets.
- **Gate:** the link checker was scraping attack-example URLs (cloud metadata, `evil.example`) written as inline code, so it now ignores code spans.

## Where this KB refines the brief

1. **Folder names.** The brief's role line names `01-The-L7-Code-Review-Framework/` … `06-Interactive-PR-Review-Scorecards/`, but its repository blueprint names `01-The-L7-Code-Review-Mental-Model-and-Rubric/` … `06-Anti-Pattern-Cheat-Sheets-and-Self-Audit-Checklists/`. The blueprint names are used. Scorecard material is in Folder 01 (rubric and scoring) and recurs in every PR module (§9, a severity-weighted scoring table).
2. **"Passes unit tests" is literal.** Each PR ships with its author's own tests, which are run and shown passing against the buggy code. Separate production-shaped probes (multiple instances, timeouts after commit, failover, old consumers, other tenants) demonstrate each defect on the PR and its absence on the fix.
3. **A calibration PR in Folder 01.** PR-00 (158 diff lines, 9 defects plus 2 test/doc findings) is a worked example of the module format before the 100–150-line simulations begin. It is graded in 01, scanned and answered in 02, and commented in 03.
4. **Company names are lenses, not leaks.** The six companies are mapped to the domains their interviewers tend to probe, from public material. The only format with multiple public candidate reports (Stripe's "Bug Squash") is cited as anecdotal.
5. **Real incidents from primary sources.** The four 2024–2025 outages used to motivate the 7-layer scan (AWS, Cloudflare, Google Cloud, CrowdStrike) are quoted from the companies' own post-incident reports, and the limits of what review could have caught are stated.
6. **C++ demos stay inside defined behavior.** Where a real bug is UB (overflowing `memcpy`, dangling reads), the demo prints the decision the buggy code would make rather than executing UB, so outputs are reproducible across GCC and Clang.
7. **Review comments are machine-checked.** A small linter enforces labels, tone and the impact/evidence/proposal triple on L7 comments. Its lexical limits are documented in its self-test.
8. **Diff length.** The brief asks for 100–150-line diffs. The published diffs run 157–269 lines, because they are complete `git diff` output: file headers, hunk headers, context lines, and the author's rewritten test file, which is part of what the reviewer must read. The production-code change in each PR is in the brief's range. Nothing is summarized or shortened.
9. **Hardware claims rest on generated code, not hardware.** No ARM or Cortex-M hardware was available. PR08 shows the AArch64 instructions Clang emits for the PR and the fix (`str`/`ldr` vs `stlr`/`ldar`) and argues reordering from the memory model. PR09 runs against a host model of a write-back D-cache, DMA and interrupt delivery, and shows the Cortex-M7 code for the defect a host run can't reproduce. Each module says so in its Verification line.
10. **Version-specific facts are pinned and probed.** Where behavior depends on a version, the module measures it: Hibernate 7.4's join-fetch pagination (a decoy in PR02), JDK 21 virtual-thread pinning (PR02 runs its tests and probes on JDK 21), and Spring AI 2.0.2's non-resubscribable `ChatClient` stream (PR10).
11. **Compiler lint for third-party jars.** Java builds use `-Xlint:all,-path,-classfile -Werror`. The two exclusions silence warnings about third-party jars' manifests and class files (Beam, Spring AI), never about this KB's code.
12. **The red-flag scanner reports its own limits.** Folder 06's `redflags.py` was written alongside the PRs, so its recall on them is an upper bound, and the sheets say so. They lead with the numbers that generalize: defects no regex can see, false alarms, and flags that still fire on the corrected code.

## Facts measured while building Folder 01

- PR-00: the author's 6 tests pass on the buggy code. Against the fix, exactly the 2 tests that assert defects fail; the fixed suite passes 9/9.
- Two pods, two keys, 6,000 + 6,000 on a 10,000 charge: over-refund in 20/20 trials on the PR (gateway latency 20 ms), 0/20 on the fix. Same key on two pods: duplicate events in 20/20 trials, 0/20 on the fix.
- Lock across a 20 ms gateway call, 16 concurrent refunds on one pod: about 16 × 20 ms on the PR vs about 20 ms on the fix.
- `std::accumulate` with an `int` init over `int64_t` data truncates silently under `-Wall -Wextra -Wconversion -Werror` on both GCC 16 and Clang 21: the narrowing sits in a system header.
- `std::this_thread::sleep_for(5ms)` sleeps about 15 ms on this Windows machine (default timer tick ~15.6 ms). The C++ lock-across-I/O demo therefore measures ~120 ms for 8 "5 ms" sends, while Java's `Thread.sleep(20)` measured close to 20 ms.
- A one-latch "forced deadlock" test is not deterministic: two `tryLock` timeouts race, and the loser's release lets the winner finish. Holding both first locks until both threads have tried makes it deterministic.
- The IDE's Java inspections flagged the deliberate boxed `Integer ==` in `FaultScan.java`. That illustrates the "tools catch this class; spend human attention elsewhere" point in 02 §1.3.

## Facts measured while building Folders 02–06

- **Hibernate 7.4** paginates `join fetch` + `setMaxResults` in SQL (a derived table), so the classic "in-memory pagination" warning no longer applies there. PR02 uses it as a decoy, with the SQL as evidence.
- **Kafka:** with a `group.id`, `enable.auto.commit` defaults to `true`, so deleting the explicit `"false"` changes behavior silently (PR04 F5). A retry loop that restores the interrupt flag and keeps looping hung the probe JVM, and became PR04 F8.
- **Beam:** a 24-hour timer output timestamp holds the watermark, and every alert fires a day late. It also *masks* the deleted allowed lateness, which only bites after the hold is fixed (PR05 F3/F5).
- **PR07:** `std::vector` growth with a non-`noexcept` move acquired 227 pixel blocks for 100 pushes (100 with `noexcept`), identical on libstdc++ and libc++.
- **PR08:** with `N = 1000` and an `& (N - 1)` mask, a full ring delivers 256 distinct ticks out of 1,000. At AArch64 `-O2`, relaxed vs release is `str` vs `stlr` and `ldr` vs `ldar`, while x86-64 emits `mov` for both. GCC 16 warns (`-Winterference-size`) when `std::hardware_destructive_interference_size` is used in a header.
- **PR09:** a polled plain `bool` written by an ISR compiles to a jump-to-self with GCC 16 (x86-64) and to `bx lr` (loop deleted) with Clang 21 (Cortex-M7). Both are permitted by C's forward-progress rule. GCC compiles the `uint8_t` length check to an 8-bit `cmp cl, 24`. The first draft of the failsafe finding claimed "never fires." Re-deriving it with a continuous 1 kHz tick showed the real failure is a spurious trip, and the module was corrected.
- **PR10:** in Spring AI 2.0.2, re-subscribing a `ChatClient` `stream().content()` Flux fails with `IllegalStateException: No StreamAdvisors available to execute`, so `.retry(n)` never retries. `Flux.defer` around the request fixes it. `SimpleVectorStore` string filters are injectable, because `&&` binds tighter than `||`.
- **PR11:** MCP Java SDK 2.1.0 deprecates the no-argument `Tool.builder()` (caught by `-Werror`). The MCP spec's "Confused Deputy" section covers an OAuth-consent variant. PR11's defect is the classic authorization form, and the module says so.
- **Red-flag scanner:** over the 8 Java PRs, 51 of 61 defects have a rule firing on their line, 10 are judgment-only, and the rules raise 63 flags on the corrected code. Over PR07–PR09: 22 of 22 (training set) and 21 flags on corrected code. In five PRs the deleted test is exactly the one that would have caught a planted defect.
