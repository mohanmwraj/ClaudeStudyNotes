# Fixture provenance

`index_format_v1/` is copied byte-for-byte from the Prometheus repository at tag `v3.15.1`, path `tsdb/testdata/index_format_v1/`:
<https://github.com/prometheus/prometheus/tree/v3.15.1/tsdb/testdata/index_format_v1>

- License: Apache License 2.0, Copyright The Prometheus Authors.
- Written by Prometheus 2.0.0 (commit 706602daed1487f7849990678b4ece4599745905), according to the comment in `tsdb/block_test.go` `TestReadIndexFormatV1`.
- Expected contents, asserted by that test:
  - `{foo="bar"}` → (t=1, v=2);
  - `{foo="baz"}` → (t=3, v=4);
  - 100 series `{bar="0".."99"}` → (0, 0);
  - `{foo="meh"}` was written at t=4h and is outside the block.

It is used by `tsdb_block_reader.py` (File 02, listing L3) as an independent oracle for the index, chunk and XOR decoders.

| File | Bytes | Role |
|---|---|---|
| `index` | 5,407 | format v1 index |
| `chunks/000001` | 1,844 | 102 single-sample XOR chunks |
| `meta.json` | 255 | block metadata |
| `tombstones` | 9 | empty tombstones file |
