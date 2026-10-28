# 04 · Empty base optimization, `[[no_unique_address]]`, tail padding, and trivial relocation

> **Scope.** Layout rules that cost or save bytes in every object of a type: why an empty class has size 1, how
> EBO and `[[no_unique_address]]` remove that byte, how the Itanium ABI reuses tail padding (and how that turns
> an innocent `memcpy` into memory corruption), why both standard libraries keep `unique_ptr<T, FinalDeleter>`
> at 16 bytes, and *relocation*: the "move + destroy = memcpy" property that every high-performance container
> exploits. That last topic includes the C++26 trivial-relocatability feature, voted in and then voted out.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 4.1 | `ebo.cpp` | 12 layout rules as `static_assert`s + offsets (two same-type empties both overlap `x`) | run, both compilers |
| 4.2 | `nua_abi.cpp` | the MSVC ABI **ignores** `[[no_unique_address]]` and never reuses tail padding | `static_assert` for x86-64 Linux, AArch64 Linux, x86-64 MSVC |
| 4.3 | `tail_padding.cpp` | `memcpy(sizeof(Base))` into a base subobject **overwrites a derived member** | run, both compilers |
| 4.4 | `compressed_pair.cpp` | `unique_ptr` sizes for 6 deleters × 2 libraries; EBO breaks on `final` | run + expected diagnostics |
| 4.5 | `relocate.cpp` | memcpy-relocating a libstdc++ short string leaves a pointer into the old object; the libraries' internal traits; memcpy vs move+destroy timing | run, both libraries |
| 4.6 | `relocate_n.cpp` | trait-gated relocation blueprint | run, both libraries |
| 4.7 | `p2786.cpp` | the removed C++26 rules as Clang 21 implements them; on PAuth targets the builtin is a plain `memmove` | `static_assert` × 3 targets + asm |

**Verification line.** Native runs on Windows x86-64: GCC 16.2 + libstdc++ and Clang 21.1 + libc++ (both the
Itanium ABI). Cross-ABI checks with Clang 21.1 for `x86_64-linux-gnu`, `aarch64-linux-gnu`,
`aarch64-unknown-linux-pauthtest` and `x86_64-pc-windows-msvc`, compile-only, since all the facts are
`static_assert`s. Library internals were read from the shipped headers (libstdc++ 16.2, libc++ 21.1).

---

## 1. First principles

### 1.1 Four sizes per class, and the one-address rule

Every complete object must have a unique address among objects of the same type. That is why `sizeof(Empty) ==
1`. The Itanium ABI tracks four quantities per class (Clang prints them in file 01's layout dumps):

```text
 sizeof   - size of a complete object, rounded up to alignment (what arrays use)
 dsize    - "data size": sizeof without TAIL PADDING (last byte any member actually uses, + 1)
 nvsize   - size without virtual bases (what a base-class subobject occupies)
 nvalign  - alignment without virtual bases

 struct Padded { int32_t a; char b; Padded() {} };      sizeof 8, dsize 5, align 4
   +0 a a a a  +4 b  +5 . . .   <- 3 bytes of tail padding
                       ^
 struct DerivedReuse : Padded { char c; };             c is placed at +5, INSIDE Padded's sizeof
```

Two mechanisms let a subobject take less than its `sizeof`:

* **Empty base optimization.** An empty base class may share its address with other subobjects, so it costs 0
  bytes. It has been permitted since C++98 and is required by the Itanium ABI.
* **Tail-padding reuse.** The Itanium ABI places later members of a derived class inside a base class's tail
  padding, **if the base is not "POD for the purpose of layout"** (roughly: not a C++03 POD). C++20's
  `[[no_unique_address]]` extends both to *members*. Base subobjects and `[[no_unique_address]]` members are
  called **potentially-overlapping subobjects**, and the standard's `memcpy` guarantees do not apply to them.

### 1.2 The rules, proven (Listing 4.1)

```cpp
// ebo.cpp - empty base optimization and [[no_unique_address]]: the size rules, proven with static_assert
#include <cstddef>
#include <cstdint>
#include <print>

struct Empty {};
struct Empty2 {};
struct FinalEmpty final {};

struct AsMember {                      // an empty member still occupies 1 byte (+7 padding here)
    Empty e;
    std::int64_t x;
};
struct AsBase : Empty {                // EBO: the empty base shares address with x
    std::int64_t x;
};
struct NuaMember {                     // C++20: the member may share storage
    [[no_unique_address]] Empty e;
    std::int64_t x;
};
struct NuaTwoDistinct {                // two DIFFERENT empty types may both overlap x
    [[no_unique_address]] Empty e1;
    [[no_unique_address]] Empty2 e2;
    std::int64_t x;
};
struct NuaTwoSame {                    // same type twice: e1 and e2 need DISTINCT addresses, yet both
    [[no_unique_address]] Empty e1;
    [[no_unique_address]] Empty e2;    // may still overlap x (e1 at +0, e2 at +1)
    std::int64_t x;
};
struct EboBlocked : Empty {            // the base sits at +0, so a member of the SAME type cannot:
    Empty first;                       // 'first' is pushed to +1 and x to +8 -> 16 bytes, not 8
    std::int64_t x;
};
struct NuaFinal {                      // final types cannot be inherited from, but CAN be [[no_unique_address]]
    [[no_unique_address]] FinalEmpty f;
    std::int64_t x;
};

struct Padded {                        // 5 bytes of data, 3 bytes of tail padding; not POD for layout
    std::int32_t a = 0;
    char b = 0;
    Padded() {}                        // user-provided ctor -> not POD -> Itanium may reuse tail padding
};
struct DerivedReuse : Padded {         // c lands INSIDE Padded's tail padding: sizeof stays 8
    char c = 0;
};
struct MemberNoReuse {                 // ordinary member: its tail padding is never reused
    Padded p;
    char c = 0;
};
struct MemberNuaReuse {                // [[no_unique_address]] member: tail padding reused, like a base
    [[no_unique_address]] Padded p;
    char c = 0;
};

static_assert(sizeof(Empty) == 1);
static_assert(sizeof(AsMember) == 16);
static_assert(sizeof(AsBase) == 8);
static_assert(sizeof(NuaMember) == 8);
static_assert(sizeof(NuaTwoDistinct) == 8);
static_assert(sizeof(NuaTwoSame) == 8);
static_assert(sizeof(EboBlocked) == 16);
static_assert(sizeof(NuaFinal) == 8);
static_assert(sizeof(Padded) == 8);
static_assert(sizeof(DerivedReuse) == 8);
static_assert(sizeof(MemberNoReuse) == 12);
static_assert(sizeof(MemberNuaReuse) == 8);

template <class T>
std::ptrdiff_t offset_in(const T& outer, const void* inner) {
    return static_cast<const char*>(inner) - reinterpret_cast<const char*>(&outer);
}

int main() {
    std::println("{:<16} {:>6}  notes", "type", "sizeof");
    std::println("{:<16} {:>6}  empty class: 1 byte so distinct objects have distinct addresses", "Empty",
                 sizeof(Empty));
    std::println("{:<16} {:>6}  empty member costs 1 byte + 7 padding", "AsMember", sizeof(AsMember));
    std::println("{:<16} {:>6}  EBO", "AsBase", sizeof(AsBase));
    std::println("{:<16} {:>6}  [[no_unique_address]]", "NuaMember", sizeof(NuaMember));
    std::println("{:<16} {:>6}  two different empty types overlap", "NuaTwoDistinct", sizeof(NuaTwoDistinct));
    std::println("{:<16} {:>6}  same type twice: distinct addresses, both inside x", "NuaTwoSame",
                 sizeof(NuaTwoSame));
    std::println("{:<16} {:>6}  EBO suppressed by a same-type first member", "EboBlocked", sizeof(EboBlocked));
    std::println("{:<16} {:>6}  final empty type via [[no_unique_address]]", "NuaFinal", sizeof(NuaFinal));
    std::println("{:<16} {:>6}  4 + 1 data bytes, 3 bytes tail padding", "Padded", sizeof(Padded));
    std::println("{:<16} {:>6}  base tail padding reused", "DerivedReuse", sizeof(DerivedReuse));
    std::println("{:<16} {:>6}  member tail padding NOT reused", "MemberNoReuse", sizeof(MemberNoReuse));
    std::println("{:<16} {:>6}  [[no_unique_address]] member tail padding reused", "MemberNuaReuse",
                 sizeof(MemberNuaReuse));
    NuaTwoSame s;
    std::println("NuaTwoSame offsets: e1 +{}  e2 +{}  x +{}", offset_in(s, &s.e1), offset_in(s, &s.e2),
                 offset_in(s, &s.x));
    EboBlocked eb;
    std::println("EboBlocked offsets: Empty base +{}  first +{}  x +{}",
                 offset_in(eb, static_cast<const Empty*>(&eb)), offset_in(eb, &eb.first), offset_in(eb, &eb.x));
    DerivedReuse d;
    std::println("DerivedReuse offsets: c +{}", offset_in(d, &d.c));
}
```

Output (verified; GCC 16.2 and Clang 21.1 print the same, and every size is also a `static_assert`):

```text
type             sizeof  notes
Empty                 1  empty class: 1 byte so distinct objects have distinct addresses
AsMember             16  empty member costs 1 byte + 7 padding
AsBase                8  EBO
NuaMember             8  [[no_unique_address]]
NuaTwoDistinct        8  two different empty types overlap
NuaTwoSame            8  same type twice: distinct addresses, both inside x
EboBlocked           16  EBO suppressed by a same-type first member
NuaFinal              8  final empty type via [[no_unique_address]]
Padded                8  4 + 1 data bytes, 3 bytes tail padding
DerivedReuse          8  base tail padding reused
MemberNoReuse        12  member tail padding NOT reused
MemberNuaReuse        8  [[no_unique_address]] member tail padding reused
NuaTwoSame offsets: e1 +0  e2 +1  x +0
EboBlocked offsets: Empty base +0  first +1  x +8
DerivedReuse offsets: c +5
```

Two rows surprised me when I wrote the assertions, so I corrected them against the compiler:

* **`NuaTwoSame` is 8, not 16.** Two `[[no_unique_address]]` members of the *same* empty type must have
  distinct addresses *from each other*, but nothing stops both from overlapping `x`: `e1` at +0, `e2` at +1,
  `x` at +0.
* **In `EboBlocked` the base stays at +0 and the member moves.** An `Empty` base and an `Empty` first member
  cannot share an address, so `first` is pushed to +1 and `x` to +8 (16 bytes). This is why
  `std::tuple<Empty, Empty>` and `compressed_pair<Empty, Empty>` implementations need care.

### 1.3 It is an ABI property, not a language property (Listing 4.2)

```cpp
// nua_abi.cpp - the same struct under the Itanium ABI and the MSVC ABI: [[no_unique_address]] is not portable
// Self-contained (no headers) so it compiles for x86_64-linux-gnu and x86_64-pc-windows-msvc alike.
struct Empty {};
struct Padded {
    int a;
    char b;
    Padded() {}
};

struct Nua {
    [[no_unique_address]] Empty e;  // MSVC ABI: IGNORED (Clang says so with -Wunknown-attributes)
    long long x;
};
struct NuaMsvc {
#if defined(_MSC_VER)
    [[msvc::no_unique_address]] Empty e;  // the MSVC-ABI spelling (VS 2019 16.9+, clang-cl)
#else
    [[no_unique_address]] Empty e;
#endif
    long long x;
};
struct TailReuse : Padded {         // Itanium: c goes into Padded's tail padding; MSVC: never
    char c;
};

#if defined(_MSC_VER)
static_assert(sizeof(Nua) == 16, "MSVC ABI ignores [[no_unique_address]]");
static_assert(sizeof(NuaMsvc) == 8, "[[msvc::no_unique_address]] is honoured");
static_assert(sizeof(TailReuse) == 12, "MSVC ABI does not reuse base tail padding");
#else
static_assert(sizeof(Nua) == 8, "Itanium ABI honours [[no_unique_address]]");
static_assert(sizeof(NuaMsvc) == 8);
static_assert(sizeof(TailReuse) == 8, "Itanium ABI reuses non-POD base tail padding");
#endif

int sizes() { return int(sizeof(Nua) * 100 + sizeof(NuaMsvc) * 10 + sizeof(TailReuse)); }
```

```text
x86_64-linux-gnu           static_asserts hold
aarch64-linux-gnu          static_asserts hold
x86_64-pc-windows-msvc     static_asserts hold
    nua_abi.cpp:11:7: warning: unknown attribute 'no_unique_address' ignored [-Wunknown-attributes]
```

On the MSVC ABI (`cl.exe`, and `clang-cl` for compatibility) `[[no_unique_address]]` is accepted and ignored.
Changing that would change the layout of existing types, which MSVC treats as an ABI break. The MSVC-specific
spelling `[[msvc::no_unique_address]]` is honoured. MSVC also never reuses base tail padding (`TailReuse` is 12
bytes there, 8 on Itanium). The same header therefore produces different layouts on Windows and Linux, which
matters for anything that crosses process or language boundaries. Portable libraries use a macro:

```cpp
#if defined(_MSC_VER)
#  define NO_UNIQUE_ADDRESS [[msvc::no_unique_address]]
#else
#  define NO_UNIQUE_ADDRESS [[no_unique_address]]
#endif
```

### 1.4 Tail padding meets `memcpy` (Listing 4.3)

```cpp
// tail_padding.cpp - memcpy of sizeof(Base) into a potentially-overlapping subobject corrupts its neighbour
#include <cstdint>
#include <cstring>
#include <print>
#include <type_traits>

struct Header {                        // 5 data bytes + 3 bytes tail padding
    std::int32_t id = 0;
    char kind = 0;
    Header() = default;
    Header(std::int32_t i, char k) : id(i), kind(k) {}  // user-declared ctor: not a C++03 POD, so the
};                                                       // Itanium ABI may reuse the tail padding
struct Message : Header {
    char flags = 0;                    // lives at offset 5: INSIDE sizeof(Header)
};
static_assert(sizeof(Header) == 8 && sizeof(Message) == 8);
static_assert(std::is_trivially_copyable_v<Header>);  // "trivially copyable" does not make this memcpy safe

// The subtle bug: "Header is trivially copyable, so memcpy sizeof(Header) bytes into the base."
void reset_header_buggy(Header& h, const Header& from) {
    std::memcpy(static_cast<void*>(&h), &from, sizeof(Header));  // writes bytes 0..7, including flags at +5
}
// Correct: assignment copies only the members (data size), never the tail padding.
void reset_header(Header& h, const Header& from) { h = from; }

int main() {
    static const Header fresh(7, 'H');  // static storage: zero-initialized first, so padding bytes are 0
    Message m;
    m.flags = 'F';
    reset_header(m, fresh);
    std::println("assignment : id={} kind={} flags={}", m.id, m.kind, m.flags);
    m.flags = 'F';
    reset_header_buggy(m, fresh);      // UB per [basic.types.general]/2-3: m's Header is potentially-overlapping
    std::println("memcpy     : id={} kind={} flags={} ({})", m.id, m.kind, static_cast<int>(m.flags),
                 m.flags == 'F' ? "intact" : "CLOBBERED by fresh's padding byte");
}
```

Output (verified, both compilers):

```text
assignment : id=7 kind=H flags=F
memcpy     : id=7 kind=H flags=0 (CLOBBERED by fresh's padding byte)
```

`Header` is trivially copyable, and that is exactly the trap. The rule "trivially copyable → memcpy is fine"
holds only for objects that are **not potentially-overlapping subobjects** ([basic.types.general]/2–3).
`Message::flags` lives at offset 5, inside `sizeof(Header)`, so `memcpy(&h, &from, sizeof(Header))` writes
`from`'s padding byte over it (here 0, because `fresh` has static storage and was zero-initialized first).
Assignment is correct because the compiler copies only `dsize` bytes into a potentially-overlapping
subobject. GCC normally warns about `memcpy` on non-trivial class types (`-Wclass-memaccess`). Here the type
*is* trivial, and the listing casts to `void*` the way real code does, so no compiler warns at all.

Where this happens in production: "reset to defaults" helpers (`memcpy(this, &kDefaults, sizeof(*this))` in a
base class), serialization that writes a base by `sizeof`, and `std::memset(static_cast<Base*>(p), 0,
sizeof(Base))`.

### 1.5 Compressed pairs: why `unique_ptr<T, FinalDeleter>` is 16 bytes (Listing 4.4)

```cpp
// compressed_pair.cpp - zero-cost stateless deleters: C++03 EBO pair vs C++20 [[no_unique_address]] pair
#include <cstdio>
#include <functional>
#include <memory>
#include <print>
#include <utility>

struct FileCloser {                    // stateless: sizeof 1, but should cost 0 bytes inside a handle
    void operator()(std::FILE* f) const noexcept { std::fclose(f); }
};
struct FinalCloser final {             // final: you cannot inherit from it
    void operator()(std::FILE* f) const noexcept { std::fclose(f); }
};
struct CountingCloser {                // stateful: must occupy storage
    int* closed;
    void operator()(std::FILE* f) const noexcept { std::fclose(f); ++*closed; }
};

// C++03-style compressed pair: inherit from the deleter to get EBO. Breaks for final classes, for
// function-pointer deleters (cannot inherit from a non-class), and leaks the deleter's members into scope.
template <class P, class D>
struct EboPair : private D {
    P ptr;
    EboPair(P p, D d) : D(std::move(d)), ptr(p) {}
    D& deleter() { return *this; }
};

// C++20: [[no_unique_address]] works for final classes and non-class types (they just take space).
template <class P, class D>
struct NuaPair {
    P ptr;
    [[no_unique_address]] D del;
};

template <class D>
using Handle = std::unique_ptr<std::FILE, D>;

int main() {
    auto lambda = [](std::FILE* f) noexcept { std::fclose(f); };
    std::println("std::unique_ptr<FILE, D> sizes with this standard library:");
    std::println("  {:<34} {}", "D = FileCloser (stateless)", sizeof(Handle<FileCloser>));
    std::println("  {:<34} {}", "D = FinalCloser (stateless, final)", sizeof(Handle<FinalCloser>));
    std::println("  {:<34} {}", "D = captureless lambda", sizeof(Handle<decltype(lambda)>));
    std::println("  {:<34} {}", "D = int(*)(FILE*) (fclose)", sizeof(Handle<int (*)(std::FILE*)>));
    std::println("  {:<34} {}", "D = CountingCloser (8-byte state)", sizeof(Handle<CountingCloser>));
    std::println("  {:<34} {}", "D = std::function<void(FILE*)>", sizeof(Handle<std::function<void(std::FILE*)>>));
    std::println("hand-rolled pairs:");
    std::println("  {:<34} {}", "EboPair<FILE*, FileCloser>", sizeof(EboPair<std::FILE*, FileCloser>));
    std::println("  {:<34} {}", "NuaPair<FILE*, FileCloser>", sizeof(NuaPair<std::FILE*, FileCloser>));
    std::println("  {:<34} {}", "NuaPair<FILE*, FinalCloser>", sizeof(NuaPair<std::FILE*, FinalCloser>));
#ifdef SHOW_EBO_FINAL_ERROR
    EboPair<std::FILE*, FinalCloser> broken(nullptr, FinalCloser{});  // ill-formed: final base
    (void)broken;
#endif
    static_assert(sizeof(Handle<FileCloser>) == sizeof(void*));
    static_assert(sizeof(NuaPair<std::FILE*, FinalCloser>) == sizeof(void*));
}
```

GCC 16.2 + libstdc++ (verified):

```text
std::unique_ptr<FILE, D> sizes with this standard library:
  D = FileCloser (stateless)         8
  D = FinalCloser (stateless, final) 16
  D = captureless lambda             8
  D = int(*)(FILE*) (fclose)         16
  D = CountingCloser (8-byte state)  16
  D = std::function<void(FILE*)>     40
hand-rolled pairs:
  EboPair<FILE*, FileCloser>         8
  NuaPair<FILE*, FileCloser>         8
  NuaPair<FILE*, FinalCloser>        8
```

Clang 21.1 + libc++ (verified):

```text
std::unique_ptr<FILE, D> sizes with this standard library:
  D = FileCloser (stateless)         8
  D = FinalCloser (stateless, final) 16
  D = captureless lambda             8
  D = int(*)(FILE*) (fclose)         16
  D = CountingCloser (8-byte state)  16
  D = std::function<void(FILE*)>     64
hand-rolled pairs:
  EboPair<FILE*, FileCloser>         8
  NuaPair<FILE*, FileCloser>         8
  NuaPair<FILE*, FinalCloser>        8
```

The C++03-style EBO pair cannot hold a `final` deleter:

```text
compressed_pair.cpp:22:8: error: cannot derive from 'final' base 'FinalCloser' in derived type 'EboPair<_iobuf*, FinalCloser>'
compressed_pair.cpp:22:26: error: base 'FinalCloser' is marked 'final'
```

The interesting row is **`FinalCloser`: 16 bytes in both standard libraries**, while a hand-written
`NuaPair<FILE*, FinalCloser>` is 8. I read both headers to find out why:

* **libstdc++** stores `unique_ptr`'s pointer and deleter in a `std::tuple`, whose element base
  `_Head_base<Idx, Head, bool = __empty_not_final<Head>::value>` uses `[[no_unique_address]]` **only when the
  type is empty and not final**. The final case keeps a plain member, as the old inheritance-based layout did.
* **libc++ 21.1** replaced its `__compressed_pair` with `_LIBCPP_COMPRESSED_PAIR` (`[[no_unique_address]]` plus
  explicit padding). A header comment explains that the utilities exist "for staying ABI compatible with the
  legacy `__compressed_pair`". The padding logic treats an empty type as zero-size only if
  `is_empty && !__libcpp_is_final`.

Both libraries could make the final case 8 bytes, and both deliberately do not, because that would change
`sizeof(unique_ptr<T, D>)` for existing binaries. **Layout, once shipped, is forever.**

### 1.6 Relocation: move + destroy as one `memcpy` (Listing 4.5)

*Relocating* an object means moving it to new storage and ending the old one's lifetime. `vector`
reallocation, `deque` map growth, `insert` and `erase` in the middle, and swapping are all relocations. For
most types, "move-construct at the destination, destroy the source" produces exactly the bytes a `memcpy`
would, and the memcpy is one bulk operation instead of 2N constructor and destructor calls. The question is
**which types are safe**:

```text
 trivially relocatable (memcpy works)              NOT (memcpy breaks an invariant)
 -----------------------------------------         ------------------------------------------------------
 int, POD structs, pointers                         types with SELF-POINTERS: libstdc++ std::string (SSO),
 unique_ptr<T> (default deleter)                    std::list (sentinel node inside the object, libstdc++)
 vector<T>, libc++ std::string                      types whose address is registered elsewhere
 most "handle" classes                              (intrusive lists, observers, mutexes and atomics in use)
 polymorphic classes (vptr is position-free)        polymorphic classes on PAuth targets (signed vptr:
                                                    the signature is bound to the object's address)
```

```cpp
// relocate.cpp - "move + destroy" vs memcpy relocation: which types survive being memcpy'd, and what it buys
#include <chrono>
#include <cstddef>
#include <cstring>
#include <deque>
#include <list>
#include <memory>
#include <new>
#include <print>
#include <string>
#include <utility>
#include <vector>

// 1. A short std::string relocated with memcpy. libstdc++ keeps a pointer to its own SSO buffer
//    (self-referential), so the copy still points into the OLD object. libc++ stores a size/flag
//    instead of a self-pointer, so its strings survive. Formally UB in both: the demo shows why.
static void sso_relocation() {
    alignas(std::string) unsigned char from[sizeof(std::string)];
    alignas(std::string) unsigned char to[sizeof(std::string)];
    auto* s = ::new (static_cast<void*>(from)) std::string("short");
    std::memcpy(to, from, sizeof(std::string));           // "relocate": bytes moved, no constructor ran
    auto* r = std::launder(reinterpret_cast<std::string*>(to));
    const char* d = r->data();
    bool into_old = d >= reinterpret_cast<const char*>(from) && d < reinterpret_cast<const char*>(from) + sizeof from;
    std::memset(from, 'X', sizeof from);                   // the old storage is reused
    std::println("  sizeof(std::string)={}  relocated data() points into {} storage; reads \"{}\"",
                 sizeof(std::string), into_old ? "the OLD" : "its own", std::string_view(d, 5));
    if (!into_old) std::destroy_at(r);                     // libstdc++ case: destroying would free() a stack address
    (void)s;
}

// 2. The library's own (internal, non-portable) answer to "may I memcpy this?"
template <class T>
static bool lib_says_relocatable() {
#if defined(_LIBCPP_VERSION)
    return std::__libcpp_is_trivially_relocatable<T>::value;
#else
    return std::__is_bitwise_relocatable<T>::value;
#endif
}

// 3. A unique_ptr-like handle: move ctor + dtor are non-trivial, but relocation is just a byte copy.
struct Handle {
    int* p = nullptr;
    Handle() = default;
    explicit Handle(int* q) : p(q) {}
    Handle(Handle&& o) noexcept : p(std::exchange(o.p, nullptr)) {}
    ~Handle() { delete p; }
};

static double relocate_ms(bool use_memcpy, std::size_t n, int reps) {
    auto* src = static_cast<Handle*>(::operator new(n * sizeof(Handle)));
    auto* dst = static_cast<Handle*>(::operator new(n * sizeof(Handle)));
    for (std::size_t i = 0; i < n; ++i) ::new (static_cast<void*>(src + i)) Handle(nullptr);
    auto t0 = std::chrono::steady_clock::now();
    for (int r = 0; r < reps; ++r) {
        if (use_memcpy) {
            std::memcpy(static_cast<void*>(dst), src, n * sizeof(Handle));
        } else {
            for (std::size_t i = 0; i < n; ++i) {
                ::new (static_cast<void*>(dst + i)) Handle(std::move(src[i]));
                src[i].~Handle();
            }
        }
        std::swap(src, dst);                               // relocate back and forth
    }
    auto t1 = std::chrono::steady_clock::now();
    for (std::size_t i = 0; i < n; ++i) src[i].~Handle();
    ::operator delete(src);
    ::operator delete(dst);
    return std::chrono::duration<double, std::milli>(t1 - t0).count() / reps;
}

int main() {
#if defined(_LIBCPP_VERSION)
    std::println("library: libc++");
#else
    std::println("library: libstdc++");
#endif
    std::println("1. memcpy-relocating a short std::string:");
    sso_relocation();
    std::println("2. library-internal relocatability trait:");
    std::println("  {:<28} {}", "int", lib_says_relocatable<int>());
    std::println("  {:<28} {}", "std::unique_ptr<int>", lib_says_relocatable<std::unique_ptr<int>>());
    std::println("  {:<28} {}", "std::string", lib_says_relocatable<std::string>());
    std::println("  {:<28} {}", "std::vector<int>", lib_says_relocatable<std::vector<int>>());
    std::println("  {:<28} {}", "std::deque<int>", lib_says_relocatable<std::deque<int>>());
    std::println("  {:<28} {}", "std::list<int>", lib_says_relocatable<std::list<int>>());
    std::println("3. relocating 4M Handles (one run, ms per pass):");
    constexpr std::size_t kN = 4'000'000;
    std::println("  move-construct + destroy loop: {:6.2f} ms", relocate_ms(false, kN, 20));
    std::println("  memcpy                       : {:6.2f} ms", relocate_ms(true, kN, 20));
}
```

GCC 16.2 + libstdc++ (one run):

```text
library: libstdc++
1. memcpy-relocating a short std::string:
  sizeof(std::string)=32  relocated data() points into the OLD storage; reads "XXXXX"
2. library-internal relocatability trait:
  int                          true
  std::unique_ptr<int>         false
  std::string                  false
  std::vector<int>             false
  std::deque<int>              true
  std::list<int>               false
3. relocating 4M Handles (one run, ms per pass):
  move-construct + destroy loop:   4.43 ms
  memcpy                       :   2.18 ms
```

Clang 21.1 + libc++ (one run):

```text
library: libc++
1. memcpy-relocating a short std::string:
  sizeof(std::string)=24  relocated data() points into its own storage; reads "short"
2. library-internal relocatability trait:
  int                          true
  std::unique_ptr<int>         true
  std::string                  true
  std::vector<int>             true
  std::deque<int>              true
  std::list<int>               false
3. relocating 4M Handles (one run, ms per pass):
  move-construct + destroy loop:   4.13 ms
  memcpy                       :   3.20 ms
```

* **libstdc++'s `std::string` points into itself.** After the memcpy, `data()` still points at the *old*
  object's SSO buffer. Reusing the old storage changes the "relocated" string to `XXXXX`, and destroying it would
  pass a stack address to `operator delete`. libc++'s string (24 bytes) stores a size/flag byte instead of a
  self-pointer, so the same memcpy produces a valid string. Formally both are UB; the libc++ result is why
  libc++ can relocate strings internally.
* **The libraries' own (internal, non-portable) relocatability traits agree with that physics.** libstdc++'s
  `std::__is_bitwise_relocatable` is `true` only for trivial types plus an explicit `deque` specialization
  (file 02, §1.5). libc++'s `std::__libcpp_is_trivially_relocatable` is `true` for `unique_ptr`, `string`,
  `vector` and `deque`, and `false` for `list`.
* **Timing** (4M handles, 20 passes, ranges over 3 runs): move+destroy loop 4.6–5.1 ms (GCC), 4.3–4.4 ms
  (Clang); memcpy 2.1–2.2 ms (GCC), 3.3–3.4 ms (Clang). The optimizer already turns the loop into a tight
  copy-and-null-store sequence for this simple handle. For types with non-inline move constructors, or with
  destructors the compiler cannot prove trivial after a move, the gap grows by the cost of 2N calls.

### 1.7 C++26 trivial relocatability: in, then out (Listing 4.7)

The history, because interviewers ask about it:

* **P1144** (Arthur O'Dwyer, from 2018) proposed `[[trivially_relocatable]]` and `std::relocate_at`, with the
  semantics "relocation is equivalent to memcpy", matching what Folly, BDE, Qt, EASTL, libstdc++ and libc++
  already do.
* **P2786** (Alisdair Meredith, Mungo Gill et al.; R13 adopted into the C++26 working draft at Hagenberg, February 2025) chose
  different semantics: context-sensitive keywords `trivially_relocatable_if_eligible` and
  `replaceable_if_eligible`, the trait `std::is_trivially_relocatable_v`, and the function
  `std::trivially_relocate`.
* **Kona, November 2025:** a joint EWG/LEWG session found a showstopper problem that could not be fixed in time,
  and the feature was **removed from C++26**. P3920R0 (Louis Dionne) gives the removal wording, and P4197R0
  lists the open design questions for C++29. It is the one feature removed after the C++26 feature freeze.

Clang 21.1 shipped P2786 before the removal, so the design can still be inspected:

```cpp
// p2786.cpp - the P2786 trivial-relocatability rules as Clang 21 implements them in -std=c++26
// P2786 was voted into the C++26 draft (Hagenberg, Feb 2025) and voted OUT again (Kona, Nov 2025; P3920).
// Clang 21 shipped before the removal, so this is a record of the design, not portable C++26.
struct Plain {                                    // implicitly trivially relocatable: everything trivial
    int* p;
};
struct UserMove {                                 // a user-provided move ctor/dtor -> not eligible by default
    int* p;
    UserMove(UserMove&&) noexcept;
    ~UserMove();
};
struct OptIn trivially_relocatable_if_eligible {  // the author vouches: move+destroy == memcpy
    int* p;
    OptIn(OptIn&&) noexcept;
    ~OptIn();
};
struct OptInBadMember trivially_relocatable_if_eligible {  // "if eligible": a non-relocatable member wins
    UserMove m;
};
struct Polymorphic {                              // vptr: P2786 still counts it as trivially relocatable...
    virtual ~Polymorphic() = default;             // ...as long as no special member is user-PROVIDED
    virtual int f() const;
    int x;
};
struct PolymorphicUserDtor {                      // virtual ~T(); defined out of line = user-provided
    virtual ~PolymorphicUserDtor();
    int x;
};
struct VirtualBase : virtual Plain {              // virtual base: never trivially relocatable
    int y;
};

static_assert(__builtin_is_cpp_trivially_relocatable(int));
static_assert(__builtin_is_cpp_trivially_relocatable(Plain));
static_assert(!__builtin_is_cpp_trivially_relocatable(UserMove));
static_assert(__builtin_is_cpp_trivially_relocatable(OptIn));
static_assert(!__builtin_is_cpp_trivially_relocatable(OptInBadMember));
static_assert(__builtin_is_cpp_trivially_relocatable(Polymorphic));
static_assert(!__builtin_is_cpp_trivially_relocatable(PolymorphicUserDtor));
static_assert(!__builtin_is_cpp_trivially_relocatable(VirtualBase));

// The relocation primitive. Clang 21.1 lowers it to memmove on every target - including pauthtest, where
// the vptr signature is blended with the object's own address (vt_hardening.cpp). A relocated polymorphic
// object would then carry a vptr signed for its OLD address (inferred from codegen; not executed here).
Polymorphic* relocate(Polymorphic* first, Polymorphic* last, Polymorphic* out) {
    return __builtin_trivially_relocate(out, first, static_cast<unsigned long>(last - first));
}
```

```text
x86_64-linux-gnu           static_asserts hold
aarch64-linux-gnu          static_asserts hold
aarch64-unknown-linux-pauthtest static_asserts hold
```

```asm
_Z8relocateP11PolymorphicS0_S0_:   # relocate(Polymorphic*, Polymorphic*, Polymorphic*)
	movq	%rdx, %rax
	movq	%rsi, %rdx
	movq	%rdi, %rsi
	subq	%rdi, %rdx
	movq	%rax, %rdi
	jmp	memmove@PLT
```

```asm
_Z8relocateP11PolymorphicS0_S0_:   // relocate(Polymorphic*, Polymorphic*, Polymorphic*)
	mov	x9, x2
	mov	x8, x0
	sub	x2, x1, x0
	mov	x0, x9
	mov	x1, x8
	b	memmove
```

* The rules: implicitly eligible only with no user-provided special members, no virtual bases, and only
  eligible members. The keyword is an opt-in "I vouch", but "if eligible" means a non-relocatable member still
  wins (`OptInBadMember`). **Polymorphic types are eligible**, provided the destructor is not user-provided.
* On `aarch64-unknown-linux-pauthtest`, Clang 21.1 reports `Polymorphic` as trivially relocatable **and lowers
  `__builtin_trivially_relocate` to a plain `memmove`**. File 01 (§1.7) showed that on this target the vptr is
  signed with a discriminator blended from the *object's address*. ⚠ Inference from the two codegen listings,
  not executed (no PAuth hardware or emulator here): an object relocated this way carries a vptr signed for its
  old address, and its next virtual call would fail authentication. A correct implementation would have to
  re-sign vptrs during relocation. I am not claiming this was the Kona showstopper. The public papers describe
  the problems in their own terms.
* **GCC 16.2 does not implement P2786** (the keyword is a syntax error). Neither library defines
  `__cpp_lib_trivially_relocatable` (file 03, Listing 3.8).

---

## 2. Evolution table

| Standard | Change (paper) | Effect |
|---|---|---|
| C++98 | EBO permitted; Itanium ABI requires it and tail-padding reuse for non-POD bases | `boost::compressed_pair`, library-internal compressed pairs |
| C++11 | `std::is_empty`, `final` | `final` classes cannot be EBO'd by inheritance (Listing 4.4) |
| C++11 | standard-layout, trivially copyable formalized | memcpy guarantees, which exclude potentially-overlapping subobjects |
| C++14 | `std::is_final` | libraries switch to member storage for final types |
| C++20 | `[[no_unique_address]]` (P0840R2) | member-level EBO and tail-padding reuse; ignored on MSVC ABI (Listing 4.2) |
| C++20 | `std::is_layout_compatible`, `std::is_corresponding_member` (P0466R5) | layout queries |
| C++23 | — | (P1144 discussed; not adopted) |
| C++26 | trivial relocatability (P2786R13): **adopted Feb 2025, removed Nov 2025 (P3920R0)** | no portable relocation in C++26; library-internal traits stay |
| C++26 | static reflection (P2996R13) | layout introspection at compile time (`offset_of`, `size_of` on members) |
| C++29? | P4197 and successors | trivial relocation, redesigned |

---

## 3. Production blueprints

### 3.1 Policy-based storage without paying for empty policies

Use `[[no_unique_address]]` members (through the portability macro in §1.3), not inheritance. Inheritance
breaks on `final` policies (Listing 4.4) and leaks the policy's member names into your class. Pin the result:
`static_assert(sizeof(Handle<FileCloser>) == sizeof(void*))`. Do not mark your own empty policy types `final`.
Listing 4.4 shows that `final` doubles `unique_ptr` in both standard libraries.

### 3.2 Never `memcpy`/`memset` a potentially-overlapping subobject

Copy bases and `[[no_unique_address]]` members by assignment. If you must reset raw bytes, operate on the
**complete object** only, and only if it is trivially copyable. Listing 4.3 is the failure.

### 3.3 Relocation behind an opt-in trait (Listing 4.6)

```cpp
// relocate_n.cpp - trait-gated relocation: memcpy only for types that opted in, move + destroy for the rest
#include <cstddef>
#include <cstring>
#include <memory>
#include <new>
#include <print>
#include <string>
#include <type_traits>
#include <utility>

// Opt-in trait (the pattern behind folly::IsRelocatable, bslmf::IsBitwiseMoveable, Q_RELOCATABLE_TYPE):
// conservative by default, explicitly specialized by the author of a type who has checked it.
template <class T>
struct is_relocatable : std::bool_constant<std::is_trivially_copyable_v<T>> {};

struct Handle {                        // non-trivial move + destructor, but no self-pointers: relocatable
    int* p = nullptr;
    Handle() = default;
    explicit Handle(int v) : p(new int(v)) {}
    Handle(Handle&& o) noexcept : p(std::exchange(o.p, nullptr)) {}
    Handle& operator=(Handle&&) = delete;
    ~Handle() { delete p; }
};
template <>
struct is_relocatable<Handle> : std::true_type {};
static_assert(!is_relocatable<std::string>::value, "never assume a library type is relocatable");

// Subtle buggy way: "everything is just bytes".
template <class T>
T* relocate_n_buggy(T* first, std::size_t n, T* out) {
    std::memcpy(static_cast<void*>(out), static_cast<const void*>(first), n * sizeof(T));
    return out;                        // libstdc++ short strings now point into *first's* storage
}

// Production-hardened way. NOTE: even the memcpy branch is not blessed by ISO C++ today for non-trivially-
// copyable T (no object is created at 'out'); it is the existing practice of libstdc++, libc++, Folly, BDE
// and Qt, which is exactly the gap P1144/P2786 tried to close.
template <class T>
T* relocate_n(T* first, std::size_t n, T* out) noexcept(is_relocatable<T>::value ||
                                                       std::is_nothrow_move_constructible_v<T>) {
    if constexpr (is_relocatable<T>::value) {
        if (n != 0) std::memcpy(static_cast<void*>(out), static_cast<const void*>(first), n * sizeof(T));
    } else {
        for (std::size_t i = 0; i < n; ++i) {
            std::construct_at(out + i, std::move(first[i]));
            std::destroy_at(first + i);
        }
    }
    return out;
}

template <class T, std::size_t N>
struct Buffer {                        // raw storage for N objects
    alignas(T) unsigned char bytes[N * sizeof(T)];
    T* data() { return std::launder(reinterpret_cast<T*>(bytes)); }
};

int main() {
    Buffer<std::string, 3> a, b;
    std::string* s = a.data();
    for (int i = 0; i < 3; ++i) std::construct_at(s + i, std::string(1, char('x' + i)));
    std::string* t = relocate_n(s, 3, b.data());      // move + destroy path: s[] is gone, t[] owns the data
    std::memset(a.bytes, 'Z', sizeof a.bytes);         // reuse the old storage
    std::println("hardened, std::string: {} {} {}", t[0], t[1], t[2]);
    std::destroy(t, t + 3);

    Buffer<Handle, 3> c, d;
    Handle* h = c.data();
    for (int i = 0; i < 3; ++i) std::construct_at(h + i, 10 * (i + 1));
    Handle* k = relocate_n(h, 3, d.data());           // memcpy path (opted in): no destructor runs on h[]
    std::memset(c.bytes, 0, sizeof c.bytes);
    std::println("hardened, Handle     : {} {} {}", *k[0].p, *k[1].p, *k[2].p);
    std::destroy(k, k + 3);

    Buffer<std::string, 1> e, f;
    std::construct_at(e.data(), "short");
    std::string* u = relocate_n_buggy(e.data(), 1, f.data());
    std::memset(e.bytes, 'Z', sizeof e.bytes);
    const char* p = u->data();
    bool into_old = p >= reinterpret_cast<const char*>(e.bytes) && p < reinterpret_cast<const char*>(e.bytes + sizeof e.bytes);
    std::println("buggy,    std::string: data() points into {} storage, first byte '{}'",
                 into_old ? "the OLD" : "its own", p[0]);
    if (!into_old) std::destroy_at(u);                // libstdc++: destroying would free a stack address
}
```

GCC 16.2 + libstdc++:

```text
hardened, std::string: x y z
hardened, Handle     : 10 20 30
buggy,    std::string: data() points into the OLD storage, first byte 'Z'
```

Clang 21.1 + libc++:

```text
hardened, std::string: x y z
hardened, Handle     : 10 20 30
buggy,    std::string: data() points into its own storage, first byte 's'
```

The hardened version takes the memcpy path only for types whose authors specialized the trait (`Handle`), and
uses move + destroy for everything else, including `std::string`, which it refuses to trust because the answer
differs between libraries. The buggy version shows that difference: a dangling SSO pointer with libstdc++, a
string that survives with libc++. **Never relocate polymorphic types with memcpy if you ship on PAuth
platforms.**

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| a derived field "randomly" resets to 0 | `memcpy`/`memset` of `sizeof(Base)` into a base or `[[no_unique_address]]` member (Listing 4.3) | grep `memcpy(this`, `memset(static_cast<Base*>`; UBSan does not catch it |
| struct size differs between Windows and Linux builds | `[[no_unique_address]]` ignored on MSVC; MSVC never reuses tail padding (Listing 4.2) | `static_assert(sizeof(T) == N)` in a header compiled on every platform |
| `unique_ptr` grew to 16 bytes after "hardening" a deleter with `final` | library ABI-compat layout (Listing 4.4) | `static_assert(sizeof(Handle) == sizeof(void*))` |
| corrupted short strings after a custom container's growth | memcpy relocation of a self-referential type (Listing 4.5) | opt-in trait; tests with short strings on libstdc++ |
| PAuth trap after container growth, arm64e only | memcpy relocation of a polymorphic type | never memcpy types with vptrs on PAuth targets |
| ODR/ABI mismatch after adding `[[no_unique_address]]` to a released type | layout change: sizeof and offsets differ between old and new binaries | ABI checkers (abidiff, libabigail); version the inline namespace |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What is EBO, and why does unique_ptr care?"</b></summary>

**Initial prompt.** "What is the empty base optimization? Where does the standard library use it?"

**L5 textbook answer.** "If you inherit from an empty class it takes no space. `unique_ptr` uses it for the
deleter, so `unique_ptr` is the size of a pointer."

**Why L5 breaks.** True for the default deleter, but incomplete in four verified ways (Listing 4.4): a
function-pointer deleter makes it 16 bytes; a `std::function` deleter 40 (libstdc++) or 64 (libc++); a `final`
empty deleter 16 in **both** libraries, because of ABI compatibility with their pre-C++20 layouts; and
inheritance-based EBO does not compile at all for `final` types. The L5 answer also misses the one-address rule
(why empties have size 1 at all) and the same-type collision (`EboBlocked`, 16 bytes).

**L7 principal defense.** "EBO is the ABI-mandated ability of an empty base to overlap other subobjects. Since
C++20 I get the same for members with `[[no_unique_address]]`, which also handles `final` types. But library
layouts are frozen by ABI, so for `unique_ptr` I keep deleters empty, non-final and stateless, and I pin the size
with a `static_assert`. On Windows I need `[[msvc::no_unique_address]]`."
</details>

<details><summary><b>Chain 2 ⚡ "Any pitfalls with [[no_unique_address]]?"</b></summary>

**Initial prompt.** "We want to add `[[no_unique_address]]` to policy members across our library. Risks?"

**L5 textbook answer.** "No, it's a pure optimization. Worst case the compiler ignores it."

**Why L5 breaks.** "The compiler ignores it" is precisely the MSVC behaviour (Listing 4.2), so Windows and Linux
layouts diverge. Adding it to a released type **changes `sizeof` and member offsets**, which is an ABI break for
every binary compiled against the old header. Mixing objects compiled before and after is an ODR violation
that shows up as memory corruption. It also makes the member *potentially-overlapping*, so existing `memcpy`
code that was valid becomes UB and can clobber neighbours (Listing 4.3's mechanism). Finally, two members of the
same empty type still need distinct addresses (`NuaTwoSame`), although here they still fit in 8 bytes.

**L7 principal defense.** "Treat it as an ABI change: do it at a major version, behind an inline-namespace
version bump, with abidiff in CI. Use the portability macro. Audit `memcpy`/`memset` and `offsetof` users of the
affected types first. Then `static_assert` the new sizes on every target platform."
</details>

<details><summary><b>Chain 3 🔥 "Header is trivially copyable, so memcpy into it is fine?"</b></summary>

**Initial prompt.** "Code review: `memcpy(static_cast<Header*>(&msg), &defaults, sizeof(Header))`. Header is
trivially copyable. Approve?"

**L5 textbook answer.** "Yes. Trivially copyable types can be copied with memcpy."

**Why L5 corrupts memory.** The guarantee in [basic.types.general] excludes potentially-overlapping subobjects,
and `msg`'s `Header` is a base. On the Itanium ABI a non-POD base's tail padding is reused: `flags` sits at
offset 5, inside `sizeof(Header)` = 8. Listing 4.3 shows `flags` overwritten with `defaults`' padding byte. On
MSVC this layout does not happen (no tail-padding reuse), so the bug is Linux/macOS/Android-only. On ARM64
the layout is the same as on x86-64, so this one is an ABI bug, not an ARM bug.

**L7 principal defense.** "Reject it: assign (`static_cast<Header&>(msg) = defaults;`), which copies only `dsize`
bytes. A memcpy is allowed only on a *complete* object of trivially copyable type, which I would encode as a
helper that `static_assert`s `std::is_trivially_copyable_v<T>` and takes `T&` to a complete object."
</details>

<details><summary><b>Chain 4 🧊 "What is trivial relocation, and why isn't it in C++26?"</b></summary>

**Initial prompt.** "Explain trivial relocatability. Is it in C++26?"

**L5 textbook answer.** "It means move + destroy can be a memcpy. C++26 added it with
`std::is_trivially_relocatable`."

**Why L5 breaks (and what goes wrong on ARM64e/PAuth).** It *was* in the C++26 working draft (P2786R13, February
2025) and was **removed in November 2025** (P3920R0). The candidate's information is a year stale. The
technical subtleties show why the design is hard. P2786 counts polymorphic types as trivially relocatable. On
PAuth platforms the vptr signature is bound to the object's address (file 01, §1.7). Yet Clang 21's
pre-removal implementation lowers `__builtin_trivially_relocate` to a plain `memmove` on the PAuth test
target (Listing 4.7), so relocation needs re-signing that a "memcpy" does not do (an inference from codegen,
not executed). Two incompatible semantic models competed (P1144's "equivalent to memcpy" vs P2786's
"relocate + replaceable"). Library types differ by implementation (libstdc++'s string is self-referential,
libc++'s is not; Listing 4.5).

**L7 principal defense.** "In C++26 there is no portable trait. Containers keep using their internal ones
(libstdc++'s `__is_bitwise_relocatable`, libc++'s `__libcpp_is_trivially_relocatable`), and my code uses an
opt-in trait (Listing 4.6): conservative default, explicit specializations reviewed by the type's owner,
polymorphic types excluded when we ship on arm64e. I would track P4197's successors for C++29, and Clang's
`__builtin_is_cpp_trivially_relocatable` exists today if a project can depend on Clang."
</details>

<details><summary><b>Chain 5 ⚡ "Why isn't std::string trivially relocatable?"</b></summary>

**Initial prompt.** "`std::string` is just a pointer, a size and a capacity. Why can't `vector<string>` growth
memcpy?"

**L5 textbook answer.** "It can. Moving a string just copies those three words."

**Why L5 corrupts memory.** Depends on the library. libstdc++'s string (32 bytes) keeps `_M_p` pointing at its
own internal buffer for short strings. Listing 4.5: after a memcpy, the copy's `data()` points into the *old*
object, prints `XXXXX` after the old storage is reused, and would `delete` a stack address on destruction.
libc++'s string (24 bytes) has no self-pointer, and libc++ does relocate strings internally (its trait says
`true`). Code that "works" with libc++ corrupts memory with libstdc++. (MSVC's STL uses yet another layout,
which this harness did not test.)

**L7 principal defense.** "SSO layouts are implementation details with different relocation properties. Generic
code must not assume either. Use move + destroy, or let the standard containers, which know their own library,
do the relocation. If profiling says relocation of strings dominates, the fix is usually `reserve()`, or a
container that stores strings out of line."
</details>

<details><summary><b>Chain 6 🧊 "Why is our unique_ptr 16 bytes?"</b></summary>

**Initial prompt.** "After someone marked our `FileCloser` deleter `final`, our handle structs grew by 8 bytes
each and a cache-line-packed struct now spills. Why?"

**L5 textbook answer.** "`final` shouldn't change size. Probably padding somewhere else."

**Why L5 breaks.** It is exactly `final`. Both standard libraries compress the deleter only if it is empty **and
not final** (libstdc++'s `_Head_base<..., __empty_not_final<Head>::value>`, libc++'s legacy-layout padding
logic), to keep `sizeof(unique_ptr<T, D>)` identical to the old inheritance-based layouts (Listing 4.4: 16 bytes
in both). `[[no_unique_address]]` could store it in 0 bytes (`NuaPair`: 8), but that would break ABI for
existing binaries.

**L7 principal defense.** "Revert the `final`, add `static_assert(sizeof(Handle) == 8)` next to the type so this
cannot regress silently, and document that policy and deleter classes must not be `final`. The broader lesson:
in a standard library, layout decisions made in 2005 still constrain 2026."
</details>

<details><summary><b>Chain 7 ⚡ "Design a memory-tight handle type for an HFT order book"</b></summary>

**Initial prompt.** "Each order holds an owning handle to a pooled buffer, a policy for returning it to the
pool, and a 32-bit size. 10⁸ orders. Design the handle."

**L5 textbook answer.** "`std::unique_ptr<Buffer, PoolDeleter>` plus a `uint32_t`."

**Why L5 breaks.** If `PoolDeleter` carries a pool pointer, it is 8 bytes, and the handle becomes 24 bytes after
padding (8 + 8 + 4 + 4). If someone makes it `final`, the deleter is no longer compressed (Listing 4.4). The
handle also travels through memory at every call boundary (file 02, §1.4). At 10⁸ objects every 8 bytes is
800 MB.

**L7 principal defense.** "Make the pool a template parameter or a global per type (empty deleter, 0 bytes via
`[[no_unique_address]]`). Store a 32-bit index into the pool instead of a 64-bit pointer. Put the size into
the 32 bits that alignment would otherwise waste. That is an 8-byte handle, `static_assert`ed. Make it relocatable
with an opt-in trait (Listing 4.6), so book reallocation is a memcpy. Consider `[[clang::trivial_abi]]` if it
crosses hot non-inline calls. Then measure cache misses per order, not bytes per order."
</details>

<details><summary><b>Chain 8 🧊 "Is tail-padding reuse an x86 thing or an ABI thing?"</b></summary>

**Initial prompt.** "Our struct is 8 bytes on Linux and 12 on Windows, same compiler family (Clang). Bug?"

**L5 textbook answer.** "Different alignment rules for x86 on Windows."

**Why L5 breaks.** Alignment is the same. The difference is the **C++ ABI**: Itanium (Linux, macOS, MinGW) reuses
a non-POD base's tail padding, and MSVC never does (Listing 4.2, `TailReuse` 8 vs 12). Clang follows the
platform ABI (`clang` vs `clang-cl` / `-target *-windows-msvc`). On AArch64 Linux the result is the same as on
x86-64 Linux. The same 8-vs-12 difference applies to `[[no_unique_address]]`.

**L7 principal defense.** "Layout is per ABI, not per architecture. Anything shared across platforms (wire
formats, shared memory, files) uses trivially copyable standard-layout types with explicit padding fields, plus a
`static_assert` on `sizeof` and every `offsetof`, compiled on every target in CI."
</details>

---

## 6. Invariants checklist

- [ ] Empty policies are stored with `[[no_unique_address]]` (via a portability macro), not inheritance; they
      are not `final`.
- [ ] `static_assert(sizeof(...))` for every size-sensitive type, compiled on every target ABI.
- [ ] No `memcpy`/`memset` into base subobjects or `[[no_unique_address]]` members.
- [ ] Adding or removing `[[no_unique_address]]` is treated as an ABI change.
- [ ] Relocation by memcpy only behind an opt-in trait; never for library types, and never for polymorphic types
      on PAuth platforms.
- [ ] No reliance on `std::is_trivially_relocatable` (not in C++26); Clang builtins only behind feature checks.
- [ ] Cross-platform shared layouts use explicit padding and `offsetof` assertions.

## 7. References

- Itanium C++ ABI §2.2–2.4 (dsize, nvsize, POD for layout, empty bases): <https://itanium-cxx-abi.github.io/cxx-abi/abi.html#layout>
- P0840R2 (`[[no_unique_address]]`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0840r2.html>
- MSVC and `[[msvc::no_unique_address]]`: <https://devblogs.microsoft.com/cppblog/msvc-cpp20-and-the-std-cpp20-switch/>
- P1144 (trivially relocatable, O'Dwyer): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p1144r12.html>
- P2786R13 (trivial relocatability for C++26): <https://open-std.org/jtc1/sc22/wg21/docs/papers/2025/p2786r13.html>
- P3920R0 (removal wording): <https://www.open-std.org/JTC1/sc22/wg21/docs/papers/2025/p3920r0.html>
- P4197R0 (design questions after removal): <https://open-std.org/JTC1/SC22/WG21/docs/papers/2026/p4197r0.html>
- Herb Sutter, Kona 2025 trip report: <https://herbsutter.com/author/herbsutter/page/2/>
- folly `IsRelocatable` (Traits.h): <https://github.com/facebook/folly/blob/main/folly/Traits.h>
- libc++ ABI guarantees and flags: <https://libcxx.llvm.org/DesignDocs/ABIVersioning.html>
