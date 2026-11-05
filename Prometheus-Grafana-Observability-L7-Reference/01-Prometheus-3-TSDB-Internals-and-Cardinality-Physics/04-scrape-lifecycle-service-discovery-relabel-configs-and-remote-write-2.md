# 04 · Scrape Lifecycle, Service Discovery, Relabel Configs and Remote Write 2.0

> **Folder 01: Prometheus 3 TSDB Internals and Cardinality Physics. File 4 of 4.**
> Pinned to **Prometheus v3.15.1**; source read at tag `v3.15.1`. The Remote Write 2.0 proto in that tag is marked **v2.0-rc.4**.
> Labels: **[D]** documented or read in pinned source. **[M]** measured by a listing here (deterministic, re-run by the gate). **[E]** model. **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L6 `relabel_engine.py` | Port of `model/relabel/relabel.go` with Go `regexp.Expand` template semantics. Passes 16 cases copied verbatim from `relabel_test.go` (including the MD5 `hashmod` results 976 and 734), demonstrates the `$1_suffix` trap and the UTF-8 vs legacy name check, and runs a 2,000-pod Kubernetes target pipeline with 4-way hashmod sharding | <1 s |
| L7 `remote_write_lab.py` | Hand-encoded RW 1.0 `WriteRequest` vs RW 2.0 `Request` (symbol table, inline metadata) for a 2,000-sample batch, raw and snappy-compressed, decoded back. Also a port of `calculateDesiredShards` under a remote-latency spike, and the HTTP retry matrix from `client.go` | <1 s |

**Verification.**
- L6's oracle is the expected output of Prometheus's own `TestRelabel` cases, including two MD5-derived hashmod values that an incorrect hash slice or byte order would miss.
- L7's protobuf is built field-by-field from `prompb/io/prometheus/write/v2/types.proto` and the RW1 `types.proto`, then parsed back with an independent decoder. Its snappy codec is the format-valid encoder from File 01's L2, so compressed sizes approximate Go's snappy rather than equal it [E].
- No live Prometheus or remote receiver was run (binary execution was not permitted in the build environment).

---

## 0. Orientation

**What this file answers.** How a pod becomes a scrape target and a sample becomes a series, where labels are added, rewritten and dropped, and how samples leave Prometheus. It covers four exits: remote write 1.0 and 2.0, federation, and Agent mode; and two push entrances: the remote-write receiver and the OTLP receiver.

**Four relabeling stages, four different jobs [D]:**

| Stage | Config key | Operates on | Typical use | Cost of a mistake |
|---|---|---|---|---|
| Target relabeling | `relabel_configs` | Discovered target labels (`__meta_*`, `__address__`…) | Keep/drop targets, set address/port/path, attach `namespace`/`pod`, shard | Wrong/missing targets, duplicate scrapes |
| Metric relabeling | `metric_relabel_configs` | Every scraped sample (after parse, before append) | Drop families or labels, normalize | CPU per sample; can merge series |
| Write relabeling | `write_relabel_configs` | Samples leaving via remote write (after external labels) | Ship only aggregates or critical series | Silent gaps in the long-term store |
| Alert relabeling | `alerting.alert_relabel_configs` | Alerts before Alertmanager | Strip replica labels for dedupe | Duplicate pages or lost routing |

---

## 1. First principles: from discovery to the wire

### 1.1 The scrape pipeline

```text
 SD providers (kubernetes, ec2, consul, file, http, dns, oci (3.14), … 30+)
   │  target groups { targets: [{__address__}], labels: {__meta_*} }
   ▼
 discovery manager ── throttled fan-out (3.12+: dynamic backoff, was a static 5 s)
   ▼
 scrape manager ── one scrapePool per job_name ── target_limit check
   │   relabel_configs ──► __address__, __scheme__, __metrics_path__, __param_*,
   │                       __scrape_interval__, __scrape_timeout__, internal __*__ toggles
   │   drop all labels starting "__"; instance := __address__ if unset; job := job_name
   ▼
 scrapeLoop per target (goroutine)
   │   start offset = (hash(target labels, URL) XOR server seed) mod interval  ◄─ spreads load
   │   timestamp snapped to the grid if ≤ min(interval/100, 2 ms) late           (File 01 §1.8)
   │   GET <scheme>://<address><path>?<params>
   │       Accept: negotiated scrape_protocols   Accept-Encoding: gzip (+zstd with flag)
   │       X-Prometheus-Scrape-Timeout-Seconds: <scrape_timeout>
   │   body_size_limit ─► parse (text / OpenMetrics 1.0 / protobuf / OM 2.0 with flag)
   │   metric_relabel_configs ─► sample_limit, label_limit, bucket limits ─► FAIL whole scrape if exceeded
   │   staleness: series seen last scrape but absent now ─► append StaleNaN (0x7ff0000000000002)
   │   report series: up, scrape_duration_seconds, scrape_samples_scraped,
   │                  scrape_samples_post_metric_relabeling, scrape_series_added
   │                  (+ scrape_timeout_seconds, scrape_sample_limit, scrape_body_size_bytes
   │                     with extra_scrape_metrics)
   ▼
 headAppender.Commit()  ─► WAL ─► head   (File 01)
```

**Staleness [D].** When a series disappears from a target's exposition, or the target itself disappears, the scrape loop writes a **staleness marker**: a special NaN with bit pattern `0x7ff0000000000002`. PromQL treats it as "no value from here on", so a dead pod's series vanishes from instant queries immediately instead of after the 5-minute lookback.
- If a target exposes its *own* timestamps (`honor_timestamps: true`, the default), Prometheus does not write staleness markers for those series, unless `track_timestamps_staleness: true` is set.
- XOR2 (File 01 §1.5) encodes this marker in 5 bits and keeps the value baseline.

**Load spreading.** Each target's first scrape starts at `(t.hash() ^ offsetSeed) % interval` into the interval, where the hash covers labels and URL. Thousands of targets therefore do not fire on the same tick. Changing a target's labels changes its phase, which is why relabel changes can shift scrape timing.

### 1.2 Relabeling semantics, exactly

```text
 for each rule (defaults: action=replace, separator=";", regex="(.*)", replacement="$1"):
   val   = join(values of source_labels, separator)        missing label ≡ ""
   regex = ^(?s:<regex>)$                                    ALWAYS fully anchored
   replace   : no match → no-op;  target = Expand(target_label), skip if not a valid name
               res = Expand(replacement); res == "" → DELETE target label
   keep/drop : on regex match of val
   keepequal / dropequal : val == value of target_label
   hashmod   : md5(val)[8:16] big-endian mod modulus → target_label
   labelmap  : for each label NAME matching regex → copy value to Expand(replacement)
   labeldrop / labelkeep : on label NAMES (not values)
   lowercase / uppercase : target_label = lower/upper(val)
 Expand(): Go regexp.Expand — $name or ${name}; the name is the LONGEST run of [A-Za-z0-9_]
           so "$1_suffix" means group "1_suffix" → "" ; write "${1}_suffix"
```

L6 verifies these against Prometheus's own test cases [M]. Two of them are worth memorising:
- Case 9: `target_label: $1, replacement: $2` with a one-group regex **deletes** the label named by `$1`. A blank replacement means delete.
- Case 13: a `target_label` expanding to `""` is silently skipped.

**UTF-8 names (3.x default).** With `metric_name_validation_scheme: utf8`, any non-empty UTF-8 string is a valid label name. A relabel rule whose `target_label` comes from a capture can now create labels like `app.kubernetes.io/name`, which legacy validation would have skipped (L6 §2). Downstream systems that still assume `[a-zA-Z_][a-zA-Z0-9_]*` (old Grafana variables, some SQL-backed stores, recording-rule names) break in surprising places.

### 1.3 Sharding and HA

**Horizontal sharding with `hashmod` [D][M].** Each of N Prometheus replicas keeps the targets whose `hashmod(__address__) == own_shard`. L6 §3 shards 1,680 kept targets 4 ways as 420/409/415/436, within 4% of even. MD5 over the joined source values is stable across restarts and versions, and the last-8-bytes rule has not changed since early 2.x.

```text
            ┌──────── all replicas discover ALL targets (SD cost × N) ────────┐
 targets ──►│ shard 0: keep hashmod==0 │ shard 1 │ shard 2 │ shard 3          │
            └──────────┬───────────────┴────┬────┴────┬────┴────┬────────────┘
                       ▼ each shard = HA pair (replica=a/b), same targets
                 remote_write ─────────► Mimir/Thanos: dedupe on {cluster, __replica__}
 changing N rehashes ~(1 − 1/N') of targets to a NEW shard: their series restart there
 (new head series = churn, File 02 §1.5) and the old shard keeps stale copies until head GC
```

**HA pairs.** Two identical replicas with `external_labels: {replica: a|b}` scrape the same targets. Downstream, Mimir's HA tracker or Thanos/Mimir query-time dedupe keeps one. Alertmanager deduplicates notifications across replicas (Folder 04), so alert rules run on both.

**Agent mode (`--agent`).** No local querying, no blocks: the head is WAL-only, with series kept for remote write. Retention is `--storage.agent.retention.min-time` 5 m / `max-time` 4 h, and the WAL is kept until samples are sent or `max-time` passes. Use it for edge clusters that only forward. It needs much less memory, because there are no chunks or queries.

### 1.4 Remote Write: 1.0 vs 2.0 on the wire

```text
 RW 1.0  prometheus.WriteRequest   Content-Type: application/x-protobuf
                                   X-Prometheus-Remote-Write-Version: 0.1.0
   timeseries[1] { labels[1] {name[1] value[2]}…  samples[2] {value[1] timestamp[2]}…
                   exemplars[3]  histograms[4] }
   metadata[3]  (separate requests, every metadata_config.send_interval = 1m)
   → every label NAME and VALUE string is repeated in every series, every request

 RW 2.0  io.prometheus.write.v2.Request   (proto v2.0-rc.4 in v3.15.1)
   Content-Type: application/x-protobuf;proto=io.prometheus.write.v2.Request
   X-Prometheus-Remote-Write-Version: 2.0.0          Content-Encoding: snappy
   symbols[4]  = ["", "__name__", "container_cpu_usage_seconds_total", "namespace", …]
                 (MUST start with ""; the order is up to the sender)
   timeseries[5] { labels_refs[1] = packed uint32 pairs into symbols
                   samples[2] {value[1] timestamp[2] start_timestamp[3]}
                   histograms[3] (native, incl. custom_values for NHCB, start_timestamp[17])
                   exemplars[4] {labels_refs value timestamp}
                   metadata[5] {type[1] help_ref[3] unit_ref[4]} }   ← ALWAYS sent inline
   response headers: X-Prometheus-Remote-Write-Samples-Written / -Histograms-Written /
                     -Exemplars-Written (receiver tells the sender what was actually stored)
   fields 1-3 reserved: a v1 message parsed as v2 decodes to an EMPTY request, not garbage
```

L7 §1 encodes one realistic 2,000-sample batch (`max_samples_per_send`) both ways [M]:

| Encoding | Raw B | B/sample | Snappy B | B/sample |
|---|---|---|---|---|
| RW1 `WriteRequest` | 403,176 | 201.6 | 50,793 | 25.4 |
| RW2, no metadata | 77,089 | 38.5 | 34,808 | 17.4 |
| RW2, inline metadata | 92,238 | 46.1 | 36,533 | 18.3 |

The mechanics:
- RW2's symbol table removes ~77% of raw bytes, because Kubernetes label sets are ~95% repeated strings.
- After snappy, which already exploits repetition, RW2 is still **~28% smaller** *while carrying metadata, start timestamps and written-count acknowledgements* that RW1 lacked.
- For a fleet pushing 1 M samples/s, that is the difference between ~25 MB/s and ~18 MB/s of compressed egress [E: the snappy ratio approximates Go's].
- The CPU cost moves to the sender: building a symbol table per request.

**Receiver-side protection (3.12+).** Prometheus rejects snappy requests whose *declared* decoded length exceeds 32 MB. That fixed a decompression-bomb DoS on `/api/v1/write`.

### 1.5 The remote-write pipeline and its autoscaler

```text
 WAL segments ──► WAL watcher (tails segments, reads Series/Samples/Histograms records)
                     │  write_relabel_configs, external_labels, sample_age_limit
                     ▼
                 QueueManager (one per remote_write)
                     │  shards = N goroutines, each: queue (capacity 10,000)
                     │  batch = max_samples_per_send (2,000) or batch_send_deadline (5 s)
                     ▼
                 HTTP POST (snappy) ─► 2xx ok
                                      5xx ─► retry, backoff 30 ms → 5 s (Retry-After honoured)
                                      429 ─► retry ONLY if retry_on_http_429: true (default false!)
                                      other 4xx ─► DROP the batch (non-recoverable)
 every 10 s: desired = timePerSample × (inRate·keptRatio + 0.05·pending)
             change only if outside ±30% of current; ceil; clamp [min_shards, max_shards];
             never down-shard while > 10 s behind
```

L7 §2 runs the autoscaler for 1 M series @15 s (66,667 samples/s) [M]:
- At 80 ms per batch, 4 shards suffice.
- When latency jumps to 2 s, shards hit **50 (the default `max_shards`)**. 50 shards × 2,000 / 2 s = 50,000 samples/s < 66,667, so the queue falls behind by **~5 minutes** over 20 minutes.
- With `max_shards: 200` the same spike costs **9 s** of lag.

The danger is not the lag itself; it is what happens if lag exceeds what the WAL still holds:
- Prometheus truncates the WAL at head compaction regardless of remote-write progress (File 01 §1.9).
- A remote write more than ~1–2 h behind starts *losing* data, which shows up as `prometheus_remote_storage_samples_dropped_total` and gaps in the long-term store.
- Agent mode instead keeps WAL until sent, up to `max-time`.

**Lag metric:** `prometheus_remote_storage_queue_highest_timestamp_seconds − prometheus_remote_storage_queue_highest_sent_timestamp_seconds`.

### 1.6 The OTLP receiver

`--web.enable-otlp-receiver` exposes `POST /api/v1/otlp/v1/metrics` (OTLP/HTTP protobuf) [D]. Translation is configured in the `otlp:` block:
- `translation_strategy`:
  - `UnderscoreEscapingWithSuffixes` (default): `http.server.request.duration` (unit `s`) → `http_server_request_duration_seconds`;
  - `UnderscoreEscapingWithoutSuffixes`;
  - `NoUTF8EscapingWithSuffixes` (keeps dots, adds suffixes);
  - experimental `NoTranslation`.
- `service.name` / `service.namespace` → `job`, and `service.instance.id` → `instance`. Remaining resource attributes go to a `target_info` series unless promoted.
- `promote_resource_attributes: [k8s.namespace.name, k8s.pod.name, …]` copies chosen attributes onto every series. `promote_all_resource_attributes: true` promotes everything except `ignore_resource_attributes`, which is a cardinality and churn hazard.
- Delta temporality: `--enable-feature=otlp-deltatocumulative` (3.2+), or experimental native delta ingestion.
- Histograms: exponential → native (File 03 §1.7); explicit → classic, or NHCB with `convert_histograms_to_nhcb`.

The docs say plainly that OTLP and remote-write *receivers* are "not considered an efficient way of ingesting samples … for specific low-volume use cases". For fleet-scale OTLP, put an OTel Collector or Grafana Alloy in front and remote-write to Mimir (Folder 06). Do not turn a Prometheus server into a push gateway.

<!-- listing:relabel_engine.py -->
```python
"""relabel_engine.py - Prometheus v3.15.1 relabeling (model/relabel/relabel.go), Go regexp
template expansion, and a Kubernetes target pipeline with hashmod sharding.

Port notes (tag v3.15.1):
  * Defaults: action replace, separator ';', regex '(.*)', replacement '$1'. Regexes are
    anchored as '^(?s:<regex>)$' (here: re.fullmatch with re.S).
  * replace: no match -> no-op; target and replacement are expanded with Go Regexp.Expand
    semantics ($name / ${name}; $1x means the group NAMED '1x', which does not exist -> '');
    an expanded target that is not a valid label name is skipped; an empty result DELETES the
    target label.
  * hashmod: md5(joined source values), last 8 bytes big-endian, mod modulus.
  * keepequal / dropequal compare the joined source values with the target label's value.
  * Name validation: 3.x default 'utf8' accepts any non-empty UTF-8 name; 'legacy' requires
    [a-zA-Z_][a-zA-Z0-9_]*.
The oracle is 16 cases copied from model/relabel/relabel_test.go TestRelabel (expected outputs
verbatim, including the md5 hashmod results 976 and 734).

Usage: python relabel_engine.py [target.md]
"""
import hashlib
import re
import sys

DEFAULT = {"action": "replace", "separator": ";", "regex": "(.*)", "replacement": "$1"}


def valid_label_name(name, scheme="utf8"):
    if scheme == "legacy":
        return re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", name) is not None
    return name != ""


def go_expand(template, m):
    """Go regexp.(*Regexp).ExpandString."""
    out, i = [], 0
    while i < len(template):
        j = template.find("$", i)
        if j < 0:
            out.append(template[i:])
            break
        out.append(template[i:j])
        rest = template[j + 1:]
        if rest.startswith("$"):
            out.append("$")
            i = j + 2
            continue
        brace = rest.startswith("{")
        k = 1 if brace else 0
        n0 = k
        while k < len(rest) and (rest[k] == "_" or rest[k].isalnum()):
            k += 1
        name = rest[n0:k]
        if not name or (brace and (k >= len(rest) or rest[k] != "}")):
            out.append("$")  # malformed: '$' is literal
            i = j + 1
            continue
        i = j + 1 + k + (1 if brace else 0)
        if name.isdigit():
            num = int(name)
            if num <= m.re.groups and m.group(num) is not None:
                out.append(m.group(num))
        elif name in m.re.groupindex and m.group(name) is not None:
            out.append(m.group(name))
    return "".join(out)


def relabel(lbls, cfgs, scheme="utf8"):
    lb = dict(lbls)
    for raw in cfgs:
        c = {**DEFAULT, **raw}
        rx = re.compile(c["regex"], re.S)
        val = c["separator"].join(lb.get(s, "") for s in c.get("source_labels", []))
        act, tgt = c["action"], c.get("target_label", "")
        if act == "drop" and rx.fullmatch(val):
            return None
        if act == "keep" and not rx.fullmatch(val):
            return None
        if act == "dropequal" and lb.get(tgt, "") == val:
            return None
        if act == "keepequal" and lb.get(tgt, "") != val:
            return None
        if act == "replace":
            if val == "" and c["regex"] == DEFAULT["regex"] and "$" not in tgt and "$" not in c["replacement"]:
                lb[tgt] = c["replacement"]  # fast path (an empty replacement still sets "")
                lb = {k: v for k, v in lb.items() if v != ""}
                continue
            m = rx.fullmatch(val)
            if not m:
                continue
            target = go_expand(tgt, m)
            if not valid_label_name(target, scheme):
                continue
            res = go_expand(c["replacement"], m)
            if res == "":
                lb.pop(target, None)
            else:
                lb[target] = res
        elif act == "lowercase":
            lb[tgt] = val.lower()
        elif act == "uppercase":
            lb[tgt] = val.upper()
        elif act == "hashmod":
            h = hashlib.md5(val.encode()).digest()
            lb[tgt] = str(int.from_bytes(h[8:], "big") % c["modulus"])
        elif act == "labelmap":
            for k, v in sorted(lb.items()):
                if rx.fullmatch(k):
                    lb[rx.sub(lambda mm: go_expand(c["replacement"], mm), k, count=1)] = v
        elif act == "labeldrop":
            lb = {k: v for k, v in lb.items() if not rx.fullmatch(k)}
        elif act == "labelkeep":
            lb = {k: v for k, v in lb.items() if rx.fullmatch(k)}
        lb = {k: v for k, v in lb.items() if v != ""}  # labels.Builder drops empty values
    return lb


# 16 cases from relabel_test.go TestRelabel (v3.15.1); configs there are built in Go code, so
# unset fields are zero values, not YAML defaults - mirrored with explicit keys below.
ORACLE = [
    ({"a": "foo", "b": "bar", "c": "baz"},
     [dict(source_labels=["a"], regex="f(.*)", target_label="d", replacement="ch${1}-ch${1}")],
     {"a": "foo", "b": "bar", "c": "baz", "d": "choo-choo"}),
    ({"a": "foo", "b": "bar", "c": "baz"},
     [dict(source_labels=["a", "b"], regex="f(.*);(.*)r", target_label="a", replacement="b${1}${2}m"),
      dict(source_labels=["c", "a"], regex="(b).*b(.*)ba(.*)", target_label="d", replacement="$1$2$2$3")],
     {"a": "boobam", "b": "bar", "c": "baz", "d": "boooom"}),
    ({"a": "foo"}, [dict(source_labels=["a"], regex=".*o.*", action="drop"),
                    dict(source_labels=["a"], regex="f(.*)", target_label="d", replacement="ch$1-ch$1")], None),
    ({"a": "abc"}, [dict(source_labels=["a"], regex=".*(b).*", target_label="d", replacement="$1")],
     {"a": "abc", "d": "b"}),
    ({"a": "foo"}, [dict(source_labels=["a"], regex="no-match", action="drop")], {"a": "foo"}),
    ({"a": "foo"}, [dict(source_labels=["a"], regex="f|o", action="drop")], {"a": "foo"}),
    ({"a": "foo"}, [dict(source_labels=["a"], regex="no-match", action="keep")], None),
    ({"a": "boo"}, [dict(source_labels=["a"], regex="f", target_label="b", replacement="bar")], {"a": "boo"}),
    ({"a": "foo", "f": "baz"}, [dict(source_labels=["a"], regex="(f).*", target_label="$1", replacement="$2")],
     {"a": "foo"}),
    ({"a": "foo", "b": "bar", "c": "baz"}, [dict(source_labels=["c"], target_label="d", action="hashmod", modulus=1000)],
     {"a": "foo", "b": "bar", "c": "baz", "d": "976"}),
    ({"a": "foo\nbar"}, [dict(source_labels=["a"], target_label="b", action="hashmod", modulus=1000)],
     {"a": "foo\nbar", "b": "734"}),
    ({"a": "foo", "__meta_my_bar": "aaa", "__meta_my_baz": "bbb", "__meta_other": "ccc"},
     [dict(regex="__meta_(my.*)", replacement="${1}", action="labelmap")],
     {"a": "foo", "__meta_my_bar": "aaa", "__meta_my_baz": "bbb", "__meta_other": "ccc", "my_bar": "aaa", "my_baz": "bbb"}),
    ({"a": "some-name-0"}, [dict(source_labels=["a"], regex="some-([^-]+)-([^,]+)", replacement="${1}", target_label="${3}")],
     {"a": "some-name-0"}),
    ({"__meta_sd_tags": "path:/secret,job:some-job,label:foo=bar"},
     [dict(source_labels=["__meta_sd_tags"], regex="(?:.+,|^)path:(/[^,]+).*", replacement="${1}", target_label="__metrics_path__"),
      dict(source_labels=["__meta_sd_tags"], regex="(?:.+,|^)job:([^,]+).*", replacement="${1}", target_label="job"),
      dict(source_labels=["__meta_sd_tags"], regex="(?:.+,|^)label:([^=]+)=([^,]+).*", replacement="${2}", target_label="${1}")],
     {"__meta_sd_tags": "path:/secret,job:some-job,label:foo=bar", "__metrics_path__": "/secret", "job": "some-job", "foo": "bar"}),
    ({"foo": "bAr123Foo"}, [dict(source_labels=["foo"], action="uppercase", target_label="foo_uppercase"),
                            dict(source_labels=["foo"], action="lowercase", target_label="foo_lowercase")],
     {"foo": "bAr123Foo", "foo_lowercase": "bar123foo", "foo_uppercase": "BAR123FOO"}),
    ({"__tmp_port": "1234", "__port1": "1234", "__port2": "5678"},
     [dict(source_labels=["__tmp_port"], action="dropequal", target_label="__port1")], None),
]

K8S_POD_RELABEL = [  # the canonical annotation-driven pod scrape job (see the YAML in the file)
    dict(source_labels=["__meta_kubernetes_pod_annotation_prometheus_io_scrape"], regex="true", action="keep"),
    dict(source_labels=["__meta_kubernetes_pod_phase"], regex="Pending|Succeeded|Failed|Completed", action="drop"),
    dict(source_labels=["__meta_kubernetes_pod_annotation_prometheus_io_path"], regex="(.+)", target_label="__metrics_path__"),
    dict(source_labels=["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"],
         regex="(.+?)(?::\\d+)?;(\\d+)", replacement="$1:$2", target_label="__address__"),
    dict(source_labels=["__address__"], action="hashmod", modulus=4, target_label="__tmp_hash"),
    dict(source_labels=["__tmp_hash"], regex="2", action="keep"),  # this replica owns shard 2 of 4
    dict(regex="__meta_kubernetes_pod_label_(.+)", action="labelmap"),
    dict(source_labels=["__meta_kubernetes_namespace"], target_label="namespace"),
    dict(source_labels=["__meta_kubernetes_pod_name"], target_label="pod"),
    dict(regex="pod_template_hash|controller_revision_hash", action="labeldrop"),
]


def finalize(lb):
    """scrape/target.go PopulateLabels: instance defaults to __address__; '__' labels are dropped."""
    if lb is None:
        return None
    lb.setdefault("instance", lb.get("__address__", ""))
    return {k: v for k, v in lb.items() if not k.startswith("__")}


def main():
    checks = []
    print("== 1. Oracle: 16 TestRelabel cases from relabel_test.go ==")
    for i, (inp, cfgs, want) in enumerate(ORACLE, 1):
        got = relabel(inp, cfgs)
        checks.append((f"case {i}", got == want))
        print(f"case {i:>2} {'ok ' if got == want else 'BAD'} {cfgs[0].get('action', 'replace'):<9} -> "
              f"{'DROPPED' if got is None else sorted((got or {}).items())[:3]}")
    print()

    print("== 2. Go template traps ==")
    m = re.fullmatch("(.*)", "api")
    for tpl in ("$1_suffix", "${1}_suffix", "$1-suffix", "$$1", "${1", "prefix_$1"):
        print(f"replacement {tpl!r:<14} on 'api' -> {go_expand(tpl, m)!r}")
    checks.append(("$1_suffix is empty", go_expand("$1_suffix", m) == ""))
    checks.append(("${1}_suffix", go_expand("${1}_suffix", m) == "api_suffix"))
    for scheme in ("utf8", "legacy"):
        got = relabel({"__meta_kubernetes_pod_label_app_kubernetes_io_name": "x", "src": "app.kubernetes.io/name"},
                      [dict(source_labels=["src"], regex="(.+)", target_label="$1", replacement="checkout")], scheme)
        print(f"target_label from capture 'app.kubernetes.io/name' under {scheme!r}: "
              f"{'created' if 'app.kubernetes.io/name' in got else 'skipped (invalid name)'}")
        checks.append((f"name scheme {scheme}", ('app.kubernetes.io/name' in got) == (scheme == "utf8")))
    print()

    print("== 3. Kubernetes pod targets -> relabel -> 4-way hashmod sharding ==")
    targets = []
    for i in range(2_000):
        ns = ("checkout", "cart", "search", "payments", "kube-system")[i % 5]
        targets.append({
            "__address__": f"10.{8 + i // 60000}.{(i // 250) % 256}.{i % 250}:{8080 if i % 3 else 9102}",
            "__meta_kubernetes_namespace": ns,
            "__meta_kubernetes_pod_name": f"{ns}-{i:05d}",
            "__meta_kubernetes_pod_phase": "Running" if i % 50 else "Succeeded",
            "__meta_kubernetes_pod_annotation_prometheus_io_scrape": "true" if i % 7 else "false",
            "__meta_kubernetes_pod_annotation_prometheus_io_port": "9090",
            "__meta_kubernetes_pod_label_app": f"{ns}-svc",
            "__meta_kubernetes_pod_label_pod_template_hash": f"{i * 7919 % 99999:05x}",
        })
    shards = [0, 0, 0, 0]
    kept = []
    for t in targets:
        lb = relabel(t, K8S_POD_RELABEL[:5])
        if lb is not None:
            shards[int(lb["__tmp_hash"])] += 1
        out = finalize(relabel(t, K8S_POD_RELABEL))
        if out is not None:
            kept.append(out)
    print(f"discovered {len(targets):,}; after keep/drop {sum(shards):,}; per-shard {shards}; "
          f"this replica (shard 2) scrapes {len(kept):,}")
    print(f"example target labels: {sorted(kept[0].items())}")
    checks.append(("shard balance within 10%", max(shards) / (sum(shards) / 4) < 1.10))
    checks.append(("port rewritten to annotation", all(k["instance"].endswith(":9090") for k in kept)))
    checks.append(("pod_template_hash dropped", all("pod_template_hash" not in k for k in kept)))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed[:5]}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:relabel_engine.py -->
```text
== 1. Oracle: 16 TestRelabel cases from relabel_test.go ==
case  1 ok  replace   -> [('a', 'foo'), ('b', 'bar'), ('c', 'baz')]
case  2 ok  replace   -> [('a', 'boobam'), ('b', 'bar'), ('c', 'baz')]
case  3 ok  drop      -> DROPPED
case  4 ok  replace   -> [('a', 'abc'), ('d', 'b')]
case  5 ok  drop      -> [('a', 'foo')]
case  6 ok  drop      -> [('a', 'foo')]
case  7 ok  keep      -> DROPPED
case  8 ok  replace   -> [('a', 'boo')]
case  9 ok  replace   -> [('a', 'foo')]
case 10 ok  hashmod   -> [('a', 'foo'), ('b', 'bar'), ('c', 'baz')]
case 11 ok  hashmod   -> [('a', 'foo\nbar'), ('b', '734')]
case 12 ok  labelmap  -> [('__meta_my_bar', 'aaa'), ('__meta_my_baz', 'bbb'), ('__meta_other', 'ccc')]
case 13 ok  replace   -> [('a', 'some-name-0')]
case 14 ok  replace   -> [('__meta_sd_tags', 'path:/secret,job:some-job,label:foo=bar'), ('__metrics_path__', '/secret'), ('foo', 'bar')]
case 15 ok  uppercase -> [('foo', 'bAr123Foo'), ('foo_lowercase', 'bar123foo'), ('foo_uppercase', 'BAR123FOO')]
case 16 ok  dropequal -> DROPPED

== 2. Go template traps ==
replacement '$1_suffix'    on 'api' -> ''
replacement '${1}_suffix'  on 'api' -> 'api_suffix'
replacement '$1-suffix'    on 'api' -> 'api-suffix'
replacement '$$1'          on 'api' -> '$1'
replacement '${1'          on 'api' -> '${1'
replacement 'prefix_$1'    on 'api' -> 'prefix_api'
target_label from capture 'app.kubernetes.io/name' under 'utf8': created
target_label from capture 'app.kubernetes.io/name' under 'legacy': skipped (invalid name)

== 3. Kubernetes pod targets -> relabel -> 4-way hashmod sharding ==
discovered 2,000; after keep/drop 1,680; per-shard [420, 409, 415, 436]; this replica (shard 2) scrapes 415
example target labels: [('app', 'cart-svc'), ('instance', '10.8.0.1:9090'), ('namespace', 'cart'), ('pod', 'cart-00001')]

checks: 23/23 passed
verdict: OK
```

<!-- listing:remote_write_lab.py -->
```python
"""remote_write_lab.py - Remote Write 1.0 vs 2.0 wire encoding and the remote-write shard
autoscaler, ported from Prometheus v3.15.1.

Sources (tag v3.15.1):
  prompb/types.proto, prompb/remote.proto          RW 1.0 prometheus.WriteRequest
  prompb/io/prometheus/write/v2/types.proto (v2.0-rc.4)  RW 2.0 Request: symbols=4 (MUST start
      with ""), timeseries=5{labels_refs=1 packed, samples=2{value=1,timestamp=2,
      start_timestamp=3}, metadata=5{type=1, help_ref=3, unit_ref=4}}
  storage/remote/queue_manager.go  calculateDesiredShards: desired = timePerSample *
      (inRate*keptRatio + 0.05*pending); +-30% tolerance band; ceil; clamp [min,max]; no
      down-sharding while >10 s behind; recomputed every 10 s (shardUpdateDuration).
  config/config.go DefaultQueueConfig: max_shards 50, min_shards 1, max_samples_per_send 2000,
      capacity 10000, batch_send_deadline 5s, min_backoff 30ms, max_backoff 5s.
  storage/remote/client.go  2xx ok; 5xx retried; 429 retried ONLY if retry_on_http_429 (default
      false); other 4xx dropped.
Both payloads are snappy-compressed with the block-format encoder from wal_head_lab.py.

Usage: python remote_write_lab.py [target.md]
"""
import math
import pathlib
import random
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from wal_head_lab import snappy_compress, snappy_decompress  # noqa: E402
from xor_chunk import T0  # noqa: E402


def uv(x):
    out = bytearray()
    while x >= 0x80:
        out.append((x & 0x7F) | 0x80)
        x >>= 7
    out.append(x)
    return bytes(out)


def fld(num, wt, payload=b""):
    return uv(num << 3 | wt) + payload


def ld(num, b):  # length-delimited field
    return fld(num, 2, uv(len(b)) + b)


def sample_msg(v, t, st=0):
    b = fld(1, 1, struct.pack("<d", v)) + fld(2, 0, uv(t & 0xFFFFFFFFFFFFFFFF))
    return b + (fld(3, 0, uv(st)) if st else b"")


def rw1(series):  # [(labels sorted, value, ts)]
    out = bytearray()
    for lbls, v, t, _meta in series:
        ts = b"".join(ld(1, ld(1, n.encode()) + ld(2, val.encode())) for n, val in lbls)
        ts += ld(2, sample_msg(v, t))
        out += ld(1, ts)
    return bytes(out)


def rw1_metadata(families):  # separate request every metadata send_interval (1m)
    out = bytearray()
    for name, (typ, help_, unit) in families.items():
        out += ld(3, fld(1, 0, uv(typ)) + ld(2, name.encode()) + ld(4, help_.encode()) + ld(5, unit.encode()))
    return bytes(out)


def rw2(series, with_metadata=True):
    symbols, idx = [""], {"": 0}

    def ref(s):
        if s not in idx:
            idx[s] = len(symbols)
            symbols.append(s)
        return idx[s]

    tss = bytearray()
    for lbls, v, t, meta in series:
        refs = b"".join(uv(ref(x)) for kv in lbls for x in kv)
        ts = ld(1, refs) + ld(2, sample_msg(v, t))
        if with_metadata and meta:
            typ, help_, unit = meta
            m = fld(1, 0, uv(typ)) + fld(3, 0, uv(ref(help_))) + (fld(4, 0, uv(ref(unit))) if unit else b"")
            ts += ld(5, m)
        tss += ld(5, ts)
    return b"".join(ld(4, s.encode()) for s in symbols) + bytes(tss), symbols


def parse(b):  # generic protobuf -> list of (field, wiretype, value)
    out, pos = [], 0
    while pos < len(b):
        key, pos = _uv(b, pos)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, pos = _uv(b, pos)
        elif wt == 1:
            v, pos = b[pos:pos + 8], pos + 8
        elif wt == 2:
            n, pos = _uv(b, pos)
            v, pos = b[pos:pos + n], pos + n
        else:
            raise ValueError(wt)
        out.append((f, wt, v))
    return out


def _uv(b, pos):
    x = s = 0
    while True:
        c = b[pos]
        pos += 1
        x |= (c & 0x7F) << s
        if c < 0x80:
            return x, pos
        s += 7


def decode_rw2(b):
    fields = parse(b)
    symbols = [v.decode() for f, _, v in fields if f == 4]
    out = []
    for f, _, v in fields:
        if f != 5:
            continue
        ts = parse(v)
        raw = next(x for ff, _, x in ts if ff == 1)
        refs, p = [], 0
        while p < len(raw):
            r, p = _uv(raw, p)
            refs.append(r)
        lbls = [(symbols[refs[i]], symbols[refs[i + 1]]) for i in range(0, len(refs), 2)]
        s = {ff: x for ff, _, x in parse(next(x for ff, _, x in ts if ff == 2))}
        out.append((lbls, struct.unpack("<d", s[1])[0], s[2]))
    return symbols, out


FAMILIES = {
    "container_cpu_usage_seconds_total": (1, "Cumulative cpu time consumed in seconds.", "seconds"),
    "container_memory_working_set_bytes": (2, "Current working set in bytes.", "bytes"),
    "http_server_request_duration_seconds_bucket": (3, "Duration of HTTP server requests.", "seconds"),
    "kube_pod_status_phase": (2, "The pods current phase.", ""),
}


def batch(rng, n=2000):
    series = []
    while len(series) < n:
        p = len(series) // 40
        ns = ("checkout", "cart", "search", "payments")[p % 4]
        base = [("instance", f"10.3.{p // 250}.{p % 250}:8080"), ("job", "kubernetes-pods"),
                ("namespace", ns), ("pod", f"{ns}-6d5f8b{p:04d}-{rng.getrandbits(20):05x}")]
        for name in FAMILIES:
            extra = [[("container", "app")]] if name.startswith("container") else \
                [[("le", le), ("route", "/api/cart")] for le in ("0.05", "0.1", "0.25", "0.5", "1", "2.5", "5", "+Inf")] \
                if name.startswith("http") else [[("phase", ph)] for ph in ("Pending", "Running", "Succeeded", "Failed")]
            for e in extra:
                lbls = tuple(sorted(base + e + [("__name__", name)]))
                series.append((lbls, float(rng.randint(0, 10**9)), T0 + rng.randint(0, 999), FAMILIES[name]))
    return series[:n]


def shard_sim(in_rate, latency_profile, minutes=60, batch_n=2000, max_shards=50):
    """10 s ticks of calculateDesiredShards against a remote whose per-batch latency varies."""
    shards, pending, rows, peak_lag = 1, 0.0, [], 0.0
    for tick in range(minutes * 6):
        lat = latency_profile(tick * 10)
        capacity = shards * batch_n / lat  # samples/s the current shards can push
        out_rate = min(capacity, in_rate + pending / 10)
        pending = max(0.0, pending + (in_rate - out_rate) * 10)
        delay = pending / in_rate
        time_per_sample = lat / batch_n  # dataOutDuration / dataOutRate
        desired = time_per_sample * (in_rate + 0.05 * pending)
        lo, hi = shards * 0.7, shards * 1.3
        d = math.ceil(desired)
        if not (lo <= d <= hi):
            if not (d < shards and delay > 10):
                shards = min(max(d, 1), max_shards)
        peak_lag = max(peak_lag, delay)
        rows.append((tick * 10, lat, shards, delay))
    return rows, peak_lag


def main():
    checks = []
    rng = random.Random(8)
    series = batch(rng)
    b1, b1m = rw1(series), rw1_metadata(FAMILIES)
    b2, syms = rw2(series)
    b2n, _ = rw2(series, with_metadata=False)
    z1, z2, z2n = snappy_compress(b1), snappy_compress(b2), snappy_compress(b2n)
    checks.append(("snappy round trip", snappy_decompress(z2) == b2 and snappy_decompress(z1) == b1))
    sy, dec = decode_rw2(b2)
    checks.append(("RW2 decode == input", sy[0] == "" and [(list(l), v, t) for l, v, t, _ in series] == dec))
    n = len(series)
    print(f"== 1. One batch: {n} samples (max_samples_per_send), {len(syms)} distinct symbols ==")
    print(f"{'encoding':<34} {'raw B':>9} {'B/sample':>9} {'snappy B':>9} {'B/sample':>9}")
    for name, raw, z in (("RW1 prometheus.WriteRequest", b1, z1),
                         ("RW2 Request, no metadata", b2n, z2n),
                         ("RW2 Request, inline metadata", b2, z2)):
        print(f"{name:<34} {len(raw):>9,} {len(raw) / n:>9.1f} {len(z):>9,} {len(z) / n:>9.1f}")
    print(f"RW1 metadata request (separate, every 1m): {len(b1m)} B for {len(FAMILIES)} families")
    print(f"RW2/RW1 raw {len(b2) / len(b1):.2f}x, compressed {len(z2) / len(z1):.2f}x "
          f"(symbol table interns every label string once per request)")
    checks.append(("RW2 smaller raw", len(b2) < 0.5 * len(b1)))
    print()

    print("== 2. Shard autoscaling: 1M series @15s (66,667 samples/s), remote latency 80 ms -> 2 s spike ==")
    prof = lambda s: 2.0 if 600 <= s < 1800 else 0.08  # noqa: E731
    rows, peak = shard_sim(1_000_000 / 15, prof)
    for t, lat, sh, lag in rows:
        if t % 300 == 0 or t in (610, 620, 1810, 1820):
            print(f"t={t // 60:>3}m{t % 60:02d}s latency {lat * 1000:>5.0f} ms shards {sh:>3} behind {lag:>7.1f} s")
    print(f"peak lag {peak / 60:.1f} min (max_shards=50 caps throughput at {50 * 2000 / 2.0:,.0f} samples/s < 66,667)")
    checks.append(("caps at 50 during spike", max(sh for _, _, sh, _ in rows) == 50))
    checks.append(("recovers after spike", rows[-1][3] < 1))
    rows2, peak2 = shard_sim(1_000_000 / 15, prof, max_shards=200)
    print(f"same spike with max_shards=200: peak lag {peak2:.0f} s")
    checks.append(("more shards bound the lag", peak2 < peak))
    print()

    print("== 3. Response handling (storage/remote/client.go) ==")
    for code, retry429 in ((200, False), (204, False), (400, False), (404, False), (429, False), (429, True), (500, False), (503, False)):
        verdict = "ok" if code // 100 == 2 else "RETRY with backoff 30ms..5s (Retry-After honoured)" if (
            code // 100 == 5 or (code == 429 and retry429)) else "DROP batch (non-recoverable)"
        print(f"HTTP {code} retry_on_http_429={str(retry429).lower():<5} -> {verdict}")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:remote_write_lab.py -->
```text
== 1. One batch: 2000 samples (max_samples_per_send), 232 distinct symbols ==
encoding                               raw B  B/sample  snappy B  B/sample
RW1 prometheus.WriteRequest          403,176     201.6    50,793      25.4
RW2 Request, no metadata              77,089      38.5    34,808      17.4
RW2 Request, inline metadata          92,238      46.1    36,533      18.3
RW1 metadata request (separate, every 1m): 315 B for 4 families
RW2/RW1 raw 0.23x, compressed 0.72x (symbol table interns every label string once per request)

== 2. Shard autoscaling: 1M series @15s (66,667 samples/s), remote latency 80 ms -> 2 s spike ==
t=  0m00s latency    80 ms shards   4 behind     6.3 s
t=  5m00s latency    80 ms shards   4 behind     0.0 s
t= 10m00s latency  2000 ms shards  50 behind     9.4 s
t= 10m10s latency  2000 ms shards  50 behind    11.9 s
t= 10m20s latency  2000 ms shards  50 behind    14.4 s
t= 15m00s latency  2000 ms shards  50 behind    84.4 s
t= 20m00s latency  2000 ms shards  50 behind   159.4 s
t= 25m00s latency  2000 ms shards  50 behind   234.4 s
t= 30m00s latency    80 ms shards  50 behind   129.4 s
t= 30m10s latency    80 ms shards   3 behind     0.0 s
t= 30m20s latency    80 ms shards   3 behind     0.0 s
t= 35m00s latency    80 ms shards   3 behind     0.0 s
t= 40m00s latency    80 ms shards   3 behind     0.0 s
t= 45m00s latency    80 ms shards   3 behind     0.0 s
t= 50m00s latency    80 ms shards   3 behind     0.0 s
t= 55m00s latency    80 ms shards   3 behind     0.0 s
peak lag 5.1 min (max_shards=50 caps throughput at 50,000 samples/s < 66,667)
same spike with max_shards=200: peak lag 9 s

== 3. Response handling (storage/remote/client.go) ==
HTTP 200 retry_on_http_429=false -> ok
HTTP 204 retry_on_http_429=false -> ok
HTTP 400 retry_on_http_429=false -> DROP batch (non-recoverable)
HTTP 404 retry_on_http_429=false -> DROP batch (non-recoverable)
HTTP 429 retry_on_http_429=false -> DROP batch (non-recoverable)
HTTP 429 retry_on_http_429=true  -> RETRY with backoff 30ms..5s (Retry-After honoured)
HTTP 500 retry_on_http_429=false -> RETRY with backoff 30ms..5s (Retry-After honoured)
HTTP 503 retry_on_http_429=false -> RETRY with backoff 30ms..5s (Retry-After honoured)

checks: 6/6 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 A complete, sharded Kubernetes `prometheus.yml` (shard 2 of 4, replica a)

```yaml
global:
  scrape_interval: 30s
  scrape_timeout: 10s
  evaluation_interval: 30s
  scrape_native_histograms: false
  external_labels:
    cluster: prod-eu-west-1
    shard: "2"
    __replica__: a                       # Mimir HA tracker / Thanos dedupe label (dropped on query)
  sample_limit: 50000
  label_limit: 40
  body_size_limit: 50MB
runtime:
  gogc: 75
rule_files:
  - /etc/prometheus/rules/*.yaml
scrape_configs:
  - job_name: kubernetes-pods
    honor_labels: false
    target_limit: 3000
    kubernetes_sd_configs:
      - role: pod
        selectors:
          - role: pod
            field: status.phase=Running
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        regex: "true"
        action: keep
      - source_labels: [__address__]       # shard BEFORE any expensive relabeling
        modulus: 4
        target_label: __tmp_hash
        action: hashmod
      - source_labels: [__tmp_hash]
        regex: "2"
        action: keep
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        regex: (.+)
        target_label: __metrics_path__
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        regex: (.+?)(?::\d+)?;(\d+)
        replacement: "${1}:${2}"           # braces: "$1:$2" also works, "$1_x" would not
        target_label: __address__
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
        regex: (https?)
        target_label: __scheme__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(app_kubernetes_io_name|app_kubernetes_io_component|team)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: go_gc_duration_seconds.*|go_memstats_(alloc|frees|lookups|mallocs)_.*
        action: drop
      - action: labeldrop
        regex: pod_template_hash|controller_revision_hash
  - job_name: kubernetes-cadvisor
    scheme: https
    metrics_path: /metrics/cadvisor
    authorization:
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - source_labels: [__meta_kubernetes_node_name]
        modulus: 4
        target_label: __tmp_hash
        action: hashmod
      - source_labels: [__tmp_hash]
        regex: "2"
        action: keep
      - source_labels: [__meta_kubernetes_node_name]
        target_label: node
    metric_relabel_configs:
      - source_labels: [__name__]           # cAdvisor is the #1 cardinality source; keep what you use
        regex: container_(cpu_usage_seconds_total|cpu_cfs_(periods|throttled_periods)_total|memory_working_set_bytes|oom_events_total|network_(receive|transmit)_bytes_total|fs_(reads|writes)_bytes_total)
        action: keep
      - source_labels: [container]
        regex: ""                           # drop pod-level cgroup aggregates without a container
        action: drop
remote_write:
  - name: mimir
    url: https://mimir.example.internal/api/v1/push
    protobuf_message: io.prometheus.write.v2.Request
    send_native_histograms: true
    send_exemplars: true
    remote_timeout: 30s
    headers:
      X-Scope-OrgID: platform
    queue_config:
      capacity: 10000
      max_shards: 200                       # default 50 caps throughput at 50 x 2000 / latency
      min_shards: 4
      max_samples_per_send: 2000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s
      retry_on_http_429: true               # default false = rate-limited batches are DROPPED
      sample_age_limit: 30m                 # do not replay hour-old data into a recovering backend
    write_relabel_configs:
      - source_labels: [__name__]
        regex: kubernetes_pods:.*|.*:.*:.*  # ship recording-rule aggregates ...
        action: keep
      # ... plus a curated raw allowlist would go in a second remote_write if needed
```

> **Order matters in `relabel_configs`.** `keep` and `hashmod` run first, so the remaining rules execute only for this shard's targets. Each replica still runs SD for *all* targets, so for very large clusters use `selectors` (field and label selectors pushed to the API server) to cut SD volume.

### 2.2 Agent-mode forwarder for an edge cluster

```yaml
# prometheus --agent --config.file=agent.yml --storage.agent.path=/data
#   --storage.agent.retention.max-time=6h   # survive a 6h backend outage without loss
global:
  scrape_interval: 30s
  external_labels: {cluster: edge-store-0421, __replica__: a}
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ["localhost:9100"]
remote_write:
  - url: https://mimir.example.internal/api/v1/push
    protobuf_message: io.prometheus.write.v2.Request
    queue_config: {max_shards: 20, retry_on_http_429: true}
```

### 2.3 Remote-write and scrape health rules

```yaml
groups:
  - name: remote-write.alerts
    rules:
      - alert: RemoteWriteBehind
        expr: |
          (
            max by (instance, remote_name) (prometheus_remote_storage_queue_highest_timestamp_seconds)
            - max by (instance, remote_name) (prometheus_remote_storage_queue_highest_sent_timestamp_seconds)
          ) > 120
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }} -> {{ $labels.remote_name }} is {{ $value | humanizeDuration }} behind; data is lost once the WAL truncates past it"
      - alert: RemoteWriteShardsMaxed
        expr: |
          max by (instance, remote_name) (prometheus_remote_storage_shards_desired)
            > max by (instance, remote_name) (prometheus_remote_storage_shards_max)
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "Desired shards exceed max_shards; throughput is capped at max_shards x max_samples_per_send / latency"
      - alert: RemoteWriteDroppingSamples
        expr: |
          sum by (instance, remote_name) (rate(prometheus_remote_storage_samples_failed_total[5m])
            + rate(prometheus_remote_storage_samples_dropped_total[5m])) > 0
        for: 10m
        labels: {severity: critical}
        annotations:
          summary: "Samples are failing/dropping on the way to {{ $labels.remote_name }} (4xx, 429 without retry, or sample_age_limit)"
  - name: scrape.alerts
    rules:
      - alert: ScrapeDurationNearTimeout
        expr: |
          max by (job, instance) (scrape_duration_seconds)
            > 0.8 * max by (job, instance) (scrape_timeout_seconds)
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.job }}/{{ $labels.instance }} scrape takes >80% of scrape_timeout (needs extra_scrape_metrics)"
      - alert: TargetsDroppedByLimit
        expr: increase(prometheus_target_scrape_pool_exceeded_target_limit_total[15m]) > 0
        labels: {severity: critical}
        annotations:
          summary: "A scrape pool exceeded target_limit; ALL its targets are failing"
```

### 2.4 Minimal RW2 sender (stdlib Python)

L7 contains a complete encoder. The 25-line core below is what a custom exporter or load generator needs. It sends literal-only snappy, which is valid snappy that any decoder accepts.

```python
import struct
import urllib.request


def uv(x):
    out = bytearray()
    while x >= 0x80:
        out.append((x & 0x7F) | 0x80)
        x >>= 7
    return bytes(out + bytes([x]))


def ld(field, payload):
    return uv(field << 3 | 2) + uv(len(payload)) + payload


def snappy_literal(raw):  # valid snappy block: preamble + literal chunks of <= 65536 bytes
    out = bytearray(uv(len(raw)))
    for i in range(0, len(raw), 65536):
        chunk = raw[i:i + 65536]
        n = len(chunk) - 1
        out += (bytes([n << 2]) if n < 60 else bytes([61 << 2]) + n.to_bytes(2, "little")) + chunk
    return bytes(out)


def push(url, labels, value, ts_ms):
    symbols = [""] + [s for kv in sorted(labels.items()) for s in kv]
    refs = b"".join(uv(i) for i in range(1, len(symbols)))
    sample = uv(1 << 3 | 1) + struct.pack("<d", value) + uv(2 << 3) + uv(ts_ms)
    body = b"".join(ld(4, s.encode()) for s in symbols) + ld(5, ld(1, refs) + ld(2, sample))
    req = urllib.request.Request(url, data=snappy_literal(body), method="POST", headers={
        "Content-Type": "application/x-protobuf;proto=io.prometheus.write.v2.Request",
        "Content-Encoding": "snappy", "X-Prometheus-Remote-Write-Version": "2.0.0"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status, r.headers.get("X-Prometheus-Remote-Write-Samples-Written")
```

---

## 3. Failure modes and FinOps debugging

### F1. The `$1_suffix` relabel rule that silently empties a label

**Symptom.** After a relabel change, a label such as `service` is missing on all series of a job, or a target's `__address__` becomes just `:9090`.

**Signature.** The `/targets` page and `/api/v1/targets/relabel_steps` (3.10 computes the steps in a single pass) show the rule producing `""` and deleting the label. The config contains `replacement: $1_svc` or `$1-$2x`-style templates.

**Root cause.** Go's `Expand` reads the **longest** `[A-Za-z0-9_]` run after `$` as the group name. `$1_svc` refers to a group named `1_svc`, which does not exist, so the result is empty, and an empty replacement **deletes** the target label (L6 §2).

**Fix.** Use braces: `${1}_svc`.

**Prevention.**
- Lint relabel configs for `\$\d+[A-Za-z_]`.
- Unit-test relabel rules against fixtures with a port like L6, or with Prometheus's relabel-steps API in CI against a throwaway server.

### F2. Re-sharding a hashmod fleet doubles series for a day

**Symptom.** Going from 4 to 6 shards, total head series across shards jump ~1.7×, and the remote store's active series spike. Some panels show double lines.

**Signature.** On every shard, `prometheus_tsdb_head_series` steps up, then decays over ~3 h. `count by (__name__)` in the long-term store briefly exceeds the expected value. A lagging config rollout means two shards temporarily own the same target.

**Root cause.**
- `hashmod` with a new modulus reassigns about 1 − 1/N of targets (~83% for 4 → 6). Their series are *new* to the receiving shard (churn).
- The old shard keeps stale copies until head GC.
- During a staggered rollout, some targets are scraped by two shards with different `shard` external labels. Downstream, those are distinct series.

**Fix.** Roll out modulus changes atomically (all shards' config at once), and do not put `shard` in external labels that become series labels downstream.

**Prevention.**
- Size shards with headroom, so modulus changes are rare.
- Prefer consistent-hash target assignment (an operator with a hash ring, or Alloy clustering, Folder 06) where re-sharding is frequent.

### F3. Rate-limited remote write silently drops data

**Symptom.** After the vendor or Mimir tenant hits its ingestion limit, gaps appear in the long-term store, but Prometheus never reports backpressure.

**Signature.** The receiver returns 429. `prometheus_remote_storage_samples_failed_total` increases while `samples_retried_total` does not. The lag metric stays near zero, because data is being dropped, not queued.

**Root cause.** `queue_config.retry_on_http_429` defaults to **false** (and is documented as experimental). A 429 is then handled like any other 4xx: non-recoverable, so the batch is dropped (L7 §3).

**Fix.** Set `retry_on_http_429: true`, so `Retry-After` is honoured with backoff. Raise the tenant limit, or reduce volume with `write_relabel_configs`.

**Prevention.**
- Alert on `samples_failed_total` and `samples_dropped_total` (§2.3).
- Capacity-plan tenant limits from `rate(prometheus_remote_storage_samples_total[5m])` with 2× headroom.

### F4. Remote write falls behind, then loses data at the next head compaction

**Symptom.** During a backend latency incident, dashboards on the long-term store go stale. After recovery there is a permanent hole of 30–90 minutes.

**Signature.**
- The queue-highest minus sent-timestamp lag grows past 1 h.
- `prometheus_remote_storage_shards` equals `shards_max`.
- Compaction runs, then `prometheus_remote_storage_samples_dropped_total` jumps (or the WAL watcher logs that it skipped segments).

**Root cause.**
- Throughput is capped at `max_shards × max_samples_per_send / latency` (L7: 50 × 2,000 / 2 s = 50k/s < 66.7k/s).
- The WAL watcher reads from WAL segments that head compaction deletes regardless of remote-write progress (File 01 §1.9). Lag beyond the retained WAL becomes loss.

**Fix.**
- Raise `max_shards`, which needs receiver capacity, to bound lag (L7: 200 shards → 9 s).
- Use `sample_age_limit` to stop replaying very old data into a recovering backend.
- For edge clusters, use Agent mode with `retention.max-time` covering the longest expected outage.

**Prevention.** Alert on lag over 2 minutes and on desired shards above max. Load-test the backend at 2× peak with injected latency.

### F5. Scrapes time out on large targets, and alerts fire for healthy services

**Symptom.** `up == 0` flaps for kube-state-metrics, cAdvisor or a fat exporter. The service is fine.

**Signature.** `scrape_duration_seconds` is close to `scrape_timeout_seconds` (needs `extra_scrape_metrics`). The target error is "context deadline exceeded". Body size is tens of MB (`scrape_body_size_bytes`).

**Root cause.** `scrape_timeout` (default 10 s, ≤ interval) bounds the whole GET + parse. The usual causes:
- huge expositions (KSM in large clusters, cAdvisor with many containers);
- a slow exporter that computes on scrape;
- a CPU-starved Prometheus.

A timed-out scrape drops everything, and the staleness markers make every series vanish.

**Fix.**
- Shard the exporter (KSM `--shard`/`--total-shards`), drop families at the exporter side (KSM `--metric-allowlist`), or raise `scrape_timeout` toward the interval.
- Enable `zstd-scrape` or ensure gzip.

**Prevention.** Alert at 80% of the timeout (§2.3), and track `scrape_body_size_bytes` growth per job.

### F6. Federation or `honor_timestamps` hides staleness

**Symptom.** A global Prometheus federating from leaf servers keeps showing values for pods that died minutes ago. Alerts on `absent()` fire late.

**Signature.** The federated series carry explicit timestamps from the leaf. With `honor_timestamps: true` (the default), the global server writes **no staleness markers** for them, so values persist for the 5-minute lookback.

**Root cause.** Prometheus only writes staleness markers for series it timestamps itself, unless `track_timestamps_staleness: true` is set (added for exactly this case).

**Fix.** Set `track_timestamps_staleness: true` on federation jobs. Better still, replace federation with remote write to a global store and query that (Folder 06).

**Prevention.** Federate only aggregated recording-rule series (`match[]={__name__=~"job:.*"}`), never raw series.

### F7. A service-discovery explosion takes down a scrape pool

**Symptom.** A misconfigured namespace with thousands of Jobs or CronJob pods causes every target in that job to show as failed.

**Signature.**
- `prometheus_target_scrape_pool_exceeded_target_limit_total` increments.
- The UI shows the pool in an error state.
- Discovery metrics (`prometheus_sd_discovered_targets`) spike.

**Root cause.** `target_limit` is enforced after relabeling. Exceeding it marks **all** targets of the pool as failed, to protect the server. Without a limit, the same explosion would instead create a cardinality spike.

**Fix.** Narrow discovery with `selectors` or a `namespaces` filter, and `keep` only annotated pods. Raise the limit only with evidence.

**Prevention.** Keep one scrape config per workload class, so a blast radius stays local, and alert on target-limit breaches (§2.3).

### F8. OTLP resource attribute promotion multiplies series

**Symptom.** After enabling `promote_all_resource_attributes: true` on the OTLP receiver, head series grow 3–5× and churn spikes on every deploy.

**Signature.** Series now carry `k8s_pod_uid`, `process_pid`, `host_id`, `container_id` and similar labels. `labelValueCountByLabelName` shows these at the top.

**Root cause.** Promoted attributes become series labels. Attributes that change per process start (PIDs, pod UIDs, container IDs) make every restart a new series. File 02's churn law applies.

**Fix.** Promote an explicit allowlist (`k8s.namespace.name`, `k8s.deployment.name`, `deployment.environment.name`). Leave the rest in `target_info` and join on demand with `info()` (experimental) or `group_left`.

**Prevention.** Review the OTLP translation config as a schema decision, and watch `prometheus_api_otlp_translation_warnings_total`.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Explain relabel_configs vs metric_relabel_configs vs write_relabel_configs."</b></summary>

**Initial Prompt.** Where should I drop a noisy label?

**L5 Textbook Answer.** `relabel_configs` is for targets and `metric_relabel_configs` is for metrics. Drop it in `metric_relabel_configs`.

**Why L5 Fails at 3 AM or on the Bill.** It ignores cost and semantics:
- metric relabeling runs per *sample* on every scrape (CPU);
- dropping a distinguishing label can *merge* series into duplicates that are rejected;
- write relabeling only affects the remote copy, so local memory is not saved.

The right stage depends on whether the label is on the target or the sample, and whether the goal is memory, network or both.

**L7 Principal Defense.**
1. Target labels (from SD) are dropped in `relabel_configs`: zero per-sample cost, applies to all series of the target.
2. Exposed labels that are unbounded are fixed at the instrumentation. Until then, use `metric_relabel_configs` `labeldrop` only if no two series differ solely by that label; otherwise drop the family or aggregate with a recording rule.
3. Long-term cost is controlled with `write_relabel_configs` that ship aggregates and an allowlist.
4. Each stage is verified with the relabel-steps API, plus fixture tests for template traps like `$1_suffix`.
</details>

<details><summary><b>Q2 · "How would you scale scraping to 50,000 targets?"</b></summary>

**Initial Prompt.** One Prometheus can't keep up with 50k pods. Design the collection tier.

**L5 Textbook Answer.** Use federation: several Prometheus servers scrape subsets, and a global one federates from them.

**Why L5 Fails at 3 AM or on the Bill.**
- Federation re-scrapes raw series into a single server, recreating the bottleneck.
- It loses staleness unless configured carefully.
- It doubles storage.
- It does not say how targets are split, or how to survive a shard loss.

**L7 Principal Defense.**
1. Shard by `hashmod(__address__)` across N HA pairs, with each replica keeping only its shard after cheap `keep` rules. Or use an operator or Alloy clustering with consistent hashing to make re-sharding cheaper.
2. Size N from series per shard (≤ 2–4 M head series at the churn peak) and scrape CPU.
3. Each shard remote-writes RW2 to a horizontally scalable store (Mimir/Thanos) that dedupes HA replicas.
4. Global queries go to the store, not to a federating Prometheus.
5. SD load is controlled with selectors.
6. Guard rails: target limits per pool and sample limits per job.
</details>

<details><summary><b>Q3 · "What does Remote Write 2.0 change and should we adopt it?"</b></summary>

**Initial Prompt.** Our vendor supports RW2. Worth switching?

**L5 Textbook Answer.** Yes, it is more efficient because of string interning.

**Why L5 Fails at 3 AM or on the Bill.** "More efficient" has no number and no risk analysis. The proto in v3.15.1 is still marked rc.4, receivers differ in which optional features (exemplars, native histograms, start timestamps) they store, and a misconfigured receiver might parse a v1 payload as v2 into an *empty request* that it then acknowledges.

**L7 Principal Defense.**
1. Measured on a realistic batch: RW2 is 0.23× raw and ~0.72× after snappy, while also carrying inline metadata, start timestamps and written-count response headers (L7).
2. Adoption plan:
   - confirm the receiver advertises RW2 (content-type negotiation);
   - canary one shard with `protobuf_message: io.prometheus.write.v2.Request`;
   - compare `prometheus_remote_storage_samples_total` against the receiver's `X-Prometheus-Remote-Write-Samples-Written` counts and the store's ingested-samples metrics;
   - then roll out.
3. Cost win: ~25–30% less egress at the same sample rate. The real prize is semantic: metadata and start timestamps arrive with the data.
</details>

<details><summary><b>Q4 · "The long-term store has gaps but Prometheus looks healthy. Debug."</b></summary>

**Initial Prompt.** Local Prometheus has the data, Mimir doesn't. Where do you look?

**L5 Textbook Answer.** Check the remote-write error logs and the network. Maybe increase the timeout.

**Why L5 Fails at 3 AM or on the Bill.** It does not separate the three loss modes:
- dropped batches: 4xx and 429 without retry;
- lag past WAL truncation;
- filtering: `write_relabel_configs`, `sample_age_limit`, `send_native_histograms: false`.

Each has a different fix and a different metric. "Increase the timeout" fixes none of them.

**L7 Principal Defense.**
1. `samples_failed_total` / `samples_dropped_total` by `remote_name`. A non-zero failure rate with near-zero lag means drops: check the receiver's 4xx and 429 responses and `retry_on_http_429`.
2. Lag (`queue_highest_timestamp − queue_highest_sent_timestamp`) and `shards` vs `shards_max`. Lag that crossed a compaction boundary means WAL-truncation loss.
3. If only some families are missing, check `write_relabel_configs`. If native histograms are missing, check `send_native_histograms`. If only old data is missing, check `sample_age_limit`.
4. Then the receiver's own limits (per-tenant series and samples).

The fix comes from whichever metric moved.
</details>

<details><summary><b>Q5 · "Why does Prometheus spread scrapes instead of scraping everything on the minute?"</b></summary>

**Initial Prompt.** Could we align all scrapes to :00 so dashboards line up nicely?

**L5 Textbook Answer.** Prometheus randomizes scrapes to spread load; aligning them would overload the server.

**Why L5 Fails at 3 AM or on the Bill.** It is directionally right but misses that the offset is *deterministic*: a hash of target labels and URL XOR a server seed, mod the interval. So it is stable across restarts (good for `rate()`), it changes when labels change, and two HA replicas scrape the same target at *different* phases (different seeds). Their values differ slightly, which is why HA dedupe is done per series, not by comparing samples.

**L7 Principal Defense.**
1. A thundering herd on targets and on the server's ingest is avoided by the hash offset. Within each target's phase, timestamps are snapped to a 2 ms-tolerant grid for compression (File 01).
2. Dashboard alignment is a *query* concern: step-aligned range queries with `rate()` windows ≥ 4 × interval.
3. HA replicas being out of phase is a feature: one replica's scrape failure is covered by the other's.
4. Aligning scrapes would trade correctness and robustness for cosmetics.
</details>

<details><summary><b>Q6 · "OTLP straight into Prometheus, or through a collector?"</b></summary>

**Initial Prompt.** Prometheus 3 has an OTLP endpoint. Can our 2,000 services push directly to it?

**L5 Textbook Answer.** Yes. Prometheus 3 supports OTLP natively, so the collector is unnecessary.

**Why L5 Fails at 3 AM or on the Bill.**
- The docs call the receiver "not … an efficient way of ingesting samples" for anything but low-volume use.
- Direct push concentrates retries, out-of-order data and translation cost on the TSDB.
- Push loses `up`-based target health.
- Promoting resource attributes without a policy multiplies series (F8).

**L7 Principal Defense.**
1. Services push OTLP to a local OTel Collector or Alloy (agent or gateway) that batches, does delta→cumulative, filters attributes, and remote-writes RW2 to Mimir (Folder 06).
2. Prometheus's OTLP receiver is for small or edge cases, with `out_of_order_time_window` sized from `prometheus_tsdb_sample_ooo_delta`.
3. The translation policy is explicit:
   - `UnderscoreEscapingWithSuffixes` until all consumers are UTF-8 ready;
   - an allowlist for promoted resource attributes;
   - `convert_histograms_to_nhcb: true`.
4. Health comes from collector self-metrics, since push has no `up`.
</details>

<details><summary><b>Q7 · "Design HA for Prometheus without double-counting."</b></summary>

**Initial Prompt.** We want two replicas for availability, but sums double in Grafana.

**L5 Textbook Answer.** Query only one replica, or put a load balancer in front and pick one.

**Why L5 Fails at 3 AM or on the Bill.** A load balancer flips between replicas whose samples differ by phase, which produces jagged graphs and `rate()` artifacts. Querying "one replica" loses the availability benefit, and alerts still fire twice unless Alertmanager dedupes.

**L7 Principal Defense.**
1. Both replicas scrape identically and carry `external_labels: {__replica__: a|b}`.
2. Remote write to Mimir with the HA tracker, which accepts one replica per cluster at a time and fails over on silence. Or Thanos Query with `--query.replica-label` dedupe.
3. Alerts are evaluated on both, sent to all Alertmanagers, and deduplicated by label identity after `alert_relabel_configs` drops `__replica__` (Folder 04).
4. Restarts are staggered with a PodDisruptionBudget.
5. Grafana points at the deduplicating query layer, never at an individual replica.
</details>

<details><summary><b>Q8 · "How do you test relabel configs before they hit production?"</b></summary>

**Initial Prompt.** A relabel change dropped half our targets last quarter. How do we prevent that?

**L5 Textbook Answer.** Review the YAML carefully and use `promtool check config`.

**Why L5 Fails at 3 AM or on the Bill.** `promtool check config` validates syntax, not semantics. The `$1_suffix` template bug, a `keep` on the wrong annotation, or a regex that now matches more (anchoring is implicit) all pass validation.

**L7 Principal Defense.**
1. Golden tests. Feed recorded SD target groups (or `/api/v1/targets?state=any` snapshots) through the candidate config in CI, using Prometheus itself in a throwaway container or a faithful port like L6, which passes Prometheus's own test vectors. Then diff the resulting target sets and label sets.
2. Lint for template traps (`\$\d+[A-Za-z_]`), unanchored-intent regexes, and `labeldrop` on distinguishing labels.
3. Canary the config on one shard and compare the target count and `scrape_series_added` before fleet rollout.
4. Keep `keep_dropped_targets` > 0, so dropped targets remain inspectable in the UI.
</details>

---

## 5. Invariants checklist

- [ ] Relabel templates use `${n}` whenever the group reference is followed by `[A-Za-z0-9_]`. CI lints for `\$\d+[A-Za-z_]`.
- [ ] Target-level labels are dropped in `relabel_configs`; sample-level labels are dropped at the instrumentation (or in metric relabeling only when it cannot merge series).
- [ ] Sharding uses `hashmod` on a stable key, applied *before* expensive relabel rules. Modulus changes roll out atomically.
- [ ] Every `remote_write` sets `retry_on_http_429`, `max_shards` (sized for 2× peak at degraded latency), `send_native_histograms` and a `sample_age_limit` explicitly.
- [ ] Remote-write lag, shards-at-max and failed/dropped samples are alerted. Lag is kept far below the WAL retention window (~1 h minimum).
- [ ] RW2 is adopted after a canary that reconciles sent vs written counts.
- [ ] OTLP ingestion goes through a collector at scale. Resource-attribute promotion is an allowlist, and the translation strategy has an owner.
- [ ] Federation, if any, ships only recording-rule aggregates, with `track_timestamps_staleness: true`.
- [ ] `target_limit` / `sample_limit` breaches page the owning team with "limit exceeded" text, not "target down".

---

## 6. References

- Relabel engine: <https://github.com/prometheus/prometheus/blob/v3.15.1/model/relabel/relabel.go> and tests <https://github.com/prometheus/prometheus/blob/v3.15.1/model/relabel/relabel_test.go>
- Configuration reference (`<relabel_config>`, `<scrape_config>`, `<remote_write>`, `otlp:`): <https://prometheus.io/docs/prometheus/latest/configuration/configuration/>
- Remote Write 2.0 specification: <https://prometheus.io/docs/specs/prw/remote_write_spec_2_0/>
- Remote Write 2.0 proto (v2.0-rc.4 in v3.15.1): <https://github.com/prometheus/prometheus/blob/v3.15.1/prompb/io/prometheus/write/v2/types.proto>
- Queue manager and shard autoscaling: <https://github.com/prometheus/prometheus/blob/v3.15.1/storage/remote/queue_manager.go>
- Remote-write client (retry and 429 handling): <https://github.com/prometheus/prometheus/blob/v3.15.1/storage/remote/client.go>
- Scrape loop (staleness, alignment, report series): <https://github.com/prometheus/prometheus/blob/v3.15.1/scrape/scrape.go>
- Target offset hashing: <https://github.com/prometheus/prometheus/blob/v3.15.1/scrape/target.go>
- HTTP API: remote-write and OTLP receivers, relabel steps: <https://prometheus.io/docs/prometheus/latest/querying/api/>
- Prometheus Agent mode: <https://prometheus.io/docs/prometheus/latest/prometheus_agent/>
- Using Prometheus as an OpenTelemetry backend: <https://prometheus.io/docs/guides/opentelemetry/>
- Remote write tuning: <https://prometheus.io/docs/practices/remote_write/>
- Go `regexp.Expand` semantics: <https://pkg.go.dev/regexp#Regexp.Expand>
