# Fenwick (BIT) and Lazy Segment Trees with Sparse Dynamic Nodes

> **Folder 03 · File 2 of 3** — the four range structures every Staff candidate should be able to write, the invariant behind each, the classic lazy-propagation bug caught by an oracle, the 14× constant between them, and what a commutative update buys you under concurrency.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 3.3 | `RangeTrees.java` | Fenwick, range-update Fenwick, lazy segment tree (sum + min) and bottom-up tree against an array oracle: 80,000 ops, 0 mismatches. The "lengthless" lazy bug gives 14,775 wrong answers. A sparse tree over [0, 2³⁰) uses 336k nodes instead of 2.1 billion. Constants; 8-thread updates three ways |
| 3.4 | `range_trees.cpp` | The same; the buggy variant is a `template <bool Lengthless>` rather than a subclass; identical correctness counts |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the two timing lines (**one measured run**).

---

## 0. Orientation

In a contest, "segment tree" means a 4n global array and a recursive template pasted from a library. In a Staff round the questions are *which* structure, *why* it's correct, *what it costs in practice*, and *what happens with 64 writers or 10⁹ coordinates*.

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| Segment tree for every range problem | 2–14× slower than needed; more code to get wrong | Fenwick when the operation is invertible (sums); segment tree only for min/max or range assignment |
| `int sum[4*MAXN]` | Overflow; fixed size; global state | `long` arrays sized from `n`, inside a class |
| Lazy tag added once to the node's sum | Range sums wrong after any range update | `sum += tag × length`; an oracle test with range updates |
| Coordinates up to 10⁹ → "compress them" | Needs every coordinate in advance (offline only) | Sparse dynamic tree with nodes in a pool: online, O(updates × log range) memory |
| One lock around the tree for concurrent updates | Serializes every writer | Per-thread trees summed at query time, or atomic cells, because addition commutes |

---

## 1. First principles

### 1.1 Fenwick tree: prefix sums by lowest set bit

Cell `f[i]` (1-based) stores the sum of the `lowbit(i) = i & −i` elements ending at `i`. A prefix sum walks down by stripping the lowest bit (`i −= i & −i`). A point update walks up by adding it (`i += i & −i`). Each walk touches at most `log₂ n + 1` cells. Because subtraction is available, `range(l, r) = prefix(r) − prefix(l − 1)`. **Fenwick needs an invertible operation**: sum and xor work, min and max don't. A second Fenwick extends it to range add + range sum: write the prefix sum as `B1(i)·i − B2(i)` and update both with the boundary corrections.

### 1.2 Segment tree: a balanced tree of segment summaries

Each node summarizes a segment, and children split it in half. Any query range decomposes into O(log n) maximal nodes, and any point update touches the O(log n) nodes on one root-to-leaf path. It works for **any associative** operation (sum, min, max, gcd, matrix product, the maximum-subarray tuple), not only invertible ones. The **bottom-up iterative** variant (leaves at `[n, 2n)`, parent `i/2`) has no recursion and half the memory of the textbook `4n` version.

### 1.3 Lazy propagation

A range update would touch O(n) leaves. Instead, stop at the O(log n) maximal nodes covering the range and leave a **tag** there meaning "every leaf below me has a pending +d". The invariant: *a node's summary is correct for its segment including its own tag, but its children do not yet include it.* Before descending into a node's children for any reason, **push** the tag down. Applying a tag to a node must update its summary **for the whole segment**: `sum += d × length`, `min += d`. Forgetting the `× length` is the most common lazy bug, and the listing keeps it as a variant so the oracle can show what it does.

### 1.4 Sparse dynamic nodes

With coordinates up to 2³⁰ and only `q` updates, a dense tree needs 2³¹ nodes. A dynamic tree creates nodes only along the paths that updates touch: at most `q × 30` nodes. Node 0 is a shared "absent child" with sum 0, so queries need no null checks. Storing nodes as **parallel primitive arrays** (left[], right[], sum[]) instead of objects keeps memory at about 16 bytes per node, with no per-node object header and no pointer chasing through the heap. This is the online alternative to coordinate compression, which needs every coordinate up front.

### 1.5 Commutative updates and concurrency

Point "add d" operations **commute**. However they interleave, the final state of every cell is the same sum. That gives two lock-free designs:

1. **Atomic cells:** each Fenwick cell is an atomic and `add` does `fetch_add` on each of its O(log n) cells. The final state is exact. A concurrent reader may see an update applied to some cells and not others: the result is not linearizable, but it converges.
2. **Per-thread structures:** each writer owns a private tree, and a query sums the per-writer answers. Writes are uncontended, while queries cost × (number of writers).

---

## 2. The listings

### 2.1 Listing 3.3 — Java

```java
// RangeTrees.java - Fenwick, lazy segment tree, sparse dynamic segment tree: oracles, constants, and concurrent updates.
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicLongArray;

public final class RangeTrees {

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

    // ===================================================================== 1. Fenwick: point add, prefix sum
    /** f[i] covers (i - lowbit(i), i]. add and prefix each touch at most log2(n) + 1 cells. */
    static final class Fenwick {
        private final long[] f;
        Fenwick(int n) { f = new long[n + 1]; }
        void add(int i, long d) { for (i++; i < f.length; i += i & -i) f[i] += d; }
        long prefix(int i) { long s = 0; for (i++; i > 0; i -= i & -i) s += f[i]; return s; }  // [0, i]
        long range(int l, int r) { return prefix(r) - prefix(l - 1); }
    }

    /** Range add + range sum with two Fenwicks: sum[0..i] = B1(i) * i - B2(i) after the classic rewrite. */
    static final class RangeFenwick {
        private final Fenwick b1, b2;
        RangeFenwick(int n) { b1 = new Fenwick(n + 1); b2 = new Fenwick(n + 1); }
        void add(int l, int r, long d) {
            b1.add(l, d); b1.add(r + 1, -d);
            b2.add(l, d * (l - 1)); b2.add(r + 1, -d * r);
        }
        long prefix(int i) { return i < 0 ? 0 : b1.prefix(i) * i - b2.prefix(i); }
        long range(int l, int r) { return prefix(r) - prefix(l - 1); }
    }

    // ===================================================================== 2. lazy segment tree: range add, range sum/min
    /** Recursion depth is log2(n) + 1 (about 21 for a million leaves), so recursion is fine HERE, and said so. */
    static class LazyTree {
        final int size;
        final long[] sum, min, tag;

        LazyTree(int n) {
            int s = 1;
            while (s < n) s <<= 1;
            size = s;
            sum = new long[2 * s];
            min = new long[2 * s];
            tag = new long[2 * s];
            for (int i = n; i < s; i++) min[s + i] = Long.MAX_VALUE / 4;  // padding never wins a min
            for (int i = s - 1; i > 0; i--) min[i] = Math.min(min[2 * i], min[2 * i + 1]);
        }

        void apply(int node, int len, long add) {  // a pending add of `add` to every one of the `len` leaves below
            sum[node] += add * len;
            min[node] += add;
            tag[node] += add;
        }

        private void push(int node, int len) {
            if (tag[node] != 0) {
                apply(2 * node, len / 2, tag[node]);
                apply(2 * node + 1, len / 2, tag[node]);
                tag[node] = 0;
            }
        }

        void add(int l, int r, long d) { add(1, 0, size - 1, l, r, d); }

        private void add(int node, int nl, int nr, int l, int r, long d) {
            if (r < nl || nr < l) return;
            if (l <= nl && nr <= r) { apply(node, nr - nl + 1, d); return; }
            push(node, nr - nl + 1);
            int mid = (nl + nr) >>> 1;
            add(2 * node, nl, mid, l, r, d);
            add(2 * node + 1, mid + 1, nr, l, r, d);
            sum[node] = sum[2 * node] + sum[2 * node + 1];
            min[node] = Math.min(min[2 * node], min[2 * node + 1]);
        }

        long sum(int l, int r) { return sum(1, 0, size - 1, l, r); }

        private long sum(int node, int nl, int nr, int l, int r) {
            if (r < nl || nr < l) return 0;
            if (l <= nl && nr <= r) return sum[node];
            push(node, nr - nl + 1);
            int mid = (nl + nr) >>> 1;
            return sum(2 * node, nl, mid, l, r) + sum(2 * node + 1, mid + 1, nr, l, r);
        }

        long min(int l, int r) { return min(1, 0, size - 1, l, r); }

        private long min(int node, int nl, int nr, int l, int r) {
            if (r < nl || nr < l) return Long.MAX_VALUE;
            if (l <= nl && nr <= r) return min[node];
            push(node, nr - nl + 1);
            int mid = (nl + nr) >>> 1;
            return Math.min(min(2 * node, nl, mid, l, r), min(2 * node + 1, mid + 1, nr, l, r));
        }
    }

    /** The most common lazy bug: the pending add is applied to a node's SUM once, not once per leaf below it. */
    static final class LengthlessLazyTree extends LazyTree {
        LengthlessLazyTree(int n) { super(n); }
        @Override
        void apply(int node, int len, long add) {
            sum[node] += add;
            min[node] += add;
            tag[node] += add;
        }
    }

    // ===================================================================== 3. iterative bottom-up tree (no lazy)
    static final class BottomUpTree {
        private final long[] t;
        private final int n;
        BottomUpTree(int n) { this.n = n; t = new long[2 * n]; }
        void add(int i, long d) { for (i += n; i > 0; i >>= 1) t[i] += d; }
        long range(int l, int r) {  // [l, r]
            long s = 0;
            for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
                if ((l & 1) == 1) s += t[l++];
                if ((r & 1) == 1) s += t[--r];
            }
            return s;
        }
    }

    // ===================================================================== 4. sparse dynamic tree over [0, 2^30)
    /** Nodes are created on demand in parallel int/long arrays (no node objects): memory O(updates x 30). */
    static final class SparseTree {
        private static final int SPAN = 1 << 30;
        private int[] left = new int[1 << 10], right = new int[1 << 10];
        private long[] sum = new long[1 << 10];
        private int nodes = 2;  // node 0 = "no child" (sums to 0), node 1 = the root; the rest allocated on demand

        private int child(int node, boolean goRight) {
            int c = goRight ? right[node] : left[node];
            if (c != 0) return c;
            if (nodes == sum.length) {
                left = java.util.Arrays.copyOf(left, nodes * 2);
                right = java.util.Arrays.copyOf(right, nodes * 2);
                sum = java.util.Arrays.copyOf(sum, nodes * 2);
            }
            c = nodes++;
            if (goRight) right[node] = c; else left[node] = c;
            return c;
        }

        void add(int i, long d) {
            if (i < 0 || i >= SPAN) throw new IndexOutOfBoundsException(i);
            int node = 1, lo = 0, hi = SPAN - 1;
            while (true) {
                sum[node] += d;
                if (lo == hi) return;
                int mid = (lo + hi) >>> 1;
                boolean goRight = i > mid;
                node = child(node, goRight);
                if (goRight) lo = mid + 1; else hi = mid;
            }
        }

        long range(int l, int r) { return range(1, 0, SPAN - 1, l, r); }

        private long range(int node, int lo, int hi, int l, int r) {
            if (node == 0 || r < lo || hi < l) return 0;
            if (l <= lo && hi <= r) return sum[node];
            int mid = (lo + hi) >>> 1;
            return range(left[node], lo, mid, l, r) + range(right[node], mid + 1, hi, l, r);
        }

        int nodeCount() { return nodes - 1; }
    }

    // ===================================================================== Extension A: concurrent point updates
    /** Every update is a commutative add, so per-cell atomic adds give the exact final state in ANY interleaving. */
    static final class AtomicFenwick {
        private final AtomicLongArray f;
        AtomicFenwick(int n) { f = new AtomicLongArray(n + 1); }
        void add(int i, long d) { for (i++; i < f.length(); i += i & -i) f.getAndAdd(i, d); }
        long prefix(int i) { long s = 0; for (i++; i > 0; i -= i & -i) s += f.get(i); return s; }
    }

    interface Body { void run(int thread); }

    static double parallel(int threads, Body body) throws InterruptedException {
        CountDownLatch gate = new CountDownLatch(1), done = new CountDownLatch(threads);
        for (int t = 0; t < threads; t++) {
            int id = t;
            Thread.ofPlatform().start(() -> {
                try { gate.await(); body.run(id); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                finally { done.countDown(); }
            });
        }
        long t0 = System.nanoTime();
        gate.countDown();
        done.await();
        return (System.nanoTime() - t0) / 1e6;
    }

    public static void main(String[] args) throws InterruptedException {
        SplitMix64 r = new SplitMix64(61);
        int trials = 2_000, ops = 0, bad = 0, buggyBad = 0;
        for (int t = 0; t < trials; t++) {
            int n = 1 + r.nextInt(30);
            long[] a = new long[n];
            Fenwick fw = new Fenwick(n);
            RangeFenwick rf = new RangeFenwick(n);
            LazyTree lazy = new LazyTree(n);
            LazyTree buggy = new LengthlessLazyTree(n);
            BottomUpTree bu = new BottomUpTree(n);
            for (int q = 0; q < 40; q++, ops++) {
                int l = r.nextInt(n), rr = r.nextInt(n), kind = r.nextInt(3);
                if (l > rr) { int x = l; l = rr; rr = x; }
                long d = r.nextInt(2_000_001) - 1_000_000;
                if (kind == 0) {                       // point add
                    a[l] += d; fw.add(l, d); rf.add(l, l, d); lazy.add(l, l, d); buggy.add(l, l, d); bu.add(l, d);
                } else if (kind == 1) {                // range add (only the range structures)
                    for (int i = l; i <= rr; i++) a[i] += d;
                    rf.add(l, rr, d); lazy.add(l, rr, d); buggy.add(l, rr, d);
                    for (int i = l; i <= rr; i++) { fw.add(i, d); bu.add(i, d); }
                } else {                               // queries
                    long sum = 0, mn = Long.MAX_VALUE;
                    for (int i = l; i <= rr; i++) { sum += a[i]; mn = Math.min(mn, a[i]); }
                    if (fw.range(l, rr) != sum || rf.range(l, rr) != sum || lazy.sum(l, rr) != sum || lazy.min(l, rr) != mn
                            || bu.range(l, rr) != sum) bad++;
                    if (buggy.sum(l, rr) != sum) buggyBad++;
                }
            }
        }
        System.out.printf("1-3. %,d random ops on n <= 30: Fenwick, range Fenwick, lazy tree (sum+min), bottom-up tree:"
                + " %d mismatches | lengthless-lazy bug: %d wrong query answers%n", ops, bad, buggyBad);

        SparseTree sparse = new SparseTree();
        TreeMap<Integer, Long> oracle = new TreeMap<>();
        int sparseBad = 0;
        for (int q = 0; q < 20_000; q++) {
            int i = r.nextInt(1 << 30);
            long d = r.nextInt(1_000) + 1;
            sparse.add(i, d);
            oracle.merge(i, d, Long::sum);
            int l = r.nextInt(1 << 30), rr = r.nextInt(1 << 30);
            if (l > rr) { int x = l; l = rr; rr = x; }
            long want = 0;
            for (Map.Entry<Integer, Long> e : oracle.subMap(l, true, rr, true).entrySet()) want += e.getValue();
            if (sparse.range(l, rr) != want) sparseBad++;
        }
        System.out.printf("4. sparse dynamic tree over [0, 2^30): 20,000 adds + queries vs TreeMap oracle: %d mismatches,"
                + " %,d nodes (a dense tree would need %,d)%n", sparseBad, sparse.nodeCount(), 2L << 30);

        int n = 1 << 20, m = 2_000_000;
        int[] idx = new int[m], lo = new int[m], hi = new int[m];
        for (int i = 0; i < m; i++) {
            idx[i] = r.nextInt(n);
            int x = r.nextInt(n), y = r.nextInt(n);
            lo[i] = Math.min(x, y);
            hi[i] = Math.max(x, y);
        }
        long[] check = new long[3];
        double[] best = {Double.MAX_VALUE, Double.MAX_VALUE, Double.MAX_VALUE};
        for (int rep = 0; rep < 2; rep++) {
            Fenwick fw = new Fenwick(n);
            BottomUpTree bu = new BottomUpTree(n);
            LazyTree lazy = new LazyTree(n);
            long t0 = System.nanoTime(), s0 = 0;
            for (int i = 0; i < m; i++) { fw.add(idx[i], i & 7); s0 += fw.range(lo[i], hi[i]); }
            long t1 = System.nanoTime(), s1 = 0;
            for (int i = 0; i < m; i++) { bu.add(idx[i], i & 7); s1 += bu.range(lo[i], hi[i]); }
            long t2 = System.nanoTime(), s2 = 0;
            for (int i = 0; i < m; i++) { lazy.add(idx[i], idx[i], i & 7); s2 += lazy.sum(lo[i], hi[i]); }
            long t3 = System.nanoTime();
            best[0] = Math.min(best[0], (t1 - t0) / (double) m);
            best[1] = Math.min(best[1], (t2 - t1) / (double) m);
            best[2] = Math.min(best[2], (t3 - t2) / (double) m);
            check[0] = s0; check[1] = s1; check[2] = s2;
        }
        System.out.printf("constants, n=2^20, %,d (point add + range sum) pairs, best of 2 (one measured run): Fenwick %.0f ns |"
                + " bottom-up tree %.0f ns | recursive lazy tree %.0f ns | agree %b%n", m, best[0], best[1], best[2],
                check[0] == check[1] && check[1] == check[2]);

        int threads = 8, perThread = 1_000_000, cells = 1 << 16;
        int[][] work = new int[threads][perThread];
        for (int[] w : work) for (int i = 0; i < perThread; i++) w[i] = r.nextInt(cells);
        long want = (long) threads * perThread;
        Fenwick locked = new Fenwick(cells);
        double msLocked = parallel(threads, t -> { for (int i : work[t]) synchronized (locked) { locked.add(i, 1); } });
        AtomicFenwick atomic = new AtomicFenwick(cells);
        double msAtomic = parallel(threads, t -> { for (int i : work[t]) atomic.add(i, 1); });
        Fenwick[] mine = new Fenwick[threads];
        double msLocal = parallel(threads, t -> { Fenwick f = new Fenwick(cells); for (int i : work[t]) f.add(i, 1); mine[t] = f; });
        long localTotal = 0;
        for (Fenwick f : mine) localTotal += f.prefix(cells - 1);
        System.out.printf("A. %d threads x %,d point adds into %,d cells (one measured run): one lock %.0f ms (total %,d) |"
                + " AtomicLongArray cells %.0f ms (total %,d) | per-thread Fenwicks %.0f ms (summed at query: %,d) | expected %,d%n",
                threads, perThread, cells, msLocked, locked.prefix(cells - 1), msAtomic, atomic.prefix(cells - 1), msLocal, localTotal, want);
    }
}
```

**Output (verified; the last two lines are one measured run):**

```text
1-3. 80,000 random ops on n <= 30: Fenwick, range Fenwick, lazy tree (sum+min), bottom-up tree: 0 mismatches | lengthless-lazy bug: 14775 wrong query answers
4. sparse dynamic tree over [0, 2^30): 20,000 adds + queries vs TreeMap oracle: 0 mismatches, 336,346 nodes (a dense tree would need 2,147,483,648)
constants, n=2^20, 2,000,000 (point add + range sum) pairs, best of 2 (one measured run): Fenwick 76 ns | bottom-up tree 184 ns | recursive lazy tree 1009 ns | agree true
A. 8 threads x 1,000,000 point adds into 65,536 cells (one measured run): one lock 485 ms (total 8,000,000) | AtomicLongArray cells 308 ms (total 8,000,000) | per-thread Fenwicks 44 ms (summed at query: 8,000,000) | expected 8,000,000
```

### 2.2 Listing 3.4 — C++23

```cpp
// range_trees.cpp - Fenwick, lazy segment tree, sparse dynamic segment tree: oracles, constants, and concurrent updates.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <limits>
#include <map>
#include <mutex>
#include <print>
#include <stdexcept>
#include <thread>
#include <vector>

using i64 = std::int64_t;
inline std::size_t U(int x) { return static_cast<std::size_t>(x); }

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int next_int(int bound) noexcept { return static_cast<int>(next() % static_cast<std::uint64_t>(bound)); }
};

// ======================================================================= 1. Fenwick: point add, prefix sum
// f[i] covers (i - lowbit(i), i]. add and prefix each touch at most log2(n) + 1 cells.
class Fenwick {
public:
    explicit Fenwick(int n) : f_(U(n) + 1) {}
    void add(int i, i64 d) {
        for (std::size_t x = U(i) + 1; x < f_.size(); x += x & (~x + 1)) f_[x] += d;
    }
    i64 prefix(int i) const {  // [0, i]; prefix(-1) == 0
        i64 s = 0;
        for (std::size_t x = U(i + 1); x > 0; x -= x & (~x + 1)) s += f_[x];
        return s;
    }
    i64 range(int l, int r) const { return prefix(r) - prefix(l - 1); }

private:
    std::vector<i64> f_;
};

// Range add + range sum with two Fenwicks: sum[0..i] = B1(i) * i - B2(i).
class RangeFenwick {
public:
    explicit RangeFenwick(int n) : b1_(n + 1), b2_(n + 1) {}
    void add(int l, int r, i64 d) {
        b1_.add(l, d), b1_.add(r + 1, -d);
        b2_.add(l, d * (l - 1)), b2_.add(r + 1, -d * r);
    }
    i64 prefix(int i) const { return i < 0 ? 0 : b1_.prefix(i) * i - b2_.prefix(i); }
    i64 range(int l, int r) const { return prefix(r) - prefix(l - 1); }

private:
    Fenwick b1_, b2_;
};

// ======================================================================= 2. lazy segment tree: range add, sum/min
// Recursion depth is log2(n) + 1, so recursion is fine HERE. Lengthless = the classic bug, kept for the oracle to find.
template <bool Lengthless = false>
class LazyTree {
public:
    explicit LazyTree(int n) {
        while (size_ < n) size_ <<= 1;
        sum_.assign(U(2 * size_), 0);
        min_.assign(U(2 * size_), 0);
        tag_.assign(U(2 * size_), 0);
        for (int i = n; i < size_; ++i) min_[U(size_ + i)] = std::numeric_limits<i64>::max() / 4;  // padding never wins
        for (int i = size_ - 1; i > 0; --i) min_[U(i)] = std::min(min_[U(2 * i)], min_[U(2 * i + 1)]);
    }
    void add(int l, int r, i64 d) { add(1, 0, size_ - 1, l, r, d); }
    i64 sum(int l, int r) { return sum(1, 0, size_ - 1, l, r); }
    i64 min(int l, int r) { return min(1, 0, size_ - 1, l, r); }

private:
    void apply(int node, int len, i64 add) {  // a pending add to every one of the `len` leaves below
        sum_[U(node)] += Lengthless ? add : add * len;
        min_[U(node)] += add;
        tag_[U(node)] += add;
    }
    void push(int node, int len) {
        if (tag_[U(node)] != 0) {
            apply(2 * node, len / 2, tag_[U(node)]);
            apply(2 * node + 1, len / 2, tag_[U(node)]);
            tag_[U(node)] = 0;
        }
    }
    void add(int node, int nl, int nr, int l, int r, i64 d) {
        if (r < nl || nr < l) return;
        if (l <= nl && nr <= r) return apply(node, nr - nl + 1, d);
        push(node, nr - nl + 1);
        int mid = nl + (nr - nl) / 2;
        add(2 * node, nl, mid, l, r, d);
        add(2 * node + 1, mid + 1, nr, l, r, d);
        sum_[U(node)] = sum_[U(2 * node)] + sum_[U(2 * node + 1)];
        min_[U(node)] = std::min(min_[U(2 * node)], min_[U(2 * node + 1)]);
    }
    i64 sum(int node, int nl, int nr, int l, int r) {
        if (r < nl || nr < l) return 0;
        if (l <= nl && nr <= r) return sum_[U(node)];
        push(node, nr - nl + 1);
        int mid = nl + (nr - nl) / 2;
        return sum(2 * node, nl, mid, l, r) + sum(2 * node + 1, mid + 1, nr, l, r);
    }
    i64 min(int node, int nl, int nr, int l, int r) {
        if (r < nl || nr < l) return std::numeric_limits<i64>::max();
        if (l <= nl && nr <= r) return min_[U(node)];
        push(node, nr - nl + 1);
        int mid = nl + (nr - nl) / 2;
        return std::min(min(2 * node, nl, mid, l, r), min(2 * node + 1, mid + 1, nr, l, r));
    }
    int size_ = 1;
    std::vector<i64> sum_, min_, tag_;
};

// ======================================================================= 3. iterative bottom-up tree (no lazy)
class BottomUpTree {
public:
    explicit BottomUpTree(int n) : n_(U(n)), t_(2 * U(n)) {}
    void add(int i, i64 d) {
        for (std::size_t x = U(i) + n_; x > 0; x >>= 1) t_[x] += d;
    }
    i64 range(int l, int r) const {  // [l, r]
        i64 s = 0;
        for (std::size_t a = U(l) + n_, b = U(r) + n_ + 1; a < b; a >>= 1, b >>= 1) {
            if (a & 1) s += t_[a++];
            if (b & 1) s += t_[--b];
        }
        return s;
    }

private:
    std::size_t n_;
    std::vector<i64> t_;
};

// ======================================================================= 4. sparse dynamic tree over [0, 2^30)
// Nodes are created on demand in parallel vectors (no per-node allocation): memory O(updates x 30).
class SparseTree {
public:
    void add(int i, i64 d) {
        if (i < 0 || i >= kSpan) throw std::out_of_range("index");
        int node = 1, lo = 0, hi = kSpan - 1;
        while (true) {
            sum_[U(node)] += d;
            if (lo == hi) return;
            int mid = lo + (hi - lo) / 2;
            bool go_right = i > mid;
            node = child(node, go_right);
            if (go_right) lo = mid + 1;
            else hi = mid;
        }
    }
    i64 range(int l, int r) const { return range(1, 0, kSpan - 1, l, r); }
    std::size_t node_count() const { return sum_.size() - 1; }

private:
    static constexpr int kSpan = 1 << 30;
    int child(int node, bool go_right) {
        int& c = go_right ? right_[U(node)] : left_[U(node)];
        if (c != 0) return c;
        int fresh = static_cast<int>(sum_.size());
        left_.push_back(0), right_.push_back(0), sum_.push_back(0);
        (go_right ? right_ : left_)[U(node)] = fresh;  // re-index: push_back may have moved the vectors
        return fresh;
    }
    i64 range(int node, int lo, int hi, int l, int r) const {
        if (node == 0 || r < lo || hi < l) return 0;
        if (l <= lo && hi <= r) return sum_[U(node)];
        int mid = lo + (hi - lo) / 2;
        return range(left_[U(node)], lo, mid, l, r) + range(right_[U(node)], mid + 1, hi, l, r);
    }
    std::vector<int> left_{0, 0}, right_{0, 0};  // node 0 = "no child" (sums to 0), node 1 = the root
    std::vector<i64> sum_{0, 0};
};

// ======================================================================= Extension A: concurrent point updates
// Every update is a commutative add, so per-cell atomic adds give the exact final state in ANY interleaving.
class AtomicFenwick {
public:
    explicit AtomicFenwick(int n) : f_(U(n) + 1) {}
    void add(int i, i64 d) {
        for (std::size_t x = U(i) + 1; x < f_.size(); x += x & (~x + 1)) f_[x].fetch_add(d, std::memory_order_relaxed);
    }
    i64 prefix(int i) const {
        i64 s = 0;
        for (std::size_t x = U(i + 1); x > 0; x -= x & (~x + 1)) s += f_[x].load(std::memory_order_relaxed);
        return s;
    }

private:
    std::vector<std::atomic<i64>> f_;
};

template <class Body>
double parallel(int threads, Body body) {
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::chrono::steady_clock::time_point t0;
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < threads; ++t)
            ts.emplace_back([&, t] {
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}
                body(t);
            });
        while (ready.load() < threads) {}
        t0 = std::chrono::steady_clock::now();
        go.store(true, std::memory_order_release);
    }
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

int main() {
    SplitMix64 r{61};
    int ops = 0, bad = 0, buggy_bad = 0;
    for (int t = 0; t < 2'000; ++t) {
        int n = 1 + r.next_int(30);
        std::vector<i64> a(U(n));
        Fenwick fw(n);
        RangeFenwick rf(n);
        LazyTree<> lazy(n);
        LazyTree<true> buggy(n);
        BottomUpTree bu(n);
        for (int q = 0; q < 40; ++q, ++ops) {
            int l = r.next_int(n), rr = r.next_int(n), kind = r.next_int(3);
            if (l > rr) std::swap(l, rr);
            i64 d = r.next_int(2'000'001) - 1'000'000;
            if (kind == 0) {
                a[U(l)] += d, fw.add(l, d), rf.add(l, l, d), lazy.add(l, l, d), buggy.add(l, l, d), bu.add(l, d);
            } else if (kind == 1) {
                for (int i = l; i <= rr; ++i) a[U(i)] += d, fw.add(i, d), bu.add(i, d);
                rf.add(l, rr, d), lazy.add(l, rr, d), buggy.add(l, rr, d);
            } else {
                i64 sum = 0, mn = std::numeric_limits<i64>::max();
                for (int i = l; i <= rr; ++i) sum += a[U(i)], mn = std::min(mn, a[U(i)]);
                bad += fw.range(l, rr) != sum || rf.range(l, rr) != sum || lazy.sum(l, rr) != sum || lazy.min(l, rr) != mn ||
                       bu.range(l, rr) != sum;
                buggy_bad += buggy.sum(l, rr) != sum;
            }
        }
    }
    std::println("1-3. {} random ops on n <= 30: Fenwick, range Fenwick, lazy tree (sum+min), bottom-up tree: {} mismatches |"
                 " lengthless-lazy bug: {} wrong query answers", ops, bad, buggy_bad);

    SparseTree sparse;
    std::map<int, i64> oracle;
    int sparse_bad = 0;
    for (int q = 0; q < 20'000; ++q) {
        int i = r.next_int(1 << 30);
        i64 d = r.next_int(1'000) + 1;
        sparse.add(i, d);
        oracle[i] += d;
        int l = r.next_int(1 << 30), rr = r.next_int(1 << 30);
        if (l > rr) std::swap(l, rr);
        i64 want = 0;
        for (auto it = oracle.lower_bound(l); it != oracle.end() && it->first <= rr; ++it) want += it->second;
        sparse_bad += sparse.range(l, rr) != want;
    }
    std::println("4. sparse dynamic tree over [0, 2^30): 20,000 adds + queries vs std::map oracle: {} mismatches, {} nodes"
                 " (a dense tree would need {})", sparse_bad, sparse.node_count(), 2LL << 30);

    constexpr int n = 1 << 20, m = 2'000'000;
    std::vector<int> idx(U(m)), lo(U(m)), hi(U(m));
    for (std::size_t i = 0; i < U(m); ++i) {
        idx[i] = r.next_int(n);
        int x = r.next_int(n), y = r.next_int(n);
        lo[i] = std::min(x, y), hi[i] = std::max(x, y);
    }
    using clock = std::chrono::steady_clock;
    auto ns = [](clock::duration d) { return std::chrono::duration<double, std::nano>(d).count() / m; };
    double best[3] = {1e300, 1e300, 1e300};
    i64 check[3] = {};
    for (int rep = 0; rep < 2; ++rep) {
        Fenwick fw(n);
        BottomUpTree bu(n);
        LazyTree<> lazy(n);
        i64 s0 = 0, s1 = 0, s2 = 0;
        auto t0 = clock::now();
        for (std::size_t i = 0; i < U(m); ++i) fw.add(idx[i], static_cast<i64>(i & 7)), s0 += fw.range(lo[i], hi[i]);
        auto t1 = clock::now();
        for (std::size_t i = 0; i < U(m); ++i) bu.add(idx[i], static_cast<i64>(i & 7)), s1 += bu.range(lo[i], hi[i]);
        auto t2 = clock::now();
        for (std::size_t i = 0; i < U(m); ++i) lazy.add(idx[i], idx[i], static_cast<i64>(i & 7)), s2 += lazy.sum(lo[i], hi[i]);
        auto t3 = clock::now();
        best[0] = std::min(best[0], ns(t1 - t0)), best[1] = std::min(best[1], ns(t2 - t1)), best[2] = std::min(best[2], ns(t3 - t2));
        check[0] = s0, check[1] = s1, check[2] = s2;
    }
    std::println("constants, n=2^20, {} (point add + range sum) pairs, best of 2 (one measured run): Fenwick {:.0f} ns |"
                 " bottom-up tree {:.0f} ns | recursive lazy tree {:.0f} ns | agree {}", m, best[0], best[1], best[2],
                 check[0] == check[1] && check[1] == check[2]);

    constexpr int threads = 8, per_thread = 1'000'000, cells = 1 << 16;
    std::vector<std::vector<int>> work(U(threads), std::vector<int>(U(per_thread)));
    for (auto& w : work)
        for (int& i : w) i = r.next_int(cells);
    Fenwick locked(cells);
    std::mutex mu;
    double ms_locked = parallel(threads, [&](int t) {
        for (int i : work[U(t)]) {
            std::scoped_lock lock(mu);
            locked.add(i, 1);
        }
    });
    AtomicFenwick atomic(cells);
    double ms_atomic = parallel(threads, [&](int t) {
        for (int i : work[U(t)]) atomic.add(i, 1);
    });
    std::vector<Fenwick> mine(U(threads), Fenwick(cells));
    double ms_local = parallel(threads, [&](int t) {
        for (int i : work[U(t)]) mine[U(t)].add(i, 1);
    });
    i64 local_total = 0;
    for (const auto& f : mine) local_total += f.prefix(cells - 1);
    std::println("A. {} threads x {} point adds into {} cells (one measured run): one mutex {:.0f} ms (total {}) | atomic cells"
                 " {:.0f} ms (total {}) | per-thread Fenwicks {:.0f} ms (summed at query: {}) | expected {}", threads, per_thread,
                 cells, ms_locked, locked.prefix(cells - 1), ms_atomic, atomic.prefix(cells - 1), ms_local, local_total,
                 static_cast<i64>(threads) * per_thread);
}
```

**Output, GCC 16.2 (verified; the last two lines are one measured run):**

```text
1-3. 80000 random ops on n <= 30: Fenwick, range Fenwick, lazy tree (sum+min), bottom-up tree: 0 mismatches | lengthless-lazy bug: 14775 wrong query answers
4. sparse dynamic tree over [0, 2^30): 20,000 adds + queries vs std::map oracle: 0 mismatches, 336346 nodes (a dense tree would need 2147483648)
constants, n=2^20, 2000000 (point add + range sum) pairs, best of 2 (one measured run): Fenwick 58 ns | bottom-up tree 121 ns | recursive lazy tree 920 ns | agree true
A. 8 threads x 1000000 point adds into 65536 cells (one measured run): one mutex 1412 ms (total 8000000) | atomic cells 310 ms (total 8000000) | per-thread Fenwicks 21 ms (summed at query: 8000000) | expected 8000000
```

**Output, Clang 21.1 (verified; the last two lines are one measured run):**

```text
1-3. 80000 random ops on n <= 30: Fenwick, range Fenwick, lazy tree (sum+min), bottom-up tree: 0 mismatches | lengthless-lazy bug: 14775 wrong query answers
4. sparse dynamic tree over [0, 2^30): 20,000 adds + queries vs std::map oracle: 0 mismatches, 336346 nodes (a dense tree would need 2147483648)
constants, n=2^20, 2000000 (point add + range sum) pairs, best of 2 (one measured run): Fenwick 60 ns | bottom-up tree 134 ns | recursive lazy tree 971 ns | agree true
A. 8 threads x 1000000 point adds into 65536 cells (one measured run): one mutex 523 ms (total 8000000) | atomic cells 306 ms (total 8000000) | per-thread Fenwicks 21 ms (summed at query: 8000000) | expected 8000000
```

---

## 3. What the results show

* **Correctness:** 80,000 random operations (point adds, range adds, range sum and range min queries) on arrays of up to 30 elements. Fenwick, range Fenwick, the lazy tree and the bottom-up tree match a plain array in every case. Java and C++ agree exactly.
* **The lengthless-lazy bug is loud under an oracle and silent without one.** 14,775 wrong answers out of about 26,700 queries. Point updates alone would never expose it, because the length of a leaf is 1. That is why the oracle mix includes range updates.
* **Sparse beats dense by four orders of magnitude when coordinates are sparse:** 20,000 updates over [0, 2³⁰) created 336,346 nodes, against 2,147,483,648 for a dense tree, with 0 mismatches against an ordered-map oracle.
* **Constants for the same O(log n)** (point add + range sum pairs, n = 2²⁰):

| Structure | Java | C++ GCC | C++ Clang |
|---|---|---|---|
| Fenwick | 76–88 ns | 58–61 ns | 60–62 ns |
| Bottom-up segment tree | 176–184 ns | 121–126 ns | 134–137 ns |
| Recursive lazy segment tree | 1,009–1,219 ns | 920–946 ns | 962–971 ns |

The recursive lazy tree is **13–16×** slower than Fenwick for work Fenwick can do: recursion, push checks and three arrays touched per level. Use the lightest structure that supports the operation, and don't pay for laziness when there are no range updates.

* **Concurrency (8 threads × 1 M point adds, 65,536 cells):** every design produced the exact total of 8,000,000.

| Design | Java | C++ GCC | C++ Clang |
|---|---|---|---|
| One lock | 419–485 ms | 1,410–1,412 ms | 516–523 ms |
| Atomic cells (`AtomicLongArray` / `std::atomic`) | 307–310 ms | 299–310 ms | 306–307 ms |
| Per-thread Fenwicks, summed at query | 39–67 ms | 21 ms | 21–23 ms |

Contention on the shared top-level Fenwick cells (every update touches the high cells) limits the atomic version. Per-thread structures avoid sharing entirely, at the cost of a query that reads every writer's tree.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads update and query"

| Workload | Design | Why |
|---|---|---|
| Write-heavy counters, rare queries (metrics, histograms) | Per-thread Fenwicks; query sums all of them | Uncontended writes measured 6–67× faster than a lock; query cost × threads is acceptable when queries are rare |
| Balanced reads and writes | Atomic cells | Exact final state, no locks; readers may see a partially applied update (non-linearizable) |
| Queries must be linearizable ("exact at an instant") | A lock, or single-writer + snapshot publication | Pay for consistency only where the contract demands it |
| Range updates (lazy trees) | Single writer per tree, or a lock | Lazy pushes mutate internal nodes during *reads*, so even queries write. Concurrent lock-free reads are unsafe |

The last row is the trap. In a lazy segment tree, **queries mutate the tree** (they push tags down), so a "read-only" query isn't read-only, and two concurrent "readers" race. A design review should catch that sentence.

### 4.2 Extension B — "an unbounded stream of (timestamp, value), range queries over time"

* **Time-bucketed ring:** a Fenwick over the last W buckets, with the bucket index modulo W. Expiring a bucket subtracts its total. O(W) memory and O(log W) per operation.
* **Sparse dynamic trees** cover arbitrary keys online with memory proportional to the updates. Pair them with a retention policy (drop subtrees older than a horizon) to keep memory bounded.
* **Approximate range counts** over unbounded key spaces: dyadic Count-Min sketches (one sketch per tree level, Cormode and Muthukrishnan) answer range sums with bounded error in bounded memory (Folder 06).

### 4.3 Extension C — "the key space is range-partitioned over 100 machines"

* Each shard owns a contiguous key range and a local tree. A range query is split at shard boundaries: full shards answer with their **root summary** (one value), and the two edge shards answer partial ranges. That is a two-level segment tree whose top level lives in the router.
* Any associative summary composes this way (sum, min, max, the max-subarray tuple), so the same design answers "max over the last day across all shards".
* **Rebalancing** moves a key range from one shard to another, carrying its subtree (or its raw data) and rebuilding locally. Fenwick's implicit layout can't be split cheaply; a segment tree's subtrees can.
* **Hot ranges** (recent timestamps) concentrate writes on one shard. Salt by a hash suffix within the range, or pre-split time ranges, and sum the salted partitions at query time.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Lazy tag applied without × length | Range sums wrong after range updates (14,775 of ~26,700 here) | `apply(node, len, d)`; oracle tests that include range updates |
| F2 | Forgetting to push before descending | Children read stale values | Push at the top of every recursive call that descends |
| F3 | Fenwick for min/max | Wrong answers: min has no inverse | Segment tree, or a sparse table for static data |
| F4 | `int` sums, `4*MAXN` globals | Overflow; fixed capacity | `long`, sized from `n`, instance state |
| F5 | Dense tree over a huge coordinate range | Out of memory | Sparse dynamic nodes, or offline compression |
| F6 | Object-per-node dynamic trees | 3–5× memory, pointer chasing, GC | Parallel primitive arrays as a node pool |
| F7 | One lock around a write-heavy tree | Writers serialize (up to 1.4 s vs 21 ms) | Per-thread trees, or atomic cells for commutative updates |
| F8 | Concurrent "read-only" queries on a lazy tree | Data races: queries push tags | Single writer, or lock reads too |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Fenwick or segment tree for range sums with point updates?"</b></summary>

**Initial Prompt.** The candidate reaches for a segment tree.

**L5 Answer.** "Segment tree, it's more general."

**Why L5 Stalls.** Generality has a cost: measured 2× (bottom-up) to 14× (recursive lazy) slower than Fenwick for exactly this workload, and more code.

**L7 Answer.** "Sums are invertible, so a Fenwick tree does it in two short loops, half the memory, and was the fastest of the three I measured: about 60–90 ns per update+query pair against 130–180 for a bottom-up segment tree and about 1 µs for a recursive lazy one. I'd switch to a segment tree for min/max, for range assignment, or for any non-invertible associative summary."
</details>

<details><summary><b>Q2 · "Add d to every element in [l, r], then query range sums."</b></summary>

**Initial Prompt.** Range update, range query.

**L5 Answer.** Writes a lazy segment tree; the range sum is off after the first range update.

**Why L5 Stalls.** The lazy tag was added to the node's sum once instead of once per element in the segment, the bug the listing keeps on purpose.

**L7 Answer.** "Lazy invariant: a node's summary already includes its own pending tag, and its children don't. So applying d to a node adds d × length to its sum and d to its min, and before I descend I push the tag to both children. For sums alone I could avoid lazy entirely with two Fenwicks: prefix(i) = B1(i)·i − B2(i). Either way I'd test against a plain array with a mix that *includes range updates*. Point updates alone can't catch the length bug."
</details>

<details><summary><b>Q3 · "Coordinates go up to 10⁹ and arrive online."</b></summary>

**Initial Prompt.** Range counts over prices or timestamps.

**L5 Answer.** "Coordinate-compress first."

**Why L5 Stalls.** Compression needs all coordinates in advance, and they arrive online.

**L7 Answer.** "A sparse dynamic segment tree: create nodes only on update paths, at most 30 per update for a 2³⁰ range, with node 0 as a shared empty child. I'd store nodes as parallel int/long arrays rather than objects to avoid headers and GC. With 20,000 updates the listing uses 336k nodes against 2.1 billion for a dense tree. If the coordinates were known up front, compression plus a Fenwick would be smaller and faster still."
</details>

<details><summary><b>Q4 · "64 threads increment counters at random indices; occasionally someone queries a range."</b></summary>

**Initial Prompt.** Extension A.

**L5 Answer.** "Synchronize the add and query methods."

**Why L5 Stalls.** Writers serialize; measured, one lock was the slowest option by up to 60×.

**L7 Answer.** "Adds commute, so I don't need mutual exclusion for correctness of the final state. If queries are rare, each thread gets its own Fenwick and a query sums across them: writes never contend, measured about 20–60 ms vs 0.4–1.4 s with a lock. If I need fewer copies, each Fenwick cell becomes an atomic with fetch-add: exact eventually, but a concurrent reader can see a half-applied update. If a query must be exact at an instant, I'd use a single writer that publishes snapshots."
</details>

<details><summary><b>Q5 · "Is a lazy segment tree safe for concurrent readers?"</b></summary>

**Initial Prompt.** A follow-up after the candidate proposes a read-write lock.

**L5 Answer.** "Yes, readers don't modify anything."

**Why L5 Stalls.** In a lazy tree, queries push tags down: reads write.

**L7 Answer.** "No. A query pushes pending tags into children, so two concurrent queries can race on the same nodes. Under a read-write lock that's a data race inside the read side. Options: take the write lock for queries too (simple, serial), push all tags eagerly at update time so queries are truly read-only (slower updates), or give each tree a single writer and publish immutable snapshots for readers."
</details>

<details><summary><b>Q6 · "The data is range-partitioned across 100 shards."</b></summary>

**Initial Prompt.** Extension C: range max over all shards.

**L5 Answer.** "Query every shard and combine."

**Why L5 Stalls.** Correct but fans out to all shards even for narrow ranges, and recomputes full-shard answers that could be cached.

**L7 Answer.** "The router keeps one summary per shard (its root value), a top-level segment tree over shards. A query is split at shard boundaries: fully covered shards contribute their cached summary, and only the two edge shards get a partial-range request. That works for any associative summary. Each shard keeps its root current in the router, either on every update or periodically with a staleness bound."
</details>

<details><summary><b>Q7 · "Why is your recursive segment tree slower than expected?"</b></summary>

**Initial Prompt.** Performance probe after the candidate quotes O(log n).

**L5 Answer.** "Log n is 20; it should be fast."

**Why L5 Stalls.** It ignores recursion overhead, push checks and memory traffic per level.

**L7 Answer.** "Per level it makes a call, checks and maybe pushes a tag, and touches up to three arrays: sum, min and tag. That's a lot more than Fenwick's one array and one add. I measured about 1 µs vs about 70 ns per operation. If I only need point updates, a bottom-up iterative tree halves the memory and removes recursion. If I need laziness, it's still fine for 10⁵–10⁶ operations, and I'd say so instead of optimizing blindly."
</details>

<details><summary><b>Q8 · "How do you test a segment tree?"</b></summary>

**Initial Prompt.** Verification probe.

**L5 Answer.** "Try a few ranges by hand."

**Why L5 Stalls.** Hand tests rarely include range updates followed by overlapping range queries, which is where the bugs live.

**L7 Answer.** "Against a plain array: random sizes up to about 30, random mixes of point adds, range adds and queries, including ranges at the edges and of length 1. Compare every query. That oracle immediately catches the forgotten × length and missing pushes; the listing's buggy variant fails 14,775 times. I'd also run each structure against the others on the same operation stream, since that costs nothing."
</details>

---

## 7. Checklist

* [ ] Choose by operation: invertible → Fenwick; associative only → segment tree; range assignment or add → lazy.
* [ ] Lazy invariant stated: summary includes own tag; push before descending; `× length`.
* [ ] `long` sums; sized from `n`; no globals.
* [ ] Huge sparse coordinates: dynamic nodes in primitive arrays; or offline compression.
* [ ] Test against an array oracle with range updates in the mix.
* [ ] Extension A: commutative updates → per-thread trees or atomic cells; lazy trees need a single writer.
* [ ] Extension B: time-bucket rings; retention for dynamic trees; sketches for approximate ranges.
* [ ] Extension C: router-level summaries per shard; edge shards answer partial ranges.

---

## 8. References

* P. M. Fenwick, *A New Data Structure for Cumulative Frequency Tables*, Software: Practice and Experience 24(3), 1994 — DOI 10.1002/spe.4380240306
* G. Cormode, S. Muthukrishnan, *An Improved Data Stream Summary: The Count-Min Sketch and its Applications*, J. Algorithms 55(1), 2005 — DOI 10.1016/j.jalgor.2003.12.001 (dyadic range sums)
* cp-algorithms: [Fenwick tree](https://cp-algorithms.com/data_structures/fenwick.html), [Segment tree](https://cp-algorithms.com/data_structures/segment_tree.html)
* Al.Cash, *Efficient and easy segment trees* (bottom-up iterative trees) — <https://codeforces.com/blog/entry/18051>
* Java SE 21 API: `AtomicLongArray` — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/atomic/AtomicLongArray.html>
* LeetCode anchors: [307 Range Sum Query - Mutable](https://leetcode.com/problems/range-sum-query-mutable/), [315 Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/), [699 Falling Squares](https://leetcode.com/problems/falling-squares/), [732 My Calendar III](https://leetcode.com/problems/my-calendar-iii/)

*Folder 03:* [01 — LCA, Euler tour, HLD](01-binary-lifting-lca-euler-tour-flattening-and-heavy-light-decomposition.md) · [03 — radix tries, Aho–Corasick, XOR tries](03-compressed-radix-tries-aho-corasick-automata-and-bitwise-xor-tries.md)
