# 03.4 · Archetype D: Embedded, Avionics and Edge Firmware (Verification, Bus Protocols, Hardware–Software Co-Design)

> **Folder:** `03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes` · file 4 of 4
> **Question this file answers:** I built safety-relevant firmware: an avionics data concentrator, an automotive ECU, an industrial controller, an edge device. How do I defend the bus protocol handling, the scheduling and timing analysis, the verification evidence (structural coverage, MC/DC) and the hardware–software split, in a room where "it passed the tests" is the weakest possible answer?
> **Composite exhibit:** "Flightline", a remote data concentrator (RDC) firmware rework for a regional-aircraft retrofit program. The numbers are placeholders. ⚠ Certification specifics are illustrative: real certification credit is agreed with the certification authority for each program.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L10 `flightline.c` | C11, freestanding-clean firmware core plus a host test harness | 1. ARINC 429 word encode/decode: bit-reversed label, SDI, two's-complement BNR data with sign at bit 29, SSM, odd parity (every single-bit flip detected).<br>2. The word-acceptance decision, with an MC/DC (unique-cause) checker comparing a decision-coverage test set with an N+1 MC/DC test set.<br>3. A cyclic-executive frame-budget check, before and after re-phasing.<br>4. An SPSC ISR→task ring with an explicit never-overwrite policy and an overflow counter. | [§12](#12-listing-and-output). Host build: `-std=c11 -O2 -Wall -Wextra -Werror -pedantic`. The firmware core also cross-compiles for Cortex-M7 (`thumb-freestanding-eabihf`, `-DFIRMWARE_ONLY`). |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, builds and runs the host harness, and compares the output with §12. It also cross-compiles the firmware-only build for a Cortex-M7 target with the same warnings-as-errors flags, and records the object size in the README. The program prints `verdict: OK` only if its 10 checks pass. Tellings and the ledger are checked by the Folder 01 tools. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

**Who this archetype fits.** Firmware and embedded engineers in avionics, automotive, medical, industrial, robotics and IoT edge devices. Typical résumé lines: "developed DO-178C Level B software", "ARINC 429 / CAN / SPI drivers", "achieved 100% MC/DC coverage", "reduced interrupt latency", "hardware/software co-design".

**Why it's dangerous in a deep dive.** The interviewers for these roles (often from NVIDIA, Apple or automotive and aerospace teams) probe three things that résumés routinely blur:
1. **What the verification evidence actually shows.** Coverage criteria, requirements traceability, and what "100%" was measured against.
2. **Timing.** WCET, scheduling, jitter, and the worst-case burst, not the average.
3. **The hardware–software boundary.** Who decided what lives in silicon, in an FPGA or in code, and why.

They know that safety-relevant work is reviewed by many people and certified by an authority. Ownership claims have to be precise (01.2), and claims about certification credit must be careful (⚠).

---

## 1. First principles: what interviewers assume about this archetype

### 1.1 The attack surface

| Claim | What they suspect | The probe | What survives |
|---|---|---|---|
| "100% coverage" | Statement or decision coverage presented as if it were MC/DC | "Which criterion, against which requirements?" | The criterion, the level that requires it, and an independence pair per condition (§4) |
| "Real-time" | Average-case timing | "Worst-case frame, worst-case burst?" | Per-frame budgets, WCET method, burst analysis (§5, §6) |
| "Lock-free ring buffer" | Works on the bench, races with DMA or caches | "Cortex-M7 with D-cache and DMA: what do you do?" | Ownership, barriers, cache maintenance or non-cacheable regions (Q3) |
| "Hardware/software co-design" | Implemented the hardware team's choice | "Who decided, on what data?" | A decision memo with measured alternatives (§7) |
| "DO-178C certified" | Worked on a certified program | "What was your role in the evidence?" | The specific artifacts you produced, and who signed (§2.3) |

### 1.2 The standards vocabulary (state it precisely)

- **DO-178C (RTCA, 2011)** assigns software levels A–E by the failure condition the software can contribute to. Structural coverage objectives scale with the level:
  - **Level A:** modified condition/decision coverage (MC/DC);
  - **Level B:** decision coverage;
  - **Level C:** statement coverage.

  Coverage analysis supplements requirements-based testing. It doesn't replace it.
- **DO-330** covers tool qualification. A tool whose output removes a verification step needs qualification before you can take credit for it.
- **MISRA C** ([misra.org.uk](https://misra.org.uk/)) is a widely used coding guideline set for critical C. Deviations are documented and justified.
- **The NASA MC/DC tutorial** (Hayhurst et al., NASA/TM-2001-210876, [PDF](https://shemesh.larc.nasa.gov/fm/papers/Hayhurst-2001-tm210876-MCDC.pdf)) is the standard practitioner's reference for MC/DC.
- **ARINC 429** is the long-standing avionics data bus: 32-bit words; a label in bits 1–8 (transmitted most-significant bit first, while the rest of the word goes least-significant bit first); SDI in bits 9–10; data in bits 11–29; SSM in bits 30–31; odd parity in bit 32. Speeds are 100 kbit/s (high) and 12.5 kbit/s (low).

---

## 2. The composite project: "Flightline" fact sheet

### 2.1 Before-state

- **The unit:** an RDC on a Cortex-M7 at 300 MHz. It collects 12 ARINC 429 receive channels (high speed) and 48 discrete inputs, and publishes validated parameters to the aircraft data network.
- **Interrupt load:**
  - v1 firmware took **one interrupt per received word**, and the ISR decoded, validated and queued it.
  - Theoretical maximum: 12 channels × 100,000 bit/s ÷ 36 bit-times per word (32 bits + a 4-bit gap) ≈ **33,333 words/s**.
  - At ~6 µs per ISR, that's ~**20% of CPU** at the maximum rate, with jitter that disturbed the cyclic executive.
- **Frame overrun:** minor frame 0 overran its 8,000 µs budget (8,600 µs), because every periodic task was phased at 0.
- **Field reports:** 3 "air-data stale" crew messages in 14 months on the fleet, none reproducible on the bench.
- **The retrofit program** added 4 channels and a new validity-monitoring function that the system safety assessment assigned to the most stringent level (MC/DC required).

### 2.2 Goals and kill criteria

| ID | Goal | Threshold | Kind |
|---|---|---|---|
| K1 | Every minor frame meets its budget | ≤ 8,000 µs (80% of 10 ms) at WCET | Kill |
| K2 | No received word lost or corrupted silently | Every loss counted and reported in the health word | Kill |
| K3 | Validity-monitor logic verified to MC/DC | Every condition shown independently | Kill |
| K4 | No board respin | Hardware fixed for the program schedule | Kill |
| G5 | Interrupt CPU at maximum bus rate | < 5% | Scored |

### 2.3 Ownership (precise, as 01.2 requires)

| Component | Mark | My role |
|---|---|---|
| Word acceptance and validity-monitor logic | ★ | Wrote the low-level requirements and the code; designed the MC/DC test set; produced the coverage-analysis report |
| Scheduler re-phasing and the timing budget | ★ | Did the per-frame analysis; wrote the timing-budget document |
| Hardware/software decision memo (label filtering in the protocol IC + DMA) | ★ | Measured the options; wrote the memo; the hardware lead and the chief engineer approved it |
| Board design, protocol IC selection | ○ | Hardware team; I consumed their register-level documentation |
| DO-178C plans (PSAC, SVP), liaison with the authority | ◆ | Reviewed the verification plan sections for my components; the certification lead owned the plans and the liaison |
| HIL test rig | ○ | Test team; I wrote 61 of its 412 requirements-based test procedures |

---

## 3. The whiteboard blueprint

```text
 ENTERPRISE BAND (thin): aircraft data network (o) | sensors / LRUs on 12 A429 buses (o) | HIL rig (o) | certification lead / authority (o)

 12 x ARINC 429 (100 kbit/s) --> [protocol IC (o)] -- hardware label filter: 9 of 30 labels pass <> --
                                        |  SPI + DMA (32-word blocks)
                                        v
                         [[ RING (SPSC, 256) * ]]  ISR: signal only (~2 us per block)
                                        |  task, minor frame
                                        v
       [[ DECODE + ACCEPT * ]] parity & label & (normal | (ftest & test-mode))  --MC/DC: 6 tests, 5 conditions
                                        |
                         [[ LATEST-VALUE TABLE * ]] per label: value, SSM, timestamp  --> staleness monitor
                                        |
       [[ CYCLIC EXECUTIVE * ]] 10 x 10 ms frames, budget 8,000 us; tasks re-phased --> network publisher (o)
       health word: overflows, parity errors, stale labels, frame overruns
 numbers: 33,333 words/s max -> ~10,000 after filter | ISR 20% -> < 2% CPU | worst frame 8,600 -> 7,700 us | MC/DC 5/5
```

| Phase | What to draw and say for Archetype D |
|---|---|
| Context | 12 channels, 33,333 words/s maximum, an ISR per word (20% CPU), the frame-0 overrun, 3 unreproducible stale-data reports |
| Architecture | Bus → protocol IC filter → DMA → ring → decode/accept → latest-value table → executive |
| Depth menu | (1) acceptance logic and MC/DC, (2) timing: frames, WCET, bursts, (3) the hardware/software decision and the ring/DMA/cache details |
| Failure | INC-F1: the stale-data reports explained (§6) |
| Trade-offs | Optimized ISR vs FPGA vs protocol IC + DMA; cyclic executive vs preemptive RTOS (§8) |
| Hindsight | Overflow and timeout policies as explicit requirements from day 1 (§9) |

#### How an L5 tells it

> I worked on avionics firmware for a data concentrator. We rewrote the ARINC 429 handling and got 100% test coverage, and it was certified under DO-178C. Performance improved a lot after our optimizations and the system is very robust now.

#### How an L7 tells it

> Flightline was a firmware rework of a remote data concentrator on a Cortex-M7 that reads 12 ARINC 429 buses. The v1 design took 1 interrupt per word, about 20% of the CPU at the maximum rate of 33,333 words a second, and minor frame 0 overran its 8,000-microsecond budget, and the fleet had 3 stale-air-data reports that never reproduced on the bench. I owned 3 things: the hardware-software decision to filter labels in the existing protocol IC and move words by DMA, which needed no board respin; the word-acceptance and validity logic with its MC/DC test design, because that function was assigned the most stringent level; and the scheduler re-phasing. Interrupt load fell below 2%, the worst frame is 7,700 microseconds, all 5 conditions of the acceptance decision are shown independently, and the stale reports traced to a ring that overwrote words the task was still reading.

---

## 4. Deep well 1: the acceptance decision and MC/DC

### 4.1 The decision

A received word is accepted only if:

> **parity OK ∧ label known ∧ (SSM = Normal ∨ (SSM = Functional Test ∧ test mode))**

There are 5 conditions. Two of them (the SSM comparisons) are *coupled*: both are derived from the same 2-bit field, so they can't both be true. Unique-cause MC/DC has to find independence pairs despite the coupling.

### 4.2 Decision coverage is not MC/DC

The listing runs two test sets through an independence-pair checker (§12):
- **The decision-coverage set (2 tests):** one accepted word and one with bad parity. Decision coverage is 100%, because the decision was both true and false. **MC/DC: 1 of 5.** Only parity is shown to independently affect the outcome.
- **The MC/DC set (6 tests = N + 1):** independence pairs for all 5 conditions.
  - T1/T2 shows parity, T1/T3 shows label, T1/T4 shows SSM=Normal.
  - **T4/T5 shows SSM=Functional Test:** both vectors have test mode set and SSM≠Normal, so only the functional-test condition changes.
  - **T5/T6 shows test mode:** both are functional-test words, and only the mode differs.

**Why the coupling matters.** A naive vector set that set test mode false everywhere except one test can't show the functional-test condition independently. The first draft of this listing's vector set did exactly that, and working the pairs by hand showed it would score 4/5. The fix was choosing T1–T5 with test mode *true*, so the SSM conditions vary alone.

#### How an L5 tells it

> We achieved 100% code coverage on the acceptance logic, which meets the DO-178C requirements. The test suite was really thorough and basically covered every case.

#### How an L7 tells it

> The acceptance decision has 5 conditions, and the coverage criterion for that function was MC/DC, so 100% decision coverage was not the target. My first requirements-based test set reached 100% decision coverage with 2 tests and showed only 1 of the 5 conditions independently, the parity bit. MC/DC needs, for each condition, a pair of tests that differ only in that condition and flip the outcome. 2 of the conditions are coupled because both come from the 2-bit SSM field, so I chose the vectors with test mode set, which lets the 2 SSM conditions vary alone. The final set is 6 tests, N plus 1 for 5 conditions, with an independence pair for every condition, and each test traces to a low-level requirement.

### 4.3 Short-circuit evaluation and what the tool measures

C's `&&` and `||` short-circuit. A condition may never be *evaluated* in a given test, and coverage tools account for that with masking or unique-cause rules (the NASA tutorial covers both). The listing deliberately evaluates every condition (bitwise operators on booleans), so each test's condition vector is complete and the pair search is unambiguous. ⚠ In a certified program, the coverage tool's MC/DC definition and its qualification status are agreed in the verification plan.

---

## 5. Deep well 2: timing (frames, WCET and bursts)

### 5.1 The cyclic executive

There are 10 minor frames of 10 ms, and the budget is 8,000 µs per frame: 80%, leaving 20% for interrupt and margin.

| Task | Period (frames) | WCET (µs) | Phase before | Phase after |
|---|---|---|---|---|
| attitude | 1 | 2,600 | 0 | 0 |
| air-data | 2 | 1,900 | 0 | **1** |
| bus-io | 1 | 1,700 | 0 | 0 |
| health | 5 | 1,500 | 0 | **2** |
| logging | 10 | 900 | 0 | **4** |

- **Before:** everything is phased at 0, so frame 0 carries **8,600 µs**, an overrun, while other frames carry 4,300.
- **After re-phasing:** the worst frame is **7,700 µs** (frame 7), and every frame is within budget.
- **Utilization is unchanged at 56.4%.** Re-phasing moves load between frames; it doesn't reduce it.

The listing computes all of this (§12).

### 5.2 Would a preemptive RTOS be schedulable?

Liu and Layland's bound for rate-monotonic scheduling (*Journal of the ACM*, 1973, DOI 10.1145/321738.321743) is U ≤ n(2^(1/n) − 1). For 5 tasks that's **0.743**. Our utilization of 0.564 is under it, so a rate-monotonic RTOS would also schedule this task set. The choice between them is about *evidence*, not feasibility (§8).

### 5.3 WCET: how the numbers were obtained

- **Measured high-water marks on the target:** caches and branch predictors in the worst state the configuration permits, the longest paths exercised by dedicated tests, and the maximum over 10⁶ frames on the HIL rig.
- **Plus margin,** because measurement can miss the true worst case. The survey by Wilhelm et al. ("The worst-case execution-time problem", *ACM TECS* 7(3), 2008, DOI 10.1145/1347375.1347389) explains why measurement alone is not a safe bound on cached processors.
- **Flightline's method:** measured maximum + 20% margin, with the instruction and data caches configured identically to flight. ⚠ The acceptable method is agreed in the verification plan; static WCET analysis tools are the stronger evidence when they're available for the processor.

#### How an L5 tells it

> The scheduler had some timing issues, so we optimized the tasks and moved some things around until the timing looked good on the bench. Everything fits well within the budget now.

#### How an L7 tells it

> Frame 0 overran at 8,600 microseconds against an 8,000 budget, and the reason was phasing, not slow code: every periodic task started in frame 0. I re-phased 3 tasks: air-data to odd frames, health to frames 2 and 7, logging to frame 4. That made the worst frame 7,700 microseconds while utilization stayed at 56.4%, because re-phasing moves load between frames without reducing it. The WCETs are measured high-water marks over a million frames on the HIL rig with flight cache settings, plus a 20% margin, because on a cached processor measurement alone can miss the worst path. A rate-monotonic RTOS would also schedule this set, since 0.564 is under the 0.743 bound for 5 tasks; I kept the executive for the timing evidence it produces, frame by frame.

---

## 6. Failure archaeology: INC-F1, the unreproducible stale-data reports

1. **Detection.** 3 crew "air-data stale" messages over 14 months of fleet service, each clearing within seconds. Never reproduced on the bench.
2. **Bounding.**
   - All 3 coincided with a bus-transmitter reset: an upstream unit rebooting.
   - The logs showed parity errors on that channel in the same second.
3. **Hypothesis and reproduction.** A reset makes the upstream unit resynchronize and burst its whole label set. With 4 transmitters resetting together on a shared power event, the HIL rig produced a **300-word burst** into the 256-slot ring.
4. **Root cause.** The v1 ring *overwrote the oldest slot* when full, with no ownership rule. The task could be mid-read of that slot when the ISR overwrote it. The torn word failed its parity check, was discarded, and the label's latest value aged past its staleness limit. No counter recorded the overwrite. My analysis showed it; the v1 ring predated my involvement, and I owned the fix.
5. **Fix.**
   - The SPSC ring now **never overwrites unread data**: full means drop the newest and count it (the listing: 300 pushed, 256 kept, 44 counted, no corruption).
   - Freshness comes from a **latest-value table** at the consumer, not from overwriting in the ring.
   - **Hardware label filtering** cut the burst from ~300 to ~90 words.
   - The ring was resized to 512 slots for margin.
6. **Systemic.**
   - The overflow policy and the staleness timeouts became **explicit low-level requirements** with tests. They had been implementation defaults.
   - The health word reports overflows, so the fleet data now shows any recurrence. 0 so far.

#### How an L5 tells it

> There were some stale data issues in the field that were kind of hard to reproduce. We eventually figured out it was a buffer issue, fixed the ring buffer, and the problem went away.

#### How an L7 tells it

> The fleet had 3 'air-data stale' messages in 14 months that never reproduced on the bench. All 3 coincided with an upstream transmitter reset, and the logs showed parity errors on that channel in the same second. On the HIL rig, 4 transmitters resetting together produced a 300-word burst into a 256-slot ring, and the v1 ring overwrote its oldest slot while the task could still be reading it, so the task saw a torn word, the parity check discarded it, and the label went stale with no counter to show why. The v1 ring predated my time on the program; I owned the analysis and the fix. The ring now never overwrites unread data and counts every drop, freshness comes from a latest-value table at the consumer, and hardware label filtering cut the burst to about 90 words. The overflow policy and the timeouts became explicit requirements with tests, and the health word has reported 0 overflows since.

---

## 7. Deep well 3: the hardware–software decision

### 7.1 The options memo (what I measured)

| Option | Interrupt CPU at max rate | Board change | Certification impact | Verdict |
|---|---|---|---|---|
| O0: optimize the per-word ISR (assembly, tighter decode) | ~11% (best measured) | None | Hand-written assembly needs extra verification evidence | Fails G5 by 2× |
| O1: FPGA receivers for all 12 channels | ~1% | **Respin** (K4 fails) | The FPGA becomes complex electronic hardware with its own assurance process (DO-254) | Killed by K4 |
| O2: protocol IC's hardware label filter + DMA blocks (chosen) | **< 2%** | None: uses existing IC features and an unused DMA channel | Configuration of an existing device; filter tables verified by test | Chosen |

**The key fact was hidden in a datasheet.** The protocol IC already on the board had a per-channel hardware label filter that v1 never enabled. Only 9 of the ~30 labels on each bus were needed, so enabling the filter cut word traffic by ~70% at the source. The DMA channel moved 32-word blocks, so the ISR became one short notification per block.

#### How an L5 tells it

> We decided to move some of the processing into hardware to improve performance, which made the interrupt handling much more efficient. The hardware team helped us set it up.

#### How an L7 tells it

> I measured 3 options before writing the memo. A hand-optimized per-word ISR got to about 11% of CPU at the maximum rate, twice our 5% target. FPGA receivers would have reached about 1%, but needed a board respin, which the program schedule ruled out, and would have brought a hardware assurance process of their own. The third option was in the datasheet of the protocol IC already on the board: a per-channel hardware label filter that v1 never enabled. We needed 9 of about 30 labels per bus, so the filter removed about 70% of the traffic before the processor saw it, and an unused DMA channel moves words in 32-word blocks, which brought interrupt load below 2%. The hardware lead and the chief engineer approved the memo, and the filter tables are verified by test like any other configuration.

### 7.2 Debugging across the boundary

The hardest co-design bugs sit on the boundary, and both teams believe the other one is wrong. Flightline's example: after enabling the filter, 2 labels never arrived.
- **The finding:** the filter table had been programmed with the labels' *octal values in transmission bit order*, but the IC expected the *reversed* order. ARINC 429 labels go out most-significant bit first, and receivers often store them reversed (§1.2; the listing's `reverse8`).
- **How it was resolved:** a logic-analyzer capture on the bus plus a register dump, compared side by side. That's evidence both teams accept.
- **The fix was one line in the table generator.** The lesson was a shared test that encodes a label through the same code path the filter configuration uses.

---

## 8. Why not simpler? (three options + Option Zero, and the scheduler choice)

| Decision | Options | Kill criterion | Chosen and why |
|---|---|---|---|
| Word handling | O0 optimized ISR · O1 FPGA · O2 filter + DMA | G5 (O0), K4 (O1) | O2: meets both with existing hardware |
| Scheduling | Cyclic executive · rate-monotonic RTOS | None: both schedulable (0.564 < 0.743) | Cyclic executive: frame-by-frame timing evidence, an existing verified executive, and deterministic test reproduction. An honest tie on feasibility. |
| Ring overflow | Overwrite oldest · drop newest + count | K2 (overwrite-oldest corrupted reads) | Never overwrite unread data; freshness from the latest-value table |
| Verification | Decision coverage · MC/DC | K3 | MC/DC for the validity function; decision coverage elsewhere, per its assigned level ⚠ |

---

## 9. Constraints and hindsight

<!-- ledger:start name=d-flightline -->
| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| TD1 | No board respin for this program | Deadline | Program schedule; supplemental type certificate date | Hard | Program plan; respin estimate of ~9 months including hardware assurance | Label filtering in the existing protocol IC; DMA on an unused channel | FPGA option (about 1% CPU) given up | Next hardware revision |
| TD2 | Validity-monitor function verified to MC/DC | Regulatory | System safety assessment; software verification plan | Hard | Safety assessment allocation; the approved verification plan | Acceptance logic written for testability; N+1 test design | 6 tests and an independence-pair analysis for 5 conditions; ~3 engineer-weeks | Safety assessment revision |
| TD3 | Static analyzer not qualified as a verification tool | Regulatory | Certification lead; tool qualification guidance | Hard | Tool qualification status recorded in the plan | Analyzer findings used as a review aid, not for credit; manual review retained | ~2 engineer-weeks of manual review per release | Tool qualification completed |
| TD4 | 128 KB RAM on the MCU | Budget | Hardware design | Hard | Datasheet and the linker map: 41 KB free before the rework | Fixed-size ring (512 slots) and latest-value table; no heap | 2 KB for the ring and 1.2 KB for the table | Next hardware revision |
<!-- ledger:end -->

**Hindsight:**
- **Overflow and staleness policies as explicit low-level requirements from day 1.** In v1 they were implementation defaults, and INC-F1 was the cost.
- **A shared hardware/software test harness** that drives the IC's filter configuration through the same encoder the firmware uses (§7.2).
- **A decision to defend:** the cyclic executive over an RTOS, even though both were feasible.

---

## 10. Numbers card (Archetype D)

| Number | Value | Re-derive |
|---|---|---|
| Max words/s | ~33,333 | 12 × 100,000 ÷ 36 |
| v1 ISR CPU | ~20% | 33,333 × 6 µs |
| Filter reduction | ~70% | 9 of ~30 labels needed |
| v2 interrupt CPU | < 2% | ~10,000 words/s in 32-word blocks, ~2 µs per block |
| Worst frame | 8,600 → 7,700 µs | Listing |
| Utilization | 56.4% | Σ WCET × rate |
| RM bound (5 tasks) | 0.743 | 5(2^0.2 − 1) |
| MC/DC | 1/5 → 5/5 with 6 tests | Listing |
| Burst | ~300 → ~90 words | HIL rig, with and without the filter |
| Ring | 256 → 512 slots; overflow counted | Listing (44 drops at 256) |

---

## 11. Hiring-committee scoring rubric: Archetype D

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Coverage** | "100% coverage" | Names the criterion | MC/DC with independence pairs | Plus coupled conditions, short-circuit handling, traceability to requirements |
| **Timing** | "Fits on the bench" | Utilization | Per-frame budgets and WCET method | Phasing analysis; RM bound comparison; measurement limits on cached cores |
| **Bus protocol** | Names ARINC 429 | Word format | Parity, SSM and BNR handled correctly | Bit-order subtleties at the hardware boundary; burst analysis |
| **Concurrency** | "Lock-free ring" | SPSC | Ownership and ordering | Plus DMA and cache coherency on a cached MCU (Q3) |
| **Co-design** | "Moved it to hardware" | Names the options | A measured options memo | Found the existing-hardware option; resolved a cross-boundary bug with shared evidence |
| **Certification** | "It was certified" | Names the standard | States own artifacts | States own artifacts and the limits of credit (tool qualification, ⚠ authority agreement) |

---

## 12. Listing and output

### 12.1 Listing L10: `flightline.c`

<!-- listing:flightline.c -->
```c
/* flightline.c - the Archetype D mechanisms, as host-testable C11:
 *   1. ARINC 429 word encode/decode: label (bit-reversed on the wire), SDI,
 *      BNR data with sign bit, SSM, odd parity
 *   2. the word-acceptance decision and an MC/DC (unique-cause) checker:
 *      a decision-coverage test set vs an MC/DC test set
 *   3. cyclic executive: per-minor-frame budget check, before/after re-phasing
 *   4. ISR -> task SPSC ring buffer with an explicit overflow policy (drop newest)
 * The firmware part (sections 1-4 minus the harness) also cross-compiles for a
 * Cortex-M7 with -DFIRMWARE_ONLY: no libc, no heap, no recursion, fixed sizes.
 * cross: thumb-freestanding-eabihf -mcpu=cortex_m7 -DFIRMWARE_ONLY
 */
// cross: thumb-freestanding-eabihf -mcpu=cortex_m7 -DFIRMWARE_ONLY
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

/* ---- 1. ARINC 429 ------------------------------------------------------ */
enum ssm_bnr { SSM_FAILURE_WARNING = 0, SSM_NO_COMPUTED_DATA = 1, SSM_FUNCTIONAL_TEST = 2, SSM_NORMAL = 3 };

static uint32_t reverse8(uint32_t b) {
    uint32_t r = 0;
    for (int i = 0; i < 8; ++i) {
        r = (r << 1) | ((b >> i) & 1u);
    }
    return r;
}

static uint32_t parity_odd_bit(uint32_t w31) {   /* bit 32 makes the total count of ones odd */
    uint32_t ones = 0;
    for (int i = 0; i < 31; ++i) {
        ones += (w31 >> i) & 1u;
    }
    return (ones % 2u == 0u) ? 1u : 0u;
}

/* BNR: value / resolution as a signed integer in bits 11-29 (bit 29 = sign, two's complement). */
static uint32_t a429_encode_bnr(uint32_t label_octal, uint32_t sdi, int32_t counts, uint32_t ssm) {
    uint32_t w = reverse8(label_octal & 0xFFu);
    w |= (sdi & 0x3u) << 8;
    w |= ((uint32_t)counts & 0x7FFFFu) << 10;   /* 19 bits: 18 magnitude + sign */
    w |= (ssm & 0x3u) << 29;
    w |= parity_odd_bit(w) << 31;
    return w;
}

struct a429_fields {
    uint32_t label_octal, sdi, ssm;
    int32_t counts;
    bool parity_ok;
};

static struct a429_fields a429_decode(uint32_t w) {
    struct a429_fields f;
    f.label_octal = reverse8(w & 0xFFu);
    f.sdi = (w >> 8) & 0x3u;
    uint32_t raw = (w >> 10) & 0x7FFFFu;
    f.counts = (raw & 0x40000u) ? (int32_t)(raw | 0xFFF80000u) : (int32_t)raw;   /* sign-extend bit 29 */
    f.ssm = (w >> 29) & 0x3u;
    f.parity_ok = parity_odd_bit(w & 0x7FFFFFFFu) == (w >> 31);
    return f;
}

/* ---- 2. Acceptance decision (instrumented: all conditions evaluated, values recorded) */
enum { C_PARITY, C_LABEL, C_NORMAL, C_FTEST, C_TESTMODE, N_COND };

static bool label_known(uint32_t label) {
    static const uint32_t table[] = {0203u, 0204u, 0310u, 0311u};
    for (unsigned i = 0; i < sizeof table / sizeof table[0]; ++i) {
        if (table[i] == label) {
            return true;
        }
    }
    return false;
}

static bool accept_word(uint32_t w, bool test_mode, bool cond[N_COND]) {
    struct a429_fields f = a429_decode(w);
    cond[C_PARITY] = f.parity_ok;
    cond[C_LABEL] = label_known(f.label_octal);
    cond[C_NORMAL] = f.ssm == SSM_NORMAL;
    cond[C_FTEST] = f.ssm == SSM_FUNCTIONAL_TEST;
    cond[C_TESTMODE] = test_mode;
    return cond[C_PARITY] & cond[C_LABEL] & (cond[C_NORMAL] | (cond[C_FTEST] & cond[C_TESTMODE]));
}

/* ---- 3. Cyclic executive: 10 ms minor frames, 100 ms major frame ---------- */
struct task { const char *name; uint32_t period_frames, phase, wcet_us; };

static uint32_t frame_load_us(const struct task *t, unsigned n, uint32_t frame) {
    uint32_t load = 0;
    for (unsigned i = 0; i < n; ++i) {
        if (frame % t[i].period_frames == t[i].phase) {
            load += t[i].wcet_us;
        }
    }
    return load;
}

/* ---- 4. SPSC ring: ISR produces, task consumes; on full, drop newest and count */
#define RING_SIZE 256u
struct ring {
    uint32_t slot[RING_SIZE];
    _Atomic uint32_t head;     /* written by the ISR only */
    _Atomic uint32_t tail;     /* written by the task only */
    uint32_t overflows;        /* ISR-owned; read by the task for health reporting */
};

static bool ring_push_isr(struct ring *r, uint32_t w) {
    uint32_t h = atomic_load_explicit(&r->head, memory_order_relaxed);
    uint32_t t = atomic_load_explicit(&r->tail, memory_order_acquire);
    if (h - t == RING_SIZE) {
        r->overflows++;
        return false;                         /* policy: never overwrite unread data */
    }
    r->slot[h % RING_SIZE] = w;
    atomic_store_explicit(&r->head, h + 1u, memory_order_release);   /* publish after the write */
    return true;
}

static bool ring_pop_task(struct ring *r, uint32_t *w) {
    uint32_t t = atomic_load_explicit(&r->tail, memory_order_relaxed);
    uint32_t h = atomic_load_explicit(&r->head, memory_order_acquire);
    if (t == h) {
        return false;
    }
    *w = r->slot[t % RING_SIZE];
    atomic_store_explicit(&r->tail, t + 1u, memory_order_release);
    return true;
}

/* Exported so the firmware-only build keeps every function (no unused statics). */
uint32_t fl_encode(uint32_t label, uint32_t sdi, int32_t counts, uint32_t ssm);
bool fl_accept(uint32_t w, bool test_mode);
uint32_t fl_frame_load(const struct task *t, unsigned n, uint32_t frame);
bool fl_push(struct ring *r, uint32_t w);
bool fl_pop(struct ring *r, uint32_t *w);
uint32_t fl_encode(uint32_t label, uint32_t sdi, int32_t counts, uint32_t ssm) { return a429_encode_bnr(label, sdi, counts, ssm); }
bool fl_accept(uint32_t w, bool test_mode) { bool c[N_COND]; return accept_word(w, test_mode, c); }
uint32_t fl_frame_load(const struct task *t, unsigned n, uint32_t frame) { return frame_load_us(t, n, frame); }
bool fl_push(struct ring *r, uint32_t w) { return ring_push_isr(r, w); }
bool fl_pop(struct ring *r, uint32_t *w) { return ring_pop_task(r, w); }

#if !defined(FIRMWARE_ONLY)
/* ---- Host test harness -------------------------------------------------- */
#include <stdio.h>

static int checks = 0, failed = 0;
static void check(bool ok, const char *what) {
    ++checks;
    if (!ok) {
        ++failed;
    }
    printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
}

struct vec { const char *name; uint32_t w; bool test_mode; };

/* Unique-cause MC/DC: for each condition, a pair of vectors that differ only in
 * that condition and produce different outcomes. */
static unsigned mcdc(const struct vec *v, unsigned n, const char *label) {
    bool cond[16][N_COND];
    bool out[16];
    for (unsigned i = 0; i < n; ++i) {
        out[i] = accept_word(v[i].w, v[i].test_mode, cond[i]);
    }
    static const char *names[N_COND] = {"parity", "label", "ssm=normal", "ssm=func-test", "test-mode"};
    unsigned covered = 0;
    bool decision_true = false, decision_false = false;
    printf("  %s (%u tests)\n", label, n);
    for (unsigned i = 0; i < n; ++i) {
        decision_true |= out[i];
        decision_false |= !out[i];
    }
    for (int c = 0; c < N_COND; ++c) {
        const char *pair = NULL;
        static char buf[64];
        for (unsigned i = 0; i < n && !pair; ++i) {
            for (unsigned j = i + 1; j < n && !pair; ++j) {
                bool only_c = cond[i][c] != cond[j][c];
                for (int k = 0; k < N_COND && only_c; ++k) {
                    if (k != c && cond[i][k] != cond[j][k]) {
                        only_c = false;
                    }
                }
                if (only_c && out[i] != out[j]) {
                    snprintf(buf, sizeof buf, "%s/%s", v[i].name, v[j].name);
                    pair = buf;
                }
            }
        }
        covered += pair ? 1u : 0u;
        printf("    %-14s %s\n", names[c], pair ? pair : "NOT SHOWN (no independence pair)");
    }
    printf("    decision coverage: %s; MC/DC: %u/%d conditions\n",
           (decision_true && decision_false) ? "100%" : "incomplete", covered, N_COND);
    return covered;
}

int main(void) {
    printf("1. ARINC 429 encode/decode\n");
    int32_t counts = 35000;   /* example: BNR counts at 1 unit per count */
    uint32_t w = a429_encode_bnr(0203u, 1u, counts, SSM_NORMAL);
    struct a429_fields f = a429_decode(w);
    printf("  word 0x%08X: label %03o, sdi %u, counts %d, ssm %u, parity %s\n",
           (unsigned)w, (unsigned)f.label_octal, (unsigned)f.sdi, (int)f.counts, (unsigned)f.ssm, f.parity_ok ? "ok" : "BAD");
    check(f.label_octal == 0203u && f.sdi == 1u && f.counts == 35000 && f.ssm == SSM_NORMAL && f.parity_ok, "round trip");
    uint32_t neg = a429_encode_bnr(0204u, 0u, -1250, SSM_NORMAL);
    check(a429_decode(neg).counts == -1250, "negative BNR value sign-extends from bit 29");
    bool all_flips_caught = true;
    for (int bit = 0; bit < 32; ++bit) {
        all_flips_caught = all_flips_caught && !a429_decode(w ^ (1u << bit)).parity_ok;
    }
    check(all_flips_caught, "each of the 32 single-bit flips breaks odd parity");
    check((w & 0xFFu) == reverse8(0203u) && (w & 0xFFu) != 0203u, "label bits stored reversed (transmitted MSB first)");

    printf("2. Acceptance decision: parity & label & (normal | (func-test & test-mode))\n");
    uint32_t ok = a429_encode_bnr(0203u, 0u, 100, SSM_NORMAL);
    uint32_t bad_parity = ok ^ 0x80000000u;
    uint32_t unknown = a429_encode_bnr(0277u, 0u, 100, SSM_NORMAL);
    uint32_t ncd = a429_encode_bnr(0203u, 0u, 100, SSM_NO_COMPUTED_DATA);
    uint32_t ftest = a429_encode_bnr(0203u, 0u, 100, SSM_FUNCTIONAL_TEST);
    const struct vec dc[] = {{"T1", ok, false}, {"T2", bad_parity, false}};
    const struct vec mc[] = {{"T1", ok, true}, {"T2", bad_parity, true}, {"T3", unknown, true},
                             {"T4", ncd, true}, {"T5", ftest, true}, {"T6", ftest, false}};
    unsigned c1 = mcdc(dc, 2, "requirements tests, decision coverage only");
    unsigned c2 = mcdc(mc, 6, "with MC/DC independence pairs");
    check(c1 < N_COND, "decision coverage alone leaves conditions unshown");
    check(c2 == N_COND, "N+1 = 6 tests show every condition independently affects the outcome");

    printf("3. Cyclic executive: 10 minor frames x 10 ms, budget 8,000 us per frame (80%%)\n");
    struct task before[] = {{"attitude", 1, 0, 2600}, {"air-data", 2, 0, 1900}, {"bus-io", 1, 0, 1700},
                            {"health", 5, 0, 1500}, {"logging", 10, 0, 900}};
    struct task after[] = {{"attitude", 1, 0, 2600}, {"air-data", 2, 1, 1900}, {"bus-io", 1, 0, 1700},
                           {"health", 5, 2, 1500}, {"logging", 10, 4, 900}};
    uint32_t worst_before = 0, worst_after = 0, sum = 0;
    printf("  frame:  ");
    for (uint32_t fr = 0; fr < 10; ++fr) {
        printf("%6u", (unsigned)fr);
    }
    printf("\n  before: ");
    for (uint32_t fr = 0; fr < 10; ++fr) {
        uint32_t l = frame_load_us(before, 5, fr);
        worst_before = l > worst_before ? l : worst_before;
        printf("%6u", (unsigned)l);
    }
    printf("\n  after:  ");
    for (uint32_t fr = 0; fr < 10; ++fr) {
        uint32_t l = frame_load_us(after, 5, fr);
        worst_after = l > worst_after ? l : worst_after;
        sum += l;
        printf("%6u", (unsigned)l);
    }
    printf("\n  utilization %.1f%%; worst frame before %u us, after %u us\n", sum / 1000.0, (unsigned)worst_before, (unsigned)worst_after);
    check(worst_before > 8000u, "before: frame 0 overruns its budget (every task phased at 0)");
    check(worst_after <= 8000u, "after re-phasing: every frame within budget, same utilization");

    printf("4. ISR -> task ring (256 slots), burst of 300 words with the task blocked\n");
    static struct ring r;
    unsigned pushed = 0;
    for (uint32_t i = 0; i < 300u; ++i) {
        pushed += ring_push_isr(&r, i) ? 1u : 0u;
    }
    uint32_t got, first = 0, last = 0, n = 0;
    while (ring_pop_task(&r, &got)) {
        if (n == 0) {
            first = got;
        }
        last = got;
        ++n;
    }
    printf("  pushed %u, overflows %u, drained %u (first %u, last %u)\n",
           pushed, (unsigned)r.overflows, (unsigned)n, (unsigned)first, (unsigned)last);
    check(pushed == 256u && r.overflows == 44u, "full ring drops the newest 44 words and counts them");
    check(first == 0u && last == 255u, "no unread word was overwritten");

    printf("\n%s (%d checks)\n", failed == 0 ? "verdict: OK" : "verdict: CHECK", checks);
    return 0;
}
#endif
```

### 12.2 Output (host harness)

<!-- output:flightline.c -->
```text
1. ARINC 429 encode/decode
  word 0xE222E1C1: label 203, sdi 1, counts 35000, ssm 3, parity ok
  [ok] round trip
  [ok] negative BNR value sign-extends from bit 29
  [ok] each of the 32 single-bit flips breaks odd parity
  [ok] label bits stored reversed (transmitted MSB first)
2. Acceptance decision: parity & label & (normal | (func-test & test-mode))
  requirements tests, decision coverage only (2 tests)
    parity         T1/T2
    label          NOT SHOWN (no independence pair)
    ssm=normal     NOT SHOWN (no independence pair)
    ssm=func-test  NOT SHOWN (no independence pair)
    test-mode      NOT SHOWN (no independence pair)
    decision coverage: 100%; MC/DC: 1/5 conditions
  with MC/DC independence pairs (6 tests)
    parity         T1/T2
    label          T1/T3
    ssm=normal     T1/T4
    ssm=func-test  T4/T5
    test-mode      T5/T6
    decision coverage: 100%; MC/DC: 5/5 conditions
  [ok] decision coverage alone leaves conditions unshown
  [ok] N+1 = 6 tests show every condition independently affects the outcome
3. Cyclic executive: 10 minor frames x 10 ms, budget 8,000 us per frame (80%)
  frame:       0     1     2     3     4     5     6     7     8     9
  before:   8600  4300  6200  4300  6200  5800  6200  4300  6200  4300
  after:    4300  6200  5800  6200  5200  6200  4300  7700  4300  6200
  utilization 56.4%; worst frame before 8600 us, after 7700 us
  [ok] before: frame 0 overruns its budget (every task phased at 0)
  [ok] after re-phasing: every frame within budget, same utilization
4. ISR -> task ring (256 slots), burst of 300 words with the task blocked
  pushed 256, overflows 44, drained 256 (first 0, last 255)
  [ok] full ring drops the newest 44 words and counts them
  [ok] no unread word was overwritten

verdict: OK (10 checks)
```

**Reading the output.**
- **Section 1:** a BNR word round-trips. A negative value sign-extends from bit 29. All 32 single-bit flips break odd parity. The label is stored bit-reversed.
- **Section 2:** decision coverage at 100% with MC/DC at 1/5, then 5/5 with the N+1 set, with the independence pair named for each condition.
- **Section 3:** frame loads before and after re-phasing, at the same utilization.
- **Section 4:** a 300-word burst into 256 slots keeps the first 256 intact and counts 44 drops.

The gate also compiles the firmware core for a Cortex-M7 with `-DFIRMWARE_ONLY`. That build has no `stdio`, no heap and no recursion, and the README records its object size.

---

## 13. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | Decision coverage presented as MC/DC | Fails "show me the independence pair" | Pair per condition (§4.2) |
| F2 | Coupled conditions ignored | MC/DC "impossible" claims, or 4/5 | Choose vectors so coupled conditions vary alone |
| F3 | Average-case timing | Frame overruns in the field | Per-frame WCET budgets; phasing (§5.1) |
| F4 | Measured WCET treated as proven | Missed worst path on a cached core | Margin + flight cache configuration; static analysis where available (§5.3) |
| F5 | Implicit overflow policy | Silent loss or torn reads (INC-F1) | Never overwrite unread data; count drops |
| F6 | DMA buffers in cacheable memory | Stale or partial data seen by the CPU | MPU non-cacheable region or explicit clean/invalidate (Q3) |
| F7 | Bit-order confusion | Labels "missing" after a filter change | Shared encoder for hardware config and firmware (§7.2) |
| F8 | Tool output taken as credit | Audit finding | Tool qualification status in the plan (TD3) |
| F9 | Ownership blur | "We certified it" | Name your artifacts (§2.3) |
| F10 | No staleness monitoring | A channel goes silent unnoticed | Timestamps in the latest-value table; explicit timeouts (Q9) |

---

## 14. Bar-raiser chains

<details><summary><b>Q1 · "You have 100% decision coverage. Isn't that enough?"</b></summary>

**Initial Prompt.** "Your tests take every decision both ways. What more could MC/DC possibly add?"

**L5 Answer.** "MC/DC is a stricter form of coverage required for higher levels, so it just means more tests."

**Why L5 Stalls.** "More tests" misses the point. MC/DC shows that *each condition* independently affects the outcome, which decision coverage doesn't. The candidate can't explain what a missing independence pair would hide.

**L7 Answer.** "Decision coverage shows the decision was true once and false once. With 5 conditions, that can be done with 2 tests that tell you nothing about 4 of them. My first test set did exactly that: 100% decision coverage, and only the parity condition shown to matter. If the label check were miscoded so it never rejected anything, those 2 tests would still pass. MC/DC requires, per condition, a pair of tests differing only in that condition with different outcomes, so a condition that can't affect the result is exposed. For 5 conditions that took 6 tests, including handling 2 conditions coupled through the same SSM field, by choosing vectors with test mode set so each SSM condition can vary alone."

</details>

<details><summary><b>Q2 · "Why a cyclic executive? A preemptive RTOS is more flexible."</b></summary>

**Initial Prompt.** "Rate-monotonic scheduling on an RTOS would handle this. Why a static table?"

**L5 Answer.** "Cyclic executives are more deterministic, and that's what you want in safety-critical systems."

**Why L5 Stalls.** "More deterministic" is a slogan. It doesn't say whether the RTOS would have worked, or what the executive bought that matters for this program.

**L7 Answer.** "Both would work, and I'd say so first. Utilization is 0.564, under the 0.743 Liu-Layland bound for 5 tasks, so rate-monotonic scheduling is feasible. I kept the cyclic executive for the evidence it produces: each minor frame is a fixed list of tasks, so timing verification is a per-frame sum of WCETs plus interrupt allowance, checkable by hand and by test, and every HIL run reproduces the same interleaving, which made INC-F1's burst reproducible. The executive also already existed with its verification evidence. The cost is rigidity: adding a task means re-phasing by hand, as I did. If the task set grew to the point where hand-phasing became error-prone, I'd move to the RTOS and its response-time analysis."

</details>

<details><summary><b>Q3 · "Your ring is fed by DMA on a Cortex-M7 with a data cache. What can go wrong?"</b></summary>

**Initial Prompt.** "Single core, so no memory-ordering issue, right?"

**L5 Answer.** "Right, on a single core there are no concurrency issues, so the ring is safe."

**Why L5 Stalls.** Two problems remain on a single core: the compiler can reorder or cache accesses across the ISR/task boundary, and the DMA engine writes memory behind the CPU's data cache. Both corrupt data silently.

**L7 Answer.** "Two things, even on one core. First, the compiler: the ISR and the task share the indices, so they're C11 atomics with release on publish and acquire on read, which also stops the compiler from reordering the slot write past the index update. Second, and more dangerous, the cache: the DMA engine writes the words to memory directly, and if the buffer is in cacheable memory the CPU can read stale cache lines. I placed the DMA buffers in a region the MPU marks non-cacheable. The alternative is invalidating the buffer's lines before each read, which has to be aligned to the 32-byte cache line or it corrupts neighboring data. The non-cacheable region costs a little bandwidth and removes a whole class of bugs that never show up on a bench with caches disabled."

</details>

<details><summary><b>Q4 · "Prove the worst-case burst fits your ring."</b></summary>

**Initial Prompt.** "512 slots. Why is that enough? Show me the burst analysis."

**L5 Answer.** "We tested with high traffic on the rig and it never overflowed, so 512 is plenty."

**Why L5 Stalls.** "Never overflowed in test" is the reasoning that missed INC-F1. The interviewer wants the bound.

**L7 Answer.** "The bound comes from the bus, not from the test. The worst case is every transmitter resetting at once and bursting its full label set while the task is in its longest frame. After the hardware filter, each bus delivers at most its 9 needed labels per burst cycle. The worst sustained arrival is the maximum filtered word rate, about 10,000 words a second, so 100 words per 10-millisecond frame. The worst observed simultaneous reset burst on the rig was about 90 words. The task drains the ring every frame, so the ring needs one frame's arrivals plus one burst, under 200 words. I set 512 for more than 2 times margin. The overflow counter in the health word turns that margin claim into fleet data. It has read 0 since entry into service."

</details>

<details><summary><b>Q5 · "How did you get your WCET numbers?"</b></summary>

**Initial Prompt.** "Attitude task: 2,600 µs worst case. Says who?"

**L5 Answer.** "We measured the execution time on the target with a timer and took the maximum."

**Why L5 Stalls.** A measured maximum is a lower bound on the true worst case, especially on a processor with caches and branch prediction. The candidate doesn't acknowledge the limitation.

**L7 Answer.** "Measured, with 3 safeguards, and I'd call it measurement-based, not proven. Measurement ran on the target with flight cache settings, over a million frames on the HIL rig, with test inputs designed to drive the longest paths (identified by path analysis of the code). The value is the maximum observed plus a 20% margin, and the method is in the verification plan. On a cached core measurement can miss the worst path, which is why the margin exists, and why static WCET analysis is the stronger evidence where a tool supports the processor configuration. The attitude task's observed maximum was 2,160 microseconds; with the margin it's budgeted at 2,600."

</details>

<details><summary><b>Q6 · "Why not just put the receivers in an FPGA?"</b></summary>

**Initial Prompt.** "An FPGA would handle all 12 buses in parallel at ~1% CPU. That's the clean design."

**L5 Answer.** "FPGA development is expensive and takes too long, so it wasn't practical."

**Why L5 Stalls.** "Expensive and takes too long" isn't quantified, and it misses the two specific blockers: the board respin and the hardware assurance process.

**L7 Answer.** "Technically it's the best option. I measured it on a dev kit at about 1% CPU. It failed a hard constraint: no board respin for this program, which the schedule put at about 9 months including the hardware assurance work an FPGA of that complexity brings. What made the decision easy was that the option we chose got to under 2% with zero hardware change, using a filter feature of the IC already on the board. I'd recommend the FPGA for the next hardware revision, where a respin is planned anyway; it's in my ledger with that trigger."

</details>

<details><summary><b>Q7 · "A word arrives in flight with SSM = Functional Test. What happens?"</b></summary>

**Initial Prompt.** "Test mode is off, the aircraft is flying, and a label shows Functional Test. Walk me through it."

**L5 Answer.** "The word would be rejected since we're not in test mode."

**Why L5 Stalls.** The rejection is right, but what happens *next* matters for safety: the label's value, its staleness, and what the crew and maintenance systems see.

**L7 Answer.** "The acceptance decision rejects it: SSM isn't Normal, and the functional-test branch needs test mode. The latest-value table keeps the previous accepted value with its timestamp, so the label isn't refreshed. If Functional Test words keep arriving, the value ages past its staleness limit, the label is published as invalid to the network, and the health word logs it as 'SSM non-normal', distinct from 'stale, silent'. That distinction matters to maintenance: a transmitter stuck in test mode on the ground is a different fault from a broken wire. Both behaviors are low-level requirements with tests. T5 and T6 in the MC/DC set exercise exactly the test-mode condition."

</details>

<details><summary><b>Q8 · "Your static analyzer isn't qualified. What credit did you take?"</b></summary>

**Initial Prompt.** "You ran a MISRA checker. Did it count toward verification?"

**L5 Answer.** "Yes, we used it to show MISRA compliance for the certification."

**Why L5 Stalls.** Claiming credit from an unqualified tool is a real certification problem. The interviewer is testing whether the candidate understands what the evidence can and can't stand on (⚠ program-specific).

**L7 Answer.** "None, by itself, and that's in the plan as TD3. The analyzer wasn't qualified under the tool-qualification guidance, so its findings were a review aid. The verification credit came from code reviews against the coding standard, with the analyzer's report as an input that reviewers had to disposition finding by finding. That costs about 2 engineer-weeks of manual review per release. Documented MISRA deviations went through the same review, each with a rationale. If the tool were qualified, some of that review could be replaced. The certification lead decided that trade, not me, and I'd only describe the credit as the plan defined it."

</details>

<details><summary><b>Q9 · "One bus goes completely silent. How do you know, and how fast?"</b></summary>

**Initial Prompt.** "A wire breaks. No words arrive on channel 7. What detects it, and when?"

**L5 Answer.** "The data would go stale and the system would flag it."

**Why L5 Stalls.** It has no mechanism and no timing. Silence produces no events, so detection must be designed in, and the interviewer wants the timeout and its rationale.

**L7 Answer.** "Silence is detected by absence, so each label in the latest-value table carries the timestamp of its last accepted word, and the health task checks every label's age each frame against a per-label limit. The limit is a low-level requirement derived from the label's transmit rate: typically 3 times the nominal interval, so a label sent every 50 milliseconds goes invalid at 150. A broken wire on channel 7 makes all of its labels go invalid within 1 limit period, and the health word reports a channel-level 'no activity' when every label on a channel ages out together, which tells maintenance it's the wire or the transmitter, not one parameter. In v1 these limits were implementation constants; making them requirements with tests was one of the INC-F1 lessons."

</details>

<details><summary><b>Q10 · "The hardware team says it's a software bug. You say it's hardware. Resolve it."</b></summary>

**Initial Prompt.** "After enabling the label filter, 2 labels never arrive. Each team blames the other. What did you do?"

**L5 Answer.** "We worked with the hardware team to debug it, and eventually we found the issue and fixed the configuration."

**Why L5 Stalls.** It's a narrative without method. The interviewer is testing how the candidate produces evidence both sides accept, which is the core co-design skill.

**L7 Answer.** "I stopped the argument by producing evidence both teams trust. I put a logic analyzer on channel 3 and captured the 2 missing labels on the wire, with correct parity, so the transmitter was fine. I dumped the IC's filter registers and compared them with the label table bit by bit: the table generator had written the labels in transmission bit order, and the IC expects them bit-reversed, the opposite convention. It was a one-line fix in the generator. Neither team's code was wrong in isolation; the convention between them was undocumented. The lasting fix was a shared test that encodes each label through the same encoder the firmware uses and checks the IC accepts it on the rig."

</details>

---

## 15. Checklist

- [ ] The coverage criterion for each component, the level that requires it, and an independence pair per condition for your most complex decision (§4).
- [ ] Coupled conditions and short-circuit handling explained for your decisions (§4.2–§4.3).
- [ ] Per-frame timing table, phasing, utilization, and the RM bound comparison (§5).
- [ ] WCET method stated with its limits (§5.3, Q5).
- [ ] Burst analysis for every buffer between an ISR or DMA and a task (Q4).
- [ ] DMA and cache coherency handling on your MCU (Q3).
- [ ] The hardware/software options memo with measurements (§7.1).
- [ ] One cross-boundary bug and the evidence that resolved it (§7.2, Q10).
- [ ] Your certification artifacts listed precisely, and the limits of tool credit (§2.3, Q8, ⚠).
- [ ] Staleness and timeout behavior as requirements (Q9).

---

## 16. References

- RTCA DO-178C, *Software Considerations in Airborne Systems and Equipment Certification*, 2011 (software levels; structural coverage objectives). RTCA DO-330, *Software Tool Qualification Considerations*, 2011.
- Kelly J. Hayhurst, Dan S. Veerhusen, John J. Chilenski and Leanna K. Rierson, "A Practical Tutorial on Modified Condition/Decision Coverage", NASA/TM-2001-210876. <https://shemesh.larc.nasa.gov/fm/papers/Hayhurst-2001-tm210876-MCDC.pdf>
- C. L. Liu and James W. Layland, "Scheduling Algorithms for Multiprogramming in a Hard-Real-Time Environment", *Journal of the ACM* 20(1):46–61, 1973. DOI 10.1145/321738.321743 (verified via Crossref).
- Reinhard Wilhelm et al., "The worst-case execution-time problem: overview of methods and survey of tools", *ACM Transactions on Embedded Computing Systems* 7(3), 2008. DOI 10.1145/1347375.1347389 (verified via Crossref).
- MISRA (C coding guidelines). <https://misra.org.uk/>
- ARINC Specification 429, *Digital Information Transfer System* (published by SAE ITC / ARINC Industry Activities): word format, label bit order, SSM and parity conventions.
