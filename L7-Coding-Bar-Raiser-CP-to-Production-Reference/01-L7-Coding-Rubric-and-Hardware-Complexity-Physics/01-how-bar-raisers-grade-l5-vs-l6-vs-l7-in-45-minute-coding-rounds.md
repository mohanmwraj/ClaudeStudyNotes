# How Bar-Raisers Grade L5 vs L6 vs L7 in a 45-Minute Coding Round

> **Folder 01 · File 1 of 3** — the grading model, one problem solved at three levels, and the three follow-ups that decide the level.
> **Languages:** Java 21 (`javac --release 21 -Xlint:all -Werror`, run on JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, both `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`).
> **Machine for every number:** Intel i5-11260H (6 cores / 12 threads, L1d 48 KiB and L2 1.25 MiB per core, L3 12 MiB), 16 GB RAM, Windows 11.

| Listing | File | What it proves |
|---|---|---|
| 1.1 | `TopKTalkers.java` | One problem solved at L5 (contest habits), L6 (correct heap) and L7 (contracted, mergeable API); 8 failure cases, 3,000 randomized cases against an oracle, a benchmark |
| 1.2 | `top_k_talkers.cpp` | The same in C++23: `std::expected`, heterogeneous lookup, strong-guarantee `merge`, and the same 8 cases on two standard libraries |
| 1.3 | `CpTraps.java` | `(lo + hi) / 2`, `mid * mid`, `int` sums and deep recursion, measured failing; one audited `firstTrue` binary search |
| 1.4 | `cp_traps.cpp` | The same traps in C++ caught at **compile time** by `static_assert` (an expected-failure build), plus `std::midpoint` and `partition_point` over `iota` |
| 1.5 | `TopKExtensions.java` | The three follow-ups, measured: (A) 8 threads, 7 strategies; (B) Space-Saving in bounded RAM; (C) 16 shards, naive merge vs TPUT |
| 1.6 | `top_k_extensions.cpp` | The same in C++: lock striping, thread-local maps, dense-id atomics with and without padding, node-handle Space-Saving, TPUT |

**Verification.** Every listing was extracted from this file, compiled with the flags above and run; the outputs below are spliced from those runs. Blocks labelled **Output (verified)** are deterministic and re-checked byte-for-byte by the folder gate. Blocks or lines marked **one measured run** contain timings; reruns change the numbers, not the shape.

---

## 0. Orientation

A Staff coding round is not a harder LeetCode problem. Most loops use medium-difficulty problems at every level. What changes is **what the interviewer writes down**. An L5 packet says "solved it, optimal complexity, a couple of bugs found with hints". An L7 packet says "defined the contract before coding, named the overflow and tie-breaking cases unprompted, shipped a mergeable API, and turned all three follow-ups into designs with numbers".

This file gives you the grading model (§1), then makes it concrete with one problem — **top-K clients by bytes transferred** — written three ways (§2). Next come the two contest reflexes that most often sink otherwise-strong candidates (§3), and the three "last 10 minutes" extensions every later folder repeats (§4).

**Honesty note.** No company publishes its internal coding rubric. The model below is a **composite**. It draws on Google's public re:Work guidance on structured interviewing (same questions, scored on the same scale against a rubric with weak-to-strong anchors). It also uses the four coding areas that third-party prep guides consistently report for Meta (communication, problem solving, coding, verification ⚠ — reported, not an official Meta document). The rest is the observable pattern of what separates levels. Nothing here is leaked material, and no question is claimed to be "the" question at any company.

### 0.1 The bridge: contest habit → what the interviewer writes → the L7 replacement

| Contest habit (rewarded on Codeforces) | What it looks like in the packet | L7 replacement shown in this file |
|---|---|---|
| `static int tot[MAXN]` global arrays | "Hard-codes input bounds; state leaks between calls" | An instance-scoped accumulator; capacity from data, not a constant (§2) |
| `int` everywhere, `#define int long long` when burned | "Did not consider overflow until prompted" | Overflow budget stated aloud; `long`/`int64_t`; `Math.addExact` or a checked add (§2, §3) |
| `(a, b) -> x[b] - x[a]` comparators | "Comparator bug; unstable under large values" | `Comparator.comparingLong(...)`, explicit tie-break (§2) |
| Ties "don't matter, any answer accepted" | "Output not deterministic; did not ask about ties" | Ties are part of the contract: bytes desc, then id asc (§2) |
| `(lo + hi) / 2`, `mid * mid <= x` | "Binary search overflows on large inputs" | One audited `firstTrue` with a written invariant (§3) |
| Recursive DFS, `ulimit -s unlimited` | "Stack overflow on a degenerate input" | Iterative traversal; recursion only with a proven depth bound (§3) |
| One-letter names, macros, `using namespace std` | "Readability below bar" | Domain names (`Talker`, `clientId`), types that carry meaning |
| "It passed the samples" | "No testing strategy" | Edge-case table, oracle, randomized differential test (§2; File 03) |
| Solve and stop | "Did not engage with follow-ups" | A/B/C extensions with measured trade-offs (§4) |

---

## 1. First principles: what a 45-minute coding round can actually measure

### 1.1 The round is a sampling instrument

You have roughly 45 minutes: about 5 for introductions and questions at the end, about 25 of real coding, and 10–15 of discussion. That sample is tiny, so the interviewer is not estimating "how good is this engineer". They are collecting **evidence for a fixed set of dimensions**, each with level anchors. Then they write the evidence up for a debrief or hiring committee that never saw you. Two consequences follow:

1. **Unspoken competence is invisible.** If you thought about overflow but never said so, the packet records "did not consider overflow". At L7 the narration *is* part of the work product.
2. **Every minute has an opportunity cost.** A candidate who spends 10 minutes polishing a helper the interviewer did not care about has spent 10 minutes not producing extension evidence. Senior candidates are graded on **how they allocate the round**.

### 1.2 The dimensions

| Dimension | What is observed | L5 anchor ("hire at L5") | L6 anchor | L7 anchor |
|---|---|---|---|---|
| **D1 Problem framing** | Questions before code | Asks about input size | Pins down edge cases and output format | Writes the **contract**: types, ties, error behaviour, size and memory budget, batch vs stream, who calls it and how often |
| **D2 Algorithm & proof** | Choice and justification | Reaches optimal with a hint | Reaches optimal unprompted, states complexity | Names the **invariant** that makes it correct, compares two candidates with constants, knows when the "worse" Big-O wins |
| **D3 Complexity physics** | Time/space reasoning | Big-O of time | Big-O of time and space | Big-O **plus** memory footprint, cache behaviour, allocation, I/O and network bytes (File 02) |
| **D4 Code structure** | The artefact | Works, monolithic | Clean functions, good names | An **API**: types that make invalid states hard, immutable results, no leaked representation (File 03) |
| **D5 Correctness** | Bugs and edge cases | Bugs found with hints | Few bugs, self-found | Overflow, empty, duplicates, ties, extremes **called out before** writing the line that would break |
| **D6 Verification** | Testing | Runs the sample by hand | Walks through edge cases | Edge-case table + invariant checks + a **differential test strategy** (oracle, randomized, properties) |
| **D7 Communication** | Driving the session | Responds to prompts | Thinks aloud, checks in | **Drives**: states the plan, time-boxes, asks the interviewer to choose between trade-offs |
| **D8 Extensions** | The last 10 minutes | Attempts one | Solid answer to one or two | Concurrency, streaming and distribution each answered with a **mechanism, a cost and a failure mode** (§4) |

A useful mental model: **L5 is graded on output, L6 on output and hygiene, L7 on output, hygiene and judgment.** The coding bar for L7 is roughly a flawless L6 round. The level comes from D1, D3, D8 and how you trade among them.

### 1.3 The 45-minute clock

| Minute | Phase | What L5 does | What L7 does |
|---|---|---|---|
| 0–5 | **Contract** | Restates the problem | Restates it **as a signature with types**, then asks the 5–8 questions whose answers change the design (§2.2) |
| 5–10 | **Approach** | Proposes one algorithm | Brute force in one sentence, then the target algorithm, its invariant, time/space, and the one alternative they rejected and why |
| 10–28 | **Code** | Writes top to bottom, fixes as they go | Writes the **API shell first** (types, signatures, contract comments), then fills bodies; narrates every "this line could overflow / be empty / tie" decision |
| 28–33 | **Verify** | Traces the sample | Edge-case table out loud (empty, one, duplicates, ties, extremes, overflow); names the oracle and the randomized test they would add |
| 33–45 | **Extensions** | Answers what is asked | Answers what is asked, **then volunteers the next failure mode** (contention → hot keys → skew; bounded memory → error bound → certification; sharding → partitioning function → stability) |

The single highest-leverage habit is in the first row. A typed signature written in minute two, such as `List<Talker> topK(int k)` with `record Talker(String clientId, long bytes)`, forces every ambiguous question into the open. It also gives the interviewer a contract to grade the rest of the round against.

### 1.4 How a packet becomes a level

The interviewer writes observations ("asked whether ties matter; chose bytes-desc then id-asc"), not adjectives ("smart"), then a score per dimension and an overall recommendation. A committee or debrief reads several packets side by side. Three patterns recur (observed patterns, not policy):

* **Clean code, shallow extensions → down-level.** Perfect D2/D4/D5 with one-sentence answers to the follow-ups reads as a strong L6.
* **Strong extensions, buggy code → no-hire or down-level.** At Staff level, interviewers expect the code to work; design talk does not compensate for an off-by-one the candidate could not find.
* **One unforced error is survivable; a pattern is not.** A missed overflow that you catch yourself during verification is evidence *for* you. The same overflow found by the interviewer, after you declared the code done, is evidence against you.

### 1.5 Round archetypes you will meet

Formats change and differ by team, so treat this as a map, not a promise ⚠. Ask the recruiter which archetype each round is.

| Archetype | Typical shape | What carries the most weight |
|---|---|---|
| Algorithmic whiteboard / shared editor | One or two medium problems, no execution | D2, D5, D6 by reasoning; extensions discussed |
| Practical / codebase | Extend or debug a small realistic codebase, often with execution | D4 (API), D6 (tests you write), reading unfamiliar code |
| Performance-sensitive | Data-structure problem plus "make it faster", often C++ | D3: memory layout, allocation, branch and cache behaviour (File 02) |
| Systems coding | Concurrency, file/IO or storage flavoured problems | D8-A and D8-B: thread safety, bounded memory, failure semantics |

---

## 2. The exhibit: top-K clients by bytes, three ways

### 2.1 The prompt

> "You get an access log as records `(clientId, bytes)`. Return the K clients that transferred the most bytes."

That is all the interviewer says. Every word of the contract is yours to establish.

### 2.2 The questions that change the design

| Question | Answer used in this file | Design decision it drives |
|---|---|---|
| What is a `clientId`? | A string such as `"10.0.0.7"` or `"tenant-42"` | Hash map keyed by string, **not** `int tot[MAXN]` |
| How large can `bytes` be, and how many records? | One record ≤ 2³¹ − 1; billions of records | Per-client totals exceed 2³¹ after **two** records; use 64-bit totals with a checked add |
| Can `bytes` be negative or the id missing? | No; reject them | Validate at the boundary, throw (Java) or return `std::unexpected` (C++) |
| How are ties ordered? | Bytes descending, then `clientId` ascending | A total order, so the output is deterministic and testable (LeetCode 692 has exactly this contract) |
| What if `k` exceeds the number of clients, or is 0 or negative? | Return all clients; `k = 0` → empty; `k < 0` → error | No phantom clients; `k` validated |
| Is the log a batch or a stream? Does it fit in RAM? | Batch now, stream later | A **mergeable accumulator**, so the same code serves threads (A), streams (B) and shards (C) |
| Who calls this, and how often? | Once per reporting window | `topK` is `O(U log k)` with a size-k heap; a full sort would be `O(U log U)` |

### 2.3 Listing 1.1 — Java

The file holds all three levels side by side. `CpStyle` is deliberately written the way a strong contestant writes under time pressure. `l6TopK` is what most good candidates produce. `TalkerAccumulator` is the L7 artefact. `oracle` is an independent reference that shares no code with the L7 version.

```java
// TopKTalkers.java - "top-K clients by bytes" three ways: contest habit (L5), correct (L6), production API (L7).
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.PriorityQueue;
import java.util.TreeMap;

public final class TopKTalkers {

    // ===================================================================== L5: contest habits
    /** Global arrays sized by a constraint production never promised, int sums, state never reset. */
    static final class CpStyle {
        static final int MAXN = 100_005;
        static int[] tot = new int[MAXN];

        static int[] solve(String[] ids, int[] bytes, int k) {
            for (int i = 0; i < ids.length; i++) tot[Integer.parseInt(ids[i])] += bytes[i];
            Integer[] o = new Integer[MAXN];
            for (int i = 0; i < MAXN; i++) o[i] = i;
            Arrays.sort(o, (a, b) -> tot[b] - tot[a]);
            int[] r = new int[k];
            for (int i = 0; i < k; i++) r[i] = o[i];
            return r;
        }

        static void freshProcess() { tot = new int[MAXN]; }  // what the judge does for you between runs
    }

    // ===================================================================== L6: correct and efficient
    static List<String> l6TopK(List<String> ids, List<Long> bytes, int k) {
        Map<String, Long> total = new HashMap<>();
        for (int i = 0; i < ids.size(); i++) total.merge(ids.get(i), bytes.get(i), Long::sum);
        PriorityQueue<Map.Entry<String, Long>> heap = new PriorityQueue<>(Map.Entry.comparingByValue());
        for (Map.Entry<String, Long> e : total.entrySet()) {
            heap.offer(e);
            if (heap.size() > k) heap.poll();
        }
        List<Map.Entry<String, Long>> best = new ArrayList<>(heap);
        best.sort(Map.Entry.<String, Long>comparingByValue().reversed());
        return best.stream().map(Map.Entry::getKey).toList();
    }

    // ===================================================================== L7: production API
    /** One client's total. Validated once, at the boundary; everything downstream may trust it. */
    record Talker(String clientId, long bytes) {
        Talker {
            Objects.requireNonNull(clientId, "clientId");
            if (bytes < 0) throw new IllegalArgumentException("bytes must be >= 0, got " + bytes);
        }
    }

    /** The contract: more bytes first; ties by clientId, so the answer never depends on hash order. */
    static final Comparator<Talker> RANK =
            Comparator.comparingLong(Talker::bytes).reversed().thenComparing(Talker::clientId);

    /**
     * Mergeable accumulator. add: O(1) expected. topK: O(U log k) time, O(k) extra space (U = distinct clients).
     * Not thread-safe on purpose: give each thread or shard its own instance and combine them with merge().
     */
    static final class TalkerAccumulator {
        private final Map<String, Long> totals = new HashMap<>();

        void add(String clientId, long bytes) {
            Objects.requireNonNull(clientId, "clientId");
            if (bytes < 0) throw new IllegalArgumentException("bytes must be >= 0, got " + bytes);
            totals.merge(clientId, bytes, Math::addExact);
        }

        TalkerAccumulator merge(TalkerAccumulator other) {
            other.totals.forEach((id, b) -> totals.merge(id, b, Math::addExact));
            return this;
        }

        int distinctClients() { return totals.size(); }

        List<Talker> topK(int k) {
            if (k < 0) throw new IllegalArgumentException("k must be >= 0, got " + k);
            if (k == 0) return List.of();
            PriorityQueue<Talker> worstFirst = new PriorityQueue<>(Math.min(k, totals.size()) + 1, RANK.reversed());
            for (Map.Entry<String, Long> e : totals.entrySet()) {
                if (worstFirst.size() == k) {
                    Talker worst = worstFirst.peek();
                    long b = e.getValue();
                    if (b < worst.bytes() || (b == worst.bytes() && e.getKey().compareTo(worst.clientId()) > 0)) continue;
                    worstFirst.poll();
                }
                worstFirst.offer(new Talker(e.getKey(), e.getValue()));
            }
            Talker[] out = worstFirst.toArray(new Talker[0]);
            Arrays.sort(out, RANK);
            return List.of(out);
        }

        /** O(U log U) baseline for the benchmark. */
        List<Talker> sortedAll() {
            List<Talker> all = new ArrayList<>(totals.size());
            totals.forEach((id, b) -> all.add(new Talker(id, b)));
            all.sort(RANK);
            return all;
        }
    }

    // ===================================================================== verification
    /** Independent oracle: exact sums in a TreeMap, full sort, prefix. No heap, no shared code with L7. */
    static List<Talker> oracle(List<String> ids, List<Long> bytes, int k) {
        TreeMap<String, Long> sums = new TreeMap<>();
        for (int i = 0; i < ids.size(); i++) sums.merge(ids.get(i), bytes.get(i), Long::sum);
        List<Talker> all = new ArrayList<>();
        sums.forEach((id, b) -> all.add(new Talker(id, b)));
        all.sort(RANK);
        return List.copyOf(all.subList(0, Math.min(k, all.size())));
    }

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
        int nextInt(int bound) { return (int) Long.remainderUnsigned(next(), bound); }
    }

    record Case(String name, List<String> ids, List<Long> bytes, int k) {}

    static String ids(List<Talker> ts) { return ts.stream().map(Talker::clientId).toList().toString(); }

    static String runL5(Case c) {
        try {
            int[] b = c.bytes().stream().mapToInt(Long::intValue).toArray();
            return Arrays.toString(CpStyle.solve(c.ids().toArray(new String[0]), b, c.k()));
        } catch (RuntimeException e) {
            return e.getClass().getSimpleName() + ": " + e.getMessage();
        }
    }

    static String runL7(Case c) {
        try {
            TalkerAccumulator acc = new TalkerAccumulator();
            for (int i = 0; i < c.ids().size(); i++) acc.add(c.ids().get(i), c.bytes().get(i));
            return ids(acc.topK(c.k()));
        } catch (RuntimeException e) {
            return e.getClass().getSimpleName() + ": " + e.getMessage();
        }
    }

    static void table() {
        List<Case> cases = List.of(
                new Case("int overflow: 7 sends 2 x 1.5e9 bytes, 8 sends 10", List.of("7", "7", "8"),
                        List.of(1_500_000_000L, 1_500_000_000L, 10L), 1),
                new Case("comparator a-b overflow: 1 sends 2e9, 2 sends 3 x 1e9", List.of("1", "2", "2", "2"),
                        List.of(2_000_000_000L, 1_000_000_000L, 1_000_000_000L, 1_000_000_000L), 2),
                new Case("real-world id: \"10.0.0.7\"", List.of("10.0.0.7"), List.of(5L), 1),
                new Case("id beyond MAXN: \"200000\"", List.of("200000"), List.of(5L), 1),
                new Case("k > distinct clients: 2 clients, k=3", List.of("3", "4"), List.of(9L, 8L), 3),
                new Case("tie: b and a both send 5, k=1", List.of("b", "a"), List.of(5L, 5L), 1),
                new Case("negative k", List.of("3"), List.of(1L), -1));
        int n = 1;
        for (Case c : cases) {
            CpStyle.freshProcess();
            String truth = c.k() < 0 ? "reject k<0" : ids(oracle(c.ids(), c.bytes(), c.k()));
            System.out.printf("[%d] %s%n    truth %s | L5 %s | L6 %s | L7 %s%n", n++, c.name(), truth, runL5(c),
                    l6TopK(c.ids(), c.bytes(), c.k()), runL7(c));
        }
        // Stale global state: the second "request" in the same process sees the first one's totals.
        CpStyle.freshProcess();
        CpStyle.solve(new String[] {"5"}, new int[] {100}, 1);
        int[] second = CpStyle.solve(new String[] {"6"}, new int[] {50}, 1);
        System.out.printf("[%d] stale globals: call 1 = {5: 100}, call 2 = {6: 50}, k=1%n    truth [6] | L5 %s | L6 %s | L7 %s%n",
                n, Arrays.toString(second), l6TopK(List.of("6"), List.of(50L), 1),
                runL7(new Case("", List.of("6"), List.of(50L), 1)));
    }

    static void contracts() {
        TalkerAccumulator acc = new TalkerAccumulator();
        acc.add("big", Long.MAX_VALUE);
        String[] probes = new String[4];
        try { acc.add("big", 1); } catch (ArithmeticException e) { probes[0] = "overflow -> ArithmeticException(" + e.getMessage() + ")"; }
        try { acc.add("x", -1); } catch (IllegalArgumentException e) { probes[1] = "negative bytes -> " + e.getMessage(); }
        try { acc.add(null, 1); } catch (NullPointerException e) { probes[2] = "null id -> NPE(" + e.getMessage() + ")"; }
        try { acc.topK(1).add(new Talker("y", 1)); } catch (UnsupportedOperationException e) { probes[3] = "result is immutable -> UnsupportedOperationException"; }
        System.out.println("L7 contracts:");
        for (String p : probes) System.out.println("    " + p);
    }

    static void randomized(int cases) {
        SplitMix64 rng = new SplitMix64(2026);
        int l7Agree = 0, mergeAgree = 0, l6Agree = 0, l6TieOnly = 0;
        for (int c = 0; c < cases; c++) {
            int u = 1 + rng.nextInt(8), n = rng.nextInt(30), k = rng.nextInt(u + 3);
            List<String> ids = new ArrayList<>();
            List<Long> bytes = new ArrayList<>();
            for (int i = 0; i < n; i++) {
                ids.add("c" + rng.nextInt(u));
                bytes.add(rng.nextInt(2) == 0 ? rng.nextInt(4) : rng.next() >>> 34);  // small values force ties
            }
            List<Talker> want = oracle(ids, bytes, k);
            TalkerAccumulator whole = new TalkerAccumulator(), left = new TalkerAccumulator(), right = new TalkerAccumulator();
            int cut = n == 0 ? 0 : rng.nextInt(n + 1);
            for (int i = 0; i < n; i++) {
                whole.add(ids.get(i), bytes.get(i));
                (i < cut ? left : right).add(ids.get(i), bytes.get(i));
            }
            if (whole.topK(k).equals(want)) l7Agree++;
            if (left.merge(right).topK(k).equals(want)) mergeAgree++;
            List<String> l6 = l6TopK(ids, bytes, k);
            if (l6.equals(want.stream().map(Talker::clientId).toList())) {
                l6Agree++;
            } else {
                Map<String, Long> sums = new HashMap<>();
                for (int i = 0; i < n; i++) sums.merge(ids.get(i), bytes.get(i), Long::sum);
                if (l6.stream().map(sums::get).toList().equals(want.stream().map(Talker::bytes).toList())) l6TieOnly++;
            }
        }
        System.out.printf("randomized vs oracle (%d cases, ids from <= 8 clients, values forced to tie):%n", cases);
        System.out.printf("    L7 topK            %d/%d agree%n", l7Agree, cases);
        System.out.printf("    L7 merge(halves)   %d/%d agree   <- the property Extensions A and C rely on%n", mergeAgree, cases);
        System.out.printf("    L6 heap            %d/%d agree, %d differ only in which tied client is returned%n",
                l6Agree, cases, l6TieOnly);
    }

    static void benchmark() {
        int u = 1_000_000, n = 4_000_000;
        String[] names = new String[u];
        for (int i = 0; i < u; i++) names[i] = "client-" + i;
        SplitMix64 rng = new SplitMix64(7);
        TalkerAccumulator acc = new TalkerAccumulator();
        long t0 = System.nanoTime();
        for (int i = 0; i < n; i++) acc.add(names[rng.nextInt(u)], 1 + rng.nextInt(1_500));
        long buildMs = (System.nanoTime() - t0) / 1_000_000;
        long bestHeap = Long.MAX_VALUE, bestSort = Long.MAX_VALUE;
        List<Talker> a = List.of(), b = List.of();
        for (int rep = 0; rep < 5; rep++) {
            long s = System.nanoTime();
            a = acc.topK(10);
            bestHeap = Math.min(bestHeap, System.nanoTime() - s);
            s = System.nanoTime();
            b = acc.sortedAll().subList(0, 10);
            bestSort = Math.min(bestSort, System.nanoTime() - s);
        }
        System.out.printf("benchmark (one measured run): N=%,d records, U=%,d distinct, accumulate %d ms%n",
                n, acc.distinctClients(), buildMs);
        System.out.printf("    topK(10) heap  O(U log k): %6.1f ms (best of 5)%n", bestHeap / 1e6);
        System.out.printf("    sort all       O(U log U): %6.1f ms (best of 5)   same answer: %b%n", bestSort / 1e6, a.equals(b));
    }

    public static void main(String[] args) {
        table();
        contracts();
        randomized(3_000);
        benchmark();
    }
}
```

**Output (verified; the benchmark lines are one measured run):**

```text
[1] int overflow: 7 sends 2 x 1.5e9 bytes, 8 sends 10
    truth [7] | L5 [8] | L6 [7] | L7 [7]
[2] comparator a-b overflow: 1 sends 2e9, 2 sends 3 x 1e9
    truth [2, 1] | L5 [3, 2] | L6 [2, 1] | L7 [2, 1]
[3] real-world id: "10.0.0.7"
    truth [10.0.0.7] | L5 NumberFormatException: For input string: "10.0.0.7" | L6 [10.0.0.7] | L7 [10.0.0.7]
[4] id beyond MAXN: "200000"
    truth [200000] | L5 ArrayIndexOutOfBoundsException: Index 200000 out of bounds for length 100005 | L6 [200000] | L7 [200000]
[5] k > distinct clients: 2 clients, k=3
    truth [3, 4] | L5 [3, 4, 0] | L6 [3, 4] | L7 [3, 4]
[6] tie: b and a both send 5, k=1
    truth [a] | L5 NumberFormatException: For input string: "b" | L6 [b] | L7 [a]
[7] negative k
    truth reject k<0 | L5 NegativeArraySizeException: -1 | L6 [] | L7 IllegalArgumentException: k must be >= 0, got -1
[8] stale globals: call 1 = {5: 100}, call 2 = {6: 50}, k=1
    truth [6] | L5 [5] | L6 [6] | L7 [6]
L7 contracts:
    overflow -> ArithmeticException(long overflow)
    negative bytes -> bytes must be >= 0, got -1
    null id -> NPE(clientId)
    result is immutable -> UnsupportedOperationException
randomized vs oracle (3000 cases, ids from <= 8 clients, values forced to tie):
    L7 topK            3000/3000 agree
    L7 merge(halves)   3000/3000 agree   <- the property Extensions A and C rely on
    L6 heap            2957/3000 agree, 43 differ only in which tied client is returned
benchmark (one measured run): N=4,000,000 records, U=982,064 distinct, accumulate 1286 ms
    topK(10) heap  O(U log k):   11.2 ms (best of 5)
    sort all       O(U log U):  815.7 ms (best of 5)   same answer: true
```

### 2.4 Listing 1.2 — C++23

```cpp
// top_k_talkers.cpp - "top-K clients by bytes" three ways: contest habit (L5), correct (L6), production API (L7).
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <expected>
#include <functional>
#include <limits>
#include <map>
#include <numeric>
#include <print>
#include <queue>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

// ======================================================================= L5: contest habits
// Compiled the way contestants compile: without -Wconversion. Under this KB's flags those two warnings
// reject the program -- the first production lesson is already in the build line.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
namespace cp {
const int MAXN = 100005;
int tot[MAXN];
std::vector<int> solve(const std::vector<std::string>& ids, const std::vector<long long>& bytes, int k) {
    for (size_t i = 0; i < ids.size(); i++) tot[std::stoi(ids[i])] += bytes[i];
    std::vector<int> o(MAXN);
    std::iota(o.begin(), o.end(), 0);
    std::sort(o.begin(), o.end(), [](int a, int b) { return tot[a] > tot[b]; });
    return std::vector<int>(o.begin(), o.begin() + k);
}
void fresh_process() { std::fill(std::begin(tot), std::end(tot), 0); }  // what the judge does between runs
}  // namespace cp
#pragma GCC diagnostic pop

// ======================================================================= L6: correct and efficient
std::vector<std::string> l6_top_k(const std::vector<std::string>& ids, const std::vector<long long>& bytes, int k) {
    std::unordered_map<std::string, long long> total;
    for (std::size_t i = 0; i < ids.size(); ++i) total[ids[i]] += bytes[i];
    using Entry = std::pair<std::string, long long>;
    auto by_bytes = [](const Entry& a, const Entry& b) { return a.second > b.second; };  // min-heap on bytes
    std::priority_queue<Entry, std::vector<Entry>, decltype(by_bytes)> heap(by_bytes);
    for (const auto& e : total) {
        heap.push(e);
        if (heap.size() > static_cast<std::size_t>(k)) heap.pop();
    }
    std::vector<std::string> out(heap.size());
    for (auto i = out.size(); i-- > 0; heap.pop()) out[i] = heap.top().first;
    return out;
}

// ======================================================================= L7: production API
struct Talker {
    std::string client_id;
    std::int64_t bytes{};
    friend bool operator==(const Talker&, const Talker&) = default;
};

// The contract: more bytes first; ties by client_id, so the answer never depends on hash order.
struct RankBefore {
    bool operator()(const Talker& a, const Talker& b) const noexcept {
        return a.bytes != b.bytes ? a.bytes > b.bytes : a.client_id < b.client_id;
    }
};

enum class AddError { empty_id, negative_bytes, overflow };

constexpr std::string_view name(AddError e) noexcept {
    switch (e) {
        case AddError::empty_id: return "empty_id";
        case AddError::negative_bytes: return "negative_bytes";
        case AddError::overflow: return "overflow";
    }
    return "?";
}

// Mergeable accumulator. add: O(1) expected. top_k: O(U log k) time, O(k) extra space.
// Not thread-safe on purpose: one instance per thread or shard, combined with merge().
class TalkerAccumulator {
public:
    [[nodiscard]] std::expected<void, AddError> add(std::string_view client_id, std::int64_t bytes) {
        if (client_id.empty()) return std::unexpected(AddError::empty_id);
        if (bytes < 0) return std::unexpected(AddError::negative_bytes);
        auto it = totals_.find(client_id);  // heterogeneous lookup: no std::string is built for a hit
        if (it == totals_.end()) {
            totals_.emplace(std::string(client_id), bytes);
            return {};
        }
        if (bytes > kMax - it->second) return std::unexpected(AddError::overflow);
        it->second += bytes;
        return {};
    }

    // Strong guarantee: check every sum first, then apply, so a failed merge changes nothing.
    [[nodiscard]] std::expected<void, AddError> merge(const TalkerAccumulator& other) {
        for (const auto& [id, b] : other.totals_)
            if (auto it = totals_.find(id); it != totals_.end() && b > kMax - it->second)
                return std::unexpected(AddError::overflow);
        for (const auto& [id, b] : other.totals_) totals_[id] += b;
        return {};
    }

    [[nodiscard]] std::size_t distinct_clients() const noexcept { return totals_.size(); }

    [[nodiscard]] std::vector<Talker> top_k(std::size_t k) const {
        std::vector<Talker> heap;  // heap under RankBefore: front() is the worst kept so far
        if (k == 0) return heap;
        heap.reserve(std::min(k, totals_.size()));
        RankBefore before;
        for (const auto& [id, b] : totals_) {
            if (heap.size() == k) {
                const Talker& worst = heap.front();
                if (b < worst.bytes || (b == worst.bytes && id > worst.client_id)) continue;
                std::ranges::pop_heap(heap, before);
                heap.back() = Talker{id, b};
            } else {
                heap.push_back(Talker{id, b});
            }
            std::ranges::push_heap(heap, before);
        }
        std::ranges::sort_heap(heap, before);
        return heap;
    }

    [[nodiscard]] std::vector<Talker> sorted_all() const {  // O(U log U) baseline for the benchmark
        std::vector<Talker> all;
        all.reserve(totals_.size());
        for (const auto& [id, b] : totals_) all.push_back(Talker{id, b});
        std::ranges::sort(all, RankBefore{});
        return all;
    }

private:
    static constexpr std::int64_t kMax = std::numeric_limits<std::int64_t>::max();
    struct Hash {
        using is_transparent = void;
        std::size_t operator()(std::string_view s) const noexcept { return std::hash<std::string_view>{}(s); }
    };
    std::unordered_map<std::string, std::int64_t, Hash, std::equal_to<>> totals_;
};

// ======================================================================= verification
// Independent oracle: exact sums in a std::map, full sort, prefix. No heap, no shared code with L7.
std::vector<Talker> oracle(const std::vector<std::string>& ids, const std::vector<long long>& bytes, std::size_t k) {
    std::map<std::string, std::int64_t> sums;
    for (std::size_t i = 0; i < ids.size(); ++i) sums[ids[i]] += bytes[i];
    std::vector<Talker> all;
    for (const auto& [id, b] : sums) all.push_back(Talker{id, b});
    std::ranges::sort(all, RankBefore{});
    all.resize(std::min(k, all.size()));
    return all;
}

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int below(int bound) noexcept { return static_cast<int>(next() % static_cast<std::uint64_t>(bound)); }
};

template <class R, class F>
std::string join(const R& r, F f) {
    std::string s = "[";
    for (bool first = true; const auto& x : r) {
        s += (first ? "" : ", ") + f(x);
        first = false;
    }
    return s + "]";
}

std::string ids_of(const std::vector<Talker>& ts) { return join(ts, [](const Talker& t) { return t.client_id; }); }

struct Case {
    std::string name;
    std::vector<std::string> ids;
    std::vector<long long> bytes;
    int k;
};

std::string run_l5(const Case& c) {
    for (const auto& id : c.ids) {
        long long v = 0;
        try { v = std::stoi(id); } catch (const std::invalid_argument&) { return "std::invalid_argument from std::stoi"; }
        if (v >= cp::MAXN) return "not run: tot[" + id + "] writes past a 100005-int array (UB; ASan aborts here)";
    }
    if (c.k < 0) return "not run: vector(begin, begin + k) with k<0 is UB";
    return join(cp::solve(c.ids, c.bytes, c.k), [](int v) { return std::to_string(v); });
}

std::string run_l7(const Case& c) {
    TalkerAccumulator acc;
    for (std::size_t i = 0; i < c.ids.size(); ++i)
        if (auto r = acc.add(c.ids[i], c.bytes[i]); !r) return std::string("error: ") + std::string(name(r.error()));
    if (c.k < 0) return "unrepresentable: top_k takes std::size_t";
    return ids_of(acc.top_k(static_cast<std::size_t>(c.k)));
}

void table() {
    const std::vector<Case> cases = {
        {"int overflow: 7 sends 2 x 1.5e9 bytes, 8 sends 10", {"7", "7", "8"}, {1'500'000'000, 1'500'000'000, 10}, 1},
        {"comparator a-b overflow: 1 sends 2e9, 2 sends 3 x 1e9", {"1", "2", "2", "2"},
         {2'000'000'000, 1'000'000'000, 1'000'000'000, 1'000'000'000}, 2},
        {"real-world id: \"10.0.0.7\"", {"10.0.0.7"}, {5}, 1},
        {"id beyond MAXN: \"200000\"", {"200000"}, {5}, 1},
        {"k > distinct clients: 2 clients, k=3", {"3", "4"}, {9, 8}, 3},
        {"tie: b and a both send 5, k=1", {"b", "a"}, {5, 5}, 1},
        {"negative k", {"3"}, {1}, -1},
    };
    int n = 1;
    for (const auto& c : cases) {
        cp::fresh_process();
        std::string truth = c.k < 0 ? "reject k<0" : ids_of(oracle(c.ids, c.bytes, static_cast<std::size_t>(c.k)));
        std::string l6 = join(l6_top_k(c.ids, c.bytes, c.k), [](const std::string& s) { return s; });
        std::println("[{}] {}\n    truth {} | L5 {} | L6 {} | L7 {}", n++, c.name, truth, run_l5(c), l6, run_l7(c));
    }
    cp::fresh_process();
    (void)cp::solve({"5"}, {100}, 1);
    auto second = cp::solve({"6"}, {50}, 1);
    std::println("[{}] stale globals: call 1 = {{5: 100}}, call 2 = {{6: 50}}, k=1\n    truth [6] | L5 {} | L6 {} | L7 {}", n,
                 join(second, [](int v) { return std::to_string(v); }),
                 join(l6_top_k({"6"}, {50}, 1), [](const std::string& s) { return s; }),
                 run_l7({"", {"6"}, {50}, 1}));
}

void contracts() {
    TalkerAccumulator acc;
    (void)acc.add("big", std::numeric_limits<std::int64_t>::max());
    TalkerAccumulator other;
    (void)other.add("big", 1);
    (void)other.add("new", 1);
    std::println("L7 contracts:");
    std::println("    overflow -> {}", name(acc.add("big", 1).error()));
    std::println("    negative bytes -> {}", name(acc.add("x", -1).error()));
    std::println("    empty id -> {}", name(acc.add("", 1).error()));
    auto m = acc.merge(other);
    std::println("    merge overflow -> {}, distinct clients still {} (strong guarantee)", name(m.error()),
                 acc.distinct_clients());
}

void randomized(int cases) {
    SplitMix64 rng{2026};
    int l7_agree = 0, merge_agree = 0, l6_agree = 0, l6_tie_only = 0;
    for (int c = 0; c < cases; ++c) {
        int u = 1 + rng.below(8), n = rng.below(30), k = rng.below(u + 3);
        std::vector<std::string> ids;
        std::vector<long long> bytes;
        for (int i = 0; i < n; ++i) {
            ids.push_back("c" + std::to_string(rng.below(u)));
            bytes.push_back(rng.below(2) == 0 ? rng.below(4) : static_cast<long long>(rng.next() >> 34));
        }
        auto want = oracle(ids, bytes, static_cast<std::size_t>(k));
        TalkerAccumulator whole, left, right;
        int cut = n == 0 ? 0 : rng.below(n + 1);
        for (int i = 0; i < n; ++i) {
            auto idx = static_cast<std::size_t>(i);
            (void)whole.add(ids[idx], bytes[idx]);
            (void)(i < cut ? left : right).add(ids[idx], bytes[idx]);
        }
        l7_agree += whole.top_k(static_cast<std::size_t>(k)) == want;
        (void)left.merge(right);
        merge_agree += left.top_k(static_cast<std::size_t>(k)) == want;
        auto l6 = l6_top_k(ids, bytes, k);
        std::vector<std::string> want_ids;
        for (const auto& t : want) want_ids.push_back(t.client_id);
        if (l6 == want_ids) {
            ++l6_agree;
        } else {
            std::map<std::string, long long> sums;
            for (std::size_t i = 0; i < ids.size(); ++i) sums[ids[i]] += bytes[i];
            bool same_values = l6.size() == want.size();
            for (std::size_t i = 0; same_values && i < l6.size(); ++i) same_values = sums[l6[i]] == want[i].bytes;
            l6_tie_only += same_values;
        }
    }
    std::println("randomized vs oracle ({} cases, ids from <= 8 clients, values forced to tie):", cases);
    std::println("    L7 top_k           {}/{} agree", l7_agree, cases);
    std::println("    L7 merge(halves)   {}/{} agree   <- the property Extensions A and C rely on", merge_agree, cases);
    std::println("    L6 heap            {}/{} agree, {} differ only in which tied client is returned", l6_agree, cases,
                 l6_tie_only);
}

void benchmark() {
    constexpr int u = 1'000'000, n = 4'000'000;
    std::vector<std::string> names;
    names.reserve(u);
    for (int i = 0; i < u; ++i) names.push_back("client-" + std::to_string(i));
    SplitMix64 rng{7};
    TalkerAccumulator acc;
    using clock = std::chrono::steady_clock;
    auto t0 = clock::now();
    for (int i = 0; i < n; ++i) {
        // Two statements, not add(names[rng()], rng()): argument evaluation order is unspecified, and GCC and
        // Clang really do draw the two numbers in opposite orders (this listing's first run built different data).
        auto who = static_cast<std::size_t>(rng.below(u));
        (void)acc.add(names[who], 1 + rng.below(1'500));
    }
    auto build_ms = std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count();
    double best_heap = 1e300, best_sort = 1e300;
    std::vector<Talker> a, b;
    for (int rep = 0; rep < 5; ++rep) {
        auto s = clock::now();
        a = acc.top_k(10);
        best_heap = std::min(best_heap, std::chrono::duration<double, std::milli>(clock::now() - s).count());
        s = clock::now();
        b = acc.sorted_all();
        b.resize(10);
        best_sort = std::min(best_sort, std::chrono::duration<double, std::milli>(clock::now() - s).count());
    }
    std::println("benchmark (one measured run): N={} records, U={} distinct, accumulate {} ms", n, acc.distinct_clients(),
                 build_ms);
    std::println("    top_k(10) heap O(U log k): {:6.1f} ms (best of 5)", best_heap);
    std::println("    sort all       O(U log U): {:6.1f} ms (best of 5)   same answer: {}", best_sort, a == b);
}

int main() {
    table();
    contracts();
    randomized(3'000);
    benchmark();
}
```

**Output, GCC 16.2 / libstdc++ (verified; benchmark lines are one measured run):**

```text
[1] int overflow: 7 sends 2 x 1.5e9 bytes, 8 sends 10
    truth [7] | L5 [8] | L6 [7] | L7 [7]
[2] comparator a-b overflow: 1 sends 2e9, 2 sends 3 x 1e9
    truth [2, 1] | L5 [1, 66677] | L6 [2, 1] | L7 [2, 1]
[3] real-world id: "10.0.0.7"
    truth [10.0.0.7] | L5 [10] | L6 [10.0.0.7] | L7 [10.0.0.7]
[4] id beyond MAXN: "200000"
    truth [200000] | L5 not run: tot[200000] writes past a 100005-int array (UB; ASan aborts here) | L6 [200000] | L7 [200000]
[5] k > distinct clients: 2 clients, k=3
    truth [3, 4] | L5 [3, 4, 66664] | L6 [3, 4] | L7 [3, 4]
[6] tie: b and a both send 5, k=1
    truth [a] | L5 std::invalid_argument from std::stoi | L6 [b] | L7 [a]
[7] negative k
    truth reject k<0 | L5 not run: vector(begin, begin + k) with k<0 is UB | L6 [3] | L7 unrepresentable: top_k takes std::size_t
[8] stale globals: call 1 = {5: 100}, call 2 = {6: 50}, k=1
    truth [6] | L5 [5] | L6 [6] | L7 [6]
L7 contracts:
    overflow -> overflow
    negative bytes -> negative_bytes
    empty id -> empty_id
    merge overflow -> overflow, distinct clients still 1 (strong guarantee)
randomized vs oracle (3000 cases, ids from <= 8 clients, values forced to tie):
    L7 top_k           3000/3000 agree
    L7 merge(halves)   3000/3000 agree   <- the property Extensions A and C rely on
    L6 heap            2952/3000 agree, 48 differ only in which tied client is returned
benchmark (one measured run): N=4000000 records, U=982064 distinct, accumulate 1814 ms
    top_k(10) heap O(U log k):   78.9 ms (best of 5)
    sort all       O(U log U):  294.8 ms (best of 5)   same answer: true
```

**Output, Clang 21.1 / libc++ (verified; benchmark lines are one measured run):**

```text
[1] int overflow: 7 sends 2 x 1.5e9 bytes, 8 sends 10
    truth [7] | L5 [8] | L6 [7] | L7 [7]
[2] comparator a-b overflow: 1 sends 2e9, 2 sends 3 x 1e9
    truth [2, 1] | L5 [1, 50002] | L6 [2, 1] | L7 [2, 1]
[3] real-world id: "10.0.0.7"
    truth [10.0.0.7] | L5 [10] | L6 [10.0.0.7] | L7 [10.0.0.7]
[4] id beyond MAXN: "200000"
    truth [200000] | L5 not run: tot[200000] writes past a 100005-int array (UB; ASan aborts here) | L6 [200000] | L7 [200000]
[5] k > distinct clients: 2 clients, k=3
    truth [3, 4] | L5 [3, 4, 50002] | L6 [3, 4] | L7 [3, 4]
[6] tie: b and a both send 5, k=1
    truth [a] | L5 std::invalid_argument from std::stoi | L6 [b] | L7 [a]
[7] negative k
    truth reject k<0 | L5 not run: vector(begin, begin + k) with k<0 is UB | L6 [3] | L7 unrepresentable: top_k takes std::size_t
[8] stale globals: call 1 = {5: 100}, call 2 = {6: 50}, k=1
    truth [6] | L5 [5] | L6 [6] | L7 [6]
L7 contracts:
    overflow -> overflow
    negative bytes -> negative_bytes
    empty id -> empty_id
    merge overflow -> overflow, distinct clients still 1 (strong guarantee)
randomized vs oracle (3000 cases, ids from <= 8 clients, values forced to tie):
    L7 top_k           3000/3000 agree
    L7 merge(halves)   3000/3000 agree   <- the property Extensions A and C rely on
    L6 heap            2950/3000 agree, 50 differ only in which tied client is returned
benchmark (one measured run): N=4000000 records, U=982064 distinct, accumulate 1357 ms
    top_k(10) heap O(U log k):   76.9 ms (best of 5)
    sort all       O(U log U):  219.2 ms (best of 5)   same answer: true
```

### 2.5 Reading the results the way an interviewer does

**Case 1, int overflow.** Client 7 sends 2 × 1.5 × 10⁹ bytes. The contest version stores `−1,294,967,296` (3 × 10⁹ − 2³²) and ranks client 8, with 10 bytes, first. Nothing crashed, and the answer is confidently wrong. In C++ the `int += long long` line wraps modulo 2³²: well defined since C++20, still wrong. Under this KB's warning flags that line **does not compile** (`-Wconversion` + `-Werror`). The listing has to switch those two warnings off to reproduce contest conditions, which makes the first production lesson a build flag.

**Case 2, comparator overflow.** Client 1 sends 2 × 10⁹ and client 2 sends 3 × 10⁹. The Java subtraction comparator `tot[b] - tot[a]` overflows, the ordering stops being transitive, and TimSort returns `[3, 2]`: a client that **sent nothing** is ranked first. The C++ contest code uses `>` instead of subtraction, so its comparator is sound. Its overflowed total for client 2 still sinks below the zero-byte clients, and it returns `[1, <some zero-byte id>]`. The phantom id is `66677` with libstdc++ and `50002` with libc++, because `std::sort` is not stable and the two libraries break ties differently.

**Cases 3–4, real ids.** `Integer.parseInt("10.0.0.7")` throws in Java. `std::stoi("10.0.0.7")` **returns 10**: it parses the prefix and silently merges client `10.0.0.7` into client `10`. The same habit fails loudly in one language and silently in the other. Id `200000` indexes past the 100,005-element array, which is an exception in Java and undefined behaviour in C++ (not executed here; AddressSanitizer would abort).

**Case 5, k > clients.** Contest code returns `k` ids no matter what, so a zero-byte phantom appears.

**Case 6, ties.** L6 returns `b`, the contract says `a`. The heap version is "correct" under any tie rule, but its tie behaviour is an accident of hash order. Across 3,000 randomized cases, 43 (Java), 48 (libstdc++) and 50 (libc++) L6 answers differed from the oracle **only** in which tied client came back. The counts differ by standard library because `unordered_map` iteration order differs. That is the whole case for writing the tie-break into the contract.

**Case 7, negative k.** The contest code throws `NegativeArraySizeException`. Java L6 silently returns `[]`. C++ L6 casts `k` to `size_t`, gets 2⁶⁴ − 1, never pops the heap, and returns **every** client. The same bug has opposite symptoms in two languages, and only an explicit contract (Java throws; C++ makes the bad value unrepresentable with `std::size_t`) gives one behaviour.

**Case 8, stale globals.** The second call in the same process sees the first call's totals and returns client 5, which was not in the second request at all. Online judges run each test in a fresh process, so this bug never shows up in contests. In a service it is a **cross-request data leak**.

**The L7 contract checks.** In Java, overflow surfaces as `ArithmeticException` from `Math::addExact`, negative bytes and a null id are rejected at the boundary, and the result list is immutable. In C++ the same failures are values (`std::expected<void, AddError>`). `merge` gives the **strong guarantee**: it checks every sum before applying any, so a failed merge leaves the accumulator unchanged ("distinct clients still 1").

**The randomized check is the L7 verification story in miniature.** 3,000 small cases (≤ 8 clients, values forced to tie) run against an oracle that shares no code with the solution. The run also checks the property the extensions depend on: `merge(left, right).topK(k) == whole.topK(k)` for a random split. Java and C++ use the same SplitMix64 generator and agree case for case.

**A bug this listing found in itself.** The first version of the C++ benchmark loop was `acc.add(names[rng.below(u)], 1 + rng.below(1'500))`. GCC and Clang built **different data** from the same seed (`U = 981,621` vs `982,064`), because function-argument evaluation order is unspecified in C++ and the two compilers really do evaluate in opposite orders. Java defines left-to-right evaluation and agreed with Clang. The fix is two statements, and the comment in the listing records why. For an interview it makes a good one-liner: *"never put two side-effecting calls in one argument list."*

### 2.6 The benchmark, and a hidden constant worth knowing

`topK(10)` over about 982,000 distinct clients took **11–14 ms** in Java with a size-10 heap. Sorting all of them took **0.8–1.1 s**: the `O(U log k)` vs `O(U log U)` gap plus allocating 982k `Talker` objects. In C++ the heap took **77–81 ms** and the full sort **219–315 ms**.

Why is Java's heap scan about 6× faster than C++'s over the same hash map? Both loops spend their time chasing hash-map nodes. Rerunning the same Java listing with `-XX:+UnlockExperimentalVMOptions -XX:+UseEpsilonGC -Xmx7g` (a no-op collector that never moves objects) gave **63.1 ms**. `-XX:+UseParallelGC` gave 22.4 ms and the default G1 12.9 ms (one measured run each). A copying collector relocates surviving objects in traversal order, so after a few young collections the `HashMap` nodes sit nearly in table order and the scan becomes close to sequential. `malloc` never moves anything, so the C++ nodes stay scattered in insertion order. This is the File 02 lesson in miniature: **the same Big-O, a 5× constant, decided by memory layout rather than by the algorithm.**

---

## 3. Two contest reflexes that silently break: overflow and recursion depth

The two most common Staff-loop "unforced errors" by a strong competitive programmer are midpoint/product overflow inside binary search and unbounded recursion depth. Both pass every sample.

### 3.1 The binary-search invariant, written once

Binary search on an answer is always the same object. Given a predicate `p` that is **monotone** on `[lo, hi]` (false…false true…true), find the first `v` with `p(v)`. The L7 move is to write that object **once**, with its invariant, and reuse it, rather than re-deriving `while (lo <= hi)` vs `while (lo < hi)` under pressure:

* **Invariant:** every `v < l` has `p(v) == false`; `p(h)` is true or `h == hi + 1`.
* **Progress:** `mid ∈ [l, h)`, and each branch strictly shrinks `h − l`, so the loop terminates.
* **Midpoint:** computed without forming `l + h` (`(l & h) + ((l ^ h) >> 1)` in Java, `std::midpoint` in C++), correct for **any** signs.
* **Predicate:** never multiplies values that can overflow; `v > x / v` instead of `v * v > x`.

The `int` midpoint bug lived in `java.util.Arrays.binarySearch` for about nine years before Joshua Bloch's 2006 write-up. It is not a beginner's mistake.

### 3.2 Listing 1.3 — Java

```java
// CpTraps.java - contest habits that pass the samples and fail production: overflowing binary search, int sums, deep recursion.
import java.util.function.LongPredicate;

public final class CpTraps {

    // ===================================================================== Trap 1: LC 69 sqrt(x), contest style
    static long iterations, firstNegativeMid;

    static int cpSqrt(int x) {
        int lo = 0, hi = x, ans = 0;
        while (lo <= hi) {
            if (++iterations > 1_000) return Integer.MIN_VALUE;  // demo guard: the contest code has none
            int mid = (lo + hi) / 2;
            if (mid < 0 && firstNegativeMid == 0) firstNegativeMid = iterations;  // instrumentation, not contest code
            if (mid * mid <= x) { ans = mid; lo = mid + 1; } else hi = mid - 1;
        }
        return ans;
    }

    // ===================================================================== L7: one audited binary search
    /**
     * Smallest v in [lo, hi] with p(v), or hi + 1 if there is none.
     * Requires: p is monotone on [lo, hi] (false...false true...true) and hi < Long.MAX_VALUE.
     * Invariant: every v < l has p(v) false; p(h) is true or h == hi + 1. Each step shrinks h - l, so it terminates.
     */
    static long firstTrue(long lo, long hi, LongPredicate p) {
        if (lo > hi) throw new IllegalArgumentException("empty range [" + lo + ", " + hi + "]");
        if (hi == Long.MAX_VALUE) throw new IllegalArgumentException("hi + 1 must be representable");
        long l = lo, h = hi + 1;
        while (l < h) {
            long mid = (l & h) + ((l ^ h) >> 1);  // floor((l + h) / 2) with no intermediate overflow, any signs
            if (p.test(mid)) h = mid; else l = mid + 1;
        }
        return l;
    }

    /** floor(sqrt(x)) for every non-negative long; v > x / v is v * v > x without the multiplication. */
    static long isqrt(long x) {
        if (x < 0) throw new IllegalArgumentException("x < 0");
        // sqrt(2^63) < 3,037,000,500 bounds the search. (The first draft searched [1, x]: firstTrue's own
        // precondition rejected isqrt(Long.MAX_VALUE), because hi + 1 overflowed. Contracts earn their keep.)
        return x < 2 ? x : firstTrue(1, Math.min(x, 3_037_000_500L), v -> v > x / v) - 1;
    }

    // ===================================================================== Trap 2: LC 1011 ship within D days
    static int cpShip(int[] w, int days) {
        int lo = 0, hi = 0;
        for (int x : w) { lo = Math.max(lo, x); hi += x; }
        while (lo < hi) {
            int mid = (lo + hi) / 2, need = 1, cur = 0;
            for (int x : w) { if (cur + x > mid) { need++; cur = 0; } cur += x; }
            if (need <= days) hi = mid; else lo = mid + 1;
        }
        return lo;
    }

    static long daysNeeded(int[] w, long capacity) {
        long need = 1, cur = 0;
        for (int x : w) {
            if (cur + x > capacity) { need++; cur = 0; }
            cur += x;
        }
        return need;
    }

    static long shipWithinDays(int[] w, int days) {
        if (w.length == 0 || days < 1) throw new IllegalArgumentException("need >= 1 package and >= 1 day");
        long max = 0, sum = 0;
        for (int x : w) {
            if (x < 0) throw new IllegalArgumentException("negative weight " + x);
            max = Math.max(max, x);
            sum = Math.addExact(sum, x);
        }
        return firstTrue(max, sum, cap -> daysNeeded(w, cap) <= days);  // monotone: more capacity, fewer days
    }

    // ===================================================================== Trap 3: recursion depth
    static int deepest;

    static void dfsRecursive(int[] next, int u, int depth) {
        deepest = depth;
        if (next[u] >= 0) dfsRecursive(next, next[u], depth + 1);
    }

    static int dfsIterative(int[] next, int start) {
        int depth = 0;
        for (int u = start; u >= 0; u = next[u]) depth++;  // a path needs no stack; a tree needs an explicit int[] one
        return depth;
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.println("Trap 1 - LC 69 sqrt by binary search");
        for (int x : new int[] {16, 2_147_395_599, Integer.MAX_VALUE}) {
            iterations = 0;
            firstNegativeMid = 0;
            int cp = cpSqrt(x);
            String why = firstNegativeMid > 0 ? " (lo + hi wrapped: mid < 0 first at iteration " + firstNegativeMid + ")" : "";
            System.out.printf("    x=%,13d  contest %s%s  L7 %d%n", x,
                    cp == Integer.MIN_VALUE ? "NO ANSWER after 1,000 iterations"
                            : String.format("%d after %d iterations%s", cp, iterations, cp == isqrt(x) ? "" : "  <- WRONG"),
                    why, isqrt(x));
        }
        long r = 3_037_000_499L, x = r * r - 1;
        System.out.printf("    x=r*r-1, r=%,d: (long) Math.sqrt(x) = %,d  isqrt = %,d  <- doubles carry 53 bits, x needs 63%n",
                r, (long) Math.sqrt(x), isqrt(x));
        System.out.printf("    isqrt(Long.MAX_VALUE) = %,d (exact: %b)%n", isqrt(Long.MAX_VALUE),
                isqrt(Long.MAX_VALUE) * isqrt(Long.MAX_VALUE) <= Long.MAX_VALUE);

        System.out.println("Trap 2 - LC 1011 ship packages within D days");
        int[][] inputs = {{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, {1_000_000_000, 1_000_000_000, 1_000_000_000}};
        int[] days = {5, 2};
        for (int i = 0; i < inputs.length; i++) {
            int cp = cpShip(inputs[i], days[i]);
            long l7 = shipWithinDays(inputs[i], days[i]);
            System.out.printf("    %d packages, D=%d: contest %,d (needs %d days)  L7 %,d (needs %d days)%n",
                    inputs[i].length, days[i], cp, daysNeeded(inputs[i], cp), l7, daysNeeded(inputs[i], l7));
        }
        System.out.printf("    firstTrue on [Long.MIN_VALUE, Long.MAX_VALUE - 1], p(v) = v >= -7: %d%n",
                firstTrue(Long.MIN_VALUE, Long.MAX_VALUE - 1, v -> v >= -7));

        System.out.println("Trap 3 - DFS on a path of 1,000,000 nodes (a degenerate tree, a long linked chain)");
        int n = 1_000_000;
        int[] next = new int[n];
        for (int i = 0; i < n; i++) next[i] = i + 1 < n ? i + 1 : -1;
        try {
            dfsRecursive(next, 0, 1);
            System.out.println("    recursive on main thread: completed");
        } catch (StackOverflowError e) {
            System.out.printf("    recursive on main thread: StackOverflowError at depth ~%,d (varies with JIT state)%n", deepest);
        }
        System.out.printf("    iterative:                 visited %,d nodes, O(1) extra space%n", dfsIterative(next, 0));
        Thread big = new Thread(null, () -> dfsRecursive(next, 0, 1), "big-stack", 512L << 20);
        big.start();
        big.join();
        System.out.printf("    recursive on a 512 MiB-stack thread (the contest trick): reached depth %,d%n", deepest);
    }
}
```

**Output (verified; the stack-overflow depth varies with JIT state):**

```text
Trap 1 - LC 69 sqrt by binary search
    x=           16  contest 4 after 4 iterations  L7 4
    x=2,147,395,599  contest NO ANSWER after 1,000 iterations (lo + hi wrapped: mid < 0 first at iteration 2)  L7 46339
    x=2,147,483,647  contest NO ANSWER after 1,000 iterations (lo + hi wrapped: mid < 0 first at iteration 2)  L7 46340
    x=r*r-1, r=3,037,000,499: (long) Math.sqrt(x) = 3,037,000,499  isqrt = 3,037,000,498  <- doubles carry 53 bits, x needs 63
    isqrt(Long.MAX_VALUE) = 3,037,000,499 (exact: true)
Trap 2 - LC 1011 ship packages within D days
    10 packages, D=5: contest 15 (needs 5 days)  L7 15 (needs 5 days)
    3 packages, D=2: contest 1,000,000,000 (needs 3 days)  L7 2,000,000,000 (needs 2 days)
    firstTrue on [Long.MIN_VALUE, Long.MAX_VALUE - 1], p(v) = v >= -7: -7
Trap 3 - DFS on a path of 1,000,000 nodes (a degenerate tree, a long linked chain)
    recursive on main thread: StackOverflowError at depth ~15,268 (varies with JIT state)
    iterative:                 visited 1,000,000 nodes, O(1) extra space
    recursive on a 512 MiB-stack thread (the contest trick): reached depth 1,000,000
```

### 3.3 Listing 1.4 — C++23: make the compiler run the samples

Signed overflow is undefined behaviour in C++, so the contest versions cannot be "run to see what happens"; the result could be anything. In a **constant expression**, though, the compiler must diagnose undefined behaviour. The listing therefore evaluates the contest code inside `static_assert`. The samples pass. With `-DCONSTEXPR_OVERFLOW` the production inputs are added and the build must fail, which the harness checks.

```cpp
// cp_traps.cpp - contest habits that pass the samples and fail production: overflowing binary search, int sums, deep recursion.
#include <algorithm>
#include <array>
#include <cmath>
#include <concepts>
#include <cstdint>
#include <functional>
#include <limits>
#include <numeric>
#include <print>
#include <ranges>
#include <span>
#include <stdexcept>
#include <vector>

// ======================================================================= the contest versions
// Signed overflow is UB at run time, so these are never run. In a constant expression the compiler MUST diagnose
// UB instead -- static_assert turns "passes the samples" into a compile-time test. -DCONSTEXPR_OVERFLOW adds the
// production inputs and the build fails (this KB's harness compiles that variant and expects the failure).
constexpr int cp_sqrt(int x) {
    int lo = 0, hi = x, ans = 0;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (mid * mid <= x) { ans = mid; lo = mid + 1; } else hi = mid - 1;
    }
    return ans;
}

constexpr int cp_ship(std::span<const int> w, int days) {
    int lo = 0, hi = 0;
    for (int x : w) { lo = std::max(lo, x); hi += x; }
    while (lo < hi) {
        int mid = (lo + hi) / 2, need = 1, cur = 0;
        for (int x : w) { if (cur + x > mid) { need++; cur = 0; } cur += x; }
        if (need <= days) hi = mid; else lo = mid + 1;
    }
    return lo;
}

static_assert(cp_sqrt(16) == 4);                                            // the samples pass ...
static_assert(cp_ship(std::array{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, 5) == 15);
#ifdef CONSTEXPR_OVERFLOW
static_assert(cp_sqrt(2'147'483'647) == 46'340);                             // ... production inputs do not compile
static_assert(cp_ship(std::array{1'000'000'000, 1'000'000'000, 1'000'000'000}, 2) == 2'000'000'000);
#endif

// ======================================================================= L7: one audited binary search
// Smallest v in [lo, hi] with p(v), or hi + 1 if there is none.
// Requires: p monotone on [lo, hi] (false...false true...true) and hi < INT64_MAX.
// Invariant: every v < l has !p(v); p(h) holds or h == hi + 1. h - l shrinks every step, so it terminates.
template <std::predicate<std::int64_t> P>
constexpr std::int64_t first_true(std::int64_t lo, std::int64_t hi, P p) {
    if (lo > hi) throw std::invalid_argument("empty range");
    if (hi == std::numeric_limits<std::int64_t>::max()) throw std::invalid_argument("hi + 1 must be representable");
    std::int64_t l = lo, h = hi + 1;
    while (l < h) {
        std::int64_t mid = std::midpoint(l, h);  // rounds toward l (floor here); never overflows
        if (std::invoke(p, mid)) h = mid; else l = mid + 1;
    }
    return l;
}

// floor(sqrt(x)) the library way: partition_point over a lazy iota_view is O(log n) and allocates nothing.
constexpr std::int64_t isqrt(std::int64_t x) {
    if (x < 0) throw std::invalid_argument("x < 0");
    if (x < 2) return x;
    auto candidates = std::views::iota(std::int64_t{1}, std::min<std::int64_t>(x, 3'037'000'500) + 1);
    auto it = std::ranges::partition_point(candidates, [x](std::int64_t v) { return v <= x / v; });
    return *it - 1;  // first v with v*v > x, minus one; the bound guarantees such a v exists
}

static_assert(isqrt(2'147'483'647) == 46'340);
static_assert(isqrt(std::numeric_limits<std::int64_t>::max()) == 3'037'000'499);

constexpr std::int64_t days_needed(std::span<const int> w, std::int64_t capacity) {
    std::int64_t need = 1, cur = 0;
    for (int x : w) {
        if (cur + x > capacity) { ++need; cur = 0; }
        cur += x;
    }
    return need;
}

constexpr std::int64_t ship_within_days(std::span<const int> w, int days) {
    if (w.empty() || days < 1) throw std::invalid_argument("need >= 1 package and >= 1 day");
    std::int64_t max = 0, sum = 0;
    for (int x : w) {
        if (x < 0) throw std::invalid_argument("negative weight");
        max = std::max<std::int64_t>(max, x);
        sum += x;  // at most 2^31 * |w|: cannot overflow int64 for any span that fits in memory
    }
    return first_true(max, sum, [w, days](std::int64_t cap) { return days_needed(w, cap) <= days; });
}

static_assert(ship_within_days(std::array{1'000'000'000, 1'000'000'000, 1'000'000'000}, 2) == 2'000'000'000);

// ======================================================================= Trap 3: recursion depth
int dfs_iterative(std::span<const int> next, int start) {
    int depth = 0;
    for (int u = start; u >= 0; u = next[static_cast<std::size_t>(u)]) ++depth;  // a tree needs an explicit stack
    return depth;
}

int main() {
    std::println("Trap 1 - LC 69 sqrt by binary search");
    std::println("    contest cp_sqrt(2147483647): rejected at compile time (UB in a constant expression); see the -D build");
    for (std::int64_t x : {std::int64_t{16}, std::int64_t{2'147'395'599}, std::int64_t{2'147'483'647}})
        std::println("    x={:>13}  L7 {}", x, isqrt(x));
    const std::int64_t r = 3'037'000'499, x = r * r - 1;
    std::println("    x=r*r-1, r={}: (int64) std::sqrt(x) = {}  isqrt = {}  <- doubles carry 53 bits, x needs 63", r,
                 static_cast<std::int64_t>(std::sqrt(static_cast<double>(x))), isqrt(x));
    std::println("    isqrt(INT64_MAX) = {} (checked by static_assert)", isqrt(std::numeric_limits<std::int64_t>::max()));

    std::println("Trap 2 - LC 1011 ship packages within D days");
    const std::vector<int> small = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, big = {1'000'000'000, 1'000'000'000, 1'000'000'000};
    for (auto [w, d] : {std::pair{std::span<const int>(small), 5}, std::pair{std::span<const int>(big), 2}}) {
        auto cap = ship_within_days(w, d);
        std::println("    {} packages, D={}: L7 {} (needs {} days)", w.size(), d, cap, days_needed(w, cap));
    }
    std::println("    first_true on [INT64_MIN, INT64_MAX - 1], p(v) = v >= -7: {}",
                 first_true(std::numeric_limits<std::int64_t>::min(), std::numeric_limits<std::int64_t>::max() - 1,
                            [](std::int64_t v) { return v >= -7; }));

    std::println("Trap 3 - DFS on a path of 1,000,000 nodes");
    std::vector<int> next(1'000'000);
    std::iota(next.begin(), next.end(), 1);
    next.back() = -1;
    std::println("    recursive: not run -- a C++ stack overflow is a crash, not an exception (no handler, no stack trace)");
    std::println("    iterative: visited {} nodes, O(1) extra space", dfs_iterative(next, 0));
}
```

**Output, both compilers (verified; GCC shown, Clang identical):**

```text
Trap 1 - LC 69 sqrt by binary search
    contest cp_sqrt(2147483647): rejected at compile time (UB in a constant expression); see the -D build
    x=           16  L7 4
    x=   2147395599  L7 46339
    x=   2147483647  L7 46340
    x=r*r-1, r=3037000499: (int64) std::sqrt(x) = 3037000499  isqrt = 3037000498  <- doubles carry 53 bits, x needs 63
    isqrt(INT64_MAX) = 3037000499 (checked by static_assert)
Trap 2 - LC 1011 ship packages within D days
    10 packages, D=5: L7 15 (needs 5 days)
    3 packages, D=2: L7 2000000000 (needs 2 days)
    first_true on [INT64_MIN, INT64_MAX - 1], p(v) = v >= -7: -7
Trap 3 - DFS on a path of 1,000,000 nodes
    recursive: not run -- a C++ stack overflow is a crash, not an exception (no handler, no stack trace)
    iterative: visited 1000000 nodes, O(1) extra space
```

**The expected-failure build, GCC 16.2** (diagnostics collapsed with counts):

```text
cp_traps.cpp:43:38: error: non-constant condition for static assertion
cp_traps.cpp:24:17: error: overflow in constant expression [-fpermissive]   [x262,144]
cp_traps.cpp:23:23: error: overflow in constant expression [-fpermissive]   [x262,143]
cp_traps.cpp:23:29: error: overflow in constant expression [-fpermissive]   [x262,143]
cp_traps.cpp:24:51: error: overflow in constant expression [-fpermissive]   [x262,143]
cp_traps.cpp:22:5: error: 'constexpr' loop iteration count exceeds limit of 262144 (use '-fconstexpr-loop-limit=' to increase the limit)
cp_traps.cpp:44:83: error: non-constant condition for static assertion
cp_traps.cpp:31:48: error: overflow in constant expression [-fpermissive]
```

**The expected-failure build, Clang 21.1:**

```text
cp_traps.cpp:43:15: error: static assertion expression is not an integral constant expression
cp_traps.cpp:23:9: note: constexpr evaluation hit maximum step limit; possible infinite loop?
cp_traps.cpp:44:15: error: static assertion expression is not an integral constant expression
cp_traps.cpp:31:48: note: value 3000000000 is outside the range of representable values of type 'int'
```

### 3.4 What the traps teach

* **Java `cpSqrt` never returns.** At iteration 2, `lo + hi` wraps negative, `mid` goes negative, and the search interval no longer contains the answer. The demo guard stops it after 1,000 iterations. The compilers confirm the same thing independently. GCC keeps evaluating after each overflow (each one is a `-fpermissive` error) and gives up only at its 262,144-iteration `constexpr` loop limit. Clang stops at its step limit with *"possible infinite loop?"*. For the shipping problem, Clang names the exact value: *"3000000000 is outside the range of representable values of type 'int'"*.
* **The contest `cpShip` returns 1,000,000,000 for a case that needs 2,000,000,000.** `hi = sum` wrapped negative, the loop never ran, and the answer was the lower bound. It needs 3 days instead of the 2 allowed, and no exception tells you so.
* **"Just use `Math.sqrt`" is also wrong.** For `x = 3,037,000,499² − 1`, `(long) Math.sqrt(x)` returns 3,037,000,499, one too many. A `double` carries 53 significant bits and `x` needs 63, so `x` rounds up to a perfect square. The same holds for `std::sqrt` in C++.
* **Contracts earn their keep.** The first draft of `isqrt` searched `[1, x]`, and `firstTrue`'s own precondition (`hi + 1` must be representable) rejected `isqrt(Long.MAX_VALUE)` on the first run. The fix, bounding the search by √2⁶³ < 3,037,000,500, is now a comment in the listing.
* **Recursion depth is a deployment property, not an algorithm property.** The recursive DFS on a 10⁶-node path overflowed the Java main thread at a depth of about 15,000–15,600 frames. The **same** code on a thread created with a 512 MiB stack reached 1,000,000. That is the contest trick, and it works because stack size here is a constructor argument. (The Javadoc warns the value "may have no effect whatsoever" on some platforms.) The default stacks, read from the PE headers of the binaries built here, are **1 MiB** for `java.exe`, **2 MiB** for the MinGW-GCC executable and **16 MiB** for the Zig/Clang one. The same C++ recursion can therefore survive under one toolchain and crash under another. A C++ stack overflow is a crash, not an exception: no handler, no stack trace. The L7 answer is an explicit stack (an `int[]` or `std::vector<int>`) or a proven depth bound, such as a balanced tree with depth `O(log n)`.

---

## 4. The last 10 minutes: Extensions A, B and C

Once the base problem works, a Staff interviewer almost always asks some version of three questions. Every later folder of this KB answers them for its own patterns. Here they are on the top-K exhibit, measured.

* **A — Concurrency:** "64 threads call `add` concurrently. What changes?"
* **B — Streaming / bounded RAM:** "The log is an infinite stream, or a 100 TB file. You have 1 GB."
* **C — Distribution:** "The log is spread over 100 machines. Give me the global top-K."

The L7 shape of every answer is the same three beats: **mechanism → cost → failure mode**. "Use a ConcurrentHashMap" is a mechanism. "...which locks a bin per update, so the hot client serializes on one bin; I'd measure, then stripe or pre-aggregate" is an L7 answer.

### 4.1 Listing 1.5 — Java

```java
// TopKExtensions.java - the last 10 minutes of top-K talkers: (A) 8 threads, (B) bounded-RAM stream, (C) 16 shards.
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReferenceArray;
import java.util.concurrent.atomic.LongAdder;

public final class TopKExtensions {
    static final int U = 100_000, N = 8_000_000, THREADS = 8, K = 10, SHARDS = 16;
    static final String[] NAMES = new String[U];
    static final int[] EV_CLIENT = new int[N], EV_BYTES = new int[N];

    record Talker(String clientId, long bytes) {}
    static final Comparator<Talker> RANK =
            Comparator.comparingLong(Talker::bytes).reversed().thenComparing(Talker::clientId);

    static List<Talker> topK(Map<String, ? extends Number> totals, int k) {
        return totals.entrySet().stream().map(e -> new Talker(e.getKey(), e.getValue().longValue()))
                .sorted(RANK).limit(k).toList();
    }

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
        int nextInt(int bound) { return (int) Long.remainderUnsigned(next(), bound); }
        double nextDouble() { return (next() >>> 11) * 0x1.0p-53; }
    }

    /** Skewed traffic: P(client < x) = (x/U)^(1/4), so client-0 sends ~5.6% of all events (a hot key). */
    static void generate() {
        for (int i = 0; i < U; i++) NAMES[i] = "client-" + i;
        SplitMix64 r = new SplitMix64(42);
        for (int i = 0; i < N; i++) {
            double u = r.nextDouble();
            EV_CLIENT[i] = (int) (U * (u * u * u * u));
            EV_BYTES[i] = 64 + r.nextInt(1_437);
        }
    }

    // ===================================================================== Extension A: 8 threads
    interface Body { void run(int thread, int lo, int hi); }

    /** Start all workers behind one gate; record (never lose) a worker's exception; return wall ms. */
    static double parallel(Body body, List<Throwable> errors) throws InterruptedException {
        CountDownLatch gate = new CountDownLatch(1), done = new CountDownLatch(THREADS);
        for (int t = 0; t < THREADS; t++) {
            int id = t, lo = (int) ((long) N * t / THREADS), hi = (int) ((long) N * (t + 1) / THREADS);
            Thread.ofPlatform().start(() -> {
                try {
                    gate.await();
                    body.run(id, lo, hi);
                } catch (Throwable e) {
                    synchronized (errors) { errors.add(e); }
                } finally {
                    done.countDown();
                }
            });
        }
        long t0 = System.nanoTime();
        gate.countDown();
        done.await();
        return (System.nanoTime() - t0) / 1e6;
    }

    static void report(String name, double ms, Map<String, ? extends Number> totals, List<Throwable> errors,
                       long wantBytes, List<Talker> want) {
        long got = totals.values().stream().mapToLong(Number::longValue).sum();
        String verdict;
        try {
            verdict = topK(totals, K).equals(want) ? "exact" : "WRONG";
        } catch (RuntimeException e) {  // a racy map can fail LATER, in single-threaded code, far from the race
            verdict = "CRASH on a later read";
        }
        System.out.printf("    %-36s %7.1f ms %6.1f M events/s  lost bytes %,11d  top-10 %s%n", name, ms,
                N / ms / 1e3, wantBytes - got, verdict);
        long iterated = totals.entrySet().stream().count();
        if (!errors.isEmpty() || iterated != totals.size()) {
            System.out.printf("        size() %,d vs iterated %,d entries; %d of %d workers died: %s%n", totals.size(),
                    iterated, errors.size(), THREADS,
                    errors.stream().map(e -> e.getClass().getSimpleName()).distinct().sorted().toList());
        }
    }

    static Map<String, Long> extensionA() throws InterruptedException {
        long t0 = System.nanoTime();
        Map<String, Long> truth = new HashMap<>();
        for (int i = 0; i < N; i++) truth.merge(NAMES[EV_CLIENT[i]], (long) EV_BYTES[i], Long::sum);
        double singleMs = (System.nanoTime() - t0) / 1e6;
        long wantBytes = truth.values().stream().mapToLong(Long::longValue).sum();
        List<Talker> want = topK(truth, K);
        System.out.printf("Extension A - %d threads, N=%,d events, U=%,d clients (one measured run)%n", THREADS, N, U);
        System.out.printf("    %-36s %7.1f ms %6.1f M events/s  (baseline, also warms the JIT)%n",
                "1 thread HashMap", singleMs, N / singleMs / 1e3);

        List<Throwable> errors = new ArrayList<>();
        Map<String, Long> shared = new HashMap<>();
        double ms = parallel((t, lo, hi) -> {
            for (int i = lo; i < hi; i++) shared.merge(NAMES[EV_CLIENT[i]], (long) EV_BYTES[i], Long::sum);
        }, errors);
        report("shared HashMap, no lock (WRONG)", ms, shared, errors, wantBytes, want);

        errors = new ArrayList<>();
        Map<String, Long> locked = new HashMap<>();
        ms = parallel((t, lo, hi) -> {
            for (int i = lo; i < hi; i++) {
                synchronized (locked) { locked.merge(NAMES[EV_CLIENT[i]], (long) EV_BYTES[i], Long::sum); }
            }
        }, errors);
        report("one lock around HashMap", ms, locked, errors, wantBytes, want);

        errors = new ArrayList<>();
        ConcurrentHashMap<String, Long> chm = new ConcurrentHashMap<>();
        ms = parallel((t, lo, hi) -> {
            for (int i = lo; i < hi; i++) chm.merge(NAMES[EV_CLIENT[i]], (long) EV_BYTES[i], Long::sum);
        }, errors);
        report("ConcurrentHashMap.merge", ms, chm, errors, wantBytes, want);

        errors = new ArrayList<>();
        ConcurrentHashMap<String, LongAdder> adders = new ConcurrentHashMap<>();
        ms = parallel((t, lo, hi) -> {
            for (int i = lo; i < hi; i++) adders.computeIfAbsent(NAMES[EV_CLIENT[i]], x -> new LongAdder()).add(EV_BYTES[i]);
        }, errors);
        report("ConcurrentHashMap<String, LongAdder>", ms, adders, errors, wantBytes, want);

        errors = new ArrayList<>();
        AtomicReferenceArray<Map<String, Long>> local = new AtomicReferenceArray<>(THREADS);
        ms = parallel((t, lo, hi) -> {
            Map<String, Long> mine = new HashMap<>();
            for (int i = lo; i < hi; i++) mine.merge(NAMES[EV_CLIENT[i]], (long) EV_BYTES[i], Long::sum);
            local.set(t, mine);  // published to main by the done latch
        }, errors);
        long m0 = System.nanoTime();
        Map<String, Long> merged = new HashMap<>();
        for (int t = 0; t < THREADS; t++) local.get(t).forEach((k, v) -> merged.merge(k, v, Math::addExact));
        double mergeMs = (System.nanoTime() - m0) / 1e6;
        report(String.format("thread-local Long maps + merge %.0f ms", mergeMs), ms + mergeMs, merged, errors, wantBytes, want);

        errors = new ArrayList<>();
        AtomicReferenceArray<Map<String, long[]>> cells = new AtomicReferenceArray<>(THREADS);
        ms = parallel((t, lo, hi) -> {
            Map<String, long[]> mine = new HashMap<>();  // mutable cell: no Long allocated per event
            for (int i = lo; i < hi; i++) mine.computeIfAbsent(NAMES[EV_CLIENT[i]], x -> new long[1])[0] += EV_BYTES[i];
            cells.set(t, mine);
        }, errors);
        m0 = System.nanoTime();
        Map<String, Long> mergedCells = new HashMap<>();
        for (int t = 0; t < THREADS; t++) cells.get(t).forEach((k, v) -> mergedCells.merge(k, v[0], Math::addExact));
        mergeMs = (System.nanoTime() - m0) / 1e6;
        report(String.format("thread-local long[] cells + merge %.0f ms", mergeMs), ms + mergeMs, mergedCells, errors,
                wantBytes, want);
        return truth;
    }

    // ===================================================================== Extension B: bounded RAM
    /** Weighted Space-Saving (Metwally et al. 2005): m counters, every estimate within W/m of the truth. */
    static final class SpaceSaving {
        static final class Counter {
            final String id;
            long count;
            final long error;
            Counter(String id, long count, long error) { this.id = id; this.count = count; this.error = error; }
        }

        private final int capacity;
        private final Map<String, Counter> byId = new HashMap<>();
        // Ordered by a MUTABLE field: always remove, then mutate, then re-insert, or the tree is corrupt.
        private final TreeSet<Counter> byCount =
                new TreeSet<>(Comparator.<Counter>comparingLong(c -> c.count).thenComparing(c -> c.id));

        SpaceSaving(int capacity) { this.capacity = capacity; }

        void add(String id, long w) {
            Counter c = byId.get(id);
            if (c != null) {
                byCount.remove(c);
                c.count += w;
                byCount.add(c);
                return;
            }
            if (byId.size() < capacity) {
                c = new Counter(id, w, 0);
            } else {
                Counter min = byCount.pollFirst();
                byId.remove(min.id);
                c = new Counter(id, min.count + w, min.count);  // inherit the evicted count as error
            }
            byId.put(id, c);
            byCount.add(c);
        }

        List<Counter> top(int k) { return byCount.descendingSet().stream().limit(k).toList(); }
    }

    static void extensionB(Map<String, Long> truth) {
        long w = truth.values().stream().mapToLong(Long::longValue).sum();
        List<Talker> want = topK(truth, K);
        System.out.printf("Extension B - one pass, bounded memory (W = %,d bytes in the stream)%n", w);
        for (int m : new int[] {1_000, 100, 20}) {
            SpaceSaving ss = new SpaceSaving(m);
            long t0 = System.nanoTime();
            for (int i = 0; i < N; i++) ss.add(NAMES[EV_CLIENT[i]], EV_BYTES[i]);
            double ns = (System.nanoTime() - t0) / (double) N;
            List<SpaceSaving.Counter> top = ss.top(K + 1);
            Set<String> wantIds = new HashSet<>();
            for (Talker t : want) wantIds.add(t.clientId());
            int recall = 0;
            long maxOver = 0;
            boolean order = true;
            for (int i = 0; i < K; i++) {
                SpaceSaving.Counter c = top.get(i);
                if (wantIds.contains(c.id)) recall++;
                maxOver = Math.max(maxOver, c.count - truth.getOrDefault(c.id, 0L));
                order &= c.id.equals(want.get(i).clientId());
            }
            // Certified: the 10th estimate's guaranteed part beats the 11th estimate's upper bound.
            boolean certified = top.get(K - 1).count - top.get(K - 1).error >= top.get(K).count;
            System.out.printf("    m=%,5d counters (%.2f%% of U): recall %2d/10, order %-5s max overestimate %,9d"
                            + " (bound W/m %,11d), set certified: %-5b %4.0f ns/event%n",
                    m, 100.0 * m / U, recall, order ? "exact" : "off", maxOver, w / m, certified, ns);
        }
    }

    // ===================================================================== Extension C: 16 shards
    static List<Talker> localTopK(Map<String, Long> shard, int k) { return topK(shard, k); }

    /** Partitioning needs a SPECIFIED hash (FNV-1a 64), identical in every process, version and language. */
    static int shardOf(String id, int shards) {
        long h = 0xcbf29ce484222325L;
        for (int i = 0; i < id.length(); i++) h = (h ^ id.charAt(i)) * 0x100000001b3L;
        return (int) Long.remainderUnsigned(h, shards);
    }

    /** Each shard ships its local top-k; the coordinator sums what it received. Exact only for key partitioning. */
    static List<Talker> naiveMerge(List<Map<String, Long>> shards, int k) {
        Map<String, Long> sum = new HashMap<>();
        for (Map<String, Long> s : shards) for (Talker t : localTopK(s, k)) sum.merge(t.clientId(), t.bytes(), Long::sum);
        return topK(sum, k);
    }

    /** TPUT (Cao & Wang, PODC 2004): exact top-k over ANY partitioning in three round trips. */
    static List<Talker> tput(List<Map<String, Long>> shards, int k, long[] shipped) {
        int s = shards.size();
        Map<String, Long> partial = new HashMap<>();
        Map<String, Integer> reporters = new HashMap<>();
        List<Set<String>> sent = new ArrayList<>();
        for (int i = 0; i < s; i++) sent.add(new HashSet<>());
        for (int i = 0; i < s; i++) {                                   // phase 1: local top-k
            for (Talker t : localTopK(shards.get(i), k)) {
                partial.merge(t.clientId(), t.bytes(), Long::sum);
                reporters.merge(t.clientId(), 1, Integer::sum);
                sent.get(i).add(t.clientId());
                shipped[0]++;
            }
        }
        long tau1 = kthLargest(partial.values(), k);
        long threshold = Math.ceilDiv(tau1, s);  // a top-k item's total >= tau1, so some shard holds >= tau1/s
        for (int i = 0; i < s; i++) {                                   // phase 2: everything >= threshold
            for (Map.Entry<String, Long> e : shards.get(i).entrySet()) {
                if (e.getValue() >= threshold && sent.get(i).add(e.getKey())) {
                    partial.merge(e.getKey(), e.getValue(), Long::sum);
                    reporters.merge(e.getKey(), 1, Integer::sum);
                    shipped[1]++;
                }
            }
        }
        long tau2 = kthLargest(partial.values(), k);
        long unseenMax = Math.max(threshold - 1, 0);                    // an unreported local value is < threshold
        Map<String, Long> exact = new HashMap<>();
        for (Map.Entry<String, Long> e : partial.entrySet()) {          // phase 3: exact totals for survivors
            long upper = e.getValue() + (s - reporters.get(e.getKey())) * unseenMax;
            if (upper < tau2) continue;
            long total = 0;
            for (int i = 0; i < s; i++) {
                total += shards.get(i).getOrDefault(e.getKey(), 0L);
                if (!sent.get(i).contains(e.getKey())) shipped[2]++;
            }
            exact.put(e.getKey(), total);
        }
        return topK(exact, k);
    }

    static long kthLargest(java.util.Collection<Long> values, int k) {
        long[] v = values.stream().mapToLong(Long::longValue).toArray();
        if (v.length < k) return 0;
        Arrays.sort(v);
        return v[v.length - k];
    }

    static void compare(String name, List<Map<String, Long>> shards, List<Talker> want, int k) {
        long all = shards.stream().mapToLong(Map::size).sum();
        List<Talker> naive = naiveMerge(shards, k);
        long[] shipped = new long[3];
        List<Talker> exact = tput(shards, k, shipped);
        int wrongTotals = 0;
        for (int i = 0; i < naive.size(); i++) if (!naive.get(i).equals(want.get(i))) wrongTotals++;
        System.out.printf("    %-34s naive merge: %-5s (%d/%d entries wrong), ships %,d%n", name,
                naive.equals(want) ? "exact" : "WRONG", wrongTotals, k, (long) shards.size() * k);
        System.out.printf("    %-34s TPUT:        %-5s ships %,d + %,d + %,d = %,d of %,d (%.2f%%)%n", "",
                exact.equals(want) ? "exact" : "WRONG", shipped[0], shipped[1], shipped[2],
                shipped[0] + shipped[1] + shipped[2], all, 100.0 * (shipped[0] + shipped[1] + shipped[2]) / all);
    }

    static void extensionC(Map<String, Long> truth) {
        List<Talker> want = topK(truth, K);
        System.out.printf("Extension C - %d shards, coordinator merges partial answers%n", SHARDS);
        List<Map<String, Long>> byKey = new ArrayList<>(), byArrival = new ArrayList<>();
        for (int i = 0; i < SHARDS; i++) {
            byKey.add(new HashMap<>());
            byArrival.add(new HashMap<>());
        }
        for (int i = 0; i < N; i++) {
            String id = NAMES[EV_CLIENT[i]];
            byKey.get(shardOf(id, SHARDS)).merge(id, (long) EV_BYTES[i], Long::sum);
            byArrival.get(i % SHARDS).merge(id, (long) EV_BYTES[i], Long::sum);
        }
        compare("partitioned by hash(clientId)", byKey, want, K);
        compare("partitioned by arrival (skewed)", byArrival, want, K);

        // Hourly shards: "steady" sends 60 every hour; three new burst clients send 100 each in one hour only;
        // 2,000 background events per hour send 1..5. Steady is 4th in EVERY hour and 1st overall.
        List<Map<String, Long>> hourly = new ArrayList<>();
        Map<String, Long> hourlyTruth = new HashMap<>();
        SplitMix64 r = new SplitMix64(9);
        for (int h = 0; h < SHARDS; h++) {
            Map<String, Long> m = new HashMap<>();
            m.put("steady", 60L);
            for (int b = 0; b < 3; b++) m.put("burst-" + (3 * h + b), 100L);
            for (int b = 0; b < 2_000; b++) m.merge("bg-" + r.nextInt(5_000), 1L + r.nextInt(5), Long::sum);
            m.forEach((id, v) -> hourlyTruth.merge(id, v, Long::sum));
            hourly.add(m);
        }
        compare("partitioned by hour (adversarial)", hourly, topK(hourlyTruth, 3), 3);
        System.out.printf("    hourly truth top-3 %s, naive merge says %s%n",
                topK(hourlyTruth, 3).stream().map(Talker::clientId).toList(),
                naiveMerge(hourly, 3).stream().map(Talker::clientId).toList());
    }

    public static void main(String[] args) throws InterruptedException {
        generate();
        Map<String, Long> truth = extensionA();
        extensionB(truth);
        extensionC(truth);
    }
}
```

**Output (one measured run; the correctness columns are deterministic except the racy row):**

```text
Extension A - 8 threads, N=8,000,000 events, U=100,000 clients (one measured run)
    1 thread HashMap                      1046.3 ms    7.6 M events/s  (baseline, also warms the JIT)
    shared HashMap, no lock (WRONG)        111.4 ms   71.8 M events/s  lost bytes 5,473,637,033  top-10 WRONG
        size() 97,570 vs iterated 97,570 entries; 7 of 8 workers died: [ConcurrentModificationException]
    one lock around HashMap               2049.5 ms    3.9 M events/s  lost bytes           0  top-10 exact
    ConcurrentHashMap.merge                230.5 ms   34.7 M events/s  lost bytes           0  top-10 exact
    ConcurrentHashMap<String, LongAdder>   129.0 ms   62.0 M events/s  lost bytes           0  top-10 exact
    thread-local Long maps + merge 69 ms   360.8 ms   22.2 M events/s  lost bytes           0  top-10 exact
    thread-local long[] cells + merge 67 ms   223.7 ms   35.8 M events/s  lost bytes           0  top-10 exact
Extension B - one pass, bounded memory (W = 6,255,615,525 bytes in the stream)
    m=1,000 counters (1.00% of U): recall 10/10, order exact max overestimate         0 (bound W/m   6,255,615), set certified: true   278 ns/event
    m=  100 counters (0.10% of U): recall  4/10, order off   max overestimate 59,552,748 (bound W/m  62,556,155), set certified: false  191 ns/event
    m=   20 counters (0.02% of U): recall  1/10, order off   max overestimate 310,732,899 (bound W/m 312,780,776), set certified: false  154 ns/event
Extension C - 16 shards, coordinator merges partial answers
    partitioned by hash(clientId)      naive merge: exact (0/10 entries wrong), ships 160
                                       TPUT:        exact ships 160 + 225 + 5,775 = 6,160 of 100,000 (6.16%)
    partitioned by arrival (skewed)    naive merge: WRONG (1/10 entries wrong), ships 160
                                       TPUT:        exact ships 160 + 11 + 0 = 171 of 1,398,977 (0.01%)
    partitioned by hour (adversarial)  naive merge: WRONG (3/3 entries wrong), ships 48
                                       TPUT:        exact ships 48 + 2,275 + 8,911 = 11,234 of 26,426 (42.51%)
    hourly truth top-3 [steady, burst-0, burst-1], naive merge says [burst-0, burst-1, burst-10]
```

### 4.2 Listing 1.6 — C++23

```cpp
// top_k_extensions.cpp - the last 10 minutes of top-K talkers: (A) 8 threads, (B) bounded-RAM stream, (C) 16 shards.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <mutex>
#include <numeric>
#include <print>
#include <set>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

constexpr int kU = 100'000, kN = 8'000'000, kThreads = 8, kK = 10, kShards = 16;

struct SvHash {
    using is_transparent = void;
    std::size_t operator()(std::string_view s) const noexcept { return std::hash<std::string_view>{}(s); }
};
using Totals = std::unordered_map<std::string, std::int64_t, SvHash, std::equal_to<>>;

struct Talker {
    std::string client_id;
    std::int64_t bytes{};
    friend bool operator==(const Talker&, const Talker&) = default;
};
struct RankBefore {
    bool operator()(const Talker& a, const Talker& b) const noexcept {
        return a.bytes != b.bytes ? a.bytes > b.bytes : a.client_id < b.client_id;
    }
};

std::vector<Talker> top_k(const Totals& totals, std::size_t k) {
    std::vector<Talker> all;
    all.reserve(totals.size());
    for (const auto& [id, b] : totals) all.push_back({id, b});
    auto mid = all.begin() + static_cast<std::ptrdiff_t>(std::min(k, all.size()));
    std::ranges::partial_sort(all, mid, RankBefore{});
    all.erase(mid, all.end());
    return all;
}

void add(Totals& m, std::string_view id, std::int64_t b) {
    if (auto it = m.find(id); it != m.end()) it->second += b;
    else m.emplace(std::string(id), b);
}

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int below(int bound) noexcept { return static_cast<int>(next() % static_cast<std::uint64_t>(bound)); }
    double unit() noexcept { return static_cast<double>(next() >> 11) * 0x1.0p-53; }
};

std::vector<std::string> g_names;
std::vector<int> g_client, g_bytes;

// Skewed traffic: P(client < x) = (x/U)^(1/4), so client-0 sends ~5.6% of all events (a hot key).
void generate() {
    for (int i = 0; i < kU; ++i) g_names.push_back("client-" + std::to_string(i));
    SplitMix64 r{42};
    g_client.resize(kN);
    g_bytes.resize(kN);
    for (std::size_t i = 0; i < kN; ++i) {
        double u = r.unit();
        g_client[i] = static_cast<int>(kU * (u * u * u * u));
        g_bytes[i] = 64 + r.below(1'437);
    }
}
const std::string& name_of(std::size_t i) { return g_names[static_cast<std::size_t>(g_client[i])]; }

// ======================================================================= Extension A: 8 threads
using clock_type = std::chrono::steady_clock;

// Start all workers behind a spin gate (with a ready count, so they really overlap); return wall ms.
template <class Body>
double parallel(Body body) {
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    clock_type::time_point t0;
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < kThreads; ++t) {
            auto lo = static_cast<std::size_t>(std::int64_t{kN} * t / kThreads);
            auto hi = static_cast<std::size_t>(std::int64_t{kN} * (t + 1) / kThreads);
            ts.emplace_back([&, t, lo, hi] {
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}
                body(t, lo, hi);
            });
        }
        while (ready.load() < kThreads) {}
        t0 = clock_type::now();
        go.store(true, std::memory_order_release);
    }  // jthreads join here
    return std::chrono::duration<double, std::milli>(clock_type::now() - t0).count();
}

std::int64_t sum_of(const Totals& t) {
    return std::accumulate(t.begin(), t.end(), std::int64_t{0}, [](std::int64_t s, const auto& e) { return s + e.second; });
}

void report(std::string_view name, double ms, const Totals& totals, std::int64_t want_bytes,
            const std::vector<Talker>& want) {
    std::println("    {:<38} {:7.1f} ms {:6.1f} M events/s  lost bytes {:11}  top-10 {}", name, ms, kN / ms / 1e3,
                 want_bytes - sum_of(totals), top_k(totals, kK) == want ? "exact" : "WRONG");
}

Totals from_dense(const std::vector<std::int64_t>& dense) {
    Totals t;
    for (std::size_t i = 0; i < dense.size(); ++i)
        if (dense[i] != 0) t.emplace(g_names[i], dense[i]);
    return t;
}

Totals extension_a() {
    auto t0 = clock_type::now();
    Totals truth;
    for (std::size_t i = 0; i < kN; ++i) add(truth, name_of(i), g_bytes[i]);
    double single_ms = std::chrono::duration<double, std::milli>(clock_type::now() - t0).count();
    std::int64_t want_bytes = sum_of(truth);
    auto want = top_k(truth, kK);
    std::println("Extension A - {} threads, N={} events, U={} clients (one measured run)", kThreads, kN, kU);
    std::println("    {:<38} {:7.1f} ms {:6.1f} M events/s  (baseline)", "1 thread unordered_map", single_ms,
                 kN / single_ms / 1e3);
    std::println("    {:<38} not run: a data race on a std::unordered_map is UB (TSan reports it)",
                 "shared unordered_map, no lock");

    Totals locked;
    std::mutex mu;
    double ms = parallel([&](int, std::size_t lo, std::size_t hi) {
        for (std::size_t i = lo; i < hi; ++i) {
            std::scoped_lock lock(mu);
            add(locked, name_of(i), g_bytes[i]);
        }
    });
    report("one mutex around unordered_map", ms, locked, want_bytes, want);

    struct alignas(64) Stripe {
        std::mutex mu;
        Totals map;
    };
    std::vector<Stripe> stripes(64);
    ms = parallel([&](int, std::size_t lo, std::size_t hi) {
        for (std::size_t i = lo; i < hi; ++i) {
            const auto& id = name_of(i);
            auto& s = stripes[SvHash{}(id) % stripes.size()];
            std::scoped_lock lock(s.mu);
            add(s.map, id, g_bytes[i]);
        }
    });
    Totals striped;
    for (auto& s : stripes) striped.merge(s.map);  // keys are disjoint across stripes
    report("64 lock stripes", ms, striped, want_bytes, want);

    std::vector<Totals> local(kThreads);
    ms = parallel([&](int t, std::size_t lo, std::size_t hi) {
        Totals mine;
        for (std::size_t i = lo; i < hi; ++i) add(mine, name_of(i), g_bytes[i]);
        local[static_cast<std::size_t>(t)] = std::move(mine);
    });
    auto m0 = clock_type::now();
    Totals merged;
    for (const auto& m : local)
        for (const auto& [id, b] : m) add(merged, id, b);
    double merge_ms = std::chrono::duration<double, std::milli>(clock_type::now() - m0).count();
    report(std::format("thread-local maps + merge {:.0f} ms", merge_ms), ms + merge_ms, merged, want_bytes, want);

    // Dense ids (clients dictionary-encoded to 0..U-1) open up array-based strategies.
    std::vector<std::atomic<std::int64_t>> packed(kU);
    ms = parallel([&](int, std::size_t lo, std::size_t hi) {
        for (std::size_t i = lo; i < hi; ++i)
            packed[static_cast<std::size_t>(g_client[i])].fetch_add(g_bytes[i], std::memory_order_relaxed);
    });
    std::vector<std::int64_t> dense(kU);
    for (std::size_t i = 0; i < kU; ++i) dense[i] = packed[i].load();
    report("dense ids: atomic<int64>[U] fetch_add", ms, from_dense(dense), want_bytes, want);

    struct alignas(64) Padded {
        std::atomic<std::int64_t> v{0};
    };
    std::vector<Padded> padded(kU);
    ms = parallel([&](int, std::size_t lo, std::size_t hi) {
        for (std::size_t i = lo; i < hi; ++i)
            padded[static_cast<std::size_t>(g_client[i])].v.fetch_add(g_bytes[i], std::memory_order_relaxed);
    });
    for (std::size_t i = 0; i < kU; ++i) dense[i] = padded[i].v.load();
    report("dense ids: 64B-padded atomics", ms, from_dense(dense), want_bytes, want);

    std::vector<std::vector<std::int64_t>> per_thread(kThreads);
    ms = parallel([&](int t, std::size_t lo, std::size_t hi) {
        std::vector<std::int64_t> mine(kU);
        for (std::size_t i = lo; i < hi; ++i) mine[static_cast<std::size_t>(g_client[i])] += g_bytes[i];
        per_thread[static_cast<std::size_t>(t)] = std::move(mine);
    });
    m0 = clock_type::now();
    std::ranges::fill(dense, 0);
    for (const auto& v : per_thread)
        for (std::size_t i = 0; i < kU; ++i) dense[i] += v[i];
    merge_ms = std::chrono::duration<double, std::milli>(clock_type::now() - m0).count();
    report(std::format("dense ids: thread-local arrays + merge {:.1f} ms", merge_ms), ms + merge_ms, from_dense(dense),
           want_bytes, want);
    return truth;
}

// ======================================================================= Extension B: bounded RAM
// Weighted Space-Saving (Metwally et al. 2005): m counters, every estimate within W/m of the truth.
class SpaceSaving {
public:
    struct Slot {
        std::int64_t count;
        std::string id;
        auto operator<=>(const Slot&) const = default;
    };
    explicit SpaceSaving(std::size_t capacity) : capacity_(capacity) {}

    void add(const std::string& id, std::int64_t w) {
        if (auto it = by_id_.find(id); it != by_id_.end()) {
            // std::set keys are const: the type system forbids the in-place edit that silently corrupts a Java
            // TreeSet. extract() hands out the node, we edit it, insert() relinks it without reallocating.
            auto node = by_count_.extract(it->second.where);
            node.value().count += w;
            it->second.where = by_count_.insert(std::move(node)).position;
            return;
        }
        std::int64_t error = 0;
        if (by_id_.size() == capacity_) {
            auto node = by_count_.extract(by_count_.begin());
            error = node.value().count;  // inherit the evicted count as this counter's error
            by_id_.erase(node.value().id);
            node.value() = Slot{error + w, id};
            by_id_.emplace(id, Entry{by_count_.insert(std::move(node)).position, error});
            return;
        }
        by_id_.emplace(id, Entry{by_count_.insert(Slot{w, id}).first, 0});
    }

    struct Estimate {
        std::string id;
        std::int64_t count, error;
    };
    std::vector<Estimate> top(std::size_t k) const {
        std::vector<Estimate> out;
        for (auto it = by_count_.rbegin(); it != by_count_.rend() && out.size() < k; ++it)
            out.push_back({it->id, it->count, by_id_.at(it->id).error});
        return out;
    }

private:
    struct Entry {
        std::set<Slot>::iterator where;
        std::int64_t error;
    };
    std::size_t capacity_;
    std::set<Slot> by_count_;
    std::unordered_map<std::string, Entry> by_id_;
};

void extension_b(const Totals& truth) {
    std::int64_t w = sum_of(truth);
    auto want = top_k(truth, kK);
    std::println("Extension B - one pass, bounded memory (W = {} bytes in the stream)", w);
    for (int m : {1'000, 100, 20}) {
        SpaceSaving ss(static_cast<std::size_t>(m));
        auto t0 = clock_type::now();
        for (std::size_t i = 0; i < kN; ++i) ss.add(name_of(i), g_bytes[i]);
        double ns = std::chrono::duration<double, std::nano>(clock_type::now() - t0).count() / kN;
        auto top = ss.top(kK + 1);
        std::unordered_set<std::string> want_ids;
        for (const auto& t : want) want_ids.insert(t.client_id);
        int recall = 0;
        std::int64_t max_over = 0;
        bool order = true;
        for (std::size_t i = 0; i < kK; ++i) {
            recall += want_ids.contains(top[i].id);
            auto it = truth.find(top[i].id);
            max_over = std::max(max_over, top[i].count - (it == truth.end() ? 0 : it->second));
            order = order && top[i].id == want[i].client_id;
        }
        bool certified = top[kK - 1].count - top[kK - 1].error >= top[kK].count;
        std::println("    m={:5} counters ({:.2f}% of U): recall {:2}/10, order {:<5} max overestimate {:9}"
                     " (bound W/m {:11}), set certified: {:<5} {:4.0f} ns/event",
                     m, 100.0 * m / kU, recall, order ? "exact" : "off", max_over, w / m, certified, ns);
    }
}

// ======================================================================= Extension C: 16 shards
// Partitioning needs a SPECIFIED hash: std::hash only promises consistency within one execution of one program.
std::size_t shard_of(std::string_view id, std::size_t shards) {
    std::uint64_t h = 0xcbf29ce484222325ULL;
    for (char c : id) h = (h ^ static_cast<unsigned char>(c)) * 0x100000001b3ULL;
    return static_cast<std::size_t>(h % shards);
}

std::vector<Talker> naive_merge(const std::vector<Totals>& shards, std::size_t k) {
    Totals sum;
    for (const auto& s : shards)
        for (const auto& t : top_k(s, k)) add(sum, t.client_id, t.bytes);
    return top_k(sum, k);
}

std::int64_t kth_largest(const Totals& m, std::size_t k) {
    std::vector<std::int64_t> v;
    for (const auto& [id, b] : m) v.push_back(b);
    if (v.size() < k) return 0;
    std::ranges::sort(v);
    return v[v.size() - k];
}

// TPUT (Cao & Wang, PODC 2004): exact top-k over ANY partitioning in three round trips.
std::vector<Talker> tput(const std::vector<Totals>& shards, std::size_t k, std::int64_t shipped[3]) {
    const auto s = static_cast<std::int64_t>(shards.size());
    Totals partial;
    std::unordered_map<std::string, std::int64_t> reporters;
    std::vector<std::unordered_set<std::string>> sent(shards.size());
    for (std::size_t i = 0; i < shards.size(); ++i) {  // phase 1: local top-k
        for (const auto& t : top_k(shards[i], k)) {
            add(partial, t.client_id, t.bytes);
            ++reporters[t.client_id];
            sent[i].insert(t.client_id);
            ++shipped[0];
        }
    }
    std::int64_t tau1 = kth_largest(partial, k);
    std::int64_t threshold = (tau1 + s - 1) / s;  // a top-k item's total >= tau1, so some shard holds >= tau1/s
    for (std::size_t i = 0; i < shards.size(); ++i) {  // phase 2: everything >= threshold
        for (const auto& [id, v] : shards[i]) {
            if (v >= threshold && sent[i].insert(id).second) {
                add(partial, id, v);
                ++reporters[id];
                ++shipped[1];
            }
        }
    }
    std::int64_t tau2 = kth_largest(partial, k);
    std::int64_t unseen_max = std::max<std::int64_t>(threshold - 1, 0);  // an unreported local value is < threshold
    Totals exact;
    for (const auto& [id, lower] : partial) {  // phase 3: exact totals for survivors
        if (lower + (s - reporters[id]) * unseen_max < tau2) continue;
        std::int64_t total = 0;
        for (std::size_t i = 0; i < shards.size(); ++i) {
            if (auto it = shards[i].find(id); it != shards[i].end()) total += it->second;
            if (!sent[i].contains(id)) ++shipped[2];
        }
        exact.emplace(id, total);
    }
    return top_k(exact, k);
}

void compare(std::string_view name, const std::vector<Totals>& shards, const std::vector<Talker>& want, std::size_t k) {
    std::int64_t all = 0;
    for (const auto& s : shards) all += static_cast<std::int64_t>(s.size());
    auto naive = naive_merge(shards, k);
    std::int64_t shipped[3] = {0, 0, 0};
    auto exact = tput(shards, k, shipped);
    std::size_t wrong = 0;
    for (std::size_t i = 0; i < naive.size(); ++i) wrong += !(naive[i] == want[i]);
    std::println("    {:<34} naive merge: {:<5} ({}/{} entries wrong), ships {}", name, naive == want ? "exact" : "WRONG",
                 wrong, k, shards.size() * k);
    std::int64_t total = shipped[0] + shipped[1] + shipped[2];
    std::println("    {:<34} TPUT:        {:<5} ships {} + {} + {} = {} of {} ({:.2f}%)", "", exact == want ? "exact" : "WRONG",
                 shipped[0], shipped[1], shipped[2], total, all, 100.0 * static_cast<double>(total) / static_cast<double>(all));
}

std::string ids_of(const std::vector<Talker>& ts) {
    std::string s = "[";
    for (std::size_t i = 0; i < ts.size(); ++i) s += (i ? ", " : "") + ts[i].client_id;
    return s + "]";
}

void extension_c(const Totals& truth) {
    auto want = top_k(truth, kK);
    std::println("Extension C - {} shards, coordinator merges partial answers", kShards);
    std::vector<Totals> by_key(kShards), by_arrival(kShards);
    for (std::size_t i = 0; i < kN; ++i) {
        const auto& id = name_of(i);
        add(by_key[shard_of(id, kShards)], id, g_bytes[i]);
        add(by_arrival[i % kShards], id, g_bytes[i]);
    }
    compare("partitioned by hash(clientId)", by_key, want, kK);
    compare("partitioned by arrival (skewed)", by_arrival, want, kK);

    // Hourly shards: "steady" sends 60 every hour; three new burst clients send 100 each in one hour only;
    // 2,000 background events per hour send 1..5. Steady is 4th in EVERY hour and 1st overall.
    std::vector<Totals> hourly(kShards);
    Totals hourly_truth;
    SplitMix64 r{9};
    for (std::size_t h = 0; h < kShards; ++h) {
        auto& m = hourly[h];
        add(m, "steady", 60);
        for (std::size_t b = 0; b < 3; ++b) add(m, "burst-" + std::to_string(3 * h + b), 100);
        for (int b = 0; b < 2'000; ++b) {
            auto who = "bg-" + std::to_string(r.below(5'000));  // two statements: argument order is unspecified
            add(m, who, 1 + r.below(5));
        }
        for (const auto& [id, v] : m) add(hourly_truth, id, v);
    }
    compare("partitioned by hour (adversarial)", hourly, top_k(hourly_truth, 3), 3);
    std::println("    hourly truth top-3 {}, naive merge says {}", ids_of(top_k(hourly_truth, 3)),
                 ids_of(naive_merge(hourly, 3)));
}

int main() {
    generate();
    auto truth = extension_a();
    extension_b(truth);
    extension_c(truth);
}
```

**Output, GCC 16.2 (one measured run):**

```text
Extension A - 8 threads, N=8000000 events, U=100000 clients (one measured run)
    1 thread unordered_map                  2059.8 ms    3.9 M events/s  (baseline)
    shared unordered_map, no lock          not run: a data race on a std::unordered_map is UB (TSan reports it)
    one mutex around unordered_map          5370.1 ms    1.5 M events/s  lost bytes           0  top-10 exact
    64 lock stripes                          529.9 ms   15.1 M events/s  lost bytes           0  top-10 exact
    thread-local maps + merge 263 ms         640.5 ms   12.5 M events/s  lost bytes           0  top-10 exact
    dense ids: atomic<int64>[U] fetch_add     29.8 ms  268.3 M events/s  lost bytes           0  top-10 exact
    dense ids: 64B-padded atomics             21.3 ms  375.3 M events/s  lost bytes           0  top-10 exact
    dense ids: thread-local arrays + merge 0.5 ms     5.9 ms 1353.6 M events/s  lost bytes           0  top-10 exact
Extension B - one pass, bounded memory (W = 6255615525 bytes in the stream)
    m= 1000 counters (1.00% of U): recall 10/10, order exact max overestimate         0 (bound W/m     6255615), set certified: true   410 ns/event
    m=  100 counters (0.10% of U): recall  4/10, order off   max overestimate  59552748 (bound W/m    62556155), set certified: false  330 ns/event
    m=   20 counters (0.02% of U): recall  1/10, order off   max overestimate 310732899 (bound W/m   312780776), set certified: false  638 ns/event
Extension C - 16 shards, coordinator merges partial answers
    partitioned by hash(clientId)      naive merge: exact (0/10 entries wrong), ships 160
                                       TPUT:        exact ships 160 + 225 + 5775 = 6160 of 100000 (6.16%)
    partitioned by arrival (skewed)    naive merge: WRONG (1/10 entries wrong), ships 160
                                       TPUT:        exact ships 160 + 11 + 0 = 171 of 1398977 (0.01%)
    partitioned by hour (adversarial)  naive merge: WRONG (3/3 entries wrong), ships 48
                                       TPUT:        exact ships 48 + 2275 + 8911 = 11234 of 26426 (42.51%)
    hourly truth top-3 [steady, burst-0, burst-1], naive merge says [burst-0, burst-1, burst-10]
```

**Output, Clang 21.1 (one measured run):**

```text
Extension A - 8 threads, N=8000000 events, U=100000 clients (one measured run)
    1 thread unordered_map                  1311.0 ms    6.1 M events/s  (baseline)
    shared unordered_map, no lock          not run: a data race on a std::unordered_map is UB (TSan reports it)
    one mutex around unordered_map          2474.3 ms    3.2 M events/s  lost bytes           0  top-10 exact
    64 lock stripes                          378.6 ms   21.1 M events/s  lost bytes           0  top-10 exact
    thread-local maps + merge 166 ms         537.4 ms   14.9 M events/s  lost bytes           0  top-10 exact
    dense ids: atomic<int64>[U] fetch_add     27.9 ms  286.6 M events/s  lost bytes           0  top-10 exact
    dense ids: 64B-padded atomics             19.8 ms  403.5 M events/s  lost bytes           0  top-10 exact
    dense ids: thread-local arrays + merge 0.5 ms     4.3 ms 1876.7 M events/s  lost bytes           0  top-10 exact
Extension B - one pass, bounded memory (W = 6255615525 bytes in the stream)
    m= 1000 counters (1.00% of U): recall 10/10, order exact max overestimate         0 (bound W/m     6255615), set certified: true   338 ns/event
    m=  100 counters (0.10% of U): recall  4/10, order off   max overestimate  59552748 (bound W/m    62556155), set certified: false  281 ns/event
    m=   20 counters (0.02% of U): recall  1/10, order off   max overestimate 310732899 (bound W/m   312780776), set certified: false  289 ns/event
Extension C - 16 shards, coordinator merges partial answers
    partitioned by hash(clientId)      naive merge: exact (0/10 entries wrong), ships 160
                                       TPUT:        exact ships 160 + 225 + 5775 = 6160 of 100000 (6.16%)
    partitioned by arrival (skewed)    naive merge: WRONG (1/10 entries wrong), ships 160
                                       TPUT:        exact ships 160 + 11 + 0 = 171 of 1398977 (0.01%)
    partitioned by hour (adversarial)  naive merge: WRONG (3/3 entries wrong), ships 48
                                       TPUT:        exact ships 48 + 2275 + 8911 = 11234 of 26426 (42.51%)
    hourly truth top-3 [steady, burst-0, burst-1], naive merge says [burst-0, burst-1, burst-10]
```

Phases B and C print identical numbers in Java and both C++ builds. The traffic comes from the same SplitMix64 stream, and shards are chosen with the same FNV-1a hash (see §4.5). That gives you three independent implementations agreeing on every count.

### 4.3 Extension A — "64 threads call this concurrently"

The laptop has 12 hardware threads, so the listing runs 8 workers over 8,000,000 events with a hot key (client-0 receives about 5.6% of all events). Scale the conclusions, not the numbers.

| Strategy | Java (ms) | C++ GCC / Clang (ms) | Correct? | Why |
|---|---|---|---|---|
| 1 thread, plain map | 1,046 | 2,060 / 1,311 | yes | Baseline |
| Shared map, **no lock** | 111 | not run (UB) | **no** | Lost 5.47 × 10⁹ of 6.26 × 10⁹ bytes; 7 of 8 workers died |
| One lock around the map | 2,050 | 5,370 / 2,474 | yes | **Slower than one thread**: every event serializes, plus lock hand-off |
| `ConcurrentHashMap.merge` | 231 | — | yes | Lock per bin; the hot client's bin is a serialization point |
| `CHM<String, LongAdder>` | 129 | — | yes | Lock-free fast path after the first insert; `LongAdder` stripes the hot counter |
| 64 lock stripes | — | 530 / 379 | yes | Same idea, manual: contention divided by 64, hot key still on one stripe |
| Thread-local maps + merge | 361 (boxed `Long`) / 224 (`long[]` cells) | 641 / 537 | yes | No sharing, but 8 private copies of a 100k-entry map, plus a serial merge |
| Dense ids, `atomic<int64>[U]` | — | 30 / 28 | yes | No hashing: an index and a `fetch_add` |
| Dense ids, 64-byte-padded atomics | — | 21 / 20 | yes | Removes false sharing among the hot ids 0–9 |
| Dense ids, thread-local arrays + merge | — | **6 / 4** | yes | 800 KB per thread, sequential merge of 8 × 100k longs |

What the numbers say, beyond "use a concurrent map":

1. **The unsynchronized map is not slow-and-wrong; it is fast-and-wrong.** It is also wrong in a way that varies from run to run. `HashMap.merge` checks its modification count and, "on a best-effort basis", throws `ConcurrentModificationException`; 7 of the 8 workers died that way. The map left behind was corrupt. In most development runs a **later, single-threaded** `stream().sorted()` over it threw `ArrayIndexOutOfBoundsException`, because `size()` disagreed with the entries actually reachable. In the spliced run it returned a wrong top-10 instead. A data race does not fail where it happens. It fails wherever the corrupted structure is next read. In C++ it is undefined behaviour, which is why the listing refuses to run it.
2. **One big lock is worse than no parallelism.** About 1.9–2.6× slower than a single thread. The critical section is so short that lock hand-off dominates.
3. **"Thread-local and merge" is not automatically fastest.** Shared-nothing multiplies the working set: eight private 70–100k-entry maps no longer fit in the 12 MiB L3, while one shared `ConcurrentHashMap<String, LongAdder>` does. The final merge is also serial (67–263 ms here). Removing the per-event `Long` allocation (the `long[]` cell variant, 224 vs 361 ms) recovered more than half of the gap to `LongAdder`, so the boxing cost is real, but it was not the whole story.
4. **Representation beats synchronization by two orders of magnitude.** Dictionary-encode client ids to dense integers (a one-time `String → int` map at ingest) and the same aggregation takes 4–6 ms with thread-local arrays, roughly **100× faster** than any string-keyed concurrent map. Interviewers rarely expect this answer, and it is the one that most clearly sounds like someone who has run such a system.
5. **Padding is real but small, and not guaranteed.** Padding each dense counter to 64 bytes removed false sharing among the hot ids 0–9. That was worth up to 1.4× in this run, but one earlier development run on GCC showed the packed array ahead. Padding multiplies the footprint by 8 (6.4 MB here) and costs cache capacity for the cold keys. Measure before claiming it.

**The script (about 90 seconds):** "Correctness first. A shared `HashMap` is a data race; I'd never ship it. The baseline is `ConcurrentHashMap<String, LongAdder>`: lock-free reads, striped counters for hot keys. If the profile shows the map itself is the bottleneck, I'd pre-aggregate per thread and merge, and that is exactly why `TalkerAccumulator` has a `merge` method. For real throughput, dictionary-encode the ids and aggregate into per-thread arrays. Then `topK` becomes a read on a snapshot, so readers never block writers."

### 4.4 Extension B — "Infinite stream, or 100 TB, and 1 GB of RAM"

Two different questions hide here, and the L7 move is to separate them.

**B1. Infinite stream, approximate answer acceptable → a sketch with a guarantee.** Weighted **Space-Saving** (Metwally, Agrawal and El Abbadi, 2005) keeps `m` counters. When a new client arrives and the table is full, it evicts the minimum counter and the newcomer **inherits** that count as its error. Every estimate then satisfies `true ≤ estimate ≤ true + W/m`, where `W` is the total weight seen. Any client heavier than `W/m` is guaranteed to be monitored. The measured results:

| Counters `m` | Memory vs exact | Recall of true top-10 | Max overestimate | Bound `W/m` | Top-10 set certified? |
|---|---|---|---|---|---|
| 1,000 | 1% of clients | 10/10, exact order | 0 | 6.26 M | **yes** |
| 100 | 0.1% | 4/10 | 59.6 M | 62.6 M | no |
| 20 | 0.02% | 1/10 | 310.7 M | 312.8 M | no |

The overestimate always stays under `W/m`: the guarantee holds even when the answer is poor. **Certification** is the production detail. If the k-th counter's guaranteed part (`count − error`) is at least the (k+1)-th counter's estimate, the top-k **set** is provably exact, and the system can say so in its response. With `m = 1,000` it could. With 100 or 20 it knew it could not, which beats silently returning a wrong list.

Implementation trap (both languages): the counters live in an ordered set **keyed by a field you are about to change**. In Java, mutating `count` while the counter sits in the `TreeSet` silently corrupts the tree, so the listing removes, mutates and re-inserts. C++ `std::set` elements are `const`, so the type system forbids the bug outright. The idiomatic fix is `extract()` → edit the node → `insert()`, which relinks the same node without reallocating.

**B2. A 100 TB file, exact answer required → external aggregation.** One pass that hash-partitions records by `clientId` into `P` spill files, sized so each partition's distinct clients fit in RAM. Then one pass per partition with an in-memory accumulator, keeping a global size-k heap across partitions. Cost: two sequential reads and one sequential write of the data, and no sort. This is the I/O-model reasoning of File 02 and the core of Folder 07. If one client is so hot that its partition overflows, that partition is split again by a second hash, or the heavy hitters found in B1 are handled out-of-band.

### 4.5 Extension C — "100 machines"

**C1. If you can choose the partitioning, choose the key.** Route each record by `hash(clientId) mod S`. Every client then lives entirely on one shard, local totals are global totals, and the coordinator merges `S` local top-k lists **exactly** (160 entries shipped for 16 shards × k = 10). The mergeable-accumulator property tested in §2 is precisely what makes this correct.

**The partition function must be specified.** `std::hash` is only required to give the same result within **one execution of one program**; implementations may salt it, and libstdc++ and libc++ differ. Java's `String.hashCode` is specified, but tying an on-disk or on-wire layout to it couples you to Java. The listing uses FNV-1a 64 in both languages, which is why every shard holds identical data in all three builds. In production use a published hash (FNV, xxHash, Murmur3) and version the choice, because changing it reshuffles every shard.

**C2. If the data is already partitioned by something else** (by arrival, by time, by data centre), naive "local top-k, then merge" is **wrong**:

* **Partitioned by arrival:** one of ten totals came back wrong. A client outside some shard's local top-10 is under-counted.
* **Partitioned by hour (adversarial but realistic):** client `steady` sends 60 bytes every hour, 960 in total, the largest by far. Every hour, though, three burst clients send 100 each, so `steady` is 4th in **every** shard and never shipped. The naive merge answered `[burst-0, burst-1, burst-10]`; the truth is `[steady, burst-0, burst-1]`.

**TPUT** (Cao and Wang, PODC 2004) is exact over any partitioning in three round trips:

1. Every shard sends its local top-k. The coordinator sums the partial scores and takes `τ₁`, the k-th largest partial sum. Any true top-k item has a total ≥ `τ₁`, so on **some** shard its local value is ≥ `τ₁ / S`.
2. Every shard sends every item with local value ≥ `T = ⌈τ₁ / S⌉`. The coordinator now has lower bounds, and upper bounds of `partial + (unreported shards) × (T − 1)`. It prunes every item whose upper bound is below `τ₂`, the new k-th largest lower bound.
3. Exact values are fetched for the survivors only.

The measured costs make the trade-off concrete. On arrival-partitioned data TPUT shipped **171 of 1,398,977** (shard, client) entries (0.01%) and was exact. On the adversarial hourly data it was still exact but shipped **42.5%**, because its upper bounds are loose when many items sit just under the threshold. On key-partitioned data it shipped 6.16% for an answer the naive merge gets with 160 entries. *Exactness is guaranteed; cost is data-dependent; and if you control the partitioning, partition by key and skip all of this.*

**C3. Hot keys break key partitioning.** If one client produces 30% of the traffic, the shard that owns it is the bottleneck. The standard fix is **salting**: split the key into `client#0 … client#7` across shards and sum at the coordinator. That reintroduces C2's merge problem for that key alone, so salt only keys a B1-style sketch has identified as heavy. That one sentence connects all three extensions.

---

## 5. Failure modes

| # | Failure | Where it bites | Symptom | Prevention |
|---|---|---|---|---|
| F1 | `int` accumulators | Any sum of ≥ 2 values near 2³¹ | Wrong ranking, no error (case 1) | Budget the maximum aloud; 64-bit sums; `Math.addExact` / checked add |
| F2 | Subtraction comparator | `(a, b) -> x[b] - x[a]` | Intransitive order; TimSort may throw "Comparison method violates its general contract" or return garbage (case 2) | `Comparator.comparingLong`, `Long.compare` |
| F3 | Undefined tie order | Heaps, hash-map iteration, unstable sorts | Output varies by JVM, standard library or run (43/48/50 diffs) | Total order in the contract, tested |
| F4 | Global mutable state | `static` arrays, singletons | Cross-request leakage (case 8) | Instance state; no statics with data |
| F5 | Input-bound constants | `MAXN`, `int` ids | Crash or silent aliasing (`stoi("10.0.0.7") == 10`) | Key by the real type; validate at the boundary |
| F6 | Midpoint / product overflow | Binary search on answer | Non-termination or wrong bound (§3) | `firstTrue` with written invariant; `std::midpoint`; division instead of multiplication |
| F7 | `double` for exact integer math | `sqrt`, `pow`, `log` on large longs | Off-by-one above 2⁵³ | Integer algorithms (`isqrt`), or verify-and-adjust |
| F8 | Unbounded recursion | DFS on chains or degenerate trees | `StackOverflowError`; C++ crash with no trace | Explicit stack; proven depth bound |
| F9 | Unspecified evaluation order (C++) | Two side effects in one argument list | Different behaviour per compiler | One side effect per full-expression |
| F10 | Unsynchronized shared map | "It's just counters" | Lost updates, delayed crashes, CME | Concurrent map + adders, or confinement + merge |
| F11 | Sorting by a mutable key | Space-Saving, schedulers, LRU | Corrupted `TreeSet`/heap, silent | Remove → mutate → reinsert; C++ `extract` |
| F12 | Merging local top-k of non-key partitions | Time/arrival-partitioned logs | Heavy, evenly spread keys disappear (`steady`) | Partition by key, or TPUT / threshold algorithms |
| F13 | Unstable partition hash | `std::hash`, language-specific hashes | Data on the "wrong" shard after an upgrade | Specified hash, versioned |

---

## 6. Bar-raiser chains

Each chain gives the prompt, a typical L5 answer, why that answer stalls at L5, and an answer that reads as L7.

<details><summary><b>Q1 · "Before you code — anything you want to ask?"</b></summary>

**Initial Prompt.** The interviewer has just stated the top-K problem and pauses.

**L5 Answer.** "How big is N? Can I assume the input fits in memory?" Then starts coding.

**Why L5 Stalls.** Size questions are necessary but not sufficient. The questions that change the *design* go unasked: ties, overflow, invalid input, k bounds, batch vs stream. So the interviewer has to inject them later, and each injection becomes a "prompted" note in the packet.

**L7 Answer.** "Let me write the signature first: `List<Talker> topK(int k)` over records `(String clientId, long bytes)`. Five questions: are ids strings or ints? Is a single `bytes` value bounded by 2³¹, and how many records, because totals overflow 32 bits after two max records? How should ties order? I'll propose bytes descending, then id ascending, so output is deterministic. What should `k > clients` and `k < 0` do? And is this a batch or a stream? If it might become a stream or get sharded, I'll make the accumulator mergeable from the start; it costs nothing now."
</details>

<details><summary><b>Q2 · "Why a heap and not just sort?"</b></summary>

**Initial Prompt.** Candidate proposes a size-k min-heap.

**L5 Answer.** "Heap is `O(N log k)`, sort is `O(N log N)`, so the heap is faster."

**Why L5 Stalls.** True but incomplete. It conflates `N` (records) with `U` (distinct clients), ignores the aggregation pass that dominates both, and offers no sense of when the difference matters.

**L7 Answer.** "Aggregation is `O(N)` expected and dominates. Selection over `U` distinct clients is `O(U log k)` with the heap vs `O(U log U)` with a sort. On about 10⁶ clients I measured 11–14 ms vs about 0.9 s in Java, partly because the sort also allocates a million result objects. If `k` approached `U` I'd switch to sort, or to quickselect for `O(U)` average. The heap also gives me `O(k)` extra space, which matters once this runs per shard."
</details>

<details><summary><b>Q3 · "Your code passed my examples. Are you done?"</b></summary>

**Initial Prompt.** The interviewer is inviting verification.

**L5 Answer.** Re-traces the sample input by hand.

**Why L5 Stalls.** The sample was chosen to be easy. Re-tracing it produces no new evidence on D5/D6.

**L7 Answer.** "Let me walk the edge-case table: empty log returns an empty list; one client; `k = 0`; `k` larger than the number of clients; two clients tied, where the contract says the smaller id wins; a total above 2³¹, which is why totals are `long` with `addExact`; negative bytes, rejected at `add`. Given ten more minutes I'd add a brute-force oracle (sum in a `TreeMap`, sort everything) and run a few thousand random small cases with values forced to collide, plus a property test that `merge` of two halves equals the whole."
</details>

<details><summary><b>Q4 · "64 threads now call add(). What breaks?"</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Wrap it in `synchronized`," or "use `ConcurrentHashMap`."

**Why L5 Stalls.** One mechanism, no cost, no failure mode. A single lock is measurably *slower than one thread* (about 2× here). `ConcurrentHashMap.merge` serializes the hot key's bin.

**L7 Answer.** "Correctness first: today it's a data race. A racy `HashMap` loses updates and can corrupt itself so that a later, unrelated read fails. Baseline fix: `ConcurrentHashMap<String, LongAdder>`, since `computeIfAbsent` is lock-free once the key exists and `LongAdder` stripes the hot counter. With a skewed workload I'd measure the hot key. If the map is the bottleneck, I'd confine state per thread and `merge` periodically: the accumulator is already mergeable. The big win is representation: dictionary-encode ids to ints at ingest, and per-thread arrays aggregate 8 M events in single-digit milliseconds instead of hundreds."
</details>

<details><summary><b>Q5 · "Now it's an infinite stream and you have 1 GB."</b></summary>

**Initial Prompt.** Extension B.

**L5 Answer.** "Keep a hash map of counts and a heap."

**Why L5 Stalls.** An unbounded key space makes the map unbounded. The candidate didn't notice that the question changed from *exact* to *approximate*.

**L7 Answer.** "Exactness and bounded memory conflict for an unbounded key space, so I'd confirm an approximate answer is acceptable. If so: Space-Saving with `m` counters, error at most `W/m` per estimate, and every item heavier than `W/m` guaranteed to be tracked. I'd size `m` from the tolerable error. I'd also return a *certified* flag, true when the k-th guaranteed count beats the (k+1)-th estimate. With 1% of the key space as counters I measured exact recall and certification on a skewed stream; with 0.1% recall dropped to 4/10, and the structure knew it. If the answer must be exact over a finite 100 TB file, it's external aggregation instead: hash-partition to disk, aggregate each partition in RAM. Two sequential passes, no sort."
</details>

<details><summary><b>Q6 · "The logs are on 100 machines."</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Each machine computes its top-K and sends it to a coordinator, which merges them."

**Why L5 Stalls.** Correct **only** when the data is partitioned by client. On time- or arrival-partitioned logs, an evenly spread heavy client is dropped from every local list. The measured hourly example returns three wrong answers out of three.

**L7 Answer.** "It depends on the partition key. If I can route by `hash(clientId)`, each client lives on one machine and merging local top-Ks is exact. That needs a specified hash, not `std::hash`, and versioning, because changing it moves every key. If the logs are partitioned by time, local top-K merge is wrong for clients that are moderate everywhere. Then I'd either reshuffle by key (one network shuffle) or run TPUT: three rounds, exact, usually shipping a tiny fraction of the data. Here 0.01% on arrival-partitioned data, but up to 42% on adversarial data. Hot keys get salted across shards, and only the keys a sketch has flagged as heavy."
</details>

<details><summary><b>Q7 · "Your binary search: is it correct for all inputs?"</b></summary>

**Initial Prompt.** The candidate wrote binary search on the answer for a capacity problem.

**L5 Answer.** Traces two examples and says yes.

**Why L5 Stalls.** Examples cannot show termination or overflow. `(lo + hi) / 2` and `mid * mid` pass every small test.

**L7 Answer.** "The invariant: everything left of `l` fails the predicate, and `h` satisfies it or is one past the range. `mid` is in `[l, h)` and each branch shrinks `h − l`, so it terminates. The midpoint never forms `l + h`, so it's correct for any signs, and the predicate divides rather than multiplies. The bounds are `long`, because `sum(weights)` exceeds 2³¹ with three packages of 10⁹. And the predicate is monotone: more capacity never needs more days."
</details>

<details><summary><b>Q8 · "Why did you make the result immutable? It's slower."</b></summary>

**Initial Prompt.** The interviewer probes the `List.of(...)` / return-by-value choice.

**L5 Answer.** "It's best practice."

**Why L5 Stalls.** An appeal to authority. No cost or benefit stated.

**L7 Answer.** "The copy is `O(k)` on a result of size k: noise compared with the `O(U)` scan. What it buys is that callers can't corrupt my state or each other's. The returned list can be cached, logged or handed to another thread without defensive copies, and once Extension A arrives an immutable snapshot is what lets readers proceed without locking writers. I'd only drop it if profiling showed the copy mattered, and on a top-10 it won't."
</details>

<details><summary><b>Q9 · "Your C++ add returns std::expected. Why not throw?"</b></summary>

**Initial Prompt.** C++ round; the interviewer probes error handling.

**L5 Answer.** "Exceptions are slow."

**Why L5 Stalls.** Folklore; the happy path of an exception is nearly free. The real reasons go unsaid.

**L7 Answer.** "Bad bytes and overflow are expected outcomes of untrusted input, not programming errors, so they belong in the return type, where the caller can't ignore them (`[[nodiscard]]`). Precondition violations that are bugs, like a negative `k` from my own code, I make unrepresentable instead (`std::size_t k`). I keep exceptions for truly exceptional failures like allocation. And `merge` gives the strong guarantee: check every sum first, then apply. So a failed merge has no partial effect."
</details>

<details><summary><b>Q10 · "Recursion or iteration for the DFS?"</b></summary>

**Initial Prompt.** A tree problem where the input can be a chain of 10⁶ nodes.

**L5 Answer.** Writes recursive DFS: "it's cleaner."

**Why L5 Stalls.** Depth is `O(n)` on a chain. The default Java main thread overflowed at about 15,000 frames here. In C++ the program dies with no trace, at a depth that depends on the toolchain's default stack (2 MiB vs 16 MiB for the two compilers used here).

**L7 Answer.** "Recursion depth equals tree height, which the input controls, so I'll iterate with an explicit stack. Same `O(n)`, the depth limit becomes a heap allocation, and failure would be an `OutOfMemoryError` I can see instead of a crash. If the tree were guaranteed balanced, recursion would be fine at depth `O(log n)`, and I'd say so in a comment."
</details>

---

## 7. Checklist: the 45-minute card

* [ ] Signature with **types** written in the first 2 minutes.
* [ ] Asked: id type, value bounds × count (overflow), **ties**, invalid input, `k` bounds, batch vs stream.
* [ ] Stated the brute force in one sentence, then the target, with its invariant and both complexities.
* [ ] Named one rejected alternative and why (sort vs heap vs quickselect).
* [ ] API shell first: types, contract comments, then bodies.
* [ ] Said "this could overflow" **before** writing the sum; used 64-bit / checked add.
* [ ] Comparator uses `compare`, never subtraction; total order including ties.
* [ ] No globals; no `MAXN`; result immutable or returned by value.
* [ ] Binary search via one invariant-documented helper; no `l + h`, no `mid * mid`.
* [ ] Recursion depth bounded or replaced by an explicit stack.
* [ ] Verification: edge-case table aloud; oracle and randomized differential test named.
* [ ] Extension A: mechanism → cost → failure mode; mentioned confinement + merge and representation.
* [ ] Extension B: separated "infinite + approximate" (sketch, error bound, certification) from "huge + exact" (external aggregation).
* [ ] Extension C: partitioning key first; specified, versioned hash; TPUT or reshuffle when not key-partitioned; salting for hot keys.

---

## 8. References

* Google re:Work, *A guide to structured interviewing for better hiring practices* — <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
* Joshua Bloch, *Extra, Extra — Read All About It: Nearly All Binary Searches and Mergesorts are Broken* (Google Research blog, 2006) — <https://research.google/blog/extra-extra-read-all-about-it-nearly-all-binary-searches-and-mergesorts-are-broken/>
* A. Metwally, D. Agrawal, A. El Abbadi, *Efficient Computation of Frequent and Top-k Elements in Data Streams*, ICDT 2005 — <https://link.springer.com/chapter/10.1007/978-3-540-30570-5_27>
* J. Misra, D. Gries, *Finding Repeated Elements*, Science of Computer Programming 2(2), 1982 — DOI 10.1016/0167-6423(82)90012-0
* P. Cao, Z. Wang, *Efficient Top-K Query Calculation in Distributed Networks*, PODC 2004 — DOI 10.1145/1011767.1011798
* Java SE 21 API: `Math.addExact` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Math.html>; `HashMap` (not synchronized; best-effort CME) — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/HashMap.html>; `ConcurrentHashMap` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/ConcurrentHashMap.html>; `LongAdder` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/atomic/LongAdder.html>; `Thread` (stack size) — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Thread.html>
* JEP 318, *Epsilon: A No-Op Garbage Collector* — <https://openjdk.org/jeps/318>
* cppreference: order of evaluation — <https://en.cppreference.com/w/cpp/language/eval_order>; `std::hash` (same result required only within one execution) — <https://en.cppreference.com/w/cpp/utility/hash>; `std::midpoint` — <https://en.cppreference.com/w/cpp/numeric/midpoint>; `std::expected` — <https://en.cppreference.com/w/cpp/utility/expected>; constant expressions (UB is not a core constant expression) — <https://en.cppreference.com/w/cpp/language/constant_expression>; `std::set::extract` — <https://en.cppreference.com/w/cpp/container/set/extract>
* FNV hash (specification and parameters) — <http://www.isthe.com/chongo/tech/comp/fnv/index.html>
* LeetCode problems used as anchors: [347 Top K Frequent Elements](https://leetcode.com/problems/top-k-frequent-elements/), [692 Top K Frequent Words](https://leetcode.com/problems/top-k-frequent-words/) (lexicographic ties), [69 Sqrt(x)](https://leetcode.com/problems/sqrtx/), [1011 Capacity To Ship Packages Within D Days](https://leetcode.com/problems/capacity-to-ship-packages-within-d-days/)

*Next in this folder:* [02 — cache-aware algorithms, branch prediction and hidden Big-O constants](02-cache-aware-algorithms-branch-prediction-and-hidden-big-o-constants.md) · [03 — API hygiene, immutability, custom iterators and test-driven verification](03-api-hygiene-immutability-custom-iterators-and-test-driven-verification.md)
