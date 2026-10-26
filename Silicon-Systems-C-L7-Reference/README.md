# Silicon Systems C · Bare-Metal · RTOS · Kernel — L7 Reference

A Principal/Staff (L6/L7) knowledge base for systems C on real silicon. It covers:

- Modern ISO C (C11/C17/C23): the abstract machine, undefined behavior, provenance, and the ABI.
- Bare-metal boot, linker scripts, and ELF.
- Weak memory models, barriers, and DMA/cache coherency.
- Cortex-M/R/A, RISC-V and x86-64 exception and interrupt hardware, plus RTOS kernel internals.
- Deterministic memory and lock-free structures.
- SoC buses (AXI/AHB/APB, PCIe, SMMU) and Linux drivers.
- Safety-critical engineering: MISRA C, WCET, and watchdogs.

It is meant to be a permanent engineering reference and a Tier-1 silicon interview playbook (NVIDIA / Qualcomm / Apple / Samsung / Arm L6–L7).

## Layout and build status

| # | Folder | Status |
|---|--------|--------|
| 01 | [`01-C-Language-Standard-Compiler-and-ABI-Physics/`](01-C-Language-Standard-Compiler-and-ABI-Physics/) | ✅ Written 2026-10-26 |
| 02 | [`02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/`](02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/) | ✅ Written 2026-10-26 |
| 03 | [`03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/`](03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/) | ✅ Written 2026-10-26 |
| 04 | [`04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/`](04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/) | ✅ Written 2026-10-26 |
| 05 | [`05-Deterministic-Memory-and-Lock-Free-Data-Structures/`](05-Deterministic-Memory-and-Lock-Free-Data-Structures/) | ✅ Written 2026-10-26 |
| 06 | [`06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/`](06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/) | ✅ Written 2026-10-26 (kernel code in file 03 not compiled: no kernel tree) |
| 07 | [`07-Production-Embedded-C-Code-Blueprints/`](07-Production-Embedded-C-Code-Blueprints/) | ✅ Written 2026-10-26 |
| 08 | [`08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/`](08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/) | ✅ Written 2026-10-26 |

### Folder 01 contents

1. [Undefined behavior, strict aliasing, type punning, and pointer provenance](01-C-Language-Standard-Compiler-and-ABI-Physics/01-undefined-behavior-strict-aliasing-type-punning-and-pointer-provenance.md)
2. [Struct padding, bit-fields, endianness, and cache-line alignment](01-C-Language-Standard-Compiler-and-ABI-Physics/02-struct-padding-bitfields-endianness-and-cache-line-alignment.md)
3. [Calling conventions: AAPCS64, stack frames, red zone, and inline asm](01-C-Language-Standard-Compiler-and-ABI-Physics/03-calling-conventions-aapcs64-stack-frames-red-zone-and-inline-asm.md)

### Folder 02 contents

1. [ELF internals, relocations, GOT/PLT, and GNU LD linker scripts](02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/01-elf-internals-relocations-got-plt-and-gnu-ld-linker-scripts.md)
2. [Reset vector, crt0, `.bss` zeroing, `.data` relocation, and XIP flash](02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/02-reset-vector-crt0-bss-zeroing-data-relocation-and-xip-flash.md)
3. [Secure boot, TrustZone, MPU/MMU page tables, and TCM SRAM](02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/03-secure-boot-trustzone-mpu-mmu-page-tables-and-tcm-sram.md)

Folder 02 adds three verification methods on top of Folder 01's:

- linking with **LLD 21.1** (GNU-ld-syntax scripts);
- inspecting the results with **pyelftools** `readelf.py` and **capstone**;
- **executing** the Cortex-M7, AArch64 and RISC-V reset paths in the **Unicorn 2.1.4** emulator, with RAM pre-filled with `0xA5` and cold-boot semantics (only bytes stored in non-volatile memory survive).

### Folder 03 contents

1. [`volatile` vs. atomics: why `volatile` never fixes multi-core races](03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/01-volatile-vs-atomics-why-volatile-never-fixes-multicore-races.md)
2. [Weak memory models: ARM vs. x86, `DMB`/`DSB`/`ISB`, and C11 memory orders](03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/02-weak-memory-models-arm-vs-x86-dmb-dsb-isb-and-c11-memory-orders.md)
3. [CPU cache coherency (MESI) and DMA clean/invalidate hazards](03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/03-cpu-cache-coherency-mesi-and-dma-cache-invalidation-clean-hazards.md)

Folder 03 adds **measured** results from real threads on the author's x86-64 laptop:
- lost updates;
- store-buffering and message-passing litmus tests;
- seqlock tearing;
- false sharing.

It also adds a deterministic cache + DMA simulator. ARM litmus outcomes are stated architecturally: run them with litmus7 on your silicon.

### Folder 04 contents

1. [ARM NVIC and GIC: tail-chaining, late arrival, and zero-latency ISRs](04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/01-arm-nvic-gic-tail-chaining-late-arrival-and-zero-latency-isrs.md)
2. [RTOS scheduler, PendSV context switch in assembly, and tickless idle](04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/02-rtos-scheduler-context-switch-pendsv-assembly-and-tickless-idle.md)
3. [Priority inversion, inheritance, ceiling protocols, and ISR-safe synchronization](04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/03-priority-inversion-inheritance-ceiling-and-isr-safe-synchronization.md)

Folder 04 adds a key verification: the Thumb-2 PendSV context switch **executed in Unicorn**. A Python harness emulates only the NVIC's exception-entry stacking and `EXC_RETURN` unstacking (ARMv7-M B1.5). Two tasks ran through 15 switches with their callee-saved state independently verified.

### Folder 05 contents

1. [Custom slab, pool, and arena allocators, and preventing fragmentation](05-Deterministic-Memory-and-Lock-Free-Data-Structures/01-custom-slab-pool-arena-allocators-and-preventing-fragmentation.md)
2. [Lock-free SPSC/MPMC rings, LL/SC (`LDREX`/`STREX`, LSE), and ABA](05-Deterministic-Memory-and-Lock-Free-Data-Structures/02-lock-free-spsc-mpmc-ring-buffers-ll-sc-ldrex-strex-and-aba.md)
3. [Intrusive lists, hierarchical timing wheels, and state machines](05-Deterministic-Memory-and-Lock-Free-Data-Structures/03-intrusive-linked-lists-hierarchical-timing-wheels-and-state-machines.md)

### Folder 06 contents

1. [AXI4/AHB/APB interconnects, PCIe BAR/MSI-X, and IOMMU/SMMU](06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/01-axi4-ahb-apb-interconnects-pcie-bar-msi-x-and-iommu-smmu.md)
2. [Low-level I²C (clock stretching, bus recovery), SPI DMA, and UART idle-line reception](06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/02-low-level-i2c-clock-stretching-bus-recovery-spi-dma-and-uart-idle.md)
3. [Linux kernel drivers: top/bottom halves, NAPI, `mmap`, `kmalloc`](06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/03-linux-kernel-drivers-top-bottom-halves-napi-mmap-and-kmalloc.md). **Kernel code here is written against Linux 6.x but was not compiled** (no kernel tree on the build machine); version-sensitive APIs are marked ⚠ verify.

### Folder 07 contents

1. [Complete bare-metal startup (C) and a multi-region linker script](07-Production-Embedded-C-Code-Blueprints/01-complete-bare-metal-startup-c-and-multi-region-linker-script.md): ITCM / DTCM / AXI / DMA-NC / backup `.noinit`, copy/zero tables, MPU-before-caches, NULL guard.
2. [A cache-coherent scatter-gather DMA ping-pong driver](07-Production-Embedded-C-Code-Blueprints/02-cache-coherent-scatter-gather-dma-ping-pong-driver-in-c.md): OWN-bit protocol, the four DMA orderings (including the barriers Linux hides in `writel`/`readl`), interrupt coalescing.
3. [Lock-free C11 ring buffer and fixed-block pool allocator](07-Production-Embedded-C-Code-Blueprints/03-lock-free-c11-atomic-ring-buffer-and-fixed-block-pool-allocator.md): `{tag:24, idx:8}` Treiber pool with misuse detection, a type-generic zero-copy SPSC template.
4. [HardFault crash-dump handler and stack unwinder](07-Production-Embedded-C-Code-Blueprints/04-hardfault-crash-dump-handler-and-stack-unwinder-in-c-and-asm.md): naked entry, validated capture, CRC-sealed backup-SRAM record, SYSRESETREQ, next-boot decode.

Folder 07 composes earlier folders into complete subsystems, and verifies each one end to end:

- The startup is **cold-booted** in Unicorn, with every write to VTOR, CCR, CPACR, the MPU and the cache-maintenance registers counted. The buggy linker script is booted both as a debugger download and through a power cycle.
- The DMA driver runs against a behavioral engine model: OWN protocol, W1C status, stall-on-no-buffer, bus ≠ CPU addresses, and a **coalesced-interrupt** workload. That workload found a real ordering bug in the first draft of the production driver, documented in the file.
- The pool and ring are stress-tested with 4 threads and 1,000,000 messages, with conservation checked by walking the free list, plus deterministic defect demonstrations.
- The crash handler is run **end to end** in emulation: a PSP task faults, the harness performs the architectural exception entry, the real handler records and resets, and a warm reboot decodes the record. 24/24 fields match the injected CPU state.

### Folder 08 contents

1. [Safety-critical C: MISRA, static analysis, stack and WCET bounds, and watchdog supervision](08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/01-safety-critical-misra-c-static-analysis-wcet-and-watchdog-design.md)
2. [30 Tier-1 L7 bar-raiser Q&A chains](08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/02-30-qualcomm-nvidia-apple-samsung-l7-bar-raiser-qna-chains.md): integrative chains for GPU, modem, SoC and memory-controller firmware. They are representative of the domains, not reported questions.
3. [Curated open-source firmware and kernel repositories to study](08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/03-curated-open-source-firmware-and-kernel-repositories-to-study.md): 107 links, each verified to resolve on 2026-10-26, plus a twelve-week reading plan.

Folder 08 File 01 adds two kinds of evidence:

- **A layered-analysis experiment.** Six real defects were run through every analysis available locally: `-Wall -Wextra`, the strict warning set, the Clang Static Analyzer, UBSan host tests, and a cross-ABI test. No layer caught all six. One defect (an out-of-bounds loop bound) was caught by none of them, which is the argument for sound analysis.
- **Measured resource and supervision evidence:**
  - `-fstack-usage` bounds for the Folder 07 crash path;
  - a WCET measurement trap: random inputs reach 82.6% of the worst path;
  - a watchdog supervisor tested against seven failure scenarios, including the SysTick-refresh anti-pattern.

## Verification harnesses (all published inside the KB)

| Harness | What it does | Published in |
|---|---|---|
| `emu_m.py` | Cortex-M7 cold/warm boot: PT_LOAD at PhysAddr, `--flash-only` power-cycle semantics, `0xA5` RAM, register-write watches | [Folder 07 File 01](07-Production-Embedded-C-Code-Blueprints/01-complete-bare-metal-startup-c-and-multi-region-linker-script.md) |
| `emu_rtos.py` | Software NVIC: SVC/PendSV exception entry and EXC_RETURN unstacking for the context-switch test | [Folder 04 File 02](04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/02-rtos-scheduler-context-switch-pendsv-assembly-and-tickless-idle.md) |
| `emu_crash.py` | Bus error → architectural exception entry with latched CFSR/HFSR/BFAR; SYSRESETREQ → warm reset with RAM retained | [Folder 07 File 04](07-Production-Embedded-C-Code-Blueprints/04-hardfault-crash-dump-handler-and-stack-unwinder-in-c-and-asm.md) |
| `emu_count.py` | Executed-instruction and store counts per input (a WCET path-length proxy) | [Folder 08 File 01](08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/01-safety-critical-misra-c-static-analysis-wcet-and-watchdog-design.md) |
| `layers.sh` | The analysis-layer runner (warnings, analyzer, UBSan, cross-ABI) | [Folder 08 File 01](08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/01-safety-critical-misra-c-static-analysis-wcet-and-watchdog-design.md) |

The **folder gate**, run for every folder:

1. Extract every code block whose first line names a file (`/* name.c - …`) from the finished markdown.
2. Rebuild it with the flags below.
3. Rerun its tests or emulation.
4. Diff the outputs against those inserted in the text.

All eight folders passed, except Folder 06 File 03's kernel code, which is explicitly uncompiled.

## Per-file structure (mandatory)

Every file follows the same five-part spine:

1. **First-principles hardware and compiler mechanics.** Register state, bus transactions, pipelines, memory layouts, and the exact ISO C clause involved.
2. **Production C code blueprints.** Each shows *The Subtle Buggy Way* next to *The Silicon-Hardened Production Way*, as complete, warning-free C11/C17/C23 code.
3. **Hardware debugging and post-mortem diagnostics.** Fault-register decoding (CFSR/HFSR/ESR_ELx), JTAG/SWD, Trace32/GDB recipes, and how each bug class looks in a crash dump.
4. **Tier-1 L7 bar-raiser Q&A chains.** Each chain runs: prompt → L5 textbook answer → why L5 fails on multi-core ARM/DMA hardware → L7 principal defense.
5. **Invariants checklist and references.**

## Verification method — read this before trusting a listing

Every assembly listing labeled **"Codegen (verified)"** was produced on 2026-10-26 by an actual compile. It was not typed from memory.

- **Compiler:** Clang **21.1.0**, as bundled in Zig 0.16.0 (`pip install ziglang`, used as `zig cc` / `zig clang`).
- **Common flags:** `-O2 -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-addrsig -g0 -fno-stack-protector`. Listings are then filtered godbolt-style, keeping labels, instructions and data directives.
- **Target triples:**

| Tag | Triple / CPU | Notes |
|-----|--------------|-------|
| `a64` | `aarch64-linux-gnu`, generic | Clang default `-mframe-pointer=non-leaf` |
| `a64mac` | `aarch64-macos` | Apple arm64 ABI |
| `x64` | `x86_64-linux-gnu` | `-fomit-frame-pointer` (upstream Clang default at `-O2`) |
| `i386` | `i386-linux-gnu` | SysV i386 |
| `a32` | `arm-linux-gnueabihf -mcpu=cortex-a7` | AAPCS32 hard-float |
| `m7` | `thumbv7em-none-eabihf -mcpu=cortex-m7 -mfloat-abi=hard` | Hosted (no `-ffreestanding`), like a normal `arm-none-eabi` + newlib build |
| `m33` | `thumbv8m.main-none-eabihf -mcpu=cortex-m33` | ARMv8-M Mainline |
| `m0` | `thumbv6m-none-eabi -mcpu=cortex-m0plus` | ARMv6-M, soft-float |
| `rv64` | `riscv64-linux-gnu` (`lp64d`) | RVA-style generic |
| `m4` | `thumbv7em-none-eabihf -mcpu=cortex-m4 -mfloat-abi=hard` | ARMv7E-M with FPv4-SP |
| `a64e` | `aarch64-none-elf`, generic | Bare-metal, non-PIC (no GOT noise in listings) |
| `a64lse` | `aarch64-none-elf -march=armv8.4-a` | LSE atomics (`cas`, `ldadd`) and RCpc `ldapr` |
| `x64e` | `x86_64-unknown-elf` | Bare-metal, non-PIC, `-fomit-frame-pointer` |
| `rv64e` | `riscv64-unknown-elf -march=rv64gc -mabi=lp64d -mcmodel=medany` | Bare-metal RISC-V |
| `rv32` | `riscv32-unknown-elf -march=rv32imac -mabi=ilp32` | Microcontroller-class RISC-V |
| host | `x86_64-windows-gnu` | Native self-tests, stress tests and UBSan runs |

- **Warning-free claim:** each blueprint compiled with `-Wall -Wextra -Wpedantic -Werror -Wconversion -Wsign-conversion -Wcast-align -Wshadow -Wstrict-prototypes -Wmissing-prototypes`, with zero diagnostics on every listed target.
- **Self-tests:** the outputs shown ran natively on x86-64 Windows 11.
- **GCC:** no GCC was available on the build machine. Statements about GCC codegen are marked **⚠ verify**. They describe documented GCC behavior; reproduce them on Compiler Explorer with your exact GCC release before relying on them.
- **Version-sensitive or unconfirmed facts** (publication years, kernel versions, vendor-specific numbers) are marked **⚠ verify**.
- **Reproducing a listing:** paste the shown source into Compiler Explorer with the same triple and `-O2`. Different compiler versions differ in scheduling and register choice, but not in the property each listing proves.

## Study tracks

- **A · Interview sprint (2 weeks):** read only §1 and the Q&A chains of every file, then the Folder 08 playbook.
- **B · Firmware engineer → Staff:** read every file in order, rebuild every blueprint on your own board, and reproduce one fault per file on purpose.
- **C · Kernel / driver track:** Folders 01 → 03 → 06 → 05 → 04 → 07.
- **D · Safety-critical track:** Folders 01 → 08/01 (MISRA, WCET) → 04 → 05 → 07, with the MISRA/CERT mapping tables in each file.

## Conventions

- 🔥 = asked in nearly every Tier-1 loop; ⚡ = production-incident favorite; 🧊 = deep cut that separates L6 from L7.
- C standard references use clause numbers from C11/C17 (N1570/N2176 drafts) unless marked C23. C23 is ISO/IEC 9899:2024 (N3220 is the closest public draft).
- "MISRA" means MISRA C:2012 rule numbers, which are retained in MISRA C:2023. "CERT" means the SEI CERT C Coding Standard (2016 edition plus wiki).
