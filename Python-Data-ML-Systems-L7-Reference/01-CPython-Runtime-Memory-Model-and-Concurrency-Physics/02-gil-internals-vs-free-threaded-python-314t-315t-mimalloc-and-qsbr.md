# 01.2 · GIL Internals vs. Free-Threaded Python (3.14t / 3.15t): Biased Refcounting, mimalloc & QSBR

> **Folder 01 · CPython Runtime, Memory Model & Concurrency Physics**
> **Measured on:** CPython 3.14.5 default (GIL) build, GCC 16.2 (C listings), i5-11260H 6C/12T, Windows 11.
> **Source verified against:** `v3.14.10` / `v3.15.2`: `Python/ceval_gil.c`, `Python/condvar.h`, `Include/internal/pycore_gil.h`, `Include/internal/pycore_ceval.h`, `Python/bytecodes.c`, `Include/refcount.h`, `Objects/object.c`, `Python/brc.c`, `Include/internal/pycore_qsbr.h`, `Include/cpython/critical_section.h`, `Include/internal/pycore_uniqueid.h`, `Objects/listobject.c`, `Python/gc_free_threading.c`, `Python/import.c`.
> ⚠ **Not executed here:** the free-threaded interpreter itself. I downloaded the official PSF-signed `python-freethreaded` 3.14.10 / 3.15.2 builds and verified their Authenticode signatures, but this environment refused to run a downloaded executable. Free-threaded *layouts* come from compiling the real headers with `Py_GIL_DISABLED`; free-threaded *refcount physics* come from a C model; free-threaded *scaling* is a stated prediction plus a probe you run yourself (§2.5).

---

## 0. Orientation & the JVM/C++ Bridge

The GIL is one mutex plus two condition variables that serialize **bytecode execution** per interpreter. Since PEP 684 (3.12) each subinterpreter can have its own; 01.3 uses that via `InterpreterPoolExecutor`. It was never a data-race shield for *your* code. It protects the interpreter's internals: refcounts, dict and list internals, allocator state.

Free-threading (PEP 703; "supported but optional" since 3.14 under PEP 779) removes it. That forces four replacements, each of which has a JVM or C++ ancestor:

| Problem the GIL solved for free | Free-threaded replacement | JVM analogue | C++ analogue |
|---|---|---|---|
| Refcount updates without atomics | **Biased refcounting**: owner thread plain stores to `ob_ref_local`, others atomic RMW on `ob_ref_shared` | *Biased locking* (removed in JDK 18 — revocation cost > gain) | `shared_ptr` = always-atomic count (one shared counter) |
| Hot shared objects (`None`, types, functions) | Immortalization, **deferred** refcounting, **per-thread** refcounts for types/code | No refcounts at all (tracing GC) | Intrusive counts + careful ownership |
| Container internals (dict, list) | Per-object `PyMutex ob_mutex` + **critical sections** (auto-suspended when blocking) | `synchronized` monitors (held across blocking!) | `std::mutex` per object |
| Readers vs. concurrent frees | Lock-free optimistic reads + **QSBR** delayed reclamation | GC makes it free | RCU / hazard pointers / epochs |
| Allocator global state | **mimalloc** thread-local heaps, segregated by GC-ness | TLABs | jemalloc/tcmalloc thread caches |
| GC needs a consistent heap | **Stop-the-world** + heap walk (`_PyEval_StopTheWorld`) | Safepoints | — |

The GIL's switch points are themselves a JVM concept: `_CHECK_PERIODIC` at `RESUME`, `JUMP_BACKWARD` and `CALL` is a safepoint poll on back-edges and calls.

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The GIL as a state machine

`Include/internal/pycore_gil.h` at `v3.14.10` (comments trimmed):

```c
struct _gil_runtime_state {
#ifdef Py_GIL_DISABLED
    int enabled;                 /* 0, transient count, or INT_MAX (re-enabled permanently) */
#endif
    unsigned long interval;      /* microseconds; DEFAULT_INTERVAL 5000 = sys.getswitchinterval() 0.005 */
    PyThreadState* last_holder;  /* who held it last: FORCE_SWITCHING compares against this */
    int locked;                  /* read without the mutex by ceval */
    unsigned long switch_number; /* incremented on every successful handoff */
    PyCOND_T cond;   PyMUTEX_T mutex;          /* waiters sleep here */
    PyCOND_T switch_cond; PyMUTEX_T switch_mutex;  /* releaser waits here until someone else took it */
};
```

The protocol (`Python/ceval_gil.c`, `take_gil` / `drop_gil`):

```text
 Holder A (running bytecode)                         Waiter B (in take_gil)
 ------------------------------------------          -------------------------------------------------
                                                     lock(mutex)
                                                     while locked:
                                                        saved = switch_number
                                                        COND_TIMED_WAIT(cond, mutex, interval)   (5 ms)
                                                        if timed out and locked and switch_number == saved:
                                                           set eval_breaker bit _PY_GIL_DROP_REQUEST_BIT
 _CHECK_PERIODIC at RESUME / JUMP_BACKWARD / CALL:
   eval_breaker != 0 ? -> handle: drop request set
 drop_gil(): locked = 0; COND_SIGNAL(cond)
   FORCE_SWITCHING: wait on switch_cond until          wakes: locked = 1, last_holder = B,
   last_holder != A  (so A can't re-grab it)            ++switch_number, COND_SIGNAL(switch_cond)
 take_gil(): now A is the waiter ...                 runs bytecode ...
```

`eval_breaker` is a per-thread word whose bits (`Include/internal/pycore_ceval.h`) OR together everything the loop must handle at a safe point: `_PY_GIL_DROP_REQUEST_BIT` (1<<0), signals (1<<1), pending calls (1<<2), async exceptions (1<<3), GC scheduled (1<<4), stop-the-world (1<<5), explicit refcount merge (1<<6, free-threaded), JIT invalidation (1<<7). The check is one load and a branch, and it exists **only** in `RESUME`, `JUMP_BACKWARD` and the `CALL` family (`Python/bytecodes.c`). A straight-line sequence of bytecodes between two such points can't be interrupted by another *Python* thread. That's why `c.n += 1` "happens to be atomic" and `v = c.n; f(); c.n = v + 1` loses 65 % of its updates (§2.3).

C code leaves the protocol with `Py_BEGIN_ALLOW_THREADS` (detach: release the GIL, mark the thread state detached) and returns with `Py_END_ALLOW_THREADS`. This is the *only* way threads run in parallel on a GIL build. Blocking I/O, `time.sleep`, hashlib for buffers ≥ `HASHLIB_GIL_MINSIZE` (2048 B), zlib, most NumPy ufunc loops, and every `ctypes.CDLL` call do it. `ctypes.PyDLL` deliberately doesn't.

### 1.2 Platform physics: the "5 ms" interval is a request, not a guarantee

`Python/condvar.h`, Windows branch:

```c
PyCOND_TIMEDWAIT(PyCOND_T *cv, PyMUTEX_T *cs, long long us)
{
    BOOL success = SleepConditionVariableSRW(cv, cs, (DWORD)(us/1000), 0);   /* truncate to whole ms */
```

So on Windows the waiter's timeout is first **truncated to milliseconds** (500 µs → 0 ms) and then rounded up by the scheduler to the system timer tick (~15.6 ms unless some process raised the timer resolution). The measurements in §2.2 show exactly this. Median GIL slices are **~16 ms at both 5 ms and 1 ms intervals**, and **≈ 0.2–0.25 ms at 0.5 ms**, because a 0 ms timeout means "request the drop immediately". On Linux, `pthread_cond_timedwait` uses high-resolution timers and slices track the interval (~5 ms); ⚠ that wasn't measured here.

**History check on a common claim.** "CPU-bound threads run *slower* on multicore than on one core because of the GIL" was true of the **old GIL** (≤ 3.1, tick-based, signal storms; Beazley 2009–2010). The **new GIL** (Pitrou, 3.2) is time-based with forced switching and removed that thrash. Four CPU-bound threads here run at **0.98–1.15×** of one thread across runs: no gain, no meltdown. What survives is the **convoy effect** (bpo-7946). An I/O-bound thread must wait out a full interval every time it wakes up, so its latency is quantized to the switch interval (§2.2: 35 ms median round trip with one CPU hog).

### 1.3 Free-threaded object header and biased refcounting

From compiling the 3.14 headers with `Py_GIL_DISABLED` (`pyobject_layout.c` in 01.1):

```text
 off  0  ob_tid        uintptr  owning thread id = TLS base: gs:[0x30] Win x64, fs:0 Linux x86-64, tpidr_el0 AArch64
                                 (also reused by the GC as list link / gc_refs scratch)
 off  8  ob_flags      u16
 off 10  ob_mutex      u8       PyMutex: bit0 locked, bit1 has-parked (waiters in the parking lot)
 off 11  ob_gc_bits    u8       tracked / finalized / unreachable / alive / deferred ...
 off 12  ob_ref_local  u32      owner-only count; UINT32_MAX = immortal
 off 16  ob_ref_shared ssize    everyone else's count << 2 | 2 flag bits
 off 24  ob_type       PyTypeObject*                                             total 32 B (vs 16 B)
```

`Py_INCREF` / `Py_DECREF`, verbatim logic from `Include/refcount.h` and `Objects/object.c`:

```text
INCREF(op):
  local = load_relaxed(&op->ob_ref_local)
  if (uint32)(local + 1) == 0:           return                       # immortal (UINT32_MAX)
  if op->ob_tid == _Py_ThreadId():       store_relaxed(&op->ob_ref_local, local + 1)   # plain mov
  else:                                  atomic_add(&op->ob_ref_shared, 1 << 2)         # lock xadd

DECREF(op) by a NON-owner  (_Py_DecRefSharedIsDead, CAS loop):
  shared = load_relaxed(&op->ob_ref_shared)
  if shared in (0, MAYBE_WEAKREF):  new = QUEUED      # count would go negative: hand to the owner
  else:                             new = shared - 4  # may legitimately go negative!
  CAS(&op->ob_ref_shared, shared, new)
  if QUEUED:  _Py_brc_queue_object(op)  -> owner's eval_breaker bit _PY_EVAL_EXPLICIT_MERGE_BIT
  if new == MERGED (refcount 0, already merged): deallocate

ob_ref_shared low 2 bits:  0 = INIT   1 = MAYBE_WEAKREF   2 = QUEUED   3 = MERGED
true refcount = ob_ref_local + (ob_ref_shared >> 2)
```

When the owner's local count reaches zero it merges the two fields (`_Py_MergeZeroLocalRefcount`). A non-owner that would drive the shared count below zero *queues* the object to the owner's per-thread merge queue (`Python/brc.c`), signals it via the eval breaker, and every queue is also drained during GC. The design bet comes from the Biased Reference Counting paper (Choi, Shull, Torrellas, PACT 2018): most objects are only ever touched by the thread that created them. The C model in §2.4 measures the bet: **~1 ns** per incref+decref pair for the owner against **~10 ns** for an uncontended atomic and **≈ 36–140 ns** for a contended shared counter.

The counter-strategies for objects that are *inherently* shared, all verified in `v3.14.10`:

* **Immortalization** (`ob_ref_local == UINT32_MAX`): `None`, bools, small ints, static strings and types. Increfs skip *before* any thread-ownership test, so they scale like owned data (≈ 0.8–1.7 ns per pair at 1–6 threads in §2.4).
* **Deferred refcounting** (`_PyObject_SetDeferredRefcount`, used in `funcobject.c`, `moduleobject.c`, `descrobject.c`, `typeobject.c`): references from the interpreter's evaluation stack aren't counted, and the GC accounts for them. It covers functions, modules, `classmethod`/`staticmethod` objects and method descriptors: the objects every thread loads constantly.
* **Per-thread refcounting** (`_PyObject_AssignUniqueId` for heap types, code objects and module dicts via `_PyDict_EnablePerThreadRefcounting(m->md_dict)`). Each thread keeps a private array of counts indexed by the object's unique id, merged at GC.
* **Stack references** (`_PyStackRef`, 3.14): tagged pointers on the eval stack that can *borrow* instead of increfing.

### 1.4 Containers without the GIL: per-object locks and critical sections

`list.append`, `dict.__setitem__` and friends lock the object's 1-byte `ob_mutex` through **critical sections** (`Include/cpython/critical_section.h`). The semantics are *not* a Java monitor:

* A thread holds the lock(s) of **one operation at a time** (two objects via `Py_BEGIN_CRITICAL_SECTION2`). Nested operations suspend the outer critical section only *if they would block*.
* **All** active critical sections are suspended when the thread detaches: blocking I/O, waiting on a lock, waiting for a stop-the-world. They're re-acquired on attach.

Deadlocks from lock-ordering therefore can't occur inside the runtime. The flip side is that **atomicity ends at any blocking point** inside an operation. A dict operation that calls a Python `__eq__` which takes a lock can see the dict change underneath it. Python-level guarantees remain "built-in operations don't corrupt objects", never "compound operations are atomic".

### 1.5 Lock-free reads, QSBR, and why the allocator had to change

The free-threaded `list_get_item_ref` (`Objects/listobject.c`) reads without the lock:

```c
if (!_Py_IsOwnedByCurrentThread((PyObject *)op) && !_PyObject_GC_IS_SHARED(op)) {
    return list_item_impl(op, i);                      /* never shared: plain path */
}
PyObject **ob_item = _Py_atomic_load_ptr(&op->ob_item);
Py_ssize_t cap = list_capacity(ob_item);              /* capacity lives in a header before the items */
if (!valid_index(i, cap)) return NULL;
PyObject *item = _Py_TryXGetRef(&ob_item[i]);         /* incref only if the refcount isn't already 0 */
```

Two hazards follow, and two mechanisms answer them:

1. **The array may be freed by a concurrent resize.** Old `ob_item` arrays and dict key tables go through `_PyMem_FreeDelayed` and are reclaimed by **QSBR** (quiescent-state-based reclamation, `Include/internal/pycore_qsbr.h`). A global write sequence starts odd (`QSBR_INITIAL` 1) and advances by `QSBR_INCR` (2) when freed memory is queued (batched by `should_advance_qsbr_for_free`). Each thread publishes the sequence it last observed at a *quiescent state* (`QSBR_QUIESCENT_STATE` in the eval loop, GC), and a detached thread is offline (0) and never blocks reclamation. Memory tagged with sequence *s* is freed once every attached thread has published ≥ *s*. This is RCU's idea, and the same trade-off: zero cost on the read side, bounded memory held until stragglers pass a quiescent point.
2. **The item's memory may be reused for a different object.** `_Py_TryXGetRef` can only validate an object header if the memory still *is* an object header. mimalloc provides that: per-thread heaps, *segregated* by kind (`_Py_MIMALLOC_HEAP_MEM`, `_OBJECT`, `_GC`, `_GC_PRE`). Pages of GC objects only ever hold GC objects, so an optimistic reader never misinterprets a string buffer as a refcount. The same segregation lets the collector find every container by **walking mimalloc's GC heaps** (`gc_visit_heaps` → `mi_heap_visit_blocks`), which is why the free-threaded build has no `PyGC_Head`.

### 1.6 The free-threaded collector

`Python/gc_free_threading.c` collects with the world stopped (`_PyEval_StopTheWorld`). It walks the GC heaps, runs the same subtract-internal-references algorithm (using `ob_tid` as scratch), merges queued refcounts, and processes QSBR-delayed frees. Its trigger is **memory-aware**: once more than `young.threshold` (2000) containers have been allocated, it collects only if process memory grew by more than 10 % since the last collection, or unconditionally after 40× the threshold ("older versions … roughly every 70,000 new container objects"). The pause grows with the number of GC objects walked, and every thread is stopped for it.

### 1.7 What 3.15 changes (⚠ from `v3.15.2` docs/source, not executed)

* **PEP 803 `abi3t`**: a Stable ABI for free-threaded builds. One wheel per platform can serve every free-threaded 3.15+ interpreter. Extensions must move to PEP 697 (negative `basicsize`, `PyObject_GetTypeData`) and the PEP 793 `PyModExport_*` hook.
* Official macOS binaries install free-threading support by default. Windows x64 binaries use the tail-calling interpreter. The JIT is significantly upgraded (LLVM 21, tracing frontend; 7–8 % geomean on x86-64 Linux per the 3.15 notes). The small-int cache grows to −5…1024. The GC stays generational.
* Unchanged rule: importing an extension module that doesn't declare `Py_mod_gil = Py_MOD_GIL_NOT_USED` **re-enables the GIL for the whole process** (`Python/import.c`) with a `RuntimeWarning`: *"The global interpreter lock (GIL) has been enabled to load module '…', which has not declared that it can run safely without the GIL. To override this behavior and keep the GIL disabled (at your own risk), run with PYTHON_GIL=0 or -Xgil=0."*

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Trap: "add threads" — which work actually escapes the GIL?

Same total work: four units on one thread, then one unit on each of four threads. The C kernel is called through `ctypes` both ways. `CDLL` releases the GIL around the call and `PyDLL` doesn't, which isolates the GIL as the only variable.

```c
/* spin.c - a C hot loop for ctypes: ctypes.CDLL releases the GIL around the call, ctypes.PyDLL keeps it. */
/* Build: gcc -O2 -shared -o spin.dll spin.c   (Linux: -fPIC -o libspin.so) */
#include <stdint.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif

EXPORT uint64_t spin(uint64_t n) {
    uint64_t x = 88172645463325252ull, acc = 0;
    for (uint64_t i = 0; i < n; i++) {   /* xorshift64: dependent chain, no memory traffic */
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        acc += x;
    }
    return acc;
}
```

```python
"""gil_release_scaling.py - same total work on 1 thread vs 4 threads: which workloads escape the GIL?

Threads scale only while the running code has released the GIL (Py_BEGIN_ALLOW_THREADS): hashlib above
HASHLIB_GIL_MINSIZE (2048 B), zlib, most NumPy ufunc loops, ctypes.CDLL calls. Pure-Python bytecode never does.
usage: python gil_release_scaling.py PATH_TO_SPIN_DLL
"""
import ctypes
import hashlib
import sys
import threading
import time
import zlib

import numpy as np

T = 4
dll = sys.argv[1]
cdll, pydll = ctypes.CDLL(dll), ctypes.PyDLL(dll)
for f in (cdll.spin, pydll.spin):
    f.argtypes, f.restype = [ctypes.c_uint64], ctypes.c_uint64

blob = bytes(range(256)) * (64 * 1024)                    # 16 MiB
text = (b"order_id,customer,amount\n" + b"1234567,acme corp,99.95\n" * 300_000)
big = np.random.default_rng(1).random(8_000_000)


def py_loop():
    s = 0
    for i in range(1_500_000):
        s += i * i
    return s


def sha_big():
    return hashlib.sha256(blob).digest()                  # one 16 MiB update: GIL released


def sha_small():
    h = hashlib.sha256()
    for i in range(0, 1 << 22, 64):                       # 64 B updates: below 2048 B, GIL kept
        h.update(blob[i:i + 64])
    return h.digest()


def zlib_c():
    return len(zlib.compress(text, 6))


def numpy_ufunc():
    return float(np.sqrt(big).sum())                      # ufunc inner loop runs without the GIL


def c_spin_cdll():
    return cdll.spin(150_000_000)


def c_spin_pydll():
    return pydll.spin(150_000_000)


def run(fn, threads):
    """T units of work: on 1 thread back to back, or one unit per thread concurrently."""
    if threads == 1:
        t0 = time.perf_counter()
        for _ in range(T):
            fn()
        return time.perf_counter() - t0
    ts = [threading.Thread(target=fn) for _ in range(threads)]
    t0 = time.perf_counter()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return time.perf_counter() - t0


print(f"{T} units of work; speedup = time(1 thread) / time({T} threads); {T} = perfect scaling")
print(f"{'workload':40} {'1 thread':>9} {f'{T} threads':>10} {'speedup':>8}")
res = {}
for label, fn in [("pure-Python loop (bytecode)", py_loop), ("hashlib.sha256, one 16 MiB update", sha_big),
                  ("hashlib.sha256, 64 B updates", sha_small), ("zlib.compress 7 MB", zlib_c),
                  ("np.sqrt + sum over 8M float64", numpy_ufunc), ("ctypes.CDLL C loop (GIL released)", c_spin_cdll),
                  ("ctypes.PyDLL C loop (GIL held)", c_spin_pydll)]:
    fn()                                                  # warm caches / page in
    t1 = min(run(fn, 1) for _ in range(2))
    tn = min(run(fn, T) for _ in range(2))
    res[label] = t1 / tn
    print(f"{label:40} {t1 * 1e3:7.0f}ms {tn * 1e3:8.0f}ms {t1 / tn:7.2f}x")
assert res["ctypes.CDLL C loop (GIL released)"] > 2.5 and res["ctypes.PyDLL C loop (GIL held)"] < 1.3
assert res["pure-Python loop (bytecode)"] < 1.3 and res["hashlib.sha256, one 16 MiB update"] > 2.0
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
4 units of work; speedup = time(1 thread) / time(4 threads); 4 = perfect scaling
workload                                  1 thread  4 threads  speedup
pure-Python loop (bytecode)                  296ms      283ms    1.05x
hashlib.sha256, one 16 MiB update             38ms       11ms    3.37x
hashlib.sha256, 64 B updates                  36ms       39ms    0.92x
zlib.compress 7 MB                            31ms        9ms    3.29x
np.sqrt + sum over 8M float64                 86ms       36ms    2.38x
ctypes.CDLL C loop (GIL released)            850ms      243ms    3.49x
ctypes.PyDLL C loop (GIL held)               849ms      860ms    0.99x
ALL ASSERTIONS PASSED
```

The **same C loop** scales ≈ 3.5× or 1.0× depending on one flag. One 16 MiB `sha256` scales ≈ 3.4×, while the same bytes in 64 B updates scale 0.9×, because each `update()` is below `HASHLIB_GIL_MINSIZE`, so the GIL is never released and the per-call overhead dominates. NumPy's ufunc loop scales 2–2.4×: memory bandwidth, not the GIL, is the roof for `sqrt` over 64 MB. **Pattern:** batch work into large C-level calls that release the GIL (NumPy, Arrow compute, hashlib/zlib on big buffers, your own extension with `Py_BEGIN_ALLOW_THREADS`), then threads are a legitimate parallelism tool even on GIL builds.

### 2.2 Trap: a CPU-bound thread next to an I/O thread — the convoy effect

```python
"""gil_convoy.py - the convoy effect: an I/O thread's latency when a CPU-bound thread owns the GIL.

An echo thread blocks in recv() (GIL released). When the ping arrives it must re-take the GIL; the CPU-bound
thread only yields after the waiter has timed out for one switch interval and set gil_drop_request.
Round trip = up to 2 handoffs, so RTT tracks sys.setswitchinterval(), not the network.
Also measures the time-slice length directly: two CPU threads log timestamps; a run of one thread = one slice.
Windows: the GIL wait is SleepConditionVariableSRW(us/1000 ms) - truncated to whole ms, then rounded up to the
OS timer tick (~15.6 ms by default); intervals below 1 ms truncate to 0 and hand off at once (Python/condvar.h).
"""
import socket
import statistics
import sys
import threading
import time

PINGS = 200


def echo(sock):
    while True:
        b = sock.recv(1)
        if not b or b == b"q":
            return
        sock.sendall(b)


def hog(stop):
    x = 0
    while not stop.is_set():
        for i in range(10_000):
            x += i


def rtt(hogs, interval):
    sys.setswitchinterval(interval)
    a, b = socket.socketpair()
    server = threading.Thread(target=echo, args=(b,))
    server.start()
    stop = threading.Event()
    hs = [threading.Thread(target=hog, args=(stop,)) for _ in range(hogs)]
    for h in hs:
        h.start()
    time.sleep(0.05)
    lat = []
    for _ in range(PINGS):
        t0 = time.perf_counter()
        a.sendall(b"p")
        a.recv(1)
        lat.append(time.perf_counter() - t0)
    stop.set()
    a.sendall(b"q")
    server.join()
    for h in hs:
        h.join()
    a.close()
    b.close()
    lat.sort()
    return statistics.median(lat), lat[int(0.99 * len(lat)) - 1]


print(f"== A. echo round trip over a local socketpair ({PINGS} pings), median / p99")
print(f"{'CPU hogs':>9} {'switch interval':>16} {'median':>10} {'p99':>10}")
rows = {}
for hogs, interval in [(0, 0.005), (1, 0.005), (1, 0.001), (1, 0.0005), (2, 0.005), (2, 0.0005)]:
    med, p99 = rtt(hogs, interval)
    rows[(hogs, interval)] = med
    print(f"{hogs:>9} {interval * 1e3:13.1f} ms {med * 1e6:8.0f}us {p99 * 1e6:8.0f}us")
sys.setswitchinterval(0.005)
assert rows[(1, 0.005)] > 10 * rows[(0, 0.005)], "one CPU hog should inflate RTT by an order of magnitude"
assert rows[(1, 0.0005)] < rows[(1, 0.005)]

print("== B. measured GIL time slices: 2 CPU-bound threads, timestamps every 5k iterations")


def logger(log, tid, n):
    for i in range(n):
        if i % 5_000 == 0:
            log.append((tid, time.perf_counter()))


print(f"  platform: {sys.platform}")
for interval in (0.005, 0.001, 0.0005):
    sys.setswitchinterval(interval)
    log = []
    ts = [threading.Thread(target=logger, args=(log, k, 4_000_000)) for k in range(2)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    slices, start = [], 0
    for i in range(1, len(log)):
        if log[i][0] != log[i - 1][0]:
            slices.append(log[i][1] - log[start][1])     # first sample of next run ~ handoff instant
            start = i
    slices = slices[1:-1]
    print(f"  switch interval {interval * 1e3:4.1f} ms -> {len(slices):4} handoffs, median slice "
          f"{statistics.median(slices) * 1e3:5.2f} ms")
sys.setswitchinterval(0.005)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run, Windows):

```text
== A. echo round trip over a local socketpair (200 pings), median / p99
 CPU hogs  switch interval     median        p99
        0           5.0 ms       47us      573us
        1           5.0 ms    35106us    97927us
        1           1.0 ms    32186us    79341us
        1           0.5 ms       56us      216us
        2           5.0 ms    67912us   137653us
        2           0.5 ms       58us      223us
== B. measured GIL time slices: 2 CPU-bound threads, timestamps every 5k iterations
  platform: win32
  switch interval  5.0 ms ->   18 handoffs, median slice 15.84 ms
  switch interval  1.0 ms ->   21 handoffs, median slice 15.61 ms
  switch interval  0.5 ms -> 1512 handoffs, median slice  0.23 ms
ALL ASSERTIONS PASSED
```

One CPU hog turns a ~35–50 µs local round trip into **~35 ms**, a thousandfold, with p99 near 100 ms. Two hogs double it (≈ 68 ms). On this OS lowering the interval to 1 ms changes nothing (still one timer tick), while 0.5 ms "fixes" latency by making the holder yield almost immediately. That shows up in part B as ~1,300–1,500 handoffs per run, i.e. continuous context switching that taxes every CPU-bound thread. **Pattern:** never co-locate latency-sensitive I/O threads with pure-Python CPU work in one process. Move the CPU work to processes or subinterpreters (01.3) or into GIL-releasing C, or use a free-threaded build where the I/O thread doesn't need anyone's permission to run.

### 2.3 Trap: "the GIL makes it thread-safe"

```python
"""gil_is_not_a_lock.py - lost updates WITH the GIL: atomicity is an accident of where the eval breaker runs.

3.14's bytecode checks the eval breaker (where a GIL handoff can happen) only in RESUME, JUMP_BACKWARD and CALL.
`self.n += 1` has no CALL between its load and store, so it happens to survive; put a call in between and
updates vanish. A free-threaded build loses updates in both versions. Fix: a Lock, or a single C-level operation.
"""
import itertools
import sys
import threading
import time

THREADS, PER = 4, 200_000
sys.setswitchinterval(0.0005)            # < 1 ms: frequent handoffs on every platform (see gil_convoy.py)


class Counter:
    def __init__(self):
        self.n = 0
        self.lock = threading.Lock()


def noop():
    pass


def inc_inline(c):
    for _ in range(PER):
        c.n += 1                          # LOAD_ATTR, BINARY_OP, STORE_ATTR: no CALL inside


def inc_with_call(c):
    for _ in range(PER):
        v = c.n
        noop()                            # CALL -> _CHECK_PERIODIC: another thread may run here
        c.n = v + 1


def inc_locked(c):
    for _ in range(PER):
        with c.lock:
            v = c.n
            noop()
            c.n = v + 1


ids = itertools.count()
seen = []


def take_ids(_):
    out = seen.append
    for _ in range(PER):
        out(next(ids))                    # one C call: the GIL (or the object's lock) covers it


def run(fn):
    c = Counter()
    ts = [threading.Thread(target=fn, args=(c,)) for _ in range(THREADS)]
    t0 = time.perf_counter()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return c.n, time.perf_counter() - t0


want = THREADS * PER
print(f"GIL enabled: {getattr(sys, '_is_gil_enabled', lambda: True)()}; {THREADS} threads x {PER:,} increments"
      f" = {want:,} expected")
results = {}
for label, fn in [("c.n += 1 (no call between)", inc_inline), ("v = c.n; noop(); c.n = v + 1", inc_with_call),
                  ("same, under threading.Lock", inc_locked)]:
    got, dt = run(fn)
    results[label] = got
    print(f"  {label:32} final={got:>9,}  lost={want - got:>9,}  {dt / want * 1e9:6.1f} ns/increment")
run(take_ids)
print(f"  {'next(itertools.count()) ids':32} unique={len(set(seen)):>8,}  dupes={len(seen) - len(set(seen)):>9,}")
assert results["same, under threading.Lock"] == want
assert results["v = c.n; noop(); c.n = v + 1"] < want, "expected lost updates with a CALL inside the window"
assert len(set(seen)) == want
sys.setswitchinterval(0.005)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; the lost count varies):

```text
GIL enabled: True; 4 threads x 200,000 increments = 800,000 expected
  c.n += 1 (no call between)       final=  800,000  lost=        0    39.2 ns/increment
  v = c.n; noop(); c.n = v + 1     final=  285,714  lost=  514,286    65.0 ns/increment
  same, under threading.Lock       final=  800,000  lost=        0   366.7 ns/increment
  next(itertools.count()) ids      unique= 800,000  dupes=        0
ALL ASSERTIONS PASSED
```

`c.n += 1` survives only because no `CALL` sits between its load and store. Add one call and ~65 % of increments vanish *with the GIL enabled*. On a free-threaded build both variants lose updates. `next(itertools.count())` and `list.append` are single C-level operations and stay correct. **Pattern:** make shared mutable state either (a) owned by one thread (queues, actors), (b) updated by one C-level operation, or (c) guarded by a lock, and shard hot locks, because the cost here goes from ≈ 38 ns (no lock) to ≈ 368 ns per increment under a contended lock.

### 2.4 Biased refcounting, measured in C

The question PEP 703 had to answer is what a refcount update costs when it must be thread-safe. Four ways to do one incref+decref pair, on 1–6 threads:

```c
/* brc_physics.c - why free-threaded CPython splits the refcount (PEP 703 biased refcounting), measured in C.
 *
 * One INCREF+DECREF pair per op, four ways:
 *   owner-local   : relaxed load + store of a thread-owned uint32 (ob_ref_local fast path: plain mov, no lock)
 *   atomic-private: lock xadd on a counter only this thread touches (what naive atomic refcounting costs)
 *   atomic-shared : lock xadd on ONE counter shared by all threads (ob_ref_shared of a hot object)
 *   immortal-check: relaxed load + compare of a shared word, no store (Py_INCREF on an immortal)
 * Build: gcc -O2 -std=c11 -pthread brc_physics.c -o brc_physics
 */
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

#define PAIRS 5000000u
#define MAXT 6

typedef struct {
    _Alignas(64) _Atomic uint32_t ob_ref_local;   /* one object per 64-byte line: no false sharing */
    _Atomic int64_t ob_ref_shared;
} obj_t;

static obj_t shared_obj = {UINT32_MAX, 0};        /* UINT32_MAX = _Py_IMMORTAL_REFCNT_LOCAL */
static obj_t owned[MAXT];
static pthread_barrier_t start_line;
static volatile uint64_t sink;

enum mode { OWNER_LOCAL, ATOMIC_PRIVATE, ATOMIC_SHARED, IMMORTAL_CHECK };
struct job { int tid; enum mode m; double secs; };

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void *worker(void *arg) {
    struct job *j = arg;
    obj_t *mine = &owned[j->tid];
    uint64_t skipped = 0;
    pthread_barrier_wait(&start_line);
    double t0 = now();
    for (uint32_t i = 0; i < PAIRS; i++) {
        switch (j->m) {
        case OWNER_LOCAL: {
            uint32_t v = atomic_load_explicit(&mine->ob_ref_local, memory_order_relaxed);
            atomic_store_explicit(&mine->ob_ref_local, v + 1, memory_order_relaxed);
            v = atomic_load_explicit(&mine->ob_ref_local, memory_order_relaxed);
            atomic_store_explicit(&mine->ob_ref_local, v - 1, memory_order_relaxed);
            break;
        }
        case ATOMIC_PRIVATE:
            atomic_fetch_add_explicit(&mine->ob_ref_shared, 4, memory_order_relaxed);   /* 1 << _Py_REF_SHARED_SHIFT */
            atomic_fetch_sub_explicit(&mine->ob_ref_shared, 4, memory_order_release);
            break;
        case ATOMIC_SHARED:
            atomic_fetch_add_explicit(&shared_obj.ob_ref_shared, 4, memory_order_relaxed);
            atomic_fetch_sub_explicit(&shared_obj.ob_ref_shared, 4, memory_order_release);
            break;
        case IMMORTAL_CHECK:
            skipped += atomic_load_explicit(&shared_obj.ob_ref_local, memory_order_relaxed) == UINT32_MAX;
            skipped += atomic_load_explicit(&shared_obj.ob_ref_local, memory_order_relaxed) == UINT32_MAX;
            break;
        }
    }
    j->secs = now() - t0;
    sink += skipped;
    return NULL;
}

static void run(enum mode m, int threads, const char *name) {
    pthread_t th[MAXT];
    struct job jobs[MAXT];
    pthread_barrier_init(&start_line, NULL, (unsigned)threads);
    for (int t = 0; t < threads; t++) {
        jobs[t] = (struct job){t, m, 0};
        pthread_create(&th[t], NULL, worker, &jobs[t]);
    }
    double worst = 0;
    for (int t = 0; t < threads; t++) {
        pthread_join(th[t], NULL);
        if (jobs[t].secs > worst) worst = jobs[t].secs;
    }
    pthread_barrier_destroy(&start_line);
    printf("  %-15s threads=%d  %7.2f ns per incref+decref pair  %8.1f M pairs/s total\n", name, threads,
           worst / PAIRS * 1e9, threads * (double)PAIRS / worst / 1e6);
}

int main(void) {
    static const char *names[] = {"owner-local", "atomic-private", "atomic-shared", "immortal-check"};
    for (int m = OWNER_LOCAL; m <= IMMORTAL_CHECK; m++) {
        for (int t = 1; t <= MAXT; t = (t == 1 ? 2 : t + 2)) run((enum mode)m, t, names[m]);
    }
    if (atomic_load(&shared_obj.ob_ref_shared) != 0) return 1;   /* every incref was matched */
    for (int t = 0; t < MAXT; t++)
        if (atomic_load(&owned[t].ob_ref_shared) != 0 || atomic_load(&owned[t].ob_ref_local) != 0) return 1;
    puts("ALL CHECKS PASSED (counters balanced)");
    return 0;
}
```

Output (one measured run):

```text
  owner-local     threads=1     1.07 ns per incref+decref pair     930.3 M pairs/s total
  owner-local     threads=2     0.86 ns per incref+decref pair    2317.7 M pairs/s total
  owner-local     threads=4     0.94 ns per incref+decref pair    4241.3 M pairs/s total
  owner-local     threads=6     1.60 ns per incref+decref pair    3742.7 M pairs/s total
  atomic-private  threads=1     9.70 ns per incref+decref pair     103.1 M pairs/s total
  atomic-private  threads=2     9.63 ns per incref+decref pair     207.6 M pairs/s total
  atomic-private  threads=4    17.97 ns per incref+decref pair     222.6 M pairs/s total
  atomic-private  threads=6    17.08 ns per incref+decref pair     351.3 M pairs/s total
  atomic-shared   threads=1     9.30 ns per incref+decref pair     107.5 M pairs/s total
  atomic-shared   threads=2    36.08 ns per incref+decref pair      55.4 M pairs/s total
  atomic-shared   threads=4    88.41 ns per incref+decref pair      45.2 M pairs/s total
  atomic-shared   threads=6   141.33 ns per incref+decref pair      42.5 M pairs/s total
  immortal-check  threads=1     0.81 ns per incref+decref pair    1239.8 M pairs/s total
  immortal-check  threads=2     0.88 ns per incref+decref pair    2259.9 M pairs/s total
  immortal-check  threads=4     0.90 ns per incref+decref pair    4466.9 M pairs/s total
  immortal-check  threads=6     1.66 ns per incref+decref pair    3617.6 M pairs/s total
ALL CHECKS PASSED (counters balanced)
```

* **owner-local** (what the owner thread pays): ~1 ns per pair; throughput scales with threads because every thread owns its own line.
* **atomic-private**: making *every* refcount atomic costs ~10× even with zero contention (`lock add` / `lock sub`, each a full barrier on x86). That's why "just make refcounts atomic" (the 2016 Gilectomy) ran single-threaded code far slower.
* **atomic-shared**: one hot object touched by every thread is a cache line ping-ponging between cores. Per-pair cost rises to **≈ 140 ns at 6 threads**, and *total* throughput is flat at ~42–57 M pairs/s no matter how many threads you add. This is the free-threaded scaling cliff for shared mutable objects, and why types, functions, code and globals get deferred or per-thread counting.
* **immortal-check**: a read-only shared line stays in every core's cache in Shared state, giving ≈ 0.8–1.7 ns at 1–6 threads, owner-local speed.

🧊 The same physics in C++: `std::shared_ptr` copies cost ~10 ns and 41–62 ns under contention (see the Modern C++ KB, Folder 05). CPython's biased scheme is effectively an intrusive count that is non-atomic for one owner and atomic for everyone else.

### 2.5 Probe: what actually scales on *your* free-threaded build

```python
"""ft_scaling_probe.py - thread scaling of pure-Python work on whichever build runs it (GIL or 3.14t/3.15t).

Three shapes of the same arithmetic. On a GIL build all three stay near 1x. On a free-threaded build the
prediction from biased refcounting is: private data scales; summing a SHARED list of mortal ints pays an atomic
ob_ref_shared RMW per element read by a non-owner thread (contended cache lines); shared IMMORTAL ints
(small-int cache) skip refcounting entirely and scale again. Run it on both builds and compare.
"""
import sys
import sysconfig
import threading
import time

N = 400_000
SHARED_MORTAL = [10**6 + (i % 1000) for i in range(N)]     # owned by the main thread, refcounted
SHARED_IMMORTAL = [i % 200 for i in range(N)]               # small-int cache: immortal, never refcounted


def private_work():
    data = [10**6 + (i % 1000) for i in range(N)]          # each thread builds and owns its data
    return sum(x * 2 for x in data)


def shared_mortal():
    return sum(x * 2 for x in SHARED_MORTAL)


def shared_immortal():
    return sum(x * 2 for x in SHARED_IMMORTAL)


def timed(fn, threads, units=4):
    def body(k):
        for _ in range(k):
            fn()
    per = units // threads
    ts = [threading.Thread(target=body, args=(per,)) for _ in range(threads)]
    t0 = time.perf_counter()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return time.perf_counter() - t0


gil = getattr(sys, "_is_gil_enabled", lambda: True)()
print(f"Python {sys.version.split()[0]}  Py_GIL_DISABLED={sysconfig.get_config_var('Py_GIL_DISABLED')}  "
      f"GIL enabled at runtime={gil}")
print(f"{'workload (4 units of work)':34} {'1 thr':>8} {'2 thr':>8} {'4 thr':>8} {'speedup@4':>10}")
for label, fn in [("private data per thread", private_work), ("shared list, mortal ints", shared_mortal),
                  ("shared list, immortal small ints", shared_immortal)]:
    fn()
    t = {k: min(timed(fn, k) for _ in range(2)) for k in (1, 2, 4)}
    print(f"{label:34} {t[1] * 1e3:6.0f}ms {t[2] * 1e3:6.0f}ms {t[4] * 1e3:6.0f}ms {t[1] / t[4]:9.2f}x")
print("probe complete")
```

Output (measured on the default GIL build: everything ~1×, as §1.1 predicts):

```text
Python 3.14.5  Py_GIL_DISABLED=0  GIL enabled at runtime=True
workload (4 units of work)            1 thr    2 thr    4 thr  speedup@4
private data per thread               165ms    158ms    161ms      1.03x
shared list, mortal ints               58ms     64ms     60ms      0.98x
shared list, immortal small ints       51ms     51ms     51ms      0.99x
probe complete
```

⚠ **Prediction for 3.14t/3.15t (not measured here; run the probe and compare).**

| Workload | Mechanism | Expected scaling at 4 threads |
|---|---|---|
| private data per thread | every object owned by its thread → `ob_ref_local` plain stores | near-linear (≈ 3–4×) |
| shared list of **mortal** ints | each read by a non-owner = atomic `ob_ref_shared` RMW on the owner's objects; lines shared across cores | sub-linear; can fall below 1× per thread |
| shared list of **immortal** small ints | `ob_ref_local == UINT32_MAX` → skipped before any write | near-linear again |

The design rule to remember is that in free-threaded Python, **sharing is free when the data is immutable *and* immortal, cheap when it's owned, and expensive when it's mortal and shared**. That pushes architectures towards thread-owned state plus message passing, or shared data in buffers (NumPy/Arrow) whose elements aren't Python objects at all.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 ⚡ | Thread pool added, throughput unchanged | `py-spy dump` shows one thread running, others in `take_gil`; CPU ≈ 100 % of one core | Pure-Python CPU work serializes on the GIL | Processes / `InterpreterPoolExecutor` (01.3); move the kernel to NumPy/C with `Py_BEGIN_ALLOW_THREADS` | Classify each workload as bytecode-bound or C-bound before choosing threads |
| F2 🔥 | Health checks or RPC latency spike to tens of ms under load | p50 latency ≈ switch interval; ~16 ms quanta on Windows | Convoy effect: I/O thread waits a full interval for the CPU-bound holder | Isolate CPU work in other processes; keep the I/O process CPU-light | SLO alerts on event-loop/thread wakeup lag, not only request latency |
| F3 🔥 | Counters drift, duplicate IDs, "impossible" states | Lost updates under load; disappear when a `print` is added | Compound read-modify-write across a `CALL`; GIL atomicity is accidental | `threading.Lock`; single C-level ops (`itertools.count`, `queue.Queue`); ownership | Treat every shared mutable as racy; test with `sys.setswitchinterval(1e-6)` to amplify races |
| F4 🔥 | Migrated to 3.14t, zero speedup | `RuntimeWarning: The global interpreter lock (GIL) has been enabled to load module ...`; `sys._is_gil_enabled()` → True | An extension without `Py_mod_gil = Py_MOD_GIL_NOT_USED` re-enabled the GIL process-wide | Upgrade to `cp314t`/`abi3t` wheels; audit `pip list` for C extensions | CI: `python -X gil=0 -W error::RuntimeWarning -c "import yourapp"`, plus assert `not sys._is_gil_enabled()` |
| F5 ⚡ | 3.14t scales to 2 threads, then flattens | `perf c2c` / VTune shows HITM on one line; atomic RMW hot spot | Shared mortal hot object (config dict, shared list, a global instance) → `ob_ref_shared` ping-pong | Make it immutable + immortal where possible; per-thread copies; pass small values, not shared objects | Design for thread-owned state; review globals touched in hot loops |
| F6 | Memory +20–50 % after switching to free-threaded | Same object counts, larger RSS | 32 B headers (16 B before), mimalloc page overhead, QSBR-delayed frees | Re-budget; move bulk data into buffers | Capacity-test both builds; track `sys._is_gil_enabled()` in metrics |
| F7 | `sys.setswitchinterval(0.0005)` "fixed latency" but throughput fell | Thousands of GIL handoffs per second; high context-switch rate | Windows truncates < 1 ms waits to 0 → immediate drop requests | Remove the knob; isolate workloads instead | Never tune the interval without measuring both latency and throughput |
| F8 🔥 | Process hangs; one thread in C code waiting for a lock, another waiting for the GIL | Native stacks: thread A holds the GIL and waits for lock L; thread B holds L inside a C callback and calls `PyGILState_Ensure` | Lock-ordering inversion between the GIL and a library lock | Release the GIL (`Py_BEGIN_ALLOW_THREADS`) before taking library locks; never call into Python while holding one | Code review rule for every extension: no Python calls under native locks |
| F9 | A C extension crashes only on 3.14t | Use-after-free in `PyList_GET_ITEM` / `PyDict_GetItem` (borrowed refs) under concurrency | Borrowed references aren't safe once other threads can mutate the container | Use strong-ref APIs (`PyList_GetItemRef`, `PyDict_GetItemRef`) and critical sections | Build extensions with `Py_GIL_DISABLED` in CI; run TSan builds |
| F10 | Lock-protected counter is 10× slower under 4 threads | ≈ 368 ns/increment vs ≈ 38 ns without the lock | Contended `threading.Lock` + handoff latency | Shard counters per thread and merge; batch updates | Benchmark contended, not just uncontended, paths |

**Debugging toolkit.** `py-spy dump --native --pid N` shows who holds or waits for the GIL. `sys._is_gil_enabled()` and `sysconfig.get_config_var("Py_GIL_DISABLED")` tell you the build and runtime state. `python -X gil=0` forces it off. `PYTHON_GIL=0` sets the same in the environment. On Linux use `perf c2c record` (cache-line contention, HITM) for F5 and a TSan-instrumented CPython build for F9.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Walk me through exactly how one thread takes the GIL from another."</b></summary>

**Initial Prompt.** Two Python threads are CPU-bound. Describe, at the level of the C code, how control passes from A to B.

**L5 Answer.** "Every 5 ms the interpreter switches threads. The GIL is a mutex they take turns on."

**Why L5 Crashes at Scale.** Nothing preempts A on a timer. B *asks*, and only after waiting. A notices only at specific bytecodes, and the waiting is subject to OS timer resolution. Engineers who believe "5 ms round-robin" mis-diagnose 16 ms (Windows) or 35 ms (two handoffs) latency spikes and tune the wrong knob.

**L7 Principal Defense.** B waits on `gil->cond` with a timeout of `interval`. If it times out and `switch_number` hasn't changed, it sets `_PY_GIL_DROP_REQUEST_BIT` in A's `eval_breaker`. A observes it at the next `_CHECK_PERIODIC`, which exists only in `RESUME`, `JUMP_BACKWARD` and `CALL`. A drops the GIL, signals `cond`, and with `FORCE_SWITCHING` waits on `switch_cond` until `last_holder != A`, so it can't immediately re-grab. B takes it and increments `switch_number`. Consequences: a long-running C call that doesn't release the GIL stalls everyone indefinitely; straight-line bytecode between check points is uninterruptible; and on Windows the wait is `SleepConditionVariableSRW(us/1000)`, so the effective slice is a timer tick (~16 ms measured), not 5 ms.

</details>

<details><summary><b>Q2 · "Our 8-thread CPU job got no faster. The vendor says use multiprocessing. Is that the only answer in 2026?"</b></summary>

**Initial Prompt.** A pure-Python feature-computation step runs in a `ThreadPoolExecutor(8)` with a 1.0× speedup.

**L5 Answer.** "Yes, the GIL prevents parallelism. Use `multiprocessing.Pool`."

**Why L5 Crashes at Scale.** `multiprocessing` adds process startup (223–266 ms measured for 4 spawn workers), pickling of every argument and result, and N copies of every module and cache. For data-heavy steps the serialization can exceed the compute (01.3: ≈ 155–170 ms to pickle 128 MiB). The L5 answer also ignores three newer options.

**L7 Principal Defense.** Choose by where the time goes. (1) If the kernel can be vectorized (NumPy, Polars, Arrow), do that first: it's a 10–50× win *and* releases the GIL, so threads then scale (2–3.5× measured). (2) If it must stay pure Python, `InterpreterPoolExecutor` (3.14, PEP 734) gives one GIL per subinterpreter inside one process: 2.4–3.1× on 4 workers measured, with cheaper startup than spawn (≈ 145 ms). (3) For shared-memory parallelism without pickling, a free-threaded build, but only after auditing extensions for `Py_mod_gil` and redesigning shared mutable state (biased refcounting punishes it). (4) Processes remain right for isolation (crash containment, memory caps per worker).

</details>

<details><summary><b>Q3 · "Explain biased reference counting and why it isn't just 'atomic refcounts'."</b></summary>

**Initial Prompt.** PEP 703 needed thread-safe refcounting. Why not make `ob_refcnt` atomic?

**L5 Answer.** "Atomic refcounts are slow, so they use two counters, one per thread."

**Why L5 Crashes at Scale.** "One per thread" is wrong, and without the real mechanism you can't predict which workloads scale. Uniformly atomic counts cost ~10× on *every* incref even single-threaded (measured ≈ 10 ns against ≈ 1 ns per pair), which was the Gilectomy's failure. And the cost of contended atomics on shared objects (≈ 140 ns at 6 threads) doesn't go away just because there are two fields.

**L7 Principal Defense.** Each object records its creating thread in `ob_tid`. The owner updates `ob_ref_local` with relaxed load/store (plain `mov`). Every other thread does an atomic add on `ob_ref_shared`, shifted left by 2, whose two low bits encode `MAYBE_WEAKREF`/`QUEUED`/`MERGED`. If a non-owner's decrement would take the shared count below zero, the object is queued to the owner (`brc.c`) via the eval breaker, and the owner merges the fields. The objects that defeat the bias (types, functions, modules, code, globals, singletons) are handled separately by immortalization, deferred refcounting and per-thread refcount arrays. The architectural takeaway is that **owned or immortal is cheap, mortal and shared is expensive**. Design data ownership accordingly.

</details>

<details><summary><b>Q4 · "Is `dict` thread-safe in free-threaded Python? Is my code?"</b></summary>

**Initial Prompt.** Our service mutates a module-level `dict` cache from many threads. Moving to 3.14t: what breaks?

**L5 Answer.** "Dicts have per-object locks now, so it's safe."

**Why L5 Crashes at Scale.** Per-object locks protect the dict's *integrity* per operation. They don't make `if k not in d: d[k] = compute()` atomic: two threads compute and both store, and with expensive `compute()` you stampede. Critical sections are also *suspended* whenever the thread blocks, including inside a key's `__eq__`/`__hash__` that takes a lock, so even single operations can interleave at blocking points.

**L7 Principal Defense.** Separate the guarantees. Integrity of built-ins is guaranteed: `ob_mutex` + critical sections, with lock-free reads via `_Py_TryXGetRef` and QSBR-delayed frees. Atomicity of compound logic is never guaranteed and needs `setdefault`-style single operations, an explicit `Lock`, or a per-key future (singleflight). Also check *performance*. A dict read by every thread on every request is a shared mortal object, but module globals dicts get per-thread refcounting. Most of the cost is in the *values* you return: a shared mutable value object is refcounted atomically on every access. Return immutable or immortal values, or copy per thread.

</details>

<details><summary><b>Q5 · "We installed 3.14t and `sys._is_gil_enabled()` returns True. Why?"</b></summary>

**Initial Prompt.** The benchmark shows no scaling on the free-threaded interpreter.

**L5 Answer.** "Maybe you installed the wrong Python. Reinstall `python3.14t`."

**Why L5 Crashes at Scale.** The interpreter is right. A single import re-enabled the GIL *process-wide and permanently*, and a production fleet would silently run at GIL speed while paying the free-threaded memory overhead (+16 B per object).

**L7 Principal Defense.** `Python/import.c` enables the GIL permanently when loading a module whose `md_gil` isn't `Py_MOD_GIL_NOT_USED`, and emits the `RuntimeWarning` "…has been enabled to load module '…'". Find it with `-W error::RuntimeWarning`. Fix it by upgrading to wheels built for `cp314t` (or `abi3t` on 3.15, PEP 803). `PYTHON_GIL=0` is an override "at your own risk" for extensions you've audited. Make it a CI gate: import the full application under `-X gil=0 -W error::RuntimeWarning` and assert `not sys._is_gil_enabled()`.

</details>

<details><summary><b>Q6 · "Why does QSBR exist in CPython? Isn't the GC enough?"</b></summary>

**Initial Prompt.** The free-threaded build added quiescent-state-based reclamation. What problem does it solve that refcounting and GC don't?

**L5 Answer.** "It's part of the garbage collector for threads."

**Why L5 Crashes at Scale.** QSBR isn't about *objects* (refcounts handle those). It's about *internal buffers* read without locks: list item arrays and dict key tables. Without it, lock-free readers would read freed memory during a concurrent resize, giving rare, unreproducible crashes in exactly the hottest code.

**L7 Principal Defense.** Readers of `list[i]` load `ob_item` atomically and try-incref the item without taking `ob_mutex`. When a writer resizes, the old array may still be under a reader, so it goes to `_PyMem_FreeDelayed`, tagged with the current write sequence (odd; +2 per advance). Each thread reports a quiescent state at eval-breaker checks and on detach (offline = 0), and the buffer is freed when every attached thread has passed the tag. Read side costs nothing; the price is bounded memory retention when a thread runs a long C call without passing a quiescent point. It's the same trade-off as Linux RCU and the epoch reclamation in the C++ KB Folder 09, and it explains two production observations: free-threaded memory can lag behind frees, and long non-yielding C calls delay reclamation for everyone.

</details>

<details><summary><b>Q7 · "Your health-check endpoint times out whenever the batch thread runs. Fix it without rewriting the batch."</b></summary>

**Initial Prompt.** A Flask app runs a background thread that rebuilds a recommendation index in pure Python every minute. During rebuilds, `/healthz` takes 20–80 ms and the load balancer marks pods unhealthy.

**L5 Answer.** "Lower `sys.setswitchinterval` so the health thread gets scheduled more often."

**Why L5 Crashes at Scale.** On Windows, anything from 1 to 15 ms changes nothing (one timer tick) and < 1 ms causes constant handoffs (~1,500 per run measured) that slow the rebuild. On Linux it trades rebuild throughput for latency. Either way it treats the symptom, and a third thread doubles the latency again (2 hogs → ≈ 68 ms median measured).

**L7 Principal Defense.** The convoy effect is structural: the latency-critical thread must wait for the holder's next check point plus a timer-quantized wait. Move the rebuild out of the serving process, into a `ProcessPoolExecutor` or `InterpreterPoolExecutor` worker that publishes the finished index via shared memory or an atomic file swap (01.3). Or vectorize the rebuild so it runs in GIL-releasing C. Keep the serving process's CPU work below ~1 ms per request. Monitor *wakeup lag* (scheduled vs actual time of a heartbeat) as an SLI, since it exposes convoy problems before request latency does.

</details>

<details><summary><b>Q8 · "What does free-threading cost a single-threaded service, and when should we adopt it?"</b></summary>

**Initial Prompt.** Leadership asks whether to standardize on free-threaded Python for all services in 2026.

**L5 Answer.** "Yes, removing the GIL makes Python faster."

**Why L5 Crashes at Scale.** Single-threaded code gets *slower*: 3.14's What's New quotes a 5–10 % penalty. Memory grows (32 B headers, mimalloc pages). Extension coverage decides whether the GIL even stays off. Latent races that the GIL's accidental atomicity hid (§2.3) become real.

**L7 Principal Defense.** Adopt per workload, not per fleet. Free-threading pays when there's (a) CPU-bound pure-Python work that can't be vectorized, (b) parallelism that needs shared in-memory state too large or too mutable to pickle, and (c) dependencies all published as `cp314t`/`abi3t` wheels. Request-per-process web services, NumPy/Polars-heavy pipelines and I/O-bound asyncio services gain little and pay the penalty. Run both builds in CI. Gate on `sys._is_gil_enabled()`. Load-test the shared-state paths for `ob_ref_shared` contention. Keep the GIL build as the default until the benchmark on *your* workload says otherwise. The build is supported (PEP 779) but "still optional", and phase III (default) is explicitly undecided.

</details>

<details><summary><b>Q9 · "Why is `ctypes` a good way to prove a GIL hypothesis?"</b></summary>

**Initial Prompt.** You suspect a third-party C library doesn't release the GIL. How do you prove it in five minutes?

**L5 Answer.** "Read the source and look for `Py_BEGIN_ALLOW_THREADS`."

**Why L5 Crashes at Scale.** The library may release the GIL conditionally: on input size (hashlib's 2048-byte threshold), on dtype, or only in some code paths. Source reading misses runtime behaviour, and a production profile can't easily separate GIL wait from compute.

**L7 Principal Defense.** Make the GIL the only variable. Run the same work 1×4 sequentially and 4×1 on threads and compute the speedup, as in `gil_release_scaling.py`. As a control, call a known C loop through `ctypes.CDLL` (releases the GIL, ≈ 3.5× measured) against `ctypes.PyDLL` (holds it, 1.0×). If the library behaves like `PyDLL`, it holds the GIL, and you also learn the size thresholds (64 B `sha256` updates: 0.9×). Then confirm with `py-spy dump --native` showing threads parked in `take_gil`. Thirty lines of Python replace hours of source spelunking and give a number to attach to the bug report.

</details>

<details><summary><b>Q10 · "Compare CPython's free-threading design to the JVM's. What did each get right?"</b></summary>

**Initial Prompt.** As a JVM architect, critique PEP 703's design choices.

**L5 Answer.** "The JVM never had a GIL, so Python is just catching up."

**Why L5 Crashes at Scale.** It ignores the constraint that shaped everything: CPython's C API exposes refcounting and borrowed references to thousands of extensions, so a moving, tracing GC (the JVM's answer) was off the table. It also ignores that the JVM *removed* biased locking (JDK 15 deprecation, JDK 18 removal) because revocation costs outgrew its benefit on modern CPUs. That precedent tells you when biasing pays.

**L7 Principal Defense.** The JVM avoids refcount traffic entirely (tracing GC, TLABs, safepoints) and pays with GC complexity. CPython had to keep refcounts for C-API compatibility, so it biased them. That works because increfs are vastly more frequent and more thread-local than monitor entries were. It immortalizes and defers the objects that break the bias, segregates mimalloc heaps so optimistic readers are safe, and uses QSBR where the JVM relies on GC for safe reclamation. Critical sections that suspend on blocking are a deliberately weaker contract than `synchronized` (deadlock-free, not atomic-across-blocking). The JVM's lesson that carries over is to measure the bias assumption on your workload: a design where objects are shared mutable across threads will behave like the JVM's revoked biased locks, slower than not biasing at all.

</details>

---

## 5. Invariants Checklist

- [ ] The GIL serializes **bytecode**, not your logic. Switches happen only at `RESUME` / `JUMP_BACKWARD` / `CALL` checks, after a waiter times out.
- [ ] Threads scale on a GIL build only inside C code that called `Py_BEGIN_ALLOW_THREADS` (hashlib ≥ 2048 B, zlib, NumPy loops, `ctypes.CDLL`, I/O).
- [ ] The switch interval is OS-quantized: ~16 ms slices on Windows for 1–15 ms settings; < 1 ms truncates to 0.
- [ ] The convoy effect: I/O threads sharing a process with CPU-bound Python threads get interval-quantized latency.
- [ ] No compound operation is atomic on either build. A `CALL` between read and write loses updates *with* the GIL.
- [ ] Free-threaded refcount cost: owner ≈ 1 ns, uncontended atomic ≈ 10 ns, contended shared ≈ 36–140 ns, immortal ≈ 1 ns. Design for owned or immortal data.
- [ ] One unaudited extension re-enables the GIL process-wide (`Py_mod_gil`). Gate CI on `sys._is_gil_enabled()`.
- [ ] Free-threaded headers are 32 B; expect +20–50 % memory for object-heavy services.
- [ ] Free-threaded critical sections suspend on blocking: integrity yes, atomicity across blocking no.
- [ ] QSBR delays frees of internal buffers until all threads pass a quiescent state. Long non-yielding C calls delay reclamation.

---

## 6. References

**CPython source (pinned tags)**
- `Python/ceval_gil.c` (take_gil/drop_gil, FORCE_SWITCHING design comment) — https://github.com/python/cpython/blob/v3.14.10/Python/ceval_gil.c
- `Python/condvar.h` (Windows `SleepConditionVariableSRW(us/1000)`) — https://github.com/python/cpython/blob/v3.14.10/Python/condvar.h
- `Include/internal/pycore_ceval.h` (eval-breaker bits) — https://github.com/python/cpython/blob/v3.14.10/Include/internal/pycore_ceval.h
- `Python/bytecodes.c` (`_CHECK_PERIODIC` placement) — https://github.com/python/cpython/blob/v3.14.10/Python/bytecodes.c
- `Include/refcount.h`, `Objects/object.c` (biased INCREF/DECREF, `_Py_DecRefSharedIsDead`) — https://github.com/python/cpython/blob/v3.14.10/Include/refcount.h
- `Python/brc.c` (merge queues) — https://github.com/python/cpython/blob/v3.14.10/Python/brc.c
- `Include/internal/pycore_qsbr.h` — https://github.com/python/cpython/blob/v3.14.10/Include/internal/pycore_qsbr.h
- `Include/cpython/critical_section.h` (design comment) — https://github.com/python/cpython/blob/v3.14.10/Include/cpython/critical_section.h
- `Include/internal/pycore_uniqueid.h` (per-thread refcounting) — https://github.com/python/cpython/blob/v3.14.10/Include/internal/pycore_uniqueid.h
- `Include/internal/pycore_mimalloc.h` (heap segregation) — https://github.com/python/cpython/blob/v3.14.10/Include/internal/pycore_mimalloc.h
- `Python/gc_free_threading.c` (stop-the-world heap walk, memory-aware trigger) — https://github.com/python/cpython/blob/v3.14.10/Python/gc_free_threading.c
- `Python/import.c` (GIL re-enable on `Py_mod_gil`) — https://github.com/python/cpython/blob/v3.14.10/Python/import.c
- What's New in 3.15 (PEP 803 abi3t, JIT, tail-calling Windows build) — https://docs.python.org/3.15/whatsnew/3.15.html

**PEPs**
- PEP 703 — Making the Global Interpreter Lock Optional: https://peps.python.org/pep-0703/
- PEP 779 — Criteria for supported status for free-threaded Python: https://peps.python.org/pep-0779/
- PEP 803 — Stable ABI for Free-Threaded Builds: https://peps.python.org/pep-0803/
- PEP 684 — A Per-Interpreter GIL: https://peps.python.org/pep-0684/
- PEP 683 — Immortal Objects: https://peps.python.org/pep-0683/

**Papers, talks, guides**
- J. Choi, T. Shull, J. Torrellas, "Biased Reference Counting: Minimizing Atomic Operations in Garbage Collection", PACT 2018, DOI 10.1145/3243176.3243195.
- D. Leijen, B. Zorn, L. de Moura, "Mimalloc: Free List Sharding in Action", APLAS 2019, DOI 10.1007/978-3-030-34175-6_13.
- P. McKenney, J. Slingwine, "Read-Copy Update: Using Execution History to Solve Concurrency Problems", PDCS 1998.
- D. Beazley, "Understanding the Python GIL", PyCon 2010 (talk and GIL papers index) — https://www.dabeaz.com/GIL/
- bpo-7946, "Convoy effect with I/O bound threads and New GIL" — https://bugs.python.org/issue7946
- Python docs, "Python support for free threading" — https://docs.python.org/3/howto/free-threading-python.html
- Community free-threading guide (porting, `abi3t`) — https://py-free-threading.github.io/
- JEP 374 — Deprecate and Disable Biased Locking: https://openjdk.org/jeps/374
