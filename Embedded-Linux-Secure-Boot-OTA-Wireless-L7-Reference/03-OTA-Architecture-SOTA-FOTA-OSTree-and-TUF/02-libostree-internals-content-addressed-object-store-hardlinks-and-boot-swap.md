# 03.2 · libostree Internals: the Content-Addressed Object Store, Hardlink Deployments and the Boot Swap

> **Folder 03 · File 2 of 4.** OSTree ("git for operating system binaries") replaces two fixed slots with a **content-addressed object store** and **deployments** that are hardlink farms into it.
> - **Storage:** an update costs only the files that changed.
> - **Rollback:** the previous deployment is still there, byte for byte.
> - **The switch:** one atomic `rename()` of a symlink in `/boot`.
>
> It brings its own failure modes:
> - an `/etc` merge that silently keeps stale configuration;
> - integrity that depends on composefs being **signed**, not merely enabled;
> - a device-side configuration where one boolean decides whether signature keys are mandatory.
>
> **Pinned.** libostree **v2026.5**: `src/libostree/ostree-core.{c,h}`, `ostree-mutable-tree.c`, `ostree-sysroot-deploy.c`, `ostree-sysroot-upgrader.c`, `man/ostree-prepare-root.xml`, `man/ostree.repo-config.xml`.
>
> **Verification.**
> - `ostree_model.py` implements GVariant normal-form serialization for OSTree's object formats. It reproduces libostree's own empty-tree checksum constant, and models deployments, the `/etc` three-way merge and the boot swap. The boot swap is checked against every crash point and every subset of unsynced writes.
> - `ostree_cfg_check.py` reads its option tables from this version's man pages.
> - Other object checksums follow the same serialization rules, but weren't cross-checked against a running `ostree` binary ⚠.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 The object store

```text
 /ostree/repo/objects/<first 2 hex>/<remaining 62 hex>.<type>      (_ostree_get_relative_object_path)
   type (ostree-core.h)        content                                       checksum (SHA-256) over
   .file        (1)            the file's bytes ("bare" mode)                be32(len(hdr)) ‖ 0x00000000 ‖ hdr ‖ content
                                                                              hdr = GVariant (uuuusa(ayay)):
                                                                              uid, gid, mode (big-endian), rdev 0, symlink target, xattrs
   .dirtree     (2)            GVariant (a(say)a(sayay)): files (name, file csum), dirs (name, dirtree csum, dirmeta csum)
   .dirmeta     (3)            GVariant (uuua(ayay)): uid, gid, mode, xattrs
   .commit      (4)            GVariant (a{sv}aya(say)sstayay): metadata, parent, related, subject, body,
                               timestamp (big-endian u64), root dirtree csum, root dirmeta csum
   .commitmeta  (6)            detached metadata: where Ed25519 / GPG signatures live
```

- **Every object is named by the hash of its canonical serialization.** A commit therefore names its whole tree, transitively, like a Merkle tree.
- **Proof of the encoding.** The empty directory tree serializes to a single framing-offset byte (`0x00`), and libostree hard-codes its checksum as `empty_tree_csum = "6e340b9c…"` (`ostree-mutable-tree.c`). §2.1's serializer reproduces it.

**Repository modes** (`ostree.repo-config(5)` `mode`):

| Mode | Use |
|---|---|
| `bare` | The device: objects are real files with real ownership, so deployments can hardlink them |
| `bare-user` | Unprivileged builds |
| `bare-user-only` | Unprivileged builds |
| `archive` | Servers: zlib-compressed `.filez`, served over HTTP |

### 1.2 Deployments and the boot swap

```text
 /ostree/deploy/<stateroot>/deploy/<commit>.<serial>/     a checkout: every regular file is a HARDLINK to its .file object
       usr/  (read-only)   etc/ (merged, writable)   var -> /ostree/deploy/<stateroot>/var (shared, never versioned)
 /boot/loader -> loader.0          (current bootversion)
 /boot/loader.0/entries/ostree-1-<os>.conf, ostree-2-<os>.conf   BLS entries for EVERY deployment of this version
 /boot/ostree/<os>-<bootcsum>/vmlinuz, initramfs                 kernels, by content checksum

 write_deployments_bootswap() (ostree-sysroot-deploy.c), for new bootversion N = 1 - current:
   1. install_deployment_kernel()      kernels + BLS entries into /boot/loader.N/entries
   2. swap_bootlinks()                 /ostree/boot.N.M links
   3. _ostree_bootloader_write_config() bootloader-specific config, if any
   4. prepare_new_bootloader_link()    symlink /boot/loader.tmp -> loader.N
   5. full_system_sync()               syncfs(): everything above durable
   6. swap_bootloader()                renameat(loader.tmp, loader); fsfreeze/thaw cycle
```

The previous `loader.(1-N)` and its entries are never modified during the swap. At any instant `/boot/loader` names one complete set of entries. §2.1 checks this against every crash point and every subset of unsynced writes. It also shows that rewriting entries in place, with no barrier, admits unbootable states.

Note the code's own constraint: `g_assert (!sysroot->boot_is_vfat)`. Symlink swapping needs a POSIX `/boot`. With a U-Boot that reads from vfat, OSTree uses its bootloader-specific config writer instead, and its atomicity is that writer's.

### 1.3 `/etc`: a three-way merge

`merge_configuration_from()` computes `ostree_diff_dirs(orig = old deployment's /usr/etc, modified = old deployment's /etc)`, then applies the result to the new deployment's `/etc`, which starts as its `/usr/etc`:

| In the old deployment | In the new `/etc` |
|---|---|
| File removed locally | Removed |
| File added locally | Copied over |
| File modified locally | **The local copy wins**, even if the new release changed the default |
| File untouched | The new default |

The last-but-one row is the trap. A product that edits a vendor config file in place never receives that file's future defaults, including security-relevant ones. §2.1 shows a `secure=1` default that never lands. Keep the product's configuration in drop-in directories (`/etc/<thing>.d/`) or in `/usr`, and never edit shipped files.

### 1.4 Integrity: composefs, signed

- **Hardlink deployments are only as trustworthy as the files' bytes.** Anything with write access to `/sysroot` can modify an object, and every deployment sharing it.
- **composefs + fs-verity** (`ostree-prepare-root`, `composefs.enabled`) closes that:
  - `signed` / `verity`: "before the content of a file is read, the integrity of its backing OSTree object is validated by the digest stored in the image";
  - `signed`: "boot will fail if the image cannot be validated by a public key" (Ed25519 keys at `composefs.keypath`, default `/etc/ostree/initramfs-root-binding.key`, **in the initramfs**).
  - `maybe` "causes unpredictable and confusing semantics and is not recommended".
- **The kernel command line overrides the file.** `ostree.prepare-root.composefs=0` disables composefs. That is why the command line must not be writable: 03.1's `ENV_WRITEABLE_LIST` ensures it. The initramfs and its key must also be inside the signed FIT (01.4).

### 1.5 Pull-side trust

- **Commit signatures** (`ostree.repo-config(5)`):
  - `sign-verify=ed25519` names the engine, which makes keys **mandatory**;
  - `sign-verify=true` enables engines with keys **optional**, falling back to system-wide key storage;
  - `gpg-verify` defaults to **true**, so an Ed25519-only remote must set it to false or every pull fails.
- **The summary** (the ref → commit map) is verified only with `sign-verify-summary`.
- **Downgrade protection.** `ostree_sysroot_upgrader_check_timestamps()` refuses a commit older than the current one, unless `ALLOW_OLDER`.
- **No freeze protection.** Nothing in OSTree stops a server, or a man in the middle, from simply withholding new commits forever. That is TUF's timestamp role (03.3).

---

## 2. Production Code & Configuration Blueprints

### 2.1 The model

```python
# ostree_model.py - libostree's object model, hardlink deployments, /etc merge and the atomic boot swap
"""Usage: python ostree_model.py

Mirrors libostree v2026.5:
  ostree-core.h       object types; OSTREE_TREE_GVARIANT_STRING "(a(say)a(sayay))",
                      OSTREE_DIRMETA_GVARIANT_STRING "(uuua(ayay))",
                      OSTREE_COMMIT_GVARIANT_STRING "(a{sv}aya(say)sstayay)", file header "(uuuusa(ayay))"
  ostree-core.c       objects/<2 hex>/<62 hex>.<type>; file checksum = sha256(be32 size, 4 NULs, header
                      GVariant, content); uid/gid/mode/timestamp byte-swapped to big-endian before packing
  ostree-mutable-tree.c  empty_tree_csum = 6e340b9c... (the empty dirtree): validates the serializer below
  ostree-sysroot-deploy.c  merge_configuration_from() and write_deployments_bootswap():
                      install kernels + BLS entries into boot/loader.<new> -> symlink loader.tmp ->
                      loader.<new> -> full_system_sync() -> renameat(loader.tmp, loader)
"""
import hashlib
import itertools
import struct

EMPTY_TREE_CSUM = "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d"


# ---------------- GVariant normal form (the subset OSTree's objects use) ----------------
def parse(t, i=0):
    """Type string -> nested ('kind', children) and next index."""
    c = t[i]
    if c in "yuts":
        return (c, None), i + 1
    if c == "a":
        if t[i + 1] == "{":                     # a{sv}: only the empty commit metadata is modelled
            return ("a{sv}", None), t.index("}", i) + 1
        elem, j = parse(t, i + 1)
        return ("a", elem), j
    if c == "(":
        members, j = [], i + 1
        while t[j] != ")":
            m, j = parse(t, j)
            members.append(m)
        return ("(", members), j + 1
    raise ValueError(t)


def align(ty):
    k, ch = ty
    return {"y": 1, "s": 1, "u": 4, "t": 8, "a{sv}": 8}.get(k) or (
        align(ch) if k == "a" else max([align(m) for m in ch] or [1]))


def fixed(ty):
    k, ch = ty
    return k in "yut" or (k == "(" and all(fixed(m) for m in ch))


def offset_size(body, n):
    for w in (1, 2, 4, 8):
        if body + n * w < 1 << (8 * w):
            return w


def pad(buf, a):
    return buf + b"\0" * (-len(buf) % a)


def ser(ty, v):
    k, ch = ty
    if k == "y":
        return bytes([v])
    if k == "u":
        return struct.pack(">I", v)             # OSTree passes GUINT32_TO_BE(x): stored big-endian
    if k == "t":
        return struct.pack(">Q", v)
    if k == "s":
        return v.encode() + b"\0"
    if k == "a{sv}":
        assert not v
        return b""
    if k == "a":
        if ch == ("y", None):
            return bytes(v)
        out, ends = b"", []
        for e in v:
            out = pad(out, align(ch)) + ser(ch, e)
            ends.append(len(out))
        if fixed(ch) or not v:
            return out
        w = offset_size(len(out), len(ends))
        return out + b"".join(x.to_bytes(w, "little") for x in ends)
    out, ends = b"", []
    for i, (m, val) in enumerate(zip(ch, v)):
        out = pad(out, align(m)) + ser(m, val)
        if not fixed(m) and i != len(ch) - 1:
            ends.append(len(out))
    if fixed(ty):
        return pad(out, align(ty))
    w = offset_size(len(out), len(ends)) if ends else 1
    return out + b"".join(x.to_bytes(w, "little") for x in reversed(ends))


GV = lambda t: parse(t)[0]
FILE_HEADER, DIRMETA, TREE, COMMIT = GV("(uuuusa(ayay))"), GV("(uuua(ayay))"), GV("(a(say)a(sayay))"), \
    GV("(a{sv}aya(say)sstayay)")


# ---------------- the repository: content-addressed objects ----------------
class Repo:
    def __init__(self):
        self.objects = {}                       # relative path -> serialized bytes

    def put(self, data, kind):
        csum = hashlib.sha256(data).hexdigest()
        self.objects[f"objects/{csum[:2]}/{csum[2:]}.{kind}"] = data
        return csum

    def file(self, content, mode=0o100644, uid=0, gid=0):
        header = ser(FILE_HEADER, (uid, gid, mode, 0, "", []))
        prefixed = struct.pack(">I", len(header)) + b"\0" * 4 + header
        csum = hashlib.sha256(prefixed + content).hexdigest()
        self.objects[f"objects/{csum[:2]}/{csum[2:]}.file"] = content
        return csum

    def tree(self, entries, mode=0o40755):
        """entries: name -> bytes (a file) or dict (a subdirectory). Returns (dirtree, dirmeta)."""
        files, dirs = [], []
        for name in sorted(entries):
            v = entries[name]
            if isinstance(v, dict):
                t, m = self.tree(v)
                dirs.append((name, bytes.fromhex(t), bytes.fromhex(m)))
            else:
                files.append((name, bytes.fromhex(self.file(v))))
        meta = self.put(ser(DIRMETA, (0, 0, mode, [])), "dirmeta")
        return self.put(ser(TREE, (files, dirs)), "dirtree"), meta

    def commit(self, root, subject, timestamp, parent=None):
        t, m = self.tree(root)
        body = (dict(), bytes.fromhex(parent) if parent else b"", [], subject, "", timestamp,
                bytes.fromhex(t), bytes.fromhex(m))
        return self.put(ser(COMMIT, body), "commit")


def flatten(tree, prefix=""):
    out = {}
    for name, v in tree.items():
        path = f"{prefix}/{name}"
        out.update(flatten(v, path) if isinstance(v, dict) else {path: v})
    return out


# ---------------- deployments: hardlink checkouts and the /etc three-way merge ----------------
def deployment_inodes(repo, tree):
    """A bare-repo checkout hardlinks each file to its object: inode identity = file checksum."""
    return {path: repo.file(content) for path, content in flatten(tree).items()}


def merge_etc(old_usr_etc, old_etc, new_usr_etc):
    """merge_configuration_from(): diff(old /usr/etc -> old /etc) applied on top of the new defaults."""
    new_etc = dict(new_usr_etc)
    for path in old_usr_etc.keys() - old_etc.keys():           # removed locally: removed in new /etc
        new_etc.pop(path, None)
    for path, content in old_etc.items():                       # modified or added locally: copied over
        if old_usr_etc.get(path) != content:
            new_etc[path] = content
    return new_etc


# ---------------- the boot swap under power loss ----------------
# Each op: ("write", path, data) | ("symlink", path, target) | ("rename", src, dst) | ("sync",)
def bootswap_ops(new_ver, entries):
    ops = [("write", f"loader.{new_ver}/entries/{n}", d) for n, d in entries.items()]
    ops += [("symlink", "loader.tmp", f"loader.{new_ver}"), ("sync",), ("rename", "loader.tmp", "loader"),
            ("sync",)]
    return ops


def inplace_ops(entries):
    """The fragile way: rewrite the active entries where they are, no versioned directory, no barrier."""
    return [("write", f"loader.0/entries/{n}", d) for n, d in entries.items()]


def apply(state, op):
    s = dict(state)
    if op[0] == "write":
        s[op[1]] = op[2]
    elif op[0] == "symlink":
        s[op[1]] = ("->", op[2])
    elif op[0] == "rename":
        s[op[2]] = s.pop(op[1])
    return s


def after_crash(state, ops, cut):
    """Every on-disk state power loss after `cut` ops can leave: everything before the last sync is
    durable; of the unsynced ops, any subset may have reached the disk (data writes may also land
    empty: delayed allocation), each rename/symlink itself atomic."""
    durable, pending = dict(state), []
    for op in ops[:cut]:
        if op[0] == "sync":
            for p in pending:
                durable = apply(durable, p)
            pending = []
        else:
            pending.append(op)
    results = []
    for r in range(len(pending) + 1):
        for subset in itertools.combinations(range(len(pending)), r):
            s = dict(durable)
            for i in sorted(subset):
                s = apply(s, pending[i])
            results.append(s)
            for i in subset:                    # the same subset, with that write's data not yet allocated
                if pending[i][0] == "write":
                    results.append({**s, pending[i][1]: b""})
    return results


def bootable(state, valid_entries):
    link = state.get("loader")
    if not (isinstance(link, tuple) and link[0] == "->"):
        return False
    d = link[1] + "/entries/"
    entries = {k: v for k, v in state.items() if k.startswith(d)}
    return bool(entries) and all(v in valid_entries for v in entries.values())


def main():
    fails = 0

    def check(name, cond, detail=""):
        nonlocal fails
        fails += not cond
        print(f"   {'ok  ' if cond else 'FAIL'} {name}{': ' + detail if detail else ''}")

    print("== GVariant serialization and object checksums")
    repo = Repo()
    empty = hashlib.sha256(ser(TREE, ([], []))).hexdigest()
    check("empty dirtree checksum equals libostree's empty_tree_csum", empty == EMPTY_TREE_CSUM, empty[:16])
    v1 = {"usr": {"bin": {"app": b"app 1.0\n", "busybox": b"BB" * 4096}, "lib": {"libc.so.6": b"LIBC" * 8192},
                  "etc": {"app.conf": b"level=info\n", "hosts": b"127.0.0.1 localhost\n"}}}
    c1 = repo.commit(v1, "release 1", 1793145600)
    v2 = {"usr": {"bin": {"app": b"app 1.1\n", "busybox": b"BB" * 4096}, "lib": {"libc.so.6": b"LIBC" * 8192},
                  "etc": {"app.conf": b"level=info\nsecure=1\n", "hosts": b"127.0.0.1 localhost\n"}}}
    c2 = repo.commit(v2, "release 2", 1793232000, parent=c1)
    path = next(p for p in repo.objects if p.endswith(f"{c2[2:]}.commit"))
    check("objects stored as objects/<2>/<62>.<type>", path == f"objects/{c2[:2]}/{c2[2:]}.commit", path[:30] + "...")
    kinds = sorted({p.rsplit(".", 1)[1] for p in repo.objects})
    print(f"   repo: {len(repo.objects)} objects ({', '.join(kinds)}); commits {c1[:12]}.. and {c2[:12]}..")
    again = Repo().commit(v1, "release 1", 1793145600)
    check("same tree, metadata and timestamp -> same commit checksum (content addressing)", again == c1)

    print("== deployments share every unchanged file (hardlinks to the same object)")
    d1, d2 = deployment_inodes(repo, v1), deployment_inodes(repo, v2)
    shared = sum(1 for p in d1 if d1[p] == d2.get(p))
    size = lambda tree: sum(len(v) for v in flatten(tree).values())
    distinct = {}
    for t in (v1, v2):
        for p, c in flatten(t).items():
            distinct[repo.file(c)] = len(c)
    print(f"   files per deployment: {len(d1)}; shared inodes: {shared}; "
          f"bytes for two deployments: {sum(distinct.values())} (vs {size(v1) + size(v2)} as copies)")
    check("only the two changed files cost space twice", shared == len(d1) - 2)

    print("== /etc three-way merge (old /usr/etc -> old /etc, applied to new /usr/etc)")
    old_usr_etc = {"app.conf": b"level=info\n", "hosts": b"127.0.0.1 localhost\n", "motd": b"hello\n"}
    old_etc = {"app.conf": b"level=debug\n", "hosts": b"127.0.0.1 localhost\n", "wifi.conf": b"ssid=x\n"}
    new_usr_etc = {"app.conf": b"level=info\nsecure=1\n", "hosts": b"127.0.0.1 localhost\n", "motd": b"hi\n"}
    merged = merge_etc(old_usr_etc, old_etc, new_usr_etc)
    check("locally added file survives (wifi.conf)", merged.get("wifi.conf") == b"ssid=x\n")
    check("locally removed file stays removed (motd)", "motd" not in merged)
    check("untouched file takes the new default (hosts)", merged["hosts"] == new_usr_etc["hosts"])
    check("locally modified file KEEPS the local copy: the new 'secure=1' default never lands",
          merged["app.conf"] == b"level=debug\n")

    print("== boot swap: every crash point x every subset of unsynced writes")
    good = {"ostree-2.conf": b"title release 2\nlinux /ostree/acme-2/vmlinuz\n",
            "ostree-1.conf": b"title release 1\nlinux /ostree/acme-1/vmlinuz\n"}
    valid = set(good.values()) | {b"title release 1\nlinux /ostree/acme-1/vmlinuz\n"}
    start = {"loader": ("->", "loader.0"), "loader.0/entries/ostree-1.conf": b"title release 1\nlinux /ostree/acme-1/vmlinuz\n"}
    for name, ops, must in (("libostree order (loader.1, sync, rename)", bootswap_ops(1, good), True),
                            ("in-place rewrite, no barrier", inplace_ops(good), False)):
        states = [s for cut in range(len(ops) + 1) for s in after_crash(start, ops, cut)]
        bad = sum(not bootable(s, valid) for s in states)
        print(f"   {name}: {len(states)} possible on-disk states, {bad} unbootable")
        check(f"{name} is {'always bootable' if must else 'NOT always bootable'}", (bad == 0) == must)
        if must:
            check("after the final sync, loader -> loader.1", apply_all(start, ops)["loader"] == ("->", "loader.1"))
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


def apply_all(state, ops):
    for op in ops:
        state = apply(state, op)
    return state


if __name__ == "__main__":
    main()
```

```text
== GVariant serialization and object checksums
   ok   empty dirtree checksum equals libostree's empty_tree_csum: 6e340b9cffb37a98
   ok   objects stored as objects/<2>/<62>.<type>: objects/12/7d14d3672b440f9f394...
   repo: 19 objects (commit, dirmeta, dirtree, file); commits 67316a8dca51.. and 127d14d3672b..
   ok   same tree, metadata and timestamp -> same commit checksum (content addressing)
== deployments share every unchanged file (hardlinks to the same object)
   files per deployment: 5; shared inodes: 3; bytes for two deployments: 41027 (vs 82007 as copies)
   ok   only the two changed files cost space twice
== /etc three-way merge (old /usr/etc -> old /etc, applied to new /usr/etc)
   ok   locally added file survives (wifi.conf)
   ok   locally removed file stays removed (motd)
   ok   untouched file takes the new default (hosts)
   ok   locally modified file KEEPS the local copy: the new 'secure=1' default never lands
== boot swap: every crash point x every subset of unsynced writes
   libostree order (loader.1, sync, rename): 32 possible on-disk states, 0 unbootable
   ok   libostree order (loader.1, sync, rename) is always bootable
   ok   after the final sync, loader -> loader.1
   in-place rewrite, no barrier: 12 possible on-disk states, 5 unbootable
   ok   in-place rewrite, no barrier is NOT always bootable
ALL PASSED: 0 failure(s)
```

What the model proves:
- **The object encoding.** It is validated against libostree's own constant, and identical inputs give identical commit checksums.
- **Storage cost.** Two deployments differing in two files cost those two files twice and share everything else.
- **The `/etc` merge** follows `merge_configuration_from()`, including the stale-default trap.
- **The boot swap.** libostree's order (versioned directory, sync, rename) leaves 32 possible on-disk states after a crash, all bootable. An in-place rewrite leaves 5 of 12 unbootable.

### 2.2 Device repository configuration

#### The Fragile Way

```ini
# ostree-repo-fragile.config - the device repo config from the proof of concept
[core]
repo_version=1
mode=bare

[remote "acme"]
url=http://updates.acme.example/ostree
gpg-verify=false
sign-verify=true
```

#### The Silicon-Hardened Production Way

```ini
# ostree-repo.config - /ostree/repo/config on the device: bare repo, one remote, Ed25519 signatures mandatory
[core]
repo_version=1
mode=bare
min-free-space-percent=10

[remote "acme"]
url=https://updates.acme.example/ostree
# Named engine: keys become mandatory (a bare "true" falls back to system-wide key storage).
sign-verify=ed25519
verification-ed25519-file=/usr/share/acme/ostree/release.ed25519
sign-verify-summary=ed25519
# Only Ed25519 is used; left at its default (true), GPG would fail every pull for lack of signatures.
gpg-verify=false
```

### 2.3 Root integrity at boot

#### The Fragile Way

```ini
# prepare-root-fragile.conf - copied from a desktop OSTree example
[composefs]
enabled=maybe

[sysroot]
readonly=false
```

#### The Silicon-Hardened Production Way

```ini
# prepare-root.conf - /usr/lib/ostree/prepare-root.conf, carried in the initramfs inside the signed FIT (01.4)
[composefs]
# Every file read is checked against the digest in the image, and the image against a signed commit.
enabled=signed
keypath=/etc/ostree/initramfs-root-binding.key

[sysroot]
readonly=true

[etc]
transient=false
```

The gate, with option names taken from this ostree version's man pages:

```python
# ostree_cfg_check.py - device-side OSTree configuration gate; option names read from the ostree man pages
"""Usage: python ostree_cfg_check.py <ostree-man-dir> repo:<config> prepare-root:<conf> ...

Option tables come from man/ostree.repo-config.xml and man/ostree-prepare-root.xml (the <varname> terms),
so a misspelled or removed option is reported rather than silently ignored. Policy rules:
  O1 unknown option (not in the man page of this ostree version)
  O2 a remote without Ed25519 commit verification as a NAMED engine (sign-verify=ed25519); a boolean
     true makes keys optional and falls back to system-wide key storage
  O3 the summary unsigned (sign-verify-summary unset): refs can be redirected
  O4 plain http, or gpg-verify left at its default while only Ed25519 is used (every pull fails)
  O5 composefs not 'signed' (verity alone proves integrity, not origin; 'maybe' is "not recommended")
  O6 the physical sysroot writable from the running system (sysroot.readonly false)
"""
import pathlib
import re
import sys


def man_options(xml):
    text = pathlib.Path(xml).read_text(encoding="utf-8")
    return set(re.findall(r"<term><varname>([\w.\-<>&;]+)</varname></term>", text))


def parse_ini(path):
    section, out = None, []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            section = m.group(1)
        else:
            k, _, v = line.partition("=")
            out.append((n, section, k.strip(), v.strip()))
    return out


def check(kind, path, repo_opts, root_opts):
    entries, findings = parse_ini(path), []
    if kind == "repo":
        remotes = {}
        for n, sec, k, v in entries:
            known = k in repo_opts or (k.startswith("verification-") and k.endswith(("-key", "-file")))
            if not known:
                findings.append(f"O1 line {n}: '{k}' is not an option in ostree.repo-config(5)")
            if sec and sec.startswith("remote "):
                remotes.setdefault(sec, {})[k] = v
        for sec, r in remotes.items():
            engines = [e.split("=")[0] for e in r.get("sign-verify", "").split(";") if e]
            if not engines or engines in (["true"], ["1"], ["false"], ["0"]):
                findings.append(f"O2 [{sec}]: sign-verify={r.get('sign-verify', '(unset)')}: no mandatory key")
            elif not any(f"verification-{e}-file" in r or f"verification-{e}-key" in r for e in engines):
                findings.append(f"O2 [{sec}]: no verification key configured for {engines}")
            if not r.get("sign-verify-summary"):
                findings.append(f"O3 [{sec}]: summary not verified: refs can be redirected")
            if r.get("url", "").startswith("http://"):
                findings.append(f"O4 [{sec}]: plain http")
            if engines and r.get("gpg-verify", "true") not in ("false", "0"):
                findings.append(f"O4 [{sec}]: gpg-verify defaults to true: pulls fail without GPG signatures")
    else:
        values = {f"{sec}.{k}": v for n, sec, k, v in entries}
        for n, sec, k, v in entries:
            if f"{sec}.{k}" not in root_opts:
                findings.append(f"O1 line {n}: '{sec}.{k}' is not an option in ostree-prepare-root(1)")
        if values.get("composefs.enabled") != "signed":
            findings.append(f"O5 composefs.enabled={values.get('composefs.enabled', '(unset: no)')}, not signed")
        if values.get("sysroot.readonly", "false") != "true":
            findings.append("O6 sysroot.readonly is not true")
    return findings


def main():
    man = pathlib.Path(sys.argv[1])
    repo_opts = man_options(man / "ostree.repo-config.xml")
    root_opts = man_options(man / "ostree-prepare-root.xml")
    total = 0
    for spec in sys.argv[2:]:
        kind, path = spec.split(":", 1)
        found = check(kind, path, repo_opts, root_opts)
        total += len(found)
        print(f"{pathlib.Path(path).name} [{kind}]: {len(found)} finding(s)")
        for f in found:
            print("   ", f)
    print(f"options known: repo-config {len(repo_opts)}, prepare-root {len(root_opts)}")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
```

```text
== hardened
ostree-repo.config [repo]: 0 finding(s)
prepare-root.conf [prepare-root]: 0 finding(s)
options known: repo-config 36, prepare-root 7
exit=0
== fragile
ostree-repo-fragile.config [repo]: 3 finding(s)
    O2 [remote "acme"]: sign-verify=true: no mandatory key
    O3 [remote "acme"]: summary not verified: refs can be redirected
    O4 [remote "acme"]: plain http
prepare-root-fragile.conf [prepare-root]: 2 finding(s)
    O5 composefs.enabled=maybe, not signed
    O6 sysroot.readonly is not true
options known: repo-config 36, prepare-root 7
exit=1
```

### 2.4 Operating it

```bash
ostree admin status                                  # deployments, booted (*), pending (on next boot), rollback
ostree admin upgrade                                 # pull + deploy; timestamp check refuses older commits
ostree admin deploy --stage <commit>                 # stage; finalized at shutdown (ostree-finalize-staged.service)
ostree admin config-diff                             # /etc files that differ from /usr/etc: drift to review
ostree fsck                                          # verify every object's checksum
```

`ostree admin config-diff` should run in fleet health telemetry. Every locally modified file is a file that will never take a new default (§1.3).

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Mechanism | Detect | Fix |
|---|---|---|---|
| Security setting in a new release has no effect on some devices | `/etc` file modified locally, so the three-way merge keeps it | `ostree admin config-diff`; journal `ETC_N_MODIFIED` | Drop-ins, not edits; migrate modified files explicitly in the new release |
| Pull fails: "GPG verification enabled, but no signatures found" | Ed25519-only remote with `gpg-verify` at its default true | Pull error | `gpg-verify=false` with `sign-verify=ed25519` |
| A tampered object propagates to every deployment | Hardlinks share inodes; no composefs / fs-verity | `ostree fsck` mismatch | `composefs.enabled=signed`; `sysroot.readonly=true` |
| Device boots without integrity after a cmdline change | `ostree.prepare-root.composefs=0` on the kernel command line | `/proc/cmdline` | Command line from the signed binary only (03.1) |
| Disk full mid-pull bricks the next boot | Pull fills `/sysroot`, deployment half-written | `min-free-space-percent` violation | `min-free-space-*` set; pull before deploy; prune old commits (`ostree admin cleanup`) |
| Device stays on an old release, no error | Updates withheld (freeze) | Commit timestamp vs fleet | TUF timestamp/expiry over the OSTree ref (03.3) |

**Recovery.**
- **The rollback deployment is the first line.** `ostree admin status` shows it, and the boot menu or a one-shot `bootcount` scheme (03.1) selects it.
- **Below that sits the bootloader and SoC recovery path** from 03.1 and 02.2.

**Post-mortem for an OSTree device:**
1. Record the booted and pending commits (`ostree admin status`).
2. Diff them (`ostree diff <a> <b>`).
3. Check `/etc` drift (`config-diff`) and object integrity (`fsck`).
4. Read `ostree-finalize-staged.service` logs from the shutdown that should have applied the update.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · Why OSTree instead of A/B?

**Initial Prompt:** "We have 4 GB of eMMC, a 1.4 GB root filesystem and monthly releases. Make the case for or against OSTree."

**L5 Answer:** "OSTree is like git for the OS, so updates are smaller and we can roll back. It's better than A/B."

**Why L5 Bricks Devices at Scale:** It sells features without costs. OSTree introduces:
- a writable `/sysroot` that must be protected (composefs, signed);
- an `/etc` merge with sticky local edits;
- dependence on POSIX `/boot` semantics for its atomic swap;
- a repository that grows until pruned.

A team adopting it without those controls ships a system that is easier to tamper with than the A/B design it replaced.

**L7 Principal Defense:**
- **Compare on the real constraints.**
  - Storage: OSTree costs 1× plus the changed files, against 2× for A/B, which matters at 4 GB with growth (03.1 Chain 5).
  - Update size: per-file dedup plus static deltas.
  - Atomicity: OSTree's is rename-based (§2.1); A/B's is boot-count-based.
  - Integrity: dm-verity per slot vs composefs signed per commit.
- **Decide with a prototype of both on the target**, measuring update size, boot time and recovery behavior.
- **If OSTree is chosen**, ship the controls of §2.2–2.3 on day one, gated by `ostree_cfg_check.py`.

### Chain 2 · "Rollback is free"

**Initial Prompt:** "With OSTree, if a release is bad, we just boot the previous deployment. Anything to worry about?"

**L5 Answer:** "No. The old deployment is untouched, so rolling back is always safe."

**Why L5 Bricks Devices at Scale:**
- **`/var` is shared, not versioned.** A new release that migrated a database schema in `/var` leaves the old release unable to read it after rollback.
- **`/etc` was merged forward,** so the rollback deployment sees whatever the new release wrote there.
- **"Untouched" is only true for `/usr`.**

**L7 Principal Defense:**
- **Make state migrations reversible, or two-phase:**
  1. The new release writes data the old one can still read, until the new one is marked good.
  2. Only then does it migrate destructively.
- **Version the on-disk formats in `/var`.**
- **Test rollback as a first-class release step:** upgrade, run, roll back, run.
- **The same applies to A/B systems** with a shared data partition (03.1).

### Chain 3 · Is composefs enough?

**Initial Prompt:** "We enabled composefs with fs-verity. Are we protected against offline tampering of the root filesystem?"

**L5 Answer:** "Yes. fs-verity checks every file against its digest, so modified files are detected."

**Why L5 Bricks Devices at Scale:**
- **`verity` proves the files match the composefs image, not that the image is ours.** An attacker who replaces both the objects and the image, and the commit referencing it, passes verity checks. Only `signed` ties the image to our key.
- **The kernel command line can disable composefs entirely,** and the key file location matters: in the initramfs, inside the signed FIT.

**L7 Principal Defense:**
- **Run the whole chain:**
  - `composefs.enabled=signed` with `keypath` in the initramfs;
  - the initramfs in the signed FIT (01.4);
  - the command line from the signed bootloader, never from writable storage (03.1);
  - `sysroot.readonly=true`.
- **Tie commits to the same release key policy** as the update metadata (03.3), with rotation planned.
- **Test with a tampered object and a tampered image:** both must fail to boot.

### Chain 4 · Pull-side trust

**Initial Prompt:** "Review this device config: `sign-verify=true`, `gpg-verify=false`, `url=http://...`."

**L5 Answer:** "Signatures are verified, so plain HTTP is fine: a man in the middle can't forge commits."

**Why L5 Bricks Devices at Scale:**
- **`sign-verify=true` makes keys optional**, falling back to system-wide key storage. Whether a commit is checked against *our* key depends on what else is installed.
- **The summary isn't verified,** so a man in the middle can redirect refs to older signed commits. The timestamp check stops downgrades past the booted commit, but not freezes.
- **Plain HTTP exposes the fleet's update metadata and versions.**

**L7 Principal Defense:**
- `sign-verify=ed25519` with a pinned `verification-ed25519-file` in `/usr` (covered by composefs signing).
- `sign-verify-summary=ed25519`, HTTPS, and `gpg-verify=false` explicitly.
- **Freeze and rollback protection from TUF metadata** around the ref (03.3).
- **Gate the configuration in CI** (`ostree_cfg_check.py`).

### Chain 5 · Power loss during deployment

**Initial Prompt:** "What happens if power fails while `ostree admin deploy` is writing the new deployment?"

**L5 Answer:** "OSTree is atomic, so nothing bad happens."

**Why L5 Bricks Devices at Scale:** "Atomic" is a property of a specific sequence of operations on a specific kind of filesystem. The L5 can't say which step is the commit point or what makes it durable, so it can't review a port that breaks it:
- `/boot` on vfat;
- a custom bootloader config writer;
- a filesystem without the assumed ordering.

**L7 Principal Defense:**
- **Name the commit point.** It is `renameat(loader.tmp, loader)` in `swap_bootloader()`, preceded by `full_system_sync()`, with the previous `loader.N` untouched.
- **Show the proof** (§2.1: all states bootable; the in-place variant isn't).
- **For vfat `/boot` or U-Boot-specific configs,** require the same structure: write new, sync, atomically switch. Test with power-cut rigs that cut at random points during deploy, thousands of times.

### Chain 6 · `/etc` drift across a fleet

**Initial Prompt:** "Six months after launch, 8% of devices behave differently after an update that changed a default in `/etc/app.conf`. Why, and what's the fix?"

**L5 Answer:** "Those devices must have a different version. Force-reinstall the update on them."

**Why L5 Bricks Devices at Scale:**
- **They do have the same version.** Their `/etc/app.conf` was edited locally (support, provisioning, a script), so OSTree's three-way merge kept the old file and the new default never landed (§1.3).
- **Re-deploying doesn't change the merge result.**

**L7 Principal Defense:**
- **Measure drift** (`ostree admin config-diff` in telemetry) and classify the modified files.
- **Fix the architecture:** product settings move to drop-ins or `/var`, and shipped files are never edited.
- **Ship a one-time migration** in the next release that reconciles the known drifted files.
- **Gate:** any new edit of a shipped `/etc` file by product tooling fails CI.

---

## 5. Invariants Checklist

- [ ] `composefs.enabled=signed`, key in the initramfs, initramfs inside the signed FIT; `sysroot.readonly=true`.
- [ ] Kernel command line not writable from storage (03.1).
- [ ] Remote: `sign-verify=ed25519` with a pinned key file in `/usr`, `sign-verify-summary`, HTTPS, `gpg-verify=false` if Ed25519-only.
- [ ] `/boot` on a POSIX filesystem for the symlink swap, or a bootloader writer with the same write-sync-switch structure, power-cut tested.
- [ ] No edits of shipped `/etc` files; drift measured with `config-diff`.
- [ ] State in `/var` versioned and migrations reversible until mark-good.
- [ ] Freeze protection from TUF metadata (03.3); `min-free-space-*` set; old commits pruned.

## 6. References

- libostree v2026.5: `src/libostree/ostree-core.h` (object types, GVariant formats), `ostree-core.c` (paths, checksums), `ostree-mutable-tree.c` (empty tree), `ostree-sysroot-deploy.c` (`merge_configuration_from`, `write_deployments_bootswap`, `swap_bootloader`), `ostree-sysroot-upgrader.c` (timestamp check). <https://github.com/ostreedev/ostree/tree/v2026.5>
- `ostree-prepare-root(1)`, `ostree.repo-config(5)`, and `docs/composefs.md`, `docs/atomic-upgrades.md`, `docs/deployment.md`. <https://ostreedev.github.io/ostree/>
- GVariant serialization specification (GLib). <https://docs.gtk.org/glib/struct.Variant.html>
- In this KB: [03.1 A/B state machine](01-sota-vs-fota-ab-symmetric-asymmetric-and-bootloader-fallback-state-machine.md) · [03.3 TUF and Uptane](03-tuf-the-update-framework-uptane-role-keys-threshold-signing-and-anti-rollback.md) · [01.4 signed FIT](../01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE/04-uboot-verified-boot-fit-images-dm-verity-fscrypt-and-tpm2-measured-boot.md)
