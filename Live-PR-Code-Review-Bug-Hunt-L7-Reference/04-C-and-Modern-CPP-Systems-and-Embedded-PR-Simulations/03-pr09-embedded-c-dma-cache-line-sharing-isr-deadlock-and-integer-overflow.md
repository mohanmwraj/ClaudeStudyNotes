# PR09 · Embedded C: DMA Cache-Line Sharing, ISR Deadlock and Integer Overflow

> **What this module is.** A motor-controller firmware PR moves the host-PC command link from a polled UART to DMA on a Cortex-M7 (32-byte-line write-back data cache). The PR adds an interrupt-driven TX queue, a flush before low-power entry, a public frame-length check and a cheaper link-loss failsafe. It hides **7 defects (4 Sev-1)**. All compile warning-free (`-Wall -Wextra -Wpedantic -Wconversion -Werror`) on GCC 16 and Clang 21 and pass the author's host tests. In the worst of them, a **STOP command is undone by a late retransmission**, a length check accepts a 250-byte payload for an 18-byte buffer, and the failsafe trips on valid commands near the 49.7-day uptime wrap. A host model of the D-cache, the DMA and interrupt delivery reproduces each one, and the generated Cortex-M7 and x86-64 code shows the one that a host run can't.

| Artifact | What it is | Verified |
|---|---|---|
| `pr09-diff` | `uart_link.c` (polled → DMA, TX queue, flush, frame check, failsafe), `uart_link.h`, test rewritten: 269 diff lines | `git diff --no-index` from compiled sources |
| `uart_link_test.c` (author's) | 7 host tests | **7/7 pass** on GCC and Clang (§4) |
| `hal_host.c` | Host model: per-line D-cache (CPU copy vs RAM copy), DMA that reads and writes RAM only, interrupt windows, single-core spinlock semantics | unchanged by the PR; listed in §8 |
| `probes.c` | 7 probes: replay after STOP, eviction mid-transfer, stale TX, ISR inside the critical section, oversized payload, failsafe across the wrap, telemetry layout | each shows the defect on the PR and its absence on the fix (§8) |
| `asm_probe.c` | `uart_link_flush` and `uart_link_frame_fits` compiled for Cortex-M7 (Clang 21) and x86-64 (GCC 16) | PR vs fix listings (§8.2) |
| Fixed code | Line-owning DMA buffers, invalidate after RX and clean before TX, IRQ masking instead of a shared spinlock, an atomic idle flag, an `int` length check, elapsed-time failsafe, field-by-field telemetry | fixed suite 13/13; PR's own tests against the fix 6/7 (the failing one encodes F7) |

**Verification.** GCC 16.2 (MinGW-w64) and Clang 21.1 (Zig 0.16), `-std=c17 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`. Tests and probes are built and run with both compilers, with identical results. The cache model keeps a CPU copy and a RAM copy of every 32-byte line the firmware or DMA touches, and treats each such line as resident and write-back. A Cortex-M7 behaves that way once the CPU has touched the line, which the PR's code does. It is a model, not the silicon. The listings in §8.2 are compiler output for `-mcpu=cortex-m7 -mthumb`, not hand-written. No hardware was used.

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L3 Resources (cache and DMA) | F1 RX DMA buffer shares a cache line with `last_seq`, F2 TX buffer not cleaned before the DMA reads it | Cache effects are invisible in host tests and in debuggers (which read through the cache) |
| L2 Concurrency (interrupts) | F3 spinlock shared by task and ISR on one core, F4 ISR flag polled without `volatile`/atomic | "Spinlock" sounds safe, and "it works on my build" depends on the compiler |
| L1/L6 Arithmetic at a trust boundary | F5 `uint8_t` length sum wraps, silenced by a cast | The cast was added to quiet `-Wconversion`, which was reporting this bug |
| L1 Time | F6 deadline compared with `>` across the `uint32_t` millisecond wrap | Only wrong after 49.7 days of uptime |
| L5 Wire compatibility | F7 telemetry struct `memcpy`'d onto the wire (padding, layout) | Same compiler on both ends of the test |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "Aligned to the cache line, so DMA-safe." | Aligned isn't enough: the buffer must also *own* every line it touches. |
| "I invalidate before reading." | That's right for RX. TX needs a *clean*, and the PR does neither for TX. |
| "A spinlock protects shared data." | Not against an interrupt on the same core: the ISR spins forever. |
| "It's a simple bool flag." | Without `volatile`/atomic, GCC hangs and Clang deletes the loop. |
| "Cast to silence the warning." | The warning was the bug report. |
| "`now > deadline`" | Not across a wrap. Elapsed time is `now - start`. |
| "`memcpy` the struct, it's faster." | Padding and layout become the wire format. |

---

## 1. First principles

1. **Cache maintenance is per line, not per byte.** CMSIS documents `SCB_InvalidateDCache_by_Addr` and `SCB_CleanDCache_by_Addr` with: "The address is aligned to 32-byte boundary." Invalidating a buffer therefore discards *every* byte of every line it overlaps, including neighbouring variables the CPU has written but not yet written back.
2. **The DMA sees RAM, the CPU sees the cache.** RX: the DMA writes RAM, so the CPU must invalidate *after* the transfer to read it. TX: the CPU's writes may still be only in the cache, so it must *clean* *before* the DMA reads. A dirty line evicted during an RX transfer writes the CPU's stale copy over the DMA's data.
3. **A DMA buffer must own its lines.** Start it on a line boundary, round its size up to whole lines, and put nothing else in those lines. Alternatively, place DMA buffers in an MPU region marked non-cacheable.
4. **An ISR preempts the code it interrupts, on the same core.** If the task holds a lock and the ISR spins on it, the task never runs again to release it. The task must instead mask the interrupt (PRIMASK or BASEPRI) around the shared state.
5. **The compiler may assume an unobservable loop terminates.** cppreference (C): "A program with an endless loop has undefined behavior if the loop has no observable behavior (I/O, volatile accesses, atomic or synchronization operation) in any part of its statement or expression. This allows the compilers to optimize out all unobservable loops without proving that they terminate." A loop polling a plain `bool` that only an ISR writes is such a loop.
6. **Narrow arithmetic wraps before you compare.** `uint8_t total = 4 + len + 2` is 0 for `len = 250`. Compute in `int` (or wider) and compare without narrowing.
7. **Elapsed time is a subtraction.** With a free-running `uint32_t` counter, `now - start > timeout` is correct across the wrap. `now > start + timeout` is not.
8. **Structs aren't wire formats.** Padding and member layout are compiler/ABI choices, and padding bytes carry whatever was in memory. Serialize field by field.

---

## 2. The PR

> **FW-318 · DMA for the host link**
>
> The polled UART blocks the motor task for ~2 ms per telemetry frame at 115,200 baud, and the control loop's jitter budget is 200 µs. Move RX and TX to DMA. While there: the PC-side encoder needs the same frame-length check as the firmware, so make it public. The failsafe check runs at 1 kHz, so make it cheaper.
>
> **PR description, by the author:**
> - RX: DMA into a buffer in DMA-capable SRAM (`hal_dma_alloc`). The RX state (sequence, counters, buffer) is grouped into one cache-line-aligned struct. The buffer is invalidated before parsing.
> - TX: `uart_link_send_telemetry` returns immediately. Frames queue while the DMA is busy, and the TX-complete ISR starts the next one. The queue is protected by `s_tx_lock`.
> - `uart_link_flush()` waits for TX to go idle (called before low-power entry).
> - `uart_link_frame_fits()` is public for the PC encoder. A cast keeps `-Wconversion` quiet.
> - Failsafe: a precomputed `s_deadline_ms`, so the 1 kHz tick does one comparison.
> - Telemetry: one `memcpy` of the record instead of field-by-field packing.
> - Tests rewritten for the DMA host model. All green on GCC and Clang.
>
> **Context the reviewer can discover:** the target is a Cortex-M7 with the D-cache enabled. `hal.h` says maintenance works on 32-byte lines. The PC retransmits a command if it gets no ACK within 50 ms, which is why `last_seq` exists. The protocol document fixes telemetry at 8 packed little-endian bytes. Controllers in the field run for months between reboots. The failsafe is the safety function that stops the motor when the operator's link drops.

---

## 3. The diff

```diff
diff --git a/firmware/link/src/uart_link.c b/firmware/link/src/uart_link.c
index b2f31a8..7baf8cc 100644
--- a/firmware/link/src/uart_link.c
+++ b/firmware/link/src/uart_link.c
@@ -1,4 +1,4 @@
-// uart_link.c - command link to the host PC: fixed 24-byte frames over a polled UART.
+// uart_link.c - command link to the host PC: fixed 24-byte frames over UART, received and sent by DMA (FW-318).
 #include "uart_link.h"
 
 #include <string.h>
@@ -6,25 +6,41 @@
 #include "hal.h"
 #include "motor.h"
 
-static uint8_t s_last_seq; // highest command sequence applied; duplicates and replays are dropped
-static uint16_t s_crc_errors;
-static uint32_t s_frames_ok;
+typedef struct {
+    uint8_t last_seq;                // highest command sequence applied; duplicates and replays are dropped
+    uint8_t dma_buf[UART_FRAME_LEN]; // the RX DMA writes each frame here
+    uint16_t crc_errors;
+    uint32_t frames_ok;
+} rx_state_t;
+
+static rx_state_t* s_rx;  // DMA memory, cache-line aligned: the whole RX state in one place
+static uint8_t* s_tx_buf; // DMA memory: the frame the TX DMA is sending
+static uint8_t s_tx_queue[TX_QUEUE_DEPTH][UART_FRAME_LEN];
+static uint8_t s_tx_count;
+static bool s_tx_idle;
+static hal_spinlock_t s_tx_lock; // TX queue: shared by uart_link_send_telemetry() and the TX-complete ISR
 static uint8_t s_tx_seq;
-static uint32_t s_last_cmd_ms;
+static uint32_t s_deadline_ms; // failsafe deadline, pushed out by every applied command
+static volatile bool s_rx_ready;
 static motor_config_t s_config;
 
+bool uart_link_frame_fits(uint8_t payload_len) {
+    uint8_t total = (uint8_t)(FRAME_HEADER_LEN + payload_len + FRAME_CRC_LEN);
+    return total <= UART_FRAME_LEN;
+}
+
 static void handle_frame(const uint8_t* f) {
-    if (f[0] != FRAME_SYNC || f[1] > FRAME_MAX_PAYLOAD || !frame_crc_ok(f)) {
-        s_crc_errors++;
+    if (f[0] != FRAME_SYNC || !uart_link_frame_fits(f[1]) || !frame_crc_ok(f)) {
+        s_rx->crc_errors++;
         return;
     }
-    uint8_t ahead = (uint8_t)(f[2] - s_last_seq); // serial-number arithmetic: 1..127 means newer
+    uint8_t ahead = (uint8_t)(f[2] - s_rx->last_seq); // serial-number arithmetic: 1..127 means newer
     if (ahead == 0 || ahead >= 128) {
         return; // duplicate or replay
     }
-    s_last_seq = f[2];
-    s_frames_ok++;
-    s_last_cmd_ms = hal_millis();
+    s_rx->last_seq = f[2];
+    s_rx->frames_ok++;
+    s_deadline_ms = hal_millis() + LINK_TIMEOUT_MS;
     if (f[3] == CMD_SET_SPEED) {
         motor_set_speed((int16_t)get_u16le(f + FRAME_HEADER_LEN));
     } else if (f[3] == CMD_SET_CONFIG) {
@@ -34,36 +50,70 @@ static void handle_frame(const uint8_t* f) {
 }
 
 void uart_link_init(void) {
-    s_last_seq = 0;
-    s_crc_errors = 0;
-    s_frames_ok = 0;
+    s_rx = hal_dma_alloc(sizeof *s_rx, DCACHE_LINE);
+    memset(s_rx, 0, sizeof *s_rx);
+    s_tx_buf = hal_dma_alloc(UART_FRAME_LEN, DCACHE_LINE);
+    s_tx_count = 0;
+    s_tx_idle = true;
     s_tx_seq = 0;
-    s_last_cmd_ms = hal_millis();
+    s_deadline_ms = hal_millis() + LINK_TIMEOUT_MS;
+    s_rx_ready = false;
+    hal_dma_rx_start(s_rx->dma_buf, UART_FRAME_LEN);
 }
 
+void DMA_RX_IRQHandler(void) { s_rx_ready = true; } // a whole frame has landed in s_rx->dma_buf
+
 void uart_link_poll(void) { // task context
-    uint8_t frame[UART_FRAME_LEN];
-    if (hal_uart_read(frame, sizeof frame)) {
-        handle_frame(frame);
+    if (!s_rx_ready) {
+        return;
     }
+    s_rx_ready = false;
+    SCB_InvalidateDCache_by_Addr(s_rx->dma_buf, UART_FRAME_LEN); // read what the DMA wrote, not stale cache lines
+    handle_frame(s_rx->dma_buf);
+    hal_dma_rx_start(s_rx->dma_buf, UART_FRAME_LEN);
 }
 
 void uart_link_tick(void) { // 1 kHz control loop
-    if (hal_millis() - s_last_cmd_ms > LINK_TIMEOUT_MS) {
+    if (hal_millis() > s_deadline_ms) {
         motor_failsafe();
     }
 }
 
-void uart_link_send_telemetry(const telemetry_t* t) { // task context
-    uint8_t frame[UART_FRAME_LEN] = {FRAME_SYNC, TELEMETRY_WIRE_LEN, 0, CMD_TELEMETRY};
-    uint8_t* p = frame + FRAME_HEADER_LEN;
+static void tx_start(const uint8_t* frame) { // with s_tx_lock held
+    memcpy(s_tx_buf, frame, UART_FRAME_LEN);
+    hal_dma_tx_start(s_tx_buf, UART_FRAME_LEN);
+}
+
+void uart_link_send_telemetry(const telemetry_t* t) { // task context; returns without waiting for the UART
+    uint8_t frame[UART_FRAME_LEN] = {FRAME_SYNC, sizeof *t, 0, CMD_TELEMETRY};
     frame[2] = s_tx_seq++;
-    p[0] = t->state; // the protocol's packed little-endian layout, field by field
-    put_u32le(p + 1, t->uptime_ms);
-    put_u16le(p + 5, (uint16_t)t->current_ma);
-    p[7] = t->temp_c;
+    memcpy(frame + FRAME_HEADER_LEN, t, sizeof *t); // one copy instead of field-by-field packing
     frame_seal(frame);
-    hal_uart_write(frame, sizeof frame); // blocks the task for ~2 ms at 115200 baud
+    hal_spin_lock(&s_tx_lock);
+    if (s_tx_idle) {
+        s_tx_idle = false;
+        tx_start(frame);
+    } else if (s_tx_count < TX_QUEUE_DEPTH) {
+        memcpy(s_tx_queue[s_tx_count++], frame, UART_FRAME_LEN);
+    }
+    hal_spin_unlock(&s_tx_lock);
+}
+
+void DMA_TX_IRQHandler(void) { // TX DMA complete: start the next queued frame
+    hal_spin_lock(&s_tx_lock);
+    if (s_tx_count > 0) {
+        tx_start(s_tx_queue[0]);
+        s_tx_count--;
+        memmove(s_tx_queue[0], s_tx_queue[1], (size_t)s_tx_count * UART_FRAME_LEN);
+    } else {
+        s_tx_idle = true;
+    }
+    hal_spin_unlock(&s_tx_lock);
+}
+
+void uart_link_flush(void) { // before low-power entry
+    while (!s_tx_idle) {
+    }
 }
 
-uint16_t uart_link_crc_errors(void) { return s_crc_errors; }
+uint16_t uart_link_crc_errors(void) { return s_rx->crc_errors; }
diff --git a/firmware/link/src/uart_link.h b/firmware/link/src/uart_link.h
index 95e9aa2..474329c 100644
--- a/firmware/link/src/uart_link.h
+++ b/firmware/link/src/uart_link.h
@@ -1,13 +1,20 @@
 #pragma once
 // uart_link.h - command link to the host PC (speed and tuning commands in, telemetry out).
+#include <stdbool.h>
 #include <stdint.h>
 
 #include "frame.h"
 
 #define LINK_TIMEOUT_MS 100u // no valid command for this long: motor failsafe
+#define TX_QUEUE_DEPTH 4
 
 void uart_link_init(void);
 void uart_link_poll(void); // task context: handles a received frame, if any
 void uart_link_tick(void); // 1 kHz control loop: link-loss failsafe
 void uart_link_send_telemetry(const telemetry_t* t);
+void uart_link_flush(void); // waits until the TX DMA is idle (called before low-power entry)
+bool uart_link_frame_fits(uint8_t payload_len); // shared with the PC-side encoder
 uint16_t uart_link_crc_errors(void);
+
+void DMA_RX_IRQHandler(void); // vector table entries
+void DMA_TX_IRQHandler(void);
diff --git a/firmware/link/test/uart_link_test.c b/firmware/link/test/uart_link_test.c
index 46d3709..53b8a4a 100644
--- a/firmware/link/test/uart_link_test.c
+++ b/firmware/link/test/uart_link_test.c
@@ -1,4 +1,4 @@
-// uart_link_test.c - host unit tests for the command link (hal_host.c models the hardware).
+// uart_link_test.c - host unit tests for the command link (hal_host.c models the hardware, DMA and cache included).
 #include "check.h"
 #include "hal_host.h"
 #include "link_frames.h"
@@ -6,11 +6,13 @@
 
 static void setup(void) {
     hal_host_reset();
+    hal_host_set_irq_handlers(DMA_RX_IRQHandler, DMA_TX_IRQHandler);
     uart_link_init();
 }
 
 static void receive(const uint8_t* f) {
-    hal_host_uart_inject(f, UART_FRAME_LEN);
+    hal_host_dma_rx_deliver(f, UART_FRAME_LEN);
+    hal_host_run_irqs();
     uart_link_poll();
 }
 
@@ -22,16 +24,6 @@ static void applies_speed_command(void) {
     CHECK(g_host.motor_rpm == 1500);
 }
 
-static void drops_duplicate_sequence(void) {
-    setup();
-    uint8_t f[UART_FRAME_LEN];
-    speed_frame(f, 1, 1500);
-    receive(f);
-    speed_frame(f, 1, 2000);
-    receive(f);
-    CHECK(g_host.motor_rpm == 1500);
-}
-
 static void rejects_bad_crc(void) {
     setup();
     uint8_t f[UART_FRAME_LEN];
@@ -46,11 +38,24 @@ static void sends_telemetry(void) {
     setup();
     telemetry_t t = {2, 123456, 1200, 41};
     uart_link_send_telemetry(&t);
+    hal_host_dma_tx_complete();
     CHECK(g_host.wire_frames == 1);
-    CHECK(g_host.wire[0][1] == TELEMETRY_WIRE_LEN);
+    CHECK(g_host.wire[0][1] == sizeof(telemetry_t));
     CHECK(frame_crc_ok(g_host.wire[0]));
 }
 
+static void queues_while_busy(void) {
+    setup();
+    telemetry_t t = {2, 1000, 1200, 41};
+    uart_link_send_telemetry(&t);
+    uart_link_send_telemetry(&t); // DMA still busy: queued
+    hal_host_dma_tx_complete();
+    hal_host_run_irqs(); // the TX-complete ISR starts the queued frame
+    hal_host_dma_tx_complete();
+    hal_host_run_irqs();
+    CHECK(g_host.wire_frames == 2);
+}
+
 static void failsafe_after_timeout(void) {
     setup();
     hal_host_set_millis(1000);
@@ -62,11 +67,24 @@ static void failsafe_after_timeout(void) {
     CHECK(g_host.failsafes == 1);
 }
 
+static void flush_returns_when_idle(void) {
+    setup();
+    uart_link_flush();
+    CHECK(g_host.wire_frames == 0);
+}
+
+static void frame_fits_limits(void) {
+    CHECK(uart_link_frame_fits(FRAME_MAX_PAYLOAD));
+    CHECK(!uart_link_frame_fits(FRAME_MAX_PAYLOAD + 1));
+}
+
 int main(void) {
     RUN(applies_speed_command);
-    RUN(drops_duplicate_sequence);
     RUN(rejects_bad_crc);
     RUN(sends_telemetry);
+    RUN(queues_while_busy);
     RUN(failsafe_after_timeout);
+    RUN(flush_returns_when_idle);
+    RUN(frame_fits_limits);
     return finish();
 }
```

---

## 4. The author's tests: green

```text
ok   applies_speed_command
ok   rejects_bad_crc
ok   sends_telemetry
ok   queues_while_busy
ok   failsafe_after_timeout
ok   flush_returns_when_idle
ok   frame_fits_limits
7 passed, 0 failed
```

What they never do: receive a frame *after* the CPU has written `last_seq` (the duplicate test from the polled version was not carried over, and the diff shows it deleted). Send two frames and compare their contents (`queues_while_busy` counts frames only). Take an interrupt while `uart_link_send_telemetry` holds the lock. Run near the millisecond wrap. Ask `frame_fits` about anything above 19. `sends_telemetry` asserts `wire[0][1] == sizeof(telemetry_t)`, which pins the defect (F7) into the test: it is the one PR test that fails against the fixed code.

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** who owns the RX buffer's cache lines, when the CPU and DMA views are synchronized (RX and TX), how the TX queue is shared with an ISR, what a polled flag guarantees, the length check's arithmetic, failsafe time arithmetic, and the telemetry wire layout.
- **Hunk scores:** `rx_state_t` + `uart_link_poll` 8/8, `uart_link_send_telemetry` + `DMA_TX_IRQHandler` 8/8, `uart_link_frame_fits` 6/8, `uart_link_tick` 6/8, `uart_link_flush` 4/8.
- **Radar hits:** a DMA buffer *inside* a struct with other fields (9–14). `hal_dma_tx_start` with no clean anywhere (84). `hal_spin_lock` in an `_IRQHandler` (103). `static bool s_tx_idle` (20) next to `static volatile bool s_rx_ready` (24). `(uint8_t)(…)` cast in a bounds check (28). `hal_millis() > s_deadline_ms` (77). `memcpy(frame + …, t, sizeof *t)` (90).

### Minute 10: one hop each

- The invalidate on line 71 covers `dma_buf`'s lines, which also hold `last_seq` and the counters. What happens to the CPU's last write to `last_seq`? It's discarded. Replay check defeated: F1.
- Who writes the TX frame back from the cache before the DMA reads it? Nobody: F2.
- What happens when the TX-complete IRQ fires while the task is between lines 92 and 99? The ISR spins on line 103 forever: F3.
- What stops the compiler from reading `s_tx_idle` once? Nothing: F4.
- What is `(uint8_t)(4 + 250 + 2)`? 0: F5.
- What is `s_deadline_ms` when a command arrives 50 ms before the wrap? It's 50, while `now` is about 4.29 billion, so the next tick trips the failsafe on a healthy link: F6.
- Is `sizeof(telemetry_t)` 8? It's 12, with 3 + 1 padding bytes: F7.

### Minute 20: prove, unify, fix

- **Unify:** every defect is a missing statement of *who owns what, when*. The cache line (F1) and the bytes in RAM vs the cache (F2) on the DMA side. The CPU, between task and ISR (F3, F4). The range of a value: 8 bits (F5), 32 bits of time (F6). The byte layout on the wire (F7). Firmware review is ownership review at the hardware level.
- **Fix shape:** DMA buffers that own whole lines, with counters and sequence state moved out; invalidate after RX and clean before TX; mask the TX IRQ in task context, with no lock in the ISR; `atomic_bool` with acquire/release for the idle flag; compute lengths in `int`; `now - last > timeout`; explicit little-endian serialization.

---

## 6. The L7 answer key, line by line

### F1 · L3 · Sev-1 · The RX DMA buffer shares its cache line with `last_seq`, so invalidation undoes the replay check and eviction destroys received frames (uart_link.c 9–16, 53, 71)

**Mechanism.** `rx_state_t` puts `last_seq` at offset 0, `dma_buf` at 1–24 and the counters at 26–31: one 32-byte line. The struct is line-aligned, but the buffer doesn't own the line. Two failures follow.

1. **Invalidate discards the CPU's writes.** After a frame is handled, `last_seq` and `frames_ok` are updated in the cache only (the line is dirty). On the next frame, line 71 invalidates the buffer's line, which throws those updates away. `last_seq` reverts to the RAM value (0), so a late retransmission of an older command passes the replay check. Concretely: RUN (seq 1), STOP (seq 2), then the PC's retransmission of seq 1 restarts the motor.
2. **Eviction overwrites the DMA's data.** If the dirty line is evicted while a frame sits in RAM, the CPU's stale copy of the whole line (old buffer bytes included) is written over the DMA's bytes. The CPU then reads the *previous* frame back, the replay check drops it as a duplicate, and the new command is lost without a CRC error.

**Evidence.** P1 (replay): PR `motor = 3000 rpm` after STOP; fix `0 rpm`. P1 (eviction): PR `motor = 1000 rpm, CRC errors = 0` (seq 2 = 500 rpm silently lost); fix `500 rpm`.

```comment-l7
issue (blocking): dma_buf shares its 32-byte cache line with last_seq and the counters, so invalidating the buffer discards the CPU's update to last_seq and a retransmitted old command passes the replay check

Maintenance works on whole lines (hal.h, CMSIS: "aligned to 32-byte boundary"), which means line 71 rolls last_seq back to its RAM value every frame; the probe scenario RUN(seq 1), STOP(seq 2), retransmitted RUN(seq 1) ends with the motor at 3000 rpm. The reverse also happens: evicting the dirty line mid-transfer overwrites the received frame (probe: the 500 rpm command is lost with no CRC error). Suggest giving the DMA a buffer that owns its lines: allocate it alone, size rounded up to DCACHE_LINE, and move last_seq and the counters into ordinary statics.
```

**Fix.**
```c
#define DMA_BUF_LEN ((UART_FRAME_LEN + DCACHE_LINE - 1) / DCACHE_LINE * DCACHE_LINE)
```
```c
static uint8_t* s_rx_dma; // DMA memory, DMA_BUF_LEN bytes, line-aligned: nothing else lives in its lines
static uint8_t s_last_seq; // highest command sequence applied; duplicates and replays are dropped
```
```c
    s_rx_dma = hal_dma_alloc(DMA_BUF_LEN, DCACHE_LINE);
```
```c
    SCB_InvalidateDCache_by_Addr(s_rx_dma, DMA_BUF_LEN); // after the transfer: read what the DMA wrote
```

### F2 · L3 · Sev-2 · TX frames are never cleaned from the cache, so the DMA transmits whatever RAM held: the previous frame, with a valid CRC (uart_link.c 82–85)

**Mechanism.** `tx_start` copies the frame into `s_tx_buf` and starts the DMA. The copy lands in the D-cache (write-back), but the DMA reads RAM. The first frame after boot goes out correctly (the line was clean), and every later frame transmits RAM's stale contents: the previous frame, byte for byte, CRC included. The PC can't detect it, so telemetry silently repeats old values. A motor at 3,400 mA reports 1,200 mA.

**Evidence.** P2: PR `second frame on the wire is a byte-for-byte copy of the first: yes (sequence byte 0, CRC valid: yes)`. Fix: `no (sequence byte 1, CRC valid: yes)`.

```comment-l7
issue (blocking): tx_start never cleans s_tx_buf before hal_dma_tx_start, so the DMA sends RAM's stale bytes instead of the frame the CPU wrote

The memcpy lands in the write-back cache and the DMA reads RAM, which means every frame after the first repeats the previous one, CRC and all, so the PC accepts it (probe: the 3400 mA frame goes out as an exact copy of the 1200 mA one). Suggest SCB_CleanDCache_by_Addr over the whole line-owning buffer between the memcpy and the DMA start, in both the task and ISR paths.
```

**Fix.**
```c
static void tx_start(const uint8_t* frame) { // TX DMA idle; task context with interrupts masked, or the TX ISR
    memcpy(s_tx_dma, frame, UART_FRAME_LEN);
    SCB_CleanDCache_by_Addr(s_tx_dma, DMA_BUF_LEN); // the DMA reads RAM: push the frame out of the cache first
    hal_dma_tx_start(s_tx_dma, UART_FRAME_LEN);
}
```

### F3 · L2 · Sev-1 · Task and ISR share a spinlock on a single core: a TX-complete interrupt inside the critical section spins forever (uart_link.c 92–99, 103)

**Mechanism.** `uart_link_send_telemetry` takes `s_tx_lock`. If the TX DMA finishes in that window, its IRQ preempts the task, and `DMA_TX_IRQHandler` spins on the same lock. The holder is the code the ISR interrupted, which can't run until the ISR returns. On a single core that spin never ends. The watchdog resets the controller mid-move, and the window recurs whenever telemetry is sent at a rate comparable to the frame time.

**Evidence.** P3: PR `deadlocks = 1, frames on the wire = 1 of 2`. The model detects the spin that can never end, abandons the ISR, and the second frame is stranded. Fix: `deadlocks = 0, frames on the wire = 2 of 2`.

```comment-l7
issue (blocking): DMA_TX_IRQHandler takes s_tx_lock, which uart_link_send_telemetry holds with the TX interrupt enabled, so a TX-complete interrupt inside that window spins forever

On one core the lock holder can't run until the ISR returns, which means the spin never ends and the watchdog resets the controller (probe: completion pended, then a second send, gives deadlocks = 1 and the queued frame never leaves). Suggest masking interrupts in the task's critical section (hal_irq_save/restore around the queue) and taking no lock in the ISR; a spinlock only makes sense across cores, and there it needs the irqsave form.
```

**Fix.**
```c
    uint32_t irq = hal_irq_save(); // the TX ISR runs on this core: mask it rather than share a lock with it
    if (atomic_load_explicit(&s_tx_idle, memory_order_relaxed)) {
        atomic_store_explicit(&s_tx_idle, false, memory_order_relaxed);
        tx_start(frame);
    } else if (s_tx_count < TX_QUEUE_DEPTH) {
        memcpy(s_tx_queue[s_tx_count++], frame, UART_FRAME_LEN);
    }
    hal_irq_restore(irq);
```

### F4 · L2 · Sev-1 · `s_tx_idle` is a plain `bool` polled in a tight loop: GCC turns `uart_link_flush` into an infinite loop and Clang deletes the loop (uart_link.c 20, 114–117)

**Mechanism.** The loop body has no observable behavior, so the compiler may read `s_tx_idle` once (C's forward-progress rule, §1). The two compilers used here make different choices, and both are wrong for the firmware. GCC 16 checks once and then jumps to itself forever: called while TX is busy, `flush` hangs until the watchdog fires. Clang 21 removes the loop entirely: `flush` returns at once, the firmware enters low-power mode with a frame half-sent, and the UART clock stops mid-byte. The author made `s_rx_ready` `volatile` but not `s_tx_idle`, and host tests can't run either path.

**Evidence.** §8.2, PR. Cortex-M7 (Clang 21): `uart_link_flush` is a single `bx lr`. x86-64 (GCC 16): `cmp BYTE PTR s_tx_idle[rip], 0` / `je .L52` / `ret` / `.L52: jmp .L52`. Fix on both targets: a load inside the loop (`ldrb` + `dmb sy` on the M7, `movzx` + `test` + `je` on x86-64).

```comment-l7
issue (blocking): s_tx_idle is a plain bool written by the TX ISR and polled in uart_link_flush's empty loop, so the compiler may read it once: GCC compiles the loop to a jump-to-self and Clang removes it

A loop with no observable behavior may be assumed to terminate, which means flush either hangs forever with TX busy (GCC: cmp, je .L52, .L52: jmp .L52) or returns immediately and we power down mid-frame (Clang for Cortex-M7: bx lr); the asm probe in the thread has both compilers' output. Suggest atomic_bool with a release store in the ISR and an acquire load in the loop, which also orders the queue state; volatile alone would fix the reload but not the ordering.
```

**Fix.**
```c
static atomic_bool s_tx_idle; // written by the TX ISR, polled by uart_link_flush()
```
```c
void uart_link_flush(void) { // before low-power entry
    while (!atomic_load_explicit(&s_tx_idle, memory_order_acquire)) {
    }
}
```

### F5 · L6 · Sev-1 · `uint8_t` arithmetic in `uart_link_frame_fits` wraps to 0 for lengths 250–255, so the CONFIG handler copies up to 255 bytes into an 18-byte struct (uart_link.c 27–30, 47)

**Mechanism.** `(uint8_t)(4 + len + 2)` truncates. For `len` 250–255 the total is 0–5, and `<= 24` passes. The frame CRC covers a fixed 22 bytes, so anyone who can write to the serial port can build a valid frame with `len = 250` and `CMD_SET_CONFIG`. Line 47 then copies 250 bytes from a 24-byte DMA buffer into the 18-byte `s_config`: an out-of-bounds read, and a write over whatever follows it in `.bss`. The cast exists because `-Wconversion` flagged the narrowing. The warning was correct.

**Evidence.** P5: PR `uart_link_frame_fits(250) = true`. Fix: `false`. The probe calls only the check and never executes the copy. §8.2: GCC compiles the PR's check to `add ecx, 6` / `cmp cl, 24`, an 8-bit compare. Clang's `subs r0, #250` / `cmn.w r0, #231` / `lo` computes exactly "true unless 19 ≤ len ≤ 249." In the fix, both compilers emit a plain `cmp` against 18 or 19.

```comment-l7
issue (blocking): uart_link_frame_fits sums the lengths in uint8_t, so 4 + 250 + 2 wraps to 0 and the check accepts payload lengths 250-255

The CRC covers a fixed 22 bytes, which means a well-formed frame from anyone on the serial link with len = 250 and CMD_SET_CONFIG reaches the memcpy on line 47 and copies 250 bytes into the 18-byte s_config (probe: frame_fits(250) returns true; the copy itself is not executed). The (uint8_t) cast was silencing -Wconversion's report of exactly this narrowing. Suggest computing in int, `FRAME_HEADER_LEN + payload_len + FRAME_CRC_LEN <= UART_FRAME_LEN`, and a test for 250.
```

**Fix.**
```c
bool uart_link_frame_fits(uint8_t payload_len) {
    return FRAME_HEADER_LEN + payload_len + FRAME_CRC_LEN <= UART_FRAME_LEN; // in int: no narrowing before the compare
}
```

### F6 · L1 · Sev-2 · `hal_millis() > s_deadline_ms` breaks across the 32-bit millisecond wrap: valid commands trip the failsafe (uart_link.c 43, 77)

**Mechanism.** The deadline is `now + 100`, computed modulo 2³², and compared with `>`. A command in the last 100 ms before the wrap gets a deadline that has already wrapped. For example, a command at 4,294,967,246 ms (50 ms before the wrap) gets deadline 50, while `now` is still about 4.29 billion. The next 1 kHz tick sees `now > deadline` and trips the failsafe on a healthy link, so the motor coasts to a stop and latches a fault. Every device crosses this point every 49.7 days of uptime. With commands arriving every 50 ms during operation, a device that's running at that moment almost certainly trips. Across a large fleet that's a steady trickle of unexplained stops that never reproduce in the lab. A second, rarer failure: if the control loop ever stalls across the wrap (a blocking flash erase, a debugger halt), an unwrapped deadline is compared against a wrapped `now`, and the failsafe stays silent for 49.7 days. The polled code's `hal_millis() - s_last_cmd_ms > LINK_TIMEOUT_MS` was correct in both cases. The "cheaper" form saves one subtraction.

**Evidence.** P6: a valid command 50 ms before the wrap, and the next tick 1 ms later. PR `failsafe fired = yes, motor = 0 rpm`. Fix: `no, motor = 1500 rpm`. The fixed suite checks both directions across the wrap: no trip 1 ms after the command, and a trip 101 ms after it.

```comment-l7
issue (blocking): the failsafe compares hal_millis() > s_deadline_ms, so a command in the last 100 ms before the 32-bit millisecond wrap gets a wrapped deadline and the next tick trips the failsafe on a healthy link

The deadline wraps to a small value while hal_millis() is still near 2^32, which means every running device stops itself once per 49.7 days of uptime (probe: command 50 ms before the wrap, failsafe fires 1 ms later, motor 0 rpm). If the loop ever stalls across the wrap the opposite happens and the failsafe stays silent. The previous `hal_millis() - s_last_cmd_ms > LINK_TIMEOUT_MS` handles both and costs one subtraction. Suggest restoring it, plus tests seeded at 0xFFFFFFCE.
```

**Fix.**
```c
    if (hal_millis() - s_last_cmd_ms > LINK_TIMEOUT_MS) { // elapsed time by subtraction: correct across the wrap
```
```c
    s_last_cmd_ms = hal_millis();
```

### F7 · L5 · Sev-2 · Telemetry is `memcpy`'d as a C struct: 12 bytes with padding instead of the protocol's 8 packed bytes (uart_link.c 88–90)

**Mechanism.** `telemetry_t` is `{uint8_t; uint32_t; int16_t; uint8_t}`. Natural alignment puts 3 padding bytes after `state` and 1 at the end: `sizeof` is 12, and `uptime_ms` sits at offset 4. The protocol says 8 bytes with `uptime_ms` at offset 1. Every PC decoder misreads every field after `state`. The padding bytes go out on the wire carrying leftover stack contents. The wire format would also change silently with a compiler, ABI or field reorder. The author's test asserts `sizeof(telemetry_t)`, so it locks the bug in.

**Evidence.** P7: PR `payload length byte = 12 (protocol: 8); uptime_ms found at payload offset 4 (protocol: 1)`. Fix: `8 … offset 1`. `fixed-vs-pr-tests`: the PR's `sends_telemetry` fails against the fix on exactly that assertion.

```comment-l7
issue (blocking): telemetry is sent as memcpy(frame, t, sizeof *t), so the wire format becomes the compiler's struct layout: 12 bytes with padding, uptime at offset 4, where the protocol specifies 8 packed bytes with uptime at offset 1

The PC decoder follows the protocol document, which means every field after state is misread, and the 4 padding bytes transmit leftover stack data (probe: length byte 12, uptime found at offset 4). Suggest keeping the field-by-field put_u32le/put_u16le packing from the polled version (it costs a few cycles per frame), and changing the test to assert TELEMETRY_WIRE_LEN and the field offsets instead of sizeof(telemetry_t).
```

**Fix.**
```c
    uint8_t frame[UART_FRAME_LEN] = {FRAME_SYNC, TELEMETRY_WIRE_LEN, 0, CMD_TELEMETRY};
    uint8_t* p = frame + FRAME_HEADER_LEN;
    frame[2] = s_tx_seq++;
    p[0] = t->state; // the protocol's packed little-endian layout, field by field
    put_u32le(p + 1, t->uptime_ms);
    put_u16le(p + 5, (uint16_t)t->current_ma);
    p[7] = t->temp_c;
```

### D1 · Decoy · Invalidating the RX buffer before parsing is correct; "clean-invalidate it instead" would be a bug

Line 71's *intent* is right: after an RX transfer, invalidate, then read. Some reviewers suggest `SCB_CleanInvalidateDCache_by_Addr` "to be safe." On an RX buffer that writes the cache's stale copy back over the bytes the DMA just delivered, which is F1's eviction failure on purpose. The finding on line 71 is the *line sharing* (F1), not the operation. Likewise, `volatile bool s_rx_ready` is adequate: it is read once per poll, and the opaque maintenance call that follows keeps the compiler from moving buffer reads ahead of it.

### T1 · Tests

The rewrite dropped `drops_duplicate_sequence`, which would have failed on the PR because of F1. The remaining tests count frames instead of comparing them (hiding F2), never take an interrupt inside a critical section (F3), never run near the wrap (F6), test `frame_fits` only up to 19 (F5), and assert the struct size (F7).

```comment-l7
todo (blocking): the rewrite deleted drops_duplicate_sequence, and the new tests count frames, stay away from the millisecond wrap, and assert sizeof(telemetry_t), so none of the DMA, interrupt or arithmetic paths can fail

This means the replay, stale-TX, deadlock, wrap and overflow defects all pass CI. Suggest: restoring the duplicate test plus a RUN/STOP/retransmit scenario; an eviction step in the host model; comparing the second frame's sequence byte; pending the TX IRQ before a second send; failsafe tests seeded at 0xFFFFFFCE; frame_fits(250); and asserting the protocol layout. Run the suite on the target with the D-cache enabled too.
```

---

## 7. The refactored code

```c
// ===== firmware/link/src/uart_link.c =====
// uart_link.c - command link to the host PC: fixed 24-byte frames over UART, received and sent by DMA (FW-318).
#include "uart_link.h"

#include <stdatomic.h>
#include <string.h>

#include "hal.h"
#include "motor.h"

// Cache maintenance works on whole 32-byte lines, so each DMA buffer owns its lines outright: a buffer sharing a line
// with other data would discard that data on invalidate and overwrite received bytes when the line is evicted.
#define DMA_BUF_LEN ((UART_FRAME_LEN + DCACHE_LINE - 1) / DCACHE_LINE * DCACHE_LINE)

static uint8_t* s_rx_dma; // DMA memory, DMA_BUF_LEN bytes, line-aligned: nothing else lives in its lines
static uint8_t* s_tx_dma; // likewise, for the TX DMA
static uint8_t s_last_seq; // highest command sequence applied; duplicates and replays are dropped
static uint16_t s_crc_errors;
static uint32_t s_frames_ok;
static uint8_t s_tx_queue[TX_QUEUE_DEPTH][UART_FRAME_LEN];
static uint8_t s_tx_count; // task touches it only with interrupts masked; the TX ISR is the other user
static atomic_bool s_tx_idle; // written by the TX ISR, polled by uart_link_flush()
static uint8_t s_tx_seq;
static uint32_t s_last_cmd_ms;
static volatile bool s_rx_ready;
static motor_config_t s_config;

bool uart_link_frame_fits(uint8_t payload_len) {
    return FRAME_HEADER_LEN + payload_len + FRAME_CRC_LEN <= UART_FRAME_LEN; // in int: no narrowing before the compare
}

static void handle_frame(const uint8_t* f) {
    if (f[0] != FRAME_SYNC || !uart_link_frame_fits(f[1]) || !frame_crc_ok(f)) {
        s_crc_errors++;
        return;
    }
    uint8_t ahead = (uint8_t)(f[2] - s_last_seq); // serial-number arithmetic: 1..127 means newer
    if (ahead == 0 || ahead >= 128) {
        return; // duplicate or replay
    }
    s_last_seq = f[2];
    s_frames_ok++;
    s_last_cmd_ms = hal_millis();
    if (f[3] == CMD_SET_SPEED) {
        motor_set_speed((int16_t)get_u16le(f + FRAME_HEADER_LEN));
    } else if (f[3] == CMD_SET_CONFIG) {
        memcpy(&s_config, f + FRAME_HEADER_LEN, f[1]);
        motor_apply_config(&s_config);
    }
}

void uart_link_init(void) {
    s_rx_dma = hal_dma_alloc(DMA_BUF_LEN, DCACHE_LINE);
    s_tx_dma = hal_dma_alloc(DMA_BUF_LEN, DCACHE_LINE);
    s_last_seq = 0;
    s_crc_errors = 0;
    s_frames_ok = 0;
    s_tx_count = 0;
    atomic_store(&s_tx_idle, true);
    s_tx_seq = 0;
    s_last_cmd_ms = hal_millis();
    s_rx_ready = false;
    hal_dma_rx_start(s_rx_dma, UART_FRAME_LEN);
}

void DMA_RX_IRQHandler(void) { s_rx_ready = true; } // a whole frame has landed in s_rx_dma

void uart_link_poll(void) { // task context
    if (!s_rx_ready) {
        return;
    }
    s_rx_ready = false;
    SCB_InvalidateDCache_by_Addr(s_rx_dma, DMA_BUF_LEN); // after the transfer: read what the DMA wrote
    handle_frame(s_rx_dma);
    hal_dma_rx_start(s_rx_dma, UART_FRAME_LEN);
}

void uart_link_tick(void) { // 1 kHz control loop
    if (hal_millis() - s_last_cmd_ms > LINK_TIMEOUT_MS) { // elapsed time by subtraction: correct across the wrap
        motor_failsafe();
    }
}

static void tx_start(const uint8_t* frame) { // TX DMA idle; task context with interrupts masked, or the TX ISR
    memcpy(s_tx_dma, frame, UART_FRAME_LEN);
    SCB_CleanDCache_by_Addr(s_tx_dma, DMA_BUF_LEN); // the DMA reads RAM: push the frame out of the cache first
    hal_dma_tx_start(s_tx_dma, UART_FRAME_LEN);
}

void uart_link_send_telemetry(const telemetry_t* t) { // task context; returns without waiting for the UART
    uint8_t frame[UART_FRAME_LEN] = {FRAME_SYNC, TELEMETRY_WIRE_LEN, 0, CMD_TELEMETRY};
    uint8_t* p = frame + FRAME_HEADER_LEN;
    frame[2] = s_tx_seq++;
    p[0] = t->state; // the protocol's packed little-endian layout, field by field
    put_u32le(p + 1, t->uptime_ms);
    put_u16le(p + 5, (uint16_t)t->current_ma);
    p[7] = t->temp_c;
    frame_seal(frame);
    uint32_t irq = hal_irq_save(); // the TX ISR runs on this core: mask it rather than share a lock with it
    if (atomic_load_explicit(&s_tx_idle, memory_order_relaxed)) {
        atomic_store_explicit(&s_tx_idle, false, memory_order_relaxed);
        tx_start(frame);
    } else if (s_tx_count < TX_QUEUE_DEPTH) {
        memcpy(s_tx_queue[s_tx_count++], frame, UART_FRAME_LEN);
    }
    hal_irq_restore(irq);
}

void DMA_TX_IRQHandler(void) { // TX DMA complete: start the next queued frame
    if (s_tx_count > 0) {
        tx_start(s_tx_queue[0]);
        s_tx_count--;
        memmove(s_tx_queue[0], s_tx_queue[1], (size_t)s_tx_count * UART_FRAME_LEN);
    } else {
        atomic_store_explicit(&s_tx_idle, true, memory_order_release);
    }
}

void uart_link_flush(void) { // before low-power entry
    while (!atomic_load_explicit(&s_tx_idle, memory_order_acquire)) {
    }
}

uint16_t uart_link_crc_errors(void) { return s_crc_errors; }

// ===== firmware/link/src/uart_link.h =====
#pragma once
// uart_link.h - command link to the host PC (speed and tuning commands in, telemetry out).
#include <stdbool.h>
#include <stdint.h>

#include "frame.h"

#define LINK_TIMEOUT_MS 100u // no valid command for this long: motor failsafe
#define TX_QUEUE_DEPTH 4

void uart_link_init(void);
void uart_link_poll(void); // task context: handles a received frame, if any
void uart_link_tick(void); // 1 kHz control loop: link-loss failsafe
void uart_link_send_telemetry(const telemetry_t* t);
void uart_link_flush(void); // waits until the TX DMA is idle (called before low-power entry)
bool uart_link_frame_fits(uint8_t payload_len); // shared with the PC-side encoder
uint16_t uart_link_crc_errors(void);

void DMA_RX_IRQHandler(void); // vector table entries
void DMA_TX_IRQHandler(void);
```

**Fixed suite: 13/13 on GCC (output, verified; the Clang run is identical).**

```text
ok   applies_speed_command
ok   drops_duplicate_sequence
ok   replay_after_stop_is_dropped
ok   frame_survives_cache_eviction
ok   rejects_bad_crc
ok   sends_telemetry_in_protocol_layout
ok   consecutive_frames_reach_the_wire
ok   queues_while_busy
ok   tx_complete_during_send_does_not_deadlock
ok   failsafe_after_timeout
ok   failsafe_timing_across_millis_wrap
ok   flush_returns_when_idle
ok   frame_fits_limits
13 passed, 0 failed
```

**The PR's original tests against the fix (output, verified).** Six pass. `sends_telemetry` fails because it asserts the defect (F7), so the test changes with the fix:

```text
ok   applies_speed_command
ok   rejects_bad_crc
    FAILED at line 43: g_host.wire[0][1] == sizeof(telemetry_t)
FAIL sends_telemetry
ok   queues_while_busy
ok   failsafe_after_timeout
ok   flush_returns_when_idle
ok   frame_fits_limits
6 passed, 1 failed
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| RX buffer | Inside a struct with `last_seq` and counters | Alone, line-aligned, size rounded up to whole lines |
| RX sync | Invalidate the buffer's lines (and the neighbours') | Invalidate the line-owning buffer after the transfer |
| TX sync | None | Clean after `memcpy`, before the DMA starts |
| Task ↔ ISR exclusion | Spinlock taken by both | Task masks the IRQ; the ISR takes nothing |
| Idle flag | Plain `bool` | `atomic_bool`, release in the ISR, acquire in `flush` |
| Length check | `uint8_t` sum with a silencing cast | `int` arithmetic, no narrowing |
| Failsafe | `now > now0 + timeout` | `now - now0 > timeout` |
| Telemetry | `memcpy` of the struct | Field-by-field little-endian, 8 bytes |
| Alternative for RX/TX | n/a | MPU region marked non-cacheable for DMA buffers (no maintenance at all; slower CPU access to them) |

---

## 8. Probe evidence

### 8.1 Behavior probes (host model)

**Against the PR's code (output, verified, GCC 16.2):**

```text
PR09 probes against the PR's link firmware (GCC)
P1 F1 seq 1 (3000 rpm), seq 2 (STOP), then a late retransmission of seq 1: motor = 3000 rpm
P1 F1 seq 2 (500 rpm) lands in RAM, then dirty lines are evicted: motor = 1000 rpm, CRC errors = 0
P2 F2 two telemetry frames (1200 mA, then 3400 mA): second frame on the wire is a byte-for-byte copy of the first: yes (sequence byte 0, CRC valid: yes)
P3 F3 TX-complete interrupt taken inside uart_link_send_telemetry(): deadlocks = 1, frames on the wire = 1 of 2
P5 F5 uart_link_frame_fits(250) = true (4 + 250 + 2 = 256; the payload area is 18 bytes and s_config is 18)
P6 F6 valid command 50 ms before the millisecond wrap, next tick 1 ms later: failsafe fired = yes, motor = 0 rpm
P7 F7 telemetry payload length byte = 12 (protocol: 8); uptime_ms found at payload offset 4 (protocol: 1)
```

**Against the PR's code (output, verified, Clang 21.1):**

```text
PR09 probes against the PR's link firmware (Clang)
P1 F1 seq 1 (3000 rpm), seq 2 (STOP), then a late retransmission of seq 1: motor = 3000 rpm
P1 F1 seq 2 (500 rpm) lands in RAM, then dirty lines are evicted: motor = 1000 rpm, CRC errors = 0
P2 F2 two telemetry frames (1200 mA, then 3400 mA): second frame on the wire is a byte-for-byte copy of the first: yes (sequence byte 0, CRC valid: yes)
P3 F3 TX-complete interrupt taken inside uart_link_send_telemetry(): deadlocks = 1, frames on the wire = 1 of 2
P5 F5 uart_link_frame_fits(250) = true (4 + 250 + 2 = 256; the payload area is 18 bytes and s_config is 18)
P6 F6 valid command 50 ms before the millisecond wrap, next tick 1 ms later: failsafe fired = yes, motor = 0 rpm
P7 F7 telemetry payload length byte = 12 (protocol: 8); uptime_ms found at payload offset 4 (protocol: 1)
```

**Against the fixed code (output, verified, GCC 16.2; Clang identical except the compiler name):**

```text
PR09 probes against the fixed link firmware (GCC)
P1 F1 seq 1 (3000 rpm), seq 2 (STOP), then a late retransmission of seq 1: motor = 0 rpm
P1 F1 seq 2 (500 rpm) lands in RAM, then dirty lines are evicted: motor = 500 rpm, CRC errors = 0
P2 F2 two telemetry frames (1200 mA, then 3400 mA): second frame on the wire is a byte-for-byte copy of the first: no (sequence byte 1, CRC valid: yes)
P3 F3 TX-complete interrupt taken inside uart_link_send_telemetry(): deadlocks = 0, frames on the wire = 2 of 2
P5 F5 uart_link_frame_fits(250) = false (4 + 250 + 2 = 256; the payload area is 18 bytes and s_config is 18)
P6 F6 valid command 50 ms before the millisecond wrap, next tick 1 ms later: failsafe fired = no, motor = 1500 rpm
P7 F7 telemetry payload length byte = 8 (protocol: 8); uptime_ms found at payload offset 1 (protocol: 1)
```

### 8.2 Generated code: `uart_link_flush` and `uart_link_frame_fits`

Clang 21 for `-mcpu=cortex-m7 -mthumb` (Thumb-2), and GCC 16 for x86-64, both at `-O2`. The x86-64 build uses MinGW's Windows calling convention, so the first argument arrives in `ecx`.

**The PR (output, verified):**

```text
== cortex-m7 (clang 21) · uart_link_flush ==
    bx      lr

== cortex-m7 (clang 21) · uart_link_frame_fits ==
    subs    r0, #250
    cmn.w   r0, #231
    mov.w   r0, #0
    it      lo
    movlo   r0, #1
    bx      lr

== x86-64 (gcc 16) · uart_link_flush ==
    cmp     BYTE PTR s_tx_idle[rip], 0
    je      .L52
    ret
.L52:
    jmp     .L52

== x86-64 (gcc 16) · uart_link_frame_fits ==
    add     ecx, 6
    cmp     cl, 24
    setbe   al
    ret
```

**The fix (output, verified):**

```text
== cortex-m7 (clang 21) · uart_link_flush ==
    movw    r0, :lower16:s_tx_idle
    movt    r0, :upper16:s_tx_idle
.LBB7_1:
    ldrb    r1, [r0]
    dmb     sy
    cbnz    r1, .LBB7_4
    ldrb    r1, [r0]
    dmb     sy
    cmp     r1, #0
    ittt    eq
    ldrbeq  r1, [r0]
    dmbeq   sy
    cmpeq   r1, #0
    bne     .LBB7_4
    ldrb    r1, [r0]
    dmb     sy
    cmp     r1, #1
    bne     .LBB7_1
.LBB7_4:
    bx      lr

== cortex-m7 (clang 21) · uart_link_frame_fits ==
    cmp     r0, #19
    mov.w   r0, #0
    it      lo
    movlo   r0, #1
    bx      lr

== x86-64 (gcc 16) · uart_link_flush ==
.L50:
    movzx   eax, BYTE PTR s_tx_idle[rip]
    test    al, al
    je      .L50
    ret

== x86-64 (gcc 16) · uart_link_frame_fits ==
    cmp     cl, 18
    setbe   al
    ret
```

| Function | PR · Cortex-M7 (Clang) | PR · x86-64 (GCC) | Fix (both) |
|---|---|---|---|
| `uart_link_flush` | `bx lr`: the loop is gone, so `flush` returns with TX busy | `cmp` once, then `.L52: jmp .L52`: hangs forever | A load (`ldrb` + `dmb` / `movzx`) inside the loop |
| `uart_link_frame_fits` | `subs r0, #250` / `cmn.w r0, #231`: true for 0–18 **and 250–255** | `add ecx, 6` / `cmp cl, 24`: an 8-bit compare | `cmp r0, #19` / `cmp cl, 18` |

<details><summary><b>The unchanged code the PR builds on: frame format, HAL, host model, test helpers</b></summary>

```c
// ===== firmware/link/src/frame.c =====
// frame.c - CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) for the link's frames.
#include "frame.h"

uint16_t frame_crc16(const uint8_t* p, size_t n) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < n; i++) {
        crc = (uint16_t)(crc ^ (p[i] << 8));
        for (int bit = 0; bit < 8; bit++) {
            crc = (uint16_t)((crc & 0x8000u) ? (crc << 1) ^ 0x1021 : crc << 1);
        }
    }
    return crc;
}

void frame_seal(uint8_t* f) {
    put_u16le(f + UART_FRAME_LEN - FRAME_CRC_LEN, frame_crc16(f, UART_FRAME_LEN - FRAME_CRC_LEN));
}

bool frame_crc_ok(const uint8_t* f) {
    return get_u16le(f + UART_FRAME_LEN - FRAME_CRC_LEN) == frame_crc16(f, UART_FRAME_LEN - FRAME_CRC_LEN);
}

// ===== firmware/link/src/frame.h =====
#pragma once
// frame.h - the link's wire format: fixed 24-byte frames, little-endian, CRC-16/CCITT-FALSE over bytes 0..21.
//   [0] sync 0xA5  [1] payload length  [2] sequence  [3] command  [4..21] payload  [22..23] CRC
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define UART_FRAME_LEN 24
#define FRAME_HEADER_LEN 4
#define FRAME_CRC_LEN 2
#define FRAME_MAX_PAYLOAD (UART_FRAME_LEN - FRAME_HEADER_LEN - FRAME_CRC_LEN)
#define FRAME_SYNC 0xA5

enum { CMD_SET_SPEED = 0x01, CMD_SET_CONFIG = 0x02, CMD_TELEMETRY = 0x80 };

// Telemetry record. The protocol document fixes its wire layout: 8 bytes, packed, little-endian, in field order.
typedef struct {
    uint8_t state;
    uint32_t uptime_ms;
    int16_t current_ma;
    uint8_t temp_c;
} telemetry_t;
#define TELEMETRY_WIRE_LEN 8

typedef struct {
    uint8_t bytes[FRAME_MAX_PAYLOAD]; // opaque tuning blob, interpreted by the motor task
} motor_config_t;

uint16_t frame_crc16(const uint8_t* p, size_t n);
void frame_seal(uint8_t* f);        // writes the CRC into bytes 22..23
bool frame_crc_ok(const uint8_t* f);

static inline void put_u16le(uint8_t* p, uint16_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static inline void put_u32le(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static inline uint16_t get_u16le(const uint8_t* p) { return (uint16_t)(p[0] | p[1] << 8); }

// ===== firmware/link/src/hal.h =====
#pragma once
// hal.h - the hardware abstraction the firmware is written against. port/stm32h7 implements it on the target (a
// Cortex-M7 with a 32-byte-line write-back data cache); hal_host.c implements it as a host model for unit tests.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define DCACHE_LINE 32u // Cortex-M7 L1 data cache line, in bytes

uint32_t hal_millis(void); // milliseconds since boot; wraps every 2^32 ms (49.7 days)

// Polled UART.
bool hal_uart_read(uint8_t* dst, size_t len); // false if a whole frame hasn't arrived yet
void hal_uart_write(const uint8_t* src, size_t len);

// DMA-capable SRAM (the DMA controllers can't reach DTCM, where .bss lives) and the link UART's two DMA streams.
// Completion raises DMA_RX_IRQHandler / DMA_TX_IRQHandler.
void* hal_dma_alloc(size_t size, size_t align);
void hal_dma_rx_start(uint8_t* dst, uint16_t len);
void hal_dma_tx_start(const uint8_t* src, uint16_t len);

// CMSIS data cache maintenance by address. Both operate on every whole 32-byte line that overlaps [addr, addr+dsize).
void SCB_InvalidateDCache_by_Addr(volatile void* addr, int32_t dsize); // discard cached copies; next read comes from RAM
void SCB_CleanDCache_by_Addr(volatile void* addr, int32_t dsize);      // write dirty cached data back to RAM

// Interrupt masking (PRIMASK) and a spinlock.
uint32_t hal_irq_save(void); // masks interrupts, returns the previous state
void hal_irq_restore(uint32_t state);
typedef struct {
    volatile uint32_t held;
} hal_spinlock_t;
void hal_spin_lock(hal_spinlock_t* lock);
void hal_spin_unlock(hal_spinlock_t* lock);

// ===== firmware/link/src/hal_host.c =====
// hal_host.c - host model of hal.h for unit tests.
//
// Data cache: modelled per 32-byte line inside the DMA arena. Ordinary C loads and stores act on the cached copy (the
// arena bytes the program sees); the DMA reads and writes a separate RAM copy of each line it touches; maintenance
// moves whole lines between the two. Every touched line is treated as resident and write-back, which is what the
// Cortex-M7 does once the CPU has read or written any byte of the line (or speculatively prefetched it). A line is
// dirty when the CPU's copy differs from what was last synchronized with RAM.
//
// Interrupts: pending IRQs are taken at "interrupt windows": right after hal_spin_lock() acquires in task context,
// when hal_irq_restore() unmasks, and on hal_host_run_irqs(). A single core is modelled: an ISR that finds a spinlock
// held can never see it released, so the model records a deadlock and abandons that ISR.
#include "hal_host.h"

#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

#include "hal.h"
#include "motor.h"

host_state_t g_host;

#define ARENA_LEN 1024u
#define MAX_LINES 32u

typedef struct {
    size_t off; // line's offset in the arena
    uint8_t ram[DCACHE_LINE];
    uint8_t synced[DCACHE_LINE];
} line_t;

static uint8_t* s_block;  // malloc'd once; the arena is its first 64-byte-aligned ARENA_LEN bytes
static uint8_t* s_arena;
static size_t s_arena_used;
static line_t s_lines[MAX_LINES];
static size_t s_nlines;
static uint32_t s_millis;
static uint8_t s_uart_rx[256];
static size_t s_uart_rx_len;
static size_t s_uart_rx_pos;
static uint8_t* s_rx_dst;
static uint16_t s_rx_len;
static uint8_t s_tx_bytes[32];
static uint16_t s_tx_len;
static bool s_tx_busy;
static bool s_rx_pending;
static bool s_tx_pending;
static bool s_irq_masked;
static bool s_in_isr;
static jmp_buf s_isr_escape;
static void (*s_rx_isr)(void);
static void (*s_tx_isr)(void);

void hal_host_reset(void) {
    if (s_block == NULL) {
        s_block = malloc(ARENA_LEN + 64);
        if (s_block == NULL) {
            abort();
        }
        s_arena = s_block + (64 - (uintptr_t)s_block % 64) % 64;
    }
    memset(s_arena, 0, ARENA_LEN);
    s_arena_used = 0;
    s_nlines = 0;
    s_millis = 0;
    s_uart_rx_len = s_uart_rx_pos = 0;
    s_rx_dst = NULL;
    s_rx_len = s_tx_len = 0;
    s_tx_busy = s_rx_pending = s_tx_pending = s_irq_masked = s_in_isr = false;
    s_rx_isr = s_tx_isr = NULL;
    memset(&g_host, 0, sizeof g_host);
}

void hal_host_set_irq_handlers(void (*rx)(void), void (*tx)(void)) {
    s_rx_isr = rx;
    s_tx_isr = tx;
}

// ------------------------------------------------------------------------------------------------ interrupts
static void irq_window(void) {
    while (!s_irq_masked && !s_in_isr && ((s_rx_pending && s_rx_isr) || (s_tx_pending && s_tx_isr))) {
        void (*volatile isr)(void) = (s_rx_pending && s_rx_isr) ? s_rx_isr : s_tx_isr; // volatile: lives across setjmp
        if (isr == s_rx_isr && s_rx_pending) {
            s_rx_pending = false;
        } else {
            s_tx_pending = false;
        }
        s_in_isr = true;
        if (setjmp(s_isr_escape) == 0) {
            isr();
        }
        s_in_isr = false;
    }
}

void hal_host_run_irqs(void) { irq_window(); }

uint32_t hal_irq_save(void) {
    uint32_t was_masked = s_irq_masked ? 1u : 0u;
    s_irq_masked = true;
    return was_masked;
}

void hal_irq_restore(uint32_t state) {
    s_irq_masked = state != 0;
    irq_window();
}

void hal_spin_lock(hal_spinlock_t* lock) {
    if (lock->held) {
        g_host.deadlocks++;
        if (s_in_isr) {
            longjmp(s_isr_escape, 1); // the holder can't run until this ISR returns: the spin never ends
        }
        return;
    }
    lock->held = 1;
    if (!s_in_isr) {
        irq_window(); // an interrupt can arrive right after the lock is taken
    }
}

void hal_spin_unlock(hal_spinlock_t* lock) { lock->held = 0; }

// ------------------------------------------------------------------------------------------------ time, UART
uint32_t hal_millis(void) { return s_millis; }
void hal_host_set_millis(uint32_t ms) { s_millis = ms; }

void hal_host_uart_inject(const uint8_t* bytes, size_t len) {
    memcpy(s_uart_rx + s_uart_rx_len, bytes, len);
    s_uart_rx_len += len;
}

bool hal_uart_read(uint8_t* dst, size_t len) {
    if (s_uart_rx_len - s_uart_rx_pos < len) {
        return false;
    }
    memcpy(dst, s_uart_rx + s_uart_rx_pos, len);
    s_uart_rx_pos += len;
    return true;
}

static void wire_append(const uint8_t* src, size_t len) {
    if (g_host.wire_frames < HOST_WIRE_FRAMES) {
        memcpy(g_host.wire[g_host.wire_frames++], src, len);
    }
}

void hal_uart_write(const uint8_t* src, size_t len) { wire_append(src, len); }

// ------------------------------------------------------------------------------------------------ DMA and cache
void* hal_dma_alloc(size_t size, size_t align) {
    size_t off = (s_arena_used + align - 1) / align * align;
    if (off + size > ARENA_LEN) {
        abort();
    }
    s_arena_used = off + size;
    return s_arena + off;
}

static size_t arena_off(const volatile void* p) { return (size_t)((const uint8_t*)p - s_arena); }

static line_t* line_at(size_t off) {
    size_t base = off / DCACHE_LINE * DCACHE_LINE;
    for (size_t i = 0; i < s_nlines; i++) {
        if (s_lines[i].off == base) {
            return &s_lines[i];
        }
    }
    if (s_nlines == MAX_LINES) {
        abort();
    }
    line_t* l = &s_lines[s_nlines++];
    l->off = base;
    memcpy(l->ram, s_arena + base, DCACHE_LINE); // first touch: RAM and cache agree
    memcpy(l->synced, l->ram, DCACHE_LINE);
    return l;
}

void SCB_InvalidateDCache_by_Addr(volatile void* addr, int32_t dsize) {
    size_t first = arena_off(addr);
    size_t end = first + (size_t)dsize;
    for (size_t o = first / DCACHE_LINE * DCACHE_LINE; o < end; o += DCACHE_LINE) {
        line_t* l = line_at(o);
        memcpy(s_arena + l->off, l->ram, DCACHE_LINE); // the whole line, including bytes outside [addr, addr+dsize)
        memcpy(l->synced, l->ram, DCACHE_LINE);
    }
}

void SCB_CleanDCache_by_Addr(volatile void* addr, int32_t dsize) {
    size_t first = arena_off(addr);
    size_t end = first + (size_t)dsize;
    for (size_t o = first / DCACHE_LINE * DCACHE_LINE; o < end; o += DCACHE_LINE) {
        line_t* l = line_at(o);
        memcpy(l->ram, s_arena + l->off, DCACHE_LINE);
        memcpy(l->synced, l->ram, DCACHE_LINE);
    }
}

void hal_host_evict_dirty(void) {
    for (size_t i = 0; i < s_nlines; i++) {
        line_t* l = &s_lines[i];
        if (memcmp(s_arena + l->off, l->synced, DCACHE_LINE) != 0) { // dirty: the whole line goes back to RAM
            memcpy(l->ram, s_arena + l->off, DCACHE_LINE);
            memcpy(l->synced, l->ram, DCACHE_LINE);
        }
    }
}

void hal_dma_rx_start(uint8_t* dst, uint16_t len) {
    s_rx_dst = dst;
    s_rx_len = len;
    line_at(arena_off(dst));
}

void hal_host_dma_rx_deliver(const uint8_t* bytes, uint16_t len) {
    size_t off = arena_off(s_rx_dst);
    for (size_t i = 0; i < len && i < s_rx_len; i++) {
        line_at(off + i)->ram[(off + i) % DCACHE_LINE] = bytes[i]; // RAM only: the cache keeps what it had
    }
    s_rx_pending = true;
}

void hal_dma_tx_start(const uint8_t* src, uint16_t len) {
    size_t off = arena_off(src);
    for (size_t i = 0; i < len; i++) {
        s_tx_bytes[i] = line_at(off + i)->ram[(off + i) % DCACHE_LINE]; // the DMA reads RAM, not the cache
    }
    s_tx_len = len;
    s_tx_busy = true;
}

void hal_host_dma_tx_complete(void) {
    if (!s_tx_busy) {
        return;
    }
    s_tx_busy = false;
    wire_append(s_tx_bytes, s_tx_len);
    s_tx_pending = true;
}

// ------------------------------------------------------------------------------------------------ motor task
void motor_set_speed(int16_t rpm) { g_host.motor_rpm = rpm; }
void motor_apply_config(const motor_config_t* config) {
    (void)config;
    g_host.configs++;
}
void motor_failsafe(void) {
    g_host.failsafes++;
    g_host.motor_rpm = 0;
}

// ===== firmware/link/src/hal_host.h =====
#pragma once
// hal_host.h - controls and observations of the host model behind hal.h, for unit tests and probes.
#include <stddef.h>
#include <stdint.h>

#define HOST_WIRE_FRAMES 16

typedef struct {
    int16_t motor_rpm;
    unsigned failsafes;
    unsigned configs;
    unsigned deadlocks; // an ISR spun on a lock held by the code it interrupted (on the MCU: hang, watchdog reset)
    unsigned wire_frames;
    uint8_t wire[HOST_WIRE_FRAMES][32]; // what the UART transmitted, frame by frame
} host_state_t;

extern host_state_t g_host;

void hal_host_reset(void);
void hal_host_set_irq_handlers(void (*rx)(void), void (*tx)(void));
void hal_host_set_millis(uint32_t ms);
void hal_host_uart_inject(const uint8_t* bytes, size_t len);      // bytes arrive at the polled UART
void hal_host_dma_rx_deliver(const uint8_t* bytes, uint16_t len); // the RX DMA writes RAM, then its IRQ pends
void hal_host_dma_tx_complete(void);                              // the TX DMA finishes, then its IRQ pends
void hal_host_evict_dirty(void);                                  // cache pressure: dirty lines written back to RAM
void hal_host_run_irqs(void);                                     // take pending interrupts now

// ===== firmware/link/src/motor.h =====
#pragma once
// motor.h - the motor task's interface, as the link uses it.
#include <stdint.h>

#include "frame.h"

void motor_set_speed(int16_t rpm);
void motor_apply_config(const motor_config_t* config);
void motor_failsafe(void); // coast to a stop and latch a fault until the next valid command

// ===== firmware/link/test/check.h =====
#pragma once
// check.h - a minimal C test runner: one line per test, a summary, non-zero exit on failure.
#include <stdio.h>

static int g_failed;
static int g_run;
static int g_passed;

#define CHECK(cond)                                                    \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("    FAILED at line %d: %s\n", __LINE__, #cond);    \
            ++g_failed;                                                \
        }                                                              \
    } while (0)

#define RUN(test) run_test(#test, test)

static inline void run_test(const char* name, void (*fn)(void)) {
    int before = g_failed;
    fn();
    int ok = g_failed == before;
    g_run++;
    g_passed += ok;
    printf("%s %s\n", ok ? "ok  " : "FAIL", name);
}

static inline int finish(void) {
    printf("%d passed, %d failed\n", g_passed, g_run - g_passed);
    return g_passed == g_run ? 0 : 1;
}

// ===== firmware/link/test/link_frames.h =====
#pragma once
// link_frames.h - builds frames the way the PC-side encoder does, for the link's tests.
#include <string.h>

#include "frame.h"

static inline void make_frame(uint8_t* f, uint8_t seq, uint8_t cmd, const uint8_t* payload, uint8_t len) {
    memset(f, 0, UART_FRAME_LEN);
    f[0] = FRAME_SYNC;
    f[1] = len;
    f[2] = seq;
    f[3] = cmd;
    memcpy(f + FRAME_HEADER_LEN, payload, len);
    frame_seal(f);
}

static inline void speed_frame(uint8_t* f, uint8_t seq, int16_t rpm) {
    uint8_t payload[2];
    put_u16le(payload, (uint16_t)rpm);
    make_frame(f, seq, CMD_SET_SPEED, payload, sizeof payload);
}
```

</details>

<details><summary><b>The probe harness (probes.c and asm_probe.c)</b></summary>

```c
// asm_probe.c - compiles the link firmware itself so its generated code can be read. tools/pr.py builds this file at
// -O2 with Clang 21 for a Cortex-M7 (Thumb-2) and with the host GCC 16 (x86-64).
#include "uart_link.c"
// probes.c - cache, interrupt, overflow, wrap and wire-format probes for PR09, run against the host model in
// hal_host.c. Nothing here executes the overflow (F5) or the flush loop (F4): F5 is shown by the bounds check's verdict
// and F4 by the generated code (asm_probe.c).
#include <stdio.h>
#include <string.h>

#include "hal_host.h"
#include "uart_link.h"

static void setup(uint32_t millis) {
    hal_host_reset();
    hal_host_set_irq_handlers(DMA_RX_IRQHandler, DMA_TX_IRQHandler);
    hal_host_set_millis(millis);
    uart_link_init();
}

static void speed_frame(uint8_t* f, uint8_t seq, int16_t rpm) {
    memset(f, 0, UART_FRAME_LEN);
    f[0] = FRAME_SYNC;
    f[1] = 2;
    f[2] = seq;
    f[3] = CMD_SET_SPEED;
    put_u16le(f + FRAME_HEADER_LEN, (uint16_t)rpm);
    frame_seal(f);
}

static void receive(uint8_t seq, int16_t rpm) {
    uint8_t f[UART_FRAME_LEN];
    speed_frame(f, seq, rpm);
    hal_host_dma_rx_deliver(f, UART_FRAME_LEN);
    hal_host_run_irqs();
    uart_link_poll();
}

static void replay_after_stop(void) {
    setup(0);
    receive(1, 3000);
    receive(2, 0); // STOP
    receive(1, 3000); // the PC retransmits seq 1 after a lost ACK
    printf("P1 F1 seq 1 (3000 rpm), seq 2 (STOP), then a late retransmission of seq 1: motor = %d rpm\n",
           g_host.motor_rpm);
}

static void eviction_mid_transfer(void) {
    setup(0);
    receive(1, 1000);
    uint8_t f[UART_FRAME_LEN];
    speed_frame(f, 2, 500);
    hal_host_dma_rx_deliver(f, UART_FRAME_LEN); // the frame is in RAM...
    hal_host_evict_dirty();                     // ...when cache pressure writes dirty lines back
    hal_host_run_irqs();
    uart_link_poll();
    printf("P1 F1 seq 2 (500 rpm) lands in RAM, then dirty lines are evicted: motor = %d rpm, CRC errors = %u\n",
           g_host.motor_rpm, (unsigned)uart_link_crc_errors());
}

static void stale_tx(void) {
    setup(0);
    telemetry_t a = {2, 1000, 1200, 41};
    telemetry_t b = {2, 1010, 3400, 42};
    uart_link_send_telemetry(&a);
    hal_host_dma_tx_complete();
    hal_host_run_irqs();
    uart_link_send_telemetry(&b);
    hal_host_dma_tx_complete();
    printf("P2 F2 two telemetry frames (1200 mA, then 3400 mA): second frame on the wire is a byte-for-byte copy of the"
           " first: %s (sequence byte %u, CRC valid: %s)\n",
           memcmp(g_host.wire[0], g_host.wire[1], UART_FRAME_LEN) == 0 ? "yes" : "no", (unsigned)g_host.wire[1][2],
           frame_crc_ok(g_host.wire[1]) ? "yes" : "no");
}

static void isr_during_send(void) {
    setup(0);
    telemetry_t t = {2, 1000, 1200, 41};
    uart_link_send_telemetry(&t);
    hal_host_dma_tx_complete(); // frame 1 done: its interrupt pends...
    uart_link_send_telemetry(&t); // ...and is taken while this send is inside its critical section
    hal_host_dma_tx_complete();
    hal_host_run_irqs();
    printf("P3 F3 TX-complete interrupt taken inside uart_link_send_telemetry(): deadlocks = %u, frames on the wire ="
           " %u of 2\n", g_host.deadlocks, g_host.wire_frames);
}

static void oversized_payload(void) {
    printf("P5 F5 uart_link_frame_fits(250) = %s (4 + 250 + 2 = 256; the payload area is %d bytes and s_config is %u)\n",
           uart_link_frame_fits(250) ? "true" : "false", FRAME_MAX_PAYLOAD, (unsigned)sizeof(motor_config_t));
}

static void failsafe_across_wrap(void) {
    setup(0xFFFFFFCEu); // 50 ms before the 32-bit millisecond counter wraps (uptime 49.7 days)
    receive(1, 1500);
    hal_host_set_millis(0xFFFFFFCEu + 1u); // the next 1 kHz tick
    uart_link_tick();
    printf("P6 F6 valid command 50 ms before the millisecond wrap, next tick 1 ms later: failsafe fired = %s, motor = %d"
           " rpm\n", g_host.failsafes > 0 ? "yes" : "no", g_host.motor_rpm);
}

static void telemetry_layout(void) {
    setup(0);
    telemetry_t t = {2, 0x11223344u, 1200, 41};
    uart_link_send_telemetry(&t);
    hal_host_dma_tx_complete();
    const uint8_t* payload = g_host.wire[0] + FRAME_HEADER_LEN;
    int uptime_at = -1;
    for (int i = 0; i + 4 <= FRAME_MAX_PAYLOAD; i++) {
        if (payload[i] == 0x44 && payload[i + 1] == 0x33 && payload[i + 2] == 0x22 && payload[i + 3] == 0x11) {
            uptime_at = i;
            break;
        }
    }
    printf("P7 F7 telemetry payload length byte = %u (protocol: %d); uptime_ms found at payload offset %d (protocol:"
           " 1)\n", (unsigned)g_host.wire[0][1], TELEMETRY_WIRE_LEN, uptime_at);
}

int main(int argc, char** argv) {
    printf("PR09 probes against the %s link firmware (%s)\n", argc > 1 ? argv[1] : "?",
#if defined(__clang__)
           "Clang"
#else
           "GCC"
#endif
    );
    replay_after_stop();
    eviction_mid_transfer();
    stale_tx();
    isr_during_send();
    oversized_payload();
    failsafe_across_wrap();
    telemetry_layout();
    return 0;
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/firmware/link/src/uart_link.c b/firmware/link/src/uart_link.c
index 7baf8cc..3e7ab7a 100644
--- a/firmware/link/src/uart_link.c
+++ b/firmware/link/src/uart_link.c
@@ -1,46 +1,45 @@
 // uart_link.c - command link to the host PC: fixed 24-byte frames over UART, received and sent by DMA (FW-318).
 #include "uart_link.h"
 
+#include <stdatomic.h>
 #include <string.h>
 
 #include "hal.h"
 #include "motor.h"
 
-typedef struct {
-    uint8_t last_seq;                // highest command sequence applied; duplicates and replays are dropped
-    uint8_t dma_buf[UART_FRAME_LEN]; // the RX DMA writes each frame here
-    uint16_t crc_errors;
-    uint32_t frames_ok;
-} rx_state_t;
+// Cache maintenance works on whole 32-byte lines, so each DMA buffer owns its lines outright: a buffer sharing a line
+// with other data would discard that data on invalidate and overwrite received bytes when the line is evicted.
+#define DMA_BUF_LEN ((UART_FRAME_LEN + DCACHE_LINE - 1) / DCACHE_LINE * DCACHE_LINE)
 
-static rx_state_t* s_rx;  // DMA memory, cache-line aligned: the whole RX state in one place
-static uint8_t* s_tx_buf; // DMA memory: the frame the TX DMA is sending
+static uint8_t* s_rx_dma; // DMA memory, DMA_BUF_LEN bytes, line-aligned: nothing else lives in its lines
+static uint8_t* s_tx_dma; // likewise, for the TX DMA
+static uint8_t s_last_seq; // highest command sequence applied; duplicates and replays are dropped
+static uint16_t s_crc_errors;
+static uint32_t s_frames_ok;
 static uint8_t s_tx_queue[TX_QUEUE_DEPTH][UART_FRAME_LEN];
-static uint8_t s_tx_count;
-static bool s_tx_idle;
-static hal_spinlock_t s_tx_lock; // TX queue: shared by uart_link_send_telemetry() and the TX-complete ISR
+static uint8_t s_tx_count; // task touches it only with interrupts masked; the TX ISR is the other user
+static atomic_bool s_tx_idle; // written by the TX ISR, polled by uart_link_flush()
 static uint8_t s_tx_seq;
-static uint32_t s_deadline_ms; // failsafe deadline, pushed out by every applied command
+static uint32_t s_last_cmd_ms;
 static volatile bool s_rx_ready;
 static motor_config_t s_config;
 
 bool uart_link_frame_fits(uint8_t payload_len) {
-    uint8_t total = (uint8_t)(FRAME_HEADER_LEN + payload_len + FRAME_CRC_LEN);
-    return total <= UART_FRAME_LEN;
+    return FRAME_HEADER_LEN + payload_len + FRAME_CRC_LEN <= UART_FRAME_LEN; // in int: no narrowing before the compare
 }
 
 static void handle_frame(const uint8_t* f) {
     if (f[0] != FRAME_SYNC || !uart_link_frame_fits(f[1]) || !frame_crc_ok(f)) {
-        s_rx->crc_errors++;
+        s_crc_errors++;
         return;
     }
-    uint8_t ahead = (uint8_t)(f[2] - s_rx->last_seq); // serial-number arithmetic: 1..127 means newer
+    uint8_t ahead = (uint8_t)(f[2] - s_last_seq); // serial-number arithmetic: 1..127 means newer
     if (ahead == 0 || ahead >= 128) {
         return; // duplicate or replay
     }
-    s_rx->last_seq = f[2];
-    s_rx->frames_ok++;
-    s_deadline_ms = hal_millis() + LINK_TIMEOUT_MS;
+    s_last_seq = f[2];
+    s_frames_ok++;
+    s_last_cmd_ms = hal_millis();
     if (f[3] == CMD_SET_SPEED) {
         motor_set_speed((int16_t)get_u16le(f + FRAME_HEADER_LEN));
     } else if (f[3] == CMD_SET_CONFIG) {
@@ -50,70 +49,75 @@ static void handle_frame(const uint8_t* f) {
 }
 
 void uart_link_init(void) {
-    s_rx = hal_dma_alloc(sizeof *s_rx, DCACHE_LINE);
-    memset(s_rx, 0, sizeof *s_rx);
-    s_tx_buf = hal_dma_alloc(UART_FRAME_LEN, DCACHE_LINE);
+    s_rx_dma = hal_dma_alloc(DMA_BUF_LEN, DCACHE_LINE);
+    s_tx_dma = hal_dma_alloc(DMA_BUF_LEN, DCACHE_LINE);
+    s_last_seq = 0;
+    s_crc_errors = 0;
+    s_frames_ok = 0;
     s_tx_count = 0;
-    s_tx_idle = true;
+    atomic_store(&s_tx_idle, true);
     s_tx_seq = 0;
-    s_deadline_ms = hal_millis() + LINK_TIMEOUT_MS;
+    s_last_cmd_ms = hal_millis();
     s_rx_ready = false;
-    hal_dma_rx_start(s_rx->dma_buf, UART_FRAME_LEN);
+    hal_dma_rx_start(s_rx_dma, UART_FRAME_LEN);
 }
 
-void DMA_RX_IRQHandler(void) { s_rx_ready = true; } // a whole frame has landed in s_rx->dma_buf
+void DMA_RX_IRQHandler(void) { s_rx_ready = true; } // a whole frame has landed in s_rx_dma
 
 void uart_link_poll(void) { // task context
     if (!s_rx_ready) {
         return;
     }
     s_rx_ready = false;
-    SCB_InvalidateDCache_by_Addr(s_rx->dma_buf, UART_FRAME_LEN); // read what the DMA wrote, not stale cache lines
-    handle_frame(s_rx->dma_buf);
-    hal_dma_rx_start(s_rx->dma_buf, UART_FRAME_LEN);
+    SCB_InvalidateDCache_by_Addr(s_rx_dma, DMA_BUF_LEN); // after the transfer: read what the DMA wrote
+    handle_frame(s_rx_dma);
+    hal_dma_rx_start(s_rx_dma, UART_FRAME_LEN);
 }
 
 void uart_link_tick(void) { // 1 kHz control loop
-    if (hal_millis() > s_deadline_ms) {
+    if (hal_millis() - s_last_cmd_ms > LINK_TIMEOUT_MS) { // elapsed time by subtraction: correct across the wrap
         motor_failsafe();
     }
 }
 
-static void tx_start(const uint8_t* frame) { // with s_tx_lock held
-    memcpy(s_tx_buf, frame, UART_FRAME_LEN);
-    hal_dma_tx_start(s_tx_buf, UART_FRAME_LEN);
+static void tx_start(const uint8_t* frame) { // TX DMA idle; task context with interrupts masked, or the TX ISR
+    memcpy(s_tx_dma, frame, UART_FRAME_LEN);
+    SCB_CleanDCache_by_Addr(s_tx_dma, DMA_BUF_LEN); // the DMA reads RAM: push the frame out of the cache first
+    hal_dma_tx_start(s_tx_dma, UART_FRAME_LEN);
 }
 
 void uart_link_send_telemetry(const telemetry_t* t) { // task context; returns without waiting for the UART
-    uint8_t frame[UART_FRAME_LEN] = {FRAME_SYNC, sizeof *t, 0, CMD_TELEMETRY};
+    uint8_t frame[UART_FRAME_LEN] = {FRAME_SYNC, TELEMETRY_WIRE_LEN, 0, CMD_TELEMETRY};
+    uint8_t* p = frame + FRAME_HEADER_LEN;
     frame[2] = s_tx_seq++;
-    memcpy(frame + FRAME_HEADER_LEN, t, sizeof *t); // one copy instead of field-by-field packing
+    p[0] = t->state; // the protocol's packed little-endian layout, field by field
+    put_u32le(p + 1, t->uptime_ms);
+    put_u16le(p + 5, (uint16_t)t->current_ma);
+    p[7] = t->temp_c;
     frame_seal(frame);
-    hal_spin_lock(&s_tx_lock);
-    if (s_tx_idle) {
-        s_tx_idle = false;
+    uint32_t irq = hal_irq_save(); // the TX ISR runs on this core: mask it rather than share a lock with it
+    if (atomic_load_explicit(&s_tx_idle, memory_order_relaxed)) {
+        atomic_store_explicit(&s_tx_idle, false, memory_order_relaxed);
         tx_start(frame);
     } else if (s_tx_count < TX_QUEUE_DEPTH) {
         memcpy(s_tx_queue[s_tx_count++], frame, UART_FRAME_LEN);
     }
-    hal_spin_unlock(&s_tx_lock);
+    hal_irq_restore(irq);
 }
 
 void DMA_TX_IRQHandler(void) { // TX DMA complete: start the next queued frame
-    hal_spin_lock(&s_tx_lock);
     if (s_tx_count > 0) {
         tx_start(s_tx_queue[0]);
         s_tx_count--;
         memmove(s_tx_queue[0], s_tx_queue[1], (size_t)s_tx_count * UART_FRAME_LEN);
     } else {
-        s_tx_idle = true;
+        atomic_store_explicit(&s_tx_idle, true, memory_order_release);
     }
-    hal_spin_unlock(&s_tx_lock);
 }
 
 void uart_link_flush(void) { // before low-power entry
-    while (!s_tx_idle) {
+    while (!atomic_load_explicit(&s_tx_idle, memory_order_acquire)) {
     }
 }
 
-uint16_t uart_link_crc_errors(void) { return s_rx->crc_errors; }
+uint16_t uart_link_crc_errors(void) { return s_crc_errors; }
diff --git a/firmware/link/test/uart_link_test.c b/firmware/link/test/uart_link_test.c
index 53b8a4a..18065b7 100644
--- a/firmware/link/test/uart_link_test.c
+++ b/firmware/link/test/uart_link_test.c
@@ -24,6 +24,41 @@ static void applies_speed_command(void) {
     CHECK(g_host.motor_rpm == 1500);
 }
 
+static void drops_duplicate_sequence(void) {
+    setup();
+    uint8_t f[UART_FRAME_LEN];
+    speed_frame(f, 1, 1500);
+    receive(f);
+    speed_frame(f, 1, 2000);
+    receive(f);
+    CHECK(g_host.motor_rpm == 1500);
+}
+
+static void replay_after_stop_is_dropped(void) {
+    setup();
+    uint8_t run[UART_FRAME_LEN];
+    uint8_t stop[UART_FRAME_LEN];
+    speed_frame(run, 1, 3000);
+    speed_frame(stop, 2, 0);
+    receive(run);
+    receive(stop);
+    receive(run); // a retransmission of seq 1 arrives late
+    CHECK(g_host.motor_rpm == 0);
+}
+
+static void frame_survives_cache_eviction(void) {
+    setup();
+    uint8_t f[UART_FRAME_LEN];
+    speed_frame(f, 1, 1000);
+    receive(f);
+    speed_frame(f, 2, 500);
+    hal_host_dma_rx_deliver(f, UART_FRAME_LEN);
+    hal_host_evict_dirty(); // cache pressure while the frame sits in RAM
+    hal_host_run_irqs();
+    uart_link_poll();
+    CHECK(g_host.motor_rpm == 500);
+}
+
 static void rejects_bad_crc(void) {
     setup();
     uint8_t f[UART_FRAME_LEN];
@@ -34,16 +69,30 @@ static void rejects_bad_crc(void) {
     CHECK(uart_link_crc_errors() == 1);
 }
 
-static void sends_telemetry(void) {
+static void sends_telemetry_in_protocol_layout(void) {
     setup();
-    telemetry_t t = {2, 123456, 1200, 41};
+    telemetry_t t = {2, 0x11223344u, 1200, 41};
     uart_link_send_telemetry(&t);
     hal_host_dma_tx_complete();
     CHECK(g_host.wire_frames == 1);
-    CHECK(g_host.wire[0][1] == sizeof(telemetry_t));
+    CHECK(g_host.wire[0][1] == TELEMETRY_WIRE_LEN);
+    CHECK(g_host.wire[0][FRAME_HEADER_LEN + 1] == 0x44 && g_host.wire[0][FRAME_HEADER_LEN + 4] == 0x11);
     CHECK(frame_crc_ok(g_host.wire[0]));
 }
 
+static void consecutive_frames_reach_the_wire(void) {
+    setup();
+    telemetry_t a = {2, 1000, 1200, 41};
+    telemetry_t b = {2, 1010, 3400, 42};
+    uart_link_send_telemetry(&a);
+    hal_host_dma_tx_complete();
+    hal_host_run_irqs();
+    uart_link_send_telemetry(&b);
+    hal_host_dma_tx_complete();
+    CHECK(g_host.wire_frames == 2);
+    CHECK(g_host.wire[1][2] == 1); // the second frame's own sequence number
+}
+
 static void queues_while_busy(void) {
     setup();
     telemetry_t t = {2, 1000, 1200, 41};
@@ -56,6 +105,18 @@ static void queues_while_busy(void) {
     CHECK(g_host.wire_frames == 2);
 }
 
+static void tx_complete_during_send_does_not_deadlock(void) {
+    setup();
+    telemetry_t t = {2, 1000, 1200, 41};
+    uart_link_send_telemetry(&t);
+    hal_host_dma_tx_complete(); // its IRQ pends while the next send is in its critical section
+    uart_link_send_telemetry(&t);
+    hal_host_dma_tx_complete();
+    hal_host_run_irqs();
+    CHECK(g_host.deadlocks == 0);
+    CHECK(g_host.wire_frames == 2);
+}
+
 static void failsafe_after_timeout(void) {
     setup();
     hal_host_set_millis(1000);
@@ -67,6 +128,22 @@ static void failsafe_after_timeout(void) {
     CHECK(g_host.failsafes == 1);
 }
 
+static void failsafe_timing_across_millis_wrap(void) {
+    hal_host_reset();
+    hal_host_set_irq_handlers(DMA_RX_IRQHandler, DMA_TX_IRQHandler);
+    hal_host_set_millis(0xFFFFFFCEu); // 50 ms before the 32-bit millisecond counter wraps
+    uart_link_init();
+    uint8_t f[UART_FRAME_LEN];
+    speed_frame(f, 1, 1500);
+    receive(f);
+    hal_host_set_millis(0xFFFFFFCEu + 1u); // 1 ms after the command: no trip
+    uart_link_tick();
+    CHECK(g_host.failsafes == 0);
+    hal_host_set_millis(0xFFFFFFCEu + 101u); // 101 ms after it, the counter has wrapped to 51: trip
+    uart_link_tick();
+    CHECK(g_host.failsafes == 1);
+}
+
 static void flush_returns_when_idle(void) {
     setup();
     uart_link_flush();
@@ -76,14 +153,21 @@ static void flush_returns_when_idle(void) {
 static void frame_fits_limits(void) {
     CHECK(uart_link_frame_fits(FRAME_MAX_PAYLOAD));
     CHECK(!uart_link_frame_fits(FRAME_MAX_PAYLOAD + 1));
+    CHECK(!uart_link_frame_fits(250)); // 4 + 250 + 2 = 256: must not wrap to 0
 }
 
 int main(void) {
     RUN(applies_speed_command);
+    RUN(drops_duplicate_sequence);
+    RUN(replay_after_stop_is_dropped);
+    RUN(frame_survives_cache_eviction);
     RUN(rejects_bad_crc);
-    RUN(sends_telemetry);
+    RUN(sends_telemetry_in_protocol_layout);
+    RUN(consecutive_frames_reach_the_wire);
     RUN(queues_while_busy);
+    RUN(tx_complete_during_send_does_not_deadlock);
     RUN(failsafe_after_timeout);
+    RUN(failsafe_timing_across_millis_wrap);
     RUN(flush_returns_when_idle);
     RUN(frame_fits_limits);
     return finish();
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F1 | RX buffer shares a cache line with `last_seq` | Sev-1 (5) | 10 | L7 (needs the line-granularity model, then the replay consequence) |
| F3 | Spinlock shared with an ISR on one core | Sev-1 (5) | 2 | L6+ firmware reviewers |
| F4 | ISR flag polled without `volatile`/atomic | Sev-1 (5) | 2 | L5+ (names it); L7 (knows the two compilers diverge) |
| F5 | `uint8_t` length sum behind a cast | Sev-1 (5) | 10 | L6+ (the cast is the tell) |
| F2 | TX not cleaned before DMA | Sev-2 (3) | 10 | L6+ |
| F6 | Deadline `>` across the millisecond wrap | Sev-2 (3) | 10 | L6+ |
| F7 | Struct `memcpy` as the wire format | Sev-2 (3) | 2 | L5+ |

Total **29**. L5s find F4 and F7. L6s add F3, F5, F2 and F6. L7s find F1 by reading the struct layout against the 32-byte line, then follow it to the *consequence*: the replay check silently disabled, so a retransmitted RUN undoes a STOP. They reject the clean-invalidate "fix" (D1) and note that the test rewrite deleted the one test that would have caught it.

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| "Add `__attribute__((aligned(32)))`" for F1 | The struct is already aligned | Alignment of the start doesn't make the buffer own its lines |
| "Use CleanInvalidate on RX to be safe" | Writes the stale cache over the DMA's data | D1: turns an intermittent bug into a deterministic one |
| Turning the D-cache off "for DMA stability" | Works | Costs the whole system's performance; hides the next maintenance bug |
| `volatile` on everything | Fixes F4's reload | Doesn't order the queue state; doesn't fix F3 |
| Fixing F3 with a "trylock in the ISR" | ISR skips work when the lock is held | Drops the TX-complete event: the queue stalls instead of deadlocking |
| Widening the cast to `uint16_t` for F5 | Works for 8-bit `len` | Keeps the narrowing pattern; compute in `int` and drop the cast |
| Accepting "tests pass on the host" | Approves | The host model in CI didn't exercise eviction, wrap or IRQ timing |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "Why not mark the DMA buffers non-cacheable with the MPU and skip maintenance entirely?"</b></summary>

**Initial Prompt.** Design alternatives for DMA coherency.

**L5 Answer.** "Yes, that's simpler."

**Why L5 Stalls.** It doesn't weigh the trade-offs or check that the parse path is fast enough.

**L7 Answer.** "It's a legitimate design and often the right one on an M7: put DMA buffers in an MPU region with the non-cacheable attribute, and coherency maintenance disappears. The costs: every CPU access to those buffers goes to SRAM (slower parsing, though 24 bytes is nothing), the MPU region must be sized and aligned to its granularity, and you must still never put unrelated variables in that region, or they lose caching. What I won't accept is mixing: cacheable buffers with partial-line maintenance. Pick one model per buffer and document it next to `hal_dma_alloc`."

</details>

<details><summary><b>Q2 · "Is `volatile` enough for `s_tx_idle`?"</b></summary>

**Initial Prompt.** Volatile vs atomics in ISR code.

**L5 Answer.** "Yes, volatile is what you use for ISR flags."

**Why L5 Stalls.** Half right: it fixes the reload, not the ordering.

**L7 Answer.** "`volatile` forces a load on each iteration, which fixes the hang/deletion. It doesn't order the *other* accesses: the compiler may move non-volatile reads and writes of the queue across the flag. With `atomic_bool`, the ISR's release store and `flush`'s acquire load make everything the ISR did before setting the flag visible after the loop exits. On a single-core M7 the cost is a `dmb` per iteration of a wait loop, which is irrelevant. For a plain 'event happened' flag with no data behind it, `volatile` is acceptable. Here the flag summarizes queue state, so atomics."

</details>

<details><summary><b>Q3 · "GCC hangs and Clang deletes the loop. Which compiler is right?"</b></summary>

**Initial Prompt.** Undefined behavior and divergent compilers.

**L5 Answer.** "GCC: the loop should wait."

**Why L5 Stalls.** Treats one compiler's output as the semantics.

**L7 Answer.** "Both conform. The loop has no observable behavior, so the implementation may assume it terminates. GCC hoists the load and keeps a jump-to-self. Clang concludes that a terminating loop whose condition never changes must exit at once and removes it. That's exactly why 'it works with our compiler' isn't evidence: the next toolchain upgrade can turn a hang into a truncated frame. The fix makes the access observable (atomic or volatile), and then both compilers agree."

</details>

<details><summary><b>Q4 · "Linux drivers use spinlocks between process context and interrupt handlers. Why is it wrong here?"</b></summary>

**Initial Prompt.** Spinlocks across contexts.

**L5 Answer.** "Spinlocks are fine in ISRs."

**Why L5 Stalls.** Misses the interrupt-masking half of the Linux pattern.

**L7 Answer.** "Linux's rule is `spin_lock_irqsave` in process context when the same lock is taken in an interrupt handler: it disables local interrupts *and* takes the lock. The lock handles other CPUs, and the masking handles the local interrupt. This PR does only the lock half, on a single core, where the lock protects against nothing and the missing mask is the whole problem. On one core you need the mask. On SMP you'd need both."

</details>

<details><summary><b>Q5 · "The author added a cast to satisfy `-Wconversion`. What's your policy?"</b></summary>

**Initial Prompt.** Casts as a review signal.

**L5 Answer.** "Casts are fine if the value fits."

**Why L5 Stalls.** Here it doesn't fit, and the cast removed the only tool that said so.

**L7 Answer.** "A narrowing cast inside a bounds check or size computation is a review stop: the warning is reporting a possible wrap, and the cast asserts it can't happen without proof. Policy: compute sizes in `size_t` or `int`, compare before narrowing, and allow narrowing casts only after a check that makes them provably safe, with the check adjacent. CI can grep for `(uint8_t)(` and `(uint16_t)(` around `+` in changed lines and require a justification."

</details>

<details><summary><b>Q6 · "How do you test cache-coherency bugs without the board?"</b></summary>

**Initial Prompt.** Testing strategy for hardware-dependent defects.

**L5 Answer.** "You can't; test on hardware."

**Why L5 Stalls.** Hardware runs are intermittent. You need determinism first.

**L7 Answer.** "Three layers. A host model like `hal_host.c`, with line granularity, a separate RAM copy for the DMA, and explicit eviction, makes these deterministic in CI: P1 and P2 run in milliseconds. On the board, run the same suite twice, D-cache on and off: a test that passes only with the cache off has found a maintenance bug. Then add a guard pattern around DMA buffers (canary words in the adjacent lines) checked after each transfer, which catches sharing in soak tests. And a review rule: every `hal_dma_*` call site names its buffer's maintenance contract."

</details>

<details><summary><b>Q7 · "F6 needs 49.7 days of uptime. Why spend review time on it?"</b></summary>

**Initial Prompt.** Severity of rare-but-certain failures.

**L5 Answer.** "Devices get rebooted for updates anyway."

**Why L5 Stalls.** Fleet uptime isn't controlled by the reviewer, and 'rare per device' is 'daily per fleet'.

**L7 Answer.** "Per device it's once every 49.7 days. Across 10,000 devices that's about 200 wraps a day, and any device that's running when it wraps stops itself. Each incident is unreproducible in the lab ('motor stopped, no fault cause'), which makes it expensive. The fix is one subtraction, and the PR replaced a correct expression with an incorrect one to save that subtraction. Wrap-safe time arithmetic is a rule, not a judgment call. The test is cheap: seed the clock at 0xFFFFFFCE."

</details>

<details><summary><b>Q8 · "Rank the findings and name the guardrails."</b></summary>

**Initial Prompt.** Prioritization and prevention.

**L5 Answer.** "F5 first, it's a buffer overflow."

**Why L5 Stalls.** A defensible pick, but it ignores the physical-safety finding.

**L7 Answer.** "F1 first: a STOP undone by a retransmitted RUN is a physical safety hazard, and it happens on every lost ACK. Then F5 (memory corruption reachable from the serial port), F3 (field resets under normal telemetry load), F4 (hang or truncated frame on every sleep entry while busy), F6 (spurious stops fleet-wide), F2 (stale telemetry) and F7 (wire format). Guardrails: the host model with eviction, IRQ pending and wrap seeds in CI; a lint rule rejecting `hal_spin_lock` in `*_IRQHandler`; DMA buffers only via a line-owning allocator API; narrowing casts in size math require review; the test suite run on target with the D-cache enabled."

</details>

---

## 12. Checklist

- [ ] Every DMA buffer: line-aligned start, size rounded up to whole lines, nothing else in its lines (or a non-cacheable MPU region).
- [ ] RX: invalidate *after* the transfer, before reading. TX: clean *before* starting. Never clean an RX buffer.
- [ ] State shared with an ISR: the task masks the IRQ; no lock the ISR can spin on.
- [ ] Flags written by an ISR and polled: `atomic_*` (or `volatile` for pure events); check the generated code.
- [ ] Size and length math in `int`/`size_t`; no narrowing cast before a comparison.
- [ ] Time: `now - start > timeout`; tests seeded just before the counter wraps.
- [ ] Wire formats serialized field by field; tests assert the protocol layout, not `sizeof`.
- [ ] Tests: run on target with the D-cache on and off; deleted tests explained.

---

## 13. References

- Arm CMSIS-Core: D-Cache functions (`SCB_InvalidateDCache_by_Addr`, `SCB_CleanDCache_by_Addr`). https://arm-software.github.io/CMSIS_5/Core/html/group__Dcache__functions__m7.html
- cppreference (C): `while` loop, the note on endless loops without observable behavior. https://en.cppreference.com/w/c/language/while
- cppreference (C): Atomic operations library. https://en.cppreference.com/w/c/atomic
- The Linux Kernel: Unreliable Guide To Locking (spinlocks shared with interrupt handlers). https://www.kernel.org/doc/html/latest/kernel-hacking/locking.html
- RFC 1982: Serial Number Arithmetic (the `last_seq` comparison). https://www.rfc-editor.org/rfc/rfc1982
- Within this KB: [PR07 Coroutines and lifetimes](01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md) · [PR08 Lock-free ring buffer](02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md) · [01-02 Layer 3](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#5-layer-3-resource-lifecycle-and-failure-paths) · [01-02 Layer 5](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#7-layer-5-data-and-wire-compatibility)
