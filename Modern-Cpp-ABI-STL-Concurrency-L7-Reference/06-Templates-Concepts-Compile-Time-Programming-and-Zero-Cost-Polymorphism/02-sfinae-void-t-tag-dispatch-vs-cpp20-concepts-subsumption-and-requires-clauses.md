# 02 · SFINAE, `void_t`, tag dispatch vs C++20 concepts, subsumption and `requires`

> **Scope.** Before C++20, constraining a template meant making substitution fail on purpose (SFINAE), detecting members
> with `void_t`, or dispatching on tag types. C++20 concepts replace all three with named, checkable predicates that
> participate in overload resolution through *subsumption*. This file writes the same overload set each way, shows that
> subsumption picks the more constrained overload, and shows the rule that surprises everyone: textually identical
> constraints are not the same constraint.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 6.3 | `constraints.cpp` | `enable_if`, `void_t` detection and concepts side by side; `Random` subsumes `Forward`; two `sizeof(T) > 4` clauses are **different** atomic constraints → ambiguity | run + expected diagnostics on both |

Folder 02, file 03 (Listing 2.10) measured the diagnostic side: with Clang, a constrained template's error dropped from
150 lines to 16, and with GCC it moved from `stl_algo.h` to the call site.

**Verification line.** As in Folders 01–05.

---

## 1. First principles

### 1.1 Three generations of the same idea (Listing 6.3)

```cpp
// constraints.cpp - one overload set written three ways (enable_if, void_t detection, concepts) + subsumption
#include <concepts>
#include <iterator>
#include <list>
#include <print>
#include <string>
#include <type_traits>
#include <vector>

// ---- C++11: enable_if in the return type ----
template <class T>
std::enable_if_t<std::is_integral_v<T>, std::string> kind11(T) { return "integral"; }
template <class T>
std::enable_if_t<std::is_floating_point_v<T>, std::string> kind11(T) { return "floating"; }

// ---- C++17: detection idiom with void_t ----
template <class, class = void>
struct has_size : std::false_type {};
template <class T>
struct has_size<T, std::void_t<decltype(std::declval<const T&>().size())>> : std::true_type {};
static_assert(has_size<std::vector<int>>::value && !has_size<int>::value);

// ---- C++20: concepts, requires-expressions, and subsumption ----
template <class I>
concept Forward = std::forward_iterator<I>;
template <class I>
concept Random = Forward<I> && std::random_access_iterator<I>;  // Random SUBSUMES Forward

template <Forward I>
std::string advance_kind(I) { return "forward: O(n) advance"; }
template <Random I>                    // more constrained: wins for random-access iterators, no ambiguity
std::string advance_kind(I) { return "random access: O(1) advance"; }

template <class T>
concept Sized = requires(const T& t) {
    { t.size() } -> std::convertible_to<std::size_t>;
};

// Subsumption works on NAMED concepts and their atomic constraints, not on textually equal expressions.
template <class T>
    requires(sizeof(T) > 4)
std::string big(T) { return "big"; }
#ifdef SHOW_AMBIGUITY
template <class T>
    requires(sizeof(T) > 4) && std::is_class_v<T>   // NOT seen as "more constrained": each (sizeof(T) > 4) is
std::string big(T) { return "big class"; }         // a different atomic constraint -> ambiguous call
#endif

int main() {
    std::println("kind11(1)={} kind11(1.5)={}", kind11(1), kind11(1.5));
    std::println("Sized<std::string>={} Sized<int>={}", Sized<std::string>, Sized<int>);
    std::vector<int> v;
    std::list<int> l;
    std::println("vector iterator: {}", advance_kind(v.begin()));
    std::println("list iterator:   {}", advance_kind(l.begin()));
    std::println("big(std::string{{}}) = {}", big(std::string{}));
}
```

Output (verified, both compilers):

```text
kind11(1)=integral kind11(1.5)=floating
Sized<std::string>=true Sized<int>=false
vector iterator: random access: O(1) advance
list iterator:   forward: O(n) advance
big(std::string{}) = big
```

| Technique | Mechanism | Cost |
|---|---|---|
| `enable_if_t<cond, R>` (C++11/14) | an invalid type in the signature removes the overload during substitution (SFINAE) | conditions are not named; errors are "no matching function" with a list of failed substitutions; overloads must be mutually exclusive by hand |
| `void_t` detection (C++17) | a partial specialization that is only viable if an expression is well-formed | one trait struct per property; still no ordering between overloads |
| tag dispatch | overload on `std::true_type`/`std::false_type` or iterator category tags | works for ordering (iterator tags form a hierarchy), but needs a helper function per dispatch point |
| concepts (C++20) | named predicates on template parameters, checked before instantiation | overloads ordered by **subsumption**; readable errors at the call site |

### 1.2 Subsumption: how the compiler picks "more constrained"

```text
 constraints are normalized into a conjunction/disjunction of ATOMIC constraints
 an atomic constraint = an expression + the template parameters it uses, identified by WHERE it is written
   (the same concept expanded twice yields the same atomic constraints; the same expression written twice does not)
 P subsumes Q  iff  every way P can be true implies Q is true (checked on the normalized forms)
 overload resolution: if both are viable and one's constraints subsume the other's, the subsuming one wins

 concept Random = Forward<I> && random_access_iterator<I>;   -> Random subsumes Forward  (named concept reused)
 requires (sizeof(T) > 4)  vs  requires (sizeof(T) > 4) && is_class_v<T>
   -> the two "sizeof(T) > 4" are DIFFERENT atomic constraints (different source locations): no subsumption, ambiguous
```

* `advance_kind(v.begin())` chose the `Random` overload for `vector`, and `Forward` for `list`. No `enable_if`
  exclusivity was needed: `Random` is *defined in terms of* `Forward`, so it subsumes it.
* With `-DSHOW_AMBIGUITY`, the second `big` writes `(sizeof(T) > 4) && std::is_class_v<T>`. It looks more constrained,
  but the compiler does not compare expressions textually. The two `sizeof(T) > 4` are distinct atomic constraints, so
  neither overload subsumes the other (GCC, then Clang):

```text
constraints.cpp:56:50: error: call of overloaded 'big(std::string)' is ambiguous
constraints.cpp:56:47: error: call to 'big' is ambiguous
```

The fix is to name the shared part: `template <class T> concept Big = sizeof(T) > 4;` and write `requires Big<T>` and
`requires Big<T> && std::is_class_v<T>`. Subsumption then sees the same atomic constraint in both.

### 1.3 `requires` expressions

```cpp
template <class T>
concept Sized = requires(const T& t) {
    { t.size() } -> std::convertible_to<std::size_t>;   // compound requirement: valid AND result type constrained
};
// also: simple requirements (expr;), type requirements (typename T::value_type;),
//       nested requirements (requires std::is_trivially_copyable_v<T>;)
```

`requires` expressions check *syntax*: that an expression is valid and its type matches. They do not check semantics.
`Sized<T>` is true for any type with a `size()` member convertible to `size_t`, including one whose `size()` means
something else. The standard library's concepts (`std::regular`, `std::sortable`, `std::random_access_iterator`) carry
semantic requirements in their *specification*. Satisfying the syntax and violating the semantics is still UB.

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| SFINAE (as a deduction rule) | C++98, extended to expressions in C++11 (N2634) | "expression SFINAE" |
| `std::enable_if` | C++11 | — |
| `enable_if_t`, `is_same_v`-style `_t`/`_v` aliases | C++14 / C++17 | — |
| `std::void_t` | C++17 (N3911) | the detection idiom |
| `if constexpr` | C++17 (P0292) | replaces many tag-dispatch uses inside one function (Folder 02) |
| concepts, `requires` clauses and expressions, abbreviated templates, standard concepts | C++20 (P0734, P0898, P1141) | subsumption-based ordering |
| constrained algorithms (`std::ranges::`) | C++20 (P0896) | — |
| `std::is_detected` | Library Fundamentals TS v2 only | never standardized; concepts replaced it |
| concept and variable-template template parameters | C++26 (P2841) | ⚠ not tested here |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| two overloads with overlapping conditions | `enable_if<is_integral>` + `enable_if<is_arithmetic>` (ambiguous for `int`) | concepts where one refines the other (`Integral` subsumes `Arithmetic` only if defined in terms of it) |
| a refined overload written ad hoc | `requires (A) && (B)` repeated inline | named concepts: `concept Base = A; concept Refined = Base<T> && B;` |
| detecting a member | a hand-written `void_t` trait | a `requires` expression, inline or as a named concept |
| default template argument SFINAE | two templates differing only in `typename = enable_if_t<...>` (redeclaration error) | put the condition in the type (`enable_if_t<...>* = nullptr`) or use `requires` |
| constraining for documentation only | `template <class T>` + a comment "T must be sortable" | `template <std::sortable I>`: the compiler enforces it |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| "call is ambiguous" between two constrained overloads | constraints not related by subsumption (textually equal ≠ identical) | name the shared constraint as a concept |
| "redefinition of template" with two `enable_if` overloads | default template arguments are not part of the signature | move the condition into the signature, or use concepts |
| a type satisfies a concept but misbehaves | syntactic check, semantic violation | document semantic requirements; test with archetypes |
| a constrained overload is never chosen | a more specialized unconstrained template is a better match | overload resolution ranks conversions before constraints: check the parameter types first |
| huge error output in SFINAE-heavy code | substitution failures listed per candidate | concepts; `static_assert` with a message at the API boundary |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "SFINAE vs concepts?"</b></summary>

**Initial prompt.** "What do concepts give you over `enable_if`?"

**L5 textbook answer.** "Nicer syntax and better error messages."

**Why L5 breaks.** Syntax and errors are the visible parts (Folder 02 measured both). The structural difference is
**ordering**: concepts participate in overload resolution through subsumption, so a refined overload (`Random`) beats
the general one (`Forward`) without manual mutual exclusion (Listing 6.3). With `enable_if` you must make the conditions
disjoint yourself, and adding a third overload means editing the other two.

**L7 principal defense.** "Concepts make constraints named, composable and ordered. I define a small hierarchy of named
concepts (each refinement written in terms of its base), constrain overloads with them, and let subsumption choose. I keep
`enable_if` only in code that must compile as C++17."
</details>

<details><summary><b>Chain 2 🧊 "Why is this call ambiguous?"</b></summary>

**Initial prompt.** "One overload `requires (sizeof(T) > 4)`, another `requires (sizeof(T) > 4) && std::is_class_v<T>`.
Calling with `std::string` is ambiguous. The second is obviously more constrained. Why?"

**L5 textbook answer.** "Compiler bug."

**Why L5 breaks.** It is the rule (Listing 6.3, rejected identically by GCC and Clang). Subsumption compares *atomic
constraints*, which are identified by the expression *and its source location* after normalization. Two textually
identical `sizeof(T) > 4` expressions written in two places are different atoms, so the compiler cannot prove that one
conjunction implies the other. The design avoids expensive and fragile expression-equivalence checking.

**L7 principal defense.** "Shared parts of constraints go into named concepts: `concept Big = sizeof(T) > 4;`, then
`Big<T>` and `Big<T> && std::is_class_v<T>`. Now both refer to the same atomic constraint, and the second subsumes the
first. That is also why the standard library defines refined concepts in terms of their bases."
</details>

<details><summary><b>Chain 3 ⚡ "What does void_t do?"</b></summary>

**Initial prompt.** "Explain `std::void_t` and the detection idiom."

**L5 textbook answer.** "It's an alias that turns any type into void."

**Why L5 breaks.** That is the definition, not the mechanism. The idiom is: a primary template `has_size<T, void> :
false_type`, and a partial specialization `has_size<T, void_t<decltype(declval<const T&>().size())>> : true_type`. If the
expression is ill-formed, substitution into the specialization fails (SFINAE), and the primary is used. If it is
well-formed, `void_t<...>` is `void`, which matches the default argument, so the specialization is chosen. Listing 6.3:
`has_size<vector<int>>` is true and `has_size<int>` false.

**L7 principal defense.** "In C++20 the same check is `requires (const T& t) { t.size(); }`, which is shorter and reusable
as a concept. `void_t` remains useful for C++17 code bases. Its known pitfall (CWG 1558, unused alias arguments
historically not SFINAE-tested) was resolved, so it works on all current compilers."
</details>

<details><summary><b>Chain 4 🔥 "Write an overload set for iterator categories"</b></summary>

**Initial prompt.** "Implement `my_advance(it, n)` with O(1) for random-access iterators and O(n) otherwise."

**L5 textbook answer.** "Tag dispatch on `iterator_traits<It>::iterator_category`."

**Why L5 breaks.** Tag dispatch works (it is how `std::advance` was written for decades), because iterator tags form an
inheritance hierarchy, so the most-derived tag overload wins. In C++20 the same structure is expressed directly with
concepts and subsumption (Listing 6.3's `advance_kind`): no tag objects, no helper functions, and an error at the call site
for non-iterators.

**L7 principal defense.** "Two overloads: `template <std::input_or_output_iterator I>` (loop) and `template
<std::random_access_iterator I>` (`it += n`), because `random_access_iterator` subsumes the weaker concepts. Add a
`bidirectional_iterator` overload for negative `n`. The semantic requirements (iterator stays valid, `n` in range) stay in
the documentation and in debug-mode checks."
</details>

<details><summary><b>Chain 5 🧊 "Concepts check semantics?"</b></summary>

**Initial prompt.** "If my type satisfies `std::totally_ordered`, is it safe to sort?"

**L5 textbook answer.** "Yes, the concept guarantees ordering."

**Why L5 breaks.** The compiler checks only the syntactic part (the comparison operators exist and return something
boolean-testable). The semantic part (a total order: transitive, antisymmetric) is a *requirement on you*. A type whose
`operator<` uses `<=` internally, or compares doubles that can be NaN, satisfies the concept and still breaks `std::sort`
(Folder 04, file 01).

**L7 principal defense.** "Concepts are contracts with a compile-time syntactic part and a documented semantic part. For
types I own, I make semantics easy to get right (defaulted `<=>`, a total order on floating point), and I test with
sanitizers plus the libraries' checked modes, which catch ordering violations at run time."
</details>

<details><summary><b>Chain 6 ⚡ "Two enable_if overloads don't compile"</b></summary>

**Initial prompt.** "Both `template <class T, class = std::enable_if_t<std::is_integral_v<T>>> void f(T)` and the same
with `is_floating_point_v` give 'redefinition'. Why?"

**L5 textbook answer.** "You can't overload on enable_if."

**Why L5 breaks.** You can, but default template arguments are not part of a function template's signature. Both
declarations are `template <class T, class> void f(T)`, the same template declared twice. The fix is to put the condition
where it changes the signature: the return type (as in Listing 6.3's `kind11`), a function parameter, or a non-type
template parameter (`std::enable_if_t<cond, int> = 0`).

**L7 principal defense.** "In C++20, `requires` clauses: constraints *are* part of the signature for overloading. In
C++17, the return-type or `= 0` non-type parameter form. I'd mention that this redefinition error is one of the reasons
concepts were added."
</details>

<details><summary><b>Chain 7 🔥 "Abbreviated templates: any pitfalls?"</b></summary>

**Initial prompt.** "Is `void log(const auto& x)` the same as a template?"

**L5 textbook answer.** "Yes, just shorter."

**Why L5 breaks.** It is a function template with an invented parameter, so it has template properties that surprise people
who think of it as a function: it must be defined in a header (or exported from a module), every distinct argument type
instantiates a new function (code size), you can't take its address without specifying the type, and two `auto` parameters
are *independent* types (`void f(auto a, auto b)` accepts `int` and `string`). Constraining it is easy: `void
log(const std::formattable<char> auto& x)`.

**L7 principal defense.** "Abbreviated templates are good for short, local generic code. For public APIs I name the
template parameter when two parameters must share a type, constrain each `auto`, and watch instantiation counts in large
code bases (`-ftime-trace`)."
</details>

<details><summary><b>Chain 8 ⚡ "What does a constraint failure look like at the call site?"</b></summary>

**Initial prompt.** "Do concepts improve compile errors?"

**L5 textbook answer.** "Yes, they're always short."

**Why L5 breaks.** Folder 02, Listing 2.10, measured it: Clang went from 150 lines to 16, but GCC went from 36 to 38,
because GCC explains each unsatisfied constraint. The robust improvement is *location*: the error points at the call
site, naming the unsatisfied concept, instead of a line deep inside the library.

**L7 principal defense.** "Location and intent matter more than length. I constrain public templates, name concepts after
domain requirements so errors are readable (`SerializableMessage`, not `requires requires`), and add a `static_assert`
with a message for the one requirement users get wrong most often."
</details>

---

## 6. Invariants checklist

- [ ] Public templates are constrained with standard or named concepts.
- [ ] Refinements are defined in terms of their base concepts, so subsumption works.
- [ ] No repeated inline constraint expressions that need to subsume each other.
- [ ] `enable_if` only in C++17-compatible code, and only in signature positions.
- [ ] Semantic requirements of concepts are documented and tested, not assumed from satisfaction.

## 7. References

- P0734R0 (concepts wording): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0734r0.pdf>
- P0898R3 (standard library concepts): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0898r3.pdf>
- N3911 (`void_t`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2014/n3911.pdf>
- Andrew Sutton, "Concepts in 60" (CppCon 2018).
- cppreference, constraints and concepts: <https://en.cppreference.com/w/cpp/language/constraints>
