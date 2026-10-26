# 02 · 30 Tier-1 L7 Bar-Raiser Q&A Chains (GPU, Modem, SoC, Memory-Controller Firmware)

> **Folder:** `08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/` · **File 2 of 3**
> **What this is:** thirty *integrative* interview chains in the style of Tier-1 silicon companies' firmware, kernel and SoC-software loops. They cover GPU/accelerator firmware, modem and DSP subsystems, application-processor SoC bring-up, and memory/storage controllers.
> - They are **representative of the domains, not reported questions** from any company.
> - Each chain crosses several folders of this KB and points to the **verified evidence** there. An L7 answer cites mechanisms and measurements, not slogans.
>
> **Chain format:**
> 1. **Prompt.**
> 2. **L5 answer:** correct textbook knowledge.
> 3. **Why it fails on multi-core ARM / DMA silicon.**
> 4. **L7 principal defense.**
> 5. **Bar-raiser follow-ups:** where the interviewer escalates next, with the short answers.
>
> Tags: 🔥 asked in nearly every loop · ⚡ production-incident favorite · 🧊 deep cut.

---

## How bar-raisers score these chains

| Signal | L5 (senior) | L6 (staff) | L7 (principal) |
|---|---|---|---|
| Mechanism | Names the right API | Explains what the hardware does | Explains it *and* where it breaks: which core, interconnect or compiler pass |
| Evidence | "It works in my tests" | Points to a test | Points to a disassembly, a trace, a fault register, or a measurement, and to what the measurement *cannot* show |
| Scope | One component | The subsystem | The system lifecycle: boot, update, field failure, telemetry, certification |
| Trade-offs | One solution | Two options | The decision with its cost, risk and rollback, and what would change the decision |
| Failure thinking | Happy path | Error handling | Failure *modes*: detection latency, containment, recovery, and evidence for the post-mortem |

---

## A. C, the compiler, and the ABI

### 1 🔥 "This polling loop works at `-O0` and hangs forever at `-O2`. Explain it at the IR and instruction level, then fix it properly."

```c
extern int g_ready;            /* set by an ISR or another core */
void wait_ready(void) { while (!g_ready) { } }
```

- **L5:** "Make `g_ready` `volatile`."
- **Why it fails on multi-core ARM:**
  - `volatile` fixes the *compiler* half only. A side-effect-free loop on a plain global may be assumed to terminate (C11 6.8.5p6), and the load is hoisted. Clang 21 deletes the loop entirely (verified, Folder 01 File 01; Folder 03 File 01).
  - With `volatile` the load is re-issued, but on another core nothing orders the *data* the flag guards. The reader can see `g_ready == 1` and stale payload: message passing without acquire/release (verified MP litmus outcome classes, Folder 03 File 02).
- **L7 defense:**
  - ISR → task on one core: `volatile` is sufficient for the flag. Also ensure that the payload is written before the flag (a compiler barrier), and that no wider-than-native access tears.
  - Across cores, or with DMA: `_Atomic int` with `store_explicit(release)` and `load_explicit(acquire)`. The codegen is `stlr`/`ldar` on AArch64 and `dmb ish` + `str` / `ldr` + `dmb ish` on ARMv7 (Folder 03 File 02 matrix).
  - Add `wfe`/`sev` or a doorbell interrupt instead of spinning, for power.
- **Follow-ups:**
  - *"Why is the deleted loop legal?"* The forward-progress assumption: a loop with no I/O, volatile access, synchronization or atomic operation, whose controlling expression is not a constant, may be assumed to terminate.
  - *"Would `asm volatile("" ::: "memory")` in the loop body fix it?"* It forces the reload on Clang and GCC (compiler barrier), but provides no hardware ordering. It's acceptable on a single core for ISR flags, and wrong across cores.

### 2 ⚡ "Review this packet parser: `const struct ipv4_hdr *h = (const void *)(buf + 14);`"

- **L5:** "Fine if the struct is packed."
- **Why it fails:**
  - Two separate violations. **Alignment:** `buf + 14` is 2-byte aligned. Cortex-M0/M0+ fault on unaligned word loads, and LDM/LDRD/VLDR fault on every Arm core.
  - **Strict aliasing:** reading a `uint8_t` buffer through a struct lvalue the effective type doesn't match is UB under TBAA. The optimizer may reorder those reads across writes made through `buf` (verified TBAA reordering, Folder 01 File 01).
  - `packed` fixes alignment by generating byte loads, but not aliasing. It also makes `&h->field` a misaligned pointer that escapes into other code.
- **L7 defense:**
  - `memcpy` into a local struct, or into scalar fields with explicit endianness conversion. The verified Folder 01 File 01 listings show both the cost and the hazard:
    - On Cortex-M7, Clang compiles an 8-byte header `memcpy` into two plain `ldr` (unaligned-tolerant), while the **cast** version becomes a single **`ldrd`**, which requires word alignment on every ARMv7-M core. So the "free" cast is the one that faults on `buf + 14`.
    - On Cortex-M0+ (no unaligned access), `memcpy` becomes byte loads and the cast becomes `ldr`, which faults.
    - GCC behaves similarly ⚠ verify.
  - For zero-copy, receive buffers aligned so that the IP header is 4-aligned: NET_IP_ALIGN-style 2-byte padding in front of the Ethernet header.
- **Follow-ups:**
  - *"Union punning instead?"* Defined in C (not C++), but still needs alignment.
  - *"`-fno-strict-aliasing`?"* The Linux kernel uses it. It costs optimizations everywhere and hides real bugs; treat it as a policy decision, not a fix.

### 3 "Register access layer: C bit-fields or masks and shifts?"

- **L5:** "Bit-fields are more readable."
- **Why it fails:**
  - Bit-field layout (bit order, padding, straddling) is implementation-defined, and so is the **access width**. AAPCS requires the container's width for volatile bit-fields, but a `uint8_t` container produces `ldrb`/`strb` byte-lane accesses that word-only peripherals ignore or answer with a bus error. Verified in Folder 01 File 02 §1.6.2: on M0+, `packed` split every register access into byte lanes.
  - Every bit-field write is a read-modify-write (verified `ldr`/`orr`/`str`). On registers with write-1-to-clear or read-to-clear bits, the RMW clears flags it didn't intend to touch.
- **L7 defense:**
  - Masks and shifts on a full-width `volatile uint32_t`, with explicit write-only patterns for W1C registers. For set/clear registers (BSRR-style), use single writes with no RMW.
  - Generate the register headers from SVD/IP-XACT. Never hand-type addresses (MISRA 11.4 deviation, Folder 08 File 01).
- **Follow-ups:**
  - *"When is RMW on a register unsafe even with masks?"* When an ISR or another bus master modifies the same register between the read and the write. Use set/clear aliases or bit-banding (M3/M4), or mask interrupts around the RMW for that register.

### 4 🔥 "List exactly what `volatile` guarantees and what it doesn't."

- **L5:** "It stops the compiler caching the variable in a register."
- **Why it fails:** That's half of it, and the missing half causes the bugs.
- **L7 defense:**
  - **Guarantees** (C11 5.1.2.3, 6.7.3): each volatile access in the abstract machine is performed, in program order relative to other *volatile* accesses, as an access of the declared type.
  - **No guarantees:**
    - atomicity (a 64-bit volatile on a 32-bit core is two accesses);
    - ordering relative to *non-volatile* accesses (the compiler may move those across it);
    - any hardware ordering (no DMB: another core or a DMA engine may observe the stores in any order on a weakly ordered machine);
    - cache coherency with non-coherent masters.
  - Proper uses: MMIO, `setjmp` locals, signal/ISR-shared flags on one core.
- **Follow-ups:**
  - *"Device memory on Arm is ordered; isn't volatile + Device enough for MMIO?"* For MMIO to the *same* device, yes. But Device accesses are not ordered with Normal-memory accesses: a DMA descriptor (Normal) followed by a doorbell write (Device) needs a DMB (verified, Folder 07 File 02).

### 5 "Call this C function from your AArch64 exception vector: `struct big r = f(a0..a8);`. What must the assembly do?"

- **L5:** "Put the arguments in x0–x7 and `bl f`."
- **Why it fails:**
  - The 9th argument goes on the stack.
  - The large struct return goes through **x8** (an indirect result location supplied by the caller).
  - SP must be 16-byte aligned at the call.
  - The vector must preserve x0–x18 and x30 of the interrupted context: they are caller-saved, so the callee won't.
  - With BTI enabled, an *indirectly* called target (`blr`) needs a `bti c` landing pad. With PAC, a signed return address in LR must be authenticated with the same key and modifier (SP) it was signed with, so don't move SP between `paciasp` and `autiasp` (verified codegen, Folder 01 File 03).
- **L7 defense:**
  - Save the full caller-saved set plus SPSR_ELx/ELR_ELx (and FP/SIMD state if C may touch it, or compile the handler with `-mgeneral-regs-only`).
  - Align SP, allocate the x8 buffer, put arg 9 at `[sp]`, `bl f`, restore, `eret`.
  - On Cortex-M the hardware already stacks r0–r3, r12, LR, PC and xPSR (8-byte aligned via STKALIGN), so a C function *is* a valid handler. That asymmetry is the point of the question.
- **Follow-ups:**
  - *"Red zone?"* None in AAPCS64 for interrupt-safe code (the SysV x86-64 128-byte red zone is the counterexample: kernels compile with `-mno-red-zone`).

---

## B. Boot, linker, and security

### 6 🔥 "Bring up a brand-new SoC from the reset vector to `main()`. Give me your ordered checklist and what breaks if you reorder it."

- **L5:** "Set the stack, copy `.data`, zero `.bss`, call `main`."
- **Why it fails:** On real silicon, at least five steps come before that, and the order is causal:
  1. **Flash wait states *before* raising the core clock.** Otherwise the instruction fetch reads garbage at the new frequency.
  2. **PLL lock and voltage scaling** (raise the voltage before the frequency).
  3. **DDR initialization and training** before any section placed in DDR is copied or zeroed.
  4. **Caches and MPU/MMU** after their RAM is valid. On M7: MPU first, then invalidate + enable the caches (verified trace, Folder 07 File 01).
  5. FPU enable before any FP instruction, including compiler-generated ones in crt0.
- **L7 defense:**
  - The verified Folder 07 File 01 sequence, plus clock and DDR bring-up before the copy tables.
  - Every step that changes the memory map or system registers is followed by `DSB; ISB`.
  - Validated with a **cold boot** (RAM full of garbage, only flash contents surviving). The debugger-download-only LMA bug shows why (verified: the image works under the debugger and runs off the end of ITCM after a power cycle).
- **Follow-ups:**
  - *"Stack before DDR is up?"* Use on-chip SRAM or TCM for the early stack. Many boot ROMs hand over with SP in SRAM.
  - *"How do you debug a hang before the UART works?"* GPIO toggles per step, the debugger's PC sampling, a post-code byte in a backup register.

### 7 "Design secure boot with anti-rollback and A/B updates for a phone-class SoC."

- **L5:** "Sign the image; the bootloader checks the signature."
- **Why it fails:** That stops random images, not *old signed* images with known vulnerabilities (rollback), and it can't recover from a bad update. Without **measured boot**, the OS can't attest what ran.
- **L7 defense:**
  - **Chain of trust:** immutable ROM → BL1 → BL2 → TF-A BL31/TEE → OS. Each stage verifies the next stage's signature against a key hash fused in OTP (verified SHA-256 + verify flow, Folder 02 File 03).
  - **Anti-rollback:** a security version in the signed header, compared against a monotonic counter in OTP/RPMB, which is bumped only *after* the new image has booted successfully.
  - **A/B slots** with a boot-attempt counter, so a failed boot falls back to the other slot.
  - **Key revocation** via OTP fuse bits.
  - **Measured boot:** extend a hash of each stage into a TPM/PCR-like register for remote attestation.
  - **TrustZone:** secure-world keys never leave it.
- **Follow-ups:**
  - *"Where does the check-then-use (TOCTOU) bug hide?"* Verifying an image in flash and then executing from flash, which an attacker can swap between the two. Copy to internal RAM first, then verify, then jump.
  - *"Fault injection?"* Glitch-hardened checks: double comparisons, random delays, flow counters.

### 8 ⚡ "Enabling the MMU hangs the core. Walk me through the root causes."

- **L5:** "The page tables are wrong."
- **Why it fails:** Usually the tables are *nearly* right. The failures are about the transition itself:
  - The code that writes SCTLR.M must be **identity-mapped**: the next instruction is fetched through the new translation.
  - TLBs and caches must be invalidated *before* the enable.
  - The table walker must see the tables. If the walks are cacheable (TCR IRGN/ORGN/SH) but the tables were written with the caches off, or the other way round, the walker reads stale memory.
  - A **break-before-make** violation when changing live mappings.
  - A missing `DSB` after the table writes, or a missing `ISB` after the SCTLR write.
- **L7 defense:** The verified AArch64 sequence (Folder 02 File 03):
  1. Write the tables.
  2. `dsb ish`, then `tlbi vmalle1`, then `dsb ish`.
  3. Set MAIR/TCR/TTBR0, then `isb`.
  4. Set SCTLR.M|C|I, then `isb`.
  5. Do all of this from an identity-mapped page.
  Then move to the high mapping.
- **Follow-ups:**
  - *"Why BBM?"* Two different valid translations for one VA in the TLB at the same time can cause TLB-conflict aborts and loss of coherency. Invalidate in between.

### 9 "Your firmware executes in place from QSPI flash and must also write to that flash. Design it."

- **L5:** "Disable interrupts during the write."
- **Why it fails:**
  - While the flash is erasing or programming, *any* instruction fetch from it stalls or returns garbage. That includes interrupt handlers, the vector table, and the constant pools of the write routine itself.
  - Disabling interrupts for a 400 ms sector erase breaks every real-time deadline, and the watchdog fires.
- **L7 defense:**
  - Run the flash driver from RAM or ITCM (`.ramfunc`, copied by crt0: Folder 07 File 01).
  - Relocate the vector table (VTOR) and the latency-critical ISRs to RAM/ITCM, so interrupts stay enabled during the erase.
  - Or use dual-bank flash with read-while-write.
  - Split erases into steps, and let the watchdog supervisor account for them.
  - Make the update power-loss-safe (chain 30).
- **Follow-ups:**
  - *"Memory-mapped mode vs indirect mode on the QSPI controller?"* You must leave memory-mapped mode to issue commands; anything still fetching from it will fault or stall. That's the same constraint, one level down.

---

## C. Memory hierarchy, caches, and barriers

### 10 🔥 "A Cortex-A core and a Cortex-M core exchange messages through shared SRAM. Design the protocol."

- **L5:** "A ring buffer in shared memory, with a spinlock."
- **Why it fails:**
  - The two cores are usually **not coherent**: the A-core's D-cache can hold the ring while the M-core reads SRAM directly.
  - Spinlocks need exclusives that work across both masters, which needs a global monitor, often absent (Folder 07 File 03 Q5).
  - Polling burns power on both cores.
- **L7 defense:**
  - Two **SPSC rings**, one per direction: single writer per index, so no exclusives are needed.
  - Place them in memory mapped **Normal non-cacheable** on both sides, or do explicit clean/invalidate by line with line-exact layout (Folder 03 File 03).
  - Release/acquire ordering: on Arm, `dmb` before publishing the index, `dmb` after reading it, and a `dsb` before ringing a **mailbox interrupt** (Device write). That's the same Normal → Device rule as `writel` (Folder 07 File 02).
  - Message ownership via a pool (Folder 07 File 03).
- **Follow-ups:**
  - *"Why not just use the hardware semaphore?"* Fine for rare configuration updates. Too slow, and not scalable, for a data path.

### 11 🔥 "Give me one real bug for each of DMB, DSB and ISB."

- **L5:** "DMB orders memory, DSB waits for completion, ISB flushes the pipeline."
- **Why it fails:** Definitions without failure modes don't pass.
- **L7 defense:**
  - **DMB:** a DMA descriptor written to Normal memory, then a doorbell to Device memory, observed by the engine in the opposite order. The engine sees OWN = 0 and stalls (Folder 07 File 02).
  - **DSB:** clear an interrupt flag, then return from the ISR. The posted write hasn't reached the peripheral, the NVIC re-samples a still-high line, and the ISR runs twice. That's the spurious double interrupt (Folder 06 File 01). A DSB, or a read-back of the device, fixes it.
  - **ISB:**
    - Write VTOR, CPACR, MPU or SCTLR and execute the next instruction under the *old* context: prefetched with the old permissions, or the FPU still off.
    - Copy code to ITCM and jump without an ISB: stale prefetch.
- **Follow-ups:**
  - *"Which DMB variant for DMA on AArch64?"* `dmb oshst` (stores, outer shareable) for `dma_wmb`; `oshld` for `dma_rmb`. Inner-shareable `ish` is only for CPU↔CPU ordering.

### 12 ⚡ "Throughput collapses when four cores update per-core statistics. Diagnose and fix."

- **L5:** "Use atomics."
- **Why it fails:** Atomics make it worse. The counters share a cache line (**false sharing**), so every increment steals the line from the other cores.
- **L7 defense:**
  - Prove it first: PMU coherence events, `perf c2c` (HITM), or a microbenchmark (measured false sharing, Folder 03 File 01).
  - Fix with per-core data padded to the **destructive interference size** of *this* platform: 64 B on most Arm and x86 cores; some Apple cores use 128-byte lines ⚠ verify.
  - Use `alignas(64)` (or 128) per struct, and aggregate on read.
- **Follow-ups:**
  - *"`std::hardware_destructive_interference_size` in C?"* No standard equivalent. Use a per-target config macro, as Folder 07 File 03's `LF_LINE` does.

### 13 🧊 "Your DMA buffers are aligned to the 64-byte L1 line, yet corruption persists on a big server SoC. Why?"

- **L5:** "Use a larger buffer."
- **Why it fails:** Cache maintenance granularity is not always the L1 line. On Arm, `CTR_EL0.CWG` (cache writeback granule) is the maximum size a writeback can affect, which may be larger, for example because of a system-level cache or a different line size in an outer level. `CTR_EL0.DminLine` is the minimum line for by-VA operations.
- **L7 defense:**
  - Align and size DMA buffers to `max(CWG, DminLine)`. Linux uses `ARCH_DMA_MINALIGN` and `cache_line_size()` from CWG for exactly this.
  - Never let unrelated data share a CWG-sized granule with a DMA buffer.
  - Prefer an IOMMU plus coherent interconnect (ACE/CHI I/O coherency) on server parts.
- **Follow-ups:**
  - *"How does Linux handle `kmalloc` buffers used for DMA?"* `ARCH_KMALLOC_MINALIGN` and bounce buffers (swiotlb) for small unaligned allocations on non-coherent platforms ⚠ verify the current kernel behavior.

### 14 🔥 "This SPSC ring passed a week of x86 stress tests and corrupts on the ARM board. Why, and prove the fix."

- **L5:** "Add `volatile` to head and tail."
- **Why it fails:** x86 is TSO: store→store and load→load order is preserved, so a missing release/acquire is invisible there. ARM is weakly ordered: the index store can become visible before the slot store.
- **L7 defense:**
  - Release on publish, acquire on observe (Folder 05 File 02; production template in Folder 07 File 03).
  - Prove it in the disassembly: `dmb ish` (v7) or `stlr`/`ldar` (v8) between the slot write and the index publish (verified listings).
  - Prove it on silicon with **litmus7** MP tests (Folder 03 File 02), not with an x86 stress test. TSO can't exhibit the bug.
- **Follow-ups:**
  - *"Would `seq_cst` everywhere be safer?"* Correct but slower (extra barriers); on AArch64 it's `stlr`/`ldar` anyway. Use the weakest correct order, and document why.

---

## D. Interrupts, exceptions, and RTOS

### 15 🔥 "Minimize and *bound* interrupt latency on a Cortex-M7 running an RTOS."

- **L5:** "Use the highest priority and keep the ISR short."
- **Why it fails:** Latency is dominated by what the ISR *waits for*:
  - critical sections that mask with PRIMASK;
  - flash wait states and cache misses on the vector fetch and the ISR code;
  - lazy FP stacking;
  - the longest non-interruptible instruction sequences;
  - bus contention.
- **L7 defense:**
  - Hardware entry is ~12 cycles ⚠ verify per core.
  - Mask with **BASEPRI**, never PRIMASK, so zero-latency ISRs above the RTOS threshold are never blocked (Folder 04 File 01).
  - Vector table and hot ISRs in **ITCM**, ISR data in **DTCM** (Folder 07 File 01).
  - Measure with DWT `CYCCNT` high-water marks and a GPIO on a scope under worst-case load (Folder 08 File 01). Bound it: the longest masked section + entry + memory effects.
- **Follow-ups:**
  - *"Tail-chaining and late arrival?"* Tail-chaining skips unstacking and restacking between back-to-back ISRs. Late arrival lets a higher-priority IRQ take over during stacking. Both reduce latency, and both are visible in DWT traces.

### 16 "Assign priorities for 10 periodic tasks and 6 ISRs, and prove that the deadlines hold."

- **L5:** "Most important task gets the highest priority."
- **Why it fails:** Importance isn't schedulability. Without analysis, a long high-priority task starves short, tight-deadline ones.
- **L7 defense:**
  - Rate- or deadline-monotonic assignment.
  - **Response-time analysis:** `R_i = C_i + B_i + Σ_{j∈hp(i)} ⌈R_i / T_j⌉ · C_j`, iterated to a fixed point. Check `R_i ≤ D_i`.
  - ISRs are the highest-priority "tasks": include their WCETs (Folder 08 File 01) and arrival rates.
  - Blocking `B_i` comes from the priority-ceiling or inheritance bound (Folder 04 File 03).
  - Validate with tracing (SEGGER SystemView, Tracealyzer).
- **Follow-ups:**
  - *"ISRs above `configMAX_SYSCALL_INTERRUPT_PRIORITY`?"* They can't call RTOS APIs, and they are not delayed by kernel critical sections. Reserve them for hard real-time work.

### 17 ⚡ "Mars Pathfinder reset itself repeatedly in 1997. What happened, and could it happen in your RTOS today?"

- **L5:** "Priority inversion; enable priority inheritance."
- **Why it fails:** True, but incomplete. Inheritance only works for **mutexes with owners**. Inversion through *semaphores used as signals*, through queues, or through an ISR waiting on a task can't be fixed by inheritance.
- **L7 defense:**
  - The story: a low-priority task held a mutex protecting a shared bus. Medium-priority tasks preempted it, the high-priority bus task blocked, a watchdog-style timer detected the missed deadline, and the system reset. Uploading a fix that enabled priority inheritance on that mutex resolved it ⚠ verify details.
  - Today: enable inheritance or ceilings for every resource mutex (verified inversion simulator, Folder 04 File 03).
  - Bound critical sections, and never block in ISRs.
  - Use deadline supervision to detect inversion as a missed deadline (Folder 08 File 01).
- **Follow-ups:**
  - *"Inheritance vs ceiling?"* The ceiling protocol (ICPP) prevents chained blocking and deadlock but needs static priority knowledge. Inheritance is dynamic but allows chains.

### 18 "After enabling tickless idle, your system clock drifts and timers fire late. Why?"

- **L5:** "Timer configuration."
- **Why it fails:** Tickless idle reprograms a low-power timer for the next deadline and suppresses ticks. Errors come from:
  - truncation when converting ticks to LPTIM counts;
  - the time spent entering and leaving sleep not being accounted for;
  - a race between computing the sleep length and an interrupt arriving.
  Each accumulates every sleep.
- **L7 defense:**
  - Compute the sleep with interrupts masked and **re-check pending work before WFI** (verified tickless logic, Folder 04 File 02).
  - Correct the tick count from a free-running reference (RTC/LPTIM counter), not from the intended sleep.
  - Carry the fractional remainder; compensate the entry and exit latency.
  - Validate over hours against a reference clock.
- **Follow-ups:**
  - *"Why mask interrupts but still WFI?"* Pending interrupts wake WFI even when masked by PRIMASK. That closes the "decide to sleep, then the IRQ arrives" race.

### 19 🧊 "Port your Cortex-M context switch to a core with an FPU. What changes?"

- **L5:** "Save the FPU registers too."
- **Why it fails:** Saving s0–s31 on every switch wastes ~100 cycles and stack in tasks that never use FP. Missing the lazy-stacking rules corrupts FP state silently.
- **L7 defense:**
  - With lazy stacking (FPCCR.ASPEN/LSPEN), the hardware reserves the s0–s15 + FPSCR frame and stacks it only if the handler uses FP.
  - PendSV saves **s16–s31 only if `EXC_RETURN[4] == 0`** (the task has an FP context), and stores EXC_RETURN in the TCB so the right frame is restored.
  - `CONTROL.FPCA` tracks it.
  - Stack sizes grow by 104 B per FP frame (Folder 08 File 01, the stack formula).
  - Verified integer switch: Folder 04 File 02.
- **Follow-ups:**
  - *"LSPERR in a crash record?"* A lazy-stacking fault: the reserved FP frame area was invalid, usually because of a stack overflow (decoded in Folder 07 File 04).

---

## E. Lock-free structures and memory management

### 20 🔥 "Give me a bounded MPMC queue for 4 cores, and prove its progress guarantee."

- **L5:** "A ring buffer with a CAS on head and tail."
- **Why it fails:** A naive CAS on indices has ABA and torn-slot problems: a consumer can read a slot that a producer has claimed but not yet written.
- **L7 defense:**
  - Vyukov's bounded MPMC: each cell has a **sequence number**. Producers CAS the enqueue position, then write data, then release-store `seq = pos + 1`. Consumers wait for that sequence (verified 4-thread stress, Folder 05 File 02).
  - Progress: **lock-free, not wait-free**. A preempted producer between its CAS and its sequence publish blocks consumers of *that* cell. Say so explicitly.
- **Follow-ups:**
  - *"On LSE vs LL/SC?"* LSE `ldadd`/`cas` can execute as far atomics at the interconnect, so contended throughput scales far better than `ldxr`/`stxr` loops (Folder 05 File 02 Q4; Folder 07 File 03 listings).

### 21 "An allocator for a system that must run 24/7 for ten years."

- **L5:** "Use `malloc` carefully and test for leaks."
- **Why it fails:** General-purpose heaps fragment: they can fail with plenty of free memory (verified adversarial fragmentation, Folder 05 File 01). Their worst-case time is unbounded, and they're lock-based.
- **L7 defense:**
  - Static allocation at init, plus **fixed-block pools** sized from telemetry peaks (`peak` counters, Folder 07 File 03), plus arenas for phase-scoped data.
  - Guards and state words to detect misuse.
  - Pool exhaustion is a *designed* failure path (back-pressure, drop with counters), not an assert.
- **Follow-ups:**
  - *"How do you size the pools?"* Analytic worst case (rate × residence time), validated with field `peak` telemetry, plus a margin, reviewed per release.

### 22 🧊 "Lock-free reads are easy; freeing memory is the hard part. Explain RCU, hazard pointers and epochs, and pick one for an RTOS."

- **L5:** "Use reference counting."
- **Why it fails:** Reference counts on the read path put an atomic RMW on every read, which is the cache-line contention problem again (chain 12). And a reader can still load a pointer to an object whose count has just reached zero.
- **L7 defense:**
  - **RCU:** readers do nothing (on non-preemptible kernels). Writers publish a new version with release, then wait a **grace period** (every CPU passes a quiescent state) before freeing.
  - **Hazard pointers:** readers publish the pointer they use, and reclaimers scan those before freeing. Bounded garbage, but each read pays a store plus a fence.
  - **Epoch-based reclamation:** cheap, but a stalled reader blocks reclamation forever.
  - On an RTOS with known task periods: epochs or quiescent-state RCU, using task completion as the quiescent state. Bound memory with a deferred-free pool.
- **Follow-ups:**
  - *"Why does Linux RCU need memory barriers at all?"* `rcu_assign_pointer` is a release store. `rcu_dereference` relies on address-dependency ordering, which every architecture Linux supports preserves; that is how Alpha was handled ⚠ verify the current LKMM wording.

---

## F. Buses, drivers, and Linux

### 23 ⚡ "Every interrupt from a new peripheral fires twice. The ISR clears the status flag. Why?"

- **L5:** "Hardware bug; add a debounce."
- **Why it fails:**
  - The clear is a **posted write**: it sits in the bus fabric or write buffer. The ISR returns, the NVIC or GIC re-samples the still-asserted level-sensitive line, and pends the interrupt again.
  - The difference between fabrics explains why it appears on one SoC and not another.
- **L7 defense:**
  - Read back the status register (or any register of that peripheral) after the W1C, and/or `DSB` before exception return (verified mechanism, Folder 06 File 01; read-back in Folder 07 File 02's ISR).
  - On PCIe, MSI-X avoids it: edge semantics, and the message write is ordered behind the device's DMA writes.
- **Follow-ups:**
  - *"Why does a read flush the write?"* AXI/AHB bridges, and PCIe ordering rules, return a read completion only after preceding posted writes to the same device.

### 24 🔥 "A PCIe NIC works on x86 and corrupts data on an Arm server. Find it."

- **L5:** "Endianness."
- **Why it fails:** Both are little-endian. The differences are coherency and ordering:
  - x86 snoops device DMA; Arm servers may have non-coherent DMA (ACPI `_CCA` / DT `dma-coherent` missing).
  - x86 MMIO writes are strongly ordered; Arm Device memory isn't ordered with Normal memory.
  - The x86-tested driver uses `dma_alloc_coherent` in one place and streaming DMA without `dma_sync_*` in another, and writes the doorbell with `writel_relaxed`.
- **L7 defense:**
  - Correct DMA API use: map, then sync for the device before the doorbell; sync for the CPU before reading.
  - `dma_wmb()` between descriptor fields and ownership.
  - `writel()` (not relaxed) for the doorbell, or an explicit `wmb()`.
  - Verify the coherency attribute in firmware tables. Use the IOMMU (SMMU) for isolation and to catch bad DMA (Folder 06 File 01; Folder 07 File 02).
- **Follow-ups:**
  - *"Write-combining BAR mappings?"* Faster MMIO bursts, but stores may merge and reorder. A `wmb()` is needed before the doorbell (Folder 06 File 01).

### 25 "Design the Linux receive path for a 1 Mpps NIC."

- **L5:** "Process packets in the IRQ handler."
- **Why it fails:** One million interrupts per second is livelock. Hard-IRQ work blocks other interrupts, and per-packet allocation thrashes the allocator.
- **L7 defense:**
  - **NAPI:** the hard IRQ masks the device interrupt and schedules a poll. The poll processes up to a budget, then calls `napi_complete_done` and re-enables the interrupt (verified skeleton, Folder 06 File 03).
  - Interrupt coalescing (time/packet thresholds).
  - Multiple RX queues with **RSS**, plus IRQ affinity per core.
  - Page-pool recycling (no per-packet `kmalloc`); GRO.
  - Busy-polling or XDP/AF_XDP for latency-critical paths.
- **Follow-ups:**
  - *"Why mask before scheduling the poll?"* Otherwise the device keeps interrupting during the poll. NAPI's whole point is to switch from interrupt-driven to polling under load.

### 26 ⚡ "Expose a device's DMA buffer to user space with `mmap`. What can go wrong?"

- **L5:** "Call `remap_pfn_range` in the `mmap` handler."
- **Why it fails:**
  - Wrong cache attributes: a cacheable user mapping of a non-coherent DMA buffer is stale-data city. Two mappings of the same memory with different attributes is a mismatched-attribute alias on Arm.
  - Lifetime: the device unbinds while user space still maps the buffer.
  - Size and offset validation, which gives users a window onto arbitrary physical memory.
- **L7 defense:**
  - `dma_mmap_coherent()`/`dma_mmap_attrs()`, which pick the right `pgprot`. Otherwise `pgprot_noncached`/`pgprot_writecombine` explicitly.
  - Validate `vm_pgoff` and the size; set `VM_IO | VM_DONTEXPAND | VM_DONTDUMP`.
  - Hold a reference on the buffer for the VMA lifetime. On unbind, zap the mappings (`unmap_mapping_range`) (Folder 06 File 03).
- **Follow-ups:**
  - *"Why not `virt_to_phys` on a `kmalloc` buffer?"* No DMA-API ownership, no IOMMU mapping, wrong attributes, and on some systems not even physically contiguous beyond a page.

### 27 "An I²C sensor reads correctly at boot, then occasionally returns stale data or hangs the bus after a watchdog reset."

- **L5:** "Add retries."
- **Why it fails:** Retries hide two distinct mechanisms:
  1. The MCU reset in the middle of a read and the slave holds SDA low, so the bus is stuck.
  2. A missing **repeated START** between the register-address write and the read: a STOP in between lets the slave's register pointer change (other masters, auto-increment), which shows up as stale data.
- **L7 defense:**
  - Nine-clock bus recovery + STOP at boot and after timeouts (verified at multiple interruption points, Folder 06 File 02).
  - Combined transactions with repeated START.
  - Clock-stretching support with a timeout.
  - Pull-ups sized from the rise-time formula, and a decoding logic analyzer to verify.
- **Follow-ups:**
  - *"SCL held low forever?"* Not recoverable by clocking. Escalate to a slave reset or power-cycle line, and design that in.

---

## G. Debugging, safety, and system design

### 28 🔥 "Field units HardFault about once a month. Build the investigation pipeline."

- **L5:** "Ask for a unit back and debug it."
- **Why it fails:** Monthly faults don't reproduce on a returned unit. By the time it arrives, the evidence (fault registers, stack) was destroyed at reset.
- **L7 defense:**
  1. **Capture:** a naked-asm handler; validated frame capture; CFSR/HFSR/BFAR/MMFAR; heuristic trace; a CRC-sealed record with a build ID in backup SRAM; SYSRESETREQ (verified end to end, 24/24 fields, Folder 07 File 04).
  2. **Transport:** report it on the next boot via telemetry.
  3. **Symbolize** offline against archived ELFs.
  4. **Bucket** by (PC function, LR function, CFSR class).
  5. **Reproduce** with fault injection at the suspected site.
  6. Add MTB/ETM trace capture for the hottest bucket.
  7. Close the loop with a regression test.
- **Follow-ups:**
  - *"IMPRECISERR buckets point at `memcpy`."* Make the faults precise (DISDEFWBUF on M3/M4, DSB after suspect stores) in a diagnostic build (Folder 07 File 04 Q2).

### 29 "This firmware must run ten years without a reboot. What do you design differently?"

- **L5:** "Avoid memory leaks."
- **Why it fails:** Leaks are one of a dozen slow failure modes:
  - counter wrap: a 32-bit ms tick wraps after **49.7 days**;
  - comparisons that aren't wrap-safe;
  - flash wear;
  - clock drift;
  - accumulated soft errors (SEUs) in RAM;
  - configuration corruption;
  - fragmentation.
- **L7 defense:**
  - Wrap-safe time arithmetic (`(int32_t)(a - b) < 0`), and 64-bit monotonic time where needed. Test by seeding counters near the wrap (verified technique, Folder 07 File 03 demo 4).
  - Static allocation and pools; wear-levelled, power-safe storage (chain 30).
  - ECC with periodic **scrubbing**; CRC-checked configuration with redundant copies.
  - Watchdog supervision (Folder 08 File 01); periodic self-tests of the safety mechanisms themselves.
- **Follow-ups:**
  - *"Is a scheduled reboot acceptable?"* Sometimes (rejuvenation), but only as a documented mitigation with its own hazard analysis, never as a substitute for finding the leak.

### 30 🔥 "Design the update and storage path so that power can fail at *any* instruction."

- **L5:** "Write the new image, then set a flag."
- **Why it fails:**
  - Power fails between programming and flagging, or halfway through programming the flag word.
  - Flash programs in pages and erases in sectors.
  - Writes may be reordered by a cache or a controller.
  - A torn flag can read as valid.
- **L7 defense:**
  - **A/B slots:** write the inactive slot, verify its hash and signature, then commit with an **atomic, sealed** metadata record (sequence number + CRC, written last, as with the crash record's magic-last seal in Folder 07 File 04).
  - The bootloader picks the newest *valid* record, plus a boot-attempt counter for rollback (chain 7).
  - For the file system: copy-on-write/log-structured with atomic commits (littlefs-style metadata pairs).
  - Flush write caches, and use FUA for external storage.
  - Brown-out detection with an early-warning interrupt that stops new writes.
  - Validate by **cutting power at random points** in an automated rig: thousands of cycles, checking invariants after each.
- **Follow-ups:**
  - *"How do you test 'any instruction'?"* Fault-injection harnesses that reset at every N-th flash operation (simulated, as in this KB's emulators), plus physical power-cut rigs for the analog reality.

---

## Using this file

- **Two-week interview sprint (README track A):**
  - Rehearse each chain aloud in under four minutes: prompt, L5, why it fails, L7, then one follow-up.
  - For every chain, open the referenced KB file and be able to *show* the evidence: listing, trace, or test output.
- **Mock-interview pairing:** one person plays the bar-raiser and escalates only through the follow-ups. The candidate must name a mechanism, a measurement, and a failure mode in every answer.
