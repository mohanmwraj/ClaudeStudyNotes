# 02 · Low-Level I²C (Clock Stretching, Bus Recovery), SPI with DMA, and UART Idle-Line Reception

> **Folder:** `06-SoC-Buses-Peripheral-Drivers-and-Linux-Kernel-C/` · **File 2 of 3**
> **Anchors:**
> - NXP *UM10204 I²C-bus specification and user manual* (Rev. 7): §3.1.9 clock stretching, §3.1.16 bus clear, §3.1.4 START/STOP.
> - Motorola SPI block guide (CPOL/CPHA modes).
> - Vendor reference manuals for UART IDLE/HT/TC interrupts and circular DMA (STM32 RM0433/RM0090-style; ⚠ verify register names for your part).
> - Linux `drivers/i2c/i2c-core-base.c` (`i2c_generic_scl_recovery`), `drivers/spi/spi.c`, `drivers/tty/serial/`.
>
> **Verification:**
> - I²C bus recovery ran against an **open-drain wired-AND bus model** with a slave interrupted mid-byte at several bit positions, and a slave holding SCL low.
> - UART circular-DMA consumption logic was checked against 200 bytes in bursts, including wraps, and the full-lap ambiguity was demonstrated.
> - An SPI full-duplex DMA driver compiled warning-free for Cortex-M7/M33.
> - All outputs inserted verbatim.

---

## 0. The thesis

Low-speed buses fail in ways high-speed buses don't. A slave can **hang the whole I²C bus** by holding SDA low after a brownout. An SPI transfer can **truncate its last byte** if completion is taken from the TX side. A UART can **lose or duplicate bytes** if variable-length reception is driven by per-byte interrupts or by a DMA that stops and restarts. Each has a known, verifiable cure.

---

## 1. First-Principles Mechanics

### 1.1 I²C electrically: open drain, wired-AND, stretching

- Both lines are **open-drain**, with pull-ups. Any device can pull a line low, and no device can drive it high. The line level is the **wired-AND** of all drivers.
- **START:** SDA falls while SCL is high. **STOP:** SDA rises while SCL is high. Data changes only while SCL is low.
- **Clock stretching:** a slave holds SCL low after the master releases it, to buy time. The master must **read SCL back** after releasing it and wait, *with a timeout* (SMBus: 25–35 ms), before continuing. Controllers that don't support stretching, and bit-banged masters that don't read SCL back, corrupt transfers with slow slaves.
- **Rise time:** `t_r ≈ 0.847 · R_pullup · C_bus` (30%→70%). The spec limits are 1000 ns at 100 kHz, 300 ns at 400 kHz, and 120 ns at 1 MHz. Long cables or many devices need stronger pull-ups (lower R) or a bus buffer.

### 1.2 The stuck bus and the nine-clock recovery

If the master resets (watchdog, brownout, debugger reset) **in the middle of a read**, the slave is still shifting out its byte. If the current bit is 0, the slave holds **SDA low indefinitely**, waiting for clocks that will never come. Every subsequent START fails (a START needs SDA high).

**The cure (UM10204 §3.1.16):** clock SCL until the slave has shifted out its remaining bits (at most 8 data bits plus the ACK slot = **9 clocks**), so that it releases SDA, then send a **STOP**, which resets every slave's state machine.

```c
/* i2c_recover.c - I2C bus recovery (NXP UM10204 §3.1.16): if a slave was
 * reset-interrupted mid-transfer it may hold SDA low forever. Clock SCL up to
 * nine times until the slave finishes its byte and releases SDA, then issue a
 * STOP. A slave holding SCL low cannot be fixed by clocking: detect and report.
 * Pins are open-drain: drive 0 or release (1); reads see the wired-AND. */
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    void (*scl)(void *ctx, bool release);
    void (*sda)(void *ctx, bool release);
    bool (*scl_in)(void *ctx);
    bool (*sda_in)(void *ctx);
    void (*delay_half_period)(void *ctx);    /* >= 5 us for 100 kHz */
    void *ctx;
} i2c_pins_t;

typedef enum { I2C_RECOVERED = 0, I2C_WAS_IDLE, I2C_SDA_STUCK, I2C_SCL_STUCK } i2c_rec_t;

/* Wait for SCL to actually go high (a slave may be clock-stretching). */
static bool scl_release_wait(const i2c_pins_t *p, uint32_t max_half_periods)
{
    p->scl(p->ctx, true);
    for (uint32_t i = 0u; i < max_half_periods; i++) {
        if (p->scl_in(p->ctx)) { return true; }
        p->delay_half_period(p->ctx);
    }
    return false;
}

i2c_rec_t i2c_bus_recover(const i2c_pins_t *p, uint32_t *clocks_used);
i2c_rec_t i2c_bus_recover(const i2c_pins_t *p, uint32_t *clocks_used)
{
    *clocks_used = 0u;
    p->sda(p->ctx, true);
    if (!scl_release_wait(p, 20u)) {
        return I2C_SCL_STUCK;                      /* stretching forever: power-cycle the slave */
    }
    if (p->sda_in(p->ctx)) {
        return I2C_WAS_IDLE;
    }
    for (uint32_t k = 0u; k < 9u; k++) {           /* 8 data bits + ACK slot worst case */
        p->scl(p->ctx, false);
        p->delay_half_period(p->ctx);
        if (!scl_release_wait(p, 20u)) { return I2C_SCL_STUCK; }
        p->delay_half_period(p->ctx);
        (*clocks_used)++;
        if (p->sda_in(p->ctx)) { break; }
    }
    if (!p->sda_in(p->ctx)) {
        return I2C_SDA_STUCK;
    }
    /* STOP: SDA low -> high while SCL is high resets every slave's state machine. */
    p->scl(p->ctx, false);
    p->delay_half_period(p->ctx);
    p->sda(p->ctx, false);
    p->delay_half_period(p->ctx);
    if (!scl_release_wait(p, 20u)) { return I2C_SCL_STUCK; }
    p->delay_half_period(p->ctx);
    p->sda(p->ctx, true);
    p->delay_half_period(p->ctx);
    return (p->sda_in(p->ctx) && p->scl_in(p->ctx)) ? I2C_RECOVERED : I2C_SDA_STUCK;
}

#ifdef I2C_SELFTEST
#include <stdio.h>

/* Slave model: was transmitting `byte` (read transfer) with `bits_left` bits
 * still to send when the master reset. It updates SDA on SCL falling edges,
 * releases SDA for the ACK slot, then goes idle; a STOP also resets it. */
typedef struct {
    bool m_scl, m_sda;            /* master drive (true = released) */
    bool s_sda, s_scl;            /* slave drive                     */
    int  bits_left;               /* >0: data bits; 0: ACK slot; <0: idle */
    uint8_t byte;
    bool prev_scl, prev_sda;
    bool stuck_scl;
    int  stops_seen;
} bus_t;

static bool line_scl(const bus_t *b) { return b->m_scl && b->s_scl && !b->stuck_scl; }
static bool line_sda(const bus_t *b) { return b->m_sda && b->s_sda; }

static void slave_step(bus_t *b)
{
    bool scl = line_scl(b), sda = line_sda(b);
    if (b->prev_scl && !scl && (b->bits_left >= 0)) {          /* SCL falling: next bit */
        if (b->bits_left > 0) {
            b->bits_left--;
            b->s_sda = (b->bits_left > 0) ? (((b->byte >> (b->bits_left - 1)) & 1u) != 0u) : true;
        } else {
            b->bits_left = -1; b->s_sda = true;                 /* after ACK slot: idle */
        }
    }
    if (scl && b->prev_scl && !b->prev_sda && sda) {            /* STOP condition */
        b->stops_seen++; b->bits_left = -1; b->s_sda = true;
    }
    b->prev_scl = scl; b->prev_sda = sda;
}
static void p_scl(void *c, bool r) { bus_t *b = c; b->m_scl = r; slave_step(b); }
static void p_sda(void *c, bool r) { bus_t *b = c; b->m_sda = r; slave_step(b); }
static bool p_scl_in(void *c) { return line_scl(c); }
static bool p_sda_in(void *c) { return line_sda(c); }
static void p_delay(void *c) { slave_step(c); }

static void run(const char *name, int bits_left, uint8_t byte, bool stuck)
{
    bus_t b = { true, true, true, true, bits_left, byte, true, true, stuck, 0 };
    if (bits_left > 0) { b.s_sda = ((byte >> (bits_left - 1)) & 1u) != 0u; }
    b.prev_sda = line_sda(&b); b.prev_scl = line_scl(&b);
    i2c_pins_t p = { p_scl, p_sda, p_scl_in, p_sda_in, p_delay, &b };
    uint32_t clocks;
    static const char *const r[] = { "RECOVERED", "WAS_IDLE", "SDA_STUCK", "SCL_STUCK" };
    i2c_rec_t res = i2c_bus_recover(&p, &clocks);
    printf("%-34s -> %-9s clocks=%u STOP seen by slave=%d bus SCL=%d SDA=%d\n",
           name, r[res], (unsigned)clocks, b.stops_seen, (int)line_scl(&b), (int)line_sda(&b));
}

int main(void)
{
    run("idle bus", -1, 0x00u, false);
    run("slave mid-byte 0x00, 5 bits left", 5, 0x00u, false);
    run("slave sending 0x00, all 8 bits left", 8, 0x00u, false);
    run("slave sending 0x7F, 8 bits left", 8, 0x7Fu, false);
    run("slave holding SCL low (stretch)", 3, 0x00u, true);
    return 0;
}
#endif
```

**Output (verified, native, against the wired-AND bus model):**

```text
idle bus                           -> WAS_IDLE  clocks=0 STOP seen by slave=0 bus SCL=1 SDA=1
slave mid-byte 0x00, 5 bits left   -> RECOVERED clocks=5 STOP seen by slave=1 bus SCL=1 SDA=1
slave sending 0x00, all 8 bits left -> RECOVERED clocks=8 STOP seen by slave=1 bus SCL=1 SDA=1
slave sending 0x7F, 8 bits left    -> RECOVERED clocks=1 STOP seen by slave=1 bus SCL=1 SDA=1
slave holding SCL low (stretch)    -> SCL_STUCK clocks=0 STOP seen by slave=0 bus SCL=0 SDA=0
```

- **Interrupted 5 bits into a `0x00` byte:** **5 clocks** to release SDA, then STOP. The slave saw it, and the bus is idle (SCL = 1, SDA = 1).
- **A full `0x00` byte still to send:** 8 clocks, within the 9-clock bound.
- **Sending `0x7F`:** only the MSB is 0, so SDA rises after **1 clock**. The slave is *still mid-byte*, which is why the STOP is mandatory: it resets the slave, rather than leaving it to drive the next bits onto the next transaction.
- **A slave holding SCL low** (stuck stretching, or a crashed slave firmware) **can't be fixed by clocking**. The code *detects* it (`SCL_STUCK`) through the stretch-wait timeout instead of spinning forever. The system-level remedy is to power-cycle or reset the slave through a GPIO or load switch, and that path must exist in the hardware design.

Production notes:
- Run recovery **at boot** (the brownout case) and **after any timeout or arbitration-lost error**.
- Bit-bang it on GPIO with the pins temporarily switched from the I²C peripheral to open-drain outputs. Many controllers (and Linux `i2c_generic_scl_recovery` via `bus_recovery_info`) support it natively.
- Hold each phase for at least half the bus period: ≥ 5 µs at 100 kHz.

### 1.3 SPI with DMA: four ordering rules

SPI is full-duplex and master-clocked: **every transmitted byte simultaneously clocks in a received byte**.

1. **Arm RX DMA before TX DMA.** The first RX byte appears as soon as the first TX byte shifts out. If RX isn't ready, it overruns (OVR) or is lost.
2. **Complete on RX, not TX.** TX-DMA-complete means "the last byte was written to the TX FIFO/shift register", not "it was clocked out". Deasserting CS, or reusing the TX buffer for the *peripheral's* view, on TX-complete truncates the final byte. RX-complete implies every byte was fully shifted. Then wait for `BSY = 0` before deasserting CS.
3. **Cache maintenance on non-coherent cores** (Folder 03): clean TX before starting, invalidate RX (line-exact) before and after.
4. **CS through an atomic set/reset register** (BSRR), never by RMW on a GPIO output register shared with other code (Folder 01, File 02).

```c
/* spi_dma.c - full-duplex SPI transfer with two DMA channels on a
 * non-coherent Cortex-M7. Order matters at four points (see comments).
 * Register layout is a generic SPI/DMA model; map it onto your SoC. */
#include <stdalign.h>
#include <stdbool.h>
#include <stdint.h>

#include "dcache.h"                   /* Folder 03: clean / invalidate helpers (line-exact) */

typedef struct {
    volatile uint32_t CR;             /* [0] EN, [1] RXDMAEN, [2] TXDMAEN */
    const volatile uint32_t SR;       /* [7] BSY                          */
    volatile uint32_t DR;
} spi_regs_t;

typedef struct {
    volatile uint32_t CCR;            /* [0] EN, [1] TCIE                 */
    volatile uint32_t CNDTR;          /* transfer count                   */
    volatile uint32_t CPAR;           /* peripheral address               */
    volatile uint32_t CMAR;           /* memory address                   */
} dma_ch_t;

#define SPI_EN       (1u << 0)
#define SPI_RXDMAEN  (1u << 1)
#define SPI_TXDMAEN  (1u << 2)
#define SPI_BSY      (1u << 7)
#define DMA_EN       (1u << 0)
#define DMA_TCIE     (1u << 1)

typedef struct {
    spi_regs_t *spi;
    dma_ch_t   *rx, *tx;
    volatile uint32_t *cs_gpio_bsrr;  /* atomic set/reset register (Folder 01 File 02) */
    uint32_t    cs_pin;
    volatile bool rx_done;            /* set by the RX DMA complete ISR */
} spi_dev_t;

int spi_xfer_dma(spi_dev_t *d, const uint8_t *tx, uint8_t *rx, uint32_t n);
int spi_xfer_dma(spi_dev_t *d, const uint8_t *tx, uint8_t *rx, uint32_t n)
{
    if (!dcache_range_exact(rx, n)) {
        return -1;                                   /* RX buffer must own whole cache lines */
    }
    dcache_clean_range(tx, n);                       /* 1. TX bytes from cache to SRAM        */
    if (!dcache_invalidate_range(rx, n)) {           /* 2. no dirty RX lines can be evicted   */
        return -1;
    }
    d->rx_done = false;
    *d->cs_gpio_bsrr = d->cs_pin << 16;              /*    CS low (atomic reset half)         */

    d->rx->CPAR = (uint32_t)(uintptr_t)&d->spi->DR;  /* 3. RX channel armed BEFORE TX: the    */
    d->rx->CMAR = (uint32_t)(uintptr_t)rx;           /*    first received byte appears as     */
    d->rx->CNDTR = n;                                /*    soon as the first TX byte shifts   */
    d->rx->CCR = DMA_TCIE | DMA_EN;
    d->tx->CPAR = (uint32_t)(uintptr_t)&d->spi->DR;
    d->tx->CMAR = (uint32_t)(uintptr_t)tx;
    d->tx->CNDTR = n;
    d->tx->CCR = DMA_EN;                             /*    no TX IRQ: completion = RX done    */
    __asm__ volatile("dsb sy" : : : "memory");       /*    descriptors programmed before go   */
    d->spi->CR = SPI_EN | SPI_RXDMAEN | SPI_TXDMAEN;

    while (!d->rx_done) {                            /* 4. wait for RX complete, NOT TX:      */
        __asm__ volatile("wfi" : : : "memory");      /*    TX-complete fires while the last   */
    }                                                /*    byte is still shifting out         */
    while ((d->spi->SR & SPI_BSY) != 0u) { }
    d->spi->CR = 0u;
    *d->cs_gpio_bsrr = d->cs_pin;                    /*    CS high only after the bus idles   */
    (void)dcache_invalidate_range(rx, n);            /* 5. drop speculative refills (Folder 03)*/
    return 0;
}
```

**Build evidence (verified):** zero diagnostics on Cortex-M7 and Cortex-M33 (full warning set, `-std=c11`), with `dcache.h` from Folder 03.

**SPI mode reminder:**
- Mode 0 (CPOL = 0, CPHA = 0): idle low, sample on the rising edge.
- Mode 3 (CPOL = 1, CPHA = 1): idle high, sample on the rising edge.

Modes 1 and 2 sample on the falling edge. A mode mismatch typically shows as data shifted by one bit, which a logic analyzer's SPI decoder makes obvious.

### 1.4 UART: variable-length frames with circular DMA and IDLE-line detection

Per-byte RX interrupts at 1–3 Mbaud (~100–300k IRQ/s) burn the CPU and lose bytes during long critical sections. Stopping and restarting the DMA per frame opens a window where bytes are lost. The robust pattern:

- **The DMA runs forever in circular mode** into a ring of N bytes.
- **The IDLE-line interrupt** fires when the line is idle for one character time after activity: "a frame (or a burst) ended".
- **The half-transfer (HT) and transfer-complete (TC) interrupts** fire at N/2 and N.
- **All three call one function** that consumes the bytes between the last processed position and the DMA's current position (`pos = N − NDTR`), handling the wrap.

```c
/* uart_dma_rx.c - variable-length UART reception with a CIRCULAR DMA buffer
 * and the IDLE-line interrupt: the DMA never stops; the IDLE, half-transfer
 * and transfer-complete interrupts all call one function that consumes the
 * bytes between the last processed position and the DMA's current position.
 *   pos = N - NDTR   (NDTR = remaining count in the current lap)
 * The HT/TC interrupts guarantee the handler runs at least twice per lap, so
 * fewer than N bytes can arrive between two calls - the only way "pos == old"
 * can be told apart from "a whole lap arrived". */
#include <stdint.h>

#define RX_N 64u

typedef struct {
    uint8_t  buf[RX_N];          /* DMA target (line-aligned + cache-maintained: Folder 03) */
    uint32_t old;                /* last consumed position                                */
    uint32_t delivered;
    uint32_t laps;               /* TC count, for overrun detection                       */
} uart_rx_t;

typedef void (*sink_t)(const uint8_t *p, uint32_t n, void *ctx);

void uart_rx_process(uart_rx_t *u, uint32_t ndtr, sink_t sink, void *ctx);
void uart_rx_process(uart_rx_t *u, uint32_t ndtr, sink_t sink, void *ctx)
{
    uint32_t pos = RX_N - ndtr;                 /* 0..N; N means "just wrapped" */
    if (pos == RX_N) { pos = 0u; }
    if (pos > u->old) {                         /* contiguous */
        sink(&u->buf[u->old], pos - u->old, ctx);
        u->delivered += pos - u->old;
    } else if (pos < u->old) {                  /* wrapped: tail then head */
        sink(&u->buf[u->old], RX_N - u->old, ctx);
        u->delivered += RX_N - u->old;
        if (pos > 0u) {
            sink(&u->buf[0], pos, ctx);
            u->delivered += pos;
        }
    }                                           /* pos == old: nothing new (given HT/TC) */
    u->old = pos;
}

#ifdef RX_SELFTEST
#include <stdio.h>

static uint8_t g_out[4096];
static uint32_t g_outn;
static void collect(const uint8_t *p, uint32_t n, void *ctx)
{
    (void)ctx;
    for (uint32_t i = 0u; i < n; i++) { g_out[g_outn++] = p[i]; }
}

int main(void)
{
    static uart_rx_t u;
    uint32_t dma_pos = 0u, sent = 0u;
    /* bursts of bytes arriving, each followed by an interrupt (IDLE/HT/TC) */
    const uint32_t bursts[] = { 10u, 20u, 2u, 40u, 63u, 1u, 33u, 31u };
    for (unsigned b = 0u; b < sizeof bursts / sizeof bursts[0]; b++) {
        for (uint32_t i = 0u; i < bursts[b]; i++) {          /* the "DMA" writes */
            u.buf[dma_pos] = (uint8_t)(sent & 0xFFu);
            sent++;
            dma_pos = (dma_pos + 1u) % RX_N;
        }
        uint32_t ndtr = RX_N - dma_pos;                       /* what the register would read */
        uart_rx_process(&u, ndtr, collect, NULL);
    }
    uint32_t bad = 0u;
    for (uint32_t i = 0u; i < g_outn; i++) { bad += (g_out[i] != (uint8_t)(i & 0xFFu)); }
    printf("sent=%u delivered=%u mismatched=%u (bursts incl. wraps and a 63-byte near-lap)\n",
           (unsigned)sent, (unsigned)u.delivered, (unsigned)bad);

    /* The ambiguity: exactly N bytes between two interrupts looks like 0. */
    static uart_rx_t v;
    uint32_t before = v.delivered;
    uart_rx_process(&v, RX_N - 0u, collect, NULL);            /* a full lap later, DMA pos unchanged */
    printf("exactly one full lap between calls: delivered %u new bytes (should be %u) -> "
           "HT/TC interrupts must bound the gap below N\n",
           (unsigned)(v.delivered - before), (unsigned)RX_N);
    return 0;
}
#endif
```

**Output (verified, native):**

```text
sent=200 delivered=200 mismatched=0 (bursts incl. wraps and a 63-byte near-lap)
exactly one full lap between calls: delivered 0 new bytes (should be 64) -> HT/TC interrupts must bound the gap below N
```

- **200 bytes in 8 bursts**, including wraps and a 63-byte near-lap burst, were delivered in order (**0 mismatched**).
- **The full-lap ambiguity, demonstrated.** If exactly N bytes arrive between two calls, `pos == old`, and the function correctly reports **0 new bytes**, losing 64. The design guarantee that prevents this is architectural: **HT and TC interrupts bound the gap below N**, because the handler runs at least twice per lap. Size N so that `N/2 > bytes arriving during the worst-case interrupt latency`, and treat a TC count advancing by 2 or more between calls as an overrun.

Production notes:
- The DMA buffer is line-aligned and line-sized, and invalidated before reading on cached cores (Folder 03).
- The consumer pushes into an SPSC ring for the protocol task (Folder 05).
- Enable the UART overrun (ORE) and noise/framing error interrupts, and clear them W1C-correctly (Folder 01, File 02).
- On STM32, *read SR then read DR* sequences clear some flags, and the two reads must be separate statements (Folder 01, File 01 §1.3).

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* periph_bad.c - three drivers, three classic defects. */
#include <stdbool.h>
#include <stdint.h>

extern void gpio_scl(bool level);          /* push-pull drive (!) */
extern void gpio_sda(bool level);
extern void delay_us(uint32_t us);
extern volatile bool g_tx_done;
extern void cs_high(void);
extern volatile uint32_t UART_DR;
extern uint8_t g_frame[256];
extern volatile uint32_t g_frame_len;

void i2c_bitbang_clock(void);
void i2c_bitbang_clock(void)
{
    gpio_scl(false); delay_us(5);
    gpio_scl(true);  delay_us(5);          /* BUG 1: pushes SCL high (fights a stretching
                                            *        slave) and never reads SCL back       */
}

void spi_dma_tx_complete_isr(void);
void spi_dma_tx_complete_isr(void)
{
    cs_high();                             /* BUG 2: TX-complete != last bit shifted out:
                                            *        truncates the final byte              */
    g_tx_done = true;
}

void uart_rx_isr(void);
void uart_rx_isr(void)
{
    g_frame[g_frame_len++] = (uint8_t)UART_DR;   /* BUG 3: per-byte IRQ at Mbaud rates; no bounds
                                                  *        check (len overflows the buffer);
                                                  *        frame boundary undefined          */
}
```

### 2.2 The Silicon-Hardened Production Way

- **I²C:**
  - controller in open-drain mode with stretch support enabled, and a transfer timeout;
  - the verified `i2c_bus_recover()` at boot and after timeouts or arbitration loss;
  - a slave reset/power path for `SCL_STUCK`;
  - pull-ups sized from the rise-time formula.
- **SPI:** the verified `spi_xfer_dma()`: RX armed first, completion on RX plus `!BSY`, CS through BSRR, cache maintenance line-exact.
- **UART:** the verified `uart_rx_process()` called from the IDLE, HT and TC interrupts with circular DMA; an SPSC ring to the task; overrun detection through the TC count.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| I²C dead after a reset; every transfer times out; SDA stuck low on the scope | Slave interrupted mid-read (§1.2) | Scope both lines. Run recovery and watch the 1–9 clocks plus STOP; the verified model shows the expected counts |
| I²C works with some slaves, corrupts with a slow one | No clock-stretching support, or SCL pushed high | Logic analyzer: SCL held low by the slave after the master released it. Use open-drain and read SCL back |
| Data errors at 400 kHz but not 100 kHz | Rise time too slow (pull-ups too weak, bus capacitance) | Scope the rise time and compare with `0.847·R·C` and the spec limit |
| SPI last byte corrupted, or CS too early | Completion taken from TX | Logic analyzer: CS rises during the last byte's clocks |
| SPI RX overrun (OVR) at the first byte | RX DMA armed after TX | Check the arm order |
| UART drops bytes under load | Per-byte IRQs blocked by critical sections; DMA restarted per frame | Circular DMA + IDLE/HT/TC; latency budget vs N/2 |
| UART frames "merge" | IDLE not enabled, or IDLE flag cleared incorrectly (read-sequence clear) | Check the flag-clear sequence in the reference manual |

A **protocol-decoding logic analyzer** (Saleae, Sigrok/PulseView) on SCL/SDA, SCK/MOSI/MISO/CS and TX/RX is the primary instrument for every row in this table. Trigger on the error condition (NACK, CS edge, framing error), and correlate with a GPIO toggled by the firmware.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "After a watchdog reset, your I²C sensor bus is dead until a power cycle. Why, and how do you fix it in firmware?"

- **L5:** "The sensor crashed; add a power cycle."
- **Why L5 fails on real hardware:** The sensor is fine. It was **mid-read when the MCU reset**, and it's holding SDA low, waiting for clocks to finish its byte. A power cycle works, but it isn't necessary, and it may not be available.
- **L7 principal defense:**
  - Bus clear: toggle SCL (open-drain, read back for stretching) up to 9 times until SDA is released, then a STOP (verified: 5, 8 and 1 clocks for different interruption points; the STOP always reaches the slave).
  - Detect the unrecoverable SCL-held-low case (verified `SCL_STUCK`) and escalate to a slave reset or power path.
  - Run it at every boot and after every bus error.
  - Cite UM10204 §3.1.16 and Linux `i2c_generic_scl_recovery`.

### Q2 "Why must the RX DMA channel be enabled before TX in an SPI transfer, and why complete on RX?"

- **L5:** "That's the order in the reference manual."
- **Why L5 fails:** Know the *mechanism*. SPI shifts in as it shifts out, so the first RX byte arrives one byte time after TX starts, and an unarmed RX path overruns. TX-complete fires when the last byte enters the shift register, not when its final clock edge has happened. CS deasserted then truncates it.
- **L7 defense:** The verified driver: RX armed first, a `dsb` before enabling, wait for RX-complete and `BSY = 0`, CS via BSRR. Add cache maintenance on non-coherent cores, and verify on a logic analyzer.

### Q3 🔥 "Design variable-length UART reception at 3 Mbaud on a Cortex-M4."

- **L5:** "RX interrupt per byte into a buffer."
- **Why L5 fails:** At 3 Mbaud that's ~300k interrupts/s. Any critical section longer than ~3 µs drops bytes, and frame boundaries need a timer.
- **L7 defense:** Circular DMA plus IDLE-line plus HT/TC interrupts, all calling the verified consumer (`pos = N − NDTR`, wrap handling, 200/200 bytes delivered). Size N so HT/TC bound the gap below N (verified ambiguity at exactly one lap), detect overrun via the TC count, use an SPSC ring to the task, and do cache maintenance on M7.

### Q4 "How do you size I²C pull-up resistors?"

- **L5:** "4.7 kΩ."
- **Why L5 fails:** It depends on bus capacitance, speed mode, and V_DD. 4.7 kΩ on a 400 pF bus gives `t_r ≈ 0.847 × 4700 × 400 pF ≈ 1.6 µs`: too slow even for 100 kHz (1000 ns max).
- **L7 defense:**
  - **R_max** from rise time: `R ≤ t_r,max / (0.847 · C_bus)`.
  - **R_min** from the sink current: `R ≥ (V_DD − V_OL,max) / I_OL` (3 mA for standard and fast modes).
  - Pick within the range, and measure on the scope.
  - Use Fast-mode Plus drivers or bus buffers for large buses.

---

## 5. Invariants Checklist

- [ ] I²C pins open-drain; SCL read back after release (stretch support) with a timeout; recovery (≤ 9 clocks + STOP) at boot and on errors; an escalation path for SCL stuck low.
- [ ] Pull-ups computed from the rise-time and sink-current limits, and verified on a scope.
- [ ] SPI: RX DMA armed before TX; completion = RX done + not busy; CS via an atomic set/reset register; cache maintenance line-exact.
- [ ] UART: circular DMA + IDLE/HT/TC into one consumer; N sized against worst-case latency; overrun detected via the TC count; error flags cleared correctly.
- [ ] Every protocol verified with a decoding logic analyzer against the firmware's GPIO markers.

## 6. References

1. NXP, *UM10204: I²C-bus specification and user manual*, Rev. 7.0 (2021): §3.1.9, §3.1.16, rise-time and pull-up sizing.
2. SMBus Specification 3.x: clock-low timeout (25–35 ms).
3. Linux `drivers/i2c/i2c-core-base.c` (`i2c_generic_scl_recovery`, `struct i2c_bus_recovery_info`), `drivers/spi/spi.c`.
4. Vendor reference manuals for UART IDLE detection, DMA circular mode and HT/TC flags; vendor application notes on UART DMA reception (⚠ verify for your part).
