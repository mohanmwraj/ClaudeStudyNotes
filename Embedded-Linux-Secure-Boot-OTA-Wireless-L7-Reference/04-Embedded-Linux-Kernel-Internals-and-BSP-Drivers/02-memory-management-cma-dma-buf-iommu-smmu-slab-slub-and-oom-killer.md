# 04.2 · Memory Management: CMA, DMA-BUF, IOMMU/SMMU, SLUB and the OOM Killer

> **Folder 04 · File 2 of 4.** An embedded SoC moves most of its bytes without the CPU: cameras, display, video codecs, NICs and storage DMA directly into memory. The kernel's job is to make three things true:
> - every device gets addresses it can reach;
> - the CPU and the device never see different versions of the same bytes;
> - contiguous memory exists when a 30 MB frame buffer is needed at minute 300 of uptime.
>
> When memory does run out, the kernel also has to decide which process dies.
>
> This file covers:
> - the DMA API's contract, and the arm64 cache maintenance behind it, simulated to show exactly which misuse corrupts data and how rarely;
> - CMA and reserved memory;
> - IOMMU/SMMU translation;
> - DMA-BUF sharing;
> - SLUB;
> - the OOM killer's arithmetic.
>
> **Pinned.** Linux **v7.2**:
> - `arch/arm64/mm/dma-mapping.c` (`arch_sync_dma_for_device` / `arch_sync_dma_for_cpu`);
> - `mm/oom_kill.c` (`oom_badness`, `oom_evaluate_task`, `oom_unkillable_task`);
> - `fs/proc/base.c` (`proc_oom_score`);
> - `include/uapi/linux/dma-buf.h`;
> - Kconfig: `SLUB` (SLAB and SLOB are gone), `DMA_CMA`, `CMA_SIZE_MBYTES`, `ARM_SMMU_V3`, `IOMMU_DEFAULT_DMA_STRICT` / `_LAZY` / `_PASSTHROUGH`, `DMA_API_DEBUG`, `KFENCE`.
>
> **Verification.**
> - `dma_cache_model.py` applies the arm64 maintenance rules under every speculative-fill and eviction point.
> - `oom_model.py` reproduces the kernel's scoring.
> - The drivers pass `kapi_check.py` (04.1) against v7.2 headers, and `dma_lint.py` for DMA-specific misuse.
> - The reserved-memory tree passes `dts_lint.py` and `dt_probe_check.py`.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 Coherent vs non-coherent, and what the DMA API does about it

```text
                      CPU ──► L1/L2 (write-back) ──┐
                                                    ├──► interconnect ──► DRAM
   non-coherent master (most SoC IP) ──────────────┘          (device reads/writes DRAM; never sees CPU caches)
   coherent master (CCI/CMN-attached, "dma-coherent" in DT) ── snoops CPU caches: no maintenance needed

 arm64, non-coherent device (arch/arm64/mm/dma-mapping.c):
   dma_map_* / dma_sync_*_for_device  → arch_sync_dma_for_device: dcache_clean_poc   (any direction)
   dma_unmap_* / dma_sync_*_for_cpu   → arch_sync_dma_for_cpu:    TO_DEVICE: nothing;  else dcache_inval_poc
```

- **Streaming mappings transfer ownership.** Between map (or sync-for-device) and unmap (or sync-for-cpu), the buffer belongs to the device and the CPU must not touch it. The cache can still speculatively fill lines for it at any time, which is exactly why `sync_for_cpu` invalidates.
- **Coherent allocations** (`dma_alloc_coherent`) are mapped non-cacheable on non-coherent systems. They need no maintenance, only ordering: `dma_wmb()` / `dma_rmb()` between descriptor fields and ownership flags, and `writel()` (not `_relaxed`) for the doorbell that follows ring updates.

### 1.2 Addresses: masks, IOMMU, bounce buffers

| Mechanism | What it gives the device |
|---|---|
| `dma_set_mask_and_coherent(dev, DMA_BIT_MASK(n))` | A promise to the DMA layer about what the device can address; allocations and mappings respect it |
| IOMMU / SMMUv3 (`ARM_SMMU_V3`, DT `iommus`) | I/O virtual addresses per device: isolation (a bad DMA can't scribble on the kernel), and contiguous IOVA over scattered pages |
| `iommu.strict` / `IOMMU_DEFAULT_DMA_STRICT` vs `_LAZY` | Strict: unmap invalidates the IOTLB immediately (safe). Lazy: batched invalidation, faster, with a window where a device can still reach freed memory |
| `iommu.passthrough` / `IOMMU_DEFAULT_PASSTHROUGH` | 1:1 mapping: performance, no isolation |
| swiotlb (`SWIOTLB`) | Bounce buffers for devices that can't reach a buffer's physical address |

All of this works only if the driver uses `dma_addr_t` from the DMA API. A driver that writes `virt_to_phys()` into a descriptor bypasses the IOMMU, swiotlb and the mask at once. It works on the dev board without an IOMMU and fails, or corrupts, on the product that has one.

### 1.3 Contiguous memory: CMA and reserved-memory

- **The default CMA area** (`shared-dma-pool` + `reusable` + `linux,cma-default`, or `cma=` / `CMA_SIZE_MBYTES`) is lent to movable allocations. When a driver needs contiguous memory, the pages are migrated out. That costs latency and fails if pinned pages sit in the area (long-term GUP, some filesystems).
- **A dedicated pool** (`no-map` + `reg`) is never part of the kernel's linear map, so it is guaranteed but wasted when idle. A driver claims it with `memory-region` and `of_reserved_mem_device_init()`.
- **Size and place the default area deliberately.** Below 4 GiB (`alloc-ranges`) for 32-bit masters, and sized for the worst *concurrent* use (camera + display + codec), measured, not guessed.

### 1.4 DMA-BUF: one buffer, many devices

```text
 exporter (e.g. camera ISP / GPU / display, or a dma-heap)  ── dma_buf (fd to userspace)
   importer: dma_buf_attach → dma_buf_map_attachment(dir) → sg_table with the importer's DMA addresses
   CPU access from userspace: mmap + DMA_BUF_IOCTL_SYNC { DMA_BUF_SYNC_START | READ/WRITE } ... { _END }
   fences (dma_resv): who may touch the buffer now
```

**Zero-copy is achieved by never copying and never guessing ownership.** Every CPU access is bracketed by the sync ioctl, and every device access is ordered by fences (07.3 builds this).

### 1.5 SLUB and allocator hardening

- **SLUB is the only slab allocator.** v7.2 has no `SLAB` or `SLOB` Kconfig symbol.
- **Debugging and hardening:**
  - `slub_debug=FZPU` (sanity checks, red zones, poisoning, owner tracking), at a cost;
  - `KFENCE`: low-overhead sampled detection of use-after-free and out-of-bounds, suitable for production;
  - `init_on_free` / `INIT_ON_FREE_DEFAULT_ON`;
  - `SLAB_FREELIST_HARDENED`, `SLAB_FREELIST_RANDOM` (02.2 hardening).
- **Reading usage:** `/proc/slabinfo` and `slabtop`. A slab cache that grows without bound is a leak with a name.

### 1.6 The OOM killer, as arithmetic

From `mm/oom_kill.c` and `fs/proc/base.c` at v7.2:

```text
 unkillable: global init, kernel threads (oom_unkillable_task); oom_score_adj == -1000 (OOM_SCORE_ADJ_MIN)
 badness  = rss + swapents + pgtables_bytes / PAGE_SIZE  +  oom_score_adj * (totalpages / 1000)
 victim   = max badness; ties go to the LATER task (oom_evaluate_task skips only points < chosen)
 /proc/<pid>/oom_score = (1000 + badness * 1000 / totalpages) * 2 / 3
```

`oom_score_adj` is the only lever a product has, and the default (0 everywhere) means "kill the biggest". On an embedded device that is often the process that must not die mid-operation, such as the update client holding a download buffer (§2.4).

---

## 2. Production Code & Configuration Blueprints

### 2.1 The DMA contract, simulated

```python
# dma_cache_model.py - streaming DMA on a non-coherent arm64 SoC: what each DMA API call does to the cache
"""Usage: python dma_cache_model.py

Cache maintenance exactly as Linux v7.2 arch/arm64/mm/dma-mapping.c does it for a non-coherent device:
  arch_sync_dma_for_device(dir):  dcache_clean_poc   (write back dirty lines, any direction)
  arch_sync_dma_for_cpu(dir):     DMA_TO_DEVICE -> nothing;  otherwise dcache_inval_poc (drop lines)
dma_map_*/dma_sync_*_for_device call the first; dma_unmap_*/dma_sync_*_for_cpu the second.
The CPU reads and writes through a write-back cache; the device reads and writes DRAM directly. The cache may
at ANY point speculatively fill a clean line or evict a dirty one; every such point is tried. A scenario is
correct if the CPU ends with exactly the data the device wrote (RX) and the device read exactly what the CPU
wrote (TX), for every possible speculation/eviction point.
"""
import itertools


class SoC:
    def __init__(self):
        self.dram = {0: "old"}            # one cache line's worth of buffer, enough to show every effect
        self.line = None                  # None, or {"data": ..., "dirty": bool}
        self.device_saw = None

    # CPU side, through the cache
    def cpu_write(self, v):
        self.line = {"data": v, "dirty": True}

    def cpu_read(self):
        if self.line is None:
            self.line = {"data": self.dram[0], "dirty": False}
        return self.line["data"]

    # the cache acting on its own
    def speculate(self):
        if self.line is None:
            self.line = {"data": self.dram[0], "dirty": False}

    def evict(self):
        if self.line and self.line["dirty"]:
            self.dram[0] = self.line["data"]
        self.line = None

    # maintenance, as arch/arm64/mm/dma-mapping.c
    def clean(self):
        if self.line and self.line["dirty"]:
            self.dram[0] = self.line["data"]
            self.line["dirty"] = False

    def invalidate(self):
        self.line = None

    def for_device(self, direction):
        self.clean()

    def for_cpu(self, direction):
        if direction != "TO_DEVICE":
            self.invalidate()

    # the device, straight to DRAM
    def dev_write(self, v):
        self.dram[0] = v

    def dev_read(self):
        self.device_saw = self.dram[0]


SCENARIOS = {
    # name: (steps, check)
    "TX: write, map(TO_DEVICE), device reads": (
        ["cpu_write:new", "map:TO_DEVICE", "dev_read", "unmap:TO_DEVICE"], lambda s, r: s.device_saw == "new"),
    "TX bug: write AFTER map(TO_DEVICE)": (
        ["map:TO_DEVICE", "cpu_write:new", "dev_read", "unmap:TO_DEVICE"], lambda s, r: s.device_saw == "new"),
    "RX: map(FROM_DEVICE), device writes, unmap, read": (
        ["map:FROM_DEVICE", "dev_write:dma", "unmap:FROM_DEVICE", "cpu_read"], lambda s, r: r == ["dma"]),
    "RX bug: read before unmap/sync_for_cpu": (
        ["map:FROM_DEVICE", "dev_write:dma", "cpu_read", "unmap:FROM_DEVICE"], lambda s, r: r == ["dma"]),
    "RX bug: CPU writes the buffer while the device owns it": (
        ["map:FROM_DEVICE", "cpu_write:cpu", "dev_write:dma", "unmap:FROM_DEVICE", "cpu_read"],
        lambda s, r: r == ["dma"]),
    "RX ring reuse: sync_for_cpu, read, sync_for_device, again": (
        ["map:FROM_DEVICE", "dev_write:dma1", "sync_for_cpu:FROM_DEVICE", "cpu_read", "sync_for_device:FROM_DEVICE",
         "dev_write:dma2", "sync_for_cpu:FROM_DEVICE", "cpu_read"], lambda s, r: r == ["dma1", "dma2"]),
    "RX bug: ring reuse without sync_for_cpu before the 2nd read": (
        ["map:FROM_DEVICE", "dev_write:dma1", "sync_for_cpu:FROM_DEVICE", "cpu_read", "sync_for_device:FROM_DEVICE",
         "dev_write:dma2", "cpu_read"], lambda s, r: r == ["dma1", "dma2"]),
}


def run(steps, check, spec_at, evict_at):
    s, reads = SoC(), []
    for i, step in enumerate(steps):
        if i == spec_at:
            s.speculate()
        if i == evict_at:
            s.evict()
        op, _, arg = step.partition(":")
        if op == "cpu_write":
            s.cpu_write(arg)
        elif op == "cpu_read":
            reads.append(s.cpu_read())
        elif op in ("map", "sync_for_device"):
            s.for_device(arg)
        elif op in ("unmap", "sync_for_cpu"):
            s.for_cpu(arg)
        elif op == "dev_write":
            s.dev_write(arg)
        elif op == "dev_read":
            s.dev_read()
    return check(s, reads)


def main():
    fails = 0
    for name, (steps, check) in SCENARIOS.items():
        points = range(-1, len(steps))                       # -1: the event never happens
        bad = sum(not run(steps, check, sp, ev) for sp, ev in itertools.product(points, points))
        total = len(points) ** 2
        buggy = " bug" in name
        ok = (bad > 0) if buggy else (bad == 0)
        fails += not ok
        print(f"   {'ok  ' if ok else 'FAIL'} {name:<62} {bad:>2}/{total} interleavings corrupt")
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
   ok   TX: write, map(TO_DEVICE), device reads                         0/25 interleavings corrupt
   ok   TX bug: write AFTER map(TO_DEVICE)                             20/25 interleavings corrupt
   ok   RX: map(FROM_DEVICE), device writes, unmap, read                0/25 interleavings corrupt
   ok   RX bug: read before unmap/sync_for_cpu                          5/25 interleavings corrupt
   ok   RX bug: CPU writes the buffer while the device owns it          6/36 interleavings corrupt
   ok   RX ring reuse: sync_for_cpu, read, sync_for_device, again       0/81 interleavings corrupt
   ok   RX bug: ring reuse without sync_for_cpu before the 2nd read    41/64 interleavings corrupt
ALL PASSED: 0 failure(s)
```

- **Correct use is correct under every interleaving.**
- **Each misuse corrupts only under some interleavings.** Reading before `sync_for_cpu` fails in 5 of 25 here, only when the cache happened to fill the line early. That's why these bugs pass lab testing and appear as rare field corruption.

### 2.2 The RX engine driver

#### The Fragile Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_rx_fragile.c - the RX engine driver that worked on the coherent dev board and corrupts data on the product */
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/slab.h>

#define RING		64
#define BUF_SIZE	2048

struct rx_desc {
	u64 addr;
	u32 len;
	u32 flags;
};

static void __iomem *base;
static struct rx_desc *ring;
static void *buf[RING];
static unsigned int next;

static irqreturn_t rx_irq(int irq, void *data)
{
	while (!(ring[next].flags & 1)) {
		pr_info("rx %u bytes: %*ph\n", ring[next].len, 16, buf[next]);	/* stale cache lines */
		ring[next].flags = 1;
		next = (next + 1) % RING;
	}
	writel_relaxed(next, base + 0x0c);
	return IRQ_HANDLED;
}

static int rx_probe(struct platform_device *pdev)
{
	unsigned int i;

	base = devm_platform_ioremap_resource(pdev, 0);
	ring = kzalloc(RING * sizeof(*ring), GFP_KERNEL);		/* cached memory shared with a device */
	for (i = 0; i < RING; i++) {
		buf[i] = kmalloc(BUF_SIZE, GFP_KERNEL);
		ring[i].addr = virt_to_phys(buf[i]);			/* bypasses IOMMU and bounce buffers */
		ring[i].len = BUF_SIZE;
		ring[i].flags = 1;
	}
	writel_relaxed(virt_to_phys(ring), base + 0x00);
	writel_relaxed(RING, base + 0x08);
	return request_irq(platform_get_irq(pdev, 0), rx_irq, 0, "rx", NULL);
}

static const struct of_device_id rx_of_match[] = {
	{ .compatible = "acme,rx-engine" },
	{ }
};

static struct platform_driver rx_driver = {
	.probe = rx_probe,
	.driver = {
		.name = "acme-rx",
		.of_match_table = rx_of_match,
	},
};
module_platform_driver(rx_driver);
MODULE_LICENSE("GPL");
```

#### The Silicon-Hardened Production Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_rx.c - RX engine: coherent descriptor ring, streaming-mapped buffers, a reserved pool, the DMA API rules */
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/of_reserved_mem.h>
#include <linux/platform_device.h>
#include <linux/slab.h>

#define RX_RING_BASE	0x00
#define RX_RING_LEN	0x08
#define RX_DOORBELL	0x0c
#define RX_IRQ_STAT	0x10
#define RING		64
#define BUF_SIZE	2048

struct rx_desc {			/* shared with the device: lives in coherent memory */
	__le64 addr;
	__le32 len;
	__le32 flags;			/* bit 0: owned by device */
};

struct acme_rx {
	struct device *dev;
	void __iomem *base;
	struct rx_desc *ring;		/* dma_alloc_coherent: no cache maintenance, ever */
	dma_addr_t ring_dma;
	void *buf[RING];
	dma_addr_t buf_dma[RING];	/* streaming: ownership moves with dma_sync_* */
	unsigned int next;
};

static int acme_rx_refill(struct acme_rx *rx, unsigned int i)
{
	rx->buf_dma[i] = dma_map_single(rx->dev, rx->buf[i], BUF_SIZE, DMA_FROM_DEVICE);
	if (dma_mapping_error(rx->dev, rx->buf_dma[i]))
		return -ENOMEM;
	rx->ring[i].addr = cpu_to_le64(rx->buf_dma[i]);
	rx->ring[i].len = cpu_to_le32(BUF_SIZE);
	dma_wmb();			/* descriptor fields visible before ownership flips */
	rx->ring[i].flags = cpu_to_le32(1);
	return 0;
}

static irqreturn_t acme_rx_thread(int irq, void *data)
{
	struct acme_rx *rx = data;

	writel_relaxed(readl_relaxed(rx->base + RX_IRQ_STAT), rx->base + RX_IRQ_STAT);
	while (!(le32_to_cpu(READ_ONCE(rx->ring[rx->next].flags)) & 1)) {
		unsigned int i = rx->next;
		u32 len = le32_to_cpu(rx->ring[i].len);

		dma_rmb();		/* read the length only after seeing the ownership flag */
		/* The CPU owns the buffer again only after this call (arm64: invalidate to PoC). */
		dma_sync_single_for_cpu(rx->dev, rx->buf_dma[i], BUF_SIZE, DMA_FROM_DEVICE);
		print_hex_dump_debug("rx ", DUMP_PREFIX_OFFSET, 16, 1, rx->buf[i], min_t(u32, len, 64), false);
		/* Back to the device: arm64 cleans, so no dirty line can later land on top of the DMA data. */
		dma_sync_single_for_device(rx->dev, rx->buf_dma[i], BUF_SIZE, DMA_FROM_DEVICE);
		rx->ring[i].len = cpu_to_le32(BUF_SIZE);
		dma_wmb();
		rx->ring[i].flags = cpu_to_le32(1);
		rx->next = (i + 1) % RING;
	}
	writel(rx->next, rx->base + RX_DOORBELL);	/* writel: orders the ring writes before the doorbell */
	return IRQ_HANDLED;
}

static void acme_rx_unmap(void *data)
{
	struct acme_rx *rx = data;
	unsigned int i;

	for (i = 0; i < RING; i++)
		if (rx->buf_dma[i])
			dma_unmap_single(rx->dev, rx->buf_dma[i], BUF_SIZE, DMA_FROM_DEVICE);
}

static int acme_rx_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct acme_rx *rx;
	unsigned int i;
	int irq, ret;

	rx = devm_kzalloc(dev, sizeof(*rx), GFP_KERNEL);
	if (!rx)
		return -ENOMEM;
	rx->dev = dev;
	rx->base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(rx->base))
		return PTR_ERR(rx->base);

	/* The engine has 32 address bits: without this the DMA layer may hand it addresses it cannot reach. */
	ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(32));
	if (ret)
		return dev_err_probe(dev, ret, "no usable 32-bit DMA\n");
	/* Optional dedicated pool from the node's memory-region; falls back to the default CMA area. */
	ret = of_reserved_mem_device_init(dev);
	if (ret && ret != -ENODEV)
		return dev_err_probe(dev, ret, "memory-region\n");

	rx->ring = dmam_alloc_coherent(dev, RING * sizeof(*rx->ring), &rx->ring_dma, GFP_KERNEL);
	if (!rx->ring)
		return -ENOMEM;
	for (i = 0; i < RING; i++) {
		rx->buf[i] = devm_kmalloc(dev, BUF_SIZE, GFP_KERNEL);
		if (!rx->buf[i])
			return -ENOMEM;
	}
	ret = devm_add_action_or_reset(dev, acme_rx_unmap, rx);
	if (ret)
		return ret;
	for (i = 0; i < RING; i++) {
		ret = acme_rx_refill(rx, i);
		if (ret)
			return ret;
	}

	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;
	ret = devm_request_threaded_irq(dev, irq, NULL, acme_rx_thread, IRQF_ONESHOT, dev_name(dev), rx);
	if (ret)
		return ret;
	writel_relaxed(lower_32_bits(rx->ring_dma), rx->base + RX_RING_BASE);
	writel_relaxed(RING, rx->base + RX_RING_LEN);
	writel(0, rx->base + RX_DOORBELL);
	return 0;
}

static const struct of_device_id acme_rx_of_match[] = {
	{ .compatible = "acme,rx-engine" },
	{ }
};
MODULE_DEVICE_TABLE(of, acme_rx_of_match);

static struct platform_driver acme_rx_driver = {
	.probe = acme_rx_probe,
	.driver = {
		.name = "acme-rx",
		.of_match_table = acme_rx_of_match,
	},
};
module_platform_driver(acme_rx_driver);
MODULE_DESCRIPTION("Acme RX engine");
MODULE_LICENSE("GPL");
```

Both pass the API check (every call exists in v7.2). The bugs are in *how* the API is used, which this lint finds:

```python
# dma_lint.py - DMA API misuse that compiles, passes on a coherent dev board, and corrupts data on the product
"""Usage: python dma_lint.py <driver.c> ...

  D1 virt_to_phys()/__pa()/page_to_phys() handed to hardware: device addresses must be dma_addr_t from the DMA
     API (IOMMU/SMMU translation, swiotlb bouncing and address limits are all bypassed otherwise)
  D2 memory shared with a device allocated from kmalloc/kzalloc without dma_map_*: cached memory with no cache
     maintenance on a non-coherent SoC (dma_cache_model.py shows the corruption)
  D3 dma_map_single/page/sg without dma_mapping_error()
  D4 DMA used but no dma_set_mask_and_coherent()/dma_set_mask(): the device may get addresses it cannot reach
  D5 streaming mappings whose buffers the CPU touches without dma_sync_*_for_cpu()/dma_unmap_*()
  D6 a descriptor ownership flag written without dma_wmb() before it (fields may reach the device after the flag)
  D7 doorbell written with writel_relaxed() after descriptor updates: no ordering against the ring writes
"""
import re
import sys


def lint(path):
    src = re.sub(r"/\*.*?\*/", " ", open(path, encoding="utf-8").read(), flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    out = []
    for m in re.finditer(r"\b(virt_to_phys|__pa|page_to_phys)\s*\(", src):
        out.append(f"D1 line {src[:m.start()].count(chr(10)) + 1}: {m.group(1)}() used as a device address")
    uses_dma_api = bool(re.search(r"\bdma_(map|alloc|sync|unmap)_\w+\s*\(|\bdmam_alloc_coherent\s*\(", src))
    shared = re.search(r"\b(\w*(?:ring|desc)\w*)\s*=\s*k[mz]alloc\s*\(", src)
    if shared and not uses_dma_api:
        out.append(f"D2 '{shared.group(1)}' is kmalloc'd and shared with the device without any DMA mapping")
    maps = len(re.findall(r"\bdma_map_(?:single|page|sg)\s*\(", src))
    if maps and "dma_mapping_error" not in src:
        out.append(f"D3 {maps} dma_map_* call(s), no dma_mapping_error() check")
    if (uses_dma_api or re.search(r"virt_to_phys", src)) and not re.search(r"dma_set_(?:mask_and_coherent|mask)\s*\(", src):
        out.append("D4 no dma_set_mask_and_coherent(): addressing limits never declared")
    if re.search(r"\bdma_map_single\s*\(", src) and not re.search(r"dma_sync_single_for_cpu|dma_unmap_single", src):
        out.append("D5 streaming buffers mapped but never handed back to the CPU (sync_for_cpu/unmap)")
    for fn in re.finditer(r"^\w[^\n;]*\(([^)]*)\)\s*\{(.*?)^\}", src, re.M | re.S):
        body = fn.group(2)
        for fm in re.finditer(r"\.flags\s*=", body):
            if "dma_wmb" not in body[:fm.start()]:
                line = src[:fn.start(2) + fm.start()].count("\n") + 1
                out.append(f"D6 line {line}: ownership flag written with no dma_wmb() before it")
                break
        if re.search(r"\.flags\s*=|\.addr\s*=", body) and re.search(r"writel_relaxed\s*\([^;]*\)\s*;\s*(?:return|\})", body):
            line = src[:fn.start(2) + re.search(r"writel_relaxed", body).start()].count("\n") + 1
            out.append(f"D7 line {line}: doorbell writel_relaxed() after descriptor writes: use writel() or wmb()")
    return out


def main():
    total = 0
    for path in sys.argv[1:]:
        found = lint(path)
        total += len(found)
        print(f"{path.replace(chr(92), '/').rsplit('/', 1)[-1]}: {len(found)} finding(s)")
        for f in found:
            print("   ", f)
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

```text
acme_rx.c: 0 finding(s)
acme_rx_fragile.c: 8 finding(s)
    D1 line 42: virt_to_phys() used as a device address
    D1 line 46: virt_to_phys() used as a device address
    D2 'ring' is kmalloc'd and shared with the device without any DMA mapping
    D4 no dma_set_mask_and_coherent(): addressing limits never declared
    D6 line 27: ownership flag written with no dma_wmb() before it
    D7 line 30: doorbell writel_relaxed() after descriptor writes: use writel() or wmb()
    D6 line 44: ownership flag written with no dma_wmb() before it
    D7 line 46: doorbell writel_relaxed() after descriptor writes: use writel() or wmb()
acme_rx.c: 0 finding(s)
acme_rx_fragile.c: 0 finding(s)
index: 69886 function/macro names, 20008 structs from include/ and arch/arm64/include
acme-dma.dts: 8 nodes, 0 error(s)
   /soc@0/rx@30be0000: binds as 'acme,rx-engine' (data none)
acme-dma.dts x acme_rx.c: 0 finding(s)
```

### 2.3 Reserved memory

```dts
/* acme-dma.dts - reserved memory for DMA: the default CMA area and a dedicated pool for one device */
/dts-v1/;

/ {
	compatible = "acme,imx8mm-board", "fsl,imx8mm";
	#address-cells = <2>;
	#size-cells = <2>;

	memory@40000000 {
		device_type = "memory";
		reg = <0x0 0x40000000 0x0 0x20000000>;
	};

	reserved-memory {
		#address-cells = <2>;
		#size-cells = <2>;
		ranges;

		/* Default CMA area: reusable (movable pages live here until a driver needs contiguous memory),
		 * placed below 4 GiB for 32-bit masters, sized for the worst concurrent camera + display + VPU use. */
		linux,cma {
			compatible = "shared-dma-pool";
			reusable;
			size = <0x0 0x6000000>;
			alloc-ranges = <0x0 0x40000000 0x0 0x20000000>;
			linux,cma-default;
		};

		/* Dedicated pool: never mapped by the kernel's linear map, owned by one device. */
		rx_pool: rx-pool@5c000000 {
			compatible = "shared-dma-pool";
			reg = <0x0 0x5c000000 0x0 0x400000>;
			no-map;
		};
	};

	soc@0 {
		compatible = "simple-bus";
		#address-cells = <1>;
		#size-cells = <1>;
		ranges = <0x0 0x0 0x0 0x3e000000>;

		gic: interrupt-controller@38800000 {
			compatible = "arm,gic-v3";
			reg = <0x38800000 0x10000>, <0x38880000 0xc0000>;
			#interrupt-cells = <3>;
			interrupt-controller;
		};

		rx@30be0000 {
			compatible = "acme,rx-engine";
			reg = <0x30be0000 0x10000>;
			interrupt-parent = <&gic>;
			interrupts = <0 118 4>;
			memory-region = <&rx_pool>;
		};
	};
};
```

In production, size the CMA area from measurement: read `/proc/meminfo` `CmaTotal`/`CmaFree` under peak media load, plus `cma_alloc` failures in `/sys/kernel/debug/cma/`.

### 2.4 Who dies when memory runs out

#### The Fragile Way

Every service at `oom_score_adj = 0`. Under memory pressure the kernel kills the largest process. Here that's the update client mid-download, leaving a half-written slot (03.1 recovers, but the update fails fleet-wide whenever telemetry leaks).

#### The Silicon-Hardened Production Way

`oom_score_adj` per role, set in each unit (`OOMScoreAdjust=` in systemd):
- **Expendable, restartable services:** positive.
- **Services that must finish:** strongly negative.
- **The safety monitor:** −1000 (never killed). Use this sparingly: a −1000 leak is a whole-device lockup.
- **Plus memory cgroup limits per service** (`MemoryMax=`), so one leak hits its own limit first.

```python
# oom_model.py - which process the OOM killer picks, by Linux v7.2's own arithmetic
"""Usage: python oom_model.py

Mirrors mm/oom_kill.c and fs/proc/base.c at v7.2:
  oom_unkillable_task(): global init and kernel threads are never candidates
  oom_badness(): LONG_MIN if oom_score_adj == OOM_SCORE_ADJ_MIN (-1000); else
                 points = rss + swapents + pgtables_bytes / PAGE_SIZE, then points += adj * (totalpages / 1000)
  oom_evaluate_task(): skip LONG_MIN and points < chosen_points (so on a tie the LATER task is chosen)
  /proc/<pid>/oom_score = (1000 + badness * 1000 / totalpages) * 2 / 3
Device scenario: 512 MiB of RAM, no swap (4 KiB pages).
"""
LONG_MIN = -(2**63)
OOM_SCORE_ADJ_MIN = -1000
PAGE = 4096


def badness(t, totalpages):
    if t.get("init") or t.get("kthread"):
        return LONG_MIN
    if t["adj"] == OOM_SCORE_ADJ_MIN:
        return LONG_MIN
    points = t["rss"] + t.get("swap", 0) + t.get("pgtables", 0) // PAGE
    return points + t["adj"] * (totalpages // 1000)


def proc_oom_score(t, totalpages):
    b = badness(t, totalpages)
    return 0 if b == LONG_MIN else int((1000 + b * 1000 // totalpages) * 2 / 3)


def victim(tasks, totalpages):
    chosen, chosen_points = None, LONG_MIN
    for t in tasks:
        p = badness(t, totalpages)
        if p == LONG_MIN or p < chosen_points:
            continue
        chosen, chosen_points = t, p
    return chosen


def mib(n):
    return n * 1024 * 1024 // PAGE


def main():
    total = mib(512)
    fragile = [
        {"name": "systemd", "init": True, "rss": mib(12), "adj": 0},
        {"name": "acme-telemetryd", "rss": mib(96), "adj": 0},       # leaks
        {"name": "acme-update-client", "rss": mib(140), "adj": 0},   # mid-download buffer
        {"name": "acme-ui", "rss": mib(80), "adj": 0},
    ]
    hardened = [
        {"name": "systemd", "init": True, "rss": mib(12), "adj": 0},
        {"name": "acme-telemetryd", "rss": mib(96), "adj": 300},     # expendable: restarted by systemd
        {"name": "acme-update-client", "rss": mib(140), "adj": -800},  # must finish or roll back cleanly
        {"name": "acme-ui", "rss": mib(80), "adj": 0},
        {"name": "acme-safety-monitor", "rss": mib(30), "adj": OOM_SCORE_ADJ_MIN},
    ]
    fails = 0
    for label, tasks, want in (("all oom_score_adj = 0", fragile, "acme-update-client"),
                               ("adj tuned per role", hardened, "acme-telemetryd")):
        v = victim(tasks, total)
        print(f"== {label}: victim {v['name']}")
        for t in tasks:
            b = badness(t, total)
            print(f"   {t['name']:<20} rss {t['rss'] * PAGE >> 20:>4} MiB  adj {t['adj']:>5}  "
                  f"badness {'unkillable' if b == LONG_MIN else b:>10}  oom_score {proc_oom_score(t, total):>4}")
        fails += v["name"] != want
    tie = [{"name": "a", "rss": 100, "adj": 0}, {"name": "b", "rss": 100, "adj": 0}]
    fails += victim(tie, total)["name"] != "b"
    print("tie on points: the later task is chosen ->", victim(tie, total)["name"])
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
== all oom_score_adj = 0: victim acme-update-client
   systemd              rss   12 MiB  adj     0  badness unkillable  oom_score    0
   acme-telemetryd      rss   96 MiB  adj     0  badness      24576  oom_score  791
   acme-update-client   rss  140 MiB  adj     0  badness      35840  oom_score  848
   acme-ui              rss   80 MiB  adj     0  badness      20480  oom_score  770
== adj tuned per role: victim acme-telemetryd
   systemd              rss   12 MiB  adj     0  badness unkillable  oom_score    0
   acme-telemetryd      rss   96 MiB  adj   300  badness      63876  oom_score  991
   acme-update-client   rss  140 MiB  adj  -800  badness     -68960  oom_score  315
   acme-ui              rss   80 MiB  adj     0  badness      20480  oom_score  770
   acme-safety-monitor  rss   30 MiB  adj -1000  badness unkillable  oom_score    0
tie on points: the later task is chosen -> b
ALL PASSED: 0 failure(s)
```

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Mechanism | Detect | Fix |
|---|---|---|---|
| Rare corrupted frames or packets, only on the product SoC | Missing `sync_for_cpu` / CPU touching device-owned buffer; cached ring without maintenance | `CONFIG_DMA_API_DEBUG` (checks map/unmap/sync pairing); `dma_lint.py` | DMA API rules (§1.1); coherent memory for descriptors |
| Device writes land in random kernel memory | `virt_to_phys` address bypassing the SMMU; mask too large | SMMU fault logs (`arm-smmu-v3 ... event`); KASAN/KFENCE reports | `dma_addr_t` from the DMA API; `dma_set_mask_and_coherent` |
| Camera start fails after hours of uptime | CMA fragmentation / pinned pages in the CMA area | `cma_alloc` failures, `CmaFree` | Dedicated `no-map` pool for the hard requirement; size CMA from measurement; avoid long-term pins in CMA |
| Performance drop after enabling the IOMMU | Strict invalidation per unmap | `perf` on unmap paths | Map once (ring buffers), use lazy mode only where the isolation trade-off is acceptable |
| The wrong process dies under memory pressure | `oom_score_adj` all 0 | `dmesg` OOM report (`Killed process ... oom_score_adj`) | Per-role `OOMScoreAdjust`, `MemoryMax=` per service |
| Device hangs with no OOM kill | A −1000 process leaking, or memory reclaim thrashing | PSI (`/proc/pressure/memory`) | Cgroup limits; userspace OOM daemon (systemd-oomd) acting on PSI before the kernel thrashes |

**Post-mortem.**
- **Memory corruption:** enable `DMA_API_DEBUG` and KFENCE on a debug build, reproduce, and read the first report (it names the mapping and the call site).
- **OOM:** the kernel's OOM report lists every task with RSS, `pgtables_bytes`, swap and `oom_score_adj`. That's exactly the input `oom_model.py` takes, so the decision can be replayed offline.
- **No-console hangs:** pstore (04.4) preserves the log.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · "It works on the dev kit"

**Initial Prompt:** "Our capture driver works perfectly on the vendor dev kit, but on our board 1 frame in 10,000 has a corrupted stripe. Same SoC family. Diagnose."

**L5 Answer:** "Probably a signal-integrity issue on our board's camera interface. Check the MIPI lanes."

**Why L5 Bricks Devices at Scale:**
- **The frequency and shape point to cache coherency, not the lanes.** A stripe is a cache line's worth of stale data at a random position. The dev kit may have a coherent interconnect path for that master, or simply different timing for speculative fills.
- **If the driver reads the buffer before `dma_sync_*_for_cpu()`,** or writes to it while the device owns it, corruption appears only when the cache interleaves badly (§2.1: some interleavings, never all).
- **Weeks on board signal integrity** leave the bug in the code.

**L7 Principal Defense:**
- **Reason from the mechanism.** arm64 cleans on `for_device` and invalidates on `for_cpu`. Any CPU access outside the window between `for_cpu` and the next `for_device` races the cache.
- **Run with `DMA_API_DEBUG`.** Lint the driver (`dma_lint.py`).
- **Fix the ownership protocol.** Use coherent memory for descriptors, with `dma_wmb()`/`dma_rmb()` around ownership flags and `writel()` for the doorbell.
- **Verify the DT** marks only genuinely coherent masters `dma-coherent`.

### Chain 2 · Enabling the SMMU

**Initial Prompt:** "Security wants the SMMU enabled for all DMA masters. Two drivers break. Why, and is the SMMU worth it?"

**L5 Answer:** "Leave the SMMU off for those two drivers with passthrough. The SMMU mostly costs performance."

**Why L5 Bricks Devices at Scale:**
- **The two drivers that break are almost certainly the ones bypassing the DMA API:** `virt_to_phys()` in descriptors, or hard-coded physical addresses. With the SMMU on, those addresses mean nothing.
- **Passthrough hides the bug and gives up isolation exactly where it matters:** a compromised or buggy peripheral (a USB or Wi-Fi controller running vendor firmware) can DMA over the kernel.

**L7 Principal Defense:**
- **Fix the drivers** to use `dma_addr_t` from the DMA API, which is required anyway for correctness with masks and swiotlb.
- **Enable the SMMU in strict mode for untrusted masters** (network, USB, PCIe: anything running firmware we don't control).
- **Measure the cost** and reduce it by mapping long-lived rings once, rather than switching whole devices to passthrough.
- **The isolation is a core part of the threat model** that Folder 01's secure boot assumes.

### Chain 3 · CMA at hour 300

**Initial Prompt:** "After a few days of uptime, starting the camera sometimes fails with -ENOMEM even though there's plenty of free memory. Explain and fix."

**L5 Answer:** "Free memory is fragmented. Add a cron job that drops caches every hour."

**Why L5 Bricks Devices at Scale:**
- **"Free memory" isn't contiguous memory.** The camera needs a large physically contiguous (or IOMMU-contiguous) buffer.
- **If it comes from CMA,** the pages lent to movable users must migrate out, and pinned pages (long-term GUP, certain drivers or filesystems) can't move. Dropping caches doesn't unpin anything, and it costs I/O on every device.

**L7 Principal Defense:**
- **Diagnose** with `cma_alloc` failure counters and `CmaFree`, then find the pinned pages.
- **Fix structurally:**
  - a dedicated `no-map` pool for the camera's guaranteed minimum;
  - CMA sized for measured concurrent peaks;
  - no long-term pinning of CMA pages;
  - or an IOMMU so the device doesn't need physical contiguity at all.
- **Add a soak test** that starts the camera after days of synthetic load.

### Chain 4 · Who should the OOM killer kill?

**Initial Prompt:** "Under a memory leak in telemetry, devices lose an in-progress update. Why, and how do you design memory policy for a device?"

**L5 Answer:** "Fix the leak. Memory policy isn't needed if there are no leaks."

**Why L5 Bricks Devices at Scale:**
- **There will always be a next leak.** With `oom_score_adj = 0` everywhere, the kernel kills the largest process: the update client holding its download buffer, not the leaking daemon (§2.4).
- **Without cgroup limits** the leak consumes everything first.

**L7 Principal Defense:**
- **Policy by role:**
  - expendable, restartable services have positive `OOMScoreAdjust`;
  - critical transactional services have strongly negative values;
  - the minimal safety monitor sits at −1000;
  - every service has a `MemoryMax=`.
- **Use PSI-based userspace OOM handling** (systemd-oomd) to act before the kernel thrashes.
- **Replay real OOM reports** through the kernel's arithmetic (`oom_model.py`) to verify the policy.

### Chain 5 · Zero-copy across camera, GPU and display

**Initial Prompt:** "Design the buffer path from camera to GPU to display with no copies."

**L5 Answer:** "Allocate a big buffer, mmap it everywhere, and pass the pointer around."

**Why L5 Bricks Devices at Scale:**
- **Each device needs its own DMA address,** possibly through its own SMMU context.
- **The CPU's mapping needs coherency management.**
- **Ownership between devices needs fences.**
- **A shared pointer has none of that:** tearing, stale frames, and SMMU faults appear under load.

**L7 Principal Defense:**
- **Use DMA-BUF.** One exporter (dma-heap or the producing driver). Each consumer attaches and maps through its own device, getting its own `sg_table` and addresses.
- **Bracket userspace CPU access** with `DMA_BUF_IOCTL_SYNC` start and end.
- **Express producer/consumer ordering with dma-fences** (`dma_resv`).
- **Allocate where every consumer can reach:** check masks and IOMMU domains.
- **07.3 implements the driver side.**

### Chain 6 · Debugging memory corruption in production

**Initial Prompt:** "A rare kernel crash looks like a use-after-free. We can't reproduce it in the lab. What do you ship?"

**L5 Answer:** "Enable KASAN on all devices and wait for the next crash."

**Why L5 Bricks Devices at Scale:** KASAN's memory and CPU overhead (2–3× slowdown, about 1/8 of RAM for shadow memory) is unacceptable on production devices. Shipping it changes timing so much that the bug may disappear, while performance and memory problems appear.

**L7 Principal Defense:**
- **Ship KFENCE.** It is sampling-based, with negligible overhead, designed for production, and catches use-after-free and out-of-bounds with a full report.
- **Add `init_on_free`** (already in the hardening fragment) to turn some use-after-free cases into deterministic zeros.
- **Persist the report across the crash** with pstore (04.4).
- **Set up a fleet pipeline** that symbolizes reports against the release's debug symbols (02.3).
- **Reproduce in the lab with KASAN,** using the KFENCE report's call stacks.

---

## 5. Invariants Checklist

- [ ] Device addresses only from the DMA API; `dma_set_mask_and_coherent` in every DMA driver; `dma_mapping_error` checked.
- [ ] Streaming buffers: CPU access only between `sync_for_cpu`/unmap and the next `sync_for_device`/map; descriptors in coherent memory with `dma_wmb`/`dma_rmb`; `writel` for doorbells.
- [ ] `dma-coherent` in DT only for genuinely coherent masters; `DMA_API_DEBUG` in debug builds.
- [ ] SMMU on, strict mode, for every master running firmware we don't control.
- [ ] CMA sized from measured concurrent peaks, below 4 GiB for 32-bit masters; dedicated `no-map` pools for hard guarantees.
- [ ] `OOMScoreAdjust` and `MemoryMax` per service; −1000 only for the minimal safety monitor; PSI-based userspace OOM handling.
- [ ] KFENCE and `init_on_free` in production; pstore to keep the report.

## 6. References

- Linux v7.2: `arch/arm64/mm/dma-mapping.c`, `kernel/dma/`, `mm/oom_kill.c`, `fs/proc/base.c`, `include/uapi/linux/dma-buf.h`; `Documentation/core-api/dma-api.rst`, `dma-api-howto.rst`; `Documentation/devicetree/bindings/reserved-memory/`. <https://github.com/torvalds/linux/tree/v7.2>
- Kernel documentation: DMA-BUF and dma-fence (`Documentation/driver-api/dma-buf.rst`), KFENCE (`Documentation/dev-tools/kfence.rst`), CMA (`Documentation/admin-guide/mm/cma_debugfs.rst`). <https://docs.kernel.org/>
- Arm SMMUv3 architecture specification (IHI 0070).
- In this KB: [04.1 drivers and kapi_check](01-kernel-boot-flow-device-tree-of-matching-pinmux-and-common-clock-framework.md) · [04.4 pstore](04-high-speed-peripherals-pcie-nvme-mipi-i2c-spi-regmap-and-pstore-ramoops.md) · 07.3 (zero-copy DMA-BUF driver, Folder 07)
