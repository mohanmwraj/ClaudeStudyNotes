# 04 · 30 bar-raiser questions: core C++, the ABI, the STL, templates, and lifetimes

> **Scope.** The non-concurrency half of a senior C++ loop: object layout and the Itanium ABI, value categories and
> elision, lifetimes and aliasing, containers and algorithms, smart pointers, templates and compile-time programming.
> As in file 03, every answer points to a listing in Folders 01–06 that compiled or ran on GCC 16 and Clang 21. The
> point is to answer with *what the compiler and library actually do*, not with rules of thumb.

**How to use it.** Answer each prompt before reading on. The L7 version always includes the mechanism (layout,
instructions, library internals), the evidence (a listing), and the engineering decision.

---

## 1. First principles

### 1.1 What the questions test

| Area | Questions | Evidence in this KB |
|---|---|---|
| object model and ABI | Q1–Q4, Q8, Q28 | [Folder 01](../01-ABI-Object-Model-Lifetimes-and-Value-Categories/) |
| value categories, elision, moves | Q5–Q7 | [Folder 01, file 02](../01-ABI-Object-Model-Lifetimes-and-Value-Categories/02-value-categories-lvalue-prvalue-xvalue-rvo-nrvo-and-move-noexcept.md) |
| lifetimes and aliasing | Q9, Q10, Q29 | [Folder 01, file 03](../01-ABI-Object-Model-Lifetimes-and-Value-Categories/) and [Folder 02](../02-Chronological-C++-Standards-Evolution-C++11-to-C++26/) |
| containers | Q11–Q15 | [Folder 03](../03-STL-Containers-Internals-Memory-Layouts-and-Tradeoffs/) |
| algorithms, ranges, callables | Q16–Q18 | [Folder 04](../04-STL-Algorithms-Ranges-Views-and-Functional-Internals/) |
| ownership | Q19–Q22 | [Folder 05](../05-Smart-Pointers-RAII-and-Memory-Management-Internals/) |
| templates and compile time | Q23–Q27, Q30 | [Folder 06](../06-Templates-Concepts-Compile-Time-Programming-and-Zero-Cost-Polymorphism/) and [Folder 02](../02-Chronological-C++-Standards-Evolution-C++11-to-C++26/) |

### 1.2 Answer shape

1. **Mechanism**: "a vptr per polymorphic subobject, thunks adjust `this`", not "virtual functions are slower".
2. **Evidence**: the layout dump, the instructions, or a measurement with its conditions.
3. **Decision**: what you'd write instead, and the check (`static_assert`, sanitizer, benchmark) that keeps it right.

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| object model | move semantics, `noexcept` | — | guaranteed elision, `std::launder` | implicit-lifetime types, `[[no_unique_address]]`, `bit_cast` | `start_lifetime_as`, deducing `this` | trivial relocation adopted then removed (P2786) |
| library | `unordered_*`, `shared_ptr`, `function` | heterogeneous lookup | `string_view`, `optional`, `variant`, pmr | ranges, `span`, `format` | `expected`, `flat_map`, `move_only_function`, `generator` | `inplace_vector`, `function_ref`, hive (library-provided), `std::execution` |
| templates | variadics | variable templates | fold expressions, `if constexpr`, CTAD | concepts, `consteval`, `constinit` | `if consteval` | pack indexing, static reflection, contracts |

---

## 3. Production blueprints: answer anti-patterns

| Anti-pattern | What it sounds like | L7 version |
|---|---|---|
| performance folklore | "virtual calls are slow" | "8.3–10.2 ns in random type order, 4.6–5.7 sorted; the branch predictor and data layout dominate (Folder 06)" |
| standard text without implementations | "`std::string` has SSO" | "15 chars in libstdc++, 22 in libc++, so the same code allocates on one and not the other (Folder 03)" |
| ignoring ABI | "just add a member" | "layout changes break every binary that shares the type; check with a layout dump" |
| UB as a corner case | "it works in practice" | "GCC deleted the rest of `main` for one wrong cast (Folder 01): UB is an optimizer input" |

---

## 4. Failure modes in the interview itself

| Symptom | Root cause | Remedy |
|---|---|---|
| an answer that's true for one library only | conflating the standard with libstdc++ | say which library; know where they differ |
| unable to explain a 2× surprise | no mental model of cache and branch behaviour | relate every cost to memory layout or a mispredicted branch |
| "the compiler will optimize it" | no idea what it actually emits | read the asm (Godbolt-style), as every folder here does |

---

## 5. The 30 questions

<details><summary><b>Q 1 🔥 "Draw the object layout for multiple inheritance"</b></summary>

**Initial prompt.** "`struct C : A, B` with virtual functions in both bases. Where are the vptrs, and what happens when
you call a `B` virtual through a `C*`?"

**L5 textbook answer.** "C has one vtable with all the functions."

**Why L5 breaks.** C has *two* vptrs: one at offset 0 (shared by A and C) and one in the B subobject. Calling through a
`B*` that points into a C passes the B subobject's address, so C's override is reached through a **thunk** that adjusts
`this` back by B's offset before jumping to the real function. The vtable group also stores `offset_to_top` and RTTI
pointers (Folder 01, file 01, which dumps the layouts and thunks).

**L7 principal defense.** "One vptr per polymorphic base subobject, a vtable group with secondary vtables, `this`-adjusting
thunks (`_ZThn…`) for non-primary bases. That's why a pointer conversion between bases may change the pointer value,
and why `reinterpret_cast` between them is wrong."
</details>

<details><summary><b>Q 2 ⚡ "What does virtual inheritance cost?"</b></summary>

**Initial prompt.** "Why is accessing a virtual base's member slower than a normal base's?"

**L5 textbook answer.** "Virtual inheritance is just like normal inheritance with one copy of the base."

**Why L5 breaks.** The virtual base's position isn't fixed: it depends on the most-derived type. Reaching it means
reading a *virtual base offset* from the vtable at run time, even for an upcast. Only when the static type is `final`
can the compiler use a constant offset (Folder 01, file 01). Constructors also need construction vtables and a VTT.

**L7 principal defense.** "Virtual inheritance trades a run-time offset load per access, and complex construction, for
a shared base. I use it only for genuine diamonds of interfaces, mark leaf classes `final`, and prefer composition."
</details>

<details><summary><b>Q 3 🧊 "How expensive is dynamic_cast?"</b></summary>

**Initial prompt.** "Is `dynamic_cast` acceptable on a hot path?"

**L5 textbook answer.** "It's always slow because it walks the class hierarchy."

**Why L5 breaks.** It depends on the target and compiler. A `dynamic_cast` to a `final` class can be a single vptr
comparison: Clang emits exactly that (4–5 ns), while GCC/MinGW called `__dynamic_cast` (17–20 ns) (Folder 01, Listing
1.7). Casts to non-final classes or across hierarchies do walk type info. libstdc++ may also compare `type_info` names
with `strcmp`.

**L7 principal defense.** "Mark leaf types `final`, cast to final targets, and measure on each compiler. In hot paths,
better designs: a virtual function, a `variant`, or a type tag."
</details>

<details><summary><b>Q 4 ⚡ "What is a pointer-to-member-function, physically?"</b></summary>

**Initial prompt.** "`sizeof(void (C::*)())` is 16 on Linux. Why not 8?"

**L5 textbook answer.** "It stores a function pointer plus some padding."

**Why L5 breaks.** The Itanium PMF is `{ptr, adj}`: `ptr` is either a function address or (for virtual functions) a
vtable offset + 1, and `adj` is the `this` adjustment for the base the function belongs to. The ARM variant moves the
virtual flag into `adj`'s low bit. MSVC uses 8, 16 or 24 bytes depending on the inheritance model (Folder 01, file 01).

**L7 principal defense.** "PMFs are fat because they must work for virtual functions and non-primary bases. Converting
them to `void*` is meaningless, and their size is ABI-specific. Use `std::function`, `std::function_ref`, or a lambda
instead of storing raw PMFs."
</details>

<details><summary><b>Q 5 🔥 "Is return-value optimization guaranteed?"</b></summary>

**Initial prompt.** "`T make() { T t; ...; return t; }` and `T make2() { return T(); }`: which copies are guaranteed to
disappear?"

**L5 textbook answer.** "The compiler always removes both copies (RVO)."

**Why L5 breaks.** Only the prvalue case is guaranteed (C++17: `return T();` initializes the caller's object directly,
even for non-movable types). Returning a named local (NRVO) is permitted, not required; when it doesn't happen, the
value is moved, not copied (implicit move, broadened by P1825/P2266). Folder 01, file 02 shows a case where GCC copied
`return t;` for a `T&&` parameter in C++17 mode while Clang moved.

**L7 principal defense.** "Return prvalues where possible, return named locals by name (never `std::move(local)`, which
disables NRVO), keep a single named return object per function, and know that the ABI passes the return slot in
RDI/X8 (sret)."
</details>

<details><summary><b>Q 6 ⚡ "Why mark move constructors noexcept?"</b></summary>

**Initial prompt.** "Our type has a move constructor. Why does `vector` still copy it when growing?"

**L5 textbook answer.** "`noexcept` is just documentation."

**Why L5 breaks.** `vector` growth uses `move_if_noexcept` to keep the strong exception guarantee: if the move might
throw, it copies (file 02 here, Listing 11.16: 1,023 moves vs copies, depending only on `noexcept`; Folder 01, file 02).

**L7 principal defense.** "`noexcept` (or `= default` with noexcept members) on move operations, enforced with
`static_assert(std::is_nothrow_move_constructible_v<T>)`. It's a performance property of every container that relocates."
</details>

<details><summary><b>Q 7 🧊 "What are value categories, really?"</b></summary>

**Initial prompt.** "Explain lvalue, prvalue and xvalue with an example where the distinction changes behaviour."

**L5 textbook answer.** "Lvalues have names, rvalues don't."

**Why L5 breaks.** A named rvalue reference is an lvalue (`T&& x` is an lvalue inside the function). `std::move(x)` is
an xvalue, an expiring object with identity. A prvalue has no identity until it's materialized, which is what makes
guaranteed elision possible. Overload resolution, `decltype`, and lifetime extension all depend on the category
(Folder 01, file 02; Folder 06, file 01 for `decltype` rules).

**L7 principal defense.** "Identity (glvalue) vs movability (rvalue): lvalue = identity, xvalue = both, prvalue =
movable without identity. Then `decltype((x))` vs `decltype(x)`, and why `std::forward` exists."
</details>

<details><summary><b>Q 8 ⚡ "What does [[no_unique_address]] do to the ABI?"</b></summary>

**Initial prompt.** "We use `[[no_unique_address]]` for an empty allocator member. Portable?"

**L5 textbook answer.** "Yes, it's standard C++20."

**Why L5 breaks.** The attribute is standard, but MSVC ignores it (it uses `[[msvc::no_unique_address]]`), so the same
type has different sizes on GCC/Clang and MSVC, and tail-padding reuse differs too (Folder 01, file 04). That's an ABI
difference for any header shared across those compilers.

**L7 principal defense.** "EBO by inheritance (or a compressed pair) when the layout must be identical everywhere, the
attribute plus the MSVC spelling otherwise, and `static_assert(sizeof(T) == N)` in shared headers."
</details>

<details><summary><b>Q 9 🔥 "Type punning: reinterpret_cast, union, memcpy, bit_cast?"</b></summary>

**Initial prompt.** "Parse a `float` from 4 bytes of a network buffer. Which way is legal?"

**L5 textbook answer.** "`*reinterpret_cast<float*>(buf)`."

**Why L5 breaks.** That violates strict aliasing (and possibly alignment): there is no `float` object there. The
optimizer is allowed to assume the access doesn't alias other types (Folder 01, file 03 shows code reordered on that
basis). Reading the inactive member of a union is also UB in C++.

**L7 principal defense.** "`std::memcpy` into a `float` (compiled to one load), or `std::bit_cast<float>(bytes)` for
same-size values, or C++23 `std::start_lifetime_as` for implicit-lifetime types in place. Plus `-fno-strict-aliasing`
only as a last resort for legacy code."
</details>

<details><summary><b>Q 10 🧊 "When do you need std::launder?"</b></summary>

**Initial prompt.** "After placement-new over an existing object, why might the old pointer not be usable?"

**L5 textbook answer.** "You never need it."

**Why L5 breaks.** If the new object differs in ways the compiler may have cached (a `const` member, a reference member,
or a different dynamic type, so a different vptr), the old pointer doesn't "point to" the new object for optimization
purposes. With `-fstrict-vtable-pointers` Clang assumes the vptr doesn't change, and a stale pointer calls the old
function (Folder 01, file 03).

**L7 principal defense.** "Use the pointer returned by placement new, or `std::launder` it when you must derive it
from old storage (containers of `aligned_storage`, `optional`-like types). And prefer `std::construct_at`."
</details>

<details><summary><b>Q 11 ⚡ "How big is std::string's small buffer?"</b></summary>

**Initial prompt.** "Does `std::string s = "hello, world!!!!";` (16 chars) allocate?"

**L5 textbook answer.** "No, strings have a small-string optimization."

**Why L5 breaks.** It depends on the library. libstdc++ stores up to 15 characters inline (32-byte string), libc++ up
to 22 (24-byte string) (Folder 03 Listing 3.2). This 16-character string allocates with libstdc++ and not with libc++.

**L7 principal defense.** "SSO capacity is an implementation detail: 15 vs 22 here, different again on MSVC. For hot
paths with short strings: `string_view`, fixed-capacity strings, or `inplace_vector<char, N>`, measured per library."
</details>

<details><summary><b>Q 12 🔥 "Which vector operations invalidate iterators?"</b></summary>

**Initial prompt.** "You hold an iterator into a `vector` and call `push_back`. Valid?"

**L5 textbook answer.** "Yes unless the vector is cleared."

**Why L5 breaks.** Any reallocation invalidates *all* iterators, pointers and references. `push_back` reallocates when
`size() == capacity()`, and `insert`/`erase` invalidate from the point of change onward. `deque` keeps references valid
on push at the ends but invalidates iterators (Folder 03 Listing 3.11 checks each case with debug-mode containers).

**L7 principal defense.** "`reserve()` to bound reallocation, indices instead of iterators across mutations, and
`_GLIBCXX_DEBUG`/libc++ hardening in CI to catch invalidated uses."
</details>

<details><summary><b>Q 13 ⚡ "map, unordered_map, or flat_map?"</b></summary>

**Initial prompt.** "Choose a container for 1M integer keys with frequent lookups and rare inserts."

**L5 textbook answer.** "`unordered_map`, because hashing is O(1)."

**Why L5 breaks.** Big-O hides memory. `std::map` is a node-based red-black tree (one cache miss per level); `unordered_map`
is node-based too (a bucket array plus a node per element); a flat (open-addressing) map probes a contiguous array.
Folder 03 measured node sizes and lookups, and Folder 11's flat map did lookups in 25–34 ns vs 50–79 ns for
`unordered_map`. For sorted iteration with rare inserts, `std::flat_map` (C++23, sorted vectors) beats `std::map`.

**L7 principal defense.** "Flat hash map (Abseil/Boost) for lookups, `flat_map` for sorted read-mostly data, `map` when
references must stay stable or ordered inserts dominate. Decide with a benchmark on realistic keys."
</details>

<details><summary><b>Q 14 🔥 "Can someone DoS our unordered_map?"</b></summary>

**Initial prompt.** "Our service keys an `unordered_map<uint64_t, Session>` by client-supplied IDs. Risk?"

**L5 textbook answer.** "No, hash maps are O(1)."

**Why L5 breaks.** `std::hash<uint64_t>` is the identity in both libraries, and the bucket index is `hash % buckets`.
An attacker who sends multiples of the bucket count puts every key in one bucket: Folder 03 measured a lookup going from
3 ns to 38 µs. Both libraries grow their bucket counts through fixed, published prime sequences, so the counts are
predictable.

**L7 principal defense.** "A keyed hash (SipHash-style, or a seeded mixer) for untrusted keys, a flat map with good
mixing, and limits on per-client entries. Treat hash flooding as an input-validation problem."
</details>

<details><summary><b>Q 15 🧊 "What is a deque, physically?"</b></summary>

**Initial prompt.** "Why does `std::deque` behave so differently across libraries?"

**L5 textbook answer.** "It's a double-ended vector."

**Why L5 breaks.** It's a map (array) of pointers to fixed-size blocks. libstdc++ uses 512-byte blocks, libc++ 4,096-byte
blocks with a minimum of 16 elements (Folder 03 Listing 3.3). A `deque<BigStruct>` in libstdc++ can be one element per
block, a pointer chase per element. libstdc++'s deque isn't nothrow-movable either (Folder 01).

**L7 principal defense.** "Use `deque` for stable references at both ends; otherwise a `vector` or a ring buffer. Know
the block size of your library before using it for large elements."
</details>

<details><summary><b>Q 16 🔥 "My comparator uses <=. What can happen?"</b></summary>

**Initial prompt.** "`std::sort(v.begin(), v.end(), [](auto a, auto b) { return a <= b; })`. Bug?"

**L5 textbook answer.** "It just sorts equal elements in a different order."

**Why L5 breaks.** `<=` isn't a strict weak ordering (it isn't irreflexive). `std::sort` may then read out of bounds:
unguarded partition loops rely on the comparator to stop. Folder 04 Listing 4.2: both libraries' debug modes report it
("irreflexive" in libstdc++, "not a valid strict-weak ordering" in libc++). NaN in floating-point keys breaks ordering the
same way.

**L7 principal defense.** "Comparators must be strict weak orderings: `<`, never `<=`; `std::ranges::less`; handle
NaN explicitly (or `std::strong_order` for doubles). Test sorts with debug-mode libraries in CI."
</details>

<details><summary><b>Q 17 ⚡ "Are ranges pipelines zero-cost?"</b></summary>

**Initial prompt.** "Is `v | views::filter(p) | views::transform(f)` as fast as a hand-written loop?"

**L5 textbook answer.** "Yes, views are lazy and inline away."

**Why L5 breaks.** They inline, but the generated loop isn't the hand-written one: `filter` becomes a nested search
loop per element, which defeats the branchless (cmov) code a hand loop gets. Folder 04 Listing 4.5 measured the pipeline
**6× slower** on random data (178–203 ms vs 30–36 ms), and roughly equal on predictable data. Views also dangle easily:
a view of a temporary outlives it (Listing 4.4).

**L7 principal defense.** "Ranges for clarity in non-hot code; for hot loops, measure with realistic, unpredictable data
and read the asm. Never store views of temporaries."
</details>

<details><summary><b>Q 18 🧊 "What does std::function cost?"</b></summary>

**Initial prompt.** "We store callbacks as `std::function<void()>`. Costs?"

**L5 textbook answer.** "A virtual call, nothing more."

**Why L5 breaks.** An indirect call through a type-erased table, plus **allocation** when the callable doesn't fit the
inline buffer: libstdc++ inlines at most 16 bytes of trivially copyable state (32-byte object), libc++ at most 24 bytes
of nothrow-copyable state (48-byte object) (Folder 04 Listing 4.6; this folder's Listing 11.18 builds one). Copying a
`std::function` copies the callable.

**L7 principal defense.** "`std::function_ref` (C++26, non-owning, 16 bytes) for parameters, `move_only_function` for
move-only captures, templates for hot paths, and small captures (a pointer to state) for stored callbacks."
</details>

<details><summary><b>Q 19 ⚡ "Is unique_ptr zero-overhead?"</b></summary>

**Initial prompt.** "Does `std::unique_ptr<T>` cost anything over a raw pointer?"

**L5 textbook answer.** "No, it's zero-overhead."

**Why L5 breaks.** With the default deleter, the happy path compiles to the same instructions as raw `new`/`delete`,
plus a landing pad for exception cleanup (Folder 05 Listing 5.1). With a function-pointer deleter it doubles in size and
calls the deleter indirectly. And it can't be passed in registers under the Itanium ABI (non-trivial destructor), unless
libc++'s ABI v2 `trivial_abi` is enabled.

**L7 principal defense.** "Default or stateless deleters (empty-base optimized), pass by value only when transferring
ownership, raw pointers or references for non-owning access."
</details>

<details><summary><b>Q 20 🔥 "make_shared or shared_ptr(new T)?"</b></summary>

**Initial prompt.** "Why prefer `make_shared`, and when should you not use it?"

**L5 textbook answer.** "Always use `make_shared`; it's faster."

**Why L5 breaks.** It's one allocation instead of two (Listing 11.17 here; Folder 05 Listing 5.3), but the object's
memory is part of the control block, so it isn't freed until the last `weak_ptr` dies (Folder 05 Listing 5.4's zombie
memory). For a large object observed by long-lived weak pointers, that's a leak in practice.

**L7 principal defense.** "`make_shared` by default; `shared_ptr(new T)` or `allocate_shared` with a custom allocator
for large objects with long-lived weak observers. And remember a copy costs two atomic RMWs: about 10 ns, 41–62 ns
contended (Folder 05)."
</details>

<details><summary><b>Q 21 🧊 "What's wrong with shared_from_this in a constructor?"</b></summary>

**Initial prompt.** "A class registers a callback with `shared_from_this()` in its constructor. It throws
`bad_weak_ptr`. Why?"

**L5 textbook answer.** "You forgot to inherit from `enable_shared_from_this`."

**Why L5 breaks.** `enable_shared_from_this` holds a `weak_ptr` that the *owning `shared_ptr`* initializes after
construction. Inside the constructor no owner exists yet, so `shared_from_this()` throws (C++17) and `weak_from_this()`
is empty. Capturing a strong `shared_ptr` to self in a stored callback also creates a cycle (Folder 05 Listing 5.6).

**L7 principal defense.** "Two-phase creation: a static factory that constructs, then registers. Callbacks capture
`weak_from_this()` and `lock()` when they run."
</details>

<details><summary><b>Q 22 ⚡ "Destroying a long linked list crashes"</b></summary>

**Initial prompt.** "A singly-linked list of 1M `unique_ptr<Node>` crashes on destruction. Why?"

**L5 textbook answer.** "A double free somewhere."

**Why L5 breaks.** Each node's destructor destroys the next node's `unique_ptr`, which runs the next destructor: one
stack frame per node. 1M frames overflow the stack, crashing with `0xC00000FD` on both compilers (Folder 05 Listing 5.8).

**L7 principal defense.** "An iterative destructor (detach the chain in a loop), or an arena where nodes are freed in
bulk: 6–10 ms vs 59–68 ms for individual frees in Folder 05's measurement."
</details>

<details><summary><b>Q 23 🔥 "decltype(auto) and forwarding references"</b></summary>

**Initial prompt.** "`template <class T> decltype(auto) get(T&& c) { return c[0]; }`. What does it return for a
`std::vector<int>&` and for a temporary vector?"

**L5 textbook answer.** "An `int` in both cases."

**Why L5 corrupts memory on ARM64.** `decltype(auto)` on `c[0]` deduces `int&` (an lvalue expression). For a temporary
vector, `get` returns a reference into a vector destroyed at the end of the full-expression: a dangling reference on any
architecture. Wrapping the return in parentheses (`return (x);`) also changes the type to a reference (Folder 06 Listing
6.1).

**L7 principal defense.** "`T&&` in a template is a forwarding reference; `decltype(auto)` preserves value category
exactly, which is right only for perfect-forwarding wrappers. Otherwise return by value, and constrain away rvalue
containers when returning references."
</details>

<details><summary><b>Q 24 ⚡ "SFINAE or concepts?"</b></summary>

**Initial prompt.** "Two overloads constrained by `enable_if` are ambiguous for random-access iterators. How do concepts
fix it?"

**L5 textbook answer.** "Concepts are just nicer syntax for `enable_if`."

**Why L5 breaks.** Concepts add **subsumption**: when one constraint implies another (a `random_access_iterator`
subsumes a `forward_iterator`), the more constrained overload wins, while `enable_if` conditions are opaque booleans,
so both candidates stay viable and the call is ambiguous (Folder 06 Listing 6.3). Concepts also produce far shorter
diagnostics.

**L7 principal defense.** "Concepts for overload sets that refine each other, built from named concepts (subsumption
works on concept names, not on arbitrary expressions); `requires` clauses for one-off constraints."
</details>

<details><summary><b>Q 25 🧊 "Virtual functions, CRTP, or variant?"</b></summary>

**Initial prompt.** "A hot loop calls `area()` on a million shapes. Virtual functions, CRTP, `std::variant`, or
something else?"

**L5 textbook answer.** "CRTP: virtual calls are slow."

**Why L5 breaks.** CRTP removes the indirect call but needs a homogeneous type at compile time, which a mixed collection
doesn't have. Folder 06 Listing 6.5: virtual calls 8.3–10.2 ns in random type order, 4.6–5.7 ns sorted by type,
`variant` 5.8–7.9 ns, and separate per-type arrays (structure of arrays) 1.0–1.25 ns. The branch predictor and data
layout dominate, not the indirection.

**L7 principal defense.** "Group by type (or store per-type arrays) for hot loops; `variant` for closed sets; virtual
functions for open hierarchies off the hot path; CRTP or deducing `this` for static mixins."
</details>

<details><summary><b>Q 26 🔥 "Explain the static initialization order fiasco and its cure"</b></summary>

**Initial prompt.** "A global in one file reads a global from another during start-up and sees zero. Fix?"

**L5 textbook answer.** "Use a singleton."

**Why L5 breaks.** Dynamic initialization order across translation units is unspecified: the global sits zeroed in
the object file until its initializer function runs (Folder 06 Listing 6.6 shows `.long 0` plus `_GLOBAL__sub_I`). A
function-local static fixes the order but adds a guard check on every call (an acquire load, `ldarb` on ARM64) and
destruction-order problems at exit.

**L7 principal defense.** "`constinit` for every global that can be constant-initialized (pure data, checked by the
compiler); function-local statics, with the reference hoisted out of hot loops, for the rest; deliberately leaked
singletons for objects used during shutdown."
</details>

<details><summary><b>Q 27 ⚡ "How does std::format reject bad format strings at compile time?"</b></summary>

**Initial prompt.** "`std::format("{:d}", "text")` fails to compile. How does a library check a string literal at
compile time?"

**L5 textbook answer.** "Compiler magic."

**Why L5 breaks.** The parameter type `basic_format_string<Args...>` has a `consteval` constructor that parses the
literal during compilation; a parse error calls a non-constexpr function, so the call is not a constant expression and
compilation fails at the call site (Folder 06 Listing 6.7, which builds the same technique for a logging API).

**L7 principal defense.** "A `consteval` converting constructor plus `type_identity_t` to keep it out of deduction.
I'd use it for any literal-only input: log formats, SQL templates, unit-checked constants."
</details>

<details><summary><b>Q 28 🧊 "Can we add a member to a struct in a shared library header?"</b></summary>

**Initial prompt.** "We ship `libfoo.so` with `struct Config` in its public header. Adding a field: safe?"

**L5 textbook answer.** "Yes, as long as old code doesn't use the new field."

**Why L5 breaks.** Old binaries compiled with the old header allocate the old size, copy the old size, and use the old
offsets. The library writes the new field past the end of their objects: memory corruption. Inline functions and
templates in the header bake layouts into every client, and adding a virtual function shifts vtable slots.

**L7 principal defense.** "ABI-stable boundaries: opaque pointers (pimpl), versioned structs with a size field, or C
APIs. Check with layout dumps (`-fdump-record-layouts`, as Folder 01 does) and ABI checkers (libabigail) in CI."
</details>

<details><summary><b>Q 29 🔥 "Return a string_view from a function"</b></summary>

**Initial prompt.** "`std::string_view name() { std::string s = build(); return s; }`. Problem?"

**L5 textbook answer.** "It's fine; string_view is a lightweight copy."

**Why L5 corrupts memory on ARM64.** A `string_view` is a pointer and a length into memory it doesn't own. Here it
points into `s`, destroyed at the return: every use reads freed memory, on any architecture. Clang warns
(`-Wdangling-gsl`); GCC 16 did not warn on the equivalent case in Folder 02's listing.

**L7 principal defense.** "`string_view` only for parameters and for views into storage that provably outlives them.
Return `std::string` from functions that build strings. Clang's lifetime warnings and ASan in CI."
</details>

<details><summary><b>Q 30 ⚡ "Exceptions or std::expected?"</b></summary>

**Initial prompt.** "Our parser throws on malformed input, about 1% of messages. Keep exceptions or switch to
`std::expected`?"

**L5 textbook answer.** "Exceptions are zero-cost, so keep them."

**Why L5 breaks.** Zero-cost only when nothing throws. A thrown exception cost 1.9–3.1 µs here (allocation, unwinding,
handler search; Folder 02 Listing 2.15). At 1% of a million messages per second that's 10,000 throws per second,
20–30 ms of CPU per second spent unwinding, and the cost spikes under bad input, exactly when attackers send it.

**L7 principal defense.** "`std::expected` (C++23) for failures that are part of normal operation (parsing, validation,
lookups); exceptions for truly exceptional, unrecoverable-locally conditions. Mark non-throwing paths `noexcept` so
containers and the optimizer can rely on it."
</details>

---

## 6. Invariants checklist

- [ ] Every claim about cost names the library and compiler it was measured on.
- [ ] Every layout or ABI claim can be shown with a dump or the generated code.
- [ ] Every UB answer explains what the optimizer does with it, not just that it's UB.
- [ ] Every container answer accounts for memory layout and invalidation rules.

## 7. References

- This KB, Folders [01](../01-ABI-Object-Model-Lifetimes-and-Value-Categories/) to [06](../06-Templates-Concepts-Compile-Time-Programming-and-Zero-Cost-Polymorphism/)
- Itanium C++ ABI: <https://itanium-cxx-abi.github.io/cxx-abi/abi.html>
- S. Meyers, *Effective Modern C++*, O'Reilly 2014
- N. Josuttis, *C++17 — The Complete Guide* and *C++20 — The Complete Guide*
- libabigail (ABI compatibility checking): <https://sourceware.org/libabigail/>
