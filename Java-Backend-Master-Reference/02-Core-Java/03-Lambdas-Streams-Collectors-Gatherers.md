# 2.3 · Lambdas, Streams, Spliterators, Collectors & Gatherers — Internals and Performance

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("Processing Data Using Streams and Lambda Expressions": reduction, grouping, partitioning **and gatherers** on 1Z0-831)
> **Sources:** JLS §15.27 (lambda expressions), §15.13 (method references); `java.lang.invoke.LambdaMetafactory`; `java.util.stream` package docs ("Non-interference", "Stateless behaviors", "Associativity"); JEP 485 (Stream Gatherers, final in JDK 24); Brian Goetz, "Translation of Lambda Expressions".
> Bytecode excerpts are real `javap` output from JDK 25.

---

## 1. How lambdas are compiled and linked 🔥

### 1.1 Translation (javac)

```java
public class Lam {
    int base = 10;
    static Supplier<String> nonCapturing()        { return () -> "hi"; }
    static IntUnaryOperator capturing(int k)      { return x -> x + k; }
    IntUnaryOperator capturingThis()              { return x -> x + base; }
    static Function<String, Integer> methodRef()  { return String::length; }
}
```

`javap -c -p Lam` (JDK 25):

```
  static java.util.function.Supplier<java.lang.String> nonCapturing();
     0: invokedynamic #13,  0   // InvokeDynamic #0:get:()Ljava/util/function/Supplier;            ← no captured args
  static java.util.function.IntUnaryOperator capturing(int);
     1: invokedynamic #17,  0   // InvokeDynamic #1:applyAsInt:(I)Ljava/util/function/IntUnaryOperator;  ← captures k
  java.util.function.IntUnaryOperator capturingThis();
     1: invokedynamic #21,  0   // InvokeDynamic #2:applyAsInt:(LLam;)…                            ← captures `this`
  static java.util.function.Function<java.lang.String, java.lang.Integer> methodRef();
     0: invokedynamic #24,  0   // InvokeDynamic #3:apply:()Ljava/util/function/Function;
  private static int lambda$capturing$0(int, int);       ← lambda body desugared into a private method
  private static java.lang.String lambda$nonCapturing$0();
  (lambda$capturingThis$0 is a private INSTANCE method, because it reads `base`)

BootstrapMethods:
  0: REF_invokeStatic java/lang/invoke/LambdaMetafactory.metafactory:(…)
       Method arguments: ()Ljava/lang/Object;  REF_invokeStatic Lam.lambda$nonCapturing$0:()Ljava/lang/String;  ()Ljava/lang/String;
  3: REF_invokeStatic java/lang/invoke/LambdaMetafactory.metafactory:(…)
       Method arguments: (Ljava/lang/Object;)Ljava/lang/Object;  REF_invokeVirtual java/lang/String.length:()I  (Ljava/lang/String;)Ljava/lang/Integer;
```

* The **body** becomes a `private` synthetic method (static unless it uses `this`). **Method references** need no synthetic method; the bootstrap points straight at `String.length`.
* The `invokedynamic` call site's **dynamic arguments are the captured values**. Its static bootstrap arguments are the erased interface signature, the implementation method handle, and the instantiated signature.
* No `Lam$1.class` files are produced, unlike anonymous classes.

### 1.2 Linkage (first execution) and identity

On first execution, `LambdaMetafactory` spins a **hidden class** (nestmate of `Lam`, so it may call the private `lambda$…`) implementing the functional interface, and links the call site:

* **Non-capturing** lambda: the call site is bound to a **constant**, so every evaluation returns the **same instance**.
* **Capturing** lambda: each evaluation allocates a new instance holding the captured values. Escape analysis often removes it after inlining.

<!-- run: -->
```java
import java.util.function.IntSupplier;
import java.util.function.Supplier;

public class LambdaIdentity {
    static Supplier<String> make() { return () -> "constant"; }
    static IntSupplier make(int k) { return () -> k; }

    public static void main(String[] args) {
        System.out.println("non-capturing same instance: " + (make() == make()));
        System.out.println("capturing same instance:     " + (make(1) == make(1)));
        Supplier<String> s = make();
        System.out.println("class: " + s.getClass().getName().replaceAll("0x[0-9a-f]+", "0x…")
            + " hidden=" + s.getClass().isHidden() + " synthetic=" + s.getClass().isSynthetic());
        Runnable anon = new Runnable() { public void run() { } };
        System.out.println("anonymous class: " + anon.getClass().getName() + " hidden=" + anon.getClass().isHidden());
    }
}
```

Output (verified):

```
non-capturing same instance: true
capturing same instance:     false
class: LambdaIdentity$$Lambda/0x… hidden=true synthetic=true
anonymous class: LambdaIdentity$1 hidden=false
```

### 1.3 Lambda vs anonymous class — semantic differences 🎓

| | Lambda | Anonymous class |
|---|---|---|
| `this` | The **enclosing** instance | The anonymous instance itself |
| Shadowing local variables | ❌ A lambda parameter or local can't redeclare an enclosing local | ✅ Allowed (new scope) |
| Captured locals | Must be **effectively final** | Must be effectively final |
| Target | Functional interface only (one abstract method) | Any interface or class, multiple methods, state |
| Class file / identity | Hidden class at run time; non-capturing = singleton | One `.class` per declaration; a new instance per evaluation |
| `toString`/serialization | Unstable names; serializable only if the target type is `Serializable` (`altMetafactory` + `$deserializeLambda$`). Avoid | Normal |

**Why must captured locals be effectively final?** Captured *values* are copied into the lambda object (the dynamic arguments above). Allowing mutation would require boxing the variable on the heap and would invite data races once the lambda runs on another thread. Use an `AtomicInteger` or a one-element array to mutate deliberately, or better, restructure into a reduction.

### 1.4 Method reference kinds 🎓

| Kind | Syntax | Equivalent lambda |
|---|---|---|
| Static | `Integer::parseInt` | `s -> Integer.parseInt(s)` |
| Bound instance | `myList::add`, `this::handle`, `System.out::println` | `x -> myList.add(x)` (receiver **evaluated once**, when the reference is created) |
| Unbound instance | `String::length`, `String::compareToIgnoreCase` | `(s) -> s.length()`, `(a, b) -> a.compareToIgnoreCase(b)` |
| Constructor | `ArrayList::new`, `int[]::new` | `() -> new ArrayList<>()`, `n -> new int[n]` |

Trap: `System.out::println` captures the `PrintStream` **at creation**. If `System.setOut` runs later, the reference still prints to the old stream. Bound receivers that are `null` throw an NPE **when the reference is created**, not when it is invoked.

### 1.5 Functional interfaces you must know cold 🎓

| Interface | Method | Primitive specializations (avoid boxing) |
|---|---|---|
| `Supplier<T>` | `T get()` | `IntSupplier`, `LongSupplier`, `DoubleSupplier`, `BooleanSupplier` |
| `Consumer<T>` / `BiConsumer<T,U>` | `void accept(T)` | `IntConsumer`, `ObjIntConsumer<T>`, … |
| `Function<T,R>` / `BiFunction<T,U,R>` | `R apply(T)` | `IntFunction<R>`, `ToIntFunction<T>`, `IntToLongFunction`, `ToIntBiFunction`, … |
| `UnaryOperator<T>` / `BinaryOperator<T>` | `T apply(T)` / `T apply(T,T)` | `IntUnaryOperator`, `IntBinaryOperator`, … |
| `Predicate<T>` / `BiPredicate<T,U>` | `boolean test(T)` | `IntPredicate`, … |

Composition defaults: `Function.andThen/compose/identity`, `Predicate.and/or/negate/not` (static `Predicate.not`, JDK 11), `Comparator.comparing/thenComparing/reversed/nullsFirst`, `BinaryOperator.minBy/maxBy`.

---

## 2. Stream pipeline internals 🔥

### 2.1 Structure: a linked list of stages, executed by a chain of `Sink`s

```
list.stream()          → ReferencePipeline.Head        (source: Spliterator + flags)
    .filter(p)         → StatelessOp                   (flags: NOT_SIZED)
    .map(f)            → StatelessOp
    .sorted()          → StatefulOp                    (barrier: must see ALL elements before emitting)
    .limit(10)         → StatefulOp / short-circuit    (flags: SHORT_CIRCUIT)
    .collect(toList()) → TERMINAL: wrapSink() builds   Sink(filter) → Sink(map) → Sink(sorted) → Sink(limit) → Sink(collector)
                         then spliterator.forEachRemaining(headSink)   (or tryAdvance loop if short-circuiting)
```

* **Laziness:** nothing happens until the terminal operation. Intermediate operations only build stages.
* **Fusion ("vertical" processing):** each element flows through *all* stateless stages before the next element starts, with no intermediate collections. Stateful operations (`sorted`, `distinct`, and `limit`/`skip` in ordered parallel streams) are **barriers** that buffer.
* **Stream flags** (`SIZED`, `ORDERED`, `DISTINCT`, `SORTED`, `SHORT_CIRCUIT`) propagate and enable optimizations. For example, `sorted()` on an already `SORTED` stream is a no-op, `distinct()` on a `DISTINCT` source is skipped, and `count()` on a `SIZED` pipeline **doesn't execute the stages at all** (so side effects in `peek`/`map` don't run, a JDK 9+ behaviour and an exam trap).
* `Sink.cancellationRequested()` lets short-circuit operations (`findFirst`, `anyMatch`, `limit`) stop the source.

<!-- run: -->
```java
import java.util.List;
import java.util.stream.Stream;

public class StreamLaziness {
    public static void main(String[] args) {
        Stream<String> s = Stream.of("a", "bb", "ccc", "dddd")
            .peek(x -> System.out.print("peek(" + x + ") "))
            .filter(x -> { System.out.print("filter(" + x + ") "); return x.length() > 1; })
            .map(x -> { System.out.print("map(" + x + ") "); return x.toUpperCase(); });
        System.out.println("— pipeline built, nothing ran yet");
        System.out.println("\nfindFirst = " + s.findFirst().orElseThrow() + "   ← vertical, short-circuited after 'bb'");

        long n = List.of(1, 2, 3).stream().peek(x -> System.out.print("never printed ")).count();
        System.out.println("count() on SIZED source = " + n + " (peek skipped: count computed from size)");

        Stream<Integer> once = Stream.of(1, 2);
        once.forEach(x -> { });
        try { once.forEach(x -> { }); } catch (IllegalStateException e) { System.out.println("reuse → " + e.getMessage()); }
    }
}
```

Output (verified):

```
— pipeline built, nothing ran yet
peek(a) filter(a) peek(bb) filter(bb) map(bb)
findFirst = BB   ← vertical, short-circuited after 'bb'
count() on SIZED source = 3 (peek skipped: count computed from size)
reuse → stream has already been operated upon or closed
```

### 2.2 `Spliterator` mechanics ⚡

```java
public interface Spliterator<T> {
    boolean tryAdvance(Consumer<? super T> action);     // one element
    default void forEachRemaining(Consumer<? super T> a) // bulk traversal (sources override for speed)
    Spliterator<T> trySplit();                           // hand off a PREFIX to another task, or null
    long estimateSize();
    int characteristics();  // ORDERED DISTINCT SORTED SIZED NONNULL IMMUTABLE CONCURRENT SUBSIZED
}
```

* **Late binding:** the `ArrayList` spliterator binds to the list at first traversal, not at creation. **Fail-fast:** it checks `modCount` after traversal.
* **Split quality decides parallel performance.** Array-backed sources split **exactly in half** (`SIZED|SUBSIZED`). Iterator-based sources (`LinkedList`, `Stream.iterate`, `BufferedReader.lines`, most `Iterable`s) split by **copying batches into arrays** whose size grows arithmetically (1024, 2048, …). That gives poor balance and extra copying.

<!-- run: -->
```java
import java.util.*;
import java.util.stream.IntStream;
import java.util.stream.Stream;

public class SpliteratorAnatomy {
    static String flags(int c) {
        StringJoiner j = new StringJoiner("|");
        Map<Integer, String> names = new LinkedHashMap<>();
        names.put(Spliterator.ORDERED, "ORDERED"); names.put(Spliterator.DISTINCT, "DISTINCT");
        names.put(Spliterator.SORTED, "SORTED"); names.put(Spliterator.SIZED, "SIZED");
        names.put(Spliterator.NONNULL, "NONNULL"); names.put(Spliterator.IMMUTABLE, "IMMUTABLE");
        names.put(Spliterator.CONCURRENT, "CONCURRENT"); names.put(Spliterator.SUBSIZED, "SUBSIZED");
        names.forEach((bit, name) -> { if ((c & bit) != 0) j.add(name); });
        return j.toString();
    }

    static String splits(Spliterator<?> s, int depth) {           // recursive halving, report leaf sizes
        if (depth == 0) return String.valueOf(s.estimateSize() == Long.MAX_VALUE ? "?" : s.estimateSize());
        Spliterator<?> prefix = s.trySplit();
        if (prefix == null) return "[" + splits(s, 0) + " unsplittable]";
        return "(" + splits(prefix, depth - 1) + " " + splits(s, depth - 1) + ")";
    }

    public static void main(String[] args) {
        List<Integer> array = new ArrayList<>(IntStream.range(0, 10_000).boxed().toList());
        List<Integer> linked = new LinkedList<>(array);
        Map<String, Spliterator<?>> sources = new LinkedHashMap<>();
        sources.put("ArrayList", array.spliterator());
        sources.put("LinkedList", linked.spliterator());
        sources.put("HashSet", new HashSet<>(array).spliterator());
        sources.put("TreeSet", new TreeSet<>(array).spliterator());
        sources.put("IntStream.range", IntStream.range(0, 10_000).spliterator());
        sources.put("Stream.iterate+limit", Stream.iterate(0, i -> i + 1).limit(10_000).spliterator());
        sources.forEach((name, sp) -> System.out.printf("%-21s %-58s%n", name, flags(sp.characteristics())));

        System.out.println("ArrayList split x3  : " + splits(array.spliterator(), 3));
        System.out.println("LinkedList split x3 : " + splits(linked.spliterator(), 3));
        System.out.println("iterate split x3    : " + splits(Stream.iterate(0, i -> i + 1).limit(10_000).spliterator(), 3));
    }
}
```

Output (verified):

```
ArrayList             ORDERED|SIZED|SUBSIZED
LinkedList            ORDERED|SIZED|SUBSIZED
HashSet               DISTINCT|SIZED
TreeSet               ORDERED|DISTINCT|SORTED|SIZED
IntStream.range       ORDERED|DISTINCT|SORTED|SIZED|NONNULL|IMMUTABLE|SUBSIZED
Stream.iterate+limit  ORDERED
ArrayList split x3  : (((1250 1250) (1250 1250)) ((1250 1250) (1250 1250)))
LinkedList split x3 : (((256 256) (256 256)) ((1024 1024) (3072 3856)))
iterate split x3    : [? unsplittable]
```

* `ArrayList` splits into eight perfect 1,250-element leaves.
* `LinkedList`'s first split **walks and copies a 1,024-element batch into an array**, which then splits evenly (512 → 256s). The remainder hands out ever-larger batches (1,024, 2,048, 3,072, …), leaving a lopsided 3,856-element leaf.
* The `Stream.iterate(…).limit(…)` spliterator is **unsized and refused to split at all** (`trySplit()` returned `null`), so in a parallel pipeline the stream framework has to buffer elements itself to create any parallelism.

With few cores that's tolerable. With many cores, most workers idle.

### 2.3 Writing a custom `Spliterator` (fixed-size chunks)

<!-- run: -->
```java
import java.util.*;
import java.util.function.Consumer;
import java.util.stream.Stream;
import java.util.stream.StreamSupport;

public class ChunkingSpliterator<T> implements Spliterator<List<T>> {
    private final List<T> source; private int from; private final int to; private final int chunk;

    ChunkingSpliterator(List<T> source, int from, int to, int chunk) { this.source = source; this.from = from; this.to = to; this.chunk = chunk; }

    public static <T> Stream<List<T>> chunks(List<T> list, int size, boolean parallel) {
        return StreamSupport.stream(new ChunkingSpliterator<>(list, 0, list.size(), size), parallel);
    }

    @Override public boolean tryAdvance(Consumer<? super List<T>> action) {
        if (from >= to) return false;
        int end = Math.min(from + chunk, to);
        action.accept(List.copyOf(source.subList(from, end)));
        from = end;
        return true;
    }

    @Override public Spliterator<List<T>> trySplit() {                      // split on chunk boundaries
        int remainingChunks = (to - from + chunk - 1) / chunk;
        if (remainingChunks < 2) return null;
        int mid = from + (remainingChunks / 2) * chunk;
        var prefix = new ChunkingSpliterator<>(source, from, mid, chunk);
        from = mid;
        return prefix;
    }

    @Override public long estimateSize() { return (to - from + chunk - 1) / chunk; }
    @Override public int characteristics() { return ORDERED | SIZED | SUBSIZED | NONNULL | IMMUTABLE; }

    public static void main(String[] args) {
        List<Integer> ids = java.util.stream.IntStream.rangeClosed(1, 10).boxed().toList();
        System.out.println(chunks(ids, 4, false).toList());
        System.out.println("parallel sums per chunk (order kept): " + chunks(ids, 3, true).map(c -> c.stream().mapToInt(i -> i).sum()).toList());
    }
}
```

Output (verified):

```
[[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]]
parallel sums per chunk (order kept): [6, 15, 24, 10]
```

(For streams, JDK 24 offers `Gatherers.windowFixed(n)`. The spliterator approach still matters for **custom sources**: files, cursors, paginated APIs.)

---

## 3. Parallel streams: when they help and when they hurt 🔥

**Mechanics:** a parallel terminal operation creates `AbstractTask`s (Fork/Join `CountedCompleter`s) that recursively `trySplit` the source until leaves are around `estimatedSize / (4 × parallelism)`, then run the sink chain on each leaf, then **combine** the results. Everything runs on **`ForkJoinPool.commonPool()`** (parallelism = `availableProcessors() − 1`, plus the calling thread). That pool is **shared with every other parallel stream and every `CompletableFuture.*Async` without an executor** in the JVM.

### 3.1 Runnable: measured degradation scenarios

<!-- run: timeout=120 -->
```java
import java.util.*;
import java.util.concurrent.*;
import java.util.function.LongSupplier;
import java.util.stream.*;

public class ParallelPitfalls {
    static String best(LongSupplier work) {
        long best = Long.MAX_VALUE, r = 0;
        for (int i = 0; i < 7; i++) { long t = System.nanoTime(); r += work.getAsLong(); best = Math.min(best, System.nanoTime() - t); }
        return String.format("%8.3f ms", best / 1e6) + (r == 42 ? "!" : "");
    }

    public static void main(String[] args) throws Exception {
        System.out.println("commonPool parallelism = " + ForkJoinPool.getCommonPoolParallelism());
        System.out.println("1. tiny N (10k ints)        seq " + best(() -> IntStream.range(0, 10_000).sum())
            + " | par " + best(() -> IntStream.range(0, 10_000).parallel().sum()));
        System.out.println("2. big N (50M ints)         seq " + best(() -> LongStream.range(0, 50_000_000).map(x -> x * x % 7).sum())
            + " | par " + best(() -> LongStream.range(0, 50_000_000).parallel().map(x -> x * x % 7).sum()));

        List<Integer> array = new ArrayList<>(IntStream.range(0, 2_000_000).boxed().toList());
        List<Integer> linked = new LinkedList<>(array);
        System.out.println("3. ArrayList 2M boxed par   " + best(() -> array.parallelStream().mapToLong(i -> i).sum())
            + " | LinkedList par " + best(() -> linked.parallelStream().mapToLong(i -> i).sum()));
        System.out.println("4. iterate+limit 2M par     " + best(() -> Stream.iterate(0L, i -> i + 1).limit(2_000_000).parallel().mapToLong(i -> i).sum())
            + " | range par " + best(() -> LongStream.range(0, 2_000_000).parallel().sum()));
        System.out.println("5. ordered limit, par       " + best(() -> IntStream.range(0, 20_000_000).parallel().filter(i -> i % 3 == 0).limit(100_000).asLongStream().sum())
            + " | unordered() " + best(() -> IntStream.range(0, 20_000_000).parallel().unordered().filter(i -> i % 3 == 0).limit(100_000).asLongStream().sum()));

        // 6. Blocking work inside a parallel stream starves EVERY other commonPool user
        ExecutorService bg = Executors.newSingleThreadExecutor();
        Future<?> blocker = bg.submit(() -> IntStream.range(0, 64).parallel().forEach(i -> sleep(200)));   // "remote calls"
        Thread.sleep(50);
        long t0 = System.nanoTime();
        CompletableFuture.supplyAsync(() -> "quick task").join();                                           // default executor = commonPool
        System.out.printf("6. unrelated supplyAsync waited %.0f ms behind blocking parallel stream%n", (System.nanoTime() - t0) / 1e6);
        blocker.get(); bg.shutdown();
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { throw new RuntimeException(e); } }
}
```

One measured run (12 logical CPUs, JDK 25, best of 7 per cell):

```
commonPool parallelism = 11
1. tiny N (10k ints)        seq    0.283 ms | par    0.556 ms
2. big N (50M ints)         seq   54.604 ms | par   11.195 ms
3. ArrayList 2M boxed par      1.063 ms | LinkedList par    8.441 ms
4. iterate+limit 2M par       17.110 ms | range par    0.109 ms
5. ordered limit, par          5.118 ms | unordered()    2.139 ms
6. unrelated supplyAsync waited 367 ms behind blocking parallel stream
```

### 3.2 The rules distilled

| Parallel streams **help** when | They **hurt** when |
|---|---|
| N × Q is large (Doug Lea's rule of thumb: N × cost-per-element > ~10,000 "basic operations"). Scenario 2: 4.9× faster on 11 workers | N is small: fork/join overhead dominates (scenario 1: **~2× slower** than sequential) |
| The source splits well: arrays, `ArrayList`, `IntStream.range`, `HashMap`/`ConcurrentHashMap` keySets | Iterator-backed sources: `LinkedList` (8× slower than `ArrayList`), `Stream.iterate`, `BufferedReader.lines()`, I/O streams (scenario 4: ~157× slower than `range`) |
| Operations are stateless, non-interfering, CPU-bound | Ordered stateful operations: `limit`/`skip`/`sorted`/`distinct` on `ORDERED` streams (scenario 5: 2.4× slower than `unordered()`) |
| Primitive streams (no boxing) | Boxing-heavy pipelines (memory-bandwidth bound, not CPU bound) |
| Cheap combine (sum, min, `toList`) | Expensive combine: merging big `HashMap`s in `groupingBy` (use `groupingByConcurrent`), string concatenation |
| The machine has idle cores | Already-saturated servers: a web request using `parallelStream()` competes with all other requests for the shared commonPool |
| Pure CPU work | **Blocking I/O in the pipeline**: starves the commonPool for the whole JVM (scenario 6: an unrelated `supplyAsync` waited 367 ms) |
| `findAny`, `unordered()` | `findFirst`, `forEachOrdered` on large ordered data |

**Production guidance:** in request-serving code, **default to sequential streams**. Use parallelism explicitly via executors or virtual threads for I/O-bound fan-out (`Gatherers.mapConcurrent`, `StructuredTaskScope`), and reserve parallel streams for batch/CPU-heavy jobs on dedicated pools or processes. The often-quoted trick `customPool.submit(() -> list.parallelStream()…).get()` relies on an implementation detail (tasks fork into the *current* FJP) and is not a supported API.

---

## 4. Reduction and collectors 🔥🎓

### 4.1 `reduce` contracts

* `reduce(identity, accumulator)` requires `accumulator(identity, x) == x` and **associativity**. Otherwise parallel results differ from sequential ones. `reduce(0, (a, b) -> a - b)` is wrong in parallel.
* The 3-arg `reduce(identity, accumulator, combiner)` is for changing type, but `collect` is usually clearer and avoids copying.
* `reduce` is for **immutable** reduction. **Mutable** reduction (into a collection or builder) belongs to `collect`.

### 4.2 `Collector<T, A, R>` anatomy

```
supplier()       () -> A              new mutable container per leaf task
accumulator()    (A, T) -> void        fold one element in
combiner()       (A, A) -> A           merge two partial containers (parallel)
finisher()       A -> R                final transform (skipped if IDENTITY_FINISH)
characteristics  IDENTITY_FINISH | UNORDERED | CONCURRENT (one shared container, accumulator must be thread-safe)
```

### 4.3 Collectors in practice, including the traps

<!-- run: -->
```java
import java.util.*;
import java.util.stream.*;
import static java.util.stream.Collectors.*;

public class CollectorsTour {
    record Order(String customer, String region, double amount, boolean paid) {}

    public static void main(String[] args) {
        List<Order> orders = List.of(
            new Order("ann", "EU", 120, true), new Order("bob", "US", 80, false),
            new Order("ann", "EU", 30, true), new Order("cat", "US", 200, true), new Order("dan", "APAC", 50, false));

        Map<String, Double> revenueByRegion = orders.stream()
            .collect(groupingBy(Order::region, TreeMap::new, summingDouble(Order::amount)));
        Map<Boolean, List<String>> paidSplit = orders.stream()
            .collect(partitioningBy(Order::paid, mapping(Order::customer, toList())));
        Map<String, Long> countByCustomer = orders.stream().collect(groupingBy(Order::customer, LinkedHashMap::new, counting()));
        var stats = orders.stream().collect(summarizingDouble(Order::amount));
        String csv = orders.stream().map(Order::customer).distinct().sorted().collect(joining(",", "[", "]"));
        var minMax = orders.stream().collect(teeing(minBy(Comparator.comparingDouble(Order::amount)),
            maxBy(Comparator.comparingDouble(Order::amount)), (min, max) -> min.orElseThrow().amount() + ".." + max.orElseThrow().amount()));
        Map<String, Optional<Order>> biggestPerRegion = orders.stream()
            .collect(groupingBy(Order::region, maxBy(Comparator.comparingDouble(Order::amount))));

        System.out.println(revenueByRegion);
        System.out.println(paidSplit);
        System.out.println(countByCustomer + " " + csv + " " + minMax);
        System.out.printf("avg=%.1f max=%.0f n=%d%n", stats.getAverage(), stats.getMax(), stats.getCount());
        System.out.println("biggest US: " + biggestPerRegion.get("US").map(Order::customer).orElse("-"));
        System.out.println("partitioningBy always has both keys: " + Stream.of(1, 3).collect(partitioningBy(i -> i % 2 == 0)));

        try { orders.stream().collect(toMap(Order::customer, Order::amount)); }
        catch (IllegalStateException e) { System.out.println("toMap duplicate key → " + e.getMessage()); }
        System.out.println("toMap with merge → " + orders.stream().collect(toMap(Order::customer, Order::amount, Double::sum, TreeMap::new)));
        try { Stream.of("k").collect(toMap(k -> k, k -> (String) null)); }
        catch (NullPointerException e) { System.out.println("toMap null value → NullPointerException (HashMap.merge rejects null)"); }
    }
}
```

Output (verified):

```
{APAC=50.0, EU=150.0, US=280.0}
{false=[bob, dan], true=[ann, ann, cat]}
{ann=2, bob=1, cat=1, dan=1} [ann,bob,cat,dan] 30.0..200.0
avg=96.0 max=200 n=5
biggest US: cat
partitioningBy always has both keys: {false=[1, 3], true=[]}
toMap duplicate key → Duplicate key ann (attempted merging values 120.0 and 30.0)
toMap with merge → {ann=150.0, bob=80.0, cat=200.0, dan=50.0}
toMap null value → NullPointerException (HashMap.merge rejects null)
```

### 4.4 A custom collector: top-K with a bounded heap (O(n log k))

<!-- run: -->
```java
import java.util.*;
import java.util.stream.Collector;
import java.util.stream.IntStream;

public class TopK {
    public static <T> Collector<T, ?, List<T>> topK(int k, Comparator<? super T> cmp) {
        return Collector.of(
            () -> new PriorityQueue<T>(k + 1, cmp),                          // min-heap of the best k
            (heap, t) -> { heap.offer(t); if (heap.size() > k) heap.poll(); },
            (h1, h2) -> { for (T t : h2) { h1.offer(t); if (h1.size() > k) h1.poll(); } return h1; },
            heap -> { List<T> out = new ArrayList<>(heap); out.sort(cmp.reversed()); return out; });
    }

    public static void main(String[] args) {
        var random = new Random(7);
        List<Integer> latencies = IntStream.range(0, 1_000_000).map(i -> random.nextInt(10_000)).boxed().toList();
        List<Integer> seq = latencies.stream().collect(topK(5, Comparator.naturalOrder()));
        List<Integer> par = latencies.parallelStream().collect(topK(5, Comparator.naturalOrder()));
        System.out.println("top-5 sequential " + seq + " == parallel " + par + " : " + seq.equals(par));
    }
}
```

Output (verified): `top-5 sequential [9999, 9999, 9999, 9999, 9999] == parallel [9999, 9999, 9999, 9999, 9999] : true`

---

## 5. Stream Gatherers (JDK 24 final, JEP 485) 🔥🎓

`Stream.gather(Gatherer)` is to intermediate operations what `collect(Collector)` is to terminal ones: a user-defined, possibly **stateful**, possibly **short-circuiting**, one-to-many or many-to-one transformation that still fuses into the pipeline.

```
Gatherer<T, A, R>
  initializer()  () -> A                         per-stream (or per-split) private state; default = stateless
  integrator()   (A state, T element, Downstream<? super R> down) -> boolean   push 0..n results;
                                                 return false to SHORT-CIRCUIT (stop upstream)
  combiner()     (A, A) -> A                     enables parallel evaluation (absent → sequential)
  finisher()     (A, Downstream<? super R>) -> void   flush buffered state at end
```

### 5.1 Built-ins (`java.util.stream.Gatherers`)

| Gatherer | Behaviour |
|---|---|
| `windowFixed(n)` | `[1..7]` with n=3 → `[1,2,3] [4,5,6] [7]` |
| `windowSliding(n)` | n=3 → `[1,2,3] [2,3,4] …` |
| `fold(init, folder)` | Many-to-one, emitted at the end (ordered fold, no combiner needed) |
| `scan(init, scanner)` | Running accumulation (prefix sums) |
| `mapConcurrent(maxConcurrency, fn)` | Runs `fn` on **virtual threads**, at most N at a time, **preserving encounter order**: bounded I/O fan-out inside a stream |

### 5.2 Runnable: built-ins plus two custom gatherers

<!-- run: -->
```java
import java.util.*;
import java.util.function.Function;
import java.util.stream.Gatherer;
import java.util.stream.Gatherers;
import java.util.stream.Stream;

public class GatherersTour {
    /** Emits the first element for each distinct key (stateful, sequential). */
    static <T, K> Gatherer<T, ?, T> distinctBy(Function<? super T, ? extends K> key) {
        return Gatherer.ofSequential(
            HashSet<K>::new,
            Gatherer.Integrator.ofGreedy((seen, element, down) -> {
                if (seen.add(key.apply(element))) return down.push(element);
                return true;
            }));
    }

    /** Groups consecutive elements into batches whose total weight stays <= max; flushes the tail in the finisher. */
    static <T> Gatherer<T, ?, List<T>> batchByWeight(long max, Function<T, Long> weight) {
        class State { List<T> batch = new ArrayList<>(); long total; }
        return Gatherer.ofSequential(
            State::new,
            Gatherer.Integrator.ofGreedy((s, element, down) -> {
                long w = weight.apply(element);
                if (!s.batch.isEmpty() && s.total + w > max) {
                    if (!down.push(List.copyOf(s.batch))) return false;
                    s.batch.clear(); s.total = 0;
                }
                s.batch.add(element); s.total += w;
                return true;
            }),
            (s, down) -> { if (!s.batch.isEmpty()) down.push(List.copyOf(s.batch)); });
    }

    record Event(String user, int sizeKb) {}

    public static void main(String[] args) {
        System.out.println(Stream.of(1, 2, 3, 4, 5, 6, 7).gather(Gatherers.windowFixed(3)).toList());
        System.out.println(Stream.of(1, 2, 3, 4).gather(Gatherers.windowSliding(2)).toList());
        System.out.println(Stream.of(1, 2, 3, 4).gather(Gatherers.scan(() -> 0, Integer::sum)).toList());
        System.out.println(Stream.of("a", "b", "c").gather(Gatherers.fold(() -> "", String::concat)).toList());

        var events = List.of(new Event("ann", 40), new Event("bob", 70), new Event("ann", 10), new Event("cat", 30), new Event("dan", 90));
        System.out.println(events.stream().gather(distinctBy(Event::user)).map(Event::user).toList());
        System.out.println(events.stream().gather(batchByWeight(100, e -> (long) e.sizeKb()))
            .map(b -> b.stream().map(Event::user).toList()).toList());
        System.out.println("short-circuit: " + Stream.iterate(1, i -> i + 1)            // infinite source
            .gather(batchByWeight(10, i -> (long) i)).limit(3).toList());

        long t0 = System.nanoTime();
        List<String> results = Stream.of("u1", "u2", "u3", "u4", "u5", "u6", "u7", "u8")
            .gather(Gatherers.mapConcurrent(4, id -> { sleep(100); return id.toUpperCase(); }))   // virtual threads
            .toList();
        System.out.printf("mapConcurrent(4) of 8×100ms calls: %s in ~%d ms (order preserved)%n", results, (System.nanoTime() - t0) / 1_000_000 / 100 * 100);
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { throw new RuntimeException(e); } }
}
```

Output (verified):

```
[[1, 2, 3], [4, 5, 6], [7]]
[[1, 2], [2, 3], [3, 4]]
[1, 3, 6, 10]
[abc]
[ann, bob, cat, dan]
[[ann], [bob, ann], [cat], [dan]]
short-circuit: [[1, 2, 3, 4], [5], [6]]
mapConcurrent(4) of 8×100ms calls: [U1, U2, U3, U4, U5, U6, U7, U8] in ~200 ms (order preserved)
```

* `ofGreedy` tells the stream that the integrator never short-circuits on its own, which allows optimizations. Return `down.push(...)`'s result to propagate downstream short-circuits, as `limit(3)` does on the infinite source above.
* Gatherers compose: `g1.andThen(g2)`. A gatherer **without a combiner** forces sequential evaluation of that stage even in a parallel stream.
* **`mapConcurrent` is the idiomatic bounded-I/O fan-out in streams on JDK 24+.** Prefer it over `parallelStream()` for remote calls.

---

## 6. `Optional` and other API traps 🔥🎓

<!-- run: -->
```java
import java.util.*;
import java.util.stream.*;

public class StreamTraps {
    static String expensiveDefault() { System.out.print("[expensiveDefault ran] "); return "default"; }

    public static void main(String[] args) {
        Optional<String> present = Optional.of("value");
        System.out.println(present.orElse(expensiveDefault()) + "  ← orElse evaluates its argument eagerly");
        System.out.println(present.orElseGet(StreamTraps::expensiveDefault) + "  ← orElseGet is lazy");
        try { Optional.of(null); } catch (NullPointerException e) { System.out.println("Optional.of(null) → NPE; use ofNullable"); }
        System.out.println("map to null → " + Optional.of("x").map(x -> null) + " (empty, not NPE)");

        System.out.println(IntStream.rangeClosed(1, 5).average() + " " + IntStream.empty().max() + " " + Stream.of(3, 1, 2).max(Integer::compare).get());
        System.out.println(Stream.of("a", "b", "c").reduce("", String::concat) + " " + Stream.of(1, 2, 3, 4).reduce(Integer::sum).get());
        System.out.println(Stream.of(List.of(1, 2), List.of(3)).flatMap(List::stream).map(i -> i * 10).toList()
            + " " + Stream.of("a-b", "c").mapMulti((String s, java.util.function.Consumer<String> sink) -> { for (String p : s.split("-")) sink.accept(p); }).toList());
        System.out.println(Stream.iterate(1, i -> i <= 20, i -> i * 3).toList() + " " + Stream.of(5, 6, 7, 1, 8).takeWhile(i -> i > 4).toList()
            + " " + Stream.of(5, 6, 7, 1, 8).dropWhile(i -> i > 4).toList());
        var sorted = Stream.of("pear", "Fig", "apple", "kiwi")
            .sorted(Comparator.comparing(String::length).thenComparing(String.CASE_INSENSITIVE_ORDER)).toList();
        System.out.println(sorted);
    }
}
```

Output (verified):

```
[expensiveDefault ran] value  ← orElse evaluates its argument eagerly
value  ← orElseGet is lazy
Optional.of(null) → NPE; use ofNullable
map to null → Optional.empty (empty, not NPE)
OptionalDouble[3.0] OptionalInt.empty 3
abc 10
[10, 20, 30] [a, b, c]
[1, 3, 9] [5, 6, 7] [1, 8]
[Fig, kiwi, pear, apple]
```

**`Optional` guidance:** use it as a **return type** for "maybe absent" results. Don't use it for fields, parameters, collections (return empty collections) or in hot loops (it allocates). Never call `get()` without checking; prefer `orElseThrow()`, `map`, `orElseGet`.

---

## 7. Performance notes: streams vs loops ⚡

* For simple loops over arrays, a hand-written loop and an `IntStream` compile to similar code once C2 has inlined the pipeline, which requires the pipeline's call sites to be monomorphic.
* **Profile pollution** (see [1.5 §2.2](../01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md#22-profile-pollution--why-the-same-code-is-slower-in-production-)): `ReferencePipeline` internals are shared by every stream in the JVM. In large applications, stream stages become megamorphic and stop inlining, which typically makes streams 1.5–5× slower than loops in hot paths. Use loops in the top few hottest methods (profile first), and streams for clarity everywhere else.
* Boxing: `Stream<Integer>` allocates (often EA-eliminated only in simple cases). Use `mapToInt`/`IntStream`.
* Lambdas capturing state allocate per evaluation. Hoist non-capturing lambdas, or rely on EA.

---

## 8. Production failure modes & diagnostics

| Failure | Signature | Fix |
|---|---|---|
| `parallelStream()` in request handlers | CPU saturation, latency spikes, commonPool threads in all dumps | Sequential by default; dedicated executors |
| Blocking calls in a parallel stream | `ForkJoinPool.commonPool-worker-*` threads in `TIMED_WAITING`/socket reads; unrelated `CompletableFuture`s slow | `Gatherers.mapConcurrent`, virtual-thread executors |
| `IllegalStateException: Duplicate key` | `toMap` without a merge function on non-unique keys | Add a merge function, or use `groupingBy` |
| NPE inside `Collectors.toMap` | Null values | Filter nulls, or collect via `groupingBy`/a custom collector |
| Parallel results differ from sequential | Non-associative reduce, shared mutable state in lambdas (`list.add` from `forEach`) | Associative ops; `collect`; no side effects |
| Stream not closed → file handle leak | `Files.lines`/`Files.list`/`Files.walk` without try-with-resources | `try (Stream<String> s = Files.lines(p)) { … }` |
| Stream "does nothing" | No terminal op (common with `peek` debugging) | Add a terminal op |
| Slow stream-heavy hot path | Megamorphic pipeline in flame graphs (`ReferencePipeline$…`, `Sink$ChainedReference`) | Loop rewrite in the hot path |

---

## 9. Interview & certification Q&A

<details><summary><b>Q1. 🔥 How are lambdas implemented? Why not anonymous inner classes?</b></summary>

javac desugars the body into a private (static, if it doesn't use `this`) synthetic method and emits an `invokedynamic` whose bootstrap is `LambdaMetafactory.metafactory`, passing the functional interface signature and a method handle to the body. On first execution the metafactory spins a hidden class implementing the interface and links the call site. Non-capturing lambdas link to a constant singleton; capturing ones allocate per evaluation. This defers the strategy to run time (the JDK can improve it without recompiling code), avoids one class file per lambda, reduces startup and footprint costs, and lets hidden classes be unloaded independently.
</details>

<details><summary><b>Q2. 🎓 What is printed? <code>Stream.of("a","b").peek(System.out::print).count();</code> (JDK 9+)</b></summary>

Nothing. `count()` on a `SIZED` stream with no size-changing stages is computed directly from the source size, and the pipeline (including `peek`) is not executed. Adding a `filter` makes `peek` run.
</details>

<details><summary><b>Q3. 🔥 List five scenarios where `parallelStream()` makes things slower.</b></summary>

Small N (fork/join overhead), iterator-based sources that split poorly (`LinkedList`, `Stream.iterate`, `lines()`), ordered stateful operations (`limit`, `sorted`, `distinct`, `findFirst`), boxing- or memory-bound work, expensive combiners (big map merges), blocking I/O (commonPool starvation), and running on an already-saturated server. Measured: ~2× slower for 10k ints, ~157× slower with `iterate` vs `range`, 8× slower with `LinkedList` vs `ArrayList`.
</details>

<details><summary><b>Q4. ⚡ Explain the `Collector` contract and the CONCURRENT and UNORDERED characteristics.</b></summary>

`supplier` creates a container, `accumulator` folds an element in, `combiner` merges two containers (parallel), and `finisher` converts to the result (skipped with `IDENTITY_FINISH`). `CONCURRENT` means one container may be accumulated into from multiple threads at once (the container must be thread-safe, like `ConcurrentHashMap` in `groupingByConcurrent`). It only applies if the stream is unordered or the collector is `UNORDERED`. `UNORDERED` means the result doesn't depend on encounter order, which enables more efficient parallel execution.
</details>

<details><summary><b>Q5. 🎓 What do `partitioningBy` and `groupingBy` return for no matches?</b></summary>

`partitioningBy` always returns a map with **both** `true` and `false` keys (empty lists if none match). `groupingBy` only contains keys that occurred.
</details>

<details><summary><b>Q6. 🔥 What are stream gatherers and when would you write one?</b></summary>

Gatherers (JDK 24) are custom intermediate operations with optional private state, a finisher and short-circuiting, fused into the pipeline. Write one when the built-in `map`/`filter`/`flatMap` can't express the logic without breaking the stream: windowing, batching by weight, deduplication by key, rate-aware transforms, sessionization, or bounded concurrent mapping. Built-ins: `windowFixed`, `windowSliding`, `fold`, `scan`, `mapConcurrent` (virtual threads, bounded, order-preserving).
</details>

<details><summary><b>Q7. 🎓 Why must lambda-captured locals be effectively final?</b></summary>

Lambdas capture the **value** of local variables, copied into the lambda instance. Mutation after capture would make the copy and the variable diverge, and would introduce races if the lambda runs on another thread. Fields aren't subject to this rule, because the lambda captures `this` and reads the field through it.
</details>

<details><summary><b>Q8. ⚡ `Optional.orElse(compute())` vs `orElseGet(this::compute)`?</b></summary>

`orElse` evaluates its argument **before** the call, even when the Optional is present, wasting work or causing side effects. `orElseGet` takes a `Supplier` and evaluates it only when the Optional is empty.
</details>

<details><summary><b>Q9. 🧊 Why can `LinkedList.parallelStream()` be much slower than `ArrayList.parallelStream()`?</b></summary>

`LinkedList`'s spliterator can't split in O(1). It traverses nodes and copies batches (1024, 2048, …) into arrays to hand off, which leaves unbalanced work and serial traversal costs. Pointer-chasing nodes also defeats prefetching. `ArrayList` splits by index arithmetic into equal halves.
</details>

<details><summary><b>Q10. 🎓 Which compiles? (a) <code>Runnable r = () -&gt; { return; };</code> (b) <code>Supplier&lt;Integer&gt; s = () -&gt; { 42; };</code> (c) <code>Function&lt;String,Integer&gt; f = String::length;</code> (d) <code>BiFunction&lt;String,String,Boolean&gt; b = String::equalsIgnoreCase;</code> (e) <code>int x = 1; Runnable r2 = () -&gt; x++;</code></b></summary>

(a), (c) and (d) compile. (b) fails because a block body needs `return 42;`. (e) fails because `x` is not effectively final. (d) is an unbound method reference: the first argument becomes the receiver.
</details>

---

## 10. Further reading

* Brian Goetz, "Translation of Lambda Expressions": <https://cr.openjdk.org/~briangoetz/lambda/lambda-translation.html>
* `java.util.stream` package summary (non-interference, statelessness, associativity, side effects).
* JEP 485 Stream Gatherers: <https://openjdk.org/jeps/485>
* Doug Lea, "When to use parallel streams": <https://gee.cs.oswego.edu/dl/html/StreamParallelGuidance.html>
