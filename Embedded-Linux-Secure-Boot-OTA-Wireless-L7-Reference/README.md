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
| 02-Yocto-Project-BitBake-and-Cross-Toolchain-Internals | BitBake parsing, task signatures, sstate and hash equivalence; BSP layers and override mechanics; cross toolchains, sysroots, glibc/musl, SDK/eSDK; SBOM/SPDX, CVE patching, reproducible builds, licenses | ⏳ next (awaiting your prompt) |
| 03-OTA-Architecture-SOTA-FOTA-OSTree-and-TUF | A/B and bootloader fallback state machines; libostree internals; TUF and Uptane roles, keys and anti-rollback; delta updates (casync, RAUC, SWUpdate, Mender), multi-ECU flashing | ⏳ |
| 04-Embedded-Linux-Kernel-Internals-and-BSP-Drivers | Boot flow, DT matching, pinmux, CCF; CMA, DMA-BUF, IOMMU/SMMU, SLUB, OOM; GICv3, threaded IRQs, PREEMPT_RT; PCIe/NVMe, MIPI, I²C/SPI, regmap, pstore/ramoops | ⏳ |
| 05-Bluetooth-Low-Energy-BLE-Stack-and-Firmware-Internals | PHY and link layer, connection events, channel selection, PAwR; HCI transports and BlueZ; GATT/ATT throughput math, LE Audio ISO; SMP, LE Secure Connections, IRK/RPA | ⏳ |
| 06-WiFi-80211-Architecture-Linux-mac80211-and-Coexistence | 802.11ax/be (OFDMA, MU-MIMO, MLO, TWT, aggregation); cfg80211/mac80211/nl80211, wpa_supplicant, FullMAC vs SoftMAC; WPA3-SAE, 802.1X, PMF, key hierarchy; Wi-Fi/BLE PTA coexistence | ⏳ |
| 07-Production-Code-Recipes-and-Driver-Blueprints | Yocto BSP, OP-TEE and signed-FIT and OSTree image recipes; TA plus tee-supplicant client; zero-copy DMA platform driver and DT overlay; BlueZ GATT daemon and nl80211 roaming monitor | ⏳ |
| 08-Target-Company-Bar-Raiser-Playbook-Qualcomm-NVIDIA-Apple-KLA | A 15-company focus matrix; 35 L7 scenario Q&A chains; curated repositories and specifications | ⏳ |

Folders are generated one per turn, in order.

## Pinned versions

| Component | Version | Used for |
|---|---|---|
| TF-A (Trusted Firmware-A) | **v2.15.0** | 01.2 and 01.3 sources compiled against its headers; code paths quoted from it |
| OP-TEE OS / optee_client | **4.11.0 / 4.11.0** | 01.3 TA and client compiled against them; defenses quoted from them |
| U-Boot | **v2026.10** | 01.1 HAB fuse tables and CSF; 01.4 FIT signing, measured boot and Kconfig symbol checks |
| Linux | **v7.2** for docs and source quotes (mainline 7.3; LTS 6.18 / 6.12) | dm-verity, fscrypt, trusted keys, OP-TEE DT binding |
| cryptsetup | main (`tests/verity-compat-test`, `man/veritysetup.8.adoc`) | dm-verity root-hash vectors; veritysetup options |
| Toolchain | GCC 16.2 (host), Clang 21.1 via Zig 0.16 (aarch64), OpenSSL 3.5 | Building and running every listing |

## Conventions

- **✅ verified listings.** Every fenced code block whose first line is `/* name.ext - …` or `# name.ext - …` is a real file that was compiled and/or run as described in the file's verification note. The markdown was assembled from those files, so the published text is byte-identical to what was tested.
- **📄** marks configuration quoted from upstream documentation at the pinned version.
- **⚠** marks vendor details that are under NDA or only partly public, or behavior that depends on your kernel or SoC version. Confirm against your reference manual.
- **Fragile vs hardened.** Fragile listings are deliberately vulnerable, and they also compile cleanly. That's the point: the compiler can't see these bugs.
- **Interview prompts are original formulations**, not recalled or leaked questions.

## Verification

### What the Folder 01 gate does (`emb_gate.py`)

1. **Structure:** the four mandatory sections in every file; Fragile/Hardened pairs balanced; every Q&A chain has all four fields.
2. **Listing integrity:** extract every listing from the published markdown, and require byte-identity with the verified source.
3. **Rebuild from the extracted copies:**
   - regenerate fresh RSA keys and OpenSSL-signed images, then rerun the BootROM model;
   - recompile the TF-A sources against TF-A v2.15 headers;
   - recompile the TA and clients against OP-TEE / optee_client 4.11;
   - rerun the RPMB, Boomerang, SMCCC, PUF, dm-verity and PCR models;
   - lint the device trees and FIT sources;
   - run the FIT signing-policy gate (hardened must pass, fragile must fail);
   - resolve every U-Boot `CONFIG_` symbol against v2026.10's Kconfig;
   - syntax-check the shell scripts.
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

### What was not possible here, stated plainly

- **`dtc` and `mkimage` were not run.** Running a downloaded `dtc.exe` was blocked in this environment, and there's no Windows build of U-Boot's `mkimage`. Device trees and `.its` files are checked by my own structural linter (`dts_lint.py`, published in 01.4) and a FIT signing-policy gate (`fit_policy.py`). These catch unit-address/`reg` mismatches, cell-count errors, dangling references, missing properties and policy violations, but they don't replace `dtc` plus dt-schema, or a real `mkimage` signing run.
- **Firmware was compiled, not booted.** TF-A and OP-TEE sources were compiled against the real headers; they were not linked into BL31 or BL32 images or run on QEMU or hardware.
- **Vendor ROM behavior** (NXP, Qualcomm, NVIDIA, AMD, Apple) is described from public documentation. NDA details are marked ⚠.

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

## Related KBs in this workspace

- [Silicon Systems C L7 Reference](../Silicon-Systems-C-L7-Reference/): the bare-metal C, linker scripts, DMA and cache coherency, and Linux driver fundamentals under these firmware stages.
- [CKAD Exam Prep](../CKAD-Exam-Prep/) and [Distributed Systems Design L7 Reference](../Distributed-Systems-Design-L7-Reference/): the fleet backend side of OTA and device attestation.
