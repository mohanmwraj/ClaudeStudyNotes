# 01 · Instant vs Range Vectors, rate() vs irate() Extrapolation and Counter Resets

> **Folder 02 — PromQL Deep Dive and Mathematical Mechanics · File 1 of 3.**
> Pinned to **Prometheus v3.15.1** (`promql/engine.go`, `promql/functions.go`, `promql/quantile.go` read at tag `v3.15.1`).
> Labels: **[D]** documented / read in pinned source · **[M]** measured by a listing here (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `promql_mini.py` | A stdlib PromQL engine (parser + evaluator for float samples: selectors, offsets, subqueries, 40+ functions, aggregations, vector matching, set operators, classic `histogram_quantile`/`histogram_fraction`) and a runner for Prometheus's own **promqltest** scripts. It passes **every attempted case** of 9 upstream test files; native-histogram, `@`, experimental-function and error-expecting cases are counted as SKIP with reasons | ~1 s |
| L2 `rate_math_lab.py` | The arithmetic of `rate`/`increase`/`irate`/`delta`: a worked extrapolation, non-integer increases, reset correction, half-spacing and zero-point clamps, a Monte Carlo of bias/RMSE vs window length, irate vs rate on a burst, and rate() on a gauge | ~1 s |

**Verification.** L1's oracle is Prometheus's own test corpus. The `.test` files in `fixtures/promqltest-v3.15.1/` are copied verbatim from `promql/promqltest/testdata/` at tag v3.15.1 (Apache-2.0), and L1 evaluates each `eval instant`/`eval range` block against the expected samples using the same `almost.Equal` tolerance (1e-6 relative). A case is PASS only if parsing and evaluation are fully supported and every expected series matches; anything else is SKIP with a stated reason, never PASS. L2 builds on L1's `extrapolatedRate`/`instantValue` ports, so its numbers inherit that validation. No live Prometheus server was run.

---

## 0. Orientation

**What this file answers.** What exactly a PromQL expression *returns* at time T; why `rate(x[1m])` can be empty, non-integer, or a "spike" after a deploy; how extrapolation works sample by sample; and how to pick windows and functions so dashboards and alerts are correct by construction.

**The four value types [D].** *Scalar* (a float), *string*, *instant vector* (a set of series, one sample each, all stamped with the evaluation time) and *range vector* (a set of series, each with the samples inside a window). Functions are typed: `rate()` takes a range vector and returns an instant vector; `histogram_quantile()` takes an instant vector; a range vector can never be graphed directly.

**Two evaluation modes.** An *instant query* evaluates once at T. A *range query* (what Grafana issues) is the instant query evaluated independently at `start, start+step, …, end` — there is no "range-aware" evaluation, which is the root of most dashboard surprises (aliasing, `topk` flapping, step-dependent results).

**What changed in 3.x that matters here [D].** Range selectors and the lookback window are **left-open**: `x[5m]` at T selects samples with `T−5m < t ≤ T` (2.x included `t = T−5m`); experimental `anchored`/`smoothed` range-selector modifiers (`--enable-feature=promql-extended-range-selectors`); start-timestamp-aware `rate`/`increase` (`use-start-timestamps`, 3.12+); duration expressions are on by default (3.14); `first_over_time` is stable (3.14).

---

## 1. First principles: selection, then arithmetic

### 1.1 Instant selection, lookback and staleness

```text
 samples of x:   ●──────●──────●──────●──────●                  ●(stale marker)
 time (s):       0     15     30     45     60          ...     75
                                           ▲ T=60: newest sample in (T-5m, T]  → value at t=60
 query at T=70:  newest sample in (70s-5m, 70s] is t=60  → returned, stamped T=70 (not 60!)
 query at T=80:  newest sample is the STALE MARKER at 75 → series ABSENT (no 5-minute ghost)
 without a marker (target vanished without one, or honor_timestamps): the value at t=60 is
 returned for every T in (60s, 60s+5m] — the "ghost" that makes dead pods linger on dashboards
```

- `--query.lookback-delta` (default **5m**) bounds how far back an instant selector looks. It is a *query-time* parameter; setting it below 2× the scrape interval makes every missed scrape a gap.
- A staleness marker (`StaleNaN`, bit pattern `0x7ff0000000000002`) is written by the scrape loop when a series disappears from a target or the target disappears (Folder 01 File 04). The instant selector treats it as "no value from here on"; range selectors drop it from the window.
- The returned sample's timestamp is the **evaluation time**, not the sample's time. `timestamp(x)` recovers the real sample time (L1 implements both).

### 1.2 Range selection

`x[r] offset o` at T selects samples with `T − o − r < t ≤ T − o`, excluding staleness markers. At a 15 s scrape interval, `[1m]` therefore holds **4** samples on an aligned grid (not 5 as in 2.x), `[30s]` holds 2, and `[15s]` holds 1 — which yields **nothing** for `rate()` (it needs two). That single fact explains most "my rate panel is empty" tickets.

### 1.3 `rate()` and `increase()`: the extrapolation algorithm

`extrapolatedRate()` in `promql/functions.go`, for the float path [D] (L1 ports it; L2 §1 walks it):

```text
 window (T-r, T]       first sample t₁ ... last sample tₙ   (n ≥ 2, else: no output)
 raw   Δ  = vₙ − v₁ + Σ_{i: vᵢ < vᵢ₋₁} vᵢ₋₁                     (counters: add pre-reset value)
 sampled  = tₙ − t₁ ;  avg = sampled / (n−1) ;  thr = 1.1 · avg
 toStart  = t₁ − (T−r) ;  toEnd = T − tₙ
 if toStart ≥ thr: toStart = avg/2           (series probably started inside the window)
 if counter and Δ > 0 and v₁ ≥ 0:
     toZero = sampled · v₁/Δ ;  toStart = min(toStart, toZero)   (never extrapolate below 0)
 if toEnd ≥ thr:   toEnd = avg/2             (series probably ended inside the window)
 increase = Δ · (sampled + toStart + toEnd) / sampled
 rate     = increase / r(seconds)            delta() = same, without reset handling/zero clamp
```

Read it as: *assume samples are regular; if the window edges are within ~one spacing of real samples, extend the observed slope to the edges; otherwise assume the series starts or stops half a spacing beyond the last sample we saw.*

L2 §1 at 15 s scrapes, +30 per scrape: 4 samples, Δ = 90 over 45 s, both gaps < 16.5 s → `increase = 90 × 60/45 = 120`, `rate = 2.0/s` exactly. Consequences that surprise people [M]:

- **`increase()` of an integer counter is not an integer** whenever the sampled interval does not divide the window: `increase(x[50s])` of a +1/scrape counter = **3.333**; with 0–400 ms scrape jitter even `[1m]` gives 4.0217 / 3.9861. It is an *estimate of the rate × window*, not a count. For exact integer counts use `increase(x[5m] anchored)` (experimental) or count events in logs.
- **Resets are corrected by adding the pre-reset value.** `110, 5, 15` → Δ = 15 − 110 + 110 = 15. Any decrease is a reset — which is why `rate()` on a gauge produces positive garbage (L2 §6: `+1.43/s` for a draining queue whose true slope is `−0.61/s`).
- **A series born inside the window** is extrapolated only half a spacing back (3, 6, 9 → 7.5 not 12), and **never below zero** (1, 11, 21 → 21, the counter's own value: it has counted from zero 1.5 s earlier).

### 1.4 How accurate is `increase()`? (L2 §4)

Monte Carlo over 1,500 random windows of a Poisson(2/s) counter scraped every 15 s with up to 400 ms jitter [M]:

| Window | Scrape intervals | Bias | RMSE | RMSE % of mean | Empty results |
|---|---|---|---|---|---|
| 30 s | 2 | −0.15 | 7.7 | **12.8%** | 0.4% |
| 45 s | 3 | −0.14 | 6.5 | 7.2% | 0% |
| 1 m | 4 | −0.08 | 6.3 | 5.3% | 0% |
| 2 m | 8 | −0.04 | 5.8 | 2.4% | 0% |
| 5 m | 20 | +0.43 | 5.7 | **0.9%** | 0% |

`rate()` is essentially **unbiased**; its error is dominated by edge effects of size ≈ one scrape interval's worth of events, so relative error falls ~1/window. The operational rules that follow:

- **Window ≥ 4 × scrape interval.** Below 2 intervals results vanish; at 2 they are noisy (13%); at 4 they are usable (5%). Grafana's `$__rate_interval` encodes this: `max($__interval + scrape_interval, 4 × scrape_interval)` [D, Grafana docs].
- **Alerting windows** should be the *longest* tolerable for detection latency (5 m+), and dashboards the shortest that keeps error under ~5%.
- **Changing the scrape interval** silently breaks every hard-coded `[1m]` window — a fleet moving from 15 s to 60 s turns `[1m]` panels empty.

### 1.5 `irate()`, `idelta()` and why alerts should not use them

`irate(x[r])` uses only the **last two samples** in the window (`instantValue`): `(v₂ − v₁)/(t₂ − t₁)`, or `v₂/(t₂ − t₁)` after a reset. The range only bounds how far back to look for those two samples. L2 §5 shows a 30-second burst of +200/s on a +2/s counter [M]:

| T | `rate(x[5m])` | `irate(x[5m])` | `rate(x[1m])` |
|---|---|---|---|
| burst+0 | 12.4 | **200.0** | 65.0 |
| burst+15 s | 22.8 | 200.0 | 115.0 |
| burst+30 s | 22.8 | **2.0** | 115.5 |
| +5 min | 2.0 | 2.0 | 2.0 |

`irate` is exact about the last interval and **forgets everything else**: a burst that ends between two dashboard steps is invisible at most zoom levels, and an alert on `irate` flaps with every scrape. Use `irate` for high-resolution "what is happening right now" panels; use `rate` for anything aggregated, recorded or alerted on.

### 1.6 Gauges: `delta`, `deriv`, `predict_linear`

- `delta(g[r])` — extrapolated difference, no reset logic (same edge rules as `increase`).
- `deriv(g[r])` — least-squares slope (Kahan-compensated sums of x, y, xy, x²; a constant series returns slope 0 exactly) [D].
- `predict_linear(g[r], s)` — the regression line evaluated `s` seconds after T (intercept is computed at T). The canonical disk-full alert: `predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0`.
- `resets()` / `changes()` — counts of decreases / value changes (NaN→NaN is not a change).

### 1.7 Experimental: start timestamps, `anchored`, `smoothed` (⚠ 3.12–3.15)

- With `--enable-feature=use-start-timestamps` (and ST ingestion via protobuf or `st-storage`), `rate`/`increase` use the counter's **start timestamp** instead of extrapolating to the left when the start lies inside the window — removing the "first scrape after restart is lost" error.
- `x[5m] anchored` (with `--enable-feature=promql-extended-range-selectors`) takes the last sample *before* the window as the left anchor and does **no extrapolation**: `increase` returns integers. `x[5m] smoothed` linearly interpolates at both boundaries using samples outside the window — accurate, but it needs a sample *after* T, so recording/alerting rules must set `query_offset` ≥ one scrape interval or they under-estimate.

### 1.8 The engine and Prometheus's own test corpus (L1)

L1 is the reference implementation the rest of Folder 02 uses. Running it over the nine upstream files evaluates every `eval instant` and `eval range` case it can parse and evaluate and compares with the expected samples. The output below is regenerated by the gate; **0 failures** is the bar, and every skipped case is attributed (native-histogram literals, `@`, experimental duration functions such as `step()`/`range()`/`min_of()`, `sort_by_label`, RE2-only regex syntax, and cases that *expect* an error).

<!-- listing:promql_mini.py -->
```python
"""promql_mini.py - a stdlib PromQL subset engine (float samples) ported from Prometheus v3.15.1,
checked against Prometheus's own promqltest scripts.

Semantics ported from promql/{engine.go, functions.go, quantile.go} at tag v3.15.1:
  * instant selection: newest sample in (T - 5m lookback, T]; a staleness marker hides the series;
    range selection: samples in (T - range, T] (3.x left-open), staleness markers excluded;
  * rate/increase/delta: extrapolatedRate (extrapolate to the window edge if the gap is < 1.1x
    the average sample spacing, else by half a spacing; counters never extrapolate below zero);
  * irate/idelta from the last two samples; deriv/predict_linear by Kahan least squares;
  * *_over_time, aggregations with Kahan/Neumaier summation and direct-then-incremental means;
  * binary operators with on/ignoring/group_left/group_right, bool, and/or/unless; resultMetric;
  * subqueries on the absolute step grid: first step strictly after T - offset - range;
  * classic histogram_quantile (coalesce buckets, force monotonicity, +Inf rule).
Unsupported (reported as SKIP, never as PASS): native histograms, @ modifier, duration
expressions, info(), limitk/limit_ratio, experimental functions, smoothed/anchored selectors.

Usage: python promql_mini.py <target.md>   (runs fixtures/promqltest-v3.15.1/*.test next to it)
"""
import math
import pathlib
import re
import struct
import sys

LOOKBACK = 5 * 60 * 1000
STALE = struct.unpack(">d", struct.pack(">Q", 0x7FF0000000000002))[0]
UNITS = {"ms": 1, "s": 1000, "m": 60000, "h": 3600000, "d": 86400000, "w": 604800000, "y": 31536000000}


class Unsupported(Exception):
    pass


class EvalError(Exception):
    pass


_RX = {}


def rx(pattern):
    """Prometheus anchors matcher regexes as ^(?s:...)$; RE2-only syntax is reported as SKIP."""
    if pattern not in _RX:
        try:
            _RX[pattern] = re.compile(pattern, re.S)
        except re.error as e:
            raise Unsupported("RE2-only regex syntax") from e
    return _RX[pattern]


def is_stale(v):
    return struct.pack(">d", v) == struct.pack(">Q", 0x7FF0000000000002)


def parse_duration(s):
    if re.fullmatch(r"\d+(\.\d+)?", s):
        return int(round(float(s) * 1000))
    parts = re.findall(r"(\d+)(ms|s|m|h|d|w|y)", s)
    if not parts or "".join(a + b for a, b in parts) != s:
        raise Unsupported(f"duration {s!r}")
    return sum(int(a) * UNITS[b] for a, b in parts)


# ----------------------------------------------------------------------------- lexer
TOKEN_RE = re.compile(r"""
 (?P<ws>\s+|\#[^\n]*)
|(?P<dur>\d+(?:ms|[smhdwy])(?:\d+(?:ms|[smhdwy]))*(?![\w]))
|(?P<num>0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)
|(?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`]*`)
|(?P<id>[a-zA-Z_][a-zA-Z0-9_:]*|:[a-zA-Z_][a-zA-Z0-9_:]*)
|(?P<op>==|!=|<=|>=|=~|!~|[-+*/%^<>=(){}\[\],:@])
""", re.X)


def lex(src):
    out, pos = [], 0
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise Unsupported(f"lex error at {src[pos:pos + 10]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        val = m.group()
        if kind == "id" and val.lower() in KEYWORDS:  # PromQL keywords are case-insensitive
            val = val.lower()
        out.append((kind, val))
    out.append(("eof", ""))
    return out


def unquote(s):
    if s[0] == "`":
        return s[1:-1]
    body = s[1:-1]
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}.get(m.group(1), "\\" + m.group(1)), body)


KEYWORDS = {"by", "without", "on", "ignoring", "group_left", "group_right", "bool", "offset", "and", "or",
            "unless", "atan2", "sum", "avg", "count", "min", "max", "group", "stddev", "stdvar", "topk", "bottomk",
            "quantile", "count_values", "limitk", "limit_ratio"}
AGGS = {"sum", "avg", "count", "min", "max", "group", "stddev", "stdvar", "topk", "bottomk", "quantile", "count_values",
        "limitk", "limit_ratio"}
PREC = {"or": 1, "and": 2, "unless": 2, "==": 3, "!=": 3, "<=": 3, "<": 3, ">=": 3, ">": 3, "+": 4, "-": 4,
        "*": 5, "/": 5, "%": 5, "atan2": 5}
COMPARISON = {"==", "!=", "<=", "<", ">=", ">"}
SETOPS = {"and", "or", "unless"}


class Parser:
    def __init__(self, src):
        self.t, self.i = lex(src), 0

    def peek(self, k=0):
        return self.t[self.i + k]

    def take(self, val=None):
        tok = self.t[self.i]
        if val is not None and tok[1] != val:
            raise Unsupported(f"expected {val!r}, got {tok[1]!r}")
        self.i += 1
        return tok

    def parse(self):
        e = self.expr(0)
        if self.peek()[0] != "eof":
            raise Unsupported(f"trailing {self.peek()[1]!r}")
        return e

    def expr(self, min_prec):
        lhs = self.unary()
        while True:
            kind, val = self.peek()
            op = val if (kind == "op" or (kind == "id" and val in ("and", "or", "unless", "atan2"))) else None
            if op not in PREC or PREC[op] < min_prec:
                return lhs
            self.take()
            mod = {"bool": False, "card": "one", "on": None, "labels": [], "include": []}
            if self.peek()[1] == "bool":
                self.take()
                mod["bool"] = True
            if self.peek()[1] in ("on", "ignoring"):
                mod["on"] = self.take()[1] == "on"
                mod["labels"] = self.label_list()
            if self.peek()[1] in ("group_left", "group_right"):
                mod["card"] = self.take()[1]
                if self.peek()[1] == "(":
                    mod["include"] = self.label_list()
            rhs = self.expr(PREC[op] + 1)
            lhs = ("bin", op, lhs, rhs, mod)

    def label_list(self):
        self.take("(")
        out = []
        while self.peek()[1] != ")":
            kind, val = self.take()
            if kind == "str":
                val = unquote(val)
            out.append(val)
            if self.peek()[1] == ",":
                self.take()
        self.take(")")
        return out

    def unary(self):
        if self.peek()[1] in ("-", "+"):
            op = self.take()[1]
            inner = self.unary()
            if op == "-" and inner[0] == "num":
                return ("num", -inner[1])
            return ("neg", inner) if op == "-" else inner
        return self.power()

    def power(self):
        base = self.postfix(self.primary())
        if self.peek()[1] == "^":
            self.take()
            mod = {"bool": False, "card": "one", "on": None, "labels": [], "include": []}
            if self.peek()[1] == "bool":
                self.take()
                mod["bool"] = True
            if self.peek()[1] in ("on", "ignoring"):
                mod["on"] = self.take()[1] == "on"
                mod["labels"] = self.label_list()
            if self.peek()[1] in ("group_left", "group_right"):
                mod["card"] = self.take()[1]
                if self.peek()[1] == "(":
                    mod["include"] = self.label_list()
            return ("bin", "^", base, self.unary(), mod)
        return base

    def postfix(self, node):
        while True:
            v = self.peek()[1]
            if v == "[":
                self.take()
                kind, val = self.take()
                if kind not in ("dur", "num"):
                    raise Unsupported("duration expression")
                rng = parse_duration(val)
                if self.peek()[1] == ":":
                    self.take()
                    step = None
                    if self.peek()[1] != "]":
                        kind, val = self.take()
                        if kind not in ("dur", "num"):
                            raise Unsupported("duration expression")
                        step = parse_duration(val)
                    self.take("]")
                    node = ("subq", node, rng, step, 0)
                else:
                    self.take("]")
                    if node[0] != "sel":
                        raise Unsupported("range on non-selector")
                    node = ("msel", node, rng)
            elif v == "offset":
                self.take()
                sign = 1
                if self.peek()[1] in ("-", "+"):
                    sign = -1 if self.take()[1] == "-" else 1
                kind, val = self.take()
                if kind not in ("dur", "num"):
                    raise Unsupported("duration expression")
                off = sign * parse_duration(val)
                if node[0] == "sel":
                    node = ("sel", node[1], node[2], off)
                elif node[0] == "msel":
                    node = ("msel", ("sel", node[1][1], node[1][2], off), node[2])
                elif node[0] == "subq":
                    node = ("subq", node[1], node[2], node[3], off)
                else:
                    raise Unsupported("offset on expression")
            elif v == "@":
                raise Unsupported("@ modifier")
            elif v in ("smoothed", "anchored"):
                raise Unsupported("extended range selectors")
            else:
                return node

    def primary(self):
        kind, val = self.peek()
        if val == "(":
            self.take()
            e = self.expr(0)
            self.take(")")
            return ("paren", e)
        if kind == "num":
            self.take()
            return ("num", float(int(val, 16)) if val[:2].lower() == "0x" else float(val))
        if kind == "dur":
            raise Unsupported("duration literal as number")
        if kind == "str":
            self.take()
            return ("str", unquote(val))
        if val == "{":
            return ("sel", None, self.matchers(), 0)
        if kind == "id":
            low = val.lower()
            if low in ("inf", "nan") and self.peek(1)[1] not in ("{", "("):
                self.take()
                return ("num", math.inf if low == "inf" else math.nan)
            if val in AGGS and self.peek(1)[1] in ("(", "by", "without"):
                return self.aggregation()
            if self.peek(1)[1] == "(":
                self.take()
                self.take("(")
                args = []
                while self.peek()[1] != ")":
                    args.append(self.expr(0))
                    if self.peek()[1] == ",":
                        self.take()
                self.take(")")
                return ("call", val, args)
            self.take()
            ms = self.matchers() if self.peek()[1] == "{" else []
            return ("sel", val, ms, 0)
        raise Unsupported(f"unexpected token {val!r}")

    def matchers(self):
        self.take("{")
        ms = []
        while self.peek()[1] != "}":
            kind, name = self.take()
            if kind == "str":
                raise Unsupported("quoted UTF-8 names")
            op = self.take()[1]
            if op not in ("=", "!=", "=~", "!~"):
                raise Unsupported(f"matcher op {op}")
            kind, v = self.take()
            if kind != "str":
                raise Unsupported("matcher value")
            ms.append((name, op, unquote(v)))
            if self.peek()[1] == ",":
                self.take()
        self.take("}")
        return ms

    def aggregation(self):
        op = self.take()[1]
        grouping, without = None, False
        if self.peek()[1] in ("by", "without"):
            without = self.take()[1] == "without"
            grouping = self.label_list()
        self.take("(")
        args = []
        while self.peek()[1] != ")":
            args.append(self.expr(0))
            if self.peek()[1] == ",":
                self.take()
        self.take(")")
        if self.peek()[1] in ("by", "without"):
            without = self.take()[1] == "without"
            grouping = self.label_list()
        param = args[0] if len(args) == 2 else None
        return ("agg", op, param, args[-1], grouping, without)


# ----------------------------------------------------------------------------- values
def lkey(d):
    return tuple(sorted(d.items()))


def drop_name(d):
    return {k: v for k, v in d.items() if k != "__name__"}


class Vector(list):
    pass


class Matrix(list):
    pass


def go_div(a, b):
    if b == 0:
        if a == 0 or math.isnan(a):
            return math.nan
        return math.copysign(math.inf, a) * math.copysign(1, b)
    return a / b


def go_pow(a, b):
    try:
        r = math.pow(a, b)
    except OverflowError:
        neg = a < 0 and float(b).is_integer() and int(b) % 2 == 1
        return -math.inf if neg else math.inf
    except ValueError:
        if a == 0 and b < 0:
            odd = float(b).is_integer() and int(b) % 2 == 1
            return math.copysign(math.inf, a) if odd else math.inf
        return math.nan
    return r


def go_mod(a, b):
    try:
        return math.fmod(a, b)
    except ValueError:
        return math.nan


def arith(op, a, b):
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    if op == "/":
        return go_div(a, b)
    if op == "%":
        return go_mod(a, b)
    if op == "^":
        return go_pow(a, b)
    if op == "atan2":
        return math.atan2(a, b)
    raise Unsupported(op)


def compare(op, a, b):
    return {"==": a == b, "!=": a != b, "<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b}[op]


def kahan_inc(inc, s, c):
    t = s + inc
    if math.isinf(t):
        c = 0.0
    elif abs(s) >= abs(inc):
        c += (s - t) + inc
    else:
        c += (inc - t) + s
    return t, c


def go_format_float(f):
    if math.isnan(f):
        return "NaN"
    if math.isinf(f):
        return "+Inf" if f > 0 else "-Inf"
    from decimal import Decimal
    s = format(Decimal(repr(f)), "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") and f == 0 and math.copysign(1, f) > 0 else s


def quantile_values(q, values):
    if not values or math.isnan(q):
        return math.nan
    if q < 0:
        return -math.inf
    if q > 1:
        return math.inf
    vs = sorted(values, key=lambda v: (not math.isnan(v), v if not math.isnan(v) else 0))
    n = float(len(vs))
    rank = q * (n - 1)
    lo = max(0.0, math.floor(rank))
    hi = min(n - 1, lo + 1)
    w = rank - math.floor(rank)
    return vs[int(lo)] * (1 - w) + vs[int(hi)] * w


def go_expand(template, m):
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
        k = n0 = 1 if brace else 0
        while k < len(rest) and (rest[k] == "_" or rest[k].isalnum()):
            k += 1
        name = rest[n0:k]
        if not name or (brace and (k >= len(rest) or rest[k] != "}")):
            out.append("$")
            i = j + 1
            continue
        i = j + 1 + k + (1 if brace else 0)
        if name.isdigit():
            g = int(name)
            if g <= m.re.groups and m.group(g) is not None:
                out.append(m.group(g))
        elif name in m.re.groupindex and m.group(name) is not None:
            out.append(m.group(name))
    return "".join(out)


# ----------------------------------------------------------------------------- engine
class Engine:
    def __init__(self):
        self.series = {}  # lkey -> (labels dict, [(t, v)])
        self.histo_series = set()
        self.default_step = 60000

    def add(self, labels, points):
        k = lkey(labels)
        self.series.setdefault(k, (labels, []))[1].extend(points)
        self.series[k][1].sort(key=lambda p: p[0])

    def match(self, name, ms):
        ms = list(ms) + ([("__name__", "=", name)] if name else [])
        out = []
        for k, (lbls, pts) in self.series.items():
            ok = True
            for ln, op, v in ms:
                have = lbls.get(ln, "")
                if op == "=":
                    ok = have == v
                elif op == "!=":
                    ok = have != v
                else:
                    hit = rx(v).fullmatch(have) is not None
                    ok = hit if op == "=~" else not hit
                if not ok:
                    break
            if ok:
                if k in self.histo_series:
                    raise Unsupported("native histogram series")
                out.append((lbls, pts))
        return out

    # -- selectors
    def instant(self, node, T):
        _, name, ms, off = node
        t = T - off
        vec = Vector()
        for lbls, pts in self.match(name, ms):
            cand = [p for p in pts if t - LOOKBACK < p[0] <= t]
            if cand and not is_stale(cand[-1][1]):
                vec.append((dict(lbls), cand[-1][1], cand[-1][0]))
        return vec

    def matrix(self, node, T):
        sel, rng = node[1], node[2]
        _, name, ms, off = sel
        t = T - off
        mat = Matrix()
        for lbls, pts in self.match(name, ms):
            win = [p for p in pts if t - rng < p[0] <= t and not is_stale(p[1])]
            if win:
                mat.append((dict(lbls), win))
        return mat

    def subquery(self, node, T):
        _, inner, rng, step, off = node
        step = step or self.default_step
        base = T - off - rng
        start = step * int(base / step)  # Go integer division truncates toward zero
        if start <= base:
            start += step
        acc = {}
        t = start
        while t <= T - off:
            v = self.eval(inner, t)
            if isinstance(v, (float, int)):
                acc.setdefault((), ({}, []))[1].append((t, float(v)))
            elif isinstance(v, Vector):
                for lbls, val, _ in v:
                    acc.setdefault(lkey(lbls), (lbls, []))[1].append((t, val))
            else:
                raise Unsupported("subquery over non-instant")
            t += step
        return Matrix((l, [p for p in pts if not is_stale(p[1])]) for l, pts in acc.values())

    # -- eval
    def eval(self, node, T):
        kind = node[0]
        if kind == "num":
            return node[1]
        if kind == "str":
            return ("string", node[1])
        if kind == "paren":
            return self.eval(node[1], T)
        if kind == "neg":
            v = self.eval(node[1], T)
            if isinstance(v, float):
                return -v
            if isinstance(v, Vector):
                return Vector((drop_name(l), -x, t) for l, x, t in v)
            raise Unsupported("neg")
        if kind == "sel":
            return self.instant(node, T)
        if kind == "msel":
            return self.matrix(node, T)
        if kind == "subq":
            return self.subquery(node, T)
        if kind == "call":
            return self.call(node, T)
        if kind == "agg":
            return self.aggregate(node, T)
        if kind == "bin":
            return self.binary(node, T)
        raise Unsupported(kind)

    def scalar_arg(self, node, T):
        v = self.eval(node, T)
        if not isinstance(v, float):
            raise Unsupported("non-scalar parameter")
        return v

    # -- functions
    def call(self, node, T):
        _, fn, args = node
        if fn in RANGE_FUNCS:
            mi = 1 if fn == "quantile_over_time" else 0
            arg0 = args[mi]
            while arg0[0] == "paren":
                arg0 = arg0[1]
            if arg0[0] not in ("msel", "subq"):
                raise Unsupported(f"{fn} arg")
            mat = self.eval(arg0, T)
            rng = arg0[2]
            extra = [self.scalar_arg(a, T) for k, a in enumerate(args) if k != mi]
            out = Vector()
            keep = fn in ("last_over_time", "first_over_time")
            if fn == "absent_over_time":
                if mat:
                    return Vector()
                return Vector([(absent_labels(arg0), 1.0, T)])
            shift = arg0[1][3] if arg0[0] == "msel" else arg0[4]  # window ends at T - offset
            for lbls, pts in mat:
                v = RANGE_FUNCS[fn](pts, T - shift, rng, *extra)
                if v is None:
                    continue
                out.append((lbls if keep else drop_name(lbls), v, T))
            check_dupes(out)
            return out
        if fn in SIMPLE:
            vec = self.eval(args[0], T)
            if not isinstance(vec, Vector):
                raise Unsupported(f"{fn} on non-vector")
            out = Vector((drop_name(l), SIMPLE[fn](x), T) for l, x, _ in vec)
            check_dupes(out)
            return out
        if fn == "time":
            return T / 1000.0
        if fn in DATE_FUNCS:
            import datetime
            if args:
                vec = self.eval(args[0], T)
                pts = [(drop_name(l), x) for l, x, _ in vec]
            else:
                pts = [({}, T / 1000.0)]
            out = Vector()
            for l, x in pts:
                if math.isnan(x) or math.isinf(x):
                    out.append((l, math.nan, T))
                    continue
                d = datetime.datetime.fromtimestamp(x, datetime.timezone.utc)
                out.append((l, float(DATE_FUNCS[fn](d)), T))
            return out
        if fn == "pi":
            return math.pi
        if fn == "vector":
            return Vector([({}, self.scalar_arg(args[0], T), T)])
        if fn == "scalar":
            v = self.eval(args[0], T)
            return v[0][1] if isinstance(v, Vector) and len(v) == 1 else math.nan
        if fn == "timestamp":
            if args[0][0] != "sel":
                vec = self.eval(args[0], T)
                return Vector((drop_name(l), T / 1000.0, T) for l, _, _ in vec)
            vec = self.instant(args[0], T)
            out = Vector((drop_name(l), ts / 1000.0, T) for l, _, ts in vec)
            check_dupes(out)
            return out
        if fn in ("round", "clamp", "clamp_min", "clamp_max"):
            vec = self.eval(args[0], T)
            ps = [self.scalar_arg(a, T) for a in args[1:]]
            if fn == "round":
                to = ps[0] if ps else 1.0
                inv = 1.0 / to
                f = lambda x: math.floor(x * inv + 0.5) / inv if not (math.isnan(x) or math.isinf(x)) else x  # noqa: E731
            elif fn == "clamp":
                if ps[1] < ps[0]:
                    return Vector()
                f = lambda x: max(ps[0], min(ps[1], x)) if not math.isnan(x) else x  # noqa: E731
            elif fn == "clamp_min":
                f = lambda x: max(ps[0], x) if not math.isnan(x) else x  # noqa: E731
            else:
                f = lambda x: min(ps[0], x) if not math.isnan(x) else x  # noqa: E731
            out = Vector((drop_name(l), f(x), T) for l, x, _ in vec)
            check_dupes(out)
            return out
        if fn == "absent":
            vec = self.eval(args[0], T)
            if vec:
                return Vector()
            return Vector([(absent_labels(args[0]), 1.0, T)])
        if fn in ("sort", "sort_desc"):
            vec = self.eval(args[0], T)
            nan = [s for s in vec if math.isnan(s[1])]
            rest = sorted((s for s in vec if not math.isnan(s[1])), key=lambda s: s[1], reverse=fn == "sort_desc")
            return Vector(rest + nan)
        if fn == "label_replace":
            vec = self.eval(args[0], T)
            dst, repl, src, rx = (self.eval(a, T)[1] for a in args[1:])
            r = re.compile(rx, re.S)
            out = Vector()
            for l, x, t in vec:
                m = r.fullmatch(l.get(src, ""))
                nl = dict(l)
                if m:
                    res = go_expand(repl, m)
                    if res:
                        nl[dst] = res
                    else:
                        nl.pop(dst, None)
                out.append((nl, x, t))
            check_dupes(out)
            return out
        if fn == "label_join":
            vec = self.eval(args[0], T)
            dst, sep = self.eval(args[1], T)[1], self.eval(args[2], T)[1]
            srcs = [self.eval(a, T)[1] for a in args[3:]]
            out = Vector()
            for l, x, t in vec:
                nl = dict(l)
                val = sep.join(l.get(s, "") for s in srcs)
                if val:
                    nl[dst] = val
                else:
                    nl.pop(dst, None)
                out.append((nl, x, t))
            check_dupes(out)
            return out
        if fn == "histogram_quantile":
            q = self.scalar_arg(args[0], T)
            vec = self.eval(args[1], T)
            return classic_histogram_quantile(q, vec, T)
        if fn == "histogram_fraction":
            lo, hi = self.scalar_arg(args[0], T), self.scalar_arg(args[1], T)
            vec = self.eval(args[2], T)
            return Vector((k, bucket_fraction(lo, hi, b), T) for k, b in classic_groups(vec))
        raise Unsupported(f"function {fn}")

    # -- aggregations
    def aggregate(self, node, T):
        _, op, param, expr, grouping, without = node
        if op in ("limitk", "limit_ratio"):
            raise Unsupported(op)
        p = None
        if op == "count_values":
            p = self.eval(param, T)[1]
        elif param is not None:
            p = self.scalar_arg(param, T)
        vec = self.eval(expr, T)
        if not isinstance(vec, Vector):
            raise Unsupported("aggregation over non-vector")
        groups = {}
        for l, x, t in vec:
            if grouping is None:
                key = {}
            elif without:
                key = {k: v for k, v in l.items() if k not in grouping and k != "__name__"}
            else:
                key = {k: v for k, v in l.items() if k in grouping}
            groups.setdefault(lkey(key), (key, []))[1].append((l, x))
        out = Vector()
        for key, members in groups.values():
            xs = [x for _, x in members]
            if op == "sum":
                s = c = 0.0
                for x in xs:
                    s, c = kahan_inc(x, s, c)
                out.append((key, s + c, T))
            elif op == "avg":
                s, c, cnt, mean, inc = xs[0], 0.0, 1.0, 0.0, False
                for x in xs[1:]:
                    cnt += 1
                    if not inc:
                        ns, nc = kahan_inc(x, s, c)
                        if not math.isinf(ns):
                            s, c = ns, nc
                            continue
                        inc = True
                        mean = s / (cnt - 1)
                        c /= cnt - 1
                    q = (cnt - 1) / cnt
                    mean, c = kahan_inc(x / cnt, q * mean, q * c)
                out.append((key, (mean + c) if inc else (s / cnt + c / cnt), T))
            elif op == "count":
                out.append((key, float(len(xs)), T))
            elif op == "group":
                out.append((key, 1.0, T))
            elif op in ("min", "max"):
                v = xs[0]
                for x in xs[1:]:
                    if (op == "max" and (v < x or math.isnan(v))) or (op == "min" and (v > x or math.isnan(v))):
                        v = x
                out.append((key, v, T))
            elif op in ("stddev", "stdvar"):
                v = math.nan if (math.isnan(xs[0]) or math.isinf(xs[0])) else 0.0
                mean, cnt = xs[0], 1.0
                for x in xs[1:]:
                    cnt += 1
                    d = x - mean
                    mean += d / cnt
                    v += d * (x - mean)
                v /= cnt
                out.append((key, math.sqrt(v) if op == "stddev" else v, T))
            elif op == "quantile":
                out.append((key, quantile_values(p, xs), T))
            elif op in ("topk", "bottomk"):
                if math.isnan(p):
                    raise EvalError("k is NaN")
                k = int(p)
                if k < 1:
                    continue
                def rank(m):
                    x = m[1]
                    if math.isnan(x):
                        return -math.inf if op == "topk" else math.inf
                    return x
                srt = sorted(members, key=rank, reverse=(op == "topk"))
                for l, x in srt[:k]:
                    out.append((l, x, T))
            elif op == "count_values":
                counts = {}
                for x in xs:
                    counts[go_format_float(x)] = counts.get(go_format_float(x), 0) + 1
                for sval, n in counts.items():
                    out.append(({**key, p: sval}, float(n), T))
            else:
                raise Unsupported(op)
        return out

    # -- binary
    def binary(self, node, T):
        _, op, ln, rn, mod = node
        lhs, rhs = self.eval(ln, T), self.eval(rn, T)
        is_cmp, is_set = op in COMPARISON, op in SETOPS
        if isinstance(lhs, float) and isinstance(rhs, float):
            if is_cmp:
                if not mod["bool"]:
                    raise EvalError("comparisons between scalars must use BOOL modifier")
                return 1.0 if compare(op, lhs, rhs) else 0.0
            return arith(op, lhs, rhs)
        if isinstance(lhs, Vector) and isinstance(rhs, float) or isinstance(lhs, float) and isinstance(rhs, Vector):
            swap = isinstance(lhs, float)
            vec, sc = (rhs, lhs) if swap else (lhs, rhs)
            out = Vector()
            for l, x, t in vec:
                a, b = (sc, x) if swap else (x, sc)
                if is_cmp:
                    keep = compare(op, a, b)
                    if mod["bool"]:
                        out.append((drop_name(l), 1.0 if keep else 0.0, T))
                    elif keep:
                        out.append((l, x, T))
                else:
                    out.append((drop_name(l), arith(op, a, b), T))
            check_dupes(out)
            return out
        if not (isinstance(lhs, Vector) and isinstance(rhs, Vector)):
            raise Unsupported("binary on non-vector")

        def sig(l):
            if mod["on"] is True:
                return lkey({k: v for k, v in l.items() if k in mod["labels"]})
            excl = set(mod["labels"]) | {"__name__"}
            return lkey({k: v for k, v in l.items() if k not in excl})

        if is_set:
            rsigs = {sig(l) for l, _, _ in rhs}
            if op == "and":
                return Vector(s for s in lhs if sig(s[0]) in rsigs)
            if op == "unless":
                return Vector(s for s in lhs if sig(s[0]) not in rsigs)
            lsigs = {sig(l) for l, _, _ in lhs}
            return Vector(list(lhs) + [s for s in rhs if sig(s[0]) not in lsigs])

        card = mod["card"]
        many, one = (lhs, rhs) if card != "group_right" else (rhs, lhs)
        one_by_sig = {}
        for s in one:
            k = sig(s[0])
            if k in one_by_sig:
                raise EvalError("found duplicate series for the match group on the 'one' side")
            one_by_sig[k] = s
        drop = (not is_cmp) or mod["bool"]
        out, matched = Vector(), {}
        for s in many:
            k = sig(s[0])
            if k not in one_by_sig:
                continue
            o = one_by_sig[k]
            if card == "one":
                if k in matched:
                    raise EvalError("multiple matches for labels: many-to-one matching must be explicit")
                matched[k] = True
            a, b = (s[1], o[1]) if card != "group_right" else (o[1], s[1])
            if is_cmp:
                keep = compare(op, a, b)
                if not keep and not mod["bool"]:
                    continue
                val = (1.0 if keep else 0.0) if mod["bool"] else a if card != "group_right" else b
            else:
                val = arith(op, a, b)
            nl = drop_name(s[0]) if drop else dict(s[0])
            if card == "one":
                if mod["on"] is True:
                    nl = {k2: v for k2, v in nl.items() if k2 in mod["labels"]}
                else:
                    for k2 in mod["labels"]:
                        nl.pop(k2, None)
            for inc in mod["include"]:
                if o[0].get(inc, ""):
                    nl[inc] = o[0][inc]
                else:
                    nl.pop(inc, None)
            out.append((nl, val, T))
        check_dupes(out)
        return out


def check_dupes(vec):
    seen = set()
    for l, _, _ in vec:
        k = lkey(l)
        if k in seen:
            raise EvalError("vector cannot contain metrics with the same labelset")
        seen.add(k)


def absent_labels(node):
    if node[0] == "msel":
        node = node[1]
    if node[0] != "sel":
        return {}
    out, drop = {}, set()
    for n, op, v in node[2]:
        if n == "__name__":
            continue
        if op == "=" and n not in out and n not in drop:
            out[n] = v
        else:
            drop.add(n)  # repeated or non-equality matcher: the label value is ambiguous
    return {k: v for k, v in out.items() if k not in drop}


# ----------------------------------------------------------------------------- range functions
def extrapolated(pts, T, rng, is_counter, is_rate):
    if len(pts) < 2:
        return None
    first_t, last_t = pts[0][0], pts[-1][0]
    result = pts[-1][1] - pts[0][1]
    if is_counter:
        for (_, pv), (_, cv) in zip(pts, pts[1:]):
            if cv < pv:
                result += pv
    range_start, range_end = T - rng, T
    to_start = (first_t - range_start) / 1000
    to_end = (range_end - last_t) / 1000
    sampled = (last_t - first_t) / 1000
    avg = sampled / (len(pts) - 1)
    thr = avg * 1.1
    if to_start >= thr:
        to_start = avg / 2
    if is_counter:
        to_zero = to_start
        if result > 0 and pts[0][1] >= 0:
            to_zero = sampled * (pts[0][1] / result)
        if to_zero < to_start:
            to_start = to_zero
    if to_end >= thr:
        to_end = avg / 2
    factor = (sampled + to_start + to_end) / sampled if sampled else 1.0
    if is_rate:
        factor /= rng / 1000
    return result * factor


def instant_value(pts, is_rate):
    if len(pts) < 2:
        return None
    (t1, v1), (t2, v2) = pts[-2], pts[-1]
    res = v2 if (is_rate and v2 < v1) else v2 - v1
    if is_rate:
        dt = (t2 - t1) / 1000
        if dt == 0:
            return None
        res /= dt
    return res


def linreg(pts, intercept_t):
    n = sx = cx = sy = cy = sxy = cxy = sx2 = cx2 = 0.0
    init, const = pts[0][1], True
    for i, (t, v) in enumerate(pts):
        if const and i > 0 and v != init:
            const = False
        n += 1
        x = (t - intercept_t) / 1e3
        sx, cx = kahan_inc(x, sx, cx)
        sy, cy = kahan_inc(v, sy, cy)
        sxy, cxy = kahan_inc(x * v, sxy, cxy)
        sx2, cx2 = kahan_inc(x * x, sx2, cx2)
    if const:
        if math.isinf(init):
            return math.nan, math.nan
        return 0.0, init
    sx, sy, sxy, sx2 = sx + cx, sy + cy, sxy + cxy, sx2 + cx2
    cov = sxy - sx * sy / n
    var = sx2 - sx * sx / n
    slope = go_div(cov, var)
    return slope, sy / n - slope * sx / n


def avg_over(pts):
    vals = [v for _, v in pts]
    s, cnt, mean, c, inc = vals[0], 1.0, 0.0, 0.0, False
    for v in vals[1:]:
        cnt += 1
        if not inc:
            ns, nc = kahan_inc(v, s, c)
            if not math.isinf(ns):
                s, c = ns, nc
                continue
            inc = True
            mean = s / (cnt - 1)
            c /= cnt - 1
        q = (cnt - 1) / cnt
        mean, c = kahan_inc(v / cnt, q * mean, q * c)
    return mean + c if inc else s / cnt + c / cnt


def variance(pts):
    cnt = mean = cm = aux = ca = 0.0
    for _, v in pts:
        cnt += 1
        d = v - (mean + cm)
        mean, cm = kahan_inc(d / cnt, mean, cm)
        aux, ca = kahan_inc(d * (v - (mean + cm)), aux, ca)
    return (aux + ca) / cnt


def sum_over(pts):
    s = c = 0.0
    for _, v in pts:
        s, c = kahan_inc(v, s, c)
    return s + c


def changes(pts):
    n, prev = 0, pts[0][1]
    for _, v in pts[1:]:
        if not (v == prev or (math.isnan(v) and math.isnan(prev))):
            n += 1
        prev = v
    return float(n)


def resets(pts):
    n, prev = 0, pts[0][1]
    for _, v in pts[1:]:
        if v < prev:
            n += 1
        prev = v
    return float(n)


def mad(pts):
    vals = [v for _, v in pts]
    if any(math.isnan(v) for v in vals):  # 3.14: a NaN makes the median undefined
        return math.nan
    med = quantile_values(0.5, vals)
    return quantile_values(0.5, [abs(v - med) for v in vals])


def _minmax(pts, is_max):
    v = pts[0][1]
    for _, x in pts[1:]:
        if (is_max and (x > v or math.isnan(v))) or (not is_max and (x < v or math.isnan(v))):
            v = x
    return v


RANGE_FUNCS = {
    "rate": lambda p, T, r: extrapolated(p, T, r, True, True),
    "increase": lambda p, T, r: extrapolated(p, T, r, True, False),
    "delta": lambda p, T, r: extrapolated(p, T, r, False, False),
    "irate": lambda p, T, r: instant_value(p, True),
    "idelta": lambda p, T, r: instant_value(p, False),
    "deriv": lambda p, T, r: linreg(p, p[0][0])[0] if len(p) >= 2 else None,
    "predict_linear": lambda p, T, r, d: (lambda s, i: i + s * d)(*linreg(p, T)) if len(p) >= 2 else None,
    "resets": lambda p, T, r: resets(p),
    "changes": lambda p, T, r: changes(p),
    "avg_over_time": lambda p, T, r: avg_over(p),
    "sum_over_time": lambda p, T, r: sum_over(p),
    "count_over_time": lambda p, T, r: float(len(p)),
    "min_over_time": lambda p, T, r: _minmax(p, False),
    "max_over_time": lambda p, T, r: _minmax(p, True),
    "last_over_time": lambda p, T, r: p[-1][1],
    "first_over_time": lambda p, T, r: p[0][1],
    "present_over_time": lambda p, T, r: 1.0,
    "stddev_over_time": lambda p, T, r: math.sqrt(variance(p)),
    "stdvar_over_time": lambda p, T, r: variance(p),
    "quantile_over_time": None,
    "mad_over_time": lambda p, T, r: mad(p),
    "absent_over_time": None,
}
RANGE_FUNCS["quantile_over_time"] = None
del RANGE_FUNCS["quantile_over_time"]


def _days_in_month(d):
    import calendar
    return calendar.monthrange(d.year, d.month)[1]


DATE_FUNCS = {"year": lambda d: d.year, "month": lambda d: d.month, "day_of_month": lambda d: d.day,
              "day_of_week": lambda d: (d.weekday() + 1) % 7, "day_of_year": lambda d: d.timetuple().tm_yday,
              "days_in_month": _days_in_month, "hour": lambda d: d.hour, "minute": lambda d: d.minute}


def _sgn(x):
    return math.nan if math.isnan(x) else (1.0 if x > 0 else -1.0 if x < 0 else 0.0)


def _safe(f):
    def g(x):
        try:
            return f(x)
        except (ValueError, OverflowError):
            return math.nan if not (f is math.exp and x > 0) else math.inf
    return g


def _ln(x):
    if x == 0:
        return -math.inf
    if x < 0 or math.isnan(x):
        return math.nan
    return math.inf if math.isinf(x) else math.log(x)


SIMPLE = {
    "abs": abs, "ceil": lambda x: x if math.isnan(x) or math.isinf(x) else float(math.ceil(x)),
    "floor": lambda x: x if math.isnan(x) or math.isinf(x) else float(math.floor(x)),
    "exp": _safe(math.exp), "sqrt": lambda x: math.nan if x < 0 or math.isnan(x) else math.sqrt(x),
    "ln": _ln, "log2": lambda x: _ln(x) / math.log(2) if x > 0 and not math.isinf(x) else _ln(x),
    "log10": lambda x: _ln(x) / math.log(10) if x > 0 and not math.isinf(x) else _ln(x), "sgn": _sgn,
    "deg": lambda x: x * 180 / math.pi, "rad": lambda x: x * math.pi / 180,
}


def classic_groups(vec):
    groups = {}
    for l, x, _ in vec:
        if "le" not in l:
            continue
        try:
            ub = float(l["le"].replace("+Inf", "inf").replace("-Inf", "-inf"))
        except ValueError:
            continue
        key = {k: v for k, v in l.items() if k not in ("le", "__name__")}
        groups.setdefault(lkey(key), (key, []))[1].append((ub, x))
    return list(groups.values())


def bucket_fraction(lower, upper, buckets):
    """promql/quantile.go BucketFraction: share of observations in [lower, upper], linear in-bucket."""
    buckets = sorted(buckets, key=lambda b: b[0])
    if not math.isinf(buckets[-1][0]) or buckets[-1][0] < 0:
        return math.nan
    co = []
    for ub, c in buckets:
        if co and co[-1][0] == ub:
            co[-1][1] += c
        else:
            co.append([ub, c])
    count = co[-1][1]
    if count == 0 or math.isnan(lower) or math.isnan(upper):
        return math.nan
    if lower >= upper:
        return 0.0
    rank = lo_rank = up_rank = 0.0
    lo_set = up_set = False
    lb = 0.0 if co[0][0] > 0 else -math.inf
    for i, (ub, c) in enumerate(co):
        if i > 0:
            lb = co[i - 1][0]

        def interp(v):
            if lb == -math.inf:
                return c
            return rank + (c - rank) * (v - lb) / (ub - lb)
        if not lo_set and lb >= lower:
            lo_rank, lo_set = rank, True
        if not up_set and lb >= upper:
            up_rank, up_set = rank, True
        if lo_set and up_set:
            break
        if not lo_set and lb < lower < ub:
            lo_rank, lo_set = interp(lower), True
        if not up_set and lb < upper < ub:
            up_rank, up_set = interp(upper), True
        if lo_set and up_set:
            break
        rank = c
    if not lo_set or lo_rank > count:
        lo_rank = count
    if not up_set or up_rank > count:
        up_rank = count
    return (up_rank - lo_rank) / count


def classic_histogram_quantile(q, vec, T):
    groups = {}
    for l, x, _ in vec:
        if "le" not in l:
            continue
        try:
            ub = float(l["le"].replace("+Inf", "inf").replace("-Inf", "-inf"))
        except ValueError:
            continue
        key = {k: v for k, v in l.items() if k not in ("le", "__name__")}
        groups.setdefault(lkey(key), (key, []))[1].append((ub, x))
    out = Vector()
    for key, buckets in groups.values():
        out.append((key, bucket_quantile(q, buckets), T))
    return out


def almost_equal(a, b, eps):
    if math.isnan(a) and math.isnan(b):
        return True
    if a == b:
        return True
    min_normal = 2.2250738585072014e-308
    abs_sum, diff = abs(a) + abs(b), abs(a - b)
    if a == 0 or b == 0 or abs_sum < min_normal:
        return diff < eps * min_normal
    return diff / min(abs_sum, sys.float_info.max) < eps


def bucket_quantile(q, buckets):
    if math.isnan(q):
        return math.nan
    if q < 0:
        return -math.inf
    if q > 1:
        return math.inf
    buckets = sorted(buckets, key=lambda b: b[0])
    if not math.isinf(buckets[-1][0]) or buckets[-1][0] < 0:
        return math.nan
    co = []
    for ub, c in buckets:  # coalesceBuckets
        if co and co[-1][0] == ub:
            co[-1][1] += c
        else:
            co.append([ub, c])
    prev = co[0][1]
    for b in co[1:]:  # ensureMonotonicAndIgnoreSmallDeltas
        cur = b[1]
        if cur == prev:
            continue
        if almost_equal(prev, cur, 1e-12) or cur < prev:
            b[1] = prev
            continue
        prev = cur
    if len(co) < 2:
        return math.nan
    obs = co[-1][1]
    if obs == 0:
        return math.nan
    rank = q * obs
    b = next((i for i in range(len(co) - 1) if co[i][1] >= rank), len(co) - 1)
    if b == len(co) - 1:
        return co[-2][0]
    if b == 0 and co[0][0] <= 0:
        return co[0][0]
    start, end, count = 0.0, co[b][0], co[b][1]
    if b > 0:
        start = co[b - 1][0]
        count -= co[b - 1][1]
        rank -= co[b - 1][1]
    return start + (end - start) * (rank / count)


def _quantile_over_time(p, T, r, q):  # matrix is the 2nd argument; q arrives as the extra arg
    return quantile_values(q, [v for _, v in p])


RANGE_FUNCS["quantile_over_time"] = _quantile_over_time
RANGE_FUNCS["absent_over_time"] = None


# ----------------------------------------------------------------------------- promqltest runner
TERM = re.compile(r"^(?P<a>-?(?:\d+\.?\d*(?:e[+-]?\d+)?|\.\d+|Inf|NaN|inf|nan))(?:(?P<op>[+-])(?P<b>\d+\.?\d*(?:e[+-]?\d+)?))?x(?P<n>\d+)$")


def expand_points(spec):
    vals = []
    for term in spec.split("#")[0].split():
        if term.startswith("{{"):
            raise Unsupported("native histogram literal")
        if term == "_":
            vals.append(None)
        elif term == "stale":
            vals.append(STALE)
        elif re.fullmatch(r"_x\d+", term):
            vals.extend([None] * int(term[2:]))
        else:
            m = TERM.match(term)
            if m:
                a = float(m.group("a"))
                b = float(m.group("b") or 0) * (-1 if m.group("op") == "-" else 1)
                vals.extend(a + i * b for i in range(int(m.group("n")) + 1))
            else:
                vals.append(float(term))
    return vals


def parse_series(line):
    m = re.match(r"^\s*([a-zA-Z_:][\w:]*)?(\{[^}]*\})?\s*(.*)$", line)
    name, braces, rest = m.group(1), m.group(2), m.group(3)
    lbls = {}
    if braces:
        for k, v in re.findall(r'([a-zA-Z_][\w]*)\s*=\s*"((?:[^"\\]|\\.)*)"', braces):
            lbls[k] = unquote('"' + v + '"')
    if name:
        lbls["__name__"] = name
    return lbls, rest


def parse_time(s):
    return parse_duration(s) if not re.fullmatch(r"-?\d+", s) else int(s) * 1000


def run_file(path):
    eng = Engine()
    lines = path.read_text(encoding="utf-8").splitlines()
    stats = {"pass": 0, "fail": 0, "skip": 0}
    fails, skips, i, nhcb = [], {}, 0, False

    def skip(reason):
        stats["skip"] += 1
        skips[reason] = skips.get(reason, 0) + 1

    while i < len(lines):
        line = lines[i].rstrip()
        s = line.strip()
        if not s or s.startswith("#"):
            i += 1
            continue
        if s == "clear":
            eng, nhcb = Engine(), False
            i += 1
            continue
        if s.startswith("load"):
            nhcb = nhcb or s.startswith("load_with_nhcb")
            step = parse_duration(s.split()[1])
            i += 1
            while i < len(lines) and lines[i].strip() and (lines[i][0] in " \t"):
                if lines[i].strip().startswith("#"):
                    i += 1
                    continue
                lbls, spec = parse_series(lines[i])
                if nhcb and lbls.get("__name__", "").endswith("_bucket") and "le" in lbls:
                    derived = {k: v for k, v in lbls.items() if k != "le"}
                    derived["__name__"] = derived["__name__"][:-7]
                    eng.histo_series.add(lkey(derived))  # the NHCB twin is a native histogram
                    eng.add(derived, [])
                try:
                    vals = expand_points(spec)
                    eng.add(lbls, [(k * step, v) for k, v in enumerate(vals) if v is not None])
                except Unsupported:
                    eng.histo_series.add(lkey(lbls))
                    eng.add(lbls, [])
                except ValueError:
                    eng.histo_series.add(lkey(lbls))
                    eng.add(lbls, [])
                i += 1
            continue
        if s.startswith("eval"):
            head = s
            lineno = i + 1
            i += 1
            body = []
            while i < len(lines) and lines[i].strip() and lines[i][0] in " \t":
                if not lines[i].strip().startswith("#"):
                    body.append(lines[i].strip())
                i += 1
            run_eval(eng, head, body, stats, fails, skip, lineno, nhcb)
            continue
        i += 1
    return stats, fails, skips


def run_eval(eng, head, body, stats, fails, skip, lineno, nhcb):
    m_inst = re.match(r"^(eval[a-z_]*) instant at (\S+) (.*)$", head)
    m_rng = re.match(r"^(eval[a-z_]*) range from (\S+) to (\S+) step (\S+) (.*)$", head)
    cmd = (m_inst or m_rng).group(1)
    expects = [b for b in body if b.startswith("expect ")]
    results = [b for b in body if not b.startswith("expect ")]
    if cmd == "eval_fail" or any(e.startswith("expect fail") for e in expects):
        return skip("expects failure")
    if any(e.startswith("expect range vector") for e in expects):
        return skip("range-vector result")
    ordered = cmd == "eval_ordered" or any(e.startswith("expect ordered") for e in expects)
    exp_string = next((e for e in expects if e.startswith("expect string")), None)
    query = (m_inst or m_rng).group(3 if m_inst else 5)
    try:
        ast = Parser(query).parse()
        if m_inst:
            T = parse_time(m_inst.group(2))
            got = eng.eval(ast, T)
            if isinstance(got, Matrix):
                return skip("range-vector result")
            if exp_string is not None:
                want = unquote(exp_string.split(" ", 2)[2].strip())
                ok = isinstance(got, tuple) and got[1] == want
            else:
                ok = compare_instant(got, results, ordered)
        else:
            start, end, step = (parse_time(m_rng.group(k)) for k in (2, 3, 4))
            ok = compare_range(eng, ast, start, end, step, results)
    except Unsupported as e:
        reason = str(e).split(" ")[0] if not str(e).startswith(("function", "native", "@", "duration", "quoted", "extended", "range")) else " ".join(str(e).split(" ")[:2])
        return skip(reason)
    except EvalError as e:
        ok = False
        got = f"error: {e}"
    if ok:
        stats["pass"] += 1
    else:
        stats["fail"] += 1
        fails.append((lineno, head))


def compare_instant(got, results, ordered):
    if isinstance(got, float):
        if len(results) != 1:
            return False
        return almost_equal(float(results[0].split()[-1]), got, 1e-6)
    if isinstance(got, tuple):
        return False
    want = []
    for r in results:
        lbls, rest = parse_series(r)
        if rest.startswith("{{"):
            raise Unsupported("native histogram expectation")
        want.append((lkey(lbls), expand_points(rest)[0]))
    have = [(lkey(l), x) for l, x, _ in got]
    if len(want) != len(have):
        return False
    if ordered:
        return all(a[0] == b[0] and almost_equal(a[1], b[1], 1e-6) for a, b in zip(want, have))
    hm = dict(have)
    return all(k in hm and almost_equal(v, hm[k], 1e-6) for k, v in want)


def compare_range(eng, ast, start, end, step, results):
    steps = list(range(start, end + 1, step))
    acc = {}
    for idx, t in enumerate(steps):
        v = eng.eval(ast, t)
        if isinstance(v, float):
            v = Vector([({}, v, t)])
        if not isinstance(v, Vector):
            raise Unsupported("range result type")
        for l, x, _ in v:
            acc.setdefault(lkey(l), [None] * len(steps))[idx] = x
    want = {}
    for r in results:
        lbls, rest = parse_series(r)
        vals = expand_points(rest)
        want[lkey(lbls)] = vals + [None] * (len(steps) - len(vals))
    if set(want) != set(acc):
        return False
    for k, vals in want.items():
        for a, b in zip(vals, acc[k]):
            if (a is None) != (b is None) or (a is not None and not almost_equal(a, b, 1e-6)):
                return False
    return True


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    target = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve()
    fixdir = target.parent / "fixtures" / "promqltest-v3.15.1"
    tot = {"pass": 0, "fail": 0, "skip": 0}
    all_skips, all_fails = {}, []
    print(f"{'file':<22} {'pass':>5} {'fail':>5} {'skip':>5}")
    for f in sorted(fixdir.glob("*.test")):
        st, fails, skips = run_file(f)
        for k in tot:
            tot[k] += st[k]
        for k, v in skips.items():
            all_skips[k] = all_skips.get(k, 0) + v
        all_fails += [(f.name, ln, h) for ln, h in fails]
        print(f"{f.name:<22} {st['pass']:>5} {st['fail']:>5} {st['skip']:>5}")
    print(f"{'TOTAL':<22} {tot['pass']:>5} {tot['fail']:>5} {tot['skip']:>5}")
    print("skip reasons: " + ", ".join(f"{k} {v}" for k, v in sorted(all_skips.items(), key=lambda kv: -kv[1])))
    for name, ln, h in all_fails[:40]:
        print(f"FAIL {name}:{ln} {h}")
    print("verdict: OK" if tot["fail"] == 0 and tot["pass"] > 0 else f"verdict: FAIL {tot['fail']} cases")
    return 0 if tot["fail"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:promql_mini.py -->
```text
file                    pass  fail  skip
aggregators.test         122     0    38
functions.test           242     0   196
histograms.test           82     0   103
literals.test             25     0     0
operators.test           136     0    78
range_queries.test        11     0     7
selectors.test            28     0     3
staleness.test            17     0     0
subquery.test             32     0     2
TOTAL                    695     0   427
skip reasons: native histogram 291, expects failure 23, function histogram_quantiles 14, function end 10, function sort_by_label 9, function range 8, function start 8, function step 7, function min_of 7, function max_of 7, @ modifier 6, function ts_of_first_over_time 5, range-vector result 5, function sort_by_label_desc 4, function double_exponential_smoothing 4, function ts_of_last_over_time 4, duration literal 3, RE2-only 3, function histogram_count 2, function histogram_sum 2, function ts_of_min_over_time 1, function ts_of_max_over_time 1, function histogram_avg 1, function histogram_stddev 1, function histogram_stdvar 1
verdict: OK
```

<!-- listing:rate_math_lab.py -->
```python
"""rate_math_lab.py - the arithmetic of rate(), increase(), irate() and delta() in Prometheus 3.x,
using the extrapolatedRate/instantValue ports in promql_mini.py (validated against promqltest).

Sections: (1) a worked extrapolation, step by step; (2) why increase() of an integer counter is not
an integer; (3) counter resets and the zero-point clamp; (4) Monte Carlo bias/RMSE of increase()
versus the true number of events for windows of 2..20 scrape intervals, with 15 s scrapes and
scrape jitter; (5) irate vs rate on a bursty series; (6) rate() on a gauge.
Deterministic (fixed seeds), stdlib only.

Usage: python rate_math_lab.py [target.md]
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import Engine, Parser, extrapolated, instant_value  # noqa: E402

S = 1000
M = 60 * S


def window(pts, T, rng):
    return [p for p in pts if T - rng < p[0] <= T]


def explain(pts, T, rng):
    w = window(pts, T, rng)
    first_t, last_t = w[0][0], w[-1][0]
    sampled = (last_t - first_t) / S
    avg = sampled / (len(w) - 1)
    to_start, to_end = (first_t - (T - rng)) / S, (T - last_t) / S
    raw = w[-1][1] - w[0][1]
    return w, sampled, avg, to_start, to_end, raw


def main():
    checks = []
    print("== 1. rate(x[1m]) at T=10m, 15 s scrapes, +30 per scrape (true rate 2/s) ==")
    pts = [(i * 15 * S, 30.0 * i) for i in range(0, 41)]
    T, rng = 10 * M, 1 * M
    w, sampled, avg, ts, te, raw = explain(pts, T, rng)
    print(f"samples in (T-1m, T] (left-open since 3.0): {[(t // S, v) for t, v in w]}")
    print(f"raw delta {raw:.0f} over sampled interval {sampled:.0f}s; avg spacing {avg:.0f}s; "
          f"gap to window start {ts:.0f}s, to end {te:.0f}s; threshold 1.1*avg = {1.1 * avg:.1f}s")
    inc = extrapolated(w, T, rng, True, False)
    r = extrapolated(w, T, rng, True, True)
    print(f"both gaps < threshold -> extrapolate to the edges: increase = {raw:.0f} * (45+15+0)/45 = {inc:.1f}; "
          f"rate = {inc:.1f}/60 = {r:.4f}/s")
    checks.append(("worked rate", abs(r - 2.0) < 1e-12 and abs(inc - 120.0) < 1e-9))
    left_closed = [p for p in pts if T - rng <= p[0] <= T]
    print(f"a 2.x-style left-closed window would hold {len(left_closed)} samples (raw delta "
          f"{left_closed[-1][1] - left_closed[0][1]:.0f} over 60 s): same rate here, different sample set")
    print()

    print("== 2. increase() of an integer counter is not an integer ==")
    ev = [(i * 15 * S, float(i)) for i in range(0, 41)]  # +1 per scrape, aligned
    for label, w_ms in (("[1m]", 60 * S), ("[50s]", 50 * S), ("[40s]", 40 * S)):
        T = 10 * M
        w = window(ev, T, w_ms)
        v = extrapolated(w, T, w_ms, True, False)
        print(f"aligned scrapes, increase(x{label}) at 10m: {len(w)} samples, raw delta "
              f"{w[-1][1] - w[0][1]:.0f} -> {v:.4f}")
    jit = [(int(i * 15 * S + (i * 7919 % 400)), float(i)) for i in range(0, 41)]  # 0-400 ms late
    vals = [extrapolated(window(jit, T, 60 * S), T, 60 * S, True, False) for T in (600 * S, 603 * S, 607 * S)]
    print(f"0-400 ms scrape jitter, increase(x[1m]) at 600/603/607 s: {', '.join(f'{v:.4f}' for v in vals)}")
    checks.append(("non-integer increase", any(abs(v - round(v)) > 1e-6 for v in vals)))
    print()

    print("== 3. Counter reset, half-spacing extrapolation and the zero-point clamp ==")
    reset = [(0, 100.0), (15 * S, 110.0), (30 * S, 5.0), (45 * S, 15.0)]
    v = extrapolated(window(reset, 60 * S, 60 * S), 60 * S, 60 * S, True, False)
    print(f"samples {[x[1] for x in reset]} at 0/15/30/45 s (window (0, 60s]): sample at t=0 is EXCLUDED "
          f"(left-open); raw 15-110 = -95, +110 for the reset = 15 over 30 s -> increase = {v:.4f}")
    checks.append(("reset", abs(v - 15 * (30 + 15 + 15) / 30) < 1e-9))
    young = [(30 * S, 3.0), (45 * S, 6.0), (60 * S, 9.0)]
    v2 = extrapolated(young, 60 * S, 60 * S, True, False)
    print(f"series first seen 30 s into the window (3, 6, 9): the 30 s gap exceeds 1.1 x 15 s, so it is "
          f"extrapolated only half a spacing: 6 x (30+7.5)/30 = {v2:.4f}")
    near_zero = [(30 * S, 1.0), (45 * S, 11.0), (60 * S, 21.0)]
    v3 = extrapolated(near_zero, 60 * S, 60 * S, True, False)
    print(f"series 1, 11, 21: half a spacing back would imply a negative count; the zero point is 1.5 s back, "
          f"so 20 x (30+1.5)/30 = {v3:.4f} (= the last value: counted from zero)")
    checks.append(("half spacing", abs(v2 - 7.5) < 1e-9))
    checks.append(("zero clamp", abs(v3 - 21.0) < 1e-9))
    print()

    print("== 4. Monte Carlo: increase() vs true events, Poisson 2 events/s, 15 s scrapes ==")
    rng_ = random.Random(42)
    events, t, horizon = [], 0.0, 4 * 3600.0
    while t < horizon:
        t += rng_.expovariate(2.0)
        events.append(t)
    import bisect
    scrapes = []
    for i in range(int(horizon / 15)):
        st = i * 15.0 + rng_.uniform(0, 0.4)  # up to 400 ms late: misaligned scrapes
        scrapes.append((int(st * 1000), float(bisect.bisect_right(events, st))))
    print(f"{'window':>7} {'mean est':>9} {'mean true':>10} {'bias':>7} {'RMSE':>7} {'RMSE %':>7} {'empty':>6}")
    rmse_by = {}
    for mult in (2, 3, 4, 8, 20):
        w_ms = mult * 15 * S
        est, tru, empty = [], [], 0
        for _ in range(1500):
            T = rng_.randint(w_ms + 60 * S, int(horizon * 1000) - 60 * S)
            ww = window(scrapes, T, w_ms)
            v = extrapolated(ww, T, w_ms, True, False)
            if v is None:
                empty += 1
                continue
            true = bisect.bisect_right(events, T / 1000) - bisect.bisect_right(events, (T - w_ms) / 1000)
            est.append(v)
            tru.append(true)
        n = len(est)
        bias = sum(e - t for e, t in zip(est, tru)) / n
        rmse = math.sqrt(sum((e - t) ** 2 for e, t in zip(est, tru)) / n)
        mt = sum(tru) / n
        rmse_by[mult] = rmse / mt
        print(f"{mult * 15:>6}s {sum(est) / n:>9.1f} {mt:>10.1f} {bias:>+7.2f} {rmse:>7.2f} {rmse / mt:>6.1%} {empty / 1500:>6.1%}")
    checks.append(("RMSE shrinks with window", rmse_by[20] < rmse_by[4] < rmse_by[2]))
    print()

    print("== 5. irate vs rate on a burst (counter +2/s, then +200/s for 30 s) ==")
    burst = []
    c = 0.0
    for i in range(0, 61):
        t = i * 15 * S
        c += (200 if 30 <= i < 32 else 2) * 15
        burst.append((t, c))
    print(f"{'T':>6} {'rate[5m]':>9} {'irate[5m]':>10} {'rate[1m]':>9}")
    seen = []
    for i in (29, 30, 31, 32, 33, 36, 50):
        T = i * 15 * S
        a = extrapolated(window(burst, T, 5 * M), T, 5 * M, True, True)
        b = instant_value(window(burst, T, 5 * M), True)
        d = extrapolated(window(burst, T, 1 * M), T, 1 * M, True, True)
        seen.append((i, a, b))
        print(f"{T / S:>5.0f}s {a:>9.1f} {b:>10.1f} {d:>9.1f}")
    checks.append(("irate sees burst fully", max(b for _, _, b in seen) >= 200 - 1e-9))
    checks.append(("irate forgets burst", seen[-1][2] < 3))
    print()

    print("== 6. rate() on a gauge (queue depth draining 100 -> 0) ==")
    g = [(i * 15 * S, max(0.0, 100.0 - 10 * i)) for i in range(0, 12)]
    eng = Engine()
    eng.add({"__name__": "queue_depth"}, g)
    T = 165 * S
    r_bad = eng.eval(Parser("rate(queue_depth[2m])").parse(), T)[0][1]
    d_ok = eng.eval(Parser("deriv(queue_depth[2m])").parse(), T)[0][1]
    print(f"rate(queue_depth[2m]) = {r_bad:+.3f}/s (each decrease treated as a counter reset)")
    print(f"deriv(queue_depth[2m]) = {d_ok:+.3f}/s (least-squares slope; the right tool for gauges)")
    checks.append(("rate on gauge misleads", r_bad > 0 > d_ok))
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:rate_math_lab.py -->
```text
== 1. rate(x[1m]) at T=10m, 15 s scrapes, +30 per scrape (true rate 2/s) ==
samples in (T-1m, T] (left-open since 3.0): [(555, 1110.0), (570, 1140.0), (585, 1170.0), (600, 1200.0)]
raw delta 90 over sampled interval 45s; avg spacing 15s; gap to window start 15s, to end 0s; threshold 1.1*avg = 16.5s
both gaps < threshold -> extrapolate to the edges: increase = 90 * (45+15+0)/45 = 120.0; rate = 120.0/60 = 2.0000/s
a 2.x-style left-closed window would hold 5 samples (raw delta 120 over 60 s): same rate here, different sample set

== 2. increase() of an integer counter is not an integer ==
aligned scrapes, increase(x[1m]) at 10m: 4 samples, raw delta 3 -> 4.0000
aligned scrapes, increase(x[50s]) at 10m: 4 samples, raw delta 3 -> 3.3333
aligned scrapes, increase(x[40s]) at 10m: 3 samples, raw delta 2 -> 2.6667
0-400 ms scrape jitter, increase(x[1m]) at 600/603/607 s: 4.0217, 3.9861, 3.9861

== 3. Counter reset, half-spacing extrapolation and the zero-point clamp ==
samples [100.0, 110.0, 5.0, 15.0] at 0/15/30/45 s (window (0, 60s]): sample at t=0 is EXCLUDED (left-open); raw 15-110 = -95, +110 for the reset = 15 over 30 s -> increase = 30.0000
series first seen 30 s into the window (3, 6, 9): the 30 s gap exceeds 1.1 x 15 s, so it is extrapolated only half a spacing: 6 x (30+7.5)/30 = 7.5000
series 1, 11, 21: half a spacing back would imply a negative count; the zero point is 1.5 s back, so 20 x (30+1.5)/30 = 21.0000 (= the last value: counted from zero)

== 4. Monte Carlo: increase() vs true events, Poisson 2 events/s, 15 s scrapes ==
 window  mean est  mean true    bias    RMSE  RMSE %  empty
    30s      60.1       60.3   -0.15    7.69  12.8%   0.4%
    45s      89.5       89.7   -0.14    6.50   7.2%   0.0%
    60s     120.2      120.3   -0.08    6.33   5.3%   0.0%
   120s     240.8      240.9   -0.04    5.75   2.4%   0.0%
   300s     602.9      602.5   +0.43    5.68   0.9%   0.0%

== 5. irate vs rate on a burst (counter +2/s, then +200/s for 30 s) ==
     T  rate[5m]  irate[5m]  rate[1m]
  435s       2.0        2.0       2.0
  450s      12.4      200.0      65.0
  465s      22.8      200.0     115.0
  480s      22.8        2.0     115.5
  495s      22.8        2.0      68.0
  540s      22.8        2.0       2.0
  750s       2.0        2.0       2.0

== 6. rate() on a gauge (queue depth draining 100 -> 0) ==
rate(queue_depth[2m]) = +1.429/s (each decrease treated as a counter reset)
deriv(queue_depth[2m]) = -0.611/s (least-squares slope; the right tool for gauges)

checks: 9/9 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Recording rules for rates (the only place a `rate()` should be computed twice)

```yaml
groups:
  - name: http-rates
    interval: 30s                     # >= scrape_interval; aligned evaluations
    rules:
      # level:metric:operations naming (Folder 04). Window = 4 x 30s scrape = 2m minimum; 5m chosen
      - record: job_route_code:http_server_requests:rate5m
        expr: |
          sum by (job, route, code) (
            rate(http_server_requests_seconds_count[5m])
          )
      - record: job:http_server_requests:rate5m
        expr: sum by (job) (job_route_code:http_server_requests:rate5m)
      - record: job:http_server_errors:ratio_rate5m
        expr: |
          sum by (job) (job_route_code:http_server_requests:rate5m{code=~"5.."})
            / sum by (job) (job_route_code:http_server_requests:rate5m)
      # Gauges: slope, not rate
      - record: instance_mountpoint:node_filesystem_avail_bytes:deriv1h
        expr: deriv(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}[1h])
  - name: capacity-alerts
    rules:
      - alert: DiskWillFillIn4h
        expr: |
          predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}[6h], 4 * 3600) < 0
            and node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}
              / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"} < 0.25
        for: 30m
        labels: {severity: warning}
        annotations:
          summary: "{{ $labels.instance }}:{{ $labels.mountpoint }} predicted full within 4h"
```

### 2.2 Query-engine limits that protect the server

```yaml
# Flags (Deployment args), not config file:
#   --query.lookback-delta=5m      >= 2x the LONGEST scrape interval in the fleet
#   --query.timeout=2m             default; lower for the Grafana-facing tier
#   --query.max-samples=50000000   default; samples loaded per query (not series)
#   --query.max-concurrency=20     default
#   --enable-feature=promql-per-step-stats   # optional: stats=all shows samplesReadPerStep
global:
  query_log_file: /prometheus/query.log     # every query with timings: find the expensive panels
```

### 2.3 Grafana panel queries that are correct by construction

```promql
# Throughput: rate over a Grafana-computed window that always holds >= 4 scrapes
sum by (route) (rate(http_server_requests_seconds_count{job="checkout"}[$__rate_interval]))

# "Right now" panel at high zoom: irate is fine for display, never for alerts
sum by (route) (irate(http_server_requests_seconds_count{job="checkout"}[$__rate_interval]))

# Counts over a dashboard time range: increase over $__range is an ESTIMATE (non-integer)
sum(increase(orders_created_total{job="checkout"}[$__range]))

# Restarts in the last hour: resets() on a counter, changes() on a "start time" gauge
sum by (pod) (changes(process_start_time_seconds{job="checkout"}[1h]))
```

---

## 3. Failure modes and FinOps debugging

### F1. Empty or gappy rate panels after a scrape-interval change

**Symptom.** After moving a job from 15 s to 60 s scrapes (to save cost), throughput panels show gaps or nothing; alerts using `rate(x[1m])` never fire.

**Signature.** `count_over_time(x[1m])` is 0–1; `prometheus_target_interval_length_seconds{interval="1m"}` exists for the job; dashboards hard-code `[1m]`.

**Root cause.** A left-open 1 m window holds at most one 60 s sample; `rate()` needs two. (In 2.x the closed window sometimes caught two, which hid the problem.)

**Fix.** Use `$__rate_interval` in Grafana; rewrite rules to windows ≥ 4 × the new interval (`[4m]`+); for alerts, re-derive `for:` durations.

**Prevention.** Lint rules and dashboards for `[Nm]` windows smaller than 4 × the job's scrape interval; treat a scrape-interval change as a schema change with a dashboard/rule migration.

### F2. Phantom traffic spikes from two processes exporting one counter

**Symptom.** `rate(requests_total[5m])` shows periodic spikes of 10–1000× during deploys or permanently for one job.

**Signature.** `resets(requests_total[5m]) > 0` continuously; the series has two alternating "counters" (e.g. two pods behind one target address, or `honor_labels: true` with a pushgateway, or a sidecar and the app both exposing the same name); values zig-zag.

**Root cause.** Every downward step is treated as a reset and the *entire* pre-reset value is added (§1.3). Interleaving two counters makes every other sample a "reset".

**Fix.** Ensure one series per counter: distinct `instance`/`pod` labels, stop double exposure, drop the duplicate in `metric_relabel_configs`.

**Prevention.** Alert on `resets(x[15m]) > 3` for counters that should be monotonic; review `honor_labels` usage.

### F3. Alert flapping from `irate()`

**Symptom.** A "high error rate" alert fires and resolves every few minutes; on-call fatigue.

**Signature.** The expression uses `irate()`; `ALERTS_FOR_STATE` toggles; the error-rate panel built with `rate()` looks smooth.

**Root cause.** `irate` reflects only the last interval (L2 §5): one bad scrape interval crosses the threshold, the next one does not.

**Fix.** `rate()` over ≥ 5 m (or SLO burn-rate windows, Folder 04) plus `for:`/`keep_firing_for:`.

**Prevention.** Rule linting: reject `irate` in alerting and recording rules.

### F4. `rate()` applied to a gauge

**Symptom.** "Consumer throughput" computed as `rate(kafka_consumergroup_lag[5m])` is always positive even while lag shrinks.

**Signature.** The metric has no `_total` suffix, type metadata `gauge`; values go up and down.

**Root cause.** Decreases are counted as resets (§1.3; L2 §6).

**Fix.** `deriv(lag[5m])` (or `delta`) for gauges; export a counter (`records_consumed_total`) for throughput.

**Prevention.** Naming (`_total` only on counters); with `type-and-unit-labels` enabled, lint `rate()` on `__type__="gauge"`.

### F5. Billing or capacity reports built on `increase()`

**Symptom.** Monthly "requests served" numbers differ by a few percent from the access logs and are non-integers; finance asks which is right.

**Signature.** `sum(increase(x[30d]))` or `[1d]` windows over many short-lived pods.

**Root cause.** `increase` is an extrapolated estimate; each pod's first interval after start and last interval before death is guessed (half-spacing rule), and counters that die before their first scrape are never seen.

**Fix.** Use logs/events for billing; for metrics, record `increase` per short window into a recording rule and sum those, and accept a documented error bound.

**Prevention.** Label metrics-derived numbers as estimates in reports; enable start-timestamp ingestion where accuracy matters.

### F6. Dead pods linger on dashboards for 5 minutes

**Symptom.** After a rollout, old pod series remain visible for up to 5 minutes; capacity sums double-count.

**Signature.** Series of terminated pods keep a flat last value until exactly 5 m after the last scrape; the job uses `honor_timestamps: true` with exposed timestamps or is federated.

**Root cause.** No staleness marker was written (targets that expose their own timestamps, federation without `track_timestamps_staleness`), so the lookback delta governs disappearance.

**Fix.** `track_timestamps_staleness: true`; stop exposing timestamps unless required.

**Prevention.** Federate only aggregates; test target removal in staging and check that `up{pod="old"}` disappears within one scrape.

### F7. The 2.x → 3.x upgrade changed numbers on edge-aligned queries

**Symptom.** After upgrading to 3.x, some recording rules evaluated at exact scrape boundaries changed slightly; a few `[30s]` rates became empty.

**Signature.** Rules with windows equal to 2 × scrape interval; evaluation aligned with scrape times.

**Root cause.** Left-open range selection excludes the sample at exactly `T − r` (2.x included it), dropping a sample at aligned boundaries (L2 §1).

**Fix.** Widen windows to ≥ 4 × scrape interval; re-baseline alert thresholds that depended on the old sample count.

**Prevention.** Run `promtool test rules` fixtures against both versions in CI before major upgrades.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "What does rate(x[5m]) return, precisely?"</b></summary>

**Initial Prompt.** Define `rate(http_requests_total[5m])` evaluated at T, including edge cases.

**L5 Textbook Answer.** The per-second average increase of the counter over the last 5 minutes, handling counter resets.

**Why L5 Fails at 3 AM or on the Bill.** It cannot explain non-integer increases, empty results for short windows, spikes from interleaved counters, or why a series born inside the window reports less than its value. Each of those becomes a 3 AM argument about whether "Prometheus is wrong".

**L7 Principal Defense.** It selects samples in `(T−5m, T]` (left-open, staleness markers excluded), needs ≥ 2, computes Δ = last − first plus each pre-reset value, then extrapolates to the window edges if the edge gaps are < 1.1 × the average spacing — otherwise only half a spacing — never extrapolating a counter below zero, and divides by 300 s. It is an unbiased estimator whose relative error is ~one scrape interval / window (5% at 4 intervals, <1% at 20). I can derive any panel value from the raw samples by hand, and I size windows from that error budget.
</details>

<details><summary><b>Q2 · "rate or irate for this alert?"</b></summary>

**Initial Prompt.** We want to page fast on error spikes. irate reacts faster, so use it?

**L5 Textbook Answer.** Yes, irate is more responsive because it uses the latest data, so it detects spikes sooner.

**Why L5 Fails at 3 AM or on the Bill.** irate uses two samples; it flaps on single bad intervals, forgets a burst one interval later, and its value depends on which two samples happen to be last. You get both false pages and missed incidents.

**L7 Principal Defense.** Speed comes from *burn-rate* design, not irate: a short window paired with a long one (5 m AND 1 h at 14.4× burn, Folder 04) detects a hard outage in about a minute while refusing to page on blips. irate stays on "right now" dashboards. I'd show the L2 burst table: irate is 200 then 2 within 30 s; rate[5m] holds 22.8 for the whole window.
</details>

<details><summary><b>Q3 · "Why is increase() returning 3.33 for a counter that only goes up by 1?"</b></summary>

**Initial Prompt.** Our test asserts `increase(jobs_total[50s]) == 3` and fails with 3.333.

**L5 Textbook Answer.** Floating-point rounding; round the result.

**Why L5 Fails at 3 AM or on the Bill.** It is not rounding — it is extrapolation: 3 observed increments over 45 s are scaled to the 50 s window. Rounding hides a systematic estimator property and will be wrong in the next test with jittered scrapes.

**L7 Principal Defense.** increase = Δ × (sampled + toStart + toEnd)/sampled = 3 × 50/45 = 3.333 (L2 §2). Exact integer counts need either a window that is a multiple of the scrape interval *and* aligned scrapes, `anchored` selectors (experimental), or event counting in logs. In tests I assert with tolerance, or use `promtool test rules` with series on an aligned grid.
</details>

<details><summary><b>Q4 · "How do counter resets work, and when do they lie?"</b></summary>

**Initial Prompt.** Explain counter reset handling and its failure modes.

**L5 Textbook Answer.** If the value decreases, Prometheus assumes a restart and continues counting from the new value.

**Why L5 Fails at 3 AM or on the Bill.** It omits *how* (the pre-reset value is added), so it cannot diagnose phantom spikes from interleaved counters, lost increments before a restart, or `rate()` on gauges.

**L7 Principal Defense.** For each decrease, Prometheus adds the previous value to Δ — assuming the counter went to zero and climbed to the new value. It lies when (1) two processes share a series (every zig-zag adds a full counter value — huge spikes), (2) the process counted events after the last scrape and died (lost), (3) a gauge is passed (every decrease is a "reset"). Mitigations: unique series per process, `resets()` alerts, start timestamps for (2), naming discipline for (3).
</details>

<details><summary><b>Q5 · "Pick the rate window for a 30-second scrape interval."</b></summary>

**Initial Prompt.** Teams use `[1m]` everywhere. Is that right at 30 s scrapes?

**L5 Textbook Answer.** 1 minute covers two scrapes, which is enough for rate.

**Why L5 Fails at 3 AM or on the Bill.** Two samples at best — and with left-open windows and jitter often one, so panels flicker empty; relative error ~13% at two intervals. Alerts built on it are noisy and miss.

**L7 Principal Defense.** ≥ 4 intervals → `[2m]` minimum, typically `[5m]` for alerts (≈2% error) and `$__rate_interval` for dashboards. The math (L2 §4): error ∝ 1/window; empties vanish at ≥ 3 intervals. I'd also standardize scrape intervals per tier so window conventions are global, not per team.
</details>

<details><summary><b>Q6 · "Why do dead pods stay on the dashboard?"</b></summary>

**Initial Prompt.** After deploys, old pods linger for 5 minutes and inflate our replica-count panel.

**L5 Textbook Answer.** Prometheus keeps the last value for 5 minutes because of the lookback window; it is expected.

**Why L5 Fails at 3 AM or on the Bill.** Normally staleness markers remove them within one scrape; a 5-minute linger means markers are *not* being written — a symptom of exposed timestamps, federation or a broken scrape path, which also distorts sums and alerts.

**L7 Principal Defense.** Staleness markers are written when a series or target disappears; they hide the series immediately (L1 implements both behaviours; Folder 02 File 02's L3 §6 shows marker vs lookback). Lingering means `honor_timestamps` with exposed timestamps or federation — fix with `track_timestamps_staleness: true`, don't federate raw series, and avoid exposing timestamps.
</details>

<details><summary><b>Q7 · "Should we lower --query.lookback-delta to 1m for fresher data?"</b></summary>

**Initial Prompt.** Lookback 5m makes dashboards show stale values. Lower it?

**L5 Textbook Answer.** Yes, a shorter lookback shows only fresh samples.

**Why L5 Fails at 3 AM or on the Bill.** Lookback applies to *every* instant selector: any series scraped at ≥ 1 m (or with one missed scrape) disappears intermittently, breaking ratios, `absent()` alerts and joins with info metrics scraped every few minutes.

**L7 Principal Defense.** Staleness markers already solve freshness for disappearing series; lookback is the safety net for irregular scrapes. Keep it ≥ 2× the longest scrape interval (default 5 m). For "freshness", alert on `time() - timestamp(x) > N` or `absent_over_time`, explicitly.
</details>

<details><summary><b>Q8 · "How would you prove the PromQL engine semantics to a skeptical team?"</b></summary>

**Initial Prompt.** Your team doubts that rate() extrapolation is the cause of a billing mismatch. Prove it.

**L5 Textbook Answer.** Point them to the docs that say rate extrapolates.

**Why L5 Fails at 3 AM or on the Bill.** Docs are qualitative; the dispute is quantitative ("is 3% expected?"). Without a reproduction, the argument stalls and someone "fixes" it by rounding.

**L7 Principal Defense.** Reproduce with the engine's own semantics: load the raw samples (`promtool tsdb dump`) into a promqltest script and run it, or use a faithful port (L1, which passes every upstream case it attempts) to compute the window by hand and show Δ, spacing, edge gaps and factor. Then quantify the estimator's error with a Monte Carlo at the real scrape interval (L2 §4) and decide whether the use case tolerates it — billing doesn't, so billing moves to events.
</details>

---

## 5. Invariants checklist

- [ ] Every `rate`/`increase`/`delta` window is ≥ 4 × the scrape interval of its inputs; dashboards use `$__rate_interval`.
- [ ] No `irate` in recording or alerting rules.
- [ ] No `rate`/`increase` on gauges (`deriv`/`delta` instead); `_total` only on counters.
- [ ] `resets()` is monitored on business-critical counters to catch interleaved exporters.
- [ ] `--query.lookback-delta` ≥ 2 × the longest scrape interval; freshness is alerted explicitly, not via lookback.
- [ ] Billing-grade counts come from events, not `increase()`; metric-derived counts are labelled as estimates.
- [ ] Scrape-interval changes trigger a rule/dashboard window review (left-open windows in 3.x).
- [ ] Experimental selectors (`anchored`, `smoothed`) or start-timestamp rates are used only with their feature flags documented and, for `smoothed`, a rule `query_offset`.

---

## 6. References

- PromQL engine: <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/engine.go>
- PromQL functions (`extrapolatedRate`, `instantValue`, `linearRegression`): <https://github.com/prometheus/prometheus/blob/v3.15.1/promql/functions.go>
- promqltest language and corpus: <https://github.com/prometheus/prometheus/tree/v3.15.1/promql/promqltest>
- PromQL basics (selectors, lookback, staleness): <https://prometheus.io/docs/prometheus/latest/querying/basics/>
- Function reference: <https://prometheus.io/docs/prometheus/latest/querying/functions/>
- Feature flags (extended range selectors, start timestamps): <https://prometheus.io/docs/prometheus/latest/feature_flags/>
- Extended range selectors design doc: <https://github.com/prometheus/proposals/blob/main/proposals/2025-04-04_extended-range-selectors-semantics.md>
- Migration to 3.0 (left-open ranges): <https://prometheus.io/docs/prometheus/latest/migration/>
- Grafana `$__rate_interval`: <https://grafana.com/docs/grafana/latest/datasources/prometheus/template-variables/>
