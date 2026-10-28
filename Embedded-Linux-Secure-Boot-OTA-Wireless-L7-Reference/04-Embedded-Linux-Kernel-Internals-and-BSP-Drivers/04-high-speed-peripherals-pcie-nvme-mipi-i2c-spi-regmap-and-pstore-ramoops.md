# 04.4 · High-Speed Peripherals (PCIe, NVMe, MIPI), I²C/SPI with regmap, and pstore/ramoops

> **Folder 04 · File 4 of 4.** The last kernel layer is the busses that carry real data, and the tooling for when it all goes wrong in the field:
> - **PCIe and NVMe:** link training, BARs, MSI-X, queue pairs with phase tags;
> - **MIPI CSI-2/DSI:** lane math that decides whether a sensor mode is possible at all;
> - **I²C/SPI:** where `regmap` turns register access into data and removes a whole class of races;
> - **pstore/ramoops:** a crash recorder in reserved RAM that survives the watchdog reset of 03.1 and tells you why the device rebooted.
>
> **Pinned.** Linux **v7.2**:
> - `include/linux/regmap.h` (`enum regcache_type`: `REGCACHE_NONE`, `_RBTREE`, `_FLAT`, `_MAPLE`, `_FLAT_S`);
> - `fs/pstore/ram.c` and `ram_core.c` (`struct persistent_ram_buffer`, `PERSISTENT_RAM_SIG` "DBGC", zone layout, record header);
> - `Documentation/admin-guide/ramoops.rst`.
>
> **Verification.**
> - The PMIC drivers pass `kapi_check.py` (04.1).
> - `rmw_race.py` enumerates the unlocked read-modify-write interleavings.
> - `ramoops_extract.py` implements the kernel's ramoops layout and is self-tested on an image built the way `persistent_ram_write()` leaves memory.
> - The ramoops tree passes `dts_lint.py`.
> - PCIe, NVMe and MIPI facts are from the specifications' public descriptions; no hardware was exercised (README) ⚠.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 PCIe from the SoC's point of view

```text
 Root complex (DT: pcie@... with ranges for I/O, 32-bit and 64-bit prefetchable memory; bus-range;
               interrupt-map for legacy INTx; msi-map / msi-parent → GICv3 ITS for MSI/MSI-X as LPIs, 04.3)
   LTSSM: Detect → Polling → Configuration → L0 (up) ⇄ Recovery;  L0s/L1 (ASPM low power), L2/L3 (off)
   enumeration: config space via ECAM; BAR sizing (write all-ones, read back the mask); bridges get windows
   endpoint driver: pci_enable_device → pci_request_regions → pcim_iomap → pci_alloc_irq_vectors(MSI-X)
                    → dma_set_mask_and_coherent (04.2) → bus mastering on
```

| Bring-up failure | Typical cause |
|---|---|
| Link never leaves Detect/Polling | Reference clock, PERST# timing, lane polarity or reversal not configured |
| Link up at Gen1 only | Signal integrity, or the controller's max link speed limited in DT |
| Endpoint enumerates, BAR mapping fails | `ranges` too small for the endpoint's BARs (prefetchable 64-bit windows) |
| Random hangs under load | ASPM L1 entry/exit latency the endpoint doesn't tolerate (`pcie_aspm=off` as a diagnosis, never as the fix without understanding) |
| MSI-X vectors never fire | `msi-map`/ITS not described, so the driver falls back to INTx (or nothing) |

### 1.2 NVMe queues and the phase tag

```text
 host memory: SQ (submission ring, 64-byte commands) + CQ (completion ring, 16-byte entries), per CPU
 submit:   write command at SQ tail → advance tail → write SQ tail doorbell (MMIO)
 complete: controller writes CQE with Phase Tag P; host consumes entries while P == expected phase,
           writes CQ head doorbell; when the head wraps to 0, the expected phase INVERTS
 interrupt: one MSI-X vector per CQ; coalescing trades latency for interrupt rate
```

**The phase tag is how the host tells a new entry from a stale one without the controller ever clearing the ring.** Forget to invert the expected phase on wrap, and the host either stalls or re-processes a whole ring of stale completions. That's a classic custom-driver bug in firmware and bootloader NVMe code.

### 1.3 MIPI CSI-2 / D-PHY: does the mode fit?

```text
 required bit rate = width × height × fps × bits_per_pixel × (1 + blanking overhead)
 per-lane rate     = required / lanes            must be ≤ the PHY's and the receiver's per-lane maximum
 example: 3840 × 2160 × 30 fps × 10 bpp (RAW10) ≈ 2.49 Gb/s payload; with ~10–20% blanking/protocol
          overhead ≈ 2.8–3.0 Gb/s → 4 lanes at ~750 Mb/s each, or 2 lanes at ~1.5 Gb/s (D-PHY 1.2 allows 2.5)
```

The DT endpoint's `data-lanes` and `link-frequencies` must match the sensor mode, and the receiver's lane count. A mismatch shows up as "no frames" or CRC errors, not a probe failure. Do the arithmetic before ordering boards.

### 1.4 I²C/SPI and regmap

A peripheral on a slow bus is a set of registers with properties: read-only, volatile (changes on its own), write-1-to-clear, or cacheable. `regmap` turns those properties into data (`struct regmap_config`) and gives:

| Without regmap | With regmap |
|---|---|
| Driver-written read-modify-write: two bus transactions, no lock | `regmap_update_bits()`: one critical section under regmap's lock |
| Every read goes on the bus | Non-volatile registers cached (`REGCACHE_MAPLE`); volatile ones always read |
| State lost when the chip loses power in suspend | `regcache_mark_dirty()` + `regcache_sync()` restores it |
| Error from a failed read used as data | Errors propagate as return codes |
| Raw access spread across files | One description, plus debugfs (`/sys/kernel/debug/regmap/`) to inspect it |

### 1.5 pstore/ramoops: the crash recorder

From `fs/pstore/ram.c` / `ram_core.c` at v7.2:

```text
 reserved region (DT "ramoops": reg, record-size, console-size, pmsg-size, ftrace-size, ecc-size)
   [ dmesg zone 0 | dmesg zone 1 | ... ]  [ console ]  [ pmsg ]  [ ftrace ]
     cnt = (size - console - ftrace - pmsg) / record-size;  zone = ALIGN_DOWN(that / cnt, 2)
   each zone: struct persistent_ram_buffer { u32 sig; u32 start; u32 size; u8 data[]; }
     sig = PERSISTENT_RAM_SIG (0x43474244, "DBGC") ^ (0, or LINUX_VERSION_CODE for ftrace zones)
     ring buffer: start = next write position; the old log is data[start:size] + data[0:start]
   dmesg record text: "====<sec>.<usec>-<C|D>\n" (C = compressed)
   ECC (optional): software Reed-Solomon, 16 parity bytes per block by default
 next boot: mount -t pstore pstore /sys/fs/pstore → dmesg-ramoops-N, console-ramoops-0, pmsg-ramoops-0
```

**It survives only a warm reset.** The DRAM must stay powered, which holds for a watchdog reset or a panic reboot but not for a power cycle. The region must also be one no earlier boot stage touches:
- U-Boot's relocation, stack or load addresses;
- TF-A or OP-TEE carve-outs (01.2, 01.3);
- DRAM training scratch areas.

`pmsg` (`/dev/pmsg0`) lets userspace leave breadcrumbs, such as the update client's state (03.1), that survive with the kernel log.

---

## 2. Production Code & Configuration Blueprints

### 2.1 A PMIC through regmap

#### The Fragile Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_pmic_fragile.c - the PMIC driver as raw SMBus calls: unlocked read-modify-write, no cache, no resume */
#include <linux/i2c.h>
#include <linux/module.h>

static struct i2c_client *pmic;

/* Called from the regulator path AND from a sysfs knob: two contexts, no lock. */
static int pmic_set_bits(u8 reg, u8 mask, u8 val)
{
	int old = i2c_smbus_read_byte_data(pmic, reg);

	return i2c_smbus_write_byte_data(pmic, reg, (old & ~mask) | val);	/* old < 0 is written back too */
}

static int pmic_probe(struct i2c_client *client)
{
	pmic = client;
	pmic_set_bits(0x10, 0x07, 0x03);
	return 0;
}

static struct i2c_driver pmic_driver = {
	.driver = { .name = "acme-pmic" },
	.probe = pmic_probe,
};
module_i2c_driver(pmic_driver);
MODULE_LICENSE("GPL");
```

#### The Silicon-Hardened Production Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_pmic.c - I2C PMIC control through regmap: register map as data, locked RMW, cache, suspend/resume */
#include <linux/bitfield.h>
#include <linux/i2c.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/pm.h>
#include <linux/regmap.h>

#define PMIC_ID		0x00		/* read-only */
#define PMIC_STATUS	0x01		/* read-only, changes on its own: volatile */
#define PMIC_BUCK1_CTRL	0x10
#define  BUCK_EN	BIT(0)
#define  BUCK_MODE	GENMASK(2, 1)
#define PMIC_BUCK1_VSEL	0x11
#define PMIC_IRQ	0x20		/* write 1 to clear: volatile */
#define PMIC_MAX	0x2f

static bool acme_pmic_volatile(struct device *dev, unsigned int reg)
{
	return reg == PMIC_STATUS || reg == PMIC_IRQ;
}

static bool acme_pmic_writeable(struct device *dev, unsigned int reg)
{
	return reg != PMIC_ID && reg != PMIC_STATUS;
}

static const struct regmap_config acme_pmic_regmap = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = PMIC_MAX,
	.volatile_reg = acme_pmic_volatile,
	.writeable_reg = acme_pmic_writeable,
	/* Non-volatile registers are cached: reads cost no bus traffic, and regcache_sync() restores them after
	 * the PMIC loses state in suspend. */
	.cache_type = REGCACHE_MAPLE,
};

struct acme_pmic {
	struct regmap *map;
};

static int acme_pmic_suspend(struct device *dev)
{
	struct acme_pmic *pmic = dev_get_drvdata(dev);

	regcache_cache_only(pmic->map, true);
	regcache_mark_dirty(pmic->map);
	return 0;
}

static int acme_pmic_resume(struct device *dev)
{
	struct acme_pmic *pmic = dev_get_drvdata(dev);

	regcache_cache_only(pmic->map, false);
	return regcache_sync(pmic->map);		/* write back everything the PMIC forgot */
}

static DEFINE_SIMPLE_DEV_PM_OPS(acme_pmic_pm, acme_pmic_suspend, acme_pmic_resume);

static int acme_pmic_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct acme_pmic *pmic;
	unsigned int id;
	int ret;

	pmic = devm_kzalloc(dev, sizeof(*pmic), GFP_KERNEL);
	if (!pmic)
		return -ENOMEM;
	pmic->map = devm_regmap_init_i2c(client, &acme_pmic_regmap);
	if (IS_ERR(pmic->map))
		return dev_err_probe(dev, PTR_ERR(pmic->map), "regmap\n");
	ret = regmap_read(pmic->map, PMIC_ID, &id);
	if (ret)
		return dev_err_probe(dev, ret, "no PMIC at 0x%02x\n", client->addr);
	dev_info(dev, "PMIC id 0x%02x\n", id);
	i2c_set_clientdata(client, pmic);

	/* One locked read-modify-write: no other thread can interleave between the read and the write. */
	ret = regmap_update_bits(pmic->map, PMIC_BUCK1_CTRL, BUCK_EN | BUCK_MODE,
				 BUCK_EN | FIELD_PREP(BUCK_MODE, 1));
	if (ret)
		return ret;
	return regmap_write(pmic->map, PMIC_IRQ, 0xff);	/* clear latched events */
}

static const struct of_device_id acme_pmic_of_match[] = {
	{ .compatible = "acme,pmic" },
	{ }
};
MODULE_DEVICE_TABLE(of, acme_pmic_of_match);

static struct i2c_driver acme_pmic_driver = {
	.driver = {
		.name = "acme-pmic",
		.of_match_table = acme_pmic_of_match,
		.pm = pm_sleep_ptr(&acme_pmic_pm),
	},
	.probe = acme_pmic_probe,
};
module_i2c_driver(acme_pmic_driver);
MODULE_DESCRIPTION("Acme PMIC");
MODULE_LICENSE("GPL");
```

Both pass the kernel API check. The difference is behavioral, shown by the race and error-path model:

```text
acme_pmic.c: 0 finding(s)
acme_pmic_fragile.c: 0 finding(s)
index: 69886 function/macro names, 20008 structs from include/ and arch/arm64/include
```

```python
# rmw_race.py - why register read-modify-write belongs inside regmap_update_bits(): lost updates and errno writes
"""Usage: python rmw_race.py

Two contexts (a regulator call and a sysfs write) each set their own bit in the same PMIC control register.
  unlocked RMW (acme_pmic_fragile.c): read, compute, write as separate bus transactions -> every interleaving
  regmap_update_bits(): regmap's own lock makes read+write one critical section
Then the error path: i2c_smbus_read_byte_data() returns -EIO (-5) on a NAK; (old & ~mask) | val, truncated to
the 8-bit register, is what the fragile driver writes back.
"""
import itertools

EIO = 5


def run(order, locked):
    """order: sequence of ('A'|'B') steps; each context does read then write. Returns the final register."""
    reg, seen, steps = 0x00, {}, {"A": 0, "B": 0}
    bits = {"A": 0x01, "B": 0x04}
    if locked:                                    # the lock serializes whole RMWs
        firsts = []
        for c in order:
            if c not in firsts:
                firsts.append(c)
        order = [c for c in firsts for _ in range(2)]
    for c in order:
        if steps[c] == 0:
            seen[c] = reg                         # bus read
        else:
            reg = (seen[c] & ~bits[c]) | bits[c]  # bus write of the value computed from the stale read
        steps[c] += 1
    return reg


def main():
    valid = sorted(set(itertools.permutations("AABB")))   # each context: its read always precedes its write
    fails = 0
    for locked in (False, True):
        finals = [run(list(o), locked) for o in valid]
        lost = sum(f != 0x05 for f in finals)
        print(f"{'regmap_update_bits (locked)' if locked else 'unlocked read-modify-write':<30}: "
              f"{len(valid)} interleavings, {lost} lose an update")
        fails += (lost == 0) if not locked else (lost != 0)
    old = -EIO
    written = ((old & ~0x07) | 0x03) & 0xFF
    print(f"read fails with -EIO: the fragile driver writes 0x{written:02x} to BUCK1_CTRL "
          f"(every other bit set: other rails' enables, mode bits)")
    fails += written != 0xFB
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
unlocked read-modify-write    : 6 interleavings, 4 lose an update
regmap_update_bits (locked)   : 6 interleavings, 0 lose an update
read fails with -EIO: the fragile driver writes 0xfb to BUCK1_CTRL (every other bit set: other rails' enables, mode bits)
ALL PASSED: 0 failure(s)
```

Writing `0xfb` into a PMIC control register enables every rail-control bit it holds, out of sequence. On real power hardware that's a brown-out at best and damaged silicon at worst, all from an I²C NAK that a retry would have survived.

### 2.2 The crash recorder

#### The Fragile Way

No pstore. Devices reboot via the watchdog (03.1), the A/B logic retries or falls back, and the only evidence of *why* is gone. Support's answer is "can't reproduce". Alternatively, a ramoops region placed inside U-Boot's relocation area, so the log is overwritten on every boot before Linux can read it.

#### The Silicon-Hardened Production Way

```dts
/* acme-ramoops.dts - pstore/ramoops in reserved RAM that survives a warm reset: the field crash recorder */
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

		/* 1 MiB: 59 dmesg records of 16 KiB (several oopses), 64 KiB console, 16 KiB pmsg for userspace
		 * breadcrumbs (/dev/pmsg0). Survives a watchdog reset only if the DRAM is not re-initialised and
		 * the bootloader never writes here: keep it out of U-Boot's relocation and load areas. */
		ramoops@5ff00000 {
			compatible = "ramoops";
			reg = <0x0 0x5ff00000 0x0 0x100000>;
			record-size = <0x4000>;
			console-size = <0x10000>;
			pmsg-size = <0x4000>;
			ecc-size = <16>;
		};
	};
};
```

Kernel side (02.2 fragments): `CONFIG_PSTORE`, `CONFIG_PSTORE_RAM`, `CONFIG_PSTORE_CONSOLE`, `CONFIG_PSTORE_PMSG`.

Userspace side, a unit at boot:
1. Copy `/sys/fs/pstore/*` into the crash report.
2. Upload the report with the release identity (02.4 SBOM).
3. Delete the entries to free the zones.

When the device can't boot far enough to mount pstore, extract offline:

```python
# ramoops_extract.py - recover dmesg/console/pmsg from a raw ramoops memory dump (JTAG or a recovery shell)
"""Usage: python ramoops_extract.py <dump.bin> --size N --record N --console N --pmsg N [--ftrace N --version V]
          python ramoops_extract.py --selftest

Layout and format as Linux v7.2 fs/pstore/ram.c and ram_core.c write them:
  zones in order: dmesg (size - console - ftrace - pmsg, cut into record-size zones), console, pmsg, ftrace
  each zone: struct persistent_ram_buffer { u32 sig; u32 start; u32 size; u8 data[]; }   (little-endian)
             sig == PERSISTENT_RAM_SIG (0x43474244, "DBGC") ^ (0 for dmesg/console/pmsg, LINUX_VERSION_CODE
             for ftrace): a kernel upgrade invalidates old ftrace zones
  valid zone: sig matches, size <= buffer size, start <= size; old data = data[start:size] + data[0:start]
  dmesg record text starts "====<sec>.<usec>-<C|D>\n" (C = compressed)
Use it when the device cannot boot far enough to mount /sys/fs/pstore: dump the reserved region over JTAG
(e.g. a CoreSight memory read of the address in the ramoops DT node) and extract offline.
"""
import re
import struct
import sys

SIG = 0x43474244
HDR = 12


def zones(size, record, console, pmsg, ftrace):
    """ramoops_init_przs(): cnt = mem / record; zone = ALIGN_DOWN(mem / cnt, 2); the address advances cnt*zone."""
    dump = size - console - ftrace - pmsg
    cnt = dump // record if record else 0
    zone = (dump // cnt) & ~1 if cnt else 0
    out = [(f"dmesg-{i}", i * zone, zone, 0) for i in range(cnt)]
    off = cnt * zone
    for name, sz in (("console", console), ("pmsg", pmsg)):
        if sz:
            out.append((name, off, sz, 0))
            off += sz
    if ftrace:
        out.append(("ftrace", off, ftrace, None))
    return out


def read_zone(dump, off, sz, sigxor):
    sig, start, size = struct.unpack_from("<III", dump, off)
    cap = sz - HDR
    if sig != SIG ^ sigxor:
        return None, f"no valid data (sig 0x{sig:08x})"
    if size == 0 and start == 0:
        return b"", "empty"
    if size > cap or start > size:
        return None, f"invalid buffer, size {size}, start {start}"
    data = dump[off + HDR:off + HDR + cap]
    return data[start:size] + data[:start], "ok"


def write_zone(buf, off, sz, text, sigxor=0):
    """What persistent_ram_write() leaves behind: a ring of cap bytes, start = next write position."""
    cap = sz - HDR
    ring, start, size = bytearray(cap), 0, 0
    for b in text:
        ring[start] = b
        start = (start + 1) % cap
        size = min(size + 1, cap)
    struct.pack_into("<III", buf, off, SIG ^ sigxor, start, size)
    buf[off + HDR:off + HDR + cap] = ring


def extract(dump, layout, version=0):
    found = {}
    for name, off, sz, sigxor in zones(*layout):
        data, status = read_zone(dump, off, sz, version if sigxor is None else sigxor)
        found[name] = (data, status)
    return found


def selftest():
    layout = (1 << 20, 16 << 10, 64 << 10, 16 << 10, 0)       # size, record-size, console, pmsg, ftrace
    img = bytearray(layout[0])
    oops = (b"====1793200000.123456-D\n<0>Unable to handle kernel NULL pointer dereference at virtual address "
            b"0000000000000008\n<0>pc : acme_rx_thread+0x44/0x120 [acme_rx]\n<0>Kernel panic - not syncing: Oops\n")
    console = b"".join(b"[%8d.000000] acme: heartbeat %d\n" % (i, i) for i in range(3000))   # wraps the 64 KiB ring
    zl = zones(*layout)
    write_zone(img, zl[0][1], zl[0][2], oops)
    con = next(z for z in zl if z[0] == "console")
    write_zone(img, con[1], con[2], console)
    pm = next(z for z in zl if z[0] == "pmsg")
    write_zone(img, pm[1], pm[2], b"acme-update-client: slot b written, rebooting\n")
    struct.pack_into("<III", img, zl[1][1], SIG, 900, 100)      # dmesg-1: start > size -> invalid
    found = extract(bytes(img), layout)
    fails = 0
    d0 = found["dmesg-0"][0] or b""
    m = re.match(rb"====(\d+)\.(\d+)-([CD])\n", d0)
    ok = m and m.group(3) == b"D" and d0 == oops
    print(f"   dmesg-0: {found['dmesg-0'][1]}, header time {m.group(1).decode()}.{m.group(2).decode()}" if m else "   dmesg-0 bad")
    fails += not ok
    con_data = found["console"][0]
    want_tail = console[-(con[2] - HDR):]
    oldest = con_data.split(b"\n")[1][:40].decode()       # [0] is a partial line cut by the wrap
    print(f"   console: {found['console'][1]}, {len(con_data)} bytes (ring wrapped), oldest line: {oldest!r}")
    fails += con_data != want_tail
    print(f"   pmsg: {found['pmsg'][1]}: {found['pmsg'][0].decode().strip()!r}")
    fails += found["pmsg"][0] != b"acme-update-client: slot b written, rebooting\n"
    print(f"   dmesg-1: {found['dmesg-1'][1]}")
    fails += "invalid" not in found["dmesg-1"][1]
    print(f"   dmesg-2: {found['dmesg-2'][1]}")
    fails += "no valid data" not in found["dmesg-2"][1]
    print(f"   zones: {len(zones(*layout))} ({(layout[0] - layout[2] - layout[3]) // layout[1]} dmesg records of "
          f"{layout[1] >> 10} KiB, console {layout[2] >> 10} KiB, pmsg {layout[3] >> 10} KiB)")
    print("selftest:", "ALL PASSED" if not fails else f"FAILED ({fails})")
    return fails


def main():
    args = sys.argv[1:]
    if args == ["--selftest"]:
        sys.exit(1 if selftest() else 0)
    get = lambda k, d=0: int(args[args.index(k) + 1], 0) if k in args else d
    layout = (get("--size"), get("--record"), get("--console"), get("--pmsg"), get("--ftrace"))
    for name, (data, status) in extract(open(args[0], "rb").read(), layout, get("--version")).items():
        print(f"== {name}: {status}")
        if data:
            sys.stdout.write(data.decode(errors="replace"))


if __name__ == "__main__":
    main()
```

```text
   dmesg-0: ok, header time 1793200000.123456
   console: ok, 65524 bytes (ring wrapped), oldest line: '[    1320.000000] acme: heartbeat 1320'
   pmsg: ok: 'acme-update-client: slot b written, rebooting'
   dmesg-1: invalid buffer, size 100, start 900
   dmesg-2: no valid data (sig 0x00000000)
   zones: 61 (59 dmesg records of 16 KiB, console 64 KiB, pmsg 16 KiB)
selftest: ALL PASSED
```

With `ecc-size` set, zones carry Reed-Solomon parity after the data. The extractor reads the text through the same `start`/`size` header but doesn't apply corrections, so prefer the kernel's own pstore read whenever the device boots.

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Mechanism | Detect | Fix |
|---|---|---|---|
| Random PMIC misconfiguration under load | Unlocked RMW from two contexts; errno written as data | `rmw_race.py`; I²C traces | `regmap_update_bits()`; propagate errors |
| Peripheral misbehaves only after suspend | Chip lost register state; no restore | Register dump before/after (`debugfs/regmap`) | `regcache_mark_dirty` + `regcache_sync` on resume |
| PCIe endpoint missing after cold boot, present after warm reboot | PERST#/refclk timing or power sequencing | LTSSM state from controller debug registers | Follow the controller's power-up sequence; DT reset/clock timing |
| NVMe driver (custom/bootloader) hangs after N commands | Phase tag not inverted on CQ wrap | Count commands to hang: ring size | Invert expected phase on head wrap |
| Camera "no frames" | `data-lanes`/`link-frequencies` mismatch, lane rate over PHY max | Receiver error counters | Lane math (§1.3) before DT; match sensor mode tables |
| Reboot loop, nothing in logs | No pstore, or region overwritten by the bootloader | Empty `/sys/fs/pstore` after a watchdog reset | Reserved region outside every boot stage's memory; verify with a forced panic test (`echo c > /proc/sysrq-trigger`) |

**Brick recovery with pstore.** A device in a boot loop (03.1 with bootlimit exhaustion) on the bench:
1. Stop it in U-Boot.
2. Dump the ramoops region (`md` in U-Boot only if that's allowed in a debug build, otherwise over JTAG).
3. Run `ramoops_extract.py`.

The oops record names the faulting function, the pmsg breadcrumbs name the update step, and the console tail shows the last thing that happened.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · "Why did it reboot?"

**Initial Prompt:** "Field devices occasionally reboot. The watchdog brings them back, and the update system keeps them on a good slot. Leadership asks why they reboot. What do you have?"

**L5 Answer:** "Nothing persists across the reboot. Add more logging to flash and ship it."

**Why L5 Bricks Devices at Scale:**
- **Logging to flash at crash time** writes from a dying kernel through drivers that may be the cause, wears the flash on every boot loop, and loses the last seconds anyway.
- **Without evidence,** every incident is a guess.

**L7 Principal Defense:**
- **Run pstore/ramoops in reserved RAM:**
  - oops and panic records survive the warm reset;
  - console tail and pmsg breadcrumbs from userspace;
  - collected at the next boot and uploaded with the release identity (02.4).
- **Validate it with forced crashes in CI** (`sysrq-trigger c`, a watchdog-only hang) on every board revision. A region overwritten by the bootloader is a silent failure until the day it's needed.
- **For devices that can't boot,** extract over JTAG (§2.2).

### Chain 2 · The PMIC that sometimes misbehaves

**Initial Prompt:** "About 1 in 100,000 boots, a PMIC rail comes up in the wrong mode. The code that sets it is a simple read-modify-write. Ideas?"

**L5 Answer:** "Probably an I²C glitch. Add a retry around the write."

**Why L5 Bricks Devices at Scale:**
- **Two failure mechanisms fit, and neither is fixed by a retry:**
  - another context (a regulator call, sysfs, a resume path) running its own RMW between this read and write (§2.1: 4 of 6 interleavings lose an update);
  - a failed read whose negative errno is masked into the value and written (0xfb here).
- **A retry around the write** retries the corrupt value.

**L7 Principal Defense:**
- **Move all register access to regmap:** `regmap_update_bits()` under regmap's lock, errors propagated.
- **Describe volatile registers** so status isn't served from cache.
- **Sync the cache on resume.**
- **Test with I²C fault injection** (NAKs on reads).
- **For PMICs, make the rail sequence a table** reviewed against the datasheet's power-up order.

### Chain 3 · Bringing up a PCIe Wi-Fi module

**Initial Prompt:** "A PCIe Wi-Fi module isn't detected on the new board. Walk through bring-up."

**L5 Answer:** "Rescan the PCI bus and check that the driver is loaded."

**Why L5 Bricks Devices at Scale:**
- **No driver can load for a device that never enumerated.** The question is where the LTSSM stopped.
- **Rescans** don't change reference-clock routing, PERST# timing, the module's power sequencing, or a DT `ranges` too small for its BARs.

**L7 Principal Defense:**
- **Work up the stack:**
  - power rails and their sequence;
  - reference clock present and spread-spectrum settings compatible;
  - PERST# deasserted after power-good plus the required delay;
  - LTSSM state from the controller's debug registers (Detect/Polling means electrical or clock; Configuration means lanes; L0 means enumeration next);
  - `lspci -vv` for link width and speed;
  - BAR assignment against DT `ranges`;
  - MSI-X via `msi-map`;
  - then the driver.
- **Document the sequence per board** and automate it as a bring-up checklist.

### Chain 4 · Will the camera mode work?

**Initial Prompt:** "Product wants 4K at 60 fps RAW12 from a sensor on a 2-lane CSI-2 port. Feasible?"

**L5 Answer:** "The sensor supports 4K60, so yes."

**Why L5 Bricks Devices at Scale:** The sensor's capability isn't the system's.
- **The raw payload:** 3840 × 2160 × 60 × 12 ≈ 5.97 Gb/s before blanking and protocol overhead.
- **On two lanes** that's ~3 Gb/s per lane plus overhead, beyond typical D-PHY receivers.
- **Then the ISP and DDR bandwidth** for the whole pipeline (04.2).

Discovering that after boards are built costs a spin.

**L7 Principal Defense:**
- **Do the arithmetic (§1.3)** for every requested mode against the receiver's lane count and per-lane maximum (D-PHY version), and against the ISP's throughput and DDR bandwidth.
- **Offer the feasible alternatives:** 4 lanes, RAW10, 30 fps, or C-PHY on SoCs that have it.
- **Encode the mode in DT** (`data-lanes`, `link-frequencies`) and test with the receiver's error counters.

### Chain 5 · Writing a bootloader NVMe driver

**Initial Prompt:** "We need NVMe boot support in our bootloader. What's the minimum correct design?"

**L5 Answer:** "Submit a read command, poll the completion queue until it's non-zero, copy the data."

**Why L5 Bricks Devices at Scale:**
- **Completion entries are never zeroed by the controller.** The host must track the phase tag, which inverts every pass.
- **"Non-zero" works for the first pass of the ring,** then re-reads stale entries or hangs once the ring wraps. On a large image load, that's after a few hundred commands.
- **DMA addresses must be ones the controller can reach**, with cache maintenance on non-coherent SoCs (04.2).

**L7 Principal Defense:**
- **The minimal correct design:**
  - one admin and one I/O queue pair;
  - phase-tag consumption with inversion on wrap;
  - doorbell writes ordered after queue entries;
  - PRP or SGL lists for multi-page transfers;
  - timeouts with controller reset;
  - cache clean and invalidate around DMA buffers.
- **Better:** use U-Boot's existing NVMe driver and harden it, rather than writing one.
- **Test across ring wraps and large transfers.**

### Chain 6 · Debugging without a console

**Initial Prompt:** "A device hangs in the field with no serial console. You get it back. What do you do first?"

**L5 Answer:** "Connect a serial cable and try to reproduce."

**Why L5 Bricks Devices at Scale:**
- **Reproducing first destroys the evidence.** The current DRAM may still hold the pstore records, and power-cycling it erases them.
- **Many field hangs never reproduce on the bench.**

**L7 Principal Defense:**
- **Preserve before probing.**
  - Keep it powered if possible and warm-reset it into the recovery path.
  - Collect `/sys/fs/pstore` (or dump the ramoops region over JTAG and extract offline).
  - Read the boot-state variables (03.1) and the hardware watchdog's reset-cause register.
- **Only then reproduce**, with the evidence pointing at the failing subsystem.
- **Make this a written field-return procedure**, with the tooling (`ramoops_extract.py`) in the support kit.

---

## 5. Invariants Checklist

- [ ] All I²C/SPI register access through regmap; volatile registers declared; `regcache_sync` on resume; errors never used as data.
- [ ] PCIe: power/refclk/PERST# sequence per datasheet; DT `ranges` sized for the endpoints' BARs; `msi-map` to the ITS; ASPM decisions measured.
- [ ] Custom NVMe code: phase-tag inversion on wrap, ordered doorbells, DMA rules (04.2).
- [ ] MIPI: lane-rate arithmetic for every mode before DT; receiver error counters monitored.
- [ ] pstore/ramoops in a reserved region no boot stage touches; console + pmsg enabled; forced-crash test per board revision; collection and upload at boot; JTAG extraction procedure in the field-return kit.

## 6. References

- Linux v7.2: `include/linux/regmap.h`, `drivers/base/regmap/`, `fs/pstore/ram.c`, `fs/pstore/ram_core.c`, `Documentation/admin-guide/ramoops.rst`, `drivers/nvme/host/pci.c`, `drivers/pci/controller/dwc/`. <https://github.com/torvalds/linux/tree/v7.2>
- NVM Express Base Specification (queues, phase tag). <https://nvmexpress.org/specifications/>
- PCI Express Base Specification (LTSSM, ASPM); MIPI CSI-2 / D-PHY specifications (membership).
- In this KB: [03.1 watchdog and boot state](../03-OTA-Architecture-SOTA-FOTA-OSTree-and-TUF/01-sota-vs-fota-ab-symmetric-asymmetric-and-bootloader-fallback-state-machine.md) · [04.1 kapi_check](01-kernel-boot-flow-device-tree-of-matching-pinmux-and-common-clock-framework.md) · [04.2 DMA rules](02-memory-management-cma-dma-buf-iommu-smmu-slab-slub-and-oom-killer.md)
