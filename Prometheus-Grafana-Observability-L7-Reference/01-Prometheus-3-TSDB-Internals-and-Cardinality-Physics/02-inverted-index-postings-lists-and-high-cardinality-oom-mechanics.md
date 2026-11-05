# 02 · Inverted Index, Postings Lists and High-Cardinality OOM Mechanics

> **Folder 01: Prometheus 3 TSDB Internals and Cardinality Physics. File 2 of 4.**
> Pinned to **Prometheus v3.15.1**; source read at tag `v3.15.1`.
> Labels: **[D]** documented or read in pinned source. **[M]** measured by a listing here (deterministic, re-run by the gate). **[E]** model with stated assumptions. **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L3 `tsdb_block_reader.py` | Reads a **real block written by Prometheus 2.0.0** byte by byte: magic numbers, every CRC32C, symbol table, series, postings offset table and postings, plus all 102 XOR chunks. It matches the samples asserted by Prometheus's own Go test and re-encodes every chunk byte-identically. It then writes and re-reads a format-V2 index for a 15,600-series Kubernetes fleet and attributes every byte | ~2 s |
| L4 `postings_lab.py` | Port of `MemPostings` + `PostingsForMatchers` (intersect / merge / without, `labelMustBeSet`, the `l=""` rule, `.*`/`.+` shortcuts, set-regex fast path), checked against brute force on 20 selectors. Also the `/api/v1/status/tsdb` statistics, the cardinality product law, and a 6 h rolling-deploy churn simulation | ~2 s |

**Verification.** The fixture `fixtures/prometheus-v3.15.1-testdata/index_format_v1/` is copied verbatim from `tsdb/testdata/index_format_v1` in the Prometheus repository (Apache-2.0) at tag v3.15.1.
- Its expected content is asserted by `TestReadIndexFormatV1` in `tsdb/block_test.go`: `{foo="bar"}` → (1, 2), `{foo="baz"}` → (3, 4), and `foo!~"^.?$"` selects exactly those two series.
- L3 must reproduce all three facts and pass every checksum. L4's matcher engine must equal a brute-force scan on every selector.
- No live Prometheus server was run (binary execution was not permitted in the build environment).

---

## 0. Orientation

**What this file answers.**
- How a label selector becomes a set of series IDs.
- Why that is cheap for `{job="api"}` and ruinous for `{pod=~".*x.*"}`.
- Why "cardinality" is the single variable that explains most Prometheus OOMs and most observability bills.

**A correction to the brief.** Prometheus does **not** use Roaring bitmaps [D].
- Head postings are plain sorted `[]storage.SeriesRef` slices.
- Block postings are written by `EncodePostingsRaw`: a 4-byte big-endian count followed by 4-byte big-endian series IDs, with a CRC.
- The index writer has a pluggable `PostingsEncoder` (`NewWriterWithEncoder`) and the reader a `PostingsDecoder`, so downstream projects can experiment. The upstream default is raw.

Where you *do* meet compressed bitmaps or compressed postings in this landscape:
- Lucene/Elasticsearch (Roaring-style doc-ID sets in filter caches).
- ClickHouse (`groupBitmap*` functions over Roaring).
- Druid/Pinot (Roaring/Concise bitmap indexes).
- ⚠ Thanos and Mimir store-gateways, which compress postings in their *caches*. Implementation details vary by release, so check the version you run.

The interview-grade point: raw sorted lists are chosen because **series IDs in a block are ordinal in label order** and lists are merge-joined with `Seek`. The CPU cost is dominated by the number of postings *read*, not by decode speed.

**Mental model.** A selector is boolean algebra over postings lists:

```text
 {__name__="http_requests_total", code=~"5..", env!="dev"}
   = postings(__name__="http_requests_total")
   ∩ ⋃_{v ∈ values(code), v matches 5..} postings(code=v)
   − postings(env="dev")
```

Cost = Σ lengths of the lists you touch + the number of label **values** you run a regex against. Memory = the number of series each list points to, held for the life of the head.

---

## 1. First principles: postings, IDs and the algebra of selectors

### 1.1 The head's inverted index: `MemPostings`

```text
 MemPostings.m : map[labelName] map[labelValue] []SeriesRef      (sorted ascending)
 ┌─────────────────────────────────────────────────────────────────────────────────┐
 │ ""          → { "" : [1 2 3 4 5 6 … N] }   ◄─ the all-postings key (AllPostingsKey)│
 │ __name__    → { "http_server_duration_seconds_bucket": [3 4 5 … ],               │
 │                 "container_cpu_usage_seconds_total":   [1 219 437 …] }           │
 │ pod         → { "checkout-000a3f1c-7b2e": [1 2 3 … 218],  … 300 values … }        │
 │ le          → { "0.005": [3 15 27 …], …, "+Inf": [14 26 38 …] }                   │
 │ lvs         : map[labelName][]labelValue   (value lists for LabelValues())       │
 └─────────────────────────────────────────────────────────────────────────────────┘
 Add(ref, lset): for each (n,v) in lset + ("",""):  m[n][v] = append(m[n][v], ref)
   refs are a monotonically increasing counter ⇒ append keeps every list sorted (no insert cost)
 Delete(deleted, affected): rebuild only the affected (n,v) lists during head GC
 EnsureOrder(): sort all lists once after a parallel WAL replay (refs arrive out of order)
```

Each label pair of each series costs one 8-byte `SeriesRef` slot (plus slice growth slack) **for as long as the series is in the head**. Churned series stay until the next head GC (File 01 §1.9). A unique label value (a pod name, a request ID) also costs a map entry: a string header plus a slice header plus the map's control word.

### 1.2 The block index (format V2)

```text
 index file
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ magic 0xBAAAD700 <4B> │ version <1B> = 2                                    │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Symbol table   len<4B> #symbols<4B> {uvarint len, utf-8 bytes}… CRC32C<4B>  │
 │   sorted, deduplicated; V2 references symbols by SEQUENCE NUMBER            │
 │   (V1 used byte offsets); reader keeps every 32nd offset (symbolFactor)     │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Series         each entry 16-byte aligned; series ID = offset / 16          │
 │   len<uvarint> #labels {nameRef valueRef}… #chunks                          │
 │   c0: mint<varint> maxt-mint<uvarint> ref<uvarint>                          │
 │   ci: mint-prevMaxt<uvarint> maxt-mint<uvarint> Δref<varint>   CRC32C       │
 │   series sorted by label set ⇒ ID order == label order                      │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Label indices  (legacy; still written, unused by the V2 reader)             │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Postings       per (name,value): len<4B> #entries<4B> {seriesID <4B BE>}…   │
 │                CRC32C   — EncodePostingsRaw; no compression                 │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Label offset table (legacy)                                                 │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Postings offset table  SORTED by (name,value): {n=2, name, value, offset}   │
 │   reader keeps every 32nd value per name (+ first/last) in memory, then     │
 │   binary-searches and scans ≤ 31 entries from disk/page cache               │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ TOC  6 × <8B> section offsets + CRC32C   (fixed 52 bytes at end of file)    │
 └─────────────────────────────────────────────────────────────────────────────┘
```

Three design decisions to defend in an interview [D]:

1. **Series ID = offset/16, assigned in label-sorted order.** Postings lists are then sorted in the same order as the series section. The query path can merge-join lists *and* read series sequentially. The 16-byte alignment trades a few bytes per series for a 4-byte ID addressing up to 64 GiB of series data.
2. **A sorted postings offset table with 1-in-32 sampling.** V1 (Prometheus 2.0) wrote the table unsorted, and the reader loaded it entirely into a map. L3 confirms the real 2.0 block's table is unsorted, starting `('bar','42'), ('bar','68'), ('bar','1')`. V2 sorts it, so opening a block costs memory proportional to 1/32 of its label pairs.
3. **Raw postings.** Decoding 4-byte big-endian integers is trivial. Intersection cost is the number of `Seek`s, which raw lists support with binary search.

### 1.3 The real block, decoded (L3)

L3 Part A opens the Prometheus 2.0.0 block and walks every structure [M]:
- `index` (5,407 B, format **v1**) and `chunks/000001` (1,844 B).
- A TOC pointing at symbols@5, series@323, postings@2248 and postings-offset-table@4326.
- 104 symbols.
- 103 postings-table entries: 102 label pairs plus the `("","")` all-postings key.
- 102 series whose V1 IDs are **byte offsets** (323, 336, 349, …), not offset/16.

All 106 index CRCs and 102 chunk CRCs verify. Decoding gives exactly the Go test's oracle. Each 1-sample chunk is 12 bytes, and re-encoding with the Prometheus 2.0 bit-stream variant reproduces every chunk byte-for-byte (File 01 §1.4).

Part B writes a V2 index for 15,600 series of a realistic Kubernetes fleet: 400 pods × (3 cAdvisor series + a 3-route × 2-code × 6-bucket histogram) [M]:
- **102.6 B per series in the index**, against 184 B/series of raw label text. The symbol table deduplicates `job`, `namespace`, metric names and `le` values to 1,233 strings.
- 57% of the index is the series section; it is per-series, with 16-byte alignment padding.
- 39% is postings: 4 B × label pairs, 138,000 pairs here.
- 2.4% is the postings offset table.

The capacity rule that falls out [E]:

> **index bytes ≈ series × (≈ 40 + 4·labels_per_series + 3·chunks_per_series) + unique label text.**

The index is per *block*, so the same series is indexed again in each overlapping 2 h block until compaction merges them. High churn multiplies index size, because each block indexes every series that was alive in its window.

<!-- listing:tsdb_block_reader.py -->
```python
"""tsdb_block_reader.py - read a real Prometheus TSDB block byte by byte, and write + re-read a
format-V2 index, following tsdb/docs/format/{index,chunks}.md at tag v3.15.1.

Part A reads fixtures/prometheus-v3.15.1-testdata/index_format_v1 (copied verbatim from the
Prometheus repo, tsdb/testdata/index_format_v1, written by Prometheus 2.0.0 per the comment in
tsdb/block_test.go TestReadIndexFormatV1). It checks magic numbers and every CRC32C, decodes the
symbol table, series, postings offset table, postings lists and every XOR chunk, then compares
against the oracle asserted by that Go test: {foo="bar"} -> (1, 2), {foo="baz"} -> (3, 4) and the
matcher foo!~"^.?$" selecting exactly those two series.
It also re-encodes every chunk with xor_chunk.xor_encode(legacy=True) and requires byte equality.

Part B writes a V2 index (sorted symbols referenced by sequence number, 16-byte-aligned series,
ID = offset/16, raw 4-byte big-endian postings, sorted postings offset table) for a synthetic
Kubernetes fleet, re-reads it with the same reader, and reports where the bytes go.

Usage: python tsdb_block_reader.py <target.md>   (fixtures are resolved relative to target.md)
"""
import json
import pathlib
import random
import struct
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from wal_head_lab import crc32c  # noqa: E402
from xor_chunk import put_varint, xor_decode, xor_encode  # noqa: E402

MAGIC_INDEX, MAGIC_CHUNKS = 0xBAAAD700, 0x85BD40DD


def uvarint(b, pos):
    x = s = 0
    while True:
        c = b[pos]
        pos += 1
        x |= (c & 0x7F) << s
        if c < 0x80:
            return x, pos
        s += 7


def varint(b, pos):
    ux, pos = uvarint(b, pos)
    return (-(ux >> 1) - 1 if ux & 1 else ux >> 1), pos


def put_uvarint(x):
    out = bytearray()
    while x >= 0x80:
        out.append((x & 0x7F) | 0x80)
        x >>= 7
    out.append(x)
    return bytes(out)




class Index:
    def __init__(self, b: bytes):
        self.b, self.crc_ok, self.crc_n = b, True, 0
        magic, self.version = struct.unpack_from(">IB", b, 0)
        assert magic == MAGIC_INDEX, hex(magic)
        toc = b[-52:]
        self._crc(toc[:48], struct.unpack_from(">I", toc, 48)[0])
        (self.t_symbols, self.t_series, self.t_lidx, self.t_ltable, self.t_postings,
         self.t_ptable) = struct.unpack_from(">6Q", toc, 0)
        self.symbols, self.sym_by_off = self._read_symbols()
        self.ptable = self._read_postings_table()

    def _crc(self, data, want):
        self.crc_n += 1
        self.crc_ok &= crc32c(data) == want

    def _section(self, off):  # len <4b> | body | CRC32 <4b>
        ln = struct.unpack_from(">I", self.b, off)[0]
        body = self.b[off + 4: off + 4 + ln]
        self._crc(body, struct.unpack_from(">I", self.b, off + 4 + ln)[0])
        return body, off + 4

    def _read_symbols(self):
        body, base = self._section(self.t_symbols)
        n, pos, syms, by_off = struct.unpack_from(">I", body, 0)[0], 4, [], {}
        for _ in range(n):
            ln, p2 = uvarint(body, pos)
            s = body[p2:p2 + ln].decode()
            by_off[base + pos] = s  # V1 refs are absolute file offsets of the entry
            syms.append(s)
            pos = p2 + ln
        return syms, by_off

    def sym(self, ref):
        return self.sym_by_off[ref] if self.version == 1 else self.symbols[ref]

    def _read_postings_table(self):
        body, _ = self._section(self.t_ptable)
        n, pos, out = struct.unpack_from(">I", body, 0)[0], 4, []
        for _ in range(n):
            assert body[pos] == 2
            pos += 1
            kv = []
            for _ in range(2):
                ln, pos = uvarint(body, pos)
                kv.append(body[pos:pos + ln].decode())
                pos += ln
            off, pos = uvarint(body, pos)
            out.append((kv[0], kv[1], off))
        return out

    def postings(self, off):
        body, _ = self._section(off)
        n = struct.unpack_from(">I", body, 0)[0]
        return list(struct.unpack_from(f">{n}I", body, 4))

    def series(self, ref):
        off = ref if self.version == 1 else ref * 16
        ln, pos = uvarint(self.b, off)
        body = self.b[pos:pos + ln]
        self._crc(body, struct.unpack_from(">I", self.b, pos + ln)[0])
        p = 0
        nl, p = uvarint(body, p)
        lbls = []
        for _ in range(nl):
            a, p = uvarint(body, p)
            v, p = uvarint(body, p)
            lbls.append((self.sym(a), self.sym(v)))
        nc, p = uvarint(body, p)
        chunks, maxt, cref = [], 0, 0
        for i in range(nc):
            if i == 0:
                mint, p = varint(body, p)
                d, p = uvarint(body, p)
                maxt = mint + d
                cref, p = uvarint(body, p)
            else:
                d, p = uvarint(body, p)
                mint = maxt + d
                d, p = uvarint(body, p)
                maxt = mint + d
                dr, p = varint(body, p)
                cref += dr
            chunks.append((mint, maxt, cref))
        return lbls, chunks


def read_chunk(segments, ref):
    seg, off = ref >> 32, ref & 0xFFFFFFFF
    b = segments[seg]
    ln, pos = uvarint(b, off)
    enc, data = b[pos], b[pos + 1: pos + 1 + ln]
    ok = crc32c(b[pos: pos + 1 + ln]) == struct.unpack_from(">I", b, pos + 1 + ln)[0]
    return enc, data, ok


def matches(lbls, name, op, rx):
    import re
    v = dict(lbls).get(name, "")
    hit = re.fullmatch(rx, v, re.S) is not None
    return hit if op == "=~" else not hit


def part_a(block: pathlib.Path, checks):
    print(f"== A. Real block written by Prometheus 2.0.0: {block.name} ==")
    meta = json.loads((block / "meta.json").read_text())
    idx = Index((block / "index").read_bytes())
    chunk_file = (block / "chunks" / "000001").read_bytes()
    magic, ver = struct.unpack_from(">IB", chunk_file, 0)
    checks.append(("chunks magic", magic == MAGIC_CHUNKS and ver == 1))
    print(f"meta.json: ulid {meta['ulid']}, [{meta['minTime']}, {meta['maxTime']}) ms, stats {meta['stats']}")
    print(f"index: {len(idx.b):,} B, magic 0x{MAGIC_INDEX:08X}, format version {idx.version}; "
          f"chunks/000001: {len(chunk_file):,} B, magic 0x{magic:08X}")
    print(f"TOC: symbols@{idx.t_symbols} series@{idx.t_series} label-indices@{idx.t_lidx} "
          f"label-offset-table@{idx.t_ltable} postings@{idx.t_postings} postings-offset-table@{idx.t_ptable}")
    print(f"symbol table: {len(idx.symbols)} strings, e.g. {idx.symbols[:4]} ... {idx.symbols[-3:]}")
    keys = [(n, v) for n, v, _ in idx.ptable]
    print(f"postings offset table: {len(keys)} entries; first {keys[:3]}; sorted? {keys == sorted(keys)}")
    checks.append(("V1 postings table unsorted (why V2 sorts it)", keys != sorted(keys)))
    allp = next(off for n, v, off in idx.ptable if n == "" and v == "")
    refs = idx.postings(allp)
    series, samples, reenc_ok, n_chunks = {}, {}, True, 0
    for ref in refs:
        lbls, chunks = idx.series(ref)
        key = "{" + ",".join(f'{n}="{v}"' for n, v in lbls) + "}"
        series[key] = lbls
        for mint, maxt, cref in chunks:
            enc, data, ok = read_chunk({0: chunk_file}, cref)  # ref>>32 = index of chunks/00000N, 0-based
            n_chunks += 1
            checks.append((f"chunk crc {key}", ok and enc == 1))
            dec = xor_decode(data)
            samples.setdefault(key, []).extend(dec)
            reenc_ok &= xor_encode(dec, legacy=True)[0] == data
            reenc_ok &= mint == dec[0][0] and maxt == dec[-1][0]
    print(f"series via all-postings key (\"\",\"\"): {len(refs)}; chunks decoded: {n_chunks}; "
          f"series refs are byte offsets in V1: {refs[:3]}...")
    print(f"CRC32C verified: {idx.crc_n} index sections/series + {n_chunks} chunks, all ok: {idx.crc_ok}")
    checks.append(("index CRCs", idx.crc_ok))
    checks.append(("legacy re-encode byte-identical", reenc_ok))
    oracle = {'{foo="bar"}': [(1, 2.0)], '{foo="baz"}': [(3, 4.0)]}
    got = {k: samples[k] for k in oracle}
    print(f"Go-test oracle {oracle} -> decoded {got}")
    checks.append(("oracle samples", got == oracle))
    sel = sorted(k for k, l in series.items() if "foo" in dict(l) and matches(l, "foo", "!~", "^.?$"))
    print(f'foo!~"^.?$" (with foo set) selects {sel}')
    checks.append(("oracle matcher", sel == ['{foo="bar"}', '{foo="baz"}']))
    bar = sorted(int(dict(l)["bar"]) for l in series.values() if "bar" in dict(l))
    checks.append(("bar 0..99 at (0,0)", bar == list(range(100)) and all(
        samples[k] == [(0, 0.0)] for k in series if k.startswith("{bar="))))
    print(f"bar series: {len(bar)} (values 0..99), each one sample (0, 0.0); "
          f"foo=\"meh\" at t=4h correctly absent: {'{foo=\"meh\"}' not in series}")
    print(f"every chunk is 1 sample, 12 B of XOR data: re-encoding with the 2.0 bstream reproduces "
          f"all {n_chunks} chunks byte-for-byte: {reenc_ok}")
    print()


def write_v2_index(series):
    """series: list of (sorted label tuple, [(mint, maxt, chunk_ref)]). Returns (bytes, stats)."""
    b = bytearray(struct.pack(">IB", MAGIC_INDEX, 2))
    stats = {}

    def section(body):
        b.extend(struct.pack(">I", len(body)) + body + struct.pack(">I", crc32c(body)))

    syms = sorted({s for lbls, _ in series for kv in lbls for s in kv} | {""})
    sym_id = {s: i for i, s in enumerate(syms)}
    t_sym = len(b)
    body = bytearray(struct.pack(">I", len(syms)))
    for s in syms:
        e = s.encode()
        body += put_uvarint(len(e)) + e
    section(bytes(body))
    stats["symbols"] = len(b) - t_sym
    series = sorted(series)
    while len(b) % 16:
        b.append(0)
    t_series, refs = len(b), []
    for lbls, chunks in series:
        while len(b) % 16:
            b.append(0)
        refs.append(len(b) // 16)
        body = bytearray(put_uvarint(len(lbls)))
        for n, v in lbls:
            body += put_uvarint(sym_id[n]) + put_uvarint(sym_id[v])
        body += put_uvarint(len(chunks))
        prev_maxt = prev_ref = 0
        for i, (mint, maxt, cref) in enumerate(chunks):
            if i == 0:
                body += put_varint(mint) + put_uvarint(maxt - mint) + put_uvarint(cref)
            else:
                body += put_uvarint(mint - prev_maxt) + put_uvarint(maxt - mint) + put_varint(cref - prev_ref)
            prev_maxt, prev_ref = maxt, cref
        b.extend(put_uvarint(len(body)) + body + struct.pack(">I", crc32c(bytes(body))))
    stats["series"] = len(b) - t_series
    plist = {}
    for ref, (lbls, _) in zip(refs, series):
        plist.setdefault(("", ""), []).append(ref)
        for kv in lbls:
            plist.setdefault(kv, []).append(ref)
    t_post, offsets = len(b), []
    for key in sorted(plist):
        while len(b) % 4:
            b.append(0)
        offsets.append((key, len(b)))
        ids = plist[key]
        section(struct.pack(f">I{len(ids)}I", len(ids), *ids))
    stats["postings"] = len(b) - t_post
    t_pt = len(b)
    body = bytearray(struct.pack(">I", len(offsets)))
    for (n, v), off in offsets:
        body += b"\x02" + put_uvarint(len(n.encode())) + n.encode() + put_uvarint(len(v.encode())) + v.encode() + put_uvarint(off)
    section(bytes(body))
    stats["postings offset table"] = len(b) - t_pt
    toc = struct.pack(">6Q", t_sym, t_series, 0, 0, t_post, t_pt)
    b.extend(toc + struct.pack(">I", crc32c(toc)))
    stats["toc+header"] = 52 + 5
    return bytes(b), stats, refs, plist


def fleet(rng, n_pods=400):
    """A k8s-like fleet: per pod, cAdvisor-ish container metrics + app RED metrics."""
    out = []
    for p in range(n_pods):
        ns = ("checkout", "cart", "search", "payments", "ads")[p % 5]
        pod = f"{ns}-{rng.getrandbits(32):08x}-{rng.getrandbits(20):05x}"
        node = f"ip-10-0-{p % 40}-{(p * 7) % 250}.ec2.internal"
        base = (("namespace", ns), ("pod", pod), ("node", node), ("job", "kubernetes-pods"),
                ("instance", f"10.1.{p // 250}.{p % 250}:8080"))
        for m in ("container_cpu_usage_seconds_total", "container_memory_working_set_bytes",
                  "container_network_receive_bytes_total"):
            out.append(tuple(sorted(base + (("__name__", m), ("container", "app")))))
        for route in ("/api/cart", "/api/item", "/healthz"):
            for code in ("200", "500"):
                for le in ("0.05", "0.1", "0.25", "0.5", "1", "+Inf"):
                    out.append(tuple(sorted(base + (("__name__", "http_server_request_duration_seconds_bucket"),
                                                    ("route", route), ("code", code), ("le", le)))))
    return out


def part_b(checks):
    print("== B. Write + re-read a V2 index for a synthetic k8s fleet (400 pods) ==")
    rng = random.Random(11)
    lsets = fleet(rng)
    series = [(l, [(0, 7_199_000, 8 + 40 * i)]) for i, l in enumerate(lsets)]
    data, stats, refs, plist = write_v2_index(series)
    idx = Index(data)
    back = [idx.series(r)[0] for r in refs]
    checks.append(("V2 round trip labels", [tuple(x) for x in back] == sorted(lsets)))
    checks.append(("V2 CRCs", idx.crc_ok))
    keys = [(n, v) for n, v, _ in idx.ptable]
    checks.append(("V2 postings table sorted", keys == sorted(keys)))
    n, raw = len(lsets), sum(len(k) + len(v) for l in lsets for k, v in l)
    print(f"series {n:,}; label pairs {sum(len(l) for l in lsets):,}; raw label text {raw:,} B "
          f"({raw / n:.0f} B/series); unique symbols {len(idx.symbols):,}")
    print(f"index {len(data):,} B = {len(data) / n:.1f} B/series:")
    for k, v in stats.items():
        print(f"   {k:<24} {v:>9,} B  {v / len(data):6.1%}")
    big = sorted(plist.items(), key=lambda kv: -len(kv[1]))[:4]
    print("largest postings lists: " + ", ".join(f'{k[0] or "<all>"}={k[1]!r}:{len(v)}' for k, v in big))
    one = sum(1 for v in plist.values() if len(v) == 1)
    print(f"postings lists of length 1 (pure overhead: 12 B framing for 4 B of payload): {one:,} of {len(plist):,}")
    print()


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    target = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else HERE / "x.md"
    block = target.parent / "fixtures" / "prometheus-v3.15.1-testdata" / "index_format_v1"
    checks = []
    part_a(block, checks)
    part_b(checks)
    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed[:6]}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:tsdb_block_reader.py -->
```text
== A. Real block written by Prometheus 2.0.0: index_format_v1 ==
meta.json: ulid 01DXXFZDYD1MQW6079WK0K6EDQ, [0, 7200000) ms, stats {'numSamples': 102, 'numSeries': 102, 'numChunks': 102}
index: 5,407 B, magic 0xBAAAD700, format version 1; chunks/000001: 1,844 B, magic 0x85BD40DD
TOC: symbols@5 series@323 label-indices@1806 label-offset-table@4300 postings@2248 postings-offset-table@4326
symbol table: 104 strings, e.g. ['0', '1', '10', '11'] ... ['baz', 'foo', 'meh']
postings offset table: 103 entries; first [('bar', '42'), ('bar', '68'), ('bar', '1')]; sorted? False
series via all-postings key ("",""): 102; chunks decoded: 102; series refs are byte offsets in V1: [323, 336, 349]...
CRC32C verified: 106 index sections/series + 102 chunks, all ok: True
Go-test oracle {'{foo="bar"}': [(1, 2.0)], '{foo="baz"}': [(3, 4.0)]} -> decoded {'{foo="bar"}': [(1, 2.0)], '{foo="baz"}': [(3, 4.0)]}
foo!~"^.?$" (with foo set) selects ['{foo="bar"}', '{foo="baz"}']
bar series: 100 (values 0..99), each one sample (0, 0.0); foo="meh" at t=4h correctly absent: True
every chunk is 1 sample, 12 B of XOR data: re-encoding with the 2.0 bstream reproduces all 102 chunks byte-for-byte: True

== B. Write + re-read a V2 index for a synthetic k8s fleet (400 pods) ==
series 15,600; label pairs 138,000; raw label text 2,877,782 B (184 B/series); unique symbols 1,233
index 1,600,253 B = 102.6 B/series:
   symbols                     26,163 B    1.6%
   series                     906,609 B   56.7%
   postings                   629,079 B   39.3%
   postings offset table       38,337 B    2.4%
   toc+header                      57 B    0.0%
largest postings lists: <all>='':15600, job='kubernetes-pods':15600, __name__='http_server_request_duration_seconds_bucket':14400, code='200':7200
postings lists of length 1 (pure overhead: 12 B framing for 4 B of payload): 0 of 1,223

checks: 112/112 passed
verdict: OK
```

### 1.4 `PostingsForMatchers`: the selector algorithm

The function in `tsdb/querier.go` is short. Every branch matters, and most cardinality bugs are someone misunderstanding one of them [D]:

```text
 1. labelMustBeSet[name] = true  if any matcher on name does NOT match ""
 2. subtracting(m) = !labelMustBeSet[m.name] || (m is != or !~ and m matches "")
 3. if every matcher is subtracting: start from ALL postings  ("" = "")
 4. process intersecting matchers first, then:
      =~ ".*"  → no-op            !~ ".*" → EMPTY result
      =~ ".+"  → ∪ all values     !~ ".+" → subtract ∪ all values
      label must be set:
        l!="foo" / l!~"a|b"   → subtract postings(l="foo")            (Without)
        l!=""                 → intersect ∪ all values of l
        l="a" / l=~"a|b"      → intersect postings (set-regex fast path: no regex run)
        l=~"a.*b"             → run regex over EVERY value of l, ∪ matching lists
      label NOT required (matcher matches ""):
        l="" / l=~"" / l=~"x|" → subtract series that HAVE l with a non-matching value
                                  ⇒ selects series WITHOUT the label too (issue #3575)
 5. result = Intersect(its…) then Without(result, each notIt)
```

L4 checks this against brute force on 20 selectors [M]. The cost columns explain real query latencies:

| Selector shape | Label values regex-tested | Postings entries read | Why |
|---|---|---|---|
| `{__name__="x", route="/cart", le="0.1"}` | 0 | 91,800 | Three equality lists, intersected by Seek |
| `{__name__="x", code=~"5.."}` | 3 | 86,400 | Regex over 3 `code` values: cheap because `code` is low-cardinality |
| `{__name__="y", pod=~"checkout-.*"}` | **300** | 16,650 | Regex over **every pod value**: cost grows with pod churn |
| `{__name__="z", env=""}` | 1 | 43,900 | Selects series **without** `env`, by subtracting those with it |
| `{namespace="payments", le!~".*"}` | 0 | 16,350 | `!~".*"` short-circuits to empty |
| `{job="app", method!~"GET\|POST"}` | 0 | 130,200 | Set fast path, but `job="app"` is huge, so the base list dominates |

In a real head, `pod` and `instance` have tens of thousands of values, including churned ones. A regex on them evaluates a Go regexp tens of thousands of times *before* touching a postings list.
- 3.14 sped up regex sets of literals (`{job=~"foo|bar|baz"}`).
- 3.13 sped up case-insensitive prefixes.
- 3.10 sped up `.*-.*-.*`.

The architectural fix is still: **select on low-cardinality labels first, and keep regexes off high-cardinality labels in dashboards and alerts.**

### 1.5 The cardinality product law

A metric family's series count is the number of distinct label combinations *actually observed*. That is bounded above by the product of each label's distinct values.

```text
 http_server_duration_seconds_bucket per pod:
     route(3) × code(3) × method(2) × le(12)                       =     216
   × pods(300)                                                     =  64,800
   + user_tier (5 values)                                          = 324,000
   + customer_id (10,000 seen per pod per day)                     = 648,000,000   ✗
```

Two multipliers are invisible in code review:
- **Histogram buckets.** Every classic bucket is a series (File 03): 12 buckets is ×12 per label combination.
- **Time.** Pod names, container IDs, build SHAs, `pod_template_hash` and per-request IDs make a label's *lifetime* distinct-value count far exceed its *instantaneous* count.

The head holds every series alive in the last 1–3 h. L4 §4 simulates a 60-pod service redeployed every 30 minutes [M]:
- Head series saw-tooth from 13k to **105k = 8× the active count**.
- GC releases them only when the head compacts (every 2 h, after the 3 h trigger).
- At ~2 KiB per series, the same fleet ×100 needs 2.5 GiB steady but **19.7 GiB at the churn peak**.

**Memory is sized by churn, not by "active series".**

### 1.6 Where cardinality turns into an OOM

```text
                     ┌──────────── head memory ∝ series alive in last 1–3 h (×1.75 GC)
 new label value ──► │ new memSeries + label string + postings slots + map entries
 (churn, explosion)  │ WAL Series record (replayed on restart; checkpointed per live series)
                     ├──────────── compaction ∝ series in the block × labels (index build)
                     ├──────────── queries ∝ series matched × samples per series
                     │             (--query.max-samples=50M guards samples, NOT series fan-out)
                     └──────────── remote write ∝ series (RW2 symbols per batch, shards)
 the OOM happens at the MAX of these, usually "head at 3h + compaction" or "head + one bad query"
```

Guards Prometheus gives you, in order of where they act [D]:
1. **Per scrape:** `sample_limit`, `label_limit`, `label_name_length_limit`, `label_value_length_limit`, `body_size_limit`, `native_histogram_bucket_limit`. Exceeding `sample_limit` **fails the whole scrape**: `up == 0`, and all of that scrape's samples are dropped.
2. **Per scrape config:** `target_limit` and `keep_dropped_targets`.
3. **Per query:** `--query.max-samples`, `--query.timeout`, `--query.max-concurrency`.
4. **Runtime:** `--auto-gomemlimit`, which converts a runaway into GC thrash before the OOMKill.
5. **Experimental:** `stale_series_compaction_threshold`, which evicts stale series early.

### 1.7 Measuring cardinality without making it worse

`/api/v1/status/tsdb?limit=N` (default 10, max 10,000 since 3.9) returns head statistics [D]:
- `seriesCountByMetricName`
- `labelValueCountByLabelName`
- `memoryInBytesByLabelName`
- `seriesCountByLabelValuePair`
- `headStats`

The results are computed from `MemPostings.Stats` and cached for a short time, so polling is cheap.

> **Doc vs code [D].** The API docs say `memoryInBytesByLabelName` is "the length of all values for a given label name". In v3.15.1 it is `Σ_values labels.SizeOfLabels(name, value, seriesCount)`, i.e. **(1 + len(name) + 1 + len(value)) × series count** for stringlabels. It counts every series' copy of the pair, which matches what the head actually holds (L4 §2 reproduces the code's formula).

Prefer these to PromQL such as `count by (__name__)({__name__=~".+"})`. That query *is itself* a cardinality bomb: it matches every series in the time range, including churned ones, and can OOM the server you are diagnosing. `promtool tsdb analyze` on a block copy gives the same picture for persisted data, including churn ("label pairs most involved in churning"). 3.13 added experimental search endpoints for metric and label names and values behind `--enable-feature=search-api`.

<!-- listing:postings_lab.py -->
```python
"""postings_lab.py - the head inverted index (MemPostings), PostingsForMatchers, cardinality
statistics and churn-driven head growth, ported from Prometheus v3.15.1.

Sources (tag v3.15.1):
  tsdb/index/postings.go  MemPostings m[name][value] -> sorted []SeriesRef; Intersect / Merge /
                          Without iterators built on Seek; Stats() (the /api/v1/status/tsdb data).
  tsdb/querier.go         PostingsForMatchers: labelMustBeSet, intersecting matchers first,
                          '.*' no-op, '.+' = all values, subtracting matchers via Without, and
                          the l="" rule (selects series WITHOUT the label, issue #3575).
  model/labels            SizeOfLabels = (2 + len(name) + len(value)) * series for stringlabels.
The matcher engine is checked against brute force on every selector. Python `re.fullmatch`
stands in for Go RE2 (the selectors used avoid syntax where the two differ).

Usage: python postings_lab.py [target.md]
"""
import bisect
import heapq
import pathlib
import random
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from wal_head_lab import head_series_bytes  # noqa: E402


class Cost:
    def __init__(self):
        self.values_tested = self.postings_read = self.seeks = 0


class MemPostings:
    def __init__(self):
        self.m, self.series, self.next_ref = {}, {}, 1

    def add(self, lbls):  # refs only grow, so appends keep every list sorted
        ref = self.next_ref
        self.next_ref += 1
        self.series[ref] = dict(lbls)
        for kv in list(lbls) + [("", "")]:
            self.m.setdefault(kv[0], {}).setdefault(kv[1], []).append(ref)
        return ref

    def delete(self, refs):  # head GC (MemPostings.Delete): one filtering pass per affected list
        gone, affected = set(refs), set()
        for ref in refs:
            affected.update(self.series.pop(ref).items())
        affected.add(("", ""))
        for n, v in affected:
            lst = [r for r in self.m[n][v] if r not in gone]
            if lst:
                self.m[n][v] = lst
            else:
                del self.m[n][v]
                if not self.m[n]:
                    del self.m[n]

    def postings(self, name, values, cost):
        lists = [self.m.get(name, {}).get(v, []) for v in values]
        cost.postings_read += sum(len(x) for x in lists)
        return merge(lists)

    def matching(self, name, pred, cost):
        vals = []
        for v in self.m.get(name, {}):
            cost.values_tested += 1
            if pred(v):
                vals.append(v)
        return self.postings(name, vals, cost)


def merge(lists):
    return list(heapq.merge(*lists)) if len(lists) > 1 else (list(lists[0]) if lists else [])


def intersect(lists, cost):
    if not lists:
        return []
    lists = sorted(lists, key=len)
    out, idx = [], [0] * len(lists)
    for ref in lists[0]:
        ok = True
        for j in range(1, len(lists)):
            idx[j] = bisect.bisect_left(lists[j], ref, idx[j])  # Seek(ref)
            cost.seeks += 1
            if idx[j] == len(lists[j]) or lists[j][idx[j]] != ref:
                ok = False
                break
        if ok:
            out.append(ref)
    return out


def without(full, drop):
    d = set(drop)
    return [r for r in full if r not in d]


class Matcher:
    def __init__(self, name, op, value):
        self.name, self.op, self.value = name, op, value
        self.rx = re.compile(value, re.S) if op in ("=~", "!~") else None

    def matches(self, s):
        if self.op == "=":
            return s == self.value
        if self.op == "!=":
            return s != self.value
        hit = self.rx.fullmatch(s) is not None  # Prometheus anchors regexes: ^(?s:...)$
        return hit if self.op == "=~" else not hit

    def inverse(self):
        return Matcher(self.name, {"=": "!=", "!=": "=", "=~": "!~", "!~": "=~"}[self.op], self.value)

    def set_matches(self):  # FastRegexMatcher: a pure alternation of literals
        if self.op in ("=~", "!~") and re.fullmatch(r"[\w:/.\-]+(\|[\w:/.\-]+)*", self.value) and \
                not re.search(r"[.]", self.value.replace(r"\.", "")):
            return self.value.split("|")
        return []

    def __repr__(self):
        return f'{self.name}{self.op}"{self.value}"'


def postings_for_matcher(ix, m, cost):
    if m.op == "=":
        return ix.postings(m.name, [m.value], cost)
    if m.op == "=~" and m.set_matches():
        return ix.postings(m.name, m.set_matches(), cost)
    return ix.matching(m.name, m.matches, cost)


def inverse_postings_for_matcher(ix, m, cost):
    if m.op == "!~" and m.set_matches():
        return ix.postings(m.name, m.set_matches(), cost)
    if m.op == "!=":
        return ix.postings(m.name, [m.value], cost)
    if m.value == "" and m.op in ("=~", "="):
        return ix.matching(m.name, lambda s: True, cost)
    return ix.matching(m.name, lambda s: not m.matches(s), cost)


def postings_for_matchers(ix, ms, cost):
    its, not_its = [], []
    must = {m.name for m in ms if not m.matches("")}

    def subtracting(m):
        return m.name not in must or (m.op in ("!=", "!~") and m.matches(""))

    if any(subtracting(m) for m in ms) and not any(not subtracting(m) for m in ms):
        its.append(ix.postings("", [""], cost))
    for m in sorted(ms, key=subtracting):  # stable: intersecting matchers first
        if m.op == "=~" and m.value == ".*":
            continue
        if m.op == "!~" and m.value == ".*":
            return []
        if m.op == "=~" and m.value == ".+":
            its.append(ix.matching(m.name, lambda s: True, cost))
        elif m.op == "!~" and m.value == ".+":
            not_its.append(ix.matching(m.name, lambda s: True, cost))
        elif m.name in must:
            is_not, empty = m.op in ("!=", "!~"), m.matches("")
            if is_not and empty:  # l!="foo"
                not_its.append(postings_for_matcher(ix, m.inverse(), cost))
            elif is_not:  # l!=""
                it = inverse_postings_for_matcher(ix, m.inverse(), cost)
                if not it:
                    return []
                its.append(it)
            else:
                it = postings_for_matcher(ix, m, cost)
                if not it:
                    return []
                its.append(it)
        else:  # l="" style: also selects series WITHOUT the label
            not_its.append(inverse_postings_for_matcher(ix, m, cost))
    out = intersect(its, cost)
    for n in not_its:
        out = without(out, n)
    return out


def brute(ix, ms):
    return [r for r, l in ix.series.items() if all(m.matches(l.get(m.name, "")) for m in ms)]


def parse(sel):
    return [Matcher(n, op, v) for n, op, v in re.findall(r'([\w]+)\s*(=~|!~|!=|=)\s*"([^"]*)"', sel)]


def build_fleet(rng, ix, pods=300, deploy=0):
    """Each pod: cAdvisor container series + a 12-bucket latency histogram per route/code/method."""
    refs = []
    for p in range(pods):
        ns = ("checkout", "cart", "search", "payments")[p % 4]
        pod = f"{ns}-{deploy:03d}{rng.getrandbits(24):06x}-{rng.getrandbits(16):04x}"
        base = [("namespace", ns), ("pod", pod), ("instance", f"10.2.{p // 200}.{p % 200}:8080"),
                ("job", "app")] + ([("env", "prod")] if p % 3 else [])
        for m in ("container_cpu_usage_seconds_total", "container_memory_working_set_bytes"):
            refs.append(ix.add(base + [("__name__", m)]))
        for route in ("/cart", "/item", "/pay"):
            for code in ("200", "404", "500"):
                for method in ("GET", "POST"):
                    for le in ("0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1", "2.5", "5", "10", "+Inf"):
                        refs.append(ix.add(base + [("__name__", "http_server_duration_seconds_bucket"),
                                                   ("route", route), ("code", code), ("method", method), ("le", le)]))
    return refs


def main():
    checks = []
    rng = random.Random(5)
    ix = MemPostings()
    build_fleet(rng, ix)
    print(f"== 1. Head index: {len(ix.series):,} series, {sum(len(v) for v in ix.m.values()) - 1:,} label pairs ==")
    sels = [
        '{__name__="http_server_duration_seconds_bucket", route="/cart", le="0.1"}',
        '{__name__="http_server_duration_seconds_bucket", code=~"5.."}',
        '{__name__="http_server_duration_seconds_bucket", code!="200"}',
        '{__name__="container_memory_working_set_bytes", pod=~"checkout-.*"}',
        '{pod=~"checkout-.*"}',
        '{__name__=~"container_.*", namespace=~"cart|search"}',
        '{__name__="container_cpu_usage_seconds_total", env=""}',
        '{__name__="container_cpu_usage_seconds_total", env!=""}',
        '{__name__="container_cpu_usage_seconds_total", env=~""}',
        '{__name__="container_cpu_usage_seconds_total", env!~"prod"}',
        '{__name__="container_cpu_usage_seconds_total", env=~"prod|"}',
        '{__name__="container_cpu_usage_seconds_total", route=~".+"}',
        '{__name__="container_cpu_usage_seconds_total", route!~".+"}',
        '{namespace="payments", nonexistent="x"}',
        '{namespace="payments", nonexistent!="x"}',
        '{namespace="payments", le=~".*"}',
        '{namespace="payments", le!~".*"}',
        '{job="app", method!~"GET|POST"}',
        '{job="app", le=~"0\\.0.*", code="500", method="POST"}',
        '{instance=~"10\\.2\\.0\\.1.*", __name__!="container_cpu_usage_seconds_total"}',
    ]
    print(f"{'selector':<92} {'series':>6} {'vals tested':>11} {'postings read':>13}")
    for sel in sels:
        ms, c = parse(sel), Cost()
        got = postings_for_matchers(ix, ms, c)
        want = sorted(brute(ix, ms))
        checks.append((sel, got == want))
        print(f"{sel:<92} {len(got):>6} {c.values_tested:>11,} {c.postings_read:>13,}{'' if got == want else '  MISMATCH'}")
    print()

    print("== 2. /api/v1/status/tsdb-style cardinality report (MemPostings.Stats) ==")
    by_metric = sorted(((len(v), k) for k, v in ix.m["__name__"].items()), reverse=True)
    by_label = sorted(((len(v), k) for k, v in ix.m.items() if k), reverse=True)
    mem = sorted(((sum((2 + len(k) + len(val)) * len(refs) for val, refs in v.items()), k)
                  for k, v in ix.m.items() if k), reverse=True)
    pairs = sorted(((len(r), f"{k}={val}") for k, v in ix.m.items() if k for val, r in v.items()), reverse=True)
    print("seriesCountByMetricName   : " + ", ".join(f"{k} {n:,}" for n, k in by_metric[:3]))
    print("labelValueCountByLabelName: " + ", ".join(f"{k} {n:,}" for n, k in by_label[:4]))
    print("memoryInBytesByLabelName  : " + ", ".join(f"{k} {n / 1024:,.0f} KiB" for n, k in mem[:4]))
    print("seriesCountByLabelValuePair: " + ", ".join(f"{k} {n:,}" for n, k in pairs[:3]))
    checks.append(("pod is the top value-count label", by_label[0][1] == "pod"))
    print()

    print("== 3. Cardinality is a product: one histogram family per pod ==")
    per_pod = 3 * 3 * 2 * 12
    print(f"route(3) x code(3) x method(2) x le(12) = {per_pod} series/pod; x300 pods = {per_pod * 300:,}")
    for extra, k in (("+ user_tier label (5 values)", 5), ("+ customer_id label (10k values seen per pod-day)", 10_000)):
        print(f"{extra:<52} -> {per_pod * 300 * k:>14,} series")
    print()

    print("== 4. Churn: rolling deploy replaces every pod; head GC only at head compaction (every 2h) ==")
    rng2 = random.Random(9)
    head = MemPostings()
    live = build_fleet(rng2, head, pods=60, deploy=0)
    active = len(live)
    timeline, dead, deploy, head_min = [], [], 0, 0
    last_sample = {r: 0 for r in live}
    for minute in range(0, 6 * 60 + 1, 5):
        if minute and minute % 30 == 0:  # deploy every 30 min: new pod names -> new series
            deploy += 1
            for r in live:
                last_sample[r] = minute
            dead += live
            live = build_fleet(rng2, head, pods=60, deploy=deploy)
        if minute - head_min > 180:  # compactable(): head spans > 1.5 x 2h
            head_min = (head_min // 120 + 1) * 120  # block [old minT, boundary) persisted
            gone = [r for r in dead if last_sample[r] < head_min]  # gc(): no samples left in head
            head.delete(gone)
            gone_set = set(gone)
            dead = [r for r in dead if r not in gone_set]
        timeline.append((minute, len(head.series)))
    peak = max(n for _, n in timeline)
    print("minute:head series  " + " ".join(f"{m}:{n / 1000:.0f}k" for m, n in timeline[::6]))
    print(f"active series {active:,}; peak head series {peak:,} = {peak / active:.1f}x active")
    checks.append(("churn inflates head", peak / active > 3))
    per = head_series_bytes(10, 9, 14, 15, 2.1, 2)
    b = sum(per.values()) * 1.75
    print(f"at ~{b:,.0f} B/series (wal_head_lab model) the same fleet x100 needs "
          f"{active * 100 * b / 2**30:.1f} GiB steady but {peak * 100 * b / 2**30:.1f} GiB at the churn peak")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed[:5]}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:postings_lab.py -->
```text
== 1. Head index: 65,400 series, 629 label pairs ==
selector                                                                                     series vals tested postings read
{__name__="http_server_duration_seconds_bucket", route="/cart", le="0.1"}                      1800           0        91,800
{__name__="http_server_duration_seconds_bucket", code=~"5.."}                                 21600           3        86,400
{__name__="http_server_duration_seconds_bucket", code!="200"}                                 43200           0        86,400
{__name__="container_memory_working_set_bytes", pod=~"checkout-.*"}                              75         300        16,650
{pod=~"checkout-.*"}                                                                          16350         300        16,350
{__name__=~"container_.*", namespace=~"cart|search"}                                            300           3        33,300
{__name__="container_cpu_usage_seconds_total", env=""}                                          100           1        43,900
{__name__="container_cpu_usage_seconds_total", env!=""}                                         200           1        43,900
{__name__="container_cpu_usage_seconds_total", env=~""}                                         100           1        43,900
{__name__="container_cpu_usage_seconds_total", env!~"prod"}                                     100           0        43,900
{__name__="container_cpu_usage_seconds_total", env=~"prod|"}                                    300           1           300
{__name__="container_cpu_usage_seconds_total", route=~".+"}                                       0           3        65,100
{__name__="container_cpu_usage_seconds_total", route!~".+"}                                     300           3        65,100
{namespace="payments", nonexistent="x"}                                                           0           0        16,350
{namespace="payments", nonexistent!="x"}                                                      16350           0        16,350
{namespace="payments", le=~".*"}                                                              16350           0        16,350
{namespace="payments", le!~".*"}                                                                  0           0        16,350
{job="app", method!~"GET|POST"}                                                                 600           0       130,200
{job="app", le=~"0\.0.*", code="500", method="POST"}                                           3600          12       141,000
{instance=~"10\.2\.0\.1.*", __name__!="container_cpu_usage_seconds_total"}                    24087         300        24,498

== 2. /api/v1/status/tsdb-style cardinality report (MemPostings.Stats) ==
seriesCountByMetricName   : http_server_duration_seconds_bucket 64,800, container_memory_working_set_bytes 300, container_cpu_usage_seconds_total 300
labelValueCountByLabelName: pod 300, instance 300, le 12, namespace 4
memoryInBytesByLabelName  : __name__ 2,873 KiB, pod 1,692 KiB, instance 1,550 KiB, namespace 1,118 KiB
seriesCountByLabelValuePair: job=app 65,400, __name__=http_server_duration_seconds_bucket 64,800, env=prod 43,600

== 3. Cardinality is a product: one histogram family per pod ==
route(3) x code(3) x method(2) x le(12) = 216 series/pod; x300 pods = 64,800
+ user_tier label (5 values)                         ->        324,000 series
+ customer_id label (10k values seen per pod-day)    ->    648,000,000 series

== 4. Churn: rolling deploy replaces every pod; head GC only at head compaction (every 2h) ==
minute:head series  0:13k 30:26k 60:39k 90:52k 120:65k 150:78k 180:92k 210:65k 240:78k 270:92k 300:105k 330:65k 360:78k
active series 13,080; peak head series 104,640 = 8.0x active
at ~2,024 B/series (wal_head_lab model) the same fleet x100 needs 2.5 GiB steady but 19.7 GiB at the churn peak

checks: 22/22 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Scrape-side cardinality guardrails

```yaml
global:
  scrape_interval: 15s
  # Fleet-wide ceilings; per-job values override. A breach FAILS the scrape (up == 0).
  sample_limit: 50000
  label_limit: 40
  label_name_length_limit: 128
  label_value_length_limit: 512
  body_size_limit: 50MB
  extra_scrape_metrics: true          # adds scrape_sample_limit, scrape_timeout_seconds, scrape_body_size_bytes
scrape_configs:
  - job_name: kubernetes-pods
    target_limit: 5000                # per scrape config: protects against SD explosions
    keep_dropped_targets: 100         # bound memory used to show dropped targets in the UI
    sample_limit: 20000
    native_histogram_bucket_limit: 160
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        regex: "true"
        action: keep
      - action: labeldrop               # never let these become TARGET labels (one value per rollout)
        regex: pod_template_hash|controller_revision_hash|statefulset_kubernetes_io_pod_name
    metric_relabel_configs:
      # 1. strip unbounded identifiers (safe only if no two series differ solely by them; see note)
      - action: labeldrop
        regex: user_id|session_id|request_id|trace_id|customer_id
      # 2. drop whole families nobody queries (validated with Grafana/rule usage, Folder 08)
      - source_labels: [__name__]
        regex: go_gc_duration_seconds.*|go_memstats_(alloc|frees|lookups|mallocs).*_total
        action: drop
      # 3. normalise unbounded path labels into route templates
      - source_labels: [path]
        regex: /api/v1/orders/[0-9a-f-]+
        target_label: path
        replacement: /api/v1/orders/:id
```

> **Note.** `labeldrop` in `metric_relabel_configs` can **merge** series. If two series differ only by `user_id`, dropping it makes them collide with identical label sets in one scrape, and Prometheus rejects the duplicates (`prometheus_target_scrapes_sample_duplicate_timestamp_total`). Drop high-cardinality labels **at the instrumentation**, or aggregate via recording rules, when the values must be summed.

### 2.2 Cardinality recording rules and alerts

```yaml
groups:
  - name: cardinality.rules
    interval: 1m
    rules:
      - record: job:scrape_series_added:sum_increase1h
        expr: sum by (job) (increase(scrape_series_added[1h]))
      - record: job:scrape_samples_post_metric_relabeling:sum
        expr: sum by (job) (scrape_samples_post_metric_relabeling)
      - record: job:scrape_sample_limit_utilization:max
        expr: |
          max by (job) (
            scrape_samples_post_metric_relabeling / (scrape_sample_limit > 0)
          )
  - name: cardinality.alerts
    rules:
      - alert: ScrapeSampleLimitNear
        expr: job:scrape_sample_limit_utilization:max > 0.8
        for: 30m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.job }} is at {{ $value | humanizePercentage }} of sample_limit; the next increase fails the whole scrape"
      - alert: SeriesChurnSpike
        expr: |
          job:scrape_series_added:sum_increase1h
            > 3 * (job:scrape_samples_post_metric_relabeling:sum)
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.job }} created >3x its live series in the last hour (unbounded label or redeploy storm)"
      - alert: HeadSeriesGrowthAnomaly
        expr: |
          prometheus_tsdb_head_series
            > 1.5 * avg_over_time(prometheus_tsdb_head_series[1d] offset 1d)
        for: 30m
        labels: {severity: critical}
        annotations:
          summary: "Head series 50% above yesterday's average; check /api/v1/status/tsdb before the next compaction"
```

`scrape_series_added` counts series **newly created** by each scrape (relative to the scrape's series cache). It is the earliest, cheapest churn signal and it is free; no feature flag is needed.

### 2.3 A cardinality diff bot (stdlib Python, runs as a CronJob)

```python
"""cardinality_diff.py - compare today's /api/v1/status/tsdb with yesterday's snapshot."""
import json
import pathlib
import sys
import urllib.request

PROM = sys.argv[1]                      # e.g. http://prometheus.monitoring:9090
STATE = pathlib.Path(sys.argv[2])       # e.g. /state/tsdb-status.json


def fetch():
    with urllib.request.urlopen(f"{PROM}/api/v1/status/tsdb?limit=200", timeout=30) as r:
        data = json.load(r)["data"]
    return {
        "series": data["headStats"]["numSeries"],
        "by_metric": {x["name"]: x["value"] for x in data["seriesCountByMetricName"]},
        "by_label": {x["name"]: x["value"] for x in data["labelValueCountByLabelName"]},
    }


now = fetch()
old = json.loads(STATE.read_text()) if STATE.exists() else now
grew = sorted(((now["by_metric"].get(k, 0) - v, k) for k, v in old["by_metric"].items()), reverse=True)
new_metrics = sorted(set(now["by_metric"]) - set(old["by_metric"]), key=lambda k: -now["by_metric"][k])
print(f"head series {old['series']:,} -> {now['series']:,} ({now['series'] / max(old['series'], 1) - 1:+.1%})")
for delta, name in grew[:10]:
    if delta > 0:
        print(f"  +{delta:,} {name}")
for name in new_metrics[:10]:
    print(f"  NEW {name} {now['by_metric'][name]:,}")
for name, n in sorted(now["by_label"].items(), key=lambda kv: -kv[1])[:10]:
    print(f"  label {name}: {n:,} values (was {old['by_label'].get(name, 0):,})")
STATE.write_text(json.dumps(now))
```

### 2.4 Query-side guardrails (PromQL patterns)

```promql
# Cheap: equality on low-cardinality labels first, regex last and on low-cardinality labels
sum by (code) (rate(http_server_requests_seconds_count{job="checkout", namespace="shop", code=~"5.."}[5m]))

# Expensive: regex on a high-cardinality label scans every value of 'pod' (incl. churned ones)
sum(rate(container_cpu_usage_seconds_total{pod=~".*checkout.*"}[5m]))

# Better: select by a stable, low-cardinality label you control at relabel time
sum(rate(container_cpu_usage_seconds_total{namespace="shop", container="checkout"}[5m]))

# Cardinality by job WITHOUT touching samples: use the per-scrape counter
topk(10, sum by (job) (scrape_samples_post_metric_relabeling))
```

---

## 3. Failure modes and FinOps debugging

### F1. A new label value per request: OOMKill within an hour

**Symptom.** A deploy adds `customer_id` (or `trace_id`, or a raw URL path) as a metric label. Within 30–90 minutes Prometheus is OOMKilled. After restart it OOMs during WAL replay.

**Signature.**
- `scrape_series_added` for that job jumps from ~0 to thousands per scrape.
- `prometheus_tsdb_head_series` rises linearly.
- `/api/v1/status/tsdb` shows the label at the top of `labelValueCountByLabelName`.
- Replay dies because the WAL contains a Series record for every new series.

**Root cause.** Each distinct value creates a new series: memSeries, label string, a postings slot per label pair, two map entries, and an open chunk buffer of ≥128 B, about 2 KiB in total. The series stays until head GC, up to 3 h later. 10k new values × 216 histogram series per value is 2 M series, ~4 GiB, per scrape cycle of new values.

**Fix.**
1. Add a `metric_relabel_configs` `labeldrop` for the label (or `drop` for the family) on that job.
2. Restart. If replay still OOMs, temporarily raise the memory limit; as a last resort, move the WAL aside and accept losing up to 3 h of head data.
3. Revert the instrumentation change.

**Prevention.**
- Set `sample_limit` per job, so a breach fails that job's scrape instead of the server.
- Alert on `scrape_series_added` churn.
- Lint new instrumentation with a check that rejects label names on an unbounded list (`*_id`, `path`, `url`, `email`).
- Put trace IDs in **exemplars**, never labels (Folder 05).

### F2. The cardinality dashboard that killed Prometheus

**Symptom.** Someone opens a "Top metrics by series" panel and Prometheus OOMs or times out. The incident is attributed to "load".

**Signature.** The query log (`global.query_log_file`) shows `count by (__name__) ({__name__=~".+"})` or `count({__name__!=""})` over a range. `prometheus_engine_query_samples_total` spikes, and the active-query log (`queries.active`) lists it at crash time.

**Root cause.** `{__name__=~".+"}` intersects nothing. It unions every value of `__name__`, i.e. every series in the queried time range, including churned series in persisted blocks, then loads their samples. The cost is O(all series × samples in range).

**Fix.** Kill the panel. Use `/api/v1/status/tsdb`, `promtool tsdb analyze`, or the recording rule `topk(10, sum by (job) (scrape_samples_post_metric_relabeling))`.

**Prevention.**
- Lower `--query.max-samples` for the Grafana-facing server, or front it with a query frontend that enforces limits (Folder 06).
- Review dashboards for unbounded selectors.

### F3. Slow dashboards from regexes on high-cardinality labels

**Symptom.** A dashboard with `{pod=~"$pod"}` and `$pod = .*` takes 10–30 s. Variable dropdowns time out.

**Signature.** Query stats (`stats=all`) show modest `samplesRead` but high wall time. CPU profiles (`/debug/pprof`) show `regexp` and `PostingsForLabelMatching`. `labelValueCountByLabelName` for `pod` is in the hundreds of thousands, because churned pods are still in blocks within the range.

**Root cause.** `=~` on a label that is not a literal set runs the regex against **every value** of that label (L4: 300 regex tests for 300 pods; production has 10⁵+). A `.*`-anchored pattern defeats the prefix optimizations.

**Fix.**
- Put a low-cardinality equality first (`namespace`, `job`, `container`).
- Use Grafana's "All" value as a custom literal set or `.+` (which hits the `.+` fast path) rather than `.*`-wrapped patterns.
- Turn variables into `label_values(kube_pod_info{namespace="$ns"}, pod)` so they are scoped.

**Prevention.** Lint dashboards for regex matchers on `pod`, `instance`, `container_id` or `id`. Prefer stable service-level labels added at relabel time.

### F4. Rolling deploys every 30 minutes: memory 8× the active series

**Symptom.** Steady-state head series is ~1.2 M, but the server needs 30+ GiB and OOMs during busy release days.

**Signature.**
- `max_over_time(prometheus_tsdb_head_series[1d])` / `min_over_time(...)` ≈ 5–8.
- `prometheus:tsdb_head_series:churn_ratio_1h` > 1.
- Sharp drops in head series exactly at compaction times.

**Root cause.** Every rollout renames every pod, so every series is new. Old series linger until head GC after the 3 h trigger. L4 §4 reproduces 8× head inflation with a 30-minute cadence.

**Fix.**
- Short term: size memory for the peak.
- Medium term: drop pod-scoped labels from metrics that are aggregated anyway (`sum without(pod, instance)` recording rules, then drop the raw series), so a rollout does not create new series.
- Enable `stale_series_compaction_threshold` (experimental) to evict stale series between compactions.

**Prevention.** Record the "churn multiple" per job and make it part of the deploy-frequency conversation. A team deploying 50×/day pays a different observability price than one deploying daily, and the chargeback model should show it.

### F5. `env=""` silently matches everything without the label

**Symptom.** An alert meant to catch series where `env` is empty fires for thousands of series that simply do not have `env`. Or a dashboard filter `env=~"$env"` with an empty variable shows everything.

**Signature.** The result count equals "series with `env=""` plus series without `env`". L4 shows that `env=""`, `env=~""` and `env!~"prod"` all return the 100 series lacking the label.

**Root cause.** In PromQL a missing label **is** the empty string. `PostingsForMatchers` implements this deliberately (issue #3575): a matcher that matches `""` subtracts series that *have* the label with a non-matching value, which leaves the ones without it.

**Fix.**
- To require the label to be present and empty is impossible: Prometheus never stores empty label values (`labels.Builder` deletes them).
- To require presence, use `env!=""`.
- To select series lacking it, `env=""` is correct, but say so in the alert description.

**Prevention.** Default dashboard variables to `.+` rather than empty. Unit-test alert expressions with `promtool test rules` fixtures that include label-less series.

### F6. Classic histogram bucket explosion on a multi-tenant API

**Symptom.** One histogram family is 40% of all series.

**Signature.** `seriesCountByMetricName` is topped by `*_bucket`; `count by (le) (...)` shows 20–30 buckets. Labels include `route`, `method`, `code` and `tenant`.

**Root cause.** A classic histogram is (buckets + 2) series per label combination. Fine-grained buckets times tenant cardinality multiply (§1.5).

**Fix.**
1. Migrate to **native histograms**: one series per combination, with exponential resolution (File 03).
2. Or convert at scrape time with `convert_classic_histograms_to_nhcb: true`, keeping the bucket layout as one NHCB series.
3. Drop `tenant` from latency histograms and keep it on counters.

**Prevention.** Budget series per family at design review with the product law (§1.5), and require justification for each label on a histogram.

### F7. `sample_limit` turns a cardinality problem into an outage

**Symptom.** A team's dashboard goes completely blank, and `TargetDown` fires for a healthy service.

**Signature.** `up == 0` while `scrape_samples_scraped` is large, and `prometheus_target_scrapes_exceeded_sample_limit_total` increments. The target page shows "sample limit exceeded".

**Root cause.** `sample_limit` is enforced after metric relabeling, and a breach **fails the entire scrape**. All samples from that target are dropped, including `up`-adjacent health metrics. This protects the server, but users see it as an outage.

**Fix.** Raise the job's limit temporarily, and drop the exploding family in `metric_relabel_configs` so the rest of the scrape survives.

**Prevention.**
- Alert at 80% of the limit (`ScrapeSampleLimitNear`, which needs `extra_scrape_metrics: true` for `scrape_sample_limit`).
- Give teams a dashboard of their headroom.
- Make the alert text say "limit exceeded", not "target down".

### F8. UTF-8 names create parallel series families

**Symptom.** After enabling OTLP ingestion, or upgrading a relabel config, dashboards show duplicates such as `k8s.pod.name` and `k8s_pod_name`, or `http.server.request.duration` beside `http_server_request_duration_seconds`.

**Signature.**
- `labelValueCountByLabelName` lists dotted and underscored twins.
- `prometheus_api_otlp_translation_warnings_total` (3.14+) increments for attribute collisions.
- `__name__` values contain dots.

**Root cause.** 3.x validates names as UTF-8 by default (`metric_name_validation_scheme: utf8`), so dots and slashes are legal. OTLP `translation_strategy` (`NoUTF8EscapingWithSuffixes` / `NoTranslation`) or a relabel `target_label` derived from a capture (L6 in File 04) creates names that older pipelines would have escaped.

**Fix.** Pick one convention per pipeline: keep `UnderscoreEscapingWithSuffixes` until every consumer supports UTF-8. Normalise with `metric_relabel_configs` and backfill recording rules for dashboards.

**Prevention.** Treat `translation_strategy` and the name validation scheme as a schema decision with an owner, not a per-collector default.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "How does Prometheus find the series for a selector?"</b></summary>

**Initial Prompt.** Explain what happens for `rate(http_requests_total{job="api", code=~"5.."}[5m])` before any sample is read.

**L5 Textbook Answer.** There is an inverted index from label pairs to series IDs. Prometheus looks up each matcher and intersects the lists.

**Why L5 Fails at 3 AM or on the Bill.** It cannot explain why `code=~"5.."` is cheap and `pod=~".*x.*"` is slow, why `env=""` returns extra series, or why a query OOMs while its sample count looks fine. The algebra is right, but the cost model is missing.

**L7 Principal Defense.**
1. Per block and for the head, `PostingsForMatchers` classifies matchers. Equality and set-regexes become direct postings lookups. A general regex is evaluated against **every value** of its label and the matching lists are unioned. Negations and empty-matching matchers are subtracted at the end with `Without`.
2. Intersection is a Seek-driven merge over sorted lists, so cost ~ Σ lengths of the lists touched.
3. The IDs are then resolved to series and chunks, filtered by time, and decoded.
4. So I put a selective equality first (`job`), keep regexes on low-cardinality labels, and watch two numbers: label values tested, which is driven by churn, and postings read, which is driven by series per pair.
</details>

<details><summary><b>Q2 · "Does Prometheus use Roaring bitmaps?"</b></summary>

**Initial Prompt.** I read that Prometheus's index uses Roaring bitmaps for postings. Explain how that helps.

**L5 Textbook Answer.** Yes. Roaring bitmaps compress the series-ID sets and make intersections fast with bitwise AND.

**Why L5 Fails at 3 AM or on the Bill.** It is factually wrong. Defending a design on the wrong premise leads to wrong capacity math: postings are 4 B per entry on disk and 8 B per entry in the head, uncompressed.

**L7 Principal Defense.**
1. Upstream Prometheus writes raw postings: a 4-byte big-endian count and 4-byte big-endian IDs, CRC'd (`EncodePostingsRaw`). The head uses sorted `[]SeriesRef`.
2. The encoder is pluggable (`PostingsEncoder`), so forks can experiment.
3. Raw works because block series IDs are assigned in label order (offset/16). Lists are dense, sorted and merge-joinable with binary-search Seek, and the dominant cost is how many entries you touch, not the decode.
4. Bitmaps win when sets are dense and wide, as with Druid/Pinot dimension filters and Lucene filter caches. Remote stores (Thanos, Mimir) compress postings in caches where network and memory matter.
5. For capacity I budget 4 B × label pairs × series per block on disk, and 8 B (+ slack) × label pairs per head series in RAM.
</details>

<details><summary><b>Q3 · "Our Prometheus OOMs every afternoon. Diagnose it."</b></summary>

**Initial Prompt.** It runs fine at night and dies around 3 PM. Memory limit 32 GiB, about 2 M active series.

**L5 Textbook Answer.** 2 M series should fit in 32 GiB. Probably a heavy query in the afternoon; increase memory or limit queries.

**Why L5 Fails at 3 AM or on the Bill.** It assumes "active series" is the head size, so it misses churn, which correlates with afternoon deploys. Doubling memory on a churn problem doubles the bill and moves the OOM to release day.

**L7 Principal Defense.** I triage in order:
1. Plot `prometheus_tsdb_head_series` against deploy events. A saw-tooth peaking at 3–8× active means churn, and GC only runs at head compaction.
2. Read `/api/v1/status/tsdb` for the label with exploding values, and `scrape_series_added` for the job creating series.
3. Check whether the OOM coincides with `prometheus_tsdb_compaction_duration_seconds`, because compaction adds index-build memory to a peak head.
4. Check the query log for unbounded selectors.

The fixes in order of leverage:
- drop pod-scoped labels from pre-aggregated metrics;
- `sample_limit` per job;
- more shards;
- `stale_series_compaction_threshold`;
- size memory for the measured peak, not the average.
</details>

<details><summary><b>Q4 · "Why does `env=\"\"` return series that do not have an env label?"</b></summary>

**Initial Prompt.** Our alert `up{env=""} == 0` fires for targets that have no `env` label. Bug?

**L5 Textbook Answer.** It is probably a Prometheus bug, or the targets have an empty `env` label. Add `env!=""` to be safe.

**Why L5 Fails at 3 AM or on the Bill.** Prometheus cannot store empty label values, so "has an empty env" is impossible. "Add `env!=""`" inverts the alert's meaning. The behavior is by design: a missing label equals `""` in every matcher.

**L7 Principal Defense.**
1. A matcher that matches `""` is a subtracting matcher. `PostingsForMatchers` removes the series that have `env` with a non-matching value, so series without `env` remain (issue #3575).
2. `env=""` therefore means "no env label". `env!=""` means "has env". `env=~"prod|"` means "prod or no env".
3. I make that explicit in alert descriptions, and test it with `promtool test rules` fixtures that include unlabeled series.
4. Where "no env" is itself a hygiene bug, I add the label at relabel time so every target has one.
</details>

<details><summary><b>Q5 · "Estimate the index size and memory for 50 M series."</b></summary>

**Initial Prompt.** We are designing for 50 M active series at 15 s with 14 labels each. What does the index cost?

**L5 Textbook Answer.** The index is small compared with the samples, maybe a few GB. Memory is about 3 KB per series, so 150 GB.

**Why L5 Fails at 3 AM or on the Bill.** It ignores that every 2 h block re-indexes every series alive in its window, so churn multiplies index bytes. It treats 50 M as one server, and it gives no structure to the memory number.

**L7 Principal Defense.**
1. Index per 2 h block ≈ series × (~40 + 4·14 + 3·chunks) + unique label text, about 100–120 B/series per L3. That is ~5–6 GB per 2 h block, before 6 h/18 h compaction merges the series sections. With 2× churn per window it doubles.
2. Head memory ≈ 2–4 KiB × churn-peak series. At 50 M with a 2× peak that is 200–400 GiB, which **is not a single Prometheus**.
3. The design is shards plus a horizontally scalable backend: Mimir ingesters with replication factor 3 and series sharded on a ring (Folder 06). Then I re-run the math per ingester with replication factor and the ingester's own head and local-retention windows instead of Prometheus's 3 h.
</details>

<details><summary><b>Q6 · "Is `sample_limit` a safety feature or an outage generator?"</b></summary>

**Initial Prompt.** Should we set `sample_limit` on every job?

**L5 Textbook Answer.** Yes. It protects Prometheus from cardinality explosions.

**Why L5 Fails at 3 AM or on the Bill.** A breach fails the **whole scrape**: `up == 0` and all the target's data, including healthy metrics, is dropped. Teams experience a total observability outage that looks like their service is down, and alert routing pages the wrong team.

**L7 Principal Defense.**
1. Yes, set it, but with three companions.
2. Per-job limits derived from measured `scrape_samples_post_metric_relabeling` plus ~2× headroom.
3. `extra_scrape_metrics: true` and an 80% warning alert routed to the owning team, so the breach is anticipated.
4. A runbook that drops the offending *family* in `metric_relabel_configs` rather than raising the limit blindly.
5. I also distinguish "target down" from "limit exceeded" in alert text, using `prometheus_target_scrapes_exceeded_sample_limit_total`.
</details>

<details><summary><b>Q7 · "Why not just add `pod` to every metric? It's useful for debugging."</b></summary>

**Initial Prompt.** Developers want `pod` on every application metric so they can find the bad replica.

**L5 Textbook Answer.** Kubernetes service discovery adds `pod` anyway, so it is already there. It is fine.

**Why L5 Fails at 3 AM or on the Bill.**
- `pod` is the label with the highest churn: a new value every rollout, autoscale event or eviction.
- On aggregated SLO metrics it multiplies series by replica count and multiplies head memory by deploy frequency (L4: 8×).
- Long-range queries have to touch every historical pod.
- "Already there" is the problem, not the justification.

**L7 Principal Defense.**
1. Keep `pod` on the *raw* scrape for short-retention debugging. Build recording rules that `sum without (pod, instance)` for dashboards, SLOs and long-term storage.
2. Drop the raw high-churn series from remote write with `write_relabel_configs`.
3. For "which replica is bad", use exemplars linking to traces, or logs, which are cheap per event, not per series.
4. Make the trade explicit: debugging granularity for minutes to hours locally; aggregated, low-cardinality data for weeks remotely.
</details>

<details><summary><b>Q8 · "How do you find the label that is killing us, without killing Prometheus?"</b></summary>

**Initial Prompt.** Head series doubled overnight. Show me how you find the cause safely.

**L5 Textbook Answer.** Run `topk(10, count by (__name__)({__name__=~".+"}))` to find the biggest metrics, then drill down by label.

**Why L5 Fails at 3 AM or on the Bill.** That query touches every series in the range and may be the thing that finishes the server off. It also finds the *biggest* metric, not the one that *changed*.

**L7 Principal Defense.**
1. `/api/v1/status/tsdb?limit=50`: cached and computed from the head index. Compare `seriesCountByMetricName`, `labelValueCountByLabelName` and `seriesCountByLabelValuePair` with yesterday's snapshot (the diff bot in §2.3).
2. `sum by (job) (increase(scrape_series_added[1h]))` to find the job creating series. It is a tiny per-target series.
3. `promtool tsdb analyze` on a snapshot copy for persisted blocks and churn.
4. Only then a scoped PromQL query on that job.
5. The fix lands as a `metric_relabel_configs` drop with a ticket to fix the instrumentation.
</details>

---

## 5. Invariants checklist

- [ ] Memory is sized from `max_over_time(prometheus_tsdb_head_series[7d])` (the churn peak), not from active series.
- [ ] Every scrape job has `sample_limit` with ~2× headroom, `extra_scrape_metrics: true`, and an 80% warning alert routed to the owner.
- [ ] `metric_relabel_configs` drop unbounded labels (`*_id`, raw paths, emails, trace IDs). Trace IDs travel as exemplars.
- [ ] Dashboards and alerts never use `{__name__=~".+"}`-style selectors, or `.*`-wrapped regexes on `pod`, `instance` or `container_id`.
- [ ] Cardinality is inspected with `/api/v1/status/tsdb` and `promtool tsdb analyze`, never with whole-TSDB PromQL counts.
- [ ] Empty-matcher semantics (`l=""` matches series without `l`) are documented in alert descriptions and covered by rule unit tests.
- [ ] High-churn raw series are aggregated by recording rules and excluded from remote write.
- [ ] Classic histograms with more than ~10 buckets or high-cardinality labels are migrated to native histograms or NHCB (File 03).
- [ ] Capacity math uses about 4 B × label pairs per series per block on disk and about 8 B × label pairs per head series in RAM for postings. Postings are raw, not bitmaps.

---

## 6. References

- Index format v2 (with the V1 notes): <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/docs/format/index.md>
- Index writer/reader (`EncodePostingsRaw`, `PostingsEncoder`, `symbolFactor`): <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/index/index.go>
- `MemPostings`, `Intersect`, `Merge`, `Without`, `Stats`: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/index/postings.go>
- `PostingsForMatchers`: <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/querier.go>
- Fixture origin and oracle: <https://github.com/prometheus/prometheus/tree/v3.15.1/tsdb/testdata/index_format_v1> and <https://github.com/prometheus/prometheus/blob/v3.15.1/tsdb/block_test.go>
- Empty-label matcher semantics, issue #3575: <https://github.com/prometheus/prometheus/issues/3575>
- TSDB status API: <https://prometheus.io/docs/prometheus/latest/querying/api/#tsdb-stats>
- Scrape limits in `<scrape_config>`: <https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config>
- promtool `tsdb analyze`: <https://prometheus.io/docs/prometheus/latest/command-line/promtool/>
- Roaring bitmaps (for contrast): <https://roaringbitmap.org/>
