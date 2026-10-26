# 01 · ELF Internals, Relocations, GOT/PLT, and GNU LD Linker Scripts

> **Folder:** `02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/` · **File 1 of 3**
> **Anchors:**
> - System V gABI, *ELF* chapters 4–5 (sections, segments, symbols, relocation, dynamic linking).
> - Arm *ELF for the Arm Architecture* (AAELF32, IHI 0044) and *for the Arm 64-bit Architecture* (AAELF64, IHI 0056): relocation codes.
> - GNU ld manual §3 *Linker Scripts*; LLD ELF linker-script compatibility notes.
> - Ulrich Drepper, *How To Write Shared Libraries* (2011): GOT/PLT, visibility, relocation cost.
> - Linux `kernel/module/` loader and arm64 `module-plts.c`.
>
> **Verification:** every listing marked *verified* was produced on 2026-10-26:
> - compiled with Clang 21.1.0 and linked with **LLD 21.1.0** (`zig ld.lld`) using the GNU-syntax scripts shown;
> - inspected with `readelf.py` (pyelftools 0.33) and capstone 5.0.7;
> - the reset path executed in **Unicorn 2.1.4** (Cortex-M7 model).
>
> GNU ld-specific behavior is marked ⚠ verify.

---

## 0. The thesis

The C compiler emits **relocatable fragments that know nothing about where they will live**. The linker is the component that decides physical reality:

- which bytes go to flash and which to RAM;
- where each function actually executes;
- how a call that is 128 MB away is reached;
- how a shared library's function gets called from an executable that was compiled without knowing its address.

A Principal engineer reads `readelf -l` the way an application developer reads a stack trace. The program headers *are* the contract with the flash programmer, the bootloader, and the dynamic loader.

---

## 1. First-Principles Mechanics

### 1.1 Two views of one file: sections vs. segments

An ELF file has two indexes over the same bytes:

| View | Table | Consumer | Granularity |
|---|---|---|---|
| **Linking view** | Section header table (`readelf -S`) | Linker, debugger, `objcopy`, `nm` | `.text`, `.data`, `.bss`, `.rodata`, `.symtab`, `.rela.*`, debug sections |
| **Execution view** | Program header table (`readelf -l`) | Loader: flash programmer, ROM bootloader, Linux `execve`, `ld.so` | `PT_LOAD` segments (and `PT_DYNAMIC`, `PT_INTERP`, `PT_TLS`, `PT_GNU_STACK`, `PT_GNU_RELRO`, `PT_ARM_EXIDX`) |

**Each `PT_LOAD` segment carries two addresses**:
- `p_vaddr`, the **VMA**: where the bytes are *used* at run time;
- `p_paddr`, the **LMA**: where the bytes are *stored* at load time.

On a hosted OS with an MMU they are equal and `p_paddr` is ignored. On a microcontroller **they differ for every RAM-resident initialized section**, and that difference is what `crt0` (File 02) exists to undo.

The firmware below was built from the File 02 sources: a C `Reset_Handler`, a vector table, `.data`, `.bss`, `.noinit`, an ITCM `.ramfunc`, and a constructor. It was linked with this file's linker script (§1.6):

```text
$ ld.lld -T fw_min.ld --gc-sections -z max-page-size=4 -Map fw_min.map -o fw_min.elf startup_min.o main_min.o
```

**`readelf -S -l fw_min.elf` (verified):**

```text
There are 15 section headers, starting at offset 0xaa4

Section Headers:
  [Nr] Name              Type            Addr     Off    Size   ES Flg Lk Inf Al
  [ 0]                   NULL            00000000 000000 000000 00      0   0  0
  [ 1] .isr_vector       PROGBITS        08000000 0001b4 000040 00   A  0   0  4
  [ 2] .text             PROGBITS        08000040 0001f8 0002c4 00  AX  0   0  8
  [ 3] .ARM.exidx        ARM_EXIDX       08000304 0004bc 000010 00  AL  5   0  4
  [ 4] .init_array       INIT_ARRAY      08000314 0004cc 000004 00  WA  0   0  4
  [ 5] .ramfunc          PROGBITS        00000000 0004d0 000008 00  AX  0   0  8
  [ 6] .data             PROGBITS        20000000 0004d8 000010 00  WA  0   0  4
  [ 7] .bss              NOBITS          20000010 0004e8 00003c 00  WA  0   0  4
  [ 8] .noinit           NOBITS          2000004c 0004e8 000004 00  WA  0   0  4
  [ 9] .stack            NOBITS          20000050 0004e8 001000 00  WA  0   0  1
  [10] .comment          PROGBITS        00000000 0004e8 000029 01  MS  0   0  1
  [11] .ARM.attributes   ARM_ATTRIBUTES  00000000 000511 000047 00      0   0  1
  [12] .symtab           SYMTAB          00000000 000558 0002c0 10     14  13  4
  [13] .shstrtab         STRTAB          00000000 000818 000080 00      0   0  1
  [14] .strtab           STRTAB          00000000 000898 00020b 00      0   0  1

Program Headers:
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  LOAD           0x0001b4 0x08000000 0x08000000 0x00040 0x00040 R   0x4
  LOAD           0x0001f8 0x08000040 0x08000040 0x002c4 0x002c4 R E 0x8
  LOAD           0x0004bc 0x08000304 0x08000304 0x00010 0x00010 R   0x4
  LOAD           0x0004cc 0x08000314 0x08000314 0x00004 0x00004 RW  0x4
  LOAD           0x0004d0 0x00000000 0x08000318 0x00008 0x00008 R E 0x8
  LOAD           0x0004d8 0x20000000 0x08000320 0x00010 0x00010 RW  0x4
  LOAD           0x0004e8 0x20000010 0x20000010 0x00000 0x01040 RW  0x4
  GNU_RELRO      0x0004cc 0x08000314 0x08000314 0x00004 0x00004 R   0x1
  GNU_STACK      0x000000 0x00000000 0x00000000 0x00000 0x00000 RW  0x0
  EXIDX          0x0004bc 0x08000304 0x08000304 0x00010 0x00010 R   0x4
```

How to read it like a firmware lead:

- **Segment 4 (`.ramfunc`):** `VirtAddr 0x00000000` (ITCM, where it *runs*), `PhysAddr 0x08000318` (flash, where it is *stored*). The flash programmer writes 8 bytes at `0x08000318`. `crt0` copies them to `0x00000000`.
- **Segment 5 (`.data`):** `VirtAddr 0x20000000` (SRAM), `PhysAddr 0x08000320` (flash). This is the same story.
- **Segment 6:** `FileSiz 0`, `MemSiz 0x1040`. That is `.bss` + `.noinit` + `.stack`: RAM that *exists* but has **no bytes in the image**. Its `PhysAddr` is in RAM, and that's harmless because there is nothing to write.
- **Section types tell you what costs flash.** `PROGBITS` has file contents. `NOBITS` occupies memory only. `.bss` costs zero flash; `.data` costs its size in **both** flash and RAM. This is why `size` reports `text + data` as flash usage and `data + bss` as RAM usage.
- **Flags:** `A` (alloc: occupies memory at run time), `W` (writable), `X` (executable), `L` (link order: `.ARM.exidx` entries follow their `.text`, whose index is in `Lk` = 5). Non-`A` sections (`.comment`, `.symtab`, debug sections) never reach the device.
- **`GNU_RELRO`** appeared because LLD defaults to `-z relro`, which is meaningless without a dynamic loader. Pass `-z norelro` for bare-metal images.
- **`-z max-page-size=4`.** Without it, the first link of this firmware padded segments to **64 KB file alignment** and produced a 198 KB ELF for a 1 KB program. That is harmless for `objcopy` (which uses addresses, not file offsets), but noisy. With it, the file is 2.7 KB.

The entry point is `0x8000049`. The **low bit is the Thumb bit**: `Reset_Handler` lives at `0x08000048`, and every Thumb function symbol and vector-table entry carries bit 0 = 1. A vector entry with bit 0 clear makes the core attempt ARM state, which M-profile doesn't have: a UsageFault with `INVSTATE`, escalated to a HardFault at reset (lockup).

### 1.2 From ELF to flash bytes

| Format | Produced by | Notes |
|---|---|---|
| ELF | linker | Programmers like pyOCD, OpenOCD and J-Link read `PT_LOAD` segments and write each one to its **LMA** (`p_paddr`). Debuggers that load *sections* use the section LMA ⚠ verify per tool |
| Raw binary | `objcopy -O binary` | One contiguous blob from the lowest to the highest LMA. Gaps are filled with zeros, so an LMA accidentally in RAM (0x2000_0000) next to flash (0x0800_0000) yields a **~400 MB** file. That size is the cheapest detector of the §2.1 bug |
| Intel HEX / S-record | `objcopy -O ihex/srec` | Address-tagged records; sparse regions are fine |

**The image is a list of `(LMA, bytes)` pairs. Nothing else survives power-off.** Every RAM-resident initialized byte must have an LMA inside non-volatile memory, and code at reset must move it.

### 1.3 Symbols: the linker's address book

**Symbol table, sorted by address (verified, capstone/pyelftools helper):**

```text
  0x00000000     0 NOTYPE __ramfunc_start__
  0x00000001     8 FUNC   ram_mix
  0x00000008     0 NOTYPE __ramfunc_end__
  0x00001000     0 NOTYPE __stack_size
  0x08000041     2 FUNC   Default_Handler
  0x08000041     2 FUNC   NMI_Handler
  0x08000041     2 FUNC   HardFault_Handler
  0x08000041     2 FUNC   MemManage_Handler
  0x08000041     2 FUNC   BusFault_Handler
  0x08000041     2 FUNC   UsageFault_Handler
  0x08000041     2 FUNC   SVC_Handler
  0x08000041     2 FUNC   PendSV_Handler
  0x08000041     2 FUNC   SysTick_Handler
  0x08000049   516 FUNC   Reset_Handler
  0x08000251    22 FUNC   early_ctor
  0x08000269     2 FUNC   test_done
  0x08000271   136 FUNC   main
  0x080002F9    10 FUNC   __Thumbv7ABSLongThunk_ram_mix
  0x08000314     0 NOTYPE __init_array_start
  0x08000318     0 NOTYPE __ramfunc_load__
  0x08000318     0 NOTYPE __init_array_end
  0x08000320     0 NOTYPE __data_load__
  0x20000000     0 NOTYPE __data_start__
  0x20000010     0 NOTYPE __data_end__
  0x20000010     0 NOTYPE __bss_start__
  0x2000004C     0 NOTYPE __bss_end__
  0x20000050     0 NOTYPE __stack_limit
  0x20001050     0 NOTYPE __stack_top
```

Observations:

- **Weak aliases collapse.** Eight exception handlers share `Default_Handler`'s address, which is the `__attribute__((weak, alias("Default_Handler")))` pattern. A strong definition anywhere in the link replaces one of them, with no `#ifdef`.
- **Linker-defined symbols are addresses, not objects.** `__stack_size` is an *absolute* value (`0x1000`) that only looks like an address. `__data_load__` is `LOADADDR(.data)`. In C they must be declared as `extern uint32_t sym[];` and compared as integers (Folder 01, File 01 §3.3).
- **`ram_mix` is at `0x00000001`.** That is ITCM address 0 with the Thumb bit. A null-pointer function call on this part would execute `ram_mix`. That is a real hazard of putting code at address 0 (§3).
- **`__Thumbv7ABSLongThunk_ram_mix`** is a function the *linker* synthesized (§1.5).

### 1.4 Relocations: the fix-up list

A relocatable object (`ET_REL`) has holes wherever an address is unknown at compile time. Each hole has a relocation record `(offset, type, symbol, addend)` telling the linker how to compute and encode the final value. AArch32 ELF uses **REL** (the addend is stored *in the instruction bits*). AArch64 uses **RELA** (an explicit addend field).

**Relocations in the Cortex-M7 object `main_min.o` (verified; one line per distinct type):**

```text
00000000  0000062a R_ARM_PREL31      00000000 .ramfunc
00000000  00000326 R_ARM_TARGET1     00000001 early_ctor
00000058  00000c0a R_ARM_THM_CALL    00000001 ram_mix
00000084  00000d0a R_ARM_THM_CALL    00000001 test_done
0000000c  00001030 R_ARM_THM_MOVT_AB 00000000 g_table
```

| Type (code) | Meaning | Where it appears |
|---|---|---|
| `R_ARM_THM_CALL` (10) | 25-bit PC-relative `BL`, range **±16 MB** | Every direct call |
| `R_ARM_THM_MOVW_ABS_NC` (47) / `R_ARM_THM_MOVT_ABS` (48) | Low/high 16 bits of an absolute address into `MOVW`/`MOVT` | Address materialization (`movw r0, :lower16:g_table`). The dump truncates the name to `R_ARM_THM_MOVT_AB` |
| `R_ARM_PREL31` (42) | 31-bit place-relative offset | `.ARM.exidx` unwind entries pointing at their functions |
| `R_ARM_TARGET1` (38) | Platform-defined: `ABS32` on bare metal | `.init_array` entries |
| `R_ARM_ABS32` (2) | Plain 32-bit address | Data words: vector-table entries, pointer initializers |

**AArch64 `app.c` compiled `-fno-pic` vs `-fPIC` (verified; full names restored from the numeric codes that pyelftools truncates):**

```text
-fno-pic:
00000000000c  00070000011b R_AARCH64_CALL26              foo + 0          (283)
000000000010  000800000113 R_AARCH64_ADR_PREL_PG_HI21    foo_counter + 0  (275)
000000000014  00080000011d R_AARCH64_LDST32_ABS_LO12_NC  foo_counter + 0  (285)
00000000001c  000200000105 R_AARCH64_PREL32              .text + 0        (261)

-fPIC:
00000000000c  000a0000011b R_AARCH64_CALL26              foo + 0          (283)
000000000010  000b00000137 R_AARCH64_ADR_GOT_PAGE        foo_counter + 0  (311)
000000000014  000b00000138 R_AARCH64_LD64_GOT_LO12_NC    foo_counter + 0  (312)
00000000001c  000500000105 R_AARCH64_PREL32              .text + 0        (261)
```

- **Non-PIC data access:** `ADRP` takes the 4 KB page of the symbol, PC-relative, ±4 GB (`ADR_PREL_PG_HI21`). A load then adds the low 12 bits (`LDST32_ABS_LO12_NC`). That is two instructions, no memory indirection, and position-dependent only at page granularity.
- **PIC data access** goes through the **GOT**: `ADRP` to the GOT entry's page, then `LDR` of the *address* of `foo_counter` (`LD64_GOT_LO12_NC`), then a third instruction to load the value. One extra dependent load per access.
- **Calls** are `CALL26` (±128 MB) either way. If the target ends up in a shared object, the linker redirects the call to a **PLT stub** (§1.5).

### 1.5 Range extension: thunks/veneers, and the PLT

#### 1.5.1 Long-branch thunks: FLASH → ITCM is 128 MB

`ram_mix` lives in ITCM at `0x0000_0000`. `main` lives in flash at `0x0800_0271`. The gap is 128 MB, beyond Thumb `BL`'s ±16 MB. The compiler doesn't know this, since it emitted an ordinary `R_ARM_THM_CALL`. **The linker fixed it**.

**Disassembly of the linked image (verified, capstone):**

```asm
main:
  ...
  080002c0:  movw     r1, #0xc0de
  080002c4:  movt     r1, #0xc0de
  080002c8:  bl       #0x80002f8
  080002cc:  str      r0, [r4, #8]
  ...
__Thumbv7ABSLongThunk_ram_mix:
  080002f8:  movw     ip, #1
  080002fc:  movt     ip, #0
  08000300:  bx       ip
ram_mix:
  00000000:  eors     r0, r1
  00000002:  add.w    r0, r0, #0x5a5a5a5a
  00000006:  bx       lr
```

The `bl` goes to a 10-byte **thunk** (GNU ld calls these *veneers*). The thunk loads the absolute address `0x00000001` (Thumb bit set) into `ip` (= `r12`, which AAPCS32 reserves for exactly this) and does `bx ip`. Consequences:

- `r12` is clobbered between caller and callee. Hand-written assembly must never pass a value in `r12` across a call that might be thunked. On AArch64, the same rule applies to `x16`/`x17`.
- Each thunk adds 3 instructions and a pipeline flush per call. Hot ITCM functions called from flash in a tight loop pay this every time. Either call them from other ITCM code, or mark the call site `__attribute__((long_call))` (GCC/Clang ARM), which makes the compiler materialize the address itself and lets it schedule the load.
- The thunk lives in flash, inside `.text` (`<internal>:(.text.thunk)` in the map file, §1.7). It isn't covered by any `ASSERT` you wrote about `.ramfunc`.

#### 1.5.2 The PLT and GOT in a real AArch64 Linux executable

```c
/* libfoo.c */                                   /* app.c */
int foo_counter = 7;                              extern int foo(int);
int foo(int x);                                   extern int foo_counter;
int foo(int x) { return x + foo_counter++; }      int main(void) { return foo(3) + foo_counter; }
```

Build (verified):

```text
zig cc -target aarch64-linux-gnu -O2 -fPIC -shared -Wl,-soname,libfoo.so libfoo.c -o libfoo.so
zig cc -target aarch64-linux-gnu -O2 -fPIC -c app.c -o app_pic.o
zig cc -target aarch64-linux-gnu -O2 -fPIE -pie app_pic.o -L. -lfoo -o app_pie
```

**`readelf -h -r -d -S app_pie` (verified; relevant lines):**

```text
  Type:                              DYN (Position-Independent Executable file)
Relocation section '.rela.dyn' at offset 0x3f0 contains 4 entries:
000000020790  000000000403 R_AARCH64_RELATIVE                       1052c
000000020798  000000000403 R_AARCH64_RELATIVE                       10554
0000000207a0  000000000403 R_AARCH64_RELATIVE                       105c8
0000000207a8  000400000401 R_AARCH64_GLOB_DAT   0000000000000000 foo_counter + 0
Relocation section '.rela.plt' at offset 0x450 contains 3 entries:
0000000207c8  000100000402 R_AARCH64_JUMP_SLOT  0000000000000000 __libc_start_main@GLIBC_2.17 + 0
0000000207d0  000200000402 R_AARCH64_JUMP_SLOT  0000000000000000 abort@GLIBC_2.17 + 0
0000000207d8  000300000402 R_AARCH64_JUMP_SLOT  0000000000000000 foo + 0
 0x0000000000000001 (NEEDED)             Shared library: [libfoo.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x000000000000001e (FLAGS)              BIND_NOW
 0x000000006ffffffb (FLAGS_1)            Flags: NOW PIE
 0x000000006ffffff9 (RELACOUNT)          3
 0x0000000000000017 (JMPREL)             0x450
 0x0000000000000002 (PLTRELSZ)           72 (bytes)
 0x0000000000000003 (PLTGOT)             0x207b0
 0x0000000000000014 (PLTREL)             RELA
  [13] .text             PROGBITS         00000000000104f4  000004f4
  [14] .plt              PROGBITS         00000000000105d0  000005d0
  [15] .dynamic          DYNAMIC          0000000000020620  00000620
  [16] .got              PROGBITS         0000000000020790  00000790
  [17] .got.plt          PROGBITS         00000000000207b0  000007b0
```

**Disassembly of `main` and `.plt` (verified, capstone):**

```asm
main:
  0001052c:  stp      x29, x30, [sp, #-0x10]!
  00010530:  mov      x29, sp
  00010534:  mov      w0, #3
  00010538:  bl       #0x10610
  0001053c:  adrp     x8, #0x20000
  00010540:  ldr      x8, [x8, #0x7a8]
  00010544:  ldr      w8, [x8]
  00010548:  add      w0, w8, w0
  0001054c:  ldp      x29, x30, [sp], #0x10
  00010550:  ret
.plt:
  000105d0:  stp      x16, x30, [sp, #-0x10]!
  000105d4:  adrp     x16, #0x20000
  000105d8:  ldr      x17, [x16, #0x7c0]
  000105dc:  add      x16, x16, #0x7c0
  000105e0:  br       x17
  000105e4:  nop
  000105e8:  nop
  000105ec:  nop
  000105f0:  adrp     x16, #0x20000
  000105f4:  ldr      x17, [x16, #0x7c8]
  000105f8:  add      x16, x16, #0x7c8
  000105fc:  br       x17
  00010600:  adrp     x16, #0x20000
  00010604:  ldr      x17, [x16, #0x7d0]
  00010608:  add      x16, x16, #0x7d0
  0001060c:  br       x17
  00010610:  adrp     x16, #0x20000
  00010614:  ldr      x17, [x16, #0x7d8]
  00010618:  add      x16, x16, #0x7d8
  0001061c:  br       x17
```

Tracing one call:

1. `main` does `bl 0x10610`. That is not `foo`. It is the **PLT stub for `foo`**, the fourth 16-byte entry.
2. The stub loads `x17 = *(0x207d8)`, the `.got.plt` slot that `R_AARCH64_JUMP_SLOT foo` targets, and branches to it. **`x16`/`x17` are the AAPCS64 IP0/IP1 scratch registers precisely so PLT stubs and veneers can clobber them.** BTI-enabled PLTs land on `bti c` pads through `br x16/x17` (Folder 01, File 03).
3. The first entry (`stp x16, x30` … `br x17`) is **PLT0**, the lazy-binding trampoline into the dynamic linker's resolver. With **`BIND_NOW`** (zig's default, and the security-hardened default on most distributions), `ld.so` resolves every `JUMP_SLOT` before `main` runs. Then the GOT is made read-only (**full RELRO**), so an attacker can't overwrite `.got.plt` to hijack calls.
4. `foo_counter` is *data* in the library. `main` loads its address from the **GOT** (`ldr x8, [x8, #0x7a8]`: the `R_AARCH64_GLOB_DAT` slot), then loads the value. A non-PIE executable would instead use a **copy relocation** (`R_AARCH64_COPY`): the loader copies the variable into the executable's `.bss`, and the library is redirected to that copy. That freezes the variable's size into the executable's ABI.
5. **`R_AARCH64_RELATIVE`** entries are "base + addend" fix-ups for absolute pointers in a PIE: function-pointer tables, `.init_array`, `.dynamic`. They cost load time proportional to their count. Linux kernels and large binaries use RELR packing (`-z pack-relative-relocs`) to shrink them.

**Interposition inside the library.** `foo` reads its *own* `foo_counter` through the GOT (verified: `libfoo.so` carries `R_AARCH64_GLOB_DAT foo_counter`):

```asm
foo:
  0001033c:  adrp     x8, #0x20000
  00010340:  ldr      x8, [x8, #0x428]
  00010344:  ldr      w9, [x8]
  00010348:  add      w10, w9, #1
  0001034c:  add      w0, w9, w0
  00010350:  str      w10, [x8]
  00010354:  ret
```

ELF's default visibility makes every exported symbol **interposable**: an earlier-loaded object, or the executable via a copy relocation, may provide `foo_counter`, so the library can't assume its own definition is the one used. With `-fvisibility=hidden` (verified), the access becomes direct: `R_AARCH64_ADR_PREL_PG_HI21` + `R_AARCH64_LDST32_ABS_LO12_NC`, with no GOT. Production shared libraries:

- build with `-fvisibility=hidden`;
- export an explicit API with `__attribute__((visibility("default")))`;
- add `-fno-semantic-interposition` (GCC; Clang defaults to `-fhalf-no-semantic-interposition` for `-fPIC`, visible in the driver output in Folder 01).

#### 1.5.3 Kernel modules: relocations at `insmod` time

A Linux kernel module is an `ET_REL` object. `kernel/module/` applies its relocations itself when loading. On arm64, modules are placed in a 128 MB window near the kernel. Calls that might exceed `CALL26` range go through **module PLTs** (`arch/arm64/kernel/module-plts.c`), which are veneers the kernel's loader generates. That's why unusual module relocation types fail with `unknown relocation` at load time instead of link time.

### 1.6 The GNU LD script language, element by element

This is the complete script used for every verified listing in this file:

```ld
/* fw_min.ld - Cortex-M7: execute-in-place FLASH, zero-wait ITCM, SRAM.
 * Every output section states WHERE IT RUNS (VMA, "> REGION") and, if that is
 * RAM, WHERE ITS BYTES ARE STORED (LMA, "AT > FLASH"). */
ENTRY(Reset_Handler)

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 512K
  ITCM  (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
  SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}

__stack_size = 0x1000;

SECTIONS
{
  /* Vector table first: VTOR needs it aligned to the next power of two
   * >= table size (minimum 128 bytes on ARMv7-M). */
  .isr_vector ORIGIN(FLASH) :
  {
    KEEP(*(.isr_vector))
  } > FLASH

  .text :
  {
    *(.text .text.*)
    *(.rodata .rodata.*)
    . = ALIGN(4);
  } > FLASH

  .ARM.exidx :
  {
    *(.ARM.exidx* .gnu.linkonce.armexidx.*)
  } > FLASH

  .init_array :
  {
    . = ALIGN(4);
    __init_array_start = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    KEEP(*(.init_array))
    __init_array_end = .;
  } > FLASH

  /* Runs from ITCM (VMA 0x0000_xxxx), stored in FLASH (LMA 0x080x_xxxx). */
  .ramfunc :
  {
    . = ALIGN(4);
    __ramfunc_start__ = .;
    *(.ramfunc .ramfunc.*)
    . = ALIGN(4);
    __ramfunc_end__ = .;
  } > ITCM AT > FLASH
  __ramfunc_load__ = LOADADDR(.ramfunc);

  /* Initialized data: runs from SRAM, initial image stored in FLASH. */
  .data :
  {
    . = ALIGN(4);
    __data_start__ = .;
    *(.data .data.*)
    . = ALIGN(4);
    __data_end__ = .;
  } > SRAM AT > FLASH
  __data_load__ = LOADADDR(.data);

  /* Zero-initialized: occupies SRAM, occupies NO bytes in the image. */
  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    __bss_start__ = .;
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end__ = .;
  } > SRAM

  /* Survives warm resets: neither loaded nor zeroed by crt0. */
  .noinit (NOLOAD) :
  {
    . = ALIGN(4);
    *(.noinit .noinit.*)
  } > SRAM

  .stack (NOLOAD) :
  {
    . = ALIGN(8);
    __stack_limit = .;
    . = . + __stack_size;
    . = ALIGN(8);
    __stack_top = .;
  } > SRAM
}

ASSERT(__stack_top <= ORIGIN(SRAM) + LENGTH(SRAM), "SRAM overflow: .data + .bss + .noinit + stack")
ASSERT(__ramfunc_end__ <= ORIGIN(ITCM) + LENGTH(ITCM), "ITCM overflow")
ASSERT((ADDR(.isr_vector) & 0x7F) == 0, "vector table must be 128-byte aligned for VTOR")
```

| Construct | Semantics | Production notes |
|---|---|---|
| `ENTRY(sym)` | Sets `e_entry` | Bare-metal hardware ignores it (the core reads the vector table), but debuggers use it, and `--gc-sections` treats it as a root |
| `MEMORY { NAME (attr) : ORIGIN, LENGTH }` | Declares regions. Attributes (`r w x a i l !`) steer **orphan** sections | A region overflow is a *link error*: the cheapest memory budget check there is |
| `.sec [addr] : { … } > VMA_REGION AT > LMA_REGION` | Output section; `>` sets the run address, `AT >` the load address | Omitting `AT >` makes LMA = VMA: the §2.1 bug |
| `LOADADDR(.sec)`, `ADDR(.sec)`, `SIZEOF(.sec)` | LMA, VMA and size of an output section | What crt0 copies |
| `.` (location counter), `ALIGN(n)` | Current VMA within the output section | `. = ALIGN(8)` before `__stack_top` gives the AAPCS 8-byte SP alignment |
| `*(.text .text.*)` | Input-section wildcards, in order | With `-ffunction-sections -fdata-sections`, each function or object is its own input section, so `--gc-sections` can drop unreferenced ones |
| `KEEP(...)` | Exempt from garbage collection | **Mandatory** for the vector table and `.init_array`. Nothing references them by symbol, so without `KEEP` `--gc-sections` deletes the vector table and the part never boots |
| `SORT_BY_INIT_PRIORITY` | Orders `.init_array.NNNNN` by priority | `__attribute__((constructor(101)))` ordering |
| `(NOLOAD)` | Section is allocated but not loaded (becomes `NOBITS`) | `.noinit` arrives as **PROGBITS** from the compiler (verified in `main_min.o`: `[17] .noinit PROGBITS`). Without `NOLOAD`, a debugger `load` writes zeros into it and the "survives reset" property is broken in every debug session |
| `/DISCARD/ : { *(.pattern) }` | Drop input sections | E.g. `*(.ARM.exidx*)` in C-only firmware without unwinding. Keep it if the crash handler unwinds through EHABI |
| `PROVIDE(sym = expr)` | Define only if not otherwise defined | Weak defaults such as heap bounds |
| `ASSERT(expr, "msg")` | Link-time invariant | Turns layout assumptions into build failures. Use it for every budget and alignment rule |
| `OVERLAY` | Multiple sections share one VMA | Legacy code paging on MMU-less parts; rare today |
| Orphan sections | Input sections no rule matched | LLD and GNU ld place them by heuristics next to similar sections. **Always** catch them with `--orphan-handling=error` (LLD and GNU ld 2.26+; ⚠ verify) |

### 1.7 Reading the map file

**`fw_min.map` (verified, LLD format, first 48 lines):**

```text
     VMA      LMA     Size Align Out     In      Symbol
       0        0        0     1 __stack_size = 0x1000
 8000000  8000000       40     4 .isr_vector
 8000000  8000000       40     4         startup_min.o:(.isr_vector)
 8000000  8000000       40     1                 g_vector_table
 8000040  8000040      2c4     8 .text
 8000040  8000040        2     8         startup_min.o:(.text.Default_Handler)
 8000040  8000040        0     1                 $t
 8000041  8000041        2     1                 Default_Handler
 8000041  8000041        2     1                 NMI_Handler
 8000041  8000041        2     1                 HardFault_Handler
 8000041  8000041        2     1                 MemManage_Handler
 8000041  8000041        2     1                 BusFault_Handler
 8000041  8000041        2     1                 UsageFault_Handler
 8000041  8000041        2     1                 SVC_Handler
 8000041  8000041        2     1                 PendSV_Handler
 8000041  8000041        2     1                 SysTick_Handler
 8000048  8000048      204     8         startup_min.o:(.text.Reset_Handler)
 8000048  8000048        0     1                 $t
 8000049  8000049      204     1                 Reset_Handler
 8000250  8000250       16     8         main_min.o:(.text.early_ctor)
 8000250  8000250        0     1                 $t
 8000251  8000251       16     1                 early_ctor
 8000268  8000268        2     8         main_min.o:(.text.test_done)
 8000268  8000268        0     1                 $t
 8000269  8000269        2     1                 test_done
 8000270  8000270       88     8         main_min.o:(.text.main)
 8000270  8000270        0     1                 $t
 8000271  8000271       88     1                 main
 80002f8  80002f8        a     4         <internal>:(.text.thunk)
 8000302  8000302        2     1         . = ALIGN(4)
 8000304  8000304       10     4 .ARM.exidx
 8000304  8000304       10     4         <internal>:(.ARM.exidx)
 8000314  8000314        4     4 .init_array
 8000314  8000314        0     1         . = ALIGN(4)
 8000314  8000314        0     1         __init_array_start = .
 8000314  8000314        4     4         main_min.o:(.init_array)
 8000318  8000318        0     1         __init_array_end = .
       0  8000318        8     8 .ramfunc
       0  8000318        0     1         . = ALIGN(4)
       0  8000318        0     1         __ramfunc_start__ = .
       0  8000318        8     8         main_min.o:(.ramfunc)
       0  8000318        0     1                 $t
       1  8000319        8     1                 ram_mix
       8  8000320        0     1         . = ALIGN(4)
       8  8000320        0     1         __ramfunc_end__ = .
       8  8000320        0     1 __ramfunc_load__ = LOADADDR(.ramfunc)
20000000  8000320       10     4 .data
```

A map file answers the questions that matter in an incident: which object contributed which bytes, where a section's VMA and LMA diverge, what the linker inserted on its own (`<internal>:(.text.thunk)`), and how much alignment padding the layout costs. `$t` and `$a`/`$d` are **ARM mapping symbols**, marking the start of Thumb code, ARM code, and literal data. Disassemblers use them so they don't decode literal pools as instructions.

A related trap that this build demonstrated: the first attempt had `.init_array` **empty**. Clang's GlobalOpt had evaluated the constructor (`ctor_ran = 0xC7`) *at compile time* and folded the value into `main`, so no constructor entry existed. A constructor that touches hardware (it now reads `SCB->CPUID`) can't be folded. If you ever see an empty `.init_array` where you expected entries, check whether the constructors became constants before you blame `KEEP`.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way: an LMA-less `.data` that works under the debugger

```ld
  .data :
  {
    . = ALIGN(4);
    __data_start__ = .;
    *(.data .data.*)
    . = ALIGN(4);
    __data_end__ = .;
  } > SRAM                      /* BUG: no "AT > FLASH" -> LMA == VMA == 0x2000_0000 */
  __data_load__ = LOADADDR(.data);
```

**`readelf -l` of that build (verified):**

```text
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  LOAD           0x000194 0x08000000 0x08000000 0x00040 0x00040 R   0x4
  LOAD           0x0001d8 0x08000040 0x08000040 0x002c4 0x002c4 R E 0x8
  LOAD           0x00049c 0x08000304 0x08000304 0x00010 0x00010 R   0x4
  LOAD           0x0004ac 0x08000314 0x08000314 0x00004 0x00004 RW  0x4
  LOAD           0x0004b0 0x00000000 0x08000318 0x00008 0x00008 R E 0x8
  LOAD           0x0004b8 0x20000000 0x20000000 0x00010 0x01050 RW  0x4
```

The `.data` segment now has **`PhysAddr 0x20000000`**: its initial values are to be "programmed" into RAM. Executed in the emulator two ways (verified, Unicorn Cortex-M7, RAM pre-filled with `0xA5`):

```text
## no-AT image, debugger-style load (all segments written at LMA)
run 1: reset SP=0x20001050 PC=0x08000049 -> stopped at 0x08000268 (test_done)
  g_result@0x20000034: 0xAAAAAAAA 0x00000001 0xC4CEC4CE
  g_table@0x20000000: 0x11111111 0x22222222 0x33333333 0x44444444
## no-AT image, cold boot (flash only)
  cold boot: segment for 0x20000000 has LMA 0x20000000 outside FLASH -> lost at power-off
run 1: reset SP=0x20001050 PC=0x08000049 -> stopped at 0x08000268 (test_done)
  g_result@0x20000034: 0x96969694 0x00000001 0xB0A2B0A4
  g_table@0x20000000: 0xA5A5A5A5 0xA5A5A5A5 0xA5A5A5A5 0xA5A5A5A5
## correct image, cold boot
run 1: reset SP=0x20001050 PC=0x08000049 -> stopped at 0x08000268 (test_done)
  g_result@0x20000034: 0xAAAAAAAA 0x00000001 0xC4CEC4CE
  g_table@0x20000000: 0x11111111 0x22222222 0x33333333 0x44444444
```

This is the most expensive kind of firmware bug: **it passes every bench test**. The debugger writes `g_table`'s initial values straight into SRAM during `load`, and crt0's copy loop copies `.data` onto itself (LMA == VMA). After a power cycle in the field, SRAM holds whatever the cells powered up with, and every initialized global is garbage. The `objcopy -O binary` output would also have grown to roughly 400 MB, because the image now spans from `0x0800_0000` to `0x2000_0010`. That size is the alarm, if anyone looks.

**Guards (all mechanical):**

1. `ASSERT(LOADADDR(.data) >= ORIGIN(FLASH) && LOADADDR(.data) < ORIGIN(FLASH) + LENGTH(FLASH), ".data LMA must be in FLASH")`.
2. A CI step that fails if any `PT_LOAD` with `FileSiz > 0` has a `p_paddr` outside non-volatile regions. This is a ten-line pyelftools script, the same logic as the emulator's `--flash-only` check.
3. Release qualification boots **from a power cycle with the debugger detached**, never only through `load`.

### 2.2 The Silicon-Hardened Production Way

`fw_min.ld` in §1.6 is the hardened pattern, and Folder 07 File 01 extends it to five regions (ITCM, DTCM, AXI SRAM, D2 SRAM for DMA, backup SRAM). The rules it embodies:

| Rule | Mechanism in the script |
|---|---|
| Every initialized RAM section has a flash LMA | `> RAM AT > FLASH`, plus the LMA `ASSERT` above |
| crt0 never hard-codes addresses | `__data_load__ = LOADADDR(.data)` etc., declared in C as `extern uint32_t sym[]` |
| The vector table survives `--gc-sections` and is VTOR-aligned | `KEEP(*(.isr_vector))` at `ORIGIN(FLASH)`, plus `ASSERT((ADDR(.isr_vector) & 0x7F) == 0)`. Tables with more than 32 entries need a larger power-of-two alignment (e.g. 512 bytes for 128 entries) |
| Budgets fail the build, not the board | `ASSERT(__stack_top <= ORIGIN(SRAM) + LENGTH(SRAM))`, region overflow errors |
| Persistent RAM is truly untouched | `.noinit (NOLOAD)`, not covered by the `.bss` zeroing symbols |
| The stack is explicit, aligned and bounded | `.stack (NOLOAD)` with `__stack_limit` for `MSPLIM` (v8-M) or an MPU guard (File 03) |
| No surprises | `--orphan-handling=error`, `-Map`, and a post-link segment audit |

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| Part doesn't boot at all; the debugger shows a HardFault/lockup at reset | Vector table garbage-collected (no `KEEP`), not at the boot address, or a reset vector without the Thumb bit (`INVSTATE`) | `readelf -S` (`.isr_vector` present, size > 0). `x/2wx 0x08000000` in GDB: word 0 must be a plausible SRAM top, word 1 odd |
| Works under the debugger, fails after a power cycle | LMA in RAM (§2.1), or `.noinit`/`.data` initialized by the debugger's `load` | Segment audit; GDB `compare-sections` checks target memory against the ELF |
| Globals have wrong initial values only in some builds | `.data` copy loop sized with the wrong symbols, or a crt0 that relies on library `memcpy` before it's usable (File 02) | Emulator run with RAM pre-filled (the `0xA5` technique) |
| Calling a RAM function crashes with `INVSTATE` or `IACCVIOL` | Function pointer lost the Thumb bit, or ITCM not yet copied when called (a constructor calling a `.ramfunc`), or an MPU XN on SRAM | Disassemble the thunk; check `__ramfunc_start__` contents after reset |
| Null-function-pointer call "works" | Code mapped at address 0 (ITCM), e.g. `ram_mix` at `0x00000001` here | Reserve the first ITCM bytes (place a trap stub or leave 32 bytes no-access) so a null call faults |
| `region 'FLASH' overflowed by N bytes` | Real growth, or `.data` counted twice | `size -A`, sorted symbol sizes (`nm -S --size-sort`), puncover/bloaty |
| `undefined symbol: __aeabi_memcpy4` | Compiler-generated runtime call in a libc-less link (File 02 §1.4 shows when crt0 produces these) | Provide the helper, or keep crt0 loops `volatile` |

**TRACE32:** `Data.LOAD.Elf fw.elf /NoCODE` loads symbols only, without rewriting flash. That's how you attach to a field unit without disturbing it. `sYmbol.List.SECtion` shows VMA and LMA per section. **GDB:** `info files` lists sections and their target addresses. `x/8wx &__data_load__` vs `x/8wx &__data_start__` compares the flash image of `.data` to the live RAM copy.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "What is the difference between a section and a segment, and what is an LMA?"

- **L5:** "Sections are for the linker, segments for the loader. LMA is where the section is loaded."
- **Why L5 fails on hardware:** It doesn't connect to the failure mode. On a microcontroller the *loader is the flash programmer*. It writes each `PT_LOAD` at `p_paddr`. A RAM-resident initialized section must have its `p_paddr` in flash, or its initial contents exist only in debug sessions (verified: cold boot gives `0xA5A5A5A5`). Conversely, `.bss` segments have `FileSiz 0` and cost no flash.
- **L7 defense:** Read `readelf -l` and explain each `LOAD` line's VMA/LMA/FileSiz/MemSiz (§1.1). State the crt0 contract: copy `[LOADADDR, +SIZEOF)` to `[ADDR, +SIZEOF)` and zero `NOBITS`. Name the guards: an LMA `ASSERT`, a post-link segment audit in CI, and cold-boot qualification.

### Q2 🔥 "Why does a call from flash to an ITCM function work even though `BL` only reaches ±16 MB?"

- **L5:** "The compiler uses a long call."
- **Why L5 fails:** The compiler didn't. It emitted a plain `R_ARM_THM_CALL`. **The linker** inserted `__Thumbv7ABSLongThunk_ram_mix` (`movw ip`/`movt ip`/`bx ip`, verified). That clobbers `r12`, costs three instructions plus a branch per call, and lives in flash, outside your `.ramfunc` accounting.
- **L7 defense:** Know thunks and veneers exist. Know that AAPCS reserves `r12` and `x16`/`x17` for them, and read the map file's `<internal>` entries. For hot paths: call ITCM code from ITCM code, or use `__attribute__((long_call))` so the compiler can hoist the address load. On AArch64, `CALL26` reaches ±128 MB, and the same thunk mechanism (and arm64 module PLTs) covers the rest.

### Q3 🔥 "Walk me through what happens when `main` calls `foo` from a shared library on AArch64 Linux."

- **L5:** "It goes through the PLT and GOT; the dynamic linker resolves it lazily."
- **Why L5 fails:** "Lazily" is usually false today. Hardened builds use `BIND_NOW` + full RELRO (verified `FLAGS BIND_NOW`, `FLAGS_1 NOW PIE`). All `JUMP_SLOT`s are resolved before `main`, then `.got` is made read-only. The L5 answer also skips the data path (`GLOB_DAT` vs copy relocations) and why the library itself indexes its own globals through the GOT.
- **L7 defense:** Trace it (§1.5.2):
  - `bl` → PLT stub (`adrp x16` / `ldr x17, [slot]` / `br x17`) → `foo`;
  - `x16`/`x17` are the IP registers by ABI design;
  - `JUMP_SLOT` relocations fill the `.got.plt` slots;
  - `RELATIVE` relocations fix absolute pointers in a PIE;
  - copy relocations freeze data-symbol sizes into the executable's ABI;
  - default visibility makes even internal accesses go through the GOT (verified), so `-fvisibility=hidden` plus an export list removes that.

  Mention `LD_BIND_NOW`, `-z now`, `-z relro`, and RELR packing for startup cost.

### Q4 ⚡ "Firmware boots on the bench but every unit returned from the field has corrupted calibration constants."

- **L5:** "Flash corruption; add CRC checks."
- **Why L5 fails:** The constants are in `.data` with an LMA in RAM (§2.1). The bench always boots through a debugger `load`, which writes RAM directly. A CRC over flash passes, because the constants were never *in* flash.
- **L7 defense:** `readelf -l`: `.data`'s `PhysAddr` is `0x2000_xxxx`. Fix with `AT > FLASH` plus `ASSERT`. Add the segment audit to CI and power-cycle qualification without a debugger. Put true calibration data in a dedicated flash/OTP section, read through a `const` struct with its own CRC and version field, not in `.data`.

### Q5 "Why does `--gc-sections` sometimes delete the vector table, and why doesn't it delete `main`?"

- **L5:** "Use `KEEP`."
- **Why L5 fails:** That's the fix, but not the mechanism. GC starts from roots: `ENTRY`, `KEEP` sections, and symbols marked `used` or exported. It keeps everything reachable through *relocations*. `main` is reachable via `Reset_Handler`'s call. Nothing *references* `.isr_vector` by relocation: the hardware reads it by address.
- **L7 defense:** Explain root-set reachability. `__attribute__((used))` keeps the object in the *compiler's* output, while `KEEP` keeps the section in the *linker's* output. Both are needed. Likewise `.init_array` and any table found by section-boundary symbols (`__start_SECNAME`/`__stop_SECNAME` linker magic for registration tables) need `KEEP`.

### Q6 🧊 "Your shared library is 15% slower than the same code linked statically. Why?"

- **L5:** "PLT overhead."
- **Why L5 fails:** Calls through the PLT cost a little. The bigger cost is that **every access to an exported global goes through the GOT** (one extra dependent load, verified in `foo`). Interposition also blocks inlining and constant propagation across exported functions. And `RELATIVE` relocation processing slows startup.
- **L7 defense:**
  - `-fvisibility=hidden` with explicit exports (verified: the GOT disappears);
  - `-fno-semantic-interposition` (GCC) or Clang's default `-fhalf-no-semantic-interposition`;
  - `-Bsymbolic-functions` where the ABI policy allows;
  - LTO;
  - measure with `perf` and compare instruction counts in the hot functions.

### Q7 "How do you prove at build time that the image fits and that the stack can't collide with `.bss`?"

- **L5:** "Check the map file before release."
- **Why L5 fails:** Manual checks don't scale and miss growth. A stack collision is a *run-time* property that layout alone can't prove.
- **L7 defense:**
  - Layout: `MEMORY` lengths give overflow errors, and `ASSERT`s cover every derived budget (`__stack_top <= end of SRAM`).
  - Stack depth: `-fstack-usage` and call-graph analysis give worst-case static stack (Folder 01, File 03) for every task and ISR nesting level.
  - Run time: an `MSPLIM`/`PSPLIM` stack limit (v8-M), or a no-access MPU guard region below the stack (File 03, verified encoder), so an overflow faults instead of corrupting `.bss`.
  - Telemetry: stack painting plus high-water reporting in the field.

### Q8 🧊 "What's in `.ARM.exidx`, and should firmware keep it?"

- **L5:** "It's for C++ exceptions; delete it in C firmware."
- **Why L5 fails:** It's the **EHABI unwind index**: `R_ARM_PREL31` entries (verified) mapping each function to its unwind instructions. A HardFault handler or `backtrace()` can use it to unwind accurately without frame pointers (Folder 01 File 03 §4.3). Discarding it saves 8 bytes per function and loses crash-dump quality.
- **L7 defense:** Keep it in builds whose crash handler unwinds, budget it explicitly, and discard it only with a decision record. Note the `L` (link-order) flag: entries must stay sorted with their `.text`. A custom script that reorders `.text` without `.ARM.exidx` breaks unwinding silently.

---

## 5. Invariants Checklist

- [ ] Every `PT_LOAD` with `FileSiz > 0` has `p_paddr` inside non-volatile memory (CI audit).
- [ ] Every RAM output section with contents is `> RAM AT > FLASH`, and its symbols come from `ADDR`/`LOADADDR`/`SIZEOF`.
- [ ] `KEEP` on `.isr_vector`, `.init_array`, `.fini_array` and every linker-set or registration table; `__attribute__((used))` on the objects.
- [ ] Vector table at the boot address, aligned for `VTOR`, with `ASSERT`; all entries Thumb-bit-correct.
- [ ] `.noinit`, `.stack` and heap are `NOLOAD`; `.noinit` excluded from `.bss` zeroing.
- [ ] `ASSERT`s for every region budget; `--orphan-handling=error`; `-Map` archived per build ID.
- [ ] `-z norelro`, `-z max-page-size=4` (or the GNU ld equivalent) for bare metal; no `.interp`/dynamic sections in firmware.
- [ ] Thunks and veneers accounted for: no values in `r12`/`x16`/`x17` across calls; hot RAM code called from RAM.
- [ ] Shared libraries: `-fvisibility=hidden` with an export list; `-z now -z relro`; RELR where supported.
- [ ] Release qualification includes a cold boot from power-off without a debugger.

## 6. References

1. System V ABI, *Generic ELF* (gABI) and the AMD64/AArch64 supplements; Arm IHI 0044 (AAELF32) and IHI 0056 (AAELF64) relocation tables.
2. GNU ld manual, *Linker Scripts* (MEMORY, SECTIONS, output-section LMA, `NOLOAD`, `KEEP`, `ASSERT`, orphan sections); LLD documentation, *Linker Script implementation notes* and `--orphan-handling`.
3. U. Drepper, *How To Write Shared Libraries*, 2011; I. L. Taylor, *Linkers* (20-part essay series, 2007).
4. Arm, *Exception Handling ABI for the Arm Architecture* (EHABI, IHI 0038).
5. Linux kernel: `kernel/module/main.c`, `arch/arm64/kernel/module.c`, `arch/arm64/kernel/module-plts.c`.
6. pyelftools (`readelf.py`), capstone and Unicorn project documentation (the tools used for verification here).
