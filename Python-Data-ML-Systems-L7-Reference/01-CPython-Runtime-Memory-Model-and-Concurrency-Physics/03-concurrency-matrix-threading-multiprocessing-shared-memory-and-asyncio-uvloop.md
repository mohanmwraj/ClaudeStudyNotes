# 01.3 · The Concurrency Matrix: Threading, Multiprocessing, Subinterpreters, Shared Memory & asyncio/uvloop

> **Folder 01 · CPython Runtime, Memory Model & Concurrency Physics**
> **Measured on:** CPython 3.14.5 (GIL build), NumPy 2.5.4, psutil 7.2.2, Windows 11 (start method `spawn`, `ProactorEventLoop`), i5-11260H 6C/12T.
> **Source verified against:** `v3.14.10` `Lib/concurrent/futures/`, `Lib/multiprocessing/shared_memory.py`, `Lib/multiprocessing/context.py`, `Lib/asyncio/`, `Doc/whatsnew/3.12.rst`, `3.14.rst`.
> ⚠ **Not executed here:** `fork`/`forkserver` start methods, `/dev/shm` behaviour and **uvloop** (no Windows support). Those parts are marked and explained from source and docs.

---

## 0. Orientation & the JVM/C++ Bridge

Python gives you four ways to be concurrent. Each has a different unit of isolation, a different cost of crossing the boundary, and a different failure mode. Choosing among them is an architecture decision, not a library preference.

| Primitive | Unit of isolation | Parallel CPU? (GIL build) | Crossing cost | Memory cost per unit (measured) | JVM analogue | C++ analogue |
|---|---|---|---|---|---|---|
| `threading` / `ThreadPoolExecutor` | none (shared heap) | only inside GIL-releasing C | ~0 (shared refs) | ~58 KB committed per parked thread | platform threads | `std::thread` |
| `InterpreterPoolExecutor` (3.14, PEP 734) | subinterpreter (own GIL, own modules) | **yes**, in one process | pickle per call | per-interpreter module state | isolated classloader + thread (loosely) | — |
| `multiprocessing` / `ProcessPoolExecutor` | OS process | **yes** | pickle + pipe per call; spawn start-up | a whole interpreter per worker | separate JVMs | `fork`/`posix_spawn` + IPC |
| `asyncio` tasks | none (one thread, cooperative) | no | ~0 | **~1 KB per pending task** | virtual threads (JEP 444): stackful, no function colouring | C++20 coroutines (stackless, like Python's) |
| `multiprocessing.shared_memory` | named OS segment | — (a data plane, not a scheduler) | **name only**: pages are shared | the segment, once | off-heap `ByteBuffer` / `MappedByteBuffer` | `boost::interprocess`, `shm_open` + `mmap` |

The rule of thumb that falls out of §2: **use processes or subinterpreters for Python-bytecode CPU work, threads for GIL-releasing C and blocking I/O, asyncio for many concurrent waits, and shared memory whenever bulk data must cross a boundary.**

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 What actually crosses the boundary

```text
 ProcessPoolExecutor.submit(fn, big_array)
   parent:  pickle.dumps(args) ---> pipe (OS copy) ---> worker: pickle.loads -> NEW array (copy #2)
            128 MiB payload = serialize + 2 copies + page faults on the worker side  (155-170 ms measured)

 SharedMemory + name
   parent:  CreateFileMapping / shm_open+ftruncate -> MapViewOfFile / mmap -> np.frombuffer(shm.buf)
   pipe:    "psm_3f2a..." (a few bytes)
   worker:  OpenFileMapping / shm_open -> mmap -> np.frombuffer(shm.buf)   SAME physical pages
            per call: attach + submit round trip + first-touch page faults (4.7 ms measured: 4,096 pages sampled)

 InterpreterPoolExecutor.submit(fn, x)
   same process, different PyInterpreterState: own GIL, own sys.modules, own heap of objects
   fn and args are pickled into the target interpreter (objects are never shared across interpreters)
```

### 1.2 Start methods (⚠ Linux/macOS behaviour from `Lib/multiprocessing/context.py` and What's New, not executed here)

| Platform default (3.14) | Mechanism | Start-up | Gotchas |
|---|---|---|---|
| Windows: `spawn` | new interpreter, re-imports `__main__` as `__mp_main__` | slowest (223–266 ms for 4 workers measured) | requires `if __name__ == "__main__":`; every global is re-created per worker |
| macOS: `spawn` (since 3.8) | same | slow | same |
| **Linux and other POSIX: `forkserver` (changed from `fork` in 3.14)** | a clean server process forks workers on request | medium | functions and args must be picklable *and* importable; no inherited globals |
| `fork` (explicit opt-in) | `fork()` the parent | fastest, CoW pages | unsafe with threads (3.12+ `os.fork` can raise `DeprecationWarning` "This process is multi-threaded…"); refcount writes break CoW sharing (01.1 F10) |

The 3.14 default change on Linux is a silent behaviour break for code that relied on `fork` inheriting module globals, lambdas or open resources. That code now fails to pickle, or re-initializes state per worker.

### 1.3 The asyncio event loop, one iteration

`Lib/asyncio/base_events.py` `_run_once`, in essence:

```text
 while True:                                         # one "tick"
   timeout = 0 if ready else (earliest timer deadline - now)
   events  = selector.select(timeout)                # Linux: epoll; macOS: kqueue; Windows: IOCP (Proactor)
   for each event: ready.append(callback)            # I/O completions become callbacks
   move expired timers from the heap into ready
   for _ in range(len(ready)):                       # run ONLY the callbacks ready at tick start
       handle = ready.popleft(); handle._run()       # Task.__step -> coro.send(None) until next await
```

```text
 Task (C accelerated, Modules/_asynciomodule.c)
 +--------------------+      coro.send(None)      +----------------------------------+
 | Task               | ------------------------> | coroutine object                 |
 |  _coro  ---------------------------------------> |  frame (heap, like a generator) |
 |  _fut_waiter ---+  |  <-- yields a Future ----- |  suspended at `await fut`       |
 |  _state PENDING |  |                            +----------------------------------+
 +-----------------|--+
                   v
            Future (callbacks: [task.__wakeup])  <-- set_result() from I/O completion schedules the task
```

Consequences:

* **One callback runs at a time and nothing preempts it.** A 50 ms CPU burst inside a handler is a 50 ms stall for *every* connection on that loop (§2.3 measures p99 = 76 ms).
* **The loop references tasks weakly.** A pending task that nobody holds, waiting on a future nobody else holds, is an unreachable cycle, and the GC destroys it mid-flight (§2.4 C). Hence the docs' "save a reference to the result of `create_task`".
* `asyncio.to_thread` hands work to the loop's default `ThreadPoolExecutor`, sized `min(32, os.process_cpu_count() + 4)` (`Lib/concurrent/futures/thread.py`). The worker still needs the GIL to run bytecode, *and so does the loop thread to process the next event*. That makes it the convoy effect from 01.2 inside your event loop.
* Windows uses the Proactor (IOCP). Linux uses `epoll` through `selectors`. **uvloop** (⚠ not executed: no Windows support) replaces the loop with libuv. It lowers per-callback overhead, but it can't make a CPU-bound handler cooperative and can't release the GIL for Python code.
* 3.12 added `eager_task_factory`: a coroutine started by `create_task` runs synchronously until its first real suspension, so cache hits never pay a loop round trip. 3.14 adds `python -m asyncio ps PID` / `pstree PID` for live task introspection, and deprecates the policy system (`set_event_loop_policy` etc.).

### 1.4 Shared memory lifecycle (the part that crashes)

```text
 SharedMemory(create=True, size=n)     parent owns the name; resource_tracker registers it (POSIX, track=True)
   .buf  -> memoryview over the mmap   <- exports must be released before .close()
 np.frombuffer(shm.buf, ...)           holds a buffer EXPORT on the memoryview -> close() raises BufferError
 np.ndarray(shape, buffer=shm.buf)     (NumPy 2.5.4) keeps a reference to the mmap only, NO export ->
                                       close() succeeds, unmaps the pages, and the array now points at
                                       unmapped memory -> access violation (measured: exit 0xC0000005)
 .close()                              unmap this process's view
 .unlink()                             POSIX: remove /dev/shm/<name> (else it outlives every process);
                                       Windows: no-op, the segment dies with its last handle
```

The `track=` parameter (present in 3.14's `shared_memory.py`) decides whether the POSIX resource tracker will unlink the segment when the *creating* process exits. Pass `track=False` when a long-lived service, not the creator, owns the segment's lifetime.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Trap: one executor for everything — the CPU-bound matrix

```python
"""cpu_bound_matrix.py - 8 pure-Python CPU tasks on 4 workers: threads vs processes vs subinterpreters (3.14).

ThreadPoolExecutor shares one GIL; ProcessPoolExecutor pays process start-up + pickling through a pipe;
InterpreterPoolExecutor (PEP 734, 3.14) runs each worker in its own subinterpreter with its own GIL (PEP 684)
inside ONE process - parallel bytecode, but arguments and results still cross by pickling.
"""
import os
import time
from concurrent.futures import InterpreterPoolExecutor, ProcessPoolExecutor, ThreadPoolExecutor

TASKS, WORKERS, LOOP = 8, 4, 1_500_000


def burn(n):
    s = 0
    for i in range(n):
        s += i * i
    return s


def burn_and_return_list(n):
    burn(n // 4)
    return list(range(1_000_000))          # 1M ints back to the caller: the result must be pickled


def trivial(_):
    return os.getpid()


def bench(make):
    t0 = time.perf_counter()
    with make() as ex:
        list(ex.map(trivial, range(WORKERS)))          # force worker start-up
        t_start = time.perf_counter() - t0
        t1 = time.perf_counter()
        r = list(ex.map(burn, [LOOP] * TASKS))
        t_cpu = time.perf_counter() - t1
        t2 = time.perf_counter()
        r2 = list(ex.map(burn_and_return_list, [LOOP] * TASKS))
        t_ret = time.perf_counter() - t2
    assert r == [burn(LOOP)] * TASKS and all(len(x) == 1_000_000 for x in r2)
    return t_start, t_cpu, t_ret


if __name__ == "__main__":                              # required: spawn re-imports this module in each worker
    t0 = time.perf_counter()
    for _ in range(TASKS):
        burn(LOOP)
    seq = time.perf_counter() - t0
    print(f"{TASKS} tasks x burn({LOOP:,}); sequential = {seq * 1e3:.0f} ms; {WORKERS} workers; cpu_count={os.cpu_count()}")
    print(f"{'executor':28} {'start-up':>9} {'8 CPU tasks':>12} {'speedup':>8} {'8 tasks + 1M-int result':>24}")
    rows = {}
    for label, make in [("ThreadPoolExecutor", lambda: ThreadPoolExecutor(WORKERS)),
                        ("ProcessPoolExecutor (spawn)", lambda: ProcessPoolExecutor(WORKERS)),
                        ("InterpreterPoolExecutor", lambda: InterpreterPoolExecutor(WORKERS))]:
        st, cpu, ret = bench(make)
        rows[label] = seq / cpu
        print(f"{label:28} {st * 1e3:7.0f}ms {cpu * 1e3:10.0f}ms {seq / cpu:7.2f}x {ret * 1e3:22.0f}ms")
    assert rows["ThreadPoolExecutor"] < 1.3
    assert rows["ProcessPoolExecutor (spawn)"] > 2.0 and rows["InterpreterPoolExecutor"] > 2.0
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run; process and interpreter pools land between 2.4× and 3.1× across runs):

```text
8 tasks x burn(1,500,000); sequential = 613 ms; 4 workers; cpu_count=12
executor                      start-up  8 CPU tasks  speedup  8 tasks + 1M-int result
ThreadPoolExecutor                 2ms        603ms    1.02x                    249ms
ProcessPoolExecutor (spawn)      239ms        207ms    2.97x                    343ms
InterpreterPoolExecutor          144ms        197ms    3.11x                    544ms
ALL ASSERTIONS PASSED
```

* Threads: 1.0×, exactly as 01.2 predicts for bytecode.
* Processes and subinterpreters both reach **2.4–3.1× on 4 workers**. Subinterpreters start faster (no new process, no DLL loading) but still pickle arguments and results.
* The last column inverts the ranking. When each task *returns 1 M ints*, threads win (≈ 250 ms: no serialization), processes pay ~100 ms of pickling, and subinterpreters pay the most (≈ 545–550 ms here). **Parallelism is only a win when compute ≫ serialization.** For data-heavy steps, either move the data by shared memory (§2.2) or keep it in a columnar engine that parallelizes internally (Folder 03).

### 2.2 Trap: shipping arrays through pickle — and the view-lifetime crash

```python
"""ipc_cost_matrix.py - hand a 128 MiB float64 array to a worker process: pickle-through-a-pipe vs shared memory.

ProcessPoolExecutor pickles the argument (one full copy into the pipe, one out of it); SharedMemory maps the same
physical pages into both processes, so only the segment NAME crosses the pipe and the worker reads in place.
Part B: the view-lifetime trap. np.frombuffer() holds a buffer export, so close() refuses; np.ndarray(buffer=)
(NumPy 2.5.4) keeps only a reference to the mmap, so close() unmaps under a live array -> crash (child process).
"""
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from multiprocessing import shared_memory

import numpy as np

MB = 1 << 20
SHAPE = (16 * MB,)                                     # 16M float64 = 128 MiB


def checksum_copy(arr):
    return float(arr[::4096].sum()), arr.nbytes        # arr arrived by pickle: a private copy


def checksum_shm(name, shape, dtype):
    shm = shared_memory.SharedMemory(name=name)        # attach: maps the existing segment, no copy
    try:
        arr = np.frombuffer(shm.buf, dtype=dtype).reshape(shape)   # holds a buffer export on shm.buf
        out = float(arr[::4096].sum()), arr.nbytes
        del arr                                        # drop the export before close()
    finally:
        shm.close()
    return out


def best_of(fn, reps=5):
    best, r = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter()
        r = fn()
        best = min(best, time.perf_counter() - t0)
    return best, r


DANGLING = """
from multiprocessing import shared_memory
import numpy as np
shm = shared_memory.SharedMemory(create=True, size=1 << 20)
v = np.ndarray((1 << 17,), dtype=np.float64, buffer=shm.buf)   # base is the mmap, no export held
v[:] = 1.5
shm.close()                                                    # succeeds: nothing stops the unmap
print("closed; reading the view...", flush=True)
print(v[:3])                                                   # use-after-unmap
"""

if __name__ == "__main__":
    data = np.random.default_rng(0).random(SHAPE)
    expect = float(data[::4096].sum())
    with ProcessPoolExecutor(1) as ex:
        ex.submit(sum, [1]).result()                   # start the worker outside the timings
        t_pickle, (s1, n1) = best_of(lambda: ex.submit(checksum_copy, data).result())
        shm = shared_memory.SharedMemory(create=True, size=data.nbytes)
        try:
            view = np.frombuffer(shm.buf, dtype=data.dtype).reshape(data.shape)
            t0 = time.perf_counter()
            view[:] = data                             # one-time copy in (or produce the data here directly)
            t_fill = time.perf_counter() - t0
            t_shm, (s2, n2) = best_of(lambda: ex.submit(checksum_shm, shm.name, data.shape, data.dtype.str).result())
            try:
                shm.close()
                raise SystemExit("expected BufferError while a frombuffer() view is alive")
            except BufferError as e:
                refused = str(e)
            del view
        finally:
            shm.close()
            shm.unlink()                               # POSIX: removes the /dev/shm entry; Windows: no-op
    assert s1 == s2 == expect and n1 == n2 == data.nbytes
    print(f"== A. payload {data.nbytes / MB:.0f} MiB float64; worker reads a strided sample, returns a checksum")
    print(f"  {'pickle through the pipe (per call)':38} {t_pickle * 1e3:9.1f} ms")
    print(f"  {'shared_memory, name only (per call)':38} {t_shm * 1e3:9.1f} ms   ({t_pickle / t_shm:.0f}x faster)")
    print(f"  {'shared_memory one-time fill':38} {t_fill * 1e3:9.1f} ms   (paid once, amortised)")
    assert t_pickle > 10 * t_shm
    print("== B. view lifetime vs SharedMemory.close()")
    print(f"  np.frombuffer(shm.buf) alive -> close() raises BufferError: {refused}")
    r = subprocess.run([sys.executable, "-c", DANGLING], capture_output=True, text=True)
    code = r.returncode if r.returncode >= 0 else f"signal {-r.returncode}"
    print(f"  np.ndarray(buffer=shm.buf) alive -> child printed {r.stdout.strip()!r}, then exit code {code}"
          f" ({hex(r.returncode & 0xFFFFFFFF)})")
    assert r.returncode != 0, "the dangling view should crash the child"
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. payload 128 MiB float64; worker reads a strided sample, returns a checksum
  pickle through the pipe (per call)         171.3 ms
  shared_memory, name only (per call)          4.6 ms   (37x faster)
  shared_memory one-time fill                 38.5 ms   (paid once, amortised)
== B. view lifetime vs SharedMemory.close()
  np.frombuffer(shm.buf) alive -> close() raises BufferError: cannot close exported pointers exist
  np.ndarray(buffer=shm.buf) alive -> child printed 'closed; reading the view...', then exit code 3221225477 (0xc0000005)
ALL ASSERTIONS PASSED
```

* 128 MiB by pickle is **≈ 155–170 ms per call**. By shared memory it's **≈ 4.6–4.7 ms**, mostly first-touch page faults (the worker samples one value per 32 KiB, so 4,096 fresh pages per attach), and that falls further if workers attach once and keep the mapping. That's **33–37× faster**, and *zero* additional resident memory per worker, versus a full private copy.
* **Section B is a real crash, reproduced in a child process.** With NumPy 2.5.4, `np.ndarray(shape, buffer=shm.buf)` keeps only a reference to the `mmap`, not a buffer export, so `shm.close()` succeeds and the next read dereferences unmapped memory (exit `0xC0000005`). `np.frombuffer(shm.buf)` *does* hold an export, so `close()` refuses with `BufferError: cannot close exported pointers exist`. **Pattern:** create views with `np.frombuffer(...).reshape(...)`, scope them (`del view` before `close()`), and wrap the segment in a context manager that owns both.

### 2.3 Trap: "it's async, so it's fast" — GIL starvation of an asyncio server

A cheap endpoint's latency, measured from a *separate process* while the server runs a 50 ms CPU job every 100 ms:

```python
"""asyncio_loop_lag.py - GIL starvation of an asyncio server: ping latency while a 50 ms CPU job runs every 100 ms.

A client in a SEPARATE process (its own GIL) pings a TCP echo server every 5 ms. The server also runs a CPU job:
inline on the loop, in asyncio.to_thread (still needs the loop's GIL), in a ProcessPoolExecutor, or a
GIL-releasing job (hashlib) in a thread. Latency of the cheap endpoint is the metric that pages you.
"""
import asyncio
import hashlib
import multiprocessing as mp
import socket
import statistics
import time
from concurrent.futures import ProcessPoolExecutor

PINGS, GAP = 200, 0.005
BLOB = bytes(64 << 20)                                 # 64 MiB: sha256 of it takes ~150 ms with the GIL released


def burn():                                            # ~50 ms of pure-Python bytecode
    s = 0
    for i in range(1_100_000):
        s += i * i
    return s


def sha():
    return hashlib.sha256(BLOB).digest()


def client(port, out):
    s = socket.create_connection(("127.0.0.1", port))
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    lat = []
    for _ in range(PINGS):
        t0 = time.perf_counter()
        s.sendall(b"x")
        s.recv(1)
        lat.append(time.perf_counter() - t0)
        time.sleep(GAP)
    s.close()
    out.put(lat)


async def handle(reader, writer):
    writer.transport.get_extra_info("socket").setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    while data := await reader.read(1):
        writer.write(data)
        await writer.drain()
    writer.close()


async def scenario(mode, pool):
    server = await asyncio.start_server(handle, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    q = mp.Queue()
    p = mp.Process(target=client, args=(port, q))
    p.start()
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()

    async def cpu_job():
        while not stop.is_set():
            if mode == "inline on the loop":
                burn()
            elif mode == "asyncio.to_thread(burn)":
                await asyncio.to_thread(burn)
            elif mode == "ProcessPoolExecutor":
                await loop.run_in_executor(pool, burn)
            elif mode == "to_thread(hashlib) - GIL released":
                await asyncio.to_thread(sha)
            await asyncio.sleep(0.05)

    job = asyncio.create_task(cpu_job()) if mode != "no CPU job" else None
    lat = await loop.run_in_executor(None, q.get)      # wait for the client without blocking the loop
    stop.set()
    if job:
        await job
    p.join()
    server.close()
    await server.wait_closed()
    lat.sort()
    return statistics.median(lat), lat[int(0.99 * len(lat)) - 1], lat[-1]


async def main():
    with ProcessPoolExecutor(1) as pool:
        await asyncio.get_running_loop().run_in_executor(pool, burn)   # warm the worker
        print(f"{PINGS} pings, one every {GAP * 1e3:.0f} ms, from a separate process")
        print(f"{'server-side CPU job':36} {'median':>9} {'p99':>9} {'max':>9}")
        res = {}
        for mode in ("no CPU job", "inline on the loop", "asyncio.to_thread(burn)", "ProcessPoolExecutor",
                     "to_thread(hashlib) - GIL released"):
            med, p99, mx = await scenario(mode, pool)
            res[mode] = p99
            print(f"{mode:36} {med * 1e3:7.2f}ms {p99 * 1e3:7.2f}ms {mx * 1e3:7.2f}ms")
    assert res["inline on the loop"] > 25e-3
    assert res["ProcessPoolExecutor"] < res["inline on the loop"] / 3
    print("ALL ASSERTIONS PASSED")


if __name__ == "__main__":
    asyncio.run(main())
```

Output (one measured run):

```text
200 pings, one every 5 ms, from a separate process
server-side CPU job                     median       p99       max
no CPU job                              0.89ms    1.06ms    1.19ms
inline on the loop                      0.59ms   71.74ms   92.27ms
asyncio.to_thread(burn)                 0.68ms   47.79ms   64.35ms
ProcessPoolExecutor                     0.35ms    1.03ms    1.12ms
to_thread(hashlib) - GIL released       0.44ms    0.99ms    1.07ms
ALL ASSERTIONS PASSED
```

| Strategy for the CPU job | Ping p99 | Why |
|---|---:|---|
| inline on the loop | **≈ 72–76 ms** | the loop can't run any other callback for 50 ms; a ping arriving at the start waits it out |
| `asyncio.to_thread(burn)` | **≈ 48–59 ms** | the loop is free, but the *thread* holds the GIL and the loop thread needs it to process each event; on Windows each handoff is a ~16 ms timer tick (01.2 §1.2) |
| `ProcessPoolExecutor` | 1.0 ms | separate process, separate GIL |
| `to_thread(hashlib)` (GIL released in C) | 1.0–1.1 ms | the thread doesn't hold the GIL while hashing |

`to_thread` is the most common asyncio "fix" in code review and it buys almost nothing for pure-Python CPU work. **Pattern:** route CPU work by *what it executes*. GIL-releasing C goes to a thread, Python bytecode to a process or subinterpreter pool (or a separate service), and the event loop keeps only I/O and microsecond-scale glue. Monitor loop lag as an SLI.

### 2.4 Trap: trusting asyncio defaults — cost of a task, eager tasks, and three silent failures

```python
"""asyncio_footguns.py - what a coroutine costs, and five ways asyncio code fails silently in production.

A: bytes per pending Task vs per OS thread.  B: eager_task_factory for coroutines that finish without awaiting.
C: a fire-and-forget task collected mid-flight.  D: debug mode naming the callback that blocked the loop.
E: a swallowed CancelledError turns a 50 ms deadline into a late, *successful* return.
"""
import asyncio
import gc
import io
import logging
import re
import threading
import time
import tracemalloc

import psutil

print("== A. memory per pending unit of concurrency")


async def parked(ev):
    await ev.wait()


async def tasks_cost(n):
    ev = asyncio.Event()
    tracemalloc.start()
    ts = [asyncio.create_task(parked(ev)) for _ in range(n)]
    await asyncio.sleep(0)                             # let every task start and park on the Event
    cur, _ = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    ev.set()
    await asyncio.gather(*ts)
    return cur / n


per_task = asyncio.run(tasks_cost(50_000))
proc = psutil.Process()
gate = threading.Event()
before = proc.memory_info().private
threads = [threading.Thread(target=gate.wait) for _ in range(500)]
for t in threads:
    t.start()
per_thread = (proc.memory_info().private - before) / 500
gate.set()
for t in threads:
    t.join()
print(f"  pending asyncio Task (coroutine frame + Task + Event waiter): {per_task:8.0f} B")
print(f"  parked OS thread (committed stack + TLS + PyThreadState)     : {per_thread:8.0f} B  "
      f"({per_thread / per_task:.0f}x)")

print("== B. 200k tasks whose coroutine returns without suspending (e.g. a cache hit)")
CACHE = {k: k * 2 for k in range(1000)}


async def lookup(k):
    return CACHE[k % 1000]                             # never awaits


async def fan_out(eager):
    loop = asyncio.get_running_loop()
    loop.set_task_factory(asyncio.eager_task_factory if eager else None)
    t0 = time.perf_counter()
    r = await asyncio.gather(*(asyncio.create_task(lookup(k)) for k in range(200_000)))
    return time.perf_counter() - t0, sum(r)


t_lazy, s1 = asyncio.run(fan_out(False))
t_eager, s2 = asyncio.run(fan_out(True))
assert s1 == s2
print(f"  default factory: {t_lazy * 1e3:6.0f} ms   eager_task_factory: {t_eager * 1e3:6.0f} ms   "
      f"({t_lazy / t_eager:.1f}x: the coroutine runs inside create_task, no loop round trip)")

print("== C. fire-and-forget: nothing but the event loop's weak bookkeeping holds the task")
log = io.StringIO()
handler = logging.StreamHandler(log)
logging.getLogger("asyncio").addHandler(handler)
finished = []


async def waits_on_private_future():
    fut = asyncio.get_running_loop().create_future()  # only this coroutine (and its Task) reference fut
    await fut
    finished.append(True)                              # never reached


async def fire_and_forget():
    asyncio.create_task(waits_on_private_future())     # result discarded: no strong reference kept
    await asyncio.sleep(0)                             # task starts, parks on fut: task <-> fut is a cycle
    gc.collect()                                       # the cycle is unreachable: the Task is destroyed
    await asyncio.sleep(0)


asyncio.run(fire_and_forget())
msg = next((ln for ln in log.getvalue().splitlines() if "destroyed" in ln), "<no message>")
print(f"  finished={finished}; asyncio logged: {msg[:60]!r}")
assert "Task was destroyed but it is pending" in log.getvalue() and not finished

print("== D. debug mode names the coroutine that blocked the loop")
log.truncate(0)
log.seek(0)


async def handler_that_blocks():
    time.sleep(0.15)                                   # a sync call hiding in async code


async def debug_main():
    asyncio.get_running_loop().slow_callback_duration = 0.1
    await asyncio.create_task(handler_that_blocks())


asyncio.run(debug_main(), debug=True)
m = re.search(r"coro=<(\w+)\(\).*? took ([\d.]+) seconds", log.getvalue())
print(f"  asyncio warning: Executing <Task coro={m.group(1)}()> took {m.group(2)} seconds")
assert "handler_that_blocks" in log.getvalue() and "took" in log.getvalue()
logging.getLogger("asyncio").removeHandler(handler)

print("== E. a swallowed CancelledError defeats the deadline")


async def swallows_cancel():
    try:
        await asyncio.sleep(0.5)
    except BaseException:                              # also what a bare `except:` does
        await asyncio.sleep(0.3)                       # "cleanup" that keeps going
        return "late result"


async def honours_cancel():
    try:
        await asyncio.sleep(0.5)
    finally:
        pass                                           # cleanup, then CancelledError propagates


async def deadline(coro):
    t0 = time.perf_counter()
    try:
        r = await asyncio.wait_for(coro, timeout=0.05)
    except TimeoutError:
        r = "TimeoutError"
    return r, time.perf_counter() - t0


for fn in (honours_cancel, swallows_cancel):
    r, dt = asyncio.run(deadline(fn()))
    print(f"  wait_for({fn.__name__}(), timeout=0.05) -> {r!r} after {dt * 1e3:4.0f} ms")
    assert (r == "TimeoutError") == (fn is honours_cancel)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. memory per pending unit of concurrency
  pending asyncio Task (coroutine frame + Task + Event waiter):     1049 B
  parked OS thread (committed stack + TLS + PyThreadState)     :    58425 B  (56x)
== B. 200k tasks whose coroutine returns without suspending (e.g. a cache hit)
  default factory:   1097 ms   eager_task_factory:    480 ms   (2.3x: the coroutine runs inside create_task, no loop round trip)
== C. fire-and-forget: nothing but the event loop's weak bookkeeping holds the task
  finished=[]; asyncio logged: 'Task was destroyed but it is pending!'
== D. debug mode names the coroutine that blocked the loop
  asyncio warning: Executing <Task coro=handler_that_blocks()> took 0.151 seconds
== E. a swallowed CancelledError defeats the deadline
  wait_for(honours_cancel(), timeout=0.05) -> 'TimeoutError' after   64 ms
  wait_for(swallows_cancel(), timeout=0.05) -> 'late result' after  365 ms
ALL ASSERTIONS PASSED
```

* **A pending task ≈ 1 KB; a parked OS thread ≈ 58 KB committed (56×).** This is why 100 k concurrent connections are routine with asyncio and unthinkable with thread-per-connection. 🧊 JDK 21 virtual threads close the same gap on the JVM, but without the colouring of every function as `async`.
* `eager_task_factory` halves the cost of fan-out when most coroutines finish without suspending (2.2–2.3× measured): cache hits, memoized lookups, already-resolved futures.
* **C:** the task vanished with `Task was destroyed but it is pending!`. In production this is a webhook never sent or a write never flushed, with only a log line as evidence. **Pattern:** own every task (`asyncio.TaskGroup`, or a module-level `set()` with `task.add_done_callback(tasks.discard)`).
* **D:** `debug=True` with `slow_callback_duration` names the offending coroutine. Run staging with `PYTHONASYNCIODEBUG=1`.
* **E:** a coroutine that catches `BaseException` (or uses bare `except:`) swallows `CancelledError`, so `wait_for(timeout=0.05)` returned **"late result" after 365 ms**: a deadline miss reported as success. Since 3.8 `CancelledError` is a `BaseException`, precisely so that `except Exception` *doesn't* catch it. Never catch it without re-raising.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Process pool slower than serial | Profile dominated by `pickle.dumps`/`loads`, pipe writes | Data crossing the boundary on every task | Shared memory / memory-mapped Arrow or Parquet; send names, not data; larger tasks | Estimate bytes-per-task × tasks before choosing a pool |
| F2 🔥 | Worker segfaults or returns garbage after "cleanup" | Access violation / SIGSEGV in NumPy code after `shm.close()` | `np.ndarray(buffer=shm.buf)` holds no export; the mapping was closed under it | `np.frombuffer` + scoped views; close after the last view dies | Wrap segments in a context manager; never return views past the segment's lifetime |
| F3 | `/dev/shm` fills up on Linux nodes; "leaked shared_memory objects" warnings (⚠ POSIX) | `ls /dev/shm` shows stale `psm_*` | Missing `unlink()`, or the resource tracker unlinking a segment another process still needs | Exactly one owner calls `unlink()`; `track=False` for service-owned segments | Name segments deterministically; a reaper on startup |
| F4 🔥 | Upgrading to 3.14 breaks multiprocessing on Linux | `PicklingError`, or globals unexpectedly re-initialized per worker | Default start method changed `fork` → `forkserver` | Make tasks picklable and importable; pass state explicitly; or opt into `fork` knowingly | Set the start method explicitly in code; test with `spawn` in CI |
| F5 | Child hangs forever right after `fork()` | Deadlock in the child on a lock held by a parent thread (logging, malloc, an SDK client) | `fork()` copies one thread and every lock in whatever state it was in | `forkserver`/`spawn`; fork before starting threads | Heed the 3.12+ `DeprecationWarning` about forking a multi-threaded process |
| F6 🔥 | asyncio p99 spikes during background work | Loop-lag SLI spikes; py-spy shows a CPU-bound frame on the loop thread or another bytecode thread | CPU work inline or in `to_thread` | Process / interpreter pool; split the service | Loop-lag alert; debug mode in staging |
| F7 🔥 | Background work silently never completes | `Task was destroyed but it is pending!` in logs | Unreferenced task collected as a cycle | `TaskGroup` / strong-reference set | Lint: result of `create_task` must be stored |
| F8 | Timeouts don't fire; requests exceed deadlines but "succeed" | `wait_for` returns late values | `CancelledError` swallowed by `except BaseException:` / bare `except:` | Re-raise cancellation; use `try/finally` for cleanup | Ruff rule BLE001 (blind except) + E722 (bare except) |
| F9 | Thread-per-connection service OOMs at a few thousand clients | RSS ≈ 58 KB × threads + stacks reserved | Each OS thread commits a stack and a thread state | asyncio (≈ 1 KB/task) or a bounded pool | Cap concurrency with `asyncio.Semaphore` / bounded queues |
| F10 | `to_thread` calls queue up; latency climbs under load | Default executor saturated at `min(32, cpu+4)` workers | Blocking calls exceed the default pool | A dedicated `ThreadPoolExecutor` per dependency, sized and bounded | Per-dependency bulkheads, like Java's per-client pools |

**Debugging toolkit.** `python -m asyncio ps PID` / `pstree PID` (3.14) show live task trees. `PYTHONASYNCIODEBUG=1` plus `loop.slow_callback_duration` flag blocking callbacks. `py-spy dump --pid` shows which thread holds the GIL. `faulthandler.enable()` and `faulthandler.dump_traceback_later()` catch hangs and segfaults in workers. On Linux, `ls -l /dev/shm` and `lsof | grep psm_` show segment leaks.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Pick a concurrency model for a feature-engineering service: 2 k RPS, each request does 5 ms of pure-Python transforms on a 2 MB payload."</b></summary>

**Initial Prompt.** Design the execution model for a Python feature service on 16-core machines.

**L5 Answer.** "FastAPI with async handlers. It's I/O, so asyncio will scale."

**Why L5 Crashes at Scale.** 2 k RPS × 5 ms of bytecode is 10 core-seconds per second. One event loop can deliver ~1 core, so the loop saturates at ~200 RPS and every request's latency includes everyone else's CPU time (§2.3: ≈ 72–76 ms p99 from a 50 ms job). `to_thread` doesn't help for bytecode (≈ 48–59 ms p99 measured).

**L7 Principal Defense.** Separate the planes. Run N worker *processes* per host (≈ cores) behind the HTTP front, each with a small asyncio loop for I/O and ≤ 1 ms of glue per request. Better still, vectorize the transform (NumPy/Polars over the 2 MB batch, 10–50× less CPU and GIL-free). Size by core-seconds: 10 core-s/s needs ≥ 10 cores at 100 %, so plan ~16 with headroom. If shared reference data is large, map it read-only via shared memory or mmapped Arrow instead of loading it per process. Monitor loop lag and per-process CPU, not just request latency.

</details>

<details><summary><b>Q2 · "Why is our ProcessPoolExecutor slower than the single-process version?"</b></summary>

**Initial Prompt.** A batch job parallelized `df_chunk -> score(chunk)` with 8 processes and got 0.7× the throughput.

**L5 Answer.** "Process start-up overhead. Reuse the pool."

**Why L5 Crashes at Scale.** Start-up is a one-time 200–300 ms. The per-task cost is serialization: each chunk is pickled, copied through a pipe, unpickled into a new object graph, and the results come back the same way. For a DataFrame of Python objects that's often more CPU than `score()` itself (≈ 155–170 ms to move 128 MiB of float64, and object columns are far worse).

**L7 Principal Defense.** Measure bytes per task against compute per task. If serialization ≥ 10 % of compute, change the data plane. Put inputs in shared memory or memory-mapped Arrow/Parquet and pass `(name, offset, length)`. Workers return small results or write into a preallocated shared output buffer. With columnar formats this is zero-copy at both ends (Folder 02 covers the Arrow C Data Interface). If the scoring is vectorizable, one process with a multithreaded engine (Polars, DuckDB, NumPy/BLAS) usually beats eight pickling processes outright.

</details>

<details><summary><b>Q3 · "What exactly does `asyncio.to_thread` buy you, and when is it harmful?"</b></summary>

**Initial Prompt.** A team wraps every slow function in `await asyncio.to_thread(...)`.

**L5 Answer.** "It runs the function in a thread so the event loop isn't blocked."

**Why L5 Crashes at Scale.** True only if the function releases the GIL. For pure-Python work the loop still competes for the GIL, and latency becomes the switch interval (≈ 48–59 ms p99 measured against ≈ 72–76 ms inline). The default executor (`min(32, cpu+4)` workers) also becomes an unbounded queue that hides overload until timeouts cascade.

**L7 Principal Defense.** Classify each call. Blocking I/O or GIL-releasing C (file reads, `hashlib`, NumPy, a C driver) is fine in a thread (≈ 1 ms p99 measured with hashlib). Python bytecode goes to a process or subinterpreter pool. Unknown means measure it with the ctypes CDLL/PyDLL control (01.2 Q9). Give each dependency its own bounded executor (a bulkhead), add timeouts, and shed load when its queue is full. Watch `to_thread` hot spots in loop-lag traces.

</details>

<details><summary><b>Q4 · "How do two processes share a 20 GB feature table without 2× the RAM?"</b></summary>

**Initial Prompt.** Eight inference workers each load the same 20 GB embedding table. The host has 64 GB.

**L5 Answer.** "Use `fork` so the children share the parent's pages copy-on-write."

**Why L5 Crashes at Scale.** If the table is Python objects, refcount and GC-header writes on *read* dirty the pages, and CoW copies them back into each child (01.1 F10). If it's a NumPy array, `fork` works until a library thread exists (deadlock risk) or the platform default is `forkserver` (3.14 Linux) or `spawn` (macOS, Windows). And the arrangement dies on the first worker restart.

**L7 Principal Defense.** Make sharing explicit and restart-safe. Store the table as a flat binary file (NumPy `.npy`, Arrow IPC, or Parquet decoded once into Arrow) and `mmap` it read-only in every worker; the OS page cache holds one copy. Or create a named `SharedMemory` segment owned by a supervisor (`track=False`, a single owner unlinks) and attach from workers with `np.frombuffer` views. Keep no Python objects per row. Ray's object store (Folder 04) is this same design with a scheduler on top.

</details>

<details><summary><b>Q5 · "A fire-and-forget audit-log task occasionally never runs. Explain."</b></summary>

**Initial Prompt.** Handlers do `asyncio.create_task(send_audit(evt))` and return. Roughly 0.1 % of audit events are missing.

**L5 Answer.** "The process is shutting down before the task runs. Add a graceful shutdown."

**Why L5 Crashes at Scale.** Shutdown is one cause, but the vanishing happens in steady state too. The event loop keeps only weak references to tasks. A task suspended on a future that only it references forms an unreachable cycle, and the cycle collector destroys it (measured: "Task was destroyed but it is pending!", body never finished).

**L7 Principal Defense.** Own every task: a `TaskGroup` scoped to the request or a supervisor, or a strong-reference set with `add_done_callback(set.discard)`. For audit-grade delivery, don't use in-process fire-and-forget at all. Write to a durable queue (Kafka, an outbox table) inside the request's transaction and let a consumer deliver. Add a log-based alert on "Task was destroyed but it is pending" and a lint for unassigned `create_task` results.

</details>

<details><summary><b>Q6 · "Threads vs. asyncio for 50 k concurrent websocket clients?"</b></summary>

**Initial Prompt.** Each client sends a message every few seconds; handling is ~200 µs.

**L5 Answer.** "Threads are simpler; Python threads are fine for I/O."

**Why L5 Crashes at Scale.** 50 k threads × ~58 KB committed (measured) is ~3 GB before any application state, plus scheduler overhead and stack reservations that can exhaust address space or ulimits. GIL convoying makes tail latency proportional to thread count when any handler does CPU work.

**L7 Principal Defense.** asyncio at ~1 KB per pending task is ~50 MB for 50 k waits, a 56× difference measured. Shard across processes (one loop per core, `SO_REUSEPORT` on Linux) to use all cores. Bound per-connection queues for backpressure, and keep handlers ≤ 1 ms. Consider uvloop on Linux for lower per-callback overhead (⚠ not measured here), and keep the honest caveat: it doesn't change the one-callback-at-a-time model.

</details>

<details><summary><b>Q7 · "Should we use subinterpreters (`InterpreterPoolExecutor`) instead of processes?"</b></summary>

**Initial Prompt.** 3.14 ships `concurrent.interpreters` and `InterpreterPoolExecutor`. When are they the right tool?

**L5 Answer.** "They're like threads without the GIL, so always prefer them."

**Why L5 Crashes at Scale.** They share no Python objects. Arguments and results are pickled exactly like processes (and measured *slower* for a 1 M-int result: ≈ 545 vs ≈ 340 ms). Many C extensions don't support multiple interpreters (single-phase init, global state) and fail to import. Unlike processes, a crash in one takes down all of them.

**L7 Principal Defense.** Use them for CPU-bound, compute-heavy, small-I/O Python tasks where process start-up or per-process memory hurts. Measured: ≈ 145 ms start-up against 223–266 ms for spawn, and 2.4–3.1× on 4 workers. Keep the data plane outside Python objects (shared memory or buffers). Verify every imported extension supports per-interpreter state. Keep processes when you need fault isolation, memory limits per worker, or extensions that only work in the main interpreter.

</details>

<details><summary><b>Q8 · "A `wait_for(..., timeout=1)` call sometimes takes 9 seconds and returns a value. How?"</b></summary>

**Initial Prompt.** Tracing shows requests exceeding a hard 1 s budget with *successful* responses.

**L5 Answer.** "The event loop was busy, so the timeout fired late."

**Why L5 Crashes at Scale.** A busy loop delays the timeout, but it would then raise `TimeoutError`, not return a value. A successful late return means the cancellation was swallowed. Blaming loop load sends the team after the wrong fix.

**L7 Principal Defense.** `wait_for`/`timeout()` deliver the deadline as a `CancelledError` *inside* the coroutine. If that coroutine (or a library it calls) catches `BaseException` or uses bare `except:` and keeps working, `timeout()`'s `__aexit__` sees normal completion and the deadline becomes a lie. Measured: a 50 ms deadline returned "late result" after 365 ms. Fix: always re-raise `CancelledError`, use `try/finally` for cleanup, and use `asyncio.timeout()` with structured `TaskGroup`s. Enforce with ruff BLE001/E722, and add an end-to-end deadline metric that compares elapsed time with the budget.

</details>

<details><summary><b>Q9 · "Your NumPy-on-shared-memory worker segfaults once a week. Where do you look?"</b></summary>

**Initial Prompt.** Workers attach to a `SharedMemory` segment, compute on an array view, and occasionally die with an access violation (Windows) or SIGSEGV (Linux).

**L5 Answer.** "A NumPy bug. Upgrade NumPy."

**Why L5 Crashes at Scale.** It's a lifetime bug in your code that NumPy doesn't guard. Upgrading changes nothing, and the weekly crash stays non-deterministic because it depends on which view survives past `close()`.

**L7 Principal Defense.** Look for views built with `np.ndarray(..., buffer=shm.buf)`. In NumPy 2.5.4 they reference the mmap without holding a buffer export, so `SharedMemory.close()` unmaps under them (reproduced: exit `0xC0000005`). `np.frombuffer(shm.buf)` holds an export, so a premature `close()` raises `BufferError` instead of corrupting memory. Fix it by construction: build views with `frombuffer`, scope them inside a context manager that closes the segment only after the views are gone, and never return a view across that scope. Enable `faulthandler` in workers so the next crash carries a Python traceback.

</details>

---

## 5. Invariants Checklist

- [ ] Choose concurrency by what executes. Bytecode goes to processes or subinterpreters, GIL-releasing C and blocking I/O to threads, many waits to asyncio.
- [ ] Crossing a process or interpreter boundary costs pickling. Parallelism pays only when compute ≫ bytes moved.
- [ ] Bulk data crosses boundaries by name: shared memory or mmapped Arrow/Parquet. Pages are shared, not copied.
- [ ] `np.frombuffer` (export-holding) views only; close segments after the last view; exactly one owner unlinks on POSIX.
- [ ] 3.14 Linux defaults to `forkserver`. Set the start method explicitly; never `fork` a multi-threaded process.
- [ ] The event loop runs one callback at a time. Keep handlers ≤ 1 ms of CPU and monitor loop lag.
- [ ] `to_thread` helps only for GIL-releasing work.
- [ ] Own every task (TaskGroup / strong refs). Never swallow `CancelledError`.
- [ ] A pending task is ~1 KB and a parked thread ~58 KB. Bound concurrency explicitly either way.

---

## 6. References

**CPython source and docs (pinned)**
- `Lib/concurrent/futures/interpreter.py`, `process.py`, `thread.py` (`min(32, process_cpu_count() + 4)`) — https://github.com/python/cpython/tree/v3.14.10/Lib/concurrent/futures
- `Lib/multiprocessing/shared_memory.py` (`close`, `unlink`, `track`) — https://github.com/python/cpython/blob/v3.14.10/Lib/multiprocessing/shared_memory.py
- `Lib/multiprocessing/context.py` (platform default start method) — https://github.com/python/cpython/blob/v3.14.10/Lib/multiprocessing/context.py
- `Lib/asyncio/base_events.py` (`_run_once`), `tasks.py` (`eager_task_factory`) — https://github.com/python/cpython/tree/v3.14.10/Lib/asyncio
- What's New 3.14: forkserver default, asyncio introspection, policy deprecation — https://docs.python.org/3.14/whatsnew/3.14.html
- What's New 3.12: `os.fork` with threads `DeprecationWarning` — https://docs.python.org/3.12/whatsnew/3.12.html
- `asyncio` developing guide (debug mode, "save a reference") — https://docs.python.org/3/library/asyncio-dev.html
- `asyncio.create_task` docs — https://docs.python.org/3/library/asyncio-task.html#asyncio.create_task

**PEPs**
- PEP 734 — Multiple Interpreters in the Stdlib: https://peps.python.org/pep-0734/
- PEP 684 — A Per-Interpreter GIL: https://peps.python.org/pep-0684/
- PEP 492 — Coroutines with async and await syntax: https://peps.python.org/pep-0492/
- PEP 3156 — Asynchronous IO Support Rebooted (asyncio): https://peps.python.org/pep-3156/

**Ecosystem and bridge**
- uvloop (libuv-based loop; Linux/macOS) — https://github.com/MagicStack/uvloop
- JEP 444 — Virtual Threads: https://openjdk.org/jeps/444
- NumPy `frombuffer` docs — https://numpy.org/doc/stable/reference/generated/numpy.frombuffer.html
