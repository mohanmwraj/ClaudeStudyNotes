# 01.1 · `PyObject` C Structs, Refcounting, Cyclic GC & `__slots__` Memory Math

> **Folder 01 · CPython Runtime, Memory Model & Concurrency Physics**
> **Measured on:** CPython 3.14.5 (python.org Windows x64 build, default/GIL), NumPy 2.5.4, psutil 7.2.2, GCC 16.2 · Intel i5-11260H (6C/12T), 16 GB, Windows 11.
> **Source verified against:** CPython tags `v3.14.10` and `v3.15.2` (`Include/object.h`, `Include/refcount.h`, `Include/cpython/longintrepr.h`, `Objects/longobject.c`, `Objects/listobject.c`, `Include/internal/pycore_obmalloc.h`, `Python/gc.c`).
> **Tags:** 🔥 production-critical · ⚡ performance lever · 🧊 Java/C++ bridge · ⚠ release-dependent or not executed here.

---

## 0. Orientation & the JVM/C++ Bridge

In CPython every value is a heap object reached through a `PyObject*`. A `list` is an array of pointers, an `int` is a 32-byte allocation, and copying a reference writes to the referent's cache line, because that copy is a refcount increment. Almost every Python memory or latency incident comes back to three facts: **headers**, **pointer chasing**, and **refcount writes**. The L7 move is to keep data in **contiguous, typed buffers** (`array`, NumPy, Arrow) and use Python objects only for orchestration and metadata.

🧊 **The bridge table.** The JVM column is layout arithmetic for HotSpot with compressed class pointers. It wasn't executed here.

| Concept | CPython 3.14 (default build) | HotSpot JVM (JDK 21–25) | C++ |
|---|---|---|---|
| Object header | 16 B: `ob_refcnt`(u32) + `ob_overflow`(u16) + `ob_flags`(u16) + `ob_type`. Free-threaded build: **32 B** | 12 B: mark word + compressed klass pointer. 8 B with `-XX:+UseCompactObjectHeaders` (JEP 519) | 0 B for PODs; 8 B vptr if polymorphic |
| A boxed 64-bit integer | `sys.getsizeof` says 28 B; the allocator gives it a **32 B** block | `java.lang.Long` = 24 B (16 B with compact headers) | `int64_t`: 8 B, inline |
| 10 M integers in "a list" | **≈ 402 MB** measured (`list[int]`) | `ArrayList<Long>` ≈ 40 MB `Object[]` + 240 MB of `Long` ≈ 280 MB | `std::vector<int64_t>`: 80 MB |
| Value cache | ints −5…256 (3.14), −5…**1024** (3.15), all immortal | `Long.valueOf` −128…127 | n/a |
| Reclamation | Refcount (immediate) + generational cycle GC for containers | Tracing, moving, compacting GC (G1/ZGC) | RAII; `shared_ptr` atomic refcount |
| Small-object allocation | pymalloc: 16-B size classes ≤ 512 B, 16 KiB pools, 1 MiB arenas | TLAB bump-pointer | `malloc` size classes, arenas, `pmr` |
| Fragmentation | Non-moving: a single survivor pins a 1 MiB arena | Compaction removes it | Non-moving, like CPython |
| Field layout | Inline-values array (3.13+) or `__slots__` member offsets | Field offsets fixed at class load | Struct offsets fixed at compile time |
| Refcount atomicity | Plain store (GIL build); biased local/shared (free-threaded build) | n/a | `shared_ptr`: always atomic |

The rest of this file proves every CPython cell in that table on a live interpreter.

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The universal header — `PyObject`

`Include/object.h` at `v3.14.10`, 64-bit little-endian, default (GIL) build:

```text
 offset  0                 4          6          8                          16
         +-----------------+----------+----------+--------------------------+
PyObject | ob_refcnt  u32  | overflow | ob_flags | ob_type -> PyTypeObject  |
         +-----------------+----------+----------+--------------------------+
          \________ union: int64 ob_refcnt_full ________/
PyVarObject = PyObject + Py_ssize_t ob_size  (24 B)       e.g. tuple, bytes, (list: see 1.3)
```

Since 3.14 the refcount word is a union. The low 32 bits are the count. Bits 32–47 (`ob_overflow`) absorb overflow for objects that are still mortal. Bits 48–63 hold `ob_flags`, and statically allocated immortals carry `_Py_STATICALLY_ALLOCATED_FLAG | _Py_IMMORTAL_FLAGS` = `0x0005` there. `Py_INCREF` in the default 64-bit build is, verbatim:

```c
PY_UINT32_T cur_refcnt = op->ob_refcnt;
if (cur_refcnt >= _Py_IMMORTAL_INITIAL_REFCNT) { return; }   /* immortal: 3 << 30 */
op->ob_refcnt = cur_refcnt + 1;                              /* plain 32-bit store, no lock prefix */
```

`Py_DECREF` tests immortality with the sign bit of the 32-bit count: anything at or above `_Py_IMMORTAL_MINIMUM_REFCNT` (1 << 31) is never decremented. PEP 683's immortal objects exist so that `None`, `True`, small ints, `()`, `''` and the static type objects are **never written to** by refcounting. That matters in three places. Their cache lines can stay shared across cores. Their pages stay shared across `fork()`. And the free-threaded build needs no atomics for them.

The free-threaded (`Py_GIL_DISABLED`) header is twice as large. The C listing below compiles the *same* headers both ways and prints the real offsets; 01.2 explains every field.

```c
/* pyobject_layout.c - sizeof/offsetof of CPython 3.14 object headers, default vs free-threaded (Py_GIL_DISABLED). */
/* Build twice against the same headers:  cc -I<python>/include pyobject_layout.c [-DPy_GIL_DISABLED=1]   */
#include <Python.h>
#include <stddef.h>
#include <stdio.h>

#define F(T, m) printf("  %-34s off %3zu  size %2zu\n", #T "." #m, offsetof(T, m), sizeof(((T *)0)->m))

int main(void) {
#ifdef Py_GIL_DISABLED
    puts("build: free-threaded (Py_GIL_DISABLED) - biased refcount header");
    F(PyObject, ob_tid);
    F(PyObject, ob_flags);
    F(PyObject, ob_mutex);
    F(PyObject, ob_gc_bits);
    F(PyObject, ob_ref_local);
    F(PyObject, ob_ref_shared);
    F(PyObject, ob_type);
#else
    puts("build: default (GIL) - one 64-bit refcount word");
    F(PyObject, ob_refcnt);
    F(PyObject, ob_overflow);
    F(PyObject, ob_flags);
    F(PyObject, ob_type);
#endif
    F(PyVarObject, ob_size);
    F(PyLongObject, long_value.lv_tag);
    F(PyLongObject, long_value.ob_digit);
    F(PyFloatObject, ob_fval);
    F(PyListObject, ob_item);
    F(PyListObject, allocated);
    F(PyTupleObject, ob_hash);
    F(PyTupleObject, ob_item);
    printf("  sizeof(PyObject)=%zu sizeof(PyVarObject)=%zu sizeof(PyListObject)=%zu sizeof(PyFloatObject)=%zu\n",
           sizeof(PyObject), sizeof(PyVarObject), sizeof(PyListObject), sizeof(PyFloatObject));
    /* An int with one 30-bit digit: header + lv_tag + one uint32 digit. */
    size_t one_digit = offsetof(PyLongObject, long_value.ob_digit) + sizeof(digit);
    printf("  one-digit int = %zu B requested -> %zu B block at 16-byte alignment\n",
           one_digit, (one_digit + 15) & ~(size_t)15);
    return 0;
}
```

Output (deterministic, verified — default build):

```text
build: default (GIL) - one 64-bit refcount word
  PyObject.ob_refcnt                 off   0  size  4
  PyObject.ob_overflow               off   4  size  2
  PyObject.ob_flags                  off   6  size  2
  PyObject.ob_type                   off   8  size  8
  PyVarObject.ob_size                off  16  size  8
  PyLongObject.long_value.lv_tag     off  16  size  8
  PyLongObject.long_value.ob_digit   off  24  size  4
  PyFloatObject.ob_fval              off  16  size  8
  PyListObject.ob_item               off  24  size  8
  PyListObject.allocated             off  32  size  8
  PyTupleObject.ob_hash              off  24  size  8
  PyTupleObject.ob_item              off  32  size  8
  sizeof(PyObject)=16 sizeof(PyVarObject)=24 sizeof(PyListObject)=40 sizeof(PyFloatObject)=24
  one-digit int = 28 B requested -> 32 B block at 16-byte alignment
```

Output (deterministic, verified — same headers with `-DPy_GIL_DISABLED=1`):

```text
build: free-threaded (Py_GIL_DISABLED) - biased refcount header
  PyObject.ob_tid                    off   0  size  8
  PyObject.ob_flags                  off   8  size  2
  PyObject.ob_mutex                  off  10  size  1
  PyObject.ob_gc_bits                off  11  size  1
  PyObject.ob_ref_local              off  12  size  4
  PyObject.ob_ref_shared             off  16  size  8
  PyObject.ob_type                   off  24  size  8
  PyVarObject.ob_size                off  32  size  8
  PyLongObject.long_value.lv_tag     off  32  size  8
  PyLongObject.long_value.ob_digit   off  40  size  4
  PyFloatObject.ob_fval              off  32  size  8
  PyListObject.ob_item               off  40  size  8
  PyListObject.allocated             off  48  size  8
  PyTupleObject.ob_hash              off  40  size  8
  PyTupleObject.ob_item              off  48  size  8
  sizeof(PyObject)=32 sizeof(PyVarObject)=40 sizeof(PyListObject)=56 sizeof(PyFloatObject)=40
  one-digit int = 44 B requested -> 48 B block at 16-byte alignment
```

Every header grows by 16 B in the free-threaded build. A one-digit int goes from a 32 B to a **48 B** block, and a list header from 40 to 56 B plus its GC metadata. That is part of the "5–10 % single-thread penalty" the 3.14 What's New quotes. The other part is atomics on shared objects (01.2).

### 1.2 `PyLongObject`: arbitrary precision, 30 bits at a time

```text
PyLongObject (3.12+)                                 value = 1_000_000 (one 30-bit digit)
 off  0  ob_refcnt / overflow / flags      8 B
 off  8  ob_type -> &PyLong_Type           8 B
 off 16  lv_tag                            8 B   = ndigits << 3 | small_int << 2 | (1 - sign)
                                                 = 1 << 3 | 0 | 0 = 8
 off 24  ob_digit[0]  (uint32, 30 bits)    4 B   = 1_000_000
 off 28  padding to sizeof(PyLongObject)   4 B   -> 32 B allocation
```

`lv_tag` replaced `ob_size` in 3.12 (`Include/internal/pycore_long.h`). Bits 0–1 hold `1 − sign` (0 = positive, 1 = zero, 2 = negative), bit 2 marks the cached small ints, and bits 3+ are the digit count. A **compact** int (≤ 1 digit, |v| < 2³⁰) has the fast paths: `_PyLong_IsCompact`, `BINARY_OP_ADD_INT` specialization, and a Py_ssize_t accumulator in `sum()`.

**There are three different answers to "how big is an int?", and only one of them matches what you pay:**

1. `sys.getsizeof(10**6)` → **28**: `offsetof(PyLongObject, ob_digit) + 4`.
2. What CPython *requests* → **32**. `_PyLong_FromMedium()` (the path for `range()` items, arithmetic results and parsed one-digit ints) calls `PyObject_Malloc(sizeof(PyLongObject))`, and the struct is padded to 32. One-digit ints are also recycled through a freelist (`_Py_FREELIST_POP(PyLongObject, ints)` in `v3.14.10`). A two-digit sum produced by `x_add` allocates `size_a + 1` digits and never shrinks, so it requests 36 B.
3. What the process pays → **40.2 B per element** for an exact-size `list[int]`: 32 B block + 8 B pointer.

So the classic "10 M ints = 80 MB of pointers + 280 MB of 28-byte objects = 360 MB" is the *getsizeof* view. The measured bill is **≈ 402 MB**. Section 2 measures all three.

### 1.3 `PyListObject`: a header plus a separately allocated pointer array

```text
                PyGC_Head (16 B)    PyListObject (40 B)
               +-------+-------+  +--------+--------+---------+---------+-----------+
               |gc_next|gc_prev|  | refcnt | type   | ob_size | ob_item | allocated |
               +-------+-------+  +--------+--------+---------+----+----+-----------+
                                                                   |
                       PyMem_Malloc'd array (8 B x allocated)      v
                       +--------+--------+--------+-----+--------+---------+
                       | ptr[0] | ptr[1] | ptr[2] | ... | ptr[n-1] | spare...|
                       +---+----+---+----+---+----+-----+--------+---------+
                           v        v        v
                      PyLong(32B) PyLong   PyLong     <- each in some pymalloc pool, anywhere
```

Growth rule (`py_list_resize`): `new_allocated = (n + (n >> 3) + 6) & ~3`. That gives 0, 4, 8, 16, 24, 32, 40, 52, 64, 76, 92…, roughly 12.5 % headroom. `list(iterable_with_len)` and `[x] * n` size exactly; `append` loops over-allocate. Shrinking happens only when the size falls below half the capacity.

🧊 **Bridge.** This is `ArrayList<Long>` with pointer-sized elements (Python has no compressed oops), or `std::vector<T*>`. The *pointer array* is contiguous. The *objects* are only as contiguous as the allocator happened to place them, which is the subject of the shuffled-sum benchmark below.

### 1.4 pymalloc: arenas → pools → blocks

```text
 OS (VirtualAlloc / mmap)
   └── arena: 1 MiB (ARENA_BITS 20; 256 KiB without large arenas)        freed only when ALL its pools are empty
         └── pool: 16 KiB (POOL_BITS 14), ONE size class per pool        bookkeeping header + blocks
               └── blocks: 16, 32, 48, ... 512 B (ALIGNMENT 16 on 64-bit, SMALL_REQUEST_THRESHOLD 512)
 > 512 B  -> PyMem_RawMalloc -> the C runtime malloc (returned to the OS on free for large blocks)
```

Allocation within a size class is a pop off the pool's free list, nearly as cheap as a TLAB bump. **Freeing never moves anything.** Since 3.13 the default build can also run on mimalloc via `PYTHONMALLOC=mimalloc` (verified to start on 3.14.5); the free-threaded build *requires* mimalloc (01.2).

### 1.5 Where instance attributes live (3.13+): inline values, managed dicts, `__slots__`

A plain class instance in 3.14 carries **no dict at all** until something asks for one:

```text
           offset  -32  managed weakref slot    \  "pre-header" (Py_TPFLAGS_PREHEADER), 16 B
                   -24  managed dict slot (NULL) /
                   -16  PyGC_Head._gc_next      \  16 B
                    -8  PyGC_Head._gc_prev      /
 id(obj) ->          0  ob_refcnt/flags          \  PyObject, tp_basicsize = 16
                     8  ob_type                  /
                    16  _dictvalues {capacity, size, embedded, valid} + insertion-order bytes
                    ..  values[capacity]   <- the attribute VALUES; the NAMES live once per class
                                              in the shared keys (ht_cached_keys, PEP 412)
```

The flags (`Py_TPFLAGS_INLINE_VALUES | MANAGED_DICT | MANAGED_WEAKREF`), `__dictoffset__ = -1` and `__weakrefoffset__ = -32` in the measured output below are exactly this picture. `MANAGED_DICT_OFFSET` is `-3` words in the default build and `-1` word in the free-threaded build, which has no `PyGC_Head`. Three consequences matter, and all three are measured below:

* **Insertion order differing per instance is fine.** The values block carries its own order bytes, so key-sharing survives. The "always assign attributes in the same order" folklore is out of date.
* **Touching `obj.__dict__` or `vars(obj)` materializes a real dict**: +64 B per object, permanently.
* **More than `SHARED_KEYS_MAX_SIZE` = 30 distinct attribute names per class** exhausts the shared keys. Later instances get a private dict, and a 3-attribute record measures **320 B instead of 96 B**.

`__slots__` replaces all of that with a C struct:

```text
 -16 PyGC_Head (16)                      member_descriptor  Slotted.id  -> PyMemberDef{offset=16, type=Py_T_OBJECT_EX}
   0 PyObject header (16)                member_descriptor  Slotted.ts  -> PyMemberDef{offset=24}
  16 id  PyObject*  <----------------    member_descriptor  Slotted.v   -> PyMemberDef{offset=32}
  24 ts  PyObject*                       tp_basicsize = 16 + 3*8 = 40; no dict, no weakref slot
  32 v   PyObject*
```

🧊 That is a Java class layout: fixed offsets, decided once when the class is created, no per-instance hash table. **But the slots hold `PyObject*`.** The *values* are still boxed objects elsewhere on the heap. Slots fix the container; they do not unbox the payload. A slotted record of `(int, int, float)` is still ~150 B where a NumPy structured row is 24 B.

### 1.6 Two reclamation engines

**Refcounting** frees at the last `Py_DECREF`, deterministically and on the calling thread. `del big_list` therefore *is* a pause: it walks and frees every element. The trashcan mechanism (`Py_TRASHCAN_BEGIN`) turns deep recursive deallocation into a bounded-depth loop, so a million-deep nested list frees without a C stack overflow.

**The cycle collector** (`Python/gc.c`) handles only objects whose type has `Py_TPFLAGS_HAVE_GC` (lists, dicts, sets, instances, frames, functions…), each with a `PyGC_Head` linked into a generation list:

```text
for the generation(s) being collected:
  1. update_refs:     gc_refs := ob_refcnt                         (copy the true count)
  2. subtract_refs:   for every object, tp_traverse its referents; gc_refs(referent) -= 1
                      -> gc_refs > 0 now means "referenced from OUTSIDE this set"
  3. move_unreachable: everything reachable from a gc_refs > 0 object is alive; the rest is garbage
  4. finalize (PEP 442 tp_finalize, resurrection check), clear weakrefs + callbacks, tp_clear to break cycles
```

The cost is **linear in the number of tracked objects in the collected generations**: 44–47 ns per object here. Triggering and generation policy:

* Thresholds are `(2000, 10, 10)`. The young-generation counter advances on every **allocation** of a GC-type object (and drops on its deallocation), *not* on tracking. Generation 1 collects every 10 young collections and generation 2 every 10 of those, but a full collection also waits until `long_lived_pending > long_lived_total / 4` (`Python/gc.c`). That 25 % rule keeps total GC work linear while the heap grows.
* ⚠ **Version trap.** CPython 3.14.0–3.14.4 shipped an *incremental* collector with only two generations (young and old). **3.14.5 reverted to the 3.13 generational GC** after production reports of memory pressure (gh-142516), and 3.15 keeps the generational one. Your GC behaviour therefore changed in a *patch* release. Pin patch versions in performance-sensitive images.
* 3.14 decides tuple tracking at construction: a tuple is tracked only if some element's type is a GC type. Dicts are tracked from birth, even with only atomic values. Both are measured below.
* `gc.freeze()` (3.7+) moves every tracked object into a permanent generation that collections skip. It is the fork-server pattern for keeping pages shared: freeze in the parent, then fork.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Read the structs off a live interpreter

`id(obj)` is the object's address, so `ctypes` can overlay the headers from 1.1–1.3 on live objects and assert them. That covers refcount increments, immortality, `lv_tag` decoding, the list growth rule, the `ob_item` pointers and who pays for `PyGC_Head`.

```python
"""pyobject_anatomy.py - overlay the C structs on live CPython 3.14 objects and assert the layout.

CPython's id(obj) is the object's address, so ctypes can read a PyObject header in place.
Default (GIL) 64-bit build only; pyobject_layout.c prints the free-threaded header instead.
"""
import ctypes
import sys
import sysconfig

assert sys.maxsize == 2**63 - 1, "64-bit build required"
assert not sysconfig.get_config_var("Py_GIL_DISABLED"), "default (GIL) build required"


class PyObject(ctypes.Structure):             # Include/object.h, 64-bit little-endian, 3.14
    _fields_ = [("ob_refcnt", ctypes.c_uint32),   # low 32 bits of the 64-bit word
                ("ob_overflow", ctypes.c_uint16),
                ("ob_flags", ctypes.c_uint16),    # bits 48..63: immortal/static flags
                ("ob_type", ctypes.c_void_p)]


class PyVarObject(ctypes.Structure):
    _fields_ = [("ob_base", PyObject), ("ob_size", ctypes.c_ssize_t)]


class PyLongObject(ctypes.Structure):         # Include/cpython/longintrepr.h
    _fields_ = [("ob_base", PyObject), ("lv_tag", ctypes.c_uint64)]   # uint32 ob_digit[] follows


class PyFloatObject(ctypes.Structure):
    _fields_ = [("ob_base", PyObject), ("ob_fval", ctypes.c_double)]


class PyListObject(ctypes.Structure):         # Include/cpython/listobject.h
    _fields_ = [("ob_base", PyVarObject),
                ("ob_item", ctypes.POINTER(ctypes.c_void_p)),
                ("allocated", ctypes.c_ssize_t)]


class PyTupleObject(ctypes.Structure):        # Include/cpython/tupleobject.h (3.14 caches the hash)
    _fields_ = [("ob_base", PyVarObject), ("ob_hash", ctypes.c_ssize_t)]  # PyObject *ob_item[] follows


def view(cls, obj):
    return cls.from_address(id(obj))


GC_HEAD = 16   # PyGC_Head {_gc_next, _gc_prev} sits *before* every GC-tracked object

print("== A. struct sizes: ctypes overlay vs the interpreter's own tp_basicsize")
for name, cls, tp in [("PyObject", PyObject, object), ("PyFloatObject", PyFloatObject, float),
                      ("PyListObject", PyListObject, list), ("PyTupleObject(no items)", PyTupleObject, tuple)]:
    assert ctypes.sizeof(cls) == tp.__basicsize__, name
    print(f"  {name:24} {ctypes.sizeof(cls):3} B   == {tp.__name__}.__basicsize__")
assert int.__basicsize__ == ctypes.sizeof(PyLongObject) and int.__itemsize__ == 4
print(f"  {'PyLongObject(no digits)':24} {int.__basicsize__:3} B   + {int.__itemsize__} B per 30-bit digit")

print("== B. reference counting is a plain uint32 store in the default build")
o = object()
r0 = view(PyObject, o).ob_refcnt
alias1 = alias2 = o
r2 = view(PyObject, o).ob_refcnt
box = [o] * 1000
r1002 = view(PyObject, o).ob_refcnt
del alias1, alias2, box
assert (r2 - r0, r1002 - r0, view(PyObject, o).ob_refcnt) == (2, 1002, r0)
assert view(PyObject, o).ob_type == id(object)
print(f"  fresh object: ob_refcnt={r0}; +2 names -> {r2}; +[o]*1000 -> {r1002}; after del -> {r0}")
print(f"  ob_type == id(object): True; sys.getrefcount(o) = {sys.getrefcount(o)} (ob_refcnt + the argument)")

print("== C. immortal objects (PEP 683): refcount pinned, INCREF/DECREF become a compare + branch")
for label, x in [("None", None), ("True", True), ("small int 7", 7), ("()", ()), ("''", ""),
                 ("type int", int), ("intern('order_id')", sys.intern("order_id")),
                 ("fresh object()", object()), ("10**12", 10**12)]:
    h = view(PyObject, x)
    before = h.ob_refcnt
    names = [x] * 50
    after = h.ob_refcnt
    del names
    tag = "immortal" if sys._is_immortal(x) else "mortal  "
    print(f"  {label:20} ob_refcnt=0x{before:08X} ob_flags=0x{h.ob_flags:04X} {tag}"
          f" (+50 refs -> {'unchanged' if after == before else f'+{after - before}'})")
    assert (after == before) == sys._is_immortal(x)
assert view(PyObject, None).ob_refcnt == 3 << 30         # _Py_IMMORTAL_INITIAL_REFCNT
assert view(PyObject, None).ob_flags == 4 | 1            # _Py_STATICALLY_ALLOCATED_FLAG | _Py_IMMORTAL_FLAGS

print("== D. the small-int cache (_PY_NSMALLPOSINTS: 257 in 3.14, 1025 in 3.15)")
top = 1024 if sys.version_info >= (3, 15) else 256
cached = int(str(top)) is int(str(top))
fresh = int(str(top + 1)) is int(str(top + 1))
assert cached and not fresh
print(f"  int('{top}') is int('{top}') -> {cached};  int('{top + 1}') is int('{top + 1}') -> {fresh}")


def decode(n):
    """Rebuild n from lv_tag and the raw 30-bit digits."""
    tag = view(PyLongObject, n).lv_tag
    ndigits, sign, small = tag >> 3, tag & 3, (tag >> 2) & 1
    digits = (ctypes.c_uint32 * max(ndigits, 1)).from_address(id(n) + ctypes.sizeof(PyLongObject))
    mag = sum(digits[i] << (30 * i) for i in range(ndigits))
    value = {0: mag, 1: 0, 2: -mag}[sign]   # sign field = 1 - sign(n)
    assert value == n
    assert sys.getsizeof(n) == int.__basicsize__ + 4 * max(ndigits, 1)
    return tag, ndigits, sign, small


print("== E. PyLongObject: lv_tag = ndigits << 3 | small_int_bit << 2 | (1 - sign)")
print(f"  {'value':>24} {'lv_tag':>8} digits sign small getsizeof")
for expr in ["0", "1", "-1", "1000", "2**30 - 1", "2**30", "2**60", "-(2**90)", "10**100"]:
    n = int(str(eval(expr)))             # build at run time (no constant folding)
    tag, nd, sign, small = decode(n)
    print(f"  {expr:>24} {tag:8} {nd:6} {sign:4} {small:5} {sys.getsizeof(n):6} B")

print("== F. PyListObject: a header plus a separately malloc'd array of PyObject* (ob_item)")


def grow(allocated, size, newsize):      # py_list_resize() growth rule, Objects/listobject.c
    if allocated >= newsize and newsize >= (allocated >> 1):
        return allocated
    new = (newsize + (newsize >> 3) + 6) & ~3
    if newsize - size > new - newsize:
        new = (newsize + 3) & ~3
    return new


L, model, seen = [], 0, []
for i in range(80):
    model = grow(model, len(L), len(L) + 1)
    L.append(i)
    real = view(PyListObject, L).allocated
    assert real == model, (i, real, model)
    if not seen or seen[-1] != real:
        seen.append(real)
print(f"  allocated after appends: {seen}  (matches the C growth rule)")
assert sys.getsizeof(L) == list.__basicsize__ + GC_HEAD + 8 * view(PyListObject, L).allocated
items = [int(str(10**9 + i)) for i in range(5)]
arr = view(PyListObject, items).ob_item
assert all(arr[i] == id(items[i]) for i in range(5))
print(f"  ob_item[i] == id(items[i]) for all i: True; sizeof(list of {len(L)}) = {sys.getsizeof(L)} B"
      f" = {list.__basicsize__} header + {GC_HEAD} GC head + 8 x {view(PyListObject, L).allocated} slots")

print("== G. who pays the 16-byte PyGC_Head (containers only)")
for label, x, payload in [("int 10**12", 10**12, 2 * 4), ("float 1.5", 1.5, 0), ("tuple of 3", (1, 2, 3), 3 * 8),
                          ("list of 0", [], 0), ("object()", object(), 0)]:
    tp = type(x)
    extra = sys.getsizeof(x) - tp.__basicsize__ - payload     # payload = digits / inline items
    gc_tracked_type = bool(tp.__flags__ & (1 << 14))     # Py_TPFLAGS_HAVE_GC
    print(f"  {label:12} getsizeof={sys.getsizeof(x):3}  basicsize={tp.__basicsize__:3}  "
          f"HAVE_GC={gc_tracked_type!s:5}  extra={extra}")
    if tp in (tuple, list):
        assert extra == GC_HEAD and gc_tracked_type
    if tp in (int, float, object):
        assert extra == 0 and not gc_tracked_type
print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
== A. struct sizes: ctypes overlay vs the interpreter's own tp_basicsize
  PyObject                  16 B   == object.__basicsize__
  PyFloatObject             24 B   == float.__basicsize__
  PyListObject              40 B   == list.__basicsize__
  PyTupleObject(no items)   32 B   == tuple.__basicsize__
  PyLongObject(no digits)   24 B   + 4 B per 30-bit digit
== B. reference counting is a plain uint32 store in the default build
  fresh object: ob_refcnt=1; +2 names -> 3; +[o]*1000 -> 1003; after del -> 1
  ob_type == id(object): True; sys.getrefcount(o) = 2 (ob_refcnt + the argument)
== C. immortal objects (PEP 683): refcount pinned, INCREF/DECREF become a compare + branch
  None                 ob_refcnt=0xC0000000 ob_flags=0x0005 immortal (+50 refs -> unchanged)
  True                 ob_refcnt=0xC0000000 ob_flags=0x0005 immortal (+50 refs -> unchanged)
  small int 7          ob_refcnt=0xC0000000 ob_flags=0x0005 immortal (+50 refs -> unchanged)
  ()                   ob_refcnt=0xC0000000 ob_flags=0x0005 immortal (+50 refs -> unchanged)
  ''                   ob_refcnt=0xC0000000 ob_flags=0x0005 immortal (+50 refs -> unchanged)
  type int             ob_refcnt=0xC0000000 ob_flags=0x0005 immortal (+50 refs -> unchanged)
  intern('order_id')   ob_refcnt=0x00000004 ob_flags=0x0000 mortal   (+50 refs -> +50)
  fresh object()       ob_refcnt=0x00000002 ob_flags=0x0000 mortal   (+50 refs -> +50)
  10**12               ob_refcnt=0x00000003 ob_flags=0x0000 mortal   (+50 refs -> +50)
== D. the small-int cache (_PY_NSMALLPOSINTS: 257 in 3.14, 1025 in 3.15)
  int('256') is int('256') -> True;  int('257') is int('257') -> False
== E. PyLongObject: lv_tag = ndigits << 3 | small_int_bit << 2 | (1 - sign)
                     value   lv_tag digits sign small getsizeof
                         0        5      0    1     1     28 B
                         1       12      1    0     1     28 B
                        -1       14      1    2     1     28 B
                      1000        8      1    0     0     28 B
                 2**30 - 1        8      1    0     0     28 B
                     2**30       16      2    0     0     32 B
                     2**60       24      3    0     0     36 B
                  -(2**90)       34      4    2     0     40 B
                   10**100       96     12    0     0     72 B
== F. PyListObject: a header plus a separately malloc'd array of PyObject* (ob_item)
  allocated after appends: [4, 8, 16, 24, 32, 40, 52, 64, 76, 92]  (matches the C growth rule)
  ob_item[i] == id(items[i]) for all i: True; sizeof(list of 80) = 792 B = 40 header + 16 GC head + 8 x 92 slots
== G. who pays the 16-byte PyGC_Head (containers only)
  int 10**12   getsizeof= 32  basicsize= 24  HAVE_GC=False  extra=0
  float 1.5    getsizeof= 24  basicsize= 24  HAVE_GC=False  extra=0
  tuple of 3   getsizeof= 72  basicsize= 32  HAVE_GC=True   extra=16
  list of 0    getsizeof= 56  basicsize= 40  HAVE_GC=True   extra=16
  object()     getsizeof= 16  basicsize= 16  HAVE_GC=False  extra=0
ALL ASSERTIONS PASSED
```

What to take from it:

* `None`, `True`, `7`, `()`, `''` and `int` all read `0xC0000000` (= `3 << 30`) with flags `0x0005`. Fifty new references change nothing. The cost of `Py_INCREF` on them is one load, one compare and a not-taken branch.
* **A runtime-interned string is mortal in 3.14** (`sys.intern('order_id')` reads refcount 4 and grows by 50). Immortality belongs to *statically allocated* strings, so don't assume an interned key's cache line stays clean.
* `10**100` is 12 digits = 24 + 48 = 72 B; 30 bits per digit, as `PyLong_SHIFT` says.

### 2.2 Trap: `list[int]` for numeric data — 10 M values, three containers, three scans

The trap is reaching for `ids = [row.id for row in rows]` and then `sum(ids)`, `sorted(ids)`, `set(ids)`, and multiplying it by every worker. The L7 pattern is one contiguous `int64` buffer that every consumer reads without boxing.

```python
"""int_storage_math.py - 10M integers as list[int] vs array('q') vs np.int64: bytes requested, bytes paid, scan speed.

"getsizeof" is what sys.getsizeof reports; "paid" is the measured growth of the process's private bytes.
A one-digit int reports 28 B but is allocated as sizeof(PyLongObject) = 32 B (struct padding), which tracemalloc shows.
"""
import array
import gc
import random
import sys
import time
import tracemalloc

import numpy as np
import psutil

N = 10_000_000
BASE = 10**6                      # above the small-int cache, so every element is a real heap object
MB = 1e6
proc = psutil.Process()


def private():
    gc.collect()
    m = proc.memory_info()
    return getattr(m, "private", m.rss)          # Windows: private commit; elsewhere RSS


def best(fn, reps=3):
    t = []
    for _ in range(reps):
        t0 = time.perf_counter()
        r = fn()
        t.append(time.perf_counter() - t0)
    return min(t), r


expect = N * BASE + N * (N - 1) // 2
print(f"N = {N:,} int64 values starting at {BASE:,}")
print(f"{'container':32} {'getsizeof':>11} {'paid (RSS)':>11} {'B/elem':>7}")

m0 = private()
lst = list(range(BASE, BASE + N))                 # exact-size: list() uses the length hint
m1 = private()
req = sys.getsizeof(lst) + sum(map(sys.getsizeof, lst))
print(f"{'list(range(..)) exact':32} {req / MB:9.1f}MB {(m1 - m0) / MB:9.1f}MB {(m1 - m0) / N:7.1f}")
paid_list = m1 - m0

tracemalloc.start()
sample = [x + 1 for x in lst[:1_000_000]]         # 1M fresh one-digit ints
traced, _ = tracemalloc.get_traced_memory()
tracemalloc.stop()
print(f"  tracemalloc, 1M fresh ints: {(traced - sys.getsizeof(sample)) / 1e6:.1f} B/int requested from pymalloc "
      f"(getsizeof says {sys.getsizeof(sample[0])})")
del sample
ids = [id(x) for x in lst[:1_000_001]]
steps = [b - a for a, b in zip(ids, ids[1:])]
same_pool = sum(1 for d in steps if d == 32) / len(steps)
print(f"  creation order: {same_pool:.1%} of neighbours are exactly 32 B apart (one pymalloc size class)")

t_seq, s = best(lambda: sum(lst))
assert s == expect
random.seed(7)
shuffled = lst[:]                                  # same objects, pointer array permuted
random.shuffle(shuffled)
t_shuf, s = best(lambda: sum(shuffled))
assert s == expect
del shuffled, ids, steps

grow = []
m2 = private()
for x in lst:
    grow.append(x)                                # same objects, append-grown pointer array
m3 = private()
print(f"{'  + append-grown list (ptrs only)':32} {sys.getsizeof(grow) / MB:9.1f}MB {(m3 - m2) / MB:9.1f}MB "
      f"{(m3 - m2) / N:7.1f}")
del grow, lst

m4 = private()
arr = array.array("q", range(BASE, BASE + N))
m5 = private()
print(f"{'array.array(\"q\")':32} {sys.getsizeof(arr) / MB:9.1f}MB {(m5 - m4) / MB:9.1f}MB {(m5 - m4) / N:7.1f}")
t_arr, s = best(lambda: sum(arr))                 # boxes every element on the way out
assert s == expect
del arr

m6 = private()
nd = np.arange(BASE, BASE + N, dtype=np.int64)
m7 = private()
print(f"{'np.arange(int64)':32} {nd.nbytes / MB:9.1f}MB {(m7 - m6) / MB:9.1f}MB {(m7 - m6) / N:7.1f}")
t_np, s = best(lambda: int(nd.sum()))
assert s == expect

print()
print(f"{'scan (sum of all 10M)':40} {'ms':>8} {'vs numpy':>9}")
for label, t in [("sum(list) - creation order", t_seq), ("sum(list) - shuffled pointer order", t_shuf),
                 ("sum(array('q')) - boxes each element", t_arr), ("np.int64.sum() - SIMD over 80 MB", t_np)]:
    print(f"{label:40} {t * 1e3:8.1f} {t / t_np:8.1f}x")
assert paid_list > 0.95 * N * (8 + 32), "expected ~40 B/element for an exact-size list of ints"
print("ALL ASSERTIONS PASSED")
```

Output (one measured run — Windows private bytes; timings vary ±10 %):

```text
N = 10,000,000 int64 values starting at 1,000,000
container                          getsizeof  paid (RSS)  B/elem
list(range(..)) exact                360.0MB     401.7MB    40.2
  tracemalloc, 1M fresh ints: 32.0 B/int requested from pymalloc (getsizeof says 28)
  creation order: 99.8% of neighbours are exactly 32 B apart (one pymalloc size class)
  + append-grown list (ptrs only)      89.1MB      89.3MB     8.9
array.array("q")                      81.9MB      90.2MB     9.0
np.arange(int64)                      80.0MB      80.2MB     8.0

scan (sum of all 10M)                          ms  vs numpy
sum(list) - creation order                   37.4      7.9x
sum(list) - shuffled pointer order          258.6     54.5x
sum(array('q')) - boxes each element        101.9     21.5x
np.int64.sum() - SIMD over 80 MB              4.7      1.0x
ALL ASSERTIONS PASSED
```

Read it like a capacity planner:

* **getsizeof 360 MB, paid ≈ 402 MB.** The 4 B per int that `getsizeof` hides is padding inside `sizeof(PyLongObject)`, and it is ~10 % of the bill.
* **99.8 % of consecutive ints sit exactly 32 B apart.** Freshly allocated objects are *dense* in creation order, which is why `sum(list)` in creation order (≈ 38 ms) is "only" 8× slower than NumPy. **Shuffle the pointer array** (the same objects, visited in random order, which is what you get after a sort by another key, a `set()` or a hash join) and the scan becomes **≈ 7× slower again, ≈ 54× NumPy**. That gap is pure cache and TLB misses: every element is a dependent load to a random 32 B block.
* `sum(array('q'))` is *slower* than `sum(list)`. The storage is 8 B per element, but every element read creates a temporary `PyLong`. Compact storage alone does not help if the computation is still per-element Python. You need compact storage **and** a vectorized kernel (`np.sum`: 4.7 ms over 80 MB ≈ 17 GB/s, at the memory-bandwidth roof of this laptop).

### 2.3 Trap: "it's just a small record class" — bytes per record, nine ways

```python
"""slots_layout.py - per-instance bytes of a 3-field record across 9 representations, and where __slots__ live.

Reads each slot's PyMemberDef.offset through ctypes (the C field-offset table, like a JVM field layout),
then measures bytes per record with tracemalloc (requested) and private-bytes growth (paid).
"""
import ctypes
import gc
import sys
import time
import tracemalloc
from collections import namedtuple
from dataclasses import dataclass

import numpy as np
import psutil

N = 500_000
proc = psutil.Process()


class Plain:
    def __init__(self, id, ts, v):
        self.id = id
        self.ts = ts
        self.v = v


class Slotted:
    __slots__ = ("id", "ts", "v")

    def __init__(self, id, ts, v):
        self.id = id
        self.ts = ts
        self.v = v


@dataclass(slots=True)
class DC:
    id: int
    ts: int
    v: float


NT = namedtuple("NT", "id ts v")


class PlainShuffled(Plain):          # same three attributes, insertion order varies per instance
    def __init__(self, id, ts, v, k):
        for name in (("id", "ts", "v"), ("v", "id", "ts"), ("ts", "v", "id"))[k % 3]:
            setattr(self, name, {"id": id, "ts": ts, "v": v}[name])


class PlainDynamic:                   # third attribute name drawn from 40 names: > SHARED_KEYS_MAX_SIZE (30)
    def __init__(self, id, ts, v, k):
        self.id = id
        self.ts = ts
        setattr(self, f"v{k % 40}", v)


class PyMemberDef(ctypes.Structure):
    _fields_ = [("name", ctypes.c_char_p), ("type", ctypes.c_int), ("offset", ctypes.c_ssize_t),
                ("flags", ctypes.c_int), ("doc", ctypes.c_char_p)]


def member_offset(descr):
    """PyMemberDescrObject: PyObject_HEAD(16) + d_type + d_name + d_qualname, then PyMemberDef *d_member."""
    p = ctypes.c_void_p.from_address(id(descr) + 16 + 3 * 8).value
    return PyMemberDef.from_address(p).offset


print("== A. type layout metadata (tp_basicsize, flags) - 3.14 default build")
FLAGS = {"INLINE_VALUES": 1 << 2, "MANAGED_WEAKREF": 1 << 3, "MANAGED_DICT": 1 << 4, "HAVE_GC": 1 << 14}
for cls in (Plain, Slotted, DC, NT):
    f = [k for k, bit in FLAGS.items() if cls.__flags__ & bit]
    print(f"  {cls.__name__:8} basicsize={cls.__basicsize__:3}  dictoffset={cls.__dictoffset__:3}  "
          f"weakrefoffset={cls.__weakrefoffset__:3}  flags={'|'.join(f)}")
offs = {name: member_offset(Slotted.__dict__[name]) for name in Slotted.__slots__}
print(f"  Slotted member descriptors -> C offsets {offs}  (type(Slotted.id) = {type(Slotted.id).__name__})")
assert list(offs.values()) == [16, 24, 32] and Slotted.__basicsize__ == 16 + 3 * 8


def measure(make, label, boxed):
    gc.collect()
    tracemalloc.start()
    p0 = proc.memory_info().private
    objs = make(boxed)
    req, _ = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    gc.collect()
    paid = proc.memory_info().private - p0
    holder = 8 * N                                   # the list holding the records is not "the record"
    print(f"  {label:34} requested {(req - holder) / N:6.1f} B   paid {(paid - holder) / N:6.1f} B")
    return objs


def fields(i, boxed):
    if boxed:                                        # realistic: every field is its own heap object
        return 10**9 + i, 1_700_000_000_000 + i, i * 0.5
    return 1, 2, None                                # cached immortals: isolates the container itself


def tuple_of(a, b, c):
    return (a, b, c)                                 # BUILD_TUPLE: a new object (no constant folding)


def materialize(boxed):
    objs = [Plain(*fields(i, boxed)) for i in range(N)]
    for o in objs:
        o.__dict__                                   # any vars(o)/o.__dict__ access builds a real dict
    return objs


makers = [
    ("class (inline values, 3.13+)", lambda b: [Plain(*fields(i, b)) for i in range(N)]),
    ("class after o.__dict__ touched", materialize),
    ("class, attr order varies", lambda b: [PlainShuffled(*fields(i, b), i) for i in range(N)]),
    ("class, 40 distinct attr names", lambda b: [PlainDynamic(*fields(i, b), i) for i in range(N)]),
    ("__slots__ class", lambda b: [Slotted(*fields(i, b)) for i in range(N)]),
    ("@dataclass(slots=True)", lambda b: [DC(*fields(i, b)) for i in range(N)]),
    ("namedtuple", lambda b: [NT(*fields(i, b)) for i in range(N)]),
    ("tuple", lambda b: [tuple_of(*fields(i, b)) for i in range(N)]),
    ("dict per record", lambda b: [dict(zip(("id", "ts", "v"), fields(i, b))) for i in range(N)]),
]
results = {}
for boxed in (False, True):
    print(f"== B{'2' if boxed else '1'}. {N:,} records, fields = "
          f"{'fresh int, int, float (boxed)' if boxed else 'shared immortals (container cost only)'}")
    for label, mk in makers:
        objs = measure(mk, label, boxed)
        if not boxed:
            results[label] = objs[0]
        del objs
    if boxed:
        dt = np.dtype([("id", "i8"), ("ts", "i8"), ("v", "f8")])
        rec = np.zeros(N, dtype=dt)
        print(f"  {'numpy structured array (columnar)':34} requested {rec.nbytes / N:6.1f} B   (no per-row object)")

print("== C. attribute read cost: o.v in a 2M-iteration loop (specialized LOAD_ATTR variants)")


def bench(o, reps=2_000_000):
    t0 = time.perf_counter()
    for _ in range(reps):
        o.v
    return (time.perf_counter() - t0) / reps * 1e9


d = {"v": 1.0}
for label, o in [("class (inline values)", Plain(1, 2, 3.0)), ("__slots__", Slotted(1, 2, 3.0)),
                 ("namedtuple (property->itemgetter)", NT(1, 2, 3.0))]:
    bench(o, 50_000)
    print(f"  {label:34} {min(bench(o) for _ in range(3)):5.1f} ns/read")
t0 = time.perf_counter()
for _ in range(2_000_000):
    d["v"]
print(f"  {'dict[\"v\"]':34} {(time.perf_counter() - t0) / 2e6 * 1e9:5.1f} ns/read")
assert not hasattr(Slotted(1, 2, 3), "__dict__")
try:
    Slotted(1, 2, 3).extra = 1
    raise SystemExit("slots should reject new attributes")
except AttributeError:
    print("  Slotted(...).extra = 1 -> AttributeError (fixed layout, like a Java class)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run — tracemalloc "requested" is deterministic, "paid" varies ±5 %):

```text
== A. type layout metadata (tp_basicsize, flags) - 3.14 default build
  Plain    basicsize= 16  dictoffset= -1  weakrefoffset=-32  flags=INLINE_VALUES|MANAGED_WEAKREF|MANAGED_DICT|HAVE_GC
  Slotted  basicsize= 40  dictoffset=  0  weakrefoffset=  0  flags=HAVE_GC
  DC       basicsize= 40  dictoffset=  0  weakrefoffset=  0  flags=HAVE_GC
  NT       basicsize= 32  dictoffset=  0  weakrefoffset=  0  flags=HAVE_GC
  Slotted member descriptors -> C offsets {'id': 16, 'ts': 24, 'v': 32}  (type(Slotted.id) = member_descriptor)
== B1. 500,000 records, fields = shared immortals (container cost only)
  class (inline values, 3.13+)       requested   96.3 B   paid   98.4 B
  class after o.__dict__ touched     requested  160.3 B   paid  159.5 B
  class, attr order varies           requested   96.3 B   paid   96.5 B
  class, 40 distinct attr names      requested  319.9 B   paid  332.9 B
  __slots__ class                    requested   56.3 B   paid   68.7 B
  @dataclass(slots=True)             requested   56.3 B   paid   58.9 B
  namedtuple                         requested   80.3 B   paid   82.1 B
  tuple                              requested   72.3 B   paid   76.4 B
  dict per record                    requested  184.3 B   paid  192.2 B
== B2. 500,000 records, fields = fresh int, int, float (boxed)
  class (inline values, 3.13+)       requested  188.3 B   paid  211.9 B
  class after o.__dict__ touched     requested  252.3 B   paid  267.3 B
  class, attr order varies           requested  188.3 B   paid  205.5 B
  class, 40 distinct attr names      requested  411.8 B   paid  440.0 B
  __slots__ class                    requested  148.3 B   paid  165.0 B
  @dataclass(slots=True)             requested  148.3 B   paid  168.8 B
  namedtuple                         requested  172.3 B   paid  178.9 B
  tuple                              requested  164.3 B   paid  175.4 B
  dict per record                    requested  276.3 B   paid  289.3 B
  numpy structured array (columnar)  requested   24.0 B   (no per-row object)
== C. attribute read cost: o.v in a 2M-iteration loop (specialized LOAD_ATTR variants)
  class (inline values)               16.6 ns/read
  __slots__                           15.8 ns/read
  namedtuple (property->itemgetter)   25.4 ns/read
  dict["v"]                           53.7 ns/read
  Slotted(...).extra = 1 -> AttributeError (fixed layout, like a Java class)
ALL ASSERTIONS PASSED
```

The decision table that falls out of it (3.14, per record of three fields):

| Representation | Container only | With boxed `int,int,float` | Notes |
|---|---:|---:|---|
| plain class (inline values) | 96 B | 188 B | default; fine for ≤ 30 attribute names per class |
| …after `o.__dict__` is touched | 160 B | 252 B | serializers, `vars()`, `copy`, debuggers do this |
| …40 distinct names on one class | **320 B** | 412 B | dynamic `setattr(self, f"x{k}")` → private dicts |
| `__slots__` / `dataclass(slots=True)` | **56 B** | 148 B | GC head + header + 3 pointers |
| `namedtuple` | 80 B | 172 B | tuple subclass: `PyType_GenericAlloc` adds one sentinel item |
| `tuple` | 72 B | 164 B | 3.14 tuples carry a cached hash (+8 B) |
| `dict` per record | 184 B | 276 B | the JSON-shaped default — the worst |
| NumPy structured / columnar | — | **24 B** | no per-row object at all |

The attribute read cost is the same for plain and slotted classes (≈ 16–18 ns; both specialize, 01.4), so `__slots__` is a **memory** decision, not a speed one. A `dict["v"]` read is ≈ 3× slower than either.

### 2.4 Refcounting vs. the cycle collector, measured

```python
"""refcount_gc_physics.py - when CPython frees memory: refcount (immediate), cycle GC (generational), and their pauses.

Measures: deterministic frees vs cycles, which allocations advance the GC counter, full-collection pause vs heap
size, gc.freeze(), automatic-collection overhead while building a large heap, and the cost of `del big_list`.
"""
import gc
import sys
import time
import weakref

assert gc.isenabled()
print(f"Python {sys.version.split()[0]}  gc.get_threshold() = {gc.get_threshold()}")

print("== A. refcounting frees at the last DECREF; cycles wait for the collector")
freed = []


class Node:
    pass


a = Node()
weakref.finalize(a, freed.append, "acyclic")
del a
print(f"  acyclic object: finalizer ran at `del`        -> {freed}")
assert freed == ["acyclic"]
x, y = Node(), Node()
x.peer, y.peer = y, x
weakref.finalize(x, freed.append, "cycle")
del x, y
after_del = list(freed)
found = gc.collect()
print(f"  2-node cycle: after `del` {after_del[1:]}; after gc.collect() -> {freed[1:]} (collect found {found})")
assert after_del == ["acyclic"] and freed == ["acyclic", "cycle"]

print("== B. only container (GC-tracked) allocations advance generation-0's counter")
gc.collect()
gc.disable()


def delta(make):
    c0 = gc.get_count()[0]
    keep = [make() for _ in range(1000)]
    return gc.get_count()[0] - c0 - 1, keep        # -1: the list `keep` itself


for label, make in [("1000 floats", lambda: float(time.perf_counter())), ("1000 big ints", lambda: 10**30 + 1),
                    ("1000 str", lambda: str(time.perf_counter())), ("1000 tuples (x, y)", lambda: (object(), 1)),
                    ("1000 empty lists", list), ("1000 dicts", dict), ("1000 Node()", Node)]:
    d, keep = delta(make)
    print(f"  {label:20} gen0 count += {d}")
gc.enable()
atoms = (int("1"), 2.0, "s")                         # built at run time, elements are not GC types
holder = (int("1"), [])                               # one element is a GC-tracked list
print(f"  3.14 decides tuple tracking at construction: (int, float, str) tracked={gc.is_tracked(atoms)}, "
      f"(int, list) tracked={gc.is_tracked(holder)}; dict {{'a': 1}} tracked={gc.is_tracked({'a': 1})}")
print("  ...yet every tuple allocation above still advanced the counter: allocation, not tracking, drives gen0")
assert not gc.is_tracked(atoms) and gc.is_tracked(holder)


def build(n):
    """n containers in a shallow tree: every object is GC-tracked and reachable."""
    root, cur = [], []
    for i in range(n):
        if i % 1000 == 0:
            cur = []
            root.append(cur)
        cur.append({"i": i, "child": [None]})        # 1 dict + 1 list per item, mutable -> stays tracked
    return root


print("== C. a full collection traverses every tracked object: pause ~ heap size")
for n in (250_000, 500_000, 1_000_000):
    heap = build(n)
    gc.collect()
    t0 = time.perf_counter()
    gc.collect()
    pause = time.perf_counter() - t0
    tracked = len(gc.get_objects())
    print(f"  {n:>9,} items -> {tracked:>9,} tracked objects   gc.collect() = {pause * 1e3:6.1f} ms"
          f"   ({pause / tracked * 1e9:5.1f} ns/object)")
    if n == 1_000_000:
        gc.freeze()                                    # move everything to the permanent generation
        t0 = time.perf_counter()
        gc.collect()
        frozen_pause = time.perf_counter() - t0
        print(f"  after gc.freeze() ({gc.get_freeze_count():,} frozen): gc.collect() = {frozen_pause * 1e3:6.1f} ms")
        gc.unfreeze()
        assert frozen_pause < pause / 5
    del heap
gc.collect()

print("== D. automatic collections while building a 1M-item live heap")
stats = {"n": [0, 0, 0], "t": 0.0}
t_start = [0.0]


def cb(phase, info):
    if phase == "start":
        t_start[0] = time.perf_counter()
    else:
        stats["n"][info["generation"]] += 1
        stats["t"] += time.perf_counter() - t_start[0]


gc.callbacks.append(cb)
for label, setup in [("default (2000, 10, 10)", lambda: gc.set_threshold(2000, 10, 10)),
                     ("threshold0 = 100_000", lambda: gc.set_threshold(100_000, 10, 10)),
                     ("gc.disable(), then enable", gc.disable)]:
    gc.collect()
    stats["n"], stats["t"] = [0, 0, 0], 0.0
    setup()
    t0 = time.perf_counter()
    heap = build(1_000_000)
    wall = time.perf_counter() - t0
    gc.enable()
    gc.set_threshold(2000, 10, 10)
    print(f"  {label:26} build {wall * 1e3:7.1f} ms   collections gen0/1/2 = {stats['n']}"
          f"   time in GC {stats['t'] * 1e3:6.1f} ms")
    del heap
gc.callbacks.remove(cb)
gc.collect()

print("== E. refcounting has pauses too: `del` of a big structure frees it synchronously")
for n in (1_000_000, 5_000_000):
    big = [str(i) for i in range(n)]
    t0 = time.perf_counter()
    del big
    print(f"  del list of {n:>9,} str -> {(time.perf_counter() - t0) * 1e3:6.1f} ms on the calling thread")
deep = []
for _ in range(1_000_000):
    deep = [deep]                                      # 1M-deep nesting
t0 = time.perf_counter()
del deep                                               # the trashcan mechanism bounds C-stack depth
print(f"  del of a 1,000,000-deep nested list: {(time.perf_counter() - t0) * 1e3:.1f} ms, no stack overflow")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
Python 3.14.5  gc.get_threshold() = (2000, 10, 10)
== A. refcounting frees at the last DECREF; cycles wait for the collector
  acyclic object: finalizer ran at `del`        -> ['acyclic']
  2-node cycle: after `del` []; after gc.collect() -> ['cycle'] (collect found 3)
== B. only container (GC-tracked) allocations advance generation-0's counter
  1000 floats          gen0 count += 1
  1000 big ints        gen0 count += 0
  1000 str             gen0 count += -1
  1000 tuples (x, y)   gen0 count += 998
  1000 empty lists     gen0 count += 999
  1000 dicts           gen0 count += 999
  1000 Node()          gen0 count += 999
  3.14 decides tuple tracking at construction: (int, float, str) tracked=False, (int, list) tracked=True; dict {'a': 1} tracked=True
  ...yet every tuple allocation above still advanced the counter: allocation, not tracking, drives gen0
== C. a full collection traverses every tracked object: pause ~ heap size
    250,000 items ->   507,080 tracked objects   gc.collect() =   22.4 ms   ( 44.2 ns/object)
    500,000 items -> 1,007,330 tracked objects   gc.collect() =   45.2 ms   ( 44.8 ns/object)
  1,000,000 items -> 2,007,830 tracked objects   gc.collect() =   94.2 ms   ( 46.9 ns/object)
  after gc.freeze() (2,007,830 frozen): gc.collect() =    0.0 ms
== D. automatic collections while building a 1M-item live heap
  default (2000, 10, 10)     build   556.9 ms   collections gen0/1/2 = [911, 82, 6]   time in GC  359.0 ms
  threshold0 = 100_000       build   342.9 ms   collections gen0/1/2 = [19, 1, 0]   time in GC  146.9 ms
  gc.disable(), then enable  build   195.9 ms   collections gen0/1/2 = [1, 0, 0]   time in GC   84.4 ms
== E. refcounting has pauses too: `del` of a big structure frees it synchronously
  del list of 1,000,000 str ->   10.9 ms on the calling thread
  del list of 5,000,000 str ->   68.6 ms on the calling thread
  del of a 1,000,000-deep nested list: 35.8 ms, no stack overflow
ALL ASSERTIONS PASSED
```

* Building a 1 M-item live heap with default thresholds spent **≈ 360 ms of ≈ 557 ms inside the collector**: 911 young, 82 middle and 6 full collections, each one rescanning survivors that will never die. Raising `threshold0` to 100 000 cut the GC time to ≈ 147 ms. Disabling the collector moved the bill: the first young collection after `gc.enable()` scanned all ~2 M young objects (≈ 84 ms) in one go.
* A full collection costs ~44–47 ns per tracked object, linear in the heap. On a 20 M-object service that is a ~1 s stop-the-world pause on whichever request triggers it.
* `gc.freeze()` makes the same collection cost ~0 ms. It is the right tool *after* warm-up, for a long-lived immutable heap (model metadata, vocabularies, config). It is not the right tool for transient garbage.
* `del` of 5 M strings is 50–70 ms (across runs) of synchronous freeing on the calling thread: refcounting has pauses too, just deterministic ones.

### 2.5 "I freed 90 % of my objects; why didn't RSS drop?"

```python
"""arena_fragmentation.py - why "I deleted 90% of my objects" does not shrink the process (pymalloc arenas).

pymalloc carves 1 MiB arenas into 16 KiB pools of one size class; an arena goes back to the OS only when every
pool in it is empty. One survivor per pool pins the whole arena. Large buffers (numpy) bypass pymalloc entirely.
"""
import gc
import os
import re
import sys
import tempfile

import numpy as np
import psutil

proc = psutil.Process()
N = 8_000_000


def private_mb():
    gc.collect()
    m = proc.memory_info()
    return getattr(m, "private", m.rss) / 1e6


def arenas():
    """Parse 'arenas allocated current' from sys._debugmallocstats(), which writes to the C-level stderr."""
    sys.stderr.flush()
    fd = os.dup(2)
    with tempfile.TemporaryFile() as tmp:
        os.dup2(tmp.fileno(), 2)
        try:
            sys._debugmallocstats()
        finally:
            os.dup2(fd, 2)
            os.close(fd)
        tmp.seek(0)
        text = tmp.read().decode()
    return int(re.search(r"# arenas allocated current\s*=\s*([\d,]+)", text).group(1).replace(",", ""))


BASE = [0.0]


def show(label):
    now = private_mb()
    if label == "baseline":
        BASE[0] = now                      # imports (numpy/OpenBLAS buffers) are already committed here
    print(f"  {label:46} private = baseline {now - BASE[0]:+8.1f} MB   pymalloc arenas = {arenas():5}")


print(f"== {N:,} one-digit ints (32 B blocks -> 512 per 16 KiB pool, 64 pools per 1 MiB arena)")
show("baseline")
xs = [10**9 + i for i in range(N)]
show("allocated 8M ints")
survivors = xs[::10]                       # keep 1 in 10: every pool keeps ~51 live blocks
del xs
show("freed 90% (every 10th survives)")
assert len(survivors) == N // 10
compacted = [s + 0 for s in survivors]     # new objects, allocated densely into recycled pools
del survivors
show("re-allocated the 10% densely, freed originals")
del compacted
show("freed everything")

print("== the same 8M values as one numpy buffer (64 MB, malloc'd outside pymalloc)")
arr = np.arange(10**9, 10**9 + N, dtype=np.int64)
show("np.int64 array allocated")
keep = arr[::10].copy()                    # a slice VIEW would pin the whole parent buffer; copy() does not
del arr
show("kept 10% via .copy(), freed the parent")
del keep
show("freed everything")
print("ALL STEPS DONE")
```

Output (one measured run):

```text
== 8,000,000 one-digit ints (32 B blocks -> 512 per 16 KiB pool, 64 pools per 1 MiB arena)
  baseline                                       private = baseline     +0.0 MB   pymalloc arenas =     9
  allocated 8M ints                              private = baseline   +328.9 MB   pymalloc arenas =   254
  freed 90% (every 10th survives)                private = baseline   +263.6 MB   pymalloc arenas =   254
  re-allocated the 10% densely, freed originals  private = baseline    +37.2 MB   pymalloc arenas =    38
  freed everything                               private = baseline     +1.1 MB   pymalloc arenas =    10
== the same 8M values as one numpy buffer (64 MB, malloc'd outside pymalloc)
  np.int64 array allocated                       private = baseline    +65.2 MB   pymalloc arenas =    10
  kept 10% via .copy(), freed the parent         private = baseline     +7.5 MB   pymalloc arenas =    10
  freed everything                               private = baseline     +1.1 MB   pymalloc arenas =    10
ALL STEPS DONE
```

Keeping every 10th object left all **254 arenas** alive, and only the 64 MB pointer array (a large `malloc`) went back to the OS. Re-allocating the survivors densely and dropping the originals collapsed that to 38 arenas. The NumPy buffer of the same values returned to the OS immediately, because it never entered pymalloc. **A non-moving allocator punishes interleaved lifetimes**; the JVM's compacting collector would have slid the survivors together. In CPython you get the same result by giving long-lived data its own *allocation epoch*: build it once, early, densely; keep request-scoped garbage out of its arenas; and put bulk numeric data in buffers.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Pod OOMKilled loading "only" 50 M ids | RSS ≈ 40 B × N + list slack; `tracemalloc` top = list/int allocation sites | Boxed ints (32 B) + 8 B pointers; often duplicated per worker | `np.int64` / `array('q')` / Arrow column; dedupe across workers via shared memory | Budget rule: Python object graph ≈ 5–10× the raw bytes; review any `list` > 1 M elements |
| F2 🔥 | Memory never returns after a big batch is "freed" | RSS flat after `del`; `sys._debugmallocstats()` shows arenas allocated ≈ high-water | Survivor objects pin pymalloc arenas (non-moving allocator) | Rebuild survivors densely, then drop the originals; move bulk data to buffers; recycle workers (`max_tasks_per_child`, gunicorn `max_requests`) | Separate long-lived from request-scoped allocations; never cache "a few" objects from every batch |
| F3 ⚡ | Mysterious 100 ms – 1 s stalls every few minutes | `gc.callbacks` shows gen-2 collections aligned with p99 spikes | Full collection walks every tracked object (~45 ns each) | `gc.freeze()` after warm-up; raise `threshold0`; avoid creating long-lived containers per request | Export GC pause histograms (`gc.callbacks`) next to latency SLOs |
| F4 🔥 | Memory climbs after upgrading 3.14.4 → 3.14.5 (or the other way) | Different gen counts / pause profile in `gc.get_stats()` | Incremental GC (3.14.0–3.14.4) reverted to generational in 3.14.5 | Re-baseline GC settings per patch release | Pin `python:3.14.N` exactly; run a GC soak test on every bump |
| F5 | Instance memory triples after adding a "dynamic fields" feature | `sys.getsizeof` unchanged, tracemalloc per-instance jumps 96 → 320 B | > 30 distinct attribute names per class → shared keys exhausted → private dicts | Store dynamic fields in one dict attribute or a side table | Lint for `setattr(self, f"...")`; prefer `__slots__` for record types |
| F6 | Serializer "doubles" memory of a model graph | +64 B per object after a `vars(o)` / `o.__dict__` pass | Dict materialization from inline values | Serialize via explicit field lists / `__slots__` / `dataclasses.fields` | Never call `vars()` on hot or bulk paths |
| F7 | `sum()` / hash join 5–10× slower in prod than in the benchmark | perf shows LLC/TLB misses, same instruction count | Pointer order ≠ allocation order after sort/shuffle/set; dependent random loads | Columnar buffers; sort data by access order; vectorize | Benchmark with production-shaped (shuffled) data |
| F8 | Leak in a C extension; refcounts creep | `sys.getrefcount(x)` climbs; `tracemalloc` shows growth at the extension call site | Missing `Py_DECREF` on an error path or a borrowed→owned confusion | Fix the refcount discipline; build with `--with-pydebug` (`sys.gettotalrefcount()`) | Use pybind11/nanobind/PyO3 smart handles; run the debug build in CI |
| F9 | `__del__` objects in cycles "never freed" (pre-3.4 lore) or freed in odd order | `gc.garbage` empty but finalizers run during GC | PEP 442: finalizers run, order inside a cycle is arbitrary | Use `weakref.finalize` / context managers, never finalizers, for resources | Lint against `__del__` for resource release |
| F10 ⚡ | `fork()`ed workers' memory balloons despite copy-on-write | Per-worker private RSS grows while only reading | Reading an object writes its refcount and GC header → CoW page copies | `gc.freeze()` before forking; immortal/static data; data in shared buffers (01.3) | Measure USS/PSS (not RSS) per worker |

**Debugging toolkit, in the order to reach for it:**

1. `tracemalloc.start(25)`, then `snapshot.statistics("traceback")` for *who* allocated.
2. `sys._debugmallocstats()` for pymalloc arenas, pools and size-class occupancy. It writes to the C-level stderr, so redirect fd 2 as `arena_fragmentation.py` does.
3. `gc.get_stats()`, `gc.callbacks` and `gc.get_count()` for collector behaviour.
4. `objgraph` or `gc.get_referrers()` for *why* something is alive.
5. For native leaks: a `--with-pydebug` build, `PYTHONMALLOC=debug` (guard bytes), and ASan/Valgrind on Linux.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "We hold 50 M user IDs in a Python list per worker and the pods OOM at 4 GiB. Why, and what's the fix?"</b></summary>

**Initial Prompt.** Eight gunicorn workers each load 50 M int64 user IDs from a feature file into a `list` for membership tests and joins.

**L5 Answer.** "Python ints are 28 bytes plus an 8-byte pointer, so about 1.8 GB per worker. Use `__slots__`, or `array('q')`, or load fewer IDs."

**Why L5 Crashes at Scale.** The arithmetic misses the allocator: each int is a 32 B block (`sizeof(PyLongObject)`), so it's 40 B per element, or ~2.0 GB, *before* the `set` built for membership tests (another ~2× in hash table slots and entries). It also misses that eight workers each hold a private copy. `__slots__` is irrelevant because there are no instances. `array('q')` fixes storage, but every lookup still boxes.

**L7 Principal Defense.** Price it precisely: 50 M × 40 B = 2.0 GB per worker, ×8 = 16 GB, plus the set. Then change the representation, not the container. Load the IDs once as a sorted `np.int64` array or an Arrow column (400 MB). Do membership by `np.searchsorted` or a vectorized `isin`. Map it read-only into all workers via shared memory or a memory-mapped Parquet/Arrow file (01.3, Folder 02), so the fleet pays 400 MB once instead of 16 GB. The guardrail is to require an explicit memory budget and `tracemalloc` evidence for any in-process collection above 1 M elements.

</details>

<details><summary><b>Q2 · "`sys.getsizeof` says our cache is 300 MB but RSS is 1.1 GB. Which one is lying?"</b></summary>

**Initial Prompt.** A service sums `sys.getsizeof` over a cache dict's keys and values for a metrics gauge.

**L5 Answer.** "`getsizeof` is shallow; it doesn't count referenced objects, so recurse into them."

**Why L5 Crashes at Scale.** Even a perfect recursive `getsizeof` under-reports. It omits the 16 B `PyGC_Head` and 16 B pre-header on instances, the struct padding allocated beyond `getsizeof` (28 vs 32 for ints), allocator size-class rounding, free blocks stranded in partially used pools, and arenas pinned by survivors. On a churned heap the gap reaches 2–3×, and the gauge drives the wrong eviction decisions.

**L7 Principal Defense.** Use three instruments for three questions. `tracemalloc` gives requested bytes by allocation site, which answers who allocates. `sys._debugmallocstats()` gives arena, pool and size-class occupancy, which answers fragmentation. Process private bytes or USS answer what the OS charges. Size caches by *entry count × measured bytes-per-entry*, calibrated with tracemalloc on production-shaped data, and alert on RSS. Then remove the root cause: store cache values as encoded bytes or Arrow buffers, not object graphs.

</details>

<details><summary><b>Q3 · "Should we put `__slots__` on everything?"</b></summary>

**Initial Prompt.** A team proposes a lint rule that every class must declare `__slots__` "for performance".

**L5 Answer.** "Yes. Slots remove the `__dict__`, which saves about 100 bytes per object and makes attribute access faster."

**Why L5 Crashes at Scale.** In 3.13+ a plain instance has no dict unless one is materialized: inline values are 96 B against 56 B for slots, not "dict vs no dict". Attribute reads cost the same (≈ 16–18 ns, both specialized). Slots break `__dict__`-based tooling (some serializers, `functools.cached_property`, monkeypatching in tests). They need `__weakref__` listed explicitly to be weak-referenceable, and multiple inheritance with non-empty slots in more than one base raises a layout conflict. A blanket rule buys ~40 B per object on classes with a few hundred instances and breaks things.

**L7 Principal Defense.** Apply slots where *instance count × lifetime* is large: record types in caches, graph nodes, event objects in buffers. Use `@dataclass(slots=True)`. Measure with tracemalloc (56 vs 96 B here). And recognize that slots don't unbox the fields: with three boxed numbers you're at ~148 B against 24 B in a NumPy structured array. For millions of homogeneous records the answer isn't slots, it's columnar storage, with Python objects created lazily at the edges.

</details>

<details><summary><b>Q4 · "Explain immortal objects. Why did CPython need them, and what do they cost?"</b></summary>

**Initial Prompt.** PEP 683 made some objects immortal in 3.12. What changed in the machine code and why does it matter for production?

**L5 Answer.** "Immortal objects like `None` never get deallocated, which saves some refcount operations."

**Why L5 Crashes at Scale.** That misses the point. The win isn't fewer frees, it's *no writes*. Every `Py_INCREF(None)` used to dirty `None`'s cache line from every core and dirty its page in every forked child, triggering copy-on-write faults across thousands of shared pages. In free-threaded builds those writes would have to be atomic on the most contended objects in the process.

**L7 Principal Defense.** In 3.14 the default build's `Py_INCREF` checks `cur_refcnt >= 3 << 30` and returns, so immortals cost one load and one compare. Immortal objects carry refcount `0xC0000000` and, if static, `ob_flags = 0x0005`, which I verified on a live interpreter. The initial value `3 << 30` sits mid-way between `2**31` and `2**32` on purpose: a stable-ABI extension compiled for 3.11 that still does a raw `++`/`--` can drift the count by ~1 billion without the object losing immortality (`Include/refcount.h` comment). The trade-offs are a branch on every incref/decref (well predicted) and the fact that interned strings are *not* immortal in 3.14, so don't build "shared read-only" designs on interned keys. In the free-threaded build immortality is `ob_ref_local == UINT32_MAX` and is what makes `None`/`True`/small-int traffic scale across cores (01.2).

</details>

<details><summary><b>Q5 · "Our p99 has 300 ms spikes every ~90 s with no I/O correlation. GC?"</b></summary>

**Initial Prompt.** A recommendation service holds a 15 M-object in-memory graph and handles 2 k RPS on CPython 3.14.

**L5 Answer.** "Probably GC. Call `gc.disable()` in production; refcounting frees most things anyway."

**Why L5 Crashes at Scale.** `gc.disable()` turns rare pauses into an unbounded leak. Every reference cycle (exceptions holding tracebacks holding frames, parent/child links, closures) accumulates until the pod dies. And when someone re-enables it, the first young collection scans *everything* allocated since (≈ 84 ms per 2 M objects here).

**L7 Principal Defense.** First prove it: register a `gc.callbacks` hook that records generation and duration, and overlay it on the latency histogram. At ~45 ns per tracked object, a full collection of 15 M objects is ≈ 0.7 s, which matches. Then fix it structurally. (1) `gc.freeze()` after loading the long-lived graph, so collections skip it. (2) Raise `threshold0` modestly (a measured 2.4× less GC time while building). (3) Stop allocating long-lived containers per request. (4) Move the graph to arrays (CSR adjacency in NumPy), where the GC has nothing to traverse. Keep the collector *enabled* for cycle safety, and pin the patch version, because 3.14.0–3.14.4 had a different (incremental) collector.

</details>

<details><summary><b>Q6 · "Why does `sum()` over the same list get 6× slower after we sort it by a different key?"</b></summary>

**Initial Prompt.** A pipeline sorts records by `customer_id` and then aggregates `amount`. The aggregation slowed from 40 ms to 250 ms on 10 M rows, even though the instructions are identical.

**L5 Answer.** "Sorting is O(n log n); maybe the sort is the slow part."

**Why L5 Crashes at Scale.** It's the *aggregation* that slowed. Sorting permuted the pointer array, so the objects are now visited in random memory order: a dependent cache miss and often a TLB miss per element. At 10 M elements × 32 B the objects span 320 MB, far beyond the LLC.

**L7 Principal Defense.** This is the measured shuffled-vs-creation-order result: ≈ 259 ms against ≈ 37 ms for identical objects. The general rule is that a Python object graph's locality is an *accident of allocation history*. Make locality explicit with columnar buffers: `argsort` once, then gather contiguous columns (`amount[idx]`) and aggregate with SIMD. Or let a columnar engine (Polars, DuckDB, Folder 03) do the sort-and-aggregate natively. Benchmark on production-ordered data, never on freshly built `range()` lists.

</details>

<details><summary><b>Q7 · "How does CPython's cycle detector actually find garbage without a root set?"</b></summary>

**Initial Prompt.** The JVM traces from GC roots (thread stacks, statics). CPython has no precise stack maps. How does it decide what is unreachable?

**L5 Answer.** "It does mark and sweep from the globals."

**Why L5 Crashes at Scale.** CPython can't enumerate roots: C extensions hold `PyObject*` in C variables it can't see. A mark-from-roots collector would free objects owned by C code. That is why the algorithm is *subtractive*, and why a buggy extension's extra INCREF manifests as a permanent leak rather than a crash.

**L7 Principal Defense.** It infers external references by difference. Copy each container's refcount into `gc_refs`, then call `tp_traverse` on every object in the generation and decrement the referents' `gc_refs`. Whatever stays above zero is referenced from *outside* the set (C code, stacks, older generations), so it and everything it reaches are alive; the rest is a closed island and is garbage. The cost is O(tracked objects in the generation), never O(heap) for young collections, and objects that can't form cycles (ints, strs, tuples of atomics in 3.14) are never tracked at all. Production levers follow from that: fewer tracked containers, `gc.freeze()` for immortal-ish data, and no `gc.disable()`.

</details>

<details><summary><b>Q8 · "We cut memory 90% by deleting old entries but the container's RSS didn't move. Explain to the SRE."</b></summary>

**Initial Prompt.** A long-running ingestion worker keeps a rolling window of parsed events. After pruning 90 % of them, RSS stays at the peak and the pod is evicted at the next spike.

**L5 Answer.** "Python never returns memory to the OS. Restart the worker periodically."

**Why L5 Crashes at Scale.** It does return memory: whole arenas once empty, and large blocks immediately. Periodic restarts hide the design flaw and add cold-start latency and lost in-flight work.

**L7 Principal Defense.** Show the arena math: 32 B blocks, 512 per 16 KiB pool, 64 pools per 1 MiB arena. One survivor per pool pins the arena, which reproduces 254 arenas pinned after freeing 90 %. The structural fixes are: (1) keep the rolling window in a ring of preallocated NumPy/Arrow buffers, not objects; (2) if objects are unavoidable, rebuild survivors into a fresh structure and drop the old one (254 → 38 arenas measured), so the survivors pack densely; (3) cap per-worker lifetime with `max_tasks_per_child` only as a backstop; (4) alert on `arenas allocated current` from `sys._debugmallocstats()`.

</details>

<details><summary><b>Q9 · "What does the free-threaded build do to these numbers?"</b></summary>

**Initial Prompt.** We plan to move the same services to `python3.14t`. What happens to memory?

**L5 Answer.** "Nothing major. It just removes the GIL."

**Why L5 Crashes at Scale.** Every object header doubles from 16 to 32 B. A one-digit int's block grows from 32 to 48 B (+50 %), and allocation moves to mimalloc's per-thread heaps, so the memory budgets computed above are wrong by 20–50 % for object-heavy services.

**L7 Principal Defense.** Use the header facts verified by compiling the 3.14 headers with `Py_GIL_DISABLED`: `ob_tid` 8, `ob_flags` 2, `ob_mutex` 1, `ob_gc_bits` 1, `ob_ref_local` 4, `ob_ref_shared` 8, `ob_type` 8 = 32 B. There's no `PyGC_Head`, because the collector walks mimalloc's GC heaps instead. Re-budget object-heavy services (10 M ints ≈ 560 MB instead of ≈ 400 MB), and treat that as one more reason to keep bulk data in buffers, whose cost is build-independent. Then evaluate the CPU side separately (01.2).

</details>

<details><summary><b>Q10 · "A colleague says 'Python ints are slow because they're bignums.' Agree?"</b></summary>

**Initial Prompt.** In a design review, someone claims integer-heavy Python is slow because every int is arbitrary precision.

**L5 Answer.** "Yes. Each operation has to handle arbitrary digits."

**Why L5 Crashes at Scale.** Small ints aren't handled as bignums on the hot path. Since 3.12, *compact* ints (one 30-bit digit) take dedicated paths: `BINARY_OP_ADD_INT` after specialization, a Py_ssize_t accumulator inside `sum()`, and the one-digit freelist. Optimizing the bignum path (`gmpy2`) would change nothing.

**L7 Principal Defense.** The cost is *boxing and dispatch*: an allocation (or freelist pop) per result, a type-guarded bytecode per operation, a refcount write per reference, and a pointer chase per element read. That is ~4–8 ns of overhead around a 0.3 ns add. The cure is to amortize dispatch over many elements (NumPy ufuncs, Arrow compute, Polars expressions), so the 30-bit-digit format never appears in the inner loop. Bignums *do* matter at the edges. NumPy `int64` silently wraps where Python ints don't (01.4 measures a wrapped sum), so validate ranges when moving data across that boundary.

</details>

---

## 5. Invariants Checklist

- [ ] Every Python value costs ≥ 16 B of header (32 B free-threaded) plus allocator rounding to 16 B classes. Budget **40 B per element** for `list[int]` and ~5–10× raw bytes for object graphs.
- [ ] `sys.getsizeof` is shallow and excludes `PyGC_Head`, pre-headers and padding. Use tracemalloc for requested bytes and private bytes/USS for what you pay.
- [ ] Immortal objects (`None`, bools, small ints −5…256 in 3.14 / …1024 in 3.15, static strings, static types) are never written by refcounting. A runtime-interned string is **not** immortal in 3.14.
- [ ] Plain instances in 3.13+ have inline values, not dicts. Touching `__dict__` or using > 30 attribute names per class silently reverts to dicts.
- [ ] `__slots__` fixes the container (56 B), not the payload. Boxed field values still cost their own objects.
- [ ] Refcounting frees synchronously on the calling thread: `del` of a big structure is a latency event.
- [ ] Cycle GC cost ∝ tracked objects in the collected generations (~45 ns/object here). `gc.freeze()` long-lived heaps; never `gc.disable()` in a long-running service.
- [ ] GC behaviour is patch-version-specific (3.14.0–3.14.4 incremental, 3.14.5+ generational). Pin patch versions.
- [ ] pymalloc never moves objects; arena release needs *all* pools empty. Separate long-lived and transient allocation lifetimes.
- [ ] For numeric data, contiguous typed buffers + vectorized kernels beat any object layout by 8–54× in time and 5× in memory.

---

## 6. References

**CPython source (pinned tags)**
- `Include/object.h`: struct `_object`, both builds — https://github.com/python/cpython/blob/v3.14.10/Include/object.h
- `Include/refcount.h`: `_Py_IMMORTAL_INITIAL_REFCNT`, `Py_INCREF`/`Py_DECREF` — https://github.com/python/cpython/blob/v3.14.10/Include/refcount.h
- `Include/cpython/longintrepr.h` and `Include/internal/pycore_long.h`: `lv_tag` bit layout — https://github.com/python/cpython/blob/v3.14.10/Include/cpython/longintrepr.h
- `Objects/longobject.c`: `long_alloc`, `_PyLong_FromMedium` (`sizeof(PyLongObject)`) — https://github.com/python/cpython/blob/v3.14.10/Objects/longobject.c
- `Objects/listobject.c`: `py_list_resize` growth rule — https://github.com/python/cpython/blob/v3.14.10/Objects/listobject.c
- `Include/internal/pycore_obmalloc.h`: arenas, pools, size classes — https://github.com/python/cpython/blob/v3.14.10/Include/internal/pycore_obmalloc.h
- `Python/gc.c`: generational collector, 25 % full-collection rule — https://github.com/python/cpython/blob/v3.14.10/Python/gc.c
- `Include/internal/pycore_runtime_structs.h`: `_PY_NSMALLPOSINTS` 257 (3.14) vs 1025 (3.15) — https://github.com/python/cpython/blob/v3.15.2/Include/internal/pycore_runtime_structs.h
- What's New 3.14, "Garbage collection" (incremental GC reverted in 3.14.5) — https://docs.python.org/3.14/whatsnew/3.14.html

**PEPs**
- PEP 683 — Immortal Objects: https://peps.python.org/pep-0683/
- PEP 412 — Key-Sharing Dictionary: https://peps.python.org/pep-0412/
- PEP 442 — Safe object finalization: https://peps.python.org/pep-0442/
- PEP 454 — tracemalloc: https://peps.python.org/pep-0454/
- PEP 703 — Making the GIL Optional (header layout): https://peps.python.org/pep-0703/

**Docs and background**
- `gc` module (`freeze`, `callbacks`, thresholds): https://docs.python.org/3/library/gc.html
- Python memory management and `PYTHONMALLOC`: https://docs.python.org/3/c-api/memory.html
- JEP 519 — Compact Object Headers (JVM bridge): https://openjdk.org/jeps/519
- Instagram Engineering, "Copy-on-write friendly Python garbage collection" (2017), the `gc.freeze` motivation; cited by title (the blog host refused automated requests during the link check).
