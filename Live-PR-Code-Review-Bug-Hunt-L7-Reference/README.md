# Live PR Code Review & Bug-Hunt: L7 Reference

A first-principles training manual and PR simulation bank for the **live pull-request review / bug-hunt** interview round at the Staff and Principal level (FAANG L6–L7). It covers Java 21+ (Spring Boot, Hibernate, Kafka, concurrency) and C/C++20/23 (systems, memory safety, DMA, lock-free concurrency). Every PR simulation is a realistic multi-file `git diff` that compiles and passes its author's tests while hiding 7–10 high-severity defects. Each comes with a timed 3-pass diagnostic guide and a line-by-line L7 answer key.

## Status

| Folder | Files | Status |
|---|---|---|
| [01-The-L7-Code-Review-Mental-Model-and-Rubric](01-The-L7-Code-Review-Mental-Model-and-Rubric/) | 3 | ✅ Done 2026-10-29, gated |
| 02-Java-Spring-Hibernate-and-Microservices-PR-Simulations | 3 (PR01–PR03) | ⏳ Next |
| 03-Kafka-Beam-Dataflow-and-Distributed-Streaming-PR-Simulations | 3 (PR04–PR06) | ⏳ |
| 04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations | 3 (PR07–PR09) | ⏳ |
| 05-AI-Engineering-RAG-and-MCP-Server-PR-Simulations | 2 (PR10–PR11) | ⏳ |
| 06-Anti-Pattern-Cheat-Sheets-and-Self-Audit-Checklists | 2 | ⏳ |

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

**Toolchain.** JDK 25.0.4.1 (`javac --release 21 -Xlint:all -Werror`); JUnit Platform console 1.13.4 (SHA-1 verified against Maven Central); GCC 16.2 (MinGW-w64) and Clang 21.1 (Zig 0.16), both at `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`; Python 3.14 (`-I`). Windows 11, run sequentially.

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

## Where this KB refines the brief

1. **Folder names.** The brief's role line names `01-The-L7-Code-Review-Framework/` … `06-Interactive-PR-Review-Scorecards/`, but its repository blueprint names `01-The-L7-Code-Review-Mental-Model-and-Rubric/` … `06-Anti-Pattern-Cheat-Sheets-and-Self-Audit-Checklists/`. The blueprint names are used. Scorecard material is in Folder 01 (rubric and scoring) and will recur per PR.
2. **"Passes unit tests" is literal.** Each PR ships with its author's own tests, which are run and shown passing against the buggy code. Separate production-shaped probes (multiple instances, timeouts after commit, failover, old consumers, other tenants) demonstrate each defect on the PR and its absence on the fix.
3. **A calibration PR in Folder 01.** PR-00 (158 diff lines, 9 defects plus 2 test/doc findings) is a worked example of the module format before the 100–150-line simulations begin. It is graded in 01, scanned and answered in 02, and commented in 03.
4. **Company names are lenses, not leaks.** The six companies are mapped to the domains their interviewers tend to probe, from public material. The only format with multiple public candidate reports (Stripe's "Bug Squash") is cited as anecdotal.
5. **Real incidents from primary sources.** The four 2024–2025 outages used to motivate the 7-layer scan (AWS, Cloudflare, Google Cloud, CrowdStrike) are quoted from the companies' own post-incident reports, and the limits of what review could have caught are stated.
6. **C++ demos stay inside defined behavior.** Where a real bug is UB (overflowing `memcpy`, dangling reads), the demo prints the decision the buggy code would make rather than executing UB, so outputs are reproducible across GCC and Clang.
7. **Review comments are machine-checked.** A small linter enforces labels, tone and the impact/evidence/proposal triple on L7 comments. Its lexical limits are documented in its self-test.

## Facts measured while building Folder 01

- PR-00: the author's 6 tests pass on the buggy code. Against the fix, exactly the 2 tests that assert defects fail; the fixed suite passes 9/9.
- Two pods, two keys, 6,000 + 6,000 on a 10,000 charge: over-refund in 20/20 trials on the PR (gateway latency 20 ms), 0/20 on the fix. Same key on two pods: duplicate events in 20/20 trials, 0/20 on the fix.
- Lock across a 20 ms gateway call, 16 concurrent refunds on one pod: about 16 × 20 ms on the PR vs about 20 ms on the fix.
- `std::accumulate` with an `int` init over `int64_t` data truncates silently under `-Wall -Wextra -Wconversion -Werror` on both GCC 16 and Clang 21: the narrowing sits in a system header.
- `std::this_thread::sleep_for(5ms)` sleeps about 15 ms on this Windows machine (default timer tick ~15.6 ms). The C++ lock-across-I/O demo therefore measures ~120 ms for 8 "5 ms" sends, while Java's `Thread.sleep(20)` measured close to 20 ms.
- A one-latch "forced deadlock" test is not deterministic: two `tryLock` timeouts race, and the loser's release lets the winner finish. Holding both first locks until both threads have tried makes it deterministic.
- The IDE's Java inspections flagged the deliberate boxed `Integer ==` in `FaultScan.java`. That illustrates the "tools catch this class; spend human attention elsewhere" point in 02 §1.3.
