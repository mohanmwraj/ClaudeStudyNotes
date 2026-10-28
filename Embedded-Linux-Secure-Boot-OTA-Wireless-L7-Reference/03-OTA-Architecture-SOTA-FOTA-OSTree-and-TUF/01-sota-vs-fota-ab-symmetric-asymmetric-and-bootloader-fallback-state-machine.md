# 03.1 · SOTA vs FOTA, Symmetric and Asymmetric A/B, and the Bootloader Fallback State Machine

> **Folder 03 · File 1 of 4.** An update system is judged on one property: **after any single failure, at any instant, the device still boots a known-good system without human help.** Failures include power loss mid-write, a bad image, a hang, and a crash in the new userspace.
>
> Everything else depends on getting that right: delta efficiency, campaign management, the backend. This file builds the A/B state machine from the code that implements it:
> - U-Boot's boot counter;
> - U-Boot's redundant environment;
> - libubootenv's `fw_setenv`;
> - systemd's boot-complete target.
>
> It then **proves** the property by injecting a power cut before every single sector write of an update and its subsequent boots. It does that for the hardened policy and for each weakness removed one at a time.
>
> **Pinned.**
> - U-Boot **v2026.10**: `drivers/bootcount/bootcount_env.c`, `include/bootcount.h`, `common/autoboot.c`, `env/common.c`, `env/mmc.c`, `env/Kconfig`.
> - libubootenv **0.3.7** (`1e3511ed`, oe-core 6.1's `SRCREV`).
> - systemd **261** units (`boot-complete.target`, `systemd-boot-check-no-failures.service`, `systemd-bless-boot.service`).
>
> **Verification.**
> - `ab_model.c` mirrors the listed functions line by line, and is compiled warning-free for the host and for AArch64.
> - `ab_test.c` runs 4,152 fault-injected scenarios across nine policy variants.
> - `ab_env_check.py` derives the policy from the actual `.env` and Kconfig fragments, so the files that ship are tied to the model that was proven.
> - The U-Boot fragment's symbols are resolved against v2026.10 Kconfig.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 SOTA and FOTA are different problems

| | **SOTA** (software over the air) | **FOTA** (firmware over the air) |
|---|---|---|
| Targets | Linux kernel, rootfs, applications, containers | Bootloaders, MCU and modem firmware, sensor hubs, secondary ECUs, FPGA bitstreams |
| Storage | Gigabytes; room for two slots or an object store | Often a single flash bank; sometimes dual-bank MCUs |
| Who verifies | U-Boot / FIT signature, dm-verity (01.4), the update client | The component's own ROM or bootloader, or the host that flashes it |
| Rollback | A/B fallback or OSTree deployment (03.2) | Dual-bank swap, a ROM-resident fallback, or none |
| Power-loss behavior | Must be atomic by design (this file) | Often only "the ROM can always be re-entered": a recovery path, not atomicity |
| Orchestration | Per device | Often a *system* of components that must agree on versions (03.4) |

A product typically has both. The SOTA update carries the FOTA payloads and drives them, with the system update's commit gated on every component's commit (03.4). This file is the SOTA core.

### 1.2 Slot strategies

| Strategy | Layout | Update time | Downtime | Rollback | Cost |
|---|---|---|---|---|---|
| **Symmetric A/B** | Two full systems; either may be active (02.2 layout) | Background | One reboot | Instant (other slot) | 2× system storage |
| **Asymmetric** (main + recovery) | Full main system plus a small recovery system that performs updates | Reboot into recovery, then write | Minutes | Re-flash from recovery | 1× + small recovery |
| **OSTree / deployments** (03.2) | One filesystem, several hardlinked deployments | Background | One reboot | Previous deployment | 1× + changed files |
| **In place** | One copy, overwritten | Down during write | Long | None | 1× |

In-place updates are only acceptable where a ROM-resident recovery path exists and the device can tolerate being offline until a technician or the backend re-flashes it. That is FOTA thinking, never SOTA.

### 1.3 The state machine

```text
                 updater (Linux, running slot X)                     U-Boot (every boot)                    Linux (new slot Y)
 COMMITTED(X) ──write Y, read back, verify──► Y written
              ──fw_setenv -s boot_slot=Y upgrade_available=1 bootcount=0──► PENDING(Y, n=0)
                                                               bootcount_inc: n+1, saveenv
                                                               n ≤ bootlimit → bootcmd → verify FIT(Y)
                                                                   FIT bad → altbootcmd ─────────────┐
                                                                   FIT ok → kernel ─► health check ──┤
                                                                                       ok: fw_setenv -s upgrade_available=0 bootcount=0
                                                                                           ──► COMMITTED(Y), rollback counter may advance
                                                                                       fail / panic / hang+watchdog: reset ──► next boot
                                                               n > bootlimit → altbootcmd: boot_slot=X, upgrade_available=0,
                                                                                           bootcount=0, saveenv ──► COMMITTED(X)
```

**Ownership of each transition:**
- **The updater** writes the inactive slot and switches. It runs on the healthy current slot.
- **U-Boot** counts attempts and falls back. It is the only component guaranteed to run after a crash.
- **systemd** decides when a boot is healthy.
- **A single atomic environment write** commits.

No transition depends on the component that might be broken.

### 1.4 U-Boot's mechanism, as implemented in v2026.10

**Boot counting** (`include/bootcount.h`, `common/autoboot.c`, `drivers/bootcount/bootcount_env.c`):
- **When it counts.** `bootdelay_process()` calls `bootcount_inc()` on every boot.
- **Where it counts.** With `CONFIG_BOOTCOUNT_ENV`, `bootcount_load()` returns the stored `bootcount` *only if* `upgrade_available` is non-zero. `bootcount_store()` saves the environment *only if* `upgrade_available` is non-zero. An ordinary boot of a committed system therefore costs **no** flash write.
- **When it falls back.** `bootcount_error()` is `bootlimit && bootcount > bootlimit`. If true, U-Boot runs `altbootcmd` instead of `bootcmd`. With `bootlimit=3`, the new slot gets three attempts and the fourth boot falls back.
- **Where the limit comes from.** `CONFIG_BOOTCOUNT_BOOTLIMIT=n` (if > 0) writes `bootlimit=n` into the default environment (`include/env_default.h`).

**The redundant environment** (`env/common.c` `env_check_redund()`, `env/mmc.c` `env_mmc_save()`):

```text
 env_t (CONFIG_ENV_REDUNDANT):  | crc32 (4) | flags (1) | data: "name=value\0...\0\0" (CONFIG_ENV_SIZE - 5) |
 load:  CRC of each copy → one valid: use it; both valid: higher flags wins, except 255 vs 0 (wrap) → the 0;
        equal → copy 0; neither valid → "bad CRC", compiled-in default environment
 save:  env_export() writes the whole environment, sorted by name, into the copy that is NOT current,
        with flags = ++serial; the current copy is never touched
```

A power cut during `saveenv` therefore leaves the previous copy intact and valid. With a **single** copy, the same cut leaves nothing valid, and U-Boot boots from its compiled-in default environment, whatever slot that names.

**What storage is allowed to say** (`env/Kconfig`):
- `CONFIG_ENV_WRITEABLE_LIST` (which selects `ENV_APPEND`) means only variables flagged `w` in `CONFIG_ENV_FLAGS_LIST_STATIC` are imported from storage.
- With `"boot_slot:sw,upgrade_available:dw,bootcount:dw"`, the scripts, `bootlimit` and `bootargs` always come from the signed U-Boot binary.
- An attacker with raw eMMC access can choose between two signed slots. They can't change how they boot.

**The watchdog.** `CONFIG_WATCHDOG_AUTOSTART` starts the hardware watchdog in U-Boot. The kernel takes it over (`CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED`, 02.2) and userspace pets it. A hang anywhere before mark-good becomes a reset, and therefore a counted attempt.

### 1.5 The Linux side

- **libubootenv `fw_setenv -s <file>`** (`src/fw_printenv.c`, `libuboot_load_file()`) reads `name=value` lines. It applies them all in memory and writes **one** image to the non-current copy with the serial incremented, exactly as U-Boot does. Two variables, one write, atomic.
- **`fw_env.config`.** One line per copy: `device offset size [sector-size [sectors]]`. Two lines mean a redundant environment.
- **systemd 261 boot assessment:**
  - `boot-complete.target` (`Requires=sysinit.target`, `After=sysinit.target`) is the synchronization point.
  - `systemd-boot-check-no-failures.service` has `After=default.target graphical.target multi-user.target` and `Before=boot-complete.target`. With `[Install] RequiredBy=boot-complete.target`, a failed unit anywhere blocks the target.
  - The pattern is `systemd-bless-boot.service`: `DefaultDependencies=no`, `Requires=boot-complete.target`, `After=local-fs.target boot-complete.target`.
  - Our mark-good unit copies that pattern, and our health check is `RequiredBy=boot-complete.target`.
- **Anti-rollback** (01.1, 01.2) advances only in mark-good. The new version has proven that it boots, and the old one stays bootable until then.

---

## 2. Production Code & Configuration Blueprints

### 2.1 The proof: every power cut, every policy

The model, mirroring the U-Boot and libubootenv functions named in §1.4–1.5:

```c
/* ab_model.h - A/B boot over a redundant U-Boot environment, with sector-level power-loss injection */
#ifndef AB_MODEL_H
#define AB_MODEL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SECTOR       512u
#define ENV_SECTORS  8u                          /* one environment copy = CONFIG_ENV_SIZE (4 KiB)   */
#define ENV_BYTES    (SECTOR * ENV_SECTORS)
#define IMG_SECTORS  8u                          /* one boot slot: header sector + payload           */

enum quality { Q_GOOD, Q_BAD_KERNEL, Q_BAD_USERSPACE, Q_HANG };

/* What a run of the boot loop ended in. */
enum outcome { O_NEW_COMMITTED, O_OLD_RUNNING, O_STUCK, O_LOOP };

struct ab_policy {
	const char *name;
	bool redundant_env;            /* CONFIG_ENV_REDUNDANT: two copies, CRC + serial flags         */
	unsigned bootlimit;            /* default-env bootlimit; 0 disables altbootcmd (bootcount.h)   */
	bool write_then_switch;        /* updater writes and read-back-verifies before setting slot    */
	bool fallback_on_bad_image;    /* bootcmd runs altbootcmd if the slot's image fails to verify  */
	bool commit_after_health;      /* mark good only after the health check (boot-complete.target) */
	bool watchdog;                 /* hardware watchdog armed from U-Boot through userspace        */
};

struct device {
	uint8_t env[2][ENV_BYTES];
	uint8_t slot[2][IMG_SECTORS * SECTOR];
	long writes_left;              /* sector writes until power is cut; < 0 = never                */
	long writes_done;
	bool power_lost;
};

void ab_factory(struct device *d, int good_slot, const struct ab_policy *p);
bool ab_update(struct device *d, enum quality q, const struct ab_policy *p);
enum outcome ab_boot_loop(struct device *d, const struct ab_policy *p, int max_boots);
uint32_t ab_crc32(const uint8_t *buf, size_t len);

#endif
```

```c
/* ab_model.c - U-Boot's bootcount/altbootcmd flow, its redundant environment and fw_setenv, modelled */
/*
 * Mirrors, from U-Boot v2026.10 and libubootenv 0.3.7:
 *   env/common.c env_check_redund()      which copy is valid: CRC first, then the serial in env_t.flags
 *                                        (255 -> 0 wraps), equal serials -> copy 0
 *   env/mmc.c env_mmc_save()             write the copy that is NOT current, flags = ++serial
 *   drivers/bootcount/bootcount_env.c    bootcount is loaded and stored only while upgrade_available != 0
 *   include/bootcount.h, common/autoboot.c
 *                                        every boot: bootcount_inc(); bootcount > bootlimit -> altbootcmd
 *   libubootenv fw_setenv -s <file>      all variables in ONE write of the non-current copy (atomic)
 * The FIT signature check of 01.4 is stood in for by a CRC over the slot payload: a torn or corrupted
 * image fails it, a complete one passes.
 */
#include "ab_model.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- CRC-32 (IEEE 802.3, reflected): the crc32() U-Boot and zlib use ---- */
uint32_t ab_crc32(const uint8_t *buf, size_t len)
{
	uint32_t crc = 0xFFFFFFFFu;

	for (size_t i = 0; i < len; i++) {
		crc ^= buf[i];
		for (int k = 0; k < 8; k++)
			crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
	}
	return ~crc;
}

/* ---- storage: sector writes; power fails between two sectors when the budget runs out ---- */
static bool disk_write(struct device *d, uint8_t *dst, const uint8_t *src, size_t len)
{
	for (size_t off = 0; off < len; off += SECTOR) {
		if (d->writes_left == 0) {
			d->power_lost = true;
			d->writes_left = -1;            /* one cut per scenario: power returns for the reboot */
			return false;
		}
		memcpy(dst + off, src + off, SECTOR);
		d->writes_done++;
		if (d->writes_left > 0)
			d->writes_left--;
	}
	return true;
}

/* ---- the environment: only the three variables ENV_WRITEABLE_LIST lets storage provide ---- */
struct uenv {
	char slot;                       /* boot_slot: 'a' or 'b'                                        */
	unsigned long upgrade_available;
	unsigned long bootcount;
	int current;                     /* copy the values came from; -1 = compiled-in default env      */
	uint8_t serial;                  /* env_flags                                                    */
};

/* Stand-in for the default scripts' text (about 700 bytes each in a real A/B .env). */
#define SCRIPT_LEN 700
static char script_text[SCRIPT_LEN + 1];

static void init_script_text(void)
{
	static const char run[] = "run boot_try_slot; ";

	for (size_t i = 0; i < SCRIPT_LEN; i++)
		script_text[i] = run[i % (sizeof run - 1)];
}

static size_t hdr(const struct ab_policy *p)
{
	return p->redundant_env ? 5u : 4u;   /* ENV_HEADER_SIZE: crc (+ flags with ENV_REDUNDANT)        */
}

static bool copy_valid(const uint8_t *c, const struct ab_policy *p)
{
	uint32_t crc;

	memcpy(&crc, c, sizeof crc);
	return ab_crc32(c + hdr(p), ENV_BYTES - hdr(p)) == crc;
}

static unsigned long get_ulong(const char *data, const char *key, unsigned long dflt)
{
	size_t kl = strlen(key);

	for (const char *s = data; *s; s += strlen(s) + 1)
		if (!strncmp(s, key, kl) && s[kl] == '=')
			return strtoul(s + kl + 1, NULL, 10);
	return dflt;
}

static void env_default(struct uenv *e)
{
	e->slot = 'a';                   /* the board's .env: boot_slot=a                                */
	e->upgrade_available = 0;
	e->bootcount = 0;
	e->current = -1;
	e->serial = 0;
}

static void env_load(const struct device *d, const struct ab_policy *p, struct uenv *e)
{
	bool ok0 = copy_valid(d->env[0], p);
	bool ok1 = p->redundant_env && copy_valid(d->env[1], p);
	int cur;

	if (!ok0 && !ok1) {              /* "*** Warning - bad CRC, using default environment"           */
		env_default(e);
		return;
	}
	if (ok0 && !ok1) {
		cur = 0;
	} else if (!ok0) {
		cur = 1;
	} else {
		uint8_t f0 = d->env[0][4], f1 = d->env[1][4];

		if (f0 == 255 && f1 == 0)
			cur = 1;
		else if (f1 == 255 && f0 == 0)
			cur = 0;
		else
			cur = f1 > f0 ? 1 : 0;
	}
	const char *data = (const char *)d->env[cur] + hdr(p);
	char slot = 'a';

	for (const char *s = data; *s; s += strlen(s) + 1)
		if (!strncmp(s, "boot_slot=", 10))
			slot = s[10];
	e->slot = slot == 'b' ? 'b' : 'a';   /* bootcmd accepts only "a" or "b"                          */
	e->upgrade_available = get_ulong(data, "upgrade_available", 0);
	e->bootcount = get_ulong(data, "bootcount", 0);
	e->current = cur;
	e->serial = p->redundant_env ? d->env[cur][4] : 0;
}

/* saveenv (U-Boot) and fw_setenv -s (libubootenv): one image, written to the non-current copy.
 * env_export() writes the WHOLE environment sorted by name, so the scripts (altbootcmd, bootcmd)
 * come first and bootcount/upgrade_available land sectors after the CRC: a torn write is visible. */
static bool env_save(struct device *d, const struct ab_policy *p, struct uenv *e)
{
	uint8_t img[ENV_BYTES];
	int copy = p->redundant_env ? (e->current == 0 ? 1 : 0) : 0;
	size_t h = hdr(p), off = h;
	char kv[6][SCRIPT_LEN + 16];

	memset(img, 0, sizeof img);                 /* "k=v\0k=v\0...\0\0", zero padded             */
	(void)snprintf(kv[0], sizeof kv[0], "altbootcmd=%s", script_text);
	(void)snprintf(kv[1], sizeof kv[1], "boot_slot=%c", e->slot);
	(void)snprintf(kv[2], sizeof kv[2], "bootcmd=%s", script_text);
	(void)snprintf(kv[3], sizeof kv[3], "bootcount=%lu", e->bootcount);
	(void)snprintf(kv[4], sizeof kv[4], "bootlimit=%u", p->bootlimit);
	(void)snprintf(kv[5], sizeof kv[5], "upgrade_available=%lu", e->upgrade_available);
	for (int i = 0; i < 6; i++) {
		size_t n = strlen(kv[i]) + 1;

		memcpy(img + off, kv[i], n);
		off += n;
	}
	if (p->redundant_env)
		img[4] = ++e->serial;
	uint32_t crc = ab_crc32(img + h, ENV_BYTES - h);

	memcpy(img, &crc, sizeof crc);
	if (!disk_write(d, d->env[copy], img, ENV_BYTES))
		return false;
	e->current = copy;
	return true;
}

/* ---- slot images: header sector (magic, quality, version, payload CRC) + payload ---- */
static void make_image(uint8_t *img, enum quality q, uint8_t version)
{
	memset(img, 0, IMG_SECTORS * SECTOR);
	for (size_t i = SECTOR; i < IMG_SECTORS * SECTOR; i++)
		img[i] = (uint8_t)(i * 31u + version);
	uint32_t crc = ab_crc32(img + SECTOR, (IMG_SECTORS - 1u) * SECTOR);

	memcpy(img, "ACMEFIT1", 8);
	img[8] = (uint8_t)q;
	img[9] = version;
	memcpy(img + 12, &crc, sizeof crc);
}

static bool image_verifies(const uint8_t *img)
{
	uint32_t crc;

	memcpy(&crc, img + 12, sizeof crc);
	return !memcmp(img, "ACMEFIT1", 8) && ab_crc32(img + SECTOR, (IMG_SECTORS - 1u) * SECTOR) == crc;
}

void ab_factory(struct device *d, int good_slot, const struct ab_policy *p)
{
	struct uenv e = { .slot = good_slot ? 'b' : 'a', .current = 1 };

	init_script_text();
	memset(d, 0, sizeof *d);
	d->writes_left = -1;
	make_image(d->slot[0], Q_GOOD, 1);          /* both slots provisioned at the factory            */
	make_image(d->slot[1], Q_GOOD, 1);
	(void)env_save(d, p, &e);
	if (p->redundant_env)
		(void)env_save(d, p, &e);
}

/* The update client, running on the healthy current slot. Returns false if power was lost. */
bool ab_update(struct device *d, enum quality q, const struct ab_policy *p)
{
	struct uenv e;
	uint8_t img[IMG_SECTORS * SECTOR];

	env_load(d, p, &e);
	int target = e.slot == 'a' ? 1 : 0;

	make_image(img, q, 2);
	if (p->write_then_switch) {
		if (!disk_write(d, d->slot[target], img, sizeof img))
			return false;
		if (!image_verifies(d->slot[target]))   /* read back before pointing the bootloader at it */
			return false;
	}
	e.slot = target ? 'b' : 'a';
	e.upgrade_available = 1;
	e.bootcount = 0;
	if (!env_save(d, p, &e))                    /* fw_setenv -s: three variables, one write          */
		return false;
	if (!p->write_then_switch && !disk_write(d, d->slot[target], img, sizeof img))
		return false;
	return true;
}

/* altbootcmd: take the other slot, end the trial, save, boot it. */
static int altbootcmd(struct device *d, const struct ab_policy *p, struct uenv *e)
{
	e->slot = e->slot == 'a' ? 'b' : 'a';
	e->upgrade_available = 0;
	e->bootcount = 0;
	if (!env_save(d, p, e))
		return -2;                              /* power lost: reboot                              */
	int s = e->slot == 'b';

	return image_verifies(d->slot[s]) ? s : -1; /* -1: neither slot boots -> recovery (stuck)      */
}

/* Linux on slot s. Returns 1 = running healthy (loop ends), 0 = reboot, -1 = hung forever. */
static int linux_runs(struct device *d, const struct ab_policy *p, int s)
{
	enum quality q = (enum quality)d->slot[s][8];
	struct uenv e;

	if (q == Q_BAD_KERNEL)
		return 0;                               /* panic, then reboot after CONFIG_PANIC_TIMEOUT     */
	if (q == Q_HANG)
		return p->watchdog ? 0 : -1;
	if (!p->commit_after_health) {              /* "mark good" from an early unit                    */
		env_load(d, p, &e);
		if (e.upgrade_available) {
			e.upgrade_available = 0;
			e.bootcount = 0;
			if (!env_save(d, p, &e))
				return 0;
		}
	}
	if (q == Q_BAD_USERSPACE)
		return 0;                               /* health check fails: the unit triggers a reboot    */
	env_load(d, p, &e);
	if (e.upgrade_available) {                  /* acme-mark-good.service after boot-complete.target */
		e.upgrade_available = 0;
		e.bootcount = 0;
		if (!env_save(d, p, &e))
			return 0;
	}
	return 1;
}

enum outcome ab_boot_loop(struct device *d, const struct ab_policy *p, int max_boots)
{
	for (int boot = 0; boot < max_boots; boot++) {
		struct uenv e;
		int s;

		d->power_lost = false;
		env_load(d, p, &e);
		/* bootcount_inc(): load returns 0 unless upgrade_available; store only if upgrade_available */
		unsigned long count = e.upgrade_available ? e.bootcount : 0;

		count++;
		if (e.upgrade_available) {
			e.bootcount = count;
			if (!env_save(d, p, &e))
				continue;
		}
		/* bootcount_error(): bootlimit && bootcount_load() > bootlimit -> altbootcmd */
		if (p->bootlimit && e.upgrade_available && e.bootcount > p->bootlimit) {
			s = altbootcmd(d, p, &e);
		} else {
			s = e.slot == 'b';
			if (!image_verifies(d->slot[s]))     /* bootm returned: the image did not verify        */
				s = p->fallback_on_bad_image ? altbootcmd(d, p, &e) : -1;
		}
		if (s == -2)
			continue;
		if (s == -1)
			return O_STUCK;
		int r = linux_runs(d, p, s);

		if (r < 0)
			return O_STUCK;
		if (r == 1)
			return d->slot[s][9] == 2 ? O_NEW_COMMITTED : O_OLD_RUNNING;
	}
	return O_LOOP;
}
```

The harness:
- Both slots are provisioned at the factory.
- An update of one of four qualities: good, bad kernel (panics), bad userspace (fails health), hangs.
- The harness counts the sector writes of a fault-free run, then cuts power before each of them, one cut per scenario.
- Every policy variant is run from both starting slots.

```c
/* ab_test.c - cut power before every sector write of an update and its boots, for each A/B policy */
#include "ab_model.h"

#include <stdio.h>
#include <string.h>

#define MAX_BOOTS 16

struct tally {
	unsigned runs, stuck, loop, no_update, bad_committed;
};

/* One scenario: factory image in both slots, booting from good_slot; an update of quality q; power
 * cut after `cut` sector writes (-1 = never). Returns the outcome and the sector writes performed. */
static enum outcome run(const struct ab_policy *p, int good_slot, enum quality q, long cut, long *writes)
{
	static struct device d;

	ab_factory(&d, good_slot, p);
	d.writes_done = 0;
	d.writes_left = cut;
	(void)ab_update(&d, q, p);              /* if power is lost here, the device just reboots       */
	enum outcome o = ab_boot_loop(&d, p, MAX_BOOTS);

	*writes = d.writes_done;
	return o;
}

static struct tally evaluate(const struct ab_policy *p)
{
	struct tally t = { 0 };

	for (int good_slot = 0; good_slot < 2; good_slot++) {
		for (int qi = Q_GOOD; qi <= Q_HANG; qi++) {
			enum quality q = (enum quality)qi;
			long total, w;

			(void)run(p, good_slot, q, -1, &total);
			for (long cut = -1; cut < total; cut++) {     /* no power loss, then before each write */
				enum outcome o = run(p, good_slot, q, cut, &w);

				t.runs++;
				t.stuck += o == O_STUCK;
				t.loop += o == O_LOOP;
				t.bad_committed += o == O_NEW_COMMITTED && q != Q_GOOD;
				t.no_update += cut < 0 && q == Q_GOOD && o != O_NEW_COMMITTED;
			}
		}
	}
	return t;
}

int main(void)
{
	static const uint8_t vec[] = "123456789";
	const struct ab_policy H = { "hardened", true, 3, true, true, true, true };
	struct ab_policy v[9];
	int n = 0, fails = 0;

	if (ab_crc32(vec, 9) != 0xCBF43926u) {      /* the standard CRC-32 check value                 */
		puts("CRC-32 check value mismatch");
		return 1;
	}
	v[n++] = H;
	v[n] = H; v[n].name = "single env copy";                  v[n++].redundant_env = false;
	v[n] = H; v[n].name = "bootlimit = 0";                    v[n++].bootlimit = 0;
	v[n] = H; v[n].name = "switch slot before writing";       v[n++].write_then_switch = false;
	v[n] = H; v[n].name = "no fallback on unverifiable image"; v[n++].fallback_on_bad_image = false;
	v[n] = H; v[n].name = "switch first + no fallback";
	v[n].write_then_switch = false;           v[n++].fallback_on_bad_image = false;
	v[n] = H; v[n].name = "mark good before health check";    v[n++].commit_after_health = false;
	v[n] = H; v[n].name = "no watchdog";                      v[n++].watchdog = false;
	v[n++] = (struct ab_policy){ "fragile (all six)", false, 0, false, false, false, false };

	/* expected: 0 = must be safe; 1 = must show at least one stuck/looping device */
	const int expect_unsafe[] = { 0, 1, 1, 0, 0, 1, 1, 1, 1 };

	printf("%-36s %5s %6s %5s %10s %13s\n", "policy", "runs", "stuck", "loop", "no-update", "bad-committed");
	for (int i = 0; i < n; i++) {
		struct tally t = evaluate(&v[i]);
		unsigned bad = t.stuck + t.loop + t.no_update + t.bad_committed;
		int ok = expect_unsafe[i] ? bad > 0 : bad == 0;

		fails += !ok;
		printf("%-36s %5u %6u %5u %10u %13u  %s\n", v[i].name, t.runs, t.stuck, t.loop, t.no_update,
		       t.bad_committed, !expect_unsafe[i] ? (ok ? "safe" : "UNEXPECTEDLY UNSAFE")
							: (ok ? "unsafe, as expected" : "UNEXPECTEDLY SAFE"));
	}
	printf("%s: %d failure(s)\n", fails ? "FAILED" : "ALL PASSED", fails);
	return fails ? 1 : 0;
}
```

```text
policy                                runs  stuck  loop  no-update bad-committed
hardened                               408      0     0          0             0  safe
single env copy                        408      0    36          0             0  unsafe, as expected
bootlimit = 0                          936      0   804          0             0  unsafe, as expected
switch slot before writing             408      0     0          0             0  safe
no fallback on unverifiable image      408      0     0          0             0  safe
switch first + no fallback             408     56     0          0             0  unsafe, as expected
mark good before health check          360      0    44          0             0  unsafe, as expected
no watchdog                            344     28     0          0             0  unsafe, as expected
fragile (all six)                      472     72   258          0             0  unsafe, as expected
ALL PASSED: 0 failure(s)
```

What the table proves:
- **Hardened: 408 scenarios, none stuck, none looping, every good update committed.**
- **Each single weakness that isn't covered by another defense fails on its own:**
  - a single environment copy: a torn save boots the default slot, which may be the new, bad one, forever;
  - `bootlimit = 0`;
  - marking good before the health check: the bad image is committed, then reboots forever;
  - no watchdog: a hang is permanent.
- **Two weaknesses are masked by each other's defense.** "Switch slot before writing" alone is safe because `bootcmd` falls back when the FIT doesn't verify. "No fallback" alone is safe because the slot is only switched after a verified write. Remove both, and 56 scenarios brick. **Defense in depth is measurable:** each layer is load-bearing exactly where the others are absent.

### 2.2 U-Boot configuration

#### The Fragile Way

```text
# uboot-ab-fragile.config - the A/B fragment from the first prototype board
CONFIG_ENV_IS_IN_MMC=y
CONFIG_SYS_MMC_ENV_DEV=2
CONFIG_ENV_SIZE=0x2000
CONFIG_ENV_OFFSET=0x400000
CONFIG_BOOTCOUNT_LIMIT=y
CONFIG_BOOTCOUNT_ENV=y
# CONFIG_WATCHDOG_AUTOSTART is not set
```

What's wrong with it:
- **One environment copy.**
- **No watchdog autostart.**
- **The device symbol was renamed** in this U-Boot (`SYS_MMC_ENV_DEV` → `ENV_MMC_DEVICE_INDEX`). `merge_config.sh` drops it silently, and the environment goes to the default device index instead of the eMMC.
- **The offset is 4 MiB**, which is exactly where `boot_a` starts in the 02.2 layout. Every `saveenv` overwrites the first 8 KiB of the kernel FIT.

#### The Silicon-Hardened Production Way

```text
# uboot-ab.config - A/B boot counting over a redundant eMMC environment (merge after uboot-secure.config, 01.4)
# --- Two copies in the gap between the boot container and boot_a (02.2 layout: 33 KiB..4 MiB), 512 KiB
#     apart so that they never share an eMMC erase group (check EXT_CSD HC_ERASE_GRP_SIZE for the part) ---
CONFIG_ENV_IS_IN_MMC=y
CONFIG_ENV_MMC_DEVICE_INDEX=2
CONFIG_ENV_SIZE=0x10000
CONFIG_ENV_OFFSET=0x300000
CONFIG_ENV_REDUNDANT=y
CONFIG_ENV_OFFSET_REDUND=0x380000
# --- The A/B scripts are compiled into this signed binary; storage may change only three variables ---
CONFIG_ENV_SOURCE_FILE="acme-ab"
CONFIG_ENV_WRITEABLE_LIST=y
CONFIG_ENV_FLAGS_LIST_STATIC="boot_slot:sw,upgrade_available:dw,bootcount:dw"
# --- Boot counting: three attempts of a new slot, then altbootcmd ---
CONFIG_BOOTCOUNT_LIMIT=y
CONFIG_BOOTCOUNT_ENV=y
CONFIG_BOOTCOUNT_BOOTLIMIT=3
CONFIG_CMD_PART=y
CONFIG_CMD_MMC=y
# --- The watchdog starts here and is never stopped: a hang anywhere until mark-good is a reset ---
CONFIG_WATCHDOG=y
CONFIG_WDT=y
CONFIG_IMX_WATCHDOG=y
CONFIG_WATCHDOG_AUTOSTART=y
CONFIG_WATCHDOG_TIMEOUT_MSECS=60000
```

Merge it after 01.4's `uboot-secure.config`, which already disables legacy images and the interactive prompt and sets `ENV_ACCESS_IGNORE_FORCE`. Symbol check against U-Boot v2026.10 (01.4's `kconfig_check.py`):

```text
uboot-ab.config: 19 symbols checked against 8577 defined in u-boot-2026.10, 0 error(s)
uboot-ab-fragile.config: 7 symbols checked against 8577 defined in u-boot-2026.10, 1 error(s)   (SYS_MMC_ENV_DEV)
```

**Where the copies live.** Copies in the eMMC user area 512 KiB apart avoid sharing an erase group on parts whose `HC_ERASE_GRP_SIZE` is ≤ 512 KiB (read it from EXT_CSD) ⚠.

U-Boot also supports one copy in each **boot hardware partition**: `CONFIG_ENV_MMC_EMMC_HW_PARTITION=1` with equal offsets makes `env_mmc_save()` write copy 0 to boot0 and copy 1 to boot1. That is physically the strongest separation, but check the Linux side first.

libubootenv 0.3.7 clears the kernel's `force_ro` lock only for device names literally of the form `/dev/mmcblk<d>boot<d>` (`fileprotect()`). A stable `/dev/disk/by-path/...-boot0` symlink is written without unlocking, the write fails, mark-good never commits, and every update rolls back after three boots. If you use boot partitions:
1. Pin the mmcblk numbering with a device-tree alias (`mmc2 = &usdhc3;`).
2. Use the `/dev/mmcblk2boot0` form.

### 2.3 The default environment: the scripts the device actually runs

#### The Fragile Way

```text
/* acme-ab-fragile.env - the prototype's A/B environment */
part=1
bootlimit=0
bootargs=console=ttymxc1,115200 root=/dev/mmcblk2p${part} rootwait
bootcmd=
	load mmc 2:${part} ${loadaddr} fitImage;
	bootm ${loadaddr}
altbootcmd=
	if test ${part} = 1; then setenv part 2; else setenv part 1; fi;
	saveenv;
	run bootcmd
```

#### The Silicon-Hardened Production Way

```text
/* acme-ab.env - default environment (board/acme/imx8mm/acme-ab.env): A/B selection with boot counting */
/*
 * Compiled into the signed U-Boot (CONFIG_ENV_SOURCE_FILE="acme-ab"). Storage can supply only
 * boot_slot, upgrade_available and bootcount (ENV_WRITEABLE_LIST, ENV_FLAGS_LIST_STATIC); bootlimit
 * comes from CONFIG_BOOTCOUNT_BOOTLIMIT. Each slot's FIT carries its own signed initramfs, which knows
 * its own rootfs and root hash (01.4): nothing here names a root device.
 */
boot_slot=a
mmcdev=2
fit_addr=0x48000000
console=ttymxc1,115200
boot_try_slot=
	part start mmc ${mmcdev} boot_${boot_slot} fit_blk;
	part size mmc ${mmcdev} boot_${boot_slot} fit_cnt;
	mmc dev ${mmcdev};
	mmc read ${fit_addr} ${fit_blk} ${fit_cnt};
	setenv bootargs console=${console} panic=5;
	bootm ${fit_addr}#conf-1
bootcmd=
	/* Only "a" or "b" is accepted from storage. */
	if test "${boot_slot}" != "b"; then setenv boot_slot a; fi;
	run boot_try_slot;
	/* bootm returned: this slot's FIT is missing, torn or not signed by our key. */
	echo "slot ${boot_slot} did not verify";
	run altbootcmd
altbootcmd=
	/* Reached from bootcmd, or by U-Boot itself once bootcount > bootlimit. */
	if test "${boot_slot}" = "a"; then setenv boot_slot b; else setenv boot_slot a; fi;
	setenv upgrade_available 0;
	setenv bootcount 0;
	saveenv;
	run boot_try_slot;
	echo "no slot verified";
	run boot_recovery
boot_recovery=
	/* Board-specific: boot the signed recovery FIT kept in the eMMC boot1 hardware partition. */
	mmc dev ${mmcdev} 2;
	mmc read ${fit_addr} 0 0x10000;
	bootm ${fit_addr}#conf-recovery
```

`ab_env_check.py` derives, from these files and the U-Boot fragments, the four bootloader-side fields of `struct ab_policy` that §2.1 proved. It also checks the structural rules:
- an `altbootcmd` that really ends the trial;
- a normalized `boot_slot`;
- no `root=` in the environment;
- environment copies inside the gap;
- `fw_env.config` agreeing with U-Boot.

```python
# ab_env_check.py - derive the A/B policy a U-Boot build really implements, from its .env and Kconfig fragments
"""Usage: python ab_env_check.py <board.env> <fragment.config> ... [--boot-budget 33K:3072K] [--first-partition 4096K]
                                [--fw-env fw_env.config]

Prints the policy fields ab_model.c proves safe or unsafe (redundant_env, bootlimit, fallback_on_bad_image,
watchdog), derived from the files that are actually built, and fails on:
  E1 boot counting not configured (CONFIG_BOOTCOUNT_LIMIT + CONFIG_BOOTCOUNT_ENV)
  E2 storage can change more than the A/B state: CONFIG_ENV_WRITEABLE_LIST off, or ENV_FLAGS_LIST_STATIC
     not exactly boot_slot, upgrade_available, bootcount with the 'w' flag
  E3 altbootcmd does not switch boot_slot, end the trial (upgrade_available 0, bootcount 0) and saveenv
  E4 bootcmd uses boot_slot without normalizing it to "a" or "b"
  E5 a root device in the environment: which rootfs a slot boots must be decided inside its signed FIT
  E6 an environment copy outside the gap between the boot container's budget and the first partition,
     or the two copies overlapping
  E7 bootlimit 0, no fallback when a slot does not verify, or no watchdog armed from the bootloader
  E8 (with --fw-env) libubootenv's fw_env.config not addressing exactly U-Boot's copies, or naming the
     disk by its enumeration-order name (/dev/mmcblkN) instead of a stable path
"""
import re
import sys

WRITABLE = {"boot_slot", "upgrade_available", "bootcount"}


def parse_env(text):
    """U-Boot text environment: 'var=' in column 1 starts a variable, indented lines continue it."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    env, name = {}, None
    for line in text.splitlines():
        m = re.match(r"^([A-Za-z_][\w.]*)=(.*)$", line)
        if m:
            name = m.group(1)
            env[name] = m.group(2).strip()
        elif name and line[:1].isspace() and line.strip():
            env[name] = (env[name] + " " + line.strip()).strip()
    return env


def parse_config(paths):
    cfg = {}
    for path in paths:
        for line in open(path, encoding="utf-8"):
            m = re.match(r"^CONFIG_(\w+)=(.*)$", line.strip())
            if m:
                cfg[m.group(1)] = m.group(2).strip('"')
            m = re.match(r"^# CONFIG_(\w+) is not set", line.strip())
            if m:
                cfg[m.group(1)] = "n"
    return cfg


def kib(s):
    m = re.match(r"^(\d+)([KM]?)$", s)
    return int(m.group(1)) * (1024 if m.group(2) == "M" else 1)


def main():
    args = sys.argv[1:]
    opts = {}
    for flag in ("--boot-budget", "--first-partition", "--fw-env"):
        if flag in args:
            i = args.index(flag)
            opts[flag] = args[i + 1]
            args = args[:i] + args[i + 2:]
    env = parse_env(open(args[0], encoding="utf-8").read())
    cfg = parse_config(args[1:])
    y = lambda k: cfg.get(k) == "y"
    out = []

    redundant = y("ENV_REDUNDANT") and "ENV_OFFSET_REDUND" in cfg
    bootlimit = int(cfg.get("BOOTCOUNT_BOOTLIMIT") or env.get("bootlimit", "0") or 0)
    bootcmd, alt = env.get("bootcmd", ""), env.get("altbootcmd", "")
    attempt = max(bootcmd.find("run boot_try_slot"), bootcmd.find("bootm"))
    fallback = attempt >= 0 and bootcmd.find("run altbootcmd", attempt) > attempt
    watchdog = y("WATCHDOG_AUTOSTART") and (y("WDT") or y("WATCHDOG"))

    if not (y("BOOTCOUNT_LIMIT") and y("BOOTCOUNT_ENV")):
        out.append("E1 CONFIG_BOOTCOUNT_LIMIT and CONFIG_BOOTCOUNT_ENV are both required")
    flags = {e.split(":")[0].strip(): (e.split(":")[1].strip() if ":" in e else "")
             for e in cfg.get("ENV_FLAGS_LIST_STATIC", "").split(",") if e.strip()}
    writable = {k for k, v in flags.items() if v.endswith("w")}
    if not y("ENV_WRITEABLE_LIST"):
        out.append("E2 CONFIG_ENV_WRITEABLE_LIST off: every variable, bootcmd and bootargs included, comes from storage")
    elif writable != WRITABLE:
        out.append(f"E2 writable variables {sorted(writable)}, expected exactly {sorted(WRITABLE)}")
    for needle in ("setenv boot_slot", "setenv upgrade_available 0", "setenv bootcount 0", "saveenv"):
        if needle not in alt:
            out.append(f"E3 altbootcmd lacks '{needle}'")
    if "${boot_slot}" in bootcmd + env.get("boot_try_slot", "") and "setenv boot_slot a" not in bootcmd:
        out.append("E4 bootcmd trusts boot_slot from storage without normalizing it")
    if "boot_slot" not in bootcmd + env.get("boot_try_slot", ""):
        out.append("E4 bootcmd does not select a slot from boot_slot at all")
    for name, value in env.items():
        if re.search(r"\broot=", value):
            out.append(f"E5 {name} names a root device: '{re.search(r'root=[^ ;]*', value).group(0)}'")
    if "--boot-budget" in opts and "--first-partition" in opts:
        lo = sum(kib(x) for x in opts["--boot-budget"].split(":"))
        hi = kib(opts["--first-partition"])
        size = int(cfg.get("ENV_SIZE", "0"), 0) // 1024
        copies = [int(cfg[k], 0) // 1024 for k in ("ENV_OFFSET", "ENV_OFFSET_REDUND") if k in cfg]
        for c in copies:
            if c < lo or c + size > hi:
                out.append(f"E6 environment copy at {c} KiB (+{size} KiB) is outside the gap {lo}..{hi} KiB")
        if len(copies) == 2 and abs(copies[0] - copies[1]) < size:
            out.append("E6 the two environment copies overlap")
    if "--fw-env" in opts:
        lines = [ln.split() for ln in open(opts["--fw-env"], encoding="utf-8")
                 if ln.strip() and not ln.startswith("#")]
        want = [(int(cfg[k], 0), int(cfg.get("ENV_SIZE", "0"), 0))
                for k in ("ENV_OFFSET", "ENV_OFFSET_REDUND") if k in cfg and (k == "ENV_OFFSET" or redundant)]
        have = [(int(f[1], 0), int(f[2], 16)) for f in lines]    # libubootenv: offset %lli, size %zx
        if have != want:
            out.append(f"E8 fw_env.config copies {[(hex(o), hex(s)) for o, s in have]} != U-Boot's "
                       f"{[(hex(o), hex(s)) for o, s in want]}")
        for f in lines:
            if re.match(r"^/dev/mmcblk\d+$", f[0]):
                out.append(f"E8 fw_env.config names {f[0]}: mmcblk numbers follow probe order, not hardware")
    if bootlimit == 0:
        out.append("E7 bootlimit 0: altbootcmd never runs, a failing slot is retried forever")
    if not fallback:
        out.append("E7 bootcmd stops when the slot's image does not verify: no fallback")
    if not watchdog:
        out.append("E7 no watchdog armed from the bootloader: a hang before mark-good is permanent")

    print(f"{args[0].replace(chr(92), '/').rsplit('/', 1)[-1]}:")
    print(f"   derived: redundant_env={int(redundant)} bootlimit={bootlimit} "
          f"fallback_on_bad_image={int(fallback)} watchdog={int(watchdog)}")
    for o in out:
        print("   ", o)
    print(f"   {len(out)} finding(s)")
    sys.exit(1 if out else 0)


if __name__ == "__main__":
    main()
```

```text
== hardened
acme-ab.env:
   derived: redundant_env=1 bootlimit=3 fallback_on_bad_image=1 watchdog=1
   0 finding(s)
exit=0
== fragile
acme-ab-fragile.env:
   derived: redundant_env=0 bootlimit=0 fallback_on_bad_image=0 watchdog=0
    E2 CONFIG_ENV_WRITEABLE_LIST off: every variable, bootcmd and bootargs included, comes from storage
    E3 altbootcmd lacks 'setenv boot_slot'
    E3 altbootcmd lacks 'setenv upgrade_available 0'
    E3 altbootcmd lacks 'setenv bootcount 0'
    E4 bootcmd does not select a slot from boot_slot at all
    E5 bootargs names a root device: 'root=/dev/mmcblk2p${part}'
    E6 environment copy at 4096 KiB (+8 KiB) is outside the gap 3041..4096 KiB
    E8 fw_env.config copies [('0x400000', '0x4000')] != U-Boot's [('0x400000', '0x2000')]
    E8 fw_env.config names /dev/mmcblk0: mmcblk numbers follow probe order, not hardware
    E7 bootlimit 0: altbootcmd never runs, a failing slot is retried forever
    E7 bootcmd stops when the slot's image does not verify: no fallback
    E7 no watchdog armed from the bootloader: a hang before mark-good is permanent
   12 finding(s)
exit=1
```

The hardened derivation, `redundant_env=1 bootlimit=3 fallback_on_bad_image=1 watchdog=1`, is exactly the hardened policy in `ab_test.c`. The update client's write-then-switch ordering (03.4) and the health-gated commit below supply the other two fields.

### 2.4 Linux: where the commit happens

#### The Fragile Way

```text
# fw_env-fragile.config - copied from the evaluation kit's image
/dev/mmcblk0	0x400000	0x4000
```

```sh
#!/bin/sh
# mark-good-fragile.sh - started from rc.local as soon as userspace is up
fw_setenv upgrade_available 0
fw_setenv bootcount 0
/usr/libexec/acme/rollback-counter commit
curl -sf https://updates.acme.example/health > /dev/null || reboot
```

What's wrong:
- **It commits before anything has been checked**, so the bad-userspace row of §2.1 applies.
- **It uses two separate environment writes.**
- **It advances anti-rollback before the new version has proven itself**, so the old slot can never boot again.
- **Health is a network probe.** During a backend outage every device reboots in a loop, and because it already committed, there's nothing to fall back to.
- **The disk is named by probe order**, and the environment copy is somewhere U-Boot doesn't read.

#### The Silicon-Hardened Production Way

```text
# fw_env.config - libubootenv: the two copies U-Boot uses (uboot-ab.config), on the eMMC addressed by its controller
/dev/disk/by-path/platform-30b60000.mmc	0x300000	0x10000
/dev/disk/by-path/platform-30b60000.mmc	0x380000	0x10000
```

```ini
# acme-health-check.service - the product's definition of "this boot works"; boot-complete.target requires it
[Unit]
Description=Acme post-boot health check
After=multi-user.target acme-telemetryd.service
Before=boot-complete.target
# A failed check reboots at once; U-Boot's bootcount then decides between another try and the old slot.
FailureAction=reboot

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/acme/health-check
TimeoutStartSec=120

[Install]
RequiredBy=boot-complete.target
```

```sh
#!/bin/sh
# health-check.sh - /usr/libexec/acme/health-check: checks what an update can break, and nothing it cannot
set -eu

fail() {
	echo "health-check: $*" > /dev/kmsg
	exit 1
}

# 1. The services this product exists for are running.
for unit in acme-telemetryd.service systemd-networkd.service; do
	systemctl is-active --quiet "$unit" || fail "$unit is not active"
done

# 2. Persistent state is mounted read-write: the device can keep its identity, logs and keys.
grep -qs ' /data ext4 rw' /proc/mounts || fail "/data is not mounted read-write"

# 3. The update client starts and accepts its trust root and configuration: without it, this slot could
#    never receive the next fix. Deliberately NOT a network test: a backend outage must not roll back a fleet.
/usr/bin/acme-update-client --self-test || fail "update client self-test failed"
```

```ini
# acme-mark-good.service - end the A/B trial only once boot-complete.target is reached (systemd 261 semantics)
[Unit]
Description=Mark the running A/B slot good
DefaultDependencies=no
Requires=boot-complete.target
After=local-fs.target boot-complete.target
Conflicts=shutdown.target
Before=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/acme/mark-good

[Install]
WantedBy=multi-user.target
```

```sh
#!/bin/sh
# mark-good.sh - /usr/libexec/acme/mark-good: end the A/B trial in ONE environment write (fw_setenv -s)
set -eu

# Not in a trial: nothing to commit, and no flash write on every ordinary boot.
[ "$(fw_printenv -n upgrade_available 2>/dev/null || echo 0)" = "1" ] || exit 0

script=$(mktemp)
trap 'rm -f "$script"' EXIT
printf 'upgrade_available=0\nbootcount=0\n' > "$script"
# libubootenv writes both variables into the inactive copy with the next serial: atomic across power loss.
fw_setenv -s "$script"

# Only now may anti-rollback move forward (01.1): this version has proven that it boots and works.
/usr/libexec/acme/rollback-counter commit
```

How the pieces fit:
- **The ordering chain.** `multi-user.target` → `acme-health-check.service` and `systemd-boot-check-no-failures.service` (enable it: `RequiredBy=boot-complete.target`) → `boot-complete.target` → `acme-mark-good.service`. If either check fails, the target isn't reached and mark-good never runs.
- **A failed check reboots** (`FailureAction=reboot`), which costs one of the three attempts.
- **The health check tests what an update can break**, and deliberately nothing outside the device.
- ⚠ `/dev/disk/by-path/platform-30b60000.mmc` assumes the eMMC is on the i.MX8M Mini's third uSDHC; confirm the path on the board.

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Mechanism | Evidence | Fix |
|---|---|---|---|
| Every update rolls back after exactly `bootlimit` boots | Mark-good never reaches U-Boot's copies: `fw_env.config` mismatch, `force_ro` not cleared, wrong device | `fw_printenv upgrade_available` still 1 after a healthy boot; libubootenv error in the journal | `ab_env_check.py --fw-env`; correct device naming (§2.2) |
| Device boots an old or unexpected slot after a power cut | Single environment copy torn, so the default environment selected its slot | U-Boot console: `*** Warning - bad CRC, using default environment` | `CONFIG_ENV_REDUNDANT` with both copies inside the reserved gap |
| Boot loop on a new image that never falls back | `bootlimit` 0 or unset; `upgrade_available` cleared before health; `altbootcmd` doesn't end the trial | `fw_printenv bootcount` grows, or stays 0 | §2.2, §2.3, §2.4; model rows 3 and 7 |
| Device frozen after an update, until power-cycled | No watchdog armed from U-Boot, or userspace stops petting it early | Serial console silent; no reset | `WATCHDOG_AUTOSTART`, kernel `WATCHDOG_HANDLE_BOOT_ENABLED`, `WATCHDOG_NOWAYOUT` |
| Kernel FIT corrupted on every save | Environment offset overlapping a partition | `bootm` fails after the first `saveenv` | E6: copies inside the gap; layout as an interface (02.2) |
| Fleet-wide rollback during a cloud outage | Health check depends on the backend | Rollback spike correlated with backend incidents | Health checks only device-local invariants (§2.4) |
| Anti-rollback blocks the fallback slot | Counter advanced at install or first boot | Old slot fails verification with a rollback error | Advance only in mark-good (01.1 commit-on-success) |

**Brick recovery.**
- **When neither slot verifies,** `altbootcmd` reaches `boot_recovery`: a signed recovery FIT in eMMC boot1. Beyond that is the SoC's serial-download mode (02.2 §3). Every step must stay inside the signature chain (01.4).
- **Post-mortem for a rollback in the field:**
  1. Capture `fw_printenv` (slot, `upgrade_available`, `bootcount`).
  2. Capture the U-Boot console log if a serial console is logged.
  3. Capture `journalctl -b -1` from the failed attempt; pstore/ramoops carries the panic or watchdog reason across the reset (Folder 04).
  4. Capture the health-check unit's output.
  5. Map them onto the state machine of §1.3: which transition failed, and which component owned it.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · "Is the update atomic?"

**Initial Prompt:** "Our A/B update writes the new image to the inactive slot and flips a flag in the U-Boot environment. Is it atomic with respect to power loss?"

**L5 Answer:** "Yes. The slot write doesn't touch the running system, and the flag flip is a single variable, so it's atomic."

**Why L5 Bricks Devices at Scale:** "A single variable" is not a single write.
- **`saveenv` rewrites the whole environment image**, several sectors, which can be torn.
- **With one copy, a torn write leaves no valid environment**, and U-Boot boots its compiled-in default. That may name the slot that was half-written.
- **The flag flip's atomicity depends on things the L5 never names:**
  - the redundant copy and its CRC and serial selection;
  - whether the write order is verify-then-switch;
  - whether the boot path falls back when the image doesn't verify.

**L7 Principal Defense:**
- **Atomicity is a property of the whole protocol, and it can be proven.**
  - Redundant environment: write the non-current copy, `flags = ++serial`, CRC-selected on load.
  - Write the image, read it back and verify it, then switch with one `fw_setenv -s`.
  - `bootcmd` falls back when the FIT doesn't verify.
- **Model it and cut power before every sector write** (§2.1: 408 scenarios, zero failures).
- **Show which layers are load-bearing** by removing them one at a time, and tie the shipped `.env` and Kconfig back to the model (`ab_env_check.py`).

### Chain 2 · When is "good" good?

**Initial Prompt:** "When should the device mark a new slot as good?"

**L5 Answer:** "As soon as the kernel boots and userspace starts. If it got that far, the image works."

**Why L5 Bricks Devices at Scale:**
- **Booting is the easy part.** The bad-userspace scenario (a service that crashes, a migration that fails, a config the new version can't read) gets committed under this policy, then reboots forever.
- **There's no fallback left:** `upgrade_available` was cleared before the failure (§2.1, "mark good before health check").
- **Anti-rollback advanced at the same moment** makes the old slot permanently unbootable.

**L7 Principal Defense:**
- **Mark good only after a product-defined health check passes**, through `boot-complete.target`:
  - our check `RequiredBy=boot-complete.target`;
  - `systemd-boot-check-no-failures.service` enabled;
  - mark-good `Requires=` and `After=boot-complete.target`.
- **Commit in one atomic write**, then advance anti-rollback.
- **The health check tests what the update can break:** core services, persistent state mounted read-write, and the update client's own ability to fetch the next fix.
- **It never tests the network or the backend.** Their outages must not trigger rollbacks.

### Chain 3 · The fleet-wide rollback

**Initial Prompt:** "During a two-hour cloud outage, 30% of the fleet that had just updated rolled back to the previous version. Diagnose and fix."

**L5 Answer:** "The update must have been buggy. Pause the rollout and investigate the new version."

**Why L5 Bricks Devices at Scale:**
- **The correlation is with the outage, not the version.** Devices that rebooted during the outage failed a health check that called the backend, burned their attempts, and fell back.
- **"Pausing the rollout" blocks a working release** and leaves 30% of the fleet on the old one.
- **It teaches the organization that the update system is unreliable,** when the real defect is the health check's design.

**L7 Principal Defense:**
- **Separate device health from service health.** The health check verifies only device-local invariants (§2.4), and connectivity problems are reported through telemetry instead.
- **Re-offer the release** to the devices that rolled back.
- **Add fleet-level guardrails:**
  - staged rollout with automatic pause on rollback-rate anomalies;
  - rollback telemetry tagged with *which* health criterion failed.
- **Review every criterion** for "could something outside this device make it fail?"

### Chain 4 · Who is allowed to write the environment?

**Initial Prompt:** "Security review: an attacker with physical access can write the eMMC. With A/B and signed FITs, what can they do through the U-Boot environment?"

**L5 Answer:** "Nothing serious. The FITs are signed, so they can't boot unsigned code."

**Why L5 Bricks Devices at Scale:** Without `CONFIG_ENV_WRITEABLE_LIST`, the environment on storage supplies every variable: `bootcmd`, `bootargs`, `altbootcmd`, `bootlimit`.
- **The attacker can** boot a signed kernel with `init=/bin/sh` or a different `root=`, mix slot A's kernel with slot B's rootfs, set `bootlimit=0`, or replace `bootcmd` entirely.
- **None of that requires breaking a signature.** It requires only that the policy be read from writable storage.

**L7 Principal Defense:**
- **The bootloader's policy belongs inside the signed binary:**
  - `ENV_WRITEABLE_LIST` with `ENV_FLAGS_LIST_STATIC="boot_slot:sw,upgrade_available:dw,bootcount:dw"`;
  - `ENV_ACCESS_IGNORE_FORCE`;
  - `bootcmd` normalizing `boot_slot` to `a` or `b`.
- **The slot-to-rootfs binding lives inside each slot's signed FIT** (the initramfs carries its root device and verity root hash, 01.4), never in `bootargs`.
- **The attacker's remaining power is choosing between two signed, verified slots** (and anti-rollback limits even that).

### Chain 5 · Symmetric A/B or recovery partition?

**Initial Prompt:** "Storage is tight: 4 GB eMMC, a 1.4 GB rootfs that will grow. A/B or asymmetric recovery?"

**L5 Answer:** "A/B is the industry standard. Use two 1.5 GB slots and figure out growth later."

**Why L5 Bricks Devices at Scale:**
- **"Later" is a repartition,** the one change an OTA can't make safely (02.2 Chain 5).
- **Two slots sized for today** mean the image that grows past 1.5 GB in year two can't be delivered.
- **The device is then frozen on an old release** with known CVEs, or requires a risky repartition campaign.

**L7 Principal Defense:**
- **Decide with numbers:** image growth rate over the support life, compressed and uncompressed, and the persistent data budget.
- **Options:**
  - Symmetric A/B with fixed slots at 2–3× today's image.
  - An **OSTree-style deployment model** (03.2), where only changed files cost space.
  - Asymmetric recovery, accepting minutes of downtime and a riskier recovery-update path.
- **Prototype the worst-case delta and full update** under the chosen layout.
- **Gate the layout** (02.2 `wks_check.py`).
- **Record the decision** as an architectural constraint that release engineering checks every release (image size budget in CI).

### Chain 6 · The bootloader itself

**Initial Prompt:** "A/B covers the kernel and rootfs. How do you update U-Boot and TF-A in the field?"

**L5 Answer:** "Include them in the rootfs update and write them to the boot area when the new slot first boots."

**Why L5 Bricks Devices at Scale:**
- **The boot container isn't slotted.** It sits at the BootROM's fixed offset (02.2), one copy, shared by both slots.
- **A torn write or bad bootloader there bricks the device at the first stage,** below the A/B fallback that is supposed to protect it.
- **"On first boot of the new slot" writes it before the new slot is proven.**

**L7 Principal Defense:**
- **Treat the boot chain as FOTA with its own redundancy.** Use the SoC's secondary boot image support or eMMC boot0/boot1 hardware partitions, switched with `BOOT_PARTITION_ENABLE` in EXT_CSD, where the ROM supports it ⚠ (SoC-specific).
- **Write the inactive copy and verify it.** Switch only after the new SoC-level image has booted once via a one-shot mechanism, and keep the old one.
- **Update the bootloader rarely, separately from rootfs releases,** and only after the new rootfs (which contains the new bootloader payload) has been marked good.
- **Version the bootloader's environment contract** (the three writable variables) so old and new bootloaders agree with the running userspace.

---

## 5. Invariants Checklist

- [ ] Redundant environment, both copies inside the reserved gap, in different erase groups; `fw_env.config` byte-identical in offsets and sizes (E6, E8).
- [ ] `ENV_WRITEABLE_LIST` with exactly `boot_slot`, `upgrade_available`, `bootcount` writable; scripts and `bootlimit` from the signed binary.
- [ ] `bootlimit` > 0 (here 3); `altbootcmd` switches slot, ends the trial and saves; `bootcmd` falls back when a FIT doesn't verify.
- [ ] Watchdog armed in U-Boot, inherited by the kernel, never stopped before mark-good.
- [ ] Updater: write, read back, verify, then one `fw_setenv -s` switch.
- [ ] Commit only after `boot-complete.target`, one atomic write; anti-rollback advances only then.
- [ ] Health checks are device-local; no backend dependency.
- [ ] Recovery path signed and tested (boot1 recovery FIT, BootROM download mode).
- [ ] Model (`ab_test.c`) and policy derivation (`ab_env_check.py`) run in CI on the files that ship.

## 6. References

- U-Boot v2026.10: `drivers/bootcount/`, `include/bootcount.h`, `common/autoboot.c`, `env/common.c`, `env/mmc.c`, `env/Kconfig`, `doc/usage/environment.rst`, `cmd/part.c`. <https://github.com/u-boot/u-boot/tree/v2026.10>
- libubootenv 0.3.7 (`src/uboot_env.c`, `src/fw_printenv.c`, `docs/fw_env_config.md`). <https://github.com/sbabic/libubootenv/tree/v0.3.7>
- systemd 261 units: `boot-complete.target`, `systemd-boot-check-no-failures.service`, `systemd-bless-boot.service`; `systemd.special(7)`. <https://github.com/systemd/systemd/tree/v261/units>
- Automatic boot assessment (systemd documentation). <https://systemd.io/AUTOMATIC_BOOT_ASSESSMENT/>
- In this KB: [01.1 anti-rollback commit-on-success](../01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE/01-bootrom-efuse-otp-puf-and-cryptographic-chain-of-trust.md) · [01.4 FIT signing and the secure U-Boot fragment](../01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE/04-uboot-verified-boot-fit-images-dm-verity-fscrypt-and-tpm2-measured-boot.md) · [02.2 storage layout](../02-Yocto-Project-BitBake-and-Cross-Toolchain-Internals/02-bsp-layer-engineering-machine-distro-overrides-and-kernel-devtool.md) · [03.2 OSTree](02-libostree-internals-content-addressed-object-store-hardlinks-and-boot-swap.md) · [03.4 update clients](04-delta-updates-casync-rauc-swupdate-mender-and-atomic-ecu-subnode-flashing.md)
