# 03 · Curated Open-Source Firmware and Kernel Repositories to Study

> **Folder:** `08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/` · **File 3 of 3**
> **What this is:** a reading list of production code. For each repository it gives the exact files that show a mechanism from this KB done for real, what to look for in them, and which KB file each one deepens.
>
> **Link verification:** every link below (107 unique GitHub URLs: repositories, files and directories) was requested on **2026-10-26** and returned HTTP 200 at that time. Repositories move files: if a link breaks, search the repository for the file name, or use `git log --follow` on the old path.

---

## 0. How to read a production codebase (the method matters more than the list)

1. **Start from a question, not from `main()`.** For example: "Where does Zephyr decide that the stacked frame is on PSP?" Then use `git grep`/LSP to find the code that answers it.
2. **Read the tests and the commit history of the hot path.** `git log -p -S'dmb' -- path` and `git blame` show *why* a barrier exists. The commit message usually names the silicon bug.
3. **Read the review discussion.** For Linux, search the patch subject on `lore.kernel.org`. The objections raised in review are bar-raiser questions in disguise.
4. **Rebuild one mechanism yourself** with this KB's harness: compile the snippet for M7/A64, compare your listing with the KB's, and break it on purpose.
5. **Write down the invariant** the code maintains, in one sentence, the way each KB file's checklist does.

---

## 1. Linux: the reference implementation of almost everything

Repository: [torvalds/linux](https://github.com/torvalds/linux)

| Read | Look for | Deepens |
|---|---|---|
| [`Documentation/memory-barriers.txt`](https://github.com/torvalds/linux/blob/master/Documentation/memory-barriers.txt) | The "DMA barriers" and "Kernel I/O barrier effects" sections: what `dma_wmb`, `readl` and `writel` guarantee | Folder 03 File 02, Folder 07 File 02 |
| [`tools/memory-model/`](https://github.com/torvalds/linux/tree/master/tools/memory-model) | LKMM: herd7 cat models and litmus tests you can run | Folder 03 File 02 |
| [`arch/arm64/include/asm/barrier.h`](https://github.com/torvalds/linux/blob/master/arch/arm64/include/asm/barrier.h) | `dma_wmb()` = `dmb(oshst)`, `smp_*` variants, `smp_cond_load_*` | Folder 03 Files 01–02 |
| [`arch/arm64/include/asm/io.h`](https://github.com/torvalds/linux/blob/master/arch/arm64/include/asm/io.h) | `__iowmb()`/`__iormb()`: the barriers hidden in `writel`/`readl` | Folder 07 File 02 §1.2 |
| [`arch/arm64/include/asm/cache.h`](https://github.com/torvalds/linux/blob/master/arch/arm64/include/asm/cache.h) | `ARCH_DMA_MINALIGN`, `cache_line_size()` from CTR_EL0.CWG | Playbook chain 13 |
| [`arch/arm64/kernel/head.S`](https://github.com/torvalds/linux/blob/master/arch/arm64/kernel/head.S), [`arch/arm64/mm/proc.S`](https://github.com/torvalds/linux/blob/master/arch/arm64/mm/proc.S) | Reset-to-C: identity map, MMU enable, `__cpu_setup` (MAIR/TCR) | Folder 02 Files 02–03 |
| [`kernel/sched/core.c`](https://github.com/torvalds/linux/blob/master/kernel/sched/core.c) | `try_to_wake_up` memory-ordering comments: a masterclass in documenting barriers | Folder 04 File 02 |
| [`kernel/locking/rtmutex.c`](https://github.com/torvalds/linux/blob/master/kernel/locking/rtmutex.c) | Priority inheritance chains, deadlock detection | Folder 04 File 03 |
| [`kernel/rcu/tree.c`](https://github.com/torvalds/linux/blob/master/kernel/rcu/tree.c), [`Documentation/RCU/whatisRCU.rst`](https://github.com/torvalds/linux/blob/master/Documentation/RCU/whatisRCU.rst) | Grace periods, quiescent states | Playbook chain 22 |
| [`include/linux/kfifo.h`](https://github.com/torvalds/linux/blob/master/include/linux/kfifo.h) | A power-of-two SPSC FIFO with free-running indices | Folder 05 File 02, Folder 07 File 03 |
| [`mm/slub.c`](https://github.com/torvalds/linux/blob/master/mm/slub.c) | Per-CPU slabs, freelist pointer hardening (`CONFIG_SLAB_FREELIST_HARDENED`): why out-of-band or obfuscated links matter | Folder 05 File 01, Folder 07 File 03 §1.1 |
| [`include/linux/bitfield.h`](https://github.com/torvalds/linux/blob/master/include/linux/bitfield.h) | `FIELD_PREP`/`FIELD_GET` instead of C bit-fields | Folder 01 File 02 |
| [`drivers/dma/pl330.c`](https://github.com/torvalds/linux/blob/master/drivers/dma/pl330.c) | A real descriptor/microcode DMA engine driver | Folder 07 File 02 |
| [`drivers/iommu/arm/arm-smmu-v3/arm-smmu-v3.c`](https://github.com/torvalds/linux/blob/master/drivers/iommu/arm/arm-smmu-v3/arm-smmu-v3.c) | Command/event queues (rings shared with hardware), STE/CD tables | Folder 06 File 01 |
| [`drivers/net/ethernet/intel/igb/igb_main.c`](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/igb/igb_main.c) | RX/TX rings, NAPI poll, and the barrier before each tail (doorbell) write ⚠ verify which barrier the current version uses | Folder 06 File 03, Folder 07 File 02 |
| [`net/core/page_pool.c`](https://github.com/torvalds/linux/blob/master/net/core/page_pool.c) | Recycling RX buffers without per-packet allocation | Playbook chain 25 |
| [`drivers/i2c/i2c-core-base.c`](https://github.com/torvalds/linux/blob/master/drivers/i2c/i2c-core-base.c) | `i2c_generic_scl_recovery`: the nine-clock bus clear | Folder 06 File 02 |
| [`kernel/dma/swiotlb.c`](https://github.com/torvalds/linux/blob/master/kernel/dma/swiotlb.c), [`Documentation/core-api/dma-api.rst`](https://github.com/torvalds/linux/blob/master/Documentation/core-api/dma-api.rst) | Bounce buffers; the streaming-DMA ownership rules | Folder 03 File 03 |

---

## 2. RTOS kernels: the same problems at microcontroller scale

**Zephyr:** [zephyrproject-rtos/zephyr](https://github.com/zephyrproject-rtos/zephyr)

| Read | Look for | Deepens |
|---|---|---|
| [`arch/arm/core/cortex_m/fault.c`](https://github.com/zephyrproject-rtos/zephyr/blob/main/arch/arm/core/cortex_m/fault.c), [`fault_s.S`](https://github.com/zephyrproject-rtos/zephyr/blob/main/arch/arm/core/cortex_m/fault_s.S) | MSP/PSP selection from EXC_RETURN, CFSR decoding, stack-overflow detection | Folder 07 File 04 |
| [`arch/arm/core/cortex_m/swap_helper.S`](https://github.com/zephyrproject-rtos/zephyr/blob/main/arch/arm/core/cortex_m/swap_helper.S) | PendSV switch, FP context handling | Folder 04 File 02, chain 19 |
| [`kernel/sched.c`](https://github.com/zephyrproject-rtos/zephyr/blob/main/kernel/sched.c), [`kernel/timeout.c`](https://github.com/zephyrproject-rtos/zephyr/blob/main/kernel/timeout.c) | Ready queues, tickless timeout list | Folder 04 File 02, Folder 05 File 03 |
| [`kernel/mem_slab.c`](https://github.com/zephyrproject-rtos/zephyr/blob/main/kernel/mem_slab.c) | A fixed-block allocator (lock-based: compare with Folder 07 File 03) | Folder 05 File 01 |
| [`subsys/debug/coredump/`](https://github.com/zephyrproject-rtos/zephyr/tree/main/subsys/debug/coredump) | Post-mortem dumps and offline tooling | Folder 07 File 04 |

**FreeRTOS:** [FreeRTOS/FreeRTOS-Kernel](https://github.com/FreeRTOS/FreeRTOS-Kernel)

| Read | Look for | Deepens |
|---|---|---|
| [`portable/GCC/ARM_CM4F/port.c`](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/portable/GCC/ARM_CM4F/port.c), [`ARM_CM7/r0p1/port.c`](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/portable/GCC/ARM_CM7/r0p1/port.c) | `xPortPendSVHandler`: `tst r14, #0x10` → conditional `vstmdb {s16-s31}`; BASEPRI critical sections; the r0p1 erratum workaround | Folder 04 Files 01–02, chain 19 |
| [`portable/GCC/ARM_CM33/non_secure/port.c`](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/portable/GCC/ARM_CM33/non_secure/port.c) | PSPLIM, TrustZone secure context | Folder 02 File 03 |
| [`tasks.c`](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/tasks.c), [`queue.c`](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/queue.c), [`timers.c`](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/timers.c) | Tickless idle (`vTaskStepTick`), priority inheritance in mutexes | Folder 04 Files 02–03 |
| [`stream_buffer.c`](https://github.com/FreeRTOS/FreeRTOS-Kernel/blob/main/stream_buffer.c) | An ISR-to-task SPSC byte stream | Folder 05 File 02 |

**Others worth a deep read:**

- **Eclipse ThreadX:** [`ports/cortex_m7/gnu/src/tx_thread_schedule.S`](https://github.com/eclipse-threadx/threadx/blob/master/ports/cortex_m7/gnu/src/tx_thread_schedule.S). A safety-certified scheduler's context switch; compare with Folder 04 File 02.
- **Apache NuttX:** [`arch/arm/src/armv7-m/arm_hardfault.c`](https://github.com/apache/nuttx/blob/master/arch/arm/src/armv7-m/arm_hardfault.c). Fault-register reporting in a POSIX-style RTOS.
- **RIOT:** [`cpu/cortexm_common/thread_arch.c`](https://github.com/RIOT-OS/RIOT/blob/master/cpu/cortexm_common/thread_arch.c) and [`core/sched.c`](https://github.com/RIOT-OS/RIOT/blob/master/core/sched.c). A compact, readable Cortex-M thread switch.

---

## 3. Boot, secure boot, and firmware update

| Repository | Read | Look for | Deepens |
|---|---|---|---|
| [Trusted Firmware-A](https://github.com/ARM-software/arm-trusted-firmware) | [`bl1/bl1_main.c`](https://github.com/ARM-software/arm-trusted-firmware/blob/master/bl1/bl1_main.c), [`bl2/bl2_main.c`](https://github.com/ARM-software/arm-trusted-firmware/blob/master/bl2/bl2_main.c), [`bl31/bl31_main.c`](https://github.com/ARM-software/arm-trusted-firmware/blob/master/bl31/bl31_main.c), [`drivers/auth/auth_mod.c`](https://github.com/ARM-software/arm-trusted-firmware/blob/master/drivers/auth/auth_mod.c), [`lib/xlat_tables_v2/xlat_tables_core.c`](https://github.com/ARM-software/arm-trusted-firmware/blob/master/lib/xlat_tables_v2/xlat_tables_core.c) | The chain of trust (Trusted Board Boot); page-table construction with break-before-make | Folder 02 File 03, chain 7 |
| [Trusted Firmware-M](https://github.com/TrustedFirmware-M/trusted-firmware-m) | [`secure_fw/`](https://github.com/TrustedFirmware-M/trusted-firmware-m/tree/main/secure_fw) | PSA secure partitions on Armv8-M TrustZone | Folder 02 File 03 |
| [MCUboot](https://github.com/mcu-tools/mcuboot) | [`boot/bootutil/src/loader.c`](https://github.com/mcu-tools/mcuboot/blob/main/boot/bootutil/src/loader.c), [`image_validate.c`](https://github.com/mcu-tools/mcuboot/blob/main/boot/bootutil/src/image_validate.c), [`swap_move.c`](https://github.com/mcu-tools/mcuboot/blob/main/boot/bootutil/src/swap_move.c), [`docs/design.md`](https://github.com/mcu-tools/mcuboot/blob/main/docs/design.md) | Power-fail-safe image swap, trailers and magic, anti-rollback security counters | Chains 7 and 30, Folder 07 File 04 (sealed records) |
| [U-Boot](https://github.com/u-boot/u-boot) | [`arch/arm/cpu/armv8/start.S`](https://github.com/u-boot/u-boot/blob/master/arch/arm/cpu/armv8/start.S), [`cache_v8.c`](https://github.com/u-boot/u-boot/blob/master/arch/arm/cpu/armv8/cache_v8.c) | AArch64 reset, EL transitions, MMU and cache setup | Folder 02 Files 02–03 |
| [OpenSBI](https://github.com/riscv-software-src/opensbi) | [`firmware/fw_base.S`](https://github.com/riscv-software-src/opensbi/blob/master/firmware/fw_base.S), [`lib/sbi/sbi_hart.c`](https://github.com/riscv-software-src/opensbi/blob/master/lib/sbi/sbi_hart.c) | RISC-V M-mode boot, relocation, PMP setup | Folder 02 File 02 (RV crt0) |
| [pico-sdk](https://github.com/raspberrypi/pico-sdk) | [`src/rp2_common/pico_crt0/crt0.S`](https://github.com/raspberrypi/pico-sdk/blob/master/src/rp2_common/pico_crt0/crt0.S), [`hardware_dma/dma.c`](https://github.com/raspberrypi/pico-sdk/blob/master/src/rp2_common/hardware_dma/dma.c) | A clean, small crt0 with data-copy tables; a DMA HAL | Folder 07 Files 01–02 |
| [cmsis-device-h7](https://github.com/STMicroelectronics/cmsis-device-h7) (used by [STM32CubeH7](https://github.com/STMicroelectronics/STM32CubeH7)) | [`Source/Templates/gcc/startup_stm32h743xx.s`](https://github.com/STMicroelectronics/cmsis-device-h7/blob/master/Source/Templates/gcc/startup_stm32h743xx.s) | The vendor startup that Folder 07 File 01 replaces: compare the copy loops, the missing MPU/cache order, the vector table | Folder 07 File 01 |

---

## 4. CMSIS: the canonical Cortex-M register and cache code

- [**CMSIS 6**](https://github.com/ARM-software/CMSIS_6), [`CMSIS/Core/Include/core_cm7.h`](https://github.com/ARM-software/CMSIS_6/blob/main/CMSIS/Core/Include/core_cm7.h) (and [CMSIS 5's version](https://github.com/ARM-software/CMSIS_5/blob/develop/CMSIS/Core/Include/core_cm7.h)).
  - `SCB_EnableICache`, `SCB_EnableDCache` (the set/way loop in Folder 07 File 01).
  - `SCB_InvalidateDCache_by_Addr` (line-exact maintenance in Folder 03 File 03, Folder 07 File 02).
  - `NVIC_*` and `__set_BASEPRI`.
  - The `_VAL2FLD` field macros.

---

## 5. Concurrency: lock-free structures and memory models

| Repository | Read | Look for | Deepens |
|---|---|---|---|
| [Concurrency Kit](https://github.com/concurrencykit/ck) | [`include/ck_ring.h`](https://github.com/concurrencykit/ck/blob/master/include/ck_ring.h) | SPSC/MPMC rings with explicit fences per architecture | Folder 05 File 02 |
| [DPDK](https://github.com/DPDK/dpdk) | [`lib/ring/rte_ring.h`](https://github.com/DPDK/dpdk/blob/main/lib/ring/rte_ring.h) | A bulk/burst MPMC ring at 100 Gb/s scale; head/tail per side on separate lines | Folder 05 File 02, Folder 07 File 03 |
| [herdtools7](https://github.com/herd/herdtools7) | [`litmus/`](https://github.com/herd/herdtools7/tree/master/litmus) | `litmus7`: run MP/SB/LB litmus tests on *your* silicon | Folder 03 File 02, chain 14 |
| Linux LKMM | [`tools/memory-model/`](https://github.com/torvalds/linux/tree/master/tools/memory-model) | The formal kernel memory model | Folder 03 File 02 |

---

## 6. Robust storage

- [**littlefs**](https://github.com/littlefs-project/littlefs): [`lfs.c`](https://github.com/littlefs-project/littlefs/blob/master/lfs.c), [`DESIGN.md`](https://github.com/littlefs-project/littlefs/blob/master/DESIGN.md).
  - Power-loss resilience through copy-on-write metadata pairs with revision counts and CRCs.
  - Wear leveling, and bounded RAM.
  - The best short read on "commit atomically or not at all" (chain 30).

---

## 7. Crash capture and observability

| Repository | Read | Look for | Deepens |
|---|---|---|---|
| [CmBacktrace](https://github.com/armink/CmBacktrace) | [`cm_backtrace/cm_backtrace.c`](https://github.com/armink/CmBacktrace/blob/master/cm_backtrace/cm_backtrace.c) | Heuristic Cortex-M unwinding by scanning for BL-preceded return addresses | Folder 07 File 04 §1.5 |
| [Memfault firmware SDK](https://github.com/memfault/memfault-firmware-sdk) | [`components/panics/`](https://github.com/memfault/memfault-firmware-sdk/tree/master/components/panics) | Production coredump capture, reboot-reason tracking, upload | Folder 07 File 04, chain 28 |
| [Pigweed](https://github.com/google/pigweed) | [`pw_cpu_exception_cortex_m/`](https://github.com/google/pigweed/tree/main/pw_cpu_exception_cortex_m), [`pw_ring_buffer/`](https://github.com/google/pigweed/tree/main/pw_ring_buffer) | A carefully engineered exception entry (PSP/MSP, FP frames), a prefixed-entry ring buffer | Folder 07 Files 03–04 |
| [ESP-IDF](https://github.com/espressif/esp-idf) | [`components/esp_system/panic.c`](https://github.com/espressif/esp-idf/blob/master/components/esp_system/panic.c) | Panic handling on a dual-core SMP RTOS (Xtensa/RISC-V) | Folder 07 File 04 |
| [OpenOCD](https://github.com/openocd-org/openocd) | [`src/target/cortex_m.c`](https://github.com/openocd-org/openocd/blob/master/src/target/cortex_m.c) | The debugger's side: DHCSR, halting, vector catch, reset strategies | Folder 07 File 04 §3 |

---

## 8. Toolchain internals: where the codegen in this KB comes from

| Read | Look for | Deepens |
|---|---|---|
| LLVM [`lld/ELF/Thunks.cpp`](https://github.com/llvm/llvm-project/blob/main/lld/ELF/Thunks.cpp) | Range-extension and interworking thunks: the `movw/movt ip; bx ip` of Folder 07 File 01 §1.4 | Folder 02 File 01, Folder 07 File 01 |
| LLVM [`llvm/lib/Transforms/Scalar/LoopIdiomRecognize.cpp`](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Transforms/Scalar/LoopIdiomRecognize.cpp) | Why crt0 copy loops become `__aeabi_memcpy4`, and the self-recursion guard for functions named `memset`/`memcpy` | Folder 02 File 02, Folder 07 File 01 |
| LLVM [`compiler-rt/lib/builtins/arm/aeabi_memcpy.S`](https://github.com/llvm/llvm-project/blob/main/compiler-rt/lib/builtins/arm/aeabi_memcpy.S) | The AEABI helper ABI | Folder 02 File 02 |
| LLVM [`clang/lib/StaticAnalyzer/Checkers/`](https://github.com/llvm/llvm-project/tree/main/clang/lib/StaticAnalyzer/Checkers) | How `core.UndefinedBinaryOperatorResult` and `NullDereference` work, and why they are path-bounded | Folder 08 File 01 §1.3 |
| [picolibc](https://github.com/picolibc/picolibc) [`libc/machine/arm/`](https://github.com/picolibc/picolibc/tree/main/libc/machine/arm) | An embedded C library: memcpy variants, crt0, TLS on bare metal | Folder 02 File 02 |
| [cppcheck](https://github.com/danmar/cppcheck) [`addons/misra.py`](https://github.com/danmar/cppcheck/blob/main/addons/misra.py) | A free (partial) MISRA C:2012 checker you can add to CI today | Folder 08 File 01 |

---

## 9. Emulators: the hardware models behind fault and exception semantics

- **QEMU:** [`target/arm/tcg/m_helper.c`](https://github.com/qemu/qemu/blob/master/target/arm/tcg/m_helper.c) has M-profile exception entry and return, stacking, lazy FP, and EXC_RETURN checks. [`hw/intc/armv7m_nvic.c`](https://github.com/qemu/qemu/blob/master/hw/intc/armv7m_nvic.c) has the NVIC: priorities, pending/active, and SHCSR. Read them next to this KB's `emu_rtos.py`/`emu_crash.py` harnesses (Folder 04 File 02, Folder 07 File 04): they implement in full what those harnesses implement in a few lines.

---

## 10. Other perspectives: verified kernels and safe languages

- **seL4:** [`src/kernel/thread.c`](https://github.com/seL4/seL4/blob/master/src/kernel/thread.c). A formally verified microkernel (functional correctness proof). It shows what "proof of absence" costs, at the far end of Folder 08 File 01's evidence table.
- **Tock:** [`kernel/src/platform/mpu.rs`](https://github.com/tock/tock/blob/master/kernel/src/platform/mpu.rs). MPU-enforced process isolation on Cortex-M in Rust: Folder 02 File 03's PMSA concepts in a memory-safe kernel.

---

## 11. Specifications in source form

- **Arm ABI** [abi-aa](https://github.com/ARM-software/abi-aa): [`aapcs64/aapcs64.rst`](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst) and [`aapcs32/aapcs32.rst`](https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst). Calling conventions, volatile bit-fields, `Tag_ABI_enum_size` (Folder 01 Files 02–03).
- **RISC-V psABI:** [`riscv-cc.adoc`](https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-cc.adoc) (Folder 01 File 03).

---

## 12. Testing

- **Unity:** [`src/unity.c`](https://github.com/ThrowTheSwitch/Unity/blob/master/src/unity.c). The de-facto C unit-test framework for firmware; with CMock it gives host-side tests of drivers against mocked registers, as this KB's host tests do.

---

## 13. A twelve-week reading plan

| Week | Read | Then do (with this KB's harness) |
|---|---|---|
| 1 | `memory-barriers.txt` (DMA and I/O sections); arm64 `barrier.h`, `io.h` | Re-derive the four DMA orderings of Folder 07 File 02 from the kernel text |
| 2 | LKMM + herdtools7 `litmus7` | Run MP and SB on an Arm board; compare with Folder 03 File 02 |
| 3 | CMSIS `core_cm7.h` cache functions; cmsis-device-h7 startup | Diff the vendor startup against Folder 07 File 01; list every ordering difference |
| 4 | FreeRTOS `ARM_CM4F/port.c`; Zephyr `swap_helper.S` | Add FP-context switching to Folder 04's PendSV and verify it in `emu_rtos.py` |
| 5 | Zephyr `fault.c`; CmBacktrace; Pigweed `pw_cpu_exception_cortex_m` | Inject an FP-frame fault into `emu_crash.py` and extend the record |
| 6 | Linux `kfifo.h`; DPDK `rte_ring.h`; ck `ck_ring.h` | Port a bulk API onto Folder 07 File 03's ring; rerun the stress test |
| 7 | `mm/slub.c` freelist hardening; Zephyr `mem_slab.c` | Add generation-tagged handles to `lf_pool.h` (§1.4 limit) |
| 8 | `igb_main.c` RX path; `page_pool.c`; `pl330.c` | Map igb's descriptor writes onto Folder 07 File 02's barrier table |
| 9 | TF-A BL1/BL2 + `auth_mod.c`; MCUboot `loader.c`, `swap_move.c` | Sketch anti-rollback for Folder 02 File 03's verifier |
| 10 | littlefs `DESIGN.md`, `lfs.c` | Write a power-cut test harness in the style of `emu_crash.py` |
| 11 | QEMU `m_helper.c`, `armv7m_nvic.c` | Find three behaviors that the KB's harnesses approximate, and document the gaps |
| 12 | seL4 overview; cppcheck `misra.py` in CI | Run `misra.py` on Folder 08 File 01's `misra_bad.c`; extend the layer matrix |
