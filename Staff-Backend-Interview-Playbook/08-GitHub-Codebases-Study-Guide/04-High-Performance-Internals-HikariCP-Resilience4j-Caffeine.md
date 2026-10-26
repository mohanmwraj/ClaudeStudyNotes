# 8.4 High-Performance Internals: HikariCP, Resilience4j, Caffeine

> **Verified 2026-10-25.** Excerpts are quoted from each project's default branch on that date: HikariCP `dev` (tags up to `HikariCP-7.1.0`; the labs in this kit used 7.0.2), Resilience4j `master` (2.4.0 jars verified with `javap` in [6.1](../06-Resilience-Caching-Kafka/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)), Caffeine `master` (3.3.1 jar verified in [6.3](../06-Resilience-Caching-Kafka/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)). All three are Apache-2.0 licensed; excerpts are short and attributed.
>
> **Go deeper:** sibling kit [5.1 JDBC & HikariCP](../../Java-Backend-Master-Reference/05-Persistence-JPA-Hibernate/01-JDBC-HikariCP-Connection-Pooling.md), [3.3 lock-free CAS](../../Java-Backend-Master-Reference/03-Concurrency-Loom/03-Lock-Free-CAS-Atomics.md), [1.3 object layout & mechanical sympathy](../../Java-Backend-Master-Reference/01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md).

---

## 0. Why these three 🔥

They sit on the hot path of every request (a connection borrow, a breaker check, a cache lookup), so their authors optimized for **contention** and **cache-line behavior**, not just big-O. Reading them teaches a small set of techniques you can name in a design review:

| Technique | HikariCP | Resilience4j | Caffeine |
|---|---|---|---|
| Avoid shared contention: try a thread-local or per-entry path first | Thread-local list of recently used connections | — | Striped read buffers |
| CAS on a small state word instead of locking a collection | `compareAndSet(NOT_IN_USE, IN_USE)` per entry | `AtomicReference<State>` swap | Drain-status CAS |
| Immutable state objects replaced atomically | — | Breaker state, rate-limiter `State` | — |
| Accept loss where it's harmless | — | — | **Lossy** read buffer (dropped access events) |
| Batch the bookkeeping, do it under `tryLock` | Housekeeper thread | — | `maintenance()` under `evictionLock` |
| Jitter to avoid synchronized events | `maxLifetime` variance up to 25 % | — | (same idea as cache TTL jitter, [6.4](../06-Resilience-Caching-Kafka/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md)) |
| Shape data structures to the access pattern | `FastList`: reverse scan, identity compare | Circular array + running totals | Sketch counters within one 64-byte block |

---

## 1. HikariCP: `ConcurrentBag` 🧊

### 1.1 The data structure

`src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java` (fields):

```java
private final CopyOnWriteArrayList<T> sharedList;        // every connection in the pool
private final ThreadLocal<List<Object>> threadLocalList; // connections THIS thread used recently
private final AtomicInteger waiters;                     // threads currently waiting for a connection
private final SynchronousQueue<T> handoffQueue;          // direct hand-off from returner to waiter (fair)
```

Each pool entry carries its own state word, changed only by CAS:

```java
int STATE_NOT_IN_USE = 0;
int STATE_IN_USE = 1;
int STATE_REMOVED = -1;
int STATE_RESERVED = -2;
```

Borrowed connections are **not removed** from any collection. "Borrowing" is just flipping the entry's state from `NOT_IN_USE` to `IN_USE`. There's no queue to lock and no node allocation.

### 1.2 `borrow`: three tiers, cheapest first

```java
public T borrow(long timeout, final TimeUnit timeUnit) throws InterruptedException
{
   // Try the thread-local list first
   final var list = threadLocalList.get();
   for (var i = list.size() - 1; i >= 0; i--) {
      final var entry = list.remove(i);
      …
      if (bagEntry != null && bagEntry.compareAndSet(STATE_NOT_IN_USE, STATE_IN_USE)) {
         return bagEntry;
      }
   }

   // Otherwise, scan the shared list ... then poll the handoff queue
   final var waiting = waiters.incrementAndGet();
   try {
      for (T bagEntry : sharedList) {
         if (bagEntry.compareAndSet(STATE_NOT_IN_USE, STATE_IN_USE)) {
            // If we may have stolen another waiter's connection, request another bag add.
            if (waiting > 1) {
               listener.addBagItem(waiting - 1);
            }
            return bagEntry;
         }
      }

      listener.addBagItem(waiting);
      …
      do {
         final T bagEntry = handoffQueue.poll(timeout, NANOSECONDS);
         if (bagEntry == null || bagEntry.compareAndSet(STATE_NOT_IN_USE, STATE_IN_USE)) {
            return bagEntry;
         }
         …
      } while (timeout > 10_000);
      return null;
   }
   finally {
      waiters.decrementAndGet();
   }
}
```

1. **Thread-local**: the connection this thread returned last time is likely still idle and still warm in this core's cache. One CAS, no shared memory traffic.
2. **Shared scan**: a lock-free iteration over a `CopyOnWriteArrayList` (cheap to read, expensive to modify, and connections are added and removed rarely). Thread-local entries are just references into the same entries, so another thread can "steal" an idle one with the same CAS.
3. **Hand-off**: register as a waiter, ask the pool to add a connection (`listener.addBagItem`), then wait on a **fair** `SynchronousQueue` for a returning connection.

### 1.3 `requite`: give it back, preferably straight to a waiter

```java
public void requite(final T bagEntry)
{
   bagEntry.setState(STATE_NOT_IN_USE);

   final var isVirtualThread = isCurrentThreadVirtual();
   for (int i = 1, waiting = waiters.get(); waiting > 0; i++, waiting = waiters.get()) {
      if (bagEntry.getState() != STATE_NOT_IN_USE || handoffQueue.offer(bagEntry)) {
         return;
      }
      else if (isVirtualThread || (i & 0xff) == 0xff || (waiting > 1 && i % waiting == 0)) {
         parkNanos(MICROSECONDS.toNanos(10));
      }
      else {
         Thread.yield();
      }
   }

   final var threadLocalEntries = this.threadLocalList.get();
   if (threadLocalEntries.size() < 16) {
      threadLocalEntries.add(useWeakThreadLocals ? new WeakReference<>(bagEntry) : bagEntry);
   }
}
```

* If someone is waiting, the returner **hands the connection directly** to them. That's fairness under pressure.
* If the entry was already grabbed by a scanning thread (state no longer `NOT_IN_USE`), stop.
* On the `dev` branch the spin backs off with `parkNanos(10 µs)` **whenever the returning thread is virtual**; platform threads mostly `Thread.yield()` and only park periodically. (The code shows the switch, not the reasoning; a reasonable reading is that a short park is a more predictable back-off for a virtual thread than a yield to its scheduler.)
* Otherwise, remember the connection in this thread's list (at most 16 entries; weak references when HikariCP is loaded by a non-system class loader, to avoid leaks in app servers).

### 1.4 `FastList`: a list shaped to one access pattern

`ProxyConnection` tracks open `Statement`s in a `FastList` so it can close them when the connection is returned:

```java
public boolean remove(Object element)
{
   for (var index = size - 1; index >= 0; index--) {
      if (element == elementData[index]) {
         …
```

Statements are usually closed in **reverse order of creation**, so scanning from the tail finds them immediately; `==` avoids `equals()` calls; `get()` skips the range check. That's tiny per call, but this code runs on every statement of every request.

### 1.5 `HikariPool.getConnection`: the liveness shortcut, and jitter

```java
private final long aliveBypassWindowMs = Long.getLong("com.zaxxer.hikari.aliveBypassWindowMs", MILLISECONDS.toMillis(500));
…
var poolEntry = connectionBag.borrow(timeout, MILLISECONDS);
…
if (poolEntry.isMarkedEvicted() || (elapsedMillis(poolEntry.lastAccessed, now) > aliveBypassWindowMs && isConnectionDead(poolEntry.connection))) {
```

A connection used within the last **500 ms** isn't re-validated, which saves a round trip on busy pools. And in `createPoolEntry`:

```java
// default variance upto 25% of the maxLifetime (random)
final var variance = maxLifetime > 10_000L ? ThreadLocalRandom.current().nextLong( maxLifetime / lifeTimeVarianceFactor ) : 0L;
…
// variance up to 20% of the heartbeat time
final var variance = ThreadLocalRandom.current().nextLong(keepaliveTime / 5);
```

Connections created together (at startup) would otherwise all expire together and reconnect in one burst: the same synchronized-expiry problem as cache TTLs ([6.4 §3.1](../06-Resilience-Caching-Kafka/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md)).

### 1.6 Reading questions

1. With **virtual threads**, each request typically runs on a new thread. How often does the thread-local tier hit then? What does that imply for the borrow path?
2. Why a `CopyOnWriteArrayList` and not a `ConcurrentLinkedQueue` for `sharedList`?
3. What happens to a connection that's borrowed and never returned? (The class comment: borrowed items are never removed from a collection, so they're never garbage-collected. That's why there's leak detection.)

---

## 2. Resilience4j 🧊

### 2.1 State transitions: one `AtomicReference`

`resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/internal/CircuitBreakerStateMachine.java`:

```java
private void stateTransition(State newState,
    UnaryOperator<CircuitBreakerState> newStateGenerator) {
    CircuitBreakerState previousState = stateReference.getAndUpdate(currentState -> {
        StateTransition.transitionBetween(getName(), currentState.getState(), newState);
        currentState.preTransitionHook();
        return newStateGenerator.apply(currentState);
    });
    publishStateTransitionEvent(
        StateTransition.transitionBetween(getName(), previousState.getState(), newState));
}
```

A good code-review question: `AtomicReference.getAndUpdate`'s Javadoc says the function **"should be side-effect-free, since it may be re-applied when attempted updates fail due to contention among threads."** This updater calls `preTransitionHook()` and builds a new state (which can schedule tasks). What happens if two threads race to transition at the same moment? Reasoning through that, and where the design accepts it, is exactly the kind of depth a bar-raiser enjoys.

### 2.2 The count-based window

`resilience4j-core/src/main/java/io/github/resilience4j/core/metrics/FixedSizeSlidingWindowMetrics.java`:

```java
public Snapshot record(long duration, TimeUnit durationUnit, Outcome outcome) {
    lock.lock();

    try {
        totalAggregation.record(duration, durationUnit, outcome);
        moveWindowByOne().record(duration, durationUnit, outcome);
        return new SnapshotImpl(totalAggregation);
    } finally {
        lock.unlock();
    }
}

private Measurement moveWindowByOne() {
    moveHeadIndexByOne();
    Measurement latestMeasurement = getLatestMeasurement();
    totalAggregation.removeBucket(latestMeasurement);
    latestMeasurement.reset();
    return latestMeasurement;
}
```

O(1) per call: add the new outcome to the running totals, subtract the evicted slot's outcome, reuse the slot. The `ReentrantLock` is the default `SYNCHRONIZED` strategy; the lock-free variant is opt-in ([6.1 §1](../06-Resilience-Caching-Kafka/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)).

### 2.3 The rate limiter is a fixed window: proof in code

`resilience4j-ratelimiter/src/main/java/io/github/resilience4j/ratelimiter/internal/AtomicRateLimiter.java`:

```java
long currentNanos = currentNanoTime();
long currentCycle = currentNanos / cyclePeriodInNanos;

long nextCycle = activeState.activeCycle;
int nextPermissions = activeState.activePermissions;
if (nextCycle != currentCycle) {
    long elapsedCycles = currentCycle - nextCycle;
    long accumulatedPermissions = elapsedCycles * permissionsPerCycle;
    nextCycle = currentCycle;
    nextPermissions = (int) min(nextPermissions + accumulatedPermissions,
        permissionsPerCycle);
}
```

Time is cut into whole cycles; on a new cycle permissions jump back to (at most) `permissionsPerCycle`. Negative permissions (reservations by waiting callers) are repaid by elapsed cycles. A token bucket would refill continuously instead. That's the code behind the measured 2× burst across a boundary ([6.2 §2.1](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)).

---

## 3. Caffeine 🧊

### 3.1 The frequency sketch, in the author's words

`caffeine/src/main/java/com/github/benmanes/caffeine/cache/FrequencySketch.java` (class comment, excerpts):

> *"This class maintains a 4-bit CountMinSketch with periodic aging to provide the popularity history for the TinyLfu admission policy."*
>
> *"The counter matrix is represented as a single-dimensional array holding 16 counters per slot. A fixed depth of four balances the accuracy and cost … the array's length equals the maximum number of entries in the cache, increased to the closest power-of-two."*
>
> *"To improve hardware efficiency, an item's counters are constrained to a 64-byte block, which is the size of an L1 cache line … the typical cost is only one memory access."*

And `ensureCapacity`: the aging sample is `10 × maximum` entries. The aging step:

```java
void reset() {
  @Var long count = 0;
  for (int i = 0; i < table.length; i++) {
    count += Long.bitCount(table[i] & ONE_MASK);
    table[i] = (table[i] >>> 1) & RESET_MASK;      // halve all sixteen 4-bit counters in one shift + mask
  }
  size = Math.max(0, (int) ((size - (count >>> 2)) >>> 1));
}
```

Memory: one `long` (8 bytes) per cache entry, rounded to a power of two. Halving sixteen counters is one shift and one mask per `long`.

### 3.2 Admission, with the attack it defends against

`BoundedLocalCache.java`:

```java
@GuardedBy("evictionLock")
boolean admit(Object candidateKeyRef, Object victimKeyRef) {
  int candidateFreq = frequencySketch().frequency(candidateKeyRef);
  int victimFreq = frequencySketch().frequency(victimKeyRef);
  if (candidateFreq > victimFreq) {
    return true;
  } else if (candidateFreq >= ADMIT_HASHDOS_THRESHOLD) {
    // The maximum frequency is 15 and halved to 7 after a reset to age the history. An attack
    // exploits that a hot candidate is rejected in favor of a hot victim. The threshold of a warm
    // candidate reduces the number of random acceptances to minimize the impact on the hit rate.
    int random = ThreadLocalRandom.current().nextInt();
    return ((random & 127) == 0);
  }
  return false;
}
```

This matches the 3.3.1 bytecode read in [6.3 §1.2](../06-Resilience-Caching-Kafka/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md).

### 3.3 Reads never wait for the policy

```java
@Nullable V afterRead(Node<K, V> node, long now, boolean recordHit) {
  if (recordHit) {
    statsCounter().recordHits(1);
  }

  boolean delayable = (readBuffer.offer(node) != Buffer.FULL);
  if (shouldDrainBuffers(delayable)) {
    scheduleDrainBuffers();
  }
  return refreshIfNeeded(node, now);
}
```

The access is *offered* to a striped ring buffer. If it's full, the event is simply dropped (the map is still exact; only the LRU/LFU bookkeeping is approximate). Draining happens in `maintenance()`, one thread at a time:

```java
void maintenance(@Nullable Runnable task) {
  …
      drainReadBuffer();
      drainWriteBuffer();
  …
    drainKeyReferences();
    drainValueReferences();

    long now = expirationTicker().read();
    expireEntries(now);
    evictEntries(now);

    climb();
  …
}
```

### 3.4 Reading questions

1. Why can the read buffer be lossy but the write buffer can't? (A lost read event mis-orders the policy slightly; a lost write event would leave the policy not knowing an entry exists, so it could never be evicted.)
2. What does `climb()` adjust, and what workload makes it grow the window? (See `WindowClimber.java`.)
3. Why are the sketch's counters for one key kept within a single 64-byte block, even though that's statistically worse than spreading them?

---

## 4. Files to read

| Repo | Path | Focus |
|---|---|---|
| [brettwooldridge/HikariCP](https://github.com/brettwooldridge/HikariCP) | `src/main/java/com/zaxxer/hikari/util/ConcurrentBag.java` | `borrow`, `requite`, `add`, `remove`, `reserve` |
| same | `src/main/java/com/zaxxer/hikari/util/FastList.java` | Reverse scan, identity compare |
| same | `src/main/java/com/zaxxer/hikari/pool/HikariPool.java` | `getConnection`, `createPoolEntry`, the housekeeper |
| same | `src/main/java/com/zaxxer/hikari/pool/ProxyConnection.java` | Statement tracking, what happens on `close()` |
| same | `src/main/java/com/zaxxer/hikari/pool/PoolEntry.java` | The CAS state word |
| [resilience4j/resilience4j](https://github.com/resilience4j/resilience4j) | `resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/internal/CircuitBreakerStateMachine.java` | `stateTransition`, inner state classes |
| same | `resilience4j-core/src/main/java/io/github/resilience4j/core/metrics/FixedSizeSlidingWindowMetrics.java` | O(1) window |
| same | `resilience4j-ratelimiter/src/main/java/io/github/resilience4j/ratelimiter/internal/AtomicRateLimiter.java` | `calculateNextState`, `reservePermissions` |
| [ben-manes/caffeine](https://github.com/ben-manes/caffeine) | `caffeine/src/main/java/com/github/benmanes/caffeine/cache/FrequencySketch.java` | The sketch and its aging |
| same | `caffeine/src/main/java/com/github/benmanes/caffeine/cache/BoundedLocalCache.java` | `admit`, `afterRead`, `maintenance`, `evictEntries` |
| same | `caffeine/src/main/java/com/github/benmanes/caffeine/cache/WindowClimber.java` | Adaptive window sizing |

---

## 5. Interview soundbites

* "HikariCP's bag never removes a borrowed connection; borrowing is a CAS on the entry's state. It tries this thread's recently used connections, then scans a copy-on-write list, then waits on a fair hand-off queue that returning threads feed directly."
* "It also jitters `maxLifetime` by up to 25 % so connections created together don't all reconnect together, the same trick as TTL jitter in caches."
* "Resilience4j's breaker state is one `AtomicReference`, and the window keeps running totals in a circular array, so recording is O(1). The rate limiter's `calculateNextState` shows it's a fixed window, not a token bucket."
* "Caffeine's sketch packs sixteen 4-bit counters per `long`, keeps a key's counters in one cache line, and ages them with one shift and mask. Reads drop bookkeeping when buffers are full rather than wait."

**Next:** [8.5 Code-reading plan and bar-raiser drill-downs →](05-Code-Reading-Plan-and-Bar-Raiser-Drill-Downs.md)
