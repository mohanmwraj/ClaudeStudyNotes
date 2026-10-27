# 02.3 · Observer and Event Bus, Command with Undo/Redo, and Double-Dispatch Visitor

> **Folder 02 · File 3 of 3.** Three patterns whose textbook versions break under real conditions:
> - **Observer:** re-entrant publishes reorder causality; one bad subscriber starves the others; "back-pressure" policies silently destroy ordering.
> - **Command:** undo state captured at the wrong moment corrupts history.
> - **Visitor:** solves the wrong problem once Java and C++ have exhaustive pattern matching. Its real job is *double dispatch* and *open* hierarchies.
>
> **Listing pair 2.3.1:** `EventBusCommandVisitor.java` / `event_bus_command_visitor.cpp`. Deterministic sections are identical in Java, GCC and Clang. Ordering-inversion counts and timings are one measured run.

---

## 1. Observer and event bus

### 1.1 The four properties a bus must state 🔥

| Property | Question | The listing's answer |
|---|---|---|
| **Delivery order under re-entrancy** | If a subscriber publishes while handling an event, who sees what first? | Breadth-first: nested publishes are queued per thread and delivered after the current event finishes |
| **Isolation** | Does a throwing subscriber stop delivery to the others? | No. Each call is wrapped, and failures go to a dead-letter list |
| **Subscription lifecycle** | How do you unsubscribe a lambda? | With a **token** (`AutoCloseable` in Java, an RAII `Subscription` in C++). Never `equals`-based removal of lambdas |
| **Concurrency** | Can `subscribe` race with `publish`? | Copy-on-write subscriber lists. Each delivery iterates a stable snapshot, and **no lock is held while user code runs** |

### 1.2 Re-entrancy reorders causality ⚡

The scenario: the payment subscriber reacts to `OrderPlaced` by publishing `PaymentRequested`, and the audit subscriber was registered second. With naive recursive (depth-first) delivery:

```text
publish(OrderPlaced) → payment.on(OrderPlaced) → publish(PaymentRequested) → audit.on(PaymentRequested)
                                                ← return
                    → audit.on(OrderPlaced)
audit log: [PaymentRequested, OrderPlaced]      ← the effect is logged before its cause
```

Breadth-first delivery (a per-thread queue plus a "dispatching" flag) gives `[OrderPlaced, PaymentRequested]` in both languages. Any subscriber that reasons about sequence (audit, projections, sagas) needs this. The C++ version keys its thread-local queue by `(bus, event)`, so two buses nested on one thread don't mix their queues.

### 1.3 Asynchronous delivery: mailboxes, not a shared pool

A shared thread pool processing "deliver event E to subscriber S" tasks gives no per-subscriber order, and one slow subscriber occupies pool threads. The listing gives **each subscriber its own bounded mailbox** (a queue plus one worker thread):
- **Per-subscriber FIFO:** 0 inversions across 150,000 events from 3 producers, for both the fast and the slow subscriber.
- **Isolation:** the slow subscriber (1 ms pause every 10,000 events) delays only its own mailbox.
- **Back-pressure that preserves order:** a full mailbox *blocks the publisher* (`put`).
- **Draining on close:** a poison pill. `close()` restores the interrupt flag rather than throwing `InterruptedException`, because javac's `-Xlint:try` flags an `AutoCloseable` whose `close()` can throw it.

**The trap: `CallerRunsPolicy` is not order-preserving back-pressure.** When a one-thread `ThreadPoolExecutor`'s queue is full, the *producer* runs the task itself, concurrently with the worker that is still draining earlier tasks. One producer, 20,000 sequenced events: **9,383 inversions (Java) / 9,597 (C++)**. It's a fine policy for independent tasks and a correctness bug for ordered streams.

Production analogues:
- per-partition single consumers (Kafka, P4);
- actor mailboxes;
- LMAX-style rings (P17);
- in the JDK, `SubmissionPublisher`, with per-subscriber buffers and `onBackpressureDrop`-style handlers.

## 2. Command: undo/redo that can't corrupt history

### 2.1 The bug the first draft of this listing had

The first version built a macro as `[Insert(0, ">> "), editor.delete(5, 6)]`. The delete captured the text to remove *when the macro was constructed*, but it executed *after* the insert had shifted every position by 3. Undo then "restored" the wrong text, producing `'He worldrld'`. This is the general failure: **captured undo state is only valid against the exact state it was captured from.**

### 2.2 The fix: `apply()` returns its exact inverse

```text
Insert(pos, s).apply(text)  → Delete(pos, s.length())
Delete(pos, len).apply(text) → Insert(pos, removedTextAsOfNow)
Macro(steps).apply(text)    → Macro(inverses in reverse order), each step applied to its predecessors' result
undo: pop an inverse, apply it, and push what it returns (the forward command) onto redo
```

The inverse is computed **at execution time, from the state actually changed**, so a macro step always sees its predecessors' effects. The undo and redo stacks are then symmetric, and both are just command stacks.

Remaining rules:
- **A new edit clears redo.** History forks.
- **Coalesce typing.** Consecutive single-character, non-space inserts at the caret extend the top inverse (`Delete(p, n) → Delete(p, n+1)`), so typing `Hello` is one undo step. A paste or a space starts a new step.
- **Commands are records.** They can be logged, serialized for collaborative editing, and replayed. Chess (P19) uses the same structure, where a move's inverse includes the captured piece.

## 3. Double dispatch: sealed pair switch, classic visitor, multimethod registry

With sealed types (Java) and `std::variant` (C++), the classic *single-dispatch visitor* is a `switch` (file 01.2 §7). What remains for the pattern is **choosing behaviour by two runtime types**, here collision detection between shapes, and **open hierarchies**.

| Approach | Adding a shape | Adding an operation | Checked by | Use when |
|---|---|---|---|---|
| **Sealed pair switch** (Java nested pattern switch; C++ `std::visit(f, a, b)` over two variants) | Edit one function; the compiler lists every missing pair (7 new pairs for a 4th shape) | A new function | **Compiler** | You own the hierarchy (almost always in LLD) |
| **Classic GoF double dispatch** (`collide(other)` → `other.withCircle(this)`) | Edit *every* class (one `withX` each) | Edit every class | Compiler, but scattered | The hierarchy must stay open to subclasses across modules |
| **Multimethod registry** (`Map<(Class, Class), fn>`, symmetric registration) | Register rows at runtime; plugins can add types *and* pairs | Another registry | **Runtime** (missing pair → exception) | Plugin systems, game engines, rule engines |

In the listing all three dispatchers agree on all 25 ordered pairs of 5 sample shapes (11 collide) in both languages. In C++, `std::visit` over two variants instantiates the full 3×3 product, so a missing overload is a compile error. That's the same guarantee as Java's nested sealed switches, from one call.

## 4. Listing 2.3.1 (Java)

```java
// EventBusCommandVisitor.java - observer/event bus (ordering, isolation, mailboxes), command undo/redo, double dispatch
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BiPredicate;

public final class EventBusCommandVisitor {

    // ===== A1. Synchronous bus: isolation, unsubscribe tokens, re-entrant publish ordering ==========

    record Event(String topic, String payload) {}

    @FunctionalInterface
    interface Subscriber {
        void on(Event e) throws Exception;
    }

    static final class SyncBus {
        private static final CopyOnWriteArrayList<Subscriber> NONE = new CopyOnWriteArrayList<>();
        private final ConcurrentHashMap<String, CopyOnWriteArrayList<Subscriber>> subs = new ConcurrentHashMap<>();
        private final boolean breadthFirst;
        private final ThreadLocal<ArrayDeque<Event>> pending = ThreadLocal.withInitial(ArrayDeque::new);
        private final ThreadLocal<boolean[]> dispatching = ThreadLocal.withInitial(() -> new boolean[1]);
        final List<String> deadLetters = Collections.synchronizedList(new ArrayList<>());

        SyncBus(boolean breadthFirst) {
            this.breadthFirst = breadthFirst;
        }

        /** The token is the only way to unsubscribe: no equals()-based removal of lambdas. */
        AutoCloseable subscribe(String topic, Subscriber s) {
            subs.computeIfAbsent(topic, t -> new CopyOnWriteArrayList<>()).add(s);
            return () -> subs.get(topic).remove(s);
        }

        void publish(Event e) {
            if (!breadthFirst) {
                deliver(e);                                    // depth-first: nested publishes jump the queue
                return;
            }
            ArrayDeque<Event> q = pending.get();
            q.add(e);
            boolean[] busy = dispatching.get();
            if (busy[0]) return;                               // re-entrant: the outer loop delivers it, in order
            busy[0] = true;
            try {
                while (!q.isEmpty()) deliver(q.poll());
            } finally {
                busy[0] = false;
            }
        }

        private void deliver(Event e) {
            for (Subscriber s : subs.getOrDefault(e.topic(), NONE)) {   // COW: a stable snapshot per delivery
                try {
                    s.on(e);
                } catch (Exception ex) {                       // one failing subscriber must not starve the rest
                    deadLetters.add(e.payload() + " -> " + ex.getMessage());
                }
            }
        }
    }

    static List<String> reentrancyOrder(boolean breadthFirst) {
        SyncBus bus = new SyncBus(breadthFirst);
        List<String> audit = new ArrayList<>();
        bus.subscribe("order", e -> {                          // the payment service reacts by publishing
            if (e.payload().equals("OrderPlaced")) bus.publish(new Event("order", "PaymentRequested"));
        });
        bus.subscribe("order", e -> audit.add(e.payload()));  // the audit log subscribed second
        bus.publish(new Event("order", "OrderPlaced"));
        return audit;
    }

    // ===== A2. Asynchronous bus: one bounded mailbox per subscriber ================================

    /** Per-subscriber FIFO, a slow subscriber can't delay others, and a full mailbox blocks the publisher. */
    static final class Mailbox implements AutoCloseable {
        private static final Event POISON = new Event("", "");
        private final BlockingQueue<Event> queue;
        private final Thread worker;

        Mailbox(String name, int capacity, Subscriber s) {
            queue = new ArrayBlockingQueue<>(capacity);
            worker = Thread.ofPlatform().name(name).start(() -> {
                try {
                    for (Event e; (e = queue.take()) != POISON; ) {
                        try {
                            s.on(e);
                        } catch (InterruptedException ie) {
                            Thread.currentThread().interrupt();
                            return;
                        } catch (Exception ignored) {          // a real bus routes this to a dead-letter topic
                        }
                    }
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                }
            });
        }

        void post(Event e) throws InterruptedException {
            queue.put(e);                                      // back-pressure that preserves order
        }

        /** AutoCloseable.close() must not throw InterruptedException (javac -Xlint:try): restore the flag. */
        @Override public void close() {
            try {
                queue.put(POISON);                             // drains everything posted before close
                worker.join();
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
            }
        }
    }

    /** Counts per-producer order inversions seen by one subscriber (state confined to its mailbox thread). */
    static final class OrderChecker implements Subscriber {
        final Map<String, Long> last = new HashMap<>();
        long received, inversions;
        final long slowEvery;

        OrderChecker(long slowEvery) {
            this.slowEvery = slowEvery;
        }

        @Override public void on(Event e) throws InterruptedException {
            String[] parts = e.payload().split("-");
            long seq = Long.parseLong(parts[1]);
            Long prev = last.put(parts[0], seq);
            if (prev != null && seq <= prev) inversions++;
            received++;
            if (slowEvery > 0 && received % slowEvery == 0) Thread.sleep(1);
        }
    }

    // ===== B. Command pattern: undo/redo where apply() returns the exact inverse ====================

    static final class Editor {
        /** apply() performs the edit AND returns its inverse, computed from the state it actually changed. */
        sealed interface Command permits Insert, Delete, Macro {
            Command apply(StringBuilder sb);
        }
        record Insert(int pos, String s) implements Command {
            public Command apply(StringBuilder sb) {
                sb.insert(pos, s);
                return new Delete(pos, s.length());
            }
        }
        record Delete(int pos, int len) implements Command {
            public Command apply(StringBuilder sb) {
                String removed = sb.substring(pos, pos + len);   // captured at execution time, never earlier
                sb.delete(pos, pos + len);
                return new Insert(pos, removed);
            }
        }
        record Macro(List<Command> steps) implements Command {
            public Command apply(StringBuilder sb) {
                ArrayDeque<Command> inverse = new ArrayDeque<>();
                for (Command c : steps) inverse.push(c.apply(sb));   // each step sees its predecessors' effects
                return new Macro(List.copyOf(inverse));               // inverses, last step first
            }
        }

        private final StringBuilder text = new StringBuilder();
        private final ArrayDeque<Command> undo = new ArrayDeque<>();  // inverses
        private final ArrayDeque<Command> redo = new ArrayDeque<>();  // forwards
        private boolean lastWasTyping;

        void execute(Command c) {
            Command inverse = c.apply(text);
            redo.clear();                                        // a new edit forks history: redo is gone
            boolean typing = c instanceof Insert in && in.s().length() == 1 && !Character.isWhitespace(in.s().charAt(0));
            if (typing && lastWasTyping && undo.peek() instanceof Delete d && c instanceof Insert in && d.pos() + d.len() == in.pos()) {
                undo.pop();
                undo.push(new Delete(d.pos(), d.len() + 1));     // typing "H","e","l" = ONE undo step
            } else {
                undo.push(inverse);
            }
            lastWasTyping = typing;
        }

        boolean undo() {
            Command inverse = undo.poll();
            if (inverse == null) return false;
            redo.push(inverse.apply(text));                      // the inverse of the inverse is the redo
            lastWasTyping = false;
            return true;
        }

        boolean redo() {
            Command forward = redo.poll();
            if (forward == null) return false;
            undo.push(forward.apply(text));
            lastWasTyping = false;
            return true;
        }

        String state() {
            return "'" + text + "' undo=" + undo.size() + " redo=" + redo.size();
        }
    }

    // ===== C. Double dispatch three ways ============================================================

    sealed interface Shape permits Circle, Rect, Pt {}
    record Circle(double x, double y, double r) implements Shape {}
    record Rect(double x1, double y1, double x2, double y2) implements Shape {}
    record Pt(double x, double y) implements Shape {}

    static boolean circleRect(Circle c, Rect r) {
        double nx = Math.clamp(c.x(), r.x1(), r.x2()), ny = Math.clamp(c.y(), r.y1(), r.y2());
        return (c.x() - nx) * (c.x() - nx) + (c.y() - ny) * (c.y() - ny) <= c.r() * c.r();
    }

    static boolean circleCircle(Circle a, Circle b) {
        double dx = a.x() - b.x(), dy = a.y() - b.y(), rr = a.r() + b.r();
        return dx * dx + dy * dy <= rr * rr;
    }

    static boolean rectRect(Rect a, Rect b) {
        return a.x1() <= b.x2() && b.x1() <= a.x2() && a.y1() <= b.y2() && b.y1() <= a.y2();
    }

    /** C1. Sealed: all 9 pairs, compiler-checked; a 4th shape breaks the build until 7 new pairs exist. */
    static boolean collides(Shape a, Shape b) {
        return switch (a) {
            case Circle c -> switch (b) {
                case Circle d -> circleCircle(c, d);
                case Rect r -> circleRect(c, r);
                case Pt p -> circleCircle(c, new Circle(p.x(), p.y(), 0));
            };
            case Rect r -> switch (b) {
                case Circle c -> circleRect(c, r);
                case Rect s -> rectRect(r, s);
                case Pt p -> rectRect(r, new Rect(p.x(), p.y(), p.x(), p.y()));
            };
            case Pt p -> switch (b) {
                case Circle c -> circleCircle(c, new Circle(p.x(), p.y(), 0));
                case Rect r -> rectRect(r, new Rect(p.x(), p.y(), p.x(), p.y()));
                case Pt q -> p.x() == q.x() && p.y() == q.y();
            };
        };
    }

    /** C2. Classic GoF double dispatch for an OPEN hierarchy: two virtual calls pick the pair. */
    interface Body {
        boolean collide(Body other);                             // first dispatch: on `this`
        boolean withCircle(Circle c);                            // second dispatch: on `other`
        boolean withRect(Rect r);
        boolean withPt(Pt p);
    }
    record CircleBody(Circle shape) implements Body {
        public boolean collide(Body o) { return o.withCircle(shape); }
        public boolean withCircle(Circle c) { return circleCircle(shape, c); }
        public boolean withRect(Rect r) { return circleRect(shape, r); }
        public boolean withPt(Pt p) { return circleCircle(shape, new Circle(p.x(), p.y(), 0)); }
    }
    record RectBody(Rect shape) implements Body {
        public boolean collide(Body o) { return o.withRect(shape); }
        public boolean withCircle(Circle c) { return circleRect(c, shape); }
        public boolean withRect(Rect r) { return rectRect(shape, r); }
        public boolean withPt(Pt p) { return rectRect(shape, new Rect(p.x(), p.y(), p.x(), p.y())); }
    }
    record PtBody(Pt shape) implements Body {
        public boolean collide(Body o) { return o.withPt(shape); }
        public boolean withCircle(Circle c) { return circleCircle(c, new Circle(shape.x(), shape.y(), 0)); }
        public boolean withRect(Rect r) { return rectRect(r, new Rect(shape.x(), shape.y(), shape.x(), shape.y())); }
        public boolean withPt(Pt p) { return shape.x() == p.x() && shape.y() == p.y(); }
    }

    /** C3. Multimethod registry: open in BOTH directions (plugins add types and pairs), checked at runtime. */
    static final class CollisionRegistry {
        private final Map<List<Class<?>>, BiPredicate<Object, Object>> table = new HashMap<>();

        @SuppressWarnings("unchecked")
        <A, B> void register(Class<A> a, Class<B> b, BiPredicate<A, B> f) {
            table.put(List.of(a, b), (x, y) -> f.test((A) x, (B) y));
            table.putIfAbsent(List.of(b, a), (x, y) -> f.test((A) y, (B) x));   // symmetry for free
        }

        boolean collides(Object x, Object y) {
            BiPredicate<Object, Object> f = table.get(List.of(x.getClass(), y.getClass()));
            if (f == null) throw new IllegalStateException("no rule for " + x.getClass().getSimpleName() + " x " + y.getClass().getSimpleName());
            return f.test(x, y);
        }
    }

    static Body body(Shape s) {
        return switch (s) {
            case Circle c -> new CircleBody(c);
            case Rect r -> new RectBody(r);
            case Pt p -> new PtBody(p);
        };
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== A1. Re-entrant publish: the audit log's view of causality ==");
        System.out.println("  depth-first   (recursive delivery) -> " + reentrancyOrder(false));
        System.out.println("  breadth-first (queued delivery)    -> " + reentrancyOrder(true));
        SyncBus bus = new SyncBus(true);
        List<String> got = new ArrayList<>();
        bus.subscribe("t", e -> { if (e.payload().equals("boom")) throw new IllegalStateException("subscriber bug"); });
        AutoCloseable token = bus.subscribe("t", e -> got.add(e.payload()));
        bus.publish(new Event("t", "boom"));
        token.close();
        bus.publish(new Event("t", "after-unsubscribe"));
        System.out.println("  isolation: healthy subscriber got " + got + ", dead letters " + bus.deadLetters);

        System.out.println("== A2. Async mailboxes: 3 publishers x 50,000 events, one fast + one slow subscriber ==");
        OrderChecker fast = new OrderChecker(0), slow = new OrderChecker(10_000);
        long t0 = System.nanoTime();
        try (Mailbox mf = new Mailbox("fast", 256, fast); Mailbox ms = new Mailbox("slow", 256, slow)) {
            CountDownLatch done = new CountDownLatch(3);
            for (int p = 0; p < 3; p++) {
                final String producer = "p" + p;
                Thread.ofPlatform().start(() -> {
                    try {
                        for (long i = 0; i < 50_000; i++) {
                            Event e = new Event("t", producer + "-" + i);
                            mf.post(e);
                            ms.post(e);
                        }
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                    }
                    done.countDown();
                });
            }
            done.await();
        }
        System.out.printf("  fast: received %,d, per-producer inversions %d | slow: received %,d, inversions %d (%.0f ms)%n",
                fast.received, fast.inversions, slow.received, slow.inversions, (System.nanoTime() - t0) / 1e6);

        ThreadPoolExecutor pool = new ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, new ArrayBlockingQueue<>(4),
                new ThreadPoolExecutor.CallerRunsPolicy());
        AtomicLong lastSeen = new AtomicLong(-1), inversions = new AtomicLong();
        for (long i = 0; i < 20_000; i++) {
            final long seq = i;
            pool.execute(() -> {
                if (lastSeen.getAndSet(seq) > seq) inversions.incrementAndGet();
                for (int k = 0; k < 50; k++) Thread.onSpinWait();
            });
        }
        pool.shutdown();
        if (!pool.awaitTermination(10, TimeUnit.SECONDS)) throw new IllegalStateException("pool did not drain");
        System.out.printf("  'back-pressure' via CallerRunsPolicy, one producer: %,d order inversions in 20,000 events%n", inversions.get());

        System.out.println("== B. Command undo/redo (apply() returns the inverse) ==");
        Editor ed = new Editor();
        for (String ch : List.of("H", "e", "l", "l", "o")) ed.execute(new Editor.Insert(ed.text.length(), ch));
        System.out.println("  typed 'Hello' (5 keystrokes)   -> " + ed.state());
        ed.execute(new Editor.Insert(5, " world"));
        System.out.println("  paste ' world'                 -> " + ed.state());
        ed.execute(new Editor.Delete(0, 6));
        System.out.println("  delete(0,6)                    -> " + ed.state());
        ed.undo();
        System.out.println("  undo                           -> " + ed.state());
        ed.undo();
        System.out.println("  undo                           -> " + ed.state());
        ed.redo();
        System.out.println("  redo                           -> " + ed.state());
        ed.execute(new Editor.Macro(List.of(new Editor.Insert(0, ">> "), new Editor.Delete(3, 6))));
        System.out.println("  macro(insert '>> ', delete 6)  -> " + ed.state() + "   (redo history dropped)");
        ed.undo();
        System.out.println("  undo macro (one step)          -> " + ed.state());
        ed.redo();
        System.out.println("  redo macro                     -> " + ed.state());

        System.out.println("== C. Double dispatch: sealed switch vs classic visitor vs multimethod registry ==");
        List<Shape> shapes = List.of(new Circle(0, 0, 1), new Rect(0.5, 0.5, 2, 2), new Pt(1.5, 1.5),
                new Circle(5, 5, 0.5), new Pt(0, 0));
        CollisionRegistry reg = new CollisionRegistry();
        reg.register(Circle.class, Circle.class, EventBusCommandVisitor::circleCircle);
        reg.register(Circle.class, Rect.class, EventBusCommandVisitor::circleRect);
        reg.register(Rect.class, Rect.class, EventBusCommandVisitor::rectRect);
        reg.register(Circle.class, Pt.class, (c, p) -> circleCircle(c, new Circle(p.x(), p.y(), 0)));
        reg.register(Rect.class, Pt.class, (r, p) -> rectRect(r, new Rect(p.x(), p.y(), p.x(), p.y())));
        reg.register(Pt.class, Pt.class, (p, q) -> p.x() == q.x() && p.y() == q.y());
        int pairs = 0, collisions = 0, disagreements = 0;
        StringBuilder matrix = new StringBuilder();
        for (Shape a : shapes) {
            matrix.append("  ");
            for (Shape b : shapes) {
                boolean s = collides(a, b), v = body(a).collide(body(b)), r = reg.collides(a, b);
                if (s != v || s != r) disagreements++;
                pairs++;
                if (s) collisions++;
                matrix.append(s ? 'X' : '.');
            }
            matrix.append('\n');
        }
        System.out.print(matrix);
        System.out.println("  " + pairs + " ordered pairs, " + collisions + " collide, disagreements between the 3 dispatchers: " + disagreements);

        boolean ok = reentrancyOrder(true).equals(List.of("OrderPlaced", "PaymentRequested")) && ed.text.toString().equals(">> world")
                && got.equals(List.of("boom")) && fast.inversions == 0 && slow.inversions == 0
                && fast.received == 150_000 && slow.received == 150_000 && disagreements == 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (inversion counts and timing: one measured run; everything else verified):**

```text
== A1. Re-entrant publish: the audit log's view of causality ==
  depth-first   (recursive delivery) -> [PaymentRequested, OrderPlaced]
  breadth-first (queued delivery)    -> [OrderPlaced, PaymentRequested]
  isolation: healthy subscriber got [boom], dead letters [boom -> subscriber bug]
== A2. Async mailboxes: 3 publishers x 50,000 events, one fast + one slow subscriber ==
  fast: received 150,000, per-producer inversions 0 | slow: received 150,000, inversions 0 (184 ms)
  'back-pressure' via CallerRunsPolicy, one producer: 9,383 order inversions in 20,000 events
== B. Command undo/redo (apply() returns the inverse) ==
  typed 'Hello' (5 keystrokes)   -> 'Hello' undo=1 redo=0
  paste ' world'                 -> 'Hello world' undo=2 redo=0
  delete(0,6)                    -> 'world' undo=3 redo=0
  undo                           -> 'Hello world' undo=2 redo=1
  undo                           -> 'Hello' undo=1 redo=2
  redo                           -> 'Hello world' undo=2 redo=1
  macro(insert '>> ', delete 6)  -> '>> world' undo=3 redo=0   (redo history dropped)
  undo macro (one step)          -> 'Hello world' undo=2 redo=1
  redo macro                     -> '>> world' undo=3 redo=0
== C. Double dispatch: sealed switch vs classic visitor vs multimethod registry ==
  XX..X
  XXX..
  .XX..
  ...X.
  X...X
  25 ordered pairs, 11 collide, disagreements between the 3 dispatchers: 0
SELF-TEST OK
```

## 5. Listing 2.3.1 (C++)

The C++ version adds three idioms:
- an RAII `Subscription` whose destructor unsubscribes;
- a `shared_ptr<const vector>` copy-on-write list, loaded under a short lock and iterated without one;
- a recursive `Command` struct wrapping a variant, which works because `std::vector` of an incomplete type is allowed since C++17.

It also hit the ADL trap from 01.2 a second time: a free function `apply(const Command&, std::string&)` made Clang/libc++ pick `std::apply`. It's named `perform`.

```cpp
// event_bus_command_visitor.cpp - observer/event bus (ordering, isolation, mailboxes), command undo/redo, double dispatch
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <format>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <print>
#include <stdexcept>
#include <string>
#include <thread>
#include <typeindex>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

// ===== A1. Synchronous bus: COW subscriber lists, RAII tokens, isolation, re-entrant ordering ===

struct Event { std::string topic, payload; };
using Handler = std::function<void(const Event&)>;

class SyncBus {
    struct Sub { std::uint64_t id; Handler h; };
    using List = std::vector<Sub>;
    std::mutex m_;
    std::unordered_map<std::string, std::shared_ptr<const List>> subs_;  // copy-on-write per topic
    std::uint64_t next_id_ = 0;
    bool breadth_first_;
    struct Pending { std::deque<std::pair<SyncBus*, Event>> q; bool busy = false; };
    static Pending& pending() {
        thread_local Pending p;  // per thread; holds (bus, event) so nested buses stay separate
        return p;
    }
public:
    std::vector<std::string> dead_letters;  // only appended on the publishing thread in this demo

    explicit SyncBus(bool breadth_first) : breadth_first_(breadth_first) {}

    /** RAII token: unsubscribes in its destructor (the C++ spelling of Java's AutoCloseable token). */
    class Subscription {
        SyncBus* bus_;
        std::string topic_;
        std::uint64_t id_;
    public:
        Subscription(SyncBus* b, std::string t, std::uint64_t id) : bus_(b), topic_(std::move(t)), id_(id) {}
        Subscription(Subscription&& o) noexcept : bus_(std::exchange(o.bus_, nullptr)), topic_(std::move(o.topic_)), id_(o.id_) {}
        Subscription(const Subscription&) = delete;
        Subscription& operator=(const Subscription&) = delete;
        Subscription& operator=(Subscription&&) = delete;
        ~Subscription() {
            if (bus_) bus_->unsubscribe(topic_, id_);
        }
    };

    [[nodiscard]] Subscription subscribe(const std::string& topic, Handler h) {
        std::scoped_lock l(m_);
        auto next = std::make_shared<List>(subs_.contains(topic) ? *subs_[topic] : List{});
        next->push_back(Sub{++next_id_, std::move(h)});
        subs_[topic] = std::move(next);
        return Subscription(this, topic, next_id_);
    }
    void unsubscribe(const std::string& topic, std::uint64_t id) {
        std::scoped_lock l(m_);
        auto next = std::make_shared<List>(*subs_[topic]);
        std::erase_if(*next, [&](const Sub& s) { return s.id == id; });
        subs_[topic] = std::move(next);
    }
    void publish(const Event& e) {
        if (!breadth_first_) {
            deliver(e);  // depth-first: nested publishes jump the queue
            return;
        }
        Pending& p = pending();
        p.q.emplace_back(this, e);
        if (p.busy) return;  // re-entrant: the outer loop delivers it, in order
        p.busy = true;
        while (!p.q.empty()) {
            auto [bus, ev] = std::move(p.q.front());
            p.q.pop_front();
            bus->deliver(ev);
        }
        p.busy = false;
    }
private:
    void deliver(const Event& e) {
        std::shared_ptr<const List> snapshot;
        {
            std::scoped_lock l(m_);
            if (auto it = subs_.find(e.topic); it != subs_.end()) snapshot = it->second;
        }
        if (!snapshot) return;
        for (const auto& s : *snapshot) {  // no lock held while calling user code
            try {
                s.h(e);
            } catch (const std::exception& ex) {
                dead_letters.push_back(e.payload + " -> " + ex.what());
            }
        }
    }
};

std::vector<std::string> reentrancy_order(bool breadth_first) {
    SyncBus bus(breadth_first);
    std::vector<std::string> audit;
    auto a = bus.subscribe("order", [&](const Event& e) {
        if (e.payload == "OrderPlaced") bus.publish({"order", "PaymentRequested"});
    });
    auto b = bus.subscribe("order", [&](const Event& e) { audit.push_back(e.payload); });
    bus.publish({"order", "OrderPlaced"});
    return audit;
}

// ===== A2. Asynchronous bus: one bounded mailbox per subscriber ================================

class Mailbox {  // per-subscriber FIFO; a full mailbox blocks the publisher; destructor drains
    std::mutex m_;
    std::condition_variable not_empty_, not_full_;
    std::deque<std::optional<Event>> q_;  // nullopt = poison pill
    std::size_t cap_;
    std::thread worker_;
public:
    Mailbox(std::size_t cap, Handler h) : cap_(cap) {
        worker_ = std::thread([this, h = std::move(h)] {
            while (true) {
                std::optional<Event> e;
                {
                    std::unique_lock l(m_);
                    not_empty_.wait(l, [&] { return !q_.empty(); });
                    e = std::move(q_.front());
                    q_.pop_front();
                }
                not_full_.notify_one();
                if (!e) return;
                try {
                    h(*e);
                } catch (const std::exception&) {  // a real bus routes this to a dead-letter topic
                }
            }
        });
    }
    void post(Event e) {
        {
            std::unique_lock l(m_);
            not_full_.wait(l, [&] { return q_.size() < cap_; });  // back-pressure that preserves order
            q_.emplace_back(std::move(e));
        }
        not_empty_.notify_one();
    }
    ~Mailbox() {
        {
            std::unique_lock l(m_);
            not_full_.wait(l, [&] { return q_.size() < cap_; });
            q_.emplace_back(std::nullopt);
        }
        not_empty_.notify_one();
        worker_.join();
    }
    Mailbox(const Mailbox&) = delete;
    Mailbox& operator=(const Mailbox&) = delete;
};

struct OrderChecker {  // state confined to the mailbox thread
    std::map<std::string, long long> last;
    long long received = 0, inversions = 0, slow_every = 0;
    void on(const Event& e) {
        const auto dash = e.payload.find('-');
        const long long seq = std::stoll(e.payload.substr(dash + 1));
        auto [it, fresh] = last.try_emplace(e.payload.substr(0, dash), seq);
        if (!fresh) {
            if (seq <= it->second) ++inversions;
            it->second = seq;
        }
        ++received;
        if (slow_every > 0 && received % slow_every == 0) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
};

/** A one-thread pool whose "back-pressure" is caller-runs: when the queue is full the producer runs the task. */
class CallerRunsPool {
    std::mutex m_;
    std::condition_variable cv_;
    std::deque<std::function<void()>> q_;
    std::size_t cap_;
    bool stop_ = false;
    std::thread worker_;
public:
    explicit CallerRunsPool(std::size_t cap) : cap_(cap) {
        worker_ = std::thread([this] {
            while (true) {
                std::function<void()> f;
                {
                    std::unique_lock l(m_);
                    cv_.wait(l, [&] { return stop_ || !q_.empty(); });
                    if (q_.empty()) return;
                    f = std::move(q_.front());
                    q_.pop_front();
                }
                f();
            }
        });
    }
    void execute(std::function<void()> f) {
        {
            std::scoped_lock l(m_);
            if (q_.size() < cap_) {
                q_.push_back(std::move(f));
                cv_.notify_one();
                return;
            }
        }
        f();  // caller runs: concurrently with the worker, so ORDER is lost
    }
    ~CallerRunsPool() {
        {
            std::scoped_lock l(m_);
            stop_ = true;
        }
        cv_.notify_one();
        worker_.join();
    }
};

// ===== B. Command pattern: perform() returns the exact inverse ===================================

struct Command;
struct Insert { std::size_t pos; std::string s; };
struct Delete { std::size_t pos, len; };
struct Macro { std::vector<Command> steps; };  // std::vector of an incomplete type: allowed since C++17
struct Command { std::variant<Insert, Delete, Macro> v; };

// Not named apply(): a std::string argument makes ADL find std::apply (the trap from 01.2, hit again here).
Command perform(const Command& c, std::string& text) {
    return std::visit(overloaded{
        [&](const Insert& i) -> Command {
            text.insert(i.pos, i.s);
            return {Delete{i.pos, i.s.size()}};
        },
        [&](const Delete& d) -> Command {
            std::string removed = text.substr(d.pos, d.len);  // captured at execution time, never earlier
            text.erase(d.pos, d.len);
            return {Insert{d.pos, std::move(removed)}};
        },
        [&](const Macro& m) -> Command {
            Macro inverse;
            for (const auto& step : m.steps) inverse.steps.insert(inverse.steps.begin(), perform(step, text));
            return {std::move(inverse)};
        },
    }, c.v);
}

class Editor {
    std::string text_;
    std::vector<Command> undo_, redo_;  // inverses / forwards
    bool last_was_typing_ = false;
public:
    void execute(const Command& c) {
        Command inverse = perform(c, text_);
        redo_.clear();  // a new edit forks history
        const auto* in = std::get_if<Insert>(&c.v);
        const bool typing = in && in->s.size() == 1 && in->s[0] != ' ';
        const Delete* top = undo_.empty() ? nullptr : std::get_if<Delete>(&undo_.back().v);
        if (typing && last_was_typing_ && top && top->pos + top->len == in->pos)
            undo_.back() = Command{Delete{top->pos, top->len + 1}};  // typing = ONE undo step
        else
            undo_.push_back(std::move(inverse));
        last_was_typing_ = typing;
    }
    bool undo() {
        if (undo_.empty()) return false;
        Command inverse = std::move(undo_.back());
        undo_.pop_back();
        redo_.push_back(perform(inverse, text_));  // the inverse of the inverse is the redo
        last_was_typing_ = false;
        return true;
    }
    bool redo() {
        if (redo_.empty()) return false;
        Command forward = std::move(redo_.back());
        redo_.pop_back();
        undo_.push_back(perform(forward, text_));
        last_was_typing_ = false;
        return true;
    }
    std::size_t size() const { return text_.size(); }
    const std::string& text() const { return text_; }
    std::string state() const { return std::format("'{}' undo={} redo={}", text_, undo_.size(), redo_.size()); }
};

// ===== C. Double dispatch: multi-variant visit, classic visitor, multimethod registry ==========

struct Circle { double x, y, r; };
struct Rect { double x1, y1, x2, y2; };
struct Pt { double x, y; };
using Shape = std::variant<Circle, Rect, Pt>;

bool circle_rect(const Circle& c, const Rect& r) {
    const double nx = std::clamp(c.x, r.x1, r.x2), ny = std::clamp(c.y, r.y1, r.y2);
    return (c.x - nx) * (c.x - nx) + (c.y - ny) * (c.y - ny) <= c.r * c.r;
}
bool circle_circle(const Circle& a, const Circle& b) {
    const double dx = a.x - b.x, dy = a.y - b.y, rr = a.r + b.r;
    return dx * dx + dy * dy <= rr * rr;
}
bool rect_rect(const Rect& a, const Rect& b) { return a.x1 <= b.x2 && b.x1 <= a.x2 && a.y1 <= b.y2 && b.y1 <= a.y2; }
Circle as_circle(const Pt& p) { return {p.x, p.y, 0}; }
Rect as_rect(const Pt& p) { return {p.x, p.y, p.x, p.y}; }

/** C1. std::visit over TWO variants: the compiler instantiates all 9 pairs; a missing one is an error. */
bool collides(const Shape& a, const Shape& b) {
    return std::visit(overloaded{
        [](const Circle& c, const Circle& d) { return circle_circle(c, d); },
        [](const Circle& c, const Rect& r) { return circle_rect(c, r); },
        [](const Circle& c, const Pt& p) { return circle_circle(c, as_circle(p)); },
        [](const Rect& r, const Circle& c) { return circle_rect(c, r); },
        [](const Rect& r, const Rect& s) { return rect_rect(r, s); },
        [](const Rect& r, const Pt& p) { return rect_rect(r, as_rect(p)); },
        [](const Pt& p, const Circle& c) { return circle_circle(c, as_circle(p)); },
        [](const Pt& p, const Rect& r) { return rect_rect(r, as_rect(p)); },
        [](const Pt& p, const Pt& q) { return p.x == q.x && p.y == q.y; },
    }, a, b);
}

/** C2. Classic double dispatch for an open hierarchy: two virtual calls. */
struct Body {
    virtual ~Body() = default;
    virtual bool collide(const Body& other) const = 0;
    virtual bool with(const Circle& c) const = 0;
    virtual bool with(const Rect& r) const = 0;
    virtual bool with(const Pt& p) const = 0;
};
struct CircleBody final : Body {
    Circle s;
    explicit CircleBody(Circle c) : s(c) {}
    bool collide(const Body& o) const override { return o.with(s); }
    bool with(const Circle& c) const override { return circle_circle(s, c); }
    bool with(const Rect& r) const override { return circle_rect(s, r); }
    bool with(const Pt& p) const override { return circle_circle(s, as_circle(p)); }
};
struct RectBody final : Body {
    Rect s;
    explicit RectBody(Rect r) : s(r) {}
    bool collide(const Body& o) const override { return o.with(s); }
    bool with(const Circle& c) const override { return circle_rect(c, s); }
    bool with(const Rect& r) const override { return rect_rect(s, r); }
    bool with(const Pt& p) const override { return rect_rect(s, as_rect(p)); }
};
struct PtBody final : Body {
    Pt s;
    explicit PtBody(Pt p) : s(p) {}
    bool collide(const Body& o) const override { return o.with(s); }
    bool with(const Circle& c) const override { return circle_circle(c, as_circle(s)); }
    bool with(const Rect& r) const override { return rect_rect(r, as_rect(s)); }
    bool with(const Pt& p) const override { return s.x == p.x && s.y == p.y; }
};
std::unique_ptr<Body> body(const Shape& s) {
    return std::visit(overloaded{
        [](const Circle& c) -> std::unique_ptr<Body> { return std::make_unique<CircleBody>(c); },
        [](const Rect& r) -> std::unique_ptr<Body> { return std::make_unique<RectBody>(r); },
        [](const Pt& p) -> std::unique_ptr<Body> { return std::make_unique<PtBody>(p); },
    }, s);
}

/** C3. Multimethod registry keyed by (type, type): open in both directions, checked at runtime. */
class CollisionRegistry {
    std::map<std::pair<std::type_index, std::type_index>, std::function<bool(const Shape&, const Shape&)>> table_;
    static std::type_index type_of(const Shape& s) {
        return std::visit([](const auto& x) { return std::type_index(typeid(x)); }, s);
    }
public:
    template <class A, class B, class F>
    void add(F f) {
        table_[{typeid(A), typeid(B)}] = [f](const Shape& x, const Shape& y) { return f(std::get<A>(x), std::get<B>(y)); };
        table_.try_emplace({typeid(B), typeid(A)}, [f](const Shape& x, const Shape& y) { return f(std::get<A>(y), std::get<B>(x)); });
    }
    bool collides(const Shape& a, const Shape& b) const {
        auto it = table_.find({type_of(a), type_of(b)});
        if (it == table_.end()) throw std::logic_error("no rule for this pair");
        return it->second(a, b);
    }
};

int main() {
    auto join = [](const std::vector<std::string>& v) {
        std::string s;
        for (const auto& x : v) s += (s.empty() ? "" : ", ") + x;
        return "[" + s + "]";
    };
    std::println("== A1. Re-entrant publish: the audit log's view of causality ==");
    std::println("  depth-first   (recursive delivery) -> {}", join(reentrancy_order(false)));
    std::println("  breadth-first (queued delivery)    -> {}", join(reentrancy_order(true)));
    SyncBus bus(true);
    std::vector<std::string> got;
    auto faulty = bus.subscribe("t", [](const Event& e) {
        if (e.payload == "boom") throw std::runtime_error("subscriber bug");
    });
    {
        auto token = bus.subscribe("t", [&](const Event& e) { got.push_back(e.payload); });
        bus.publish({"t", "boom"});
    }  // token destroyed: unsubscribed
    bus.publish({"t", "after-unsubscribe"});
    std::println("  isolation: healthy subscriber got {}, dead letters {}", join(got), join(bus.dead_letters));

    std::println("== A2. Async mailboxes: 3 publishers x 50,000 events, one fast + one slow subscriber ==");
    OrderChecker fast, slow;
    slow.slow_every = 10'000;
    const auto t0 = std::chrono::steady_clock::now();
    {
        Mailbox mf(256, [&](const Event& e) { fast.on(e); });
        Mailbox ms(256, [&](const Event& e) { slow.on(e); });
        std::vector<std::jthread> pubs;
        for (int p = 0; p < 3; ++p)
            pubs.emplace_back([&, p] {
                for (long long i = 0; i < 50'000; ++i) {
                    Event e{"t", std::format("p{}-{}", p, i)};
                    mf.post(e);
                    ms.post(std::move(e));
                }
            });
    }  // publishers joined first (declared last), then mailboxes drain and join
    std::println("  fast: received {}, per-producer inversions {} | slow: received {}, inversions {} ({:.0f} ms)", fast.received,
                 fast.inversions, slow.received, slow.inversions,
                 std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count());
    std::atomic<long long> last_seen{-1}, inversions{0};
    {
        CallerRunsPool pool(4);
        for (long long i = 0; i < 20'000; ++i)
            pool.execute([&, i] {
                if (last_seen.exchange(i) > i) inversions.fetch_add(1);
                for (int k = 0; k < 50; ++k) {
#if defined(__x86_64__) || defined(__i386__)
                    __builtin_ia32_pause();
#endif
                }
            });
    }
    std::println("  'back-pressure' via caller-runs, one producer: {} order inversions in 20000 events", inversions.load());

    std::println("== B. Command undo/redo (perform() returns the inverse) ==");
    Editor ed;
    for (const char* ch : {"H", "e", "l", "l", "o"}) ed.execute({Insert{ed.size(), ch}});
    std::println("  typed 'Hello' (5 keystrokes)   -> {}", ed.state());
    ed.execute({Insert{5, " world"}});
    std::println("  paste ' world'                 -> {}", ed.state());
    ed.execute({Delete{0, 6}});
    std::println("  delete(0,6)                    -> {}", ed.state());
    ed.undo();
    std::println("  undo                           -> {}", ed.state());
    ed.undo();
    std::println("  undo                           -> {}", ed.state());
    ed.redo();
    std::println("  redo                           -> {}", ed.state());
    ed.execute({Macro{{Command{Insert{0, ">> "}}, Command{Delete{3, 6}}}}});
    std::println("  macro(insert '>> ', delete 6)  -> {}   (redo history dropped)", ed.state());
    ed.undo();
    std::println("  undo macro (one step)          -> {}", ed.state());
    ed.redo();
    std::println("  redo macro                     -> {}", ed.state());

    std::println("== C. Double dispatch: two-variant visit vs classic visitor vs multimethod registry ==");
    const std::vector<Shape> shapes = {Circle{0, 0, 1}, Rect{0.5, 0.5, 2, 2}, Pt{1.5, 1.5}, Circle{5, 5, 0.5}, Pt{0, 0}};
    CollisionRegistry reg;
    reg.add<Circle, Circle>(circle_circle);
    reg.add<Circle, Rect>(circle_rect);
    reg.add<Rect, Rect>(rect_rect);
    reg.add<Circle, Pt>([](const Circle& c, const Pt& p) { return circle_circle(c, as_circle(p)); });
    reg.add<Rect, Pt>([](const Rect& r, const Pt& p) { return rect_rect(r, as_rect(p)); });
    reg.add<Pt, Pt>([](const Pt& p, const Pt& q) { return p.x == q.x && p.y == q.y; });
    int pairs = 0, collisions = 0, disagreements = 0;
    for (const auto& a : shapes) {
        std::string row = "  ";
        for (const auto& b : shapes) {
            const bool s = collides(a, b), v = body(a)->collide(*body(b)), r = reg.collides(a, b);
            disagreements += (s != v || s != r);
            ++pairs;
            collisions += s;
            row += s ? 'X' : '.';
        }
        std::println("{}", row);
    }
    std::println("  {} ordered pairs, {} collide, disagreements between the 3 dispatchers: {}", pairs, collisions, disagreements);

    const auto bf = reentrancy_order(true);
    const bool ok = bf == std::vector<std::string>{"OrderPlaced", "PaymentRequested"} && ed.text() == ">> world" &&
                    got == std::vector<std::string>{"boom"} && fast.inversions == 0 && slow.inversions == 0 &&
                    fast.received == 150'000 && slow.received == 150'000 && disagreements == 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2 (Clang 21.1 identical apart from the measured lines):**

```text
== A1. Re-entrant publish: the audit log's view of causality ==
  depth-first   (recursive delivery) -> [PaymentRequested, OrderPlaced]
  breadth-first (queued delivery)    -> [OrderPlaced, PaymentRequested]
  isolation: healthy subscriber got [boom], dead letters [boom -> subscriber bug]
== A2. Async mailboxes: 3 publishers x 50,000 events, one fast + one slow subscriber ==
  fast: received 150000, per-producer inversions 0 | slow: received 150000, inversions 0 (341 ms)
  'back-pressure' via caller-runs, one producer: 9637 order inversions in 20000 events
== B. Command undo/redo (perform() returns the inverse) ==
  typed 'Hello' (5 keystrokes)   -> 'Hello' undo=1 redo=0
  paste ' world'                 -> 'Hello world' undo=2 redo=0
  delete(0,6)                    -> 'world' undo=3 redo=0
  undo                           -> 'Hello world' undo=2 redo=1
  undo                           -> 'Hello' undo=1 redo=2
  redo                           -> 'Hello world' undo=2 redo=1
  macro(insert '>> ', delete 6)  -> '>> world' undo=3 redo=0   (redo history dropped)
  undo macro (one step)          -> 'Hello world' undo=2 redo=1
  redo macro                     -> '>> world' undo=3 redo=0
== C. Double dispatch: two-variant visit vs classic visitor vs multimethod registry ==
  XX..X
  XXX..
  .XX..
  ...X.
  X...X
  25 ordered pairs, 11 collide, disagreements between the 3 dispatchers: 0
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Observer | `List<Listener>` iterated in place | `CopyOnWriteArrayList`; try/catch per listener | States ordering (breadth-first), isolation, lifecycle (tokens) and concurrency (snapshot, no lock across user code) as explicit contracts |
| Async events | `executor.submit` per (event, listener) | Per-listener executor | Bounded per-subscriber mailboxes with blocking back-pressure; knows `CallerRunsPolicy` breaks FIFO; dead-letter routing; drain on shutdown |
| Undo/redo | Stores "before" snapshots of the whole document | Command objects with captured state | `apply()` returns the inverse computed at execution time; coalescing; macro inverses reversed; commands are serializable records |
| Visitor | `accept/visit` everywhere | Visitor for operations over a fixed hierarchy | Sealed `switch` for single dispatch; nested switch / two-variant `visit` for double dispatch; registry only for genuinely open, plugin-extended type sets |

## 7. Curveballs

| Curveball | 5-minute response |
|---|---|
| "Subscribers must receive events in global publish order" | One global sequence number at publish plus per-subscriber mailboxes that deliver in sequence order (reorder buffer), or a single dispatcher thread. Name the throughput cost |
| "At-least-once delivery across restarts" | Persist events (outbox / log), track per-subscriber offsets, make handlers idempotent by event id. That's Kafka consumer groups (P4) |
| "Undo must work in a shared document with two editors" | Commands are already data: transform concurrent operations (OT) or switch to CRDTs. Mention that position-based inverses must be re-based on concurrent edits |
| "Limit undo history to 100 steps / 10 MB" | Bound the undo deque; evict the oldest; coalescing already keeps typing to a few entries |
| "Add a `Triangle` shape" | Sealed: the compiler demands 7 new pairs. Registry: register 4 functions (symmetry fills the rest), and a missing pair fails loudly at first use |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "A subscriber publishes another event. What does everyone else see?"</b></summary>

**L5:** "They get both events."

**Why it fails:** with recursive delivery, subscribers registered after the publisher see the nested event *first*. The listing's audit log recorded `[PaymentRequested, OrderPlaced]`.

**L7 defence:** "Delivery must be breadth-first: a per-thread pending queue and a dispatching flag, so nested publishes are delivered after the current event completes. Then every subscriber sees publish order. For async buses, each subscriber's mailbox preserves FIFO, and cross-subscriber ordering is a separate, stated guarantee."
</details>

<details>
<summary><b>Q2 ⚡ "Your mailbox is full. What happens?"</b></summary>

**L5:** "Use `CallerRunsPolicy` so the producer slows down."

**Why it fails:** caller-runs executes the task on the producer thread *concurrently* with the worker. Measured: 9,383 order inversions in 20,000 events from one producer.

**L7 defence:** "Choose explicitly: block the producer (order-preserving back-pressure), drop with a metric (lossy, for telemetry), or shed at the edge (reject with 429). Caller-runs is acceptable only for unordered, independent tasks."
</details>

<details>
<summary><b>Q3 ⚡ "Implement undo for delete."</b></summary>

**L5:** "Store the deleted text when the user asks to delete, and re-insert it on undo."

**Why it fails:** inside a macro or a replay, the stored text and position belong to a different document state. The listing's first draft corrupted the text this way.

**L7 defence:** "`apply()` returns the inverse computed from the state it actually changed. Undo applies the inverse and pushes the forward command it returns onto redo. The stacks are symmetric, macros invert in reverse order, and commands are records I can log and replay."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Projections and audit logs show effects before causes | Depth-first re-entrant delivery | Breadth-first queue |
| One listener's exception stops all others | No per-listener isolation | try/catch per delivery + dead letters |
| Memory leak from listeners | No unsubscribe path for lambdas | Tokens / RAII subscriptions; weak references only with care |
| Deadlock calling listeners | Lock held while invoking user code | Snapshot under the lock, invoke outside it |
| Async events out of order | Shared pool, or `CallerRunsPolicy` | Per-subscriber mailbox; blocking back-pressure |
| Undo restores the wrong text | Inverse captured before execution | Inverse returned by `apply()` |
| New shape type silently unsupported | `default` in a dispatch switch / missing registry pair | Sealed exhaustive switch; registry fails fast |

- [ ] Ordering, isolation, lifecycle and concurrency of the bus are stated and tested.
- [ ] No lock is held while invoking subscribers; snapshots are copy-on-write.
- [ ] Async delivery uses per-subscriber bounded mailboxes with an explicit overflow policy.
- [ ] Commands compute their inverse at execution; redo clears on new edits; typing is coalesced.
- [ ] Double dispatch uses exhaustive sealed or variant matching unless the hierarchy is genuinely open.

## 10. References

- Gamma et al., *Design Patterns*: Observer, Command, Visitor.
- Java `SubmissionPublisher` (per-subscriber buffering, back-pressure). <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/SubmissionPublisher.html>
- Java `ThreadPoolExecutor.CallerRunsPolicy`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/ThreadPoolExecutor.CallerRunsPolicy.html>
- Robert C. Martin, "Acyclic Visitor", *Pattern Languages of Program Design 3*, 1997.
- cppreference: `std::visit` (multiple variants). <https://en.cppreference.com/w/cpp/utility/variant/visit>
- In this KB: [02.1 State machines](01-state-machines-enum-vs-sealed-types-and-optimistic-transitions.md) · [02.2 Strategy and specification](02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md) · P4 pub/sub broker (Folder 03) · P17 async logger and P19 chess undo (Folder 06)
