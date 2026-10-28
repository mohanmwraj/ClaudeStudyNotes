# 02 · The six memory orders: relaxed, acquire/release, seq_cst, litmus tests, and x86-64 vs ARM64 assembly

> **Scope.** A memory order tells the compiler which instructions to emit and which reorderings it may still perform
> itself. Hardware decides which of the remaining reorderings actually happen. This file maps every order to x86-64
> and AArch64 instructions (three AArch64 generations). It then runs the four classic litmus tests (SB, MP, LB,
> IRIW) on this x86-64 machine and measures what `seq_cst` costs. The result sets the testing strategy: **x86-64
> hardware can only ever expose store-buffering bugs.** Every message-passing, load-buffering or multi-copy bug
> stays invisible until the code runs on ARM.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 7.4 | `orders_asm.cpp` | loads are always `MOV` on x86-64; `seq_cst` stores are `XCHG`; every RMW is `LOCK`ed; AArch64 uses `LDAR`/`STLR` (v8.0), `LDAPR` (RCpc), `LDAPUR`/`STLUR` (v8.4), LL/SC loops or LSE single instructions | asm: Clang x86-64, GCC x86-64, Clang AArch64 v8.0 / Neoverse N1 / Neoverse V1 |
| 7.5 | `litmus.cpp` | SB is observed with relaxed **and with release/acquire**; never with `seq_cst` or `seq_cst` fences; MP, LB and IRIW are never observed on x86 | run, 2 or 4 threads, 100,000 instances each, both compilers |
| 7.6 | `sc_cost.cpp` | a `seq_cst` store costs 20–40× a release store on x86-64; loads cost the same for every order | run, 1 thread, both compilers |

**Verification line.** As in file 01 (GCC 16.2 / Clang 21.1, Intel Core i5-11260H). AArch64 code is compiled, not run
(⚠). AArch64 *outcomes* come from the architecture's published axiomatic model (Arm ARM, chapter B2; the `herd7`
`aarch64.cat` model) and are marked as such.

---

## 1. First principles

### 1.1 Why hardware reorders: store buffers, out-of-order loads, and coherence

```text
           core 0                                   core 1
  +-------------------------+              +-------------------------+
  | out-of-order pipeline   |              | out-of-order pipeline   |
  |   loads execute early   |              |   loads execute early   |
  |   (speculatively)       |              |   (speculatively)       |
  +-----------+-------------+              +-------------+-----------+
              | stores retire into                       |
              v                                          v
  +-------------------------+              +-------------------------+
  | STORE BUFFER (FIFO)     |              | STORE BUFFER (FIFO)     |
  |  x = 1   (not yet       |              |  y = 1                  |
  |  visible to core 1)     |              |                         |
  +-----------+-------------+              +-------------+-----------+
              | drains in order (x86) /                  |
              | in any order (ARM)                       |
              v                                          v
  +-------------------------+   coherence  +-------------------------+
  | L1D  (MESI/MOESI line   |<============>| L1D                     |
  |       states)           |  protocol    |                         |
  +-------------------------+              +-------------------------+
```

* **x86-64 is TSO** (total store order; Sewell et al., *x86-TSO*). Stores leave the store buffer in program order, and
  loads are never visibly reordered with other loads. The only visible reordering is **a later load completing before
  an earlier store to a different address has left the store buffer**: store→load reordering, the SB outcome. A core
  reads its own buffered stores (store forwarding). A `LOCK`-prefixed instruction or `XCHG` with memory drains the
  buffer first, and so does `MFENCE`. That is why every RMW on x86 is a full barrier.
* **AArch64 is weakly ordered but *other-multi-copy-atomic*** (since the 2017 revision of the ARMv8 model). Any pair
  of accesses to different addresses (load→load, load→store, store→store, store→load) may be reordered unless
  something orders them: a barrier (`DMB`), an acquire load (`LDAR`, `LDAPR`), a release store (`STLR`), or a
  dependency. A store becomes visible to all *other* cores at the same moment, so two other cores cannot disagree about
  the order of two stores.
* **`LDAR`/`STLR` are RCsc**: an `STLR` followed by an `LDAR` stays in order, which is why AArch64 can implement
  `seq_cst` without a fence. **`LDAPR` is RCpc** (ARMv8.3 `FEAT_LRCPC`). It may complete before an *earlier* `STLR` to a
  different address, which is fine for `acquire` but not for `seq_cst`.

### 1.2 The orders as instructions (Listing 7.4)

```cpp
// orders_asm.cpp - the six memory orders as instructions: x86-64 (TSO) vs AArch64 v8.0, v8.2 (+RCpc), v8.4 (+RCpc2)
#include <atomic>

using A = std::atomic<int>;
struct Node {
    long long key;
    std::atomic<int> state;   // a field at offset 8: shows the addressing forms (LDAPUR/STLUR take an offset)
};

int load_relaxed(const A& a) { return a.load(std::memory_order_relaxed); }
int load_consume(const A& a) { return a.load(std::memory_order_consume); }   // deprecated in C++26 (P3475)
int load_acquire(const A& a) { return a.load(std::memory_order_acquire); }
int load_seq_cst(const A& a) { return a.load(std::memory_order_seq_cst); }

void store_relaxed(A& a, int v) { a.store(v, std::memory_order_relaxed); }
void store_release(A& a, int v) { a.store(v, std::memory_order_release); }
void store_seq_cst(A& a, int v) { a.store(v, std::memory_order_seq_cst); }

int xchg_acq_rel(A& a, int v) { return a.exchange(v, std::memory_order_acq_rel); }
int add_relaxed(A& a) { return a.fetch_add(1, std::memory_order_relaxed); }
int add_acq_rel(A& a) { return a.fetch_add(1, std::memory_order_acq_rel); }
int add_seq_cst(A& a) { return a.fetch_add(1, std::memory_order_seq_cst); }

int field_acquire(const Node& n) { return n.state.load(std::memory_order_acquire); }
void field_release(Node& n, int v) { n.state.store(v, std::memory_order_release); }
```

x86-64, both compilers (Clang 21 `-O3`, GCC 16 `-O3`):

```text
function       x86-64 Clang 21                          x86-64 GCC 16
-------------  ---------------------------------------  ---------------------------------------
load_relaxed   movl (%rdi), %eax                        movl (%rdi), %eax
load_consume   movl (%rdi), %eax                        movl (%rdi), %eax
load_acquire   movl (%rdi), %eax                        movl (%rdi), %eax
load_seq_cst   movl (%rdi), %eax                        movl (%rdi), %eax
store_relaxed  movl %esi, (%rdi)                        movl %esi, (%rdi)
store_release  movl %esi, (%rdi)                        movl %esi, (%rdi)
store_seq_cst  xchgl %esi, (%rdi)                       xchgl (%rdi), %esi
xchg_acq_rel   xchgl %eax, (%rdi)                       xchgl (%rdi), %eax
add_relaxed    movl $1, %eax ; lock xaddl %eax, (%rdi)  movl $1, %eax ; lock xaddl %eax, (%rdi)
add_acq_rel    movl $1, %eax ; lock xaddl %eax, (%rdi)  movl $1, %eax ; lock xaddl %eax, (%rdi)
add_seq_cst    movl $1, %eax ; lock xaddl %eax, (%rdi)  movl $1, %eax ; lock xaddl %eax, (%rdi)
field_acquire  movl 8(%rdi), %eax                       movl 8(%rdi), %eax
field_release  movl %esi, 8(%rdi)                       movl %esi, 8(%rdi)
```

AArch64 loads and stores: baseline ARMv8.0, Neoverse N1 (ARMv8.2 + LSE + RCpc), and Neoverse V1 (ARMv8.4, `LRCPC2`):

```text
function       AArch64 v8.0                    Neoverse N1, v8.2+RCpc           Neoverse V1, v8.4
-------------  ------------------------------  -------------------------------  -------------------
load_relaxed   ldr w0, [x0]                    ldr w0, [x0]                     ldr w0, [x0]
load_consume   ldar w0, [x0]                   ldapr w0, [x0]                   ldapr w0, [x0]
load_acquire   ldar w0, [x0]                   ldapr w0, [x0]                   ldapr w0, [x0]
load_seq_cst   ldar w0, [x0]                   ldar w0, [x0]                    ldar w0, [x0]
store_relaxed  str w1, [x0]                    str w1, [x0]                     str w1, [x0]
store_release  stlr w1, [x0]                   stlr w1, [x0]                    stlr w1, [x0]
store_seq_cst  stlr w1, [x0]                   stlr w1, [x0]                    stlr w1, [x0]
field_acquire  add x8, x0, #8 ; ldar w0, [x8]  add x8, x0, #8 ; ldapr w0, [x8]  ldapur w0, [x0, #8]
field_release  add x8, x0, #8 ; stlr w1, [x8]  add x8, x0, #8 ; stlr w1, [x8]   stlur w1, [x0, #8]
```

AArch64 read-modify-writes, the same three CPUs:

```text
xchg_acq_rel:
  AArch64 v8.0            mov x8, x0 ; ldaxr w0, [x8] ; stlxr w9, w1, [x8] ; cbnz w9, .LBB7_1
  Neoverse N1, v8.2+RCpc  swpal w1, w0, [x0]
  Neoverse V1, v8.4       swpal w1, w0, [x0]

add_relaxed:
  AArch64 v8.0            ldxr w8, [x0] ; add w9, w8, #1 ; stxr w10, w9, [x0] ; cbnz w10, .LBB8_1 ; mov w0, w8
  Neoverse N1, v8.2+RCpc  mov w8, #1 ; ldadd w8, w0, [x0]
  Neoverse V1, v8.4       mov w8, #1 ; ldadd w8, w0, [x0]

add_acq_rel:
  AArch64 v8.0            ldaxr w8, [x0] ; add w9, w8, #1 ; stlxr w10, w9, [x0] ; cbnz w10, .LBB9_1 ; mov w0, w8
  Neoverse N1, v8.2+RCpc  mov w8, #1 ; ldaddal w8, w0, [x0]
  Neoverse V1, v8.4       mov w8, #1 ; ldaddal w8, w0, [x0]

add_seq_cst:
  AArch64 v8.0            ldaxr w8, [x0] ; add w9, w8, #1 ; stlxr w10, w9, [x0] ; cbnz w10, .LBB10_1 ; mov w0, w8
  Neoverse N1, v8.2+RCpc  mov w8, #1 ; ldaddal w8, w0, [x0]
  Neoverse V1, v8.4       mov w8, #1 ; ldaddal w8, w0, [x0]
```

* **x86-64: every load is a plain `MOV`**, including `seq_cst`, and relaxed and release stores are plain `MOV`. The
  only order-dependent instruction is the **`seq_cst` store, which is `XCHG`**: an implicitly `LOCK`ed exchange
  that drains the store buffer. GCC 16 and Clang 21 agree (older GCC releases emitted `MOV` + `MFENCE`). Every RMW is
  `LOCK XADD`/`XCHG`, the same for `relaxed` and `seq_cst`, because x86 has no weaker RMW.
* **AArch64 v8.0**: acquire, consume and seq_cst loads are `LDAR`, release and seq_cst stores are `STLR`. RMWs are
  load-exclusive/store-exclusive loops: `LDXR`/`STXR` for relaxed, `LDAXR`/`STLXR` for acq_rel and seq_cst.
* **Neoverse N1**: acquire (and consume) become **`LDAPR`**, while **seq_cst loads stay `LDAR`** (§1.1: RCpc vs RCsc).
  LSE turns the RMW loops into single instructions: `LDADD`, `LDADDAL`, `SWPAL` (the `AL` suffix means
  acquire + release).
* **Neoverse V1**: `LDAPUR`/`STLUR` (`FEAT_LRCPC2`) take an immediate offset, so `field_acquire` and `field_release`
  lose the `ADD`.
* **consume = acquire** on every target, the reason C++26 deprecated it (P3475).

### 1.3 The litmus tests, run (Listing 7.5)

```cpp
// litmus.cpp - SB, MP, LB and IRIW run on this machine: which outcomes x86-64 really produces
#include <atomic>
#include <cstddef>
#include <print>
#include <thread>
#include <vector>

constexpr auto rlx = std::memory_order_relaxed;
constexpr auto acq = std::memory_order_acquire;
constexpr auto rel = std::memory_order_release;
constexpr auto sc = std::memory_order_seq_cst;

// Sense-reversing spin barrier: threads leave it within tens of nanoseconds of each other, so the
// few-instruction test bodies really overlap (a futex-based barrier would wake them microseconds apart).
class SpinBarrier {
    const unsigned n_;
    std::atomic<unsigned> arrived_{0};
    std::atomic<unsigned> phase_{0};

public:
    explicit SpinBarrier(unsigned n) : n_(n) {}
    void wait() {
        const unsigned ph = phase_.load(acq);
        if (arrived_.fetch_add(1, std::memory_order_acq_rel) + 1 == n_) {
            arrived_.store(0, rlx);
            phase_.store(ph + 1, rel);
        } else {
            while (phase_.load(acq) == ph) {
            }
        }
    }
};

// One fresh pair of variables per iteration (no reset step between iterations), as litmus7 does.
struct Instance {
    std::vector<std::atomic<int>> x, y;
    std::vector<int> r0, r1, r2, r3;
    explicit Instance(std::size_t n) : x(n), y(n), r0(n), r1(n), r2(n), r3(n) {}
};

// Runs every thread body `n` times, all threads released together by the barrier for each iteration.
template <class... Body>
void litmus(std::size_t n, Body... body) {
    SpinBarrier bar(sizeof...(Body));
    std::vector<std::jthread> ts;
    (ts.emplace_back([&bar, n, body] {
         for (std::size_t i = 0; i < n; ++i) {
             bar.wait();
             body(i);
         }
     }),
     ...);
}

template <class Pred>
std::size_t count(std::size_t n, Pred p) {
    std::size_t c = 0;
    for (std::size_t i = 0; i < n; ++i)
        if (p(i)) ++c;
    return c;
}

void report(const char* test, const char* outcome, bool cpp_allows, bool tso_allows, std::size_t seen,
            std::size_t n, bool& violated) {
    if (seen && (!cpp_allows || !tso_allows)) violated = true;
    std::println("{:<30} {:<18} {:<11} {:<14} {:>7} / {}", test, outcome, cpp_allows ? "yes" : "no",
                 tso_allows ? "yes" : "no", seen, n);
}

// SB: each thread stores to one variable, then loads the other. r0 = r1 = 0 needs store->load reordering.
template <std::memory_order St, std::memory_order Ld, bool Fence = false>
std::size_t store_buffering(std::size_t n) {
    Instance s(n);
    litmus(n,
           [&](std::size_t i) {
               s.x[i].store(1, St);
               if constexpr (Fence) std::atomic_thread_fence(sc);
               s.r0[i] = s.y[i].load(Ld);
           },
           [&](std::size_t i) {
               s.y[i].store(1, St);
               if constexpr (Fence) std::atomic_thread_fence(sc);
               s.r1[i] = s.x[i].load(Ld);
           });
    return count(n, [&](std::size_t i) { return s.r0[i] == 0 && s.r1[i] == 0; });
}

// MP with relaxed atomics: flag seen set but data not yet visible.
std::size_t message_passing_relaxed(std::size_t n) {
    Instance s(n);  // x = data, y = flag
    litmus(n,
           [&](std::size_t i) {
               s.x[i].store(1, rlx);
               s.y[i].store(1, rlx);
           },
           [&](std::size_t i) {
               s.r0[i] = s.y[i].load(rlx);
               s.r1[i] = s.x[i].load(rlx);
           });
    return count(n, [&](std::size_t i) { return s.r0[i] == 1 && s.r1[i] == 0; });
}

// LB: each thread loads one variable, then stores to the other. r0 = r1 = 1 needs load->store reordering.
std::size_t load_buffering_relaxed(std::size_t n) {
    Instance s(n);
    litmus(n,
           [&](std::size_t i) {
               s.r0[i] = s.x[i].load(rlx);
               s.y[i].store(1, rlx);
           },
           [&](std::size_t i) {
               s.r1[i] = s.y[i].load(rlx);
               s.x[i].store(1, rlx);
           });
    return count(n, [&](std::size_t i) { return s.r0[i] == 1 && s.r1[i] == 1; });
}

// IRIW: two writers, two readers that read the variables in opposite orders. The outcome means the readers
// disagree on the order of two independent stores.
std::size_t iriw_acquire(std::size_t n) {
    Instance s(n);
    litmus(n,
           [&](std::size_t i) { s.x[i].store(1, rel); },
           [&](std::size_t i) { s.y[i].store(1, rel); },
           [&](std::size_t i) {
               s.r0[i] = s.x[i].load(acq);
               s.r1[i] = s.y[i].load(acq);
           },
           [&](std::size_t i) {
               s.r2[i] = s.y[i].load(acq);
               s.r3[i] = s.x[i].load(acq);
           });
    return count(n, [&](std::size_t i) { return s.r0[i] == 1 && s.r1[i] == 0 && s.r2[i] == 1 && s.r3[i] == 0; });
}

int main() {
    constexpr std::size_t n = 100'000, n4 = 50'000;
    bool violated = false;
    std::println("{:<30} {:<18} {:<11} {:<14} {:>7}", "test", "outcome", "C++ allows", "x86-TSO allows",
                 "seen / runs");
    report("SB   relaxed", "r0=0 r1=0", true, true, store_buffering<rlx, rlx>(n), n, violated);
    report("SB   release / acquire", "r0=0 r1=0", true, true, store_buffering<rel, acq>(n), n, violated);
    report("SB   seq_cst", "r0=0 r1=0", false, false, store_buffering<sc, sc>(n), n, violated);
    report("SB   relaxed + seq_cst fences", "r0=0 r1=0", false, false, store_buffering<rlx, rlx, true>(n), n,
           violated);
    report("MP   relaxed", "flag=1 data=0", true, false, message_passing_relaxed(n), n, violated);
    report("LB   relaxed", "r0=1 r1=1", true, false, load_buffering_relaxed(n), n, violated);
    report("IRIW release / acquire", "1,0 and 1,0", true, false, iriw_acquire(n4), n4, violated);
    std::println("outcomes forbidden by C++ or by x86-TSO observed: {}", violated ? "YES (bug)" : "none");
}
```

Output (verified, GCC then Clang; counts vary between runs):

```text
test                           outcome            C++ allows  x86-TSO allows seen / runs
SB   relaxed                   r0=0 r1=0          yes         yes               2473 / 100000
SB   release / acquire         r0=0 r1=0          yes         yes               2692 / 100000
SB   seq_cst                   r0=0 r1=0          no          no                   0 / 100000
SB   relaxed + seq_cst fences  r0=0 r1=0          no          no                   0 / 100000
MP   relaxed                   flag=1 data=0      yes         no                   0 / 100000
LB   relaxed                   r0=1 r1=1          yes         no                   0 / 100000
IRIW release / acquire         1,0 and 1,0        yes         no                   0 / 50000
outcomes forbidden by C++ or by x86-TSO observed: none
test                           outcome            C++ allows  x86-TSO allows seen / runs
SB   relaxed                   r0=0 r1=0          yes         yes                403 / 100000
SB   release / acquire         r0=0 r1=0          yes         yes                672 / 100000
SB   seq_cst                   r0=0 r1=0          no          no                   0 / 100000
SB   relaxed + seq_cst fences  r0=0 r1=0          no          no                   0 / 100000
MP   relaxed                   flag=1 data=0      yes         no                   0 / 100000
LB   relaxed                   r0=1 r1=1          yes         no                   0 / 100000
IRIW release / acquire         1,0 and 1,0        yes         no                   0 / 50000
outcomes forbidden by C++ or by x86-TSO observed: none
```

Across repeated runs, SB with relaxed or release/acquire produced r0 = r1 = 0 in 403 to 2,987 of 100,000 instances
(0.4–3%). The other rows were 0 in every run. The full picture, with the AArch64 column taken from the architecture model
(⚠ not run):

| Test (outcome) | C++ allows | x86-TSO | AArch64 model, with the instructions of Listing 7.4 | Seen here (x86-64) |
|---|---|---|---|---|
| SB relaxed (0,0) | yes | yes | yes (`STR`; `LDR`) | yes, 0.4–3% |
| SB release/acquire (0,0) | **yes** | yes | v8.0 `STLR`;`LDAR`: **no** (RCsc). N1/V1 `STLR`;`LDAPR`: **yes** | yes, 0.7–3% |
| SB seq_cst (0,0) | no | no (`XCHG`) | no (`STLR`;`LDAR`) | never |
| SB relaxed + seq_cst fences | no | no (`LOCK OR` fence) | no (`DMB ISH`) | never |
| MP relaxed (flag=1, data=0) | yes | no | **yes** (stores and loads reorder) | never |
| LB relaxed (1,1) | yes | no | **yes** in the model (load→store reordering) | never |
| IRIW release/acquire (1,0 / 1,0) | **yes** (for POWER) | no | no (other-multi-copy-atomic + ordered acquire loads) | never |
| IRIW relaxed | yes | no | yes (each reader's two loads may reorder) | not run |

Four lessons follow:

1. **Release/acquire does not forbid SB.** On x86 it compiles to the same `MOV`s as relaxed, and the outcome appears at
   the same rate. Dekker- and Peterson-style mutual exclusion, "set my flag, then check yours", needs `seq_cst`.
2. **An x86 stress test can find SB bugs and nothing else.** MP, LB and IRIW are forbidden by TSO itself. A relaxed
   message-passing bug passes every x86 test and fails on ARM.
3. **AArch64 v8.0 happened to forbid SB for release/acquire, and newer cores don't.** Code that "worked on our older
   ARM servers" can break on an N1/V1 build, because the compiler switched acquire loads from `LDAR` to `LDAPR`. The C++
   program was always allowed to produce (0,0).
4. **C++ allows IRIW disagreement even with acquire/release**, because POWER is not multi-copy-atomic. Neither x86
   nor ARMv8 produces it. Only `seq_cst` forbids it in the language.

### 1.4 What each order costs on x86-64 (Listing 7.6)

```cpp
// sc_cost.cpp - what each order costs on x86-64, one thread, no contention: MOV vs XCHG vs MFENCE vs LOCK XADD
#include <atomic>
#include <chrono>
#include <cstdint>
#include <print>

constexpr int kOps = 20'000'000;
std::atomic<int> a{0}, b{0};

template <class F>
double ns_per_op(F f) {
    for (int i = 0; i < kOps / 10; ++i) f(i);   // warm up
    const auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < kOps; ++i) f(i);
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    return d.count() / kOps;
}

int main() {
    std::int64_t sink = 0;
    const double st_rlx = ns_per_op([](int i) { a.store(i, std::memory_order_relaxed); });
    const double st_rel = ns_per_op([](int i) { a.store(i, std::memory_order_release); });
    const double st_sc = ns_per_op([](int i) { a.store(i, std::memory_order_seq_cst); });
    const double st_fence = ns_per_op([](int i) {
        a.store(i, std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_seq_cst);
    });
    const double rmw = ns_per_op([](int) { a.fetch_add(1, std::memory_order_relaxed); });
    const double ld_acq = ns_per_op([&](int) { sink += a.load(std::memory_order_acquire); });
    const double ld_sc = ns_per_op([&](int) { sink += a.load(std::memory_order_seq_cst); });
    // The pattern seq_cst exists for: a store followed by a load of ANOTHER variable (Dekker / SB).
    const double sb_rel = ns_per_op([&](int i) {
        a.store(i, std::memory_order_release);
        sink += b.load(std::memory_order_acquire);
    });
    const double sb_sc = ns_per_op([&](int i) {
        a.store(i, std::memory_order_seq_cst);
        sink += b.load(std::memory_order_seq_cst);
    });
    std::println("store relaxed                   {:6.2f} ns   (MOV)", st_rlx);
    std::println("store release                   {:6.2f} ns   (MOV: TSO already orders it)", st_rel);
    std::println("store seq_cst                   {:6.2f} ns   (XCHG: implicit LOCK, drains the store buffer)", st_sc);
    std::println("store relaxed + seq_cst fence   {:6.2f} ns   (MOV + LOCK OR $0 to the stack, not MFENCE)", st_fence);
    std::println("fetch_add relaxed               {:6.2f} ns   (LOCK XADD: every RMW is a full barrier on x86)", rmw);
    std::println("load acquire                    {:6.2f} ns   (MOV)", ld_acq);
    std::println("load seq_cst                    {:6.2f} ns   (MOV)", ld_sc);
    std::println("store+load release/acquire      {:6.2f} ns   (SB outcome possible)", sb_rel);
    std::println("store+load seq_cst              {:6.2f} ns   (SB outcome forbidden)", sb_sc);
    std::println("(checksum {})", sink & 0xFF);   // keeps the loads alive
}
```

Output (verified, GCC then Clang):

```text
store relaxed                     0.19 ns   (MOV)
store release                     0.26 ns   (MOV: TSO already orders it)
store seq_cst                     5.46 ns   (XCHG: implicit LOCK, drains the store buffer)
store relaxed + seq_cst fence     4.66 ns   (MOV + LOCK OR $0 to the stack, not MFENCE)
fetch_add relaxed                 4.63 ns   (LOCK XADD: every RMW is a full barrier on x86)
load acquire                      0.24 ns   (MOV)
load seq_cst                      0.26 ns   (MOV)
store+load release/acquire        0.28 ns   (SB outcome possible)
store+load seq_cst                4.66 ns   (SB outcome forbidden)
(checksum 0)
store relaxed                     0.12 ns   (MOV)
store release                     0.12 ns   (MOV: TSO already orders it)
store seq_cst                     4.73 ns   (XCHG: implicit LOCK, drains the store buffer)
store relaxed + seq_cst fence     4.67 ns   (MOV + LOCK OR $0 to the stack, not MFENCE)
fetch_add relaxed                 4.62 ns   (LOCK XADD: every RMW is a full barrier on x86)
load acquire                      0.12 ns   (MOV)
load seq_cst                      0.12 ns   (MOV)
store+load release/acquire        0.21 ns   (SB outcome possible)
store+load seq_cst                4.67 ns   (SB outcome forbidden)
(checksum 0)
```

Over repeated runs, a `seq_cst` store cost 4.7–5.5 ns and a relaxed or release store 0.12–0.26 ns: **20–40× more,
with no contention at all.** That is the cost of draining the store buffer, which the release store simply doesn't do.
A relaxed store plus a `seq_cst` fence (`LOCK OR` to the stack, file 04), and any `LOCK`ed RMW, cost the same 4.6–5 ns.
Loads cost the same for every order. The SB pattern (store, then load another variable) costs 0.21–0.28 ns with
release/acquire and 4.6–4.7 ns with `seq_cst`: that is the price of forbidding the (0,0) outcome. On AArch64 the
relative costs depend on the core (⚠ not measured here). `LDAR` and `LDAPR` differ in whether the load may complete before
an earlier `STLR`, not in instruction count.

### 1.5 Choosing an order

| You need | Use | Why |
|---|---|---|
| a counter, a statistic, a "max seen" value; no conclusion about other data | `relaxed` | atomicity + per-object coherence (file 01, §1.4 D) |
| publish data, then a flag/pointer | `release` store | earlier writes become visible to whoever acquires the flag |
| read a flag/pointer, then the data it guards | `acquire` load | later reads cannot move before it |
| an RMW that both consumes and publishes (lock acquire/release, refcount last-drop) | `acq_rel` (or acquire on lock, release on unlock) | both edges on one operation |
| "set mine, then read yours" (SB/Dekker), or a single global order of independent events (IRIW) | `seq_cst` | the only order that forbids those outcomes |
| unsure, not on a hot path | `seq_cst` (the default) | correct for more programs; costs only on stores and RMWs |

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| order values | `memory_order_relaxed` … `seq_cst` (unscoped enum) | — | `consume` temporarily discouraged (P0371) | `enum class memory_order` with `std::memory_order::relaxed` etc. + old names as constants (P0439) | — | `consume` deprecated (P3475) |
| `seq_cst` semantics | single total order `S` | — | — | `S` reformulated, `seq_cst` fences strengthened (P0668) so the standard POWER/ARM mappings are correct | — | — |
| fences vs orders | `atomic_thread_fence`, `atomic_signal_fence` | — | — | fence rules restated with the new `S` (P0668) | — | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| Dekker/Peterson-style "both raise a flag, then check the other" | release stores + acquire loads (SB observed in 0.7–3% of runs, Listing 7.5) | `seq_cst` stores and loads, or a `seq_cst` fence between the store and the load |
| message passing tested on x86 only | relaxed flag "works" (MP never observed on x86) | release/acquire, plus an ARM64 CI job or a litmus-style stress test on ARM hardware |
| hot-path publish in a queue | `seq_cst` store by default (20–40× a release store on x86) | release store; document the acquire it pairs with |
| relying on "LOCK is a full barrier" | relaxed `fetch_add` used as a fence on x86 | state the order you need (`acq_rel`); on ARM64 a relaxed RMW orders nothing |
| choosing order per call site | the same atomic accessed with `seq_cst` here and `relaxed` there "for speed" | one documented protocol per atomic; mixed-order reasoning is where P0668's subtleties live |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| two threads both enter a Peterson/Dekker critical section | SB outcome with release/acquire | Listing 7.5 style stress test (fails on x86 too); `seq_cst` fixes it |
| corrupted or half-initialized objects only on ARM servers | relaxed (or plain) publication, MP outcome | ARM64 stress tests; review relaxed atomics that guard other data |
| a regression after moving to newer ARM cores (N1/V1/Graviton 2+) | the code relied on `LDAR`'s RCsc behaviour (SB forbidden) instead of `seq_cst` | check for release/acquire-based "flag then check" protocols |
| `seq_cst` hot path dominates a profile on x86 | `XCHG` per store (4.7–5.5 ns) | perf: `XCHG`/`LOCK` instructions in the hot loop |
| lock-free code "proven correct" with relaxed RMWs on x86 | x86 RMWs are full barriers by accident | compile for AArch64 and read the asm: `LDXR`/`STXR` or `LDADD` without `A`/`L` |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Acquire and release are free on x86, right?"</b></summary>

**Initial prompt.** "Why do people say acquire/release is free on x86, and is `seq_cst` free too?"

**L5 textbook answer.** "x86 is strongly ordered, so all atomics compile to plain moves and are free."

**Why L5 breaks.** Only half true (Listing 7.4). Loads of every order and relaxed and release stores are plain `MOV`,
because TSO already provides acquire for loads and release for stores. A `seq_cst` store is `XCHG`, and every RMW is
`LOCK`ed. Listing 7.6: 4.7–5.5 ns against 0.12–0.26 ns, uncontended. "Free" also ignores the compiler: an acquire load
still forbids the compiler from hoisting later accesses above it, even on x86.

**L7 principal defense.** "On x86: loads free, release stores free, `seq_cst` stores and all RMWs about 20 cycles
because they drain the store buffer. On ARMv8.0: acquire = `LDAR`, release = `STLR`, `seq_cst` the same instructions;
on RCpc cores acquire becomes the cheaper `LDAPR`. I choose the order for correctness, then know what it costs on each
target."
</details>

<details><summary><b>Chain 2 🔥 "Implement Peterson's lock with acquire/release"</b></summary>

**Initial prompt.** "Two threads. `flag[me].store(true, release); turn = other; while (flag[other].load(acquire) &&
turn == other) {}`. Is mutual exclusion guaranteed?"

**L5 textbook answer.** "Yes: the release store makes my flag visible before I read the other flag with acquire."

**Why L5 corrupts memory on ARM64.** Release orders *earlier* operations before the store. Acquire orders *later*
operations after the load. Nothing orders a release store before a *later* load: that is store→load reordering, the SB
pattern. Both threads can read the other's flag as `false` and both enter the critical section. Listing 7.5 shows exactly
this outcome with release/acquire, in 0.7–3% of instances, **on x86 itself**. On RCpc ARM cores (`STLR` followed by
`LDAPR`) it is allowed too. Only ARMv8.0's RCsc `LDAR` accidentally prevented it.

**L7 principal defense.** "Peterson and Dekker need `seq_cst` on the flag and turn accesses (or a `seq_cst` fence
between my store and my load). That's the textbook case for `seq_cst`. In production I'd use a real mutex: Peterson
doesn't scale past two threads, and its `seq_cst` store per acquisition costs about the same as the one `LOCK`ed CAS
an uncontended `std::mutex` lock performs."
</details>

<details><summary><b>Chain 3 ⚡ "It passed a billion iterations of stress testing"</b></summary>

**Initial prompt.** "Our lock-free queue uses relaxed for the 'slot ready' flag and passed 10^9 iterations of a stress
test on our x86 CI fleet. Ship it?"

**L5 textbook answer.** "With that many iterations any reordering would have shown up, so it's safe."

**Why L5 corrupts memory on ARM64.** The test cannot fail on x86. MP (flag seen, data not yet visible) is forbidden by
TSO: Listing 7.5 shows 0 in every run, while the C++ program is allowed to produce it. The compiler emits plain `STR`/`LDR`
for those relaxed accesses on AArch64, which the architecture may reorder (MP is allowed in the AArch64 model and has
been observed on ARM hardware, *Herding Cats*). The first Graviton or Apple-silicon deployment is the real test.

**L7 principal defense.** "Release on the 'ready' store, acquire on the 'ready' load. That's one `STLR` and one
`LDAPR`/`LDAR` on ARM, and free on x86. For validation: an AArch64 CI lane running the stress test, reasoning in
happens-before edges (file 01), and model checking for the core protocol (CDSChecker/GenMC style, Folder 12)."
</details>

<details><summary><b>Chain 4 🧊 "Do two readers always agree on the order of two independent writes?"</b></summary>

**Initial prompt.** "Two writers set `x = 1` and `y = 1` (release). Two readers read them in opposite orders (acquire).
Can reader 1 see x-then-not-y while reader 2 sees y-then-not-x?"

**L5 textbook answer.** "No: acquire/release gives a consistent order, and on any real CPU stores become visible in one
order."

**Why L5 breaks.** C++ allows it (IRIW): with release/acquire, nothing creates a single order of independent stores.
The allowance exists for POWER, which is not multi-copy-atomic: a store can reach one core before another. x86-TSO and
ARMv8 (other-multi-copy-atomic, with ordered acquire loads) both forbid it in hardware, and Listing 7.5 shows 0 on x86.
So code relying on it is correct in practice on x86/ARM and wrong by the standard: not portable to POWER, and
technically an assumption the compiler is not obliged to preserve.

**L7 principal defense.** "If a protocol needs all threads to agree on the order of independent events (leader
election from two flags, 'who came first'), those operations are `seq_cst`, the only order whose single total order `S`
covers them. Otherwise I design so that no two readers need to compare."
</details>

<details><summary><b>Chain 5 ⚡ "Just make everything seq_cst"</b></summary>

**Initial prompt.** "Memory orders are hard. Isn't the safest policy to use the default `seq_cst` everywhere?"

**L5 textbook answer.** "Yes: `seq_cst` is sequentially consistent, so the program behaves like interleaved threads
and all bugs go away."

**Why L5 breaks.** `seq_cst` atomics give sequential consistency only for the atomics themselves, and only for
data-race-free programs. They don't fix race conditions: `store(load() + 1)` with `seq_cst` still loses updates
(file 01, Listing 7.2). They cost real time on hot paths (Listing 7.6: `XCHG` per store). And when other code uses weaker
orders on the same objects, the guarantees become the subtle ones P0668 had to repair.

**L7 principal defense.** "Default to `seq_cst` when correctness reasoning is not done, and that is a fine policy for
cold code. On hot paths, prove the protocol with acquire/release and write the proof in a comment: which release pairs
with which acquire. And keep one order discipline per atomic object."
</details>

<details><summary><b>Chain 6 🧊 "Why does the compiler use LDAPR for acquire but LDAR for seq_cst?"</b></summary>

**Initial prompt.** "On Graviton 2 builds, acquire loads became `LDAPR` but `seq_cst` loads stayed `LDAR`. Isn't
`LDAPR` just a faster `LDAR`?"

**L5 textbook answer.** "Yes, LDAPR is the newer, optimized acquire load; the compiler is just being conservative
for seq_cst."

**Why L5 breaks.** They differ in one ordering rule. `LDAR` (RCsc) cannot complete before an earlier `STLR` to another
address; `LDAPR` (RCpc) can. `seq_cst` needs store→load order between `seq_cst` operations (to forbid SB), and AArch64
gets it from `STLR` + `LDAR` with no fence. Using `LDAPR` for `seq_cst` loads would allow SB, so compilers keep `LDAR`
(Listing 7.4, N1/V1 columns).

**L7 principal defense.** "RCsc vs RCpc. That's also why a release/acquire Dekker protocol that 'worked' on ARMv8.0
can break on RCpc cores: the C++ program was always allowed to produce SB (0,0), and v8.0's `LDAR` just didn't."
</details>

<details><summary><b>Chain 7 🔥 "A relaxed fetch_add is a full barrier anyway"</b></summary>

**Initial prompt.** "Our ring buffer publishes a slot with `count.fetch_add(1, relaxed)` after writing it. On x86,
`LOCK XADD` is a full barrier, so the slot write is visible first. Fine?"

**L5 textbook answer.** "Yes: every locked instruction drains the store buffer, so relaxed and seq_cst RMWs are
identical."

**Why L5 corrupts memory on ARM64.** That's an x86 implementation detail, not the C++ contract. On AArch64 the relaxed
RMW is `LDXR`/`STXR` (v8.0) or `LDADD` (LSE) without acquire/release semantics (Listing 7.4), so the slot write can
become visible after the count. The consumer reads a stale slot. The compiler may also legally move the slot store after
a relaxed RMW, even on x86.

**L7 principal defense.** "Publishing needs `release` on the RMW (`LDADDL`/`STLXR` on ARM, unchanged on x86) and
`acquire` on the consumer's read. I write the order the protocol needs, and I review lock-free code by reading the
AArch64 output, because that's where missing orders become visible."
</details>

<details><summary><b>Chain 8 ⚠ "What is memory_order_consume for?"</b></summary>

**Initial prompt.** "Linux RCU readers use dependency ordering, not acquire. Shouldn't we use `memory_order_consume`
for pointer-chasing readers?"

**L5 textbook answer.** "Yes: consume orders only loads that depend on the pointer, so it's free on ARM, where
dependencies are ordered by hardware."

**Why L5 breaks.** The hardware fact is right (AArch64 orders address-dependent loads), but C++ cannot keep a
dependency alive through optimization: a compiler can replace `p->field` with a value it proved equal, breaking the
dependency. So every compiler implements `consume` as `acquire` (Listing 7.4: `LDAR`/`LDAPR`, identical to acquire), and
C++26 deprecated it (P3475). Linux relies on compiler-specific behaviour and `READ_ONCE`, which is not available to
portable C++.

**L7 principal defense.** "Use acquire. On RCpc cores `LDAPR` is the cheap acquire anyway. For RCU-style reclamation,
use C++26 `<rcu>` / hazard pointers when available, or an epoch scheme (Folder 09)."
</details>

---

## 6. Invariants checklist

- [ ] Every non-relaxed atomic has a documented partner: release ↔ acquire.
- [ ] "Store my flag, then load yours" protocols use `seq_cst` (or a `seq_cst` fence between).
- [ ] No correctness argument rests on x86 `LOCK` semantics or on ARMv8.0 `LDAR` being RCsc.
- [ ] Lock-free code has been compiled for AArch64 and the orders checked in the asm.
- [ ] Hot-path stores are release, not `seq_cst`, unless SB/IRIW must be forbidden.
- [ ] `memory_order_consume` is not used in new code.

## 7. References

- P. Sewell et al., "x86-TSO: a rigorous and usable programmer's model for x86 multiprocessors", CACM 2010: <https://www.cl.cam.ac.uk/~pes20/weakmemory/cacm.pdf>
- Arm Architecture Reference Manual for A-profile, chapter B2 (memory model): <https://developer.arm.com/documentation/ddi0487/latest>
- C/C++11 mappings to processors (x86, POWER, ARMv7, ARMv8): <https://www.cl.cam.ac.uk/~pes20/cpp/cpp0xmappings.html>
- herd7 / diy / litmus7 (memory-model simulators and hardware testers): <https://diy.inria.fr/>
- J. Alglave, L. Maranget, M. Tautschnig, "Herding Cats", TOPLAS 2014: <https://arxiv.org/abs/1308.6810>
- P0668R5 (revising the C++ memory model): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0668r5.html>
- P0439R0 (`enum class memory_order`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0439r0.html>
- J. Preshing, "Memory Reordering Caught in the Act": <https://preshing.com/20120515/memory-reordering-caught-in-the-act/>
