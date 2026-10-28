# 02.3 · Cross-Compilation Toolchains: Sysroots, glibc vs musl, the C Library ABI, and SDK/eSDK

> **Folder 02 · File 3 of 4.** A cross build produces code for a machine that isn't running the build, so every input has to come from the right place:
> - headers and libraries from the **target** sysroot;
> - tools from the **native** sysroot;
> - flags from the **tune and the distro**;
> - **nothing** from the build host's `/usr`.
>
> When one of those leaks, the result is rarely a build failure. It's a binary that runs on the developer's board and dies on the fleet. Typical failures: a symbol version the device's C library doesn't have, a host header's struct layout, a missing `GNU_HASH`, or an instruction a SKU can't execute.
>
> This file covers:
> - the three-machine model: build, host and target;
> - per-recipe sysroots, and the dependency and packaging model that feeds them;
> - the C library **ABI floor**, proven by building one source against two glibc versions and musl and reading the ELF symbol versions the result demands;
> - the QA checks that catch leaks, with a recipe lint mapped to each;
> - the SDK and the extensible SDK, and what they do and don't guarantee.
>
> **Pinned versions.** oe-core `yocto-6.1` ships **GCC 16.2**, **binutils 2.47**, **glibc 2.44**, **musl 1.2.6+git**, **linux-libc-headers 7.2**, and Clang via `PREFERRED_TOOLCHAIN_TARGET`.
>
> **Verification.**
> - `abi_demo.c` is cross-compiled for AArch64 against **glibc 2.39, glibc 2.31 and musl** using Zig's `cc` driver (Clang 21), which carries those C library stubs. Zig doesn't carry 2.44, so 2.39 stands in for "newer than the device".
> - Each output is inspected by `elfinfo.py`, an ELF64 reader written for this KB: `PT_INTERP`, `DT_NEEDED` and version-needs.
> - `recipe_lint.py` checks the recipes below; its rules cite the oe-core 6.1 `insane.bbclass` check each one corresponds to.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 Three machines, six recipe classes

GNU's naming convention: **build** is where the compiler runs, **host** is where its output runs, and **target** is what that output generates code for (relevant only when building compilers). OE spells these `BUILD_SYS`, `HOST_SYS` and `TARGET_SYS`. oe-core 6.1 sets `TARGET_VENDOR = "-oe"`, so this board's triplet is `aarch64-oe-linux`.

| Recipe class | Runs on | Generates for | Example | Sysroot it populates |
|---|---|---|---|---|
| target (default) | device | — | `zlib` | `recipe-sysroot` of dependents |
| `-native` | build machine | build machine | `zlib-native`, `u-boot-tools-native` | `recipe-sysroot-native` |
| `-cross` | build machine | device | `gcc-cross-aarch64` | `recipe-sysroot-native` |
| `nativesdk-` | SDK machine (`SDKMACHINE ??= "${BUILD_ARCH}"`) | SDK machine | `nativesdk-cmake` | SDK only |
| `-crosssdk` / `-cross-canadian` | SDK machine | device | the SDK's compiler | SDK only |
| image / `packagegroup` | — | — | `core-image-minimal` | rootfs |

**Canadian cross** is the SDK compiler: built on the build machine, to run on the SDK machine, generating device code. Three different machines, which is why a typo in a `-native` or `nativesdk-` dependency produces a tool that runs in one place and not another.

### 1.2 Per-recipe sysroots

```text
 zlib:   do_install → ${D} ──do_populate_sysroot (SYSROOT_DIRS: includedir, libdir, base_libdir, datadir...)──► sstate
 curl:   DEPENDS = "zlib openssl"
         do_prepare_recipe_sysroot:  for each DEPENDS (transitively, build-time only):
             copy/hardlink its sysroot output into  ${WORKDIR}/recipe-sysroot          (RECIPE_SYSROOT)
             and native tools into                  ${WORKDIR}/recipe-sysroot-native   (RECIPE_SYSROOT_NATIVE)
         do_configure/do_compile:  ${CC} = aarch64-oe-linux-gcc <tune> --sysroot=${RECIPE_SYSROOT}
             → headers: recipe-sysroot/usr/include    libs: recipe-sysroot/usr/lib    pkg-config: PKG_CONFIG_SYSROOT_DIR
```

- **Each recipe sees only what its own `DEPENDS` declares.** `STAGING_DIR_HOST = STAGING_DIR_TARGET = ${RECIPE_SYSROOT}` in `bitbake.conf`.
- **This is the single biggest reproducibility feature of OE.** A recipe that forgot `DEPENDS = "zlib"` fails *every* time, rather than succeeding when some other recipe happened to stage zlib first.
- **It doesn't protect you from the host.** A recipe that passes `-I/usr/include` or calls `gcc` explicitly bypasses the sysroot entirely. That is what the QA checks and the lint in §2.2 are for.

### 1.3 Build-time vs runtime dependencies, and package splitting

| Mechanism | Resolved by | Effect |
|---|---|---|
| `DEPENDS = "zlib"` | BitBake, at build time | zlib's headers, `.so` symlink and `.pc` staged into my sysroot |
| Automatic shlib dependencies | `package.bbclass` / `oe/package.py` `process_shlibs` | Every `DT_NEEDED` library my binaries link resolves to the package providing it, so `RDEPENDS` is added for me (`PRIVATE_LIBS` opts a bundled library out) |
| `RDEPENDS:${PN} = "x"` | Package manager, at image build | Only for what the linker can't see: config packages, scripts, `dlopen()` plugins, firmware |
| `RRECOMMENDS:${PN}` | Package manager | Installed unless excluded (`BAD_RECOMMENDATIONS`, `NO_RECOMMENDATIONS`) |
| `PACKAGES`, `FILES:<pkg>` | `do_package` | Default `PACKAGES = "${PN}-src ${PN}-dbg ${PN}-staticdev ${PN}-dev ${PN}-doc ${PN}-locale ${PACKAGE_BEFORE_PN} ${PN}"`: first match wins, so `PACKAGES =+ "${PN}-tools"` claims files before `${PN}` does |

**`-dev` is for building, never for running.** `FILES:${PN}-dev` holds headers, the unversioned `.so` symlink and `.la` files. A runtime dependency on a `-dev` package is the `dev-deps` QA error.

### 1.4 The C library ABI floor

```text
 glibc symbol versioning (ELF .gnu.version_r, "version needs"):
   at link time, each undefined symbol binds to the NEWEST version the sysroot's libc.so.6 defines for it
   at run time,  ld.so refuses to start the binary unless the device's libc.so.6 defines every recorded version
       "version `GLIBC_2.34' not found (required by ./app)"
 glibc 2.34 merged libpthread/libdl into libc and gave __libc_start_main a new version, GLIBC_2.34:
   anything linked against ≥ 2.34 needs ≥ 2.34 at runtime, even if it calls nothing new.
```

The ABI floor of a binary is the **highest** `GLIBC_x.y` it records:
- Inside a Yocto build that's never a problem: the image's glibc is the one the binaries were linked against (2.44 in 6.1).
- It becomes a problem at every boundary: vendor blobs, binaries built on a developer's host, an SDK from a newer release than the device, a container built on another distro.

§2.1 proves the mechanism.

| | glibc (`TCLIBC = "glibc"`, default) | musl (`TCLIBC = "musl"`) |
|---|---|---|
| Symbol versioning | Yes: forward-compatible ABI, one floor per binary | No; ABI by `soname` only |
| Static linking | Discouraged (NSS, `dlopen`, `iconv` need runtime modules) | Designed for it: our demo is fully static, no interpreter |
| Size | Larger runtime; small dynamic binaries | Small runtime; static binaries carry it |
| Behavior differences | Reference behavior for most software | DNS resolver, locales, `dlclose` no-op, default thread stack much smaller ⚠ (check your release) |
| Fits | General-purpose images, third-party binaries | Single-purpose appliances, containers, initramfs tools |

**uninative** solves the same problem in the other direction, for **native** tools (`uninative.bbclass`, `UNINATIVE_VERSION = "5.2"` in 6.1). Native binaries are linked against a glibc that Yocto ships, not the host's, so sstate built on one host distro runs on another.

### 1.5 The kernel headers are an API, not the kernel

`linux-libc-headers` (7.2 in oe-core 6.1) provides the UAPI headers userspace compiles against: ioctl numbers, struct layouts, syscall numbers. It is **not** the kernel that runs on the device.
- **Older headers than the running kernel:** userspace can't use newer features. Safe.
- **Newer headers than the running kernel:** userspace may call an ioctl or syscall the kernel doesn't have, and gets `ENOTTY`, `ENOSYS` or `EINVAL` at runtime.

The rule: headers ≤ the oldest kernel you will ever boot that userspace on. Vendor kernels that lag mainline make this real: a 6.1 userspace on a vendor 5.15 kernel compiles against 7.2 UAPI.

### 1.6 What the build checks for you (insane.bbclass, oe-core 6.1)

```text
ERROR_QA ?= "already-stripped arch buildpaths build-deps debug-deps dev-deps dev-elf dev-so empty-dirs file-rdeps
             ldflags libdir missing-ptest rpaths staticdev textrel version-going-backwards ${CHECKLAYER_REQUIRED_TESTS}"
WARN_QA  ?= "32bit-time native-last pep517-backend"
FAKEROOT_QA = "host-user-contaminated"
```

| Check | Catches |
|---|---|
| `arch` | ELF machine, class or ABI that doesn't match the target (a host-compiled binary) |
| `ldflags` | Binaries linked without the distro's `LDFLAGS` (no `GNU_HASH`), i.e. the recipe overrode `LDFLAGS` |
| `already-stripped` | Stripped before packaging: no debug symbols for the `-dbg` package, no post-mortem |
| `buildpaths` | `TMPDIR` or build-host paths embedded in output: non-reproducible, leaks the build environment |
| `dev-deps`, `dev-so` | Runtime dependency on `-dev`; `.so` symlink in the runtime package |
| `rpaths` | `RPATH` pointing into the build tree |
| `textrel` | Text relocations: non-PIC code, writable text at load time |
| `host-user-contaminated` | Files owned by the uid/gid running BitBake: `cp -a` from the build tree |

The distro's hardening flags reach every recipe through the same variables (`security_flags.inc`, required by `defaultsetup.conf`):
- `SECURITY_STACK_PROTECTOR ?= "-fstack-protector-strong"`;
- `-D_FORTIFY_SOURCE=2` when optimizing;
- `SECURITY_LDFLAGS ?= "-Wl,-z,relro,-z,now"`;
- PIE by default via GCC's `--enable-default-pie`.

A recipe that replaces `LDFLAGS` drops them silently, except that `ldflags` notices the missing `GNU_HASH`.

### 1.7 SDK and eSDK

| | Standard SDK (`bitbake <image> -c populate_sdk`) | Extensible SDK (`-c populate_sdk_ext`) |
|---|---|---|
| Contents | Cross toolchain (`-cross-canadian`), the **image's** target sysroot (`TOOLCHAIN_TARGET_TASK`), host tools (`TOOLCHAIN_HOST_TASK`), `environment-setup-<REAL_MULTIMACH_TARGET_SYS>` | All of that plus BitBake, devtool, sstate for the image (`SDK_EXT_TYPE ?= "full"`; `"minimal"` fetches on demand) |
| Name | `environment-setup-cortexa53-crypto-oe-linux` (`REAL_MULTIMACH_TARGET_SYS = "${TUNE_PKGARCH}${TARGET_VENDOR}-${TARGET_OS}"`) | same |
| Install path | `SDKPATHINSTALL = "/usr/local/${SDK_NAME_PREFIX}-${SDK_ARCH}"` (relocatable) | same |
| Updates | Re-install | `devtool sdk-update`, from `SDK_UPDATE_URL` |
| Guarantee | Binaries built with it match **that image's** libraries and tune | Same, and new recipes can be added and built as in the full build |

- **The environment script exports** `CC="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH} --sysroot=$SDKTARGETSYSROOT"` (`toolchain-scripts.bbclass`), plus `PKG_CONFIG_SYSROOT_DIR` and the flags. It refuses to run with `LD_LIBRARY_PATH` set: "The SDK will not operate correctly in most cases when LD_LIBRARY_PATH is set."
- **An SDK is a promise about one image of one release.** A binary built with the 2026.10 SDK and deployed to a device running the 2026.04 image is outside that promise. It works until it records a newer symbol version than the device's glibc has (§2.1).

---

## 2. Production Code & Configuration Blueprints

### 2.1 Proving the ABI floor

The test program uses one function that is old everywhere, `getrandom` (glibc ≥ 2.25), and optionally one that is new, `arc4random` (glibc ≥ 2.36):

```c
/* abi_demo.c - one source, three C libraries: what the toolchain's sysroot silently decides for the target */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/random.h>

int main(void)
{
	unsigned char b[16];

	/* getrandom(): glibc >= 2.25, musl >= 1.1.20. Linking records the symbol VERSION it bound to. */
	if (getrandom(b, sizeof b, 0) != (ssize_t)sizeof b)
		return 1;
#ifdef USE_ARC4RANDOM
	/* arc4random(): glibc >= 2.36 only. Against an older target sysroot this does not link. */
	printf("arc4random: %u\n", arc4random());
#endif
#if defined(__GLIBC__)
	printf("built against glibc %d.%d headers\n", __GLIBC__, __GLIBC_MINOR__);
#else
	printf("built against a non-glibc libc (musl)\n");
#endif
	printf("random byte: %u\n", b[0]);
	return 0;
}
```

An ELF reader that reports what a binary demands from the device:

```python
# elfinfo.py - what a cross-built ELF demands from its target: machine, interpreter, DT_NEEDED, symbol versions
"""Usage: python elfinfo.py <elf> ...   (ELF64 little-endian; enough of readelf -l -d -V for release gates)"""
import struct
import sys

PT_LOAD, PT_INTERP, PT_DYNAMIC = 1, 3, 2
DT_NEEDED, DT_STRTAB, DT_VERNEED, DT_VERNEEDNUM = 1, 5, 0x6FFFFFFE, 0x6FFFFFFF
MACHINES = {183: "AArch64", 62: "x86-64", 243: "RISC-V", 40: "ARM"}


def parse(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise ValueError("not an ELF64 little-endian file")
    e_type, e_machine = struct.unpack_from("<HH", data, 16)
    e_phoff = struct.unpack_from("<Q", data, 32)[0]
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 54)
    loads, interp, dyn = [], None, None
    for i in range(e_phnum):
        p_type, _flags, off, vaddr, _paddr, filesz, _memsz, _align = struct.unpack_from(
            "<IIQQQQQQ", data, e_phoff + i * e_phentsize)
        if p_type == PT_LOAD:
            loads.append((vaddr, off, filesz))
        elif p_type == PT_INTERP:
            interp = data[off:off + filesz].rstrip(b"\0").decode()
        elif p_type == PT_DYNAMIC:
            dyn = (off, filesz)

    def v2o(vaddr):
        for va, off, sz in loads:
            if va <= vaddr < va + sz:
                return off + (vaddr - va)
        raise ValueError(hex(vaddr))

    info = {"type": {2: "EXEC", 3: "DYN (PIE or shared)"}.get(e_type, e_type),
            "machine": MACHINES.get(e_machine, e_machine), "interp": interp, "needed": [], "versions": {}}
    if dyn is None:
        info["linkage"] = "static"
        return info
    info["linkage"] = "dynamic"
    entries = [struct.unpack_from("<qQ", data, dyn[0] + i * 16) for i in range(dyn[1] // 16)]
    tags = {}
    for tag, val in entries:
        tags.setdefault(tag, []).append(val)
    strtab = v2o(tags[DT_STRTAB][0])
    s = lambda o: data[strtab + o:data.index(b"\0", strtab + o)].decode()
    info["needed"] = [s(v) for v in tags.get(DT_NEEDED, [])]
    if DT_VERNEED in tags:                                   # Elf64_Verneed / Elf64_Vernaux chain
        off = v2o(tags[DT_VERNEED][0])
        for _ in range(tags[DT_VERNEEDNUM][0]):
            _ver, cnt, file_, aux, nxt = struct.unpack_from("<HHIII", data, off)
            a = off + aux
            names = []
            for _ in range(cnt):
                _hash, _flags, _other, name, anext = struct.unpack_from("<IHHII", data, a)
                names.append(s(name))
                a += anext
            info["versions"][s(file_)] = sorted(names)
            off += nxt
    return info


def main():
    for path in sys.argv[1:]:
        i = parse(path)
        print(f"{path.replace(chr(92), '/').split('/')[-1]}: {i['machine']} {i['type']}, {i['linkage']}")
        if i["interp"]:
            print(f"   interpreter: {i['interp']}")
        if i["needed"]:
            print(f"   DT_NEEDED:   {' '.join(i['needed'])}")
        for lib, vers in i["versions"].items():
            print(f"   needs from {lib}: {' '.join(vers)}")


if __name__ == "__main__":
    main()
```

The build matrix:

```sh
#!/bin/sh
# abi_build.sh - one source against three target C libraries: prove what each binary demands from the device
# Usage: sh abi_build.sh   (in a directory holding abi_demo.c and elfinfo.py; ZIG = zig binary, default "zig")
ZIG=${ZIG:-zig}

build() {   # <zig target> <output> <label> [extra cflags]
    if err=$("$ZIG" cc -target "$1" -O2 $4 abi_demo.c -o "$2" 2>&1); then
        echo "link OK   $3"
    else
        echo "BUILD FAIL $3: $(printf '%s\n' "$err" | grep -m1 'error:' || printf '%s\n' "$err" | head -n 1)"
    fi
}

build aarch64-linux-gnu.2.39 demo-glibc239      "aarch64-linux-gnu.2.39 (dynamic)"
build aarch64-linux-gnu.2.31 demo-glibc231      "aarch64-linux-gnu.2.31 (dynamic)"
build aarch64-linux-gnu.2.39 demo-glibc239-arc4 "aarch64-linux-gnu.2.39 + arc4random" -DUSE_ARC4RANDOM
build aarch64-linux-gnu.2.31 demo-glibc231-arc4 "aarch64-linux-gnu.2.31 + arc4random" -DUSE_ARC4RANDOM
build aarch64-linux-musl     demo-musl-static   "aarch64-linux-musl (static)"         -static
python -I elfinfo.py demo-glibc239 demo-glibc231 demo-glibc239-arc4 demo-musl-static
for f in demo-glibc239 demo-glibc231 demo-musl-static; do
    echo "size $f: $(wc -c < "$f" | tr -d ' ') bytes"
done
```

```text
link OK   aarch64-linux-gnu.2.39 (dynamic)
link OK   aarch64-linux-gnu.2.31 (dynamic)
link OK   aarch64-linux-gnu.2.39 + arc4random
BUILD FAIL aarch64-linux-gnu.2.31 + arc4random: abi_demo.c:16:29: error: call to undeclared function 'arc4random'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
link OK   aarch64-linux-musl (static)
demo-glibc239: AArch64 EXEC, dynamic
   interpreter: /lib/ld-linux-aarch64.so.1
   DT_NEEDED:   libc.so.6
   needs from libc.so.6: GLIBC_2.17 GLIBC_2.25 GLIBC_2.34
demo-glibc231: AArch64 EXEC, dynamic
   interpreter: /lib/ld-linux-aarch64.so.1
   DT_NEEDED:   libc.so.6
   needs from libc.so.6: GLIBC_2.17 GLIBC_2.25
demo-glibc239-arc4: AArch64 EXEC, dynamic
   interpreter: /lib/ld-linux-aarch64.so.1
   DT_NEEDED:   libc.so.6
   needs from libc.so.6: GLIBC_2.17 GLIBC_2.25 GLIBC_2.34 GLIBC_2.36
demo-musl-static: AArch64 EXEC, static
size demo-glibc239: 8328 bytes
size demo-glibc231: 10720 bytes
size demo-musl-static: 1414952 bytes
```

What it proves:
- **Built against glibc 2.39 headers and stubs, the binary needs `GLIBC_2.34`** although it calls nothing newer than `getrandom`. That's `__libc_start_main`'s 2.34 version, so this binary will not start on a device with glibc 2.31.
- **The same source against 2.31** needs only `GLIBC_2.17` (the AArch64 baseline) and `GLIBC_2.25` (`getrandom`).
- **Using `arc4random` raises the floor to `GLIBC_2.36`.** Against a 2.31 sysroot it doesn't even compile, because the declaration doesn't exist. A sysroot older than the device is safe; a newer one is not.
- **musl static** has no interpreter and no version needs: it runs on any AArch64 Linux kernel, at about 1.4 MB versus about 8 KB.

Exact sizes vary with toolchain version and build directory; the version needs don't.

**Release gate:** run `elfinfo.py` (or `readelf -V`) over every binary that enters an image from outside the build, such as vendor blobs or prebuilt agents. Fail the build if any `GLIBC_x.y` exceeds the image's glibc version.

### 2.2 A recipe that cross-compiles correctly

#### The Fragile Way

```bitbake
# acme-telemetryd-fragile_1.4.0.bb - the same daemon, as the recipe that "built fine on my machine"
SUMMARY = "Acme device telemetry daemon"
LICENSE = "CLOSED"

SRC_URI = "git://git.acme.internal/firmware/telemetryd.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"

DEPENDS = "openssl-native zlib-native"
RDEPENDS:${PN} = "openssl zlib libssl-dev"

EXTRA_OEMAKE = "CC=gcc CFLAGS='-O2 -I/usr/include' LDFLAGS='-L/usr/lib -lssl -lz'"
INSANE_SKIP:${PN} += "ldflags already-stripped dev-deps"

do_compile() {
    oe_runmake
}

do_install() {
    install -d ${D}${bindir}
    cp -r ${S}/build/* ${D}${bindir}/
}
```

#### The Silicon-Hardened Production Way

```bitbake
# acme-telemetryd_1.4.0.bb - a C daemon built the cross-compile-correct way: sysroot-only, QA-clean, split packages
SUMMARY = "Acme device telemetry daemon"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=89aea4e17d99a7cacdbeed46a0096b10"

# A release tag AND the commit it must resolve to: the git fetcher fails if the tag is ever moved.
SRC_URI = "git://git.acme.internal/firmware/telemetryd.git;protocol=https;branch=release/1.4;tag=v${PV}"
SRCREV = "3f1c9e0b7a5d4c2e8f6a1b0d9c7e5a3f2b1d0c9e"

# Build-time: headers, libraries and .pc files staged into recipe-sysroot by these recipes'
# do_populate_sysroot. Nothing is ever taken from the build host's /usr.
DEPENDS = "zlib systemd"

inherit meson pkgconfig systemd

# Optional features as data: "enable flag, disable flag, build deps, runtime deps".
PACKAGECONFIG ??= "tls"
PACKAGECONFIG[tls] = "-Dtls=enabled,-Dtls=disabled,openssl"

SYSTEMD_SERVICE:${PN} = "acme-telemetryd.service"

# Libraries the binary links against become runtime dependencies automatically (shlibs); only
# dependencies the linker cannot see are listed by hand.
RDEPENDS:${PN} = "acme-telemetry-config"

# The diagnostic tool ships separately, so production images can leave it out.
PACKAGES =+ "${PN}-tools"
FILES:${PN}-tools = "${bindir}/telemetry-dump"
```

Notes on the hardened recipe:
- **Nothing in it names a compiler, a path or a flag.** `meson.bbclass` passes the cross file built from the environment.
- **Dependencies are minimal.**
  - `DEPENDS` lists only build-time inputs.
  - OpenSSL appears only through the `tls` `PACKAGECONFIG`, so turning the feature off removes the dependency.
  - `RDEPENDS` lists only what the linker can't see.
- **Source provenance is pinned twice.** BitBake 2.20's git fetcher checks that `tag=` and `SRCREV` agree: "The revision the git tag '%s' resolved to didn't match the SRCREV in use".

A lint that turns each fragile line into the QA check, or the field failure, it causes:

```python
# recipe_lint.py - cross-compilation hygiene for application recipes, mapped to the QA check that would fire
"""Usage: python recipe_lint.py <recipe.bb> ...

Each rule names the oe-core 6.1 insane.bbclass check (ERROR_QA by default) that a correct build would
have raised, or the device-side failure when nothing in the build can see it:
  X1 floating source revision (SRCREV = "${AUTOREV}", or no tag/SRCREV pin): not reproducible, and every
     build may ship different code under the same version
  X2 host include/library paths (-I/usr/include, -L/usr/lib, /usr/local): build-host headers and libraries
     leak into a target binary (QA: buildpaths, arch; on device: wrong ABI, missing symbols)
  X3 hard-coded host tools (CC=gcc, a bare "strip"): the host compiler builds for the host architecture
     (QA: arch); the environment's ${CC} carries --sysroot and the tune flags
  X4 INSANE_SKIP of a check that only hides a cross-compile bug (ldflags, already-stripped, buildpaths,
     dev-deps, rpaths, textrel, arch)
  X5 a -dev, -staticdev or -native package in RDEPENDS (QA: dev-deps; native packages do not exist on target)
  X6 a <pkg>-native build dependency for a library the target binary uses at runtime: the target links
     against nothing (or the host's copy); DEPENDS needs the target recipe
  X7 cp -r / cp -a in do_install: copies the builder's ownership and stray build files
     (QA: host-user-contaminated, installed-vs-shipped)
  X8 LDFLAGS replaced instead of extended: drops ${TARGET_LDFLAGS} (QA: ldflags - no GNU_HASH, no
     -Wl,-z,relro,-z,now from the distro's security flags)
  X9 a licensed recipe without LIC_FILES_CHKSUM, or LICENSE = "CLOSED" on a recipe built from source
"""
import re
import sys

HIDES_BUGS = {"ldflags", "already-stripped", "buildpaths", "dev-deps", "rpaths", "textrel", "arch"}


def values(text, var):
    """All right-hand sides assigned to VAR or VAR:<override> (continuation lines joined)."""
    body = re.sub(r"\\\n", " ", text)
    return [(m.group(1), m.group(2)) for m in
            re.finditer(rf'^\s*({var}(?::[\w${{}}\-]+)*)\s*(?:\?\?=|\?=|:=|\+=|=\+|\.=|=\.|=)\s*"([^"]*)"', body, re.M)]


def lint(path):
    text = open(path, encoding="utf-8").read()
    out = []
    srcrev = [v for _, v in values(text, "SRCREV")]
    src_uri = " ".join(v for _, v in values(text, "SRC_URI"))
    if any("AUTOREV" in v for v in srcrev) or ("git://" in src_uri and not srcrev):
        out.append(("X1", "floating SRCREV: the same PV builds different code"))
    elif "git://" in src_uri and "tag=" not in src_uri:
        out.append(("X1", "SRCREV pinned but no tag= in SRC_URI: nothing ties the commit to a release"))
    flags = " ".join(v for var in ("EXTRA_OEMAKE", "EXTRA_OECONF", "EXTRA_OEMESON", "EXTRA_OECMAKE", "CFLAGS",
                                    "CPPFLAGS", "LDFLAGS", "TARGET_CFLAGS", "TARGET_LDFLAGS")
                     for _, v in values(text, var))
    for host in re.findall(r"-[IL]/usr(?:/local)?/(?:include|lib)\w*|/usr/local/\S+", flags):
        out.append(("X2", f"host path '{host}' in build flags"))
    for tool in re.findall(r"\b(?:CC|CXX|LD|AR)=(?:gcc|g\+\+|cc|clang|ld|ar)\b", flags):
        out.append(("X3", f"'{tool}' replaces the cross toolchain from the environment"))
    if re.search(r"^\s*(?:\$\{?STRIP\}?|strip)\s", text, re.M) and "${STRIP}" not in text:
        out.append(("X3", "host 'strip' called directly"))
    for var, v in values(text, "INSANE_SKIP"):
        for check in sorted(set(v.split()) & HIDES_BUGS):
            out.append(("X4", f"{var} skips '{check}': the bug it reports ships instead"))
    rdeps = " ".join(v for _, v in values(text, "RDEPENDS"))
    for dep in rdeps.split():
        if dep.endswith(("-dev", "-staticdev", "-native")):
            out.append(("X5", f"runtime dependency on '{dep}'"))
    deps = " ".join(v for _, v in values(text, "DEPENDS")).split()
    runtime_names = set(rdeps.split())
    for dep in deps:
        base = dep[:-len("-native")] if dep.endswith("-native") else None
        if base and base in runtime_names and base not in deps:
            out.append(("X6", f"DEPENDS '{dep}' but the target uses {base}: needs DEPENDS '{base}'"))
    install = re.search(r"^do_install(?::\w+)?\s*\(\)\s*\{(.*?)^\}", text, re.M | re.S)
    if install and re.search(r"\bcp\s+-[a-zA-Z]*[ra]", install.group(1)):
        out.append(("X7", "cp -r/-a in do_install: use install -m <mode> per file"))
    for var, v in values(text, "LDFLAGS"):
        if var == "LDFLAGS" and "${LDFLAGS}" not in v and "${TARGET_LDFLAGS}" not in v:
            out.append(("X8", "LDFLAGS assigned without ${TARGET_LDFLAGS}/${LDFLAGS}"))
    if re.search(r"LDFLAGS='[^']*'", flags) and "${LDFLAGS}" not in flags:
        out.append(("X8", "EXTRA_OEMAKE overrides LDFLAGS: the distro's linker flags are dropped"))
    licenses = [v for _, v in values(text, "LICENSE")]
    if licenses and licenses[-1] != "CLOSED" and not values(text, "LIC_FILES_CHKSUM"):
        out.append(("X9", "LICENSE without LIC_FILES_CHKSUM: license changes upstream go unnoticed"))
    if licenses and licenses[-1] == "CLOSED" and ("git://" in src_uri or "https://" in src_uri):
        out.append(("X9", "LICENSE = \"CLOSED\" on a recipe fetched from source: no license is recorded in the SBOM"))
    return out


def main():
    total = 0
    for path in sys.argv[1:]:
        found = lint(path)
        total += len(found)
        print(f"{path.replace(chr(92), '/').rsplit('/', 1)[-1]}: {len(found)} finding(s)")
        for rule, msg in found:
            print(f"   {rule} {msg}")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

```text
acme-telemetryd_1.4.0.bb: 0 finding(s)
exit=0
acme-telemetryd-fragile_1.4.0.bb: 13 finding(s)
   X1 floating SRCREV: the same PV builds different code
   X2 host path '-I/usr/include' in build flags
   X2 host path '-L/usr/lib' in build flags
   X3 'CC=gcc' replaces the cross toolchain from the environment
   X4 INSANE_SKIP:${PN} skips 'already-stripped': the bug it reports ships instead
   X4 INSANE_SKIP:${PN} skips 'dev-deps': the bug it reports ships instead
   X4 INSANE_SKIP:${PN} skips 'ldflags': the bug it reports ships instead
   X5 runtime dependency on 'libssl-dev'
   X6 DEPENDS 'openssl-native' but the target uses openssl: needs DEPENDS 'openssl'
   X6 DEPENDS 'zlib-native' but the target uses zlib: needs DEPENDS 'zlib'
   X7 cp -r/-a in do_install: use install -m <mode> per file
   X8 EXTRA_OEMAKE overrides LDFLAGS: the distro's linker flags are dropped
   X9 LICENSE = "CLOSED" on a recipe fetched from source: no license is recorded in the SBOM
exit=1
```

The fragile recipe would also trip several `ERROR_QA` checks at build time (`arch` if `gcc` is the host's, and `buildpaths`), except where `INSANE_SKIP` silenced them. That is why X4 treats skipping those checks as a finding in its own right. Both recipes also pass the variable-name check of 02.2's `bb_lint.py` (0 findings each).

### 2.3 Building outside the build system: the SDK

#### The Fragile Way

```bash
sudo apt install gcc-aarch64-linux-gnu         # the host distro's cross compiler and its own glibc
aarch64-linux-gnu-gcc -O2 -o app app.c -lssl   # headers and libraries from the host distro's arm64 packages
scp app root@device:/usr/bin/                  # "works on my board" (which runs a dev image from last month)
```

This binary's ABI floor is the host distro's glibc, its OpenSSL is whatever `libssl-dev:arm64` the host had, and its flags are neither the tune's nor the distro's. On a device with an older glibc it fails at load time. With a different OpenSSL it fails at the first symbol or struct the versions disagree on.

#### The Silicon-Hardened Production Way

```bash
# produced by CI with the release, for the exact image shipped:  bitbake acme-image -c populate_sdk
./oecore-acme-image-x86_64-cortexa53-crypto-acme-imx8m-toolchain-2026.10.sh -d /opt/acme/2026.10 -y
. /opt/acme/2026.10/environment-setup-cortexa53-crypto-oe-linux
echo "$CC"        # aarch64-oe-linux-gcc <tune flags> --sysroot=/opt/acme/2026.10/sysroots/cortexa53-crypto-oe-linux
$CC $CFLAGS $LDFLAGS -o app app.c $(pkg-config --cflags --libs openssl)
python3 elfinfo.py app                         # floor must be <= the image's glibc (2.44 for a 6.1 image)
# for anything that ships: a recipe in the product layer, built by CI (section 2.2), not an SDK binary
```

- **The SDK is for development speed.** Products are built by the build system.
- **The installer name** is `TOOLCHAIN_OUTPUTNAME ?= "${SDK_NAME}-toolchain-${SDK_VERSION}"` with `SDK_NAME = "${SDK_NAME_PREFIX}-${IMAGE_BASENAME}-${SDK_ARCH}-${TUNE_PKGARCH}-${MACHINE}"` and `SDK_NAME_PREFIX ?= "oecore"`. The version shown assumes the distro sets `SDK_VERSION` to its release; check the deployed name in `tmp/deploy/sdk/`.
- **When developers need to add recipes**, give them the eSDK (`populate_sdk_ext`) with `SDK_UPDATE_URL` pointing at CI's published sstate, so `devtool add`, `devtool modify` and `devtool build` reuse CI's outputs.

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom on device | Cause | Proof | Fix |
|---|---|---|---|
| `version 'GLIBC_2.3x' not found (required by ...)` | Binary linked against a newer glibc than the device's | `readelf -V` / `elfinfo.py`: version-needs | Rebuild in the build system, or against the device's SDK; ABI gate for external binaries (§2.1) |
| `No such file or directory` when running a binary that exists | Missing interpreter (`PT_INTERP`): a glibc binary on a musl image, or wrong `ld-linux` path | `elfinfo.py` → interpreter | Match the C library; never copy binaries across images |
| `Illegal instruction` in a library | Built for a higher tune (§02.2 1.3), or with host `-march=native` | Disassemble the faulting PC (`objdump -d`), `/proc/cpuinfo` Features | Correct tune; remove host flags (lint X3) |
| `undefined symbol: SSL_...` at load, or crash in a struct accessor | Linked against the host's OpenSSL headers or libraries (lint X2, X6) | `ldd`-equivalent: `elfinfo.py` DT_NEEDED + `readelf -s` | `DEPENDS` on the target recipe; sysroot only |
| `ENOTTY`/`ENOSYS` from a new ioctl or syscall | Userspace built against newer UAPI headers than the running kernel | strace shows the call and error | Headers ≤ the oldest kernel; feature detection at runtime |
| No symbols in a crash dump | Stripped before packaging (`INSANE_SKIP already-stripped`) | `-dbg` package empty | Let `do_package` split debug info; keep `-dbg` packages per release for symbolization |
| Two builds of the same commit differ | Host paths or tools in the build (`buildpaths`), floating `SRCREV` | Reproducibility diff (02.4) | Lint X1–X3; `buildpaths` stays an error |
| `host-user-contaminated` QA error | `cp -a`/`cp -r` from the build tree in `do_install` | QA message names the file and uid | `install -m` per file |

**Post-mortem method for a crashing binary in the field:**
1. Identify the exact image and package versions (the device's `/etc/os-release` and the package manifest, or the SBOM from 02.4).
2. Fetch that release's `-dbg` packages or `IMAGE_GEN_DEBUGFS` debug filesystem; they must be archived per release.
3. Symbolize the core or the pstore log (Folder 04) with `${TARGET_PREFIX}gdb` from that release's SDK, with `set sysroot` pointing at the debug filesystem.
4. Before blaming code, compare the binary's ABI floor and `DT_NEEDED` against the image. A surprising number of "crashes" are binaries from the wrong build.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · The vendor's prebuilt agent

**Initial Prompt:** "A partner ships a prebuilt monitoring agent for our devices as an AArch64 binary. It runs on our dev boards. What do you check before it goes into the product image?"

**L5 Answer:** "Run it on a board for a week and check memory and CPU. If it's stable, add it to the image with a recipe that installs the binary."

**Why L5 Bricks Devices at Scale:** A week on a dev board tests the dev image, not every image in the field.
- **The binary records an ABI floor** (its highest `GLIBC_x.y`) and a set of `DT_NEEDED` libraries. If either exceeds what the oldest supported image provides, devices on that image fail at load time.
- **A stuck update is worse.** If a fleet update rolls the agent out ahead of the base image, the agent fails exactly where the update is stuck. A soak test can't see either.

**L7 Principal Defense:**
- **Treat external binaries as an ABI contract checked by the build.**
  - Read the version needs, `DT_NEEDED`, interpreter and ELF machine.
  - Compare them against the image's glibc and library set (`elfinfo.py`).
  - Reject a floor above the image's glibc, and any library the image doesn't provide.
- **Package it honestly:**
  - `INSANE_SKIP` only for the specific checks a prebuilt can't satisfy (`already-stripped` if it truly ships stripped, documented);
  - `RDEPENDS` on every library it needs, since shlib detection still works on prebuilt ELF;
  - its license recorded for the SBOM.
- **Require the partner to build against our SDK**, or better, ship source or a recipe.

### Chain 2 · Why per-recipe sysroots?

**Initial Prompt:** "A recipe built fine for two years and now fails with a missing header after an unrelated change elsewhere. Explain the mechanism and the fix."

**L5 Answer:** "Something changed the build order. Add the missing package to `DEPENDS`, and maybe clean and rebuild."

**Why L5 Bricks Devices at Scale:** The fix is right, but the L5 misses why it was ever "working".
- **It worked by accident.** Older shared-sysroot designs (and any non-OE build) let a recipe see whatever other recipes had staged. The recipe never declared its dependency; it relied on scheduling luck.
- **Teams that don't understand per-recipe sysroots** respond to such failures with clean builds and retries, and conclude the build system is flaky.

**L7 Principal Defense:**
- **The failure is the design working.** Each recipe's `recipe-sysroot` contains exactly its declared `DEPENDS` closure, so an undeclared dependency fails deterministically once nothing else stages it by chance.
- **Fix the declaration**, not the order.
- **Sweep for others** by building recipes individually from an empty `TMPDIR` with sstate, which surfaces undeclared dependencies.
- **Teach the distinction** between `DEPENDS` (sysroot) and `RDEPENDS` (package manager), and that shared libraries produce their runtime dependencies automatically.

### Chain 3 · glibc or musl for a new product?

**Initial Prompt:** "We're building a single-purpose network appliance on an i.MX8M-class SoC with 256 MB RAM. Someone proposes musl to save space. Decide."

**L5 Answer:** "musl is smaller and simpler, so it's better for embedded. Let's switch `TCLIBC` to musl."

**Why L5 Bricks Devices at Scale:** The decision is about behavior and the software supply chain, not bytes.
- **Behavior differs from glibc** in the DNS resolver, locales and thread stack defaults, and some upstream software is only tested on glibc.
- **Prebuilt third-party binaries** (vendor agents, codecs, GPU or Wi-Fi userspace blobs) are almost always glibc-linked.
- **Finding out after design-in** means rebuilding or wrapping each of them, or shipping two C libraries.

**L7 Principal Defense:**
- **Inventory first:** every prebuilt binary and every major dependency, and whether it's glibc-only.
- **Measure:** the actual image delta between `TCLIBC` values on our package set, plus thread stack and DNS behavior tests.
- **Choose glibc** if any required component is glibc-only, or if you'll accept third-party binaries over the product's life.
- **Choose musl** for closed, source-only appliances, where it wins on footprint and attack surface; then budget porting and testing.
- **Either way the choice is distro-level** (`TCLIBC` in the distro configuration), fixed for the product line, and recorded in the SBOM.

### Chain 4 · The SDK contract

**Initial Prompt:** "App teams build with the SDK and deploy binaries directly to devices over SSH for testing. Some of those binaries end up in production via a side channel. What's your policy?"

**L5 Answer:** "That's fine as long as they use our SDK and not the host compiler; the SDK guarantees compatibility."

**Why L5 Bricks Devices at Scale:**
- **The SDK guarantees compatibility with one image of one release, not "our devices".** A binary built with this release's SDK records this release's glibc floor and library versions, and fails on devices still on the previous image.
- **A side channel bypasses everything else:** signing (Folder 01), the update system (Folder 03), and the SBOM (02.4). The fleet runs code no manifest mentions.

**L7 Principal Defense:**
- **The SDK is a development tool. Production artifacts come only from the build system**, as recipes, signed and delivered as part of an image or a signed update.
- **Ship the eSDK** with `SDK_UPDATE_URL` so app teams can turn their work into recipes (`devtool add` → `devtool finish`) cheaply.
- **Enforce it on the device:** dm-verity on the rootfs makes side-loaded binaries in `/usr` impossible, and an allowlist or IMA policy can cover writable paths.
- **Version-stamp SDKs** with the image release they belong to.

### Chain 5 · Silent flag loss

**Initial Prompt:** "A security audit finds that one of our daemons lacks RELRO and immediate binding, while all other binaries have them. How did that happen and how do you prevent it?"

**L5 Answer:** "The upstream Makefile must not support hardening. Add `-Wl,-z,relro,-z,now` to that recipe's `LDFLAGS`."

**Why L5 Bricks Devices at Scale:** It patches one instance of a class of bug.
- **Root cause:** the recipe *replaced* `LDFLAGS` (or `EXTRA_OEMAKE` passes its own), which drops the distro's `SECURITY_LDFLAGS` along with everything else.
- **Hiding it:** the `ldflags` QA check would have caught the missing `GNU_HASH`, unless the recipe skips that check, which is how the fragile recipe hides it.
- **Hand-adding flags** to one recipe leaves every other recipe written the same way unprotected, and the next release reintroduces it.

**L7 Principal Defense:**
- **Fix the mechanism:** extend, never replace, the toolchain variables (lint X8).
- **Forbid skipping checks** that hide cross-compile bugs (lint X4) in CI.
- **Add an image-level audit:** scan every ELF in the rootfs for `PT_GNU_RELRO`, `BIND_NOW`, PIE and stack-protector symbols, and fail on regressions.
- **Treat the distro's security flags as policy owned by one file** (`security_flags.inc` overrides in the distro), with exceptions per recipe documented in the same place.

### Chain 6 · New headers, old kernel

**Initial Prompt:** "We upgraded to Yocto 6.1 but must keep the vendor's 6.6 kernel for this SoC. Userspace now fails on some ioctls. Explain and fix."

**L5 Answer:** "The new userspace is buggy on the old kernel. Pin those packages to the old versions."

**Why L5 Bricks Devices at Scale:** It misreads the interface.
- **The mechanism:** `linux-libc-headers` 7.2 means userspace compiles against 7.2's UAPI and may call interfaces a 6.6 kernel doesn't implement.
- **The L5's fix makes it worse.** Pinning random packages creates a mixed userspace nobody tested, and the next update unpins them.

**L7 Principal Defense:**
- **Match headers to the oldest kernel the userspace must run on.** Provide `linux-libc-headers` for the vendor kernel version in the BSP layer (`PREFERRED_VERSION_linux-libc-headers`), accepting that userspace can't use newer kernel features.
- **Add runtime feature detection** in our own code.
- **Track it as technical debt:** a vendor kernel far behind the release's headers is a security and maintenance liability.
- **Plan the move to a newer LTS kernel** (or mainline support for the SoC) on a deadline.

---

## 5. Invariants Checklist

- [ ] No host paths, host tools or replaced toolchain variables in any recipe (lint X2, X3, X8); `buildpaths`, `arch`, `ldflags` stay errors.
- [ ] `INSANE_SKIP` never used for checks that hide cross-compile bugs (X4) without a documented exception.
- [ ] `DEPENDS` = build-time inputs only; `RDEPENDS` = only what the linker can't see; no `-dev`/`-native` runtime dependencies.
- [ ] Source pinned by `SRCREV` and `tag=`; no `AUTOREV` in release builds.
- [ ] External binaries pass the ABI gate: version-needs ≤ image glibc; `DT_NEEDED` ⊆ image libraries; correct interpreter and ELF machine.
- [ ] `linux-libc-headers` ≤ the oldest kernel that userspace boots on.
- [ ] SDK/eSDK published per release with the image; production artifacts only from the build system.
- [ ] `-dbg` packages / debug filesystem archived per release for post-mortem symbolization.

## 6. References

- openembedded-core `yocto-6.1`: `meta/conf/bitbake.conf` (triplets, sysroots, `PACKAGES`), `meta/classes-global/insane.bbclass`, `staging.bbclass`, `uninative.bbclass`, `base.bbclass` (toolchain selection), `meta/conf/distro/include/security_flags.inc`, `meta/classes-recipe/populate_sdk_base.bbclass`, `populate_sdk_ext.bbclass`, `toolchain-scripts.bbclass`, `meta/lib/oe/package.py`. <https://github.com/openembedded/openembedded-core/tree/yocto-6.1>
- BitBake `yocto-6.1` git fetcher (`lib/bb/fetch/git.py`; `bb.fetch2` is now a deprecated alias of `bb.fetch`). <https://github.com/openembedded/bitbake/tree/yocto-6.1>
- glibc release notes (2.34: libpthread/libdl merged into libc; 2.36: `arc4random`). <https://sourceware.org/glibc/wiki/Release>
- musl: functional differences from glibc. <https://wiki.musl-libc.org/functional-differences-from-glibc.html>
- Yocto Project SDK manual (standard and extensible SDK). <https://docs.yoctoproject.org/sdk-manual/index.html>
- In this KB: [02.2 BSP layers, tune](02-bsp-layer-engineering-machine-distro-overrides-and-kernel-devtool.md) · [02.4 SBOM, reproducibility](04-sbom-spdx-cve-patching-reproducible-builds-and-license-compliance.md)
