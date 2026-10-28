# 01.4 · U-Boot Verified Boot: FIT Images, dm-verity, fscrypt and TPM2 Measured Boot

> **Folder 01 · File 4 of 4.** Files 01.1–01.3 carried the chain of trust from mask ROM to U-Boot and OP-TEE. This file carries it the rest of the way, into the running system:
> - **U-Boot** verifies a signed FIT configuration (kernel, DTB, initramfs);
> - the initramfs activates **dm-verity**, so every block of the read-only root is checked against a Merkle root that the signature covered;
> - writable state is encrypted with **fscrypt**, under a key only this SoC's TEE can derive;
> - **TPM2 measured boot** records what actually ran, for sealing and remote attestation.
>
> Each link fails in a specific, well-known way: signing images instead of configurations; a root hash that comes from an unsigned place; a key sealed to the wrong PCRs; a defconfig line that names an option that doesn't exist. This file shows each one.
>
> **Verification.** Everything below is checked mechanically, short of booting:
> - **dm-verity:** the tree implementation reproduces all seven root-hash vectors in **cryptsetup's own test suite** (`tests/verity-compat-test`), and its read-path model detects tampering.
> - **FIT sources:** checked by a structural linter and by a signing-policy gate. Both are my own tools: `dtc` and `mkimage` could not be run here (see the README).
> - **U-Boot fragments:** every `CONFIG_` symbol was resolved against **U-Boot v2026.10**'s Kconfig.
> - **C:** compiled for aarch64 Linux against glibc, the kernel UAPI headers and optee_client 4.11.0.
> - **Shell scripts:** checked with `sh -n` and `bash --posix -n`.
> - **PCR model:** reproduces U-Boot v2026.10's measured-boot ordering, read from `boot/bootm.c`.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 The integrity chain after U-Boot

```text
 BL2 verified U-Boot (01.2) ─► U-Boot's control DTB contains the FIT public key, marked required = "conf"
        │
        ▼
 FIT image.itb ── configuration conf-1 signature covers: root node, conf node, kernel/fdt/ramdisk nodes + hashes
        │           (verify)                       │
        ▼                                          ▼  (measure, in parallel: PCR8 kernel, PCR9 initrd, PCR1 DTB + bootargs)
 kernel + DTB + initramfs ── initramfs carries the dm-verity root hash (so the FIT signature covers it)
        │
        ▼
 dm-verity /dev/mapper/vroot ── every data block checked on its first read into the page cache, up to the root hash
        │
        ▼
 read-only root (SquashFS/EROFS) ── /var on a writable FS with fscrypt v2: key = HMAC(device key in TEE, label)
        │
        ▼
 userspace ── TPM2: secrets sealed to PCR8/9; remote attestation quotes PCRs + event log
```

**Verified boot and measured boot are different tools, and products need both:**

| | Verified boot | Measured boot |
|---|---|---|
| Action | **Enforce**: refuse anything not signed | **Record**: hash everything that runs into PCRs and an event log |
| Fails | Closed (doesn't boot) | Open (boots, but the measurements differ) |
| Protects | Code that runs | Secrets (sealed to PCRs) and remote trust (attestation) |
| Weak spot | Anything not covered by a signature (environment, bootargs, writable data) | Anything not measured; and what is measured *after* it's used |

### 1.2 FIT: images, configurations and what a signature covers

A FIT is a flattened device tree:
- **`/images`** holds the payloads (kernel, fdt, ramdisk, loadables), each with `hash-N` subnodes;
- **`/configurations`** holds bootable combinations of them;
- **`signature-N`** subnodes hold signatures.

Two ways to sign:
- **Image signatures** (a `signature` node inside each image). Each image is individually valid, so **any combination of validly signed images is accepted**: a 2026 kernel with a 2024 DTB with a vulnerable initramfs. This is the **mix-and-match** problem the U-Boot documentation warns about.
- **Configuration signatures** (a `signature` node inside each configuration). The signature covers the FIT's root node, the configuration node, and every image node the configuration references, together with their hash subnodes. Image data is covered through those hashes. Only the exact combination that was signed verifies.

In U-Boot v2026.10 (`doc/usage/fit/signature.rst`), the verifier **does not trust the FIT's own `hashed-nodes` list**, which isn't itself signed. It rebuilds the node list from the configuration's references (kernel, fdt, ramdisk, loadables…, including dm-verity subnodes). Other details:
- `-r` at signing time marks the key **required** in U-Boot's control DTB;
- `required-mode` (`any` or `all`) controls multi-key policies;
- `CONFIG_FIT_FULL_CHECK` (default y) rejects malformed FITs before use;
- the legacy uImage format can't be signed, so `CONFIG_LEGACY_IMAGE_FORMAT` must be off or `bootm` has a bypass.

This code path has a history of parser bugs:
- **2021:** FIT handling bugs fixed in 2021.04-rc2: unit addresses in FIT node names (CVE-2021-27138) and mishandling of modified FITs (CVE-2021-27097).
- **July 2026:** Binarly disclosed six more: BRLY-2026-037 to 042, covering missing NULL checks, unchecked `hashed-strings` and data offset/size bounds, and unbounded recursion in `fdt_check_no_at`. The v2026.10 tree pinned here has the depth-limited `fdt_check_no_at()` and the `hashed-strings` length check. Confirm the full set against the advisory for any other version you ship.
- **The lesson:** keep U-Boot current, and keep the attack surface small (§2.2).

### 1.3 dm-verity: what is verified, and when

The tree (Linux v7.2 `drivers/md/dm-verity-target.c`, validated in §2.4):
- **Leaves** are hashes of data blocks.
- **Each hash block** holds 2^`hash_per_block_bits` digests: 128 for SHA-256 with 4 KiB blocks. In format 1, each digest is padded to a power of two, and hashing is H(salt ‖ block).
- **Levels** are added until one block covers everything.
- **On disk, the top level comes first.**
- **The root hash** is the hash of that single top block.

**When verification happens.** The kernel's own wording is "on first read into the page cache". A block is verified when it's read from the device, and the verified page then lives in the page cache. **Subsequent accesses served from the page cache are not re-verified** (with `check_at_most_once`, even re-reads from the device are skipped, which detects only offline tampering). The brief's "verified on every page fault" is therefore not quite right, and the difference matters for the threat model:
- dm-verity defends the **block device** against offline modification, and against online modification of the storage as it is re-read;
- it does **not** defend pages already in RAM: that's the kernel's job (read-only mappings, integrity of the running system).

**Corruption policy:** the default returns `-EIO` for the read. `restart_on_corruption` reboots (pair it with A/B fallback); `panic_on_corruption` panics; `ignore_corruption` only logs (never in production). Forward error correction (FEC) can repair a limited number of bad blocks.

**The root hash must come from a signed place.** That's the whole game:
- inside the **signed initramfs** (§2.4);
- in a **FIT dm-verity subnode** covered by the configuration signature (U-Boot v2026.10 `CONFIG_FIT_VERITY`). ⚠ This relies on a kernel FIT block driver (`/dev/fitN`) that isn't in mainline Linux v7.2;
- or **signed itself**, verified by the kernel against its trusted keyring (`root_hash_sig_key_desc`, `CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG`).

A root hash on an editable kernel command line verifies nothing.

### 1.4 fscrypt: encrypting what must be writable

dm-verity makes the root immutable. Writable state (`/var`, user data) needs confidentiality and per-device binding instead:
- **fscrypt v2 policies** (kernel docs, v7.2) derive per-file keys from a master key with **HKDF-SHA512**. Recommended mode pairs are **AES-256-XTS** (contents) with **AES-256-HCTR2** (filenames), or Adiantum on CPUs without AES acceleration. For v2 policies with AES-256 modes, the master key must be at least 32 bytes.
- **The master key must never be stored on disk.** In this design it's HMAC(device key, label), computed inside the OP-TEE vault TA (01.3): a function of this SoC's HUK.
- **Hardware-wrapped keys** (`FSCRYPT_ADD_KEY_FLAG_HW_WRAPPED`, with inline-encryption hardware) keep even the master key out of kernel memory in plaintext. Use them where the SoC's inline crypto engine supports it.
- **Alternatives:** dm-crypt with kernel **trusted keys** (sources: TPM, TEE, CAAM, DCP…). The kernel documentation's warning about CAAM deserves to be memorized: trust is rooted in the OTPMK **only when HAB is enabled and CAAM is in secure mode; otherwise, a common fixed test key is used.** An open i.MX part therefore protects nothing with CAAM blobs (01.1).

### 1.5 TPM2 measured boot in U-Boot

With `CONFIG_MEASURED_BOOT` (no EFI), U-Boot v2026.10 `boot/bootm.c` measures:

| PCR | What | Event type |
|---|---|---|
| 8 | Kernel image | `EV_COMPACT_HASH` "linux" |
| 9 | initrd | `EV_COMPACT_HASH` "initrd" |
| 1 | DTB (if `CONFIG_MEASURE_DEVICETREE`) | `EV_TABLE_OF_DEVICES` |
| 1 | `bootargs` environment string (with its NUL) | `EV_PLATFORM_CONFIG_FLAGS` |

`extend(PCR, data)` is PCR ← SHA-256(PCR ‖ SHA-256(data)). PCRs reset to zero, and nothing can set them.

**Ordering matters.** The bootm state machine runs FINDOTHER → **MEASURE** → LOADOS → RAMDISK → FDT → OS_PREP. So:
- **The DTB is measured as loaded**, before OS_PREP fixups such as `kaslr-seed` injection or FIT-verity's `dm-mod.create=` append. U-Boot's own per-boot randomness doesn't perturb PCR1, but **the measurement also doesn't cover those fixups**.
- **Anything that changes bootargs per boot or per slot changes PCR1.** A/B slot selection via bootargs (`rauc.slot=A`/`B`) is the common case.

The model in §2.6 demonstrates both.

**Sealing** binds a secret to a PCR policy: the TPM releases it only if the PCRs match. **Attestation** sends a TPM-signed quote of the PCRs plus the event log, which a verifier replays. The tension every design has to resolve: including more PCRs catches more attacks, but breaks unsealing on legitimate changes (A/B fallback, updates).

---

## 2. Production Code & Configuration Blueprints

### 2.1 The FIT source

#### The Fragile Way

```dts
/* fit-fragile.its - image-signed FIT: each image valid alone, so images from different releases can be mixed */
/dts-v1/;

/ {
	description = "Product kernel and DTB";
	#address-cells = <1>;

	images {
		kernel-1 {
			description = "Linux kernel";
			data = /incbin/("./Image.gz");
			type = "kernel";
			arch = "arm64";
			os = "linux";
			compression = "gzip";
			load = <0x44000000>;
			entry = <0x44000000>;
			signature-1 {
				algo = "sha1,rsa2048";
				key-name-hint = "dev";
			};
		};

		fdt-1 {
			description = "Board device tree";
			data = /incbin/("./board.dtb");
			type = "flat_dt";
			arch = "arm64";
			compression = "none";
			hash-1 {
				algo = "crc32";
			};
		};

		fdt-old {
			description = "Device tree from release 2024 (kept 'for rollback')";
			data = /incbin/("./board-2024.dtb");
			type = "flat_dt";
			arch = "arm64";
			compression = "none";
			signature-1 {
				algo = "sha1,rsa2048";
				key-name-hint = "dev";
			};
		};
	};

	configurations {
		default = "conf-1";

		conf-1 {
			kernel = "kernel-1";
			fdt = "fdt-1";
		};

		conf-legacy {
			kernel = "kernel-1";
			fdt = "fdt-old";
		};
	};
};
```

- **Image-level signatures:** mix-and-match across releases.
- **SHA-1 and CRC32:** a CRC is an error check, not a hash.
- **Two configurations**, one pointing at a 2024 DTB "for rollback": a permanent, validly signed downgrade path.
- **No configuration signature** at all.

#### The Silicon-Hardened Production Way

```dts
/* fit-signed.its - hardened FIT: every image hashed, the CONFIGURATION signed (RSA-3072, PSS), one config only */
/dts-v1/;

/ {
	description = "Product kernel, DTB and initramfs (release 2026.10.1)";
	#address-cells = <1>;

	images {
		kernel-1 {
			description = "Linux kernel";
			data = /incbin/("./Image.gz");
			type = "kernel";
			arch = "arm64";
			os = "linux";
			compression = "gzip";
			load = <0x44000000>;
			entry = <0x44000000>;
			hash-1 {
				algo = "sha256";
			};
		};

		fdt-1 {
			description = "Board device tree";
			data = /incbin/("./board.dtb");
			type = "flat_dt";
			arch = "arm64";
			compression = "none";
			hash-1 {
				algo = "sha256";
			};
		};

		ramdisk-1 {
			description = "initramfs: carries the dm-verity root hash of this release";
			data = /incbin/("./initramfs.cpio.gz");
			type = "ramdisk";
			arch = "arm64";
			os = "linux";
			compression = "none";
			hash-1 {
				algo = "sha256";
			};
		};
	};

	configurations {
		default = "conf-1";

		conf-1 {
			description = "Release 2026.10.1";
			kernel = "kernel-1";
			fdt = "fdt-1";
			ramdisk = "ramdisk-1";
			signature-1 {
				algo = "sha256,rsa3072";
				padding = "pss";
				key-name-hint = "fit-release-2026";
				sign-images = "kernel", "fdt", "ramdisk";
			};
		};
	};
};
```

One configuration. Every image has a SHA-256 hash. The **configuration** is signed with RSA-3072 using **PSS** padding: `padding = "pss"` selects U-Boot's `pss` padding algorithm, and it needs `CONFIG_RSASSA_PSS`; U-Boot's default is `pkcs-1.5`. `sign-images` lists every image the configuration uses. The dm-verity variant (U-Boot v2026.10 `CONFIG_FIT_VERITY`; mkimage `-E` computes the verity metadata):

```dts
/* fit-verity.its - signed config whose rootfs loadable carries dm-verity metadata (U-Boot v2026.10 CONFIG_FIT_VERITY) */
/dts-v1/;

/ {
	description = "Kernel + DTB + dm-verity-protected SquashFS root";
	#address-cells = <1>;

	images {
		kernel-1 {
			description = "Linux kernel";
			data = /incbin/("./Image.gz");
			type = "kernel";
			arch = "arm64";
			os = "linux";
			compression = "gzip";
			load = <0x44000000>;
			entry = <0x44000000>;
			hash-1 {
				algo = "sha256";
			};
		};

		fdt-1 {
			description = "Board device tree";
			data = /incbin/("./board.dtb");
			type = "flat_dt";
			arch = "arm64";
			compression = "none";
			hash-1 {
				algo = "sha256";
			};
		};

		rootfs-1 {
			description = "SquashFS root filesystem";
			data = /incbin/("./rootfs.squashfs");
			type = "filesystem";
			arch = "arm64";
			compression = "none";
			hash-1 {
				algo = "sha256";
			};
			/* mkimage -E fills digest, salt, num-data-blocks and hash-start-block by running
			 * veritysetup; the config signature then covers the root hash. */
			dm-verity {
				algo = "sha256";
				data-block-size = <4096>;
				hash-block-size = <4096>;
				restart-on-corruption;
			};
		};
	};

	configurations {
		default = "conf-1";

		conf-1 {
			description = "Boot with dm-verity rootfs";
			kernel = "kernel-1";
			fdt = "fdt-1";
			loadables = "rootfs-1";
			signature-1 {
				algo = "sha256,rsa3072";
				padding = "pss";
				key-name-hint = "fit-release-2026";
				sign-images = "kernel", "fdt", "loadables";
			};
		};
	};
};
```

Since neither `dtc` nor `mkimage` can run in this environment, the FIT sources are gated by two tools of my own. First, a structural linter, which is also used for every device tree in this KB:

```python
# dts_lint.py - structural checker for .dts/.dtsi/.its sources (a stand-in where dtc cannot be run)
"""dts_lint.py - structural checker for .dts/.dtsi/.its sources (a stand-in where dtc cannot be run).

Checks: tokenization (comments, strings, <cells>, [bytes], /incbin/), balanced braces, every statement
ends in ';', node-name syntax, unit-address == first reg address (dtc W=1 unit_address_vs_reg),
reg length vs parent #address-cells/#size-cells (dtc reg_format), duplicate node/property names,
labels and &label references resolve, and required properties given on the command line.
Usage: python dts_lint.py <file> [--require /path:prop ...]
Exit 1 on any error. Not a replacement for dtc + dt-schema; it catches the structural mistakes.
"""
import re
import sys

TOK = re.compile(r"""
    (?P<ws>\s+) | (?P<lc>//[^\n]*) | (?P<bc>/\*.*?\*/) |
    (?P<str>"(?:[^"\\]|\\.)*") | (?P<cells><[^>]*>) | (?P<bytes>\[[^\]]*\]) |
    (?P<incbin>/incbin/) | (?P<dtsv1>/dts-v1/) | (?P<plugin>/plugin/) | (?P<del>/delete-(?:node|property)/) |
    (?P<punct>[{};=,]) | (?P<ref>&[A-Za-z_][\w]*) | (?P<label>[A-Za-z_][\w]*:) |
    (?P<word>[A-Za-z0-9_,.+#@\-/?]+) | (?P<paren>[()]) | (?P<pre>\#include\s*[<"][^>"]+[>"])
""", re.S | re.X)


def tokens(src):
    pos = 0
    while pos < len(src):
        m = TOK.match(src, pos)
        if not m:
            line = src.count("\n", 0, pos) + 1
            raise SyntaxError(f"line {line}: cannot tokenize near {src[pos:pos + 20]!r}")
        kind = m.lastgroup
        if kind not in ("ws", "lc", "bc"):
            yield kind, m.group(0), src.count("\n", 0, pos) + 1
        pos = m.end()


class Node:
    def __init__(self, name, parent, line):
        self.name, self.parent, self.line = name, parent, line
        self.props, self.children = {}, []

    def path(self):
        if self.parent is None:
            return "/"
        base = self.parent.path()
        return (base.rstrip("/") + "/" + self.name)


def parse(src, errors):
    root = Node("/", None, 1)
    stack, labels, refs = [], {}, []
    toks = list(tokens(src))
    i = 0
    cur = None
    pending_labels = []
    while i < len(toks):
        kind, val, line = toks[i]
        if kind in ("dtsv1", "plugin"):
            if i + 1 >= len(toks) or toks[i + 1][1] != ";":
                errors.append(f"line {line}: {val} must end with ';'")
            i += 2
            continue
        if kind == "pre":
            i += 1
            continue
        if kind == "label":
            pending_labels.append(val[:-1])
            i += 1
            continue
        if kind in ("word", "ref") and i + 1 < len(toks) and toks[i + 1][1] == "{":
            if kind == "ref":                               # &label { ... } overlay-style extension
                refs.append((val[1:], line))
                node = Node(val, cur or root, line)
            elif cur is None and val == "/":
                node = root
            else:
                if not re.fullmatch(r"[A-Za-z0-9,._+\-]+(@[0-9a-fA-F,]+)?", val):
                    errors.append(f"line {line}: bad node name {val!r}")
                parent = cur or root
                if any(c.name == val for c in parent.children):
                    errors.append(f"line {line}: duplicate node {val!r} under {parent.path()}")
                node = Node(val, parent, line)
                parent.children.append(node)
            for lab in pending_labels:
                if lab in labels:
                    errors.append(f"line {line}: duplicate label {lab!r}")
                labels[lab] = node
            pending_labels = []
            stack.append(cur)
            cur = node
            i += 2
            continue
        if val == "}":
            if not stack and cur is None:
                errors.append(f"line {line}: unbalanced '}}'")
                i += 1
                continue
            if i + 1 >= len(toks) or toks[i + 1][1] != ";":
                errors.append(f"line {line}: node {cur.name if cur else '?'} closed without ';'")
                i += 1
            else:
                i += 2
            cur = stack.pop() if stack else None
            continue
        if kind == "word":
            name = val
            j = i + 1
            value = []
            if j < len(toks) and toks[j][1] == "=":
                j += 1
                while j < len(toks) and toks[j][1] not in (";", "}", "{"):
                    value.append(toks[j])
                    if toks[j][0] == "ref":
                        refs.append((toks[j][1][1:], toks[j][2]))
                    if toks[j][0] == "cells":
                        refs += [(r[1:], toks[j][2]) for r in re.findall(r"&[A-Za-z_]\w*", toks[j][1])]
                    j += 1
            terminated = j < len(toks) and toks[j][1] == ";"
            if not terminated:
                errors.append(f"line {line}: property {name!r} not terminated by ';'")
            target = cur or root
            if name in target.props:
                errors.append(f"line {line}: duplicate property {name!r} in {target.path()}")
            target.props[name] = value
            i = j + 1 if terminated else j          # recover: let '}' / '{' be parsed normally
            pending_labels = []
            continue
        if kind == "del":
            while i < len(toks) and toks[i][1] != ";":
                i += 1
            i += 1
            continue
        errors.append(f"line {line}: unexpected token {val!r}")
        i += 1
    if stack or cur is not None:
        errors.append("unbalanced braces at end of file")
    for lab, line in refs:
        if lab not in labels:
            errors.append(f"line {line}: reference &{lab} has no label")
    return root


def cells(value):
    out = []
    for kind, val, _ in value:
        if kind == "cells":
            out += [c for c in val[1:-1].split() if not c.startswith("&")]
    return out


def to_int(tok):
    tok = tok.strip("()")
    return int(tok, 0)


def check_tree(node, errors, ac=2, sc=1):
    for child in node.children:
        reg = child.props.get("reg")
        if reg is not None:
            c = cells(reg)
            if len(c) % (ac + sc) != 0:
                errors.append(f"{child.path()}: reg has {len(c)} cells, parent wants multiples of {ac}+{sc}")
            elif "@" in child.name and ac > 0:
                try:
                    addr = 0
                    for x in c[:ac]:
                        addr = (addr << 32) | to_int(x)
                    unit = int(child.name.split("@", 1)[1].split(",")[0], 16)
                    if unit != addr:
                        errors.append(f"{child.path()}: unit address 0x{unit:x} != reg address 0x{addr:x}")
                except ValueError:
                    pass
        elif "@" in child.name and not child.name.startswith("&"):
            errors.append(f"{child.path()}: has a unit address but no reg")
        cac = int(cells(child.props["#address-cells"])[0], 0) if "#address-cells" in child.props else 2
        csc = int(cells(child.props["#size-cells"])[0], 0) if "#size-cells" in child.props else 1
        check_tree(child, errors, cac, csc)


def find(root, path):
    node = root
    for part in [p for p in path.split("/") if p]:
        node = next((c for c in node.children if c.name == part), None)
        if node is None:
            return None
    return node


def main():
    args = sys.argv[1:]
    path = args[0]
    reqs = [a for a in args[1:] if a != "--require"]
    errors = []
    root = parse(open(path, encoding="utf-8").read(), errors)
    rac = int(cells(root.props["#address-cells"])[0], 0) if "#address-cells" in root.props else 2
    rsc = int(cells(root.props["#size-cells"])[0], 0) if "#size-cells" in root.props else 1
    check_tree(root, errors, rac, rsc)
    for r in reqs:
        npath, prop = r.rsplit(":", 1)
        n = find(root, npath)
        if n is None or prop not in n.props:
            errors.append(f"required {prop!r} missing at {npath}")
    count = [0]

    def walk(n):
        count[0] += 1
        for c in n.children:
            walk(c)
    walk(root)
    for e in errors:
        print("ERROR", e)
    print(f"{path.split('/')[-1]}: {count[0]} nodes, {len(errors)} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
```

Second, a signing-policy gate that turns §1.2 into CI failures:

```python
# fit_policy.py - CI gate for FIT sources: signed configurations only, strong hashes, complete sign-images
"""Usage: python fit_policy.py <file.its> ...   (exit 1 if any file violates the policy)

Policy (rationale in 01.4 section 2.1):
  P1 every image has a hash subnode with sha256/sha384/sha512 (no crc32/md5/sha1)
  P2 no signature subnodes on images: image-only signing permits mix-and-match across releases
  P3 exactly one bootable configuration, and `default` names it: extra configs are downgrade paths
  P4 every configuration has a signature subnode with an approved algo and a key-name-hint
  P5 sign-images lists every image-reference property the configuration uses
  P6 RSA signatures declare padding = "pss" (U-Boot's default is pkcs-1.5)
"""
import sys

import dts_lint

APPROVED = {"sha256,rsa3072", "sha256,rsa4096", "sha384,rsa3072", "sha384,rsa4096",
            "sha256,ecdsa256", "sha384,ecdsa384"}
STRONG_HASH = {"sha256", "sha384", "sha512"}
IMAGE_REFS = ("kernel", "fdt", "ramdisk", "loadables", "firmware", "fpga", "setup")


def strings(value):
    return [tok[1:-1] for kind, tok, _ in value if kind == "str"]


def check(path):
    errors = []
    root = dts_lint.parse(open(path, encoding="utf-8").read(), errors)
    if errors:
        return [f"structure: {e}" for e in errors]
    images = dts_lint.find(root, "/images")
    confs = dts_lint.find(root, "/configurations")
    if images is None or confs is None:
        return ["missing /images or /configurations"]
    names = {img.name for img in images.children}
    for img in images.children:
        hashes = [c for c in img.children if c.name.startswith("hash")]
        algos = [s for h in hashes for s in strings(h.props.get("algo", []))]
        if not algos or not all(a in STRONG_HASH for a in algos):
            errors.append(f"P1 /images/{img.name}: hash algos {algos or 'none'}")
        if any(c.name.startswith("signature") for c in img.children):
            errors.append(f"P2 /images/{img.name}: image-level signature (mix-and-match)")
    configs = confs.children
    default = strings(confs.props.get("default", []))
    if len(configs) != 1 or default != [configs[0].name]:
        errors.append(f"P3 {len(configs)} configurations ({', '.join(c.name for c in configs)}), default={default}")
    for conf in configs:
        used = [p for p in IMAGE_REFS if p in conf.props]
        for p in used:
            for ref in strings(conf.props[p]):
                if ref not in names:
                    errors.append(f"/configurations/{conf.name}: {p} -> missing image {ref!r}")
        sigs = [c for c in conf.children if c.name.startswith("signature")]
        if not sigs:
            errors.append(f"P4 /configurations/{conf.name}: not signed")
        for sig in sigs:
            algo = strings(sig.props.get("algo", []))
            if algo[:1] and algo[0] not in APPROVED:
                errors.append(f"P4 {conf.name}/{sig.name}: algo {algo[0]!r} not approved")
            if "key-name-hint" not in sig.props:
                errors.append(f"P4 {conf.name}/{sig.name}: no key-name-hint")
            missing = set(used) - set(strings(sig.props.get("sign-images", [])))
            if missing:
                errors.append(f"P5 {conf.name}/{sig.name}: sign-images omits {sorted(missing)}")
            if algo[:1] and "rsa" in algo[0] and strings(sig.props.get("padding", [])) != ["pss"]:
                errors.append(f"P6 {conf.name}/{sig.name}: RSA without padding = \"pss\"")
    return errors


def main():
    bad = 0
    for path in sys.argv[1:]:
        errs = check(path)
        bad += bool(errs)
        print(f"{'PASS' if not errs else 'FAIL'} {path.split('/')[-1]}")
        for e in errs:
            print(f"     {e}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
```

```text
fit-signed.its: 11 nodes, 0 error(s)
fit-verity.its: 12 nodes, 0 error(s)
fit-fragile.its: 11 nodes, 0 error(s)
PASS fit-signed.its
PASS fit-verity.its
FAIL fit-fragile.its
     P1 /images/kernel-1: hash algos none
     P2 /images/kernel-1: image-level signature (mix-and-match)
     P1 /images/fdt-1: hash algos ['crc32']
     P1 /images/fdt-old: hash algos none
     P2 /images/fdt-old: image-level signature (mix-and-match)
     P3 2 configurations (conf-1, conf-legacy), default=['conf-1']
     P4 /configurations/conf-1: not signed
     P4 /configurations/conf-legacy: not signed
fit_policy exit=1
```

### 2.2 The U-Boot configuration

#### The Fragile Way

```ini
# uboot-fragile.config - "secure boot enabled" as it often ships: signature support on, every way around it left open
CONFIG_FIT=y
CONFIG_FIT_SIGNATURE=y
CONFIG_RSA=y
# SPL loads U-Boot proper without checking it: the chain is broken one stage earlier.
# CONFIG_SPL_FIT_SIGNATURE is not set
CONFIG_LEGACY_IMAGE_FORMAT=y
CONFIG_BOOTDELAY=3
CONFIG_CMD_MEMORY=y
CONFIG_CMD_FDT=y
CONFIG_CMD_SETEXPR=y
CONFIG_CMD_EXPORTENV=y
# The environment is fully writable: bootcmd, bootargs (and the verity root hash in them) are attacker-controlled.
# CONFIG_ENV_WRITEABLE_LIST is not set
```

"Secure boot is enabled" here means only that `FIT_SIGNATURE` is set. Around it:
- **SPL loads U-Boot proper unverified.**
- **Legacy images** offer a bypass.
- **A 3-second autoboot delay** gives a shell.
- **`md`/`mw` and `fdt`** in that shell let anyone rewrite memory and device trees.
- **A fully writable environment** lets anyone change `bootcmd` and `bootargs`.

#### The Silicon-Hardened Production Way

```ini
# uboot-secure.config - production verified-boot fragment for U-Boot v2026.10 (merge after the board defconfig)
# --- FIT verification, in SPL and in U-Boot proper ---
CONFIG_FIT=y
CONFIG_FIT_SIGNATURE=y
CONFIG_FIT_FULL_CHECK=y
CONFIG_FIT_SIGNATURE_MAX_SIZE=0x4000000
CONFIG_RSA=y
CONFIG_RSASSA_PSS=y
CONFIG_SPL_FIT=y
CONFIG_SPL_LOAD_FIT=y
CONFIG_SPL_FIT_SIGNATURE=y
CONFIG_SPL_RSA=y
CONFIG_SPL_RSASSA_PSS=y
# Legacy uImage has no signature support: with it enabled, `bootm` of a legacy image bypasses FIT checks.
# CONFIG_LEGACY_IMAGE_FORMAT is not set
# --- No interactive door around the policy ---
CONFIG_BOOTDELAY=-2
# CONFIG_AUTOBOOT_KEYED is not set
# --- Environment: only flagged variables may change at runtime, and -f cannot override the flags ---
CONFIG_ENV_WRITEABLE_LIST=y
CONFIG_ENV_ACCESS_IGNORE_FORCE=y
# --- Commands that turn a shell into arbitrary memory read/write or image surgery ---
# CONFIG_CMD_MEMORY is not set
# CONFIG_CMD_FDT is not set
# CONFIG_CMD_ITEST is not set
# CONFIG_CMD_SETEXPR is not set
# CONFIG_CMD_UNZIP is not set
# CONFIG_CMD_EXPORTENV is not set
# --- A/B fallback (Folder 03) ---
CONFIG_BOOTCOUNT_LIMIT=y
CONFIG_BOOTCOUNT_ENV=y
# --- Measured boot (section 1.5): kernel -> PCR8, initrd -> PCR9, DTB + bootargs -> PCR1 ---
CONFIG_TPM_V2=y
CONFIG_MEASURED_BOOT=y
CONFIG_MEASURE_DEVICETREE=y
```

`CONFIG_ENV_WRITEABLE_LIST` permits runtime changes only to variables explicitly flagged writable (`w`). List only what A/B logic needs, e.g. `bootcount`, `upgrade_available`, `boot_slot`, in the board's environment flags. `CONFIG_ENV_ACCESS_IGNORE_FORCE` stops `env set -f` from overriding the flags.

**The silent-typo problem.** A defconfig fragment line that names a symbol the tree doesn't define is ignored by kconfig without an error, so the option you believe you enabled doesn't exist. While writing this file I guessed `CONFIG_FIT_RSASSA_PSS`; the real symbol is `CONFIG_RSASSA_PSS`. This gate is how that kind of mistake gets caught:

```python
# kconfig_check.py - verify every symbol in a defconfig fragment exists in a U-Boot (or Linux) source tree
"""Usage: python kconfig_check.py <source-tree> <fragment> [--deny SYM=y ...]

A fragment line that names a symbol the tree doesn't define is silently ignored by `merge_config.sh` and
kconfig: the option you think you set does not exist. This gate makes that a build failure. --deny turns
dangerous settings (e.g. LEGACY_IMAGE_FORMAT=y) into failures too.
"""
import pathlib
import re
import sys


def defined_symbols(tree: pathlib.Path) -> set[str]:
    syms = set()
    for kc in tree.rglob("Kconfig*"):
        try:
            text = kc.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        syms.update(re.findall(r"^\s*(?:menu)?config\s+([A-Z0-9_]+)\s*$", text, flags=re.M))
    return syms


def main() -> None:
    tree, frag = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    deny = {a.split("=")[0]: a.split("=")[1] for a in sys.argv[3:] if "=" in a}
    syms = defined_symbols(tree)
    errors, seen = [], 0
    for n, line in enumerate(frag.read_text(encoding="utf-8").splitlines(), 1):
        m = re.match(r"^CONFIG_([A-Z0-9_]+)=(.*)$", line) or re.match(r"^# CONFIG_([A-Z0-9_]+) is not set$", line)
        if not m:
            continue
        seen += 1
        sym = m.group(1)
        val = m.group(2) if m.lastindex == 2 else "n"
        if sym not in syms:
            errors.append(f"line {n}: CONFIG_{sym} is not defined in {tree.name}")
        if deny.get(sym) == val:
            errors.append(f"line {n}: CONFIG_{sym}={val} is denied by policy")
    for e in errors:
        print("ERROR", e)
    print(f"{frag.name}: {seen} symbols checked against {len(syms)} defined in {tree.name}, {len(errors)} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
```

```text
uboot-secure.config: 27 symbols checked against 8577 defined in u-boot-2026.10, 0 error(s)
ERROR line 6: CONFIG_SPL_FIT_SIGNATURE=n is denied by policy
ERROR line 7: CONFIG_LEGACY_IMAGE_FORMAT=y is denied by policy
ERROR line 9: CONFIG_CMD_MEMORY=y is denied by policy
ERROR line 10: CONFIG_CMD_FDT=y is denied by policy
ERROR line 14: CONFIG_ENV_WRITEABLE_LIST=n is denied by policy
uboot-fragile.config: 11 symbols checked against 8577 defined in u-boot-2026.10, 5 error(s)
fragile exit=1
ERROR line 1: CONFIG_FIT_RSASSA_PSS is not defined in u-boot-2026.10
typo.config: 1 symbols checked against 8577 defined in u-boot-2026.10, 1 error(s)
```

### 2.3 Signing and key enrollment

#### The Fragile Way

- **A development key** (`key-name-hint = "dev"`) in the source tree.
- **`mkimage -f fit.its -k keys -K u-boot.dtb image.itb` without `-r`.** Without `-r`, the key isn't marked *required*: U-Boot verifies signatures that are present, **but boots FITs that carry no signature at all**. The attacker doesn't forge a signature; they delete it.
- **No verification of the output** before release.

#### The Silicon-Hardened Production Way

```bash
#!/bin/sh
# sign-fit.sh - release signing of the FIT with an HSM key, and enrollment of the public key into U-Boot's DTB
# Inputs: fit-signed.its and its /incbin/ payloads; u-boot.dtb (U-Boot's control DTB, built without keys);
#         FIT_TOKEN = the PKCS#11 token URL of the release signing key (see doc/usage/fit/signature.rst).
set -eu

: "${FIT_TOKEN:?set FIT_TOKEN to the pkcs11: URL of the release token}"
OUT=${OUT:-out}
mkdir -p "$OUT"
cp u-boot.dtb "$OUT/u-boot.dtb"

# 0. Policy gate before anything is signed (fit_policy.py, section 2.1).
python3 fit_policy.py fit-signed.its

# 1. Build the unsigned FIT (hash nodes are filled in).
mkimage -f fit-signed.its "$OUT/image.itb"

# 2. Sign in place with the HSM key; -K writes the public key into U-Boot's DTB, and -r marks it
#    "required", so U-Boot refuses any configuration this key did not sign.
mkimage -F -k "$FIT_TOKEN" -K "$OUT/u-boot.dtb" -N pkcs11 -r "$OUT/image.itb"

# 3. Verify the result the way the device will, with the exact DTB that ships in U-Boot.
fit_check_sign -f "$OUT/image.itb" -k "$OUT/u-boot.dtb" -c conf-1

# 4. Belt and braces: the enrolled key must be marked required for configurations.
test "$(fdtget "$OUT/u-boot.dtb" /signature/key-fit-release-2026 required)" = conf

# 5. Record digests for the release manifest (reproducible-build check, Folder 02).
sha256sum "$OUT/image.itb" "$OUT/u-boot.dtb" > "$OUT/SHA256SUMS"
echo "signed: $OUT/image.itb; rebuild U-Boot with EXT_DTB=$OUT/u-boot.dtb (or CONFIG_DEVICE_TREE_INCLUDES)"
```

- **Sign in the HSM** via PKCS#11, in place (`-F`), following U-Boot's documented flow.
- **`-r`** enrolls the key as required.
- **Verify** with the exact `u-boot.dtb` that ships, using `fit_check_sign`.
- **Assert** the `required` property.
- **Record digests** for reproducibility (Folder 02).

### 2.4 dm-verity

The tree, implemented from the kernel's code and validated against cryptsetup's published vectors:

```python
# verity_tree.py - dm-verity Merkle tree (format 0 and 1) exactly as drivers/md/dm-verity-target.c walks it
"""Builds the hash area for a data image, computes the root hash, and verifies single blocks the way the
kernel does on a page-cache miss. Self-test: reproduces the root hashes in cryptsetup's own
tests/verity-compat-test (8 MiB of zeros; 512/1024/4096-byte blocks; sha256 and sha1; v0 and v1).

Layout facts used (Linux v7.2):
  hash_per_block_bits = floor(log2(hash_block_size / digest_size))
  levels              = smallest L with (data_blocks - 1) >> (bits * L) == 0
  hash_level_block[i] : levels are stored TOP level first (i = levels-1 at hash_start)
  digest offset       : v1 idx << (block_bits - bits) (each digest padded to a power of two); v0 idx * digest_size
  hashing             : v1 H(salt || block); v0 H(block || salt). Root = hash of the single top-level block.
"""
import hashlib


class Verity:
    def __init__(self, alg="sha256", block=4096, salt=b"", version=1):
        self.alg, self.block, self.salt, self.version = alg, block, salt, version
        self.dsize = hashlib.new(alg).digest_size
        self.bits = (block // self.dsize).bit_length() - 1          # __fls(block / digest_size)
        self.slot = block >> self.bits if version else self.dsize

    def h(self, data: bytes) -> bytes:
        m = hashlib.new(self.alg)
        if self.version:
            m.update(self.salt)
            m.update(data)
        else:
            m.update(data)
            m.update(self.salt)
        return m.digest()

    def _pack(self, digests):
        per = 1 << self.bits
        blocks = []
        for i in range(0, len(digests), per):
            b = bytearray(self.block)
            for j, d in enumerate(digests[i:i + per]):
                b[j * self.slot: j * self.slot + self.dsize] = d
            blocks.append(bytes(b))
        return blocks

    def build(self, data: bytes):
        assert len(data) % self.block == 0
        nblk = len(data) // self.block
        levels = 0
        while self.bits * levels < 64 and (nblk - 1) >> (self.bits * levels):
            levels += 1
        tree = []                                                      # tree[0] = level 0 (bottom)
        digests = [self.h(data[i * self.block:(i + 1) * self.block]) for i in range(nblk)]
        for _ in range(levels):
            blocks = self._pack(digests)
            tree.append(blocks)
            digests = [self.h(b) for b in blocks]
        root = digests[0]                                              # hash of the top block (or of the data if levels == 0)
        area = b"".join(b"".join(tree[i]) for i in reversed(range(levels)))   # top level first on disk
        start, pos = {}, 0
        for i in reversed(range(levels)):
            start[i] = pos
            pos += len(tree[i])
        self.nblk, self.levels, self.level_start = nblk, levels, start
        return root, area

    def verify_block(self, data: bytes, area: bytes, root: bytes, index: int) -> bool:
        """The kernel's verity_verify_io for one data block: hash it, then walk up to the root."""
        want = self.h(data[index * self.block:(index + 1) * self.block])
        for level in range(self.levels):
            pos = index >> (level * self.bits)
            hblock = self.level_start[level] + (pos >> self.bits)
            idx = pos & ((1 << self.bits) - 1)
            off = idx << (self.block.bit_length() - 1 - self.bits) if self.version else idx * self.dsize
            blk = area[hblock * self.block:(hblock + 1) * self.block]
            if blk[off:off + self.dsize] != want:
                return False                                           # -EIO, plus the corruption policy
            want = self.h(blk)                                         # this hash block's own digest, one level up
        return want == root


VECTORS = [  # cryptsetup tests/verity-compat-test, data = 8192 KiB of zeros
    (512, "sha256", "e48da609055204e89ae53b655ca2216dd983cf3cb829f34f63a297d106d53e2d", 1,
     "9de18652fe74edfb9b805aaed72ae2aa48f94333f1ba5c452ac33b1c39325174"),
    (1024, "sha256", "e48da609055204e89ae53b655ca2216dd983cf3cb829f34f63a297d106d53e2d", 1,
     "54d92778750495d1f80832b486ebd007617d746271511bbf0e295e143da2b3df"),
    (4096, "sha256", "e48da609055204e89ae53b655ca2216dd983cf3cb829f34f63a297d106d53e2d", 1,
     "e522df0f97da4febb882ac40f30b37dc0b444bf6df418929463fa25280f09d5c"),
    (4096, "sha256", "e48da609055204e89ae53b655ca2216dd983cf3cb829f34f63a297d106d53e2d", 0,
     "cbbf4ebd004ef65e29b935bb635a39cf754d677f3fa10b0126da725bbdf10f7d"),
    (4096, "sha256", "", 1, "ef29c902d87350f1da4bfa536e16cebc162a909bf89abe448b81ec500d4fb9bf"),
    (1024, "sha1", "e48da609055204e89ae53b655ca2216dd983cf3cb829f34f63a297d106d53e2d", 1,
     "d0e9163ca8844aaa2e88fe5265a8c5d9ee494a99"),
    (1024, "sha1", "dadada", 1, "73509e8e868be6b8ac939817a98a3d35121413b2"),
]


def main() -> None:
    zeros = bytes(8192 * 1024)
    fails = 0
    print("[1] root hashes vs cryptsetup's verity-compat-test vectors")
    for block, alg, salt, ver, want in VECTORS:
        v = Verity(alg, block, bytes.fromhex(salt), ver)
        root, area = v.build(zeros)
        ok = root.hex() == want
        fails += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} v{ver} {alg:6s} block {block:4d} salt={'-' if not salt else salt[:6]:6s}"
              f" levels={v.levels} hash-area={len(area) // 1024:4d} KiB root={root.hex()[:16]}...")

    print("[2] read-path verification and tampering (64 MiB pseudo-random image, sha256, 4096, v1)")
    import random
    rng = random.Random(1)
    img = bytearray(rng.randbytes(64 * 1024 * 1024))
    v = Verity("sha256", 4096, bytes.fromhex(VECTORS[0][2]), 1)
    root, area = v.build(bytes(img))
    checks = [
        ("every sampled block verifies", all(v.verify_block(bytes(img), area, root, i) for i in range(0, v.nblk, 997))),
    ]
    img[5 * 4096 + 77] ^= 1                                   # offline tamper of one data byte
    checks.append(("flipped data bit in block 5 -> that block fails", not v.verify_block(bytes(img), area, root, 5)))
    checks.append(("block 6 still verifies (damage is local)", v.verify_block(bytes(img), area, root, 6)))
    img[5 * 4096 + 77] ^= 1
    bad = bytearray(area)
    bad[len(bad) - 4096 + 10] ^= 1                            # tamper the bottom level's last hash block
    checks.append(("flipped bit in a level-0 hash block -> covered blocks fail",
                   not v.verify_block(bytes(img), bytes(bad), root, v.nblk - 1)))
    other_root, _ = v.build(bytes(img[:-4096]) + bytes(4096))
    checks.append(("a different image yields a different root hash", other_root != root))
    for name, ok in checks:
        fails += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    print(f"  dm table: 0 {v.nblk * 8} verity 1 /dev/ROOT /dev/HASH 4096 4096 {v.nblk} 1 sha256 {root.hex()} {VECTORS[0][2]}")
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
[1] root hashes vs cryptsetup's verity-compat-test vectors
  ok   v1 sha256 block  512 salt=e48da6 levels=4 hash-area= 546 KiB root=9de18652fe74edfb...
  ok   v1 sha256 block 1024 salt=e48da6 levels=3 hash-area= 265 KiB root=54d92778750495d1...
  ok   v1 sha256 block 4096 salt=e48da6 levels=2 hash-area=  68 KiB root=e522df0f97da4feb...
  ok   v0 sha256 block 4096 salt=e48da6 levels=2 hash-area=  68 KiB root=cbbf4ebd004ef65e...
  ok   v1 sha256 block 4096 salt=-      levels=2 hash-area=  68 KiB root=ef29c902d87350f1...
  ok   v1 sha1   block 1024 salt=e48da6 levels=3 hash-area= 265 KiB root=d0e9163ca8844aaa...
  ok   v1 sha1   block 1024 salt=dadada levels=3 hash-area= 265 KiB root=73509e8e868be6b8...
[2] read-path verification and tampering (64 MiB pseudo-random image, sha256, 4096, v1)
  ok   every sampled block verifies
  ok   flipped data bit in block 5 -> that block fails
  ok   block 6 still verifies (damage is local)
  ok   flipped bit in a level-0 hash block -> covered blocks fail
  ok   a different image yields a different root hash
  dm table: 0 131072 verity 1 /dev/ROOT /dev/HASH 4096 4096 16384 1 sha256 6405e5df4779ba7f9f46310acca04db978b92c872d41985c07739bae0d1b62df e48da609055204e89ae53b655ca2216dd983cf3cb829f34f63a297d106d53e2d
ALL PASSED: 0 failure(s)
```

#### The Fragile Way

```bash
#!/bin/sh
# init-verity-fragile.sh - initramfs /init that trusts the kernel command line for the root hash
mount -t proc proc /proc
mount -t devtmpfs devtmpfs /dev

# BUG 1: roothash= comes from bootargs, i.e. from U-Boot's environment. If the environment is writable
# (or bootargs is not part of anything signed), the attacker supplies the root hash of THEIR rootfs.
for arg in $(cat /proc/cmdline); do
	case "$arg" in
	roothash=*) ROOTHASH=${arg#roothash=} ;;
	esac
done

# BUG 2: "verity is optional": no hash on the cmdline means boot the plain partition.
if [ -z "${ROOTHASH:-}" ]; then
	mount -o ro /dev/mmcblk0p2 /newroot
else
	# BUG 3: --ignore-corruption: corrupted blocks are logged and returned anyway.
	veritysetup open /dev/mmcblk0p2 vroot /dev/mmcblk0p3 "$ROOTHASH" --ignore-corruption
	mount -o ro /dev/mapper/vroot /newroot
fi
exec switch_root /newroot /sbin/init
```

- **A root hash from the kernel command line**, i.e. from U-Boot's environment: whoever can edit `bootargs` chooses the root filesystem.
- **A silent fallback to an unverified root** when the hash is missing.
- **`--ignore-corruption`.**

#### The Silicon-Hardened Production Way

```bash
#!/bin/sh
# init-verity.sh - initramfs /init: root hash comes from INSIDE the signed initramfs, never from the cmdline
# Build-time inputs baked into this initramfs (and therefore covered by the FIT configuration signature):
#   /etc/verity/roothash   hex root hash of rootfs.squashfs   (veritysetup format output)
#   /etc/verity/salt       hex salt
#   /etc/verity/params     ROOT_DEV, HASH_DEV, DATA_BLOCKS, HASH_OFFSET
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

fail() {
	echo "init-verity: $*" > /dev/kmsg
	# Never fall back to an unverified root. Reboot; the bootloader's bootcount picks the other slot.
	echo b > /proc/sysrq-trigger
	exit 1
}

. /etc/verity/params
ROOTHASH=$(cat /etc/verity/roothash)
SALT=$(cat /etc/verity/salt)

# Wait for the block devices (eMMC enumeration is asynchronous).
i=0
while [ ! -b "$ROOT_DEV" ] || [ ! -b "$HASH_DEV" ]; do
	i=$((i + 1))
	[ "$i" -gt 50 ] && fail "root devices did not appear"
	sleep 0.1
done

# Activate the verity target. --panic-on-corruption: a modified block halts the system instead of
# returning an error that a buggy service might ignore.
veritysetup open "$ROOT_DEV" vroot "$HASH_DEV" "$ROOTHASH" \
	--no-superblock --format=1 --hash=sha256 \
	--data-block-size=4096 --hash-block-size=4096 \
	--data-blocks="$DATA_BLOCKS" --hash-offset="$HASH_OFFSET" \
	--salt="$SALT" --panic-on-corruption || fail "veritysetup open failed"

mkdir -p /newroot
mount -o ro -t squashfs /dev/mapper/vroot /newroot || fail "cannot mount verified root"

# Writable state lives on a separate, encrypted filesystem (fscrypt, section 2.4), mounted by the real init.
umount /sys /proc
exec switch_root /newroot /sbin/init
```

- **The root hash and salt are files inside the initramfs**, so the FIT configuration signature covers them.
- **No unverified fallback:** a failure reboots, and `bootcount` (Folder 03) moves to the other slot.
- **`--panic-on-corruption`.**
- **No superblock;** parameters are fixed at build time.

### 2.5 fscrypt for writable data

#### The Fragile Way

- The fscrypt master key in a file: in `/etc`, in the initramfs, or derived from a constant "passphrase". Anyone with the flash image decrypts every device.
- **Or** a CAAM-backed trusted key on parts that were never closed, which use the fixed test key (§1.4).
- **Or** `FS_IOC_SET_ENCRYPTION_POLICY` re-run blindly at every boot, which on a fresh `/var` silently creates an unencrypted directory if key setup failed.

#### The Silicon-Hardened Production Way

```c
/* fscrypt_unlock.c - early-boot: derive /var's fscrypt v2 master key in the TEE, add it to the kernel, set policy */
#define _DEFAULT_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <linux/fscrypt.h>
#include <tee_client_api.h>

#include "vault_ta.h"

/* The master key never exists on disk. It is HMAC(device key, label), computed inside the vault TA
 * (01.3), so it is bound to this SoC's HUK. A v2 policy with AES-256 needs a key of >= 32 bytes. */
static const char LABEL[] = "fscrypt:/var/data:v1";

static int derive_master_key(uint8_t key[VAULT_MAC_LEN])
{
	TEEC_Context ctx;
	TEEC_Session sess;
	TEEC_Operation op;
	TEEC_UUID uuid = TA_VAULT_UUID;
	uint32_t origin = 0;
	int rc = -1;

	if (TEEC_InitializeContext(NULL, &ctx) != TEEC_SUCCESS)
		return -1;
	if (TEEC_OpenSession(&ctx, &sess, &uuid, TEEC_LOGIN_PUBLIC, NULL, NULL, &origin) == TEEC_SUCCESS) {
		memset(&op, 0, sizeof(op));
		op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_INPUT, TEEC_MEMREF_TEMP_OUTPUT,
						 TEEC_NONE, TEEC_NONE);
		op.params[0].tmpref.buffer = (void *)LABEL;
		op.params[0].tmpref.size = sizeof(LABEL) - 1;
		op.params[1].tmpref.buffer = key;
		op.params[1].tmpref.size = VAULT_MAC_LEN;
		if (TEEC_InvokeCommand(&sess, TA_VAULT_CMD_HMAC, &op, &origin) == TEEC_SUCCESS &&
		    op.params[1].tmpref.size == VAULT_MAC_LEN)
			rc = 0;
		TEEC_CloseSession(&sess);
	}
	TEEC_FinalizeContext(&ctx);
	return rc;
}

int main(int argc, char **argv)
{
	const char *mnt = argc > 1 ? argv[1] : "/var";
	const char *dir = argc > 2 ? argv[2] : "/var/data";
	uint8_t key[VAULT_MAC_LEN];
	size_t argsz = sizeof(struct fscrypt_add_key_arg) + sizeof(key);
	struct fscrypt_add_key_arg *add = calloc(1, argsz);
	struct fscrypt_policy_v2 pol;
	int mfd = -1, dfd = -1, rc = 1;

	if (!add || derive_master_key(key) != 0) {
		fprintf(stderr, "fscrypt_unlock: key derivation in the TEE failed\n");
		goto out;
	}

	/* 1. Hand the raw key to the filesystem keyring; the kernel returns its 16-byte identifier. */
	mfd = open(mnt, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	if (mfd < 0) {
		perror(mnt);
		goto out;
	}
	add->key_spec.type = FSCRYPT_KEY_SPEC_TYPE_IDENTIFIER;
	add->raw_size = sizeof(key);
	memcpy(add->raw, key, sizeof(key));
	if (ioctl(mfd, FS_IOC_ADD_ENCRYPTION_KEY, add) != 0) {
		perror("FS_IOC_ADD_ENCRYPTION_KEY");
		goto out;
	}

	/* 2. Bind the directory to that key with a v2 policy. On an already-encrypted directory the same
	 *    policy succeeds (no-op); a different one fails with EEXIST: never silently re-key. */
	memset(&pol, 0, sizeof(pol));
	pol.version = FSCRYPT_POLICY_V2;
	pol.contents_encryption_mode = FSCRYPT_MODE_AES_256_XTS;
	pol.filenames_encryption_mode = FSCRYPT_MODE_AES_256_HCTR2;
	pol.flags = FSCRYPT_POLICY_FLAGS_PAD_32;
	memcpy(pol.master_key_identifier, add->key_spec.u.identifier, FSCRYPT_KEY_IDENTIFIER_SIZE);
	dfd = open(dir, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	if (dfd < 0) {
		perror(dir);
		goto out;
	}
	if (ioctl(dfd, FS_IOC_SET_ENCRYPTION_POLICY, &pol) != 0) {
		fprintf(stderr, "FS_IOC_SET_ENCRYPTION_POLICY: %s%s\n", strerror(errno),
			errno == EEXIST ? " (directory uses a different key: refusing)" : "");
		goto out;
	}
	rc = 0;
out:
	explicit_bzero(key, sizeof(key));      /* the only plaintext copy outside the kernel */
	if (add) {
		explicit_bzero(add, argsz);
		free(add);
	}
	if (dfd >= 0)
		close(dfd);
	if (mfd >= 0)
		close(mfd);
	return rc;
}
```

- **The key is derived inside the TEE** from this device's HUK.
- **Added to the filesystem keyring with a v2 policy** (AES-256-XTS / AES-256-HCTR2).
- **Policy mismatch is a hard error** (`EEXIST`), never a silent re-key.
- **The plaintext key is wiped** from userspace memory.

Two refinements belong in production:
- **One-shot derivation:** the vault TA should refuse this label after early boot, so a later root compromise can't re-derive the key (a TA-side "lock until reboot" flag).
- **Hardware-wrapped keys** where the inline crypto engine supports them.

Compile results (aarch64 Linux, Clang 21.1):

```text
OK   sign-fit.sh  (sh -n, bash --posix -n)
OK   init-verity.sh  (sh -n, bash --posix -n)
OK   init-verity-fragile.sh  (sh -n, bash --posix -n)
OK   tpm2-seal.sh  (sh -n, bash --posix -n)
OK   fscrypt_unlock.c  (Linux client, optee_client 4.11.0 libteec headers, clang 21.1.0, aarch64)
```

### 2.6 TPM2 sealing that survives updates and A/B

The PCR arithmetic, with U-Boot v2026.10's real measurement order:

```python
# pcr_model.py - U-Boot (non-EFI) measured boot as PCR arithmetic: precompute, seal, replay, and the traps
"""U-Boot v2026.10 boot/bootm.c with CONFIG_MEASURED_BOOT measures, in order:
     PCR 8  <- kernel image                       (EV_COMPACT_HASH "linux")
     PCR 9  <- initrd                             (EV_COMPACT_HASH "initrd")
     PCR 1  <- device tree  (if MEASURE_DEVICETREE, EV_TABLE_OF_DEVICES)
     PCR 1  <- bootargs string incl. its NUL      (EV_PLATFORM_CONFIG_FLAGS)
   extend(PCR, data) := PCR = SHA256(PCR || SHA256(data)), PCRs start at 32 zero bytes.
   Ordering (bootm_run_states): FINDOTHER -> MEASURE -> LOADOS -> RAMDISK -> FDT -> OS_PREP. So the DTB is
   measured as LOADED, before OS_PREP fixups (kaslr-seed injection, FIT-verity's dm-mod.create append):
   PCR1 reflects the environment's bootargs and the DTB from the FIT, not what Linux finally receives.
"""
import hashlib


def sha(b: bytes) -> bytes:
    return hashlib.sha256(b).digest()


def boot(kernel: bytes, initrd: bytes, dtb: bytes, bootargs: str, measure_dtb=True):
    pcr = {1: bytes(32), 8: bytes(32), 9: bytes(32)}
    log = []

    def extend(i, data, ev):
        d = sha(data)
        pcr[i] = sha(pcr[i] + d)
        log.append((i, ev, d))
    extend(8, kernel, "linux")
    extend(9, initrd, "initrd")
    if measure_dtb:
        extend(1, dtb, "dts")
    extend(1, bootargs.encode() + b"\0", "bootargs")
    return pcr, log


def replay(log):
    pcr = {}
    for i, _, d in log:
        pcr[i] = sha(pcr.get(i, bytes(32)) + d)
    return pcr


def policy_ok(sealed: dict, actual: dict, sel) -> bool:
    return all(sealed[i] == actual[i] for i in sel)


def main() -> None:
    fails = 0

    def check(ok, what):
        nonlocal fails
        fails += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {what}")

    kernel, initrd = b"Image v6.18.59-prod" * 1000, b"initramfs roothash=6405e5df" * 100
    dtb_a = b"board.dtb from the FIT, as loaded (no kaslr-seed yet)" + b"\0" * 64
    args = "console=ttyS0 rootwait rauc.slot=A"

    print("[1] Precompute the expected PCRs offline from release artifacts (what we seal to)")
    expected, log = boot(kernel, initrd, dtb_a, args)
    for i in (1, 8, 9):
        print(f"     PCR{i:<2} = {expected[i].hex()}")
    check(replay(log) == expected, "event-log replay reproduces the PCRs")

    print("[2] Sealing policy {1,8,9} vs {8,9} across normal boots of the same release")
    again, _ = boot(kernel, initrd, dtb_a, args)
    check(policy_ok(expected, again, (1, 8, 9)),
          "reboot, same slot: PCR1 is stable (kaslr-seed is injected at OS_PREP, after MEASURE)")
    slot_b, _ = boot(kernel, initrd, dtb_a, args.replace("slot=A", "slot=B"))
    check(not policy_ok(expected, slot_b, (1, 8, 9)),
          "A/B fallback to slot B: bootargs differ -> PCR1 differs -> a {1,8,9} seal fails exactly when you need it")
    check(policy_ok(expected, slot_b, (8, 9)), "PCR8+PCR9 policy still unseals on slot B (same release)")
    dtb_fw = dtb_a.replace(b"(no kaslr-seed yet)", b"MAC 02:5e:7a:11:9c:04")
    fw_dtb, _ = boot(kernel, initrd, dtb_fw, args)
    check(not policy_ok(expected, fw_dtb, (1,)),
          "a DTB patched BEFORE measurement (e.g. by an earlier firmware stage) moves PCR1 too")

    print("[3] What the policy is supposed to catch")
    evil, _ = boot(kernel + b"\x90", initrd, dtb_a, args)
    check(not policy_ok(expected, evil, (8, 9)), "a modified kernel changes PCR8: unseal refused")
    shell, _ = boot(kernel, initrd, dtb_a, args + " init=/bin/sh")
    check(not policy_ok(expected, shell, (1,)) and policy_ok(expected, shell, (8, 9)),
          "init=/bin/sh only changes PCR1: a {8,9} policy does NOT see a bootargs attack")

    print("[4] A forged event log cannot match the TPM's PCRs")
    forged = [(i, ev, sha(b"what the attacker claims") if i == 8 else d) for i, ev, d in log]
    check(replay(forged)[8] != expected[8], "replayed forged log disagrees with the quoted PCR8")

    print("[5] An OTA update without re-sealing")
    upd, _ = boot(b"Image v6.18.60-prod" * 1000, initrd, dtb_a, args)
    check(not policy_ok(expected, upd, (8, 9)),
          "new kernel = new PCR8: the secret is unreachable unless re-sealed (or PolicyAuthorize is used)")
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
[1] Precompute the expected PCRs offline from release artifacts (what we seal to)
     PCR1  = 6e5a368456447c0b9ca571dd8df4988a313da43f24e2b941f8f39d2f782b98db
     PCR8  = 61258eb35a50a28c58c785f60cfb7fdd59740f09e12b959f9efb4e4e7f44dacd
     PCR9  = 1a04552eb1d2b3b64de859a73e4f20fd3a89ccc68c008a0bf53e8c451292558f
  ok   event-log replay reproduces the PCRs
[2] Sealing policy {1,8,9} vs {8,9} across normal boots of the same release
  ok   reboot, same slot: PCR1 is stable (kaslr-seed is injected at OS_PREP, after MEASURE)
  ok   A/B fallback to slot B: bootargs differ -> PCR1 differs -> a {1,8,9} seal fails exactly when you need it
  ok   PCR8+PCR9 policy still unseals on slot B (same release)
  ok   a DTB patched BEFORE measurement (e.g. by an earlier firmware stage) moves PCR1 too
[3] What the policy is supposed to catch
  ok   a modified kernel changes PCR8: unseal refused
  ok   init=/bin/sh only changes PCR1: a {8,9} policy does NOT see a bootargs attack
[4] A forged event log cannot match the TPM's PCRs
  ok   replayed forged log disagrees with the quoted PCR8
[5] An OTA update without re-sealing
  ok   new kernel = new PCR8: the secret is unreachable unless re-sealed (or PolicyAuthorize is used)
ALL PASSED: 0 failure(s)
```

#### The Fragile Way

- **Seal to PCRs read live from the TPM at seal time** (`tpm2_pcrread` → `tpm2_createpolicy`). If the device is already compromised when you seal, you seal the secret to the compromised state.
- **Include PCR1 when bootargs carry the A/B slot.** Scenario [2]: the secret becomes unreachable exactly when the device falls back to the other slot.
- **Seal with a password** (`userwithauth`) stored next to the blob.

#### The Silicon-Hardened Production Way

```bash
#!/bin/sh
# tpm2-seal.sh - seal a secret to precomputed PCR 8+9 (kernel+initrd) values; unseal at boot (tpm2-tools 5.x)
#   seal:   PCR_FILE=expected-pcrs.bin ./tpm2-seal.sh seal < secret.bin   (on the device, during OTA install)
#   unseal: ./tpm2-seal.sh unseal > secret.bin                              (initramfs, after measured boot)
set -eu

PCRS="sha256:8,9"
HANDLE=0x81010001          # persistent handle, owner range 0x81000000-0x817FFFFF
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

case "${1:-}" in
seal)
	# The expected PCR8||PCR9 digests (64 bytes) are computed from the NEW release's kernel and initrd
	# (pcr_model.py logic, or a signed manifest), never read back from the TPM at seal time: reading
	# the live PCRs would let a compromised boot seal the secret to itself.
	: "${PCR_FILE:?expected PCR8||PCR9 sha256 values, 64 bytes}"
	tpm2_createprimary -C o -g sha256 -G ecc -c "$WORK/primary.ctx"
	tpm2_createpolicy --policy-pcr -l "$PCRS" -f "$PCR_FILE" -L "$WORK/pcr.policy"
	# No userwithauth: only the PCR policy can authorize unsealing (no password path).
	tpm2_create -C "$WORK/primary.ctx" -L "$WORK/pcr.policy" -a "fixedtpm|fixedparent" \
		-i - -u "$WORK/seal.pub" -r "$WORK/seal.priv"
	tpm2_load -C "$WORK/primary.ctx" -u "$WORK/seal.pub" -r "$WORK/seal.priv" -c "$WORK/seal.ctx"
	tpm2_evictcontrol -C o -c "$HANDLE" 2>/dev/null || true      # drop the previous release's object
	tpm2_evictcontrol -C o -c "$WORK/seal.ctx" "$HANDLE"
	;;
unseal)
	# Satisfies the policy with the current PCRs; fails closed if the kernel or initrd differ.
	tpm2_unseal -c "$HANDLE" -p "pcr:$PCRS"
	;;
*)
	echo "usage: $0 seal|unseal" >&2
	exit 2
	;;
esac
```

- **Compute the expected PCR8/PCR9 values from the new release's artifacts** (or ship them in the signed update manifest) and seal to those, during OTA install, before reboot.
- **No `userwithauth`:** only the policy can unseal.
- **Lock bootargs instead of measuring them.** Scenario [3] shows `init=/bin/sh` moves only PCR1, so a {8,9} policy is safe only when bootargs can't be changed: `ENV_WRITEABLE_LIST` excludes `bootargs`, or bootargs come from the signed DTB.
- **For fleets with frequent updates, use an authorized policy** (`PolicyAuthorize`): seal once to "any PCR values signed by the release key", and ship a signed policy with each release instead of re-sealing. ⚠ tpm2-tools 5.x supports this (`tpm2_policyauthorize`); design and test it before relying on it.

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

### 3.1 Failure modes

| Symptom | Cause | Recovery / prevention |
|---|---|---|
| `Verifying Hash Integrity ... Bad Data Hash`, or `error! … for 'hash-1' hash node in 'kernel-1' image node` | Image corrupted in storage or transfer; FIT built from different inputs than signed | Fall back to the other slot (bootcount); verify with `fit_check_sign` offline; compare `SHA256SUMS` |
| Unsigned or old FIT boots fine | Key not marked `required` (`-r` missing), or legacy image format enabled | §2.3 assertion in the release pipeline; `LEGACY_IMAGE_FORMAT` denied |
| Option "enabled" in the defconfig has no effect | Symbol doesn't exist (typo, renamed between versions) | `kconfig_check.py` in CI against the exact U-Boot tree |
| `device-mapper: verity: …: data block N is corrupted`, then a reboot | Storage bit-rot, a bad OTA write, or tampering | `restart_on_corruption` + A/B fallback; FEC for bit-rot; report corrupted block numbers to fleet telemetry |
| Verity device fails to open after an update | Root hash in the new initramfs doesn't match the new rootfs (build race, wrong artifact pairing) | Build the rootfs, then the verity tree, then the initramfs with that hash, then the FIT, in one pipeline step; test boot every release |
| `/var` unreadable after a firmware update | fscrypt master key derivation changed (TA label, HUK derivation, OP-TEE config) | Freeze derivation inputs; add key-derivation versioning and a migration path |
| TPM unseal fails on 100% of devices after an OTA | Sealed to old PCR8/9, not re-sealed before reboot | Re-seal during install (expected values from the new artifacts), keeping the old object until the new boot is confirmed |
| TPM unseal fails only after A/B fallback | PCR1 in the policy, with slot-specific bootargs | Drop PCR1 and lock bootargs, or seal per slot / use PolicyOR |

### 3.2 Debugging without a shell

The production U-Boot has no interactive shell, and the root is read-only. Plan the instrumentation in:
- **Offline FIT verification:** `fit_check_sign -f image.itb -k u-boot.dtb -c conf-1` on a host reproduces U-Boot's decision.
- **Offline verity:** `veritysetup verify` against a raw image copied off the device (or `verity_tree.py` logic) locates bad blocks without booting.
- **Measurements:** `tpm2_pcrread sha256:1,8,9` and the event log (`tpm2_eventlog`, from the kernel's binary measurement log where exposed) let you replay what was measured and find which PCR diverged, the way scenario [4] does.
- **Panics that reboot** (`panic_on_corruption`, `restart_on_corruption`) must leave evidence. Configure **pstore/ramoops** (Folder 04) so the verity error survives the reboot, and report it on next boot.
- **Keep a signed recovery FIT** (a minimal kernel and initramfs) that can boot from the other slot or from a recovery partition, under the same keys and policy.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · Image vs configuration signatures

**Initial Prompt:** "Our FIT has a signature on the kernel and one on the DTB. Is that enough?"

**L5 Answer:** "Yes, both images are signed, so U-Boot won't load a modified kernel or DTB."

**Why L5 Bricks Devices at Scale:** Each image is valid on its own, so an attacker who keeps old signed artifacts can boot **a combination you never shipped**, for example the current kernel with an old DTB that leaves a secure peripheral mapped to the normal world, or an old initramfs with a known vulnerability. Every release you've ever signed becomes a parts bin. Without `-r`, a FIT with no signature boots anyway.

**L7 Principal Defense:**
- **Sign configurations, not images.** The signature then covers the root, the configuration, and each referenced image node and its hash, so only the shipped combination verifies.
- **One configuration per FIT**, with no "legacy" configuration.
- **Enroll the key with `-r`** so unsigned FITs are refused, and disable the legacy image format.
- **Enforce it in CI** (`fit_policy.py`).
- **Know the code's history:** 2021 and 2026 parser fixes. Pin a U-Boot release that contains them, because the parser is attack surface before signature checking even begins.

### Chain 2 · "U-Boot verified the kernel. Why dm-verity?"

**Initial Prompt:** "U-Boot already verifies the kernel and initramfs. What does dm-verity add, and when exactly does it check data?"

**L5 Answer:** "It checks the root filesystem on every page fault, so modifications are detected at runtime."

**Why L5 Bricks Devices at Scale:** The mechanism is slightly wrong in a way that affects designs:
- verification happens on **first read into the page cache**, and cached pages are not re-verified;
- `check_at_most_once` skips even device re-reads.

Teams that believe "every page fault" skip runtime protections they actually need (read-only mappings, controlling who can write `/dev/mem` or load modules). Others put mutable data on the verity device and brick the update flow.

**L7 Principal Defense:**
- **What U-Boot covers:** the kernel, DTB and initramfs, which are loaded and hashed once.
- **What dm-verity covers:** the multi-gigabyte root filesystem, lazily, block by block, against a Merkle root. That root's integrity comes from the same signature chain.
- **When it checks:** on device reads into the page cache, validated per block up to the root. The default is `-EIO`; production uses `restart_on_corruption` with A/B fallback (or panic), with corrupted block numbers reported to telemetry.
- **What it doesn't cover:** pages already in RAM, and writable state, which is fscrypt's job.
- **The tree format matters to the build** (top level first, salt-first hashing in v1), and the implementation is checked against cryptsetup's vectors.

### Chain 3 · Where the root hash lives

**Initial Prompt:** "Where does the dm-verity root hash come from on our device?"

**L5 Answer:** "We pass it on the kernel command line as `roothash=…` from U-Boot."

**Why L5 Bricks Devices at Scale:** The kernel command line comes from U-Boot's environment, which is not signed. Anyone who can change `bootargs` (a writable environment, a serial shell, a modified env partition) supplies the root hash of **their** root filesystem. dm-verity then dutifully verifies the attacker's image. The whole verity chain collapses into "trust the environment".

**L7 Principal Defense:**
- **Put the root hash somewhere the signature covers.** Choose one:
  - files in the signed initramfs;
  - a FIT dm-verity subnode covered by the configuration signature (U-Boot v2026.10, with the caveat that the `fitblk` driver it depends on isn't in mainline);
  - a root-hash PKCS#7 signature verified by the kernel's keyring.
- **Separately, lock the environment** (`ENV_WRITEABLE_LIST`) so `bootargs` can't be changed at all.
- **Never fall back** to an unverified root.
- **Build the pipeline so the rootfs, verity tree, initramfs and FIT are produced together** and test-booted every release.

### Chain 4 · Encrypting `/var`

**Initial Prompt:** "Design encryption for the device's writable partition."

**L5 Answer:** "Use dm-crypt or fscrypt with a key stored in the initramfs, so the device can unlock automatically at boot."

**Why L5 Bricks Devices at Scale:** A key in the initramfs is in the FIT, which is in every firmware download and on every unit's flash. It's one key for the whole fleet, readable by anyone. The common "improvement", a CAAM trusted key, is equally fleet-wide **on any part that was never closed**, because CAAM then uses a fixed test key.

**L7 Principal Defense:**
- **Bind the key to the SoC:** derive the fscrypt master key in the TEE from the HUK (01.3), or use hardware-wrapped keys with the inline crypto engine. Never store it.
- **Use a v2 policy:** AES-256-XTS / AES-256-HCTR2, with HKDF per-file keys. Treat a policy mismatch as fatal.
- **One-shot derivation** at early boot, then the TA locks it.
- **Version the key derivation** so firmware updates can't silently change keys.
- **If using kernel trusted keys:** TEE or TPM sources, and CAAM only on closed HAB parts.
- **Plan the field-repair and data-wipe flows** (01.3 Chain 6).

### Chain 5 · Sealing that survives OTA and A/B

**Initial Prompt:** "We want a cloud credential that's only usable when the device booted our firmware. Design the TPM sealing."

**L5 Answer:** "Seal the credential to PCRs 1, 8 and 9 using the current PCR values, so any change in kernel, initramfs, DTB or bootargs locks it."

**Why L5 Bricks Devices at Scale:** It fails in three ways:
- **Sealing to current values seals to whatever booted**, including a compromised boot.
- **PCR1 includes slot-specific bootargs**, so the credential vanishes exactly when the device falls back to the other slot.
- **Every OTA changes PCR8/9.** Unless the new values are sealed before reboot, the first update locks every device out of the cloud at once.

**L7 Principal Defense:**
- **Seal to expected values** computed from the release artifacts, or shipped in a signed manifest.
- **Pick PCRs deliberately:** kernel and initrd (8, 9).
- **Remove the need to measure bootargs** by locking them.
- **Re-seal during install, before reboot,** and keep the old object until the new boot is confirmed. Or use **PolicyAuthorize**, so a release-signed policy authorizes new PCR values without re-sealing.
- **Attest with quote plus event log,** and replay on the server (a forged log can't match the quote, scenario [4]).
- **Test A/B fallback and OTA** with sealed secrets in the release suite.

### Chain 6 · 3% of devices lose their data after an update

**Initial Prompt:** "After last week's OTA, about 3% of devices can't read `/var` and can't reach the cloud. The rest are fine. Debug it."

**L5 Answer:** "Probably corrupted downloads. Push the update again to those devices."

**Why L5 Bricks Devices at Scale:** Re-pushing changes nothing if the failure is deterministic for that subset. A clean 3% split points at a **variable in the key or seal path**, not at the payload. Re-flashing may also erase the evidence (the old sealed object, the event log) needed to recover the data.

**L7 Principal Defense:**
1. **Correlate the 3%** with hardware revision, slot, update path (fresh install vs fallback), and boot count.
2. **Suspect, in order:**
   - devices that **fell back to the other slot** after the update, sealed with a PCR1 policy (slot bootargs);
   - devices that **rebooted before the re-seal step completed**, the ordering bug;
   - devices on a **hardware revision whose DTB differs** (PCR1);
   - a **key-derivation input** that changed only on some configurations (TA label, OP-TEE config).
3. **Read the evidence:** `tpm2_pcrread` and the event log against the expected values, and fscrypt key-add errors.
4. **Recover** if the old sealed object or slot still exists (boot it and re-seal correctly); otherwise use the designed re-enrolment flow.
5. **Fix the process:** seal-before-reboot as a transactional step, PCR selection reviewed against A/B, and release tests that exercise fallback.

---

## 5. Invariants Checklist

- [ ] FIT: one configuration, configuration-signed (PSS or ECDSA, SHA-256+), every image hashed, `sign-images` complete; key enrolled `required`; legacy images off; `FIT_FULL_CHECK` on; U-Boot version includes the 2021 and 2026 FIT parser fixes.
- [ ] SPL verifies U-Boot proper (`SPL_FIT_SIGNATURE`); no autoboot interrupt; no memory, FDT or setexpr commands; environment writable only for flagged A/B variables.
- [ ] Every defconfig fragment passes a symbol-existence check against the exact source tree.
- [ ] dm-verity root hash comes only from a signed artifact; no unverified fallback; corruption policy restart or panic, plus A/B and pstore evidence.
- [ ] fscrypt v2 with a TEE-derived (or hardware-wrapped) key; policy mismatch is fatal; derivation inputs versioned; no CAAM trusted keys on open parts.
- [ ] TPM: sealed to expected (not live) PCR values; PCR set reviewed against A/B; re-seal before reboot or PolicyAuthorize; attestation replays the event log.
- [ ] Release pipeline: build rootfs → verity → initramfs → FIT → sign (HSM) → `fit_check_sign` → test boot, in one job, with recorded digests.

## 6. References

- U-Boot v2026.10: `doc/usage/fit/signature.rst`, `doc/usage/fit/dm-verity.rst`, `boot/bootm.c`, `boot/image-fit.c`, `env/Kconfig`. <https://github.com/u-boot/u-boot/tree/v2026.10>
- Linux v7.2: `Documentation/admin-guide/device-mapper/verity.rst`, `drivers/md/dm-verity-target.c`, `Documentation/filesystems/fscrypt.rst`, `Documentation/security/keys/trusted-encrypted.rst`. <https://github.com/torvalds/linux/tree/v7.2>
- cryptsetup, `tests/verity-compat-test` (the root-hash vectors used in §2.4) and `man/veritysetup.8.adoc`. <https://gitlab.com/cryptsetup/cryptsetup>
- NVD, CVE-2021-27138 (U-Boot FIT unit-address handling). <https://nvd.nist.gov/vuln/detail/CVE-2021-27138>
- Security Affairs, "Critical U-Boot Bugs Undermine Secure Boot on Millions of Devices" (Binarly BRLY-2026-037 to 042), July 2026. <https://securityaffairs.com/195150/security/critical-u-boot-bugs-undermine-secure-boot-on-millions-of-devices.html>
- tpm2-tools (tpm2_createpolicy, tpm2_create, tpm2_unseal, tpm2_policyauthorize). <https://github.com/tpm2-software/tpm2-tools>
- Trusted Computing Group, *TCG PC Client Platform Firmware Profile* (PCR usage and event types). <https://trustedcomputinggroup.org/resource/pc-client-specific-platform-firmware-profile-specification/>
- In this KB: [01.1 Chain of trust](01-bootrom-efuse-otp-puf-and-cryptographic-chain-of-trust.md) · [01.2 TF-A](02-arm-trusted-firmware-tfa-bl1-bl2-bl31-exception-levels-el3-to-el0.md) · [01.3 OP-TEE (vault TA used here)](03-optee-os-trustzone-tzasc-tzma-smc-world-switch-and-rpmb-storage.md) · Folder 03 for A/B, bootcount and OTA sealing order.
