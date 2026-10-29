# K-Way External Merge Sort, Streaming Top-K and Sharded BFS Graph Traversal

> **Folder 07 · File 1 of 3** — what changes when the data no longer fits: a real external merge sort on disk under a 4 MB memory budget, a one-pass top-K that never holds more than K items, and a bulk-synchronous BFS over 8 shards that counts every network message. This file is where Extension B ("100 TB, bounded RAM") and Extension C ("100 nodes") stop being slogans and become measured byte and message counts.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 7.1 | `ExternalMemory.java` | 64 MB of ints sorted on disk with a 4 MB budget: 16 runs; fan-in 4 needs 2 merge passes and moves 192 MB each way, fan-in 16 needs 1 pass and 128 MB; the output is sorted and has the input's exact count, sum and hash. A one-pass top-100 with a 100-entry heap equals the sorted file's tail. BSP BFS on a 1,024 × 1,024 grid over 8 shards gives the single-machine distances; hash partitioning cuts 87.5% of edges and sends 3,665,616 messages, row partitioning cuts 0.34% and sends 14,336 (256× fewer) |
| 7.2 | `external_memory.cpp` | The same, with `fread`/`fwrite` and `std::filesystem`; every count, byte total and message total identical to Java |

**Verification.** Both listings were extracted from this file, compiled and run. Every correctness line (runs, passes, bytes, sortedness, digests, top-K, distances, cut edges, messages) is **Output (verified)**: deterministic and identical across Java, GCC and Clang. The millisecond figures are **one measured run** on a Windows 11 laptop with an SSD and are labelled as such.

---

## 0. Orientation

An interviewer who says "now the file is 100 TB" is not asking for a bigger array. They are checking whether you know the **cost model changes**: the unit of cost becomes a block transfer (a disk read or a network message), not a comparison. Your algorithm has to be rearranged so that every byte is read and written sequentially, a small number of times, and so that machines exchange as few messages as possible.

| Contest habit | What breaks at scale | L7 replacement |
|---|---|---|
| `int[] a = readAll(); Arrays.sort(a);` | 100 TB doesn't fit; `mmap` + sort thrashes on random page faults | External merge sort: sorted runs of size M, then k-way merges; every access sequential |
| "Merge two at a time" (binary merge sort on disk) | log₂(runs) passes over all the data | Fan-in k ≈ M/B: log_k(runs) passes; measured 2 → 1 pass cut I/O from 192 MB to 128 MB each way |
| Count complexity in comparisons | Comparisons are free next to I/O | Count passes × bytes: the I/O model's (N/B) log_{M/B}(N/B) |
| Sort everything to get the top K | O(N log N) time and O(N) space | One pass, a K-entry min-heap: O(N log K) time, O(K) memory, mergeable across shards |
| BFS on one adjacency list | Graph is spread over 100 machines | Bulk-synchronous BFS (Pregel): local work, then one message per cut edge, then a barrier |
| Partition by `hash(v) % S` because it balances | Cuts (S−1)/S of all edges: 87.5% with 8 shards, measured | Locality-aware partitioning (ranges, METIS-style): 0.34% cut on the grid, 256× fewer messages |
| Assume a run never crashes | A 10-hour sort dies at hour 9 | Sorted runs are durable checkpoints; restart from the completed ones |

The common thread is the same as in Folder 01 File 1 (the memory hierarchy): there is a slow level and a fast level, transfers between them come in big blocks, and the algorithm's job is to make every block transfer count.

---

## 1. First principles

### 1.1 The I/O model

Aggarwal and Vitter's external-memory model has three parameters: **N** items of input, a memory of **M** items, and a block of **B** items moved per I/O. Computation in memory is free; you pay one unit per block moved. Scanning N items costs N/B I/Os. Sorting costs

> **Θ((N/B) · log_{M/B}(N/B)) I/Os**

and no comparison-based algorithm does better. The base of that logarithm is the whole story: it is the **fan-in** of the merge, how many runs you can merge at once while giving each one a block-sized buffer. With M/B in the thousands, log_{M/B} of anything realistic is 1, 2 or 3: an external sort makes **two or three passes over the data, whatever its size.**

The listing uses N = 16,777,216 ints (64 MB), M = 1,048,576 ints (4 MB) and 64 KB buffers. That gives N/M = 16 initial runs. With fan-in k, the number of merge passes is ⌈log_k 16⌉: two passes for k = 4, one pass for k = 16.

### 1.2 External merge sort

* **Phase 1, run formation.** Read M items, sort them in memory, write them out as a sorted run. Repeat until the input is consumed: ⌈N/M⌉ runs, one read and one write of the whole input.
* **Phase 2, merging.** Open up to k runs, give each a B-sized input buffer, keep a min-heap of the k current heads, and repeatedly emit the smallest head and refill from that head's run. One merge pass reads and writes everything once and divides the number of runs by k.

Total traffic is (1 + passes) reads and (1 + passes) writes of the input: for 64 MB that is 192 MB each way with two passes and 128 MB with one, exactly the numbers the listing measures.

**A non-obvious fact the measurement shows:** the total number of **comparisons** is the same for any fan-in. A heap of k entries costs log₂ k comparisons per element per pass, and there are log_k(runs) passes, so the product is log₂(runs) per element. Fan-in 4 does 2 passes × 2 levels, fan-in 16 does 1 pass × 4 levels. A bigger fan-in saves **I/O, not CPU**. That is why fan-in 16 was only modestly faster here (1.1–1.8 s against 1.3–2.1 s across the three builds): on a laptop SSD with a warm page cache, 64 MB of extra I/O is cheap. On 100 TB of spinning disk or network storage, the saved pass is hours.

**How big can k be?** Every open run needs a buffer of B, plus one output buffer: k ≤ M/B − 1. B in turn must amortize the cost of switching between runs. On a hard disk a seek is about 10 ms, so at 200 MB/s a buffer below ~2 MB spends more time seeking than reading. On an SSD, 64 KB–1 MB is enough. So the fan-in is a hardware decision, not a constant to memorize.

**Replacement selection** (Knuth, TAOCP Vol. 3) produces runs of average length **2M** on random input instead of M, using a heap that keeps emitting while it reads. It halves the number of runs and sometimes saves a pass. On already-sorted input it produces one run.

### 1.3 Streaming top-K

Keep a **min-heap of size K**. For each item: if the heap has fewer than K items, push; otherwise, if the item beats the heap's minimum, replace the minimum and sift down. At the end the heap holds the K largest items. Time O(N log K), memory O(K), one sequential pass. The invariant is "the heap is the top K of the prefix seen so far", and it survives concatenation: **top-K(A ∪ B) = top-K(top-K(A) ∪ top-K(B))**. So 100 shards can each send K items and a coordinator merges them. The same invariant doesn't hold for "top-K most frequent": a key can be rare on every shard and frequent overall. That needs a two-phase exact algorithm or a sketch (Folder 06 File 2).

### 1.4 Bulk-synchronous BFS

Pregel's model splits a computation into **supersteps**. In each superstep, every shard processes the active vertices it owns, sends messages for edges that leave the shard, and then all shards wait at a **barrier**. Messages are delivered at the start of the next superstep. BFS fits naturally: the frontier is the active set, and an edge (v, u) whose endpoint u is on another shard becomes a message "u is at distance d+1".

The costs that matter:

* **Messages = cut edges traversed.** Each vertex enters the frontier once, so each directed edge out of it is examined once. Edges that leave the shard become network messages. With a random (hash) partition into S shards, a fraction (S−1)/S of edges is cut: 7/8 = 87.5% for S = 8, exactly what the listing measures. With a partition that respects locality (here: consecutive rows), only boundary edges are cut: 7 boundaries × 1,024 columns × 2 directions = 14,336.
* **Supersteps = BFS depth + 1.** The grid's corner-to-corner distance is 1,023 + 1,023 = 2,046, so BFS needs 2,047 supersteps whatever the partition. Each superstep ends with a global barrier, so the run time has a floor of **depth × barrier latency**. 2,047 barriers at 1 ms each is 2 seconds of pure synchronization. This is why BSP BFS is fine on social graphs (diameter ≈ 6–20) and poor on road networks (diameter in the thousands).

---

## 2. The listings

### 2.1 Listing 7.1 — Java

The Java version uses `FileChannel` with direct little-endian `ByteBuffer`s, so the on-disk format matches the C++ twin byte for byte. Merge passes use a primitive binary heap over parallel `int[]` arrays (value, run index) with ties broken by run index, so the merge is deterministic. The temporary directory and every run file are deleted in a `finally` block.

```java
// ExternalMemory.java - external merge sort under a memory budget, streaming top-K from disk, BSP sharded BFS with message counts.
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

public final class ExternalMemory {

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
    }

    // ===================================================================== buffered int I/O (little-endian, like the C++ twin)
    static final class IntWriter implements AutoCloseable {
        private final FileChannel ch;
        private final ByteBuffer buf;
        static long bytes;
        IntWriter(Path p, int bufBytes) throws IOException {
            ch = FileChannel.open(p, StandardOpenOption.CREATE, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING);
            buf = ByteBuffer.allocateDirect(bufBytes).order(ByteOrder.LITTLE_ENDIAN);
        }
        void write(int v) throws IOException { if (!buf.hasRemaining()) flush(); buf.putInt(v); }
        private void flush() throws IOException { buf.flip(); while (buf.hasRemaining()) bytes += ch.write(buf); buf.clear(); }
        @Override public void close() throws IOException { flush(); ch.close(); }
    }

    static final class IntReader implements AutoCloseable {
        private final FileChannel ch;
        private final ByteBuffer buf;
        static long bytes;
        IntReader(Path p, int bufBytes) throws IOException {
            ch = FileChannel.open(p, StandardOpenOption.READ);
            buf = ByteBuffer.allocateDirect(bufBytes).order(ByteOrder.LITTLE_ENDIAN);
            buf.flip();
        }
        boolean hasNext() throws IOException {
            if (buf.remaining() >= 4) return true;
            buf.compact();
            int n = ch.read(buf);
            if (n > 0) bytes += n;
            buf.flip();
            return buf.remaining() >= 4;
        }
        int next() { return buf.getInt(); }
        @Override public void close() throws IOException { ch.close(); }
    }

    // ===================================================================== 1. external merge sort
    record SortStats(int runs, int passes, long bytesRead, long bytesWritten) {}

    /**
     * Phase 1: read memInts at a time, sort in RAM, write sorted runs. Phase 2: merge up to fanIn runs at a time with
     * a heap of run heads (one buffer per run) until one run remains. Passes = ceil(log_fanIn(runs)); each pass reads
     * and writes all N items once -- the (N/B) log_{M/B}(N/B) I/O bound in practice.
     */
    static SortStats externalSort(Path in, Path out, Path tmp, int memInts, int fanIn, int bufBytes) throws IOException {
        IntReader.bytes = 0;
        IntWriter.bytes = 0;
        List<Path> runs = new ArrayList<>();
        int[] chunk = new int[memInts];
        try (IntReader r = new IntReader(in, bufBytes)) {
            while (r.hasNext()) {
                int n = 0;
                while (n < memInts && r.hasNext()) chunk[n++] = r.next();
                Arrays.sort(chunk, 0, n);
                Path run = tmp.resolve("run-0-" + runs.size());
                try (IntWriter w = new IntWriter(run, bufBytes)) { for (int i = 0; i < n; i++) w.write(chunk[i]); }
                runs.add(run);
            }
        }
        int initialRuns = runs.size(), passes = 0;
        while (runs.size() > 1) {
            passes++;
            List<Path> next = new ArrayList<>();
            for (int g = 0; g < runs.size(); g += fanIn) {
                List<Path> group = runs.subList(g, Math.min(runs.size(), g + fanIn));
                Path merged = tmp.resolve("run-" + passes + "-" + next.size());
                mergeRuns(group, merged, bufBytes);
                for (Path p : group) Files.delete(p);
                next.add(merged);
            }
            runs = next;
        }
        Files.move(runs.get(0), out, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        return new SortStats(initialRuns, passes, IntReader.bytes, IntWriter.bytes);
    }

    /** k-way merge with a primitive binary heap of (value, run); ties broken by run index for determinism. */
    static void mergeRuns(List<Path> group, Path out, int bufBytes) throws IOException {
        int k = group.size();
        IntReader[] rd = new IntReader[k];
        int[] hv = new int[k], hs = new int[k];
        int size = 0;
        try (IntWriter w = new IntWriter(out, bufBytes)) {
            for (int i = 0; i < k; i++) {
                rd[i] = new IntReader(group.get(i), bufBytes);
                if (rd[i].hasNext()) { hv[size] = rd[i].next(); hs[size] = i; siftUp(hv, hs, size++); }
            }
            while (size > 0) {
                w.write(hv[0]);
                int src = hs[0];
                if (rd[src].hasNext()) hv[0] = rd[src].next();
                else { size--; hv[0] = hv[size]; hs[0] = hs[size]; }
                siftDown(hv, hs, 0, size);
            }
        } finally {
            for (IntReader r : rd) if (r != null) r.close();
        }
    }

    static boolean less(int[] v, int[] s, int a, int b) { return v[a] != v[b] ? v[a] < v[b] : s[a] < s[b]; }
    static void swap(int[] v, int[] s, int a, int b) { int t = v[a]; v[a] = v[b]; v[b] = t; t = s[a]; s[a] = s[b]; s[b] = t; }
    static void siftUp(int[] v, int[] s, int i) { while (i > 0 && less(v, s, i, (i - 1) / 2)) { swap(v, s, i, (i - 1) / 2); i = (i - 1) / 2; } }
    static void siftDown(int[] v, int[] s, int i, int n) {
        while (true) {
            int l = 2 * i + 1, r = l + 1, m = i;
            if (l < n && less(v, s, l, m)) m = l;
            if (r < n && less(v, s, r, m)) m = r;
            if (m == i) return;
            swap(v, s, i, m);
            i = m;
        }
    }

    record Digest(long count, long sum, long xor, boolean sorted) {}

    static Digest digest(Path p, int bufBytes) throws IOException {
        long count = 0, sum = 0, xor = 0;
        boolean sorted = true;
        int prev = Integer.MIN_VALUE;
        try (IntReader r = new IntReader(p, bufBytes)) {
            while (r.hasNext()) { int v = r.next(); count++; sum += v; xor ^= v * 0x9E3779B97F4A7C15L; sorted &= v >= prev; prev = v; }
        }
        return new Digest(count, sum, xor, sorted);
    }

    // ===================================================================== 2. streaming top-K from disk
    /** One pass, a size-K min-heap: memory O(K) whatever the file size. Returns the K largest, descending. */
    static int[] topK(Path p, int k, int bufBytes) throws IOException {
        int[] heap = new int[k];
        int size = 0;
        try (IntReader r = new IntReader(p, bufBytes)) {
            while (r.hasNext()) {
                int v = r.next();
                if (size < k) {
                    heap[size] = v;
                    for (int i = size++; i > 0 && heap[i] < heap[(i - 1) / 2]; i = (i - 1) / 2) { int t = heap[i]; heap[i] = heap[(i - 1) / 2]; heap[(i - 1) / 2] = t; }
                } else if (v > heap[0]) {
                    heap[0] = v;
                    for (int i = 0; ; ) {
                        int l = 2 * i + 1, rr = l + 1, m = i;
                        if (l < k && heap[l] < heap[m]) m = l;
                        if (rr < k && heap[rr] < heap[m]) m = rr;
                        if (m == i) break;
                        int t = heap[i]; heap[i] = heap[m]; heap[m] = t;
                        i = m;
                    }
                }
            }
        }
        Integer[] boxed = Arrays.stream(heap, 0, size).boxed().toArray(Integer[]::new);
        Arrays.sort(boxed, Comparator.reverseOrder());
        return Arrays.stream(boxed).mapToInt(Integer::intValue).toArray();
    }

    // ===================================================================== 3. BSP sharded BFS
    record BspStats(int supersteps, long messages, long crossEdges, long edges, int[] dist) {}

    /** Grid graph w x h, 4-neighbour. owner(v) decides which shard holds v; remote neighbours become messages. */
    static BspStats bspBfs(int w, int h, int shards, java.util.function.IntUnaryOperator owner) {
        int n = w * h;
        int[] dist = new int[n];
        Arrays.fill(dist, -1);
        List<List<Integer>> frontier = new ArrayList<>();
        for (int s = 0; s < shards; s++) frontier.add(new ArrayList<>());
        dist[0] = 0;
        frontier.get(owner.applyAsInt(0)).add(0);
        int steps = 0;
        long messages = 0, cross = 0, edges = 0;
        for (int v = 0; v < n; v++) {
            int x = v % w, y = v / w;
            int[] nb = {x > 0 ? v - 1 : -1, x < w - 1 ? v + 1 : -1, y > 0 ? v - w : -1, y < h - 1 ? v + w : -1};
            for (int u : nb) if (u >= 0) { edges++; if (owner.applyAsInt(u) != owner.applyAsInt(v)) cross++; }
        }
        while (frontier.stream().anyMatch(f -> !f.isEmpty())) {
            steps++;
            List<List<Integer>> next = new ArrayList<>(), inbox = new ArrayList<>();
            for (int s = 0; s < shards; s++) { next.add(new ArrayList<>()); inbox.add(new ArrayList<>()); }
            for (int s = 0; s < shards; s++) {                 // each shard works only on vertices it owns
                for (int v : frontier.get(s)) {
                    int x = v % w, y = v / w;
                    int[] nb = {x > 0 ? v - 1 : -1, x < w - 1 ? v + 1 : -1, y > 0 ? v - w : -1, y < h - 1 ? v + w : -1};
                    for (int u : nb) {
                        if (u < 0) continue;
                        int o = owner.applyAsInt(u);
                        if (o == s) { if (dist[u] == -1) { dist[u] = dist[v] + 1; next.get(s).add(u); } }
                        else { inbox.get(o).add(u); messages++; }          // sent over the network
                    }
                }
            }
            for (int s = 0; s < shards; s++)                      // barrier, then deliver messages
                for (int u : inbox.get(s)) if (dist[u] == -1) { dist[u] = steps; next.get(s).add(u); }
            frontier = next;
        }
        return new BspStats(steps, messages, cross, edges, dist);
    }

    static int[] plainBfs(int w, int h) {
        int n = w * h;
        int[] dist = new int[n], q = new int[n];
        Arrays.fill(dist, -1);
        int head = 0, tail = 0;
        dist[0] = 0;
        q[tail++] = 0;
        while (head < tail) {
            int v = q[head++], x = v % w, y = v / w;
            int[] nb = {x > 0 ? v - 1 : -1, x < w - 1 ? v + 1 : -1, y > 0 ? v - w : -1, y < h - 1 ? v + w : -1};
            for (int u : nb) if (u >= 0 && dist[u] == -1) { dist[u] = dist[v] + 1; q[tail++] = u; }
        }
        return dist;
    }

    static long mix(long x) {
        x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9L;
        x = (x ^ (x >>> 27)) * 0x94D049BB133111EBL;
        return x ^ (x >>> 31);
    }

    public static void main(String[] args) throws IOException {
        Path tmp = Files.createTempDirectory("extsort");
        try {
            int n = 1 << 24, mem = 1 << 20, buf = 1 << 16;
            Path in = tmp.resolve("input.bin"), out = tmp.resolve("sorted.bin");
            SplitMix64 r = new SplitMix64(161);
            try (IntWriter w = new IntWriter(in, buf)) { for (int i = 0; i < n; i++) w.write((int) r.next()); }
            Digest din = digest(in, buf);
            System.out.printf("input: %,d ints (%,d MB) on disk, memory budget %,d ints (%,d MB), buffers %,d KB per open run%n",
                    n, n * 4L >> 20, mem, mem * 4L >> 20, buf >> 10);
            for (int fanIn : new int[] {4, 16}) {
                long t0 = System.nanoTime();
                SortStats st = externalSort(in, out, tmp, mem, fanIn, buf);
                long ms = (System.nanoTime() - t0) / 1_000_000;
                Digest dout = digest(out, buf);
                System.out.printf("1. fan-in %2d: %d runs, %d merge pass(es), read %,d MB, wrote %,d MB, %,d ms (one measured run) |"
                        + " sorted %b, same count/sum/hash as input %b%n", fanIn, st.runs(), st.passes(), st.bytesRead() >> 20,
                        st.bytesWritten() >> 20, ms, dout.sorted(), dout.count() == din.count() && dout.sum() == din.sum() && dout.xor() == din.xor());
            }
            int[] all = new int[n];
            try (IntReader rd = new IntReader(in, buf)) { for (int i = 0; i < n && rd.hasNext(); i++) all[i] = rd.next(); }
            long t0 = System.nanoTime();
            Arrays.sort(all);
            System.out.printf("   for scale: the same 64 MB sorted entirely in RAM: %,d ms%n", (System.nanoTime() - t0) / 1_000_000);
            int[] top = topK(in, 100, buf);
            boolean topOk = true;
            for (int i = 0; i < 100; i++) topOk &= top[i] == all[n - 1 - i];
            System.out.printf("2. streaming top-100 in one pass with a 100-entry heap == last 100 of the sorted file: %b (max %,d)%n", topOk, top[0]);
        } finally {
            try (var files = Files.list(tmp)) { for (Path p : files.toList()) Files.delete(p); }
            Files.delete(tmp);
        }

        int w = 1_024, h = 1_024, shards = 8;
        int[] truth = plainBfs(w, h);
        BspStats byHash = bspBfs(w, h, shards, v -> (int) Long.remainderUnsigned(mix(v), shards));
        BspStats byRows = bspBfs(w, h, shards, v -> v / (w * h / shards));
        System.out.printf("3. BSP BFS on a %,d x %,d grid (%,d directed edges), %d shards: same distances as one machine: %b / %b%n",
                w, h, byHash.edges(), shards, Arrays.equals(byHash.dist(), truth), Arrays.equals(byRows.dist(), truth));
        System.out.printf("   hash partition : %,d supersteps, %,d cut edges (%.1f%%), %,d messages%n", byHash.supersteps(),
                byHash.crossEdges(), 100.0 * byHash.crossEdges() / byHash.edges(), byHash.messages());
        System.out.printf("   row partition  : %,d supersteps, %,d cut edges (%.2f%%), %,d messages (%.0fx fewer)%n", byRows.supersteps(),
                byRows.crossEdges(), 100.0 * byRows.crossEdges() / byRows.edges(), byRows.messages(), (double) byHash.messages() / byRows.messages());
    }
}
```

**Output (verified; the millisecond figures are one measured run):**

```text
input: 16,777,216 ints (64 MB) on disk, memory budget 1,048,576 ints (4 MB), buffers 64 KB per open run
1. fan-in  4: 16 runs, 2 merge pass(es), read 192 MB, wrote 192 MB, 2,127 ms (one measured run) | sorted true, same count/sum/hash as input true
1. fan-in 16: 16 runs, 1 merge pass(es), read 128 MB, wrote 128 MB, 1,821 ms (one measured run) | sorted true, same count/sum/hash as input true
   for scale: the same 64 MB sorted entirely in RAM: 1,363 ms
2. streaming top-100 in one pass with a 100-entry heap == last 100 of the sorted file: true (max 2,147,483,472)
3. BSP BFS on a 1,024 x 1,024 grid (4,190,208 directed edges), 8 shards: same distances as one machine: true / true
   hash partition : 2,047 supersteps, 3,665,616 cut edges (87.5%), 3,665,616 messages
   row partition  : 2,047 supersteps, 14,336 cut edges (0.34%), 14,336 messages (256x fewer)
```

### 2.2 Listing 7.2 — C++23

The C++ version uses `std::fopen`/`_wfopen` with a `unique_ptr` deleter for the file handles, `std::fread`/`std::fwrite` of whole buffers, and `std::filesystem` for the temporary directory. It writes native-endian `int32_t`, which is little-endian on every machine this KB targets. A real file format would state the byte order in a header (see F7).

```cpp
// external_memory.cpp - external merge sort under a memory budget, streaming top-K from disk, BSP sharded BFS with message counts.
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <functional>
#include <limits>
#include <memory>
#include <print>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using i32 = std::int32_t;
using i64 = std::int64_t;
using u64 = std::uint64_t;

struct SplitMix64 {
    u64 state;
    u64 next() noexcept {
        u64 z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
};

// ======================================================================= buffered int32 I/O (raw little-endian, like the Java twin)
struct FileCloser {
    void operator()(std::FILE* f) const noexcept { std::fclose(f); }
};
using File = std::unique_ptr<std::FILE, FileCloser>;
inline u64 g_bytes_read = 0, g_bytes_written = 0;

File open_file(const fs::path& p, const char* mode) {
    std::FILE* f = nullptr;
#ifdef _WIN32
    f = _wfopen(p.c_str(), mode[0] == 'r' ? L"rb" : L"wb");
#else
    f = std::fopen(p.c_str(), mode);
#endif
    if (!f) throw std::runtime_error("cannot open " + p.string());
    return File(f);
}

class IntWriter {
public:
    IntWriter(const fs::path& p, std::size_t buf_ints) : f_(open_file(p, "wb")) { buf_.reserve(buf_ints); }
    ~IntWriter() { flush(); }
    IntWriter(const IntWriter&) = delete;
    IntWriter& operator=(const IntWriter&) = delete;
    void write(i32 v) {
        if (buf_.size() == buf_.capacity()) flush();
        buf_.push_back(v);
    }

private:
    void flush() {
        if (buf_.empty()) return;
        g_bytes_written += std::fwrite(buf_.data(), sizeof(i32), buf_.size(), f_.get()) * sizeof(i32);
        buf_.clear();
    }
    File f_;
    std::vector<i32> buf_;
};

class IntReader {
public:
    IntReader(const fs::path& p, std::size_t buf_ints) : f_(open_file(p, "rb")), buf_(buf_ints) {}
    bool has_next() {
        if (pos_ < len_) return true;
        len_ = std::fread(buf_.data(), sizeof(i32), buf_.size(), f_.get());
        g_bytes_read += len_ * sizeof(i32);
        pos_ = 0;
        return len_ > 0;
    }
    i32 next() { return buf_[pos_++]; }

private:
    File f_;
    std::vector<i32> buf_;
    std::size_t pos_ = 0, len_ = 0;
};

// ======================================================================= 1. external merge sort
struct SortStats {
    std::size_t runs, passes;
    u64 bytes_read, bytes_written;
};

// k-way merge with a heap of (value, run); ties by run index for determinism.
void merge_runs(const std::vector<fs::path>& group, const fs::path& out, std::size_t buf_ints) {
    std::vector<std::unique_ptr<IntReader>> rd;
    std::vector<std::pair<i32, std::size_t>> heap;  // min-heap via greater<>
    for (std::size_t i = 0; i < group.size(); ++i) {
        rd.push_back(std::make_unique<IntReader>(group[i], buf_ints));
        if (rd.back()->has_next()) heap.emplace_back(rd.back()->next(), i);
    }
    std::ranges::make_heap(heap, std::greater<>());
    IntWriter w(out, buf_ints);
    while (!heap.empty()) {
        std::ranges::pop_heap(heap, std::greater<>());
        auto [v, src] = heap.back();
        w.write(v);
        if (rd[src]->has_next()) {
            heap.back() = {rd[src]->next(), src};
            std::ranges::push_heap(heap, std::greater<>());
        } else {
            heap.pop_back();
        }
    }
}

SortStats external_sort(const fs::path& in, const fs::path& out, const fs::path& tmp, std::size_t mem_ints, std::size_t fan_in,
                        std::size_t buf_ints) {
    g_bytes_read = g_bytes_written = 0;
    std::vector<fs::path> runs;
    std::vector<i32> chunk(mem_ints);
    {
        IntReader r(in, buf_ints);
        while (r.has_next()) {
            std::size_t n = 0;
            while (n < mem_ints && r.has_next()) chunk[n++] = r.next();
            std::sort(chunk.begin(), chunk.begin() + static_cast<std::ptrdiff_t>(n));
            fs::path run = tmp / ("run-0-" + std::to_string(runs.size()));
            IntWriter w(run, buf_ints);
            for (std::size_t i = 0; i < n; ++i) w.write(chunk[i]);
            runs.push_back(run);
        }
    }
    std::size_t initial = runs.size(), passes = 0;
    while (runs.size() > 1) {
        ++passes;
        std::vector<fs::path> next;
        for (std::size_t g = 0; g < runs.size(); g += fan_in) {
            std::vector<fs::path> group(runs.begin() + static_cast<std::ptrdiff_t>(g),
                                        runs.begin() + static_cast<std::ptrdiff_t>(std::min(runs.size(), g + fan_in)));
            fs::path merged = tmp / ("run-" + std::to_string(passes) + "-" + std::to_string(next.size()));
            merge_runs(group, merged, buf_ints);
            for (const auto& p : group) fs::remove(p);
            next.push_back(merged);
        }
        runs = std::move(next);
    }
    fs::rename(runs[0], out);
    return {initial, passes, g_bytes_read, g_bytes_written};
}

struct Digest {
    u64 count;
    i64 sum;
    u64 hash;
    bool sorted;
};
Digest digest(const fs::path& p, std::size_t buf_ints) {
    Digest d{0, 0, 0, true};
    i32 prev = std::numeric_limits<i32>::min();
    IntReader r(p, buf_ints);
    while (r.has_next()) {
        i32 v = r.next();
        ++d.count, d.sum += v, d.hash ^= static_cast<u64>(static_cast<i64>(v)) * 0x9E3779B97F4A7C15ULL;
        d.sorted = d.sorted && v >= prev;
        prev = v;
    }
    return d;
}

// ======================================================================= 2. streaming top-K from disk
std::vector<i32> top_k(const fs::path& p, std::size_t k, std::size_t buf_ints) {
    std::vector<i32> heap;  // min-heap of the K largest so far
    IntReader r(p, buf_ints);
    while (r.has_next()) {
        i32 v = r.next();
        if (heap.size() < k) {
            heap.push_back(v);
            std::ranges::push_heap(heap, std::greater<>());
        } else if (v > heap.front()) {
            std::ranges::pop_heap(heap, std::greater<>());
            heap.back() = v;
            std::ranges::push_heap(heap, std::greater<>());
        }
    }
    std::ranges::sort(heap, std::greater<>());
    return heap;
}

// ======================================================================= 3. BSP sharded BFS
u64 mix(u64 x) {
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ULL;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBULL;
    return x ^ (x >> 31);
}

struct BspStats {
    int supersteps;
    i64 messages, cross_edges, edges;
    std::vector<int> dist;
};

std::array<int, 4> neighbours(int v, int w, int h) {
    int x = v % w, y = v / w;
    return {x > 0 ? v - 1 : -1, x < w - 1 ? v + 1 : -1, y > 0 ? v - w : -1, y < h - 1 ? v + w : -1};
}

// owner(v) decides which shard holds v; remote neighbours become messages delivered after the superstep barrier.
template <class Owner>
BspStats bsp_bfs(int w, int h, int shards, Owner owner) {
    int n = w * h;
    BspStats st{0, 0, 0, 0, std::vector<int>(static_cast<std::size_t>(n), -1)};
    auto& dist = st.dist;
    for (int v = 0; v < n; ++v)
        for (int u : neighbours(v, w, h))
            if (u >= 0) ++st.edges, st.cross_edges += owner(u) != owner(v);
    std::vector<std::vector<int>> frontier(static_cast<std::size_t>(shards));
    dist[0] = 0;
    frontier[static_cast<std::size_t>(owner(0))].push_back(0);
    while (std::ranges::any_of(frontier, [](const auto& f) { return !f.empty(); })) {
        ++st.supersteps;
        std::vector<std::vector<int>> next(static_cast<std::size_t>(shards)), inbox(static_cast<std::size_t>(shards));
        for (int s = 0; s < shards; ++s)
            for (int v : frontier[static_cast<std::size_t>(s)])
                for (int u : neighbours(v, w, h)) {
                    if (u < 0) continue;
                    int o = owner(u);
                    if (o == s) {
                        if (dist[static_cast<std::size_t>(u)] == -1)
                            dist[static_cast<std::size_t>(u)] = dist[static_cast<std::size_t>(v)] + 1, next[static_cast<std::size_t>(s)].push_back(u);
                    } else {
                        inbox[static_cast<std::size_t>(o)].push_back(u), ++st.messages;  // sent over the network
                    }
                }
        for (int s = 0; s < shards; ++s)  // barrier, then deliver messages
            for (int u : inbox[static_cast<std::size_t>(s)])
                if (dist[static_cast<std::size_t>(u)] == -1) dist[static_cast<std::size_t>(u)] = st.supersteps, next[static_cast<std::size_t>(s)].push_back(u);
        frontier = std::move(next);
    }
    return st;
}

std::vector<int> plain_bfs(int w, int h) {
    std::vector<int> dist(static_cast<std::size_t>(w * h), -1), q{0};
    dist[0] = 0;
    for (std::size_t head = 0; head < q.size(); ++head)
        for (int u : neighbours(q[head], w, h))
            if (u >= 0 && dist[static_cast<std::size_t>(u)] == -1)
                dist[static_cast<std::size_t>(u)] = dist[static_cast<std::size_t>(q[head])] + 1, q.push_back(u);
    return dist;
}

int main() {
    fs::path tmp = fs::temp_directory_path() / ("extsort-cpp-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directories(tmp);
    constexpr std::size_t n = std::size_t{1} << 24, mem = std::size_t{1} << 20, buf = std::size_t{1} << 14;  // 16 Ki ints = 64 KB
    using clock = std::chrono::steady_clock;
    try {
        fs::path in = tmp / "input.bin", out = tmp / "sorted.bin";
        SplitMix64 r{161};
        {
            IntWriter w(in, buf);
            for (std::size_t i = 0; i < n; ++i) w.write(static_cast<i32>(static_cast<std::uint32_t>(r.next())));
        }
        Digest din = digest(in, buf);
        std::println("input: {} ints ({} MB) on disk, memory budget {} ints ({} MB), buffers {} KB per open run", n, n * 4 >> 20, mem,
                     mem * 4 >> 20, buf * 4 >> 10);
        for (std::size_t fan_in : {std::size_t{4}, std::size_t{16}}) {
            auto t0 = clock::now();
            SortStats st = external_sort(in, out, tmp, mem, fan_in, buf);
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count();
            Digest dout = digest(out, buf);
            std::println("1. fan-in {:2}: {} runs, {} merge pass(es), read {} MB, wrote {} MB, {} ms (one measured run) | sorted {}, same"
                         " count/sum/hash as input {}", fan_in, st.runs, st.passes, st.bytes_read >> 20, st.bytes_written >> 20, ms,
                         dout.sorted, dout.count == din.count && dout.sum == din.sum && dout.hash == din.hash);
        }
        std::vector<i32> all;
        all.reserve(n);
        {
            IntReader rd(in, buf);
            while (rd.has_next()) all.push_back(rd.next());
        }
        auto t0 = clock::now();
        std::ranges::sort(all);
        std::println("   for scale: the same 64 MB sorted entirely in RAM: {} ms",
                     std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count());
        auto top = top_k(in, 100, buf);
        bool top_ok = top.size() == 100;
        for (std::size_t i = 0; i < top.size(); ++i) top_ok = top_ok && top[i] == all[n - 1 - i];
        std::println("2. streaming top-100 in one pass with a 100-entry heap == last 100 of the sorted file: {} (max {})", top_ok, top[0]);
    } catch (...) {
        fs::remove_all(tmp);
        throw;
    }
    fs::remove_all(tmp);

    constexpr int w = 1'024, h = 1'024, shards = 8;
    auto truth = plain_bfs(w, h);
    auto by_hash = bsp_bfs(w, h, shards, [](int v) { return static_cast<int>(mix(static_cast<u64>(v)) % shards); });
    auto by_rows = bsp_bfs(w, h, shards, [](int v) { return v / (w * h / shards); });
    std::println("3. BSP BFS on a {} x {} grid ({} directed edges), {} shards: same distances as one machine: {} / {}", w, h, by_hash.edges,
                 shards, by_hash.dist == truth, by_rows.dist == truth);
    std::println("   hash partition : {} supersteps, {} cut edges ({:.1f}%), {} messages", by_hash.supersteps, by_hash.cross_edges,
                 100.0 * static_cast<double>(by_hash.cross_edges) / static_cast<double>(by_hash.edges), by_hash.messages);
    std::println("   row partition  : {} supersteps, {} cut edges ({:.2f}%), {} messages ({:.0f}x fewer)", by_rows.supersteps,
                 by_rows.cross_edges, 100.0 * static_cast<double>(by_rows.cross_edges) / static_cast<double>(by_rows.edges),
                 by_rows.messages, static_cast<double>(by_hash.messages) / static_cast<double>(by_rows.messages));
}
```

**Output, GCC 16.2 (verified; the millisecond figures are one measured run):**

```text
input: 16777216 ints (64 MB) on disk, memory budget 1048576 ints (4 MB), buffers 64 KB per open run
1. fan-in  4: 16 runs, 2 merge pass(es), read 192 MB, wrote 192 MB, 1788 ms (one measured run) | sorted true, same count/sum/hash as input true
1. fan-in 16: 16 runs, 1 merge pass(es), read 128 MB, wrote 128 MB, 1633 ms (one measured run) | sorted true, same count/sum/hash as input true
   for scale: the same 64 MB sorted entirely in RAM: 1157 ms
2. streaming top-100 in one pass with a 100-entry heap == last 100 of the sorted file: true (max 2147483472)
3. BSP BFS on a 1024 x 1024 grid (4190208 directed edges), 8 shards: same distances as one machine: true / true
   hash partition : 2047 supersteps, 3665616 cut edges (87.5%), 3665616 messages
   row partition  : 2047 supersteps, 14336 cut edges (0.34%), 14336 messages (256x fewer)
```

**Output, Clang 21.1 (verified; the millisecond figures are one measured run):**

```text
input: 16777216 ints (64 MB) on disk, memory budget 1048576 ints (4 MB), buffers 64 KB per open run
1. fan-in  4: 16 runs, 2 merge pass(es), read 192 MB, wrote 192 MB, 1264 ms (one measured run) | sorted true, same count/sum/hash as input true
1. fan-in 16: 16 runs, 1 merge pass(es), read 128 MB, wrote 128 MB, 1133 ms (one measured run) | sorted true, same count/sum/hash as input true
   for scale: the same 64 MB sorted entirely in RAM: 492 ms
2. streaming top-100 in one pass with a 100-entry heap == last 100 of the sorted file: true (max 2147483472)
3. BSP BFS on a 1024 x 1024 grid (4190208 directed edges), 8 shards: same distances as one machine: true / true
   hash partition : 2047 supersteps, 3665616 cut edges (87.5%), 3665616 messages
   row partition  : 2047 supersteps, 14336 cut edges (0.34%), 14336 messages (256x fewer)
```

---

## 3. What the results show

* **The I/O model predicts the byte counts exactly.** 16 runs from a 4 MB budget; fan-in 4 → 2 merge passes → 192 MB read and 192 MB written; fan-in 16 → 1 pass → 128 MB each way. One pass saved is one third of all I/O.
* **Correctness is checked without trusting the sort.** The output is scanned once for sortedness, and its count, sum and an order-independent hash (the XOR of each value times a 64-bit odd constant) are compared with the input's. A sort that lost, duplicated or corrupted an element fails the digest. A sort that reordered wrongly fails the sortedness check. This costs one extra sequential pass, which is affordable at any scale.
* **CPU is not where fan-in pays.** Fan-in 16 was 9–14% faster than fan-in 4 in all three builds (Java 1,821 vs 2,127 ms; GCC 1,633 vs 1,788; Clang 1,133 vs 1,264). The comparison count is the same; the saving is the second pass's 128 MB of buffered I/O, which a warm OS page cache makes cheap on a laptop. A separate probe (not a listing) measured the raw costs: writing 64 MB took about 90 ms and reading it about 56 ms, while run formation (dominated by sorting 16 chunks) took about 1.2 s and one 16-way merge about 0.5 s.
* **The in-RAM sort is the floor, and external sort is within 1.3–2.3× of it** (Java 1,363 ms, GCC 1,157, Clang 492, against the fan-in 16 times above), while using one sixteenth of the memory.
* **One cold first run.** The first Java run of this listing took 18.6 s (fan-in 4) and 8.9 s (fan-in 16); every later run took about 2 s. The cause was not identified ⚠ (likely candidates are antivirus scanning of freshly created temporary files, or a cold file cache). It is a reminder that a single measurement of I/O-heavy code is a sample, not a fact.
* **Streaming top-100** read the 64 MB file once with a 100-entry heap and produced exactly the last 100 elements of the sorted array (largest 2,147,483,472).
* **Partitioning dominates distributed BFS.** Both partitions give the single-machine distances and the same 2,047 supersteps. Hash partitioning cut 3,665,616 of 4,190,208 directed edges (87.5%, the (S−1)/S prediction) and sent that many messages. Row partitioning cut 14,336 (0.34%), **256× fewer messages for the same answer.** The partition function is a one-line lambda; choosing it is the design decision.
* **Java and C++ agree on every count.** Runs, passes, bytes, digests, top-K values, cut edges and messages are identical across the three builds. Only the timings differ.
---

## 4. The last 10 minutes: Extensions A, B and C

For this file, Extension B is the main topic, so the follow-ups usually go the other way: "now use 64 cores" and "now use 100 machines".

### 4.1 Extension A — "64 threads, one machine"

* **Run formation parallelizes trivially.** Each thread reads its own slice of the input, sorts it and writes its own run. The only shared resource is the disk, so the right thread count is "enough to keep the device busy". On NVMe that is a handful of threads with large queue depth; on one spinning disk it is one reader at a time, because interleaved readers turn sequential I/O into seeks.
* **The merge parallelizes by splitting the value range, not the runs.** Pick 63 splitter values (by sampling the runs), binary-search each splitter's position in every run, and give thread t the slice of every run between splitters t and t+1. Each thread does an independent k-way merge, and the 64 outputs concatenate into one sorted file. Splitting the runs among threads instead (thread 1 merges runs 1–4, thread 2 runs 5–8) only builds more runs and adds a pass.
* **Overlap I/O with compute** by double-buffering: while the merge consumes buffer A of a run, an I/O thread fills buffer B. With 64 KB buffers and an SSD this hides most of the read latency. Java's `AsynchronousFileChannel` and C++'s `io_uring` (Linux) or overlapped I/O (Windows) are the production tools.
* **Top-K with 64 threads:** one heap per thread over its slice, then merge 64 heaps of K. No shared state, exact by the merge invariant of §1.3.
* **BFS on a shared-memory machine:** level-synchronous BFS with the frontier split among threads and `dist[u]` claimed by a CAS from −1 to d+1, so exactly one thread adds u to the next frontier. For low-diameter graphs, direction-optimizing BFS (Beamer et al.) switches to bottom-up steps when the frontier is large: each unvisited vertex scans its neighbours for a parent, which skips most edges.

### 4.2 Extension B — "100 TB, or an unbounded stream"

* **100 TB on one machine with 64 GB of RAM:** about 1,600 runs of 64 GB. With 1 MB buffers the fan-in can reach 64 GB / 1 MB ≈ 65,000, so **one merge pass** suffices: read 100 TB, write 100 TB (runs), read 100 TB, write 100 TB (output). At 2 GB/s that is 400 TB / 2 GB/s ≈ 55 hours, which is why nobody does this on one machine (Extension C).
* **An unbounded stream can't be sorted**, but most "sort the stream" questions really want one of three things: the top K (heap, §1.3), an order over a bounded window (a sorted structure with expiry, or the windowed sketches of Folder 06), or event-time order with bounded lateness (buffer events until the watermark passes them, then emit in order: a k-way merge whose inputs are time-ordered partitions).
* **Graphs larger than memory:** keep vertex state (one int per vertex) in RAM and stream the edge list from disk on each BFS level ("semi-external" BFS). If even the vertices don't fit, external-memory BFS (Munagala–Ranade) sorts each level's neighbour list and removes the previous two levels by merging, at O(sort(E)) I/Os per level.
* **Checkpointing comes free.** Sorted runs are durable intermediate results. A sort that crashes after writing 1,200 of 1,600 runs restarts by listing the run directory, verifying each run's footer (count and checksum), and continuing. Name files by content position (`run-<pass>-<index>`, as in the listing) so a restart is idempotent.

### 4.3 Extension C — "100 machines"

* **Distributed sort (TeraSort shape):** (1) each node samples its local data; (2) a coordinator picks 99 splitters from the combined sample; (3) every node sends each record to the node owning its range (the shuffle: every byte crosses the network once); (4) every node external-sorts what it received. Node i's output precedes node i+1's, so the concatenation is globally sorted with no final merge. **Skew** is the failure: if the splitters are poor, one node receives far more than 1/100 of the data and the job waits on it. Sampling enough points (thousands per node) keeps the largest partition within a few percent of the average.
* **Distributed top-K:** every node computes its local top K and sends K values; the coordinator merges 100 × K values. Network cost is 100K values, independent of the data size.
* **Distributed BFS (this listing's §3 at scale):** the partition decides the message count. Hash partitioning is balanced but cuts (S−1)/S of the edges: 99% for 100 shards. Locality-aware partitioning (METIS-style multilevel partitioning for static graphs; ranges by geography or community for road and social graphs) cut the grid's messages by 256× here. **Combiners** merge messages addressed to the same remote vertex in one superstep (for BFS, any one message suffices), and **vertex-cut** partitioning (PowerGraph) splits high-degree vertices across machines so a celebrity vertex doesn't overload one shard.
* **Fault tolerance:** Pregel checkpoints vertex state at superstep boundaries, and a failed worker's partitions are reloaded from the last checkpoint while the others roll back to it. The barrier that costs latency also gives a natural consistent cut.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | `mmap` the file and call an in-memory sort | Random page faults; the "sort" runs at disk-seek speed | Sequential-only access: runs, then k-way merge |
| F2 | Binary (2-way) merging on disk | log₂(runs) passes: 11 passes for 1,600 runs instead of 1 | Fan-in ≈ M/B; count passes before coding |
| F3 | Huge fan-in with tiny buffers | Seek-bound merge; throughput collapses on HDD | Buffer ≥ bandwidth × seek time; k = M/B − 1 |
| F4 | Fixed temp file names, no cleanup | Two jobs overwrite each other's runs; disk fills after crashes | Unique temp directory per job (`createTempDirectory`, a timestamped `temp_directory_path` subdirectory); delete in `finally` |
| F5 | Verifying the sort by eye on a sample | Lost or duplicated records go unnoticed | Sortedness scan plus count, sum and an order-independent hash of input and output |
| F6 | `next()` called without `hasNext()` on a buffered reader | Exception at the first buffer-refill boundary | Found while writing Listing 7.1: the read-back loop threw `BufferUnderflowException` until every `next()` was gated on `hasNext()` |
| F7 | Native-endian binary files with no header | Files unreadable on another architecture or by the other language | Fixed byte order (the Java listing writes little-endian explicitly), magic number, version, record count, checksum |
| F8 | Top-K by sorting everything | O(N) memory, O(N log N) time | K-entry min-heap, one pass; merge per-shard heaps |
| F9 | Frequent-items top-K merged like value top-K | Wrong answer: per-shard counts hide globally frequent keys | Hash-partition by key first (exact), or Count-Min / Space-Saving (approximate) |
| F10 | Hash-partitioned graph | 87.5% of edges cut with 8 shards (measured), 99% with 100 | Locality-aware partitioning; combiners; vertex cuts for hubs |
| F11 | BSP on a high-diameter graph | Thousands of barriers: 2,047 supersteps for a 1,024² grid | Fewer, larger steps (delta-stepping), precomputation (contraction hierarchies) or asynchronous models |
| F12 | Splitters chosen from a tiny sample | One node of 100 gets 5× its share; the job waits on it | Sample thousands of keys per node; split hot keys explicitly |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Sort a 100 TB file. Each machine has 64 GB of RAM."</b></summary>

**Initial Prompt.** The classic Extension B opener.

**L5 Answer.** "Split it into chunks that fit in memory, sort each, then merge the sorted chunks pairwise."

**Why L5 Stalls.** Pairwise merging makes log₂(runs) passes over 100 TB: about 11 for 1,600 runs. Each pass is 200 TB of I/O. The answer is right in shape and wrong by an order of magnitude in cost.

**L7 Answer.** "External merge sort, sized by the I/O model. Runs of 64 GB give about 1,600 runs. With 1 MB read buffers the merge fan-in can be in the tens of thousands, so one merge pass is enough: total traffic is two reads and two writes of the data. On one machine at 2 GB/s that's about 55 hours, so in practice I'd spread it: sample to pick 99 splitters, shuffle by range to 100 machines, external-sort locally. Each machine handles 1 TB, which is 16 runs and one merge pass. I'd verify the output with a sortedness scan plus count, sum and hash compared with the input. In my listing the byte counts matched the model exactly: 192 MB each way for two passes and 128 MB for one."
</details>

<details><summary><b>Q2 · "Why not mmap the file and let the OS page it?"</b></summary>

**Initial Prompt.** A candidate suggests virtual memory as the external-memory algorithm.

**L5 Answer.** "The OS caches pages, so it's basically in memory."

**Why L5 Stalls.** Quicksort or introsort over an mmap'd 100 TB file touches pages in a data-dependent, effectively random order. Each miss is a random read of one page (4 KB) at seek or SSD-latency cost, and the page cache evicts what the next partition step needs. The algorithm hasn't changed its access pattern, only hidden it.

**L7 Answer.** "Paging gives you the I/O model with B = one page and no control over replacement. Sorting needs sequential access in large blocks, which only an explicitly external algorithm guarantees. mmap is fine for *reading* a run sequentially, or for a file that's a small multiple of RAM with a sequential algorithm, but the sort itself has to be restructured into runs and merges."
</details>

<details><summary><b>Q3 · "How do you choose the merge fan-in?"</b></summary>

**Initial Prompt.** Follow-up to Q1.

**L5 Answer.** "As high as possible, to minimize passes."

**Why L5 Stalls.** Each open run needs a buffer, and a buffer that's too small turns the merge into seeks. Unbounded fan-in on a hard disk with 4 KB buffers is slower than fan-in 16.

**L7 Answer.** "Fan-in k ≤ M/B − 1, where B must amortize the cost of switching runs: at least bandwidth × seek time, about 2 MB on a hard disk and 64 KB–1 MB on an SSD. Within that, I pick the smallest k that gets the pass count down to one or two. One more thing I measured: fan-in doesn't change the comparison count. A k-entry heap costs log₂ k per element per pass, and there are log_k(runs) passes, so CPU is log₂(runs) per element either way. Fan-in 16 beat fan-in 4 by 9–14% on a laptop, entirely from the saved pass of I/O."
</details>

<details><summary><b>Q4 · "Return the 100 largest values in a 100 TB file."</b></summary>

**Initial Prompt.** A streaming question disguised as a sorting one.

**L5 Answer.** "Sort it, take the last 100."

**Why L5 Stalls.** A 55-hour sort for an answer that needs one pass.

**L7 Answer.** "One sequential pass with a 100-entry min-heap: O(N log K) time, 400 bytes of state. My listing checked it against the sorted file: identical. It parallelizes and distributes with no coordination beyond the end, because the top 100 of a union is the top 100 of the per-part top 100s. 100 machines each send 100 values."
</details>

<details><summary><b>Q5 · "Now the 100 most frequent values."</b></summary>

**Initial Prompt.** Follow-up to Q4.

**L5 Answer.** "Each machine finds its top 100 by count; merge those."

**Why L5 Stalls.** Frequency doesn't merge like value. A key that's 101st on every one of 100 machines can be first overall and appear in no local top 100.

**L7 Answer.** "Exactly: shuffle by hash of the key so every occurrence of a key lands on one machine, count there (in memory if a machine's distinct keys fit, otherwise external-sort and count adjacent runs), and then each machine's local top 100 is exact for its keys. Merge 100 local lists. Approximately, in one pass: a Count-Min sketch per machine, summed exactly, plus a candidate set from Space-Saving. Folder 06 File 2 has the error bounds."
</details>

<details><summary><b>Q6 · "Run BFS on a graph spread over 100 machines."</b></summary>

**Initial Prompt.** Extension C for graphs.

**L5 Answer.** "Each machine runs BFS on its part and they share results."

**Why L5 Stalls.** No model of when to share, what to send, or how to know BFS has finished.

**L7 Answer.** "Bulk-synchronous BFS, as in Pregel. Each superstep, every machine expands the frontier vertices it owns. Neighbours it owns are labelled locally, and each edge to a remote vertex becomes a message. Then there's a barrier, and incoming messages label their targets if they're still unvisited. BFS ends when no machine has a frontier. The cost has two parts. Messages equal the cut edges traversed, so the partition decides it: on my 1,024² grid with 8 shards, hash partitioning sent 3.67 M messages and row partitioning 14,336, 256× fewer, for identical distances. Supersteps equal the BFS depth, and each one ends with a global barrier."
</details>

<details><summary><b>Q7 · "Your distributed BFS needed 2,047 supersteps. Is that a problem?"</b></summary>

**Initial Prompt.** Probing the latency side of BSP.

**L5 Answer.** "Each superstep does little work, so it's fast."

**Why L5 Stalls.** Each superstep costs at least one global barrier, a round trip across all machines. Work per step doesn't remove the floor.

**L7 Answer.** "The run time is at least depth × barrier latency: 2,047 × 1 ms is 2 seconds even with free compute. On social graphs the depth is small, so BSP is fine. On road networks or grids it isn't. Options: delta-stepping (process all vertices within a distance bucket per step), asynchronous label propagation that doesn't wait for barriers, or precomputation such as contraction hierarchies for repeated shortest-path queries. Also check the partition: with a locality-aware partition, most of a level's work stays local, and a shard can run several local BFS levels before it needs to communicate."
</details>

<details><summary><b>Q8 · "Merge the time-sorted logs of 100 servers into one time-ordered stream."</b></summary>

**Initial Prompt.** A k-way merge in production clothing.

**L5 Answer.** "Concatenate the logs and sort by timestamp."

**Why L5 Stalls.** The logs are already sorted; a full sort wastes the structure and needs all data first. It also ignores clock skew and live streams.

**L7 Answer.** "A k-way merge with a 100-entry heap of (timestamp, server, offset): O(log 100) per record, streaming, with one read buffer per server, the same code as the merge phase of an external sort. For live streams, a server that's slow to send would stall the merge, so I'd use a watermark: emit records older than the minimum of every server's last-seen timestamp minus an allowed lateness, and route records that arrive behind the watermark to a late-data path. Clock skew between servers bounds how meaningful 'time order' is. If causal order matters, the timestamps should be hybrid logical clocks, not wall time."
</details>

<details><summary><b>Q9 · "The 10-hour sort crashed at hour 9."</b></summary>

**Initial Prompt.** An operational follow-up.

**L5 Answer.** "Rerun it."

**Why L5 Stalls.** Treats a long batch job as atomic. At 100 TB, the expected number of failures per run isn't small.

**L7 Answer.** "Design for restart. Each run and each merged output is written to a temporary name and atomically renamed when complete, with a footer holding its record count and checksum. On restart, list the directory, keep every file whose footer verifies, and resume: remaining run formation from the input offset after the last complete run, then merges over whatever runs exist. Naming by (pass, index) makes the restart idempotent. In a distributed sort the framework does the same at task granularity: a failed reducer's range is re-run from the shuffled inputs."
</details>

<details><summary><b>Q10 · "How do you know the 100 TB output is correct?"</b></summary>

**Initial Prompt.** Testing at scale.

**L5 Answer.** "Spot-check some records," or "compare with a small in-memory sort."

**Why L5 Stalls.** Neither catches a dropped or duplicated record in 10¹².

**L7 Answer.** "Two cheap streaming checks that together are strong. First, a sortedness scan: every record ≥ its predecessor, including across file and machine boundaries. Second, a multiset digest of input and output: count, sum, and an order-independent hash such as the XOR or sum of a 64-bit mix of each record. A sort that's a permutation of its input preserves all three; a lost, duplicated or corrupted record changes them with overwhelming probability. My listing checks exactly that after every sort. Both checks are one sequential pass and distribute trivially, since the digests are sums."
</details>

---

## 7. Checklist

* [ ] State N, M and B, and count passes before writing code: passes = ⌈log_k(N/M)⌉ with k ≤ M/B − 1.
* [ ] Every access sequential: runs written once, merged in large buffered reads.
* [ ] Buffer size from the device: ≥ bandwidth × seek time.
* [ ] Deterministic merge: ties broken by run index.
* [ ] Unique temp directory, cleanup in `finally`, atomic rename of completed files.
* [ ] Verify with sortedness + count + sum + order-independent hash.
* [ ] File format: explicit byte order, header, record count, checksum.
* [ ] Top-K: K-entry heap; merge per-shard heaps. Frequency top-K: partition by key or sketch.
* [ ] Distributed BFS: partition for locality; count messages = cut edges; supersteps = depth.
* [ ] Extension A: split the merge by value ranges (splitters), not by runs; double-buffer I/O.
* [ ] Extension B: one or two passes over the data, whatever its size; checkpoint via durable runs.
* [ ] Extension C: sample splitters, shuffle by range, sort locally; watch for skew.

---

## 8. References

* A. Aggarwal, J. S. Vitter, *The Input/Output Complexity of Sorting and Related Problems*, CACM 31(9), 1988 — DOI 10.1145/48529.48535
* D. E. Knuth, *The Art of Computer Programming, Vol. 3: Sorting and Searching*, 2nd ed., Addison-Wesley, 1998, §5.4 (external sorting, replacement selection)
* J. Dean, S. Ghemawat, *MapReduce: Simplified Data Processing on Large Clusters*, CACM 51(1), 2008 — DOI 10.1145/1327452.1327492
* L. G. Valiant, *A Bridging Model for Parallel Computation*, CACM 33(8), 1990 — DOI 10.1145/79173.79181
* G. Malewicz et al., *Pregel: A System for Large-Scale Graph Processing*, SIGMOD 2010 — DOI 10.1145/1807167.1807184
* K. Munagala, A. Ranade, *I/O-Complexity of Graph Algorithms*, SODA 1999
* S. Beamer, K. Asanović, D. Patterson, *Direction-Optimizing Breadth-First Search*, SC 2012 — DOI 10.1109/SC.2012.50
* U. Meyer, P. Sanders, *Δ-stepping: a parallelizable shortest path algorithm*, J. Algorithms 49(1), 2003 — DOI 10.1016/S0196-6774(03)00076-2
* G. Karypis, V. Kumar, *A Fast and High Quality Multilevel Scheme for Partitioning Irregular Graphs*, SIAM J. Sci. Comput. 20(1), 1998 — DOI 10.1137/S1064827595287997
* J. E. Gonzalez et al., *PowerGraph: Distributed Graph-Parallel Computation on Natural Graphs*, OSDI 2012 — <https://www.usenix.org/conference/osdi12/technical-sessions/presentation/gonzalez>
* Sort Benchmark (GraySort, TeraSort results) — <https://sortbenchmark.org/>
* Java `FileChannel` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/channels/FileChannel.html>
* C++ `std::filesystem::temp_directory_path` — <https://en.cppreference.com/w/cpp/filesystem/temp_directory_path>

*Folder 07:* [02 — Turning single-threaded DSA into thread-safe concurrent structures](02-turning-single-threaded-dsa-into-thread-safe-concurrent-structures.md) · [03 — 30 hard problems with production Java 21 and C++23 code](03-30-faang-l7-hard-coding-problems-with-production-java21-and-cpp23-code.md)
