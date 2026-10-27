# 02 · SOLID, Composition, and Data-Oriented Java 21/25 (with the C++23 Counterparts)

> **Folder 01 · File 2 of 3.** This file covers what object-oriented design principles protect, where they become ceremony, and how modern Java (records, sealed types, pattern matching) and modern C++ (`std::variant`, `std::expected`, concepts, `requires`) make illegal states unrepresentable. It ends with the *other* data-oriented design: memory layout.
>
> **Six listing pairs plus one compile-fail file**, each in Java and C++, all self-testing:
>
> | # | Java | C++ | Shows |
> |---|---|---|---|
> | 2.1 | `OrderStateMachine.java` | `order_state_machine.cpp` | Boolean flags vs a sealed/variant ADT; exhaustive transitions; optimistic CAS transitions |
> | 2.2 | `CompositionOverInheritance.java` | `composition_over_inheritance.cpp` | Fragile base class, LSP breaks in the JDK, diamonds, a decorator that breaks thread-safety |
> | 2.3 | `ValueObjects.java` | `value_objects.cpp` | Money, rounding, allocation, strong ids, parse-don't-validate, equality traps |
> | 2.4 | `TypestateOrders.java` (+ `TypestateMisuse.java`) | `typestate_orders.cpp` | Typestate three ways; the compiler rejecting illegal transitions |
> | 2.5 | `Java25Delta.java` | `cpp23_delta.cpp` | What Java 22–25 and C++20/23 change in LLD code; library-availability matrix |
> | 2.6 | `AosVsSoa.java` | `aos_vs_soa.cpp` | Layout: AoS vs SoA, compact object headers (JEP 519), pointer chasing |
>
> **Verified with:** JDK 25.0.4.1 (`--release 21 -Xlint:all -Werror`; listing 2.5 uses `--release 25 --enable-preview`); GCC 16.2 / libstdc++ and Clang 21.1 / libc++, `-std=c++23 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`. Deterministic outputs are **Output (verified)**; timings and race counts are **one measured run** on an i5-11260H.

---

## Contents

1. [First principles: what design is for](#1-first-principles-what-design-is-for)
2. [SOLID, reframed for Java 21/25 and C++23](#2-solid-reframed-for-java-2125-and-c23)
3. [Composition over inheritance, measured](#3-composition-over-inheritance-measured)
4. [Data-oriented programming: make illegal states unrepresentable](#4-data-oriented-programming-make-illegal-states-unrepresentable)
5. [Value objects: money, identity, parsing, equality](#5-value-objects-money-identity-parsing-equality)
6. [Typestate: moving transitions into the type checker](#6-typestate-moving-transitions-into-the-type-checker)
7. [Gang-of-Four ceremony vs modern Java vs modern C++](#7-gang-of-four-ceremony-vs-modern-java-vs-modern-c)
8. [Language deltas: Java 22–25 and C++20/23](#8-language-deltas-java-2225-and-c2023)
9. [The other "data-oriented": memory layout](#9-the-other-data-oriented-memory-layout)
10. [Failure modes](#10-failure-modes)
11. [Bar-raiser chains](#11-bar-raiser-chains)
12. [Invariants checklist](#12-invariants-checklist)
13. [References](#13-references)

---

## 1. First principles: what design is for

### 1.1 Two costs, one lever

Every design decision trades between two costs:

- **Cost of change:** how many places must be edited, and understood, to add a feature.
- **Cost of defects:** how many incorrect programs the design *permits*, and how late they are caught.

The lever on both is the same: **what the design lets a reader assume without checking.** Parnas's 1972 criterion still holds. Decompose so that each module hides a *design decision likely to change*, and expose an interface that stays stable when that decision changes. Coupling is the set of assumptions modules make about each other. Cohesion is the degree to which a module's assumptions are about one decision.

### 1.2 The expression problem: the decision behind every LLD 🔥

Any model with *kinds of things* and *operations on them* forms a matrix, and you can only make one axis cheap:

| Approach | Adding a **new kind** (row) | Adding a **new operation** (column) | Exhaustiveness checked by the compiler? |
|---|---|---|---|
| **OOP**: interface + subclasses, each implements every operation | Cheap: one new class | Expensive: edit every class | No: a missing override falls back to a default or base behaviour |
| **ADT**: `sealed` + records + `switch` (Java), `std::variant` + `std::visit` (C++) | Expensive: edit every `switch`/`visit` | Cheap: one new function | **Yes**: a missing case is a compile error |

**The L7 move is to decide, per axis, which one is open, and to say why:**

- **Pricing rules, dispatch strategies, matching policies, appenders:** new kinds arrive often (product asks for a new discount weekly), while operations are few and stable (`price()`). These are **open hierarchies**: interfaces plus strategy/decorator.
- **Order state, seat state, payment outcome, commands, events:** the set of kinds is part of the domain's *rules* and changes rarely; operations on them multiply (transition, render, persist, audit, metrics). These are **closed hierarchies**: `sealed` ADTs. When a new state *does* arrive, you *want* the build to break at every place that must decide what it means.

Sealing is therefore not "less extensible". It's **extensible along the operation axis, and checked along the kind axis**, which is exactly where defects in stateful systems come from.

### 1.3 Data vs objects: one sentence each

- **Objects** bundle state with behaviour behind an interface. Use them where *identity and lifecycle under concurrency* matter: the aggregate that owns a lock, a connection pool, a cache.
- **Data** (records, variants) is transparent, immutable and compared by value. Use it for what flows between objects: commands, events, states, results, messages, keys.

Most of the L5→L7 jump in LLD is moving things from the first category to the second. The aggregate keeps its identity and its lock, but the *state* it guards becomes data, and the *rules* become a pure function over that data. Listing 2.1 does exactly this: `Order` holds an `AtomicReference<OrderState>`, and `transition(OrderState, Command)` is pure.

---

## 2. SOLID, reframed for Java 21/25 and C++23

SOLID is valuable as a set of *questions*, and harmful as a set of *rules to maximize*. For each principle, the table gives what it actually protects, its modern idiomatic form, and the over-application that interviewers read as L5 ceremony.

| Principle | What it actually protects | Java 21/25 form | C++23 form | Over-application (reads as ceremony) | Where it appears in this KB |
|---|---|---|---|---|---|
| **S**ingle responsibility | *One reason to change = one actor who requests changes* (Martin's 2014 restatement), not "one method per class" | Separate the pure rules (`transition`) from the shell that locks, persists, notifies | Same; free functions over types are idiomatic, and not everything needs a class | A class per verb (`SeatValidator`, `SeatLocker`, `SeatPersister`) with one method each | Listing 1.1 `judge()` vs `confirm()`; Listing 2.1 `transition` vs `Order` |
| **O**pen/closed | Adding a *likely* variation shouldn't require editing stable code | Open: interfaces + lambdas for strategies. **Closed on purpose:** `sealed` for domain states | Open: concepts / virtual interfaces / `std::function`. Closed: `std::variant` | An interface for every class "in case"; plugin systems with one plugin | §1.2; Folder 02 strategy/decorator chains |
| **L**iskov substitution | A subtype must honour the supertype's *behavioural* contract (pre-conditions no stronger, post-conditions no weaker, invariants kept, history constraint) | Prefer records (final) and composition; when subtyping, test the contract on every subtype | Non-virtual "overrides" silently break LSP via static dispatch (Listing 2.2) | Deep hierarchies (`Vehicle → Car → ElectricCar → Tesla`) that differ only in data | Listing 2.2: `Stack extends Vector`, `List.of(..).add` |
| **I**nterface segregation | Clients shouldn't depend on methods they don't call, because those methods change for others' reasons | Small role interfaces; `@FunctionalInterface` is ISP taken to its limit | Concepts that require only what the template uses (`StringSet` in 2.2) | Splitting a cohesive interface into one-method shards nobody composes | Listing 2.4 step-builder interfaces `UrlStep → MethodStep → BuildStep` |
| **D**ependency inversion | Policy shouldn't depend on mechanism; both depend on an abstraction *owned by the policy* | Constructor injection of `Clock`, `Ticker`, repositories; no framework needed | Template parameter (zero-cost) or virtual interface (runtime wiring) | A DI container in a 60-minute round; interfaces with a single implementation and no test fake | Listing 1.1 `Clock`; Listing 3.7 `Ticker`, `ManualScheduler` |

Three refinements that separate L6/L7 answers:

1. **DIP is the principle behind deterministic time.** "Inject `Clock`" is dependency inversion applied to the one dependency every stateful component has and almost nobody abstracts. The interview-grade sentence: "time is an input, so I inject it."
2. **LSP is about *behaviour*, and types don't check it.** `List.of(…)` is a `List` whose `add` throws. That's legal Java and a documented "optional operation", and it's why a method accepting `List` must document whether it mutates. Records sidestep most LSP traps because they can't be extended.
3. **SRP is about *who* requests change.** The pricing team and the seat-locking code change for different people, so they belong in different modules even if each is ten lines. Two validators that always change together belong in *one* class, even if that class does two things.

---
## 3. Composition over inheritance, measured

### 3.1 Why inheritance is fragile

Implementation inheritance couples a subclass to its superclass's **self-use**: which of its own overridable methods it calls internally. That's an implementation detail, usually undocumented, and free to change between releases. Composition couples you only to the *public contract*.

Listing 2.2 measures four consequences:

1. **Java: the double count (Effective Java, Item 18).** `HashSet.addAll` is inherited from `AbstractCollection`, whose implementation calls `add()` for each element. A subclass that counts in both `add` and `addAll` counts each element twice.
2. **C++: the opposite failure.** Nothing in `std::unordered_set` is virtual, so a derived `insert` merely *hides* the base one. Any code holding a base reference (every generic algorithm) calls the base `insert` and bypasses the counter entirely. Copying into the base type *slices* the counter off.
3. **Inheritance drags in obligations.** `javac -Xlint:all` refused to compile `InstrumentedHashSet` until it declared a `serialVersionUID`. Extending `HashSet` silently made the class `Serializable`, with a serialized form you now own.
4. **A decorator inherits the thread-safety duty of what it wraps.** Wrapping `ConcurrentHashMap.newKeySet()` in a decorator with a plain `int` counter makes the *decorator* the data race.

### 3.2 Listing 2.2 (Java)

```java
// CompositionOverInheritance.java - fragile base class, LSP breaks, and composition by forwarding
import java.util.ArrayDeque;
import java.util.Collection;
import java.util.Deque;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.Stack;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.LongAdder;

public final class CompositionOverInheritance {

    // ===== 1. Fragile base class (Effective Java, Item 18) ======================================

    /** Inherits HashSet's undocumented-to-you self-use: AbstractCollection.addAll() calls add(). */
    static final class InstrumentedHashSet<E> extends HashSet<E> {
        @java.io.Serial private static final long serialVersionUID = 1L;  // HashSet made us Serializable too
        private int addCount;

        @Override public boolean add(E e) {
            addCount++;
            return super.add(e);
        }

        @Override public boolean addAll(Collection<? extends E> c) {
            addCount += c.size();
            return super.addAll(c);
        }

        int addCount() {
            return addCount;
        }
    }

    /** Forwarding: the reusable half of composition. Designed for extension; documents no self-use. */
    static class ForwardingSet<E> implements Set<E> {
        private final Set<E> s;

        ForwardingSet(Set<E> s) {
            this.s = s;
        }

        @Override public int size() { return s.size(); }
        @Override public boolean isEmpty() { return s.isEmpty(); }
        @Override public boolean contains(Object o) { return s.contains(o); }
        @Override public Iterator<E> iterator() { return s.iterator(); }
        @Override public Object[] toArray() { return s.toArray(); }
        @Override public <T> T[] toArray(T[] a) { return s.toArray(a); }
        @Override public boolean add(E e) { return s.add(e); }
        @Override public boolean remove(Object o) { return s.remove(o); }
        @Override public boolean containsAll(Collection<?> c) { return s.containsAll(c); }
        @Override public boolean addAll(Collection<? extends E> c) { return s.addAll(c); }
        @Override public boolean retainAll(Collection<?> c) { return s.retainAll(c); }
        @Override public boolean removeAll(Collection<?> c) { return s.removeAll(c); }
        @Override public void clear() { s.clear(); }
        @Override public boolean equals(Object o) { return s.equals(o); }
        @Override public int hashCode() { return s.hashCode(); }
        @Override public String toString() { return s.toString(); }
    }

    /** Composition: wraps ANY Set (HashSet, TreeSet, a concurrent key set) -- inheritance can't. */
    static final class InstrumentedSet<E> extends ForwardingSet<E> {
        private int addCount;                       // fine for a confined set, wrong for a shared one

        InstrumentedSet(Set<E> s) {
            super(s);
        }

        @Override public boolean add(E e) {
            addCount++;
            return super.add(e);
        }

        @Override public boolean addAll(Collection<? extends E> c) {
            addCount += c.size();
            return super.addAll(c);
        }

        int addCount() {
            return addCount;
        }
    }

    /** The decorator inherits the thread-safety duty of what it wraps. */
    static final class ConcurrentInstrumentedSet<E> extends ForwardingSet<E> {
        private final LongAdder addCount = new LongAdder();

        ConcurrentInstrumentedSet(Set<E> s) {
            super(s);
        }

        @Override public boolean add(E e) {
            addCount.increment();
            return super.add(e);
        }

        @Override public boolean addAll(Collection<? extends E> c) {
            addCount.add(c.size());
            return super.addAll(c);
        }

        long addCount() {
            return addCount.sum();
        }
    }

    // ===== 2. Default-method diamond: the compiler forces an explicit choice ====================

    interface Auditable {
        default String tag() { return "audit"; }
    }

    interface Cacheable {
        default String tag() { return "cache"; }
    }

    static final class Repo implements Auditable, Cacheable {
        @Override public String tag() {             // omit this and javac rejects the class
            return Auditable.super.tag() + "+" + Cacheable.super.tag();
        }
    }

    // ===== 3. Records cannot be extended: Square/Rectangle is solved by composition =============

    record Rect(int w, int h) {
        int area() { return w * h; }
    }

    record Square(int side) {
        Rect asRect() { return new Rect(side, side); }  // a view, not a subtype: no LSP trap
    }

    static int lostIncrements(int threads, int perThread, boolean safe) throws InterruptedException {
        Set<Integer> inner = ConcurrentHashMap.newKeySet();
        InstrumentedSet<Integer> plain = new InstrumentedSet<>(inner);
        ConcurrentInstrumentedSet<Integer> adder = new ConcurrentInstrumentedSet<>(inner);
        CountDownLatch start = new CountDownLatch(1);
        Thread[] ts = new Thread[threads];
        for (int t = 0; t < threads; t++) {
            final int base = t * perThread;
            ts[t] = Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return;
                }
                for (int i = 0; i < perThread; i++) {
                    if (safe) adder.add(base + i);
                    else plain.add(base + i);
                }
            });
        }
        start.countDown();
        for (Thread t : ts) t.join();
        long counted = safe ? adder.addCount() : plain.addCount();
        if (inner.size() != threads * perThread) throw new AssertionError("inner set lost elements");
        return (int) (threads * perThread - counted);
    }

    public static void main(String[] args) throws InterruptedException {
        List<String> three = List.of("Snap", "Crackle", "Pop");

        System.out.println("== 1. Fragile base class ==");
        InstrumentedHashSet<String> inherited = new InstrumentedHashSet<>();
        inherited.addAll(three);
        System.out.println("InstrumentedHashSet.addAll(3 items) -> addCount = " + inherited.addCount());
        InstrumentedSet<String> composed = new InstrumentedSet<>(new HashSet<>());
        composed.addAll(three);
        System.out.println("InstrumentedSet(HashSet).addAll(3)  -> addCount = " + composed.addCount());
        InstrumentedSet<String> sorted = new InstrumentedSet<>(new TreeSet<>());
        sorted.addAll(three);
        System.out.println("InstrumentedSet(TreeSet).addAll(3)  -> addCount = " + sorted.addCount() + " " + sorted);

        System.out.println("== 2. LSP breaks shipped in the JDK ==");
        Stack<String> stack = new Stack<>();              // Stack extends Vector: inherits index access
        stack.push("a");
        stack.push("b");
        stack.add(0, "z");                                // legal through the Vector API
        System.out.println("Stack after push(a), push(b), add(0,z): " + stack + " -> pop()=" + stack.pop() + ", bottom=" + stack.get(0));
        Deque<String> deque = new ArrayDeque<>();         // the replacement exposes no index insertion
        deque.push("a");
        deque.push("b");
        System.out.println("ArrayDeque push(a), push(b) -> pop()=" + deque.pop());
        try {
            List<String> fixed = List.of("x");
            fixed.add("y");
        } catch (UnsupportedOperationException e) {
            System.out.println("List.of(x).add(y) -> UnsupportedOperationException (an 'optional operation')");
        }

        System.out.println("== 3. Diamond + records ==");
        System.out.println("Repo.tag() = " + new Repo().tag());
        System.out.println("Square(4).asRect().area() = " + new Square(4).asRect().area());

        System.out.println("== 4. A decorator inherits the thread-safety duty of what it wraps ==");
        int lostPlain = lostIncrements(4, 250_000, false);
        int lostAdder = lostIncrements(4, 250_000, true);
        System.out.printf("4 threads x 250,000 distinct adds into ConcurrentHashMap.newKeySet()%n");
        System.out.printf("  int addCount       : lost %,d increments (set itself kept all 1,000,000)%n", lostPlain);
        System.out.printf("  LongAdder addCount : lost %,d increments%n", lostAdder);

        boolean ok = inherited.addCount() == 6 && composed.addCount() == 3 && sorted.addCount() == 3 && lostAdder == 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (verified, except the lost-increment count, which is one measured run):**

```text
== 1. Fragile base class ==
InstrumentedHashSet.addAll(3 items) -> addCount = 6
InstrumentedSet(HashSet).addAll(3)  -> addCount = 3
InstrumentedSet(TreeSet).addAll(3)  -> addCount = 3 [Crackle, Pop, Snap]
== 2. LSP breaks shipped in the JDK ==
Stack after push(a), push(b), add(0,z): [z, a, b] -> pop()=b, bottom=z
ArrayDeque push(a), push(b) -> pop()=b
List.of(x).add(y) -> UnsupportedOperationException (an 'optional operation')
== 3. Diamond + records ==
Repo.tag() = audit+cache
Square(4).asRect().area() = 16
== 4. A decorator inherits the thread-safety duty of what it wraps ==
4 threads x 250,000 distinct adds into ConcurrentHashMap.newKeySet()
  int addCount       : lost 394,625 increments (set itself kept all 1,000,000)
  LongAdder addCount : lost 0 increments
SELF-TEST OK
```

### 3.3 Listing 2.2 (C++)

```cpp
// composition_over_inheritance.cpp - non-virtual "overrides", slicing, diamonds, and composition by forwarding
#include <atomic>
#include <concepts>
#include <cstddef>
#include <latch>
#include <mutex>
#include <print>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

// ===== 1. Inheriting from a std container: the "override" is only name hiding ===============

struct CountingSet : std::unordered_set<std::string> {  // public inheritance from a non-polymorphic type
    std::size_t adds = 0;
    auto insert(const std::string& v) {                  // hides the base insert; nothing is virtual
        ++adds;
        return std::unordered_set<std::string>::insert(v);
    }
};

void add_all(std::unordered_set<std::string>& s, const std::vector<std::string>& items) {
    for (const auto& x : items) s.insert(x);             // static dispatch: calls the BASE insert
}

// ===== 2. Composition: a decorator over any set-like type, checked by a concept ==============

template <class S>
concept StringSet = requires(S s, const std::string& v) {
    { s.insert(v) };
    { s.size() } -> std::convertible_to<std::size_t>;
};

template <StringSet Inner>
class InstrumentedSet {
    Inner inner_;
    std::size_t adds_ = 0;  // fine for a confined set
public:
    bool insert(const std::string& v) {
        ++adds_;
        return inner_.insert(v).second;
    }
    void insert_all(const std::vector<std::string>& items) {
        for (const auto& x : items) insert(x);
    }
    std::size_t adds() const { return adds_; }
    std::size_t size() const { return inner_.size(); }
};

// ===== 3. Diamond: the C++ spelling of Java's Auditable.super.tag() =========================

struct Auditable {
    virtual ~Auditable() = default;
    virtual std::string tag() const { return "audit"; }
};
struct Cacheable {
    virtual ~Cacheable() = default;
    virtual std::string tag() const { return "cache"; }
};
struct Repo final : Auditable, Cacheable {
    std::string tag() const override { return Auditable::tag() + "+" + Cacheable::tag(); }
};

// ===== 4. A decorator inherits the thread-safety duty of what it wraps =======================

class LockedSet {  // the thread-safe inner set
    mutable std::mutex m_;
    std::unordered_set<int> s_;
public:
    bool insert(int v) {
        std::scoped_lock lock(m_);
        return s_.insert(v).second;
    }
    std::size_t size() const {
        std::scoped_lock lock(m_);
        return s_.size();
    }
};

/**
 * In C++ the Java bug (a plain int++ shared by threads) is a data race, i.e. undefined behaviour,
 * so it cannot be "measured". A relaxed load followed by a separate store reproduces the same
 * lost-update interleaving with defined behaviour.
 */
template <bool kSafe>
class CountingDecorator {
    LockedSet& inner_;
    std::atomic<std::size_t> adds_{0};
public:
    explicit CountingDecorator(LockedSet& inner) : inner_(inner) {}
    bool insert(int v) {
        if constexpr (kSafe) {
            adds_.fetch_add(1, std::memory_order_relaxed);  // one atomic read-modify-write
        } else {
            adds_.store(adds_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);  // read, then write
        }
        return inner_.insert(v);
    }
    std::size_t adds() const { return adds_.load(); }
};

template <bool kSafe>
std::size_t lost_increments(int threads, int per_thread) {
    LockedSet inner;
    CountingDecorator<kSafe> deco(inner);
    std::latch start(1);
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t) {
        ts.emplace_back([&, base = t * per_thread] {
            start.wait();
            for (int i = 0; i < per_thread; ++i) deco.insert(base + i);
        });
    }
    start.count_down();
    ts.clear();  // jthread joins on destruction
    const auto expected = static_cast<std::size_t>(threads) * static_cast<std::size_t>(per_thread);
    if (inner.size() != expected) throw std::logic_error("inner set lost elements");
    return expected - deco.adds();
}

int main() {
    const std::vector<std::string> three = {"Snap", "Crackle", "Pop"};

    std::println("== 1. Inheriting from std::unordered_set ==");
    CountingSet counting;
    add_all(counting, three);
    std::println("add_all(CountingSet&, 3 items) through a base reference -> adds = {} (size = {})", counting.adds,
                 counting.size());
    std::unordered_set<std::string> sliced = counting;  // slicing: the copy silently drops `adds`
    std::println("copy into the base type keeps {} elements and no counter", sliced.size());

    std::println("== 2. Composition ==");
    InstrumentedSet<std::unordered_set<std::string>> hashed;
    hashed.insert_all(three);
    InstrumentedSet<std::set<std::string>> ordered;
    ordered.insert_all(three);
    std::println("InstrumentedSet<unordered_set>.insert_all(3) -> adds = {}", hashed.adds());
    std::println("InstrumentedSet<set>.insert_all(3)           -> adds = {}", ordered.adds());

    std::println("== 3. Diamond ==");
    std::println("Repo.tag() = {}", Repo{}.tag());

    std::println("== 4. Decorating a thread-safe set ==");
    const auto lost_plain = lost_increments<false>(4, 250'000);
    const auto lost_atomic = lost_increments<true>(4, 250'000);
    std::println("4 threads x 250,000 distinct inserts into a mutex-guarded set");
    std::println("  load-then-store counter : lost {} increments (set itself kept all 1,000,000)", lost_plain);
    std::println("  fetch_add counter       : lost {} increments", lost_atomic);

    const bool ok = counting.adds == 0 && hashed.adds() == 3 && ordered.adds() == 3 && lost_atomic == 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2 (lost-increment count: one measured run; Clang lost 15 in its run):**

```text
== 1. Inheriting from std::unordered_set ==
add_all(CountingSet&, 3 items) through a base reference -> adds = 0 (size = 3)
copy into the base type keeps 3 elements and no counter
== 2. Composition ==
InstrumentedSet<unordered_set>.insert_all(3) -> adds = 3
InstrumentedSet<set>.insert_all(3)           -> adds = 3
== 3. Diamond ==
Repo.tag() = audit+cache
== 4. Decorating a thread-safe set ==
4 threads x 250,000 distinct inserts into a mutex-guarded set
  load-then-store counter : lost 99 increments (set itself kept all 1,000,000)
  fetch_add counter       : lost 0 increments
SELF-TEST OK
```

### 3.4 What the numbers say

| Effect | Java | C++ | Lesson |
|---|---|---|---|
| Inherit + override `add`/`addAll` | **6** counted for 3 adds (self-use) | **0** counted for 3 inserts through a base reference (static dispatch) | Inheriting from a class not designed for it fails *in both directions* |
| Compose + forward | 3, for both `HashSet` and `TreeSet` | 3, for both `unordered_set` and `set` | Composition works over *any* implementation of the contract |
| Decorator with a non-atomic counter over a concurrent set | **394,625** of 1,000,000 increments lost | 99 lost (GCC), 15 (Clang) | The decorator becomes the weakest link. C++ loses fewer only because the inner mutex serializes threads and shrinks the race window |
| Decorator with `LongAdder` / `fetch_add` | 0 lost | 0 lost | The counter must be at least as concurrent as what it decorates |

Two C++-specific notes belong in an interview answer:

- **The Java bug can't legally be written in C++.** An unsynchronized `int++` shared between threads is a data race, which is *undefined behaviour*. The compiler may assume it never happens. To *measure* lost updates without UB, the listing uses a relaxed atomic load followed by a separate store: the same interleaving, defined behaviour.
- **Deleting a derived object through a base pointer without a virtual destructor is UB.** `std::` containers have none, which is the strongest reason never to inherit from them publicly.

### 3.5 When inheritance *is* right

- The base class is **designed and documented for extension**: `AbstractSet`/`AbstractList` (their self-use is documented in their Javadoc), `ForwardingSet` above, or a template method whose hooks are the documented extension surface.
- The hierarchy is **sealed**, and subclasses differ in *behaviour* that the supertype's contract fully specifies.
- You need **substitutability across a module boundary** that you also control (both sides can be changed together).

Everywhere else, prefer: interface + composition (Java), concept + composition or type erasure (C++).

---

## 4. Data-oriented programming: make illegal states unrepresentable

### 4.1 The principles (Goetz, 2022)

Brian Goetz's statement of data-oriented programming in Java has four rules. Each one maps to a C++ idiom:

| Principle | Java mechanism | C++ mechanism |
|---|---|---|
| Model the data, the whole data, and nothing but the data | `record` components = exactly the state | aggregates / structs with no invariant-free setters |
| Data is immutable | records are shallowly immutable; copy collections in the compact constructor | `const` members or value semantics + no mutating API |
| Validate at the boundary | compact constructor / static factory returning a result | constructor that throws, or a factory returning `std::expected` |
| Make illegal states unrepresentable | `sealed` interface + records, each carrying only its own data | `std::variant` of structs, each carrying only its own data |

### 4.2 Counting what the flag model fails to forbid 🔥

Listing 2.1 starts by *enumerating* the boolean model. Four flags (`isAuthorized`, `isPaid`, `isCancelled`, `isRefunded`) give 16 combinations, and only 6 are reachable by legal transitions. Add three nullable ids (`authId`, `captureId`, `refundId`), each null or non-null, and the type admits **128 shapes for 6 legal states**. The sealed model has exactly **6 shapes**: five records, with `Cancelled` carrying a two-way `CancelPoint`. That matches the 6 legal states one-to-one. **The type *is* the state diagram.**

### 4.3 Listing 2.1 (Java)

```java
// OrderStateMachine.java - boolean flags vs a sealed state ADT for an order's payment lifecycle
import java.util.ArrayList;
import java.util.ArrayDeque;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

public final class OrderStateMachine {

    // ===== L5: four booleans and three nullable ids ===========================================

    static final int AUTHORIZED = 1, PAID = 2, CANCELLED = 4, REFUNDED = 8;
    static final String[] FLAG_NAMES = {"isAuthorized", "isPaid", "isCancelled", "isRefunded"};

    /** The flag model's legal moves, written down so we can count what the type fails to forbid. */
    static List<Integer> flagMoves(int m) {
        List<Integer> next = new ArrayList<>();
        if (m == 0) next.add(AUTHORIZED);                           // authorize
        if (m == AUTHORIZED) next.add(AUTHORIZED | PAID);           // capture
        if (m == 0) next.add(CANCELLED);                            // cancel before auth
        if (m == AUTHORIZED) next.add(AUTHORIZED | CANCELLED);      // cancel = void the auth
        if (m == (AUTHORIZED | PAID)) next.add(AUTHORIZED | PAID | REFUNDED);  // refund
        return next;
    }

    static String flags(int m) {
        List<String> on = new ArrayList<>();
        for (int i = 0; i < 4; i++) if ((m & (1 << i)) != 0) on.add(FLAG_NAMES[i]);
        return on.isEmpty() ? "{}" : "{" + String.join(",", on) + "}";
    }

    // ===== L7: value objects + a sealed state ADT ============================================

    record OrderId(String value) {
        OrderId {
            Objects.requireNonNull(value, "value");
            if (value.isBlank()) throw new IllegalArgumentException("blank order id");
        }
    }

    record Money(long cents) {
        Money {
            if (cents < 0) throw new IllegalArgumentException("negative money: " + cents);
        }
        boolean exceeds(Money o) {
            return cents > o.cents;
        }
    }

    /** How a cancellation happened is data, not a nullable field. */
    sealed interface CancelPoint permits BeforeAuthorization, AuthorizationVoided {}
    record BeforeAuthorization() implements CancelPoint {}
    record AuthorizationVoided(String authId) implements CancelPoint {}

    sealed interface OrderState permits Created, Authorized, Captured, Cancelled, Refunded {
        OrderId id();
    }
    record Created(OrderId id, Money total) implements OrderState {}
    record Authorized(OrderId id, Money total, String authId) implements OrderState {}
    record Captured(OrderId id, Money total, String authId, String captureId, Money captured) implements OrderState {
        Captured {
            if (captured.exceeds(total)) throw new IllegalArgumentException("capture exceeds total");
        }
    }
    record Cancelled(OrderId id, String reason, CancelPoint at) implements OrderState {}
    record Refunded(OrderId id, String captureId, String refundId, Money refunded) implements OrderState {}

    sealed interface Command permits Authorize, Capture, Cancel, Refund {}
    record Authorize(String authId) implements Command {}
    record Capture(String captureId, Money amount) implements Command {}
    record Cancel(String reason) implements Command {}
    record Refund(String refundId, Money amount) implements Command {}

    sealed interface Result<T> permits Ok, Err {}
    record Ok<T>(T value) implements Result<T> {}
    record Err<T>(String code, String detail) implements Result<T> {}

    static Result<OrderState> ok(OrderState s) {
        return new Ok<>(s);
    }

    static Result<OrderState> err(String code, String detail) {
        return new Err<>(code, detail);
    }

    static Result<OrderState> illegal(OrderState s, Command c) {
        return err("ILLEGAL_TRANSITION", s.getClass().getSimpleName() + " + " + c.getClass().getSimpleName());
    }

    /**
     * The whole state machine. Nested exhaustive switches, no default anywhere: adding a sixth state
     * or a fifth command fails compilation until every (state, command) pair is decided.
     */
    static Result<OrderState> transition(OrderState state, Command cmd) {
        return switch (state) {
            case Created c -> switch (cmd) {
                case Authorize a -> ok(new Authorized(c.id(), c.total(), a.authId()));
                case Cancel x -> ok(new Cancelled(c.id(), x.reason(), new BeforeAuthorization()));
                case Capture cp -> illegal(state, cmd);
                case Refund r -> illegal(state, cmd);
            };
            case Authorized au -> switch (cmd) {
                case Authorize a when a.authId().equals(au.authId()) -> ok(au);     // idempotent replay
                case Authorize a -> err("ALREADY_AUTHORIZED", au.authId());
                case Capture cp when cp.amount().exceeds(au.total()) -> err("CAPTURE_EXCEEDS_AUTH", cp.amount() + " > " + au.total());
                case Capture cp -> ok(new Captured(au.id(), au.total(), au.authId(), cp.captureId(), cp.amount()));
                case Cancel x -> ok(new Cancelled(au.id(), x.reason(), new AuthorizationVoided(au.authId())));
                case Refund r -> illegal(state, cmd);
            };
            case Captured ca -> switch (cmd) {
                case Capture cp when cp.captureId().equals(ca.captureId()) -> ok(ca); // idempotent replay
                case Refund r when r.amount().exceeds(ca.captured()) -> err("REFUND_EXCEEDS_CAPTURE", r.amount() + " > " + ca.captured());
                case Refund r -> ok(new Refunded(ca.id(), ca.captureId(), r.refundId(), r.amount()));
                case Cancel x -> err("CAPTURED_USE_REFUND", "cancel after capture must be a refund");
                case Authorize a -> illegal(state, cmd);
                case Capture cp -> illegal(state, cmd);
            };
            case Cancelled cn -> illegal(state, cmd);   // terminal
            case Refunded rf -> illegal(state, cmd);    // terminal
        };
    }

    /** Aggregate with optimistic transitions: transition() is pure, so a lost CAS can simply retry. */
    static final class Order {
        private final AtomicReference<OrderState> state;

        Order(OrderState initial) {
            state = new AtomicReference<>(initial);
        }

        Result<OrderState> handle(Command cmd) {
            while (true) {
                OrderState prev = state.get();
                Result<OrderState> r = transition(prev, cmd);
                if (!(r instanceof Ok<OrderState>(OrderState next))) return r;      // record pattern
                if (next == prev || state.compareAndSet(prev, next)) return r;  // identity CAS on the object we read
            }
        }

        OrderState current() {
            return state.get();
        }
    }

    static String show(Result<OrderState> r) {
        return switch (r) {
            case Ok<OrderState> ok -> ok.value().getClass().getSimpleName();
            case Err<OrderState> e -> "x " + e.code();
        };
    }

    public static void main(String[] args) throws Exception {
        // ---- 1. What the flag model fails to forbid ----
        Set<Integer> reachable = new LinkedHashSet<>();
        ArrayDeque<Integer> todo = new ArrayDeque<>(List.of(0));
        while (!todo.isEmpty()) {
            int m = todo.poll();
            if (reachable.add(m)) todo.addAll(flagMoves(m));
        }
        List<String> illegal = new ArrayList<>();
        for (int m = 0; m < 16; m++) if (!reachable.contains(m)) illegal.add(flags(m));
        System.out.println("== Flag model ==");
        System.out.println("representable flag combinations : 16");
        System.out.println("reachable by legal transitions  : " + reachable.size() + " " + reachable.stream().map(OrderStateMachine::flags).toList());
        System.out.println("representable but illegal       : " + illegal.size());
        System.out.println("  e.g. " + illegal.subList(0, 4));
        System.out.println("with 3 nullable ids (x8 shapes) : " + 16 * 8 + " representable, " + reachable.size() + " legal");
        System.out.println("sealed ADT shapes               : 6 (Created, Authorized, Captured, Cancelled x2 CancelPoints, Refunded)");

        // ---- 2. The full transition table, every pair decided ----
        OrderId id = new OrderId("o-1");
        Money total = new Money(10_000);
        List<OrderState> states = List.of(
                new Created(id, total),
                new Authorized(id, total, "auth-1"),
                new Captured(id, total, "auth-1", "cap-1", total),
                new Cancelled(id, "user", new BeforeAuthorization()),
                new Refunded(id, "cap-1", "ref-1", total));
        List<Command> cmds = List.of(new Authorize("auth-1"), new Capture("cap-1", total), new Cancel("user"), new Refund("ref-1", total));
        System.out.println("== Transition table (state x command -> next state | x error) ==");
        System.out.println(String.format("%-11s %-22s %-22s %-22s %-22s", "", "Authorize(auth-1)",
                "Capture(cap-1,100.00)", "Cancel", "Refund(100.00)").stripTrailing());
        for (OrderState s : states) {
            StringBuilder row = new StringBuilder(String.format("%-11s", s.getClass().getSimpleName()));
            for (Command c : cmds) row.append(String.format(" %-22s", show(transition(s, c))));
            System.out.println(row.toString().stripTrailing());
        }
        System.out.println("guarded: Authorized + Capture(150.00) -> " + show(transition(states.get(1), new Capture("cap-9", new Money(15_000)))));
        System.out.println("guarded: Authorized + Authorize(auth-2) -> " + show(transition(states.get(1), new Authorize("auth-2"))));
        try {
            new Captured(id, total, "auth-1", "cap-1", new Money(20_000));
        } catch (IllegalArgumentException e) {
            System.out.println("record invariant: new Captured(total=100.00, captured=200.00) -> " + e.getMessage());
        }

        // ---- 3. Optimistic transitions: capture webhook races a user cancel, 20,000 times ----
        int trials = 20_000, captureWon = 0, cancelWon = 0, bothWon = 0;
        for (int t = 0; t < trials; t++) {
            Order order = new Order(new Authorized(id, total, "auth-1"));
            AtomicInteger gate = new AtomicInteger();
            AtomicReference<Result<OrderState>> a = new AtomicReference<>(), b = new AtomicReference<>();
            Thread t1 = Thread.ofPlatform().start(() -> {
                gate.incrementAndGet();
                while (gate.get() < 2) Thread.onSpinWait();
                a.set(order.handle(new Capture("cap-1", total)));
            });
            Thread t2 = Thread.ofPlatform().start(() -> {
                gate.incrementAndGet();
                while (gate.get() < 2) Thread.onSpinWait();
                b.set(order.handle(new Cancel("user changed mind")));
            });
            t1.join();
            t2.join();
            boolean capOk = a.get() instanceof Ok<OrderState>, canOk = b.get() instanceof Ok<OrderState>;
            if (capOk && canOk) bothWon++;
            else if (capOk) captureWon++;
            else if (canOk) cancelWon++;
            boolean consistent = capOk ? order.current() instanceof Captured : order.current() instanceof Cancelled;
            if (!consistent) throw new AssertionError("final state disagrees with winner: " + order.current());
        }
        System.out.println("== Capture vs Cancel race, " + trials + " trials ==");
        System.out.printf("capture won %,d | cancel won %,d | both won %d (must be 0)%n", captureWon, cancelWon, bothWon);
        if (bothWon != 0 || captureWon + cancelWon != trials) throw new AssertionError("race invariant broken");
        System.out.println("SELF-TEST OK");
    }
}
```

**Output (verified; the race split is one measured run, while "both won 0" is guaranteed):**

```text
== Flag model ==
representable flag combinations : 16
reachable by legal transitions  : 6 [{}, {isAuthorized}, {isCancelled}, {isAuthorized,isPaid}, {isAuthorized,isCancelled}, {isAuthorized,isPaid,isRefunded}]
representable but illegal       : 10
  e.g. [{isPaid}, {isPaid,isCancelled}, {isAuthorized,isPaid,isCancelled}, {isRefunded}]
with 3 nullable ids (x8 shapes) : 128 representable, 6 legal
sealed ADT shapes               : 6 (Created, Authorized, Captured, Cancelled x2 CancelPoints, Refunded)
== Transition table (state x command -> next state | x error) ==
            Authorize(auth-1)      Capture(cap-1,100.00)  Cancel                 Refund(100.00)
Created     Authorized             x ILLEGAL_TRANSITION   Cancelled              x ILLEGAL_TRANSITION
Authorized  Authorized             Captured               Cancelled              x ILLEGAL_TRANSITION
Captured    x ILLEGAL_TRANSITION   Captured               x CAPTURED_USE_REFUND  Refunded
Cancelled   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION
Refunded    x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION
guarded: Authorized + Capture(150.00) -> x CAPTURE_EXCEEDS_AUTH
guarded: Authorized + Authorize(auth-2) -> x ALREADY_AUTHORIZED
record invariant: new Captured(total=100.00, captured=200.00) -> capture exceeds total
== Capture vs Cancel race, 20000 trials ==
capture won 9,642 | cancel won 10,358 | both won 0 (must be 0)
SELF-TEST OK
```

### 4.4 Listing 2.1 (C++)

```cpp
// order_state_machine.cpp - boolean flags vs a std::variant state ADT for an order's payment lifecycle
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <deque>
#include <expected>
#include <format>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

// ===== L5: four booleans and three nullable ids ==============================================

constexpr int kAuthorized = 1, kPaid = 2, kCancelled = 4, kRefunded = 8;
constexpr const char* kFlagNames[] = {"isAuthorized", "isPaid", "isCancelled", "isRefunded"};

std::vector<int> flag_moves(int m) {  // the flag model's legal moves
    std::vector<int> next;
    if (m == 0) next.push_back(kAuthorized);
    if (m == kAuthorized) next.push_back(kAuthorized | kPaid);
    if (m == 0) next.push_back(kCancelled);
    if (m == kAuthorized) next.push_back(kAuthorized | kCancelled);
    if (m == (kAuthorized | kPaid)) next.push_back(kAuthorized | kPaid | kRefunded);
    return next;
}

std::string flags(int m) {
    std::string s;
    for (int i = 0; i < 4; ++i)
        if (m & (1 << i)) s += (s.empty() ? "" : ",") + std::string(kFlagNames[i]);
    return "{" + s + "}";
}

// ===== L7: value objects + a variant state ADT ==============================================

struct OrderId {
    std::string value;
    explicit OrderId(std::string v) : value(std::move(v)) {
        if (value.empty()) throw std::invalid_argument("blank order id");
    }
};

struct Money {
    std::int64_t cents;
    explicit Money(std::int64_t c) : cents(c) {
        if (c < 0) throw std::invalid_argument("negative money");
    }
    bool exceeds(Money o) const { return cents > o.cents; }
};

struct BeforeAuthorization {};
struct AuthorizationVoided { std::string auth_id; };
using CancelPoint = std::variant<BeforeAuthorization, AuthorizationVoided>;  // how, as data

struct Created { OrderId id; Money total; };
struct Authorized { OrderId id; Money total; std::string auth_id; };
struct Captured {
    OrderId id;
    Money total;
    std::string auth_id, capture_id;
    Money captured;
    Captured(OrderId i, Money t, std::string a, std::string c, Money cap)
        : id(std::move(i)), total(t), auth_id(std::move(a)), capture_id(std::move(c)), captured(cap) {
        if (captured.exceeds(total)) throw std::invalid_argument("capture exceeds total");
    }
};
struct Cancelled { OrderId id; std::string reason; CancelPoint at; };
struct Refunded { OrderId id; std::string capture_id, refund_id; Money refunded; };
using OrderState = std::variant<Created, Authorized, Captured, Cancelled, Refunded>;
constexpr const char* kStateNames[] = {"Created", "Authorized", "Captured", "Cancelled", "Refunded"};

struct Authorize { std::string auth_id; };
struct Capture { std::string capture_id; Money amount; };
struct Cancel { std::string reason; };
struct Refund { std::string refund_id; Money amount; };
using Command = std::variant<Authorize, Capture, Cancel, Refund>;
constexpr const char* kCommandNames[] = {"Authorize", "Capture", "Cancel", "Refund"};

struct TransitionError { std::string code, detail; };
using Result = std::expected<OrderState, TransitionError>;

Result err(std::string code, std::string detail) { return std::unexpected(TransitionError{std::move(code), std::move(detail)}); }

/** Nested exhaustive visits: a 6th state or a 5th command does not compile until every pair is decided. */
// Named transition, not apply: with std::variant arguments, ADL would also find std::apply.
Result transition(const OrderState& state, const Command& cmd) {
    auto illegal = [&] {
        return err("ILLEGAL_TRANSITION", std::string(kStateNames[state.index()]) + " + " + kCommandNames[cmd.index()]);
    };
    return std::visit(overloaded{
        [&](const Created& c) -> Result {
            return std::visit(overloaded{
                [&](const Authorize& a) -> Result { return Authorized{c.id, c.total, a.auth_id}; },
                [&](const Cancel& x) -> Result { return Cancelled{c.id, x.reason, BeforeAuthorization{}}; },
                [&](const Capture&) -> Result { return illegal(); },
                [&](const Refund&) -> Result { return illegal(); },
            }, cmd);
        },
        [&](const Authorized& au) -> Result {
            return std::visit(overloaded{
                [&](const Authorize& a) -> Result {
                    if (a.auth_id == au.auth_id) return au;  // idempotent replay
                    return err("ALREADY_AUTHORIZED", au.auth_id);
                },
                [&](const Capture& cp) -> Result {
                    if (cp.amount.exceeds(au.total)) return err("CAPTURE_EXCEEDS_AUTH", "");
                    return Captured(au.id, au.total, au.auth_id, cp.capture_id, cp.amount);
                },
                [&](const Cancel& x) -> Result { return Cancelled{au.id, x.reason, AuthorizationVoided{au.auth_id}}; },
                [&](const Refund&) -> Result { return illegal(); },
            }, cmd);
        },
        [&](const Captured& ca) -> Result {
            return std::visit(overloaded{
                [&](const Capture& cp) -> Result {
                    if (cp.capture_id == ca.capture_id) return ca;  // idempotent replay
                    return illegal();
                },
                [&](const Refund& r) -> Result {
                    if (r.amount.exceeds(ca.captured)) return err("REFUND_EXCEEDS_CAPTURE", "");
                    return Refunded{ca.id, ca.capture_id, r.refund_id, r.amount};
                },
                [&](const Cancel&) -> Result { return err("CAPTURED_USE_REFUND", "cancel after capture must be a refund"); },
                [&](const Authorize&) -> Result { return illegal(); },
            }, cmd);
        },
        [&](const Cancelled&) -> Result { return illegal(); },  // terminal
        [&](const Refunded&) -> Result { return illegal(); },   // terminal
    }, state);
}

/** Aggregate with optimistic transitions where the library has atomic<shared_ptr>; a mutex otherwise. */
class Order {
#if defined(__cpp_lib_atomic_shared_ptr)
    std::atomic<std::shared_ptr<const OrderState>> state_;
#else
    mutable std::mutex m_;
    std::shared_ptr<const OrderState> state_;
#endif
public:
    explicit Order(OrderState initial) : state_(std::make_shared<const OrderState>(std::move(initial))) {}

    Result handle(const Command& cmd) {
#if defined(__cpp_lib_atomic_shared_ptr)
        auto prev = state_.load();
        while (true) {
            Result r = transition(*prev, cmd);
            if (!r) return r;
            auto next = std::make_shared<const OrderState>(*r);
            if (state_.compare_exchange_weak(prev, next)) return r;  // on failure prev is reloaded
        }
#else
        std::scoped_lock lock(m_);
        Result r = transition(*state_, cmd);
        if (r) state_ = std::make_shared<const OrderState>(*r);
        return r;
#endif
    }

    std::size_t current_index() const {
#if defined(__cpp_lib_atomic_shared_ptr)
        return state_.load()->index();
#else
        std::scoped_lock lock(m_);
        return state_->index();
#endif
    }
};

std::string show(const Result& r) { return r ? kStateNames[r->index()] : "x " + r.error().code; }

int main() {
    // ---- 1. What the flag model fails to forbid ----
    std::vector<int> reachable;
    std::deque<int> todo{0};
    while (!todo.empty()) {
        const int m = todo.front();
        todo.pop_front();
        if (std::ranges::find(reachable, m) != reachable.end()) continue;
        reachable.push_back(m);
        for (int n : flag_moves(m)) todo.push_back(n);
    }
    std::vector<std::string> illegal_combos;
    for (int m = 0; m < 16; ++m)
        if (std::ranges::find(reachable, m) == reachable.end()) illegal_combos.push_back(flags(m));
    std::string reach;
    for (int m : reachable) reach += (reach.empty() ? "" : ", ") + flags(m);
    std::println("== Flag model ==");
    std::println("representable flag combinations : 16");
    std::println("reachable by legal transitions  : {} [{}]", reachable.size(), reach);
    std::println("representable but illegal       : {}", illegal_combos.size());
    std::println("  e.g. [{}, {}, {}, {}]", illegal_combos[0], illegal_combos[1], illegal_combos[2], illegal_combos[3]);
    std::println("with 3 nullable ids (x8 shapes) : {} representable, {} legal", 16 * 8, reachable.size());
    std::println("variant ADT shapes              : 6 (Created, Authorized, Captured, Cancelled x2 CancelPoints, Refunded)");

    // ---- 2. The full transition table ----
    const OrderId id{"o-1"};
    const Money total{10'000};
    const std::vector<OrderState> states = {
        Created{id, total},
        Authorized{id, total, "auth-1"},
        Captured(id, total, "auth-1", "cap-1", total),
        Cancelled{id, "user", BeforeAuthorization{}},
        Refunded{id, "cap-1", "ref-1", total},
    };
    const std::vector<Command> cmds = {Authorize{"auth-1"}, Capture{"cap-1", total}, Cancel{"user"}, Refund{"ref-1", total}};
    std::println("== Transition table (state x command -> next state | x error) ==");
    std::println("{:<11} {:<22} {:<22} {:<22} {}", "", "Authorize(auth-1)", "Capture(cap-1,100.00)", "Cancel", "Refund(100.00)");
    for (const auto& s : states) {
        std::string row = std::format("{:<11}", kStateNames[s.index()]);
        for (const auto& c : cmds) row += std::format(" {:<22}", show(transition(s, c)));
        while (!row.empty() && row.back() == ' ') row.pop_back();
        std::println("{}", row);
    }
    std::println("guarded: Authorized + Capture(150.00) -> {}", show(transition(states[1], Capture{"cap-9", Money{15'000}})));
    std::println("guarded: Authorized + Authorize(auth-2) -> {}", show(transition(states[1], Authorize{"auth-2"})));
    try {
        Captured bad(id, total, "auth-1", "cap-1", Money{20'000});
        (void)bad;
    } catch (const std::invalid_argument& e) {
        std::println("constructor invariant: Captured(total=100.00, captured=200.00) -> {}", e.what());
    }

    // ---- 3. Capture webhook races a user cancel, 20,000 times ----
#if defined(__cpp_lib_atomic_shared_ptr)
    std::println("== Capture vs Cancel race: atomic<shared_ptr> CAS (is_lock_free={}) ==",
                 std::atomic<std::shared_ptr<const OrderState>>{}.is_lock_free());
#else
    std::println("== Capture vs Cancel race: mutex fallback (no atomic<shared_ptr> in this library) ==");
#endif
    int capture_won = 0, cancel_won = 0, both_won = 0;
    constexpr int kTrials = 20'000;
    for (int t = 0; t < kTrials; ++t) {
        Order order{Authorized{id, total, "auth-1"}};
        std::atomic<int> gate{0};
        std::optional<Result> a, b;
        std::thread t1([&] {
            gate.fetch_add(1);
            while (gate.load() < 2) {}
            a = order.handle(Capture{"cap-1", total});
        });
        std::thread t2([&] {
            gate.fetch_add(1);
            while (gate.load() < 2) {}
            b = order.handle(Cancel{"user changed mind"});
        });
        t1.join();
        t2.join();
        const bool cap_ok = a->has_value(), can_ok = b->has_value();
        if (cap_ok && can_ok) ++both_won;
        else if (cap_ok) ++capture_won;
        else if (can_ok) ++cancel_won;
        const std::size_t expect = cap_ok ? 2 : 3;  // Captured : Cancelled
        if (order.current_index() != expect) throw std::logic_error("final state disagrees with winner");
    }
    std::println("{} trials: capture won {} | cancel won {} | both won {} (must be 0)", kTrials, capture_won, cancel_won, both_won);
    if (both_won != 0 || capture_won + cancel_won != kTrials) throw std::logic_error("race invariant broken");
    std::println("SELF-TEST OK");
}
```

**Output, GCC 16.2 / libstdc++:**

```text
== Flag model ==
representable flag combinations : 16
reachable by legal transitions  : 6 [{}, {isAuthorized}, {isCancelled}, {isAuthorized,isPaid}, {isAuthorized,isCancelled}, {isAuthorized,isPaid,isRefunded}]
representable but illegal       : 10
  e.g. [{isPaid}, {isPaid,isCancelled}, {isAuthorized,isPaid,isCancelled}, {isRefunded}]
with 3 nullable ids (x8 shapes) : 128 representable, 6 legal
variant ADT shapes              : 6 (Created, Authorized, Captured, Cancelled x2 CancelPoints, Refunded)
== Transition table (state x command -> next state | x error) ==
            Authorize(auth-1)      Capture(cap-1,100.00)  Cancel                 Refund(100.00)
Created     Authorized             x ILLEGAL_TRANSITION   Cancelled              x ILLEGAL_TRANSITION
Authorized  Authorized             Captured               Cancelled              x ILLEGAL_TRANSITION
Captured    x ILLEGAL_TRANSITION   Captured               x CAPTURED_USE_REFUND  Refunded
Cancelled   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION
Refunded    x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION
guarded: Authorized + Capture(150.00) -> x CAPTURE_EXCEEDS_AUTH
guarded: Authorized + Authorize(auth-2) -> x ALREADY_AUTHORIZED
constructor invariant: Captured(total=100.00, captured=200.00) -> capture exceeds total
== Capture vs Cancel race: atomic<shared_ptr> CAS (is_lock_free=false) ==
20000 trials: capture won 9974 | cancel won 10026 | both won 0 (must be 0)
SELF-TEST OK
```

**Output, Clang 21.1 / libc++.** Only the race section differs, because libc++ 21 has no `std::atomic<std::shared_ptr>`, so the mutex fallback is compiled:

```text
== Flag model ==
representable flag combinations : 16
reachable by legal transitions  : 6 [{}, {isAuthorized}, {isCancelled}, {isAuthorized,isPaid}, {isAuthorized,isCancelled}, {isAuthorized,isPaid,isRefunded}]
representable but illegal       : 10
  e.g. [{isPaid}, {isPaid,isCancelled}, {isAuthorized,isPaid,isCancelled}, {isRefunded}]
with 3 nullable ids (x8 shapes) : 128 representable, 6 legal
variant ADT shapes              : 6 (Created, Authorized, Captured, Cancelled x2 CancelPoints, Refunded)
== Transition table (state x command -> next state | x error) ==
            Authorize(auth-1)      Capture(cap-1,100.00)  Cancel                 Refund(100.00)
Created     Authorized             x ILLEGAL_TRANSITION   Cancelled              x ILLEGAL_TRANSITION
Authorized  Authorized             Captured               Cancelled              x ILLEGAL_TRANSITION
Captured    x ILLEGAL_TRANSITION   Captured               x CAPTURED_USE_REFUND  Refunded
Cancelled   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION
Refunded    x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION   x ILLEGAL_TRANSITION
guarded: Authorized + Capture(150.00) -> x CAPTURE_EXCEEDS_AUTH
guarded: Authorized + Authorize(auth-2) -> x ALREADY_AUTHORIZED
constructor invariant: Captured(total=100.00, captured=200.00) -> capture exceeds total
== Capture vs Cancel race: mutex fallback (no atomic<shared_ptr> in this library) ==
20000 trials: capture won 724 | cancel won 19276 | both won 0 (must be 0)
SELF-TEST OK
```

### 4.5 Design notes on Listing 2.1

**Nested exhaustive switches, no `default`.** The transition function switches on the state first, and on the command inside each arm, with no `default` anywhere. Adding a sixth state *or* a fifth command fails compilation until every new pair is decided. The tempting alternative is a single `switch (new Pair(state, cmd))` with a catch-all `case Pair(var s, var c) -> illegal`. It's shorter, but the catch-all makes the switch total *without* thinking. New states silently become "illegal transition" at runtime: exactly the defect sealing was meant to prevent. The C++ version has the same trade-off. A generic `[](const auto&, const auto&)` lambda in a two-variant `std::visit` compiles for every pair. Nested visits with one lambda per alternative don't.

**Idempotent replays are transitions too.**
- `Authorized + Authorize(sameAuthId) → Authorized` (the same state).
- `Captured + Capture(sameCaptureId) → Captured`.
- The same command with a *different* id is an error.

This is how a webhook retry becomes harmless, and it's visible in the table: the `Authorized/Authorize` and `Captured/Capture` cells map to themselves.

**Guards express value rules; types express shape rules.** `Capture` above the authorized total and `Refund` above the captured amount are `when` guards (C++: `if` inside the lambda). The `Captured` record's compact constructor enforces `captured ≤ total` again, so no code path can *construct* an over-capture, even one that bypasses `transition`.

**Optimistic transitions (Java).** `transition` is pure, so the aggregate can use the classic optimistic loop: read the current state, compute the next, `compareAndSet(prev, next)`, and retry on failure. Running a capture webhook against a user cancel 20,000 times, exactly one wins every time (9,557 / 10,443 split in this run; "both won" = 0). The CAS compares **object identity**, which is exactly right here: we CAS from the instance we read. File 03, Listing 3.2 shows the same identity semantics biting when you CAS against an *equal* but different object.

**Optimistic transitions (C++).** libstdc++ provides `std::atomic<std::shared_ptr<T>>` (P0718), but it reports `is_lock_free() == false`: it is implemented with an internal lock bit. libc++ 21 doesn't provide it. The portable choice is a mutex around the aggregate. The listing compiles either path from the `__cpp_lib_atomic_shared_ptr` feature-test macro, and both hold the invariant.

**ADL gotcha (C++, found while building this listing).** The function was first named `apply`. Clang 21/libc++ rejected `apply(states[1], Capture{…})`: argument-dependent lookup on the `std::variant` argument also found `std::apply`, whose forwarding-reference signature is a better match than a user function requiring a `Capture → Command` conversion. GCC/libstdc++ accepted it. **Don't name free functions after `std` algorithms when their arguments are `std` types.**

### 4.6 Pattern-matching rules that matter in interviews 🧊

| Rule | Java 21+ | C++ (`std::visit`) |
|---|---|---|
| Exhaustiveness | `switch` over a sealed type with no `default` must cover all permitted subtypes, otherwise a compile error | every alternative needs a viable overload, otherwise a compile error |
| Separate compilation | A subtype added later without recompiling the switch causes `MatchException` at runtime | n/a (header-only templates recompile) |
| Dominance | `case Held h` before `case Held h when …` is a compile error (the guarded case is unreachable) | first-match isn't a concept; overload resolution picks the best match, and ambiguity is an error |
| Guards | `case Held h when h.token() == t ->` | an `if` inside the lambda |
| Nulls | `switch` throws `NullPointerException` unless there's `case null` | a `std::variant` is never null; `valueless_by_exception()` after a throwing assignment |
| Deconstruction | `case Booked(var token, var user, var pay)`; Java 22+ adds `_` for unused components | structured bindings on the alternative inside the lambda |
| Multi-dispatch | switch on a record pair, or nest switches | `std::visit(f, v1, v2)` visits the cartesian product |

### 4.7 Where data-orientation stops

Data-oriented modelling doesn't remove objects; it shrinks them to what must have identity:

- **The aggregate keeps identity, the lock, and the lifecycle.** `Order` (one `AtomicReference`), `FencedSeatHolds` (locks + array). Its state is data and its rules are a pure function: *functional core, imperative shell.*
- **Entities with long-lived mutable relationships** (a graph of drivers and trips, a file-system tree) stay as objects. Their *snapshots*, *events* and *commands* become records.
- **Hot numeric loops** may abandon both for primitive arrays (§9).

---
## 5. Value objects: money, identity, parsing, equality

### 5.1 What makes something a value object

A value object is defined entirely by its attributes, is immutable, validates itself on construction, and carries its own operations: `Money.plus`, `Money.allocate`. In interviews, value objects carry the defects that tests rarely catch: scale, rounding, currency mixing, and identifiers passed in the wrong order. Listing 2.3 takes each one in turn.

### 5.2 Listing 2.3 (Java)

```java
// ValueObjects.java - Money, strong ids, parse-don't-validate, and the record equality traps
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Currency;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;
import java.util.regex.Pattern;

public final class ValueObjects {

    // ===== Money: the canonical value object ====================================================

    record Money(BigDecimal amount, Currency currency) implements Comparable<Money> {
        Money {
            Objects.requireNonNull(amount, "amount");
            Objects.requireNonNull(currency, "currency");
            // Normalise the scale so equals() means "same money"; refuse silent precision loss.
            amount = amount.setScale(currency.getDefaultFractionDigits(), RoundingMode.UNNECESSARY);
        }

        static Money of(String amount, String currencyCode) {
            return new Money(new BigDecimal(amount), Currency.getInstance(currencyCode));
        }

        private void requireSameCurrency(Money o) {
            if (!currency.equals(o.currency)) throw new IllegalArgumentException(currency + " vs " + o.currency);
        }

        Money plus(Money o) {
            requireSameCurrency(o);
            return new Money(amount.add(o.amount), currency);
        }

        Money times(BigDecimal factor, RoundingMode mode) {
            return new Money(amount.multiply(factor).setScale(currency.getDefaultFractionDigits(), mode), currency);
        }

        long minorUnits() {
            return amount.movePointRight(currency.getDefaultFractionDigits()).longValueExact();
        }

        static Money ofMinor(long minor, Currency c) {
            return new Money(BigDecimal.valueOf(minor, c.getDefaultFractionDigits()), c);
        }

        /** Largest-remainder allocation in minor units: the parts always sum to the whole. */
        List<Money> allocate(long... ratios) {
            long total = minorUnits(), sum = Arrays.stream(ratios).sum();
            if (sum <= 0 || Arrays.stream(ratios).anyMatch(r -> r < 0)) throw new IllegalArgumentException("bad ratios");
            long[] parts = new long[ratios.length];
            long[] remainders = new long[ratios.length];
            long given = 0;
            for (int i = 0; i < ratios.length; i++) {
                long scaled = Math.multiplyExact(total, ratios[i]);   // overflow is an error, never a wrap
                parts[i] = scaled / sum;
                remainders[i] = scaled % sum;
                given += parts[i];
            }
            for (long left = total - given; left > 0; left--) {         // one minor unit to each largest remainder
                int best = 0;
                for (int i = 1; i < ratios.length; i++) if (remainders[i] > remainders[best]) best = i;
                parts[best]++;
                remainders[best] = -1;
            }
            List<Money> out = new ArrayList<>();
            for (long p : parts) out.add(ofMinor(p, currency));
            return out;
        }

        @Override public int compareTo(Money o) {
            requireSameCurrency(o);
            return amount.compareTo(o.amount);
        }

        @Override public String toString() {
            return amount.toPlainString() + " " + currency.getCurrencyCode();
        }
    }

    // ===== Strong ids and parse-don't-validate ===================================================

    record UserId(String value) {
        UserId {
            if (!value.matches("u-[0-9]{1,12}")) throw new IllegalArgumentException("bad user id: " + value);
        }
    }

    record OrderId(String value) {
        OrderId {
            if (!value.matches("o-[0-9]{1,12}")) throw new IllegalArgumentException("bad order id: " + value);
        }
    }

    sealed interface Parsed<T> permits Valid, Invalid {}
    record Valid<T>(T value) implements Parsed<T> {}
    record Invalid<T>(String why) implements Parsed<T> {}

    /** Once you hold an EmailAddress it IS valid and normalised: no re-validation downstream. */
    record EmailAddress(String value) {
        private static final Pattern SHAPE = Pattern.compile("[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}");

        EmailAddress {
            if (!SHAPE.matcher(value).matches()) throw new IllegalArgumentException("not normalised: " + value);
        }

        static Parsed<EmailAddress> parse(String raw) {
            String v = raw == null ? "" : raw.strip().toLowerCase(Locale.ROOT);
            return SHAPE.matcher(v).matches() ? new Valid<>(new EmailAddress(v)) : new Invalid<>("not an email: '" + raw + "'");
        }
    }

    static String place(UserId user, OrderId order) {     // place(order, user) does not compile
        return user.value() + " placed " + order.value();
    }

    // ===== Record equality traps ===================================================================

    record Blob(byte[] bytes) {}                          // equals() compares the array REFERENCE

    record Point(double x, double y) {}                   // equals() uses Double.compare, not ==

    record Team(String name, List<String> members) {}     // no defensive copy

    record SafeTeam(String name, List<String> members) {
        SafeTeam {
            members = List.copyOf(members);               // immutable snapshot; rejects nulls
        }
    }

    static final class MutableKey {                       // what records protect you from
        int id;

        MutableKey(int id) {
            this.id = id;
        }

        @Override public boolean equals(Object o) {
            return o instanceof MutableKey k && k.id == id;
        }

        @Override public int hashCode() {
            return Integer.hashCode(id);
        }
    }

    public static void main(String[] args) {
        System.out.println("== BigDecimal equality is scale-sensitive ==");
        BigDecimal a = new BigDecimal("2.0"), b = new BigDecimal("2.00");
        System.out.println("2.0 equals 2.00 -> " + a.equals(b) + ", compareTo -> " + a.compareTo(b)
                + ", HashSet size -> " + new HashSet<>(List.of(a, b)).size());
        System.out.println("Money(2.0 USD) equals Money(2.00 USD) -> " + Money.of("2.0", "USD").equals(Money.of("2.00", "USD")));
        for (String bad : List.of("10.005 USD", "100.5 JPY")) {
            String[] p = bad.split(" ");
            try {
                Money.of(p[0], p[1]);
            } catch (ArithmeticException e) {
                System.out.println("Money.of(" + bad + ") -> rejected: " + e.getMessage());
            }
        }

        System.out.println("== Never double for money ==");
        System.out.println("0.1 + 0.2 = " + (0.1 + 0.2));
        System.out.println("new BigDecimal(0.1)     = " + new BigDecimal(0.1));
        System.out.println("BigDecimal.valueOf(0.1) = " + BigDecimal.valueOf(0.1));

        System.out.println("== Rounding is a business decision ==");
        Money base = Money.of("23.45", "USD");
        for (RoundingMode m : List.of(RoundingMode.HALF_EVEN, RoundingMode.HALF_UP, RoundingMode.DOWN))
            System.out.println("23.45 x 0.1 (=2.345) " + m + " -> " + base.times(new BigDecimal("0.1"), m));
        System.out.println("23.55 x 0.1 (=2.355) HALF_EVEN -> " + Money.of("23.55", "USD").times(new BigDecimal("0.1"), RoundingMode.HALF_EVEN));

        System.out.println("== Allocation: parts always sum to the whole ==");
        Money hundred = Money.of("100.00", "USD");
        List<Money> thirds = hundred.allocate(1, 1, 1);
        System.out.println("100.00 USD / 3       -> " + thirds + " sum=" + thirds.stream().reduce(Money::plus).orElseThrow());
        List<Money> nickel = Money.of("0.05", "USD").allocate(50, 30, 20);
        System.out.println("0.05 USD by 50/30/20 -> " + nickel + " sum=" + nickel.stream().reduce(Money::plus).orElseThrow());
        System.out.println("naive 100.00/3 HALF_EVEN x3 -> "
                + new BigDecimal("100.00").divide(new BigDecimal(3), 2, RoundingMode.HALF_EVEN).multiply(new BigDecimal(3)) + " (a cent vanished)");

        System.out.println("== Strong ids + parse, don't validate ==");
        System.out.println(place(new UserId("u-42"), new OrderId("o-7")));
        for (String raw : List.of("  Alice.Smith@Example.COM ", "alice@", "bob@corp.io"))
            System.out.println("parse('" + raw + "') -> " + EmailAddress.parse(raw));

        System.out.println("== Record equality traps ==");
        System.out.println("Blob([1,2]) equals Blob([1,2])        -> " + new Blob(new byte[] {1, 2}).equals(new Blob(new byte[] {1, 2})));
        System.out.println("0.0 == -0.0                            -> " + (0.0 == -0.0));
        System.out.println("Point(0.0,0) equals Point(-0.0,0)      -> " + new Point(0.0, 0).equals(new Point(-0.0, 0)));
        System.out.println("NaN == NaN                             -> " + (Double.NaN == Double.NaN));
        System.out.println("Point(NaN,0) equals Point(NaN,0)       -> " + new Point(Double.NaN, 0).equals(new Point(Double.NaN, 0)));
        List<String> roster = new ArrayList<>(List.of("ann"));
        Team team = new Team("core", roster);
        SafeTeam safe = new SafeTeam("core", roster);
        roster.add("mallory");
        System.out.println("Team after caller mutates its list     -> " + team.members());
        System.out.println("SafeTeam after caller mutates its list -> " + safe.members());
        Set<MutableKey> keys = new HashSet<>();
        MutableKey k = new MutableKey(1);
        keys.add(k);
        k.id = 2;                                         // hash bucket is now wrong
        System.out.println("HashSet.contains(key) after mutating the key -> " + keys.contains(k) + " (size " + keys.size() + ")");

        boolean ok = thirds.stream().reduce(Money::plus).orElseThrow().equals(hundred)
                && nickel.stream().reduce(Money::plus).orElseThrow().equals(Money.of("0.05", "USD"))
                && !a.equals(b) && Money.of("2.0", "USD").equals(Money.of("2.00", "USD"));
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (verified):**

```text
== BigDecimal equality is scale-sensitive ==
2.0 equals 2.00 -> false, compareTo -> 0, HashSet size -> 2
Money(2.0 USD) equals Money(2.00 USD) -> true
Money.of(10.005 USD) -> rejected: Rounding necessary
Money.of(100.5 JPY) -> rejected: Rounding necessary
== Never double for money ==
0.1 + 0.2 = 0.30000000000000004
new BigDecimal(0.1)     = 0.1000000000000000055511151231257827021181583404541015625
BigDecimal.valueOf(0.1) = 0.1
== Rounding is a business decision ==
23.45 x 0.1 (=2.345) HALF_EVEN -> 2.34 USD
23.45 x 0.1 (=2.345) HALF_UP -> 2.35 USD
23.45 x 0.1 (=2.345) DOWN -> 2.34 USD
23.55 x 0.1 (=2.355) HALF_EVEN -> 2.36 USD
== Allocation: parts always sum to the whole ==
100.00 USD / 3       -> [33.34 USD, 33.33 USD, 33.33 USD] sum=100.00 USD
0.05 USD by 50/30/20 -> [0.03 USD, 0.01 USD, 0.01 USD] sum=0.05 USD
naive 100.00/3 HALF_EVEN x3 -> 99.99 (a cent vanished)
== Strong ids + parse, don't validate ==
u-42 placed o-7
parse('  Alice.Smith@Example.COM ') -> Valid[value=EmailAddress[value=alice.smith@example.com]]
parse('alice@') -> Invalid[why=not an email: 'alice@']
parse('bob@corp.io') -> Valid[value=EmailAddress[value=bob@corp.io]]
== Record equality traps ==
Blob([1,2]) equals Blob([1,2])        -> false
0.0 == -0.0                            -> true
Point(0.0,0) equals Point(-0.0,0)      -> false
NaN == NaN                             -> false
Point(NaN,0) equals Point(NaN,0)       -> true
Team after caller mutates its list     -> [ann, mallory]
SafeTeam after caller mutates its list -> [ann]
HashSet.contains(key) after mutating the key -> false (size 1)
SELF-TEST OK
```

### 5.3 Listing 2.3 (C++)

```cpp
// value_objects.cpp - Money in minor units, strong ids, parse-don't-validate, and equality traps
#include <algorithm>
#include <cctype>
#include <cmath>
#include <compare>
#include <cstdint>
#include <expected>
#include <format>
#include <limits>
#include <numeric>
#include <print>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

// ===== Money: integer minor units, currency carries its exponent ===========================

struct Currency {
    std::string_view code;
    int exponent;  // USD 2, JPY 0, BHD 3
    bool operator==(const Currency&) const = default;
};
constexpr Currency USD{"USD", 2}, JPY{"JPY", 0};

enum class MoneyError { Malformed, PrecisionLoss, Overflow, CurrencyMismatch };
constexpr const char* name(MoneyError e) {
    switch (e) {
        case MoneyError::Malformed: return "Malformed";
        case MoneyError::PrecisionLoss: return "PrecisionLoss";
        case MoneyError::Overflow: return "Overflow";
        case MoneyError::CurrencyMismatch: return "CurrencyMismatch";
    }
    return "?";
}

class Money {
    std::int64_t minor_;
    Currency cur_;
    Money(std::int64_t minor, Currency c) : minor_(minor), cur_(c) {}

public:
    /** Parse "123.45": the only way in, so every Money that exists is well-formed. */
    [[nodiscard]] static std::expected<Money, MoneyError> parse(std::string_view s, Currency c) {
        const auto dot = s.find('.');
        const std::string_view whole = s.substr(0, dot);
        const std::string_view frac = dot == std::string_view::npos ? std::string_view{} : s.substr(dot + 1);
        constexpr auto digit = [](char ch) { return ch >= '0' && ch <= '9'; };
        if (whole.empty() || !std::ranges::all_of(whole, digit) || !std::ranges::all_of(frac, digit))
            return std::unexpected(MoneyError::Malformed);
        if (frac.size() > static_cast<std::size_t>(c.exponent)) return std::unexpected(MoneyError::PrecisionLoss);
        std::int64_t v = 0;
        for (char ch : whole) {
            if (__builtin_mul_overflow(v, 10, &v) || __builtin_add_overflow(v, ch - '0', &v))
                return std::unexpected(MoneyError::Overflow);
        }
        for (int i = 0; i < c.exponent; ++i) {
            const int d = static_cast<std::size_t>(i) < frac.size() ? frac[static_cast<std::size_t>(i)] - '0' : 0;
            if (__builtin_mul_overflow(v, 10, &v) || __builtin_add_overflow(v, d, &v))
                return std::unexpected(MoneyError::Overflow);
        }
        return Money(v, c);
    }
    static Money of_minor(std::int64_t minor, Currency c) { return Money(minor, c); }

    [[nodiscard]] std::expected<Money, MoneyError> plus(const Money& o) const {
        if (cur_ != o.cur_) return std::unexpected(MoneyError::CurrencyMismatch);
        std::int64_t r;
        if (__builtin_add_overflow(minor_, o.minor_, &r)) return std::unexpected(MoneyError::Overflow);
        return Money(r, cur_);
    }

    /** amount x (bp / 10000), rounded half-to-even in integer arithmetic. */
    [[nodiscard]] Money times_bp_half_even(std::int64_t bp) const {
        std::int64_t num;
        if (__builtin_mul_overflow(minor_, bp, &num)) throw std::overflow_error("times_bp");
        const std::int64_t q = num / 10'000, r = num % 10'000;
        const bool round_up = r > 5'000 || (r == 5'000 && (q % 2 != 0));
        return Money(q + (round_up ? 1 : 0), cur_);
    }

    /** Largest-remainder allocation: the parts always sum to the whole. */
    [[nodiscard]] std::vector<Money> allocate(const std::vector<std::int64_t>& ratios) const {
        const std::int64_t sum = std::accumulate(ratios.begin(), ratios.end(), std::int64_t{0});
        if (sum <= 0) throw std::invalid_argument("bad ratios");
        std::vector<std::int64_t> parts(ratios.size()), rem(ratios.size());
        std::int64_t given = 0;
        for (std::size_t i = 0; i < ratios.size(); ++i) {
            std::int64_t scaled;
            if (__builtin_mul_overflow(minor_, ratios[i], &scaled)) throw std::overflow_error("allocate");
            parts[i] = scaled / sum;
            rem[i] = scaled % sum;
            given += parts[i];
        }
        for (std::int64_t left = minor_ - given; left > 0; --left) {
            const auto best = static_cast<std::size_t>(std::ranges::max_element(rem) - rem.begin());  // first max wins
            ++parts[best];
            rem[best] = -1;
        }
        std::vector<Money> out;
        for (auto p : parts) out.push_back(Money(p, cur_));
        return out;
    }

    std::int64_t minor() const { return minor_; }
    bool operator==(const Money&) const = default;  // same units, same currency: no scale trap
    std::string str() const {
        if (cur_.exponent == 0) return std::format("{} {}", minor_, cur_.code);
        std::int64_t p = 1;
        for (int i = 0; i < cur_.exponent; ++i) p *= 10;
        return std::format("{}.{:0{}} {}", minor_ / p, minor_ % p, cur_.exponent, cur_.code);
    }
};

std::string join(const std::vector<Money>& v) {
    std::string s;
    for (const auto& m : v) s += (s.empty() ? "" : ", ") + m.str();
    return "[" + s + "]";
}

Money sum(const std::vector<Money>& v) {
    Money acc = v.front();
    for (std::size_t i = 1; i < v.size(); ++i) acc = acc.plus(v[i]).value();
    return acc;
}

// ===== Strong ids and parse-don't-validate ===================================================

template <class Tag>
struct StrongId {
    std::string value;
    auto operator<=>(const StrongId&) const = default;
};
using UserId = StrongId<struct UserTag>;
using OrderId = StrongId<struct OrderTag>;

std::string place(const UserId& user, const OrderId& order) { return user.value + " placed " + order.value; }  // swapped args: no conversion

class EmailAddress {
    std::string value_;
    explicit EmailAddress(std::string v) : value_(std::move(v)) {}
public:
    [[nodiscard]] static std::expected<EmailAddress, std::string> parse(std::string_view raw) {
        std::string v;
        for (char ch : raw)
            if (!std::isspace(static_cast<unsigned char>(ch))) v += static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
        static const std::regex shape(R"([a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})");
        if (!std::regex_match(v, shape)) return std::unexpected("not an email: '" + std::string(raw) + "'");
        return EmailAddress(std::move(v));
    }
    const std::string& value() const { return value_; }
};

// ===== Equality: what "= default" means in C++ vs a Java record =============================

struct Blob {
    std::vector<unsigned char> bytes;
    bool operator==(const Blob&) const = default;  // compares CONTENTS (Java record + byte[]: reference)
};
struct Point {
    double x, y;
    bool operator==(const Point&) const = default;  // uses == on doubles (Java record: Double.compare)
};

int main() {
    std::println("== Money is integer minor units ==");
    const auto two_a = Money::parse("2.0", USD).value(), two_b = Money::parse("2.00", USD).value();
    std::println("Money(2.0 USD) == Money(2.00 USD) -> {}", two_a == two_b);
    for (auto [text, cur] : {std::pair{"10.005", USD}, std::pair{"100.5", JPY}, std::pair{"12a.00", USD},
                             std::pair{"99999999999999999999", USD}}) {
        const auto m = Money::parse(text, cur);
        std::println("parse({} {}) -> {}", text, cur.code, m ? m->str() : std::string("rejected: ") + name(m.error()));
    }
    const auto big = Money::of_minor(std::numeric_limits<std::int64_t>::max(), USD);
    std::println("INT64_MAX minor + 0.01 USD -> {}", big.plus(Money::of_minor(1, USD)) ? "?" : "rejected: Overflow");

    std::println("== Never double for money ==");
    std::println("0.1 + 0.2 = {:.17g}  (== 0.3: {})", 0.1 + 0.2, 0.1 + 0.2 == 0.3);
    std::println("0.1 stored as {:.55f}", 0.1);

    std::println("== Rounding is a business decision ==");
    std::println("23.45 x 10% HALF_EVEN -> {}", Money::parse("23.45", USD)->times_bp_half_even(1'000).str());
    std::println("23.55 x 10% HALF_EVEN -> {}", Money::parse("23.55", USD)->times_bp_half_even(1'000).str());

    std::println("== Allocation: parts always sum to the whole ==");
    const auto hundred = Money::parse("100.00", USD).value();
    const auto thirds = hundred.allocate({1, 1, 1});
    std::println("100.00 USD / 3       -> {} sum={}", join(thirds), sum(thirds).str());
    const auto nickel = Money::parse("0.05", USD)->allocate({50, 30, 20});
    std::println("0.05 USD by 50/30/20 -> {} sum={}", join(nickel), sum(nickel).str());

    std::println("== Strong ids + parse, don't validate ==");
    std::println("{}", place(UserId{"u-42"}, OrderId{"o-7"}));
    for (std::string_view raw : {"  Alice.Smith@Example.COM ", "alice@", "bob@corp.io"}) {
        const auto e = EmailAddress::parse(raw);
        std::println("parse('{}') -> {}", raw, e ? "Valid[" + e->value() + "]" : "Invalid[" + e.error() + "]");
    }

    std::println("== Equality: C++ defaulted == vs Java records ==");
    std::println("Blob{{1,2}} == Blob{{1,2}}         -> {}", Blob{{1, 2}} == Blob{{1, 2}});
    std::println("Point{{0.0,0}} == Point{{-0.0,0}}  -> {}", Point{0.0, 0} == Point{-0.0, 0});
    const double nan = std::numeric_limits<double>::quiet_NaN();
    std::println("Point{{NaN,0}} == Point{{NaN,0}}   -> {}", Point{nan, 0} == Point{nan, 0});
    std::set<int> keys{1};
    std::println("std::set keys are const: *keys.begin() = 2 does not compile; size {}", keys.size());

    const bool ok = sum(thirds) == hundred && sum(nickel) == Money::parse("0.05", USD).value() && two_a == two_b &&
                    Blob{{1, 2}} == Blob{{1, 2}} && !(Point{nan, 0} == Point{nan, 0});
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output (verified; identical under GCC 16.2 and Clang 21.1):**

```text
== Money is integer minor units ==
Money(2.0 USD) == Money(2.00 USD) -> true
parse(10.005 USD) -> rejected: PrecisionLoss
parse(100.5 JPY) -> rejected: PrecisionLoss
parse(12a.00 USD) -> rejected: Malformed
parse(99999999999999999999 USD) -> rejected: Overflow
INT64_MAX minor + 0.01 USD -> rejected: Overflow
== Never double for money ==
0.1 + 0.2 = 0.30000000000000004  (== 0.3: false)
0.1 stored as 0.1000000000000000055511151231257827021181583404541015625
== Rounding is a business decision ==
23.45 x 10% HALF_EVEN -> 2.34 USD
23.55 x 10% HALF_EVEN -> 2.36 USD
== Allocation: parts always sum to the whole ==
100.00 USD / 3       -> [33.34 USD, 33.33 USD, 33.33 USD] sum=100.00 USD
0.05 USD by 50/30/20 -> [0.03 USD, 0.01 USD, 0.01 USD] sum=0.05 USD
== Strong ids + parse, don't validate ==
u-42 placed o-7
parse('  Alice.Smith@Example.COM ') -> Valid[alice.smith@example.com]
parse('alice@') -> Invalid[not an email: 'alice@']
parse('bob@corp.io') -> Valid[bob@corp.io]
== Equality: C++ defaulted == vs Java records ==
Blob{1,2} == Blob{1,2}         -> true
Point{0.0,0} == Point{-0.0,0}  -> true
Point{NaN,0} == Point{NaN,0}   -> false
std::set keys are const: *keys.begin() = 2 does not compile; size 1
SELF-TEST OK
```

### 5.4 The money rules, distilled 🔥

1. **Never `double`.** `0.1 + 0.2 = 0.30000000000000004`, and `0.1` is stored as `0.1000000000000000055511151231257827021181583404541015625`. Use `BigDecimal` in Java and integer minor units in C++ (or a decimal library). In Java, construct from strings or `BigDecimal.valueOf(double)`, never from `new BigDecimal(double)`.
2. **Normalize the scale in the constructor, and refuse silent precision loss.** `BigDecimal.equals` is scale-sensitive: `2.0 ≠ 2.00` even though `compareTo` says equal, so a `HashSet` holds both. Normalizing to the currency's fraction digits with `RoundingMode.UNNECESSARY` makes `equals` mean "same money" and rejects `10.005 USD` and `100.5 JPY` at the boundary.
3. **Rounding is a business decision, so name it.** At the half-cent, `HALF_EVEN` (banker's rounding) gives 2.34 for 2.345 and 2.36 for 2.355, and `HALF_UP` gives 2.35. Taxes, FX and interest each have a regulated rule: ask, and put the mode in the method signature.
4. **Allocate, don't divide.** `100.00 / 3` rounded and multiplied back gives `99.99`: a cent vanished. Largest-remainder allocation in minor units gives `[33.34, 33.33, 33.33]`, and the parts always sum to the whole. Splitwise (P11) and ledger postings (P13) build on this.
5. **Overflow is an error, never a wrap.** Java: `Math.multiplyExact` / `longValueExact`. C++: `__builtin_*_overflow` (GCC/Clang; C++26 adds `<stdckdint.h>` ⚠) returning `MoneyError::Overflow`.

### 5.5 Strong identifiers and parse-don't-validate ⚡

- **Strong ids** (`record UserId(String value)`, `StrongId<struct UserTag>`) turn "arguments in the wrong order" from a production incident into a compile error: `place(order, user)` doesn't compile. Their constructors validate the format once.
- **Parse, don't validate** (Alexis King): a function that *checks* an email returns `boolean`, and every caller must remember to call it. A function that *parses* returns `EmailAddress` or a failure (`Parsed<T>` in Java, `std::expected` in C++). The type then carries the proof, so downstream code can't receive an unvalidated string.

### 5.6 Equality: Java records vs C++ defaulted `==` 🧊

The same-looking declaration means different things in the two languages. Every row below is a verified output line from Listing 2.3:

| Case | Java `record` `equals` | C++ `operator== = default` |
|---|---|---|
| Array / vector component | **Reference** equality: `Blob([1,2]) ≠ Blob([1,2])` | **Element-wise**: `Blob{1,2} == Blob{1,2}` |
| `double` component, `0.0` vs `-0.0` | `Double.compare`: **not equal** | `==`: **equal** |
| `double` component, `NaN` vs `NaN` | `Double.compare`: **equal** | `==`: **not equal** |
| Mutable collection component | Shallow immutability: the caller's later `add` shows through, unless copied in the compact constructor | value semantics: the vector was copied on construction |
| Mutating a key after inserting into a hash set | Allowed: `contains` returns `false` and the element is lost in the wrong bucket | Not possible: `std::set`/`unordered_set` elements are `const` |

Interview takeaway:
- **Java records:** never use arrays as components (use `List.copyOf`, or override `equals`/`hashCode` with `Arrays.equals`), and copy every mutable collection in the compact constructor.
- **C++ aggregates:** remember that `-0.0 == 0.0` and `NaN != NaN` leak into your keys.

---

## 6. Typestate: moving transitions into the type checker

### 6.1 The idea

Instead of one `Order` type with a `status` field checked at runtime, give each state its own *type*, and put each transition only on the types where it's legal. Calling `ship()` on a draft then isn't a runtime `IllegalStateException`; it's a **compile error**.

Typestate is worth using in interviews when the protocol is linear and short:
- builders with mandatory steps;
- connection/session lifecycles (`Unauthenticated → Authenticated → Closed`);
- workflow handles returned to client code.

It's the wrong tool when states are many, data-driven, or must be persisted and re-hydrated. Use the sealed ADT of §4 for those.

### 6.2 Listing 2.4 (Java)

Three Java styles:
- **A:** one record per state; each transition method returns the next state's type.
- **B:** a step builder, where `build()` only exists once `url()` and `method()` were called.
- **C:** a phantom type parameter. Java can't constrain an *instance* method on a class's type argument, so the gate becomes a static method's parameter type.

```java
// TypestateOrders.java - typestate: make the illegal call fail to compile, not fail at runtime
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public final class TypestateOrders {

    // ===== Style A: one record per state; a transition returns the next state's type ==========

    record Draft(String id, List<String> lines) {
        Draft {
            lines = List.copyOf(lines);
        }

        static Draft create(String id) {
            return new Draft(id, List.of());
        }

        Draft add(String line) {
            List<String> next = new ArrayList<>(lines);
            next.add(line);
            return new Draft(id, next);
        }

        Submitted submit() {
            if (lines.isEmpty()) throw new IllegalStateException("empty order");  // data rule: still runtime
            return new Submitted(id, lines);
        }
    }

    record Submitted(String id, List<String> lines) {
        Paid pay(String paymentId) {
            return new Paid(id, lines, paymentId);
        }

        Draft reopen() {
            return new Draft(id, lines);
        }
    }

    record Paid(String id, List<String> lines, String paymentId) {
        Shipped ship(String tracking) {
            return new Shipped(id, lines, paymentId, tracking);
        }
    }

    record Shipped(String id, List<String> lines, String paymentId, String tracking) {}

    // ===== Style B: step builder -- build() exists only once the mandatory steps are done =======

    record HttpRequest(String url, String method, Map<String, String> headers) {
        HttpRequest {
            headers = Map.copyOf(headers);
        }

        static UrlStep builder() {
            return new Steps();
        }
    }

    interface UrlStep { MethodStep url(String url); }
    interface MethodStep { BuildStep method(String method); }
    interface BuildStep {
        BuildStep header(String k, String v);
        HttpRequest build();
    }

    private static final class Steps implements UrlStep, MethodStep, BuildStep {
        private String url, method;
        private final Map<String, String> headers = new TreeMap<>();

        @Override public MethodStep url(String u) {
            url = u;
            return this;
        }

        @Override public BuildStep method(String m) {
            method = m;
            return this;
        }

        @Override public BuildStep header(String k, String v) {
            headers.put(k, v);
            return this;
        }

        @Override public HttpRequest build() {
            return new HttpRequest(url, method, headers);
        }
    }

    // ===== Style C: phantom type parameter -- Java can't constrain an instance method on it =====

    sealed interface Stage permits Open, Locked {}
    static final class Open implements Stage {
        private Open() {}
    }
    static final class Locked implements Stage {
        private Locked() {}
    }

    record Config<S extends Stage>(Map<String, String> values) {
        Config {
            // Not Map.copyOf: its iteration order is randomized per JVM run, so printed output would flap.
            values = Collections.unmodifiableMap(new TreeMap<>(values));
        }

        static Config<Open> empty() {
            return new Config<>(Map.of());
        }

        // Instance methods cannot say "only when S = Open", so the gate is a static method's parameter type.
        static Config<Open> set(Config<Open> c, String k, String v) {
            Map<String, String> m = new TreeMap<>(c.values());
            m.put(k, v);
            return new Config<>(m);
        }

        static Config<Locked> lock(Config<Open> c) {
            return new Config<>(c.values());
        }
    }

    public static void main(String[] args) {
        Shipped shipped = Draft.create("o-1").add("book").add("pen").submit().pay("pay-9").ship("trk-1");
        System.out.println("Style A: " + shipped);
        Draft stale = Draft.create("o-2").add("mug");
        Submitted sub = stale.submit();
        Draft reused = stale.add("oops");               // the OLD state object is still usable: Java has no linear types
        System.out.println("Style A caveat: after submit(), the stale Draft still accepts add(): " + reused.lines() + " vs " + sub.lines());
        try {
            Draft.create("o-3").submit();
        } catch (IllegalStateException e) {
            System.out.println("Style A data rule (runtime): submit() on an empty draft -> " + e.getMessage());
        }

        HttpRequest req = HttpRequest.builder().url("https://api.example.com/v1/seats").method("POST")
                .header("Idempotency-Key", "k-1").build();
        System.out.println("Style B: " + req);

        Config<Locked> cfg = Config.lock(Config.set(Config.set(Config.empty(), "ttl", "300s"), "seats", "12"));
        System.out.println("Style C: " + cfg.values());
        System.out.println("SELF-TEST OK");
    }
}
```

**Output (verified):**

```text
Style A: Shipped[id=o-1, lines=[book, pen], paymentId=pay-9, tracking=trk-1]
Style A caveat: after submit(), the stale Draft still accepts add(): [mug, oops] vs [mug]
Style A data rule (runtime): submit() on an empty draft -> empty order
Style B: HttpRequest[url=https://api.example.com/v1/seats, method=POST, headers={Idempotency-Key=k-1}]
Style C: {seats=12, ttl=300s}
SELF-TEST OK
```

**A determinism bug the folder gate caught.** `Config` first stored `Map.copyOf(values)`. On rerun, the same program printed `{ttl=300s, seats=12}` in one JVM and `{seats=12, ttl=300s}` in the next. The iteration order of `Map.of`/`Set.of`/`Map.copyOf` is **deliberately randomized per JVM instance** (a per-run salt), so code can't come to depend on it. The fix is to copy into a `TreeMap` and wrap it unmodifiable, when order is part of the contract. Never print, serialize-for-comparison or assert on the iteration order of the immutable `Map.of` family.

The misuse file below must **fail** to compile. The harness compiles it against the classes above and asserts that javac rejects it:

```java
// TypestateMisuse.java - must NOT compile: each line is an illegal transition caught by javac
public final class TypestateMisuse {
    public static void main(String[] args) {
        TypestateOrders.Draft.create("o-1").ship("trk-1");                          // ship a draft
        TypestateOrders.HttpRequest.builder().method("GET");                         // skip url()
        TypestateOrders.Config.set(TypestateOrders.Config.lock(TypestateOrders.Config.empty()), "k", "v");  // edit a locked config
    }
}
```

**javac 25 diagnostics (verified):**

```text
TypestateMisuse.java:4: error: cannot find symbol
        TypestateOrders.Draft.create("o-1").ship("trk-1");                          // ship a draft
                                           ^
  symbol:   method ship(String)
  location: class Draft
TypestateMisuse.java:5: error: cannot find symbol
        TypestateOrders.HttpRequest.builder().method("GET");                         // skip url()
                                             ^
  symbol:   method method(String)
  location: interface UrlStep
TypestateMisuse.java:6: error: incompatible types: Config<Locked> cannot be converted to Config<Open>
        TypestateOrders.Config.set(TypestateOrders.Config.lock(TypestateOrders.Config.empty()), "k", "v");  // edit a locked config
                                                              ^
Note: Some messages have been simplified; recompile with -Xdiags:verbose to get full output
3 errors
```

### 6.3 Listing 2.4 (C++)

C++ can do what Java can't: constrain a *member function* on the class's own template parameter (`requires std::same_as<S, Paid>`). The `&&` ref-qualifier makes every transition consume the old state object. Use-after-move is still possible; clang-tidy's `bugprone-use-after-move` catches it. The illegal calls live under `#ifdef TYPESTATE_MISUSE`, and the harness builds that block separately, expecting failure.

```cpp
// typestate_orders.cpp - typestate with constrained member functions; build with -DTYPESTATE_MISUSE to see it bite
#include <concepts>
#include <map>
#include <print>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// ===== Style A: one class template, the state is a type parameter, methods are constrained ===

struct Draft {};
struct Submitted {};
struct Paid {};
struct Shipped {};

template <class S>
class Order {
    template <class> friend class Order;
    std::string id_;
    std::vector<std::string> lines_;
    std::string payment_id_, tracking_;

    Order(std::string id, std::vector<std::string> lines, std::string pay, std::string trk)
        : id_(std::move(id)), lines_(std::move(lines)), payment_id_(std::move(pay)), tracking_(std::move(trk)) {}

public:
    static Order create(std::string id)
        requires std::same_as<S, Draft>
    {
        return Order(std::move(id), {}, "", "");
    }
    // && : a transition consumes the old state (use-after-move is still possible; clang-tidy flags it)
    Order<Draft> add(std::string line) &&
        requires std::same_as<S, Draft>
    {
        lines_.push_back(std::move(line));
        return Order<Draft>(std::move(id_), std::move(lines_), "", "");
    }
    Order<Submitted> submit() &&
        requires std::same_as<S, Draft>
    {
        if (lines_.empty()) throw std::logic_error("empty order");  // data rule: still runtime
        return Order<Submitted>(std::move(id_), std::move(lines_), "", "");
    }
    Order<Paid> pay(std::string payment_id) &&
        requires std::same_as<S, Submitted>
    {
        return Order<Paid>(std::move(id_), std::move(lines_), std::move(payment_id), "");
    }
    Order<Shipped> ship(std::string tracking) &&
        requires std::same_as<S, Paid>
    {
        return Order<Shipped>(std::move(id_), std::move(lines_), std::move(payment_id_), std::move(tracking));
    }
    std::string str() const {
        std::string l;
        for (const auto& x : lines_) l += (l.empty() ? "" : ", ") + x;
        return id_ + " [" + l + "] pay=" + payment_id_ + " trk=" + tracking_;
    }
};

// ===== Style B: builder whose build() exists only when the mandatory steps are recorded ======

struct HttpRequest {
    std::string url, method;
    std::map<std::string, std::string> headers;
};

template <bool HasUrl = false, bool HasMethod = false>
class RequestBuilder {
    template <bool, bool> friend class RequestBuilder;
    HttpRequest r_;
    explicit RequestBuilder(HttpRequest r) : r_(std::move(r)) {}

public:
    RequestBuilder() = default;
    RequestBuilder<true, HasMethod> url(std::string u) && {
        r_.url = std::move(u);
        return RequestBuilder<true, HasMethod>(std::move(r_));
    }
    RequestBuilder<HasUrl, true> method(std::string m) && {
        r_.method = std::move(m);
        return RequestBuilder<HasUrl, true>(std::move(r_));
    }
    RequestBuilder header(std::string k, std::string v) && {
        r_.headers.insert_or_assign(std::move(k), std::move(v));
        return std::move(*this);
    }
    HttpRequest build() &&
        requires(HasUrl && HasMethod)
    {
        return std::move(r_);
    }
};

int main() {
    auto shipped = Order<Draft>::create("o-1").add("book").add("pen").submit().pay("pay-9").ship("trk-1");
    std::println("Style A: {}", shipped.str());
    try {
        (void)Order<Draft>::create("o-3").submit();
    } catch (const std::logic_error& e) {
        std::println("Style A data rule (runtime): submit() on an empty draft -> {}", e.what());
    }
    const HttpRequest req = RequestBuilder<>{}.url("https://api.example.com/v1/seats").method("POST")
                                .header("Idempotency-Key", "k-1").build();
    std::println("Style B: {} {} headers={}", req.method, req.url, req.headers.size());

#ifdef TYPESTATE_MISUSE
    auto draft = Order<Draft>::create("o-2");
    (void)std::move(draft).ship("trk-1");                         // ship a draft
    (void)RequestBuilder<>{}.method("GET").build();               // skip url()
    (void)Order<Paid>::create("o-4");                             // create in a non-initial state
#endif
    std::println("SELF-TEST OK");
}
```

**Output (verified):**

```text
Style A: o-1 [book, pen] pay=pay-9 trk=trk-1
Style A data rule (runtime): submit() on an empty draft -> empty order
Style B: POST https://api.example.com/v1/seats headers=1
SELF-TEST OK
```

**`-DTYPESTATE_MISUSE`, GCC 16.2 errors (verified):**

```text
typestate_orders.cpp:111:32: error: no matching function for call to 'Order<Draft>::ship(const char [6])'
typestate_orders.cpp:112:49: error: no matching function for call to 'RequestBuilder<false, true>::build()'
typestate_orders.cpp:113:30: error: no matching function for call to 'Order<Paid>::create(const char [4])'
```

**`-DTYPESTATE_MISUSE`, Clang 21.1 errors (verified):**

```text
typestate_orders.cpp:111:28: error: invalid reference to function 'ship': constraints not satisfied
typestate_orders.cpp:112:44: error: invalid reference to function 'build': constraints not satisfied
typestate_orders.cpp:113:24: error: invalid reference to function 'create': constraints not satisfied
```

### 6.4 The limit of typestate in Java and C++ ⚡

The verified Java output shows the catch: after `stale.submit()`, the **old `Draft` object is still usable** (`stale.add("oops")` succeeded). Neither Java nor C++ has *linear* types; Rust's move semantics enforce "used at most once" at compile time. Two mitigations:

- **Keep state transitions inside the aggregate.** Client code gets the *current* state from the owner, not a handle it can hoard. This is what `Order.handle` does in Listing 2.1.
- **C++:** `&&`-qualified transitions plus `bugprone-use-after-move` in CI.

---
## 7. Gang-of-Four ceremony vs modern Java vs modern C++

| Pattern | 2005-era ceremony | Modern Java (21/25) | Modern C++ (20/23) | When the classic form still wins |
|---|---|---|---|---|
| **Strategy** | Interface + one class per variant + factory | Functional interface; lambdas or small records | Template parameter / concept (static) or `std::function` (dynamic) | Strategies with configuration, metrics and names (pricing rules shown in an admin UI) |
| **State** | `State` interface, context delegating every call | `sealed` ADT + one pure `transition(state, cmd)` (Listing 2.1) | `std::variant` + `std::visit` | Each state owns substantial private behaviour and resources (a TCP session per state) |
| **Visitor** | `accept`/`visit` double dispatch across a hierarchy | `switch` over a sealed type with record patterns | `std::visit(overloaded{…})` | The hierarchy is **open** (third-party subtypes), so exhaustiveness is impossible. Folder 02, file 03 |
| **Command** | `Command` interface with `execute()`/`undo()` | Commands as records; a handler `switch`; undo as an inverse record or a captured-state memento | Variant of command structs | Undo needs captured context (chess: the captured piece, P19) |
| **Builder** | Mutable builder mirroring every field | Records + static factories; **step builder** for mandatory steps (Listing 2.4) | Designated initializers on aggregates; typestate builder (Listing 2.4) | Many optional parameters with cross-field validation |
| **Factory method / abstract factory** | Factory hierarchies | Static factory on the sealed interface; `Supplier<T>`; `ServiceLoader` for plugins | Factory function returning `std::unique_ptr` / a variant | Runtime plugin discovery |
| **Singleton** | `getInstance()` with double-checked locking | An `enum` singleton or, better, one instance wired by the composition root | Function-local static (initialization is thread-safe since C++11) | Never for *mutable* shared state; it is a hidden global |
| **Template method** | Abstract class with hooks | Higher-order function taking lambdas | Template + callables | Framework extension surfaces. `AbstractQueuedSynchronizer` is the canonical template method (`tryAcquire`/`tryRelease` hooks, file 03) |
| **Observer** | Subject/observer interfaces | Listener list (`CopyOnWriteArrayList`), `Flow`, or an event bus | `std::vector<std::function>` + unsubscribe tokens / `weak_ptr` | Folder 02, file 03 (ordering, re-entrancy, back-pressure) |
| **Decorator** | Wrapper classes | Same, via forwarding (`ForwardingSet`, Listing 2.2) or `Function.andThen` | Wrapper templates; function composition | Still the right tool: pricing surcharges (P7), cache layers (P18) |
| **Chain of responsibility** | Linked handler objects | `List<Handler>` iterated; `Predicate.and/or` | `std::vector<std::function>` | ATM dispensing with backtracking (P14) |
| **Null object** | `NullFoo implements Foo` | `Optional` return; a sealed `None` variant | `std::optional`; a variant alternative | Behaviour-bearing no-ops (a `NoopMetrics` recorder) |

---

## 8. Language deltas: Java 22–25 and C++20/23

### 8.1 Java: status as of JDK 25 ⚠

Later JDKs may finalize these previews; verify against the release notes of your interview JDK.

| Feature | JEP | Status in 25 | Why it matters in LLD code |
|---|---|---|---|
| Records / sealed classes | 395 / 409 | Final (16 / 17) | The ADT toolkit |
| Record patterns, pattern `switch` | 440 / 441 | Final (21) | Exhaustive, deconstructing transitions |
| Virtual threads | 444 | Final (21) | Thread-per-request without pools; Folder 07 |
| Sequenced collections | 431 | Final (21) | `getFirst/getLast/reversed` on `List`/`Deque`/`LinkedHashMap` |
| Unnamed variables and patterns `_` | 456 | Final (22) | `case Free _`, `Held(_, var user)`, `catch (X _)` |
| Stream gatherers | 485 | Final (24) | `windowSliding`, `windowFixed`, custom stateful stream ops |
| Virtual threads don't pin on `synchronized` | 491 | Final (24) | `synchronized` is acceptable again on virtual-thread paths |
| Scoped values | 506 | Final (25) | Immutable, inherited context; the `ThreadLocal` replacement for MDC-like data |
| Module import declarations | 511 | Final (25) | `import module java.base;` |
| Compact source files, instance `main` | 512 | Final (25) | Scripts and quick demos (`void main()`, `IO.println`) |
| Flexible constructor bodies | 513 | Final (25) | Validate, and even assign fields, *before* `super(…)` |
| Compact object headers | 519 | Product flag (25) | `-XX:+UseCompactObjectHeaders`: 8-byte headers (§9 measures it) |
| Structured concurrency | 505 | Fifth preview (25) | `StructuredTaskScope.open()` + joiners; fail-fast fan-out |
| Primitive types in patterns | 507 | Third preview (25) | `case int s when s >= 500`; `long instanceof int` as an exact-range test |
| Stable values | 502 | Preview (25) ⚠ | Lazily initialized constants (API reshaped after 25 ⚠ verify) |
| Value classes (Valhalla) | 401 | **Not in 25** (EA builds) ⚠ | Flattened records in arrays would close much of §9's gap |

Listing 2.5 exercises the 22–25 features that change LLD code. It's compiled with `--release 25 --enable-preview` and `-Xlint:all,-preview`; every other lint stays an error.

```java
// Java25Delta.java - Java 22-25 features that change LLD code (javac --release 25 --enable-preview)
import module java.base;                                     // JEP 511, final in 25: one import for java.base

import java.util.concurrent.StructuredTaskScope.Subtask;

public final class Java25Delta {

    // ===== JEP 513 (final in 25): flexible constructor bodies ===================================

    static class Account {
        final String id;

        Account(String id) {
            this.id = id;
            onCreated();                                       // overridable call from a constructor: the classic trap
        }

        void onCreated() {}
    }

    static final class PremiumAccount extends Account {
        final long limitCents;
        final List<String> seen = new ArrayList<>();          // initialisers still run AFTER super(...)

        PremiumAccount(String id, long limitCents) {
            if (limitCents <= 0) throw new IllegalArgumentException("limit must be positive");  // before super()
            this.limitCents = limitCents;                      // field assigned before super(): JEP 513
            super(id);
        }

        @Override void onCreated() {
            System.out.println("  override called from super(): limitCents=" + limitCents + " (assigned after super(), it reads 0)"
                    + ", seen=" + seen + " (initialisers have not run yet)");
        }
    }

    // ===== JEP 456 (final in 22): unnamed variables and patterns ================================

    sealed interface SeatState permits Free, Held, Booked {}
    record Free() implements SeatState {}
    record Held(long token, String user) implements SeatState {}
    record Booked(long token, String user, String paymentId) implements SeatState {}

    static String owner(SeatState s) {
        return switch (s) {
            case Free _ -> "-";
            case Held(_, String user) -> user;                 // ignore the token, bind only what is used
            case Booked(_, String user, _) -> user;
        };
    }

    // ===== JEP 507 (third preview in 25): primitive types in patterns ===========================

    static String classify(int httpStatus) {
        return switch (httpStatus) {
            case 200, 201, 204 -> "ok";
            case int s when s >= 500 -> "retry with backoff (" + s + ")";
            case int s when s == 429 -> "throttled: honour Retry-After";
            case int s -> "fail fast (" + s + ")";
        };
    }

    // ===== JEP 506 (final in 25) + JEP 505 (fifth preview in 25) ================================

    static final ScopedValue<String> REQUEST_ID = ScopedValue.newInstance();

    static int quote(boolean failPricing) throws InterruptedException {
        try (var scope = StructuredTaskScope.open()) {        // default joiner: all must succeed
            Subtask<Integer> seats = scope.fork(() -> {
                try {
                    Thread.sleep(failPricing ? 5_000 : 10);
                } catch (InterruptedException e) {
                    System.out.println("  seats subtask cancelled (" + REQUEST_ID.get() + ")");  // inherited value
                    throw e;
                }
                return 3;
            });
            Subtask<Integer> price = scope.fork(() -> {
                if (failPricing) throw new IllegalStateException("pricing down");
                return 1_250;
            });
            scope.join();                                      // throws FailedException if any subtask failed
            return seats.get() * price.get();
        }
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.println("== JEP 513 flexible constructor bodies ==");
        new PremiumAccount("acct-1", 500_00);
        try {
            new PremiumAccount("acct-2", 0);
        } catch (IllegalArgumentException _) {                 // JEP 456: unnamed catch parameter
            System.out.println("  PremiumAccount(limit=0) rejected before Account() ran");
        }

        System.out.println("== JEP 456 unnamed patterns ==");
        for (SeatState s : List.of(new Free(), new Held(7, "alice"), new Booked(8, "bob", "pay-1")))
            System.out.println("  owner(" + s + ") = " + owner(s));

        System.out.println("== JEP 507 primitive patterns (preview) ==");
        for (int code : new int[] {204, 429, 503, 404}) System.out.println("  " + code + " -> " + classify(code));
        long big = 3_000_000_000L, small = 42L;
        System.out.println("  3_000_000_000L instanceof int -> " + (big instanceof int) + ";  42L instanceof int -> " + (small instanceof int));

        System.out.println("== JEP 506 ScopedValue + JEP 505 StructuredTaskScope (preview) ==");
        ScopedValue.where(REQUEST_ID, "req-7").call(() -> {
            System.out.println("  quote = " + quote(false));
            try {
                quote(true);
            } catch (StructuredTaskScope.FailedException e) {
                System.out.println("  quote failed fast: " + e.getCause().getMessage());
            }
            return null;
        });
        System.out.println("  outside the scope, REQUEST_ID.isBound() = " + REQUEST_ID.isBound());

        System.out.println("== Java 21 reminders: sequenced collections + 24: stream gatherers ==");
        List<Integer> seats = List.of(4, 8, 15, 16, 23, 42);
        System.out.println("  getFirst=" + seats.getFirst() + " getLast=" + seats.getLast() + " reversed=" + seats.reversed());
        System.out.println("  windowSliding(3) sums = " + seats.stream().gather(Gatherers.windowSliding(3))
                .map(w -> w.stream().mapToInt(Integer::intValue).sum()).toList());
        System.out.println("SELF-TEST OK");
    }
}
```

**Output (verified):**

```text
== JEP 513 flexible constructor bodies ==
  override called from super(): limitCents=50000 (assigned after super(), it reads 0), seen=null (initialisers have not run yet)
  PremiumAccount(limit=0) rejected before Account() ran
== JEP 456 unnamed patterns ==
  owner(Free[]) = -
  owner(Held[token=7, user=alice]) = alice
  owner(Booked[token=8, user=bob, paymentId=pay-1]) = bob
== JEP 507 primitive patterns (preview) ==
  204 -> ok
  429 -> throttled: honour Retry-After
  503 -> retry with backoff (503)
  404 -> fail fast (404)
  3_000_000_000L instanceof int -> false;  42L instanceof int -> true
== JEP 506 ScopedValue + JEP 505 StructuredTaskScope (preview) ==
  quote = 3750
  seats subtask cancelled (req-7)
  quote failed fast: pricing down
  outside the scope, REQUEST_ID.isBound() = false
== Java 21 reminders: sequenced collections + 24: stream gatherers ==
  getFirst=4 getLast=42 reversed=[42, 23, 16, 15, 8, 4]
  windowSliding(3) sums = [27, 39, 54, 81]
SELF-TEST OK
```

Points the output proves:

- **JEP 513 changes what an overridable call from a constructor sees.** With the field assigned *before* `super(id)`, the override reads `limitCents=50000` instead of `0`. Field *initializers* (`seen`) still run after `super()`, so it reads `null`. Calling overridable methods from constructors remains a smell. JEP 513 narrows the hazard; it doesn't remove it.
- **Structured concurrency fails fast and cancels siblings.** When pricing throws, the seats subtask is interrupted *before* `join()` rethrows (its "cancelled" line prints first). The subtask still sees the parent's `ScopedValue` (`req-7`), and outside the scope the value is unbound.
- **`long instanceof int` is an exact-range test**, not a cast: `3_000_000_000L instanceof int` is `false`.

### 8.2 C++20/23, with the library-availability matrix

```cpp
// cpp23_delta.cpp - C++20/23 features that change LLD code: expected, deducing this, ranges, jthread scopes
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <exception>
#include <expected>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <ranges>
#include <stdexcept>
#include <stop_token>
#include <string>
#include <thread>
#include <utility>
#include <vector>

using namespace std::chrono_literals;

// ===== std::expected with monadic chaining (C++23) =========================================

enum class Err { Empty, NotNumber, OutOfRange };
constexpr const char* name(Err e) {
    switch (e) {
        case Err::Empty: return "Empty";
        case Err::NotNumber: return "NotNumber";
        case Err::OutOfRange: return "OutOfRange";
    }
    std::unreachable();  // C++23: every enumerator is handled above
}

std::expected<std::string, Err> non_empty(std::string s) {
    if (s.empty()) return std::unexpected(Err::Empty);
    return s;
}
std::expected<int, Err> to_int(const std::string& s) {
    int v = 0;
    for (char c : s) {
        if (c < '0' || c > '9') return std::unexpected(Err::NotNumber);
        v = v * 10 + (c - '0');
        if (v > 10'000) return std::unexpected(Err::OutOfRange);
    }
    return v;
}
std::expected<int, Err> seat_count(std::string raw) {
    return non_empty(std::move(raw)).and_then(to_int).transform([](int n) { return n * 2; });  // no if-ladder
}

// ===== Deducing this (C++23): one fluent setter for lvalue and rvalue builders, no CRTP ===

struct ShowConfig {
    std::string title;
    int seats = 0;
    template <class Self>
    auto&& with_title(this Self&& self, std::string t) {
        self.title = std::move(t);
        return std::forward<Self>(self);
    }
    template <class Self>
    auto&& with_seats(this Self&& self, int n) {
        self.seats = n;
        return std::forward<Self>(self);
    }
};

// ===== A minimal structured scope on jthread + stop_source (C++20) ==========================

class TaskScope {  // fork -> join -> first failure cancels the siblings; destructor never leaks a thread
    std::stop_source stop_;
    std::mutex m_;
    std::exception_ptr first_error_;
    std::vector<std::jthread> threads_;

public:
    template <class T, class F>
    std::shared_ptr<std::optional<T>> fork(F f) {
        auto slot = std::make_shared<std::optional<T>>();
        threads_.emplace_back([this, slot, f = std::move(f)] {
            try {
                *slot = f(stop_.get_token());
            } catch (...) {
                std::scoped_lock lock(m_);
                if (!first_error_) first_error_ = std::current_exception();
                stop_.request_stop();  // cancel the siblings
            }
        });
        return slot;
    }
    void join() {
        for (auto& t : threads_) t.join();
        threads_.clear();
        if (first_error_) std::rethrow_exception(first_error_);
    }
    ~TaskScope() {
        stop_.request_stop();  // jthread destructors then join
    }
};

/** Interruptible sleep: returns false if cancellation arrived first. */
bool sleep_for(std::stop_token st, std::chrono::milliseconds d) {
    std::mutex m;
    std::condition_variable_any cv;
    std::unique_lock lock(m);
    cv.wait_for(lock, st, d, [] { return false; });  // returns pred(), NOT "was stop requested"
    return !st.stop_requested();
}

int quote(bool fail_pricing) {
    TaskScope scope;
    auto seats = scope.fork<int>([&](std::stop_token st) {
        if (!sleep_for(st, fail_pricing ? 5'000ms : 10ms)) {
            std::println("  seats subtask cancelled");
            throw std::runtime_error("cancelled");
        }
        return 3;
    });
    auto price = scope.fork<int>([&](std::stop_token) -> int {
        if (fail_pricing) throw std::runtime_error("pricing down");
        return 1'250;
    });
    scope.join();
    return **seats * **price;
}

int main() {
    std::println("== std::expected + and_then/transform ==");
    for (std::string raw : {"21", "", "2x", "99999"}) {
        const auto r = seat_count(raw);
        std::println("  seat_count('{}') -> {}", raw, r ? std::to_string(*r) : std::string("error ") + name(r.error()));
    }

    std::println("== deducing this ==");
    ShowConfig a;
    a.with_title("Dune").with_seats(120);  // lvalue chain mutates a
    auto b = ShowConfig{}.with_title("Arrival").with_seats(80);  // rvalue chain moves out
    std::println("  a = {} / {}   b = {} / {}", a.title, a.seats, b.title, b.seats);

    std::println("== ranges (C++23): enumerate, zip, slide, to ==");
    const std::vector<int> seats{4, 8, 15, 16, 23, 42};
    const std::vector<std::string> rows{"A", "B", "C", "D", "E", "F"};
#if defined(__cpp_lib_ranges_enumerate)
    for (auto [i, s] : std::views::enumerate(seats) | std::views::take(2)) std::println("  enumerate: #{} -> {}", i, s);
#else
    for (std::size_t i = 0; i < 2; ++i) std::println("  enumerate: #{} -> {} (fallback: no __cpp_lib_ranges_enumerate)", i, seats[i]);
#endif
    for (auto [r, s] : std::views::zip(rows, seats) | std::views::drop(4)) std::println("  zip: row {} has {} seats", r, s);
#if defined(__cpp_lib_ranges_slide)
    auto sums = seats | std::views::slide(3) | std::views::transform([](auto w) {
                    int t = 0;
                    for (int x : w) t += x;
                    return t;
                }) |
                std::ranges::to<std::vector>();
#else
    std::vector<int> sums;  // fallback: no __cpp_lib_ranges_slide
    for (std::size_t i = 0; i + 3 <= seats.size(); ++i) sums.push_back(seats[i] + seats[i + 1] + seats[i + 2]);
#endif
    std::string joined;
    for (int x : sums) joined += (joined.empty() ? "" : ", ") + std::to_string(x);
    std::println("  slide(3) sums = [{}]", joined);

    std::println("== move_only_function + to_underlying ==");
    enum class Level : std::uint8_t { Info = 2, Warn = 3 };
#if defined(__cpp_lib_move_only_function)
    std::move_only_function<int()> task = [p = std::make_unique<int>(7)] { return *p * 6; };  // std::function can't hold this
    std::println("  move-only task -> {};  to_underlying(Level::Warn) = {}", task(), std::to_underlying(Level::Warn));
#else
    std::println("  no __cpp_lib_move_only_function in this library;  to_underlying(Level::Warn) = {}",
                 std::to_underlying(Level::Warn));
#endif

    std::println("== structured scope on jthread + stop_source ==");
    std::println("  quote = {}", quote(false));
    try {
        quote(true);
    } catch (const std::exception& e) {
        std::println("  quote failed fast: {}", e.what());
    }
    std::println("SELF-TEST OK");
}
```

**Output, GCC 16.2 / libstdc++ (verified):**

```text
== std::expected + and_then/transform ==
  seat_count('21') -> 42
  seat_count('') -> error Empty
  seat_count('2x') -> error NotNumber
  seat_count('99999') -> error OutOfRange
== deducing this ==
  a = Dune / 120   b = Arrival / 80
== ranges (C++23): enumerate, zip, slide, to ==
  enumerate: #0 -> 4
  enumerate: #1 -> 8
  zip: row E has 23 seats
  zip: row F has 42 seats
  slide(3) sums = [27, 39, 54, 81]
== move_only_function + to_underlying ==
  move-only task -> 42;  to_underlying(Level::Warn) = 3
== structured scope on jthread + stop_source ==
  quote = 3750
  seats subtask cancelled
  quote failed fast: pricing down
SELF-TEST OK
```

**Output, Clang 21.1 / libc++ (verified; feature-test macros select the fallbacks):**

```text
== std::expected + and_then/transform ==
  seat_count('21') -> 42
  seat_count('') -> error Empty
  seat_count('2x') -> error NotNumber
  seat_count('99999') -> error OutOfRange
== deducing this ==
  a = Dune / 120   b = Arrival / 80
== ranges (C++23): enumerate, zip, slide, to ==
  enumerate: #0 -> 4 (fallback: no __cpp_lib_ranges_enumerate)
  enumerate: #1 -> 8 (fallback: no __cpp_lib_ranges_enumerate)
  zip: row E has 23 seats
  zip: row F has 42 seats
  slide(3) sums = [27, 39, 54, 81]
== move_only_function + to_underlying ==
  no __cpp_lib_move_only_function in this library;  to_underlying(Level::Warn) = 3
== structured scope on jthread + stop_source ==
  quote = 3750
  seats subtask cancelled
  quote failed fast: pricing down
SELF-TEST OK
```

**Library availability as measured on this toolchain** (x86_64 Windows, MinGW-w64 targets; libc++ as shipped with Zig 0.16 / LLVM 21 ⚠ your platform may differ):

| Feature | libstdc++ (GCC 16.2) | libc++ (Clang 21.1) | Feature-test macro |
|---|---|---|---|
| `std::expected` + `and_then`/`transform` | ✅ | ✅ | `__cpp_lib_expected` |
| Deducing `this` (explicit object parameter) | ✅ | ✅ | `__cpp_explicit_this_parameter` |
| `views::zip`, `ranges::to` | ✅ | ✅ | `__cpp_lib_ranges_zip`, `__cpp_lib_ranges_to_container` |
| `views::slide` | ✅ | ✅ | `__cpp_lib_ranges_slide` |
| `views::enumerate` | ✅ | ❌ | `__cpp_lib_ranges_enumerate` |
| `std::move_only_function` | ✅ | ❌ | `__cpp_lib_move_only_function` |
| `std::atomic<std::shared_ptr>` | ✅ (`is_lock_free()==false`) | ❌ | `__cpp_lib_atomic_shared_ptr` |
| `std::print` | ✅ (MinGW: link `-lstdc++exp`) | ✅ | `__cpp_lib_print` |
| `std::jthread`, `stop_token`, `latch`, `barrier`, `atomic::wait` | ✅ | ✅ | `__cpp_lib_jthread`, … |
| `hardware_destructive_interference_size` | 64 | 64 | `__cpp_lib_hardware_interference_size` |

**A bug this listing caught in its own first draft.** `std::condition_variable_any::wait_for(lock, stop_token, d, pred)` returns `pred()`, **not** "was stop requested". The first version returned `!wait_for(…)` from a predicate that is always `false`, so cancellation was never reported. The fix checks `st.stop_requested()` after the wait. Read the return-value clause of every wait API.

---

## 9. The other "data-oriented": memory layout

"Data-oriented design" also names a second, older idea from game and HPC engineering (Mike Acton, CppCon 2014): **organize data for how the hardware reads it.** The term collision is worth naming in an interview. Goetz's DOP is about *correctness* (types); Acton's DOD is about *cache lines*. They pull in different directions for hot loops.

```java
// AosVsSoa.java - the OTHER data-oriented design: memory layout decides hot-loop speed
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.lang.management.ManagementFactory;
import java.util.ArrayList;
import java.util.List;
import java.util.SplittableRandom;

public final class AosVsSoa {

    record Particle(double x, double y, double vx, double vy) {}

    static final int N = 2_000_000;

    /** Four accumulators so the loop is memory-bound, not bound by FP-add latency. */
    static double sumAos(Particle[] ps) {
        double a = 0, b = 0, c = 0, d = 0;
        int i = 0;
        for (; i + 3 < ps.length; i += 4) {
            a += ps[i].x();
            b += ps[i + 1].x();
            c += ps[i + 2].x();
            d += ps[i + 3].x();
        }
        for (; i < ps.length; i++) a += ps[i].x();
        return a + b + c + d;
    }

    static double sumSoa(double[] xs) {
        double a = 0, b = 0, c = 0, d = 0;
        int i = 0;
        for (; i + 3 < xs.length; i += 4) {
            a += xs[i];
            b += xs[i + 1];
            c += xs[i + 2];
            d += xs[i + 3];
        }
        for (; i < xs.length; i++) a += xs[i];
        return a + b + c + d;
    }

    /** Immutable records: an "update" is an allocation per element. */
    static void stepAos(Particle[] ps, double dt) {
        for (int i = 0; i < ps.length; i++) {
            Particle p = ps[i];
            ps[i] = new Particle(p.x() + p.vx() * dt, p.y() + p.vy() * dt, p.vx(), p.vy());
        }
    }

    static void stepSoa(double[] xs, double[] ys, double[] vxs, double[] vys, double dt) {
        for (int i = 0; i < xs.length; i++) {
            xs[i] += vxs[i] * dt;
            ys[i] += vys[i] * dt;
        }
    }

    static double sink;

    static double bestMillis(Runnable r) {
        for (int i = 0; i < 3; i++) r.run();                  // warm-up: let C2 compile the loop
        long best = Long.MAX_VALUE;
        for (int i = 0; i < 7; i++) {
            long t0 = System.nanoTime();
            r.run();
            best = Math.min(best, System.nanoTime() - t0);
        }
        return best / 1e6;
    }

    static long heapUsed() {
        for (int i = 0; i < 3; i++) System.gc();
        return ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed();
    }

    static Particle[] particles(long seed) {
        SplittableRandom rnd = new SplittableRandom(seed);
        Particle[] ps = new Particle[N];
        for (int i = 0; i < N; i++) ps[i] = new Particle(rnd.nextDouble(), rnd.nextDouble(), rnd.nextDouble(), rnd.nextDouble());
        return ps;
    }

    /** Bytes per particle (record + its array slot) and the in-order AoS scan under this JVM's flags. */
    static String layoutReport() {
        long before = heapUsed();
        Particle[] ps = particles(42);
        long after = heapUsed();
        double ms = bestMillis(() -> sink += sumAos(ps));
        return String.format("%.1f B/particle, AoS in-order sum(x) %.2f ms", (after - before) / (double) N, ms);
    }

    public static void main(String[] args) throws IOException, InterruptedException {
        if (args.length == 1 && args[0].equals("child")) {
            System.out.println(layoutReport());
            return;
        }
        System.out.printf("N = %,d particles, best of 7 after 3 warm-ups (JDK %s)%n", N, Runtime.version());
        System.out.println("== Footprint: 12-byte vs 8-byte object headers (JEP 519) ==");
        System.out.println("default headers          : " + layoutReport());
        List<String> cmd = new ArrayList<>(List.of(ProcessHandle.current().info().command().orElseThrow(),
                "-XX:+UseCompactObjectHeaders", "-cp", System.getProperty("java.class.path"), "AosVsSoa", "child"));
        Process child = new ProcessBuilder(cmd).redirectErrorStream(true).start();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(child.getInputStream()))) {
            System.out.println("-XX:+UseCompactObjectHeaders: " + r.readLine());
        }
        if (child.waitFor() != 0) throw new IllegalStateException("child JVM failed");

        Particle[] inOrder = particles(7);
        Particle[] shuffled = inOrder.clone();                  // same objects, references in random order
        SplittableRandom rnd = new SplittableRandom(99);
        for (int i = N - 1; i > 0; i--) {
            int j = rnd.nextInt(i + 1);
            Particle t = shuffled[i];
            shuffled[i] = shuffled[j];
            shuffled[j] = t;
        }
        double[] xs = new double[N], ys = new double[N], vxs = new double[N], vys = new double[N];
        for (int i = 0; i < N; i++) {
            xs[i] = inOrder[i].x();
            ys[i] = inOrder[i].y();
            vxs[i] = inOrder[i].vx();
            vys[i] = inOrder[i].vy();
        }
        System.out.println("== Scan one field: sum(x) ==");
        double soa = bestMillis(() -> sink += sumSoa(xs));
        double aos = bestMillis(() -> sink += sumAos(inOrder));
        double shuf = bestMillis(() -> sink += sumAos(shuffled));
        System.out.printf("SoA double[]                 %7.2f ms%n", soa);
        System.out.printf("AoS Particle[] in alloc order %6.2f ms  (%.1fx SoA)%n", aos, aos / soa);
        System.out.printf("AoS Particle[] shuffled refs  %6.2f ms  (%.1fx SoA)%n", shuf, shuf / soa);
        System.out.println("== Update every element: x += vx*dt, y += vy*dt ==");
        double stepSoa = bestMillis(() -> stepSoa(xs, ys, vxs, vys, 1e-3));
        double stepAos = bestMillis(() -> stepAos(inOrder, 1e-3));
        System.out.printf("SoA in place                 %7.2f ms%n", stepSoa);
        System.out.printf("AoS immutable records (alloc) %6.2f ms  (%.1fx SoA)%n", stepAos, stepAos / stepSoa);
        boolean ok = Math.abs(sumSoa(xs) - sumAos(inOrder)) < 1e-6 * N;
        System.out.println(ok ? "SELF-TEST OK (SoA and AoS agree after the same updates)" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**One measured run (JDK 25.0.4.1):**

```text
N = 2,000,000 particles, best of 7 after 3 warm-ups (JDK 25.0.4.1+1-LTS)
== Footprint: 12-byte vs 8-byte object headers (JEP 519) ==
default headers          : 52.3 B/particle, AoS in-order sum(x) 5.86 ms
-XX:+UseCompactObjectHeaders: 44.4 B/particle, AoS in-order sum(x) 4.77 ms
== Scan one field: sum(x) ==
SoA double[]                    1.16 ms
AoS Particle[] in alloc order   5.66 ms  (4.9x SoA)
AoS Particle[] shuffled refs   19.39 ms  (16.7x SoA)
== Update every element: x += vx*dt, y += vy*dt ==
SoA in place                    3.98 ms
AoS immutable records (alloc)  18.19 ms  (4.6x SoA)
SELF-TEST OK (SoA and AoS agree after the same updates)
```

```cpp
// aos_vs_soa.cpp - the OTHER data-oriented design: memory layout decides hot-loop speed
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <functional>
#include <memory>
#include <print>
#include <random>
#include <vector>

struct Particle { double x, y, vx, vy; };  // 32 bytes, stored inline in a vector (no headers, no references)

constexpr std::size_t kN = 2'000'000;
volatile double g_sink = 0;  // defeats dead-code elimination of the measured loops

template <class Get>
double sum4(std::size_t n, Get get) {  // four accumulators: memory-bound, not FP-latency-bound
    double a = 0, b = 0, c = 0, d = 0;
    std::size_t i = 0;
    for (; i + 3 < n; i += 4) {
        a += get(i);
        b += get(i + 1);
        c += get(i + 2);
        d += get(i + 3);
    }
    for (; i < n; ++i) a += get(i);
    return a + b + c + d;
}

double best_millis(const std::function<void()>& f) {
    for (int i = 0; i < 3; ++i) f();
    auto best = std::chrono::nanoseconds::max();
    for (int i = 0; i < 7; ++i) {
        const auto t0 = std::chrono::steady_clock::now();
        f();
        best = std::min(best, std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0));
    }
    return static_cast<double>(best.count()) / 1e6;
}

int main() {
    std::mt19937_64 rng(7);
    std::uniform_real_distribution<double> u(0.0, 1.0);
    std::vector<Particle> aos(kN);
    for (auto& p : aos) p = {u(rng), u(rng), u(rng), u(rng)};
    std::vector<double> xs(kN), ys(kN), vxs(kN), vys(kN);
    for (std::size_t i = 0; i < kN; ++i) {
        xs[i] = aos[i].x;
        ys[i] = aos[i].y;
        vxs[i] = aos[i].vx;
        vys[i] = aos[i].vy;
    }
    std::vector<std::unique_ptr<Particle>> boxed;  // the Java-like layout: one heap object per element
    boxed.reserve(kN);
    for (const auto& p : aos) boxed.push_back(std::make_unique<Particle>(p));
    std::ranges::shuffle(boxed, rng);  // an "aged heap": references no longer follow memory order

    std::println("N = {} particles, sizeof(Particle) = {} B, best of 7 after 3 warm-ups", kN, sizeof(Particle));
    std::println("== Scan one field: sum(x) ==");
    const double soa = best_millis([&] { g_sink = g_sink + sum4(kN, [&](std::size_t i) { return xs[i]; }); });
    const double aos_ms = best_millis([&] { g_sink = g_sink + sum4(kN, [&](std::size_t i) { return aos[i].x; }); });
    const double boxed_ms = best_millis([&] { g_sink = g_sink + sum4(kN, [&](std::size_t i) { return boxed[i]->x; }); });
    std::println("SoA vector<double>              {:7.2f} ms", soa);
    std::println("AoS vector<Particle> contiguous {:7.2f} ms  ({:.1f}x SoA)", aos_ms, aos_ms / soa);
    std::println("vector<unique_ptr> shuffled     {:7.2f} ms  ({:.1f}x SoA)", boxed_ms, boxed_ms / soa);

    std::println("== Update every element in place: x += vx*dt, y += vy*dt ==");
    constexpr double dt = 1e-3;
    const double step_soa = best_millis([&] {
        for (std::size_t i = 0; i < kN; ++i) {
            xs[i] += vxs[i] * dt;
            ys[i] += vys[i] * dt;
        }
    });
    const double step_aos = best_millis([&] {
        for (auto& p : aos) {
            p.x += p.vx * dt;
            p.y += p.vy * dt;
        }
    });
    std::println("SoA                             {:7.2f} ms", step_soa);
    std::println("AoS (touches all 4 fields)      {:7.2f} ms  ({:.1f}x SoA)", step_aos, step_aos / step_soa);

    const double s1 = sum4(kN, [&](std::size_t i) { return xs[i]; });
    const double s2 = sum4(kN, [&](std::size_t i) { return aos[i].x; });
    const bool ok = std::abs(s1 - s2) < 1e-6 * static_cast<double>(kN);
    std::println("{}", ok ? "SELF-TEST OK (SoA and AoS agree after the same updates)" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**One measured run, GCC 16.2:**

```text
N = 2000000 particles, sizeof(Particle) = 32 B, best of 7 after 3 warm-ups
== Scan one field: sum(x) ==
SoA vector<double>                 0.91 ms
AoS vector<Particle> contiguous    3.71 ms  (4.1x SoA)
vector<unique_ptr> shuffled       19.68 ms  (21.6x SoA)
== Update every element in place: x += vx*dt, y += vy*dt ==
SoA                                3.82 ms
AoS (touches all 4 fields)         4.90 ms  (1.3x SoA)
SELF-TEST OK (SoA and AoS agree after the same updates)
```

**One measured run, Clang 21.1:**

```text
N = 2000000 particles, sizeof(Particle) = 32 B, best of 7 after 3 warm-ups
== Scan one field: sum(x) ==
SoA vector<double>                 0.97 ms
AoS vector<Particle> contiguous    3.55 ms  (3.7x SoA)
vector<unique_ptr> shuffled       19.89 ms  (20.5x SoA)
== Update every element in place: x += vx*dt, y += vy*dt ==
SoA                                3.69 ms
AoS (touches all 4 fields)         4.71 ms  (1.3x SoA)
SELF-TEST OK (SoA and AoS agree after the same updates)
```

### 9.1 Reading the layout numbers ⚡

**Footprint matches first principles.**
- A `Particle` record is 32 B of doubles plus a 12 B header (8 B mark word + 4 B compressed class pointer), aligned to **48 B**, plus a 4 B compressed reference in the array: **52 B**. Measured: 52.3.
- With JEP 519's 8 B header it's 40 + 4 = **44 B**. Measured: 44.4 (44.2 on a rerun).
- That's 15% less memory. In-order scans were 4–19% faster across two runs (5.86 → 4.77 ms in the run shown, 4.69 → 4.49 ms on the rerun). Real, but noisier than the footprint.

**Scanning one field is bandwidth-bound.**
- SoA reads 16 MB for 2 M `x` values. AoS drags whole objects through the cache: about 104 MB in Java, or 64 MB as a contiguous C++ `vector<Particle>`.
- The measured ratios (Java 4.6–4.9×, C++ 3.7–4.1× across two runs) track the bytes moved. C++'s ~4× ≈ 32 B / 8 B.
- At 64 MB in 3.7 ms, the C++ AoS loop streams roughly 17 GB/s, the same order as a single core's DRAM bandwidth on this class of laptop. The loop is limited by memory traffic, not by arithmetic.

**Pointer chasing is the real enemy.**
- *Shuffled* references, the shape of an aged heap or of a `vector<unique_ptr<T>>`, cost 16.6–16.7× (Java) and 20–25× (C++) over SoA. Each element becomes a dependent cache miss.
- Java's in-order case looks good only because the TLAB allocated the records contiguously, and a moving collector can keep them that way. You can't rely on that after a long-lived heap is churned.

**Immutability has a price in hot loops.** Updating every element of an array of immutable records means allocating 2 M records per step: 4.6–5.0× slower than in-place SoA. C++ mutating a contiguous AoS in place is only 1.3–1.4× slower than SoA, because the update touches all four fields anyway.

**The L7 synthesis:**
- Records and sealed types for **domain state, messages, keys and results**, where correctness dominates.
- Primitive arrays (SoA) or off-heap buffers for **hot numeric inner loops**: order-book price levels, geo grids, ring buffers, the columnar index in P16.
- Measure before converting. Valhalla's value classes (JEP 401 ⚠ not in 25) aim to flatten records in arrays and dissolve most of this trade-off.

---

## 10. Failure modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | "Impossible" order states in the DB (refunded but never captured) | Rows with contradictory flags | Boolean/nullable model admits 122 illegal shapes (§4.2) | Sealed ADT with per-state data | Review rule: no `isX` boolean pairs on stateful entities |
| F2 | A new state silently treated as "illegal transition" | Runtime errors after a feature launch | `default ->` or a catch-all pattern in the transition switch | Remove `default`; nest exhaustive switches | Lint: forbid `default` in switches over sealed types |
| F3 | `MatchException` in production | Stack trace from a pattern `switch` | Sealed hierarchy changed; dependent module not recompiled | Rebuild dependents; version the module | Sealed hierarchies and their switches live in one module |
| F4 | Duplicate prices in a `HashSet<BigDecimal>` | `2.0` and `2.00` both present | `BigDecimal.equals` is scale-sensitive | Normalize the scale in the value object | `Money` type; never raw `BigDecimal` keys |
| F5 | Cent drift in reports | Totals off by 0.01 | Divide-then-round; `new BigDecimal(double)` | Allocate in minor units; construct from strings | Property test: `sum(allocate(x)) == x` |
| F6 | Cache misses for "equal" keys | `map.get(new Key(bytes))` returns null | Record with an array component compares references | `List`/`ByteBuffer` component or a custom `equals` | Lint: no array components in records |
| F7 | Invariant broken "from outside" | Record contents change after construction | Mutable collection not copied | `List.copyOf` in the compact constructor | Code review checklist |
| F8 | Element "lost" in a `HashSet` | `contains` false, `size` unchanged | Key mutated after insertion | Immutable keys (records) | Keys are value objects, always |
| F9 | Metrics double-counted | Counter is 2× the events | Fragile base class self-use (§3) | Composition + forwarding | Never extend a concrete collection |
| F10 | C++ counter never increments | Derived "override" not called | Name hiding; no virtual dispatch | Composition | `-Woverloaded-virtual`; don't inherit from `std::` types |
| F11 | C++ object loses its extra state on copy | Base-type copy | Slicing | Composition; `= delete` copying through the base | Polymorphic bases: protected copy, virtual dtor |
| F12 | Lost counts under load in a "thread-safe" wrapper | Decorator counter < events | Decorator non-atomic over a concurrent delegate | `LongAdder` / `fetch_add` | The decorator documents its concurrency contract |
| F13 | C++ call resolves to `std::` | Confusing template errors | ADL found `std::apply` for `std::variant` arguments | Rename, or qualify the call | Don't reuse `std` algorithm names for free functions |
| F14 | Wrong results only on Windows | Overflow in "64-bit" math | `long` is 32 bits under LLP64 | `std::int64_t` | `-Werror=overflow`, fixed-width types |
| F15 | A stale typestate handle used again | `oldDraft.add()` after `submit()` succeeds | No linear types | Keep transitions inside the aggregate; `&&` + `bugprone-use-after-move` | Return only the current state from the owner |
| F16 | Golden-file / snapshot tests flap between runs | Same input, different key order in output | `Map.of`/`Set.of`/`Map.copyOf` iteration order is randomized per JVM run (§6.2) | `TreeMap`/`LinkedHashMap` copy + unmodifiable wrapper when order matters | Never assert on immutable-collection iteration order |

---

## 11. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Doesn't <code>sealed</code> violate open/closed?"</b></summary>

**L5:** "Yes, but it's safer."

**Why it fails:** it concedes a false premise. OCP is about the *axis of likely change*, not about every axis.

**L7 defence:** "The expression problem says I can make only one axis cheap. Order states are part of the business rules and change rarely, while operations on them (transition, persist, render, audit) multiply. So I close the kinds and keep operations open. When a state *is* added, the compiler lists every decision that must be made. For pricing rules, where new kinds arrive weekly, I do the opposite: open interface, closed operation."
</details>

<details>
<summary><b>Q2 ⚡ "Why not an <code>enum</code> with fields for the order state?"</b></summary>

**L5:** "An enum is simpler."

**Why it fails:** enum constants are singletons, so per-instance data (`authId`, `capturedAmount`) must live in nullable fields *next to* the enum. That's the L6 model in file 01, and it's what admits illegal combinations.

**L7 defence:** "An enum is perfect for data-less states (an elevator `Direction`, a log `Level`). When each state carries different data, the state is a sum of products: a sealed interface of records, or a `std::variant` of structs. Each variant carries exactly its fields, so 'captured without a capture id' can't be constructed."
</details>

<details>
<summary><b>Q3 ⚡ "Records are immutable. How do you update shared state concurrently?"</b></summary>

**L5:** "Use setters with synchronized."

**Why it fails:** it gives up the immutability that made reasoning easy, and couples the rules to the lock.

**L7 defence:** "The aggregate holds an `AtomicReference<State>`. The rules are a pure `transition(state, cmd)`: read, compute, `compareAndSet(prev, next)`, retry on failure. The CAS compares identity, which is correct because I CAS from the instance I read. Retries are safe because the function is pure. If contention makes retries expensive, I swap in a lock without touching the rules. C++: a mutex around the aggregate, because `atomic<shared_ptr>` isn't lock-free in libstdc++ and missing in libc++."
</details>

<details>
<summary><b>Q4 🔥 "How do you represent and compare money?"</b></summary>

**L5:** "`double` with two decimals" or "`BigDecimal`".

**Why it fails:** `double` loses cents. Raw `BigDecimal` has scale-sensitive `equals` and no currency.

**L7 defence:** "A `Money` value object: amount plus currency. In Java, a `BigDecimal` normalized to the currency's fraction digits with `RoundingMode.UNNECESSARY`, so equals means same money and precision loss is rejected at the boundary. In C++, integer minor units with overflow-checked arithmetic. Rounding modes are explicit per operation (tax, FX). Splitting uses largest-remainder allocation so parts sum to the whole."
</details>

<details>
<summary><b>Q5 🧊 "C++: <code>std::variant</code> or a virtual hierarchy?"</b></summary>

**L5:** "Virtual functions are standard OOP."

**Why it fails:** it ignores the closed/open decision, value semantics and cost.

**L7 defence:** "`std::variant` for a closed set:
- value semantics, no heap allocation;
- size = largest alternative + index;
- `std::visit` is a jump table, and exhaustiveness is checked at compile time;
- recursive alternatives need indirection;
- after an assignment throws, the variant can be `valueless_by_exception`.

Virtual hierarchies for open sets and plugin boundaries, with a virtual destructor and copying deleted or protected to avoid slicing."
</details>

<details>
<summary><b>Q6 ⚡ "When is inheritance the right answer?"</b></summary>

**L5:** "When there's an is-a relationship."

**Why it fails:** `Stack` *is-a* `Vector` by that test, and inherits `add(0, x)`, which breaks LIFO (Listing 2.2).

**L7 defence:** "When the base class is designed and documented for extension (its self-use is specified), the subtypes honour its behavioural contract (LSP: pre-conditions no stronger, post-conditions no weaker), and I control both sides. `AbstractQueuedSynchronizer` is the model: a template method with documented hooks. Otherwise composition, with forwarding if I need the full interface."
</details>

---

## 12. Invariants checklist

- [ ] Every stateful entity's state is a closed set (sealed/variant); each variant carries only its own data.
- [ ] Transition functions are pure, total, exhaustive, and have no `default`; idempotent replays are explicit cases.
- [ ] Value objects validate in the constructor/factory and normalize their representation (money scale, lower-cased email).
- [ ] No `double` for money; rounding mode named; allocation preserves the total.
- [ ] Identifiers are distinct types; no two `String` parameters of different meaning are adjacent.
- [ ] Records copy mutable components; no array components.
- [ ] Extension uses composition unless the base class documents its self-use.
- [ ] Decorators match the concurrency contract of what they wrap.
- [ ] C++: no inheritance from `std::` containers; fixed-width integers; free functions not named after `std` algorithms.
- [ ] Hot numeric loops are measured before choosing records vs primitive arrays.

---

## 13. References

- David L. Parnas, "On the Criteria To Be Used in Decomposing Systems into Modules", *CACM* 1972. <https://doi.org/10.1145/361598.361623>
- Philip Wadler, "The Expression Problem", 1998. <https://homepages.inf.ed.ac.uk/wadler/papers/expression/expression.txt>
- Barbara Liskov and Jeannette Wing, "A Behavioral Notion of Subtyping", *TOPLAS* 1994. <https://doi.org/10.1145/197320.197383>
- Robert C. Martin, "The Single Responsibility Principle", 2014. <https://blog.cleancoder.com/uncle-bob/2014/05/08/SingleReponsibilityPrinciple.html>
- Brian Goetz, "Data Oriented Programming in Java", InfoQ, 2022. <https://www.infoq.com/articles/data-oriented-programming-java/>
- Yaron Minsky, "Effective ML Revisited" ("make illegal states unrepresentable"). <https://blog.janestreet.com/effective-ml-revisited/>
- Alexis King, "Parse, don't validate", 2019. <https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/>
- Martin Fowler, *Patterns of Enterprise Application Architecture*: Money. <https://martinfowler.com/eaaCatalog/money.html>
- Joshua Bloch, *Effective Java*, 3rd ed.: Items 17–20 (mutability, composition, inheritance, interfaces), 60 (avoid `float`/`double` for exact answers).
- OpenJDK JEPs: 395, 409, 440, 441, 456, 485, 491, 502, 505, 506, 507, 511, 512, 513, 519, 401. <https://openjdk.org/jeps/0>
- WG21 papers: P0718 (atomic `shared_ptr`) <https://wg21.link/p0718>, P0847 (deducing `this`) <https://wg21.link/p0847>, P0323 (`std::expected`) <https://wg21.link/p0323>.
- libc++ C++23 status. <https://libcxx.llvm.org/Status/Cxx23.html>
- Mike Acton, "Data-Oriented Design and C++", CppCon 2014. <https://www.youtube.com/watch?v=rX0ItVEVjHc>
- In this KB: [01 · Rubric](01-l5-vs-l6-vs-l7-lld-and-machine-coding-evaluation-rubric.md) (where the sealed seat state earns its keep) · [03 · Concurrency primitives](03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) (CAS identity, false sharing, clocks).
