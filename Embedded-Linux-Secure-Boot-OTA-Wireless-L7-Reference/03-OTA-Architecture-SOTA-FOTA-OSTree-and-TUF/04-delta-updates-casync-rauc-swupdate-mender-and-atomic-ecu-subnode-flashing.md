# 03.4 · Delta Updates (casync), RAUC, SWUpdate, Mender, and Atomic Multi-ECU Flashing

> **Folder 03 · File 4 of 4.** The last mile of an update system has three parts:
> - **moving fewer bytes:** delta and chunk-based transfer;
> - **an update client** that installs a signed bundle into the inactive slot and hands over to the boot state machine (03.1);
> - for products with more than one programmable component, **updating them as one system**.
>
> Each has a characteristic failure:
> - deltas that are small only in the lab;
> - a client whose bootloader integration disagrees with the bootloader;
> - a fleet of vehicles stuck with half their ECUs on the new version.
>
> **Pinned.** casync **v2** (`src/cachunker.{c,h}`, `src/util.h` `rol32`), RAUC **v1.15.2** (`docs/reference.rst`, `docs/integration.rst`), SWUpdate **2026.05.1** (`doc/source/overview.rst`, `signed_images.rst`, `sw-description.rst`).
>
> **Verification.**
> - `cdc_chunker.py` mirrors `ca_chunker_scan()` and reads the buzhash table out of `cachunker.c` itself.
> - `rauc_cfg_check.py` reads its option tables from RAUC's `reference.rst`.
> - `rauc-bootchooser.sh` implements RAUC's documented custom-backend interface over 03.1's U-Boot contract.
> - `ecu_2pc.py` injects a power cut before every step of a three-ECU update, alone and combined with each ECU failing its health check.
> - Mender details are from public documentation and were not checked against source here ⚠.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 Why fixed-block deltas fail, and content-defined chunking doesn't

A binary diff between two images (bsdiff-style) is small, but needs the exact old image on the device and CPU and RAM to apply. A block-level scheme ("download only the blocks that changed") is simpler but fragile: **one inserted byte shifts every following block boundary**, so every block after the insertion "changed".

**Content-defined chunking (CDC)** places boundaries where the *content* says to. casync's chunker (`cachunker.c`):

```text
 rolling hash h over a 48-byte window (CA_CHUNKER_WINDOW_SIZE), buzhash:
   start:  h = XOR_{i=1..47} rol32(T[w[i-1]], 48-i)  XOR  T[w[47]]
   roll:   h = rol32(h, 1) XOR rol32(T[leaving], 48) XOR T[entering]        (rol32: i %= 32)
 cut after byte i when  size >= max  OR  (size >= min AND h mod d == d - 1)
   avg default 64 KiB (CA_CHUNK_SIZE_AVG_DEFAULT), min = avg/4, max = avg*4
   d = avg / (-1.42888852e-7*avg + 1.33237515)     ("chunks end up being ~1.32 times larger than the raw size")
 after a cut: h = 0, window empty, size 0: the next chunk starts fresh
```

- **An insertion moves the cut points only locally.** Downstream of it, the same content produces the same window contents, hence the same cuts and the same chunk hashes.
- **The device downloads only chunks it doesn't already have,** looked up in its current slot or a local store (casync's "seed").

§2.1 measures the effect on a 4 MiB image with a 100-byte insertion and a 4 KiB edit.

### 1.2 Update clients compared

| | RAUC | SWUpdate | Mender |
|---|---|---|---|
| Unit | Bundle: signed (CMS) image set + `manifest.raucm`; formats `verity` (dm-verity protected while mounted), `crypt`, legacy `plain` | `.swu` (cpio) with `sw-description` (libconfig/JSON), signed `sw-description` carrying every image's hash | Artifact (format v3) ⚠ |
| Device config | `system.conf`: slots, keyring, bootloader backend | Build-time config + `sw-description` selections | Client config + device type ⚠ |
| Bootloader integration | Backends: `barebox`, `grub`, `uboot` (`BOOT_ORDER`, `BOOT_<name>_LEFT`), `efi`, `custom`, `noop` | Transaction marker `recovery_status` (`progress` / `failed` / unset) and `ustate` in the bootloader environment | U-Boot/GRUB integration with its own variables ⚠ |
| Delta | casync-based adaptive and streaming (chunked) | Delta handler (zchunk) | Binary delta (commercial) ⚠ |
| Fits | Embedded Linux A/B, strong slot model | Highly configurable handlers (MCU, FPGA, scripts) | Managed fleets, integrated server ⚠ |

**The integration rule that matters most.** Exactly one boot-selection contract may exist between the client and the bootloader.
- RAUC's `uboot` backend writes `BOOT_ORDER` and `BOOT_x_LEFT` and expects a matching U-Boot script (its `contrib/uboot.sh`).
- 03.1's U-Boot implements `boot_slot`, `upgrade_available` and `bootcount`.

Using both means the client marks slots in variables the bootloader never reads. Here RAUC uses `bootloader=custom` with a backend that maps its five commands onto 03.1's variables (§2.3).

### 1.3 Signing the right thing

SWUpdate's documentation states the design point well. Signing the *compound* image means "it is not possible to know if the image is verified until the whole image is loaded", so parts would be installed before verification.

The fix, in every serious client:
- **Sign a small manifest** (`sw-description`, RAUC's manifest within a CMS-signed bundle) that carries each image's hash.
- **Verify it first.**
- **Then verify each image's hash as it streams into the slot.**

RAUC's `verity` format additionally protects the bundle with dm-verity while it is mounted, closing the time-of-check/time-of-use window of a bundle file that could change after its signature was checked. That window is why `plain` should be disabled (`bundle-formats=-plain`).

### 1.4 Multi-ECU systems: one version, many components

```text
           gateway (Primary)                      brake ECU                 ADAS ECU
 phase 1   write v2 → inactive bank, verify   ┐  write, verify           write, verify
           journal := PREPARED (persisted)    ┘
 phase 2   one-shot trial boot of v2 on all; collect health
           all healthy → journal := COMMITTING → mark v2 good on each (OLD BANK KEPT) → DONE → release old banks
           any failure → journal := ABORTING → every ECU back to v1
 after any crash: one-shot trials fall back by themselves; the gateway reads the journal:
           IDLE/PREPARED/ABORTING → roll back;  COMMITTING → roll forward (re-trial stragglers;
           if one fails, roll everyone back: the old banks still exist)
```

Version compatibility is a property of the *set*. Brake v2 may require gateway v2's message catalogue. Flashing ECUs one after another and committing each on its own creates intermediate states that are only safe if every pair of versions interoperates. In practice that is untested and false. §2.4 measures it.

---

## 2. Production Code & Configuration Blueprints

### 2.1 Content-defined chunking, measured

```python
# cdc_chunker.py - casync's content-defined chunker, and why it makes deltas small where fixed blocks cannot
"""Usage: python cdc_chunker.py <casync>/src/cachunker.c

Mirrors casync v2 src/cachunker.c: buzhash over a 48-byte window (CA_CHUNKER_WINDOW_SIZE), the table read
from the source file itself, rol32() with i %= 32 (src/util.h), cut when h mod d == d - 1 with
d = CA_CHUNKER_DISCRIMINATOR_FROM_AVG(avg), chunk size clamped to [avg/4, avg*4], and the window, hash and
size reset after every cut (ca_chunker_scan). Compares the bytes a device must download for a new image
that inserts 100 bytes and edits 4 KiB, against the same image cut into fixed-size blocks.
"""
import hashlib
import random
import re
import sys

WINDOW = 48


def rol32(x, i):
    i %= 32
    return x if i == 0 else ((x << i) | (x >> (32 - i))) & 0xFFFFFFFF


def load_table(path):
    src = open(path, encoding="utf-8").read()
    body = re.search(r"buzhash_table\[\]\s*=\s*\{(.*?)\};", src, re.S).group(1)
    table = [int(v, 16) for v in re.findall(r"0x[0-9a-fA-F]+", body)]
    assert len(table) == 256
    return table


def chunks(data, table, avg):
    lo, hi = avg // 4, avg * 4
    d = int(avg / (-1.42888852e-7 * avg + 1.33237515))      # CA_CHUNKER_DISCRIMINATOR_FROM_AVG
    d = min(max(d, lo), hi)
    out, start, n = [], 0, len(data)
    while start < n:
        end = min(start + WINDOW, n)
        if end - start < WINDOW:                              # tail shorter than one window
            out.append((start, n))
            break
        h = 0
        for i in range(1, WINDOW):                            # ca_chunker_start()
            h ^= rol32(table[data[start + i - 1]], WINDOW - i)
        h ^= table[data[start + WINDOW - 1]]
        size, pos = WINDOW, end
        cut = size >= hi or (size >= lo and h % d == d - 1)
        while not cut and pos < n:                            # ca_chunker_roll() + shall_break()
            h = rol32(h, 1) ^ rol32(table[data[pos - WINDOW]], WINDOW) ^ table[data[pos]]
            size += 1
            pos += 1
            cut = size >= hi or (size >= lo and h % d == d - 1)
        out.append((start, pos))
        start = pos
    return out


def digest_set(data, spans):
    return {hashlib.sha256(data[a:b]).digest(): b - a for a, b in spans}


def main():
    table = load_table(sys.argv[1])
    rng = random.Random(2026)
    old = bytes(rng.getrandbits(8) for _ in range(4 << 20))   # a 4 MiB image (incompressible content)
    new = bytearray(old)
    new[1 << 20:1 << 20] = b"\xa5" * 100                     # 100 bytes inserted at 1 MiB
    new[3 << 20:(3 << 20) + 4096] = bytes(rng.getrandbits(8) for _ in range(4096))   # 4 KiB edited at 3 MiB
    new = bytes(new)
    fails = 0
    for avg in (16 << 10, 64 << 10):
        spans_old, spans_new = chunks(old, table, avg), chunks(new, table, avg)
        have = digest_set(old, spans_old)
        need = sum(size for dg, size in digest_set(new, spans_new).items() if dg not in have)
        sizes = [b - a for a, b in spans_new]
        print(f"CDC avg {avg >> 10:>2} KiB: {len(spans_new)} chunks, mean {sum(sizes) // len(sizes) >> 10} KiB, "
              f"min {min(sizes[:-1]) >> 10} KiB, max {max(sizes) >> 10} KiB; download {need >> 10} KiB "
              f"of {len(new) >> 10} KiB")
        fails += not (need < 8 * avg)                         # a few chunks around each change
        fails += not (min(sizes[:-1]) >= avg // 4 and max(sizes) <= avg * 4)
    for block in (16 << 10, 64 << 10):
        fixed = lambda data: [(i, min(i + block, len(data))) for i in range(0, len(data), block)]
        have = digest_set(old, fixed(old))
        need = sum(size for dg, size in digest_set(new, fixed(new)).items() if dg not in have)
        print(f"fixed {block >> 10:>2} KiB blocks: download {need >> 10} KiB of {len(new) >> 10} KiB "
              "(every block after the insertion shifted)")
        fails += not (need > (len(new) * 2) // 3)
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
CDC avg 16 KiB: 262 chunks, mean 15 KiB, min 4 KiB, max 64 KiB; download 48 KiB of 4096 KiB
CDC avg 64 KiB: 63 chunks, mean 65 KiB, min 16 KiB, max 241 KiB; download 274 KiB of 4096 KiB
fixed 16 KiB blocks: download 3072 KiB of 4096 KiB (every block after the insertion shifted)
fixed 64 KiB blocks: download 3072 KiB of 4096 KiB (every block after the insertion shifted)
ALL PASSED: 0 failure(s)
```

- **Fixed blocks re-download everything after the insertion:** 3 MiB of 4 MiB.
- **CDC downloads the few chunks around the two changes.**
- **Smaller average chunks** mean less re-download and more index metadata per image. Pick the average from the measured change pattern of real releases, not from defaults.
- **Compressed or encrypted payloads defeat chunk dedup,** because every byte changes. Chunk the uncompressed filesystem image (squashfs block-level compression helps), and compress chunks individually, as casync does.

### 2.2 RAUC device configuration and bundle

#### The Fragile Way

```ini
# rauc-system-fragile.conf - system.conf from the RAUC quick start, adapted overnight
[system]
compatible=acme
bootloader=uboot
statusfile=/etc/rauc/status.raucs

[keyring]
path=/etc/rauc/dev-ca.pem

[slot.rootfs.0]
device=/dev/mmcblk2p3
type=ext4
bootname=A

[slot.rootfs.1]
device=/dev/mmcblk2p4
type=ext4
bootname=B
```

```ini
# manifest-fragile.raucm - the manifest the first bundle shipped with
[update]
compatible=acme
version=11

[image.rootfs]
filename=rootfs.ext4
```

#### The Silicon-Hardened Production Way

```ini
# rauc-system.conf - /etc/rauc/system.conf: A/B slots of the 02.2 layout, boot selection through 03.1's contract
[system]
compatible=acme-imx8m
# RAUC's own "uboot" backend uses BOOT_ORDER/BOOT_x_LEFT; this U-Boot implements boot_slot/upgrade_available/
# bootcount (03.1), so RAUC drives it through a custom backend instead of a second, conflicting scheme.
bootloader=custom
bundle-formats=-plain
data-directory=/data/rauc
min-bundle-version=2026.10.0

[keyring]
path=/etc/rauc/release-ca.pem
check-purpose=codesign

[handlers]
bootloader-custom-backend=/usr/libexec/acme/rauc-bootchooser

[slot.rootfs.0]
device=/dev/disk/by-partlabel/rootfs_a
type=raw
bootname=A

[slot.rootfs.1]
device=/dev/disk/by-partlabel/rootfs_b
type=raw
bootname=B

[slot.boot.0]
device=/dev/disk/by-partlabel/boot_a
type=raw
parent=rootfs.0

[slot.boot.1]
device=/dev/disk/by-partlabel/boot_b
type=raw
parent=rootfs.1
```

```ini
# manifest.raucm - bundle manifest: dm-verity bundle format, compatible string and version the device checks
[update]
compatible=acme-imx8m
version=2026.11.0
description=Acme release 2026.11
build=20261105.1

[bundle]
format=verity

[image.rootfs]
filename=acme-image-acme-imx8m.rootfs.squashfs

[image.boot]
filename=fitImage
```

The gate, with option names read from RAUC 1.15.2's own reference documentation:

```python
# rauc_cfg_check.py - RAUC system.conf + bundle manifest gate; option tables read from RAUC's reference.rst
"""Usage: python rauc_cfg_check.py <rauc>/docs/reference.rst <system.conf> <manifest.raucm> [--uboot-env <board.env>]

  U1 an option the reference does not define for that section (silently ignored by a typo'd key)
  U2 bundle formats that still accept 'plain' (signature checked once at install, no dm-verity)
  U3 keyring without check-purpose=codesign (any certificate in the CA chain can sign bundles)
  U4 slot devices by /dev/mmcblkNpM (probe order) instead of a stable name
  U5 slot status on the root filesystem, or the deprecated statusfile without data-directory
  U6 no min-bundle-version: nothing stops the installation of an older bundle
  U7 bootloader backend disagreeing with the U-Boot environment's contract (--uboot-env)
  M1 manifest without [bundle] format=verity (or crypt)
  M2 manifest compatible != system compatible
  M3 manifest version not semantic-versioned while min-bundle-version is set (comparison undefined)
"""
import re
import sys


def option_tables(rst):
    tables, sec = {}, None
    for line in open(rst, encoding="utf-8"):
        m = re.match(r"^``\[([a-z.<>*/\-]+)\]``\s+Section", line) or re.match(r"^``\[(image\.[^\]]+)\]``\s*$", line)
        if m:
            sec = m.group(1)
            tables.setdefault(sec, set())
            continue
        m = re.match(r"^``([a-z][a-z0-9-]*)(?:=[^`]*)?``", line)
        if sec and m:
            tables[sec].add(m.group(1))
    image = set().union(*(v for k, v in tables.items() if k.startswith("image.")))
    return tables, image


def parse(path):
    sec, out = None, {}
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            sec = m.group(1)
            out.setdefault(sec, {})
        else:
            k, _, v = line.partition("=")
            out[sec][k.strip()] = (v.strip(), n)
    return out


def table_for(sec, tables, image):
    if sec.startswith("slot."):
        return tables.get("slot.<slot-class>.<idx>", set())
    if sec.startswith("image."):
        return image
    return tables.get(sec, set())


def main():
    args = sys.argv[1:]
    env = None
    if "--uboot-env" in args:
        i = args.index("--uboot-env")
        env = open(args[i + 1], encoding="utf-8").read()
        args = args[:i] + args[i + 2:]
    tables, image = option_tables(args[0])
    findings = {}
    for path in args[1:3]:
        cfg, out = parse(path), []
        for sec, kv in cfg.items():
            known = table_for(sec, tables, image)
            for k, (_, n) in kv.items():
                if k not in known:
                    out.append(f"U1 line {n}: [{sec}] {k} is not a documented option")
        findings[path] = (cfg, out)
    (system, sout), (manifest, mout) = findings[args[1]][0:2], findings[args[2]][0:2]
    s = system.get("system", {})
    fmts = s.get("bundle-formats", ("", 0))[0].split()
    if not fmts or ("plain" in fmts) or ("-plain" not in fmts and not any(f in fmts for f in ("verity", "crypt"))):
        sout.append(f"U2 bundle-formats={' '.join(fmts) or '(default)'}: 'plain' bundles still accepted")
    if system.get("keyring", {}).get("check-purpose", ("", 0))[0] != "codesign":
        sout.append("U3 [keyring] check-purpose is not codesign")
    for sec, kv in system.items():
        dev = kv.get("device", ("", 0))
        if sec.startswith("slot.") and re.match(r"^/dev/mmcblk\d+p\d+$", dev[0]):
            sout.append(f"U4 line {dev[1]}: [{sec}] device={dev[0]} follows probe order")
    status = s.get("statusfile", ("", 0))[0]
    if "data-directory" not in s:
        sout.append(f"U5 no data-directory{' (statusfile=' + status + ', deprecated)' if status else ''}")
    if status.startswith(("/etc", "/usr", "/var/lib")):
        sout.append(f"U5 statusfile={status} lives on a filesystem that updates replace")
    if "min-bundle-version" not in s:
        sout.append("U6 no min-bundle-version: older bundles install")
    if env is not None:
        uses_bootslot, uses_order = "boot_slot" in env, "BOOT_ORDER" in env
        backend = s.get("bootloader", ("", 0))[0]
        if backend == "uboot" and not uses_order:
            sout.append("U7 bootloader=uboot writes BOOT_ORDER/BOOT_x_LEFT, which this U-Boot environment never reads")
        if backend == "custom" and "bootloader-custom-backend" not in system.get("handlers", {}):
            sout.append("U7 bootloader=custom without a bootloader-custom-backend handler")
    fmt = manifest.get("bundle", {}).get("format", ("plain", 0))[0]
    if fmt not in ("verity", "crypt"):
        mout.append(f"M1 bundle format {fmt}: no dm-verity protection while the bundle is mounted")
    if manifest.get("update", {}).get("compatible", ("", 0))[0] != s.get("compatible", ("", 0))[0]:
        mout.append("M2 manifest compatible differs from system.conf compatible")
    version = manifest.get("update", {}).get("version", ("", 0))[0]
    if "min-bundle-version" in s and not re.match(r"^\d+\.\d+\.\d+", version):
        mout.append(f"M3 version '{version}' is not semver: min-bundle-version cannot compare it")
    total = 0
    for path in args[1:3]:
        out = sout if path == args[1] else mout
        total += len(out)
        print(f"{path.replace(chr(92), '/').rsplit('/', 1)[-1]}: {len(out)} finding(s)")
        for o in out:
            print("   ", o)
    print("options known: " + ", ".join(f"[{k}] {len(v)}" for k, v in tables.items() if v and not k.startswith("image.")))
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

```text
== hardened
rauc-system.conf: 0 finding(s)
manifest.raucm: 0 finding(s)
options known: [system] 21, [keyring] 7, [streaming] 5, [encryption] 2, [casync] 4, [autoinstall] 1, [handlers] 4, [slot.<slot-class>.<idx>] 13, [artifacts.<repo-name>] 4, [log.<logger>] 5, [update] 5, [bundle] 5, [hooks] 2, [handler] 2, [meta.<label>] 1
exit=0
== fragile
rauc-system-fragile.conf: 8 finding(s)
    U2 bundle-formats=(default): 'plain' bundles still accepted
    U3 [keyring] check-purpose is not codesign
    U4 line 11: [slot.rootfs.0] device=/dev/mmcblk2p3 follows probe order
    U4 line 16: [slot.rootfs.1] device=/dev/mmcblk2p4 follows probe order
    U5 no data-directory (statusfile=/etc/rauc/status.raucs, deprecated)
    U5 statusfile=/etc/rauc/status.raucs lives on a filesystem that updates replace
    U6 no min-bundle-version: older bundles install
    U7 bootloader=uboot writes BOOT_ORDER/BOOT_x_LEFT, which this U-Boot environment never reads
manifest-fragile.raucm: 1 finding(s)
    M1 bundle format plain: no dm-verity protection while the bundle is mounted
options known: [system] 21, [keyring] 7, [streaming] 5, [encryption] 2, [casync] 4, [autoinstall] 1, [handlers] 4, [slot.<slot-class>.<idx>] 13, [artifacts.<repo-name>] 4, [log.<logger>] 5, [update] 5, [bundle] 5, [hooks] 2, [handler] 2, [meta.<label>] 1
exit=1
```

### 2.3 One boot contract: RAUC's custom backend over 03.1

#### The Fragile Way

`bootloader=uboot` on a board whose U-Boot implements 03.1's variables. RAUC writes `BOOT_ORDER=B A` and `BOOT_B_LEFT=3` after installing slot B. U-Boot never reads them and keeps booting A. `rauc status mark-good` "succeeds" on the wrong slot, and every update silently never takes effect (U7 in §2.2).

#### The Silicon-Hardened Production Way

```sh
#!/bin/sh
# rauc-bootchooser.sh - RAUC custom bootloader backend over 03.1's U-Boot contract (boot_slot, upgrade_available,
# bootcount). Bootnames A/B map to boot_slot a/b. Every change is ONE fw_setenv -s write (atomic).
set -eu

slot_of() { [ "$1" = "B" ] && echo b || echo a; }
name_of() { [ "$1" = "b" ] && echo B || echo A; }
other() { [ "$1" = "a" ] && echo b || echo a; }
getv() { fw_printenv -n "$1" 2>/dev/null || echo "$2"; }

commit() {
	script=$(mktemp)
	trap 'rm -f "$script"' EXIT
	printf '%s\n' "$@" > "$script"
	fw_setenv -s "$script"
}

primary=$(getv boot_slot a)
trial=$(getv upgrade_available 0)

case "${1:-}" in
get-primary | get-current)
	# U-Boot boots only ${boot_slot}, and altbootcmd rewrites it before falling back: primary == running.
	name_of "$primary"
	;;
set-primary)
	# Called after RAUC has written and verified the slot: start a trial of it (03.1 write-then-switch).
	commit "boot_slot=$(slot_of "$2")" "upgrade_available=1" "bootcount=0"
	;;
get-state)
	if [ "$(slot_of "$2")" = "$primary" ] && [ "$trial" = "1" ]; then echo bad; else echo good; fi
	;;
set-state)
	if [ "$(slot_of "$2")" = "$primary" ] && [ "$3" = "good" ]; then
		[ "$trial" = "1" ] && commit "upgrade_available=0" "bootcount=0"
	elif [ "$(slot_of "$2")" = "$primary" ] && [ "$3" = "bad" ]; then
		commit "boot_slot=$(other "$primary")" "upgrade_available=0" "bootcount=0"
	fi
	;;
*)
	echo "usage: $0 get-primary|get-current|set-primary <A|B>|get-state <A|B>|set-state <A|B> <good|bad>" >&2
	exit 2
	;;
esac
```

| RAUC calls | Backend does |
|---|---|
| `set-primary` (after RAUC has written and verified the slot) | 03.1's switch: `boot_slot`, `upgrade_available=1`, `bootcount=0`, in one `fw_setenv -s` |
| `set-state <current> good` (`rauc status mark-good`) | 03.1's commit |
| `set-state <current> bad` | Immediate fallback |
| `get-current` | Reads `boot_slot`: U-Boot boots only that slot and rewrites it before falling back, so it always names the running slot |

### 2.4 Updating several ECUs as one system

#### The Fragile Way

Flash and commit each ECU in turn: brake, then ADAS, then the gateway. Any failure or power cut part-way leaves a version mix that was never tested.

#### The Silicon-Hardened Production Way

```python
# ecu_2pc.py - updating several ECUs as ONE system: two-phase commit with a journal, against sequential flashing
"""Usage: python ecu_2pc.py

Each ECU has two banks and a one-shot trial boot (an untried or unconfirmed bank falls back by itself on the
next reset). Versions are only compatible as a set: (1, 1, 1) or (2, 2, 2).
  hardened: phase 1 writes and verifies v2 into every inactive bank, journal PREPARED; phase 2 trial-boots
            every ECU, collects health; all healthy -> journal COMMITTING -> mark v2 good on each ECU (old bank
            kept) -> DONE, old banks released; any failure -> journal ABORTING -> every ECU back to v1. After a
            crash, the gateway reads the journal: PREPARED/ABORTING roll back, COMMITTING rolls forward
            (re-trial the stragglers; if one of them fails, roll everyone back: the old banks still exist).
  fragile:  flash and commit one ECU after the other.
A power cut is injected before every step, alone and combined with one ECU failing its health check.
"""
import itertools

ECUS = ("gateway", "brake", "adas")
COMPATIBLE = {("1", "1", "1"), ("2", "2", "2")}


class Vehicle:
    def __init__(self, bad=None):
        self.ecu = {e: {"good": "1", "other": None, "running": "1", "trial": False} for e in ECUS}
        self.journal, self.bad, self.steps = "IDLE", bad, 0

    def tick(self, budget):
        """One persistent step; raises when the power budget is exhausted."""
        if budget[0] == 0:
            raise PowerCut
        budget[0] -= 1
        self.steps += 1

    def reset(self):
        for s in self.ecu.values():                      # one-shot trials fall back by themselves
            if s["trial"]:
                s["running"], s["trial"] = s["good"], False

    def trial_boot(self, e):
        s = self.ecu[e]
        s["running"], s["trial"] = s["other"], True
        return not (self.bad == e and s["running"] == "2")   # health check result

    def versions(self):
        return tuple(self.ecu[e]["running"] for e in ECUS)


class PowerCut(Exception):
    pass


def hardened(v, budget):
    for e in ECUS:                                       # phase 1: prepare
        v.tick(budget)
        v.ecu[e]["other"] = "2"
    v.tick(budget)
    v.journal = "PREPARED"
    healthy = True
    for e in ECUS:                                       # phase 2: trial every ECU
        v.tick(budget)
        healthy &= v.trial_boot(e)
    v.tick(budget)
    v.journal = "COMMITTING" if healthy else "ABORTING"
    finish(v, budget)


def finish(v, budget):
    if v.journal == "COMMITTING":
        for e in ECUS:
            s = v.ecu[e]
            if s["good"] == "2":
                continue
            if not s["trial"] or s["running"] != "2":    # a straggler after a crash: trial it again
                v.tick(budget)
                if not v.trial_boot(e):
                    v.tick(budget)
                    v.journal = "ABORTING"
                    return finish(v, budget)
            v.tick(budget)
            s["good"], s["other"], s["trial"] = "2", "1", False   # old bank kept until DONE
        v.tick(budget)
        v.journal = "DONE"
        for s in v.ecu.values():
            s["other"] = None
    elif v.journal in ("PREPARED", "ABORTING"):
        for e in ECUS:
            s = v.ecu[e]
            v.tick(budget)
            if s["good"] == "2":                         # was committed during a roll-forward: revert
                s["good"], s["other"] = "1", "2"
            s["running"], s["trial"] = s["good"], False
        v.tick(budget)
        v.journal = "IDLE"


def fragile(v, budget):
    for e in ECUS:
        v.tick(budget)
        v.ecu[e]["other"] = "2"
        v.tick(budget)
        if v.trial_boot(e):
            v.ecu[e]["good"], v.ecu[e]["trial"] = "2", False   # committed on its own, immediately
        else:
            v.reset()                                    # this ECU falls back; the others stay on v2


def run(protocol, bad, cut):
    v = Vehicle(bad)
    try:
        protocol(v, [cut])
    except PowerCut:
        v.reset()
        if protocol is hardened:                         # the gateway recovers from its journal
            finish(v, [-1])
    return v.versions()


def main():
    fails = 0
    for name, protocol in (("two-phase with journal", hardened), ("sequential flashing", fragile)):
        mixed, total, updated = 0, 0, None
        for bad in (None,) + ECUS:
            clean = run(protocol, bad, -1)
            if bad is None:
                updated = clean
            steps = Vehicle(bad)
            try:
                protocol(steps, [-1])
            except PowerCut:
                pass
            for cut in itertools.chain([-1], range(steps.steps + 1)):
                total += 1
                if run(protocol, bad, cut) not in COMPATIBLE:
                    mixed += 1
        print(f"{name:<24}: {total} scenarios, {mixed} end in an incompatible version set; "
              f"no-fault result {updated}")
        if protocol is hardened:
            fails += mixed != 0 or updated != ("2", "2", "2")
        else:
            fails += mixed == 0
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
two-phase with journal  : 56 scenarios, 0 end in an incompatible version set; no-fault result ('2', '2', '2')
sequential flashing     : 32 scenarios, 20 end in an incompatible version set; no-fault result ('2', '2', '2')
ALL PASSED: 0 failure(s)
```

What the model shows:
- **The two-phase protocol never ends in an incompatible version set** across every crash point and every single-ECU health failure.
- **The roll-forward/roll-back decision is made from a persisted journal.**
- **Committed ECUs keep their old bank until the whole system is DONE,** so a straggler failing during roll-forward can still bring everyone back.
- **Sequential flashing leaves most failure scenarios mixed.**

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Cause | Detect | Fix |
|---|---|---|---|
| Deltas are as large as full images in the field | Payload compressed or encrypted before chunking; per-build non-reproducible output (02.4) | Chunk reuse ratio per release | Chunk uncompressed or block-compressed images; reproducible builds; measure reuse in CI |
| Updates "install" but devices keep the old version | Client and bootloader use different variables (RAUC `uboot` vs custom U-Boot contract) | `fw_printenv` after install vs what U-Boot reads | One contract (§2.3); U7 lint |
| Partially written slot booted after power loss | Image installed before its signature or hash was verified (signing the compound file, not a manifest) | Install log order: write before verify | Signed manifest with per-image hashes, verified first (§1.3); verity bundles |
| RAUC slot status lost on every update | `statusfile` on the root filesystem | Status file missing after update | `data-directory` on persistent storage (U5) |
| Older bundle accepted | No `min-bundle-version`; version not semver | Install log | `min-bundle-version`; semver versions (U6, M3); plus TUF (03.3) |
| Vehicle with mixed ECU versions after a failed campaign | Sequential per-ECU commit | Version-set telemetry | Journaled two-phase update; old banks kept until DONE (§2.4) |
| Single-bank ECU bricked during FOTA | No second bank; flash erased before new image complete | ECU unresponsive | ROM bootloader recovery path; staging the image in the Primary; write-verify-swap only on dual-bank parts |

**Recovery.**
- **Client-level:** RAUC and SWUpdate leave the other slot intact, and the boot state machine (03.1) does the rest.
- **System-level:** the gateway's journal is the source of truth, so recovery is a deterministic function of journal plus ECU states, as in `finish()`.
- **Single-bank ECUs need their ROM bootloader's recovery protocol,** fed from a copy staged on the gateway.
- **Post-mortem:** collect the journal, each ECU's bank state and versions, and the client logs (`rauc status --detailed`, SWUpdate `recovery_status`).

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · "Our deltas are 95% smaller"

**Initial Prompt:** "The team reports block-level deltas 95% smaller than full images in testing. Ship it to the fleet?"

**L5 Answer:** "Yes. The bandwidth savings are huge; let's enable it for the next release."

**Why L5 Bricks Devices at Scale:** Test deltas are usually between two builds with almost no change.
- **One real release inserts or removes bytes early in the image** (a larger library, a new file in a sorted directory). Every later block shifts, and the "delta" becomes a full image (§2.1: 3 of 4 MiB).
- **Budgets fail:** cellular cost models and campaign durations planned on 5% fail by an order of magnitude.

**L7 Principal Defense:**
- **Measure on real release pairs,** and use content-defined chunking so boundaries follow content.
- **Make builds reproducible** so unchanged components produce unchanged bytes (02.4).
- **Chunk before compression.**
- **Set the chunk size from measurement,** and track the chunk reuse ratio per release as a KPI with a CI gate.

### Chain 2 · Client and bootloader disagree

**Initial Prompt:** "After integrating RAUC, installs report success but devices keep running the old slot. Diagnose."

**L5 Answer:** "Probably the install isn't finishing. Increase logging and check the bundle."

**Why L5 Bricks Devices at Scale:**
- **The install did finish.** RAUC set `BOOT_ORDER` and `BOOT_x_LEFT`, but U-Boot implements a different contract (03.1's `boot_slot`, `upgrade_available`, `bootcount`) and never reads them.
- **Debugging the bundle wastes weeks,** and "success" plus "mark-good" keeps lying.

**L7 Principal Defense:**
- **One boot contract between client and bootloader, owned by the platform team.** Either RAUC's `uboot` scheme with its U-Boot script, or `bootloader=custom` mapping onto the existing contract (§2.3).
- **Lint the pair** (U7).
- **Add an end-to-end test:** install, reboot, assert the running slot changed, mark good, assert the committed state.

### Chain 3 · What to sign

**Initial Prompt:** "We sign the entire update file. Isn't that the strongest option?"

**L5 Answer:** "Yes. Signing the whole file covers everything inside it."

**Why L5 Bricks Devices at Scale:**
- **Verification of a whole-file signature completes only after the whole file is read.** Streaming installers either buffer gigabytes (impossible on many devices) or install parts before verifying, which is exactly what SWUpdate's documentation warns against.
- **A file checked once and then reopened** can be swapped between check and use.

**L7 Principal Defense:**
- **Sign a manifest that carries per-image hashes,** verify it first, and verify each image as it streams.
- **For RAUC, use `verity` bundles:** the payload is protected by dm-verity while mounted.
- **The manifest also carries the `compatible` string and version,** checked against the device's configuration and minimum version.

### Chain 4 · Updating a vehicle

**Initial Prompt:** "A vehicle has a gateway, a brake controller and an ADAS ECU with interdependent versions. Design the update so the vehicle is never left in an incompatible state."

**L5 Answer:** "Update the ECUs one at a time, verifying each before moving on. If one fails, retry it."

**Why L5 Bricks Devices at Scale:**
- **Per-ECU commits create intermediate version mixes** that were never validated together.
- **A failure or power loss mid-sequence strands the vehicle in one of them,** and "retry" can fail indefinitely (§2.4: most sequential failure scenarios end mixed).
- **In a vehicle,** an incompatible gateway and brake controller is a safety problem, not an inconvenience.

**L7 Principal Defense:**
- **A journaled two-phase update:**
  - prepare every bank and verify it;
  - persist PREPARED;
  - trial-boot all ECUs together and collect health;
  - persist COMMITTING or ABORTING;
  - keep old banks until DONE.
- **Recovery is deterministic from the journal.**
- **Uptane full verification on the gateway** decides what each ECU may install (03.3).
- **Single-bank ECUs** get their image staged on the gateway and are flashed last, under the ROM's recovery protocol.
- **Model-check the protocol,** as `ecu_2pc.py` does, before writing it in C for the gateway.

### Chain 5 · Choosing an update client

**Initial Prompt:** "RAUC, SWUpdate, Mender, or build our own?"

**L5 Answer:** "Build our own. We have special requirements and want full control."

**Why L5 Bricks Devices at Scale:**
- **The hard parts are years of edge cases:** power-loss-safe slot writes, signature formats, verity bundles, bootloader backends, streaming, adaptive deltas.
- **A home-grown client rediscovers them in the field,** one fleet incident at a time.
- **"Full control" usually means no external security review** of the most attack-exposed code on the device.

**L7 Principal Defense:**
- **Decide on requirements:**
  - slot model (A/B, OSTree);
  - handlers needed (MCU, FPGA);
  - delta strategy;
  - backend integration;
  - license and support.
- **Prototype the top two on the target,** including power-cut testing.
- **Choose a mature client and own the integration:** the boot contract, the manifest policy, the health check.
- **Contribute fixes upstream.**

### Chain 6 · The single-bank microcontroller

**Initial Prompt:** "One ECU is a microcontroller with a single flash bank and a ROM bootloader. How do you update it safely?"

**L5 Answer:** "Erase and write the new firmware over CAN. If it fails, the technician can re-flash it."

**Why L5 Bricks Devices at Scale:** A vehicle that needs a technician after a failed OTA isn't an OTA product.
- **Erasing before the new image is complete** leaves nothing runnable on power loss.
- **The ROM recovery path must be reachable automatically** from the gateway, with the image staged locally, not re-downloaded.

**L7 Principal Defense:**
- **Stage the verified image on the gateway first.**
- **Use the MCU's ROM bootloader** (or a small, never-updated first-stage loader) that validates the application image CRC/signature before jumping and stays in a recovery protocol otherwise.
- **Flash last in the campaign,** after the A/B ECUs have committed.
- **Keep the gateway able to re-flash** the MCU's previous version from its staged copy.
- **Where the bill of materials allows,** choose dual-bank MCUs: hardware bank swap turns FOTA into A/B.

---

## 5. Invariants Checklist

- [ ] Delta strategy measured on real release pairs; CDC with a chunk size chosen from data; chunking before compression; reproducible builds.
- [ ] One boot contract between update client and bootloader, linted (U7) and tested end to end.
- [ ] Signed manifest with per-image hashes verified before any write; RAUC `bundle-formats=-plain`, `verity` bundles, `check-purpose=codesign`, `min-bundle-version`.
- [ ] Slot devices by stable names; client status in a persistent data directory.
- [ ] Multi-ECU: journaled two-phase update; old banks kept until DONE; deterministic recovery; Uptane full verification on the Primary.
- [ ] Single-bank components: staged image, ROM recovery path, flashed last.

## 6. References

- casync v2: `src/cachunker.c`, `src/cachunker.h`, `src/util.h`. <https://github.com/systemd/casync/tree/v2>
- RAUC v1.15.2 documentation: reference (system.conf, manifest), integration (U-Boot, custom bootloader backend). <https://rauc.readthedocs.io/en/latest/>
- SWUpdate documentation (2026.05.1): overview (transactions, `recovery_status`), signed images, `sw-description`. <https://sbabic.github.io/swupdate/>
- Mender documentation (artifact format, state scripts). <https://docs.mender.io/>
- Uptane Standard 2.1.0 (Primary/Secondary roles). <https://uptane.org/docs/2.1.0/standard/uptane-standard>
- In this KB: [03.1 boot state machine](01-sota-vs-fota-ab-symmetric-asymmetric-and-bootloader-fallback-state-machine.md) · [03.3 TUF and Uptane](03-tuf-the-update-framework-uptane-role-keys-threshold-signing-and-anti-rollback.md) · [02.4 reproducible builds](../02-Yocto-Project-BitBake-and-Cross-Toolchain-Internals/04-sbom-spdx-cve-patching-reproducible-builds-and-license-compliance.md)
