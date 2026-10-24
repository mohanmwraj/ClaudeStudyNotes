# 2.5 · Generics, Exceptions & the Object Model — Internals Behind the Exam Traps

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam (OOP is the largest 1Z0-830/831 domain, at roughly 18%; exceptions ~8%)
> **Sources:** JLS SE 25 §4.6 (type erasure), §4.10.2, §5.1.10 (capture conversion), §8.4.8 (overriding/hiding), §15.12.2 (overload resolution phases), §11 (exceptions), §14.20.3 (try-with-resources), §5.6 (numeric promotion); *Effective Java* 3rd ed. items 26–33 (generics) and 69–77 (exceptions); JEP 358 (helpful NPEs).
> This file skips introductory syntax. It explains **why** the rules exist (what the compiler and JVM actually do), which is how you answer trick questions quickly and debug production oddities.

---

## 1. Generics are a compile-time fiction: erasure 🔥🎓

### 1.1 What the compiler emits

* Type parameters are **erased** to their leftmost bound (`T` → `Object`, `T extends Comparable<T>` → `Comparable`). Casts are inserted at use sites.
* Generic signatures survive in the class file's `Signature` attribute, readable by reflection (`getGenericSuperclass`, `getGenericReturnType`) but ignored by the JVM's type checks.
* **Bridge methods** preserve polymorphism after erasure. Real `javap` output for `class ByLength implements Comparator<String>`:

```
  public int compare(java.lang.String, java.lang.String);          ← what you wrote
  public int compare(java.lang.Object, java.lang.Object);          ← javac-generated bridge
         2: checkcast     #8   // class java/lang/String
         6: checkcast     #8   // class java/lang/String
         9: invokevirtual #19  // Method compare:(Ljava/lang/String;Ljava/lang/String;)I
    descriptor: (Ljava/lang/Object;Ljava/lang/Object;)I
    flags: (0x1041) ACC_PUBLIC, ACC_BRIDGE, ACC_SYNTHETIC
```

`Comparator.compare(Object, Object)` callers hit the bridge, which casts and delegates. **Consequence:** a raw or heap-polluted `Comparator` fed an `Integer` throws `ClassCastException` *inside the bridge*. Stack traces show a `compare` frame at a line number you didn't write.

### 1.2 Consequences of erasure (exam favourites)

| You can't… | Because | Workaround |
|---|---|---|
| `new T()` / `new T[n]` | `T` is unknown at run time | Pass `Class<T>`, `Supplier<T>`, or `IntFunction<T[]>` (`list.toArray(String[]::new)`) |
| `obj instanceof List<String>` (when `obj` is `Object`) | Can't be checked at run time | `instanceof List<?>`, then check the elements |
| Overload `m(List<String>)` and `m(List<Integer>)` | Same erasure: `m(List)` → **name clash** | Different names |
| Declare `static T field` in `class Box<T>` | Statics are shared across all parameterizations | Generic static *methods* `<U> U of(...)` |
| `catch (T e)` / generic `Throwable` subclasses | Exception handlers are matched by run-time class | — |
| Create `List<String>[]` | Arrays are reified and covariant; generic arrays would be unsound | `List<List<String>>` |
| Primitives as type arguments | Erasure to `Object` | Boxing, or primitive specializations (`IntStream`). Valhalla aims to fix this eventually |

<!-- run: compilefail expect="name clash" -->
```java
import java.util.List;

public class ErasureClash {
    void process(List<String> names) { }
    void process(List<Integer> ids) { }        // error: name clash: both methods have same erasure
}
```

<!-- run: compilefail expect="cannot be safely cast" -->
```java
import java.util.List;

public class ReifiableCheck {
    static boolean f(Object o) {
        return o instanceof List<String>;      // error: Object cannot be safely cast to List<String>
    }
}
```

### 1.3 Heap pollution: the ClassCastException that happens far away 🔥

<!-- run: -->
```java
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.util.*;

public class HeapPollution {
    @SuppressWarnings({"unchecked", "rawtypes"})
    static void legacyLibrary(List list) { list.add(42); }          // raw type: the compiler can't protect you

    @SafeVarargs                                                    // a PROMISE that we don't store into the array
    static <T> List<T> listOf(T... items) { return new ArrayList<>(Arrays.asList(items)); }

    static <T> T[] unsafeToArray(T... items) { return items; }     // returns the varargs array: unsafe!
    static <T> T[] pair(T a, T b) { return unsafeToArray(a, b); }  // T erased → creates an Object[]

    /** Super type token: capture a full generic type at run time (Jackson TypeReference, Spring ParameterizedTypeReference). */
    static abstract class TypeRef<T> {
        final Type type = ((ParameterizedType) getClass().getGenericSuperclass()).getActualTypeArguments()[0];
    }

    public static void main(String[] args) {
        List<String> names = new ArrayList<>(List.of("ann"));
        legacyLibrary(names);                                        // compiles (unchecked warning), succeeds at run time
        System.out.println("size=" + names.size() + " (an Integer is now inside List<String>)");
        try {
            for (String n : names) System.out.print(n.length() + " ");   // checkcast String fails HERE, far from the bug
        } catch (ClassCastException e) { System.out.println("\nCCE at the read site: " + e.getMessage().replaceAll(" \\(.*", "")); }

        try { String[] arr = pair("a", "b"); }
        catch (ClassCastException e) { System.out.println("generic varargs array: " + e.getMessage().replaceAll(" \\(.*", "")); }

        System.out.println("type token: " + new TypeRef<Map<String, List<Integer>>>() { }.type);
        System.out.println("erasure: " + (new ArrayList<String>().getClass() == new ArrayList<Integer>().getClass()));
    }
}
```

Output (verified):

```
size=2 (an Integer is now inside List<String>)
3
CCE at the read site: class java.lang.Integer cannot be cast to class java.lang.String
generic varargs array: class [Ljava.lang.Object; cannot be cast to class [Ljava.lang.String;
type token: java.util.Map<java.lang.String, java.util.List<java.lang.Integer>>
erasure: true
```

**Defensive measures:** never ignore unchecked warnings without proving safety. Use `Collections.checkedList(list, String.class)` at boundaries with legacy or raw code (it fails at *insert* time instead). Use `@SafeVarargs` only on methods that don't store into or expose the varargs array.

### 1.4 Variance: wildcards and PECS 🔥🎓

Arrays are **covariant** (`String[]` is an `Object[]`), checked at run time with `ArrayStoreException`. Generics are **invariant** (`List<String>` is **not** a `List<Object>`). Wildcards restore flexibility safely:

| Declaration | Can read as | Can write | Use when the parameter is a… |
|---|---|---|---|
| `List<? extends Number>` | `Number` | Nothing (except `null`) | **Producer** (you only take values out) |
| `List<? super Integer>` | `Object` | `Integer` (and subtypes) | **Consumer** (you only put values in) |
| `List<?>` | `Object` | Nothing (except `null`) | Don't care about the type |
| `List<Number>` | `Number` | `Number` | Both, with exactly `Number` |

**PECS: Producer `extends`, Consumer `super`.** See `Collections.copy(List<? super T> dest, List<? extends T> src)` and `Collections.max(Collection<? extends T>, Comparator<? super T>)`.

Recursive bound: `<T extends Comparable<? super T>> T max(Collection<? extends T> c)`. The `? super T` lets `java.sql.Timestamp` (which is `Comparable<java.util.Date>`) work.

<!-- run: -->
```java
import java.util.*;

public class Pecs {
    static double sum(Collection<? extends Number> producer) {            // read-only view of "some Number subtype"
        double s = 0; for (Number n : producer) s += n.doubleValue(); return s;
    }
    static void fill(List<? super Integer> consumer, int n) {             // can add Integers to List<Number>/List<Object>
        for (int i = 0; i < n; i++) consumer.add(i);
    }
    static void swapFirstTwo(List<?> list) { swapHelper(list); }           // wildcard capture via helper
    private static <T> void swapHelper(List<T> l) { T tmp = l.get(0); l.set(0, l.get(1)); l.set(1, tmp); }

    public static void main(String[] args) {
        List<Integer> ints = List.of(1, 2, 3); List<Double> doubles = List.of(0.5, 1.5);
        System.out.println(sum(ints) + " " + sum(doubles));
        List<Number> numbers = new ArrayList<>(); List<Object> objects = new ArrayList<>();
        fill(numbers, 3); fill(objects, 2);
        System.out.println(numbers + " " + objects);
        List<String> pair = new ArrayList<>(List.of("x", "y"));
        swapFirstTwo(pair);
        System.out.println(pair);
        Object[] arr = new String[1];
        try { arr[0] = 42; } catch (ArrayStoreException e) { System.out.println("covariant arrays fail at run time: ArrayStoreException " + e.getMessage()); }
    }
}
```

Output (verified):

```
6.0 2.0
[0, 1, 2] [0, 1]
[y, x]
covariant arrays fail at run time: ArrayStoreException java.lang.Integer
```

### 1.5 Inference and `var` 🎓

* Diamond `new ArrayList<>()` infers from the target. **`var list = new ArrayList<>();` infers `ArrayList<Object>`**, because there's no target to infer from.
* Explicit type witness: `Collections.<String>emptyList()`, `this.<T>convert(x)`.
* `var` is allowed for local variables with initializers, for-loop variables and lambda parameters (`(var x, var y) ->`, all-or-nothing). It is not allowed for fields, method parameters, return types, `var x = null;`, `var a = {1, 2};`, or `var x;` without an initializer. `var` is a reserved type name, not a keyword: `var var = 1;` is legal.

---

## 2. Exceptions — internals, costs and exam rules 🔥

### 2.1 How `try/catch/finally` compiles

```java
static int tryFinally(int x) {
    try { return x * 2; }
    catch (IllegalStateException e) { return -1; }
    finally { System.out.println("finally"); }
}
```

Real `javap -c -p` (JDK 25). Note that the **`finally` body is duplicated three times** and that "any" handlers cover both the try and the catch blocks:

```
   0: iload_0  1: iconst_2  2: imul  3: istore_1               ← compute return value, stash it
   4: getstatic System.out … 9: invokevirtual println           ← finally copy #1 (normal path)
  12: iload_1 13: ireturn
  14: astore_1 15: iconst_m1 16: istore_2                      ← catch IllegalStateException
  17: getstatic … 22: invokevirtual println                     ← finally copy #2 (catch path)
  25: iload_2 26: ireturn
  27: astore_3                                                  ← any other throwable
  28: getstatic … 33: invokevirtual println                     ← finally copy #3 (exceptional path)
  36: aload_3 37: athrow
Exception table:
   from    to  target type
     0     4    14   Class java/lang/IllegalStateException
     0     4    27   any
    14    17    27   any
```

* **The return value is computed before `finally` runs and stashed in a local.** Modifying the variable in `finally` doesn't change the returned value (for primitives, or for reassigning a reference). A `return` *inside* `finally` overrides everything, **including a pending exception**, which is silently discarded. That is an exam trap and a production bug.
* Exception tables are scanned only when something is thrown, so a `try` block costs nothing on the happy path.

### 2.2 The cost of exceptions (measured)

<!-- run: timeout=120 -->
```java
public class ExceptionCost {
    static final class FullTrace extends RuntimeException { FullTrace() { super("full"); } }
    static final class NoTrace extends RuntimeException { NoTrace() { super("lite", null, false, false); } }   // no suppression, no stack trace
    static final RuntimeException PREALLOCATED = new NoTrace();

    static int depth(int d, int mode) {                       // recursion puts real frames on the stack
        if (d > 0) return depth(d - 1, mode) + 1;
        switch (mode) {
            case 0 -> throw new FullTrace();
            case 1 -> throw new NoTrace();
            case 2 -> throw PREALLOCATED;
            default -> { return -1; }
        }
    }

    static double measure(int mode, int stackDepth) {
        int iters = 200_000; long best = Long.MAX_VALUE; long sink = 0;
        for (int round = 0; round < 7; round++) {
            long t = System.nanoTime();
            for (int i = 0; i < iters; i++) {
                try { sink += depth(stackDepth, mode); } catch (RuntimeException e) { sink += e.getMessage().length(); }
            }
            best = Math.min(best, System.nanoTime() - t);
        }
        if (sink == 42) System.out.print("");
        return best / (double) iters;
    }

    public static void main(String[] args) {
        for (int d : new int[] {5, 50}) {
            System.out.printf("stack depth %2d: new exception w/ trace %8.1f ns | w/o trace %6.1f ns | preallocated %6.1f ns | return code %5.1f ns%n",
                d, measure(0, d), measure(1, d), measure(2, d), measure(3, d));
        }
    }
}
```

Two measured runs (JDK 25):

```
stack depth  5: new exception w/ trace   1040.3 ns | w/o trace  144.2 ns | preallocated  149.0 ns | return code   3.7 ns
stack depth 50: new exception w/ trace   4401.7 ns | w/o trace 1999.0 ns | preallocated 2038.1 ns | return code  65.6 ns
stack depth  5: new exception w/ trace   1022.3 ns | w/o trace  158.7 ns | preallocated  140.3 ns | return code   3.9 ns
stack depth 50: new exception w/ trace   4692.5 ns | w/o trace 2091.7 ns | preallocated 1926.5 ns | return code  75.6 ns
```

**Anatomy of the cost:**

1. **`fillInStackTrace()`** (in the `Throwable` constructor) walks the stack, which is the bulk at shallow depth (~1 µs vs ~0.15 µs). The cost grows with depth, up to `-XX:MaxJavaStackTraceDepth=1024` frames.
2. **Unwinding**: looking up handlers frame by frame through non-inlined frames costs ~2 µs for 50 frames even without a trace. When thrower and catcher are inlined into the same compiled method, C2 turns the `throw` into a plain jump, which is nearly free.
3. Framework stacks are often 100–300 frames deep (Spring, servlet filters, reactive operators), so a 404-as-exception at 10k req/s costs measurable CPU. **Don't use exceptions for expected control flow** (validation results, "not found"). Return `Optional`/result types.
4. Lightweight exceptions: `super(msg, cause, false, false)` disables suppression and stack-trace capture. Useful for high-frequency, well-understood signals; never for real errors, because you lose the diagnostics.

### 2.3 Checked vs unchecked and the overriding rules 🎓

```
Throwable
 ├── Error                      (unchecked)  OutOfMemoryError, StackOverflowError, ExceptionInInitializerError, AssertionError
 └── Exception                  (checked)    IOException, SQLException, InterruptedException, ReflectiveOperationException
      └── RuntimeException      (unchecked)  NPE, IllegalArgumentException, IllegalStateException, ClassCastException,
                                              ArithmeticException, IndexOutOfBounds, UnsupportedOperation, ConcurrentModification
```

* **Catch or declare** applies to checked exceptions only.
* An overriding method may declare **fewer or narrower** checked exceptions, never broader or new ones. Unchecked ones are always allowed.
* A `catch` block for a checked exception that the try block **cannot throw** is a compile error (except for `Exception`/`Throwable`).
* Multi-catch `catch (IOException | SQLException e)`: the alternatives can't be subtypes of each other (compile error), and `e` is implicitly **final**.
* **Precise rethrow:** `catch (Exception e) { throw e; }` with an effectively final `e` only throws the checked types the try block can actually throw, so the method needn't declare `Exception`.
* `InterruptedException`: catching it clears the interrupt flag. Either rethrow it or call `Thread.currentThread().interrupt()` (Pillar 3).

### 2.4 try-with-resources desugaring and suppressed exceptions 🔥🎓

<!-- run: -->
```java
public class TwrSemantics {
    record Res(String name, boolean failOnClose) implements AutoCloseable {
        Res { System.out.println("open " + name); }
        @Override public void close() {
            System.out.println("close " + name);
            if (failOnClose) throw new IllegalStateException("close failed: " + name);
        }
    }

    @SuppressWarnings("finally")
    static int finallyOverrides() {
        try { throw new RuntimeException("lost!"); }
        finally { return 7; }                       // discards the exception (compiler warns)
    }

    static int returnValueSnapshot() {
        int x = 1;
        try { return x; } finally { x = 99; }       // returned value was already stashed → 1
    }

    public static void main(String[] args) {
        try (Res a = new Res("A", true); Res b = new Res("B", true); Res none = null) {   // null resources are allowed
            throw new RuntimeException("body failed");
        } catch (RuntimeException e) {
            System.out.println("caught: " + e.getMessage());
            for (Throwable s : e.getSuppressed()) System.out.println("  suppressed: " + s.getMessage());
        } finally {
            System.out.println("finally runs after the resources are closed");
        }
        System.out.println("finally return overrides exception → " + finallyOverrides());
        System.out.println("return value snapshot → " + returnValueSnapshot());

        Res shared = new Res("C", false);
        try (shared) { System.out.println("using effectively-final resource " + shared.name()); }   // Java 9+
    }
}
```

Output (verified):

```
open A
open B
close B
close A
caught: body failed
  suppressed: close failed: B
  suppressed: close failed: A
finally runs after the resources are closed
finally return overrides exception → 7
return value snapshot → 1
open C
using effectively-final resource C
close C
```

Rules shown: resources close in **reverse order of declaration**, **before** `catch`/`finally` run. Close failures are **added as suppressed** to the primary exception (with the old manual `finally { close(); }` pattern, a close failure *replaced* the original exception). Only if the body succeeds does a close exception become the thrown exception.

### 2.5 Helpful NullPointerExceptions (JEP 358, JDK 14+) ⚡

<!-- run: -->
```java
public class HelpfulNpe {
    record Address(String city) {}
    record Customer(String name, Address address) {}
    public static void main(String[] args) {
        Customer c = new Customer("ann", null);
        try { System.out.println(c.address().city().length()); }
        catch (NullPointerException e) { System.out.println(e.getMessage()); }
        int[][] grid = new int[2][];
        try { grid[1][0] = 5; }
        catch (NullPointerException e) { System.out.println(e.getMessage()); }
    }
}
```

Output (verified):

```
Cannot invoke "HelpfulNpe$Address.city()" because the return value of "HelpfulNpe$Customer.address()" is null
Cannot store to int array because "<local2>[1]" is null
```

Local variable names appear only if the class was compiled with `-g` (debug info). Otherwise you see `<localN>`, as here, because the source launcher doesn't keep local variable tables. Remember that NPE messages can lose their *stack traces* in hot code because of `OmitStackTraceInFastThrow` ([1.5 §3.2](../01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md#32-the-omitstacktraceinfastthrow-production-gotcha-)).

### 2.6 Exception design guidance for services

* **Translate at boundaries:** map low-level exceptions (`SQLException`, `IOException`) to domain or infrastructure exceptions *with the cause chained*. Never `throw new X(e.getMessage())`, which loses the trace.
* **Don't log and rethrow.** That produces duplicate stack traces in logs. Log once, at the boundary that handles it.
* Map exceptions to HTTP status in one place (Spring `@ControllerAdvice`, Problem Details RFC 9457).
* Don't catch `Throwable`/`Error` except at thread or process top level. Never swallow `InterruptedException` or `OutOfMemoryError`.

---

## 3. The object model: resolution rules the JVM and javac apply 🔥🎓

### 3.1 Overload resolution happens at compile time, in three phases (JLS §15.12.2)

1. **Phase 1:** applicable by strict/loose invocation **without boxing/unboxing or varargs** (identity, widening primitive, widening reference).
2. **Phase 2:** allow **boxing and unboxing**.
3. **Phase 3:** allow **varargs**.

Within the first phase that finds candidates, the **most specific** method wins. If none is most specific, the call is ambiguous (compile error). **Overriding** (run-time dispatch on the receiver) applies only after the signature has been chosen at compile time.

<!-- run: -->
```java
public class OverloadResolution {
    static String m(long x) { return "long (widening)"; }
    static String m(Integer x) { return "Integer (boxing)"; }
    static String m(int... xs) { return "int... (varargs)"; }
    static String m(Object o) { return "Object"; }

    static String n(Object o) { return "n(Object)"; }
    static String n(String s) { return "n(String)"; }

    static class Animal { String sound() { return "..."; } String name = "animal"; static String kind() { return "Animal"; } }
    static class Dog extends Animal { @Override String sound() { return "woof"; } String name = "dog"; static String kind() { return "Dog"; } }

    public static void main(String[] args) {
        int i = 5;
        System.out.println(m(i));                  // phase 1 finds m(long) via widening; boxing never considered
        System.out.println(m(Integer.valueOf(5))); // phase 1: Integer exact; Object also applicable, but Integer is more specific
        System.out.println(m());                   // only varargs applies
        System.out.println(n(null));               // both apply; String is more specific than Object
        Object s = "text";
        System.out.println(n(s));                  // static type Object → n(Object), regardless of the runtime type

        Animal a = new Dog();
        System.out.println(a.sound() + " | field: " + a.name + " | static: " + a.kind());
        // methods: dynamic dispatch (Dog) | fields: static type (Animal) | static methods: hidden, by static type (Animal)
    }
}
```

Output (verified):

```
long (widening)
Integer (boxing)
int... (varargs)
n(String)
n(Object)
woof | field: animal | static: Animal
```

### 3.2 Overriding vs hiding rules 🎓

| | Instance method (override) | Static method | Field |
|---|---|---|---|
| Resolution | **Run time**, by the object's class (virtual) | Compile time, by **static type** (hiding) | Compile time, by **static type** (hiding) |
| Access modifier | Same or **wider** (can't reduce `public` → `protected`) | Same rule | Any |
| Return type | Same or **covariant** subtype (primitives: identical) | Same rule | — |
| Checked exceptions | Same, narrower or fewer | Same rule | — |
| `static` ↔ instance | Instance can't override static (compile error), and vice versa | — | — |
| `final` / `private` | `final`: can't override. `private`: not inherited, so a same-named method is a *new* method | `final` static can't be hidden | — |

### 3.3 Interfaces: default-method conflict resolution 🎓

1. **Class wins:** a method in the class or any superclass beats interface defaults.
2. **More specific interface wins:** if `B extends A` and both define `m()`, then `B.m()` wins.
3. Otherwise you **must override** to resolve the conflict, optionally delegating with `A.super.m()`.

Interfaces may declare `private` (JDK 9) and `private static` methods (helpers for defaults), `static` methods (not inherited by implementing classes: call `Iface.m()`), and constants (implicitly `public static final`). They can't have instance fields or constructors.

<!-- run: -->
```java
public class DefaultDiamond {
    interface Walker { default String move() { return "walk"; } }
    interface Swimmer { default String move() { return "swim"; } }
    static class Duck implements Walker, Swimmer {
        @Override public String move() { return Walker.super.move() + "+" + Swimmer.super.move(); }  // mandatory override
    }
    static class Base { public String move() { return "base"; } }
    static class Robot extends Base implements Walker { }       // class wins over the default
    public static void main(String[] args) {
        System.out.println(new Duck().move() + " " + new Robot().move());
    }
}
```

Output (verified): `walk+swim base`

### 3.4 Nested classes and the hidden outer reference 🔥

| Kind | Holds a reference to the enclosing instance? | Typical use |
|---|---|---|
| **Static nested** | No | Builders, helpers, `Map.Entry` implementations |
| **Inner** (non-static member) | **Yes, if the body uses the enclosing instance** (synthetic field `this$0`). Since JDK 18, javac **omits** `this$0` when the inner class never uses it (serializable inner classes keep it) | Iterators over the outer collection |
| Local class | Same rule in an instance context; also captures the effectively final locals it uses | Rare |
| Anonymous class | Same as local | Pre-lambda callbacks |
| Lambda | Only if it uses `this` or instance members (captured as a field of the hidden class) | Callbacks |

<!-- run: -->
```java
import java.lang.reflect.Field;
import java.util.Arrays;

public class OuterReference {
    private final byte[] big = new byte[10_000_000];              // 10 MB owned by the outer object

    class InnerUsing { int size() { return big.length; } }        // uses outer state → needs OuterReference.this
    class InnerUnused { int answer() { return 42; } }             // never touches the outer instance
    static class Nested { }

    Runnable anonymousUsing() { return new Runnable() { public void run() { System.out.print(big.length > 0 ? "" : "?"); } }; }
    Runnable lambdaUsing() { return () -> System.out.print(big.length > 0 ? "" : "?"); }   // captures `this`
    Runnable lambdaPure() { return () -> System.out.print(""); }                           // captures nothing

    static String fields(Class<?> c) { return Arrays.toString(Arrays.stream(c.getDeclaredFields()).map(Field::getName).toArray()); }

    public static void main(String[] args) {
        var outer = new OuterReference();
        System.out.println("InnerUsing fields:     " + fields(InnerUsing.class));
        System.out.println("InnerUnused fields:    " + fields(InnerUnused.class) + "  ← JDK 18+ javac drops the unused this$0");
        System.out.println("Nested fields:         " + fields(Nested.class));
        System.out.println("anonymous (uses big):  " + fields(outer.anonymousUsing().getClass()) + "  ← keeps 10 MB alive as long as the callback lives");
        System.out.println("lambda (uses big):     " + fields(outer.lambdaUsing().getClass()));
        System.out.println("lambda (pure):         " + fields(outer.lambdaPure().getClass()));
    }
}
```

Output (verified, JDK 25):

```
InnerUsing fields:     [this$0]
InnerUnused fields:    []  ← JDK 18+ javac drops the unused this$0
Nested fields:         []
anonymous (uses big):  [this$0]  ← keeps 10 MB alive as long as the callback lives
lambda (uses big):     [arg$1]
lambda (pure):         []
```

**Version note:** before JDK 18, **every** inner and anonymous class created in an instance context held `this$0`, even if unused. That leak pattern is still everywhere in code compiled with older JDKs (classes in JARs keep the bytecode they were compiled with).

**Production rule:** a listener or callback registered with a long-lived registry (event bus, scheduler, cache) as an inner or anonymous class keeps the **entire outer object** alive. Make nested classes `static` unless they genuinely need the outer instance.

### 3.5 `equals`, `hashCode`, `compareTo` contracts ⚡🎓

* `equals`: reflexive, symmetric, transitive, consistent, `x.equals(null) == false`. Inheritance plus added state breaks symmetry (*Effective Java* item 10). Prefer composition, or `getClass()`-based checks for non-final hierarchies, or records.
* `hashCode`: equal objects must have equal hashes. Unequal objects may collide.
* `compareTo`: sign-symmetric and transitive, ideally **consistent with equals**. `BigDecimal` is the famous counterexample ([2.1 §2.8](01-Collections-Internals.md#28-equalshashcode-contract-failures-)). Never implement comparators as `a - b` (overflow); use `Integer.compare`.
* `clone()`: shallow, requires `Cloneable`, bypasses constructors. Arrays' `clone()` is fine and public. Prefer copy constructors or factories.

---

## 4. Primitives, boxing and arithmetic traps 🔥🎓

<!-- run: -->
```java
public class NumericTraps {
    public static void main(String[] args) {
        Integer a = 127, b = 127, c = 128, d = 128;
        System.out.println((a == b) + " " + (c == d) + " " + c.equals(d) + "   ← Integer cache is -128..127 (-XX:AutoBoxCacheMax raises the top)");

        Integer missing = null;
        boolean flag = true;
        try { int v = flag ? missing : 0; System.out.println(v); }          // ternary unboxes `missing`
        catch (NullPointerException e) { System.out.println("ternary unboxing NPE"); }

        byte bt = 10;
        bt += 120;                                                           // compound assignment = implicit (byte) cast
        System.out.println("byte 10 += 120 → " + bt + "   (bt = bt + 120 would not compile)");

        int big = Integer.MAX_VALUE;
        long wrong = big + 1;                                                // int overflow happens BEFORE widening
        long right = big + 1L;
        System.out.println("MAX+1 as int then long: " + wrong + " vs " + right);
        try { Math.addExact(big, 1); } catch (ArithmeticException e) { System.out.println("Math.addExact → " + e.getMessage()); }

        System.out.println("char math: " + ('a' + 1) + " " + (char) ('a' + 1) + " " + ("" + 'a' + 1));
        System.out.println("integer division: " + (7 / 2) + " " + (-7 / 2) + " " + (-7 % 3) + " " + Math.floorMod(-7, 3));
        System.out.println("0.1 + 0.2 = " + (0.1 + 0.2) + ", NaN == NaN: " + (Double.NaN == Double.NaN)
            + ", Double.valueOf(NaN).equals(NaN): " + Double.valueOf(Double.NaN).equals(Double.NaN)
            + ", 0.0 == -0.0: " + (0.0 == -0.0) + ", 1/0.0 = " + (1 / 0.0));
        try { System.out.println(1 / 0); } catch (ArithmeticException e) { System.out.println("int / 0 → " + e.getMessage()); }
        long l = 1_000_000 * 1_000_000;                                       // int * int overflows
        System.out.println("1_000_000 * 1_000_000 = " + l + " ; with L: " + 1_000_000L * 1_000_000);
        short s1 = 1, s2 = 2;
        int sum = s1 + s2;                                                    // binary numeric promotion → int
        System.out.println("short + short is int: " + sum + ", Long.compare vs subtraction overflow: "
            + Long.signum(Long.compare(Long.MIN_VALUE, 1)) + " vs " + Long.signum(Long.MIN_VALUE - 1));
    }
}
```

Output (verified):

```
true false true   ← Integer cache is -128..127 (-XX:AutoBoxCacheMax raises the top)
ternary unboxing NPE
byte 10 += 120 → -126   (bt = bt + 120 would not compile)
MAX+1 as int then long: -2147483648 vs 2147483648
Math.addExact → integer overflow
char math: 98 b a1
integer division: 3 -3 -1 2
0.1 + 0.2 = 0.30000000000000004, NaN == NaN: false, Double.valueOf(NaN).equals(NaN): true, 0.0 == -0.0: true, 1/0.0 = Infinity
int / 0 → / by zero
1_000_000 * 1_000_000 = -727379968 ; with L: 1000000000000
short + short is int: 3, Long.compare vs subtraction overflow: -1 vs 1
```

Every line is a classic exam question **and** a production bug class: caching-dependent `==`, null unboxing in ternaries and switches, silent overflow in time and money arithmetic, and comparator subtraction overflow. Money must use `long` minor units or `BigDecimal` ([2.6](06-Date-Time-Localization-Numerics.md)).

---

## 5. Production failure modes & diagnostics

| Failure | Signature | Fix |
|---|---|---|
| `ClassCastException` in a `for` loop over a typed list | Heap pollution from raw types, unchecked casts, or reflection/JSON mapping into the wrong generic type | `Collections.checkedList` at boundaries; type tokens for deserialization |
| Lost exceptions | `return` in `finally`; `catch (Exception e) {}`; close exceptions overwriting originals (manual `finally`) | try-with-resources; never return from `finally`; log or propagate |
| Exceptions as control flow | CPU in `Throwable.fillInStackTrace` (async-profiler/JFR) | Result types/`Optional`; lightweight exceptions for well-known signals |
| Duplicate stack traces in logs | Log-and-rethrow at each layer | Log once at the boundary |
| Memory leak via listeners | Retained inner or anonymous classes holding `this$0` | Static nested classes; weak listeners; unregister |
| Wrong overload called after a refactor | Changing a parameter's static type changes compile-time overload choice | Avoid overloading with related types; prefer distinct method names |
| Overflow in time/money math | Negative durations or amounts | `Math.*Exact`, `long` math, `Duration`, `BigDecimal` |

---

## 6. Interview & certification Q&A

<details><summary><b>Q1. 🎓 What is printed? <code>static void f(long x){System.out.print("L");} static void f(Integer x){System.out.print("I");} static void f(Object x){System.out.print("O");} … f(5); f((short)5); f(5L); f('c');</code></b></summary>

`LLLL`. Each call finds `f(long)` in phase 1 through widening (`int`→`long`, `short`→`long`, `char`→`long`) or identity (`5L`). Boxing (phase 2) is never needed.
</details>

<details><summary><b>Q2. 🔥 Explain bridge methods and why a raw `Comparator` can throw `ClassCastException` inside `compare`.</b></summary>

After erasure, `ByLength implements Comparator<String>` has `compare(String,String)`, but the interface's erased method is `compare(Object,Object)`. javac generates a synthetic bridge `compare(Object,Object)` that casts its arguments to `String` and delegates. Calling it through a raw or polluted reference with an `Integer` fails at the bridge's `checkcast`.
</details>

<details><summary><b>Q3. 🎓 What does `try { return 1; } finally { return 2; }` return? And `int x=1; try { return x; } finally { x=2; }`?</b></summary>

The first returns 2, because a `return` in `finally` overrides (and would also discard any exception). The second returns 1: the value is evaluated and stored before `finally` runs, and reassigning `x` afterwards doesn't affect the stored return value.
</details>

<details><summary><b>Q4. 🎓 In what order are try-with-resources resources closed, and what happens to an exception thrown by `close()` if the body also threw?</b></summary>

Reverse order of declaration, before any `catch`/`finally` of the same statement. The body's exception is the primary one, and close exceptions are attached via `addSuppressed` (retrieve them with `getSuppressed()`). If the body completes normally, the first close exception is thrown, with any later ones suppressed into it.
</details>

<details><summary><b>Q5. 🔥 Explain PECS with a real JDK signature.</b></summary>

`Collections.copy(List<? super T> dest, List<? extends T> src)`. `src` *produces* `T`s, so it uses `extends` (you can read `T`s from a list of any subtype). `dest` *consumes* `T`s, so it uses `super` (you can write `T`s into a list of any supertype). This lets you copy a `List<Integer>` into a `List<Number>`.
</details>

<details><summary><b>Q6. 🎓 Which compile? (a) <code>List&lt;Number&gt; l = new ArrayList&lt;Integer&gt;();</code> (b) <code>List&lt;? extends Number&gt; l = new ArrayList&lt;Integer&gt;(); l.add(1);</code> (c) <code>List&lt;? super Integer&gt; l = new ArrayList&lt;Number&gt;(); l.add(1);</code> (d) <code>var v = new ArrayList&lt;&gt;(); v.add("x"); v.add(1);</code></b></summary>

(c) and (d). (a): generics are invariant. (b): you can't add to an `extends` wildcard list (except `null`). (d): `var` with a bare diamond infers `ArrayList<Object>`, so both adds compile.
</details>

<details><summary><b>Q7. 🔥 Why are exceptions expensive, and how would you make a high-frequency "not found" path cheap?</b></summary>

Most of the cost is `fillInStackTrace` walking deep stacks, plus unwinding through non-inlined frames (measured ~1 µs at depth 5, ~4.4 µs at depth 50, versus ~4 ns for a return value). Use return types (`Optional`, a sealed `Result`), or, for an exception-based API you can't change, exceptions constructed with `writableStackTrace=false`, accepting the loss of diagnostics.
</details>

<details><summary><b>Q8. 🎓 `Integer a = 1000, b = 1000; System.out.println(a == b);` and why?</b></summary>

`false` (with default settings). Autoboxing uses `Integer.valueOf`, which caches only -128..127 by default. Two distinct objects are compared by reference. Use `equals`, or compare `int` values.
</details>

<details><summary><b>Q9. ⚡ An overriding method wants to throw `Exception` while the parent declares `IOException`. Allowed?</b></summary>

No. An overriding method can't throw broader or new checked exceptions than the overridden method. It may throw `IOException`, subclasses of it, unchecked exceptions, or nothing.
</details>

<details><summary><b>Q10. 🎓 Static nested vs inner class: which can declare static members, and which needs an outer instance?</b></summary>

Static nested classes don't need an outer instance (`new Outer.Nested()`). Inner classes do (`outer.new Inner()`) and hold a hidden `this$0` reference whenever they use the enclosing instance (JDK 18+ javac omits it if unused). Since JDK 16, inner classes may also declare static members (a change introduced with records, JEP 395).
</details>

---

## 7. Further reading

* JLS §15.12.2 (method invocation), §4.6 (erasure), §14.20.3 (try-with-resources).
* *Effective Java* 3rd ed., chapters 5 (Generics) and 10 (Exceptions).
* Angelika Langer's Java Generics FAQ: <http://www.angelikalanger.com/GenericsFAQ/JavaGenericsFAQ.html>
* JEP 358 Helpful NPEs.
