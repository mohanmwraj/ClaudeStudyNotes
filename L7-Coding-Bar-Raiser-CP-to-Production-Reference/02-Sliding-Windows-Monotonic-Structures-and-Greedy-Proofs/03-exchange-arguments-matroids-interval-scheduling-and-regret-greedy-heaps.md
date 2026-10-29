# Exchange Arguments, Matroids, Interval Scheduling and Regret-Greedy Heaps

> **Folder 02 · File 3 of 3** — how to *prove* a greedy in two minutes, how to *refute* one in two seconds with a random oracle, and why matroids are both the theory and the Extension C trick.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 2.5 | `GreedyProofs.java` | Earliest-finish passes 20,000 exhaustive checks; earliest-start and shortest-first fail, shrunk to 3-interval counterexamples. Meeting rooms' tie rule; LC 630's regret heap vs take-if-fits; unit jobs with deadlines as a matroid with DSU slots; weighted intervals need DP. Merging per-shard matroid optima is exact |
| 2.6 | `greedy_proofs.cpp` | The same, byte-for-byte the same results; `stable_sort` is required to match Java's stable `List.sort` |

**Verification.** Both listings were extracted from this file, compiled and run. Every output is **Output (verified)**, identical between Java and both C++ builds apart from number formatting.

---

## 0. Orientation

Greedy algorithms are where competitive programmers are most often *right for the wrong reason*. In a contest, a greedy that passes the tests is accepted. In a Staff round the follow-up is **"prove it"**, and a wrong greedy that happens to pass the sample is the most common silent failure in this folder. The L7 toolkit has three parts:

1. **A proof template:** the exchange argument, or "greedy stays ahead".
2. **A refutation machine:** a brute-force oracle on small random inputs plus shrinking (Folder 01, File 3), which finds a counterexample to a wrong greedy in seconds.
3. **A theory that predicts when greedy works:** matroids. It also hands you a distributed algorithm for free.

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| "Sort by something that feels right" | Earliest start, shortest first and heaviest first all fail on 3-interval inputs | State the exchange argument; if you can't, run the oracle before trusting it |
| Take-if-fits, never reconsider | LeetCode 630 loses courses | Regret greedy: take, then evict the worst choice with a heap when infeasible |
| Closed/half-open intervals by feel | Meeting rooms off by one on touching intervals | Interval semantics in the contract; tie order of sweep events follows from it |
| Greedy for weighted interval scheduling | Wrong whenever a heavy interval blocks two lighter ones | Recognize "not a matroid" and use DP: O(n log n) with binary search |
| Recursive DSU `find` | Stack overflow on long chains | Iterative with path halving |

---

## 1. First principles

### 1.1 The exchange argument

To prove a greedy is optimal: take any optimal solution `O`, look at the **first** place it differs from the greedy solution `G`, and show you can **exchange** `O`'s choice for `G`'s without making `O` worse. Repeating the exchange turns `O` into `G` with no loss, so `G` is optimal. For interval scheduling by **earliest finish**:

* Let `g₁` be the interval with the earliest end and `o₁` the first interval of `O`. Since `end(g₁) ≤ end(o₁)`, replacing `o₁` by `g₁` in `O` keeps every later interval of `O` compatible (they start after `end(o₁) ≥ end(g₁)`). Same size, still feasible.
* Induct on the remainder after `end(g₁)`.

The same argument **fails** for earliest start: replacing `o₁` by the earliest-starting interval may end *later* and conflict with `o₂`. That's the counterexample the listing finds: `[0,3)` starts first and blocks both `[1,2)` and `[2,3)`.

**"Greedy stays ahead"** is the same idea stated as an invariant. After k choices, the greedy's k-th interval ends no later than the optimum's k-th. Either form is a 60-second proof in an interview.

### 1.2 Matroids: when greedy is provably optimal

A **matroid** is a ground set with a family of "independent" subsets that is

1. **hereditary**: subsets of independent sets are independent; and
2. **exchange-closed**: if `|A| < |B|` are independent, some `x ∈ B \ A` makes `A ∪ {x}` independent.

**Rado–Edmonds theorem:** "sort by weight descending, add the element if the set stays independent" gives a maximum-weight independent set **for every weight function** if and only if the structure is a matroid. Examples:

| Matroid | Independent sets | Greedy it justifies |
|---|---|---|
| Uniform | Any set of ≤ k elements | Top-k by weight |
| Graphic | Edge sets with no cycle (forests) | Kruskal's minimum spanning tree |
| Scheduling (transversal) | Unit jobs that can all meet their deadlines | Job sequencing: most profitable first, latest free slot |
| Linear | Linearly independent vectors | Max-weight basis (XOR basis in Folder 03) |

**Unit jobs with deadlines** form a matroid. A set is schedulable iff, for every `t`, at most `t` jobs have deadline ≤ `t` (Hall's condition), and that family is hereditary and exchange-closed. So "highest profit first, put it in the latest free slot ≤ its deadline" is optimal. The "latest free slot" query is a disjoint-set union where `find(t)` returns the latest free slot ≤ `t`, and taking slot `s` links `s` to `s − 1`: `O(n α(n))` overall.

**Weighted interval scheduling is not a matroid.** `{[0,2)}` and `{[0,1), [1,2)}` are both maximal, with different sizes, so exchange fails. No greedy order works for all weights. The listing's minimal counterexample: weights 7 vs 6 + 2. The fix is DP over intervals sorted by end, `dp[i] = max(dp[i−1], w_i + dp[p(i)])`, where `p(i)` is found by binary search.

### 1.3 Regret greedy

Some problems need a greedy that can **undo** a choice. In LeetCode 630 (courses with durations and deadlines; maximize the number taken), process courses by deadline, always take the current one, and if the total time now exceeds the deadline, **drop the longest course taken so far** (a max-heap). Exchange argument: among all feasible sets of size k ending by this deadline, the one with the least total duration dominates, because it leaves the most room for the future. Dropping the longest restores feasibility and minimizes the remaining total. The plain "take if it fits" greedy has no undo and loses: minimal counterexample `[(1,6), (1,6), (5,5), (1,5)]`, 2 courses instead of 3. The same pattern ("commit, then regret through a heap") solves minimum refueling stops (LeetCode 871), IPO (LeetCode 502) and many scheduling problems.

### 1.4 Interval semantics decide tie order

For meeting rooms (LeetCode 253), the minimum number of rooms is the maximum overlap, computed by a sweep over `+1` at each start and `−1` at each end. With **half-open** intervals `[s, e)`, a meeting ending at 9 and one starting at 9 can share a room, so at equal times **ends must be processed before starts**. Sorting starts first answers 2 rooms for `[[0,2), [2,3)]`; the truth is 1. For closed intervals the opposite order is correct. Either way, the tie order is derived from the contract, not chosen by habit.

---

## 2. The listings

### 2.1 Listing 2.5 — Java

```java
// GreedyProofs.java - which greedy is right, proven by exchange argument and checked against exhaustive search.
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.PriorityQueue;
import java.util.function.Function;
import java.util.function.Predicate;

public final class GreedyProofs {

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

    /** Half-open [start, end) with a weight; validated once. */
    record Iv(int start, int end, int weight) {
        Iv {
            if (start >= end) throw new IllegalArgumentException("need start < end");
        }
        @Override
        public String toString() { return "[" + start + "," + end + (weight == 1 ? ")" : ")w" + weight); }
    }

    static List<Iv> randomIntervals(SplitMix64 r, int maxN, int maxW) {
        List<Iv> out = new ArrayList<>();
        int n = r.nextInt(maxN + 1);
        for (int i = 0; i < n; i++) {
            int s = r.nextInt(10);
            out.add(new Iv(s, s + 1 + r.nextInt(5), 1 + r.nextInt(maxW)));
        }
        return out;
    }

    static <T> List<T> shrinkList(List<T> x, Predicate<List<T>> fails, Function<T, List<T>> smaller,
                                  Function<List<T>, List<List<T>>> whole) {
        for (boolean progress = true; progress; ) {
            progress = false;
            List<List<T>> cands = new ArrayList<>();
            for (int i = 0; i < x.size(); i++) {
                List<T> c = new ArrayList<>(x);
                c.remove(i);
                cands.add(c);
            }
            for (int i = 0; i < x.size(); i++) {
                for (T s : smaller.apply(x.get(i))) {
                    List<T> c = new ArrayList<>(x);
                    c.set(i, s);
                    cands.add(c);
                }
            }
            cands.addAll(whole.apply(x));
            for (List<T> c : cands) if (fails.test(c)) { x = c; progress = true; break; }
        }
        return x;
    }

    static <T> List<T> shrinkList(List<T> x, Predicate<List<T>> fails, Function<T, List<T>> smaller) {
        return shrinkList(x, fails, smaller, l -> List.of());
    }

    /** Moves every interval left together, which keeps touching and overlapping pairs intact. */
    static List<List<Iv>> translateLeft(List<Iv> x) {
        if (x.isEmpty() || x.stream().anyMatch(v -> v.start() == 0)) return List.of();
        return List.of(x.stream().map(v -> new Iv(v.start() - 1, v.end() - 1, v.weight())).toList());
    }

    static List<Iv> smallerIv(Iv v) {
        List<Iv> out = new ArrayList<>();
        if (v.start() > 0) out.add(new Iv(v.start() - 1, v.end() - 1, v.weight()));
        if (v.end() - v.start() > 1) out.add(new Iv(v.start(), v.end() - 1, v.weight()));
        if (v.weight() > 1) out.add(new Iv(v.start(), v.end(), v.weight() - 1));
        return out;
    }

    // ===================================================================== 1. max non-overlapping intervals
    /** Generic "sort, then take whatever fits". Only the ORDER differs between the right and the wrong greedies. */
    static int greedyCount(List<Iv> ivs, Comparator<Iv> order) {
        List<Iv> s = new ArrayList<>(ivs);
        s.sort(order);
        int count = 0, lastEnd = Integer.MIN_VALUE;
        List<Iv> taken = new ArrayList<>();
        for (Iv v : s) {
            boolean fits = taken.stream().allMatch(t -> v.end() <= t.start() || t.end() <= v.start());
            if (fits) { taken.add(v); count++; lastEnd = Math.max(lastEnd, v.end()); }
        }
        return count;
    }

    static final Comparator<Iv> EARLIEST_FINISH = Comparator.comparingInt(Iv::end).thenComparingInt(Iv::start);
    static final Comparator<Iv> EARLIEST_START = Comparator.comparingInt(Iv::start).thenComparingInt(Iv::end);
    static final Comparator<Iv> SHORTEST = Comparator.comparingInt((Iv v) -> v.end() - v.start()).thenComparingInt(Iv::start);

    static int maxIndependentOracle(List<Iv> ivs, boolean weighted) {
        int best = 0, n = ivs.size();
        for (int mask = 0; mask < 1 << n; mask++) {
            List<Iv> pick = new ArrayList<>();
            for (int i = 0; i < n; i++) if ((mask >> i & 1) == 1) pick.add(ivs.get(i));
            boolean ok = true;
            for (int i = 0; i < pick.size() && ok; i++)
                for (int j = i + 1; j < pick.size() && ok; j++)
                    ok = pick.get(i).end() <= pick.get(j).start() || pick.get(j).end() <= pick.get(i).start();
            if (ok) best = Math.max(best, weighted ? pick.stream().mapToInt(Iv::weight).sum() : pick.size());
        }
        return best;
    }

    // ===================================================================== 2. LC 253 meeting rooms
    /** Sweep: +1 at start, -1 at end. Half-open intervals: at equal times process ends BEFORE starts. */
    static int minRooms(List<Iv> ivs, boolean endsFirst) {
        List<int[]> ev = new ArrayList<>();
        for (Iv v : ivs) { ev.add(new int[] {v.start(), +1}); ev.add(new int[] {v.end(), -1}); }
        ev.sort(Comparator.<int[]>comparingInt(e -> e[0]).thenComparingInt(e -> endsFirst ? e[1] : -e[1]));
        int cur = 0, best = 0;
        for (int[] e : ev) best = Math.max(best, cur += e[1]);
        return best;
    }

    static int minRoomsOracle(List<Iv> ivs) {
        int best = 0;
        for (int t = 0; t < 20; t++) {
            final int q = t;
            best = Math.max(best, (int) ivs.stream().filter(v -> v.start() <= q && q < v.end()).count());
        }
        return best;
    }

    // ===================================================================== 3. LC 630 course schedule III (regret greedy)
    record Course(int duration, int deadline) {
        @Override
        public String toString() { return "(" + duration + "," + deadline + ")"; }
    }

    /** Contest guess: by deadline, take a course if it still fits. Never reconsiders. */
    static int coursesNoRegret(List<Course> cs) {
        List<Course> s = new ArrayList<>(cs);
        s.sort(Comparator.comparingInt(Course::deadline));
        long time = 0;
        int taken = 0;
        for (Course c : s) if (time + c.duration() <= c.deadline()) { time += c.duration(); taken++; }
        return taken;
    }

    /**
     * By deadline; always take; if the deadline is now violated, drop the LONGEST course taken so far.
     * Exchange argument: among schedules with k courses ending by this deadline, the one with the least total time
     * dominates, and dropping the longest restores feasibility while minimizing time. O(n log n).
     */
    static int coursesWithRegret(List<Course> cs) {
        List<Course> s = new ArrayList<>(cs);
        s.sort(Comparator.comparingInt(Course::deadline));
        PriorityQueue<Integer> longest = new PriorityQueue<>(Comparator.reverseOrder());
        long time = 0;
        for (Course c : s) {
            time += c.duration();
            longest.add(c.duration());
            if (time > c.deadline()) time -= longest.poll();
        }
        return longest.size();
    }

    static int coursesOracle(List<Course> cs) {
        int best = 0, n = cs.size();
        for (int mask = 0; mask < 1 << n; mask++) {
            List<Course> pick = new ArrayList<>();
            for (int i = 0; i < n; i++) if ((mask >> i & 1) == 1) pick.add(cs.get(i));
            pick.sort(Comparator.comparingInt(Course::deadline));   // a feasible set is feasible in deadline order
            long time = 0;
            boolean ok = true;
            for (Course c : pick) ok &= (time += c.duration()) <= c.deadline();
            if (ok) best = Math.max(best, pick.size());
        }
        return best;
    }

    // ===================================================================== 4. unit jobs with deadlines: a matroid
    record Job(int id, int deadline, long profit) {}

    /** Matroid greedy: heaviest first, keep if still schedulable. "Latest free slot <= deadline" via DSU: O(n α(n)). */
    static List<Job> scheduleJobs(List<Job> jobs) {
        int maxSlot = jobs.stream().mapToInt(Job::deadline).max().orElse(0);
        int[] parent = new int[maxSlot + 1];  // parent[t] leads to the latest free slot <= t; slot 0 = "none"
        for (int t = 0; t <= maxSlot; t++) parent[t] = t;
        List<Job> s = new ArrayList<>(jobs);
        s.sort(Comparator.comparingLong(Job::profit).reversed().thenComparingInt(Job::id));
        List<Job> chosen = new ArrayList<>();
        for (Job j : s) {
            int slot = find(parent, j.deadline());
            if (slot > 0) { chosen.add(j); parent[slot] = slot - 1; }
        }
        return chosen;
    }

    static int find(int[] p, int x) {  // iterative, with path halving: no recursion depth to worry about
        while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; }
        return x;
    }

    static long profit(List<Job> js) { return js.stream().mapToLong(Job::profit).sum(); }

    static long jobsOracle(List<Job> jobs) {
        long best = 0;
        int n = jobs.size();
        for (int mask = 0; mask < 1 << n; mask++) {
            int[] byDeadline = new int[12];
            long p = 0;
            for (int i = 0; i < n; i++) if ((mask >> i & 1) == 1) { byDeadline[jobs.get(i).deadline()]++; p += jobs.get(i).profit(); }
            boolean ok = true;
            for (int t = 1, cum = 0; t < 12 && ok; t++) ok = (cum += byDeadline[t]) <= t;  // Hall's condition
            if (ok) best = Math.max(best, p);
        }
        return best;
    }

    // ===================================================================== 5. weighted intervals: not a matroid -> DP
    static int greedyByWeight(List<Iv> ivs) {
        List<Iv> s = new ArrayList<>(ivs);
        s.sort(Comparator.comparingInt(Iv::weight).reversed().thenComparingInt(Iv::end));
        List<Iv> taken = new ArrayList<>();
        for (Iv v : s) if (taken.stream().allMatch(t -> v.end() <= t.start() || t.end() <= v.start())) taken.add(v);
        return taken.stream().mapToInt(Iv::weight).sum();
    }

    /** dp[i] = best using the first i intervals by end; p(i) = intervals ending <= start_i, by binary search. O(n log n). */
    static long weightedDp(List<Iv> ivs) {
        List<Iv> s = new ArrayList<>(ivs);
        s.sort(Comparator.comparingInt(Iv::end));
        long[] dp = new long[s.size() + 1];
        for (int i = 1; i <= s.size(); i++) {
            Iv v = s.get(i - 1);
            int lo = 0, hi = i - 1;                  // count of intervals among the first i-1 with end <= v.start
            while (lo < hi) {
                int mid = (lo + hi + 1) >>> 1;
                if (s.get(mid - 1).end() <= v.start()) lo = mid; else hi = mid - 1;
            }
            dp[i] = Math.max(dp[i - 1], v.weight() + dp[lo]);
        }
        return dp[s.size()];
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(41);
        int trials = 20_000;
        String[] names = {"earliest finish", "earliest start", "shortest first"};
        List<Comparator<Iv>> orders = List.of(EARLIEST_FINISH, EARLIEST_START, SHORTEST);
        int[] ok = new int[3];
        List<List<Iv>> firstBad = new ArrayList<>(List.of(List.of(), List.of(), List.of()));
        int okRooms = 0, cpRooms = 0, okCourses = 0, cpCourses = 0, okJobs = 0, okDp = 0, greedyW = 0;
        List<Course> badCourses = null;
        List<Iv> badRooms = null, badWeighted = null;
        for (int t = 0; t < trials; t++) {
            List<Iv> ivs = randomIntervals(r, 8, 1);
            int want = maxIndependentOracle(ivs, false);
            for (int g = 0; g < 3; g++) {
                if (greedyCount(ivs, orders.get(g)) == want) ok[g]++;
                else if (firstBad.get(g).isEmpty()) firstBad.set(g, ivs);
            }
            int rooms = minRoomsOracle(ivs);
            okRooms += minRooms(ivs, true) == rooms ? 1 : 0;
            if (minRooms(ivs, false) == rooms) cpRooms++;
            else if (badRooms == null) badRooms = ivs;
            List<Course> cs = new ArrayList<>();
            for (int i = r.nextInt(8); i > 0; i--) cs.add(new Course(1 + r.nextInt(5), 1 + r.nextInt(12)));
            int wantC = coursesOracle(cs);
            okCourses += coursesWithRegret(cs) == wantC ? 1 : 0;
            if (coursesNoRegret(cs) == wantC) cpCourses++;
            else if (badCourses == null) badCourses = cs;
            List<Job> jobs = new ArrayList<>();
            for (int i = r.nextInt(9); i > 0; i--) jobs.add(new Job(jobs.size(), 1 + r.nextInt(5), 1 + r.nextInt(20)));
            okJobs += profit(scheduleJobs(jobs)) == jobsOracle(jobs) ? 1 : 0;
            List<Iv> wiv = randomIntervals(r, 8, 9);
            int wantW = maxIndependentOracle(wiv, true);
            okDp += weightedDp(wiv) == wantW ? 1 : 0;
            if (greedyByWeight(wiv) == wantW) greedyW++;
            else if (badWeighted == null) badWeighted = wiv;
        }
        System.out.printf("1. max non-overlapping intervals (half-open), %d random sets of <= 8, vs exhaustive search:%n", trials);
        for (int g = 0; g < 3; g++) {
            final Comparator<Iv> ord = orders.get(g);
            String ce = "";
            if (!firstBad.get(g).isEmpty()) {
                List<Iv> m = shrinkList(firstBad.get(g), x -> greedyCount(x, ord) != maxIndependentOracle(x, false),
                        GreedyProofs::smallerIv, GreedyProofs::translateLeft);
                ce = "  minimal counterexample " + m + ": greedy " + greedyCount(m, ord) + ", optimum " + maxIndependentOracle(m, false);
            }
            System.out.printf("   %-16s %5d/%d%s%n", names[g], ok[g], trials, ce);
        }
        List<Iv> mr = shrinkList(badRooms, x -> minRooms(x, false) != minRoomsOracle(x), GreedyProofs::smallerIv,
                GreedyProofs::translateLeft);
        System.out.printf("2. LC 253 meeting rooms: ends-before-starts sweep %d/%d | starts-first %d/%d, minimal %s -> %d rooms, truth %d%n",
                okRooms, trials, cpRooms, trials, mr, minRooms(mr, false), minRoomsOracle(mr));
        List<Course> mc = shrinkList(badCourses, x -> coursesNoRegret(x) != coursesOracle(x), c -> {
            List<Course> out = new ArrayList<>();
            if (c.duration() > 1) out.add(new Course(c.duration() - 1, c.deadline()));
            if (c.deadline() > 1) out.add(new Course(c.duration(), c.deadline() - 1));
            return out;
        });
        System.out.printf("3. LC 630 courses (duration,deadline): regret heap %d/%d | take-if-fits %d/%d, minimal %s -> %d, optimum %d%n",
                okCourses, trials, cpCourses, trials, mc, coursesNoRegret(mc), coursesOracle(mc));
        System.out.printf("4. unit jobs with deadlines (matroid greedy + DSU slots) vs exhaustive: %d/%d%n", okJobs, trials);
        List<Iv> mw = shrinkList(badWeighted, x -> greedyByWeight(x) != maxIndependentOracle(x, true), GreedyProofs::smallerIv,
                GreedyProofs::translateLeft);
        System.out.printf("5. weighted intervals: DP %d/%d | heaviest-first greedy %d/%d, minimal %s -> %d, optimum %d%n",
                okDp, trials, greedyW, trials, mw, greedyByWeight(mw), maxIndependentOracle(mw, true));

        // Extension C: in a matroid, an element outside a shard's optimal basis is never in the global optimum.
        int shards = 16, perShard = 2_000;
        List<List<Job>> parts = new ArrayList<>();
        List<Job> all = new ArrayList<>();
        for (int s = 0; s < shards; s++) {
            List<Job> part = new ArrayList<>();
            for (int i = 0; i < perShard; i++) {
                Job j = new Job(all.size(), 1 + r.nextInt(200), 1 + r.nextInt(1_000_000));  // only 200 slots exist
                part.add(j);
                all.add(j);
            }
            parts.add(part);
        }
        List<Job> shipped = new ArrayList<>();
        long naiveSum = 0;
        for (List<Job> part : parts) {
            List<Job> local = scheduleJobs(part);
            shipped.addAll(local);
            naiveSum += profit(local);
        }
        long global = profit(scheduleJobs(all)), merged = profit(scheduleJobs(shipped));
        System.out.printf("C. %d shards x %,d jobs: global optimum %,d | greedy over the union of local optima %,d (ships %,d of %,d jobs)"
                + " | sum of local profits %,d (infeasible: shards reuse the same slots)%n", shards, perShard, global, merged,
                shipped.size(), all.size(), naiveSum);
    }
}
```

**Output (verified):**

```text
1. max non-overlapping intervals (half-open), 20000 random sets of <= 8, vs exhaustive search:
   earliest finish  20000/20000
   earliest start   18533/20000  minimal counterexample [[2,3), [1,2), [0,3)]: greedy 1, optimum 2
   shortest first   19746/20000  minimal counterexample [[2,4), [0,3), [3,5)]: greedy 1, optimum 2
2. LC 253 meeting rooms: ends-before-starts sweep 20000/20000 | starts-first 13717/20000, minimal [[0,2), [2,3)] -> 2 rooms, truth 1
3. LC 630 courses (duration,deadline): regret heap 20000/20000 | take-if-fits 19399/20000, minimal [(1,6), (1,6), (5,5), (1,5)] -> 2, optimum 3
4. unit jobs with deadlines (matroid greedy + DSU slots) vs exhaustive: 20000/20000
5. weighted intervals: DP 20000/20000 | heaviest-first greedy 18462/20000, minimal [[1,2)w2, [0,2)w7, [0,1)w6] -> 7, optimum 8
C. 16 shards x 2,000 jobs: global optimum 199,349,408 | greedy over the union of local optima 199,349,408 (ships 3,200 of 32,000 jobs) | sum of local profits 3,036,195,552 (infeasible: shards reuse the same slots)
```

### 2.2 Listing 2.6 — C++23

```cpp
// greedy_proofs.cpp - which greedy is right, proven by exchange argument and checked against exhaustive search.
#include <algorithm>
#include <cstdint>
#include <format>
#include <functional>
#include <numeric>
#include <print>
#include <queue>
#include <stdexcept>
#include <string>
#include <vector>

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

// Half-open [start, end) with a weight; the only constructor validates.
struct Iv {
    int start, end, weight;
    Iv(int s, int e, int w) : start(s), end(e), weight(w) {
        if (s >= e) throw std::invalid_argument("need start < end");
    }
    friend bool operator==(const Iv&, const Iv&) = default;
};
using Ivs = std::vector<Iv>;

std::string show(const Iv& v) { return v.weight == 1 ? std::format("[{},{})", v.start, v.end) : std::format("[{},{})w{}", v.start, v.end, v.weight); }
template <class T, class F>
std::string show_list(const std::vector<T>& xs, F f) {
    std::string s = "[";
    for (std::size_t i = 0; i < xs.size(); ++i) s += (i ? ", " : "") + f(xs[i]);
    return s + "]";
}

Ivs random_intervals(SplitMix64& r, int max_n, int max_w) {
    Ivs out;
    int n = r.next_int(max_n + 1);
    for (int i = 0; i < n; ++i) {
        int s = r.next_int(10);
        int e = s + 1 + r.next_int(5);  // one draw per statement: argument evaluation order is unspecified
        int w = 1 + r.next_int(max_w);
        out.emplace_back(s, e, w);
    }
    return out;
}

template <class T, class Fails, class Smaller, class Whole>
std::vector<T> shrink_list(std::vector<T> x, Fails fails, Smaller smaller, Whole whole) {
    for (bool progress = true; progress;) {
        progress = false;
        std::vector<std::vector<T>> cands;
        for (std::size_t i = 0; i < x.size(); ++i) {
            auto c = x;
            c.erase(c.begin() + static_cast<std::ptrdiff_t>(i));
            cands.push_back(std::move(c));
        }
        for (std::size_t i = 0; i < x.size(); ++i)
            for (const T& s : smaller(x[i])) {
                auto c = x;
                c[i] = s;
                cands.push_back(std::move(c));
            }
        for (auto& c : whole(x)) cands.push_back(std::move(c));
        for (auto& c : cands)
            if (fails(c)) {
                x = std::move(c);
                progress = true;
                break;
            }
    }
    return x;
}

Ivs smaller_iv(const Iv& v) {
    Ivs out;
    if (v.start > 0) out.emplace_back(v.start - 1, v.end - 1, v.weight);
    if (v.end - v.start > 1) out.emplace_back(v.start, v.end - 1, v.weight);
    if (v.weight > 1) out.emplace_back(v.start, v.end, v.weight - 1);
    return out;
}
// Moves every interval left together, which keeps touching and overlapping pairs intact.
std::vector<Ivs> translate_left(const Ivs& x) {
    if (x.empty() || std::ranges::any_of(x, [](const Iv& v) { return v.start == 0; })) return {};
    Ivs c;
    for (const Iv& v : x) c.emplace_back(v.start - 1, v.end - 1, v.weight);
    return {c};
}

bool disjoint(const Iv& a, const Iv& b) { return a.end <= b.start || b.end <= a.start; }

// ======================================================================= 1. max non-overlapping intervals
// Generic "sort, then take whatever fits". Only the ORDER differs between the right and the wrong greedies.
template <class Order>
int greedy_count(Ivs ivs, Order before) {
    std::ranges::stable_sort(ivs, before);
    Ivs taken;
    for (const Iv& v : ivs)
        if (std::ranges::all_of(taken, [&](const Iv& t) { return disjoint(v, t); })) taken.push_back(v);
    return static_cast<int>(taken.size());
}
auto earliest_finish = [](const Iv& a, const Iv& b) { return a.end != b.end ? a.end < b.end : a.start < b.start; };
auto earliest_start = [](const Iv& a, const Iv& b) { return a.start != b.start ? a.start < b.start : a.end < b.end; };
auto shortest = [](const Iv& a, const Iv& b) {
    return a.end - a.start != b.end - b.start ? a.end - a.start < b.end - b.start : a.start < b.start;
};

int max_independent_oracle(const Ivs& ivs, bool weighted) {
    int best = 0;
    auto n = ivs.size();
    for (std::uint32_t mask = 0; mask < (1u << n); ++mask) {
        Ivs pick;
        for (std::size_t i = 0; i < n; ++i)
            if (mask >> i & 1) pick.push_back(ivs[i]);
        bool ok = true;
        for (std::size_t i = 0; i < pick.size() && ok; ++i)
            for (std::size_t j = i + 1; j < pick.size() && ok; ++j) ok = disjoint(pick[i], pick[j]);
        if (ok) {
            int v = weighted ? std::accumulate(pick.begin(), pick.end(), 0, [](int s, const Iv& x) { return s + x.weight; })
                             : static_cast<int>(pick.size());
            best = std::max(best, v);
        }
    }
    return best;
}

// ======================================================================= 2. LC 253 meeting rooms
// Sweep: +1 at start, -1 at end. Half-open intervals: at equal times process ends BEFORE starts.
int min_rooms(const Ivs& ivs, bool ends_first) {
    std::vector<std::pair<int, int>> ev;
    for (const Iv& v : ivs) ev.emplace_back(v.start, +1), ev.emplace_back(v.end, -1);
    std::ranges::stable_sort(ev, [&](const auto& a, const auto& b) {
        if (a.first != b.first) return a.first < b.first;
        return ends_first ? a.second < b.second : a.second > b.second;
    });
    int cur = 0, best = 0;
    for (const auto& e : ev) best = std::max(best, cur += e.second);
    return best;
}

int min_rooms_oracle(const Ivs& ivs) {
    int best = 0;
    for (int t = 0; t < 20; ++t)
        best = std::max(best, static_cast<int>(std::ranges::count_if(ivs, [t](const Iv& v) { return v.start <= t && t < v.end; })));
    return best;
}

// ======================================================================= 3. LC 630 course schedule III
struct Course {
    int duration, deadline;
};
std::string show(const Course& c) { return std::format("({},{})", c.duration, c.deadline); }

int courses_no_regret(std::vector<Course> cs) {  // contest guess: by deadline, take a course if it still fits
    std::ranges::stable_sort(cs, {}, &Course::deadline);
    std::int64_t time = 0;
    int taken = 0;
    for (const auto& c : cs)
        if (time + c.duration <= c.deadline) time += c.duration, ++taken;
    return taken;
}

// By deadline; always take; if the deadline is now violated, drop the LONGEST course taken so far. O(n log n).
int courses_with_regret(std::vector<Course> cs) {
    std::ranges::stable_sort(cs, {}, &Course::deadline);
    std::priority_queue<int> longest;
    std::int64_t time = 0;
    for (const auto& c : cs) {
        time += c.duration;
        longest.push(c.duration);
        if (time > c.deadline) time -= longest.top(), longest.pop();
    }
    return static_cast<int>(longest.size());
}

int courses_oracle(const std::vector<Course>& cs) {
    int best = 0;
    for (std::uint32_t mask = 0; mask < (1u << cs.size()); ++mask) {
        std::vector<Course> pick;
        for (std::size_t i = 0; i < cs.size(); ++i)
            if (mask >> i & 1) pick.push_back(cs[i]);
        std::ranges::stable_sort(pick, {}, &Course::deadline);  // a feasible set is feasible in deadline order
        std::int64_t time = 0;
        bool ok = true;
        for (const auto& c : pick) ok = ok && (time += c.duration) <= c.deadline;
        if (ok) best = std::max(best, static_cast<int>(pick.size()));
    }
    return best;
}

// ======================================================================= 4. unit jobs with deadlines: a matroid
struct Job {
    int id, deadline;
    std::int64_t profit;
};

int find(std::vector<int>& p, int x) {  // iterative, with path halving: no recursion depth to worry about
    while (p[static_cast<std::size_t>(x)] != x) {
        auto ux = static_cast<std::size_t>(x);
        p[ux] = p[static_cast<std::size_t>(p[ux])];
        x = p[ux];
    }
    return x;
}

// Matroid greedy: heaviest first, keep if still schedulable. "Latest free slot <= deadline" via DSU: O(n α(n)).
std::vector<Job> schedule_jobs(std::vector<Job> jobs) {
    int max_slot = 0;
    for (const auto& j : jobs) max_slot = std::max(max_slot, j.deadline);
    std::vector<int> parent(static_cast<std::size_t>(max_slot) + 1);  // slot 0 = "none left"
    std::iota(parent.begin(), parent.end(), 0);
    std::ranges::stable_sort(jobs, [](const Job& a, const Job& b) { return a.profit != b.profit ? a.profit > b.profit : a.id < b.id; });
    std::vector<Job> chosen;
    for (const auto& j : jobs) {
        int slot = find(parent, j.deadline);
        if (slot > 0) chosen.push_back(j), parent[static_cast<std::size_t>(slot)] = slot - 1;
    }
    return chosen;
}

std::int64_t profit(const std::vector<Job>& js) {
    return std::accumulate(js.begin(), js.end(), std::int64_t{0}, [](std::int64_t s, const Job& j) { return s + j.profit; });
}

std::int64_t jobs_oracle(const std::vector<Job>& jobs) {
    std::int64_t best = 0;
    for (std::uint32_t mask = 0; mask < (1u << jobs.size()); ++mask) {
        int by_deadline[12] = {};
        std::int64_t p = 0;
        for (std::size_t i = 0; i < jobs.size(); ++i)
            if (mask >> i & 1) ++by_deadline[jobs[i].deadline], p += jobs[i].profit;
        bool ok = true;
        for (int t = 1, cum = 0; t < 12 && ok; ++t) ok = (cum += by_deadline[t]) <= t;  // Hall's condition
        if (ok) best = std::max(best, p);
    }
    return best;
}

// ======================================================================= 5. weighted intervals: not a matroid -> DP
int greedy_by_weight(Ivs ivs) {
    std::ranges::stable_sort(ivs, [](const Iv& a, const Iv& b) { return a.weight != b.weight ? a.weight > b.weight : a.end < b.end; });
    Ivs taken;
    for (const Iv& v : ivs)
        if (std::ranges::all_of(taken, [&](const Iv& t) { return disjoint(v, t); })) taken.push_back(v);
    return std::accumulate(taken.begin(), taken.end(), 0, [](int s, const Iv& x) { return s + x.weight; });
}

// dp[i] = best using the first i intervals by end; p(i) = intervals ending <= start_i, by binary search. O(n log n).
std::int64_t weighted_dp(Ivs ivs) {
    std::ranges::stable_sort(ivs, {}, &Iv::end);
    std::vector<std::int64_t> dp(ivs.size() + 1);
    for (std::size_t i = 1; i <= ivs.size(); ++i) {
        const Iv& v = ivs[i - 1];
        auto p = std::ranges::partition_point(ivs.begin(), ivs.begin() + static_cast<std::ptrdiff_t>(i - 1),
                                              [&](const Iv& u) { return u.end <= v.start; }) - ivs.begin();
        dp[i] = std::max(dp[i - 1], v.weight + dp[static_cast<std::size_t>(p)]);
    }
    return dp.back();
}

int main() {
    SplitMix64 r{41};
    constexpr int kTrials = 20'000;
    const char* names[] = {"earliest finish", "earliest start", "shortest first"};
    int ok[3] = {}, ok_rooms = 0, cp_rooms = 0, ok_courses = 0, cp_courses = 0, ok_jobs = 0, ok_dp = 0, greedy_w = 0;
    std::vector<Ivs> first_bad(3);
    Ivs bad_rooms, bad_weighted;
    std::vector<Course> bad_courses;
    auto count_with = [](int g, const Ivs& x) {
        return g == 0 ? greedy_count(x, earliest_finish) : g == 1 ? greedy_count(x, earliest_start) : greedy_count(x, shortest);
    };
    for (int t = 0; t < kTrials; ++t) {
        Ivs ivs = random_intervals(r, 8, 1);
        int want = max_independent_oracle(ivs, false);
        for (int g = 0; g < 3; ++g) {
            if (count_with(g, ivs) == want) ++ok[g];
            else if (first_bad[static_cast<std::size_t>(g)].empty()) first_bad[static_cast<std::size_t>(g)] = ivs;
        }
        int rooms = min_rooms_oracle(ivs);
        ok_rooms += min_rooms(ivs, true) == rooms;
        if (min_rooms(ivs, false) == rooms) ++cp_rooms;
        else if (bad_rooms.empty()) bad_rooms = ivs;
        std::vector<Course> cs;
        for (int i = r.next_int(8); i > 0; --i) {
            int d = 1 + r.next_int(5);
            int dl = 1 + r.next_int(12);
            cs.push_back({d, dl});
        }
        int want_c = courses_oracle(cs);
        ok_courses += courses_with_regret(cs) == want_c;
        if (courses_no_regret(cs) == want_c) ++cp_courses;
        else if (bad_courses.empty()) bad_courses = cs;
        std::vector<Job> jobs;
        for (int i = r.next_int(9); i > 0; --i) {
            int dl = 1 + r.next_int(5);
            std::int64_t p = 1 + r.next_int(20);
            jobs.push_back({static_cast<int>(jobs.size()), dl, p});
        }
        ok_jobs += profit(schedule_jobs(jobs)) == jobs_oracle(jobs);
        Ivs wiv = random_intervals(r, 8, 9);
        int want_w = max_independent_oracle(wiv, true);
        ok_dp += weighted_dp(wiv) == want_w;
        if (greedy_by_weight(wiv) == want_w) ++greedy_w;
        else if (bad_weighted.empty()) bad_weighted = wiv;
    }
    std::println("1. max non-overlapping intervals (half-open), {} random sets of <= 8, vs exhaustive search:", kTrials);
    for (int g = 0; g < 3; ++g) {
        std::string ce;
        if (const auto& fb = first_bad[static_cast<std::size_t>(g)]; !fb.empty()) {
            Ivs m = shrink_list(fb, [&](const Ivs& x) { return count_with(g, x) != max_independent_oracle(x, false); }, smaller_iv,
                                translate_left);
            ce = std::format("  minimal counterexample {}: greedy {}, optimum {}", show_list(m, [](const Iv& v) { return show(v); }),
                             count_with(g, m), max_independent_oracle(m, false));
        }
        std::println("   {:<16} {:5}/{}{}", names[g], ok[g], kTrials, ce);
    }
    Ivs mr = shrink_list(bad_rooms, [](const Ivs& x) { return min_rooms(x, false) != min_rooms_oracle(x); }, smaller_iv, translate_left);
    std::println("2. LC 253 meeting rooms: ends-before-starts sweep {}/{} | starts-first {}/{}, minimal {} -> {} rooms, truth {}",
                 ok_rooms, kTrials, cp_rooms, kTrials, show_list(mr, [](const Iv& v) { return show(v); }), min_rooms(mr, false),
                 min_rooms_oracle(mr));
    auto mc = shrink_list(
        bad_courses, [](const std::vector<Course>& x) { return courses_no_regret(x) != courses_oracle(x); },
        [](const Course& c) {
            std::vector<Course> out;
            if (c.duration > 1) out.push_back({c.duration - 1, c.deadline});
            if (c.deadline > 1) out.push_back({c.duration, c.deadline - 1});
            return out;
        },
        [](const std::vector<Course>&) { return std::vector<std::vector<Course>>{}; });
    std::println("3. LC 630 courses (duration,deadline): regret heap {}/{} | take-if-fits {}/{}, minimal {} -> {}, optimum {}",
                 ok_courses, kTrials, cp_courses, kTrials, show_list(mc, [](const Course& c) { return show(c); }),
                 courses_no_regret(mc), courses_oracle(mc));
    std::println("4. unit jobs with deadlines (matroid greedy + DSU slots) vs exhaustive: {}/{}", ok_jobs, kTrials);
    Ivs mw = shrink_list(bad_weighted, [](const Ivs& x) { return greedy_by_weight(x) != max_independent_oracle(x, true); },
                         smaller_iv, translate_left);
    std::println("5. weighted intervals: DP {}/{} | heaviest-first greedy {}/{}, minimal {} -> {}, optimum {}", ok_dp, kTrials,
                 greedy_w, kTrials, show_list(mw, [](const Iv& v) { return show(v); }), greedy_by_weight(mw),
                 max_independent_oracle(mw, true));

    // Extension C: in a matroid, an element outside a shard's optimal basis is never in the global optimum.
    constexpr int kShards = 16, kPerShard = 2'000;
    std::vector<Job> all, shipped;
    std::int64_t naive_sum = 0;
    for (int s = 0; s < kShards; ++s) {
        std::vector<Job> part;
        for (int i = 0; i < kPerShard; ++i) {
            int dl = 1 + r.next_int(200);  // only 200 slots exist
            std::int64_t p = 1 + r.next_int(1'000'000);
            Job j{static_cast<int>(all.size()), dl, p};
            part.push_back(j);
            all.push_back(j);
        }
        auto local = schedule_jobs(part);
        naive_sum += profit(local);
        shipped.insert(shipped.end(), local.begin(), local.end());
    }
    std::println("C. {} shards x {} jobs: global optimum {} | greedy over the union of local optima {} (ships {} of {} jobs)"
                 " | sum of local profits {} (infeasible: shards reuse the same slots)", kShards, kPerShard,
                 profit(schedule_jobs(all)), profit(schedule_jobs(shipped)), shipped.size(), all.size(), naive_sum);
}
```

**Output, both compilers (verified; GCC shown, Clang identical):**

```text
1. max non-overlapping intervals (half-open), 20000 random sets of <= 8, vs exhaustive search:
   earliest finish  20000/20000
   earliest start   18533/20000  minimal counterexample [[2,3), [1,2), [0,3)]: greedy 1, optimum 2
   shortest first   19746/20000  minimal counterexample [[2,4), [0,3), [3,5)]: greedy 1, optimum 2
2. LC 253 meeting rooms: ends-before-starts sweep 20000/20000 | starts-first 13717/20000, minimal [[0,2), [2,3)] -> 2 rooms, truth 1
3. LC 630 courses (duration,deadline): regret heap 20000/20000 | take-if-fits 19399/20000, minimal [(1,6), (1,6), (5,5), (1,5)] -> 2, optimum 3
4. unit jobs with deadlines (matroid greedy + DSU slots) vs exhaustive: 20000/20000
5. weighted intervals: DP 20000/20000 | heaviest-first greedy 18462/20000, minimal [[1,2)w2, [0,2)w7, [0,1)w6] -> 7, optimum 8
C. 16 shards x 2000 jobs: global optimum 199349408 | greedy over the union of local optima 199349408 (ships 3200 of 32000 jobs) | sum of local profits 3036195552 (infeasible: shards reuse the same slots)
```

---

## 3. What the results show

* **Wrong greedies are wrong rarely, and that's the danger.** Earliest-start failed 7.3% of random inputs and shortest-first only **1.3%**. A handful of hand-made tests could easily miss shortest-first's flaw. The oracle found both, and the shrinker reduced each to three intervals: `[[2,3), [1,2), [0,3)]` (earliest start takes `[0,3)` and blocks both others) and `[[2,4), [0,3), [3,5)]` (shortest first takes `[2,4)`, which overlaps both of the pair that would have fit). Earliest finish passed all 20,000, as the exchange argument predicts.
* **Meeting rooms:** sorting starts first at equal times was wrong in 31% of random inputs, minimal case `[[0,2), [2,3)]`: 2 rooms instead of 1.
* **Regret matters in 3% of inputs:** take-if-fits was right 19,399 times out of 20,000. A three-course sample would probably pass, which is why the proof, not the sample, is the evidence.
* **Matroid greedy with DSU slots:** 20,000/20,000 against exhaustive search with Hall's condition as the feasibility test.
* **Not a matroid, no greedy:** heaviest-first failed 7.7% of weighted inputs; the DP passed all of them.
* **Java and C++ agree exactly**, after one detail. Java's `List.sort` is a **stable** merge sort, while C++ `std::sort` is not stable. Greedy results depend on the order of tied elements (two courses with the same deadline), so the C++ listing uses `std::ranges::stable_sort` throughout. That's an L7 observation in its own right: *"the tie order of the sort is part of the algorithm's output contract."*

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads book rooms concurrently"

Greedy scheduling becomes **concurrent allocation**: a booking service that must never double-book.

* **Per-resource serialization:** each room's calendar is guarded by its own lock, or owned by a single-writer partition. A booking checks for overlap in an ordered map of intervals (`floorEntry`/`ceilingEntry`, O(log n)) and inserts under the same lock. That is the check-then-act pattern that must be atomic.
* **Optimistic concurrency** for low contention: read the room's version, compute, then commit with a compare-and-set on the version (or a conditional write in the database). Retry on conflict.
* **"Any free room" requests** shouldn't lock all rooms. Keep a concurrent free-room index (a heap of rooms keyed by next-free time) whose pop-and-reserve is atomic, or shard rooms and let each shard answer independently.
* **The DSU slot allocator** used for job sequencing can be made lock-free: `find` with path halving and a CAS to claim a slot. Folder 04 measures a CAS-based DSU.

### 4.2 Extension B — "intervals arrive as a stream"

* **Unweighted interval scheduling online, arrivals sorted by start:** keep only the last chosen interval. When a new interval overlaps it and **ends earlier**, replace it: an exchange step done online. Memory O(1), and the result equals the offline earliest-finish answer. That is the regret idea with a heap of size one.
* **Meeting rooms over a stream sorted by start:** a min-heap of current end times; its maximum size is the answer. Memory is O(max concurrent meetings), not O(total meetings).
* **Course schedule III** needs deadline order. If input arrives in arbitrary order, it must be buffered or sorted externally (Folder 07) first. Say so; don't pretend the regret heap works on unsorted streams.
* **Weighted problems** generally have no bounded-memory exact online algorithm. The honest answer is buffering, or an approximation with a stated competitive ratio.

### 4.3 Extension C — "jobs are spread over 16 shards"

**The matroid merge property:** an element that is not in a shard's optimal (maximum-weight) basis is spanned by heavier elements of that shard, so it can never be in the global optimum. Each shard can therefore run the greedy locally and ship **only its chosen elements**, and the coordinator runs the same greedy on the union. The result is exactly the global optimum. Measured with 16 shards × 2,000 jobs and 200 slots: global optimum 199,349,408; greedy over the union of local optima **199,349,408**, from shipping 3,200 of 32,000 jobs (10%). Adding up the local profits instead claims 3,036,195,552, which is **infeasible**: every shard used the same 200 slots.

The same property is why distributed minimum spanning tree works by computing local spanning forests and merging them (the graphic matroid), and why top-k merges exactly (the uniform matroid, Folder 01 File 1). The L7 sentence: *"if the feasibility structure is a matroid, shards can pre-select locally without losing optimality; if it's not, like weighted intervals, I need a different decomposition, such as DP over time ranges with boundary states."*

For **meeting rooms across shards** (rooms partitioned, meetings global), the overlap at time t is the sum of per-shard overlaps at t. Each shard emits its sorted event stream, and the coordinator sweeps a k-way merge of those streams (Folder 01 File 3's merge iterator).

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Unproven greedy order | Wrong on 1–8% of inputs; passes samples | Exchange argument aloud; random oracle + shrink before trusting |
| F2 | No regret step | Suboptimal on rare inputs (LC 630: 3%) | Take, then evict the worst via a heap when infeasible |
| F3 | Interval semantics unstated | Off-by-one rooms on touching intervals | Half-open vs closed in the contract; sweep tie order follows |
| F4 | Greedy on a non-matroid | Heavy element blocks better combinations | Recognize the missing exchange property; DP |
| F5 | Unstable sort where ties matter | Results differ between languages, libraries and runs | Total order or a stable sort, stated |
| F6 | Recursive DSU find | Stack overflow on long chains | Iterative, with path halving |
| F7 | Check-then-act booking without atomicity | Double booking under concurrency | Per-resource lock, single writer, or CAS on a version |
| F8 | Summing local optima across shards | Infeasible "solution" (3.0×10⁹ vs 2.0×10⁸) | Merge local *selections*, re-run greedy; matroids only |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Why earliest finish time and not earliest start?"</b></summary>

**Initial Prompt.** Maximum non-overlapping meetings.

**L5 Answer.** "Earliest finish leaves the most room afterwards."

**Why L5 Stalls.** Correct intuition, but not a proof, and the candidate can't say why earliest start fails.

**L7 Answer.** "Exchange argument: take any optimal schedule. Its first meeting ends no earlier than the earliest-finishing meeting, so I can swap it in without conflicting with the rest. Same size, still feasible; induct on what's left. Earliest start fails because the earliest-starting meeting can be long: `[0,3)` blocks `[1,2)` and `[2,3)`. That's the smallest counterexample the random oracle found."
</details>

<details><summary><b>Q2 · "How would you convince yourself a greedy is correct if you can't prove it in the interview?"</b></summary>

**Initial Prompt.** A novel scheduling problem.

**L5 Answer.** "I'd try a few examples."

**Why L5 Stalls.** Wrong greedies are wrong rarely. Shortest-first failed only 1.3% of random inputs; hand-picked examples won't find it.

**L7 Answer.** "Write an exponential brute force over subsets for n ≤ 8 and compare on tens of thousands of random small instances. If it disagrees, shrink to a minimal counterexample, which usually shows *why* the greedy is wrong. If it never disagrees, I look for the exchange argument with more confidence. Earliest-start, shortest-first and heaviest-first all fail within a few thousand trials and shrink to three intervals."
</details>

<details><summary><b>Q3 · "Course Schedule III: your greedy takes a course if it fits. Correct?"</b></summary>

**Initial Prompt.** LeetCode 630.

**L5 Answer.** "Yes, sorting by deadline is optimal for feasibility."

**Why L5 Stalls.** Sorting by deadline decides *order*, not *selection*. Take-if-fits never revisits a long course taken early. Minimal counterexample: `[(1,6), (1,6), (5,5), (1,5)]`, 2 instead of 3.

**L7 Answer.** "Process by deadline, always take, and if the total exceeds the deadline, drop the longest course taken so far, with a max-heap. Among sets of the same size, the one with the smallest total time dominates for the future, and dropping the longest keeps the count while minimizing time. O(n log n). The same regret-through-a-heap pattern solves refueling stops and IPO."
</details>

<details><summary><b>Q4 · "Jobs with deadlines and profits, each takes one unit of time."</b></summary>

**Initial Prompt.** Job sequencing.

**L5 Answer.** Sort by profit, then scan backwards from each deadline for a free slot: O(n²).

**Why L5 Stalls.** Correct but quadratic, and the candidate can't say *why* profit-first is optimal.

**L7 Answer.** "Schedulable job sets form a matroid: by Hall's condition, a set is feasible iff for every t at most t jobs have deadline ≤ t, which is hereditary and has the exchange property. So greedy by profit is optimal by Rado–Edmonds. For the slot search I'd use a DSU where `find(t)` is the latest free slot ≤ t and taking slot s links it to s−1: near-linear overall, with an iterative find."
</details>

<details><summary><b>Q5 · "Same as interval scheduling, but each interval has a weight."</b></summary>

**Initial Prompt.** Weighted interval scheduling (LeetCode 1235).

**L5 Answer.** "Heaviest first, then earliest finish among those that fit."

**Why L5 Stalls.** Not a matroid, so no greedy order is safe. Minimal counterexample: `[0,2)` with weight 7 blocks `[0,1)` (6) + `[1,2)` (2) = 8.

**L7 Answer.** "Weights break the exchange property: two short intervals can beat one heavy long one. So DP. Sort by end; `dp[i] = max(dp[i−1], w_i + dp[p(i)])`, where `p(i)` is the number of intervals ending at or before interval i's start, found by binary search. O(n log n), with reconstruction by walking back through the choices."
</details>

<details><summary><b>Q6 · "Meeting rooms: [9,10) and [10,11) — one room or two?"</b></summary>

**Initial Prompt.** LeetCode 253 with touching intervals.

**L5 Answer.** Sorts all events by time and gets 2 or 1 depending on how ties fell.

**Why L5 Stalls.** The answer depends on interval semantics, which weren't established. Measured, the starts-first tie order was wrong in 31% of random inputs.

**L7 Answer.** "Meetings are half-open: one ending at 10 frees the room for one starting at 10. So at equal times the sweep processes ends before starts. I'd make that explicit in the comparator and test `[[0,2),[2,3)]`, expecting 1. If the spec said closed intervals, I'd flip the tie order."
</details>

<details><summary><b>Q7 · "The jobs are spread over 16 data centres. Global optimum?"</b></summary>

**Initial Prompt.** Extension C for job sequencing.

**L5 Answer.** "Each data centre schedules its own jobs; add up the profits."

**Why L5 Stalls.** Every data centre used the same time slots, so the sum is infeasible. Measured: 3.0×10⁹ claimed vs 2.0×10⁸ achievable.

**L7 Answer.** "Because it's a matroid, a job a shard rejects can never be in the global optimum: it's dominated by heavier jobs in the same shard. So each shard runs the greedy locally and ships only its selected jobs, at most the number of slots, and the coordinator re-runs the greedy on the union. That's provably exact. I measured it shipping 10% of the jobs. The same reasoning is why distributed MST merges local spanning forests."
</details>

<details><summary><b>Q8 · "Bookings arrive from many clients at once."</b></summary>

**Initial Prompt.** Extension A for room booking.

**L5 Answer.** "Check availability, then insert."

**Why L5 Stalls.** Check-then-act without atomicity double-books under concurrency.

**L7 Answer.** "The overlap check and the insert must be one atomic step per room. I'd keep an ordered interval map per room under that room's lock, or give each room a single owner thread. For a database-backed version, a conditional write on a version number with retries. For 'any free room', a concurrent index of rooms by next-free time with an atomic pop-and-reserve, so requests don't lock every room."
</details>

---

## 7. Checklist

* [ ] Before coding a greedy: state the exchange argument, or "stays ahead", in two sentences.
* [ ] If unsure: brute force on n ≤ 8, random inputs, shrink. Trust the oracle over intuition.
* [ ] Check the matroid properties (hereditary + exchange). If they fail, consider DP.
* [ ] Regret pattern when a later item can make an earlier choice wrong: take, then evict via a heap.
* [ ] Interval semantics (half-open/closed) → sweep tie order.
* [ ] Stable sort or a total order when ties change the result.
* [ ] DSU: iterative find, path halving, union by size where relevant.
* [ ] Extension A: atomic check-and-reserve per resource; optimistic versions.
* [ ] Extension B: online exchange (keep the earlier-ending interval); heaps sized by concurrency, not by input.
* [ ] Extension C: matroid → merge local selections exactly; otherwise decompose by time with boundary state.

---

## 8. References

* J. Edmonds, *Matroids and the greedy algorithm*, Mathematical Programming 1, 1971 — DOI 10.1007/BF01584082
* J. Kleinberg, É. Tardos, *Algorithm Design* (2005): chapter 4, greedy algorithms ("stays ahead", exchange arguments); chapter 6.1, weighted interval scheduling.
* T. H. Cormen, C. E. Leiserson, R. L. Rivest, C. Stein, *Introduction to Algorithms*, 4th ed. (2022): greedy algorithms and matroids (task scheduling with deadlines).
* LeetCode anchors: [435 Non-overlapping Intervals](https://leetcode.com/problems/non-overlapping-intervals/), [253 Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/), [630 Course Schedule III](https://leetcode.com/problems/course-schedule-iii/), [871 Minimum Number of Refueling Stops](https://leetcode.com/problems/minimum-number-of-refueling-stops/), [502 IPO](https://leetcode.com/problems/ipo/), [1235 Maximum Profit in Job Scheduling](https://leetcode.com/problems/maximum-profit-in-job-scheduling/)
* Java SE 21 API, `List.sort` (stable) — <https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/List.html>; cppreference `std::stable_sort` — <https://en.cppreference.com/w/cpp/algorithm/stable_sort>

*Folder 02:* [01 — two pointers and window invariants](01-two-pointers-and-non-shrinkable-sliding-window-invariants.md) · [02 — monotonic stack and deque](02-monotonic-stack-and-deque-submatrix-histograms-and-window-extrema.md)
