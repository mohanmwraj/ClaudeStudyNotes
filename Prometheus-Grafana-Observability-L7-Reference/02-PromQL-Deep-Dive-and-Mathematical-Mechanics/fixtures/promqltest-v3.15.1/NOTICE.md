# Fixture provenance

The `*.test` files here are copied byte-for-byte from the Prometheus repository at tag `v3.15.1`, path `promql/promqltest/testdata/`:
<https://github.com/prometheus/prometheus/tree/v3.15.1/promql/promqltest/testdata>

- License: Apache License 2.0, Copyright The Prometheus Authors.
- Use: oracle for `promql_mini.py` (File 01, listing L1).
- Each `eval instant` and `eval range` block is evaluated and compared with the expected samples at 1e-6 relative tolerance.
- Cases L1 cannot evaluate are counted as SKIP with a reason, never as PASS. These are native-histogram literals, `@`, experimental functions, RE2-only regex syntax, and cases that expect an error.

Files: aggregators, functions, histograms, literals, operators, range_queries, selectors, staleness, subquery.
