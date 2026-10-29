# The 7-Layer Fault Scan: Correctness, Concurrency, Resources, I/O, Compatibility, Security, Operability

> **What this file is.** A repeatable procedure for finding Sev-1 production killers in a diff before you spend a minute on style. It covers seven layers, each with its invariant class, its instant tells in Java and C++, the questions that expose it, and a runnable demonstration. It closes with the **complete line-by-line answer key for PR-00** (introduced in [01 §5](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#5-the-pr-00-exhibit)), with probe evidence, the refactored code, and the test results.

| Listing | Lang | What it demonstrates | Output |
|---|---|---|---|
| `FaultScan.java` | Java 21 | 16 defects across the 7 layers, each next to its fix (boxed `==`, `BigDecimal` equality, stream-sum overflow, double money, check-then-act stampede, lock-order deadlock, permit leak on throw, `ThreadLocal` tenant leak, missing deadline, retry storm, ordinal persistence, strict enum reader, path traversal, tenant-less cache key, N+1, unbounded map) | Output (verified); 2 lines are one measured run |
| `fault_scan.cpp` | C++23 | 14 defects: `accumulate` init truncation, `uint32` size wrap, `size_t` underflow, signed-overflow UB, TOCTOU across two lock scopes, leak on throw, lock left held on throw, iterator invalidation, lock held across blocking sends, struct-as-wire padding/offsets, `long` width, byte order, 16-bit length truncation, unbounded queue | Output (verified) on GCC 16.2 and Clang 21.1; 3 lines are one measured run |
| `Pr00Probes.java` + fixed `RefundService` | Java 21 | The 9 PR-00 defects exercised in production shape: two pods, timeout-after-commit, failover-after-payout, deployed v1 consumer | Output (verified); P5 is one measured run |

**Verification.** Java: JDK 25.0.4.1, `javac --release 21 -Xlint:all -Werror`; JUnit Platform console 1.13.4. C++: GCC 16.2 (MinGW-w64) and Clang 21.1 (Zig 0.16), `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`, both compilers. Every listing and output in this file is spliced verbatim from the build; the gate re-extracts the listings and re-runs them ([README](../README.md#gate)). All C++ demos stay inside defined behavior: where the real bug is undefined behavior (an overflowing `memcpy`, a dangling read), the program prints the decision the buggy code would make instead of executing it.

---

## 0. Orientation

### 0.1 Why layers

Under time pressure, unstructured review collapses into whatever the reviewer happens to know best: the concurrency expert finds the race and misses the IDOR; the security person finds the IDOR and misses the renamed field. A fixed scan order gives three guarantees:

1. **Coverage you can state.** "I've checked all seven layers; layer 5 is clean because nothing serialized changed" is a sentence an interviewer can award.
2. **Severity-first ordering.** Each layer has a short list of patterns that are almost always Sev-1 when present. You check those first in every layer before going deep in any.
3. **A place to put every suspicion.** When you notice something outside the layer you're scanning, note it under its layer and keep going. That stops tunnel vision.

### 0.2 The seven layers

| # | Layer | The invariant class it protects | The question that opens it |
|---|---|---|---|
| L1 | **Correctness and invariants** | Values are what the code thinks they are: arithmetic, equality, units, nullability, time | "What's the largest, smallest, emptiest, oddest value this sees?" |
| L2 | **Concurrency and atomicity** | Decisions are still true when acted on: check-then-act, lock order, visibility | "What if two of these run at once, in one process *and* across processes?" |
| L3 | **Resource lifecycle and failure paths** | Everything acquired is released, and every partial failure leaves a recoverable state | "What if this line throws? What if the process dies right after it?" |
| L4 | **I/O and distributed boundaries** | Remote calls are bounded, idempotent, and their outcomes are classified honestly | "What if this call hangs, fails, or succeeds and the answer is lost?" |
| L5 | **Data and wire compatibility** | Every deployed reader can read every writer's data, in both rollout directions | "Who reads this today, and what version are they running?" |
| L6 | **Security and trust boundaries** | Every input is authenticated, authorized for *this object*, and validated | "Who can call this, and what stops them from naming someone else's thing?" |
| L7 | **Operability and scale** | The system stays observable, bounded and affordable at 100× | "What grows with traffic, tenants, or time, and what bounds it?" |

### 0.3 Habits that cap you, and what replaces them

| Habit | L7 replacement |
|---|---|
| Scan for "bugs" in general | Scan for *violated invariants* per layer; say which invariant |
| Start at line 1 | Start at the hunk that mutates state or crosses a process boundary |
| Concurrency means threads | Concurrency means threads, pods, retries, replays, consumers and humans pressing a button twice |
| An exception means failure | An exception from a remote call means *unknown*, unless the contract says otherwise |
| Compatibility means the API | Compatibility means every serialized byte: events, DB columns, caches, enum ordinals, config files, struct layouts |
| Security means injection | Security mostly means authorization: whose object is this? |
| Performance means Big-O | Operability means bounds: queues, caches, labels, retries, connections, fan-out |

---

## 1. First principles

### 1.1 Every Sev-1 is a violated invariant at a boundary

Production code is correct in the author's mental model. Outages come from the places where the model is narrower than reality, and those places are boundaries:

| Boundary | What the author's model assumes | What reality does |
|---|---|---|
| **Time** (L2) | Nothing changes between my check and my act | Another thread, pod or retry acts in between |
| **Failure** (L3) | Each line completes | Any line can throw; the process can die between any two lines |
| **Process** (L4) | A call returns success or failure | It returns success, failure, *or nothing*, and "nothing" may mean success |
| **Version** (L5) | Everyone runs my code | Old readers, new writers, rollbacks and replays coexist for weeks |
| **Trust** (L6) | Callers are who they say and ask for their own things | Callers name arbitrary IDs, paths and sizes |
| **Scale** (L7) | The numbers in my test | Unbounded keys, values, tenants and retries |
| **Representation** (L1) | `int` holds it; `==` compares values; `0.1` is 0.1 | Wraparound, identity comparison, binary fractions |

The scan is just a disciplined walk across these boundaries.

### 1.2 Severity is impact × likelihood × detectability × reversibility

| Factor | Raises severity | Lowers severity |
|---|---|---|
| **Impact** | Money, PII, security, data loss, deployed-consumer breakage | Latency on a non-critical path |
| **Likelihood** | Triggered by normal traffic, retries or deploys | Needs an exotic interleaving *and* a rare failure |
| **Detectability** | **Silent** (wrong numbers, missing rows, zeroed fields) | Loud (crash, 5xx, alarm) |
| **Reversibility** | Money moved, data overwritten, emails sent | Retry fixes it; data recomputable |

**Silent beats loud.** A crash pages someone within minutes. A ledger that books every refund as 0 (PR-00 F8) can run for weeks and needs a forensic backfill. When two defects compete for your last five minutes, the silent one wins.

### 1.3 Spend human attention where tools are blind

Tools have commoditized a large class of review findings. An L7 knows which ones and doesn't spend interview minutes re-deriving them, beyond naming the tool that should have caught them.

| Usually caught by tools (if configured) | Tool | Usually invisible to tools |
|---|---|---|
| Boxed `==`, unused results, null dereference patterns | Error Prone, SpotBugs, IDE inspections (the IDE flagged `FaultScan.java`'s deliberate boxed `==` while this file was written) | Whether a check-then-act spans **processes** |
| Format/naming/import order | Formatters, Checkstyle, clang-format | Whether an exception means **unknown outcome** under the dependency's contract |
| Signed/unsigned mixing, narrowing, shadowing | `-Wall -Wextra -Wconversion`, clang-tidy | Whether a renamed field has a **deployed reader** |
| Use-after-free, overflow, data races (at runtime, on exercised paths) | ASan, UBSan, TSan | Whether `merchantId` is **compared** with the object's owner |
| Known-vulnerable dependencies, some injection | SCA, Semgrep, CodeQL | Whether a metric label is **unbounded in production** |
| Schema compatibility | Schema-registry compatibility checks (if wired into CI) | Whether a lock is held across **I/O you don't control** |

The right-hand column is the round. Every PR simulation in this KB hides most of its Sev-1s there.

### 1.4 Real outages, mapped to layers

Four widely studied public incidents from 2024–2025, each traced to the review question that targets its class. The quotes are from the companies' own post-incident reports.

**AWS us-east-1, October 19–20, 2025: L2 race, L3 cleanup.** DynamoDB's DNS automation has a Planner that produces plans and three independent Enactors that apply them. One Enactor was "experiencing unusually high delays." It applied a much older plan over a newer one, because its check that the plan was newer "was stale by this time due to the unusually high delays in Enactor processing." The other Enactor's clean-up then "identifies plans that are significantly older than the one it just applied and deletes them." That deleted the now-active plan, and "all IP addresses for the regional endpoint were immediately removed." *Review question (L2): "This checks a version, then acts after a slow operation. What enforces that the check is still true at the act?"* The textbook answer is a compare-and-set or a fencing token on the write, not a check before it.

**Cloudflare, November 18, 2025: L5/L1 internal data treated as trusted.** "A change in our underlying ClickHouse query behaviour," triggered by a database permissions change, filled a generated Bot Management feature file with duplicate feature rows, making it much larger than usual. The consuming proxy had a feature limit ("Currently that limit is set to 200, well above our current use of ~60 features") because "we preallocate memory for the features." The doubled file crossed it, and the thread "panicked: called Result::unwrap() on an Err value." First remediation item: "Hardening ingestion of Cloudflare-generated configuration files in the same way we would for user-generated input." *Review question (L5): "This file or event is produced by another system. What happens when it arrives larger, duplicated, or with new fields, and does exceeding a limit fail closed for one request or panic the process?"*

**Google Cloud, June 12, 2025: L1 null, L3 unguarded path, L4 herd.** A Service Control feature added on May 29 "did not have appropriate error handling nor was it feature flag protected." Policy data "contained unintended blank fields," and "the null pointer caused the binary to crash." Then, "as Service Control tasks restarted, it created a herd effect" in us-central1, because it "did not have the appropriate randomized exponential backoff." *Review questions: (L1) "What does this do when the field is empty?" (L3) "Is this new code path behind a flag that defaults off?" (L4) "When every instance restarts at once, what spreads out their retries?"*

**CrowdStrike Channel File 291, July 19, 2024: L1/L5 count mismatch.** Per CrowdStrike's root-cause analysis, a new template type defined 21 input parameter fields, but the integration code that invoked the content interpreter supplied only 20 input values. Tests had used wildcard matching for the 21st input, so the out-of-bounds read stayed latent until content with a non-wildcard 21st criterion shipped. Remediation included input-field count validation and bounds checking in the content interpreter. *Review question (L1/L5): "Where is the count of fields in this data checked against the count the code supplies, and is the 'never happens in tests' case actually reachable?"*

None of these was an exotic algorithmic bug. Each is a one-line question from this scan, asked at the right boundary.

### 1.5 Instant tells: the Minute-2 radar

These patterns are not always bugs, but each one *always* earns a second look. They are greppable in a diff:

| Pattern (Java) | Pattern (C/C++) | Layer | Usual defect |
|---|---|---|---|
| `int` arithmetic on money, sizes, counts, epoch millis | `uint32_t`/`int` size math; `a * b` before `malloc`/`new[]` | L1 | Overflow defeats a bound check |
| `Integer ==`, `BigDecimal.equals`, `double` money | `float`/`double` money; `==` on floats | L1 | Identity or representation, not value |
| `if (!map.containsKey(k)) map.put(…)`; `get` then `put` | Lock, check, unlock, …, lock, act | L2 | Check-then-act (TOCTOU) |
| `synchronized` / `ReentrantLock` in a multi-replica service | `std::mutex` guarding state that lives in a DB/cache | L2 | Lock scope narrower than state scope |
| Nested locks in varying order | Two `lock()` calls without `std::scoped_lock(a, b)` | L2 | Deadlock |
| `acquire()` / `lock()` / `open()` without `finally` or try-with-resources | `new`/`malloc`/`lock()` without RAII | L3 | Leak or stuck lock on the throw path |
| `ThreadLocal.set` without `remove()` in `finally` | Thread-local state in a pool | L3 | Cross-request leak |
| Remote call inside `synchronized`, `@Transactional`, or a lock | Blocking call under a mutex | L4 | Lock across I/O |
| `future.get()`, HTTP clients, JDBC without a timeout | Blocking `recv`/`read` without deadline | L4 | Hang |
| `catch (Timeout…)` treated as failure; retries at several layers | Same | L4 | Unknown outcome mishandled; retry storm |
| Renamed/removed field on an event, DTO or JSON; enum reordered; `@Enumerated` with default ORDINAL | Struct used as wire format; `long` in a protocol; field inserted mid-struct | L5 | Deployed reader breaks or silently misreads |
| Repository `findById(id)` behind an authenticated endpoint | Index from the packet used without bounds | L6 | IDOR / out-of-bounds |
| `Path.resolve(userInput)`; string-built SQL | `memcpy(dst, src, attacker_len)`; narrowing a length field | L6 | Traversal, injection, overflow |
| Lazy association touched in a loop | Per-item syscalls/allocations in a hot loop | L7 | N+1, death by a thousand cuts |
| Unbounded `static Map`, queue, executor; IDs as metric labels | Unbounded `std::deque`/`vector` growth | L7 | Memory, cost, or metrics-backend outage |

---

## 2. The scan procedure: three timed passes

The brief's PR modules all use a **Minute-2 / Minute-10 / Minute-20** diagnostic guide. This is the procedure behind it.

### 2.1 Pass 1, by minute 2: map the change and triage the hunks

1. **Read the ticket and PR description.** Write down every contract the change touches: *who calls* (internal → public?), *how many run* (one → many?), *who retries* (client, SDK, queue redelivery?), *who reads the output* (events, tables, caches, files), *what data shape changes*.
2. **Read the file list.** Production code vs tests vs config vs schema. A migration file or a `.proto`/`.avsc` in the list moves L5 to the top.
3. **Score each hunk** with four yes/no questions and visit the high scorers first:

| Question | Points |
|---|---|
| Does it **mutate shared state** (DB row, cache, file, global, money)? | +2 |
| Does it **cross a process boundary** (network, disk, queue, IPC, DMA)? | +2 |
| Does it **change a contract** (signature, serialized field, enum, status code, error semantics)? | +2 |
| Does it **touch a trust boundary** (auth, IDs from the caller, sizes from the wire, paths)? | +2 |
| Is it pure computation, logging, or test-only? | +0 |

In PR-00, `refund()` scores 8/8 and the constructor scores 0. That alone tells you where the first 20 minutes go.

### 2.2 Pass 2, by minute 10: the Sev-1 radar across all seven layers

Run the instant tells (§1.5) over every high-scoring hunk, **one layer at a time, shallow**. You are collecting suspicions, not proving them. Write each as `layer · line · suspicion · proven?`. Resist proving anything yet. The goal of this pass is that no layer goes unvisited.

### 2.3 Pass 3, by minute 20: prove, unify, fix

For each suspicion, in severity order:

1. **Mechanism**: the exact interleaving, input value or deployed reader that breaks it.
2. **Evidence**: a number ("−1,794,967,296"), a two-column interleaving, or the test or probe that fails today.
3. **Root-cause grouping**: which suspicions share a violated invariant? In PR-00, F3, F4, F5, F6 and F7 all follow from one decision, "the JVM is the source of truth for state shared across pods and time."
4. **Fix**: the smallest change that restores the invariant, checked against all seven layers so it doesn't relocate the bug.

After minute 20, sweep the low-scoring hunks and tests, batch the nits, and land the summary ([01 §7](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#7-the-45-minute-game-plan)).

---

## 3. Layer 1: correctness and invariants

**Invariant class.** Every value is what the code believes it is: in range, compared by value, in the right unit, present when assumed present, in the right time zone.

**Instant tells.**
- *Java:* `int`/`long` arithmetic on money, quantities, sizes or epoch values with no `Math.*Exact`; `Integer`/`Long` compared with `==`; `BigDecimal.equals`/`hashCode` in sets or map keys; `double`/`float` for money; `IntStream.sum()` over large values; `Optional.get()`; `LocalDateTime.now()` (zone-less) in business logic; integer division before multiplication.
- *C/C++:* size computations in 32-bit types before `malloc`/`new[]`/`memcpy`; `size_t` subtraction (`len - header`); `std::accumulate` with an `int` literal init over 64-bit data; signed overflow in loop bounds or checks (UB: the optimizer may delete a post-hoc `if (x + 1 < x)` check); mixed signed/unsigned comparisons; `long` assumed 64-bit.

**Questions that expose it.** "What's the largest realistic value here, and the largest malicious one?" "What's the zero/empty/null case?" "Is this compared by identity or value?" "Which unit is this in, and who converts?"

**Demonstrated** in `FaultScan.java` layer 1 and `fault_scan.cpp` layer 1 (§10):
- `100 == 100` is `true` but `1000 == 1000` is `false` for boxed `Integer`s: the `Integer` cache covers −128..127, so tests with small quantities pass.
- `new BigDecimal("10.0")` and `new BigDecimal("10.00")` are two entries in a `HashSet`, because `equals` includes scale. Dedup by `compareTo` or normalize scale.
- `IntStream.sum()` of three 1,000,000,000 amounts is −1,294,967,296.
- Ten × 0.10 as `double` is 0.9999999999999999.
- In C++, `std::accumulate(v.begin(), v.end(), 0)` over `int64_t` values returns −1294967296, because the accumulator's type is the init's type. The narrowing happens inside a system header, so `-Wconversion -Werror` stays silent on both compilers.
- 536,870,913 records × 8 bytes in `uint32_t` "allocates" 8 bytes; `3 - 4` in `size_t` is 18446744073709551615.

**Severity guidance.** Overflow or underflow that *feeds a bound check, an allocation size or money* is Sev-1: it turns a guard into a bypass. Representation bugs in displayed values are Sev-3.

**False positives to avoid.** Minor units in integer types are the industry norm for money. "Use `BigDecimal`" is not a finding; "this `int` overflows at IDR scale" is. `Integer ==` against a value that is always cached (e.g., enum-like small codes) is a smell, not a Sev-1: say so.

**In PR-00.** F2 (line 40): `int newTotal = charge.refundedMinor() + req.amountMinor()` wraps to a negative number and *passes* `newTotal > charge.amountMinor()`.

---

## 4. Layer 2: concurrency and atomicity

**Invariant class.** A decision is still true when it is acted on. Shared state is accessed under the coordination mechanism whose *scope matches the state's scope*.

That second sentence is the L7 core of this layer. A JVM lock coordinates threads in one process. A database transaction coordinates connections to one database. A distributed lock coordinates lease holders, but only with a fencing token checked at the resource. **When state lives in a database shared by six pods, a JVM lock is decoration.**

**Instant tells.**
- *Java:* `containsKey`/`get` followed by `put`; `find` then `save`; `if (count < limit) count++`; `synchronized`/`ReentrantLock`/`AtomicX` guarding state that also lives in a DB or cache; nested `synchronized` blocks or `lock()` calls in data-dependent order (transfer A→B vs B→A); `volatile` used for compound actions (`x++`); double-checked locking without `volatile`; `ConcurrentHashMap.computeIfAbsent` doing slow I/O in the mapping function (it holds the bin lock).
- *C/C++:* two separate critical sections around a check and an act; non-atomic flags read in loops (a data race is UB, and the compiler may hoist the load); `std::shared_ptr` copy across threads assumed to make the pointee thread-safe; locks taken in different orders without `std::scoped_lock(a, b)`; relaxed atomics publishing data.

**Questions.** "What runs concurrently with this: other threads, other pods, retries, replays, a human double-clicking?" "Between this read and this write, what else can write?" "What's the scope of this lock vs the scope of the state?" "In what order are these locks taken on every path?"

**Demonstrated** (§10):
- Java: check-then-act on a `ConcurrentHashMap` with a 5 ms load: 16 threads → 16 loads of one key; `computeIfAbsent` → 1 (the map's own atomic compound operation).
- Java: `transfer(A,B) ‖ transfer(B,A)` with two latches that script the interleaving: both threads hold their first lock, and neither releases it until both have tried their second. Both `tryLock` calls time out (with `lock()` this is a permanent deadlock); a global lock order completes both. The first version had only one latch and was *not* deterministic. The gate rerun printed `true/false`, because the first thread to time out released its lock and let the other through. That is exactly how timeout-based deadlock "recovery" picks an arbitrary victim.
- C++: lock-check-unlock, RPC, lock-insert-unlock with 8 threads creates 8 sessions for one user; one critical section with `try_emplace` creates 1.

**How to prove a race in review.** Draw two columns, one per actor, with time going down, and place each read and write. If you can draw an order where both actors pass a check that only one should pass, you have proven it. That's the evidence an interviewer wants, and it's what the PR-00 probes automate.

| t | Pod A | Pod B |
|---|---|---|
| 0 | read `refunded = 0` | |
| 1 | | read `refunded = 0` |
| 2 | `0 + 6000 ≤ 10000` ✓ | `0 + 6000 ≤ 10000` ✓ |
| 3 | gateway pays 6,000 | gateway pays 6,000 |
| 4 | `setRefunded(6000)` | `setRefunded(6000)` (lost update) |

**Severity guidance.** Check-then-act on money, inventory, quotas or uniqueness is Sev-1. Deadlocks on a request path are Sev-1 or Sev-2 (they look like a hang, and pods restart into the same state). Benign races on statistics are Sev-3.

**False positives to avoid.** A single `ConcurrentHashMap.get` is not a race. `synchronized` in a component documented and deployed as a singleton (a leader-elected scheduler) may be fine: ask about deployment before asserting. Relaxed atomics on a pure counter are fine.

**In PR-00.** F3 (lines 31, 40, 54): per-JVM `synchronized` plus a blind `setRefunded(newTotal)`. F4 (lines 32–35, 53): the idempotency key is checked first and written only after the payout.

---

## 5. Layer 3: resource lifecycle and failure paths

**Invariant class.** Everything acquired is released on *every* path, including the throw path. Every partial failure (a process dying between any two lines) leaves a state that a person or a job can find and repair.

**Instant tells.**
- *Java:* `acquire()`, `lock()`, `getConnection()`, `new FileInputStream()`, `ThreadLocal.set()` without try-with-resources or a `finally`; `ExecutorService` created per request and never shut down; listeners registered and never removed; a sequence of independent writes (DB, then cache, then event) with no transaction or outbox; "save after the side effect" ordering.
- *C/C++:* raw `new`/`malloc`/`fopen`/`lock()` with an early `return` or a throw before the release; `goto cleanup` paths that miss one resource; destructors that can throw; ownership expressed in comments instead of types; references or iterators held across container mutation (`push_back` reallocation).

**Questions.** "If this line throws, what's still held?" "If the process dies right after this line, what does the system look like, and who notices?" "Which write is the commit point, and is everything before it reversible?"

**Demonstrated** (§10):
- Java: a 4-permit pool. After four requests that throw between `acquire` and `release`, a valid request can't get a connection; `try/finally` keeps the pool healthy.
- Java: a pooled thread keeps `TENANT = "acme"` from a failed request, and the next anonymous request on that thread sees it. A cross-tenant leak from a missing `remove()` in `finally`.
- C++: 100 bad frames leak 100 `Parser` objects with raw `new`/`delete`, and 0 with `std::unique_ptr`. A manual `lock()` before a throw leaves the mutex held, so another thread's `try_lock` fails (in production every later caller blocks forever); `std::scoped_lock` releases it.
- C++: `push_back` past capacity moves the buffer, so a reference taken earlier dangles.

**Severity guidance.** A leak on a path a client can trigger (bad input, auth failure) is Sev-1 for availability: an attacker can drain your pool with 4 requests. A cross-tenant leak via `ThreadLocal` is Sev-1 for security. A "side effect before the durable record" ordering on money is Sev-1 in impact, Sev-2 in likelihood.

**False positives to avoid.** Try-with-resources already closes in reverse order; don't ask for a `finally` around it. A `ThreadLocal` that is always overwritten before read, with no sensitive data, is a smell, not a Sev-1.

**In PR-00.** F7 (lines 53–57): the gateway pays, then three independent writes follow. A failover before line 53 leaves money moved with no row anywhere. The probe reports `durable trace = NONE (unreconcilable)`.

---

## 6. Layer 4: I/O and distributed boundaries

**Invariant class.** Every remote interaction is **bounded** (deadline), **classified honestly** (success / definite failure / unknown), **idempotent** where retried, and never performed **while holding a lock** that other work needs.

**Instant tells.**
- *Java:* HTTP/gRPC/JDBC/Kafka calls inside `synchronized`, a `ReentrantLock`, or a long `@Transactional` method; `future.get()` / `join()` / `HttpClient.send` without a timeout; `catch (TimeoutException e)` lumped with definitive errors, or mapped to "failed"; retries at more than one layer of the stack; retries without jitter; retries of non-idempotent operations; new idempotency keys minted per retry.
- *C/C++:* blocking `send`/`recv`/`write` or a callback invoked while holding a mutex; no `SO_RCVTIMEO`/deadline; retry loops without backoff in daemons that all restart together.

**Questions.** "What if this call takes 30 seconds?" "What if it succeeds and the response is lost?" "Who retries this, at how many layers, with which key?" "What else is waiting on the lock while this call is in flight?"

**Demonstrated** (§10):
- Java: a peer that accepts and never answers. A caller with no deadline is still blocked after 300 ms (forever, in production); `get(100 ms)` fails fast with `TimeoutException`.
- Java: three layers × three attempts = 27 calls to a down database per user request; retrying at one layer = 3. AWS's Builders' Library gives the five-layer version: "the load on the database will increase 243x," and the best practice is "to retry at a single point in the stack."
- C++: a notifier holds a mutex while making 8 blocking sends, and a request-path lookup waits behind it. The measured wait was ~120 ms, longer than the 8 × 5 ms requested, because Windows' default timer tick is ~15.6 ms, so each `sleep_for(5ms)` slept about 15 ms. Copying the subscriber list under the lock and sending outside it drops the wait to 0 ms.

**The three outcomes of a remote call.** Most L5 code models two: success and failure. Production has three:

| Outcome | Meaning | Correct handling |
|---|---|---|
| **Success** | It happened | Commit your side durably |
| **Definite failure** | The dependency guarantees it did *not* happen (e.g. a decline) | Release reservations; report failure |
| **Unknown** | Timeout, connection reset after send, 5xx from a proxy | Record UNKNOWN; **never** invite a fresh-key retry; reconcile by key (`lookup`) or retry with the *same* idempotency key |

**Severity guidance.** Treating "unknown" as "failed" on a money-moving or message-sending path is Sev-1: it produces duplicates. A lock across I/O on a request path is Sev-2 (a dependency brownout becomes your outage). A missing timeout on a request path is Sev-2. Retry amplification is Sev-2: it converts a dependency's partial outage into a total one.

**False positives to avoid.** A blocking call under a lock that *only* guards that call's own connection (a per-connection write lock) is often correct. A missing timeout in a batch tool run by a human with Ctrl-C is a Sev-3.

**In PR-00.** F5 (lines 31, 46): the monitor is held across `gateway.refund()`. F6 (lines 47–49): `catch (GatewayTimeoutException | GatewayDeclinedException e)` reports both as "refund failed, please retry," although the gateway's own Javadoc says a timeout means "the refund may or may not have executed."

---

## 7. Layer 5: data and wire compatibility

**Invariant class.** Every deployed reader can correctly read every deployed writer's data, **in both directions of a rollout and a rollback**, for as long as the data lives: an event retained for 7 days, a row for 7 years, a cache entry for 1 hour, a struct on the wire for one packet.

This is the most under-reviewed layer, because the breakage is invisible in the diff. The reader is in another repo, owned by another team, often deployed months ago. It is also the layer where breakage is most often *silent*: a missing JSON field defaults to 0 or null and the consumer keeps running.

**Instant tells.**
- *Java:* a field renamed or removed in an event, DTO, JSON or Avro/Protobuf schema; a type changed (`int` → `String`, cents → decimal); an enum constant added mid-list, reordered or removed; `@Enumerated` without `EnumType.STRING` (the Jakarta Persistence default is `ORDINAL`); `Enum.valueOf` on data from another service (a strict reader); changed meaning without changed name (amount in cents → amount in major units); Java serialization of classes that evolve; cache keys or cached value shapes changed without a version prefix; DB migrations that are not expand-then-contract.
- *Protobuf specifically:* reused or renumbered tags (`reserved` exists to prevent this), `required` fields, a changed field type. *Avro:* removed fields without defaults, renamed fields without aliases.
- *C/C++:* `struct` written to the wire or disk with `memcpy` (padding, alignment, endianness and type widths become protocol); `long`/`size_t`/`bool` in a wire format; a field inserted mid-struct (every later offset moves); a bitfield's layout assumed; a `#pragma pack` added on one side only.

**Questions.** "Who reads this? Find them in the consumer registry, topic ACLs or `grep` across repos, not from memory." "Can v1 read what v2 writes, and can v2 read what v1 wrote?" "If we roll back after writing new data, what happens?" "Is the change additive?"

**Demonstrated** (§10):
- Java: a row written as `REFUNDED` under `@Enumerated(ORDINAL)` is read back as `PARTIALLY_REFUNDED` once v2 inserts a constant mid-list. **Silent corruption, no exception.** Storing the name fixes it.
- Java: a strict v1 consumer parsing a v2 value throws `IllegalArgumentException`, a poison pill that stops the partition. A tolerant reader maps unknown values to UNKNOWN, counts them and moves on.
- C++: `WireHeaderV1` is 16 bytes with 3 padding bytes. Adding `flags` "next to version" in V2 moves `length` from offset 4 to 8, so a V1 reader reads `flags` as the length. `sizeof(long)` is 4 here (Windows, LLP64) and 8 on Linux (LP64). `memcpy` of `0x01020304` emits `04 03 02 01` on little-endian hosts; explicit big-endian encoding emits `01 02 03 04` everywhere.

**The safe-change rules (expand → migrate → contract).**

| Change | Safe pattern |
|---|---|
| Rename a field | Add the new field; write both; migrate readers; stop writing the old one only after the registry shows no reader; or publish v2 on a new topic |
| Add an enum value | Readers must be tolerant (unknown → default plus a metric) *before* any writer emits it; persist names, not ordinals |
| Change a type or unit | New field with a new name (`amount_minor` next to `amount_cents`); never reinterpret the old one |
| Remove a field | Stop reading everywhere, then stop writing; in Protobuf, `reserved` the tag and name |
| DB column | Expand (add nullable column) → backfill → dual-read → contract (drop) in a later release |
| Wire struct | Explicit serialization with fixed-width types, explicit byte order, a version field first, and a length prefix so old readers can skip unknown trailers |

**Severity guidance.** Silent misreads by a deployed consumer (zeroed amounts, ordinal shifts) are Sev-1. Loud failures (poison pills) are Sev-1 for availability: the partition stops, lag grows, downstream SLAs breach. A break with no current reader is Sev-3, but prove there's no reader.

**False positives to avoid.** Adding an *optional* field to a JSON or Protobuf message is normally safe. Renaming a private field of an internal class that is never serialized is fine. Check before flagging.

**In PR-00.** F8 (lines 55–57): `amountCents` is renamed to `amountMinor` on the live `refunds.v1` topic. The deployed ledger consumer reads `amountCents`, gets its default of 0, and books every refund as zero. The test `publishesRefundIssuedEvent` asserts the new name, so it pins the break.

---

## 8. Layer 6: security and trust boundaries

**Invariant class.** Every request is authenticated, **authorized for this specific object**, and every externally supplied value (ID, path, size, URL, query fragment, header) is validated *before* use. Internally generated data that crosses a system boundary is validated as if it were external (Cloudflare's November 2025 lesson).

**Instant tells.**
- *Java:* `repository.findById(idFromRequest)` behind an authenticated endpoint with no owner/tenant predicate (IDOR, OWASP API1:2023 "Broken Object Level Authorization"); an authorization context that changed in this PR (internal → public, staff → merchant); cache keys missing the tenant; `Path.resolve(userInput)` without `normalize()` + `startsWith(base)`; SQL/JPQL/LDAP built by concatenation; `ObjectInputStream` on untrusted bytes; outbound requests to caller-supplied URLs (SSRF, which OWASP's 2025 Top 10 folds into A01 Broken Access Control); secrets or PANs in logs or exception messages; 403 vs 404 responses that let callers enumerate.
- *C/C++:* lengths from the packet used before checking against the buffer; a length narrowed to a smaller type before the check (`uint16_t len = size`); `strcpy`/`sprintf`/`%s` with external data; signed lengths; `memcpy` sizes derived from two attacker-controlled fields; format strings from input.

**Questions.** "Who can call this, as of *this* PR?" "Where is the caller's identity compared with the object's owner?" "What's the largest, longest, deepest input, and is the check done on the same type that's used?"

**Demonstrated** (§10):
- Java: `resolve("../globex/2026-10.pdf")` from acme's base directory normalizes to `srv/invoices/globex/2026-10.pdf`. The containment check (`startsWith(base)` after `normalize()`) rejects it.
- Java: a cache keyed by invoice id alone returns acme's invoice to globex. Scoping the key to `(tenant, id)` turns it into a miss, then a tenant-filtered load, then a 404.
- C++: a 65,552-byte payload's length stored in a 16-bit field becomes 16, so the bounds check against a 64-byte buffer *passes*, and the `memcpy` would copy 65,552 bytes. Checking the `size_t` before narrowing, and copying through a checked `std::span`, rejects it.

**Severity guidance.** IDOR on any mutation, or on a read of PII or financial data, is Sev-1. A traversal or overflow reachable from the network is Sev-1. A context change (internal → public) without a matching authz review is Sev-1 by default until proven otherwise.

**False positives to avoid.** If authorization happens upstream in a gateway or filter *and that is the documented pattern*, verify it covers this route before flagging. Then the finding is "this route isn't in the filter's scope," or nothing. A 404-for-other-tenant's-object is a *feature*.

**In PR-00.** F1 (line 36): `charges.find(req.chargeId())` loads any merchant's charge. The `merchantId` parameter is "the authenticated merchant, from the API key" (line 29), but it is only *written* into the record (line 51), never compared. Exploit: create a merchant account, buy from the victim merchant, then refund your own purchase against the victim's charge.

---

## 9. Layer 7: operability and scale

**Invariant class.** Everything that grows with traffic, tenants, data or time has a **bound**, and the system stays **observable and affordable** at 100× today's load.

**Instant tells.**
- *Java:* lazy JPA associations touched in a loop (N+1); `findAll()` without pagination; a `static Map`/`List` used as a cache without eviction; `Executors.newCachedThreadPool()` or unbounded queues on request paths; IDs, emails, URLs or raw paths as metric labels; log lines inside hot loops or with full payloads; a feature without a flag/kill switch; per-request object creation of expensive clients (an `HttpClient` or `ObjectMapper` per call).
- *C/C++:* unbounded `std::deque`/`std::vector` growth fed by a faster producer; per-item allocations or syscalls in a hot loop; logging under a lock; `std::endl` (flush) per line in high-volume output; no backpressure between stages.

**Questions.** "What's the cardinality of this key or label in production?" "What bounds this queue or cache, and what happens at the bound: block, drop, or shed?" "How many queries does this endpoint issue for a page of 100?" "If this misbehaves at 3 a.m., what dashboard shows it, and what switch turns it off?"

**Demonstrated** (§10):
- Java: 100 orders → 101 queries with a per-row lookup; one batched `IN (…)` → 2.
- Java: a never-evicted session map holds 100,000 entries after 100,000 requests; a bounded LRU (`LinkedHashMap` with `removeEldestEntry`) holds 1,000.
- C++: a producer faster than its consumer drives an unbounded queue to a peak depth in the hundreds of thousands (most of the 200,000 items); a bounded queue of 1,024 with a blocking `put` caps it at 1,024, and backpressure slows the producer instead of exhausting memory.

**Severity guidance.** Unbounded growth on a request path is Sev-2 (a slow OOM, often during a traffic spike, when you can least afford it). Metric-label explosions are Sev-3, or Sev-2 when they can take down a shared metrics backend. Prometheus's guidance is explicit: "Do not use labels to store dimensions with high cardinality (many different label values), such as user IDs, email addresses, or other unbounded sets of values." N+1 on a hot endpoint is Sev-2.

**False positives to avoid.** A bounded label like `currency` (≈ 180 ISO 4217 codes) or `outcome` (4) is fine. An N+1 over a list capped at 3 items by the domain is a nit at most.

**In PR-00.** F9 (lines 48, 58): `Map.of("refund_id", req.idempotencyKey())` as metric tags. The probe shows 500 refunds producing 500 series; the fix (`outcome`, `currency`) produces 1.

---

## 10. Runnable demonstrations

### 10.1 `FaultScan.java`

```java
// FaultScan.java - one runnable demo per layer of the 7-layer fault scan (Java 21, no dependencies).
// Each demo runs the code shape a reviewer should flag, then the fix, and prints both outcomes.
// Lines marked "one measured run" are timing- or scheduling-dependent; everything else is deterministic.

import java.math.BigDecimal;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.locks.ReentrantLock;
import java.util.function.Supplier;
import java.util.stream.IntStream;

public final class FaultScan {
    private static String n(long v) {
        return String.format(Locale.ROOT, "%,d", v);
    }

    public static void main(String[] args) throws Exception {
        layer1Correctness();
        layer2Concurrency();
        layer3Resources();
        layer4IoBoundaries();
        layer5Compatibility();
        layer6Security();
        layer7Operability();
    }

    // ---------------------------------------------------------------- Layer 1: correctness and invariants
    static void layer1Correctness() {
        System.out.println("== Layer 1: correctness");
        Integer smallA = 100, smallB = 100, bigA = 1_000, bigB = 1_000; // e.g. quantity vs limit from two DTOs
        System.out.println("boxed ==        : 100 == 100 -> " + (smallA == smallB) + ", 1000 == 1000 -> " + (bigA == bigB)
                + "   fix: equals() -> " + bigA.equals(bigB));

        Set<BigDecimal> seen = new HashSet<>(List.of(new BigDecimal("10.0"), new BigDecimal("10.00")));
        System.out.println("BigDecimal dedup: HashSet{10.0, 10.00}.size() = " + seen.size()
                + "   fix: compareTo == 0 -> " + (new BigDecimal("10.0").compareTo(new BigDecimal("10.00")) == 0));

        int[] amounts = {1_000_000_000, 1_000_000_000, 1_000_000_000};
        long checked = IntStream.of(amounts).asLongStream().reduce(0L, Math::addExact);
        System.out.println("int stream sum  : " + n(IntStream.of(amounts).sum()) + "   fix: long + addExact -> " + n(checked));

        double total = 0;
        for (int i = 0; i < 10; i++) {
            total += 0.10;
        }
        long cents = 0;
        for (int i = 0; i < 10; i++) {
            cents += 10;
        }
        System.out.println("double money    : ten x 0.10 = " + total + ", == 1.0 -> " + (total == 1.0)
                + "   fix: minor units -> " + cents + " cents");
    }

    // ---------------------------------------------------------------- Layer 2: concurrency and atomicity
    static void layer2Concurrency() throws Exception {
        System.out.println("== Layer 2: concurrency");
        AtomicInteger loads = new AtomicInteger();
        Map<String, String> cache = new ConcurrentHashMap<>();
        Runnable checkThenAct = () -> {
            if (!cache.containsKey("user:42")) { // check ...
                cache.put("user:42", slowLoad(loads)); // ... then act: every thread that passed the check loads
            }
        };
        runConcurrently(16, checkThenAct);
        int stampede = loads.getAndSet(0);
        Map<String, String> fixed = new ConcurrentHashMap<>();
        runConcurrently(16, () -> fixed.computeIfAbsent("user:42", k -> slowLoad(loads)));
        System.out.println("check-then-act  : 16 threads -> " + stampede + " loads of one key (one measured run)"
                + "   fix: computeIfAbsent -> " + loads.get() + " load");

        ReentrantLock a = new ReentrantLock();
        ReentrantLock b = new ReentrantLock();
        boolean[] unordered = transferPair(a, b, b, a);
        boolean[] ordered = transferPair(a, b, a, b); // both threads lock in one global order (e.g. by account id)
        System.out.println("lock ordering   : transfer(A,B) || transfer(B,A) completed = " + unordered[0] + "/" + unordered[1]
                + " (deadlock; tryLock timed out)   fix: global order -> " + ordered[0] + "/" + ordered[1]);
    }

    static String slowLoad(AtomicInteger loads) {
        loads.incrementAndGet();
        sleep(5); // the database round trip that widens the race window
        return "profile-42";
    }

    /**
     * Thread 1 locks (f1, s1), thread 2 locks (f2, s2). Two latches script the interleaving: both hold their first
     * lock before either tries its second, and neither releases until both have tried. Without the second latch the
     * first timeout frees its lock and lets the other thread through, a nondeterministic "victim".
     */
    static boolean[] transferPair(ReentrantLock f1, ReentrantLock s1, ReentrantLock f2, ReentrantLock s2)
            throws Exception {
        CountDownLatch bothHoldFirst = new CountDownLatch(2);
        CountDownLatch bothTried = new CountDownLatch(2);
        ExecutorService pool = Executors.newFixedThreadPool(2);
        Future<Boolean> t1 = pool.submit(() -> transfer(f1, s1, bothHoldFirst, bothTried));
        Future<Boolean> t2 = pool.submit(() -> transfer(f2, s2, bothHoldFirst, bothTried));
        boolean[] r = {t1.get(), t2.get()};
        pool.shutdown();
        return r;
    }

    static boolean transfer(ReentrantLock first, ReentrantLock second, CountDownLatch bothHoldFirst,
                            CountDownLatch bothTried) throws InterruptedException {
        first.lock();
        try {
            bothHoldFirst.countDown();
            bothHoldFirst.await(100, TimeUnit.MILLISECONDS); // test seam: the interleaving production hits rarely
            boolean got = second.tryLock(200, TimeUnit.MILLISECONDS); // lock() here would block forever
            bothTried.countDown();
            bothTried.await(100, TimeUnit.MILLISECONDS); // test seam: hold the first lock until both have tried
            if (!got) {
                return false;
            }
            try {
                return true; // move money
            } finally {
                second.unlock();
            }
        } finally {
            first.unlock();
        }
    }

    // ---------------------------------------------------------------- Layer 3: resource lifecycle, failure paths
    static final ThreadLocal<String> TENANT = new ThreadLocal<>();

    static void layer3Resources() throws Exception {
        System.out.println("== Layer 3: resources and failure paths");
        Semaphore leaky = new Semaphore(4); // a 4-connection pool
        for (int i = 0; i < 4; i++) {
            try {
                handleLeaky(leaky, "bad-input");
            } catch (IllegalArgumentException expected) {
                // the client got a 400; the connection never came back
            }
        }
        boolean got = leaky.tryAcquire(100, TimeUnit.MILLISECONDS);
        Semaphore safe = new Semaphore(4);
        for (int i = 0; i < 4; i++) {
            try {
                handleSafe(safe, "bad-input");
            } catch (IllegalArgumentException expected) {
                // 400, and the finally block returned the connection
            }
        }
        System.out.println("leak on throw   : after 4 bad requests a good one gets a connection -> " + got
                + "   fix: try/finally -> " + safe.tryAcquire(100, TimeUnit.MILLISECONDS));

        ExecutorService worker = Executors.newSingleThreadExecutor(); // a pooled request thread
        Future<?> first = worker.submit(() -> {
            TENANT.set("acme");
            throw new IllegalStateException("validation failed"); // TENANT.remove() below never runs
        });
        try {
            first.get();
        } catch (java.util.concurrent.ExecutionException expected) {
            // request 1 failed
        }
        String leaked = worker.submit(() -> String.valueOf(TENANT.get())).get(); // request 2: anonymous caller
        TENANT.remove();
        Future<String> second = worker.submit(() -> {
            try {
                TENANT.set("acme");
                throw new IllegalStateException("validation failed");
            } catch (IllegalStateException e) {
                return "failed";
            } finally {
                TENANT.remove();
            }
        });
        second.get();
        String clean = worker.submit(() -> String.valueOf(TENANT.get())).get();
        worker.shutdown();
        System.out.println("ThreadLocal leak: next request on the pooled thread sees tenant = " + leaked
                + "   fix: remove() in finally -> " + clean);
    }

    static void handleLeaky(Semaphore pool, String input) throws InterruptedException {
        pool.acquire();
        validate(input); // throws: release() is skipped
        pool.release();
    }

    static void handleSafe(Semaphore pool, String input) throws InterruptedException {
        pool.acquire();
        try {
            validate(input);
        } finally {
            pool.release();
        }
    }

    static void validate(String input) {
        if (input.startsWith("bad")) {
            throw new IllegalArgumentException("400: " + input);
        }
    }

    // ---------------------------------------------------------------- Layer 4: I/O and distributed boundaries
    static int dbCalls;

    static void layer4IoBoundaries() throws Exception {
        System.out.println("== Layer 4: I/O boundaries");
        CompletableFuture<String> silentPeer = new CompletableFuture<>(); // accepted the connection, never answers
        Thread caller = Thread.ofPlatform().daemon().start(() -> {
            try {
                silentPeer.get();
            } catch (Exception ignored) {
                // never reached
            }
        });
        caller.join(300);
        long t0 = System.nanoTime();
        String outcome;
        try {
            silentPeer.get(100, TimeUnit.MILLISECONDS);
            outcome = "answered";
        } catch (TimeoutException e) {
            outcome = "TimeoutException after " + (System.nanoTime() - t0) / 1_000_000 + " ms";
        }
        System.out.println("no deadline     : caller still blocked after 300 ms -> " + caller.isAlive()
                + "   fix: get(100 ms) -> " + outcome + " (one measured run)");

        dbCalls = 0;
        try {
            retry(3, () -> retry(3, () -> retry(3, FaultScan::db))); // gateway -> service -> DAO, each "resilient"
        } catch (RuntimeException expected) {
            // the user sees an error either way
        }
        int amplified = dbCalls;
        dbCalls = 0;
        try {
            retry(3, () -> FaultScan.db()); // retry at one layer only; inner layers fail fast
        } catch (RuntimeException expected) {
            // same error, 9x less load on the sick database
        }
        System.out.println("retry storm     : 3 layers x 3 attempts -> " + amplified + " calls to a down DB per request"
                + "   fix: retry at one layer -> " + dbCalls);
    }

    static String db() {
        dbCalls++;
        throw new IllegalStateException("db unavailable");
    }

    static String retry(int attempts, Supplier<String> call) {
        RuntimeException last = null;
        for (int i = 0; i < attempts; i++) {
            try {
                return call.get();
            } catch (RuntimeException e) {
                last = e;
            }
        }
        throw last;
    }

    // ---------------------------------------------------------------- Layer 5: data and wire compatibility
    enum StatusV1 { PENDING, PAID, REFUNDED }

    enum StatusV2 { PENDING, PAID, PARTIALLY_REFUNDED, REFUNDED } // the PR inserts a constant in the middle

    static void layer5Compatibility() {
        System.out.println("== Layer 5: compatibility");
        int stored = StatusV1.REFUNDED.ordinal(); // a row written by v1 with @Enumerated(EnumType.ORDINAL)
        System.out.println("ordinal storage : row written as REFUNDED is read back by v2 as " + StatusV2.values()[stored]
                + "   fix: store the name -> " + StatusV2.valueOf(StatusV1.REFUNDED.name()));
        String fromNewerProducer = "PARTIALLY_REFUNDED";
        String strict;
        try {
            strict = StatusV1.valueOf(fromNewerProducer).name();
        } catch (IllegalArgumentException e) {
            strict = "IllegalArgumentException (poison pill: the partition stops)";
        }
        System.out.println("strict reader   : v1 consumer parses a v2 value -> " + strict
                + "   fix: tolerant reader -> " + tolerant(fromNewerProducer).map(Enum::name).orElse("UNKNOWN, counted, skipped"));
    }

    static Optional<StatusV1> tolerant(String raw) {
        for (StatusV1 s : StatusV1.values()) {
            if (s.name().equals(raw)) {
                return Optional.of(s);
            }
        }
        return Optional.empty();
    }

    // ---------------------------------------------------------------- Layer 6: security and trust boundaries
    static void layer6Security() {
        System.out.println("== Layer 6: security");
        Path base = Path.of("srv", "invoices", "acme");
        String userInput = "../globex/2026-10.pdf";
        Path resolved = base.resolve(userInput).normalize(); // the PR serves this path without a containment check
        System.out.println("path traversal  : resolve(\"" + userInput + "\") -> " + resolved.toString().replace('\\', '/')
                + "   fix: normalize + startsWith(base) -> " + (resolved.startsWith(base) ? "allowed" : "rejected"));

        Map<String, String> naiveCache = new HashMap<>(); // keyed by invoice id only
        naiveCache.put("inv-7", "acme: $12,400 owed by Initech");
        String leaked = naiveCache.get("inv-7"); // tenant globex asks for inv-7 and hits acme's entry
        Map<String, String> scoped = new HashMap<>();
        scoped.put("acme/inv-7", "acme: $12,400 owed by Initech");
        System.out.println("cache key scope : globex reads inv-7 -> \"" + leaked + "\"   fix: (tenant, id) key -> "
                + scoped.getOrDefault("globex/inv-7", "miss -> load with tenant filter -> 404"));
    }

    // ---------------------------------------------------------------- Layer 7: operability and scale
    static int queries;

    record Order(int id, int customerId) {}

    static void layer7Operability() {
        System.out.println("== Layer 7: operability");
        List<Order> orders = new ArrayList<>();
        for (int i = 0; i < 100; i++) {
            orders.add(new Order(i, i % 37));
        }
        queries = 1; // SELECT * FROM orders ...
        for (Order o : orders) {
            findCustomer(o.customerId()); // lazy association touched in a loop
        }
        int nPlusOne = queries;
        queries = 1;
        findCustomers(orders.stream().map(Order::customerId).distinct().toList());
        System.out.println("N+1             : 100 orders -> " + nPlusOne + " queries   fix: one IN (...) batch -> " + queries);

        Map<String, byte[]> sessions = new HashMap<>(); // static, never evicted
        Map<String, byte[]> bounded = new LinkedHashMap<>(16, 0.75f, true) {
            private static final long serialVersionUID = 1L;

            @Override
            protected boolean removeEldestEntry(Map.Entry<String, byte[]> eldest) {
                return size() > 1_000;
            }
        };
        for (int i = 0; i < 100_000; i++) {
            sessions.put("req-" + i, new byte[16]);
            bounded.put("req-" + i, new byte[16]);
        }
        System.out.println("unbounded map   : entries after 100,000 requests -> " + n(sessions.size())
                + "   fix: bounded LRU -> " + n(bounded.size()));
    }

    static void findCustomer(int id) {
        queries++;
    }

    static void findCustomers(List<Integer> ids) {
        queries++;
    }

    // ---------------------------------------------------------------- helpers
    static void runConcurrently(int threads, Runnable task) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads);
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        List<Future<?>> fs = new ArrayList<>();
        for (int i = 0; i < threads; i++) {
            fs.add(pool.submit(() -> {
                start.await();
                task.run();
                return null;
            }));
        }
        for (Future<?> f : fs) {
            f.get();
        }
        pool.shutdown();
    }

    static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```

**Output (verified).** The `check-then-act` count and the `no deadline` timing are one measured run; every other line is deterministic.

```text
== Layer 1: correctness
boxed ==        : 100 == 100 -> true, 1000 == 1000 -> false   fix: equals() -> true
BigDecimal dedup: HashSet{10.0, 10.00}.size() = 2   fix: compareTo == 0 -> true
int stream sum  : -1,294,967,296   fix: long + addExact -> 3,000,000,000
double money    : ten x 0.10 = 0.9999999999999999, == 1.0 -> false   fix: minor units -> 100 cents
== Layer 2: concurrency
check-then-act  : 16 threads -> 16 loads of one key (one measured run)   fix: computeIfAbsent -> 1 load
lock ordering   : transfer(A,B) || transfer(B,A) completed = false/false (deadlock; tryLock timed out)   fix: global order -> true/true
== Layer 3: resources and failure paths
leak on throw   : after 4 bad requests a good one gets a connection -> false   fix: try/finally -> true
ThreadLocal leak: next request on the pooled thread sees tenant = acme   fix: remove() in finally -> null
== Layer 4: I/O boundaries
no deadline     : caller still blocked after 300 ms -> true   fix: get(100 ms) -> TimeoutException after 100 ms (one measured run)
retry storm     : 3 layers x 3 attempts -> 27 calls to a down DB per request   fix: retry at one layer -> 3
== Layer 5: compatibility
ordinal storage : row written as REFUNDED is read back by v2 as PARTIALLY_REFUNDED   fix: store the name -> REFUNDED
strict reader   : v1 consumer parses a v2 value -> IllegalArgumentException (poison pill: the partition stops)   fix: tolerant reader -> UNKNOWN, counted, skipped
== Layer 6: security
path traversal  : resolve("../globex/2026-10.pdf") -> srv/invoices/globex/2026-10.pdf   fix: normalize + startsWith(base) -> rejected
cache key scope : globex reads inv-7 -> "acme: $12,400 owed by Initech"   fix: (tenant, id) key -> miss -> load with tenant filter -> 404
== Layer 7: operability
N+1             : 100 orders -> 101 queries   fix: one IN (...) batch -> 2
unbounded map   : entries after 100,000 requests -> 100,000   fix: bounded LRU -> 1,000
```

### 10.2 `fault_scan.cpp`

```cpp
// fault_scan.cpp - one runnable demo per layer of the 7-layer fault scan (C++23, GCC 16 and Clang 21).
// Every demo stays inside defined behavior: where the real bug is UB (overflowing memcpy, dangling reads),
// the program prints the decision the buggy code would make instead of executing the UB.
// Lines marked "one measured run" depend on timing; everything else is deterministic.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <deque>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <numeric>
#include <print>
#include <span>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

static long long ms_since(Clock::time_point t0) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0).count();
}

// ------------------------------------------------------------------ Layer 1: correctness and invariants
struct Rec {
    std::uint32_t id;
    std::uint32_t qty;
};

static void layer1_correctness() {
    std::println("== Layer 1: correctness");
    std::vector<std::int64_t> amounts{1'000'000'000, 1'000'000'000, 1'000'000'000};
    auto truncated = std::accumulate(amounts.begin(), amounts.end(), 0);  // init is int: the sum is int
    auto exact = std::accumulate(amounts.begin(), amounts.end(), std::int64_t{0});
    std::println("accumulate init : int 0 -> {}   fix: int64_t{{0}} -> {}", truncated, exact);

    std::uint32_t count = 0x2000'0001u;  // record count from a file header
    std::uint32_t bytes = count * static_cast<std::uint32_t>(sizeof(Rec));  // wraps modulo 2^32
    bool rejects = count > std::numeric_limits<std::uint32_t>::max() / sizeof(Rec);
    std::println("size multiply   : {} records x {} B = {} B allocated   fix: overflow check -> {}", count, sizeof(Rec),
                 bytes, rejects ? "rejected" : "accepted");

    constexpr std::size_t kHeader = 4;
    std::size_t len = 3;  // a truncated datagram
    std::size_t body = len - kHeader;  // unsigned underflow
    std::println("size underflow  : len 3 - header 4 = {}   fix: check len < header first -> {}", body,
                 len < kHeader ? "rejected" : "accepted");

    int big = std::numeric_limits<int>::max();
    int sum = 0;
    bool overflow = __builtin_add_overflow(big, 1, &sum);  // INT_MAX + 1 in plain int is UB, not wraparound
    std::println("signed overflow : INT_MAX + 1 overflows -> {} (plain + is UB; the optimizer may delete your check)",
                 overflow);
}

// ------------------------------------------------------------------ Layer 2: concurrency and atomicity
static void layer2_concurrency() {
    std::println("== Layer 2: concurrency");
    for (bool fixed : {false, true}) {
        std::mutex m;
        std::map<int, std::string> sessions;
        std::atomic<int> creates{0};
        std::atomic<bool> go{false};
        {
            std::vector<std::jthread> ts;
            for (int i = 0; i < 8; ++i) {
                ts.emplace_back([&] {
                    while (!go.load(std::memory_order_acquire)) {
                    }
                    if (!fixed) {
                        bool exists;
                        {
                            std::scoped_lock lk(m);  // each step is locked ...
                            exists = sessions.contains(42);
                        }
                        if (!exists) {  // ... but the pair is not atomic
                            std::this_thread::sleep_for(2ms);  // build the session (an RPC)
                            std::scoped_lock lk(m);
                            sessions[42] = "session";
                            creates.fetch_add(1);
                        }
                    } else {
                        std::scoped_lock lk(m);  // decide and act in one critical section
                        if (sessions.try_emplace(42, "session").second) {
                            creates.fetch_add(1);
                        }
                    }
                });
            }
            go.store(true, std::memory_order_release);
        }
        if (!fixed) {
            std::print("TOCTOU          : 8 threads -> {} sessions created for one user (one measured run)", creates.load());
        } else {
            std::println("   fix: one critical section -> {}", creates.load());
        }
    }
}

// ------------------------------------------------------------------ Layer 3: resource lifecycle and lifetimes
static std::atomic<int> g_live_parsers{0};

struct Parser {
    Parser() { g_live_parsers.fetch_add(1); }
    ~Parser() { g_live_parsers.fetch_sub(1); }
    Parser(const Parser&) = delete;
    Parser& operator=(const Parser&) = delete;
    void parse(const std::string& in) const {
        if (in.empty()) {
            throw std::invalid_argument("empty frame");
        }
    }
};

static void handle_raw(const std::string& in) {
    Parser* p = new Parser;
    p->parse(in);  // throws: the delete below never runs
    delete p;
}

static void handle_owned(const std::string& in) {
    auto p = std::make_unique<Parser>();
    p->parse(in);
}

static std::mutex g_registry_mu;

static void update_manual(bool fail) {
    g_registry_mu.lock();
    if (fail) {
        throw std::runtime_error("bad update");  // unlock() below never runs
    }
    g_registry_mu.unlock();
}

static void update_scoped(bool fail) {
    std::scoped_lock lk(g_registry_mu);
    if (fail) {
        throw std::runtime_error("bad update");
    }
}

static bool other_thread_can_lock() {
    bool ok = false;
    std::jthread t([&] {
        if (g_registry_mu.try_lock()) {
            ok = true;
            g_registry_mu.unlock();
        }
    });
    t.join();
    return ok;
}

static void layer3_resources() {
    std::println("== Layer 3: resources and lifetimes");
    for (int i = 0; i < 100; ++i) {
        try {
            handle_raw("");
        } catch (const std::invalid_argument&) {
        }
    }
    int leaked = g_live_parsers.load();
    for (int i = 0; i < 100; ++i) {
        try {
            handle_owned("");
        } catch (const std::invalid_argument&) {
        }
    }
    std::println("leak on throw   : 100 bad frames -> {} Parsers never freed   fix: unique_ptr -> {} more",
                 leaked, g_live_parsers.load() - leaked);

    try {
        update_manual(true);
    } catch (const std::runtime_error&) {
    }
    bool after_manual = other_thread_can_lock();
    g_registry_mu.unlock();  // clean up the demo: this thread still owns it
    try {
        update_scoped(true);
    } catch (const std::runtime_error&) {
    }
    std::println("lock on throw   : after one failed update another thread can lock -> {}   fix: scoped_lock -> {}",
                 after_manual, other_thread_can_lock());

    std::vector<int> v{1, 2, 3};
    v.shrink_to_fit();
    auto before = reinterpret_cast<std::uintptr_t>(v.data());  // what a held `int& first = v[0]` points at
    v.push_back(4);  // exceeds capacity: reallocates
    auto after = reinterpret_cast<std::uintptr_t>(v.data());
    std::println("invalidation    : push_back moved the buffer -> {} (a reference taken before now dangles)",
                 before != after);
}

// ------------------------------------------------------------------ Layer 4: I/O and blocking boundaries
static void layer4_io() {
    std::println("== Layer 4: I/O boundaries");
    for (bool fixed : {false, true}) {
        std::mutex m;
        std::vector<int> subscribers{1, 2, 3, 4, 5, 6, 7, 8};
        std::atomic<long long> worst_wait_ms{0};
        std::atomic<bool> notifying{false};
        std::jthread notifier([&] {
            std::vector<int> snapshot;
            std::unique_lock lk(m);
            notifying.store(true);
            if (fixed) {
                snapshot = subscribers;  // copy under the lock ...
                lk.unlock();             // ... deliver outside it
            }
            for ([[maybe_unused]] int s : fixed ? snapshot : subscribers) {
                std::this_thread::sleep_for(5ms);  // a blocking send to subscriber s
            }
        });
        while (!notifying.load()) {
        }
        std::vector<std::jthread> readers;
        for (int r = 0; r < 4; ++r) {
            readers.emplace_back([&] {
                auto t0 = Clock::now();
                std::scoped_lock lk(m);  // a lookup() on the request path
                long long w = ms_since(t0);
                long long cur = worst_wait_ms.load();
                while (w > cur && !worst_wait_ms.compare_exchange_weak(cur, w)) {
                }
            });
        }
        readers.clear();
        notifier.join();
        if (!fixed) {
            std::print("lock across I/O : worst lookup waited {} ms behind 8 blocking sends", worst_wait_ms.load());
        } else {
            std::println("   fix: snapshot, unlock, send -> {} ms (one measured run)", worst_wait_ms.load());
        }
    }
}

// ------------------------------------------------------------------ Layer 5: data and wire compatibility
struct WireHeaderV1 {
    std::uint8_t version;
    std::uint32_t length;
    std::uint64_t seq;
};

struct WireHeaderV2 {  // the PR adds `flags` "next to version, where it belongs"
    std::uint8_t version;
    std::uint32_t flags;
    std::uint32_t length;
    std::uint64_t seq;
};

static void put_be32(std::span<std::byte, 4> out, std::uint32_t v) {
    for (std::size_t i = 0; i < 4; ++i) {
        out[i] = static_cast<std::byte>(v >> (24 - 8 * i));
    }
}

static void layer5_compat() {
    std::println("== Layer 5: compatibility");
    std::println("struct as wire  : V1 sizeof {} with {} padding bytes; length at offset {} in V1, {} in V2",
                 sizeof(WireHeaderV1), sizeof(WireHeaderV1) - (1 + 4 + 8), offsetof(WireHeaderV1, length),
                 offsetof(WireHeaderV2, length));
    std::println("long on the wire: sizeof(long) = {} here (LLP64 Windows); 8 on LP64 Linux -> use std::int64_t",
                 sizeof(long));
    std::uint32_t len = 0x01020304;
    std::byte host[4];
    std::memcpy(host, &len, 4);
    std::byte be[4];
    put_be32(be, len);
    std::println("byte order      : memcpy -> {:02x} {:02x} {:02x} {:02x}   fix: explicit big-endian -> {:02x} {:02x} {:02x} {:02x}",
                 std::to_integer<int>(host[0]), std::to_integer<int>(host[1]), std::to_integer<int>(host[2]),
                 std::to_integer<int>(host[3]), std::to_integer<int>(be[0]), std::to_integer<int>(be[1]),
                 std::to_integer<int>(be[2]), std::to_integer<int>(be[3]));
}

// ------------------------------------------------------------------ Layer 6: security and trust boundaries
static void layer6_security() {
    std::println("== Layer 6: security");
    std::vector<std::byte> payload(65'552);  // attacker-sized: 64 KiB + 16
    char buf[64];
    auto len16 = static_cast<std::uint16_t>(payload.size());  // the wire format's length field is 16 bits
    bool buggy_ok = len16 <= sizeof(buf);
    std::println("length truncate : size {} stored as uint16 {} -> bounds check {}; memcpy would copy {} B into {} B",
                 payload.size(), len16, buggy_ok ? "passes" : "fails", payload.size(), sizeof(buf));
    bool fixed_ok = payload.size() <= sizeof(buf);
    std::span<const std::byte> in(payload);
    std::println("   fix: compare the size_t, copy a checked span -> {}", fixed_ok ? "copied" : "rejected");
    if (fixed_ok) {
        std::memcpy(buf, in.first(in.size()).data(), in.size());
    }
}

// ------------------------------------------------------------------ Layer 7: operability and backpressure
static void layer7_operability() {
    std::println("== Layer 7: operability");
    for (std::size_t cap : {std::size_t{0}, std::size_t{1024}}) {  // 0 = unbounded
        std::mutex m;
        std::condition_variable not_full, not_empty;
        std::deque<int> q;
        std::size_t peak = 0;
        bool done = false;
        constexpr int kItems = 200'000;
        std::jthread consumer([&] {
            for (;;) {
                std::unique_lock lk(m);
                not_empty.wait(lk, [&] { return !q.empty() || done; });
                if (q.empty()) {
                    return;
                }
                q.pop_front();
                lk.unlock();
                not_full.notify_one();
                volatile int sink = 0;
                for (int k = 0; k < 200; ++k) {
                    sink = sink + k;  // per-item work: the consumer is slower than the producer
                }
            }
        });
        for (int i = 0; i < kItems; ++i) {
            std::unique_lock lk(m);
            if (cap != 0) {
                not_full.wait(lk, [&] { return q.size() < cap; });  // backpressure
            }
            q.push_back(i);
            peak = std::max(peak, q.size());
            lk.unlock();
            not_empty.notify_one();
        }
        {
            std::scoped_lock lk(m);
            done = true;
        }
        not_empty.notify_one();
        consumer.join();
        if (cap == 0) {
            std::print("unbounded queue : peak depth {} of {} items", peak, kItems);
        } else {
            std::println("   fix: bounded {} + blocking put -> peak {} (one measured run)", cap, peak);
        }
    }
}

int main() {
    layer1_correctness();
    layer2_concurrency();
    layer3_resources();
    layer4_io();
    layer5_compat();
    layer6_security();
    layer7_operability();
}
```

**Output (verified, GCC 16.2).** The TOCTOU count, the lock-across-I/O wait and the queue peak are one measured run.

```text
== Layer 1: correctness
accumulate init : int 0 -> -1294967296   fix: int64_t{0} -> 3000000000
size multiply   : 536870913 records x 8 B = 8 B allocated   fix: overflow check -> rejected
size underflow  : len 3 - header 4 = 18446744073709551615   fix: check len < header first -> rejected
signed overflow : INT_MAX + 1 overflows -> true (plain + is UB; the optimizer may delete your check)
== Layer 2: concurrency
TOCTOU          : 8 threads -> 8 sessions created for one user (one measured run)   fix: one critical section -> 1
== Layer 3: resources and lifetimes
leak on throw   : 100 bad frames -> 100 Parsers never freed   fix: unique_ptr -> 0 more
lock on throw   : after one failed update another thread can lock -> false   fix: scoped_lock -> true
invalidation    : push_back moved the buffer -> true (a reference taken before now dangles)
== Layer 4: I/O boundaries
lock across I/O : worst lookup waited 123 ms behind 8 blocking sends   fix: snapshot, unlock, send -> 0 ms (one measured run)
== Layer 5: compatibility
struct as wire  : V1 sizeof 16 with 3 padding bytes; length at offset 4 in V1, 8 in V2
long on the wire: sizeof(long) = 4 here (LLP64 Windows); 8 on LP64 Linux -> use std::int64_t
byte order      : memcpy -> 04 03 02 01   fix: explicit big-endian -> 01 02 03 04
== Layer 6: security
length truncate : size 65552 stored as uint16 16 -> bounds check passes; memcpy would copy 65552 B into 64 B
   fix: compare the size_t, copy a checked span -> rejected
== Layer 7: operability
unbounded queue : peak depth 188938 of 200000 items   fix: bounded 1024 + blocking put -> peak 1024 (one measured run)
```

**Output (verified, Clang 21.1).** Same program, built with the other compiler. The deterministic lines are byte-identical to GCC's.

```text
== Layer 1: correctness
accumulate init : int 0 -> -1294967296   fix: int64_t{0} -> 3000000000
size multiply   : 536870913 records x 8 B = 8 B allocated   fix: overflow check -> rejected
size underflow  : len 3 - header 4 = 18446744073709551615   fix: check len < header first -> rejected
signed overflow : INT_MAX + 1 overflows -> true (plain + is UB; the optimizer may delete your check)
== Layer 2: concurrency
TOCTOU          : 8 threads -> 8 sessions created for one user (one measured run)   fix: one critical section -> 1
== Layer 3: resources and lifetimes
leak on throw   : 100 bad frames -> 100 Parsers never freed   fix: unique_ptr -> 0 more
lock on throw   : after one failed update another thread can lock -> false   fix: scoped_lock -> true
invalidation    : push_back moved the buffer -> true (a reference taken before now dangles)
== Layer 4: I/O boundaries
lock across I/O : worst lookup waited 123 ms behind 8 blocking sends   fix: snapshot, unlock, send -> 0 ms (one measured run)
== Layer 5: compatibility
struct as wire  : V1 sizeof 16 with 3 padding bytes; length at offset 4 in V1, 8 in V2
long on the wire: sizeof(long) = 4 here (LLP64 Windows); 8 on LP64 Linux -> use std::int64_t
byte order      : memcpy -> 04 03 02 01   fix: explicit big-endian -> 01 02 03 04
== Layer 6: security
length truncate : size 65552 stored as uint16 16 -> bounds check passes; memcpy would copy 65552 B into 64 B
   fix: compare the size_t, copy a checked span -> rejected
== Layer 7: operability
unbounded queue : peak depth 190784 of 200000 items   fix: bounded 1024 + blocking put -> peak 1024 (one measured run)
```

### 10.3 What the demos teach beyond their layer

- **Tests with small numbers hide L1 bugs.** The boxed `==` passes for 100 and fails for 1,000. The overflow passes for 5,000 and fails for 1,000,000,000. Ask for boundary-value tests: `Integer.MAX_VALUE − 1`, empty, one, max-size.
- **Races are only "rare" when the window is tiny.** Both TOCTOU demos hit the maximum duplicate count (16 of 16, 8 of 8) in every run here, including the gate rerun, because the window is a 2–5 ms I/O call, not a nanosecond. In production the window is your dependency's p99 latency. That's why cross-pod check-then-act around a network call is a near-certain bug, not a theoretical one.
- **A race demo is only evidence if it is deterministic.** The deadlock demo's first version passed every run while it was being written, then printed `true/false` instead of `false/false` in the gate's independent rerun: one thread's timeout freed a lock and let the other thread finish. Scripting the interleaving with latches (a test seam) made it deterministic. In a review, the analogous move is asking for a test that forces the interleaving rather than hoping a stress test hits it.
- **Platform details leak into measurements.** The C++ lock-across-I/O wait reflects Windows' timer granularity. Always report what you measured *and* why it differs from the model.
- **Compilers don't save you at layer boundaries.** `std::accumulate`'s truncation, the struct layout shift and the 16-bit length truncation all compile cleanly under `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Werror` on both GCC and Clang. The narrowing either happens in a system header or is explicit (`static_cast`), which is precisely how real code hides it.

---

## 11. PR-00 answer key, line by line

The diff is in [01 §5.2](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#52-the-diff). Line numbers refer to the **new** `RefundService.java` (the `+` side). Review it yourself first.

### 11.1 The timed 3-pass diagnostic guide for PR-00

**Minute 2: map and triage.**
- Ticket: internal console → **public API** (trust changes), single instance → **6 replicas** (concurrency changes), staff → **merchant SDKs that retry** (idempotency matters), `refunds.v1` → **deployed ledger consumer** (compat matters).
- Hunk scores: `refund()` = 8/8 (state, I/O, contract, trust); constructor = 0; tests = read later for *what they pin*.
- Radar hits on sight: `int newTotal` (L1), `synchronized` + `gateway.refund` in one method (L2/L4), `catch (GatewayTimeoutException | GatewayDeclinedException e)` (L4), `"amountMinor"` replacing `"amountCents"` on `refunds.v1` (L5), `"refund_id"` as a tag (L7).

**Minute 10: one hop each.**
- Where is `merchantId` compared? Nowhere → F1.
- Who reads `amountCents`? The ledger → F8 is Sev-1 silent corruption.
- What does the gateway say a timeout means? "May or may not have executed" → F6.
- How many pods? Six → `synchronized` is per pod → F3 and F5 confirmed in principle.

**Minute 20: model-dependent defects and root cause.**
- Interleave two pods (§4 table) → F3 proven, including the lost update from the blind `setRefunded`.
- Same key on two pods → both miss `find`, gateway dedups money, we write two rows and two events → F4.
- Failover between the payout (line 46) and the first write (line 53) → no durable trace → F7.
- Overflow arithmetic with real IDR values → F2 proven with a number.
- Tests: `gatewayTimeoutIsRetryable` and `publishesRefundIssuedEvent` **assert** F6 and F8 → T1.
- **Unify:** F3, F4, F5, F6 and F7 are one root cause: *the PR keeps correctness in the JVM (a monitor) and in call ordering, but the state is shared across pods, time and failures.* The fix moves correctness into the database, which the platform already supports.

### 11.2 Findings

#### F1 · L6 · Sev-1 · Object-level authorization missing (line 36; context lines 29, 51)

**Mechanism.** Before this PR, only staff called `refundFull`, after the console authorized them. Now any merchant API key reaches `refund()`, and the charge is loaded by id alone. `merchantId` is documented as "the authenticated merchant, from the API key" but is only copied into the record. Exploit: open a merchant account, buy something from the victim merchant, then call `POST /v1/refunds` with the victim's `chargeId`. The refund comes out of the victim's balance onto the attacker's card. Charge IDs leak through receipts, support tickets and client-side code.

**Evidence.** Probe P1: `m_evil refunds m_shop's charge -> SUCCEEDED; network paid 5,000`.

**Comment (L7, short).** `issue (blocking):` the charge is loaded without an owner predicate, so any merchant can refund any charge they can name. Use `findForMerchant(merchantId, chargeId)` and return the same 404-style rejection as for a missing charge, so callers can't probe which IDs exist.

**Fix.**
```java
        Charge charge = charges.findForMerchant(merchantId, req.chargeId()); // another merchant's charge == missing
        if (charge == null) {
            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
            throw new RefundRejectedException("no such charge");
        }
```

#### F2 · L1 · Sev-1 · `int` overflow turns the balance check into a bypass (lines 40–41, 54)

**Mechanism.** `refundedMinor` and `amountMinor` are `int`. An IDR charge of 2,000,000,000 minor units (about 20 million rupiah, an ordinary B2B or electronics purchase) with 1,500,000,000 refunded, plus a 1,000,000,000 request, gives `newTotal = −1,794,967,296`. That is `< 2,000,000,000`, so the check passes and the gateway pays 1,000,000,000 more than remains. Line 54 then persists the negative total, so every later refund on that charge also passes.

**Evidence.** Probe P2: `-> SUCCEEDED; network paid 1,000,000,000, ledger refunded_minor = -1,794,967,296`.

**Comment (L7, short).** `issue (blocking):` `int` addition on line 40 wraps for large-denomination currencies. Concretely, 1.5 B + 1 B = −1,794,967,296, which passes the check and is then persisted on line 54. Rather than widening the local, could we let the conditional UPDATE (`tryReserve`) do the arithmetic in BIGINT and the comparison atomically? That fixes this and F3 together.

**Fix.** Never compute the new total in the application. `tryReserve` issues `UPDATE charges SET refunded_minor = refunded_minor + :amt WHERE id = ? AND refunded_minor + :amt <= amount_minor`:
```java
        if (!charges.tryReserve(charge.id(), req.amountMinor())) { // one conditional UPDATE, BIGINT math
            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
            throw new RefundRejectedException("amount exceeds refundable balance");
        }
```
Follow-up (non-blocking ticket): widen `refunded_minor`/`amount_minor` to `BIGINT` with an expand-then-contract migration.

#### F3 · L2 · Sev-1 · Per-JVM lock over state shared by six pods; lost update (lines 31, 40, 54; Javadoc 26–27)

**Mechanism.** `synchronized` coordinates threads inside one JVM. Two requests for the same charge on two pods both read `refunded = 0`, both pass, both pay, and both write `setRefunded(6000)`. The second write overwrites the first (a lost update), so the ledger understates what left the building. The window is the whole gateway round trip, so this is routine at production QPS, not a rare race. The Javadoc ("two concurrent partial refunds can never both pass the balance check") is false for the deployed topology. That makes it worse than no comment, because it tells future readers not to look.

**Evidence.** Probe P3: `over-refund in 20/20 trials; last trial network paid 12,000, ledger refunded_minor = 6,000`.

**Comment (L7, short).** `issue (blocking):` `synchronized` serializes threads in one pod, but we run six, and the charge row is shared. Two partial refunds on different pods both pass the check (interleaving attached), and the blind `setRefunded` loses one update. Suggest `tryReserve` (an atomic conditional UPDATE) and removing `synchronized`. Also, the Javadoc's thread-safety claim should go.

**Fix.** Same `tryReserve` block as F2; `refund` is no longer `synchronized`.

#### F4 · L2 · Sev-2 · Idempotency is check-then-act; the key is claimed after the payout (lines 32–35, 53)

**Mechanism.** The replay check reads `refunds.find(key)`, but the row is written only at line 53, after the gateway call. Two deliveries of the same request (a client retry landing on another pod, or a load-balancer retry) both miss the check. The gateway dedups by key, so the money moves once. But this service writes two records, calls `setRefunded` twice and publishes two `RefundIssued` events, and the ledger books the refund twice. Severity is Sev-2 rather than Sev-1 only because the gateway saved the money. The books are still wrong.

**Evidence.** Probe P4: `network paid 3,000 (gateway de-dup), duplicate RefundIssued events in 20/20 trials`.

**Comment (L7, short).** `issue (blocking):` the idempotency key is checked at line 32 but claimed at line 53, after the payout, so concurrent deliveries of one request both proceed. The gateway dedups the money, but we publish two events and the ledger double-counts. Suggest claiming the key first with `insertIfAbsent` (a unique constraint) as a PENDING row.

**Fix.**
```java
        RefundRecord prior = refunds.insertIfAbsent(claim); // unique key: races and replays converge here
        if (prior != null) {
            return replay(prior, merchantId, req);
        }
```
`replay` also rejects a key reused with a *different* body (different merchant, charge or amount). Stripe's public API documents the same rule for its idempotency keys.

#### F5 · L4 · Sev-2 · Lock held across the gateway's network call (lines 31, 46)

**Mechanism.** The monitor is held for the full gateway round trip, so a pod processes one refund at a time, at gateway latency. When the gateway browns out (2 s timeouts), each pod's refund throughput drops to 0.5/s. Request threads pile up behind the monitor, health checks time out, and the orchestrator restarts healthy-but-blocked pods into the same state. On virtual threads the picture changes but not the conclusion: since JDK 24, JEP 491 lets a virtual thread blocked in `synchronized` release its carrier, so it is no longer *pinning*, but the requests are still serialized behind the lock.

**Evidence.** Probe P5: 16 concurrent refunds with a 20 ms gateway take about 16 × 20 ms on the PR's code and about 20 ms on the fix (exact numbers below; one measured run).

**Comment (L7, short).** `issue (blocking):` the monitor is held across `gateway.refund()`, so every refund on a pod waits for the slowest gateway response. A gateway brownout becomes our outage. Once F2/F3 move into `tryReserve`, no lock is needed at all.

**Fix.** Remove `synchronized`. The fix holds no lock across I/O: not in the JVM, and not in the database. That is why `SELECT … FOR UPDATE` is the wrong fix ([01 Q4](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#11-bar-raiser-chains)).

#### F6 · L4 · Sev-1 · A timeout is reported as a failure and invites a duplicate payout (lines 47–49)

**Mechanism.** `GatewayTimeoutException` means the outcome is *unknown*; the interface says the refund "may or may not have executed." `GatewayDeclinedException` means it definitely did not execute. The PR maps both to `RefundFailedException("refund failed, please retry")`, an HTTP 502 saying "failed." Merchants' dashboards and many SDK integrations respond to "failed" by issuing a *new* refund with a *new* key, and the gateway pays again. Nothing in our database records the first attempt, so no balance check can stop the second.

**Evidence.** Probe P6: `timeout after payout -> RefundFailedException: refund failed, please retry; merchant retries with a new key -> SUCCEEDED; network paid 10,000 for a 5,000 charge`.

**Comment (L7, short).** `issue (blocking):` the catch on line 47 treats a timeout (outcome unknown, per the gateway's Javadoc) like a decline (definitely not executed), and tells the merchant "failed, please retry." A retry with a fresh key pays twice. Suggest three outcomes: decline releases the reservation and returns 4xx; timeout records UNKNOWN, keeps the reservation and returns 202; success commits.

**Fix.**
```java
        } catch (GatewayDeclinedException e) { // definitive: no money moved
            charges.release(charge.id(), req.amountMinor());
            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
            count("declined", charge);
            throw new RefundRejectedException("declined by network: " + e.getMessage());
        } catch (GatewayTimeoutException e) { // ambiguous: keep the reservation, never invite a new key
            RefundRecord unknown = claim.with(RefundRecord.Status.UNKNOWN, null);
            refunds.save(unknown);
            count("unknown", charge);
            return unknown;
        }
```
Follow-up: a reconciler that resolves UNKNOWN rows via `gateway.lookup(key)`, either to SUCCEEDED (commit plus outbox) or, after the 24 h dedupe window with no execution, to FAILED with the reservation released.

#### F7 · L3 · Sev-2 · Money moves before anything durable exists; three independent writes after it (lines 46, 53–57)

**Mechanism.** The order is: pay (46), then save the record (53), then update the ledger (54), then publish the event (56). A crash, deploy or primary failover between 46 and 53 leaves money moved with no row, no ledger update and no event, and no way to find it except by diffing the network's settlement file. A failure between 53 and 56 leaves a record with no event: the classic dual write.

**Evidence.** Probe P7: `DB failover after payout -> IllegalStateException: primary failover: write rejected; network paid 5,000; durable trace = NONE (unreconcilable)`. On the fix, the same fault leaves `PENDING` with the reservation held, and the reconciler finds the gateway reference.

**Comment (L7, short).** `issue (blocking):` the first durable write happens after the payout, so a failover at line 53 loses all trace of money that moved. Suggest claiming a PENDING row before the call (F4's fix gives us this), then committing the outcome and the event together with `saveWithOutbox`.

**Fix.** The PENDING claim (F4) plus the commit with the outbox:
```java
        RefundRecord done = claim.with(RefundRecord.Status.SUCCEEDED, gatewayRef);
        refunds.saveWithOutbox(done, "refunds.v1", Map.of("refundId", done.key(), "chargeId", charge.id(),
                "amountCents", req.amountMinor(), // existing consumers read this; keep it on v1
                "amountMinor", req.amountMinor(), "currency", charge.currency()));
```

#### F8 · L5 · Sev-1 · Field renamed on a live topic: the ledger books every refund as 0 (lines 55–57)

**Mechanism.** `refunds.v1` has a deployed consumer, the ledger, that reads `amountCents`. After this deploy the field is absent. A lenient JSON reader returns 0 or null and the ledger silently books zero-value refunds. A strict reader throws and stops the partition. The author's motive is right ("cents" is wrong for JPY's 0 and KWD's 3 decimal places), but the mechanism is a breaking change. Rollback doesn't repair the zeroed rows.

**Evidence.** Probe P8: `v1 ledger consumer reads amountCents = 0 (refund was 1,200)`.

**Comment (L7, short).** `issue (blocking):` the ledger consumes `refunds.v1` and reads `amountCents`, so after deploy it books every refund as 0. The rename is right in spirit. Could we make it additive (emit both on v1, deprecate `amountCents` in the schema, migrate the ledger, remove later) or publish `refunds.v2`? Separately, a schema-registry compatibility check in CI would catch this class automatically.

**Fix.** Both fields on v1 (see the F7 block). Follow-up: a BACKWARD/FULL compatibility check on the `refunds.*` subjects.

#### F9 · L7 · Sev-3 · Unbounded metric label (lines 48, 58)

**Mechanism.** `refund_id` makes every refund its own time series. At 1 M refunds/day that's 1 M new series per day: index bloat, query timeouts and, on shared backends, a noisy-neighbor outage. Prometheus's naming guide says not to do this.

**Evidence.** Probe P9: `500 refunds -> 500 distinct metric series` (fixed: 1).

**Comment (L7, short).** `issue (non-blocking):` `refund_id` as a label creates one series per refund. Suggest bounded labels (`outcome`, `currency`) and putting the id in logs or traces. A label-key allowlist in our metrics wrapper would prevent this class.

**Fix.**
```java
    private void count(String outcome, Charge charge) {
        metrics.increment("refunds.outcome", Map.of("outcome", outcome, "currency", charge.currency()));
    }
```

#### T1 · Tests that pin the bugs (test lines 53, 60–63)

`gatewayTimeoutIsRetryable` asserts that a timeout throws `RefundFailedException` (F6), and `publishesRefundIssuedEvent` asserts `amountMinor` only (F8). Against the fixed service, exactly these two fail. That is evidence they encode the defects, not the requirements. The remaining suite has no test with two service instances, no timeout-after-commit, no other merchant, no near-`MAX_VALUE` amounts. Those four scenarios cover F1–F4 and F6.

#### D1 · The Javadoc's thread-safety claim (lines 26–27)

"Two concurrent partial refunds can never both pass the balance check" is false for six pods. Misleading concurrency documentation is a correctness issue, because the next engineer trusts it. Delete it, or replace it with the real mechanism (the unique key plus the conditional UPDATE).

### 11.3 The refactored `RefundService`

```java
package com.acme.refunds;

import java.util.Map;

/**
 * Refund orchestration for the public Refunds API ({@code POST /v1/refunds}) and the support console.
 * Correctness comes from the database, not from the JVM: a unique key claims each request before money moves, a
 * conditional UPDATE reserves the balance, and the event commits with the refund row through the outbox.
 * No lock is held while the gateway is called.
 */
public final class RefundService {
    private final ChargeStore charges;
    private final RefundStore refunds;
    private final PaymentGateway gateway;
    private final Metrics metrics;

    public RefundService(ChargeStore charges, RefundStore refunds, PaymentGateway gateway, EventBus events,
                         Metrics metrics) {
        this.charges = charges;
        this.refunds = refunds;
        this.gateway = gateway;
        this.metrics = metrics; // events now leave through the outbox relay
    }

    /**
     * Refunds {@code req.amountMinor()} of a charge owned by {@code merchantId}. Returns SUCCEEDED, or UNKNOWN when
     * the gateway timed out (HTTP 202; the reconciler settles it through {@link PaymentGateway#lookup}).
     */
    public RefundRecord refund(String merchantId, RefundRequest req) {
        if (req.amountMinor() <= 0) {
            throw new RefundRejectedException("amount must be positive");
        }
        RefundRecord claim = new RefundRecord(req.idempotencyKey(), merchantId, req.chargeId(), req.amountMinor(),
                null, RefundRecord.Status.PENDING);
        RefundRecord prior = refunds.insertIfAbsent(claim); // unique key: races and replays converge here
        if (prior != null) {
            return replay(prior, merchantId, req);
        }
        Charge charge = charges.findForMerchant(merchantId, req.chargeId()); // another merchant's charge == missing
        if (charge == null) {
            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
            throw new RefundRejectedException("no such charge");
        }
        if (!charges.tryReserve(charge.id(), req.amountMinor())) { // one conditional UPDATE, BIGINT math
            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
            throw new RefundRejectedException("amount exceeds refundable balance");
        }
        String gatewayRef;
        try {
            gatewayRef = gateway.refund(charge.id(), req.amountMinor(), req.idempotencyKey());
        } catch (GatewayDeclinedException e) { // definitive: no money moved
            charges.release(charge.id(), req.amountMinor());
            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
            count("declined", charge);
            throw new RefundRejectedException("declined by network: " + e.getMessage());
        } catch (GatewayTimeoutException e) { // ambiguous: keep the reservation, never invite a new key
            RefundRecord unknown = claim.with(RefundRecord.Status.UNKNOWN, null);
            refunds.save(unknown);
            count("unknown", charge);
            return unknown;
        }
        RefundRecord done = claim.with(RefundRecord.Status.SUCCEEDED, gatewayRef);
        refunds.saveWithOutbox(done, "refunds.v1", Map.of("refundId", done.key(), "chargeId", charge.id(),
                "amountCents", req.amountMinor(), // existing consumers read this; keep it on v1
                "amountMinor", req.amountMinor(), "currency", charge.currency()));
        count("succeeded", charge);
        return done;
    }

    private static RefundRecord replay(RefundRecord prior, String merchantId, RefundRequest req) {
        if (!prior.merchantId().equals(merchantId) || !prior.chargeId().equals(req.chargeId())
                || prior.amountMinor() != req.amountMinor()) {
            throw new RefundRejectedException("idempotency key reused with a different request");
        }
        return prior; // may be PENDING: the client polls GET /v1/refunds/{key}
    }

    private void count(String outcome, Charge charge) {
        metrics.increment("refunds.outcome", Map.of("outcome", outcome, "currency", charge.currency()));
    }
}
```

**The fixed service with its updated tests: 9/9 pass (output, verified).**

```text
├─ JUnit Jupiter ✔
│  └─ RefundServiceTest ✔
│     ├─ partialRefundsAccumulate() ✔
│     ├─ nonPositiveAmountRejected() ✔
│     ├─ hugeAmountsDoNotOverflowTheBalanceCheck() ✔
│     ├─ fullRefundSucceeds() ✔
│     ├─ otherMerchantCannotRefund() ✔
│     ├─ publishesRefundIssuedEventThroughOutbox() ✔
│     ├─ gatewayTimeoutIsUnknownAndKeepsTheReservation() ✔
│     ├─ replayReturnsSameRecord() ✔
│     └─ twoPodsCannotOverRefund() ✔
[         9 tests found           ]
[         9 tests successful      ]
[         0 tests failed          ]
```

**The PR's original tests against the fixed service (output, verified).** Exactly the two tests that encode F6 and F8 fail:

```text
├─ JUnit Jupiter ✔
│  └─ RefundServiceTest ✔
│     ├─ partialRefundsAccumulate() ✔
│     ├─ publishesRefundIssuedEvent() ✘ expected: <1> but was: <0>
│     ├─ nonPositiveAmountRejected() ✔
│     ├─ gatewayTimeoutIsRetryable() ✘ Expected com.acme.refunds.RefundFailedException to be thrown, but nothing was thrown.
│     ├─ fullRefundSucceeds() ✔
│     └─ replayReturnsSameRecord() ✔
[         6 tests found           ]
[         4 tests successful      ]
[         2 tests failed          ]
```

### 11.4 Probe evidence

**Against the PR's code (output, verified; P5 is one measured run):**

```text
PR-00 probes against the PR's RefundService
P1 L6 m_evil refunds m_shop's charge -> SUCCEEDED; network paid 5,000
P2 L1 refund 1,000,000,000 when only 500,000,000 remains -> SUCCEEDED; network paid 1,000,000,000, ledger refunded_minor = -1,794,967,296
P3 L2 two pods, 6,000 + 6,000 on a 10,000 charge: over-refund in 20/20 trials; last trial network paid 12,000, ledger refunded_minor = 6,000
P4 L2 two pods, same key: network paid 3,000 (gateway de-dup), duplicate RefundIssued events in 20/20 trials
P5 L4 16 concurrent refunds, 20 ms gateway, one pod: 331 ms wall (one measured run)
P6 L4 timeout after payout -> RefundFailedException: refund failed, please retry; merchant retries with a new key -> SUCCEEDED; network paid 10,000 for a 5,000 charge
P7 L3 DB failover after payout -> IllegalStateException: primary failover: write rejected; network paid 5,000; durable trace = NONE (unreconcilable)
P8 L5 v1 ledger consumer reads amountCents = 0 (refund was 1,200)
P9 L7 500 refunds -> 500 distinct metric series
```

**Against the fixed code (output, verified; P5 is one measured run):**

```text
PR-00 probes against the fixed RefundService
P1 L6 m_evil refunds m_shop's charge -> RefundRejectedException: no such charge; network paid 0
P2 L1 refund 1,000,000,000 when only 500,000,000 remains -> RefundRejectedException: amount exceeds refundable balance; network paid 0, ledger refunded_minor = 1,500,000,000
P3 L2 two pods, 6,000 + 6,000 on a 10,000 charge: over-refund in 0/20 trials; last trial network paid 6,000, ledger refunded_minor = 6,000
P4 L2 two pods, same key: network paid 3,000 (gateway de-dup), duplicate RefundIssued events in 0/20 trials
P5 L4 16 concurrent refunds, 20 ms gateway, one pod: 21 ms wall (one measured run)
P6 L4 timeout after payout -> UNKNOWN; merchant retries with a new key -> RefundRejectedException: amount exceeds refundable balance; network paid 5,000 for a 5,000 charge
P7 L3 DB failover after payout -> IllegalStateException: primary failover: write rejected; network paid 5,000; durable trace = PENDING (reconciler finds gateway ref re_1)
P8 L5 v1 ledger consumer reads amountCents = 1,200 (refund was 1,200)
P9 L7 500 refunds -> 1 distinct metric series
```

<details><summary><b>The probe harness (Pr00Probes.java)</b></summary>

```java
package com.acme.refunds;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/**
 * Pr00Probes - production-shaped probes for PR-00. Compiled once against the PR's RefundService and once against
 * the fixed one; every probe builds fresh stores. Prints observable outcomes (money moved, ledger, events, series).
 */
public final class Pr00Probes {
    private static final class World {
        final ChargeStore charges = new ChargeStore();
        final RefundStore refunds = new RefundStore();
        final RecordingEventBus bus = new RecordingEventBus();
        final RecordingMetrics metrics = new RecordingMetrics();
        final FakeGateway gw;

        World(long gatewayLatencyMillis) {
            gw = new FakeGateway(gatewayLatencyMillis);
        }

        RefundService pod() { // one instance per JVM, i.e. per Kubernetes pod
            return new RefundService(charges, refunds, gw, bus, metrics);
        }

        List<RecordingEventBus.Event> events() {
            OutboxRelay.drain(refunds, bus);
            return bus.events;
        }
    }

    private static String n(long v) {
        return String.format(Locale.ROOT, "%,d", v);
    }

    private static String attempt(RefundService pod, String merchant, RefundRequest req) {
        try {
            return "-> " + pod.refund(merchant, req).status();
        } catch (RuntimeException e) {
            return "-> " + e.getClass().getSimpleName() + ": " + e.getMessage();
        }
    }

    public static void main(String[] args) throws Exception {
        System.out.println("PR-00 probes against the " + args[0] + " RefundService");
        idor();
        overflow();
        twoPodsTwoKeys();
        twoPodsSameKey();
        lockAcrossIo();
        ambiguousTimeout();
        failoverAfterPayout();
        v1Consumer();
        cardinality();
    }

    static void idor() {
        World w = new World(0);
        w.charges.insert(new Charge("ch_1", "m_shop", 5_000, 0, "USD"));
        String r = attempt(w.pod(), "m_evil", new RefundRequest("k1", "ch_1", 5_000));
        System.out.println("P1 L6 m_evil refunds m_shop's charge " + r + "; network paid " + n(w.gw.paidOut()));
    }

    static void overflow() {
        World w = new World(0);
        w.charges.insert(new Charge("ch_big", "m_shop", 2_000_000_000, 1_500_000_000, "IDR"));
        String r = attempt(w.pod(), "m_shop", new RefundRequest("k1", "ch_big", 1_000_000_000));
        System.out.println("P2 L1 refund 1,000,000,000 when only 500,000,000 remains " + r + "; network paid "
                + n(w.gw.paidOut()) + ", ledger refunded_minor = " + n(w.charges.find("ch_big").refundedMinor()));
    }

    /** Runs two refunds at the same instant on two pods that share the database. */
    private static void race(World w, RefundRequest a, RefundRequest b) throws Exception {
        List<RefundService> pods = List.of(w.pod(), w.pod());
        List<RefundRequest> reqs = List.of(a, b);
        CyclicBarrier start = new CyclicBarrier(2);
        ExecutorService pool = Executors.newFixedThreadPool(2);
        List<Future<?>> done = new ArrayList<>();
        for (int i = 0; i < 2; i++) {
            RefundService pod = pods.get(i);
            RefundRequest req = reqs.get(i);
            done.add(pool.submit(() -> {
                start.await();
                attempt(pod, "m_shop", req);
                return null;
            }));
        }
        for (Future<?> f : done) {
            f.get();
        }
        pool.shutdown();
    }

    static void twoPodsTwoKeys() throws Exception {
        int bad = 0;
        long paid = 0;
        long ledger = 0;
        for (int t = 0; t < 20; t++) {
            World w = new World(20);
            w.charges.insert(new Charge("ch_1", "m_shop", 10_000, 0, "USD"));
            race(w, new RefundRequest("ka", "ch_1", 6_000), new RefundRequest("kb", "ch_1", 6_000));
            paid = w.gw.paidOut();
            ledger = w.charges.find("ch_1").refundedMinor();
            bad += paid > 10_000 ? 1 : 0;
        }
        System.out.println("P3 L2 two pods, 6,000 + 6,000 on a 10,000 charge: over-refund in " + bad
                + "/20 trials; last trial network paid " + n(paid) + ", ledger refunded_minor = " + n(ledger));
    }

    static void twoPodsSameKey() throws Exception {
        int dup = 0;
        long paid = 0;
        for (int t = 0; t < 20; t++) {
            World w = new World(20);
            w.charges.insert(new Charge("ch_1", "m_shop", 10_000, 0, "USD"));
            RefundRequest req = new RefundRequest("k1", "ch_1", 3_000);
            race(w, req, req);
            paid = w.gw.paidOut();
            dup += w.events().size() > 1 ? 1 : 0;
        }
        System.out.println("P4 L2 two pods, same key: network paid " + n(paid)
                + " (gateway de-dup), duplicate RefundIssued events in " + dup + "/20 trials");
    }

    static void lockAcrossIo() throws Exception {
        World w = new World(20);
        RefundService pod = w.pod();
        int n = 16;
        for (int i = 0; i < n; i++) {
            w.charges.insert(new Charge("ch_" + i, "m_shop", 1_000, 0, "USD"));
        }
        CyclicBarrier start = new CyclicBarrier(n + 1);
        ExecutorService pool = Executors.newFixedThreadPool(n);
        List<Future<?>> done = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            RefundRequest req = new RefundRequest("k" + i, "ch_" + i, 1_000);
            done.add(pool.submit(() -> {
                start.await();
                attempt(pod, "m_shop", req);
                return null;
            }));
        }
        start.await();
        long t0 = System.nanoTime();
        for (Future<?> f : done) {
            f.get();
        }
        long ms = (System.nanoTime() - t0) / 1_000_000;
        pool.shutdown();
        System.out.println("P5 L4 16 concurrent refunds, 20 ms gateway, one pod: " + ms + " ms wall (one measured run)");
    }

    static void ambiguousTimeout() {
        World w = new World(0);
        w.charges.insert(new Charge("ch_1", "m_shop", 5_000, 0, "USD"));
        RefundService pod = w.pod();
        w.gw.timeoutAfterNextExecute(); // the network executes the refund, then the response is lost
        String first = attempt(pod, "m_shop", new RefundRequest("k1", "ch_1", 5_000));
        String retry = attempt(pod, "m_shop", new RefundRequest("k2", "ch_1", 5_000)); // dashboard mints a new key
        System.out.println("P6 L4 timeout after payout " + first + "; merchant retries with a new key " + retry
                + "; network paid " + n(w.gw.paidOut()) + " for a 5,000 charge");
    }

    static void failoverAfterPayout() {
        World w = new World(0);
        w.charges.insert(new Charge("ch_1", "m_shop", 5_000, 0, "USD"));
        w.gw.afterNextExecute(w.refunds::failNextWrite); // primary fails over right after the network pays
        String r = attempt(w.pod(), "m_shop", new RefundRequest("k1", "ch_1", 5_000));
        RefundRecord trace = w.refunds.find("k1");
        System.out.println("P7 L3 DB failover after payout " + r + "; network paid " + n(w.gw.paidOut())
                + "; durable trace = " + (trace == null ? "NONE (unreconcilable)" : trace.status()
                + " (reconciler finds gateway ref " + w.gw.lookup("k1") + ")"));
    }

    static void v1Consumer() {
        World w = new World(0);
        w.charges.insert(new Charge("ch_1", "m_shop", 5_000, 0, "USD"));
        w.pod().refund("m_shop", new RefundRequest("k1", "ch_1", 1_200));
        Map<String, Object> e = w.events().get(0).payload();
        long ledgerSees = ((Number) e.getOrDefault("amountCents", 0)).longValue(); // the deployed v1 consumer
        System.out.println("P8 L5 v1 ledger consumer reads amountCents = " + n(ledgerSees) + " (refund was 1,200)");
    }

    static void cardinality() {
        World w = new World(0);
        RefundService pod = w.pod();
        for (int i = 0; i < 500; i++) {
            w.charges.insert(new Charge("ch_" + i, "m_shop", 1_000, 0, "USD"));
            pod.refund("m_shop", new RefundRequest("k" + i, "ch_" + i, 1_000));
        }
        System.out.println("P9 L7 500 refunds -> " + w.metrics.series.size() + " distinct metric series");
    }
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/refunds-service/src/main/java/com/acme/refunds/RefundService.java b/refunds-service/src/main/java/com/acme/refunds/RefundService.java
index 5cc3790..008fa63 100644
--- a/refunds-service/src/main/java/com/acme/refunds/RefundService.java
+++ b/refunds-service/src/main/java/com/acme/refunds/RefundService.java
@@ -4,13 +4,14 @@ import java.util.Map;
 
 /**
  * Refund orchestration for the public Refunds API ({@code POST /v1/refunds}) and the support console.
- * Supports full and partial refunds. Requests are de-duplicated by idempotency key, so clients may safely retry.
+ * Correctness comes from the database, not from the JVM: a unique key claims each request before money moves, a
+ * conditional UPDATE reserves the balance, and the event commits with the refund row through the outbox.
+ * No lock is held while the gateway is called.
  */
 public final class RefundService {
     private final ChargeStore charges;
     private final RefundStore refunds;
     private final PaymentGateway gateway;
-    private final EventBus events;
     private final Metrics metrics;
 
     public RefundService(ChargeStore charges, RefundStore refunds, PaymentGateway gateway, EventBus events,
@@ -18,44 +19,63 @@ public final class RefundService {
         this.charges = charges;
         this.refunds = refunds;
         this.gateway = gateway;
-        this.events = events;
-        this.metrics = metrics;
+        this.metrics = metrics; // events now leave through the outbox relay
     }
 
     /**
-     * Refunds {@code req.amountMinor()} of a charge, in minor units (cents, yen, ...). Thread-safe: the method is
-     * synchronized, so two concurrent partial refunds can never both pass the balance check.
-     *
-     * @param merchantId the authenticated merchant, from the API key
+     * Refunds {@code req.amountMinor()} of a charge owned by {@code merchantId}. Returns SUCCEEDED, or UNKNOWN when
+     * the gateway timed out (HTTP 202; the reconciler settles it through {@link PaymentGateway#lookup}).
      */
-    public synchronized RefundRecord refund(String merchantId, RefundRequest req) {
-        RefundRecord existing = refunds.find(req.idempotencyKey());
-        if (existing != null) {
-            return existing; // replay: same key, same answer
+    public RefundRecord refund(String merchantId, RefundRequest req) {
+        if (req.amountMinor() <= 0) {
+            throw new RefundRejectedException("amount must be positive");
         }
-        Charge charge = charges.find(req.chargeId());
+        RefundRecord claim = new RefundRecord(req.idempotencyKey(), merchantId, req.chargeId(), req.amountMinor(),
+                null, RefundRecord.Status.PENDING);
+        RefundRecord prior = refunds.insertIfAbsent(claim); // unique key: races and replays converge here
+        if (prior != null) {
+            return replay(prior, merchantId, req);
+        }
+        Charge charge = charges.findForMerchant(merchantId, req.chargeId()); // another merchant's charge == missing
         if (charge == null) {
-            throw new RefundRejectedException("unknown charge " + req.chargeId());
+            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
+            throw new RefundRejectedException("no such charge");
         }
-        int newTotal = charge.refundedMinor() + req.amountMinor();
-        if (req.amountMinor() <= 0 || newTotal > charge.amountMinor()) {
+        if (!charges.tryReserve(charge.id(), req.amountMinor())) { // one conditional UPDATE, BIGINT math
+            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
             throw new RefundRejectedException("amount exceeds refundable balance");
         }
         String gatewayRef;
         try {
             gatewayRef = gateway.refund(charge.id(), req.amountMinor(), req.idempotencyKey());
-        } catch (GatewayTimeoutException | GatewayDeclinedException e) {
-            metrics.increment("refunds.failed", Map.of("refund_id", req.idempotencyKey()));
-            throw new RefundFailedException("refund failed, please retry", e);
+        } catch (GatewayDeclinedException e) { // definitive: no money moved
+            charges.release(charge.id(), req.amountMinor());
+            refunds.save(claim.with(RefundRecord.Status.FAILED, null));
+            count("declined", charge);
+            throw new RefundRejectedException("declined by network: " + e.getMessage());
+        } catch (GatewayTimeoutException e) { // ambiguous: keep the reservation, never invite a new key
+            RefundRecord unknown = claim.with(RefundRecord.Status.UNKNOWN, null);
+            refunds.save(unknown);
+            count("unknown", charge);
+            return unknown;
         }
-        RefundRecord rec = new RefundRecord(req.idempotencyKey(), merchantId, charge.id(), req.amountMinor(),
-                gatewayRef, RefundRecord.Status.SUCCEEDED);
-        refunds.save(rec);
-        charges.setRefunded(charge.id(), newTotal);
-        // "cents" was wrong for JPY and KWD; minor units are currency-agnostic.
-        events.publish("refunds.v1", Map.of("refundId", rec.key(), "chargeId", charge.id(),
+        RefundRecord done = claim.with(RefundRecord.Status.SUCCEEDED, gatewayRef);
+        refunds.saveWithOutbox(done, "refunds.v1", Map.of("refundId", done.key(), "chargeId", charge.id(),
+                "amountCents", req.amountMinor(), // existing consumers read this; keep it on v1
                 "amountMinor", req.amountMinor(), "currency", charge.currency()));
-        metrics.increment("refunds.succeeded", Map.of("refund_id", req.idempotencyKey()));
-        return rec;
+        count("succeeded", charge);
+        return done;
+    }
+
+    private static RefundRecord replay(RefundRecord prior, String merchantId, RefundRequest req) {
+        if (!prior.merchantId().equals(merchantId) || !prior.chargeId().equals(req.chargeId())
+                || prior.amountMinor() != req.amountMinor()) {
+            throw new RefundRejectedException("idempotency key reused with a different request");
+        }
+        return prior; // may be PENDING: the client polls GET /v1/refunds/{key}
+    }
+
+    private void count(String outcome, Charge charge) {
+        metrics.increment("refunds.outcome", Map.of("outcome", outcome, "currency", charge.currency()));
     }
 }
diff --git a/refunds-service/src/test/java/com/acme/refunds/RefundServiceTest.java b/refunds-service/src/test/java/com/acme/refunds/RefundServiceTest.java
index 47ee4b1..eca022c 100644
--- a/refunds-service/src/test/java/com/acme/refunds/RefundServiceTest.java
+++ b/refunds-service/src/test/java/com/acme/refunds/RefundServiceTest.java
@@ -4,6 +4,12 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 import static org.junit.jupiter.api.Assertions.assertSame;
 import static org.junit.jupiter.api.Assertions.assertThrows;
 
+import java.util.ArrayList;
+import java.util.List;
+import java.util.concurrent.CyclicBarrier;
+import java.util.concurrent.ExecutorService;
+import java.util.concurrent.Executors;
+import java.util.concurrent.Future;
 import org.junit.jupiter.api.BeforeEach;
 import org.junit.jupiter.api.Test;
 
@@ -50,16 +56,65 @@ class RefundServiceTest {
     }
 
     @Test
-    void gatewayTimeoutIsRetryable() {
+    void gatewayTimeoutIsUnknownAndKeepsTheReservation() {
         gateway.timeoutAfterNextExecute();
-        assertThrows(RefundFailedException.class,
-                () -> service.refund("m_shop", new RefundRequest("key-1", "ch_1", 1_000)));
+        RefundRecord rec = service.refund("m_shop", new RefundRequest("key-1", "ch_1", 5_000));
+        assertEquals(RefundRecord.Status.UNKNOWN, rec.status());
+        assertThrows(RefundRejectedException.class, // an impatient retry with a fresh key cannot pay twice
+                () -> service.refund("m_shop", new RefundRequest("key-2", "ch_1", 5_000)));
+        assertEquals(5_000, gateway.paidOut());
     }
 
     @Test
-    void publishesRefundIssuedEvent() {
+    void publishesRefundIssuedEventThroughOutbox() {
         service.refund("m_shop", new RefundRequest("key-1", "ch_1", 1_200));
+        OutboxRelay.drain(refunds, bus);
         assertEquals(1, bus.events.size());
+        assertEquals(1_200, bus.events.get(0).payload().get("amountCents")); // v1 consumers keep working
         assertEquals(1_200, bus.events.get(0).payload().get("amountMinor"));
     }
+
+    @Test
+    void otherMerchantCannotRefund() {
+        assertThrows(RefundRejectedException.class,
+                () -> service.refund("m_evil", new RefundRequest("key-1", "ch_1", 5_000)));
+        assertEquals(0, gateway.paidOut());
+    }
+
+    @Test
+    void hugeAmountsDoNotOverflowTheBalanceCheck() {
+        charges.insert(new Charge("ch_big", "m_shop", 2_000_000_000, 1_500_000_000, "IDR"));
+        assertThrows(RefundRejectedException.class,
+                () -> service.refund("m_shop", new RefundRequest("key-1", "ch_big", 1_000_000_000)));
+    }
+
+    @Test
+    void twoPodsCannotOverRefund() throws Exception {
+        FakeGateway slow = new FakeGateway(20);
+        List<RefundService> pods = List.of(
+                new RefundService(charges, refunds, slow, bus, new RecordingMetrics()),
+                new RefundService(charges, refunds, slow, bus, new RecordingMetrics()));
+        CyclicBarrier start = new CyclicBarrier(2);
+        ExecutorService pool = Executors.newFixedThreadPool(2);
+        List<Future<?>> done = new ArrayList<>();
+        for (int i = 0; i < 2; i++) {
+            RefundService pod = pods.get(i);
+            String key = "key-" + i;
+            done.add(pool.submit(() -> {
+                start.await();
+                try {
+                    pod.refund("m_shop", new RefundRequest(key, "ch_1", 3_000));
+                } catch (RefundRejectedException expectedForOne) {
+                    // the loser of the conditional UPDATE
+                }
+                return null;
+            }));
+        }
+        for (Future<?> f : done) {
+            f.get();
+        }
+        pool.shutdown();
+        assertEquals(3_000, slow.paidOut());
+        assertEquals(3_000, charges.find("ch_1").refundedMinor());
+    }
 }
```

</details>

---

## 12. Failure modes of the scan itself

| Failure mode | What happens | Prevention |
|---|---|---|
| **Layer skipping** | You go deep on L2 because you love concurrency and never open L5 | Pass 2 is shallow and visits every layer before any proof |
| **Instance-only concurrency** | You reason about threads and miss pods, retries and consumers | Ask "how many of me run, and who replays my inputs?" in Pass 1 |
| **Two-outcome thinking** | Every remote error is treated as failure | For every external call, write down all three outcomes (§6) |
| **Diff-only compatibility** | You check the producer and forget the deployed reader | Find the readers (registry, ACLs, grep) before judging a rename |
| **Authentication ≠ authorization** | "It's behind auth" ends the security pass | Ask "whose object is this, and where is that compared?" |
| **Big-O blinders** | Algorithmic complexity checked, cardinality ignored | Ask "what grows with traffic or tenants, and what bounds it?" |
| **Defect relocation** | Your fix moves the bug (row lock across I/O; a retry that re-pays) | Run every proposed fix through the seven layers before you say it |
| **Proof by pattern** | "That's a race" with no interleaving | Draw the two-column table, or give the exact value |
| **Precision collapse** | Flagging every `synchronized` and every `int` | Check the false-positive notes per layer; ask the deciding question first |
| **Ignoring what tools catch** | Minutes spent finding a boxed `==` | Name the tool ("Error Prone flags this") and move on |

---

## 13. Bar-raiser chains

<details><summary><b>Q1 · "Walk me through how you'd scan a diff you've never seen, in the first two minutes."</b></summary>

**Initial Prompt.** Process articulation.

**L5 Answer.** "I'd start reading from the top of the first file and look for anything suspicious."

**Why L5 Stalls.** No triage. The first file is often a DTO or config, and the Sev-1 sits in the third file's second hunk.

**L7 Answer.** "Ticket first: I list the contracts it changes (callers, instance count, retry semantics, readers of the output, data shape). Then the file list: a schema or migration file moves compatibility to the top. Then I score hunks for state mutation, process boundary, contract change and trust boundary, and start with the highest. Within those I run a shallow pass over all seven layers, writing suspicions down without proving them, so no layer is skipped. Proofs start at about minute 10."

</details>

<details><summary><b>Q2 · "Is `ConcurrentHashMap` enough to make this cache thread-safe?" (a check-then-act over CHM)</b></summary>

**Initial Prompt.** Distinguishing thread-safe operations from thread-safe compound actions.

**L5 Answer.** "Yes, CHM is thread-safe."

**Why L5 Stalls.** Each method is atomic; the *sequence* `containsKey` → `put` is not. The demo shows 16 loads for one key.

**L7 Answer.** "Each call is atomic; the decision spanning two calls isn't. Use `computeIfAbsent`, but note it holds a bin lock while the mapping function runs, so a slow load blocks unrelated keys in the same bin. For slow loads I'd store a `CompletableFuture` in the map (`computeIfAbsent(k, x -> supplyAsync(load))`), so the lock is held only to install the future. And if the cache is per-pod but the loaded value must be unique cluster-wide, CHM isn't the right layer at all."

</details>

<details><summary><b>Q3 · "When is a JVM lock correct in a multi-replica service?"</b></summary>

**Initial Prompt.** Lock scope vs state scope.

**L5 Answer.** "Never. Always use a distributed lock."

**Why L5 Stalls.** Overcorrects. JVM locks are correct for state that lives in the JVM. Distributed locks without fencing are themselves unsafe (Kleppmann's fencing-token argument).

**L7 Answer.** "A lock is correct when its scope matches the scope of the state it guards. A JVM lock is right for an in-memory structure that is per-pod by design: a local cache, a connection pool, a rate-limiter shard. For state in a database, use the database's atomicity: a conditional UPDATE, a unique constraint, or a serializable transaction held briefly. If I truly need mutual exclusion across processes around an external side effect, a lease is not enough. The resource must reject stale holders using a fencing token, otherwise a paused lease holder writes after its lease expired."

</details>

<details><summary><b>Q4 · "The PR adds a retry with exponential backoff around this payment call. Approve?"</b></summary>

**Initial Prompt.** Retries vs idempotency vs amplification.

**L5 Answer.** "Yes, retries with backoff improve reliability."

**Why L5 Stalls.** Retrying a non-idempotent, money-moving call duplicates payments. Retrying at another layer multiplies load. Backoff without jitter synchronizes clients.

**L7 Answer.** "Only if three things hold. (1) The call is idempotent: the *same* key is sent on every attempt, and the dependency dedupes for longer than our retry horizon. (2) This is the only layer that retries. AWS's guidance is to retry at a single point in the stack, and their five-layer example amplifies database load 243×. (3) Backoff has jitter and is capped by a retry budget or token bucket, so a dependency outage doesn't turn into a self-inflicted DDoS. Also: a timeout on the final attempt is still *unknown*, not failed."

</details>

<details><summary><b>Q5 · "Adding a value to an enum is backward compatible, right?"</b></summary>

**Initial Prompt.** Compatibility depth.

**L5 Answer.** "Yes, adding is always safe; only removing breaks things."

**Why L5 Stalls.** Adding is safe only if every deployed reader is *tolerant*. A strict `valueOf` reader throws (a poison pill), and an ordinal-persisted enum with a mid-list insertion silently remaps existing rows. Both are demonstrated above.

**L7 Answer.** "It's forward-incompatible for strict readers and corrupting for ordinal storage. Safe sequence: deploy tolerant readers first (unknown maps to a default plus a metric), and persist names, not ordinals (`EnumType.STRING`; the JPA default is ORDINAL). Only then start emitting the new value. Append, never insert. In Protobuf, also keep 0 as an `UNSPECIFIED` value so missing fields don't look like a real state."

</details>

<details><summary><b>Q6 · "The endpoint is behind our API gateway with OAuth. Why are you flagging authorization?"</b></summary>

**Initial Prompt.** Authentication vs object-level authorization.

**L5 Answer.** "Fair point, if the gateway checks the token then it's fine."

**Why L5 Stalls.** The token proves *who* is calling; it says nothing about whether *that* caller owns charge `ch_123`. OWASP ranks broken object-level authorization first among API risks for exactly this reason.

**L7 Answer.** "The gateway authenticates; it can't know which charges belong to which merchant. That check needs the object, so it lives where the object is loaded. I'd put the owner in the query (`findForMerchant`), return the same response for 'not yours' and 'doesn't exist' so IDs can't be probed, and add a test that uses another merchant's key. If there's a central authorization layer, I'd confirm this route is covered by a policy that checks ownership, not just the scope."

</details>

<details><summary><b>Q7 · "Your C++ fix for the length check is `if (len16 <= sizeof(buf))`. What did you miss?"</b></summary>

**Initial Prompt.** Checking the value that's used.

**L5 Answer.** "Nothing, that's a bounds check."

**Why L5 Stalls.** The check is on the *truncated* 16-bit value; the copy uses the original `size_t`. 65,552 becomes 16 and passes. The check and the use must be on the same value and type.

**L7 Answer.** "Check the original `size_t`, before any narrowing, and copy exactly the checked length. Better, make it structural: parse into a `std::span`, take `first(n)` only after validating `n`, and reject frames whose declared length doesn't match the bytes actually received. Then fuzz the parser with libFuzzer under ASan, because length-confusion bugs are what fuzzers find best. And treat internally generated input the same way. Cloudflare's November 2025 remediation was to harden ingestion of internally generated config files the same way as user input."

</details>

<details><summary><b>Q8 · "How do you prioritize when you find more than you can discuss?"</b></summary>

**Initial Prompt.** Severity calculus.

**L5 Answer.** "Crashes first, then everything else."

**Why L5 Stalls.** Crashes are loud and self-reporting. The defects that do the most damage are often silent: zeroed amounts, lost updates, cross-tenant reads.

**L7 Answer.** "Impact × likelihood × detectability × reversibility. Money, security and silent corruption beat availability; availability beats cost; cost beats style. Within a tier, prefer the defect normal traffic triggers over the one that needs a failover. In PR-00 that gives F1 (exploitable today), F8 (silent from the first refund), F3 and F6 (money, routine), F2 (money, needs large amounts), then F4, F5, F7, then F9. I'd also say out loud that five of these are one fix."

</details>

<details><summary><b>Q9 · "What's the difference between a check-then-act race and a data race?"</b></summary>

**Initial Prompt.** Precision of vocabulary (C++ and Java memory models).

**L5 Answer.** "They're the same thing."

**Why L5 Stalls.** Conflating them leads to wrong fixes. Making a field `volatile` or atomic fixes a data race but not a check-then-act.

**L7 Answer.** "A data race is a memory-model property: two unsynchronized accesses to the same location, at least one a write. In C++ that's undefined behavior; in Java it gives weak, but defined, guarantees. A check-then-act race is a logic property: each access can be perfectly synchronized and the *decision* still goes stale. PR-00's F3 involves no data race at all; every access is synchronized or atomic in the database. It's a race on the business invariant. TSan finds the first kind on exercised paths. Only reasoning, or a targeted interleaving test, finds the second."

</details>

<details><summary><b>Q10 · "Which of the 2024–2025 outages in §1.4 would a code reviewer realistically have caught?"</b></summary>

**Initial Prompt.** Honest limits of review.

**L5 Answer.** "All of them, if the reviewer was careful."

**Why L5 Stalls.** Overclaims. Some of these defects spanned systems and data no single diff showed.

**L7 Answer.** "Partly, and that's the point of asking the boundary questions. The Google Cloud change was a code path without error handling or a feature flag, a direct L1/L3 review question on the diff. The Cloudflare limit-plus-panic is catchable when reviewing the consumer ('what happens past 200 features?'), though the trigger was a database permission change in another system. The AWS race lived in the interaction of independently correct components, so a diff review catches it only if someone asks 'what makes this check still true at the act?', which is exactly the L2 question. CrowdStrike's mismatch needed someone to ask where field counts were validated. Review reduces these classes; it doesn't replace staged rollouts, flags, fuzzing and invariant monitoring, and an L7 says so."

</details>

---

## 14. Checklist: the 7-layer card

Print this; run it on every PR in Folders 02–05.

- [ ] **Map (minute 2):** contracts changed (callers, instances, retries, readers, data shape); hunks scored; top hunk chosen.
- [ ] **L1 Correctness:** largest/smallest/empty/null values; identity vs value equality; units; overflow feeding checks, sizes or money; time zones.
- [ ] **L2 Concurrency:** every check-then-act; lock scope vs state scope (threads *and* pods); lock order; idempotency claimed *before* side effects.
- [ ] **L3 Failure paths:** every acquire has a release on the throw path; the first durable write precedes the irreversible side effect; dual writes go through an outbox.
- [ ] **L4 I/O:** every remote call has a deadline; three outcomes classified; no lock (JVM or DB) across I/O; retries at one layer, same key, with jitter and a budget.
- [ ] **L5 Compatibility:** deployed readers identified; additive changes only; enums tolerant and persisted by name; structs serialized explicitly.
- [ ] **L6 Security:** authorization per object (owner in the query); trust context changes reviewed; sizes, paths and IDs validated on the type that's used.
- [ ] **L7 Operability:** bounded queues, caches, labels, retries and fan-out; N+1; flags/kill switches; the dashboard that would show this failing.
- [ ] **Prove:** a mechanism plus a number or interleaving for each Sev-1.
- [ ] **Unify:** which findings share a root cause? Is there one fix?
- [ ] **Re-scan the fix:** does it relocate the defect?
- [ ] **Tests:** which tests pin bugs; which scenarios are missing.

---

## 15. References

- Amazon Web Services: *Summary of the Amazon DynamoDB Service Disruption in the Northern Virginia (US-EAST-1) Region* (October 2025). https://aws.amazon.com/message/101925/
- Cloudflare: *Cloudflare outage on November 18, 2025.* https://blog.cloudflare.com/18-november-2025-outage/
- Google Cloud Service Health: *Multiple GCP products are experiencing Service issues* (incident report, June 12, 2025). https://status.cloud.google.com/incidents/ow5i3PPK96RduMcb1SsW
- CrowdStrike: *Channel File 291 Incident Root Cause Analysis* (August 6, 2024). https://www.crowdstrike.com/wp-content/uploads/2024/08/Channel-File-291-Incident-Root-Cause-Analysis-08.06.2024.pdf
- AWS Builders' Library: *Timeouts, retries, and backoff with jitter.* https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/
- Martin Kleppmann: *How to do distributed locking* (fencing tokens). https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html
- Stripe API reference: *Idempotent requests* (same key → same result; parameters compared; keys pruned after ≥ 24 h). https://docs.stripe.com/api/idempotent_requests
- OpenJDK: *JEP 491: Synchronize Virtual Threads without Pinning* (delivered in JDK 24). https://openjdk.org/jeps/491
- Jakarta Persistence 3.2 API: `@Enumerated` (`value()` defaults to `ORDINAL`). https://jakarta.ee/specifications/persistence/3.2/apidocs/jakarta.persistence/jakarta/persistence/Enumerated.html
- Protocol Buffers: *Proto Best Practices* (don't re-use tag numbers; reserve deleted fields). https://protobuf.dev/best-practices/dos-donts/
- Confluent: *Schema Evolution and Compatibility for Schema Registry.* https://docs.confluent.io/platform/current/schema-registry/fundamentals/schema-evolution.html
- OWASP API Security Top 10 (2023): *API1:2023 Broken Object Level Authorization.* https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
- OWASP Top 10:2025. https://owasp.org/Top10/2025/
- Prometheus: *Metric and label naming.* https://prometheus.io/docs/practices/naming/
- MITRE CWE: CWE-367 TOCTOU https://cwe.mitre.org/data/definitions/367.html · CWE-190 Integer Overflow https://cwe.mitre.org/data/definitions/190.html · CWE-191 Integer Underflow https://cwe.mitre.org/data/definitions/191.html · CWE-197 Numeric Truncation https://cwe.mitre.org/data/definitions/197.html · CWE-401 Missing Release of Memory https://cwe.mitre.org/data/definitions/401.html · CWE-833 Deadlock https://cwe.mitre.org/data/definitions/833.html · CWE-639 Authorization Bypass Through User-Controlled Key https://cwe.mitre.org/data/definitions/639.html · CWE-22 Path Traversal https://cwe.mitre.org/data/definitions/22.html
- C++ Core Guidelines (RAII, `CP.20`/`CP.21` on lock scoping). https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
- Within this KB: [01 · How rounds are graded](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md) · [03 · High-leverage communication](03-high-leverage-communication-mentoring-tone-vs-blocking-nitpicks.md) · [README](../README.md)
