# Modern C++ (C++11 → C++26), Itanium ABI, STL Internals & Concurrency: L7 Reference

A 12-folder knowledge base and interview playbook at the Principal/Staff (L6/L7) bar: the object model and ABI,
the standards' evolution, STL internals, templates and compile-time programming, the memory model and hardware
coherency, OS synchronization, lock-free structures and safe memory reclamation, coroutines and
`std::execution`, and interview problem banks. It is written one folder per turn. Each folder's code is compiled,
run and gated before the folder counts as done.

## Status

| # | Folder | Files | Status |
|---|---|---|---|
| 01 | [ABI, object model, lifetimes, value categories](01-ABI-Object-Model-Lifetimes-and-Value-Categories/) | 4 | ✅ done 2026-10-28, gated (31 listings, ~34.5k words) |
| 02 | [Chronological C++ standards evolution, C++11 → C++26](02-Chronological-C++-Standards-Evolution-C++11-to-C++26/) | 4 | ✅ done 2026-10-28, gated (21 listings, ~21.7k words) |
| 03 | [STL containers: internals, memory layouts, trade-offs](03-STL-Containers-Internals-Memory-Layouts-and-Tradeoffs/) | 4 | ✅ done 2026-10-28, gated (13 listings, ~16.7k words) |
| 04 | STL algorithms, ranges, views, functional internals | 3 | ⏳ next |
| 05 | Smart pointers, RAII, memory-management internals | 3 | — |
| 06 | Templates, concepts, compile-time programming, zero-cost polymorphism | 4 | — |
| 07 | C++ memory model, atomics, hardware coherency physics | 4 | — |
| 08 | OS threads, synchronization primitives, futex internals | 4 | — |
| 09 | Lock-free programming, data structures, safe memory reclamation | 4 | — |
| 10 | Async execution: thread pools, coroutines, C++26 senders | 4 | — |
| 11 | Master concurrency + STL interview problem bank | 4 | — |
| 12 | Curated libraries, TSan debugging, study guide | 2 | — |

### Folder 01 contents

| File | Listings | Highlights (all verified) |
|---|---|---|
| [01 Itanium ABI: vtables, thunks](01-ABI-Object-Model-Lifetimes-and-Value-Categories/01-itanium-abi-vtable-vptr-multiple-virtual-inheritance-and-thunks.md) | 1.1–1.8 | vtable group byte maps from Clang's own dumps; VTT + construction vtables; PMF `{17,0}` on x86-64 vs `{16,1}` on AArch64; MSVC PMF sizes 8/16/24; AArch64 PAuth `autda`/`braa`; relative vtables; GCC speculative devirtualization; Clang's one-compare `dynamic_cast` to `final` (4–5 ns vs 17–20 ns); a wrong-base `void*` cast that makes **GCC delete the rest of `main`** |
| [02 Value categories, elision, call ABI](01-ABI-Object-Model-Lifetimes-and-Value-Categories/02-value-categories-lvalue-prvalue-xvalue-rvo-nrvo-and-move-noexcept.md) | 2.1–2.7 | 38 categories as `static_assert`s; 11 return patterns × C++17/20/23 (GCC and Clang disagree in C++17); P2266 break; `unique_ptr` by value = ~20 instructions vs 1 for `trivial_abi`; X8 on AArch64; 1,048,575 copies vs moves; libstdc++ `deque` is not nothrow-movable but is memcpy-relocated |
| [03 Lifetime, launder, aliasing](01-ABI-Object-Model-Lifetimes-and-Value-Categories/03-object-lifetime-placement-new-std-launder-bit-cast-and-strict-aliasing.md) | 3.1–3.8 | TBAA returns a stale `1` on both compilers; `vector<uint8_t>` loop not vectorized, `char8_t` is; `-fstrict-vtable-pointers` calls `Animal::speak` on a `Cat` without `std::launder`; `ldar` vs `ldapr` vs `ldaddal`; P2718 observed; constexpr as a UB detector; feature macros per library |
| [04 EBO, no_unique_address, relocation](01-ABI-Object-Model-Lifetimes-and-Value-Categories/04-empty-base-optimization-no-unique-address-and-trivially-relocatable.md) | 4.1–4.7 | 12 layout rules; MSVC ignores `[[no_unique_address]]` and never reuses tail padding; `memcpy(sizeof(Base))` clobbers a derived field; `unique_ptr<T, FinalDeleter>` = 16 B in both libraries (ABI compat); libstdc++ SSO self-pointer after memcpy; P2786 in → out of C++26; Clang 21 lowers relocation to `memmove` on the PAuth target |

## Conventions

* **Spine of every file:** first-principles memory layout / state machine / assembly proof → evolution table
  (C++11 → C++26) → production blueprints (subtle buggy way vs production-hardened way, as compiled listings)
  → failure-mode table → adversarial bar-raiser chains → invariants checklist → references.
* **Bar-raiser chains** use *Initial prompt → L5 textbook answer → Why L5 breaks → L7 principal defense*. For
  the concurrency folders (07–11) the third step is literally "why L5 deadlocks or corrupts memory on ARM64".
  In Folder 01 it is "why it breaks", and the ARM64 angle (PAuth, X8, PMF encoding, alignment faults, weak
  ordering of vptr stores) appears where it is real. Chains are domain-representative questions, **not**
  claimed to be actual questions from any company.
* **Tags:** 🔥 interview-critical · ⚡ performance · 🧊 deep or rare · ⚠ a claim that was *not* executed here
  (read from a spec, or inferred from codegen); each ⚠ says which.
* **Listings** start with `// name.cpp - description`. Assembly blocks are filtered godbolt-style: labels,
  instructions and data directives, demangled names as comments, and EH landing pads labelled.
* **Outputs** labelled "verified" are deterministic and reproduced by the gate. "One run" outputs contain
  timings; the text gives ranges over several runs.
* Files are written directly into this repository, so there are no `### FILE:` chat headers to extract.

## Toolchains and verification method

| Purpose | Tool |
|---|---|
| Codegen, x86-64 + AArch64 (Itanium ABI) | Clang 21.1.0 (Zig 0.16 bundle), `-O3 -fomit-frame-pointer`, `x86_64-linux-gnu` / `aarch64-linux-gnu` (Armv8.0 baseline; `-mcpu=neoverse_n1` where LSE/RCpc matter) |
| Codegen cross-check | GCC 16.2.0 MinGW-w64, `-O3 -mabi=sysv` (SysV registers, Itanium C++ ABI; PE/COFF sections, 32-bit `long`) |
| Hardened ABIs | Clang `aarch64-unknown-linux-pauthtest`; `-fexperimental-relative-c++-abi-vtables`; `x86_64-pc-windows-msvc` (compile-only `static_assert`s) |
| Layout dumps | Clang `-fdump-record-layouts`, `-fdump-vtable-layouts` |
| Runs | Windows 11 x86-64: GCC 16.2 + libstdc++ 16 (static), Clang 21.1 + libc++ 21.1; `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion` |

**Gate (Folder 01, 2026-10-28):** every `cpp` block whose first line is `// name.cpp - ` was extracted from the
markdown: **31 listings, all byte-identical** to the sources that produced the outputs. The full build
script (114 compile/run/disassemble/expected-failure steps, one process at a time) was rerun **from the
extracted copies**. Result: 97 outputs identical, 6 differ only in measured timings, 0 structural differences.
Each file has all 7 sections and 8–9 chains with all four parts.

**Not possible on this machine** (each instance is marked ⚠ in the text): running AArch64 code (no hardware or
emulator; AArch64 facts come from Clang codegen plus the Arm ARM), a Linux-hosted GCC (the GCC cross-check is
the MinGW build), LTO-dependent devirtualization (`-fwhole-program-vtables`), sanitizer runtimes, and MSVC
`cl.exe` itself (MSVC-ABI facts come from Clang targeting `x86_64-pc-windows-msvc`).

## Where this KB refines the brief

1. **Trivial relocatability is not in C++26.** P2786R13 was adopted in February 2025 and removed in November
   2025 (P3920R0). The brief's C++26 list does not include it, and the KB treats it as history plus a C++29
   design question (Folder 01, file 04).
2. **`-O3` vs "free" acquire/release.** Folder 01 does not depend on memory orders. Folder 07 will show that
   acquire/release are plain `MOV`s on x86 *for loads and stores*, while RMWs are always `LOCK`ed.
   Similarly, Armv8.0 uses `LDAR`/`STLR` but RCpc cores use `LDAPR` for acquire loads (already visible in
   Listing 3.4).
3. **Several "well-known" facts were wrong when checked**, and the text says so where it matters: a `final`-less
   most-derived class still needs a run-time vbase lookup; two same-type `[[no_unique_address]]` empties do not
   enlarge a struct here; EBO-blocked layouts move the *member*, not the base; GCC 16's `-Wdangling-reference`
   is enabled by `-Wextra`, not `-Wall`; `unique_ptr` with a `final` deleter is 16 bytes in both standard
   libraries.
