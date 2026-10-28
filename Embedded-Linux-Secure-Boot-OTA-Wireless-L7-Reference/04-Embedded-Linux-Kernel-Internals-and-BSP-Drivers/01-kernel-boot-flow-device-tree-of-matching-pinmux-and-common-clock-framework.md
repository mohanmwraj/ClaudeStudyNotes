# 04.1 · Kernel Boot Flow, Device Tree OF Matching, Pinmux and the Common Clock Framework

> **Folder 04 · File 1 of 4.** Between U-Boot's `bootm` (01.4, 03.1) and the first userspace process, the kernel turns a flattened device tree into devices, matches drivers to them, and brings up the clocks, pins, resets and interrupts each one needs. Most board bring-up bugs live in that hand-off:
> - a compatible string the driver doesn't list;
> - a `clock-names` entry spelled differently from the driver's request;
> - an interrupt specifier with the wrong cell count;
> - a pin group that is never applied;
> - a clock the kernel gates at `late_initcall` because nothing claimed it.
>
> None of these fail `dtc`. They fail at probe, or worse, the driver probes with the wrong data.
>
> **Pinned.** Linux **v7.2**:
> - `Documentation/arch/arm64/booting.rst`;
> - `drivers/of/base.c` (`__of_device_is_compatible`, `__of_match_node`);
> - `drivers/base/pinctrl.c` (`pinctrl_bind_pins`);
> - `drivers/clk/clk.c` (`clk_disable_unused`);
> - `include/linux/clk-provider.h`, `include/linux/platform_device.h`.
>
> **Verification.**
> - `kapi_check.py` checks driver code against an index of every function, macro and struct in v7.2's `include/` and `arch/arm64/include` (≈70k names, ≈20k structs): missing APIs, missing struct fields (nested initializers included), callback return types.
> - `dt_probe_check.py` implements the kernel's OF match scoring and checks every resource the driver requests against the node and its providers.
> - The trees pass `dts_lint.py` (01.4), which in this folder gained dtc's rule that a non-empty `ranges` satisfies a unit address.
> - No kernel build here: that needs `make modules_prepare` on the configured tree (README).

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 From `bootm` to `probe()`

```text
 U-Boot bootm (01.4): verified FIT → kernel Image at a 2 MB-aligned base + text_offset, DTB fixed up (chosen, memory)
   x0 = physical address of the DTB, x1 = x2 = x3 = 0; PSTATE.DAIF masked; non-secure EL2 (recommended) or EL1;
   MMU off; I-cache may be on but must hold no stale lines; the image range cleaned to PoC   (booting.rst)
 head.S: primary_entry → set up page tables, enable MMU → start_kernel()
 start_kernel: setup_arch → unflatten_device_tree (FDT → struct device_node tree)
               → early consoles (earlycon=), memblock from /memory + /reserved-memory (04.2)
               → GICv3 init from the interrupt-controller node (04.3)
 initcalls:    of_platform_populate: every node under simple-bus / root with compatible → struct platform_device
               driver registration (module_platform_driver) → bus match → really_probe():
                   pinctrl_bind_pins()  ── "init" state if present, else "default" (drivers/base/pinctrl.c)
                   driver->probe()      ── clocks, resets, regulators, IRQs, DMA via their consumer APIs
                   -EPROBE_DEFER        ── supplier not ready: put on the deferred list, retried later
 late_initcall_sync(clk_disable_unused): every clock nobody enabled is gated (unless clk_ignore_unused,
               CLK_IGNORE_UNUSED or CLK_IS_CRITICAL)
```

### 1.2 How a driver matches a node

`__of_match_node()` walks the driver's `of_device_id` table and keeps the entry with the highest score from `__of_device_is_compatible()`:

```text
 score = INT_MAX/2 - (index << 2)        index = position of the matching string in the NODE's compatible list
         + 2 if type matches, + 1 if name matches;   comparison: of_compat_cmp = strcasecmp (case-insensitive)
 ties keep the earlier table entry (score > best_score)
```

Two consequences:
- **The node's compatible order decides, not the table's.** `compatible = "acme,imx8mm-fan", "acme,fan"` binds the `imx8mm` entry even if the table lists the generic one first.
- **A node that lists only the generic string binds the generic data.** That's a silent behavioral difference: here, the wrong pulses-per-revolution and a doubled RPM reading.

Driver variants therefore belong in `.data` of the match table, read with `device_get_match_data()`. Never write `if (of_machine_is_compatible("fsl,imx8mm"))` in a driver, which couples it to the board instead of the device.

### 1.3 Pin control

- A node's `pinctrl-names = "default", "sleep"` names states. `pinctrl-0` and `pinctrl-1` reference pin-group nodes under the pin controller. On i.MX, `fsl,pins` holds 6 cells per pad: mux register, config register, input register, mux value, input value, pad settings.
- **The driver core applies the state before probe.** `pinctrl_bind_pins()` looks up `PINCTRL_STATE_DEFAULT`; if absent, it logs at debug level and returns 0 ("no default pinctrl state"). The driver then probes with whatever mux the pins had: often the bootloader's, sometimes another function's.
- **The driver switches states itself** for power management, e.g. `pinctrl_pm_select_sleep_state()` in suspend.

### 1.4 The Common Clock Framework (CCF)

| Concept | Where | Why it matters |
|---|---|---|
| Provider | Clock controller node, `#clock-cells` | The specifier length every consumer must use |
| Consumer | `clocks` + `clock-names`, `devm_clk_get*(dev, "name")` | Lookup is by **name**: a mismatch is `-ENOENT`, not a warning |
| Tree | Parent/child clocks, `CLK_SET_RATE_PARENT` ("propagate rate change up one level") | A consumer's `clk_set_rate()` may retune a parent shared with others |
| Gating | `clk_prepare_enable()` refcounts; `clk_disable_unused()` at `late_initcall_sync` | A clock nothing claimed is turned off late in boot, often taking a working peripheral down |
| Never gate | `CLK_IS_CRITICAL` (provider flag), `clk_ignore_unused` (cmdline, debug only) | Critical clocks belong in the provider, never on the command line of a product |

**`devm_clk_get_enabled()`** gets, prepares and enables in one call, and undoes all three on unbind or probe failure, in reverse order. It removes the most common resource leak in drivers.

### 1.5 Deferred probe

- **Suppliers are found and waited for.** A consumer whose supplier (clock, regulator, reset, GPIO, PHY) hasn't probed gets `-EPROBE_DEFER` from the consumer API and is retried. `fw_devlink` derives supplier/consumer links from DT phandles, so most ordering happens without explicit retries.
- **The driver has to propagate the error.** It must return the error unchanged, `return dev_err_probe(dev, err, "...")`, which logs only real errors and records the deferral reason in `/sys/kernel/debug/devices_deferred`.
- **Hard failure on defer leaves the device dead forever.** A driver that prints and returns `-EINVAL` on any `clk_get()` failure converts a transient deferral into a permanently dead device, and which boots hit it depends on probe order.

---

## 2. Production Code & Configuration Blueprints

### 2.1 The platform driver

#### The Fragile Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_fan_fragile.c - the same driver as it arrived in a 5.4-era vendor BSP, forward-ported by search-and-replace */
#include <linux/clk.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>

#define FAN_BASE	0x30660000	/* "the block is always here" */
#define FAN_CTRL	0x00
#define FAN_IRQ_STAT	0x08
#define FAN_IRQ_EN	0x0c

static void __iomem *base;
static struct clk *clk;
static unsigned long stalls;

static irqreturn_t fan_irq(int irq, void *data)
{
	writel(readl(base + FAN_IRQ_STAT), base + FAN_IRQ_STAT);
	stalls++;
	return IRQ_HANDLED;
}

static int fan_probe(struct platform_device *pdev)
{
	int irq = platform_get_irq(pdev, 0);

	if (request_irq(irq, fan_irq, IRQF_SHARED, "fan", NULL))
		return -EINVAL;
	base = devm_ioremap_nocache(&pdev->dev, FAN_BASE, 0x1000);
	clk = clk_get(&pdev->dev, "ipg");
	if (IS_ERR(clk)) {
		dev_err(&pdev->dev, "no clock\n");
		return -EINVAL;
	}
	clk_prepare_enable(clk);
	if (of_machine_is_compatible("fsl,imx8mm"))
		writel(0x8001, base + FAN_CTRL);
	else
		writel(0x4001, base + FAN_CTRL);
	writel(1, base + FAN_IRQ_EN);
	return 0;
}

static int fan_remove(struct platform_device *pdev)
{
	free_irq(platform_get_irq(pdev, 0), NULL);
	return 0;
}

static const struct of_device_id fan_of_match[] = {
	{ .compatible = "acme,fan" },
	{ }
};

static struct platform_driver fan_driver = {
	.probe = fan_probe,
	.remove_new = fan_remove,
	.driver = {
		.name = "acme-fan",
		.of_match_table = fan_of_match,
	},
};
module_platform_driver(fan_driver);
MODULE_LICENSE("GPL");
```

What's wrong with it:
- **It maps a hard-coded physical address.**
- **`devm_ioremap_nocache()`** was removed years ago (see the check below).
- **It requests the shared IRQ with a `NULL` dev_id** before the block is mapped or clocked, so a pending interrupt runs the handler on an unmapped base.
- **Deferral becomes failure.** It turns `-EPROBE_DEFER` into `-EINVAL`.
- **The clock is never disabled.**
- **It branches on the machine** instead of the device.
- **`.remove_new` returning `int`** is a forward-port by search-and-replace onto a kernel where `.remove` returns `void`.

#### The Silicon-Hardened Production Way

```c
// SPDX-License-Identifier: GPL-2.0-only
/* acme_fan.c - platform driver for the Acme fan/tach block: DT match data, managed resources, deferred probe */
#include <linux/bitfield.h>
#include <linux/clk.h>
#include <linux/hwmon.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/property.h>
#include <linux/reset.h>

#define FAN_CTRL	0x00
#define  FAN_CTRL_EN	BIT(0)
#define  FAN_CTRL_DUTY	GENMASK(15, 8)
#define FAN_TACH	0x04
#define FAN_IRQ_STAT	0x08		/* write 1 to clear */
#define FAN_IRQ_EN	0x0c
#define  FAN_IRQ_STALL	BIT(0)

struct acme_fan_variant {
	u32 pulses_per_rev;
	u32 max_duty;
};

struct acme_fan {
	void __iomem *base;
	struct clk *clk;
	const struct acme_fan_variant *variant;
	unsigned long stalls;
};

static irqreturn_t acme_fan_irq(int irq, void *data)
{
	struct acme_fan *fan = data;
	u32 stat = readl_relaxed(fan->base + FAN_IRQ_STAT);

	if (!(stat & FAN_IRQ_STALL))
		return IRQ_NONE;		/* shared line: not ours */
	writel_relaxed(stat, fan->base + FAN_IRQ_STAT);
	fan->stalls++;
	return IRQ_HANDLED;
}

static int acme_fan_read(struct device *dev, enum hwmon_sensor_types type, u32 attr, int channel, long *val)
{
	struct acme_fan *fan = dev_get_drvdata(dev);
	u32 ticks;

	if (type != hwmon_fan || attr != hwmon_fan_input)
		return -EOPNOTSUPP;
	/* TACH counts pulses per second; the variant knows how many pulses one revolution produces. */
	ticks = readl_relaxed(fan->base + FAN_TACH);
	*val = (long)(ticks * 60 / fan->variant->pulses_per_rev);
	return 0;
}

static umode_t acme_fan_is_visible(const void *data, enum hwmon_sensor_types type, u32 attr, int channel)
{
	return type == hwmon_fan && attr == hwmon_fan_input ? 0444 : 0;
}

static const struct hwmon_ops acme_fan_hwmon_ops = {
	.is_visible = acme_fan_is_visible,
	.read = acme_fan_read,
};

static const struct hwmon_channel_info *const acme_fan_info[] = {
	HWMON_CHANNEL_INFO(fan, HWMON_F_INPUT),
	NULL
};

static const struct hwmon_chip_info acme_fan_chip = {
	.ops = &acme_fan_hwmon_ops,
	.info = acme_fan_info,
};

static int acme_fan_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct reset_control *rst;
	struct device *hwmon;
	struct acme_fan *fan;
	int irq, ret;

	fan = devm_kzalloc(dev, sizeof(*fan), GFP_KERNEL);
	if (!fan)
		return -ENOMEM;
	/* Per-SoC behaviour comes from the matched compatible, never from of_machine_is_compatible(). */
	fan->variant = device_get_match_data(dev);
	if (!fan->variant)
		return -ENODEV;

	fan->base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(fan->base))
		return PTR_ERR(fan->base);

	/* Enabled now, disabled and unprepared automatically on unbind or probe failure. A provider that
	 * is not ready yet returns -EPROBE_DEFER: dev_err_probe() stays quiet and records the reason. */
	fan->clk = devm_clk_get_enabled(dev, "ipg");
	if (IS_ERR(fan->clk))
		return dev_err_probe(dev, PTR_ERR(fan->clk), "ipg clock\n");

	rst = devm_reset_control_get_exclusive_deasserted(dev, NULL);
	if (IS_ERR(rst))
		return dev_err_probe(dev, PTR_ERR(rst), "reset\n");

	/* Hardware into a known state BEFORE the interrupt can fire. */
	writel_relaxed(0, fan->base + FAN_IRQ_EN);
	writel_relaxed(FAN_IRQ_STALL, fan->base + FAN_IRQ_STAT);
	writel_relaxed(FAN_CTRL_EN | FIELD_PREP(FAN_CTRL_DUTY, fan->variant->max_duty / 2), fan->base + FAN_CTRL);

	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;
	ret = devm_request_threaded_irq(dev, irq, NULL, acme_fan_irq, IRQF_ONESHOT | IRQF_SHARED,
					dev_name(dev), fan);
	if (ret)
		return dev_err_probe(dev, ret, "irq %d\n", irq);
	writel_relaxed(FAN_IRQ_STALL, fan->base + FAN_IRQ_EN);

	platform_set_drvdata(pdev, fan);
	hwmon = devm_hwmon_device_register_with_info(dev, "acme_fan", fan, &acme_fan_chip, NULL);
	return PTR_ERR_OR_ZERO(hwmon);
}

static void acme_fan_remove(struct platform_device *pdev)
{
	struct acme_fan *fan = platform_get_drvdata(pdev);

	/* Quiesce the block; devm then frees the IRQ, asserts reset and disables the clock, in reverse order. */
	writel_relaxed(0, fan->base + FAN_IRQ_EN);
	writel_relaxed(0, fan->base + FAN_CTRL);
}

static const struct acme_fan_variant imx8mm_variant = { .pulses_per_rev = 2, .max_duty = 255 };
static const struct acme_fan_variant generic_variant = { .pulses_per_rev = 1, .max_duty = 255 };

static const struct of_device_id acme_fan_of_match[] = {
	{ .compatible = "acme,imx8mm-fan", .data = &imx8mm_variant },
	{ .compatible = "acme,fan", .data = &generic_variant },
	{ }
};
MODULE_DEVICE_TABLE(of, acme_fan_of_match);

static struct platform_driver acme_fan_driver = {
	.probe = acme_fan_probe,
	.remove = acme_fan_remove,
	.driver = {
		.name = "acme-fan",
		.of_match_table = acme_fan_of_match,
	},
};
module_platform_driver(acme_fan_driver);

MODULE_DESCRIPTION("Acme fan/tach controller");
MODULE_LICENSE("GPL");
```

The kernel API gate, run against v7.2's headers:

```python
# kapi_check.py - check kernel driver code against the API the target kernel's headers actually declare
"""Usage: python kapi_check.py <linux-tree> <driver.c> ...

A full module build needs the target's configured tree (make modules_prepare). Before that exists, this gate
catches the class of breakage that follows a kernel upgrade, from the headers alone:
  K1 a function or function-like macro the driver calls that no header in include/ or arch/arm64/include
     declares or defines (removed or renamed API, e.g. devm_ioremap_nocache)
  K2 a designated initializer naming a field the struct does not have (nested initializers are checked
     against the member's own struct type, e.g. .driver = { .of_match_table = ... })
  K3 a function assigned to a function-pointer field whose return type differs from the field's
     (e.g. 'int remove()' where v6.11+ declares 'void (*remove)(struct platform_device *)')
  K4 a struct the driver initializes that neither the headers nor the driver itself define
Heuristic by design (no preprocessor, no type checker): a fast first gate, not a substitute for compiling
against the configured tree.
"""
import pathlib
import re
import sys

KEYWORDS = {"if", "for", "while", "switch", "return", "sizeof", "typeof", "__typeof__", "defined", "do",
            "case", "else", "goto", "alignof", "_Alignof", "__alignof__", "offsetof", "va_arg"}
PROTO = re.compile(r"\b(\w+)\s*\((?:[^;{}()]|\([^;{}()]*\))*\)\s*(?:__\w+(?:\([^)]*\))?\s*)*(?:;|\{)")
MACRO = re.compile(r"^\s*#\s*define\s+(\w+)\(", re.M)
STRUCT = re.compile(r"\bstruct\s+(\w+)\s*\{", re.S)


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def bodies(text):
    """struct name -> body text, found by brace matching (handles nested unions/structs)."""
    out = {}
    for m in STRUCT.finditer(text):
        depth, i = 1, m.end()
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        out.setdefault(m.group(1), text[m.end():i - 1])
    return out


def index_headers(tree):
    funcs, structs = set(), {}
    for root in (pathlib.Path(tree) / "include", pathlib.Path(tree) / "arch" / "arm64" / "include"):
        for h in root.rglob("*.h"):
            text = strip_comments(h.read_text(encoding="utf-8", errors="replace"))
            funcs.update(PROTO.findall(text))
            funcs.update(MACRO.findall(text))
            for k, v in bodies(text).items():
                structs.setdefault(k, v)
    return funcs, structs


def norm(t):
    t = re.sub(r"\b(static|inline|extern|__always_inline|__init|__exit|__cold|const)\b", " ", t)
    return " ".join(t.replace("*", " * ").split())


def struct_fields(body):
    """field -> ('fn', return type) | ('struct', type name) | ('data', None)."""
    fields = {}
    for m in re.finditer(r"([\w\s\*]+?)\(\s*\*\s*(\w+)\s*\)\s*\(", body):
        fields[m.group(2)] = ("fn", norm(m.group(1)))
    flat = re.sub(r"\([^()]*\)", "", re.sub(r"\{[^{}]*\}", ";", body))
    for decl in flat.split(";"):
        m = re.search(r"(?:struct\s+(\w+)\s+)?[\w\s\*]*?(\w+)\s*(?:\[[^\]]*\])?\s*(?::\s*\w+)?\s*$", decl.strip())
        if m and m.group(2) and m.group(2) not in fields:
            fields[m.group(2)] = ("struct", m.group(1)) if m.group(1) else ("data", None)
    return fields


def designators(body):
    """Top-level '.field = value' pairs; a value that is a {...} block is returned as ('{', inner)."""
    out, i, depth = [], 0, 0
    while i < len(body):
        c = body[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "." and depth == 0:
            m = re.match(r"\.(\w+)\s*=\s*", body[i:])
            if m:
                j = i + m.end()
                if body[j:j + 1] == "{":
                    d, k = 1, j + 1
                    while d:
                        d += {"{": 1, "}": -1}.get(body[k], 0)
                        k += 1
                    out.append((m.group(1), ("{", body[j + 1:k - 1])))
                    i = k
                    continue
                v = re.match(r"&?(\w+)", body[j:])
                out.append((m.group(1), v.group(1) if v else None))
                i = j
                continue
        i += 1
    return out


def check_init(sname, body, structs, own_types, out):
    if sname not in structs:
        out.append(f"K4 struct {sname} is defined in no header and not in the driver")
        return
    fields = struct_fields(structs[sname])
    for field, value in designators(body):
        if field not in fields:
            out.append(f"K2 struct {sname} has no field .{field}")
        elif isinstance(value, tuple):
            if fields[field][0] == "struct":
                check_init(fields[field][1], value[1], structs, own_types, out)
        elif fields[field][0] == "fn" and value in own_types and own_types[value] != fields[field][1]:
            out.append(f"K3 .{field} = {value}: returns '{own_types[value]}', struct {sname} wants "
                       f"'{fields[field][1]}'")


def check(path, funcs, structs):
    text = strip_comments(open(path, encoding="utf-8").read())
    local = {**structs, **bodies(text)}
    own_types = {m.group(2): norm(m.group(1)) for m in re.finditer(
        r"^((?:static\s+)?(?:inline\s+)?(?:const\s+)?(?:struct\s+\w+|enum\s+\w+|unsigned\s+\w+|\w+)[\s\*]*)\b(\w+)\s*\(",
        text, re.M)}
    defined = set(own_types) | set(MACRO.findall(text))
    out = []
    for name in sorted(set(re.findall(r"\b([A-Za-z_]\w*)\s*\(", text))):
        if name in KEYWORDS or name in defined or name.startswith("__builtin") or name in funcs:
            continue
        out.append(f"K1 {name}() is declared nowhere in this kernel's headers")
    for m in re.finditer(r"\bstruct\s+(\w+)\s+(?:const\s+)?\*?\s*(?:const\s+)?\w+(?:\[\])?\s*=\s*\{", text):
        d, k = 1, m.end()
        while d:
            d += {"{": 1, "}": -1}.get(text[k], 0)
            k += 1
        inner = text[m.end():k - 1]
        if re.search(r"^\s*\{", inner):                       # array of structs: check each element
            for em in re.finditer(r"\{([^{}]*)\}", inner):
                check_init(m.group(1), em.group(1), local, own_types, out)
        else:
            check_init(m.group(1), inner, local, own_types, out)
    return out


def main():
    funcs, structs = index_headers(sys.argv[1])
    total = 0
    for path in sys.argv[2:]:
        found = check(path, funcs, structs)
        total += len(found)
        print(f"{pathlib.Path(path).name}: {len(found)} finding(s)")
        for f in found:
            print("   ", f)
    print(f"index: {len(funcs)} function/macro names, {len(structs)} structs from include/ and arch/arm64/include")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

```text
acme_fan.c: 0 finding(s)
acme_fan_fragile.c: 2 finding(s)
    K1 devm_ioremap_nocache() is declared nowhere in this kernel's headers
    K2 struct platform_driver has no field .remove_new
index: 69886 function/macro names, 20008 structs from include/ and arch/arm64/include
```

The gate is exercised beyond what the fragile driver shows. Changing only `.remove_new` to `.remove` in the fragile file produces `K3 .remove = fan_remove: returns 'int', struct platform_driver wants 'void'`: v7.2's `struct platform_driver` declares `void (*remove)(struct platform_device *)`, and the CI step runs that variant too.

### 2.2 The device tree node and its providers

#### The Fragile Way

```dts
/* acme-fan-fragile.dts - the fan node as a board bring-up commit wrote it */
/dts-v1/;

/ {
	compatible = "acme,imx8mm-board", "fsl,imx8mm";
	#address-cells = <2>;
	#size-cells = <2>;

	soc@0 {
		compatible = "simple-bus";
		#address-cells = <1>;
		#size-cells = <1>;
		ranges = <0x0 0x0 0x0 0x3e000000>;

		gic: interrupt-controller@38800000 {
			compatible = "arm,gic-v3";
			reg = <0x38800000 0x10000>, <0x38880000 0xc0000>;
			#interrupt-cells = <3>;
			interrupt-controller;
		};

		clk: clock-controller@30380000 {
			compatible = "fsl,imx8mm-ccm";
			reg = <0x30380000 0x10000>;
			#clock-cells = <1>;
		};

		iomuxc: pinctrl@30330000 {
			compatible = "fsl,imx8mm-iomuxc";
			reg = <0x30330000 0x10000>;

			pinctrl_fan: fangrp {
				fsl,pins = <0x1c4 0x42c 0x0 0x5 0x0 0x116>;
			};
		};

		fan@30660000 {
			compatible = "acme,fan";
			reg = <0x30660000 0x1000>;
			interrupt-parent = <&gic>;
			interrupts = <99 4>;
			clocks = <&clk 241>, <&clk 242>;
			clock-names = "per";
			pinctrl-names = "default", "sleep";
			pinctrl-0 = <&pinctrl_fan>;
		};
	};
};
```

#### The Silicon-Hardened Production Way

```dts
/* acme-fan.dts - the fan block and every provider it depends on, as a minimal self-contained i.MX8MM-class tree */
/*
 * Addresses follow the i.MX8M Mini memory map (GICv3, CCM, SRC, IOMUXC); the clock index, reset index and
 * pad values are illustrative - a real board takes them from the SoC's dt-bindings headers (01.3 style
 * #include <dt-bindings/clock/imx8mm-clock.h>), which keeps them from drifting.
 */
/dts-v1/;

/ {
	compatible = "acme,imx8mm-board", "fsl,imx8mm";
	#address-cells = <2>;
	#size-cells = <2>;

	soc@0 {
		compatible = "simple-bus";
		#address-cells = <1>;
		#size-cells = <1>;
		ranges = <0x0 0x0 0x0 0x3e000000>;

		gic: interrupt-controller@38800000 {
			compatible = "arm,gic-v3";
			reg = <0x38800000 0x10000>, <0x38880000 0xc0000>;
			#interrupt-cells = <3>;
			interrupt-controller;
		};

		clk: clock-controller@30380000 {
			compatible = "fsl,imx8mm-ccm";
			reg = <0x30380000 0x10000>;
			#clock-cells = <1>;
		};

		src: reset-controller@30390000 {
			compatible = "fsl,imx8mm-src", "syscon";
			reg = <0x30390000 0x10000>;
			#reset-cells = <1>;
		};

		iomuxc: pinctrl@30330000 {
			compatible = "fsl,imx8mm-iomuxc";
			reg = <0x30330000 0x10000>;

			pinctrl_fan: fangrp {
				fsl,pins = <0x1c4 0x42c 0x0 0x5 0x0 0x116>;
			};

			pinctrl_fan_sleep: fansleepgrp {
				fsl,pins = <0x1c4 0x42c 0x0 0x5 0x0 0x100>;
			};
		};

		fan@30660000 {
			/* Most specific first: the driver binds this entry and its imx8mm_variant data. */
			compatible = "acme,imx8mm-fan", "acme,fan";
			reg = <0x30660000 0x1000>;
			interrupt-parent = <&gic>;
			interrupts = <0 99 4>;
			clocks = <&clk 241>;
			clock-names = "ipg";
			resets = <&src 7>;
			pinctrl-names = "default", "sleep";
			pinctrl-0 = <&pinctrl_fan>;
			pinctrl-1 = <&pinctrl_fan_sleep>;
		};
	};
};
```

Both pass structural lint, because the mistakes are semantic:

```text
acme-fan.dts: 9 nodes, 0 error(s)
acme-fan-fragile.dts: 7 nodes, 0 error(s)
```

The probe check binds nodes with the kernel's own scoring and checks every resource the driver asks for:

```python
# dt_probe_check.py - will this driver bind to this device-tree node, with which match data, and will probe succeed?
"""Usage: python dt_probe_check.py <board.dts> <driver.c>      (needs dts_lint.py alongside)

Binding follows drivers/of/base.c (v7.2): __of_device_is_compatible() scores a match on the node's compatible
list as INT_MAX/2 - (index << 2) with case-insensitive comparison (of_compat_cmp = strcasecmp), and
__of_match_node() keeps the best score (first table entry on a tie). Then, for every bound node, the resources
the driver asks for are checked against the node and its providers:
  P1 a node with the driver's vendor prefix that no table entry matches: the driver never binds
  P2 a clock requested by name that clock-names does not list (-ENOENT at probe)
  P3 clocks/clock-names count mismatch, or a specifier length != the provider's #clock-cells
  P4 interrupts specifier length != #interrupt-cells of the interrupt parent
  P5 fewer reg entries than the resource index the driver maps
  P6 pinctrl-names without the matching pinctrl-N (or without "default")
  P7 a reset requested with a NULL id but no resets property
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # python -I drops the script directory
import dts_lint  # noqa: E402

INT_MAX = 2**31 - 1


def strings(value):
    return [v[1][1:-1] for v in value if v[0] == "str"]


def groups(value):
    """Each <...> group as a list of tokens (phandle references kept, e.g. '&clk')."""
    return [v[1][1:-1].split() for v in value if v[0] == "cells"]


def walk(node):
    yield node
    for c in node.children:
        yield from walk(c)


def driver_facts(src):
    table = re.findall(r'\{\s*\.compatible\s*=\s*"([^"]+)"(?:\s*,\s*\.data\s*=\s*&?(\w+))?', src)
    clocks = re.findall(r'devm_clk_get\w*\(\s*\w+\s*,\s*"([^"]+)"\s*\)', src)
    reset_null = bool(re.search(r"reset_control_get\w*\(\s*\w+\s*,\s*NULL\s*\)", src))
    irqs = [int(i) for i in re.findall(r"platform_get_irq\(\s*\w+\s*,\s*(\d+)\s*\)", src)]
    regs = [int(i) for i in re.findall(r"devm_platform_ioremap_resource\(\s*\w+\s*,\s*(\d+)\s*\)", src)]
    return table, clocks, reset_null, irqs, regs


def best_match(compatibles, table):
    best, best_score = None, 0
    for entry in table:                                    # __of_match_node
        score = 0
        for index, cp in enumerate(compatibles):           # __of_device_is_compatible
            if cp.lower() == entry[0].lower():
                score = INT_MAX // 2 - (index << 2)
                break
        if score > best_score:
            best, best_score = entry, score
    return best


def main():
    dts, drv = sys.argv[1], sys.argv[2]
    src = open(dts, encoding="utf-8").read()
    errors = []
    root = dts_lint.parse(src, errors)
    labels = {}
    for lab, name in re.findall(r"(\w+):\s*([\w@,.\-]+)\s*\{", src):
        labels[lab] = next((n for n in walk(root) if n.name == name), None)
    table, clocks, reset_null, irqs, regs = driver_facts(open(drv, encoding="utf-8").read())
    vendors = {c.split(",")[0] for c, _ in table}
    out = []
    for node in walk(root):
        compat = strings(node.props.get("compatible", []))
        if not compat:
            continue
        match = best_match(compat, table)
        if match is None:
            if any(c.split(",")[0] in vendors and c not in ("simple-bus",) for c in compat) and node.parent is not None \
                    and node.parent.parent is not None:
                out.append(f"P1 {node.path()}: compatible {compat} matches no driver entry: never binds")
            continue
        status = strings(node.props.get("status", []))
        if status and status[0] not in ("okay", "ok"):
            continue
        print(f"   {node.path()}: binds as '{match[0]}' (data {match[1] or 'none'})")
        names = strings(node.props.get("clock-names", []))
        specs = groups(node.props.get("clocks", []))
        for c in clocks:
            if c not in names:
                out.append(f"P2 {node.path()}: driver requests clock '{c}', clock-names has {names}")
        if names and len(names) != len(specs):
            out.append(f"P3 {node.path()}: {len(specs)} clocks for {len(names)} clock-names")
        for spec in specs:
            prov = labels.get(spec[0].lstrip("&")) if spec and spec[0].startswith("&") else None
            want = int(dts_lint.cells(prov.props["#clock-cells"])[0], 0) if prov and "#clock-cells" in prov.props else None
            if want is not None and len(spec) - 1 != want:
                out.append(f"P3 {node.path()}: clock specifier {spec} has {len(spec) - 1} cells, provider wants {want}")
        parent_ref = groups(node.props.get("interrupt-parent", []))
        ip = labels.get(parent_ref[0][0].lstrip("&")) if parent_ref else None
        if ip is not None and node.props.get("interrupts"):
            want = int(dts_lint.cells(ip.props["#interrupt-cells"])[0], 0)
            got = len(dts_lint.cells(node.props["interrupts"]))
            if got % want:
                out.append(f"P4 {node.path()}: interrupts has {got} cells, {ip.name} has #interrupt-cells = {want}")
            elif irqs and max(irqs) >= got // want:
                out.append(f"P4 {node.path()}: driver uses interrupt {max(irqs)}, node has {got // want}")
        reg_cells = len(dts_lint.cells(node.props.get("reg", [])))
        if regs and reg_cells == 0:
            out.append(f"P5 {node.path()}: driver maps reg {max(regs)}, node has no reg")
        pn = strings(node.props.get("pinctrl-names", []))
        for i, state in enumerate(pn):
            if f"pinctrl-{i}" not in node.props:
                out.append(f"P6 {node.path()}: pinctrl-names[{i}] = '{state}' has no pinctrl-{i}")
        if pn and "default" not in pn:
            out.append(f"P6 {node.path()}: no 'default' pinctrl state: the core applies none before probe")
        if reset_null and "resets" not in node.props:
            out.append(f"P7 {node.path()}: driver requests its reset, node has no resets property")
    for e in errors + out:
        print("   ", e)
    print(f"{os.path.basename(dts)} x {os.path.basename(drv)}: {len(errors) + len(out)} finding(s)")
    sys.exit(1 if errors or out else 0)


if __name__ == "__main__":
    main()
```

```text
   /soc@0/fan@30660000: binds as 'acme,imx8mm-fan' (data imx8mm_variant)
acme-fan.dts x acme_fan.c: 0 finding(s)
exit=0
   /soc@0/fan@30660000: binds as 'acme,fan' (data generic_variant)
    P2 /soc@0/fan@30660000: driver requests clock 'ipg', clock-names has ['per']
    P3 /soc@0/fan@30660000: 2 clocks for 1 clock-names
    P4 /soc@0/fan@30660000: interrupts has 2 cells, interrupt-controller@38800000 has #interrupt-cells = 3
    P6 /soc@0/fan@30660000: pinctrl-names[1] = 'sleep' has no pinctrl-1
    P7 /soc@0/fan@30660000: driver requests its reset, node has no resets property
acme-fan-fragile.dts x acme_fan.c: 5 finding(s)
exit=1
```

The fragile node binds, so nothing at boot says "no driver". But it binds the generic variant, and its probe fails on the clock name before reaching any of the other three errors. Fix one, and the next appears on the next boot. The check reports all of them at once, before the board exists.

### 2.3 Bring-up commands

```bash
cat /sys/kernel/debug/devices_deferred                # who is waiting, and for what (dev_err_probe reasons)
ls /sys/bus/platform/drivers/acme-fan/                # bound devices
cat /sys/kernel/debug/pinctrl/*/pinmux-pins           # which function owns each pad now
cat /sys/kernel/debug/clk/clk_summary                 # enable/prepare counts, rates, parents
dtc -I fs -O dts /sys/firmware/devicetree/base        # the tree the kernel actually got (after U-Boot fixups)
```

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Mechanism | Detect | Fix |
|---|---|---|---|
| Device works until ~30 s into boot, then stops | `clk_disable_unused()` gated a clock no driver claimed (bootloader left it on) | `clk_summary` enable count 0; log "clk: Disabling unused clocks" | The consumer claims its clock; truly always-on clocks are `CLK_IS_CRITICAL` in the provider |
| Probe sometimes works, sometimes `-EINVAL` | Deferral turned into a hard error | `devices_deferred` empty, error in dmesg | Return the consumer API's error via `dev_err_probe()` |
| Peripheral talks garbage, no errors | No `default` pinctrl state: probe ran with the bootloader's pad mux | `pinmux-pins` shows another function | `pinctrl-names = "default"` + `pinctrl-0` (P6) |
| Interrupt storm or no interrupts | Wrong interrupt specifier (cells, type), or handler runs before hardware init | `/proc/interrupts`; `IRQ_NONE` warnings ("nobody cared") | P4; quiesce hardware before `request_irq`; `IRQF_SHARED` handlers return `IRQ_NONE` when not theirs |
| Driver binds the wrong variant | Node lists only the generic compatible | `dt_probe_check.py` "binds as" | Most specific compatible first; variants in `.data` |
| Out-of-tree driver stops compiling after a kernel upgrade | Removed or retyped API (`.remove` void, `devm_ioremap_nocache` gone) | `kapi_check.py` K1–K3 | Track upstream APIs per LTS; upstream the driver |
| No console at all after `bootm` | DTB address wrong, MMU/cache state wrong, or `earlycon` missing | JTAG: PC in `head.S`; `earlycon=` output | Follow booting.rst; `earlycon` and `keep_bootcon` on bring-up builds |

**Post-mortem method for "it worked in U-Boot, not in Linux":**
1. Dump the live tree (`dtc -I fs`) and diff it against the source.
2. Check `devices_deferred`, `clk_summary` and `pinmux-pins` for the node.
3. Bisect probe order with `initcall_debug`.
4. For no-console hangs, attach JTAG (CoreSight, 01.2): read PC and `ESR_EL1`, and walk the kernel log buffer from memory. pstore/ramoops (04.4) captures it across a reset.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · The 30-second death

**Initial Prompt:** "A new board's Ethernet works in U-Boot and for the first half minute of Linux boot, then the PHY stops responding. No errors. Diagnose."

**L5 Answer:** "Probably a PHY driver bug or a link issue. Swap the cable, then check the PHY registers."

**Why L5 Bricks Devices at Scale:**
- **It misses a clock problem with a timestamp.** `clk_disable_unused()` runs at `late_initcall_sync` and gates every clock nobody claimed. If the PHY's reference clock was enabled by U-Boot but not listed in the Linux DT for the consumer that needs it, Linux turns it off mid-boot.
- **A "fix" of `clk_ignore_unused` on the command line** ships a product with every unused clock running: power, EMI, and a masked bug.

**L7 Principal Defense:**
- **Correlate the stop with the "Disabling unused clocks" log line,** then read `clk_summary`.
- **Put the reference clock in the consumer's DT node** (MAC or PHY `clocks`/`clock-names`) so its driver claims it.
- **If it's genuinely always-on**, mark it `CLK_IS_CRITICAL` in the clock provider driver.
- **Ban `clk_ignore_unused`** from product command lines (a lint on the U-Boot environment, 03.1).

### Chain 2 · Probe order roulette

**Initial Prompt:** "About 1 in 50 boots, the touch controller doesn't come up. The log shows 'failed to get regulator: -517'... then nothing. Explain."

**L5 Answer:** "-517 is a weird error. Add a delay before the driver loads, or make it a module and load it later."

**Why L5 Bricks Devices at Scale:**
- **-517 is `-EPROBE_DEFER`.** The supplier wasn't ready yet. The driver logged it as an error and returned something else (or swallowed it), so the core never retried.
- **Delays and load-order hacks** change the odds without removing the bug, and the next kernel's different probe order brings it back at 1 in 5.

**L7 Principal Defense:**
- **Propagate deferral:** `return dev_err_probe(dev, PTR_ERR(reg), "vdd\n");`.
- **Let `fw_devlink` order suppliers** from DT phandles.
- **Verify** with `devices_deferred` and by forcing deferral in testing (`deferred_probe_timeout`, randomized probe order in CI).
- **Make it a review rule:** every resource getter's error goes through `dev_err_probe`.

### Chain 3 · One driver, three SoCs

**Initial Prompt:** "The same IP block appears on three SoC generations with small differences. How should the driver handle them?"

**L5 Answer:** "Check which SoC we're on with `of_machine_is_compatible()` and branch."

**Why L5 Bricks Devices at Scale:**
- **It ties device behavior to the board's root compatible.** A fourth SoC with the same IP, a board vendor's custom root compatible, or a DT overlay silently takes the wrong branch.
- **Variants spread as `if` chains** through the driver, untestable in isolation.

**L7 Principal Defense:**
- **Per-IP compatibles, most specific first in the node** (`"acme,imx8mm-fan", "acme,fan"`), with variant data in `of_device_id.data` read by `device_get_match_data()`.
- **Know the kernel's scoring:** node order decides, case-insensitive, ties to the earlier table entry.
- **Check every board DT against the driver** (`dt_probe_check.py` "binds as …") in CI.
- **Upstream the binding** with a dt-schema YAML so `make dtbs_check` enforces it.

### Chain 4 · Pins in the wrong mode

**Initial Prompt:** "An SPI flash reads all 0xFF on Linux, but U-Boot reads it fine. Same pins, same chip."

**L5 Answer:** "The SPI driver must have a timing bug. Lower the clock rate."

**Why L5 Bricks Devices at Scale:**
- **U-Boot muxed those pads for SPI. Linux re-applies pin states from the DT.** If the node lacks a `default` state, `pinctrl_bind_pins()` silently applies nothing. If a different node claims the same pads, the last applied state wins.
- **Lowering the clock does nothing** for a pad that isn't connected to the SPI controller.

**L7 Principal Defense:**
- **Read `pinmux-pins`:** which function owns each pad.
- **Ensure the SPI node has `pinctrl-names = "default"`** with its group, and that no other enabled node claims the pads (the pin controller rejects double claims; read its log).
- **Validate** with `dt_probe_check.py` (P6).
- **Treat pinmux as part of the board's DT review,** with the schematic open.

### Chain 5 · The vendor driver forward-port

**Initial Prompt:** "We're moving from the vendor's 5.15 kernel to 6.18 LTS. The vendor's out-of-tree drivers 'mostly compile' after some sed. Ship?"

**L5 Answer:** "If they compile and the board boots, yes. Fix runtime problems as they come up."

**Why L5 Bricks Devices at Scale:**
- **"Compiles after sed" is how `.remove_new` and `int remove()` survive** into a kernel where the callback is `void`.
- **Removed APIs get replaced by lookalikes** with different semantics.
- **Subtle breakage compiles:** locking or DMA API changes, and new requirements such as `IRQF_ONESHOT` for threaded handlers without a primary handler. They show up as field failures.

**L7 Principal Defense:**
- **Gate first** (`kapi_check.py` K1–K3 against the target headers), then compile against the configured tree with `W=1`, run sparse and smatch, and review each API change against upstream's own conversion commits.
- **Run the driver's test suite on hardware**, including unbind/rebind and probe-deferral injection.
- **The strategic fix is upstreaming:** an upstream driver is converted by the people changing the API.

### Chain 6 · Device tree as an interface

**Initial Prompt:** "Who owns the device tree on a product, and how is it validated?"

**L5 Answer:** "The BSP team writes it. If the board boots, it's right."

**Why L5 Bricks Devices at Scale:**
- **"Boots" exercises the drivers that happen to probe on this board revision.** Errors in resources only some paths use (sleep pin states, second interrupt, optional clocks) wait for the field.
- **Without bindings,** the DT and driver drift independently across teams.

**L7 Principal Defense:**
- **The DT is an ABI between hardware and software,** and gets validated like one:
  - dt-schema bindings (`make dtbs_check`);
  - the structural lint;
  - a driver-aware probe check;
  - review against the schematic.
- **One owner per node** (BSP for SoC and board, product team for overlays).
- **Every board revision gets its own DTS**, never runtime patching.
- **The live tree is captured in the SBOM** and the field debug bundle.

---

## 5. Invariants Checklist

- [ ] Drivers: variants in `of_device_id.data`; resources via `devm_*`; every getter's error through `dev_err_probe`; hardware quiesced before `request_irq`; shared handlers return `IRQ_NONE` when not theirs.
- [ ] `kapi_check.py` clean against the target kernel's headers; then a real build with `W=1`, sparse/smatch.
- [ ] DT: most specific compatible first; `clock-names` match driver requests; specifier lengths match provider `#…-cells`; `default` pinctrl state present; `resets` where requested (`dt_probe_check.py` clean).
- [ ] No `clk_ignore_unused` on product command lines; always-on clocks `CLK_IS_CRITICAL` in the provider.
- [ ] Bring-up builds: `earlycon`, `initcall_debug` available; product builds capture the live DT in the debug bundle.

## 6. References

- Linux v7.2: `Documentation/arch/arm64/booting.rst`, `drivers/of/base.c`, `drivers/base/pinctrl.c`, `drivers/clk/clk.c`, `include/linux/clk-provider.h`, `include/linux/platform_device.h`. <https://github.com/torvalds/linux/tree/v7.2>
- Devicetree specification. <https://www.devicetree.org/specifications/>
- Kernel documentation: driver model, deferred probe (`Documentation/driver-api/driver-model/`), CCF (`Documentation/driver-api/clk.rst`). <https://docs.kernel.org/>
- In this KB: [01.4 dts_lint and FIT](../01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE/04-uboot-verified-boot-fit-images-dm-verity-fscrypt-and-tpm2-measured-boot.md) · [02.2 kernel configuration](../02-Yocto-Project-BitBake-and-Cross-Toolchain-Internals/02-bsp-layer-engineering-machine-distro-overrides-and-kernel-devtool.md) · [04.3 interrupts](03-interrupts-gicv3-top-bottom-halves-threaded-irqs-workqueues-and-preempt-rt.md) · [04.4 pstore](04-high-speed-peripherals-pcie-nvme-mipi-i2c-spi-regmap-and-pstore-ramoops.md)
