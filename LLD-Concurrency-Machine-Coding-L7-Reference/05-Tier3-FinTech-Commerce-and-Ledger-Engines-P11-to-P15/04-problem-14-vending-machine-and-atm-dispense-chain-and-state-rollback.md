# P14 · Vending Machine and ATM: State Machines, Change-Making That Greedy Gets Wrong, and Rollback as a Saga

> **Folder 05 · Problem 14 of 20.** The textbook answer is the State pattern plus a Chain of Responsibility of note handlers. At L7, both survive only after three corrections:
> 1. **The chain is greedy, and greedy fails on limited cassettes.** $60 from `[50, 20, 20, 20]` has a solution greedy can't find. You need backtracking or DP.
> 2. **"Rollback" is a saga.** Steps run in order of reversibility, each with a compensation; the irreversible one (paper leaving the machine) goes last.
> 3. **A machine receives events concurrently** (keypad, coin lever, sensors, the service port). Transitions must be committed one at a time, with effects only after the commit. Measured: the naive version overpaid in **4,988–4,992 of 5,000** rounds.
>
> **Listing pair P14:** `VendingAtm.java` / `vending_atm.cpp`. Sections 1–4 are deterministic and **byte-identical in Java and GCC**; section 5 shows one measured run.

---

## 1. Problem and scope

**ATM:**
- card → PIN (3 tries, then the card is retained) → withdraw an amount → notes from limited cassettes (100/50/20/10);
- jams, a purge bin, out-of-service mode and a technician reset.

**Vending:**
- insert coins, select an item, get change from limited coin tubes (25/10/5), cancel for a refund;
- sold out, exact-change-only, out of service.

**Out of scope:** card networks and EMV, and hardware protocols. The dispenser is an interface returning how many notes left before a jam.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| ATM state | `sealed Atm permits Idle, CardIn(account, badPins), Authed(account), Dispensing(account, amount, tx), OutOfService(reason)` | `std::variant` of the same |
| Vending snapshot | `record Machine(Mode, coins[], stock[])`, `sealed Mode permits Ready, Accepting(credit), Broken` | `struct Machine { Mode; Counts coins, stock; }` |
| Transition | pure `Step insert/select/cancel(Machine, …)` → `Step(next, effects)` | the same; `Step::next` is `std::optional` (nullopt = no change) |
| Change-making | `greedy` (a `Handler` chain), `dfs` (`Search`, min pieces + node count), `dpMinPieces` | the same |
| Money movement | `Bank.apply(tx, account, delta)`, idempotent per tx id (as in P13) | the same |

**Invariants:**
- **I1:** you can withdraw only from `Authed`, and insert a card only in `Idle`. The data each state needs (account, bad-PIN count) lives **in** the state, so a field can't be stale or null.
- **I2:** when a dispense plan is accepted, the cassettes can pay it **exactly**. Rejection happens *before* any money moves, and comes with the nearest feasible amounts.
- **I3:** the customer is debited exactly the value of notes that left the machine. Undelivered notes are refunded and land in the purge bin for reconciliation.
- **I4:** a vending machine pays out exactly what it took in: item price + change, **or** a refund, never both.
- **I5:** every effect (dispense, refund) belongs to exactly one committed transition.

## 3. Concurrency and contention analysis

### 3.1 Change-making: the chain is greedy

The Chain of Responsibility (`Handler(100) → Handler(50) → Handler(20) → Handler(10)`) has each handler take as many of its note as fit.

| Case | Greedy chain | Backtracking DFS | Bounded DP |
|---|---|---|---|
| 60 from 50×1, 20×3 | **FAILED**: took the 50, nothing makes 10 | 20×3 (10 search nodes) | 3 notes |
| 80 from 50×1, 20×4 | **FAILED** | 20×4 | 4 |
| Coins {4,3,1} unlimited, amount 6 | 4+1+1 (3 coins) | 3+3 (2 coins) | 2 |
| 100,000 random cassettes, 0–5 of each note, amounts 10–500 | failed on **1,647 of 69,532** feasible cases (2.4%) | all found; 24 nodes per case | DFS and DP disagree on **0** |

Two separate failures hide here:
- **Limited counts** break greedy even for a canonical system like 100/50/20/10.
- **Non-canonical systems** ({4,3,1}) break greedy even with unlimited coins.

**The DFS:**
- goes largest denomination first, most pieces first;
- prunes with the bound `pieces + ⌈rem / d_i⌉ ≥ best`;
- at ATM scale it is tiny, and the DP cross-checks it on every random case.

**Keep the chain** if you like the extensibility (a new cassette type is a new handler). Just make it a chain of *candidates* explored by backtracking, not a single greedy pass.

### 3.2 Rollback is a saga, ordered by reversibility

A withdrawal runs as:
1. **plan** (pure);
2. **reserve notes** (local; undo = put them back);
3. **debit** (remote; undo = an idempotent credit);
4. **dispense** (irreversible).

Ordering matters. Debiting after dispensing means a crash hands out free money. Dispensing before reserving means two plans can claim the same notes.

**On a jam after 2 of 3 notes**, the listing:
- refunds the undelivered 20 (`tx:refund`, idempotent);
- moves the stuck note to the purge bin;
- goes `OutOfService`.

The customer ends at 1000 − 40, and the cassette, purge bin and ledger reconcile. Real ATMs do the same: a later physical count of the purge bin settles disputes.

### 3.3 Concurrent events: commit transitions, then act

**The race:** credit 100, and "select chips (75)" and "coin return" pressed simultaneously. Both naive handlers read `credit` and act, so the machine drops the chips **and** refunds 100.

| 5,000 rounds | Java | GCC | Clang |
|---|---|---|---|
| Naive mutable fields, check then act | **4,988** overpaid | **4,990** | **4,992** |
| Pure transition, committed one at a time | 0 | 0 | 0 |

**The fix:** each event is a pure function `Machine → Step(next, effects)`.
- **Java** commits `next` with `compareAndSet` on an `AtomicReference<Machine>`. The loser re-runs its event against the winner's state, and `cancel` on a `Ready` machine is a no-op ("nothing to refund").
- **C++** serializes the same pure transition under a mutex, an actor with a lock as its mailbox, because libc++ here lacks `atomic<shared_ptr>` (see P11).

**Effects (motors, coin release) run only after the commit,** so a retried transition never drops two items. The same shape as P12's single writer: events in, one transition at a time, effects out.

## 4. Java 21 implementation

```java
// VendingAtm.java - P14: ATM/vending state machines, greedy chain vs backtracking change, saga rollback, CAS-committed events
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.StringJoiner;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Function;

public final class VendingAtm {

    // ---- change making: greedy chain vs backtracking vs DP

    record Plan(int[] counts, int pieces) {
        String show(int[] denoms) {
            StringJoiner j = new StringJoiner(" + ");
            for (int i = 0; i < denoms.length; i++)
                if (counts[i] > 0) j.add(denoms[i] + "x" + counts[i]);
            return j.length() == 0 ? "nothing" : j.toString();
        }
    }

    /** Classic chain of responsibility: each handler takes as many of its denomination as fit and delegates the rest. That is greedy. */
    record Handler(int index, Handler next) {
        boolean handle(int amount, int[] denoms, int[] avail, int[] taken) {
            taken[index] = Math.min(avail[index], amount / denoms[index]);
            int rest = amount - taken[index] * denoms[index];
            return rest == 0 || (next != null && next.handle(rest, denoms, avail, taken));
        }
    }

    static Plan greedy(int amount, int[] denoms, int[] avail) {
        Handler chain = null;
        for (int i = denoms.length - 1; i >= 0; i--) chain = new Handler(i, chain);
        int[] taken = new int[denoms.length];
        if (chain == null || !chain.handle(amount, denoms, avail, taken)) return null;
        return new Plan(taken, Arrays.stream(taken).sum());
    }

    /** Backtracking over denominations (largest first, most pieces first), pruned by a lower bound: minimum pieces. */
    static final class Search {
        final int[] d, c, cur;
        int[] best;
        int bestPieces = Integer.MAX_VALUE;
        long nodes;

        Search(int[] denoms, int[] avail) {
            d = denoms;
            c = avail;
            cur = new int[denoms.length];
        }

        void go(int i, int rem, int pieces) {
            nodes++;
            if (rem == 0) {
                if (pieces < bestPieces) {
                    bestPieces = pieces;
                    best = cur.clone();
                }
                return;
            }
            if (i == d.length || pieces + (rem + d[i] - 1) / d[i] >= bestPieces) return;   // even all-d[i] can't beat the best
            for (int t = Math.min(c[i], rem / d[i]); t >= 0; t--) {
                cur[i] = t;
                go(i + 1, rem - t * d[i], pieces + t);
            }
            cur[i] = 0;
        }

        Plan plan() {
            return best == null ? null : new Plan(best, bestPieces);
        }
    }

    static Search dfs(int amount, int[] denoms, int[] avail) {
        Search s = new Search(denoms, avail);
        s.go(0, amount, 0);
        return s;
    }

    static int gcd(int a, int b) {
        return b == 0 ? a : gcd(b, a % b);
    }

    /** Bounded change-making DP (every piece is a 0/1 item), in units of the denominations' gcd: min pieces or -1. */
    static int dpMinPieces(int amount, int[] denoms, int[] avail) {
        int g = 0;
        for (int x : denoms) g = gcd(g, x);
        if (amount % g != 0) return -1;
        int a = amount / g;
        int[] best = new int[a + 1];
        Arrays.fill(best, Integer.MAX_VALUE / 2);
        best[0] = 0;
        for (int i = 0; i < denoms.length; i++) {
            int v = denoms[i] / g;
            for (int k = 0; k < avail[i]; k++)
                for (int x = a; x >= v; x--) best[x] = Math.min(best[x], best[x - v] + 1);
        }
        return best[a] >= Integer.MAX_VALUE / 2 ? -1 : best[a];
    }

    static String cassette(int[] denoms, int[] counts) {
        StringJoiner j = new StringJoiner(" ");
        for (int i = 0; i < denoms.length; i++) j.add(denoms[i] + "x" + counts[i]);
        return j.toString();
    }

    // ---- ATM: sealed states; a withdrawal is a saga whose irreversible step (paper leaving the machine) runs last

    static final int[] NOTES = {100, 50, 20, 10};

    sealed interface Atm permits Idle, CardIn, Authed, Dispensing, OutOfService {}
    record Idle() implements Atm {}
    record CardIn(String account, int badPins) implements Atm {}
    record Authed(String account) implements Atm {}
    record Dispensing(String account, int amount, String tx) implements Atm {}
    record OutOfService(String reason) implements Atm {}

    static String show(Atm a) {
        return switch (a) {
            case Idle i -> "Idle";
            case CardIn c -> "CardIn(" + c.account() + ")";
            case Authed x -> "Authed(" + x.account() + ")";
            case Dispensing d -> "Dispensing(" + d.amount() + ")";
            case OutOfService o -> "OutOfService(" + o.reason() + ")";
        };
    }

    /** Idempotent per tx id, like P13's ledger (one map here: the ATM is a single-session device). */
    static final class Bank {
        final Map<String, Long> balances = new HashMap<>();
        final Set<String> applied = new HashSet<>();

        void apply(String tx, String account, long delta) {
            if (applied.add(tx)) balances.merge(account, delta, Long::sum);
        }
    }

    /** The hardware: presents notes one by one; returns how many left the machine before a jam (all of them if none). */
    interface Dispenser {
        int present(List<Integer> notes);
    }

    static final class AtmMachine {
        Atm state = new Idle();
        final int[] cassettes, purgeBin = new int[NOTES.length];
        final Bank bank;
        final Dispenser dispenser;
        int seq;

        AtmMachine(int[] cassettes, Bank bank, Dispenser dispenser) {
            this.cassettes = cassettes;
            this.bank = bank;
            this.dispenser = dispenser;
        }

        String insertCard(String account) {
            return switch (state) {
                case Idle i -> {
                    state = new CardIn(account, 0);
                    yield "card accepted";
                }
                case OutOfService o -> "rejected: out of service (" + o.reason() + ")";
                default -> "rejected: a session is active";
            };
        }

        String enterPin(String pin) {
            if (!(state instanceof CardIn(var account, var bad))) return "rejected: no card";
            if (pin.equals("1234")) {
                state = new Authed(account);
                return "authenticated " + account;
            }
            state = bad + 1 == 3 ? new Idle() : new CardIn(account, bad + 1);
            return bad + 1 == 3 ? "card retained after 3 wrong PINs" : "wrong PIN (" + (bad + 1) + " of 3)";
        }

        String withdraw(int amount) {
            if (!(state instanceof Authed(var account))) return "rejected: not authenticated";
            Plan p = dfs(amount, NOTES, cassettes).plan();
            if (p == null) return "rejected: cannot dispense " + amount + " from " + cassette(NOTES, cassettes) + "; try " + nearest(amount);
            if (bank.balances.getOrDefault(account, 0L) < amount) return "rejected: insufficient funds";
            String tx = "atm-" + ++seq;
            for (int i = 0; i < NOTES.length; i++) cassettes[i] -= p.counts()[i];   // 1. reserve notes (undo: put them back)
            bank.apply(tx + ":debit", account, -amount);                          // 2. debit (undo: credit, idempotent)
            state = new Dispensing(account, amount, tx);
            List<Integer> notes = new ArrayList<>();
            for (int i = 0; i < NOTES.length; i++)
                for (int k = 0; k < p.counts()[i]; k++) notes.add(i);
            int presented = dispenser.present(notes);                            // 3. irreversible, so it runs last
            if (presented == notes.size()) {
                state = new Idle();
                return "dispensed " + p.show(NOTES) + ", card returned";
            }
            int undelivered = 0;                                                 // compensate what did not happen
            for (int k = presented; k < notes.size(); k++) {
                undelivered += NOTES[notes.get(k)];
                purgeBin[notes.get(k)]++;
            }
            bank.apply(tx + ":refund", account, undelivered);
            state = new OutOfService("dispenser jam");
            return "jam after " + presented + " of " + notes.size() + " notes: refunded " + undelivered + ", " + (notes.size() - presented)
                    + " note(s) to the purge bin, out of service";
        }

        String nearest(int amount) {
            int down = amount - 10, up = amount + 10;
            while (down > 0 && dfs(down, NOTES, cassettes).plan() == null) down -= 10;
            while (up < 2_000 && dfs(up, NOTES, cassettes).plan() == null) up += 10;
            return (down > 0 ? down + " or " : "") + up;
        }

        String service() {
            if (!(state instanceof OutOfService)) return "nothing to service";
            Arrays.fill(purgeBin, 0);                                            // a technician empties and counts the purge bin
            state = new Idle();
            return "jam cleared, purge bin reconciled, back in service";
        }
    }

    // ---- vending: an immutable snapshot and pure transitions; effects run only after the transition commits

    static final int[] COINS = {25, 10, 5};
    static final String[] ITEMS = {"chips", "soda", "gum"};
    static final int[] PRICES = {75, 60, 35};

    sealed interface Mode permits Ready, Accepting, Broken {}
    record Ready() implements Mode {}
    record Accepting(int credit) implements Mode {}
    record Broken(String reason) implements Mode {}

    static String show(Mode m) {
        return switch (m) {
            case Ready r -> "Ready";
            case Accepting a -> "Accepting(" + a.credit() + ")";
            case Broken b -> "Broken(" + b.reason() + ")";
        };
    }

    record Machine(Mode mode, int[] coins, int[] stock) {}           // arrays are never written after publication

    record Step(Machine next, List<String> effects) {}

    static Step insert(Machine m, int coin) {
        int credit = switch (m.mode()) {
            case Ready r -> 0;
            case Accepting a -> a.credit();
            case Broken b -> -1;
        };
        if (credit < 0) return new Step(m, List.of("coin returned (out of service)"));
        int[] coins = m.coins().clone();
        coins[coin]++;                                                   // the coin drops into its tube immediately
        return new Step(new Machine(new Accepting(credit + COINS[coin]), coins, m.stock()), List.of());
    }

    static Step select(Machine m, int item) {
        if (!(m.mode() instanceof Accepting(var credit))) return new Step(m, List.of("insert coins first"));
        if (m.stock()[item] == 0) return new Step(m, List.of(ITEMS[item] + " sold out"));
        if (credit < PRICES[item]) return new Step(m, List.of("insert " + (PRICES[item] - credit) + " more"));
        Plan change = dfs(credit - PRICES[item], COINS, m.coins()).plan();
        if (change == null) return new Step(m, List.of("exact change only: cannot return " + (credit - PRICES[item])));
        int[] coins = m.coins().clone(), stock = m.stock().clone();
        for (int i = 0; i < COINS.length; i++) coins[i] -= change.counts()[i];
        stock[item]--;
        return new Step(new Machine(new Ready(), coins, stock),
                List.of("drop " + ITEMS[item], "change " + (credit - PRICES[item]) + (change.pieces() > 0 ? " as " + change.show(COINS) : "")));
    }

    static Step cancel(Machine m) {
        if (!(m.mode() instanceof Accepting(var credit))) return new Step(m, List.of("nothing to refund"));
        Plan back = dfs(credit, COINS, m.coins()).plan();              // always exists: the inserted coins are in the tubes
        int[] coins = m.coins().clone();
        for (int i = 0; i < COINS.length; i++) coins[i] -= back.counts()[i];
        return new Step(new Machine(new Ready(), coins, m.stock()), List.of("refund " + credit + " as " + back.show(COINS)));
    }

    /** One CAS commits a transition; the loser re-runs its event against the winner's state. Effects follow the commit. */
    static final class Vending {
        final AtomicReference<Machine> ref;

        Vending(Machine m) {
            ref = new AtomicReference<>(m);
        }

        List<String> fire(Function<Machine, Step> event) {
            for (;;) {
                Machine cur = ref.get();
                Step s = event.apply(cur);
                if (s.next() == cur || ref.compareAndSet(cur, s.next())) return s.effects();
            }
        }
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

    static void spin(int n) {
        for (int i = 0; i < n; i++) Thread.onSpinWait();
    }

    /** Two threads released together by a spin gate with a ready count (a CyclicBarrier's wake-up skew hides the race). */
    static void race(Runnable a, Runnable b) throws InterruptedException {
        AtomicInteger ready = new AtomicInteger();
        AtomicBoolean go = new AtomicBoolean();
        Thread ta = Thread.ofPlatform().start(() -> {
            ready.incrementAndGet();
            while (!go.get()) Thread.onSpinWait();
            a.run();
        });
        Thread tb = Thread.ofPlatform().start(() -> {
            ready.incrementAndGet();
            while (!go.get()) Thread.onSpinWait();
            b.run();
        });
        while (ready.get() < 2) Thread.onSpinWait();
        go.set(true);
        ta.join();
        tb.join();
    }

    static int paidOut(List<String> effects) {                         // value that left the machine: change/refund + item price
        int v = 0;
        for (String e : effects) {
            if (e.startsWith("drop chips")) v += 75;
            if (e.startsWith("change ") || e.startsWith("refund ")) v += Integer.parseInt(e.split(" ")[1]);
        }
        return v;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Dispense 60 from cassettes 50x1 20x3 (no 10s, no 100s) ==");
        int[] c60 = {0, 1, 3, 0};
        Plan g60 = greedy(60, NOTES, c60);
        Search d60 = dfs(60, NOTES, c60);
        System.out.println("  chain of responsibility (greedy): " + (g60 == null ? "FAILED (took 50, nothing can make the last 10)" : g60.show(NOTES)));
        System.out.printf("  backtracking DFS (min notes):     %s (%d notes, %d search nodes)%n", d60.plan().show(NOTES), d60.plan().pieces(), d60.nodes);
        System.out.printf("  bounded DP (min notes):           %d notes%n", dpMinPieces(60, NOTES, c60));
        int[] c80 = {0, 1, 4, 0};
        Plan g80 = greedy(80, NOTES, c80);
        System.out.printf("  80 from 50x1 20x4: greedy %s | DFS %s%n", g80 == null ? "FAILED" : g80.show(NOTES), dfs(80, NOTES, c80).plan().show(NOTES));
        int[] odd = {4, 3, 1}, unlimited = {100, 100, 100};
        Plan gOdd = greedy(6, odd, unlimited), dOdd = dfs(6, odd, unlimited).plan();
        System.out.printf("  coins {4,3,1} unlimited, amount 6: greedy %s (%d coins) | optimal %s (%d coins): greedy is only safe for canonical systems%n",
                gOdd.show(odd), gOdd.pieces(), dOdd.show(odd), dOdd.pieces());

        System.out.println("== 2. 100,000 random cassettes (0-5 of each 100/50/20/10) and amounts (10..500) ==");
        Rng r = new Rng(3);
        int feasible = 0, greedyFailed = 0, greedyWorse = 0, disagree = 0;
        long nodes = 0;
        for (int i = 0; i < 100_000; i++) {
            int[] avail = {r.below(6), r.below(6), r.below(6), r.below(6)};
            int amount = 10 * (1 + r.below(50));
            int dp = dpMinPieces(amount, NOTES, avail);
            Search s = dfs(amount, NOTES, avail);
            Plan g = greedy(amount, NOTES, avail);
            nodes += s.nodes;
            if (dp >= 0) feasible++;
            if (dp >= 0 && g == null) greedyFailed++;
            if (g != null && g.pieces() > dp) greedyWorse++;
            if ((s.plan() == null ? -1 : s.plan().pieces()) != dp) disagree++;
        }
        System.out.printf("  feasible %d | greedy failed on %d feasible cases | greedy used extra notes on %d | DFS vs DP disagreements %d | DFS nodes per case %.1f%n",
                feasible, greedyFailed, greedyWorse, disagree, nodes / 100_000.0);

        System.out.println("== 3. ATM session; the withdrawal is a saga (reserve notes -> debit -> dispense) ==");
        Bank bank = new Bank();
        bank.apply("open-alice", "alice", 1_000);
        bank.apply("open-bob", "bob", 500);
        int[] jamAfter = {2};                                           // the next dispense jams after 2 notes
        AtmMachine atm = new AtmMachine(new int[]{0, 1, 3, 0}, bank, notes -> {
            int k = Math.min(jamAfter[0], notes.size());
            jamAfter[0] = Integer.MAX_VALUE;
            return k;
        });
        String[][] steps = {
                {"insert alice's card", atm.insertCard("alice")}, {"PIN 0000", atm.enterPin("0000")}, {"PIN 1234", atm.enterPin("1234")},
                {"withdraw 30", atm.withdraw(30)}, {"withdraw 60", atm.withdraw(60)}};
        for (String[] s : steps) System.out.printf("  %-28s -> %s%n", s[0], s[1]);
        System.out.printf("  after the jam: alice %d (1000 - 40 delivered) | cassettes %s | purge bin %s | state %s%n", bank.balances.get("alice"),
                cassette(NOTES, atm.cassettes), cassette(NOTES, atm.purgeBin), show(atm.state));
        String blocked = atm.insertCard("bob"), serviced = atm.service();
        String bobIn = atm.insertCard("bob"), bobPin = atm.enterPin("1234"), bobOut = atm.withdraw(50);
        System.out.printf("  %-28s -> %s%n  %-28s -> %s%n  %-28s -> %s, %s, %s | bob %d | state %s%n", "bob's card", blocked, "technician", serviced,
                "bob withdraws 50", bobIn, bobPin, bobOut, bank.balances.get("bob"), show(atm.state));

        System.out.println("== 4. Vending machine: pure transitions over an immutable snapshot ==");
        Vending v = new Vending(new Machine(new Ready(), new int[]{2, 0, 0}, new int[]{3, 2, 0}));   // tubes: 25x2, no 10s/5s
        List<String> lines = new ArrayList<>();
        for (int k = 0; k < 4; k++) v.fire(m -> insert(m, 0));          // four quarters: credit 100
        lines.add("insert 25 x4 -> credit " + ((Accepting) v.ref.get().mode()).credit());
        lines.add("select gum   -> " + v.fire(m -> select(m, 2)));
        lines.add("select soda  -> " + v.fire(m -> select(m, 1)));      // 40 change: 25x? + 10/5 needed: no
        lines.add("select chips -> " + v.fire(m -> select(m, 0)));
        lines.add("cancel       -> " + v.fire(VendingAtm::cancel));
        v.fire(m -> insert(m, 0));
        v.fire(m -> insert(m, 0));
        lines.add("insert 25 x2, cancel -> " + v.fire(VendingAtm::cancel));
        for (String s : lines) System.out.println("  " + s);
        Machine fin = v.ref.get();
        System.out.printf("  tubes 25x%d 10x%d 5x%d | stock chips %d soda %d gum %d | mode %s%n", fin.coins()[0], fin.coins()[1], fin.coins()[2],
                fin.stock()[0], fin.stock()[1], fin.stock()[2], show(fin.mode()));

        System.out.println("== 5. 'select chips' and 'coin return' pressed at the same moment, credit 100, 5,000 rounds ==");
        int naiveOverpaid = 0, casOverpaid = 0, casBoth = 0;
        for (int round = 0; round < 5_000; round++) {
            AtomicLong credit = new AtomicLong(100), out = new AtomicLong();
            race(() -> {                                                 // naive keypad handler: mutable fields, check then act
                if (credit.get() >= 75) {
                    spin(300);
                    credit.addAndGet(-75);
                    out.addAndGet(75);                                   // drop the item
                    long change = credit.getAndSet(0);
                    if (change > 0) out.addAndGet(change);               // return the change
                }
            }, () -> {                                                   // naive coin-return lever
                long c = credit.get();
                if (c > 0) {
                    spin(300);
                    credit.set(0);
                    out.addAndGet(c);
                }
            });
            if (out.get() > 100) naiveOverpaid++;
            Vending vm = new Vending(new Machine(new Accepting(100), new int[]{4, 2, 2}, new int[]{5, 5, 5}));
            List<List<String>> fx = new ArrayList<>(List.of(List.of(), List.of()));
            race(() -> fx.set(0, vm.fire(m -> select(m, 0))), () -> fx.set(1, vm.fire(VendingAtm::cancel)));
            int paid = paidOut(fx.get(0)) + paidOut(fx.get(1));
            if (paid != 100) casOverpaid++;
            if (paidOut(fx.get(0)) > 0 && paidOut(fx.get(1)) > 0) casBoth++;
        }
        System.out.printf("  naive mutable state:       rounds paying out more than the 100 inserted: %d of 5000%n", naiveOverpaid);
        System.out.printf("  CAS-committed transitions: rounds paying out != 100: %d | rounds where both events paid: %d%n", casOverpaid, casBoth);

        boolean ok = g60 == null && d60.plan().pieces() == 3 && d60.plan().counts()[2] == 3 && dpMinPieces(60, NOTES, c60) == 3 && g80 == null
                && gOdd.pieces() == 3 && dOdd.pieces() == 2 && disagree == 0 && greedyFailed > 0
                && bank.balances.get("alice") == 960 && atm.cassettes[2] == 0 && bank.balances.get("bob") == 450 && atm.state instanceof Idle
                && blocked.startsWith("rejected") && lines.get(2).contains("exact change only") && fin.mode() instanceof Ready
                && casOverpaid == 0 && casBoth == 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1–4 deterministic; 5 one measured run):**

```text
== 1. Dispense 60 from cassettes 50x1 20x3 (no 10s, no 100s) ==
  chain of responsibility (greedy): FAILED (took 50, nothing can make the last 10)
  backtracking DFS (min notes):     20x3 (3 notes, 10 search nodes)
  bounded DP (min notes):           3 notes
  80 from 50x1 20x4: greedy FAILED | DFS 20x4
  coins {4,3,1} unlimited, amount 6: greedy 4x1 + 1x2 (3 coins) | optimal 3x2 (2 coins): greedy is only safe for canonical systems
== 2. 100,000 random cassettes (0-5 of each 100/50/20/10) and amounts (10..500) ==
  feasible 69532 | greedy failed on 1647 feasible cases | greedy used extra notes on 0 | DFS vs DP disagreements 0 | DFS nodes per case 24.0
== 3. ATM session; the withdrawal is a saga (reserve notes -> debit -> dispense) ==
  insert alice's card          -> card accepted
  PIN 0000                     -> wrong PIN (1 of 3)
  PIN 1234                     -> authenticated alice
  withdraw 30                  -> rejected: cannot dispense 30 from 100x0 50x1 20x3 10x0; try 20 or 40
  withdraw 60                  -> jam after 2 of 3 notes: refunded 20, 1 note(s) to the purge bin, out of service
  after the jam: alice 960 (1000 - 40 delivered) | cassettes 100x0 50x1 20x0 10x0 | purge bin 100x0 50x0 20x1 10x0 | state OutOfService(dispenser jam)
  bob's card                   -> rejected: out of service (dispenser jam)
  technician                   -> jam cleared, purge bin reconciled, back in service
  bob withdraws 50             -> card accepted, authenticated bob, dispensed 50x1, card returned | bob 450 | state Idle
== 4. Vending machine: pure transitions over an immutable snapshot ==
  insert 25 x4 -> credit 100
  select gum   -> [gum sold out]
  select soda  -> [exact change only: cannot return 40]
  select chips -> [drop chips, change 25 as 25x1]
  cancel       -> [nothing to refund]
  insert 25 x2, cancel -> [refund 50 as 25x2]
  tubes 25x5 10x0 5x0 | stock chips 2 soda 2 gum 0 | mode Ready
== 5. 'select chips' and 'coin return' pressed at the same moment, credit 100, 5,000 rounds ==
  naive mutable state:       rounds paying out more than the 100 inserted: 4988 of 5000
  CAS-committed transitions: rounds paying out != 100: 0 | rounds where both events paid: 0
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// vending_atm.cpp - P14: ATM/vending state machines, greedy chain vs backtracking change, saga rollback, serialized events
#include <algorithm>
#include <array>
#include <atomic>
#include <climits>
#include <cstdint>
#include <cstdio>
#include <format>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <numeric>
#include <optional>
#include <print>
#include <set>
#include <string>
#include <thread>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;
using Counts = std::vector<int>;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

// ---- change making: greedy chain vs backtracking vs DP

struct Plan {
    Counts counts;
    int pieces;
    std::string show(const Counts& denoms) const {
        std::string s;
        for (sz i = 0; i < denoms.size(); ++i)
            if (counts[i] > 0) s += std::format("{}{}x{}", s.empty() ? "" : " + ", denoms[i], counts[i]);
        return s.empty() ? "nothing" : s;
    }
};

/** Classic chain of responsibility: each handler takes as many of its denomination as fit and delegates the rest. That is greedy. */
struct Handler {
    sz index;
    std::unique_ptr<Handler> next;
    bool handle(int amount, const Counts& denoms, const Counts& avail, Counts& taken) const {
        taken[index] = std::min(avail[index], amount / denoms[index]);
        const int rest = amount - taken[index] * denoms[index];
        return rest == 0 || (next && next->handle(rest, denoms, avail, taken));
    }
};

std::optional<Plan> greedy(int amount, const Counts& denoms, const Counts& avail) {
    std::unique_ptr<Handler> chain;
    for (sz i = denoms.size(); i-- > 0;) chain = std::make_unique<Handler>(Handler{i, std::move(chain)});
    Counts taken(denoms.size());
    if (!chain || !chain->handle(amount, denoms, avail, taken)) return std::nullopt;
    return Plan{taken, std::accumulate(taken.begin(), taken.end(), 0)};
}

/** Backtracking over denominations (largest first, most pieces first), pruned by a lower bound: minimum pieces. */
struct Search {
    const Counts& d;
    const Counts& c;
    Counts cur;
    std::optional<Counts> best;
    int best_pieces = INT_MAX;
    i64 nodes = 0;
    Search(const Counts& denoms, const Counts& avail) : d(denoms), c(avail), cur(denoms.size()) {}
    void go(sz i, int rem, int pieces) {
        ++nodes;
        if (rem == 0) {
            if (pieces < best_pieces) {
                best_pieces = pieces;
                best = cur;
            }
            return;
        }
        if (i == d.size() || pieces + (rem + d[i] - 1) / d[i] >= best_pieces) return;  // even all-d[i] can't beat the best
        for (int t = std::min(c[i], rem / d[i]); t >= 0; --t) {
            cur[i] = t;
            go(i + 1, rem - t * d[i], pieces + t);
        }
        cur[i] = 0;
    }
    std::optional<Plan> plan() const { return best ? std::optional<Plan>(Plan{*best, best_pieces}) : std::nullopt; }
};

Search dfs(int amount, const Counts& denoms, const Counts& avail) {
    Search s(denoms, avail);
    s.go(0, amount, 0);
    return s;
}

/** Bounded change-making DP (every piece is a 0/1 item), in units of the denominations' gcd: min pieces or -1. */
int dp_min_pieces(int amount, const Counts& denoms, const Counts& avail) {
    int g = 0;
    for (const int x : denoms) g = std::gcd(g, x);
    if (amount % g != 0) return -1;
    const int a = amount / g;
    std::vector<int> best(static_cast<sz>(a) + 1, INT_MAX / 2);
    best[0] = 0;
    for (sz i = 0; i < denoms.size(); ++i) {
        const int v = denoms[i] / g;
        for (int k = 0; k < avail[i]; ++k)
            for (int x = a; x >= v; --x) best[static_cast<sz>(x)] = std::min(best[static_cast<sz>(x)], best[static_cast<sz>(x - v)] + 1);
    }
    return best[static_cast<sz>(a)] >= INT_MAX / 2 ? -1 : best[static_cast<sz>(a)];
}

std::string cassette(const Counts& denoms, const Counts& counts) {
    std::string s;
    for (sz i = 0; i < denoms.size(); ++i) s += std::format("{}{}x{}", i ? " " : "", denoms[i], counts[i]);
    return s;
}

// ---- ATM: variant states; a withdrawal is a saga whose irreversible step (paper leaving the machine) runs last

const Counts kNotes{100, 50, 20, 10};

struct Idle {};
struct CardIn { std::string account; int bad_pins; };
struct Authed { std::string account; };
struct Dispensing { std::string account; int amount; std::string tx; };
struct OutOfService { std::string reason; };
using Atm = std::variant<Idle, CardIn, Authed, Dispensing, OutOfService>;

std::string show(const Atm& a) {
    return std::visit(overloaded{
                          [](const Idle&) { return std::string("Idle"); },
                          [](const CardIn& c) { return "CardIn(" + c.account + ")"; },
                          [](const Authed& x) { return "Authed(" + x.account + ")"; },
                          [](const Dispensing& d) { return std::format("Dispensing({})", d.amount); },
                          [](const OutOfService& o) { return "OutOfService(" + o.reason + ")"; },
                      },
                      a);
}

/** Idempotent per tx id, like P13's ledger (one map here: the ATM is a single-session device). */
struct Bank {
    std::map<std::string, i64> balances;
    std::set<std::string> applied;
    void apply(const std::string& tx, const std::string& account, i64 delta) {
        if (applied.insert(tx).second) balances[account] += delta;
    }
};

/** The hardware: presents notes one by one; returns how many left the machine before a jam (all of them if none). */
using Dispenser = std::function<sz(const std::vector<sz>& notes)>;

class AtmMachine {
public:
    Atm state = Idle{};
    Counts cassettes, purge_bin = Counts(kNotes.size());
    Bank& bank;
    Dispenser dispenser;
    int seq = 0;

    AtmMachine(Counts c, Bank& b, Dispenser d) : cassettes(std::move(c)), bank(b), dispenser(std::move(d)) {}

    std::string insert_card(const std::string& account) {
        if (std::holds_alternative<Idle>(state)) {
            state = CardIn{account, 0};
            return "card accepted";
        }
        if (const auto* o = std::get_if<OutOfService>(&state)) return "rejected: out of service (" + o->reason + ")";
        return "rejected: a session is active";
    }

    std::string enter_pin(const std::string& pin) {
        const auto* c = std::get_if<CardIn>(&state);
        if (!c) return "rejected: no card";
        if (pin == "1234") {
            const std::string account = c->account;
            state = Authed{account};
            return "authenticated " + account;
        }
        const int bad = c->bad_pins + 1;
        if (bad == 3) {
            state = Idle{};
            return "card retained after 3 wrong PINs";
        }
        state = CardIn{c->account, bad};
        return std::format("wrong PIN ({} of 3)", bad);
    }

    std::string withdraw(int amount) {
        const auto* a = std::get_if<Authed>(&state);
        if (!a) return "rejected: not authenticated";
        const std::string account = a->account;
        const auto p = dfs(amount, kNotes, cassettes).plan();
        if (!p) return std::format("rejected: cannot dispense {} from {}; try {}", amount, cassette(kNotes, cassettes), nearest(amount));
        if (bank.balances[account] < amount) return "rejected: insufficient funds";
        const std::string tx = std::format("atm-{}", ++seq);
        for (sz i = 0; i < kNotes.size(); ++i) cassettes[i] -= p->counts[i];  // 1. reserve notes (undo: put them back)
        bank.apply(tx + ":debit", account, -amount);                         // 2. debit (undo: credit, idempotent)
        state = Dispensing{account, amount, tx};
        std::vector<sz> notes;
        for (sz i = 0; i < kNotes.size(); ++i)
            for (int k = 0; k < p->counts[i]; ++k) notes.push_back(i);
        const sz presented = dispenser(notes);  // 3. irreversible, so it runs last
        if (presented == notes.size()) {
            state = Idle{};
            return "dispensed " + p->show(kNotes) + ", card returned";
        }
        int undelivered = 0;  // compensate what did not happen
        for (sz k = presented; k < notes.size(); ++k) {
            undelivered += kNotes[notes[k]];
            ++purge_bin[notes[k]];
        }
        bank.apply(tx + ":refund", account, undelivered);
        state = OutOfService{"dispenser jam"};
        return std::format("jam after {} of {} notes: refunded {}, {} note(s) to the purge bin, out of service", presented, notes.size(), undelivered,
                           notes.size() - presented);
    }

    std::string nearest(int amount) {
        int down = amount - 10, up = amount + 10;
        while (down > 0 && !dfs(down, kNotes, cassettes).plan()) down -= 10;
        while (up < 2'000 && !dfs(up, kNotes, cassettes).plan()) up += 10;
        return (down > 0 ? std::format("{} or ", down) : "") + std::to_string(up);
    }

    std::string service() {
        if (!std::holds_alternative<OutOfService>(state)) return "nothing to service";
        std::ranges::fill(purge_bin, 0);  // a technician empties and counts the purge bin
        state = Idle{};
        return "jam cleared, purge bin reconciled, back in service";
    }
};

// ---- vending: an immutable snapshot and pure transitions; effects run only after the transition commits

const Counts kCoins{25, 10, 5};
const std::array<const char*, 3> kItems{"chips", "soda", "gum"};
const std::array<int, 3> kPrices{75, 60, 35};

struct Ready {};
struct Accepting { int credit; };
struct Broken { std::string reason; };
using Mode = std::variant<Ready, Accepting, Broken>;

std::string show(const Mode& m) {
    return std::visit(overloaded{
                          [](const Ready&) { return std::string("Ready"); },
                          [](const Accepting& a) { return std::format("Accepting({})", a.credit); },
                          [](const Broken& b) { return "Broken(" + b.reason + ")"; },
                      },
                      m);
}

struct Machine { Mode mode; Counts coins, stock; };
struct Step { std::optional<Machine> next; std::vector<std::string> effects; };  // next == nullopt: no state change

Step insert(const Machine& m, sz coin) {
    if (std::holds_alternative<Broken>(m.mode)) return {std::nullopt, {"coin returned (out of service)"}};
    const int credit = std::holds_alternative<Accepting>(m.mode) ? std::get<Accepting>(m.mode).credit : 0;
    Machine n = m;
    ++n.coins[coin];  // the coin drops into its tube immediately
    n.mode = Accepting{credit + kCoins[coin]};
    return {n, {}};
}

Step select(const Machine& m, sz item) {
    const auto* a = std::get_if<Accepting>(&m.mode);
    if (!a) return {std::nullopt, {"insert coins first"}};
    if (m.stock[item] == 0) return {std::nullopt, {std::format("{} sold out", kItems[item])}};
    if (a->credit < kPrices[item]) return {std::nullopt, {std::format("insert {} more", kPrices[item] - a->credit)}};
    const int owed = a->credit - kPrices[item];
    const auto change = dfs(owed, kCoins, m.coins).plan();
    if (!change) return {std::nullopt, {std::format("exact change only: cannot return {}", owed)}};
    Machine n = m;
    for (sz i = 0; i < kCoins.size(); ++i) n.coins[i] -= change->counts[i];
    --n.stock[item];
    n.mode = Ready{};
    return {n, {std::format("drop {}", kItems[item]), std::format("change {}{}", owed, change->pieces > 0 ? " as " + change->show(kCoins) : "")}};
}

Step cancel(const Machine& m) {
    const auto* a = std::get_if<Accepting>(&m.mode);
    if (!a) return {std::nullopt, {"nothing to refund"}};
    const auto back = dfs(a->credit, kCoins, m.coins).plan();  // always exists: the inserted coins are in the tubes
    Machine n = m;
    for (sz i = 0; i < kCoins.size(); ++i) n.coins[i] -= back->counts[i];
    n.mode = Ready{};
    return {n, {std::format("refund {} as {}", a->credit, back->show(kCoins))}};
}

/**
 * Events from the keypad, the coin lever and the service port are serialized: one transition at a time, effects after
 * the commit. (Java CASes an immutable snapshot; libc++ here lacks std::atomic<std::shared_ptr>, see P11. Same contract.)
 */
class Vending {
    std::mutex m_;
    Machine state_;

public:
    explicit Vending(Machine m) : state_(std::move(m)) { std::scoped_lock warm(m_); }
    std::vector<std::string> fire(const std::function<Step(const Machine&)>& event) {
        Step s;
        {
            std::scoped_lock l(m_);
            s = event(state_);
            if (s.next) state_ = std::move(*s.next);
        }
        return s.effects;  // the hardware acts only on a committed transition
    }
    Machine snapshot() {
        std::scoped_lock l(m_);
        return state_;
    }
};

// ---- harness

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

struct Rng {
    u64 s;
    int below(int n) { return static_cast<int>(mix64(s++) % static_cast<u64>(n)); }
};

void pause_spin(int n) {
    for (int k = 0; k < n; ++k) {
#if defined(__x86_64__) || defined(__i386__)
        __builtin_ia32_pause();
#endif
    }
}

/** Two threads released together by a spin gate with a ready count. */
template <class A, class B>
void race(A a, B b) {
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::jthread ta([&] {
        ready.fetch_add(1);
        while (!go.load(std::memory_order_acquire)) {}
        a();
    });
    std::jthread tb([&] {
        ready.fetch_add(1);
        while (!go.load(std::memory_order_acquire)) {}
        b();
    });
    while (ready.load() < 2) {}
    go.store(true, std::memory_order_release);
}

int paid_out(const std::vector<std::string>& effects) {  // value that left the machine: change/refund + item price
    int v = 0;
    for (const auto& e : effects) {
        if (e.starts_with("drop chips")) v += 75;
        if (e.starts_with("change ") || e.starts_with("refund ")) v += std::stoi(e.substr(e.find(' ') + 1));
    }
    return v;
}

std::string join(const std::vector<std::string>& v) {
    std::string s = "[";
    for (const auto& x : v) s += (s.size() > 1 ? ", " : "") + x;
    return s + "]";
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Dispense 60 from cassettes 50x1 20x3 (no 10s, no 100s) ==");
    const Counts c60{0, 1, 3, 0};
    const auto g60 = greedy(60, kNotes, c60);
    const Search d60 = dfs(60, kNotes, c60);
    std::println("  chain of responsibility (greedy): {}", g60 ? g60->show(kNotes) : "FAILED (took 50, nothing can make the last 10)");
    std::println("  backtracking DFS (min notes):     {} ({} notes, {} search nodes)", d60.plan()->show(kNotes), d60.plan()->pieces, d60.nodes);
    std::println("  bounded DP (min notes):           {} notes", dp_min_pieces(60, kNotes, c60));
    const Counts c80{0, 1, 4, 0};
    const auto g80 = greedy(80, kNotes, c80);
    std::println("  80 from 50x1 20x4: greedy {} | DFS {}", g80 ? g80->show(kNotes) : "FAILED", dfs(80, kNotes, c80).plan()->show(kNotes));
    const Counts odd{4, 3, 1}, unlimited{100, 100, 100};
    const auto g_odd = greedy(6, odd, unlimited);
    const auto d_odd = dfs(6, odd, unlimited).plan();
    std::println("  coins {{4,3,1}} unlimited, amount 6: greedy {} ({} coins) | optimal {} ({} coins): greedy is only safe for canonical systems",
                 g_odd->show(odd), g_odd->pieces, d_odd->show(odd), d_odd->pieces);

    std::println("== 2. 100,000 random cassettes (0-5 of each 100/50/20/10) and amounts (10..500) ==");
    Rng r{3};
    int feasible = 0, greedy_failed = 0, greedy_worse = 0, disagree = 0;
    i64 nodes = 0;
    for (int i = 0; i < 100'000; ++i) {
        Counts avail(4);
        for (auto& x : avail) x = r.below(6);
        const int amount = 10 * (1 + r.below(50));
        const int dp = dp_min_pieces(amount, kNotes, avail);
        const Search s = dfs(amount, kNotes, avail);
        const auto g = greedy(amount, kNotes, avail);
        nodes += s.nodes;
        feasible += dp >= 0;
        greedy_failed += dp >= 0 && !g;
        greedy_worse += g && g->pieces > dp;
        disagree += (s.plan() ? s.plan()->pieces : -1) != dp;
    }
    std::println("  feasible {} | greedy failed on {} feasible cases | greedy used extra notes on {} | DFS vs DP disagreements {} | DFS nodes per case {:.1f}",
                 feasible, greedy_failed, greedy_worse, disagree, static_cast<double>(nodes) / 100'000.0);

    std::println("== 3. ATM session; the withdrawal is a saga (reserve notes -> debit -> dispense) ==");
    Bank bank;
    bank.apply("open-alice", "alice", 1'000);
    bank.apply("open-bob", "bob", 500);
    sz jam_after = 2;  // the next dispense jams after 2 notes
    AtmMachine atm({0, 1, 3, 0}, bank, [&](const std::vector<sz>& notes) {
        const sz k = std::min(jam_after, notes.size());
        jam_after = SIZE_MAX;
        return k;
    });
    const std::vector<std::pair<const char*, std::string>> steps{{"insert alice's card", atm.insert_card("alice")},
                                                                 {"PIN 0000", atm.enter_pin("0000")},
                                                                 {"PIN 1234", atm.enter_pin("1234")},
                                                                 {"withdraw 30", atm.withdraw(30)},
                                                                 {"withdraw 60", atm.withdraw(60)}};
    for (const auto& [label, out] : steps) std::println("  {:<28} -> {}", label, out);
    std::println("  after the jam: alice {} (1000 - 40 delivered) | cassettes {} | purge bin {} | state {}", bank.balances["alice"],
                 cassette(kNotes, atm.cassettes), cassette(kNotes, atm.purge_bin), show(atm.state));
    const std::string blocked = atm.insert_card("bob"), serviced = atm.service();
    const std::string bob_in = atm.insert_card("bob"), bob_pin = atm.enter_pin("1234"), bob_out = atm.withdraw(50);
    std::println("  {:<28} -> {}\n  {:<28} -> {}\n  {:<28} -> {}, {}, {} | bob {} | state {}", "bob's card", blocked, "technician", serviced,
                 "bob withdraws 50", bob_in, bob_pin, bob_out, bank.balances["bob"], show(atm.state));

    std::println("== 4. Vending machine: pure transitions over an immutable snapshot ==");
    Vending v(Machine{Ready{}, {2, 0, 0}, {3, 2, 0}});  // tubes: 25x2, no 10s/5s
    std::vector<std::string> lines;
    for (int k = 0; k < 4; ++k) v.fire([](const Machine& m) { return insert(m, 0); });  // four quarters: credit 100
    lines.push_back(std::format("insert 25 x4 -> credit {}", std::get<Accepting>(v.snapshot().mode).credit));
    lines.push_back("select gum   -> " + join(v.fire([](const Machine& m) { return select(m, 2); })));
    lines.push_back("select soda  -> " + join(v.fire([](const Machine& m) { return select(m, 1); })));
    lines.push_back("select chips -> " + join(v.fire([](const Machine& m) { return select(m, 0); })));
    lines.push_back("cancel       -> " + join(v.fire(cancel)));
    v.fire([](const Machine& m) { return insert(m, 0); });
    v.fire([](const Machine& m) { return insert(m, 0); });
    lines.push_back("insert 25 x2, cancel -> " + join(v.fire(cancel)));
    for (const auto& s : lines) std::println("  {}", s);
    const Machine fin = v.snapshot();
    std::println("  tubes 25x{} 10x{} 5x{} | stock chips {} soda {} gum {} | mode {}", fin.coins[0], fin.coins[1], fin.coins[2], fin.stock[0], fin.stock[1],
                 fin.stock[2], show(fin.mode));

    std::println("== 5. 'select chips' and 'coin return' pressed at the same moment, credit 100, 5,000 rounds ==");
    int naive_overpaid = 0, serial_overpaid = 0, serial_both = 0;
    for (int round = 0; round < 5'000; ++round) {
        std::atomic<i64> credit{100}, out{0};
        race(
            [&] {  // naive keypad handler: mutable fields, check then act
                if (credit.load() >= 75) {
                    pause_spin(300);
                    credit.fetch_sub(75);
                    out.fetch_add(75);  // drop the item
                    const i64 change = credit.exchange(0);
                    if (change > 0) out.fetch_add(change);  // return the change
                }
            },
            [&] {  // naive coin-return lever
                const i64 c = credit.load();
                if (c > 0) {
                    pause_spin(300);
                    credit.store(0);
                    out.fetch_add(c);
                }
            });
        naive_overpaid += out.load() > 100;
        Vending vm(Machine{Accepting{100}, {4, 2, 2}, {5, 5, 5}});
        std::vector<std::string> fx0, fx1;
        race([&] { fx0 = vm.fire([](const Machine& m) { return select(m, 0); }); }, [&] { fx1 = vm.fire(cancel); });
        serial_overpaid += paid_out(fx0) + paid_out(fx1) != 100;
        serial_both += paid_out(fx0) > 0 && paid_out(fx1) > 0;
    }
    std::println("  naive mutable state:       rounds paying out more than the 100 inserted: {} of 5000", naive_overpaid);
    std::println("  serialized transitions:    rounds paying out != 100: {} | rounds where both events paid: {}", serial_overpaid, serial_both);

    const bool ok = !g60 && d60.plan()->pieces == 3 && d60.plan()->counts[2] == 3 && dp_min_pieces(60, kNotes, c60) == 3 && !g80 && g_odd->pieces == 3 &&
                    d_odd->pieces == 2 && disagree == 0 && greedy_failed > 0 && bank.balances["alice"] == 960 && atm.cassettes[2] == 0 &&
                    bank.balances["bob"] == 450 && std::holds_alternative<Idle>(atm.state) && blocked.starts_with("rejected") &&
                    lines[2].find("exact change only") != std::string::npos && std::holds_alternative<Ready>(fin.mode) && serial_overpaid == 0 &&
                    serial_both == 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Dispense 60 from cassettes 50x1 20x3 (no 10s, no 100s) ==
  chain of responsibility (greedy): FAILED (took 50, nothing can make the last 10)
  backtracking DFS (min notes):     20x3 (3 notes, 10 search nodes)
  bounded DP (min notes):           3 notes
  80 from 50x1 20x4: greedy FAILED | DFS 20x4
  coins {4,3,1} unlimited, amount 6: greedy 4x1 + 1x2 (3 coins) | optimal 3x2 (2 coins): greedy is only safe for canonical systems
== 2. 100,000 random cassettes (0-5 of each 100/50/20/10) and amounts (10..500) ==
  feasible 69532 | greedy failed on 1647 feasible cases | greedy used extra notes on 0 | DFS vs DP disagreements 0 | DFS nodes per case 24.0
== 3. ATM session; the withdrawal is a saga (reserve notes -> debit -> dispense) ==
  insert alice's card          -> card accepted
  PIN 0000                     -> wrong PIN (1 of 3)
  PIN 1234                     -> authenticated alice
  withdraw 30                  -> rejected: cannot dispense 30 from 100x0 50x1 20x3 10x0; try 20 or 40
  withdraw 60                  -> jam after 2 of 3 notes: refunded 20, 1 note(s) to the purge bin, out of service
  after the jam: alice 960 (1000 - 40 delivered) | cassettes 100x0 50x1 20x0 10x0 | purge bin 100x0 50x0 20x1 10x0 | state OutOfService(dispenser jam)
  bob's card                   -> rejected: out of service (dispenser jam)
  technician                   -> jam cleared, purge bin reconciled, back in service
  bob withdraws 50             -> card accepted, authenticated bob, dispensed 50x1, card returned | bob 450 | state Idle
== 4. Vending machine: pure transitions over an immutable snapshot ==
  insert 25 x4 -> credit 100
  select gum   -> [gum sold out]
  select soda  -> [exact change only: cannot return 40]
  select chips -> [drop chips, change 25 as 25x1]
  cancel       -> [nothing to refund]
  insert 25 x2, cancel -> [refund 50 as 25x2]
  tubes 25x5 10x0 5x0 | stock chips 2 soda 2 gum 0 | mode Ready
== 5. 'select chips' and 'coin return' pressed at the same moment, credit 100, 5,000 rounds ==
  naive mutable state:       rounds paying out more than the 100 inserted: 4990 of 5000
  serialized transitions:    rounds paying out != 100: 0 | rounds where both events paid: 0
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Dispense 60 from cassettes 50x1 20x3 (no 10s, no 100s) ==
  chain of responsibility (greedy): FAILED (took 50, nothing can make the last 10)
  backtracking DFS (min notes):     20x3 (3 notes, 10 search nodes)
  bounded DP (min notes):           3 notes
  80 from 50x1 20x4: greedy FAILED | DFS 20x4
  coins {4,3,1} unlimited, amount 6: greedy 4x1 + 1x2 (3 coins) | optimal 3x2 (2 coins): greedy is only safe for canonical systems
== 2. 100,000 random cassettes (0-5 of each 100/50/20/10) and amounts (10..500) ==
  feasible 69532 | greedy failed on 1647 feasible cases | greedy used extra notes on 0 | DFS vs DP disagreements 0 | DFS nodes per case 24.0
== 3. ATM session; the withdrawal is a saga (reserve notes -> debit -> dispense) ==
  insert alice's card          -> card accepted
  PIN 0000                     -> wrong PIN (1 of 3)
  PIN 1234                     -> authenticated alice
  withdraw 30                  -> rejected: cannot dispense 30 from 100x0 50x1 20x3 10x0; try 20 or 40
  withdraw 60                  -> jam after 2 of 3 notes: refunded 20, 1 note(s) to the purge bin, out of service
  after the jam: alice 960 (1000 - 40 delivered) | cassettes 100x0 50x1 20x0 10x0 | purge bin 100x0 50x0 20x1 10x0 | state OutOfService(dispenser jam)
  bob's card                   -> rejected: out of service (dispenser jam)
  technician                   -> jam cleared, purge bin reconciled, back in service
  bob withdraws 50             -> card accepted, authenticated bob, dispensed 50x1, card returned | bob 450 | state Idle
== 4. Vending machine: pure transitions over an immutable snapshot ==
  insert 25 x4 -> credit 100
  select gum   -> [gum sold out]
  select soda  -> [exact change only: cannot return 40]
  select chips -> [drop chips, change 25 as 25x1]
  cancel       -> [nothing to refund]
  insert 25 x2, cancel -> [refund 50 as 25x2]
  tubes 25x5 10x0 5x0 | stock chips 2 soda 2 gum 0 | mode Ready
== 5. 'select chips' and 'coin return' pressed at the same moment, credit 100, 5,000 rounds ==
  naive mutable state:       rounds paying out more than the 100 inserted: 4992 of 5000
  serialized transitions:    rounds paying out != 100: 0 | rounds where both events paid: 0
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| States | `int state` + `if` ladders | GoF State classes with mutable context | Sealed states carrying their own data; pure transitions; illegal actions return a reason rather than throwing |
| Change | Greedy | Chain of Responsibility (still greedy) | Backtracking or bounded DP with counts; a property test vs DP; nearest feasible amounts offered |
| Failure handling | `try/catch` | "Rollback" by reversing fields | Saga ordered by reversibility, with idempotent compensations; purge bin + out-of-service for reconciliation |
| Concurrency | "It's one user" | `synchronized` handlers | Events from several sources committed one at a time (CAS or actor), effects after commit, no double payout |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Prefer fewer 20s; keep them for small withdrawals" | Change the DFS objective: lexicographic (pieces, then weighted use of scarce notes), or a cost per denomination in the DP |
| "Customer can choose the note mix" | Validate the requested mix against the cassettes; fall back to a DFS plan |
| "Daily withdrawal limit" | Another saga step: reserve against the limit (an idempotent hold) before the debit, release on failure |
| "Network down mid-withdrawal" | The debit is idempotent by tx id: retry it. If it can't be confirmed, don't dispense, and reconcile later from the bank's journal |
| "Remote service mode while a customer is mid-session" | It's another event in the same serialized stream. The transition from `Dispensing` defers to the end of the dispense; from `Accepting` it refunds first |
| "Coins can be inserted faster than we process them" | Bounded event queue (P12's ring); the coin acceptor rejects coins when it's full, so no coin is ever eaten |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Dispense $60. The machine has one 50 and three 20s."</b></summary>

**L5:** "Chain of Responsibility: 50 handler, then 20 handler…"

**Why it fails:** the chain is greedy. It takes the 50 and can't make 10. Over random cassettes it fails on 2.4% of feasible amounts.

**L7 defence:** "Backtracking over denominations with counts, pruned by a lower bound on pieces, or a bounded DP. I keep the handler abstraction for extensibility, but search instead of committing to the first choice. I check DFS against DP on 100,000 random cases, and on infeasible amounts I offer the nearest feasible ones before any money moves."
</details>

<details>
<summary><b>Q2 ⚡ "The dispenser jams after two notes. What's the state of the world?"</b></summary>

**L5:** "Roll back the transaction."

**Why it fails:** two notes are physically gone. You can't un-dispense them.

**L7 defence:** "It's a saga ordered by reversibility: reserve, debit, then dispense last. On a jam, compensate only what didn't happen: refund the undelivered value idempotently, send stuck notes to the purge bin, go out of service, and reconcile with a physical count. The customer pays exactly for what left the machine."
</details>

<details>
<summary><b>Q3 ⚡ "It's one machine. Why would you need concurrency control?"</b></summary>

**L5:** "One user at a time."

**Why it fails:** the keypad, the coin lever, sensors and remote service are separate event sources. Measured: 4,988–4,992 of 5,000 rounds paid out both the item and a full refund.

**L7 defence:** "Pure transitions over an immutable snapshot, committed one at a time (CAS or an actor), with hardware effects run only for the committed transition. The loser re-evaluates against the new state and becomes a no-op."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| "Cannot dispense" while notes are available | Greedy chain | DFS / bounded DP |
| Customer debited for notes never received | Debit and dispense not compensated | Saga with an idempotent refund of the undelivered value |
| Free money after a crash | Dispense before debit | Order steps by reversibility |
| Item **and** refund | Concurrent handlers on mutable fields | Committed pure transitions; effects after commit |
| Machine accepts coins it can't change | No exact-change check | DFS on the tubes before committing; exact-change-only mode |

- [ ] Sealed states carrying their data; transitions are pure functions.
- [ ] Change by search/DP with counts, cross-checked; nearest feasible amounts.
- [ ] Saga: reversible steps first, irreversible last, idempotent compensations.
- [ ] Event sources serialized; effects only for committed transitions.

## 10. References

- Kozen and Zaks, *Optimal bounds for the change-making problem* (when greedy is optimal). <https://doi.org/10.1016/0304-3975(94)90230-5>
- Garcia-Molina and Salem, *Sagas* (SIGMOD 1987). <https://doi.org/10.1145/38713.38742>
- Refactoring.Guru, *State* and *Chain of Responsibility*. <https://refactoring.guru/design-patterns/state> · <https://refactoring.guru/design-patterns/chain-of-responsibility>
- In this KB: [02.1 State machines: enum vs sealed](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/01-state-machines-enum-vs-sealed-types-and-optimistic-transitions.md) · [02.2 Chain of Responsibility](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md) · [P13 Idempotent ledger](03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md)
