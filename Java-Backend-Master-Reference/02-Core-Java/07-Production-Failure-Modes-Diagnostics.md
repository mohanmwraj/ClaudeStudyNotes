# 2.7 · Pillar 2 — Production Failure Modes & Diagnostic Checklist (Core Java)

> This file consolidates the failure tables from [2.1](01-Collections-Internals.md)–[2.6](06-Date-Time-Localization-Numerics.md) into incident playbooks plus a prevention toolkit (static analysis, tests, runtime signals).
> The war stories are composite and anonymized, but each failure mechanism is demonstrated by a verified program in this pillar (linked).

---

## 1. Incident playbooks

### 🔥 Story 1 — "Everything expired on December 29"

* **Symptom:** in the last week of December, API tokens and report file names show next year's date. Partners reject files.
* **Root cause:** `DateTimeFormatter.ofPattern("YYYY-MM-dd")`, where `YYYY` is the **week-based year** ([demo](06-Date-Time-Localization-Numerics.md#12-formatting-and-parsing-the-yyyy-incident-and-friends-)).
* **Fix:** `uuuu-MM-dd` (or `yyyy`). Add Error Prone's `MisusedWeekYear` check, plus a unit test that formats `2025-12-29`.

### 🔥 Story 2 — "Turkish customers can't log in"

* **Symptom:** `IllegalArgumentException: No enum constant Role.TİTLE` only for users with `tr-TR` browsers, after a change that applied `Locale.setDefault(userLocale)` per request.
* **Root cause:** `role.toUpperCase()` with the default locale: `i` → `İ` (dotted capital I) ([demo](02-Strings-Records-Sealed-Pattern-Matching.md#14-api-facts--traps-)).
* **Fix:** `toUpperCase(Locale.ROOT)` for identifiers, and never mutate the JVM-wide default locale per request (it's global state shared by all threads).

### 🔥 Story 3 — "Cache shows the wrong customer's data"

* **Symptom:** rare cross-tenant data in responses, impossible to reproduce locally.
* **Root cause:** a singleton service memoized results in a plain `HashMap` (and once in a `static SimpleDateFormat`). Concurrent writes corrupted bins and lost updates. In the date case, the shared formatter's internal `Calendar` mixed values between threads.
* **Fix:** `ConcurrentHashMap` (or Caffeine) and `DateTimeFormatter`. Add a load test with concurrent requests and assertions on tenant isolation.

### 🔥 Story 4 — "Thread pile-up behind one slow call"

* **Symptom:** p99 latency explodes, and thread dumps show 200 threads `BLOCKED (on object monitor)` at `ConcurrentHashMap.computeIfAbsent`.
* **Root cause:** `map.computeIfAbsent(key, k -> remoteService.fetch(k))`. The remote call ran while holding the bin lock, so every request for keys in that bin waited ([2.1 §9.3](01-Collections-Internals.md#93-computemerge-semantics-and-the-recursion-trap-)).
* **Fix:** Caffeine `AsyncLoadingCache` (one future per key, no lock held during the load), or load outside the map plus `putIfAbsent`.

### 🔥 Story 5 — "Unrelated endpoints got slow when reporting ran"

* **Symptom:** whenever the reporting endpoint runs, unrelated `CompletableFuture`-based endpoints slow down by hundreds of ms.
* **Root cause:** reporting used `parallelStream()` with JDBC calls inside, which blocked `ForkJoinPool.commonPool()`. The `CompletableFuture.supplyAsync` calls elsewhere use the same pool ([measured: 367 ms delay](03-Lambdas-Streams-Collectors-Gatherers.md#31-runnable-measured-degradation-scenarios)).
* **Fix:** a sequential stream plus a dedicated bounded executor, or virtual threads with a concurrency limit (`Gatherers.mapConcurrent`, a `Semaphore`). Never block in the commonPool.

### ⚡ Story 6 — "Validation endpoint at 100% CPU"

* **Symptom:** one pod pinned at 100% CPU. Flame graph: `java.util.regex.Pattern$Loop.match`.
* **Root cause:** an input-validation regex with a **bounded repetition of a variable-width group** (`(?:[a-z0-9]+[._-]?){2,64}@…`) fed a crafted 40-char string. JDK 9+ memoization does not cover bounded repetitions ([measured exponential growth](02-Strings-Records-Sealed-Pattern-Matching.md#15-regex-compile-once-beware-catastrophic-backtracking-)).
* **Fix:** a length check before matching, unambiguous/possessive patterns, and a linear-time engine (RE2/J) for anything user-supplied.

### ⚡ Story 7 — "Works for the first 127 customers"

* **Symptom:** a feature flag stopped matching for customer IDs ≥ 128.
* **Root cause:** `if (customer.getTierId() == config.getTierId())` compared two `Integer`s. Reference equality works only inside the `Integer.valueOf` cache (−128..127) ([demo](05-Generics-Exceptions-Object-Model.md#4-primitives-boxing-and-arithmetic-traps-)).
* **Fix:** `Objects.equals` or primitives. Error Prone `BoxedPrimitiveEquality`/`ReferenceEquality`.

### ⚡ Story 8 — "Customers charged twice"

* **Symptom:** deduplication by amount and currency failed for some payments.
* **Root cause:** a `HashSet<BigDecimal>` received `10.0` from one service and `10.00` from another, and `equals` includes the scale ([demo](01-Collections-Internals.md#28-equalshashcode-contract-failures-), [money rules](06-Date-Time-Localization-Numerics.md#3-numerics-bigdecimal-money-and-exactness-)).
* **Fix:** normalize to `long` minor units at the boundary, or `setScale(currency.getDefaultFractionDigits())`.

### ⚡ Story 9 — "Parsing broke after the JDK upgrade"

* **Symptom:** after moving from JDK 17 to 21, imports of a partner CSV fail with `DateTimeParseException` on `"9:30 AM"`.
* **Root cause:** the parser used `DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.US)`. CLDR 42 (JDK 20+) expects U+202F before AM/PM ([demo](06-Date-Time-Localization-Numerics.md#12-formatting-and-parsing-the-yyyy-incident-and-friends-)).
* **Fix:** an explicit pattern `ofPattern("h:mm a", Locale.US)` for machine input, plus golden-file tests for all formats exchanged with partners.

### ⚡ Story 10 — "`MatchException` after a minor library bump"

* **Symptom:** `java.lang.MatchException` in a reporting job after upgrading the shared `payments-model` JAR, with no code change in the job.
* **Root cause:** the library added `record Refunded(…) implements PaymentResult` to a **sealed** interface. The job's exhaustive `switch` was compiled against the old version ([2.2 §5.3](02-Strings-Records-Sealed-Pattern-Matching.md#53-how-its-compiled-typeswitch--matchexception)).
* **Fix:** recompile consumers. Treat adding a permitted subtype as a **breaking API change** (major version), and run a CI compatibility check against dependents.

### ⚡ Story 11 — "CPU in `fillInStackTrace`"

* **Symptom:** a 20% CPU regression. async-profiler shows `Throwable.fillInStackTrace` → `StackWalker` frames.
* **Root cause:** a refactor turned "item not found in cache" into `throw new NotFoundException()`, caught one layer up, at 30k req/s with stacks ~150 frames deep ([cost measured](05-Generics-Exceptions-Object-Model.md#22-the-cost-of-exceptions-measured)).
* **Fix:** `Optional` return, or a lightweight exception without a stack trace for that internal signal.

### ⚡ Story 12 — "Memory leak from a callback"

* **Symptom:** the old generation grows by one large `ReportContext` (50 MB) per report run.
* **Root cause:** an anonymous `ProgressListener` registered with a static event bus captured `this` (`this$0`) and was never unregistered ([demo](05-Generics-Exceptions-Object-Model.md#34-nested-classes-and-the-hidden-outer-reference-)).
* **Fix:** unregister in `finally`, or use weak listeners, or a static nested listener with only the data it needs.

### ⚡ Story 13 — "`UnsupportedOperationException` deep inside a batch job"

* **Symptom:** a batch job fails at `list.add` after a "harmless" refactor that changed `.collect(Collectors.toList())` to `.toList()`.
* **Root cause:** `Stream.toList()` returns an **unmodifiable** list; `Collectors.toList()` returned an `ArrayList` in practice ([demo](01-Collections-Internals.md#6-immutable-and-unmodifiable-collections-)).
* **Fix:** `new ArrayList<>(stream.toList())` where mutation is intended, or `Collectors.toCollection(ArrayList::new)`.

### 🧊 Story 14 — "Reflection hot path"

* **Symptom:** a custom mapper uses 12% of CPU.
* **Root cause:** `getClass().getDeclaredFields()` plus `setAccessible(true)` on every object mapped ([cost: 28 ns per lookup vs ~1 ns cached](04-Reflection-MethodHandles-VarHandles-Proxies-Bytecode.md#21-runnable-what-an-invocation-costs)).
* **Fix:** cache per-class accessors (`MethodHandle`s, or `LambdaMetafactory` functions) in a `ClassValue`.

---

## 2. Prevention toolkit

### 2.1 Static analysis rules that would have caught these

| Tool / rule | Catches |
|---|---|
| Error Prone `MisusedWeekYear`, `JavaTimeDefaultTimeZone`, `JavaLocalDateTimeGetNano` | Story 1; default-zone `now()` |
| Error Prone `StringCaseLocaleUsage`; Forbidden-APIs (`toUpperCase()` without a locale) | Story 2 |
| Error Prone `ReferenceEquality`, `BoxedPrimitiveEquality`, `StringEquality` | Story 7, `==` on strings |
| Error Prone `ModifiedButNotUsed`, `ReturnValueIgnored` (e.g. `date.plusDays(1);`) | Immutable API misuse |
| Error Prone `FutureReturnValueIgnored`, `CompletableFutureNoExecutor`-style rules (Pillar 3) | Lost async errors, commonPool use |
| SpotBugs `STCAL_STATIC_SIMPLE_DATE_FORMAT_INSTANCE`, `DMI_RANDOM_USED_ONLY_ONCE`, `SIC_INNER_SHOULD_BE_STATIC` | Story 3, Story 12 |
| SonarQube "BigDecimal(double)", "Regex ReDoS" (S5852), "Parallel streams" | Money, Story 6 |
| `javac -Xlint:all -Werror` (unchecked, rawtypes, finally, deprecation) | Heap pollution, `return` in `finally` |
| ArchUnit ([8.4](../08-Observability-Security-Testing/04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md)): "no `parallelStream()` in `..web..`", "no `java.util.Date`" | Stories 5 and 1 |

### 2.2 Tests that pay for themselves

* **Time:** inject a `Clock`. Test DST boundary days for every zone you support, plus year-end (Dec 28–Jan 3) formatting.
* **Locale:** run the suite under `-Duser.language=tr -Duser.country=TR` and `de_DE` at least once in CI.
* **Concurrency:** stress shared mutable structures with concurrent tests (jcstress for low-level code, Pillar 3).
* **Golden files:** for every externally exchanged format (CSV, JSON dates, number formats).
* **Library compatibility:** compile dependents against new versions of shared model JARs (sealed hierarchies, enums).

### 2.3 Runtime signals

| Signal | Tool | Indicates |
|---|---|---|
| `Throwable.fillInStackTrace` in CPU profiles | async-profiler, JFR `jdk.ExecutionSample` | Exceptions as control flow |
| JFR `jdk.ExceptionStatistics` (periodic counts) and `jdk.JavaExceptionThrow` (on by default in JDK 25, throttled to 100 events/s with stack traces) | JFR | Exception rate and throw sites |
| `java.util.regex.Pattern$*` hot | async-profiler | Regex cost or ReDoS |
| `HashMap$Node`, `Integer`, `String` dominate histograms | `jcmd GC.class_histogram` | Boxed or oversized collections |
| `ForkJoinPool.commonPool-worker-*` blocked in I/O | Thread dumps | Parallel stream misuse |
| Many `BLOCKED` threads at `ConcurrentHashMap` frames | Thread dumps | Long `compute*` functions |
| `Class.getDeclared*` in profiles | async-profiler | Uncached reflection |

---

## 3. Checklist for code review (Core Java)

- [ ] No `==` on boxed types or strings; `equals`/`Objects.equals` used.
- [ ] `toUpperCase/toLowerCase/format/parse` of machine data use `Locale.ROOT` or explicit patterns.
- [ ] Date patterns use `uuuu`/`yyyy` (never `YYYY`) and explicit zones or clocks.
- [ ] Money uses `long` minor units or `BigDecimal` with explicit scale and rounding; no `new BigDecimal(double)`.
- [ ] Shared mutable state uses concurrent collections; no `static SimpleDateFormat`.
- [ ] `compute*`/`merge` functions are short and side-effect free.
- [ ] No `parallelStream()` on request paths; no blocking calls in parallel streams.
- [ ] `Stream.toList()` results not mutated; `Collectors.toMap` has a merge function where keys can collide.
- [ ] Exceptions: no control flow by exception in hot paths; no `return` in `finally`; causes chained.
- [ ] Records for value types; defensive copies of collection components.
- [ ] Sealed hierarchies: exhaustive switches without `default` (so the compiler flags new subtypes).
- [ ] Regexes reviewed for ambiguity; input length bounded before matching.
- [ ] Reflection results cached; no per-call `getDeclaredFields()`.
- [ ] Inner and anonymous listeners unregistered, or made static.
