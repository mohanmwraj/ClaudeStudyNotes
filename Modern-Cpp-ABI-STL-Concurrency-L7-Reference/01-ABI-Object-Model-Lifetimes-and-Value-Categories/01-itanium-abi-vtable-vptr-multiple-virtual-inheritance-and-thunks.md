# 01 · Itanium C++ ABI: vptr, vtable groups, multiple & virtual inheritance, thunks

> **Scope.** What a polymorphic object *is* in memory under the Itanium C++ ABI, the ABI used by every non-MSVC
> C++ toolchain: Linux, Android, macOS/iOS, the BSDs, MinGW and most embedded toolchains. That covers the vptr,
> the vtable group, offset-to-top, RTTI, this-adjusting and virtual thunks, VTTs and construction vtables, and
> pointers to member functions. It also covers what the optimizer can and cannot remove (devirtualization), and
> two hardening variants that change the machine code: AArch64 pointer authentication and relative vtables.

| # | Listing | What it proves | How it was verified |
|---|---|---|---|
| 1.1 | `vt_layout.cpp` | primary vs secondary vptr, thunk, null-checked upcast, `final` devirtualization, `dynamic_cast` fast paths | Clang `-fdump-record-layouts`/`-fdump-vtable-layouts`; `-O3` asm for x86-64, AArch64 and GCC |
| 1.2 | `vt_virtual.cpp` | vbase offsets, virtual thunks, VTT, construction vtables, C1 vs C2 constructors | layout dumps + asm (x86-64, AArch64) |
| 1.3 | `vt_runtime.cpp` | the vtable header read back at run time; vptr swaps during construction/destruction | run under GCC 16.2 and Clang 21.1 (identical output) |
| 1.4 | `pmf.cpp`, `pmf_abi.cpp` | `{ptr, adj}` encoding; ARM moves the virtual bit into `adj`; MSVC ABI sizes 8/16/24 | run + asm; `static_assert` for 3 targets |
| 1.5 | `devirt.cpp` | `final`, speculative devirtualization (GCC), opaque bases | asm (Clang x86-64/AArch64, GCC) |
| 1.6 | `vt_hardening.cpp` | AArch64 PAuth signed vptr + signed slots; relative (32-bit) vtables | asm (`aarch64-linux-pauthtest`, `-fexperimental-relative-c++-abi-vtables`) |
| 1.7 | `rtti_cost.cpp` | measured cost of `typeid` / `dynamic_cast` flavours vs a virtual tag | 3 runs × 2 compilers, ranges reported |
| 1.8 | `cb_cast.cpp` | a `void*` callback context cast to the wrong base: wrong function (Clang), deleted code (GCC) | run, both compilers; GCC `main` control-flow dump |

**Verification line.** Codegen: Clang 21.1.0 (via Zig 0.16) `-O3 -fomit-frame-pointer`, targets
`x86_64-linux-gnu` and `aarch64-linux-gnu` (baseline Armv8.0-A), filtered godbolt-style. GCC 16.2.0
cross-check: the MinGW-w64 build with `-O3 -mabi=sysv`. It gives SysV register assignment and the Itanium C++
ABI, but PE/COFF sections and a 32-bit `long`. Runs: Windows 11 x86-64. GCC 16.2 uses libstdc++ and Clang 21.1
uses libc++; both toolchains use the Itanium C++ ABI (MinGW is not the MSVC ABI). Every listing below is
byte-identical to the file that produced the output under it.

---

## 1. First principles: what the hardware sees

### 1.1 The three rules that generate everything else

1. **Every polymorphic subobject starts with a vptr.** A class with virtual functions, virtual bases or
   polymorphic bases has, at offset 0 of each polymorphic subobject, a pointer into a *vtable group*. The
   primary base (the first non-virtual polymorphic base) shares the derived class's vptr. Every other polymorphic
   base subobject keeps its own vptr.
2. **The vptr points at an *address point*, not at the start of the vtable.** Function pointers sit at
   non-negative offsets from the address point. At negative offsets sit `offset_to_top` (at −16 on LP64), the
   RTTI pointer (at −8) and, for classes with virtual bases, *vbase offsets* and *vcall offsets* further down.
3. **The callee always receives `this` pointing at the subobject whose class declared the function.** If the
   caller holds a pointer to a different subobject, somebody must adjust `this`. Inside one hierarchy the
   compiler adjusts at compile time. Through a secondary vtable a **thunk** does it.

Those three rules explain the size of every object, the shape of every virtual call, and the existence of every
mangled symbol you will meet in a crash dump: `_ZTV` vtable, `_ZTI` typeinfo, `_ZTS` typeinfo name, `_ZTT` VTT,
`_ZTC` construction vtable, `_ZThn` non-virtual thunk, `_ZTv` virtual thunk and `_ZTc` covariant-return thunk.

### 1.2 Listing 1.1: single + multiple inheritance

```cpp
// vt_layout.cpp - Itanium vptr/vtable layout: primary + secondary base, this-adjusting thunks, upcasts, final
#include <cstdint>

struct Shape {                        // polymorphic: vptr at offset 0
    virtual ~Shape();                 // key function: the vtable is emitted only in the TU that defines it
    virtual double area() const = 0;  // pure: the slot holds __cxa_pure_virtual in Shape's own vtable
    virtual int id() const { return 1; }
    std::int32_t tag = 0;
};

struct Named {
    virtual ~Named();
    virtual const char* name() const;
    std::int64_t len = 0;
};

struct Circle final : Shape, Named {  // Shape is the primary base (offset 0); Named-in-Circle is at offset 16
    ~Circle() override;
    double area() const override;
    const char* name() const override;  // reached through Named* -> needs a this-adjusting thunk
    double r = 1.0;
};

Shape::~Shape() = default;
Named::~Named() = default;
const char* Named::name() const { return "named"; }
Circle::~Circle() = default;
double Circle::area() const { return 3.0 * r * r; }
const char* Circle::name() const { return "circle"; }

// Primary-base virtual call: load vptr, load slot, indirect call (tail-call here).
double call_area(const Shape* s) { return s->area(); }
// Secondary-base virtual call: identical code; for a Circle the slot points at the thunk.
const char* call_name(const Named* n) { return n->name(); }
// Pointer upcast to a non-primary base: +16 adjustment, but nullptr must stay nullptr.
const Named* to_named(const Circle* c) { return c; }
// Reference upcast: references are never null, so no test.
const Named& to_named_ref(const Circle& c) { return c; }
// Circle is final: the dynamic type through Circle* is exactly Circle -> direct call, inlined.
const char* call_name_final(const Circle* c) { return c->name(); }
// dynamic_cast to a final class: Clang compares the vptr against Circle's vtable address.
const Circle* down_final(const Shape* s) { return dynamic_cast<const Circle*>(s); }
// dynamic_cast to void*: offset-to-top from the vtable header, no runtime library call.
const void* most_derived(const Named* n) { return dynamic_cast<const void*>(n); }
```

Clang's own record and vtable layout for these classes, dumped by the compiler:

```text
*** Dumping AST Record Layout
         0 | struct Shape
         0 |   (Shape vtable pointer)
         8 |   std::int32_t tag
           | [sizeof=16, dsize=12, align=8,
           |  nvsize=12, nvalign=8]

*** Dumping AST Record Layout
         0 | struct Named
         0 |   (Named vtable pointer)
         8 |   std::int64_t len
           | [sizeof=16, dsize=16, align=8,
           |  nvsize=16, nvalign=8]

*** Dumping AST Record Layout
         0 | struct Circle
         0 |   struct Shape (primary base)
         0 |     (Shape vtable pointer)
         8 |     std::int32_t tag
        16 |   struct Named (base)
        16 |     (Named vtable pointer)
        24 |     std::int64_t len
        32 |   double r
           | [sizeof=40, dsize=40, align=8,
           |  nvsize=40, nvalign=8]

Vtable for 'Circle' (12 entries).
   0 | offset_to_top (0)
   1 | Circle RTTI
       -- (Circle, 0) vtable address --
       -- (Shape, 0) vtable address --
   2 | Circle::~Circle() [complete]
   3 | Circle::~Circle() [deleting]
   4 | double Circle::area() const
   5 | int Shape::id() const
   6 | const char *Circle::name() const
   7 | offset_to_top (-16)
   8 | Circle RTTI
       -- (Named, 16) vtable address --
   9 | Circle::~Circle() [complete]
       [this adjustment: -16 non-virtual] method: Named::~Named()
  10 | Circle::~Circle() [deleting]
       [this adjustment: -16 non-virtual] method: Named::~Named()
  11 | const char *Circle::name() const
       [this adjustment: -16 non-virtual] method: const char *Named::name() const

VTable indices for 'Circle' (4 entries).
   0 | Circle::~Circle() [complete]
   1 | Circle::~Circle() [deleting]
   2 | double Circle::area() const
   4 | const char *Circle::name() const
```

Read the dump as a byte map:

```text
 Circle object: sizeof 40, align 8                vtable group _ZTV6Circle: 12 slots x 8 bytes
 +0  +-------------------------+                  [0]  offset_to_top = 0
     | vptr (Shape, primary) --+------------+     [1]  &_ZTI6Circle            (RTTI of the MOST-derived type)
 +8  | Shape::tag  int32       |            +---> [2]  Circle::~Circle() D1 complete   <- address point +16
 +12 | padding (4)             |                  [3]  Circle::~Circle() D0 deleting
 +16 +-------------------------+                  [4]  Circle::area()
     | vptr (Named-in-Circle) -+------------+     [5]  Shape::id()            (inherited, not overridden)
 +24 | Named::len  int64       |            |     [6]  Circle::name()         (extra primary slot, see below)
 +32 | Circle::r   double      |            |     [7]  offset_to_top = -16
 +40 +-------------------------+            |     [8]  &_ZTI6Circle
                                            +---> [9]  thunk(-16) -> ~Circle() D1   <- address point +72
                                                  [10] thunk(-16) -> ~Circle() D0
                                                  [11] thunk(-16) -> Circle::name()
```

Four things in that map are easy to get wrong in an interview:

* **Destructors take two slots.** D1 is the *complete-object* destructor. D0 is the *deleting* destructor:
  D1 plus `operator delete`, which since C++14 is the sized form `operator delete(void*, size_t)`. The
  *base-object* destructor D2 has no slot of its own. Without virtual bases, D1 and D2 do the same thing, so
  Clang emits D1 as an alias of D2 and the vtable may name the `D2` symbol directly (the PAuth and relative
  listings in §1.7 show `_ZN6WidgetD2Ev` in the D1 slot).
* **`Shape` has `dsize` 12 but `sizeof` 16.** `Named` needs 8-byte alignment, so it starts at +16, not +12.
  Tail-padding reuse (file 04) only happens when the next field fits the gap.
* **Slot 6 exists because of the thunk.** `Circle::name()` overrides a function of a *secondary* base. The
  Itanium ABI then adds a new entry to the **primary** vtable, so that a call through `Circle*` (or `Shape*`
  after a downcast) needs no adjustment. Slot 11 holds the adjusting thunk for callers that hold a `Named*`.
* **The RTTI pointer is the same in both vtables**: the typeinfo of the *most-derived* class. Listing 1.3
  reads it back at run time from the secondary vtable. That is how `typeid(*named_ptr)` gives `Circle`.

The code for the functions in Listing 1.1. Clang x86-64 first, then Clang AArch64:

```asm
_ZNK6Circle4nameEv:                # Circle::name() const
	leaq	.L.str.1(%rip), %rax
	retq

_ZThn16_NK6Circle4nameEv:          # non-virtual thunk to Circle::name() const
	leaq	.L.str.1(%rip), %rax
	retq

_Z9call_areaPK5Shape:              # call_area(Shape const*)
	movq	(%rdi), %rax
	jmpq	*16(%rax)

_Z9call_namePK5Named:              # call_name(Named const*)
	movq	(%rdi), %rax
	jmpq	*16(%rax)

_Z8to_namedPK6Circle:              # to_named(Circle const*)
	leaq	16(%rdi), %rax
	testq	%rdi, %rdi
	cmoveq	%rdi, %rax
	retq

_Z12to_named_refRK6Circle:         # to_named_ref(Circle const&)
	leaq	16(%rdi), %rax
	retq

_Z15call_name_finalPK6Circle:      # call_name_final(Circle const*)
	leaq	.L.str.1(%rip), %rax
	retq

_Z10down_finalPK5Shape:            # down_final(Shape const*)
	testq	%rdi, %rdi
	je	.LBB17_2
	movq	%rdi, %rax
	movq	_ZTV6Circle@GOTPCREL(%rip), %rcx      # vtable for Circle
	addq	$16, %rcx
	cmpq	%rcx, (%rdi)
	je	.LBB17_3
.LBB17_2:
	xorl	%eax, %eax
.LBB17_3:
	retq

_Z12most_derivedPK5Named:          # most_derived(Named const*)
	testq	%rdi, %rdi
	je	.LBB18_1
	movq	%rdi, %rax
	movq	(%rdi), %rcx
	addq	-16(%rcx), %rax
	retq
.LBB18_1:
	xorl	%eax, %eax
	retq

_ZTV6Circle:                       # vtable for Circle
	.quad 0
	.quad _ZTI6Circle                          # typeinfo for Circle
	.quad _ZN6CircleD1Ev                       # Circle::~Circle()
	.quad _ZN6CircleD0Ev                       # Circle::~Circle()
	.quad _ZNK6Circle4areaEv                   # Circle::area() const
	.quad _ZNK5Shape2idEv                      # Shape::id() const
	.quad _ZNK6Circle4nameEv                   # Circle::name() const
	.quad -16
	.quad _ZTI6Circle                          # typeinfo for Circle
	.quad _ZThn16_N6CircleD1Ev                 # non-virtual thunk to Circle::~Circle()
	.quad _ZThn16_N6CircleD0Ev                 # non-virtual thunk to Circle::~Circle()
	.quad _ZThn16_NK6Circle4nameEv             # non-virtual thunk to Circle::name() const

_ZTI6Circle:                       # typeinfo for Circle
	.quad _ZTVN10__cxxabiv121__vmi_class_type_infoE+16 # vtable for __cxxabiv1::__vmi_class_type_info
	.quad _ZTS6Circle                          # typeinfo name for Circle
	.long 0
	.long 2
	.quad _ZTI5Shape                           # typeinfo for Shape
	.quad 2
	.quad _ZTI5Named                           # typeinfo for Named
	.quad 4098
```

```asm
_ZNK6Circle4nameEv:                // Circle::name() const
	adrp	x0, .L.str.1
	add	x0, x0, :lo12:.L.str.1
	ret

_ZThn16_NK6Circle4nameEv:          // non-virtual thunk to Circle::name() const
	adrp	x0, .L.str.1
	add	x0, x0, :lo12:.L.str.1
	ret

_Z9call_areaPK5Shape:              // call_area(Shape const*)
	ldr	x8, [x0]
	ldr	x1, [x8, #16]
	br	x1

_Z9call_namePK5Named:              // call_name(Named const*)
	ldr	x8, [x0]
	ldr	x1, [x8, #16]
	br	x1

_Z8to_namedPK6Circle:              // to_named(Circle const*)
	add	x8, x0, #16
	cmp	x0, #0
	csel	x0, xzr, x8, eq
	ret

_Z12to_named_refRK6Circle:         // to_named_ref(Circle const&)
	add	x0, x0, #16
	ret

_Z15call_name_finalPK6Circle:      // call_name_final(Circle const*)
	adrp	x0, .L.str.1
	add	x0, x0, :lo12:.L.str.1
	ret

_Z10down_finalPK5Shape:            // down_final(Shape const*)
	cbz	x0, .LBB17_2
	adrp	x8, :got:_ZTV6Circle                  // vtable for Circle
	ldr	x8, [x8, :got_lo12:_ZTV6Circle]        // vtable for Circle
	ldr	x9, [x0]
	add	x8, x8, #16
	cmp	x9, x8
	b.eq	.LBB17_3
.LBB17_2:
	mov	x0, xzr
.LBB17_3:
	ret

_Z12most_derivedPK5Named:          // most_derived(Named const*)
	cbz	x0, .LBB18_2
	ldr	x8, [x0]
	ldur	x8, [x8, #-16]
	add	x0, x0, x8
.LBB18_2:
	ret

_ZTV6Circle:                       // vtable for Circle
	.xword 0
	.xword _ZTI6Circle                         // typeinfo for Circle
	.xword _ZN6CircleD1Ev                      // Circle::~Circle()
	.xword _ZN6CircleD0Ev                      // Circle::~Circle()
	.xword _ZNK6Circle4areaEv                  // Circle::area() const
	.xword _ZNK5Shape2idEv                     // Shape::id() const
	.xword _ZNK6Circle4nameEv                  // Circle::name() const
	.xword -16
	.xword _ZTI6Circle                         // typeinfo for Circle
	.xword _ZThn16_N6CircleD1Ev                // non-virtual thunk to Circle::~Circle()
	.xword _ZThn16_N6CircleD0Ev                // non-virtual thunk to Circle::~Circle()
	.xword _ZThn16_NK6Circle4nameEv            // non-virtual thunk to Circle::name() const

_ZTI6Circle:                       // typeinfo for Circle
	.xword _ZTVN10__cxxabiv121__vmi_class_type_infoE+16 // vtable for __cxxabiv1::__vmi_class_type_info
	.xword _ZTS6Circle                         // typeinfo name for Circle
	.word 0
	.word 2
	.xword _ZTI5Shape                          // typeinfo for Shape
	.xword 2
	.xword _ZTI5Named                          // typeinfo for Named
	.xword 4098
```

What the listings prove:

| Function | x86-64 | AArch64 | Why |
|---|---|---|---|
| `call_area` | `mov (%rdi),%rax; jmp *16(%rax)` | `ldr x8,[x0]; ldr x1,[x8,#16]; br x1` | two dependent loads + an indirect tail call; `area` is +16 from the address point (D1 at +0, D0 at +8) |
| `call_name` | identical shape | identical shape | for a `Circle`, `*16(vptr)` is slot 11 of the group, the **thunk** |
| thunk `_ZThn16_…` | `lea .L.str.1(%rip),%rax` | `adrp/add` | the body was inlined into the thunk. In general a thunk is `sub $16,%rdi; jmp target` |
| `to_named` | `lea 16(%rdi); test; cmove` | `add; cmp; csel` | the upcast must keep a null pointer null: a branch-free select |
| `to_named_ref` | `lea 16(%rdi),%rax` | `add x0,x0,#16` | references cannot be null, so there is no test |
| `call_name_final` | `lea "circle"` | `adrp/add` | `final` fixes the dynamic type, so the call is direct, then inlined |
| `down_final` | `cmp vptr, &_ZTV6Circle+16` | `ldr x9,[x0]; cmp` | **Clang**: `dynamic_cast` to a `final` class is one pointer compare |
| `most_derived` | `add -16(vptr),%rdi` | `ldur x8,[x8,#-16]; add` | `dynamic_cast<void*>` = this + offset_to_top, no library call |

> **Two numbering schemes.** Clang's dump counts slots from the start of the group (offset_to_top = slot 0,
> `area` = slot 4). Machine code counts bytes from the address point (`area` = +16). Crash dumps give you the
> second, so convert before you look a slot up.

The typeinfo at the end of the x86-64 listing is a `__vmi_class_type_info` ("virtual or multiple
inheritance"): name, flags = 0, base count = 2, then one `{base typeinfo, offset_flags}` pair per base, where
`offset_flags = (offset << 8) | __public_mask (2) | __virtual_mask (1)`. For `Shape` that is `2` (offset 0,
public). For `Named` it is `4098` = `(16 << 8) | 2`. `__dynamic_cast` walks exactly this structure, so a
cross-cast in a deep hierarchy is a graph walk. Listing 1.7 measures it.

GCC 16.2 on the same source (MinGW build, `-mabi=sysv`) makes two different choices:

```asm
_ZNK6Circle4nameEv:                # Circle::name() const
	leaq	.LC2(%rip), %rax
	ret

_ZThn16_NK6Circle4nameEv:          # non-virtual thunk to Circle::name() const
	leaq	.LC2(%rip), %rax
	ret

_Z9call_areaPK5Shape:              # call_area(Shape const*)
	movq	(%rdi), %rax
	leaq	_ZNK6Circle4areaEv(%rip), %rdx        # Circle::area() const
	movq	16(%rax), %rax
	cmpq	%rdx, %rax
	jne	.L20
	movsd	32(%rdi), %xmm1
	movsd	.LC1(%rip), %xmm0
	mulsd	%xmm1, %xmm0
	mulsd	%xmm1, %xmm0
	ret
.L20:
	jmp	*%rax

_Z9call_namePK5Named:              # call_name(Named const*)
	movq	(%rdi), %rax
	leaq	_ZThn16_NK6Circle4nameEv(%rip), %rdx  # non-virtual thunk to Circle::name() const
	movq	16(%rax), %rax
	cmpq	%rdx, %rax
	je	.L23
	leaq	_ZNK5Named4nameEv(%rip), %rcx         # Named::name() const
	leaq	.LC0(%rip), %rdx
	cmpq	%rcx, %rax
	jne	.L25
	movq	%rdx, %rax
	ret
.L25:
	jmp	*%rax
.L23:
	leaq	.LC2(%rip), %rdx
	movq	%rdx, %rax
	ret

_Z8to_namedPK6Circle:              # to_named(Circle const*)
	xorl	%edx, %edx
	leaq	16(%rdi), %rax
	testq	%rdi, %rdi
	cmove	%rdx, %rax
	ret

_Z12to_named_refRK6Circle:         # to_named_ref(Circle const&)
	leaq	16(%rdi), %rax
	ret

_Z10down_finalPK5Shape:            # down_final(Shape const*)
	testq	%rdi, %rdi
	je	.L31
	xorl	%ecx, %ecx
	leaq	_ZTI6Circle(%rip), %rdx               # typeinfo for Circle
	leaq	_ZTI5Shape(%rip), %rsi                # typeinfo for Shape
	jmp	__dynamic_cast
.L31:
	xorl	%eax, %eax
	ret

_Z12most_derivedPK5Named:          # most_derived(Named const*)
	testq	%rdi, %rdi
	je	.L34
	movq	(%rdi), %rax
	addq	-16(%rax), %rdi
	movq	%rdi, %rax
	ret
.L34:
	xorl	%eax, %eax
	ret

_ZTI6Circle:                       # typeinfo for Circle
	.quad _ZTVN10__cxxabiv121__vmi_class_type_infoE+16 # vtable for __cxxabiv1::__vmi_class_type_info
	.quad _ZTS6Circle                          # typeinfo name for Circle
	.long 0
	.long 2
	.quad _ZTI5Shape                           # typeinfo for Shape
	.quad 2
	.quad _ZTI5Named                           # typeinfo for Named
	.quad 4098

_ZTV6Circle:                       # vtable for Circle
	.quad 0
	.quad _ZTI6Circle                          # typeinfo for Circle
	.quad _ZN6CircleD1Ev                       # Circle::~Circle()
	.quad _ZN6CircleD0Ev                       # Circle::~Circle()
	.quad _ZNK6Circle4areaEv                   # Circle::area() const
	.quad _ZNK5Shape2idEv                      # Shape::id() const
	.quad _ZNK6Circle4nameEv                   # Circle::name() const
	.quad -16
	.quad _ZTI6Circle                          # typeinfo for Circle
	.quad _ZThn16_N6CircleD1Ev                 # non-virtual thunk to Circle::~Circle()
	.quad _ZThn16_N6CircleD0Ev                 # non-virtual thunk to Circle::~Circle()
	.quad _ZThn16_NK6Circle4nameEv             # non-virtual thunk to Circle::name() const
	.long 0
	.long 1074266112
```

* **Speculative devirtualization.** In `call_area` GCC loads the slot and compares it with
  `&Circle::area`. On a match it runs an inlined copy (`3.0*r*r`); otherwise it makes the indirect call. The
  pass is `-fdevirtualize-speculatively`, on at `-O2`. It fires because `Circle` is the only override GCC can
  see. `call_name` gets a two-way guess: Circle's thunk, then `Named::name`.
* **No vptr-compare `dynamic_cast` in this build.** `down_final` calls `__dynamic_cast`. ⚠ This is the MinGW
  target, where typeinfo objects are not guaranteed unique (no ELF symbol interposition, no merged names). A
  Linux-hosted GCC may behave differently, and I could not run one here. Clang does the vptr compare for
  `x86_64-linux-gnu` in the listing above, and the run-time numbers in 1.7 show it also does it for MinGW.

### 1.3 Listing 1.2: virtual inheritance, VTT and construction vtables

With `virtual` bases, the position of the shared base inside an object depends on the **most-derived** class.
`Base` sits at +16 inside a complete `Left`, but at +40 inside a `Join`. The position therefore cannot be a
compile-time constant for a `Left*`, so it is stored in the vtable as a *vbase offset*.

```cpp
// vt_virtual.cpp - virtual inheritance: vbase offsets, virtual thunks, VTT and construction vtables
#include <cstdint>

struct Base {
    virtual ~Base();
    virtual int f() const;
    std::int64_t b = 1;
};
struct Left : virtual Base {          // Base's position inside Left depends on the most-derived class
    Left();
    int f() const override;
    std::int64_t l = 2;
};
struct Right : virtual Base {
    Right();
    virtual int g() const;
    std::int64_t r = 3;
};
struct Join : Left, Right {           // one shared Base subobject, placed after all non-virtual parts
    Join();
    int f() const override;           // final overrider of Base::f, reached through Base* via a virtual thunk
    int g() const override;
    std::int64_t j = 4;
};

Base::~Base() = default;
int Base::f() const { return 10; }
Left::Left() = default;               // C1 (complete) and C2 (base-object, takes a VTT) are both emitted
int Left::f() const { return 20; }
Right::Right() = default;
int Right::g() const { return 30; }
Join::Join() = default;
int Join::f() const { return static_cast<int>(b + j); }
int Join::g() const { return 40; }

// Reading a virtual-base member: the offset of Base inside *p is only known at run time.
std::int64_t read_b(const Left* p) { return p->b; }
// Upcast to a virtual base: same lookup, plus the null check.
const Base* up(const Right* p) { return p; }
// Join* may point at a Join that is itself a base of something bigger: still a run-time lookup.
const Base* up_join(const Join* p) { return p; }

struct Sealed final : Left, Right {   // final: no further derivation, so Base's offset is fixed
    std::int64_t s = 5;
};
// Constant +40 adjustment (plus the null check); no vtable load.
const Base* up_sealed(const Sealed* p) { return p; }
```

```text
*** Dumping AST Record Layout
         0 | struct Left
         0 |   (Left vtable pointer)
         8 |   std::int64_t l
        16 |   struct Base (virtual base)
        16 |     (Base vtable pointer)
        24 |     std::int64_t b
           | [sizeof=32, dsize=32, align=8,
           |  nvsize=16, nvalign=8]

*** Dumping AST Record Layout
         0 | struct Join
         0 |   struct Left (primary base)
         0 |     (Left vtable pointer)
         8 |     std::int64_t l
        16 |   struct Right (base)
        16 |     (Right vtable pointer)
        24 |     std::int64_t r
        32 |   std::int64_t j
        40 |   struct Base (virtual base)
        40 |     (Base vtable pointer)
        48 |     std::int64_t b
           | [sizeof=56, dsize=56, align=8,
           |  nvsize=40, nvalign=8]

Vtable for 'Join' (20 entries).
   0 | vbase_offset (40)
   1 | offset_to_top (0)
   2 | Join RTTI
       -- (Join, 0) vtable address --
       -- (Left, 0) vtable address --
   3 | int Join::f() const
   4 | Join::~Join() [complete]
   5 | Join::~Join() [deleting]
   6 | int Join::g() const
   7 | vbase_offset (24)
   8 | offset_to_top (-16)
   9 | Join RTTI
       -- (Right, 16) vtable address --
  10 | int Join::g() const
       [this adjustment: -16 non-virtual] method: int Right::g() const
  11 | Join::~Join() [complete]
       [this adjustment: -16 non-virtual] method: Right::~Right()
  12 | Join::~Join() [deleting]
       [this adjustment: -16 non-virtual] method: Right::~Right()
  13 | vcall_offset (-40)
  14 | vcall_offset (-40)
  15 | offset_to_top (-40)
  16 | Join RTTI
       -- (Base, 40) vtable address --
  17 | Join::~Join() [complete]
       [this adjustment: 0 non-virtual, -24 vcall offset offset] method: Base::~Base()
  18 | Join::~Join() [deleting]
       [this adjustment: 0 non-virtual, -24 vcall offset offset] method: Base::~Base()
  19 | int Join::f() const
       [this adjustment: 0 non-virtual, -32 vcall offset offset] method: int Base::f() const

VTable indices for 'Join' (4 entries).
   0 | int Join::f() const
   1 | Join::~Join() [complete]
   2 | Join::~Join() [deleting]
   3 | int Join::g() const

Construction vtable for ('Left', 0) in 'Join' (13 entries).
   0 | vbase_offset (40)
   1 | offset_to_top (0)
   2 | Left RTTI
       -- (Left, 0) vtable address --
   3 | int Left::f() const
   4 | Left::~Left() [complete]
   5 | Left::~Left() [deleting]
   6 | vcall_offset (-40)
   7 | vcall_offset (-40)
   8 | offset_to_top (-40)
   9 | Left RTTI
       -- (Base, 40) vtable address --
  10 | Left::~Left() [complete]
       [this adjustment: 0 non-virtual, -24 vcall offset offset] method: Base::~Base()
  11 | Left::~Left() [deleting]
       [this adjustment: 0 non-virtual, -24 vcall offset offset] method: Base::~Base()
  12 | int Left::f() const
       [this adjustment: 0 non-virtual, -32 vcall offset offset] method: int Base::f() const
```

```text
 Join object: sizeof 56 (nvsize 40)              _ZTV4Join (20 slots)
 +0  vptr (Join/Left primary) ---------------->  [0] vbase_offset 40  [1] offset_to_top 0  [2] RTTI
 +8  Left::l                                     [3] Join::f  [4] D1  [5] D0  [6] Join::g   <- +24 address point
 +16 vptr (Right-in-Join) -------------------->  [7] vbase_offset 24  [8] offset_to_top -16  [9] RTTI
 +24 Right::r                                    [10] g thunk(-16)  [11] D1 thunk  [12] D0 thunk  <- +80
 +32 Join::j                                     [13] vcall_offset -40 (f)  [14] vcall_offset -40 (dtor)
 +40 vptr (Base, VIRTUAL) ------------------->   [15] offset_to_top -40  [16] RTTI
 +48 Base::b                                     [17] D1 vthunk  [18] D0 vthunk  [19] f vthunk  <- +136
```

```asm
_ZN4LeftC2Ev:                      # Left::Left()
	movq	(%rsi), %rax
	movq	%rax, (%rdi)
	movq	8(%rsi), %rcx
	movq	-24(%rax), %rax
	movq	%rcx, (%rdi,%rax)
	movq	$2, 8(%rdi)
	retq

_ZN4LeftC1Ev:                      # Left::Left()
	movq	$1, 24(%rdi)
	movq	_ZTV4Left@GOTPCREL(%rip), %rax        # vtable for Left
	leaq	24(%rax), %rcx
	movq	%rcx, (%rdi)
	addq	$80, %rax
	movq	%rax, 16(%rdi)
	movq	$2, 8(%rdi)
	retq

_ZNK4Join1fEv:                     # Join::f() const
	movq	(%rdi), %rax
	movq	-24(%rax), %rcx
	movl	32(%rdi), %eax
	addl	8(%rdi,%rcx), %eax
	retq

_ZTv0_n32_NK4Join1fEv:             # virtual thunk to Join::f() const
	movq	(%rdi), %rax
	movq	-32(%rax), %rax
	leaq	(%rdi,%rax), %rcx
	movq	(%rdi,%rax), %rdx
	movq	-24(%rdx), %rdx
	movl	32(%rdi,%rax), %eax
	addl	8(%rdx,%rcx), %eax
	retq

_Z6read_bPK4Left:                  # read_b(Left const*)
	movq	(%rdi), %rax
	movq	-24(%rax), %rax
	movq	8(%rdi,%rax), %rax
	retq

_Z2upPK5Right:                     # up(Right const*)
	testq	%rdi, %rdi
	je	.LBB17_1
	movq	%rdi, %rax
	movq	(%rdi), %rcx
	addq	-24(%rcx), %rax
	retq
.LBB17_1:
	xorl	%eax, %eax
	retq

_Z7up_joinPK4Join:                 # up_join(Join const*)
	testq	%rdi, %rdi
	je	.LBB18_1
	movq	%rdi, %rax
	movq	(%rdi), %rcx
	addq	-24(%rcx), %rax
	retq
.LBB18_1:
	xorl	%eax, %eax
	retq

_Z9up_sealedPK6Sealed:             # up_sealed(Sealed const*)
	leaq	40(%rdi), %rax
	testq	%rdi, %rdi
	cmoveq	%rdi, %rax
	retq

_ZTT4Join:                         # VTT for Join
	.quad _ZTV4Join+24                         # vtable for Join
	.quad _ZTC4Join0_4Left+24                  # construction vtable for Left-in-Join
	.quad _ZTC4Join0_4Left+80                  # construction vtable for Left-in-Join
	.quad _ZTC4Join16_5Right+24                # construction vtable for Right-in-Join
	.quad _ZTC4Join16_5Right+80                # construction vtable for Right-in-Join
	.quad _ZTV4Join+136                        # vtable for Join
	.quad _ZTV4Join+80                         # vtable for Join
```

```asm
_ZN4LeftC2Ev:                      // Left::Left()
	ldr	x9, [x1]
	mov	w8, #2
	str	x9, [x0]
	ldur	x9, [x9, #-24]
	ldr	x10, [x1, #8]
	str	x8, [x0, #8]
	str	x10, [x0, x9]
	ret

_ZN4LeftC1Ev:                      // Left::Left()
	adrp	x8, :got:_ZTV4Left                    // vtable for Left
	mov	w9, #1
	ldr	x8, [x8, :got_lo12:_ZTV4Left]          // vtable for Left
	add	x10, x8, #80
	add	x8, x8, #24
	stp	x10, x9, [x0, #16]
	mov	w9, #2
	stp	x8, x9, [x0]
	ret

_ZNK4Join1fEv:                     // Join::f() const
	ldr	x8, [x0]
	ldr	w9, [x0, #32]
	ldur	x8, [x8, #-24]
	add	x8, x0, x8
	ldr	w8, [x8, #8]
	add	w0, w9, w8
	ret

_ZTv0_n32_NK4Join1fEv:             // virtual thunk to Join::f() const
	ldr	x8, [x0]
	ldur	x8, [x8, #-32]
	add	x8, x0, x8
	ldr	x9, [x8]
	ldur	x9, [x9, #-24]
	add	x9, x8, x9
	ldr	w8, [x8, #32]
	ldr	w9, [x9, #8]
	add	w0, w8, w9
	ret

_Z6read_bPK4Left:                  // read_b(Left const*)
	ldr	x8, [x0]
	ldur	x8, [x8, #-24]
	add	x8, x0, x8
	ldr	x0, [x8, #8]
	ret

_Z2upPK5Right:                     // up(Right const*)
	cbz	x0, .LBB17_2
	ldr	x8, [x0]
	ldur	x8, [x8, #-24]
	add	x0, x0, x8
.LBB17_2:
	ret

_Z7up_joinPK4Join:                 // up_join(Join const*)
	cbz	x0, .LBB18_2
	ldr	x8, [x0]
	ldur	x8, [x8, #-24]
	add	x0, x0, x8
.LBB18_2:
	ret

_Z9up_sealedPK6Sealed:             // up_sealed(Sealed const*)
	add	x8, x0, #40
	cmp	x0, #0
	csel	x0, xzr, x8, eq
	ret

_ZTT4Join:                         // VTT for Join
	.xword _ZTV4Join+24                        // vtable for Join
	.xword _ZTC4Join0_4Left+24                 // construction vtable for Left-in-Join
	.xword _ZTC4Join0_4Left+80                 // construction vtable for Left-in-Join
	.xword _ZTC4Join16_5Right+24               // construction vtable for Right-in-Join
	.xword _ZTC4Join16_5Right+80               // construction vtable for Right-in-Join
	.xword _ZTV4Join+136                       // vtable for Join
	.xword _ZTV4Join+80                        // vtable for Join
```

How to read it:

* **`read_b(const Left*)`** loads the vptr, then the vbase offset at **address point − 24** (slot 0 is three
  slots before slot 3), adds it to `this`, and reads `b` at +8. That is **three dependent loads** for what
  looks like a member access. In a hot loop over `Left*` this is a pointer-chasing chain.
* **`up_join(const Join*)` is still a run-time lookup.** I first wrote this listing expecting a constant +40,
  and the compiler disagreed: a `Join*` may point at a `Join` that is a base subobject of a bigger class, where
  `Base` lives elsewhere. Only `final` removes the lookup. `up_sealed(const Sealed*)` compiles to
  `lea 40(%rdi)` plus the null select.
* **The virtual thunk `_ZTv0_n32_NK4Join1fEv`** is reached through `Base*`. It cannot know a fixed adjustment,
  because `Base` may sit at different offsets in different most-derived classes. So it loads a **vcall offset**
  (slot 13, at address point −32) to find the final overrider's `this`. The name encodes this: `v0_n32` =
  non-virtual adjustment 0, vcall offset at −32.
* **Two constructors.** `_ZN4LeftC1Ev` (C1, complete-object) builds the virtual base itself: it stores
  `b = 1` at +24 and points both vptrs into `_ZTV4Left`. `_ZN4LeftC2Ev` (C2, base-object) receives a
  **VTT pointer** in `%rsi` / `x1`. It installs vptrs from the VTT and never touches `Base::b`, because the
  most-derived constructor owns virtual-base construction.
* **The VTT** (`_ZTT4Join`, 7 entries) is a table of vtable addresses that `Join`'s constructor hands to its
  bases' C2 constructors. Entries 1–4 point into **construction vtables** (`_ZTC4Join0_4Left` = "Left-in-Join").
  While `Left`'s constructor runs inside a `Join`, the object must *behave as a `Left`*: virtual calls go to
  `Left::f`. But its virtual base is already at the `Join` position (+40), so neither `_ZTV4Left` (vbase at
  +16) nor `_ZTV4Join` (final overriders) is correct.

### 1.4 Listing 1.3: the ABI observed at run time

```cpp
// vt_runtime.cpp - observe the Itanium ABI at run time: vtable header, subobject offsets, vptr swaps in ctor/dtor
// Implementation-specific by design: it reads the vtable header that the Itanium C++ ABI (section 2.5) defines.
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <print>
#include <typeinfo>

namespace abi {
struct VtableHeader {                 // the two words in front of every address point
    std::ptrdiff_t offset_to_top;     // subobject address + offset_to_top == most-derived object address
    const std::type_info* rtti;       // typeinfo of the MOST-DERIVED type, shared by all secondary vtables
};
inline const void* vptr_of(const void* obj) {
    const void* vp;
    std::memcpy(&vp, obj, sizeof vp);  // the vptr is the first word of every polymorphic (sub)object
    return vp;
}
inline const VtableHeader* header_of(const void* obj) { return static_cast<const VtableHeader*>(vptr_of(obj)) - 1; }
inline std::ptrdiff_t byte_offset(const void* from, const void* to) {
    return static_cast<const char*>(to) - static_cast<const char*>(from);
}
}  // namespace abi

struct Shape {
    virtual ~Shape() = default;
    virtual double area() const = 0;
    std::int32_t tag = 7;
};
struct Named {
    virtual ~Named() = default;
    virtual const char* name() const { return "named"; }
    std::int64_t len = 0;
};
struct Circle final : Shape, Named {
    double area() const override { return 3.0 * r * r; }
    const char* name() const override { return "circle"; }
    double r = 2.0;
};

// ---- vptr swaps during construction and destruction ----
const void* g_tracer_vptr = nullptr;
const void* g_derived_vptr = nullptr;
bool g_quiet = true;

struct Tracer {
    Tracer() { report("Tracer()"); }
    virtual ~Tracer() { report("~Tracer()"); }
    virtual const char* who() const { return "Tracer"; }
    void report(const char* where) const {
        if (g_quiet) return;
        const void* vp = abi::vptr_of(this);
        std::println("  {:<11} who()={:<8} typeid={:<9} vptr={}", where, who(), typeid(*this).name(),
                     vp == g_tracer_vptr ? "Tracer's" : vp == g_derived_vptr ? "Derived's" : "other");
    }
};
struct Derived final : Tracer {
    Derived() { report("Derived()"); }
    ~Derived() override { report("~Derived()"); }
    const char* who() const override { return "Derived"; }
};

int main() {
    Circle c;
    const Shape* s = &c;
    const Named* n = &c;
    std::println("sizeof: Shape={} Named={} Circle={}", sizeof(Shape), sizeof(Named), sizeof(Circle));
    std::println("Named-in-Circle at +{}, Shape-in-Circle at +{}", abi::byte_offset(&c, n), abi::byte_offset(&c, s));
    std::println("primary   header: offset_to_top={:>3} rtti={}", abi::header_of(s)->offset_to_top,
                 abi::header_of(s)->rtti->name());
    std::println("secondary header: offset_to_top={:>3} rtti={}", abi::header_of(n)->offset_to_top,
                 abi::header_of(n)->rtti->name());
    std::println("rtti pointers identical across both headers: {}", abi::header_of(s)->rtti == abi::header_of(n)->rtti);
    std::println("typeid(*n) == typeid(Circle): {}", typeid(*n) == typeid(Circle));
    std::println("dynamic_cast<const void*>(n) == &c: {}", dynamic_cast<const void*>(n) == &c);
    std::println("n->name() via secondary vptr: {}", n->name());

    {
        Tracer t;
        Derived d;
        g_tracer_vptr = abi::vptr_of(&t);
        g_derived_vptr = abi::vptr_of(&d);
    }
    std::println("construct + destroy a Derived:");
    g_quiet = false;
    { Derived d; }
    g_quiet = true;
}
```

Output (verified, GCC 16.2 and Clang 21.1 print the same text):

```text
sizeof: Shape=16 Named=16 Circle=40
Named-in-Circle at +16, Shape-in-Circle at +0
primary   header: offset_to_top=  0 rtti=6Circle
secondary header: offset_to_top=-16 rtti=6Circle
rtti pointers identical across both headers: true
typeid(*n) == typeid(Circle): true
dynamic_cast<const void*>(n) == &c: true
n->name() via secondary vptr: circle
construct + destroy a Derived:
  Tracer()    who()=Tracer   typeid=6Tracer   vptr=Tracer's
  Derived()   who()=Derived  typeid=7Derived  vptr=Derived's
  ~Derived()  who()=Derived  typeid=7Derived  vptr=Derived's
  ~Tracer()   who()=Tracer   typeid=6Tracer   vptr=Tracer's
```

The second half is the **construction/destruction state machine** of the vptr. It is the reason a virtual call
from a constructor "does not dispatch to the derived class": the derived class's vptr has not been stored yet.

```text
 Derived d;                     vptr value                 virtual call resolves to
 ---------------------------    -------------------------  ------------------------
 enter Tracer::Tracer()         &_ZTV6Tracer + 16          Tracer::who        (Derived members not built)
 enter Derived::Derived()       &_ZTV7Derived + 16         Derived::who
 ...object fully constructed...
 enter Derived::~Derived()      &_ZTV7Derived + 16         Derived::who
 enter Tracer::~Tracer()        &_ZTV6Tracer + 16 (re-stored on entry)   Tracer::who  (Derived members gone)
```

Two production consequences follow. A *pure* virtual call during construction or destruction lands in
`__cxa_pure_virtual`, which reports the error and calls `std::terminate`. And a **second thread** that calls a
virtual function on an object being destroyed races with these vptr stores. That race is Q&A chain 2.

### 1.5 Listing 1.4: pointers to member functions

A pointer to member function must handle three cases: a non-virtual function, a virtual function (resolved
against the object's vptr *at call time*), and a `this` adjustment when the function belongs to a non-primary
base. The Itanium ABI uses two words, `{ptr, adj}`.

```cpp
// pmf.cpp - pointer-to-member-function representation: Itanium {ptr, adj} on x86-64 vs the ARM variant on AArch64
#include <cstdint>
#include <cstring>
#include <print>

struct A {
    virtual ~A() = default;
    virtual int v1() { return 1; }    // vtable slot 2 -> byte offset 16 (slots 0/1 are the two destructors)
    int nv() { return 2; }
    int a = 0;
};
struct B {
    virtual ~B() = default;
    virtual int w() { return 3; }
    int b = 0;
};
struct C : A, B {                     // B-in-C at +16
    int w() override { return 4; }
};

using PmfC = int (C::*)();

// The call sequence: decode {ptr, adj}, adjust this, then either call ptr or fetch it from the vtable.
int call(C* c, PmfC pmf) { return (c->*pmf)(); }
// Materialize constants so the encoding is visible in the assembly of each target.
PmfC make_virtual() { return &C::v1; }
PmfC make_nonvirtual() { return &C::nv; }
PmfC make_from_b() { return static_cast<int (C::*)()>(&B::w); }  // adj = +16 to reach B-in-C

struct Raw {
    std::uintptr_t ptr;
    std::intptr_t adj;
};
static Raw raw(PmfC p) {
    static_assert(sizeof(PmfC) == sizeof(Raw), "Itanium: a PMF is two words");
    Raw r;
    std::memcpy(&r, &p, sizeof r);
    return r;
}

int main() {
    C c;
    Raw rv = raw(make_virtual()), rn = raw(make_nonvirtual()), rb = raw(make_from_b());
    std::println("sizeof(int (C::*)()) = {}, sizeof(int C::*) = {}", sizeof(PmfC), sizeof(int C::*));
    std::println("&C::v1 : ptr={:#x} (1 + vtable offset)  adj={}", rv.ptr, rv.adj);
    std::println("&C::nv : ptr is a code address ({}), adj={}", (rn.ptr & 1) ? "odd!" : "even", rn.adj);
    std::println("&B::w  : ptr={:#x} adj={}", rb.ptr, rb.adj);
    std::println("calls  : v1={} nv={} w={}", call(&c, make_virtual()), call(&c, make_nonvirtual()),
                 call(&c, make_from_b()));
    std::println("null data-member pointer is all-ones: {}", [] {
        int C::* pm = nullptr;
        std::intptr_t bits;
        std::memcpy(&bits, &pm, sizeof bits);
        return bits == -1;
    }());
}
```

Output on Windows x86-64 (verified, both compilers):

```text
sizeof(int (C::*)()) = 16, sizeof(int C::*) = 8
&C::v1 : ptr=0x11 (1 + vtable offset)  adj=0
&C::nv : ptr is a code address (even), adj=0
&B::w  : ptr=0x11 adj=16
calls  : v1=1 nv=2 w=4
null data-member pointer is all-ones: true
```

```asm
_Z4callP1CMS_FivE:                 # call(C*, int (C::*)())
	addq	%rdx, %rdi
	testb	$1, %sil
	je	.LBB0_2
	movq	(%rdi), %rax
	movq	-1(%rax,%rsi), %rsi
.LBB0_2:
	jmpq	*%rsi

_Z12make_virtualv:                 # make_virtual()
	movl	$17, %eax
	xorl	%edx, %edx
	retq

_Z15make_nonvirtualv:              # make_nonvirtual()
	movq	_ZN1A2nvEv@GOTPCREL(%rip), %rax       # A::nv()
	xorl	%edx, %edx
	retq

_Z11make_from_bv:                  # make_from_b()
	movl	$17, %eax
	movl	$16, %edx
	retq
```

```asm
_Z4callP1CMS_FivE:                 // call(C*, int (C::*)())
	add	x0, x0, x2, asr #1
	tbz	w2, #0, .LBB0_2
	ldr	x8, [x0]
	ldr	x1, [x8, x1]
.LBB0_2:
	br	x1

_Z12make_virtualv:                 // make_virtual()
	mov	w0, #16
	mov	w1, #1
	ret

_Z15make_nonvirtualv:              // make_nonvirtual()
	adrp	x0, :got:_ZN1A2nvEv                   // A::nv()
	mov	x1, xzr
	ldr	x0, [x0, :got_lo12:_ZN1A2nvEv]         // A::nv()
	ret

_Z11make_from_bv:                  // make_from_b()
	mov	w0, #16
	mov	w1, #33
	ret
```

| | generic Itanium (x86-64) | ARM variant (AArch64, also 32-bit ARM) |
|---|---|---|
| non-virtual | `ptr` = code address, `adj` = byte adjustment | `ptr` = code address, `adj` = 2 × adjustment |
| virtual | `ptr` = 1 + vtable byte offset (odd = virtual) | `ptr` = vtable byte offset, `adj` = 2 × adjustment **+ 1** |
| test at call time | `testb $1, %sil` (low bit of **ptr**) | `tbz w2, #0` (low bit of **adj**) |
| `&C::v1` (slot at +16) | `{17, 0}` | `{16, 1}` |
| `&B::w` seen as `int (C::*)()` | `{17, 16}` | `{16, 33}` |

Why ARM moved the flag: in 32-bit ARM, Thumb function addresses are odd, so the low bit of `ptr` was not free.
The AArch64 C++ ABI kept the same encoding. Code that serializes PMFs, hashes their bits or stores them in
`uintptr_t` therefore produces different values per architecture. And on the MSVC ABI the *size* changes with
the inheritance model:

```cpp
// pmf_abi.cpp - sizeof(pointer to member function): always 2 words on Itanium, 1-3 words on the MSVC ABI
// Self-contained (no headers) so it compiles for Itanium and MSVC targets alike.
struct Single { int f(); };
struct A { int a; };
struct B { int b; };
struct Multi : A, B { int f(); };
struct Virt : virtual A { int f(); };
struct Unknown;                        // incomplete: the MSVC ABI must assume the most general model

using PSingle = int (Single::*)();
using PMulti = int (Multi::*)();
using PVirt = int (Virt::*)();
using PUnknown = int (Unknown::*)();

#if defined(_MSC_VER)
static_assert(sizeof(PSingle) == 8, "MSVC: single inheritance = code pointer only");
static_assert(sizeof(PMulti) == 16, "MSVC: multiple inheritance = code pointer + this adjustment");
static_assert(sizeof(PVirt) == 16, "MSVC: virtual inheritance = + vbtable index");
static_assert(sizeof(PUnknown) == 24, "MSVC: unknown inheritance = the general 3-field form");
#else
static_assert(sizeof(PSingle) == 16 && sizeof(PMulti) == 16 && sizeof(PVirt) == 16 && sizeof(PUnknown) == 16,
              "Itanium: {ptr, adj} for every class");
#endif

int sizes() { return int(sizeof(PSingle) + sizeof(PMulti) + sizeof(PVirt) + sizeof(PUnknown)); }
```

```text
x86_64-linux-gnu           static_asserts hold
aarch64-linux-gnu          static_asserts hold
x86_64-pc-windows-msvc     static_asserts hold
```

### 1.6 Listing 1.5: devirtualization, and what blocks it

```cpp
// devirt.cpp - when the optimizer can remove a virtual call: final, speculative devirtualization, opaque bases
struct Codec {
    virtual ~Codec();
    virtual int encode(int x) const = 0;
};
struct Doubler final : Codec {        // final: Doubler* / Doubler& has exactly this dynamic type
    int encode(int x) const override { return 2 * x; }
};
struct Tripler : Codec {              // not final: a subclass of Tripler may override encode()
    int encode(int x) const override { return 3 * x; }
};
Codec::~Codec() = default;

// Opaque base: an indirect call (Clang); GCC guesses the only override it can see and tests the guess.
int one_base(const Codec& c, int x) { return c.encode(x); }
// final: direct call, inlined to a single LEA / LSL.
int one_final(const Doubler& d, int x) { return d.encode(x); }
// Non-final derived: still a virtual call, even though Tripler::encode is visible and inline.
int one_tripler(const Tripler& t, int x) { return t.encode(x); }
// The loop form: the vptr and slot are re-loaded on every iteration because encode() is opaque.
int sum_base(const Codec& c, const int* p, int n) {
    int s = 0;
    for (int i = 0; i < n; ++i) s += c.encode(p[i]);
    return s;
}
```

Clang, x86-64 then AArch64:

```asm
_Z8one_baseRK5Codeci:              # one_base(Codec const&, int)
	movq	(%rdi), %rax
	movq	16(%rax), %rax
	jmpq	*%rax

_Z9one_finalRK7Doubleri:           # one_final(Doubler const&, int)
	leal	(%rsi,%rsi), %eax
	retq

_Z11one_triplerRK7Tripleri:        # one_tripler(Tripler const&, int)
	movq	(%rdi), %rax
	movq	16(%rax), %rax
	jmpq	*%rax

_Z8sum_baseRK5CodecPKii:           # sum_base(Codec const&, int const*, int)
	pushq	%rbp
	pushq	%r15
	pushq	%r14
	pushq	%r12
	pushq	%rbx
	testl	%edx, %edx
	jle	.LBB5_1
	movq	%rsi, %rbx
	movq	%rdi, %r14
	movl	%edx, %r15d
	xorl	%r12d, %r12d
	xorl	%ebp, %ebp
.LBB5_4:
	movl	(%rbx,%r12,4), %esi
	movq	(%r14), %rax
	movq	%r14, %rdi
	callq	*16(%rax)
	addl	%eax, %ebp
	addq	$1, %r12
	cmpq	%r12, %r15
	jne	.LBB5_4
	jmp	.LBB5_2
.LBB5_1:
	xorl	%ebp, %ebp
.LBB5_2:
	movl	%ebp, %eax
	popq	%rbx
	popq	%r12
	popq	%r14
	popq	%r15
	popq	%rbp
	retq
```

```asm
_Z8one_baseRK5Codeci:              // one_base(Codec const&, int)
	ldr	x8, [x0]
	ldr	x2, [x8, #16]
	br	x2

_Z9one_finalRK7Doubleri:           // one_final(Doubler const&, int)
	lsl	w0, w1, #1
	ret

_Z11one_triplerRK7Tripleri:        // one_tripler(Tripler const&, int)
	ldr	x8, [x0]
	ldr	x2, [x8, #16]
	br	x2

_Z8sum_baseRK5CodecPKii:           // sum_base(Codec const&, int const*, int)
	str	x30, [sp, #-48]!
	stp	x22, x21, [sp, #16]
	stp	x20, x19, [sp, #32]
	cmp	w2, #1
	b.lt	.LBB5_3
	mov	x19, x1
	mov	x21, x0
	mov	w20, wzr
	mov	w22, w2
.LBB5_2:
	ldr	x8, [x21]
	ldr	w1, [x19], #4
	mov	x0, x21
	ldr	x8, [x8, #16]
	blr	x8
	subs	x22, x22, #1
	add	w20, w0, w20
	b.ne	.LBB5_2
	b	.LBB5_4
.LBB5_3:
	mov	w20, wzr
.LBB5_4:
	mov	w0, w20
	ldp	x20, x19, [sp, #32]
	ldp	x22, x21, [sp, #16]
	ldr	x30, [sp], #48
	ret
```

GCC 16.2 (`-O3 -mabi=sysv`). Note the speculative guesses and the vectorized tail in `sum_base`:

<details><summary>GCC listing (139 lines)</summary>

```asm
_Z8one_baseRK5Codeci:              # one_base(Codec const&, int)
	movq	(%rdi), %rax
	leaq	_ZNK7Doubler6encodeEi(%rip), %rdx     # Doubler::encode(int) const
	movq	16(%rax), %rax
	cmpq	%rdx, %rax
	je	.L10
	leaq	_ZNK7Tripler6encodeEi(%rip), %rdx     # Tripler::encode(int) const
	cmpq	%rdx, %rax
	jne	.L9
	leal	(%rsi,%rsi,2), %eax
	ret
.L9:
	jmp	*%rax
.L10:
	leal	(%rsi,%rsi), %eax
	ret

_Z9one_finalRK7Doubleri:           # one_final(Doubler const&, int)
	leal	(%rsi,%rsi), %eax
	ret

_Z11one_triplerRK7Tripleri:        # one_tripler(Tripler const&, int)
	movq	(%rdi), %rax
	leaq	_ZNK7Tripler6encodeEi(%rip), %rdx     # Tripler::encode(int) const
	movq	16(%rax), %rax
	cmpq	%rdx, %rax
	jne	.L17
	leal	(%rsi,%rsi,2), %eax
	ret
.L17:
	jmp	*%rax

_Z8sum_baseRK5CodecPKii:           # sum_base(Codec const&, int const*, int)
	subq	$72, %rsp
	movq	%rbp, 32(%rsp)
	testl	%edx, %edx
	jle	.L29
	movl	%edx, 12(%rsp)
	xorl	%ebp, %ebp
	movq	%rbx, 24(%rsp)
	movl	$1, %ebx
	movq	%r12, 40(%rsp)
	leaq	_ZNK7Doubler6encodeEi(%rip), %r12     # Doubler::encode(int) const
	movq	%r13, 48(%rsp)
	movq	%rsi, %r13
	movq	%r14, 56(%rsp)
	movl	%edx, %r14d
	movq	%r15, 64(%rsp)
	leaq	_ZNK7Tripler6encodeEi(%rip), %r15     # Tripler::encode(int) const
.L27:
	movq	(%rdi), %rax
	movl	-4(%r13,%rbx,4), %esi
	movq	16(%rax), %rax
	cmpq	%r12, %rax
	je	.L36
	cmpq	%r15, %rax
	jne	.L22
	leal	(%rsi,%rsi,2), %eax
	addl	%eax, %ebp
	cmpq	%rbx, %r14
	je	.L35
.L28:
	addq	$1, %rbx
	jmp	.L27
.L22:
	movq	%rdi, (%rsp)
	call	*%rax
	movq	(%rsp), %rdi
	addl	%eax, %ebp
	cmpq	%rbx, %r14
	jne	.L28
.L35:
	movl	%ebp, %eax
	movq	24(%rsp), %rbx
	movq	40(%rsp), %r12
	movq	48(%rsp), %r13
	movq	56(%rsp), %r14
	movq	64(%rsp), %r15
	movq	32(%rsp), %rbp
	addq	$72, %rsp
	ret
.L36:
	leal	0(%rbp,%rsi,2), %ebp
	cmpq	%rbx, %r14
	je	.L35
	movl	12(%rsp), %edi
	movl	%ebx, %ecx
	subl	%ebx, %edi
	leal	-1(%rdi), %eax
	cmpl	$2, %eax
	jbe	.L25
	movl	%edi, %esi
	leaq	0(%r13,%rbx,4), %rax
	pxor	%xmm1, %xmm1
	shrl	$2, %esi
	movl	%esi, %edx
	salq	$4, %rdx
	addq	%rax, %rdx
.L24:
	movdqu	(%rax), %xmm0
	addq	$16, %rax
	pslld	$1, %xmm0
	paddd	%xmm0, %xmm1
	cmpq	%rax, %rdx
	jne	.L24
	movdqa	%xmm1, %xmm0
	sall	$2, %esi
	psrldq	$8, %xmm0
	paddd	%xmm0, %xmm1
	movdqa	%xmm1, %xmm0
	psrldq	$4, %xmm0
	paddd	%xmm0, %xmm1
	movd	%xmm1, %eax
	addl	%eax, %ebp
	cmpl	%esi, %edi
	je	.L35
	addl	%esi, %ecx
.L25:
	movl	%ecx, %eax
	movl	12(%rsp), %ebx
	movl	0(%r13,%rax,4), %edx
	leal	0(%rbp,%rdx,2), %ebp
	leal	1(%rcx), %edx
	cmpl	%edx, %ebx
	jle	.L35
	movl	4(%r13,%rax,4), %edx
	addl	$2, %ecx
	leal	0(%rbp,%rdx,2), %ebp
	cmpl	%ecx, %ebx
	jle	.L35
	movl	8(%r13,%rax,4), %eax
	leal	0(%rbp,%rax,2), %ebp
	jmp	.L35
.L29:
	xorl	%ebp, %ebp
	movl	%ebp, %eax
	movq	32(%rsp), %rbp
	addq	$72, %rsp
	ret
```

</details>

What the three compilers' outputs say:

* `one_final` compiles to `lea (%rsi,%rsi),%eax` / `lsl w0,w1,#1`. `final` on the **class**, or on the
  function, is the only portable, LTO-free way to promise "no further overriders".
* `one_tripler` stays virtual on Clang even though `Tripler::encode` is inline and visible. A class derived
  from `Tripler` in another TU could override it.
* `sum_base` on Clang **reloads the vptr and the slot on every iteration** (`movq (%r14),%rax` is inside the
  loop). The callee could have destroyed `*c` and placement-new'ed a different type into it (file 03,
  `std::launder`). GCC compares once per iteration and, after the first `Doubler` hit, *vectorizes the rest of
  the loop* (`pslld $1` / `paddd`). It has proved that the inlined `Doubler::encode` cannot change the dynamic
  type.
* Clang's equivalents are opt-in: `-fstrict-vtable-pointers` (file 03 shows it change code) and
  `-fwhole-program-vtables` with LTO. ⚠ The second needs an LTO link, which this harness does not perform.

### 1.7 Listing 1.6: hardening changes the machine code (AArch64 PAuth, relative vtables)

```cpp
// vt_hardening.cpp - the same virtual call under AArch64 PAuth (signed vptr + signed slots) and relative vtables
// Self-contained (no headers): the pauthtest target has no libc++ in this toolchain.
struct Widget {
    virtual ~Widget();
    virtual int draw() const;
    int state = 0;
};
Widget::~Widget() {}
int Widget::draw() const { return state; }

// Plain Itanium: ldr vptr; ldr slot; br.
// PAuth ABI: autda the vptr (discriminator = object address blended with a type hash), then braa through the
// slot (discriminator = slot address blended with a per-method hash). A copied/forged vptr fails authentication.
// Relative vtables: each slot is a 32-bit PC-relative offset, so the vtable needs no dynamic relocations.
int render(const Widget* w) { return w->draw(); }
```

Plain AArch64:

```asm
_Z6renderPK6Widget:                // render(Widget const*)
	ldr	x8, [x0]
	ldr	x1, [x8, #16]
	br	x1

_ZTV6Widget:                       // vtable for Widget
	.xword 0
	.xword _ZTI6Widget                         // typeinfo for Widget
	.xword _ZN6WidgetD1Ev                      // Widget::~Widget()
	.xword _ZN6WidgetD0Ev                      // Widget::~Widget()
	.xword _ZNK6Widget4drawEv                  // Widget::draw() const
```

AArch64 with the **PAuth ABI** (`aarch64-unknown-linux-pauthtest`, the Linux test environment for the
pointer-authentication C++ ABI that arm64e also uses):

```asm
_Z6renderPK6Widget:                // render(Widget const*)
	ldr	x1, [x0]
	mov	x8, x0
	movk	x8, #5065, lsl #48
	autda	x1, x8
	mov	x8, x1
	xpacd	x8
	cmp	x1, x8
	b.eq	.Lauth_success_0
	brk	#0xc472
.Lauth_success_0:
	ldr	x2, [x1, #16]!
	movk	x1, #32773, lsl #48
	braa	x2, x1

_ZTV6Widget:                       // vtable for Widget
	.xword 0
	.xword _ZTI6Widget                         // typeinfo for Widget
	.xword _ZN6WidgetD2Ev@AUTH(ia,47018,addr)  // Widget::~Widget()
	.xword _ZN6WidgetD0Ev@AUTH(ia,31211,addr)  // Widget::~Widget()
	.xword _ZNK6Widget4drawEv@AUTH(ia,32773,addr) // Widget::draw() const
```

* The **vptr is signed** with the DA key. The discriminator is the *object's address* blended with a 16-bit
  constant (`movk x8, #5065, lsl #48`). `autda` authenticates it. On failure the code reaches `brk #0xc472`, a
  deliberate trap, before any dereference happens.
* **Each vtable slot is signed** with the IA key and an address-discriminated, per-method constant
  (`@AUTH(ia,32773,addr)`). `braa x2, x1` authenticates and branches in one instruction, and the call site uses
  the same constant 32773 that the vtable entry was signed with.
* **Consequence.** Copying a live polymorphic object with `memcpy` to a different address produces a vptr whose
  signature is bound to the *old* address. The next virtual call traps. On x86-64 the same copy "works", but it
  is UB in both cases. File 04 shows why this matters for trivial relocation.

**Relative vtables** (`-fexperimental-relative-c++-abi-vtables`, built for Fuchsia): each slot is a 32-bit
PC-relative offset, so vtables need no dynamic relocations and can live in read-only, shareable pages.

```asm
_Z6renderPK6Widget:                # render(Widget const*)
	movq	(%rdi), %rax
	movslq	8(%rax), %rcx
	addq	%rax, %rcx
	jmpq	*%rcx

_ZTV6Widget.local:                 # vtable for Widget [clone .local]
	.long 0
	.long _ZTI6Widget@GOTPCREL-4               # typeinfo for Widget
	.long _ZN6WidgetD2Ev@PLT-_ZTV6Widget.local-8 # Widget::~Widget(), vtable for Widget [clone .local]
	.long _ZN6WidgetD0Ev@PLT-_ZTV6Widget.local-8 # Widget::~Widget(), vtable for Widget [clone .local]
	.long _ZNK6Widget4drawEv@PLT-_ZTV6Widget.local-8 # Widget::draw() const, vtable for Widget [clone .local]
```

The call sequence grows by one instruction (`movslq 8(%rax),%rcx; addq %rax,%rcx`), the vtable halves in size,
and the relocation count drops. That is the trade for large binaries with many vtables. Relative vtables are an
**ABI break**: every TU and library must agree.

### 1.8 Listing 1.7: what RTTI actually costs

```cpp
// rtti_cost.cpp - measured cost of RTTI operations vs a virtual tag (single thread, one run, ns per operation)
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <print>
#include <typeinfo>
#include <vector>

struct Node {
    virtual ~Node() = default;
    virtual int kind() const = 0;
};
struct L1 : Node {};
struct L2 : L1 {};
struct L3 : L2 {};
struct L4 : L3 {};
struct Mixin {
    virtual ~Mixin() = default;
    int m = 1;
};
struct Leaf final : L4, Mixin {       // depth 5 + a second base for the cross-cast
    int kind() const override { return 1; }
};
struct Other final : Node {
    int kind() const override { return 2; }
};

template <class F>
static void bench(const char* label, const std::vector<Node*>& v, F f) {
    constexpr int kRounds = 200;
    std::size_t hits = 0;
    auto t0 = std::chrono::steady_clock::now();
    for (int r = 0; r < kRounds; ++r)
        for (Node* p : v) hits += f(p) ? 1u : 0u;
    auto t1 = std::chrono::steady_clock::now();
    double ns = std::chrono::duration<double, std::nano>(t1 - t0).count() / (double(kRounds) * double(v.size()));
    std::println("  {:<34} {:6.2f} ns/op  (hits={})", label, ns, hits);
}

int main() {
    std::vector<std::unique_ptr<Node>> owned;
    std::vector<Node*> v;
    std::uint32_t x = 12345;            // xorshift: an unpredictable Leaf/Other mix
    for (int i = 0; i < 50'000; ++i) {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        if (x & 1) owned.push_back(std::make_unique<Leaf>());
        else owned.push_back(std::make_unique<Other>());
        v.push_back(owned.back().get());
    }
    std::println("10M operations each over a random 50/50 Leaf/Other array:");
    bench("virtual tag: p->kind() == 1", v, [](Node* p) { return p->kind() == 1; });
    bench("typeid(*p) == typeid(Leaf)", v, [](Node* p) { return typeid(*p) == typeid(Leaf); });
    bench("dynamic_cast<Leaf*> (final)", v, [](Node* p) { return dynamic_cast<Leaf*>(p) != nullptr; });
    bench("dynamic_cast<L2*>   (mid-chain)", v, [](Node* p) { return dynamic_cast<L2*>(p) != nullptr; });
    bench("dynamic_cast<Mixin*> (cross-cast)", v, [](Node* p) { return dynamic_cast<Mixin*>(p) != nullptr; });
    bench("dynamic_cast<void*>", v, [](Node* p) { return dynamic_cast<void*>(p) != nullptr; });
}
```

One run (GCC 16.2 + libstdc++, then Clang 21.1 + libc++, same laptop):

```text
10M operations each over a random 50/50 Leaf/Other array:
  virtual tag: p->kind() == 1          4.28 ns/op  (hits=4986600)
  typeid(*p) == typeid(Leaf)           6.78 ns/op  (hits=4986600)
  dynamic_cast<Leaf*> (final)         13.77 ns/op  (hits=4986600)
  dynamic_cast<L2*>   (mid-chain)     33.08 ns/op  (hits=4986600)
  dynamic_cast<Mixin*> (cross-cast)   38.54 ns/op  (hits=4986600)
  dynamic_cast<void*>                  0.35 ns/op  (hits=10000000)
```

```text
10M operations each over a random 50/50 Leaf/Other array:
  virtual tag: p->kind() == 1          5.48 ns/op  (hits=4986600)
  typeid(*p) == typeid(Leaf)           6.07 ns/op  (hits=4986600)
  dynamic_cast<Leaf*> (final)          3.96 ns/op  (hits=4986600)
  dynamic_cast<L2*>   (mid-chain)     26.02 ns/op  (hits=4986600)
  dynamic_cast<Mixin*> (cross-cast)   35.75 ns/op  (hits=4986600)
  dynamic_cast<void*>                  0.33 ns/op  (hits=10000000)
```

Ranges over 3 runs each: virtual tag 4.6–6.4 ns; `typeid ==` 6.8–8.5 ns; `dynamic_cast` to the **final**
class 17–20 ns on GCC vs **4.1–5.0 ns on Clang**; mid-chain 28–40 ns; cross-cast 39–48 ns. `dynamic_cast<void*>`
is 0.2–0.4 ns because it reduces to a null test plus offset_to_top.

* The 50/50 random mix defeats the branch predictor. That is why even the "free" virtual tag costs ~5 ns:
  most of it is the mispredicted indirect branch, not the loads.
* Clang's `final` fast path is the vptr compare from Listing 1.1. GCC calls `__dynamic_cast`.
* Mid-chain and cross-casts walk the `__vmi_class_type_info` graph, so the cost grows with hierarchy depth
  and breadth. Cross-casts are the slowest because the walk has to find a *sibling*.

---

## 2. Evolution of the object model across standards

| Standard | Change (paper) | What changes in memory or code |
|---|---|---|
| C++98/03 | Itanium ABI (2000–) fixes vptr/vtable/RTTI/VTT layout | the layouts in §1 have been stable for 25 years. That stability is the reason they cannot change |
| C++11 | `override`, `final` (N3272) | `final` enables devirtualization and the Clang `dynamic_cast` fast path |
| C++11 | `noexcept` | none in the vtable; changes EH tables (file 02) |
| C++14 | sized deallocation (N3778) | the D0 deleting destructor calls `operator delete(void*, size_t)` (`_ZdlPvm`) |
| C++17 | `noexcept` is part of the function type (P0012R1) | `void(*)() noexcept` is a distinct type; mangling adds `Do` |
| C++17 | aligned `new` (P0035R4) | over-aligned classes use `operator delete(void*, size_t, align_val_t)` in D0 |
| C++20 | `constexpr` virtual functions (P1064R0), `dynamic_cast`/`typeid` in constant expressions (P1327R1) | the compiler evaluates virtual dispatch at compile time; the run-time layout is unchanged |
| C++20 | destroying `operator delete` (P0722R3) | `delete p` calls a class's `operator delete(T*, std::destroying_delete_t)` *instead of* the destructor |
| C++20 | `[[no_unique_address]]` (P0840R2) | file 04 |
| C++23 | deducing `this` (P0847R7) | explicit-object member functions **cannot be virtual**; CRTP without templates on the base |
| C++26 | static reflection (P2996R13) | `^^T` can enumerate bases and members at compile time (Folder 06) |
| C++26 | constexpr exceptions (P3068R6), `= delete("reason")` (P2573R2) | compile-time only |
| C++26 | trivial relocatability (P2786R13), **voted in (Feb 2025), voted out (Nov 2025, P3920R0)** | file 04. Polymorphic types were "trivially relocatable" under it, which collides with PAuth (§1.7) |

---

## 3. Production blueprints

### 3.1 C callbacks with multiple inheritance (Listing 1.8, `cb_cast.cpp`)

The subtle buggy way and the production-hardened way are the two `register_cb` calls in one program:

```cpp
// cb_cast.cpp - a void* context that round-trips through the WRONG type: wrong function, or deleted code
#include <cstdio>
#include <print>

// Stand-in for a C library: stores (fn, ctx) and calls fn(ctx, event) later.
extern "C" {
using cb_t = void (*)(void*, int);
static cb_t g_fn = nullptr;
static void* g_ctx = nullptr;
static void register_cb(cb_t fn, void* ctx) { g_fn = fn; g_ctx = ctx; }
static void fire(int e) { g_fn(g_ctx, e); }
}
// A real C library keeps ctx where the optimizer cannot follow it. Model that with a volatile round trip.
// -DOPTIMIZER_SEES_THE_TYPE lets the optimizer see everything instead (see the GCC result in the text).
#ifdef OPTIMIZER_SEES_THE_TYPE
#define CTX(p) static_cast<void*>(p)
#else
static void* opaque(void* p) {
    void* volatile v = p;
    return v;
}
#define CTX(p) opaque(p)
#endif

struct Listener {
    virtual void on_event(int e) = 0;  // slot +0 of Listener's vtable
    virtual ~Listener() = default;
};
struct Metrics {
    virtual void reset() { std::println("  Metrics::reset() ran  <- WRONG FUNCTION"); count = 0; }  // slot +0
    virtual ~Metrics() = default;
    long count = 0;
};
struct Service : Metrics, Listener {   // Metrics is the primary base (+0); Listener-in-Service is at +16
    void on_event(int e) override {
        count += e;
        std::println("  Service::on_event({}) ran, count={}", e, count);
    }
};

void cb(void* ctx, int e) { static_cast<Listener*>(ctx)->on_event(e); }

int main() {
    Service s;
    std::println("buggy: register_cb(cb, &s)  - ctx is a Service* converted to void*");
    std::fflush(stdout);
    register_cb(cb, CTX(&s));          // converts Service* -> void*: no adjustment, points at +0
    fire(5);                           // cb treats +0 as a Listener: loads Metrics' vptr, calls slot +0
    std::println("fixed: register_cb(cb, static_cast<Listener*>(&s))");
    register_cb(cb, CTX(static_cast<Listener*>(&s)));  // the +16 adjustment happens in typed code
    fire(5);
}
```

Default build, a realistic opaque C library (verified; GCC 16.2 and Clang 21.1 print the same):

```text
buggy: register_cb(cb, &s)  - ctx is a Service* converted to void*
  Metrics::reset() ran  <- WRONG FUNCTION
fixed: register_cb(cb, static_cast<Listener*>(&s))
  Service::on_event(5) ran, count=5
```

`&s` converts to `void*` **as a `Service*`**, at +0. `cb` reinterprets those bytes as a `Listener*`, which
should have been at +16. The "vptr" it loads is `Metrics`'s vptr, and slot +0 of that vtable is
`Metrics::reset`, so a different virtual function runs on a live object. In production the slot was a
destructor and the crash came minutes later in an unrelated place. On a PAuth target the vptr signature still
matches (it is the right vptr for that address), so pointer authentication does not catch it either.

**When the optimizer can see the whole program, it is worse.** Build with `-DOPTIMIZER_SEES_THE_TYPE` (no
opaque round trip). Clang still calls the wrong function. GCC 16.2 `-O2` proves that `static_cast<Listener*>`
of a pointer to offset 0 of a `Service` cannot yield a `Listener`, so the call is UB and therefore unreachable.
It **deletes the rest of `main`**:

```text
GCC 16.2, -DOPTIMIZER_SEES_THE_TYPE: program output (the process then exits with 0xC0000374)
buggy: register_cb(cb, &s)  - ctx is a Service* converted to void*
```

```text
main: control transfers in GCC -O2 output
	call __main
	call *%rbp
	call _Znwy    # operator new(unsigned long long)
	call _ZSt14vprint_unicodeP6_iobufSt17basic_string_viewIcSt11char_traitsIcEESt17basic_format_argsISt20basic_format_contextINSt8__format10_Sink_iterIcEEcEE    # std::vprint_unicode(_iobuf*, std::basic_string_view<char, std::char_traits<char> >, std::basic_format_args<std::basic_format_context<std::__format::_Sink_iter<char>, char> >)
	call _ZdlPvy    # operator delete(void*, unsigned long long)
	call *%rbp
	call fflush
	call _Znwy    # operator new(unsigned long long)
	call _ZdlPvy    # operator delete(void*, unsigned long long)
	jmp .L3825
	jmp .L3832
```

Those are all of `main`'s control transfers: the first print, `fflush`, and then **no call to `cb`, no second
print, and no `ret`**. Execution runs off the end of `main` into whatever code follows, and the Windows heap
reports corruption (0xC0000374). The `fflush` in the listing is there so that the first line survives the
crash.

**Invariant:** a `void*` must round-trip through *exactly* the type it was created from. Grep for
`static_cast<.*\*>(ctx)` and check each one against its `register`. In code review, reject any C callback that
casts its context pointer to a base class.

### 3.2 Hot polymorphic loops

| Situation | Hardened choice | Why (§1.6, §1.8) |
|---|---|---|
| closed set of types, hot loop | `std::variant` + `std::visit`, or a manual tag switch | no indirect branch per element; inlinable |
| open set, but leaves known | mark leaf classes `final`; call through the leaf type | direct calls; Clang's `dynamic_cast` fast path |
| mixed collection | **sort or partition by type**, then one loop per type | the indirect branch becomes perfectly predictable |
| plugin boundary | keep virtual; batch the work per call (`process(span<Item>)`) | one indirect call per batch, not per element |

### 3.3 Do not put vptrs in shared or persistent memory

A vptr is a virtual address in *this* process. ASLR moves it on every exec, and different binaries place it in
different spots. Objects with vptrs placed in `mmap`'d files, POSIX shared memory, GPU-mapped buffers or
RDMA regions crash, or worse, call arbitrary code in the peer process. Use trivially copyable message structs
with an explicit type tag. Use offset pointers (`boost::interprocess::offset_ptr`) instead of raw pointers.

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| `undefined reference to 'vtable for X'` | the key function (first non-inline, non-pure virtual) is declared but never defined | `nm -C`; define it, or make it inline |
| `pure virtual method called` + abort | virtual call during construction/destruction, or on an object destroyed by another thread | core dump: frame below `__cxa_pure_virtual`; TSan "data race on vptr" |
| `dynamic_cast` returns null across a `.so` boundary | duplicate typeinfo (hidden visibility, `RTLD_LOCAL`); libstdc++ compares `type_info` *names*, libc++ may compare *addresses* | export polymorphic and exception types with default visibility |
| random calls into the wrong function | `void*` round trip through the wrong base (§3.1), or a stale object in shared memory | ASan rarely flags it. Grep the casts; build with CFI (`-fsanitize=cfi-vcall`, needs LTO) |
| PAuth trap (`brk #0xc472`) on arm64e/pauthtest only | object memcpy'd, realloc'd or relocated with its vptr | the trap address points at the auth failure; find the memcpy |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What does a virtual call cost?"</b></summary>

**Initial prompt.** "What does a virtual function call cost compared with a direct call?"

**L5 textbook answer.** "One extra indirection through the vtable, a few cycles. Negligible."

**Why L5 breaks in production.** The loads are the cheap part. Listing 1.5 shows the real costs. (1) The
optimizer can neither inline nor vectorize across the call: GCC vectorized `sum_base` only after it had proved
the target. (2) In a loop Clang reloads vptr and slot every iteration, because the callee may legally change the
dynamic type. (3) The indirect branch must be predicted. Listing 1.7's random mix pays ~5 ns per call, which is
mostly misprediction. (4) Under retpoline / IBRS mitigations, indirect branches cost far more on affected x86
parts. (5) On PAuth targets every call adds `autda` + `braa` (Listing 1.6). (6) Through a secondary base, a
thunk adds a jump.

**L7 principal defense.** "Measure the branch, not the load. In a hot loop I make the call predictable by
partitioning by type. Or I remove it: `final` leaves, `std::variant` for closed sets, a batch API at plugin
boundaries. The rule I would put in a style guide: **no virtual call per element in a loop over more than
~10⁴ elements without a profile showing it is predictable**. I would back it up with Listing 1.5's assembly and
Listing 1.7's numbers."
</details>

<details><summary><b>Chain 2 🔥 "Why can't a constructor call a derived override?" — and the concurrent-destruction race</b></summary>

**Initial prompt.** "Why does a virtual call inside a base-class constructor not reach the derived override?
What about destructors?"

**L5 textbook answer.** "The derived part isn't constructed yet, so C++ calls the base version. Same in
destructors, in reverse."

**Why L5 corrupts memory on ARM64.** The answer is right but incomplete. It misses that the mechanism is a
*vptr store* (Listing 1.3), and so it misses the production bug. Thread A runs `delete obj`; thread B, still
holding the raw pointer, calls `obj->handle()`. `~Derived` runs, then the base destructor **re-stores the base
vptr** on entry. Depending on timing B sees: the derived vptr (calls into a half-destroyed object), the base vptr
(calls `Base::handle`, or `__cxa_pure_virtual` and aborts), or freed memory. On x86-TSO, stores become visible
in program order, so "B saw the base vptr" at least implies `~Derived`'s writes are visible too. **On AArch64
nothing orders A's plain stores as B observes them.** B can see the new vptr *before* the member writes that
preceded it, or the old vptr after the members were already torn down. The window is wider and the corruption
less deterministic. Either way it is a data race and therefore UB; ThreadSanitizer reports it as a race on the
vptr.

**L7 principal defense.** "A virtual call on an object whose lifetime is not guaranteed is a lifetime bug, not
a virtual-dispatch bug. My rules: (1) never publish `this` from a constructor (registering callbacks or starting
threads in a constructor is how B gets the pointer early). (2) Two-phase shutdown: `stop()`, which unregisters
and joins every thread that can call in, completes *before* destruction begins. (3) Shared lifetime through
`shared_ptr`/`weak_ptr::lock()` for callbacks (Folder 05), or an epoch/hazard scheme for hot paths (Folder 09).
(4) TSan in CI, because 'it never crashed on x86' is exactly what this bug looks like before the fleet moves to
Graviton."
</details>

<details><summary><b>Chain 3 ⚡ "Explain this-adjusting thunks"</b></summary>

**Initial prompt.** "What is a thunk in a vtable, and when do you pay for it?"

**L5 textbook answer.** "With multiple inheritance, the compiler adjusts `this` so the right function gets the
right object."

**Why L5 breaks.** The answer gives no layout, so the candidate cannot debug the §3.1 bug or a crash in
`_ZThn16_…`. The precise model: an overrider is called through a *secondary* vtable with `this` pointing at the
secondary subobject (+16 in Listing 1.1). The thunk subtracts 16 and jumps (Clang inlined the body there). A
call through the derived type uses the extra **primary** slot (slot 6) and pays nothing. *Virtual* thunks
(Listing 1.2) cost more: they load a vcall offset from the vtable because the adjustment is not a constant.
There are also covariant-return thunks (`_ZTc`), which adjust the *returned* pointer.

**L7 principal defense.** "I can draw the vtable group from memory: offset_to_top, RTTI, address point, and one
secondary vtable per non-primary polymorphic base, with thunks in the secondary slots. In a profile, `_ZThn`
symbols mean a call through a secondary interface. That is usually fine, but a hot `_ZTv` thunk means virtual
inheritance on a hot path, and I would design that out."
</details>

<details><summary><b>Chain 4 🧊 "Can I memcpy a polymorphic object / put it in shared memory?"</b></summary>

**Initial prompt.** "We store request objects in a shared-memory ring between two processes. Some have virtual
methods. Fine?"

**L5 textbook answer.** "As long as both processes run the same binary, the vtables are at the same address."

**Why L5 corrupts memory (and traps on ARM64e/PAuth).** ASLR randomizes the base of each process image, so the
same binary does **not** put `_ZTV` at the same address in two processes. A vptr written by process A points
into unmapped memory, or into arbitrary code, in process B. With PAuth (Listing 1.6) the signature also binds
the vptr to the *object's address*. Even a same-process memcpy to a new address fails authentication on the
next call. The x86 developer's test passes, and the arm64e build traps.

**L7 principal defense.** "Shared memory and persistence carry **trivially copyable** payloads only. That gets a
`static_assert(std::is_trivially_copyable_v<Msg>)` on every message type, a type tag, and offset pointers. The
polymorphism lives in process-local handler tables keyed by the tag. This is the same discipline as
network serialization, because shared memory is a network with a faster wire."
</details>

<details><summary><b>Chain 5 🔥 "Diamond inheritance: what does virtual inheritance cost?"</b></summary>

**Initial prompt.** "When would you use virtual inheritance, and what does it cost?"

**L5 textbook answer.** "To solve the diamond problem: one shared base instead of two. A small overhead."

**Why L5 breaks.** (1) **Access cost:** Listing 1.2's `read_b` needs three dependent loads; even `Join::f`
reads `b` through the vbase offset. (2) **Upcasts** to the virtual base are run-time lookups unless the class
is `final` (`up_join` vs `up_sealed`, which surprised me when I built the listing). (3) **`static_cast` from a
virtual base down is ill-formed**; you need `dynamic_cast`. (4) **Initialization order:** the *most-derived*
class constructs the virtual base, so `Left`'s mem-initializer for `Base` is **silently ignored** when `Left`
is a base of `Join`. Configuration passed through `Left(...) : Base(cfg)` vanishes in production.
(5) Constructors take a VTT; layout depends on the most-derived class, so `memcpy` and offset arithmetic are
meaningless.

**L7 principal defense.** "I allow virtual inheritance only for **stateless interfaces** (no data members in
the virtual base), the way `std::iostream` uses it for `basic_ios`. That kills problems 1 and 4. For everything
else: composition, or CRTP / deducing-this mixins (Folder 06). If someone needs a stateful diamond, I would ask
what the shared state models, because it is usually a missing aggregate."
</details>

<details><summary><b>Chain 6 ⚡ "undefined reference to vtable" and RTTI across shared libraries</b></summary>

**Initial prompt.** "A build fails with `undefined reference to vtable for Foo`. Later, `dynamic_cast` across a
plugin boundary returns null. Explain both."

**L5 textbook answer.** "You forgot to implement a virtual function. For the cast, maybe the types don't match."

**Why L5 breaks.** The first diagnosis is close but imprecise. Under the **key-function rule** the vtable is
emitted in the TU that defines the first non-inline, non-pure virtual function. Declare `virtual ~Foo();` and
never define it, and *no* TU emits `_ZTV3Foo`. If there is no key function, every TU that needs the vtable emits
a COMDAT copy and the linker folds them. The second failure is an identity problem. Two DSOs built with
`-fvisibility=hidden`, or loaded with `RTLD_LOCAL`, each carry their own `_ZTI3Foo`. What happens next depends
on the library, and I read both headers to check. libstdc++ 16 compares the name *pointers*, then falls back to
`strcmp` of the names (`__GXX_MERGED_TYPEINFO_NAMES` defaults to 0). libc++ 21 compares typeinfo *addresses*
on ELF ("Unique"), names on COFF/XCOFF, and uses a flag bit in the name pointer on Apple arm64. So the same
plugin works against libstdc++ and fails against libc++ on Linux, and exceptions thrown across the boundary
stop being caught.

**L7 principal defense.** "Every polymorphic type and every exception type that crosses a DSO boundary is
exported with default visibility, and each has a key function so exactly one TU owns its vtable and typeinfo.
Plugin APIs use C entry points and an interface version, and they never rely on cross-DSO `dynamic_cast`. I
would also check what the toolchain's `type_info::operator==` actually does instead of assuming."
</details>

<details><summary><b>Chain 7 🧊 "How big is a pointer to member function?"</b></summary>

**Initial prompt.** "`sizeof(&Widget::draw)`? Can I store it in a `uintptr_t` or hash it?"

**L5 textbook answer.** "It's a function pointer, so 8 bytes."

**Why L5 breaks on ARM64 (and on Windows).** On Itanium it is **16 bytes**, `{ptr, adj}` (Listing 1.4).
Truncating it to 8 bytes drops the adjustment, so calls through a secondary base get the wrong `this`. The
encoding also differs by architecture: x86-64 flags "virtual" in `ptr`'s low bit (`&C::v1` = `{17, 0}`),
AArch64 in `adj`'s low bit (`{16, 1}`). A hash or serialized form computed on one is meaningless on the other.
On the MSVC ABI the *size* depends on the inheritance model: 8, 16 or 24 bytes, and 24 for an incomplete class.
So the same header can produce different sizes in different TUs, which is an ODR/ABI bug unless
`/vmg` or the `__single_inheritance` keywords pin it.

**L7 principal defense.** "PMFs are opaque values: compare them, call them, never inspect them. If I need
storage or hashing I wrap the call in a lambda or `std::function`, or I store an enum and switch. On Windows I
would check the inheritance-model pragmas in any header that forward-declares classes used in PMFs."
</details>

<details><summary><b>Chain 8 ⚡ "Is dynamic_cast slow? Should we ban it?"</b></summary>

**Initial prompt.** "Our style guide bans `dynamic_cast` for performance. Agree?"

**L5 textbook answer.** "Yes, RTTI is slow. Use a virtual `type()` method instead."

**Why L5 breaks.** "Slow" depends on the cast. Listing 1.7 measured three different costs: `dynamic_cast<void*>`
is a load and an add; a cast to a `final` class is one compare **on Clang** (4–5 ns, about the cost of the
virtual tag) but a library call on this GCC build (17–20 ns); mid-chain and cross-casts walk the type graph
(28–48 ns), growing with depth. A blanket ban drives people to hand-rolled `type()` enums. Those enums go stale
when someone adds a subclass, and a `static_cast` on a stale tag is silent UB. The cast was at least checked.

**L7 principal defense.** "Ban the *pattern*, not the operator: a chain of `dynamic_cast`s choosing behaviour is
a missing virtual function or a missing `std::variant`. Keep `dynamic_cast` at boundaries (plugin APIs, event
dispatch at low rates), cast to `final` leaves where you can, and profile before arguing. If the profile shows
`__dynamic_cast`, the fix is usually to hoist the cast out of the loop, not to remove RTTI."
</details>

<details><summary><b>Chain 9 🧊 "Does final change anything except preventing inheritance?"</b></summary>

**Initial prompt.** "Is `final` just documentation?"

**L5 textbook answer.** "It stops people from deriving. Maybe a small optimization."

**Why L5 breaks.** Listings 1.1, 1.2 and 1.5 show four concrete code changes: direct calls and inlining
(`call_name_final`, `one_final`); a compile-time virtual-base offset (`up_sealed`); the vptr-compare
`dynamic_cast` (`down_final`); and, in file 04, the fact that a `final` deleter **cannot** be compressed by
inheritance-based EBO. That last one silently doubles `unique_ptr`'s size in both standard libraries.

**L7 principal defense.** "`final` is an optimization contract with a cost. I mark leaf implementations
`final` by default in application code. I do not mark empty policy or deleter types `final` (file 04), and I do
not mark library types `final` when users are expected to compose them by inheritance."
</details>

---

## 6. Invariants checklist

- [ ] Every polymorphic base has a virtual destructor, or a protected non-virtual one if deletion through the
      base is not allowed.
- [ ] Every class with virtual functions has a **key function** defined out of line in exactly one TU.
- [ ] No virtual calls from constructors or destructors except deliberately qualified ones (`Base::f()`).
- [ ] No `this` published to other threads or callbacks before construction completes; stop and join before
      destruction starts.
- [ ] Every `void*` context round-trips through exactly one type.
- [ ] No vptr-carrying object in shared memory, files, DMA/GPU buffers, or any `memcpy`/`realloc` path.
- [ ] Leaf classes `final`; policy/deleter classes **not** `final`.
- [ ] Virtual inheritance only for data-free interfaces.
- [ ] Exported polymorphic and exception types have default visibility; no cross-DSO `dynamic_cast` in plugin
      APIs.
- [ ] Hot loops over polymorphic collections are partitioned by type, or devirtualized via `final` / `variant`.

## 7. References

- Itanium C++ ABI (layout, vtables, RTTI, mangling): <https://itanium-cxx-abi.github.io/cxx-abi/abi.html>
- C++ ABI for the Arm 64-bit Architecture (PMF encoding, guard variables): <https://github.com/ARM-software/abi-aa/blob/main/cppabi64/cppabi64.rst>
- Clang pointer authentication: <https://clang.llvm.org/docs/PointerAuthentication.html>
- Clang relative vtables / LTO devirtualization: <https://clang.llvm.org/docs/LTOVisibility.html>
- GCC `-fdevirtualize-speculatively`: <https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html>
- N3272 (override/final): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2011/n3272.htm>
- P1327R1 (`dynamic_cast`/`typeid` in constexpr): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p1327r1.html>
- P0722R3 (destroying delete): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0722r3.html>
- P2996R13 (reflection): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p2996r13.html>
- Stanley Lippman, *Inside the C++ Object Model* (1996): the classic, pre-Itanium but still the best mental model.
