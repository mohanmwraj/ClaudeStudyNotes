# 03 · Zero-cost polymorphism: CRTP, mixins, deducing `this`, `std::variant` visitors, type erasure

> **Scope.** C++ offers five ways to call "the right `area()`": virtual functions, CRTP (static dispatch through a
> template base), deducing `this` (C++23), `std::variant` + `visit` (closed sets of value types), and data-oriented
> per-type arrays (no dispatch at all). Type erasure (Folder 04, file 03) is the sixth. This file shows the CRTP
> mechanics and its classic bug, the deducing-`this` replacement, and one benchmark that runs the same computation
> through four strategies.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 6.4 | `crtp.cpp` | a CRTP mixin with a private-constructor guard against the wrong-`Derived` bug; a counting mixin; the deducing-`this` mixin; EBO keeps mixins free | run + expected diagnostic on both |
| 6.5 | `poly_bench.cpp` | 1M shapes: virtual in random order 8.3–10.2 ns, sorted by type 4.6–5.7, `variant` 5.8–7.9, per-type arrays 1.0–1.25 | run, both compilers (3 runs) |

**Verification line.** As in Folders 01–05. Benchmark numbers are ranges over three runs.

---

## 1. First principles

### 1.1 CRTP and mixins (Listing 6.4)

```text
 template <class Derived> struct Printable { void print() const { static_cast<const Derived&>(*this).describe(); } };
 struct Order : Printable<Order> { std::string describe() const; };
   - the base knows the derived type at compile time: calls are direct and inlinable, no vptr
   - each Derived gets its own base type (Printable<Order> != Printable<Trade>): no common base for containers
   - the static_cast is unchecked: if Derived is wrong, it is UB
```

```cpp
// crtp.cpp - CRTP mixins, the wrong-Derived bug and its guard, and the C++23 deducing-this replacement
#include <print>
#include <string>

// Classic CRTP mixin: the base calls into the derived class without virtual dispatch.
template <class Derived>
class Printable {
public:
    void print() const { std::println("[{}]", self().describe()); }

private:
    Printable() = default;             // guard: only Derived (a friend) can construct this base...
    friend Derived;                    // ...so 'struct B : Printable<A>' fails to compile
    const Derived& self() const { return static_cast<const Derived&>(*this); }
};

template <class Derived>
class Counted {                        // a second mixin: per-derived-type instance counter
public:
    static inline int live = 0;
    Counted() { ++live; }
    Counted(const Counted&) { ++live; }
    ~Counted() { --live; }
};

struct Order : Printable<Order>, Counted<Order> {
    int id = 7;
    std::string describe() const { return "Order " + std::to_string(id); }
};
#ifdef SHOW_WRONG_DERIVED
struct Trade : Printable<Order> {      // copy-paste bug: should be Printable<Trade>
    std::string describe() const { return "Trade"; }
};
void use_trade() { Trade{}.print(); }  // without the guard: static_cast to Order& on a Trade -> UB
#endif

// C++23: deducing 'this' gives the mixin the real type directly; there is nothing to get wrong.
struct PrintableDT {
    void print(this const auto& self) { std::println("<{}>", self.describe()); }
};
struct Quote : PrintableDT {
    std::string describe() const { return "Quote"; }
};

int main() {
    Order a, b;
    a.print();
    std::println("Counted<Order>::live = {}", Counted<Order>::live);
    { Order c = a; std::println("after a copy: live = {}", Counted<Order>::live); }
    std::println("after the copy is destroyed: live = {}", Counted<Order>::live);
    Quote{}.print();
    std::println("sizeof(Order) = {} (two empty mixin bases + one int: EBO makes the mixins free)", sizeof(Order));
    (void)b;
}
```

Output (verified, both compilers):

```text
[Order 7]
Counted<Order>::live = 2
after a copy: live = 3
after the copy is destroyed: live = 2
<Quote>
sizeof(Order) = 4 (two empty mixin bases + one int: EBO makes the mixins free)
```

With `-DSHOW_WRONG_DERIVED` (`struct Trade : Printable<Order>`, a copy-paste bug), the private-constructor guard turns the
UB into a compile error (GCC, then Clang):

```text
crtp.cpp:34:26: error: 'constexpr Printable<Derived>::Printable() [with Derived = Order]' is private within this context
crtp.cpp:34:26: error: base class 'Printable<Order>' has private default constructor
```

* **The guard**: `Printable`'s constructor is private and `Derived` is a friend. Only the class named as the template
  argument can construct the base. Without it, `Trade{}.print()` would `static_cast` a `Trade` to `Order&` and read a
  `describe()` that doesn't exist on that object.
* **Mixins compose**: `Order` inherits `Printable<Order>` and `Counted<Order>`. Each `Counted<T>` has its own static
  counter per derived type, which no single virtual base can do. Both bases are empty, so EBO keeps `sizeof(Order)` at 4
  (Folder 01, file 04).
* **Deducing `this` removes the template parameter**: `PrintableDT::print(this const auto& self)` sees `Quote` directly.
  There is no `Derived` argument to get wrong, the base is a single non-template type, and the call is still static.
  Limits: the function is a template (defined in the header), and it cannot be virtual.

### 1.2 Four strategies, one computation (Listing 6.5)

```cpp
// poly_bench.cpp - one computation (sum of areas of 1M shapes), four polymorphism strategies (one run)
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <memory>
#include <print>
#include <random>
#include <variant>
#include <vector>

// 1. Classic runtime polymorphism.
struct Shape {
    virtual ~Shape() = default;
    virtual double area() const = 0;
};
struct Circle final : Shape { double r; explicit Circle(double v) : r(v) {} double area() const override { return 3.14159 * r * r; } };
struct Square final : Shape { double s; explicit Square(double v) : s(v) {} double area() const override { return s * s; } };
struct Tri final : Shape { double b, h; Tri(double x, double y) : b(x), h(y) {} double area() const override { return 0.5 * b * h; } };

// 2. Closed set as a value type.
struct VCircle { double r; };
struct VSquare { double s; };
struct VTri { double b, h; };
using VShape = std::variant<VCircle, VSquare, VTri>;
struct AreaOf {
    double operator()(const VCircle& c) const { return 3.14159 * c.r * c.r; }
    double operator()(const VSquare& s) const { return s.s * s.s; }
    double operator()(const VTri& t) const { return 0.5 * t.b * t.h; }
};

template <class F>
double ns_per(std::size_t n, F f) {
    auto t0 = std::chrono::steady_clock::now();
    volatile double sink = f();
    auto t1 = std::chrono::steady_clock::now();
    (void)sink;
    return std::chrono::duration<double, std::nano>(t1 - t0).count() / static_cast<double>(n);
}

int main() {
    constexpr std::size_t kN = 1'000'000;
    std::mt19937 rng(11);
    std::vector<int> kinds(kN);
    for (auto& k : kinds) k = static_cast<int>(rng() % 3);  // random mix: dispatch is unpredictable

    std::vector<std::unique_ptr<Shape>> objs;
    std::vector<VShape> vals;
    std::vector<VCircle> circles;      // 4. data-oriented: one array per type, no dispatch at all
    std::vector<VSquare> squares;
    std::vector<VTri> tris;
    for (std::size_t i = 0; i < kN; ++i) {
        double x = 1.0 + static_cast<double>(i % 7);
        switch (kinds[i]) {
        case 0: objs.push_back(std::make_unique<Circle>(x)); vals.emplace_back(VCircle{x}); circles.push_back({x}); break;
        case 1: objs.push_back(std::make_unique<Square>(x)); vals.emplace_back(VSquare{x}); squares.push_back({x}); break;
        default: objs.push_back(std::make_unique<Tri>(x, x)); vals.emplace_back(VTri{x, x}); tris.push_back({x, x}); break;
        }
    }
    std::vector<const Shape*> by_type;   // the same objects, visited grouped by type (predictable dispatch)
    for (auto& o : objs) by_type.push_back(o.get());
    std::stable_partition(by_type.begin(), by_type.end(), [](const Shape* s) { return dynamic_cast<const Circle*>(s); });
    std::stable_partition(by_type.begin(), by_type.end(), [](const Shape* s) { return !dynamic_cast<const Tri*>(s); });

    double t_virtual = ns_per(kN, [&] { double s = 0; for (auto& o : objs) s += o->area(); return s; });
    double t_sorted = ns_per(kN, [&] { double s = 0; for (auto* o : by_type) s += o->area(); return s; });
    double t_variant = ns_per(kN, [&] { double s = 0; for (auto& v : vals) s += std::visit(AreaOf{}, v); return s; });
    double t_soa = ns_per(kN, [&] {
        double s = 0;
        for (auto& c : circles) s += 3.14159 * c.r * c.r;
        for (auto& q : squares) s += q.s * q.s;
        for (auto& t : tris) s += 0.5 * t.b * t.h;
        return s;
    });
    std::println("1M shapes, random type order (ns per shape, one run):");
    std::println("  virtual, heap objects, random order   {:5.2f}", t_virtual);
    std::println("  virtual, same objects sorted by type  {:5.2f}", t_sorted);
    std::println("  std::variant + visit, contiguous      {:5.2f}", t_variant);
    std::println("  one array per type (no dispatch)      {:5.2f}", t_soa);
    std::println("sizeof: Circle object {} (+ heap header), VShape {}, VCircle {}", sizeof(Circle), sizeof(VShape),
                 sizeof(VCircle));
}
```

GCC 16.2 (one run):

```text
1M shapes, random type order (ns per shape, one run):
  virtual, heap objects, random order    8.42
  virtual, same objects sorted by type   4.43
  std::variant + visit, contiguous       5.40
  one array per type (no dispatch)       1.05
sizeof: Circle object 16 (+ heap header), VShape 24, VCircle 8
```

Clang 21.1 (one run):

```text
1M shapes, random type order (ns per shape, one run):
  virtual, heap objects, random order    8.33
  virtual, same objects sorted by type   4.86
  std::variant + visit, contiguous       6.60
  one array per type (no dispatch)       1.05
sizeof: Circle object 16 (+ heap header), VShape 24, VCircle 8
```

Over three runs per compiler: virtual in random order **8.3–10.2 ns** per shape; the same virtual calls over the same
objects visited grouped by type **4.6–5.7 ns**; `std::variant` + `visit` over a contiguous array **5.8–7.9 ns**; one array
per type **1.0–1.25 ns**.

* **The dominant cost is not the vtable load. It is the unpredictable branch and the memory.** Sorting the *same* virtual
  calls by type nearly halves the time: the indirect-branch predictor now sees long runs of the same target.
  `unique_ptr`-held objects are also scattered on the heap (16 bytes + allocator header each).
* **`variant` is contiguous (24 bytes per element) but still dispatches per element.** libstdc++ compiles it to a
  switch, libc++ to a function-pointer table (Folder 02, file 02), and with a random type mix either one mispredicts.
  It beat random-order virtual dispatch by less than people expect, and lost to sorted virtual dispatch.
* **Per-type arrays win by 5–9×**: no dispatch, dense data, and loops that the compiler vectorizes. This is the
  data-oriented design argument in one number. The cost is that the "object" no longer exists as one thing: code that
  needs heterogeneous order (render in z-order, process events in arrival order) has to keep indices.
* CRTP and deducing `this` are not in the benchmark because they don't support heterogeneous collections: their
  dispatch happens at compile time, per type. In a loop over one type, they compile to the same code as the per-type array.

### 1.3 Choosing a strategy

| Need | Strategy | Why |
|---|---|---|
| open set of types (plugins, user extensions) | virtual functions / type erasure | only option where new types arrive after compilation |
| closed set, value semantics, moderate counts | `std::variant` | no heap, no vptr, exhaustive `visit` checked by the compiler |
| hot loops over many objects | per-type arrays (SoA/data-oriented) | no dispatch, vectorizable |
| reusable behaviour mixed into concrete types | CRTP / deducing-`this` mixins | static calls, per-type state, zero size |
| one type-erased callable or value | `std::function`, `move_only_function`, `any` / a hand-written erasure | Folder 04, file 03 |

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| virtual functions, templates, CRTP (as an idiom) | C++98 | CRTP named by Coplien (1995) |
| `final`, `override` | C++11 | `final` enables devirtualization (Folder 01) |
| `std::variant`, `std::visit` | C++17 (P0088) | closed-set polymorphism |
| the `overloaded` lambda-set idiom with CTAD | C++17 | aggregate CTAD made the deduction guide unnecessary in C++20 |
| deducing `this` | C++23 (P0847R7) | CRTP without the template parameter |
| `visit<R>`, `variant` member `visit` | C++20 (P0655), C++26 (P2637) | — |
| static reflection | C++26 (P2996) | generate mixin-like behaviour (printers, serializers) without inheritance (file 04) |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| CRTP base | public base constructor (wrong `Derived` compiles, UB at run time) | private constructor + `friend Derived;`, or deducing `this` |
| polymorphic collection in a hot loop | `vector<unique_ptr<Base>>` in arbitrary order | partition by type first, or per-type arrays |
| closed set of message types | an inheritance hierarchy + `dynamic_cast` chains | `std::variant` + `visit`, with exhaustive overloads |
| shared behaviour across unrelated types | a common virtual base "just for reuse" | mixins (CRTP / deducing `this`), or free functions constrained by concepts |
| needing both open extension and speed | everything virtual | virtual at the boundary (plugin API), data-oriented inside |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| crash or garbage from a CRTP call | wrong template argument (`Trade : Base<Order>`) | private-constructor guard; deducing `this` |
| code size explosion | many CRTP / deducing-`this` instantiations | symbol size reports (`nm --size-sort`), `-ftime-trace` |
| `visit` doesn't compile after adding an alternative | non-exhaustive visitor | intended: fix the visitor (an advantage over virtual hierarchies) |
| polymorphic loop slower than expected | random type order defeats the indirect-branch predictor | sort/partition by type; measure |
| `sizeof` grows after adding a mixin | the mixin is not empty, or two bases of the same type | `static_assert(sizeof(T) == ...)`; Folder 01, file 04 |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Explain CRTP and when to use it"</b></summary>

**Initial prompt.** "What is the curiously recurring template pattern, and why use it instead of virtual functions?"

**L5 textbook answer.** "Static polymorphism: the base calls derived methods through a template, so it's faster than
virtual."

**Why L5 breaks.** "Faster than virtual" is true per call and usually irrelevant (file 01 of Folder 01 measured a virtual
call at ~1–6 ns, and Listing 6.5 shows the real cost is branch prediction and memory). The bigger differences: CRTP gives
**no common base**, so you cannot store a `vector<Printable<?>>`; the unchecked `static_cast` makes the wrong-`Derived` bug
possible (Listing 6.4); and each instantiation adds code. CRTP shines for *mixins* (per-type behaviour and state, like
`Counted<T>`), not for replacing runtime polymorphism.

**L7 principal defense.** "CRTP or deducing `this` for mixins and compile-time customization points (counting, comparison
operators, interface completion like `boost::iterator_facade`). Virtual functions for heterogeneous runtime collections.
In C++23 code I prefer deducing `this`, which removes the template parameter and the bug class with it."
</details>

<details><summary><b>Chain 2 🧊 "What goes wrong with CRTP?"</b></summary>

**Initial prompt.** "Code review: `struct Trade : Printable<Order> {}`. What happens?"

**L5 textbook answer.** "It won't compile because the types don't match."

**Why L5 breaks.** It compiles. `Printable<Order>::print()` does `static_cast<const Order&>(*this)` on a `Trade`, which is
UB: it reads `Order` members at `Trade`'s addresses. Only a guard makes it a compile error (Listing 6.4: a private base
constructor with `friend Derived;`, rejected by both compilers).

**L7 principal defense.** "Every CRTP base in our code has the private-constructor guard, or is written with deducing
`this`. A `static_assert(std::is_base_of_v<Printable, Derived>)` inside a member function is a second check, because it is
evaluated where `Derived` is complete."
</details>

<details><summary><b>Chain 3 🔥 "variant or virtual for performance?"</b></summary>

**Initial prompt.** "We have 1M shapes of 3 types. Switching from virtual to `std::variant` will make it much faster,
right?"

**L5 textbook answer.** "Yes, variant avoids the vtable and heap, so it's much faster."

**Why L5 breaks.** Listing 6.5: `variant` (5.8–7.9 ns) beat random-order virtual dispatch (8.3–10.2 ns) only modestly,
and was *slower* than the same virtual calls sorted by type (4.6–5.7 ns). With a random type mix, `variant` still
dispatches per element, and the branch (or function-table call in libc++) mispredicts. The structure that wins by 5–9× is
per-type arrays (1.0–1.25 ns), where there is no dispatch at all.

**L7 principal defense.** "The cost model is prediction plus locality, not 'vtable vs no vtable'. I'd first sort or
partition by type (cheap, big win), then consider per-type arrays for the hot loop, and use `variant` where value
semantics and exhaustiveness matter. I would measure all three on the real distribution of types."
</details>

<details><summary><b>Chain 4 ⚡ "Deducing this vs CRTP"</b></summary>

**Initial prompt.** "Show how C++23 deducing `this` replaces CRTP."

**L5 textbook answer.** "You write `this auto& self` instead of the template parameter."

**Why L5 breaks.** Correct in outline. The details an L7 answer adds: (1) the base becomes a single non-template type, so
the wrong-`Derived` bug disappears; (2) `self` is deduced per call, so a `const` object deduces `const Derived&`; (3) it
cannot be used for *per-type static state* (`Counted<T>::live` needs the template parameter), and (4) the member functions
are templates (header-defined, instantiated per derived type).

**L7 principal defense.** "Deducing `this` for interface completion and behaviour mixins; CRTP where the mixin needs
per-type static data or must name `Derived` in its own declarations (types, member typedefs). Both are static; neither
replaces virtual dispatch for runtime collections."
</details>

<details><summary><b>Chain 5 🧊 "The overloaded idiom"</b></summary>

**Initial prompt.** "Explain `template <class... F> struct overloaded : F... { using F::operator()...; };`."

**L5 textbook answer.** "It lets you pass several lambdas to `std::visit`."

**Why L5 breaks.** That is the use. The mechanics: it inherits from each lambda's closure type (variadic base list, C++11),
pulls every `operator()` into one overload set with a pack `using` declaration (C++17, P0195), and is constructed by
aggregate initialization from the lambdas. C++17 needed a deduction guide (`template <class... F> overloaded(F...) ->
overloaded<F...>;`); C++20 aggregate CTAD (P1816) makes it unnecessary. Overload resolution then picks the best match per
alternative, which includes conversions. A `[](double)` lambda will silently accept an `int` alternative if there is no
exact match.

**L7 principal defense.** "Use it for exhaustive visitors, and make sure each alternative has an *exact* overload (or a
constrained generic fallback that `static_assert`s), so an added alternative breaks the build instead of being converted
silently."
</details>

<details><summary><b>Chain 6 ⚡ "Why does sorting by type speed up virtual calls?"</b></summary>

**Initial prompt.** "Sorting our object list by dynamic type made a virtual-call loop 2× faster without changing any code.
Why?"

**L5 textbook answer.** "Better cache locality."

**Why L5 breaks.** Partly, but here the objects themselves did not move: the listing only reordered pointers (Listing 6.5).
The main effect is **indirect branch prediction**: in random order, each call's target is unpredictable, so the CPU
mispredicts about two thirds of the time with three types. Grouped by type, the target repeats, and the predictor is
almost always right. The `vtable` load is the same in both cases.

**L7 principal defense.** "For polymorphic hot loops, order by type (or by vptr) once, then iterate. If objects are
allocated per type in separate pools, both the branch predictability and the memory locality improve. Measure with branch
miss counters (`perf stat -e branch-misses`)."
</details>

<details><summary><b>Chain 7 🔥 "Design a plugin interface that's also fast"</b></summary>

**Initial prompt.** "Third-party plugins implement audio effects processed per sample. Design the interface."

**L5 textbook answer.** "`struct Effect { virtual float process(float sample) = 0; };`"

**Why L5 breaks.** A virtual call per sample (48,000+ per second per channel, times plugins) cannot be inlined or
vectorized. The plugin boundary is open (virtual is right there), but per-element dispatch is the wrong granularity.

**L7 principal defense.** "Virtual at the *batch* level: `virtual void process(std::span<float> block) = 0;`. One indirect
call per block (e.g. 256 samples); inside, the plugin's own code is a tight, vectorizable loop. The same principle as
per-type arrays: dispatch once, then process many. ABI-stable plugin interfaces would also use C entry points and
versioned structs (Folder 01)."
</details>

<details><summary><b>Chain 8 🧊 "Where do mixins break EBO?"</b></summary>

**Initial prompt.** "Our class has four empty mixin bases and `sizeof` is 16 instead of 8. Why?"

**L5 textbook answer.** "Empty classes always take one byte."

**Why L5 breaks.** EBO lets empty bases take zero bytes (Listing 6.4: `sizeof(Order) == 4` with two mixins), *unless* two
base subobjects of the **same type** would share an address. That happens when two mixins themselves derive from a common
empty helper base, or when a mixin's type also appears as the first member (Folder 01, file 04, `EboBlocked`). The MSVC ABI
is also stricter about EBO with multiple empty bases than Itanium.

**L7 principal defense.** "Make mixins distinct types (CRTP gives that for free: `Counted<Order>` vs `Counted<Trade>`),
avoid shared empty helper bases, and `static_assert` the size of types that live in large arrays or in shared memory, on
every target ABI."
</details>

---

## 6. Invariants checklist

- [ ] CRTP bases have the private-constructor + `friend Derived` guard, or use deducing `this`.
- [ ] Polymorphic hot loops are ordered by type, or the data is split per type.
- [ ] Visitors have exact overloads per alternative; adding an alternative breaks the build.
- [ ] Open extension points dispatch per batch, not per element.
- [ ] Sizes of mixin-composed types are pinned with `static_assert` on every target ABI.

## 7. References

- P0847R7 (deducing `this`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2021/p0847r7.html>
- P0195R2 (pack expansion in using-declarations): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0195r2.html>
- Boost.STLInterfaces / `iterator_facade` (CRTP in practice): <https://www.boost.org/doc/libs/release/doc/html/stl_interfaces.html>
- Mike Acton, "Data-Oriented Design and C++", CppCon 2014: <https://www.youtube.com/watch?v=rX0ItVEVjHc>
- Sean Parent, "Better Code: Runtime Polymorphism", NDC 2017.
