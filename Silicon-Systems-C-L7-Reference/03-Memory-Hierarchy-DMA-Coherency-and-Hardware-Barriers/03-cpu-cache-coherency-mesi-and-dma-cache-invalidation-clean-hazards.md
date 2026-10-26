# 03 · CPU Cache Coherency (MESI/MOESI) and DMA Cache Clean/Invalidate Hazards

> **Folder:** `03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/` · **File 3 of 3**
> **Anchors:**
> - U. Drepper, *What Every Programmer Should Know About Memory* §3.3 (multi-processor coherency), §6.4 (false sharing).
> - Sorin, Hill & Wood, *A Primer on Memory Consistency and Cache Coherence* (2nd ed., 2020).
> - Arm AMBA ACE and CHI specifications (IHI 0022, IHI 0050); Arm ARM DDI 0487 D7 (*Point of Coherency / Unification*, `DC`/`IC` operations).
> - ARMv7-M ARM B2.2.7 (cache maintenance operations); Cortex-M7 TRM (L1 caches, 32-byte lines).
> - Linux `Documentation/core-api/dma-api.rst`, `dma-api-howto.rst`; `arch/arm64/mm/cache.S`, `dma-mapping.c`.
>
> **Verification:**
> - A deterministic write-back cache + non-coherent DMA **simulator** reproduces every hazard in this file (run output inserted verbatim).
> - The Cortex-M7 (SCB `DCCMVAC`/`DCIMVAC`/`DCCIMVAC`) and AArch64 (`DC CVAC`/`IVAC`/`CIVAC`) maintenance routines were compiled warning-free, and their codegen is inserted verbatim.
> - False-sharing cost was measured on the author's x86-64 laptop (one run).

---

## 0. The thesis

Hardware cache coherency (MESI and its relatives) makes caches invisible **between CPU cores**. It does nothing for a **non-coherent bus master**: a DMA engine, a GPU on a non-coherent port, an FPGA fabric, or a second cluster outside the coherency domain. Those see only DRAM or SRAM. The CPU's caches are, for them, a write-back buffer full of data they can't see, and a read cache full of data they can overwrite underneath. **Cache maintenance is the software implementation of coherency for those masters.** Every rule in it follows from one fact: **maintenance operates on whole cache lines.**

---

## 1. First-Principles Hardware Mechanics

### 1.1 MESI, MOESI, and what a write costs

| State | Meaning | Dirty? | Other copies? |
|---|---|---|---|
| **M**odified | Only this cache has it; differs from memory | yes | none |
| **O**wned (MOESI) | Dirty, but shared. This cache must supply data and eventually write back | yes | yes (in S) |
| **E**xclusive | Only this cache has it; equals memory | no | none |
| **S**hared | Clean copy; others may have it | no | maybe |
| **I**nvalid | Not present | n/a | n/a |
| **F**orward (MESIF, Intel) | The designated shared responder | no | yes |

A **write** to a line in S or I requires a **Read-For-Ownership (RFO)** or an upgrade. The interconnect invalidates every other copy (snoop broadcast, or a directory/snoop-filter lookup), and the writer moves to M. Two cores writing *different variables in the same line* therefore pay that invalidation on every write. That is **false sharing** (measured, §1.6).

ARM interconnect vocabulary:

- **ACE** (AXI Coherency Extensions): full-coherent masters, i.e. CPU clusters.
- **ACE-Lite**: *I/O-coherent* masters. They snoop CPU caches on reads and invalidate on writes, but have no cache of their own. A DMA engine on an ACE-Lite port *needs no software maintenance*.
- **CHI**: the packet-based protocol of CMN mesh interconnects (Neoverse).
- Interconnects: **CCI-400/500/550** (crossbars), **CMN-600/700** (meshes with distributed snoop filters, the home nodes). The **DSU** (DynamIQ Shared Unit) keeps a cluster coherent.

### 1.2 Points of coherency and unification

- **PoC (Point of Coherency):** the level where *all* observers (all CPUs **and** all DMA masters) are guaranteed to see the same copy, typically DRAM or the system-level cache. **DMA maintenance targets the PoC**: `DC CVAC`, `DC IVAC`, `DC CIVAC` on AArch64; `DCCMVAC`/`DCIMVAC`/`DCCIMVAC` on Cortex-M7.
- **PoU (Point of Unification):** the level where a core's **instruction and data** paths see the same copy. **Self-modifying-code maintenance targets the PoU** (`DC CVAU`, `IC IVAU`; File 02 §2.3).

### 1.3 The DMA hazards, as a state machine on one cache line

The simulator (§2.1) models a direct-mapped, write-back, write-allocate L1 with **32-byte lines** (Cortex-M7), a non-coherent DMA master that reads and writes RAM directly, and maintenance-by-range that rounds *out* to whole lines, exactly like the hardware.

**Simulator output (verified, deterministic):**

```text
TX, no clean            : DMA sees  0/64 new bytes
TX, clean before DMA    : DMA sees 64/64 new bytes
RX, no invalidate       : CPU sees  0/64 new bytes
RX, invalidate after    : CPU sees 64/64 new bytes
RX, shared line, evict  : CPU sees 40/64 new bytes (first 24 lost to the write-back)
RX, shared line, inval  : CPU sees 64/64 new bytes, neighbour var = 0x00 (wrote 0x77)
RX, aligned, inv+inv    : CPU sees 64/64 new bytes, neighbour var = 0x77
```

| Case | Sequence | Result | Lesson |
|---|---|---|---|
| 1 | CPU writes TX buffer (lines become **M**), DMA reads RAM | DMA sees **0 / 64** new bytes | The CPU's writes are in the cache, not in RAM |
| 2 | … + **clean** (write back M lines) before starting the DMA | 64 / 64 | **TX rule: clean, then `DSB`, then start the DMA** |
| 3 | CPU had read the RX buffer earlier (lines **E/S**), DMA writes RAM, CPU reads | CPU sees **0 / 64** | The CPU reads its stale cached copy |
| 4 | … + **invalidate** after completion | 64 / 64 | **RX rule: invalidate before the CPU reads** |
| 5 | RX buffer starts mid-line (byte 40); a CPU variable lives in bytes 32–39 of the *same line*; the CPU writes it during the DMA; the line is later evicted | **40 / 64**: the first 24 DMA bytes are **overwritten with stale data** by the write-back | **The neighbor-variable disaster.** The write-back is whole-line, so it carries the stale copy of bytes 40–63 back over the DMA data |
| 6 | Same layout; the driver "fixes" it by invalidating the range (rounded out to the line) before reading | DMA data OK, but the **neighbor variable is destroyed**: it reads `0x00`, though `0x77` was written | Invalidate discards dirty data, including the neighbor's. **Neither clean nor invalidate can make a shared line safe** |
| 7 | Line-aligned, line-padded buffer; **invalidate before** starting (no dirty victim can be evicted onto the buffer), a speculative or prefetch refill *during* the DMA (modeled by a CPU read), **invalidate after** completion | 64 / 64, and the neighbor intact (`0x77`) | **The correct RX protocol.** The after-invalidate is mandatory on cores that can speculatively refill lines during the transfer (Cortex-A, Cortex-M7) |

### 1.4 The rules that follow

1. **Ownership is per cache line, not per byte.** A DMA buffer must **start and end on a line boundary**: the CWG on AArch64, 32 B on Cortex-M7. **No CPU-written object may share any of its lines** (Folder 01 File 02 §1.8, and its `dma_range_is_line_exact`).
2. **TX (memory → device):** CPU writes → **clean** (`DC CVAC` / `DCCMVAC`) → `DSB` → doorbell.
3. **RX (device → memory):**
   - **before** starting: **invalidate** (or clean+invalidate, if the buffer might be dirty);
   - start the DMA, wait for completion (status read or interrupt);
   - **after** completion: **invalidate** again;
   - `DSB`, then read.
4. **Invalidate-only must never be applied to a partial line** (case 6). The verified `dcache_invalidate_range()` *refuses* non-line-exact ranges. For a partial line, use clean+invalidate, which never loses data, and fix the layout.
5. **Bidirectional buffers:** clean before (CPU → device data), invalidate after (device → CPU data). Or clean+invalidate for both.
6. **Alternatives that need no maintenance:**
   - map the buffers **Normal Non-cacheable** (MPU on Cortex-M, Folder 02 File 03: `RASR 0x110C0021`; page attributes `MT_NORMAL_NC` on AArch64);
   - use **TCM** where the DMA can reach it;
   - or put the device behind an **I/O-coherent** (ACE-Lite / SMMU-coherent) port.
   
   Non-cacheable costs CPU bandwidth on the buffer. Cached plus maintenance costs cycles per transfer. Choose per buffer size and access pattern.

### 1.5 The Linux DMA API is this file in code

| API | What it does on a non-coherent arm64 device |
|---|---|
| `dma_alloc_coherent()` | Returns memory mapped **Normal Non-cacheable** (or coherent via the SMMU/ACE-Lite): no maintenance ever needed |
| `dma_map_single(dev, p, n, DMA_TO_DEVICE)` | **Clean** to PoC (`dcache_clean_poc`) |
| `dma_map_single(..., DMA_FROM_DEVICE)` | **Invalidate** (or clean+invalidate) before the transfer |
| `dma_unmap_single(..., DMA_FROM_DEVICE)` / `dma_sync_single_for_cpu()` | **Invalidate again** after the transfer (the speculative-refill rule, case 7) |
| `dma_sync_single_for_device()` | Re-clean for re-use |
| `ARCH_DMA_MINALIGN` (128 on arm64) | Guarantees `kmalloc` buffers don't share lines with other allocations. Since Linux 6.5, small unaligned `kmalloc` buffers are **bounced** through swiotlb for non-coherent devices |
| `CONFIG_DMA_API_DEBUG` | Catches CPU access to mapped buffers, missing unmaps, and direction misuse at run time |

### 1.6 False sharing, measured

From the File 01 harness, the same counters in one line vs padded to separate 64-byte lines (one run, x86-64):

```text
2 threads x 1,000,000 increments: volatile=1024996 (lost 975004)  atomic=2000000
SB no fence (relaxed)     r0,r1 = 0,0:  94243  0,1:  19153  1,0:  83110  1,1:   3494
SB with seq_cst fence     r0,r1 = 0,0:      0  0,1:  49329  1,0:  43236  1,1: 107435
MP no fence (relaxed)     flag,data = 0,0:  75522  0,1:  54449  1,0:      0  1,1:  70029
false sharing, 2 x 20000000 increments: same line 37.4 ms, separate lines 9.6 ms
```

The last line: **37.4 ms vs 9.6 ms** for the same 2 × 20,000,000 increments. That's 3.9× from MESI line ping-pong alone, with no logical sharing. Per-core counters, ring indices, locks and per-CPU statistics must each own a line (`alignas(64)`, or 128 on Apple and x86 adjacent-line prefetch: Folder 01 File 02).

---

## 2. Production Blueprints

### 2.1 The simulator (also the executable spec of the rules)

```c
/* dma_cache_sim.c - deterministic model of a write-back, write-allocate L1
 * D-cache (32-byte lines, like Cortex-M7) sharing RAM with a NON-coherent DMA
 * master. DMA reads/writes RAM directly; the CPU sees RAM only through the
 * cache. Reproduces every DMA coherency hazard and its fix. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define LINE   32u
#define NLINES 8u                       /* direct-mapped, 256 B: easy to force evictions */
#define RAM_SZ 1024u

static uint8_t ram[RAM_SZ];
static struct { bool valid, dirty; uint32_t tag; uint8_t data[LINE]; } cache[NLINES];

static uint32_t line_base(uint32_t a) { return a & ~(LINE - 1u); }
static uint32_t idx_of(uint32_t a)    { return (a / LINE) % NLINES; }

static void writeback(uint32_t i)
{
    if (cache[i].valid && cache[i].dirty) {
        memcpy(&ram[cache[i].tag], cache[i].data, LINE);   /* the WHOLE line goes back */
        cache[i].dirty = false;
    }
}

static uint32_t lookup(uint32_t a)    /* returns line index, filling on miss */
{
    uint32_t i = idx_of(a);
    if (!cache[i].valid || cache[i].tag != line_base(a)) {
        writeback(i);                                     /* eviction of a dirty victim */
        memcpy(cache[i].data, &ram[line_base(a)], LINE);
        cache[i].tag = line_base(a);
        cache[i].valid = true;
        cache[i].dirty = false;
    }
    return i;
}

static void    cpu_write(uint32_t a, uint8_t v) { uint32_t i = lookup(a); cache[i].data[a % LINE] = v; cache[i].dirty = true; }
static uint8_t cpu_read(uint32_t a)             { uint32_t i = lookup(a); return cache[i].data[a % LINE]; }
static void    dma_write(uint32_t a, uint8_t v) { ram[a] = v; }
static uint8_t dma_read(uint32_t a)             { return ram[a]; }

/* Maintenance by address range, rounded OUT to whole lines (like the hardware). */
static void dc_clean(uint32_t a, uint32_t n)
{
    for (uint32_t l = line_base(a); l < a + n; l += LINE) {
        uint32_t i = idx_of(l);
        if (cache[i].valid && cache[i].tag == l) { writeback(i); }
    }
}
static void dc_invalidate(uint32_t a, uint32_t n)
{
    for (uint32_t l = line_base(a); l < a + n; l += LINE) {
        uint32_t i = idx_of(l);
        if (cache[i].valid && cache[i].tag == l) { cache[i].valid = false; } /* dirty data DISCARDED */
    }
}
static void evict_all(void) { for (uint32_t i = 0; i < NLINES; i++) { writeback(i); cache[i].valid = false; } }
static void reset(void)     { memset(ram, 0, sizeof ram); memset(cache, 0, sizeof cache); }

static int count_bytes(uint32_t a, uint32_t n, uint8_t v, bool via_cpu)
{
    int c = 0;
    for (uint32_t k = 0; k < n; k++) { c += ((via_cpu ? cpu_read(a + k) : dma_read(a + k)) == v); }
    return c;
}

int main(void)
{
    const uint32_t buf = 64u, n = 64u;            /* line-aligned 64-byte DMA buffer */

    /* 1. TX without clean: CPU fills the buffer (dirty in cache), DMA reads RAM. */
    reset();
    for (uint32_t k = 0; k < n; k++) { cpu_write(buf + k, 0xC3u); }
    printf("TX, no clean            : DMA sees %2d/64 new bytes\n", count_bytes(buf, n, 0xC3u, false));

    /* 2. TX with clean (+DSB on real HW) before starting the DMA. */
    reset();
    for (uint32_t k = 0; k < n; k++) { cpu_write(buf + k, 0xC3u); }
    dc_clean(buf, n);
    printf("TX, clean before DMA    : DMA sees %2d/64 new bytes\n", count_bytes(buf, n, 0xC3u, false));

    /* 3. RX without invalidate: CPU had read the buffer earlier (lines cached). */
    reset();
    (void)count_bytes(buf, n, 0u, true);                     /* lines now cached, clean */
    for (uint32_t k = 0; k < n; k++) { dma_write(buf + k, 0x5Au); }
    printf("RX, no invalidate       : CPU sees %2d/64 new bytes\n", count_bytes(buf, n, 0x5Au, true));

    /* 4. RX with invalidate after completion. */
    reset();
    (void)count_bytes(buf, n, 0u, true);
    for (uint32_t k = 0; k < n; k++) { dma_write(buf + k, 0x5Au); }
    dc_invalidate(buf, n);
    printf("RX, invalidate after    : CPU sees %2d/64 new bytes\n", count_bytes(buf, n, 0x5Au, true));

    /* 5. RX buffer NOT line-aligned: a CPU variable shares its first line and is
     *    written while the DMA is in flight; the dirty line is later evicted. */
    reset();
    const uint32_t rx = 40u, var = 32u;                      /* var in [32,40), buffer [40,104) */
    (void)count_bytes(rx, n, 0u, true);
    for (uint32_t k = 0; k < n; k++) { dma_write(rx + k, 0x5Au); }   /* DMA lands in RAM   */
    cpu_write(var, 0x77u);                                   /* neighbour write: line 32 dirty */
    evict_all();                                             /* any later eviction / clean ...  */
    dc_invalidate(rx, n);
    printf("RX, shared line, evict  : CPU sees %2d/64 new bytes (first %u lost to the write-back)\n",
           count_bytes(rx, n, 0x5Au, true), (unsigned)(LINE - (rx - var)));

    /* 6. Same layout, driver "fixes" it with invalidate before reading: the
     *    neighbour's dirty update is DISCARDED instead. */
    reset();
    (void)count_bytes(rx, n, 0u, true);
    cpu_write(var, 0x77u);
    for (uint32_t k = 0; k < n; k++) { dma_write(rx + k, 0x5Au); }
    dc_invalidate(rx, n);                                    /* rounds out: kills var's line */
    printf("RX, shared line, inval  : CPU sees %2d/64 new bytes, neighbour var = 0x%02X (wrote 0x77)\n",
           count_bytes(rx, n, 0x5Au, true), (unsigned)cpu_read(var));

    /* 7. Correct: line-aligned, line-padded buffer; clean+invalidate (or
     *    invalidate) BEFORE starting, invalidate AFTER completion. */
    reset();
    (void)count_bytes(buf, n, 0u, true);
    cpu_write(var, 0x77u);                                   /* var lives in its own line */
    dc_invalidate(buf, n);                                   /* before: no dirty lines can be evicted onto the buffer */
    for (uint32_t k = 0; k < n; k++) { dma_write(buf + k, 0x5Au); }
    (void)cpu_read(buf + 8u);                                /* a speculative/prefetch refill DURING the DMA ... */
    dc_invalidate(buf, n);                                   /* ... is why the "after" invalidate is mandatory */
    printf("RX, aligned, inv+inv    : CPU sees %2d/64 new bytes, neighbour var = 0x%02X\n",
           count_bytes(buf, n, 0x5Au, true), (unsigned)cpu_read(var));
    return 0;
}
```

Built natively with `-std=c11 -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Werror`: zero diagnostics. The output is in §1.3.

### 2.2 The Subtle Buggy Way: the "cache-aware" driver that still corrupts

```c
/* eth_rx_bad.c - looks careful, uses the CMSIS-style calls, and corrupts data. */
#include <stdint.h>

extern void SCB_InvalidateDCache_by_Addr(volatile void *addr, int32_t size);
extern void SCB_CleanDCache_by_Addr(volatile void *addr, int32_t size);
extern void dma_start(void *buf, uint32_t n);
extern void dma_wait(void);

typedef struct {
    uint32_t rx_count;                 /* CPU statistics ...                       */
    uint8_t  rx_buf[1522];             /* ... sharing a cache line with the buffer */
    uint32_t rx_errors;                /* ... and the trailing line too            */
} eth_ctx_t;

static eth_ctx_t g_eth;                /* 4-byte aligned, 1530 bytes: no line rule */

uint32_t eth_receive(void);
uint32_t eth_receive(void)
{
    dma_start(g_eth.rx_buf, sizeof g_eth.rx_buf);   /* BUG 1: no invalidate BEFORE */
    g_eth.rx_count++;                               /* BUG 2: dirties line 0 during DMA */
    dma_wait();
    SCB_InvalidateDCache_by_Addr(g_eth.rx_buf, (int32_t)sizeof g_eth.rx_buf);
                                                    /* BUG 3: rounds out: discards rx_count's
                                                     *        and rx_errors' dirty updates */
    return g_eth.rx_buf[0];
}
```

The bugs map onto the simulator's cases:
- **Bug 1:** a dirty line, from an earlier `rx_count` update, can be evicted *onto* the incoming data during the transfer (case 5).
- **Bug 2:** writing `rx_count` during the DMA re-dirties the shared first line (case 5).
- **Bug 3:** the rounded-out invalidate destroys `rx_count`'s and `rx_errors`' updates (case 6: the counters lose increments "randomly"). The buffer's last line also holds `rx_errors`, so the trailing edge has the same problem. The size, 1522, isn't a multiple of 32.

### 2.3 The Silicon-Hardened Production Way: `dcache.h` + a line-exact buffer layout

`dcache.h` (Cortex-M7 and AArch64):

```c
/* dcache.h - D-cache maintenance by address for non-coherent DMA.
 * Cortex-M7: SCB cache-maintenance registers (ARMv7-M ARM B2.2.7, CMSIS-Core).
 * AArch64:   DC CVAC / DC IVAC / DC CIVAC to the Point of Coherency.
 * Contract: invalidate-only operations REQUIRE line-exact ranges (File 02 of
 * Folder 01, dma_range_is_line_exact): rounding them out would discard
 * neighbouring dirty data (see dma_cache_sim.c, case 6). */
#ifndef DCACHE_H
#define DCACHE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__ARM_ARCH_7EM__) || defined(__ARM_ARCH_8M_MAIN__) || defined(__ARM_ARCH_8_1M_MAIN__)
#define DCACHE_LINE 32u
#define SCB_DCIMVAC  (*(volatile uint32_t *)0xE000EF5Cu)   /* invalidate by MVA to PoC  */
#define SCB_DCCMVAC  (*(volatile uint32_t *)0xE000EF68u)   /* clean by MVA to PoC       */
#define SCB_DCCIMVAC (*(volatile uint32_t *)0xE000EF70u)   /* clean+invalidate to PoC   */
#define DC_OP(reg, a) ((reg) = (uint32_t)(a))
#define DC_BARRIER()  __asm__ volatile("dsb sy" : : : "memory")
#elif defined(__aarch64__)
#define DCACHE_LINE 64u   /* production code reads CTR_EL0.DminLine at boot and asserts CWG */
#define DC_OP_CVAC(a)  __asm__ volatile("dc cvac, %0"  : : "r"(a) : "memory")
#define DC_OP_IVAC(a)  __asm__ volatile("dc ivac, %0"  : : "r"(a) : "memory")
#define DC_OP_CIVAC(a) __asm__ volatile("dc civac, %0" : : "r"(a) : "memory")
#define DC_BARRIER()   __asm__ volatile("dsb sy" : : : "memory")
#else
#error "unsupported architecture"
#endif

static inline bool dcache_range_exact(const void *p, size_t n)
{
    return (n != 0u) && (((uintptr_t)p % DCACHE_LINE) == 0u) && ((n % DCACHE_LINE) == 0u);
}

/* TX: make CPU writes visible to the DMA master (write back dirty lines). */
static inline void dcache_clean_range(const void *p, size_t n)
{
    uintptr_t a = (uintptr_t)p & ~(uintptr_t)(DCACHE_LINE - 1u);
    uintptr_t end = (uintptr_t)p + n;
    DC_BARRIER();                              /* prior stores issued before the clean */
    for (; a < end; a += DCACHE_LINE) {
#if defined(__aarch64__)
        DC_OP_CVAC(a);
#else
        DC_OP(SCB_DCCMVAC, a);
#endif
    }
    DC_BARRIER();                              /* cleans complete before DMA is kicked */
}

/* RX: discard stale lines so the CPU re-reads what the DMA wrote. Returns
 * false (and does nothing) for a range that is not line-exact. */
static inline bool dcache_invalidate_range(void *p, size_t n)
{
    if (!dcache_range_exact(p, n)) {
        return false;
    }
    uintptr_t a = (uintptr_t)p;
    uintptr_t end = a + n;
    DC_BARRIER();
    for (; a < end; a += DCACHE_LINE) {
#if defined(__aarch64__)
        DC_OP_IVAC(a);
#else
        DC_OP(SCB_DCIMVAC, a);
#endif
    }
    DC_BARRIER();
    return true;
}

/* Bidirectional buffers / safe default for partial lines (never discards data). */
static inline void dcache_clean_invalidate_range(const void *p, size_t n)
{
    uintptr_t a = (uintptr_t)p & ~(uintptr_t)(DCACHE_LINE - 1u);
    uintptr_t end = (uintptr_t)p + n;
    DC_BARRIER();
    for (; a < end; a += DCACHE_LINE) {
#if defined(__aarch64__)
        DC_OP_CIVAC(a);
#else
        DC_OP(SCB_DCCIMVAC, a);
#endif
    }
    DC_BARRIER();
}

#endif /* DCACHE_H */
```

A driver using it:

```c
/* dma_use.c - the two DMA directions, as a driver writes them. */
#include <stdalign.h>
#include "dcache.h"

#define BUF_BYTES 1536u
static alignas(DCACHE_LINE) uint8_t tx_buf[BUF_BYTES];
static alignas(DCACHE_LINE) uint8_t rx_buf[BUF_BYTES];
extern void dma_start(const void *src_or_dst, size_t n, int dir);
extern void dma_wait(void);

void dma_send(size_t n);
void dma_send(size_t n)
{
    tx_buf[0] = 0xA5u;                         /* CPU produced the payload        */
    dcache_clean_range(tx_buf, n);             /* 1. write back dirty lines       */
    dma_start(tx_buf, n, 0);                   /* 2. MMIO doorbell (Device memory) */
}

int dma_receive(size_t n);
int dma_receive(size_t n)
{
    if ((n > BUF_BYTES) || !dcache_invalidate_range(rx_buf, n)) {  /* before: no dirty victims */
        return -1;                                                 /* n must be line-exact    */
    }
    dma_start(rx_buf, n, 1);
    dma_wait();                                          /* completion via status/IRQ */
    (void)dcache_invalidate_range(rx_buf, n);            /* after: drop speculative refills */
    return rx_buf[0];
}
```

**Build evidence (verified):** zero diagnostics with the full warning set (`-std=c11`) on Cortex-M7, Cortex-M33 and AArch64 (`aarch64-none-elf`).

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
dma_send:
	movw	r1, :lower16:tx_buf
	mov	r12, r0
	movt	r1, :upper16:tx_buf
	movs	r0, #165
	strb	r0, [r1]
	add.w	r0, r12, r1
	dsb	sy
	cmp	r0, r1
	bls	.LBB0_6
	movw	r3, :lower16:tx_buf
	movw	r2, #61288
	movt	r3, :upper16:tx_buf
	movt	r2, #57344
.LBB0_2:
	add.w	r1, r3, #32
	str	r3, [r2]
	cmp	r1, r0
	bhs	.LBB0_6
	add.w	r3, r1, #32
	str	r1, [r2]
	cmp	r3, r0
	bhs	.LBB0_6
	add.w	r1, r3, #32
	str	r3, [r2]
	cmp	r1, r0
	bhs	.LBB0_6
	add.w	r3, r1, #32
	str	r1, [r2]
	cmp	r3, r0
	blo	.LBB0_2
.LBB0_6:
	movw	r0, :lower16:tx_buf
	dsb	sy
	movt	r0, :upper16:tx_buf
	movs	r2, #0
	mov	r1, r12
	b	dma_start
dma_receive:
	cmp.w	r0, #1536
	bls	.LBB1_2
	mov.w	r0, #-1
	bx	lr
.LBB1_2:
	mov	r1, r0
	cmp	r0, #0
	mov.w	r0, #-1
	beq	.LBB1_17
	ands	r2, r1, #31
	it	ne
	bxne	lr
.LBB1_4:
	push	{r4, r5, r6, r7, lr}
	sub	sp, #4
	movw	r5, :lower16:rx_buf
	dsb	sy
	movt	r5, :upper16:rx_buf
	adds	r6, r1, r5
	cmp	r6, r5
	bls	.LBB1_15
	movw	r0, :lower16:rx_buf
	movw	r7, #61276
	movt	r0, :upper16:rx_buf
	movt	r7, #57344
.LBB1_6:
	add.w	r2, r0, #32
	str	r0, [r7]
	cmp	r2, r6
	bhs	.LBB1_10
	add.w	r0, r2, #32
	str	r2, [r7]
	cmp	r0, r6
	bhs	.LBB1_10
	add.w	r2, r0, #32
	str	r0, [r7]
	cmp	r2, r6
	bhs	.LBB1_10
	add.w	r0, r2, #32
	str	r2, [r7]
	cmp	r0, r6
	blo	.LBB1_6
.LBB1_10:
	movw	r4, :lower16:rx_buf
	dsb	sy
	movt	r4, :upper16:rx_buf
	movs	r2, #1
	mov	r0, r4
	bl	dma_start
	bl	dma_wait
	dsb	sy
.LBB1_11:
	add.w	r0, r4, #32
	str	r4, [r7]
	cmp	r0, r6
	bhs	.LBB1_16
	add.w	r1, r0, #32
	str	r0, [r7]
	cmp	r1, r6
	bhs	.LBB1_16
	add.w	r0, r1, #32
	str	r1, [r7]
	cmp	r0, r6
	bhs	.LBB1_16
	add.w	r4, r0, #32
	str	r0, [r7]
	cmp	r4, r6
	blo	.LBB1_11
	b	.LBB1_16
.LBB1_15:
	movw	r0, :lower16:rx_buf
	dsb	sy
	movt	r0, :upper16:rx_buf
	movs	r2, #1
	bl	dma_start
	bl	dma_wait
	dsb	sy
.LBB1_16:
	dsb	sy
	ldrb	r0, [r5]
	add	sp, #4
	pop.w	{r4, r5, r6, r7, lr}
.LBB1_17:
	bx	lr
```

**Codegen (verified — Clang 21.1.0, `-O2`, AArch64):**

```asm
dma_send:
	mov	w8, #165
	adrp	x9, tx_buf
	add	x9, x9, :lo12:tx_buf
	strb	w8, [x9]
	add	x8, x0, x9
	mov	x1, x0
	dsb	sy
	cmp	x8, x9
	b.ls	.LBB0_2
.LBB0_1:
	dc	cvac, x9
	add	x9, x9, #64
	cmp	x9, x8
	b.lo	.LBB0_1
.LBB0_2:
	dsb	sy
	adrp	x0, tx_buf
	add	x0, x0, :lo12:tx_buf
	mov	w2, wzr
	b	dma_start
dma_receive:
	cmp	x0, #1536
	b.ls	.LBB1_2
	mov	w0, #-1
	ret
.LBB1_2:
	mov	x1, x0
	mov	w0, #-1
	cbz	x1, .LBB1_10
	and	x8, x1, #0x3f
	cbnz	x8, .LBB1_10
	stp	x29, x30, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	adrp	x8, rx_buf
	add	x8, x8, :lo12:rx_buf
	add	x20, x1, x8
	dsb	sy
	mov	x29, sp
	cmp	x20, x8
	b.ls	.LBB1_8
.LBB1_5:
	dc	ivac, x8
	add	x8, x8, #64
	cmp	x8, x20
	b.lo	.LBB1_5
	dsb	sy
	adrp	x19, rx_buf
	add	x19, x19, :lo12:rx_buf
	mov	x0, x19
	mov	w2, #1
	bl	dma_start
	bl	dma_wait
	dsb	sy
.LBB1_7:
	dc	ivac, x19
	add	x19, x19, #64
	cmp	x19, x20
	b.lo	.LBB1_7
	b	.LBB1_9
.LBB1_8:
	dsb	sy
	adrp	x0, rx_buf
	add	x0, x0, :lo12:rx_buf
	mov	w2, #1
	bl	dma_start
	bl	dma_wait
	dsb	sy
.LBB1_9:
	dsb	sy
	adrp	x8, rx_buf
	ldp	x20, x19, [sp, #16]
	ldrb	w0, [x8, :lo12:rx_buf]
	ldp	x29, x30, [sp], #32
.LBB1_10:
	ret
```

Reading the listings:

- **TX, Cortex-M7 (`dma_send`):** the payload store (`strb r0, [r1]`), then `dsb sy`, then a loop of `str` to **`0xE000EF68`** (`DCCMVAC`; `61288 = 0xEF68`, `57344 = 0xE000`), one per 32-byte line, unrolled four times, then `dsb sy`, then a tail call to `dma_start`.
- **TX, AArch64:** `dsb sy`, then `dc cvac` per 64-byte line, then `dsb sy`, then `b dma_start`.
- **RX (`dma_receive`):**
  1. The line-exactness check is real code: `and x8, x1, #0x3f` / `cbnz` on AArch64, rejecting a non-multiple-of-line length before touching the cache.
  2. `dsb` → invalidate loop (`dc ivac` / `DCIMVAC` at `0xE000EF5C`) → `dsb`.
  3. `bl dma_start`, `bl dma_wait`.
  4. A **second** `dsb` → invalidate loop → `dsb` (rule 3's after-invalidate).
  5. Only then the `ldrb` of `rx_buf[0]`.
- `alignas(DCACHE_LINE)` on both buffers and a size that is a multiple of the line (1536 = 48 × 32 = 24 × 64) mean no CPU object can share their lines.
- An earlier version of this test used a constant 1536-byte RX length. Clang then **fully unrolled** both invalidate loops (48 `DCIMVAC` stores on M7), and spilled the precomputed line addresses to the stack across the `dma_start`/`dma_wait` calls: correct, but 250 lines. A run-time length, as real drivers have, keeps it to a loop.

Production additions:
- **AArch64:** read `CTR_EL0` at boot and assert `DminLine` and `CWG` against `DCACHE_LINE` (Folder 01 File 02 §1.8). `DC IVAC` is EL1-only, while EL0 has `DC CIVAC` if `SCTLR_EL1.UCI` permits.
- **Cortex-M7:** cache maintenance is privileged.
- **Batched RX:** invalidate all descriptors' buffers once per batch, not per packet.
- **Very large buffers:** clean/invalidate the *whole* cache by set/way (`SCB_CleanInvalidateDCache`) when it's cheaper than walking a 64 KB range line by line. On SMP Cortex-A, set/way operations are **not** broadcast, so they're only valid at boot or power-down.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| Received frames correct except for the first or last ≤ 31 bytes, intermittently | Shared edge line: write-back over DMA data (case 5) | Print the buffer address mod line and size mod line from the map file. The pattern is "stale chunk at an edge, ≤ line size" |
| A statistics counter or flag next to a DMA buffer loses updates | Invalidate rounded out over a neighbor (case 6) | DWT/`watch` on the neighbor variable. Its value reverts right after `SCB_InvalidateDCache_by_Addr` |
| TX frames sometimes contain old data | Missing clean, or a clean issued *after* the doorbell | Disassemble the send path. The order must be clean loop → `dsb` → doorbell store |
| RX data correct when read once, stale on a second read later | Missing after-invalidate: a speculative refill during the DMA | Add the post-completion invalidate (case 7) |
| Everything works with the D-cache disabled | It's a maintenance or layout bug, not a device bug | Quick triage: disable the D-cache (`SCB_DisableDCache`), or map the region non-cacheable with the MPU. If the bug vanishes, audit layout and maintenance |
| Linux: `DMA-API: device driver frees DMA memory with different size` / `… tries to sync DMA memory it has not allocated` | API misuse | `CONFIG_DMA_API_DEBUG=y`; `dma_debug` in debugfs |
| Throughput collapses when two cores update per-core statistics | False sharing (measured 3.9×) | `perf c2c` (HITM lines); pad to separate lines |

TRACE32's `CACHE.view` and `CACHE.DUMP DC` show the L1 contents and dirty bits on cores that expose cache debug (most Cortex-A; Cortex-M7 via the debug cache interface, ⚠ verify). That turns the simulator's state table into a live inspection.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "A DMA RX buffer shares a cache line with an unrelated variable. Walk me through how data gets corrupted."

- **L5:** "The CPU reads stale data unless you invalidate the cache."
- **Why L5 fails:** That's case 3, the easy one. The real disaster (case 5) is a **write-back**:
  - The CPU writes the neighbor variable during the transfer, so the shared line becomes dirty (M).
  - The line holds a *stale* copy of the buffer's edge bytes.
  - Any later eviction or clean writes the **whole line** back to RAM, overwriting the bytes the DMA just delivered (verified: 24 of 64 bytes lost).
  
  The obvious patch, invalidating the range, rounds out to the line and **discards the neighbor's update** instead (verified: `0x77` → `0x00`). Because maintenance is per line, no ordering of clean and invalidate operations can fix a shared line.
- **L7 principal defense:** Layout is the fix:
  - `alignas(LINE)` buffers whose size is rounded up to whole lines;
  - neighbors moved to their own lines;
  - invalidate-only operations that *refuse* partial lines (verified `dcache_invalidate_range`);
  - the protocol: invalidate before, invalidate after completion, `DSB`.
  
  Use the line size from `CTR_EL0` (the CWG) at boot. Or eliminate maintenance with Normal-NC (MPU or page tables) or an I/O-coherent port. On Linux, `ARCH_DMA_MINALIGN` plus swiotlb bouncing do this for you, so never DMA into stack or struct-embedded buffers.

### Q2 🔥 "Why invalidate *before* starting RX DMA, if you'll invalidate after anyway?"

- **L5:** "To be safe."
- **Why L5 fails:** It's not about safety margin. A **dirty** line covering the buffer (left over from earlier CPU use) can be **evicted during the transfer** and overwrite the incoming data. Invalidating afterwards can't undo a write-back that already happened. The *after*-invalidate handles the opposite problem: lines **speculatively refilled** during the transfer.
- **L7 defense:** Two different hazards, two operations (verified case 7). If the buffer may hold dirty data you want to keep, use clean+invalidate before. Linux encodes this in `dma_map` (before) and `dma_unmap`/`sync_for_cpu` (after) for `DMA_FROM_DEVICE`.

### Q3 "When would you choose a non-cacheable mapping over cache maintenance?"

- **L5:** "Non-cacheable is always simpler."
- **Why L5 fails:** Non-cacheable means every CPU access to the buffer goes to the bus. Parsing a 1500-byte frame byte by byte from NC SRAM can cost far more than one invalidate loop. Unaligned accesses to *Device* memory fault (Folder 01), so it must be Normal-NC, never Device.
- **L7 defense:** Decide per buffer:
  - **Descriptors** (small, touched by both sides constantly): Normal-NC, or coherent memory (`dma_alloc_coherent`).
  - **Bulk payloads** the CPU processes heavily: cached plus maintenance, with batched invalidates.
  - **I/O-coherent masters** (ACE-Lite, a coherent SMMU): neither.
  - **TCM**: neither, if the DMA can reach it.
  
  Measure both options on the real workload.

### Q4 "Explain MESI and show me false sharing in numbers."

- **L5:** "Four states; false sharing is when two variables share a cache line."
- **Why L5 fails:** It doesn't explain *why* it's slow: an **RFO invalidation on every write**, plus the line's transfer latency, serialize the two cores (verified: 37.4 ms vs 9.6 ms, 3.9×). It also misses the M → O path in MOESI, and snoop filters.
- **L7 defense:**
  - The state table.
  - Write-to-S/I costs an RFO; two writers ping-pong M ↔ I.
  - MOESI lets a dirty line be shared without a write-back.
  - Directories and snoop filters scale snooping on meshes (CMN).
  - Detection: `perf c2c` HITM.
  - Fix: per-core data on separate lines (64 or 128 bytes), and batched shared updates.

### Q5 🧊 "On SMP Cortex-A, why can't you clean the whole D-cache by set/way to flush DMA data?"

- **L5:** "Set/way is the fastest way to clean everything."
- **Why L5 fails:** Set/way operations act on **this core's cache structure only**. They aren't broadcast and they aren't coherent with other cores. Another core may hold the line dirty, or a line may migrate between cores mid-operation. Arm explicitly says set/way is for power-down and boot only.
- **L7 defense:** For DMA, maintenance **by VA to PoC** (`DC CVAC`/`IVAC`/`CIVAC`), which is broadcast in the inner-shareable domain. For very large ranges on SMP, use non-cacheable mappings or coherent DMA instead of walking huge ranges. Reserve set/way for the cache-off sequences of cpuidle and boot code.

---

## 5. Invariants Checklist

- [ ] Every DMA buffer: line-aligned start, size rounded up to whole lines (CWG on AArch64, 32 B on M7), no CPU object sharing a line.
- [ ] TX: clean to PoC → `DSB` → doorbell. RX: invalidate (or clean+invalidate) before → transfer → invalidate after → `DSB` → read.
- [ ] Invalidate-only maintenance refuses partial lines; partial lines use clean+invalidate, and the layout gets fixed.
- [ ] Descriptors in coherent/Normal-NC memory or line-padded (Folder 01 File 02 `dma_desc_t`); payload policy decided per buffer.
- [ ] Line size and CWG read at boot (`CTR_EL0` / `CCSIDR`) and asserted against the compile-time constant.
- [ ] No set/way maintenance on running SMP systems.
- [ ] Linux drivers use the DMA API only (`dma_map_*`/`dma_sync_*`/`dma_alloc_coherent`); `CONFIG_DMA_API_DEBUG` in test builds.
- [ ] Per-core hot data padded to its own line; `perf c2c` in the performance test plan.

## 6. References

1. U. Drepper, *What Every Programmer Should Know About Memory*, 2007, §3.3, §6.4.
2. D. Sorin, M. Hill, D. Wood, *A Primer on Memory Consistency and Cache Coherence*, 2nd ed., Morgan & Claypool, 2020.
3. Arm, *AMBA AXI and ACE Protocol Specification* (IHI 0022) and *AMBA 5 CHI Architecture Specification* (IHI 0050); CoreLink CCI-500 / CMN-700 TRMs.
4. Arm, *Arm Architecture Reference Manual for A-profile* (DDI 0487) D7.5 cache maintenance instructions, PoC/PoU; *ARMv7-M ARM* B2.2.7; *Cortex-M7 TRM* and AN *Level 1 cache on STM32F7/H7* (vendor app notes; ⚠ verify).
5. Linux: `Documentation/core-api/dma-api.rst`, `dma-api-howto.rst`, `arch/arm64/mm/cache.S`, `arch/arm64/mm/dma-mapping.c`, `kernel/dma/swiotlb.c`.
6. CMSIS-Core `SCB_CleanDCache_by_Addr` / `SCB_InvalidateDCache_by_Addr` reference implementations (ARM-software/CMSIS_6).
