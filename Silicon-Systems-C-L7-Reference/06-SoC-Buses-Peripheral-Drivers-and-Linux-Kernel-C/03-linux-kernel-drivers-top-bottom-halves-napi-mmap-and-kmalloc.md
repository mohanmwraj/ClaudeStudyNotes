# 03 · Linux Kernel Drivers: Top/Bottom Halves, NAPI, `mmap`, and `kmalloc`

> **Folder:** `06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/` · **File 3 of 3**
> **Anchors:**
> - Linux `Documentation/driver-api/` (driver model, `devres`), `Documentation/core-api/genericirq.rst`, `Documentation/networking/napi.rst`, `Documentation/core-api/dma-api.rst`, `Documentation/core-api/memory-allocation.rst`, `Documentation/mm/`.
> - J. Corbet, A. Rubini, G. Kroah-Hartman, *Linux Device Drivers, 3rd ed.* (concepts; APIs since changed).
> - LWN articles on threaded interrupts, NAPI, the BH workqueue, and `vm_flags_set`.
>
> **Verification status: ⚠ READ THIS.** No Linux kernel source tree was available on the build machine, so **the kernel code in this file was not compiled here**. That's the only exception to the KB's compile-everything rule.
> - The code is written against **Linux 6.x mainline APIs**, and every version-sensitive API is marked ⚠ verify.
> - To build it, put the driver in a directory with `obj-m := l7dev.o` in a `Kbuild` file, then run `make -C /lib/modules/$(uname -r)/build M=$PWD modules`.
> - The *concepts* (ordering, DMA, interrupts) are the same ones verified in Folders 03–05.

---

## 0. The thesis

A Linux driver runs in up to four execution contexts with different rules: hard IRQ, softirq/BH, process context, and atomic sections. Most driver bugs are context bugs:

- sleeping in atomic context;
- taking a spinlock without disabling the IRQ that also takes it;
- allocating with `GFP_KERNEL` from an interrupt;
- touching a DMA buffer the device still owns.

The kernel's frameworks (threaded IRQs, NAPI, the DMA API, `devres`) exist to make the correct context discipline the easy path.

---

## 1. First-Principles Mechanics

### 1.1 Execution contexts

| Context | Entered via | May sleep? | Preemptible? | Allocation | Locks |
|---|---|---|---|---|---|
| **Hard IRQ** (top half) | Device interrupt | ❌ | ❌ (local IRQs masked on this line; nested IRQs typically disabled) | `GFP_ATOMIC` only | `spin_lock` (IRQ already off) |
| **Softirq / BH** | `raise_softirq`, NAPI poll (`NET_RX_SOFTIRQ`), tasklets, BH workqueues | ❌ | ❌ (runs on IRQ exit or in `ksoftirqd`) | `GFP_ATOMIC` | `spin_lock_bh` from process context to exclude BHs |
| **Process context** (syscalls, kthreads, workqueues, **threaded IRQ handlers**) | System call, `kthread_run`, `queue_work`, `request_threaded_irq` thread | ✅ | ✅ | `GFP_KERNEL` | mutexes, semaphores, `spin_lock_irqsave` if shared with hard IRQ |
| **Atomic section** inside any context | `spin_lock`, `preempt_disable`, `rcu_read_lock` (classic) | ❌ | ❌ | `GFP_ATOMIC` / `GFP_NOWAIT` | (nesting rules) |

`might_sleep()` and `CONFIG_DEBUG_ATOMIC_SLEEP` turn "sleeping in atomic context" into an immediate splat at the call site. `lockdep` (`CONFIG_PROVE_LOCKING`) catches IRQ-safety inversions, such as "lock L taken in hard IRQ and in process context without irqsave". Enable both in every driver development config.

### 1.2 Top half / bottom half

The **top half** (hard IRQ handler) must:
1. confirm the interrupt is ours (shared lines: return `IRQ_NONE` otherwise);
2. **acknowledge or mask it at the device**, with a read-back if the bus posts writes (File 01 §1.2);
3. capture minimal state;
4. defer everything else.

Deferral mechanisms:

| Mechanism | Context | Use |
|---|---|---|
| **Threaded IRQ** (`request_threaded_irq`, `IRQF_ONESHOT`) | A dedicated kernel thread per IRQ (process context, can sleep, RT-schedulable) | **Default choice** for non-network devices: I²C/SPI controllers, sensors, slow-path work. `IRQF_ONESHOT` keeps the line masked until the thread finishes (required for level-triggered lines with a NULL or quick primary handler) |
| **NAPI** | `NET_RX` softirq (or threaded NAPI) | Network RX/TX completion with interrupt mitigation (§1.3) |
| Workqueue (`queue_work`) | kworker threads (process context) | Deferred maintenance, sleeping operations |
| Tasklet | Softirq | Legacy. Being replaced by **BH workqueues** (`WQ_BH`, 6.9+; ⚠ verify) |
| Softirq directly | Softirq | Core subsystems only (net, block, timers, RCU) |

### 1.3 NAPI: interrupt mitigation by switching to polling

At high packet rates, one interrupt per packet is a **livelock** (receive livelock: the CPU spends all its time entering interrupts). NAPI works like this:

1. The first packet raises the interrupt. The handler **disables the device's RX interrupt** and calls `napi_schedule()`.
2. The NET_RX softirq calls the driver's `poll(napi, budget)`. It processes up to `budget` packets (default 64) from the RX ring.
3. If it processed fewer than `budget`, the ring is drained: it calls `napi_complete_done()` and **re-enables the RX interrupt**.
4. If it used the whole budget, more work remains. It stays scheduled and is polled again, which bounds latency for other softirqs. The kernel moves excess work to `ksoftirqd`.

This is the same idea as Folder 04's GIC drain loop and Cortex-M tail-chaining: amortize the entry cost over a batch. Add-ons:
- **GRO** (`napi_gro_receive`) coalesces TCP segments;
- **page_pool** recycles RX buffers without reallocation or DMA re-mapping;
- **busy polling** (`SO_BUSY_POLL`) lets latency-critical sockets poll from process context;
- **threaded NAPI** (`/sys/class/net/<if>/threaded`) moves polling into schedulable threads.

### 1.4 `kmalloc` and friends

| Allocator | Returns | Physically contiguous | DMA-able | Notes |
|---|---|---|---|---|
| `kmalloc(size, gfp)` / `kzalloc` | Slab object from size classes (`kmalloc-8` … `kmalloc-8k`, larger from the page allocator) | ✅ | ✅ via the DMA API (`ARCH_DMA_MINALIGN` alignment, Folder 03) | The default for small objects. `kmalloc_array`/`kcalloc` and `struct_size()` are **overflow-checked** (Folder 01 File 02) |
| `kmem_cache_create` + `kmem_cache_alloc` | Objects from a dedicated slab cache | ✅ | ✅ | Hot fixed-size objects (Folder 05's pools, kernel-grade); constructor, alignment, `SLAB_HWCACHE_ALIGN` |
| `vmalloc` / `kvmalloc` | Virtually contiguous pages | ❌ | ⚠ not directly (needs scatter-gather mapping) | Large buffers; `kvmalloc` tries `kmalloc` first |
| `alloc_pages(gfp, order)` | 2^order pages (buddy allocator) | ✅ | ✅ | Page-granular buffers; `order > 3` may fail under fragmentation (the Folder 05 lesson at kernel scale) |
| `dma_alloc_coherent(dev, size, &dma, gfp)` | Memory **coherent with the device**: uncached on non-coherent SoCs, or IOMMU-mapped | ✅ (in IOVA space) | ✅ | Descriptor rings, mailboxes |
| `devm_kzalloc` / `dmam_alloc_coherent` | Same, **freed automatically** when the device unbinds | as above | as above | Removes most error-path leaks |

**GFP flags:**
- `GFP_KERNEL` may sleep (reclaim, I/O), so it's process context only.
- `GFP_ATOMIC` never sleeps and dips into reserves: IRQ, softirq, spinlock-held code.
- `GFP_NOWAIT` never sleeps and has no reserves.
- `__GFP_ZERO`; `GFP_DMA32` (the zone below 4 GB, for 32-bit DMA devices without an IOMMU).

Debugging: `CONFIG_SLUB_DEBUG` (`slub_debug=FZPU`) gives red zones and poisoning, **KASAN** catches out-of-bounds and use-after-free, and **KFENCE** samples the same at low production overhead.

### 1.5 `mmap` from a driver

| Mapping | API | Page protection |
|---|---|---|
| MMIO registers to user space (UIO-style) | `io_remap_pfn_range(vma, vma->vm_start, pfn, size, pgprot_noncached(vma->vm_page_prot))` | Device / UC |
| A write-combining BAR (framebuffer, GPU aperture) | Same with `pgprot_writecombine()` | Normal-NC / WC |
| A DMA coherent buffer | **`dma_mmap_coherent(dev, vma, cpu_addr, dma_addr, size)`** | Matches the kernel mapping's coherence attributes (this matters: mismatched attributes for the same physical page are architecturally forbidden on ARM) |
| Kernel pages (`alloc_pages`) | `vm_insert_page` / `vm_map_pages` | Normal |

Validate `vma->vm_pgoff` and the size against the buffer, and set `VM_IO | VM_DONTEXPAND | VM_DONTDUMP` through **`vm_flags_set(vma, ...)`** (6.3+; older kernels modified `vma->vm_flags` directly, ⚠ verify).

---

## 2. Production Blueprints (written for Linux 6.x; ⚠ not compiled here)

### 2.1 The Subtle Buggy Way

```c
/* l7bad.c - compiles on most kernels; breaks under load, on unbind, or on ARM. */
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/slab.h>

struct l7bad { void __iomem *base; u32 *buf; spinlock_t lock; int irq; };

static irqreturn_t l7bad_irq(int irq, void *data)
{
    struct l7bad *p = data;
    u32 *tmp = kmalloc(4096, GFP_KERNEL);      /* BUG 1: may sleep in hard-IRQ context        */
    spin_lock(&p->lock);                       /* BUG 2: process context takes this lock with  */
    memcpy(tmp, p->buf, 4096);                 /*        plain spin_lock -> deadlock if the IRQ */
    spin_unlock(&p->lock);                     /*        fires while it is held on this CPU     */
    msleep(1);                                 /* BUG 3: sleeping in hard IRQ                 */
    writel(1, p->base + 0x20);                 /* BUG 4: ack LAST, no read-back (File 01)      */
    kfree(tmp);
    return IRQ_HANDLED;                        /* BUG 5: unconditional on a shared line        */
}

static int l7bad_probe(struct platform_device *pdev)
{
    struct l7bad *p = kzalloc(sizeof(*p), GFP_KERNEL);   /* BUG 6: no devm, leaks on error paths */
    p->base = ioremap(0x40011000, 0x100);      /* BUG 7: hard-coded address, not from DT/ACPI   */
    p->buf = kmalloc(4096, GFP_KERNEL);        /* BUG 8: given to the device via virt_to_phys -> */
    writel(virt_to_phys(p->buf), p->base + 0x10);   /*   bypasses the IOMMU and cache maintenance */
    p->irq = platform_get_irq(pdev, 0);
    request_irq(p->irq, l7bad_irq, IRQF_SHARED, "l7bad", p);  /* BUG 9: return value ignored;  */
    return 0;                                  /*        IRQ requested before the device is quiet */
}
```

### 2.2 The Silicon-Hardened Production Way: a platform driver with a threaded IRQ, a coherent DMA ring, and `mmap`

```c
// SPDX-License-Identifier: GPL-2.0
/* l7dev.c - platform driver for a hypothetical DMA-capable sensor/accelerator
 * ("l7kb,demo-dma"): threaded IRQ, coherent DMA ring, misc char device with
 * read()/poll()/mmap(). Written for Linux 6.x mainline (see the version notes). */
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/miscdevice.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/poll.h>
#include <linux/uaccess.h>
#include <linux/wait.h>

#define L7_REG_CTRL      0x00   /* [0] EN, [1] IRQ_EN                    */
#define L7_REG_STATUS    0x04   /* [0] DONE (W1C), [31] ERROR (W1C)      */
#define L7_REG_RING_LO   0x10   /* ring bus address (IOVA), low 32 bits  */
#define L7_REG_RING_HI   0x14
#define L7_REG_HEAD      0x18   /* device-written producer index         */
#define L7_CTRL_EN       BIT(0)
#define L7_CTRL_IRQ_EN   BIT(1)
#define L7_ST_DONE       BIT(0)
#define L7_ST_ERR        BIT(31)
#define L7_RING_BYTES    (64 * 1024)

struct l7dev {
    struct device      *dev;
    void __iomem       *base;
    void               *ring;            /* CPU address of the coherent ring  */
    dma_addr_t          ring_dma;        /* device (IOVA) address              */
    int                 irq;
    spinlock_t          lock;            /* protects head/tail vs the IRQ path */
    u32                 head, tail;
    wait_queue_head_t   wq;
    struct miscdevice   misc;
};

/* Top half: confirm it is ours, quiet the device, hand off. Never sleeps. */
static irqreturn_t l7_irq_top(int irq, void *data)
{
    struct l7dev *l = data;
    u32 st = readl(l->base + L7_REG_STATUS);

    if (!(st & (L7_ST_DONE | L7_ST_ERR)))
        return IRQ_NONE;                                  /* shared line: not us */
    writel(st & (L7_ST_DONE | L7_ST_ERR), l->base + L7_REG_STATUS);  /* W1C exactly what we saw */
    (void)readl(l->base + L7_REG_STATUS);                 /* flush the posted write (File 01) */
    return IRQ_WAKE_THREAD;
}

/* Bottom half (threaded, process context): may sleep, takes the lock with
 * irqsave because nothing else here runs in hard IRQ - but stay correct if a
 * future change adds hard-IRQ users. */
static irqreturn_t l7_irq_thread(int irq, void *data)
{
    struct l7dev *l = data;
    unsigned long flags;
    u32 head = readl(l->base + L7_REG_HEAD);   /* device's producer index (readl orders vs DMA) */

    spin_lock_irqsave(&l->lock, flags);
    l->head = head;
    spin_unlock_irqrestore(&l->lock, flags);
    wake_up_interruptible(&l->wq);
    return IRQ_HANDLED;
}

static bool l7_has_data(struct l7dev *l)
{
    unsigned long flags;
    bool ret;

    spin_lock_irqsave(&l->lock, flags);
    ret = (l->head != l->tail);
    spin_unlock_irqrestore(&l->lock, flags);
    return ret;
}

static ssize_t l7_read(struct file *f, char __user *ubuf, size_t len, loff_t *off)
{
    struct l7dev *l = container_of(f->private_data, struct l7dev, misc);
    unsigned long flags;
    u32 head, tail, avail;
    int ret;

    ret = wait_event_interruptible(l->wq, l7_has_data(l));
    if (ret)
        return ret;                                     /* -ERESTARTSYS on a signal */
    spin_lock_irqsave(&l->lock, flags);
    head = l->head;
    tail = l->tail;
    spin_unlock_irqrestore(&l->lock, flags);

    avail = head - tail;                                 /* free-running u32 indices: a FULL ring
                                                          * reads L7_RING_BYTES, not 0 (Folder 05) */
    avail = min_t(u32, avail, L7_RING_BYTES - (tail % L7_RING_BYTES)); /* contiguous part */
    len = min_t(size_t, len, avail);
    dma_rmb();                                           /* index observed before data (Folder 03) */
    if (copy_to_user(ubuf, (u8 *)l->ring + (tail % L7_RING_BYTES), len))
        return -EFAULT;

    spin_lock_irqsave(&l->lock, flags);
    l->tail = tail + (u32)len;
    spin_unlock_irqrestore(&l->lock, flags);
    return len;
}

static __poll_t l7_poll(struct file *f, poll_table *pt)
{
    struct l7dev *l = container_of(f->private_data, struct l7dev, misc);

    poll_wait(f, &l->wq, pt);
    return l7_has_data(l) ? (EPOLLIN | EPOLLRDNORM) : 0;
}

/* Zero-copy view of the ring for user space, with the SAME memory attributes
 * as the kernel's coherent mapping (mismatched aliases are forbidden on ARM). */
static int l7_mmap(struct file *f, struct vm_area_struct *vma)
{
    struct l7dev *l = container_of(f->private_data, struct l7dev, misc);
    size_t size = vma->vm_end - vma->vm_start;

    if (vma->vm_pgoff != 0 || size > L7_RING_BYTES)
        return -EINVAL;
    vm_flags_set(vma, VM_DONTEXPAND | VM_DONTDUMP);     /* 6.3+ API (⚠ verify) */
    return dma_mmap_coherent(l->dev, vma, l->ring, l->ring_dma, size);
}

static const struct file_operations l7_fops = {
    .owner  = THIS_MODULE,
    .read   = l7_read,
    .poll   = l7_poll,
    .mmap   = l7_mmap,
    .llseek = noop_llseek,
};

static int l7_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct l7dev *l;
    int ret;

    l = devm_kzalloc(dev, sizeof(*l), GFP_KERNEL);
    if (!l)
        return -ENOMEM;
    l->dev = dev;
    spin_lock_init(&l->lock);
    init_waitqueue_head(&l->wq);

    l->base = devm_platform_ioremap_resource(pdev, 0);  /* address from DT/ACPI, Device-nGnRE */
    if (IS_ERR(l->base))
        return PTR_ERR(l->base);

    writel(0, l->base + L7_REG_CTRL);                   /* quiesce BEFORE requesting the IRQ */
    writel(L7_ST_DONE | L7_ST_ERR, l->base + L7_REG_STATUS);

    ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(64));
    if (ret)
        ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(32));
    if (ret)
        return dev_err_probe(dev, ret, "no usable DMA mask\n");

    l->ring = dmam_alloc_coherent(dev, L7_RING_BYTES, &l->ring_dma, GFP_KERNEL);
    if (!l->ring)
        return -ENOMEM;

    l->irq = platform_get_irq(pdev, 0);
    if (l->irq < 0)
        return l->irq;
    ret = devm_request_threaded_irq(dev, l->irq, l7_irq_top, l7_irq_thread,
                                    IRQF_ONESHOT | IRQF_SHARED, dev_name(dev), l);
    if (ret)
        return dev_err_probe(dev, ret, "irq %d\n", l->irq);

    writel(lower_32_bits(l->ring_dma), l->base + L7_REG_RING_LO);  /* IOVA, not a phys addr */
    writel(upper_32_bits(l->ring_dma), l->base + L7_REG_RING_HI);
    writel(L7_CTRL_EN | L7_CTRL_IRQ_EN, l->base + L7_REG_CTRL);     /* writel orders after the ring setup */

    l->misc.minor = MISC_DYNAMIC_MINOR;
    l->misc.name  = "l7dev";
    l->misc.fops  = &l7_fops;
    l->misc.parent = dev;
    ret = misc_register(&l->misc);
    if (ret) {
        writel(0, l->base + L7_REG_CTRL);
        return ret;
    }
    platform_set_drvdata(pdev, l);
    return 0;
}

static void l7_remove(struct platform_device *pdev)     /* void since 6.11 (⚠ verify) */
{
    struct l7dev *l = platform_get_drvdata(pdev);

    misc_deregister(&l->misc);
    writel(0, l->base + L7_REG_CTRL);                   /* stop DMA before devres frees the ring */
    (void)readl(l->base + L7_REG_CTRL);
    /* IRQ, ring, mapping and l itself are released by devres, in reverse order */
}

static const struct of_device_id l7_of_match[] = {
    { .compatible = "l7kb,demo-dma" },
    { }
};
MODULE_DEVICE_TABLE(of, l7_of_match);

static struct platform_driver l7_driver = {
    .probe  = l7_probe,
    .remove = l7_remove,
    .driver = {
        .name = "l7dev",
        .of_match_table = l7_of_match,
    },
};
module_platform_driver(l7_driver);

MODULE_DESCRIPTION("L7 KB demo DMA device");
MODULE_LICENSE("GPL");
```

The decisions that matter, and where each is grounded in this KB:

| Decision | Why |
|---|---|
| Top half: `IRQ_NONE` if not ours, W1C exactly the bits seen, **read-back**, `IRQ_WAKE_THREAD` | Shared lines; W1C semantics (Folder 01 File 02); posted writes (File 01 §1.2) |
| `IRQF_ONESHOT` | The line stays masked until the thread finishes. That's required when the thread does the real work for a level-triggered source |
| Quiesce the device **before** `request_irq` | An interrupt pending from firmware or a previous driver instance would otherwise fire into half-initialized state |
| `dma_set_mask_and_coherent` with 64 → 32 fallback; `dmam_alloc_coherent` | The DMA API yields an IOVA (SMMU-aware) and coherent attributes (Folder 03 File 03, File 01 §1.7) |
| `dma_rmb()` between reading the device index and reading ring data | Index before payload: the MP pattern (Folder 03), in the device direction |
| `dma_mmap_coherent` for user mapping | Same attributes as the kernel alias; zero-copy |
| `devm_*` everywhere; explicit stop in `remove` before devres frees the ring | No leaks on error paths; the device must not DMA into freed memory (stop, then free) |
| `spin_lock_irqsave` for state shared with the IRQ path | Lockdep-clean if hard-IRQ users are ever added |

**Version notes (⚠ verify against your target kernel):**
- `struct platform_driver.remove` returns `void` since 6.11 (6.3–6.10 used `.remove_new`).
- `vm_flags_set()` was introduced in 6.3.
- `netif_napi_add()` lost its `weight` argument in 6.1.
- `devm_platform_ioremap_resource()` exists since 5.1.

### 2.3 The NAPI RX skeleton (network drivers; ⚠ not compiled here)

```c
/* l7net_napi.c - the canonical NAPI structure (excerpted from a full netdev
 * driver: ring setup, TX path and ethtool ops omitted). Linux 6.x. */
static irqreturn_t l7net_irq(int irq, void *data)
{
    struct l7net *n = data;
    u32 st = readl(n->base + NET_ISR);

    if (!(st & NET_ISR_RX))
        return IRQ_NONE;
    writel(NET_ISR_RX, n->base + NET_ISR);          /* ack (W1C) */
    if (napi_schedule_prep(&n->napi)) {
        writel(0, n->base + NET_RX_IRQ_EN);         /* 1. device RX IRQ OFF while polling */
        __napi_schedule(&n->napi);
    }
    return IRQ_HANDLED;
}

static int l7net_poll(struct napi_struct *napi, int budget)
{
    struct l7net *n = container_of(napi, struct l7net, napi);
    int done = 0;

    while (done < budget) {
        struct l7net_rxd *d = &n->rx_ring[n->rx_tail % L7NET_RXQ];
        u32 status = le32_to_cpu(READ_ONCE(d->status));   /* descriptors are little-endian */

        if (!(status & RXD_OWN_HOST))
            break;                                  /* 2. ring drained */
        dma_rmb();                                  /*    status before length/data */
        dma_sync_single_for_cpu(n->dev, n->rx_dma[n->rx_tail % L7NET_RXQ],
                                L7NET_BUF, DMA_FROM_DEVICE);
        /* build skb (or use page_pool), set protocol, hand to GRO */
        l7net_rx_one(n, d, napi);                   /* -> napi_gro_receive(napi, skb) */
        l7net_refill(n, n->rx_tail);                /* give a fresh buffer back: dma_wmb() + OWN_DEV */
        n->rx_tail++;
        done++;
    }
    if (done < budget && napi_complete_done(napi, done))
        writel(1, n->base + NET_RX_IRQ_EN);         /* 3. IRQ back ON only if NAPI really completed */
    return done;                                    /* 4. done == budget -> stay scheduled */
}

/* in probe: netif_napi_add(ndev, &n->napi, l7net_poll);   (6.1+: no weight arg; ⚠ verify) */
```

Two key details. Re-enabling the interrupt happens **only** when `napi_complete_done()` returns true, because the kernel may have kept the NAPI instance scheduled (busy polling, GRO flush). And the `dma_rmb()` after observing ownership is the same index-before-data rule as everywhere else in this KB.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| `BUG: sleeping function called from invalid context` | `GFP_KERNEL`, `msleep`, `mutex_lock` in hard IRQ / softirq / under a spinlock | `CONFIG_DEBUG_ATOMIC_SLEEP`; the splat gives the exact call chain |
| `inconsistent {HARDIRQ-ON-W} -> {IN-HARDIRQ-W} usage` | Lock taken in hard IRQ and in process context without `irqsave` | lockdep (`CONFIG_PROVE_LOCKING`) |
| Soft lockups or high `si` time at high packet rates | IRQ per packet, no NAPI, or NAPI never completing | `/proc/interrupts` rates, `mpstat -P ALL` (`%soft`), `perf top` in the poll function |
| Data corruption only on ARM SoCs, not x86 | Missing `dma_rmb`/`dma_wmb`, or a non-coherent device without the DMA API's maintenance | `CONFIG_DMA_API_DEBUG`; run on the target; Folder 03 checklists |
| SMMU translation faults in `dmesg` | Physical addresses given to the device, or use after unmap | The SMMU event decode (StreamID, IOVA); audit `dma_map`/`unmap` pairs |
| Use-after-free on `rmmod` / unbind | DMA or IRQ still active while devres frees memory | Stop the device in `.remove` before return; KASAN; `echo <dev> > unbind` stress loops |
| `mmap`'d buffer shows stale data in user space | Attribute mismatch (kernel uncached, user cached) | Use `dma_mmap_coherent`; never `remap_pfn_range` a coherent buffer with default cached protections |

Kernel tracing: `ftrace` function graph on the driver's functions; the `irq:irq_handler_entry/exit` and `napi:napi_poll` tracepoints; `trace-cmd record -e irq -e napi`; `bpftrace` one-liners for latency histograms of the handler.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Top half vs. bottom half: what goes where, and which bottom-half mechanism do you pick?"

- **L5:** "Top half is fast, bottom half is slow; use a tasklet."
- **Why L5 fails:** Tasklets are legacy (BH workqueues are replacing them), they run in softirq context (no sleeping), and they serialize per tasklet. The real decision is about **context requirements**.
- **L7 principal defense:**
  - **Top half:** confirm ownership, W1C-ack with a read-back, capture, return `IRQ_WAKE_THREAD` or schedule NAPI.
  - **Threaded IRQ** (`IRQF_ONESHOT`) for most devices: it can sleep, it's RT-schedulable, and it has its own priority.
  - **NAPI** for network RX/TX completion (batching, budget, GRO).
  - **Workqueues** for long or sleeping maintenance.
  - The code in §2.2 shows the threaded pattern end to end.

### Q2 🔥 "Explain NAPI. Why does it re-enable interrupts only on `napi_complete_done() == true`?"

- **L5:** "NAPI polls instead of interrupting."
- **Why L5 fails:** It misses the *mitigation dynamics*. An IRQ per packet means livelock at high rates, so NAPI switches to polling under load and back to interrupts when idle. The budget bounds the softirq time. Re-enabling interrupts while the kernel still considers the NAPI instance scheduled (busy-poll, GRO) causes races and duplicate scheduling.
- **L7 defense:** The skeleton (§2.3):
  - IRQ → device RX IRQ off → schedule;
  - poll up to budget with `dma_rmb()` after the ownership check;
  - `dma_sync_single_for_cpu` (or page_pool) for buffers;
  - refill with `dma_wmb()` and OWN;
  - complete and re-enable conditionally.
  
  Add interrupt coalescing in hardware, and threaded NAPI for RT workloads.

### Q3 "`kmalloc` vs `vmalloc` vs `dma_alloc_coherent`: when?"

- **L5:** "`kmalloc` for small, `vmalloc` for large."
- **Why L5 fails:** The axes are **physical contiguity** and **device coherence**, not just size:
  - `vmalloc` memory isn't physically contiguous, so the device can't DMA to it without scatter-gather mapping;
  - `kmalloc` memory is contiguous, but needs streaming DMA maps (and is subject to `ARCH_DMA_MINALIGN` and bouncing);
  - `dma_alloc_coherent` gives device-coherent memory for rings.
- **L7 defense:** The table (§1.4), GFP-by-context, overflow-checked size helpers, `devm_`/`dmam_` lifetimes, dedicated `kmem_cache` for hot objects, and the debugging stack (SLUB debug, KASAN, KFENCE).

### Q4 🧊 "Your driver `mmap`s a DMA buffer to user space and users see stale data on an ARM board. Why?"

- **L5:** "Add cache flushes in user space."
- **Why L5 fails:** The kernel mapped the buffer **uncached** (coherent allocation on a non-coherent SoC), but the driver used `remap_pfn_range` with default (cached) protections, creating two mappings with **mismatched attributes for one physical page**. That's architecturally forbidden on ARM (loss of coherency, unpredictable results).
- **L7 defense:** `dma_mmap_coherent()` (verified in the pattern above) picks matching attributes. For MMIO use `io_remap_pfn_range` with `pgprot_noncached`, and for WC apertures `pgprot_writecombine`. Validate offset and size, and set `VM_DONTEXPAND | VM_DONTDUMP`.

### Q5 "What can go wrong on driver unbind or module removal, and how does devres help?"

- **L5:** "Free everything in `remove`."
- **Why L5 fails:** *Order* matters. The device may still be DMAing into the ring, or raise an interrupt, while memory is freed. Use-after-free by hardware isn't caught by KASAN.
- **L7 defense:**
  - Stop the device first (disable DMA and IRQ at the device, read back) in `.remove`.
  - Then devres releases resources in reverse order of acquisition: IRQ, then the coherent ring, then the mapping, then the allocation.
  - Quiesce *before* `request_irq` in probe.
  - Stress with unbind/bind loops under traffic, with KASAN and `DMA_API_DEBUG` enabled.

---

## 5. Invariants Checklist

- [ ] No sleeping or `GFP_KERNEL` in hard IRQ, softirq or under spinlocks; `DEBUG_ATOMIC_SLEEP` and lockdep enabled in development configs.
- [ ] Top halves: ownership check (`IRQ_NONE`), W1C ack with read-back, minimal work, `IRQ_WAKE_THREAD`/NAPI.
- [ ] Threaded IRQs with `IRQF_ONESHOT` for level sources; NAPI with budget and conditional IRQ re-enable for network paths.
- [ ] Every device-visible address comes from the DMA API; DMA mask set; coherent memory for rings; streaming maps with correct direction and sync calls.
- [ ] `dma_rmb()` after reading device ownership/index; `dma_wmb()` before handing buffers to the device; `writel` for doorbells.
- [ ] User mappings via `dma_mmap_coherent` / `io_remap_pfn_range` with matching attributes; offset and size validated.
- [ ] `devm_`/`dmam_` resources; device quiesced before IRQ request and stopped before resources are released.
- [ ] Build-tested against each supported kernel version (the API notes above), with KASAN, KFENCE and `DMA_API_DEBUG` in CI.

## 6. References

1. Linux kernel documentation: `driver-api/driver-model`, `driver-api/driver-model/devres.rst`, `core-api/genericirq.rst`, `networking/napi.rst`, `core-api/dma-api.rst`, `core-api/memory-allocation.rst`, `mm/slub.rst`, `dev-tools/kasan.rst`, `dev-tools/kfence.rst`.
2. T. Gleixner, threaded interrupt handlers (LWN, *Moving interrupts to threads*, 2008); LWN coverage of BH workqueues (2024) and `vm_flags_set` (2023).
3. J. H. Salim, R. Olsson, A. Kuznetsov, *Beyond Softnet* (NAPI), USENIX ALS 2001; J. Mogul, K. K. Ramakrishnan, *Eliminating Receive Livelock in an Interrupt-Driven Kernel*, TOCS 1997.
4. Reference drivers: `drivers/net/ethernet/stmicro/stmmac/` (DMA rings, NAPI), `drivers/net/ethernet/intel/igb/`, `drivers/misc/` (misc char devices), `drivers/uio/` (user-space MMIO).
