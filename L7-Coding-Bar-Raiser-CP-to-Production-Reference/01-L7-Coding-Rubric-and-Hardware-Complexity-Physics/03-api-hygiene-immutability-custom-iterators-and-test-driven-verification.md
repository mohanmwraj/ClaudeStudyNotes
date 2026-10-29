# API Hygiene, Immutability, Custom Iterators and Test-Driven Verification

> **Folder 01 · File 3 of 3** — turning a correct contest solution into a component other engineers can call safely, and proving it correct in a way an interviewer can watch.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, run on JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, flags as in File 01).

| Listing | File | What it proves |
|---|---|---|
| 3.1 | `RepExposure.java` | A caller breaks an interval set's invariant through a leaked list; the L7 version owns its invariant. Snapshot vs live view; records with array fields compare by identity |
| 3.2 | `rep_exposure.cpp` | The same in C++: a private-constructor value type with an `expected` factory, a lazy `const` view, pointer vs value equality, and an expected-failure build where a defaulted `==` over `std::span` is deleted |
| 3.3 | `MergeIterator.java` | A lazy k-way merge as a real `Iterator`/`Stream`: `O(k)` memory, stable ties, works on infinite sources, fails loudly on unsorted input |
| 3.4 | `merge_iterator.cpp` | The same as a C++23 `std::ranges` input view, with concept checks (`static_assert`) that prove what the type promises |
| 3.5 | `StressOracle.java` | CP's "stress test" as a production differential-testing harness: random small inputs, an oracle, automatic shrinking to a minimal counterexample, oracle-free properties |
| 3.6 | `stress_oracle.cpp` | The same harness in C++; it finds the same bugs at the same trials and shrinks them to the same counterexamples |

**Verification.** Every listing was extracted from this file, compiled and run; outputs are spliced from those runs. Everything is **Output (verified)** except the two timing lines in Listings 3.3/3.4 (one measured run).

---

## 0. Orientation

File 1 showed that a Staff packet is graded on the contract as much as the algorithm. This file is about the artefact itself: the **API surface** you leave behind and the **evidence** you produce that it works. The contest habits being replaced are useful under contest conditions and actively harmful in a codebase:

| Contest habit | Why it was fine in a contest | Why it fails in a Staff round | L7 replacement |
|---|---|---|---|
| Return the internal array or list | One caller (you), one run | Any caller can break the invariant, and the bug surfaces later, elsewhere | Immutable value types; return snapshots or read-only views; document which |
| Public mutable fields, setters | Speed of writing | Invariants can't be enforced if anything can write anything | Validate in constructors / factories; no setters on value types |
| `int[]` / `pair<int,int>` everywhere | Fast to type | No names, no validation, no equality semantics you chose | `record Interval(long start, long end)`; a C++ class with a factory |
| Materialize everything into a vector | Input fits in memory | Streams, infinite sources, 100 TB inputs | Lazy iterators / ranges with `O(k)` state |
| "Passed samples, submit" | The judge tests for you | Nobody tests for you; the interviewer watches how you verify | Edge-case table, oracle, randomized differential test, shrinking, properties |
| Brute-force stress test kept private | Private debugging tool | — it is the right tool, just never shown | Show it: the oracle-plus-shrinker *is* the senior answer to "how do you know it's correct?" |

---

## 1. First principles

### 1.1 Representation invariant and abstraction function

Every data structure is a representation (fields) plus two things you should be able to state in one sentence each:

* the **representation invariant**: which field values are legal (for an interval set: "sorted by start, pairwise disjoint, non-adjacent, each `start < end`");
* the **abstraction function**: what a legal representation *means* (the union of the intervals as a set of points).

Every public method may assume the invariant on entry and must re-establish it on exit. That is the whole correctness argument, and it is local. It only works if **nothing outside the class can write the representation**. A getter that returns the internal list breaks this: the invariant now depends on every caller in the codebase. This is Liskov and Guttag's "representation exposure", and Bloch's *Effective Java* Items 17 ("minimize mutability") and 50 ("make defensive copies when needed").

### 1.2 The immutability spectrum

| Kind | Java | C++ | Reflects later changes? | Cost |
|---|---|---|---|---|
| Mutable reference | `List<T>` returned as-is | `std::vector<T>&` | yes, and the caller can write | free, unsafe |
| Read-only **view** | `Collections.unmodifiable*`, `sequencedValues()` wrapped | `const T&`, `std::span<const T>`, a `views::transform` over `const` data | **yes** (live) | `O(1)`; lifetime and iteration hazards |
| Immutable **snapshot** | `List.copyOf`, records of immutables | return by value (`std::vector<T>`) | no | `O(n)` copy |
| Persistent structure | (libraries) PCollections, Vavr | (libraries) immer | no, and cheap new versions | `O(log n)` per update, structural sharing |

The L7 skill is choosing deliberately and saying which one an API returns. "Unmodifiable" in Java is not "immutable": a view reflects later changes, and a list of mutable objects can still be mutated through its elements.

### 1.3 Make illegal states unrepresentable

Validation belongs at the **one** place a value is created: a record's compact constructor, a private constructor behind a factory that returns `std::expected`, a `std::size_t` instead of an `int` that might be negative. Downstream code then never re-checks, and a reviewer can verify the invariant by reading one function. Java records give you value semantics (`equals`, `hashCode`, `toString`) for free, **but only shallowly**. A record with an array component compares the array by identity and hands out the array itself (Listing 3.1).

### 1.4 Iterator contracts

| Property | Java `Iterator` | C++ ranges |
|---|---|---|
| Protocol | `hasNext()` / `next()`; `next()` past the end throws `NoSuchElementException` | `begin()`, `end()` (a **sentinel** may have a different type), `*it`, `++it`, `it == end` |
| Single vs multi-pass | Single-pass by contract | Categories: `input` (single pass) ⊂ `forward` (multi-pass) ⊂ `bidirectional` ⊂ `random_access` ⊂ `contiguous`; **concepts** check them at compile time |
| Concurrent modification | Collections are **fail-fast** (best-effort `ConcurrentModificationException` from a `modCount` check); concurrent collections are **weakly consistent** (never throw, may or may not show concurrent updates) | No check at all. Each container documents **iterator invalidation** rules, and using an invalidated iterator is undefined behaviour |
| Laziness | Iterators and `Stream`s are pull-based and lazy | Views are lazy; `std::views::take` works on infinite ranges |

A custom iterator is the right abstraction whenever the consumer should control the pace: merging, paginating, streaming, generating. It is also the unit that **Extension B** (bounded memory) and **Extension C** (cursor-based pagination across shards) are built from.

### 1.5 Verification, as a ladder

| Rung | What it catches | Cost in an interview |
|---|---|---|
| Dry-run the example | Gross logic errors | 1 minute |
| Edge-case table (empty, one, two equal, extremes, overflow, ties, invalid) | Boundary bugs | 2–3 minutes aloud |
| Invariant assertions in code | Representation drift | Lines you write anyway |
| **Differential test vs an oracle** on random **small** inputs | Most remaining bugs | Describe in 30 s; write in 5 min if asked |
| **Shrinking** to a minimal counterexample | Turns "it failed on this 600-element input" into `[-1]` | Part of the harness |
| **Properties** (idempotence, order-independence, conservation) | Bugs where no oracle exists | Describe in 30 s |

Competitive programmers already own the expensive rung: they write brute-force checkers and random generators to debug wrong answers. The L7 move is to make that a reusable harness, add shrinking and properties, and **say it out loud** when the interviewer asks "how do you know it's correct?" (QuickCheck, Claessen and Hughes, 2000; Hypothesis; jqwik.)

---

## 2. Representation exposure, demonstrated

### 2.1 Listing 3.1 — Java

```java
// RepExposure.java - an interval set whose invariant a caller can break (L5) vs one it cannot (L7); records with arrays.
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.ConcurrentModificationException;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.SequencedCollection;
import java.util.Set;
import java.util.TreeMap;

public final class RepExposure {

    // ===================================================================== L5: the representation escapes
    /** Invariant (unchecked, undocumented): sorted, disjoint, half-open [l, r). */
    static final class CpIntervalSet {
        private final List<int[]> intervals = new ArrayList<>();

        List<int[]> getIntervals() { return intervals; }  // hands out the representation itself

        void add(int l, int r) {
            List<int[]> out = new ArrayList<>();
            int i = 0;
            while (i < intervals.size() && intervals.get(i)[1] < l) out.add(intervals.get(i++));
            while (i < intervals.size() && intervals.get(i)[0] <= r) {
                l = Math.min(l, intervals.get(i)[0]);
                r = Math.max(r, intervals.get(i)[1]);
                i++;
            }
            out.add(new int[] {l, r});
            while (i < intervals.size()) out.add(intervals.get(i++));
            intervals.clear();
            intervals.addAll(out);
        }

        long covered() {  // correct only while the invariant holds
            long sum = 0;
            for (int[] iv : intervals) sum += iv[1] - iv[0];
            return sum;
        }

        String show() { return intervals.stream().map(Arrays::toString).toList().toString(); }
    }

    // ===================================================================== L7: the invariant is owned
    /** Half-open [start, end). Immutable; validated once; equals/hashCode by value for free. */
    record Interval(long start, long end) {
        Interval {
            if (start >= end) throw new IllegalArgumentException("need start < end, got [" + start + ", " + end + ")");
        }
        long length() { return end - start; }
    }

    /** Sorted, disjoint, non-adjacent intervals keyed by start. add: O(log n + merged). covers: O(log n). */
    static final class IntervalSet {
        private final TreeMap<Long, Interval> byStart = new TreeMap<>();

        void add(Interval iv) {
            long start = iv.start(), end = iv.end();
            Map.Entry<Long, Interval> left = byStart.floorEntry(start);
            if (left != null && left.getValue().end() >= start) {           // overlaps or touches on the left
                start = left.getKey();
                end = Math.max(end, left.getValue().end());
                byStart.remove(left.getKey());
            }
            for (Map.Entry<Long, Interval> e = byStart.ceilingEntry(start); e != null && e.getKey() <= end;
                 e = byStart.ceilingEntry(start)) {
                end = Math.max(end, e.getValue().end());
                byStart.remove(e.getKey());
            }
            byStart.put(start, new Interval(start, end));
        }

        boolean covers(long x) {
            Map.Entry<Long, Interval> e = byStart.floorEntry(x);
            return e != null && x < e.getValue().end();
        }

        long covered() { return byStart.values().stream().mapToLong(Interval::length).sum(); }

        /** Point-in-time copy: unaffected by later adds. O(n). */
        List<Interval> snapshot() { return List.copyOf(byStart.values()); }

        /** Live read-only view: O(1) to create, reflects later adds, fail-fast if iterated across an add. */
        SequencedCollection<Interval> view() { return Collections.unmodifiableSequencedCollection(byStart.sequencedValues()); }
    }

    // ===================================================================== records do not deep-copy
    record PathArray(int[] nodes) {}  // shallow: equals compares array identity, accessor leaks the array

    record Path(List<Integer> nodes) {
        Path { nodes = List.copyOf(nodes); }  // defensive, immutable copy; equals/hashCode by content
    }

    public static void main(String[] args) {
        System.out.println("L5 CpIntervalSet");
        CpIntervalSet cp = new CpIntervalSet();
        cp.add(1, 5);
        cp.add(10, 15);
        System.out.printf("    after add [1,5) [10,15): %s covered=%d%n", cp.show(), cp.covered());
        cp.getIntervals().get(0)[1] = 12;  // a caller "just adjusting" the first interval
        System.out.printf("    caller writes getIntervals().get(0)[1] = 12: %s covered=%d (true union [1,15) = 14)%n",
                cp.show(), cp.covered());
        cp.add(20, 25);
        System.out.printf("    the next add inherits the corruption: %s covered=%d (true 19)%n", cp.show(), cp.covered());

        System.out.println("L7 IntervalSet");
        IntervalSet set = new IntervalSet();
        set.add(new Interval(1, 5));
        set.add(new Interval(10, 15));
        set.add(new Interval(5, 7));  // touches [1,5): merges into [1,7)
        List<Interval> snap = set.snapshot();
        SequencedCollection<Interval> live = set.view();
        System.out.printf("    after add [1,5) [10,15) [5,7): %s covered=%d covers(6)=%b covers(7)=%b%n",
                snap, set.covered(), set.covers(6), set.covers(7));
        try {
            snap.set(0, new Interval(1, 12));
        } catch (UnsupportedOperationException e) {
            System.out.println("    snapshot.set(...) -> UnsupportedOperationException; Interval has no setters at all");
        }
        try {
            new Interval(9, 3);
        } catch (IllegalArgumentException e) {
            System.out.println("    new Interval(9, 3) -> " + e.getMessage());
        }
        set.add(new Interval(20, 25));
        System.out.printf("    after add [20,25): snapshot still %d intervals, live view now %d%n", snap.size(), live.size());
        try {
            for (Interval iv : live) if (iv.start() == 1) set.add(new Interval(30, 31));
        } catch (ConcurrentModificationException e) {
            System.out.println("    add while iterating the live view -> ConcurrentModificationException (fail-fast, not thread-safe)");
        }

        System.out.println("Records are shallowly immutable");
        PathArray a1 = new PathArray(new int[] {1, 2, 3}), a2 = new PathArray(new int[] {1, 2, 3});
        Set<PathArray> seenA = new HashSet<>(List.of(a1, a2));
        a1.nodes()[0] = 99;
        System.out.printf("    record PathArray(int[]): equals=%b, HashSet of two equal paths has %d entries,"
                + " accessor let a caller write nodes[0]=99: %s%n", a1.equals(a2), seenA.size(), Arrays.toString(a1.nodes()));
        List<Integer> source = new ArrayList<>(List.of(1, 2, 3));
        Path p1 = new Path(source), p2 = new Path(List.of(1, 2, 3));
        source.set(0, 99);
        Set<Path> seen = new HashSet<>(List.of(p1, p2));
        System.out.printf("    record Path(List<Integer>) + List.copyOf: equals=%b, HashSet has %d entry, source edit ignored: %s%n",
                p1.equals(p2), seen.size(), p1.nodes());
    }
}
```

**Output (verified):**

```text
L5 CpIntervalSet
    after add [1,5) [10,15): [[1, 5], [10, 15]] covered=9
    caller writes getIntervals().get(0)[1] = 12: [[1, 12], [10, 15]] covered=16 (true union [1,15) = 14)
    the next add inherits the corruption: [[1, 12], [10, 15], [20, 25]] covered=21 (true 19)
L7 IntervalSet
    after add [1,5) [10,15) [5,7): [Interval[start=1, end=7], Interval[start=10, end=15]] covered=11 covers(6)=true covers(7)=false
    snapshot.set(...) -> UnsupportedOperationException; Interval has no setters at all
    new Interval(9, 3) -> need start < end, got [9, 3)
    after add [20,25): snapshot still 2 intervals, live view now 3
    add while iterating the live view -> ConcurrentModificationException (fail-fast, not thread-safe)
Records are shallowly immutable
    record PathArray(int[]): equals=false, HashSet of two equal paths has 2 entries, accessor let a caller write nodes[0]=99: [99, 2, 3]
    record Path(List<Integer>) + List.copyOf: equals=true, HashSet has 1 entry, source edit ignored: [1, 2, 3]
```

### 2.2 Listing 3.2 — C++23

```cpp
// rep_exposure.cpp - an interval set whose invariant a caller can break (L5) vs one it cannot (L7); shallow vs deep equality.
#include <algorithm>
#include <cstdint>
#include <expected>
#include <map>
#include <print>
#include <ranges>
#include <set>
#include <span>
#include <string>
#include <utility>
#include <vector>

// ======================================================================= L5: the representation escapes
// Invariant (unchecked, undocumented): sorted, disjoint, half-open [l, r).
struct CpIntervalSet {
    std::vector<std::pair<int, int>> intervals;
    std::vector<std::pair<int, int>>& get_intervals() { return intervals; }  // hands out the representation itself

    void add(int l, int r) {
        std::vector<std::pair<int, int>> out;
        std::size_t i = 0;
        while (i < intervals.size() && intervals[i].second < l) out.push_back(intervals[i++]);
        while (i < intervals.size() && intervals[i].first <= r) {
            l = std::min(l, intervals[i].first);
            r = std::max(r, intervals[i].second);
            ++i;
        }
        out.emplace_back(l, r);
        while (i < intervals.size()) out.push_back(intervals[i++]);
        intervals = std::move(out);
    }
    long long covered() const {  // correct only while the invariant holds
        long long sum = 0;
        for (auto [l, r] : intervals) sum += r - l;
        return sum;
    }
};

// ======================================================================= L7: the invariant is owned
// Half-open [start, end). The only way to get one is make(), so an invalid Interval cannot exist.
class Interval {
public:
    static std::expected<Interval, std::string> make(std::int64_t start, std::int64_t end) {
        if (start >= end) return std::unexpected(std::format("need start < end, got [{}, {})", start, end));
        return Interval(start, end);
    }
    std::int64_t start() const noexcept { return start_; }
    std::int64_t end() const noexcept { return end_; }
    std::int64_t length() const noexcept { return end_ - start_; }
    friend bool operator==(const Interval&, const Interval&) = default;

private:
    friend class IntervalSet;
    Interval(std::int64_t s, std::int64_t e) : start_(s), end_(e) {}
    std::int64_t start_, end_;
};

// Sorted, disjoint, non-adjacent intervals keyed by start. add: O(log n + merged). covers: O(log n).
class IntervalSet {
public:
    void add(const Interval& iv) {
        std::int64_t start = iv.start(), end = iv.end();
        if (auto it = by_start_.upper_bound(start); it != by_start_.begin()) {
            if (auto left = std::prev(it); left->second >= start) {  // overlaps or touches on the left
                start = left->first;
                end = std::max(end, left->second);
                by_start_.erase(left);
            }
        }
        for (auto it = by_start_.lower_bound(start); it != by_start_.end() && it->first <= end;) {
            end = std::max(end, it->second);
            it = by_start_.erase(it);
        }
        by_start_.emplace(start, end);
    }
    bool covers(std::int64_t x) const {
        auto it = by_start_.upper_bound(x);
        return it != by_start_.begin() && x < std::prev(it)->second;
    }
    std::int64_t covered() const {
        std::int64_t sum = 0;
        for (auto [s, e] : by_start_) sum += e - s;
        return sum;
    }
    // Point-in-time copy: unaffected by later adds. O(n).
    std::vector<Interval> snapshot() const {
        std::vector<Interval> out;
        for (auto [s, e] : by_start_) out.push_back(Interval(s, e));
        return out;
    }
    // Live read-only view: O(1), lazy. Valid while *this lives and is not modified: add() erases nodes, and
    // iterating across an add is undefined behaviour -- C++ has no ConcurrentModificationException safety net.
    auto view() const {
        return by_start_ | std::views::transform([](const auto& kv) { return Interval(kv.first, kv.second); });
    }

private:
    std::map<std::int64_t, std::int64_t> by_start_;
};

std::string show(const std::vector<std::pair<int, int>>& v) {
    std::string s = "[";
    for (std::size_t i = 0; i < v.size(); ++i) s += std::format("{}[{}, {})", i ? ", " : "", v[i].first, v[i].second);
    return s + "]";
}
template <std::ranges::input_range R>
std::string show_intervals(R&& r) {
    std::string s = "[";
    bool first = true;
    for (const Interval& iv : r) {
        s += std::format("{}[{}, {})", first ? "" : ", ", iv.start(), iv.end());
        first = false;
    }
    return s + "]";
}

// ======================================================================= shallow vs deep equality
struct PathPtr {  // pointer member: the defaulted == compares addresses
    const int* nodes;
    std::size_t n;
    friend bool operator==(const PathPtr&, const PathPtr&) = default;
};
struct Path {  // value member: the defaulted <=> and == compare contents
    std::vector<int> nodes;
    friend auto operator<=>(const Path&, const Path&) = default;
};
#ifdef COMPARE_SPANS
struct PathSpan {  // std::span is a view, not a value: it has no operator==, so this defaulted == is deleted
    std::span<const int> nodes;
    friend bool operator==(const PathSpan&, const PathSpan&) = default;
};
const int g_a[] = {1, 2, 3}, g_b[] = {1, 2, 3};
bool g_same = PathSpan{g_a} == PathSpan{g_b};
#endif

int main() {
    std::println("L5 CpIntervalSet");
    CpIntervalSet cp;
    cp.add(1, 5);
    cp.add(10, 15);
    std::println("    after add [1,5) [10,15): {} covered={}", show(cp.intervals), cp.covered());
    cp.get_intervals()[0].second = 12;  // a caller "just adjusting" the first interval
    std::println("    caller writes get_intervals()[0].second = 12: {} covered={} (true union [1,15) = 14)", show(cp.intervals),
                 cp.covered());
    cp.add(20, 25);
    std::println("    the next add inherits the corruption: {} covered={} (true 19)", show(cp.intervals), cp.covered());

    std::println("L7 IntervalSet");
    IntervalSet set;
    for (auto [s, e] : {std::pair{1, 5}, std::pair{10, 15}, std::pair{5, 7}}) set.add(*Interval::make(s, e));
    auto snap = set.snapshot();
    std::println("    after add [1,5) [10,15) [5,7): {} covered={} covers(6)={} covers(7)={}", show_intervals(snap),
                 set.covered(), set.covers(6), set.covers(7));
    std::println("    Interval::make(9, 3) -> {}", Interval::make(9, 3).error());
    std::println("    snapshot is a std::vector<Interval> by value; Interval has no setters and no public constructor");
    set.add(*Interval::make(20, 25));
    std::println("    after add [20,25): snapshot still {} intervals, live view now {}", snap.size(),
                 std::ranges::distance(set.view()));
    std::println("    add while iterating view(): not run -- undefined behaviour, no fail-fast check exists");

    std::println("Shallow vs deep equality");
    const int a[] = {1, 2, 3}, b[] = {1, 2, 3};
    std::println("    struct {{ const int* nodes; }} with defaulted ==: equal contents compare {}", PathPtr{a, 3} == PathPtr{b, 3});
    std::vector<int> source = {1, 2, 3};
    Path p1{source}, p2{{1, 2, 3}};
    source[0] = 99;
    std::set<Path> seen{p1, p2};
    std::println("    struct {{ std::vector<int> nodes; }} with defaulted <=>: equal={}, std::set holds {} entry, copy ignored the "
                 "source edit: {}", p1 == p2, seen.size(), p1.nodes[0]);
    std::println("    struct {{ std::span<const int> nodes; }} with defaulted ==: does not compile (see the -D build)");
}
```

**Output, both compilers (verified; GCC shown, Clang identical):**

```text
L5 CpIntervalSet
    after add [1,5) [10,15): [[1, 5), [10, 15)] covered=9
    caller writes get_intervals()[0].second = 12: [[1, 12), [10, 15)] covered=16 (true union [1,15) = 14)
    the next add inherits the corruption: [[1, 12), [10, 15), [20, 25)] covered=21 (true 19)
L7 IntervalSet
    after add [1,5) [10,15) [5,7): [[1, 7), [10, 15)] covered=11 covers(6)=true covers(7)=false
    Interval::make(9, 3) -> need start < end, got [9, 3)
    snapshot is a std::vector<Interval> by value; Interval has no setters and no public constructor
    after add [20,25): snapshot still 2 intervals, live view now 3
    add while iterating view(): not run -- undefined behaviour, no fail-fast check exists
Shallow vs deep equality
    struct { const int* nodes; } with defaulted ==: equal contents compare false
    struct { std::vector<int> nodes; } with defaulted <=>: equal=true, std::set holds 1 entry, copy ignored the source edit: 1
    struct { std::span<const int> nodes; } with defaulted ==: does not compile (see the -D build)
```

**The expected-failure build (`-DCOMPARE_SPANS`), GCC 16.2:**

```text
rep_exposure.cpp:134:44: error: use of deleted function 'constexpr bool operator==(const PathSpan&, const PathSpan&)'
rep_exposure.cpp:130:26: error: no match for 'operator==' (operand types are 'std::span<const int>' and 'std::span<const int>')
```

**Clang 21.1:**

```text
rep_exposure.cpp:131:17: error: explicitly defaulted equality comparison operator is implicitly deleted [-Werror,-Wdefaulted-function-deleted]
rep_exposure.cpp:134:29: error: overload resolution selected deleted operator '=='
```

### 2.3 What the listings show

* **One innocent write breaks every later answer.** A caller "adjusts" the first interval through the returned list. `covered()` now reports 16 for a union of 14, and the **next** `add` faithfully preserves the corruption (21 vs 19). The class's own code was correct throughout. Nothing in a stack trace would point at the line that caused it: this is why representation exposure is a Staff-level concern rather than a style nit.
* **The L7 set cannot be corrupted from outside.** `Interval` validates once (`new Interval(9, 3)` and `Interval::make(9, 3)` both refuse), has no setters, and is a value. The set returns either an immutable snapshot (`List.copyOf` / a `std::vector` by value) or a live read-only view, and the two behave differently: after one more `add`, the snapshot still has 2 intervals and the view shows 3. The merge logic treats touching half-open intervals (`[1,5)` + `[5,7)`) as one, and `covers(7)` is false, because the end is exclusive. Those are the boundary decisions an interviewer looks for.
* **A read-only view is not thread-safe, and Java tells you; C++ doesn't.** Adding while iterating the live view throws `ConcurrentModificationException` in Java. That is the **fail-fast** check, explicitly best-effort and not a concurrency mechanism. In C++, `add()` may erase `std::map` nodes the view is pointing at, and iterating across it is undefined behaviour with no check at all, so the listing refuses to run it. The C++ `view()` comment states its lifetime contract; L7 C++ APIs say this out loud.
* **Records and defaulted comparisons are only as deep as their members.** `record PathArray(int[] nodes)` gives `equals == false` for equal contents, a `HashSet` holding two "equal" paths, and an accessor that lets a caller rewrite `nodes[0]`. `record Path(List<Integer> nodes)` with `List.copyOf` in the compact constructor fixes all three. C++ shows the same split: a defaulted `==` over a pointer member compares addresses, while over a `std::vector` it compares contents. And `std::span` has **no** `operator==` at all (span comparison was removed during C++20 standardization), so a defaulted `==` over a span member is deleted, and using it is a compile error on both compilers. A span is a view, not a value; the type system says so.

---

## 3. Custom iterators: a lazy k-way merge

The problem: merge `k` individually sorted sources (log files from `k` hosts, sorted runs of an external sort, posting lists, shard results) into one sorted sequence. The contest answer concatenates and sorts. That needs all `n` elements in memory, and it cannot start producing output until the inputs end, which on an infinite source is never.

The L7 artefact is an iterator holding **one buffered head per source** in a min-heap: `O(k)` memory, `O(log k)` per element, output from the first call. Three contract details separate a production iterator from a homework one:

1. **Stable ties:** equal elements come out in source order. That is a determinism guarantee callers can test against (heap ordered by `(value, sourceIndex)`).
2. **Contract checks on input:** a source that turns out to be unsorted would silently produce unsorted output. The iterator remembers each source's last value and throws as soon as a regression is pulled.
3. **Honest category:** it is single-pass, so it says so. Java's `Iterator` is inherently single-pass. The C++ view models `std::ranges::input_range` and `static_assert`s that it is **not** a `forward_range`.

### 3.1 Listing 3.3 — Java

```java
// MergeIterator.java - a lazy k-way merge as a production Iterator: O(k) memory, stable ties, loud contract checks.
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Objects;
import java.util.PriorityQueue;
import java.util.Spliterator;
import java.util.Spliterators;
import java.util.stream.LongStream;
import java.util.stream.Stream;
import java.util.stream.StreamSupport;

/**
 * Merges k individually sorted sources into one sorted sequence, lazily.
 * Memory O(k): one buffered head per source. Time O(log k) per element. Ties keep source order (stable).
 * Fails loudly: a null element or an out-of-order source throws as soon as the offending element is pulled.
 * Single-threaded and single-pass, like every java.util.Iterator.
 */
public final class MergeIterator<T> implements Iterator<T> {
    private record Head<E>(E value, int source) {}

    private final List<Iterator<? extends T>> sources;
    private final Comparator<? super T> order;
    private final PriorityQueue<Head<T>> heap;
    private final List<T> last;  // last value pulled from each source, to detect unsorted input

    public MergeIterator(List<? extends Iterator<? extends T>> sources, Comparator<? super T> order) {
        this.sources = List.copyOf(sources);
        this.order = Objects.requireNonNull(order, "order");
        Comparator<Head<T>> byValue = (a, b) -> order.compare(a.value(), b.value());
        this.heap = new PriorityQueue<>(Math.max(1, this.sources.size()), byValue.thenComparingInt(Head::source));
        this.last = new ArrayList<>(Collections.nCopies(this.sources.size(), null));
        for (int i = 0; i < this.sources.size(); i++) pull(i);
    }

    private void pull(int i) {
        Iterator<? extends T> it = sources.get(i);
        if (!it.hasNext()) return;
        T v = Objects.requireNonNull(it.next(), () -> "source " + i + " produced null");
        T prev = last.get(i);
        if (prev != null && order.compare(v, prev) < 0) {
            throw new IllegalStateException("source " + i + " is not sorted: " + v + " after " + prev);
        }
        last.set(i, v);
        heap.add(new Head<>(v, i));
    }

    @Override
    public boolean hasNext() { return !heap.isEmpty(); }

    @Override
    public T next() {
        Head<T> h = heap.poll();
        if (h == null) throw new NoSuchElementException("merge exhausted");
        pull(h.source());
        return h.value();
    }

    /** The same merge as a Stream, so callers get limit/filter/map without materializing anything. */
    public static <T> Stream<T> stream(List<? extends Iterator<? extends T>> sources, Comparator<? super T> order) {
        return StreamSupport.stream(Spliterators.spliteratorUnknownSize(new MergeIterator<>(sources, order),
                Spliterator.ORDERED | Spliterator.NONNULL), false);
    }

    // ===================================================================== demo
    record Event(long ts, String host) {
        @Override
        public String toString() { return ts + host; }
    }

    public static void main(String[] args) {
        List<Iterator<Event>> logs = List.of(
                List.of(new Event(1, "A"), new Event(4, "A"), new Event(4, "A"), new Event(9, "A")).iterator(),
                List.of(new Event(2, "B"), new Event(4, "B"), new Event(7, "B")).iterator(),
                List.<Event>of().iterator(),
                List.of(new Event(3, "D")).iterator());
        System.out.println("4 host logs, sorted by ts, one empty: "
                + stream(logs, Comparator.comparingLong(Event::ts)).toList() + "   <- ts=4 ties keep source order A, A, B");

        List<Iterator<Long>> infinite = List.of(LongStream.iterate(0, x -> x + 2).boxed().iterator(),
                LongStream.iterate(0, x -> x + 3).boxed().iterator(), LongStream.iterate(0, x -> x + 5).boxed().iterator());
        System.out.println("3 INFINITE sources (multiples of 2, 3, 5), first 15: "
                + stream(infinite, Comparator.<Long>naturalOrder()).limit(15).toList());

        try {
            stream(List.of(List.of(1, 5, 3).iterator(), List.of(2).iterator()), Comparator.<Integer>naturalOrder()).toList();
        } catch (IllegalStateException e) {
            System.out.println("unsorted source -> IllegalStateException: " + e.getMessage());
        }
        MergeIterator<Integer> done = new MergeIterator<>(List.of(List.of(1).iterator()), Comparator.naturalOrder());
        done.next();
        try {
            done.next();
        } catch (NoSuchElementException e) {
            System.out.println("next() after the end -> NoSuchElementException: " + e.getMessage());
        }

        int k = 64, n = 1 << 21;
        List<List<Long>> runs = new ArrayList<>();
        long seed = 12345;
        for (int r = 0; r < k; r++) {
            List<Long> run = new ArrayList<>(n / k);
            for (int i = 0; i < n / k; i++) {
                seed = seed * 6364136223846793005L + 1442695040888963407L;  // LCG: deterministic, cheap
                run.add(seed >>> 20);
            }
            Collections.sort(run);
            runs.add(run);
        }
        for (int rep = 0; rep < 2; rep++) {  // second round is the one reported: the first pays for JIT
            long t0 = System.nanoTime();
            List<Iterator<Long>> its = new ArrayList<>();
            for (List<Long> run : runs) its.add(run.iterator());
            long hashMerge = 0;
            for (MergeIterator<Long> it = new MergeIterator<>(its, Comparator.naturalOrder()); it.hasNext(); ) {
                hashMerge = hashMerge * 31 + it.next();
            }
            long t1 = System.nanoTime();
            List<Long> all = new ArrayList<>(n);
            for (List<Long> run : runs) all.addAll(run);
            Collections.sort(all);
            long hashSort = 0;
            for (long v : all) hashSort = hashSort * 31 + v;
            long t2 = System.nanoTime();
            if (rep == 1) {
                System.out.printf("k=%d sorted runs, n=%,d Longs (one measured run): merge %d ms holding %d heads;"
                        + " concat+sort %d ms holding %,d; same sequence: %b%n", k, n, (t1 - t0) / 1_000_000, k,
                        (t2 - t1) / 1_000_000, n, hashMerge == hashSort);
            }
        }
    }
}
```

**Output (verified; the last line is one measured run):**

```text
4 host logs, sorted by ts, one empty: [1A, 2B, 3D, 4A, 4A, 4B, 7B, 9A]   <- ts=4 ties keep source order A, A, B
3 INFINITE sources (multiples of 2, 3, 5), first 15: [0, 0, 0, 2, 3, 4, 5, 6, 6, 8, 9, 10, 10, 12, 12]
unsorted source -> IllegalStateException: source 0 is not sorted: 3 after 5
next() after the end -> NoSuchElementException: merge exhausted
k=64 sorted runs, n=2,097,152 Longs (one measured run): merge 258 ms holding 64 heads; concat+sort 213 ms holding 2,097,152; same sequence: true
```

### 3.2 Listing 3.4 — C++23

```cpp
// merge_iterator.cpp - a lazy k-way merge as a C++23 input view: O(k) memory, stable ties, loud contract checks.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <format>
#include <functional>
#include <iterator>
#include <print>
#include <ranges>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

// Merges k individually sorted views into one sorted, single-pass sequence.
// Memory O(k): one buffered head per source. O(log k) per element. Ties keep source order (stable).
// Like std::ranges::istream_view, the state lives in the view and iterators point at it: call begin() once,
// and do not move the view while iterating. Throws std::logic_error when a source turns out to be unsorted.
template <std::ranges::view R, class Cmp = std::ranges::less>
    requires std::ranges::input_range<R> &&
             std::strict_weak_order<Cmp, std::ranges::range_value_t<R>, std::ranges::range_value_t<R>>
class merge_view : public std::ranges::view_interface<merge_view<R, Cmp>> {
public:
    using value_type = std::ranges::range_value_t<R>;

    explicit merge_view(std::vector<R> sources, Cmp cmp = {}) : sources_(std::move(sources)), cmp_(std::move(cmp)) {}

    class iterator {
    public:
        using value_type = merge_view::value_type;
        using difference_type = std::ptrdiff_t;
        iterator() = default;
        explicit iterator(merge_view* parent) : parent_(parent) {}
        const value_type& operator*() const { return parent_->heap_.front().value; }
        iterator& operator++() {
            parent_->pop();
            return *this;
        }
        void operator++(int) { ++*this; }
        friend bool operator==(const iterator& it, std::default_sentinel_t) { return it.parent_->heap_.empty(); }

    private:
        merge_view* parent_ = nullptr;
    };

    iterator begin() {
        if (!primed_) {
            primed_ = true;
            cursors_.reserve(sources_.size());
            for (auto& s : sources_) cursors_.push_back(Cursor{std::ranges::begin(s), std::ranges::end(s)});
            for (std::size_t i = 0; i < cursors_.size(); ++i) push(i, nullptr);
        }
        return iterator{this};
    }
    std::default_sentinel_t end() const noexcept { return {}; }

private:
    struct Head {
        value_type value;
        std::size_t source;
    };
    struct Cursor {
        std::ranges::iterator_t<R> it;
        std::ranges::sentinel_t<R> end;
    };
    // Heap order: front() is the smallest value; among equals, the lowest source index.
    bool after(const Head& a, const Head& b) const {
        if (std::invoke(cmp_, b.value, a.value)) return true;
        if (std::invoke(cmp_, a.value, b.value)) return false;
        return a.source > b.source;
    }
    void push(std::size_t i, const value_type* prev) {
        auto& c = cursors_[i];
        if (c.it == c.end) return;
        value_type v = *c.it;
        ++c.it;
        if (prev != nullptr && std::invoke(cmp_, v, *prev))
            throw std::logic_error("source " + std::to_string(i) + " is not sorted");
        heap_.push_back(Head{std::move(v), i});
        std::ranges::push_heap(heap_, [this](const Head& a, const Head& b) { return after(a, b); });
    }
    void pop() {
        std::ranges::pop_heap(heap_, [this](const Head& a, const Head& b) { return after(a, b); });
        Head taken = std::move(heap_.back());
        heap_.pop_back();
        push(taken.source, &taken.value);
    }

    std::vector<R> sources_;
    Cmp cmp_;
    std::vector<Cursor> cursors_;
    std::vector<Head> heap_;
    bool primed_ = false;
};

using span_merge = merge_view<std::span<const int>>;
static_assert(std::input_iterator<span_merge::iterator>);
static_assert(std::sentinel_for<std::default_sentinel_t, span_merge::iterator>);
static_assert(std::ranges::input_range<span_merge> && std::ranges::view<span_merge>);
static_assert(!std::ranges::forward_range<span_merge>);  // single pass, and the type says so

struct Event {
    std::int64_t ts;
    char host;
};

int main() {
    const std::vector<Event> a = {{1, 'A'}, {4, 'A'}, {4, 'A'}, {9, 'A'}}, b = {{2, 'B'}, {4, 'B'}, {7, 'B'}}, c = {},
                             d = {{3, 'D'}};
    auto by_ts = [](const Event& x, const Event& y) { return x.ts < y.ts; };
    merge_view<std::span<const Event>, decltype(by_ts)> logs(
        {std::span<const Event>(a), std::span<const Event>(b), std::span<const Event>(c), std::span<const Event>(d)}, by_ts);
    std::string out;
    for (const Event& e : logs) out += std::format("{}{}{}", out.empty() ? "" : ", ", e.ts, e.host);
    std::println("4 host logs, sorted by ts, one empty: [{}]   <- ts=4 ties keep source order A, A, B", out);

    auto multiples = [](std::int64_t step) {
        return std::views::iota(std::int64_t{0}) | std::views::transform([step](std::int64_t i) { return i * step; });
    };
    using Inf = decltype(multiples(2));  // the same closure type every call, so k infinite sources share one R
    out.clear();
    for (std::int64_t v : merge_view<Inf>({multiples(2), multiples(3), multiples(5)}) | std::views::take(15))
        out += std::format("{}{}", out.empty() ? "" : ", ", v);
    std::println("3 INFINITE sources (multiples of 2, 3, 5), first 15: [{}]", out);

    const std::vector<int> bad = {1, 5, 3}, two = {2};
    try {
        for (int v : span_merge({std::span<const int>(bad), std::span<const int>(two)})) (void)v;
    } catch (const std::logic_error& e) {
        std::println("unsorted source -> std::logic_error: {}", e.what());
    }

    constexpr std::size_t k = 64, n = std::size_t{1} << 21;
    std::vector<std::vector<int>> runs(k);
    std::uint64_t seed = 12345;
    for (auto& run : runs) {
        run.resize(n / k);
        for (auto& v : run) {
            seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;  // LCG: deterministic, cheap
            v = static_cast<int>(seed >> 33);
        }
        std::ranges::sort(run);
    }
    using clock = std::chrono::steady_clock;
    auto t0 = clock::now();
    std::vector<std::span<const int>> views(runs.begin(), runs.end());
    std::uint64_t hash_merge = 0;
    for (int v : span_merge(std::move(views))) hash_merge = hash_merge * 31 + static_cast<std::uint64_t>(v);
    auto t1 = clock::now();
    std::vector<int> all;
    all.reserve(n);
    for (const auto& run : runs) all.insert(all.end(), run.begin(), run.end());
    std::ranges::sort(all);
    std::uint64_t hash_sort = 0;
    for (int v : all) hash_sort = hash_sort * 31 + static_cast<std::uint64_t>(v);
    auto t2 = clock::now();
    auto ms = [](clock::duration dur) { return std::chrono::duration_cast<std::chrono::milliseconds>(dur).count(); };
    std::println("k={} sorted runs, n={} ints (one measured run): merge {} ms holding {} heads; concat+sort {} ms holding {};"
                 " same sequence: {}", k, n, ms(t1 - t0), k, ms(t2 - t1), n, hash_merge == hash_sort);
}
```

**Output, GCC 16.2 (verified; the last line is one measured run):**

```text
4 host logs, sorted by ts, one empty: [1A, 2B, 3D, 4A, 4A, 4B, 7B, 9A]   <- ts=4 ties keep source order A, A, B
3 INFINITE sources (multiples of 2, 3, 5), first 15: [0, 0, 0, 2, 3, 4, 5, 6, 6, 8, 9, 10, 10, 12, 12]
unsorted source -> std::logic_error: source 0 is not sorted
k=64 sorted runs, n=2097152 ints (one measured run): merge 96 ms holding 64 heads; concat+sort 80 ms holding 2097152; same sequence: true
```

**Output, Clang 21.1 (verified; the last line is one measured run):**

```text
4 host logs, sorted by ts, one empty: [1A, 2B, 3D, 4A, 4A, 4B, 7B, 9A]   <- ts=4 ties keep source order A, A, B
3 INFINITE sources (multiples of 2, 3, 5), first 15: [0, 0, 0, 2, 3, 4, 5, 6, 6, 8, 9, 10, 10, 12, 12]
unsorted source -> std::logic_error: source 0 is not sorted
k=64 sorted runs, n=2097152 ints (one measured run): merge 99 ms holding 64 heads; concat+sort 67 ms holding 2097152; same sequence: true
```

### 3.3 What the listings show

* **Laziness is a capability, not an optimization.** Three infinite sources (multiples of 2, 3 and 5) merged and truncated to 15 elements. `Stream.limit` in Java and `std::views::take` in C++ pull exactly what they need. No concatenate-and-sort solution can produce this output at all.
* **Stable ties are visible:** at `ts = 4` the output is `4A, 4A, 4B`, because source A comes before source B. An empty source is handled without a special case.
* **Unsorted input fails loudly, at the point of consumption.** Java reports which source and which values (`3 after 5`). The C++ version throws `std::logic_error` from `operator++`.
* **It is not faster in RAM, and saying so is the senior answer.** Merging 64 sorted runs of 2 M elements took 258 ms (Java) and 96–99 ms (C++). Concatenate-and-sort took 213 ms and 67–80 ms. Java's TimSort detects the 64 pre-sorted runs and merges them with sequential memory access. The heap merge does `log₂ 64 = 6` unpredictable comparisons per element. The merge iterator's advantage is **memory, `O(k)` vs `O(n)`, and latency to first output**. That is exactly what matters when the runs are files larger than RAM (Folder 07's external sort) or results streaming back from 100 shards.
* **C++ design notes.** Like `std::ranges::istream_view`, the state lives in the view and the iterator holds a pointer to it, so the view must not move while iterated; the class comment says so. `operator*` returns a reference valid until the next increment, the standard input-iterator rule. The infinite sources work because `iota | transform` with one lambda expression produces **one** closure type, so all `k` sources share a single `R`. The `static_assert`s are executable documentation: if a refactor broke the iterator's concept conformance, the build would fail.

---

## 4. Test-driven verification: the contest stress test, promoted

The harness is about 30 lines in each language:

1. **Generate** a random input from a deliberately **small** domain (sizes 0–8, values −10..10, interval endpoints 0..14).
2. Run the **fast** solution and an **oracle**: an obviously correct, slow implementation that shares no code with it. Render each outcome as text, **including exceptions**, so a crash is just another wrong answer.
3. At the first disagreement, **shrink**: try candidate inputs that are "smaller" (drop an element, move a value toward 0, translate all intervals left, shorten one) and keep the first that still disagrees. Repeat until no candidate fails.
4. Report the trial number, the original input, the minimal input and both outcomes.

Two targets, each in versions that a real candidate might write:

* **Maximum subarray sum** (LeetCode 53). v1 is the classic contest Kadane, `cur = max(0, cur + v)`, which returns 0 for an empty array *and* for an all-negative one. v2 rejects empty input but still starts at 0. v3 starts from the first element.
* **Merging closed intervals** (LeetCode 56). v1 merges when `next.lo < last.hi`, v2 when `next.lo <= last.hi`. For closed intervals `[a, b]`, sharing an endpoint *is* overlapping. Then three **oracle-free properties** for v2: idempotence, independence from input order, and conservation of the covered points.

### 4.1 Listing 3.5 — Java

```java
// StressOracle.java - the contest stress test promoted to production: random differential testing + shrinking + properties.
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.function.Function;

public final class StressOracle {

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
        int nextInt(int bound) { return (int) Long.remainderUnsigned(next(), bound); }
    }

    // ===================================================================== the harness
    /** Runs f and renders the result -- or the exception -- as text, so a crash is just another wrong answer. */
    static <T> String outcome(Function<T, ?> f, T x) {
        try {
            return String.valueOf(f.apply(x));
        } catch (RuntimeException e) {
            return "threw " + e.getClass().getSimpleName();
        }
    }

    /**
     * Generates `trials` inputs; at the first input where fast and oracle disagree, greedily applies the first
     * shrink candidate that still disagrees until none does, and reports the minimal input.
     */
    static <T> String check(int trials, long seed, Function<SplitMix64, T> gen, Function<T, List<T>> shrinks,
                            Function<T, ?> fast, Function<T, ?> oracle) {
        SplitMix64 r = new SplitMix64(seed);
        for (int t = 1; t <= trials; t++) {
            T x = gen.apply(r);
            if (outcome(fast, x).equals(outcome(oracle, x))) continue;
            T cur = x;
            int steps = 0;
            for (boolean progress = true; progress; ) {
                progress = false;
                for (T c : shrinks.apply(cur)) {
                    if (!outcome(fast, c).equals(outcome(oracle, c))) {
                        cur = c;
                        steps++;
                        progress = true;
                        break;
                    }
                }
            }
            return String.format("FAIL at trial %d: %s%n        shrunk in %d steps to %s: fast %s, oracle %s", t, x, steps,
                    cur, outcome(fast, cur), outcome(oracle, cur));
        }
        return String.format("passed %,d random trials", trials);
    }

    // ===================================================================== target 1: maximum subarray sum
    static long kadaneV1(List<Integer> a) {  // contest version: "answer is at least 0"
        long best = 0, cur = 0;
        for (int v : a) {
            cur = Math.max(0, cur + v);
            best = Math.max(best, cur);
        }
        return best;
    }

    static long kadaneV2(List<Integer> a) {  // empty input now rejected, initialisation still wrong
        if (a.isEmpty()) throw new IllegalArgumentException("empty");
        long best = 0, cur = 0;
        for (int v : a) {
            cur = Math.max(0, cur + v);
            best = Math.max(best, cur);
        }
        return best;
    }

    static long kadaneV3(List<Integer> a) {  // a subarray is non-empty: start from the first element
        if (a.isEmpty()) throw new IllegalArgumentException("empty");
        long best = Long.MIN_VALUE, cur = 0;
        for (int v : a) {
            cur = Math.max(v, cur + v);
            best = Math.max(best, cur);
        }
        return best;
    }

    static long maxSubarrayOracle(List<Integer> a) {  // O(n^2), obviously correct
        if (a.isEmpty()) throw new IllegalArgumentException("empty");
        long best = Long.MIN_VALUE;
        for (int i = 0; i < a.size(); i++) {
            long s = 0;
            for (int j = i; j < a.size(); j++) best = Math.max(best, s += a.get(j));
        }
        return best;
    }

    static List<Integer> smallArray(SplitMix64 r) {  // small sizes, small values: edge cases become likely
        int n = r.nextInt(9);
        List<Integer> a = new ArrayList<>();
        for (int i = 0; i < n; i++) a.add(r.nextInt(21) - 10);
        return a;
    }

    static List<Integer> bigArray(SplitMix64 r) {  // the tempting "realistic" generator
        int n = 1 + r.nextInt(1_000);
        List<Integer> a = new ArrayList<>();
        for (int i = 0; i < n; i++) a.add(r.nextInt(2_000_000_001) - 1_000_000_000);
        return a;
    }

    static List<List<Integer>> shrinkArray(List<Integer> a) {  // remove an element, then move one toward zero
        List<List<Integer>> out = new ArrayList<>();
        for (int i = 0; i < a.size(); i++) {
            List<Integer> c = new ArrayList<>(a);
            c.remove(i);
            out.add(c);
        }
        for (int i = 0; i < a.size(); i++) {
            int v = a.get(i);
            for (int w : new int[] {0, v / 2, v - Integer.signum(v)}) {
                if (w == v || Math.abs(w) >= Math.abs(v)) continue;
                List<Integer> c = new ArrayList<>(a);
                c.set(i, w);
                out.add(c);
            }
        }
        return out;
    }

    // ===================================================================== target 2: merge closed intervals
    record Iv(int lo, int hi) {
        @Override
        public String toString() { return "[" + lo + "," + hi + "]"; }
    }

    static List<Iv> mergeV1(List<Iv> in) {  // contest version: "overlap" written as a strict inequality
        List<Iv> s = new ArrayList<>(in);
        s.sort(Comparator.comparingInt(Iv::lo).thenComparingInt(Iv::hi));
        List<Iv> out = new ArrayList<>();
        for (Iv iv : s) {
            Iv last = out.isEmpty() ? null : out.get(out.size() - 1);
            if (last != null && iv.lo() < last.hi()) out.set(out.size() - 1, new Iv(last.lo(), Math.max(last.hi(), iv.hi())));
            else out.add(iv);
        }
        return out;
    }

    static List<Iv> mergeV2(List<Iv> in) {  // closed intervals sharing an endpoint overlap
        List<Iv> s = new ArrayList<>(in);
        s.sort(Comparator.comparingInt(Iv::lo).thenComparingInt(Iv::hi));
        List<Iv> out = new ArrayList<>();
        for (Iv iv : s) {
            Iv last = out.isEmpty() ? null : out.get(out.size() - 1);
            if (last != null && iv.lo() <= last.hi()) out.set(out.size() - 1, new Iv(last.lo(), Math.max(last.hi(), iv.hi())));
            else out.add(iv);
        }
        return out;
    }

    static List<Iv> mergeOracle(List<Iv> in) {  // merge any overlapping pair until nothing changes: slow, obviously right
        List<Iv> cur = new ArrayList<>(in);
        for (boolean changed = true; changed; ) {
            changed = false;
            search:
            for (int i = 0; i < cur.size(); i++) {
                for (int j = i + 1; j < cur.size(); j++) {
                    Iv a = cur.get(i), b = cur.get(j);
                    if (a.lo() <= b.hi() && b.lo() <= a.hi()) {
                        cur.set(i, new Iv(Math.min(a.lo(), b.lo()), Math.max(a.hi(), b.hi())));
                        cur.remove(j);
                        changed = true;
                        break search;
                    }
                }
            }
        }
        cur.sort(Comparator.comparingInt(Iv::lo));
        return cur;
    }

    static List<Iv> smallIntervals(SplitMix64 r) {
        int n = r.nextInt(7);
        List<Iv> a = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            int lo = r.nextInt(11);
            a.add(new Iv(lo, lo + r.nextInt(5)));
        }
        return a;
    }

    /** Remove one; translate all left (keeps every touching pair touching); then shift / shorten one. */
    static List<List<Iv>> shrinkIntervals(List<Iv> a) {
        List<List<Iv>> out = new ArrayList<>();
        for (int i = 0; i < a.size(); i++) {
            List<Iv> c = new ArrayList<>(a);
            c.remove(i);
            out.add(c);
        }
        if (!a.isEmpty() && a.stream().allMatch(v -> v.lo() > 0)) out.add(a.stream().map(v -> new Iv(v.lo() - 1, v.hi() - 1)).toList());
        for (int i = 0; i < a.size(); i++) {
            Iv v = a.get(i);
            List<Iv> candidates = new ArrayList<>();
            if (v.lo() > 0) candidates.add(new Iv(v.lo() - 1, v.hi() - 1));
            if (v.hi() > v.lo()) candidates.add(new Iv(v.lo() + 1, v.hi()));
            if (v.hi() > v.lo()) candidates.add(new Iv(v.lo(), v.hi() - 1));
            for (Iv w : candidates) {
                List<Iv> c = new ArrayList<>(a);
                c.set(i, w);
                out.add(c);
            }
        }
        return out;
    }

    /** Oracle-free checks: properties any correct merge must satisfy. */
    static String properties(int trials, long seed) {
        SplitMix64 r = new SplitMix64(seed);
        int idempotent = 0, orderFree = 0, coverage = 0;
        for (int t = 0; t < trials; t++) {
            List<Iv> x = smallIntervals(r), m = mergeV2(x);
            if (mergeV2(m).equals(m)) idempotent++;
            if (mergeV2(x.reversed()).equals(m)) orderFree++;
            boolean same = true;
            for (int p = 0; p <= 15; p++) {
                final int q = p;
                same &= x.stream().anyMatch(iv -> iv.lo() <= q && q <= iv.hi()) == m.stream().anyMatch(iv -> iv.lo() <= q && q <= iv.hi());
            }
            if (same) coverage++;
        }
        return String.format("idempotent %d/%d, input-order-free %d/%d, covers the same points %d/%d", idempotent, trials,
                orderFree, trials, coverage, trials);
    }

    public static void main(String[] args) {
        int trials = 100_000;
        System.out.println("maximum subarray sum (fast vs O(n^2) oracle, sizes 0..8, values -10..10):");
        System.out.println("    v1 cur = max(0, cur + v), no empty check:   "
                + check(trials, 1, StressOracle::smallArray, StressOracle::shrinkArray, StressOracle::kadaneV1, StressOracle::maxSubarrayOracle));
        System.out.println("    v2 rejects empty, still starts at 0:        "
                + check(trials, 1, StressOracle::smallArray, StressOracle::shrinkArray, StressOracle::kadaneV2, StressOracle::maxSubarrayOracle));
        System.out.println("    v3 starts from the first element:           "
                + check(trials, 1, StressOracle::smallArray, StressOracle::shrinkArray, StressOracle::kadaneV3, StressOracle::maxSubarrayOracle));
        System.out.println("    v2 again, 'realistic' generator (n<=1000, |v|<=1e9), 2,000 trials: "
                + check(2_000, 1, StressOracle::bigArray, StressOracle::shrinkArray, StressOracle::kadaneV2, StressOracle::maxSubarrayOracle));
        System.out.println("merge closed intervals (fast vs pairwise-fixpoint oracle):");
        System.out.println("    v1 merges when next.lo <  last.hi:          "
                + check(trials, 2, StressOracle::smallIntervals, StressOracle::shrinkIntervals, StressOracle::mergeV1, StressOracle::mergeOracle));
        System.out.println("    v2 merges when next.lo <= last.hi:          "
                + check(trials, 2, StressOracle::smallIntervals, StressOracle::shrinkIntervals, StressOracle::mergeV2, StressOracle::mergeOracle));
        System.out.println("    v2 properties, no oracle needed: " + properties(20_000, 3));
    }
}
```

**Output (verified):**

```text
maximum subarray sum (fast vs O(n^2) oracle, sizes 0..8, values -10..10):
    v1 cur = max(0, cur + v), no empty check:   FAIL at trial 2: []
        shrunk in 0 steps to []: fast 0, oracle threw IllegalArgumentException
    v2 rejects empty, still starts at 0:        FAIL at trial 6: [-4]
        shrunk in 2 steps to [-1]: fast 0, oracle -1
    v3 starts from the first element:           passed 100,000 random trials
    v2 again, 'realistic' generator (n<=1000, |v|<=1e9), 2,000 trials: FAIL at trial 711: [-518056415, -996644898, -380110124, -672683503]
        shrunk in 32 steps to [-1]: fast 0, oracle -1
merge closed intervals (fast vs pairwise-fixpoint oracle):
    v1 merges when next.lo <  last.hi:          FAIL at trial 8: [[1,2], [10,13], [6,10], [1,2], [7,9], [7,8]]
        shrunk in 21 steps to [[0,0], [0,0]]: fast [[0,0], [0,0]], oracle [[0,0]]
    v2 merges when next.lo <= last.hi:          passed 100,000 random trials
    v2 properties, no oracle needed: idempotent 20000/20000, input-order-free 20000/20000, covers the same points 20000/20000
```

### 4.2 Listing 3.6 — C++23

```cpp
// stress_oracle.cpp - the contest stress test promoted to production: random differential testing + shrinking + properties.
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <limits>
#include <print>
#include <stdexcept>
#include <string>
#include <vector>

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int next_int(int bound) noexcept { return static_cast<int>(next() % static_cast<std::uint64_t>(bound)); }
};

using Array = std::vector<int>;
struct Iv {
    int lo, hi;
    friend bool operator==(const Iv&, const Iv&) = default;
};
using Ivs = std::vector<Iv>;

std::string show(std::int64_t v) { return std::to_string(v); }
std::string show(const Array& a) {
    std::string s = "[";
    for (std::size_t i = 0; i < a.size(); ++i) s += std::format("{}{}", i ? ", " : "", a[i]);
    return s + "]";
}
std::string show(const Ivs& a) {
    std::string s = "[";
    for (std::size_t i = 0; i < a.size(); ++i) s += std::format("{}[{},{}]", i ? ", " : "", a[i].lo, a[i].hi);
    return s + "]";
}

// ======================================================================= the harness
// Runs f and renders the result -- or the exception -- as text, so a crash is just another wrong answer.
template <class T, class F>
std::string outcome(F f, const T& x) {
    try {
        return show(f(x));
    } catch (const std::invalid_argument&) {
        return "threw std::invalid_argument";
    }
}

// Generates `trials` inputs; at the first disagreement, greedily applies the first shrink candidate that still
// disagrees until none does, and reports the minimal input.
template <class T, class Gen, class Shrink, class Fast, class Oracle>
std::string check(int trials, std::uint64_t seed, Gen gen, Shrink shrinks, Fast fast, Oracle oracle) {
    SplitMix64 r{seed};
    for (int t = 1; t <= trials; ++t) {
        T x = gen(r);
        if (outcome<T>(fast, x) == outcome<T>(oracle, x)) continue;
        T cur = x;
        int steps = 0;
        for (bool progress = true; progress;) {
            progress = false;
            for (const T& c : shrinks(cur)) {
                if (outcome<T>(fast, c) != outcome<T>(oracle, c)) {
                    cur = c;
                    ++steps;
                    progress = true;
                    break;
                }
            }
        }
        return std::format("FAIL at trial {}: {}\n        shrunk in {} steps to {}: fast {}, oracle {}", t, show(x), steps,
                           show(cur), outcome<T>(fast, cur), outcome<T>(oracle, cur));
    }
    return std::format("passed {} random trials", trials);
}

// ======================================================================= target 1: maximum subarray sum
std::int64_t kadane_v1(const Array& a) {  // contest version: "answer is at least 0"
    std::int64_t best = 0, cur = 0;
    for (int v : a) {
        cur = std::max<std::int64_t>(0, cur + v);
        best = std::max(best, cur);
    }
    return best;
}
std::int64_t kadane_v2(const Array& a) {  // empty input now rejected, initialisation still wrong
    if (a.empty()) throw std::invalid_argument("empty");
    return kadane_v1(a);
}
std::int64_t kadane_v3(const Array& a) {  // a subarray is non-empty: start from the first element
    if (a.empty()) throw std::invalid_argument("empty");
    std::int64_t best = std::numeric_limits<std::int64_t>::min(), cur = 0;
    for (int v : a) {
        cur = std::max<std::int64_t>(v, cur + v);
        best = std::max(best, cur);
    }
    return best;
}
std::int64_t max_subarray_oracle(const Array& a) {  // O(n^2), obviously correct
    if (a.empty()) throw std::invalid_argument("empty");
    std::int64_t best = std::numeric_limits<std::int64_t>::min();
    for (std::size_t i = 0; i < a.size(); ++i) {
        std::int64_t s = 0;
        for (std::size_t j = i; j < a.size(); ++j) best = std::max(best, s += a[j]);
    }
    return best;
}
Array small_array(SplitMix64& r) {  // small sizes, small values: edge cases become likely
    int n = r.next_int(9);
    Array a;
    for (int i = 0; i < n; ++i) a.push_back(r.next_int(21) - 10);
    return a;
}
Array big_array(SplitMix64& r) {  // the tempting "realistic" generator
    int n = 1 + r.next_int(1'000);
    Array a;
    for (int i = 0; i < n; ++i) a.push_back(r.next_int(2'000'000'001) - 1'000'000'000);
    return a;
}
std::vector<Array> shrink_array(const Array& a) {  // remove an element, then move one toward zero
    std::vector<Array> out;
    for (std::size_t i = 0; i < a.size(); ++i) {
        Array c = a;
        c.erase(c.begin() + static_cast<std::ptrdiff_t>(i));
        out.push_back(std::move(c));
    }
    for (std::size_t i = 0; i < a.size(); ++i) {
        int v = a[i];
        for (int w : {0, v / 2, v - (v > 0) + (v < 0)}) {
            if (w == v || std::abs(w) >= std::abs(v)) continue;
            Array c = a;
            c[i] = w;
            out.push_back(std::move(c));
        }
    }
    return out;
}

// ======================================================================= target 2: merge closed intervals
template <bool Inclusive>
Ivs merge_sorted(const Ivs& in) {  // v1 (Inclusive=false) writes "overlap" as a strict inequality
    Ivs s = in;
    std::ranges::sort(s, {}, [](const Iv& v) { return std::pair{v.lo, v.hi}; });
    Ivs out;
    for (const Iv& iv : s) {
        if (!out.empty() && (Inclusive ? iv.lo <= out.back().hi : iv.lo < out.back().hi))
            out.back().hi = std::max(out.back().hi, iv.hi);
        else
            out.push_back(iv);
    }
    return out;
}
Ivs merge_oracle(const Ivs& in) {  // merge any overlapping pair until nothing changes: slow, obviously right
    Ivs cur = in;
    for (bool changed = true; changed;) {
        changed = false;
        for (std::size_t i = 0; i < cur.size() && !changed; ++i) {
            for (std::size_t j = i + 1; j < cur.size() && !changed; ++j) {
                if (cur[i].lo <= cur[j].hi && cur[j].lo <= cur[i].hi) {
                    cur[i] = Iv{std::min(cur[i].lo, cur[j].lo), std::max(cur[i].hi, cur[j].hi)};
                    cur.erase(cur.begin() + static_cast<std::ptrdiff_t>(j));
                    changed = true;
                }
            }
        }
    }
    std::ranges::stable_sort(cur, {}, &Iv::lo);
    return cur;
}
Ivs small_intervals(SplitMix64& r) {
    int n = r.next_int(7);
    Ivs a;
    for (int i = 0; i < n; ++i) {
        int lo = r.next_int(11);
        a.push_back(Iv{lo, lo + r.next_int(5)});
    }
    return a;
}
// Remove one; translate all left (keeps every touching pair touching); then shift / shorten one.
std::vector<Ivs> shrink_intervals(const Ivs& a) {
    std::vector<Ivs> out;
    for (std::size_t i = 0; i < a.size(); ++i) {
        Ivs c = a;
        c.erase(c.begin() + static_cast<std::ptrdiff_t>(i));
        out.push_back(std::move(c));
    }
    if (!a.empty() && std::ranges::all_of(a, [](const Iv& v) { return v.lo > 0; })) {
        Ivs c = a;
        for (Iv& v : c) v = Iv{v.lo - 1, v.hi - 1};
        out.push_back(std::move(c));
    }
    for (std::size_t i = 0; i < a.size(); ++i) {
        const Iv v = a[i];
        std::vector<Iv> candidates;
        if (v.lo > 0) candidates.push_back(Iv{v.lo - 1, v.hi - 1});
        if (v.hi > v.lo) candidates.push_back(Iv{v.lo + 1, v.hi});
        if (v.hi > v.lo) candidates.push_back(Iv{v.lo, v.hi - 1});
        for (const Iv& w : candidates) {
            Ivs c = a;
            c[i] = w;
            out.push_back(std::move(c));
        }
    }
    return out;
}

// Oracle-free checks: properties any correct merge must satisfy.
std::string properties(int trials, std::uint64_t seed) {
    SplitMix64 r{seed};
    int idempotent = 0, order_free = 0, coverage = 0;
    auto covered = [](const Ivs& s, int p) { return std::ranges::any_of(s, [p](const Iv& v) { return v.lo <= p && p <= v.hi; }); };
    for (int t = 0; t < trials; ++t) {
        Ivs x = small_intervals(r), m = merge_sorted<true>(x);
        idempotent += merge_sorted<true>(m) == m;
        order_free += merge_sorted<true>(Ivs(x.rbegin(), x.rend())) == m;
        bool same = true;
        for (int p = 0; p <= 15; ++p) same = same && covered(x, p) == covered(m, p);
        coverage += same;
    }
    return std::format("idempotent {}/{}, input-order-free {}/{}, covers the same points {}/{}", idempotent, trials,
                       order_free, trials, coverage, trials);
}

int main() {
    constexpr int kTrials = 100'000;
    std::println("maximum subarray sum (fast vs O(n^2) oracle, sizes 0..8, values -10..10):");
    std::println("    v1 cur = max(0, cur + v), no empty check:   {}",
                 check<Array>(kTrials, 1, small_array, shrink_array, kadane_v1, max_subarray_oracle));
    std::println("    v2 rejects empty, still starts at 0:        {}",
                 check<Array>(kTrials, 1, small_array, shrink_array, kadane_v2, max_subarray_oracle));
    std::println("    v3 starts from the first element:           {}",
                 check<Array>(kTrials, 1, small_array, shrink_array, kadane_v3, max_subarray_oracle));
    std::println("    v2 again, 'realistic' generator (n<=1000, |v|<=1e9), 2,000 trials: {}",
                 check<Array>(2'000, 1, big_array, shrink_array, kadane_v2, max_subarray_oracle));
    std::println("merge closed intervals (fast vs pairwise-fixpoint oracle):");
    std::println("    v1 merges when next.lo <  last.hi:          {}",
                 check<Ivs>(kTrials, 2, small_intervals, shrink_intervals, merge_sorted<false>, merge_oracle));
    std::println("    v2 merges when next.lo <= last.hi:          {}",
                 check<Ivs>(kTrials, 2, small_intervals, shrink_intervals, merge_sorted<true>, merge_oracle));
    std::println("    v2 properties, no oracle needed: {}", properties(20'000, 3));
}
```

**Output, both compilers (verified; GCC shown, Clang identical):**

```text
maximum subarray sum (fast vs O(n^2) oracle, sizes 0..8, values -10..10):
    v1 cur = max(0, cur + v), no empty check:   FAIL at trial 2: []
        shrunk in 0 steps to []: fast 0, oracle threw std::invalid_argument
    v2 rejects empty, still starts at 0:        FAIL at trial 6: [-4]
        shrunk in 2 steps to [-1]: fast 0, oracle -1
    v3 starts from the first element:           passed 100000 random trials
    v2 again, 'realistic' generator (n<=1000, |v|<=1e9), 2,000 trials: FAIL at trial 711: [-518056415, -996644898, -380110124, -672683503]
        shrunk in 32 steps to [-1]: fast 0, oracle -1
merge closed intervals (fast vs pairwise-fixpoint oracle):
    v1 merges when next.lo <  last.hi:          FAIL at trial 8: [[1,2], [10,13], [6,10], [1,2], [7,9], [7,8]]
        shrunk in 21 steps to [[0,0], [0,0]]: fast [[0,0], [0,0]], oracle [[0,0]]
    v2 merges when next.lo <= last.hi:          passed 100000 random trials
    v2 properties, no oracle needed: idempotent 20000/20000, input-order-free 20000/20000, covers the same points 20000/20000
```

### 4.3 What the harness found

* **Two bugs in sequence, each reduced to a one-line counterexample.** v1 failed at trial 2 on `[]`, which is already minimal: the contract question "what is the maximum subarray of nothing?" was never answered. With that fixed (v2), the harness failed at trial 6 and shrank `[-4]` to `[-1]` in 2 steps: fast says 0, oracle says −1. That is the all-negative bug, stated as plainly as it can be. v3 passed 100,000 trials.
* **Small domains find bugs fast; "realistic" ones find them slowly.** The same v2 bug under a generator with up to 1,000 values of magnitude up to 10⁹ took **711** trials to surface. It only did because `n = 1 + nextInt(1000)` occasionally produces a tiny array. The first failing input then needed **32** shrink steps. Edge cases live at small sizes and small values, where collisions, zeros, negatives and ties are common.
* **The interval bug shrinks to its essence.** The first failing input had six intervals. After 21 shrink steps: `[[0,0], [0,0]]`, two identical points that v1 refuses to merge because `0 < 0` is false. The first shrinker version got stuck at `[[10,10],[6,10]]`. Shifting one interval alone breaks the "touching" relationship, so no single step could make progress. Adding a "translate everything left" candidate fixed it. *A shrinker needs moves that preserve the failure's structure.*
* **Properties need no oracle.** 20,000 random inputs confirmed that v2 is idempotent, input-order-free and conserves the covered points. When no slow oracle exists (an optimizer, a scheduler, a distributed protocol), properties like these are the test.
* **Determinism across languages.** Java and C++ share SplitMix64 and the same generator logic, and they agree on every trial number, counterexample and shrink count. Two independent implementations disagreeing would itself be a bug report.

### 4.4 How to say it in 60 seconds, in the round

"I've traced the example. The edge-case table: empty, which my contract says throws; one element; all negative, where the answer is the maximum element, not 0; all zeros; and the extremes, where the sum can exceed 32 bits, so it's `long`. Beyond that I'd write an O(n²) brute force as an oracle and compare on thousands of random arrays of length 0 to 8 with values −10..10, small on purpose so negatives and ties are common, and shrink any failure to a minimal case. For the interval merge there's also a property check: merging twice equals merging once, and the result doesn't depend on input order."

---

## 5. The last 10 minutes: Extensions A, B and C

### 5.1 Extension A — "64 threads use this API"

| Artefact | Thread-safety story |
|---|---|
| Immutable values (`Interval`, `Talker`, snapshots) | Thread-safe by construction once **safely published**: `final` fields in Java, `const` objects in C++. This is the strongest argument for value types: no locks, no reasoning about interleavings |
| The mutable `IntervalSet` | Not thread-safe; say so in the class comment. Options: confine it to one thread and publish immutable snapshots (single-writer, many-reader); a `ReadWriteLock` or `StampedLock` around it; or copy-on-write (writers build a new `TreeMap` and atomically swap a `volatile`/`AtomicReference`, readers never block) when reads vastly outnumber writes |
| Live views | **Never** hand a live view to another thread. Java's fail-fast check is best-effort and single-threaded in spirit; C++ has no check at all. Concurrent collections offer **weakly consistent** iterators instead, which never throw and reflect some state since creation |
| Iterators (merge) | Single-consumer by design. For many producers feeding one merge, put a bounded queue per source in front of it. For many consumers, partition the output range rather than share an iterator |
| The test harness | Concurrency bugs need different tools: stress runs with a start barrier and hot-key collisions; linearizability checkers such as Lincheck (Kotlin/JVM); `jcstress` for memory-model litmus tests; ThreadSanitizer for C++ data races |

### 5.2 Extension B — "the data is an infinite stream or 100 TB"

* **Iterators are the streaming API.** Pull-based iteration gives natural backpressure: the producer is asked for the next element only when the consumer is ready. The k-way merge is exactly the inner loop of external merge sort (Folder 07). With `k` runs on disk and a buffer per run, memory is `O(k × buffer)` regardless of `n`.
* **Snapshots of huge state** cannot be `O(n)` copies. Use persistent structures (structural sharing), MVCC (versioned values, readers see a consistent version), or an LSM-style immutable-segments design, where snapshots are "the current list of immutable files".
* **Testing streaming algorithms:** an oracle is often unavailable at scale, so test **properties with bounds**. "Every Space-Saving estimate is within `W/m` of the truth" was checked against exact counts in File 1. On a smaller replay, the exact answer *is* the oracle.

### 5.3 Extension C — "the data is spread over 100 machines"

* **Iterators become cursors.** A paginated API returns a page plus an opaque **continuation token** that encodes where to resume, such as the last key returned per shard. It never encodes "offset 10,000", which is `O(offset)` to resume and wrong if data shifts underneath. Scatter-gather queries are a distributed k-way merge: each shard returns its next sorted page, and the coordinator merges with the same heap-of-heads logic and stable tie-breaking (`(value, shardId)`), so repeated calls are deterministic.
* **Immutable snapshots become consistent reads.** "Return an immutable snapshot" across shards means a consistent cut: read at a timestamp (MVCC / snapshot isolation) or accept per-shard snapshots and document the anomaly.
* **Verification becomes fault injection.** Differential testing still applies (a single-node implementation is the oracle for the distributed one), and so do properties: idempotent retries, no lost or duplicated elements across a paginated scan. The distributed-systems analogues of this file's harness are Jepsen-style histories and deterministic simulation testing. Both use the same three ideas: generate, check against a model, shrink.

---

## 6. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Returning internal mutable state | Invariant broken by a caller; wrong answers later, far away | Snapshots or read-only views; value types without setters |
| F2 | Confusing "unmodifiable view" with "immutable" | Returned list changes under the caller | Name the method `view()` or `snapshot()` and document it; `List.copyOf` for snapshots |
| F3 | Records or structs with array, pointer or span members | Identity equality; leaked internals; `HashSet` duplicates | Immutable collection members + defensive copy; value members in C++ |
| F4 | Validation scattered across call sites | Invalid values slip in through the one path that forgot | Validate in the constructor / factory only; make invalid states unrepresentable |
| F5 | Iterating while mutating | Java CME (best-effort) or C++ UB | Snapshot first, or collect changes and apply after iteration |
| F6 | Live view shared across threads | Torn or stale reads, CME, UB | Immutable snapshots; concurrent collections with weakly consistent iterators |
| F7 | Materializing what could stream | `O(n)` memory, no output until input ends, impossible on infinite input | Lazy iterators / views with `O(k)` state |
| F8 | Silent garbage on contract-violating input | Unsorted source → unsorted "merged" output | Check the contract as data flows; fail loudly, naming the source |
| F9 | Testing only big random inputs | Edge-case bugs found after hundreds of trials, or never | Small domains; many trials; shrink |
| F10 | No oracle, so no tests | "It's hard to test" | Properties: idempotence, permutation invariance, conservation, round-trips, bounds |
| F11 | Non-deterministic tests | Failures that don't reproduce | Seeded RNG (SplitMix64); print the seed and the shrunk input |

---

## 7. Bar-raiser chains

<details><summary><b>Q1 · "Why not just return the list? It's simpler."</b></summary>

**Initial Prompt.** The candidate's class has `List<int[]> getIntervals()` returning the field.

**L5 Answer.** "Callers shouldn't modify it; I'll add a comment."

**Why L5 Stalls.** A comment is not enforcement. The invariant now depends on every caller, and the failure appears later in an unrelated method, exactly as in Listing 3.1, where `covered()` went wrong one `add` after the write.

**L7 Answer.** "The set's correctness argument is local only if nobody else can write its representation. I'd return an immutable snapshot (`List.copyOf` of immutable `Interval` records), which costs `O(n)`, or a read-only live view if callers need to observe changes cheaply, and name and document which. Elements must be immutable too, otherwise 'unmodifiable list' still allows `get(0)[1] = 12`."
</details>

<details><summary><b>Q2 · "Your record has an int[] field. Any problem?"</b></summary>

**Initial Prompt.** `record Path(int[] nodes)` is used as a `HashMap` key for memoization.

**L5 Answer.** "Records are immutable, so it's fine."

**Why L5 Stalls.** Records are *shallowly* immutable. `equals`/`hashCode` on an array component use identity, so two equal paths are different keys and the memo never hits. The accessor also returns the live array.

**L7 Answer.** "That breaks memoization: equal paths aren't equal keys, and anyone can mutate the array after hashing. I'd store `List<Integer>` with `List.copyOf` in the compact constructor. Or, if boxing matters, keep the `int[]`, clone it in and out, and override `equals`/`hashCode` with `Arrays.equals`/`Arrays.hashCode`. In C++ the analogue is a defaulted `==` over a pointer or span member: pointers compare addresses, and `std::span` doesn't even have `==`."
</details>

<details><summary><b>Q3 · "Merge k sorted lists — can you do better than concatenate and sort?"</b></summary>

**Initial Prompt.** LeetCode 23, in a Staff round.

**L5 Answer.** "A min-heap of the k heads: O(n log k) instead of O(n log n)."

**Why L5 Stalls.** Right algorithm, but the candidate claims a speed win that may not exist in RAM, and stops at a function that returns a full list.

**L7 Answer.** "Asymptotically, yes: `O(n log k)`. In RAM, concatenate-and-sort can actually win: TimSort detects pre-sorted runs, and I measured concatenate-and-sort 17–30% faster than a heap merge for 64 runs. The real wins are memory, `O(k)` instead of `O(n)`, and latency to the first element. So I'd expose it as a lazy iterator: one head per source in a heap ordered by `(value, sourceIndex)` for stable ties, checking that each source really is sorted. Then the same component merges files bigger than RAM in an external sort, or result pages from 100 shards."
</details>

<details><summary><b>Q4 · "What does your iterator promise?"</b></summary>

**Initial Prompt.** The interviewer asks the candidate to document the custom iterator.

**L5 Answer.** "It returns elements in sorted order."

**Why L5 Stalls.** An iterator contract has more clauses than order: end behaviour, null handling, pass-count, concurrent modification, failure behaviour.

**L7 Answer.** "Sorted output, with ties in source order. `O(k)` memory, `O(log k)` per element. Single-pass. `next()` past the end throws `NoSuchElementException`; null elements and out-of-order sources throw immediately, naming the source. Not thread-safe; one consumer. The sources must not be modified during iteration. In C++ it models `input_range` and *not* `forward_range`, enforced with `static_assert`, and the view must not move while being iterated."
</details>

<details><summary><b>Q5 · "How do you know your solution is correct?"</b></summary>

**Initial Prompt.** After the candidate finishes coding maximum subarray.

**L5 Answer.** Traces the example array and says it works.

**Why L5 Stalls.** The example contains positives. The all-negative case and the empty case, the two real bugs, are never exercised.

**L7 Answer.** "Edge cases first: empty, which the contract must define; I'd throw. Single element. All negative, where the answer is the max element, so the running best must start from the first element, not 0. All zero. Large magnitudes, so the sum is `long`. Then I'd test it like a contest stress test but keep the harness: a brute-force O(n²) oracle, thousands of random arrays of length 0–8 with values in −10..10, and automatic shrinking. With exactly that setup the all-negative bug surfaces in 6 trials and shrinks to `[-1]`."
</details>

<details><summary><b>Q6 · "Why small random inputs? Production data is big."</b></summary>

**Initial Prompt.** The interviewer challenges the generator choice.

**L5 Answer.** "Big inputs are more realistic."

**Why L5 Stalls.** Bugs concentrate at boundaries: empty, single, equal, negative, zero, touching. Big random inputs almost never hit them.

**L7 Answer.** "The probability of hitting an edge case falls fast with size. A 1,000-element random array is almost never all negative. In my measurement the same bug took 711 trials with large inputs versus 6 with small ones, and the failing input needed 32 shrink steps instead of 2. Small domains also make the oracle cheap. I keep a separate large-input test for performance and overflow, which is a different property."
</details>

<details><summary><b>Q7 · "There's no slow oracle for this. How do you test it?"</b></summary>

**Initial Prompt.** A scheduling or optimization component where the "correct" answer is itself hard to compute.

**L5 Answer.** "Hand-written test cases."

**Why L5 Stalls.** Hand-written cases encode the author's blind spots.

**L7 Answer.** "Properties. For a merge: idempotent, order-independent, covers exactly the input points. For a sort: a sorted permutation of the input. For an encoder: `decode(encode(x)) == x`. For a scheduler: no two jobs overlap, every job scheduled once, total cost no worse than a trivial schedule. Each runs on thousands of random inputs. On small instances, a brute-force or ILP solver can serve as an oracle even when it's too slow for production."
</details>

<details><summary><b>Q8 · "This set will be read by many threads. Change anything?"</b></summary>

**Initial Prompt.** Extension A on the interval set.

**L5 Answer.** "Add `synchronized` to every method."

**Why L5 Stalls.** Readers serialize with each other and with writers. Iteration over a view is still unsafe, because `synchronized` methods don't protect a caller's for-each loop.

**L7 Answer.** "It depends on the read/write ratio. If reads dominate: copy-on-write. Writers build a new immutable map and publish it through an `AtomicReference`, and readers take a snapshot with one volatile read and never block. If writes are frequent: a `StampedLock` with optimistic reads for `covers`, and `snapshot()` taken under the read lock. Live views are never shared across threads. Immutable `Interval` values need no synchronization at all, which is why they're values."
</details>

---

## 8. Checklist

* [ ] State the representation invariant and the abstraction function in one sentence each.
* [ ] No getter returns mutable internal state; each API returns a **snapshot** or a **view**, named and documented.
* [ ] Value types validate once (compact constructor / private constructor + factory) and have no setters.
* [ ] Value types contain only value members (immutable collections, not arrays, pointers or spans).
* [ ] Errors: exceptions or `expected` for bad input; unrepresentable types for impossible input.
* [ ] Iterators document order, ties, pass-count, end behaviour, failure behaviour and thread-safety.
* [ ] Prefer lazy iteration when input may be large, infinite or remote.
* [ ] Verification ladder aloud: example → edge-case table → oracle on small random inputs → shrink → properties.
* [ ] Seeded RNG; print seed and shrunk input.
* [ ] Extension A: immutable values + published snapshots; COW vs locks by read/write ratio.
* [ ] Extension B: iterators as streaming backpressure; persistent/MVCC snapshots; property tests with bounds.
* [ ] Extension C: continuation tokens, not offsets; scatter-gather merge with stable ties; consistent cuts.

---

## 9. References

* J. Bloch, *Effective Java*, 3rd ed. (2018): Item 17 "Minimize mutability", Item 50 "Make defensive copies when needed".
* B. Liskov, J. Guttag, *Program Development in Java: Abstraction, Specification, and Object-Oriented Design* (2000): rep invariants, abstraction functions, rep exposure.
* JEP 395, *Records* — <https://openjdk.org/jeps/395>; JEP 431, *Sequenced Collections* — <https://openjdk.org/jeps/431>
* Java SE 21 API: `Iterator` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/Iterator.html>; `Collections.unmodifiableSequencedCollection` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/Collections.html>; `ConcurrentModificationException` (fail-fast is best-effort) — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/ConcurrentModificationException.html>; `java.util.concurrent` package summary (weakly consistent iterators) — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/package-summary.html>
* cppreference: iterator concepts — <https://en.cppreference.com/w/cpp/iterator>; `std::ranges::view_interface` — <https://en.cppreference.com/w/cpp/ranges/view_interface>; `basic_istream_view` — <https://en.cppreference.com/w/cpp/ranges/basic_istream_view>; `std::span` — <https://en.cppreference.com/w/cpp/container/span>; `std::map` (iterator invalidation) — <https://en.cppreference.com/w/cpp/container/map>
* T. Winters et al., *Software Engineering at Google* (O'Reilly, 2020), chapters on testing — <https://abseil.io/resources/swe-book>
* C++ Core Guidelines — <https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines>
* K. Claessen, J. Hughes, *QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs*, ICFP 2000 — DOI 10.1145/351240.351266
* A. Zeller, R. Hildebrandt, *Simplifying and Isolating Failure-Inducing Input*, IEEE TSE 28(2), 2002 — DOI 10.1109/32.988498
* Hypothesis (property-based testing with shrinking) — <https://hypothesis.readthedocs.io/>; jqwik — <https://jqwik.net/>; Lincheck — <https://github.com/JetBrains/lincheck>; jcstress — <https://github.com/openjdk/jcstress>
* LeetCode anchors: [23 Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/), [53 Maximum Subarray](https://leetcode.com/problems/maximum-subarray/), [56 Merge Intervals](https://leetcode.com/problems/merge-intervals/), [57 Insert Interval](https://leetcode.com/problems/insert-interval/), [715 Range Module](https://leetcode.com/problems/range-module/)

*Folder 01:* [01 — how bar-raisers grade](01-how-bar-raisers-grade-l5-vs-l6-vs-l7-in-45-minute-coding-rounds.md) · [02 — cache-aware algorithms, branch prediction and hidden Big-O constants](02-cache-aware-algorithms-branch-prediction-and-hidden-big-o-constants.md)
