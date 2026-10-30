# Zero to Production: Java 21 / Spring Boot Microservice Scaffolding Prompts

> **Folder 07 · File 1 of 4** · verified 2026-10-30. Versions are from Maven Central and the Spring Boot 4.1.2 BOM (`spring-boot-dependencies-4.1.2.pom`), not memory.
> **Templates:** T1 Phase 0 architecture RFC and spec generator, T2 hexagonal vertical-slice scaffolder.
> **Listing:** `prompt_template_check.py`, which lints and renders all seven Folder 07 templates and catches 11 classes of defect in a BAD control.

---

## 0. Orientation

Folders 01–06 explain *why* prompts work: attention, caching, XML grammar, specs, verification, hooks, MCP. This folder is the payoff: seven copy-paste templates for the work a Java backend team does repeatedly.

| # | Template | File | Use it for |
|---|---|---|---|
| T1 | Phase 0 RFC and spec generator | 01 (this file) | a new service, before any code |
| T2 | Hexagonal vertical-slice scaffolder | 01 | each use case, one at a time |
| T3 | Kafka with transactional outbox and idempotent consumer | 02 | replacing a dual write; adding events |
| T4 | Beam / Dataflow scaffolder and fusion/coder auditor | 03 | new pipelines; slow or failing jobs |
| T7 | PostgreSQL tuning from plan evidence | 03 | a slow query, with its `EXPLAIN ANALYZE` |
| T5 | Adversarial concurrency and load-test harness | 04 | code that shares mutable state |
| T6 | Testcontainers, ArchUnit and legacy refactoring | 04 | a legacy module you must change safely |

The brief asked for six; T7 is the SQL prompt the file 03 title implies.

Every template has the same anatomy, and a checker (L1) enforces it. Each one carries invariants that its verification section must check. The labs in files 02–04 prove that those invariants are the right ones by measuring what happens without them.

### 0.1 The twelve rules

1. **Data first, the ask last.** `<context>` holds every long input, and `<task>` is the final section. Anthropic reports up to 30% better responses with queries at the end of long, multi-document prompts. [doc: Folder 01]
2. **Variables are declared, typed and exemplified.**
   - `kind="data"` (pasted material) may appear only inside `<context>`.
   - `kind="param"` (short choices) may appear anywhere.
   - Every variable has an example, so the template renders and can be tested. [L1 PT04, PT05, PT10]
3. **Instructions are actions, not a reasoning script.** "Write the domain first" is a step. "Think step by step" is a script; with thinking on, the model plans better than your script does. [doc: Folder 01 · L1 PT11]
4. **Invariants have IDs, and every ID has a check.** An invariant nobody verifies is a wish. [Folder 02 · L1 PT08]
5. **Anti-goals are concrete "No …" sentences**, at least three: the defaults you have seen go wrong. [L1 PT09]
6. **The output contract names files and a report.** "Write good code" is not a contract; `src/main/java/…/application/PlaceOrderUseCase.java` is. [L1 PT06]
7. **Verification contains commands.** Claude Code's best practices put it first: give Claude a way to verify its work. [doc · L1 PT07]
8. **No shouting.** `CRITICAL`, `MUST` and `NEVER` in capitals make current models over-trigger. Plain, specific sentences work better. [doc: Folder 01 · L1 PT11]
9. **Pin the platform in the template, from the BOM.**
   - Boot 4.1.2 manages Spring Kafka 4.1.2, kafka-clients 4.2.2, Testcontainers 2.0.5, Flyway 12.4.0, jOOQ 3.21.9, HikariCP 7.0.2, JUnit 6.0.3 and Jackson 3.1.7.
   - The templates say "managed versions", so Claude doesn't pin stale ones. [measured: BOM]
10. **Phase 0 asks before it writes.** T1 may stop with at most N blocking questions. A design built on a guessed NFR is worse than no design. [Folder 02 + doc: best practices, "let Claude interview you"]
11. **One slice per T2 run, in its own worktree.** A small diff can be reviewed; "scaffold the whole service" can't. [Folder 03]
12. **Templates are code.** Keep them in the repo, lint them in CI (L1), version them, and review changes. A template change changes every future output.

---

## 1. First principles

### 1.1 Why this anatomy [Folders 01–02]

| Section | What it does | Physics behind it |
|---|---|---|
| `<variables>` | Declares inputs, with kinds and examples | Makes the template a function: testable, renderable, lintable |
| `<context>` | All long material, each piece in its own tag | Long content first. Unambiguous tag boundaries (Folder 01 L2: XML 100% vs Markdown fences 45% boundary recovery) |
| `<role>` (optional) | Accountability, not flattery | "Expert" adds nothing; "accountable for every number" changes behaviour |
| `<instructions>` | Ordered actions | Actions constrain the work; reasoning scripts constrain the thinking (bad with thinking on) |
| `<invariants>` | Numbered properties the output must have | Spec-driven prompting (Folder 02 L1): checkable, and checked |
| `<anti_goals>` | The defaults to avoid | The prior fills every unstated decision. Anti-goals state the ones you've seen go wrong |
| `<output_contract>` | Files and a report | Turns "done" into something a reviewer and a hook can check |
| `<verification>` | Commands plus per-invariant checks | Closes the loop: Claude runs them, and a Stop hook (Folder 05) can too |
| `<task>` | One sentence, last | The question at the end gets the most reliable attention on long inputs |

### 1.2 Filling the data variables in Claude Code [doc + inference]

You rarely paste. In Claude Code:
- **`@SPEC.md` or `@src/main/resources/db/migration/`** in the message pulls a file or directory listing into context.
- **"Read `docs/rfc/0001-order-service.md` first" inside `<context>`** lets Claude read the file itself.
- **The MCP server from Folder 06** (`describe_table`, `architecture_rules`) answers the schema and rules variables on demand.

Write the template's `<context>` with those references in place of the examples. The checker's rule still holds: data goes in `<context>`, nowhere else.

### 1.3 Model, effort and mode per template [inference from Folder 01 routing]

| Template | Model | Effort | Mode | Why |
|---|---|---|---|---|
| T1 Phase 0 | Opus 5.5 | high | plan mode (Shift+Tab), then accept | Design errors are the most expensive kind; the output is short |
| T2 slice | Sonnet 5.5 or Opus 5.5 | medium | a worktree per slice, normal mode with hooks | Well-specified implementation work; the build is the verifier |
| T3 outbox | Opus 5.5 | high | normal, then a reviewer subagent | Subtle failure semantics |
| T4 Beam audit | Opus 5.5 | high | normal | Reasoning over job evidence |
| T5 concurrency | Opus 5.5 | high | normal | Interleavings are reasoning-heavy |
| T6 legacy | Opus 5.5 to plan, Sonnet 5.5 for steps | medium | many small sessions | Long, incremental work; compaction-friendly (Folder 02) |
| T7 SQL | Opus 5.5 | medium | normal | Evidence is pre-digested (file 03 L3) |

### 1.4 What T1 forces that a "design a microservice" prompt doesn't

- **A real alternative.** One option must be a module in the existing system (anti-goal 3). Many "microservices" should have been a package.
- **Numbers that trace** (INV-SPEC-5). Every throughput or latency figure cites the context or a calculation. Otherwise it is labelled ASSUMPTION or OPEN-Qn.
- **Idempotency and concurrency per operation** (INV-SPEC-2), before code exists. These are the decisions that cause the outages, and T3 and T5 build on them.
- **CLAUDE.md as an output** (INV-SPEC-6), under 150 lines (Folder 03): the new repo starts with the memory its future sessions need.

### 1.5 What T2 forces that a "scaffold a Spring Boot service" prompt doesn't

- **Order of creation:** domain → application → adapters → configuration → tests. The domain is written without framework imports, then *fenced* by ArchUnit (INV-HEX-1; file 04 L2 runs these rules on real bytecode).
- **The transaction boundary in one place** (INV-HEX-2), including Folder 02's `@Transactional` self-invocation trap.
- **Virtual threads, done right.**
  - With `spring.threads.virtual.enabled=true`, thread count stops being the limit and the Hikari pool becomes it (INV-HEX-4). Size it explicitly against the database's connection budget.
  - On a JDK 21 runtime, `synchronized` around blocking I/O pins carrier threads. JDK 24+ (JEP 491) removed that pinning for `synchronized`. Hence an anti-goal, not a ban.
- **Idempotent POSTs** (INV-HEX-7), with a test that sends the request twice.

---

## 2. Practice

### 2.1 T1: Phase 0 architecture RFC and spec generator

```xml
<!-- t1_phase0_rfc_spec.xml - Phase 0: architecture RFC, SPEC.md, schema, API contract and CLAUDE.md before any code -->
<prompt id="T1" title="Phase 0 architecture RFC and spec generator">
  <variables>
    <var name="service_name" kind="param" example="order-service">kebab-case name of the new service</var>
    <var name="problem_statement" kind="data" example="Customers place orders that reserve stock and take payment; today a nightly batch double-books stock.">the business problem in the product owner's words</var>
    <var name="nfrs" kind="data" example="p99 under 150 ms at 2,000 rps; 99.95% monthly; RPO 0, RTO 15 min; EU data residency">non-functional requirements as given</var>
    <var name="platform_constraints" kind="data" example="Java 21 (runtime JDK 25), Spring Boot 4.1.2, PostgreSQL 17, Kafka 4.2, Kubernetes, OpenTelemetry">technology the team has already chosen</var>
    <var name="existing_system" kind="data" example="Monolith 'shop-core' owns customers and catalog; exposes REST; publishes nothing.">what exists today and who owns it</var>
    <var name="max_questions" kind="param" example="6">how many blocking questions Claude may ask before writing</var>
  </variables>
  <context>
    <problem>{{problem_statement}}</problem>
    <nfrs>{{nfrs}}</nfrs>
    <platform>{{platform_constraints}}</platform>
    <existing_system>{{existing_system}}</existing_system>
  </context>
  <role>You are the staff engineer writing the design that a review board will approve or reject. You are accountable for every number and every assumption in it.</role>
  <instructions>
    <step n="1">Before writing anything, list what you would need to know and cannot infer. If any item blocks a decision, output only a questions block of at most {{max_questions}} numbered questions and stop. Otherwise continue and record non-blocking unknowns as OPEN-Qn.</step>
    <step n="2">Write the RFC: context, goals, non-goals, at least two real options (one of them a module inside the existing system), the decision with its trade-offs, failure modes and their blast radius, rollout and rollback, and the run cost.</step>
    <step n="3">Write SPEC.md: invariants with IDs, the aggregate's state machine (every transition with its command or event), the API contract, the domain events, the error model (RFC 9457 problem details), idempotency rules, and the SLOs with their SLIs.</step>
    <step n="4">Write the first Flyway migration and the OpenAPI 3.1 document so they agree with SPEC.md field for field.</step>
    <step n="5">Write the new repository's CLAUDE.md: build and test commands, architecture rules, and how to verify a change. Keep it short enough to load on every turn.</step>
    <step n="6">Run the checks in the verification section and report each result.</step>
  </instructions>
  <invariants>
    <inv id="INV-SPEC-1">Every state transition names its trigger, its guard and the event it emits; no transition is implied.</inv>
    <inv id="INV-SPEC-2">Every mutating operation states its idempotency rule (key, scope, retention) and its concurrency control (version column or lock).</inv>
    <inv id="INV-SPEC-3">Every table has a primary key; every foreign key has an index in the same migration; every money column is numeric with a currency column.</inv>
    <inv id="INV-SPEC-4">Every NFR maps to a measurable SLI and to the test or dashboard that measures it.</inv>
    <inv id="INV-SPEC-5">Nothing is invented: each assumption is labelled ASSUMPTION, each unknown OPEN-Qn, and every number traces to the context or to a stated calculation.</inv>
    <inv id="INV-SPEC-6">CLAUDE.md is under 150 lines and contains only what applies to every task in the repository.</inv>
  </invariants>
  <anti_goals>
    <no>No application code beyond the migration and the OpenAPI document.</no>
    <no>No technology outside the platform constraints unless it is listed as a proposed addition with its cost and an alternative.</no>
    <no>No microservice by default: the RFC must say why a module in the existing system is not enough, or choose it.</no>
    <no>No generic boilerplate sections; a section with nothing specific to say is omitted.</no>
  </anti_goals>
  <output_contract>
    <file path="docs/rfc/0001-{{service_name}}.md">RFC, sections as in step 2</file>
    <file path="SPEC.md">specification, sections as in step 3, invariants as INV-n</file>
    <file path="src/main/resources/db/migration/V1__init.sql">schema</file>
    <file path="api/openapi.yaml">OpenAPI 3.1 contract</file>
    <file path="CLAUDE.md">repository memory for Claude Code</file>
    <report>A table: each check from the verification section, its command or method, and its result. Then the OPEN-Q list.</report>
  </output_contract>
  <verification>
    <cmd>npx @redocly/cli@2.72.1 lint api/openapi.yaml</cmd>
    <cmd>wc -l CLAUDE.md</cmd>
    <check ref="INV-SPEC-1">For each state in the state machine, list its outgoing transitions; a state with none must be marked terminal.</check>
    <check ref="INV-SPEC-2">For each POST/PUT/PATCH/DELETE in openapi.yaml, point to its idempotency and concurrency rule in SPEC.md.</check>
    <check ref="INV-SPEC-3">For each FOREIGN KEY in V1__init.sql, name the CREATE INDEX that covers it.</check>
    <check ref="INV-SPEC-4">Print the NFR-to-SLI table; an NFR without an SLI fails the check.</check>
    <check ref="INV-SPEC-5">grep the RFC and SPEC.md for numbers; each must cite the context or a calculation.</check>
    <check ref="INV-SPEC-6">The wc -l result is under 150.</check>
  </verification>
  <task>Produce the Phase 0 design for {{service_name}} following the instructions, honouring every invariant and anti-goal, in the files of the output contract.</task>
</prompt>
```

Run it in plan mode with Opus 5.5. If Claude returns questions, answer them in the same session and say "continue". Commit the five files on a branch; the RFC review happens on that PR, before any code.

### 2.2 T2: Hexagonal vertical-slice scaffolder

```xml
<!-- t2_vertical_slice_scaffolder.xml - one hexagonal vertical slice (domain, use case, ports, adapters, migration, tests) on Boot 4.1 / Java 21 -->
<prompt id="T2" title="Hexagonal vertical slice scaffolder">
  <variables>
    <var name="base_package" kind="param" example="com.acme.orders">root Java package</var>
    <var name="base_path" kind="param" example="com/acme/orders">the same package as a source path</var>
    <var name="slice" kind="param" example="PlaceOrder">use case name, PascalCase</var>
    <var name="persistence" kind="param" example="jOOQ">jOOQ or Spring Data JPA</var>
    <var name="spec_excerpt" kind="data" example="SPEC.md 3.2 PlaceOrder: POST /orders with Idempotency-Key; NEW to RESERVED on stock reserved; emits OrderPlaced; INV-3 amount positive.">the SPEC.md section for this slice, verbatim</var>
    <var name="repo_tree" kind="data" example="src/main/java/com/acme/orders/{domain,application,adapter}/... (output of tree -d src)">current layout, so new code lands where it belongs</var>
    <var name="existing_conventions" kind="data" example="Records, no Lombok; constructor injection; problem+json errors; Spotless palantir format.">the parts of CLAUDE.md and .claude/rules that apply</var>
  </variables>
  <context>
    <spec>{{spec_excerpt}}</spec>
    <layout>{{repo_tree}}</layout>
    <conventions>{{existing_conventions}}</conventions>
    <platform>Java 21 source level on a JDK 25 runtime; Spring Boot 4.1.2 with its managed versions (Spring Framework 7, HikariCP 7.0.2, jOOQ 3.21.9, Flyway 12.4.0, Testcontainers 2.0.5, JUnit 6.0.3); Resilience4j 2.4.0 (resilience4j-spring-boot4); OpenTelemetry Spring Boot starter 2.33.1.</platform>
  </context>
  <instructions>
    <step n="1">Restate the slice contract from the spec in at most ten lines: inputs, outputs, state change, events, errors, idempotency. If the spec is silent on any of these, stop and ask.</step>
    <step n="2">Write the domain first: records and sealed result types in {{base_package}}.domain, with the invariants as constructor or method checks and unit tests beside them. No framework imports.</step>
    <step n="3">Write the application layer: the {{slice}} use case in {{base_package}}.application, an inbound port it implements, and the outbound ports it needs. The use case owns the transaction boundary.</step>
    <step n="4">Write the adapters: a REST controller that maps to problem details and honours Idempotency-Key; a {{persistence}} repository implementing the persistence port; an outbox writer for the domain events; each outbound HTTP client wrapped in a Resilience4j time limiter and circuit breaker.</step>
    <step n="5">Write the next Flyway migration (never edit an applied one) and the configuration: virtual threads on, an explicit Hikari pool size with the sizing arithmetic in a comment, OpenTelemetry resource attributes.</step>
    <step n="6">Write the tests: domain unit tests, a web slice test, a Testcontainers PostgreSQL integration test using @ServiceConnection, and an ArchUnit test for the layer rules.</step>
    <step n="7">Run the verification commands, fix until they pass, and report.</step>
  </instructions>
  <invariants>
    <inv id="INV-HEX-1">Domain classes import nothing from org.springframework, jakarta.persistence, org.jooq or the adapter packages.</inv>
    <inv id="INV-HEX-2">@Transactional appears only on application-layer public methods called from outside the bean; no self-invocation, no transactions in controllers.</inv>
    <inv id="INV-HEX-3">Every outbound port has exactly one production adapter and one in-memory test double.</inv>
    <inv id="INV-HEX-4">The Hikari maximum pool size is set explicitly; with virtual threads the pool, not the thread count, limits database concurrency, so pool size times replica count stays below the database's connection budget.</inv>
    <inv id="INV-HEX-5">Every outbound network call has a timeout and a circuit breaker; retries only on idempotent calls.</inv>
    <inv id="INV-HEX-6">Domain events are written to the outbox in the same transaction as the state change, with the W3C traceparent in the event headers.</inv>
    <inv id="INV-HEX-7">A repeated POST with the same Idempotency-Key returns the original result and changes nothing.</inv>
  </invariants>
  <anti_goals>
    <no>No Lombok, field injection or service locators.</no>
    <no>No H2 or embedded databases in persistence tests.</no>
    <no>No new dependency beyond the platform list without asking first.</no>
    <no>No catch-all exception handlers that log and continue.</no>
    <no>No synchronized blocks around blocking I/O (on a JDK 21 runtime they pin virtual threads); use ReentrantLock.</no>
  </anti_goals>
  <output_contract>
    <file path="src/main/java/{{base_path}}/domain/">aggregate, value objects, domain events, sealed results</file>
    <file path="src/main/java/{{base_path}}/application/">{{slice}}UseCase, ports.in, ports.out</file>
    <file path="src/main/java/{{base_path}}/adapter/">in.web, out.persistence, out.messaging</file>
    <file path="src/main/resources/db/migration/">V(n+1)__{{slice}}.sql</file>
    <file path="src/test/java/{{base_path}}/">domain tests, web slice test, Testcontainers IT, ArchitectureTest</file>
    <report>The commands you ran with their pass/fail summary lines, each invariant with the file and test that enforces it, and any deviation from the spec with the reason.</report>
  </output_contract>
  <verification>
    <cmd>./mvnw -q spotless:check</cmd>
    <cmd>./mvnw -q verify</cmd>
    <cmd>./mvnw -q test -Dtest=ArchitectureTest</cmd>
    <check ref="INV-HEX-1">ArchitectureTest: domain must not depend on Spring, JPA, jOOQ or adapter packages.</check>
    <check ref="INV-HEX-2">ArchitectureTest: @Transactional methods live only in application classes; grep shows no this-calls to them.</check>
    <check ref="INV-HEX-3">List each outbound port with its adapter and its test double.</check>
    <check ref="INV-HEX-4">Quote the pool-size line and its arithmetic.</check>
    <check ref="INV-HEX-5">List each outbound client with its Resilience4j instance names and timeouts.</check>
    <check ref="INV-HEX-6">The Testcontainers IT asserts the outbox row and its traceparent exist after the use case commits, and none after a rollback.</check>
    <check ref="INV-HEX-7">The web or integration test sends the same POST twice and asserts one state change and identical responses.</check>
  </verification>
  <task>Implement the {{slice}} vertical slice end to end as specified, satisfying every invariant, then report against the output contract.</task>
</prompt>
```

Run one slice per worktree (`claude --worktree`), with Folder 05's hooks active. `format_java` runs Spotless after each edit, and `verify_build` stops Claude from declaring done on a red build. Then run `/code-review` before the PR. Folder 04's `/new-slice` skill is T2 packaged with a next-migration-number script.

### 2.3 Turning a template into a skill

```yaml
# .claude/skills/new-slice/SKILL.md (frontmatter; body = the T2 template with $ARGUMENTS for the slice name)
---
name: new-slice
description: Scaffold one hexagonal vertical slice (domain, use case, ports, adapters, migration, tests) from a SPEC.md section. Use when asked to add a use case or endpoint.
disable-model-invocation: true
---
```

`disable-model-invocation: true` keeps a scaffolder from firing on its own; you invoke it with `/new-slice PlaceOrder`. Folder 04 file 01 has the linted version.

### 2.4 Lint templates in CI

```bash
python prompt_template_check.py .claude/prompts      # exit 1 on any finding; run on every PR that touches a template
```

---

## 3. Verified listing

### L1 · `prompt_template_check.py`

**What it shows.** Twelve checks:
- **PT01:** a header and the root element.
- **PT02:** a skeleton-first parse of the known tags, so generics like `List<String>` inside data can't break it (Folder 01).
- **PT03:** context before instructions, task last.
- **PT04:** every placeholder declared and used.
- **PT05:** examples render.
- **PT06:** the output contract names files.
- **PT07:** verification commands.
- **PT08:** every invariant has a check, and every check refers to an invariant.
- **PT09:** at least three concrete anti-goals.
- **PT10:** data variables only in `<context>`.
- **PT11:** no reasoning scripts or shouting.
- **PT12:** a size budget.

All seven Folder 07 templates are checked and rendered with their examples. A BAD control template, written the way prompts usually are, triggers 11 of the 12 rules (all except PT12).

**What it does not show.** That a template produces good output. Only running it on your codebase shows that, and Folder 02's eval method is how to measure it. The checker makes a template *well-formed and testable*, which is the precondition.

Run: `python prompt_template_check.py [dir]`.

```python
"""prompt_template_check.py - lint and render XML prompt templates (default: the t*.xml files beside this script).
Twelve checks encode this KB's prompt rules: a known skeleton, balanced and in order (data before instructions, the task
last); every placeholder declared and used; data variables only inside <context>; examples that render; an output
contract naming files; verification with commands; every invariant covered by a check; concrete anti-goals; no reasoning
scripts or shouting; a size budget. Each template is then rendered with its examples. A BAD template is the control.
Usage: python prompt_template_check.py [dir]   (exit 1 if any template has findings)
"""
import pathlib
import re
import sys

SECTIONS = ["variables", "context", "role", "instructions", "invariants", "anti_goals", "output_contract", "verification",
            "task"]
REQUIRED = [s for s in SECTIONS if s != "role"]
KNOWN = set(SECTIONS) | {"prompt", "var", "step", "inv", "no", "file", "report", "cmd", "check"}
TAG = re.compile(r"<(/?)([a-z_]+)((?:\s[^<>]*?)?)(/?)>")
PLACEHOLDER = re.compile(r"\{\{(\w+)\}\}")
SHOUT = re.compile(r"\b(CRITICAL|IMPORTANT|MUST|NEVER|ALWAYS)\b")
SCRIPT = re.compile(r"(?i)think step[- ]by[- ]step|let'?s think|take a deep breath")
TOKEN_BUDGET = 2_500            # rendered size, chars/4; long data belongs in the variables, not in the template


def skeleton(text):
    """Skeleton-first parse (Folder 01): only known tag names count, so List<String> inside data cannot break it."""
    stack, top, problems = [], [], []
    for m in TAG.finditer(text):
        close, name, _, selfclose = m.groups()
        if name not in KNOWN or selfclose:
            continue
        if not close:
            if [s for s, _ in stack] == ["prompt"]:
                top.append(name)
            stack.append((name, m.start()))
        elif stack and stack[-1][0] == name:
            stack.pop()
        else:
            problems.append(f"unbalanced </{name}>")
    return top, problems + [f"unclosed <{name}>" for name, _ in stack]


def body(text, section):
    m = re.search(rf"<{section}\b[^>]*>(.*?)</{section}>", text, re.S)
    return m.group(1) if m else ""


def check(name, text):
    f = []
    header = re.match(r"<!-- ([\w-]+\.xml) - (.+?) -->\n", text)
    if not header or header.group(1) != name:
        f.append(("PT01", "first line must be '<!-- <file name> - <purpose> -->'"))
    if not re.search(r'<prompt id="T\d+" title="[^"]+">', text):
        f.append(("PT01", 'root element must be <prompt id="Tn" title="...">'))
    top, problems = skeleton(text)
    f += [("PT02", p) for p in problems]
    f += [("PT02", f"<{s}> appears {top.count(s)} times, need exactly 1") for s in REQUIRED if top.count(s) != 1]
    if "context" in top and "instructions" in top and top.index("context") > top.index("instructions"):
        f.append(("PT03", "<context> (the data) must come before <instructions>: long material first"))
    if top and top[-1] != "task":
        f.append(("PT03", "<task> must be the last section: the ask goes at the end"))
    variables = {m.group(1): (m.group(2), m.group(3))
                 for m in re.finditer(r'<var name="(\w+)" kind="(param|data)" example="([^"]*)">', text)}
    declared = re.findall(r'<var name="(\w+)"', text)
    f += [("PT04", f"variable '{v}' needs kind=\"param|data\" and example=\"...\"") for v in declared if v not in variables]
    rest = re.sub(r"<variables>.*?</variables>", "", text, flags=re.S)
    used = set(PLACEHOLDER.findall(rest))
    f += [("PT04", f"{{{{{u}}}}} is used but not declared") for u in sorted(used - set(declared))]
    f += [("PT04", f"'{d}' is declared but never used") for d in sorted(set(declared) - used)]
    f += [("PT05", f"'{v}' has an empty example") for v, (_, ex) in variables.items() if not ex.strip()]
    context = body(text, "context")
    outside_context = re.sub(r"<context\b[^>]*>.*?</context>", "", rest, count=1, flags=re.S)
    for v, (kind, _) in variables.items():
        token = f"{{{{{v}}}}}"
        if kind == "data" and (token in outside_context or token not in context):
            f.append(("PT10", f"data variable '{v}' must appear inside <context> and nowhere else"))
    if not re.search(r'<file path="[^"]+">', body(text, "output_contract")):
        f.append(("PT06", "the output contract names no <file path=...>"))
    if not re.findall(r"<cmd>.+?</cmd>", body(text, "verification"), re.S):
        f.append(("PT07", "verification has no <cmd>"))
    invariants = re.findall(r'<inv id="(INV-[A-Z]+-\d+)">', text)
    refs = re.findall(r'<check ref="(INV-[A-Z]+-\d+)">', text)
    f += [("PT08", f"{i} has no <check ref> in verification") for i in invariants if i not in refs]
    f += [("PT08", f"<check ref=\"{r}\"> points at no invariant") for r in refs if r not in invariants]
    anti = re.findall(r"<no>(.*?)</no>", body(text, "anti_goals"), re.S)
    if len(anti) < 3:
        f.append(("PT09", f"{len(anti)} anti-goal(s); need at least 3 concrete ones"))
    f += [("PT09", f"anti-goal '{a.strip()[:30]}' is not a concrete 'No ...'") for a in anti if not re.match(r"\s*No\b", a)]
    if SCRIPT.search(text):
        f.append(("PT11", f"reasoning script '{SCRIPT.search(text).group(0)}': with thinking on, ask for results, not steps"))
    shouts = SHOUT.findall(rest)
    if len(shouts) >= 3:
        f.append(("PT11", f"{len(shouts)} shouted words ({', '.join(sorted(set(shouts)))}): current models over-trigger on them"))
    rendered = PLACEHOLDER.sub(lambda m: variables.get(m.group(1), ("", m.group(0)))[1], rest)
    if "{{" in rendered:
        f.append(("PT05", "rendering with the examples leaves unfilled placeholders"))
    tokens = len(rendered) // 4
    if tokens > TOKEN_BUDGET:
        f.append(("PT12", f"rendered size ~{tokens} tokens exceeds {TOKEN_BUDGET}"))
    stats = (top, variables, invariants, re.findall(r"<cmd>", text), anti, tokens)
    return f, stats


BAD = """<!-- review_prompt.xml - x -->
<prompt id="T9" title="bad">
<variables><var name="code" kind="data" example="class A {}">code</var><var name="unused" kind="param" example="1">y</var></variables>
<task>IMPORTANT: Review {{code}} and think step by step. You MUST be CRITICAL and NEVER miss a bug.</task>
<instructions><step n="1">Also read {{ticket}}.</inv></step></instructions>
<context>{{code}}</context>
<invariants><inv id="INV-X-1">No bugs.</inv></invariants>
<anti_goals><no>Be careful.</no></anti_goals>
<output_contract><report>Findings.</report></output_contract>
<verification><check ref="INV-X-2">Looks good.</check></verification>
</prompt>
"""


def main():
    folder = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent
    total, orders = 0, set()
    for path in sorted(folder.glob("t*.xml")):
        findings, (top, variables, invariants, cmds, anti, tokens) = check(path.name, path.read_text(encoding="utf-8"))
        total += len(findings)
        orders.add(" > ".join(s for s in top if s != "role"))
        data = sum(kind == "data" for kind, _ in variables.values())
        print(f"{path.name:<38} {len(top)} sections, {len(variables)} vars ({data} data), {len(invariants)} invariants "
              f"all checked, {len(cmds)} cmd(s), {len(anti)} anti-goals, ~{tokens:,} tokens rendered: {len(findings)} findings")
        for rule, msg in findings:
            print(f"    {rule} {msg}")
    print(f"section orders in use (role omitted): {len(orders)}: {' | '.join(sorted(orders))}")
    findings, _ = check("bad_template.xml", BAD)
    print(f"\nBAD control template: {len(findings)} findings")
    for rule, msg in findings:
        print(f"    {rule} {msg}")
    print(f"\nrules triggered by BAD: {', '.join(sorted({r for r, _ in findings}))}")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

**Output (verified):**

```text
t1_phase0_rfc_spec.xml                 9 sections, 6 vars (4 data), 6 invariants all checked, 2 cmd(s), 4 anti-goals, ~1,250 tokens rendered: 0 findings
t2_vertical_slice_scaffolder.xml       8 sections, 7 vars (3 data), 7 invariants all checked, 3 cmd(s), 5 anti-goals, ~1,463 tokens rendered: 0 findings
t3_kafka_outbox_idempotent.xml         8 sections, 7 vars (3 data), 7 invariants all checked, 1 cmd(s), 4 anti-goals, ~1,443 tokens rendered: 0 findings
t4_beam_pipeline_auditor.xml           8 sections, 5 vars (4 data), 6 invariants all checked, 2 cmd(s), 4 anti-goals, ~1,284 tokens rendered: 0 findings
t5_adversarial_concurrency.xml         8 sections, 4 vars (2 data), 5 invariants all checked, 2 cmd(s), 3 anti-goals, ~1,042 tokens rendered: 0 findings
t6_testcontainers_archunit_legacy.xml  8 sections, 4 vars (3 data), 5 invariants all checked, 2 cmd(s), 3 anti-goals, ~948 tokens rendered: 0 findings
t7_sql_explain_tuning.xml              8 sections, 4 vars (3 data), 5 invariants all checked, 1 cmd(s), 3 anti-goals, ~987 tokens rendered: 0 findings
section orders in use (role omitted): 1: variables > context > instructions > invariants > anti_goals > output_contract > verification > task

BAD control template: 16 findings
    PT01 first line must be '<!-- <file name> - <purpose> -->'
    PT02 unbalanced </inv>
    PT03 <context> (the data) must come before <instructions>: long material first
    PT03 <task> must be the last section: the ask goes at the end
    PT04 {{ticket}} is used but not declared
    PT04 'unused' is declared but never used
    PT10 data variable 'code' must appear inside <context> and nowhere else
    PT06 the output contract names no <file path=...>
    PT07 verification has no <cmd>
    PT08 INV-X-1 has no <check ref> in verification
    PT08 <check ref="INV-X-2"> points at no invariant
    PT09 1 anti-goal(s); need at least 3 concrete ones
    PT09 anti-goal 'Be careful.' is not a concrete 'No ...'
    PT11 reasoning script 'think step by step': with thinking on, ask for results, not steps
    PT11 4 shouted words (CRITICAL, IMPORTANT, MUST, NEVER): current models over-trigger on them
    PT05 rendering with the examples leaves unfilled placeholders

rules triggered by BAD: PT01, PT02, PT03, PT04, PT05, PT06, PT07, PT08, PT09, PT10, PT11
```

Two things to read from it:
- Every template renders to roughly 950–1,500 tokens *before* your data. The structure is cheap; your SPEC excerpt and source code are the bulk.
- The BAD control is not a strawman. Task-first prompts, `{{placeholders}}` nobody declared, "think step by step", `CRITICAL` in capitals, and no verification are the most common shape of a team's first prompt library.

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Claude scaffolds the whole service in one go | No slice boundary, no "stop and ask" | T2 per slice; step 1 restates the contract and stops on gaps |
| F2 | The design has invented throughput numbers | No traceability rule | INV-SPEC-5: ASSUMPTION / OPEN-Qn labels |
| F3 | The domain imports Spring or JPA | The layer rule existed only in prose | INV-HEX-1 plus an ArchUnit test (file 04 L2) |
| F4 | DB connections exhausted after enabling virtual threads | Default pool; thousands of concurrent requests | INV-HEX-4: explicit pool size against the database budget |
| F5 | Template edits silently break other teams' runs | Templates not versioned or linted | Templates in the repo; L1 in CI |
| F6 | Output ignores half the context | Context pasted after the question, or data scattered through instructions | Data in `<context>` first, task last (PT03, PT10) |
| F7 | Claude over-applies a rule everywhere | Shouted absolute language | Plain, specific sentences (PT11) |
| F8 | Claude pins old versions | The template didn't name the BOM | The `<platform>` line with managed versions |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Why not one big prompt that does design and scaffolding together?"</b></summary>

**Staff answer.** They have different verifiers and different costs of error.
- **Design (T1)** is verified by humans in review and is cheap to change.
- **Scaffolding (T2)** is verified by the build and expensive to unwind once merged.

Merging them means the design is never reviewed on its own; the code arrives with it as a fait accompli. Separate prompts, separate PRs, separate sessions also give clean context for each (Folder 02, compaction).
</details>

<details><summary><b>D2 · "The checker passes. Does that mean the template is good?"</b></summary>

**Staff answer.** It means the template is *well-formed*: complete, consistent, testable, and free of known anti-patterns. Whether it is *good* is an empirical question.
1. Run it on three real slices.
2. Score each output against its own invariants: the verification section is the rubric.
3. Keep that as a regression set (Folder 02, evals).

When you change the template, rerun the set.
</details>

<details><summary><b>D3 · "Our seniors find the templates too long. Will they use them?"</b></summary>

**Staff answer.** Package them so nobody pastes.
- Make each one a skill (`/new-slice PlaceOrder`).
- Let `@file` references fill the context.
- Let hooks enforce the verification.

The template's length is paid once, by its author. Its users type one line. Measure adoption by how many PRs carry the output-contract report.
</details>

---

## 6. Checklist

- [ ] Templates live in the repo (`.claude/prompts/` or skills) and pass `prompt_template_check.py` in CI.
- [ ] Each template names the platform from the BOM, not from memory.
- [ ] T1 runs in plan mode on Opus; its five files are reviewed before any T2 run.
- [ ] T2 runs one slice per worktree with hooks active, followed by `/code-review`.
- [ ] Each invariant's check is either a command Claude runs or a test it writes.

---

## 7. References

- Prompting best practices (long context, XML, examples): <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Claude Code best practices (verification first, interview, plan mode): <https://code.claude.com/docs/en/best-practices>
- Spring Boot 4.1.2 dependency versions (the BOM): <https://repo1.maven.org/maven2/org/springframework/boot/spring-boot-dependencies/4.1.2/>
- JEP 491, synchronizing virtual threads without pinning: <https://openjdk.org/jeps/491>
- Folder 02 spec-driven prompting: [01 · Spec-driven prompting](../02-Advanced-Prompt-Engineering-Patterns-and-Anti-Patterns/01-spec-driven-prompting-invariants-anti-goals-and-verification-contracts.md)

Next: [02 · Kafka outbox, saga and Resilience4j](02-kafka-outbox-saga-and-resilience4j-implementation-prompt-templates.md) · [KB README](../README.md)
