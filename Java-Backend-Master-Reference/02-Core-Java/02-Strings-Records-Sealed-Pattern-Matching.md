# 2.2 · Strings, Immutability, Records, Sealed Types, Enums & Pattern Matching

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam (strings, text blocks, records, sealed, enums, switch and pattern matching are heavily tested on 1Z0-830/831)
> **Sources:** JLS SE 25 §3.10.5 (string literals), §15.29 (constant expressions), §8.10 (records), §8.1.1.2 (sealed), §14.11 and §14.30 (switch, patterns), §17.5 (final field semantics); JEP 254 (compact strings), 280 (indy concat), 378 (text blocks), 395 (records), 409 (sealed), 440/441 (record patterns, switch patterns), 456 (unnamed variables), 507 (primitive patterns, preview in 25), 513 (flexible constructor bodies, JDK 25).
> All `javap` excerpts below are real output from JDK 25's `javap -c -p`/`-v`.

---

## 1. `String` internals 🔥

### 1.1 Layout (JDK 9+ compact strings)

```java
public final class String {
    private final byte[] value;   // LATIN1: 1 byte/char; UTF16: 2 bytes/char
    private final byte coder;     // 0 = LATIN1, 1 = UTF16 (chosen at construction; all-or-nothing)
    private int hash;             // cached hashCode (0 = not computed yet…)
    private boolean hashIsZero;   // …unless the real hash is 0 (JDK 13+), avoids recomputing forever
}
```

* `"hello"` = 24 B `String` + 24 B `byte[]` (16 header + 5, padded) = **48 B**. Before JDK 9 a `char[]` doubled the payload.
* One non-Latin-1 char (`'€'`, `'é'` is Latin-1, `'中'` isn't) switches the **whole** string to UTF-16.
* `-XX:-CompactStrings` disables it. Rarely useful; maybe for workloads that are almost entirely non-Latin-1.
* `length()` counts **UTF-16 code units**, not characters: `"😀".length() == 2`. Use `codePointCount`/`codePoints()` for user-visible characters. Full grapheme clusters need `BreakIterator`.

<!-- run: jvm="--add-opens java.base/java.lang=ALL-UNNAMED" -->
```java
import java.lang.reflect.Field;

public class CompactStrings {
    public static void main(String[] args) throws Exception {
        Field value = String.class.getDeclaredField("value"); value.setAccessible(true);
        Field coder = String.class.getDeclaredField("coder"); coder.setAccessible(true);
        for (String s : new String[] {"hello", "héllo", "h€llo", "😀"}) {
            byte[] v = (byte[]) value.get(s);
            System.out.printf("%-6s length()=%d codePoints=%d coder=%s value.length=%d%n",
                s, s.length(), s.codePointCount(0, s.length()), (byte) coder.get(s) == 0 ? "LATIN1" : "UTF16", v.length);
        }
    }
}
```

Output (verified):

```
hello  length()=5 codePoints=5 coder=LATIN1 value.length=5
héllo  length()=5 codePoints=5 coder=LATIN1 value.length=5
h€llo  length()=5 codePoints=5 coder=UTF16 value.length=10
😀     length()=2 codePoints=1 coder=UTF16 value.length=4
```

### 1.2 The string pool (StringTable) and identity 🔥🎓

* String **literals** and compile-time **constant expressions** are interned. The constant-pool `CONSTANT_String` entry is resolved lazily by `ldc` to a canonical `String` in the JVM's **StringTable** (a native hashtable whose entries reference heap objects; `StringTableSize=65536` buckets, resized concurrently).
* `new String("x")` always creates a new object. `s.intern()` returns the canonical instance.
* **Constant expression** (JLS §15.29): literals, `final` variables of primitive/String type initialized with constant expressions, and operators on them, all folded at compile time. Anything involving a non-final variable or a method call is computed at run time and **not** interned.

<!-- run: -->
```java
public class StringIdentity {
    static final String PREFIX = "Ja";                       // constant variable
    static String nonConstant() { return "Ja"; }

    public static void main(String[] args) {
        String a = "Java";
        String b = "Ja" + "va";                              // folded by javac → same literal
        final String ja = "Ja";
        String c = ja + "va";                                // final local constant → folded
        String part = "Ja";
        String d = part + "va";                              // runtime concat → new object
        String e = PREFIX + "va";                            // static final constant → folded
        String f = nonConstant() + "va";                     // method call → runtime
        String g = new String("Java");
        System.out.println((a == b) + " " + (a == c) + " " + (a == d) + " " + (a == e) + " " + (a == f) + " " + (a == g));
        System.out.println((a == d.intern()) + " " + a.equals(d) + " " + (g.intern() == a));
    }
}
```

Output (verified): `true true false true false false`, then `true true true`.

> **Production rule:** never use `==` on strings (except deliberately on interned constants). Don't `intern()` unbounded input (user IDs, JSON values): the StringTable grows, GC must scan it, and it's a DoS vector. For deduplicating many equal long-lived strings, prefer a bounded `Map<String,String>` canonicalizer or `-XX:+UseStringDeduplication` (GC-side, dedups the `byte[]` only).

### 1.3 Concatenation: `invokedynamic` since JDK 9 (JEP 280) ⚡

```java
static String concat(String name, int age) { return "name=" + name + ", age=" + age; }
```

`javap -c -p` (JDK 25):

```
  static java.lang.String concat(java.lang.String, int);
    Code:
         0: aload_0
         1: iload_1
         2: invokedynamic #7,  0   // InvokeDynamic #0:makeConcatWithConstants:(Ljava/lang/String;I)Ljava/lang/String;
         7: areturn
  …
  #73 = String  #74   // name=\u0001, age=\u0001        ← the "recipe": \u0001 marks each argument slot
  #75 = MethodHandle 6:#76  // REF_invokeStatic java/lang/invoke/StringConcatFactory.makeConcatWithConstants:(…)
```

* javac emits **one** `invokedynamic` with a recipe. On first execution `StringConcatFactory` links an optimized strategy: it computes the exact length and coder up front, allocates one `byte[]` and copies once (no `StringBuilder` growth, no intermediate copies). JDK 23+ generates a hidden class per shape for even better code.
* **Consequences:** `a + b + c` in straight-line code is optimal; don't "optimize" it into a `StringBuilder`. But **concatenation in a loop** still creates a new String per iteration, so it is O(n²). Use `StringBuilder` (or `String.join`, `Collectors.joining`, `StringJoiner`).
* The first execution of each concat call site costs bootstrap and linking time (startup and Metaspace). Recall [the Metaspace OOM demo](../01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md#43-runnable-exhausting-metaspace-and-the-error-handler-that-also-fails), where a never-executed concat inside a `catch` failed to link.

<!-- run: -->
```java
public class ConcatLoop {
    public static void main(String[] args) {
        int n = 40_000;
        long t0 = System.nanoTime();
        String s = "";
        for (int i = 0; i < n; i++) s += 'x';                  // new String every iteration: O(n²) copying
        long t1 = System.nanoTime();
        StringBuilder sb = new StringBuilder(n);                // pre-sized: no growth copies
        for (int i = 0; i < n; i++) sb.append('x');
        String s2 = sb.toString();
        long t2 = System.nanoTime();
        System.out.printf("+= in loop: %d ms, StringBuilder: %.2f ms, equal=%b%n",
            (t1 - t0) / 1_000_000, (t2 - t1) / 1e6, s.equals(s2));
    }
}
```

Output (three measured runs on JDK 25): `+= in loop: 118 ms / 122 ms / 126 ms` vs `StringBuilder: 1.54 ms / 1.54 ms / 1.71 ms`. That is ~75× slower at n = 40,000, and the gap grows quadratically with n.

`StringBuilder` growth: `newCapacity = (oldCapacity << 1) + 2` (default capacity 16). It is not synchronized. `StringBuffer` is the synchronized legacy twin; don't use it.

### 1.4 API facts & traps 🎓

<!-- run: -->
```java
import java.util.Arrays;
import java.util.Locale;

public class StringTraps {
    public static void main(String[] args) {
        System.out.println(Arrays.toString("a,b,,".split(",")) + " " + "a,b,,".split(",").length);      // trailing empties dropped
        System.out.println(Arrays.toString("a,b,,".split(",", -1)));                                       // negative limit keeps them
        System.out.println(Arrays.toString("a.b.c".split(".")) + " (regex: '.' matches everything)");
        System.out.println(Arrays.toString("a.b.c".split("\\.")));

        String ws = "\u2003 hi \u2003";                                                                   // EM SPACE
        System.out.println("[" + ws.trim() + "] vs [" + ws.strip() + "]  isBlank(\"\\u2003\")=" + "\u2003".isBlank());

        Locale.setDefault(Locale.of("tr", "TR"));
        System.out.println("title".toUpperCase() + " vs " + "title".toUpperCase(Locale.ROOT) + "  (Turkish dotted İ)");
        System.out.println("TITLE".toLowerCase().equals("title") + "  ← fails under tr_TR: ı (dotless i)");
        Locale.setDefault(Locale.ROOT);

        String block = """
            {
              "id": 42,\s
              "note": "line one \
            continued"
            }""";
        System.out.println(block);
        System.out.println("indent/strip: [" + "  x\n  y".stripIndent() + "] repeat=" + "ab".repeat(3)
            + " chars=" + "abc".chars().sum() + " compareTo=" + "apple".compareTo("banana"));
        String s = null;
        System.out.println("concat with null: " + ("x" + s) + ", String.valueOf((Object) null)=" + String.valueOf((Object) null));
    }
}
```

Output (verified):

```
[a, b] 2
[a, b, , ]
[] (regex: '.' matches everything)
[a, b, c]
[  hi  ] vs [hi]  isBlank("\u2003")=true
TİTLE vs TITLE  (Turkish dotted İ)
false  ← fails under tr_TR: ı (dotless i)
{
  "id": 42, 
  "note": "line one continued"
}
indent/strip: [x
y] repeat=ababab chars=294 compareTo=-1
concat with null: xnull, String.valueOf((Object) null)=null
```

Key points:

* `split` takes a **regex**, and trailing empty strings are removed unless `limit < 0`. Single-char non-regex patterns take a fast path that skips regex compilation.
* `trim()` strips chars ≤ U+0020 only; `strip()`/`isBlank()` use `Character.isWhitespace` (Unicode-aware).
* **Always pass `Locale.ROOT`** to `toUpperCase`/`toLowerCase` for protocol strings (header names, enum lookups, SQL keywords). The Turkish-locale bug has broken real systems: `"title".toUpperCase()` → `"TİTLE"`.
* **Text blocks** (JEP 378): incidental indentation is removed relative to the closing delimiter and the least-indented line. Trailing spaces are stripped (use `\s` to keep one). `\` at the end of a line joins lines. The opening `"""` must be followed by a line terminator.
* `compareTo` is lexicographic by UTF-16 code unit: `"apple".compareTo("banana") == 'a' - 'b' == -1`. For human-language ordering use `Collator`.

### 1.5 Regex: compile once, beware catastrophic backtracking 🔥

* `String.matches`, `replaceAll` and `split` (non-fast-path) **compile a `Pattern` every call**. In hot paths, hold a `static final Pattern`.
* `java.util.regex` is a **backtracking** engine. Ambiguous quantified groups can take **exponential** time on non-matching input, which is the **ReDoS** class of vulnerabilities.
* **What modern JDKs fixed, and what they didn't** (measured on JDK 25, input `"a".repeat(n) + "!"`): since JDK 9 the engine memoizes failures for greedy loops over groups. The textbook patterns `(a+)+b`, `(a|aa)+b`, `^(\w+\s?)*$` and `(x+x+)+y` all stayed at **0 ms even at n = 30**. **Bounded repetitions** of variable-width groups are not covered: `(?:a+){2,20}b` took 86 → 322 → 1,272 → 5,499 ms for n = 22 → 28, and `(.*a){12}` grows polynomially (n¹²). Don't rely on the engine's memoization, because it covers specific shapes only. Old JDKs (8) are vulnerable to the classic patterns too.

<!-- run: timeout=60 -->
```java
import java.util.regex.Pattern;

public class Redos {
    public static void main(String[] args) {
        Pattern classic = Pattern.compile("(a+)+b");            // textbook ReDoS: memoized by JDK 9+ engines
        Pattern evil = Pattern.compile("(?:a+){2,20}b");        // bounded repetition of a variable-width group
        Pattern safe = Pattern.compile("a{2,}+b");              // same language, possessive, no ambiguity
        for (int n = 16; n <= 24; n += 2) {
            String input = "a".repeat(n) + "!";                 // can never match → engine explores all splits
            long t0 = System.nanoTime(); boolean m0 = classic.matcher(input).matches();
            long t1 = System.nanoTime(); boolean m1 = evil.matcher(input).matches();
            long t2 = System.nanoTime(); boolean m2 = safe.matcher(input).matches();
            long t3 = System.nanoTime();
            System.out.printf("n=%d classic=%5.1f ms  evil=%7.1f ms  safe=%.3f ms  (%b %b %b)%n",
                n, (t1 - t0) / 1e6, (t2 - t1) / 1e6, (t3 - t2) / 1e6, m0, m1, m2);
        }
    }
}
```

One measured run (JDK 25): `evil` roughly **quadruples every +2 characters** (exponential), while `classic` is defused by memoization and the unambiguous possessive pattern stays at microseconds.

```
n=16 classic=  0.2 ms  evil=    4.4 ms  safe=0.014 ms  (false false false)
n=18 classic=  0.1 ms  evil=   13.8 ms  safe=0.008 ms  (false false false)
n=20 classic=  0.0 ms  evil=   28.5 ms  safe=0.008 ms  (false false false)
n=22 classic=  0.1 ms  evil=   98.0 ms  safe=0.028 ms  (false false false)
n=24 classic=  0.0 ms  evil=  343.5 ms  safe=0.011 ms  (false false false)
```

At n = 34 the evil pattern would run for minutes, so a single malicious request can pin a CPU. **Mitigations:** possessive quantifiers (`a++`) and atomic groups (`(?>…)`); avoid nested quantifiers; bound input length *before* matching; run untrusted patterns with a timeout (interrupt-checking `CharSequence` wrapper) or a linear-time engine (RE2/J).

---

## 2. Immutability & `final` field semantics 🔥

* An immutable class has `private final` fields, no setters, defensive copies of mutable inputs and outputs, and is `final` (or has private constructors), so subclasses can't add mutability.
* **JMM bonus (JLS §17.5):** a correctly constructed object's `final` fields are guaranteed visible to all threads **without synchronization**, even if the reference is published through a data race. The "freeze" at the end of the constructor acts like a release barrier for those fields. This only holds if `this` doesn't **escape** during construction (no registering listeners or starting threads in the constructor).
* `final` instance fields are **not** treated as constants by the JIT (reflection could change them, `TrustFinalNonStaticFields=false`), **except** record fields and hidden-class fields, which are trusted. JEP 500 (JDK 26) begins warning on reflective mutation of finals, the path toward "final means final" and more constant folding.

---

## 3. Records (JDK 16, JEP 395) 🔥🎓

### 3.1 What javac generates

```java
record Point(int x, int y) {}
```

`javap -c -p` (JDK 25) shows a `final` class extending `java.lang.Record`, with `private final` fields, public accessors, and `toString/hashCode/equals` implemented via **one `invokedynamic`** each to `ObjectMethods.bootstrap`, with the component list `"x;y"` as a constant:

```
  private final int x;
  private final int y;
  public final java.lang.String toString();
         1: invokedynamic #16,  0   // InvokeDynamic #0:toString:(LBytecode$Point;)Ljava/lang/String;
  public final int hashCode();
         1: invokedynamic #20,  0   // InvokeDynamic #0:hashCode:(LBytecode$Point;)I
  public final boolean equals(java.lang.Object);
         2: invokedynamic #24,  0   // InvokeDynamic #0:equals:(LBytecode$Point;Ljava/lang/Object;)Z
  public int x();
  public int y();
  #42 = String  #43   // x;y
  #46 = MethodHandle 6:#47  // REF_invokeStatic java/lang/runtime/ObjectMethods.bootstrap:(…)
```

### 3.2 Rules (exam-grade) 🎓

| Rule | Detail |
|---|---|
| Implicitly `final` | Can't be extended. Can't be `abstract`. Can implement interfaces |
| Superclass | Implicitly `java.lang.Record`. No `extends` clause allowed |
| Fields | Only the component fields (implicitly `private final`). **No instance fields** may be declared; `static` fields are fine |
| Instance initializers | Not allowed. Static initializers are fine |
| Canonical constructor | Implicit if not declared. If declared explicitly, it must assign every field and can't be less accessible than the record |
| **Compact constructor** | `Point { if (x < 0) throw …; }`: no parameter list; parameters are implicit; **assign to the parameters** (e.g. `x = Math.abs(x)`), not to `this.x`. Fields are assigned *after* the body |
| Other constructors | Must delegate to another constructor (ultimately the canonical one) via `this(…)` as the first statement |
| Accessors | Can be overridden explicitly; must be `public`, same return type, no `throws` |
| Nested records | Implicitly `static`. Local records are allowed (and are static, so they can't capture locals) |
| `equals` | Component-wise: `==` for primitives (`float`/`double` via `compare`, so `NaN` equals `NaN`), `Objects.equals` for references, which is **reference equality for arrays** |
| Annotations | An annotation on a component propagates to the field, accessor, constructor parameter and/or record component, based on `@Target` |
| Serialization | Records deserialize **through the canonical constructor** (validation runs). They are the safest serializable classes (Pillar 4) |

<!-- run: -->
```java
import java.util.*;

public class RecordsDemo {
    record Money(long minorUnits, String currency) {
        Money {                                                  // compact canonical constructor
            Objects.requireNonNull(currency, "currency");
            if (minorUnits < 0) throw new IllegalArgumentException("negative amount");
            currency = currency.toUpperCase(Locale.ROOT);        // normalize: assign the PARAMETER
        }
        Money(long minorUnits) { this(minorUnits, "USD"); }     // non-canonical → must delegate
        static Money zero(String c) { return new Money(0, c); }
        Money plus(Money o) {
            if (!currency.equals(o.currency)) throw new IllegalArgumentException("currency mismatch");
            return new Money(minorUnits + o.minorUnits, currency);   // "wither" style: new instance
        }
    }

    record Basket(String id, List<String> items) {
        Basket { items = List.copyOf(items); }                  // defensive copy: shallow immutability made real
    }

    record Blob(byte[] data) {}                                 // arrays: equals is reference equality!

    public static void main(String[] args) {
        System.out.println(new Money(1999, "eur") + " " + new Money(5).plus(Money.zero("usd")));
        try { new Money(-1, "USD"); } catch (IllegalArgumentException e) { System.out.println("rejected: " + e.getMessage()); }

        List<String> src = new ArrayList<>(List.of("apple"));
        Basket b = new Basket("b1", src);
        src.add("pear");
        System.out.println(b + " (unaffected by later changes to src)");

        System.out.println("records equal: " + new Money(1, "USD").equals(new Money(1, "usd"))
            + ", Blob equal: " + new Blob(new byte[] {1}).equals(new Blob(new byte[] {1})));

        record Pair<A, B>(A first, B second) {}                  // local generic record
        var p = new Pair<>("k", 42);
        System.out.println(p + " components=" + Arrays.toString(Pair.class.getRecordComponents()));
    }
}
```

Output (verified):

```
Money[minorUnits=1999, currency=EUR] Money[minorUnits=5, currency=USD]
rejected: negative amount
Basket[id=b1, items=[apple]] (unaffected by later changes to src)
records equal: true, Blob equal: false
Pair[first=k, second=42] components=[java.lang.Object first, java.lang.Object second]
```

(`RecordComponent.toString()` prints the **erased** type. Use `getGenericType()` to see `A`/`B`.)

**Where records fit in a backend:** DTOs and API payloads (Jackson supports them natively), value objects (Money, Email), events and messages, composite map keys, query projections (Spring Data DTO projections, [5.3](../05-Persistence-JPA-Hibernate/03-Performance-NPlus1-Cartesian-Projections.md)), and pattern-matching ADTs. **Not** JPA entities: those need a no-arg constructor, mutable state for dirty checking, and non-final classes for lazy-loading proxies. **Derived record creation** (`p with { x = 3; }`, JEP 468) has been proposed but is **not** in JDK 27. Write explicit `withX` methods.

---

## 4. Sealed classes and interfaces (JDK 17, JEP 409) 🔥🎓

```java
public sealed interface Payment permits Card, BankTransfer, Wallet {}
public record Card(String last4) implements Payment {}                    // records are implicitly final ✔
public final class BankTransfer implements Payment { … }                  // final ✔
public non-sealed class Wallet implements Payment { … }                   // re-opens the hierarchy below Wallet
```

| Rule | Detail |
|---|---|
| Every permitted subclass must be `final`, `sealed` or `non-sealed` | Records and enums are implicitly final |
| Location | Permitted subclasses must be in the **same module** (named module) or the **same package** (unnamed module) |
| `permits` may be omitted | When all subclasses are declared in the same source file; the compiler infers them |
| Must directly extend | Each permitted class must actually extend or implement the sealed type |
| Class file | `PermittedSubclasses` attribute (shown below), enforced by the JVM at class loading |
| Reflection | `Class.isSealed()`, `Class.getPermittedSubclasses()` |

`javap -v` of a sealed interface (JDK 25):

```
PermittedSubclasses:
  Bytecode$Circle
  Bytecode$Square
```

**Why architects care:** a sealed hierarchy is a **closed sum type**. Combined with records (product types) and exhaustive `switch`, the compiler proves you handled every case. Adding a new variant breaks the build in every place that must handle it, instead of failing at run time in a `default` branch.

---

## 5. Pattern matching 🔥🎓

### 5.1 `instanceof` patterns and flow scoping

```java
if (obj instanceof String s && s.length() > 3) { use(s); }   // ✔ s in scope on the true branch of &&
if (!(obj instanceof Integer i)) return;                     // ✔ i in scope AFTER the if (definite matching)
use(i);
// if (obj instanceof String s || s.isEmpty())               // ✘ s not definitely matched on the || right side
```

Since JDK 21 the pattern may be the same type as the static type (`String s instanceof String t`), and generic patterns are allowed when the cast would be safe.

### 5.2 `switch` with patterns — semantics

| Feature | Detail |
|---|---|
| Type patterns | `case Circle c ->` |
| Record patterns | `case Point(int x, int y) ->`, nested: `case Line(Point(var x1, _), Point p2) ->` |
| Guards | `case Circle c when c.r() > 10 ->`. A guard can use pattern variables |
| `null` | Without `case null`, a null selector throws **NPE** (as before). `case null ->`, or `case null, default ->` handles it |
| **Exhaustiveness** | Switch **expressions**, and **statements using patterns or `null`**, must be exhaustive: cover all permitted subtypes of a sealed type, all enum constants, or have a `default`/unconditional pattern |
| **Dominance** | A case label must not be dominated by an earlier one (`case CharSequence cs` before `case String s` is a **compile error**). Guarded patterns don't dominate unguarded ones of the same type. Constant labels must come before type patterns of the same type |
| Qualified enum constants | `case Color.RED ->` is allowed in pattern switches (JDK 21) |
| Fall-through | Arrow labels never fall through. Colon labels do, and pattern variables can't be used after a fall-through into a pattern label |
| Unnamed `_` (JDK 22) | `case Point(var x, _) ->`, `catch (Exception _)`, `for (var _ : list)`, lambda parameter `_` |

### 5.3 How it's compiled: `typeSwitch` + `MatchException`

```java
static double area(Shape s) {
    return switch (s) {
        case Circle c -> Math.PI * c.r() * c.r();
        case Square q -> q.s() * q.s();
    };
}
```

`javap -c -p` (JDK 25), trimmed:

```
   2: invokestatic  #25   // Method java/util/Objects.requireNonNull   ← null selector → NPE (no case null)
  11: invokedynamic #31,  0   // InvokeDynamic #1:typeSwitch:(LBytecode$Shape;I)I   ← SwitchBootstraps.typeSwitch
  16: lookupswitch  { // 2
                 0: 54        ← Circle
                 1: 75        ← Square
           default: 44 }
  44: new           #35   // class java/lang/MatchException   ← synthesized "impossible" default
  50: invokespecial #37   // Method java/lang/MatchException."<init>"
  53: athrow
  54: aload_1
  55: checkcast     #40   // class Bytecode$Circle
```

* `SwitchBootstraps.typeSwitch` returns the index of the first matching label (the int argument lets the code **restart** after a failed guard).
* The compiler adds a **`MatchException` default** for exhaustive switches. It fires only if the hierarchy changed **after** this code was compiled, for example a new permitted subclass added to a library without recompiling the client. For enum switches the equivalent is a new constant, which used to be `IncompatibleClassChangeError`.
* For comparison, a classic `String` switch compiles to `hashCode()` + `lookupswitch` + `equals()` (javap below). Hash collisions are handled with `equals` chains.

```
   5: invokevirtual #11  // Method java/lang/String.hashCode:()I
   8: lookupswitch  { // 2
             70454: 36      ← "GET".hashCode()
           2461856: 50      ← "POST".hashCode()
           default: 61 }
  36: aload_1
  37: ldc           #17  // String GET
  39: invokevirtual #19  // Method java/lang/String.equals:(Ljava/lang/Object;)Z
```

### 5.4 Runnable: data-oriented programming end to end

<!-- run: -->
```java
import java.util.List;

public class ExprEvaluator {
    sealed interface Expr permits Num, Neg, Add, Mul, Var {}
    record Num(double value) implements Expr {}
    record Neg(Expr e) implements Expr {}
    record Add(Expr l, Expr r) implements Expr {}
    record Mul(Expr l, Expr r) implements Expr {}
    record Var(String name) implements Expr {}

    static double eval(Expr e, java.util.Map<String, Double> env) {
        return switch (e) {                                          // exhaustive: no default
            case Num(var v) -> v;
            case Neg(var inner) -> -eval(inner, env);
            case Add(var l, var r) -> eval(l, env) + eval(r, env);
            case Mul(var l, var r) -> eval(l, env) * eval(r, env);
            case Var(var name) -> env.getOrDefault(name, 0.0);
        };
    }

    /** Algebraic simplification with NESTED record patterns and guards. */
    static Expr simplify(Expr e) {
        return switch (e) {
            case Add(Num(var a), Num(var b)) -> new Num(a + b);              // constant folding
            case Mul(Num(var z), _) when z == 0 -> new Num(0);               // 0 * x
            case Mul(_, Num(var z)) when z == 0 -> new Num(0);               // x * 0
            case Mul(Num(var one), var x) when one == 1 -> simplify(x);      // 1 * x
            case Neg(Neg(var x)) -> simplify(x);                             // --x
            case Add(var l, var r) -> new Add(simplify(l), simplify(r));
            case Mul(var l, var r) -> new Mul(simplify(l), simplify(r));
            case Neg(var x) -> new Neg(simplify(x));
            case Num n -> n;
            case Var v -> v;
        };
    }

    static String describe(Object o) {
        return switch (o) {
            case null -> "null!";
            case Integer i when i > 100 -> "big int " + i;
            case Integer i -> "int " + i;
            case String s when s.isBlank() -> "blank string";
            case String s -> "string of " + s.length();
            case List<?> l when l.isEmpty() -> "empty list";
            case List<?> l -> "list, first=" + l.getFirst();
            default -> "other " + o.getClass().getSimpleName();
        };
    }

    public static void main(String[] args) {
        Expr e = new Add(new Mul(new Num(1), new Var("x")), new Neg(new Neg(new Add(new Num(2), new Num(3)))));
        System.out.println(simplify(e));
        System.out.println(eval(e, java.util.Map.of("x", 10.0)));
        for (Object o : new Object[] {null, 7, 700, " ", "abc", List.of(), List.of(9), 3.14})
            System.out.print(describe(o) + " | ");
        System.out.println();
    }
}
```

Output (verified):

```
Add[l=Var[name=x], r=Num[value=5.0]]
15.0
null! | int 7 | big int 700 | blank string | string of 3 | empty list | list, first=9 | other Double |
```

### 5.5 Compile errors you must recognize 🎓

Dominance: a broader type pattern before a narrower one.

<!-- run: compilefail expect="dominated" -->
```java
public class Dominance {
    static String f(Object o) {
        return switch (o) {
            case CharSequence cs -> "chars";
            case String s -> "string";          // error: this case label is dominated by a preceding case label
            default -> "other";
        };
    }
}
```

Non-exhaustive switch over a sealed type.

<!-- run: compilefail expect="does not cover all possible input values" -->
```java
public class NotExhaustive {
    sealed interface S permits A, B {}
    record A() implements S {}
    record B() implements S {}
    static int f(S s) {
        return switch (s) {
            case A a -> 1;                       // error: the switch expression does not cover all possible input values
        };
    }
}
```

A pattern variable is not in scope across `||`.

<!-- run: compilefail expect="cannot find symbol" -->
```java
public class PatternScope {
    static boolean f(Object o) {
        return o instanceof String s || s.isEmpty();   // error: cannot find symbol s
    }
}
```

The harness confirms each of these fails to compile with the quoted messages.

### 5.6 Primitive patterns (preview in JDK 25–27: JEPs 507 → 530 → 532) 🧊

<!-- run: -->
```java
public class PrimitivePatterns {
    static String bucket(int status) {
        return switch (status) {                    // primitive type patterns with guards (preview)
            case 200 -> "OK";
            case int s when s >= 500 -> "server error " + s;
            case int s when s >= 400 -> "client error " + s;
            case int s -> "other " + s;
        };
    }

    public static void main(String[] args) {
        System.out.println(bucket(200) + ", " + bucket(404) + ", " + bucket(503) + ", " + bucket(302));
        long big = 3_000_000_000L, small = 42L;
        System.out.println((big instanceof int i ? "fits: " + i : "does not fit in int")
            + " | " + (small instanceof int j ? "fits: " + j : "does not fit"));   // safe narrowing test
    }
}
```

Output (verified with `--enable-preview --source 25`): `OK, client error 404, server error 503, other 302` and `does not fit in int | fits: 42`.

`x instanceof int i` tests whether the conversion is **exact** (no loss of information), which replaces hand-written range checks. Preview APIs can change; don't ship them in production code.

---

## 6. Enums internals ⚡🎓

* `enum Color { RED, GREEN }` compiles to `final class Color extends Enum<Color>` with `public static final Color RED, GREEN`, a private `$VALUES` array and a private constructor. **`values()` clones `$VALUES` every call**, so cache it in hot code.
* `valueOf(String)` uses a lazily built name→constant map (`Class.enumConstantDirectory`) and throws `IllegalArgumentException` for unknown names.
* Constants with bodies (`RED { … }`) are **anonymous subclasses**: `RED.getClass() != Color.class`, so use `getDeclaringClass()`.
* `ordinal()` is the declaration position. Never persist it (reordering breaks data). Persist `name()`, or an explicit code field.
* Enums are the best singleton (serialization-safe, reflection-safe: `Constructor.newInstance` refuses enums).
* `switch` on enums historically compiled through a synthetic `$SwitchMap$` int array. Pattern switches use `SwitchBootstraps.enumSwitch`.

<!-- run: -->
```java
public class EnumInternals {
    enum Op {
        ADD { int apply(int a, int b) { return a + b; } },
        MUL { int apply(int a, int b) { return a * b; } };
        abstract int apply(int a, int b);
    }

    public static void main(String[] args) throws Exception {
        System.out.println(Op.ADD.apply(2, 3) + " " + Op.MUL.apply(2, 3));
        System.out.println("values() same array each call? " + (Op.values() == Op.values()));
        System.out.println("ADD.getClass()=" + Op.ADD.getClass().getName() + ", getDeclaringClass()=" + Op.ADD.getDeclaringClass().getSimpleName());
        try { Op.valueOf("DIV"); } catch (IllegalArgumentException e) { System.out.println(e.getMessage()); }
        try {
            var ctor = Op.class.getDeclaredConstructors()[0];
            ctor.setAccessible(true);
            ctor.newInstance("HACK", 99);
        } catch (Exception e) { System.out.println("reflection: " + e.getClass().getSimpleName()); }
    }
}
```

Output (verified):

```
5 6
values() same array each call? false
ADD.getClass()=EnumInternals$Op$1, getDeclaringClass()=Op
No enum constant EnumInternals.Op.DIV
reflection: IllegalArgumentException
```

---

## 7. Flexible constructor bodies (JDK 25, JEP 513) 🔥🎓

Statements may now appear **before** `super(…)`/`this(…)`, in the *prologue*. They cannot read `this` (no instance method calls, no reading fields), but they **may assign fields** of the class being constructed. This fixes two long-standing problems: validating arguments before an expensive superclass constructor, and **the superclass constructor calling an overridden method that reads a not-yet-initialized subclass field**.

<!-- run: -->
```java
public class FlexibleConstructors {
    static abstract class Component {
        Component() { System.out.println("init: " + describe()); }      // calls an overridable method (classic hazard)
        abstract String describe();
    }

    static class OldStyle extends Component {
        private final String name;
        OldStyle(String name) { super(); this.name = name; }           // field assigned AFTER super() runs describe()
        String describe() { return "OldStyle(" + name + ")"; }
    }

    static class NewStyle extends Component {
        private final String name;
        NewStyle(String name) {
            if (name == null || name.isBlank()) throw new IllegalArgumentException("name required");  // validate first
            this.name = name.strip();                                   // early assignment (JDK 25)
            super();                                                    // super sees the initialized field
        }
        String describe() { return "NewStyle(" + name + ")"; }
    }

    public static void main(String[] args) {
        new OldStyle("db-pool");
        new NewStyle("  db-pool ");
        try { new NewStyle(" "); } catch (IllegalArgumentException e) { System.out.println("rejected before super(): " + e.getMessage()); }
    }
}
```

Output (verified):

```
init: OldStyle(null)
init: NewStyle(db-pool)
rejected before super(): name required
```

---

## 8. Production failure modes & diagnostics

| Failure | Signature | Fix |
|---|---|---|
| `==` on strings works in tests, fails in prod | Literals are interned, runtime strings (from JSON, DB) aren't | `equals`; static analysis (Error Prone `StringEquality`) |
| Locale bugs | `toUpperCase()` breaks under `tr_TR`, number parsing breaks under `de_DE` | `Locale.ROOT` for machine strings |
| ReDoS | CPU pinned in `java.util.regex.Pattern$Loop.match`/`$GroupTail` frames | Possessive or atomic patterns, input length limits, timeouts |
| String concat in loops | Allocation flame graph dominated by `StringConcatHelper`/`Arrays.copyOf` | `StringBuilder`, joining collectors |
| `intern()` on user input | StringTable growth; long GC root scanning | Bounded canonicalizer; G1 string dedup |
| Record with array/mutable component | Equality and hash surprises; external mutation | `List.copyOf`, `Arrays.equals` in a custom `equals`, or wrap arrays |
| `MatchException` at run time | A sealed hierarchy grew in a library; client not recompiled | Recompile clients; version sealed APIs carefully (adding a permitted subtype is a breaking change) |
| `NullPointerException` from `switch` | A null selector without `case null` | Add `case null` or validate upstream |
| Persisted `ordinal()` corrupts data after an enum reorder | — | Persist names or explicit codes |
| Superclass constructor sees `null` subclass fields | Overridable call in a constructor | JDK 25 early assignment, or avoid overridable calls in constructors |

---

## 9. Interview & certification Q&A

<details><summary><b>Q1. 🎓 What does this print? <code>String a="hi"; String b="h"+"i"; String c="h"; String d=c+"i"; System.out.print((a==b)+" "+(a==d)+" "+(a==d.intern()));</code></b></summary>

`true false true`. `"h"+"i"` is a constant expression folded at compile time to the same literal. `c+"i"` uses a non-final variable, so it is computed at run time into a new object. `intern()` returns the pooled instance.
</details>

<details><summary><b>Q2. 🔥 Why is `"a" + b + c` fine in Java 9+ but `s += x` in a loop bad?</b></summary>

A single concatenation expression compiles to one `invokedynamic` linked by `StringConcatFactory`, which pre-computes the exact size and coder, allocates once and copies once. A loop creates a new String per iteration and copies the growing prefix each time, which is O(n²) time and garbage. Use a `StringBuilder` (pre-sized if possible) for loops.
</details>

<details><summary><b>Q3. 🎓 Which are legal inside a record declaration? (a) an instance field, (b) a static field, (c) an instance initializer block, (d) a compact constructor that assigns `this.x = x`, (e) overriding an accessor as `public`, (f) `extends Object`</b></summary>

Legal: (b) and (e). Illegal: (a) no extra instance fields; (c) no instance initializers; (d) in a compact constructor you assign the *parameter* (`x = …`), not `this.x`, because fields are assigned after the body and assigning them is a compile error; (f) records cannot have an `extends` clause.
</details>

<details><summary><b>Q4. 🔥 What are sealed types for, and what's the rule for permitted subclasses?</b></summary>

They restrict which classes may extend or implement a type, giving a closed hierarchy that enables exhaustive pattern matching and models domain alternatives (sum types). Each permitted subclass must be `final`, `sealed` or `non-sealed`, must directly extend the sealed type, and must live in the same module (or the same package in the unnamed module). `permits` can be omitted when the subclasses are in the same file.
</details>

<details><summary><b>Q5. 🎓 When is a `switch` required to be exhaustive?</b></summary>

Always for switch **expressions**. For switch **statements** when they use pattern labels or `case null` (otherwise old-style statements over enums/strings/ints need not be exhaustive). Exhaustiveness is satisfied by a `default`, an unconditional pattern, all enum constants, or all permitted subtypes of a sealed type (recursively for record patterns).
</details>

<details><summary><b>Q6. ⚡ When is `MatchException` thrown?</b></summary>

When an exhaustive switch (pattern switch, or a switch expression over an enum or sealed type) meets a value none of its cases match at run time, which is only possible through separate compilation: a new enum constant or permitted subtype added after the switch was compiled. It is also thrown when a record pattern's accessor throws (wrapping the exception).
</details>

<details><summary><b>Q7. 🎓 What does `"a,b,,c,,".split(",").length` return?</b></summary>

4: `["a","b","","c"]`. Trailing empty strings are removed (an empty string in the middle is kept). `split(",", -1)` would give 6.
</details>

<details><summary><b>Q8. 🔥 Explain catastrophic backtracking and two mitigations.</b></summary>

Backtracking regex engines try all ways of splitting input among nested or overlapping quantifiers when a match fails, giving exponential time (for example `(a+)+b` on `"aaaa…"`). Mitigations: possessive quantifiers or atomic groups (`a++`, `(?>…)`) to forbid backtracking into a run; restructure the pattern to avoid ambiguity; bound input length; enforce timeouts or use a linear-time engine (RE2/J) for untrusted patterns or input.
</details>

<details><summary><b>Q9. 🎓 In a pattern switch, why is `case CharSequence cs` before `case String s` a compile error, but `case String s when s.isEmpty()` before `case String s` is fine?</b></summary>

`CharSequence cs` matches every `String`, so the later label is unreachable (dominated), which is an error. A guarded pattern doesn't dominate an unguarded pattern of the same type, because the guard may be false, so the later label is still reachable.
</details>

<details><summary><b>Q10. ⚡ What problem do flexible constructor bodies (JDK 25) solve? What can't the prologue do?</b></summary>

They allow argument validation or computation before calling `super(…)`/`this(…)`, and early assignment of the class's own fields, so a superclass constructor that calls an overridden method sees initialized subclass state. The prologue cannot reference `this` (except to assign fields), call instance methods, or read instance fields.
</details>

<details><summary><b>Q11. 🎓 What is the output? <code>enum E { A, B } … System.out.print(E.valueOf("A").ordinal() + "" + E.values().length + E.B.compareTo(E.A));</code></b></summary>

`021`. Evaluation is left to right: `0 + ""` gives `"0"` (String context from then on), `+ 2` gives `"02"` (`values().length`), and `+ 1` gives `"021"`, because `B.compareTo(A)` returns the ordinal difference 1 − 0 = 1.
</details>

<details><summary><b>Q12. 🔥 Why are `final` fields important for thread safety even without `volatile`?</b></summary>

JLS §17.5 guarantees that once a constructor completes, any thread that obtains a reference to the object sees the correctly initialized values of its `final` fields (and of objects reachable through them, as of the freeze), even if the reference was published without synchronization. Provided `this` didn't escape during construction, immutable objects can therefore be shared freely.
</details>

---

## 10. Further reading

* JEP 254, 280, 378, 395, 409, 440, 441, 456, 507/530/532, 513.
* Brian Goetz, "Data-Oriented Programming in Java" (InfoQ, 2022), the design rationale for records + sealed + patterns.
* Aleksey Shipilëv, "JDK 9 Compact Strings" and "Indify String Concat" performance notes.
* OWASP ReDoS: <https://owasp.org/www-community/attacks/Regular_expression_Denial_of_Service_-_ReDoS>
