# 04 · Safe memory reclamation: epoch-based reclamation, C++26 hazard pointers, and RCU

> **Scope.** A lock-free structure removes a node with one CAS, but readers that loaded the pointer *before* that CAS
> may still be dereferencing it. In a garbage-collected language the collector waits for them. In C++, freeing the
> node immediately is a use-after-free, and recycling it is ABA. Safe memory reclamation (SMR) answers "when is it safe
> to free?". This file implements the three standard answers in the shape of the C++26 APIs: hazard pointers
> (P2530), epoch-based reclamation, and RCU in its quiescent-state flavour (the idea behind P2545). Neither standard
> library here ships C++26's `<hazard_pointer>` or `<rcu>`. The file then measures the two properties that decide
> between them: **how much memory a stalled reader can pin, and what a read costs.**

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 9.8 | `hazard.hpp` | a hazard-pointer domain: `make_hazard_pointer`, `protect` (publish + re-check, seq_cst), `hazard_pointer_obj_base::retire`, amortized scans, orphan lists | compiled into 9.10 |
| 9.9 | `ebr.hpp` | epoch-based reclamation: announce + re-check + fence, two-epoch rule, per-thread limbo lists, orphans | compiled into 9.10 |
| 9.10 | `smr_compare.cpp` | **a stalled reader pins 1 of 10,000 retired versions with hazard pointers and all 10,000 with EBR**; read-path cost (3 readers + a writer): QSBR 0.33–0.46 ns, hazard pointers 1.8–2.1 ns, EBR 3.9–19.6 ns, mutex 24–40 ns, `atomic<shared_ptr>` 109–119 ns, `shared_mutex` 61–250 ns; 0 corrupted reads | run, both compilers; asm x86-64 + AArch64 of the three read paths |

**Verification line.** As in file 01. "ns per read" is wall time divided by the total number of reads of 3 readers
running in parallel (aggregate throughput, not single-read latency). Ranges are over two runs per compiler.

---

## 1. First principles

### 1.1 The problem, and the three answers

```text
   reader R: p = head.load()  ......  p->value  (still using p)
   writer W:              head.CAS(p -> p->next);  free(p)?   <-- when?
```

| Scheme | What a reader does | When W may free | Memory a stalled reader pins | Read cost here |
|---|---|---|---|---|
| **hazard pointers** | publish each pointer it will dereference in its own slot, then re-check the source | when no slot holds it (W scans all slots) | the nodes it currently protects: bounded (≤ slots) | 1.8–2.1 ns |
| **epoch-based (EBR)** | announce the global epoch at the start of a read section | two epoch advances after it was retired | **everything retired since the reader entered: unbounded** | 3.9–19.6 ns |
| **RCU / QSBR** | nothing per read; report "quiescent" between operations | after a grace period: every reader has reported since the removal | everything since its last report: unbounded | 0.33–0.46 ns |
| reference counting (`atomic<shared_ptr>`) | increment/decrement a shared count | when the count reaches 0 | what it holds | 109–119 ns (lock bit + count line contended) |

### 1.2 Hazard pointers (Listing 9.8)

```cpp
// hazard.hpp - a minimal hazard-pointer domain with the shape of C++26 <hazard_pointer> (P2530); neither library ships one
#pragma once
#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <mutex>
#include <utility>
#include <vector>

namespace hp {

constexpr std::size_t kSlots = 64;   // hazard slots in the domain: (threads) x (pointers protected at once)

struct alignas(64) Slot {           // one line per slot: a reader writes only its own slot
    std::atomic<const void*> ptr{nullptr};
    std::atomic<bool> taken{false};
};
inline Slot g_slots[kSlots];

struct Retired {
    void* p;
    void (*reclaim)(void*);
};
inline std::mutex g_orphans_m;               // nodes retired by threads that have exited
inline std::vector<Retired> g_orphans;
inline std::atomic<std::uint64_t> g_reclaimed{0};

class hazard_pointer {
    Slot* slot_ = nullptr;
    explicit hazard_pointer(Slot* s) noexcept : slot_(s) {}
    friend hazard_pointer make_hazard_pointer();

public:
    hazard_pointer() noexcept = default;
    hazard_pointer(hazard_pointer&& o) noexcept : slot_(std::exchange(o.slot_, nullptr)) {}
    hazard_pointer& operator=(hazard_pointer&& o) noexcept {
        std::swap(slot_, o.slot_);
        return *this;
    }
    ~hazard_pointer() {
        if (slot_) {
            slot_->ptr.store(nullptr, std::memory_order_release);
            slot_->taken.store(false, std::memory_order_release);
        }
    }
    // Publish the pointer we are about to use, then re-read the source. If it still holds that pointer, any thread
    // that unlinks it afterwards will see our hazard when it scans. Store-then-load across two locations is the SB
    // pattern (Folder 07): both must be seq_cst, or the reclaimer could miss the hazard and free the node.
    template <class T>
    T* protect(const std::atomic<T*>& src) noexcept {
        T* p = src.load(std::memory_order_relaxed);
        for (;;) {
            slot_->ptr.store(p, std::memory_order_seq_cst);
            T* again = src.load(std::memory_order_seq_cst);
            if (again == p) return p;
            p = again;
        }
    }
    void reset_protection() noexcept { slot_->ptr.store(nullptr, std::memory_order_release); }
};

inline hazard_pointer make_hazard_pointer() {
    for (Slot& s : g_slots) {
        bool expected = false;
        if (!s.taken.load(std::memory_order_relaxed) &&
            s.taken.compare_exchange_strong(expected, true, std::memory_order_acquire))
            return hazard_pointer(&s);
    }
    std::abort();   // more simultaneous hazard pointers than slots: a sizing bug
}

// Each thread keeps its retired nodes and scans once it holds 2 x kSlots of them, so every scan frees at least
// half: amortized O(1) per retire, and at most kSlots x threads nodes can be pinned by readers at any time.
class RetireList {
    std::vector<Retired> list_;

public:
    void add(Retired r) {
        list_.push_back(r);
        if (list_.size() >= 2 * kSlots) scan();
    }
    void scan() {
        std::atomic_thread_fence(std::memory_order_seq_cst);   // our unlinks happen before we read the hazards
        std::vector<const void*> hazards;
        for (const Slot& s : g_slots)
            if (const void* p = s.ptr.load(std::memory_order_acquire)) hazards.push_back(p);
        std::sort(hazards.begin(), hazards.end());
        auto unprotected = std::partition(list_.begin(), list_.end(), [&](const Retired& r) {
            return std::binary_search(hazards.begin(), hazards.end(), static_cast<const void*>(r.p));
        });
        for (auto it = unprotected; it != list_.end(); ++it) it->reclaim(it->p);
        g_reclaimed.fetch_add(static_cast<std::uint64_t>(list_.end() - unprotected), std::memory_order_relaxed);
        list_.erase(unprotected, list_.end());
    }
    ~RetireList() {   // thread exit: free what we can, hand the rest to the domain
        scan();
        std::scoped_lock lk(g_orphans_m);
        g_orphans.insert(g_orphans.end(), list_.begin(), list_.end());
    }
    std::size_t pending() const { return list_.size(); }
};
inline thread_local RetireList t_retired;

// CRTP base, as in the standard: `node->retire()` hands the object to the domain.
template <class T>
class hazard_pointer_obj_base {
public:
    void retire() noexcept {
        t_retired.add({static_cast<T*>(this), [](void* p) { delete static_cast<T*>(p); }});
    }
};

inline void scan_now() { t_retired.scan(); }

// After all other threads have joined: reclaim this thread's list and every orphan that is not protected.
inline void drain() {
    t_retired.scan();
    std::scoped_lock lk(g_orphans_m);
    for (const Retired& r : g_orphans) r.reclaim(r.p);
    g_reclaimed.fetch_add(g_orphans.size(), std::memory_order_relaxed);
    g_orphans.clear();
}

}  // namespace hp
```

* **`protect` is a store-then-load across two locations: the SB pattern of Folder 07.** The reader stores `p` into its
  slot and re-loads the source. The reclaimer unlinks `p` (a store to the source), executes a `seq_cst` fence, and loads
  every slot. Sequential consistency guarantees that at least one side sees the other. Either the reader's re-load sees
  the unlink (it retries with the new pointer), or the reclaimer's scan sees the hazard (it keeps the node). With
  release/acquire instead, *both* can miss, on x86 included (SB was observed in 0.4–3% of runs there, Folder 07 Listing
  7.5), and the node is freed under the reader.
* **The scan is amortized.** Each thread keeps a retire list and scans once it holds 2 × (number of slots) nodes, so a
  scan frees at least half of them. That is O(1) amortized per retire, with memory bounded by slots × threads.
* **The API mirrors C++26**: `hazard_pointer_obj_base<T>` (CRTP) with `retire()`, `make_hazard_pointer()`, `protect()`,
  `reset_protection()`. The standard adds `try_protect`, custom deleters and domains. Production implementations (folly
  `hazptr`, from which P2530 came) make the reader side cheaper with **asymmetric fences**: the reader uses only a
  compiler barrier, and the rare scanner issues a process-wide barrier (Linux `membarrier`) (⚠ not implemented here).

### 1.3 Epoch-based reclamation (Listing 9.9)

```cpp
// ebr.hpp - epoch-based reclamation (Fraser, 2004): readers announce an epoch; a retired node is freed two epochs later
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <mutex>
#include <vector>

namespace ebr {

constexpr std::size_t kMaxThreads = 64;
inline std::atomic<std::uint64_t> g_epoch{1};
inline std::atomic<std::uint64_t> g_reclaimed{0};

struct alignas(64) Record {          // one line per thread; epoch 0 = not inside a critical section
    std::atomic<std::uint64_t> epoch{0};
    std::atomic<bool> taken{false};
};
inline Record g_records[kMaxThreads];

struct Retired {
    void* p;
    void (*reclaim)(void*);
    std::uint64_t epoch;             // the global epoch when it was retired
};
inline std::mutex g_orphans_m;       // limbo lists of threads that have exited
inline std::vector<Retired> g_orphans;

// Advance the global epoch if every thread inside a critical section has announced the current one.
inline bool try_advance() {
    std::uint64_t e = g_epoch.load(std::memory_order_seq_cst);
    for (const Record& r : g_records) {
        const std::uint64_t re = r.epoch.load(std::memory_order_seq_cst);
        if (re != 0 && re != e) return false;   // a reader is still in an older epoch: it may hold old pointers
    }
    return g_epoch.compare_exchange_strong(e, e + 1, std::memory_order_seq_cst);
}

class ThreadState {
    Record* rec_ = nullptr;
    std::vector<Retired> limbo_;

    [[gnu::noinline]] Record& acquire_record() {   // cold: once per thread
        for (Record& r : g_records) {
            bool expected = false;
            if (r.taken.compare_exchange_strong(expected, true)) return *(rec_ = &r);
        }
        std::abort();
    }

public:
    Record& record() { return rec_ ? *rec_ : acquire_record(); }
    void retire(Retired r) {
        limbo_.push_back(r);
        if (limbo_.size() >= 128) {
            try_advance();
            collect();
        }
    }
    // A node retired in epoch e can be freed once the global epoch reaches e + 2: every reader that could have
    // seen it announced e or earlier, and two advances prove all of them have left their critical sections.
    void collect() {
        const std::uint64_t now = g_epoch.load(std::memory_order_seq_cst);
        std::size_t kept = 0;
        for (const Retired& r : limbo_) {
            if (r.epoch + 2 <= now) {
                r.reclaim(r.p);
                g_reclaimed.fetch_add(1, std::memory_order_relaxed);
            } else {
                limbo_[kept++] = r;
            }
        }
        limbo_.resize(kept);
    }
    std::size_t pending() const { return limbo_.size(); }
    ~ThreadState() {   // thread exit: release the record, hand unfinished limbo to the domain
        if (rec_) rec_->taken.store(false, std::memory_order_release);
        std::scoped_lock lk(g_orphans_m);
        g_orphans.insert(g_orphans.end(), limbo_.begin(), limbo_.end());
    }
    void adopt_orphans() {
        std::scoped_lock lk(g_orphans_m);
        limbo_.insert(limbo_.end(), g_orphans.begin(), g_orphans.end());
        g_orphans.clear();
    }
};
inline thread_local ThreadState t_state;

// A read-side critical section. Announce the epoch and re-check it: if the global epoch moved between our load and
// our store, we announced a stale epoch that the reclaimer may already have passed, so announce again. The final
// seq_cst fence makes every unlink that preceded the epoch we saw visible to the loads inside the section.
class guard {
    Record& r_;

public:
    guard() : r_(t_state.record()) {
        std::uint64_t e = g_epoch.load(std::memory_order_seq_cst);
        for (;;) {
            r_.epoch.store(e, std::memory_order_seq_cst);
            const std::uint64_t now = g_epoch.load(std::memory_order_seq_cst);
            if (now == e) break;
            e = now;
        }
        std::atomic_thread_fence(std::memory_order_seq_cst);
    }
    ~guard() { r_.epoch.store(0, std::memory_order_release); }
    guard(const guard&) = delete;
    guard& operator=(const guard&) = delete;
};

template <class T>
void retire(T* p) {
    t_state.retire({p, [](void* q) { delete static_cast<T*>(q); }, g_epoch.load(std::memory_order_seq_cst)});
}

// Try to advance the epoch (three times: enough to make everything retired so far old enough, unless a reader
// pins an epoch), adopt orphaned limbo lists, and free what is safe.
inline void quiesce() {
    for (int i = 0; i < 3; ++i) try_advance();
    t_state.adopt_orphans();
    t_state.collect();
}

}  // namespace ebr
```

* **The two-epoch rule.** A reader inside a critical section has announced epoch e. The global epoch can advance from
  e to e + 1 while such readers exist, but not to e + 2. A node retired in epoch r was unlinked before r was read, so
  readers that can still hold it announced r or earlier, and once the global epoch reaches r + 2 all of them have left.
* **The announce/re-check loop** closes a window: if the global epoch advances between the reader's load and its
  store, the reader has announced an epoch the reclaimer may already have passed, so it announces again. The final
  `seq_cst` fence makes every unlink that preceded the epoch the reader saw visible to its loads in the section. A
  first draft of this listing lacked the loop; the reasoning above found the hole before any test could.
* **Cheap, but unbounded.** One read section costs two full barriers on x86 (the `xchg` announce and the `lock or`
  fence in the asm below), regardless of how many pointers it reads. A single reader stuck inside a section stops the
  epoch, and with it all reclamation.

### 1.4 The comparison (Listing 9.10)

```cpp
// smr_compare.cpp - hazard pointers vs EBR vs QSBR (user-space RCU) vs atomic<shared_ptr> vs locks, on one read path
#include "ebr.hpp"
#include "hazard.hpp"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <latch>
#include <memory>
#include <mutex>
#include <print>
#include <shared_mutex>
#include <thread>
#include <vector>
#if defined(__x86_64__)
#include <immintrin.h>
#endif

inline void cpu_relax() {
#if defined(__x86_64__)
    _mm_pause();
#elif defined(__aarch64__)
    asm volatile("yield");
#endif
}

struct Config : hp::hazard_pointer_obj_base<Config> {
    std::uint64_t version;
    std::uint64_t check;   // == 3 * version: a reader that sees a half-built or reused Config would notice
    explicit Config(std::uint64_t v) : version(v), check(3 * v) {}
};
std::atomic<Config*> g_cfg{nullptr};

// ---------------- QSBR: quiescent-state-based reclamation, the user-space RCU flavour with free readers ----------
namespace qsbr {
inline std::atomic<std::uint64_t> g_gp{1};          // grace-period counter
struct alignas(64) Rec {
    std::atomic<std::uint64_t> seen{0};             // the last grace period this reader acknowledged
    std::atomic<bool> online{false};
};
inline Rec g_recs[8];
inline void online(Rec& r) {
    r.seen.store(g_gp.load(std::memory_order_seq_cst), std::memory_order_seq_cst);
    r.online.store(true, std::memory_order_seq_cst);
    std::atomic_thread_fence(std::memory_order_seq_cst);
}
inline void quiescent(Rec& r) {   // "I hold no references": called between operations, not inside one
    r.seen.store(g_gp.load(std::memory_order_acquire), std::memory_order_release);
}
inline void offline(Rec& r) { r.online.store(false, std::memory_order_release); }
inline void synchronize() {       // wait until every online reader has passed a quiescent state
    const std::uint64_t gp = g_gp.fetch_add(1, std::memory_order_seq_cst) + 1;
    for (Rec& r : g_recs)
        while (r.online.load(std::memory_order_seq_cst) && r.seen.load(std::memory_order_acquire) < gp) cpu_relax();
}
}  // namespace qsbr

// Out-of-line copies of the three read paths, for the assembly listing.
Config* hp_read(hp::hazard_pointer& h) { return h.protect(g_cfg); }
std::uint64_t ebr_read() {
    ebr::guard g;
    return g_cfg.load(std::memory_order_acquire)->version;
}
std::uint64_t qsbr_read() { return g_cfg.load(std::memory_order_acquire)->version; }

// ---------------- A. One reader stalls inside its read section while the writer publishes 10,000 versions ----------
void stalled_reader() {
    constexpr std::uint64_t kVersions = 10'000;
    {
        g_cfg.store(new Config(0));
        std::latch holding(1), resume(1);
        std::jthread reader([&] {
            hp::hazard_pointer h = hp::make_hazard_pointer();
            Config* c = h.protect(g_cfg);
            holding.count_down();
            resume.wait();                                   // stalled, still protecting one Config
            if (c->check != 3 * c->version) std::println("HP: corrupted read");
        });
        holding.wait();
        const std::uint64_t base = hp::g_reclaimed.load();
        for (std::uint64_t v = 1; v <= kVersions; ++v) g_cfg.exchange(new Config(v))->retire();
        hp::scan_now();
        const std::uint64_t while_stalled = hp::g_reclaimed.load() - base;
        resume.count_down();
        reader.join();
        hp::scan_now();
        std::println("hazard pointers: while the reader is stalled {:>5} of {} retired versions freed; after it resumes {:>5}",
                     while_stalled, kVersions, hp::g_reclaimed.load() - base);
        delete g_cfg.exchange(nullptr);
    }
    {
        g_cfg.store(new Config(0));
        std::latch holding(1), resume(1);
        std::jthread reader([&] {
            ebr::guard g;
            Config* c = g_cfg.load(std::memory_order_acquire);
            holding.count_down();
            resume.wait();                                   // stalled inside its critical section
            if (c->check != 3 * c->version) std::println("EBR: corrupted read");
        });
        holding.wait();
        const std::uint64_t base = ebr::g_reclaimed.load();
        for (std::uint64_t v = 1; v <= kVersions; ++v) ebr::retire(g_cfg.exchange(new Config(v)));
        ebr::quiesce();
        const std::uint64_t while_stalled = ebr::g_reclaimed.load() - base;
        resume.count_down();
        reader.join();
        ebr::quiesce();
        std::println("epoch-based:     while the reader is stalled {:>5} of {} retired versions freed; after it resumes {:>5}",
                     while_stalled, kVersions, ebr::g_reclaimed.load() - base);
        delete g_cfg.exchange(nullptr);
    }
}

// ---------------- B. Read-path cost: 3 readers, 1 writer publishing a new version every ~20 us ----------------------
using Clock = std::chrono::steady_clock;
constexpr int kReaders = 3;
constexpr int kReads = 1'000'000;

template <class Reader, class Writer>
double read_ns(Reader reader, Writer writer, std::uint64_t& broken) {
    std::atomic<int> finished{0};
    std::atomic<std::uint64_t> bad{0};
    const auto t0 = Clock::now();
    double ns = 0;
    {
        std::jthread w([&] {
            std::uint64_t v = 1;
            while (finished.load(std::memory_order_acquire) < kReaders) {
                const auto until = Clock::now() + std::chrono::microseconds(20);
                while (Clock::now() < until) cpu_relax();
                writer(v++);
            }
        });
        {
            std::vector<std::jthread> rs;
            for (int i = 0; i < kReaders; ++i)
                rs.emplace_back([&, i] {
                    std::uint64_t b = 0;
                    reader(i, b);
                    bad.fetch_add(b);
                    finished.fetch_add(1, std::memory_order_release);
                });
        }
        const std::chrono::duration<double, std::nano> d = Clock::now() - t0;
        ns = d.count() / (kReaders * kReads);
    }
    broken = bad.load();
    return ns;
}

void read_path() {
    std::uint64_t broken = 0;
    auto report = [&](const char* name, double ns) {
        std::println("  {:<36} {:7.2f} ns per read   corrupted reads: {}", name, ns, broken);
    };
    std::println("read path, {} readers x {} reads, writer swapping concurrently:", kReaders, kReads);
    {
        std::mutex m;
        Config* cur = new Config(0);
        report("std::mutex", read_ns(
            [&](int, std::uint64_t& b) {
                for (int i = 0; i < kReads; ++i) {
                    std::scoped_lock lk(m);
                    if (cur->check != 3 * cur->version) ++b;
                }
            },
            [&](std::uint64_t v) {
                Config* old;
                {
                    std::scoped_lock lk(m);
                    old = std::exchange(cur, new Config(v));
                }
                delete old;
            }, broken));
        delete cur;
    }
    {
        std::shared_mutex m;
        Config* cur = new Config(0);
        report("std::shared_mutex", read_ns(
            [&](int, std::uint64_t& b) {
                for (int i = 0; i < kReads; ++i) {
                    std::shared_lock lk(m);
                    if (cur->check != 3 * cur->version) ++b;
                }
            },
            [&](std::uint64_t v) {
                Config* old;
                {
                    std::unique_lock lk(m);
                    old = std::exchange(cur, new Config(v));
                }
                delete old;
            }, broken));
        delete cur;
    }
#if defined(__cpp_lib_atomic_shared_ptr)
    {
        std::atomic<std::shared_ptr<const Config>> cur{std::make_shared<const Config>(std::uint64_t{0})};
        report("atomic<shared_ptr> (libstdc++)", read_ns(
            [&](int, std::uint64_t& b) {
                for (int i = 0; i < kReads; ++i) {
                    const auto c = cur.load(std::memory_order_acquire);
                    if (c->check != 3 * c->version) ++b;
                }
            },
            [&](std::uint64_t v) { cur.store(std::make_shared<const Config>(v), std::memory_order_release); }, broken));
    }
#else
    std::println("  {:<36} (not provided by libc++ 21)", "atomic<shared_ptr>");
#endif
    {
        g_cfg.store(new Config(0));
        report("hazard pointer, protect per read", read_ns(
            [&](int, std::uint64_t& b) {
                hp::hazard_pointer h = hp::make_hazard_pointer();
                for (int i = 0; i < kReads; ++i) {
                    Config* c = h.protect(g_cfg);
                    if (c->check != 3 * c->version) ++b;
                }
                h.reset_protection();
            },
            [&](std::uint64_t v) { g_cfg.exchange(new Config(v))->retire(); }, broken));
        g_cfg.exchange(nullptr)->retire();
        hp::drain();
    }
    {
        g_cfg.store(new Config(0));
        report("EBR, one guard per read", read_ns(
            [&](int, std::uint64_t& b) {
                for (int i = 0; i < kReads; ++i) {
                    ebr::guard g;
                    Config* c = g_cfg.load(std::memory_order_acquire);
                    if (c->check != 3 * c->version) ++b;
                }
            },
            [&](std::uint64_t v) { ebr::retire(g_cfg.exchange(new Config(v))); }, broken));
        ebr::retire(g_cfg.exchange(nullptr));
        ebr::quiesce();   // adopts the writer thread's orphaned limbo list and frees it
    }
    {
        g_cfg.store(new Config(0));
        std::vector<Config*> pending;
        report("QSBR (RCU): no stores per read", read_ns(
            [&](int id, std::uint64_t& b) {
                qsbr::Rec& rec = qsbr::g_recs[id];
                qsbr::online(rec);
                for (int i = 0; i < kReads; ++i) {
                    if ((i & 63) == 0) qsbr::quiescent(rec);   // between reads: holds no reference here
                    Config* c = g_cfg.load(std::memory_order_acquire);
                    if (c->check != 3 * c->version) ++b;
                }
                qsbr::offline(rec);
            },
            [&](std::uint64_t v) {
                pending.push_back(g_cfg.exchange(new Config(v)));
                if (pending.size() >= 64) {   // one grace period frees a whole batch
                    qsbr::synchronize();
                    for (Config* p : pending) delete p;
                    pending.clear();
                }
            }, broken));
        qsbr::synchronize();
        for (Config* p : pending) delete p;
        delete g_cfg.exchange(nullptr);
    }
}

int main() {
    stalled_reader();
    read_path();
}
```

Output (verified, GCC then Clang):

```text
hazard pointers: while the reader is stalled  9999 of 10000 retired versions freed; after it resumes 10000
epoch-based:     while the reader is stalled     0 of 10000 retired versions freed; after it resumes 10000
read path, 3 readers x 1000000 reads, writer swapping concurrently:
  std::mutex                             39.66 ns per read   corrupted reads: 0
  std::shared_mutex                     250.41 ns per read   corrupted reads: 0
  atomic<shared_ptr> (libstdc++)        118.64 ns per read   corrupted reads: 0
  hazard pointer, protect per read        1.90 ns per read   corrupted reads: 0
  EBR, one guard per read                19.59 ns per read   corrupted reads: 0
  QSBR (RCU): no stores per read          0.38 ns per read   corrupted reads: 0
hazard pointers: while the reader is stalled  9999 of 10000 retired versions freed; after it resumes 10000
epoch-based:     while the reader is stalled     0 of 10000 retired versions freed; after it resumes 10000
read path, 3 readers x 1000000 reads, writer swapping concurrently:
  std::mutex                             23.80 ns per read   corrupted reads: 0
  std::shared_mutex                      60.74 ns per read   corrupted reads: 0
  atomic<shared_ptr>                   (not provided by libc++ 21)
  hazard pointer, protect per read        2.10 ns per read   corrupted reads: 0
  EBR, one guard per read                 3.88 ns per read   corrupted reads: 0
  QSBR (RCU): no stores per read          0.33 ns per read   corrupted reads: 0
```

The three read paths, Clang 21 `-O3`, x86-64:

```asm
_Z7hp_readRN2hp14hazard_pointerE:  # hp_read(hp::hazard_pointer&)
	movq	g_cfg@GOTPCREL(%rip), %rcx
	movq	(%rcx), %rdx
.LBB6_1:
	movq	%rdx, %rax
	movq	(%rdi), %rdx
	movq	%rax, %rsi
	xchgq	%rsi, (%rdx)
	movq	(%rcx), %rdx
	cmpq	%rdx, %rax
	jne	.LBB6_1
	retq

_Z8ebr_readv:                      # ebr_read()
	pushq	%rax
	callq	_ZTHN3ebr7t_stateE@PLT               # TLS init function for ebr::t_state
	data16
	leaq	_ZN3ebr7t_stateE@TLSGD(%rip), %rdi    # ebr::t_state
	data16
	data16
	rex64
	callq	__tls_get_addr@PLT
	movq	%rax, %rdi
	movq	(%rax), %rax
	testq	%rax, %rax
	jne	.LBB7_2
	callq	_ZN3ebr11ThreadState14acquire_recordEv@PLT # ebr::ThreadState::acquire_record()
.LBB7_2:
	movq	_ZN3ebr7g_epochE@GOTPCREL(%rip), %rcx # ebr::g_epoch
	movq	(%rcx), %rdx
.LBB7_3:
	movq	%rdx, %rsi
	xchgq	%rsi, (%rax)
	movq	(%rcx), %rsi
	cmpq	%rdx, %rsi
	movq	%rsi, %rdx
	jne	.LBB7_3
	lock	orl	$0, -64(%rsp)
	movq	g_cfg@GOTPCREL(%rip), %rcx
	movq	(%rcx), %rcx
	movq	(%rcx), %rcx
	movq	$0, (%rax)
	movq	%rcx, %rax
	popq	%rcx
	retq

_Z9qsbr_readv:                     # qsbr_read()
	movq	g_cfg@GOTPCREL(%rip), %rax
	movq	(%rax), %rax
	movq	(%rax), %rax
	retq
```

AArch64:

```asm
_Z7hp_readRN2hp14hazard_pointerE:  // hp_read(hp::hazard_pointer&)
	adrp	x9, :got:g_cfg
	ldr	x9, [x9, :got_lo12:g_cfg]
	ldr	x10, [x9]
.LBB6_1:
	ldr	x11, [x0]
	mov	x8, x10
	stlr	x10, [x11]
	ldar	x10, [x9]
	cmp	x8, x10
	b.ne	.LBB6_1
	mov	x0, x8
	ret

_Z8ebr_readv:                      // ebr_read()
	str	x30, [sp, #-16]!
	bl	_ZTHN3ebr7t_stateE                      // TLS init function for ebr::t_state
	adrp	x0, :tlsdesc:_ZN3ebr7t_stateE         // ebr::t_state
	ldr	x1, [x0, :tlsdesc_lo12:_ZN3ebr7t_stateE] // ebr::t_state
	add	x0, x0, :tlsdesc_lo12:_ZN3ebr7t_stateE // ebr::t_state
	blr	x1
	mrs	x9, TPIDR_EL0
	ldr	x8, [x9, x0]
	cbnz	x8, .LBB7_2
	add	x0, x9, x0
	bl	_ZN3ebr11ThreadState14acquire_recordEv  // ebr::ThreadState::acquire_record()
	mov	x8, x0
.LBB7_2:
	adrp	x9, :got:_ZN3ebr7g_epochE             // ebr::g_epoch
	ldr	x9, [x9, :got_lo12:_ZN3ebr7g_epochE]   // ebr::g_epoch
	ldar	x10, [x9]
.LBB7_3:
	stlr	x10, [x8]
	ldar	x11, [x9]
	cmp	x11, x10
	mov	x10, x11
	b.ne	.LBB7_3
	adrp	x9, :got:g_cfg
	ldr	x9, [x9, :got_lo12:g_cfg]
	dmb	ish
	ldar	x9, [x9]
	ldr	x0, [x9]
	stlr	xzr, [x8]
	ldr	x30, [sp], #16
	ret

_Z9qsbr_readv:                     // qsbr_read()
	adrp	x8, :got:g_cfg
	ldr	x8, [x8, :got_lo12:g_cfg]
	ldar	x8, [x8]
	ldr	x0, [x8]
	ret
```

* **Part A is deterministic.** One reader stalls while the writer publishes and retires 10,000 versions. **Hazard
  pointers freed 9,999**: the stalled reader protects exactly one. **EBR freed 0**: the reader's announced epoch blocks
  every advance. Both free all 10,000 once it resumes. That is the whole trade-off in two lines: EBR's memory is
  unbounded under a stalled reader, while hazard pointers bound it by the number of slots.
* **Part B, read cost** (aggregate over 3 readers, two runs per compiler): QSBR 0.33–0.46 ns, because its read path is
  one acquire load (`movq`/`ldar`) with no stores; hazard pointers 1.8–2.1 ns, one `xchg` (`stlr` + `ldar` on ARM) plus
  a reload; EBR 3.9–19.6 ns, an announce loop, a fence and a release store per section, plus a TLS lookup that the
  general-dynamic model turns into a call; `std::mutex` 24–40 ns; `atomic<shared_ptr>` 109–119 ns, with every reader
  CASing the same lock bit and count; `shared_mutex` 61–250 ns. All variants: 0 corrupted reads.
* EBR is cheaper than hazard pointers **per pointer** when a section reads many pointers (a long traversal). Here each
  section reads one pointer, so its fixed cost dominates.
* **QSBR's price** is paid by writers and by the program's structure. Readers must report quiescent states (every 64
  reads here), a reader that stops reporting blocks `synchronize()` forever, and the writer batches 64 retired versions
  per grace period. It suits event loops and worker threads with natural "between requests" points; that is how Linux
  kernel RCU and liburcu's QSBR flavour work.

### 1.5 The C++26 APIs, and what exists today

| C++26 (P2530 / P2545) | This folder's sketch | Production today |
|---|---|---|
| `std::hazard_pointer_obj_base<T, D>`, `obj.retire(d)` | `hp::hazard_pointer_obj_base<T>`, `retire()` | folly `hazptr_obj_base` |
| `std::make_hazard_pointer()`, `hp.protect(src)`, `try_protect`, `reset_protection` | `hp::make_hazard_pointer()`, `protect`, `reset_protection` | folly `hazptr_holder` |
| `std::rcu_obj_base<T, D>`, `std::rcu_retire(p)` | `qsbr` batch + `synchronize()` in Listing 9.10 | liburcu `call_rcu`, folly `rcu_obj_base` |
| `std::rcu_domain`: `lock()`/`unlock()` (a read section), `std::rcu_synchronize()`, `std::rcu_barrier()` | `qsbr::online`/`quiescent`/`offline`, `qsbr::synchronize()` | liburcu `rcu_read_lock`, `synchronize_rcu`, `rcu_barrier` |
| (none: epochs are not standardized) | `ebr::guard`, `ebr::retire` | crossbeam-epoch (Rust), libcds |

Neither GCC 16.2's libstdc++ nor libc++ 21 provides `<hazard_pointer>` or `<rcu>` (probed: neither header exists). Note
that `std::rcu_domain` is a *read-section* API (`lock`/`unlock`), closer to memb-RCU than to the QSBR used here.

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| reclamation | hand-rolled (`std::atomic` + seq_cst for the SB handshake) | — | — | `atomic<shared_ptr>` (reference counting) | — | `<hazard_pointer>` (P2530), `<rcu>` (P2545) |
| deprecations | — | — | — | — | — | `memory_order::consume` deprecated (P3475): RCU readers use acquire |
| availability here | — | — | — | libstdc++ only for `atomic<shared_ptr>` | — | neither library ships the C++26 headers |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| freeing a node removed from a lock-free structure | `delete` right after the removing CAS | `retire()` through hazard pointers, EBR or RCU |
| hazard publication | release store + acquire re-load "to save a barrier" | seq_cst store + seq_cst re-load (or asymmetric fences) |
| long-running readers (requests that hold a snapshot for ms) | EBR (one slow reader pins all garbage) | hazard pointers (bounded), or RCU with snapshots copied out |
| read-mostly config at very high read rates | `atomic<shared_ptr>` (109–119 ns here) or `shared_mutex` | RCU/QSBR or hazard pointers (0.3–2 ns) |
| traversals touching many nodes per operation | hazard pointer per node (a barrier per hop) | EBR or RCU: one section per traversal |
| per-node reference counts | `node->refs.fetch_add(1)` after loading `node` (it may already be freed) | SMR, or split reference counts with DWCAS (Folder 07) |
| threads that exit with retired nodes | leak them | hand retire/limbo lists to the domain (orphans), as Listings 9.8–9.9 do |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| sporadic crash or garbage read in a lock-free structure | node freed while a reader still uses it | ASan under stress; SMR |
| memory grows without bound under load | EBR/RCU reader stalled (or never reporting quiescence) | count retired-but-not-freed objects; alert on it |
| use-after-free only on ARM or only rarely on x86 | hazard publication with release/acquire (SB) | review the orders; seq_cst |
| writer latency spikes | RCU grace periods waiting for slow readers | batch retirements; callback-based reclamation (`call_rcu` / `rcu_retire`) |
| hazard slots exhausted (`abort` in `make_hazard_pointer`) | more simultaneous hazard pointers than slots | size the domain; release pointers promptly |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "When can we free a node we removed?"</b></summary>

**Initial prompt.** "Our lock-free list's `remove` unlinks a node with a CAS. When can it be deleted?"

**L5 textbook answer.** "Right after the CAS succeeds: nobody can reach it anymore."

**Why L5 corrupts memory on ARM64.** Nobody *new* can reach it. Threads that loaded the pointer before the CAS can still
be dereferencing it, possibly for a long time if preempted. Deleting immediately is a use-after-free for them, and if the
allocator reuses the address, their pending CASes hit ABA (file 01). This happens on x86 and ARM64 alike.

**L7 principal defense.** "`retire()` instead of `delete`. Hazard pointers if readers can stall and memory must stay
bounded (Listing 9.10: a stalled reader pins 1 node). EBR or RCU if read sections are short and frequent and traversals
long. And I'd say which one and why, because they fail differently."
</details>

<details><summary><b>Chain 2 ⚡ "Why does protect() re-read the pointer?"</b></summary>

**Initial prompt.** "Hazard-pointer readers store the pointer into their slot. Why the loop that re-reads the source?"

**L5 textbook answer.** "In case another thread changed the pointer, so we use the latest value."

**Why L5 corrupts memory on ARM64.** It's about the window between loading `p` and publishing it. In that window a
writer can unlink `p`, scan the slots (finding no hazard, because ours isn't published yet), and free it. The re-read
after publishing detects this: if the source still holds `p`, then any unlink happens *after* our publication, and that
writer's scan will see our hazard. If it doesn't, we retry with the new value. Without the re-read, a successful
publication can protect an already-freed node.

**L7 principal defense.** "Publish, then validate, and only the validated pointer is safe. It's the same
'optimistic read, then confirm' structure as the CAS-validated reads in file 03."
</details>

<details><summary><b>Chain 3 🔥 "Use release/acquire for the hazard publication"</b></summary>

**Initial prompt.** "`protect()` does a seq_cst store per read (an `XCHG`, about 5 ns). Release store + acquire load
is free on x86. Can we use that?"

**L5 textbook answer.** "Yes: release makes the hazard visible before the re-load, and acquire on the re-load orders
the rest."

**Why L5 corrupts memory on ARM64.** Release orders *earlier* operations before the store. Nothing stops the *later*
re-load from completing before the hazard store is visible: store→load reordering, the SB outcome. Folder 07 observed it
in 0.4–3% of runs **on x86**. The reclaimer has the mirror-image pattern (unlink, then read hazards). With SB both
sides can miss each other: the reader's re-load sees the old pointer, and the reclaimer's scan sees no hazard, so it frees
the node the reader is about to use. On RCpc ARM cores (`STLR` followed by `LDAPR`) the same reordering is allowed.

**L7 principal defense.** "seq_cst on both sides (Listing 9.8: `xchg` / `stlr` + `ldar`), or asymmetric fences: the
reader uses only a compiler barrier, and the rare scanner forces a barrier on every core (`membarrier` on Linux;
Windows offers `FlushProcessWriteBuffers`). That's how folly makes protection nearly free on Linux; off Linux, folly
falls back to ordinary fences on both sides (Folder 12, Listing 12.5 reads its source and measures the trade)."
</details>

<details><summary><b>Chain 4 🧊 "EBR or hazard pointers?"</b></summary>

**Initial prompt.** "Readers of our routing table sometimes hold a snapshot for the whole request, up to 50 ms. Which
reclamation scheme?"

**L5 textbook answer.** "EBR: it's faster and simpler than hazard pointers."

**Why L5 breaks.** EBR's cost model assumes short critical sections. One reader inside a section blocks every epoch
advance, so nothing retired during those 50 ms, by *any* thread, can be freed. Listing 9.10 part A: with one stalled
reader, EBR freed **0 of 10,000** retired versions; hazard pointers freed 9,999. Under steady updates that's unbounded
growth for the length of the slowest request.

**L7 principal defense.** "Hazard pointers for long-held references (bounded memory), or copy the needed data out of
the snapshot and leave the critical section quickly. EBR or RCU where read sections are short and traversals touch many
nodes, because EBR's per-section cost (3.9–19.6 ns here) is amortized across all the pointers in the section."
</details>

<details><summary><b>Chain 5 ⚡ "RCU reads are free, so use RCU everywhere"</b></summary>

**Initial prompt.** "QSBR reads cost 0.4 ns. Why not use it for everything?"

**L5 textbook answer.** "Yes, zero-cost reads with no downside."

**Why L5 breaks.** The cost moves to writers and to program structure. Readers must report quiescent states. A thread
that blocks, sleeps or loops without reporting holds up every `synchronize()`, so writers stall and garbage accumulates.
Grace periods take as long as the slowest reader's report interval. Writers must batch (64 versions per grace period in
Listing 9.10) or use callbacks (`call_rcu`, `std::rcu_retire`). And QSBR needs every reading thread registered
(`online`/`offline`).

**L7 principal defense.** "QSBR for event loops and pooled workers with natural quiescent points between tasks;
memb-style RCU (read-side `lock`/`unlock`, the shape of `std::rcu_domain`) for general threads; hazard pointers where
readers may stall. And it only fits read-mostly data where writers tolerate millisecond publication latency."
</details>

<details><summary><b>Chain 6 🔥 "atomic<shared_ptr> is the standard answer for snapshots"</b></summary>

**Initial prompt.** "Our feature-flag snapshot is read 10M times per second across cores via `atomic<shared_ptr>`.
Profiles show it hot. Why, and what instead?"

**L5 textbook answer.** "shared_ptr is optimized; the profile must be misleading."

**Why L5 breaks.** Every `load()` sets a lock bit with a CAS, bumps the reference count, and clears the bit (Folder 07,
§1.6), and the destructor of the copy decrements the count. All readers write the same two cache lines. Listing 9.10:
109–119 ns per read aggregated over 3 readers, against 1.8–2.1 ns for a hazard pointer and 0.33–0.46 ns for QSBR.

**L7 principal defense.** "Keep the `shared_ptr` as the ownership mechanism for writers, but don't touch its count on
every read. Readers use RCU or hazard pointers to the current snapshot, or a thread-local cached `shared_ptr` refreshed
only when a version counter changes (one relaxed load per read)."
</details>

<details><summary><b>Chain 7 🧊 "Can we use std::hazard_pointer today?"</b></summary>

**Initial prompt.** "C++26 has `<hazard_pointer>` and `<rcu>`. Can we just use them?"

**L5 textbook answer.** "Yes, compile with `-std=c++26`."

**Why L5 breaks.** On this toolchain neither header exists: GCC 16.2's libstdc++ and libc++ 21 ship neither
(probed). Standardized and implemented are different milestones. P2530 came from folly's `hazptr` and P2545 from
industrial RCU, and those libraries are what production uses today.

**L7 principal defense.** "Use folly `hazptr` or liburcu now, behind a thin wrapper with the standard's names and
shapes (as Listings 9.8–9.10 do), and switch when the standard libraries ship them. Gate on
`__cpp_lib_hazard_pointer` / `__cpp_lib_rcu`."
</details>

<details><summary><b>Chain 8 ⚡ "Give each node a reference count instead"</b></summary>

**Initial prompt.** "Simplest SMR: every node has an `atomic<int> refs`. Readers increment it before use and
decrement after; the last one deletes. Problem?"

**L5 textbook answer.** "That's how `shared_ptr` works, so it's correct."

**Why L5 corrupts memory on ARM64.** The count lives *inside the node*. A reader loads `p = head`, and before it can
`p->refs.fetch_add(1)` the writer unlinks `p`, sees `refs == 0`, and frees it. The reader then increments a count in
freed memory, a use-after-free on any architecture. `shared_ptr` avoids it only because the pointer and the control
block are copied *from an owner that keeps the count above zero*; the shared location itself still needs atomic
protection, which is exactly the lock bit `atomic<shared_ptr>` takes.

**L7 principal defense.** "Reference counts reached through a shared mutable pointer need one of: SMR around the
increment, split reference counts with DWCAS (an external count next to the pointer, updated in the same atomic step),
or a lock. That's why lock-free `atomic_shared_ptr` implementations use split counts (Folder 07, file 03)."
</details>

---

## 6. Invariants checklist

- [ ] No node removed from a concurrent structure is freed before an SMR scheme says so.
- [ ] Hazard publication and the reclaimer's scan use seq_cst (or asymmetric fences), never release/acquire alone.
- [ ] The scheme matches reader behaviour: hazard pointers for long-held references, EBR/RCU for short sections.
- [ ] Retired-but-not-freed memory is counted and monitored.
- [ ] Every reading thread is registered (QSBR) or holds sections only briefly (EBR).
- [ ] Thread exit hands remaining retired nodes to the domain.
- [ ] Code is ready to switch to `<hazard_pointer>` / `<rcu>` behind feature macros.

## 7. References

- M. Michael, "Hazard Pointers: Safe Memory Reclamation for Lock-Free Objects", IEEE TPDS 15(6), 2004, DOI 10.1109/TPDS.2004.8
- K. Fraser, "Practical Lock-Freedom" (epoch-based reclamation), Cambridge TR 579, 2004: <https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-579.pdf>
- M. Desnoyers et al., "User-Level Implementations of Read-Copy Update", IEEE TPDS 2012: <https://www.efficios.com/pub/rcu/urcu-main.pdf>
- P2530R3 (hazard pointers for C++26): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2530r3.pdf>
- P2545R4 (read-copy update for C++26): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2545r4.pdf>
- folly hazard pointers: <https://github.com/facebook/folly/blob/main/folly/synchronization/Hazptr.h>
- Linux kernel, "What is RCU?": <https://www.kernel.org/doc/html/latest/RCU/whatisRCU.html>
- liburcu: <https://liburcu.org/>
