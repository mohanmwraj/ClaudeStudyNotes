# 01.4 · Advanced Object Model: Descriptors, Metaclasses, Specialization, Generators & Pydantic v2 (Rust)

> **Folder 01 · CPython Runtime, Memory Model & Concurrency Physics**
> **Measured on:** CPython 3.14.5 (GIL build, experimental JIT present in the Windows binary), pydantic 2.14.1 / pydantic-core 2.50.1, msgspec 0.22.0, NumPy 2.5.4, i5-11260H, Windows 11.
> **Source verified against:** `v3.14.10` `Objects/object.c` (`_PyObject_GenericGetAttrWithDict`), `Objects/typeobject.c` (`MAX_VERSIONS_PER_CLASS`, `type_new`), `Include/internal/pycore_interp_structs.h` (`MCACHE_SIZE_EXP`), `Python/bytecodes.c`, `Python/specialize.c`; pydantic `main.py` (`BaseModel.__slots__`).

---

## 0. Orientation & the JVM/C++ Bridge

Python's object model is a small set of C-level protocols (`tp_getattro`, `tp_descr_get`/`tp_descr_set`, `tp_new`/`tp_init`, `tp_iternext`) with Python hooks layered on top. Every "magic" feature (properties, methods, `classmethod`, `__slots__`, ORMs, dataclasses, Pydantic) is one of those protocols. Since 3.11 they also feed a **specializing interpreter** that rewrites bytecode in place on type-guarded assumptions, and in 3.13+ an experimental JIT that stitches those specialized operations into machine code. To be fast in Python you have to know which features keep the guards stable.

| Python mechanism | What it really is | JVM analogue | C++ analogue |
|---|---|---|---|
| Attribute lookup | MRO walk cached per **type version tag** (4096-entry method cache, `MCACHE_SIZE_EXP` 12) | vtable / itable + constant-pool resolution | vtable; name lookup at compile time |
| Data / non-data descriptor | object with `__get__` (+ `__set__`/`__delete__`) on the class | — (closest: bytecode-woven accessors, Lombok) | proxy / accessor objects |
| `property` | data descriptor wrapping functions | getter methods (inlined by C2) | inline accessors |
| Bound method | non-data descriptor creating a `method` object (avoided for direct calls) | `invokevirtual` | member-function pointer + `this` |
| Metaclass | the class of the class: `type.__new__` builds the type object | `ClassLoader` + annotation processing | templates / CRTP / code generation |
| `__init_subclass__`, `__set_name__` | class-creation hooks run inside `type.__new__` | static initializers, `ServiceLoader` | static registration objects |
| PEP 659 specialization | per-instruction inline caches + guarded opcodes | interpreter quickening + C1/C2 inline caches | PGO / devirtualization |
| Generator | heap-allocated, resumable `_PyInterpreterFrame` | — (Loom continuations are stackful) | C++20 stackless coroutine frame |
| Pydantic v2 | Rust (`pydantic-core`, PyO3) validator compiled from a schema at class creation | Jackson + Bean Validation, but codegen'd | simdjson + generated validators |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The attribute lookup algorithm

`PyObject_GenericGetAttr` → `_PyObject_GenericGetAttrWithDict` (`Objects/object.c`):

```text
obj.name
 1. descr = _PyType_LookupRef(type(obj), name)       # MRO walk, served by the per-interpreter method cache
                                                      #   keyed by (type->tp_version_tag, name)
 2. if descr's type has tp_descr_get AND tp_descr_set (a DATA descriptor):
        return descr.__get__(obj, type(obj))          # property, member_descriptor (__slots__), getset
 3. look in the instance: inline values (3.13+) or __dict__  -> return the value if present
 4. if descr has tp_descr_get (NON-DATA descriptor):
        return descr.__get__(obj, type(obj))          # functions -> bound methods, classmethod, staticmethod
 5. if descr is not NULL: return descr                # plain class attribute
 6. raise AttributeError  -> type(obj).__getattr__(obj, name) if defined (slot_tp_getattr_hook)
```

Two rules decide most surprises. **Data descriptors beat the instance; the instance beats non-data descriptors.** So `obj.__dict__["total"] = 1` can't shadow a `property`, while `obj.method = f` *does* shadow a method. One edge case is worth knowing: a descriptor with `__set__` but *no* `__get__` is still a data descriptor for assignment, but on reads step 2 doesn't apply (there's no `tp_descr_get`), so the instance value wins. The listing in §2.1 checks all nine cases against the real interpreter.

### 1.2 Type version tags: the hinge of all caching

```text
PyTypeObject
  tp_version_tag      unsigned int   0 = "no valid tag" (unspecializable until reassigned)
  tp_versions_used    counter        MAX_VERSIONS_PER_CLASS = 1000  (Objects/typeobject.c)
  tp_dict / MRO       ...
assignment C.x = v   -> PyType_Modified(C) -> tp_version_tag = 0 for C and every subclass
next lookup / specialization -> assign_version_tag(): new global tag, ++tp_versions_used
          if tp_versions_used >= 1000: return 0  -> the type NEVER gets a tag again
```

Every inline cache (`LOAD_ATTR_INSTANCE_VALUE`, `LOAD_ATTR_METHOD_WITH_VALUES`, `LOAD_GLOBAL_MODULE`…) stores the version it was specialized for and deoptimizes on mismatch. **Mutating a class on a hot path** (class-level counters, per-request monkeypatching, `mock.patch` inside a loop, lazily added class attributes) invalidates every guard. Do it ~1000 times with lookups in between and the class is **unspecializable for the rest of the process**. §2.2 demonstrates the permanent `LOAD_ATTR` on the exhausted class: ≈ 130 vs ≈ 85 ns per method call.

### 1.3 PEP 659 quickening and the 3.14 JIT

```text
 cold:      LOAD_ATTR (adaptive, counter)  --warm-up-->  specialize on observed type:
 hot:       LOAD_ATTR_INSTANCE_VALUE  [guard: type_version == cached; inline values valid]
                 |  guard fails -> deopt to the generic LOAD_ATTR, exponential back-off, maybe re-specialize
 tier 2 (JIT builds, PYTHON_JIT=1): hot traces of specialized instructions -> micro-ops (uops)
                 -> copy-and-patch: pre-compiled machine-code "stencils" (LLVM at CPython BUILD time)
                    are memcpy'd and their holes patched with runtime constants/addresses (PEP 744)
```

The specializer is *monomorphic*: one cached type per instruction. A site that sees four receiver types keeps thrashing between deopt and re-specialization, measured ≈ 1.7–1.8× slower per read. The 3.14 JIT ships in the official Windows and macOS binaries but is off by default (`PYTHON_JIT=1`). The 3.14 notes say "−10 % … +20 %"; this machine measured 1.14–1.19× on a float loop across runs. 3.15 rebuilds the frontend as a tracing JIT (LLVM 21, register allocation) and reports 7–8 % geomean on x86-64 Linux (⚠ not run here).

### 1.4 Class creation, in order

`__build_class__` → metaclass resolution → `__prepare__` → body → `metaclass(name, bases, ns, **kw)`:

```text
 1. metaclass = most-derived of (explicit metaclass, type(b) for b in bases)  -> TypeError "metaclass conflict" if none is
 2. ns = metaclass.__prepare__(name, bases, **kw)            # PEP 3115 (an ordered dict by default)
 3. exec(class body, ns)
 4. cls = metaclass.__new__(...)  -> type.__new__:
        build the PyTypeObject (slots, MRO via C3, tp_basicsize, flags)
        4a. for each attribute with __set_name__: attr.__set_name__(cls, name)        # PEP 487
        4b. super(cls).__init_subclass__(**kw)                                         # PEP 487
 5. metaclass.__init__(cls, ...)
 6. class decorators, innermost first
```

A metaclass `__new__` that calls `super().__new__(mcls, name, bases, ns)` **without `**kw`** silently drops class keyword arguments before `__init_subclass__` sees them. That bit this KB's own listing during development; the fixed line carries a comment.

### 1.5 Generators are heap frames

```text
 PyGenObject (sys.getsizeof = 256 B measured, 3.14)
 +------------------------------------------------------------+
 | PyObject header | gi_weakreflist | gi_name | gi_qualname    |
 | gi_exc_state | gi_origin_or_finalizer | gi_hooks_inited ... |
 | gi_frame_state (CREATED / SUSPENDED / RUNNING / COMPLETED)  |
 | _PyInterpreterFrame gi_iframe   <- embedded since 3.11:     |
 |    f_executable (code), instr_ptr, localsplus[] (locals +  |
 |    cells + the value stack)                                 |
 +------------------------------------------------------------+
 next(g) / g.send(v): push gi_iframe onto the thread's frame chain, resume at instr_ptr, run to YIELD_VALUE
```

Consequences: a suspended generator **keeps every local alive** (a 64 MiB buffer in §2.4D), `close()` raises `GeneratorExit` at the suspension point so `finally` runs, and `yield from`/`await` chains forward each `next()` through every level, so per-item cost grows with depth (≈ 40 → 85 → 215 ns at depth 0/4/16). 🧊 This is the C++20 stackless-coroutine model (a heap frame, symmetric resumption), not Loom's stackful virtual threads.

### 1.6 Pydantic v2: where the time goes

```text
 class Order(BaseModel): ...      (class creation, once)
   pydantic: annotations -> core schema (a nested dict) -> pydantic_core.SchemaValidator (Rust, PyO3)
             stored on Order.__pydantic_validator__
 Order.model_validate_json(b)     (per call)
   Rust: jiter parses bytes -> validates field-by-field against the compiled schema
         -> builds the Python object: BaseModel.__slots__ = ('__dict__', '__pydantic_fields_set__',
            '__pydantic_extra__', '__pydantic_private__')   + a real __dict__ for the field values
 Order.model_validate(dict)       (per call) -> Python dict already built by json.loads, then validated in Rust
 Order.model_construct(**d)       (per call) -> pure-Python loop, NO validation
```

The JSON-bytes path skips building an intermediate Python dict, so it's faster than `json.loads` + validate (≈ 2.4 against ≈ 4.1 µs per record) and even faster than `json.loads` into an unvalidated slotted dataclass (≈ 2.65 µs). The cost Pydantic doesn't remove is the Python object it returns: ~1.1 KB per 5-field model against ~235 B for a `msgspec.Struct`.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 The lookup order, proven case by case

```python
"""attribute_lookup.py - a pure-Python model of PyObject_GenericGetAttr, checked against the real thing.

Order (Objects/object.c, _PyObject_GenericGetAttrWithDict):
  1. look `name` up along type(obj).__mro__ (cached per type version)          -> descr
  2. descr's type has __get__ AND (__set__ or __delete__)  -> data descriptor -> descr.__get__(obj, type)
  3. name in the instance's __dict__ / inline values                          -> that value
  4. descr has __get__ (non-data: functions, classmethod, staticmethod)       -> descr.__get__(obj, type)
  5. descr found but has no __get__ (plain class attribute)                   -> descr
  6. AttributeError -> type(obj).__getattr__(obj, name) if defined
"""
import types


def model_getattr(obj, name):
    tp = type(obj)
    descr = next((k.__dict__[name] for k in tp.__mro__ if name in k.__dict__), None)
    dtp = type(descr)
    get = getattr(dtp, "__get__", None) if descr is not None else None
    if get is not None and (hasattr(dtp, "__set__") or hasattr(dtp, "__delete__")):
        return get(descr, obj, tp)                                     # 2. data descriptor wins
    try:
        inst = object.__getattribute__(obj, "__dict__")
    except AttributeError:
        inst = {}                                                       # __slots__ only: no instance dict
    if name in inst:
        return inst[name]                                               # 3. instance attribute
    if get is not None:
        return get(descr, obj, tp)                                      # 4. non-data descriptor
    if descr is not None:
        return descr                                                    # 5. plain class attribute
    hook = next((k.__dict__["__getattr__"] for k in tp.__mro__ if "__getattr__" in k.__dict__), None)
    if hook is not None:
        return hook(obj, name)                                          # 6. fallback
    raise AttributeError(name)


class SetOnly:
    """A data descriptor WITHOUT __get__: the instance dict wins over it (step 3 before step 5)."""
    def __set__(self, obj, value):
        obj.__dict__["shadow"] = value * 10


class Base:
    kind = "class-attr"
    shadow = SetOnly()

    @property
    def total(self):
        return "property"

    def method(self):
        return "bound method"

    @classmethod
    def factory(cls):
        return f"classmethod on {cls.__name__}"

    @staticmethod
    def helper():
        return "staticmethod"


class Child(Base):
    def __getattr__(self, name):
        return f"__getattr__({name})"


class Slotted:
    __slots__ = ("x",)


def describe(v):                                                        # stable text: no addresses
    if isinstance(v, types.MethodType):
        owner = v.__self__ if isinstance(v.__self__, type) else type(v.__self__)
        return f"<bound {v.__func__.__qualname__} -> {owner.__name__}{'' if v.__self__ is owner else ' instance'}>"
    if isinstance(v, types.FunctionType):
        return f"<function {v.__qualname__}>"
    return repr(v)


def check(label, obj, name):
    real = getattr(obj, name)
    mine = model_getattr(obj, name)
    same = real == mine
    print(f"  {label:52} -> {describe(mine):38} {'OK' if same else 'MISMATCH'}")
    assert same, (label, real, mine)


c = Child()
c.kind = "instance-attr"                                                # shadows the class attribute
c.__dict__["total"] = "instance dict entry"                             # property is a data descriptor: loses
c.method = lambda: "instance callable"                                  # functions are non-data: instance wins
c.shadow = 4                                                            # SetOnly.__set__ stores 40 in __dict__
s = Slotted()
s.x = 7
print("== the lookup order, case by case (model vs builtin getattr)")
check("instance attr shadows class attr", c, "kind")
check("data descriptor (property) beats instance dict", c, "total")
check("instance dict beats non-data descriptor (function)", c, "method")
check("data descriptor w/o __get__: instance dict wins", c, "shadow")
check("classmethod binds to the type", c, "factory")
check("staticmethod returns the raw function", Child(), "helper")
check("slot = member_descriptor (data descriptor)", s, "x")
check("missing name -> __getattr__ fallback", c, "nope")
b = Base()
check("plain bound method (fresh object each access)", b, "method")
assert b.method is not b.method and b.method == b.method
print(f"  b.method is b.method -> {b.method is b.method}: every access allocates a bound method"
      f" (the interpreter avoids it for direct calls b.method())")
print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
== the lookup order, case by case (model vs builtin getattr)
  instance attr shadows class attr                     -> 'instance-attr'                        OK
  data descriptor (property) beats instance dict       -> 'property'                             OK
  instance dict beats non-data descriptor (function)   -> <function <lambda>>                    OK
  data descriptor w/o __get__: instance dict wins      -> 40                                     OK
  classmethod binds to the type                        -> <bound Base.factory -> Child>          OK
  staticmethod returns the raw function                -> <function Base.helper>                 OK
  slot = member_descriptor (data descriptor)           -> 7                                      OK
  missing name -> __getattr__ fallback                 -> '__getattr__(nope)'                    OK
  plain bound method (fresh object each access)        -> <bound Base.method -> Base instance>   OK
  b.method is b.method -> False: every access allocates a bound method (the interpreter avoids it for direct calls b.method())
ALL ASSERTIONS PASSED
```

The model in 25 lines matches the C implementation on all nine cases, including the `SetOnly` edge case (a data descriptor without `__get__` loses to the instance dict) and the classmethod binding to `type(obj)`. `b.method is b.method` is `False`: each *attribute access* allocates a bound method, while a direct call `b.method()` doesn't (`LOAD_ATTR_METHOD_*` pushes the function and `self` separately).

### 2.2 Watching specialization, breaking it, and timing the JIT

```python
"""specialization_jit.py - watch PEP 659 quickening rewrite bytecode, break it, and time the 3.14 JIT.

A: dis(adaptive=True) after warm-up shows each generic instruction replaced by a guarded, type-specific form.
B: guards key on the type's version tag. Each class gets at most MAX_VERSIONS_PER_CLASS (1000) tags
   (Objects/typeobject.c); a class mutated on the hot path exhausts them and is unspecializable forever.
C: a polymorphic call site (4 receiver types) vs a monomorphic one.
D: the experimental copy-and-patch JIT (PYTHON_JIT=1) on a hot loop, each setting in a fresh process.
"""
import dis
import os
import subprocess
import sys
import time


class P:
    def __init__(self):
        self.v = 1

    def m(self):
        return self.v

    @property
    def pv(self):
        return self.v


class S:
    __slots__ = ("v",)

    def __init__(self):
        self.v = 1


G = 5


def read_v(o):
    return o.v


def read_pv(o):
    return o.pv


def call_m(o):
    return o.m()


def add(a, b):
    return a + b


def use_global():
    return G + 1


def ops(f):
    keep = ("LOAD_ATTR", "BINARY_OP", "LOAD_GLOBAL", "CALL", "STORE_ATTR")
    return [i.opname for i in dis.get_instructions(f, adaptive=True) if i.opname.startswith(keep)]


print("== A. generic -> specialized instructions (after 1000 calls)")
for label, f, args in [("o.v, regular class", read_v, (P(),)), ("o.v, __slots__ class", read_v, (S(),)),
                       ("o.pv, property", read_pv, (P(),)), ("o.m(), method call", call_m, (P(),)),
                       ("a + b, ints", add, (1, 2)), ("a + b, floats", add, (1.0, 2.0)),
                       ("a + b, str", add, ("a", "b")), ("G + 1, module global", use_global, ())]:
    code = f.__code__
    f.__code__ = code.replace()                       # fresh copy: resets the inline caches
    cold = ops(f)
    for _ in range(1000):
        f(*args)
    print(f"  {label:22} {' '.join(cold):24} -> {' '.join(ops(f))}")
read_v.__code__ = read_v.__code__.replace()

print("== B. class mutation invalidates the type version every guard checks")


class Q:                                               # an unrelated class to mutate in the control loop
    pass


def loop_reads(o, mutate, n=1_000_000):
    t0 = time.perf_counter()
    for i in range(n):
        mutate.counter = i                             # writes a class attribute: bumps that type's version
        o.v
    return (time.perf_counter() - t0) / n * 1e9


p = P()
t_other = min(loop_reads(p, Q) for _ in range(3))
t_same = min(loop_reads(p, P) for _ in range(3))
print(f"  mutate an unrelated class each iteration: {t_other:5.1f} ns/iter")
print(f"  mutate P itself each iteration         : {t_same:5.1f} ns/iter  (+{t_same - t_other:.1f} ns)")
assert t_same > t_other


class Fresh:                                           # same shape as P, never mutated
    def __init__(self):
        self.v = 1

    def m(self):
        return self.v


def method_site():
    def call(o):
        return o.m()
    return call


for label, obj in [("P (after 3M class writes)", P()), ("identical, never-mutated class", Fresh())]:
    f = method_site()
    for _ in range(2000):
        f(obj)
    spec = " ".join(i.opname for i in dis.get_instructions(f, adaptive=True) if i.opname.startswith("LOAD_ATTR"))
    t0 = time.perf_counter()
    for _ in range(1_000_000):
        f(obj)
    print(f"  {label:32} o.m() -> {spec:30} {(time.perf_counter() - t0) * 1e3:5.0f} ns/call")
    if label.startswith("P"):
        assert spec == "LOAD_ATTR", "P should have exhausted its version tags"

print("== C. monomorphic vs polymorphic attribute site")


class A1:
    def __init__(self):
        self.v = 1


class A2(A1):
    pass


class A3(A1):
    pass


class A4(A1):
    pass


def site(objs):
    t0 = time.perf_counter()
    for o in objs:
        o.v
    return (time.perf_counter() - t0) / len(objs) * 1e9


mono = [A1() for _ in range(400_000)]
poly = [k() for _ in range(100_000) for k in (A1, A2, A3, A4)]
t_mono = min(site(mono) for _ in range(3))
t_poly = min(site(poly) for _ in range(3))
print(f"  1 receiver type : {t_mono:5.1f} ns/read    4 receiver types (round-robin): {t_poly:5.1f} ns/read"
      f"  ({t_poly / t_mono:.2f}x)")

print("== D. 3.14 experimental JIT, same loop in a fresh process per setting")
HOT = """
import sys, time
def hot(n):
    s = 0.0
    for i in range(n):
        s += (i % 7) * 0.5 - (i & 3)
    return s
hot(50_000)
t0 = time.perf_counter(); hot(5_000_000); dt = time.perf_counter() - t0
print(f"{sys._jit.is_available()} {sys._jit.is_enabled()} {dt:.4f}")
"""
res = {}
for flag in ("0", "1"):
    env = dict(os.environ, PYTHON_JIT=flag)
    out = subprocess.run([sys.executable, "-c", HOT], env=env, capture_output=True, text=True, check=True).stdout
    avail, enabled, dt = out.split()
    res[flag] = float(dt)
    print(f"  PYTHON_JIT={flag}: jit available={avail} enabled={enabled}  hot(5M) = {float(dt) * 1e3:6.0f} ms")
print(f"  JIT speedup on this loop: {res['0'] / res['1']:.2f}x (3.14 notes: -10% .. +20% typical)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. generic -> specialized instructions (after 1000 calls)
  o.v, regular class     LOAD_ATTR                -> LOAD_ATTR_INSTANCE_VALUE
  o.v, __slots__ class   LOAD_ATTR                -> LOAD_ATTR_SLOT
  o.pv, property         LOAD_ATTR                -> LOAD_ATTR_PROPERTY
  o.m(), method call     LOAD_ATTR CALL           -> LOAD_ATTR_METHOD_WITH_VALUES CALL_PY_EXACT_ARGS
  a + b, ints            BINARY_OP                -> BINARY_OP_ADD_INT
  a + b, floats          BINARY_OP                -> BINARY_OP_ADD_FLOAT
  a + b, str             BINARY_OP                -> BINARY_OP_ADD_UNICODE
  G + 1, module global   LOAD_GLOBAL BINARY_OP    -> LOAD_GLOBAL_MODULE BINARY_OP_ADD_INT
== B. class mutation invalidates the type version every guard checks
  mutate an unrelated class each iteration:  47.3 ns/iter
  mutate P itself each iteration         :  66.9 ns/iter  (+19.6 ns)
  P (after 3M class writes)        o.m() -> LOAD_ATTR                        134 ns/call
  identical, never-mutated class   o.m() -> LOAD_ATTR_METHOD_WITH_VALUES      88 ns/call
== C. monomorphic vs polymorphic attribute site
  1 receiver type :  11.0 ns/read    4 receiver types (round-robin):  19.5 ns/read  (1.78x)
== D. 3.14 experimental JIT, same loop in a fresh process per setting
  PYTHON_JIT=0: jit available=True enabled=False  hot(5M) =    343 ms
  PYTHON_JIT=1: jit available=True enabled=True  hot(5M) =    289 ms
  JIT speedup on this loop: 1.19x (3.14 notes: -10% .. +20% typical)
ALL ASSERTIONS PASSED
```

* **A** shows the rewrite PEP 659 performs. Every generic opcode becomes a guarded, type-specific one after warm-up: `LOAD_ATTR_SLOT` for `__slots__`, `LOAD_ATTR_PROPERTY`, `BINARY_OP_ADD_INT`/`_FLOAT`/`_UNICODE`, `LOAD_GLOBAL_MODULE`.
* **B** is the production trap. Writing a class attribute every iteration costs ~+20 ns per read, and afterwards the *same* class can no longer be specialized at all (`LOAD_ATTR` instead of `LOAD_ATTR_METHOD_WITH_VALUES`, ≈ 130 vs ≈ 85 ns per call) because it burned through `MAX_VERSIONS_PER_CLASS`. **Pattern:** treat classes as immutable after import; keep mutable "class-level" state in a separate object (a module-level dict, an instance, a `ContextVar`).
* **C**: megamorphic sites are ≈ 1.7–1.8× slower. **Pattern:** keep hot loops monomorphic (homogeneous lists, or dispatch once outside the loop) or, better, vectorize.
* **D**: the 3.14 JIT gave 1.14–1.19× on this loop. Useful, but it's an order of magnitude less than moving the loop into NumPy (folders 02 and 06 measure 20–50×).

### 2.3 Class machinery: hooks, a validating descriptor, and what each layer costs

```python
"""class_machinery.py - class creation hooks in order, descriptors that validate, and what each layer costs.

A: the exact hook sequence of `class Order(Base, metaclass=Meta, table="orders")` plus a decorator.
B: a __set_name__ field descriptor, and the classic bug of storing per-instance state on the descriptor.
C: ns per attribute read for every access mechanism.  D: isinstance() cost: class, ABC, Protocol, hasattr.
E: the metaclass-conflict rule.
"""
import abc
import functools
import time
from typing import Protocol, runtime_checkable

trace = []


class Meta(type):
    @classmethod
    def __prepare__(mcls, name, bases, **kw):
        trace.append(f"Meta.__prepare__({name}, kw={kw})")
        return {}

    def __new__(mcls, name, bases, ns, **kw):
        trace.append(f"Meta.__new__({name}) -> type.__new__ ...")
        cls = super().__new__(mcls, name, bases, ns, **kw)  # forward kw, or __init_subclass__ never sees them
        trace.append(f"... type.__new__ returned {name}")
        return cls

    def __init__(cls, name, bases, ns, **kw):
        trace.append(f"Meta.__init__({name})")
        super().__init__(name, bases, ns)


class Field:
    """Validating data descriptor: state lives in the INSTANCE, keyed by the attribute name."""
    def __init__(self, kind):
        self.kind = kind

    def __set_name__(self, owner, name):
        trace.append(f"Field.__set_name__({owner.__name__}.{name})")
        self.slot = "_" + name

    def __get__(self, obj, owner=None):
        return self if obj is None else getattr(obj, self.slot)

    def __set__(self, obj, value):
        if not isinstance(value, self.kind):
            raise TypeError(f"{self.slot[1:]} must be {self.kind.__name__}, got {type(value).__name__}")
        setattr(obj, self.slot, value)


class BuggyField:
    """Stores the value ON THE DESCRIPTOR: one descriptor per class -> shared by every instance."""
    def __get__(self, obj, owner=None):
        return self.value

    def __set__(self, obj, value):
        self.value = value


class Base(metaclass=Meta):
    registry = {}

    def __init_subclass__(cls, table=None, **kw):
        trace.append(f"Base.__init_subclass__({cls.__name__}, table={table})")
        super().__init_subclass__(**kw)
        Base.registry[table] = cls


trace.clear()


def decorate(cls):
    trace.append(f"decorator({cls.__name__})")
    return cls


@decorate
class Order(Base, table="orders"):
    trace.append("class body executes")
    qty = Field(int)
    price = Field(float)
    note = BuggyField()

    def __init__(self, qty, price, note):
        self.qty, self.price, self.note = qty, price, note


print("== A. hook order for `@decorate class Order(Base, table='orders')`")
for i, step in enumerate(trace, 1):
    print(f"  {i}. {step}")
assert Base.registry["orders"] is Order

print("== B. descriptor state: per-instance vs on-the-descriptor")
a, b = Order(1, 9.5, "first"), Order(2, 3.0, "second")
print(f"  Field (instance storage): a.qty={a.qty} b.qty={b.qty}")
print(f"  BuggyField (descriptor storage): a.note={a.note!r} b.note={b.note!r}  <- a's value was overwritten")
assert (a.qty, b.qty) == (1, 2) and a.note == b.note == "second"
try:
    Order("3", 1.0, "x")
except TypeError as e:
    print(f"  Order('3', ...) -> TypeError: {e}")


class Plain:
    def __init__(self):
        self.v = 1


class Slots:
    __slots__ = ("v",)

    def __init__(self):
        self.v = 1


class Prop:
    def __init__(self):
        self._v = 1

    @property
    def v(self):
        return self._v


class PyDescr:
    v = Field(int)

    def __init__(self):
        self.v = 1


class Cached:
    @functools.cached_property
    def v(self):
        return 1                                           # first access stores into the instance __dict__


class Dyn:
    def __getattr__(self, name):                           # runs only after normal lookup fails
        return 1


def read_cost(o, n=1_000_000):
    o.v
    t0 = time.perf_counter()
    for _ in range(n):
        o.v
    return (time.perf_counter() - t0) / n * 1e9


print("== C. ns per `o.v` read")
base = None
for label, o in [("instance attribute", Plain()), ("__slots__ member", Slots()), ("@property", Prop()),
                 ("Python-level data descriptor", PyDescr()), ("cached_property (after 1st)", Cached()),
                 ("__getattr__ fallback", Dyn())]:
    ns = min(read_cost(o) for _ in range(3))
    base = base or ns
    print(f"  {label:30} {ns:6.1f} ns  ({ns / base:4.1f}x)")


class Concrete:
    def close(self):
        pass


class AbstractCloser(abc.ABC):
    @abc.abstractmethod
    def close(self): ...


class ViaABC(AbstractCloser):
    def close(self):
        pass


class Unrelated:
    def close(self):
        pass


AbstractCloser.register(Unrelated)                        # virtual subclass


@runtime_checkable
class Closer(Protocol):
    def close(self): ...


def isinstance_cost(obj, cls, n=300_000):
    t0 = time.perf_counter()
    for _ in range(n):
        isinstance(obj, cls)
    return (time.perf_counter() - t0) / n * 1e9


print("== D. ns per type check")
for label, fn in [("isinstance(x, ConcreteClass)", lambda: isinstance_cost(Concrete(), Concrete)),
                  ("isinstance(x, ABC) real subclass", lambda: isinstance_cost(ViaABC(), AbstractCloser)),
                  ("isinstance(x, ABC) registered", lambda: isinstance_cost(Unrelated(), AbstractCloser)),
                  ("isinstance(x, Protocol) True", lambda: isinstance_cost(Concrete(), Closer)),
                  ("isinstance(x, Protocol) False", lambda: isinstance_cost(1, Closer))]:
    print(f"  {label:34} {min(fn() for _ in range(3)):7.1f} ns")
t0 = time.perf_counter()
o = Concrete()
for _ in range(300_000):
    hasattr(o, "close")
print(f"  {'hasattr(x, \"close\")':34} {(time.perf_counter() - t0) / 3e5 * 1e9:7.1f} ns")
assert isinstance(Concrete(), Closer) and not isinstance(1, Closer)

print("== E. metaclass conflict")


class M1(type):
    pass


class M2(type):
    pass


class X(metaclass=M1):
    pass


class Y(metaclass=M2):
    pass


try:
    class Z(X, Y):
        pass
except TypeError as e:
    print(f"  class Z(X, Y) -> TypeError: {str(e)[:70]}...")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. hook order for `@decorate class Order(Base, table='orders')`
  1. Meta.__prepare__(Order, kw={'table': 'orders'})
  2. class body executes
  3. Meta.__new__(Order) -> type.__new__ ...
  4. Field.__set_name__(Order.qty)
  5. Field.__set_name__(Order.price)
  6. Base.__init_subclass__(Order, table=orders)
  7. ... type.__new__ returned Order
  8. Meta.__init__(Order)
  9. decorator(Order)
== B. descriptor state: per-instance vs on-the-descriptor
  Field (instance storage): a.qty=1 b.qty=2
  BuggyField (descriptor storage): a.note='second' b.note='second'  <- a's value was overwritten
  Order('3', ...) -> TypeError: qty must be int, got str
== C. ns per `o.v` read
  instance attribute               15.4 ns  ( 1.0x)
  __slots__ member                 15.6 ns  ( 1.0x)
  @property                        31.4 ns  ( 2.0x)
  Python-level data descriptor    114.3 ns  ( 7.4x)
  cached_property (after 1st)      27.1 ns  ( 1.8x)
  __getattr__ fallback             75.0 ns  ( 4.9x)
== D. ns per type check
  isinstance(x, ConcreteClass)          23.1 ns
  isinstance(x, ABC) real subclass     173.6 ns
  isinstance(x, ABC) registered        432.8 ns
  isinstance(x, Protocol) True         281.8 ns
  isinstance(x, Protocol) False       3180.0 ns
  hasattr(x, "close")                  104.5 ns
== E. metaclass conflict
  class Z(X, Y) -> TypeError: metaclass conflict: the metaclass of a derived class must be a (non-st...
ALL ASSERTIONS PASSED
```

* The hook order (A) is what ORMs, Pydantic and dataclass-like libraries rely on: `__set_name__` runs inside `type.__new__` *before* `__init_subclass__`, and both before the metaclass `__init__` and any decorator. Registries belong in `__init_subclass__`; metaclasses only when you must control `__prepare__` or the type object itself.
* `BuggyField` (B) is the most common hand-written descriptor bug: storing per-instance values on the descriptor makes every instance share one value.
* **Cost ladder (C):** instance attribute or slot ≈ 16 ns, `property` ≈ 2×, `cached_property` after its first access ≈ 1.8× (it writes into the instance `__dict__`, so reads become plain dict hits; since 3.12 it no longer takes a lock), `__getattr__` ≈ 5×, and a **Python-level data descriptor ≈ 7×**. That last one is why ORMs and validation layers that intercept every attribute read are slow at scale.
* **Type checks (D):** `isinstance` against a concrete class is ≈ 23 ns; against an ABC ≈ 175–455 ns; against a `runtime_checkable` Protocol ≈ 280 ns when it matches and **≈ 3.2 µs when it doesn't**, because every protocol member is probed with `inspect.getattr_static`. Never put Protocol `isinstance` in a per-row path.

### 2.4 Generators: memory, delegation cost, and the pinned-frame leak

```python
"""generator_frames.py - a generator is a heap-allocated frame you can suspend: size, state, cost, and leaks.

A: object sizes (the _PyInterpreterFrame is embedded in the generator since 3.11) and the state machine.
B: peak memory of materialize-then-reduce vs a streaming pipeline vs NumPy, and their speed.
C: per-item cost of `yield from` delegation chains (every next() walks the chain).
D: a suspended generator pins its locals (a 64 MiB buffer here) until close() or collection.
"""
import gc
import inspect
import sys
import time
import tracemalloc

import numpy as np


def counter(n):
    total = 0
    try:
        for i in range(n):
            got = yield i
            if got is not None:
                total += got
    finally:
        print(f"    finally ran (total sent = {total})")


print("== A. size and state machine")
g = counter(3)
print(f"  sys.getsizeof(generator) = {sys.getsizeof(g)} B (frame embedded)   sys.getsizeof(lambda) = "
      f"{sys.getsizeof(lambda: 0)} B")
states = [inspect.getgeneratorstate(g)]
next(g)
states.append(inspect.getgeneratorstate(g))
g.send(10)
states.append(f"suspended={g.gi_suspended}")
g.close()                                             # raises GeneratorExit at the yield -> finally runs
states.append(inspect.getgeneratorstate(g))
print(f"  states: {' -> '.join(states)}")
assert states[0] == "GEN_CREATED" and states[-1] == "GEN_CLOSED"

print("== B. reduce 10M squares: materialize vs stream vs vectorize")
N, N_MEM = 10_000_000, 1_000_000


def timed(fn):
    t0 = time.perf_counter()
    r = fn()
    return time.perf_counter() - t0, r


def peak_mb(fn):
    gc.collect()
    tracemalloc.start()
    fn()
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return peak / 1e6


cases = [("sum([x*x for x in range(n)])", lambda n: sum([x * x for x in range(n)])),
         ("sum(x*x for x in range(n))", lambda n: sum(x * x for x in range(n))),
         ("(np.arange(n, dtype=int64)**2).sum()", lambda n: int((np.arange(n, dtype=np.int64) ** 2).sum()))]
results = []
for label, fn in cases:
    dt, r = timed(lambda: fn(N))
    results.append(r)
    print(f"  {label:38} {dt * 1e3:7.0f} ms at 10M   peak traced at 1M: {peak_mb(lambda: fn(N_MEM)):6.1f} MB")
exact, streamed, vector = results
assert exact == streamed
print(f"  exact Python int : {exact:,}")
print(f"  NumPy int64 sum  : {vector:,}   <- silently wrapped modulo 2**64 (no OverflowError)")
assert vector == (exact + 2**63) % 2**64 - 2**63
fixed = float((np.arange(N, dtype=np.float64) ** 2).sum())
print(f"  float64 accumulate: {fixed:.6e} (relative error {abs(fixed - exact) / exact:.1e})")

print("== C. `yield from` delegation depth: cost per item")


def leaf(n):
    yield from range(n)


def chain(depth, n):
    if depth == 0:
        yield from leaf(n)
    else:
        yield from chain(depth - 1, n)


for depth in (0, 4, 16):
    t0 = time.perf_counter()
    s = sum(chain(depth, 1_000_000))
    dt = time.perf_counter() - t0
    assert s == 1_000_000 * 999_999 // 2
    print(f"  depth {depth:2}: {dt / 1e6 * 1e9:6.1f} ns/item")

print("== D. a parked generator keeps its frame's locals alive")


def batches():
    buf = bytearray(64 << 20)                         # 64 MiB scratch buffer, a local of the frame
    for i in range(10):
        buf[i] = i
        yield i


def traced_now():
    gc.collect()
    return tracemalloc.get_traced_memory()[0] / 1e6


tracemalloc.start()
gen = batches()
next(gen)                                             # consumer reads one item, then "forgets" the generator
pinned = traced_now()
gen.close()                                           # or let it be collected: either releases the frame
released = traced_now()
tracemalloc.stop()
print(f"  after one next(): {pinned:6.1f} MB traced   after gen.close(): {released:6.1f} MB")
assert pinned > 60 and released < 5
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. size and state machine
  sys.getsizeof(generator) = 256 B (frame embedded)   sys.getsizeof(lambda) = 168 B
    finally ran (total sent = 10)
  states: GEN_CREATED -> GEN_SUSPENDED -> suspended=True -> GEN_CLOSED
== B. reduce 10M squares: materialize vs stream vs vectorize
  sum([x*x for x in range(n)])               782 ms at 10M   peak traced at 1M:   40.4 MB
  sum(x*x for x in range(n))                 696 ms at 10M   peak traced at 1M:    0.0 MB
  (np.arange(n, dtype=int64)**2).sum()        38 ms at 10M   peak traced at 1M:   16.0 MB
  exact Python int : 333,333,283,333,335,000,000
  NumPy int64 sum  : 1,291,890,006,563,070,912   <- silently wrapped modulo 2**64 (no OverflowError)
  float64 accumulate: 3.333333e+20 (relative error 0.0e+00)
== C. `yield from` delegation depth: cost per item
  depth  0:   40.1 ns/item
  depth  4:   85.1 ns/item
  depth 16:  215.9 ns/item
== D. a parked generator keeps its frame's locals alive
  after one next():   67.1 MB traced   after gen.close():    0.0 MB
ALL ASSERTIONS PASSED
```

* **B**: streaming (`sum(x*x for x in ...)`) holds ~0 MB instead of 40 MB per million items, with no speed penalty against the list version. Both are ~20× slower than NumPy.
* **B, also:** NumPy's `int64` sum **silently wrapped** to 1.29e18 where the exact answer is 3.33e20. Python ints never overflow; NumPy fixed-width types wrap without warning. Vectorizing changes semantics, so check value ranges or accumulate in `float64`/`object` when magnitudes are unbounded.
* **D**: a generator that was started but not exhausted pins its frame, here 64 MiB, until `close()` or collection. In pipelines that create one generator per request or file and break early, that's a leak with a long tail. **Pattern:** `contextlib.closing(gen)` or `with` inside the generator, plus explicit `close()` when breaking out.

### 2.5 Pydantic v2: seven decode paths for the same 50 k orders

```python
"""pydantic_v2_paths.py - the same 50k JSON orders through seven decode/validate paths (pydantic-core is Rust).

The model's core schema is compiled ONCE into a SchemaValidator at class creation; validate_json parses bytes in
Rust (jiter) without building Python dicts first. The costly anti-pattern is building a TypeAdapter per call.
Also: lax vs strict coercion, and bytes per instance (BaseModel vs msgspec.Struct vs slotted dataclass).
"""
import gc
import json
import time
import tracemalloc
from dataclasses import dataclass
from datetime import datetime, timezone

import msgspec
import pydantic
from pydantic import BaseModel, ConfigDict, TypeAdapter, ValidationError

N = 50_000


class Order(BaseModel):
    order_id: int
    sku: str
    qty: int
    price: float
    ts: datetime


class StrictOrder(Order):
    model_config = ConfigDict(strict=True)


class OrderStruct(msgspec.Struct):
    order_id: int
    sku: str
    qty: int
    price: float
    ts: datetime


@dataclass(slots=True)
class OrderDC:
    order_id: int
    sku: str
    qty: int
    price: float
    ts: datetime


rows = [{"order_id": 10_000_000 + i, "sku": f"SKU-{i % 977:05d}", "qty": 1 + i % 9, "price": round(1 + i * 0.01, 2),
         "ts": f"2026-10-{1 + i % 28:02d}T12:{i % 60:02d}:00Z"} for i in range(N)]
lines = [json.dumps(r) for r in rows]
array_bytes = json.dumps(rows).encode()
list_adapter = TypeAdapter(list[Order])


def manual(line):
    d = json.loads(line)
    d["ts"] = datetime.fromisoformat(d["ts"])
    return OrderDC(**d)                                  # parsed, but no type validation at all


paths = [
    ("json.loads + slotted dataclass (no validation)", lambda: [manual(s) for s in lines]),
    ("json.loads + Order.model_validate(dict)", lambda: [Order.model_validate(json.loads(s)) for s in lines]),
    ("Order.model_validate_json(line)", lambda: [Order.model_validate_json(s) for s in lines]),
    ("TypeAdapter(list[Order]).validate_json(all)", lambda: list_adapter.validate_json(array_bytes)),
    ("msgspec.json.decode(all, type=list[Struct])", lambda: msgspec.json.decode(array_bytes, type=list[OrderStruct])),
    ("Order.model_construct(**dict) (skips checks)", lambda: [Order.model_construct(**json.loads(s)) for s in lines]),
]
print(f"pydantic {pydantic.VERSION} (pydantic-core {pydantic.__version__ and __import__('pydantic_core').__version__})"
      f", msgspec {msgspec.__version__}; {N:,} orders")
print(f"{'path':50} {'us/record':>10}")
cost = {}
for label, fn in paths:
    fn()
    t0 = time.perf_counter()
    out = fn()
    cost[label] = (time.perf_counter() - t0) / N * 1e6
    assert len(out) == N
    print(f"  {label:48} {cost[label]:9.2f}")
batches = [json.dumps(rows[i:i + 10]).encode() for i in range(0, 5000, 10)]   # 10-record request bodies
for label, per_call in [("TypeAdapter(Order) per record", False), ("TypeAdapter(list[Order]) per batch", True)]:
    t0 = time.perf_counter()
    if per_call:
        for b in batches:
            TypeAdapter(list[Order]).validate_json(b)  # generic type: core schema rebuilt on every call
    else:
        for s in lines[:5000]:
            TypeAdapter(Order).validate_json(s)        # a BaseModel: reuses Order.__pydantic_validator__
    anti = (time.perf_counter() - t0) / 5000 * 1e6
    print(f"  {label + ' (anti-pattern)':48} {anti:9.2f}   ({anti / cost['Order.model_validate_json(line)']:.0f}x"
          f" the cached validator)")
validated = list_adapter.validate_json(array_bytes)
assert validated[7].ts == datetime(2026, 10, 8, 12, 7, tzinfo=timezone.utc) and isinstance(validated[7].qty, int)

print("== lax (default) vs strict coercion")
probe = {"order_id": "123", "sku": "A", "qty": 2.0, "price": 1, "ts": "2026-10-28T00:00:00Z"}
lax = Order.model_validate(probe)
print(f"  lax   : order_id {probe['order_id']!r} -> {lax.order_id!r}, qty {probe['qty']!r} -> {lax.qty!r}, "
      f"price {probe['price']!r} -> {lax.price!r}")
try:
    Order.model_validate({**probe, "qty": 2.5})
except ValidationError as e:
    print(f"  lax   : qty 2.5 -> {e.errors()[0]['type']}")
try:
    StrictOrder.model_validate(probe)
except ValidationError as e:
    print(f"  strict: {e.error_count()} errors: {sorted({err['type'] for err in e.errors()})}")

print("== bytes per instance (tracemalloc, 50k objects, field values included)")
for label, make in [("pydantic BaseModel", lambda: list_adapter.validate_json(array_bytes)),
                    ("msgspec.Struct", lambda: msgspec.json.decode(array_bytes, type=list[OrderStruct])),
                    ("@dataclass(slots=True)", lambda: [manual(s) for s in lines])]:
    gc.collect()
    tracemalloc.start()
    objs = make()
    cur, _ = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    print(f"  {label:24} {cur / N:7.0f} B/record")
    del objs
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
pydantic 2.14.1 (pydantic-core 2.50.1), msgspec 0.22.0; 50,000 orders
path                                                us/record
  json.loads + slotted dataclass (no validation)        2.67
  json.loads + Order.model_validate(dict)               4.14
  Order.model_validate_json(line)                       2.46
  TypeAdapter(list[Order]).validate_json(all)           2.12
  msgspec.json.decode(all, type=list[Struct])           0.52
  Order.model_construct(**dict) (skips checks)          5.71
  TypeAdapter(Order) per record (anti-pattern)          6.51   (3x the cached validator)
  TypeAdapter(list[Order]) per batch (anti-pattern)      6.15   (3x the cached validator)
== lax (default) vs strict coercion
  lax   : order_id '123' -> 123, qty 2.0 -> 2, price 1 -> 1.0
  lax   : qty 2.5 -> int_from_float
  strict: 3 errors: ['datetime_type', 'int_type']
== bytes per instance (tracemalloc, 50k objects, field values included)
  pydantic BaseModel          1144 B/record
  msgspec.Struct               235 B/record
  @dataclass(slots=True)       231 B/record
ALL ASSERTIONS PASSED
```

| Path | µs / record | When to use |
|---|---:|---|
| `msgspec.json.decode(..., type=list[Struct])` | **≈ 0.5** | internal high-volume decoding where msgspec's type system suffices |
| `TypeAdapter(list[Order]).validate_json(batch)` (adapter cached) | ≈ 2.1 | batch endpoints, Kafka micro-batches |
| `Order.model_validate_json(line)` | ≈ 2.4 | per-message validation: bytes in, model out |
| `json.loads` + slotted dataclass (no validation!) | ≈ 2.65 | never as a "fast path": it's slower *and* unvalidated |
| `json.loads` + `Order.model_validate(dict)` | ≈ 4.1 | only when you already have dicts |
| `Order.model_construct(**dict)` | ≈ 5.6–5.7 | not a speed optimization in v2: pure-Python and unvalidated |
| `TypeAdapter(...)` built per call | ≈ 6.1–6.5 | anti-pattern: ~2.5× here, rebuilding schema and validator objects (~35–37 µs) per call |

Lax mode coerces `"123"` → 123 and `2.0` → 2 but rejects `2.5` (`int_from_float`). Strict mode rejects all three type mismatches. **Pattern:** validate at trust boundaries with `validate_json` on raw bytes; cache adapters at module level; use strict mode for machine-to-machine contracts; inside the trusted core use plain structs or columnar data, not 1.1 KB-per-record models.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 ⚡ | A hot service gets 30–60 % slower after a "harmless" feature flag | `dis.dis(f, adaptive=True)` shows generic `LOAD_ATTR` on a hot site | Class attributes mutated on the hot path → type version churn → `MAX_VERSIONS_PER_CLASS` exhausted | Move mutable state off the class; restart to recover | Lint for class-attribute assignment outside import time; perf-regression tests |
| F2 | Values "leak" between instances | Two instances read the same field value | Descriptor stores per-instance state on itself | Store in the instance (`__set_name__` + `obj.__dict__`/slot) | Descriptor review checklist; property-based tests with two instances |
| F3 | Class keyword arguments silently ignored | `__init_subclass__` receives defaults | Metaclass `__new__` doesn't forward `**kw` to `type.__new__` | Forward `**kw` | Prefer `__init_subclass__` to metaclasses |
| F4 | `TypeError: metaclass conflict` when combining two frameworks | Raised at class definition | Two unrelated metaclasses in the bases | A combined metaclass deriving from both, or drop one framework's metaclass | Avoid metaclasses in libraries; use `__init_subclass__` |
| F5 ⚡ | Validation layer dominates the CPU profile | `isinstance` against Protocols/ABCs in per-row code; 3.2 µs negative checks | `runtime_checkable` Protocol probes every member | Check concrete types or use `hasattr` once per type, cached | Keep structural checks out of inner loops |
| F6 🔥 | Memory grows with requests that "stream" data | tracemalloc shows big objects owned by generator frames | Started-but-unfinished generators pin locals | `contextlib.closing`, `try/finally` in the generator, explicit `close()` | Prefer `with` scopes for resources inside generators |
| F7 🔥 | Silent wrong totals after "optimizing" with NumPy | No error; results differ from the Python reference | `int64` overflow wraps | Range checks, `float64`/`object` accumulation, or Python ints at the edge | Differential tests comparing the vectorized and reference paths |
| F8 ⚡ | API latency regresses after adding a typed endpoint | Profile shows `TypeAdapter.__init__` / schema generation per request | `TypeAdapter` built per call | Module-level adapters; `@lru_cache` around factory functions | Lint: no `TypeAdapter(` inside functions |
| F9 | Memory per record 5× expected after adopting Pydantic models in a cache | ~1.1 KB per 5-field model | Each model has `__dict__`, fields-set, extra/private slots, plus boxed field values | Cache `msgspec.Struct`s, tuples, or columnar data; build models at the API edge only | Budget bytes per cached record with tracemalloc |
| F10 | "Fast path" `model_construct` makes ingestion slower and lets bad data in | Profile shows Python-level `model_construct`; downstream type errors | Assumed v1 semantics; v2's Rust validator is faster than Python construction | `model_validate_json` on raw bytes | Benchmark before adopting "unsafe fast paths" |

**Debugging toolkit.** `dis.dis(fn, adaptive=True)` (or `dis.get_instructions(..., adaptive=True)`) shows the live specialized bytecode. `sys._jit.is_available()`/`is_enabled()` report the JIT state. `python -X importtime` measures class-creation-heavy imports. `inspect.getgeneratorstate`, `gi_frame` and `gi_suspended` inspect generators. Pydantic's `Model.__pydantic_core_schema__` shows the compiled schema, and `ValidationError.errors()` gives machine-readable error types (`int_from_float`, `datetime_type`).

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why can a property not be shadowed by an instance attribute, but a method can?"</b></summary>

**Initial Prompt.** A test does `obj.compute = lambda: 42` successfully but `obj.total = 5` raises `AttributeError` for a `property`. Explain.

**L5 Answer.** "Properties are special and read-only; methods are just attributes."

**Why L5 Crashes at Scale.** Without the descriptor precedence rule you can't reason about ORMs, `__slots__`, `cached_property` or framework magic. A team that "fixes" this by writing into `obj.__dict__["total"]` will find reads still return the property, which is a silent data bug.

**L7 Principal Defense.** Lookup checks the type first. A *data* descriptor (has `__get__` and `__set__`/`__delete__`: `property`, slots' `member_descriptor`) wins over the instance; then the instance dict or inline values; then *non-data* descriptors (functions, `classmethod`, `staticmethod`); then plain class attributes; then `__getattr__`. Functions are non-data, so an instance attribute shadows them. A property defines `__set__` (raising if there's no setter), so assignment goes to the property and reads ignore the instance dict. The executable model in §2.1 matches the interpreter on nine cases, including a `__set__`-only descriptor where the instance *does* win on read.

</details>

<details><summary><b>Q2 · "Our service is 40% slower in production than in the benchmark, same code. The profile is flat."</b></summary>

**Initial Prompt.** A pure-Python scoring library is fast in microbenchmarks but slow in the long-running service. No single hot function stands out.

**L5 Answer.** "Production has more data; it's cache effects, or the GC."

**Why L5 Crashes at Scale.** A flat profile with uniformly slower attribute access is the signature of *lost specialization*. Cache and GC theories send the team after memory, and the regression stays.

**L7 Principal Defense.** Inspect live bytecode: `dis.get_instructions(hot_fn, adaptive=True)` in the service (a debug endpoint) against the benchmark. Generic `LOAD_ATTR`/`LOAD_GLOBAL` where the benchmark shows `_INSTANCE_VALUE`/`_MODULE` variants means guards fail. Then look for class or module mutation at runtime: feature flags assigning class attributes, per-request monkeypatching, metrics counters on classes, `mock.patch` left in a code path. I measured ≈ +20 ns per read while mutating, and afterwards a class that exhausted `MAX_VERSIONS_PER_CLASS` (1000) stays on the generic path for the life of the process (≈ 130 vs ≈ 85 ns per call). Fix by moving the mutable state off the class, and add a regression test that asserts the specialized opcodes on the hot path.

</details>

<details><summary><b>Q3 · "When is a metaclass the right tool in 2026?"</b></summary>

**Initial Prompt.** A framework team wants a metaclass to auto-register plugin classes and validate their attributes.

**L5 Answer.** "Metaclasses are the standard way to customize class creation, so use one."

**Why L5 Crashes at Scale.** Metaclasses compose badly. Two libraries with metaclasses can't be mixed without a combined metaclass (`TypeError: metaclass conflict`, §2.3E). They hide behaviour in class creation, and a missing `**kw` forward silently breaks keyword arguments (the bug this KB's own listing hit).

**L7 Principal Defense.** Use the narrowest hook. `__init_subclass__` for registration and per-subclass validation (it receives class keywords), `__set_name__` for descriptor wiring, a class decorator for one-off transforms. Reserve metaclasses for what nothing else can do: a custom `__prepare__` namespace, altering the type object's layout or `__call__`, or class-level operators (`Enum`, ORMs' `Model.field == x`). Keep registration side-effect-free and import-order-independent, and verify the hook order (the measured 9-step trace) in tests.

</details>

<details><summary><b>Q4 · "Is `__getattr__`-based lazy loading a good pattern for our config object?"</b></summary>

**Initial Prompt.** A config class computes missing attributes on demand in `__getattr__` and is read millions of times per second.

**L5 Answer.** "Yes, `__getattr__` only runs for missing attributes, so it's cheap."

**Why L5 Crashes at Scale.** It runs only *after a full failed lookup*: the MRO walk, the instance check and the raised-and-caught `AttributeError` internally. That's ~75 ns against ~16 ns for a stored attribute, on every read, if the value isn't cached. And dynamic attributes defeat static analysis and IDEs.

**L7 Principal Defense.** Compute once and store. `functools.cached_property` writes into the instance `__dict__`, so later reads are plain hits (≈ 26–27 ns measured; no lock since 3.12, so the computation must be idempotent under threads). Or resolve config eagerly into a frozen dataclass or `msgspec.Struct` at startup. Keep `__getattr__` for genuinely dynamic proxies (and PEP 562 module-level `__getattr__` for lazy attributes; 3.15 adds explicit lazy imports, PEP 810).

</details>

<details><summary><b>Q5 · "Explain what `model_validate_json` does that `json.loads` + `model_validate` doesn't."</b></summary>

**Initial Prompt.** A Kafka consumer validates 200 k messages/s with Pydantic v2 and the CPU is pegged.

**L5 Answer.** "They're the same: one parses first, the other parses inside. Pydantic is just slow; switch libraries."

**Why L5 Crashes at Scale.** `json.loads` materializes a full Python dict (allocations, interning, refcounts) that's then walked again by the validator. Switching libraries without understanding that keeps the dict detour and loses Pydantic's error reporting.

**L7 Principal Defense.** `model_validate_json` hands the raw bytes to pydantic-core, which parses with jiter in Rust and validates as it parses, creating only the final Python objects. Measured: ≈ 2.4 µs against ≈ 4.1 µs per record, and faster than `json.loads` into an *unvalidated* dataclass (≈ 2.65). For batches, a cached `TypeAdapter(list[Order]).validate_json` amortizes call overhead (≈ 2.1). If the CPU budget still doesn't fit, msgspec Structs are ≈ 0.5 µs and ~235 B per record against ~1.1 KB. Choose per boundary: Pydantic at external trust boundaries for its errors and coercion rules, msgspec or columnar decoding (Arrow) for internal high-volume streams.

</details>

<details><summary><b>Q6 · "What's the memory model of a generator, and how can it leak?"</b></summary>

**Initial Prompt.** A streaming file processor yields parsed records; memory grows over days.

**L5 Answer.** "Generators are lazy, so they can't hold much memory."

**Why L5 Crashes at Scale.** Laziness is about *future* items. A suspended generator owns its whole frame: locals, the value stack and any buffers or open files. Every consumer that breaks early and keeps a reference (or a reference cycle through the frame) pins it.

**L7 Principal Defense.** Since 3.11 the `_PyInterpreterFrame` is embedded in the 256 B generator object, and everything the frame references stays alive while the generator is suspended. Measured: one `next()` on a generator with a 64 MiB local buffer keeps 67 MB traced until `close()`. `close()` throws `GeneratorExit` at the `yield` so `finally`/`with` blocks run. The rules: use `with` for resources *inside* generators, wrap consumers in `contextlib.closing()`, always `close()` on early exit, and for async generators rely on `asyncio.run`'s `shutdown_asyncgens()` or `aclose()` explicitly. Diagnose with `tracemalloc` tracebacks pointing into generator frames and `gc.get_referrers(gen)`.

</details>

<details><summary><b>Q7 · "Should we `isinstance`-check against Protocols for input validation in our hot path?"</b></summary>

**Initial Prompt.** A data-plane function checks `isinstance(x, SupportsFeatures)` (a `runtime_checkable` Protocol) for every row.

**L5 Answer.** "Protocols are the modern typed way; `isinstance` is fast."

**Why L5 Crashes at Scale.** Runtime Protocol checks probe every member with `inspect.getattr_static`. Measured: ≈ 280 ns when the check passes and ≈ 3.2 µs when it fails, against ≈ 23 ns for a concrete class. At 10 M rows that's 2.8–32 seconds of pure checking.

**L7 Principal Defense.** Protocols are a *static* typing tool. Validate types at the boundary once per batch (or once per type, cached in a dict keyed by `type(x)`), not per row. Inside the core rely on mypy or pyright checking the Protocol statically. If runtime dispatch is needed, dispatch on concrete types (`functools.singledispatch`, a dict of handlers). Best of all is a columnar batch with a schema, where there's nothing to check per row (Folder 02).

</details>

<details><summary><b>Q8 · "How does the 3.14/3.15 JIT change your performance advice?"</b></summary>

**Initial Prompt.** With a JIT in CPython, do the old rules (vectorize, avoid attribute lookups in loops) still apply?

**L5 Answer.** "No. The JIT compiles Python to machine code, so loops are fast now."

**Why L5 Crashes at Scale.** The JIT compiles *specialized micro-ops*. It still boxes objects, writes refcounts, checks guards and dispatches through the object model. Measured 1.14–1.19× on a float loop (3.14 notes: −10 % to +20 %; 3.15 reports 7–8 % geomean). That doesn't touch the 20–50× gap to vectorized code, and the JIT is off by default and labelled experimental.

**L7 Principal Defense.** The JIT amplifies the same thing specialization rewards: monomorphic, type-stable, guard-stable code. So the advice gets *stronger*. Keep classes immutable after import, keep hot sites monomorphic, avoid Python-level descriptors and `__getattr__` in loops. The structural lever is still moving the loop out of the interpreter (NumPy, Arrow compute, Polars, Numba/Cython for custom kernels, Triton for GPU, Folders 02 and 06). Benchmark with `PYTHON_JIT=1` in CI to catch regressions, but don't plan capacity around it until it's on by default.

</details>

<details><summary><b>Q9 · "Design a typed record layer for a 10M-row in-memory cache served by Python."</b></summary>

**Initial Prompt.** Product wants rich typed objects (`Order` with validation) and a 10 M-entry cache per pod.

**L5 Answer.** "Use Pydantic models with `__slots__` for memory."

**Why L5 Crashes at Scale.** Pydantic v2 models already use `__slots__` for their internals *plus* a `__dict__` for fields, ~1.1 KB per 5-field record measured, so 10 M is ~11 GB per pod. Adding `__slots__` doesn't help. Validating on every cache read wastes CPU.

**L7 Principal Defense.** Separate representation by tier. Store the cache columnar (Arrow/NumPy columns or a Polars DataFrame) at ~40–60 B per row including strings, about 0.5 GB per pod. Validate once at ingestion with `validate_json` on bytes. Materialize a typed object only at the API edge, for the few rows a request returns: Pydantic for external responses, or `msgspec.Struct` (~235 B) for internal hops. That keeps the developer experience of typed models where humans touch data and the physics of buffers where machines do. Folder 03 builds the columnar side.

</details>

---

## 5. Invariants Checklist

- [ ] Lookup order: data descriptor → instance → non-data descriptor → class attribute → `__getattr__`.
- [ ] Every inline cache guards on the type version tag. Classes mutated at runtime deoptimize; after `MAX_VERSIONS_PER_CLASS` (1000) tags they never specialize again.
- [ ] Specialization is monomorphic. Polymorphic sites cost ~1.7–1.8×; keep hot loops type-stable.
- [ ] Cost ladder per read: attribute/slot 1× < `cached_property` ≈ 1.8× < `property` ≈ 2× < `__getattr__` ≈ 5× < Python data descriptor ≈ 7×.
- [ ] `isinstance` against `runtime_checkable` Protocols costs up to 3.2 µs; keep it out of per-row code.
- [ ] Class-creation hooks run in a fixed order: `__prepare__` → body → `__set_name__` → `__init_subclass__` → metaclass `__init__` → decorators. Metaclasses must forward `**kw`.
- [ ] Generators are heap frames: they pin their locals while suspended, and `close()` runs `finally`.
- [ ] NumPy fixed-width arithmetic wraps silently. Validate ranges when vectorizing Python-int code.
- [ ] Pydantic: `validate_json` on bytes, adapters cached at module level, strict mode for machine contracts, models only at the edges.
- [ ] The 3.14 JIT is experimental and modest (1.14–1.19× here). Vectorization remains the order-of-magnitude lever.

---

## 6. References

**CPython source and docs (pinned)**
- `Objects/object.c` (`_PyObject_GenericGetAttrWithDict`) — https://github.com/python/cpython/blob/v3.14.10/Objects/object.c
- `Objects/typeobject.c` (`assign_version_tag`, `MAX_VERSIONS_PER_CLASS`, `type_new`, `_PyType_AllocNoTrack`) — https://github.com/python/cpython/blob/v3.14.10/Objects/typeobject.c
- `Python/specialize.c` (specialization decisions) — https://github.com/python/cpython/blob/v3.14.10/Python/specialize.c
- Descriptor HowTo Guide — https://docs.python.org/3/howto/descriptor.html
- Data model: customizing class creation — https://docs.python.org/3/reference/datamodel.html#customizing-class-creation
- What's New 3.14 (JIT binaries, `PYTHON_JIT`) — https://docs.python.org/3.14/whatsnew/3.14.html
- What's New 3.15 (upgraded JIT, PEP 810 lazy imports) — https://docs.python.org/3.15/whatsnew/3.15.html

**PEPs**
- PEP 659 — Specializing Adaptive Interpreter: https://peps.python.org/pep-0659/
- PEP 744 — JIT Compilation: https://peps.python.org/pep-0744/
- PEP 487 — Simpler customisation of class creation: https://peps.python.org/pep-0487/
- PEP 3115 — Metaclasses in Python 3000 (`__prepare__`): https://peps.python.org/pep-3115/
- PEP 544 — Protocols: structural subtyping: https://peps.python.org/pep-0544/
- PEP 380 — Syntax for delegating to a subgenerator: https://peps.python.org/pep-0380/
- PEP 810 — Explicit lazy imports: https://peps.python.org/pep-0810/

**Libraries**
- Pydantic v2 performance guide — https://docs.pydantic.dev/latest/concepts/performance/
- pydantic-core (Rust validator) — https://github.com/pydantic/pydantic-core
- jiter (Rust JSON parser used by pydantic-core) — https://github.com/pydantic/jiter
- msgspec — https://github.com/jcrist/msgspec
- H. Xu, F. Kjolstad, "Copy-and-Patch Compilation: A fast compilation algorithm for high-level languages and bytecode" (the technique behind PEP 744), OOPSLA 2021, DOI 10.1145/3485513.
