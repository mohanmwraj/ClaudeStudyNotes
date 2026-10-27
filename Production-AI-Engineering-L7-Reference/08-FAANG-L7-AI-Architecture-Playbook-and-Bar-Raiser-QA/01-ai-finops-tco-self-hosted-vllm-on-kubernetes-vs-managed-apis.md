# 01 · AI FinOps: The TCO of Self-Hosted vLLM on Kubernetes vs Managed APIs (Bedrock, Vertex)

> **Folder:** `08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/` · **File 1 of 3**
> **Anchoring material:** Folder 01 (roofline, KV capacity) and Folder 02 (goodput, disaggregation,
> quantization) of this KB · the FinOps Foundation framework (unit economics, commitment management) · public pricing
> pages of managed model services (Amazon Bedrock, Google Vertex AI) and GPU cloud instances, **used only as the shape
> of the inputs**: every price below is an assumption to be replaced by your contract rates.
> **Code baseline:** Python 3.10+ (reuses `roofline.py` from Folder 01) · Java 21 (reuses `RooflinePlanner.java` from
> Folder 01).
> **Previous folder:** [07 · The LLM gateway](../07-Production-Code-Blueprints-Java-and-Python/04-llm-gateway-semantic-cache-token-rate-limiting-and-otel-genai.md) ·
> **Next:** [02 · 25 bar-raiser scenarios](02-twenty-five-l7-bar-raiser-scenarios-with-l5-vs-l7-defenses.md)

---

## 0. The thesis in one paragraph

"Self-hosting is cheaper" and "APIs are cheaper" are both wrong as general statements. Cost per token is
`fleet $ / tokens served`, so self-hosting is a **fixed-cost business**:

- GPUs are paid by the hour whether or not traffic arrives;
- the people who run the platform are paid every month;
- the throughput per GPU is set by physics: the decode batch under the TPOT SLO, KV capacity and prefill compute.

An API is a **variable-cost business** priced per token. The crossover comes from three numbers: **volume,
utilization and workload shape.** With this file's assumptions (a hosted open 70B model at $0.70/$0.90 per 1M
tokens; H100 at $2.50–$6.00 per GPU-hour; 2 engineers), self-hosting Llama-3-70B loses at 20 req/s
($108K vs $51K/month) and wins from about 100 req/s. It beats a frontier proprietary API at every volume tested.

Inside self-hosting the levers are bigger than the price tier:

| Lever | Cost multiplier |
|---|---|
| No autoscaling | **2.19×** |
| On-demand instead of a 3-year commitment | **2.22×** |
| FP8 + FP8 KV + MTP | **0.46×** |
| 8K-token RAG prompts instead of 1K chat | **5.9×** (and the API bill grows almost as much) |

The commitment decision has a closed form: **commit the k-th replica if it is needed in at least
`p_commit / p_on-demand` of all hours** (58% here).

---

## 1. First principles

### 1.1 Capacity is physics, and prefill often dominates

A replica's sustainable request rate, composed serially (conservative):

```text
GPU-seconds per request = prefill(prompt) + output_tokens × step_time / batch
requests/s per replica  = 1 / (GPU-seconds per request)
```

- `batch` is the largest decode batch whose step time meets the TPOT SLO and whose KV fits in HBM (Folder 01 File
  02).
- `prefill` is compute-bound: about `2 × params × prompt / (TP × peak × MFU)` plus two all-reduces per layer.

For Llama-3-70B BF16 on 8×H100 TP8:

| Workload | Batch | Prefill | req/s/replica | Bound by |
|---|---|---|---|---|
| Chat 1K in / 300 out, TPOT 50 ms | 1,090 | 49 ms | 15.9 | prefill (49 ms vs 13.8 ms of decode share) |
| RAG 8K in / 300 out | 166 | 402 ms | 2.2 | KV capacity (1.36M tokens / 8,150) and prefill |
| Agent 4K in / 1K out | 301 | 196 ms | 3.5 | KV capacity and prefill |

Three consequences:

- **Prompt length is the cost driver.** 8K RAG prompts cut capacity 7× against 1K chat. Prefix caching of shared
  system prompts and tool blocks (Folder 01 File 03) is the cheapest capacity there is.
- **A tighter TPOT SLO barely matters for chat** (15.9 → 15.8 req/s at 30 ms), because prefill, not decode, sets the
  per-request GPU time.
- **The serial composition is conservative.** Chunked prefill overlaps prefill compute with memory-bound decode
  steps (Folder 02 File 01), and disaggregation (Folder 02 File 02) separates them. Measured goodput on the real
  stack is the number to plan with.

The Python and Java listings compute this independently (15.88 and 15.95 req/s) from the same roofline constants.

### 1.2 Utilization is the multiplier nobody budgets

Traffic is diurnal and weekly. A fleet provisioned for peak at a 70% target utilization, plus N+1, runs at
`mean / provisioned`: **21%** in the lab for a peak/mean of 2.5. Autoscaling that tracks the curve lifts that to
38% and cuts cost 1.45–2.2×.

GPU fleets autoscale slowly. Model load is tens of seconds to minutes, and replicas are 8-GPU units, so scale-out
must lead demand. Serve the trough with committed capacity and the peak with on-demand.

### 1.3 The commitment decision has a closed form

Let replica-hour prices be `p_c` (committed, paid every hour) and `p_o` (on-demand, paid when used). The k-th replica
is needed in a fraction `f_k` of hours. Committing it costs `p_c` per hour; leaving it on-demand costs `f_k·p_o` per
hour. **Commit it iff `f_k ≥ p_c / p_o`.**

With the assumed $3.50 vs $6.00 per GPU-hour (ratio 0.583), the planner's brute-force search over every commitment
level lands exactly on the closed form:

| Weekly mean demand | Replicas needed per hour | Commit | Saving vs all on-demand | Saving vs committing for peak |
|---|---|---|---|---|
| 40 req/s | 2–10 | 4 | 18% | 29% |
| 200 req/s | 3–46 | 12 | 10% | 35% |

Spot or preemptible capacity extends the same logic to the top of the curve for interruptible work (batch,
evaluation, embedding backfills). Interactive serving keeps its N+1 on non-preemptible capacity.

### 1.4 The API side and the fixed costs

API cost is `N × (prompt × p_in × (1 − cached_fraction × discount) + output × p_out)`. Prompt caching discounts can
take a third off an input-heavy bill (the lab's 50% cached input: $51K → $34K for the open model; ⚠ verify each
provider's cache pricing and its minimum cacheable prefix). The self-hosted side carries costs an API bill hides:

- **People.** 2 engineers at $300K loaded is $50K/month, which is the entire API bill at 20 req/s.
- **Node and platform overhead** (CPU, network, storage, K8s, observability, the gateway): +20% here.
- **Capacity risk.** GPU availability, driver and runtime upgrades, model-release churn.
- **Evaluation and safety work,** which both options need; managed services bundle some guardrails.

### 1.5 The decision is rarely binary

Most mature platforms are hybrid, routed by the gateway (Folder 07 File 04):

- **Frontier tasks** (hard reasoning, long-tail quality) go to proprietary APIs: per-token prices are high, but no
  self-hosted open model matches them.
- **High-volume, well-defined tasks** (classification, extraction, RAG answering, routing) go to self-hosted open
  models, quantized (Folder 02 File 03), with prefix caching, on committed capacity.
- **Bursty or experimental traffic** goes to managed open-model endpoints.

The gateway's single API, quota model and telemetry keep that routing reversible as prices move.

---

## 2. Production code blueprints

### 2.1 Python: capacity from physics, monthly cost, break-even and sensitivity

```python
"""llm_tco_model.py - self-hosted vLLM on Kubernetes vs a managed per-token API, from first principles.

Capacity comes from Folder 01's roofline model (roofline.py): the largest decode batch that meets the TPOT SLO and
fits in KV memory, plus prefill time, gives requests/s per 8xH100 replica for a given workload shape. Cost comes from
GPU-hour prices, node overhead, the utilization that a diurnal traffic curve and N+1 redundancy allow, and the people
who run it. Every PRICE below is an ASSUMPTION for illustration (prices move monthly); substitute your contract rates.
"""
from __future__ import annotations

import math

from roofline import H100, LLAMA3_70B, decode_step, max_batch_for_itl, prefill

# ---------------------------------------------------------------------- assumptions (substitute your own)
GPU_HOUR = {"on-demand": 6.00, "1-yr commit": 3.50, "3-yr commit": 2.50}   # $ per H100-hour (assumed)
NODE_OVERHEAD = 0.15             # CPU, memory, network, storage around each GPU node
PLATFORM_OVERHEAD = 0.05         # K8s control plane, observability, gateway
ENGINEERS, LOADED_COST = 2.0, 300_000   # FTE to run the inference platform; $/FTE-year (assumed)
API = {"hosted open 70B": (0.70, 0.90), "frontier proprietary": (3.00, 15.00)}   # $ per 1M (input, output)
HOURS = 730


def replica_capacity(prompt: int, output: int, tpot_slo: float) -> dict:
    """Requests/s one TP8 replica sustains: prefill seconds + the replica's share of decode time per request."""
    ctx = prompt + output // 2
    batch, step = max_batch_for_itl(LLAMA3_70B, H100, 8, ctx, tpot_slo)
    pre = prefill(LLAMA3_70B, H100, 8, prompt).total_s
    decode_share = output * step / batch                                  # GPU-seconds of decode per request
    rps = 1.0 / (pre + decode_share)
    return {"batch": batch, "step_ms": step * 1e3, "prefill_ms": pre * 1e3, "rps": rps,
            "tok_s_gpu": rps * (prompt + output) / 8, "out_tok_s_gpu": rps * output / 8}


def self_hosted_month(req_per_s_avg: float, peak_to_avg: float, cap_rps: float, tier: str,
                      target_util: float = 0.7, autoscale: bool = True) -> dict:
    """Replicas sized for peak at target utilization plus N+1; with autoscaling the fleet follows a diurnal curve."""
    peak = req_per_s_avg * peak_to_avg
    peak_replicas = math.ceil(peak / (cap_rps * target_util)) + 1
    if autoscale:                                                          # sinusoidal day: replicas track demand
        hours = [req_per_s_avg * (1 + (peak_to_avg - 1) * (math.sin(2 * math.pi * h / 24) + 1) / 2
                                  - (peak_to_avg - 1) / 2) for h in range(24)]
        scale = req_per_s_avg / (sum(hours) / 24)
        replica_hours = sum(math.ceil(max(x * scale, 0.0) / (cap_rps * target_util)) + 1 for x in hours) / 24 * HOURS
    else:
        replica_hours = peak_replicas * HOURS
    gpu_hours = replica_hours * 8
    infra = gpu_hours * GPU_HOUR[tier] * (1 + NODE_OVERHEAD + PLATFORM_OVERHEAD)
    people = ENGINEERS * LOADED_COST / 12
    util = req_per_s_avg * HOURS / (replica_hours * cap_rps)
    return {"peak_replicas": peak_replicas, "gpu_hours": gpu_hours, "infra": infra, "people": people,
            "total": infra + people, "util": util}


def api_month(req_per_s_avg: float, prompt: int, output: int, price: tuple, cached_frac: float = 0.0,
              cache_discount: float = 0.9) -> float:
    n = req_per_s_avg * 3600 * HOURS
    pin, pout = price
    input_cost = n * prompt / 1e6 * pin * (1 - cached_frac * cache_discount)
    return input_cost + n * output / 1e6 * pout


def main() -> None:
    print("== 1. Capacity of one 8xH100 TP8 replica, Llama-3-70B BF16 (roofline model, Folder 01) ==")
    print(f"  {'workload':28} {'TPOT SLO':>8} {'batch':>6} {'step ms':>8} {'prefill ms':>10} {'req/s':>7} {'tok/s/GPU':>10}")
    shapes = {"chat 1K in / 300 out": (1_000, 300), "RAG 8K in / 300 out": (8_000, 300),
              "agent 4K in / 1K out": (4_000, 1_000)}
    caps = {}
    for name, (p, o) in shapes.items():
        for slo in (0.05, 0.03):
            c = replica_capacity(p, o, slo)
            caps[(name, slo)] = c
            print(f"  {name:28} {slo * 1e3:>6.0f}ms {c['batch']:>6} {c['step_ms']:>8.1f} {c['prefill_ms']:>10.0f} "
                  f"{c['rps']:>7.2f} {c['tok_s_gpu']:>10.0f}")
    chat = caps[("chat 1K in / 300 out", 0.05)]
    rag = caps[("RAG 8K in / 300 out", 0.05)]
    assert rag["rps"] < chat["rps"] and caps[("chat 1K in / 300 out", 0.03)]["rps"] < chat["rps"]

    print("\n== 2. Monthly cost at 20 req/s average (52M requests/month), chat shape, peak/avg 2.5 ==")
    prompt, out = shapes["chat 1K in / 300 out"]
    rows = []
    for tier in GPU_HOUR:
        for auto in (False, True):
            m = self_hosted_month(20, 2.5, chat["rps"], tier, autoscale=auto)
            rows.append((f"self-host {tier}{' + autoscale' if auto else ''}", m["total"], m["util"]))
    for name, price in API.items():
        rows.append((f"API {name}", api_month(20, prompt, out, price), float("nan")))
        rows.append((f"API {name}, 50% cached input", api_month(20, prompt, out, price, 0.5), float("nan")))
    for name, total, util in rows:
        u = f"{util:5.0%}" if util == util else "   - "
        print(f"  {name:44} ${total:>11,.0f}/month   fleet utilization {u}")
    sh = min(r[1] for r in rows if r[0].startswith("self-host"))
    open_api = api_month(20, prompt, out, API["hosted open 70B"])
    frontier = api_month(20, prompt, out, API["frontier proprietary"])
    assert open_api < sh < frontier

    print("\n== 3. Break-even volume: self-host (3-yr commit, autoscale) vs the hosted open-model API ==")
    print(f"  {'avg req/s':>9} {'requests/month':>15} {'self-host $':>12} {'API $':>12} {'cheaper':>10} {'$/1M tok self':>14}")
    breakeven = None
    for rps in (5, 20, 50, 100, 200, 400, 800):
        m = self_hosted_month(rps, 2.5, chat["rps"], "3-yr commit")
        a = api_month(rps, prompt, out, API["hosted open 70B"])
        n = rps * 3600 * HOURS
        per_m = m["total"] / (n * (prompt + out) / 1e6)
        cheaper = "self-host" if m["total"] < a else "API"
        if cheaper == "self-host" and breakeven is None:
            breakeven = rps
        print(f"  {rps:>9} {n:>15,.0f} {m['total']:>12,.0f} {a:>12,.0f} {cheaper:>10} {per_m:>14.3f}")
    print(f"  -> with these assumptions self-hosting the open model wins from ~{breakeven} req/s average; against the"
          f" frontier API it wins at every volume above")
    assert breakeven is not None and breakeven >= 50

    print("\n== 4. What moves the answer (at 200 req/s, chat shape) ==")
    base = self_hosted_month(200, 2.5, chat["rps"], "3-yr commit")["total"]
    for label, total in (
            ("baseline (3-yr, autoscale, 70% target util)", base),
            ("no autoscaling (provisioned for peak 24x7)", self_hosted_month(200, 2.5, chat["rps"], "3-yr commit", autoscale=False)["total"]),
            ("on-demand GPUs", self_hosted_month(200, 2.5, chat["rps"], "on-demand")["total"]),
            ("FP8 + FP8 KV + MTP (~3x capacity, Folder 02 advisor)", self_hosted_month(200, 2.5, chat["rps"] * 3, "3-yr commit")["total"]),
            ("RAG 8K prompts instead of chat", self_hosted_month(200, 2.5, rag["rps"], "3-yr commit")["total"]),
            ("tighter TPOT SLO (30 ms)", self_hosted_month(200, 2.5, caps[("chat 1K in / 300 out", 0.03)]["rps"], "3-yr commit")["total"])):
        print(f"  {label:54} ${total:>11,.0f}/month  ({total / base:4.2f}x)")
    print("\nall llm_tco_model self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== 1. Capacity of one 8xH100 TP8 replica, Llama-3-70B BF16 (roofline model, Folder 01) ==
  workload                     TPOT SLO  batch  step ms prefill ms   req/s  tok/s/GPU
  chat 1K in / 300 out             50ms   1090     50.0         49   15.88       2581
  chat 1K in / 300 out             30ms    640     30.0         49   15.81       2568
  RAG 8K in / 300 out              50ms    166     25.8        402    2.23       2315
  RAG 8K in / 300 out              30ms    166     25.8        402    2.23       2315
  agent 4K in / 1K out             50ms    301     27.8        196    3.46       2164
  agent 4K in / 1K out             30ms    301     27.8        196    3.46       2164

== 2. Monthly cost at 20 req/s average (52M requests/month), chat shape, peak/avg 2.5 ==
  self-host on-demand                          $    302,288/month   fleet utilization   21%
  self-host on-demand + autoscale              $    188,408/month   fleet utilization   38%
  self-host 1-yr commit                        $    197,168/month   fleet utilization   21%
  self-host 1-yr commit + autoscale            $    130,738/month   fleet utilization   38%
  self-host 3-yr commit                        $    155,120/month   fleet utilization   21%
  self-host 3-yr commit + autoscale            $    107,670/month   fleet utilization   38%
  API hosted open 70B                          $     50,983/month   fleet utilization    - 
  API hosted open 70B, 50% cached input        $     34,427/month   fleet utilization    - 
  API frontier proprietary                     $    394,200/month   fleet utilization    - 
  API frontier proprietary, 50% cached input   $    323,244/month   fleet utilization    - 

== 3. Break-even volume: self-host (3-yr commit, autoscale) vs the hosted open-model API ==
  avg req/s  requests/month  self-host $        API $    cheaper  $/1M tok self
          5      13,140,000       85,040       12,746        API          4.978
         20      52,560,000      107,670       50,983        API          1.576
         50     131,400,000      155,120      127,458        API          0.908
        100     262,800,000      233,230      254,916  self-host          0.683
        200     525,600,000      390,910      509,832  self-host          0.572
        400   1,051,200,000      704,080    1,019,664  self-host          0.515
        800   2,102,400,000    1,333,340    2,039,328  self-host          0.488
  -> with these assumptions self-hosting the open model wins from ~100 req/s average; against the frontier API it wins at every volume above

== 4. What moves the answer (at 200 req/s, chat shape) ==
  baseline (3-yr, autoscale, 70% target util)            $    390,910/month  (1.00x)
  no autoscaling (provisioned for peak 24x7)             $    855,920/month  (2.19x)
  on-demand GPUs                                         $    868,184/month  (2.22x)
  FP8 + FP8 KV + MTP (~3x capacity, Folder 02 advisor)   $    180,670/month  (0.46x)
  RAG 8K prompts instead of chat                         $  2,321,760/month  (5.94x)
  tighter TPOT SLO (30 ms)                               $    392,370/month  (1.00x)

all llm_tco_model self-checks passed
```

### 2.2 Java 21: the committed vs on-demand mix for a weekly demand curve

```java
// CapacityMixPlanner.java - the FinOps decision an L7 owns for a self-hosted fleet: how many replicas to COMMIT
// (reserved, always paid) and how much to buy ON DEMAND (paid per hour used), for a weekly demand curve.
// Capacity per replica comes from Folder 01's roofline (RooflinePlanner: decode batch under the TPOT SLO, KV capacity)
// plus prefill FLOPs. The optimum has a closed form - commit the k-th replica iff it is needed in at least
// p_commit / p_on_demand of all hours - and a brute-force search over every commitment level confirms it.
// Prices are ASSUMPTIONS (substitute contract rates). Build: javac --release 21 (uses RooflinePlanner.java)
package dev.l7.ai.inference;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public final class CapacityMixPlanner {

    record Prices(double committed, double onDemand) {}                     // $ per replica-hour (8 GPUs)

    /** Requests/s one TP8 replica sustains for `prompt` in / `output` out under a TPOT SLO (serial prefill + decode). */
    static double replicaRps(int prompt, int output, double tpotSlo) {
        var md = RooflinePlanner.LLAMA3_70B;
        var g = RooflinePlanner.H100;
        long cap = RooflinePlanner.kvCapacityTokens(md, g, 8, 0.9, 3.0 * (1L << 30));
        long ctx = prompt + output / 2;
        int batch = RooflinePlanner.maxBatchForItl(md, g, 8, ctx, tpotSlo, cap);
        double step = RooflinePlanner.decodeStep(md, g, 8, batch, (long) batch * ctx).totalSeconds();
        int tp = 8;
        double gemms = 2.0 * md.nLayers() * md.layerParams() * prompt / tp / (g.bf16Flops() * 0.5);   // 50% MFU per rank
        double allReduce = g.arLatency() + 2.0 * (tp - 1) / tp * prompt * md.dModel() * 2.0 / g.arBusBw();
        double prefill = gemms + 2 * md.nLayers() * allReduce;               // two all-reduces per layer (Megatron TP)
        return 1.0 / (prefill + output * step / batch);
    }

    /** 168 hourly demand points (req/s): base * max(0.15, 1 + A sin(...)) peaking mid-afternoon; weekends at 60%. */
    static double[] weeklyDemand(double base, double amplitude) {
        double[] d = new double[168];
        for (int h = 0; h < 168; h++) {
            double day = Math.max(0.15, 1 + amplitude * Math.sin(Math.PI * ((h % 24) - 8) / 12.0));
            d[h] = (h / 24 >= 5 ? 0.6 : 1.0) * base * day;
        }
        return d;
    }

    static int[] replicasNeeded(double[] demand, double capRps, double targetUtil) {
        int[] n = new int[demand.length];
        for (int h = 0; h < demand.length; h++) n[h] = (int) Math.ceil(demand[h] / (capRps * targetUtil)) + 1;   // N+1
        return n;
    }

    static double weeklyCost(int[] need, int committed, Prices p) {
        double c = 0;
        for (int n : need) c += committed * p.committed() + Math.max(0, n - committed) * p.onDemand();
        return c;
    }

    /** Closed form: commit replica k iff the fraction of hours needing >= k replicas is >= committed / on-demand. */
    static int closedForm(int[] need, Prices p) {
        double ratio = p.committed() / p.onDemand();
        int max = Arrays.stream(need).max().orElse(0), k = 0;
        for (int r = 1; r <= max; r++) {
            final int rr = r;
            double frac = Arrays.stream(need).filter(n -> n >= rr).count() / (double) need.length;
            if (frac >= ratio) k = r;
        }
        return k;
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        double cap = replicaRps(1_000, 300, 0.05);
        System.out.printf("replica capacity (Llama-3-70B BF16, 8xH100 TP8, 1K in / 300 out, TPOT 50 ms): %.2f req/s%n", cap);
        check(Math.abs(cap - 15.9) < 1.0, "agrees with llm_tco_model.py's Python roofline (~15.9 req/s)");

        Prices p = new Prices(8 * 3.50, 8 * 6.00);                            // assumed $/GPU-h: 1-yr commit vs on-demand
        System.out.printf("prices (assumed): committed $%.0f, on-demand $%.0f per replica-hour -> ratio %.3f%n",
                p.committed(), p.onDemand(), p.committed() / p.onDemand());
        for (double avg : new double[] {40, 200}) {
            double[] demand = weeklyDemand(avg, 1.5);
            double mean = Arrays.stream(demand).average().orElse(0), peak = Arrays.stream(demand).max().orElse(0);
            int[] need = replicasNeeded(demand, cap, 0.7);
            int max = Arrays.stream(need).max().orElse(0), min = Arrays.stream(need).min().orElse(0);
            List<String> curve = new ArrayList<>();
            int bestR = 0;
            double best = Double.MAX_VALUE;
            for (int r = 0; r <= max; r++) {
                double c = weeklyCost(need, r, p);
                if (c < best) { best = c; bestR = r; }
                if (r == 0 || r == min || r == max || r % Math.max(1, max / 6) == 0) curve.add(r + ":" + Math.round(c / 1000) + "K");
            }
            int cf = closedForm(need, p);
            double allOnDemand = weeklyCost(need, 0, p), allCommitted = weeklyCost(need, max, p);
            System.out.printf("%nweekday base %.0f req/s: weekly mean %.0f req/s, peak %.0f (peak/mean %.2f); replicas needed per hour %d..%d%n",
                    avg, mean, peak, peak / mean, min, max);
            System.out.println("  weekly cost by committed replicas: " + String.join("  ", curve));
            System.out.printf("  brute-force optimum %d committed (%,.0f $/week); closed form %d; all on-demand %,.0f; all committed %,.0f%n",
                    bestR, best, cf, allOnDemand, allCommitted);
            System.out.printf("  optimum saves %.0f%% vs all on-demand and %.0f%% vs committing for peak%n",
                    100 * (1 - best / allOnDemand), 100 * (1 - best / allCommitted));
            check(cf == bestR || Math.abs(weeklyCost(need, cf, p) - best) < 1e-6, "closed form matches brute force");
            check(best < allOnDemand && best < allCommitted, "the mix beats both extremes");
        }
        System.out.println("\nall CapacityMixPlanner self-checks passed");
    }
}
```

Output (verified; deterministic):

```text
replica capacity (Llama-3-70B BF16, 8xH100 TP8, 1K in / 300 out, TPOT 50 ms): 15.95 req/s
prices (assumed): committed $28, on-demand $48 per replica-hour -> ratio 0.583

weekday base 40 req/s: weekly mean 40 req/s, peak 100 (peak/mean 2.49); replicas needed per hour 2..10
  weekly cost by committed replicas: 0:41K  1:37K  2:34K  3:34K  4:34K  5:34K  6:36K  7:38K  8:41K  9:44K  10:47K
  brute-force optimum 4 committed (33,600 $/week); closed form 4; all on-demand 40,800; all committed 47,040
  optimum saves 18% vs all on-demand and 29% vs committing for peak

weekday base 200 req/s: weekly mean 201 req/s, peak 500 (peak/mean 2.49); replicas needed per hour 3..46
  weekly cost by committed replicas: 0:156K  3:145K  7:141K  14:141K  21:147K  28:159K  35:177K  42:200K  46:216K
  brute-force optimum 12 committed (139,872 $/week); closed form 12; all on-demand 155,520; all committed 216,384
  optimum saves 10% vs all on-demand and 35% vs committing for peak

all CapacityMixPlanner self-checks passed
```

---

## 3. Production failure modes and P99 debugging

### F1 · The self-hosted fleet costs 3× the business case

- **Signature:** fleet utilization of 20–30%; the GPUs are idle at night and on weekends.
- **Root cause:** sized for peak with no autoscaling and no mix of committed and on-demand capacity.
- **Fix:** autoscale on queue depth and KV utilization; commit the base by the §1.3 rule; move batch work into the
  troughs.

### F2 · Cost per request doubled after a product launch, with no traffic change

- **Root cause:** a prompt-length change: a RAG context, longer tool catalogs (Folder 05 File 03), or chat history
  without compaction (Folder 06 File 01). Prefill dominates capacity.
- **Fix:** track prompt tokens per request as a cost KPI; prefix caching; context budgets; compaction.

### F3 · The capacity plan was based on a benchmark that never matches production

- **Root cause:** benchmarks with short prompts, a single output length, no TPOT SLO and no prefix-cache misses.
- **Fix:** plan from measured goodput at the SLO on replayed production traces (Folder 02 File 01), not peak tokens/s.

### F4 · Committed capacity sits unused after a model migration

- **Root cause:** a 3-year commitment for a GPU type the next model does not fit well (memory, FP8 support).
- **Fix:** keep commitment terms shorter than the model roadmap's horizon, commit at the base only, and prefer
  convertible or fungible commitments.

### F5 · The API bill explodes during an agent rollout

- **Root cause:** agent loops multiply calls and context (Folder 06 File 01: quadratic tokens), and there is no
  per-tenant budget.
- **Fix:** token budgets at the gateway (Folder 07 File 04), loop guards, compaction, and routing cheap steps to small
  models.

### F6 · Unit economics are reported per GPU-hour instead of per business outcome

- **Fix:** cost per resolved ticket, per document processed, per successful agent task, with tokens and GPU-seconds
  attributed through gateway telemetry (`gen_ai.usage.*`, tenant and use-case attributes).

---

## 4. FAANG L7 bar-raiser Q&A chains

### Q1 · "Should we self-host Llama-class models or keep paying the API?"

- **L5 answer:** "Self-hosting is always cheaper at scale" (or "APIs are always cheaper").
- **Why L5 fails at scale:** no volume, no utilization, no workload shape, no people cost. At 20 req/s the API is
  half the price; at 100+ req/s self-hosting wins, under stated assumptions.
- **L7 principal defense:**
  1. Compute capacity from physics and measured goodput for *our* workload shape (prompt and output lengths, TPOT
     SLO).
  2. Model utilization from the real diurnal and weekly curve with autoscaling and N+1.
  3. Price committed, on-demand and spot capacity plus overhead and people, and compare with API pricing including
     caching discounts.
  4. Find the break-even and run a sensitivity analysis (utilization, prompt length, quantization, GPU price).
  5. Recommend a hybrid routed by the gateway, and revisit it quarterly because prices and models change.

### Q2 · "Our GPU bill is $2M/month. Cut it 40% without hurting quality."

- **L7 principal defense:** in order of effort per dollar:
  1. **Utilization:** autoscaling and a commitment mix (1.5–2.2× in the lab).
  2. **Prompt tokens:** prefix caching, context budgets, compaction, tool routing (prefill dominates).
  3. **Quantization:** FP8 weights and KV with speculative decoding (about 0.46×; validated on evaluations, Folder 02
     File 03).
  4. **Routing:** small models for easy steps, with a quality gate.
  5. **Batch work** moved to troughs and spot capacity.
  6. Measure each step against cost per business outcome.

### Q3 · "Explain why our 8K-context RAG costs 6× our chatbot per request."

- **L7 principal defense:** prefill FLOPs scale with prompt length (and attention quadratically), and KV capacity
  limits the decode batch to 166 instead of 1,090. Capacity drops about 7×. Fixes: shorter and better-ranked context
  (Folder 04), prefix caching of shared instructions, and quantized KV.

### Q4 · "How much capacity should we commit to?"

- **L7 principal defense:** commit replica k iff it is needed in at least `p_commit / p_on-demand` of hours. That
  is 58% at the assumed prices, which means 4 of 2–10 needed replicas at 40 req/s and 12 of 3–46 at 200 req/s. Keep
  terms shorter than the model roadmap and serve the peak on demand.

### Q5 · "Bedrock/Vertex or our own Kubernetes vLLM fleet for regulated data?"

- **L7 principal defense:** cost is one axis. The others are data residency and isolation options, the provider's
  data-use terms, available models and versions, fine-tuning needs, latency SLOs and the team's operating maturity.
  Managed endpoints in your cloud account often satisfy compliance with less risk. Self-hosting wins when volume is
  high, models are open, and the platform team exists. Decide per workload through the gateway.

---

## 5. Invariants checklist

- [ ] Capacity plans come from measured goodput at the SLO on production-shaped traffic.
- [ ] Prompt tokens per request are a tracked cost KPI; prefix caching and context budgets are in place.
- [ ] Fleet utilization is reported weekly; autoscaling tracks demand with N+1.
- [ ] Commitments follow the `f_k ≥ p_c/p_o` rule with terms shorter than the model roadmap.
- [ ] Self-hosting business cases include people, overhead and capacity risk; API cases include caching discounts.
- [ ] Unit economics are reported per business outcome, attributed through gateway telemetry.
- [ ] Routing between self-hosted and API models is a gateway configuration, reviewed quarterly.

## 6. References

1. This KB: Folder 01 File 01 (roofline), File 02 (KV capacity), File 03 (prefix caching); Folder 02 Files 01–03
   (goodput, disaggregation, quantization and speculative decoding).
2. FinOps Foundation. *FinOps Framework*: unit economics, rate optimization and commitment-based discounts.
3. Amazon Bedrock and Google Vertex AI pricing pages; GPU instance pricing of your cloud provider (⚠ verify current
   prices; this file's figures are illustrative assumptions).
4. vLLM documentation: production deployment, prefix caching, quantization (⚠ verify for your version).
