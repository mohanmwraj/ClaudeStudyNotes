# 02.2 · BSP Layer Engineering: Machine and Distro Configuration, Overrides, the Kernel, and devtool

> **Folder 02 · File 2 of 4.** A board support package is where hardware facts, product policy and kernel configuration meet. Most BSP layers in the field are the vendor's evaluation-kit layer, copied once and patched until it boots. Production then inherits every shortcut:
> - priority 99;
> - policy in the machine file;
> - keys in the layer;
> - a kernel built from a copied defconfig;
> - a disk layout sized to the first release.
>
> This file builds the layer the way a maintainer would, and proves each piece:
> - **Layer mechanics.** Collections, priorities, series compatibility, bbappend matching, file search paths.
> - **The three axes.** What belongs in machine, distro and image configuration, and how `OVERRIDES` composes them.
> - **The kernel.** linux-yocto's metadata model: BSP descriptions, `.scc` and `.cfg` fragments, the configuration audit, and why an *additive* hardened configuration passes the audit where a *subtractive* one fails.
> - **The signed kernel FIT in 6.x.** The recipe split, how U-Boot gets its public key, and a check the build system doesn't do for you.
> - **The storage layout.** A/B partitions placed exactly where the BootROM and the update client need them.
> - **devtool and the kernel configuration workflow.**
>
> **Verification.**
> - Every listing below is the tested file.
> - `bb_lint.py` checks variable names against an index built from oe-core and BitBake at `yocto-6.1`.
> - `scc_audit.py` resolves the BSP description against **yocto-kernel-cache** at the commit linux-yocto 7.2 pins (`SRCREV_meta = 242eecdf…`). It follows the search rules of **kern-tools'** `spp` at the commit oe-core pins (`96a8d58b…`), and checks symbols against **Linux v7.2** Kconfig.
> - `wks_check.py` reads the option table of **wic 0.3.1** (the standalone wic that oe-core 6.1 packages, at its recipe's `SRCREV`) and mirrors wic's partition placement code.
>
> No BitBake, kernel build or wic run happens here: this environment can't run downloaded build tools (README).

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 Layers: collections, priority, compatibility

```text
 bblayers.conf: BBLAYERS = ".../oe-core/meta  .../meta-acme-bsp  .../meta-acme-distro  .../meta-acme-product"
                                 │                  │                    │                     │
 conf/layer.conf of each ──► BBPATH += layer dir   (classes, conf files searched along BBPATH)
                             BBFILES += recipe globs (what gets parsed; *.bbappend must be listed too)
                             BBFILE_COLLECTIONS += name ; BBFILE_PATTERN_name = "^${LAYERDIR}/"
                             BBFILE_PRIORITY_name  (who wins when two layers provide the same recipe)
                             LAYERDEPENDS_name, LAYERSERIES_COMPAT_name
 priorities:   oe-core = 5  <  BSP = 8  <  distro = 10  <  product = 12     (oe-core's own layer.conf: 5)
```

**Priority** decides two things:
- which layer's recipe wins when the same recipe name exists in several layers (`bitbake-layers show-overlayed`);
- the order in which bbappends are applied.

A BSP at 99 outranks the distro and product layers that are supposed to refine it.

**Series compatibility** is enforced. oe-core 6.1 declares `LAYERSERIES_CORENAMES = "blacksail"` and `LAYERSERIES_COMPAT_core = "blacksail"`. A layer whose `LAYERSERIES_COMPAT_<name>` doesn't include the core series fails parsing:

> Layer %s is not compatible with the core layer which only supports these series: %s (layer is compatible with %s)

So `"wrynose blacksail"` means *tested on 6.0 LTS and 6.1*, and builds on both. Adding a series you never built is a lie the parser can't catch.

**bbappend matching** happens in BitBake's cooker (`get_file_appends`), and has three rules:
- Everything before `%` is a **prefix** of the recipe file name. `linux-yocto_%.bbappend` matches `linux-yocto_6.18.bb` and `linux-yocto_7.2.bb` (both shipped in oe-core 6.1). `linux-yocto%.bbappend` would also match `-rt`, `-tiny` and `-fitimage`.
- An append that matches nothing is **fatal**, in `show_appends_with_no_recipes`. The old escape hatch `BB_DANGLINGAPPENDS_WARNONLY` is now listed in `BB_RENAMED_VARIABLES` as removed.
- An append is only seen at all if the layer's `BBFILES` includes `*.bbappend`.

### 1.2 The three axes and OVERRIDES

| Axis | File | Contains | Must not contain |
|---|---|---|---|
| **Hardware** | `conf/machine/<MACHINE>.conf` | CPU tune, kernel and bootloader providers, device trees, consoles, media and partition layout | Package lists, distro features, licensing, signing policy |
| **Policy** | `conf/distro/<DISTRO>.conf` | Init system, C library, `DISTRO_FEATURES`, license policy, signing policy, security defaults | Board facts |
| **Content** | `recipes-*/images/*.bb` | `IMAGE_INSTALL`, `IMAGE_FEATURES`, image-specific settings | Hardware or global policy |

oe-core 6.1 `meta/conf/bitbake.conf` composes the override list as:

```text
OVERRIDES = "${TARGET_OS}:${TRANSLATED_TARGET_ARCH}:pn-${PN}:layer-${FILE_LAYERNAME}:${MACHINEOVERRIDES}:${DISTROOVERRIDES}:${CLASSOVERRIDE}:${TCOVERRIDE}${LIBCOVERRIDE}:forcevariable"
MACHINEOVERRIDES ?= "${MACHINE}"          (tune files prepend e.g. "armv8a:" with  =.)
DISTROOVERRIDES ?= "${@d.getVar('DISTRO') or ''}"
FILESOVERRIDES = "${TRANSLATED_TARGET_ARCH}:${MACHINEOVERRIDES}:${DISTROOVERRIDES}"
```

- **Later entries have higher priority** (02.1 §1.3), so a distro override beats a machine override of the same variable, and `forcevariable` beats everything.
- **`FILESOVERRIDES` drives file lookup.** `FILESPATH` (`base.bbclass`: `${FILE_DIRNAME}/${BP}`, `${FILE_DIRNAME}/${BPN}`, `${FILE_DIRNAME}/files`, after any `FILESEXTRAPATHS`) is searched once for each override directory. So `files/acme-imx8m/foo.cfg` beats `files/foo.cfg` for that machine only: a cleaner tool than conditional `SRC_URI` for per-board variants.

### 1.3 CPU tune: one flag, one ABI decision

`tune-cortexa53.inc` (oe-core 6.1) has three tunes: `cortexa53`, `cortexa53-crypto` and `cortexa53-nocrypto`. The default, `DEFAULTTUNE ?= "cortexa53"`, has `TUNE_FEATURES` = `aarch64 crc cortexa53`, with **no crypto**.

`feature-arm-crypto.inc` appends `+crypto` to `TUNE_CCARGS_MARCH_OPTS`. Cortex tunes leave `TUNE_CCARGS_MARCH` empty, so the options are concatenated onto `-mcpu`. The crypto tune therefore compiles with `-mcpu=cortex-a53+crc+crypto`.

| Decision | Effect |
|---|---|
| `cortexa53` on a SoC that has the Cryptography Extension | Compiler never emits AES/SHA/PMULL; libraries that use runtime detection still work, others run slower |
| `cortexa53-crypto` on a SKU **without** it | Any code compiled to use those instructions takes `SIGILL` on that SKU. The extension is optional on the A53, and some vendors ship SKUs without it |
| Package architecture | `ARMPKGARCH` becomes `cortexa53-crypto`, so feeds built for one tune are a different architecture from the other's |

**Rule:** a tune is a promise about every device that will ever run the image. Different SKUs mean different `MACHINE`s (or a shared, lower tune), never one image "that mostly works".

### 1.4 linux-yocto's metadata model

```text
 SRC_URI (recipe + bbappends)
   ├── git://.../linux-yocto (KBRANCH: v7.2/standard/base)      kernel source
   ├── git://.../yocto-kernel-cache;type=kmeta (SRCREV_meta)    the "kernel cache": ktypes/, features/, cfg/, bsp/
   └── file://acme-imx8m-standard.scc, *.cfg, *.patch           our BSP description and fragments
 do_kernel_metadata:
   spp --find -DKMACHINE=${KMACHINE} -DKTYPE=${LINUX_KERNEL_TYPE}  → BSP description (.scc whose defines match)
       none found and no defconfig → bbfatal "Could not locate BSP definition for <KMACHINE>/<KTYPE> and no defconfig was provided"
   scc ... $defconfig $bsp_definition $SRC_URI-sccs/cfgs $KERNEL_FEATURES   → config queue (this order; later wins)
 do_kernel_configme: merge_config.sh -O ${B} <queue>                         → .config
 do_kernel_configcheck (after do_configure): symbol_why.py audits
   1 mismatches  "specified values did not make it into the kernel's final configuration"  KCONF_AUDIT_LEVEL ≥ 1
                 (level 1 adds --classify: only boot-relevant options are shown; level 2 shows all)
   2 invalid     fragment lines no Kconfig defines                                         KCONF_BSP_AUDIT_LEVEL ≥ 1
                 (≥ 2 adds --strict: also symbols that exist only for other architectures)
   3 redefined   "defined in more than one config, with differing values"                  KCONF_BSP_AUDIT_LEVEL > 2
   any warning + KMETA_AUDIT_WERROR → bb.fatal("configuration warnings detected, werror is set, promoting to fatal")
```

Two consequences matter most:

- **Defaults hide failures.** `KCONF_AUDIT_LEVEL ?= "1"`, `KCONF_BSP_AUDIT_LEVEL ?= "0"` and `KMETA_AUDIT_WERROR ?= ""`. A fragment line naming a symbol that no longer exists is not even reported, and a value that a dependency blocked is shown only if it looks boot-relevant.
- **Subtractive hardening fails a strict audit.**
  - `ktypes/standard/standard.scc` pulls in kgdb, kexec, kprobes, debugfs and more. A product fragment that switches `KGDB` off leaves `kgdb.cfg`'s `CONFIG_KGDB_KDB=y` requesting a value that can no longer exist. Under a strict audit that is a fatal mismatch.
  - At the pinned cache commit, `standard.cfg` itself requests `CRYPTO_ARC4`, `TEA`, `KHAZAD` and `ANUBIS`, while the same type's `cfg/crypto-obsolete-disable.scc` switches off `CRYPTO_USER_API_ENABLE_OBSOLETE`, which all four depend on.
  - The hardened BSP below therefore builds **additively** on `ktypes/base` plus the features the product needs.

### 1.5 The signed kernel FIT in 6.x

```text
 u-boot recipe (uboot-sign.bbclass, UBOOT_SIGN_ENABLE = "1")         linux-yocto-fitimage recipe (kernel-fit-image.bbclass)
   mkimage -f auto-conf -k ${UBOOT_SIGN_KEYDIR} -K u-boot.dtb          builds fit-image.its from virtual/kernel's deployed
           -d /dev/null -r unused.itb  ${UBOOT_MKIMAGE_SIGN_ARGS}      artifacts (needs KERNEL_CLASSES += "kernel-fit-extra-artifacts")
      → public key written into u-boot.dtb /signature                 oe/fitimage.py run_mkimage_sign():
   uboot-fit_check_sign -k u-boot.dtb -f unused.itb                    mkimage -F -k ${FIT_KERNEL_SIGN_KEYDIR} -r fitImage ${UBOOT_MKIMAGE_SIGN_ARGS}
      → verifies the DUMMY image only                                    (key-file sanity check SKIPPED for pkcs11: keydirs)
   deploys u-boot-${MACHINE}.dtb                                     deploys fitImage, fit-image.its
                 ╲                                                        ╱
                  ╲──────────── nothing checks the real fitImage against the deployed U-Boot key ───╱
```

- `FIT_KERNEL_SIGN_ENABLE`, `FIT_KERNEL_SIGN_KEYNAME` and `FIT_KERNEL_SIGN_KEYDIR` default (`?=`) to the `UBOOT_SIGN_*` values, so one distro setting signs both.
- oe-core's own comment in `uboot-sign.bbclass` warns that individually signed images make a FIT "susceptible to mix-and-match attack", and recommends `FIT_SIGN_INDIVIDUAL = "0"`, signing configurations, as Folder 01's 01.4 does. The class also states the limitation: "The signature support is limited to the use of CONFIG_OF_SEPARATE in U-Boot."
- `oe/fitimage.py` notes that "mkimage exits with 0 also without needed keys". It checks key files only for directory keydirs; for a PKCS#11 URI it skips the check.

The production answer is a task that verifies the real FIT against the real U-Boot DTB (§2.5).

### 1.6 Storage layout: where the bytes must be

```text
 eMMC user area (512-byte sectors)                                    who needs it there
 0 KiB      ┌ protective MBR + GPT header + 128 entries (LBA 0-33) ┐  wic reserves GPT_OVERHEAD = 34 sectors itself
 17 KiB     │ (gap)                                                 │
 33 KiB     │ boot container: SPL + DDR firmware + TF-A + U-Boot    │  the SoC BootROM reads it at a FIXED offset
            │                                                       │  (33 KiB for this i.MX8M Mini-class part) ⚠
 4 MiB      ├ boot_a   (raw FIT, fixed 64 MiB)                       │  U-Boot: "part number mmc <dev> boot_a"
 68 MiB     ├ boot_b                                                │
 132 MiB    ├ rootfs_a (squashfs + verity, fixed 1536 MiB)           │  update client writes the inactive slot
 1668 MiB   ├ rootfs_b                                              │
 3204 MiB   ├ data     (ext4, persistent)                            │  never touched by an update
 ...        └ backup GPT (last 33 sectors)                          ┘
```

wic places each partition after its own table overhead, rounded up to `--align`, wherever that happens to fall. It does not know the BootROM's offset:
- with `--align 1`, the boot container lands at **17 KiB**, and the board never starts;
- `--align 33` puts it at 33 KiB.

Three more wic behaviours matter for A/B (wic 0.3.1 source):
- **Undefined variables vanish.** `do_write_wks_template` (oe-core `image_types_wic.bbclass`) deletes undefined `${VAR}` references in `.wks.in` files ("Remove any remnant variable references left behind by the expansion due to undefined variables").
- **wic edits the root filesystem.** `update_fstab` appends a line to the root filesystem's `/etc/fstab` for every mounted partition, unless the root partition says `--no-fstab-update`. The factory slot then differs from the update artifact (and from its dm-verity hash).
- **Disk names without an index break.** For a disk named `mmcblk` with no index and no `--use-uuid`/`--use-label`, the line is `/dev/mmcblkp<N>`, a device that doesn't exist.

⚠ The 33 KiB offset is specific to this SoC family and boot medium. Take it from the SoC reference manual's boot chapter, never from another board's `.wks`.

---

## 2. Production Code & Configuration Blueprints

### 2.1 layer.conf

#### The Fragile Way

```bitbake
# layer-fragile.conf - the BSP layer.conf as copied from an old vendor BSP
BBPATH .= ":${LAYERDIR}"
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb"
BBFILE_COLLECTIONS += "acme-bsp"
BBFILE_PATTERN_acme-bsp = "^${LAYERDIR}/"
BBFILE_PRIORITY_acme-bsp = "99"
LAYERSERIES_COMPAT_acme-bsp = "kirkstone scarthgap wrynose blacksail"
```

What's wrong with it:
- **`BBFILES` has no `*.bbappend`**, so every append in this layer is silently ignored.
- **Priority 99** outranks every distro and product layer.
- **It claims two series it was never built on.** The parser can only check the core series, so this claim is invisible to it.

#### The Silicon-Hardened Production Way

```bitbake
# layer.conf - meta-acme-bsp: BSP layer for the Acme Cortex-A53 board (Yocto 6.0 "wrynose" LTS and 6.1 "blacksail")
BBPATH .= ":${LAYERDIR}"

# Both recipes AND bbappends: a pattern without *.bbappend silently drops every append in the layer.
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "acme-bsp"
BBFILE_PATTERN_acme-bsp = "^${LAYERDIR}/"
# Above oe-core (5), below product layers: a BSP should win over core, never over the distro or product.
BBFILE_PRIORITY_acme-bsp = "8"

LAYERVERSION_acme-bsp = "1"
LAYERDEPENDS_acme-bsp = "core"
# The releases this layer is tested against. bitbake refuses to parse it with any other oe-core series.
LAYERSERIES_COMPAT_acme-bsp = "wrynose blacksail"
```

### 2.2 Machine and distro configuration

#### The Fragile Way

```bitbake
# acme-imx8m-fragile.conf - the machine.conf every vendor BSP review finds at least once
require conf/machine/include/arm/armv8a/tune-cortexa53.inc
KERNEL_DEVICETREE = "imx8mm-acme.dtb"
KERNEL_DEVICETREE_append = " imx8mm-acme-rev2.dtb"
UBOOT_MACHINE = "acme_imx8mm_defconfig"
IMAGE_INSTALL:append = "openssh htop"
DISTRO_FEATURES:append = " wayland"
UBOOT_SIGN_ENABLE = "1"
UBOOT_SIGN_KEYDIR = "${LAYERDIR}/keys"
FIT_GENERATE_KEYS = "1"
```

What's wrong with it:
- **Old `_append` syntax**, which is fatal.
- **An `:append` without a leading space**, so `openssh` fuses with the previous word.
- **Distro and image policy in the machine file.**
- **Signing keys inside the layer.**
- **A key generated per build directory** (`FIT_GENERATE_KEYS = "1"` pulls in `kernel-signing-keys-native`): every builder signs with a different key.

#### The Silicon-Hardened Production Way

Machine: hardware facts only, including the tune decision of §1.3 and the boot container's name for the layout.

```bitbake
# acme-imx8m.conf - machine configuration: hardware facts only (CPU tune, kernel/DTB, bootloader, consoles, media)
#@TYPE: Machine
#@NAME: Acme i.MX8M-class board
#@DESCRIPTION: Quad Cortex-A53, eMMC with RPMB, A/B boot slots, signed FIT (see Folder 01)

require conf/machine/include/arm/armv8a/tune-cortexa53.inc
# This SoC's A53 cores implement the optional Cryptography Extension: -mcpu=cortex-a53+crc+crypto.
# A SKU without it (check /proc/cpuinfo for "aes pmull sha1 sha2") needs its own MACHINE and package feed.
DEFAULTTUNE = "cortexa53-crypto"

MACHINE_FEATURES = "ext2 serial usbhost wifi bluetooth"
SERIAL_CONSOLES = "115200;ttymxc1"

PREFERRED_PROVIDER_virtual/kernel ?= "linux-yocto"
PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot"
UBOOT_MACHINE = "acme_imx8mm_defconfig"

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = "freescale/imx8mm-acme.dtb"
# oe-core 6.x builds the signed kernel FIT in the separate linux-yocto-fitimage recipe; the kernel
# recipe must export the artifacts it needs.
KERNEL_CLASSES += "kernel-fit-extra-artifacts"

IMAGE_FSTYPES = "wic.zst squashfs"
WKS_FILE = "acme-ab.wks.in"
# The boot container (SPL + DDR training firmware + TF-A + U-Boot) deployed by the SoC vendor's boot-image
# recipe; acme-ab.wks.in places it at the BootROM's read offset.
ACME_BOOT_CONTAINER = "imx-boot"
```

Distro: the policy, including signing through PKCS#11 so that no key file exists on any builder.

```bitbake
# acme.conf - distro policy (meta-acme-distro/conf/distro/acme.conf): features, init, libc, licensing, signing
DISTRO = "acme"
DISTRO_NAME = "Acme Embedded Linux"
DISTRO_VERSION = "2026.10"

INIT_MANAGER = "systemd"
TCLIBC = "glibc"
DISTRO_FEATURES = "acl ipv6 largefile usbhost wifi bluetooth seccomp pam"

# Licensing policy: GPLv3-family code may not ship in the product image. Only these three wildcards
# exist (oe/license.py expand_wildcard_licenses); anything else with '*' is a fatal error.
INCOMPATIBLE_LICENSE = "GPL-3.0* LGPL-3.0* AGPL-3.0*"

# Signed FIT policy from 01.4, applied to oe-core's linux-yocto-fitimage recipe. The key never lives in
# a layer: a PKCS#11 URI makes oe/fitimage.py skip the key-file check and pass the URI to mkimage -k.
UBOOT_SIGN_ENABLE = "1"
UBOOT_SIGN_KEYNAME = "fit-release-2026"
UBOOT_SIGN_KEYDIR = "pkcs11:token=fw-release"
UBOOT_MKIMAGE_SIGN_ARGS = "-N pkcs11"
FIT_HASH_ALG = "sha256"
FIT_SIGN_ALG = "rsa3072"
FIT_SIGN_NUMBITS = "3072"
FIT_PAD_ALG = "pss"
FIT_SIGN_INDIVIDUAL = "0"
FIT_GENERATE_KEYS = "0"

# Shared build cache: everyone reads, only CI writes (see 02.1 section 2.2).
BB_SIGNATURE_HANDLER = "OEEquivHash"
```

### 2.3 The kernel: BSP description and fragments

#### The Fragile Way

```bitbake
# linux-yocto-fragile.bbappend - a kernel bbappend that "works on my machine"
FILESEXTRAPATHS_prepend := "${THISDIR}/files"
SRC_URI += "file://defconfig file://0001-hack-disable-cpuidle.patch"
RDEPENDS_${PN} += "kernel-module-acme-wdt"
do_configure:append() {
    cp ${UNPACKDIR}/defconfig ${B}/.config
}
```

What's wrong with it:
- **Copying a defconfig over `.config` in `do_configure:append`** runs after `do_kernel_configme`. It throws away every fragment, feature and audit, and the configuration becomes whatever that file held when someone last copied it.
- **The unconditional `SRC_URI +=`** applies a CPU-idle hack to every machine that builds linux-yocto.
- **`RDEPENDS_${PN}`** sets an unused variable, so the watchdog module never ships (02.1 Chain 5).

The same "subtract from standard" thinking, expressed in kernel metadata:

```text
# acme-imx8m-fragile-standard.scc - start from the standard kernel type, then switch off what production must not ship
define KMACHINE acme-imx8m
define KTYPE standard
define KARCH arm64

include ktypes/standard/standard.scc

kconf hardware acme-board.cfg
kconf non-hardware acme-legacy-fragile.cfg
kconf non-hardware acme-subtract-fragile.cfg
```

```text
# acme-legacy-fragile.cfg - the hardening fragment carried forward from a 4.x-era vendor BSP
CONFIG_CC_STACKPROTECTOR_STRONG=y
CONFIG_DEBUG_RODATA=y
CONFIG_DEBUG_SET_MODULE_RONX=y
# CONFIG_DEVKMEM is not set
# CONFIG_USELIB is not set
CONFIG_MODULE_SIG=y
```

```text
# acme-subtract-fragile.cfg - "turn the debug features off" on top of ktypes/standard
# CONFIG_KGDB is not set
# CONFIG_KEXEC is not set
# CONFIG_DEVMEM is not set
CONFIG_STRICT_DEVMEM=y
```

#### The Silicon-Hardened Production Way

The bbappend ships an external BSP description and makes the configuration audit strict and fatal:

```bitbake
# linux-yocto_%.bbappend - board kernel for acme-imx8m: an external BSP description plus config fragments
# := expands THISDIR now (it would otherwise expand later, in another file's context). The trailing ':'
# separates this path from the existing search path.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

COMPATIBLE_MACHINE:acme-imx8m = "acme-imx8m"

# do_kernel_metadata looks up a BSP description by KMACHINE/KTYPE; without one (or a defconfig) it stops
# with "Could not locate BSP definition". The .cfg files are listed so the fetcher stages them; the .scc
# decides their order. Machine-scoped, with the leading space that keeps the list well formed.
SRC_URI:append:acme-imx8m = " \
    file://acme-imx8m-standard.scc \
    file://acme-board.cfg \
    file://acme-hardening.cfg \
    file://0001-arm64-dts-freescale-add-imx8mm-acme.patch \
"

# Every requested value must reach .config: report all mismatches (2) and fragment lines no Kconfig
# defines (1), and fail the build on any of them instead of printing a warning nobody reads.
KCONF_AUDIT_LEVEL:acme-imx8m = "2"
KCONF_BSP_AUDIT_LEVEL:acme-imx8m = "1"
KMETA_AUDIT_WERROR:acme-imx8m = "1"
```

The BSP description is additive (§1.4):

```text
# acme-imx8m-standard.scc - linux-yocto BSP description for acme-imx8m, kept in the BSP layer (not the kernel cache)
# do_kernel_metadata finds this file by its defines (KMACHINE = MACHINE, KTYPE = LINUX_KERNEL_TYPE).
define KMACHINE acme-imx8m
define KTYPE standard
define KARCH arm64

# Additive: the minimal base type plus exactly the features the product needs. Starting from
# ktypes/standard and disabling its debug features (kgdb, kexec, kprobes...) strands their dependent
# options, which the configuration audit then reports as values that never reached .config.
include ktypes/base/base.scc
include cfg/systemd.scc
include cfg/fs/ext4.scc
include features/cgroups/cgroups.scc
include features/seccomp/seccomp.scc
include features/bpf/bpf.scc
include features/landlock/landlock.scc
include features/ftrace/ftrace.scc
include features/mmc/mmc-block.scc
include features/mmc/mmc-sdhci.scc
include features/optee/optee.scc
include features/rpmb/rpmb-base.scc
include features/security/security.scc

kconf hardware acme-board.cfg
kconf non-hardware acme-hardening.cfg
```

Board facts, classified `hardware`:

```text
# acme-board.cfg - kernel options the Acme i.MX8MM board needs: SoC, console, storage, watchdog, TEE, boot chain
CONFIG_ARCH_MXC=y
CONFIG_CLK_IMX8MM=y
CONFIG_PINCTRL_IMX8MM=y
CONFIG_GPIO_MXC=y
CONFIG_SERIAL_IMX=y
CONFIG_SERIAL_IMX_CONSOLE=y
CONFIG_SERIAL_IMX_EARLYCON=y
CONFIG_MMC_SDHCI_ESDHC_IMX=y
CONFIG_IMX_SDMA=y
CONFIG_I2C_IMX=y
CONFIG_SPI_IMX=m
CONFIG_IMX2_WDT=y
# The watchdog keeps running from U-Boot through to the userspace daemon: a hang anywhere resets the board.
CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y
CONFIG_WATCHDOG_NOWAYOUT=y
CONFIG_TEE=y
CONFIG_OPTEE=y
CONFIG_RPMB=y
CONFIG_DM_VERITY=y
CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG=y
CONFIG_SQUASHFS=y
CONFIG_SQUASHFS_ZSTD=y
CONFIG_FS_ENCRYPTION=y
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
```

Product policy, classified `non-hardware` and placed last:

```text
# acme-hardening.cfg - kernel self-protection and attack-surface reduction for a production image
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_STRICT_KERNEL_RWX=y
CONFIG_STRICT_MODULE_RWX=y
CONFIG_RANDOMIZE_BASE=y
CONFIG_UNMAP_KERNEL_AT_EL0=y
CONFIG_ARM64_SW_TTBR0_PAN=y
CONFIG_HARDENED_USERCOPY=y
CONFIG_FORTIFY_SOURCE=y
CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y
CONFIG_INIT_STACK_ALL_ZERO=y
CONFIG_SLAB_FREELIST_RANDOM=y
CONFIG_SLAB_FREELIST_HARDENED=y
CONFIG_SHUFFLE_PAGE_ALLOCATOR=y
CONFIG_LIST_HARDENED=y
# ktypes/base sets DEBUG_KERNEL=n, which silently strands security.cfg's DEBUG_LIST, DEBUG_SG,
# DEBUG_NOTIFIERS and SCHED_STACK_END_CHECK. On its own it only makes those options selectable.
CONFIG_DEBUG_KERNEL=y
CONFIG_BUG_ON_DATA_CORRUPTION=y
CONFIG_PANIC_ON_OOPS=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
# Only signed modules load; the signing key is the build's, injected by CI, never committed.
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_SHA512=y
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y
CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y
CONFIG_SECURITY_DMESG_RESTRICT=y
# CONFIG_PROC_KCORE is not set
# CONFIG_KEXEC is not set
# CONFIG_LEGACY_TIOCSTI is not set
# CONFIG_LDISC_AUTOLOAD is not set
# CONFIG_BINFMT_MISC is not set
```

Three entries in that fragment exist because of what the audit found, not because of a checklist:
- **`CONFIG_DEBUG_KERNEL=y`.** `ktypes/base/base.cfg` sets `DEBUG_KERNEL=n`, which strands `features/security/security.cfg`'s `DEBUG_LIST`, `DEBUG_SG`, `DEBUG_NOTIFIERS` and `SCHED_STACK_END_CHECK` (all `depends on DEBUG_KERNEL`).
- **No `# CONFIG_DEVMEM is not set` with `STRICT_DEVMEM=y`.** `STRICT_DEVMEM` `depends on MMU && DEVMEM` in v7.2, so asking for both is a request that can't be met. `security.cfg` keeps `/dev/mem` with `STRICT_DEVMEM` and `IO_STRICT_DEVMEM`, and lockdown in integrity mode closes `/dev/mem` access at runtime anyway.
- **No removed symbols** (`CC_STACKPROTECTOR_STRONG`, `DEBUG_RODATA`, `DEBUG_SET_MODULE_RONX`, `DEVKMEM`, `USELIB`): their replacements or nothing.

**The audit, before any kernel build.** `scc_audit.py` resolves the description the way `spp`/`scc` do:
- `include` searches the `-I` paths (kernel cache first, then the `SRC_URI` directories) before the including file's own directory;
- `kconf` searches its own directory first;
- names fall back to `<name>/<basename>.scc`, which is how `include features/bfq.scc` finds `features/bfq/bfq.scc`.

It then merges in queue order and checks every value against v7.2 Kconfig:

```python
# scc_audit.py - resolve a linux-yocto BSP description (.scc) statically, before a 30-minute kernel build
"""Usage: python scc_audit.py [-v] --cache <yocto-kernel-cache> --linux <kernel tree> [--deny SYM=VAL ...] <bsp.scc>

Walks include / kconf / if-elif-else-fi the way kern-tools' spp and scc do (search order and file-name
fallbacks of spp's search_include_paths; KARCH, KMACHINE, KTYPE from the BSP's own defines), collects
every CONFIG_ assignment in merge order (later wins, as in merge_config.sh), and reports what
kernel-yocto's do_kernel_configcheck would only tell you after configuring:
  S1 a symbol no Kconfig of any architecture defines (symbol_why --invalid, the KCONF_BSP_AUDIT_LEVEL=1
     check); a symbol that exists only for other architectures is printed as a note (the --strict check)
  S2 a value our fragments redefine from an upstream one   (informational: the intended overrides)
  S3 a final value the product policy denies (--deny)      (e.g. KGDB=y, PROC_KCORE=y on a production BSP)
  S4 an include or kconf target that exists nowhere        (spp stops: "could not find file")
  S5 a requested y/m whose dependency this configuration sets to n: the value cannot reach .config
     ("specified values did not make it": fatal under KMETA_AUDIT_WERROR = "1")
S5 evaluates plain conjunctions (A && !B && C) from "depends on" and from enclosing "if" blocks in the
same Kconfig file; conditions inherited through "source", select and choices are not modeled, so the
real do_kernel_configcheck stays in the pipeline. Findings in our files are errors; findings inside the
kernel cache are counted (upstream's to fix). An S5 counts as ours if we requested the value or if our
fragment is the one that switched its dependency off.
"""
import pathlib
import re
import sys

ASSIGN = re.compile(r"^CONFIG_([A-Za-z0-9_]+)=([^#\s]*)")
UNSET = re.compile(r"^# CONFIG_([A-Za-z0-9_]+) is not set")
EXTS = (".patch", ".cfg", ".config", ".scc")


def kconfig_model(tree, karch):
    """(symbol -> 'depends on' expressions for KARCH, every symbol defined by any architecture)."""
    deps, everywhere = {}, set()
    for kc in sorted(pathlib.Path(tree).rglob("Kconfig*")):
        if not kc.is_file():
            continue
        parts = kc.relative_to(tree).parts
        foreign = parts[0] == "arch" and len(parts) > 2 and parts[1] != karch
        current, in_help, guards = None, False, []         # guards: enclosing "if EXPR" blocks
        for line in kc.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^\s*(?:menu)?config\s+([A-Z0-9_]+)\s*$", line)
            if m:
                everywhere.add(m.group(1))
                current, in_help = (None if foreign else m.group(1)), False
                if current:
                    deps.setdefault(current, []).extend(guards)
            elif re.match(r"^if\s+", line):
                guards.append(re.sub(r"^if\s+", "", line).split("#")[0].strip())
                current, in_help = None, False
            elif re.match(r"^endif\b", line):
                guards = guards[:-1]
                current, in_help = None, False
            elif re.match(r"^\s*(menu|endmenu|choice|endchoice|if|endif|comment|source)\b", line):
                current, in_help = None, False
            elif re.match(r"^\s*(help|---help---)\s*$", line):
                in_help = True
            elif current and not in_help and re.match(r"^\s*depends on\s+", line):
                deps[current].append(re.sub(r"^\s*depends on\s+", "", line).split("#")[0].strip())
    return deps, everywhere


def condition(expr, defines):
    """[ "$KARCH" = "arm64" ] || [ "$KMACHINE" != "x" ] ... as spp evaluates it."""
    tests = re.findall(r'\[\s*"\$(\w+)"\s*(!?=)\s*"([^"]*)"\s*\]', expr)
    return any((defines.get(var, "") == val) == (op == "=") for var, op, val in tests)


class Resolver:
    def __init__(self, includes):
        self.includes = [pathlib.Path(p) for p in includes]   # -I order: kernel cache, then SRC_URI dirs
        self.defines, self.assignments, self.missing, self.files = {}, [], [], []

    @staticmethod
    def candidates(base, name):
        """spp search_include_paths(): name+ext, raw name, name/name+ext, name/name, name/basename+ext."""
        ext = next((e for e in EXTS if name.endswith(e)), ".scc")
        tgt = name[:-len(ext)] if name.endswith(ext) else name
        leaf = pathlib.PurePosixPath(tgt).name
        for rel in (tgt + ext, tgt, f"{tgt}/{tgt}{ext}", f"{tgt}/{tgt}", f"{tgt}/{leaf}{ext}", f"{tgt}/{leaf}"):
            yield base / rel

    def find(self, name, here, kind):
        # include: -I paths first, the including file's directory last; kconf: its directory first
        order = [*self.includes, here] if kind == "include" else [here, *self.includes]
        for base in order:
            for path in self.candidates(base, name):
                if path.is_file():
                    return path
        return None

    def walk(self, scc, nocfg=False):
        here = scc.parent
        stack = []                          # (taking this branch?, has a branch already been taken?)
        for raw in scc.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            words = line.split()
            if words[0] == "if":
                take = all(t for t, _ in stack) and condition(line, self.defines)
                stack.append((take, take))
                continue
            if words[0] == "elif":
                taken = stack[-1][1]
                take = not taken and all(t for t, _ in stack[:-1]) and condition(line, self.defines)
                stack[-1] = (take, taken or take)
                continue
            if words[0] == "else":
                stack[-1] = (not stack[-1][1] and all(t for t, _ in stack[:-1]), True)
                continue
            if words[0] == "fi":
                stack.pop()
                continue
            if not all(t for t, _ in stack):
                continue
            if words[0] == "define" and len(words) >= 3:
                self.defines[words[1]] = " ".join(words[2:]).strip('"')
            elif words[0] == "include":
                target = self.find(words[1], here, "include")
                if target is None:
                    self.missing.append((scc, f"include {words[1]}"))
                else:
                    self.walk(target, nocfg or "nocfg" in words[2:])
            elif words[0] in ("kconf", "kconfig") or words[:2] in (["force", "kconf"], ["force", "kconfig"]):
                kind, name = words[-2], words[-1]
                target = self.find(name, here, "kconf")
                if target is None:
                    self.missing.append((scc, f"kconf {name}"))
                elif words[0] == "force" or not nocfg:
                    self.files.append((target, kind))
                    for n, ln in enumerate(target.read_text(encoding="utf-8").splitlines(), 1):
                        m = ASSIGN.match(ln) or UNSET.match(ln)
                        if m:
                            val = (m.group(2) if m.re is ASSIGN else "n") or "n"
                            self.assignments.append((m.group(1), val, target, n))


def main():
    args = sys.argv[1:]
    opt = lambda k: args[args.index(k) + 1]
    verbose = "-v" in args
    deny = dict(a.split("=", 1) for i, a in enumerate(args) if i and args[i - 1] == "--deny")
    bsp, cache = pathlib.Path(args[-1]), pathlib.Path(opt("--cache"))
    r = Resolver([cache, bsp.parent])
    r.walk(bsp)
    karch = r.defines.get("KARCH", "")
    deps, everywhere = kconfig_model(opt("--linux"), karch)
    ours = lambda path: cache not in path.parents
    final, origin = {}, {}
    for sym, val, path, n in r.assignments:
        final[sym], origin[sym] = val, (path, n)
    errors, notes, upstream, details, seen = [], [], {"S1": 0, "S4": 0, "S5": 0}, [], {}

    def report(code, msg, mine):
        if mine:
            errors.append(f"{code} {msg}")
        else:
            upstream[code] += 1
            details.append(f"{code} {msg}")

    for sym, val, path, n in r.assignments:
        where = f"{path.name}:{n}"
        if sym not in everywhere:
            report("S1", f"{where}: CONFIG_{sym} is not defined by any Kconfig", ours(path))
        elif sym not in deps and ours(path):
            notes.append(f"note {where}: CONFIG_{sym} exists only for other architectures (reported with --strict)")
        prev = seen.get(sym)
        if prev and prev[0] != val and ours(path) and not ours(prev[1]):
            notes.append(f"S2 {where}: CONFIG_{sym}={val} overrides {prev[1].name}'s {prev[0]}")
        seen[sym] = (val, path)
    for sym, val in final.items():
        path, n = origin[sym]
        if deny.get(sym) == val:
            errors.append(f"S3 {path.name}:{n}: final CONFIG_{sym}={val} is denied by policy")
        if val not in ("y", "m"):
            continue
        for expr in deps.get(sym, []):
            if re.search(r"[|=<>()]", expr):
                continue                            # only plain conjunctions are evaluated
            for term in (t.strip() for t in expr.split("&&")):
                neg, name = term.startswith("!"), term.lstrip("!").strip()
                state = final.get(name)
                if (not neg and state == "n") or (neg and state in ("y", "m")):
                    blocker, bn = origin[name]
                    report("S5", f"{path.name}:{n}: CONFIG_{sym}={val} needs '{term}', but {blocker.name}:{bn} "
                                 f"sets CONFIG_{name}={state}", ours(path) or ours(blocker))
    for scc, what in r.missing:
        report("S4", f"{scc.name}: {what} exists nowhere", ours(scc))
    print(f"{bsp.name}: KMACHINE={r.defines.get('KMACHINE')} KTYPE={r.defines.get('KTYPE')} KARCH={karch}")
    print(f"   {len(r.files)} fragments ({sum(1 for f, _ in r.files if ours(f))} ours), "
          f"{len(r.assignments)} assignments, {len(final)} distinct symbols")
    for line in notes + errors:
        print("   ", line)
    print(f"   kernel-cache findings (upstream's to fix): S1 {upstream['S1']}, S4 {upstream['S4']}, S5 {upstream['S5']}")
    for line in details if verbose else []:
        print("      ", line)
    print(f"   {len(errors)} error(s) in our files")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
```

```text
== hardened
acme-imx8m-standard.scc: KMACHINE=acme-imx8m KTYPE=standard KARCH=arm64
   18 fragments (2 ours), 263 assignments, 236 distinct symbols
    S2 acme-hardening.cfg:18: CONFIG_DEBUG_KERNEL=y overrides base.cfg's n
   kernel-cache findings (upstream's to fix): S1 0, S4 0, S5 0
   0 error(s) in our files
exit=0
== fragile
acme-imx8m-fragile-standard.scc: KMACHINE=acme-imx8m KTYPE=standard KARCH=arm64
   41 fragments (3 ours), 463 assignments, 427 distinct symbols
    S2 acme-subtract-fragile.cfg:2: CONFIG_KGDB=n overrides kgdb.cfg's y
    S1 acme-legacy-fragile.cfg:2: CONFIG_CC_STACKPROTECTOR_STRONG is not defined by any Kconfig
    S1 acme-legacy-fragile.cfg:3: CONFIG_DEBUG_RODATA is not defined by any Kconfig
    S1 acme-legacy-fragile.cfg:4: CONFIG_DEBUG_SET_MODULE_RONX is not defined by any Kconfig
    S1 acme-legacy-fragile.cfg:5: CONFIG_DEVKMEM is not defined by any Kconfig
    S1 acme-legacy-fragile.cfg:6: CONFIG_USELIB is not defined by any Kconfig
    S3 base.cfg:923: final CONFIG_PROC_KCORE=y is denied by policy
    S5 kgdb.cfg:17: CONFIG_KGDB_KDB=y needs 'KGDB', but acme-subtract-fragile.cfg:2 sets CONFIG_KGDB=n
    S5 acme-subtract-fragile.cfg:5: CONFIG_STRICT_DEVMEM=y needs 'DEVMEM', but acme-subtract-fragile.cfg:4 sets CONFIG_DEVMEM=n
   kernel-cache findings (upstream's to fix): S1 0, S4 0, S5 4
       S5 standard.cfg:1082: CONFIG_CRYPTO_ARC4=y needs 'CRYPTO_USER_API_ENABLE_OBSOLETE', but crypto-obsolete-disable.cfg:1 sets CONFIG_CRYPTO_USER_API_ENABLE_OBSOLETE=n
       S5 standard.cfg:1081: CONFIG_CRYPTO_TEA=m needs 'CRYPTO_USER_API_ENABLE_OBSOLETE', but crypto-obsolete-disable.cfg:1 sets CONFIG_CRYPTO_USER_API_ENABLE_OBSOLETE=n
       S5 standard.cfg:1083: CONFIG_CRYPTO_KHAZAD=m needs 'CRYPTO_USER_API_ENABLE_OBSOLETE', but crypto-obsolete-disable.cfg:1 sets CONFIG_CRYPTO_USER_API_ENABLE_OBSOLETE=n
       S5 standard.cfg:1084: CONFIG_CRYPTO_ANUBIS=m needs 'CRYPTO_USER_API_ENABLE_OBSOLETE', but crypto-obsolete-disable.cfg:1 sets CONFIG_CRYPTO_USER_API_ENABLE_OBSOLETE=n
   8 error(s) in our files
exit=1
```

How to read the output:
- **Hardened.** 18 fragments, no errors, and the one intended override is listed. The kernel cache contributes **zero** findings, because we never pulled in `ktypes/standard`.
- **Fragile.** All five stale symbols are caught. So are a `PROC_KCORE=y` that nothing turned off, and **two stranded values**:
  - `kgdb.cfg`'s `KGDB_KDB` is stranded by our `KGDB=n`; it counts as ours because we caused it.
  - `STRICT_DEVMEM` is stranded by our own `DEVMEM=n`.
- **The four upstream S5s** are the `ktypes/standard` inconsistency of §1.4, which a level-2 audit with `WERROR` would turn fatal for anyone building on `standard`.

The model is honest about its limits: `select`, choices and dependencies inherited through `source` are not evaluated, so `do_kernel_configcheck` with the levels above stays in the pipeline. The static audit makes its failures rare and cheap.

### 2.4 Kernel configuration workflow (devtool and cml1)

```bash
# Explore interactively, then turn the change into a fragment (cml1.bbclass: nostamp tasks)
bitbake -c menuconfig virtual/kernel
bitbake -c diffconfig virtual/kernel          # "Config fragment has been dumped into: ${WORKDIR}/fragment.cfg"
cp tmp/work/.../linux-yocto/*/fragment.cfg meta-acme-bsp/recipes-kernel/linux/files/acme-<topic>.cfg
# then add 'kconf non-hardware acme-<topic>.cfg' to the .scc, re-run scc_audit.py, and rebuild:
bitbake -c kernel_configcheck -f virtual/kernel

# Source changes: a workspace that survives cleans, then patches into the layer
devtool modify linux-yocto                    # source in workspace/sources/linux-yocto, workspace bbappend
devtool build linux-yocto
devtool finish linux-yocto meta-acme-bsp      # --mode patch|srcrev|auto (default auto): patches + bbappend into the layer
devtool reset linux-yocto                     # drop the workspace bbappend if abandoning
```

**The rule behind the commands:** no configuration change exists until it is a fragment in the layer, referenced by the BSP description, audited, and reviewed. `menuconfig` output that lives only in `${B}/.config` is lost on the next `do_kernel_configme`.

### 2.5 The FIT signature, checked against the bootloader that will verify it

#### The Fragile Way

Trust the build: signing is enabled in the distro, and `mkimage` returned 0. With a key URI that points at the wrong HSM slot, or a U-Boot built against a different public key, the build is green. The first evidence is a fleet of devices printing `Bad Data Hash` or `Failed to verify required signature` and falling back, or not.

#### The Silicon-Hardened Production Way

```bitbake
# linux-yocto-fitimage.bbappend - refuse to deploy a kernel FIT that this machine's U-Boot would reject
# oe/fitimage.py skips its key-file sanity check for PKCS#11 key URIs, and the U-Boot recipe verifies only a
# dummy FIT. This task checks the real fitImage against the public key embedded in the deployed U-Boot DTB,
# so a key or algorithm mismatch fails the build instead of every device's first boot.
# uboot-fit_check_sign comes from u-boot-tools-native, already in this recipe's DEPENDS.
do_verify_fit_signature() {
    uboot-fit_check_sign -f ${B}/fitImage -k ${DEPLOY_DIR_IMAGE}/u-boot-${MACHINE}.dtb
}
do_verify_fit_signature[depends] += "virtual/bootloader:do_deploy"
addtask verify_fit_signature after do_compile before do_deploy

python () {
    # Unsigned development builds have nothing to verify; the release distro sets UBOOT_SIGN_ENABLE = "1".
    if d.getVar('FIT_KERNEL_SIGN_ENABLE') != '1':
        d.setVarFlag('do_verify_fit_signature', 'noexec', '1')
}
```

The task runs between `do_compile` (which signs) and `do_deploy`, using the U-Boot DTB the bootloader recipe actually deployed, with the embedded key. `uboot-fit_check_sign` is installed by `u-boot-tools.inc` (`${bindir}/uboot-fit_check_sign`).
- **A wrong key or algorithm** fails the build.
- **A disabled signing policy** skips the task explicitly (`noexec` set to `'1'` from anonymous Python). BitBake 2.20 warns that any other `noexec` value "will result in the flag not being set" in a future version.

### 2.6 The A/B storage layout

#### The Fragile Way

```text
# acme-ab-fragile.wks.in - the prototype's layout, carried into production
bootloader --ptable gpt
part --source rawcopy --sourceparams="file=${IMXBOOT_NAME}" --ondisk mmcblk --no-table --align 1
part / --source rootfs --ondisk mmcblk --fstype=ext4 --label root_a --part-name rootfs_a --align 4096 --size 512M
part --source rootfs --ondisk mmcblk --fstype=ext4 --label root_b --part-name rootfs_b --align 1024 --size 768M --no-fstab-update
part /data --ondisk mmcblk --fstype=ext4 --label data --size 256M --align 4096 --partlabel data
```

#### The Silicon-Hardened Production Way

```text
# acme-ab.wks.in - eMMC user area: boot container at the BootROM offset, A/B FIT and rootfs slots, persistent data
# GPT header and entries occupy LBA 0-33 (17 KiB). The i.MX8M Mini BootROM reads the boot container from
# 33 KiB into the eMMC user area, so it lives in the gap before the first 4 MiB-aligned partition.
bootloader --ptable gpt
part --source rawcopy --sourceparams="file=${ACME_BOOT_CONTAINER}" --ondisk mmcblk --no-table --align 33
# Slots are found by GPT name (U-Boot "part number", /dev/disk/by-partlabel), never by mmcblkN numbering.
part --source rawcopy --sourceparams="file=fitImage" --ondisk mmcblk --part-name boot_a --fixed-size 64M --align 4096
part --source rawcopy --sourceparams="file=fitImage" --ondisk mmcblk --part-name boot_b --fixed-size 64M --align 4096
# Fixed sizes with headroom for future releases. --no-fstab-update keeps each slot byte-identical to the
# update artifact; /data is mounted by a unit shipped in the image, not by a line wic writes.
part / --source rootfs --ondisk mmcblk --fstype=squashfs --part-name rootfs_a --fixed-size 1536M --align 4096 --no-fstab-update
part --source rootfs --ondisk mmcblk --fstype=squashfs --part-name rootfs_b --fixed-size 1536M --align 4096 --no-fstab-update
part --ondisk mmcblk --fstype=ext4 --label data --part-name data --fixed-size 2048M --align 4096
```

The gate reads wic's option table out of `ksparser.py` as text, and places partitions with the sector arithmetic of `PartitionedImage.layout_partitions()`. Each finding maps to a field failure:

```python
# wks_check.py - static gate for a wic kickstart (.wks / .wks.in): wic's own option table plus A/B layout policy
"""Usage: python wks_check.py <wic>/ksparser.py <layout.wks[.in]> [--disk SIZE] [--boot-offset SIZE] [VAR=VALUE ...]

wic accepts many layouts that boot once and fail later. This gate reads the option table from wic's
ksparser.py as text (it never imports or runs it), expands ${VARS} the way image_types_wic.bbclass does,
and fails on:
  K1 a ${VAR} with no value: do_write_wks_template silently deletes the reference
  K2 an option wic does not define for that command
  K3 a value outside the option's declared choices (--fstype, --ptable, --type)
  K4 a malformed size (wic sizetype: <int>[K|M|G], --offset also s/S sectors), or --size with --fixed-size
  K5 the raw boot container (first --no-table rawcopy) not where the BootROM reads it (--boot-offset): wic
     places it after its own partition-table overhead (GPT: 34 sectors = 17 KiB) rounded up to --align,
     wherever that falls, and the board then never starts
  K6 A/B slots (part-name *_a / *_b) that differ in source, fstype or size, or that use --size (sized to
     today's content: next year's update will not fit) instead of --fixed-size
  K7 a table partition not aligned to the erase/allocation unit (default 4096 KiB)
  K8 a rootfs slot without --no-fstab-update: wic rewrites /etc/fstab inside it, so the factory slot no
     longer matches the update artifact (or its dm-verity root hash)
  K9 fstab lines wic would write as /dev/<disk>p<N> for a disk name with no index ("/dev/mmcblkp4")
  K10 no persistent partition outside the slots, duplicate part-names, or a layout larger than --disk
"""
import re
import shlex
import sys

SECTOR = 512
OVERHEAD = {"msdos": 1, "gpt": 34, "gpt-hybrid": 34}   # sectors wic reserves before its first partition
BACKUP_GPT_KIB = 17                                    # backup entries + header at the end of the disk
ERASE_KIB = 4096
VAR_REF = re.compile(r"\$\{([^{}@\n\t :]+)\}")     # the regex image_types_wic.bbclass uses


def option_table(ksparser_text):
    """{command: {option: {"choices": [...] | None, "size": (suffix, in_bytes) | None, "flag": bool}}}"""
    var_cmd = dict(re.findall(r"(\w+) = subparsers\.add_parser\('(\w+)'\)", ksparser_text))
    for group, parent in re.findall(r"(\w+) = (\w+)\.add_mutually_exclusive_group\(\)", ksparser_text):
        var_cmd[group] = var_cmd[parent]
    table = {cmd: {} for cmd in var_cmd.values()}
    for var, args in re.findall(r"(\w+)\.add_argument\((.*?)\)\s*\n", ksparser_text, re.S):
        if var not in var_cmd:
            continue
        choices = re.search(r"choices\s*=\s*\(([^)]*)\)", args)
        size = re.search(r'sizetype\("(\w)"(, True)?\)', args)
        for opt in re.findall(r"""['"](--[a-z][a-z-]*)['"]""", args):
            table[var_cmd[var]][opt] = {
                "choices": re.findall(r"'([^']+)'", choices.group(1)) if choices else None,
                "size": (size.group(1), bool(size.group(2))) if size else None,
                "flag": "store_true" in args}
    return table


def kib(value, default_suffix, in_bytes):
    """wic's sizetype(), normalized to KiB. None where wic would reject the value."""
    suffix, num = (default_suffix, value) if value.isdigit() else (value[-1:], value[:-1])
    if not num.isdigit():
        return None
    n = int(num)
    if in_bytes and suffix in "sS":
        return n * 512 / 1024
    return {"K": n, "k": n, "M": n * 1024, "G": n * 1024 * 1024}.get(suffix)


def parse(table, wks_text, variables):
    errors, parts, ptable = [], [], "msdos"
    for lineno, raw in enumerate(wks_text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        for ref in VAR_REF.findall(line):
            if ref not in variables:
                errors.append(f"K1 line {lineno}: ${{{ref}}} is undefined: wic would see an empty string")
        words = shlex.split(VAR_REF.sub(lambda m: variables.get(m.group(1), ""), line))
        cmd, rest = words[0], words[1:]
        if cmd not in table:
            errors.append(f"K2 line {lineno}: unknown command '{cmd}'")
            continue
        opts, positional, i = {}, [], 0
        while i < len(rest):
            word = rest[i]
            i += 1
            if not word.startswith("--"):
                positional.append(word)
                continue
            name, eq, val = word.partition("=")
            spec = table[cmd].get(name)
            if spec is None:
                errors.append(f"K2 line {lineno}: '{name}' is not a wic '{cmd}' option")
                spec = {"choices": None, "size": None, "flag": False}
            if spec["flag"]:
                opts[name] = True
                continue
            if not eq and i < len(rest):
                val, i = rest[i], i + 1
            opts[name] = val
            if spec["choices"] and val not in spec["choices"]:
                errors.append(f"K3 line {lineno}: {name}={val} not in {spec['choices']}")
            if spec["size"] and kib(val, *spec["size"]) is None:
                errors.append(f"K4 line {lineno}: {name} {val!r} is not a wic size")
        if cmd == "bootloader":
            ptable = opts.get("--ptable", "msdos")
        if cmd == "part":
            if "--size" in opts and "--fixed-size" in opts:
                errors.append(f"K4 line {lineno}: --size and --fixed-size are mutually exclusive")
            parts.append({"line": lineno, "mount": positional[0] if positional else "", "opts": opts})
    return errors, parts, ptable


def layout(parts, ptable, disk_kib, boot_offset_kib):
    """Places partitions exactly as wic's PartitionedImage.layout_partitions() does, in sectors."""
    errors, rows, names, cursor, number, boot_seen = [], [], {}, OVERHEAD[ptable], 0, False
    edits_fstab = any(p["opts"].get("--source") == "rootfs" and not p["opts"].get("--no-fstab-update")
                      for p in parts)
    for p in parts:
        o, ln = p["opts"], p["line"]
        align = int(o.get("--align") or 0)
        if align:
            cursor = -(-cursor // (align * 1024 // SECTOR)) * (align * 1024 // SECTOR)
        if "--offset" in o:
            wanted = int(kib(o["--offset"], "K", True) * 1024 // SECTOR)
            if wanted < cursor:
                errors.append(f"K4 line {ln}: --offset {o['--offset']} is behind the next free sector {cursor}")
            cursor = max(cursor, wanted)
        start = cursor
        size_opt = o.get("--fixed-size") or o.get("--size")
        size = kib(size_opt, "M", False) if size_opt else None
        payload = re.search(r"file=([^,]+)", o.get("--sourceparams", ""))
        name = o.get("--part-name") or o.get("--label") or p["mount"] or (payload.group(1) if payload else f"line{ln}")
        if o.get("--no-table"):
            if o.get("--source") == "rawcopy" and not boot_seen and boot_offset_kib is not None:
                boot_seen = True
                if start * SECTOR // 1024 != boot_offset_kib:
                    errors.append(f"K5 line {ln}: boot container lands at {start * SECTOR // 1024} KiB; "
                                  f"the BootROM reads it at {boot_offset_kib:g} KiB")
        else:
            number += 1
            if align % ERASE_KIB:
                errors.append(f"K7 line {ln}: --align {align} KiB is not a multiple of {ERASE_KIB} KiB")
            disk = o.get("--ondisk", "sda")
            if edits_fstab and p["mount"].startswith("/") and p["mount"] != "/" \
                    and not (o.get("--use-uuid") or o.get("--use-label")) \
                    and disk.startswith(("mmcblk", "nvme")) and not disk[-1].isdigit():
                errors.append(f"K9 line {ln}: wic would write '/dev/{disk}p{number} {p['mount']}' to fstab: "
                              "no such device")
        if o.get("--part-name"):
            if o["--part-name"] in names:
                errors.append(f"K10 line {ln}: duplicate part-name {o['--part-name']}")
            names[o["--part-name"]] = p
        if o.get("--source") == "rootfs" and not o.get("--no-fstab-update"):
            errors.append(f"K8 line {ln}: rootfs partition '{name}' lacks --no-fstab-update: wic edits its /etc/fstab")
        kind = "raw" if o.get("--source") == "rawcopy" else o.get("--fstype", "vfat")
        rows.append((name, start * SECTOR // 1024, size, kind, o.get("--source", "-")))
        cursor = start + int((size or 0) * 1024 // SECTOR)
    for n, p in names.items():
        if not n.endswith("_a"):
            continue
        q = names.get(n[:-2] + "_b")
        if q is None:
            errors.append(f"K6 line {p['line']}: slot {n} has no {n[:-2]}_b")
            continue
        for k in ("--source", "--sourceparams", "--fstype", "--fixed-size", "--size"):
            if p["opts"].get(k) != q["opts"].get(k):
                errors.append(f"K6 line {q['line']}: {n[:-2]}_a/_b differ in {k}: "
                              f"{p['opts'].get(k)!r} vs {q['opts'].get(k)!r}")
        for s in (p, q):
            if "--fixed-size" not in s["opts"]:
                errors.append(f"K6 line {s['line']}: slot sized with {'--size' if '--size' in s['opts'] else 'nothing'}"
                              ", not --fixed-size: capacity follows today's content")
    if not any(not n.endswith(("_a", "_b")) for n in names):
        errors.append("K10: no persistent partition (a part-name outside the A/B slots)")
    end = max((start + (size or 0) for _, start, size, _, _ in rows), default=0)
    if disk_kib and end + BACKUP_GPT_KIB > disk_kib:
        errors.append(f"K10: layout ends at {end / 1024:.0f} MiB + backup GPT: larger than the "
                      f"{disk_kib / 1024:.0f} MiB disk")
    print(f"   {'partition':<12} {'start KiB':>10} {'size MiB':>9}  {'type':<9} source")
    for name, start, size, kind, source in rows:
        print(f"   {name:<12} {start:>10} {(size or 0) / 1024:>9g}  {kind:<9} {source}")
    print(f"   layout end: {end / 1024:.0f} MiB" + (f" of {disk_kib / 1024:.0f} MiB" if disk_kib else ""))
    return errors


def main():
    args = sys.argv[1:]
    ksparser, wks, rest = args[0], args[1], args[2:]
    sizes = {}
    for flag in ("--disk", "--boot-offset"):
        if flag in rest:
            j = rest.index(flag)
            sizes[flag] = kib(rest[j + 1], "M" if flag == "--disk" else "K", False)
            rest = rest[:j] + rest[j + 2:]
    variables = dict(a.split("=", 1) for a in rest)
    print(wks.replace("\\", "/").rsplit("/", 1)[-1] + ":")
    table = option_table(open(ksparser, encoding="utf-8").read())
    errors, parts, ptable = parse(table, open(wks, encoding="utf-8").read(), variables)
    errors += layout(parts, ptable, sizes.get("--disk"), sizes.get("--boot-offset"))
    for e in errors:
        print("   ", e)
    print(f"   {len(errors)} finding(s); wic options known: " +
          ", ".join(f"{c} {len(o)}" for c, o in sorted(table.items())))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
```

```text
== hardened
acme-ab.wks.in:
   partition     start KiB  size MiB  type      source
   imx-boot             33         0  raw       rawcopy
   boot_a             4096        64  raw       rawcopy
   boot_b            69632        64  raw       rawcopy
   rootfs_a         135168      1536  squashfs  rootfs
   rootfs_b        1708032      1536  squashfs  rootfs
   data            3280896      2048  ext4      -
   layout end: 5252 MiB of 7456 MiB
   0 finding(s); wic options known: bootloader 6, include 0, part 34
exit=0
== fragile
acme-ab-fragile.wks.in:
   partition     start KiB  size MiB  type      source
   line3                17         0  raw       rawcopy
   rootfs_a           4096       512  ext4      rootfs
   rootfs_b         528384       768  ext4      rootfs
   data            1314816       256  ext4      -
   layout end: 1540 MiB of 7456 MiB
    K1 line 3: ${IMXBOOT_NAME} is undefined: wic would see an empty string
    K2 line 6: '--partlabel' is not a wic 'part' option
    K5 line 3: boot container lands at 17 KiB; the BootROM reads it at 33 KiB
    K8 line 4: rootfs partition 'rootfs_a' lacks --no-fstab-update: wic edits its /etc/fstab
    K7 line 5: --align 1024 KiB is not a multiple of 4096 KiB
    K9 line 6: wic would write '/dev/mmcblkp3 /data' to fstab: no such device
    K6 line 5: rootfs_a/_b differ in --size: '512M' vs '768M'
    K6 line 4: slot sized with --size, not --fixed-size: capacity follows today's content
    K6 line 5: slot sized with --size, not --fixed-size: capacity follows today's content
    K10: no persistent partition (a part-name outside the A/B slots)
   10 finding(s); wic options known: bootloader 6, include 0, part 34
exit=1
```

What the fragile findings mean in the field:
- **K1:** the boot container's file name expanded to nothing.
- **K5:** the boot container is at 17 KiB, so the board never starts.
- **K8:** the factory root filesystem differs from the update artifact.
- **K9:** `/data` fails to mount at every boot: `/dev/mmcblkp3` doesn't exist.
- **K6:** slots of different, content-sized capacity, so next year's image won't fit slot A.
- **K7:** a misaligned partition costs write amplification on eMMC.
- **K10:** no persistent partition, so every update erases device state.

### 2.7 The layer lint

```python
# bb_lint.py - CI lint for BSP/distro metadata: the mistakes BitBake itself accepts silently
"""Usage: python bb_lint.py --index <oe-core> <bitbake> [--prefix ACME_] <role>:<file> ...
roles: layer | machine | distro | bbappend | recipe | release (a configuration fragment for release builds)

R1 pre-Honister override syntax: _append/_prepend/_remove is a FATAL parse error in bitbake >= 1.52
   (data_smart.setVar); _${PN}-style names (RDEPENDS_${PN}) still parse, as a different, unused variable
R2 list-variable :append whose value lacks a leading space: fuses with the previous word
R3 FILESEXTRAPATHS not ':prepend :=' or missing the trailing ':' separator
R4 LAYERSERIES_COMPAT claiming series this layer is not tested on (here: only wrynose, blacksail)
R5 a variable name defined nowhere in oe-core or bitbake (typo or renamed): silently has no effect
R6 signing keys inside layers/build dirs, or generated at build time (FIT_GENERATE_KEYS = "1")
R7 layering violations: machine.conf setting image or distro policy
R8 layer.conf BBFILES pattern that cannot match *.bbappend
R9 BBFILE_PRIORITY above 20: a BSP that outranks distro and product layers
R10 kernel recipes copying a whole defconfig over .config in do_configure (bypasses fragments)
R11 unconditional SRC_URI changes in a bbappend (applies to every machine using the recipe)
R12 a renamed or removed variable (BB_RENAMED_VARIABLES, bitbake_renamed_vars): an error at parse time
R13 inherit / INHERIT of a class that exists nowhere (e.g. cve-check, removed in favour of sbom-cve-check)
release role only - what makes a release build silently non-compliant or non-reproducible:
R14 INCOMPATIBLE_LICENSE naming part of a GPLv3-family license (GPL-3.0-only without -or-later)
R15 SBOM settings that embed build time or build-host identity (SPDX_INCLUDE_TIMESTAMPS, SPDX_BUILD_HOST...)
R16 CVE scanning inside the release build: it pulls CVE feeds at AUTOREV, so the release changes daily
"""
import pathlib
import re
import sys

LIST_VARS = {"SRC_URI", "IMAGE_INSTALL", "DEPENDS", "RDEPENDS", "RRECOMMENDS", "KERNEL_FEATURES",
             "DISTRO_FEATURES", "MACHINE_FEATURES", "KERNEL_DEVICETREE", "IMAGE_FSTYPES",
             "PACKAGECONFIG", "EXTRA_IMAGE_FEATURES", "IMAGE_FEATURES", "KERNEL_CLASSES"}
SUFFIXED = ("BBFILE_PATTERN_", "BBFILE_PRIORITY_", "LAYERSERIES_COMPAT_", "LAYERDEPENDS_",
            "LAYERVERSION_", "LAYERRECOMMENDS_", "PREFERRED_PROVIDER_", "PREFERRED_VERSION_",
            # SPDX 3.0 agent variables: <BASE>_name/_type/_ref/_id_<ID> (create-spdx-3.0.bbclass)
            "SPDX_AUTHORS_", "SPDX_PACKAGE_SUPPLIER_", "SPDX_IMAGE_SUPPLIER_", "SPDX_SDK_SUPPLIER_", "SPDX_IMPORTS_")
SUPPORTED_SERIES = {"wrynose", "blacksail"}
MACHINE_FORBIDDEN = {"IMAGE_INSTALL", "DISTRO_FEATURES", "UBOOT_SIGN_ENABLE", "UBOOT_SIGN_KEYDIR",
                     "FIT_GENERATE_KEYS", "INCOMPATIBLE_LICENSE"}
ASSIGN = re.compile(r'^\s*(?:export\s+)?(?P<lhs>[A-Za-z0-9_${}/.\-+~:%]+?)(?:\[[\w\-]+\])?\s*'
                    r'(?P<op>\?\?=|\?=|:=|\+=|=\+|\.=|=\.|=)\s*"(?P<val>(?:[^"\\]|\\.)*)', re.M | re.S)
FUNC = re.compile(r'^\s*(?:python\s+)?(?P<name>[A-Za-z0-9_${}:\-]+)\s*\(\)\s*\{(?P<body>.*?)^\}', re.M | re.S)


def build_index(roots):
    """(known variable names, renamed/removed variable -> message, class names)."""
    names, renamed, classes = set(), {}, set()
    pat = re.compile(r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\b', re.M)
    uses = re.compile(r'''getVar(?:Flag)?\(\s*["']([A-Z][A-Z0-9_]*)''')
    doc = re.compile(r':term:`([A-Z][A-Z0-9_]*)`')
    for root in roots:
        for f in pathlib.Path(root).rglob("*"):
            if f.suffix in (".conf", ".bbclass", ".bb", ".inc", ".py", ".rst") and f.is_file():
                text = f.read_text(encoding="utf-8", errors="replace")
                names.update(pat.findall(text))
                names.update(uses.findall(text))
                names.update(doc.findall(text))
                renamed.update(re.findall(r'^BB_RENAMED_VARIABLES\[([\w.+\-]+)\]\s*=\s*"([^"]*)"', text, re.M))
                block = re.search(r"^bitbake_renamed_vars = \{(.*?)^\}", text, re.M | re.S)
                if block:
                    renamed.update(re.findall(r'"([A-Z0-9_]+)":\s*"([^"]*)"', block.group(1)))
                if f.suffix == ".bbclass":
                    classes.add(f.stem)
    return names, renamed, classes


def base_name(lhs):
    return lhs.split(":")[0]


def lint(role, path, tables, prefixes):
    index, renamed, classes = tables
    text = path.read_text(encoding="utf-8")
    body = re.sub(r"\\\n", " ", text)
    out = []
    inherits = [(text[:m.start()].count("\n") + 1, c) for m in re.finditer(r"^\s*inherit(?:_defer)?\s+([^\n#]+)", text, re.M)
                for c in m.group(1).split()]
    for m in ASSIGN.finditer(body):
        lhs, op, val = m.group("lhs"), m.group("op"), m.group("val")
        base = base_name(lhs)
        line = text[:m.start()].count("\n") + 1
        if re.search(r"_(append|prepend|remove)\b", lhs):
            out.append((line, "R1", f"'{lhs}': old '_' override syntax: fatal parse error in bitbake >= 1.52 "
                                    "(convert with scripts/contrib/convert-overrides.py)"))
        elif re.search(r"_\$\{PN\}", lhs):
            out.append((line, "R1", f"'{lhs}': old '_${{PN}}' form: parses as a different, unused variable"))
        if ":append" in lhs and base in LIST_VARS and val and not val[0].isspace():
            out.append((line, "R2", f"'{lhs} = \"{val[:20]}...\"': no leading space, fuses with the previous item"))
        if base == "FILESEXTRAPATHS" and (":prepend" not in lhs or op != ":=" or not val.rstrip().endswith(":")):
            out.append((line, "R3", "FILESEXTRAPATHS must be ':prepend :=' with a trailing ':'"))
        if base.startswith("LAYERSERIES_COMPAT_"):
            extra = set(val.split()) - SUPPORTED_SERIES
            if extra:
                out.append((line, "R4", f"claims untested series {sorted(extra)}"))
        if base in renamed:
            out.append((line, "R12", f"'{base}' {'has been renamed to ' if ' ' not in renamed[base] else ''}"
                                     f"{renamed[base]}: BitBake reports an error at parse time"))
        known = base in index or base.startswith(SUFFIXED) or base.startswith(tuple(prefixes)) or "${" in base \
            or base[:1].islower() or re.search(r"_(append|prepend|remove)\b", lhs) or base in renamed
        if not known:
            out.append((line, "R5", f"'{base}' is defined nowhere in oe-core/bitbake: no effect"))
        if base in ("INHERIT", "IMAGE_CLASSES", "KERNEL_CLASSES"):
            inherits += [(line, c) for c in val.split()]
        if role == "release" and base == "INCOMPATIBLE_LICENSE":
            toks = set(val.split())
            for fam in ("GPL-3.0", "LGPL-3.0", "AGPL-3.0"):
                if any(t.startswith(fam) for t in toks) and f"{fam}*" not in toks \
                        and not {f"{fam}-only", f"{fam}-or-later"} <= toks:
                    out.append((line, "R14", f"INCOMPATIBLE_LICENSE covers only part of {fam}: use '{fam}*'"))
        if role == "release" and ((base == "SPDX_INCLUDE_TIMESTAMPS" and val.strip() == "1")
                                  or base in ("SPDX_BUILD_HOST", "SPDX_INVOKED_BY", "SPDX_ON_BEHALF_OF")):
            out.append((line, "R15", f"{base}: the SBOM records build time or build host and differs every build"))
        if role == "release" and base in ("INHERIT", "IMAGE_CLASSES", "OE_FRAGMENTS") and "sbom-cve-check" in val:
            out.append((line, "R16", "CVE scan inside the release build: CVE feeds at AUTOREV make it time-dependent"))
        if base == "UBOOT_SIGN_KEYDIR" and re.search(r"\$\{(LAYERDIR|THISDIR|TOPDIR|COREBASE)\}|^\.", val):
            out.append((line, "R6", f"signing keys inside the source/build tree: {val}"))
        if base == "FIT_GENERATE_KEYS" and val.strip() == "1":
            out.append((line, "R6", "FIT_GENERATE_KEYS = \"1\": a new key per build directory, written to disk"))
        if role == "machine" and base in MACHINE_FORBIDDEN:
            out.append((line, "R7", f"machine.conf sets {base}: image/distro policy does not belong here"))
        if role == "layer" and base == "BBFILES" and ".bbappend" not in val:
            out.append((line, "R8", "BBFILES never matches *.bbappend: every append in this layer is ignored"))
        if base.startswith("BBFILE_PRIORITY_") and val.strip().isdigit() and int(val) > 20:
            out.append((line, "R9", f"priority {val}: outranks distro and product layers"))
        if role == "bbappend" and base == "SRC_URI" and lhs == "SRC_URI" and op in ("+=", "=", ".="):
            out.append((line, "R11", "unconditional SRC_URI change: applies to every machine using this recipe"))
    for m in FUNC.finditer(text):
        name, fbody = m.group("name"), m.group("body")
        line = text[:m.start()].count("\n") + 1
        if re.search(r"_(append|prepend)$", name):
            out.append((line, "R1", f"function '{name}': old '_' override syntax: fatal parse error"))
        if "configure" in name and re.search(r"cp\s+\S*defconfig\S*\s+\S*\.config", fbody):
            out.append((line, "R10", "copies a full defconfig over .config: fragments and kernel-cache are bypassed"))
    for line, cls in inherits:
        if "$" not in cls and cls not in classes:
            out.append((line, "R13", f"class '{cls}' exists nowhere: 'Could not inherit file classes/{cls}.bbclass'"))
    return sorted(out)


def main():
    args = sys.argv[1:]
    i = args.index("--index")
    tables = build_index(args[i + 1:i + 3])
    index = tables[0]
    rest = args[:i] + args[i + 3:]
    prefixes = []
    if "--prefix" in rest:
        j = rest.index("--prefix")
        prefixes = [rest[j + 1]]
        rest = rest[:j] + rest[j + 2:]
    total = 0
    for spec in rest:
        role, f = spec.split(":", 1)
        findings = lint(role, pathlib.Path(f), tables, prefixes)
        total += len(findings)
        print(f"{pathlib.Path(f).name} [{role}]: {len(findings)} finding(s)")
        for line, rule, msg in findings:
            print(f"   {rule:>3} line {line}: {msg}")
    print(f"index: {len(index)} known variable names")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

```text
== hardened
layer.conf [layer]: 0 finding(s)
acme-imx8m.conf [machine]: 0 finding(s)
linux-yocto_%.bbappend [bbappend]: 0 finding(s)
linux-yocto-fitimage.bbappend [bbappend]: 0 finding(s)
acme.conf [distro]: 0 finding(s)
index: 3679 known variable names
exit=0
== fragile
layer-fragile.conf [layer]: 3 finding(s)
    R8 line 3: BBFILES never matches *.bbappend: every append in this layer is ignored
    R9 line 6: priority 99: outranks distro and product layers
    R4 line 7: claims untested series ['kirkstone', 'scarthgap']
acme-imx8m-fragile.conf [machine]: 9 finding(s)
    R1 line 4: 'KERNEL_DEVICETREE_append': old '_' override syntax: fatal parse error in bitbake >= 1.52 (convert with scripts/contrib/convert-overrides.py)
    R2 line 6: 'IMAGE_INSTALL:append = "openssh htop..."': no leading space, fuses with the previous item
    R7 line 6: machine.conf sets IMAGE_INSTALL: image/distro policy does not belong here
    R7 line 7: machine.conf sets DISTRO_FEATURES: image/distro policy does not belong here
    R7 line 8: machine.conf sets UBOOT_SIGN_ENABLE: image/distro policy does not belong here
    R6 line 9: signing keys inside the source/build tree: ${LAYERDIR}/keys
    R7 line 9: machine.conf sets UBOOT_SIGN_KEYDIR: image/distro policy does not belong here
    R6 line 10: FIT_GENERATE_KEYS = "1": a new key per build directory, written to disk
    R7 line 10: machine.conf sets FIT_GENERATE_KEYS: image/distro policy does not belong here
linux-yocto-fragile.bbappend [bbappend]: 4 finding(s)
    R1 line 2: 'FILESEXTRAPATHS_prepend': old '_' override syntax: fatal parse error in bitbake >= 1.52 (convert with scripts/contrib/convert-overrides.py)
   R11 line 3: unconditional SRC_URI change: applies to every machine using this recipe
    R1 line 4: 'RDEPENDS_${PN}': old '_${PN}' form: parses as a different, unused variable
   R10 line 5: copies a full defconfig over .config: fragments and kernel-cache are bypassed
index: 3679 known variable names
exit=1
```

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Root cause | Detect | Fix |
|---|---|---|---|
| A bbappend "does nothing" | `BBFILES` lacks `*.bbappend`; or `%` prefix matches a different recipe set | `bitbake-layers show-appends`; lint R8 | Layer.conf per §2.1; name appends by prefix you mean |
| Parse fails after a release upgrade | `LAYERSERIES_COMPAT` lacks the new core series; old `_append` syntax | Parser message names the layer | Test, then add the series; `convert-overrides.py` |
| `Could not locate BSP definition for acme-imx8m/standard and no defconfig was provided` | New machine, no BSP description in `SRC_URI` | `do_kernel_metadata` log | Ship `<machine>-standard.scc` (§2.3) |
| A kernel option you set is absent on the device | Dependency off ("did not make it"), symbol renamed or removed | `scc_audit.py`; `do_kernel_configcheck` at `KCONF_AUDIT_LEVEL = "2"` | Fix the dependency or the name; `KMETA_AUDIT_WERROR = "1"` |
| Kernel config differs between two builds of the same commit | `do_configure:append` copying a defconfig; host `.config` leakage | `bitbake -c diffconfig`; compare `${B}/.config` | Fragments only; never post-process `.config` |
| Devices reject the new kernel: `Failed to verify required signature` | FIT signed with a key U-Boot doesn't embed (HSM slot, rotation, wrong token) | §2.5 task; on target: U-Boot `bootm` output on the console | Verify-before-deploy; key rotation via a new U-Boot first |
| `SIGILL` in crypto code on some units | Tune with `+crypto` on a SKU without the extension | `/proc/cpuinfo` `Features` lacks `aes`; core dump in an AES routine | Per-SKU `MACHINE`, or the lower tune |
| Board dead after flashing a new layout | Boot container at the wrong offset (K5) | Serial console silent; BootROM falls back to its USB recovery mode ⚠ | Recover via the SoC's serial-download mode (vendor tool), fix `--align`/`--offset` |
| `/data` not mounted, device in emergency mode | wic wrote `/dev/mmcblkp<N>` into fstab (K9) | `journalctl -b` mount unit failure | `--no-fstab-update` on slots; mount by `PARTLABEL`; units shipped in the image |
| Update fails "image too large" on half the fleet | Slots sized with `--size` from the first release (K6) | Update client log, partition table | `--fixed-size` with documented headroom; layout versioning is a migration, not an update |

**Brick recovery for the BSP owner.** Three tiers, from cheapest to most invasive:
1. **The A/B fallback (Folder 03).** It covers a bad kernel or rootfs.
2. **The BootROM's recovery path.** Every SoC has one, typically a USB or serial download mode entered by boot-mode pins or by an empty or invalid boot medium. It covers a bad boot container or layout. Bring it up on day one of a new board, document the pin strapping, and keep a tested, signed recovery image. On a secure-boot-closed part, the recovery image must itself be signed (Folder 01).
3. **JTAG / CoreSight.** It covers everything else, on lab units with debug left enabled. Production parts usually disable or authenticate debug.

**Post-mortem method for a field configuration problem:**
1. Read the running kernel's configuration. `/proc/config.gz` requires `CONFIG_IKCONFIG_PROC`, deliberately off here, so record the `.config` in the build's deploy artifacts and SBOM instead (02.4).
2. Diff it against the expected configuration.
3. Map each difference through `scc_audit.py` output and `do_kernel_configcheck` logs: which fragment requested it, and which dependency blocked it.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · The vendor BSP layer

**Initial Prompt:** "We received the silicon vendor's BSP layer for our SoC. It has `BBFILE_PRIORITY` 99, sets `IMAGE_INSTALL` and `DISTRO_FEATURES` in the machine file, and generates signing keys at build time. Ship it?"

**L5 Answer:** "It's the vendor's supported layer, so changing it risks losing support. We'll use it as is and override what we need in our own layer."

**Why L5 Bricks Devices at Scale:** You can't override a layer that outranks you.
- **Priority 99** means the vendor's recipes and appends win over the product's.
- **Policy in the machine file** fights the distro's, and the result depends on assignment operators nobody reads.
- **Per-build generated keys** mean every builder signs with a different key. The first device that receives an update signed on a different machine rejects it. In the worse case, the device trusts whatever key the factory build happened to make.

**L7 Principal Defense:**
- **Contain the vendor layer.** Keep it for what it's good at: the SoC's kernel, bootloader and firmware recipes. Don't let it define the product.
- **Fix the contract by bbappend or a thin fork,** and upstream the fixes:
  - priority below the distro;
  - policy moved out of the machine file;
  - key generation disabled;
  - `LAYERSERIES_COMPAT` set to what we test.
- **Write the product's machine configuration** that `require`s the vendor's SoC include but owns board facts.
- **Gate it in CI** with the lint (R4, R6, R7, R8, R9) so the next vendor drop can't silently regress any of it.
- **Keep support:** the vendor supports their recipes, not their example policy.

### Chain 2 · "The option is set, but it isn't in the kernel"

**Initial Prompt:** "Our fragment sets `CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y` and the build is green, but on the device lockdown isn't active. What happened, and how do you make it impossible?"

**L5 Answer:** "Maybe the fragment wasn't applied. Check `SRC_URI`, run `menuconfig` to see the value, and add it again."

**Why L5 Bricks Devices at Scale:** It treats a configuration as a list of wishes:
- **merge_config** keeps a value only if the option's dependencies allow it.
- **A missing dependency** (here, the LSM itself) silently drops the request.
- **The default audit levels** show only boot-relevant mismatches and never fail the build.
- **"Add it again" in menuconfig** produces a `.config` the next `do_kernel_configme` throws away.

The security feature the threat model relies on is absent from every device, and no build log says so.

**L7 Principal Defense:**
- **Every request must survive into `.config`.** Run the static audit before the build (`scc_audit.py` S1/S5 on our fragments).
- **Make the audit strict and fatal in the recipe:** `KCONF_AUDIT_LEVEL = "2"`, `KCONF_BSP_AUDIT_LEVEL = "1"`, `KMETA_AUDIT_WERROR = "1"`.
- **Ship the final `.config` as a build artifact** referenced by the SBOM.
- **Test on target that lockdown is active:** `/sys/kernel/security/lockdown` shows `[integrity]`.
- **Never "fix" with `menuconfig`.** Only a fragment, in the layer, through the BSP description.

### Chain 3 · Hardened kernel: subtractive or additive?

**Initial Prompt:** "Security wants kgdb, kexec, debugfs and `/proc/kcore` gone from the production kernel. A colleague adds a fragment turning them off on top of the standard kernel type. Review it."

**L5 Answer:** "Looks right: the fragment is applied last, so its values win. Merge it."

**Why L5 Bricks Devices at Scale:**
- **Last wins for the option itself, not for what depends on it.** `kgdb.cfg`'s `KGDB_KDB=y` now requests something impossible. Under a strict audit the build fails; under default levels it passes silently, and the team learns to ignore audit output.
- **It doesn't remove everything it claims to.** `PROC_KCORE` comes from `ktypes/base/base.cfg` as `y`, and nothing in the fragment turned it off (fragile audit, S3).
- **It's fragile across releases.** Each new standard-type feature becomes something the product must notice and disable.

**L7 Principal Defense:**
- **Build additively.** Start from `ktypes/base`, add `features/security` and exactly the product's features, then add hardening (§2.3).
- **Prove it statically** (hardened audit: zero errors, zero upstream findings) and dynamically (the strict `do_kernel_configcheck`).
- **Encode the deny list** (`KGDB=y`, `KEXEC=y`, `PROC_KCORE=y`, `DEBUG_FS_ALLOW_ALL=y`, `MODULE_SIG_FORCE=n`) in CI, so a future include can't bring one back.
- **Review the BSP description** for what it pulls in, not only the fragments for what they set.

### Chain 4 · Signed FIT, green build, rejected kernel

**Initial Prompt:** "After moving FIT signing to an HSM, release builds are green, but devices from the pilot line reject the new kernel. Diagnose the build design."

**L5 Answer:** "The HSM must have signed with the wrong algorithm. Check `FIT_SIGN_ALG` and rebuild."

**Why L5 Bricks Devices at Scale:** It debugs the symptom on devices instead of fixing the pipeline that let it reach devices.
- **oe-core's signing helper skips its key-file sanity check for PKCS#11 URIs**, and `mkimage`'s exit status is not proof of a usable signature.
- **The U-Boot recipe verifies only a dummy FIT.** Nothing in the build compares the kernel FIT's signature with the key compiled into the bootloader.

Any drift then ships: a different HSM slot, a rotated key, a U-Boot built before rotation.

**L7 Principal Defense:**
- **Add the verify-before-deploy task** (§2.5): `uboot-fit_check_sign` on the real `fitImage` against the deployed `u-boot-${MACHINE}.dtb`.
- **Keep FIT configuration signing** (`FIT_SIGN_INDIVIDUAL = "0"`, per oe-core's own mix-and-match warning).
- **Treat key rotation as a two-step fleet operation:**
  1. ship a U-Boot that trusts old and new keys;
  2. only then sign kernels with the new key.
- **Record the key ID used per artifact** in the release manifest, so a rejection maps to a key in seconds.

### Chain 5 · The disk layout is an API

**Initial Prompt:** "Design the eMMC layout for an A/B product that ships for 10 years. What decisions are irreversible?"

**L5 Answer:** "Boot partition, two rootfs partitions sized for the current image, and a data partition with the rest. wic generates it from the `.wks` file."

**Why L5 Bricks Devices at Scale:** The partition table is the one thing an over-the-air update can't safely change.
- **Slots sized to today's image** turn year three's update into "doesn't fit".
- **A boot container at an offset wic chose** bricks the first board.
- **fstab lines written by wic** with an unindexed disk name fail to mount.
- **A factory slot wic modified** fails integrity checks against the artifact the update server publishes.

**L7 Principal Defense:**
- **Treat the layout as a versioned interface** (§2.6):
  - the boot container at the BootROM's documented offset;
  - fixed-size, identical slots with explicit headroom (e.g. 2–3x the first image);
  - slots addressed by GPT part-name;
  - `--no-fstab-update` on slots, with mounts defined inside the image;
  - a persistent partition outside the slots;
  - 4 MiB alignment.
- **Gate it** (`wks_check.py`) against wic's own option table and placement arithmetic.
- **Plan the one-time repartition path** (a migration image with its own recovery story) before you need it.

### Chain 6 · One image for three SKUs

**Initial Prompt:** "Product management wants one image for three SKUs of the same SoC family. One SKU lacks the Cryptography Extension. Your call?"

**L5 Answer:** "Use the crypto tune for performance. The SKU without it is low volume, and OpenSSL detects capabilities at runtime anyway."

**Why L5 Bricks Devices at Scale:**
- **OpenSSL's runtime detection protects OpenSSL, not the rest of the image.** Any component compiled with `-mcpu=cortex-a53+crc+crypto` that uses the instructions (intrinsics, auto-vectorized hashing, a vendor library) takes `SIGILL` on the SKU without the extension.
- **The failure appears in whichever code path runs first** on that SKU in the field. The crash reports look random.

**L7 Principal Defense:**
- **The tune is a contract with every device** (§1.3). Either one image at the common tune (`cortexa53`), measuring the cost on the hot paths, or one `MACHINE` per SKU with separate feeds (`ARMPKGARCH` differs).
- **Choose by measured performance and the update and logistics cost of multiple images.** Per-SKU `MACHINE`s also give per-SKU device trees and kernel fragments for free.
- **Add a boot-time assertion** that the running CPU supports everything the image was built for, to turn a random crash into a clear refusal.

---

## 5. Invariants Checklist

- [ ] `BBFILES` covers `*.bb` and `*.bbappend`; priority below distro and product layers; `LAYERSERIES_COMPAT` equals the tested series.
- [ ] Machine file: hardware only. Distro file: policy only. Image recipes: content only (lint R7).
- [ ] Tune matches the least capable device that will run the image.
- [ ] Kernel: an external BSP description; additive on `ktypes/base`; fragments only; `KCONF_AUDIT_LEVEL = "2"`, `KCONF_BSP_AUDIT_LEVEL = "1"`, `KMETA_AUDIT_WERROR = "1"`; `scc_audit.py` clean with the deny list.
- [ ] No `.config` post-processing; no defconfig copies in `do_configure`.
- [ ] Signing keys only in an HSM (PKCS#11 URI); `FIT_GENERATE_KEYS = "0"`; `FIT_SIGN_INDIVIDUAL = "0"`; verify-before-deploy task present.
- [ ] Layout: boot container at the BootROM offset; fixed-size identical slots; GPT names; `--no-fstab-update`; persistent partition; `wks_check.py` clean.
- [ ] Recovery: BootROM download mode documented and tested with a signed recovery image.

## 6. References

- openembedded-core `yocto-6.1`: `meta/conf/bitbake.conf` (OVERRIDES), `meta/conf/layer.conf`, `meta/classes-recipe/kernel-yocto.bbclass`, `kernel-fit-image.bbclass`, `uboot-sign.bbclass`, `image_types_wic.bbclass`, `meta/lib/oe/fitimage.py`, `meta/conf/machine/include/arm/`. <https://github.com/openembedded/openembedded-core/tree/yocto-6.1>
- BitBake `yocto-6.1`: `lib/bb/cooker.py` (append matching), `lib/bb/cookerdata.py` (series check), `lib/bb/build.py` (`noexec`). <https://github.com/openembedded/bitbake/tree/yocto-6.1>
- yocto-kernel-cache, branch `yocto-7.2`. <https://git.yoctoproject.org/yocto-kernel-cache>
- yocto-kernel-tools (`spp`, `scc`, `symbol_why.py`, `merge_config.sh`). <https://git.yoctoproject.org/yocto-kernel-tools>
- wic (standalone, v0.3.1). <https://git.yoctoproject.org/wic>
- Linux v7.2 Kconfig. <https://github.com/torvalds/linux/tree/v7.2>
- Yocto Project Linux Kernel Development Manual (BSP descriptions, configuration audit). <https://docs.yoctoproject.org/kernel-dev/index.html>
- In this KB: [02.1 BitBake internals](01-bitbake-task-scheduler-ast-parsing-stamps-sstate-cache-and-hash-equiv.md) · [02.3 Toolchains](03-cross-compilation-toolchain-sysroots-glibc-musl-and-sdk-esdk.md) · [01.4 FIT signing, dm-verity](../01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE/04-uboot-verified-boot-fit-images-dm-verity-fscrypt-and-tpm2-measured-boot.md) · Folder 03 (A/B update state machine).
