# P20 · Rule Engine and JSON Workflow Orchestrator: Validated DAGs, Parallel Steps, Retries, Sagas and Resumable Runs

> **Folder 06 · Problem 20 of 20.** A workflow engine turns a JSON document into a validated DAG, then into a **run** with five properties:
> 1. ready steps execute in parallel;
> 2. rules skip steps;
> 3. retries back off;
> 4. a failure cancels what can no longer run and **compensates** what already ran;
> 5. a crash resumes from a **journal** without redoing finished work.
>
> The concurrency core is one line: **the last parent to finish schedules the child**, through an atomic in-degree counter. The common alternative double-schedules joins. (The executor mechanics themselves are [Folder 07 file 03](../07-Classic-Multithreading-Synchronization-Bar-Raisers/03-parallel-dag-task-executor-with-completablefuture-and-virtual-threads.md).)
>
> **Listing pair P20:** `WorkflowEngine.java` / `workflow_engine.cpp`. Sections 1, 3 and 4 are deterministic and **byte-identical in Java, GCC and Clang**; sections 2 and 5 show one measured run.

---

## 1. Problem and scope

**Definition:** JSON with `steps[]`, each having:
- `id`, `after` (dependencies), `action`;
- an optional `when` (conditions on the run context), `retry` (max attempts, base backoff) and `compensate`.

**Validation:** malformed JSON, duplicate ids, unknown dependencies, and **cycles reported as a path**.

**Run:**
- parallel execution of ready steps;
- skipped steps count as satisfied;
- exponential backoff;
- fail-fast cancellation;
- saga compensation in reverse topological order;
- crash and resume.

**Out of scope:**
- An expression language beyond field/op/value conditions (a full one would be the Specification DSL of [02.2](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md)).
- Timers and human approval steps (§7).
- Distributed workers.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| JSON | `Json` recursive descent → `Map` / `List` / `String` / `Double` / `Boolean` | `JValue` = `std::variant<nullptr_t, bool, double, string, shared_ptr<JArray>, shared_ptr<JObject>>` |
| Model | `record Step(id, after, action, when, retry, compensate)`; `Workflow(steps, topo, dependents)` | the same structs; `shared_ptr<const Workflow>` |
| Validation | `sealed Checked permits Valid, Invalid`: the only way to get a `Workflow` | `std::variant<Valid, Invalid>` |
| Run state | `ConcurrentHashMap<id, State>` journal; `State` PENDING → RUNNING → SUCCEEDED / SKIPPED / FAILED / CANCELLED / COMPENSATED | a mutex-guarded `std::map` journal |
| Scheduling | `waiting[id]` = `AtomicInteger` in-degree; `decrementAndGet() == 0` schedules | `std::atomic<int>`, `fetch_sub(1) == 1` |
| Executor | virtual threads (section 2), single-thread (sections 3–4), fixed pool (section 5) | thread-per-task, `FixedPool(1)`, `FixedPool(8)` |

**Invariants:**
- **I1:** a `Workflow` exists only if it is a valid DAG; its topological order is unique (Kahn's algorithm, ties broken by id).
- **I2:** every step makes **exactly one** terminal transition, via a compare-and-replace on the journal. The run finishes when the count of open steps reaches 0.
- **I3:** a step is scheduled exactly once, by the last dependency to become satisfied.
- **I4:** after a failure no new step starts. Dependents are cancelled; completed steps with a `compensate` action are compensated in **reverse topological order**.
- **I5:** a resumed run never re-executes a step the journal records as SUCCEEDED or SKIPPED. RUNNING at the crash means "re-run", so actions must be idempotent.

## 3. Concurrency and contention analysis

### 3.1 Validation: reject what can never finish

- **Cycles** are found by DFS with three colours and reported **as a path**: `cycle: a -> b -> c -> a`. "Workflow invalid" is not an error message; the path is the fix.
- **Unknown dependencies, duplicate ids and malformed JSON** are rejected before any run exists. Each listing reports the same error position.
- **The topological order is unique:** `[validate, analytics, fraud, loyalty, reserve, charge, giftwrap, ship, email]`. Logs, compensation order and tests are therefore reproducible.

### 3.2 Exactly-once scheduling at a join

Each step carries an atomic count of unsatisfied dependencies. A completing parent decrements each child; **only the decrement that reaches 0 schedules the child**.

The tempting alternative is "after I finish, check whether all my siblings are done". It schedules twice whenever several parents observe "all done".

**Measured: 64 parents → 1 join, 2,000 rounds on 8 threads:**

| Join logic | Java | GCC | Clang |
|---|---|---|---|
| Each parent checks "are all parents done?" (a concurrent set: atomic operations, non-atomic pair) | join ran ≠ once in **32** rounds | **525** | **116** |
| `decrementAndGet() == 0` | 0 | 0 | 0 |

### 3.3 Parallel run, rules and retries

**Section 2:** 50 ms of work per attempt; `charge` is `flaky:2` with `retry {max 3, backoff 100}`.
- 10 attempts = 500 ms of work finished in **385 ms** (Java), 445 ms (GCC) and 430 ms (Clang).
- The critical path is 350 ms: validate → reserve → charge ×3 → ship → email.
- `giftwrap` was SKIPPED by its rule (`giftWrap == true` is false), and `email`, which depends on it, still ran.
- Backoffs were 100 then 200 ms. A **sleeper is injected**, so tests record the delays instead of waiting.

**Structured concurrency.** In Java 25, `StructuredTaskScope` (still a preview API) gives each run a scope: cancellation and failure propagate to subtasks automatically. The listing targets `--release 21` without preview, so it uses an executor plus an explicit fail-fast flag, which is what the scope would encapsulate.

### 3.4 Failure: cancel forward, compensate backward

**When `charge` fails all three attempts:**
1. Its downstream (`ship`, `email`) becomes **CANCELLED**.
2. Steps that were ready but not started (`giftwrap`) see the failed flag and cancel themselves *and their downstream*.
3. Completed steps with compensations are undone in **reverse topological order**: `release(reserve)`, then `revoke-points(loyalty)`.

Reverse *completion* order would vary run to run when steps ran in parallel. Reverse *topological* order is deterministic and still undoes dependents before their dependencies.

**The bug the first draft hit.** A step cancelled by the failed flag didn't cancel its own dependents. `giftwrap` was never scheduled and never terminal, so the run hung, and the 30-second guard in `await()` caught it. The rule: **every path to CANCELLED must propagate downstream.** That's why the listing funnels all transitions through `terminal()` plus `cancelDownstream()`.

### 3.5 Crash and resume

**Section 4** "crashes" right after `charge` succeeds. The journal write survived; the other queued steps did not run.
- The journal at the crash: `validate … charge = SUCCEEDED`, `giftwrap / ship / email = PENDING`.
- The resumed run recomputes in-degrees from the journal (satisfied = SUCCEEDED or SKIPPED) and schedules only what's ready. It **executed `ship` and `email` only**.

**The window between "work done" and "journal written" is real.** A crash there means the step re-runs. So actions take an idempotency key (run id + step id), the [P13](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md) pattern, and the second execution becomes a replay.

## 4. Java 21 implementation

```java
// WorkflowEngine.java - P20: JSON workflow -> validated DAG (cycle path), rules, parallel steps, retries, compensation, resume
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.LongAdder;

public final class WorkflowEngine {

    // ---- a minimal JSON reader: objects, arrays, strings, numbers, booleans, null

    static final class Json {
        final String s;
        int i;

        Json(String s) {
            this.s = s;
        }

        static Object parse(String text) {
            Json j = new Json(text);
            Object v = j.value();
            j.ws();
            if (j.i != text.length()) throw new IllegalArgumentException("trailing characters at " + j.i);
            return v;
        }

        void ws() {
            while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++;
        }

        Object value() {
            ws();
            char c = s.charAt(i);
            if (c == '{') {
                Map<String, Object> m = new LinkedHashMap<>();
                i++;
                ws();
                if (s.charAt(i) == '}') {
                    i++;
                    return m;
                }
                do {
                    ws();
                    String k = (String) value();
                    ws();
                    expect(':');
                    m.put(k, value());
                    ws();
                } while (s.charAt(i++) == ',');
                if (s.charAt(i - 1) != '}') throw new IllegalArgumentException("expected } at " + (i - 1));
                return m;
            }
            if (c == '[') {
                List<Object> l = new ArrayList<>();
                i++;
                ws();
                if (s.charAt(i) == ']') {
                    i++;
                    return l;
                }
                do l.add(value()); while (nextIs(','));
                expect(']');
                return l;
            }
            if (c == '"') {
                StringBuilder b = new StringBuilder();
                for (i++; s.charAt(i) != '"'; i++) b.append(s.charAt(i) == '\\' ? s.charAt(++i) : s.charAt(i));
                i++;
                return b.toString();
            }
            if (s.startsWith("true", i)) {
                i += 4;
                return true;
            }
            if (s.startsWith("false", i)) {
                i += 5;
                return false;
            }
            if (s.startsWith("null", i)) {
                i += 4;
                return null;
            }
            int start = i;
            while (i < s.length() && "+-.0123456789eE".indexOf(s.charAt(i)) >= 0) i++;
            if (start == i) throw new IllegalArgumentException("unexpected '" + c + "' at " + i);
            return Double.parseDouble(s.substring(start, i));
        }

        boolean nextIs(char c) {
            ws();
            if (i < s.length() && s.charAt(i) == c) {
                i++;
                return true;
            }
            return false;
        }

        void expect(char c) {
            ws();
            if (s.charAt(i++) != c) throw new IllegalArgumentException("expected " + c + " at " + (i - 1));
        }
    }

    // ---- the validated model: only Validator.check can produce a Workflow

    record Retry(int max, long backoffMs) {}
    record Cond(String field, String op, Object value) {}
    record Step(String id, List<String> after, String action, List<Cond> when, Retry retry, String compensate) {}
    record Workflow(String name, Map<String, Step> steps, List<String> topo, Map<String, List<String>> dependents) {}

    sealed interface Checked permits Valid, Invalid {}
    record Valid(Workflow wf) implements Checked {}
    record Invalid(String reason) implements Checked {}

    @SuppressWarnings("unchecked")
    static Checked check(String json) {
        Map<String, Object> root;
        try {
            root = (Map<String, Object>) Json.parse(json);
        } catch (RuntimeException e) {
            return new Invalid("bad JSON: " + e.getMessage());
        }
        Map<String, Step> steps = new TreeMap<>();
        for (Object o : (List<Object>) root.get("steps")) {
            Map<String, Object> m = (Map<String, Object>) o;
            String id = (String) m.get("id");
            if (steps.containsKey(id)) return new Invalid("duplicate step id " + id);
            List<Cond> when = new ArrayList<>();
            for (Object c : (List<Object>) m.getOrDefault("when", List.of())) {
                Map<String, Object> cm = (Map<String, Object>) c;
                when.add(new Cond((String) cm.get("field"), (String) cm.get("op"), cm.get("value")));
            }
            Map<String, Object> r = (Map<String, Object>) m.get("retry");
            Retry retry = r == null ? new Retry(1, 0) : new Retry(((Double) r.get("max")).intValue(), ((Double) r.get("backoffMs")).longValue());
            List<String> after = new ArrayList<>();
            for (Object a : (List<Object>) m.getOrDefault("after", List.of())) after.add((String) a);
            steps.put(id, new Step(id, after, (String) m.get("action"), when, retry, (String) m.get("compensate")));
        }
        Map<String, List<String>> dependents = new TreeMap<>();
        for (Step s : steps.values()) dependents.put(s.id(), new ArrayList<>());
        for (Step s : steps.values())
            for (String a : s.after()) {
                if (!steps.containsKey(a)) return new Invalid("step " + s.id() + " depends on unknown step " + a);
                dependents.get(a).add(s.id());
            }
        String cycle = findCycle(steps);
        if (cycle != null) return new Invalid("cycle: " + cycle);
        Map<String, Integer> indeg = new HashMap<>();                  // Kahn's algorithm, ties broken by id: one canonical order
        steps.values().forEach(s -> indeg.put(s.id(), s.after().size()));
        PriorityQueue<String> ready = new PriorityQueue<>();
        indeg.forEach((id, d) -> {
            if (d == 0) ready.add(id);
        });
        List<String> topo = new ArrayList<>();
        while (!ready.isEmpty()) {
            String id = ready.poll();
            topo.add(id);
            for (String d : dependents.get(id))
                if (indeg.merge(d, -1, Integer::sum) == 0) ready.add(d);
        }
        return new Valid(new Workflow((String) root.get("name"), Collections.unmodifiableMap(steps), List.copyOf(topo), dependents));
    }

    /** DFS with colours over "after" edges; returns the cycle as a path, e.g. "a -> b -> c -> a". */
    static String findCycle(Map<String, Step> steps) {
        Map<String, Integer> colour = new HashMap<>();
        for (String start : steps.keySet()) {
            if (colour.containsKey(start)) continue;
            List<String> path = new ArrayList<>();
            String c = dfs(start, steps, colour, path);
            if (c != null) return c;
        }
        return null;
    }

    static String dfs(String id, Map<String, Step> steps, Map<String, Integer> colour, List<String> path) {
        colour.put(id, 1);
        path.add(id);
        for (String dep : steps.get(id).after()) {
            if (colour.getOrDefault(dep, 0) == 1) {
                List<String> cyc = new ArrayList<>(path.subList(path.indexOf(dep), path.size()));
                cyc.add(dep);
                Collections.reverse(cyc);                              // print in execution direction: dep -> ... -> dependent
                return String.join(" -> ", cyc);
            }
            if (colour.getOrDefault(dep, 0) == 0) {
                String c = dfs(dep, steps, colour, path);
                if (c != null) return c;
            }
        }
        colour.put(id, 2);
        path.removeLast();
        return null;
    }

    static boolean holds(Cond c, Map<String, Object> ctx) {
        Object v = ctx.get(c.field());
        if (v instanceof Double d && c.value() instanceof Double w) return switch (c.op()) {
            case ">=" -> d >= w;
            case "<=" -> d <= w;
            case "==" -> d.equals(w);
            case "!=" -> !d.equals(w);
            default -> false;
        };
        return switch (c.op()) {
            case "==" -> String.valueOf(v).equals(String.valueOf(c.value()));
            case "!=" -> !String.valueOf(v).equals(String.valueOf(c.value()));
            default -> false;
        };
    }

    // ---- running a workflow: a journal of step states, atomic in-degree counters, retries, compensation

    enum State { PENDING, RUNNING, SUCCEEDED, SKIPPED, FAILED, CANCELLED, COMPENSATED }

    interface Sleeper {
        void sleep(long ms);
    }

    static final class Run {
        final Workflow wf;
        final Map<String, Object> ctx;
        final ConcurrentHashMap<String, State> journal;                // survives a crash: resume reads it
        final Map<String, AtomicInteger> waiting = new HashMap<>();
        final Map<String, AtomicInteger> attempts = new ConcurrentHashMap<>();
        final ExecutorService exec;
        final Sleeper backoff;
        final List<Long> backoffs = Collections.synchronizedList(new ArrayList<>());
        final List<String> compensations = Collections.synchronizedList(new ArrayList<>());
        final AtomicBoolean failed = new AtomicBoolean();
        final AtomicInteger remaining = new AtomicInteger();
        final CountDownLatch finished = new CountDownLatch(1);
        final long workMs;
        final String crashAfter;                                       // test hook: "crash" right after this step succeeds
        volatile boolean crashed;

        Run(Workflow wf, Map<String, Object> ctx, Map<String, State> journal, ExecutorService exec, Sleeper backoff, long workMs, String crashAfter) {
            this.wf = wf;
            this.ctx = ctx;
            this.journal = new ConcurrentHashMap<>(journal);
            this.exec = exec;
            this.backoff = backoff;
            this.workMs = workMs;
            this.crashAfter = crashAfter;
            for (Step s : wf.steps().values()) {
                this.journal.merge(s.id(), State.PENDING, (old, p) -> old == State.RUNNING ? State.PENDING : old);   // RUNNING at a crash = re-run
                attempts.put(s.id(), new AtomicInteger());
            }
        }

        Run start() {
            int open = 0;
            for (Step s : wf.steps().values()) {
                long unsatisfied = s.after().stream().filter(a -> !done(journal.get(a))).count();
                waiting.put(s.id(), new AtomicInteger((int) unsatisfied));
                if (!done(journal.get(s.id()))) open++;
            }
            remaining.set(open);
            if (open == 0) finish();
            for (String id : wf.topo())
                if (!done(journal.get(id)) && waiting.get(id).get() == 0) schedule(id);
            return this;
        }

        static boolean done(State s) {
            return s == State.SUCCEEDED || s == State.SKIPPED;
        }

        void schedule(String id) {
            exec.execute(() -> runStep(wf.steps().get(id)));
        }

        boolean terminal(String id, State from, State to) {             // exactly one terminal transition per step
            if (!journal.replace(id, from, to)) return false;
            if (remaining.decrementAndGet() == 0) finish();
            return true;
        }

        void runStep(Step s) {
            if (crashed) return;
            if (failed.get()) {                                        // fail fast: start nothing new after a failure
                if (terminal(s.id(), State.PENDING, State.CANCELLED)) cancelDownstream(s.id());
                return;
            }
            if (!journal.replace(s.id(), State.PENDING, State.RUNNING)) return;
            if (!s.when().stream().allMatch(c -> holds(c, ctx))) {
                complete(s, State.SKIPPED);
                return;
            }
            for (int attempt = 1; ; attempt++) {
                attempts.get(s.id()).incrementAndGet();
                if (workMs > 0) sleepQuietly(workMs);
                if (perform(s.action(), attempt)) break;
                if (attempt >= s.retry().max()) {
                    failed.set(true);
                    terminal(s.id(), State.RUNNING, State.FAILED);
                    cancelDownstream(s.id());
                    return;
                }
                long delay = s.retry().backoffMs() << (attempt - 1);   // exponential backoff
                backoffs.add(delay);
                backoff.sleep(delay);
            }
            complete(s, State.SUCCEEDED);
        }

        void complete(Step s, State how) {
            if (crashAfter != null && crashAfter.equals(s.id())) {      // the process dies after the work but...
                journal.put(s.id(), how);                              // ...the journal write made it to disk
                crashed = true;
                finished.countDown();
                return;
            }
            terminal(s.id(), State.RUNNING, how);
            for (String d : wf.dependents().get(s.id()))
                if (waiting.get(d).decrementAndGet() == 0) schedule(d); // the LAST parent to finish schedules it, exactly once
        }

        void cancelDownstream(String id) {                              // dependents of a failed step can never run
            ArrayDeque<String> todo = new ArrayDeque<>(wf.dependents().get(id));
            while (!todo.isEmpty()) {
                String d = todo.pop();
                if (terminal(d, State.PENDING, State.CANCELLED)) todo.addAll(wf.dependents().get(d));
            }
        }

        static boolean perform(String action, int attempt) {
            if (action.startsWith("flaky:")) return attempt > Integer.parseInt(action.substring(6));
            return !action.equals("fail");
        }

        void finish() {
            if (failed.get())                                          // saga: undo completed work, dependents before dependencies
                for (int i = wf.topo().size() - 1; i >= 0; i--) {
                    Step s = wf.steps().get(wf.topo().get(i));
                    if (journal.get(s.id()) == State.SUCCEEDED && s.compensate() != null) {
                        compensations.add(s.compensate() + "(" + s.id() + ")");
                        journal.put(s.id(), State.COMPENSATED);
                    }
                }
            finished.countDown();
        }

        String await() throws InterruptedException {
            if (!finished.await(30, TimeUnit.SECONDS)) throw new IllegalStateException("workflow stuck");
            StringBuilder b = new StringBuilder();
            for (String id : wf.topo()) b.append(id).append('=').append(journal.get(id)).append(' ');
            return b.toString().trim();
        }

        static void sleepQuietly(long ms) {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    static final String ORDER = """
            {"name": "order", "steps": [
              {"id": "validate", "action": "ok"},
              {"id": "reserve", "after": ["validate"], "action": "ok", "compensate": "release"},
              {"id": "fraud", "after": ["validate"], "action": "ok"},
              {"id": "loyalty", "after": ["validate"], "action": "ok", "compensate": "revoke-points"},
              {"id": "analytics", "after": ["validate"], "action": "ok"},
              {"id": "charge", "after": ["reserve", "fraud"], "action": "flaky:2", "retry": {"max": 3, "backoffMs": 100}, "compensate": "refund"},
              {"id": "giftwrap", "after": ["reserve"], "action": "ok", "when": [{"field": "giftWrap", "op": "==", "value": true}]},
              {"id": "ship", "after": ["charge"], "action": "ok", "when": [{"field": "total", "op": ">=", "value": 50}]},
              {"id": "email", "after": ["ship", "giftwrap"], "action": "ok"}
            ]}""";

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Parse and validate ==");
        Workflow wf = ((Valid) check(ORDER)).wf();
        System.out.println("  order: valid, topological order " + wf.topo());
        String[][] bad = {
                {"a -> b -> c -> a", "{\"name\":\"x\",\"steps\":[{\"id\":\"a\",\"after\":[\"c\"],\"action\":\"ok\"},{\"id\":\"b\",\"after\":[\"a\"],\"action\":\"ok\"},{\"id\":\"c\",\"after\":[\"b\"],\"action\":\"ok\"}]}"},
                {"unknown dependency", "{\"name\":\"x\",\"steps\":[{\"id\":\"a\",\"after\":[\"zzz\"],\"action\":\"ok\"}]}"},
                {"duplicate id", "{\"name\":\"x\",\"steps\":[{\"id\":\"a\",\"action\":\"ok\"},{\"id\":\"a\",\"action\":\"ok\"}]}"},
                {"broken JSON", "{\"name\":\"x\",\"steps\":[{\"id\":\"a\" \"action\":\"ok\"}]}"}};
        for (String[] b : bad) System.out.printf("  %-20s -> %s%n", b[0], check(b[1]) instanceof Invalid i ? i.reason() : "valid?!");

        System.out.println("== 2. Run in parallel (virtual threads, 50 ms of work per attempt), total = 72, no gift wrap ==");
        List<Long> recorded = Collections.synchronizedList(new ArrayList<>());
        Run run;
        long t0 = System.nanoTime();
        try (ExecutorService vt = Executors.newVirtualThreadPerTaskExecutor()) {
            run = new Run(wf, Map.of("total", 72.0, "giftWrap", false), Map.of(), vt, recorded::add, 50, null).start();
            System.out.println("  " + run.await());
        }
        long wallMs = (System.nanoTime() - t0) / 1_000_000;
        int totalAttempts = run.attempts.values().stream().mapToInt(AtomicInteger::get).sum();
        System.out.printf("  attempts: charge %d (flaky:2, max 3) | backoffs requested %s ms | %d attempts x 50 ms = %d ms of work in %d ms wall"
                + " (critical path validate-reserve-charge x3-ship-email = 7 attempts = 350 ms)%n", run.attempts.get("charge").get(), recorded,
                totalAttempts, totalAttempts * 50, wallMs);

        System.out.println("== 3. Failure: charge fails 3 times -> cancel what can't run, compensate what ran (reverse topological order) ==");
        Workflow failing = ((Valid) check(ORDER.replace("\"flaky:2\"", "\"fail\""))).wf();
        String summary3;
        Run r3;
        try (ExecutorService one = Executors.newSingleThreadExecutor()) {   // one thread: a deterministic interleaving
            r3 = new Run(failing, Map.of("total", 72.0, "giftWrap", true), Map.of(), one, ms -> {}, 0, null).start();
            summary3 = r3.await();
        }
        System.out.println("  " + summary3);
        System.out.println("  compensations run: " + r3.compensations + " | backoffs " + r3.backoffs + " ms");

        System.out.println("== 4. Crash right after 'charge' succeeds, then resume from the journal ==");
        Map<String, State> journal;
        Run first;
        try (ExecutorService one = Executors.newSingleThreadExecutor()) {
            first = new Run(wf, Map.of("total", 72.0, "giftWrap", false), Map.of(), one, ms -> {}, 0, "charge").start();
            first.await();
            journal = new TreeMap<>(first.journal);
        }
        System.out.println("  journal at the crash: " + journal);
        Run resumed;
        try (ExecutorService one = Executors.newSingleThreadExecutor()) {
            resumed = new Run(wf, Map.of("total", 72.0, "giftWrap", false), journal, one, ms -> {}, 0, null).start();
            System.out.println("  resumed: " + resumed.await());
        }
        Map<String, Integer> reRun = new TreeMap<>();
        resumed.attempts.forEach((id, n) -> {
            if (n.get() > 0) reRun.put(id, n.get());
        });
        System.out.println("  steps executed by the resumed run: " + reRun + " (validate and charge were not re-run)");

        System.out.println("== 5. Fan-in: 64 parents finish concurrently, one join step; 2,000 rounds on 8 threads ==");
        int naiveDoubles = 0, atomicDoubles = 0;
        ExecutorService pool = Executors.newFixedThreadPool(8);
        for (int round = 0; round < 2_000; round++) {
            for (int mode = 0; mode < 2; mode++) {
                Set<Integer> doneParents = ConcurrentHashMap.newKeySet();
                AtomicInteger waitingFor = new AtomicInteger(64);
                LongAdder joinRuns = new LongAdder();
                CountDownLatch all = new CountDownLatch(64);
                final int m = mode;
                for (int p = 0; p < 64; p++) {
                    final int id = p;
                    pool.execute(() -> {
                        if (m == 0) {
                            doneParents.add(id);
                            if (doneParents.size() == 64) joinRuns.increment();   // "are all my siblings done?"
                        } else if (waitingFor.decrementAndGet() == 0) {
                            joinRuns.increment();                              // only the last decrement sees 0
                        }
                        all.countDown();
                    });
                }
                all.await();
                if (joinRuns.sum() != 1) {
                    if (m == 0) naiveDoubles++;
                    else atomicDoubles++;
                }
            }
        }
        pool.shutdown();
        if (!pool.awaitTermination(10, TimeUnit.SECONDS)) throw new IllegalStateException("pool stuck");
        System.out.printf("  'all parents done?' check by each parent: join ran != once in %d of 2000 rounds%n", naiveDoubles);
        System.out.printf("  atomic in-degree, decrementAndGet() == 0: join ran != once in %d of 2000 rounds%n", atomicDoubles);

        Set<String> expectedTopo = new HashSet<>(List.of("validate", "reserve", "fraud", "loyalty", "analytics", "charge", "giftwrap", "ship", "email"));
        boolean ok = new HashSet<>(wf.topo()).equals(expectedTopo) && wf.topo().getFirst().equals("validate") && wf.topo().getLast().equals("email")
                && check(bad[0][1]) instanceof Invalid i0 && i0.reason().contains("->")
                && run.journal.get("giftwrap") == State.SKIPPED && run.journal.get("email") == State.SUCCEEDED && run.attempts.get("charge").get() == 3
                && recorded.equals(List.of(100L, 200L)) && wallMs < totalAttempts * 50L
                && r3.journal.get("charge") == State.FAILED && r3.journal.get("ship") == State.CANCELLED
                && r3.compensations.equals(List.of("release(reserve)", "revoke-points(loyalty)"))
                && journal.get("charge") == State.SUCCEEDED && resumed.attempts.get("charge").get() == 0 && resumed.attempts.get("validate").get() == 0
                && resumed.journal.get("email") == State.SUCCEEDED && atomicDoubles == 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1, 3 and 4 deterministic; 2 and 5 one measured run):**

```text
== 1. Parse and validate ==
  order: valid, topological order [validate, analytics, fraud, loyalty, reserve, charge, giftwrap, ship, email]
  a -> b -> c -> a     -> cycle: a -> b -> c -> a
  unknown dependency   -> step a depends on unknown step zzz
  duplicate id         -> duplicate step id a
  broken JSON          -> bad JSON: expected } at 31
== 2. Run in parallel (virtual threads, 50 ms of work per attempt), total = 72, no gift wrap ==
  validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=SUCCEEDED reserve=SUCCEEDED charge=SUCCEEDED giftwrap=SKIPPED ship=SUCCEEDED email=SUCCEEDED
  attempts: charge 3 (flaky:2, max 3) | backoffs requested [100, 200] ms | 10 attempts x 50 ms = 500 ms of work in 385 ms wall (critical path validate-reserve-charge x3-ship-email = 7 attempts = 350 ms)
== 3. Failure: charge fails 3 times -> cancel what can't run, compensate what ran (reverse topological order) ==
  validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=COMPENSATED reserve=COMPENSATED charge=FAILED giftwrap=CANCELLED ship=CANCELLED email=CANCELLED
  compensations run: [release(reserve), revoke-points(loyalty)] | backoffs [100, 200] ms
== 4. Crash right after 'charge' succeeds, then resume from the journal ==
  journal at the crash: {analytics=SUCCEEDED, charge=SUCCEEDED, email=PENDING, fraud=SUCCEEDED, giftwrap=PENDING, loyalty=SUCCEEDED, reserve=SUCCEEDED, ship=PENDING, validate=SUCCEEDED}
  resumed: validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=SUCCEEDED reserve=SUCCEEDED charge=SUCCEEDED giftwrap=SKIPPED ship=SUCCEEDED email=SUCCEEDED
  steps executed by the resumed run: {email=1, ship=1} (validate and charge were not re-run)
== 5. Fan-in: 64 parents finish concurrently, one join step; 2,000 rounds on 8 threads ==
  'all parents done?' check by each parent: join ran != once in 32 of 2000 rounds
  atomic in-degree, decrementAndGet() == 0: join ran != once in 0 of 2000 rounds
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// workflow_engine.cpp - P20: JSON workflow -> validated DAG (cycle path), rules, parallel steps, retries, compensation, resume
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <format>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <queue>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using sz = std::size_t;
using namespace std::chrono_literals;

// ---- a minimal JSON reader: objects, arrays, strings, numbers, booleans, null

struct JValue;
using JArray = std::vector<JValue>;
using JObject = std::map<std::string, JValue>;
struct JValue { std::variant<std::nullptr_t, bool, double, std::string, std::shared_ptr<JArray>, std::shared_ptr<JObject>> v; };

class Json {
    const std::string& s_;
    sz i_ = 0;
    char at(sz k) const {
        if (k >= s_.size()) throw std::invalid_argument(std::format("unexpected end at {}", k));
        return s_[k];
    }
    void ws() {
        while (i_ < s_.size() && std::isspace(static_cast<unsigned char>(s_[i_]))) ++i_;
    }
    bool next_is(char c) {
        ws();
        if (i_ < s_.size() && s_[i_] == c) {
            ++i_;
            return true;
        }
        return false;
    }
    void expect(char c) {
        ws();
        if (at(i_++) != c) throw std::invalid_argument(std::format("expected {} at {}", c, i_ - 1));
    }
    JValue value() {
        ws();
        const char c = at(i_);
        if (c == '{') {
            auto m = std::make_shared<JObject>();
            ++i_;
            ws();
            if (at(i_) == '}') {
                ++i_;
                return {m};
            }
            do {
                ws();
                const JValue k = value();
                ws();
                expect(':');
                (*m)[std::get<std::string>(k.v)] = value();
                ws();
            } while (at(i_++) == ',');
            if (at(i_ - 1) != '}') throw std::invalid_argument(std::format("expected }} at {}", i_ - 1));
            return {m};
        }
        if (c == '[') {
            auto a = std::make_shared<JArray>();
            ++i_;
            ws();
            if (at(i_) == ']') {
                ++i_;
                return {a};
            }
            do a->push_back(value());
            while (next_is(','));
            expect(']');
            return {a};
        }
        if (c == '"') {
            std::string b;
            for (++i_; at(i_) != '"'; ++i_) b += at(i_) == '\\' ? at(++i_) : at(i_);
            ++i_;
            return {b};
        }
        if (s_.compare(i_, 4, "true") == 0) {
            i_ += 4;
            return {true};
        }
        if (s_.compare(i_, 5, "false") == 0) {
            i_ += 5;
            return {false};
        }
        if (s_.compare(i_, 4, "null") == 0) {
            i_ += 4;
            return {nullptr};
        }
        const sz start = i_;
        while (i_ < s_.size() && std::string_view("+-.0123456789eE").find(s_[i_]) != std::string_view::npos) ++i_;
        if (start == i_) throw std::invalid_argument(std::format("unexpected '{}' at {}", c, i_));
        return {std::stod(s_.substr(start, i_ - start))};
    }

public:
    explicit Json(const std::string& s) : s_(s) {}
    static JValue parse(const std::string& text) {
        Json j(text);
        JValue v = j.value();
        j.ws();
        if (j.i_ != text.size()) throw std::invalid_argument(std::format("trailing characters at {}", j.i_));
        return v;
    }
};

const JObject& obj(const JValue& v) { return *std::get<std::shared_ptr<JObject>>(v.v); }
const JArray& arr(const JValue& v) { return *std::get<std::shared_ptr<JArray>>(v.v); }
const JValue* field(const JObject& o, const std::string& k) {
    const auto it = o.find(k);
    return it == o.end() ? nullptr : &it->second;
}

// ---- the validated model: only check() can produce a Workflow

struct Retry { int max; i64 backoff_ms; };
struct Cond { std::string field, op; JValue value; };
struct Step { std::string id; std::vector<std::string> after; std::string action; std::vector<Cond> when; Retry retry; std::optional<std::string> compensate; };
struct Workflow { std::string name; std::map<std::string, Step> steps; std::vector<std::string> topo; std::map<std::string, std::vector<std::string>> dependents; };
struct Valid { std::shared_ptr<const Workflow> wf; };
struct Invalid { std::string reason; };
using Checked = std::variant<Valid, Invalid>;

bool dfs(const std::string& id, const std::map<std::string, Step>& steps, std::map<std::string, int>& colour, std::vector<std::string>& path,
         std::string& cycle) {
    colour[id] = 1;
    path.push_back(id);
    for (const auto& dep : steps.at(id).after) {
        if (colour[dep] == 1) {
            std::vector<std::string> cyc(std::ranges::find(path, dep), path.end());
            cyc.push_back(dep);
            std::ranges::reverse(cyc);  // print in execution direction: dep -> ... -> dependent
            for (const auto& c : cyc) cycle += (cycle.empty() ? "" : " -> ") + c;
            return true;
        }
        if (colour[dep] == 0 && dfs(dep, steps, colour, path, cycle)) return true;
    }
    colour[id] = 2;
    path.pop_back();
    return false;
}

Checked check(const std::string& json) {
    JValue root;
    try {
        root = Json::parse(json);
    } catch (const std::exception& e) {
        return Invalid{std::string("bad JSON: ") + e.what()};
    }
    auto wf = std::make_shared<Workflow>();
    wf->name = std::get<std::string>(field(obj(root), "name")->v);
    for (const auto& sv : arr(*field(obj(root), "steps"))) {
        const auto& m = obj(sv);
        Step s;
        s.id = std::get<std::string>(field(m, "id")->v);
        if (wf->steps.contains(s.id)) return Invalid{"duplicate step id " + s.id};
        if (const auto* a = field(m, "after"))
            for (const auto& x : arr(*a)) s.after.push_back(std::get<std::string>(x.v));
        s.action = std::get<std::string>(field(m, "action")->v);
        if (const auto* w = field(m, "when"))
            for (const auto& c : arr(*w)) {
                const auto& cm = obj(c);
                s.when.push_back({std::get<std::string>(field(cm, "field")->v), std::get<std::string>(field(cm, "op")->v), *field(cm, "value")});
            }
        s.retry = {1, 0};
        if (const auto* r = field(m, "retry"))
            s.retry = {static_cast<int>(std::get<double>(field(obj(*r), "max")->v)), static_cast<i64>(std::get<double>(field(obj(*r), "backoffMs")->v))};
        if (const auto* c = field(m, "compensate")) s.compensate = std::get<std::string>(c->v);
        wf->steps.emplace(s.id, std::move(s));
    }
    for (const auto& [id, s] : wf->steps) wf->dependents[id];
    for (const auto& [id, s] : wf->steps)
        for (const auto& a : s.after) {
            if (!wf->steps.contains(a)) return Invalid{std::format("step {} depends on unknown step {}", id, a)};
            wf->dependents[a].push_back(id);
        }
    std::map<std::string, int> colour;
    for (const auto& [id, s] : wf->steps) {
        if (colour[id] != 0) continue;
        std::vector<std::string> path;
        std::string cycle;
        if (dfs(id, wf->steps, colour, path, cycle)) return Invalid{"cycle: " + cycle};
    }
    std::map<std::string, sz> indeg;  // Kahn's algorithm, ties broken by id: one canonical order
    std::priority_queue<std::string, std::vector<std::string>, std::greater<>> ready;
    for (const auto& [id, s] : wf->steps)
        if ((indeg[id] = s.after.size()) == 0) ready.push(id);
    while (!ready.empty()) {
        const std::string id = ready.top();
        ready.pop();
        wf->topo.push_back(id);
        for (const auto& d : wf->dependents[id])
            if (--indeg[d] == 0) ready.push(d);
    }
    return Valid{std::move(wf)};
}

bool holds(const Cond& c, const std::map<std::string, JValue>& ctx) {
    const auto it = ctx.find(c.field);
    if (it == ctx.end()) return false;
    const auto* d = std::get_if<double>(&it->second.v);
    const auto* w = std::get_if<double>(&c.value.v);
    if (d && w) return c.op == ">=" ? *d >= *w : c.op == "<=" ? *d <= *w : c.op == "==" ? *d == *w : c.op == "!=" ? *d != *w : false;
    const auto* b = std::get_if<bool>(&it->second.v);
    const auto* bv = std::get_if<bool>(&c.value.v);
    if (b && bv) return c.op == "==" ? *b == *bv : c.op == "!=" ? *b != *bv : false;
    return false;
}

// ---- executors: a serial FIFO (deterministic), thread-per-task (like virtual threads), and a fixed pool

struct Executor {
    virtual ~Executor() = default;
    virtual void execute(std::function<void()> task) = 0;
};

class FixedPool final : public Executor {
    std::mutex m_;
    std::condition_variable cv_;
    std::deque<std::function<void()>> q_;
    bool stop_ = false;
    std::vector<std::jthread> workers_;

public:
    explicit FixedPool(int n) {
        std::scoped_lock warm(m_);
        for (int i = 0; i < n; ++i)
            workers_.emplace_back([this] {
                for (;;) {
                    std::function<void()> job;
                    {
                        std::unique_lock l(m_);
                        cv_.wait(l, [&] { return stop_ || !q_.empty(); });
                        if (q_.empty()) return;
                        job = std::move(q_.front());
                        q_.pop_front();
                    }
                    job();
                }
            });
    }
    void execute(std::function<void()> task) override {
        {
            std::scoped_lock l(m_);
            q_.push_back(std::move(task));
        }
        cv_.notify_one();
    }
    ~FixedPool() override {
        {
            std::scoped_lock l(m_);
            stop_ = true;
        }
        cv_.notify_all();
        workers_.clear();  // joins after the queue drains
    }
};

class ThreadPerTask final : public Executor {
    std::mutex m_;
    std::vector<std::jthread> threads_;

public:
    ThreadPerTask() { std::scoped_lock warm(m_); }
    void execute(std::function<void()> task) override {
        std::scoped_lock l(m_);
        threads_.emplace_back(std::move(task));
    }
    ~ThreadPerTask() override {
        std::vector<std::jthread> all;
        {
            std::scoped_lock l(m_);
            all = std::move(threads_);
        }
        all.clear();
    }
};

// ---- running a workflow: a journal of step states, atomic in-degree counters, retries, compensation

enum class State { Pending, Running, Succeeded, Skipped, Failed, Cancelled, Compensated };
constexpr const char* name(State s) {
    switch (s) {
        case State::Pending: return "PENDING";
        case State::Running: return "RUNNING";
        case State::Succeeded: return "SUCCEEDED";
        case State::Skipped: return "SKIPPED";
        case State::Failed: return "FAILED";
        case State::Cancelled: return "CANCELLED";
        case State::Compensated: return "COMPENSATED";
    }
    return "?";
}

class Run {
    std::shared_ptr<const Workflow> wf_;
    std::map<std::string, JValue> ctx_;
    mutable std::mutex jm_;
    std::map<std::string, State> journal_;  // guarded by jm_; survives a crash: resume reads it
    std::map<std::string, std::atomic<int>> waiting_;
    Executor& exec_;
    std::function<void(i64)> backoff_;
    i64 work_ms_;
    std::optional<std::string> crash_after_;  // test hook: "crash" right after this step succeeds
    std::atomic<bool> failed_{false}, crashed_{false};
    std::atomic<int> remaining_{0};
    std::mutex fm_;
    std::condition_variable fcv_;
    bool finished_ = false;
    std::mutex lm_;  // guards the two lists below

public:
    std::map<std::string, std::atomic<int>> attempts;
    std::vector<i64> backoffs;
    std::vector<std::string> compensations;

    Run(std::shared_ptr<const Workflow> wf, std::map<std::string, JValue> ctx, const std::map<std::string, State>& journal, Executor& exec,
        std::function<void(i64)> backoff, i64 work_ms, std::optional<std::string> crash_after)
        : wf_(std::move(wf)), ctx_(std::move(ctx)), journal_(journal), exec_(exec), backoff_(std::move(backoff)), work_ms_(work_ms),
          crash_after_(std::move(crash_after)) {
        std::scoped_lock warm(jm_, fm_, lm_);
        for (const auto& [id, s] : wf_->steps) {
            auto [it, inserted] = journal_.try_emplace(id, State::Pending);
            if (!inserted && it->second == State::Running) it->second = State::Pending;  // RUNNING at a crash = re-run
            attempts.try_emplace(id, 0);
        }
    }

    static bool done(State s) { return s == State::Succeeded || s == State::Skipped; }
    State state(const std::string& id) const {
        std::scoped_lock l(jm_);
        return journal_.at(id);
    }
    std::map<std::string, State> journal() const {
        std::scoped_lock l(jm_);
        return journal_;
    }
    bool replace(const std::string& id, State from, State to) {
        std::scoped_lock l(jm_);
        if (journal_.at(id) != from) return false;
        journal_[id] = to;
        return true;
    }

    Run& start() {
        int open = 0;
        for (const auto& [id, s] : wf_->steps) {
            int unsatisfied = 0;
            for (const auto& a : s.after) unsatisfied += !done(state(a));
            waiting_.try_emplace(id, unsatisfied);
            open += !done(state(id));
        }
        remaining_.store(open);
        if (open == 0) finish();
        for (const auto& id : wf_->topo)
            if (!done(state(id)) && waiting_.at(id).load() == 0) schedule(id);
        return *this;
    }

    void schedule(const std::string& id) {
        exec_.execute([this, id] { run_step(wf_->steps.at(id)); });
    }

    bool terminal(const std::string& id, State from, State to) {  // exactly one terminal transition per step
        if (!replace(id, from, to)) return false;
        if (remaining_.fetch_sub(1) == 1) finish();
        return true;
    }

    static bool perform(const std::string& action, int attempt) {
        if (action.starts_with("flaky:")) return attempt > std::stoi(action.substr(6));
        return action != "fail";
    }

    void run_step(const Step& s) {
        if (crashed_.load()) return;
        if (failed_.load()) {  // fail fast: start nothing new after a failure
            if (terminal(s.id, State::Pending, State::Cancelled)) cancel_downstream(s.id);
            return;
        }
        if (!replace(s.id, State::Pending, State::Running)) return;
        if (!std::ranges::all_of(s.when, [&](const Cond& c) { return holds(c, ctx_); })) {
            complete(s, State::Skipped);
            return;
        }
        for (int attempt = 1;; ++attempt) {
            attempts.at(s.id).fetch_add(1);
            if (work_ms_ > 0) std::this_thread::sleep_for(std::chrono::milliseconds(work_ms_));
            if (perform(s.action, attempt)) break;
            if (attempt >= s.retry.max) {
                failed_.store(true);
                terminal(s.id, State::Running, State::Failed);
                cancel_downstream(s.id);
                return;
            }
            const i64 delay = s.retry.backoff_ms << (attempt - 1);  // exponential backoff
            {
                std::scoped_lock l(lm_);
                backoffs.push_back(delay);
            }
            backoff_(delay);
        }
        complete(s, State::Succeeded);
    }

    void complete(const Step& s, State how) {
        if (crash_after_ && *crash_after_ == s.id) {  // the process dies after the work but...
            {
                std::scoped_lock l(jm_);
                journal_[s.id] = how;  // ...the journal write made it to disk
            }
            crashed_.store(true);
            signal();
            return;
        }
        terminal(s.id, State::Running, how);
        for (const auto& d : wf_->dependents.at(s.id))
            if (waiting_.at(d).fetch_sub(1) == 1) schedule(d);  // the LAST parent to finish schedules it, exactly once
    }

    void cancel_downstream(const std::string& id) {  // dependents of a failed step can never run
        std::vector<std::string> todo = wf_->dependents.at(id);
        while (!todo.empty()) {
            const std::string d = todo.back();
            todo.pop_back();
            if (terminal(d, State::Pending, State::Cancelled))
                for (const auto& x : wf_->dependents.at(d)) todo.push_back(x);
        }
    }

    void finish() {
        if (failed_.load())  // saga: undo completed work, dependents before dependencies
            for (auto it = wf_->topo.rbegin(); it != wf_->topo.rend(); ++it) {
                const Step& s = wf_->steps.at(*it);
                if (state(s.id) == State::Succeeded && s.compensate) {
                    {
                        std::scoped_lock l(lm_);
                        compensations.push_back(*s.compensate + "(" + s.id + ")");
                    }
                    std::scoped_lock l(jm_);
                    journal_[s.id] = State::Compensated;
                }
            }
        signal();
    }

    void signal() {
        {
            std::scoped_lock l(fm_);
            finished_ = true;
        }
        fcv_.notify_all();
    }

    std::string await() {
        std::unique_lock l(fm_);
        if (!fcv_.wait_for(l, 30s, [&] { return finished_; })) throw std::runtime_error("workflow stuck");
        std::string out;
        for (const auto& id : wf_->topo) out += std::format("{}{}={}", out.empty() ? "" : " ", id, name(state(id)));
        return out;
    }
};

const std::string kOrder = R"({"name": "order", "steps": [
  {"id": "validate", "action": "ok"},
  {"id": "reserve", "after": ["validate"], "action": "ok", "compensate": "release"},
  {"id": "fraud", "after": ["validate"], "action": "ok"},
  {"id": "loyalty", "after": ["validate"], "action": "ok", "compensate": "revoke-points"},
  {"id": "analytics", "after": ["validate"], "action": "ok"},
  {"id": "charge", "after": ["reserve", "fraud"], "action": "flaky:2", "retry": {"max": 3, "backoffMs": 100}, "compensate": "refund"},
  {"id": "giftwrap", "after": ["reserve"], "action": "ok", "when": [{"field": "giftWrap", "op": "==", "value": true}]},
  {"id": "ship", "after": ["charge"], "action": "ok", "when": [{"field": "total", "op": ">=", "value": 50}]},
  {"id": "email", "after": ["ship", "giftwrap"], "action": "ok"}
]})";

std::string list(const std::vector<std::string>& v) {
    std::string s = "[";
    for (const auto& x : v) s += (s.size() > 1 ? ", " : "") + x;
    return s + "]";
}
std::string list(const std::vector<i64>& v) {
    std::string s = "[";
    for (const i64 x : v) s += std::format("{}{}", s.size() > 1 ? ", " : "", x);
    return s + "]";
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Parse and validate ==");
    const auto wf = std::get<Valid>(check(kOrder)).wf;
    std::println("  order: valid, topological order {}", list(wf->topo));
    const std::vector<std::pair<std::string, std::string>> bad{
        {"a -> b -> c -> a",
         R"({"name":"x","steps":[{"id":"a","after":["c"],"action":"ok"},{"id":"b","after":["a"],"action":"ok"},{"id":"c","after":["b"],"action":"ok"}]})"},
        {"unknown dependency", R"({"name":"x","steps":[{"id":"a","after":["zzz"],"action":"ok"}]})"},
        {"duplicate id", R"({"name":"x","steps":[{"id":"a","action":"ok"},{"id":"a","action":"ok"}]})"},
        {"broken JSON", R"({"name":"x","steps":[{"id":"a" "action":"ok"}]})"}};
    for (const auto& [label, text] : bad) {
        const Checked c = check(text);
        std::println("  {:<20} -> {}", label, std::holds_alternative<Invalid>(c) ? std::get<Invalid>(c).reason : "valid?!");
    }

    const std::map<std::string, JValue> ctx{{"total", {72.0}}, {"giftWrap", {false}}}, ctx_gift{{"total", {72.0}}, {"giftWrap", {true}}};
    std::println("== 2. Run in parallel (a thread per ready step, 50 ms of work per attempt), total = 72, no gift wrap ==");
    std::vector<i64> recorded;
    std::mutex rm;
    std::string summary2;
    int total_attempts = 0, charge_attempts = 0;
    bool gift_skipped = false, email_done = false;
    const auto t0 = std::chrono::steady_clock::now();
    {
        ThreadPerTask exec;
        Run run(wf, ctx, {}, exec, [&](i64 ms) { std::scoped_lock l(rm); recorded.push_back(ms); }, 50, std::nullopt);
        summary2 = run.start().await();
        for (const auto& [id, n] : run.attempts) total_attempts += n.load();
        charge_attempts = run.attempts.at("charge").load();
        gift_skipped = run.state("giftwrap") == State::Skipped;
        email_done = run.state("email") == State::Succeeded;
    }
    const i64 wall_ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    std::println("  {}", summary2);
    std::println("  attempts: charge {} (flaky:2, max 3) | backoffs requested {} ms | {} attempts x 50 ms = {} ms of work in {} ms wall"
                 " (critical path validate-reserve-charge x3-ship-email = 7 attempts = 350 ms)",
                 charge_attempts, list(recorded), total_attempts, total_attempts * 50, wall_ms);

    std::println("== 3. Failure: charge fails 3 times -> cancel what can't run, compensate what ran (reverse topological order) ==");
    std::string order_fail = kOrder;
    order_fail.replace(order_fail.find("\"flaky:2\""), 9, "\"fail\"");
    const auto failing = std::get<Valid>(check(order_fail)).wf;
    std::vector<std::string> comps;
    std::vector<i64> backoffs3;
    State charge3{}, ship3{};
    {
        FixedPool one(1);  // one thread: a deterministic interleaving
        Run r3(failing, ctx_gift, {}, one, [](i64) {}, 0, std::nullopt);
        std::println("  {}", r3.start().await());
        comps = r3.compensations;
        backoffs3 = r3.backoffs;
        charge3 = r3.state("charge");
        ship3 = r3.state("ship");
    }
    std::println("  compensations run: {} | backoffs {} ms", list(comps), list(backoffs3));

    std::println("== 4. Crash right after 'charge' succeeds, then resume from the journal ==");
    std::map<std::string, State> journal;
    {
        FixedPool one(1);
        Run first(wf, ctx, {}, one, [](i64) {}, 0, std::string("charge"));
        first.start().await();
        journal = first.journal();
    }
    std::string j;
    for (const auto& [id, st] : journal) j += std::format("{}{}={}", j.empty() ? "" : ", ", id, name(st));
    std::println("  journal at the crash: {{{}}}", j);
    std::map<std::string, int> re_run;
    State email4{};
    {
        FixedPool one(1);
        Run resumed(wf, ctx, journal, one, [](i64) {}, 0, std::nullopt);
        std::println("  resumed: {}", resumed.start().await());
        for (const auto& [id, n] : resumed.attempts)
            if (n.load() > 0) re_run[id] = n.load();
        email4 = resumed.state("email");
    }
    std::string rr;
    for (const auto& [id, n] : re_run) rr += std::format("{}{}={}", rr.empty() ? "" : ", ", id, n);
    std::println("  steps executed by the resumed run: {{{}}} (validate and charge were not re-run)", rr);

    std::println("== 5. Fan-in: 64 parents finish concurrently, one join step; 2,000 rounds on 8 threads ==");
    int naive_doubles = 0, atomic_doubles = 0;
    {
        FixedPool pool(8);
        for (int round = 0; round < 2'000; ++round)
            for (int mode = 0; mode < 2; ++mode) {
                std::mutex sm;
                std::set<int> done_parents;  // a concurrent set: each operation is atomic, the pair is not
                std::atomic<int> waiting_for{64}, join_runs{0}, finished{0};
                for (int p = 0; p < 64; ++p)
                    pool.execute([&, p, mode] {
                        if (mode == 0) {
                            { std::scoped_lock l(sm); done_parents.insert(p); }
                            sz n;
                            { std::scoped_lock l(sm); n = done_parents.size(); }
                            if (n == 64) join_runs.fetch_add(1);  // "are all my siblings done?"
                        } else if (waiting_for.fetch_sub(1) == 1) {
                            join_runs.fetch_add(1);  // only the last decrement sees 0
                        }
                        finished.fetch_add(1);
                    });
                while (finished.load() < 64) std::this_thread::yield();
                if (join_runs.load() != 1) ++(mode == 0 ? naive_doubles : atomic_doubles);
            }
    }
    std::println("  'all parents done?' check by each parent: join ran != once in {} of 2000 rounds", naive_doubles);
    std::println("  atomic in-degree, decrementAndGet() == 0: join ran != once in {} of 2000 rounds", atomic_doubles);

    const Checked cyc = check(bad[0].second);
    const bool ok = wf->topo.front() == "validate" && wf->topo.back() == "email" && wf->topo.size() == 9 && std::holds_alternative<Invalid>(cyc) &&
                    std::get<Invalid>(cyc).reason.find("->") != std::string::npos && gift_skipped && email_done && charge_attempts == 3 &&
                    recorded == std::vector<i64>{100, 200} && wall_ms < total_attempts * 50 && charge3 == State::Failed && ship3 == State::Cancelled &&
                    comps == std::vector<std::string>{"release(reserve)", "revoke-points(loyalty)"} && journal.at("charge") == State::Succeeded &&
                    !re_run.contains("charge") && !re_run.contains("validate") && email4 == State::Succeeded && atomic_doubles == 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Parse and validate ==
  order: valid, topological order [validate, analytics, fraud, loyalty, reserve, charge, giftwrap, ship, email]
  a -> b -> c -> a     -> cycle: a -> b -> c -> a
  unknown dependency   -> step a depends on unknown step zzz
  duplicate id         -> duplicate step id a
  broken JSON          -> bad JSON: expected } at 31
== 2. Run in parallel (a thread per ready step, 50 ms of work per attempt), total = 72, no gift wrap ==
  validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=SUCCEEDED reserve=SUCCEEDED charge=SUCCEEDED giftwrap=SKIPPED ship=SUCCEEDED email=SUCCEEDED
  attempts: charge 3 (flaky:2, max 3) | backoffs requested [100, 200] ms | 10 attempts x 50 ms = 500 ms of work in 445 ms wall (critical path validate-reserve-charge x3-ship-email = 7 attempts = 350 ms)
== 3. Failure: charge fails 3 times -> cancel what can't run, compensate what ran (reverse topological order) ==
  validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=COMPENSATED reserve=COMPENSATED charge=FAILED giftwrap=CANCELLED ship=CANCELLED email=CANCELLED
  compensations run: [release(reserve), revoke-points(loyalty)] | backoffs [100, 200] ms
== 4. Crash right after 'charge' succeeds, then resume from the journal ==
  journal at the crash: {analytics=SUCCEEDED, charge=SUCCEEDED, email=PENDING, fraud=SUCCEEDED, giftwrap=PENDING, loyalty=SUCCEEDED, reserve=SUCCEEDED, ship=PENDING, validate=SUCCEEDED}
  resumed: validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=SUCCEEDED reserve=SUCCEEDED charge=SUCCEEDED giftwrap=SKIPPED ship=SUCCEEDED email=SUCCEEDED
  steps executed by the resumed run: {email=1, ship=1} (validate and charge were not re-run)
== 5. Fan-in: 64 parents finish concurrently, one join step; 2,000 rounds on 8 threads ==
  'all parents done?' check by each parent: join ran != once in 525 of 2000 rounds
  atomic in-degree, decrementAndGet() == 0: join ran != once in 0 of 2000 rounds
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Parse and validate ==
  order: valid, topological order [validate, analytics, fraud, loyalty, reserve, charge, giftwrap, ship, email]
  a -> b -> c -> a     -> cycle: a -> b -> c -> a
  unknown dependency   -> step a depends on unknown step zzz
  duplicate id         -> duplicate step id a
  broken JSON          -> bad JSON: expected } at 31
== 2. Run in parallel (a thread per ready step, 50 ms of work per attempt), total = 72, no gift wrap ==
  validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=SUCCEEDED reserve=SUCCEEDED charge=SUCCEEDED giftwrap=SKIPPED ship=SUCCEEDED email=SUCCEEDED
  attempts: charge 3 (flaky:2, max 3) | backoffs requested [100, 200] ms | 10 attempts x 50 ms = 500 ms of work in 430 ms wall (critical path validate-reserve-charge x3-ship-email = 7 attempts = 350 ms)
== 3. Failure: charge fails 3 times -> cancel what can't run, compensate what ran (reverse topological order) ==
  validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=COMPENSATED reserve=COMPENSATED charge=FAILED giftwrap=CANCELLED ship=CANCELLED email=CANCELLED
  compensations run: [release(reserve), revoke-points(loyalty)] | backoffs [100, 200] ms
== 4. Crash right after 'charge' succeeds, then resume from the journal ==
  journal at the crash: {analytics=SUCCEEDED, charge=SUCCEEDED, email=PENDING, fraud=SUCCEEDED, giftwrap=PENDING, loyalty=SUCCEEDED, reserve=SUCCEEDED, ship=PENDING, validate=SUCCEEDED}
  resumed: validate=SUCCEEDED analytics=SUCCEEDED fraud=SUCCEEDED loyalty=SUCCEEDED reserve=SUCCEEDED charge=SUCCEEDED giftwrap=SKIPPED ship=SUCCEEDED email=SUCCEEDED
  steps executed by the resumed run: {email=1, ship=1} (validate and charge were not re-run)
== 5. Fan-in: 64 parents finish concurrently, one join step; 2,000 rounds on 8 threads ==
  'all parents done?' check by each parent: join ran != once in 116 of 2000 rounds
  atomic in-degree, decrementAndGet() == 0: join ran != once in 0 of 2000 rounds
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Definition | Steps hard-coded in order | JSON list with dependencies | Validated DAG (cycle path, unknown deps, duplicates), unique topological order, typed model only from the validator |
| Execution | Sequential loop | Thread pool, wait for all parents | Atomic in-degree (last parent schedules), parallel ready steps, rules with skip-as-satisfied |
| Failure | Exception propagates; partial state left | Retry | Exponential backoff via an injected sleeper; fail-fast cancellation propagated downstream; saga compensation in reverse topological order |
| Durability | None | Status column per step | Journal of step states; resume recomputes in-degrees; RUNNING at the crash means re-run with idempotent actions |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Steps can wait for a human approval" | A WAITING state persisted in the journal; an external event moves it to SUCCEEDED and decrements dependents. The run thread doesn't block |
| "Timeouts per step" | Attempt runs with a deadline (`orTimeout` / `StructuredTaskScope.joinUntil`); a timeout is a failed attempt and enters the retry policy |
| "Compensation itself fails" | Retry the compensation with backoff; after N failures mark COMPENSATION_FAILED and alert. Never silently stop: a half-compensated saga needs a human |
| "Dynamic fan-out: one step per order line" | A step's output declares children; the engine adds nodes and edges to the run (not the definition), validates acyclicity incrementally, and bumps the join's in-degree **before** scheduling the children |
| "Thousands of workflows per second" | Journals in a database (one row per step, conditional updates as the CAS) and workers claiming ready steps with `SKIP LOCKED` ([P15](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/05-problem-15-ecommerce-flash-sale-inventory-reservation-and-cart-rules.md)) |
| "Version the workflow definition" | Runs pin the definition version they started with; new runs get the new version; in-flight runs finish on the old one |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "When does the join step start?"</b></summary>

**L5:** "When a parent finishes it checks whether all parents are done."

**Why it fails:** several parents see "all done" at once. Measured: the join ran more than once in 32 / 525 / 116 of 2,000 rounds.

**L7 defence:** "Each step has an atomic in-degree; parents decrement it, and only the decrement that reaches zero schedules the child. Exactly once by construction, with no lock."
</details>

<details>
<summary><b>Q2 ⚡ "Payment failed after inventory was reserved. Now what?"</b></summary>

**L5:** "Roll back the transaction."

**Why it fails:** there's no transaction spanning the inventory service, the loyalty service and the payment provider.

**L7 defence:** "A saga. Stop starting new steps, cancel everything downstream of the failure, and run compensations for completed steps in reverse topological order, so dependents are undone before their dependencies. Compensations are idempotent and retried, and a failed compensation pages a human."
</details>

<details>
<summary><b>Q3 ⚡ "The orchestrator restarts mid-run."</b></summary>

**L5:** "Start the workflow again."

**Why it fails:** steps that already charged or shipped run again.

**L7 defence:** "Every step transition is journaled; on restart, recompute in-degrees from the journal and schedule only what's ready. The shown resume re-ran just `ship` and `email`. A step recorded RUNNING is re-run, so actions take an idempotency key."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Workflow never finishes | A cancelled step's dependents never become terminal | Every cancellation propagates downstream; one terminal transition per step |
| Join runs twice | "All parents done?" check | Atomic in-degree, last-decrement-schedules |
| Retry storm | Immediate retries | Exponential backoff (injected), capped attempts |
| Partial side effects after failure | No compensation | Saga: reverse-topological compensation |
| Duplicate charges after a restart | No journal / non-idempotent actions | Journal + resume + idempotency keys |
| "Invalid workflow" with no hint | Cycle detection without a path | Report the cycle path |

- [ ] Validation: JSON, duplicates, unknown dependencies, cycle path; unique topological order.
- [ ] Atomic in-degree scheduling; one terminal transition per step; run completes when open steps reach 0.
- [ ] Rules with explicit skip semantics; retries with injected backoff.
- [ ] Fail fast, cancel downstream, compensate in reverse topological order.
- [ ] Journal + resume; idempotent actions.

## 10. References

- Garcia-Molina and Salem, *Sagas* (SIGMOD 1987). <https://doi.org/10.1145/38713.38742>
- Kahn, *Topological sorting of large networks* (CACM 1962). <https://doi.org/10.1145/368996.369025>
- JEP 505, *Structured Concurrency (Fifth Preview)*. <https://openjdk.org/jeps/505>
- Temporal documentation, *Workflows* (durable execution with an event history). <https://docs.temporal.io/workflows>
- In this KB: [07.3 Parallel DAG executor](../07-Classic-Multithreading-Synchronization-Bar-Raisers/03-parallel-dag-task-executor-with-completablefuture-and-virtual-threads.md) · [P13 Idempotency keys](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md) · [P14 Sagas in a machine](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/04-problem-14-vending-machine-and-atm-dispense-chain-and-state-rollback.md)
