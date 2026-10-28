# Embedded Linux, Secure Boot, OTA and Wireless: L7 Platform Firmware Reference

A permanent, single-source-of-truth reference for Principal/Staff (L6/L7) platform-firmware and embedded-Linux work. It's calibrated for interviews and design reviews at Qualcomm, NVIDIA, AMD, Arm, Apple, Samsung, Intel, Broadcom, NXP, Micron, Lattice, Cisco, KLA and Lam Research.

It traces execution from the physical reset vector to userspace daemons:
- BootROM and eFUSEs; TF-A; OP-TEE; U-Boot verified boot;
- the Linux kernel and BSP drivers;
- Yocto and cross toolchains;
- atomic OTA (OSTree, TUF/Uptane);
- BLE and Wi-Fi stacks.

Every file follows the same spine:
1. **First-Principles Architecture & Hardware State Machines**: diagrams, register and memory maps, frame formats.
2. **Production Code & Configuration Blueprints**: each artifact as **The Fragile Way** vs **The Silicon-Hardened Production Way**.
3. **Failure Modes, Brick Recovery & Post-Mortem Debugging.**
4. **L7 Bar-Raiser Q&A Chains**: Initial Prompt → L5 Answer → Why L5 Bricks Devices at Scale → L7 Principal Defense.

Each file then ends with an invariants checklist and references.

---

## Status

| Folder | Contents | Status |
|---|---|---|
| [01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE](01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE/) | **01.1** BootROM, eFUSE/OTP physics and fuse maps (NXP HAB values from U-Boot docs), SRK-table hashing and revocation, SRAM-before-DDR verification, anti-rollback thermometer fuses with commit-on-success, PUF fuzzy extractors; vendor comparison (NXP HAB/AHAB, Qualcomm, NVIDIA, AMD PSP, Apple). **01.2** TF-A exception levels and SCR_EL3, BL1/BL2/BL31/BL32/BL33 with `RESET_TO_BL2`, the TBBR chain of trust and NV counters, the SMC world switch register by register through TF-A v2.15's real code path, SMCCC IDs and dispatch, SiP services and TBBR ports. **01.3** OP-TEE architecture and RPC, TrustZone NS propagation, the TZC-400 register map, TZMA/TZPC, the Boomerang and double-fetch attacks with OP-TEE's real defense code, RPMB frames, HMAC, counters, nonces and key derivation, a Trusted Application and client, the production OP-TEE profile. **01.4** FIT configuration signing (and the 2021/2026 parser CVEs), the U-Boot hardened config, HSM signing, dm-verity internals (validated against cryptsetup's vectors), root-hash provenance, fscrypt v2 with a TEE-derived key, TPM2 measured-boot ordering and A/B-safe sealing | ✅ 2026-10-28 · 4 files · ~38.9k words · 37 verified listings |
| [02-Yocto-Project-BitBake-and-Cross-Toolchain-Internals](02-Yocto-Project-BitBake-and-Cross-Toolchain-Internals/) | **02.1** the cooker pipeline and parse scopes, datastore operators and overrides (a model that reproduces all 25 results in the BitBake manual), tasks and stamps, basehash/taskhash/unihash, sstate and hash equivalence on a model, a one-writer shared-cache design, cache-miss debugging. **02.2** layer mechanics (priority, series checks, `%` prefix matching, fatal dangling appends), the machine/distro/image axes and `OVERRIDES`, the CPU tune as an ABI promise, linux-yocto's metadata model with an additive BSP description resolved statically against yocto-kernel-cache and Linux v7.2 Kconfig, the 6.x signed-FIT recipe split and a verify-before-deploy task, an A/B eMMC layout gated against wic's own option table and placement code, devtool. **02.3** build/host/target and recipe classes, per-recipe sysroots, `DEPENDS` vs `RDEPENDS` vs shlibs, the glibc ABI floor proven on real AArch64 binaries (glibc 2.39/2.31, musl), UAPI headers, `ERROR_QA`, a cross-compile recipe lint, SDK/eSDK. **02.4** SPDX 3.0 knobs, `sbom-cve-check` and VEX (the `cve-check` class is gone), `CVE_STATUS` triage discipline, `SOURCE_DATE_EPOCH` as the code actually resolves it, reproducibility knobs, license policy and GPLv3 Installation Information, a release fragment and an SBOM license gate | ✅ 2026-10-28 · 4 files · ~28.2k words · 31 verified listings |
| [03-OTA-Architecture-SOTA-FOTA-OSTree-and-TUF](03-OTA-Architecture-SOTA-FOTA-OSTree-and-TUF/) | **03.1** SOTA vs FOTA, slot strategies, U-Boot's bootcount and redundant environment read from source, a C model proving the A/B protocol against a power cut before every sector write (4,152 scenarios across nine policy variants), the shipped `.env`/Kconfig tied back to the model, libubootenv and systemd boot-complete integration. **03.2** libostree objects with a GVariant serializer that reproduces libostree's empty-tree constant, hardlink deployments, the `/etc` three-way merge and its stale-default trap, the boot swap proven against every crash state, composefs signed and pull-side trust. **03.3** TUF 1.0.37 client workflow and Uptane 2.1.0 full verification over a pure-Python Ed25519 checked against RFC 8032 and OpenSSL, 18 attack and rotation cases. **03.4** casync's chunker against fixed blocks, RAUC configuration and a custom bootloader backend over 03.1's contract, signed manifests, and a journaled two-phase multi-ECU update | ✅ 2026-10-28 · 4 files · ~24.2k words · 32 verified listings |
| [04-Embedded-Linux-Kernel-Internals-and-BSP-Drivers](04-Embedded-Linux-Kernel-Internals-and-BSP-Drivers/) | **04.1** arm64 boot entry, OF match scoring from `drivers/of/base.c`, pinctrl binding, CCF and `clk_disable_unused`, deferred probe; a platform driver checked against v7.2's headers (`kapi_check.py`: removed APIs, struct fields, callback types) and a DT-to-driver probe checker. **04.2** the arm64 DMA maintenance rules simulated under every cache interleaving, SMMU, CMA/reserved memory, DMA-BUF, SLUB, and the OOM killer's exact arithmetic; a DMA misuse lint. **04.3** GICv3, execution contexts, PREEMPT_RT lock semantics, an interrupt-context lint, and priority inheritance plus IRQ-thread priority simulated. **04.4** PCIe/NVMe/MIPI bring-up, regmap vs raw read-modify-write (race and errno model), pstore/ramoops with an offline extractor implementing the kernel's layout | ✅ 2026-10-28 · 4 files · ~19.7k words · 21 verified listings |
| 05-Bluetooth-Low-Energy-BLE-Stack-and-Firmware-Internals | PHY and link layer, connection events, channel selection, PAwR; HCI transports and BlueZ; GATT/ATT throughput math, LE Audio ISO; SMP, LE Secure Connections, IRK/RPA | ⏳ |
| 06-WiFi-80211-Architecture-Linux-mac80211-and-Coexistence | 802.11ax/be (OFDMA, MU-MIMO, MLO, TWT, aggregation); cfg80211/mac80211/nl80211, wpa_supplicant, FullMAC vs SoftMAC; WPA3-SAE, 802.1X, PMF, key hierarchy; Wi-Fi/BLE PTA coexistence | ⏳ |
| 07-Production-Code-Recipes-and-Driver-Blueprints | Yocto BSP, OP-TEE and signed-FIT and OSTree image recipes; TA plus tee-supplicant client; zero-copy DMA platform driver and DT overlay; BlueZ GATT daemon and nl80211 roaming monitor | ⏳ |
| 08-Target-Company-Bar-Raiser-Playbook-Qualcomm-NVIDIA-Apple-KLA | A 15-company focus matrix; 35 L7 scenario Q&A chains; curated repositories and specifications | ⏳ |

Folders are generated in order, each gated before the next begins.

## Pinned versions

| Component | Version | Used for |
|---|---|---|
| TF-A (Trusted Firmware-A) | **v2.15.0** | 01.2 and 01.3 sources compiled against its headers; code paths quoted from it |
| OP-TEE OS / optee_client | **4.11.0 / 4.11.0** | 01.3 TA and client compiled against them; defenses quoted from them |
| U-Boot | **v2026.10** | 01.1 HAB fuse tables and CSF; 01.4 FIT signing, measured boot and Kconfig symbol checks |
| Linux | **v7.2** for docs and source quotes (mainline 7.3; LTS 6.18 / 6.12) | dm-verity, fscrypt, trusted keys, OP-TEE DT binding |
| cryptsetup | main (`tests/verity-compat-test`, `man/veritysetup.8.adoc`) | dm-verity root-hash vectors; veritysetup options |
| Yocto Project | **6.1 "blacksail"** (oe-core and BitBake tags `yocto-6.1`, BitBake 2.20.0); 6.0 "wrynose" is the LTS line | Folder 02: every variable, class, task and behavior checked against these trees |
| yocto-kernel-cache | branch `yocto-7.2` at `242eecdf` (linux-yocto 7.2's `SRCREV_meta`) | 02.2 BSP description resolution |
| yocto-kernel-tools | `96a8d58b` (oe-core's `kern-tools-native` `SRCREV`) | `spp` search rules, `symbol_why.py` audit semantics |
| wic | **0.3.1** (`6c66da65`, the `SRCREV` of oe-core's `wic_0.3.1.bb`) | 02.2 kickstart option table and partition placement |
| libubootenv / systemd | **0.3.7** (`1e3511ed`) / **261** units | 03.1 `fw_setenv -s`, `force_ro` handling, boot-complete target |
| libostree | **v2026.5** | 03.2 object formats, deploy and boot-swap code, man pages |
| TUF / Uptane | specification **v1.0.37** / standard **2.1.0** | 03.3 client workflow and full verification |
| casync / RAUC / SWUpdate | **v2** / **v1.15.2** / **2026.05.1** | 03.4 chunker, configuration reference, transaction and signing model |
| Toolchain | GCC 16.2 (host), Clang 21.1 via Zig 0.16 (aarch64; glibc 2.39/2.31 and musl targets), OpenSSL 3.5 | Building and running every listing |

## Conventions

- **✅ verified listings.** Every fenced code block whose first line is `/* name.ext - …` or `# name.ext - …` is a real file that was compiled and/or run as described in the file's verification note. The markdown was assembled from those files, so the published text is byte-identical to what was tested.
- **📄** marks configuration quoted from upstream documentation at the pinned version.
- **⚠** marks vendor details that are under NDA or only partly public, or behavior that depends on your kernel or SoC version. Confirm against your reference manual.
- **Fragile vs hardened.** Fragile listings are deliberately vulnerable, and they also compile cleanly. That's the point: the compiler can't see these bugs.
- **Interview prompts are original formulations**, not recalled or leaked questions.

## Verification

### What the gate does (`emb_gate.py`, one run per folder)

1. **Structure:** the four mandatory sections in every file; Fragile/Hardened pairs balanced; every Q&A chain has all four fields.
2. **Listing integrity:** extract every listing from the published markdown, and require byte-identity with the verified source.
3. **Rebuild from the extracted copies.** For Folder 01:
   - regenerate fresh RSA keys and OpenSSL-signed images, then rerun the BootROM model;
   - recompile the TF-A sources against TF-A v2.15 headers;
   - recompile the TA and clients against OP-TEE / optee_client 4.11;
   - rerun the RPMB, Boomerang, SMCCC, PUF, dm-verity and PCR models;
   - lint the device trees and FIT sources;
   - run the FIT signing-policy gate (hardened must pass, fragile must fail);
   - resolve every U-Boot `CONFIG_` symbol against v2026.10's Kconfig;
   - syntax-check the shell scripts.

   For Folder 02:
   - rerun the datastore model against the BitBake manual's examples, and the signature model;
   - lint every layer, machine, distro, bbappend, recipe and release file against an index of 3,679 names built from oe-core and BitBake `yocto-6.1` (hardened sets must be clean; fragile sets must fail with the documented counts);
   - resolve both BSP descriptions through yocto-kernel-cache and Linux v7.2 Kconfig;
   - check both A/B layouts against wic 0.3.1's option table and placement arithmetic;
   - cross-build the ABI demo against glibc 2.39, glibc 2.31 and musl, and check the symbol versions;
   - run the recipe lint, the reproducibility demonstration and the SBOM gate self-test.

   For Folder 03:
   - rebuild and rerun the A/B model (host and AArch64), and derive the bootloader policy from the shipped `.env` and Kconfig;
   - resolve the U-Boot A/B fragment against v2026.10 Kconfig;
   - rerun the OSTree model and configuration gate;
   - rerun Ed25519 against RFC 8032, and against OpenSSL with a freshly generated key;
   - rerun the TUF/Uptane attack suite, the casync chunker comparison, the RAUC configuration gate and the multi-ECU model.

   For Folder 04:
   - check every driver against an index of v7.2's `include/` and `arch/arm64/include` (≈70k function/macro names, ≈20k structs), including a variant that must trip the callback-type rule;
   - lint and probe-check the device trees against their drivers;
   - rerun the DMA, OOM, scheduling, read-modify-write and ramoops models and the DMA and IRQ-context lints.
4. **Links:** relative links resolve; external URLs answer.

### Folder 01 results (2026-10-28)

| Check | Result |
|---|---|
| Structure | 4 of 4 files; 19 Fragile/Hardened pairs; 25 Q&A chains |
| Listings | 37 extracted, 37 byte-identical to verified sources |
| Rebuild and rerun | 20 of 20 steps pass from the extracted copies |
| BootROM model (SHA-256 + RSA-2048 Montgomery) | 21 of 21 checks against OpenSSL-signed images, including TOCTOU, revocation, rollback and fuse physics |
| SMCCC encoder and dispatch | 18 of 18: every PSCI, arch and OP-TEE function ID reproduced from the pinned headers |
| RPMB frame and device model | 11 of 11: replay → COUNTER_FAILURE, tamper → AUTH_FAILURE, stale read → nonce mismatch; HMAC cross-checked against Python |
| Boomerang and double-fetch model | 11 of 11 |
| dm-verity tree | **7 of 7 root hashes match cryptsetup's own test vectors** (v0/v1, SHA-256/SHA-1, 512/1024/4096-byte blocks, salted and unsalted); tamper detection 5 of 5 |
| PCR model | 9 of 9, using U-Boot v2026.10's real measure-before-fixup ordering |
| U-Boot fragments | 27 of 27 secure-fragment symbols defined; the fragile fragment fails the deny policy |
| Relative links | 12 OK |
| External URLs | 21 of 25 return 200. The 4 `developer.arm.com` links return 403 to every automated client (Python and curl); they're cited by document number (DDI 0487, DDI 0504, DEN 0022, DEN 0028) and open normally in a browser |

### Folder 02 results (2026-10-28)

| Check | Result |
|---|---|
| Structure | 4 of 4 files; 11 Fragile/Hardened pairs; 24 Q&A chains |
| Listings | 31 extracted, 31 byte-identical to verified sources |
| Rebuild and rerun | 17 of 17 steps pass from the extracted copies |
| Datastore model | 25 of 25 results stated in the BitBake 2.20 user manual |
| Metadata lint | `bb_lint.py`: hardened layer, machine, distro, two kernel appends and release fragment all 0 findings; fragile layer, machine and kernel append 16, fragile release config 8; both recipes pass the name check. `recipe_lint.py`: hardened recipe 0, fragile 13 |
| BSP description (kernel) | Hardened: 18 fragments, 0 errors, 0 kernel-cache findings. Fragile: 8 errors, including 5 symbols removed from Linux and 2 values stranded by a disabled dependency |
| A/B layout | Hardened: 0 findings, boot container at 33 KiB. Fragile: 10, including a boot container at 17 KiB and an fstab line for `/dev/mmcblkp3` |
| C library ABI | glibc 2.39 build needs `GLIBC_2.34`; 2.31 build needs only 2.17/2.25; `arc4random` raises the floor to 2.36 and doesn't compile against 2.31; musl static has no interpreter |
| Relative links | 11 OK |
| External URLs | 15 of 18 return 200. The 3 `git.yoctoproject.org` web pages return 403 to scripted clients (a bot check); the same URLs' git endpoints return 200, and all three repositories were cloned from them for this folder |

### Folder 03 results (2026-10-28)

| Check | Result |
|---|---|
| Structure | 4 of 4 files; 10 Fragile/Hardened pairs; 24 Q&A chains |
| Listings | 32 extracted, 32 byte-identical to verified sources |
| Rebuild and rerun | 17 of 17 steps pass from the extracted copies |
| A/B protocol | Hardened: 408 power-cut scenarios, none stuck or looping, every good update committed. Removing redundancy, `bootlimit`, health-gated commit or the watchdog each fails; switch-first and no-fallback are each masked by the other and fail together (56 bricked) |
| Policy derivation | The shipped `.env` + Kconfig derive `redundant_env=1 bootlimit=3 fallback_on_bad_image=1 watchdog=1`, the proven policy; the fragile set has 12 findings |
| OSTree | Empty-tree checksum equals libostree's constant; boot swap: 32 crash states, all bootable (in-place rewrite: 5 of 12 unbootable) |
| TUF / Uptane | Ed25519: RFC 8032 TEST 1-2 and OpenSSL interop both ways; 18 of 18 attack, rotation and Uptane cases with the expected outcome |
| Deltas | 100-byte insert + 4 KiB edit in 4 MiB: fixed blocks 3,072 KiB, casync CDC 48 KiB (16 KiB average) / 274 KiB (64 KiB) |
| Multi-ECU | Journaled two-phase: 56 scenarios, 0 incompatible; sequential: 20 of 32 incompatible |
| Relative links | 14 OK |
| External URLs | 15 of 15 return 200 |

### Folder 04 results (2026-10-28)

| Check | Result |
|---|---|
| Structure | 4 of 4 files; 7 Fragile/Hardened pairs; 24 Q&A chains |
| Listings | 21 extracted, 21 byte-identical to verified sources |
| Rebuild and rerun | 16 of 16 steps pass from the extracted copies |
| Kernel API | 4 hardened drivers clean against v7.2 headers; fragile: `devm_ioremap_nocache()` gone, `.remove_new` gone, `int remove()` vs `void (*remove)` |
| DT ↔ driver | Hardened node binds `acme,imx8mm-fan` (imx8mm data), 0 findings; fragile node binds the generic variant with 5 probe-breaking errors that `dtc`-level lint cannot see |
| DMA | Correct API use: 0 corrupt interleavings; each misuse corrupts some (e.g. read before `sync_for_cpu`: 5 of 25); DMA lint 0 vs 8 |
| Scheduling | No PI: 3.2 ms; rt_mutex PI: 220 µs; default IRQ thread (FIFO 50) under a FIFO-80 hog: 3.9 ms vs 30 µs when raised |
| regmap | Unlocked RMW loses an update in 4 of 6 interleavings; `-EIO` masked into the register writes `0xfb` |
| ramoops | Kernel layout, signature, wrapped-ring reassembly and invalid-zone detection self-tested |
| Relative links / URLs | 12 OK / 5 of 5 |

### What was not possible here, stated plainly

- **`dtc` and `mkimage` were not run.** Running a downloaded `dtc.exe` was blocked in this environment, and there's no Windows build of U-Boot's `mkimage`. Device trees and `.its` files are checked by my own structural linter (`dts_lint.py`, published in 01.4) and a FIT signing-policy gate (`fit_policy.py`). These catch unit-address/`reg` mismatches, cell-count errors, dangling references, missing properties and policy violations, but they don't replace `dtc` plus dt-schema, or a real `mkimage` signing run.
- **Firmware was compiled, not booted.** TF-A and OP-TEE sources were compiled against the real headers; they were not linked into BL31 or BL32 images or run on QEMU or hardware.
- **Vendor ROM behavior** (NXP, Qualcomm, NVIDIA, AMD, Apple) is described from public documentation. NDA details are marked ⚠.
- **No BitBake, kernel build or wic run (Folder 02).** Running downloaded build tools isn't possible in this environment. Folder 02 therefore verifies against the real sources instead:
  - names and behaviors are read from the pinned oe-core, BitBake, kernel-cache, kern-tools and wic trees;
  - the datastore and signature models are validated against the manual's stated results;
  - `scc_audit.py` and `wks_check.py` mirror the upstream code paths they cite, and say what they don't model (Kconfig `select`, choices and `source`-inherited conditions). The real `do_kernel_configcheck` stays in the recommended pipeline.

## Where this KB refines the brief

1. **Files are written to disk** in the blueprint's exact tree, rather than emitted as `### FILE:` blocks in chat. Where the role text and the tree name folders differently (`01-Hardware-Secure-Boot-and-OPTEE` vs `01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE`), the tree wins.
2. **"dm-verity verifies on every page fault" is corrected.** Per the kernel's own documentation and code, blocks are verified on their first read into the page cache; cached pages aren't re-verified, and `check_at_most_once` skips even device re-reads (01.4 §1.3).
3. **"Encrypted, HMAC-authenticated RPMB frames" is refined.** RPMB frames are **authenticated** (HMAC over bytes 228–511, write counter, nonce), not encrypted. Confidentiality comes from OP-TEE encrypting object data under HUK-derived keys (01.3 §1.5, Chain 3).
4. **The reset vector is stated precisely.** On ARMv8-A it's IMPLEMENTATION DEFINED via RVBAR_EL3; 0x00000000 / 0xFFFF0000 are the ARMv7-A conventions (01.1 §1.1).
5. **Current through October 2026:**
   - U-Boot v2026.10's `CONFIG_FIT_VERITY`, and its dependency on a FIT block driver that isn't in mainline Linux;
   - the July 2026 Binarly FIT-signature parser bugs, with evidence of their fixes in v2026.10;
   - OP-TEE 4.11's in-kernel RPMB routing (`CFG_RPMB_ANNOUNCE_PROBE_CAP`) and UFS RPMB;
   - TF-A 2.15's C-language SMC dispatch.
6. **Defaults that silently void security are called out with their source lines:**
   - OP-TEE's `CFG_INSECURE ?= y` with an all-zero HUK stub;
   - `TA_SIGN_KEY ?= keys/default_ta.pem`;
   - TF-A's NV-counter upgrade at authentication time;
   - `ROTPK_NOT_DEPLOYED` skipping ROTPK verification;
   - CAAM trusted keys using a fixed test key on open parts.
7. **Yocto as it is in 6.1, not as most tutorials describe it (Folder 02):**
   - the combined `poky` repository's last tag is `yocto-5.2.4`, and builds are assembled with `bitbake-setup`;
   - the signed kernel FIT moved to the separate `linux-yocto-fitimage` recipe;
   - `cve-check` is gone (`sbom-cve-check` + `vex`), and wic is a standalone project;
   - `bb.fetch2` is a deprecated alias of `bb.fetch`;
   - `BB_DANGLINGAPPENDS_WARNONLY` was removed, so dangling appends are always fatal;
   - `BUILD_REPRODUCIBLE_BINARIES` no longer exists anywhere.
8. **Silent failures separated from loud ones, with the source line for each:**
   - old `_append` syntax is fatal, but `RDEPENDS_${PN}` silently sets an unused variable;
   - renamed variables error, but removed ones are no-ops;
   - `INCOMPATIBLE_LICENSE = "GPL-3.0-only"` silently admits `-or-later`;
   - wic deletes undefined `${VAR}`s and edits the rootfs fstab;
   - `oe/fitimage.py` skips its key check for PKCS#11 keydirs, and nothing verifies the kernel FIT against U-Boot's embedded key;
   - default kernel-audit levels hide invalid fragment lines.
9. **Upstream inconsistencies found and stated:**
   - at the pinned kernel-cache commit, `ktypes/standard` requests `CRYPTO_ARC4`, `TEA`, `KHAZAD` and `ANUBIS` while its own `crypto-obsolete-disable` fragment switches off their dependency;
   - `ktypes/base` strands `features/security`'s `DEBUG_LIST` family;
   - `oe/reproducible.py`'s header lists a "known files" step that the code no longer calls.
10. **OTA mechanisms stated from their code, not their marketing (Folder 03):**
    - U-Boot saves the boot counter only while `upgrade_available` is set, and falls back at `bootcount > bootlimit`;
    - a single environment copy turns a torn save into the default environment;
    - libubootenv unlocks `force_ro` only for literal `/dev/mmcblkNbootM` names;
    - OSTree's `/etc` merge keeps locally modified files over new defaults, and `ostree.prepare-root.composefs=` on the command line overrides the signed config;
    - `sign-verify=true` makes OSTree keys optional;
    - RAUC's `uboot` backend uses different variables from a custom U-Boot contract, so the two must not be mixed.
11. **The models in Folder 03 are protocol models,** not the shipping implementations. Each one states the source functions it mirrors and what it abstracts: sector-atomic writes, a CRC standing in for the FIT signature, no TUF delegations or consistent snapshots. The real U-Boot, ostree, RAUC and TUF clients still need power-cut rigs and conformance suites on the target.
12. **Kernel drivers are checked, not built (Folder 04).** A module build needs the configured tree (`make modules_prepare`) on a POSIX host. Instead:
    - `kapi_check.py` reads v7.2's headers and catches removed APIs, missing fields and callback-type changes; it's heuristic by design and stated as such;
    - semantic lints and models cover DMA, IRQ context, scheduling and register races;
    - `dts_lint.py` (01.4) was corrected in this folder to dtc's rule that a non-empty `ranges` satisfies a unit address, and Folder 01 was re-gated after the change.

## Related KBs in this workspace

- [Silicon Systems C L7 Reference](../Silicon-Systems-C-L7-Reference/): the bare-metal C, linker scripts, DMA and cache coherency, and Linux driver fundamentals under these firmware stages.
- [CKAD Exam Prep](../CKAD-Exam-Prep/) and [Distributed Systems Design L7 Reference](../Distributed-Systems-Design-L7-Reference/): the fleet backend side of OTA and device attestation.
