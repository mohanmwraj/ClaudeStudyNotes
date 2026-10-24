# 2.8 · Pillar 2 — Interview & Certification Question Bank (Core Java)

> **Use:** Section A is flashcards. Section B holds senior/architect scenarios. Section C has **1Z0-830 / 1Z0-831-style** code questions (original practice items, not exam content). **Every code question in Section C was compiled and run on JDK 25**, and the stated answers are the real outputs. Questions marked *compile?* were verified to fail compilation with the quoted error.
> Exam facts (third-party sources, confirm on education.oracle.com): 1Z0-831 (Java SE 25 Developer Professional) has 50 questions in 120 minutes with a 68% passing score. The topics include gatherers, scoped values, module import declarations, compact source files and flexible constructor bodies, on top of the 1Z0-830 (Java SE 21) syllabus.

---

## A. Rapid-fire

<details><summary><b>A1–A15</b></summary>

1. **`HashMap` default capacity / load factor / treeify threshold?** 16 / 0.75 / 8 (table ≥ 64).
2. **Why is `HashMap`'s capacity a power of two?** Index = `(n-1) & hash`, a single AND instead of a modulo.
3. **Which iterator never throws CME and never sees later updates?** `CopyOnWriteArrayList`'s snapshot iterator.
4. **`List.of(1,2).contains(null)`?** Throws `NullPointerException`.
5. **What does `Stream.toList()` return?** An unmodifiable list that allows nulls.
6. **`Collectors.partitioningBy` with no matches?** Both keys present, with empty lists.
7. **Name the JDK 24 API for custom intermediate stream ops.** Stream Gatherers (`Stream.gather`, `Gatherer`, `Gatherers`).
8. **What does `Gatherers.mapConcurrent` use?** Virtual threads, bounded concurrency, order preserved.
9. **What translates lambdas at run time?** `invokedynamic` + `LambdaMetafactory` → hidden class.
10. **Is a non-capturing lambda a new object per evaluation?** No, it's a singleton per call site.
11. **What implements string concatenation since JDK 9?** `invokedynamic` → `StringConcatFactory.makeConcatWithConstants`.
12. **What's the `coder` field in `String`?** LATIN1 (0) or UTF16 (1), from compact strings.
13. **What implements records' `equals/hashCode/toString`?** `invokedynamic` → `ObjectMethods.bootstrap`.
14. **Which attribute lists a sealed class's subclasses?** `PermittedSubclasses`.
15. **What exception does an exhaustive switch throw for an unknown subtype at run time?** `MatchException`.
</details>

<details><summary><b>A16–A30</b></summary>

16. **Pattern switch on a `null` selector without `case null`?** NPE.
17. **Can a record declare instance fields?** No, only static fields.
18. **What do you assign in a compact constructor?** The parameters (fields are assigned after the body).
19. **What does `ArrayList` grow by?** About 1.5× (`old + old>>1`).
20. **`ArrayDeque` and null?** Rejects null elements.
21. **What is PECS?** Producer `extends`, Consumer `super`.
22. **What is a bridge method?** A synthetic method preserving overriding after erasure (casts and delegates).
23. **Overload resolution phases?** (1) no boxing or varargs, (2) boxing, (3) varargs.
24. **Static method in a subclass with the same signature?** Hiding, resolved by static type.
25. **Order of closing in try-with-resources?** Reverse order of declaration.
26. **Where do close exceptions go when the body throws?** Into `getSuppressed()` of the primary exception.
27. **`DateTimeFormatter` vs `SimpleDateFormat` thread safety?** Immutable and safe vs not thread-safe.
28. **`YYYY` in a pattern?** Week-based year.
29. **`BigDecimal.equals` considers?** Value **and** scale.
30. **Default rounding of `DecimalFormat`?** `HALF_EVEN`.
</details>

---

## B. Senior scenarios

<details><summary><b>B1. 🔥 A service uses `Map<String, Customer>` caches. GC logs show the old generation dominated by `HashMap$Node` and `String`. How do you reduce the footprint without changing behaviour?</b></summary>

Measure first: a histogram or heap dump gives the number of entries and the bytes per entry (~58 B per entry plus key and value objects). Options: replace boxed/primitive-keyed maps with primitive collections; canonicalize repeated strings (bounded interner, or G1 string dedup for long-lived ones); store compact value objects (records with primitives) instead of rich entities; use `EnumMap`/`BitSet` for enum or flag keys; cap the size with eviction (Caffeine with a weight limit); consider off-heap stores for very large caches; enable compact object headers (JDK 25+), which saves ~8 B per `Node`. Verify with before/after JOL or histograms.
</details>

<details><summary><b>B2. 🔥 When would you choose records + sealed interfaces over a class hierarchy with polymorphic methods?</b></summary>

When the **set of variants is closed and owned by you**, and **operations are many and evolving** (renderers, validators, serializers, pricing rules). Data-oriented: data is transparent, operations live in exhaustive switches, and adding an operation doesn't touch the data classes. Classic OOP polymorphism wins when the set of variants is **open** (plugins, third-party extensions) and operations are few and stable. Sealed + records also give compiler-checked exhaustiveness, which is valuable for domain events, API results and command handling.
</details>

<details><summary><b>B3. ⚡ A teammate wants to use `parallelStream()` to speed up an API endpoint that enriches 50 items via HTTP calls. Your response?</b></summary>

No. It's I/O-bound, the commonPool is shared JVM-wide and sized for CPU work (cores − 1), and blocking it starves every other parallel stream and `CompletableFuture` in the service. It also can't bound concurrency per downstream. Use virtual threads with a concurrency limit: `Gatherers.mapConcurrent(10, this::enrich)`, `StructuredTaskScope` (preview), or an executor plus a `Semaphore`. Add timeouts and a circuit breaker per dependency (Pillar 6).
</details>

<details><summary><b>B4. ⚡ How do you design an API to avoid "exception as control flow" while keeping errors explicit?</b></summary>

Return types that encode outcomes: `Optional` for absence, sealed `Result` hierarchies (`Success`/`NotFound`/`Invalid`) consumed with exhaustive switches, and validation that accumulates errors. Reserve exceptions for exceptional, non-local failures (I/O failure, programming errors, invariants violated). At transport boundaries, map results and exceptions to protocol errors (RFC 9457 Problem Details).
</details>

<details><summary><b>B5. 🧊 Why might code using `Comparator.comparing(...)` in a hot sort be slower in production than in a benchmark, and what would you do?</b></summary>

The comparator lambdas and the `TimSort` call sites are shared across the application, so their type profiles become megamorphic and C2 stops inlining the key extractors (profile pollution). Boxing of keys may also not be eliminated. Mitigations: primitive-specialized comparators (`comparingInt`); a hand-written comparator class for the hot path; sorting primitive arrays of keys; or caching sort keys. Measure with production-like profiles (JMH with polluted profiles, or async-profiler in prod).
</details>

---

## C. Certification-style code questions (all verified on JDK 25)

> Read each snippet and predict the output **before** opening the answer. The snippets are complete programs. Run them with `java File.java`.

### C1 — StringBuilder chaining

<!-- run: -->
```java
public class Q01 {
    public static void main(String[] args) {
        StringBuilder sb = new StringBuilder("abcdef");
        sb.insert(2, "X").delete(0, 1).reverse();
        sb.setLength(4);
        System.out.println(sb);
    }
}
```

<details><summary>Answer</summary>

`fedc`. "abcdef" → insert at 2 → "abXcdef" → delete [0,1) → "bXcdef" → reverse → "fedcXb" → setLength(4) → "fedc". `StringBuilder` methods mutate and return `this`, except `setLength`, which returns `void` and therefore can't be chained.
</details>

### C2 — String immutability

<!-- run: -->
```java
public class Q02 {
    public static void main(String[] args) {
        String s = " Java ";
        s.trim();
        s.concat("!");
        String t = s.strip().toUpperCase().replace('A', '4');
        System.out.println("[" + s + "][" + t + "]" + s.indexOf('a') + t.lastIndexOf("4") + s.charAt(1));
    }
}
```

<details><summary>Answer</summary>

`[ Java ][J4V4]23J`. `trim()` and `concat()` results are discarded, so `s` is unchanged. After `"]"` everything concatenates as strings: `indexOf('a')` = 2, `lastIndexOf("4")` = 3, `charAt(1)` = `J`.
</details>

### C3 — Text block content

<!-- run: -->
```java
public class Q03 {
    public static void main(String[] args) {
        String tb = """
            a\tb
              c \
            d
            """;
        System.out.println(tb.lines().count() + ":" + tb.length());
    }
}
```

<details><summary>Answer</summary>

`2:10`. Incidental indentation is removed. Line 1 is `a<TAB>b` (3 chars). The `\` joins line 2 and line 3 into `  c d` (5 chars; the space before `\` is not trailing whitespace, so it is kept). Each line ends with `\n`: 3+1+5+1 = 10.
</details>

### C4 — Switch: arrows vs fall-through

<!-- run: -->
```java
public class Q04 {
    public static void main(String[] args) {
        int day = 3;
        String r = switch (day) {
            case 1, 7 -> "weekend";
            case 2, 3, 4, 5, 6 -> { String x = "week"; yield x + "day"; }
            default -> "?";
        };
        int n = 2, total = 0;
        switch (n) {
            case 1: total += 1;
            case 2: total += 2;
            case 3: total += 3; break;
            default: total += 100;
        }
        System.out.println(r + " " + total);
    }
}
```

<details><summary>Answer</summary>

`weekday 5`. A block in an arrow case returns its value with `yield`. The colon-style switch falls through from `case 2` into `case 3` (2 + 3 = 5) until `break`.
</details>

### C5 — Pattern switch with guards and null

<!-- run: -->
```java
public class Q05 {
    static String f(Object o) {
        return switch (o) {
            case null -> "null";
            case Integer i when i > 10 -> "big";
            case Integer i -> "int";
            case String s -> "str:" + s.length();
            default -> "other";
        };
    }
    public static void main(String[] args) {
        System.out.println(f(42) + f(7) + f("ab") + f(null) + f(1.0));
    }
}
```

<details><summary>Answer</summary>

`bigintstr:2nullother`. Labels are tested top-down, and the guard fails for 7, so it falls to the unguarded `Integer` label. `case null` handles null (no NPE). `Double` hits `default`.
</details>

### C6 — Record compact constructor

<!-- run: -->
```java
public class Q06 {
    record Range(int lo, int hi) {
        Range { if (lo > hi) { int t = lo; lo = hi; hi = t; } }
    }
    public static void main(String[] args) {
        var r1 = new Range(5, 1);
        var r2 = new Range(1, 5);
        System.out.println(r1 + " " + r1.equals(r2) + " " + (r1.hashCode() == r2.hashCode()));
    }
}
```

<details><summary>Answer</summary>

`Range[lo=1, hi=5] true true`. The compact constructor reassigns the *parameters*, and the fields are assigned from them afterwards. Records use component-wise `equals`/`hashCode`.
</details>

### C7 — Overridable call from a constructor

<!-- run: -->
```java
public class Q07 {
    static class A { A() { show(); } void show() { System.out.print("A"); } }
    static class B extends A { int x = 5; @Override void show() { System.out.print("B" + x); } }
    public static void main(String[] args) { new B(); System.out.println(); }
}
```

<details><summary>Answer</summary>

`B0`. `A()` runs before `B`'s field initializers. The dynamically dispatched `show()` sees `x` still at its default value 0. (JDK 25's flexible constructor bodies let `B` assign `x` before `super()`.)
</details>

### C8 — Field hiding vs method overriding

<!-- run: -->
```java
public class Q08 {
    static class P { String v = "P"; String get() { return v; } }
    static class C extends P { String v = "C"; @Override String get() { return v + super.v; } }
    public static void main(String[] args) {
        P p = new C();
        System.out.println(p.v + p.get() + ((C) p).v);
    }
}
```

<details><summary>Answer</summary>

`PCPC`. Field access uses the static type (`p.v` → `P`). The method call is virtual (`C.get()` → `"C" + "P"`). After the cast, `.v` is C's field.
</details>

### C9 — `finally` and return values

<!-- run: -->
```java
public class Q09 {
    static int f() {
        int x = 1;
        try { x = 2; throw new RuntimeException(); }
        catch (RuntimeException e) { x = 3; return x; }
        finally { x = 4; System.out.print("F" + x); }
    }
    public static void main(String[] args) { System.out.println(f()); }
}
```

<details><summary>Answer</summary>

`F43`. The `catch` evaluates `return x` (3) and stores it, `finally` runs (prints `F4`; changing `x` doesn't affect the stored value), then 3 is returned and printed.
</details>

### C10 — Resource initialization failure

<!-- run: -->
```java
public class Q10 {
    record R(String n, boolean failOpen) implements AutoCloseable {
        R {
            if (failOpen) throw new IllegalStateException("open " + n);
            System.out.print("open" + n + " ");
        }
        public void close() { System.out.print("close" + n + " "); }
    }
    public static void main(String[] args) {
        try (var a = new R("A", false); var b = new R("B", true)) {
            System.out.print("body ");
        } catch (IllegalStateException e) {
            System.out.println("caught " + e.getMessage());
        }
    }
}
```

<details><summary>Answer</summary>

`openA closeA caught open B`. Resource B's initialization throws, so the body never runs. Already-opened resources (A) are closed, then the `catch` runs.
</details>

### C11 — *compile?* Overriding with a broader checked exception

<!-- run: compilefail expect="cannot override" -->
```java
import java.io.IOException;

public class Q11 {
    static class Base { void load() throws IOException { } }
    static class Sub extends Base { @Override void load() throws Exception { } }
}
```

<details><summary>Answer</summary>

Does **not** compile: `load() in Sub cannot override load() in Base; overridden method does not throw Exception`. An override may throw fewer or narrower checked exceptions, never broader ones.
</details>

### C12 — *compile?* Multi-catch parameter reassignment

<!-- run: compilefail expect="multi-catch parameter" -->
```java
import java.io.IOException;

public class Q12 {
    static void f() {
        try { if (System.nanoTime() > 0) throw new IOException(); }
        catch (IOException | RuntimeException e) { e = new RuntimeException(); }
    }
}
```

<details><summary>Answer</summary>

Does **not** compile: `multi-catch parameter e may not be assigned`. A multi-catch parameter is implicitly final.
</details>

### C13 — *compile?* Adding to an `extends` wildcard list

<!-- run: compilefail expect="incompatible types" -->
```java
import java.util.*;

public class Q13 {
    static void f() {
        List<? extends Number> nums = new ArrayList<Integer>();
        nums.add(1);
    }
}
```

<details><summary>Answer</summary>

Does **not** compile (`incompatible types: int cannot be converted to CAP#1`). The compiler doesn't know the exact element type, so only `null` can be added. Use `? super Integer` for a consumer.
</details>

### C14 — `TreeMap` navigation

<!-- run: -->
```java
import java.util.*;

public class Q14 {
    public static void main(String[] args) {
        var m = new TreeMap<>(Map.of(10, "a", 20, "b", 30, "c"));
        System.out.println(m.headMap(20) + " " + m.tailMap(20, false) + " " + m.ceilingKey(15) + " "
            + m.descendingMap().firstKey() + " " + m.pollFirstEntry() + " " + m);
    }
}
```

<details><summary>Answer</summary>

`{10=a} {30=c} 20 30 10=a {20=b, 30=c}`. `headMap(20)` is exclusive and `tailMap(20, false)` is exclusive. `ceilingKey(15)` = 20. The descending map's first key is 30. `pollFirstEntry` removes `10=a`, and the final print shows the mutated map (the expression is evaluated left to right).
</details>

### C15 — `ArrayDeque` as stack and queue

<!-- run: -->
```java
import java.util.*;

public class Q15 {
    public static void main(String[] args) {
        Deque<Integer> d = new ArrayDeque<>();
        d.push(1); d.push(2); d.offer(3); d.addFirst(4);
        System.out.println(d + " " + d.pop() + " " + d.pollLast() + " " + d.peek() + " " + d);
    }
}
```

<details><summary>Answer</summary>

`[4, 2, 1, 3] 4 3 2 [2, 1]`. `push`/`addFirst` insert at the head and `offer` at the tail. `pop` removes the head (4), `pollLast` the tail (3), and `peek` reads the head (2).
</details>

### C16 — `Arrays` utilities

<!-- run: -->
```java
import java.util.Arrays;

public class Q16 {
    public static void main(String[] args) {
        int[] a = {3, 1, 2}, b = {3, 1, 2};
        System.out.println(a.equals(b) + " " + Arrays.equals(a, b) + " " + Arrays.compare(new int[] {1, 2}, new int[] {1, 3})
            + " " + Arrays.mismatch(new int[] {1, 2, 3}, new int[] {1, 2, 4}));
        Arrays.sort(a);
        System.out.println(Arrays.toString(a) + " " + Arrays.binarySearch(a, 5));
    }
}
```

<details><summary>Answer</summary>

`false true -1 2` then `[1, 2, 3] -4`. Arrays don't override `equals` (identity). `Arrays.compare` is lexicographic (negative). `mismatch` returns the first differing index (2). `binarySearch` for a missing key returns `-(insertionPoint) - 1` = −(3) − 1 = −4.
</details>

### C17 — Streams: reduce and grouping

<!-- run: -->
```java
import java.util.TreeMap;
import java.util.stream.*;

public class Q17 {
    public static void main(String[] args) {
        var r = Stream.of("apple", "banana", "cherry", "avocado").filter(s -> s.startsWith("a")).map(String::length).reduce(0, Integer::sum);
        var g = Stream.of("apple", "banana", "cherry", "avocado").collect(Collectors.groupingBy(s -> s.charAt(0), TreeMap::new, Collectors.counting()));
        System.out.println(r + " " + g);
    }
}
```

<details><summary>Answer</summary>

`12 {a=2, b=1, c=1}`: 5 ("apple") + 7 ("avocado"). The `TreeMap` factory gives sorted keys, and `counting()` produces `Long` values.
</details>

### C18 — Primitive streams and collectors

<!-- run: -->
```java
import java.util.IntSummaryStatistics;
import java.util.stream.*;

public class Q18 {
    public static void main(String[] args) {
        IntSummaryStatistics st = IntStream.rangeClosed(1, 4).map(i -> i * i).summaryStatistics();
        System.out.println(st.getSum() + " " + st.getAverage() + " "
            + IntStream.range(1, 4).boxed().collect(Collectors.toMap(i -> i, i -> i * 10)) + " "
            + Stream.of(1, 2, 3, 4).skip(1).limit(2).toList());
    }
}
```

<details><summary>Answer</summary>

`30 7.5 {1=10, 2=20, 3=30} [2, 3]`. Squares 1+4+9+16 = 30, average 7.5. `range` excludes the end. `skip(1).limit(2)` gives `[2, 3]`.
</details>

### C19 — `Optional` chaining

<!-- run: -->
```java
import java.util.Optional;

public class Q19 {
    public static void main(String[] args) {
        Optional<String> o = Optional.of("  ").map(String::strip).filter(s -> !s.isEmpty());
        System.out.println(o.isPresent() + " " + o.orElse("empty") + " " + Optional.ofNullable(null).or(() -> Optional.of("alt")).get());
    }
}
```

<details><summary>Answer</summary>

`false empty alt`. `strip` yields `""`, which the filter rejects, leaving an empty Optional. `or` (JDK 9) supplies an alternative Optional.
</details>

### C20 — Gatherers (1Z0-831)

<!-- run: -->
```java
import java.util.stream.*;

public class Q20 {
    public static void main(String[] args) {
        System.out.println(Stream.of(1, 2, 3, 4, 5).gather(Gatherers.windowSliding(3))
            .map(w -> w.stream().mapToInt(Integer::intValue).sum()).toList());
        System.out.println(Stream.of(1, 2, 3, 4, 5).gather(Gatherers.windowFixed(2)).toList()
            + " " + Stream.of(1, 2, 3).gather(Gatherers.scan(() -> 10, Integer::sum)).toList());
    }
}
```

<details><summary>Answer</summary>

`[6, 9, 12]`, then `[[1, 2], [3, 4], [5]] [11, 13, 16]`. Sliding windows of 3: (1,2,3), (2,3,4), (3,4,5). Fixed windows keep a short last window. `scan` emits running results starting from the initial value 10: 10+1, 11+2, 13+3.
</details>

### C21 — Date arithmetic

<!-- run: -->
```java
import java.time.*;

public class Q21 {
    public static void main(String[] args) {
        LocalDate d = LocalDate.of(2026, 2, 28);
        System.out.println(d.plusDays(1) + " " + d.plusYears(2).plusDays(1) + " "
            + Period.between(d, LocalDate.of(2026, 5, 1)) + " " + d.getDayOfWeek() + " " + Duration.ofMinutes(135));
    }
}
```

<details><summary>Answer</summary>

`2026-03-01 2028-02-29 P2M3D SATURDAY PT2H15M`. 2026 isn't a leap year, but 2028 is. Feb 28 + 2 months = Apr 28, then + 3 days = May 1. `Duration.toString` uses ISO-8601 (`PT2H15M`).
</details>

### C22 — Localized formatting

<!-- run: -->
```java
import java.text.NumberFormat;
import java.util.Locale;

public class Q22 {
    public static void main(String[] args) {
        var nf = NumberFormat.getCurrencyInstance(Locale.US);
        System.out.println(nf.format(-1234.5) + " " + String.format(Locale.GERMANY, "%.2f", 1234.5) + " "
            + Locale.of("fr", "CA").getDisplayCountry(Locale.ENGLISH) + " " + Locale.forLanguageTag("pt-BR").getLanguage());
    }
}
```

<details><summary>Answer</summary>

`-$1,234.50 1234,50 Canada pt`. US currency format with a minus sign (CLDR). `%.2f` has no grouping flag, so there's no thousands separator, but there is a German decimal comma. The display country is in English, and the language code is `pt`.
</details>

### C23 — *compile?* `var` without an initializer

<!-- run: compilefail expect="cannot infer type" -->
```java
public class Q23 {
    static void f() {
        var x;
        x = 10;
    }
}
```

<details><summary>Answer</summary>

Does **not** compile: `cannot infer type for local variable x (cannot use 'var' on variable without initializer)`. `var` also can't be used with `null` initializers, array initializers (`var a = {1}`), fields, or parameters.
</details>

### C24 — Labeled `break` / `continue`

<!-- run: -->
```java
public class Q24 {
    public static void main(String[] args) {
        int count = 0;
        outer:
        for (int i = 0; i < 3; i++) {
            for (int j = 0; j < 3; j++) {
                if (j == 2) continue outer;
                if (i == 2) break outer;
                count++;
            }
        }
        System.out.println(count);
    }
}
```

<details><summary>Answer</summary>

`4`. For i = 0 and i = 1, j = 0 and 1 increment (4 total), and j = 2 continues the outer loop. At i = 2, j = 0 breaks out of both loops.
</details>

### C25 — Increment operators

<!-- run: -->
```java
public class Q25 {
    public static void main(String[] args) {
        int i = 5;
        int j = i++ + ++i;     // 5 + 7
        int k = i-- - --i;     // 7 - 5
        System.out.println(i + " " + j + " " + k);
    }
}
```

<details><summary>Answer</summary>

`5 12 2`. Operands are evaluated left to right: `i++` yields 5 (i becomes 6), `++i` makes i 7 and yields 7, so j = 12. `i--` yields 7 (i becomes 6), `--i` makes i 5 and yields 5, so k = 2, and i ends at 5.
</details>

### C26 — Casts and rounding

<!-- run: -->
```java
public class Q26 {
    public static void main(String[] args) {
        System.out.println((int) 7.9 + " " + Math.round(-2.5) + " " + Math.round(2.5) + " " + (5 / 2.0) + " " + (char) 66 + " " + (byte) 200);
    }
}
```

<details><summary>Answer</summary>

`7 -2 3 2.5 B -56`. A cast truncates toward zero. `Math.round(x)` = `floor(x + 0.5)`, giving −2 and 3. A `double` operand gives floating division. 66 is `B`. 200 wraps to −56 in a signed byte.
</details>

### C27 — Enum with constructor and the `+` trap

<!-- run: -->
```java
public class Q27 {
    enum Size { S(1), M(2), L(3); final int w; Size(int w) { this.w = w; } }
    public static void main(String[] args) {
        System.out.println(Size.valueOf("M").w + Size.L.ordinal() + " " + Size.values()[0] + " " + Size.M.compareTo(Size.S));
    }
}
```

<details><summary>Answer</summary>

`4 S 1`. `2 + 2` is **numeric** addition (both operands are ints) before the first string is reached. `values()[0]` is `S`. `compareTo` is the ordinal difference, 1 − 0.
</details>

### C28 — *compile?* Conflicting default methods

<!-- run: compilefail expect="are incompatible" -->
```java
public class Q28 {
    interface A { default String hi() { return "A"; } }
    interface B { default String hi() { return "B"; } }
    static class C implements A, B { }
}
```

<details><summary>Answer</summary>

Does **not** compile: `types A and B are incompatible; class C inherits unrelated defaults for hi() from types A and B`. `C` must override `hi()` (optionally calling `A.super.hi()`).
</details>

### C29 — Switch fall-through from `default`

<!-- run: -->
```java
public class Q29 {
    public static void main(String[] args) {
        String s = "B";
        switch (s) {
            default: System.out.print("D");
            case "A": System.out.print("A"); break;
            case "C": System.out.print("C");
        }
        System.out.println();
    }
}
```

<details><summary>Answer</summary>

`DA`. No label matches, so control goes to `default` (its textual position doesn't matter for matching), then falls through to `case "A"` and stops at `break`.
</details>

### C30 — Private methods are not overridden

<!-- run: -->
```java
public class Q30 {
    static class X { private String id() { return "X"; } String call() { return id(); } }
    static class Y extends X { String id() { return "Y"; } }
    public static void main(String[] args) { System.out.println(new Y().call()); }
}
```

<details><summary>Answer</summary>

`X`. Private methods aren't inherited, so `Y.id()` is a new, unrelated method. `X.call()` binds to `X.id()` statically.
</details>

### C31 — Comparators with nulls

<!-- run: -->
```java
import java.util.*;

public class Q31 {
    public static void main(String[] args) {
        List<String> l = new ArrayList<>(Arrays.asList("b", null, "a", "C"));
        l.sort(Comparator.nullsFirst(String.CASE_INSENSITIVE_ORDER));
        System.out.print(l + " ");
        l.sort(Comparator.nullsLast(Comparator.<String>naturalOrder().reversed()));
        System.out.println(l);
    }
}
```

<details><summary>Answer</summary>

`[null, a, b, C] [b, a, C, null]`. Case-insensitive ordering puts `C` after `b`. With natural ordering reversed, lowercase letters (code points 97+) come before uppercase `C` (67), and `nullsLast` puts null last.
</details>

### C32 — Interfaces: static methods aren't inherited (*compile?*)

<!-- run: compilefail expect="cannot find symbol" -->
```java
public class Q32 {
    interface Greeter { static String hello() { return "hi"; } }
    static class Impl implements Greeter { }
    static String f() { return new Impl().hello(); }
}
```

<details><summary>Answer</summary>

Does **not** compile: `cannot find symbol … method hello() … location: class Impl`. Static interface methods are **not inherited** by implementing classes, so `hello()` isn't a member of `Impl` at all (static methods of *superclasses*, in contrast, are inherited and can be hidden). They must be called as `Greeter.hello()`. Calling one through an expression whose type is the interface itself (`Greeter g = …; g.hello()`) is also an error: `illegal static interface method call`.
</details>

### C33 — Integer caching and `equals`

<!-- run: -->
```java
public class Q33 {
    public static void main(String[] args) {
        Integer a = 100, b = 100, c = 1000, d = 1000;
        Long e = 100L;
        System.out.println((a == b) + " " + (c == d) + " " + c.equals(d) + " " + e.equals(100) + " " + (e == 100));
    }
}
```

<details><summary>Answer</summary>

`true false true false true`. `Integer` cache −128..127. `Long.equals(Integer)` is false (different types). `e == 100` unboxes `e` and compares numerically, giving true.
</details>

### C34 — Sequenced collections

<!-- run: -->
```java
import java.util.*;

public class Q34 {
    public static void main(String[] args) {
        var set = new LinkedHashSet<>(List.of(3, 1, 2));
        set.addFirst(2);
        var map = new LinkedHashMap<String, Integer>(Map.of("k", 1));
        map.putLast("a", 9);
        map.putFirst("z", 0);
        System.out.println(set + " " + set.reversed() + " " + map.firstEntry() + " " + map.sequencedKeySet().reversed());
    }
}
```

<details><summary>Answer</summary>

`[2, 3, 1] [1, 3, 2] z=0 [a, k, z]`. `addFirst` of an existing element moves it to the front. `putFirst`/`putLast` position entries, and the views are reversible.
</details>

### C35 — Scoped values (1Z0-831, JDK 25)

<!-- run: -->
```java
public class Q35 {
    static final ScopedValue<String> USER = ScopedValue.newInstance();

    static String whoAmI() { return USER.isBound() ? USER.get() : "anonymous"; }

    public static void main(String[] args) throws Exception {
        System.out.print(whoAmI() + " ");
        ScopedValue.where(USER, "ann").run(() -> {
            System.out.print(whoAmI() + " ");
            ScopedValue.where(USER, "admin").run(() -> System.out.print(whoAmI() + " "));
            System.out.print(whoAmI() + " ");
        });
        System.out.println(whoAmI() + " " + ScopedValue.where(USER, "bob").call(Q35::whoAmI));
    }
}
```

<details><summary>Answer</summary>

`anonymous ann admin ann anonymous bob`. A scoped value is bound only for the dynamic extent of `run`/`call`. Nested bindings shadow and are restored afterwards, and `isBound()` is false outside any binding. More in Pillar 3, file 06.
</details>

---

## D. Study plan for the Core Java exam domains

| Domain (1Z0-831) | Files | Practise |
|---|---|---|
| Date, time, text, numeric, boolean values | [2.2](02-Strings-Records-Sealed-Pattern-Matching.md), [2.5 §4](05-Generics-Exceptions-Object-Model.md#4-primitives-boxing-and-arithmetic-traps-), [2.6](06-Date-Time-Localization-Numerics.md) | C1–C3, C21, C25–C26, C33 |
| Program flow | [2.2 §5](02-Strings-Records-Sealed-Pattern-Matching.md#5-pattern-matching-) | C4, C5, C24, C29 |
| OOP (records, sealed, nested, interfaces, enums, inheritance) | [2.2](02-Strings-Records-Sealed-Pattern-Matching.md), [2.5 §3](05-Generics-Exceptions-Object-Model.md#3-the-object-model-resolution-rules-the-jvm-and-javac-apply-) | C6–C8, C27–C28, C30, C32 |
| Exceptions | [2.5 §2](05-Generics-Exceptions-Object-Model.md#2-exceptions--internals-costs-and-exam-rules-) | C9–C12 |
| Arrays & collections | [2.1](01-Collections-Internals.md) | C14–C16, C31, C34 |
| Streams & lambdas (incl. gatherers) | [2.3](03-Lambdas-Streams-Collectors-Gatherers.md) | C17–C20 |
| Localization | [2.6 §2](06-Date-Time-Localization-Numerics.md#2-localization-i18n--l10n-) | C22 |
| Modules & packaging | [1.1 §10](../01-JVM-Internals/01-ClassLoading-Linking-JPMS.md#10-the-java-platform-module-system-jpms-internals-), [1.7 §C](../01-JVM-Internals/07-Interview-and-Cert-QA.md) | 1.7 C1–C15 |
| Concurrency, I/O | Pillars 3 and 4 | 3.8, 4.6 |
