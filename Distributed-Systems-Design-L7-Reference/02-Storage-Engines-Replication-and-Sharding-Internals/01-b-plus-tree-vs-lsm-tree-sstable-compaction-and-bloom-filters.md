# B+Tree vs LSM-Tree: SSTables, Compaction, and Bloom Filters

> **Folder 02 · File 01** of the Distributed Systems & System Design L7 Reference.
> **Prerequisites:** [Folder 01 file 02 §2–§3](../01-First-Principles-Physics-and-L5-L6-L7-Rubric/02-hardware-network-physics-latency-numbers-and-finops-math.md#3-storage-physics-from-nand-cells-to-the-wal-commit)
> (DRAM vs NVMe latency, FTL write amplification, fsync and group commit).
> **Listing:** `lsm_btree_lab.py` builds a toy leveled LSM and a toy size-tiered LSM over real keys, plus Bloom
> filters (standard and blocked) and B+tree leaves. It measures write, space and read amplification and fill factors.
> The output is deterministic.

---

## 0. The one idea: the RUM conjecture

Every access method trades three overheads (Athanassoulis et al., EDBT 2016):

| Overhead | Measured as |
|---|---|
| **R**ead | I/Os or bytes read per lookup |
| **U**pdate | Bytes written per byte changed: **write amplification**, WAF |
| **M**emory/space | Bytes stored per live byte: **space amplification**, SAF, plus RAM for indexes and filters |

You can minimize any two, but not all three. A B+tree buys low read amplification with in-place updates. An LSM tree
buys low update cost (sequential, batched writes) and pays in read amplification and compaction. Bloom filters and
compaction policy then move an LSM along the R–M edge.

Every storage-engine question in an interview reduces to "**which overhead does this workload need minimized, and
what does the hardware charge for the others?**"

---

## 1. B+trees: the read-optimized, update-in-place engine

### 1.1 Structure and fan-out math

```
                         ┌───────────────────────────────┐
  root (in RAM)          │ k1 │ k2 │ ... │ k~900          │   16 KB page, ~900 separators
                         └──┬──────────────┬─────────────┘
               ┌────────────┘              └─────────────┐
     ┌─────────▼─────────┐                    ┌──────────▼────────┐
     │ internal (in RAM) │  ...               │ internal (in RAM) │   ~900 × 900 = 810k leaves
     └─────────┬─────────┘                    └──────────┬────────┘
     ┌─────────▼──────────┐◄──────────────────►┌─────────▼──────────┐
     │ leaf: rows/entries │  sibling pointers  │ leaf: rows/entries │   range scans walk the leaf chain
     └────────────────────┘                    └────────────────────┘
```

- With 16 KB pages (the InnoDB default; PostgreSQL uses 8 KB), 8-byte keys and ~10 bytes of pointer and slot
  overhead, a node holds ~900 separators.
- Height for $N$ keys is $\lceil \log_{900} N \rceil$: **3 levels for 729M keys, 4 for 650B.**
- For 729M keys the tree has 1 root, ~900 internal pages (~14 MB), and ~810k leaves (~13 GB). The internal levels
  are effectively always in the buffer pool.
- **A point lookup therefore costs ≈ 1 random I/O** (the leaf), or 0 when cached. That is the B+tree's defining
  advantage.

### 1.2 The write path and where its amplification comes from

```
 UPDATE row ─► WAL record (sequential, group-committed fsync) ─► modify page in buffer pool (dirty)
                                                                   │
                         checkpoint / eviction (later, random) ◄───┘
                                     │
           ┌─────────────────────────┴──────────────────────────┐
           ▼                                                    ▼
  InnoDB doublewrite buffer: page written twice      PostgreSQL full_page_writes: first change after a
  (torn-page protection)                             checkpoint logs the WHOLE page into the WAL
```

The write amplification of a B+tree is

$$\text{WAF}_\text{B+tree} \approx \frac{\text{page size}}{\text{bytes changed per page between flushes}} \times (1 + \text{torn-page protection}) + \text{WAL}$$

- **Worst case:** one 100-byte row changed per 16 KB page per checkpoint gives **160×**, doubled by the
  doublewrite buffer.
- **Best case:** many updates coalesce on hot pages in the buffer pool, so a page is written once for hundreds of
  changes. WAF approaches 1–3.
- This is why B+tree write cost is **workload-shaped**. Hot-spot updates are cheap. Uniformly random updates over a
  table much larger than RAM are expensive, and they generate random 16 KB writes that the SSD's FTL must
  garbage-collect.

### 1.3 Page splits and fill factor

When a leaf overflows, it splits. Two results from the lab (§C of the output):

| Insert pattern | Leaf fill | Why |
|---|---|---|
| Random keys | **69.1%** | The classic $\ln 2$ result (Yao 1978). A third of the space is slack forever |
| Sequential keys, naive 50/50 split | 50.0% | Every split leaves a half-empty page behind |
| Sequential keys, rightmost-append split | **100%** | InnoDB and PostgreSQL detect appends at the right edge and leave the old page full |

**Random primary keys are a B+tree's worst enemy**, and it is the most common avoidable B+tree performance bug in
production. The lab inserts 1,000 more keys into a 100k-key index:

| Key type | Distinct leaves dirtied (of 2,284) |
|---|---|
| UUIDv4 (random) | **809** |
| Time-ordered (UUIDv7-like) | **17** |

The consequences of random keys:
- **The buffer pool must hold the entire index** to avoid random reads, not just the hot tail.
- **Checkpoints write ~50× more pages.**
- **Splits fragment the index**, so range scans become random I/O.

The fix is time-ordered keys: UUIDv7, ULID, or Snowflake IDs. In InnoDB, where the primary key *is* the clustered
index, this matters doubly. Every secondary index stores the PK, so a fat random PK inflates every index.

Time-ordered keys move the problem rather than removing it. In a *distributed*, range-partitioned store, monotonic
keys concentrate all writes on the last range: 100% of them, in [file 03 §D](03-consistent-hashing-bounded-loads-virtual-nodes-and-range-splitting.md#6-range-partitioning-and-the-monotonic-key-hotspot).
The right answer depends on whether the tree is local (prefer sequential) or distributed (prefer hashed prefixes).

### 1.4 Engine-specific mechanics worth knowing

| Engine | Mechanism | Design consequence |
|---|---|---|
| InnoDB | Clustered index on PK; secondaries store PK values; change buffer for secondary-index inserts; adaptive hash index; doublewrite buffer | PK choice is a physical layout choice; covering secondary indexes avoid the double lookup |
| PostgreSQL | Heap + separate B-tree indexes; MVCC keeps old tuple versions in the heap; **HOT** updates avoid index writes when no indexed column changes and the page has room (`fillfactor`) | Update-heavy tables want `fillfactor` 70–90 and few indexes; VACUUM debt is a capacity line; index-only scans need a fresh visibility map |
| WiredTiger (MongoDB) | B-tree with in-memory page images reconciled to disk, MVCC in cache, checkpoints every 60 s | Cache pressure → eviction stalls are the classic tail-latency source |
| SQLite | B-tree, 4 KB pages, WAL mode | Single-writer; fantastic read latency on local NVMe |

---

## 2. LSM trees: the write-optimized, append-only engine

### 2.1 The write path

```
 put(k,v) ─► WAL append (sequential; group commit)
          └► memtable (skiplist / ART, in RAM, ~64 MB)
                 │ full
                 ▼
          immutable memtable ──flush──► L0 SSTable (sorted, immutable; files may overlap each other)
                                            │ L0 has >= 4 files
                                            ▼
                        L1 (non-overlapping files, ~256 MB total)        ◄─ compaction: merge-sort, drop
                        L2 (~2.5 GB)   = 10 × L1                            overwritten values and expired
                        L3 (~25 GB)    = 10 × L2                            tombstones, write new files,
                        L4 (~250 GB) ...                                    delete old ones (whole-file)
```

(RocksDB defaults, ⚠ verify per version:
- `write_buffer_size` 64 MB;
- `level0_file_num_compaction_trigger` 4;
- `max_bytes_for_level_base` 256 MB;
- `max_bytes_for_level_multiplier` 10;
- dynamic level sizing on by default in recent releases.)

### 2.2 The SSTable

```
┌──────────────┬──────────────┬─────┬─────────────┬───────────────┬──────────────┬────────┐
│ data block 0 │ data block 1 │ ... │ index block │ filter block  │ properties   │ footer │
│ (4–64 KB,    │              │     │ (last key → │ (Bloom/Ribbon │ (min/max key,│ magic, │
│ prefix-      │              │     │  block off) │  per file or  │ entry counts,│ index  │
│ compressed,  │              │     │             │  partitioned) │ seqno range) │ offset │
│ restart pts) │              │     │             │               │              │        │
└──────────────┴──────────────┴─────┴─────────────┴───────────────┴──────────────┴────────┘
```

- Keys within a block are **prefix-compressed**, with restart points every ~16 keys for binary search.
- Blocks are compressed (LZ4/zstd) and checksummed (CRC32C, which is free per Folder 01 file 02 §5).
- Index and filter blocks are pinned in, or cached by, the **block cache**.
- Files are **immutable**. Every change is a new file, and deletion is whole-file. This is exactly the "data that
  dies together lives together" pattern that keeps the SSD's FTL write amplification near 1 (Folder 01 file 02 §3.2:
  5.25 → 2.63).

### 2.3 The read path

```
get(k): memtable ─► immutable memtables ─► L0 files (newest first; each may contain k)
                 ─► L1 (one file by key range) ─► L2 ─► ... ─► Ln
        at each SST: check Bloom filter (RAM) ─► if "maybe": index block ─► one data block read
```

Without filters, a point miss probes every run. With Bloom filters at false-positive rate $f$ over $r$ runs, a
lookup of a **present** key costs ≈ $1 + f(r - 1)$ I/Os, and a lookup of an **absent** key costs ≈ $f \cdot r$.
Range scans cannot use per-key filters and must merge an iterator from every run. That is the LSM's real read tax,
mitigated only by prefix Bloom filters for prefix-bounded scans.

### 2.4 Compaction strategies and their amplification

| Strategy | How it works | WAF | Space amp | Point-read runs | Typical use |
|---|---|---|---|---|---|
| **Leveled** (RocksDB default, Cassandra LCS) | Each level is one sorted run of non-overlapping files, 10× the previous. A file from Lᵢ merges into the overlapping ~10 files of Lᵢ₊₁ | High: ≈ T per level → 10–30 in practice | **Low**: ≈ 1 + 1/T ≈ 1.1 | ~1 per level + L0 files | Read-heavy, space-sensitive OLTP |
| **Size-tiered** (Cassandra STCS, the classic default) | Merge ~4 similar-sized runs into one bigger run | **Low**: ≈ number of tiers | High: up to ~2× (a major compaction needs free space equal to the data) | Many runs | Write-heavy, append-mostly |
| **Universal** (RocksDB) | Tiered with size-ratio and space-amp triggers | Low–medium | Medium–high | Many | Write-heavy with bounded space |
| **Time-window** (Cassandra TWCS) | Tier *within* time windows, never across | ≈ 1–2 | ≈ 1 when data expires by TTL | Per window | Time-series with TTL: whole windows drop |
| **FIFO** | Delete the oldest files | 1 | 1 | Many | Caches, logs |
| **Lazy leveling / Dostoevsky** (Dayan & Idreos 2018) | Tiered upper levels, leveled last level | Near-tiered | Near-leveled | Near-leveled for points | The research optimum for mixed workloads |
| **Unified (Cassandra 5.0 UCS)** | Parameterized between tiered and leveled per level | Tunable | Tunable | Tunable | Replaces STCS/LCS/TWCS choices (⚠ verify) |

The analytic shape is $\text{WAF}_\text{leveled} \approx O(T \cdot L)$ vs $\text{WAF}_\text{tiered} \approx O(L)$,
with point-read runs $O(L)$ vs $O(T \cdot L)$. The toy engines in the listing reproduce it.

### 2.5 The listing

```python
"""lsm_btree_lab.py - storage-engine amplification measured on toy engines over real keys (Folder 02, file 01).

  A. LSM tree: memtable -> L0 -> leveled (RocksDB-style, one file-sized slice at a time) or size-tiered
     (Cassandra STCS-style) compaction. Measures write, space and read amplification.
  B. Bloom filters: analytic false-positive rate vs measured; standard vs cache-line-blocked layout.
  C. B+tree leaves: fill factor under random vs sequential inserts; pages dirtied per 1,000 inserts for
     random (UUIDv4-like) vs time-ordered (UUIDv7-like) keys.
Standard library only; seeded, deterministic.
"""
import bisect
import math
import random

# ---------------------------------------------------------------- A. LSM
MEMTABLE = 500          # entries per memtable flush (= target SST size here)
T = 10                  # level size ratio
L1_CAP = 4 * MEMTABLE * 2.5
L0_TRIGGER = 4


class Leveled:
    def __init__(self):
        self.l0: list[dict] = []
        self.levels: list[tuple[list, dict]] = []          # (sorted keys, key -> seq) per level L1..
        self.cursor: list[int] = []
        self.written = 0

    def _level(self, i: int):
        while len(self.levels) <= i:
            self.levels.append(([], {}))
            self.cursor.append(0)
        return self.levels[i]

    def flush(self, mem: dict) -> None:
        self.written += len(mem)
        self.l0.append(dict(mem))
        if len(self.l0) >= L0_TRIGGER:                      # L0 -> L1: all L0 runs overlap all of L1
            keys, val = self._level(0)
            merged = dict(val)
            for run in self.l0:
                merged.update(run)
            self.l0 = []
            self.levels[0] = (sorted(merged), merged)
            self.written += len(merged)
            self._cascade(0)

    def _cascade(self, i: int) -> None:
        while len(self.levels[i][0]) > L1_CAP * T ** i:
            keys, val = self.levels[i]
            start = self.cursor[i] % len(keys)              # round-robin, one SST-sized slice at a time
            piece = keys[start:start + MEMTABLE]
            lo, hi = piece[0], piece[-1]
            nkeys, nval = self._level(i + 1)
            a, b = bisect.bisect_left(nkeys, lo), bisect.bisect_right(nkeys, hi)
            overlap = nkeys[a:b]
            merged = {k: nval[k] for k in overlap}
            for k in piece:
                merged[k] = val.pop(k)                      # the upper level is newer
            del keys[start:start + len(piece)]
            new = sorted(merged)
            nkeys[a:b] = new
            for k in new:
                nval[k] = merged[k]
            self.written += len(new)                         # rewrite of the overlapping next-level files
            self.cursor[i] = start + len(piece)
            if i + 1 < len(self.levels):
                self._cascade(i + 1)

    def stored(self) -> int:
        return sum(len(r) for r in self.l0) + sum(len(k) for k, _ in self.levels)

    def runs_to_probe(self) -> int:
        return len(self.l0) + sum(1 for k, _ in self.levels if k)


class Tiered:
    def __init__(self):
        self.tiers: list[list[dict]] = []
        self.written = 0

    def flush(self, mem: dict) -> None:
        self.written += len(mem)
        self._add(0, dict(mem))

    def _add(self, i: int, run: dict) -> None:
        while len(self.tiers) <= i:
            self.tiers.append([])
        self.tiers[i].append(run)
        if len(self.tiers[i]) >= T // 2:                    # merge ~equal-size runs (min_threshold-like)
            merged: dict = {}
            for r in self.tiers[i]:                         # oldest -> newest, newest wins
                merged.update(r)
            self.tiers[i] = []
            self.written += len(merged)
            self._add(i + 1, merged)

    def stored(self) -> int:
        return sum(len(r) for tier in self.tiers for r in tier)

    def runs_to_probe(self) -> int:
        return sum(len(t) for t in self.tiers)


def run_lsm(engine, writes: int, universe: int, seed: int = 7) -> dict:
    rng = random.Random(seed)
    mem: dict = {}
    live: set = set()
    peak_space = 0.0
    for seq in range(writes):
        k = rng.randrange(universe)
        mem[k] = seq
        live.add(k)
        if len(mem) >= MEMTABLE:
            engine.flush(mem)
            mem = {}
            peak_space = max(peak_space, engine.stored() / len(live))
    return {"waf": 1 + engine.written / writes,             # +1 for the WAL
            "space_amp": engine.stored() / len(live), "peak_space_amp": peak_space,
            "runs": engine.runs_to_probe()}


# ---------------------------------------------------------------- B. Bloom filters
def mix64(x: int) -> int:                                   # splitmix64 finalizer
    x = (x + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    x = ((x ^ (x >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    x = ((x ^ (x >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    return x ^ (x >> 31)


class Bloom:
    def __init__(self, n: int, bits_per_key: float, blocked: bool):
        self.m = int(n * bits_per_key)
        self.k = max(1, round(bits_per_key * math.log(2)))
        self.blocked = blocked
        self.bits = bytearray((self.m + 7) // 8)

    def _positions(self, key: int):
        h = mix64(key)
        h1, h2 = h & 0xFFFFFFFF, (h >> 32) | 1
        if self.blocked:                                    # all k probes inside one 512-bit (64 B) block
            blocks = max(1, self.m // 512)
            base = (h1 % blocks) * 512
            return [base + (h2 * i + (h1 >> 7)) % 512 for i in range(self.k)]
        return [(h1 + i * h2) % self.m for i in range(self.k)]

    def add(self, key: int) -> None:
        for p in self._positions(key):
            self.bits[p >> 3] |= 1 << (p & 7)

    def __contains__(self, key: int) -> bool:
        return all(self.bits[p >> 3] >> (p & 7) & 1 for p in self._positions(key))


def bloom_fpr(bits_per_key: float, blocked: bool, n: int = 20_000, probes: int = 50_000) -> tuple[float, int]:
    f = Bloom(n, bits_per_key, blocked)
    for key in range(n):
        f.add(key * 2 + 1)                                  # odd keys present
    fp = sum((key * 2) in f for key in range(probes))       # even keys absent
    return fp / probes, f.k


def bloom_analytic(bits_per_key: float, k: int) -> float:
    return (1 - math.exp(-k / bits_per_key)) ** k


# ---------------------------------------------------------------- C. B+tree leaves
LEAF = 64


class Leaves:
    def __init__(self, rightmost_opt: bool):
        self.firsts: list = []
        self.leaves: list[list] = []
        self.opt = rightmost_opt

    def insert(self, key) -> int:
        if not self.leaves:
            self.leaves.append([key])
            self.firsts.append(key)
            return 0
        i = max(0, bisect.bisect_right(self.firsts, key) - 1)
        leaf = self.leaves[i]
        bisect.insort(leaf, key)
        if len(leaf) > LEAF:
            at_end = self.opt and i == len(self.leaves) - 1 and leaf[-1] == key
            cut = LEAF if at_end else len(leaf) // 2       # rightmost-append split keeps old leaf full
            right = leaf[cut:]
            del leaf[cut:]
            self.leaves.insert(i + 1, right)
            self.firsts.insert(i + 1, right[0])
        self.firsts[i] = leaf[0]
        return i

    def fill(self) -> float:
        return sum(map(len, self.leaves)) / (len(self.leaves) * LEAF)


def btree_experiments(n: int = 100_000, seed: int = 3) -> dict:
    rng = random.Random(seed)
    rand_keys = rng.sample(range(10 ** 12), n)
    out = {}
    for label, keys, opt in (("random keys", rand_keys, False), ("sequential, 50/50 split", range(n), False),
                             ("sequential, rightmost-append split", range(n), True)):
        t = Leaves(opt)
        for key in keys:
            t.insert(key)
        out[label] = (t.fill(), len(t.leaves))
    # pages dirtied by the next 1,000 inserts into a 100k-key index
    t_rand, t_seq = Leaves(False), Leaves(True)
    for key in rand_keys:
        t_rand.insert(key)
    for key in range(n):
        t_seq.insert(key)
    touched_rand = {id(t_rand.leaves[t_rand.insert(rng.randrange(10 ** 12))]) for _ in range(1000)}
    touched_seq = {id(t_seq.leaves[t_seq.insert(n + j)]) for j in range(1000)}
    out["dirtied"] = (len(touched_rand), len(touched_seq), len(t_rand.leaves))
    return out


def main() -> None:
    print(f"== A. LSM over 200k keys, 600k writes (memtable {MEMTABLE}, ratio T={T})")
    lv = run_lsm(Leveled(), 600_000, 200_000)
    td = run_lsm(Tiered(), 600_000, 200_000)
    print(f"{'compaction':<14} {'WAF (incl WAL)':>15} {'space amp':>10} {'peak space':>11} {'runs probed':>12}")
    for name, r in (("leveled", lv), ("size-tiered", td)):
        print(f"{name:<14} {r['waf']:>15.2f} {r['space_amp']:>10.2f} {r['peak_space_amp']:>11.2f} {r['runs']:>12}")
    for name, r in (("leveled", lv), ("size-tiered", td)):
        for f in (0.01,):
            print(f"  {name}: point read of a present key with 1% Bloom filters ~ "
                  f"{1 + f * (r['runs'] - 1):.2f} I/Os (vs {r['runs']} without filters)")

    print("\n== B. Bloom filters: analytic vs measured false-positive rate (20k keys, 50k absent probes)")
    print(f"{'bits/key':>8} {'k':>3} {'analytic':>9} {'standard':>9} {'blocked':>9}")
    bl = {}
    for b in (4, 8, 10, 16):
        std, k = bloom_fpr(b, False)
        blk, _ = bloom_fpr(b, True)
        bl[b] = (bloom_analytic(b, k), std, blk)
        print(f"{b:>8} {k:>3} {bl[b][0] * 100:>8.3f}% {std * 100:>8.3f}% {blk * 100:>8.3f}%")
    for p in (0.01, 0.001):
        print(f"bits/key for FPR {p}: -ln(p)/(ln 2)^2 = {-math.log(p) / math.log(2) ** 2:.2f}")
    print(f"1e9 keys at 10 bits/key = {1e9 * 10 / 8 / 2 ** 30:.2f} GiB of filter RAM")

    print("\n== C. B+tree leaves (capacity 64 keys), 100k inserts")
    bt = btree_experiments()
    for label in ("random keys", "sequential, 50/50 split", "sequential, rightmost-append split"):
        fill, leaves = bt[label]
        print(f"  {label:<36} fill {fill * 100:5.1f}%  leaves {leaves:>5}")
    dr, ds, total = bt["dirtied"]
    print(f"  next 1,000 inserts dirty {dr} distinct leaves with random (UUIDv4-like) keys vs {ds} with "
          f"time-ordered (UUIDv7-like) keys; index has {total} leaves")

    # self-test: shapes from theory
    assert lv["waf"] > td["waf"] * 1.5 and td["runs"] > lv["runs"]
    assert lv["space_amp"] < 1.3 and td["peak_space_amp"] > lv["space_amp"]
    for b, (an, std, blk) in bl.items():
        assert abs(std - an) < max(0.004, 0.25 * an), b
        assert blk >= std * 0.9
    assert 0.64 < bt["random keys"][0] < 0.75                       # ~ln 2 (Yao 1978)
    assert bt["sequential, 50/50 split"][0] < 0.53 and bt["sequential, rightmost-append split"][0] > 0.98
    assert dr > 500 and ds <= 17
    print("\nself-test: all assertions passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== A. LSM over 200k keys, 600k writes (memtable 500, ratio T=10)
compaction      WAF (incl WAL)  space amp  peak space  runs probed
leveled                  13.58       1.26        1.26            5
size-tiered               5.01       2.15        2.15           14
  leveled: point read of a present key with 1% Bloom filters ~ 1.04 I/Os (vs 5 without filters)
  size-tiered: point read of a present key with 1% Bloom filters ~ 1.13 I/Os (vs 14 without filters)

== B. Bloom filters: analytic vs measured false-positive rate (20k keys, 50k absent probes)
bits/key   k  analytic  standard   blocked
       4   3   14.689%   14.598%   15.094%
       8   6    2.158%    2.168%    2.436%
      10   7    0.819%    0.792%    1.104%
      16  11    0.046%    0.042%    0.228%
bits/key for FPR 0.01: -ln(p)/(ln 2)^2 = 9.59
bits/key for FPR 0.001: -ln(p)/(ln 2)^2 = 14.38
1e9 keys at 10 bits/key = 1.16 GiB of filter RAM

== C. B+tree leaves (capacity 64 keys), 100k inserts
  random keys                          fill  69.1%  leaves  2260
  sequential, 50/50 split              fill  50.0%  leaves  3124
  sequential, rightmost-append split   fill 100.0%  leaves  1563
  next 1,000 inserts dirty 809 distinct leaves with random (UUIDv4-like) keys vs 17 with time-ordered (UUIDv7-like) keys; index has 2284 leaves

self-test: all assertions passed
```

Reading §A:

| | Leveled | Size-tiered |
|---|---|---|
| WAF (including the WAL's 1×) | **13.6** | **5.0** |
| Space amplification | 1.26 | 2.15 |
| Runs a point read must consider | 5 | 14 |
| I/Os per present-key point read with 1% Bloom filters | **1.04** | **1.13** |

This is the RUM conjecture in four lines:
- The **filters erase most of tiering's read penalty for point lookups.** That is why write-heavy point-lookup
  workloads (Cassandra's sweet spot) tolerate tiering.
- **Range scans still pay all 14 runs.**
- Tiering's **2.15× space** also means a major compaction needs as much free disk as the data. In production that is
  the difference between 50% and 85% disk utilization: a TCO line.

### 2.6 Write stalls: compaction debt is a backpressure signal

An LSM accepts writes at memtable speed and repays them later in compaction. If ingest × WAF exceeds the
compaction bandwidth, **debt accumulates**, and the engine throttles writers. RocksDB defaults, ⚠ verify:

| Trigger | Effect |
|---|---|
| L0 file count ≥ 20 | Slow writes |
| L0 file count ≥ 36 | Stop writes |
| Pending compaction bytes ≥ 64 GB | Slow writes |
| Pending compaction bytes ≥ 256 GB | Stop writes |
| All memtables full | Stall until a flush completes |

The capacity equation an L7 writes down:

$$\text{disk write bandwidth needed} = \text{ingest} \times \text{WAF} \qquad\text{e.g. } 100\ \text{MB/s} \times 14 = 1.4\ \text{GB/s}$$

1.4 GB/s is most of a datacenter NVMe drive's sustained write bandwidth. It also wears the drive in months (Folder 01
file 02 §3.3: 107 days on 7.68 TB TLC at WAF 10 × FTL 2.5). So the levers, in order:
1. **Reduce WAF:**
   - tiered or universal compaction for write-heavy data;
   - larger memtables (fewer, bigger L0 files);
   - **key-value separation** for large values, so compaction moves only small keys and pointers (WiscKey, FAST
     2016; RocksDB BlobDB; TiKV Titan).
2. **Rate-limit compaction I/O** (RocksDB `rate_limiter`) so foreground reads keep their p99, and alert on pending
   compaction bytes *before* the slowdown trigger.
3. **Shard so no single engine's compaction bandwidth is the bottleneck.** More, smaller LSM instances per host
   compact in parallel.

### 2.7 Deletes and tombstones

- A delete in an LSM is a **write**: a tombstone that must outlive every older version of the key in lower levels.
- Range deletes are range tombstones.
- Two production failure modes:
  - **Tombstone pile-ups.** Queue-like tables (insert, consume, delete) leave scans walking thousands of tombstones.
    Cassandra warns at 1,000 tombstones per read and fails at 100,000 (defaults, ⚠ verify). The fix: don't model
    queues as tables, use TWCS with TTL, or partition by time bucket so whole partitions drop.
  - **Resurrection.** In leaderless systems, a tombstone may be purged after `gc_grace_seconds` (10 days by default
    in Cassandra) on replicas that never received it, and the deleted value returns. Repair must run inside the grace
    window. An *operational* invariant becomes a *correctness* invariant.

---

## 3. Bloom filters and their successors

### 3.1 The math

For $n$ keys, $m$ bits and $k$ hash functions:

$$\text{FPR} = \left(1 - e^{-kn/m}\right)^k, \qquad k^* = \frac{m}{n}\ln 2, \qquad \frac{m}{n} = \frac{-\ln p}{(\ln 2)^2} \approx 1.44\log_2(1/p)$$

| Target FPR | Bits per key |
|---|---|
| 1% | **9.6** |
| 0.1% | 14.4 |

Each 10× improvement costs ~4.8 bits per key. **10⁹ keys at 10 bits/key = 1.16 GiB of RAM.** For a 10 TB LSM with
100-byte keys and values, filters are ~1% of data size, but 100% of them should be in RAM.

### 3.2 Measured vs analytic (§B of the output)

The standard filter matches the formula within sampling error at 4, 8, 10 and 16 bits per key.

The **blocked** filter puts all $k$ probes in one 64-byte cache line, so a probe costs one DRAM miss instead of $k$:
~115 ns vs ~800 ns (Folder 01 file 02 §2). It pays in FPR, a little at 8–10 bits/key (1.10% vs 0.79% at 10) and more
at 16 bits/key (0.23% vs 0.04%), because cache-line occupancy varies. RocksDB's newer "fast local" Bloom format
makes exactly this trade (⚠ verify the version defaults).

### 3.3 The menu

| Filter | Space vs Bloom at equal FPR | Supports delete | Notes |
|---|---|---|---|
| Bloom (standard) | 1× | No | Simple; $k$ random memory accesses |
| Blocked Bloom | ~1.05–1.2× | No | One cache miss per probe |
| **Ribbon** (Dillinger & Walzer 2021) | **~0.7×** | No | Built at construction time, static. RocksDB supports it for SST filters |
| Cuckoo (Fan et al. 2014) | ~0.7–1× at low FPR | **Yes** | Fingerprints in buckets; good for dynamic sets |
| Xor / binary fuse (Graf & Lemire 2020–22) | ~0.8× | No | Static; very fast queries |
| Monkey allocation (Dayan et al. 2017) | Same bits, lower total cost | — | Gives *deeper* levels fewer bits/key and shallower ones more. Minimizes the sum of FPRs across levels, since most data sits in the last level |

---

## 4. Choosing an engine

| Workload signal | Lean | Why |
|---|---|---|
| Read-mostly, point and range, data ≲ 10× RAM | **B+tree** | ~1 I/O per lookup; range scans are sequential leaf walks |
| Write-heavy (≥ 30–50% writes), point lookups | **LSM, tiered/universal** | Sequential writes, low WAF, filters fix point reads |
| Write-heavy *and* range scans | **LSM, leveled** (or lazy leveling) | Fewer runs to merge per scan |
| Large values (≥ 1 KB) with frequent updates | **LSM + key-value separation** | Compaction moves only keys |
| Time-series with TTL | **LSM, time-window** | Whole windows expire as files |
| Strict p99.9 read latency with steady writes | **B+tree**, or LSM with compaction rate-limiting and headroom | Compaction and L0 stalls are LSM tail risks |
| SSD endurance is binding (QLC, write-heavy) | **LSM tiered + FDP/whole-file placement** | Minimizes app × FTL amplification together |
| Strong in-place secondary-index maintenance | **B+tree** | LSM secondary indexes need read-before-write or lazy cleanup |

---

## 5. L5 vs L6 vs L7

| Topic | L5 (Senior) | L6 (Staff) | L7 (Principal) |
|---|---|---|---|
| Engine choice | "LSM is for writes, B-tree for reads" | Names the workload signals; picks a compaction strategy; knows Bloom filters fix point reads but not scans | States the RUM trade explicitly; computes WAF × ingest = required disk bandwidth; multiplies by the FTL's WAF for endurance and drive TCO |
| Keys | Auto-increment or UUID | Knows random PKs hurt B-trees (fill, buffer pool) | Chooses the key by engine *and* distribution: sequential for a local B-tree, hashed prefix for a range-partitioned cluster |
| Tail latency | — | Compaction and checkpoint spikes; rate-limiting compaction | Compaction debt as a backpressure SLI; stall triggers alerted before they fire; capacity headroom sized from the WAF equation |
| Deletes | "Delete the row" | Tombstones, TTL, compaction | Tombstone resurrection as a correctness invariant tied to repair cadence; queue-on-LSM anti-pattern |
| Memory | Block cache size | Filters and index blocks pinned in RAM | Filter bits per level (Monkey), Ribbon vs Bloom RAM cost at 10⁹+ keys, the five-minute rule for block-cache sizing |

---

## 6. Bar-raiser probing chains

### Chain A: "Your Cassandra cluster's p99 read latency spikes every few minutes."

1. **L5:** "Add nodes."
2. **Probe:** "CPU is fine. What's happening?" **L6:**
   - "Compaction. Big STCS compactions saturate disk I/O."
   - "Check pending compactions and SSTables per read. Switch hot tables to LCS, or throttle compaction throughput."
3. **Probe:** "We switched to LCS, and now writes stall during peaks." **L7:**
   - "LCS raised WAF from ~5 to ~14, so ingest × WAF now exceeds disk bandwidth at peak."
   - Choose per table: LCS for read-heavy reference data, UCS/STCS for the write-heavy event table.
   - Separate large values.
   - Size disk bandwidth to peak ingest × WAF with headroom.
   - Alert on pending compaction bytes trending, not on stalls.
   - "And look for tombstone-heavy reads; they look like compaction pain."

### Chain B: "We migrated our PK from BIGINT to UUIDv4 and the database got 5× slower."

1. **L5:** "UUIDs are bigger, so indexes are bigger."
2. **Probe:** "Size grew 2×; latency grew 5×." **L6:** "Random inserts: pages split everywhere, fill drops to ~69%,
   and the working set becomes the whole index, so the buffer pool misses."
3. **Probe:** "We need globally unique IDs without coordination." **L7:**
   - "UUIDv7 or Snowflake-style IDs keep B-tree locality."
   - "But if this table is range-partitioned across nodes, time-ordered keys put 100% of writes on one range. So
     prefix a hash bucket of the tenant, or use hash partitioning, and keep time order *within* the partition."
   - Pick by topology, and quantify: in the lab, 809 vs 17 leaves dirtied per 1,000 inserts.

### Chain C: "Design the storage engine for a 1 PB write-heavy event store."

1. **L5:** "Use Cassandra."
2. **Probe:** "Writes are 2 GB/s, reads are mostly 'last 24 h by device'." **L6:** "LSM with time-window compaction
   keyed by (device, day); TTL drops whole windows; Bloom filters for point lookups."
3. **Probe:** "Hardware budget is fixed. Does it fit, and how long do drives last?" **L7:**
   - Compute: 2 GB/s × WAF ~2 (TWCS) × RF 3 = 12 GB/s of device writes fleet-wide.
   - At FTL WAF ~1.1 with whole-file deletes, divide by the per-drive sustained write rate to get the drive count.
   - Drive life comes from TBW: the endurance-per-dollar comparison usually picks TLC over QLC for this tier.
   - Cold windows go to object storage via tiered storage after 7 days.
   - The design sentence: "compaction strategy is chosen so the SSD's FTL never garbage-collects live data".

---

## 7. Invariants checklist

- [ ] The workload's read/update/space priority is stated (RUM), and the engine follows from it.
- [ ] B+tree: the PK is ordered for local locality; fill factor and HOT/`fillfactor` are set for update-heavy tables;
      torn-page protection is counted in WAF.
- [ ] LSM: the compaction strategy is chosen per table; WAF × ingest ≤ sustained disk write bandwidth, with
      headroom; pending-compaction bytes are an SLI.
- [ ] Filters are sized (bits/key per level), and their RAM is budgeted.
- [ ] Range-scan cost (runs merged) is acknowledged; prefix filters are used where scans are prefix-bounded.
- [ ] Tombstones: TTL/TWCS for expiring data, no queue-on-LSM, repair inside the grace window.
- [ ] End-to-end amplification (app × FTL) is translated into drive endurance and cost.

---

## 8. References

- R. Bayer, E. McCreight. *Organization and Maintenance of Large Ordered Indexes.* Acta Informatica 1(3), 1972.
- D. Comer. *The Ubiquitous B-Tree.* ACM Computing Surveys 11(2), 1979.
- A. C. Yao. *On Random 2–3 Trees.* Acta Informatica 9, 1978 (the ln 2 ≈ 69% fill result).
- P. O'Neil, E. Cheng, D. Gawlick, E. O'Neil. *The Log-Structured Merge-Tree (LSM-Tree).* Acta Informatica 33(4),
  1996.
- M. Athanassoulis et al. *Designing Access Methods: The RUM Conjecture.* EDBT 2016.
- N. Dayan, M. Athanassoulis, S. Idreos:
  - *Monkey: Optimal Navigable Key-Value Store.* SIGMOD 2017.
  - Dayan & Idreos, *Dostoevsky: Better Space-Time Trade-Offs for LSM-Tree Based Key-Value Stores via Adaptive
    Removal of Superfluous Merging.* SIGMOD 2018.
- L. Lu et al. *WiscKey: Separating Keys from Values in SSD-Conscious Storage.* FAST 2016.
- P. Raju et al. *PebblesDB: Building Key-Value Stores using Fragmented Log-Structured Merge Trees.* SOSP 2017.
- R. Sears, R. Ramakrishnan. *bLSM: A General Purpose Log Structured Merge Tree.* SIGMOD 2012.
- B. Bloom. *Space/Time Trade-offs in Hash Coding with Allowable Errors.* CACM 13(7), 1970.
- F. Putze, P. Sanders, J. Singler. *Cache-, Hash- and Space-Efficient Bloom Filters.* WEA 2007.
- P. C. Dillinger, S. Walzer. *Ribbon Filter: Practically Smaller than Bloom and Xor.* arXiv:2103.02515, 2021.
- B. Fan, D. Andersen, M. Kaminsky, M. Mitzenmacher. *Cuckoo Filter: Practically Better Than Bloom.* CoNEXT 2014.
- T. Graf, D. Lemire. *Xor Filters: Faster and Smaller Than Bloom and Cuckoo Filters.* JEA 2020.
- RocksDB wiki: *Leveled Compaction*, *Universal Compaction*, *Write Stalls*, *RocksDB Bloom Filter*, *BlobDB*
  (github.com/facebook/rocksdb/wiki).
- Apache Cassandra documentation: compaction (STCS, LCS, TWCS, UCS), tombstones and `gc_grace_seconds`.
