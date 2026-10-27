# P11 · Splitwise: Exact Splits, a Group Ledger Readers Can Trust, and Minimum-Transfer Settlement

> **Folder 05 · Problem 11 of 20.** Splitwise looks like CRUD. The L7 core is three precise claims:
> 1. **Every split sums to the total, to the cent.** That rules out `double`, and rules out rounding each share on its own.
> 2. **Every reader sees balances that sum to zero.** Per-key atomic maps don't give you that.
> 3. **"Simplify debts" is a real algorithm.** The greedy heap everyone writes is not always minimal, and the exact minimum is NP-hard in general.
>
> All three claims are measured below in Java and C++.
>
> **Listing pair P11:** `SplitwiseLedger.java` / `splitwise_ledger.cpp`. Sections 1, 2, 5 and 5b are deterministic and **byte-identical across Java, GCC and Clang**; section 4 shows one measured run per build.

---

## 1. Problem and scope

**Functional:**
- Groups of members.
- Expenses split four ways: **Equal**, **Exact** amounts, **Percent** (up to 4 decimals) or **Shares** (weights).
- Net balances per member.
- A **settle-up plan**: who pays whom, as few transfers as possible.

**Non-functional:**
- Many devices add expenses to the same group concurrently.
- Balances are read far more often than they are written.
- Money is exact.

**Out of scope here:**
- Multi-currency (§7).
- Expense edits (§7, as reversal entries).
- Idempotent retries. [P13](03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md) builds the idempotency-key state machine; P11 reuses the idea.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Money | `record Money(BigDecimal amount)`, compact constructor `setScale(2, UNNECESSARY)` | `i64` cents; `parse_fixed(s, 2)` returns `std::expected` |
| Split | `sealed interface Split permits Equal, Exact, Percent, Shares` | `std::variant<Equal, Exact, Percent, Shares>` |
| Validated result | `sealed Allocation permits Allocated, Rejected` | `std::expected<std::map<user, cents>, std::string>` |
| Ledger | `interface Balances` with three implementations; `record Group(members, balances)` | the same, with `SnapshotCell<T>` |
| Settlement | `record Transfer(from, to, cents)`; `greedy`, `exactMin`, `cancelCycles` | the same |

**Invariants:**
- **I1:** an `Allocated` sums to the expense total exactly. `Group.addExpense` accepts *only* an `Allocation`, so an unvalidated split cannot reach a ledger.
- **I2:** money has exactly 2 decimals. `"10.005"` is rejected, never rounded. Percentages have at most 4 decimals and sum to exactly 100.
- **I3:** within a group, `Σ net == 0` in **every state any reader can observe**, not just at quiescence.
- **I4:** no lost updates. Final balances equal the sum of all accepted deltas.
- **I5:** a settlement plan, applied to the balances, brings every member to zero.

**How the types enforce it.** Splitting is a pure function, `allocate(Money, Split) → Allocation`, and runs outside any atomic section. Only the resulting **delta vector** is applied atomically. The split's arithmetic never sits inside a lock or a CAS retry loop.

## 3. Concurrency and contention analysis

### 3.1 Exactness first: the arithmetic

**Largest remainder (Hamilton) in integer cents:**
1. Every split type reduces to integer weights. Equal is all 1s; Percent is 4-decimal fixed point, with 100% = 1,000,000.
2. Take `floor(t·w/W)` for each member.
3. Hand the leftover cents, one each, to the largest remainders, breaking ties by user id.

The sum is exact by construction, and the result is deterministic and order-independent.

**Measured over 100,000 random equal/shares splits:** rounding each share on its own (`HALF_EVEN`) drifted in **62,750** splits, by up to 4 cents. Largest remainder drifted in **0**. `0.02` split three ways shows the drift goes *both* ways: round-each charges `0.03`.

**Why HALF_EVEN, measured** over 1,000,000 line items at 7.5% tax, rounded to the cent per line:

| Rounding | Total error |
|---|---|
| `DOWN` (what a `(long)` cast does) | **−$4,877.69** |
| `HALF_UP` | **+$129.97** (ties always round up: 1 in 40 items is an exact tie here) |
| `HALF_EVEN` | **+$5.29** (noise) |

So use HALF_EVEN where rounding is unavoidable (tax, FX, interest), and **apportionment** where parts must sum to a whole.

**Traps the validator catches (section 3 of the listings):**
- `new BigDecimal("100.00").equals(BigDecimal.valueOf(100))` is **false**, because `equals` compares scale. Use `compareTo`.
- `BigDecimal.divide(3)` without a scale throws *"Non-terminating decimal expansion"*.
- `0.1 + 0.2 == 0.30000000000000004`.
- A percentage with 5 decimals is rejected, not rounded.

### 3.2 The ledger: where threads collide

All expenses in a group hit the same few balance cells. The invariant `Σ net == 0` **spans keys**, so per-key atomicity can't protect it.

**8 threads × 50,000 expenses into one 6-member group, with an auditor summing balances concurrently:**

| Implementation | Members wrong at end | Final Σ | Audits that saw Σ ≠ 0 |
|---|---|---|---|
| CHM `get()` then `put()` / relaxed `load()` + `store()` | **6 of 6** (Java, GCC, Clang) | −6,523.47 / −7,916.18 / +2,090.43 | ≈ all |
| CHM `merge()` / `fetch_add()` per member | 0 | 0.00 | **359,132 of 533,227 / 186,562 of 456,671 / 179,688 of 395,470** |
| CAS on an immutable snapshot | 0 | 0.00 | **0** of 4,437,474 / 456,479 / 290,664 |

- **`merge()` fixes lost updates but not torn reads.** An expense is 2–7 separate per-key updates, so a reader between them sees money that exists nowhere. A settle-up plan computed from that read is wrong: it doesn't sum to zero.
- **The group is the consistency boundary.** The `Snapshots` ledger publishes an immutable state `(version, net[])` through `AtomicReference.compareAndSet`:
  - a writer copies the array, adds the delta and CASes, retrying on conflict;
  - a reader does one volatile load and gets a whole number of expenses, with no lock;
  - the copy costs O(members), trivial for groups of ≤ 50.
- **Cost:** 343,262 CAS retries for 400,000 expenses (Java) under deliberately extreme contention. Retries are cheap because the allocation was done *before* the loop: only an array copy and an add are retried.
- **C++:** `std::atomic<std::shared_ptr<const State>>` where available. libstdc++ 16 provides it, but `is_lock_free()` is **false**; measured here, 1,449,544 retries. libc++ as packaged here lacks it, so `SnapshotCell` falls back to a mutex-guarded pointer with the same load / compare-exchange contract.
- **The C++ "naive" row uses relaxed atomics on purpose.** A plain `std::map` written from 8 threads is a data race, which is undefined behaviour, so nothing could be measured. Atomics make the lost update well-defined and countable.
- **When a group is hot** (a 500-person office pool), the trade-off flips. Use a per-group lock with mutable arrays and readers copying under the lock. Or go **event-sourced**: an append-only expense log with idempotency keys, plus a materialized balance view rebuilt at a version. The version doubles as an optimistic-concurrency ETag for clients.

### 3.3 Settling up: three algorithms, three products

| Strategy | Trip example | 2,000 random groups, random cents | 2,000 groups, round amounts between couples |
|---|---|---|---|
| Pairwise debts, netted per pair | 6 | 23.09 avg | 17.87 avg |
| + **cycle cancellation** (only existing pairs pay each other) | **4** | 19.21 avg | 13.85 avg |
| **Greedy heap** (largest debtor pays largest creditor) | 5 | 6.08 avg | 5.52 avg |
| **Exact minimum** (zero-sum subgroups) | **4** | 6.08 avg (greedy above it in 4 of 2,000) | 5.32 avg (greedy above it in **377 of 2,000**, by up to 2) |

- **Exact minimum:** with k non-zero balances, min transfers = `k − (max number of disjoint zero-sum groups)`. Each zero-sum group of size s settles in s−1 transfers. `dp[mask] = max_i dp[mask∖i] + [Σmask = 0]` runs in O(2ᵏ·k), so it's fine to k ≈ 20.
- **Why it's NP-hard.** "Can we do better than k−1?" is exactly "does a proper, non-empty zero-sum subset exist?", and that is **subset sum**. So above roughly 20 members, use greedy (≤ k−1 transfers, usually optimal on irregular amounts) or an ILP.
- **Greedy fails on round numbers.** With irregular cents, zero-sum subgroups almost never exist, so greedy is optimal 99.8% of the time. With round amounts between couples they're common, and greedy loses 19% of the time.
- **Cycle cancellation** answers a different product requirement: *"don't make me pay a stranger."* Each cycle cancelled removes at least one edge, and every member's net is preserved (asserted in 5b). But a DAG can still have O(n²) edges, so it's ~3× the minimum on random data. Offer both modes and let the user choose.

## 4. Java 21 implementation

```java
// SplitwiseLedger.java - P11: exact splits (BigDecimal + largest remainder), CAS-published group ledger, min-cash-flow settlement
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.SortedMap;
import java.util.StringJoiner;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.stream.IntStream;

public final class SplitwiseLedger {

    static final BigDecimal HUNDRED = BigDecimal.valueOf(100);

    /** Exactly two decimals. "10.005" throws: an amount is rejected, never silently rounded. */
    record Money(BigDecimal amount) {
        Money {
            amount = amount.setScale(2, RoundingMode.UNNECESSARY);
        }

        static Money of(String s) {
            return new Money(new BigDecimal(s));
        }

        static Money ofCents(long cents) {
            return new Money(BigDecimal.valueOf(cents, 2));
        }

        long cents() {
            return amount.movePointRight(2).longValueExact();
        }

        @Override
        public String toString() {
            return amount.toPlainString();
        }
    }

    sealed interface Split permits Equal, Exact, Percent, Shares {}
    record Equal(List<String> users) implements Split {}
    record Exact(Map<String, Money> legs) implements Split {}
    record Percent(Map<String, BigDecimal> percents) implements Split {}
    record Shares(Map<String, Long> weights) implements Split {}

    /** The only way an expense reaches a ledger: an Allocated always sums to the expense total. */
    sealed interface Allocation permits Allocated, Rejected {}

    record Allocated(SortedMap<String, Long> cents) implements Allocation {
        Allocated {
            cents = Collections.unmodifiableSortedMap(new TreeMap<>(cents));
        }

        @Override
        public String toString() {
            StringJoiner j = new StringJoiner(" ");
            cents.forEach((u, c) -> j.add(u + " " + Money.ofCents(c)));
            return j + " = " + Money.ofCents(cents.values().stream().mapToLong(Long::longValue).sum());
        }
    }

    record Rejected(String reason) implements Allocation {
        @Override
        public String toString() {
            return "Rejected: " + reason;
        }
    }

    static Allocation allocate(Money total, Split split) {
        long t = total.cents();
        if (t <= 0) return new Rejected("total must be positive");
        return switch (split) {
            case Equal e -> equal(t, e.users());
            case Exact e -> exact(t, new TreeMap<>(e.legs()));
            case Percent p -> percent(t, new TreeMap<>(p.percents()));
            case Shares s -> weighted(t, new TreeMap<>(s.weights()));
        };
    }

    static Allocation equal(long t, List<String> users) {
        if (users.isEmpty() || new HashSet<>(users).size() != users.size()) return new Rejected("equal split needs distinct users");
        TreeMap<String, Long> w = new TreeMap<>();
        for (String u : users) w.put(u, 1L);
        return weighted(t, w);
    }

    static Allocation exact(long t, SortedMap<String, Money> legs) {
        long sum = 0;
        for (Money m : legs.values()) {
            if (m.cents() < 0) return new Rejected("exact legs must not be negative");
            sum += m.cents();
        }
        if (sum != t) return new Rejected("exact legs sum to " + Money.ofCents(sum) + ", total is " + Money.ofCents(t));
        TreeMap<String, Long> out = new TreeMap<>();
        legs.forEach((u, m) -> out.put(u, m.cents()));
        return new Allocated(out);
    }

    static Allocation percent(long t, SortedMap<String, BigDecimal> pct) {
        BigDecimal sum = pct.values().stream().reduce(BigDecimal.ZERO, BigDecimal::add);
        if (sum.compareTo(HUNDRED) != 0)                          // compareTo, not equals: 100.00 does not equals(100)
            return new Rejected("percentages sum to " + sum.stripTrailingZeros().toPlainString() + ", not 100");
        TreeMap<String, Long> w = new TreeMap<>();
        for (var e : pct.entrySet()) {
            BigDecimal p = e.getValue();
            if (p.signum() <= 0) return new Rejected("percentage " + p.toPlainString() + " must be positive");
            if (p.stripTrailingZeros().scale() > 4) return new Rejected("percentage " + p.toPlainString() + " has more than 4 decimals");
            w.put(e.getKey(), p.movePointRight(4).longValueExact());   // fixed point: 100% = 1,000,000
        }
        return weighted(t, w);
    }

    /**
     * Largest-remainder (Hamilton) apportionment in integer cents: floor every exact share t*w/W, then give the
     * leftover cents, one each, to the largest remainders (ties by user id). The shares always sum to exactly t.
     */
    static Allocation weighted(long t, SortedMap<String, Long> weights) {
        if (weights.isEmpty()) return new Rejected("no participants");
        long sumW = 0;
        for (long w : weights.values()) {
            if (w <= 0) return new Rejected("share weights must be positive");
            sumW += w;
        }
        record Part(String user, long floor, long rem) {}
        List<Part> parts = new ArrayList<>();
        long given = 0;
        for (var e : weights.entrySet()) {
            long num = Math.multiplyExact(t, e.getValue());       // exact integer math: no double, no division by 3.0
            parts.add(new Part(e.getKey(), num / sumW, num % sumW));
            given += num / sumW;
        }
        parts.sort(Comparator.comparingLong(Part::rem).reversed().thenComparing(Part::user));
        TreeMap<String, Long> out = new TreeMap<>();
        for (int i = 0; i < parts.size(); i++) out.put(parts.get(i).user(), parts.get(i).floor() + (i < t - given ? 1 : 0));
        return new Allocated(out);
    }

    /** What most first drafts do: compute each share and round it on its own (HALF_EVEN). The parts drift. */
    static long naiveSum(Money total, Split split) {
        BigDecimal t = total.amount();
        List<BigDecimal> parts = switch (split) {
            case Equal e -> Collections.nCopies(e.users().size(), t.divide(BigDecimal.valueOf(e.users().size()), 2, RoundingMode.HALF_EVEN));
            case Percent p -> p.percents().values().stream().map(x -> t.multiply(x).divide(HUNDRED, 2, RoundingMode.HALF_EVEN)).toList();
            case Shares s -> {
                BigDecimal w = BigDecimal.valueOf(s.weights().values().stream().mapToLong(Long::longValue).sum());
                yield s.weights().values().stream().map(x -> t.multiply(BigDecimal.valueOf(x)).divide(w, 2, RoundingMode.HALF_EVEN)).toList();
            }
            case Exact e -> e.legs().values().stream().map(Money::amount).toList();
        };
        return parts.stream().reduce(BigDecimal.ZERO, BigDecimal::add).movePointRight(2).longValueExact();
    }

    // ---- the group ledger: net balance per member (positive = is owed); every reader must be able to rely on sum == 0

    interface Balances {
        void apply(long[] delta);

        long[] read();
    }

    /** CHM, but get() then put(): two writers read the same old value and one update is lost. */
    static final class GetThenPut implements Balances {
        final List<String> members;
        final ConcurrentHashMap<String, Long> net = new ConcurrentHashMap<>();

        GetThenPut(List<String> members) {
            this.members = members;
            members.forEach(m -> net.put(m, 0L));
        }

        @Override
        public void apply(long[] d) {
            for (int i = 0; i < d.length; i++)
                if (d[i] != 0) net.put(members.get(i), net.get(members.get(i)) + d[i]);
        }

        @Override
        public long[] read() {
            return members.stream().mapToLong(net::get).toArray();
        }
    }

    /** CHM.merge per member: no lost updates, but one expense touches several keys, so a reader can see half of it. */
    static final class MergePerKey implements Balances {
        final List<String> members;
        final ConcurrentHashMap<String, Long> net = new ConcurrentHashMap<>();

        MergePerKey(List<String> members) {
            this.members = members;
            members.forEach(m -> net.put(m, 0L));
        }

        @Override
        public void apply(long[] d) {
            for (int i = 0; i < d.length; i++)
                if (d[i] != 0) net.merge(members.get(i), d[i], Long::sum);
        }

        @Override
        public long[] read() {
            return members.stream().mapToLong(net::get).toArray();
        }
    }

    /** Copy-on-write snapshot published by CAS: a reader sees a whole number of expenses, without taking a lock. */
    static final class Snapshots implements Balances {
        record State(long version, long[] net) {}                  // net is never written after publication
        final AtomicReference<State> state;
        final LongAdder retries = new LongAdder();

        Snapshots(int members) {
            state = new AtomicReference<>(new State(0, new long[members]));
        }

        @Override
        public void apply(long[] d) {
            for (;;) {
                State cur = state.get();
                long[] next = cur.net().clone();
                for (int i = 0; i < d.length; i++) next[i] += d[i];
                if (state.compareAndSet(cur, new State(cur.version() + 1, next))) return;
                retries.increment();
            }
        }

        @Override
        public long[] read() {
            return state.get().net();
        }
    }

    /** The split is computed outside any atomic section; only the resulting delta is applied atomically. */
    record Group(List<String> members, Balances balances) {
        Allocation addExpense(String payer, Money total, Split split) {
            Allocation a = allocate(total, split);
            if (!(a instanceof Allocated(var cents))) return a;
            if (!members.contains(payer) || !members.containsAll(cents.keySet())) return new Rejected("not a group member");
            long[] d = new long[members.size()];
            d[members.indexOf(payer)] += total.cents();
            cents.forEach((u, c) -> d[members.indexOf(u)] -= c);
            balances.apply(d);
            return a;
        }
    }

    // ---- settling up

    record Transfer(int from, int to, long cents) {}
    record Expense(int payer, long cents, int[] among) {}          // equal split among members, by index

    /** Greedy min cash flow: the largest debtor pays the largest creditor. At most n-1 transfers; not always minimal. */
    static List<Transfer> greedy(long[] net) {
        // heap entries {amount, index}: largest amount first, then lowest index (the same tie-break as the C++ listing)
        Comparator<long[]> order = (a, b) -> a[0] != b[0] ? Long.compare(b[0], a[0]) : Long.compare(a[1], b[1]);
        PriorityQueue<long[]> cred = new PriorityQueue<>(order), debt = new PriorityQueue<>(order);
        for (int i = 0; i < net.length; i++) {
            if (net[i] > 0) cred.add(new long[]{net[i], i});
            if (net[i] < 0) debt.add(new long[]{-net[i], i});
        }
        List<Transfer> out = new ArrayList<>();
        while (!cred.isEmpty()) {
            long[] c = cred.poll(), d = debt.poll();
            long x = Math.min(c[0], d[0]);
            out.add(new Transfer((int) d[1], (int) c[1], x));
            if (c[0] > x) cred.add(new long[]{c[0] - x, c[1]});
            if (d[0] > x) debt.add(new long[]{d[0] - x, d[1]});
        }
        return out;
    }

    /**
     * Exact minimum: with k non-zero balances, min transfers = k - (max number of disjoint zero-sum groups).
     * dp[mask] = max over members i of dp[mask - i] + (sum(mask) == 0). O(2^k * k): fine to k ~ 20 (NP-hard in general).
     */
    static List<Transfer> exactMin(long[] net) {
        int[] idx = IntStream.range(0, net.length).filter(i -> net[i] != 0).toArray();
        int k = idx.length, full = (1 << k) - 1;
        long[] sum = new long[full + 1];
        int[] dp = new int[full + 1];
        for (int m = 1; m <= full; m++) {
            sum[m] = sum[m & (m - 1)] + net[idx[Integer.numberOfTrailingZeros(m)]];
            int best = 0;
            for (int b = m; b != 0; b &= b - 1) best = Math.max(best, dp[m & ~(b & -b)]);
            dp[m] = best + (sum[m] == 0 ? 1 : 0);
        }
        // Walk back one member at a time along an optimal path; each time the remaining set sums to 0,
        // the members removed since the previous such point form a zero-sum group: settle it with k-1 transfers.
        List<Transfer> out = new ArrayList<>();
        List<Integer> group = new ArrayList<>();
        for (int m = full; m != 0; ) {
            int z = sum[m] == 0 ? 1 : 0, pick = 0;
            for (int b = m; b != 0; b &= b - 1)
                if (dp[m & ~(b & -b)] + z == dp[m]) {
                    pick = b & -b;
                    break;
                }
            group.add(idx[Integer.numberOfTrailingZeros(pick)]);
            m &= ~pick;
            if (sum[m] == 0) {
                long[] g = new long[net.length];
                for (int i : group) g[i] = net[i];
                out.addAll(greedy(g));
                group.clear();
            }
        }
        return out;
    }

    /** owe[u][v] > 0: u owes v. Repeatedly finds a cycle and subtracts its smallest edge (>= 1 edge disappears). */
    static int cancelCycles(long[][] owe) {
        int cancelled = 0;
        for (List<Integer> c; (c = findCycle(owe)) != null; cancelled++) {
            long min = Long.MAX_VALUE;
            for (int i = 0; i < c.size(); i++) min = Math.min(min, owe[c.get(i)][c.get((i + 1) % c.size())]);
            for (int i = 0; i < c.size(); i++) owe[c.get(i)][c.get((i + 1) % c.size())] -= min;
        }
        return cancelled;
    }

    static List<Integer> findCycle(long[][] owe) {
        int[] color = new int[owe.length];                         // 0 unvisited, 1 on the DFS path, 2 finished
        for (int s = 0; s < owe.length; s++) {
            if (color[s] != 0) continue;
            List<Integer> c = dfs(s, owe, color, new ArrayList<>());
            if (c != null) return c;
        }
        return null;
    }

    static List<Integer> dfs(int u, long[][] owe, int[] color, List<Integer> path) {
        color[u] = 1;
        path.add(u);
        for (int v = 0; v < owe.length; v++) {
            if (owe[u][v] == 0) continue;
            if (color[v] == 1) return new ArrayList<>(path.subList(path.indexOf(v), path.size()));
            if (color[v] == 0) {
                List<Integer> c = dfs(v, owe, color, path);
                if (c != null) return c;
            }
        }
        color[u] = 2;
        path.remove(path.size() - 1);
        return null;
    }

    static long[] sharesOf(List<String> names, Expense e) {
        TreeMap<String, Long> w = new TreeMap<>();
        for (int i : e.among()) w.put(names.get(i), 1L);
        long[] s = new long[names.size()];
        if (weighted(e.cents(), w) instanceof Allocated(var cents)) cents.forEach((u, c) -> s[names.indexOf(u)] = c);
        return s;
    }

    static long[] netOf(List<String> names, List<Expense> expenses) {
        long[] net = new long[names.size()];
        for (Expense e : expenses) {
            long[] s = sharesOf(names, e);
            net[e.payer()] += e.cents();
            for (int i = 0; i < net.length; i++) net[i] -= s[i];
        }
        return net;
    }

    /** Who actually paid for whom, netted per pair (ann owes bob 10, bob owes ann 4 -> ann owes bob 6). */
    static long[][] pairwise(List<String> names, List<Expense> expenses) {
        int n = names.size();
        long[][] owe = new long[n][n];
        for (Expense e : expenses) {
            long[] s = sharesOf(names, e);
            for (int i = 0; i < n; i++)
                if (i != e.payer()) owe[i][e.payer()] += s[i];
        }
        for (int u = 0; u < n; u++)
            for (int v = u + 1; v < n; v++) {
                long d = owe[u][v] - owe[v][u];
                owe[u][v] = Math.max(d, 0);
                owe[v][u] = Math.max(-d, 0);
            }
        return owe;
    }

    static List<Transfer> edges(long[][] owe) {
        List<Transfer> out = new ArrayList<>();
        for (int u = 0; u < owe.length; u++)
            for (int v = 0; v < owe.length; v++)
                if (owe[u][v] > 0) out.add(new Transfer(u, v, owe[u][v]));
        return out;
    }

    static boolean settles(long[] net, List<Transfer> plan) {
        long[] left = net.clone();
        for (Transfer t : plan) {
            left[t.from()] += t.cents();
            left[t.to()] -= t.cents();
        }
        return IntStream.range(0, left.length).allMatch(i -> left[i] == 0);
    }

    static String show(List<String> names, List<Transfer> plan) {
        StringJoiner j = new StringJoiner(", ", "[", "]");
        for (Transfer t : plan) j.add(names.get(t.from()) + "->" + names.get(t.to()) + " " + Money.ofCents(t.cents()));
        return j.toString();
    }

    record Study(long pairwise, long cancelled, long greedy, long exact, int greedyAbove, int maxGap, boolean invariantsHold) {}

    static Study study(long seed, boolean roundAmounts) {
        Rng r = new Rng(seed);
        long pw = 0, cc = 0, gr = 0, ex = 0;
        int above = 0, gap = 0;
        boolean ok = true;
        for (int g = 0; g < 2_000; g++) {
            int n = 4 + r.below(7);
            List<String> names = IntStream.range(0, n).mapToObj(i -> "m" + i).toList();
            List<Expense> expenses = new ArrayList<>();
            for (int k = 0; k < 3 * n; k++) {
                int payer = r.below(n);
                int size = roundAmounts ? 2 : 2 + r.below(n - 1);
                List<Integer> pool = new ArrayList<>(IntStream.range(0, n).boxed().toList());
                int[] among = new int[size];
                for (int j = 0; j < size; j++) among[j] = pool.remove(r.below(pool.size()));
                long cents = roundAmounts ? 1_000L * (1 + r.below(10)) : 1 + r.below(20_000);
                expenses.add(new Expense(payer, cents, among));
            }
            long[] net = netOf(names, expenses);
            long[][] owe = pairwise(names, expenses);
            int p = edges(owe).size();
            cancelCycles(owe);
            List<Transfer> cancelled = edges(owe), greedy = greedy(net), exact = exactMin(net);
            ok &= settles(net, cancelled) && settles(net, greedy) && settles(net, exact) && exact.size() <= greedy.size()
                    && exact.size() <= cancelled.size();
            pw += p;
            cc += cancelled.size();
            gr += greedy.size();
            ex += exact.size();
            if (greedy.size() > exact.size()) above++;
            gap = Math.max(gap, greedy.size() - exact.size());
        }
        return new Study(pw, cc, gr, ex, above, gap, ok);
    }

    static String avg(long total) {
        return BigDecimal.valueOf(total * 100 / 2_000, 2).toPlainString();
    }

    // ---- harness

    static long mix64(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    static final class Rng {
        private long s;

        Rng(long seed) {
            s = seed;
        }

        int below(int n) {
            return (int) Long.remainderUnsigned(mix64(s++), n);
        }
    }

    record Gen(String payer, Money total, Split split) {}

    static Gen nextExpense(Rng r, List<String> m) {
        String payer = m.get(r.below(m.size()));
        int k = 2 + r.below(m.size() - 1);
        List<String> pool = new ArrayList<>(m), chosen = new ArrayList<>();
        for (int j = 0; j < k; j++) chosen.add(pool.remove(r.below(pool.size())));
        Money total = Money.ofCents(1 + r.below(10_000));
        if (r.below(4) == 0) {
            TreeMap<String, Long> w = new TreeMap<>();
            for (String u : chosen) w.put(u, 1L + r.below(3));
            return new Gen(payer, total, new Shares(w));
        }
        return new Gen(payer, total, new Equal(chosen));
    }

    static BigDecimal bd(String s) {
        return new BigDecimal(s);
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Splits always sum to the total: largest remainder in integer cents ==");
        List<String> abc = List.of("ann", "bob", "cat");
        record Case(String label, Money total, Split split) {}
        List<Case> cases = List.of(
                new Case("100.00 equal among ann, bob, cat", Money.of("100.00"), new Equal(abc)),
                new Case("10.00 at 33.3333 / 33.3333 / 33.3334 %", Money.of("10.00"),
                        new Percent(Map.of("ann", bd("33.3333"), "bob", bd("33.3333"), "cat", bd("33.3334")))),
                new Case("0.10 in shares 2 : 1 : 1", Money.of("0.10"), new Shares(Map.of("ann", 2L, "bob", 1L, "cat", 1L))),
                new Case("0.02 equal among ann, bob, cat", Money.of("0.02"), new Equal(abc)));
        List<Allocation> results = new ArrayList<>();
        for (Case c : cases) {
            Allocation a = allocate(c.total(), c.split());
            results.add(a);
            System.out.printf("  %-40s -> %s | round each share: %s%n", c.label(), a, Money.ofCents(naiveSum(c.total(), c.split())));
        }
        Rng r1 = new Rng(11);
        int naiveDrift = 0, maxDrift = 0, lrDrift = 0;
        for (int i = 0; i < 100_000; i++) {
            int n = 2 + r1.below(7);
            Money total = Money.ofCents(1 + r1.below(100_000));
            List<String> users = IntStream.range(0, n).mapToObj(j -> "u" + j).toList();
            Split s;
            if (r1.below(2) == 0) {
                s = new Equal(users);
            } else {
                TreeMap<String, Long> w = new TreeMap<>();
                for (String u : users) w.put(u, 1L + r1.below(5));
                s = new Shares(w);
            }
            long drift = Math.abs(naiveSum(total, s) - total.cents());
            if (drift != 0) naiveDrift++;
            maxDrift = (int) Math.max(maxDrift, drift);
            if (!(allocate(total, s) instanceof Allocated(var cents)) || cents.values().stream().mapToLong(Long::longValue).sum() != total.cents())
                lrDrift++;
        }
        System.out.printf("  100000 random equal/shares splits: round-each drifted in %d (max %d cents) | largest remainder drifted in %d%n",
                naiveDrift, maxDrift, lrDrift);

        System.out.println("== 2. Why HALF_EVEN: 1,000,000 line items, 7.5% tax, each rounded to the cent ==");
        Rng r2 = new Rng(77);
        BigDecimal rate = new BigDecimal("0.075");
        RoundingMode[] modes = {RoundingMode.DOWN, RoundingMode.HALF_UP, RoundingMode.HALF_EVEN};
        String[] modeNames = {"DOWN (what a (long) cast does)", "HALF_UP (school rounding)", "HALF_EVEN (banker's rounding)"};
        long exactMilli = 0;                                        // thousandths of a cent
        long[] rounded = new long[3];
        for (int i = 0; i < 1_000_000; i++) {
            long price = 1 + r2.below(100_000);
            BigDecimal tax = BigDecimal.valueOf(price).multiply(rate);   // exact, in cents with 3 decimals
            exactMilli += price * 75;
            for (int m = 0; m < 3; m++) rounded[m] += tax.setScale(0, modes[m]).longValueExact();
        }
        System.out.printf("  exact tax total %s dollars%n", BigDecimal.valueOf(exactMilli, 5).toPlainString());
        long[] bias = new long[3];
        for (int m = 0; m < 3; m++) {
            bias[m] = rounded[m] * 1_000 - exactMilli;
            System.out.printf("  %-32s total off by %s dollars%n", modeNames[m], BigDecimal.valueOf(bias[m], 5).toPlainString());
        }

        System.out.println("== 3. Validation: illegal splits never reach a ledger ==");
        Money hundred = Money.of("100.00");
        Allocation v1 = allocate(hundred, new Percent(Map.of("ann", bd("33.33"), "bob", bd("33.33"), "cat", bd("33.33"))));
        System.out.println("  percent 33.33 + 33.33 + 33.33        -> " + v1);
        BigDecimal fifty = bd("50.00").add(bd("50"));
        Allocation v2 = allocate(hundred, new Percent(Map.of("ann", bd("50.00"), "bob", bd("50"))));
        System.out.printf("  percent 50.00 + 50: sum %s; equals(100) %b, compareTo(100) == 0 %b -> %s%n", fifty.toPlainString(),
                fifty.equals(HUNDRED), fifty.compareTo(HUNDRED) == 0, v2);
        Allocation v3 = allocate(hundred, new Exact(Map.of("ann", Money.of("60.00"), "bob", Money.of("30.00"))));
        System.out.println("  exact 60.00 + 30.00 of 100.00        -> " + v3);
        Allocation v4 = allocate(hundred, new Percent(Map.of("ann", bd("12.34567"), "bob", bd("87.65433"))));
        System.out.println("  percent 12.34567 + 87.65433          -> " + v4);
        Allocation v5 = allocate(Money.of("9.00"), new Shares(Map.of("ann", 0L, "bob", 3L)));
        System.out.println("  shares ann 0 : bob 3                 -> " + v5);
        boolean moneyRejected = false;
        try {
            Money.of("10.005");
        } catch (ArithmeticException e) {
            moneyRejected = true;
            System.out.println("  Money.of(\"10.005\")                   -> ArithmeticException: " + e.getMessage() + " (rejected, never rounded)");
        }
        try {
            System.out.println("  100.00 / 3 = " + bd("100.00").divide(BigDecimal.valueOf(3)));
        } catch (ArithmeticException e) {
            System.out.println("  new BigDecimal(\"100.00\").divide(3)   -> ArithmeticException: " + e.getMessage());
        }

        List<String> six = List.of("ann", "bob", "cat", "dan", "eve", "fay");
        System.out.println("== 4. 8 threads x 50,000 expenses into one 6-member group; an auditor sums the balances meanwhile ==");
        Balances[] impls = {new GetThenPut(six), new MergePerKey(six), new Snapshots(6)};
        String[] implNames = {"CHM get() then put()", "CHM merge() per member", "CAS on an immutable snapshot"};
        long[] wrong = new long[3], finalSum = new long[3], torn = new long[3], audits = new long[3];
        for (int k = 0; k < 3; k++) {
            Group g = new Group(six, impls[k]);
            long[][] expected = new long[8][6];
            CyclicBarrier start = new CyclicBarrier(10);
            CountDownLatch writersDone = new CountDownLatch(8), auditorDone = new CountDownLatch(1);
            AtomicBoolean writing = new AtomicBoolean(true);
            AtomicReference<Exception> failure = new AtomicReference<>();
            long[] seen = new long[2];                              // written by the auditor only; read after auditorDone
            for (int t = 0; t < 8; t++) {
                final int id = t;
                Thread.ofPlatform().start(() -> {
                    try {
                        start.await();
                        Rng r = new Rng(1_000 + id);
                        for (int i = 0; i < 50_000; i++) {
                            Gen e = nextExpense(r, six);
                            if (g.addExpense(e.payer(), e.total(), e.split()) instanceof Allocated(var cents)) {
                                expected[id][six.indexOf(e.payer())] += e.total().cents();
                                cents.forEach((u, c) -> expected[id][six.indexOf(u)] -= c);
                            }
                        }
                    } catch (Exception e) {
                        failure.compareAndSet(null, e);
                    } finally {
                        writersDone.countDown();
                    }
                });
            }
            final Balances b = impls[k];
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    while (writing.get()) {
                        long s = 0;
                        for (long x : b.read()) s += x;
                        seen[0]++;
                        if (s != 0) seen[1]++;
                    }
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                } finally {
                    auditorDone.countDown();
                }
            });
            start.await();
            writersDone.await();
            writing.set(false);
            auditorDone.await();
            if (failure.get() != null) throw new IllegalStateException(failure.get());
            long[] fin = b.read();
            for (int i = 0; i < 6; i++) {
                long want = 0;
                for (long[] e : expected) want += e[i];
                if (fin[i] != want) wrong[k]++;
                finalSum[k] += fin[i];
            }
            audits[k] = seen[0];
            torn[k] = seen[1];
            System.out.printf("  %-30s members wrong %d of 6 | final sum %s | audits that saw sum != 0: %d of %d%s%n", implNames[k], wrong[k],
                    Money.ofCents(finalSum[k]), torn[k], audits[k], b instanceof Snapshots sn ? " | CAS retries " + sn.retries.sum() : "");
        }

        System.out.println("== 5. Settling a trip: 7 equal-split expenses among ann, bob, cat, dan, eve, fay ==");
        List<Expense> trip = List.of(
                new Expense(5, 6_000, new int[]{5, 1}),             // fay paid 60.00 for fay, bob
                new Expense(2, 4_000, new int[]{2, 0}),             // cat paid 40.00 for cat, ann
                new Expense(3, 4_000, new int[]{3, 0}),             // dan paid 40.00 for dan, ann
                new Expense(4, 4_000, new int[]{4, 0}),             // eve paid 40.00 for eve, ann
                new Expense(0, 2_000, new int[]{0, 1}),             // ann paid 20.00 for ann, bob
                new Expense(1, 2_000, new int[]{1, 2}),             // bob paid 20.00 for bob, cat
                new Expense(2, 2_000, new int[]{2, 0}));            // cat paid 20.00 for cat, ann
        long[] net = netOf(six, trip);
        StringJoiner nj = new StringJoiner(" ");
        for (int i = 0; i < 6; i++) nj.add(six.get(i) + " " + Money.ofCents(net[i]));
        System.out.println("  net balances: " + nj + " (sum " + Money.ofCents(IntStream.range(0, 6).mapToLong(i -> net[i]).sum()) + ")");
        long[][] owe = pairwise(six, trip);
        List<Transfer> pairs = edges(owe);
        System.out.printf("  %-47s %d transfers %s%n", "pairwise debts, netted per pair:", pairs.size(), show(six, pairs));
        int cycles = cancelCycles(owe);
        List<Transfer> cancelled = edges(owe);
        System.out.printf("  %-47s %d transfers %s%n", "+ cycle cancellation (" + cycles + " cycle, existing pairs):", cancelled.size(), show(six, cancelled));
        List<Transfer> greedyPlan = greedy(net), exactPlan = exactMin(net);
        System.out.printf("  %-47s %d transfers %s%n", "greedy heap (largest pays largest):", greedyPlan.size(), show(six, greedyPlan));
        System.out.printf("  %-47s %d transfers %s%n", "exact minimum (zero-sum subgroups):", exactPlan.size(), show(six, exactPlan));

        System.out.println("== 5b. 2,000 random groups of 4-10 people, 3n expenses each: average transfers to settle ==");
        Study cents = study(21, false), round = study(22, true);
        for (Study s : List.of(cents, round))
            System.out.printf("  %-34s pairwise %s | cycle-cancelled %s | greedy %s | exact %s | greedy above minimum in %d of 2000 (max +%d)%n",
                    s == cents ? "random cents, 2..n people each:" : "round 10..100.00, 2 people each:", avg(s.pairwise()), avg(s.cancelled()),
                    avg(s.greedy()), avg(s.exact()), s.greedyAbove(), s.maxGap());

        boolean ok = results.stream().allMatch(a -> a instanceof Allocated) && lrDrift == 0
                && results.get(0) instanceof Allocated(var c0) && c0.get("ann") == 3_334
                && results.get(1) instanceof Allocated(var c1) && c1.get("cat") == 334
                && results.get(2) instanceof Allocated(var c2) && c2.get("bob") == 3
                && bias[1] > 0 && Math.abs(bias[2]) < bias[1] && bias[0] < 0
                && v1 instanceof Rejected && v2 instanceof Allocated && v3 instanceof Rejected && v4 instanceof Rejected
                && v5 instanceof Rejected && moneyRejected
                && wrong[1] == 0 && finalSum[1] == 0 && wrong[2] == 0 && finalSum[2] == 0 && torn[2] == 0
                && pairs.size() == 6 && cancelled.size() == 4 && greedyPlan.size() == 5 && exactPlan.size() == 4
                && settles(net, cancelled) && settles(net, greedyPlan) && settles(net, exactPlan)
                && cents.invariantsHold() && round.invariantsHold();
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1–3, 5, 5b deterministic; section 4 one measured run):**

```text
== 1. Splits always sum to the total: largest remainder in integer cents ==
  100.00 equal among ann, bob, cat         -> ann 33.34 bob 33.33 cat 33.33 = 100.00 | round each share: 99.99
  10.00 at 33.3333 / 33.3333 / 33.3334 %   -> ann 3.33 bob 3.33 cat 3.34 = 10.00 | round each share: 9.99
  0.10 in shares 2 : 1 : 1                 -> ann 0.05 bob 0.03 cat 0.02 = 0.10 | round each share: 0.09
  0.02 equal among ann, bob, cat           -> ann 0.01 bob 0.01 cat 0.00 = 0.02 | round each share: 0.03
  100000 random equal/shares splits: round-each drifted in 62750 (max 4 cents) | largest remainder drifted in 0
== 2. Why HALF_EVEN: 1,000,000 line items, 7.5% tax, each rounded to the cent ==
  exact tax total 37500495.92700 dollars
  DOWN (what a (long) cast does)   total off by -4877.68700 dollars
  HALF_UP (school rounding)        total off by 129.97300 dollars
  HALF_EVEN (banker's rounding)    total off by 5.29300 dollars
== 3. Validation: illegal splits never reach a ledger ==
  percent 33.33 + 33.33 + 33.33        -> Rejected: percentages sum to 99.99, not 100
  percent 50.00 + 50: sum 100.00; equals(100) false, compareTo(100) == 0 true -> ann 50.00 bob 50.00 = 100.00
  exact 60.00 + 30.00 of 100.00        -> Rejected: exact legs sum to 90.00, total is 100.00
  percent 12.34567 + 87.65433          -> Rejected: percentage 12.34567 has more than 4 decimals
  shares ann 0 : bob 3                 -> Rejected: share weights must be positive
  Money.of("10.005")                   -> ArithmeticException: Rounding necessary (rejected, never rounded)
  new BigDecimal("100.00").divide(3)   -> ArithmeticException: Non-terminating decimal expansion; no exact representable decimal result.
== 4. 8 threads x 50,000 expenses into one 6-member group; an auditor sums the balances meanwhile ==
  CHM get() then put()           members wrong 6 of 6 | final sum -6523.47 | audits that saw sum != 0: 568723 of 573314
  CHM merge() per member         members wrong 0 of 6 | final sum 0.00 | audits that saw sum != 0: 359132 of 533227
  CAS on an immutable snapshot   members wrong 0 of 6 | final sum 0.00 | audits that saw sum != 0: 0 of 4437474 | CAS retries 343262
== 5. Settling a trip: 7 equal-split expenses among ann, bob, cat, dan, eve, fay ==
  net balances: ann -60.00 bob -30.00 cat 20.00 dan 20.00 eve 20.00 fay 30.00 (sum 0.00)
  pairwise debts, netted per pair:                6 transfers [ann->cat 30.00, ann->dan 20.00, ann->eve 20.00, bob->ann 10.00, bob->fay 30.00, cat->bob 10.00]
  + cycle cancellation (1 cycle, existing pairs): 4 transfers [ann->cat 20.00, ann->dan 20.00, ann->eve 20.00, bob->fay 30.00]
  greedy heap (largest pays largest):             5 transfers [ann->fay 30.00, ann->cat 20.00, bob->dan 20.00, ann->eve 10.00, bob->eve 10.00]
  exact minimum (zero-sum subgroups):             4 transfers [ann->cat 20.00, ann->dan 20.00, ann->eve 20.00, bob->fay 30.00]
== 5b. 2,000 random groups of 4-10 people, 3n expenses each: average transfers to settle ==
  random cents, 2..n people each:    pairwise 23.09 | cycle-cancelled 19.21 | greedy 6.08 | exact 6.08 | greedy above minimum in 4 of 2000 (max +1)
  round 10..100.00, 2 people each:   pairwise 17.87 | cycle-cancelled 13.85 | greedy 5.52 | exact 5.32 | greedy above minimum in 377 of 2000 (max +2)
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// splitwise_ledger.cpp - P11: exact splits in integer cents (largest remainder), CAS-published group ledger, min-cash-flow settlement
#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <cstdint>
#include <cstdio>
#include <expected>
#include <format>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <print>
#include <queue>
#include <string>
#include <string_view>
#include <thread>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using u32 = std::uint32_t;
using sz = std::size_t;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

/** v / 10^dp printed with exactly dp decimals: fixed(-1234, 2) == "-12.34". */
std::string fixed(i64 v, int dp) {
    u64 p = 1;
    for (int i = 0; i < dp; ++i) p *= 10;
    const u64 a = v < 0 ? 0 - static_cast<u64>(v) : static_cast<u64>(v);
    std::string s = std::format("{}{}", v < 0 ? "-" : "", a / p);
    if (dp > 0) s += std::format(".{:0{}}", a % p, dp);
    return s;
}
std::string money(i64 cents) { return fixed(cents, 2); }
std::string trim_zeros(std::string s) {
    if (s.find('.') == std::string::npos) return s;
    while (s.back() == '0') s.pop_back();
    if (s.back() == '.') s.pop_back();
    return s;
}

/** "12.34" -> 1234 at dp = 2. More decimals than dp is an error, never a rounding (no double anywhere). */
std::expected<i64, std::string> parse_fixed(std::string_view s, int dp, std::string_view what) {
    i64 v = 0;
    int decimals = -1;
    if (s.empty()) return std::unexpected(std::format("empty {}", what));
    for (const char ch : s) {
        if (ch == '.' && decimals < 0) { decimals = 0; continue; }
        if (ch < '0' || ch > '9') return std::unexpected(std::format("{} {} is not a plain decimal", what, s));
        if (decimals >= 0 && ++decimals > dp) return std::unexpected(std::format("{} {} has more than {} decimals", what, s, dp));
        v = v * 10 + (ch - '0');
    }
    for (int i = std::max(decimals, 0); i < dp; ++i) v *= 10;
    return v;
}

struct Equal { std::vector<std::string> users; };
struct Exact { std::map<std::string, i64> legs; };                // cents
struct Percent { std::map<std::string, std::string> percents; };  // as received, e.g. "33.3333"
struct Shares { std::map<std::string, i64> weights; };
using Split = std::variant<Equal, Exact, Percent, Shares>;

/** The only way an expense reaches a ledger: a value always sums to the expense total; an error is a reason. */
using Allocation = std::expected<std::map<std::string, i64>, std::string>;
Allocation reject(std::string why) { return std::unexpected(std::move(why)); }

std::string to_string(const Allocation& a) {
    if (!a) return "Rejected: " + a.error();
    std::string s;
    i64 sum = 0;
    for (const auto& [u, c] : *a) {
        s += std::format("{}{} {}", s.empty() ? "" : " ", u, money(c));
        sum += c;
    }
    return s + " = " + money(sum);
}

/**
 * Largest-remainder (Hamilton) apportionment in integer cents: floor every exact share t*w/W, then give the
 * leftover cents, one each, to the largest remainders (ties by user id). The shares always sum to exactly t.
 */
Allocation weighted(i64 t, const std::map<std::string, i64>& weights) {
    if (weights.empty()) return reject("no participants");
    i64 sum_w = 0;
    for (const auto& [u, w] : weights) {
        if (w <= 0) return reject("share weights must be positive");
        sum_w += w;
    }
    struct Part { std::string user; i64 floor, rem; };
    std::vector<Part> parts;
    i64 given = 0;
    for (const auto& [u, w] : weights) {
        if (t > std::numeric_limits<i64>::max() / w) return reject("amount too large");
        const i64 num = t * w;
        parts.push_back({u, num / sum_w, num % sum_w});
        given += num / sum_w;
    }
    std::ranges::sort(parts, [](const Part& a, const Part& b) { return a.rem != b.rem ? a.rem > b.rem : a.user < b.user; });
    std::map<std::string, i64> out;
    for (sz i = 0; i < parts.size(); ++i) out[parts[i].user] = parts[i].floor + (static_cast<i64>(i) < t - given ? 1 : 0);
    return out;
}

/** Equal, Percent and Shares all reduce to integer weights (percent as 4-decimal fixed point, 100% = 1,000,000). */
std::expected<std::map<std::string, i64>, std::string> weights_of(const Split& split) {
    return std::visit(overloaded{
        [](const Equal& e) -> std::expected<std::map<std::string, i64>, std::string> {
            std::map<std::string, i64> w;
            for (const auto& u : e.users) w[u] = 1;
            if (e.users.empty() || w.size() != e.users.size()) return std::unexpected(std::string("equal split needs distinct users"));
            return w;
        },
        [](const Percent& p) -> std::expected<std::map<std::string, i64>, std::string> {
            std::map<std::string, i64> w;
            i64 sum = 0;
            for (const auto& [u, s] : p.percents) {
                auto v = parse_fixed(s, 4, "percentage");
                if (!v) return std::unexpected(v.error());
                if (*v == 0) return std::unexpected(std::format("percentage {} must be positive", s));
                w[u] = *v;
                sum += *v;
            }
            if (sum != 1'000'000) return std::unexpected(std::format("percentages sum to {}, not 100", trim_zeros(fixed(sum, 4))));
            return w;
        },
        [](const Shares& s) -> std::expected<std::map<std::string, i64>, std::string> { return s.weights; },
        [](const Exact&) -> std::expected<std::map<std::string, i64>, std::string> { return std::unexpected(std::string("exact has no weights")); },
    }, split);
}

Allocation allocate(i64 total, const Split& split) {
    if (total <= 0) return reject("total must be positive");
    if (const auto* e = std::get_if<Exact>(&split)) {
        i64 sum = 0;
        for (const auto& [u, c] : e->legs) {
            if (c < 0) return reject("exact legs must not be negative");
            sum += c;
        }
        if (sum != total) return reject(std::format("exact legs sum to {}, total is {}", money(sum), money(total)));
        return e->legs;
    }
    auto w = weights_of(split);
    if (!w) return reject(w.error());
    return weighted(total, *w);
}

/** HALF_EVEN of num / den for num >= 0, den > 0: exactly RoundingMode.HALF_EVEN. */
i64 div_half_even(i64 num, i64 den) {
    const i64 q = num / den, r = num % den;
    return 2 * r > den || (2 * r == den && q % 2 == 1) ? q + 1 : q;
}

/** What most first drafts do: compute each share and round it on its own (HALF_EVEN). The parts drift. */
i64 naive_sum(i64 total, const Split& split) {
    if (const auto* e = std::get_if<Exact>(&split)) {
        i64 s = 0;
        for (const auto& [u, c] : e->legs) s += c;
        return s;
    }
    const auto w = weights_of(split);
    i64 sum_w = 0, s = 0;
    for (const auto& [u, x] : *w) sum_w += x;
    for (const auto& [u, x] : *w) s += div_half_even(total * x, sum_w);
    return s;
}

// ---- the group ledger: net balance per member (positive = is owed); every reader must be able to rely on sum == 0

struct Balances {
    virtual ~Balances() = default;
    virtual void apply(const std::vector<i64>& delta) = 0;
    virtual std::vector<i64> read() const = 0;
};

/** The get()-then-put() race. A plain map here would be a data race (UB); relaxed atomics make the lost update measurable. */
struct LoadThenStore final : Balances {
    std::vector<std::atomic<i64>> net;
    explicit LoadThenStore(sz n) : net(n) {}
    void apply(const std::vector<i64>& d) override {
        for (sz i = 0; i < d.size(); ++i)
            if (d[i] != 0) net[i].store(net[i].load(std::memory_order_relaxed) + d[i], std::memory_order_relaxed);
    }
    std::vector<i64> read() const override {
        std::vector<i64> r;
        for (const auto& x : net) r.push_back(x.load());
        return r;
    }
};

/** fetch_add per member: no lost updates, but one expense touches several members, so a reader can see half of it. */
struct FetchAddPerKey final : Balances {
    std::vector<std::atomic<i64>> net;
    explicit FetchAddPerKey(sz n) : net(n) {}
    void apply(const std::vector<i64>& d) override {
        for (sz i = 0; i < d.size(); ++i)
            if (d[i] != 0) net[i].fetch_add(d[i]);
    }
    std::vector<i64> read() const override {
        std::vector<i64> r;
        for (const auto& x : net) r.push_back(x.load());
        return r;
    }
};

/**
 * An immutable snapshot behind load / compare-exchange. libstdc++ has std::atomic<std::shared_ptr>; libc++ as packaged
 * here does not, so the fallback guards the pointer with a mutex. Same contract: a reader gets a whole snapshot.
 */
template <class T> class SnapshotCell {
#if defined(__cpp_lib_atomic_shared_ptr)
    std::atomic<std::shared_ptr<const T>> p_;
public:
    static constexpr const char* kind = "std::atomic<shared_ptr>";
    explicit SnapshotCell(std::shared_ptr<const T> init) : p_(std::move(init)) {}
    std::shared_ptr<const T> load() const { return p_.load(); }
    bool cas(std::shared_ptr<const T>& expected, std::shared_ptr<const T> next) { return p_.compare_exchange_strong(expected, std::move(next)); }
#else
    mutable std::mutex m_;
    std::shared_ptr<const T> p_;
public:
    static constexpr const char* kind = "mutex-guarded shared_ptr";
    explicit SnapshotCell(std::shared_ptr<const T> init) : p_(std::move(init)) {}
    std::shared_ptr<const T> load() const { std::scoped_lock l(m_); return p_; }
    bool cas(std::shared_ptr<const T>& expected, std::shared_ptr<const T> next) {
        std::scoped_lock l(m_);
        if (p_ != expected) { expected = p_; return false; }
        p_ = std::move(next);
        return true;
    }
#endif
};

/** Copy-on-write snapshot published by CAS: readers always see a whole number of expenses. */
struct Snapshots final : Balances {
    struct State { i64 version; std::vector<i64> net; };
    SnapshotCell<State> cell;
    std::atomic<u64> retries{0};
    explicit Snapshots(sz n) : cell(std::make_shared<const State>(State{0, std::vector<i64>(n)})) {}
    void apply(const std::vector<i64>& d) override {
        auto cur = cell.load();
        for (;;) {
            auto next = std::make_shared<State>(State{cur->version + 1, cur->net});
            for (sz i = 0; i < d.size(); ++i) next->net[i] += d[i];
            if (cell.cas(cur, std::move(next))) return;  // on failure cur now holds the newer snapshot
            retries.fetch_add(1, std::memory_order_relaxed);
        }
    }
    std::vector<i64> read() const override { return cell.load()->net; }
};

sz index_of(const std::vector<std::string>& v, const std::string& x) {
    return static_cast<sz>(std::ranges::find(v, x) - v.begin());
}

/** The split is computed outside any atomic section; only the resulting delta is applied atomically. */
struct Group {
    std::vector<std::string> members;
    Balances& balances;
    Allocation add_expense(const std::string& payer, i64 total, const Split& split) {
        auto a = allocate(total, split);
        if (!a) return a;
        if (index_of(members, payer) == members.size()) return reject("not a group member");
        for (const auto& [u, c] : *a)
            if (index_of(members, u) == members.size()) return reject("not a group member");
        std::vector<i64> d(members.size());
        d[index_of(members, payer)] += total;
        for (const auto& [u, c] : *a) d[index_of(members, u)] -= c;
        balances.apply(d);
        return a;
    }
};

// ---- settling up

struct Transfer { sz from, to; i64 cents; };
struct Expense { sz payer; i64 cents; std::vector<sz> among; };  // equal split among members, by index

/** Greedy min cash flow: the largest debtor pays the largest creditor. At most n-1 transfers; not always minimal. */
std::vector<Transfer> greedy(const std::vector<i64>& net) {
    using E = std::pair<i64, sz>;  // (amount, index): largest amount first, then lowest index (same tie-break as Java)
    auto lower = [](const E& a, const E& b) { return a.first != b.first ? a.first < b.first : a.second > b.second; };
    std::priority_queue<E, std::vector<E>, decltype(lower)> cred(lower), debt(lower);
    for (sz i = 0; i < net.size(); ++i) {
        if (net[i] > 0) cred.push({net[i], i});
        if (net[i] < 0) debt.push({-net[i], i});
    }
    std::vector<Transfer> out;
    while (!cred.empty()) {
        const E c = cred.top(), d = debt.top();
        cred.pop();
        debt.pop();
        const i64 x = std::min(c.first, d.first);
        out.push_back({d.second, c.second, x});
        if (c.first > x) cred.push({c.first - x, c.second});
        if (d.first > x) debt.push({d.first - x, d.second});
    }
    return out;
}

/**
 * Exact minimum: with k non-zero balances, min transfers = k - (max number of disjoint zero-sum groups).
 * dp[mask] = max over members i of dp[mask - i] + (sum(mask) == 0). O(2^k * k): fine to k ~ 20 (NP-hard in general).
 */
std::vector<Transfer> exact_min(const std::vector<i64>& net) {
    std::vector<sz> idx;
    for (sz i = 0; i < net.size(); ++i)
        if (net[i] != 0) idx.push_back(i);
    const u32 full = (1u << idx.size()) - 1;
    std::vector<i64> sum(full + 1);
    std::vector<int> dp(full + 1);
    for (u32 m = 1; m <= full; ++m) {
        sum[m] = sum[m & (m - 1)] + net[idx[static_cast<sz>(std::countr_zero(m))]];
        int best = 0;
        for (u32 b = m; b != 0; b &= b - 1) best = std::max(best, dp[m & ~(b & (0u - b))]);
        dp[m] = best + (sum[m] == 0 ? 1 : 0);
    }
    // Walk back one member at a time along an optimal path; each time the remaining set sums to 0,
    // the members removed since the previous such point form a zero-sum group: settle it with k-1 transfers.
    std::vector<Transfer> out;
    std::vector<sz> group;
    for (u32 m = full; m != 0;) {
        const int z = sum[m] == 0 ? 1 : 0;
        u32 pick = 0;
        for (u32 b = m; b != 0; b &= b - 1)
            if (dp[m & ~(b & (0u - b))] + z == dp[m]) {
                pick = b & (0u - b);
                break;
            }
        group.push_back(idx[static_cast<sz>(std::countr_zero(pick))]);
        m &= ~pick;
        if (sum[m] == 0) {
            std::vector<i64> g(net.size());
            for (const sz i : group) g[i] = net[i];
            for (const auto& t : greedy(g)) out.push_back(t);
            group.clear();
        }
    }
    return out;
}

using Owe = std::vector<std::vector<i64>>;  // owe[u][v] > 0: u owes v

bool dfs(sz u, const Owe& owe, std::vector<int>& color, std::vector<sz>& path, std::vector<sz>& cycle) {
    color[u] = 1;  // 0 unvisited, 1 on the DFS path, 2 finished
    path.push_back(u);
    for (sz v = 0; v < owe.size(); ++v) {
        if (owe[u][v] == 0) continue;
        if (color[v] == 1) {
            cycle.assign(std::ranges::find(path, v), path.end());
            return true;
        }
        if (color[v] == 0 && dfs(v, owe, color, path, cycle)) return true;
    }
    color[u] = 2;
    path.pop_back();
    return false;
}

/** Repeatedly finds a cycle and subtracts its smallest edge (at least one edge disappears each time). */
int cancel_cycles(Owe& owe) {
    int cancelled = 0;
    for (;;) {
        std::vector<int> color(owe.size());
        std::vector<sz> path, c;
        bool found = false;
        for (sz s = 0; s < owe.size() && !found; ++s)
            if (color[s] == 0) found = dfs(s, owe, color, path, c);
        if (!found) return cancelled;
        i64 min = std::numeric_limits<i64>::max();
        for (sz i = 0; i < c.size(); ++i) min = std::min(min, owe[c[i]][c[(i + 1) % c.size()]]);
        for (sz i = 0; i < c.size(); ++i) owe[c[i]][c[(i + 1) % c.size()]] -= min;
        ++cancelled;
    }
}

std::vector<i64> shares_of(const std::vector<std::string>& names, const Expense& e) {
    std::map<std::string, i64> w;
    for (const sz i : e.among) w[names[i]] = 1;
    std::vector<i64> s(names.size());
    if (const auto a = weighted(e.cents, w))
        for (const auto& [u, c] : *a) s[index_of(names, u)] = c;
    return s;
}

std::vector<i64> net_of(const std::vector<std::string>& names, const std::vector<Expense>& expenses) {
    std::vector<i64> net(names.size());
    for (const auto& e : expenses) {
        const auto s = shares_of(names, e);
        net[e.payer] += e.cents;
        for (sz i = 0; i < net.size(); ++i) net[i] -= s[i];
    }
    return net;
}

/** Who actually paid for whom, netted per pair (ann owes bob 10, bob owes ann 4 -> ann owes bob 6). */
Owe pairwise(const std::vector<std::string>& names, const std::vector<Expense>& expenses) {
    const sz n = names.size();
    Owe owe(n, std::vector<i64>(n));
    for (const auto& e : expenses) {
        const auto s = shares_of(names, e);
        for (sz i = 0; i < n; ++i)
            if (i != e.payer) owe[i][e.payer] += s[i];
    }
    for (sz u = 0; u < n; ++u)
        for (sz v = u + 1; v < n; ++v) {
            const i64 d = owe[u][v] - owe[v][u];
            owe[u][v] = std::max<i64>(d, 0);
            owe[v][u] = std::max<i64>(-d, 0);
        }
    return owe;
}

std::vector<Transfer> edges(const Owe& owe) {
    std::vector<Transfer> out;
    for (sz u = 0; u < owe.size(); ++u)
        for (sz v = 0; v < owe.size(); ++v)
            if (owe[u][v] > 0) out.push_back({u, v, owe[u][v]});
    return out;
}

bool settles(std::vector<i64> net, const std::vector<Transfer>& plan) {
    for (const auto& t : plan) {
        net[t.from] += t.cents;
        net[t.to] -= t.cents;
    }
    return std::ranges::all_of(net, [](i64 x) { return x == 0; });
}

std::string show(const std::vector<std::string>& names, const std::vector<Transfer>& plan) {
    std::string s = "[";
    for (const auto& t : plan) s += std::format("{}{}->{} {}", s.size() > 1 ? ", " : "", names[t.from], names[t.to], money(t.cents));
    return s + "]";
}

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

struct Rng {
    u64 s;
    int below(int n) { return static_cast<int>(mix64(s++) % static_cast<u64>(n)); }
    sz below(sz n) { return static_cast<sz>(mix64(s++) % n); }
};

struct Study { i64 pairwise = 0, cancelled = 0, greedy = 0, exact = 0; int greedy_above = 0, max_gap = 0; bool invariants_hold = true; };

Study study(u64 seed, bool round_amounts) {
    Rng r{seed};
    Study st;
    for (int g = 0; g < 2'000; ++g) {
        const sz n = 4 + r.below(sz{7});
        std::vector<std::string> names;
        for (sz i = 0; i < n; ++i) names.push_back(std::format("m{}", i));
        std::vector<Expense> expenses;
        for (sz k = 0; k < 3 * n; ++k) {
            const sz payer = r.below(n);
            const sz size = round_amounts ? 2 : 2 + r.below(n - 1);
            std::vector<sz> pool, among;
            for (sz i = 0; i < n; ++i) pool.push_back(i);
            for (sz j = 0; j < size; ++j) {
                const sz at = r.below(pool.size());
                among.push_back(pool[at]);
                pool.erase(pool.begin() + static_cast<std::ptrdiff_t>(at));
            }
            const i64 cents = round_amounts ? 1'000 * (1 + r.below(10)) : 1 + r.below(20'000);
            expenses.push_back({payer, cents, among});
        }
        const auto net = net_of(names, expenses);
        auto owe = pairwise(names, expenses);
        const auto p = static_cast<i64>(edges(owe).size());
        cancel_cycles(owe);
        const auto cancelled = edges(owe), gr = greedy(net), ex = exact_min(net);
        st.invariants_hold = st.invariants_hold && settles(net, cancelled) && settles(net, gr) && settles(net, ex) && ex.size() <= gr.size() &&
                             ex.size() <= cancelled.size();
        st.pairwise += p;
        st.cancelled += static_cast<i64>(cancelled.size());
        st.greedy += static_cast<i64>(gr.size());
        st.exact += static_cast<i64>(ex.size());
        if (gr.size() > ex.size()) ++st.greedy_above;
        st.max_gap = std::max(st.max_gap, static_cast<int>(gr.size() - ex.size()));
    }
    return st;
}

std::string avg(i64 total) { return fixed(total * 100 / 2'000, 2); }

struct Gen { std::string payer; i64 total; Split split; };

Gen next_expense(Rng& r, const std::vector<std::string>& m) {
    std::string payer = m[r.below(m.size())];
    const sz k = 2 + r.below(m.size() - 1);
    std::vector<std::string> pool = m, chosen;
    for (sz j = 0; j < k; ++j) {
        const sz at = r.below(pool.size());
        chosen.push_back(pool[at]);
        pool.erase(pool.begin() + static_cast<std::ptrdiff_t>(at));
    }
    const i64 total = 1 + r.below(10'000);
    if (r.below(4) == 0) {
        std::map<std::string, i64> w;
        for (const auto& u : chosen) w[u] = 1 + r.below(3);
        return {payer, total, Shares{w}};
    }
    return {payer, total, Equal{chosen}};
}

template <class F>
void parallel(int threads, F body) {  // spin gate with a ready count (see P6)
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {}
            body(t);
        });
    while (ready.load() < threads) {}
    go.store(true, std::memory_order_release);
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Splits always sum to the total: largest remainder in integer cents ==");
    const std::vector<std::string> abc{"ann", "bob", "cat"};
    struct Case { std::string label; i64 total; Split split; };
    const std::vector<Case> cases{
        {"100.00 equal among ann, bob, cat", 10'000, Equal{abc}},
        {"10.00 at 33.3333 / 33.3333 / 33.3334 %", 1'000, Percent{{{"ann", "33.3333"}, {"bob", "33.3333"}, {"cat", "33.3334"}}}},
        {"0.10 in shares 2 : 1 : 1", 10, Shares{{{"ann", 2}, {"bob", 1}, {"cat", 1}}}},
        {"0.02 equal among ann, bob, cat", 2, Equal{abc}},
    };
    std::vector<Allocation> results;
    for (const auto& c : cases) {
        results.push_back(allocate(c.total, c.split));
        std::println("  {:<40} -> {} | round each share: {}", c.label, to_string(results.back()), money(naive_sum(c.total, c.split)));
    }
    Rng r1{11};
    int naive_drift = 0, lr_drift = 0;
    i64 max_drift = 0;
    for (int i = 0; i < 100'000; ++i) {
        const int n = 2 + r1.below(7);
        const i64 total = 1 + r1.below(100'000);
        std::vector<std::string> users;
        for (int j = 0; j < n; ++j) users.push_back(std::format("u{}", j));
        Split s;
        if (r1.below(2) == 0) {
            s = Equal{users};
        } else {
            std::map<std::string, i64> w;
            for (const auto& u : users) w[u] = 1 + r1.below(5);
            s = Shares{w};
        }
        const i64 drift = std::abs(naive_sum(total, s) - total);
        if (drift != 0) ++naive_drift;
        max_drift = std::max(max_drift, drift);
        const auto a = allocate(total, s);
        i64 sum = 0;
        if (a)
            for (const auto& [u, c] : *a) sum += c;
        if (!a || sum != total) ++lr_drift;
    }
    std::println("  100000 random equal/shares splits: round-each drifted in {} (max {} cents) | largest remainder drifted in {}", naive_drift, max_drift,
                 lr_drift);

    std::println("== 2. Why HALF_EVEN: 1,000,000 line items, 7.5% tax, each rounded to the cent ==");
    Rng r2{77};
    const std::array<const char*, 3> mode_names{"DOWN (what a (long) cast does)", "HALF_UP (school rounding)", "HALF_EVEN (banker's rounding)"};
    i64 exact_milli = 0;  // thousandths of a cent
    std::array<i64, 3> rounded{};
    for (int i = 0; i < 1'000'000; ++i) {
        const i64 milli = (1 + r2.below(100'000)) * 75;  // price in cents * 0.075, exactly, in thousandths of a cent
        exact_milli += milli;
        rounded[0] += milli / 1'000;
        rounded[1] += (milli + 500) / 1'000;
        rounded[2] += div_half_even(milli, 1'000);
    }
    std::println("  exact tax total {} dollars", fixed(exact_milli, 5));
    std::array<i64, 3> bias{};
    for (sz m = 0; m < 3; ++m) {
        bias[m] = rounded[m] * 1'000 - exact_milli;
        std::println("  {:<32} total off by {} dollars", mode_names[m], fixed(bias[m], 5));
    }

    std::println("== 3. Validation: illegal splits never reach a ledger ==");
    const auto v1 = allocate(10'000, Percent{{{"ann", "33.33"}, {"bob", "33.33"}, {"cat", "33.33"}}});
    std::println("  percent 33.33 + 33.33 + 33.33        -> {}", to_string(v1));
    const auto v2 = allocate(10'000, Percent{{{"ann", "50.00"}, {"bob", "50"}}});
    std::println("  percent 50.00 + 50: 4-decimal fixed point {} + {} == 1000000 -> {}", *parse_fixed("50.00", 4, ""), *parse_fixed("50", 4, ""),
                 to_string(v2));
    const auto v3 = allocate(10'000, Exact{{{"ann", 6'000}, {"bob", 3'000}}});
    std::println("  exact 60.00 + 30.00 of 100.00        -> {}", to_string(v3));
    const auto v4 = allocate(10'000, Percent{{{"ann", "12.34567"}, {"bob", "87.65433"}}});
    std::println("  percent 12.34567 + 87.65433          -> {}", to_string(v4));
    const auto v5 = allocate(900, Shares{{{"ann", 0}, {"bob", 3}}});
    std::println("  shares ann 0 : bob 3                 -> {}", to_string(v5));
    const auto m6 = parse_fixed("10.005", 2, "amount");
    std::println("  parse_fixed(\"10.005\", 2)             -> {} (rejected, never rounded)", m6 ? "accepted?!" : m6.error());
    std::println("  double 0.1 + 0.2                     -> {} (why money is never a double)", 0.1 + 0.2);

    const std::vector<std::string> six{"ann", "bob", "cat", "dan", "eve", "fay"};
    std::println("== 4. 8 threads x 50,000 expenses into one 6-member group; an auditor sums the balances meanwhile ==");
    const std::array<std::string, 3> impl_names{"relaxed load() then store()", "fetch_add() per member", "CAS on an immutable snapshot"};
    std::array<i64, 3> wrong{}, final_sum{}, torn{}, audits{};
    for (sz k = 0; k < 3; ++k) {
        std::unique_ptr<Balances> b;
        if (k == 0) b = std::make_unique<LoadThenStore>(6);
        else if (k == 1) b = std::make_unique<FetchAddPerKey>(6);
        else b = std::make_unique<Snapshots>(6);
        Group g{six, *b};
        std::vector<std::array<i64, 6>> expected(8);
        std::atomic<int> writers_done{0};
        i64 seen = 0, seen_torn = 0;  // written by the auditor only; read after parallel() joins
        parallel(9, [&](int t) {
            if (t == 8) {
                while (writers_done.load() < 8) {
                    i64 s = 0;
                    for (const i64 x : b->read()) s += x;
                    ++seen;
                    if (s != 0) ++seen_torn;
                }
                return;
            }
            Rng r{1'000 + static_cast<u64>(t)};
            auto& mine = expected[static_cast<sz>(t)];
            for (int i = 0; i < 50'000; ++i) {
                const Gen e = next_expense(r, six);
                if (const auto a = g.add_expense(e.payer, e.total, e.split)) {
                    mine[index_of(six, e.payer)] += e.total;
                    for (const auto& [u, c] : *a) mine[index_of(six, u)] -= c;
                }
            }
            writers_done.fetch_add(1);
        });
        const auto fin = b->read();
        for (sz i = 0; i < 6; ++i) {
            i64 want = 0;
            for (const auto& e : expected) want += e[i];
            if (fin[i] != want) ++wrong[k];
            final_sum[k] += fin[i];
        }
        audits[k] = seen;
        torn[k] = seen_torn;
        const auto* sn = dynamic_cast<const Snapshots*>(b.get());
        std::println("  {:<30} members wrong {} of 6 | final sum {} | audits that saw sum != 0: {} of {}{}", impl_names[k], wrong[k], money(final_sum[k]),
                     torn[k], audits[k], sn ? std::format(" | CAS retries {} ({})", sn->retries.load(), SnapshotCell<Snapshots::State>::kind) : "");
    }

    std::println("== 5. Settling a trip: 7 equal-split expenses among ann, bob, cat, dan, eve, fay ==");
    const std::vector<Expense> trip{
        {5, 6'000, {5, 1}},  // fay paid 60.00 for fay, bob
        {2, 4'000, {2, 0}},  // cat paid 40.00 for cat, ann
        {3, 4'000, {3, 0}},  // dan paid 40.00 for dan, ann
        {4, 4'000, {4, 0}},  // eve paid 40.00 for eve, ann
        {0, 2'000, {0, 1}},  // ann paid 20.00 for ann, bob
        {1, 2'000, {1, 2}},  // bob paid 20.00 for bob, cat
        {2, 2'000, {2, 0}},  // cat paid 20.00 for cat, ann
    };
    const auto net = net_of(six, trip);
    std::string nets;
    i64 net_sum = 0;
    for (sz i = 0; i < 6; ++i) {
        nets += std::format("{}{} {}", i ? " " : "", six[i], money(net[i]));
        net_sum += net[i];
    }
    std::println("  net balances: {} (sum {})", nets, money(net_sum));
    auto owe = pairwise(six, trip);
    const auto pairs = edges(owe);
    std::println("  {:<47} {} transfers {}", "pairwise debts, netted per pair:", pairs.size(), show(six, pairs));
    const int cycles = cancel_cycles(owe);
    const auto cancelled = edges(owe);
    std::println("  {:<47} {} transfers {}", std::format("+ cycle cancellation ({} cycle, existing pairs):", cycles), cancelled.size(), show(six, cancelled));
    const auto greedy_plan = greedy(net), exact_plan = exact_min(net);
    std::println("  {:<47} {} transfers {}", "greedy heap (largest pays largest):", greedy_plan.size(), show(six, greedy_plan));
    std::println("  {:<47} {} transfers {}", "exact minimum (zero-sum subgroups):", exact_plan.size(), show(six, exact_plan));

    std::println("== 5b. 2,000 random groups of 4-10 people, 3n expenses each: average transfers to settle ==");
    const Study cents = study(21, false), round = study(22, true);
    for (const Study* s : {&cents, &round})
        std::println("  {:<34} pairwise {} | cycle-cancelled {} | greedy {} | exact {} | greedy above minimum in {} of 2000 (max +{})",
                     s == &cents ? "random cents, 2..n people each:" : "round 10..100.00, 2 people each:", avg(s->pairwise), avg(s->cancelled),
                     avg(s->greedy), avg(s->exact), s->greedy_above, s->max_gap);

    const bool ok = std::ranges::all_of(results, [](const Allocation& a) { return a.has_value(); }) && lr_drift == 0 && results[0]->at("ann") == 3'334 &&
                    results[1]->at("cat") == 334 && results[2]->at("bob") == 3 && bias[1] > 0 && std::abs(bias[2]) < bias[1] && bias[0] < 0 && !v1 &&
                    v2 && !v3 && !v4 && !v5 && !m6 && wrong[1] == 0 && final_sum[1] == 0 && wrong[2] == 0 && final_sum[2] == 0 && torn[2] == 0 &&
                    pairs.size() == 6 && cancelled.size() == 4 && greedy_plan.size() == 5 && exact_plan.size() == 4 && settles(net, cancelled) &&
                    settles(net, greedy_plan) && settles(net, exact_plan) && cents.invariants_hold && round.invariants_hold;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Splits always sum to the total: largest remainder in integer cents ==
  100.00 equal among ann, bob, cat         -> ann 33.34 bob 33.33 cat 33.33 = 100.00 | round each share: 99.99
  10.00 at 33.3333 / 33.3333 / 33.3334 %   -> ann 3.33 bob 3.33 cat 3.34 = 10.00 | round each share: 9.99
  0.10 in shares 2 : 1 : 1                 -> ann 0.05 bob 0.03 cat 0.02 = 0.10 | round each share: 0.09
  0.02 equal among ann, bob, cat           -> ann 0.01 bob 0.01 cat 0.00 = 0.02 | round each share: 0.03
  100000 random equal/shares splits: round-each drifted in 62750 (max 4 cents) | largest remainder drifted in 0
== 2. Why HALF_EVEN: 1,000,000 line items, 7.5% tax, each rounded to the cent ==
  exact tax total 37500495.92700 dollars
  DOWN (what a (long) cast does)   total off by -4877.68700 dollars
  HALF_UP (school rounding)        total off by 129.97300 dollars
  HALF_EVEN (banker's rounding)    total off by 5.29300 dollars
== 3. Validation: illegal splits never reach a ledger ==
  percent 33.33 + 33.33 + 33.33        -> Rejected: percentages sum to 99.99, not 100
  percent 50.00 + 50: 4-decimal fixed point 500000 + 500000 == 1000000 -> ann 50.00 bob 50.00 = 100.00
  exact 60.00 + 30.00 of 100.00        -> Rejected: exact legs sum to 90.00, total is 100.00
  percent 12.34567 + 87.65433          -> Rejected: percentage 12.34567 has more than 4 decimals
  shares ann 0 : bob 3                 -> Rejected: share weights must be positive
  parse_fixed("10.005", 2)             -> amount 10.005 has more than 2 decimals (rejected, never rounded)
  double 0.1 + 0.2                     -> 0.30000000000000004 (why money is never a double)
== 4. 8 threads x 50,000 expenses into one 6-member group; an auditor sums the balances meanwhile ==
  relaxed load() then store()    members wrong 6 of 6 | final sum -7916.18 | audits that saw sum != 0: 440930 of 440940
  fetch_add() per member         members wrong 0 of 6 | final sum 0.00 | audits that saw sum != 0: 186562 of 456671
  CAS on an immutable snapshot   members wrong 0 of 6 | final sum 0.00 | audits that saw sum != 0: 0 of 456479 | CAS retries 1449544 (std::atomic<shared_ptr>)
== 5. Settling a trip: 7 equal-split expenses among ann, bob, cat, dan, eve, fay ==
  net balances: ann -60.00 bob -30.00 cat 20.00 dan 20.00 eve 20.00 fay 30.00 (sum 0.00)
  pairwise debts, netted per pair:                6 transfers [ann->cat 30.00, ann->dan 20.00, ann->eve 20.00, bob->ann 10.00, bob->fay 30.00, cat->bob 10.00]
  + cycle cancellation (1 cycle, existing pairs): 4 transfers [ann->cat 20.00, ann->dan 20.00, ann->eve 20.00, bob->fay 30.00]
  greedy heap (largest pays largest):             5 transfers [ann->fay 30.00, ann->cat 20.00, bob->dan 20.00, ann->eve 10.00, bob->eve 10.00]
  exact minimum (zero-sum subgroups):             4 transfers [ann->cat 20.00, ann->dan 20.00, ann->eve 20.00, bob->fay 30.00]
== 5b. 2,000 random groups of 4-10 people, 3n expenses each: average transfers to settle ==
  random cents, 2..n people each:    pairwise 23.09 | cycle-cancelled 19.21 | greedy 6.08 | exact 6.08 | greedy above minimum in 4 of 2000 (max +1)
  round 10..100.00, 2 people each:   pairwise 17.87 | cycle-cancelled 13.85 | greedy 5.52 | exact 5.32 | greedy above minimum in 377 of 2000 (max +2)
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Splits always sum to the total: largest remainder in integer cents ==
  100.00 equal among ann, bob, cat         -> ann 33.34 bob 33.33 cat 33.33 = 100.00 | round each share: 99.99
  10.00 at 33.3333 / 33.3333 / 33.3334 %   -> ann 3.33 bob 3.33 cat 3.34 = 10.00 | round each share: 9.99
  0.10 in shares 2 : 1 : 1                 -> ann 0.05 bob 0.03 cat 0.02 = 0.10 | round each share: 0.09
  0.02 equal among ann, bob, cat           -> ann 0.01 bob 0.01 cat 0.00 = 0.02 | round each share: 0.03
  100000 random equal/shares splits: round-each drifted in 62750 (max 4 cents) | largest remainder drifted in 0
== 2. Why HALF_EVEN: 1,000,000 line items, 7.5% tax, each rounded to the cent ==
  exact tax total 37500495.92700 dollars
  DOWN (what a (long) cast does)   total off by -4877.68700 dollars
  HALF_UP (school rounding)        total off by 129.97300 dollars
  HALF_EVEN (banker's rounding)    total off by 5.29300 dollars
== 3. Validation: illegal splits never reach a ledger ==
  percent 33.33 + 33.33 + 33.33        -> Rejected: percentages sum to 99.99, not 100
  percent 50.00 + 50: 4-decimal fixed point 500000 + 500000 == 1000000 -> ann 50.00 bob 50.00 = 100.00
  exact 60.00 + 30.00 of 100.00        -> Rejected: exact legs sum to 90.00, total is 100.00
  percent 12.34567 + 87.65433          -> Rejected: percentage 12.34567 has more than 4 decimals
  shares ann 0 : bob 3                 -> Rejected: share weights must be positive
  parse_fixed("10.005", 2)             -> amount 10.005 has more than 2 decimals (rejected, never rounded)
  double 0.1 + 0.2                     -> 0.30000000000000004 (why money is never a double)
== 4. 8 threads x 50,000 expenses into one 6-member group; an auditor sums the balances meanwhile ==
  relaxed load() then store()    members wrong 6 of 6 | final sum 2090.43 | audits that saw sum != 0: 372791 of 373204
  fetch_add() per member         members wrong 0 of 6 | final sum 0.00 | audits that saw sum != 0: 179688 of 395470
  CAS on an immutable snapshot   members wrong 0 of 6 | final sum 0.00 | audits that saw sum != 0: 0 of 290664 | CAS retries 339049 (mutex-guarded shared_ptr)
== 5. Settling a trip: 7 equal-split expenses among ann, bob, cat, dan, eve, fay ==
  net balances: ann -60.00 bob -30.00 cat 20.00 dan 20.00 eve 20.00 fay 30.00 (sum 0.00)
  pairwise debts, netted per pair:                6 transfers [ann->cat 30.00, ann->dan 20.00, ann->eve 20.00, bob->ann 10.00, bob->fay 30.00, cat->bob 10.00]
  + cycle cancellation (1 cycle, existing pairs): 4 transfers [ann->cat 20.00, ann->dan 20.00, ann->eve 20.00, bob->fay 30.00]
  greedy heap (largest pays largest):             5 transfers [ann->fay 30.00, ann->cat 20.00, bob->dan 20.00, ann->eve 10.00, bob->eve 10.00]
  exact minimum (zero-sum subgroups):             4 transfers [ann->cat 20.00, ann->dan 20.00, ann->eve 20.00, bob->fay 30.00]
== 5b. 2,000 random groups of 4-10 people, 3n expenses each: average transfers to settle ==
  random cents, 2..n people each:    pairwise 23.09 | cycle-cancelled 19.21 | greedy 6.08 | exact 6.08 | greedy above minimum in 4 of 2000 (max +1)
  round 10..100.00, 2 people each:   pairwise 17.87 | cycle-cancelled 13.85 | greedy 5.52 | exact 5.32 | greedy above minimum in 377 of 2000 (max +2)
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Money | `double` | `BigDecimal` | Scale-2 value type that rejects extra precision; integer cents in the core; HALF_EVEN only where rounding is unavoidable |
| Splits | `total / n` per person | Validate sums; dump the remainder on the first person | Sealed split ADT → one pure `allocate()`; largest remainder with deterministic tie-break; `compareTo` not `equals` |
| Ledger | `synchronized` service or CHM `get`/`put` | Per-key `merge()` | Group is the consistency boundary: immutable snapshot + CAS (or per-group lock when hot); allocation outside the atomic section; event log + version |
| Settle-up | Pairwise debts | Greedy heap | Greedy vs exact minimum (and why it's NP-hard), plus cycle cancellation for the "existing relationships only" product mode, all verified to settle |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Multi-currency" | `Money(amount, Currency)` with a type-level ban on mixing. Convert at expense time with the **recorded** rate (HALF_EVEN), keep per-currency balances, and settle per currency or convert explicitly at settle time |
| "Edit or delete an expense" | Never mutate history: append a reversal delta plus a new expense. Balances stay a pure fold over the log, and the audit trail survives |
| "Clients retry on flaky networks" | Expense id = idempotency key; the snapshot (or log) stores applied ids; a duplicate returns the original result ([P13](03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md)) |
| "Offline-first mobile app" | Deltas commute, so an expense set merged by id-union converges (a grow-only set CRDT) and balances are a fold. Edits as reversals keep it convergent |
| "Groups of 200 people" | Exact DP is out (2²⁰⁰). Use greedy, and optionally look for small zero-sum subsets first (pairs, triples) with hashing, which captures most of the gain on round amounts |
| "Show who owes whom in real time" | Readers already get a consistent snapshot. Push the version to subscribers; clients re-fetch on a version change |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Split $100 three ways."</b></summary>

**L5:** "33.33 each."

**Why it fails:** one cent disappears; round-each drifted in 62,750 of 100,000 random splits. The `0.02 / 3` case shows round-each can also *over*-charge.

**L7 defence:** "Largest remainder in integer cents: floor every exact share, then give the leftover cents to the largest remainders with a deterministic tie-break. It sums exactly by construction. HALF_EVEN is for rounding a single amount, like tax or FX, where its lack of bias matters: +$5 vs +$130 for HALF_UP over a million lines."
</details>

<details>
<summary><b>Q2 ⚡ "ConcurrentHashMap.merge() is atomic. Why isn't that enough?"</b></summary>

**L5:** "It is enough, there are no lost updates."

**Why it fails:** it's atomic per key, but the invariant spans keys. Measured: 359,132 of 533,227 Java audits saw a group whose balances didn't sum to zero.

**L7 defence:** "The group is the consistency boundary. Publish an immutable snapshot via CAS, so readers get one volatile load and a whole number of expenses. Compute the allocation before the CAS loop so retries are cheap. For a very hot group, switch to a per-group lock or an event log with a materialized view."
</details>

<details>
<summary><b>Q3 ⚡ "Is your settle-up minimal?"</b></summary>

**L5:** "Yes, greedy largest-to-largest is optimal."

**Why it fails:** trip example: greedy 5, minimum 4. Round amounts: greedy above the minimum in 377 of 2,000 groups.

**L7 defence:** "Min transfers = k minus the max number of disjoint zero-sum groups. Deciding whether you can beat k−1 is subset sum, so it's NP-hard. A subset DP is exact to about 20 members; past that, greedy. And if users only want to pay people they already transacted with, that's a different objective: cycle cancellation on the pairwise graph."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Group balances off by a cent | Round-each split | Largest remainder in integer cents |
| `100.00` percent split rejected | `BigDecimal.equals` compares scale | `compareTo` |
| `ArithmeticException` on a 3-way split | `divide` without scale | Integer apportionment |
| Settle-up plan doesn't settle | Plan computed from a torn read | Consistent snapshot per group |
| Balances drift under load | `get` then `put` | Atomic delta application |
| "Simplify debts" pays strangers | Greedy/exact ignore relationships | Offer cycle-cancellation mode |

- [ ] Money: scale-2 value type, rejects extra precision; no `double` anywhere.
- [ ] One pure `allocate(Money, Split)`; largest remainder; deterministic tie-break.
- [ ] Ledger invariant holds for every reader; allocation outside the atomic section.
- [ ] Settlement plans verified to settle; the exact minimum's limits stated (NP-hard via subset sum).
- [ ] Idempotency (expense id) and reversal-based edits for production.

## 10. References

- Java `BigDecimal` (`equals` vs `compareTo`, `divide`, `RoundingMode`). <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/math/BigDecimal.html>
- Java `RoundingMode.HALF_EVEN`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/math/RoundingMode.html>
- cppreference, `std::atomic<std::shared_ptr>`. <https://en.cppreference.com/w/cpp/memory/shared_ptr/atomic2>
- Largest remainder method (Hamilton apportionment). <https://en.wikipedia.org/wiki/Largest_remainders_method>
- In this KB: [P2 CAS on an immutable state](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/02-problem-02-pluggable-rate-limiter-token-bucket-sliding-window-cas.md) · [P13 Idempotency keys and ordered locking](03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md) · [01.3 CAS and striping](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md)
