# 02.2 · Vectorization: SIMD ufuncs, the Buffer Protocol, `memoryview`, Numba & Cython

> **Folder 02 · Scientific Computing Physics: NumPy & Apache Arrow**
> **Measured on:** CPython 3.14.5, NumPy 2.5.4, Numba 0.68.1 (LLVM via llvmlite 0.50), Cython 3.x compiled by GCC 16.2 against `python314.dll`, numexpr 2.14.2, i5-11260H (AVX-512 capable), Windows 11.
> **Source verified against:** CPython `Include/cpython/object.h` (`Py_buffer`), PEP 3118; NumPy runtime `__cpu_baseline__` / `__cpu_dispatch__` / `__cpu_features__`.

---

## 0. Orientation & the JVM/C++ Bridge

"Vectorized" means one Python-level call that runs a compiled loop over a whole buffer, with the interpreter out of the inner loop. Three layers make that work: **ufuncs** (precompiled, SIMD-dispatched inner loops), the **buffer protocol** (any C-level producer and consumer can share memory without copying), and **compilers for the loops NumPy doesn't have** (Numba, Cython, plain C via ctypes). The fourth lever, **fusion**, avoids writing intermediates to memory at all. It's the CPU rehearsal for `torch.compile` in Folder 06.

| Concept | Python stack | JVM | C++ |
|---|---|---|---|
| Elementwise kernel | ufunc inner loop, SIMD chosen at import from CPU features | C2 auto-vectorization; `jdk.incubator.vector` (Vector API) | `std::transform` + `-O3`, intrinsics, Highway/xsimd |
| Runtime CPU dispatch | NumPy `__cpu_dispatch__` targets (X86_V3 here) | HotSpot intrinsics chosen at startup | function multiversioning, `ifunc` |
| Zero-copy memory sharing | buffer protocol (`Py_buffer`), `memoryview`, DLPack, Arrow C Data | `ByteBuffer`, Panama `MemorySegment` | `std::span`, `mdspan` |
| Custom compiled loop | Numba (LLVM JIT), Cython (AOT to C), ctypes/cffi to C | the JIT does it for you | it's just C++ |
| Fusion | numexpr, Numba, Polars/DuckDB engines, `torch.compile` | C2 escape analysis + loop fusion (limited) | expression templates (Eigen), Halide |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Anatomy of a ufunc call (`np.add(a, b, out=c)`)

```text
 Python call -> ufunc.__call__ (C)
   1. normalize args, out=, where=, casting=, dtype=
   2. promotion + loop resolution (NumPy 2 "ArrayMethod" machinery): (float64, float64) -> (float64)
   3. pick the strided inner loop for that signature
        -> per-CPU variant chosen ONCE at import from __cpu_dispatch__ (here: baseline X86_V2, dispatch X86_V3)
   4. build the iterator (nditer): broadcast shapes, coalesce contiguous axes, order axes by stride,
      allocate cast/alignment buffers only if needed
   5. NPY_BEGIN_THREADS (release the GIL) for non-object dtypes
   6. call inner_loop(char **args, npy_intp *n, npy_intp *steps, void *data) over 1-D chunks
        the SIMD body runs when steps == itemsize (contiguous) and pointers don't alias badly
   7. NPY_END_THREADS; wrap the result
 fixed overhead ~0.6 us per call (measured: 660 ns for an 8-element sqrt) -> vectorize LARGE arrays,
 never call ufuncs per element
```

Two facts measured here that matter for capacity planning:

* **This PyPI NumPy 2.5.4 Windows wheel dispatches only to X86_V3 (AVX2 + FMA)** even though the CPU reports AVX-512 (`X86_V4 = True`). The wheel's `__cpu_dispatch__` list is `['X86_V3']`. If you need AVX-512 kernels you need a build that compiles them (or a library that ships its own: OpenBLAS, MKL, Polars).
* float32 is ~2× float64 for compute-bound ufuncs (`sqrt` 1.0 vs 1.9 ns/elem, `exp` 1.7 vs 5.5 ns/elem): twice the lanes per vector, half the bytes.

### 1.2 Reductions: pairwise summation and accuracy

`np.sum` / `np.add.reduce` over contiguous float data uses **pairwise summation**: an 8-way unrolled block, recursively halved above 128 elements. The error grows as O(log n) instead of O(n). `np.add.accumulate` is strictly sequential. On 10 M float32 values of 0.1 the sequential result is off by **~88 000** (8.8 %) and pairwise by 0.11; `dtype=np.float64` is exact to display precision. The rule is to store in float32 and accumulate in float64.

### 1.3 The buffer protocol (PEP 3118)

```c
typedef struct {            /* Include/cpython/object.h */
    void *buf;              /* start of the memory (already offset for views) */
    PyObject *obj;          /* the exporter, kept alive while the view exists */
    Py_ssize_t len;         /* total bytes */
    Py_ssize_t itemsize;
    int readonly;
    int ndim;
    char *format;           /* struct-module syntax: 'd', 'f', 'q', '<qid', 'T{...}' */
    Py_ssize_t *shape;
    Py_ssize_t *strides;    /* bytes, like NumPy */
    Py_ssize_t *suboffsets; /* PIL-style indirect arrays (rare) */
    void *internal;
} Py_buffer;
```

```text
 exporter (bytearray, bytes, array.array, mmap, ndarray, Arrow Buffer)
   bf_getbuffer(obj, &view, flags)   -> fills Py_buffer, increments the exporter's export count
   ... consumer reads/writes view.buf ...
   bf_releasebuffer(obj, &view)      -> decrements the count
 while exports > 0: bytearray refuses to resize ("Existing exports of data: object cannot be re-sized"),
                    mmap refuses to close ("cannot close exported pointers exist")
```

`memoryview` is the Python-level handle on a `Py_buffer`: slicing creates sub-views with adjusted `buf`/`shape`/`strides`, and `cast()` reinterprets formats (C-contiguous only). Consumers that write *into* a buffer avoid allocation entirely: `file.readinto(buf)`, `socket.recv_into(buf)`, `np.frombuffer(buf)`, `hashlib.update(buf)`. 🧊 It's Java's `ByteBuffer` with a type descriptor, or C++'s `std::span` plus `mdspan` extents, plus a lifetime contract enforced by the export count.

### 1.4 Compiling the loops NumPy doesn't have

* **Numba**: decorates a Python function, infers types from the first call's arguments, lowers the bytecode to LLVM IR and JIT-compiles it (nopython mode: no `PyObject*` in the loop). `parallel=True` turns `prange` loops into a threaded kernel (TBB/OpenMP/workqueue layer). `nogil=True` releases the GIL. `cache=True` persists the machine code to `__pycache__`; without it you pay compilation (~330–350 ms measured) **per process**, which matters for serverless and multiprocessing workers.
* **Cython**: compiles a typed superset of Python to C ahead of time. Typed memoryviews (`double[::1]`) compile to raw pointer arithmetic, and `with nogil:` releases the GIL. On Windows, C `long` is 32-bit (LLP64), so an int64 buffer must be typed `long long` (format `'q'`). The listing's comment records this; getting it wrong raises a buffer-dtype mismatch at call time.
* **C via ctypes**: `np.ctypeslib.ndpointer` checks dtype and contiguity at the boundary. `CDLL` releases the GIL during the call (01.2).

### 1.5 Fusion: why one pass beats four

```text
 y = sin(a) + cos(b) * c        eager NumPy                         fused (numexpr / Numba / Inductor)
   t1 = sin(a)     R a  W t1     |  every intermediate is a full    for each block of ~4K elements
   t2 = cos(b)     R b  W t2     |  array written to and read       (L1/L2 resident):
   t3 = t2 * c     R t2,c W t3   |  back from DRAM, and each new      y = sin(a)+cos(b)*c
   y  = t1 + t3    R t1,t3 W y   |  array also pays first-touch      R a,b,c  W y
   traffic: 10 arrays x 128 MiB = 1280 MiB                         traffic: 4 arrays = 512 MiB
```

On a CPU, `sin`/`cos` cost more than the memory traffic, so fusion alone gives 1.1–1.4× and parallelism gives the rest (7.5–8.6×). For the memory-bound `a*b + c*d - a`, fusion alone gives **~4×**. GPUs sit at the opposite extreme: their arithmetic throughput dwarfs HBM bandwidth, so *every* unfused elementwise chain is memory-bound. That's the premise of TorchInductor's fused Triton kernels (06.3).

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 What a ufunc costs, what SIMD buys, and how reductions lose precision

```python
"""ufunc_simd_dispatch.py - what a NumPy ufunc call costs and where its speed comes from.

A: the CPU features this NumPy build detected and compiled dispatch targets for (runtime SIMD dispatch).
B: per-element cost: Python loop vs ufunc, float32 vs float64, contiguous vs strided, small-array overhead.
C: reduction accuracy: pairwise summation (np.sum) vs sequential accumulation vs exact (math.fsum).
"""
import math
import time

import numpy as np
from numpy._core._multiarray_umath import __cpu_baseline__, __cpu_dispatch__, __cpu_features__

print("== A. SIMD: compiled baseline, dispatch targets, and what this CPU has")
print(f"  baseline (always used): {' '.join(__cpu_baseline__)}")
have = [f for f in __cpu_dispatch__ if __cpu_features__.get(f)]
print(f"  dispatch targets present on this CPU: {' '.join(have)}")
print(f"  AVX512F={__cpu_features__['AVX512F']}  AVX512_SKX={__cpu_features__.get('AVX512_SKX')}  "
      f"AVX512_ICL={__cpu_features__.get('AVX512_ICL')}")


def best(fn, reps=5):
    t = []
    for _ in range(reps):
        t0 = time.perf_counter()
        fn()
        t.append(time.perf_counter() - t0)
    return min(t)


N = 4_000_000
rng = np.random.default_rng(0)
x64 = rng.random(2 * N) + 0.5
x32 = x64.astype(np.float32)
xs = x64[:N].tolist()                                  # Python floats
print(f"== B. ns per element over {N:,} elements")
t_py = best(lambda: [math.sqrt(v) for v in xs], reps=2)
cases = [("Python list comprehension, math.sqrt", None),
         ("np.sqrt float64 contiguous", lambda: np.sqrt(x64[:N])),
         ("np.sqrt float32 contiguous", lambda: np.sqrt(x32[:N])),
         ("np.sqrt float64 stride 2 (x[::2])", lambda: np.sqrt(x64[::2])),
         ("np.exp float64 contiguous", lambda: np.exp(x64[:N])),
         ("np.exp float32 contiguous", lambda: np.exp(x32[:N])),
         ("np.add float64 contiguous", lambda: np.add(x64[:N], x64[N:]))]
rows = [(label, t_py if fn is None else best(fn)) for label, fn in cases]
for label, dt in rows:
    print(f"  {label:40} {dt / N * 1e9:7.3f} ns/elem  ({t_py / dt:6.0f}x vs Python)")
small = x64[:8]
t_small = best(lambda: [np.sqrt(small) for _ in range(10_000)]) / 10_000
print(f"  np.sqrt on an 8-element array: {t_small * 1e9:.0f} ns per CALL - dispatch, not arithmetic, dominates")

print("== C. summing 10M float32 values of 0.1 (float32(0.1) = 0.10000000149, so the exact sum is 1,000,000.0149)")
v = np.full(10_000_000, 0.1, dtype=np.float32)
exact = math.fsum(v.astype(np.float64))
seq = np.add.accumulate(v)[-1]                         # strictly sequential float32 accumulation
pair = v.sum()                                         # pairwise summation in float32
f64 = v.sum(dtype=np.float64)
for label, r in [("np.add.accumulate (sequential f32)", seq), ("np.sum (pairwise f32)", pair),
                 ("np.sum(dtype=float64)", f64), ("math.fsum (exact for the f32 inputs)", exact)]:
    print(f"  {label:38} {float(r):16.4f}   error vs exact {abs(float(r) - exact):12.4f}")
assert abs(float(pair) - exact) < abs(float(seq) - exact) / 100
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. SIMD: compiled baseline, dispatch targets, and what this CPU has
  baseline (always used): X86_V2
  dispatch targets present on this CPU: X86_V3
  AVX512F=True  AVX512_SKX=True  AVX512_ICL=True
== B. ns per element over 4,000,000 elements
  Python list comprehension, math.sqrt      84.086 ns/elem  (     1x vs Python)
  np.sqrt float64 contiguous                 1.889 ns/elem  (    45x vs Python)
  np.sqrt float32 contiguous                 1.018 ns/elem  (    83x vs Python)
  np.sqrt float64 stride 2 (x[::2])          2.082 ns/elem  (    40x vs Python)
  np.exp float64 contiguous                  5.472 ns/elem  (    15x vs Python)
  np.exp float32 contiguous                  1.714 ns/elem  (    49x vs Python)
  np.add float64 contiguous                  2.013 ns/elem  (    42x vs Python)
  np.sqrt on an 8-element array: 660 ns per CALL - dispatch, not arithmetic, dominates
== C. summing 10M float32 values of 0.1 (float32(0.1) = 0.10000000149, so the exact sum is 1,000,000.0149)
  np.add.accumulate (sequential f32)         1087937.0000   error vs exact   87936.9851
  np.sum (pairwise f32)                      1000000.1250   error vs exact       0.1101
  np.sum(dtype=float64)                      1000000.0149   error vs exact       0.0000
  math.fsum (exact for the f32 inputs)       1000000.0149   error vs exact       0.0000
ALL ASSERTIONS PASSED
```

A ufunc beats the Python loop by 15–90× per element. Strided input (`x[::2]`) costs ~10 % here because the inner loop still sees a regular stride. The 8-element call shows the fixed ~0.6 µs entry cost: below a few hundred elements, NumPy is *slower* than plain Python arithmetic. **Pattern:** batch rows into arrays before calling ufuncs; never call NumPy per record.

### 2.2 The buffer protocol: one allocation, many typed views

```python
"""buffer_protocol_zero_copy.py - PEP 3118 in practice: one allocation, many typed views, zero copies.

Py_buffer = {buf, obj, len, itemsize, readonly, ndim, format, shape, strides, suboffsets, internal}.
Exporters (bytearray, mmap, array, ndarray) fill it; consumers (memoryview, np.frombuffer, file.readinto,
socket.recv_into, hashlib, zlib) read it. The exporter's export count blocks resizing while views exist.
"""
import ctypes
import mmap
import os
import struct
import tempfile
import time

import numpy as np

print("== A. one buffer, many views: same address")
raw = bytearray(64)
mv = memoryview(raw)
nd = np.frombuffer(raw, dtype=np.int64)               # 8 int64 over the same 64 bytes
addr_raw = ctypes.addressof(ctypes.c_char.from_buffer(raw))
addr_mv_slice = ctypes.addressof(ctypes.c_char.from_buffer(mv[16:]))
print(f"  np.frombuffer(raw).ctypes.data - address(raw) = {nd.ctypes.data - addr_raw} bytes")
print(f"  address(memoryview(raw)[16:])  - address(raw) = {addr_mv_slice - addr_raw} bytes")
nd[2] = 0x1122334455667788
print(f"  write via ndarray -> raw[16:24] = {bytes(raw[16:24]).hex()} (little-endian)")
assert nd.ctypes.data == addr_raw and addr_mv_slice == addr_raw + 16
try:
    raw.extend(b"x")
except BufferError as e:
    print(f"  raw.extend() while views exist -> BufferError: {e}")
del nd, mv

print("== B. what memoryview reports for a NumPy export (format, itemsize, shape, strides)")
m2 = np.arange(12, dtype=np.float32).reshape(3, 4)
for label, arr in [("C-order (3,4) float32", m2), ("transposed view", m2.T)]:
    v = memoryview(arr)
    print(f"  {label:22} format={v.format!r} itemsize={v.itemsize} shape={v.shape} strides={v.strides} "
          f"c_contiguous={v.c_contiguous} readonly={v.readonly}")
try:
    memoryview(m2.T).cast("B")
except TypeError as e:
    print(f"  memoryview(m2.T).cast('B') -> TypeError: {e}")

print("== C. parsing 1M binary records '<qid' (int64 id, int32 qty, float64 price; 20 B packed)")
N = 1_000_000
rec = np.dtype([("id", "<i8"), ("qty", "<i4"), ("price", "<f8")])
blob = np.zeros(N, rec)
blob["id"] = np.arange(N)
blob["qty"] = np.arange(N) % 7
blob["price"] = np.arange(N) * 0.25
payload = blob.tobytes()                              # what arrives from a socket/file
assert rec.itemsize == struct.calcsize("<qid") == 20
t0 = time.perf_counter()
total_struct = sum(q * p for _, q, p in struct.iter_unpack("<qid", payload))
t_struct = time.perf_counter() - t0
t0 = time.perf_counter()
view = np.frombuffer(payload, dtype=rec)              # zero copy: a typed header over `payload`
total_np = float((view["qty"] * view["price"]).sum())
t_np = time.perf_counter() - t0
assert abs(total_struct - total_np) < 1e-6 * total_np
print(f"  struct.iter_unpack + Python sum : {t_struct * 1e3:7.1f} ms")
print(f"  np.frombuffer(structured) + sum : {t_np * 1e3:7.1f} ms   ({t_struct / t_np:.0f}x)")
print(f"  view['price'] is a strided view : strides={view['price'].strides}, readonly={not view.flags.writeable}"
      f" (bytes are immutable)")

print("== D. a file mapped into memory: views over the page cache, no read() copy")
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "records.bin")
    with open(path, "wb") as f:
        f.write(payload)
    with open(path, "rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as mm:
        t0 = time.perf_counter()
        mapped = np.frombuffer(mm, dtype=rec)
        t_map = time.perf_counter() - t0
        s = float(mapped["price"].sum())
        print(f"  np.frombuffer(mmap) for {len(mm) / 2**20:.1f} MiB: {t_map * 1e6:.1f} us to create; sum={s:,.1f}")
        del mapped                                    # release the export before mm closes
    with open(path, "rb") as f:
        t0 = time.perf_counter()
        data = f.read()                               # one full copy into a new bytes object
        t_read = time.perf_counter() - t0
    print(f"  f.read() of the same file: {t_read * 1e3:.1f} ms and {len(data) / 2**20:.1f} MiB of new memory")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. one buffer, many views: same address
  np.frombuffer(raw).ctypes.data - address(raw) = 0 bytes
  address(memoryview(raw)[16:])  - address(raw) = 16 bytes
  write via ndarray -> raw[16:24] = 8877665544332211 (little-endian)
  raw.extend() while views exist -> BufferError: Existing exports of data: object cannot be re-sized
== B. what memoryview reports for a NumPy export (format, itemsize, shape, strides)
  C-order (3,4) float32  format='f' itemsize=4 shape=(3, 4) strides=(16, 4) c_contiguous=True readonly=False
  transposed view        format='f' itemsize=4 shape=(4, 3) strides=(4, 16) c_contiguous=False readonly=False
  memoryview(m2.T).cast('B') -> TypeError: memoryview: casts are restricted to C-contiguous views
== C. parsing 1M binary records '<qid' (int64 id, int32 qty, float64 price; 20 B packed)
  struct.iter_unpack + Python sum :    99.0 ms
  np.frombuffer(structured) + sum :     4.7 ms   (21x)
  view['price'] is a strided view : strides=(20,), readonly=True (bytes are immutable)
== D. a file mapped into memory: views over the page cache, no read() copy
  np.frombuffer(mmap) for 19.1 MiB: 11.6 us to create; sum=124,999,875,000.0
  f.read() of the same file: 6.7 ms and 19.1 MiB of new memory
ALL ASSERTIONS PASSED
```

* The NumPy view and the memoryview slice point *into* the bytearray (offset 0 and +16), and a write through the ndarray is visible in the raw bytes. The export count makes `raw.extend()` fail rather than invalidate the views. That's the protocol working as designed, unlike the `np.ndarray(buffer=shm.buf)` crash in 01.3, where NumPy kept a reference without an export.
* **Binary parsing:** a packed 20-byte record format decoded with `struct.iter_unpack` is ~19–21× slower than reinterpreting the same bytes as a structured dtype and computing on its field views (zero copy; `view['price']` has stride 20). This is how you parse network or file formats at memory speed in Python.
* `np.frombuffer(mmap)` creates a typed view over the page cache in ~10–20 µs; `f.read()` copies the file into a new `bytes` object (6–7 ms and 19 MiB here). Memory-mapped reads are the basis of Arrow IPC/Feather zero-copy reads (02.3) and of `np.load(mmap_mode='r')`.

### 2.3 Trap: a recurrence NumPy can't vectorize — six implementations

The kernel is a sessionized time-decay EWMA: `out[i]` depends on `out[i-1]`, with resets at user and session boundaries. No ufunc composition expresses it exactly.

```cython
# ewma_cy.pyx - sessionized time-decay EWMA in Cython: typed memoryviews, no bounds checks, GIL released.
# cython: boundscheck=False, wraparound=False, cdivision=True, language_level=3
from libc.math cimport exp


def ewma(const double[::1] ts, const double[::1] x, const long long[::1] uid, double[::1] out,
         double tau, double session):
    # long long, not long: Windows is LLP64 (long = 32 bit) and int64 buffers export format 'q'
    cdef Py_ssize_t i, n = ts.shape[0]
    cdef double gap, a
    with nogil:
        out[0] = x[0]
        for i in range(1, n):
            gap = ts[i] - ts[i - 1]
            if uid[i] != uid[i - 1] or gap > session:
                out[i] = x[i]                      # new user or new session: restart the average
            else:
                a = exp(-gap / tau)
                out[i] = a * out[i - 1] + (1.0 - a) * x[i]
```

```c
/* ewma_c.c - sessionized time-decay EWMA in plain C, called through ctypes (CDLL releases the GIL). */
/* Build: gcc -O2 -shared -o ewma_c.dll ewma_c.c   (Linux: -fPIC -o libewma_c.so -lm) */
#include <math.h>
#include <stdint.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif

EXPORT void ewma(const double *ts, const double *x, const int64_t *uid, double *out, int64_t n,
                 double tau, double session) {
    out[0] = x[0];
    for (int64_t i = 1; i < n; i++) {
        double gap = ts[i] - ts[i - 1];
        if (uid[i] != uid[i - 1] || gap > session) {
            out[i] = x[i];
        } else {
            double a = exp(-gap / tau);
            out[i] = a * out[i - 1] + (1.0 - a) * x[i];
        }
    }
}
```

```python
"""kernels_numba_cython.py - a kernel NumPy cannot vectorize (a data-dependent recurrence), six ways.

Sessionized time-decay EWMA over 2M events sorted by (user, time): out[i] depends on out[i-1], with resets at
user changes and session gaps. Compares pure Python, Python indexing into ndarrays, Numba, Cython, C via
ctypes, and Numba parallel across users; reports Numba's one-time compile cost.
usage: python kernels_numba_cython.py BUILD_DIR   (holds ewma_cy*.pyd and ewma_c.dll from f02.sh)
"""
import ctypes
import math
import os
import sys
import time

import numba
import numpy as np

build = sys.argv[1]
sys.path.insert(0, build)
import ewma_cy  # noqa: E402  (built from ewma_cy.pyx by f02.sh)

TAU, SESSION = 300.0, 1800.0
N, USERS = 2_000_000, 2_000
rng = np.random.default_rng(0)
uid = np.sort(rng.integers(0, USERS, N)).astype(np.int64)
gaps = rng.exponential(120.0, N)
gaps[rng.random(N) < 0.01] += 3600.0                  # 1% of gaps start a new session
ts = np.cumsum(gaps)
x = rng.random(N) * 100.0


def ewma_python(ts, x, uid):
    out = [0.0] * len(ts)
    out[0] = x[0]
    for i in range(1, len(ts)):
        gap = ts[i] - ts[i - 1]
        if uid[i] != uid[i - 1] or gap > SESSION:
            out[i] = x[i]
        else:
            a = math.exp(-gap / TAU)
            out[i] = a * out[i - 1] + (1.0 - a) * x[i]
    return out


@numba.njit(cache=False, nogil=True)
def ewma_numba(ts, x, uid, out):
    out[0] = x[0]
    for i in range(1, ts.shape[0]):
        gap = ts[i] - ts[i - 1]
        if uid[i] != uid[i - 1] or gap > SESSION:
            out[i] = x[i]
        else:
            a = math.exp(-gap / TAU)
            out[i] = a * out[i - 1] + (1.0 - a) * x[i]


@numba.njit(cache=False, parallel=True)
def ewma_numba_parallel(ts, x, starts, out):
    for u in numba.prange(starts.shape[0] - 1):        # users are independent: one recurrence each
        lo, hi = starts[u], starts[u + 1]
        out[lo] = x[lo]
        for i in range(lo + 1, hi):
            gap = ts[i] - ts[i - 1]
            if gap > SESSION:
                out[i] = x[i]
            else:
                a = math.exp(-gap / TAU)
                out[i] = a * out[i - 1] + (1.0 - a) * x[i]


lib = ctypes.CDLL(os.path.join(build, "ewma_c.dll"))
dp = np.ctypeslib.ndpointer(np.float64, flags="C_CONTIGUOUS")
lib.ewma.argtypes = [dp, dp, np.ctypeslib.ndpointer(np.int64, flags="C_CONTIGUOUS"), dp, ctypes.c_int64,
                     ctypes.c_double, ctypes.c_double]
lib.ewma.restype = None


def timed(fn):
    t0 = time.perf_counter()
    r = fn()
    return time.perf_counter() - t0, r


ref_out = np.empty(N)
t_compile, _ = timed(lambda: ewma_numba(ts[:10], x[:10], uid[:10], ref_out[:10]))
starts = np.flatnonzero(np.r_[True, uid[1:] != uid[:-1], True]).astype(np.int64)
t_compile_par, _ = timed(lambda: ewma_numba_parallel(ts, x, starts, np.empty(N)))

results = {}
t, r = timed(lambda: ewma_python(ts.tolist(), x.tolist(), uid.tolist()))
results["pure Python over lists (.tolist())"] = (t, np.asarray(r))
t, r = timed(lambda: ewma_python(ts, x, uid))
results["pure Python indexing ndarrays"] = (t, np.asarray(r))
out = np.empty(N)
t, _ = timed(lambda: ewma_numba(ts, x, uid, out))
results["Numba @njit"] = (t, out.copy())
t, _ = timed(lambda: ewma_cy.ewma(ts, x, uid, out, TAU, SESSION))
results["Cython typed memoryviews, nogil"] = (t, out.copy())
t, _ = timed(lambda: lib.ewma(ts, x, uid, out, N, TAU, SESSION))
results["C via ctypes"] = (t, out.copy())
t, _ = timed(lambda: ewma_numba_parallel(ts, x, starts, out))
results[f"Numba parallel prange ({numba.get_num_threads()} threads)"] = (t, out.copy())

ref = results["pure Python over lists (.tolist())"][1]
base = results["pure Python over lists (.tolist())"][0]
print(f"{N:,} events, {len(starts) - 1:,} users; numba {numba.__version__}")
print(f"{'implementation':44} {'ms':>9} {'speedup':>9}")
for label, (t, r) in results.items():
    assert np.allclose(r, ref, rtol=1e-12, atol=1e-9), label
    print(f"  {label:42} {t * 1e3:9.1f} {base / t:8.1f}x")
print(f"  Numba one-time JIT compile: serial {t_compile * 1e3:.0f} ms, parallel {t_compile_par * 1e3:.0f} ms "
      f"(paid per process unless cache=True)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
2,000,000 events, 2,000 users; numba 0.68.1
implementation                                      ms   speedup
  pure Python over lists (.tolist())             785.3      1.0x
  pure Python indexing ndarrays                 2011.4      0.4x
  Numba @njit                                     19.8     39.6x
  Cython typed memoryviews, nogil                 24.6     31.9x
  C via ctypes                                    17.8     44.0x
  Numba parallel prange (12 threads)               5.0    156.9x
  Numba one-time JIT compile: serial 331 ms, parallel 352 ms (paid per process unless cache=True)
ALL ASSERTIONS PASSED
```

* **Indexing ndarrays from Python is ~2.5× *slower* than lists**: each `ts[i]` boxes a new `np.float64`.
* Numba, Cython and C land within ~1.5× of each other at **30–45× pure Python**. Once types are concrete, they all emit the same machine loop, dominated by `exp()`.
* Numba `prange` over the 2 000 independent per-user series adds another 2–4× on 12 threads (it varies run to run at this size, 5–9 ms; thread start-up and memory bandwidth cap the gain).
* Numba's ~330 ms compile is paid per process, so use `cache=True` (or ahead-of-time compilation) for short-lived workers.

**Choosing among them in production:** Numba for numeric kernels iterated in notebooks and services (no build step, but an LLVM dependency and compile-on-first-call). Cython or C/C++ (pybind11/nanobind) for kernels that ship in wheels, need C library calls, or must support free-threaded builds deliberately. Don't hand-roll anything a columnar engine already has: Polars and DuckDB have windowed and `ewm_*` functions (Folder 03).

### 2.4 Trap: chaining ufuncs over large arrays — fusion

```python
"""fusion_numexpr.py - one ufunc per operator = one full pass over memory per operator; fusion = one pass.

y = sin(a) + cos(b) * c   (compute-heavy)   and   y = a*b + c*d - a   (memory-bound), 16M float64 per array.
Eager NumPy materializes every intermediate (traffic ~ 2.5x the fused minimum); numexpr evaluates in cache-sized
blocks; a Numba loop fuses completely. This is the CPU analogue of why torch.compile/Inductor fuses GPU kernels.
"""
import time

import numba
import numexpr as ne
import numpy as np

N = 16 * 2**20
MiB = 2**20
rng = np.random.default_rng(0)
a, b, c, d = (rng.random(N) for _ in range(4))
y = np.empty(N)
tmp = np.empty(N)


@numba.njit(cache=False)
def fused_trig(a, b, c, y):
    for i in range(a.shape[0]):
        y[i] = np.sin(a[i]) + np.cos(b[i]) * c[i]


@numba.njit(cache=False, parallel=True)
def fused_trig_par(a, b, c, y):
    for i in numba.prange(a.shape[0]):
        y[i] = np.sin(a[i]) + np.cos(b[i]) * c[i]


@numba.njit(cache=False)
def fused_lin(a, b, c, d, y):
    for i in range(a.shape[0]):
        y[i] = a[i] * b[i] + c[i] * d[i] - a[i]


def best(fn, reps=3):
    t = []
    for _ in range(reps):
        t0 = time.perf_counter()
        fn()
        t.append(time.perf_counter() - t0)
    return min(t)


def np_out_trig():
    np.sin(a, out=y)
    np.cos(b, out=tmp)
    np.multiply(tmp, c, out=tmp)
    np.add(y, tmp, out=y)


fused_trig(a[:8], b[:8], c[:8], y[:8])
fused_trig_par(a[:8], b[:8], c[:8], y[:8])
fused_lin(a[:8], b[:8], c[:8], d[:8], y[:8])
ref_trig = np.sin(a) + np.cos(b) * c
ref_lin = a * b + c * d - a
threads = ne.detect_number_of_cores()


def ne_eval(expr, nthreads, **arrays):
    ne.set_num_threads(nthreads)
    return ne.evaluate(expr, local_dict=arrays, out=y)


print(f"16M float64 per array ({N * 8 / MiB:.0f} MiB); traffic counts reads+writes of whole arrays")
cases = [
    ("trig", "eager NumPy (3 temporaries)", 10, lambda: np.sin(a) + np.cos(b) * c),
    ("trig", "NumPy with out= (1 reused temp)", 10, np_out_trig),
    ("trig", "numexpr, 1 thread (blocked)", 4, lambda: ne_eval("sin(a) + cos(b) * c", 1, a=a, b=b, c=c)),
    ("trig", f"numexpr, {threads} threads", 4, lambda: ne_eval("sin(a) + cos(b) * c", threads, a=a, b=b, c=c)),
    ("trig", "Numba fused loop, 1 thread", 4, lambda: fused_trig(a, b, c, y)),
    ("trig", f"Numba fused prange, {numba.get_num_threads()} threads", 4, lambda: fused_trig_par(a, b, c, y)),
    ("lin", "eager NumPy (4 temporaries)", 13, lambda: a * b + c * d - a),
    ("lin", "numexpr, 1 thread (blocked)", 5, lambda: ne_eval("a*b + c*d - a", 1, a=a, b=b, c=c, d=d)),
    ("lin", "Numba fused loop, 1 thread", 5, lambda: fused_lin(a, b, c, d, y)),
]
base = {}
for kind, label, arrays_moved, fn in cases:
    dt = best(fn)
    base.setdefault(kind, dt)
    if kind == "trig" and label.startswith(("numexpr", "Numba", "NumPy with")):
        assert np.allclose(y, ref_trig)
    if kind == "lin" and not label.startswith("eager"):
        assert np.allclose(y, ref_lin)
    expr = "sin(a)+cos(b)*c" if kind == "trig" else "a*b+c*d-a"
    print(f"  {expr:16} {label:34} {dt * 1e3:7.1f} ms  ~{arrays_moved * N * 8 / MiB:5.0f} MiB moved  "
          f"{base[kind] / dt:5.1f}x")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
16M float64 per array (128 MiB); traffic counts reads+writes of whole arrays
  sin(a)+cos(b)*c  eager NumPy (3 temporaries)          282.4 ms  ~ 1280 MiB moved    1.0x
  sin(a)+cos(b)*c  NumPy with out= (1 reused temp)      224.4 ms  ~ 1280 MiB moved    1.3x
  sin(a)+cos(b)*c  numexpr, 1 thread (blocked)          252.7 ms  ~  512 MiB moved    1.1x
  sin(a)+cos(b)*c  numexpr, 12 threads                   37.4 ms  ~  512 MiB moved    7.5x
  sin(a)+cos(b)*c  Numba fused loop, 1 thread           196.2 ms  ~  512 MiB moved    1.4x
  sin(a)+cos(b)*c  Numba fused prange, 12 threads        34.4 ms  ~  512 MiB moved    8.2x
  a*b+c*d-a        eager NumPy (4 temporaries)          174.8 ms  ~ 1664 MiB moved    1.0x
  a*b+c*d-a        numexpr, 1 thread (blocked)           74.3 ms  ~  640 MiB moved    2.4x
  a*b+c*d-a        Numba fused loop, 1 thread            45.8 ms  ~  640 MiB moved    3.8x
ALL ASSERTIONS PASSED
```

* Compute-bound trig: fusion gives 1.1–1.4×, and multithreading the fused loop gives **7.5–8.6×**.
* Memory-bound arithmetic: a single-thread fused loop is **~4× faster** than eager NumPy (640 instead of 1 664 MiB moved, and no fresh temporaries to page-fault in).
* `numexpr` is the lowest-friction fusion (a string expression, cache-sized blocks, threads). Numba is the most general. Polars/DuckDB expression engines do the same inside query plans (03.2–03.3), and TorchInductor does it for GPU kernels (06.3).

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 ⚡ | "Vectorized" code slower than the loop it replaced | Profile shows ufunc entry overhead; arrays of ~10 elements | ~0.6 µs fixed cost per ufunc call | Batch rows into big arrays; plain Python for tiny data | Benchmark at production batch sizes |
| F2 | Aggregates drift from the reference by percent-level amounts | float32 sums disagree with float64 | Sequential float32 accumulation (cumsum, hand loops, some GPU kernels) | Accumulate in float64; pairwise/Kahan summation | Differential test against `math.fsum` on samples |
| F3 🔥 | `BufferError: Existing exports...` / `cannot close exported pointers exist` | Raised on resize or close | Live views of a bytearray/mmap | Release views (`del`, `memoryview.release()`, context managers) first | Scope views to `with` blocks |
| F4 🔥 | Cython extension fails or reads garbage on Windows only | Buffer dtype mismatch, or values wrong by 2³² | `long` is 32-bit on Windows (LLP64) | Type int64 buffers as `long long` / `int64_t` | CI on Windows and Linux; fixed-width types only |
| F5 ⚡ | First request after deploy takes 300+ ms | Numba compile in the request path | JIT on first call, per process | `cache=True`, warm-up at startup, AOT compile | Readiness probe that runs the warm-up |
| F6 | `parallel=True` makes the kernel *slower* | Thread pool start-up dominates on small inputs | Fork/join overhead > work | Gate parallelism by size; reuse the pool across calls | Benchmark the parallel/serial crossover |
| F7 ⚡ | Memory-bound pipeline doesn't speed up with more cores | GB/s near DRAM limit | Eager temporaries saturate bandwidth | Fuse (numexpr/Numba/Polars expressions) | Count arrays moved per output byte |
| F8 | AVX-512 machine no faster than AVX2 | `__cpu_dispatch__` lacks X86_V4 | The wheel was built without AVX-512 targets | Accept it, or use libraries with their own dispatch (BLAS, Polars) | Check `np.show_runtime()` on target hardware |

**Debugging toolkit.** `np.show_runtime()` and `numpy._core._multiarray_umath.__cpu_dispatch__` show SIMD. `numba.njit(...).inspect_types()` / `inspect_asm()` show what Numba generated. `cython -a` produces an HTML annotation where yellow lines touch the Python C API. `memoryview(x).format/.strides/.readonly` inspect any exporter. `perf stat -e cycles,instructions,LLC-load-misses` (Linux) separates compute-bound from memory-bound.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "What exactly happens between `np.sqrt(x)` and the SIMD instructions?"</b></summary>

**Initial Prompt.** Trace a ufunc call from Python to machine code and name every cost.

**L5 Answer.** "NumPy calls a C function that loops with SIMD."

**Why L5 Crashes at Scale.** Without the fixed costs (argument parsing, type resolution, iterator construction, GIL release) you can't explain why 10-element calls are slower than Python, why dtype mixes trigger hidden casts and buffers, or why AVX-512 hardware isn't faster with a given wheel.

**L7 Principal Defense.** The ufunc normalizes arguments and resolves a loop for the promoted dtypes (the NumPy 2 ArrayMethod machinery). It builds an nditer that broadcasts, coalesces contiguous axes, orders them by stride and allocates cast buffers only when dtypes or alignment demand it. It releases the GIL and calls the strided inner loop. That loop's SIMD variant was chosen at import from `__cpu_dispatch__`: X86_V3/AVX2 here, even on an AVX-512 CPU. Measured costs: ~0.6 µs per call fixed, then 1–5 ns per element depending on the function and dtype. So the design rules are: large contiguous same-dtype operands, `out=` to skip allocation, and float32 where precision allows (2× for compute-bound functions).

</details>

<details><summary><b>Q2 · "How do you parse 10 GB/s of fixed-width binary records in Python?"</b></summary>

**Initial Prompt.** A market-data feed delivers packed 20-byte records. The current `struct.unpack` loop keeps up with only 10 % of the feed.

**L5 Answer.** "Use multiprocessing to parallelize `struct.unpack`."

**Why L5 Crashes at Scale.** Each worker pays the per-record Python cost (≈ 100–115 ns per record measured), plus pickling of results back. You'd need dozens of cores and still saturate on IPC.

**L7 Principal Defense.** Don't parse records; reinterpret the buffer. `recv_into` / `readinto` a preallocated `bytearray`, then `np.frombuffer(buf, dtype=record_dtype)` gives zero-copy field views (stride = record size), and computation runs as vectorized ops over those fields. Measured: ~20× faster than `struct.iter_unpack`, and the decode cost becomes ~0. Handle endianness in the dtype (`'<i8'`) and alignment with `align=False` packed dtypes. For sustained rates, use a ring of preallocated buffers to avoid allocation, and hand batches to Arrow (02.3) for downstream engines.

</details>

<details><summary><b>Q3 · "Numba, Cython, C++ (pybind11/nanobind), or Rust (PyO3)? Choose for a shared feature-engineering library."</b></summary>

**Initial Prompt.** Five teams need a library of custom kernels (sessionization, decay features, quantile sketches) usable from batch jobs and online services.

**L5 Answer.** "Numba, because it's fastest to write."

**Why L5 Crashes at Scale.** Numba's speed is similar to the others (measured within ~1.5×), but it adds per-process JIT latency (~330 ms), an LLVM dependency, a narrower supported Python subset, and lag on new Python versions (free-threaded support in particular). For a *shared, versioned library* those operational costs dominate.

**L7 Principal Defense.** Separate prototyping from shipping. Prototype in Numba: no build, and the numerics are validated against a reference. Ship as compiled wheels, using Cython for NumPy-centric kernels and nanobind/pybind11 or PyO3 when you need rich types, threads or C++/Rust libraries. Build `cp314`/`cp314t`/`abi3t` wheels and release the GIL explicitly. Expose array-in/array-out APIs over the buffer protocol or Arrow so Polars, DuckDB and PyTorch callers pay no conversion. And check first whether a columnar engine already has the kernel; the best custom kernel is the one you don't maintain.

</details>

<details><summary><b>Q4 · "Our fp32 revenue rollups disagree with finance by 0.5 %. The code just calls cumsum."</b></summary>

**Initial Prompt.** Daily revenue is accumulated with `np.cumsum` on float32 arrays of ~10 M transactions.

**L5 Answer.** "Floating point is inexact; round at the end."

**Why L5 Crashes at Scale.** Rounding can't recover a systematic bias. Sequential float32 accumulation loses low-order bits once the running sum dwarfs each addend. Measured on 10 M × 0.1: an 8.8 % error for the sequential sum against 0.00001 % pairwise.

**L7 Principal Defense.** Money is integer cents in int64 (exact), never float. For float metrics, accumulate in float64 or pairwise/Kahan. `np.sum` is pairwise; `cumsum`/`accumulate` and naive loops are sequential. Validate aggregates against an exact reference (`math.fsum`, `decimal`) on samples in CI. The same physics bites GPU reductions in bf16/fp16 (06.4), where accumulation must be fp32.

</details>

<details><summary><b>Q5 · "Why did `numexpr` speed up our formula 4× on one core?"</b></summary>

**Initial Prompt.** Replacing `a*b + c*d - a` with `numexpr.evaluate` on 16 M-element arrays made it 2–4× faster single-threaded. Explain without hand-waving.

**L5 Answer.** "numexpr is written in C and optimized."

**Why L5 Crashes at Scale.** NumPy is also C. The difference is *memory traffic*, and if you don't see that you'll miss the same win in Polars expressions, Inductor kernels and SQL engines.

**L7 Principal Defense.** Eager NumPy writes each intermediate to a fresh 128 MiB array and reads it back: ~1.6 GiB of DRAM traffic plus page faults for four new arrays. numexpr evaluates in cache-sized blocks, so intermediates live in L1/L2, and traffic drops to the 640 MiB minimum (four inputs read, one output written). A Numba fused loop gets ~4× by the same argument. The general rule is that when arithmetic intensity is low (a few flops per byte), performance equals bytes moved, so fuse. When it's high (trig, transcendental), fusion helps little and parallelism or a better algorithm is the lever.

</details>

<details><summary><b>Q6 · "Explain the buffer protocol's export count and why it prevents a class of crashes."</b></summary>

**Initial Prompt.** What happens if a bytearray is resized while a NumPy array views it?

**L5 Answer.** "Python copies the data so both stay valid."

**Why L5 Crashes at Scale.** Nothing is copied. Without protection the view would dangle after `realloc`. Engineers who don't know the mechanism also don't know which APIs bypass it (raw pointers via `ctypes`, `np.ndarray(buffer=...)` over an mmap), and that's where the real crashes come from (01.3).

**L7 Principal Defense.** `bf_getbuffer` increments the exporter's export count, and resize or close refuses while it's non-zero (`BufferError: Existing exports...`, measured). Every consumer that holds a `Py_buffer` (memoryview, `np.frombuffer`, Cython memoryviews) participates. Consumers that take only a raw address don't: `ctypes` pointers, `__array_interface__` integers, a NumPy array constructed with `buffer=` over an mmap that releases its view. Treat those as unsafe and give them explicit lifetimes (context managers) in your API.

</details>

<details><summary><b>Q7 · "A Numba kernel is fast in benchmarks but our Lambda p99 is 400 ms. Why?"</b></summary>

**Initial Prompt.** A serverless scoring function uses `@numba.njit` kernels.

**L5 Answer.** "Lambda cold starts are slow; provision concurrency."

**Why L5 Crashes at Scale.** Provisioned concurrency hides it at a cost, but every new container still JIT-compiles every kernel on first call (~330 ms measured per kernel family), and scaling events multiply cold starts exactly when load spikes.

**L7 Principal Defense.** Make compilation a build artifact. Use `cache=True` with a cache directory baked into the image, warmed at build time, or ahead-of-time compilation, or move the kernel to Cython/C in the wheel. Add a warm-up call in the init phase, not the handler, and track first-call latency separately. For tiny inputs, check whether the kernel is worth it at all: 0.6 µs of NumPy dispatch, or a compiled call, may exceed the work.

</details>

<details><summary><b>Q8 · "When should you NOT vectorize?"</b></summary>

**Initial Prompt.** A reviewer demands that every loop be rewritten with NumPy.

**L5 Answer.** "Always vectorize; Python loops are slow."

**Why L5 Crashes at Scale.** Vectorization trades interpreter overhead for memory traffic and allocation. For recurrences it's impossible or needs O(n·w) tricks. For small n it's slower (per-call overhead). For branchy logic, masks evaluate both branches over the whole array.

**L7 Principal Defense.** Use a cost model. Vectorize when n is large, the operation maps to existing kernels, and temporaries fit the memory budget (fuse when they don't). Compile (Numba/Cython) when there's a loop-carried dependency or heavy branching (EWMA: 30–45× compiled). Use plain Python for small, control-heavy code. Push relational logic into a query engine (Polars/DuckDB), which vectorizes *and* fuses *and* parallelizes. Profile with production shapes before rewriting.

</details>

---

## 5. Invariants Checklist

- [ ] A ufunc call costs ~0.6 µs before the first element. Vectorize big batches only.
- [ ] SIMD variants are chosen at import from the wheel's `__cpu_dispatch__`. Check what your build supports (X86_V3 only here).
- [ ] float32 doubles SIMD lanes and halves bytes. Accumulate in float64 (pairwise `np.sum`, not `cumsum`).
- [ ] The buffer protocol shares memory and an export count protects it. Raw-pointer paths have no protection.
- [ ] Reinterpret binary data with structured dtypes over `frombuffer`/`mmap` instead of parsing records.
- [ ] Python-level indexing of ndarrays is slower than lists. Compile loops (Numba/Cython/C, 30–45×) or vectorize.
- [ ] Numba compiles per process. Cache or AOT-compile for short-lived workers.
- [ ] Windows is LLP64: type int64 as `long long` / `int64_t` in C and Cython.
- [ ] Memory-bound chains: performance ≈ bytes moved, so fuse. Compute-bound chains: parallelize.

---

## 6. References

- PEP 3118, Revising the buffer protocol — https://peps.python.org/pep-3118/
- Python C-API, buffer protocol (`Py_buffer`) — https://docs.python.org/3/c-api/buffer.html
- `memoryview` — https://docs.python.org/3/library/stdtypes.html#memoryview
- NumPy ufunc internals and the C-API for ufuncs — https://numpy.org/doc/stable/reference/c-api/ufunc.html
- NumPy CPU/SIMD optimizations (baseline and dispatch) — https://numpy.org/doc/stable/reference/simd/index.html
- NEP 43, Enhancing the extensibility of UFuncs (ArrayMethod) — https://numpy.org/neps/nep-0043-extensible-ufuncs.html
- Numba documentation (njit, parallel, caching) — https://numba.readthedocs.io/en/stable/
- Cython typed memoryviews — https://cython.readthedocs.io/en/latest/src/userguide/memoryviews.html
- numexpr — https://github.com/pydata/numexpr
- N. Higham, "The accuracy of floating point summation", SIAM J. Sci. Comput. 14(4), 1993, DOI 10.1137/0914050.
- DLPack specification — https://dmlc.github.io/dlpack/latest/
