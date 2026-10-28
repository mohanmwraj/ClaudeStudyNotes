# 04.3 · Interrupts: GICv3, Top and Bottom Halves, Threaded IRQs, Workqueues and PREEMPT_RT

> **Folder 04 · File 3 of 4.** Interrupt handling is where a driver's correctness meets the system's latency. Each kind of mistake has its own failure:
> - a sleeping call in a hard handler: "scheduling while atomic", or a deadlock;
> - a level-triggered line left unmasked: an interrupt storm;
> - an unthrottled printk: milliseconds of latency.
>
> On a real-time system the stakes are higher: a priority inversion or an IRQ thread at the wrong priority turns a 50 µs control loop into a 4 ms one.
>
> This file covers:
> - the GICv3 model and the device-tree encoding;
> - the context rules (hard IRQ, threaded IRQ, softirq, workqueue);
> - how PREEMPT_RT changes them;
> - priority inheritance, simulated tick by tick;
> - the measurement tools.
>
> **Pinned.** Linux **v7.2**:
> - `kernel/irq/manage.c` (`irq_thread()`: `sched_set_fifo()`; "Threaded irq requested with handler=NULL and !ONESHOT"; `threadirqs`);
> - `kernel/sched/syscalls.c` (`sched_set_fifo` = `MAX_RT_PRIO / 2`, `sched_set_fifo_secondary` = one below);
> - `kernel/Kconfig.preempt` (`PREEMPT_RT`, mainline);
> - `include/dt-bindings/interrupt-controller/arm-gic.h`;
> - `tools/tracing/rtla`.
>
> **Verification.**
> - `irq_lint.py` checks interrupt-context rules.
> - The drivers pass `kapi_check.py` (04.1) against v7.2 headers.
> - `rt_sched_sim.py` runs fixed-priority scheduling with three lock semantics.
> - No RT kernel was booted here: latency figures are model outputs, and real numbers come from `rtla`/`cyclictest` on the target (README).

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 GICv3 in one page

```text
 INTID ranges         SGI 0-15 (software, IPIs)  PPI 16-31 (per-CPU: arch timer, PMU)  SPI 32-1019 (shared peripherals)
                      LPI 8192+ (message-based, via the ITS: PCIe MSI/MSI-X)
 components           Distributor (SPIs: enable, priority, routing GICD_IROUTER) · Redistributor per CPU (SGI/PPI, LPIs)
                      CPU interface via system registers: ICC_IAR1_EL1 (acknowledge) · ICC_EOIR1_EL1 (end) · ICC_PMR_EL1
 state machine        inactive → pending → active (acked) → inactive (EOI)   [level: stays pending while the line is high]
 DT specifier         interrupts = <GIC_SPI n IRQ_TYPE_LEVEL_HIGH>  →  INTID = n + 32;  <GIC_PPI n flags> → INTID = n + 16
                      GIC_SPI = 0, GIC_PPI = 1, IRQ_TYPE_EDGE_RISING = 1, IRQ_TYPE_LEVEL_HIGH = 4  (dt-bindings headers)
```

**A level-triggered line stays pending until the device deasserts it.** If the handler returns before the device is quiesced, or the line is unmasked before the slow work clears the source, the interrupt fires again immediately: a storm. `IRQF_ONESHOT` keeps the line masked until the thread finishes.

### 1.2 Execution contexts

| Context | Can sleep? | Preemptible (mainline / PREEMPT_RT) | Use for |
|---|---|---|---|
| Hard IRQ (primary handler) | No | No / threaded by force unless `IRQF_NO_THREAD` | Ack, timestamp, read a status register, return `IRQ_WAKE_THREAD` |
| Threaded handler | Yes | Yes (SCHED_FIFO 50 by default) | Bus I/O (I2C, SPI), anything that waits |
| Softirq / tasklet | No | Mostly no / runs in threads | Networking, block completion (tasklets are being phased out) |
| Workqueue | Yes | Yes (SCHED_OTHER kworkers) | Deferred, non-urgent work; `system_unbound_wq` for CPU-agnostic work |

- **The kernel enforces one rule outright.** `request_threaded_irq(irq, NULL, thread_fn, flags, ...)` without `IRQF_ONESHOT` is refused ("Threaded irq requested with handler=NULL and !ONESHOT"), because the line would be unmasked with the source still active.
- **Thread priorities.** IRQ threads get `sched_set_fifo()`: SCHED_FIFO at `MAX_RT_PRIO / 2` = 50. Forced-threaded secondary handlers get 49.

### 1.3 What PREEMPT_RT changes

The Kconfig help (v7.2) says it replaces "various locking primitives (spinlocks, rwlocks, etc.) with preemptible priority-inheritance aware variants, enforcing interrupt threading". Concretely:

| Primitive | Mainline | PREEMPT_RT |
|---|---|---|
| `spinlock_t`, `rwlock_t` | Spinning, preemption off | **Sleeping** rt_mutex with priority inheritance |
| `raw_spinlock_t` | Spinning | Spinning (still): for the few paths that must never sleep |
| `mutex` | Sleeping (optimistic spin) | rt_mutex-based, PI |
| Interrupt handlers | Hard IRQ unless `threadirqs` | Forced threaded, except `IRQF_NO_THREAD` / per-CPU |
| `local_irq_disable()` around long work | Latency | Still latency, and a bug |

The consequence for drivers:
- **Data shared with a handler that is never threaded** (`IRQF_NO_THREAD`, or genuinely hard-IRQ paths) must use `raw_spinlock_t`, and the critical section must be tiny.
- **A `spinlock_t` in such a handler** is a sleeping lock taken in atomic context on RT.

### 1.4 Priority inversion and inheritance

The classic three-task inversion (§2.3):
- **No priority inheritance.** The high-priority task waits for the medium-priority hog that preempted the lock holder. The wait is unbounded: it's however long the hog runs.
- **rt_mutex** boosts the holder to the waiter's priority, so the wait is bounded by the critical section.
- **`raw_spinlock_t`** also bounds it, by disabling preemption, but blocks *everything* on that CPU for the section's length. That's why RT keeps raw locks for tiny sections only.

The second trap is subtler. IRQ threads default to FIFO 50. An application thread at FIFO 80 that runs long starves every interrupt thread below it, and the network or the sensor goes quiet. Assign IRQ thread priorities deliberately, with `chrt -f -p <prio> <pid>` per `irq/<n>-<name>` thread, from a startup unit.

---

## 2. Production Code & Configuration Blueprints

### 2.1 The interrupt-driven sensor driver

#### The Fragile Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_temp_fragile.c - the same sensor driver, written as if interrupt handlers were ordinary functions */
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/spinlock.h>

static struct i2c_client *sensor;
static DEFINE_SPINLOCK(lock);
static int last;

static irqreturn_t temp_irq(int irq, void *data)
{
	spin_lock(&lock);
	last = i2c_smbus_read_word_swapped(sensor, 0x00);	/* sleeps on the I2C bus, in hard-IRQ context */
	msleep(1);						/* "give the sensor time" */
	i2c_smbus_read_byte_data(sensor, 0x02);
	spin_unlock(&lock);
	pr_info("temp alert %d\n", last);
	return IRQ_HANDLED;
}

static irqreturn_t temp_thread(int irq, void *data)
{
	return IRQ_HANDLED;
}

static int temp_probe(struct i2c_client *client)
{
	int ret;

	sensor = client;
	ret = request_irq(client->irq, temp_irq, IRQF_NO_THREAD, "temp", NULL);
	if (ret)
		return ret;
	/* a second, "faster" path added later */
	return request_threaded_irq(client->irq + 1, NULL, temp_thread, 0, "temp-fast", NULL);
}

static struct i2c_driver temp_driver = {
	.driver = { .name = "acme-temp" },
	.probe = temp_probe,
};
module_i2c_driver(temp_driver);
MODULE_LICENSE("GPL");
```

#### The Silicon-Hardened Production Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_temp.c - I2C temperature sensor with an alert line: hard IRQ timestamps, threaded handler, workqueue */
#include <linux/i2c.h>
#include <linux/interrupt.h>
#include <linux/ktime.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/spinlock.h>
#include <linux/workqueue.h>

#define REG_TEMP	0x00
#define REG_STATUS	0x02		/* reading it clears the alert and releases the line */

struct acme_temp {
	struct i2c_client *client;
	raw_spinlock_t lock;		/* taken in hard-IRQ context: must stay a spinning lock on PREEMPT_RT */
	ktime_t alert_at;		/* written by the hard handler */
	int last_mdegc;
	struct work_struct report;
};

/* Hard IRQ: no sleeping, no bus access. Record when it happened and hand over to the thread. */
static irqreturn_t acme_temp_hardirq(int irq, void *data)
{
	struct acme_temp *t = data;
	unsigned long flags;

	raw_spin_lock_irqsave(&t->lock, flags);
	t->alert_at = ktime_get();
	raw_spin_unlock_irqrestore(&t->lock, flags);
	return IRQ_WAKE_THREAD;
}

/* Thread (SCHED_FIFO 50 by default): may sleep, so I2C is fine here. The line stays masked until we return
 * (IRQF_ONESHOT), which is what keeps a level-triggered alert from storming while the bus transfer runs. */
static irqreturn_t acme_temp_thread(int irq, void *data)
{
	struct acme_temp *t = data;
	s32 status = i2c_smbus_read_byte_data(t->client, REG_STATUS);
	s32 raw = i2c_smbus_read_word_swapped(t->client, REG_TEMP);

	if (status < 0 || raw < 0)
		return IRQ_HANDLED;	/* status read failed: the line is still asserted, the core will retry */
	t->last_mdegc = (s16)raw * 125 / 32;	/* 1/256 degC per LSB -> milli-degC */
	queue_work(system_unbound_wq, &t->report);	/* slow, non-urgent work off the RT thread */
	return IRQ_HANDLED;
}

static void acme_temp_report(struct work_struct *work)
{
	struct acme_temp *t = container_of(work, struct acme_temp, report);
	unsigned long flags;
	ktime_t at;

	raw_spin_lock_irqsave(&t->lock, flags);
	at = t->alert_at;
	raw_spin_unlock_irqrestore(&t->lock, flags);
	dev_warn_ratelimited(&t->client->dev, "over-temperature %d mdegC at %lld ns\n", t->last_mdegc,
			     ktime_to_ns(at));
}

static void acme_temp_cancel(void *data)
{
	struct acme_temp *t = data;

	cancel_work_sync(&t->report);
}

static int acme_temp_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct acme_temp *t;
	int ret;

	t = devm_kzalloc(dev, sizeof(*t), GFP_KERNEL);
	if (!t)
		return -ENOMEM;
	t->client = client;
	raw_spin_lock_init(&t->lock);
	INIT_WORK(&t->report, acme_temp_report);
	/* Registered before the IRQ, so it runs after the IRQ is freed: no work queued after teardown. */
	ret = devm_add_action_or_reset(dev, acme_temp_cancel, t);
	if (ret)
		return ret;
	if (i2c_smbus_read_byte_data(client, REG_STATUS) < 0)	/* clear a stale alert before enabling */
		return dev_err_probe(dev, -ENODEV, "no response at 0x%02x\n", client->addr);
	return devm_request_threaded_irq(dev, client->irq, acme_temp_hardirq, acme_temp_thread,
					 IRQF_ONESHOT, dev_name(dev), t);
}

static const struct of_device_id acme_temp_of_match[] = {
	{ .compatible = "acme,temp-sensor" },
	{ }
};
MODULE_DEVICE_TABLE(of, acme_temp_of_match);

static struct i2c_driver acme_temp_driver = {
	.driver = {
		.name = "acme-temp",
		.of_match_table = acme_temp_of_match,
	},
	.probe = acme_temp_probe,
};
module_i2c_driver(acme_temp_driver);
MODULE_DESCRIPTION("Acme temperature sensor");
MODULE_LICENSE("GPL");
```

### 2.2 The context gate

```python
# irq_lint.py - interrupt-context rules: what may run in a hard handler, on mainline and on PREEMPT_RT
"""Usage: python irq_lint.py <driver.c> ...

Finds the primary (hard) handler and the thread function of every request_irq / request_threaded_irq /
devm_request_irq / devm_request_threaded_irq, then checks:
  I1 a call that can sleep inside a hard handler (bus I/O, msleep/usleep_range, mutex, GFP_KERNEL allocation,
     wait_event, schedule): "BUG: scheduling while atomic", or a silent deadlock
  I2 request_threaded_irq(..., NULL handler, ...) without IRQF_ONESHOT: kernel/irq/manage.c rejects it
     ("Threaded irq requested with handler=NULL and !ONESHOT")
  I3 spin_lock (spinlock_t) inside a hard handler registered IRQF_NO_THREAD: on PREEMPT_RT spinlock_t is a
     sleeping rt_mutex, and a never-threaded handler must use raw_spinlock_t
  I4 printk/pr_info in a hard handler (not rate limited): a console in the IRQ path turns an alert storm into
     a latency disaster
  I5 IRQF_SHARED with a NULL dev_id (cannot be freed, cannot be told apart)
"""
import re
import sys

SLEEPING = r"\b(msleep|usleep_range|ssleep|mutex_lock\w*|i2c_\w+|spi_sync\w*|spi_write\w*|spi_read\w*|regmap_\w+|" \
           r"wait_event\w*|schedule\w*|kmalloc|kzalloc|devm_kzalloc|copy_to_user|copy_from_user|vmalloc)\s*\("


def functions(src):
    out = {}
    for m in re.finditer(r"^\w[\w\s\*]*?\b(\w+)\s*\([^;{]*\)\s*\{(.*?)^\}", src, re.M | re.S):
        out[m.group(1)] = m.group(2)
    return out


def lint(path):
    src = re.sub(r"/\*.*?\*/", " ", open(path, encoding="utf-8").read(), flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    funcs, out = functions(src), []
    for m in re.finditer(r"\b(devm_request_threaded_irq|request_threaded_irq|devm_request_irq|request_irq)\s*\((.*?)\);",
                         src, re.S):
        call, args = m.group(1), [a.strip() for a in re.split(r",(?![^()]*\))", m.group(2))]
        off = 1 if call.startswith("devm_") else 0                  # devm_ variants take dev first
        hard = args[1 + off]
        thread = args[2 + off] if "threaded" in call else None
        flags = args[3 + off] if "threaded" in call else args[2 + off]
        dev_id = args[-1]
        line = src[:m.start()].count("\n") + 1
        if thread and hard == "NULL" and "IRQF_ONESHOT" not in flags:
            out.append(f"I2 line {line}: {call}(NULL handler) without IRQF_ONESHOT: the kernel refuses it")
        if "IRQF_SHARED" in flags and dev_id == "NULL":
            out.append(f"I5 line {line}: IRQF_SHARED with a NULL dev_id")
        body = funcs.get(hard)
        if body is None:
            continue
        for s in sorted(set(re.findall(SLEEPING, body))):
            out.append(f"I1 {hard}(): {s}() may sleep, and {hard} runs in hard-IRQ context")
        if "IRQF_NO_THREAD" in flags and re.search(r"\bspin_lock(?:_irqsave)?\s*\(", body):
            out.append(f"I3 {hard}(): spinlock_t in an IRQF_NO_THREAD handler sleeps on PREEMPT_RT: use raw_spinlock_t")
        if re.search(r"\b(printk|pr_info|pr_err|pr_warn|dev_info|dev_err)\s*\(", body):
            out.append(f"I4 {hard}(): unthrottled printk in the hard handler")
    return out


def main():
    total = 0
    for path in sys.argv[1:]:
        found = lint(path)
        total += len(found)
        print(f"{path.replace(chr(92), '/').rsplit('/', 1)[-1]}: {len(found)} finding(s)")
        for f in found:
            print("   ", f)
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

```text
acme_temp.c: 0 finding(s)
acme_temp_fragile.c: 6 finding(s)
    I1 temp_irq(): i2c_smbus_read_byte_data() may sleep, and temp_irq runs in hard-IRQ context
    I1 temp_irq(): i2c_smbus_read_word_swapped() may sleep, and temp_irq runs in hard-IRQ context
    I1 temp_irq(): msleep() may sleep, and temp_irq runs in hard-IRQ context
    I3 temp_irq(): spinlock_t in an IRQF_NO_THREAD handler sleeps on PREEMPT_RT: use raw_spinlock_t
    I4 temp_irq(): unthrottled printk in the hard handler
    I2 line 38: request_threaded_irq(NULL handler) without IRQF_ONESHOT: the kernel refuses it
acme_temp.c: 0 finding(s)
acme_temp_fragile.c: 0 finding(s)
index: 69886 function/macro names, 20008 structs from include/ and arch/arm64/include
```

The fragile driver passes the API check (every function exists) and fails the context check on all five rule classes. On PREEMPT_RT the `spinlock_t` inside an `IRQF_NO_THREAD` handler is a sleeping lock in atomic context, and on any kernel the I2C calls sleep in hard IRQ.

### 2.3 Priority inheritance and IRQ-thread priority, simulated

```python
# rt_sched_sim.py - priority inversion, priority inheritance and IRQ-thread priorities on one CPU, tick by tick
"""Usage: python rt_sched_sim.py

A fixed-priority preemptive scheduler (SCHED_FIFO semantics: the highest runnable priority runs) on one CPU,
1 tick = 10 us. Scenario 1, the classic inversion: L (prio 10) takes a lock and needs 20 ticks inside it;
M (prio 30, a CPU hog for 300 ticks) wakes at tick 5; H (prio 80, needs the lock for 5 ticks) wakes at tick 6.
  mutex without priority inheritance : M preempts L while L holds the lock, H waits for all of M
  rt_mutex (what spinlock_t and mutex become on PREEMPT_RT): L inherits H's priority while H waits
  raw_spinlock_t: preemption disabled while held, so nothing preempts L, nor H, nor any other work
Scenario 2: a network IRQ thread at its default SCHED_FIFO 50 (kernel/irq/manage.c sched_set_fifo:
MAX_RT_PRIO/2) against an application thread at FIFO 80 that spins for 400 ticks: the IRQ thread, and every
packet behind it, waits.
"""


def simulate(tasks, lock_kind, horizon=1000):
    """tasks: name -> {prio, wake, plan: list of ('cpu', n) | ('lock', n)}. Returns completion tick per task."""
    state = {n: {"pc": 0, "left": None, "done": None, **t} for n, t in tasks.items()}
    owner, waiters = None, []
    for tick in range(horizon):
        ready = []
        for n, s in state.items():
            if s["done"] is not None or tick < s["wake"]:
                continue
            kind, length = s["plan"][s["pc"]]
            if kind == "lock" and owner not in (None, n):
                if n not in waiters:
                    waiters.append(n)
                continue
            ready.append(n)

        def eff(n):                                        # effective priority
            p = state[n]["prio"]
            if lock_kind == "rt_mutex" and n == owner and waiters:
                p = max(p, max(state[w]["prio"] for w in waiters))
            return p

        if lock_kind == "raw_spinlock" and owner is not None and owner in ready:
            run = owner                                    # preemption disabled while the lock is held
        else:
            run = max(ready, key=eff, default=None)
        if run is None:
            continue
        s = state[run]
        kind, length = s["plan"][s["pc"]]
        if kind == "lock" and owner is None:
            owner = run
            if run in waiters:
                waiters.remove(run)
        if s["left"] is None:
            s["left"] = length
        s["left"] -= 1
        if s["left"] == 0:
            s["left"] = None
            if kind == "lock":
                owner = None
            s["pc"] += 1
            if s["pc"] == len(s["plan"]):
                s["done"] = tick + 1
    return {n: s["done"] for n, s in state.items()}


def main():
    inversion = {
        "L": {"prio": 10, "wake": 0, "plan": [("cpu", 2), ("lock", 20)]},
        "M": {"prio": 30, "wake": 5, "plan": [("cpu", 300)]},
        "H": {"prio": 80, "wake": 6, "plan": [("lock", 5)]},
    }
    fails = 0
    print("== priority inversion: H's response time (wake at tick 6, 1 tick = 10 us)")
    results = {}
    for kind in ("mutex", "rt_mutex", "raw_spinlock"):
        done = simulate(inversion, kind)
        results[kind] = done["H"] - 6
        print(f"   {kind:<13} H done after {results[kind]:>3} ticks ({results[kind] * 10:>4} us); "
              f"M done at {done['M']}, L at {done['L']}")
    fails += not (results["mutex"] > 300 > 30 > results["rt_mutex"])     # unbounded vs bounded by L's section
    fails += not (results["rt_mutex"] <= 25)
    irq = {
        "app-rt": {"prio": 80, "wake": 0, "plan": [("cpu", 400)]},
        "irq/57-eth0": {"prio": 50, "wake": 10, "plan": [("cpu", 3)]},
    }
    print("== IRQ thread at FIFO 50 vs an application thread at FIFO 80")
    for label, prio in (("default (sched_set_fifo: 50)", 50), ("raised with chrt to 90", 90)):
        irq["irq/57-eth0"]["prio"] = prio
        done = simulate(irq, "mutex")
        wait = done["irq/57-eth0"] - 10
        print(f"   {label:<30} packet handled {wait:>3} ticks ({wait * 10:>4} us) after the interrupt")
        fails += not ((wait > 300) if prio == 50 else (wait <= 3))
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
== priority inversion: H's response time (wake at tick 6, 1 tick = 10 us)
   mutex         H done after 321 ticks (3210 us); M done at 305, L at 322
   rt_mutex      H done after  22 ticks ( 220 us); M done at 327, L at 23
   raw_spinlock  H done after  21 ticks ( 210 us); M done at 327, L at 22
== IRQ thread at FIFO 50 vs an application thread at FIFO 80
   default (sched_set_fifo: 50)   packet handled 393 ticks (3930 us) after the interrupt
   raised with chrt to 90         packet handled   3 ticks (  30 us) after the interrupt
ALL PASSED: 0 failure(s)
```

### 2.4 Measuring latency on the target

```bash
# Kernel: CONFIG_PREEMPT_RT=y (02.2 fragment), isolcpus/nohz_full for the RT cores where appropriate
rtla timerlat top -P f:95 -d 10m            # timer IRQ -> thread latency per CPU, with the blocking cause
rtla osnoise top -d 10m                     # noise from IRQs, softirqs and other threads on each CPU
cyclictest -m -S -p 95 -i 200 -D 10m -h 400 # classic histogram, mlockall, one thread per CPU
echo 1 > /sys/kernel/tracing/osnoise/stop_tracing_us   # with rtla: stop and dump the trace on the first outlier
ps -eLo pid,cls,rtprio,comm | grep 'irq/'   # every IRQ thread and its priority: check against the design
```

Run these under worst-case load (network flood, storage I/O, GPU, thermal throttling) for hours, not minutes. Tail latency is the product requirement.

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Mechanism | Detect | Fix |
|---|---|---|---|
| `BUG: scheduling while atomic` | Sleeping call in hard IRQ or under a spinlock | Backtrace names the caller | Threaded handler for bus I/O (I1) |
| CPU pegged in an IRQ, `nobody cared (try booting with "irqpoll")`, line disabled | Level IRQ not cleared; shared handler returns `IRQ_HANDLED` for others' interrupts | `/proc/interrupts` count racing; the message | Quiesce the source; `IRQF_ONESHOT`; `IRQ_NONE` when not ours |
| Threaded IRQ request fails at probe | `handler=NULL` without `IRQF_ONESHOT` | dmesg "Threaded irq requested with handler=NULL and !ONESHOT" | Add `IRQF_ONESHOT` (I2) |
| RT task misses deadlines under load | Priority inversion (no PI), or IRQ thread below a long RT task | `rtla timerlat` blocking cause; `sched_switch` trace | PI locks; deliberate IRQ thread priorities |
| Deadlock only on the RT kernel | `spinlock_t` in an `IRQF_NO_THREAD` / atomic path (sleeps on RT) | lockdep splat (`CONFIG_PROVE_LOCKING`) | `raw_spinlock_t` with a tiny section (I3) |
| Latency spikes correlate with log bursts | printk from IRQ paths to a slow serial console | spikes vs console output | Rate limit; defer reporting to a workqueue (I4) |

**Post-mortem method for a latency spike:**
1. `rtla timerlat` with `--auto <threshold>` stops tracing at the first outlier and prints the blocking chain: which IRQ, softirq or thread ran instead of the RT task, and for how long.
2. For a hard lockup with no console, the hard-lockup detector (NMI watchdog via the arm64 pseudo-NMI, `irqchip.gicv3_pseudo_nmi=1`) or the hardware watchdog (03.1) resets the board.
3. pstore (04.4) keeps the backtrace for the next boot.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · Where does the I2C read go?

**Initial Prompt:** "A sensor raises an interrupt when a threshold trips, and the driver must read two I2C registers. Where does that code live?"

**L5 Answer:** "In the interrupt handler, since it's the interrupt that tells us to read."

**Why L5 Bricks Devices at Scale:**
- **I2C transfers sleep** (they wait for the controller's completion), so in a hard handler they crash with "scheduling while atomic" or deadlock.
- **A level-triggered alert stays asserted until the status register is read,** which takes the same slow I2C transfer. Unmasking before that storms the CPU.

**L7 Principal Defense:**
- **Split it by context:**
  - the hard handler only timestamps (under a `raw_spinlock_t` if shared) and returns `IRQ_WAKE_THREAD`;
  - the threaded handler does the I2C reads;
  - `IRQF_ONESHOT` keeps the line masked until the thread clears the source.
- **Push slow, non-urgent reporting to a workqueue**, cancelled on teardown in the right order (§2.1).
- **Gate it** with `irq_lint.py` and lockdep in CI.

### Chain 2 · Moving to PREEMPT_RT

**Initial Prompt:** "We're enabling PREEMPT_RT for a 200 µs control loop. Which drivers do you audit first, and for what?"

**L5 Answer:** "RT is in mainline now, so drivers should just work. Turn it on and run the tests."

**Why L5 Bricks Devices at Scale:**
- **Correctness:** every `spinlock_t` becomes a sleeping lock. Code that takes one in a never-threaded context (`IRQF_NO_THREAD`, per-CPU timers, or a `local_irq_disable()` region) is now sleeping in atomic context.
- **Determinism:** default IRQ thread priorities (FIFO 50) and long preempt-disabled regions in vendor drivers decide the latency you get. "Tests pass" says nothing about the 99.9999th percentile.

**L7 Principal Defense:**
- **Audit:**
  - `IRQF_NO_THREAD` handlers and their locks (`raw_spinlock_t`, tiny sections);
  - `local_irq_*` and `preempt_disable` regions;
  - vendor drivers' long critical sections.
- **Design the priority map:**
  - the control-loop thread;
  - the IRQ threads it depends on, above it or just below;
  - everything else below.
- **Verify on target under worst-case load for hours** with `rtla timerlat`/`osnoise` and `cyclictest` histograms, with tracing that stops at the first outlier.

### Chain 3 · The inversion

**Initial Prompt:** "A high-priority task occasionally misses a 1 ms deadline by 3 ms, always when a medium-priority batch job runs. They don't share any lock. Diagnose."

**L5 Answer:** "If they share no lock, it's not a locking problem. The batch job must be stealing CPU; lower its priority."

**Why L5 Bricks Devices at Scale:**
- **The high-priority task shares a lock with a *low*-priority task,** which the medium job preempts while it holds the lock. That's the textbook inversion: H waits for M without touching M's code.
- **Lowering M's priority helps only until the next medium task.** Inversions are a property of the lock, not of M.

**L7 Principal Defense:**
- **Find the chain with tracing:** `rtla timerlat` blocking reasons, `sched_switch` and lock events.
- **Use priority-inheriting locks.** On PREEMPT_RT, kernel mutexes and spinlocks are rt_mutexes. In userspace, `PTHREAD_PRIO_INHERIT` mutexes.
- **Keep critical sections short and bounded.**
- **The model shows the difference:** 3.2 ms without PI vs 220 µs with it (§2.3). Measure the same on target.

### Chain 4 · The silent network

**Initial Prompt:** "On the RT build, the device stops answering on Ethernet for seconds at a time while the motion-control thread is busy, but the control loop itself is fine. Why?"

**L5 Answer:** "The NIC driver must have a bug on RT. File it with the vendor."

**Why L5 Bricks Devices at Scale:**
- **On RT the NIC's interrupt runs as a thread at FIFO 50.** The motion thread at FIFO 80 that runs for long stretches starves it, so packets queue, then drop, then the link layer times out.
- **Nothing is broken except the priority design.** The vendor can't fix it.

**L7 Principal Defense:**
- **Make IRQ thread priority an explicit part of the system design:** list every `irq/*` thread and set priorities at boot with `chrt` from a unit.
- **Bound the motion thread's runtime per period,** and consider `SCHED_DEADLINE`.
- **Put RT work on isolated cores**, with network IRQ affinity elsewhere.
- **The simulation's second scenario** shows 3.9 ms at default vs 30 µs at a deliberate priority.

### Chain 5 · Interrupt storms

**Initial Prompt:** "A board occasionally locks up with one CPU at 100% in interrupt context. Then the kernel prints 'irq 57: nobody cared' and the device stops working. Explain."

**L5 Answer:** "A hardware glitch on the interrupt line. Add a filter capacitor."

**Why L5 Bricks Devices at Scale:**
- **A level-triggered source is never cleared.** The handler returns `IRQ_HANDLED` without reading the status register that deasserts the line, or the line is shared and the handler claims interrupts that aren't its own.
- **The kernel's spurious-IRQ detector then disables the line ("nobody cared").** The device is dead until reboot. Hardware filters don't change software that never clears the source.

**L7 Principal Defense:**
- **Every handler checks its own status** and returns `IRQ_NONE` when it isn't the source (required for shared lines).
- **Clear the source** before unmasking, using `IRQF_ONESHOT` for threaded handlers that must do slow bus I/O to clear it.
- **Specify the trigger type correctly in DT** (level vs edge, polarity).
- **Count interrupts per source in telemetry** to catch slow storms before the detector fires.

### Chain 6 · Bottom halves in 2026

**Initial Prompt:** "Tasklet, softirq, workqueue, threaded IRQ: which do you use for new driver code, and why?"

**L5 Answer:** "Tasklets, because they're fast and run soon after the interrupt."

**Why L5 Bricks Devices at Scale:**
- **Tasklets run in softirq context:** no sleeping, and on RT they're threaded anyway. They are being phased out of the kernel.
- **New code that uses them** gets the drawbacks of atomic context without the priority control of threaded IRQs, and has to be rewritten later.

**L7 Principal Defense:**
- **Threaded IRQ handlers** for interrupt-driven work: sleepable, priority-controlled, `IRQF_ONESHOT` masking.
- **Workqueues** for deferred, non-urgent work: `system_unbound_wq` or a dedicated `alloc_workqueue` with `WQ_MEM_RECLAIM` if it's on a memory-reclaim path.
- **The hard handler only acknowledges.**
- **Softirqs** stay the domain of the networking and block cores.
- **NAPI** for network drivers, the subsystem's own bottom half (07.4).

---

## 5. Invariants Checklist

- [ ] Hard handlers: no sleeping calls, no unthrottled printk; ack/timestamp only; `IRQ_NONE` when not the source (`irq_lint.py` clean).
- [ ] Threaded handlers for bus I/O, always `IRQF_ONESHOT` with a NULL primary; slow work in workqueues, cancelled on teardown.
- [ ] Data shared with never-threaded handlers under `raw_spinlock_t` with tiny sections; lockdep (`PROVE_LOCKING`) in CI on the RT config.
- [ ] RT systems: documented priority map for application and IRQ threads, applied at boot; PI locks in kernel and userspace.
- [ ] Latency measured on target under worst-case load with `rtla timerlat`/`osnoise` and `cyclictest`; tracing stops at the first outlier.
- [ ] DT trigger types match the hardware (level/edge, polarity).

## 6. References

- Linux v7.2: `kernel/irq/manage.c`, `kernel/sched/syscalls.c`, `kernel/Kconfig.preempt`, `include/dt-bindings/interrupt-controller/arm-gic.h`, `tools/tracing/rtla/`; `Documentation/core-api/genericirq.rst`, `Documentation/locking/locktypes.rst` (PREEMPT_RT lock semantics). <https://github.com/torvalds/linux/tree/v7.2>
- Arm Generic Interrupt Controller Architecture Specification GICv3/v4 (IHI 0069).
- rt-tests (cyclictest, hwlatdetect). <https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/>
- In this KB: [02.2 kernel configuration](../02-Yocto-Project-BitBake-and-Cross-Toolchain-Internals/02-bsp-layer-engineering-machine-distro-overrides-and-kernel-devtool.md) · [04.1 drivers](01-kernel-boot-flow-device-tree-of-matching-pinmux-and-common-clock-framework.md) · [04.4 pstore](04-high-speed-peripherals-pcie-nvme-mipi-i2c-spi-regmap-and-pstore-ramoops.md)
