# Spec-Driven Prompting: Invariants, Anti-Goals and Verification Contracts

> **Folder 02 · File 1 of 3** · verified 2026-10-30 · builds on [Folder 01 file 02 §1.3 and §1.10](../01-First-Principles-of-Claude-Attention-and-Prompt-Physics/02-extended-thinking-physics-when-to-use-and-how-to-prompt-reasoning-models.md)
> **Listings:** `SpecContract.java` (a spec compiler and linter) · `spec_output_checker.py` (holds generated code to the contract)

---

## 0. Orientation

Folder 01 explained *why* a one-line prompt produces tutorial-shaped code: every decision you leave unstated is sampled from the model's prior. This file is the engineering response. It treats a prompt as a **specification with a verification contract**, written, reviewed and versioned like any other artifact, and it holds the model's output to that contract with checks that run without a human.

The method has three parts:

1. **Write the spec as typed blocks:** goal, context, pinned stack, numeric targets, invariants (each with a check), edge cases (each with a test), anti-goals, verification and an output contract. L1 compiles and lints this.
2. **Render it deterministically into the prompt.** It goes into a static, cacheable position (Folder 01 file 01), or into a `SPEC.md` the agent reads by path.
3. **Check the output mechanically.** Run the invariants that a static check can decide, then tests for the rest. L2 is a static checker for ten Spring Boot invariants plus a self-invocation rule. It caught a real bug in this file's own first draft of the "production" fixture.

Claim labels: **[doc]**, **[measured]**, **[research]**, **[inference]**, ⚠ verify, as in [Folder 01](../01-First-Principles-of-Claude-Attention-and-Prompt-Physics/01-transformer-attention-lost-in-the-middle-and-xml-tag-grammar.md#0-orientation).

### 0.1 The twelve rules

1. **Count the decisions before you write the prompt.** A Spring Boot service carries 20+ consequential decisions. A one-line prompt specifies about two of them. [inference]
2. **Every invariant names its check**: a test name, an ArchUnit rule or a static rule. An invariant nobody checks is a preference. [measured: L1 SC02]
3. **Every edge case names its test.** Edge cases are test vectors for the model's search *and* for your CI. [measured: L1 SC03]
4. **Replace adjectives with numbers.** "Robust, scalable, fast" constrains nothing; "p99 ≤ 150 ms at 1,200 req/s" does. [measured: L1 SC01/SC06]
5. **Pin the stack with versions.** "Spring Boot" lets the prior pick the year. [measured: L1 SC05]
6. **Name the tempting wrong designs as anti-goals, each with its alternative.** Opus 5.5 "responds well to instructions that name specific patterns to avoid". [doc]
7. **Give the reason, not just the rule.** Claude "can generalize from the explanation". [doc]
8. **Separate invariants (checked) from conventions (CLAUDE.md) from preferences (soft).** Put each where it belongs. [inference]
9. **Bound the scope explicitly**: what not to change, and no unrequested features or abstractions. [doc]
10. **The output contract asks for evidence**: diffs plus a traceability matrix with real test names, never "explain your reasoning". [doc + Folder 01]
11. **Check outputs mechanically before a human reads them.** The checker found a self-invocation bug that looked right to its author. [measured: L2]
12. **Measure the prompt.** The same tasks, run with vague and with spec prompts in fresh sessions, scored by tests plus the checker, priced per solved task. [inference + doc]

---

## 1. First principles

### 1.1 The decision inventory: what a one-line prompt leaves to the prior [inference]

"Build a Spring Boot Order Service" sounds like one decision. Here is a partial inventory of what a reviewer would hold the result to:

| Area | Decisions |
|---|---|
| Persistence | ORM vs JDBC; id strategy; schema migration tool; `ddl-auto`; `open-in-view`; batch sizes |
| Transactions | boundaries; isolation; what may happen inside one (no remote I/O); lock order |
| Idempotency | key source; storage; enforcement (unique index vs read-then-write) |
| Messaging | dual-write avoidance (outbox); producer idempotence; ordering keys; consumer dedup |
| Remote calls | timeouts; retries with jitter; circuit breaking; bulkheads |
| API | error model (RFC 9457); validation; versioning; pagination |
| Concurrency | virtual threads on JDK 21 vs 24+ pinning; pool sizes; back-pressure |
| Operability | metrics, traces, log correlation; health and readiness |
| Security | authn/z; input limits; secrets |
| Tests | unit vs integration (Testcontainers); concurrency tests; architecture tests |

That is 30+ decisions, and a one-line prompt fixes perhaps two (Spring Boot, "order"). Folder 01 file 02 §1.10 explains what happens to the rest: each is sampled from p(code | weak prompt), which is dominated by short, tutorial-shaped training documents.

Each stated constraint **conditions away a region** of that distribution. A spec is literally the information you add to move the conditional distribution out of tutorial space.

Two corollaries:
- **Specs are cheap relative to review.** A 600-token spec replaces rounds of review comments that each re-run an expensive agent turn.
- **Unspecified is not neutral.** Silence is a vote for the prior's choice. If you'd reject the prior's choice in review, say so in the spec.

### 1.2 Anatomy of a spec contract

| Block | Must contain | Failure mode when missing |
|---|---|---|
| `<goal>` | One outcome, testable ("exactly once per Idempotency-Key") | The model optimises a vaguer objective |
| `<context>` | Why it matters: who calls it, what breaks, volumes | No basis for trade-offs; the docs show Claude "can generalize from the explanation" [doc] |
| `<stack>` | Pinned versions | The prior picks versions and APIs (Boot 2 `WebSecurityConfigurerAdapter`, `javax.*`) |
| `<targets>` | Numbers: latency, throughput, size, error budget | "Scalable" with nothing to verify |
| `<invariants>` | Falsifiable rules, each with an id and a **check** | Every unstated property defaults to tutorial space |
| `<edge_cases>` | Concrete adversarial inputs, each with a **test** | Happy-path code and happy-path tests |
| `<anti_goals>` | The tempting wrong designs, each paired with the alternative | The model reaches for the common-but-wrong pattern |
| `<verification>` | Checks to run in reasoning before writing code | No stopping rule for the search (Folder 01 file 02 §1.3) |
| `<output_contract>` | Shape and evidence: diffs plus a traceability matrix | Prose essays; unverifiable claims |

L1 (`SpecContract.java`) implements this as records, lints for the failure column (rules SC01–SC09), and renders the XML deterministically, so the same spec gives the same bytes and stays cacheable. On the vague spec it reports **11 findings across 8 rules**. On the full spec it reports none, and it prints the rendered prompt and a traceability matrix (§3).

### 1.3 Invariants, conventions, preferences: put each in the right place

- **Invariant:** a property the output must have, checkable by a machine. "No JDBC connection held across Kafka/HTTP I/O" → ArchUnit or the L2 check. It belongs in the spec, *and* in CI.
- **Convention:** a house rule that applies to every task, such as package-by-feature, constructor injection, records for DTOs or ProblemDetail errors. It belongs in **CLAUDE.md** (Folder 03), which Claude Code loads into every session. Repeating it in every prompt wastes tokens and risks drift between copies.
- **Preference:** a soft choice ("prefer `JdbcClient` for simple queries"). Mark it as a preference so the model may deviate with a reason.

This separation matters for compliance. A spec that lists 40 MUSTs, half of them conventions, dilutes the five that are task-critical (Folder 01 file 01 §1.4).

### 1.4 Anti-goals: name the wrong design, then give the right one [doc, inference]

The model's search considers the designs that are most common in training data. For the order service those are a distributed lock, `existsBy…` before insert, and `kafkaTemplate.send()` inside `@Transactional`. Naming them removes them from the search.

Anthropic's Opus 5.5 guidance makes the same point for frontend work: a general instruction such as "avoid a generic AI look" "mostly swaps one default for another", while instructions "that name specific patterns to avoid" work, iteratively extended [doc].

Older advice warns that negative instructions prime the forbidden behaviour, and the reconciliation is simple: **pair every anti-goal with its alternative**. Write "No distributed locks; enforce uniqueness with a UNIQUE index and handle the conflict", not just "No distributed locks".

### 1.5 Verification contracts: traceability is the product [doc, measured]

A verification contract has two halves:

1. **For the model:** `<verification>` checks to run in its reasoning before writing code. They are phrased as "check in your reasoning that …", which is thinking and is allowed. Never "show your checks", which is reasoning extraction and may be declined (Folder 01 file 02 §1.8).
2. **For you:** a **traceability matrix** in the output contract (requirement id → enforcing test or rule), plus mechanical checks you run on the result.

The matrix turns review from "read 600 lines and hope" into "check that nine named tests exist and pass". L1 prints one. L2 runs the static half.

Why external checks rather than "review your own work"? Folder 02 file 02 derives it. Ungated self-critique converges to a fixed point p* = t·r / (f·b + t·r) that can sit *below* a strong model's first-try accuracy. A test-gated loop only ever adds correct answers, until it hits the verifier's blind spots [measured: file 02 L4].

### 1.6 Scope control: preventing over-engineering and test-gaming [doc]

Strong models at high effort sometimes do more than you asked. Anthropic documents three behaviours with prompt fixes:

- **Over-engineering:** extra files, abstractions, configurability, defensive code for impossible cases. Fix with an explicit minimal-scope block: "A bug fix doesn't need surrounding code cleaned up … Don't create helpers, utilities, or abstractions for one-time operations" [doc].
- **Test-gaming:** "focus too heavily on making tests pass at the expense of more general solutions", including hard-coding test inputs. Fix: "Tests are there to verify correctness, not to define the solution … If … any of the tests are incorrect, please inform me rather than working around them" [doc].
- **Unrequested adjacent actions:** state boundaries explicitly. "When the user is describing a problem … the deliverable is your assessment" [doc].

In a spec these become an `<scope>` block: what may change, what must not, and whether new dependencies are allowed.

### 1.7 Phase 0: generate the spec before the code [inference]

For anything bigger than a bug fix, make the first prompt produce the **spec**, not code:

1. **The model drafts it.** Ask Claude to draft `SPEC.md`: the decision inventory, proposed invariants, edge cases, anti-goals, schema, API contract and open questions. Ask it to *ask* about anything it cannot infer from the repo.
2. **You review it.** This is the cheapest review you will do: about 2 pages instead of about 2,000 lines.
3. **Implementation references it.** Implementation prompts reference the spec by path ("Implement SPEC.md §3 POST /orders; hold the output to SPEC.md §5 invariants"). The spec is versioned in git, cacheable, and shared by every agent that works on the feature.

Folder 07 template 1 is the full "Phase 0 RFC & spec generator" prompt.

### 1.8 Measuring whether specs help *your* codebase

Folder 01 frames "vague prompts produce junior code" as a mechanism, not a measured fact about current Claude. The way to turn it into a number for your team:

1. Pick 20–40 real tasks from your backlog, each with an acceptance test.
2. Write two prompts per task: a **vague** one (how engineers actually ask) and a **spec** one (L1-rendered).
3. Run each in a fresh session at the same model and effort. In Claude Code that is `claude -p` in CI (Folder 04), one task at a time.
4. Score every output: acceptance tests pass/fail, L2 contract checks passed/total, review comments needed, `usage` cost.
5. Report pass rate, contract score and **$ per solved task** for each variant, and look at the hardest quartile separately.

The KB doesn't run this here because it spends tokens. L2 was validated on hand-written fixtures: a tutorial-shaped change set scores **1/11**, the production-shaped first draft **10/11** (caught by INV-TX-SELF), and the fixed one **11/11** [measured].

---

## 2. Practice

### 2.1 The spec template (as L1 renders it)

The full rendered prompt is in L1's output (§3). The skeleton, with the blocks L1 adds beyond Folder 01's verification contract:

```xml
<goal>One testable outcome.</goal>
<context>Who calls this, what breaks if it is wrong, volumes and peaks.</context>
<stack>
- Java 21 (virtual threads on) - Spring Boot 3.5.x - PostgreSQL 17 - Kafka 4.x - Flyway 11.x - Testcontainers 1.21.x
</stack>
<targets>
- p99 latency at N req/s: <= X ms  - event lag p99: <= Y s  - duplicates under retry storm: 0
</targets>
<invariants>
- [INV-1] ... (each line is checkable; the matrix names its check)
</invariants>
<edge_cases>
- [EC-1] ... (each line becomes a named test)
</edge_cases>
<anti_goals>
- No <tempting design>; instead <alternative>.
</anti_goals>
<scope>
Change only order-service. No new dependencies. No refactoring outside the files you must touch.
If a test or this spec looks wrong, say so instead of working around it.
</scope>
<verification>Before writing the final code, check in your reasoning that: (1) ... (2) ... If any check fails, change the design first.</verification>
<output_contract>Unified diffs; then the traceability matrix (id -> real test/rule name); at most five sentences of prose.</output_contract>
```

### 2.2 Five vague requests, rewritten

| Vague | Spec fragment that replaces it |
|---|---|
| "Add caching to the product endpoint." | `<targets>` p99 ≤ 40 ms at 5K req/s; staleness ≤ 30 s. `<invariants>` cache key includes tenant and locale; a write evicts by product id; no caching of 4xx/5xx. `<anti_goals>` no `@Cacheable` on methods with side effects; no unbounded caches (max size and TTL set). |
| "Make the report faster." | `<context>` the report reads 40M rows nightly and takes 2 h. `<targets>` ≤ 10 min; heap ≤ 2 GB. `<invariants>` keyset pagination or a server-side cursor; no `findAll()`. `<edge_cases>` 0 rows; 40M rows; concurrent writes during the run. |
| "Add retries to the payment client." | `<invariants>` only idempotent operations retry (or with an idempotency key); exponential backoff, base 200 ms, factor 2, cap 5 s, full jitter, max 4 attempts; retry budget ≤ 10% of calls. `<anti_goals>` no retry on 4xx except 409/429; no retry inside a DB transaction. |
| "Secure the admin API." | `<invariants>` OAuth2 resource server with JWT; `ROLE_ADMIN` required on `/admin/**`; method security on mutating endpoints; audit log entry per mutation. `<edge_cases>` expired token; token for another tenant; missing scope. `<anti_goals>` no custom JWT parsing; no security in controllers by `if`. |
| "Write tests for OrderService." | `<goal>` tests that would fail on these defects: duplicate under concurrent retries, outbox missing on rollback, negative totals. `<invariants>` Testcontainers PG17 + Kafka, no mocks of the repository; one concurrency test with 50 threads on a `CyclicBarrier`. `<anti_goals>` no tests that assert on log text; no `Thread.sleep` synchronisation. |

### 2.3 `SPEC.md` skeleton for the repository

```markdown
# SPEC: <feature>  (status: draft | approved | superseded)  owner: <team>
## 1 Goal and non-goals
## 2 Context and numbers (callers, volumes, SLOs, error budget)
## 3 API contract (endpoints, status codes, ProblemDetail types)
## 4 Data model and migrations (Flyway files, indexes, constraints)
## 5 Invariants (INV-n, each with its check)
## 6 Edge cases (EC-n, each with its test)
## 7 Anti-goals (with alternatives)
## 8 Rollout (flags, migration order, backfill)
## 9 Open questions (answered before approval)
## 10 Traceability matrix (filled by the implementation PR)
```

### 2.4 The spec review checklist

Use this before you hand a spec to an agent:

- [ ] Every adjective is backed by a number or a named check (L1 SC01).
- [ ] Every stack element carries a version (SC05).
- [ ] Targets exist and are measurable (SC06).
- [ ] Every invariant names its check, and every edge case its test (SC02/SC03).
- [ ] The anti-goals name the 2–4 most common wrong designs for this problem, each with its alternative (SC04).
- [ ] Conventions are in CLAUDE.md, not repeated here.
- [ ] Scope says what must not change and whether dependencies may be added.
- [ ] The output contract asks for a traceability matrix and forbids reasoning transcripts.

---

## 3. Verified listings

### L1 · `SpecContract.java`: spec compiler and linter

**What it shows.** A typed spec, nine lint rules for the gaps the prior fills (SC01–SC09), deterministic XML rendering, and a traceability matrix. The vague spec produces 11 findings across 8 rules; the full spec produces 0.

**What it does not show.** That the model obeys the spec. That is L2's job and your eval's (§1.8).

Run: `java SpecContract.java`.

```java
// SpecContract.java - a spec-first prompt compiler: a typed spec (goal, pinned stack, measurable targets,
// invariants with checks, edge cases with tests, anti-goals, verification, output contract) is linted for
// the gaps a model would fill from its training prior, then rendered into a deterministic XML prompt plus a
// traceability matrix you can hold the output to.
//
// Java 21, no dependencies.  Run:  java SpecContract.java   (prints ALL ASSERTIONS PASSED)
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Pattern;

public final class SpecContract {

    record Invariant(String id, String rule, String check) {}
    record EdgeCase(String id, String scenario, String test) {}
    record Target(String metric, String value) {}                       // measurable, e.g. "p99 latency", "<= 150 ms"
    record Spec(String title, String goal, String context, List<String> stack, List<Target> targets,
                List<Invariant> invariants, List<EdgeCase> edgeCases, List<String> antiGoals,
                List<String> verification, String outputContract) {}

    record Finding(String rule, String where, String message) {}

    // Words that sound like requirements but constrain nothing unless a number or a named check follows.
    static final Pattern VAGUE = Pattern.compile(
            "\\b(robust|scalable|production[- ]ready|best practices?|high[- ]performance|performant|secure|"
            + "clean code|enterprise[- ]grade|fast|efficient|reliable|modern|well[- ]tested)\\b", Pattern.CASE_INSENSITIVE);
    static final Pattern HAS_NUMBER = Pattern.compile("\\d");
    static final Pattern VERSIONED = Pattern.compile("\\d+(\\.\\d+)*");

    static List<Finding> lint(Spec s) {
        List<Finding> f = new ArrayList<>();
        for (String[] field : new String[][] {{"goal", s.goal()}, {"context", s.context()}}) {
            for (String sentence : field[1].split("(?<=[.;!?])\\s+")) {
                var m = VAGUE.matcher(sentence);
                if (m.find() && !HAS_NUMBER.matcher(sentence).find())
                    f.add(new Finding("SC01", field[0], "'" + m.group(1) + "' with no number or named check: \"" + sentence.strip() + "\""));
            }
        }
        if (s.targets().isEmpty())
            f.add(new Finding("SC06", "targets", "no measurable targets (latency, throughput, size, error budget)"));
        for (String tech : s.stack())
            if (!VERSIONED.matcher(tech).find())
                f.add(new Finding("SC05", "stack", "unpinned: '" + tech + "' - the prior picks a version for you"));
        if (s.invariants().isEmpty())
            f.add(new Finding("SC02", "invariants", "no invariants - every unstated property is delegated to the prior"));
        Set<String> ids = new TreeSet<>();
        for (Invariant i : s.invariants()) {
            if (!ids.add(i.id())) f.add(new Finding("SC08", i.id(), "duplicate invariant id"));
            if (i.check().isBlank()) f.add(new Finding("SC02", i.id(), "invariant has no check (test name or static rule)"));
        }
        if (s.edgeCases().isEmpty())
            f.add(new Finding("SC03", "edge_cases", "no edge cases - the model tests only the happy path"));
        for (EdgeCase e : s.edgeCases())
            if (e.test().isBlank()) f.add(new Finding("SC03", e.id(), "edge case has no test"));
        if (s.antiGoals().isEmpty())
            f.add(new Finding("SC04", "anti_goals", "no anti-goals - tempting wrong designs stay on the table"));
        if (s.verification().isEmpty())
            f.add(new Finding("SC07", "verification", "no verification criteria - no stopping rule for the model's search"));
        if (s.outputContract().isBlank())
            f.add(new Finding("SC09", "output_contract", "no output contract"));
        return f;
    }

    static String render(Spec s) {
        StringBuilder b = new StringBuilder();
        b.append("<goal>\n").append(s.goal().strip()).append("\n</goal>\n\n");
        b.append("<context>\n").append(s.context().strip()).append("\n</context>\n\n");
        b.append("<stack>\n");
        s.stack().forEach(t -> b.append("- ").append(t).append('\n'));
        b.append("</stack>\n\n<targets>\n");
        s.targets().forEach(t -> b.append("- ").append(t.metric()).append(": ").append(t.value()).append('\n'));
        b.append("</targets>\n\n<invariants>\n");
        s.invariants().forEach(i -> b.append("- [").append(i.id()).append("] ").append(i.rule()).append('\n'));
        b.append("</invariants>\n\n<edge_cases>\n");
        s.edgeCases().forEach(e -> b.append("- [").append(e.id()).append("] ").append(e.scenario()).append('\n'));
        b.append("</edge_cases>\n\n<anti_goals>\n");
        s.antiGoals().forEach(a -> b.append("- ").append(a).append('\n'));
        b.append("</anti_goals>\n\n<verification>\nBefore writing the final code, check in your reasoning that:\n");
        for (int i = 0; i < s.verification().size(); i++)
            b.append("(").append(i + 1).append(") ").append(s.verification().get(i)).append('\n');
        b.append("If any check fails, change the design before writing code.\n</verification>\n\n");
        b.append("<output_contract>\n").append(s.outputContract().strip()).append("\n</output_contract>\n");
        return b.toString();
    }

    static String traceability(Spec s) {
        StringBuilder b = new StringBuilder("| id | requirement | enforced by |\n|---|---|---|\n");
        s.invariants().forEach(i -> b.append("| ").append(i.id()).append(" | ").append(i.rule()).append(" | ").append(i.check()).append(" |\n"));
        s.edgeCases().forEach(e -> b.append("| ").append(e.id()).append(" | ").append(e.scenario()).append(" | ").append(e.test()).append(" |\n"));
        return b.toString();
    }

    static Set<String> rules(List<Finding> fs) {
        Set<String> r = new TreeSet<>();
        fs.forEach(x -> r.add(x.rule()));
        return r;
    }

    static void check(boolean ok, String msg) {
        if (!ok) throw new AssertionError(msg);
    }

    public static void main(String[] args) {
        Spec vague = new Spec("Order service", "Build a robust, scalable Order Service using best practices.",
                "It should be production-ready and fast.", List.of("Java", "Spring Boot", "PostgreSQL"),
                List.of(), List.of(), List.of(), List.of(), List.of(), "");

        Spec good = new Spec("Create order",
                "Implement POST /orders in order-service: create an order exactly once per Idempotency-Key and publish OrderCreated.",
                "Mobile clients retry on timeout; peak 1,200 creates/s; duplicates cost refunds. Consumers rely on OrderCreated within 5 s.",
                List.of("Java 21 (virtual threads on)", "Spring Boot 3.5.x", "PostgreSQL 17", "Kafka 4.x", "Flyway 11.x", "Testcontainers 1.21.x"),
                List.of(new Target("p99 latency at 1,200 req/s", "<= 150 ms"), new Target("event lag p99", "<= 5 s"),
                        new Target("duplicate orders under retry storm", "0")),
                List.of(new Invariant("INV-1", "NEVER hold a JDBC connection or open transaction across Kafka or HTTP I/O.",
                                "ArchUnit rule TxBoundaryTest + OutboxRelay design"),
                        new Invariant("INV-2", "Idempotency via a UNIQUE index on (tenant_id, idempotency_key); no read-then-insert.",
                                "IdempotencyIT.concurrentDuplicates"),
                        new Invariant("INV-3", "Events leave via a transactional outbox row written in the order's transaction.",
                                "OutboxIT.eventWrittenAtomically"),
                        new Invariant("INV-4", "Constructor injection; DTOs are records; errors are RFC 9457 ProblemDetail.",
                                "ArchUnit rules + ProblemDetailIT"),
                        new Invariant("INV-5", "Schema changes only as Flyway migrations; ddl-auto=validate.", "MigrationIT")),
                List.of(new EdgeCase("EC-1", "50 concurrent POSTs with the same Idempotency-Key", "IdempotencyIT.concurrentDuplicates"),
                        new EdgeCase("EC-2", "Kafka unavailable for 30 s during a burst", "OutboxIT.brokerOutage"),
                        new EdgeCase("EC-3", "order with 10,000 line items", "CreateOrderIT.largeOrder"),
                        new EdgeCase("EC-4", "total = 0 and negative quantity", "ValidationTest.boundaries")),
                List.of("No distributed locks (Redis, ZooKeeper).", "No Kafka transactions spanning the DB commit.",
                        "No @Transactional on controller methods.", "No new framework or library beyond the stack."),
                List.of("no code path calls KafkaTemplate or an HTTP client inside a transaction",
                        "every invariant and edge case maps to a named test in the traceability matrix",
                        "the migration creates the unique index before the code relies on it"),
                "Unified diffs only, then the traceability matrix with real test names. At most five sentences of prose.");

        List<Finding> fv = lint(vague), fg = lint(good);
        System.out.println("--- VAGUE spec: " + fv.size() + " findings " + rules(fv));
        fv.forEach(x -> System.out.printf("  %s [%s] %s%n", x.rule(), x.where(), x.message()));
        System.out.println("--- GOOD spec: " + fg.size() + " findings");
        check(rules(fv).equals(new TreeSet<>(List.of("SC01", "SC02", "SC03", "SC04", "SC05", "SC06", "SC07", "SC09"))),
                "vague spec rules " + rules(fv));
        check(fg.isEmpty(), "good spec should be clean: " + fg);

        String prompt = render(good);
        check(prompt.equals(render(good)), "rendering is deterministic");
        check(prompt.toLowerCase(Locale.ROOT).indexOf("<goal>") == 0 && prompt.endsWith("</output_contract>\n"), "shape");
        System.out.println("--- rendered prompt (" + prompt.length() + " chars):");
        System.out.print(prompt);
        System.out.println("--- traceability matrix:");
        System.out.print(traceability(good));
        System.out.println("ALL ASSERTIONS PASSED");
    }
}
```

**Output (verified):**

```text
--- VAGUE spec: 11 findings [SC01, SC02, SC03, SC04, SC05, SC06, SC07, SC09]
  SC01 [goal] 'robust' with no number or named check: "Build a robust, scalable Order Service using best practices."
  SC01 [context] 'production-ready' with no number or named check: "It should be production-ready and fast."
  SC06 [targets] no measurable targets (latency, throughput, size, error budget)
  SC05 [stack] unpinned: 'Java' - the prior picks a version for you
  SC05 [stack] unpinned: 'Spring Boot' - the prior picks a version for you
  SC05 [stack] unpinned: 'PostgreSQL' - the prior picks a version for you
  SC02 [invariants] no invariants - every unstated property is delegated to the prior
  SC03 [edge_cases] no edge cases - the model tests only the happy path
  SC04 [anti_goals] no anti-goals - tempting wrong designs stay on the table
  SC07 [verification] no verification criteria - no stopping rule for the model's search
  SC09 [output_contract] no output contract
--- GOOD spec: 0 findings
--- rendered prompt (1943 chars):
<goal>
Implement POST /orders in order-service: create an order exactly once per Idempotency-Key and publish OrderCreated.
</goal>

<context>
Mobile clients retry on timeout; peak 1,200 creates/s; duplicates cost refunds. Consumers rely on OrderCreated within 5 s.
</context>

<stack>
- Java 21 (virtual threads on)
- Spring Boot 3.5.x
- PostgreSQL 17
- Kafka 4.x
- Flyway 11.x
- Testcontainers 1.21.x
</stack>

<targets>
- p99 latency at 1,200 req/s: <= 150 ms
- event lag p99: <= 5 s
- duplicate orders under retry storm: 0
</targets>

<invariants>
- [INV-1] NEVER hold a JDBC connection or open transaction across Kafka or HTTP I/O.
- [INV-2] Idempotency via a UNIQUE index on (tenant_id, idempotency_key); no read-then-insert.
- [INV-3] Events leave via a transactional outbox row written in the order's transaction.
- [INV-4] Constructor injection; DTOs are records; errors are RFC 9457 ProblemDetail.
- [INV-5] Schema changes only as Flyway migrations; ddl-auto=validate.
</invariants>

<edge_cases>
- [EC-1] 50 concurrent POSTs with the same Idempotency-Key
- [EC-2] Kafka unavailable for 30 s during a burst
- [EC-3] order with 10,000 line items
- [EC-4] total = 0 and negative quantity
</edge_cases>

<anti_goals>
- No distributed locks (Redis, ZooKeeper).
- No Kafka transactions spanning the DB commit.
- No @Transactional on controller methods.
- No new framework or library beyond the stack.
</anti_goals>

<verification>
Before writing the final code, check in your reasoning that:
(1) no code path calls KafkaTemplate or an HTTP client inside a transaction
(2) every invariant and edge case maps to a named test in the traceability matrix
(3) the migration creates the unique index before the code relies on it
If any check fails, change the design before writing code.
</verification>

<output_contract>
Unified diffs only, then the traceability matrix with real test names. At most five sentences of prose.
</output_contract>
--- traceability matrix:
| id | requirement | enforced by |
|---|---|---|
| INV-1 | NEVER hold a JDBC connection or open transaction across Kafka or HTTP I/O. | ArchUnit rule TxBoundaryTest + OutboxRelay design |
| INV-2 | Idempotency via a UNIQUE index on (tenant_id, idempotency_key); no read-then-insert. | IdempotencyIT.concurrentDuplicates |
| INV-3 | Events leave via a transactional outbox row written in the order's transaction. | OutboxIT.eventWrittenAtomically |
| INV-4 | Constructor injection; DTOs are records; errors are RFC 9457 ProblemDetail. | ArchUnit rules + ProblemDetailIT |
| INV-5 | Schema changes only as Flyway migrations; ddl-auto=validate. | MigrationIT |
| EC-1 | 50 concurrent POSTs with the same Idempotency-Key | IdempotencyIT.concurrentDuplicates |
| EC-2 | Kafka unavailable for 30 s during a burst | OutboxIT.brokerOutage |
| EC-3 | order with 10,000 line items | CreateOrderIT.largeOrder |
| EC-4 | total = 0 and negative quantity | ValidationTest.boundaries |
ALL ASSERTIONS PASSED
```

### L2 · `spec_output_checker.py`: hold generated code to the contract

**What it shows.** Eleven static checks for Spring Boot invariants:
- field injection
- IDENTITY ids
- `ddl-auto` and Flyway
- `open-in-view`
- HTTP timeouts
- ProblemDetail vs catch-all
- record DTOs
- I/O inside transactions (`@Transactional` and `TransactionTemplate`)
- **self-invocation of `@Transactional`**
- outbox table
- unique-index idempotency

The tutorial-shaped fixture passes 1/11, the production-shaped first draft 10/11, and the fixed version 11/11.

**The finding worth remembering.** The first draft of the production fixture looked right. `create()` called the fraud check outside the transaction, then called `insertWithOutbox()`, which was annotated `@Transactional`. But that call goes through `this`, not the Spring proxy, so **no transaction is ever started**. The order insert and the outbox insert are not atomic, which is exactly the dual-write the design exists to prevent. The INV-TX-SELF rule caught it. The fix uses an explicit `TransactionTemplate` boundary. Spring's documentation describes the proxy limitation: in proxy mode, only external method calls through the proxy are intercepted, and self-invocation is not.

**What it does not show.** Semantics that need execution, such as lock order or retry behaviour. Those belong to tests; regex checks are a first gate, not a proof.

Run: `python spec_output_checker.py`.

```python
"""spec_output_checker.py - hold generated Spring Boot code to the contract: static checks for the
machine-checkable invariants a spec-first prompt states (and a vague prompt leaves to the prior).

Input is a generated change set {path: content}. The fixtures below are HAND-WRITTEN exemplars of
tutorial-shaped and production-shaped output, used to validate the checker - they are not model outputs.
Point `check()` at real outputs from your eval runs (Folder 02 file 01, section 2.4) to measure the effect
of your prompts on your codebase.  Run: python spec_output_checker.py  (stdlib only)
"""
import re

RULES = []
IO_CALL = r"kafkaTemplate\.send|restClient\.|restTemplate\.|httpClient\.send|fraud\.check"


def rule(rule_id, text):
    def deco(fn):
        RULES.append((rule_id, text, fn))
        return fn
    return deco


def java(files):
    return {p: c for p, c in files.items() if p.endswith(".java")}


def config(files):
    return {p: c for p, c in files.items() if p.endswith((".yml", ".yaml", ".properties"))}


def line_of(content, offset):
    return content[:offset].count("\n") + 1


def lines_matching(files, pattern):
    rx = re.compile(pattern)
    for path, content in files.items():
        for n, line in enumerate(content.splitlines(), 1):
            if rx.search(line):
                yield f"{path}:{n}"


def balanced(content, start, open_ch, close_ch):
    """Return the text from `start` up to the bracket that closes depth 1."""
    depth, i = 1, start
    while depth and i < len(content):
        depth += {open_ch: 1, close_ch: -1}.get(content[i], 0)
        i += 1
    return content[start:i]


@rule("INV-DI", "constructor injection only (no @Autowired fields)")
def no_field_injection(files):
    return [f"{p}:{line_of(c, m.start())}" for p, c in java(files).items()
            for m in re.finditer(r"@Autowired\s+(?:private|protected|public)?\s*[\w<>, ]+\s+\w+\s*;", c)]


@rule("INV-ID", "no GenerationType.IDENTITY (it disables Hibernate JDBC insert batching)")
def no_identity(files):
    return list(lines_matching(java(files), r"GenerationType\.IDENTITY"))


@rule("INV-DDL", "schema via Flyway (db/migration/V*__*.sql present) and ddl-auto is validate/none")
def flyway_only(files):
    bad = list(lines_matching(config(files), r"ddl-auto\s*[:=]\s*(update|create|create-drop)"))
    if not any(re.search(r"db/migration/V\d+__\w+\.sql$", p) for p in files):
        bad.append("(no Flyway migration file)")
    return bad


@rule("INV-OIV", "spring.jpa.open-in-view is false")
def open_in_view_off(files):
    cfg = "\n".join(config(files).values())
    return [] if re.search(r"open-in-view\s*[:=]\s*false", cfg) else ["(open-in-view not disabled)"]


@rule("INV-TIMEOUT", "every outbound HTTP client sets connect and read timeouts")
def http_timeouts(files):
    bad = []
    for path, content in java(files).items():
        if re.search(r"RestClient\.builder|RestTemplate|HttpClient\.newBuilder|WebClient\.builder|RestClient\.Builder", content):
            if not (re.search(r"[cC]onnect(ion)?Timeout", content) and re.search(r"[rR]eadTimeout|\.timeout\(", content)):
                bad.append(f"{path} (client built without connect+read timeouts)")
    return bad


@rule("INV-ERR", "errors are RFC 9457 ProblemDetail; no catch-all Exception -> 500")
def problem_detail(files):
    bad = list(lines_matching(java(files), r"catch\s*\(\s*Exception\s+\w+\s*\)"))
    if not any("ProblemDetail" in c for c in java(files).values()):
        bad.append("(no ProblemDetail usage)")
    return bad


@rule("INV-DTO", "request/response DTOs are records")
def dto_records(files):
    return list(lines_matching(java(files), r"\bclass\s+\w+(Request|Response|Dto|DTO)\b"))


@rule("INV-TX-IO", "no Kafka/HTTP call inside a transaction (@Transactional or TransactionTemplate)")
def no_io_in_tx(files):
    bad = []
    for path, content in java(files).items():
        for m in re.finditer(r"@Transactional[^\n]*\n\s*(?:public|protected|private)?[^{;]*\{", content):
            if re.search(IO_CALL, balanced(content, m.end(), "{", "}")):
                bad.append(f"{path}:{line_of(content, m.start())}")
        for m in re.finditer(r"\.execute\(\s*\w+\s*->", content):              # TransactionTemplate lambdas
            if re.search(IO_CALL, balanced(content, m.end(), "(", ")")):
                bad.append(f"{path}:{line_of(content, m.start())}")
    return bad


@rule("INV-TX-SELF", "no @Transactional method called from its own class (the proxy is bypassed)")
def no_self_invocation(files):
    bad = []
    for path, content in java(files).items():
        for m in re.finditer(r"@Transactional[^\n]*\n\s*(?:public|protected|private)?\s*[\w<>, ]+\s+(\w+)\s*\(", content):
            name = m.group(1)
            for call in re.finditer(r"(?<![\w.])" + name + r"\s*\(", content):
                if call.start() != m.start(1):
                    bad.append(f"{path}:{line_of(content, call.start())} calls {name}()")
    return bad


@rule("INV-OUTBOX", "events published via a transactional outbox (outbox table in a migration)")
def outbox(files):
    sql = "\n".join(c for p, c in files.items() if p.endswith(".sql"))
    return [] if re.search(r"create\s+table\s+\w*outbox", sql, re.I) else ["(no outbox table)"]


@rule("INV-IDEMP", "idempotency enforced by a unique index, not read-then-insert")
def idempotency(files):
    sql = "\n".join(c for p, c in files.items() if p.endswith(".sql"))
    bad = [] if re.search(r"unique[^;]*idempotency_key", sql, re.I) else ["(no unique index on idempotency_key)"]
    bad += list(lines_matching(java(files), r"existsByIdempotencyKey|findByIdempotencyKey\(.*\)\.isPresent"))
    return bad


def check(files):
    results = [(rid, text, fn(files)) for rid, text, fn in RULES]
    return sum(1 for _, _, hits in results if not hits), results


TUTORIAL = {
    "src/main/java/com/acme/order/OrderController.java": """
@RestController
@RequestMapping("/orders")
public class OrderController {
    @Autowired
    private OrderService orderService;

    @PostMapping
    public ResponseEntity<OrderResponse> create(@RequestBody OrderRequest req) {
        try {
            return ResponseEntity.ok(orderService.create(req));
        } catch (Exception e) {
            return ResponseEntity.status(500).build();
        }
    }
}""",
    "src/main/java/com/acme/order/OrderService.java": """
@Service
public class OrderService {
    @Autowired
    private OrderRepository repo;
    @Autowired
    private KafkaTemplate<String, String> kafkaTemplate;
    private final RestTemplate restTemplate = new RestTemplate();

    @Transactional
    public OrderResponse create(OrderRequest req) {
        if (repo.existsByIdempotencyKey(req.getKey())) { return null; }
        restTemplate.getForObject("http://fraud/check", String.class);
        Order o = repo.save(new Order(req));
        kafkaTemplate.send("orders", o.getId().toString());
        return new OrderResponse(o);
    }
}""",
    "src/main/java/com/acme/order/Order.java": """
@Entity @Data
public class Order {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
}""",
    "src/main/java/com/acme/order/OrderRequest.java": "public class OrderRequest { private String key; }",
    "src/main/java/com/acme/order/OrderResponse.java": "public class OrderResponse { }",
    "src/main/resources/application.yml": "spring:\n  jpa:\n    hibernate:\n      ddl-auto: update\n",
}

COMMON = {
    "src/main/java/com/acme/order/OrderController.java": """
@RestController
@RequestMapping("/orders")
class OrderController {
    private final OrderService orders;
    OrderController(OrderService orders) { this.orders = orders; }

    @PostMapping
    ResponseEntity<OrderResponse> create(@RequestHeader("Idempotency-Key") String key, @Valid @RequestBody OrderRequest req) {
        return ResponseEntity.status(201).body(orders.create(key, req));
    }
}""",
    "src/main/java/com/acme/order/FraudClient.java": """
@Component
class FraudClient {
    private final RestClient http;
    FraudClient(RestClient.Builder b) {
        var f = new SimpleClientHttpRequestFactory();
        f.setConnectTimeout(Duration.ofMillis(300));
        f.setReadTimeout(Duration.ofSeconds(2));
        this.http = b.requestFactory(f).baseUrl("http://fraud").build();
    }
    void check(String customerId) { http.get().uri("/check/{id}", customerId).retrieve().toBodilessEntity(); }
}""",
    "src/main/java/com/acme/order/ApiErrors.java": """
@RestControllerAdvice
class ApiErrors {
    @ExceptionHandler(FraudRejectedException.class)
    ProblemDetail fraud(FraudRejectedException e) { return ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY, e.getMessage()); }
}""",
    "src/main/java/com/acme/order/OrderRequest.java": "record OrderRequest(String tenantId, String customerId, BigDecimal total) { String toJson() { return \"{}\"; } }",
    "src/main/java/com/acme/order/OrderResponse.java": "record OrderResponse(long id) {}",
    "src/main/resources/application.yml": "spring:\n  jpa:\n    open-in-view: false\n    hibernate:\n      ddl-auto: validate\n",
    "src/main/resources/db/migration/V1__orders.sql": """
create table orders (id bigserial primary key, tenant_id text not null, idempotency_key text not null, total numeric(12,2) not null);
create unique index orders_idem_ux on orders (tenant_id, idempotency_key);
create table outbox (id bigserial primary key, aggregate_id bigint not null, type text not null, payload jsonb not null, created_at timestamptz default now());
""",
}

INSERT_BODY = """
        long id = jdbc.sql("insert into orders(tenant_id, idempotency_key, total) values (?,?,?) on conflict do nothing returning id")
                .params(req.tenantId(), key, req.total()).query(Long.class).single();
        jdbc.sql("insert into outbox(aggregate_id, type, payload) values (?, 'OrderCreated', ?::jsonb)").params(id, req.toJson()).update();
        return new OrderResponse(id);
    }
}"""

# First draft: looks right, but create() calls a @Transactional method on `this` - no proxy, no transaction.
PRODUCTION_V1 = dict(COMMON, **{"src/main/java/com/acme/order/OrderService.java": """
@Service
class OrderService {
    private final JdbcClient jdbc;
    private final FraudClient fraud;
    OrderService(JdbcClient jdbc, FraudClient fraud) { this.jdbc = jdbc; this.fraud = fraud; }

    OrderResponse create(String key, OrderRequest req) {
        fraud.check(req.customerId());               // outside any transaction
        return insertWithOutbox(key, req);
    }

    @Transactional
    OrderResponse insertWithOutbox(String key, OrderRequest req) {""" + INSERT_BODY})

# Fixed: an explicit TransactionTemplate boundary - no proxy, so no self-invocation trap.
PRODUCTION = dict(COMMON, **{"src/main/java/com/acme/order/OrderService.java": """
@Service
class OrderService {
    private final JdbcClient jdbc;
    private final FraudClient fraud;
    private final TransactionTemplate tx;
    OrderService(JdbcClient jdbc, FraudClient fraud, TransactionTemplate tx) { this.jdbc = jdbc; this.fraud = fraud; this.tx = tx; }

    OrderResponse create(String key, OrderRequest req) {
        fraud.check(req.customerId());                           // outside any transaction
        return tx.execute(status -> insertWithOutbox(key, req)); // explicit boundary
    }

    private OrderResponse insertWithOutbox(String key, OrderRequest req) {""" + INSERT_BODY})

for name, files in [("TUTORIAL-shaped fixture", TUTORIAL), ("PRODUCTION-shaped, first draft", PRODUCTION_V1),
                    ("PRODUCTION-shaped, fixed", PRODUCTION)]:
    passed, results = check(files)
    print(f"--- {name}: {passed}/{len(results)} contract checks pass")
    for rid, text, hits in results:
        mark = "ok  " if not hits else "FAIL"
        detail = "" if not hits else " <- " + ", ".join(hits[:3]) + (" ..." if len(hits) > 3 else "")
        print(f"  {mark} {rid:<11} {text}{detail}")
    failed = {rid for rid, _, hits in results if hits}
    if name.startswith("TUTORIAL"):
        assert passed <= 1, "tutorial-shaped code should fail nearly every contract check"
    elif "first draft" in name:
        assert failed == {"INV-TX-SELF"}, failed
    else:
        assert not failed, failed
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
--- TUTORIAL-shaped fixture: 1/11 contract checks pass
  FAIL INV-DI      constructor injection only (no @Autowired fields) <- src/main/java/com/acme/order/OrderController.java:5, src/main/java/com/acme/order/OrderService.java:4, src/main/java/com/acme/order/OrderService.java:6
  FAIL INV-ID      no GenerationType.IDENTITY (it disables Hibernate JDBC insert batching) <- src/main/java/com/acme/order/Order.java:4
  FAIL INV-DDL     schema via Flyway (db/migration/V*__*.sql present) and ddl-auto is validate/none <- src/main/resources/application.yml:4, (no Flyway migration file)
  FAIL INV-OIV     spring.jpa.open-in-view is false <- (open-in-view not disabled)
  FAIL INV-TIMEOUT every outbound HTTP client sets connect and read timeouts <- src/main/java/com/acme/order/OrderService.java (client built without connect+read timeouts)
  FAIL INV-ERR     errors are RFC 9457 ProblemDetail; no catch-all Exception -> 500 <- src/main/java/com/acme/order/OrderController.java:12, (no ProblemDetail usage)
  FAIL INV-DTO     request/response DTOs are records <- src/main/java/com/acme/order/OrderRequest.java:1, src/main/java/com/acme/order/OrderResponse.java:1
  FAIL INV-TX-IO   no Kafka/HTTP call inside a transaction (@Transactional or TransactionTemplate) <- src/main/java/com/acme/order/OrderService.java:10
  ok   INV-TX-SELF no @Transactional method called from its own class (the proxy is bypassed)
  FAIL INV-OUTBOX  events published via a transactional outbox (outbox table in a migration) <- (no outbox table)
  FAIL INV-IDEMP   idempotency enforced by a unique index, not read-then-insert <- (no unique index on idempotency_key), src/main/java/com/acme/order/OrderService.java:12
--- PRODUCTION-shaped, first draft: 10/11 contract checks pass
  ok   INV-DI      constructor injection only (no @Autowired fields)
  ok   INV-ID      no GenerationType.IDENTITY (it disables Hibernate JDBC insert batching)
  ok   INV-DDL     schema via Flyway (db/migration/V*__*.sql present) and ddl-auto is validate/none
  ok   INV-OIV     spring.jpa.open-in-view is false
  ok   INV-TIMEOUT every outbound HTTP client sets connect and read timeouts
  ok   INV-ERR     errors are RFC 9457 ProblemDetail; no catch-all Exception -> 500
  ok   INV-DTO     request/response DTOs are records
  ok   INV-TX-IO   no Kafka/HTTP call inside a transaction (@Transactional or TransactionTemplate)
  FAIL INV-TX-SELF no @Transactional method called from its own class (the proxy is bypassed) <- src/main/java/com/acme/order/OrderService.java:10 calls insertWithOutbox()
  ok   INV-OUTBOX  events published via a transactional outbox (outbox table in a migration)
  ok   INV-IDEMP   idempotency enforced by a unique index, not read-then-insert
--- PRODUCTION-shaped, fixed: 11/11 contract checks pass
  ok   INV-DI      constructor injection only (no @Autowired fields)
  ok   INV-ID      no GenerationType.IDENTITY (it disables Hibernate JDBC insert batching)
  ok   INV-DDL     schema via Flyway (db/migration/V*__*.sql present) and ddl-auto is validate/none
  ok   INV-OIV     spring.jpa.open-in-view is false
  ok   INV-TIMEOUT every outbound HTTP client sets connect and read timeouts
  ok   INV-ERR     errors are RFC 9457 ProblemDetail; no catch-all Exception -> 500
  ok   INV-DTO     request/response DTOs are records
  ok   INV-TX-IO   no Kafka/HTTP call inside a transaction (@Transactional or TransactionTemplate)
  ok   INV-TX-SELF no @Transactional method called from its own class (the proxy is bypassed)
  ok   INV-OUTBOX  events published via a transactional outbox (outbox table in a migration)
  ok   INV-IDEMP   idempotency enforced by a unique index, not read-then-insert
ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Output "works" but review rejects it on fundamentals | Field injection, IDENTITY ids, `ddl-auto: update`, no timeouts | Decisions left to the prior | Spec with invariants and anti-goals | L1 lint, then L2 on outputs |
| F2 | Invariant stated, still violated | A rule in prose; no check named | An invariant without a check is a preference | Name the check; add it to CI (ArchUnit, L2-style rules) | L1 SC02 |
| F3 | Tests pass, behaviour wrong | Tests mirror the implementation; hard-coded expectations | Test-gaming, or tests written after the code by the same model | Edge cases with named tests up front; "tests verify, not define" block [doc] | Fresh-context test review (file 02) |
| F4 | Huge diff for a small change | New helpers, configs, refactors | Over-engineering at high effort | `<scope>` block; lower effort for small tasks | Diff-size budget in review |
| F5 | Conflicting rules followed inconsistently | The spec says X; CLAUDE.md says not-X | Conventions duplicated and drifted | Conventions only in CLAUDE.md; the spec references them | A CLAUDE.md linter (Folder 03) |
| F6 | `@Transactional` present, atomicity missing | A same-class call into a `@Transactional` method | Proxy self-invocation | `TransactionTemplate` or a separate bean | L2 INV-TX-SELF |
| F7 | Prompt cache misses on every feature | The spec is pasted with per-request edits at the top | The spec is not deterministic or not stable | Render from data (L1); keep it in `SPEC.md`, referenced by path | A byte-stability test (Folder 01 L10) |
| F8 | The model asks nothing and guesses | Missing context, but no open-questions slot | The prompt didn't invite questions | Phase 0: "list open questions before designing" | `SPEC.md` §9 must be empty before approval |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Specs are slower than just asking. Why bother on a strong model?"</b></summary>

**Staff answer.** A strong model makes good *choices*, but only among the options your prompt leaves open, and it can't know your invariants (tenant isolation, outbox policy, SLOs) unless you state them. The spec costs minutes. A wrong default discovered in review costs a full agent turn per comment, and one discovered in production costs an incident.

Measure it (§1.8): if spec prompts don't raise pass rate or cut review rounds on your backlog, shrink them. But measure on the hardest quartile, where the defaults hurt.
</details>

<details><summary><b>D2 · "Our spec has 45 MUST rules and the model still misses some."</b></summary>

**Staff answer.** Too many MUSTs dilute the critical ones (Folder 01 §1.4), and most of them are probably conventions. Move conventions to CLAUDE.md. Keep 5–8 task-critical invariants, each with a named check, and restate the top two in the final instruction.

Then stop relying on compliance alone. Make the checks run (ArchUnit, L2-style rules, tests), so a miss fails CI instead of slipping through review.
</details>

<details><summary><b>D3 · "Isn't telling the model 'no distributed locks' going to put the idea in its head?"</b></summary>

**Staff answer.** The idea is already in its head; it is one of the most common designs in training data. Naming it removes it from the search. What goes wrong is a *bare* prohibition. Pair it with the alternative ("enforce uniqueness with a UNIQUE index and handle the conflict"). Anthropic's Opus 5.5 guidance reports that naming specific patterns to avoid works where vague style instructions don't [doc].
</details>

<details><summary><b>D4 · "Why did your checker flag code that obviously has <code>@Transactional</code> on the insert?"</b></summary>

**Staff answer.** Because `create()` calls `insertWithOutbox()` on `this`. Spring's proxy-based transactions intercept only calls that go through the proxy, so the annotation does nothing on a self-call. The order and outbox inserts then commit independently: the dual write the outbox was meant to prevent.

Use `TransactionTemplate` for an explicit boundary, or move the method to another bean. This is exactly the kind of defect that reads as correct, and why mechanical checks precede human review.
</details>

<details><summary><b>D5 · "Where should the spec live: in the prompt, or in the repo?"</b></summary>

**Staff answer.** In the repo, as `SPEC.md`, reviewed in a PR. The prompt references it by path. That gives you versioning, review, one source for every agent and human, and a stable cacheable prefix. Inline specs are fine for one-off tasks; anything multi-session belongs on disk. That is also what survives context compaction (file 03).
</details>

<details><summary><b>D6 · "The model asks us twenty clarifying questions. How do we stop it?"</b></summary>

**Staff answer.** That is a Phase 0 working as intended, and the cheapest point to answer them. If it happens during implementation, the spec was incomplete. Fold the answers into `SPEC.md` and rerun.

For autonomous runs where nobody can answer, say so explicitly. Anthropic documents a prompt for unattended agents: proceed on reversible actions, and stop only when blocked on input only the user can provide [doc]. Have the agent list its assumptions in the output contract.
</details>

<details><summary><b>D7 · "How do I know a spec-first prompt actually helped?"</b></summary>

**Staff answer.** Use the §1.8 protocol. Run the same tasks with both prompts in fresh sessions at the same model and effort. Score each output on acceptance tests, L2 contract checks and review rounds, then compare $ per solved task with a hard-quartile breakdown. Keep the eval set in the repo and re-run it after each model release, because defaults change between models.
</details>

<details><summary><b>D8 · "Our generated tests pass, but they would also pass on the buggy version."</b></summary>

**Staff answer.** The tests were derived from the implementation, so they encode its behaviour, bugs included. Fixes:

- Write the edge cases (and ideally the tests) *before* the code, as part of the spec.
- Phrase test goals as "would fail on defect X".
- Review tests in a fresh context against the spec, not against the code.
- Mutation-test the critical paths. A test that survives the mutation "drop the unique index" doesn't test idempotency.
</details>

---

## 6. Invariants checklist

- [ ] Every non-trivial task starts from a spec with goal, context, pinned stack, targets, invariants (with checks), edge cases (with tests), anti-goals, scope, verification and output contract.
- [ ] The spec is rendered deterministically (L1) or kept in `SPEC.md`, referenced by path.
- [ ] Conventions live in CLAUDE.md; the spec carries only task-critical invariants (5–8).
- [ ] Every anti-goal names its alternative.
- [ ] The output contract demands a traceability matrix and no reasoning transcripts.
- [ ] Outputs pass mechanical checks (L2-style rules, ArchUnit, tests) before human review.
- [ ] Prompt effectiveness is measured on your own tasks, as $ per solved task with a hard-quartile breakdown.

---

## 7. References

- Anthropic, Prompting best practices ("Be clear and direct", "Add context", "Overeagerness", "Avoid focusing on passing tests and hardcoding"): <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Anthropic, Prompting Claude Opus 5.5 ("Frontend design defaults": naming patterns to avoid; "Unattended agentic runs"): <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>
- Spring Framework reference, declarative transactions with `@Transactional` (proxy mode and self-invocation): <https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html>
- RFC 9457, Problem Details for HTTP APIs: <https://www.rfc-editor.org/rfc/rfc9457>
- ArchUnit (architecture rules as unit tests): <https://www.archunit.org/>

Next: [02 · Few-shot, chain-of-verification and self-critique loops](02-few-shot-canonical-examples-chain-of-verification-and-self-critique-loops.md) · [03 · Compaction, hallucination and sycophancy](03-context-compaction-strategies-preventing-hallucination-and-sycophancy-traps.md) · [KB README](../README.md)
