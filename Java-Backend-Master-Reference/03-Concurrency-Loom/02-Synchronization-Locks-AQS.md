# 3.2 · Synchronization & Locks — `synchronized` Internals, `ReentrantLock`, `ReadWriteLock`, `StampedLock`, AQS, Deadlocks

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("thread-safe code with locks and the concurrent API")
> **Sources:** JVMS §2.11.10 and §6.5 (`monitorenter`/`monitorexit`), HotSpot `objectMonitor.cpp` / `lightweightSynchronizer.cpp`, JEP 374 (biased locking removed), JEP 491 (virtual threads synchronize without pinning, JDK 24), `java.util.concurrent.locks` Javadoc, Doug Lea, "The java.util.concurrent Synchronizer Framework" (2005).
> Benchmarks are short single-machine runs (12-thread laptop, JDK 25), and the numbers are indicative. The *ratios* are the lesson.

---

## 1. `synchronized` in bytecode and in HotSpot 🔥

### 1.1 Bytecode (real `javap -c -v`, JDK 25)

```java
void block() { synchronized (lock) { n++; } }
synchronized void method() { n++; }
```

```
  void block();
     6: monitorenter                       ← acquire lock's monitor
     7: aload_0 … 14: putfield n           ← critical section
    17: aload_1
    18: monitorexit                        ← normal-path release
    19: goto 27
    22: astore_2
    23: aload_1
    24: monitorexit                        ← exceptional-path release (compiler-generated handler)
    25: aload_2
    26: athrow
    Exception table:
       from    to  target type
           7    19    22   any               ← any throwable inside the block releases the monitor
          22    25    22   any
  synchronized void method();
    flags: (0x0020) ACC_SYNCHRONIZED       ← no monitorenter in the body; the VM locks `this` on entry
```

`synchronized` blocks are **structured**: the compiler guarantees `monitorexit` on every path, which is why you can't "forget to unlock" (unlike `Lock`). Synchronized methods lock `this` (or the `Class` object for `static` methods).

### 1.2 How HotSpot implements monitors (JDK 21–27)

```
 Uncontended:   LIGHTWEIGHT LOCKING (default since JDK 23; LockingMode=2)
                CAS the mark-word lock bits 01 → 00 and push the object on the thread's small LOCK-STACK.
                Recursive locking just pushes again. No allocation, no header displacement.
                        │ contention (another thread wants it), Object.wait(), lock-stack overflow, JNI MonitorEnter…
                        ▼
 Contended:     INFLATION → ObjectMonitor (C++ object)
                  _owner        thread holding it
                  _recursions   reentrancy count
                  _EntryList/_cxq   threads blocked trying to enter   (state BLOCKED)
                  _WaitSet      threads in Object.wait()              (state WAITING / TIMED_WAITING)
                Mark word points to it (lock bits 10), or, with compact headers, it is found via the
                ObjectMonitor TABLE (UseObjectMonitorTable).
                Acquire path: adaptive SPIN briefly (owner likely to release soon) → then park the thread.
                        │ monitor idle
                        ▼
 Deflation:     a background "monitor deflation" thread returns idle monitors (async since JDK 15)
```

History you'll still hear about: **biased locking** (JDK 6–14 default) made uncontended locking by a single thread almost free, but revocation needed safepoints. It was disabled in 15 (JEP 374) and removed in 18. **Stack locking** (legacy `LockingMode=1`) displaced the mark word into a lock record on the stack; it was replaced by lightweight locking.

**Properties of intrinsic locks:**

* Reentrant, non-interruptible while waiting to enter, **no fairness guarantee**, no timeout, one wait-set per object.
* The JIT can **elide** locks on non-escaping objects and **coarsen** adjacent blocks ([1.5 §4.3](../01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md#43-lock-elision-and-coarsening)).
* **Virtual threads:** before JDK 24, blocking while holding a monitor **pinned** the carrier thread. JDK 24's JEP 491 associates monitors with the virtual thread itself, so `synchronized` no longer pins ([3.6](06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md)).

### 1.3 `wait`/`notify` correctly 🎓

```java
synchronized (lock) {
    while (!conditionHolds()) {        // ALWAYS a loop: spurious wakeups + another thread may have consumed the state
        lock.wait();                   // releases the monitor; reacquires it before returning
    }
    act();
}
// elsewhere
synchronized (lock) { changeState(); lock.notifyAll(); }   // notifyAll unless exactly one waiter type and one waiter must wake
```

* Calling `wait`/`notify` without owning the monitor throws `IllegalMonitorStateException`.
* `notify()` wakes **one arbitrary** waiter. If waiters wait for **different conditions** on the same monitor, `notify()` can wake the wrong one, which is a **lost wakeup** and leads to a hang. Prefer `notifyAll`, or `Lock` + multiple `Condition`s.
* `wait` can return **spuriously**, hence the `while` loop.
* Prefer higher-level tools (`BlockingQueue`, `CountDownLatch`, `CompletableFuture`) in application code.

---

## 2. `java.util.concurrent.locks.Lock` 🔥🎓

| Capability | `synchronized` | `ReentrantLock` |
|---|---|---|
| Reentrant | ✅ | ✅ (`getHoldCount()`) |
| Interruptible acquire | ❌ | ✅ `lockInterruptibly()` |
| Try / timeout | ❌ | ✅ `tryLock()`, `tryLock(timeout, unit)` |
| Fairness option | ❌ | ✅ `new ReentrantLock(true)` |
| Multiple condition queues | ❌ (one wait-set) | ✅ `newCondition()` |
| Non-block-structured (lock in one method, unlock in another) | ❌ | ✅ (and risky) |
| Automatic release on exception | ✅ | ❌ **you must `unlock()` in `finally`** |
| Monitoring | Thread dumps | `isLocked`, `getQueueLength`, `hasQueuedThreads`, owner via dumps |
| Virtual-thread friendly | ✅ since JDK 24 | ✅ always |

```java
lock.lock();                 // acquire OUTSIDE the try: if lock() throws, we must not unlock
try {
    // critical section
} finally {
    lock.unlock();
}
```

### 2.1 Fairness costs throughput (measured)

```
1 thread  synchronized        :    78,034,501 ops/s
4 threads synchronized        :    28,912,634 ops/s
4 threads ReentrantLock       :    30,568,864 ops/s      ← non-fair (default): barging allowed
4 threads ReentrantLock(fair) :       133,755 ops/s      ← ~230× slower: strict FIFO handoff = context switch per acquisition
4 threads AtomicLong          :    67,989,715 ops/s      ← no lock at all (CAS), for comparison
```

**Why:** a non-fair lock lets a running thread grab a just-released lock immediately (*barging*), so the CPU stays busy. A fair lock must hand ownership to the longest waiter, which is parked, so every acquisition costs a park/unpark round trip and a context switch. Use fairness only when starvation is a demonstrated problem.

### 2.2 Conditions: a bounded buffer with two wait-sets

<!-- run: -->
```java
import java.util.concurrent.locks.*;

public class BoundedBuffer<T> {
    private final Object[] items;
    private int putIdx, takeIdx, count;
    private final ReentrantLock lock = new ReentrantLock();
    private final Condition notFull = lock.newCondition();     // producers wait here
    private final Condition notEmpty = lock.newCondition();    // consumers wait here

    BoundedBuffer(int capacity) { items = new Object[capacity]; }

    void put(T t) throws InterruptedException {
        lock.lockInterruptibly();
        try {
            while (count == items.length) notFull.await();      // loop: spurious wakeups
            items[putIdx] = t; putIdx = (putIdx + 1) % items.length; count++;
            notEmpty.signal();                                  // exactly the right wait-set: no lost-wakeup risk
        } finally { lock.unlock(); }
    }

    @SuppressWarnings("unchecked")
    T take() throws InterruptedException {
        lock.lockInterruptibly();
        try {
            while (count == 0) notEmpty.await();
            T t = (T) items[takeIdx]; items[takeIdx] = null; takeIdx = (takeIdx + 1) % items.length; count--;
            notFull.signal();
            return t;
        } finally { lock.unlock(); }
    }

    public static void main(String[] args) throws Exception {
        BoundedBuffer<Integer> buf = new BoundedBuffer<>(4);
        int producers = 3, perProducer = 100_000;
        Thread[] ps = new Thread[producers];
        for (int p = 0; p < producers; p++) {
            ps[p] = Thread.ofPlatform().start(() -> {
                try { for (int i = 1; i <= perProducer; i++) buf.put(i); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            });
        }
        long sum = 0;
        for (int i = 0; i < producers * perProducer; i++) sum += buf.take();
        for (Thread t : ps) t.join();
        System.out.println("sum=" + sum + " expected=" + (long) producers * perProducer * (perProducer + 1) / 2);
    }
}
```

Output (verified): `sum=15000150000 expected=15000150000`

This is essentially `ArrayBlockingQueue`'s design: one lock, two conditions.

---

## 3. `ReentrantReadWriteLock` ⚡🎓

* **State encoding (AQS `int`):** high 16 bits = shared (read) holds, low 16 bits = exclusive (write) reentrant holds. So at most 65,535 read holds and 65,535 recursive write holds.
* Per-thread read hold counts are tracked with a `ThreadLocal` (`HoldCounter`), with a cached fast path for the first reader. Every read acquire still does a **CAS on the shared state word**, so under many readers the lock's cache line ping-pongs between cores.
* **No upgrade:** a thread holding the read lock that calls `writeLock().lock()` **deadlocks itself**, because the writer waits for all readers to leave, itself included. **Downgrade is allowed:** acquire write → acquire read → release write.
* **Writer preference heuristic (non-fair mode):** new readers block if the head of the queue is a waiting writer, which prevents writer starvation.
* **When it loses:** for short critical sections, the bookkeeping plus the shared CAS makes it slower than a plain mutex. It pays off only for **long** read sections with rare writes. For read-mostly data with tiny critical sections, use `StampedLock` optimistic reads, immutable snapshots via `AtomicReference`/copy-on-write, or `ConcurrentHashMap`.

<!-- run: -->
```java
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class RwUpgradeTrap {
    public static void main(String[] args) throws Exception {
        var rw = new ReentrantReadWriteLock();
        rw.readLock().lock();
        try {
            boolean upgraded = rw.writeLock().tryLock(200, TimeUnit.MILLISECONDS);   // lock() here would hang forever
            System.out.println("upgrade read→write while holding read: " + upgraded);
        } finally { rw.readLock().unlock(); }

        rw.writeLock().lock();                                                       // downgrade is legal
        rw.readLock().lock();
        rw.writeLock().unlock();
        System.out.println("downgraded: write held=" + rw.isWriteLocked() + ", read holds=" + rw.getReadLockCount());
        rw.readLock().unlock();
    }
}
```

Output (verified):

```
upgrade read→write while holding read: false
downgraded: write held=false, read holds=1
```

---

## 4. `StampedLock` and optimistic reading 🔥

```java
private final StampedLock sl = new StampedLock();
private double x, y;

double distanceFromOrigin() {
    long stamp = sl.tryOptimisticRead();     // no CAS, no write to shared memory: just reads the version/state
    double cx = x, cy = y;                   // read into LOCALS (may be inconsistent!)
    if (!sl.validate(stamp)) {               // did a writer intervene? (acquire fence + version check)
        stamp = sl.readLock();               // fall back to a real read lock
        try { cx = x; cy = y; } finally { sl.unlockRead(stamp); }
    }
    return Math.hypot(cx, cy);               // compute only after validation
}

void move(double dx, double dy) {
    long stamp = sl.writeLock();
    try { x += dx; y += dy; } finally { sl.unlockWrite(stamp); }
}
```

**Measured, read-mostly (6 reader threads + 1 occasional writer):**

```
ReadWriteLock : reads     6,027,058/s  writes         67/s
StampedLock   : reads 2,818,813,020/s  writes         67/s (optimistic reads)
```

That is **~470× more read throughput**, because optimistic reads never write to the shared lock word, so no cache-line ping-pong. (The writer sleeps ~10 µs between writes; Windows timer granularity turned that into ~67 writes/s.)

**Rules and pitfalls:**

* Copy fields into locals, then validate, then use them. Between `tryOptimisticRead` and `validate` you may see **inconsistent state**: don't dereference possibly-null references or index arrays with values read optimistically without guarding, because you can throw *before* validating.
* **Not reentrant.** Acquiring a read lock while holding the write lock (in the same thread) deadlocks.
* No `Condition`s. Stamps are not owner-checked (any thread holding the stamp can unlock).
* Conversions: `tryConvertToWriteLock(stamp)` upgrades when possible (unlike RRWL).
* `asReadLock()`/`asWriteLock()` views adapt it to the `Lock` interface.

### 4.1 Choosing a lock

| Scenario | Choose |
|---|---|
| Simple mutual exclusion, short sections | `synchronized` (lowest ceremony; JDK 24+ VT-safe) or `ReentrantLock` |
| Need timeout, interruptibility, `tryLock`, or multiple conditions | `ReentrantLock` |
| Long read sections, rare writes, reentrancy needed | `ReentrantReadWriteLock` |
| Very hot, tiny read sections; rare writes | `StampedLock` optimistic read, or an immutable snapshot in an `AtomicReference`/`volatile` |
| Counters | `LongAdder`/`AtomicLong` (no lock: [3.3](03-Lock-Free-CAS-Atomics.md)) |
| Key-value state | `ConcurrentHashMap` (per-bin locking built in) |

---

## 5. AQS — the engine under (almost) every `j.u.c` synchronizer 🔥

`AbstractQueuedSynchronizer` implements **queuing and blocking** once. Subclasses define **what the `state` int means**:

| Synchronizer | `state` meaning | Mode |
|---|---|---|
| `ReentrantLock` | Hold count (0 = free) | Exclusive |
| `ReentrantReadWriteLock` | Read count (high 16) + write count (low 16) | Both |
| `Semaphore` | Available permits | Shared |
| `CountDownLatch` | Remaining count | Shared |
| `ThreadPoolExecutor.Worker` | Non-reentrant lock bit (protects interrupts) | Exclusive |

```
             tryAcquire(arg) succeeds? ──yes──► return (fast path: one CAS on state)
                    │ no
                    ▼
   enqueue a Node at the TAIL (CAS)  ── CLH-style FIFO queue:  head → [n1] → [n2] → [n3] ← tail
                    │
   loop: if my predecessor is head and tryAcquire succeeds → become head, return
         else LockSupport.park(this)       ← thread state WAITING ("parking to wait for <…Sync>")
                    ▲
   release(arg): tryRelease(arg) → if the lock is now free, unpark the head's successor
```

* **Template methods** you implement: `tryAcquire`, `tryRelease`, `tryAcquireShared` (negative = fail, 0 = success without propagation, positive = success and others may proceed too), `tryReleaseShared`, `isHeldExclusively` (for conditions).
* `ConditionObject` keeps a separate condition queue. `signal` **transfers** a node from the condition queue to the sync queue.
* Cancellation (timeouts, interrupts) unlinks nodes. JDK 14 rewrote AQS internals for simpler, faster code with the same API.
* **`LockSupport.park/unpark`** carry one **permit**: `unpark` before `park` makes the next `park` return immediately, and permits don't accumulate. `park(blocker)` records the blocker object, which is what thread dumps show as `- parking to wait for <0x…> (a java.util.concurrent.locks.ReentrantLock$NonfairSync)`.

### 5.1 Runnable: two custom synchronizers in ~30 lines

<!-- run: -->
```java
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.AbstractQueuedSynchronizer;

public class CustomSynchronizers {
    /** Non-reentrant mutex: state 0 = free, 1 = held. */
    static final class Mutex {
        private static final class Sync extends AbstractQueuedSynchronizer {
            @Override protected boolean tryAcquire(int ignored) {
                if (compareAndSetState(0, 1)) { setExclusiveOwnerThread(Thread.currentThread()); return true; }
                return false;
            }
            @Override protected boolean tryRelease(int ignored) {
                if (getState() == 0 || getExclusiveOwnerThread() != Thread.currentThread()) throw new IllegalMonitorStateException();
                setExclusiveOwnerThread(null);
                setState(0);                          // volatile write = release
                return true;
            }
            @Override protected boolean isHeldExclusively() { return getState() == 1 && getExclusiveOwnerThread() == Thread.currentThread(); }
        }
        private final Sync sync = new Sync();
        void lock() { sync.acquire(1); }
        boolean tryLock(long ms) throws InterruptedException { return sync.tryAcquireNanos(1, TimeUnit.MILLISECONDS.toNanos(ms)); }
        void unlock() { sync.release(1); }
    }

    /** One-shot latch: state 0 = closed, 1 = open; shared mode releases ALL waiters. */
    static final class OneShotLatch {
        private static final class Sync extends AbstractQueuedSynchronizer {
            @Override protected int tryAcquireShared(int ignored) { return getState() == 1 ? 1 : -1; }
            @Override protected boolean tryReleaseShared(int ignored) { setState(1); return true; }
        }
        private final Sync sync = new Sync();
        void await() throws InterruptedException { sync.acquireSharedInterruptibly(0); }
        void open() { sync.releaseShared(0); }
    }

    static int counter;

    public static void main(String[] args) throws Exception {
        Mutex m = new Mutex();
        Thread[] ts = new Thread[4];
        for (int i = 0; i < ts.length; i++) {
            ts[i] = Thread.ofPlatform().start(() -> { for (int k = 0; k < 250_000; k++) { m.lock(); try { counter++; } finally { m.unlock(); } } });
        }
        for (Thread t : ts) t.join();
        System.out.println("mutex-protected counter = " + counter);

        m.lock();
        System.out.println("non-reentrant: second tryLock by owner = " + m.tryLock(50));
        m.unlock();

        OneShotLatch latch = new OneShotLatch();
        Thread[] waiters = new Thread[3];
        for (int i = 0; i < waiters.length; i++) {
            int id = i;
            waiters[i] = Thread.ofPlatform().start(() -> {
                try { latch.await(); System.out.println("waiter " + id + " released"); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            });
        }
        Thread.sleep(100);
        System.out.println("waiters parked: " + waiters[0].getState() + "; opening latch");
        latch.open();
        for (Thread w : waiters) w.join();
    }
}
```

Output (verified; the order of the three "released" lines varies):

```
mutex-protected counter = 1000000
non-reentrant: second tryLock by owner = false
waiters parked: WAITING; opening latch
waiter 0 released
waiter 2 released
waiter 1 released
```

---

## 6. Deadlocks, livelocks, starvation 🔥

**Coffman conditions** (all four are required): mutual exclusion, hold-and-wait, no preemption, circular wait. **Break any one:**

| Technique | Breaks |
|---|---|
| **Global lock ordering** (always lock accounts by ascending ID) | Circular wait |
| `tryLock(timeout)` with back-off and retry | Hold-and-wait / no preemption |
| One coarse lock for the operation, or lock-free structures | Mutual exclusion granularity |
| Never call alien code (callbacks, listeners, other services) while holding a lock | Prevents unknown lock orders |

### 6.1 Runnable: create and detect a deadlock

<!-- run: -->
```java
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadInfo;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.locks.ReentrantLock;

public class DeadlockDetect {
    static final Object ACCOUNT_A = new Object(), ACCOUNT_B = new Object();
    static final ReentrantLock LOCK_X = new ReentrantLock(), LOCK_Y = new ReentrantLock();

    public static void main(String[] args) throws Exception {
        CountDownLatch both = new CountDownLatch(2);
        // Monitor deadlock: A→B vs B→A
        Thread.ofPlatform().daemon().name("transfer-1").start(() -> { synchronized (ACCOUNT_A) { both.countDown(); await(both); synchronized (ACCOUNT_B) { } } });
        Thread.ofPlatform().daemon().name("transfer-2").start(() -> { synchronized (ACCOUNT_B) { both.countDown(); await(both); synchronized (ACCOUNT_A) { } } });
        // j.u.c lock deadlock: X→Y vs Y→X
        CountDownLatch both2 = new CountDownLatch(2);
        Thread.ofPlatform().daemon().name("job-1").start(() -> { LOCK_X.lock(); both2.countDown(); await(both2); LOCK_Y.lock(); });
        Thread.ofPlatform().daemon().name("job-2").start(() -> { LOCK_Y.lock(); both2.countDown(); await(both2); LOCK_X.lock(); });
        Thread.sleep(300);

        var mx = ManagementFactory.getThreadMXBean();
        long[] ids = mx.findDeadlockedThreads();                    // monitors AND ownable synchronizers
        System.out.println("deadlocked threads: " + (ids == null ? 0 : ids.length));
        for (ThreadInfo ti : mx.getThreadInfo(ids, true, true)) {
            String lock = ti.getLockName().replaceAll("@[0-9a-f]+", "@…");
            System.out.printf("%-10s %-8s waiting for %-55s held by %s%n", ti.getThreadName(), ti.getThreadState(), lock, ti.getLockOwnerName());
        }
    }
    static void await(CountDownLatch l) { try { l.await(); } catch (InterruptedException e) { throw new RuntimeException(e); } }
}
```

Output (verified; line order may vary):

```
deadlocked threads: 4
transfer-1 BLOCKED  waiting for java.lang.Object@…                                      held by transfer-2
transfer-2 BLOCKED  waiting for java.lang.Object@…                                      held by transfer-1
job-1      WAITING  waiting for java.util.concurrent.locks.ReentrantLock$NonfairSync@…  held by job-2
job-2      WAITING  waiting for java.util.concurrent.locks.ReentrantLock$NonfairSync@…  held by job-1
```

* **Monitor** waits show as **BLOCKED**, and **j.u.c lock** waits as **WAITING** (parked). `findDeadlockedThreads` detects both. (`findMonitorDeadlockedThreads` only detects monitors.)
* `jstack <pid>` / `jcmd <pid> Thread.print` print a **"Found one Java-level deadlock"** section with the same cycle. It does **not** detect class-initialization deadlocks ([1.1 §5.4](../01-JVM-Internals/01-ClassLoading-Linking-JPMS.md#54-class-initialization-deadlock-)) or deadlocks through external resources (DB row locks, connection pools), so read the stacks.
* A deadlock is unrecoverable in-process (threads can't be forcibly unlocked). Alert on it (a periodic `findDeadlockedThreads` health check) and restart.

### 6.2 Other liveness failures

| Failure | Description | Example |
|---|---|---|
| **Livelock** | Threads keep responding to each other and make no progress | Two `tryLock` loops that back off and retry in lockstep. Fix: randomized back-off |
| **Starvation** | A thread never gets the resource | Non-fair locks under extreme contention; low-priority threads; readers starving writers |
| **Lock convoy** | Threads queue behind a lock whose holder keeps getting descheduled; throughput collapses | A hot lock around I/O or logging. Fix: shrink critical sections, shard locks |
| **Resource deadlock** | Waiting on pools rather than locks | All threads of a pool block on futures of tasks queued to **the same pool** (Pillar 3.4) |

---

## 7. Thread states in dumps 🎓

| `Thread.State` | Meaning | Typical stack top |
|---|---|---|
| `NEW` / `TERMINATED` | Not started / finished | — |
| `RUNNABLE` | Running **or ready**, or in native I/O (a blocking socket read shows RUNNABLE in older JDKs), or waiting on class init | CPU work, `socketRead0` |
| `BLOCKED` | Waiting to enter a `synchronized` monitor | `- waiting to lock <0x…> (a com.acme.X)` |
| `WAITING` | `Object.wait()`, `join()`, `LockSupport.park()` with no timeout | `- parking to wait for <0x…> (a …ConditionObject)` |
| `TIMED_WAITING` | `sleep`, `wait(ms)`, `parkNanos`, `join(ms)` | `Thread.sleep`, pool workers idling in `poll(keepAlive)` |

**Reading dumps for contention:** find the lock address that many threads are `waiting to lock`, then find the one thread that `- locked <same address>`. Its stack is your bottleneck.

---

## 8. Production failure modes & diagnostics (locks)

| Failure | Signature | Fix |
|---|---|---|
| Deadlock | Throughput to zero; "Found one Java-level deadlock" | Lock ordering; `tryLock` with timeout; no alien calls under locks |
| Lock contention / convoy | Many `BLOCKED` threads on one monitor; high context switches (`vmstat cs`), low CPU | Smaller critical sections; lock striping; concurrent collections; read-mostly → `StampedLock` or immutable snapshots |
| Fair lock throughput collapse | `ReentrantLock(true)` with high contention (measured 230× slower) | Non-fair unless starvation is proven |
| RW lock self-deadlock | Thread holding a read lock waits forever on the write lock (dump shows it parked in `writeLock().lock()`) | Never upgrade; release read first, then re-check under the write lock |
| Forgotten `unlock()` | Threads `WAITING` on a `ReentrantLock` whose owner returned long ago (dump: no thread holds it in a frame) | `try/finally`; static analysis (Error Prone `LockNotBeforeTry`) |
| Lost wakeup | Threads `WAITING` in `Object.wait()` forever although the condition is true | `while` loops; `notifyAll`; separate `Condition`s |
| Lock held during I/O | Latency spikes correlate with downstream latency; BLOCKED threads behind one RUNNABLE in `socketRead` | Never do I/O while holding a lock; snapshot then release |

**Tools:** `jcmd <pid> Thread.print -l` (`-l` prints ownable synchronizers), three dumps 5 s apart, JFR events `jdk.JavaMonitorEnter` (default threshold 20 ms), `jdk.JavaMonitorWait`, `jdk.ThreadPark`; async-profiler `-e lock` (lock-contention flame graph); `ThreadMXBean.setThreadContentionMonitoringEnabled(true)` for blocked and waited times per thread.

---

## 9. Interview & certification Q&A

<details><summary><b>Q1. 🔥 How is `synchronized` implemented today (JDK 21+)? What happened to biased locking?</b></summary>

`monitorenter`/`monitorexit` bytecodes (or `ACC_SYNCHRONIZED`). Uncontended locking uses lightweight locking: a CAS on the mark word's lock bits plus a push onto the thread's lock-stack. Contention, `wait()` or other events inflate the lock to an `ObjectMonitor` with entry and wait queues, adaptive spinning and parking. Idle monitors are deflated asynchronously. Biased locking (cheap re-acquisition by one thread) was deprecated and disabled in JDK 15 and removed in 18, because revocation required safepoints and modern CAS is cheap.
</details>

<details><summary><b>Q2. 🎓 Why must `wait()` be called in a loop, and inside `synchronized`?</b></summary>

`wait` can return spuriously, or after another thread has already consumed the state change, so the condition must be re-checked. The call must hold the monitor (else `IllegalMonitorStateException`), because the check-then-wait must be atomic with respect to notifiers, otherwise a notify can be missed between the check and the wait.
</details>

<details><summary><b>Q3. 🔥 `ReentrantLock` vs `synchronized`: when do you need `ReentrantLock`?</b></summary>

When you need `tryLock` (deadlock avoidance, non-blocking attempts), timed or interruptible acquisition, multiple `Condition`s, fairness, or lock-state introspection. Otherwise `synchronized` is simpler, can't leak a held lock on exceptions, and since JDK 24 no longer pins virtual threads.
</details>

<details><summary><b>Q4. ⚡ Explain StampedLock optimistic reads and their pitfalls.</b></summary>

`tryOptimisticRead()` returns a stamp without acquiring anything. You read fields into locals, then `validate(stamp)`; if a writer intervened, you retry or fall back to `readLock()`. It is very fast because readers don't write shared memory (measured ~470× the RW-lock read throughput). Pitfalls: inconsistent intermediate reads (never act on them before validation, and beware NPEs or index errors), no reentrancy, no conditions, and stamps not owner-checked.
</details>

<details><summary><b>Q5. 🧊 How does AQS work?</b></summary>

AQS holds a volatile `int state` and a FIFO wait queue of nodes. `acquire` tries the subclass's `tryAcquire` (a CAS on state). On failure it enqueues a node and parks, retrying when it becomes first in the queue. `release` calls `tryRelease` and unparks the successor. Shared mode (`tryAcquireShared`) lets releases propagate to multiple waiters (latches, semaphores). Conditions are separate queues whose nodes move to the sync queue on `signal`.
</details>

<details><summary><b>Q6. 🎓 What thread states do threads waiting for a monitor vs a `ReentrantLock` show?</b></summary>

A monitor wait shows `BLOCKED` ("waiting to lock"). A `ReentrantLock` wait shows `WAITING` (or `TIMED_WAITING` with `tryLock(timeout)`), because AQS parks the thread ("parking to wait for … NonfairSync").
</details>

<details><summary><b>Q7. 🔥 How do you prevent deadlocks in a money-transfer service?</b></summary>

Acquire account locks in a global order (by account ID), so `transfer(a, b)` and `transfer(b, a)` lock in the same order. Or use `tryLock` with a timeout and randomized back-off. Or avoid in-memory locks entirely by using database transactions with consistent row-lock ordering (`SELECT … FOR UPDATE` ordered by id) or optimistic concurrency (version columns, [5.4](../05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md)).
</details>

<details><summary><b>Q8. ⚡ Why is a fair lock so much slower?</b></summary>

Every release must hand the lock to the longest-waiting thread, which is parked, so each acquisition costs an unpark, a context switch and cache misses. Non-fair locks let the currently running thread re-acquire immediately (barging), keeping CPUs busy. Measured: ~134K vs ~30M ops/s with 4 threads.
</details>

<details><summary><b>Q9. 🎓 Can a `ReentrantReadWriteLock` read lock be upgraded to a write lock?</b></summary>

No. Trying to acquire the write lock while holding the read lock blocks forever (the writer waits for all readers, including itself). Downgrading (write → read → release write) is supported.
</details>

---

## 10. Further reading

* Doug Lea, "The java.util.concurrent Synchronizer Framework": <https://gee.cs.oswego.edu/dl/papers/aqs.pdf>
* *Java Concurrency in Practice* (Goetz et al.), chapters 2–3, 10, 13–14 (still the best on these topics).
* JEP 374 (biased locking), JEP 491 (VT + `synchronized`).
* Roman Kennke, "Lightweight locking in HotSpot" (OpenJDK wiki, Lilliput).
