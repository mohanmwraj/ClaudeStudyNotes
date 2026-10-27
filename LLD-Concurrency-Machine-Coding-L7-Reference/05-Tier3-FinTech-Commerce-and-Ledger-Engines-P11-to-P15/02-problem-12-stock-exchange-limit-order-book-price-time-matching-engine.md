# P12 · Limit Order Book: Price-Time Matching, O(1) Cancel, and a Single-Writer Sequenced Engine

> **Folder 05 · Problem 12 of 20.** A matching engine is a deterministic function from a *sequenced* stream of commands to a stream of events. This problem covers:
> - price-time priority over sorted price levels;
> - cancels in O(1), which needs an intrusive FIFO, not `ArrayDeque`;
> - prices as integer ticks;
> - one thread owning the book, fed by a ring.
>
> The measurements include one result a candidate must be honest about: **the single writer did not win on throughput here**. Section 3 explains why it's still the design.
>
> **Listing pair P12:** `OrderBookEngine.java` / `order_book_engine.cpp`. A **1,000,000-command run gives the identical event hash `7c47c5588e0d5454` in Java, GCC and Clang**. Sections 1 and 4 are deterministic.

---

## 1. Problem and scope

**Functional:**
- **Order types:** `LIMIT`, `MARKET`, `IOC` (fill what you can now, cancel the rest) and `FOK` (all or nothing, immediately).
- **Cancel and amend.** Amend keeps time priority only for a reduce-only change at the same price.
- **Price-time priority:** best price first, then earliest at that price. Trades execute at the **resting** order's price.

**Non-functional:**
- Deterministic output, so the engine can be replayed and replicated.
- Low, stable latency.
- O(log L) to find a level, O(1) to cancel.

**Out of scope:** multi-symbol routing (one book per symbol, §7), market-data dissemination and auctions.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Commands | `sealed interface Command permits Place, Cancel, Amend` | `std::variant<Place, Cancel, Amend>` (trivially copyable, so it can go in the ring) |
| Events | `Sink`: `accepted / rejected / trade / cancelled / amended` | same, virtual interface |
| Price | `long` ticks of 0.01; `BigDecimal` only at the boundary, with tick validation | `i64` ticks; `parse_ticks` rejects sub-tick input |
| Level | `TreeMap<Long, Level>` (bids in `reverseOrder`) + intrusive FIFO `head/tail/prev/next` | `std::map<i64, Level>` with key = `−price` for bids, so `begin()` is always best; node arena + free list |
| Index | `HashMap<Long, Order>` id → node (O(1) cancel) | `std::unordered_map<i64, Order*>` |

**Invariants**, checked after every scripted command and every 100k commands in the 1M run:
- **I1:** the book is never crossed: best bid < best ask.
- **I2:** each level's `qty` and `count` equal the sum over its FIFO; every resting order is in the id index and vice versa.
- **I3:** a taker fills against the best level first, oldest order first. The trade price is the maker's price.
- **I4:** `MARKET` and `IOC` never rest. `FOK` either fills completely or executes nothing (`available()` is checked first).
- **I5:** amend that reduces quantity at the same price keeps priority. Anything else is a cancel + re-entry at the back, which may trade.
- **I6:** the same sequenced input always produces the same events (the replay check).

## 3. Concurrency and contention analysis

### 3.1 Why one thread owns the book

Price-time priority **is** an arrival order. Matching needs a total order of commands per instrument, so the real design question is where the serialization point sits and what it costs.

**Fine-grained locks are wrong, not just slow.** A taker sweeping three ask levels needs those levels, and the best-price view, to stay consistent for the whole sweep. A concurrent taker or cancel in between produces:
- double fills of the same maker;
- a taker trading through a better price;
- a briefly crossed book.

The lock you'd need *is* the whole book.

**The sequencer pattern (LMAX-style):**
1. Gateway threads do the parallel work (parse, validate, risk-check) and publish commands into a bounded **MPSC ring** (`MpscRing`, Vyukov per-slot sequence numbers). Each producer does one `getAndIncrement` and then writes its own slot.
2. **One matching thread** drains the ring and applies commands to a book with **no synchronization at all**.
3. The drained order *is* the journal. Replaying it rebuilds the book and the exact event stream, which is what makes recovery and hot-standby replicas work. The replay check is true in every run.

**Measured: 4 gateway threads × 250,000 commands, against a deliberately deep book (~200k resting orders):**

| Build | MPSC ring → single matcher | 4 threads + lock around the book | Replay reproduces the live hash |
|---|---|---|---|
| Java | 2.48 M commands/s | 2.40 M/s (`synchronized`) | true / true |
| GCC 16.2 | 3.39 M/s | 2.51 M/s (`std::mutex`) | true / true |
| Clang 21.1 | 3.14 M/s | **3.79 M/s** | true / true |

**Throughput is a wash, and you should say so.** Both designs serialize on matching, which costs ~300 ns here. A lock-based engine that logs commands *inside* its lock is deterministic too, because it has quietly built a sequencer.

**What the single writer actually buys:**
1. **No lock discipline to get wrong in the hot path.** The book code has zero synchronization.
2. **The book stays in one core's cache** instead of migrating between cores.
3. **No convoys:** a producer descheduled while holding the lock stalls every other gateway. With the ring, only its own slot waits.
4. **The journal and replication fall out for free.**
5. **Sharding is natural:** one matcher per symbol (or symbol group) scales across cores without coordination.

Tail latency, not mean throughput, is where (3) shows up. The listing doesn't claim a number for it.

### 3.2 Cancel in O(1)

Most orders on a real venue are cancelled, so cancel is the hot path. `ArrayDeque.remove(o)` scans the deque. The intrusive FIFO unlinks a node found through the id map.

| One level, 50,000 resting orders, 25,000 random cancels | Java | GCC | Clang |
|---|---|---|---|
| `ArrayDeque.remove(o)` / `std::deque` find + erase | 185 ms | 403 ms | 164 ms |
| Intrusive unlink | **3.15 ms** | **0.27 ms** | **0.27 ms** |

**Lazy tombstones** are the alternative: mark the order cancelled, skip it while matching, and compact later. Cancel is O(1), but levels accumulate dead nodes and `qty` must be adjusted eagerly or queries lie.

### 3.3 Prices are ticks, not decimals or doubles

- **Java:** `HashMap<BigDecimal, …>` puts `100.1`, `100.10` and `100.100` on **3 levels**, because `equals` compares scale. `TreeMap` merges them into 1, because `compareTo` doesn't.
- **C++:** `std::map<double, …>` puts `0.1 + 0.2` and `0.3` on **2 levels**.
- **The fix:** convert once at the gateway to integer ticks and **reject** sub-tick prices (`100.105`). Integer keys are also faster and allocation-free.

**Cross-language determinism.** The 1M-command run uses the same SplitMix64-driven flow and hash rule in both languages: 60% places, 30% cancels, 10% amends. It produces 232,198 trades, volume 5,932,019 and 261,806 rejects in all three builds, with hash `7c47c5588e0d5454`. That is a strong check that the two implementations encode exactly the same matching semantics.

## 4. Java 21 implementation

```java
// OrderBookEngine.java - P12: price-time limit order book, O(1) cancel (intrusive FIFO), single-threaded sequenced event loop
import java.math.BigDecimal;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;
import java.util.TreeMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.AtomicReference;

public final class OrderBookEngine {

    static final long MID = 10_000;                                 // 100.00 in ticks of 0.01
    static final BigDecimal TICK = new BigDecimal("0.01");

    enum Side { BUY, SELL }

    enum Type { LIMIT, MARKET, IOC, FOK }

    sealed interface Command permits Place, Cancel, Amend {}
    record Place(long id, Side side, Type type, long price, long qty) implements Command {}   // price in ticks; MARKET ignores it
    record Cancel(long id) implements Command {}
    record Amend(long id, long price, long qty) implements Command {}

    /** Events go to a sink: the demo records them, the benchmarks only hash them. */
    interface Sink {
        void accepted(long id);

        void rejected(long id, String reason);

        void trade(long maker, long taker, long price, long qty);

        void cancelled(long id, long remaining);

        void amended(long id, boolean keptPriority);
    }

    static final class Order {
        final long id;
        final Side side;
        final long price;
        long remaining;
        Order prev, next;
        Level level;

        Order(long id, Side side, long price, long remaining) {
            this.id = id;
            this.side = side;
            this.price = price;
            this.remaining = remaining;
        }
    }

    /** One price level: an intrusive doubly-linked FIFO, so cancelling a known order is O(1) (ArrayDeque.remove is O(n)). */
    static final class Level {
        final long price;
        Order head, tail;
        long qty;
        int count;

        Level(long price) {
            this.price = price;
        }

        void append(Order o) {
            o.level = this;
            o.prev = tail;
            o.next = null;
            if (tail == null) head = o;
            else tail.next = o;
            tail = o;
            qty += o.remaining;
            count++;
        }

        void unlink(Order o) {
            if (o.prev == null) head = o.next;
            else o.prev.next = o.next;
            if (o.next == null) tail = o.prev;
            else o.next.prev = o.prev;
            o.prev = o.next = null;
            o.level = null;
            qty -= o.remaining;
            count--;
        }
    }

    /** Single-writer book: exactly one thread ever calls apply(), so nothing in here is synchronized. */
    static final class Book {
        final TreeMap<Long, Level> bids = new TreeMap<>(Comparator.reverseOrder()), asks = new TreeMap<>();
        final HashMap<Long, Order> byId = new HashMap<>();

        TreeMap<Long, Level> levels(Side s) {
            return s == Side.BUY ? bids : asks;
        }

        static boolean crosses(Side taker, long limit, long resting) {
            return taker == Side.BUY ? limit >= resting : limit <= resting;
        }

        void apply(Command c, Sink out) {
            switch (c) {
                case Place p -> place(p, out);
                case Cancel x -> cancel(x.id(), out);
                case Amend a -> amend(a, out);
            }
        }

        void place(Place p, Sink out) {
            if (p.qty() <= 0 || (p.type() != Type.MARKET && p.price() <= 0)) {
                out.rejected(p.id(), "bad price or quantity");
                return;
            }
            if (byId.containsKey(p.id())) {
                out.rejected(p.id(), "duplicate order id");
                return;
            }
            out.accepted(p.id());
            long left = match(p.id(), p.side(), p.type(), p.price(), p.qty(), out);
            if (left == 0) return;
            if (p.type() == Type.LIMIT) rest(new Order(p.id(), p.side(), p.price(), left));
            else out.cancelled(p.id(), left);                           // MARKET / IOC remainder, or a killed FOK
        }

        long match(long id, Side side, Type type, long limit, long qty, Sink out) {
            TreeMap<Long, Level> opp = levels(side == Side.BUY ? Side.SELL : Side.BUY);
            if (type == Type.FOK && available(opp, side, limit, qty) < qty) return qty;   // kill: nothing executes
            long left = qty;
            while (left > 0 && !opp.isEmpty()) {
                Level best = opp.firstEntry().getValue();
                if (type != Type.MARKET && !crosses(side, limit, best.price)) break;
                Order maker = best.head;                               // time priority: the oldest order at the best price
                long q = Math.min(left, maker.remaining);
                out.trade(maker.id, id, best.price, q);                // trades print at the RESTING price
                maker.remaining -= q;
                best.qty -= q;
                left -= q;
                if (maker.remaining == 0) {
                    best.unlink(maker);
                    byId.remove(maker.id);
                    if (best.count == 0) opp.pollFirstEntry();
                }
            }
            return left;
        }

        static long available(TreeMap<Long, Level> opp, Side side, long limit, long want) {
            long sum = 0;
            for (Level l : opp.values()) {
                if (sum >= want || !crosses(side, limit, l.price)) break;
                sum += l.qty;
            }
            return sum;
        }

        void rest(Order o) {
            levels(o.side).computeIfAbsent(o.price, Level::new).append(o);
            byId.put(o.id, o);
        }

        void remove(Order o) {
            Level l = o.level;
            l.unlink(o);
            if (l.count == 0) levels(o.side).remove(l.price);
        }

        void cancel(long id, Sink out) {
            Order o = byId.remove(id);
            if (o == null) {
                out.rejected(id, "unknown order");
                return;
            }
            long left = o.remaining;
            remove(o);
            out.cancelled(id, left);
        }

        /** Reduce-only at the same price keeps time priority; any other change re-enters at the back (and may trade). */
        void amend(Amend a, Sink out) {
            Order o = byId.get(a.id());
            if (o == null) {
                out.rejected(a.id(), "unknown order");
                return;
            }
            if (a.qty() <= 0 || a.price() <= 0) {
                out.rejected(a.id(), "bad price or quantity");
                return;
            }
            if (a.price() == o.price && a.qty() <= o.remaining) {
                o.level.qty -= o.remaining - a.qty();
                o.remaining = a.qty();
                out.amended(a.id(), true);
                return;
            }
            byId.remove(a.id());
            remove(o);
            out.amended(a.id(), false);
            long left = match(a.id(), o.side, Type.LIMIT, a.price(), a.qty(), out);
            if (left > 0) rest(new Order(a.id(), o.side, a.price(), left));
        }

        boolean invariantsHold() {
            if (!bids.isEmpty() && !asks.isEmpty() && bids.firstKey() >= asks.firstKey()) return false;   // never crossed
            long orders = 0;
            for (TreeMap<Long, Level> m : List.of(bids, asks))
                for (Level l : m.values()) {
                    long q = 0;
                    int n = 0;
                    for (Order o = l.head; o != null; o = o.next) {
                        if (o.remaining <= 0 || o.level != l || o.price != l.price || byId.get(o.id) != o) return false;
                        q += o.remaining;
                        n++;
                    }
                    if (n == 0 || q != l.qty || n != l.count) return false;
                    orders += n;
                }
            return orders == byId.size();
        }

        String depth() {
            StringJoiner b = new StringJoiner(" "), a = new StringJoiner(" ");
            bids.values().forEach(l -> b.add(px(l.price) + "x" + l.qty));
            asks.values().forEach(l -> a.add(px(l.price) + "x" + l.qty));
            return "bids [" + b + "] asks [" + a + "]";
        }
    }

    static String px(long ticks) {
        return BigDecimal.valueOf(ticks, 2).toPlainString();
    }

    static long mix64(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    /** Folds every event into one 64-bit hash: equal hashes = identical event streams (same rule as the C++ listing). */
    static final class HashSink implements Sink {
        long h, trades, volume, rejects;

        void mix(long kind, long a, long b, long c, long d) {
            h = mix64(h ^ kind);
            h = mix64(h ^ a);
            h = mix64(h ^ b);
            h = mix64(h ^ c);
            h = mix64(h ^ d);
        }

        @Override
        public void accepted(long id) {
            mix(1, id, 0, 0, 0);
        }

        @Override
        public void rejected(long id, String reason) {
            rejects++;
            mix(2, id, 0, 0, 0);
        }

        @Override
        public void trade(long maker, long taker, long price, long qty) {
            trades++;
            volume += qty;
            mix(3, maker, taker, price, qty);
        }

        @Override
        public void cancelled(long id, long remaining) {
            mix(4, id, remaining, 0, 0);
        }

        @Override
        public void amended(long id, boolean keptPriority) {
            mix(5, id, keptPriority ? 1 : 0, 0, 0);
        }
    }

    /** Records events as text for the scripted demo. */
    static final class TextSink implements Sink {
        final List<String> lines = new ArrayList<>();
        final List<long[]> trades = new ArrayList<>();

        @Override
        public void accepted(long id) {}

        @Override
        public void rejected(long id, String reason) {
            lines.add("rejected #" + id + ": " + reason);
        }

        @Override
        public void trade(long maker, long taker, long price, long qty) {
            trades.add(new long[]{maker, taker, price, qty});
            lines.add("trade #" + maker + " x" + qty + " @" + px(price));
        }

        @Override
        public void cancelled(long id, long remaining) {
            lines.add("cancelled #" + id + " x" + remaining);
        }

        @Override
        public void amended(long id, boolean keptPriority) {
            lines.add("amended #" + id + (keptPriority ? " (kept priority)" : " (lost priority)"));
        }
    }

    static final class Rng {
        private long s;

        Rng(long seed) {
            s = seed;
        }

        int below(int n) {
            return (int) Long.remainderUnsigned(mix64(s++), n);
        }
    }

    /** Deterministic order flow: 60% new orders around the mid, 30% cancels, 10% amends of this flow's earlier ids. */
    static final class Flow {
        final Rng r;
        final long base;
        long issued;

        Flow(long seed, long base) {
            r = new Rng(seed);
            this.base = base;
        }

        Command next() {
            int k = r.below(100);
            if (k < 60 || issued == 0) {
                long id = base + ++issued;
                Side side = r.below(2) == 0 ? Side.BUY : Side.SELL;
                int t = r.below(20);
                Type type = t == 0 ? Type.MARKET : t == 1 ? Type.IOC : t == 2 ? Type.FOK : Type.LIMIT;
                long price = side == Side.BUY ? MID - 20 + r.below(25) : MID - 4 + r.below(25);
                long qty = 1 + r.below(100);
                return new Place(id, side, type, price, qty);
            }
            long target = base + 1 + r.below((int) issued);
            if (k < 90) return new Cancel(target);
            long price = MID - 10 + r.below(21);
            long qty = 1 + r.below(100);
            return new Amend(target, price, qty);
        }
    }

    /** Bounded multi-producer / single-consumer ring (per-slot sequence numbers, Vyukov style): the sequencer. */
    static final class MpscRing<T> {
        final AtomicLongArray seq;
        final Object[] items;
        final int mask;
        final AtomicLong tail = new AtomicLong();
        long head;                                                     // consumer-owned

        MpscRing(int capacityPow2) {
            seq = new AtomicLongArray(capacityPow2);
            items = new Object[capacityPow2];
            mask = capacityPow2 - 1;
            for (int i = 0; i < capacityPow2; i++) seq.set(i, i);
        }

        void push(T v) {
            long pos = tail.getAndIncrement();                         // claim a slot: one atomic op per producer
            int i = (int) (pos & mask);
            while (seq.get(i) != pos) Thread.onSpinWait();             // ring full: wait for the consumer to free this slot
            items[i] = v;
            seq.set(i, pos + 1);                                       // publish (volatile write)
        }

        @SuppressWarnings("unchecked")
        T poll() {
            int i = (int) (head & mask);
            if (seq.get(i) != head + 1) return null;
            T v = (T) items[i];
            items[i] = null;
            seq.set(i, head + mask + 1);                               // free the slot for the producer one lap later
            head++;
            return v;
        }
    }

    record Run(long hash, long millis, boolean replayMatches, boolean invariants) {}

    static long replay(Command[] log) {
        Book b = new Book();
        HashSink s = new HashSink();
        for (Command c : log) b.apply(c, s);
        return s.h;
    }

    static Run eventLoop(int producers, int perProducer) throws Exception {
        MpscRing<Command> ring = new MpscRing<>(1 << 16);
        Book book = new Book();
        HashSink sink = new HashSink();
        Command[] log = new Command[producers * perProducer];
        CyclicBarrier start = new CyclicBarrier(producers + 2);
        CountDownLatch matcherDone = new CountDownLatch(1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        for (int p = 0; p < producers; p++) {
            final int id = p;
            Thread.ofPlatform().start(() -> {
                try {
                    Flow f = new Flow(100 + id, (id + 1) * 1_000_000_000L);
                    start.await();
                    for (int i = 0; i < perProducer; i++) ring.push(f.next());   // gateway work runs here, in parallel
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                }
            });
        }
        Thread.ofPlatform().start(() -> {
            try {
                start.await();
                for (int n = 0; n < log.length; ) {
                    Command c = ring.poll();
                    if (c == null) {
                        Thread.onSpinWait();
                        continue;
                    }
                    log[n++] = c;                                      // the sequenced input IS the journal
                    book.apply(c, sink);
                }
            } catch (Exception e) {
                failure.compareAndSet(null, e);
            } finally {
                matcherDone.countDown();
            }
        });
        start.await();
        long t0 = System.nanoTime();
        matcherDone.await();
        long ms = (System.nanoTime() - t0) / 1_000_000;
        if (failure.get() != null) throw new IllegalStateException(failure.get());
        return new Run(sink.h, ms, replay(log) == sink.h, book.invariantsHold());
    }

    static Run locked(int producers, int perProducer) throws Exception {
        Book book = new Book();
        HashSink sink = new HashSink();
        Command[] log = new Command[producers * perProducer];
        int[] n = new int[1];                                          // guarded by book's monitor
        CyclicBarrier start = new CyclicBarrier(producers + 1);
        CountDownLatch done = new CountDownLatch(producers);
        AtomicReference<Exception> failure = new AtomicReference<>();
        for (int p = 0; p < producers; p++) {
            final int id = p;
            Thread.ofPlatform().start(() -> {
                try {
                    Flow f = new Flow(100 + id, (id + 1) * 1_000_000_000L);
                    start.await();
                    for (int i = 0; i < perProducer; i++) {
                        Command c = f.next();
                        synchronized (book) {
                            log[n[0]++] = c;
                            book.apply(c, sink);
                        }
                    }
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                } finally {
                    done.countDown();
                }
            });
        }
        start.await();
        long t0 = System.nanoTime();
        done.await();
        long ms = (System.nanoTime() - t0) / 1_000_000;
        if (failure.get() != null) throw new IllegalStateException(failure.get());
        synchronized (book) {
            return new Run(sink.h, ms, replay(log) == sink.h, book.invariantsHold());
        }
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Price-time priority, partial fills, MARKET / IOC / FOK, amend priority, cancel ==");
        Book book = new Book();
        List<Command> script = List.of(
                new Place(1, Side.SELL, Type.LIMIT, 10_010, 50), new Place(2, Side.SELL, Type.LIMIT, 10_010, 30),
                new Place(3, Side.SELL, Type.LIMIT, 10_020, 40), new Place(4, Side.BUY, Type.LIMIT, 10_000, 25),
                new Place(5, Side.BUY, Type.LIMIT, 10_010, 60), new Place(6, Side.BUY, Type.MARKET, 0, 50),
                new Place(7, Side.SELL, Type.IOC, 9_990, 40), new Place(8, Side.BUY, Type.FOK, 10_020, 20),
                new Place(9, Side.SELL, Type.LIMIT, 10_030, 10), new Place(10, Side.SELL, Type.LIMIT, 10_030, 10),
                new Amend(9, 10_030, 5), new Amend(9, 10_030, 15), new Place(13, Side.BUY, Type.LIMIT, 10_030, 12),
                new Cancel(10), new Cancel(10), new Place(16, Side.BUY, Type.LIMIT, 9_950, 100));
        List<long[]> allTrades = new ArrayList<>();
        boolean invariants = true;
        for (Command c : script) {
            TextSink s = new TextSink();
            book.apply(c, s);
            invariants &= book.invariantsHold();
            allTrades.addAll(s.trades);
            String what = switch (c) {
                case Place p -> "#" + p.id() + " " + p.side() + " " + p.type() + (p.type() == Type.MARKET ? "" : " " + px(p.price())) + " x" + p.qty();
                case Cancel x -> "cancel #" + x.id();
                case Amend a -> "amend #" + a.id() + " to " + px(a.price()) + " x" + a.qty();
            };
            long id = switch (c) {
                case Place p -> p.id();
                case Cancel x -> x.id();
                case Amend a -> a.id();
            };
            if (book.byId.containsKey(id) && !(c instanceof Cancel)) s.lines.add("rests x" + book.byId.get(id).remaining);
            System.out.printf("  %-30s -> %s%n", what, s.lines.isEmpty() ? "rests" : String.join(", ", s.lines));
        }
        String finalDepth = book.depth();
        System.out.println("  book: " + finalDepth);

        System.out.println("== 2. Price keys: BigDecimal equality vs ordering, and ticks ==");
        Map<BigDecimal, Integer> hashed = new HashMap<>();
        TreeMap<BigDecimal, Integer> sorted = new TreeMap<>();
        for (String s : List.of("100.1", "100.10", "100.100")) {
            hashed.merge(new BigDecimal(s), 1, Integer::sum);
            sorted.merge(new BigDecimal(s), 1, Integer::sum);
        }
        System.out.printf("  prices 100.1 / 100.10 / 100.100: HashMap<BigDecimal> levels %d (equals compares scale) | TreeMap<BigDecimal> levels %d (compareTo)%n",
                hashed.size(), sorted.size());
        for (String s : List.of("100.10", "100.105")) {
            BigDecimal p = new BigDecimal(s);
            System.out.println("  " + s + " -> " + (p.remainder(TICK).signum() == 0 ? p.divide(TICK).longValueExact() + " ticks"
                    : "rejected: not a multiple of the " + TICK + " tick"));
        }

        System.out.println("== 3. Cancel cost: one level with 50,000 resting orders, cancel 25,000 at random ==");
        int depth = 50_000, cancels = 25_000;
        Order[] orders = new Order[depth];
        for (int i = 0; i < depth; i++) orders[i] = new Order(i, Side.SELL, MID, 1);
        int[] perm = new int[depth];
        for (int i = 0; i < depth; i++) perm[i] = i;
        Rng r3 = new Rng(9);
        for (int i = depth - 1; i > 0; i--) {
            int j = r3.below(i + 1), t = perm[i];
            perm[i] = perm[j];
            perm[j] = t;
        }
        ArrayDeque<Order> deque = new ArrayDeque<>();
        for (Order o : orders) deque.add(o);
        long t0 = System.nanoTime();
        for (int i = 0; i < cancels; i++) deque.remove(orders[perm[i]]);   // O(n) scan per cancel
        long dequeNs = System.nanoTime() - t0;
        Level level = new Level(MID);
        for (Order o : orders) level.append(o);
        t0 = System.nanoTime();
        for (int i = 0; i < cancels; i++) level.unlink(orders[perm[i]]);   // O(1) given the order (found via the id map)
        long intrusiveNs = System.nanoTime() - t0;
        long hd = 0, hl = 0;
        for (Order o : deque) hd = mix64(hd ^ o.id);
        for (Order o = level.head; o != null; o = o.next) hl = mix64(hl ^ o.id);
        System.out.printf("  ArrayDeque.remove(o) %.1f ms | intrusive unlink %.2f ms | same FIFO left (%d orders): %b%n", dequeNs / 1e6,
                intrusiveNs / 1e6, level.count, hd == hl && deque.size() == level.count);

        System.out.println("== 4. 1,000,000 deterministic commands through one book (same flow and hash rule as the C++ listing) ==");
        Book big = new Book();
        HashSink hs = new HashSink();
        Flow flow = new Flow(5, 0);
        boolean bigOk = true;
        t0 = System.nanoTime();
        for (int i = 1; i <= 1_000_000; i++) {
            big.apply(flow.next(), hs);
            if (i % 100_000 == 0) bigOk &= big.invariantsHold();
        }
        long bigNs = System.nanoTime() - t0;
        System.out.printf("  trades %d, volume %d, rejects %d, resting orders %d on %d+%d levels | event hash %s%n", hs.trades, hs.volume, hs.rejects,
                big.byId.size(), big.bids.size(), big.asks.size(), Long.toHexString(hs.h));
        System.out.printf("  %d ns per command (single thread, including invariant checks every 100k)%n", bigNs / 1_000_000);

        System.out.println("== 5. 4 gateway threads x 250,000 commands: sequencer ring + one matcher vs synchronized(book) ==");
        Run loop = eventLoop(4, 250_000), lock = locked(4, 250_000);
        for (Run run : List.of(loop, lock))
            System.out.printf("  %-34s %d ms (%.2f M commands/s) | replaying the sequenced log reproduces the live hash: %b | invariants %b%n",
                    run == loop ? "MPSC ring -> single matcher:" : "4 threads, synchronized(book):", run.millis(),
                    1_000_000 / 1_000.0 / Math.max(1, run.millis()), run.replayMatches(), run.invariants());

        boolean ok = invariants && allTrades.size() == 7
                && allTrades.get(0)[0] == 1 && allTrades.get(0)[3] == 50 && allTrades.get(1)[0] == 2 && allTrades.get(1)[3] == 10
                && allTrades.get(3)[0] == 3 && allTrades.get(3)[2] == 10_020 && allTrades.get(4)[0] == 4
                && allTrades.get(5)[0] == 3 && allTrades.get(6)[0] == 10 && allTrades.get(6)[3] == 2
                && finalDepth.equals("bids [99.50x100] asks [100.30x15]")
                && hashed.size() == 3 && sorted.size() == 1 && hd == hl && bigOk
                && loop.replayMatches() && loop.invariants() && lock.replayMatches() && lock.invariants();
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1, 2, 4 deterministic; 3 and 5 one measured run):**

```text
== 1. Price-time priority, partial fills, MARKET / IOC / FOK, amend priority, cancel ==
  #1 SELL LIMIT 100.10 x50       -> rests x50
  #2 SELL LIMIT 100.10 x30       -> rests x30
  #3 SELL LIMIT 100.20 x40       -> rests x40
  #4 BUY LIMIT 100.00 x25        -> rests x25
  #5 BUY LIMIT 100.10 x60        -> trade #1 x50 @100.10, trade #2 x10 @100.10
  #6 BUY MARKET x50              -> trade #2 x20 @100.10, trade #3 x30 @100.20
  #7 SELL IOC 99.90 x40          -> trade #4 x25 @100.00, cancelled #7 x15
  #8 BUY FOK 100.20 x20          -> cancelled #8 x20
  #9 SELL LIMIT 100.30 x10       -> rests x10
  #10 SELL LIMIT 100.30 x10      -> rests x10
  amend #9 to 100.30 x5          -> amended #9 (kept priority), rests x5
  amend #9 to 100.30 x15         -> amended #9 (lost priority), rests x15
  #13 BUY LIMIT 100.30 x12       -> trade #3 x10 @100.20, trade #10 x2 @100.30
  cancel #10                     -> cancelled #10 x8
  cancel #10                     -> rejected #10: unknown order
  #16 BUY LIMIT 99.50 x100       -> rests x100
  book: bids [99.50x100] asks [100.30x15]
== 2. Price keys: BigDecimal equality vs ordering, and ticks ==
  prices 100.1 / 100.10 / 100.100: HashMap<BigDecimal> levels 3 (equals compares scale) | TreeMap<BigDecimal> levels 1 (compareTo)
  100.10 -> 10010 ticks
  100.105 -> rejected: not a multiple of the 0.01 tick
== 3. Cancel cost: one level with 50,000 resting orders, cancel 25,000 at random ==
  ArrayDeque.remove(o) 185.2 ms | intrusive unlink 3.15 ms | same FIFO left (25000 orders): true
== 4. 1,000,000 deterministic commands through one book (same flow and hash rule as the C++ listing) ==
  trades 232198, volume 5932019, rejects 261806, resting orders 207865 on 18+20 levels | event hash 7c47c5588e0d5454
  375 ns per command (single thread, including invariant checks every 100k)
== 5. 4 gateway threads x 250,000 commands: sequencer ring + one matcher vs synchronized(book) ==
  MPSC ring -> single matcher:       403 ms (2.48 M commands/s) | replaying the sequenced log reproduces the live hash: true | invariants true
  4 threads, synchronized(book):     416 ms (2.40 M commands/s) | replaying the sequenced log reproduces the live hash: true | invariants true
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// order_book_engine.cpp - P12: price-time limit order book, O(1) cancel (intrusive FIFO), single-threaded sequenced event loop
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <expected>
#include <format>
#include <map>
#include <mutex>
#include <print>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

constexpr i64 kMid = 10'000;  // 100.00 in ticks of 0.01

enum class Side : std::uint8_t { Buy, Sell };
enum class Type : std::uint8_t { Limit, Market, Ioc, Fok };
constexpr const char* name(Side s) { return s == Side::Buy ? "BUY" : "SELL"; }
constexpr const char* name(Type t) {
    switch (t) {
        case Type::Limit: return "LIMIT";
        case Type::Market: return "MARKET";
        case Type::Ioc: return "IOC";
        case Type::Fok: return "FOK";
    }
    return "?";
}

struct Place { i64 id = 0; Side side = Side::Buy; Type type = Type::Limit; i64 price = 0, qty = 0; };  // price in ticks; MARKET ignores it
struct Cancel { i64 id = 0; };
struct Amend { i64 id = 0, price = 0, qty = 0; };
using Command = std::variant<Place, Cancel, Amend>;

/** Events go to a sink: the demo records them, the benchmarks only hash them. */
struct Sink {
    virtual ~Sink() = default;
    virtual void accepted(i64 id) = 0;
    virtual void rejected(i64 id, std::string_view reason) = 0;
    virtual void trade(i64 maker, i64 taker, i64 price, i64 qty) = 0;
    virtual void cancelled(i64 id, i64 remaining) = 0;
    virtual void amended(i64 id, bool kept_priority) = 0;
};

struct Level;
struct Order {
    i64 id;
    Side side;
    i64 price, remaining;
    Order* prev = nullptr;
    Order* next = nullptr;
    Level* level = nullptr;
};

/** One price level: an intrusive doubly-linked FIFO, so cancelling a known order is O(1) (a deque erase is O(n)). */
struct Level {
    i64 price;
    Order* head = nullptr;
    Order* tail = nullptr;
    i64 qty = 0;
    int count = 0;
    void append(Order* o) {
        o->level = this;
        o->prev = tail;
        o->next = nullptr;
        (tail ? tail->next : head) = o;
        tail = o;
        qty += o->remaining;
        ++count;
    }
    void unlink(Order* o) {
        (o->prev ? o->prev->next : head) = o->next;
        (o->next ? o->next->prev : tail) = o->prev;
        o->prev = o->next = nullptr;
        o->level = nullptr;
        qty -= o->remaining;
        --count;
    }
};

std::string px(i64 ticks) { return std::format("{}{}.{:02}", ticks < 0 ? "-" : "", std::abs(ticks) / 100, std::abs(ticks) % 100); }

/** Single-writer book: exactly one thread ever calls apply(), so nothing in here is synchronized. */
class Book {
    std::array<std::map<i64, Level>, 2> levels_;  // key = -price for bids, +price for asks: begin() is the best level on both sides
    std::unordered_map<i64, Order*> by_id_;
    std::deque<Order> arena_;                     // stable addresses; filled/cancelled nodes are recycled through free_
    std::vector<Order*> free_;

    static sz index(Side s) { return s == Side::Buy ? 0 : 1; }
    static i64 key(Side s, i64 price) { return s == Side::Buy ? -price : price; }
    static bool crosses(Side taker, i64 limit, i64 resting) { return taker == Side::Buy ? limit >= resting : limit <= resting; }

    Order* make(i64 id, Side s, i64 price, i64 qty) {
        if (free_.empty()) return &arena_.emplace_back(Order{id, s, price, qty});
        Order* o = free_.back();
        free_.pop_back();
        *o = Order{id, s, price, qty};
        return o;
    }

    static i64 available(const std::map<i64, Level>& opp, Side side, i64 limit, i64 want) {
        i64 sum = 0;
        for (const auto& [k, l] : opp) {
            if (sum >= want || !crosses(side, limit, l.price)) break;
            sum += l.qty;
        }
        return sum;
    }

    i64 match(i64 id, Side side, Type type, i64 limit, i64 qty, Sink& out) {
        auto& opp = levels_[index(side == Side::Buy ? Side::Sell : Side::Buy)];
        if (type == Type::Fok && available(opp, side, limit, qty) < qty) return qty;  // kill: nothing executes
        i64 left = qty;
        while (left > 0 && !opp.empty()) {
            Level& best = opp.begin()->second;
            if (type != Type::Market && !crosses(side, limit, best.price)) break;
            Order* maker = best.head;  // time priority: the oldest order at the best price
            const i64 q = std::min(left, maker->remaining);
            out.trade(maker->id, id, best.price, q);  // trades print at the RESTING price
            maker->remaining -= q;
            best.qty -= q;
            left -= q;
            if (maker->remaining == 0) {
                best.unlink(maker);
                by_id_.erase(maker->id);
                free_.push_back(maker);
                if (best.count == 0) opp.erase(opp.begin());
            }
        }
        return left;
    }

    void rest(i64 id, Side side, i64 price, i64 qty) {
        Order* o = make(id, side, price, qty);
        levels_[index(side)].try_emplace(key(side, price), Level{price}).first->second.append(o);
        by_id_[id] = o;
    }

    void remove(Order* o) {
        Level* l = o->level;
        l->unlink(o);
        if (l->count == 0) levels_[index(o->side)].erase(key(o->side, l->price));
        free_.push_back(o);
    }

    void place(const Place& p, Sink& out) {
        if (p.qty <= 0 || (p.type != Type::Market && p.price <= 0)) return out.rejected(p.id, "bad price or quantity");
        if (by_id_.contains(p.id)) return out.rejected(p.id, "duplicate order id");
        out.accepted(p.id);
        const i64 left = match(p.id, p.side, p.type, p.price, p.qty, out);
        if (left == 0) return;
        if (p.type == Type::Limit) rest(p.id, p.side, p.price, left);
        else out.cancelled(p.id, left);  // MARKET / IOC remainder, or a killed FOK
    }

    void cancel(i64 id, Sink& out) {
        const auto it = by_id_.find(id);
        if (it == by_id_.end()) return out.rejected(id, "unknown order");
        Order* o = it->second;
        by_id_.erase(it);
        const i64 left = o->remaining;
        remove(o);
        out.cancelled(id, left);
    }

    /** Reduce-only at the same price keeps time priority; any other change re-enters at the back (and may trade). */
    void amend(const Amend& a, Sink& out) {
        const auto it = by_id_.find(a.id);
        if (it == by_id_.end()) return out.rejected(a.id, "unknown order");
        if (a.qty <= 0 || a.price <= 0) return out.rejected(a.id, "bad price or quantity");
        Order* o = it->second;
        if (a.price == o->price && a.qty <= o->remaining) {
            o->level->qty -= o->remaining - a.qty;
            o->remaining = a.qty;
            return out.amended(a.id, true);
        }
        const Side side = o->side;  // o is recycled by remove()
        by_id_.erase(it);
        remove(o);
        out.amended(a.id, false);
        const i64 left = match(a.id, side, Type::Limit, a.price, a.qty, out);
        if (left > 0) rest(a.id, side, a.price, left);
    }

public:
    void apply(const Command& c, Sink& out) {
        std::visit(overloaded{[&](const Place& p) { place(p, out); }, [&](const Cancel& x) { cancel(x.id, out); },
                              [&](const Amend& a) { amend(a, out); }},
                   c);
    }

    const Order* find(i64 id) const {
        const auto it = by_id_.find(id);
        return it == by_id_.end() ? nullptr : it->second;
    }
    sz orders() const { return by_id_.size(); }
    sz bid_levels() const { return levels_[0].size(); }
    sz ask_levels() const { return levels_[1].size(); }

    bool invariants_hold() const {
        if (!levels_[0].empty() && !levels_[1].empty() && levels_[0].begin()->second.price >= levels_[1].begin()->second.price) return false;
        sz orders = 0;
        for (const auto& m : levels_)
            for (const auto& [k, l] : m) {
                i64 q = 0;
                int n = 0;
                for (const Order* o = l.head; o; o = o->next) {
                    const auto it = by_id_.find(o->id);
                    if (o->remaining <= 0 || o->level != &l || o->price != l.price || it == by_id_.end() || it->second != o) return false;
                    q += o->remaining;
                    ++n;
                }
                if (n == 0 || q != l.qty || n != l.count) return false;
                orders += static_cast<sz>(n);
            }
        return orders == by_id_.size();
    }

    std::string depth() const {
        std::array<std::string, 2> s;
        for (sz i = 0; i < 2; ++i)
            for (const auto& [k, l] : levels_[i]) s[i] += std::format("{}{}x{}", s[i].empty() ? "" : " ", px(l.price), l.qty);
        return std::format("bids [{}] asks [{}]", s[0], s[1]);
    }
};

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

/** Folds every event into one 64-bit hash: equal hashes = identical event streams (same rule as the Java listing). */
struct HashSink final : Sink {
    u64 h = 0;
    i64 trades = 0, volume = 0, rejects = 0;
    void mix(u64 kind, i64 a, i64 b, i64 c, i64 d) {
        h = mix64(h ^ kind);
        for (const i64 x : {a, b, c, d}) h = mix64(h ^ static_cast<u64>(x));
    }
    void accepted(i64 id) override { mix(1, id, 0, 0, 0); }
    void rejected(i64 id, std::string_view) override {
        ++rejects;
        mix(2, id, 0, 0, 0);
    }
    void trade(i64 maker, i64 taker, i64 price, i64 qty) override {
        ++trades;
        volume += qty;
        mix(3, maker, taker, price, qty);
    }
    void cancelled(i64 id, i64 remaining) override { mix(4, id, remaining, 0, 0); }
    void amended(i64 id, bool kept) override { mix(5, id, kept ? 1 : 0, 0, 0); }
};

/** Records events as text for the scripted demo. */
struct TextSink final : Sink {
    std::vector<std::string> lines;
    std::vector<std::array<i64, 4>> trades;
    void accepted(i64) override {}
    void rejected(i64 id, std::string_view reason) override { lines.push_back(std::format("rejected #{}: {}", id, reason)); }
    void trade(i64 maker, i64 taker, i64 price, i64 qty) override {
        trades.push_back({maker, taker, price, qty});
        lines.push_back(std::format("trade #{} x{} @{}", maker, qty, px(price)));
    }
    void cancelled(i64 id, i64 remaining) override { lines.push_back(std::format("cancelled #{} x{}", id, remaining)); }
    void amended(i64 id, bool kept) override { lines.push_back(std::format("amended #{} {}", id, kept ? "(kept priority)" : "(lost priority)")); }
};

struct Rng {
    u64 s;
    int below(int n) { return static_cast<int>(mix64(s++) % static_cast<u64>(n)); }
};

/** Deterministic order flow: 60% new orders around the mid, 30% cancels, 10% amends of this flow's earlier ids. */
struct Flow {
    Rng r;
    i64 base;
    i64 issued = 0;
    Command next() {
        const int k = r.below(100);
        if (k < 60 || issued == 0) {
            const i64 id = base + ++issued;
            const Side side = r.below(2) == 0 ? Side::Buy : Side::Sell;
            const int t = r.below(20);
            const Type type = t == 0 ? Type::Market : t == 1 ? Type::Ioc : t == 2 ? Type::Fok : Type::Limit;
            const i64 price = side == Side::Buy ? kMid - 20 + r.below(25) : kMid - 4 + r.below(25);
            const i64 qty = 1 + r.below(100);
            return Place{id, side, type, price, qty};
        }
        const i64 target = base + 1 + r.below(static_cast<int>(issued));
        if (k < 90) return Cancel{target};
        const i64 price = kMid - 10 + r.below(21);
        const i64 qty = 1 + r.below(100);
        return Amend{target, price, qty};
    }
};

/** Bounded multi-producer / single-consumer ring (per-slot sequence numbers, Vyukov style): the sequencer. */
template <class T> class MpscRing {
    struct alignas(64) Cell {  // one cell per cache line: producers on neighbouring slots don't false-share
        std::atomic<u64> seq;
        T value;
    };
    std::vector<Cell> cells_;
    const u64 mask_;
    alignas(64) std::atomic<u64> tail_{0};
    alignas(64) u64 head_ = 0;  // consumer-owned

public:
    explicit MpscRing(u64 capacity_pow2) : cells_(capacity_pow2), mask_(capacity_pow2 - 1) {
        for (u64 i = 0; i < capacity_pow2; ++i) cells_[i].seq.store(i, std::memory_order_relaxed);
    }
    void push(const T& v) {
        const u64 pos = tail_.fetch_add(1, std::memory_order_relaxed);  // claim a slot: one atomic op per producer
        Cell& c = cells_[pos & mask_];
        while (c.seq.load(std::memory_order_acquire) != pos) {}          // ring full: wait for the consumer to free this slot
        c.value = v;
        c.seq.store(pos + 1, std::memory_order_release);                 // publish
    }
    bool pop(T& out) {
        Cell& c = cells_[head_ & mask_];
        if (c.seq.load(std::memory_order_acquire) != head_ + 1) return false;
        out = c.value;
        c.seq.store(head_ + mask_ + 1, std::memory_order_release);       // free the slot for the producer one lap later
        ++head_;
        return true;
    }
};

template <class F>
void parallel(int threads, F body) {  // spin gate with a ready count (see P6)
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {}
            body(t);
        });
    while (ready.load() < threads) {}
    go.store(true, std::memory_order_release);
}

struct Run { u64 hash; i64 millis; bool replay_matches, invariants; };

u64 replay(const std::vector<Command>& log) {
    Book b;
    HashSink s;
    for (const auto& c : log) b.apply(c, s);
    return s.h;
}

i64 ms_since(std::chrono::steady_clock::time_point t0) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
}

Run event_loop(int producers, int per_producer) {
    MpscRing<Command> ring(1u << 16);
    Book book;
    HashSink sink;
    std::vector<Command> log(static_cast<sz>(producers * per_producer));
    const auto t0 = std::chrono::steady_clock::now();
    parallel(producers + 1, [&](int t) {
        if (t == producers) {  // the matcher: the only thread that touches the book
            for (sz n = 0; n < log.size();) {
                if (!ring.pop(log[n])) continue;
                book.apply(log[n], sink);  // the sequenced input IS the journal
                ++n;
            }
            return;
        }
        Flow f{Rng{100 + static_cast<u64>(t)}, (t + 1) * 1'000'000'000LL};
        for (int i = 0; i < per_producer; ++i) ring.push(f.next());  // gateway work runs here, in parallel
    });
    const i64 ms = ms_since(t0);
    return {sink.h, ms, replay(log) == sink.h, book.invariants_hold()};
}

Run locked(int producers, int per_producer) {
    Book book;
    HashSink sink;
    std::mutex m;
    std::vector<Command> log;  // guarded by m
    log.reserve(static_cast<sz>(producers * per_producer));
    const auto t0 = std::chrono::steady_clock::now();
    parallel(producers, [&](int t) {
        Flow f{Rng{100 + static_cast<u64>(t)}, (t + 1) * 1'000'000'000LL};
        for (int i = 0; i < per_producer; ++i) {
            const Command c = f.next();
            std::scoped_lock l(m);
            log.push_back(c);
            book.apply(c, sink);
        }
    });
    const i64 ms = ms_since(t0);
    return {sink.h, ms, replay(log) == sink.h, book.invariants_hold()};
}

/** "12.34" -> 1234 ticks. More decimals than the tick allows is a rejection, never a rounding. */
std::expected<i64, std::string> parse_ticks(std::string_view s) {
    i64 v = 0;
    int decimals = -1;
    for (const char ch : s) {
        if (ch == '.' && decimals < 0) { decimals = 0; continue; }
        if (ch < '0' || ch > '9') return std::unexpected(std::format("{} is not a plain decimal", s));
        if (decimals >= 0 && ++decimals > 2) return std::unexpected(std::format("{} is not a multiple of the 0.01 tick", s));
        v = v * 10 + (ch - '0');
    }
    for (int i = std::max(decimals, 0); i < 2; ++i) v *= 10;
    return v;
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Price-time priority, partial fills, MARKET / IOC / FOK, amend priority, cancel ==");
    Book book;
    const std::vector<Command> script{
        Place{1, Side::Sell, Type::Limit, 10'010, 50}, Place{2, Side::Sell, Type::Limit, 10'010, 30},
        Place{3, Side::Sell, Type::Limit, 10'020, 40}, Place{4, Side::Buy, Type::Limit, 10'000, 25},
        Place{5, Side::Buy, Type::Limit, 10'010, 60},  Place{6, Side::Buy, Type::Market, 0, 50},
        Place{7, Side::Sell, Type::Ioc, 9'990, 40},    Place{8, Side::Buy, Type::Fok, 10'020, 20},
        Place{9, Side::Sell, Type::Limit, 10'030, 10}, Place{10, Side::Sell, Type::Limit, 10'030, 10},
        Amend{9, 10'030, 5},                           Amend{9, 10'030, 15},
        Place{13, Side::Buy, Type::Limit, 10'030, 12}, Cancel{10},
        Cancel{10},                                    Place{16, Side::Buy, Type::Limit, 9'950, 100},
    };
    std::vector<std::array<i64, 4>> all_trades;
    bool invariants = true;
    for (const auto& c : script) {
        TextSink s;
        book.apply(c, s);
        invariants = invariants && book.invariants_hold();
        all_trades.insert(all_trades.end(), s.trades.begin(), s.trades.end());
        const auto [what, id] = std::visit(
            overloaded{
                [](const Place& p) {
                    return std::pair{std::format("#{} {} {}{} x{}", p.id, name(p.side), name(p.type), p.type == Type::Market ? "" : " " + px(p.price), p.qty), p.id};
                },
                [](const Cancel& x) { return std::pair{std::format("cancel #{}", x.id), x.id}; },
                [](const Amend& a) { return std::pair{std::format("amend #{} to {} x{}", a.id, px(a.price), a.qty), a.id}; },
            },
            c);
        if (const Order* o = book.find(id); o && !std::holds_alternative<Cancel>(c)) s.lines.push_back(std::format("rests x{}", o->remaining));
        std::string joined;
        for (const auto& l : s.lines) joined += (joined.empty() ? "" : ", ") + l;
        std::println("  {:<30} -> {}", what, joined.empty() ? "rests" : joined);
    }
    const std::string final_depth = book.depth();
    std::println("  book: {}", final_depth);

    std::println("== 2. Price keys: double equality vs ordering, and ticks ==");
    std::map<double, int> by_double;
    ++by_double[0.1 + 0.2];
    ++by_double[0.3];
    std::println("  prices 0.1 + 0.2 and 0.3 as std::map<double> keys: {} levels ({} vs {})", by_double.size(), 0.1 + 0.2, 0.3);
    for (const std::string_view s : {"100.10", "100.105"}) {
        const auto t = parse_ticks(s);
        std::println("  {} -> {}", s, t ? std::format("{} ticks", *t) : "rejected: " + t.error());
    }

    std::println("== 3. Cancel cost: one level with 50,000 resting orders, cancel 25,000 at random ==");
    constexpr sz depth = 50'000, cancels = 25'000;
    std::vector<Order> orders;
    for (sz i = 0; i < depth; ++i) orders.push_back(Order{static_cast<i64>(i), Side::Sell, kMid, 1});
    std::vector<sz> perm(depth);
    for (sz i = 0; i < depth; ++i) perm[i] = i;
    Rng r3{9};
    for (sz i = depth - 1; i > 0; --i) std::swap(perm[i], perm[static_cast<sz>(r3.below(static_cast<int>(i + 1)))]);
    std::deque<Order*> dq;
    for (auto& o : orders) dq.push_back(&o);
    auto t0 = std::chrono::steady_clock::now();
    for (sz i = 0; i < cancels; ++i) dq.erase(std::ranges::find(dq, &orders[perm[i]]));  // O(n) scan + shift per cancel
    const double deque_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    Level level{kMid};
    for (auto& o : orders) level.append(&o);
    t0 = std::chrono::steady_clock::now();
    for (sz i = 0; i < cancels; ++i) level.unlink(&orders[perm[i]]);  // O(1) given the order (found via the id map)
    const double intrusive_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    u64 hd = 0, hl = 0;
    for (const Order* o : dq) hd = mix64(hd ^ static_cast<u64>(o->id));
    for (const Order* o = level.head; o; o = o->next) hl = mix64(hl ^ static_cast<u64>(o->id));
    std::println("  std::deque find+erase {:.1f} ms | intrusive unlink {:.2f} ms | same FIFO left ({} orders): {}", deque_ms, intrusive_ms, level.count,
                 hd == hl && dq.size() == static_cast<sz>(level.count));

    std::println("== 4. 1,000,000 deterministic commands through one book (same flow and hash rule as the Java listing) ==");
    Book big;
    HashSink hs;
    Flow flow{Rng{5}, 0};
    bool big_ok = true;
    t0 = std::chrono::steady_clock::now();
    for (int i = 1; i <= 1'000'000; ++i) {
        big.apply(flow.next(), hs);
        if (i % 100'000 == 0) big_ok = big_ok && big.invariants_hold();
    }
    const auto big_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count();
    std::println("  trades {}, volume {}, rejects {}, resting orders {} on {}+{} levels | event hash {:x}", hs.trades, hs.volume, hs.rejects, big.orders(),
                 big.bid_levels(), big.ask_levels(), hs.h);
    std::println("  {} ns per command (single thread, including invariant checks every 100k)", big_ns / 1'000'000);

    std::println("== 5. 4 gateway threads x 250,000 commands: sequencer ring + one matcher vs a mutex around the book ==");
    const Run loop = event_loop(4, 250'000), lock = locked(4, 250'000);
    for (const Run* run : {&loop, &lock})
        std::println("  {:<34} {} ms ({:.2f} M commands/s) | replaying the sequenced log reproduces the live hash: {} | invariants {}",
                     run == &loop ? "MPSC ring -> single matcher:" : "4 threads, std::mutex around book:", run->millis,
                     1'000'000 / 1'000.0 / static_cast<double>(std::max<i64>(1, run->millis)), run->replay_matches, run->invariants);

    const bool ok = invariants && all_trades.size() == 7 && all_trades[0][0] == 1 && all_trades[0][3] == 50 && all_trades[1][0] == 2 &&
                    all_trades[1][3] == 10 && all_trades[3][0] == 3 && all_trades[3][2] == 10'020 && all_trades[4][0] == 4 && all_trades[5][0] == 3 &&
                    all_trades[6][0] == 10 && all_trades[6][3] == 2 && final_depth == "bids [99.50x100] asks [100.30x15]" && by_double.size() == 2 &&
                    hd == hl && big_ok && loop.replay_matches && loop.invariants && lock.replay_matches && lock.invariants;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Price-time priority, partial fills, MARKET / IOC / FOK, amend priority, cancel ==
  #1 SELL LIMIT 100.10 x50       -> rests x50
  #2 SELL LIMIT 100.10 x30       -> rests x30
  #3 SELL LIMIT 100.20 x40       -> rests x40
  #4 BUY LIMIT 100.00 x25        -> rests x25
  #5 BUY LIMIT 100.10 x60        -> trade #1 x50 @100.10, trade #2 x10 @100.10
  #6 BUY MARKET x50              -> trade #2 x20 @100.10, trade #3 x30 @100.20
  #7 SELL IOC 99.90 x40          -> trade #4 x25 @100.00, cancelled #7 x15
  #8 BUY FOK 100.20 x20          -> cancelled #8 x20
  #9 SELL LIMIT 100.30 x10       -> rests x10
  #10 SELL LIMIT 100.30 x10      -> rests x10
  amend #9 to 100.30 x5          -> amended #9 (kept priority), rests x5
  amend #9 to 100.30 x15         -> amended #9 (lost priority), rests x15
  #13 BUY LIMIT 100.30 x12       -> trade #3 x10 @100.20, trade #10 x2 @100.30
  cancel #10                     -> cancelled #10 x8
  cancel #10                     -> rejected #10: unknown order
  #16 BUY LIMIT 99.50 x100       -> rests x100
  book: bids [99.50x100] asks [100.30x15]
== 2. Price keys: double equality vs ordering, and ticks ==
  prices 0.1 + 0.2 and 0.3 as std::map<double> keys: 2 levels (0.30000000000000004 vs 0.3)
  100.10 -> 10010 ticks
  100.105 -> rejected: 100.105 is not a multiple of the 0.01 tick
== 3. Cancel cost: one level with 50,000 resting orders, cancel 25,000 at random ==
  std::deque find+erase 403.2 ms | intrusive unlink 0.27 ms | same FIFO left (25000 orders): true
== 4. 1,000,000 deterministic commands through one book (same flow and hash rule as the Java listing) ==
  trades 232198, volume 5932019, rejects 261806, resting orders 207865 on 18+20 levels | event hash 7c47c5588e0d5454
  308 ns per command (single thread, including invariant checks every 100k)
== 5. 4 gateway threads x 250,000 commands: sequencer ring + one matcher vs a mutex around the book ==
  MPSC ring -> single matcher:       295 ms (3.39 M commands/s) | replaying the sequenced log reproduces the live hash: true | invariants true
  4 threads, std::mutex around book: 399 ms (2.51 M commands/s) | replaying the sequenced log reproduces the live hash: true | invariants true
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Price-time priority, partial fills, MARKET / IOC / FOK, amend priority, cancel ==
  #1 SELL LIMIT 100.10 x50       -> rests x50
  #2 SELL LIMIT 100.10 x30       -> rests x30
  #3 SELL LIMIT 100.20 x40       -> rests x40
  #4 BUY LIMIT 100.00 x25        -> rests x25
  #5 BUY LIMIT 100.10 x60        -> trade #1 x50 @100.10, trade #2 x10 @100.10
  #6 BUY MARKET x50              -> trade #2 x20 @100.10, trade #3 x30 @100.20
  #7 SELL IOC 99.90 x40          -> trade #4 x25 @100.00, cancelled #7 x15
  #8 BUY FOK 100.20 x20          -> cancelled #8 x20
  #9 SELL LIMIT 100.30 x10       -> rests x10
  #10 SELL LIMIT 100.30 x10      -> rests x10
  amend #9 to 100.30 x5          -> amended #9 (kept priority), rests x5
  amend #9 to 100.30 x15         -> amended #9 (lost priority), rests x15
  #13 BUY LIMIT 100.30 x12       -> trade #3 x10 @100.20, trade #10 x2 @100.30
  cancel #10                     -> cancelled #10 x8
  cancel #10                     -> rejected #10: unknown order
  #16 BUY LIMIT 99.50 x100       -> rests x100
  book: bids [99.50x100] asks [100.30x15]
== 2. Price keys: double equality vs ordering, and ticks ==
  prices 0.1 + 0.2 and 0.3 as std::map<double> keys: 2 levels (0.30000000000000004 vs 0.3)
  100.10 -> 10010 ticks
  100.105 -> rejected: 100.105 is not a multiple of the 0.01 tick
== 3. Cancel cost: one level with 50,000 resting orders, cancel 25,000 at random ==
  std::deque find+erase 163.8 ms | intrusive unlink 0.27 ms | same FIFO left (25000 orders): true
== 4. 1,000,000 deterministic commands through one book (same flow and hash rule as the Java listing) ==
  trades 232198, volume 5932019, rejects 261806, resting orders 207865 on 18+20 levels | event hash 7c47c5588e0d5454
  286 ns per command (single thread, including invariant checks every 100k)
== 5. 4 gateway threads x 250,000 commands: sequencer ring + one matcher vs a mutex around the book ==
  MPSC ring -> single matcher:       318 ms (3.14 M commands/s) | replaying the sequenced log reproduces the live hash: true | invariants true
  4 threads, std::mutex around book: 264 ms (3.79 M commands/s) | replaying the sequenced log reproduces the live hash: true | invariants true
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Book | `List<Order>` sorted on insert | `TreeMap<price, ArrayDeque>` | Sorted levels plus an intrusive FIFO and an id index: O(log L) level lookup, O(1) cancel, trades at the maker's price, and FOK checked before executing |
| Prices | `double` | `BigDecimal` keys | Integer ticks; reject sub-tick input at the gateway; never hash `BigDecimal` |
| Concurrency | `synchronized` everywhere | One lock per book | Single-writer matcher fed by an MPSC ring; the sequenced log is the journal; replicas replay it; one matcher per symbol shard; honest about throughput vs tail latency |
| Hot path | Allocation per event | Pooled orders | Node arena and free list, primitive-keyed maps (e.g. Agrona), a price ladder array for dense instruments, and busy-spin wait strategies |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Self-trade prevention" | Check the maker's account against the taker's in `match()`. Policies: cancel newest, cancel oldest, or decrement both. It's one branch in the loop, and it's deterministic |
| "Iceberg orders" | Display quantity plus a hidden reserve. When the displayed part fills, replenish from the reserve **at the back** of the level (it loses priority), emitting an event so replay stays exact |
| "Stop orders" | A separate trigger book keyed by stop price. After each trade, release triggered stops as new commands **into the same sequenced stream**, never as a side channel |
| "Many symbols" | Shard by symbol: N rings and N matchers. Cross-symbol orders (spreads) need a coordinator or a combined book |
| "Market data feed" | Derive L2 incremental updates from the event stream (level qty changes) with sequence numbers, so clients detect gaps and request a snapshot |
| "Crash recovery" | Periodic snapshot of the book at sequence S plus journal replay from S; a hot standby consumes the same ring output |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Lock each price level so takers on different levels run in parallel."</b></summary>

**L5:** "Finer locks means more parallelism."

**Why it fails:** a sweep spans levels and depends on the current best price. Interleaved sweeps double-fill makers or trade through better prices. Price-time priority is itself a total order.

**L7 defence:** "Serialize per instrument and make that cheap: one matcher thread owns the book, gateways do the parallel work and publish into an MPSC ring, and the ring order is the journal. I measured no throughput win over a single lock here. The reasons are determinism, cache residency, no convoys and free replication, and I'd shard by symbol for scale."
</details>

<details>
<summary><b>Q2 ⚡ "How fast is your cancel?"</b></summary>

**L5:** "`deque.remove(order)`."

**Why it fails:** O(n). 25,000 cancels on a 50,000-deep level took 164–403 ms, against 0.27 ms intrusive (C++).

**L7 defence:** "An id → node map plus a doubly-linked FIFO per level: unlink in O(1), drop the level when it empties. Or lazy tombstones with compaction, if nodes must stay in arrays."
</details>

<details>
<summary><b>Q3 ⚡ "The engine process dies. What now?"</b></summary>

**L5:** "Restart it."

**Why it fails:** the resting orders are gone, or they get rebuilt in a different order. Different priority means different fills.

**L7 defence:** "The sequenced input is journaled before or while it's applied. Recovery = latest snapshot + replay. Determinism makes the result identical; the listing's replay hash equals the live hash. A standby replays the same stream and can take over at a known sequence number."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Two levels for the same price | `BigDecimal.equals` / `double` keys | Integer ticks |
| Cancel latency grows with depth | `ArrayDeque.remove` | Intrusive FIFO + id map |
| FOK partially filled | Matched before checking liquidity | `available()` first, then execute |
| Amend jumps the queue | Increase treated as in-place | Only reduce-only at the same price keeps priority |
| Replica diverges | Non-deterministic inputs (time, iteration order) inside the matcher | Everything enters through the sequenced stream; no wall clock in matching |

- [ ] Price-time priority; trades at the maker's price; FOK/IOC/MARKET semantics exact.
- [ ] O(1) cancel; levels removed when empty; invariants checkable.
- [ ] Integer ticks, sub-tick rejected at the gateway.
- [ ] Single writer per book; MPSC ring as the sequencer; journal + snapshot recovery.
- [ ] Determinism verified by replay (and, here, across languages).

## 10. References

- Martin Fowler, *The LMAX Architecture*. <https://martinfowler.com/articles/lmax.html>
- LMAX Disruptor. <https://lmax-exchange.github.io/disruptor/>
- Dmitry Vyukov, *Bounded MPMC queue*. <https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue>
- Java `ArrayDeque` (`remove(Object)` is linear). <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/ArrayDeque.html>
- In this KB: [P11 BigDecimal traps](01-problem-11-splitwise-expense-sharing-and-min-cash-flow-graph-simplifier.md) · [P17 MPSC ring buffer in a logger](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md) · [01.3 SPSC rings and false sharing](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md)
