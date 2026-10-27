# P15 · Flash Sale: Hot-SKU Inventory Without a Hot Row, TTL Holds, and Promotions That Stack (or Don't)

> **Folder 05 · Problem 15 of 20.** At 09:00 a million people want the same SKU. This problem covers:
> - **one counter** is the bottleneck, whether a row lock or a single CAS cache line;
> - **K striped buckets** remove it, but only if buyers spread over the buckets and the last units don't strand;
> - **holds** must expire without racing payment;
> - **promotions** must respect exclusivity, a fixed phase order, and line-level attribution so returns refund the right amount.
>
> The measurements include a striping layout that was *no faster* than one CAS, and why.
>
> **Listing pair P15:** `FlashSale.java` / `flash_sale.cpp`. Section 4 is deterministic and **byte-identical in Java, GCC and Clang**; sections 1–3 show one measured run.

---

## 1. Problem and scope

**Functional:**
- Buy N units of a flash-sale SKU.
- Hold units in a cart for 10 minutes; pay to confirm, or the hold expires back to stock.
- One hold per customer.
- Promotions: category and SKU sales, buy-2-get-1, cart percentages with caps, fixed amounts over a threshold, coupons.

**Non-functional:**
- **Never oversell.**
- Never say "sold out" while stock remains.
- Throughput on one SKU must not be bounded by one memory location.

**Out of scope:** the queueing/waiting-room front end (a token bucket admission layer, [P2](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/02-problem-02-pluggable-rate-limiter-token-bucket-sliding-window-cas.md)) and persistence (§7).

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Inventory | `interface Inventory { take(qty, home); giveBack; available }`: `MapGetPut`, `AdderCheckThenAdd` (bugs), `Locked`, `SingleCas`, `Striped(k, steal)` | the same (`LoadThenStore`; a hand-built striped adder, since C++ has no `LongAdder`) |
| Buckets | `AtomicLongArray`, stride 8 longs (64 B) | `alignas(64) struct Cell { std::atomic<i64> }` |
| Hold | `sealed Hold permits Held(user, qty, expires), Confirmed, Released`, in a `ConcurrentHashMap<user, Hold>` | `std::variant` in a mutex-striped map |
| Promotion | `record Promo(id, group, phase, Spec when, Discount how)`: `Spec` composable; `sealed Discount permits PercentOff, BuyNGetOneFree, PercentOffCart, FixedOffCart` | `Spec = std::function<bool(const Cart&)>` with `&&`; `Discount` variant |
| Price | `Priced(lineNet[], total, applied)`; integer cents, HALF_EVEN, largest-remainder attribution | the same |

**Invariants:**
- **I1:** sold ≤ stock; a correct inventory ends at exactly 0 left (buyers stop only when even one unit is refused).
- **I2:** available + held + confirmed = initial at every quiescent point.
- **I3:** every hold ends **exactly once**, confirmed or released. A payment and an expiry can't both win.
- **I4:** at most one promotion per exclusive group; stackables apply in a fixed phase order (item → cart % → cart fixed), ties by id.
- **I5:** cart-level discounts are attributed to lines, and the line nets sum exactly to the total.

## 3. Concurrency and contention analysis

### 3.1 The hot counter

**2,000,000 units, 8 buyers** taking 1–3 units until refused:

| Inventory | Java | GCC | Clang |
|---|---|---|---|
| CHM `get` then `put` / relaxed load + store | **sold 6.9 M** (stock "regenerates": a stale `put` overwrites other decrements) | 7.6 M | 5.1 M |
| `LongAdder.sum()` then `add(-q)` | **oversold 7** | oversold 4 | oversold 3 |
| `synchronized` / `std::mutex` | exact, 86 ms | exact, 119 ms | exact, 88 ms |
| One `AtomicLong` CAS loop | exact, 136 ms, **1.85 M retries** | exact, 99 ms, 1.81 M | exact, 97 ms, 1.98 M |
| **16 padded CAS buckets** + stealing + collapse | exact, **40 ms**, 154 k retries | exact, **29 ms**, 111 k | exact, **38 ms**, 56 k |

**`LongAdder` is a trap for inventory.** It's the fastest *counter*, but it has no conditional decrement, so "check then add" oversells. It oversold in 5 of 6 runs (published + gate rerun); the GCC gate rerun happened to oversell 0, so a clean run is no evidence of correctness. Striping has to be striping of **CAS-guarded buckets**.

**Bucket selection matters (measured on the way here).** The first harness used `home = thread id`: 8 threads on 16 buckets. Half the buckets were reachable only by stealing, every thread stole in the same direction, and they **herded** onto the same buckets. Striping was then no faster than one CAS (GCC 91 ms, 1.78 M retries). Hashing the *customer* to a bucket spreads load the way real traffic does, and gives 29–40 ms with 12–35× fewer retries.

### 3.2 The last units

Striping has two end-game failure modes:
- **Stranded stock.** With "my bucket is empty ⇒ sold out" (no stealing), all 8 buyers were told *sold out* with **5,000 of 10,000** units still in buckets 8..15.
- **Fragmentation.** Every bucket holds 1, the total is 16, and a buyer wants 2. Stealing alone still refuses.

The `Striped` slow path fixes both:
1. Under a lock, drain every bucket into bucket 0 with `getAndSet(0)` and `addAndGet`.
2. Retry there.

Units are moved, never copied, so there's no oversell. The slow path ran 16 times per sale, only at the very end, and the sale ended at exactly 0 left. Production systems do the same: switch to a single counter, or a central allocator, below a low-water mark.

### 3.3 Holds: claim cheap things first, and let one CAS decide

`reserve(user, qty)` runs in two steps, cheap and reversible first:
1. `putIfAbsent(user, Held)` enforces one hold per customer. All duplicate clicks were refused: 661 of 661.
2. `inventory.take(qty)`. If it fails, `remove(user, held)` undoes step 1.

**Payment vs expiry.** `confirm()` checks `now < expires` and then `replace(user, held, Confirmed)`. `sweep()` checks `now ≥ expires` and then `replace(user, held, Released)` + `giveBack`. Both CAS the **same** `Held` value, so exactly one wins.

**The race in the listing:** the clock ticks over the deadline a quarter of the way through the payments, while a sweeper runs. It ended with 222 holds confirmed, 668 units released, 0 still held, and `available + held + confirmed = 1000`.

### 3.4 Promotions: eligibility, exclusivity, order and attribution

These are four separate concerns:

| Concern | Mechanism |
|---|---|
| **Eligibility** | `Spec`, composable predicates on the cart as submitted |
| **Exclusivity** | Groups: try none or one member per group, keep the cheapest total |
| **Order** | Phases, because order changes the price: on 300.00, *10% then 20.00 off = 250.00*, but *20.00 off then 10% = 252.00* |
| **Attribution** | Each cart-level discount spread over lines by largest remainder (P11), so a return refunds that line's share |

**Measured on the example cart** (subtotal 244.97, both coupons entered, first order):

| Strategy | Total | Promotions applied |
|---|---|---|
| Every eligible promotion, in list order | **130.02** | ELEC10, HEAD15, SAVE10, WELCOME15, … (both coupons and both sales: the shop loses money) |
| First eligible per group | 175.27 | — |
| Engine: best combination | **164.97** | HEAD15 + WELCOME15 + SOCKS3FOR2 + BIG20 |

Line nets after attribution sum to 164.97 exactly, and returning one headphone refunds 66.77.

**Concurrency in promotions:**
- "First 1,000 redemptions" is the same bounded-decrement problem as inventory (§3.1).
- "One use per customer" is the same `putIfAbsent` as holds.

## 4. Java 21 implementation

```java
// FlashSale.java - P15: striped inventory counters without a hot row, TTL holds, specification promotions (stackable vs exclusive)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.StringJoiner;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;

public final class FlashSale {

    // ---- inventory: one hot SKU

    interface Inventory {
        boolean take(int qty, int home);                               // all-or-nothing; home = the caller's preferred stripe

        void giveBack(int qty, int home);

        long available();
    }

    /** The bug: get() then put() on a ConcurrentHashMap. Two buyers read the same stock. */
    static final class MapGetPut implements Inventory {
        final ConcurrentHashMap<String, Long> stock = new ConcurrentHashMap<>();

        MapGetPut(long units) {
            stock.put("sku", units);
        }

        @Override
        public boolean take(int qty, int home) {
            long cur = stock.get("sku");
            if (cur < qty) return false;
            stock.put("sku", cur - qty);
            return true;
        }

        @Override
        public void giveBack(int qty, int home) {
            stock.merge("sku", (long) qty, Long::sum);
        }

        @Override
        public long available() {
            return stock.get("sku");
        }
    }

    /** The other bug: "LongAdder is the fast counter". It is, but it cannot do a conditional decrement. */
    static final class AdderCheckThenAdd implements Inventory {
        final LongAdder stock = new LongAdder();

        AdderCheckThenAdd(long units) {
            stock.add(units);
        }

        @Override
        public boolean take(int qty, int home) {
            if (stock.sum() < qty) return false;
            stock.add(-qty);
            return true;
        }

        @Override
        public void giveBack(int qty, int home) {
            stock.add(qty);
        }

        @Override
        public long available() {
            return stock.sum();
        }
    }

    static final class Locked implements Inventory {
        long stock;                                                    // guarded by this

        Locked(long units) {
            stock = units;
        }

        @Override
        public synchronized boolean take(int qty, int home) {
            if (stock < qty) return false;
            stock -= qty;
            return true;
        }

        @Override
        public synchronized void giveBack(int qty, int home) {
            stock += qty;
        }

        @Override
        public synchronized long available() {
            return stock;
        }
    }

    /** Correct and lock-free, but every buyer CASes the same cache line: the hot row moved into the CPU. */
    static final class SingleCas implements Inventory {
        final AtomicLong stock;
        final LongAdder retries = new LongAdder();

        SingleCas(long units) {
            stock = new AtomicLong(units);
        }

        @Override
        public boolean take(int qty, int home) {
            for (long cur = stock.get(); cur >= qty; cur = stock.get()) {
                if (stock.compareAndSet(cur, cur - qty)) return true;
                retries.increment();
            }
            return false;
        }

        @Override
        public void giveBack(int qty, int home) {
            stock.addAndGet(qty);
        }

        @Override
        public long available() {
            return stock.get();
        }
    }

    /**
     * K padded sub-buckets ("inventory tokens"). A buyer CASes its home bucket and steals from the others when it is
     * empty. When every bucket is below qty but the total is not (fragmentation), a slow path drains all buckets into
     * bucket 0 under a lock and retries there. Units are only ever moved by getAndSet/addAndGet, never duplicated.
     */
    static final class Striped implements Inventory {
        static final int PAD = 8;                                      // 8 longs = 64 bytes between buckets
        final int k;
        final boolean steal;
        final AtomicLongArray buckets;
        final LongAdder retries = new LongAdder(), slowPaths = new LongAdder();

        Striped(long units, int k, boolean steal) {
            this.k = k;
            this.steal = steal;
            buckets = new AtomicLongArray(k * PAD);
            for (int b = 0; b < k; b++) buckets.set(b * PAD, units / k + (b < units % k ? 1 : 0));
        }

        boolean takeFrom(int b, int qty) {
            for (long cur = buckets.get(b * PAD); cur >= qty; cur = buckets.get(b * PAD)) {
                if (buckets.compareAndSet(b * PAD, cur, cur - qty)) return true;
                retries.increment();
            }
            return false;
        }

        @Override
        public boolean take(int qty, int home) {
            int first = Math.floorMod(home, k);
            for (int i = 0; i < (steal ? k : 1); i++)
                if (takeFrom((first + i) % k, qty)) return true;
            if (!steal) return false;                                  // the naive variant: "my bucket is empty = sold out"
            synchronized (this) {                                      // fragmentation: collapse into one bucket, rare
                slowPaths.increment();
                long moved = 0;
                for (int b = 1; b < k; b++) moved += buckets.getAndSet(b * PAD, 0);
                buckets.addAndGet(0, moved);
                return takeFrom(0, qty);
            }
        }

        @Override
        public void giveBack(int qty, int home) {
            buckets.addAndGet(Math.floorMod(home, k) * PAD, qty);
        }

        @Override
        public long available() {
            long s = 0;
            for (int b = 0; b < k; b++) s += buckets.get(b * PAD);
            return s;
        }
    }

    // ---- holds with a TTL: claim the customer slot, then the stock; confirm and expiry race on one CAS

    sealed interface Hold permits Held, Confirmed, Released {}
    record Held(String user, int qty, Instant expires) implements Hold {}
    record Confirmed(String user, int qty) implements Hold {}
    record Released(String user, int qty) implements Hold {}

    static final class Reservations {
        final Inventory inv;
        final Clock clock;
        final Duration ttl;
        final ConcurrentHashMap<String, Hold> byUser = new ConcurrentHashMap<>();

        Reservations(Inventory inv, Clock clock, Duration ttl) {
            this.inv = inv;
            this.clock = clock;
            this.ttl = ttl;
        }

        String reserve(String user, int qty, int home) {
            Held h = new Held(user, qty, clock.instant().plus(ttl));
            Hold prior = byUser.putIfAbsent(user, h);                  // 1. one hold per customer (cheap, reversible)
            if (prior != null) return "rejected: " + user + " already has a hold";
            if (inv.take(qty, home)) return "held";                    // 2. the stock
            byUser.remove(user, h);                                    // undo step 1
            return "sold out";
        }

        boolean confirm(String user) {                                  // payment captured
            return byUser.get(user) instanceof Held h && clock.instant().isBefore(h.expires())
                    && byUser.replace(user, h, new Confirmed(user, h.qty()));
        }

        int sweep(int home) {                                           // expiry: the same CAS decides against confirm()
            int released = 0;
            for (Hold x : byUser.values())
                if (x instanceof Held h && !clock.instant().isBefore(h.expires()) && byUser.replace(h.user(), h, new Released(h.user(), h.qty()))) {
                    inv.giveBack(h.qty(), home);
                    released += h.qty();
                }
            return released;
        }

        long units(Class<? extends Hold> kind) {
            long n = 0;
            for (Hold x : byUser.values())
                if (kind.isInstance(x)) n += switch (x) {
                    case Held h -> h.qty();
                    case Confirmed c -> c.qty();
                    case Released r -> r.qty();
                };
            return n;
        }
    }

    static final class TestClock extends Clock {
        volatile Instant now = Instant.parse("2026-11-27T09:00:00Z");

        void advance(Duration d) {
            now = now.plus(d);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    // ---- promotions: specifications decide eligibility; groups decide exclusivity; phases decide order

    record Line(String sku, String category, long unitCents, int qty) {}

    record Cart(List<Line> lines, Set<String> coupons, boolean firstOrder) {
        long subtotal() {
            return lines.stream().mapToLong(l -> l.unitCents() * l.qty()).sum();
        }
    }

    @FunctionalInterface
    interface Spec {
        boolean test(Cart c);

        default Spec and(Spec o) {
            return c -> test(c) && o.test(c);
        }

        static Spec hasLine(String match) {
            return c -> c.lines().stream().anyMatch(l -> l.sku().equals(match) || l.category().equals(match));
        }

        static Spec coupon(String code) {
            return c -> c.coupons().contains(code);
        }

        static Spec firstOrder() {
            return Cart::firstOrder;
        }

        static Spec minSubtotal(long cents) {
            return c -> c.subtotal() >= cents;
        }
    }

    enum Phase { ITEM, CART_PERCENT, CART_FIXED }

    sealed interface Discount permits PercentOff, BuyNGetOneFree, PercentOffCart, FixedOffCart {}
    record PercentOff(String match, int pct) implements Discount {}   // lines whose sku or category matches
    record BuyNGetOneFree(String sku, int n) implements Discount {}
    record PercentOffCart(int pct, long capCents) implements Discount {}
    record FixedOffCart(long cents) implements Discount {}

    /** group == null: stackable. Otherwise at most one promotion per group is applied. */
    record Promo(String id, String group, Phase phase, Spec when, Discount how) {}

    record Priced(long[] lineNet, long total, List<String> applied) {}

    static long halfEven(long num, long den) {                          // RoundingMode.HALF_EVEN of num / den, num >= 0
        long q = num / den, r = num % den;
        return 2 * r > den || (2 * r == den && q % 2 == 1) ? q + 1 : q;
    }

    /** Takes `amount` off the lines in proportion to their current net, by largest remainder (ties: lower line index). */
    static void attribute(long[] net, long amount) {
        long total = 0;
        for (long x : net) total += x;
        if (amount == 0 || total == 0) return;
        long[] floor = new long[net.length], rem = new long[net.length];
        long given = 0;
        for (int i = 0; i < net.length; i++) {
            floor[i] = Math.multiplyExact(amount, net[i]) / total;
            rem[i] = Math.multiplyExact(amount, net[i]) % total;
            given += floor[i];
        }
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < net.length; i++) order.add(i);
        order.sort(Comparator.comparingLong((Integer i) -> -rem[i]).thenComparingInt(i -> i));
        for (int k = 0; k < amount - given; k++) floor[order.get(k)]++;
        for (int i = 0; i < net.length; i++) net[i] -= floor[i];
    }

    /** Applies promotions in the given order (the engine passes them sorted by phase); cart-level discounts are attributed to lines. */
    static Priced price(Cart c, List<Promo> promos) {
        long[] net = new long[c.lines().size()];
        for (int i = 0; i < net.length; i++) net[i] = c.lines().get(i).unitCents() * c.lines().get(i).qty();
        List<String> applied = new ArrayList<>();
        for (Promo p : promos) {
            if (!p.when().test(c)) continue;
            long cart = 0;
            for (long x : net) cart += x;
            switch (p.how()) {
                case PercentOff po -> {
                    for (int i = 0; i < net.length; i++) {
                        Line l = c.lines().get(i);
                        if (l.sku().equals(po.match()) || l.category().equals(po.match())) net[i] -= halfEven(net[i] * po.pct(), 100);
                    }
                }
                case BuyNGetOneFree b -> {
                    for (int i = 0; i < net.length; i++) {
                        Line l = c.lines().get(i);
                        if (l.sku().equals(b.sku())) net[i] -= Math.min(net[i], l.qty() / (b.n() + 1) * l.unitCents());
                    }
                }
                case PercentOffCart pc -> attribute(net, Math.min(halfEven(cart * pc.pct(), 100), pc.capCents() > 0 ? pc.capCents() : Long.MAX_VALUE));
                case FixedOffCart f -> attribute(net, Math.min(f.cents(), cart));
            }
            applied.add(p.id());
        }
        long total = 0;
        for (long x : net) total += x;
        return new Priced(net, total, applied);
    }

    /** Stackables always apply; for each exclusive group try none or one eligible member; keep the cheapest total. */
    static Priced bestCombination(Cart c, List<Promo> promos) {
        Map<String, List<Promo>> groups = new LinkedHashMap<>();
        List<Promo> stackable = new ArrayList<>();
        for (Promo p : promos) {
            if (!p.when().test(c)) continue;
            if (p.group() == null) stackable.add(p);
            else groups.computeIfAbsent(p.group(), g -> new ArrayList<>()).add(p);
        }
        List<List<Promo>> options = new ArrayList<>(groups.values());
        Priced best = null;
        int[] pick = new int[options.size()];                          // 0 = none, j = options[g][j - 1]
        while (true) {
            List<Promo> chosen = new ArrayList<>(stackable);
            for (int g = 0; g < options.size(); g++)
                if (pick[g] > 0) chosen.add(options.get(g).get(pick[g] - 1));
            chosen.sort(Comparator.comparing(Promo::phase).thenComparing(Promo::id));   // one fixed, documented order
            Priced p = price(c, chosen);
            if (best == null || p.total() < best.total() || (p.total() == best.total() && p.applied().size() < best.applied().size())) best = p;
            int g = 0;
            while (g < options.size() && ++pick[g] > options.get(g).size()) pick[g++] = 0;
            if (g == options.size()) return best;
        }
    }

    static String cents(long c) {
        return String.format("%d.%02d", c / 100, c % 100);
    }

    // ---- harness

    static long mix64(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
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

    interface Body {
        void run(int thread) throws Exception;
    }

    static long parallel(int threads, Body body) throws Exception {   // returns wall time in ms
        CyclicBarrier start = new CyclicBarrier(threads + 1), end = new CyclicBarrier(threads + 1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        for (int t = 0; t < threads; t++) {
            final int id = t;
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    body.run(id);
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                } finally {
                    try {
                        end.await();
                    } catch (Exception e) {
                        failure.compareAndSet(null, e);
                    }
                }
            });
        }
        start.await();
        long t0 = System.nanoTime();
        end.await();
        if (failure.get() != null) throw new IllegalStateException(failure.get());
        return (System.nanoTime() - t0) / 1_000_000;
    }

    record Sale(long sold, long left, long ms) {}

    /** 8 buyers each take 1-3 units until even 1 unit is refused. A correct inventory ends with exactly 0 left. */
    static Sale sell(Inventory inv, long units) throws Exception {
        LongAdder sold = new LongAdder();
        long ms = parallel(8, t -> {
            Rng r = new Rng(60 + t);
            for (;;) {
                int q = 1 + r.below(3), home = r.below(1 << 16);      // home = hash(customer): spreads buyers over all K buckets
                if (inv.take(q, home)) sold.add(q);
                else if (inv.take(1, home)) sold.add(1);
                else return;
            }
        });
        return new Sale(sold.sum(), inv.available(), ms);
    }

    public static void main(String[] args) throws Exception {
        long units = 2_000_000;
        System.out.println("== 1. One hot SKU, 2,000,000 units, 8 buyers taking 1-3 units until refused ==");
        Inventory[] invs = {new MapGetPut(units), new AdderCheckThenAdd(units), new Locked(units), new SingleCas(units), new Striped(units, 16, true)};
        String[] names = {"CHM get() then put()", "LongAdder sum() then add()", "synchronized counter", "one AtomicLong, CAS loop",
                "16 padded CAS buckets + stealing"};
        Sale[] sales = new Sale[invs.length];
        for (int i = 0; i < invs.length; i++) {
            sales[i] = sell(invs[i], units);
            String extra = invs[i] instanceof SingleCas s ? " | CAS retries " + s.retries.sum()
                    : invs[i] instanceof Striped s ? " | CAS retries " + s.retries.sum() + ", slow paths " + s.slowPaths.sum() : "";
            System.out.printf("  %-34s sold %d (oversold %d) | left %d | %d ms%s%n", names[i], sales[i].sold(), Math.max(0, sales[i].sold() - units),
                    sales[i].left(), sales[i].ms(), extra);
        }

        System.out.println("== 2. The last units: striping without stealing tells buyers 'sold out' while stock remains ==");
        Striped homeOnly = new Striped(10_000, 16, false), full = new Striped(10_000, 16, true);
        LongAdder refusedHome = new LongAdder();
        parallel(8, t -> {                                              // 8 buyers only ever touch buckets 0..7
            while (homeOnly.take(1, t)) Thread.onSpinWait();
            refusedHome.increment();
        });
        Sale fullSale = sell(full, 10_000);
        System.out.printf("  home bucket only: all 8 buyers told sold out with %d of 10000 units still in buckets 8..15%n", homeOnly.available());
        System.out.printf("  steal + collapse: sold %d, left %d, slow paths %d%n", fullSale.sold(), fullSale.left(), full.slowPaths.sum());

        System.out.println("== 3. Holds with a 10-minute TTL: 1,000 units, 3,000 customers, pay-or-expire races ==");
        TestClock clock = new TestClock();
        Striped inv = new Striped(1_000, 16, true);
        Reservations res = new Reservations(inv, clock, Duration.ofMinutes(10));
        LongAdder held = new LongAdder(), soldOut = new LongAdder(), dupes = new LongAdder();
        parallel(8, t -> {
            Rng r = new Rng(80 + t);
            for (int u = 0; u < 375; u++) {
                String user = "u" + (t * 375 + u);
                for (int attempt = 0; attempt < 2; attempt++) {         // the second click is a duplicate
                    String out = res.reserve(user, 1 + r.below(2), t);
                    (out.equals("held") ? held : out.equals("sold out") ? soldOut : dupes).increment();
                }
            }
        });
        long heldUnits = res.units(Held.class);
        System.out.printf("  reserve: %d holds (%d units), %d sold out, %d duplicate clicks refused | available %d%n", held.sum(), heldUnits, soldOut.sum(),
                dupes.sum(), inv.available());
        List<String> holders = new ArrayList<>();
        res.byUser.forEach((u, h) -> {
            if (h instanceof Held) holders.add(u);
        });
        holders.sort(Comparator.naturalOrder());
        clock.advance(Duration.ofMinutes(10).minusMillis(1));          // payments arrive right at the deadline...
        LongAdder confirmed = new LongAdder(), released = new LongAdder();
        AtomicLong attempts = new AtomicLong();
        parallel(9, t -> {
            if (t == 8) {                                               // ...and the clock ticks over a quarter of the way in
                while (attempts.get() < holders.size() / 4) Thread.onSpinWait();
                clock.advance(Duration.ofMillis(1));
                while (attempts.get() < holders.size()) released.add(res.sweep(t));
                return;
            }
            for (int i = t; i < holders.size(); i += 8) {
                if (res.confirm(holders.get(i))) confirmed.increment();   // every holder tries to pay
                attempts.incrementAndGet();
            }
        });
        released.add(res.sweep(0));
        long conf = res.units(Confirmed.class), rel = res.units(Released.class), still = res.units(Held.class);
        System.out.printf("  pay-or-expire: confirmed %d holds (%d units) | released %d units | still held %d | available %d%n", confirmed.sum(), conf,
                rel, still, inv.available());
        boolean conserved = conf + still + inv.available() == 1_000 && rel == released.sum();
        System.out.printf("  invariant available + held + confirmed == 1000: %b | every hold ended exactly once (confirmed or released): %b%n", conserved,
                res.byUser.values().stream().noneMatch(h -> h instanceof Held));

        System.out.println("== 4. Promotions: specifications + exclusive groups + phases ==");
        Cart cart = new Cart(List.of(new Line("headphones", "electronics", 9_999, 2), new Line("charger", "electronics", 2_999, 1),
                new Line("socks", "apparel", 500, 3)), Set.of("SAVE10", "WELCOME15"), true);
        List<Promo> promos = List.of(
                new Promo("ELEC10", "sale", Phase.ITEM, Spec.hasLine("electronics"), new PercentOff("electronics", 10)),
                new Promo("HEAD15", "sale", Phase.ITEM, Spec.hasLine("headphones"), new PercentOff("headphones", 15)),
                new Promo("SOCKS3FOR2", null, Phase.ITEM, Spec.hasLine("socks"), new BuyNGetOneFree("socks", 2)),
                new Promo("BIG20", null, Phase.CART_FIXED, Spec.minSubtotal(20_000), new FixedOffCart(2_000)),
                new Promo("SAVE10", "coupon", Phase.CART_PERCENT, Spec.coupon("SAVE10"), new PercentOffCart(10, 0)),
                new Promo("WELCOME15", "coupon", Phase.CART_PERCENT, Spec.coupon("WELCOME15").and(Spec.firstOrder()), new PercentOffCart(15, 2_500)));
        Priced all = price(cart, promos);
        Map<String, Promo> firstPerGroup = new LinkedHashMap<>();
        for (Promo p : promos)
            if (p.when().test(cart)) firstPerGroup.putIfAbsent(p.group() == null ? p.id() : p.group(), p);
        List<Promo> firsts = new ArrayList<>(firstPerGroup.values());
        firsts.sort(Comparator.comparing(Promo::phase).thenComparing(Promo::id));
        Priced first = price(cart, firsts), best = bestCombination(cart, promos);
        System.out.printf("  cart subtotal %s: headphones 2 x 99.99, charger 29.99, socks 3 x 5.00; coupons SAVE10 + WELCOME15; first order%n",
                cents(cart.subtotal()));
        System.out.printf("  %-46s -> %s %s%n", "every eligible promo, list order (no groups):", cents(all.total()), all.applied());
        System.out.printf("  %-46s -> %s %s%n", "first eligible per group, phase order:", cents(first.total()), first.applied());
        System.out.printf("  %-46s -> %s %s%n", "best combination, phase order:", cents(best.total()), best.applied());
        Cart plain = new Cart(List.of(new Line("tv", "electronics", 30_000, 1)), Set.of("SAVE10"), false);
        Promo pct = promos.get(4), fixed = promos.get(3);
        System.out.printf("  phase order matters on 300.00: 10%% then 20.00 off = %s | 20.00 off then 10%% = %s%n",
                cents(price(plain, List.of(pct, fixed)).total()), cents(price(plain, List.of(fixed, pct)).total()));
        StringJoiner nets = new StringJoiner(", ");
        long netSum = 0;
        for (int i = 0; i < best.lineNet().length; i++) {
            nets.add(cart.lines().get(i).sku() + " " + cents(best.lineNet()[i]));
            netSum += best.lineNet()[i];
        }
        long oneHeadphone = best.lineNet()[0] / 2;                     // units share the line net; a return refunds the smaller share
        System.out.printf("  line nets after attribution: %s (sum %s == total: %b) | return 1 headphone -> refund %s%n", nets, cents(netSum),
                netSum == best.total(), cents(oneHeadphone));

        boolean ok = sales[2].sold() == units && sales[2].left() == 0 && sales[3].sold() == units && sales[3].left() == 0 && sales[4].sold() == units
                && sales[4].left() == 0 && homeOnly.available() > 0 && fullSale.sold() == 10_000 && fullSale.left() == 0
                && heldUnits == 1_000 && conserved && dupes.sum() == held.sum() && confirmed.sum() > 0 && rel > 0
                && !best.applied().containsAll(List.of("SAVE10", "WELCOME15")) && best.total() <= first.total() && netSum == best.total()
                && all.applied().containsAll(List.of("SAVE10", "WELCOME15"));
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (section 4 deterministic; 1–3 one measured run):**

```text
== 1. One hot SKU, 2,000,000 units, 8 buyers taking 1-3 units until refused ==
  CHM get() then put()               sold 6922844 (oversold 4922844) | left 0 | 332 ms
  LongAdder sum() then add()         sold 2000007 (oversold 7) | left -7 | 68 ms
  synchronized counter               sold 2000000 (oversold 0) | left 0 | 86 ms
  one AtomicLong, CAS loop           sold 2000000 (oversold 0) | left 0 | 136 ms | CAS retries 1851821
  16 padded CAS buckets + stealing   sold 2000000 (oversold 0) | left 0 | 40 ms | CAS retries 154426, slow paths 16
== 2. The last units: striping without stealing tells buyers 'sold out' while stock remains ==
  home bucket only: all 8 buyers told sold out with 5000 of 10000 units still in buckets 8..15
  steal + collapse: sold 10000, left 0, slow paths 16
== 3. Holds with a 10-minute TTL: 1,000 units, 3,000 customers, pay-or-expire races ==
  reserve: 661 holds (1000 units), 4678 sold out, 661 duplicate clicks refused | available 0
  pay-or-expire: confirmed 222 holds (332 units) | released 668 units | still held 0 | available 668
  invariant available + held + confirmed == 1000: true | every hold ended exactly once (confirmed or released): true
== 4. Promotions: specifications + exclusive groups + phases ==
  cart subtotal 244.97: headphones 2 x 99.99, charger 29.99, socks 3 x 5.00; coupons SAVE10 + WELCOME15; first order
  every eligible promo, list order (no groups):  -> 130.02 [ELEC10, HEAD15, SOCKS3FOR2, BIG20, SAVE10, WELCOME15]
  first eligible per group, phase order:         -> 175.27 [ELEC10, SOCKS3FOR2, SAVE10, BIG20]
  best combination, phase order:                 -> 164.97 [HEAD15, SOCKS3FOR2, WELCOME15, BIG20]
  phase order matters on 300.00: 10% then 20.00 off = 250.00 | 20.00 off then 10% = 252.00
  line nets after attribution: headphones 133.55, charger 23.56, socks 7.86 (sum 164.97 == total: true) | return 1 headphone -> refund 66.77
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// flash_sale.cpp - P15: striped inventory counters without a hot row, TTL holds, specification promotions (stackable vs exclusive)
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <format>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

// ---- inventory: one hot SKU

struct Inventory {
    virtual ~Inventory() = default;
    virtual bool take(i64 qty, int home) = 0;  // all-or-nothing; home = the caller's preferred stripe
    virtual void give_back(i64 qty, int home) = 0;
    virtual i64 available() const = 0;
};

/** The get()-then-put() bug, made well-defined with relaxed atomics so the lost update can be counted. */
struct LoadThenStore final : Inventory {
    std::atomic<i64> stock;
    explicit LoadThenStore(i64 units) : stock(units) {}
    bool take(i64 qty, int) override {
        const i64 cur = stock.load(std::memory_order_relaxed);
        if (cur < qty) return false;
        stock.store(cur - qty, std::memory_order_relaxed);
        return true;
    }
    void give_back(i64 qty, int) override { stock.fetch_add(qty); }
    i64 available() const override { return stock.load(); }
};

struct alignas(64) Cell { std::atomic<i64> v{0}; };  // one counter per cache line

/** C++ has no LongAdder; this is one (striped cells, sum on read). Fast, and still unable to do a conditional decrement. */
struct AdderCheckThenAdd final : Inventory {
    std::array<Cell, 16> cells;
    explicit AdderCheckThenAdd(i64 units) { cells[0].v.store(units); }
    i64 sum() const {
        i64 s = 0;
        for (const auto& c : cells) s += c.v.load(std::memory_order_relaxed);
        return s;
    }
    bool take(i64 qty, int home) override {
        if (sum() < qty) return false;
        cells[static_cast<sz>(home) % cells.size()].v.fetch_sub(qty, std::memory_order_relaxed);
        return true;
    }
    void give_back(i64 qty, int home) override { cells[static_cast<sz>(home) % cells.size()].v.fetch_add(qty); }
    i64 available() const override { return sum(); }
};

struct Locked final : Inventory {
    mutable std::mutex m;
    i64 stock;  // guarded by m
    explicit Locked(i64 units) : stock(units) { std::scoped_lock warm(m); }
    bool take(i64 qty, int) override {
        std::scoped_lock l(m);
        if (stock < qty) return false;
        stock -= qty;
        return true;
    }
    void give_back(i64 qty, int) override {
        std::scoped_lock l(m);
        stock += qty;
    }
    i64 available() const override {
        std::scoped_lock l(m);
        return stock;
    }
};

/** Correct and lock-free, but every buyer CASes the same cache line: the hot row moved into the CPU. */
struct SingleCas final : Inventory {
    std::atomic<i64> stock;
    std::atomic<i64> retries{0};
    explicit SingleCas(i64 units) : stock(units) {}
    bool take(i64 qty, int) override {
        for (i64 cur = stock.load(); cur >= qty;) {
            if (stock.compare_exchange_weak(cur, cur - qty)) return true;  // on failure cur is reloaded
            retries.fetch_add(1, std::memory_order_relaxed);
        }
        return false;
    }
    void give_back(i64 qty, int) override { stock.fetch_add(qty); }
    i64 available() const override { return stock.load(); }
};

/**
 * K padded sub-buckets ("inventory tokens"). A buyer CASes its home bucket and steals from the others when it is
 * empty. When every bucket is below qty but the total is not (fragmentation), a slow path drains all buckets into
 * bucket 0 under a lock and retries there. Units are only ever moved by exchange/fetch_add, never duplicated.
 */
class Striped final : public Inventory {
    std::vector<Cell> buckets_;
    bool steal_;
    std::mutex slow_;

    bool take_from(sz b, i64 qty) {
        for (i64 cur = buckets_[b].v.load(); cur >= qty;) {
            if (buckets_[b].v.compare_exchange_weak(cur, cur - qty)) return true;
            retries.fetch_add(1, std::memory_order_relaxed);
        }
        return false;
    }

public:
    std::atomic<i64> retries{0}, slow_paths{0};
    Striped(i64 units, sz k, bool steal) : buckets_(k), steal_(steal) {
        for (sz b = 0; b < k; ++b) buckets_[b].v.store(units / static_cast<i64>(k) + (static_cast<i64>(b) < units % static_cast<i64>(k) ? 1 : 0));
        std::scoped_lock warm(slow_);
    }
    bool take(i64 qty, int home) override {
        const sz k = buckets_.size(), first = static_cast<sz>(home) % k;
        for (sz i = 0; i < (steal_ ? k : 1); ++i)
            if (take_from((first + i) % k, qty)) return true;
        if (!steal_) return false;  // the naive variant: "my bucket is empty = sold out"
        std::scoped_lock l(slow_);  // fragmentation: collapse into one bucket, rare
        slow_paths.fetch_add(1);
        i64 moved = 0;
        for (sz b = 1; b < k; ++b) moved += buckets_[b].v.exchange(0);
        buckets_[0].v.fetch_add(moved);
        return take_from(0, qty);
    }
    void give_back(i64 qty, int home) override { buckets_[static_cast<sz>(home) % buckets_.size()].v.fetch_add(qty); }
    i64 available() const override {
        i64 s = 0;
        for (const auto& c : buckets_) s += c.v.load();
        return s;
    }
};

// ---- holds with a TTL: claim the customer slot, then the stock; confirm and expiry race on one compare-and-replace

struct Held { std::string user; i64 qty; i64 expires_ms; bool operator==(const Held&) const = default; };
struct Confirmed { std::string user; i64 qty; bool operator==(const Confirmed&) const = default; };
struct Released { std::string user; i64 qty; bool operator==(const Released&) const = default; };
using Hold = std::variant<Held, Confirmed, Released>;

/** A mutex-striped map: C++'s stand-in for ConcurrentHashMap (as in P13). */
template <class V> class StripedMap {
    struct Shard {
        std::mutex m;
        std::unordered_map<std::string, V> map;
    };
    std::array<Shard, 64> shards_;
    Shard& shard(const std::string& k) { return shards_[std::hash<std::string>{}(k) % shards_.size()]; }

public:
    StripedMap() {
        for (auto& s : shards_) std::scoped_lock warm(s.m);
    }
    std::optional<V> get(const std::string& k) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        const auto it = s.map.find(k);
        return it == s.map.end() ? std::nullopt : std::optional<V>(it->second);
    }
    bool put_if_absent(const std::string& k, const V& v) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        return s.map.try_emplace(k, v).second;
    }
    bool replace(const std::string& k, const V& expected, const V& next) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        const auto it = s.map.find(k);
        if (it == s.map.end() || !(it->second == expected)) return false;
        it->second = next;
        return true;
    }
    bool remove(const std::string& k, const V& expected) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        const auto it = s.map.find(k);
        if (it == s.map.end() || !(it->second == expected)) return false;
        s.map.erase(it);
        return true;
    }
    std::vector<std::pair<std::string, V>> entries() {
        std::vector<std::pair<std::string, V>> out;
        for (auto& s : shards_) {
            std::scoped_lock l(s.m);
            for (const auto& kv : s.map) out.push_back(kv);
        }
        return out;
    }
};

struct TestClock {
    std::atomic<i64> now_ms{0};
    i64 now() const { return now_ms.load(); }
    void advance(i64 ms) { now_ms.fetch_add(ms); }
};

class Reservations {
    Inventory& inv_;
    const TestClock& clock_;
    i64 ttl_ms_;

public:
    StripedMap<Hold> by_user;
    Reservations(Inventory& inv, const TestClock& c, i64 ttl_ms) : inv_(inv), clock_(c), ttl_ms_(ttl_ms) {}

    std::string reserve(const std::string& user, i64 qty, int home) {
        const Hold h = Held{user, qty, clock_.now() + ttl_ms_};
        if (!by_user.put_if_absent(user, h)) return "rejected: " + user + " already has a hold";  // 1. one hold per customer
        if (inv_.take(qty, home)) return "held";                                                  // 2. the stock
        by_user.remove(user, h);                                                                  // undo step 1
        return "sold out";
    }

    bool confirm(const std::string& user) {  // payment captured
        const auto cur = by_user.get(user);
        if (!cur || !std::holds_alternative<Held>(*cur)) return false;
        const auto& h = std::get<Held>(*cur);
        return clock_.now() < h.expires_ms && by_user.replace(user, *cur, Confirmed{user, h.qty});
    }

    i64 sweep(int home) {  // expiry: the same compare-and-replace decides against confirm()
        i64 released = 0;
        for (const auto& [user, x] : by_user.entries())
            if (const auto* h = std::get_if<Held>(&x); h && clock_.now() >= h->expires_ms && by_user.replace(user, x, Released{user, h->qty})) {
                inv_.give_back(h->qty, home);
                released += h->qty;
            }
        return released;
    }

    template <class Kind> i64 units() {
        i64 n = 0;
        for (const auto& [user, x] : by_user.entries())
            if (const auto* k = std::get_if<Kind>(&x)) n += k->qty;
        return n;
    }
};

// ---- promotions: specifications decide eligibility; groups decide exclusivity; phases decide order

struct Line { std::string sku, category; i64 unit_cents; i64 qty; };
struct Cart {
    std::vector<Line> lines;
    std::set<std::string> coupons;
    bool first_order;
    i64 subtotal() const {
        i64 s = 0;
        for (const auto& l : lines) s += l.unit_cents * l.qty;
        return s;
    }
};

using Spec = std::function<bool(const Cart&)>;
Spec operator&&(Spec a, Spec b) {
    return [a = std::move(a), b = std::move(b)](const Cart& c) { return a(c) && b(c); };
}
Spec has_line(std::string match) {
    return [m = std::move(match)](const Cart& c) { return std::ranges::any_of(c.lines, [&](const Line& l) { return l.sku == m || l.category == m; }); };
}
Spec coupon(std::string code) {
    return [k = std::move(code)](const Cart& c) { return c.coupons.contains(k); };
}
Spec first_order() {
    return [](const Cart& c) { return c.first_order; };
}
Spec min_subtotal(i64 cents) {
    return [cents](const Cart& c) { return c.subtotal() >= cents; };
}

enum class Phase { Item, CartPercent, CartFixed };

struct PercentOff { std::string match; i64 pct; };  // lines whose sku or category matches
struct BuyNGetOneFree { std::string sku; i64 n; };
struct PercentOffCart { i64 pct, cap_cents; };
struct FixedOffCart { i64 cents; };
using Discount = std::variant<PercentOff, BuyNGetOneFree, PercentOffCart, FixedOffCart>;

/** group empty: stackable. Otherwise at most one promotion per group is applied. */
struct Promo { std::string id, group; Phase phase; Spec when; Discount how; };

struct Priced { std::vector<i64> line_net; i64 total; std::vector<std::string> applied; };

i64 half_even(i64 num, i64 den) {  // RoundingMode.HALF_EVEN of num / den, num >= 0
    const i64 q = num / den, r = num % den;
    return 2 * r > den || (2 * r == den && q % 2 == 1) ? q + 1 : q;
}

/** Takes `amount` off the lines in proportion to their current net, by largest remainder (ties: lower line index). */
void attribute(std::vector<i64>& net, i64 amount) {
    i64 total = 0;
    for (const i64 x : net) total += x;
    if (amount == 0 || total == 0) return;
    std::vector<i64> floor(net.size()), rem(net.size());
    i64 given = 0;
    for (sz i = 0; i < net.size(); ++i) {
        floor[i] = amount * net[i] / total;
        rem[i] = amount * net[i] % total;
        given += floor[i];
    }
    std::vector<sz> order(net.size());
    for (sz i = 0; i < order.size(); ++i) order[i] = i;
    std::ranges::sort(order, [&](sz a, sz b) { return rem[a] != rem[b] ? rem[a] > rem[b] : a < b; });
    for (i64 k = 0; k < amount - given; ++k) ++floor[order[static_cast<sz>(k)]];
    for (sz i = 0; i < net.size(); ++i) net[i] -= floor[i];
}

/** Applies promotions in the given order (the engine passes them sorted by phase); cart-level discounts are attributed to lines. */
Priced price(const Cart& c, const std::vector<const Promo*>& promos) {
    std::vector<i64> net;
    for (const auto& l : c.lines) net.push_back(l.unit_cents * l.qty);
    std::vector<std::string> applied;
    for (const Promo* p : promos) {
        if (!p->when(c)) continue;
        i64 cart = 0;
        for (const i64 x : net) cart += x;
        std::visit(overloaded{
                       [&](const PercentOff& po) {
                           for (sz i = 0; i < net.size(); ++i)
                               if (c.lines[i].sku == po.match || c.lines[i].category == po.match) net[i] -= half_even(net[i] * po.pct, 100);
                       },
                       [&](const BuyNGetOneFree& b) {
                           for (sz i = 0; i < net.size(); ++i)
                               if (c.lines[i].sku == b.sku) net[i] -= std::min(net[i], c.lines[i].qty / (b.n + 1) * c.lines[i].unit_cents);
                       },
                       [&](const PercentOffCart& pc) { attribute(net, std::min(half_even(cart * pc.pct, 100), pc.cap_cents > 0 ? pc.cap_cents : INT64_MAX)); },
                       [&](const FixedOffCart& f) { attribute(net, std::min(f.cents, cart)); },
                   },
                   p->how);
        applied.push_back(p->id);
    }
    i64 total = 0;
    for (const i64 x : net) total += x;
    return {net, total, applied};
}

bool by_phase_then_id(const Promo* a, const Promo* b) { return a->phase != b->phase ? a->phase < b->phase : a->id < b->id; }

/** Stackables always apply; for each exclusive group try none or one eligible member; keep the cheapest total. */
Priced best_combination(const Cart& c, const std::vector<Promo>& promos) {
    std::vector<std::pair<std::string, std::vector<const Promo*>>> groups;  // insertion order, like Java's LinkedHashMap
    std::vector<const Promo*> stackable;
    for (const auto& p : promos) {
        if (!p.when(c)) continue;
        if (p.group.empty()) {
            stackable.push_back(&p);
            continue;
        }
        auto it = std::ranges::find(groups, p.group, &std::pair<std::string, std::vector<const Promo*>>::first);
        if (it == groups.end()) it = groups.insert(groups.end(), {p.group, {}});
        it->second.push_back(&p);
    }
    std::optional<Priced> best;
    std::vector<sz> pick(groups.size());  // 0 = none, j = groups[g][j - 1]
    for (;;) {
        std::vector<const Promo*> chosen = stackable;
        for (sz g = 0; g < groups.size(); ++g)
            if (pick[g] > 0) chosen.push_back(groups[g].second[pick[g] - 1]);
        std::ranges::sort(chosen, by_phase_then_id);  // one fixed, documented order
        Priced p = price(c, chosen);
        if (!best || p.total < best->total || (p.total == best->total && p.applied.size() < best->applied.size())) best = p;
        sz g = 0;
        while (g < groups.size() && ++pick[g] > groups[g].second.size()) pick[g++] = 0;
        if (g == groups.size()) return *best;
    }
}

std::string cents(i64 c) { return std::format("{}.{:02}", c / 100, c % 100); }
std::string list(const std::vector<std::string>& v) {
    std::string s = "[";
    for (const auto& x : v) s += (s.size() > 1 ? ", " : "") + x;
    return s + "]";
}

// ---- harness

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

struct Rng {
    u64 s;
    int below(int n) { return static_cast<int>(mix64(s++) % static_cast<u64>(n)); }
};

template <class F>
i64 parallel(int threads, F body) {  // spin gate with a ready count (see P6); returns wall ms
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::chrono::steady_clock::time_point t0;
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < threads; ++t)
            ts.emplace_back([&, t] {
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}
                body(t);
            });
        while (ready.load() < threads) {}
        t0 = std::chrono::steady_clock::now();
        go.store(true, std::memory_order_release);
    }
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
}

struct Sale { i64 sold, left, ms; };

/** 8 buyers each take 1-3 units until even 1 unit is refused. A correct inventory ends with exactly 0 left. */
Sale sell(Inventory& inv) {
    std::atomic<i64> sold{0};
    const i64 ms = parallel(8, [&](int t) {
        Rng r{60 + static_cast<u64>(t)};
        for (;;) {
            const i64 q = 1 + r.below(3);
            const int home = r.below(1 << 16);  // home = hash(customer): spreads buyers over all K buckets
            if (inv.take(q, home)) sold.fetch_add(q);
            else if (inv.take(1, home)) sold.fetch_add(1);
            else return;
        }
    });
    return {sold.load(), inv.available(), ms};
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    constexpr i64 units = 2'000'000;
    std::println("== 1. One hot SKU, 2,000,000 units, 8 buyers taking 1-3 units until refused ==");
    std::vector<std::unique_ptr<Inventory>> invs;
    invs.push_back(std::make_unique<LoadThenStore>(units));
    invs.push_back(std::make_unique<AdderCheckThenAdd>(units));
    invs.push_back(std::make_unique<Locked>(units));
    invs.push_back(std::make_unique<SingleCas>(units));
    invs.push_back(std::make_unique<Striped>(units, 16, true));
    const std::array<const char*, 5> names{"relaxed load() then store()", "striped adder: sum() then add()", "std::mutex counter", "one atomic, CAS loop",
                                           "16 padded CAS buckets + stealing"};
    std::vector<Sale> sales;
    for (sz i = 0; i < invs.size(); ++i) {
        sales.push_back(sell(*invs[i]));
        std::string extra;
        if (const auto* s = dynamic_cast<const SingleCas*>(invs[i].get())) extra = std::format(" | CAS retries {}", s->retries.load());
        if (const auto* s = dynamic_cast<const Striped*>(invs[i].get()))
            extra = std::format(" | CAS retries {}, slow paths {}", s->retries.load(), s->slow_paths.load());
        std::println("  {:<34} sold {} (oversold {}) | left {} | {} ms{}", names[i], sales[i].sold, std::max<i64>(0, sales[i].sold - units), sales[i].left,
                     sales[i].ms, extra);
    }

    std::println("== 2. The last units: striping without stealing tells buyers 'sold out' while stock remains ==");
    Striped home_only(10'000, 16, false), full(10'000, 16, true);
    parallel(8, [&](int t) {  // 8 buyers only ever touch buckets 0..7
        while (home_only.take(1, t)) {}
    });
    const Sale full_sale = sell(full);
    std::println("  home bucket only: all 8 buyers told sold out with {} of 10000 units still in buckets 8..15", home_only.available());
    std::println("  steal + collapse: sold {}, left {}, slow paths {}", full_sale.sold, full_sale.left, full.slow_paths.load());

    std::println("== 3. Holds with a 10-minute TTL: 1,000 units, 3,000 customers, pay-or-expire races ==");
    TestClock clock;
    Striped inv(1'000, 16, true);
    Reservations res(inv, clock, 600'000);
    std::atomic<i64> held{0}, sold_out{0}, dupes{0};
    parallel(8, [&](int t) {
        Rng r{80 + static_cast<u64>(t)};
        for (int u = 0; u < 375; ++u) {
            const std::string user = std::format("u{}", t * 375 + u);
            for (int attempt = 0; attempt < 2; ++attempt) {  // the second click is a duplicate
                const std::string out = res.reserve(user, 1 + r.below(2), t);
                (out == "held" ? held : out == "sold out" ? sold_out : dupes).fetch_add(1);
            }
        }
    });
    const i64 held_units = res.units<Held>();
    std::println("  reserve: {} holds ({} units), {} sold out, {} duplicate clicks refused | available {}", held.load(), held_units, sold_out.load(),
                 dupes.load(), inv.available());
    std::vector<std::string> holders;
    for (const auto& [u, h] : res.by_user.entries())
        if (std::holds_alternative<Held>(h)) holders.push_back(u);
    std::ranges::sort(holders);
    clock.advance(600'000 - 1);  // payments arrive right at the deadline...
    std::atomic<i64> confirmed{0}, released{0}, attempts{0};
    const auto n_holders = static_cast<i64>(holders.size());
    parallel(9, [&](int t) {
        if (t == 8) {  // ...and the clock ticks over a quarter of the way in
            while (attempts.load() < n_holders / 4) {}
            clock.advance(1);
            while (attempts.load() < n_holders) released.fetch_add(res.sweep(t));
            return;
        }
        for (sz i = static_cast<sz>(t); i < holders.size(); i += 8) {
            if (res.confirm(holders[i])) confirmed.fetch_add(1);  // every holder tries to pay
            attempts.fetch_add(1);
        }
    });
    released.fetch_add(res.sweep(0));
    const i64 conf = res.units<Confirmed>(), rel = res.units<Released>(), still = res.units<Held>();
    std::println("  pay-or-expire: confirmed {} holds ({} units) | released {} units | still held {} | available {}", confirmed.load(), conf, rel, still,
                 inv.available());
    const bool conserved = conf + still + inv.available() == 1'000 && rel == released.load();
    std::println("  invariant available + held + confirmed == 1000: {} | every hold ended exactly once (confirmed or released): {}", conserved, still == 0);

    std::println("== 4. Promotions: specifications + exclusive groups + phases ==");
    const Cart cart{{{"headphones", "electronics", 9'999, 2}, {"charger", "electronics", 2'999, 1}, {"socks", "apparel", 500, 3}},
                    {"SAVE10", "WELCOME15"},
                    true};
    const std::vector<Promo> promos{
        {"ELEC10", "sale", Phase::Item, has_line("electronics"), PercentOff{"electronics", 10}},
        {"HEAD15", "sale", Phase::Item, has_line("headphones"), PercentOff{"headphones", 15}},
        {"SOCKS3FOR2", "", Phase::Item, has_line("socks"), BuyNGetOneFree{"socks", 2}},
        {"BIG20", "", Phase::CartFixed, min_subtotal(20'000), FixedOffCart{2'000}},
        {"SAVE10", "coupon", Phase::CartPercent, coupon("SAVE10"), PercentOffCart{10, 0}},
        {"WELCOME15", "coupon", Phase::CartPercent, coupon("WELCOME15") && first_order(), PercentOffCart{15, 2'500}},
    };
    std::vector<const Promo*> in_list_order;
    for (const auto& p : promos) in_list_order.push_back(&p);
    const Priced all = price(cart, in_list_order);
    std::vector<const Promo*> firsts;
    std::set<std::string> seen_groups;
    for (const auto& p : promos)
        if (p.when(cart) && seen_groups.insert(p.group.empty() ? p.id : p.group).second) firsts.push_back(&p);
    std::ranges::sort(firsts, by_phase_then_id);
    const Priced first = price(cart, firsts), best = best_combination(cart, promos);
    std::println("  cart subtotal {}: headphones 2 x 99.99, charger 29.99, socks 3 x 5.00; coupons SAVE10 + WELCOME15; first order", cents(cart.subtotal()));
    std::println("  {:<46} -> {} {}", "every eligible promo, list order (no groups):", cents(all.total), list(all.applied));
    std::println("  {:<46} -> {} {}", "first eligible per group, phase order:", cents(first.total), list(first.applied));
    std::println("  {:<46} -> {} {}", "best combination, phase order:", cents(best.total), list(best.applied));
    const Cart plain{{{"tv", "electronics", 30'000, 1}}, {"SAVE10"}, false};
    const Promo* pct = &promos[4];
    const Promo* fixed = &promos[3];
    std::println("  phase order matters on 300.00: 10% then 20.00 off = {} | 20.00 off then 10% = {}", cents(price(plain, {pct, fixed}).total),
                 cents(price(plain, {fixed, pct}).total));
    std::string nets;
    i64 net_sum = 0;
    for (sz i = 0; i < best.line_net.size(); ++i) {
        nets += std::format("{}{} {}", i ? ", " : "", cart.lines[i].sku, cents(best.line_net[i]));
        net_sum += best.line_net[i];
    }
    const i64 one_headphone = best.line_net[0] / 2;  // units share the line net; a return refunds the smaller share
    std::println("  line nets after attribution: {} (sum {} == total: {}) | return 1 headphone -> refund {}", nets, cents(net_sum), net_sum == best.total,
                 cents(one_headphone));

    const auto has = [](const std::vector<std::string>& v, const char* x) { return std::ranges::find(v, x) != v.end(); };
    const bool ok = sales[2].sold == units && sales[2].left == 0 && sales[3].sold == units && sales[3].left == 0 && sales[4].sold == units &&
                    sales[4].left == 0 && home_only.available() > 0 && full_sale.sold == 10'000 && full_sale.left == 0 && held_units == 1'000 && conserved &&
                    dupes.load() == held.load() && confirmed.load() > 0 && rel > 0 && !(has(best.applied, "SAVE10") && has(best.applied, "WELCOME15")) &&
                    best.total <= first.total && net_sum == best.total && has(all.applied, "SAVE10") && has(all.applied, "WELCOME15");
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. One hot SKU, 2,000,000 units, 8 buyers taking 1-3 units until refused ==
  relaxed load() then store()        sold 7612808 (oversold 5612808) | left 0 | 145 ms
  striped adder: sum() then add()    sold 2000004 (oversold 4) | left -4 | 41 ms
  std::mutex counter                 sold 2000000 (oversold 0) | left 0 | 119 ms
  one atomic, CAS loop               sold 2000000 (oversold 0) | left 0 | 99 ms | CAS retries 1807279
  16 padded CAS buckets + stealing   sold 2000000 (oversold 0) | left 0 | 29 ms | CAS retries 111033, slow paths 16
== 2. The last units: striping without stealing tells buyers 'sold out' while stock remains ==
  home bucket only: all 8 buyers told sold out with 5000 of 10000 units still in buckets 8..15
  steal + collapse: sold 10000, left 0, slow paths 16
== 3. Holds with a 10-minute TTL: 1,000 units, 3,000 customers, pay-or-expire races ==
  reserve: 661 holds (1000 units), 4678 sold out, 661 duplicate clicks refused | available 0
  pay-or-expire: confirmed 172 holds (258 units) | released 742 units | still held 0 | available 742
  invariant available + held + confirmed == 1000: true | every hold ended exactly once (confirmed or released): true
== 4. Promotions: specifications + exclusive groups + phases ==
  cart subtotal 244.97: headphones 2 x 99.99, charger 29.99, socks 3 x 5.00; coupons SAVE10 + WELCOME15; first order
  every eligible promo, list order (no groups):  -> 130.02 [ELEC10, HEAD15, SOCKS3FOR2, BIG20, SAVE10, WELCOME15]
  first eligible per group, phase order:         -> 175.27 [ELEC10, SOCKS3FOR2, SAVE10, BIG20]
  best combination, phase order:                 -> 164.97 [HEAD15, SOCKS3FOR2, WELCOME15, BIG20]
  phase order matters on 300.00: 10% then 20.00 off = 250.00 | 20.00 off then 10% = 252.00
  line nets after attribution: headphones 133.55, charger 23.56, socks 7.86 (sum 164.97 == total: true) | return 1 headphone -> refund 66.77
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. One hot SKU, 2,000,000 units, 8 buyers taking 1-3 units until refused ==
  relaxed load() then store()        sold 5066482 (oversold 3066482) | left 0 | 112 ms
  striped adder: sum() then add()    sold 2000003 (oversold 3) | left -3 | 53 ms
  std::mutex counter                 sold 2000000 (oversold 0) | left 0 | 88 ms
  one atomic, CAS loop               sold 2000000 (oversold 0) | left 0 | 97 ms | CAS retries 1978092
  16 padded CAS buckets + stealing   sold 2000000 (oversold 0) | left 0 | 38 ms | CAS retries 55852, slow paths 16
== 2. The last units: striping without stealing tells buyers 'sold out' while stock remains ==
  home bucket only: all 8 buyers told sold out with 5000 of 10000 units still in buckets 8..15
  steal + collapse: sold 10000, left 0, slow paths 16
== 3. Holds with a 10-minute TTL: 1,000 units, 3,000 customers, pay-or-expire races ==
  reserve: 658 holds (1000 units), 4684 sold out, 658 duplicate clicks refused | available 0
  pay-or-expire: confirmed 171 holds (258 units) | released 742 units | still held 0 | available 742
  invariant available + held + confirmed == 1000: true | every hold ended exactly once (confirmed or released): true
== 4. Promotions: specifications + exclusive groups + phases ==
  cart subtotal 244.97: headphones 2 x 99.99, charger 29.99, socks 3 x 5.00; coupons SAVE10 + WELCOME15; first order
  every eligible promo, list order (no groups):  -> 130.02 [ELEC10, HEAD15, SOCKS3FOR2, BIG20, SAVE10, WELCOME15]
  first eligible per group, phase order:         -> 175.27 [ELEC10, SOCKS3FOR2, SAVE10, BIG20]
  best combination, phase order:                 -> 164.97 [HEAD15, SOCKS3FOR2, WELCOME15, BIG20]
  phase order matters on 300.00: 10% then 20.00 off = 250.00 | 20.00 off then 10% = 252.00
  line nets after attribution: headphones 133.55, charger 23.56, socks 7.86 (sum 164.97 == total: true) | return 1 headphone -> refund 66.77
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Inventory | `stock--` in a `synchronized` method / `UPDATE … SET stock = stock - 1` | One `AtomicLong` CAS | K CAS-guarded padded buckets, hashed by customer, with stealing and a collapse slow path; measured herding; `LongAdder` rejected for conditional decrement |
| Holds | Decrement on add-to-cart, never released | Holds with a cron cleanup | Claim the customer slot first, then the stock (with undo); confirm vs expiry decided by one CAS on the same value; injected clock |
| Promotions | `if` chains | Strategy per promotion, applied in list order | Specifications + exclusive groups (best combination) + explicit phases + line attribution for returns |
| Evidence | "Works on my machine" | Load test with average latency | Oversell counters, stranded-stock counts, conservation invariants, deterministic pricing identical across languages |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Put it in a database" | The single `UPDATE … WHERE stock >= q` row is the hot row. Use K inventory rows (bucket = hash(customer) % K) with the same steal/collapse logic, or pre-mint K × N inventory tokens and claim one with `SELECT … FOR UPDATE SKIP LOCKED` |
| "Fairness: first come, first served" | Striping is not FIFO. Put an admission queue (a waiting room with a sequence number) in front and serve tickets in order; inventory stays striped behind it |
| "Limit 2 per customer across devices" | The per-customer slot holds a quantity; CAS `Held(q)` → `Held(q + k)` only if `q + k ≤ 2` |
| "Coupon valid for the first 1,000 redemptions" | A striped bounded counter (same class); per-user single use via `putIfAbsent` |
| "Show live stock on the product page" | `available()` is a sum of buckets: approximate while racing, exact at quiescence. Display "low stock" bands, never promise a number |
| "Promotion explosion: 30 exclusive groups" | Brute force over groups is exponential. Prune with per-group upper bounds (branch and bound), or price greedily by group impact and document the heuristic |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "A million people buy one SKU at 09:00. Where does it break?"</b></summary>

**L5:** "Use an `AtomicInteger`, it's lock-free."

**Why it fails:** every buyer CASes one cache line. 1.8–2.0 M failed CASes to sell 2 M units, slower than the mutex in two of three builds.

**L7 defence:** "Split the stock into K padded CAS buckets, with the customer hashed to a bucket, stealing when it's empty, and a collapse-to-one slow path for the last units. Measured 29–40 ms vs ~100 ms. And no `LongAdder`: it can't do a conditional decrement, and oversold in 5 of 6 runs across the three builds (the published runs plus the gate rerun). The sixth run got lucky, which is the point: a passing run proves nothing."
</details>

<details>
<summary><b>Q2 ⚡ "Your striped inventory says sold out. Is it?"</b></summary>

**L5:** "Yes, the bucket is empty."

**Why it fails:** other buckets still hold stock. Measured: 5,000 of 10,000 units stranded. Or the stock is fragmented across buckets.

**L7 defence:** "Steal across buckets, and when the total could satisfy the request but no bucket can, drain into one bucket under a lock and retry. Units are moved with exchange/add, never duplicated. A correct sale ends at exactly zero."
</details>

<details>
<summary><b>Q3 ⚡ "Two coupons, a sale and a fixed discount. What's the price?"</b></summary>

**L5:** "Apply them all."

**Why it fails:** exclusive coupons stack, and the shop sells at 130.02 instead of 164.97. List order also changes the result by 2.00 on a 300.00 cart.

**L7 defence:** "Specifications for eligibility; groups for exclusivity, choosing the best combination; explicit phases for order; and attribute cart-level discounts to lines by largest remainder, so a return of one headphone refunds exactly its share."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Sold more than stock | `get` then `put`; `LongAdder` check-then-add | CAS-guarded decrement (per bucket) |
| Throughput flat at one core | Single counter / row | K buckets hashed by customer |
| Striping no faster than one counter | Homes clustered; stealing herds | Hash the customer; spread homes over all buckets |
| "Sold out" with stock left | No stealing / fragmentation | Steal + collapse slow path |
| Paid but released, or released twice | Confirm and expiry on separate checks | One CAS on the same hold value |
| Over-discounting | No exclusivity; list order | Groups + best combination + fixed phases |
| Wrong refund on return | Cart discount not attributed | Largest-remainder attribution to lines |

- [ ] Bounded decrement by CAS; K padded buckets; customer-hashed homes; steal + collapse.
- [ ] Holds: slot first, stock second, undo on failure; one CAS decides confirm vs expiry; injected clock.
- [ ] Promotions: specs, groups, phases, attribution; deterministic tie-breaks.
- [ ] Measure oversell, stranded stock and conservation, not just throughput.

## 10. References

- Java `LongAdder` (sum is not atomic with updates). <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/atomic/LongAdder.html>
- Java `AtomicLongArray`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/atomic/AtomicLongArray.html>
- Eric Evans and Martin Fowler, *Specifications*. <https://martinfowler.com/apsupp/spec.pdf>
- PostgreSQL `SELECT … FOR UPDATE SKIP LOCKED`. <https://www.postgresql.org/docs/current/sql-select.html#SQL-FOR-UPDATE-SHARE>
- In this KB: [01.3 Striping and false sharing](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [02.2 Specification DSL](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md) · [P11 Largest remainder](01-problem-11-splitwise-expense-sharing-and-min-cash-flow-graph-simplifier.md) · [P6 Seat holds](../04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10/01-problem-06-movie-ticket-booking-bookmyshow-seat-lock-and-deadlock-free.md)
