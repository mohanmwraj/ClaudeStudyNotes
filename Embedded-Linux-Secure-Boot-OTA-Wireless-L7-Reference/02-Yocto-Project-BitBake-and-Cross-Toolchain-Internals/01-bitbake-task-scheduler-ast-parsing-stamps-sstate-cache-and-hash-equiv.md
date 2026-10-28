# 02.1 · BitBake: Task Scheduler, AST Parsing, Stamps, sstate and Hash Equivalence

> **Folder 02 · File 1 of 4.** Every Yocto build failure at scale traces back to one of three things:
> - not understanding **what BitBake parses, in which scope**;
> - not understanding **what a task signature covers**;
> - not understanding **when the shared-state cache is allowed to reuse an output**.
>
> A team that gets these wrong loses whole days: world rebuilds after a comment change, "works on my machine" sstate, metadata whose basehash changes on every parse, and release builds nobody can reproduce. A team that gets them right builds a full distribution in minutes from a warm cache, with provable reuse.
>
> This file covers:
> - the cooker pipeline, from configuration parsing to the run queue;
> - parse scopes: `.conf`, `.bb`, `.bbclass`, `.inc`, `.bbappend`, configuration fragments;
> - the datastore's operator and override semantics, with a model validated against every worked example in the BitBake manual;
> - tasks, dependency flavors and stamps;
> - **signatures**: basehash, taskhash, unihash, and what `BB_BASEHASH_IGNORE_VARS` really does;
> - **sstate and hash equivalence**: why a comment-only change no longer rebuilds the world, shown on a model;
> - production layouts for a shared cache, and how to debug a cache miss.
>
> **Pinned versions.** **Yocto 6.1 "blacksail"** (October 2026; oe-core and BitBake tags `yocto-6.1`, **BitBake 2.20.0**), and **6.0 "wrynose"** (April 2026, the LTS line). Codenames are read from oe-core's `LAYERSERIES_CORENAMES`. The combined `poky` repository's last release tag is `yocto-5.2.4`. From 5.3 onward, a build is assembled from **oe-core + BitBake + meta-yocto** with `bitbake-setup` (`bitbake/bin/bitbake-setup`), so older `git clone poky` instructions no longer describe current releases.
>
> **Verification.**
> - Variable, class, task and function names are checked against the yocto-6.1 oe-core and BitBake trees.
> - `bbvar_model.py` reproduces all 25 results stated in BitBake's own user manual.
> - `sig_model.py` is a structural model of the signature and equivalence decisions. It is not byte-compatible with BitBake's hashes.
> - No `bitbake` binary was run: running downloaded code isn't possible in this environment (see the README).

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 The cooker pipeline

```text
 bitbake <target>
   │
   ├─ 1. Configuration parse (ONE global datastore)
   │      bitbake.conf → conf/layer.conf of every layer in bblayers.conf → local.conf / site.conf /
   │      auto.conf → machine conf (MACHINE) → distro conf (DISTRO) → INHERIT'ed global classes
   │      (oe-core 6.1 default INHERIT_DISTRO: debian devshell sstate license remove-libtool
   │       create-spdx buildstats uninative) → configuration fragments (OE_FRAGMENTS)
   │
   ├─ 2. Recipe parse (one datastore COPY per recipe, in parallel workers; cached in bb_cache)
   │      recipe.bb + every matching .bbappend (in layer priority order) + inherited .bbclass
   │      + include/require'd .inc → anonymous python () {} runs → finalize: overrides, keys
   │
   ├─ 3. Providers: PREFERRED_PROVIDER_virtual/*, PREFERRED_VERSION_*, COMPATIBLE_MACHINE, SKIP_RECIPE
   │
   ├─ 4. Task graph: each recipe's tasks (addtask … after … before …) + inter-recipe dependencies
   │      DEPENDS → do_prepare_recipe_sysroot needs dep's do_populate_sysroot
   │      RDEPENDS → do_package_write_* / do_rootfs needs dep's packages
   │      [depends] [rdepends] [recrdeptask] [mcdepends] flags for everything else
   │
   ├─ 5. Signatures: basehash per task (at parse), taskhash per task (at run-queue build),
   │      unihash via the hash-equivalence server (BB_SIGNATURE_HANDLER = "OEEquivHash")
   │
   ├─ 6. Setscene phase: for every task with sstate, try to restore output by unihash
   │      (local SSTATE_DIR, then SSTATE_MIRRORS). Covered tasks are skipped entirely.
   │
   └─ 7. Run queue: execute remaining tasks in dependency order (BB_NUMBER_THREADS parallel),
          write stamps, report outhash → server may map a new taskhash to an existing unihash
```

### 1.2 Parse scopes: where a line of metadata lives

| File | Scope | Notes |
|---|---|---|
| `conf/*.conf` (`bitbake.conf`, `layer.conf`, `local.conf`, machine, distro) | **Global**, one datastore | Everything a recipe sees as "configuration". A typo here affects every recipe |
| `*.bb` | **Per-recipe** copy of the global datastore | Isolated: one recipe's assignment never leaks to another |
| `*.bbappend` | Merged into the matching recipe(s) | Everything before `%` is a **prefix** match on the recipe file name (`cooker.get_file_appends`): `linux-yocto_%.bbappend` matches `linux-yocto_6.18.bb` and `linux-yocto_7.2.bb`, but `linux-yocto%.bbappend` would also hit `-rt`, `-tiny` and `-fitimage`. A bbappend matching no recipe is **fatal** ("No recipes in default available for"); the old `BB_DANGLINGAPPENDS_WARNONLY` escape hatch is listed in `BB_RENAMED_VARIABLES` as removed |
| `*.bbclass` | `inherit` pulls it into the recipe at that point; `INHERIT` makes it global | `inherit_defer` delays the inherit until the end of parsing, so a variable set later can choose the class |
| `*.inc` | `include` (optional) / `require` (mandatory: fails if missing) / `include_all` (from every layer) | Shared fragments of recipes or configuration |
| `conf/fragments/<layer>/<name>.conf` | Configuration fragments, enabled with `bitbake-config-build enable-fragment …` (`OE_FRAGMENTS`) | Built-in fragment variables: `machine:MACHINE distro:DISTRO` (`OE_FRAGMENTS_BUILTIN`) |

**The consequence everyone learns the hard way:** a recipe cannot change configuration. `MACHINE_FEATURES` set inside a recipe changes only that recipe's copy. Global policy belongs in machine, distro or local configuration, or in a fragment.

### 1.3 Datastore semantics: operators and overrides

BitBake evaluates a variable in a fixed order (BitBake 2.20 `lib/bb/data_smart.py`, `getVarFlag`):

1. **Immediate operators** take effect while parsing: `=` (deferred expansion), `:=` (expand now), `?=` (set if unset), `??=` (weak default), `+=` / `=+` (with a space), `.=` / `=.` (without a space).
2. **Conditional overrides.** If `VAR:o` exists and `o` is in `OVERRIDES` (later entries have higher priority), its content replaces `VAR`'s.
3. **`:append`, then `:prepend`, then `:remove`** are applied at **expansion** time, each only if all of its override qualifiers are active. `:remove` splits on single whitespace characters and drops matching tokens, preserving the remaining spacing.
4. **Key expansion** (`A${B} = …`) happens when the datastore is finalized.

| Operator | When | Space added | Typical use | Classic bug |
|---|---|---|---|---|
| `VAR = "x"` | Deferred expansion | — | Most assignments | Overwrites a class's earlier `+=` |
| `VAR := "x"` | Expanded now | — | `FILESEXTRAPATHS:prepend := "${THISDIR}/files:"` | Captures values that change later |
| `VAR ?= "x"` | Now, if unset | — | Defaults in conf files | First one wins, so ordering surprises |
| `VAR ??= "x"` | Weak default | — | Lowest-priority defaults | `+=` on it ignores the weak default |
| `VAR += "x"` | Now | Yes | Rarely: lists in the same file | Lost if a later `=` follows |
| `VAR:append = " x"` | Expansion | **No** | Classes, bbappends, conf files | Missing leading space fuses words |
| `VAR:remove = "x"` | Expansion, last | n/a | Taking items out of lists | Cannot be re-added afterwards |

**Old syntax.** Since BitBake 1.52 (Honister), `_append`, `_prepend` and `_remove` in a variable name are a **fatal** error:
- `setVar()` stops with "Variable … contains an operation using the old override syntax";
- `scripts/contrib/convert-overrides.py` converts layers.

`_${PN}`-style names (`RDEPENDS_${PN}`) don't trip that check: they still parse, as a *different, unused* variable.

### 1.4 Tasks, dependencies and stamps

The standard chain for a target recipe:

```text
do_fetch → do_unpack → do_patch → do_prepare_recipe_sysroot → do_configure → do_compile → do_install
   → do_package → do_packagedata → do_package_write_{rpm,ipk,deb} ;  do_install → do_populate_sysroot
images: do_rootfs → do_image → do_image_<fstype> → do_image_complete
```

| Mechanism | Meaning |
|---|---|
| `DEPENDS = "zlib"` | My `do_prepare_recipe_sysroot` waits for zlib's `do_populate_sysroot` (build-time headers and libraries) |
| `RDEPENDS:${PN} = "zlib"` | My package needs zlib's package at runtime. The image's `do_rootfs` installs both |
| `do_x[depends] = "pn:do_y"` | An explicit task-to-task edge |
| `do_x[rdepends]`, `[recrdeptask]`, `[mcdepends]` | Runtime, recursive and multiconfig edges |
| `do_x[nostamp] = "1"` | Always runs (e.g. `do_menuconfig`, `do_diffconfig` in `cml1.bbclass`) |
| Stamp files (`${STAMP}.do_compile.<hash>`) | "This task ran with this signature". A different signature means no matching stamp, so the task re-runs |

### 1.5 Signatures: what a task hash actually covers

BitBake 2.20 `lib/bb/siggen.py` builds hashes in three layers:

| Hash | Computed from | When |
|---|---|---|
| **basehash** | The task's code, plus the values of every variable and function it references (found by `bb.data.generate_dependencies`), **minus** `BB_BASEHASH_IGNORE_VARS`, adjusted by `vardeps` / `vardepsexclude` / `vardepvalue` flags | At parse time, per task |
| **taskhash** | basehash + the **unihash** of every task it depends on + file checksums (`file-checksums` flag, e.g. kernel fragments) | When the run queue is built |
| **unihash** | Equal to taskhash, unless the hash-equivalence server knows another taskhash whose **output hash** was identical; then that taskhash's unihash is reused | Queried before running; reported after running |

- **Determinism is enforced.** If a recipe's basehash differs between two parses, BitBake errors: "When reparsing …, the basehash value changed … The metadata is not deterministic and this needs to be fixed." Typical culprits: a timestamp, a path or a random value referenced by a task, and not listed in `BB_BASEHASH_IGNORE_VARS`.
- **Renamed variables are caught.** `data_smart.py` keeps a rename table: `BB_HASHBASE_WHITELIST` → `BB_BASEHASH_IGNORE_VARS`, `BB_ENV_WHITELIST` → `BB_ENV_PASSTHROUGH`, and so on. Using an old name is a parse error, not a silent no-op.

### 1.6 sstate and hash equivalence

- **Shared state** stores task outputs (`do_populate_sysroot`, `do_package`, `do_packagedata`, `do_package_write_*`, `do_deploy`…) as archives in `SSTATE_DIR` (default `${TOPDIR}/sstate-cache`). It looks them up by **unihash**, locally and through `SSTATE_MIRRORS`.
- **Hash equivalence** is on by default in oe-core 6.1: `BB_SIGNATURE_HANDLER ?= "OEEquivHash"` and `BB_HASHSERVE ??= "auto"` (`meta/conf/bitbake.conf`). After a task runs, OE computes an **outhash** of its output with `SSTATE_HASHEQUIV_METHOD ?= "oe.sstatesig.OEOuthashBasic"`. If the server already has a unihash for that outhash, the new taskhash is mapped to it, so **dependents see an unchanged input and come from sstate**.
- **`BB_HASHSERVE_UPSTREAM`** lets a local or company server consult a further one (for example the Yocto Project's public server).
- **sstate signing:** `SSTATE_SIG_KEY` (with `SSTATE_SIG_PASSPHRASE`) signs archives, and `SSTATE_VERIFY_SIG` (default `"0"`) makes consumers verify them.

The model in §2.3 shows the effect: one comment-only edit at the bottom of the graph re-runs one task instead of five.

---

## 2. Production Code & Configuration Blueprints

### 2.1 Datastore semantics, proven

A model of the datastore algorithm, validated against every worked example in `bitbake/doc/bitbake-user-manual/bitbake-user-manual-metadata.rst` at yocto-6.1:

```python
# bbvar_model.py - a model of BitBake's datastore operators and overrides (mirrors bitbake 2.20 lib/bb/data_smart.py)
"""Implements =, :=, ?=, ??=, +=, =+, .=, =. and :append / :prepend / :remove with conditional overrides,
the order getVarFlag() applies them in, and key expansion. Self-test: every worked example in
bitbake/doc/bitbake-user-manual/bitbake-user-manual-metadata.rst (yocto-6.1) must give the manual's result.

Algorithm (data_smart.getVarFlag, "_content"):
  1. if an override variant VAR:o is active (o in OVERRIDES; later entries have higher priority),
     its content (with its own appends/prepends) replaces VAR's content;
  2. else VAR's own content, else its weak default (??=);
  3. apply VAR's :append entries (each only if all its override qualifiers are active), then :prepend;
  4. expand ${...}; 5. apply :remove (split on each single whitespace char, drop matching tokens).
"""
import re

SETVAR = re.compile(r'(?P<base>.*?)(?P<keyword>:append|:prepend|:remove)(:(?P<add>[^A-Z]*))?$')
EXPAND = re.compile(r"\$\{([a-zA-Z0-9\-_+./~:]+)\}")
ASSIGN = re.compile(r'^\s*(?P<var>[A-Za-z0-9_${}/.\-+~:]+?)\s*(?P<op>\?\?=|\?=|:=|\+=|=\+|\.=|=\.|=)\s*"(?P<val>.*)"\s*$')


class Datastore:
    def __init__(self):
        self.vars = {}           # name -> dict(content, default, append, prepend, remove)
        self.overridedata = {}   # base -> [(variant name, override string)]

    def _v(self, name):
        return self.vars.setdefault(name, {"content": None, "default": None, "append": [], "prepend": [], "remove": []})

    def _register_override(self, name):
        if ":" in name:
            base, o = name.split(":", 1)
            self.overridedata.setdefault(base, [])
            if (name, o) not in self.overridedata[base]:
                self.overridedata[base].append((name, o))

    # ---- parsing-time operations ----
    def assign(self, name, op, value):
        m = SETVAR.match(name)
        if m and op == "=":
            base, kw, add = m.group("base"), m.group("keyword")[1:], m.group("add")
            self._v(base)[kw].append((value, add))
            self._register_override(base)
            return
        v = self._v(name)
        self._register_override(name)
        cur = v["content"]
        if op == "=":
            v["content"] = value
        elif op == ":=":
            v["content"] = self.expand(value)
        elif op == "?=":
            if cur is None:
                v["content"] = value
        elif op == "??=":
            v["default"] = value
        elif op == "+=":
            v["content"] = "%s %s" % (cur or "", value)
        elif op == "=+":
            v["content"] = "%s %s" % (value, cur or "")
        elif op == ".=":
            v["content"] = (cur or "") + value
        elif op == "=.":
            v["content"] = value + (cur or "")

    def parse(self, text):
        for line in text.strip().splitlines():
            line = line.split(" #")[0]
            if not line.strip():
                continue
            m = ASSIGN.match(line)
            if not m:
                raise SyntaxError(line)
            self.assign(m.group("var"), m.group("op"), m.group("val"))
        return self

    # ---- expansion-time evaluation ----
    def overrides(self):
        o = self.getvar("OVERRIDES", apply_overrides=False)
        return [x for x in (o or "").split(":") if x]

    def raw(self, name, apply_overrides=True):
        if name not in self.vars and name not in self.overridedata:
            return None, set()
        v = self._v(name)
        ovr = self.overrides() if apply_overrides else []
        value, removes, match = None, set(), None
        if apply_overrides and name in self.overridedata:
            active = {o: n for n, o in self.overridedata[name] if set(o.split(":")) <= set(ovr)}
            for o in ovr:                                       # later OVERRIDES entries win
                if o in active:
                    match = active[o]
            if match:
                value, removes = self.raw(match)
        if value is None:
            value = v["content"] if v["content"] is not None else v["default"]
        for kw in ("append", "prepend"):
            for r, add in v[kw]:
                if add is None or set(add.split(":")) <= set(ovr):
                    value = (value or "") + r if kw == "append" else r + (value or "")
        for r, add in v["remove"]:
            if add is None or set(add.split(":")) <= set(ovr):
                removes |= set(self.expand(r).split())
        return value, removes

    def getvar(self, name, apply_overrides=True):
        value, removes = self.raw(name, apply_overrides)
        if value is None:
            return None
        value = self.expand(value)
        if removes:
            value = "".join(x for x in re.split(r"(\s)", value) if x not in removes)
        return value

    def expand(self, s, depth=0):
        if depth > 20:
            raise RecursionError(s)

        def sub(m):
            val = self.getvar(m.group(1))
            return m.group(0) if val is None else val
        out = EXPAND.sub(sub, s)
        return out if out == s else self.expand(out, depth + 1)

    def finalize_keys(self):
        for name in [n for n in self.vars if "${" in n]:
            new = self.expand(name)
            if new != name:
                self.vars[new] = self.vars.pop(name)
        return self


# Each case: (metadata, {var: value the manual states}). Quoted from the BitBake user manual, yocto-6.1.
MANUAL = [
    ('T = "123"\nA := "test ${T}"\nT = "456"\nB := "${T} ${C}"\nC = "cval"\nC := "${C}append"',
     {"A": "test 123", "B": "456 cvalappend", "C": "cvalappend"}),
    ('W ??= "x"\nA := "${W}"\nW ??= "y"\nB := "${W}"\nW ??= "z"\nC = "${W}"\nW ?= "i"',
     {"A": "x", "B": "y", "C": "i", "W": "i"}),
    ('W ??= "x"\nW += "y"', {"W": " y"}),
    ('W ??= "x"\nW:append = "y"', {"W": "xy"}),
    ('B = "bval"\nB += "additionaldata"\nC = "cval"\nC =+ "test"', {"B": "bval additionaldata", "C": "test cval"}),
    ('B = "bval"\nB .= "additionaldata"\nC = "cval"\nC =. "test"', {"B": "bvaladditionaldata", "C": "testcval"}),
    ('B = "bval"\nB:append = " additional data"\nC = "cval"\nC:prepend = "additional data "\nD = "dval"\nD:append = "additional data"',
     {"B": "bval additional data", "C": "additional data cval", "D": "dvaladditional data"}),
    ('FOO = "123 456 789 123456 123 456 123 456"\nFOO:remove = "123"\nFOO:remove = "456"\nFOO2 = " abc def ghi abcdef abc def abc def def"\nFOO2:remove = "def abc ghi"',
     {"FOO": "  789 123456    ", "FOO2": "    abcdef     "}),
    ('OVERRIDES = "architecture:os:machine"\nTEST = "default"\nTEST:os = "osspecific"\nTEST:nooverride = "othercondvalue"',
     {"TEST": "osspecific"}),
    ('DEPENDS = "glibc ncurses"\nOVERRIDES = "machine:local"\nDEPENDS:append:machine = " libmad"',
     {"DEPENDS": "glibc ncurses libmad"}),
    ('OVERRIDES = "foo"\nA = "Z"\nA:foo:append = "X"', {"A": "X"}),
    ('OVERRIDES = "foo"\nA = "Z"\nA:append:foo = "X"', {"A": "ZX"}),
    ('OVERRIDES = "foo"\nA = "Y"\nA:foo:append = "Z"\nA:foo:append = "X"', {"A": "ZX"}),
    ('A = "1"\nA:append = "2"\nA:append = "3"\nA += "4"\nA .= "5"', {"A": "1 4523"}),
    ('A${B} = "X"\nB = "2"\nA2 = "Y"', {"A2": "X"}),
]


def main():
    fails = 0
    print("[1] BitBake user manual worked examples")
    for i, (meta, want) in enumerate(MANUAL, 1):
        d = Datastore().parse(meta).finalize_keys()
        for var, val in want.items():
            got = d.getvar(var)
            ok = got == val
            fails += not ok
            print(f"  {'ok  ' if ok else 'FAIL'} ex{i:02d} {var} = {got!r}" + ("" if ok else f"  (manual: {val!r})"))

    print("[2] The bugs these rules cause in real layers")
    d = Datastore().parse('IMAGE_INSTALL = "packagegroup-core-boot"\nIMAGE_INSTALL:append = "htop"')
    got = d.getvar("IMAGE_INSTALL")
    print(f"  IMAGE_INSTALL:append = \"htop\"   -> {got!r}   (one bogus package name)")
    fails += got != "packagegroup-core-boothtop"
    d = Datastore().parse('FOO = "initial"\nFOO += "val"')
    print(f"  class 'FOO += \"val\"' before recipe 'FOO = \"initial\"' -> recipe wins: "
          f"{Datastore().parse('FOO += \"val\"' + chr(10) + 'FOO = \"initial\"').getvar('FOO')!r}")
    d = Datastore().parse('FOO:append = " val"\nFOO = "initial"')
    got = d.getvar("FOO")
    print(f"  class 'FOO:append = \" val\"' survives the recipe assignment -> {got!r}")
    fails += got != "initial val"
    d = Datastore().parse('OVERRIDES = "aarch64:myboard"\nKERNEL_DEVICETREE = "a.dtb"\nKERNEL_DEVICETREE:aarch64 = "b.dtb"\nKERNEL_DEVICETREE:myboard = "c.dtb"')
    got = d.getvar("KERNEL_DEVICETREE")
    print(f"  OVERRIDES='aarch64:myboard': the later (machine) override wins -> {got!r}")
    fails += got != "c.dtb"
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
[1] BitBake user manual worked examples
  ok   ex01 A = 'test 123'
  ok   ex01 B = '456 cvalappend'
  ok   ex01 C = 'cvalappend'
  ok   ex02 A = 'x'
  ok   ex02 B = 'y'
  ok   ex02 C = 'i'
  ok   ex02 W = 'i'
  ok   ex03 W = ' y'
  ok   ex04 W = 'xy'
  ok   ex05 B = 'bval additionaldata'
  ok   ex05 C = 'test cval'
  ok   ex06 B = 'bvaladditionaldata'
  ok   ex06 C = 'testcval'
  ok   ex07 B = 'bval additional data'
  ok   ex07 C = 'additional data cval'
  ok   ex07 D = 'dvaladditional data'
  ok   ex08 FOO = '  789 123456    '
  ok   ex08 FOO2 = '    abcdef     '
  ok   ex09 TEST = 'osspecific'
  ok   ex10 DEPENDS = 'glibc ncurses libmad'
  ok   ex11 A = 'X'
  ok   ex12 A = 'ZX'
  ok   ex13 A = 'ZX'
  ok   ex14 A = '1 4523'
  ok   ex15 A2 = 'X'
[2] The bugs these rules cause in real layers
  IMAGE_INSTALL:append = "htop"   -> 'packagegroup-core-boothtop'   (one bogus package name)
  class 'FOO += "val"' before recipe 'FOO = "initial"' -> recipe wins: 'initial'
  class 'FOO:append = " val"' survives the recipe assignment -> 'initial val'
  OVERRIDES='aarch64:myboard': the later (machine) override wins -> 'c.dtb'
ALL PASSED: 0 failure(s)
```

#### The Fragile Way

```bitbake
# in a class:
FOO += "val"                         # lost: the recipe's later 'FOO = "initial"' overwrites it
# in a bbappend or conf file:
IMAGE_INSTALL:append = "htop"        # -> "...packagegroup-core-boothtop": a package that does not exist
KERNEL_DEVICETREE_append = " b.dtb"  # fatal parse error since bitbake 1.52
```

#### The Silicon-Hardened Production Way

```bitbake
# in a class: survives any assignment the recipe makes later
FOO:append = " val"
# lists: always start the appended value with a space
IMAGE_INSTALL:append = " htop"
# conditional, override-style, machine-scoped
KERNEL_DEVICETREE:append:acme-imx8m = " freescale/imx8mm-acme-rev2.dtb"
# and verify, instead of believing:  bitbake-getvar -r core-image-minimal IMAGE_INSTALL
```

`bitbake-getvar` (BitBake 2.20 `bin/`) prints a variable's final value, and with history shows every file and line that touched it. Use it in CI on the handful of variables that define your product (`IMAGE_INSTALL`, `DISTRO_FEATURES`, `MACHINE_FEATURES`, `KERNEL_DEVICETREE`).

### 2.2 A shared cache that is fast and trustworthy

#### The Fragile Way

```bitbake
# site.conf on every developer laptop and every CI runner
SSTATE_DIR = "/mnt/nfs/sstate"        # everyone writes to the same NFS share
BB_HASHSERVE = "auto"                 # each machine its own private hash-equivalence database
# no SSTATE_MIRRORS, no signing
```

- **Every developer writes into the release cache.** A laptop with an odd host tool, or a local patch, publishes outputs that CI and release builds then reuse.
- **Each machine has a private hash-equivalence database**, so equivalences learned on CI are invisible to developers. Their unihashes diverge from CI's, the shared archives are keyed by unihash, and the "shared" cache misses for exactly the tasks that matter.
- **Nothing proves an archive came from CI.**

#### The Silicon-Hardened Production Way

```bitbake
# --- CI builders (the only writers) ---
SSTATE_DIR = "/srv/sstate"                            # published read-only over HTTPS after each build
BB_HASHSERVE = "hashserv.build.acme.internal:8686"    # one read-write server, owned by CI
BB_HASHSERVE_UPSTREAM = "wss://hashserv.yoctoproject.org/ws"
SSTATE_SIG_KEY = "acme-sstate-ci"                     # GPG key id held by the CI signer
# --- developers (readers) ---
SSTATE_MIRRORS = "file://.* https://sstate.build.acme.internal/PATH;downloadfilename=PATH"
BB_HASHSERVE = "hashserv-ro.build.acme.internal:8687" # same database, served --read-only
SSTATE_VERIFY_SIG = "1"                               # refuse archives not signed by CI
```

The servers are `bitbake-hashserv` (BitBake 2.20 options: `--bind`, `--database`, `--upstream`, `--read-only`, `--anon-perms`, `--admin-user`/`--admin-password`, `--reuseport`):

```bash
bitbake-hashserv --bind ws://0.0.0.0:8686 --database /srv/hashserv/db.sqlite --upstream wss://hashserv.yoctoproject.org/ws
bitbake-hashserv --bind ws://0.0.0.0:8687 --database /srv/hashserv/db.sqlite --read-only
```

**One writer, many readers, one equivalence database, signed archives.** The upstream URL is the one oe-core 6.1 itself uses in its `core/yocto/sstate-mirror-cdn` fragment (`BB_HASHSERVE_UPSTREAM = 'wss://hashserv.yoctoproject.org/ws'`, with `SSTATE_MIRRORS ?= "file://.* http://sstate.yoctoproject.org/all/PATH;downloadfilename=PATH"`).

oe-core's own sanity checks (`meta/lib/oe/sanity.py`, active when `BB_SIGNATURE_HANDLER` is `OEEquivHash`) warn about both halves of the fragile layout:
- *"You are using a local hash equivalence server but have configured an sstate mirror. This will likely mean no sstate will match from the mirror."* This fires for a `unix://` (per-build) server with `SSTATE_MIRRORS` and no `BB_HASHSERVE_UPSTREAM`.
- *"Sstate directory is on a shared NFS … but hash equivalency database is inside this particular build directory … This will prevent sstate reuse."*

Treat both as build failures in CI (a log scan), not as noise.

### 2.3 What hash equivalence buys you, on a model

```python
# sig_model.py - task signatures, sstate and hash equivalence as BitBake/OE compute them (a structural model)
"""Mirrors the shape of bitbake 2.20 lib/bb/siggen.py + oe-core lib/oe/sstatesig.py (yocto-6.1):
  basehash(task) = H(task code + values of the variables it references, minus BB_BASEHASH_IGNORE_VARS)
  taskhash(task) = H(basehash + unihash of every dependency task + file checksums)
  outhash(task)  = H(the task's output tree)        (OEOuthashBasic: paths, modes, contents ...)
  unihash(task)  = taskhash, unless the hash-equivalence server already maps a taskhash with the SAME
                   outhash to a unihash: then that unihash is reused (BB_SIGNATURE_HANDLER = "OEEquivHash")
  sstate objects are keyed by unihash, and dependents hash the unihash, not the taskhash.
Not byte-compatible with BitBake's hashes; the dependency structure and decisions are the point.
"""
import hashlib

H = lambda *parts: hashlib.sha256("\x00".join(parts).encode()).hexdigest()[:16]


class Build:
    def __init__(self, equiv: bool, ignore=("DATETIME", "BB_NUMBER_THREADS")):
        self.equiv, self.ignore = equiv, set(ignore)
        self.sstate = {}          # unihash -> output
        self.hashserv = {}        # taskhash -> (unihash, outhash)
        self.by_outhash = {}      # outhash -> unihash (first reported wins)

    def run(self, recipes, env):
        unihash, ran, outputs = {}, [], {}
        for name, r in recipes.items():                        # dict order = dependency order
            used = {k: env.get(k, r["vars"].get(k, "")) for k in r["refs"]}
            base = H(r["code"], *[f"{k}={v}" for k, v in sorted(used.items()) if k not in self.ignore])
            task = H(base, *sorted(unihash[d] for d in r["deps"]))
            if self.equiv and task in self.hashserv:
                uni = self.hashserv[task][0]
            else:
                uni = task
            if uni in self.sstate:                              # setscene: restore from sstate
                unihash[name], outputs[name] = uni, self.sstate[uni]
                continue
            out = r["output"](used, {d: outputs[d] for d in r["deps"]})   # really run the task
            ran.append(name)
            outh = H(out)
            if self.equiv:
                uni = self.by_outhash.setdefault(outh, task)    # report outhash; server answers unihash
                self.hashserv[task] = (uni, outh)
            self.sstate[uni] = out
            unihash[name], outputs[name] = uni, out
        return ran


def recipes(zlib_code="./configure && make  # build zlib", zlib_ver="1.3.1"):
    strip = lambda code: code.split("#")[0].strip()             # comments don't reach the binary
    # Libraries link dynamically: a dependency's new version does not change THEIR bytes. The image
    # (rootfs) embeds every package's output, so it changes whenever any package does.
    mk = lambda name, deps, code, ver, embeds=False: {
        "deps": deps, "code": code, "refs": ["PV", "CFLAGS", "DATETIME"], "vars": {"PV": ver},
        "output": lambda used, depout, c=code, n=name, e=embeds:
            f"{n}-{used['PV']}:{strip(c)}:{used['CFLAGS']}" + ("|" + "|".join(depout.values()) if e else "")}
    return {
        "zlib": mk("zlib", [], zlib_code, zlib_ver),
        "openssl": mk("openssl", ["zlib"], "./Configure && make", "3.5.4"),
        "curl": mk("curl", ["openssl", "zlib"], "autoreconf && make", "8.16.0"),
        "app": mk("app", ["curl"], "cmake --build .", "2.1.0"),
        "image": mk("image", ["app", "curl", "openssl", "zlib"], "do_rootfs", "1.0", embeds=True),
    }


def main():
    env = {"CFLAGS": "-O2", "DATETIME": "20261028090000"}
    fails = 0
    for equiv in (False, True):
        b = Build(equiv)
        print(f"== BB_SIGNATURE_HANDLER = {'OEEquivHash' if equiv else 'OEBasicHash'}")
        print(f"   first build:             ran {b.run(recipes(), env)}")
        ran = b.run(recipes(), env)
        print(f"   rebuild, nothing changed: ran {ran}")
        fails += ran != []
        ran = b.run(recipes(zlib_code="./configure && make  # build zlib (fixed typo in comment)"), env)
        print(f"   comment-only zlib edit:   ran {ran}")
        fails += ran != (["zlib"] if equiv else ["zlib", "openssl", "curl", "app", "image"])
        ran = b.run(recipes(zlib_ver="1.3.2"), env)
        print(f"   real zlib update (PV):    ran {ran}")
        # With equivalence: openssl and curl must re-run (an input changed) but produce identical bytes,
        # so their unihashes are unchanged and app is restored from sstate; the image embeds zlib, so it runs.
        fails += ran != (["zlib", "openssl", "curl", "image"] if equiv else ["zlib", "openssl", "curl", "app", "image"])
    print("== A volatile variable that is NOT in BB_BASEHASH_IGNORE_VARS")
    b = Build(True, ignore=("BB_NUMBER_THREADS",))
    b.run(recipes(), env)
    ran = b.run(recipes(), dict(env, DATETIME="20261028090500"))
    print(f"   same sources, 5 min later: ran {ran}")
    fails += ran != ["zlib", "openssl", "curl", "app", "image"]
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
== BB_SIGNATURE_HANDLER = OEBasicHash
   first build:             ran ['zlib', 'openssl', 'curl', 'app', 'image']
   rebuild, nothing changed: ran []
   comment-only zlib edit:   ran ['zlib', 'openssl', 'curl', 'app', 'image']
   real zlib update (PV):    ran ['zlib', 'openssl', 'curl', 'app', 'image']
== BB_SIGNATURE_HANDLER = OEEquivHash
   first build:             ran ['zlib', 'openssl', 'curl', 'app', 'image']
   rebuild, nothing changed: ran []
   comment-only zlib edit:   ran ['zlib']
   real zlib update (PV):    ran ['zlib', 'openssl', 'curl', 'image']
== A volatile variable that is NOT in BB_BASEHASH_IGNORE_VARS
   same sources, 5 min later: ran ['zlib', 'openssl', 'curl', 'app', 'image']
ALL PASSED: 0 failure(s)
```

What the model shows:
- **A comment-only edit** changes zlib's code, so zlib's taskhash changes and zlib **must** run once: there's no way to know the output is unchanged without producing it. With `OEEquivHash` the outhash matches, the unihash is reused, and **nothing downstream runs**.
- **A real update** (zlib 1.3.2) re-runs zlib, openssl and curl, whose input changed. But with dynamic linking their outputs are byte-identical, so their unihashes don't change and `app` is restored from sstate. The image embeds zlib, so it runs.
- **A volatile variable left out of `BB_BASEHASH_IGNORE_VARS`** defeats everything: same sources five minutes later, full rebuild. BitBake's "basehash value changed" error exists to catch exactly this at parse time.

### 2.4 Debugging a cache miss

```bash
# Which tasks will run, and why? Compare signatures against the closest sstate match:
bitbake -S printdiff core-image-minimal
# Two specific signature files:
bitbake-diffsigs tmp/stamps/.../zlib/1.3.1.do_compile.sigdata.<old> tmp/stamps/.../zlib/1.3.1.do_compile.sigdata.<new>
# Everything a task signature was built from:
bitbake-dumpsig tmp/stamps/.../zlib/1.3.1.do_compile.sigdata.<hash>
# Final value and provenance of a variable in one recipe:
bitbake-getvar -r zlib CFLAGS
# Query or inspect the equivalence server:
bitbake-hashclient --address ws://hashserv.build.acme.internal:8686 stats
```

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Cause | Fix |
|---|---|---|
| `Variable X contains an operation using the old override syntax` (fatal) | `_append` / `_prepend` / `_remove` in a layer | `scripts/contrib/convert-overrides.py`; review the result |
| `When reparsing …, the basehash value changed` | Non-deterministic metadata: time, random value, absolute path | `bitbake-diffsigs` the two parses; add to `BB_BASEHASH_IGNORE_VARS` only if it truly doesn't affect output, otherwise make it deterministic |
| World rebuild after a trivial change | Hash equivalence off, or developers and CI use different equivalence databases | One shared `bitbake-hashserv`, read-only for readers (§2.2) |
| sstate from mirror never used | Unihash mismatch (different hashserv), signature verification failing, or `SSTATE_MIRRORS` pattern wrong | `bitbake -S printdiff`; check `SSTATE_VERIFY_SIG` logs; test the mirror URL with one archive |
| A bbappend silently has no effect | Layer's `BBFILES` doesn't match `*.bbappend`, so the file is never collected and even the dangling-append check can't see it. (A collected append whose name matches no recipe, e.g. a version-pinned name after an upgrade, is fatal instead) | `bitbake-layers show-appends`; lint rule R8 (02.2) |
| A setting "works" on one machine only | It was set inside a recipe (per-recipe scope), or in `local.conf` on that machine | Move to machine, distro or fragment configuration; CI builds from a clean `local.conf` |
| Release build differs from developer build | Developer outputs in the shared cache (fragile §2.2), host contamination | Single writer; signed sstate; reproducibility checks (02.4) |

**Post-mortem method for "why did this rebuild?"**
1. `bitbake -S printdiff <target>` names the first task whose signature diverged from the cache.
2. `bitbake-diffsigs` on its sigdata shows exactly which variable, function or dependency changed.
3. Classify it:
   - **an intended change:** fine;
   - **non-determinism:** fix the metadata;
   - **an environment difference** (host tool, path, user): fix the build environment or `BB_BASEHASH_IGNORE_VARS`, with care.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · "Why did changing a comment rebuild everything?"

**Initial Prompt:** "A developer fixed a typo in a comment in a low-level recipe, and our CI rebuilt the whole distribution. Explain and fix."

**L5 Answer:** "BitBake rebuilds everything that depends on a changed recipe. We could pin the recipe version or use sstate to speed it up."

**Why L5 Bricks Devices at Scale:** It accepts world rebuilds as normal, so teams batch changes to avoid them. The batching hides which change broke the build, release candidates take a day instead of an hour, and nobody trusts the cache enough to use it for releases. "Pinning the version" changes nothing: the task's code changed, not its version.

**L7 Principal Defense:**
- **Why the task re-runs:** the comment is part of the task's code, so the basehash changes and that task must re-run.
- **Why everything downstream used to re-run:** dependents hash the dependency's **unihash**.
- **What hash equivalence does:** with `OEEquivHash` (6.1's default) and a **shared** `bitbake-hashserv`, the re-run produces an identical outhash, the server returns the old unihash, and dependents restore from sstate (model §2.3: five tasks become one).
- **The usual root cause** when it still rebuilds is per-machine `BB_HASHSERVE = "auto"` databases.
- **The fix:** one read-write server for CI, read-only for developers, `BB_HASHSERVE_UPSTREAM`, signed sstate, and `bitbake -S printdiff` in CI to explain any unexpected rebuild.

### Chain 2 · Where does this line of metadata live?

**Initial Prompt:** "A recipe sets `DISTRO_FEATURES:append = " wayland"` and the image doesn't get Wayland. Why?"

**L5 Answer:** "Maybe a typo, or another layer overrides it. Try `+=` instead."

**Why L5 Bricks Devices at Scale:** It's a scope error, not an operator error. Every recipe parses with its own copy of the global datastore, so a recipe's change to a distro policy variable affects only that recipe. Switching operators "fixes" nothing, and the same misunderstanding leads to inconsistent features across recipes that silently mismatch at runtime.

**L7 Principal Defense:**
- **Configuration is parsed once, globally; recipes get private copies.** Policy goes in the distro configuration (or a fragment), hardware facts in the machine configuration, and per-build tweaks in `local.conf`, which CI should treat as empty.
- **Verify** with `bitbake-getvar -r <recipe> DISTRO_FEATURES` on two recipes; they must agree.
- **Lint** for policy variables set in the wrong file type. 02.2's rule R7 does this for machine configuration; the same table-driven check extends to recipes and bbappends.

### Chain 3 · Non-deterministic metadata

**Initial Prompt:** "BitBake reports that a recipe's basehash changed between parses. What does that mean and how do you fix it properly?"

**L5 Answer:** "Add the variable to `BB_BASEHASH_IGNORE_VARS` so it stops being part of the hash."

**Why L5 Bricks Devices at Scale:** That silences the error by telling BitBake a variable doesn't matter. If it does affect the output (a build timestamp baked into a binary, a path compiled into a config), the cache now reuses outputs that differ from what a fresh build would produce. That breaks reproducibility, and with it the ability to prove what you shipped.

**L7 Principal Defense:**
- **Find the variable:** `bitbake-diffsigs` the two parses.
- **Classify it:**
  - **Affects output** (time, random, host path): make it deterministic, e.g. derive from `SOURCE_DATE_EPOCH` (02.4) or use a relative path.
  - **Doesn't affect output** (a cache path, a parallelism level such as `BB_NUMBER_THREADS`): exclude it with `vardepsexclude` on that task, or with `BB_BASEHASH_IGNORE_VARS` if it's truly global.
- **Prove it:** a reproducibility build of the affected recipe from two hosts must be bit-identical.

### Chain 4 · Designing the shared cache

**Initial Prompt:** "We have 40 developers and 20 CI runners. Design sstate and hash equivalence."

**L5 Answer:** "Put sstate on a shared NFS drive everyone can write to, and enable hash equivalence."

**Why L5 Bricks Devices at Scale:** It fails on every count:
- **Writable by everyone:** any laptop can poison release builds.
- **Separate equivalence databases** make the shared cache miss.
- **No signatures** means no way to prove provenance.
- **NFS write contention** and partial archives cause flaky builds.

The release process can't be audited, and when a bad artifact appears, nobody can say which machine produced it.

**L7 Principal Defense:**
- **Single writer:** CI builds and publishes sstate (read-only HTTPS mirror) and runs the read-write `bitbake-hashserv`.
- **Readers:** developers use `SSTATE_MIRRORS` plus a `--read-only` hashserv on the same database, with `SSTATE_VERIFY_SIG = "1"` against CI's `SSTATE_SIG_KEY`.
- **Upstream:** `BB_HASHSERVE_UPSTREAM` for public equivalences.
- **Retention policy:** prune by age, but keep everything referenced by a release.
- **Measure** the cache hit rate and the "unexpected rebuild" rate, with `printdiff` reports on CI.

### Chain 5 · The silent no-op

**Initial Prompt:** "A layer sets `RDEPENDS_${PN} += "watchdog-tools"`. The build is clean, but the package isn't on the device. What happened?"

**L5 Answer:** "Maybe the package name is wrong. Check that watchdog-tools exists."

**Why L5 Bricks Devices at Scale:**
- **`_${PN}` is the pre-Honister form.** Unlike `_append`, which BitBake now rejects fatally, it parses as a **different variable**, `RDEPENDS_<pn>`, which nothing reads.
- **The build succeeds, and the dependency is simply absent.** For a watchdog daemon, that means devices that never recover from a hang.

**L7 Principal Defense:**
- **The correct form** is `RDEPENDS:${PN}`.
- **Know which old forms are fatal** (`_append`/`_prepend`/`_remove` in names) **and which are silent** (`_${PN}`, typos, renamed variables in some cases).
- **Make silent ones loud:**
  - a lint that rejects unknown variable names against an index built from oe-core and BitBake (02.2 `bb_lint.py`, 3,679 names in 6.1);
  - `bitbake-getvar` checks on product-critical variables;
  - an image test that asserts required packages are present (oeqa `runtime` tests or a manifest check in CI).

### Chain 6 · Choosing a release line

**Initial Prompt:** "We're starting a product today that ships for eight years. Which Yocto release do we build on, and how?"

**L5 Answer:** "The latest release, 6.1, because it has the newest features. Clone poky and go."

**Why L5 Bricks Devices at Scale:**
- **A non-LTS release** gets roughly seven months of upstream support. The product would be on an unmaintained branch before it ships.
- **"Clone poky" no longer describes how releases are assembled** after 5.2.
- **Eight years of support** need an LTS line and a plan to move between LTS releases, or the security patch stream stops.

**L7 Principal Defense:**
- **Build on the LTS line, 6.0 "wrynose".** ⚠ Check the published support window. Track the current release (6.1 "blacksail") in a CI job, to see breaking changes early: the 6.x FIT class split, `cve-check` replaced by `sbom-cve-check` and `vex`, SPDX 3.0.
- **Assemble with `bitbake-setup`**, pinning every layer by commit.
- **Set `LAYERSERIES_COMPAT`** to exactly the series tested.
- **Budget a migration to the next LTS** around year 2 or 3.
- **Keep sstate, downloads and SBOMs per release** for the support life (02.4).

---

## 5. Invariants Checklist

- [ ] Global policy only in machine, distro or fragment configuration; recipes never set distro or machine policy.
- [ ] Override-style operators everywhere; list appends start with a space; no `_append`/`_${PN}` forms.
- [ ] Hash equivalence on, with **one** shared `bitbake-hashserv` (read-write for CI, read-only for others).
- [ ] sstate written only by CI, signed (`SSTATE_SIG_KEY`), verified by consumers (`SSTATE_VERIFY_SIG = "1"`).
- [ ] No "basehash changed" warnings; `BB_BASEHASH_IGNORE_VARS` additions reviewed for output impact.
- [ ] CI reports `bitbake -S printdiff` for unexpected rebuilds and checks product-critical variables with `bitbake-getvar`.
- [ ] Release line: LTS base, layers pinned by commit via `bitbake-setup`, `LAYERSERIES_COMPAT` exact.

## 6. References

- BitBake 2.20 (yocto-6.1): `lib/bb/data_smart.py`, `lib/bb/siggen.py`, `bin/bitbake-hashserv`, `doc/bitbake-user-manual/`. <https://github.com/openembedded/bitbake/tree/yocto-6.1>
- openembedded-core (yocto-6.1): `meta/conf/bitbake.conf`, `meta/classes-global/sstate.bbclass`, `meta/lib/oe/sstatesig.py`, `meta/conf/layer.conf`. <https://github.com/openembedded/openembedded-core/tree/yocto-6.1>
- Yocto Project documentation (Overview and Concepts: shared state, hash equivalence). <https://docs.yoctoproject.org/>
- Setting up a hash equivalence server (the page oe-core's sanity warning links to). <https://docs.yoctoproject.org/dev-manual/hashequivserver.html>
- Yocto Project releases and support windows. <https://wiki.yoctoproject.org/wiki/Releases>
- In this KB: [02.2 BSP layers and overrides](02-bsp-layer-engineering-machine-distro-overrides-and-kernel-devtool.md) · [02.3 Toolchains and SDKs](03-cross-compilation-toolchain-sysroots-glibc-musl-and-sdk-esdk.md) · [02.4 SBOM, CVE, reproducibility](04-sbom-spdx-cve-patching-reproducible-builds-and-license-compliance.md)
