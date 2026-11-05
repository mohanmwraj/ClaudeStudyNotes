# 01 · TSDB Head Block, WAL, M-mapped Chunks and Gorilla/XOR Compression

> **Folder 01: Prometheus 3 TSDB Internals and Cardinality Physics. File 1 of 4.**
> Pinned to **Prometheus v3.15.1** (released 2026-10-21). Source was read at git tag `v3.15.1`. The **v3.13 LTS** line is noted where it differs.
> Evidence labels: **[D]** documented, or read in the pinned source. **[M]** measured by a listing in this file; the listings are deterministic and the folder gate re-runs them. **[E]** estimate or model, with its assumptions stated. **⚠** version-sensitive, so re-verify on upgrade.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `xor_chunk.py` | Bit-exact port of `bstream.go`, `xor.go` and `xor2.go`, with a bit-by-bit trace of a real counter, the bucket-edge asymmetry, XOR vs XOR2 on 8 workloads, and a 48k-sample adversarial round trip | ~2 s |
| L2 `wal_head_lab.py` | WAL Series/Samples records, 32 KiB page fragmentation with CRC32C and snappy, the `appendPreprocessor` chunk-cutting algorithm, the head-compaction/WAL-checkpoint timeline, and a structural head-memory model | ~3 s |

**Verification.** Both listings are stdlib-only Python 3.14. Their outputs are embedded verbatim and regenerated and diffed by the folder gate.
- L1 is a line-for-line port of `tsdb/chunkenc` at v3.15.1. Its decoder is written from the format spec, not from encoder state, so the round trip is a genuine cross-check.
- File 02's L3 uses L1 on a real block written by Prometheus 2.0.0 (`tsdb/testdata/index_format_v1`, shipped here under `fixtures/`). It verifies every CRC32C, matches the samples asserted by Prometheus's own Go test, and re-encodes all 102 chunks byte-for-byte.
- Running the downloaded Prometheus 3.15.1 binary was not permitted in the build environment, so no number in this file comes from a live server. Treat [M] figures as properties of the ported code, and [E] figures as models to calibrate against your own `prometheus_tsdb_*` metrics.

---

## 0. Orientation

**What this file answers.** Where a sample lives from the moment a scrape returns until it is deleted by retention. What each hop costs in bytes, in memory and in recovery time. Which of those costs an architect can actually move.

**The mental model in one paragraph.** A Prometheus server is a single-node, append-mostly time-series database with an LSM-like lifecycle:
1. A commit is written to a **write-ahead log** (WAL) for durability.
2. It is then applied to the in-memory **head block**. The head block is a lock-striped hash map of series, an inverted index, and one open compressed chunk per series.
3. Full chunks are flushed to **m-mapped files** (`chunks_head/`) so they leave the Go heap.
4. Roughly every 2 h, the oldest 2 h of the head is persisted as an **immutable block**: index + chunks + tombstones + meta.json.
5. Blocks are merged into larger blocks on a ×3 ladder (2 h → 6 h → 18 h → …). The ladder is capped at `min(31d, retention/10)`.
6. Whole blocks are deleted when they fall out of retention.

Every capacity question about Prometheus is a question about one of those five boxes.

**Release context [D].**

| Release | Date | TSDB-relevant change |
|---|---|---|
| 3.0.0 | 2024-11-14 | UTF-8 names by default, new UI, OTLP receiver flag, left-open range selectors (Folder 02) |
| 3.5 LTS | 2025-07-14 | First 3.x long-term-support line |
| 3.8.0 | 2025-12-02 | Native histograms **stable**, opt in per scrape via `scrape_native_histograms` |
| 3.9.0 | 2026-01-07 | `--enable-feature=native-histograms` becomes a no-op |
| 3.10.0 | 2026-02-26 | Experimental `stale_series_compaction_threshold` (early eviction of stale series) |
| 3.11.0 | 2026-04-02 | Experimental `st-storage` (start timestamps) and `xor2-encoding`; `storage.tsdb.retention.percentage` |
| 3.12.0 | 2026-05-28 | Constant-time head-chunk lookup; per-stripe mmap skipping (CPU) |
| 3.13 LTS | 2026-07-01 | `storage.tsdb.chunk_encoding.floats: xor\|xor2` config field |
| 3.15.0 | 2026-09-25 | **XOR2 stable** (the flag is deprecated; select it in config); `--auto-gomemlimit.refresh-interval`; OpenMetrics 2.0 scrape (experimental) |
| 3.15.1 | 2026-10-21 | Security rebuild (Go 1.27.3) |

**Prerequisites.** Binary/varint encodings and Go's memory model at a high level. Folder 02 is the PromQL companion; file `02-inverted-index-postings-lists-and-high-cardinality-oom-mechanics.md` in this folder owns the index.

---

## 1. First principles: the write path from scrape to block

### 1.1 One commit, end to end

```text
 scrape loop (one goroutine per target, offset = hash(target) mod interval)
   │  parse exposition  ──►  metric_relabel_configs  ──►  sample_limit / label_limit checks
   ▼
 headAppender.Append(ref, lset, t, v)        (buffered in the appender, nothing visible yet)
   │   - series lookup: stripeSeries.getByHash(hash(lset))   lock-striped, 16,384 stripes
   │   - new series:    memSeries alloc, MemPostings.Add (one append per label pair)
   ▼
 headAppender.Commit()
   │ 1. WAL: Series records (new series only) ─► Samples / Histograms / Exemplars / Metadata
   │         one write(2) per batch (page flush); fsync only when a 128 MiB segment closes
   │ 2. per series: appendPreprocessor ─► maybe cut a new head chunk ─► XOR/XOR2 append
   │ 3. isolation: the append ID is closed, so queries now see the batch atomically
   ▼
 memSeries.headChunks (open chunk, Go heap)
   │  cut at 120 samples / predicted end time / 2h range boundary
   ▼
 chunks_head/00000N  (full chunks written + m-mapped; leave the Go heap, live in page cache)
   │  every minute: if head.maxt - head.mint > 1.5 × 2h  ──► compact oldest 2h
   ▼
 01K...ULID/ { meta.json, index, chunks/000001.., tombstones }   immutable block
   │  leveled compaction 2h → 6h → 18h → 54h …  (≤ min(31d, retention/10))
   ▼
 deleted when maxt < now − retention.time   (or oldest first when size/percentage exceeded)
```

Three properties of this pipeline drive almost every production incident.

1. **The WAL is the only durable copy of the head [D].** `WL.Log()` writes one page flush per batch (`final && w.page.alloc > 0`). `fsync` is issued only when a segment is rotated (`nextSegment`, done asynchronously for the previous segment) or closed.
   - A **process** kill (OOMKill, SIGKILL) loses nothing that reached `write(2)`, because the bytes sit in the kernel page cache.
   - A **node** crash can lose or tear the tail of the current segment. On restart, the WAL reader stops at the first CRC mismatch and the WAL is repaired by truncating there (`prometheus_tsdb_wal_corruptions_total` increments).
2. **Memory is proportional to *series*, not samples [D].** A sample costs about 1–2 bytes once compressed. A series costs a `memSeries` struct, its label string, postings entries, map entries and an open chunk buffer. Ingest rate is cheap; cardinality is not (File 02).
3. **Restart time is proportional to WAL size [D].** Replay re-reads the checkpoint plus every remaining segment and rebuilds the head. With default 2 h blocks the head spans 1–3 h of data, so worst-case replay is ~3 h of samples. `--enable-feature=memory-snapshot-on-shutdown` writes a chunk snapshot on clean shutdown, so a clean restart replays only the WAL written after the snapshot.

### 1.2 The data directory

```text
data/                                     (--storage.tsdb.path, default "data/")
├── lock                                  single-writer flock (disable: --storage.tsdb.no-lockfile)
├── queries.active                        mmap'd active-query log (crash forensics)
├── wal/
│   ├── 00000231 … 00000248               128 MiB segments of 32 KiB pages (snappy default)
│   └── checkpoint.00000230/00000000      Series of live series + samples newer than head mint
├── wbl/                                  out-of-order WAL (only if out_of_order_time_window > 0)
├── chunks_head/
│   └── 000045 …                          head chunks, magic 0x0130BC91, m-mapped, each chunk
│                                         carries series ref + mint + maxt (no index exists yet)
├── chunk_snapshot.000248.0000131072/     (memory-snapshot-on-shutdown)
└── 01JC9…ULID/                           one persisted block
    ├── meta.json                         ulid, minTime, maxTime, stats, compaction.level/sources
    ├── index                             magic 0xBAAAD700, format v2 (File 02)
    ├── chunks/000001 …                   ≤ 512 MiB segments, magic 0x85BD40DD
    └── tombstones                        deletions not yet compacted away
```

### 1.3 The head in memory: `stripeSeries` and `memSeries`

```text
 stripeSeries (DefaultStripeSize = 1<<14 = 16,384)
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │ series[ref & (size-1)] : map[HeadSeriesRef]*memSeries      lookup by ID      │
 │ hashes[hash & (size-1)]: seriesHashmap{unique map[uint64]*memSeries,         │
 │                                        conflicts map[uint64][]*memSeries}    │
 │ locks[i]               : stripeLock{sync.RWMutex; _ [40]byte}  ◄─ pad so two │
 │                          locks never share a 64-byte cache line              │
 │ mmapReady[i]           : padded atomic int32 (3.12+: skip clean stripes)     │
 └──────────────────────────────────────────────────────────────────────────────┘
          │
          ▼
 memSeries (176 B on 64-bit: the field list at v3.15.1 sums to exactly the 176 B size class)
 ┌─────────────────────────────┬────────────────────────────────────────────────┐
 │ ref, meta*, shardHash       │ immutable after creation (lock-free reads)     │
 │ sync.Mutex                  │ guards everything below                        │
 │ lset (stringlabels: ONE     │ len-prefixed name/value pairs, 1-byte lengths  │
 │   flat string per series)   │ for ≤254 B; no cross-series interning          │
 │ mmappedChunks []*mmappedChunk│ refs into chunks_head (32 B each + pointer)   │
 │ headChunks *memChunk        │ open chunk (+ not-yet-m-mapped predecessors)   │
 │ firstChunkID, ooo*          │ chunk-ID arithmetic; OOO head chunk if enabled │
 │ nextAt                      │ timestamp at which to cut the next chunk       │
 │ state (pending commits +    │ packed flags; headChunkCount in the same word  │
 │   flags), headChunkCount    │                                                │
 │ lastValue / lastHistogram*  │ duplicate-sample detection                     │
 │ app chunkenc.Appender       │ the open chunk's appender (holds t, v, tDelta, │
 │                             │ leading/trailing window)                       │
 │ txs *txRing                 │ isolation bookkeeping                          │
 └─────────────────────────────┴────────────────────────────────────────────────┘
```

Why the stripes [D]:
- Appends from thousands of scrape goroutines hit random series. A single map lock would serialize ingestion.
- With 16,384 stripes, two appenders collide only if their refs or hashes map to the same stripe.
- The 40-byte pad after each `RWMutex` (24 B) makes each lock exactly 64 bytes. Adjacent locks therefore never false-share a cache line.
- The `hashes` map is keyed by a 64-bit label hash. Hash collisions go into a separate `conflicts` map, so correctness never depends on hash uniqueness.

`HeadSeriesRef` is a monotonically increasing counter. That single fact makes `MemPostings` cheap: each label pair's postings list grows by appending a larger ref, so it stays sorted with no insertion work (File 02).

### 1.4 Gorilla, and what Prometheus changed

Facebook's Gorilla paper (VLDB 2015) compresses `(timestamp, float64)` pairs in two independent streams.
- **Timestamps** are encoded as delta-of-delta (`dod = (tₙ − tₙ₋₁) − (tₙ₋₁ − tₙ₋₂)`). Regular scraping makes `dod = 0` the common case, and that costs 1 bit.
- **Values** are XOR-ed with the previous value. For slowly changing floats, the XOR has long runs of leading and trailing zeros, so only the "meaningful" middle bits are stored. A previous window of leading/trailing zeros can be reused for free.

Prometheus adopted this in `tsdb/chunkenc/xor.go` with millisecond timestamps. Gorilla's second-resolution buckets (7/9/12/32 bits) were widened to **14/17/20/64 bits**.

**XOR chunk layout [D]** (`tsdb/docs/format/chunks.md`):

```text
 byte 0-1      num_samples <uint16, big-endian>      (max 65,535; head cuts far earlier)
 sample 0      t0 <varint (zig-zag)>   v0 <64 raw bits>
 sample 1      Δt1 <uvarint>           v1 <varbit_xor>
 sample n≥2    dod_n <varbit_ts>       vn <varbit_xor>
 tail          0-7 padding bits to the byte boundary

 varbit_ts:  '0'                    dod == 0                         1 bit
             '10'   + 14 bits       -8191 ≤ dod ≤ 8192               16 bits
             '110'  + 17 bits       -65535 ≤ dod ≤ 65536             20 bits
             '1110' + 20 bits       -524287 ≤ dod ≤ 524288           24 bits
             '1111' + 64 bits       anything else                    68 bits
 varbit_xor: '0'                    value bits identical             1 bit
             '10'  + sig bits       reuse previous leading/trailing window
             '11'  + 5b leading + 6b sigbits + sig bits   new window (sigbits 64 stored as 0)
```

Three details that are easy to miss in an interview and that L1 reproduces bit-for-bit:

1. **The dod ranges are asymmetric.** `bitRange(x, n)` accepts `-(2ⁿ⁻¹−1) ≤ x ≤ 2ⁿ⁻¹`, and the reader sign-extends only when `bits > 2ⁿ⁻¹`. So `+8192` fits the 14-bit bucket but `-8192` does not.
2. **Leading zeros are clamped to 31** so they fit in 5 bits. A tiny XOR with 40 leading zeros is stored as "31 leading zeros", paying 9 extra significant bits.
3. **The chunk is a `bstream`, not a byte stream.** Varints are written with `writeByte` at whatever bit offset the stream is at. Prometheus 2.0's `writeByte` always appended a spill byte, while v3.x appends a byte only when unaligned. So a one-sample chunk is 12 bytes in a 2.0 block and 11 bytes today (L1 §4, and File 02's real-block check).

### 1.5 XOR2: the 3.15 stable encoding

XOR2 (`EncXOR2 = 4`) became stable in 3.15. It is opt-in via `storage.tsdb.chunk_encoding.floats: xor2`, and is implied by `--enable-feature=st-storage`. It keeps the XOR value window but changes three things [D]:

```text
 byte 0-1   num_samples <uint16>
 byte 2     st_header: bit7 firstSTKnown, bits6-0 firstSTChangeOn   (0x00 = no start timestamps)
 samples 0,1   as XOR (value of sample 1 uses the XOR2 value code below)
 sample n≥2, JOINT timestamp+value control:
   '0'            dod == 0 AND value unchanged                     1 bit total
   '10'  +'0'|'1' dod == 0, value changed: reuse | new window
   '110' +13 bits dod in [-4096, 4095]   (prefix+dod = exactly 2 bytes) then value code
   '1110'+20 bits dod in [-524288, 524287] (exactly 3 bytes)       then value code
   '11110'+64     anything else                                    then value code
   '11111'        dod == 0, value is the staleness marker          5 bits, no value field
 value code (dod ≠ 0): '0' same, '10' reuse window, '110' new window, '111' stale NaN
 optional per-sample start-timestamp delta (putVarbitInt) once ST changes
```

The design intent, in the source comments' own words, is "byte-packed dod encoding for efficient appending" plus room for start timestamps. L1 §3 measures where the bytes actually change [M]:

- **Constant series** (`up`, `*_info`, config gauges, most `kube_*_status_*`) shrink from **0.40 to 0.28 B/sample (−29%)**. A sample with `dod = 0` and an unchanged value costs 1 bit instead of 2.
- **Stale markers** cost 5 bits instead of a full XOR window. Because XOR2 keeps the value **baseline** across a stale NaN, the next real value does not pay for XOR-ing against NaN either.
- **Everything else is a wash** (±1%). The 13-bit timestamp bucket costs the same 16 bits as XOR's 14-bit one. A new value window costs one extra prefix bit when `dod ≠ 0`.
- **New edge:** XOR2's 13-bit bucket covers only ±4096 ms, so a dod between 4096 and 8192 ms costs 24 bits in XOR2 versus 16 in XOR.

The fleet-level win is therefore roughly *(share of constant series) × 30% of their chunk bytes*, plus the per-chunk +1 header byte. On a typical Kubernetes fleet where 40–60% of series are flat over a 30-minute chunk, that is roughly 5–10% of chunk bytes [E]. Measure your own constant share before promising more.

> **⚠ Compatibility trap.** Chunks written as XOR2 cannot be read by older Prometheus versions or by tools that read blocks directly, such as an older Thanos sidecar or store gateway. Downgrading requires deleting the affected blocks. Roll XOR2 out only after every block reader in the path supports it.

### 1.6 What a sample costs: the worked bit trace

L1 §1 encodes five samples of a request counter scraped every 15 s, where the fourth scrape is 3 ms late. 3 ms is more than the 2 ms alignment tolerance, so the timestamp is *not* snapped back to the grid. The trace shows every field. Read it as:
- Sample 0 costs 6 + 8 bytes: a millisecond epoch is a 6-byte varint.
- Sample 1 pays a 2-byte Δ uvarint and opens the value window (lead = 11, sig = 11 for these integers).
- Sample 2 is `dod = 0` (1 bit) + reuse window (2 + 11 bits).
- Sample 3 pays a 16-bit dod for the late scrape, then '0' for the unchanged value.
- Sample 4 pays a second 16-bit dod (−3, to get back on grid) and a reused window.

Two 16-bit dods for one late scrape is why `--scrape.adjust-timestamps` exists (§1.8).

<!-- listing:xor_chunk.py -->
```python
"""xor_chunk.py - bit-exact Python port of the Prometheus v3.15.1 float chunk codecs (XOR and XOR2).

Ported line by line from tsdb/chunkenc/{bstream.go, xor.go, xor2.go} at tag v3.15.1:
  * BStream mirrors bstream.go (writeBit / writeByte / writeBits), plus the Prometheus 2.0
    writeByte variant (legacy=True) that always appended a trailing free byte.
  * xor_encode() mirrors xorAppender.Append + xorWrite: dod buckets '0' / '10'+14 / '110'+17 /
    '1110'+20 / '1111'+64 with the ASYMMETRIC bitRange (-(2^(n-1)-1) <= dod <= 2^(n-1)).
  * xor2_encode() mirrors xor2Appender.Append (no start timestamps, st_header 0x00) + encodeJoint
    + writeVDelta: joint control '0' / '10' / '110'+13 / '1110'+20 / '11110'+64 / '11111'
    (stale NaN at dod=0), with a value baseline that ignores stale markers.
  * The decoders follow tsdb/docs/format/chunks.md and the iterators' sign rules; they do not
    replay encoder state, so the round trip is a real cross-check.
Stdlib only, deterministic (fixed seeds), no I/O. argv is ignored (the harness passes the
target Markdown path). Other listings import xor_decode/xor_encode from this file.

Usage: python xor_chunk.py [target.md]
"""
import random
import struct
import sys

STALE_NAN_BITS = 0x7FF0000000000002  # model/value.StaleNaN
MASK64 = (1 << 64) - 1


def f2b(v: float) -> int:
    return struct.unpack(">Q", struct.pack(">d", v))[0]


def b2f(b: int) -> float:
    return struct.unpack(">d", struct.pack(">Q", b & MASK64))[0]


def is_stale(v: float) -> bool:
    return f2b(v) == STALE_NAN_BITS


STALE_NAN = b2f(STALE_NAN_BITS)


# ----------------------------------------------------------------------------- bit stream
class BStream:
    """bstream.go: `count` = free right-most bits in the last byte of `stream`."""

    def __init__(self, header_bytes: int, legacy: bool = False, trace: bool = False):
        self.stream = bytearray(header_bytes)
        self.count = 0
        self.legacy = legacy
        self.trace = [] if trace else None  # (label, bitstring) segments, in write order

    def seg(self, label, value, nbits):
        if self.trace is not None:
            self.trace.append((label, format(value & ((1 << nbits) - 1), f"0{nbits}b")))

    def write_bit(self, bit: int):
        if self.count == 0:
            self.stream.append(0)
            self.count = 8
        if bit:
            self.stream[-1] |= 1 << (self.count - 1)
        self.count -= 1

    def write_byte(self, byt: int):
        byt &= 0xFF
        if self.legacy:  # Prometheus 2.0: append 0 when aligned, then ALWAYS append the spill byte
            if self.count == 0:
                self.stream.append(0)
                self.count = 8
            self.stream[-1] |= byt >> (8 - self.count)
            self.stream.append((byt << self.count) & 0xFF)
        elif self.count == 0:  # v3.15.1: aligned bytes are appended as-is
            self.stream.append(byt)
        else:
            self.stream[-1] |= byt >> (8 - self.count)
            self.stream.append((byt << self.count) & 0xFF)

    def write_bits(self, u: int, nbits: int):
        u = (u << (64 - nbits)) & MASK64
        while nbits >= 8:
            self.write_byte(u >> 56)
            u = (u << 8) & MASK64
            nbits -= 8
        while nbits > 0:
            self.write_bit(u >> 63)
            u = (u << 1) & MASK64
            nbits -= 1

    def put(self, label, value, nbits):  # write + trace one logical field (may exceed 64 bits)
        self.seg(label, value, nbits)
        value &= (1 << nbits) - 1
        if nbits > 64:  # e.g. a new value window: 2-3 prefix + 5 + 6 + up to 64 payload bits
            self.write_bits(value >> 64, nbits - 64)
            value, nbits = value & MASK64, 64
        self.write_bits(value, nbits)

    def put_bytes(self, label, raw: bytes):
        self.seg(label, int.from_bytes(raw, "big"), 8 * len(raw))
        for b in raw:
            self.write_byte(b)


class BReader:
    def __init__(self, data: bytes, offset_bytes: int):
        self.data, self.pos = data, offset_bytes * 8

    def bits(self, n: int) -> int:
        v = 0
        for _ in range(n):
            byte = self.data[self.pos >> 3]
            v = (v << 1) | ((byte >> (7 - (self.pos & 7))) & 1)
            self.pos += 1
        return v

    def uvarint(self) -> int:
        x = s = 0
        while True:
            b = self.bits(8)
            x |= (b & 0x7F) << s
            if b < 0x80:
                return x
            s += 7

    def varint(self) -> int:
        ux = self.uvarint()
        return -(ux >> 1) - 1 if ux & 1 else ux >> 1


def put_uvarint(x: int) -> bytes:
    out = bytearray()
    x &= MASK64
    while x >= 0x80:
        out.append((x & 0x7F) | 0x80)
        x >>= 7
    out.append(x)
    return bytes(out)


def put_varint(x: int) -> bytes:  # Go binary.PutVarint (zig-zag)
    ux = (x << 1) & MASK64
    if x < 0:
        ux = ~ux & MASK64
    return put_uvarint(ux)


def bit_range(x: int, nbits: int) -> bool:  # xor.go bitRange: note the asymmetry
    return -((1 << (nbits - 1)) - 1) <= x <= (1 << (nbits - 1))


def lead_trail(delta: int):
    lead = 64 - delta.bit_length()
    trail = (delta & -delta).bit_length() - 1
    return min(lead, 31), trail  # "Clamp number of leading zeros to avoid overflow"


def put_window(bs, delta, state, reuse, new, label):
    """Shared leading/trailing-zero window logic of xorWrite / writeVDelta / ...KnownNonZero.
    reuse/new are (prefix, prefix_bits) written before the payload."""
    nl, nt = lead_trail(delta)
    lead, trail = state
    if lead != 0xFF and nl >= lead and nt >= trail:
        sig = 64 - lead - trail
        p, pl = reuse
        bs.put(f"{label} reuse(lead={lead},sig={sig})", (p << sig) | (delta >> trail), pl + sig)
        return state
    sig = 64 - nl - nt
    p, pl = new
    bs.put(f"{label} new(lead={nl},sig={sig})",
           (((p << 5 | nl) << 6 | (sig & 0x3F)) << sig) | (delta >> nt), pl + 11 + sig)
    return (nl, nt)


# ----------------------------------------------------------------------------- XOR (EncXOR = 1)
def xor_encode(samples, legacy=False, trace=False):
    bs = BStream(2, legacy, trace)
    t_prev = v_prev = None
    t_delta, win = 0, (0xFF, 0)
    for i, (t, v) in enumerate(samples):
        if i == 0:
            bs.put_bytes("ts_0 varint", put_varint(t))
            bs.put("v_0 float64", f2b(v), 64)
        else:
            td = t - t_prev
            if i == 1:
                bs.put_bytes("ts_1 delta uvarint", put_uvarint(td))
            else:
                dod = td - t_delta
                if dod == 0:
                    bs.put("dod '0'", 0, 1)
                elif bit_range(dod, 14):
                    bs.put("dod '10'+14b", (0b10 << 14) | (dod & 0x3FFF), 16)
                elif bit_range(dod, 17):
                    bs.put("dod '110'+17b", (0b110 << 17) | (dod & 0x1FFFF), 20)
                elif bit_range(dod, 20):
                    bs.put("dod '1110'+20b", (0b1110 << 20) | (dod & 0xFFFFF), 24)
                else:
                    bs.put("dod '1111'", 0b1111, 4)
                    bs.put("dod 64b", dod & MASK64, 64)
            t_delta = td
            delta = f2b(v) ^ f2b(v_prev)
            if delta == 0:
                bs.put("v '0' same", 0, 1)
            else:
                win = put_window(bs, delta, win, (0b10, 2), (0b11, 2), "v '1'")
        t_prev, v_prev = t, v
    struct.pack_into(">H", bs.stream, 0, len(samples))
    return bytes(bs.stream), (bs.trace or [])


def xor_decode(chunk: bytes):
    n = struct.unpack_from(">H", chunk, 0)[0]
    r = BReader(chunk, 2)
    out, t, vb, td, lead, trail = [], 0, 0, 0, 0, 0
    for i in range(n):
        if i == 0:
            t, vb = r.varint(), r.bits(64)
        else:
            if i == 1:
                td = r.uvarint()
            else:
                d = 0
                for _ in range(4):
                    d <<= 1
                    if r.bits(1) == 0:
                        break
                    d |= 1
                sz = {0b0: 0, 0b10: 14, 0b110: 17, 0b1110: 20, 0b1111: 64}[d]
                if sz:
                    bits = r.bits(sz)
                    if sz != 64 and bits > (1 << (sz - 1)):  # xor.go: '>' (asymmetric)
                        bits -= 1 << sz
                    elif sz == 64 and bits >= 1 << 63:
                        bits -= 1 << 64
                    td += bits
            t += td
            if r.bits(1):
                if r.bits(1):
                    lead = r.bits(5)
                    sig = r.bits(6) or 64
                    trail = 64 - lead - sig
                vb ^= r.bits(64 - lead - trail) << trail
        out.append((t, b2f(vb)))
    return out


# ----------------------------------------------------------------------------- XOR2 (EncXOR2 = 4)
def xor2_encode(samples, trace=False):
    bs = BStream(3, False, trace)  # uint16 num_samples + st_header byte (0x00: no start timestamps)
    t_prev, base, t_delta, win = None, 0.0, 0, (0xFF, 0)

    def vdelta(v, win):  # writeVDelta: '0' same, '10' reuse, '110' new, '111' stale
        if is_stale(v):
            bs.put("v '111' stale", 0b111, 3)
            return win
        delta = f2b(v) ^ f2b(base)
        if delta == 0:
            bs.put("v '0' same", 0, 1)
            return win
        return put_window(bs, delta, win, (0b10, 2), (0b110, 3), "v")

    for i, (t, v) in enumerate(samples):
        if i == 0:
            bs.put_bytes("ts_0 varint", put_varint(t))
            bs.put("v_0 float64", f2b(v), 64)
            td = 0
        elif i == 1:
            td = t - t_prev
            bs.put_bytes("ts_1 delta uvarint", put_uvarint(td))
            win = vdelta(v, win)
        else:
            td = t - t_prev
            dod = td - t_delta
            if dod == 0:
                if is_stale(v):
                    bs.put("joint '11111' stale", 0b11111, 5)
                else:
                    delta = f2b(v) ^ f2b(base)
                    if delta == 0:
                        bs.put("joint '0'", 0, 1)
                    else:  # '10' + writeVDeltaKnownNonZero: '0' reuse / '1' new
                        win = put_window(bs, delta, win, (0b100, 3), (0b101, 3), "joint '10'")
            else:
                if -(1 << 12) <= dod <= (1 << 12) - 1:
                    bs.put("joint '110'+13b", (0b110 << 13) | (dod & 0x1FFF), 16)
                elif -(1 << 19) <= dod <= (1 << 19) - 1:
                    bs.put("joint '1110'+20b", (0b1110 << 20) | (dod & 0xFFFFF), 24)
                else:
                    bs.put("joint '11110'", 0b11110, 5)
                    bs.put("dod 64b", dod & MASK64, 64)
                win = vdelta(v, win)
        t_prev, t_delta = t, td
        if not is_stale(v):
            base = v
    struct.pack_into(">H", bs.stream, 0, len(samples))
    return bytes(bs.stream), (bs.trace or [])


def xor2_decode(chunk: bytes):
    n = struct.unpack_from(">H", chunk, 0)[0]
    if chunk[2] != 0:
        raise NotImplementedError("start-timestamp XOR2 chunks are not decoded by this listing")
    r = BReader(chunk, 3)
    out, t, td, base, lead, trail = [], 0, 0, 0, 0, 0

    def window(new_bit):
        nonlocal lead, trail
        if new_bit:
            lead = r.bits(5)
            sig = r.bits(6) or 64
            trail = 64 - lead - sig
        return base ^ (r.bits(64 - lead - trail) << trail)

    def value():  # varbit_xor2
        if r.bits(1) == 0:
            return base
        if r.bits(1) == 0:
            return window(False)
        return window(True) if r.bits(1) == 0 else STALE_NAN_BITS

    def sx(bits, w):
        return bits - (1 << w) if bits >= 1 << (w - 1) else bits

    for i in range(n):
        if i == 0:
            t, vb = r.varint(), r.bits(64)
        elif i == 1:
            td = r.uvarint()
            t += td
            vb = value()
        else:
            c = 0
            while c < 5 and r.bits(1):
                c += 1
            if c in (0, 1, 5):
                t += td
                vb = base if c == 0 else (window(r.bits(1)) if c == 1 else STALE_NAN_BITS)
            else:
                w = {2: 13, 3: 20, 4: 64}[c]
                td += sx(r.bits(w), w)
                t += td
                vb = value()
        if vb != STALE_NAN_BITS:
            base = vb
        out.append((t, b2f(vb)))
    return out


# ----------------------------------------------------------------------------- workloads
T0 = 1_762_300_800_000  # 2025-11-05T00:00:00Z in ms


def scrape_times(n, interval_ms, max_late_ms, rng):
    """Scrapes fire late by U[0, max_late_ms] ms; scrape.go snaps them back to the ideal grid when
    lateness <= min(interval/100, 2ms) (ScrapeTimestampTolerance + AlignScrapeTimestamps)."""
    tol = min(interval_ms // 100, 2)
    out = []
    for i in range(n):
        late = rng.randint(0, max_late_ms) if max_late_ms else 0
        out.append(T0 + i * interval_ms + (0 if late <= tol else late))
    return out


def workloads():
    rng = random.Random(20261105)
    n, iv = 120, 15_000
    w = {}
    ts = scrape_times(n, iv, 0, rng)
    w["W1 up==1, aligned"] = [(t, 1.0) for t in ts]
    c, vals = 0, []
    for _ in range(n):
        c += rng.randint(30, 70)
        vals.append(float(c))
    w["W2 int counter, aligned"] = list(zip(ts, vals))
    w["W3 int counter, late 0-10ms"] = list(zip(scrape_times(n, iv, 10, rng), vals))
    w["W4 float gauge rng.random()"] = [(t, rng.random()) for t in ts]
    w["W5 gauge 2 decimals"] = [(t, round(40 + 20 * rng.random(), 2)) for t in ts]
    cpu, cv = 0.0, []
    for _ in range(n):
        cpu += 0.01 * rng.randint(1, 40)  # float accumulation -> messy mantissas
        cv.append(cpu)
    w["W6 cpu-seconds counter"] = list(zip(ts, cv))
    w["W7 W3 + stale marker"] = w["W3 int counter, late 0-10ms"][:-1] + [(w["W3 int counter, late 0-10ms"][-1][0], STALE_NAN)]
    w["W8 const, late 0-50ms"] = [(t, 1.0) for t in scrape_times(n, iv, 50, rng)]
    return w


def same(a, b):
    return len(a) == len(b) and all(x[0] == y[0] and f2b(x[1]) == f2b(y[1]) for x, y in zip(a, b))


def dod_classes(samples):
    ts = [t for t, _ in samples]
    dods = [(ts[i] - ts[i - 1]) - (ts[i - 1] - ts[i - 2]) for i in range(2, len(ts))]
    return sum(1 for d in dods if d == 0) / len(dods)


# ----------------------------------------------------------------------------- main
def main():
    checks = []

    print("== 1. Worked example: 5 counter samples, scrape 4 is 3 ms late (> 2 ms tolerance) ==")
    ex = [(T0, 1000.0), (T0 + 15000, 1047.0), (T0 + 30000, 1093.0), (T0 + 45003, 1093.0), (T0 + 60000, 1150.0)]
    for name, enc, hdr in (("XOR", xor_encode, 2), ("XOR2", xor2_encode, 3)):
        chunk, tr = enc(ex, trace=True)
        bits = "".join(b for _, b in tr)
        stream_bits = "".join(format(x, "08b") for x in chunk[hdr:])[: len(bits)]
        ok = bits == stream_bits and len(chunk) == hdr + (len(bits) + 7) // 8
        checks.append((f"{name} trace == stream bits", ok))
        print(f"-- {name}: header {chunk[:hdr].hex()} ; {len(bits)} payload bits -> {len(chunk)} bytes")
        for label, b in tr:
            shown = b if len(b) <= 40 else f"{b[:18]}...{b[-14:]}"
            print(f"   {label:<34} {len(b):>3}b  {shown}")
    print()

    print("== 2. dod bucket edges (bitRange asymmetry in XOR vs symmetric int13/int20 in XOR2) ==")
    print(f"{'dod (ms)':>10} | {'XOR bits':>8} | {'XOR2 bits':>9} | round trip")
    for dod in (1, -1, 4095, -4096, 4096, 8192, -8192, -8191, 8193, 65536, -65536, 524287, 524288, -524288, 524289):
        s = [(T0, 1.0), (T0 + 15000, 1.0), (T0 + 30000 + dod, 1.0)]
        a, ta = xor_encode(s, trace=True)
        b, tb = xor2_encode(s, trace=True)
        xa = sum(len(x) for lab, x in ta if lab.startswith("dod"))
        xb = sum(len(x) for lab, x in tb if lab.startswith(("joint", "dod")))
        rt = same(xor_decode(a), s) and same(xor2_decode(b), s)
        checks.append((f"edge {dod}", rt))
        print(f"{dod:>10} | {xa:>8} | {xb:>9} | {'ok' if rt else 'FAIL'}")
    print()

    print("== 3. Workloads: 120 samples @15s (one head chunk), bytes incl. chunk header ==")
    print(f"{'workload':<30} {'dod=0':>6} | {'XOR B':>6} {'B/smp':>6} | {'XOR2 B':>6} {'B/smp':>6} | {'XOR2/XOR':>8}")
    tot_x = tot_x2 = 0
    for name, s in workloads().items():
        a, _ = xor_encode(s)
        b, _ = xor2_encode(s)
        ok = same(xor_decode(a), s) and same(xor2_decode(b), s)
        checks.append((name, ok))
        tot_x += len(a)
        tot_x2 += len(b)
        print(f"{name:<30} {dod_classes(s):>6.0%} | {len(a):>6} {len(a) / len(s):>6.2f} | "
              f"{len(b):>6} {len(b) / len(s):>6.2f} | {len(b) / len(a):>8.3f}")
    print(f"{'TOTAL (raw = 16 B/sample)':<30} {'':>6} | {tot_x:>6} {tot_x / 960:>6.2f} | {tot_x2:>6} {tot_x2 / 960:>6.2f} | {tot_x2 / tot_x:>8.3f}")
    print()

    print("== 4. Prometheus 2.0 vs 3.15.1 bstream on a 1-sample chunk (the testdata block shape) ==")
    one = [(1, 2.0)]
    legacy, _ = xor_encode(one, legacy=True)
    current, _ = xor_encode(one)
    print(f"legacy  ({len(legacy)} B): {legacy.hex()}")
    print(f"current ({len(current)} B): {current.hex()}")
    ok = legacy[:-1] == current and legacy[-1] == 0 and same(xor_decode(legacy), one) and same(xor_decode(current), one)
    checks.append(("legacy trailing byte only", ok))
    print(f"identical except one trailing 0x00 padding byte; both decode to {xor_decode(legacy)}")
    print()

    print("== 5. Property test: random + adversarial series through both codecs ==")
    rng = random.Random(7)
    specials = [0.0, -0.0, 1.0, -1.0, float("inf"), float("-inf"), b2f(0x7FF8000000000001), STALE_NAN,
                5e-324, 1.7976931348623157e308, 0.1, 1e-300]
    edges = [0, 0, 0, 1, -1, 4095, -4096, 8192, -8191, 8193, -8192, 65536, -65535, 65537, 524288,
             -524287, 524289, 1 << 40]
    n_series = n_samples = 0
    for k in range(400):
        n = rng.randint(1, 240)
        t, td, s = rng.randint(-10**12, 10**13), rng.randint(1, 60_000), []
        v = rng.random() * 1000
        for i in range(n):
            if i >= 2:
                td = max(1, td + rng.choice(edges))
            t = t + (td if i else 0)
            r = rng.random()
            v = rng.choice(specials) if r < 0.15 else (v if r < 0.5 else (v + rng.randint(-5, 50) if r < 0.8 else rng.uniform(-1e9, 1e9)))
            s.append((t, v))
        ok = same(xor_decode(xor_encode(s)[0]), s) and same(xor2_decode(xor2_encode(s)[0]), s)
        checks.append((f"prop {k}", ok))
        n_series += 1
        n_samples += n
    bad = [n for n, ok in checks if n.startswith("prop") and not ok]
    print(f"{n_series} series, {n_samples} samples, bit-exact round trip failures: {len(bad)}")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed[:5]}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:xor_chunk.py -->
```text
== 1. Worked example: 5 counter samples, scrape 4 is 3 ms late (> 2 ms tolerance) ==
-- XOR: header 0005 ; 212 payload bits -> 29 bytes
   ts_0 varint                         48b  100000001011000010...00101001100110
   v_0 float64                         64b  010000001000111101...00000000000000
   ts_1 delta uvarint                  16b  1001100001110101
   v '1' new(lead=11,sig=11)           24b  110101100101111111000111
   dod '0'                              1b  0
   v '1' reuse(lead=11,sig=11)         13b  1000001010010
   dod '10'+14b                        16b  1000000000000011
   v '0' same                           1b  0
   dod '10'+14b                        16b  1011111111111010
   v '1' reuse(lead=11,sig=11)         13b  1000000111011
-- XOR2: header 000500 ; 213 payload bits -> 30 bytes
   ts_0 varint                         48b  100000001011000010...00101001100110
   v_0 float64                         64b  010000001000111101...00000000000000
   ts_1 delta uvarint                  16b  1001100001110101
   v new(lead=11,sig=11)               25b  1100101100101111111000111
   joint '10' reuse(lead=11,sig=11)    14b  10000001010010
   joint '110'+13b                     16b  1100000000000011
   v '0' same                           1b  0
   joint '110'+13b                     16b  1101111111111010
   v reuse(lead=11,sig=11)             13b  1000000111011

== 2. dod bucket edges (bitRange asymmetry in XOR vs symmetric int13/int20 in XOR2) ==
  dod (ms) | XOR bits | XOR2 bits | round trip
         1 |       16 |        16 | ok
        -1 |       16 |        16 | ok
      4095 |       16 |        16 | ok
     -4096 |       16 |        16 | ok
      4096 |       16 |        24 | ok
      8192 |       16 |        24 | ok
     -8192 |       20 |        24 | ok
     -8191 |       16 |        24 | ok
      8193 |       20 |        24 | ok
     65536 |       20 |        24 | ok
    -65536 |       24 |        24 | ok
    524287 |       24 |        24 | ok
    524288 |       24 |        69 | ok
   -524288 |       68 |        24 | ok
    524289 |       68 |        69 | ok

== 3. Workloads: 120 samples @15s (one head chunk), bytes incl. chunk header ==
workload                        dod=0 |  XOR B  B/smp | XOR2 B  B/smp | XOR2/XOR
W1 up==1, aligned                100% |     48   0.40 |     34   0.28 |    0.708
W2 int counter, aligned          100% |    251   2.09 |    252   2.10 |    1.004
W3 int counter, late 0-10ms        5% |    461   3.84 |    466   3.88 |    1.011
W4 float gauge rng.random()      100% |    886   7.38 |    887   7.39 |    1.001
W5 gauge 2 decimals              100% |    842   7.02 |    843   7.03 |    1.001
W6 cpu-seconds counter           100% |    998   8.32 |    999   8.32 |    1.001
W7 W3 + stale marker               5% |    469   3.91 |    465   3.88 |    0.991
W8 const, late 0-50ms              2% |    266   2.22 |    266   2.22 |    1.000
TOTAL (raw = 16 B/sample)             |   4221   4.40 |   4212   4.39 |    0.998

== 4. Prometheus 2.0 vs 3.15.1 bstream on a 1-sample chunk (the testdata block shape) ==
legacy  (12 B): 000102400000000000000000
current (11 B): 0001024000000000000000
identical except one trailing 0x00 padding byte; both decode to [(1, 2.0)]

== 5. Property test: random + adversarial series through both codecs ==
400 series, 48396 samples, bit-exact round trip failures: 0

checks: 426/426 passed
verdict: OK
```

How to read the workload table (§3) [M]:

| Workload | Why it costs what it costs |
|---|---|
| W1 constant, aligned | 1 bit dod + 1 bit value per sample (XOR); 1 bit total (XOR2): header and sample 0 dominate |
| W2 integer counter, aligned | dod free; the XOR of two nearby integers as float64 touches about 13 mantissa bits, so ~2.1 B/sample |
| W3 the same counter, 0–10 ms late | Most dods ≠ 0 → +16 bits per sample: **jitter nearly doubles the bytes (2.09 → 3.84)** |
| W4 random float gauge | XOR of unrelated floats is ~56 significant bits → ~7.4 B/sample, the worst realistic case |
| W5 2-decimal gauge | Still ~7 B/sample: decimal fractions are not short in binary floating point |
| W6 float CPU-seconds counter | Accumulated `0.01·k` floats have noisy low mantissa bits → **8.3 B/sample, worse than random** |
| W7 jittered counter + stale marker | XOR2 is cheaper here because the stale NaN does not reset the value baseline |
| W8 constant value, 0–50 ms jitter | Bytes are entirely timestamp: a "constant" series is not cheap if its scrapes are late |

The architect's lesson is that **bytes per sample is a property of the data and of the scraper's timing, not of Prometheus**. "Prometheus stores 1.3 B/sample" is true for a well-behaved fleet with aligned scrapes and mostly integer or constant series. Exporters that publish high-entropy floats, or scrapes that are late on overloaded nodes, can quadruple it.

### 1.7 Chunk cutting: why 120 samples, and what long scrape intervals cost

`memSeries.appendPreprocessor` (`head_append.go`) decides when the open chunk is closed [D]:

1. A new chunk's deadline `nextAt` is the end of its 2 h range: `rangeForTimestamp(t) = (t / 2h)·2h + 2h`. Chunks never straddle a 2 h boundary, because blocks are cut on those boundaries.
2. When the chunk reaches `samplesPerChunk / 4 = 30` samples, the head **predicts** a better deadline with `computeChunkEndTime(start, cur, nextAt, 4)`. This divides the rest of the range into equal chunks of about 120 samples at the observed rate.
3. The chunk is cut at `t ≥ nextAt` or at **240** samples (`2 × samplesPerChunk`) if the rate jumped.
4. The cut chunk is pushed onto `headChunks` and later written to `chunks_head/` and m-mapped. 3.12 made this per-stripe and skippable for clean stripes.

L2 §2 runs the exact algorithm over 24 h [M]:

- 1–60 s intervals produce **118–120-sample chunks**, i.e. 61, 12, 6, 4, 2 and 1 chunk(s) per 2 h.
- At **120 s the 2 h boundary caps chunks at 60 samples, and at 300 s at 24 samples**. Per-sample cost rises from ~1.6 to **2.17 B/sample**, because the 14-byte first sample and the chunk framing are spread over fewer samples.
- Long scrape intervals are therefore *less* storage-efficient per sample. They are still cheaper in absolute terms, but the saving is less than linear.

### 1.8 Timestamp alignment: the 2 ms tolerance

The scrape loop computes `alignedScrapeTime` and snaps the real scrape time onto it when it is within `min(interval/100, 2 ms)`. That is `ScrapeTimestampTolerance = 2 ms` with `AlignScrapeTimestamps = true`, controlled by the experimental flags `--scrape.adjust-timestamps` and `--scrape.timestamp-tolerance` [D].

The comment links prometheus/prometheus#7846: Go timer jitter alone was measurably inflating TSDB size. W2 vs W3 in L1 quantifies this: **2.09 vs 3.84 B/sample** for the same values.

The capacity lesson is that a CPU-starved Prometheus pod (CFS throttling, Folder 03) is more expensive to *store*, not just slower:
- throttled scrapes fire late;
- lateness beyond 2 ms defeats alignment;
- every late sample costs 16 extra bits.

### 1.9 Head compaction, WAL truncation and the checkpoint

`Head.compactable()` returns true when `maxt − mint > chunkRange/2·3`, i.e. **3 h** with the default 2 h range [D]. The DB's background loop checks this every minute and then:

1. writes the block `[mint, rangeForTimestamp(mint))`, the oldest 2 h;
2. truncates head memory below the new `mint`. Series with no samples left are garbage-collected *here and only here*, apart from the experimental stale-series compaction;
3. truncates the WAL (`truncateWAL`):
   - `Segments()`, then `NextSegment()`, then `last--` (the just-closed active segment is never checkpointed);
   - `last = first + (last − first)·2/3`;
   - write `checkpoint.<last>` containing the Series records of still-live series plus any samples newer than the new `mint`;
   - delete segments `≤ last` and older checkpoints.

```text
 head span      1h ──────────────► 3h ┐ compact [0h,2h) ┌ 1h ───────────► 3h ┐ compact [2h,4h)
                                      ▼                  │                    ▼
 WAL segments   ▁▂▃▄▅▆▇█ (≈3h of data) ── checkpoint first ⅔ ─► ▁▂▃ (≈1h) ── grows again ──►
 memory         series created since the last GC stay in the head until the NEXT compaction:
                a pod that died at 0h10 keeps its series in RAM until ~3h10 (up to 3h of churn)
```

L2 §3 simulates 1 M series @15 s with the WAL bytes/sample measured in L2 §1 [M+E]:

- A 128 MiB segment is closed every ~4 minutes.
- Each compaction checkpoints and deletes ~30 of ~46 segments and keeps 16.
- **The WAL peaks at ~6 GiB including a ~150 MiB checkpoint.** The checkpoint is dominated by Series records: one per live series, ~154 B each for 8 labels.

Two consequences:
- **Disk.** Provision the WAL volume for ≥ 3 h of compressed samples plus one Series record per active series, ×2 for a failed truncation. `prometheus_tsdb_checkpoint_creations_failed_total > 0` means the WAL is no longer shrinking.
- **Recovery time objective.** A crash just before compaction replays ~720 M samples plus 1 M series records. Restart time scales with that, plus page-cache warmup of `chunks_head`. Use `memory-snapshot-on-shutdown` for planned restarts, and budget the replay time for unplanned ones (`prometheus_tsdb_data_replay_duration_seconds`).

### 1.10 WAL records: what is actually on disk

L2 §1 writes and re-reads real record layouts [M]:

- **Series record** (type 1): `id <8B BE>`, `nLabels <uvarint>`, then length-prefixed names and values. ~154 B for an 8-label Kubernetes series.
- **Samples record** (type 2, V1): base `ref <8B>` and base `t <8B>`, then per sample `Δref <varint>`, `Δt <varint>`, `value <8B>`. That is ~10.8 B/sample uncompressed for scrape batches, where Δt = 0 because a scrape commits one timestamp.
- **Fragment framing**: `type <1B>` (low 3 bits full/first/middle/last, bit 3 snappy, bit 4 zstd), `len <2B BE>`, `CRC32C <4B BE>`, payload, in 32 KiB pages. A page with fewer than 7 free bytes is zero-padded, and a zero type byte means "rest of page empty".
- With snappy (the default, `--storage.tsdb.wal-compression=true`, type `snappy`; `zstd` selectable) the segment is **~8.7 B/sample** for these counters [M]. Values are the incompressible part.

> **Spec drift worth knowing [D].** `tsdb/docs/format/wal.md` draws the per-sample deltas as `<uvarint>`, but `record.go` writes **signed** varints (`PutVarint64`). The deltas really are negative for receiver-style batches (remote write or OTLP), where samples arrive in arbitrary series and timestamp order; L2 counts 472 of 500. If you write a WAL tool from the doc alone, it will corrupt on the first push-ingested batch.

3.11+ adds `SamplesV2`, `HistogramSamplesV2` and `FloatHistogramSamplesV2` (types 11–13) when `st-storage` is enabled. A WAL containing them can only be replayed by 3.11+, which is a one-way door for rollback, mirrored by the 3.13.4 fix "Agent: ignore unknown WAL record types to allow rolling back".

### 1.11 Out-of-order ingestion: the WBL and the OOO head

With `storage.tsdb.out_of_order_time_window: 30m` [D]:
- A sample older than the series' latest but newer than `head.maxt − window` is accepted.
- It is written to the **WBL** (`wbl/`, metrics prefixed `prometheus_tsdb_out_of_order_wbl_`).
- It is held in a per-series OOO head chunk capped at `out_of_order_cap_max = 32` samples. OOO chunks are not cut by time.
- OOO data is compacted into *separate* blocks, which then overlap in-order blocks. They are merged by **vertical compaction** (`--storage.tsdb.allow-overlapping-compaction`, default true).

The costs:
- a second log;
- small (≤32-sample) chunks with worse compression;
- an extra query-time merge until vertical compaction runs.

Enable OOO **only** for push paths that genuinely reorder: OTLP from batching collectors, remote-write receivers fed by many agents, or backfill. Never enable it to paper over clock skew on scrape targets. `prometheus_tsdb_sample_ooo_delta` (3.9+) shows how late the late samples really are; size the window from its p99.9, not from a guess.

### 1.12 Structural memory per active series

L2 §4 adds up v3.15.1 struct layouts for a 14-label Kubernetes pod series scraped at 15 s [E]:

| Component | Bytes | Source |
|---|---|---|
| `memSeries` | 176 | Field list sums to the 176 B Go size class |
| label string (stringlabels) | 448 | 14 × (1 + 10 + 1 + 18) = 420, rounded to the size class |
| `memChunk` + `XORChunk` + appender | 128 | 48 + 32 + 48 |
| open chunk `[]byte` | ~203 | Starts at 128 B (`chunkAllocationSize`) and doubles to 256 |
| m-mapped chunk refs | ~140 | 3.5 refs × (32 + 8) over a 1–3 h head |
| stripe map entries | ~50 | Two map entries (by ref, by hash) |
| postings refs | ~129 | 14 label pairs × 8 B × ~1.15 slice slack |
| unique label pairs | ~112 | `pod` and `instance` values unique to this series |
| **live heap** | **~1.4 KiB** | ×1.75 for GC headroom (`runtime.gogc` default 75) → **~2.4 KiB/series** |

Treat ~2–4 KiB per active head series as the **planning band**: thin series at the bottom, OTLP series with 30 promoted resource attributes at the top.

**Calibrate it on your build:** `go_memstats_heap_inuse_bytes / prometheus_tsdb_head_series` after the head has filled. Then add 20–30% for query working sets. A single bad query can transiently exceed the whole head; the default `--query.max-samples=50000000` is the guard.

3.x defaults `--auto-gomemlimit` (ratio 0.9 of the cgroup limit). The GC therefore works harder near the limit instead of overshooting it. That converts a would-be OOMKill into CPU burn, which is better, but it is a warning, not a fix.

<!-- listing:wal_head_lab.py -->
```python
"""wal_head_lab.py - WAL record/page codec, head chunk cutting, compaction/WAL timeline and a
structural head-memory model, all ported from Prometheus v3.15.1.

Sources (tag v3.15.1):
  tsdb/record/record.go   Series (type 1) and Samples V1 (type 2) record layouts. NB: the code
                          writes the per-sample ref/ts deltas as SIGNED varints (PutVarint64),
                          while tsdb/docs/format/wal.md draws them as <uvarint>.
  tsdb/wlog/wlog.go       32 KiB pages, 7-byte fragment header (type|len BE16|CRC32C BE32),
                          full/first/middle/last fragments, snappy flag 1<<3, page.full() when
                          fewer than 7 bytes remain; 128 MiB segments.
  tsdb/head_append.go     appendPreprocessor: nextAt = rangeForTimestamp; at samplesPerChunk/4
                          predict computeChunkEndTime(...,4); cut at nextAt or 2*samplesPerChunk.
  tsdb/head.go            compactable(): maxt-mint > chunkRange/2*3; truncateWAL checkpoints the
                          first 2/3 of closed segments.
Stdlib only, deterministic. Imports xor_chunk.py from the same directory.

Usage: python wal_head_lab.py [target.md]
"""
import math
import pathlib
import random
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from xor_chunk import T0, put_uvarint, put_varint, xor_encode  # noqa: E402

# ----------------------------------------------------------------------------- CRC32C
_CRC_TABLE = []
for _i in range(256):
    _c = _i
    for _ in range(8):
        _c = (_c >> 1) ^ 0x82F63B78 if _c & 1 else _c >> 1
    _CRC_TABLE.append(_c)


def crc32c(data: bytes) -> int:
    c = 0xFFFFFFFF
    for b in data:
        c = _CRC_TABLE[(c ^ b) & 0xFF] ^ (c >> 8)
    return c ^ 0xFFFFFFFF


# ----------------------------------------------------------------------------- snappy (block format)
def snappy_compress(src: bytes) -> bytes:
    """Format-valid snappy block encoder (greedy LZ77, 4-byte hash, 64 KiB fragments like Go's
    encoder). Output decodes with any snappy decoder; its ratio approximates, not equals, Go's."""
    out = bytearray(put_uvarint(len(src)))

    def literal(lo, hi):
        n = hi - lo
        if n <= 0:
            return
        if n <= 60:
            out.append((n - 1) << 2)
        elif n <= 256:
            out.extend(bytes([60 << 2, n - 1]))
        else:
            out.extend(bytes([61 << 2]) + (n - 1).to_bytes(2, "little"))
        out.extend(src[lo:hi])

    def copy(off, n):
        while n >= 68:
            out.append((63 << 2) | 2)
            out.extend(off.to_bytes(2, "little"))
            n -= 64
        if n > 64:
            out.append((59 << 2) | 2)
            out.extend(off.to_bytes(2, "little"))
            n -= 60
        if n >= 12 or off >= 2048:
            out.append(((n - 1) << 2) | 2)
            out.extend(off.to_bytes(2, "little"))
        else:
            out.append(((off >> 8) << 5) | ((n - 4) << 2) | 1)
            out.append(off & 0xFF)

    for base in range(0, len(src), 65536):
        end = min(len(src), base + 65536)
        table, i, lit = {}, base, base
        while i + 4 <= end:
            key = src[i:i + 4]
            cand = table.get(key)
            table[key] = i
            if cand is not None and i - cand < 65536:
                n = 4
                while i + n < end and src[cand + n] == src[i + n]:
                    n += 1
                literal(lit, i)
                copy(i - cand, n)
                i += n
                lit = i
            else:
                i += 1
        literal(lit, end)
    return bytes(out)


def snappy_decompress(src: bytes) -> bytes:
    n = s = pos = 0
    while True:
        b = src[pos]
        pos += 1
        n |= (b & 0x7F) << s
        if b < 0x80:
            break
        s += 7
    out = bytearray()
    while pos < len(src):
        tag = src[pos]
        pos += 1
        kind = tag & 3
        if kind == 0:
            ln = tag >> 2
            if ln >= 60:
                k = ln - 59
                ln = int.from_bytes(src[pos:pos + k], "little")
                pos += k
            ln += 1
            out += src[pos:pos + ln]
            pos += ln
            continue
        if kind == 1:
            ln, off = ((tag >> 2) & 7) + 4, ((tag >> 5) << 8) | src[pos]
            pos += 1
        elif kind == 2:
            ln, off = (tag >> 2) + 1, int.from_bytes(src[pos:pos + 2], "little")
            pos += 2
        else:
            ln, off = (tag >> 2) + 1, int.from_bytes(src[pos:pos + 4], "little")
            pos += 4
        for _ in range(ln):
            out.append(out[-off])
    assert len(out) == n, "snappy length mismatch"
    return bytes(out)


# ----------------------------------------------------------------------------- WAL records
SERIES, SAMPLES = 1, 2


def enc_series(series):  # [(ref, [(name, value), ...])]
    b = bytearray([SERIES])
    for ref, lbls in series:
        b += struct.pack(">Q", ref) + put_uvarint(len(lbls))
        for n, v in lbls:
            for s in (n.encode(), v.encode()):
                b += put_uvarint(len(s)) + s
    return bytes(b)


def enc_samples(samples):  # [(ref, t, v)] -> Samples V1
    b = bytearray([SAMPLES])
    if not samples:
        return bytes(b)
    r0, t0, _ = samples[0]
    b += struct.pack(">Qq", r0, t0)
    for r, t, v in samples:
        b += put_varint(r - r0) + put_varint(t - t0) + struct.pack(">d", v)
    return bytes(b)


def _uvar(buf, pos):
    x = s = 0
    while True:
        b = buf[pos]
        pos += 1
        x |= (b & 0x7F) << s
        if b < 0x80:
            return x, pos
        s += 7


def _var(buf, pos):
    ux, pos = _uvar(buf, pos)
    return (-(ux >> 1) - 1 if ux & 1 else ux >> 1), pos


def dec_record(rec):
    typ, pos, out = rec[0], 1, []
    if typ == SERIES:
        while pos < len(rec):
            ref = struct.unpack_from(">Q", rec, pos)[0]
            n, pos = _uvar(rec, pos + 8)
            lbls = []
            for _ in range(n):
                pair = []
                for _ in range(2):
                    ln, pos = _uvar(rec, pos)
                    pair.append(rec[pos:pos + ln].decode())
                    pos += ln
                lbls.append(tuple(pair))
            out.append((ref, lbls))
    elif typ == SAMPLES and len(rec) > 1:
        r0, t0 = struct.unpack_from(">Qq", rec, pos)
        pos += 16
        while pos < len(rec):
            dr, pos = _var(rec, pos)
            dt, pos = _var(rec, pos)
            out.append((r0 + dr, t0 + dt, struct.unpack_from(">d", rec, pos)[0]))
            pos += 8
    return typ, out


PAGE, HDR, FULL, FIRST, MIDDLE, LAST, SNAPPY = 32 * 1024, 7, 1, 2, 3, 4, 1 << 3


class WalWriter:
    def __init__(self, compress=True):
        self.pages, self.page, self.compress = [], bytearray(), compress

    def log(self, rec: bytes):
        data, flag = rec, 0
        if self.compress and rec:
            data, flag = snappy_compress(rec), SNAPPY
        i = 0
        while i == 0 or data:
            room = PAGE - len(self.page) - HDR
            part, data = data[:room], data[room:]
            typ = FULL if i == 0 and not data else LAST if not data else FIRST if i == 0 else MIDDLE
            self.page += bytes([typ | flag]) + struct.pack(">HI", len(part), crc32c(part)) + part
            if PAGE - len(self.page) < HDR:  # page.full(): pad with zeros (= recPageTerm)
                self.flush()
            i += 1

    def flush(self):
        if self.page:
            self.pages.append(bytes(self.page) + bytes(PAGE - len(self.page)))
            self.page = bytearray()

    def segment(self) -> bytes:
        self.flush()
        return b"".join(self.pages)


def wal_read(seg: bytes):
    recs, buf, pos = [], bytearray(), 0
    while pos + HDR <= len(seg):
        typ = seg[pos]
        if typ == 0:  # rest of page is empty
            pos = (pos // PAGE + 1) * PAGE
            continue
        ln, crc = struct.unpack_from(">HI", seg, pos + 1)
        part = seg[pos + HDR:pos + HDR + ln]
        if crc32c(part) != crc:
            raise ValueError(f"CRC mismatch at {pos}")
        buf += part
        pos += HDR + ln
        if typ & 7 in (FULL, LAST):
            recs.append(snappy_decompress(bytes(buf)) if typ & SNAPPY else bytes(buf))
            buf = bytearray()
        if PAGE - pos % PAGE < HDR and pos % PAGE:
            pos = (pos // PAGE + 1) * PAGE
    return recs


# ----------------------------------------------------------------------------- chunk cutting
def range_for_ts(t, width):
    return (t // width) * width + width


def chunk_end_time(start, cur, max_t, ratio):  # computeChunkEndTime
    n = (max_t - start) / ((cur - start + 1) * ratio)
    if n <= 1:
        return max_t
    return int(start + (max_t - start) / math.floor(n))


def cut_chunks(interval_ms, duration_ms, start, spc=120, chunk_range=7_200_000):
    chunks, c, next_at = [], None, None
    for t in range(start, start + duration_ms, interval_ms):
        if c is None:
            c = [t, None, 0]
            chunks.append(c)
            next_at = range_for_ts(t, chunk_range)
        if c[2] == spc // 4:
            next_at = chunk_end_time(c[0], c[1], next_at, 4)
        if t >= next_at or c[2] >= spc * 2:
            c = [t, None, 0]
            chunks.append(c)
            next_at = range_for_ts(t, chunk_range)
        c[1], c[2] = t, c[2] + 1
    return chunks


# ----------------------------------------------------------------------------- head memory model [E]
SIZE_CLASSES = [8, 16, 24, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240, 256, 288,
                320, 352, 384, 416, 448, 480, 512, 576, 640, 704, 768, 896, 1024, 1152, 1280, 1408,
                1536, 1792, 2048, 2304, 2688, 3072, 3200, 3456, 4096]


def sc(n):
    return next((c for c in SIZE_CLASSES if c >= n), n)


def head_series_bytes(n_labels, name_len, value_len, interval_s, bytes_per_sample, unique_pairs):
    """Live-heap bytes per active series, from v3.15.1 struct layouts (64-bit, stringlabels)."""
    chunk_secs = 120 * interval_s if interval_s * 120 <= 7200 else 7200
    mm_chunks = max(0.0, 7200 / chunk_secs - 0.5)  # head spans 1h..3h (avg 2h) of m-mapped chunks
    n_in_chunk = min(120, 7200 // interval_s)
    caps = []  # average cap of the open chunk's []byte over its life (alloc 128, append doubles)
    for k in range(1, n_in_chunk + 1):
        need, cap = 2 + 8 + k * bytes_per_sample, 128
        while cap < need:
            cap *= 2
        caps.append(cap)
    parts = {
        "memSeries struct (176 B class)": sc(176),
        "labels string (1B len prefixes)": sc(n_labels * (2 + name_len + value_len)),
        "memChunk + XORChunk + appender": sc(40) + sc(32) + sc(40),
        "open chunk []byte (avg cap)": sum(caps) / len(caps),
        "m-mapped chunk refs (32 B + ptr)": mm_chunks * (sc(32) + 8),
        "stripeSeries 2 map entries": 2 * 25,
        "MemPostings refs (8 B, ~15% slack)": n_labels * 8 * 1.15,
        "unique label pairs (map entry)": unique_pairs * 56,
    }
    return parts


# ----------------------------------------------------------------------------- main
def main():
    checks = []
    checks.append(("crc32c check value", crc32c(b"123456789") == 0xE3069283))

    print("== 1. WAL records + pages: 20 targets x 250 series, 40 scrapes @15s ==")
    rng = random.Random(42)
    w_raw, w_snap = WalWriter(False), WalWriter(True)
    series, refs, ref = [], [], 1
    for tgt in range(20):
        for k in range(250):
            lbls = [("__name__", f"http_requests_total" if k % 5 else "process_cpu_seconds_total"),
                    ("code", ("200", "404", "500")[k % 3]), ("instance", f"10.42.{tgt}.{k % 7}:8080"),
                    ("job", "checkout"), ("method", ("GET", "POST")[k % 2]),
                    ("namespace", "shop"), ("pod", f"checkout-7f9c{tgt:02d}-x{k % 7}"), ("route", f"/api/v{k % 4}/item")]
            series.append((ref, lbls))
            refs.append(ref)
            ref += 1
    state = {r: float(rng.randint(0, 10_000)) for r in refs}
    expected, n_samples = [], 0
    for wr in (w_raw, w_snap):
        for i in range(0, len(series), 250):  # one Series record per target on first scrape
            wr.log(enc_series(series[i:i + 250]))
    expected += [(SERIES, series[i:i + 250]) for i in range(0, len(series), 250)]
    for scrape in range(40):
        t = T0 + scrape * 15_000  # one commit per scrape: every sample carries the scrape time
        for tgt in range(20):
            batch = []
            for r in refs[tgt * 250:(tgt + 1) * 250]:
                state[r] += rng.randint(0, 40)
                batch.append((r, t, state[r]))
            rec = enc_samples(batch)
            w_raw.log(rec)
            w_snap.log(rec)
            expected.append((SAMPLES, batch))
            n_samples += len(batch)
    seg_raw, seg_snap = w_raw.segment(), w_snap.segment()
    got_raw = [dec_record(r) for r in wal_read(seg_raw)]
    got_snap = [dec_record(r) for r in wal_read(seg_snap)]
    checks.append(("WAL raw round trip", got_raw == expected))
    checks.append(("WAL snappy round trip", got_snap == expected))
    payload = sum(len(enc_samples(b)) for typ, b in expected if typ == SAMPLES)
    series_rec = sum(len(enc_series(b)) for typ, b in expected if typ == SERIES) / len(series)
    print(f"samples written           : {n_samples:,} ({len(series):,} series, 8 labels each)")
    print(f"Series record             : {series_rec:.1f} B/series (written once per new series + per checkpoint)")
    print(f"Samples-record payload    : {payload / n_samples:.2f} B/sample before compression")
    print(f"segment bytes, no compress: {len(seg_raw):,} ({len(seg_raw) // PAGE} pages) "
          f"-> {len(seg_raw) / n_samples:.2f} B/sample incl. Series records + page padding")
    print(f"segment bytes, snappy     : {len(seg_snap):,} ({len(seg_snap) // PAGE} pages) "
          f"-> {len(seg_snap) / n_samples:.2f} B/sample")
    # A remote-write / OTLP receiver commit mixes timestamps, so deltas vs the first sample go negative.
    rw = [(r, T0 + rng.randint(-30_000, 30_000), float(k)) for k, r in enumerate(refs[:500])]
    rng.shuffle(rw)
    neg = sum(1 for r, t, v in rw if t < rw[0][1] or r < rw[0][0])
    back = dec_record(enc_samples(rw))[1]
    checks.append(("receiver batch: negative deltas round-trip", neg > 0 and back == rw))
    print(f"receiver-style batch of {len(rw)}: {neg} samples have a NEGATIVE ref or ts delta vs the "
          f"first sample -> the code writes signed varints (wal.md draws <uvarint>)")
    print()

    print("== 2. Head chunk cutting (samplesPerChunk=120, chunkRange=2h), steady state over 24h ==")
    print(f"{'interval':>8} | {'chunks/2h':>9} | {'avg smp/chunk':>13} | {'max':>4} | {'XOR B/sample':>12}")
    rng2 = random.Random(3)
    for iv in (1, 5, 10, 15, 30, 60, 120, 300):
        ch = cut_chunks(iv * 1000, 26 * 3_600_000, T0 + 37 * 60_000)
        steady = [c for c in ch if c[0] >= T0 + 2 * 3_600_000 and c[1] < T0 + 26 * 3_600_000 - 7_200_000]
        per2h = len(steady) / 11  # steady window [2h, 24h) = 11 chunk ranges
        avg = sum(c[2] for c in steady) / len(steady)
        n = int(round(avg))
        cnt, s = 0.0, []
        for k in range(n):
            cnt += rng2.randint(0, 9)
            s.append((T0 + k * iv * 1000, cnt))
        bps = len(xor_encode(s)[0]) / n
        print(f"{iv:>7}s | {per2h:>9.2f} | {avg:>13.1f} | {max(c[2] for c in steady):>4} | {bps:>12.2f}")
        if iv == 15:
            checks.append(("15s -> 4 chunks x 120", abs(per2h - 4) < 1e-9 and abs(avg - 120) < 1e-9))
        if iv == 1:
            checks.append(("1s chunks stay < 2*120", max(c[2] for c in steady) < 240))
    print()

    print("== 3. Head compaction + WAL truncation timeline: 1,000,000 series @15s ==")
    rate = 1_000_000 / 15  # samples/s
    bps_wal = len(seg_snap) / n_samples
    seg_size = 128 * 1024 * 1024
    seg_secs = seg_size / (rate * bps_wal)
    chunk_range = 7200
    start = 600  # head minT = first sample at 00:10
    head_min, segs, events = start, [], []
    cur_seg_start, peak = start, 0
    ckpt_bytes = 1_000_000 * series_rec  # checkpoint keeps a Series record per live series
    for now in range(start, start + 12 * 3600 + 1, 60):
        while now - cur_seg_start >= seg_secs:
            segs.append((cur_seg_start, cur_seg_start + seg_secs))
            cur_seg_start += seg_secs
        if now - head_min > chunk_range // 2 * 3:  # compactable(), checked every minute
            maxt = range_for_ts(head_min, chunk_range)
            head_min = maxt
            # truncateWAL: Segments() -> NextSegment() -> last-- -> last = first + (last-first)*2/3
            considered = len(segs)  # closed segments before the open one is closed
            segs.append((cur_seg_start, now))
            cur_seg_start = now
            new_last = (considered - 1) * 2 // 3
            dropped = new_last + 1 if new_last > 0 else 0
            segs = segs[dropped:]
            events.append((now, f"compact block [{(maxt - chunk_range) / 3600:.2f}h,{maxt / 3600:.2f}h); "
                                f"checkpoint+delete {dropped} of {considered + 1} segments, keep {len(segs)}"))
        wal_bytes = (len(segs) * seg_secs + (now - cur_seg_start)) * rate * bps_wal + (ckpt_bytes if events else 0)
        peak = max(peak, wal_bytes)
    print(f"WAL rate {rate * bps_wal / 2**20:.2f} MiB/s at {bps_wal:.2f} B/sample; a 128 MiB segment "
          f"every {seg_secs:.0f} s; checkpoint ~ {ckpt_bytes / 2**20:.0f} MiB of Series records (uncompressed)")
    for t, e in events[:4]:
        print(f"  t={t / 3600:5.2f}h  {e}")
    print(f"peak WAL + checkpoint on disk ~ {peak / 2**30:.2f} GiB; head spans 1h..3h of data")
    print(f"worst-case replay after a crash just before compaction ~ {3 * 3600 * rate / 1e6:.0f} M samples "
          f"+ {1_000_000:,} series records")
    checks.append(("compaction every 2h after the first", all(abs((y[0] - x[0]) - 7200) <= 60 for x, y in zip(events[1:], events[2:]))))
    print()

    print("== 4. Structural head memory per active series [E] (live heap; RSS ~ x1.75 at GOGC=75) ==")
    cases = [("k8s pod series, 14 labels @15s", 14, 10, 18, 15, 2.1, 2),
             ("small app series, 6 labels @15s", 6, 8, 10, 15, 2.1, 1),
             ("fat OTLP-promoted, 30 labels @15s", 30, 14, 24, 15, 2.1, 3),
             ("k8s pod series, 14 labels @60s", 14, 10, 18, 60, 2.1, 2)]
    for name, nl, ln, lv, iv, bps, uq in cases:
        parts = head_series_bytes(nl, ln, lv, iv, bps, uq)
        live = sum(parts.values())
        print(f"-- {name}: live {live:,.0f} B -> ~{live * 1.75:,.0f} B with GC headroom; "
              f"1M series ~ {live * 1.75 * 1e6 / 2**30:.1f} GiB")
        if name.startswith("k8s pod series, 14 labels @15s"):
            for k, v in parts.items():
                print(f"     {k:<38} {v:>7.0f}")
            checks.append(("model in 1-4 KiB band", 1024 < live * 1.75 < 4096))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:wal_head_lab.py -->
```text
== 1. WAL records + pages: 20 targets x 250 series, 40 scrapes @15s ==
samples written           : 200,000 (5,000 series, 8 labels each)
Series record             : 154.2 B/series (written once per new series + per checkpoint)
Samples-record payload    : 10.81 B/sample before compression
segment bytes, no compress: 2,949,120 (90 pages) -> 14.75 B/sample incl. Series records + page padding
segment bytes, snappy     : 1,736,704 (53 pages) -> 8.68 B/sample
receiver-style batch of 500: 472 samples have a NEGATIVE ref or ts delta vs the first sample -> the code writes signed varints (wal.md draws <uvarint>)

== 2. Head chunk cutting (samplesPerChunk=120, chunkRange=2h), steady state over 24h ==
interval | chunks/2h | avg smp/chunk |  max | XOR B/sample
      1s |     61.00 |         118.0 |  119 |         1.64
      5s |     12.00 |         120.0 |  120 |         1.65
     10s |      6.00 |         120.0 |  120 |         1.47
     15s |      4.00 |         120.0 |  120 |         1.70
     30s |      2.00 |         120.0 |  120 |         1.57
     60s |      1.00 |         120.0 |  120 |         1.58
    120s |      1.00 |          60.0 |   60 |         1.85
    300s |      1.00 |          24.0 |   24 |         2.17

== 3. Head compaction + WAL truncation timeline: 1,000,000 series @15s ==
WAL rate 0.55 MiB/s at 8.68 B/sample; a 128 MiB segment every 232 s; checkpoint ~ 147 MiB of Series records (uncompressed)
  t= 3.18h  compact block [0.00h,2.00h); checkpoint+delete 31 of 47 segments, keep 16
  t= 5.02h  compact block [2.00h,4.00h); checkpoint+delete 29 of 45 segments, keep 16
  t= 7.02h  compact block [4.00h,6.00h); checkpoint+delete 31 of 48 segments, keep 17
  t= 9.02h  compact block [6.00h,8.00h); checkpoint+delete 32 of 49 segments, keep 17
peak WAL + checkpoint on disk ~ 6.12 GiB; head spans 1h..3h of data
worst-case replay after a crash just before compaction ~ 720 M samples + 1,000,000 series records

== 4. Structural head memory per active series [E] (live heap; RSS ~ x1.75 at GOGC=75) ==
-- k8s pod series, 14 labels @15s: live 1,385 B -> ~2,425 B with GC headroom; 1M series ~ 2.3 GiB
     memSeries struct (176 B class)             176
     labels string (1B len prefixes)            448
     memChunk + XORChunk + appender             128
     open chunk []byte (avg cap)                203
     m-mapped chunk refs (32 B + ptr)           140
     stripeSeries 2 map entries                  50
     MemPostings refs (8 B, ~15% slack)         129
     unique label pairs (map entry)             112
-- small app series, 6 labels @15s: live 936 B -> ~1,638 B with GC headroom; 1M series ~ 1.5 GiB
-- fat OTLP-promoted, 30 labels @15s: live 2,421 B -> ~4,236 B with GC headroom; 1M series ~ 3.9 GiB
-- k8s pod series, 14 labels @60s: live 1,265 B -> ~2,215 B with GC headroom; 1M series ~ 2.1 GiB

checks: 8/8 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Storage section of `prometheus.yml` (3.15)

Since 3.x, retention belongs in the config file and the CLI flags are deprecated [D]. Everything in this block is runtime-reloadable.

```yaml
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s
  external_labels:
    cluster: prod-eu-west-1
    replica: ${POD_NAME}          # HA pair: dedupe downstream on this label
runtime:
  gogc: 75                         # default; lower = less RAM headroom, more CPU
  log_level: info                  # 3.15: reloadable; --log.level is deprecated
storage:
  tsdb:
    retention:
      time: 15d                    # default when neither time nor size is set
      size: 450GB                  # ~85-90% of the PV: blocks only, WAL and chunks_head are extra
      # percentage: 85             # 3.11+ experimental alternative to size; tracks volume resizes
    out_of_order_time_window: 0s   # enable (e.g. 30m) only for push/OTLP ingestion paths
    chunk_encoding:
      floats: xor                  # set xor2 only when every block reader (Thanos/Mimir/tools) supports it
    # stale_series_compaction_threshold: 0.5   # 3.10+ experimental: evict churned series early
  exemplars:
    max_exemplars: 100000          # only with --enable-feature=exemplar-storage
```

### 2.2 StatefulSet blueprint (the parts that matter for the TSDB)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
spec:
  serviceName: prometheus
  replicas: 2                                  # HA pair scraping the same targets
  podManagementPolicy: Parallel
  selector:
    matchLabels: {app: prometheus}
  template:
    metadata:
      labels: {app: prometheus}
    spec:
      terminationGracePeriodSeconds: 600       # room for the memory snapshot + WAL fsync on shutdown
      securityContext: {runAsNonRoot: true, runAsUser: 65534, fsGroup: 65534}
      containers:
        - name: prometheus
          image: quay.io/prometheus/prometheus:v3.15.1
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --storage.tsdb.path=/prometheus
            - --enable-feature=memory-snapshot-on-shutdown
            - --auto-gomemlimit.ratio=0.85      # leave room for page cache pressure + query spikes
            - --query.max-samples=50000000
            - --query.max-concurrency=20
            - --web.enable-lifecycle
          env:
            - name: POD_NAME
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
          resources:
            requests: {cpu: "4", memory: 48Gi}  # request == limit: never be the BestEffort victim
            limits: {memory: 48Gi}              # no CPU limit: throttling inflates bytes/sample (1.8)
          volumeMounts:
            - {name: data, mountPath: /prometheus}
          readinessProbe:
            httpGet: {path: /-/ready, port: 9090}
            periodSeconds: 10
            failureThreshold: 360              # WAL replay can take many minutes; do not restart-loop it
          livenessProbe:
            httpGet: {path: /-/healthy, port: 9090}
            periodSeconds: 30
            failureThreshold: 20
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: gp3-throughput        # sequential compaction I/O; IOPS matter less than MB/s
        resources:
          requests: {storage: 512Gi}
```

Sizing arithmetic for this pod, at 2 M active series @15 s with a 2.4 KiB/series model [E]:

- **Head:** 2 M × 2.4 KiB ≈ **4.6 GiB**.
- **Query working set:** + 20–30% ≈ 6 GiB.
- **Churn peak (File 02 §4):** ×3–8 on deploy storms, i.e. 6 M+ head series. This is the real limit; the 48 Gi limit here is sized for ~4× churn plus queries.
- **Disk:** 2 M / 15 s = 133 k samples/s × 1.5 B × 86,400 × 15 d ≈ **260 GB** of blocks, plus ~12 GiB of WAL (§1.9 scaled ×2) plus `chunks_head`. The 450 GB `retention.size` therefore leaves headroom on a 512 Gi PV.

### 2.3 TSDB self-monitoring rules

All metric names are taken from the v3.15.1 source.

```yaml
groups:
  - name: prometheus-tsdb.rules
    interval: 30s
    rules:
      - record: prometheus:tsdb_head_series:churn_ratio_1h
        expr: |
          increase(prometheus_tsdb_head_series_created_total[1h])
            / clamp_min(prometheus_tsdb_head_series, 1)
      - record: prometheus:tsdb_bytes_per_head_series
        expr: |
          go_memstats_heap_inuse_bytes{job="prometheus"}
            / clamp_min(prometheus_tsdb_head_series{job="prometheus"}, 1)
      - record: prometheus:tsdb_samples_appended:rate5m
        expr: rate(prometheus_tsdb_head_samples_appended_total[5m])
  - name: prometheus-tsdb.alerts
    rules:
      - alert: PrometheusTSDBCompactionsFailing
        expr: increase(prometheus_tsdb_compactions_failed_total[3h]) > 0
        for: 15m
        labels: {severity: critical}
        annotations:
          summary: "{{ $labels.instance }}: TSDB compactions failing; head and WAL will grow until OOM/disk full"
      - alert: PrometheusWALCheckpointFailing
        expr: increase(prometheus_tsdb_checkpoint_creations_failed_total[3h]) > 0
        labels: {severity: critical}
        annotations:
          summary: "{{ $labels.instance }}: WAL checkpoints failing; WAL is no longer truncated"
      - alert: PrometheusWALCorruption
        expr: increase(prometheus_tsdb_wal_corruptions_total[1h]) > 0
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }}: WAL corruption repaired on replay; data after the corruption point was lost"
      - alert: PrometheusHeadChurnHigh
        expr: prometheus:tsdb_head_series:churn_ratio_1h > 1
        for: 30m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }}: >100% of head series replaced per hour; head memory scales with churn, not active series"
      - alert: PrometheusHeadNearMemoryLimit
        expr: |
          go_memstats_heap_inuse_bytes{job="prometheus"}
            / on(instance) go_gc_gomemlimit_bytes{job="prometheus"} > 0.9
        for: 10m
        labels: {severity: critical}
        annotations:
          summary: "{{ $labels.instance }}: heap above 90% of GOMEMLIMIT; GC thrash then OOMKill"
      - alert: PrometheusOutOfOrderRejections
        expr: |
          sum by (instance) (rate(prometheus_tsdb_out_of_order_samples_total[5m])
            + rate(prometheus_tsdb_too_old_samples_total[5m])) > 0
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }}: samples rejected as out-of-order/too-old"
      - alert: PrometheusRetentionBySize
        expr: increase(prometheus_tsdb_size_retentions_total[1d]) > 0
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }}: blocks deleted by size retention before time retention; effective retention is shorter than configured"
```

> `go_gc_gomemlimit_bytes` is exported by the Go runtime collector in recent client_golang releases. ⚠ Confirm it exists on your build with `/api/v1/status/self_metrics` (3.12+). If it is missing, divide by the container limit from cAdvisor instead.

### 2.4 Operator runbook commands (promtool 3.15)

```bash
# Read-only inspection of a copy of the data dir (never on the live dir of a running server)
promtool tsdb list -r /snap/data                     # blocks, time ranges, sizes, samples
promtool tsdb analyze /snap/data                     # cardinality: label pairs, churn, highest-cardinality names
promtool tsdb dump --match='{__name__="up"}' /snap/data | head
promtool tsdb dump --format=seriesjson /snap/data    # 3.9+: series labels only, as JSON
# Consistent snapshot of a live server (needs --web.enable-admin-api; skip_head=false includes the head)
curl -XPOST 'http://prometheus:9090/api/v1/admin/tsdb/snapshot?skip_head=false'
```

---

## 3. Failure modes and FinOps debugging

### F1. OOMKill during head compaction

**Symptom.** The pod restarts every ~2 h with `OOMKilled`, usually a few minutes after an `:x0` boundary. On restart it spends 10–40 minutes in WAL replay and then dies again.

**Signature.** `prometheus_tsdb_head_series` saw-tooths with peaks far above steady state. `go_memstats_heap_inuse_bytes` spikes during `prometheus_tsdb_compaction_duration_seconds`. `prometheus_tsdb_data_replay_duration_seconds` is large. The container's `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` increments.

**Root cause.**
- Compaction materializes the block's index (postings for every label pair of every series in the range) and re-reads chunks, on top of a head already inflated by churn.
- The head holds every series created in the last 1–3 h, including dead pods' series. GC runs only after the block is written (§1.9).
- So the peak is *head-at-3h + compaction working set*. Replay after the kill rebuilds the same head and repeats the cycle.

**Fix.**
1. Raise the memory limit to cover the churn peak and restart once.
2. Cut churn at the source with `metric_relabel_configs` dropping `pod_template_hash`-style labels and ephemeral IDs (File 04).
3. Shard targets across replicas (hashmod).
4. As a last resort, set `stale_series_compaction_threshold` (3.10+, experimental) so stale series are evicted before the 3 h mark.

**Prevention.**
- Alert on `prometheus:tsdb_head_series:churn_ratio_1h`.
- Size memory from the churn peak, not the steady state.
- Set `readinessProbe.failureThreshold` high enough that replay is not killed.
- Set `--auto-gomemlimit.ratio` ≤ 0.85.

### F2. Disk fills with WAL, not blocks

**Symptom.** The PV is 95% full while `prometheus_tsdb_storage_blocks_bytes` is well under `retention.size`.

**Signature.** `prometheus_tsdb_wal_storage_size_bytes` grows monotonically. `prometheus_tsdb_checkpoint_creations_failed_total` or `prometheus_tsdb_compactions_failed_total` is non-zero, and `prometheus_tsdb_head_min_time` stops advancing.

**Root cause.** Size retention counts **blocks only**. If compaction or checkpointing fails (permissions, a corrupt `chunks_head` segment, out-of-disk during the block write itself), the head is never truncated. The WAL keeps every segment, and the server spirals: no space to write the block that would free the space.

**Fix.**
1. Free space: expand the PV, or delete the oldest blocks manually while the server is stopped.
2. Restart and check that `prometheus_tsdb_head_min_time` jumps forward after the next compaction.
3. Find the original error in the logs (`compaction failed`, `create checkpoint`).

**Prevention.**
- Alert on the failure counters (§2.3).
- Set `retention.size` ≤ ~85% of the PV, leaving room for ~2× the 3 h WAL plus `chunks_head`.
- Use `retention.percentage` (3.11+) where volumes are resized online.

### F3. Storage bill doubles after moving Prometheus to "burstable" nodes

**Symptom.** Block bytes per day rose 40–90% with no change in series count. Remote-write egress and object-store bills follow.

**Signature.** `rate(prometheus_tsdb_compaction_chunk_size_bytes_sum[1d]) / rate(prometheus_tsdb_compaction_chunk_samples_sum[1d])` (bytes per sample) climbs from ~1.3 to 2.5+. `prometheus_target_interval_length_seconds{quantile="0.99"}` drifts above the configured interval. `container_cpu_cfs_throttled_periods_total` for the Prometheus container is high.

**Root cause.**
- CPU throttling delays scrape goroutines by more than the 2 ms alignment tolerance, so most dods are non-zero and each costs 16 bits instead of 1 (L1 W2 → W3: 2.09 → 3.84 B/sample).
- The same lateness also degrades `rate()` accuracy (Folder 02).

**Fix.** Remove the CPU limit, or set requests to the measured p99 CPU. Pin Prometheus to non-burstable instance types. Check that the ratio returns to baseline within one block cycle.

**Prevention.**
- Dashboard bytes-per-sample next to scrape-interval jitter.
- Treat the observability tier as latency-sensitive in the scheduling policy.
- Budget storage per *sample* from your own measured ratio, never from a blog's "1.3 bytes".

### F4. XOR2 enabled, then a rollback or a Thanos store breaks every query

**Symptom.** After rolling back Prometheus, or in a sidecar-uploaded block, queries fail with chunk-encoding errors. Panels go blank for the time range written with the new encoding.

**Signature.** Errors mention an unknown chunk encoding. Only blocks whose `meta.json` minTime is after the XOR2 rollout are affected.

**Root cause.**
- `storage.tsdb.chunk_encoding.floats: xor2` writes `EncXOR2 = 4` chunks.
- Pre-3.11 readers, and LTS components that read blocks directly (sidecar uploads, store gateways, compactors), cannot decode them.
- 3.14 even fixed a bug where compaction *silently reverted* XOR2 to XOR, so mixed blocks exist in the wild.

**Fix.** Roll forward rather than back. Upgrade every block reader. If you must roll back, delete or re-encode the affected blocks, accepting data loss for that window.

**Prevention.** Treat chunk encoding as an on-disk *format migration*:
1. Inventory every component that opens blocks.
2. Enable XOR2 in one canary with no uploader.
3. Run a full compaction cycle (≥ 18 h).
4. Then flip the fleet.

### F5. Restart takes 45 minutes and the HA pair is down together

**Symptom.** A config rollout restarts both replicas. Dashboards show a gap of 30–60 minutes and alerts do not fire.

**Signature.** `prometheus_tsdb_data_replay_duration_seconds` is in the thousands of seconds. `/-/ready` returns 503 throughout. The rollout restarted the pods in parallel (`podManagementPolicy: Parallel` with `maxUnavailable` > 1, or a node drain).

**Root cause.** Replay is proportional to the WAL (§1.9): up to 3 h of samples plus a Series record per series. Clean shutdowns without `memory-snapshot-on-shutdown` replay everything. Restarting both members of an HA pair at once removes the redundancy the pair exists for.

**Fix.** Restart replicas one at a time and wait for `/-/ready`. Enable `memory-snapshot-on-shutdown` and give `terminationGracePeriodSeconds` enough time to write it.

**Prevention.**
- Use a PodDisruptionBudget of `maxUnavailable: 1` per HA pair.
- Apply config changes with `/-/reload` (`--web.enable-lifecycle`) or `--config.auto-reload` instead of restarting. Auto-reload was promoted to stable in 3.12; the old `auto-reload-config` feature flag is deprecated.
- Alert on `up{job="prometheus"} == 0` from the *other* replica or a meta-monitor.

### F6. Out-of-order rejections after enabling OTLP ingestion

**Symptom.** OTLP or remote-write clients log HTTP 400s, and some series have gaps while others are fine.

**Signature.** `prometheus_tsdb_out_of_order_samples_total` or `prometheus_tsdb_too_old_samples_total` is rising. `prometheus_tsdb_sample_ooo_delta` (3.9+) shows deltas of seconds to minutes.

**Root cause.**
- Push pipelines batch and retry. Two collectors (or a retry after a timeout) can deliver an older sample after a newer one for the same series.
- With `out_of_order_time_window: 0`, the head rejects anything older than the series' last sample.
- A rejected sample is a 4xx, which the client treats as non-recoverable and drops. 3.11 fixed the remaining histogram write paths that returned 500 instead of 400, which had caused retry loops.

**Fix.** Set `out_of_order_time_window` to the p99.9 of `prometheus_tsdb_sample_ooo_delta`, typically 5–30 m, on the receiving Prometheus only.

**Prevention.**
- Keep scrape-only servers at 0, because OOO costs a WBL plus small chunks plus vertical compaction.
- Ensure exactly one collector writes each series, using a consistent-hash load-balancing exporter (Folder 06).

### F7. A "small" exporter quadruples block size

**Symptom.** One team's new exporter, with ~2% of series, accounts for ~10% of block bytes.

**Signature.** Per-job bytes per sample from `promtool tsdb analyze` on a block, or from sampling chunks of that job with L3 in File 02, is 7–8 B/sample against a fleet average of ~1.5.

**Root cause.** The exporter publishes high-entropy floats: unrounded ratios, `*_seconds_total` accumulated from fractional increments, or gauges recomputed from noisy inputs. XOR compression is a bet on low entropy (L1 W4/W6).

**Fix.**
- Round at the source where precision is meaningless, e.g. a ratio to 4 significant digits.
- Expose integer counters (`*_microseconds_total` as integer) instead of float accumulations.
- Drop raw series you only use through recording rules.

**Prevention.** Include bytes-per-sample in exporter review checklists, and chargeback storage per job (Folder 08).

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Walk me through what happens when Prometheus ingests one sample."</b></summary>

**Initial Prompt.** A scrape returns `http_requests_total{code="200"} 1047`. Take me from there to disk.

**L5 Textbook Answer.** It is appended to the head block in memory and written to the WAL. Every two hours the head is flushed to a block on disk, and blocks are compacted later.

**Why L5 Fails at 3 AM or on the Bill.** It cannot explain why the pod OOMs every two hours, why restarts take 40 minutes, or why a power cut lost data while an OOMKill did not. The answer lacks the order of operations (WAL before memory, one write per batch, fsync per segment), the 3 h trigger, and where series memory comes from.

**L7 Principal Defense.**
1. The appender buffers the sample. On `Commit()`, Series records for new series and then a Samples record go to the WAL in one page-flushed `write(2)`. Fsync happens only at segment rotation, so a process kill is safe and a host crash can tear the tail.
2. Each series then runs `appendPreprocessor`:
   - cut a chunk at the predicted end time, computed at 30 samples so the rest of the 2 h range splits evenly, at 240 samples, or at a range boundary;
   - append Gorilla-style XOR bits: 1 bit for an on-grid dod plus ~13 bits for a small counter delta.
3. Full chunks are m-mapped from `chunks_head` and leave the heap.
4. When the head spans more than 3 h, the oldest 2 h is written as a block, head series with no remaining samples are GC'd, and the WAL is checkpointed over its oldest two thirds.

Each of those is a capacity lever: series → heap, WAL → RTO, 3 h → churn peak, dod → bytes.
</details>

<details><summary><b>Q2 · "Why is the default block 2 hours? Make it 30 minutes and save memory."</b></summary>

**Initial Prompt.** Our head uses 40 GiB. Let's set `--storage.tsdb.min-block-duration=30m` so less data sits in memory.

**L5 Textbook Answer.** Smaller blocks mean the head holds less data, so memory goes down. We would get more blocks, but compaction merges them.

**Why L5 Fails at 3 AM or on the Bill.**
- Head memory is dominated by **series**, not samples (§1.12). A 30 m head still holds every active series plus every series churned in the last 45 minutes, so the saving is modest.
- Chunks become tiny: 30 m at a 15 s interval is 120 samples, still fine. At 60 s it is 30 samples, so compression degrades (§1.7).
- Every block has a full index whose cost is per series. Four times more blocks means four times more index writes and more compaction CPU.
- The flag is hidden and "for use in testing". It also interacts with Thanos/Mimir uploaders, which expect 2 h blocks.

**L7 Principal Defense.**
1. Measure first. Divide `go_memstats_heap_inuse_bytes` by head series, and compare churn (`increase(prometheus_tsdb_head_series_created_total[3h])`) with active series.
2. If churn dominates, the lever is label hygiene and early stale-series eviction (3.10+ `stale_series_compaction_threshold`), not block size.
3. If series count dominates, shard by hashmod across more replicas, or move long-term storage out (Mimir/Thanos).
4. Leave the 2 h block alone. It is the unit that the WAL truncation math, uploaders and the compaction ladder are all built around.
</details>

<details><summary><b>Q3 · "Explain Gorilla compression to me in bits."</b></summary>

**Initial Prompt.** How does Prometheus get a 16-byte sample down to about 1.4 bytes?

**L5 Textbook Answer.** Timestamps are delta-of-delta encoded and values are XOR-ed with the previous value, keeping only the meaningful bits. That is from Facebook's Gorilla paper.

**Why L5 Fails at 3 AM or on the Bill.** The answer stops at the paper. It cannot predict which workloads break the ratio: jitter beyond 2 ms, float accumulations, random gauges. So it cannot explain a 2× bill increase or veto a high-entropy exporter. It also misses Prometheus's millisecond buckets and the 3.15 XOR2 change.

**L7 Principal Defense.**
1. Timestamps: 1 bit when on grid; otherwise '10' + 14 bits, '110' + 17, '1110' + 20, or '1111' + 64. The range is the asymmetric `−(2ⁿ⁻¹−1)..2ⁿ⁻¹`.
2. Values: '0' if identical. '10' + payload reuses the previous leading/trailing-zero window. '11' + 5-bit leading (clamped to 31) + 6-bit length + payload opens a new window.
3. On a real counter that is 1 + ~13 bits per sample, about 1.7–2.1 B (L1).
4. The ratio is a property of the data: random floats need ~7.4 B and late scrapes add 16 bits each. That is why I watch bytes-per-sample per job and scrape-interval jitter, not just series count.
5. XOR2 (3.15) jointly encodes dod and value, so a flat series costs 1 bit/sample instead of 2. It is only worth enabling once every block reader supports it.
</details>

<details><summary><b>Q4 · "Is Prometheus durable? Could we lose the last minute of data?"</b></summary>

**Initial Prompt.** Compliance asks whether Prometheus loses data on crash.

**L5 Textbook Answer.** No, it has a write-ahead log, so data is replayed after a crash.

**Why L5 Fails at 3 AM or on the Bill.** It conflates *process* crashes with *host* crashes, and it ignores the HA design. During an AZ power event, the tail of the open 128 MiB segment may never have been fsynced, the replay truncates at the first bad CRC, and the gap appears on both replicas if they share a fate domain.

**L7 Principal Defense.**
1. A process kill loses nothing written via `write(2)`, because the page cache survives.
2. A host or kernel crash can lose or tear data since the last segment fsync. Prometheus fsyncs on rotation, not per commit, which is the right throughput trade-off for metrics.
3. Durability for metrics comes from **redundancy**, not fsync:
   - two replicas in different AZs scraping the same targets;
   - deduplication downstream on the `replica` external label (Mimir/Thanos);
   - and, where the sink matters, remote write to a replicated store.
4. I state the RPO honestly: one replica loses at most the unsynced tail, and the pair loses nothing unless both fail together.
</details>

<details><summary><b>Q5 · "Our WAL disk filled up but retention.size is set. How?"</b></summary>

**Initial Prompt.** We set `retention.size: 400GB` on a 500 GB disk and still ran out of space.

**L5 Textbook Answer.** Retention runs periodically, so it probably lagged. Increase the disk or lower the retention size.

**Why L5 Fails at 3 AM or on the Bill.** Size retention counts **blocks only**. The WAL, the checkpoint and `chunks_head` are outside it. If compaction or checkpointing is failing, the WAL grows without bound and no retention setting helps. Adding disk just postpones the same incident.

**L7 Principal Defense.**
1. Check `prometheus_tsdb_wal_storage_size_bytes` and the compaction and checkpoint failure counters.
2. If they are non-zero, the head is stuck. Fix the root error, which is usually permissions, a corrupt head chunk file or ENOSPC during the block write itself.
3. Size the volume as: blocks (retention) + ~2 × 3 h of compressed WAL + one Series record per active series + `chunks_head` + 10–15% slack.
4. Alert on the failure counters and on WAL growth, not on disk percentage alone.
</details>

<details><summary><b>Q6 · "Should we enable out-of-order ingestion everywhere? It sounds safer."</b></summary>

**Initial Prompt.** OOO ingestion stops rejecting late samples. Why not set a 1 h window globally?

**L5 Textbook Answer.** Yes. It accepts late data, which avoids gaps, and the performance cost is small.

**Why L5 Fails at 3 AM or on the Bill.**
- OOO adds the WBL and an OOO head chunk of at most 32 samples per series, which means worse compression and more chunk objects.
- OOO blocks overlap in-order blocks until vertical compaction merges them, so queries read more.
- On scrape-only servers it hides real problems, such as clock skew or duplicate targets, that should be fixed instead of absorbed.

**L7 Principal Defense.**
1. Enable it only on receivers whose ingestion path genuinely reorders: OTLP, remote-write fan-in, backfill.
2. Size the window from `prometheus_tsdb_sample_ooo_delta`.
3. Keep scrape servers at 0 so OOO errors remain a signal.
4. Watch the OOO metrics (`prometheus_tsdb_head_out_of_order_samples_appended_total`, WBL size). If OOO volume is large, fix the producer (one writer per series), because OOO is a pressure-relief valve, not a design.
</details>

<details><summary><b>Q7 · "How much memory per series? Give me a number."</b></summary>

**Initial Prompt.** We're planning 20 M active series. How much RAM?

**L5 Textbook Answer.** Roughly 3 KB per series, so about 60 GB. Add some buffer.

**Why L5 Fails at 3 AM or on the Bill.** A single constant hides the drivers:
- label bytes, since stringlabels does no cross-series interning;
- churn within the 1–3 h head window, which can be 3–8× active;
- GC headroom (GOGC 75);
- query working sets.

20 M on one Prometheus also ignores that a single head this large means a multi-hour WAL replay and a blast radius of 20 M series.

**L7 Principal Defense.**
1. Build the number structurally: ~1.4 KiB live per 14-label series, ×1.75 for GC, giving 2.4 KiB (§1.12).
2. Multiply by the **churn peak**, not active: `max_over_time(prometheus_tsdb_head_series[7d])`. Then add a query budget.
3. Calibrate on one production replica with `go_memstats_heap_inuse_bytes / prometheus_tsdb_head_series`.
4. Architect so that no single Prometheus exceeds a few million head series: shard by hashmod or by team, and push long-term and global views to Mimir/Thanos (Folder 06).
5. The answer to "20 M" is "five to ten shards plus a horizontally scalable backend", not "one 60 GB box".
</details>

<details><summary><b>Q8 · "What does XOR2 buy us, and would you turn it on?"</b></summary>

**Initial Prompt.** The 3.15 changelog says XOR2 compresses better. Should we flip it today?

**L5 Textbook Answer.** Yes. Better compression means less disk and it is marked stable.

**Why L5 Fails at 3 AM or on the Bill.**
- The gain is concentrated in constant series and stale markers. Elsewhere it is about ±1%, and it is worse for dods of 4–8 s. The headline saving may be 5–10%, not 30%.
- The real risk is format compatibility. Older Prometheus versions and block-reading LTS components cannot read XOR2 chunks, so a rollback or an old store gateway makes queries fail for that window.

**L7 Principal Defense.**
1. Quantify with my own data. Measure the share of series that are constant over 30 minutes, multiply by the ~29% per-chunk gain (L1 W1), and compare with the ~1-byte header cost per chunk.
2. Inventory every block reader.
3. Canary on a replica that uploads nowhere for one full compaction cycle.
4. Then roll forward with a documented no-rollback window.
5. The bigger strategic value is that XOR2 is the substrate for start-timestamp storage (`st-storage`). That improves `rate()` correctness for counters that start mid-window, and may justify it even where bytes do not.
</details>

<details><summary><b>Q9 · "Why does scraping every 5 minutes not save 20× storage versus 15 seconds?"</b></summary>

**Initial Prompt.** Finance wants us to scrape low-value jobs every 5 minutes to cut storage 20×.

**L5 Textbook Answer.** It will. 20× fewer samples means 20× less storage.

**Why L5 Fails at 3 AM or on the Bill.**
- Chunks cannot cross the 2 h boundary, so 300 s scrapes give 24-sample chunks. The per-chunk overhead (first sample ~14 B, chunk framing, index chunk metadata) is amortized over 5× fewer samples, so bytes/sample rises ~35% (L2: 1.6 → 2.17).
- Series memory is unchanged, because the head cost is per series.
- `rate()` over a 5 m window now sees 1–2 samples and returns nothing or noise. Every dashboard needs ≥ 4× the interval (Folder 02).

**L7 Principal Defense.**
1. The storage saving is ~15×, not 20×, and the memory saving is ~0.
2. The real costs are query semantics and alert latency.
3. For low-value data I would rather drop series entirely (`metric_relabel_configs`), or pre-aggregate with recording rules and drop the raw series.
4. If a long interval is still right, keep it ≤ 2 minutes. Otherwise staleness (5 m lookback) turns every gap into a flapping absent series.
</details>

---

## 5. Invariants checklist

- [ ] Memory is planned per **head series at the churn peak**, calibrated on `go_memstats_heap_inuse_bytes / prometheus_tsdb_head_series`.
- [ ] The WAL volume budget is ≥ 2 × (3 h of compressed samples + one Series record per active series), outside `retention.size`.
- [ ] Alerts exist on `prometheus_tsdb_compactions_failed_total`, `prometheus_tsdb_checkpoint_creations_failed_total` and `prometheus_tsdb_wal_corruptions_total`.
- [ ] The readiness probe tolerates the measured `prometheus_tsdb_data_replay_duration_seconds`. HA replicas restart one at a time, and `memory-snapshot-on-shutdown` is on.
- [ ] Prometheus is not CPU-throttled. Scrape-interval p99 jitter is under 2 ms of tolerance, and bytes/sample is dashboarded per job.
- [ ] `out_of_order_time_window` is non-zero only on push/OTLP receivers, and sized from `prometheus_tsdb_sample_ooo_delta`.
- [ ] XOR2 / `st-storage` are enabled only after every block reader in the path supports `EncXOR2`. Treat it as a format migration.
- [ ] Retention is in the config file (`storage.tsdb.retention.*`), not the deprecated flags, with `size` ≤ ~85% of the volume.
- [ ] `--auto-gomemlimit` is on with a ratio ≤ 0.85, there is no CPU limit, and request == limit for memory.

---

## 6. References

- Prometheus v3.15.1 release (2026-10-21): <https://github.com/prometheus/prometheus/releases/tag/v3.15.1>
- Chunks on-disk format (XOR, XOR2, histograms): <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/docs/format/chunks.md>
- Head chunks format: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/docs/format/head_chunks.md>
- WAL format: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/docs/format/wal.md>
- XOR encoder: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/chunkenc/xor.go>
- XOR2 encoder: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/chunkenc/xor2.go>
- Head, stripeSeries, compaction trigger, WAL truncation: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/head.go>
- Chunk cutting (`appendPreprocessor`, `computeChunkEndTime`): <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/head_append.go>
- WAL writer (pages, fragments, fsync): <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/wlog/wlog.go>
- Storage documentation (retention, OOO, sizing): <https://prometheus.io/docs/prometheus/latest/storage/>
- Configuration reference, `<tsdb>` block: <https://prometheus.io/docs/prometheus/latest/configuration/configuration/>
- Feature flags (memory snapshot, st-storage, xor2): <https://prometheus.io/docs/prometheus/latest/feature_flags/>
- Scrape timestamp jitter issue #7846: <https://github.com/prometheus/prometheus/issues/7846>
- Pelkonen et al., "Gorilla: A Fast, Scalable, In-Memory Time Series Database", VLDB 2015: <https://www.vldb.org/pvldb/vol8/p1816-teller.pdf>
- Ganesh Vernekar, "Prometheus TSDB" blog series (head, WAL, mmap, compaction): <https://ganeshvernekar.com/blog/prometheus-tsdb-the-head-block/>
