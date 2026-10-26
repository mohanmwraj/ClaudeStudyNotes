# 01 · AXI4/AHB/APB Interconnects, PCIe BARs and MSI-X, and the IOMMU/SMMU

> **Folder:** `06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/` · **File 1 of 3**
> **Anchors:**
> - Arm *AMBA AXI and ACE Protocol Specification* (IHI 0022), *AMBA 5 AHB* (IHI 0033), *AMBA APB* (IHI 0024).
> - PCI-SIG *PCI Express Base Specification* (Type-0 header, BARs, MSI-X §6.1.4) and *PCI Local Bus Specification 3.0* §6.2.5.1 (BAR sizing).
> - Arm *System MMU Architecture Specification SMMUv3* (IHI 0070); Intel VT-d; Linux `Documentation/core-api/dma-api.rst`, `drivers/iommu/arm/arm-smmu-v3/`.
> - Arm AN321 (DSB after interrupt clear).
>
> **Verification:**
> - BAR sizing code ran against a register-accurate Type-0 configuration-space model (32-bit MMIO, 64-bit prefetchable pair, I/O).
> - MSI-X entry programming compiled for AArch64; codegen inserted verbatim.
> - Bus-protocol behavior is from the AMBA/PCIe specifications. It's architectural, not measured here.

---

## 0. The thesis

Every register write in a driver becomes a **bus transaction**. Its ordering, completion and attributes (cacheable? bufferable? secure? which master?) decide whether the hardware does what the C code says. Three facts carry most of the weight:

1. Writes are **posted**: the CPU continues before they arrive.
2. Memory **attributes** select the transaction type: Device vs Normal, UC vs WC on x86.
3. Bus masters other than the CPU **see addresses through an IOMMU/SMMU**, or don't.

---

## 1. First-Principles Hardware Mechanics

### 1.1 The AMBA family

| Bus | Structure | Key properties | Typical clients |
|---|---|---|---|
| **AXI4 / AXI5** | **Five independent channels**: AR (read address), R (read data), AW (write address), W (write data), B (write response) | Out-of-order completion by **ID**; multiple outstanding transactions; bursts up to 256 beats (INCR); `AxCACHE` (bufferable/modifiable/allocate), `AxPROT` (privileged/**non-secure**/instruction), `AxQOS`; `WSTRB` byte strobes | CPU clusters, DMA engines, GPUs, DDR controllers, NoCs |
| **ACE / ACE-Lite / CHI** | AXI plus snoop channels (ACE) or packet protocol (CHI) | Hardware coherency (Folder 03); ACE-Lite = I/O coherent (snoops CPU caches, no cache of its own) | Coherent clusters, I/O-coherent DMA |
| **AHB / AHB-Lite** | Single shared address/data, **pipelined** (address phase overlaps the previous data phase) | `HSIZE` access width, `HPROT`, `HRESP` (OKAY/ERROR); one transfer in flight per stage | Cortex-M system buses, low-end DMA, on-chip SRAM |
| **APB** | Non-pipelined, two-phase (SETUP, ACCESS); `PREADY` wait states; `PSLVERR` | Low power and low gate count; **every access takes ≥ 2 cycles of the (often divided) APB clock** | UART, I²C, SPI, timers, GPIO configuration |

**Bridges** (AXI→AHB→APB) are where driver bugs live:
- they run at different clocks (APB is often SYSCLK/2–/16);
- they **buffer writes**: a bufferable write is acknowledged to the CPU as soon as the bridge accepts it, not when the peripheral latches it.

### 1.2 Posted writes and the spurious double interrupt ⚡

```text
 CPU (ISR epilogue)      AXI/AHB            APB bridge (write buffer)      UART @ PCLK/4
 str ICR = 0x8   ──►  accepted (OKAY) ──►  queued ... 4-8 PCLK cycles ...  ──► ORE cleared
 bx lr (EXC_RETURN) ─► exception return: NVIC re-samples the IRQ line  ◄── still asserted!
                       IRQ re-pends ──► ISR runs AGAIN with nothing to do
```

The clear was *issued* but hadn't *arrived* when the NVIC re-evaluated the pending state at exception return. Fixes, in decreasing generality:

1. **Read back** a register of the same peripheral. A read on the same path can't complete until earlier buffered writes to that peripheral have drained, because APB is in-order. This is the most portable fix, and it's verified in the Folder 01 `uart_configure` read-back.
2. **`DSB`** before exception return. It ensures completion of the outstanding writes the core has issued, at least as far as the architecture's completion point for the bus (Folder 03). The Folder 04 `irq_good.c` ISR ends with `dsb sy`.
3. Clear the source **early** in the ISR rather than as its last instruction, so the write has time to drain.

The same mechanism causes:
- "clock enable then immediately access the peripheral" bus faults (the enable write hasn't reached the RCC yet, so read back the RCC register);
- "disable interrupt, then the ISR still fires once".

### 1.3 Memory types and transaction attributes

| CPU mapping | AArch64 MAIR / M-profile | x86 PAT | Transactions | Use |
|---|---|---|---|---|
| Device-nGnRnE | `0x00` / Strongly-ordered | **UC** (uncacheable) | Exact size, in order, no merging, non-posted completion semantics | Registers with side effects needing strict completion |
| Device-nGnRE | `0x04` / Device | UC- | In order, no gathering, early write acknowledgment allowed | Most MMIO registers (Linux `ioremap`) |
| Normal Non-cacheable | `0x44` / Normal NC | **WC** (write-combining) | Writes may be **gathered/merged** and reordered; reads may be speculative | Framebuffers, PCIe prefetchable BARs for doorbell batches (`ioremap_wc`), DMA buffers needing no maintenance (not for registers!) |
| Normal WB | `0xFF` / Normal WB-WA | WB | Cached | RAM |

**Write-combining** buffers a burst of writes and emits them as one bus transaction. That's a massive bandwidth win for posting descriptor blocks to a device. The cost is that the device may see the writes **out of order, or merged**, so the driver must fence before the *doorbell*:
- x86: `sfence` (Linux `wmb()`);
- ARM: `dsb st`, or the `dma_wmb()`/`writel()` discipline (Folder 03 File 02, verified `publish_desc`).

**Never map side-effecting registers WC**: two status reads may merge, or a read may be speculatively prefetched and pop a FIFO.

### 1.4 PCIe BARs: sizing, mapping, attributes (verified)

Each **BAR** (Base Address Register) in a function's configuration header asks for an address window. The device hardwires the low address bits to 0, so writing all-ones and reading back reveals the size.

```c
/* pcie_bar.c - PCI/PCIe BAR sizing and decoding (PCI Local Bus 3.0 §6.2.5.1,
 * PCIe Base spec Type-0 header): write all-ones, read back, the hardwired-zero
 * low address bits give the size. Handles 32-bit MMIO, 64-bit (two BARs),
 * prefetchable, and I/O BARs. Config access goes through two callbacks so the
 * same code runs on ECAM MMIO, a legacy CF8/CFC port, or a host test model. */
#include <stdbool.h>
#include <stdint.h>

typedef uint32_t (*cfg_rd_t)(void *ctx, uint32_t off);
typedef void     (*cfg_wr_t)(void *ctx, uint32_t off, uint32_t val);

#define PCI_CMD          0x04u
#define PCI_CMD_IO       (1u << 0)
#define PCI_CMD_MEM      (1u << 1)
#define PCI_BAR0         0x10u
#define BAR_IO           (1u << 0)
#define BAR_TYPE_MASK    (3u << 1)
#define BAR_TYPE_64      (2u << 1)
#define BAR_PREFETCH     (1u << 3)

typedef struct {
    bool     present, io, is64, prefetch;
    uint64_t base, size;
} bar_info_t;

/* Returns the number of BAR slots consumed (1, or 2 for a 64-bit BAR). */
unsigned pci_size_bar(void *ctx, cfg_rd_t rd, cfg_wr_t wr, unsigned idx, bar_info_t *out);
unsigned pci_size_bar(void *ctx, cfg_rd_t rd, cfg_wr_t wr, unsigned idx, bar_info_t *out)
{
    uint32_t off = PCI_BAR0 + 4u * idx;
    uint32_t cmd = rd(ctx, PCI_CMD);
    wr(ctx, PCI_CMD, cmd & ~(PCI_CMD_IO | PCI_CMD_MEM));   /* 1. stop decoding while probing:
                                                          *    all-ones would decode 0xFFFF_xxxx */
    uint32_t orig = rd(ctx, off);
    wr(ctx, off, 0xFFFFFFFFu);
    uint32_t probe = rd(ctx, off);
    wr(ctx, off, orig);                                  /* 2. restore */

    out->present = (probe != 0u);
    out->io = (orig & BAR_IO) != 0u;
    out->is64 = !out->io && ((orig & BAR_TYPE_MASK) == BAR_TYPE_64);
    out->prefetch = !out->io && ((orig & BAR_PREFETCH) != 0u);
    unsigned used = 1u;

    if (out->io) {
        uint32_t mask = probe & ~0x3u;
        out->base = orig & ~0x3u;
        out->size = (mask != 0u) ? (uint64_t)((~mask & 0xFFFFu) + 1u) : 0u;  /* I/O: 16-bit decode */
    } else if (out->is64) {
        uint32_t off_hi = off + 4u;
        uint32_t orig_hi = rd(ctx, off_hi);
        wr(ctx, off_hi, 0xFFFFFFFFu);
        uint32_t probe_hi = rd(ctx, off_hi);
        wr(ctx, off_hi, orig_hi);
        uint64_t mask = ((uint64_t)probe_hi << 32) | (probe & ~0xFu);
        out->base = ((uint64_t)orig_hi << 32) | (orig & ~0xFu);
        out->size = (mask != 0u) ? (~mask + 1u) : 0u;
        used = 2u;
    } else {
        uint32_t mask = probe & ~0xFu;
        out->base = orig & ~0xFu;
        out->size = (mask != 0u) ? (uint64_t)(~mask + 1u) : 0u;
    }
    wr(ctx, PCI_CMD, cmd);                               /* 3. decoding back on */
    return used;
}

#ifdef BAR_SELFTEST
#include <stdio.h>

/* Model of a Type-0 header: each BAR keeps only its writable address bits
 * (size-aligned) and hardwires the low type bits, exactly like silicon. */
typedef struct { uint32_t reg[64]; uint64_t size[6]; uint32_t type[6]; } dev_model_t;

static uint32_t m_rd(void *ctx, uint32_t off) { return ((dev_model_t *)ctx)->reg[off / 4u]; }
static void m_wr(void *ctx, uint32_t off, uint32_t v)
{
    dev_model_t *d = ctx;
    unsigned i = (off - PCI_BAR0) / 4u;
    if ((off >= PCI_BAR0) && (i < 6u) && (d->size[i] != 0u)) {
        uint64_t sz = d->size[i];
        uint32_t lowmask = (d->type[i] & BAR_IO) ? 0x3u : 0xFu;
        uint32_t keep = (uint32_t)(~(sz - 1u)) & ~lowmask;
        d->reg[off / 4u] = (v & keep) | d->type[i];
    } else if ((off >= PCI_BAR0) && (i < 6u) && (i > 0u) && (d->size[i - 1u] != 0u) &&
               ((d->type[i - 1u] & BAR_TYPE_MASK) == BAR_TYPE_64)) {
        uint64_t sz = d->size[i - 1u];                   /* upper half of a 64-bit BAR */
        d->reg[off / 4u] = v & (uint32_t)((~(sz - 1u)) >> 32);
    } else if ((off < PCI_BAR0) || (i >= 6u)) {
        d->reg[off / 4u] = v;                            /* non-BAR registers */
    }                                                    /* unimplemented BARs stay 0 */
}

int main(void)
{
    static dev_model_t d;
    d.size[0] = 16u * 1024u;          d.type[0] = 0u;                           /* 32-bit MMIO, 16 KB  */
    d.size[2] = 256ull << 20;         d.type[2] = BAR_TYPE_64 | BAR_PREFETCH;   /* 64-bit pref, 256 MB */
    d.size[4] = 256u;                 d.type[4] = BAR_IO;                       /* I/O, 256 B          */
    m_wr(&d, PCI_BAR0 + 0u, 0xF7C00000u);                                       /* firmware-assigned   */
    m_wr(&d, PCI_BAR0 + 8u, 0x00000000u); m_wr(&d, PCI_BAR0 + 12u, 0x00000040u);/* 0x40_0000_0000      */
    m_wr(&d, PCI_BAR0 + 16u, 0x0000E000u);
    d.reg[PCI_CMD / 4u] = PCI_CMD_MEM | PCI_CMD_IO;

    for (unsigned i = 0u; i < 6u; ) {
        bar_info_t b;
        unsigned used = pci_size_bar(&d, m_rd, m_wr, i, &b);
        if (b.present) {
            printf("BAR%u: %s%s%s base=0x%010llX size=0x%llX (%llu bytes)\n", i,
                   b.io ? "I/O" : "MEM", b.is64 ? " 64-bit" : (b.io ? "" : " 32-bit"),
                   b.prefetch ? " prefetchable" : "", (unsigned long long)b.base,
                   (unsigned long long)b.size, (unsigned long long)b.size);
        } else {
            printf("BAR%u: unimplemented\n", i);
        }
        i += used;
    }
    printf("command register restored: 0x%X\n", (unsigned)d.reg[PCI_CMD / 4u]);
    return 0;
}
#endif
```

**Output (verified, native, against the configuration-space model):**

```text
BAR0: MEM 32-bit base=0x00F7C00000 size=0x4000 (16384 bytes)
BAR1: unimplemented
BAR2: MEM 64-bit prefetchable base=0x4000000000 size=0x10000000 (268435456 bytes)
BAR4: I/O base=0x000000E000 size=0x100 (256 bytes)
BAR5: unimplemented
command register restored: 0x3
```

- **BAR0:** a 32-bit MMIO window, 16 KB (`~0xFFFFC000 + 1`).
- **BAR2:** a **64-bit prefetchable** 256 MB window at `0x40_0000_0000`. It **consumes BAR2 and BAR3**, which is why the enumeration loop skipped from BAR2 to BAR4 (`used = 2`). Prefetchable means reads have no side effects, so the host may map it WC/Normal-NC and the root complex may prefetch.
- **BAR4:** I/O space, 256 bytes.
- **Command register restored** (`0x3`: MEM | IO). Memory/IO decoding was **disabled while probing**. Otherwise the transient all-ones value would make the device claim addresses near `0xFFFF_FFFF` (or `0xFFFF…F` for 64-bit), colliding with other devices' ranges or the boot ROM.

In Linux this is done for you (`pci_read_bases()`). Drivers `pci_iomap()`/`pcim_iomap_regions()` the BARs: registers go through `ioremap` (Device-nGnRE), and prefetchable BARs used as write buffers through `ioremap_wc` or `pci_iomap_wc`.

### 1.5 MSI-X: interrupts as memory writes (verified)

MSI/MSI-X replace interrupt wires with a **posted memory write** from the device:
- on x86 the write goes to the LAPIC address range;
- on ARM it goes to the **GIC ITS** `GITS_TRANSLATER`, which translates (DeviceID, EventID) into an LPI (Folder 04, File 01).

An MSI-X **table** in a BAR holds up to 2048 vectors, each 16 bytes.

```c
/* msix.c - programming one MSI-X table entry (PCIe Base spec §6.1.4.2):
 * 16 bytes per vector {addr_lo, addr_hi, data, vector_control}. The table
 * lives in a BAR (Device memory). Mask the vector while address/data are
 * inconsistent, then unmask - a device may sample a half-written entry. */
#include <stdint.h>

typedef struct {
    volatile uint32_t addr_lo;
    volatile uint32_t addr_hi;
    volatile uint32_t data;
    volatile uint32_t ctrl;          /* bit 0: per-vector mask */
} msix_entry_t;
_Static_assert(sizeof(msix_entry_t) == 16u, "MSI-X entry is 16 bytes");

#define MSIX_CTRL_MASK 1u

static inline void io_wmb(void)      /* order Device-memory writes to one device (Folder 03) */
{
#if defined(__aarch64__)
    __asm__ volatile("dmb oshst" : : : "memory");
#else
    __asm__ volatile("" : : : "memory");
#endif
}

void msix_program(msix_entry_t *table, unsigned vec, uint64_t msg_addr, uint32_t msg_data);
void msix_program(msix_entry_t *table, unsigned vec, uint64_t msg_addr, uint32_t msg_data)
{
    msix_entry_t *e = &table[vec];
    e->ctrl = e->ctrl | MSIX_CTRL_MASK;         /* 1. mask                             */
    io_wmb();
    e->addr_lo = (uint32_t)msg_addr;            /* 2. GIC ITS doorbell / x86 LAPIC addr */
    e->addr_hi = (uint32_t)(msg_addr >> 32);
    e->data    = msg_data;                      /*    EventID / vector                  */
    io_wmb();
    e->ctrl = e->ctrl & ~MSIX_CTRL_MASK;        /* 3. unmask                           */
    (void)e->ctrl;                              /* 4. flush the posted writes (read)   */
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-none-elf`):**

```asm
msix_program:
	add	x9, x0, w1, uxtw #4
	lsr	x8, x2, #32
	ldr	w10, [x9, #12]
	orr	w10, w10, #0x1
	str	w10, [x9, #12]
	dmb	oshst
	str	w2, [x9]
	str	w8, [x9, #4]
	str	w3, [x9, #8]
	dmb	oshst
	ldr	w8, [x9, #12]
	and	w8, w8, #0xfffffffe
	str	w8, [x9, #12]
	ldr	wzr, [x9, #12]
	ret
```

The sequence is: set the mask bit (`orr #1`) → `dmb oshst` → address low/high and data (`str w2`/`str w8`/`str w3`) → `dmb oshst` → clear the mask → **`ldr wzr`**, a read-back that flushes the posted writes through the PCIe hierarchy. Without the mask, a device that samples the entry between the address and data writes could send an interrupt to a half-updated destination. That matters when re-targeting a vector to another CPU (IRQ affinity) while the device is live.

**Why MSI-X matters for NVIDIA/Qualcomm-class devices:**
- **one vector per queue, steered to the CPU that owns that queue** (`/proc/irq/N/smp_affinity`, `irq_set_affinity_hint`, or managed affinity via `pci_alloc_irq_vectors_affinity` with `PCI_IRQ_AFFINITY`);
- completion interrupts land on the core whose cache holds the queue's data;
- no shared-line demultiplexing;
- MSI-X writes are ordered behind the device's earlier DMA writes (PCIe ordering rules for posted writes). By the time the interrupt arrives, the completion data is visible, provided the memory is coherent or the driver performs `dma_sync_*_for_cpu`.

### 1.6 Descriptor rings and doorbells

The universal high-performance device interface (NVMe, NICs, GPUs' command processors, accelerators):

```text
 host memory (DMA-able)                        device BAR (MMIO)
 ┌──────────────────────────┐                  ┌───────────────────┐
 │ desc[0..N-1]  (SQ)       │◄── device reads ─│ SQ tail doorbell  │◄── host writes new tail
 │ completions   (CQ)       │──► device writes │ CQ head doorbell  │◄── host writes consumed head
 └──────────────────────────┘                  └───────────────────┘
 1. host fills desc[tail]            (Normal memory; coherent or cleaned)
 2. dma_wmb()                         (descriptor visible before the doorbell)
 3. writel(tail+1, SQ_DOORBELL)       (MMIO, posted)
 4. device fetches, executes, writes CQ entry with a phase bit, then raises MSI-X
 5. host: dma_rmb() after seeing the new phase bit; consume; writel(head, CQ_DOORBELL)
```

The **phase (or "owner") bit** in each completion entry flips every lap. The host detects new entries without reading a device register: a CPU-local memory poll instead of an MMIO read, which is about 1 µs or more on PCIe. Batching doorbells (one write per N descriptors) and WC-mapped doorbell pages are how drivers reach millions of IOPS.

### 1.7 IOMMU / SMMU: the MMU for devices

| Without an IOMMU | With an IOMMU / SMMUv3 |
|---|---|
| Devices DMA to **physical addresses**: any device bug, or a malicious device (Thunderbolt/PCIe DMA attacks), can write anywhere | Devices DMA to **I/O virtual addresses (IOVA)**, translated per device (StreamID) through page tables the OS controls |
| A 32-bit DMA device can't reach memory above 4 GB, so it needs **bounce buffers** (swiotlb) | IOVA space can be allocated below 4 GB while the physical pages are anywhere |
| Scatter-gather needs device support | The IOMMU can make scattered pages *look contiguous* in IOVA |
| No isolation between VMs | **Stage-2** translation lets a VM pass a device through (VFIO) safely |

SMMUv3 structures:
- **Stream Table**, indexed by StreamID (derived from the PCIe Requester ID: bus/device/function);
- **Context Descriptors** (stage-1 page tables, ASID; the same descriptor format as the CPU MMU, Folder 02 File 03);
- stage-2 tables (VMID);
- **command and event queues** in memory (rings with producer/consumer indices, §1.6 again);
- **ATS/PRI**: devices with their own TLBs (ATCs), and page-request handling for shared virtual addressing (SVA: the device uses the process's page tables).

The Linux driver contract: **always use the DMA API** (`dma_map_single`, `dma_map_sg`, `dma_alloc_coherent`). It returns the address the *device* must use (an IOVA or a physical address), performs cache maintenance for non-coherent devices, bounces when necessary, and unmaps to revoke access. Passing `virt_to_phys()` to a device works on a development board without an IOMMU and breaks everywhere else.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* nic_bad.c - an accelerator/NIC submission path with five classic defects. */
#include <stdint.h>

typedef struct { uint64_t addr; uint32_t len; uint32_t flags; } desc_t;

extern desc_t  *g_sq;                 /* allocated with plain kmalloc-like memory */
extern volatile uint32_t *g_sq_db;    /* doorbell, mapped write-combining          */
extern uint64_t virt_to_phys_hack(const void *p);

void submit(const void *buf, uint32_t len, uint32_t tail);
void submit(const void *buf, uint32_t len, uint32_t tail)
{
    g_sq[tail].addr  = virt_to_phys_hack(buf);   /* BUG 1: physical address, bypasses IOMMU,
                                                  *        no cache maintenance, no bounce    */
    g_sq[tail].len   = len;
    g_sq[tail].flags = 1u;                       /* BUG 2: no dma_wmb: device may fetch the
                                                  *        descriptor before addr/len land    */
    *g_sq_db = tail + 1u;                        /* BUG 3: doorbell in a WC mapping with no
                                                  *        wmb/sfence: may be merged/delayed   */
}                                                /* BUG 4: descriptors in cacheable memory on a
                                                  *        non-coherent device: never cleaned
                                                  * BUG 5: completion polled by MMIO register
                                                  *        read in a loop (1+ us per read)      */
```

### 2.2 The Silicon-Hardened Production Way

The submission sequence as a checklist, each step tied to a verified artifact in this KB:
1. The descriptor ring comes from `dma_alloc_coherent()` (or Normal-NC memory on bare metal), so no maintenance is needed for descriptors.
2. Payload buffers are mapped with `dma_map_single(dev, buf, len, DMA_TO_DEVICE)`, which yields an IOVA plus a clean for non-coherent devices (Folder 03 File 03 `dcache_clean_range`).
3. Fill the descriptor, then `dma_wmb()` (`dmb oshst`), then set the OWN/phase bit (Folder 03 File 02 `publish_desc`, verified).
4. Doorbell via `writel()`, which includes its own ordering barrier. With WC doorbell pages, use `wmb()` first, and batch: one doorbell per N descriptors.
5. Completions:
   - the MSI-X vector is steered to the queue's CPU;
   - the CQ phase bit is polled in memory, then `dma_rmb()`, then the entry is consumed;
   - the head doorbell is written once per batch;
   - `dma_unmap_*` (an invalidate for `FROM_DEVICE`) happens before the CPU reads the payload.
6. MSI-X entries are re-targeted with mask → write → unmask → read-back (verified).

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| ISR runs twice per event; spurious interrupt counters climb | Posted clear not yet at the APB peripheral at exception return (§1.2) | Logic analyzer: peripheral IRQ line vs a GPIO toggled in the ISR. Fix with a read-back or `DSB` |
| BusFault right after enabling a peripheral clock | Clock-enable write still buffered when the peripheral is accessed | `BFAR` = the peripheral address. Read back the RCC enable register before first use |
| Device sees a stale or partial descriptor | Missing `dma_wmb()`, or a WC doorbell without a fence, or descriptors cached on a non-coherent device | PCIe analyzer (LeCroy/Teledyne, or the device's own debug FIFOs): the doorbell TLP precedes the descriptor fetch, or the fetch returns old data |
| `DMAR`/SMMU fault log entries (`arm-smmu-v3: event 0x10 received`, translation fault) | Device used an address not mapped in its IOVA space: `virt_to_phys` used, a use-after-unmap, or a wrong StreamID | `dmesg` SMMU events give StreamID and IOVA. `CONFIG_DMA_API_DEBUG`; `iommu.passthrough=0` |
| Device works below 4 GB, fails above | 32-bit DMA mask without IOMMU or bounce | `dma_set_mask_and_coherent(dev, DMA_BIT_MASK(64))` if supported; check `swiotlb` usage |
| Interrupt storm after changing IRQ affinity | MSI-X entry updated without masking | Mask → write → unmask (§1.5) |
| Slow MMIO polling loop dominates CPU | Each non-posted read is a PCIe round trip | Poll phase bits in host memory; use MSI-X interrupts plus NAPI-style polling (File 03) |

`lspci -vvv` decodes BARs (`Region 0: Memory at f7c00000 (32-bit, non-prefetchable) [size=16K]`, matching the verified decode), the MSI-X capability (`MSI-X: Enable+ Count=64 Masked-`), and the link state. `setpci` reads and writes raw config registers. `/sys/kernel/iommu_groups/` shows isolation groups.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥⚡ "Why can clearing an interrupt flag as the last line of an ISR cause the ISR to run twice?"

- **L5:** "Hardware bug; add a check for spurious interrupts."
- **Why L5 fails on real hardware:** The write is **posted**. The CPU's bus interface acknowledged it when the AXI/AHB→APB bridge buffered it, so the core proceeded to exception return. The NVIC re-sampled the still-asserted IRQ line before the clear reached the slow APB peripheral.
- **L7 principal defense:** Describe the bus path (§1.2): pipelined AHB, buffered bridge, divided PCLK. The fixes are a read-back of the same peripheral (works on any bus), `DSB` before return (completion), and clearing early. Know the related cases: clock enable then access, and NVIC disable then a still-firing ISR (`DSB`+`ISB` after `ICER`, verified `nvic_disable` in Folder 04). Verify with a logic analyzer on the IRQ line.

### Q2 🔥 "How does the OS determine a PCIe BAR's size, and why disable decoding first?"

- **L5:** "Write all ones and read it back."
- **Why L5 fails:** It omits:
  - 64-bit BARs spanning two registers (verified: BAR2+BAR3);
  - I/O versus memory masks;
  - restoring the original value;
  - **disabling memory/IO decode** during the probe. All-ones is a valid-looking address, and a decoding device would claim transactions there.
- **L7 defense:** The verified sizing code and output. Explain prefetchable BARs and why they can be mapped WC. Then how Linux allocates BAR windows inside the host bridge apertures and programs the bridges' windows, and resizable BAR (ReBAR) for GPUs.

### Q3 🔥 "WC vs UC mappings for a GPU or NIC: when and why?"

- **L5:** "WC is faster."
- **Why L5 fails:** WC merges and reorders writes and permits speculative reads. Correct for write-only bulk data (command buffers, framebuffers, doorbell batching through prefetchable BARs). Fatal for side-effecting registers: merged status reads, popped FIFOs, reordered command writes.
- **L7 defense:** The attribute table (§1.3): registers are UC/Device-nGnRE (`ioremap`), bulk is WC (`ioremap_wc`), and RAM rings come from the DMA API. Fence before the doorbell (`wmb()`/`sfence` on x86, `dsb st` or `dma_wmb()`+`writel` on ARM). Mention the x86 PAT/MTRR interaction and the ARM mapping of WC to Normal-NC.

### Q4 "Explain MSI-X and why each queue gets its own vector."

- **L5:** "MSI-X supports more interrupts than MSI."
- **Why L5 fails:** The *architectural* reasons:
  - an interrupt is a **posted write** ordered behind the device's earlier DMA writes, so completion data is visible when it fires;
  - vectors are independently **maskable and targetable**, so each queue's completions land on the CPU that owns that queue, which keeps the data cache-local and avoids locks;
  - on ARM, MSI-X writes go to the GIC ITS, which maps them to LPIs.
- **L7 defense:** The table entry layout and the verified mask → write → unmask → read-back sequence. Managed affinity in Linux (`pci_alloc_irq_vectors_affinity`). Interrupt coalescing and NAPI (File 03) to bound the interrupt rate.

### Q5 🧊 "What does an IOMMU buy you, and what does it cost?"

- **L5:** "Security."
- **Why L5 fails:** Incomplete. It also buys:
  - address-range independence (32-bit devices, no bounces);
  - scatter-gather emulation;
  - VM device assignment (stage-2/VFIO);
  - shared virtual addressing (PASID/SVA).
  
  The **costs**: IOTLB misses (page walks on the DMA path), map/unmap overhead per I/O (mitigated by batching, lazy flush, and large IOVA pages), and invalidation latency.
- **L7 defense:** SMMUv3 structures (stream table, CDs, queues), ATS/ATC for device-side TLBs, and choosing strict vs lazy invalidation per security posture (`iommu.strict`). Driver rules: the DMA API only, never physical addresses, and never touch a buffer after unmap.

---

## 5. Invariants Checklist

- [ ] Every interrupt-source clear is followed by a read-back or `DSB` before exception return; clocks are read back after enabling.
- [ ] Registers mapped Device-nGnRE / UC; bulk write paths WC / Normal-NC with a fence before the doorbell; nothing side-effecting mapped WC.
- [ ] BARs sized with decode disabled, 64-bit pairs handled, originals restored (or left to the OS enumerator).
- [ ] MSI-X entries updated under mask, with a read-back; one vector per queue, affinity managed.
- [ ] Rings: descriptors in coherent memory; fill → `dma_wmb()` → OWN/phase → `writel` doorbell; completions via an in-memory phase bit, `dma_rmb()`, batched head doorbells.
- [ ] All device addresses come from the DMA API (IOVA-aware); no `virt_to_phys` to devices; correct DMA mask set.
- [ ] SMMU/IOMMU fault logging enabled and monitored in production fleets.

## 6. References

1. Arm, *AMBA AXI and ACE Protocol Specification* (IHI 0022), *AMBA 5 AHB Protocol Specification* (IHI 0033), *AMBA APB Protocol Specification* (IHI 0024).
2. PCI-SIG, *PCI Express Base Specification* (Rev. 5.0/6.0): configuration space, BARs, MSI-X, ordering rules; *PCI Local Bus Specification 3.0* §6.2.5.1.
3. Arm, *SMMUv3 Architecture Specification* (IHI 0070); Intel, *Virtualization Technology for Directed I/O*.
4. Linux: `drivers/pci/probe.c` (`__pci_read_base`), `Documentation/PCI/msi-howto.rst`, `Documentation/core-api/dma-api.rst`, `Documentation/driver-api/device-io.rst`.
5. NVM Express Base Specification (submission/completion queues, phase tags) as the reference ring-and-doorbell interface.
