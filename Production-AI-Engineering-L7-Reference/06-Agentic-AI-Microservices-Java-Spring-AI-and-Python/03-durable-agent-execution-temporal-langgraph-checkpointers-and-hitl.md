# 03 · Durable Agent Execution: Temporal, LangGraph Checkpointers, and Human-in-the-Loop

> **Folder:** `06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/` · **File 3 of 3**
> **Anchoring systems and research:** Temporal (event history, deterministic replay, activities, signals and
> updates, `Workflow.getVersion`, continue-as-new) · LangGraph **1.2.18** persistence (checkpointers,
> `interrupt()` / `Command(resume=…)`, `durability`, pending writes, `RetryPolicy`; `langgraph-checkpoint` 4.3.1,
> `langgraph-checkpoint-sqlite` 3.1.2, installed and crashed below) · H. Garcia-Molina and K. Salem, *Sagas*
> (SIGMOD 1987) · P. Helland, *Life beyond Distributed Transactions* (CIDR 2007).
> **Code baseline:** Java 21 (JDK 25.0.4, `--release 21`, no dependencies) · Python 3.10+ (CPython 3.14.5,
> `langgraph` 1.2.18).
> **Previous:** [02 · Spring AI, LangChain4j, virtual threads, SSE](02-spring-ai-langchain4j-virtual-threads-sse-streaming-and-advisors.md) ·
> **Next folder:** `07-Production-Code-Blueprints-Java-and-Python/`

---

## 0. The thesis in one paragraph

An agent run is a **long-lived, partially irreversible process** that outlives the processes executing it. A
refund agent that waits a day for a manager's approval will see about five deploys at five deploys a day; held in
memory, it is lost with probability 0.993. Durable execution makes progress survive restarts. It comes in two
models:

- **event-sourced replay** (Temporal, Azure Durable Functions): record every step's result, re-run the workflow code
  from the top, and return recorded results instead of re-executing;
- **state checkpoints** (LangGraph): snapshot the state after every step and resume from the last snapshot.

Neither gives exactly-once side effects. Both re-execute the step that was running when the process died. The lab
kills real processes mid-step and shows what that costs:

- **2 payments without an idempotency key, 1 with it;**
- a notification sent **twice** because it sat in the same LangGraph node as `interrupt()`, which re-runs from its
  first line on resume;
- `durability="exit"` re-running **all four** finished steps after a crash, against one with `"sync"`;
- a deploy that inserts a step into running workflows rejected as **non-determinism** instead of silently
  corrupting them.

**Effectively-once = at-least-once execution + idempotent receivers.** Human approvals are durable waits that hold
no thread, and they must bind to the exact action that was approved.

---

## 1. First principles

### 1.1 Why agents need durability: duration times failure rate

If restarts arrive as a Poisson process with mean interval `τ`, a run of duration `T` survives untouched with
probability `e^(−T/τ)`. With five deploys a day (`τ = 4.8 h`) and rolling restarts:

| Run duration | P(no restart) |
|---|---|
| 15 min (multi-step research agent) | 0.949 |
| 1 h (long tool chain) | 0.812 |
| 24 h (waits for human approval) | 0.0067 |

Add node preemption, OOM kills and spot reclamation and the conclusion is plain: **anything that waits on humans,
or runs longer than a few minutes, must keep its progress outside the process.**

### 1.2 Exactly-once is not available

Take one side-effecting step, such as charging a card, and an orchestrator that records completion. The
orchestrator can either act first and record second, or record first and act second:

- **Act, then record.** A crash between the two leaves the charge done but unrecorded. The step re-runs on recovery
  and the charge happens twice. This is at-least-once.
- **Record, then act.** A crash between the two leaves the step recorded as done but the charge never made. Recovery
  skips it and the charge is lost. This is at-most-once.

No ordering closes the window, because the orchestrator and the payment provider share no atomic commit. Durable
execution systems choose **at-least-once** and push deduplication to the receiver: an **idempotency key** that is
the same on every retry of the same logical step (workflow id + step id), which the provider uses to return the
original result. That is *effectively-once*.

The lab measures exactly this: the process is killed after the payment call and before the step's completion is
checkpointed. On resume the step runs again; the unkeyed ledger has **2** rows and the keyed one **1**.

### 1.3 Two models of durable execution

**Event-sourced replay (Temporal).**

1. The workflow function is ordinary code that calls *activities* (LLM calls, tools, payments) through stubs.
2. Each activity's scheduling and its result become events in an append-only **history** stored by the service.
3. After a crash, a worker re-runs the workflow function **from the beginning**. Each activity call is matched
   against history by position: if the result is recorded it is returned immediately, with no side effect; the
   first unrecorded call actually executes.
4. Waits (`Workflow.await`, timers, signals) are history events too, so a workflow waiting three days holds **no
   thread and no memory**; it is just history until the signal arrives.

The price is **determinism**: replay must make the same calls in the same order. Workflow code may not read the
wall clock, generate random numbers, do I/O or iterate unordered collections, except through the SDK
(`Workflow.currentTimeMillis()`, `Workflow.newRandom()`, `Workflow.sideEffect`). LLM calls are never made in
workflow code; they are activities, so their non-deterministic outputs are recorded once and replayed forever.
Changing code under running workflows requires **versioning** (`Workflow.getVersion`), otherwise replay hits a
history that no longer matches. The Java engine in §3 detects that: "step 2 was crm_lookup in history, code now
calls fraud_check".

**State checkpoints (LangGraph).**

1. The graph executes in Pregel-style super-steps. After each one, the checkpointer writes the full channel state
   plus metadata, keyed by `thread_id`.
2. A resume loads the latest checkpoint and continues with the nodes in `next`.
3. **The re-execution unit is the node.** A node that was running when the process died, or that raised
   `interrupt()`, runs again **from its first line**. On resume, `interrupt()` returns the value from
   `Command(resume=…)` instead of raising.
4. There is no determinism requirement across nodes, because state is snapshotted rather than reconstructed. Inside
   a node with several `interrupt()` calls, resume values are matched by order, so the calls must not be reordered
   conditionally.

| | Temporal (replay) | LangGraph (checkpoints) |
|---|---|---|
| What is persisted | events: activity scheduled/completed, signals, timers | full state after every super-step |
| Re-execution unit | the one activity in flight | the whole node in flight |
| Determinism | required for workflow code; versioning API | not required across nodes |
| Waiting for humans | signals / updates + `Workflow.await(timeout, cond)` | `interrupt()` + `Command(resume=…)` |
| Parallelism | async activities, child workflows | parallel branches; **pending writes** keep finished siblings |
| Long runs | history limits → continue-as-new | checkpoint growth → pruning / TTL |
| Operations | a Temporal cluster (or Cloud) and workers | a database (Postgres, SQLite) and your service |

### 1.4 What durability costs

- **Latency.** `durability="sync"` writes a checkpoint before the next step starts. A Postgres commit of ~1–5 ms
  against a model step of 400 ms or more is around 1% overhead, so for agents synchronous durability is almost
  always the right default. `"async"` overlaps the write with the next step and can lose the last step on a crash;
  `"exit"` writes only when the run exits or pauses. The lab shows `"exit"` redoing all four steps after a crash in
  step 4 (executions `[2, 2, 2, 2]`) against `[1, 1, 1, 2]` with `"sync"`.
- **Storage.** A checkpoint holds the state at that step. An agent whose state carries a growing message list
  writes a growing snapshot every step. Keep large artefacts (documents, tool payloads, transcripts) in a blob
  store and checkpoint references to them (the *claim-check* pattern), and prune old checkpoints with a TTL.
- **History limits.** Temporal caps history per workflow run, with warnings well before the hard limit (⚠ verify
  your server's limits; tens of thousands of events or tens of MB). A conversational agent that loops forever must
  **continue-as-new** periodically, carrying a compact summary forward.

### 1.5 Human-in-the-loop as a durable wait

A human approval is the longest step in most enterprise agents. Design rules:

1. **The wait must be durable and thread-free.** `Workflow.await(Duration.ofHours(48), () -> approval != null)` in
   Temporal; `interrupt()` plus a checkpoint in LangGraph. The lab's approval survived a process exit, and the
   resume happened in a different process.
2. **Approvals time out and escalate.** A wait with no deadline turns into a run that hangs forever.
3. **Approve what you saw.** The approval must carry a hash of the exact proposed action (order, amount, account).
   On resume, the workflow verifies the hash before acting, so a changed plan cannot execute under an old approval.
4. **Side effects never sit in the same LangGraph node as `interrupt()`**, because that node re-runs on resume. In
   the lab, the notification inside the interrupt node was sent **2** times; the one in its own node before it,
   **1**.
5. **The approval is audit evidence:** who approved, when, and what. A replay history or checkpoint history (8
   checkpoints for one refund thread) records it for free.

---

## 2. Temporal in Java: the production shape

The blueprint below is **not executed here**: it needs a Temporal service and the `io.temporal:temporal-sdk`
artifact. The API names are from the Temporal Java SDK (⚠ verify against the SDK version you deploy). §3 executes
the same semantics in a self-contained engine.

```java
@WorkflowInterface
public interface RefundAgentWorkflow {
    @WorkflowMethod String run(String orderId);
    @SignalMethod void decide(Approval decision);          // the human's answer arrives as a durable signal
    @QueryMethod String status();
}

public record Approval(boolean approved, String by, String actionHash) {}

@ActivityInterface
public interface AgentActivities {
    String llmPlan(String request);
    String crmLookup(String orderId);
    String issueRefund(String orderId, long cents);         // side effect: idempotent by key
    String llmSummarize(String facts);
}

public final class RefundAgentWorkflowImpl implements RefundAgentWorkflow {
    private final AgentActivities llm = Workflow.newActivityStub(AgentActivities.class,
            ActivityOptions.newBuilder()
                    .setStartToCloseTimeout(Duration.ofSeconds(60))
                    .setRetryOptions(RetryOptions.newBuilder().setMaximumAttempts(5).setBackoffCoefficient(2.0).build())
                    .build());
    private final AgentActivities payments = Workflow.newActivityStub(AgentActivities.class,
            ActivityOptions.newBuilder()
                    .setStartToCloseTimeout(Duration.ofSeconds(30))
                    .setRetryOptions(RetryOptions.newBuilder().setMaximumAttempts(3)
                            .setDoNotRetry(IllegalArgumentException.class.getName()).build())
                    .build());
    private Approval decision;
    private String status = "planning";

    @Override
    public String run(String orderId) {
        String plan = llm.llmPlan("refund request for " + orderId);      // LLM output recorded once, replayed forever
        String facts = llm.crmLookup(orderId);
        String proposed = orderId + ":2500";
        status = "awaiting approval of " + proposed;
        boolean answered = Workflow.await(Duration.ofHours(48), () -> decision != null);   // durable timer, no thread
        if (!answered) return "escalated: no decision within 48 h";
        if (!decision.approved()) return "rejected by " + decision.by();
        if (!decision.actionHash().equals(sha256(proposed))) return "approval does not match the proposed action";
        int v = Workflow.getVersion("fraud-check", Workflow.DEFAULT_VERSION, 1);
        if (v >= 1) llm.crmLookup("fraud:" + orderId);                     // only for runs started after this deploy
        String receipt = payments.issueRefund(orderId, 2500);
        status = "done";
        return llm.llmSummarize(plan + " / " + facts + " / " + receipt);
    }

    @Override public void decide(Approval a) { this.decision = a; }

    @Override public String status() { return status; }
}

// Activity side: the idempotency key is stable across retries of the same activity in the same workflow.
public String issueRefund(String orderId, long cents) {
    ActivityInfo info = Activity.getExecutionContext().getInfo();
    String key = info.getWorkflowId() + ":" + info.getActivityId();
    return paymentsClient.refund(orderId, cents, key);                    // provider dedups on Idempotency-Key
}
```

What each line buys:

- LLM and CRM calls are activities with their own timeouts and retries; the workflow never calls a model directly.
- The payment stub has a separate retry policy and a non-retryable error class for business rejections.
- The approval is a signal stored in history; `Workflow.await` with a timeout gives escalation; the action hash
  enforces "approve what you saw".
- `getVersion` lets new runs take the new path while in-flight runs replay the old one.
- The idempotency key comes from workflow id + activity id, not from anything the model chose.
- `sha256(...)` is a deterministic helper; it is safe in workflow code because it does no I/O.

---

## 3. Production code blueprints

### 3.1 Java 21: a replay engine in the Temporal style, small enough to read

The engine journals `SCHEDULED` and `COMPLETED` events to an append-only file with `SYNC` writes and re-runs the
workflow function from the top on every `run`. A recorded `COMPLETED` returns its result with no side effect. The
idempotency key is `workflowId:sequence`, so it is identical on every retry of the same step. `awaitSignal`
suspends by throwing (no thread waits), and a recorded step whose name no longer matches the code raises
`NonDeterminism`.

The self-test is a refund agent:

1. run 1 suspends at the approval;
2. a signal arrives; run 2 is killed inside `issue_refund` after the payment provider has acted;
3. a **new engine instance** (a restarted process) replays the journal and finishes;
4. the agent's LLM was called twice in total, the CRM once, and the provider charged once.

```java
// DurableWorkflowEngine.java - Java 21 durable execution in the Temporal style, small enough to read: workflow code is
// REPLAYED against an append-only event journal on disk. Completed activities are never re-executed (their recorded
// results are returned), activities with external side effects carry idempotency keys so a crash between "side effect
// happened" and "completion recorded" is harmless, human-in-the-loop waits are durable signals, and a workflow change
// that would alter history is detected as non-determinism instead of silently corrupting a running agent.
// Build & self-test:  javac --release 21 -Xlint:all -Werror -d out DurableWorkflowEngine.java
//                     java -ea -cp out dev.l7.ai.inference.DurableWorkflowEngine
package dev.l7.ai.inference;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;

public final class DurableWorkflowEngine {

    /** One journal line: kind|seq|name|payload (payload has no '|' or newline in this demo). */
    record Event(String kind, int seq, String name, String payload) {
        String line() { return kind + "|" + seq + "|" + name + "|" + payload; }

        static Event parse(String l) {
            String[] p = l.split("\\|", 4);
            return new Event(p[0], Integer.parseInt(p[1]), p[2], p[3]);
        }
    }

    /** Thrown to suspend a workflow that waits for a signal not yet in history. */
    static final class Suspend extends RuntimeException {
        private static final long serialVersionUID = 1L;

        Suspend(String why) { super(why, null, false, false); }
    }

    static final class NonDeterminism extends RuntimeException {
        private static final long serialVersionUID = 1L;

        NonDeterminism(String why) { super(why); }
    }

    /** Simulated process death: not caught by retries, the journal survives. */
    static final class Crash extends Error {
        private static final long serialVersionUID = 1L;

        Crash(String why) { super(why); }
    }

    public interface Activity { String run(String input, String idempotencyKey) throws Exception; }

    public final class Context {
        private final List<Event> history;
        private int seq;
        final String workflowId;

        Context(String workflowId, List<Event> history) {
            this.workflowId = workflowId;
            this.history = history;
        }

        private Optional<Event> recorded(int s, String kind) {
            return history.stream().filter(e -> e.seq() == s && e.kind().equals(kind)).findFirst();
        }

        /** Replay-or-execute. The idempotency key is derived from workflow id + sequence number. */
        public String activity(String name, String input) {
            int s = ++seq;
            Optional<Event> scheduled = recorded(s, "SCHEDULED");
            if (scheduled.isPresent() && !scheduled.get().name().equals(name))
                throw new NonDeterminism("step " + s + " was " + scheduled.get().name() + " in history, code now calls " + name);
            Optional<Event> done = recorded(s, "COMPLETED");
            if (done.isPresent()) return done.get().payload();                  // replay: no side effect
            if (scheduled.isEmpty()) append(new Event("SCHEDULED", s, name, input));
            String key = workflowId + ":" + s;
            Exception last = null;
            for (int attempt = 1; attempt <= 3; attempt++) {
                try {
                    String out = activities.get(name).run(input, key);
                    append(new Event("COMPLETED", s, name, out));
                    return out;
                } catch (Exception e) {
                    last = e;
                }
            }
            append(new Event("FAILED", s, name, String.valueOf(last.getMessage())));
            throw new IllegalStateException(name + " failed: " + last.getMessage());
        }

        /** Durable human-in-the-loop wait: suspends until the signal is in history (no thread is held). */
        public String awaitSignal(String name) {
            int s = ++seq;
            return history.stream().filter(e -> e.kind().equals("SIGNAL") && e.name().equals(name)).findFirst()
                    .map(Event::payload).orElseThrow(() -> new Suspend("waiting for signal '" + name + "' at step " + s));
        }

        private void append(Event e) {
            history.add(e);
            try {
                Files.writeString(journal(workflowId), e.line() + "\n", StandardCharsets.UTF_8, StandardOpenOption.CREATE,
                        StandardOpenOption.APPEND, StandardOpenOption.SYNC);           // durable before we proceed
            } catch (IOException io) {
                throw new java.io.UncheckedIOException(io);
            }
        }
    }

    private final Path dir;
    final Map<String, Activity> activities = new ConcurrentHashMap<>();

    DurableWorkflowEngine(Path dir) { this.dir = dir; }

    Path journal(String id) { return dir.resolve(id + ".journal"); }

    List<Event> load(String id) throws IOException {
        Path p = journal(id);
        List<Event> out = new ArrayList<>();
        if (Files.exists(p)) for (String l : Files.readAllLines(p, StandardCharsets.UTF_8)) if (!l.isBlank()) out.add(Event.parse(l));
        return out;
    }

    public sealed interface Status permits Completed, Suspended {}

    public record Completed(String result) implements Status {}

    public record Suspended(String reason) implements Status {}

    /** Run (or resume) a workflow by replaying its journal through the workflow code from the top. */
    public Status run(String id, Function<Context, String> workflow) throws IOException {
        List<Event> h = load(id);
        Optional<Event> fin = h.stream().filter(e -> e.kind().equals("WORKFLOW_DONE")).findFirst();
        if (fin.isPresent()) return new Completed(fin.get().payload());
        Context ctx = new Context(id, h);
        try {
            String r = workflow.apply(ctx);
            ctx.append(new Event("WORKFLOW_DONE", 0, "done", r));
            return new Completed(r);
        } catch (Suspend s) {
            return new Suspended(s.getMessage());
        }
    }

    public void signal(String id, String name, String payload) throws IOException {
        Files.writeString(journal(id), new Event("SIGNAL", 0, name, payload).line() + "\n", StandardCharsets.UTF_8,
                StandardOpenOption.CREATE, StandardOpenOption.APPEND, StandardOpenOption.SYNC);
    }

    // ------------------------------------------------------------------ self-test: a refund agent
    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) throws Exception {
        Path dir = Files.createTempDirectory("durable-agent-");
        AtomicInteger llmCalls = new AtomicInteger(), crmCalls = new AtomicInteger(), chargesSent = new AtomicInteger();
        Map<String, String> paymentLedger = new ConcurrentHashMap<>();          // the payment provider's idempotency store
        AtomicInteger crashAfterCharge = new AtomicInteger(1);

        Function<Context, String> refundAgent = ctx -> {
            String plan = ctx.activity("llm_plan", "customer says order A-17 arrived broken");
            String order = ctx.activity("crm_lookup", "A-17");
            String approval = ctx.awaitSignal("manager_approval");                  // human in the loop
            if (!approval.startsWith("approve")) return "refund rejected by manager: " + approval;
            String charge = ctx.activity("issue_refund", "A-17:25.00");
            String note = ctx.activity("llm_summarize", plan + " / " + order + " / " + charge);
            return note;
        };
        DurableWorkflowEngine eng = new DurableWorkflowEngine(dir);
        eng.activities.put("llm_plan", (in, key) -> { llmCalls.incrementAndGet(); return "plan(refund A-17)"; });
        eng.activities.put("crm_lookup", (in, key) -> { crmCalls.incrementAndGet(); return "order A-17 delivered damaged"; });
        eng.activities.put("llm_summarize", (in, key) -> { llmCalls.incrementAndGet(); return "Refunded $25.00 for A-17."; });
        eng.activities.put("issue_refund", (in, key) -> {
            String receipt = paymentLedger.computeIfAbsent(key, k -> { chargesSent.incrementAndGet(); return "rcpt-" + k; });
            if (crashAfterCharge.getAndDecrement() > 0) throw new Crash("process killed after the charge, before recording it");
            return receipt;
        });

        Status s1 = eng.run("wf-1", refundAgent);
        System.out.println("run 1: " + s1 + " | journal " + eng.load("wf-1").stream().map(Event::kind).toList());
        check(s1 instanceof Suspended, "suspends at the human approval");

        eng.signal("wf-1", "manager_approval", "approve (within policy)");
        try {
            eng.run("wf-1", refundAgent);
            check(false, "expected the simulated crash");
        } catch (Crash c) {
            System.out.println("run 2: CRASH -> " + c.getMessage());
        }
        DurableWorkflowEngine restarted = new DurableWorkflowEngine(dir);          // new process, same journal
        restarted.activities.putAll(eng.activities);
        Status s3 = restarted.run("wf-1", refundAgent);
        System.out.println("run 3 (after restart): " + s3);
        System.out.printf("side effects: LLM calls %d (plan once + summary once), CRM calls %d, charges sent %d, "
                + "ledger entries %d%n", llmCalls.get(), crmCalls.get(), chargesSent.get(), paymentLedger.size());
        check(s3 instanceof Completed && llmCalls.get() == 2 && crmCalls.get() == 1 && chargesSent.get() == 1,
                "replay re-executes nothing that completed; the idempotency key absorbs the crash window");
        check(restarted.run("wf-1", refundAgent).equals(s3) && llmCalls.get() == 2, "a completed workflow is a no-op");

        Function<Context, String> changed = ctx -> {
            ctx.activity("llm_plan", "x");
            ctx.activity("fraud_check", "A-17");                                     // inserted step: changes history
            return "never";
        };
        try {
            restarted.run("wf-2-copy", ctx -> { ctx.activity("llm_plan", "x"); ctx.activity("crm_lookup", "A-17"); return ctx.awaitSignal("x"); });
            restarted.run("wf-2-copy", changed);
            check(false, "non-determinism must be detected");
        } catch (NonDeterminism nd) {
            System.out.println("deploying a changed workflow onto a running instance: " + nd.getMessage());
        }

        eng.signal("wf-3", "manager_approval", "reject: customer abuse history");
        Status s4 = restarted.run("wf-3", refundAgent);
        System.out.println("wf-3 with a rejection signal: " + s4);
        check(s4 instanceof Completed c && c.result().startsWith("refund rejected"), "HITL rejection path");
        System.out.println("all DurableWorkflowEngine self-checks passed");
    }
}
```

Output (verified; deterministic):

```text
run 1: Suspended[reason=waiting for signal 'manager_approval' at step 3] | journal [SCHEDULED, COMPLETED, SCHEDULED, COMPLETED]
run 2: CRASH -> process killed after the charge, before recording it
run 3 (after restart): Completed[result=Refunded $25.00 for A-17.]
side effects: LLM calls 2 (plan once + summary once), CRM calls 1, charges sent 1, ledger entries 1
deploying a changed workflow onto a running instance: step 2 was crm_lookup in history, code now calls fraud_check
wf-3 with a rejection signal: Completed[result=refund rejected by manager: reject: customer abuse history]
all DurableWorkflowEngine self-checks passed
```

What it leaves out compared with Temporal: timers, task queues and worker routing, history limits and
continue-as-new, activity heartbeats, versioning markers, and a replicated store. The semantics that matter to an
agent author are the same: recorded results replay, the step in flight re-executes, and keys make that safe.

### 3.2 Python: LangGraph 1.2.18 checkpointers, crashed for real

Every crash is a child process killed with `os._exit(137)` in the middle of a node, and every resume is a new
process opening the same SQLite checkpoint file. External systems are counted in a separate database, so each
re-execution is visible.

```python
"""langgraph_durable_lab.py - durable agent state with LangGraph 1.2 checkpointers, crashed for real.

Every "crash" below is a child process killed with os._exit(137) in the middle of a node (no cleanup, no finally),
and every resume is a NEW process reopening the same SQLite checkpoint file. External systems (LLM calls, CRM,
payments, notifications) are counted in a separate database so double execution is visible.

1. Human-in-the-loop with interrupt(): pause, survive a restart, resume with Command(resume=...).
   Trap: the node that calls interrupt() RE-RUNS FROM ITS FIRST LINE on resume, so side effects placed before
   interrupt() in the same node happen twice.
2. A crash after a payment side effect but before the node finished: the node re-runs on resume. Only an
   idempotency key (thread id + node) stops the double charge.
3. durability="sync" vs "exit": with "exit", a crash loses every step of the run, so finished work is redone.
4. Parallel branches: a failing branch does not re-run its successful sibling (pending writes), and RetryPolicy
   retries transient failures inside the same run.

Requires: pip install "langgraph==1.2.18" langgraph-checkpoint-sqlite
"""
from __future__ import annotations

import os
import sqlite3
import subprocess
import sys
import tempfile
import threading
from typing import TypedDict

from langgraph.checkpoint.sqlite import SqliteSaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, RetryPolicy, interrupt


# ---------------------------------------------------------------------- the "outside world"
class World:
    """Counters and ledgers that live outside the agent's checkpoint, like real external systems."""

    def __init__(self, path: str):
        self.lock = threading.Lock()                           # LangGraph runs nodes on worker threads
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS calls(name TEXT PRIMARY KEY, n INTEGER);
            CREATE TABLE IF NOT EXISTS naive_ledger(seq INTEGER PRIMARY KEY AUTOINCREMENT, order_id TEXT, cents INTEGER);
            CREATE TABLE IF NOT EXISTS keyed_ledger(idem_key TEXT PRIMARY KEY, order_id TEXT, cents INTEGER);
            CREATE TABLE IF NOT EXISTS crashes(key TEXT PRIMARY KEY);""")

    def count(self, name: str) -> None:
        with self.lock:
            self.db.execute("INSERT INTO calls VALUES(?, 1) ON CONFLICT(name) DO UPDATE SET n = n + 1", (name,))
            self.db.commit()

    def calls(self) -> dict:
        with self.lock:
            return dict(self.db.execute("SELECT name, n FROM calls ORDER BY name"))

    def crash_once(self, key: str) -> None:
        """Kill this process the first time `key` is reached (state already committed elsewhere survives)."""
        if self.db.execute("SELECT 1 FROM crashes WHERE key = ?", (key,)).fetchone() is None:
            self.db.execute("INSERT INTO crashes VALUES(?)", (key,))
            self.db.commit()
            os._exit(137)


class Refund(TypedDict, total=False):
    order: str
    plan: str
    info: str
    approved: bool
    receipt: str
    summary: str


def refund_graph(world: World, saver: SqliteSaver):
    def plan(s: Refund):
        world.count("llm_plan")
        return {"plan": f"refund {s['order']} if damaged"}

    def lookup(s: Refund):
        world.count("crm_lookup")
        return {"info": f"{s['order']} delivered damaged"}

    def notify(s: Refund):                                   # hardened: its own node, BEFORE the interrupt node
        world.count("notify_manager (own node)")
        return {}

    def approval(s: Refund):
        world.count("notify_manager (inside interrupt node)")  # naive: a side effect before interrupt() re-runs
        decision = interrupt({"question": f"Approve refund for {s['order']}?", "facts": s["info"]})
        return {"approved": decision == "approve"}

    def refund(s: Refund, config):
        key = f"{config['configurable']['thread_id']}:refund"        # deterministic idempotency key
        world.db.execute("INSERT INTO naive_ledger(order_id, cents) VALUES(?, ?)", (s["order"], 2500))
        world.db.execute("INSERT OR IGNORE INTO keyed_ledger VALUES(?, ?, ?)", (key, s["order"], 2500))
        world.db.commit()                                      # the payment provider has now acted
        world.crash_once("after-charge")                       # killed before the node's result is checkpointed
        return {"receipt": f"rcpt-{key}"}

    def summarize(s: Refund):
        world.count("llm_summarize")
        return {"summary": f"Refunded {s['order']} ({s['receipt']})" if s.get("approved") else "Refund rejected"}

    g = StateGraph(Refund)
    for name, fn in (("plan", plan), ("lookup", lookup), ("notify", notify), ("approval", approval),
                     ("refund", refund), ("summarize", summarize)):
        g.add_node(name, fn)
    g.add_edge(START, "plan")
    g.add_edge("plan", "lookup")
    g.add_edge("lookup", "notify")
    g.add_edge("notify", "approval")
    g.add_conditional_edges("approval", lambda s: "refund" if s["approved"] else "summarize", ["refund", "summarize"])
    g.add_edge("refund", "summarize")
    g.add_edge("summarize", END)
    return g.compile(checkpointer=saver)


class Ingest(TypedDict, total=False):
    done: list


def ingest_graph(world: World, saver: SqliteSaver, tag: str):
    def step(name):
        def run(s: Ingest):
            world.count(f"{tag}:{name}")
            if name == "n4":
                world.crash_once(f"{tag}:n4")
            return {"done": (s.get("done") or []) + [name]}
        return run

    g = StateGraph(Ingest)
    prev = START
    for n in ("n1", "n2", "n3", "n4"):
        g.add_node(n, step(n))
        g.add_edge(prev, n)
        prev = n
    g.add_edge(prev, END)
    return g.compile(checkpointer=saver)


class Fan(TypedDict, total=False):
    a: str
    b: str
    joined: str


def fan_graph(world: World, saver: SqliteSaver, retry: bool):
    def a(s: Fan):
        world.count(f"fan(retry={retry}):a")
        return {"a": "A"}

    def b(s: Fan):
        world.count(f"fan(retry={retry}):b")
        if world.calls()[f"fan(retry={retry}):b"] < 3:
            raise ConnectionError("upstream 503")
        return {"b": "B"}

    def join(s: Fan):
        return {"joined": s["a"] + s["b"]}

    g = StateGraph(Fan)
    g.add_node("a", a)
    g.add_node("b", b, retry_policy=RetryPolicy(max_attempts=3, initial_interval=0.01, jitter=False) if retry else None)
    g.add_node("join", join)
    g.add_edge(START, "a")
    g.add_edge(START, "b")
    g.add_edge(["a", "b"], "join")
    g.add_edge("join", END)
    return g.compile(checkpointer=saver)


# ---------------------------------------------------------------------- child process entry points
def child(phase: str, work: str, arg: str) -> None:
    world = World(os.path.join(work, "world.db"))
    saver = SqliteSaver(sqlite3.connect(os.path.join(work, "checkpoints.db"), check_same_thread=False))
    cfg = {"configurable": {"thread_id": "refund-A-17"}}
    if phase == "start":
        out = refund_graph(world, saver).invoke({"order": "A-17"}, cfg, durability="sync")
        print(f"   paused: interrupt payload {out['__interrupt__'][0].value}")
    elif phase == "resume":
        g = refund_graph(world, saver)
        out = g.invoke(Command(resume=arg) if arg else None, cfg, durability="sync")
        print(f"   finished: {out.get('summary')}")
    elif phase == "ingest":
        cfg = {"configurable": {"thread_id": f"ingest-{arg}"}}
        g = ingest_graph(world, saver, arg)
        state = g.get_state(cfg)
        out = g.invoke(None if state.next else {"done": []}, cfg, durability=arg)
        print(f"   finished: {out['done']}")


def run_child(work: str, phase: str, arg: str = "") -> int:
    r = subprocess.run([sys.executable, __file__, "--child", phase, work, arg], capture_output=True, text=True,
                       env=dict(os.environ))
    sys.stdout.write(r.stdout)
    if r.returncode not in (0, 137):
        sys.stdout.write(r.stderr[-2000:])
        raise SystemExit(f"child {phase} failed with {r.returncode}")
    return r.returncode


def main() -> None:
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as work:
        print("== 1-2. Refund agent: interrupt, restart, crash after the charge, restart ==")
        print(" process 1: run until the human approval")
        run_child(work, "start")
        world = World(os.path.join(work, "world.db"))
        saver = SqliteSaver(sqlite3.connect(os.path.join(work, "checkpoints.db"), check_same_thread=False))
        st = refund_graph(world, saver).get_state({"configurable": {"thread_id": "refund-A-17"}})
        print(f"   checkpoint on disk: next={st.next}")
        print(" process 2: manager approves -> resume; the process is killed inside `refund` after the charge")
        rc = run_child(work, "resume", "approve")
        print(f"   exit code {rc}")
        st = refund_graph(world, saver).get_state({"configurable": {"thread_id": "refund-A-17"}})
        print(f"   checkpoint on disk: next={st.next}, approved={st.values.get('approved')}")
        print(" process 3: resume from the checkpoint (no new human input needed)")
        run_child(work, "resume", "")
        calls = world.calls()
        naive = world.db.execute("SELECT COUNT(*) FROM naive_ledger").fetchone()[0]
        keyed = world.db.execute("SELECT COUNT(*) FROM keyed_ledger").fetchone()[0]
        print("   external side effects:")
        for k, v in calls.items():
            print(f"     {k:42s} {v}")
        print(f"     {'payments without idempotency key':42s} {naive}")
        print(f"     {'payments with key thread_id:node':42s} {keyed}")
        hist = list(refund_graph(world, saver).get_state_history({"configurable": {"thread_id": "refund-A-17"}}))
        print(f"   checkpoints in this thread's history: {len(hist)} (time travel / audit / fork points)")
        assert calls["llm_plan"] == 1 and calls["crm_lookup"] == 1 and calls["llm_summarize"] == 1
        assert calls["notify_manager (own node)"] == 1 and calls["notify_manager (inside interrupt node)"] == 2
        assert naive == 2 and keyed == 1

        print("\n== 3. durability: a 4-step job killed in step 4, then restarted ==")
        for mode in ("sync", "exit"):
            run_child(work, "ingest", mode)
            run_child(work, "ingest", mode)
            c = world.calls()
            print(f"   durability={mode:4s}: executions n1..n4 = {[c[f'{mode}:n{i}'] for i in range(1, 5)]}")
        c = world.calls()
        assert [c[f"sync:n{i}"] for i in range(1, 5)] == [1, 1, 1, 2]
        assert [c[f"exit:n{i}"] for i in range(1, 5)] == [2, 2, 2, 2]

        print("\n== 4. parallel branches a || b -> join; b fails twice with a transient 503 ==")
        for retry in (False, True):
            g = fan_graph(world, saver, retry)
            cfg = {"configurable": {"thread_id": f"fan-{retry}"}}
            runs = 0
            while True:
                runs += 1
                try:
                    out = g.invoke({} if runs == 1 else None, cfg, durability="sync")
                    break
                except ConnectionError:
                    continue
            c = world.calls()
            print(f"   RetryPolicy={'on ' if retry else 'off'}: invocations {runs}, a ran {c[f'fan(retry={retry}):a']}x, "
                  f"b ran {c[f'fan(retry={retry}):b']}x -> {out['joined']}")
            assert c[f"fan(retry={retry}):a"] == 1 and out["joined"] == "AB"
            assert runs == (1 if retry else 3)
        saver.conn.close()
        world.db.close()
    print("\nall langgraph_durable_lab self-checks passed")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--child":
        child(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")
    else:
        main()
```

Output (verified; deterministic):

```text
== 1-2. Refund agent: interrupt, restart, crash after the charge, restart ==
 process 1: run until the human approval
   paused: interrupt payload {'question': 'Approve refund for A-17?', 'facts': 'A-17 delivered damaged'}
   checkpoint on disk: next=('approval',)
 process 2: manager approves -> resume; the process is killed inside `refund` after the charge
   exit code 137
   checkpoint on disk: next=('refund',), approved=True
 process 3: resume from the checkpoint (no new human input needed)
   finished: Refunded A-17 (rcpt-refund-A-17:refund)
   external side effects:
     crm_lookup                                 1
     llm_plan                                   1
     llm_summarize                              1
     notify_manager (inside interrupt node)     2
     notify_manager (own node)                  1
     payments without idempotency key           2
     payments with key thread_id:node           1
   checkpoints in this thread's history: 8 (time travel / audit / fork points)

== 3. durability: a 4-step job killed in step 4, then restarted ==
   finished: ['n1', 'n2', 'n3', 'n4']
   durability=sync: executions n1..n4 = [1, 1, 1, 2]
   finished: ['n1', 'n2', 'n3', 'n4']
   durability=exit: executions n1..n4 = [2, 2, 2, 2]

== 4. parallel branches a || b -> join; b fails twice with a transient 503 ==
   RetryPolicy=off: invocations 3, a ran 1x, b ran 3x -> AB
   RetryPolicy=on : invocations 1, a ran 1x, b ran 3x -> AB

all langgraph_durable_lab self-checks passed
```

Reading the output:

- **The resume needed no second human input.** Process 2 consumed the approval and checkpointed it before it died
  in `refund`, so `next=('refund',)` with `approved=True`, and process 3 resumed with `invoke(None)`.
- **LLM and CRM calls did not repeat** (1 each): their nodes completed before any crash.
- **Two re-execution effects appear.** The approval node re-ran on resume (notification ×2), and `refund` re-ran
  after the crash (unkeyed payment ×2, keyed ×1).
- **Pending writes.** With branch `b` failing twice and no retry policy, three invocations were needed, but `a` ran
  **once**: its successful write was kept as a pending write of the failed super-step. With `RetryPolicy` the
  retries happen inside one invocation.

---

## 4. Production failure modes and P99 debugging

### F1 · A customer was charged twice after a deploy

- **Signature:** two provider transactions for one workflow step, minutes apart, around a pod restart.
- **Root cause:** at-least-once re-execution of the in-flight step, with no idempotency key (or a key built from
  the attempt number, a timestamp or a random UUID generated inside the step).
- **Fix:** key = workflow/thread id + step id; the provider deduplicates; a reconciliation job compares the ledger
  with workflow state.

### F2 · Notifications and LLM calls repeat when a run resumes

- **Root cause (LangGraph):** side effects in the same node as `interrupt()`, or before a crash point in a
  long node.
- **Fix:** one side effect per node, placed after the interrupt node; split long nodes; key every external write.

### F3 · Workers fail with non-determinism errors after a deploy

- **Root cause (Temporal):** workflow code changed the order or set of commands for runs already in history
  (inserted or removed activities, changed timers, iterated a `HashMap`).
- **Fix:** `Workflow.getVersion` for every behavioural change; replay tests against production histories in CI;
  never read wall time, randomness or I/O in workflow code.
- **LangGraph analogue:** renaming or removing a node that in-flight checkpoints list in `next`. Keep old node names
  until those threads finish, or migrate their state explicitly.

### F4 · Storage and latency grow with run length

- **Signature:** checkpoint tables growing per step; Temporal history size warnings; slow replays for long agents.
- **Root cause:** full transcripts and tool payloads stored in state or history.
- **Fix:** claim-check references to a blob store; message compaction (File 01 §1.3); continue-as-new for unbounded
  conversations; TTL on old checkpoints.

### F5 · Finished work is redone after every crash

- **Root cause:** `durability="exit"` (or `"async"` and a crash right after a step).
- **Fix:** `"sync"` for anything with side effects or expensive LLM calls; the checkpoint write is ~1% of a step.

### F6 · An approval executed a different action than the one approved

- **Root cause:** the plan changed between approval and execution (replanning, edited state, a forked checkpoint),
  and the approval was a bare boolean.
- **Fix:** the approval carries a hash of the exact action and the approver's identity; execution verifies it.

### F7 · Runs wait forever

- **Root cause:** `await` or `interrupt` with no deadline; a lost notification to the approver.
- **Fix:** every wait has a timeout with an escalation path; a dashboard of waiting runs by age.

### F8 · After an outage every workflow resumes at once and the model server falls over

- **Root cause:** thousands of runs resume simultaneously, each making an LLM call.
- **Fix:** worker concurrency limits and task-queue rate limits sized to model goodput; jittered resume; admission
  control at the gateway (File 02 F7).

---

## 5. FAANG L7 bar-raiser Q&A chains

### Q1 · "Our agent may wait up to three days for approvals. How do you build it?"

- **L5 answer:** "Keep the conversation in memory and poll the approval table every minute."
- **Why L5 fails at scale:** at five deploys a day a three-day wait survives in memory with probability about
  e^(−15). Polling threads for thousands of waiting runs waste resources, and nothing prevents a double charge on
  restart.
- **L7 principal defense:**
  1. Durable execution: Temporal workflow or LangGraph with a Postgres checkpointer and `durability="sync"`.
  2. The approval is a durable, thread-free wait (signal + `Workflow.await` with a 48 h timeout, or `interrupt()`),
     with escalation on timeout.
  3. The approval binds to a hash of the proposed action and is recorded with the approver's identity.
  4. Every side effect is an activity or node with an idempotency key from workflow id + step id.
  5. Version the workflow for in-flight runs, and size resume concurrency to model capacity.

### Q2 · "Temporal or LangGraph?"

- **L5 answer:** "LangGraph, because it is made for LLMs."
- **Why L5 fails at scale:** the choice is about the execution model and operations, not the label. Neither makes
  side effects exactly-once.
- **L7 principal defense:**
  1. **LangGraph** when the agent is a graph of LLM steps inside one service, checkpoints in your database are
     enough, and you want `interrupt`, time travel and per-thread state with little operational surface.
  2. **Temporal** when the agent is part of a business process spanning services and days: activity-level
     retries and timeouts, signals and updates, versioning, visibility, and workers across languages.
  3. They compose: a Temporal activity can run a LangGraph graph for the LLM-heavy inner loop.
  4. Either way: idempotency keys, sync durability, versioning discipline, compaction.

### Q3 · "Guarantee the refund happens exactly once."

- **L5 answer:** "Use a transaction" or "Temporal guarantees exactly-once."
- **Why L5 fails at scale:** the orchestrator and the payment provider share no transaction. Durable execution is
  at-least-once for activities. Exactly-once *recording* of a result is not exactly-once *execution*.
- **L7 principal defense:**
  1. State the impossibility (§1.2) and choose at-least-once with an idempotent receiver.
  2. Key = workflow id + step id, sent as the provider's idempotency key and stored in our ledger with a unique
     constraint.
  3. Retry only on retryable errors, reconcile ambiguous outcomes (timeouts) by querying the provider with the key,
     and compensate (refund reversal) as a saga step if a later step fails.
  4. Prove it with a crash test like §3: kill after the provider call and assert one charge.

### Q4 · "We must change the agent's workflow while 10,000 runs are in flight."

- **L5 answer:** "Deploy the new code; the runs will pick it up."
- **Why L5 fails at scale:** with replay, in-flight runs hit non-determinism errors. With checkpoints, renamed nodes
  or changed state schemas strand threads.
- **L7 principal defense:**
  1. Temporal: `Workflow.getVersion` around the change, replay tests against sampled production histories, and
     removal of old branches only after old runs drain.
  2. LangGraph: additive changes (new nodes and edges, optional state keys); keep old node names until threads
     drain; explicit state migration for incompatible changes.
  3. Roll out per cohort and watch the error rate of resumed runs separately from new ones.

### Q5 · "LLMs are non-deterministic. Doesn't that break deterministic replay?"

- **L5 answer:** "Set temperature to zero."
- **Why L5 fails at scale:** temperature 0 is still not bit-reproducible across batch sizes, hardware or model
  versions (Folder 02's batching changes numerics), and the model may be upgraded mid-run.
- **L7 principal defense:**
  1. LLM calls are activities, never workflow code. Their outputs are recorded in history once and replayed from
     history.
  2. Workflow code only branches on recorded values.
  3. The model version used for each call is part of the recorded result, for audit and evaluation.

---

## 6. Invariants checklist

- [ ] Every agent run that waits on humans or lasts longer than a few minutes runs on durable execution.
- [ ] Checkpoint durability is synchronous for steps with side effects or LLM spend.
- [ ] Every external write carries an idempotency key from run id + step id; the receiver deduplicates.
- [ ] One side effect per LangGraph node, never in the node that calls `interrupt()`.
- [ ] LLM calls are activities (Temporal) or nodes (LangGraph), never inline in deterministic workflow code.
- [ ] Every behavioural change is versioned; replay tests run against production histories.
- [ ] Every human wait has a timeout and escalation; approvals bind to an action hash and an identity.
- [ ] Large payloads are stored by reference; long-running conversations continue-as-new or compact.
- [ ] Resume concurrency after outages is bounded by model capacity.

## 7. References

1. Temporal documentation: Workflows, Activities, Event History, Deterministic constraints, Versioning
   (`Workflow.getVersion`), Signals and Updates, Continue-As-New; Temporal Java SDK (⚠ verify against your SDK
   version).
2. LangGraph documentation: Persistence (checkpointers, threads, `get_state_history`), Human-in-the-loop
   (`interrupt`, `Command`), Durable execution (`durability` modes); `langgraph` 1.2.18,
   `langgraph-checkpoint-sqlite` 3.1.2.
3. H. Garcia-Molina, K. Salem. *Sagas.* SIGMOD 1987.
4. P. Helland. *Life beyond Distributed Transactions: an Apostate's Opinion.* CIDR 2007.
5. Microsoft. Azure Durable Functions: orchestrator replay and code constraints (the same event-sourced model).
6. Stripe API reference: Idempotent requests (`Idempotency-Key`), as a canonical receiver-side deduplication design.
