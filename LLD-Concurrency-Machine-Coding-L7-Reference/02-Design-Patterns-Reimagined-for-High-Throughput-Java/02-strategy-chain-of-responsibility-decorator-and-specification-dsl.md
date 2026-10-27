# 02.2 · Strategy, Chain of Responsibility, Decorator, and a Specification DSL

> **Folder 02 · File 2 of 3.** These four behavioural patterns carry almost every "rules" requirement in LLD rounds: pricing, discounts, approvals, eligibility, routing. In modern Java and C++ they are mostly *function composition with explicit policy*:
>
> | Pattern | What it really is |
> |---|---|
> | **Strategy** | Choosing a function |
> | **Decorator** | Composing functions, *in a defined order* |
> | **Chain of responsibility** | First-decider-wins over a list of functions |
> | **Specification** | Boolean algebra over predicates, kept as **data** so it can be explained, serialized and optimized |
>
> The concurrency angle is that rules change at runtime, so the **swap** must be atomic.
>
> **Listing pair 2.2.1:** `PricingRulesDsl.java` / `pricing_rules_dsl.cpp`. Prices, explanations and approvals are identical in both languages (verified). The hot-swap counts are one measured run.

---

## 1. The four patterns as data flow

```text
cart ─► [Strategy: price each line by tier] ─► subtotal
       ─► [Specification: which promotions are eligible?] ─► best per exclusive group + all stackable
       ─► [Decorators in PHASES: DISCOUNT → SURCHARGE → TAX] ─► total + itemized breakdown
refund ─► [Chain: fraud guard → agent ≤ 50 → supervisor ≤ 500 → manager ≤ 5,000] ─► first decision | explicit end
```

| Pattern | Java 21 idiom | C++23 idiom | The L7 rule that goes with it |
|---|---|---|---|
| Strategy | `@FunctionalInterface` + `EnumMap<Tier, LinePricing>` | `std::function` / template parameter; `std::array` indexed by enum | Stateless and immutable, so one instance is shared by all threads. Selection is *data* (a map), not an `if` ladder |
| Decorator | `record Adjustment(name, Phase, fn)` applied phase by phase | Same struct + `std::function` | **Order is domain policy.** Encode it as phases, not as wrapping order at the call site |
| Chain of responsibility | `List<Approver>` returning a sealed `Decision` (`Approved`/`Escalate`/`Denied`) | `std::vector<std::function<Decision(const Refund&)>>` + `std::variant` | The chain needs an **explicit end** (`needs finance sign-off`). The first non-`Escalate` decision wins |
| Specification | `sealed interface Spec<T> permits Leaf, And, Or, Not` | A recursive AST behind `shared_ptr<const SpecNode<T>>`; `& \| ~` operators | Keep the tree as data, so `explain()` answers "why not?" and the same tree can be serialized or compiled to SQL |

## 2. Strategy: select by data, share freely

- **Selection is a lookup.** `EnumMap<Tier, LinePricing>` (Java) or `std::array` indexed by `Tier` (C++) replaces `if (tier == …)`. Adding a tier means adding one entry, and `EnumMap` iteration is in declaration order.
- **Strategies are stateless.** Thread-safety is then a non-question. A strategy that needs state (a rate table) gets it as an *immutable* constructor argument, and replacing the table means replacing the strategy (§6).
- **Don't create a strategy per conditional.** Introduce one only where the variation is a real business axis that changes independently: pricing by tier, dispatch by building, matching by market.

## 3. Decorators: the order is the policy ⚡

The same adjustments in a different order give different money. Tax is computed on the *discounted* amount. Free shipping triggers on the post-discount amount. A coupon applied after tax would also reduce the tax, which is illegal in many jurisdictions. Classic GoF wrapping (`new Tax(new Shipping(new Discount(base)))`) makes that order an accident of the call site. The listing makes it explicit:

- `enum Phase { DISCOUNT, SURCHARGE, TAX }`. The pipeline iterates phases in declaration order, then adjustments within a phase in list order.
- The adjustment list deliberately puts `tax 8.25%` **first**, and the output still applies it last.
- Every adjustment writes a breakdown line, so the receipt is an audit trail, not a recomputation. Zero-valued adjustments are omitted.

Rounding happens **per adjustment** (`pct()` is banker's rounding in integer cents). That's itself a policy choice: per line vs per order rounding can differ by a cent, so state which one the business uses.

## 4. Promotions: stackable vs exclusive

Each promotion has an eligibility `Spec`, a discount function and an optional **exclusive group**:

- **Stackable** promotions (`member 5%`) all apply.
- In an **exclusive group** (`coupon-or-bulk`), only the largest discount applies: `SAVE15` (21.04) beat `bulk books 10%` (14.03) for the member cart.
- Exclusive groups are applied before stackable ones, so `member 5%` is computed on the already-reduced amount. That's yet another policy, so the code makes it visible in one place.

Choosing the globally best combination when exclusivity is a general conflict graph is a maximum-weight independent set problem. It's tractable for the small n of a real cart; P15 does it properly.

## 5. The specification DSL: rules as data 🔥

`Predicate.and(...)` chains are opaque lambdas: you can evaluate them, nothing else. A specification **AST** adds:

1. **Explainability.** `explain()` walks the tree and marks every node `[ok]`/`[no]`. The output answers the most common support ticket ("why didn't my coupon apply?") from data. For the gift-card cart, `coupon SAVE15` is `[ok]` but `NOT contains a GIFT_CARD line` is `[no]`.
2. **Serializability.** Leaves are named, so the tree can be stored as JSON and edited by business users. P20's rule engine does exactly this.
3. **Translation and optimization.** The same AST can compile to a SQL `WHERE` clause or choose an index (P16's predicate AST), and can be simplified (`NOT NOT x → x`).
4. **Exhaustive interpretation.** `switch (this)` over the sealed node types has no `default`. A new node kind (`AtLeast(n, specs)`) won't compile until every interpreter handles it.

C++ needs indirection for a recursive variant. Each node is a `shared_ptr<const SpecNode<T>>` holding a `std::variant<Leaf, And, Or, Not>`. `Spec` is a cheap value handle, and nodes are immutable and shared, so specifications are thread-safe to evaluate concurrently. `and`/`or`/`not` are *alternative tokens* in C++, so the builders are `&`, `|` and `~`.

## 6. Chain of responsibility: first decider, explicit end

- Each handler returns `Approved`, `Denied` or `Escalate`. The runner returns the first non-`Escalate` result.
- The **guard handler goes first** (refund larger than the order, fraud flag). Authority checks come after it, so a manager can never approve a fraudulent refund by escalation.
- The **end of the chain is explicit** (`Denied("needs finance sign-off")`). A chain that silently returns `null` or "approved" at the end is the classic bug.
- **Chain vs pipeline.** Use a *chain* when one handler decides (approvals, routing). Use a *pipeline* when all handlers run and their results accumulate (validation that reports *all* errors). Interviewers like to ask which one their requirement needs.

## 7. Hot-swapping rules while traffic runs ⚡

Rule sets change at runtime: a marketing campaign starts at midnight, a tax rate updates. The naive design updates config fields one at a time while pricing threads read them one at a time, so a quote can combine the *new* discount with the *old* tax. The listing flips between two rule versions continuously while 3 threads price 1 M quotes each:

| Design | Java | C++ | Why |
|---|---|---|---|
| Field-by-field mutable config (each field `volatile`/atomic) | **234,531** mixed quotes of 3 M | **703,236** | Each field is atomic; the *set* of fields isn't. Same disease as check-then-act (file 01.3, §3) |
| Immutable snapshot, one reference swap (copy-on-write) | **0** | **0** | A reader takes one reference and uses only that version |

In C++ the snapshot is an `std::atomic<const RuleSet*>` over versions the owner keeps alive. Rule sets are tiny and change rarely, so never freeing them during the process lifetime is a legitimate reclamation policy, and readers pay one acquire load. If versions had to be reclaimed, the options are RCU, hazard pointers, or a grace period. `std::atomic<std::shared_ptr>` would also work in libstdc++, but it isn't lock-free there and libc++ lacks it (file 01.2 §4.5).

### 7.1 Listing 2.2.1 (Java)

```java
// PricingRulesDsl.java - strategy, phased decorators, chain of responsibility, a specification DSL, hot-swapped rules
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.Predicate;
import java.util.function.ToLongBiFunction;

public final class PricingRulesDsl {

    // ===== Domain ===================================================================================

    enum Tier { GUEST, MEMBER, VIP }

    record Line(String sku, String category, long unitCents, int qty) {}

    record Cart(Tier tier, List<Line> lines, boolean express, String coupon) {
        Cart {
            lines = List.copyOf(lines);
        }

        int units() {
            return lines.stream().mapToInt(Line::qty).sum();
        }

        boolean has(String category) {
            return lines.stream().anyMatch(l -> l.category().equals(category));
        }
    }

    /** cents x basisPoints / 10_000, rounded half-to-even (banker's rounding). */
    static long pct(long cents, long bp) {
        long num = Math.multiplyExact(cents, bp), q = num / 10_000, r = num % 10_000;
        return r > 5_000 || (r == 5_000 && (q & 1) == 1) ? q + 1 : q;
    }

    static String money(long cents) {
        return String.format("%s%d.%02d", cents < 0 ? "-" : "", Math.abs(cents) / 100, Math.abs(cents) % 100);
    }

    // ===== 1. Strategy: how one line is priced, chosen by tier =======================================

    @FunctionalInterface
    interface LinePricing {
        long price(Line l);
    }

    static final LinePricing LIST = l -> Math.multiplyExact(l.unitCents(), l.qty());
    static final LinePricing VOLUME = l -> {
        long base = LIST.price(l);
        return l.qty() >= 10 ? base - pct(base, 1_000) : l.qty() >= 5 ? base - pct(base, 500) : base;
    };
    static final Map<Tier, LinePricing> PRICING_BY_TIER = new EnumMap<>(Map.of(Tier.GUEST, LIST, Tier.MEMBER, VOLUME, Tier.VIP, VOLUME));

    // ===== 4. Specification DSL: composable, explainable eligibility =================================

    sealed interface Spec<T> permits Leaf, And, Or, Not {
        boolean test(T t);

        default Spec<T> and(Spec<T> o) { return new And<>(this, o); }
        default Spec<T> or(Spec<T> o) { return new Or<>(this, o); }
        default Spec<T> negate() { return new Not<>(this); }

        /** The tree with a verdict on every node: "why wasn't my coupon applied?" answered from data. */
        default void explain(T t, String indent, List<String> out) {
            String mark = test(t) ? "[ok] " : "[no] ";
            switch (this) {
                case Leaf<T> l -> out.add(indent + mark + l.name());
                case And<T> a -> {
                    out.add(indent + mark + "ALL OF");
                    a.left().explain(t, indent + "    ", out);
                    a.right().explain(t, indent + "    ", out);
                }
                case Or<T> o -> {
                    out.add(indent + mark + "ANY OF");
                    o.left().explain(t, indent + "    ", out);
                    o.right().explain(t, indent + "    ", out);
                }
                case Not<T> n -> {
                    out.add(indent + mark + "NOT");
                    n.inner().explain(t, indent + "    ", out);
                }
            }
        }
    }
    record Leaf<T>(String name, Predicate<T> p) implements Spec<T> {
        public boolean test(T t) { return p.test(t); }
    }
    record And<T>(Spec<T> left, Spec<T> right) implements Spec<T> {
        public boolean test(T t) { return left.test(t) && right.test(t); }
    }
    record Or<T>(Spec<T> left, Spec<T> right) implements Spec<T> {
        public boolean test(T t) { return left.test(t) || right.test(t); }
    }
    record Not<T>(Spec<T> inner) implements Spec<T> {
        public boolean test(T t) { return !inner.test(t); }
    }

    static final Spec<Cart> IS_MEMBER = new Leaf<>("tier is MEMBER or VIP", c -> c.tier() != Tier.GUEST);
    static final Spec<Cart> BULK = new Leaf<>("at least 12 units", c -> c.units() >= 12);
    static final Spec<Cart> HAS_BOOKS = new Leaf<>("contains a BOOKS line", c -> c.has("BOOKS"));
    static final Spec<Cart> HAS_GIFT_CARD = new Leaf<>("contains a GIFT_CARD line", c -> c.has("GIFT_CARD"));
    static final Spec<Cart> COUPON_SAVE15 = new Leaf<>("coupon SAVE15", c -> "SAVE15".equals(c.coupon()));

    /** exclusiveGroup == null: stackable. Same group: only the largest discount applies. */
    record Promotion(String name, Spec<Cart> eligible, String exclusiveGroup, ToLongBiFunction<Cart, Long> discount) {}

    static final List<Promotion> PROMOTIONS = List.of(
            new Promotion("member 5%", IS_MEMBER, null, (c, amt) -> pct(amt, 500)),
            new Promotion("bulk books 10%", BULK.and(HAS_BOOKS), "coupon-or-bulk", (c, amt) -> pct(amt, 1_000)),
            new Promotion("SAVE15", COUPON_SAVE15.and(HAS_GIFT_CARD.negate()), "coupon-or-bulk", (c, amt) -> pct(amt, 1_500)));

    // ===== 2. Decorators as explicit, ordered phases ===============================================

    enum Phase { DISCOUNT, SURCHARGE, TAX }               // the ORDER is domain policy: tax after discounts

    record Adjustment(String name, Phase phase, ToLongBiFunction<Cart, Long> delta) {}

    record Quote(long total, Map<String, Long> breakdown) {}

    static Quote quote(Cart cart, List<Adjustment> adjustments) {
        Map<String, Long> breakdown = new LinkedHashMap<>();
        long amount = 0;
        LinePricing strategy = PRICING_BY_TIER.get(cart.tier());
        for (Line l : cart.lines()) amount += strategy.price(l);
        breakdown.put("subtotal (" + cart.tier() + " pricing)", amount);
        // promotions: stackable ones all apply; per exclusive group only the best one
        Map<String, Promotion> bestPerGroup = new LinkedHashMap<>();
        List<Promotion> stackable = new ArrayList<>();
        for (Promotion p : PROMOTIONS) {
            if (!p.eligible().test(cart)) continue;
            if (p.exclusiveGroup() == null) stackable.add(p);
            else {
                final long base = amount;
                bestPerGroup.merge(p.exclusiveGroup(), p, (a, b) ->
                        b.discount().applyAsLong(cart, base) > a.discount().applyAsLong(cart, base) ? b : a);
            }
        }
        List<Promotion> applied = new ArrayList<>(bestPerGroup.values());
        applied.addAll(stackable);
        for (Promotion p : applied) {
            long d = p.discount().applyAsLong(cart, amount);
            amount -= d;
            breakdown.put("promo " + p.name(), -d);
        }
        for (Phase phase : Phase.values())
            for (Adjustment a : adjustments)
                if (a.phase() == phase) {
                    long d = a.delta().applyAsLong(cart, amount);
                    if (d == 0) continue;
                    amount += d;
                    breakdown.put(a.name(), d);
                }
        return new Quote(amount, breakdown);
    }

    // ===== 3. Chain of responsibility: refund approvals =============================================

    record Refund(long cents, long orderTotal, boolean flagged) {}

    sealed interface Decision permits Approved, Escalate, Denied {}
    record Approved(String by) implements Decision {}
    record Escalate() implements Decision {}
    record Denied(String reason) implements Decision {}

    @FunctionalInterface
    interface Approver {
        Decision decide(Refund r);
    }

    static Approver limit(String role, long maxCents) {
        return r -> r.cents() <= maxCents ? new Approved(role) : new Escalate();
    }

    static final List<Approver> REFUND_CHAIN = List.of(
            r -> r.cents() > r.orderTotal() ? new Denied("exceeds order total") : r.flagged() ? new Denied("fraud flag") : new Escalate(),
            limit("agent", 50_00), limit("supervisor", 500_00), limit("manager", 5_000_00));

    static Decision approve(Refund r) {
        for (Approver a : REFUND_CHAIN) {
            Decision d = a.decide(r);
            if (!(d instanceof Escalate)) return d;       // first handler that decides, wins
        }
        return new Denied("needs finance sign-off");     // the chain's explicit end
    }

    // ===== 5. Hot-swapping rules while pricing runs =================================================

    record RuleSet(int version, long discountBp, long taxBp, long expressCents) {}

    static final RuleSet V_ODD = new RuleSet(1, 1_000, 800, 500), V_EVEN = new RuleSet(2, 2_000, 900, 700);

    static long priceWith(long subtotal, long discountBp, long taxBp, long expressCents) {
        long afterDiscount = subtotal - pct(subtotal, discountBp);
        long withShipping = afterDiscount + expressCents;
        return withShipping + pct(withShipping, taxBp);
    }

    /** Naive: the admin thread updates fields one by one; a reader may see half of an update. */
    static final class MutableConfig {
        volatile long discountBp = V_ODD.discountBp(), taxBp = V_ODD.taxBp(), expressCents = V_ODD.expressCents();

        void apply(RuleSet r) {
            discountBp = r.discountBp();
            taxBp = r.taxBp();
            expressCents = r.expressCents();
        }

        long price(long subtotal) {
            long d = discountBp;
            long e = expressCents;                            // each field read at a different moment
            long t = taxBp;
            return priceWith(subtotal, d, t, e);
        }
    }

    /** Copy-on-write: readers take ONE snapshot reference; a swap is a single volatile write. */
    static final class SnapshotConfig {
        final AtomicReference<RuleSet> current = new AtomicReference<>(V_ODD);

        long price(long subtotal) {
            RuleSet r = current.get();
            return priceWith(subtotal, r.discountBp(), r.taxBp(), r.expressCents());
        }
    }

    static long mixedResults(boolean snapshot, int readers, int perReader) throws InterruptedException {
        MutableConfig mutable = new MutableConfig();
        SnapshotConfig snap = new SnapshotConfig();
        long subtotal = 123_45;
        long okA = priceWith(subtotal, V_ODD.discountBp(), V_ODD.taxBp(), V_ODD.expressCents());
        long okB = priceWith(subtotal, V_EVEN.discountBp(), V_EVEN.taxBp(), V_EVEN.expressCents());
        AtomicBoolean stop = new AtomicBoolean();
        Thread admin = Thread.ofPlatform().start(() -> {
            for (int i = 0; !stop.get(); i++) {
                RuleSet r = (i & 1) == 0 ? V_EVEN : V_ODD;
                if (snapshot) snap.current.set(r);
                else mutable.apply(r);
            }
        });
        LongAdder mixed = new LongAdder();
        CountDownLatch done = new CountDownLatch(readers);
        for (int t = 0; t < readers; t++) {
            Thread.ofPlatform().start(() -> {
                for (int i = 0; i < perReader; i++) {
                    long p = snapshot ? snap.price(subtotal) : mutable.price(subtotal);
                    if (p != okA && p != okB) mixed.increment();
                }
                done.countDown();
            });
        }
        done.await();
        stop.set(true);
        admin.join();
        return mixed.sum();
    }

    public static void main(String[] args) throws InterruptedException {
        List<Adjustment> adjustments = List.of(
                new Adjustment("tax 8.25%", Phase.TAX, (c, amt) -> pct(amt, 825)),        // listed first ...
                new Adjustment("express shipping", Phase.SURCHARGE, (c, amt) -> c.express() ? 799 : 0),
                new Adjustment("free shipping over 100.00", Phase.SURCHARGE, (c, amt) -> c.express() && amt >= 100_00 ? -799 : 0));
        Cart guest = new Cart(Tier.GUEST, List.of(new Line("bk-1", "BOOKS", 12_99, 12)), true, null);
        Cart member = new Cart(Tier.MEMBER, List.of(new Line("bk-1", "BOOKS", 12_99, 12)), true, "SAVE15");
        Cart memberGift = new Cart(Tier.MEMBER, List.of(new Line("bk-1", "BOOKS", 12_99, 3),
                new Line("gc-50", "GIFT_CARD", 50_00, 1)), false, "SAVE15");

        System.out.println("== Strategy + promotions + phased decorators ==");
        for (Cart c : List.of(guest, member, memberGift)) {
            Quote q = quote(c, adjustments);
            System.out.println(c.tier() + " cart, coupon=" + c.coupon() + ", express=" + c.express() + " -> total " + money(q.total()));
            q.breakdown().forEach((k, v) -> System.out.printf("    %-34s %10s%n", k, money(v)));
        }

        System.out.println("== Specification explain(): why did SAVE15 not apply to the gift-card cart? ==");
        List<String> lines = new ArrayList<>();
        COUPON_SAVE15.and(HAS_GIFT_CARD.negate()).explain(memberGift, "    ", lines);
        lines.forEach(System.out::println);

        System.out.println("== Chain of responsibility: refund approvals ==");
        for (Refund r : List.of(new Refund(30_00, 100_00, false), new Refund(300_00, 900_00, false),
                new Refund(3_000_00, 9_000_00, false), new Refund(9_000_00, 20_000_00, false),
                new Refund(200_00, 100_00, false), new Refund(10_00, 100_00, true)))
            System.out.printf("    refund %9s of %9s flagged=%-5s -> %s%n", money(r.cents()), money(r.orderTotal()), r.flagged(), approve(r));

        System.out.println("== Hot-swapping rules during pricing: 3 readers x 1,000,000 quotes ==");
        long naive = mixedResults(false, 3, 1_000_000);
        long cow = mixedResults(true, 3, 1_000_000);
        System.out.printf("    field-by-field mutable config : %,d quotes mixed two rule versions%n", naive);
        System.out.printf("    immutable snapshot (COW)      : %,d quotes mixed two rule versions%n", cow);

        Quote m = quote(member, adjustments);
        boolean ok = cow == 0 && m.breakdown().containsKey("promo SAVE15") && !m.breakdown().containsKey("promo bulk books 10%")
                && approve(new Refund(200_00, 100_00, false)) instanceof Denied
                && approve(new Refund(300_00, 900_00, false)).equals(new Approved("supervisor"));
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (verified, except the mixed-quote count: one measured run):**

```text
== Strategy + promotions + phased decorators ==
GUEST cart, coupon=null, express=true -> total 151.86
    subtotal (GUEST pricing)               155.88
    promo bulk books 10%                   -15.59
    express shipping                         7.99
    free shipping over 100.00               -7.99
    tax 8.25%                               11.57
MEMBER cart, coupon=SAVE15, express=true -> total 122.64
    subtotal (MEMBER pricing)              140.29
    promo SAVE15                           -21.04
    promo member 5%                         -5.96
    express shipping                         7.99
    free shipping over 100.00               -7.99
    tax 8.25%                                9.35
MEMBER cart, coupon=SAVE15, express=false -> total 91.49
    subtotal (MEMBER pricing)               88.97
    promo member 5%                         -4.45
    tax 8.25%                                6.97
== Specification explain(): why did SAVE15 not apply to the gift-card cart? ==
    [no] ALL OF
        [ok] coupon SAVE15
        [no] NOT
            [ok] contains a GIFT_CARD line
== Chain of responsibility: refund approvals ==
    refund     30.00 of    100.00 flagged=false -> Approved[by=agent]
    refund    300.00 of    900.00 flagged=false -> Approved[by=supervisor]
    refund   3000.00 of   9000.00 flagged=false -> Approved[by=manager]
    refund   9000.00 of  20000.00 flagged=false -> Denied[reason=needs finance sign-off]
    refund    200.00 of    100.00 flagged=false -> Denied[reason=exceeds order total]
    refund     10.00 of    100.00 flagged=true  -> Denied[reason=fraud flag]
== Hot-swapping rules during pricing: 3 readers x 1,000,000 quotes ==
    field-by-field mutable config : 234,531 quotes mixed two rule versions
    immutable snapshot (COW)      : 0 quotes mixed two rule versions
SELF-TEST OK
```

### 7.2 Listing 2.2.1 (C++)

```cpp
// pricing_rules_dsl.cpp - strategy, phased decorators, chain of responsibility, a specification DSL, hot-swapped rules
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <functional>
#include <latch>
#include <map>
#include <memory>
#include <optional>
#include <print>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

// ===== Domain ===================================================================================

enum class Tier { Guest, Member, Vip };
constexpr const char* kTierNames[] = {"GUEST", "MEMBER", "VIP"};

struct Line { std::string sku, category; std::int64_t unit_cents; int qty; };
struct Cart {
    Tier tier;
    std::vector<Line> lines;
    bool express;
    std::optional<std::string> coupon;
    int units() const {
        int u = 0;
        for (const auto& l : lines) u += l.qty;
        return u;
    }
    bool has(const std::string& cat) const {
        for (const auto& l : lines)
            if (l.category == cat) return true;
        return false;
    }
};

std::int64_t pct(std::int64_t cents, std::int64_t bp) {  // half-to-even
    std::int64_t num;
    if (__builtin_mul_overflow(cents, bp, &num)) throw std::overflow_error("pct");
    const std::int64_t q = num / 10'000, r = num % 10'000;
    return r > 5'000 || (r == 5'000 && (q & 1) == 1) ? q + 1 : q;
}

std::string money(std::int64_t c) { return std::format("{}{}.{:02}", c < 0 ? "-" : "", std::llabs(c) / 100, std::llabs(c) % 100); }

// ===== 1. Strategy: how one line is priced, chosen by tier =======================================

using LinePricing = std::function<std::int64_t(const Line&)>;
const LinePricing kList = [](const Line& l) { return l.unit_cents * l.qty; };
const LinePricing kVolume = [](const Line& l) {
    const std::int64_t base = kList(l);
    return l.qty >= 10 ? base - pct(base, 1'000) : l.qty >= 5 ? base - pct(base, 500) : base;
};
const std::array<LinePricing, 3> kPricingByTier{kList, kVolume, kVolume};

// ===== 4. Specification DSL: a recursive AST behind shared_ptr ===================================

template <class T> struct SpecNode;

template <class T>
class Spec {  // value type; `&`, `|`, `~` build nodes (and/or/not are alternative tokens in C++)
    std::shared_ptr<const SpecNode<T>> n_;
    explicit Spec(std::shared_ptr<const SpecNode<T>> n) : n_(std::move(n)) {}
    template <class> friend struct SpecNode;
public:
    static Spec leaf(std::string name, std::function<bool(const T&)> p);
    Spec operator&(const Spec& o) const;
    Spec operator|(const Spec& o) const;
    Spec operator~() const;
    bool test(const T& t) const;
    void explain(const T& t, const std::string& indent, std::vector<std::string>& out) const;
};

template <class T>
struct SpecNode {
    struct Leaf { std::string name; std::function<bool(const T&)> p; };
    struct And { Spec<T> l, r; };
    struct Or { Spec<T> l, r; };
    struct Not { Spec<T> inner; };
    std::variant<Leaf, And, Or, Not> v;
    static Spec<T> wrap(std::variant<Leaf, And, Or, Not> x) { return Spec<T>(std::make_shared<const SpecNode>(SpecNode{std::move(x)})); }
};

template <class T> Spec<T> Spec<T>::leaf(std::string name, std::function<bool(const T&)> p) {
    return SpecNode<T>::wrap(typename SpecNode<T>::Leaf{std::move(name), std::move(p)});
}
template <class T> Spec<T> Spec<T>::operator&(const Spec& o) const { return SpecNode<T>::wrap(typename SpecNode<T>::And{*this, o}); }
template <class T> Spec<T> Spec<T>::operator|(const Spec& o) const { return SpecNode<T>::wrap(typename SpecNode<T>::Or{*this, o}); }
template <class T> Spec<T> Spec<T>::operator~() const { return SpecNode<T>::wrap(typename SpecNode<T>::Not{*this}); }

template <class T> bool Spec<T>::test(const T& t) const {
    using N = SpecNode<T>;
    return std::visit(overloaded{
        [&](const typename N::Leaf& x) { return x.p(t); },
        [&](const typename N::And& x) { return x.l.test(t) && x.r.test(t); },
        [&](const typename N::Or& x) { return x.l.test(t) || x.r.test(t); },
        [&](const typename N::Not& x) { return !x.inner.test(t); },
    }, n_->v);
}

template <class T> void Spec<T>::explain(const T& t, const std::string& indent, std::vector<std::string>& out) const {
    using N = SpecNode<T>;
    const std::string mark = test(t) ? "[ok] " : "[no] ", deeper = indent + "    ";
    std::visit(overloaded{
        [&](const typename N::Leaf& x) { out.push_back(indent + mark + x.name); },
        [&](const typename N::And& x) { out.push_back(indent + mark + "ALL OF"); x.l.explain(t, deeper, out); x.r.explain(t, deeper, out); },
        [&](const typename N::Or& x) { out.push_back(indent + mark + "ANY OF"); x.l.explain(t, deeper, out); x.r.explain(t, deeper, out); },
        [&](const typename N::Not& x) { out.push_back(indent + mark + "NOT"); x.inner.explain(t, deeper, out); },
    }, n_->v);
}

const auto kIsMember = Spec<Cart>::leaf("tier is MEMBER or VIP", [](const Cart& c) { return c.tier != Tier::Guest; });
const auto kBulk = Spec<Cart>::leaf("at least 12 units", [](const Cart& c) { return c.units() >= 12; });
const auto kHasBooks = Spec<Cart>::leaf("contains a BOOKS line", [](const Cart& c) { return c.has("BOOKS"); });
const auto kHasGiftCard = Spec<Cart>::leaf("contains a GIFT_CARD line", [](const Cart& c) { return c.has("GIFT_CARD"); });
const auto kCouponSave15 = Spec<Cart>::leaf("coupon SAVE15", [](const Cart& c) { return c.coupon == "SAVE15"; });

struct Promotion {
    std::string name;
    Spec<Cart> eligible;
    std::optional<std::string> exclusive_group;  // nullopt: stackable
    std::function<std::int64_t(const Cart&, std::int64_t)> discount;
};

const std::vector<Promotion> kPromotions = {
    {"member 5%", kIsMember, std::nullopt, [](const Cart&, std::int64_t a) { return pct(a, 500); }},
    {"bulk books 10%", kBulk & kHasBooks, "coupon-or-bulk", [](const Cart&, std::int64_t a) { return pct(a, 1'000); }},
    {"SAVE15", kCouponSave15 & ~kHasGiftCard, "coupon-or-bulk", [](const Cart&, std::int64_t a) { return pct(a, 1'500); }},
};

// ===== 2. Decorators as explicit, ordered phases ===============================================

enum class Phase { Discount, Surcharge, Tax };  // the ORDER is domain policy: tax after discounts
struct Adjustment { std::string name; Phase phase; std::function<std::int64_t(const Cart&, std::int64_t)> delta; };
struct Quote { std::int64_t total; std::vector<std::pair<std::string, std::int64_t>> breakdown; };

Quote quote(const Cart& cart, const std::vector<Adjustment>& adjustments) {
    Quote q{0, {}};
    std::int64_t amount = 0;
    for (const auto& l : cart.lines) amount += kPricingByTier[static_cast<std::size_t>(cart.tier)](l);
    q.breakdown.emplace_back(std::format("subtotal ({} pricing)", kTierNames[static_cast<std::size_t>(cart.tier)]), amount);
    std::map<std::string, const Promotion*> best;  // per exclusive group
    std::vector<const Promotion*> applied;
    for (const auto& p : kPromotions) {
        if (!p.eligible.test(cart)) continue;
        if (!p.exclusive_group) continue;
        auto [it, fresh] = best.try_emplace(*p.exclusive_group, &p);
        if (!fresh && p.discount(cart, amount) > it->second->discount(cart, amount)) it->second = &p;
    }
    for (const auto& [group, p] : best) applied.push_back(p);
    for (const auto& p : kPromotions)
        if (!p.exclusive_group && p.eligible.test(cart)) applied.push_back(&p);
    for (const auto* p : applied) {
        const auto d = p->discount(cart, amount);
        amount -= d;
        q.breakdown.emplace_back("promo " + p->name, -d);
    }
    for (Phase phase : {Phase::Discount, Phase::Surcharge, Phase::Tax})
        for (const auto& a : adjustments)
            if (a.phase == phase)
                if (const auto d = a.delta(cart, amount); d != 0) {
                    amount += d;
                    q.breakdown.emplace_back(a.name, d);
                }
    q.total = amount;
    return q;
}

// ===== 3. Chain of responsibility: refund approvals =============================================

struct Refund { std::int64_t cents, order_total; bool flagged; };
struct Approved { std::string by; };
struct Escalate {};
struct Denied { std::string reason; };
using Decision = std::variant<Approved, Escalate, Denied>;
using Approver = std::function<Decision(const Refund&)>;

Approver limit(std::string role, std::int64_t max_cents) {
    return [role = std::move(role), max_cents](const Refund& r) -> Decision {
        if (r.cents <= max_cents) return Approved{role};
        return Escalate{};
    };
}

const std::vector<Approver> kRefundChain = {
    [](const Refund& r) -> Decision {
        if (r.cents > r.order_total) return Denied{"exceeds order total"};
        if (r.flagged) return Denied{"fraud flag"};
        return Escalate{};
    },
    limit("agent", 50'00), limit("supervisor", 500'00), limit("manager", 5'000'00)};

Decision approve(const Refund& r) {
    for (const auto& a : kRefundChain)
        if (Decision d = a(r); !std::holds_alternative<Escalate>(d)) return d;  // first decider wins
    return Denied{"needs finance sign-off"};
}

std::string describe(const Decision& d) {
    return std::visit(overloaded{
        [](const Approved& a) { return "Approved[" + a.by + "]"; },
        [](const Escalate&) { return std::string("Escalate"); },
        [](const Denied& x) { return "Denied[" + x.reason + "]"; },
    }, d);
}

// ===== 5. Hot-swapping rules while pricing runs =================================================

struct RuleSet { int version; std::int64_t discount_bp, tax_bp, express_cents; };
constexpr RuleSet kOdd{1, 1'000, 800, 500}, kEven{2, 2'000, 900, 700};

std::int64_t price_with(std::int64_t subtotal, std::int64_t d, std::int64_t t, std::int64_t e) {
    const std::int64_t after = subtotal - pct(subtotal, d), with_ship = after + e;
    return with_ship + pct(with_ship, t);
}

struct MutableConfig {  // field-by-field updates: a reader can observe half of a change
    std::atomic<std::int64_t> discount_bp{kOdd.discount_bp}, tax_bp{kOdd.tax_bp}, express_cents{kOdd.express_cents};
    void apply(const RuleSet& r) {
        discount_bp.store(r.discount_bp, std::memory_order_relaxed);
        tax_bp.store(r.tax_bp, std::memory_order_relaxed);
        express_cents.store(r.express_cents, std::memory_order_relaxed);
    }
    std::int64_t price(std::int64_t subtotal) const {
        const auto d = discount_bp.load(std::memory_order_relaxed);
        const auto e = express_cents.load(std::memory_order_relaxed);
        const auto t = tax_bp.load(std::memory_order_relaxed);
        return price_with(subtotal, d, t, e);
    }
};

/**
 * Copy-on-write without atomic<shared_ptr>: rule sets are tiny and change rarely, so every published
 * version is kept alive by the owner and readers do ONE acquire load. (If versions had to be freed:
 * RCU / hazard pointers / a grace period.)
 */
class SnapshotConfig {
    std::vector<std::unique_ptr<const RuleSet>> versions_;  // touched by the single admin thread only
    std::atomic<const RuleSet*> current_;
public:
    SnapshotConfig() {
        versions_.push_back(std::make_unique<const RuleSet>(kOdd));
        versions_.push_back(std::make_unique<const RuleSet>(kEven));
        current_.store(versions_[0].get());
    }
    void publish(std::size_t i) { current_.store(versions_[i].get(), std::memory_order_release); }
    std::int64_t price(std::int64_t subtotal) const {
        const RuleSet* r = current_.load(std::memory_order_acquire);
        return price_with(subtotal, r->discount_bp, r->tax_bp, r->express_cents);
    }
};

std::uint64_t mixed_results(bool snapshot, int readers, int per_reader) {
    MutableConfig mutable_cfg;
    SnapshotConfig snap;
    constexpr std::int64_t subtotal = 123'45;
    const auto ok_a = price_with(subtotal, kOdd.discount_bp, kOdd.tax_bp, kOdd.express_cents);
    const auto ok_b = price_with(subtotal, kEven.discount_bp, kEven.tax_bp, kEven.express_cents);
    std::atomic<bool> stop{false};
    std::atomic<std::uint64_t> mixed{0};
    std::jthread admin([&] {
        for (std::size_t i = 0; !stop.load(std::memory_order_relaxed); ++i) {
            if (snapshot) snap.publish(i & 1);
            else mutable_cfg.apply((i & 1) ? kOdd : kEven);
        }
    });
    {
        std::latch start(1);
        std::vector<std::jthread> ts;
        for (int t = 0; t < readers; ++t)
            ts.emplace_back([&] {
                start.wait();
                std::uint64_t bad = 0;
                for (int i = 0; i < per_reader; ++i) {
                    const auto p = snapshot ? snap.price(subtotal) : mutable_cfg.price(subtotal);
                    bad += (p != ok_a && p != ok_b);
                }
                mixed.fetch_add(bad);
            });
        start.count_down();
    }
    stop.store(true);
    return mixed.load();
}

int main() {
    const std::vector<Adjustment> adjustments = {
        {"tax 8.25%", Phase::Tax, [](const Cart&, std::int64_t a) { return pct(a, 825); }},  // listed first ...
        {"express shipping", Phase::Surcharge, [](const Cart& c, std::int64_t) -> std::int64_t { return c.express ? 799 : 0; }},
        {"free shipping over 100.00", Phase::Surcharge,
         [](const Cart& c, std::int64_t a) -> std::int64_t { return c.express && a >= 100'00 ? -799 : 0; }},
    };
    const Cart guest{Tier::Guest, {{"bk-1", "BOOKS", 12'99, 12}}, true, std::nullopt};
    const Cart member{Tier::Member, {{"bk-1", "BOOKS", 12'99, 12}}, true, "SAVE15"};
    const Cart member_gift{Tier::Member, {{"bk-1", "BOOKS", 12'99, 3}, {"gc-50", "GIFT_CARD", 50'00, 1}}, false, "SAVE15"};

    std::println("== Strategy + promotions + phased decorators ==");
    for (const Cart* c : {&guest, &member, &member_gift}) {
        const Quote q = quote(*c, adjustments);
        std::println("{} cart, coupon={}, express={} -> total {}", kTierNames[static_cast<std::size_t>(c->tier)],
                     c->coupon.value_or("null"), c->express, money(q.total));
        for (const auto& [k, v] : q.breakdown) std::println("    {:<34} {:>10}", k, money(v));
    }

    std::println("== Specification explain(): why did SAVE15 not apply to the gift-card cart? ==");
    std::vector<std::string> lines;
    (kCouponSave15 & ~kHasGiftCard).explain(member_gift, "    ", lines);
    for (const auto& l : lines) std::println("{}", l);

    std::println("== Chain of responsibility: refund approvals ==");
    for (const Refund& r : {Refund{30'00, 100'00, false}, Refund{300'00, 900'00, false}, Refund{3'000'00, 9'000'00, false},
                            Refund{9'000'00, 20'000'00, false}, Refund{200'00, 100'00, false}, Refund{10'00, 100'00, true}})
        std::println("    refund {:>9} of {:>9} flagged={:<5} -> {}", money(r.cents), money(r.order_total), r.flagged, describe(approve(r)));

    std::println("== Hot-swapping rules during pricing: 3 readers x 1,000,000 quotes ==");
    const auto naive = mixed_results(false, 3, 1'000'000);
    const auto cow = mixed_results(true, 3, 1'000'000);
    std::println("    field-by-field mutable config : {} quotes mixed two rule versions", naive);
    std::println("    immutable snapshot (COW)      : {} quotes mixed two rule versions", cow);

    const Quote m = quote(member, adjustments);
    bool has_save15 = false, has_bulk = false;
    for (const auto& [k, v] : m.breakdown) {
        has_save15 |= k == "promo SAVE15";
        has_bulk |= k == "promo bulk books 10%";
    }
    const bool ok = cow == 0 && has_save15 && !has_bulk && std::holds_alternative<Denied>(approve({200'00, 100'00, false})) &&
                    describe(approve({300'00, 900'00, false})) == "Approved[supervisor]";
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2 (Clang 21.1 identical except the measured count):**

```text
== Strategy + promotions + phased decorators ==
GUEST cart, coupon=null, express=true -> total 151.86
    subtotal (GUEST pricing)               155.88
    promo bulk books 10%                   -15.59
    express shipping                         7.99
    free shipping over 100.00               -7.99
    tax 8.25%                               11.57
MEMBER cart, coupon=SAVE15, express=true -> total 122.64
    subtotal (MEMBER pricing)              140.29
    promo SAVE15                           -21.04
    promo member 5%                         -5.96
    express shipping                         7.99
    free shipping over 100.00               -7.99
    tax 8.25%                                9.35
MEMBER cart, coupon=SAVE15, express=false -> total 91.49
    subtotal (MEMBER pricing)               88.97
    promo member 5%                         -4.45
    tax 8.25%                                6.97
== Specification explain(): why did SAVE15 not apply to the gift-card cart? ==
    [no] ALL OF
        [ok] coupon SAVE15
        [no] NOT
            [ok] contains a GIFT_CARD line
== Chain of responsibility: refund approvals ==
    refund     30.00 of    100.00 flagged=false -> Approved[agent]
    refund    300.00 of    900.00 flagged=false -> Approved[supervisor]
    refund   3000.00 of   9000.00 flagged=false -> Approved[manager]
    refund   9000.00 of  20000.00 flagged=false -> Denied[needs finance sign-off]
    refund    200.00 of    100.00 flagged=false -> Denied[exceeds order total]
    refund     10.00 of    100.00 flagged=true  -> Denied[fraud flag]
== Hot-swapping rules during pricing: 3 readers x 1,000,000 quotes ==
    field-by-field mutable config : 703236 quotes mixed two rule versions
    immutable snapshot (COW)      : 0 quotes mixed two rule versions
SELF-TEST OK
```

## 8. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Strategy | `if/else` on type or tier | Strategy interface + factory | Lookup by enum/map; stateless; selection testable as data |
| Decorators | Nested wrappers in whatever order the call site uses | Wrappers with documented order | **Phases** as domain policy; itemized breakdown; rounding policy explicit |
| Eligibility | Boolean methods per promotion | `Predicate` chains | Specification AST: explainable, serializable, translatable, exhaustive interpreters |
| Approvals | One method with thresholds | Chain of handlers | Guard first, explicit end, sealed decisions; chain vs pipeline chosen deliberately |
| Runtime change | Mutable singleton config | Config re-read per request | Immutable snapshot + atomic swap; version stamped on every quote for audit |

## 9. Curveballs

| Curveball | 5-minute response |
|---|---|
| "VIP gets free express shipping" | One adjustment in `SURCHARGE`, guarded by `IS_VIP`. Phase order already ensures tax applies after it |
| "Coupons must not combine with bulk discount, except for VIPs" | Exclusivity becomes data: the group is selected by a `Spec` (`IS_VIP ? null : "coupon-or-bulk"`). No new classes |
| "Explain to support why a promotion didn't apply" | Already there: `explain()` on the eligibility spec; log it with the quote id |
| "Business users edit promotions without a deploy" | Serialize the spec AST (named leaves from a registry plus `And`/`Or`/`Not`); validate on load; swap atomically (§7) |
| "Refunds over 1,000 need two approvers" | Change the decision type: `Approved(by)` becomes `PartiallyApproved(by)`, and the runner continues to the next authority, collecting approvals. The sealed `Decision` shows every place that must handle it |
| "Quotes must be reproducible for 7 years" | Stamp the rule-set version and the breakdown on every quote; keep historical rule sets immutable |

## 10. Bar-raiser chains

<details>
<summary><b>Q1 ⚡ "Why not just chain <code>Predicate.and()</code>?"</b></summary>

**L5:** "It's the same thing and built in."

**Why it fails:** a lambda chain can only be *evaluated*. Support can't see why a rule failed, business users can't edit it, and nothing can translate it to a query or check it for contradictions.

**L7 defence:** "I keep the predicate as a sealed AST with named leaves. Evaluation is one interpreter; `explain`, serialization, SQL translation and simplification are others. The sealed type makes each interpreter exhaustive. The leaves can still wrap lambdas: the structure is data, the atoms are code."
</details>

<details>
<summary><b>Q2 🔥 "Your discounts and tax: does order matter?"</b></summary>

**L5:** "We apply them in the order they're added."

**Why it fails:** order then depends on whoever wrote the call site. Tax on the pre-discount amount, or a coupon reducing tax, are legal and financial defects.

**L7 defence:** "Order is policy, so it's a type: phases DISCOUNT → SURCHARGE → TAX, with list order inside a phase. The listing declares tax first and it still applies last. Every step writes a breakdown line with explicit rounding, so the receipt is the audit."
</details>

<details>
<summary><b>Q3 ⚡ "Marketing changes discounts at midnight. How do you deploy that safely under load?"</b></summary>

**L5:** "Update the config object's fields."

**Why it fails:** each field update is atomic, but the set isn't. 234 k (Java) and 703 k (C++) of 3 M quotes mixed versions in the listing.

**L7 defence:**
- "Build the new rule set as an immutable object, validate it, then publish it with one atomic reference swap.
- Each request reads the reference once and stamps its version on the quote.
- In C++: an atomic pointer over versions the owner keeps alive. Rule sets are tiny, so that's the right reclamation policy; otherwise RCU."
</details>

## 11. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Totals differ by a cent between services | Different rounding points (per line vs per order) | One documented rounding policy; shared money library |
| Tax computed on gross | Decorator order set by the call site | Phases |
| Coupon stacked when it shouldn't be | Exclusivity implied in code paths | Exclusive groups as data |
| "Approved" for a fraud case | Guard placed after authority handlers | Guard first; tests per chain position |
| Refund silently approved at the end of the chain | No explicit terminal decision | Explicit end of chain |
| Quotes mixing two rule versions | Field-by-field config updates | Immutable snapshot + atomic swap |

- [ ] Strategies are stateless and selected by data.
- [ ] Adjustment order is encoded as phases; the breakdown is recorded; rounding is explicit.
- [ ] Eligibility is a specification AST with `explain()`.
- [ ] Chains have a guard first and an explicit end; chain vs pipeline is chosen deliberately.
- [ ] Rule sets are immutable, versioned, and swapped atomically.

## 12. References

- Eric Evans and Martin Fowler, "Specifications". <https://martinfowler.com/apsupp/spec.pdf>
- Gamma, Helm, Johnson, Vlissides, *Design Patterns*, 1994: Strategy, Decorator, Chain of Responsibility.
- Martin Fowler, "Replace Conditional with Polymorphism" (refactoring catalog). <https://refactoring.com/catalog/replaceConditionalWithPolymorphism.html>
- In this KB: [02.1 State machines](01-state-machines-enum-vs-sealed-types-and-optimistic-transitions.md) · [02.3 Observer, command, visitor](03-observer-event-bus-command-undo-redo-and-double-dispatch-visitor.md) · [01.2 Value objects and money](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/02-solid-composition-and-data-oriented-java21-sealed-records.md)
