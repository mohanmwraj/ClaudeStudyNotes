# P19 · Chess and Snakes & Ladders: Command Undo That Perft Proves Correct, Per-Piece Rules, Checkmate, and Board Validation

> **Folder 06 · Problem 19 of 20.** Board games test whether "Command pattern with undo" is real or decorative.
>
> In chess, undo must restore what the move itself doesn't encode:
> - a pawn captured **en passant** on a *different* square;
> - the **pawn** that became a queen;
> - **castling rights**, the **en-passant square**, and the rook that castled.
>
> One bug in any of these is invisible in a demo game, but **perft** (counting every leaf of the move tree) exposes it. This listing matches the published counts for the start position and the castling/en-passant/promotion stress position "Kiwipete".
>
> **Listing pair P19:** `BoardGames.java` / `board_games.cpp`. Sections 1, 2 and 5 are deterministic and **byte-identical in Java, GCC and Clang**; sections 3–4 show one measured run.

---

## 1. Problem and scope

**Chess:**
- Legal moves for all pieces, including castling, en passant and all four promotions.
- Check, checkmate and stalemate.
- A game with `play / undo / redo`; illegal moves rejected.

**Snakes & ladders:**
- A configurable board validated before play (no cycles, no jump from the finish).
- An exact-finish rule; seeded dice.

**Server:** many games, each mutated by clients that may double-submit.

**Out of scope:** draw rules (50-move, repetition: a Zobrist hash + counter), SAN notation, engines and search.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Move (the command) | `record Move(from, to, promo, flags)`, flags `EP`, `CASTLE`, `DOUBLE` | `struct Move` |
| Undo memento | `record Undo(move, moved, captured, capturedSq, castling, ep)` | `struct Undo` |
| Rules (strategies) | `EnumMap<Kind, MoveRule>`: one lambda per piece kind, pseudo-legal only | `std::array<MoveRule, 6>` of function pointers |
| Legality | `legal()`: `execute` → is my king attacked? → `undo`, centrally | the same |
| History | `Game`: `done` (mementos), `undone` (moves); a new move clears redo | the same |
| Snakes & ladders | `validate(size, jumps)` → `Optional<String>`; `resolve` follows chains | `std::optional<std::string>`; `std::map` |

**Invariants:**
- **I1:** `undo(execute(m))` restores the position exactly. It is checked by hashing before and after every perft, and implied by perft matching published counts.
- **I2:** a move is legal iff it's pseudo-legal for its piece **and** doesn't leave the mover's king attacked. Castling additionally requires the king's start and transit squares to be unattacked.
- **I3:** redo is only valid along the undone line. A new move clears it.
- **I4:** a snakes & ladders board terminates: jump chains are acyclic and nothing jumps from the last square.
- **I5:** at most one move is applied per ply, however clients interleave.

## 3. Concurrency and contention analysis

### 3.1 Perft is the test oracle for undo

| Position | Depth 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Start (`rnbqkbnr/…`) | 20 | 400 | 8,902 | 197,281 |
| Kiwipete (`r3k2r/p1ppqpb1/…`) | 48 | 2,039 | 97,862 | n/a |

Every count matches the published value. Kiwipete has both sides castling either way, en-passant chances and promotions. A memento that forgets `capturedSq` (en passant), `moved` (promotion) or `castling` changes these numbers within three plies.

**Why central legality:** piece rules generate *pseudo-legal* moves (geometry only). Legality is one place: `execute`, check whether my king is attacked, `undo`. Adding a fairy piece is a new rule; king safety is untouched.

### 3.2 Parallel search: share nothing

`execute`/`undo` mutate the board, so a board is single-writer by construction. **Parallel perft(5)** splits the 20 root moves over 8 threads, each task getting its **own board copy**:
- 4,865,609 nodes, equal to the sequential count;
- **3.5–3.9× speedup** in all three builds (Java 480 → 124 ms; GCC 358 → 95 ms).

Sharing one board, even with a lock, would serialize the whole search.

### 3.3 The double submit: one critical section per ply

Two clients each submit a white move "for ply 0" at the same instant.

| Server | Java | GCC | Clang |
|---|---|---|---|
| `validate()` (locked), ~1 µs of other work, then `apply()` (locked again) | **4,964** of 5,000 rounds White moved twice | **4,963** | **4,963** |
| `submit(expectedPly, move)`: check + apply in one critical section | 0 | 0 | 0 |

**What the C++ run taught.** Without the 1 µs gap, C++ showed only 1–2 bad rounds. The validating thread re-acquired `std::mutex` immediately ("barging") and usually won. The bug was still there; the scheduler was hiding it. Real servers have work between "check" and "apply" (an audit write, a rules call), which is why the listing includes one.

**The fix is the expected-ply token.** A stale client gets "stale: ply is now 1" and refreshes. That is optimistic concurrency, the same pattern as an HTTP `If-Match` ETag.

## 4. Java 21 implementation

```java
// BoardGames.java - P19: chess with command undo/redo (perft-verified), per-piece move rules, checkmate; snakes & ladders validation
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.EnumMap;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

public final class BoardGames {

    // ---- chess: squares 0..63 (a1 = 0, h8 = 63); pieces +1..+6 white (P N B R Q K), -1..-6 black

    static final int P = 1, N = 2, B = 3, R = 4, Q = 5, K = 6;
    static final int EP = 1, CASTLE = 2, DOUBLE = 4;                    // move flags
    static final int WK = 1, WQ = 2, BK = 4, BQ = 8;                    // castling rights

    record Move(int from, int to, int promo, int flags) {
        String uci() {
            return sq(from) + sq(to) + (promo == 0 ? "" : String.valueOf("  nbrq".charAt(Math.abs(promo))));
        }
    }

    /** Everything execute() changed that the move itself doesn't say: the command's undo memento. */
    record Undo(Move move, int moved, int captured, int capturedSq, int castling, int ep) {}

    static String sq(int s) {
        return "" + (char) ('a' + s % 8) + (char) ('1' + s / 8);
    }

    enum Kind { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING }

    /** One strategy per piece kind: generates pseudo-legal moves; legality (king safety) is checked once, centrally. */
    @FunctionalInterface
    interface MoveRule {
        void generate(Board b, int from, List<Move> out);
    }

    static final int[] KNIGHT = {17, 15, 10, 6, -6, -10, -15, -17}, KING_STEPS = {1, -1, 8, -8, 9, 7, -7, -9};
    static final int[] ORTHO = {1, -1, 8, -8}, DIAG = {9, 7, -7, -9};

    static boolean onBoardStep(int from, int to) {                     // rejects wrap-around across the a/h files
        return to >= 0 && to < 64 && Math.abs(to % 8 - from % 8) <= 2;
    }

    static void slide(Board b, int from, int[] dirs, List<Move> out) {
        for (int d : dirs)
            for (int to = from + d; onBoardStep(to - d, to) && Math.abs(to % 8 - (to - d) % 8) <= 1; to += d) {
                if (b.sq[to] * b.side > 0) break;                      // own piece
                out.add(new Move(from, to, 0, 0));
                if (b.sq[to] != 0) break;                              // capture ends the ray
            }
    }

    static final EnumMap<Kind, MoveRule> RULES = new EnumMap<>(Kind.class);

    static {
        RULES.put(Kind.PAWN, (b, from, out) -> {
            int dir = 8 * b.side, start = b.side > 0 ? 1 : 6, last = b.side > 0 ? 7 : 0, to = from + dir;
            if (b.sq[to] == 0) {
                addPawn(from, to, last, 0, out);
                if (from / 8 == start && b.sq[to + dir] == 0) out.add(new Move(from, to + dir, 0, DOUBLE));
            }
            for (int df : new int[]{-1, 1}) {
                int file = from % 8 + df;
                if (file < 0 || file > 7) continue;
                int t = to + df;
                if (b.sq[t] * b.side < 0) addPawn(from, t, last, 0, out);
                else if (t == b.ep) out.add(new Move(from, t, 0, EP));
            }
        });
        RULES.put(Kind.KNIGHT, (b, from, out) -> {
            for (int d : KNIGHT) {
                int to = from + d;
                if (onBoardStep(from, to) && b.sq[to] * b.side <= 0) out.add(new Move(from, to, 0, 0));
            }
        });
        RULES.put(Kind.BISHOP, (b, from, out) -> slide(b, from, DIAG, out));
        RULES.put(Kind.ROOK, (b, from, out) -> slide(b, from, ORTHO, out));
        RULES.put(Kind.QUEEN, (b, from, out) -> {
            slide(b, from, ORTHO, out);
            slide(b, from, DIAG, out);
        });
        RULES.put(Kind.KING, (b, from, out) -> {
            for (int d : KING_STEPS) {
                int to = from + d;
                if (to >= 0 && to < 64 && Math.abs(to % 8 - from % 8) <= 1 && b.sq[to] * b.side <= 0) out.add(new Move(from, to, 0, 0));
            }
            int home = b.side > 0 ? 4 : 60, kSide = b.side > 0 ? WK : BK, qSide = b.side > 0 ? WQ : BQ;
            if (from != home || b.attacked(home, -b.side)) return;
            if ((b.castling & kSide) != 0 && b.sq[home + 1] == 0 && b.sq[home + 2] == 0 && !b.attacked(home + 1, -b.side) && !b.attacked(home + 2, -b.side))
                out.add(new Move(from, home + 2, 0, CASTLE));
            if ((b.castling & qSide) != 0 && b.sq[home - 1] == 0 && b.sq[home - 2] == 0 && b.sq[home - 3] == 0 && !b.attacked(home - 1, -b.side)
                    && !b.attacked(home - 2, -b.side))
                out.add(new Move(from, home - 2, 0, CASTLE));
        });
    }

    static void addPawn(int from, int to, int lastRank, int flags, List<Move> out) {
        if (to / 8 != lastRank) {
            out.add(new Move(from, to, 0, flags));
            return;
        }
        int sign = lastRank == 7 ? 1 : -1;
        for (int promo : new int[]{Q, R, B, N}) out.add(new Move(from, to, promo * sign, flags));
    }

    static final class Board {
        final int[] sq = new int[64];
        int side = 1, castling, ep = -1;
        final int[] king = new int[2];                                 // [0] white, [1] black

        Board copy() {
            Board c = new Board();
            System.arraycopy(sq, 0, c.sq, 0, 64);
            c.side = side;
            c.castling = castling;
            c.ep = ep;
            c.king[0] = king[0];
            c.king[1] = king[1];
            return c;
        }

        static Board fen(String fen) {
            Board b = new Board();
            String[] f = fen.split(" ");
            int rank = 7, file = 0;
            for (char c : f[0].toCharArray()) {
                if (c == '/') {
                    rank--;
                    file = 0;
                } else if (Character.isDigit(c)) {
                    file += c - '0';
                } else {
                    int kind = "pnbrqk".indexOf(Character.toLowerCase(c)) + 1;
                    int s = rank * 8 + file++;
                    b.sq[s] = Character.isUpperCase(c) ? kind : -kind;
                    if (kind == K) b.king[Character.isUpperCase(c) ? 0 : 1] = s;
                }
            }
            b.side = f[1].equals("w") ? 1 : -1;
            for (char c : f[2].toCharArray()) b.castling |= switch (c) {
                case 'K' -> WK;
                case 'Q' -> WQ;
                case 'k' -> BK;
                case 'q' -> BQ;
                default -> 0;
            };
            b.ep = f[3].equals("-") ? -1 : (f[3].charAt(1) - '1') * 8 + (f[3].charAt(0) - 'a');
            return b;
        }

        boolean attacked(int s, int by) {
            int pawnFrom = s - 8 * by;                                 // a pawn of `by` attacks diagonally forward
            for (int df : new int[]{-1, 1}) {
                int f = s % 8 + df, from = pawnFrom + df;
                if (f >= 0 && f <= 7 && from >= 0 && from < 64 && sq[from] == P * by) return true;
            }
            for (int d : KNIGHT)
                if (onBoardStep(s, s + d) && sq[s + d] == N * by) return true;
            for (int d : KING_STEPS) {
                int t = s + d;
                if (t >= 0 && t < 64 && Math.abs(t % 8 - s % 8) <= 1 && sq[t] == K * by) return true;
            }
            return ray(s, ORTHO, R * by, Q * by) || ray(s, DIAG, B * by, Q * by);
        }

        boolean ray(int s, int[] dirs, int a, int b) {
            for (int d : dirs)
                for (int t = s + d; t >= 0 && t < 64 && Math.abs(t % 8 - (t - d) % 8) <= 1; t += d) {
                    if (sq[t] == a || sq[t] == b) return true;
                    if (sq[t] != 0) break;
                }
            return false;
        }

        List<Move> pseudoLegal() {
            List<Move> out = new ArrayList<>(64);
            for (int s = 0; s < 64; s++)
                if (sq[s] * side > 0) RULES.get(Kind.values()[Math.abs(sq[s]) - 1]).generate(this, s, out);
            return out;
        }

        /** The command's execute(): applies the move and returns the memento that undoes it exactly. */
        Undo execute(Move m) {
            int moved = sq[m.from()], dir = 8 * side;
            int capturedSq = (m.flags() & EP) != 0 ? m.to() - dir : m.to();
            Undo u = new Undo(m, moved, sq[capturedSq], capturedSq, castling, ep);
            sq[capturedSq] = 0;
            sq[m.to()] = m.promo() != 0 ? m.promo() : moved;
            sq[m.from()] = 0;
            if ((m.flags() & CASTLE) != 0) {                           // the rook moves too
                int rookFrom = m.to() > m.from() ? m.to() + 1 : m.to() - 2, rookTo = m.to() > m.from() ? m.to() - 1 : m.to() + 1;
                sq[rookTo] = sq[rookFrom];
                sq[rookFrom] = 0;
            }
            if (Math.abs(moved) == K) {
                king[side > 0 ? 0 : 1] = m.to();
                castling &= side > 0 ? ~(WK | WQ) : ~(BK | BQ);
            }
            for (int s : new int[]{m.from(), m.to()})                  // a rook moving or being captured loses its right
                castling &= switch (s) {
                    case 0 -> ~WQ;
                    case 7 -> ~WK;
                    case 56 -> ~BQ;
                    case 63 -> ~BK;
                    default -> ~0;
                };
            ep = (m.flags() & DOUBLE) != 0 ? m.from() + dir : -1;
            side = -side;
            return u;
        }

        void undo(Undo u) {
            side = -side;
            Move m = u.move();
            sq[m.from()] = u.moved();
            sq[m.to()] = 0;
            sq[u.capturedSq()] = u.captured();
            if ((m.flags() & CASTLE) != 0) {
                int rookFrom = m.to() > m.from() ? m.to() + 1 : m.to() - 2, rookTo = m.to() > m.from() ? m.to() - 1 : m.to() + 1;
                sq[rookFrom] = sq[rookTo];
                sq[rookTo] = 0;
            }
            if (Math.abs(u.moved()) == K) king[side > 0 ? 0 : 1] = m.from();
            castling = u.castling();
            ep = u.ep();
        }

        List<Move> legal() {
            List<Move> out = new ArrayList<>();
            for (Move m : pseudoLegal()) {
                Undo u = execute(m);
                if (!attacked(king[side > 0 ? 1 : 0], side)) out.add(m);  // the side that just moved must not be in check
                undo(u);
            }
            return out;
        }

        String status() {
            boolean inCheck = attacked(king[side > 0 ? 0 : 1], -side);
            boolean none = legal().isEmpty();
            return none ? (inCheck ? "checkmate" : "stalemate") : inCheck ? "check" : "ok";
        }

        long perft(int depth) {
            List<Move> moves = legal();
            if (depth == 1) return moves.size();                       // bulk counting at the leaves
            long n = 0;
            for (Move m : moves) {
                Undo u = execute(m);
                n += perft(depth - 1);
                undo(u);
            }
            return n;
        }

        long hash() {
            long h = side * 31L + castling * 7L + ep;
            for (int s = 0; s < 64; s++) h = mix64(h ^ (sq[s] + 7L) * (s + 1));
            return h;
        }
    }

    /** Command history: undo pops a memento, redo re-executes the move. A new move clears the redo stack. */
    static final class Game {
        final Board board = Board.fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        final Deque<Undo> done = new ArrayDeque<>();
        final Deque<Move> undone = new ArrayDeque<>();

        String play(String uci) {
            for (Move m : board.legal())
                if (m.uci().equals(uci)) {
                    done.push(board.execute(m));
                    undone.clear();
                    return board.status();
                }
            return "illegal";
        }

        boolean undo() {
            if (done.isEmpty()) return false;
            Undo u = done.pop();
            board.undo(u);
            undone.push(u.move());
            return true;
        }

        boolean redo() {
            if (undone.isEmpty()) return false;
            done.push(board.execute(undone.pop()));
            return true;
        }
    }

    // ---- snakes & ladders: the board is data; validation rejects boards that can't terminate

    static Optional<String> validate(int size, Map<Integer, Integer> unordered) {
        TreeMap<Integer, Integer> jumps = new TreeMap<>(unordered);    // Map.of iteration order changes per JVM run: sort first
        for (var j : jumps.entrySet()) {
            int from = j.getKey(), to = j.getValue();
            if (from < 1 || from >= size) return Optional.of("jump from " + from + ": only squares 1.." + (size - 1) + " may jump");
            if (to < 1 || to > size || to == from) return Optional.of("jump " + from + "->" + to + " is out of range or a no-op");
        }
        for (int start : jumps.keySet()) {                             // chains are allowed; cycles never terminate
            Set<Integer> seen = new HashSet<>();
            for (Integer s = start; s != null; s = jumps.get(s))
                if (!seen.add(s)) return Optional.of("jumps form a cycle through " + s);
        }
        return Optional.empty();
    }

    static int resolve(int pos, Map<Integer, Integer> jumps) {
        for (Integer next = jumps.get(pos); next != null; next = jumps.get(pos)) pos = next;
        return pos;
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

    static final String START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    static final String KIWIPETE = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";

    /** A game behind a lock; a client submits a move for the ply it saw. */
    static final class GameServer {
        final Game game = new Game();
        int ply;                                                       // guarded by this

        synchronized boolean validate(int expectedPly, String uci) {
            return ply == expectedPly && game.board.legal().stream().anyMatch(m -> m.uci().equals(uci));
        }

        synchronized void apply(String uci) {
            game.play(uci);
            ply++;
        }

        synchronized String submit(int expectedPly, String uci) {      // check and act in ONE critical section
            if (ply != expectedPly) return "stale: ply is now " + ply;
            String s = game.play(uci);
            if (!s.equals("illegal")) ply++;
            return s;
        }
    }

    static void gap() {                                                // ~1 us of work between the two critical sections
        for (int i = 0; i < 300; i++) Thread.onSpinWait();
    }

    static void race(Runnable a, Runnable b) throws InterruptedException {
        AtomicInteger ready = new AtomicInteger();
        AtomicBoolean go = new AtomicBoolean();
        CountDownLatch done = new CountDownLatch(2);
        for (Runnable r : List.of(a, b))
            Thread.ofPlatform().start(() -> {
                ready.incrementAndGet();
                while (!go.get()) Thread.onSpinWait();
                r.run();
                done.countDown();
            });
        while (ready.get() < 2) Thread.onSpinWait();
        go.set(true);
        done.await();
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Perft: move generation + execute/undo checked against published node counts ==");
        long[] startExpected = {20, 400, 8_902, 197_281}, kiwiExpected = {48, 2_039, 97_862};
        boolean perftOk = true;
        for (int pos = 0; pos < 2; pos++) {
            Board b = Board.fen(pos == 0 ? START : KIWIPETE);
            long before = b.hash();
            long[] exp = pos == 0 ? startExpected : kiwiExpected;
            StringBuilder line = new StringBuilder();
            for (int d = 1; d <= exp.length; d++) {
                long n = b.perft(d);
                perftOk &= n == exp[d - 1];
                line.append(String.format("d%d %d%s  ", d, n, n == exp[d - 1] ? "" : " (expected " + exp[d - 1] + ")"));
            }
            perftOk &= b.hash() == before;
            System.out.printf("  %-9s %s| position restored after every undo: %b%n", pos == 0 ? "start:" : "kiwipete:", line, b.hash() == before);
        }

        System.out.println("== 2. A game: scholar's mate, undo, redo, illegal moves ==");
        Game g = new Game();
        List<String> log = new ArrayList<>();
        for (String mv : List.of("e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7")) log.add(mv + " " + g.play(mv));
        System.out.println("  " + String.join(" | ", log));
        boolean undone = g.undo();
        String afterUndo = g.board.status();
        String alt = g.play("h5f3");                                    // a different move clears the redo stack
        boolean redoAfterNewMove = g.redo();
        g.undo();
        g.undone.clear();
        String again = g.play("h5f7");
        boolean u2 = g.undo(), r2 = g.redo();
        String afterRedo = g.board.status();
        System.out.printf("  undo Qxf7: %b -> %s | play h5f3 instead: %s | redo now: %b | back to Qxf7: %s | undo %b + redo %b -> %s%n", undone, afterUndo, alt,
                redoAfterNewMove, again, u2, r2, afterRedo);
        Game e = new Game();
        System.out.printf("  e2e5 -> %s | e1e2 (king into own pawn) -> %s | e7e5 (black on white's turn) -> %s%n", e.play("e2e5"), e.play("e1e2"),
                e.play("e7e5"));
        Board stale = Board.fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1");
        System.out.println("  black to move, Kh8 vs Qf7 Kg6: " + stale.status());

        System.out.println("== 3. Parallel perft(5) from the start: one board copy per root move (share nothing) ==");
        Board root = Board.fen(START);
        long t0 = System.nanoTime();
        long seq = root.perft(5);
        long seqMs = (System.nanoTime() - t0) / 1_000_000;
        ExecutorService pool = Executors.newFixedThreadPool(8);
        t0 = System.nanoTime();
        List<Future<Long>> parts = new ArrayList<>();
        for (Move m : root.legal()) {
            Board copy = root.copy();                                  // each task owns its board: execute/undo mutate it
            copy.execute(m);
            parts.add(pool.submit(() -> copy.perft(4)));
        }
        long par = 0;
        for (Future<Long> f : parts) par += f.get();
        long parMs = (System.nanoTime() - t0) / 1_000_000;
        pool.shutdown();
        System.out.printf("  sequential %d nodes in %d ms | 8 threads %d nodes in %d ms (%.1fx) | expected 4865609%n", seq, seqMs, par, parMs,
                (double) seqMs / Math.max(1, parMs));

        System.out.println("== 4. Two clients submit a white move for ply 0 at the same moment, 5,000 rounds ==");
        int naiveDouble = 0, safeDouble = 0;
        for (int round = 0; round < 5_000; round++) {
            GameServer s = new GameServer();
            race(() -> {
                if (s.validate(0, "e2e4")) {                            // validate, release the lock...
                    gap();                                              // ...write an audit row / call a rules service...
                    s.apply("e2e4");                                    // ...then apply
                }
            }, () -> {
                if (s.validate(0, "d2d4")) {
                    gap();
                    s.apply("d2d4");
                }
            });
            if (s.ply == 2) naiveDouble++;
            GameServer t = new GameServer();
            race(() -> t.submit(0, "e2e4"), () -> t.submit(0, "d2d4"));
            if (t.ply == 2) safeDouble++;
        }
        System.out.printf("  validate, then apply (two critical sections): white moved twice in %d of 5000 rounds%n", naiveDouble);
        System.out.printf("  submit(expectedPly, move) in one critical section: white moved twice in %d of 5000 rounds%n", safeDouble);

        System.out.println("== 5. Snakes & ladders: validate the board, then 100,000 seeded 2-player games ==");
        Map<Integer, Integer> classic = new HashMap<>();
        int[][] pairs = {{1, 38}, {4, 14}, {9, 31}, {21, 42}, {28, 84}, {36, 44}, {51, 67}, {71, 91}, {80, 100}, {16, 6}, {47, 26}, {49, 11}, {56, 53},
                {62, 19}, {64, 60}, {87, 24}, {93, 73}, {95, 75}, {98, 78}};
        for (int[] p : pairs) classic.put(p[0], p[1]);
        System.out.println("  classic board: " + validate(100, classic).orElse("valid"));
        System.out.println("  {50->20, 20->50}: " + validate(100, Map.of(50, 20, 20, 50)).orElse("valid"));
        System.out.println("  {100->5}: " + validate(100, Map.of(100, 5)).orElse("valid"));
        System.out.println("  {30->40, 40->70} (a chain): " + validate(100, Map.of(30, 40, 40, 70)).orElse("valid") + ", 30 resolves to "
                + resolve(30, Map.of(30, 40, 40, 70)));
        Rng dice = new Rng(19);
        long totalRounds = 0;
        int longest = 0, firstWins = 0;
        for (int game = 0; game < 100_000; game++) {
            int[] pos = new int[2];
            int rounds = 0, winner = -1;
            while (winner < 0) {
                rounds++;
                for (int p = 0; p < 2 && winner < 0; p++) {
                    int roll = 1 + dice.below(6);
                    if (pos[p] + roll <= 100) pos[p] = resolve(pos[p] + roll, classic);   // exact finish: overshoot = stay
                    if (pos[p] == 100) winner = p;
                }
            }
            totalRounds += rounds;
            longest = Math.max(longest, rounds);
            if (winner == 0) firstWins++;
        }
        System.out.printf("  average rounds %.3f | longest %d | first player wins %.2f%%%n", totalRounds / 100_000.0, longest, firstWins / 1_000.0);

        boolean ok = perftOk && log.getLast().endsWith("checkmate") && undone && afterUndo.equals("ok") && !redoAfterNewMove && again.equals("checkmate")
                && afterRedo.equals("checkmate") && stale.status().equals("stalemate") && seq == 4_865_609 && par == seq && safeDouble == 0
                && validate(100, classic).isEmpty() && validate(100, Map.of(50, 20, 20, 50)).isPresent();
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1, 2 and 5 deterministic; 3–4 one measured run):**

```text
== 1. Perft: move generation + execute/undo checked against published node counts ==
  start:    d1 20  d2 400  d3 8902  d4 197281  | position restored after every undo: true
  kiwipete: d1 48  d2 2039  d3 97862  | position restored after every undo: true
== 2. A game: scholar's mate, undo, redo, illegal moves ==
  e2e4 ok | e7e5 ok | f1c4 ok | b8c6 ok | d1h5 ok | g8f6 ok | h5f7 checkmate
  undo Qxf7: true -> ok | play h5f3 instead: ok | redo now: false | back to Qxf7: checkmate | undo true + redo true -> checkmate
  e2e5 -> illegal | e1e2 (king into own pawn) -> illegal | e7e5 (black on white's turn) -> illegal
  black to move, Kh8 vs Qf7 Kg6: stalemate
== 3. Parallel perft(5) from the start: one board copy per root move (share nothing) ==
  sequential 4865609 nodes in 480 ms | 8 threads 4865609 nodes in 124 ms (3.9x) | expected 4865609
== 4. Two clients submit a white move for ply 0 at the same moment, 5,000 rounds ==
  validate, then apply (two critical sections): white moved twice in 4964 of 5000 rounds
  submit(expectedPly, move) in one critical section: white moved twice in 0 of 5000 rounds
== 5. Snakes & ladders: validate the board, then 100,000 seeded 2-player games ==
  classic board: valid
  {50->20, 20->50}: jumps form a cycle through 20
  {100->5}: jump from 100: only squares 1..99 may jump
  {30->40, 40->70} (a chain): valid, 30 resolves to 70
  average rounds 26.342 | longest 170 | first player wins 50.81%
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// board_games.cpp - P19: chess with command undo/redo (perft-verified), per-piece move rules, checkmate; snakes & ladders validation
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <format>
#include <map>
#include <mutex>
#include <optional>
#include <print>
#include <set>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;

// ---- chess: squares 0..63 (a1 = 0, h8 = 63); pieces +1..+6 white (P N B R Q K), -1..-6 black

constexpr int P = 1, N = 2, B = 3, R = 4, Q = 5, K = 6;
constexpr int EP = 1, CASTLE = 2, DOUBLE = 4;  // move flags
constexpr int WK = 1, WQ = 2, BK = 4, BQ = 8;  // castling rights

std::string sq(int s) { return {static_cast<char>('a' + s % 8), static_cast<char>('1' + s / 8)}; }

struct Move {
    int from, to, promo, flags;
    std::string uci() const { return sq(from) + sq(to) + (promo == 0 ? "" : std::string(1, "  nbrq"[std::abs(promo)])); }
};

/** Everything execute() changed that the move itself doesn't say: the command's undo memento. */
struct Undo { Move move; int moved, captured, captured_sq, castling, ep; };

constexpr std::array<int, 8> kKnight{17, 15, 10, 6, -6, -10, -15, -17}, kKingSteps{1, -1, 8, -8, 9, 7, -7, -9};
constexpr std::array<int, 4> kOrtho{1, -1, 8, -8}, kDiag{9, 7, -7, -9};

constexpr bool on_board_step(int from, int to) { return to >= 0 && to < 64 && std::abs(to % 8 - from % 8) <= 2; }  // no a/h wrap-around

struct Board;
/** One strategy per piece kind: generates pseudo-legal moves; legality (king safety) is checked once, centrally. */
using MoveRule = void (*)(const Board&, int from, std::vector<Move>& out);

struct Board {
    std::array<int, 64> squares{};
    int side = 1, castling = 0, ep = -1;
    std::array<int, 2> king{};  // [0] white, [1] black

    static Board fen(std::string_view fen);
    bool attacked(int s, int by) const;
    bool ray(int s, const std::array<int, 4>& dirs, int a, int b) const;
    std::vector<Move> pseudo_legal() const;
    Undo execute(const Move& m);
    void undo(const Undo& u);
    std::vector<Move> legal();
    std::string status();
    i64 perft(int depth);
    u64 hash() const;
};

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

void slide(const Board& b, int from, const std::array<int, 4>& dirs, std::vector<Move>& out) {
    for (const int d : dirs)
        for (int to = from + d; on_board_step(to - d, to) && std::abs(to % 8 - (to - d) % 8) <= 1; to += d) {
            if (b.squares[static_cast<sz>(to)] * b.side > 0) break;  // own piece
            out.push_back({from, to, 0, 0});
            if (b.squares[static_cast<sz>(to)] != 0) break;  // capture ends the ray
        }
}

void add_pawn(int from, int to, int last_rank, int flags, std::vector<Move>& out) {
    if (to / 8 != last_rank) {
        out.push_back({from, to, 0, flags});
        return;
    }
    const int sign = last_rank == 7 ? 1 : -1;
    for (const int promo : {Q, R, B, N}) out.push_back({from, to, promo * sign, flags});
}

void pawn_rule(const Board& b, int from, std::vector<Move>& out) {
    const int dir = 8 * b.side, start = b.side > 0 ? 1 : 6, last = b.side > 0 ? 7 : 0, to = from + dir;
    if (b.squares[static_cast<sz>(to)] == 0) {
        add_pawn(from, to, last, 0, out);
        if (from / 8 == start && b.squares[static_cast<sz>(to + dir)] == 0) out.push_back({from, to + dir, 0, DOUBLE});
    }
    for (const int df : {-1, 1}) {
        const int file = from % 8 + df;
        if (file < 0 || file > 7) continue;
        const int t = to + df;
        if (b.squares[static_cast<sz>(t)] * b.side < 0) add_pawn(from, t, last, 0, out);
        else if (t == b.ep) out.push_back({from, t, 0, EP});
    }
}

void knight_rule(const Board& b, int from, std::vector<Move>& out) {
    for (const int d : kKnight)
        if (const int to = from + d; on_board_step(from, to) && b.squares[static_cast<sz>(to)] * b.side <= 0) out.push_back({from, to, 0, 0});
}
void bishop_rule(const Board& b, int from, std::vector<Move>& out) { slide(b, from, kDiag, out); }
void rook_rule(const Board& b, int from, std::vector<Move>& out) { slide(b, from, kOrtho, out); }
void queen_rule(const Board& b, int from, std::vector<Move>& out) {
    slide(b, from, kOrtho, out);
    slide(b, from, kDiag, out);
}
void king_rule(const Board& b, int from, std::vector<Move>& out) {
    for (const int d : kKingSteps)
        if (const int to = from + d; to >= 0 && to < 64 && std::abs(to % 8 - from % 8) <= 1 && b.squares[static_cast<sz>(to)] * b.side <= 0)
            out.push_back({from, to, 0, 0});
    const int home = b.side > 0 ? 4 : 60, k_side = b.side > 0 ? WK : BK, q_side = b.side > 0 ? WQ : BQ;
    if (from != home || b.attacked(home, -b.side)) return;
    const auto empty = [&](int s) { return b.squares[static_cast<sz>(s)] == 0; };
    if ((b.castling & k_side) && empty(home + 1) && empty(home + 2) && !b.attacked(home + 1, -b.side) && !b.attacked(home + 2, -b.side))
        out.push_back({from, home + 2, 0, CASTLE});
    if ((b.castling & q_side) && empty(home - 1) && empty(home - 2) && empty(home - 3) && !b.attacked(home - 1, -b.side) && !b.attacked(home - 2, -b.side))
        out.push_back({from, home - 2, 0, CASTLE});
}

constexpr std::array<MoveRule, 6> kRules{pawn_rule, knight_rule, bishop_rule, rook_rule, queen_rule, king_rule};

Board Board::fen(std::string_view fen) {
    Board b;
    std::vector<std::string_view> f;
    for (sz pos = 0; pos <= fen.size();) {
        const sz next = std::min(fen.find(' ', pos), fen.size());
        f.push_back(fen.substr(pos, next - pos));
        pos = next + 1;
    }
    int rank = 7, file = 0;
    for (const char c : f[0]) {
        if (c == '/') {
            --rank;
            file = 0;
        } else if (c >= '1' && c <= '8') {
            file += c - '0';
        } else {
            const int kind = static_cast<int>(std::string_view("pnbrqk").find(static_cast<char>(c | 0x20))) + 1;
            const int s = rank * 8 + file++;
            const bool white = c < 'a';
            b.squares[static_cast<sz>(s)] = white ? kind : -kind;
            if (kind == K) b.king[white ? 0 : 1] = s;
        }
    }
    b.side = f[1] == "w" ? 1 : -1;
    for (const char c : f[2]) b.castling |= c == 'K' ? WK : c == 'Q' ? WQ : c == 'k' ? BK : c == 'q' ? BQ : 0;
    b.ep = f[3] == "-" ? -1 : (f[3][1] - '1') * 8 + (f[3][0] - 'a');
    return b;
}

bool Board::attacked(int s, int by) const {
    const int pawn_from = s - 8 * by;  // a pawn of `by` attacks diagonally forward
    for (const int df : {-1, 1}) {
        const int f = s % 8 + df, from = pawn_from + df;
        if (f >= 0 && f <= 7 && from >= 0 && from < 64 && squares[static_cast<sz>(from)] == P * by) return true;
    }
    for (const int d : kKnight)
        if (on_board_step(s, s + d) && squares[static_cast<sz>(s + d)] == N * by) return true;
    for (const int d : kKingSteps)
        if (const int t = s + d; t >= 0 && t < 64 && std::abs(t % 8 - s % 8) <= 1 && squares[static_cast<sz>(t)] == K * by) return true;
    return ray(s, kOrtho, R * by, Q * by) || ray(s, kDiag, B * by, Q * by);
}

bool Board::ray(int s, const std::array<int, 4>& dirs, int a, int b) const {
    for (const int d : dirs)
        for (int t = s + d; t >= 0 && t < 64 && std::abs(t % 8 - (t - d) % 8) <= 1; t += d) {
            const int v = squares[static_cast<sz>(t)];
            if (v == a || v == b) return true;
            if (v != 0) break;
        }
    return false;
}

std::vector<Move> Board::pseudo_legal() const {
    std::vector<Move> out;
    out.reserve(64);
    for (int s = 0; s < 64; ++s)
        if (const int v = squares[static_cast<sz>(s)]; v * side > 0) kRules[static_cast<sz>(std::abs(v) - 1)](*this, s, out);
    return out;
}

/** The command's execute(): applies the move and returns the memento that undoes it exactly. */
Undo Board::execute(const Move& m) {
    const int moved = squares[static_cast<sz>(m.from)], dir = 8 * side;
    const int captured_sq = (m.flags & EP) ? m.to - dir : m.to;
    const Undo u{m, moved, squares[static_cast<sz>(captured_sq)], captured_sq, castling, ep};
    squares[static_cast<sz>(captured_sq)] = 0;
    squares[static_cast<sz>(m.to)] = m.promo != 0 ? m.promo : moved;
    squares[static_cast<sz>(m.from)] = 0;
    if (m.flags & CASTLE) {  // the rook moves too
        const int rook_from = m.to > m.from ? m.to + 1 : m.to - 2, rook_to = m.to > m.from ? m.to - 1 : m.to + 1;
        squares[static_cast<sz>(rook_to)] = squares[static_cast<sz>(rook_from)];
        squares[static_cast<sz>(rook_from)] = 0;
    }
    if (std::abs(moved) == K) {
        king[side > 0 ? 0 : 1] = m.to;
        castling &= side > 0 ? ~(WK | WQ) : ~(BK | BQ);
    }
    for (const int s : {m.from, m.to})  // a rook moving or being captured loses its right
        castling &= s == 0 ? ~WQ : s == 7 ? ~WK : s == 56 ? ~BQ : s == 63 ? ~BK : ~0;
    ep = (m.flags & DOUBLE) ? m.from + dir : -1;
    side = -side;
    return u;
}

void Board::undo(const Undo& u) {
    side = -side;
    const Move& m = u.move;
    squares[static_cast<sz>(m.from)] = u.moved;
    squares[static_cast<sz>(m.to)] = 0;
    squares[static_cast<sz>(u.captured_sq)] = u.captured;
    if (m.flags & CASTLE) {
        const int rook_from = m.to > m.from ? m.to + 1 : m.to - 2, rook_to = m.to > m.from ? m.to - 1 : m.to + 1;
        squares[static_cast<sz>(rook_from)] = squares[static_cast<sz>(rook_to)];
        squares[static_cast<sz>(rook_to)] = 0;
    }
    if (std::abs(u.moved) == K) king[side > 0 ? 0 : 1] = m.from;
    castling = u.castling;
    ep = u.ep;
}

std::vector<Move> Board::legal() {
    std::vector<Move> out;
    for (const Move& m : pseudo_legal()) {
        const Undo u = execute(m);
        if (!attacked(king[side > 0 ? 1 : 0], side)) out.push_back(m);  // the side that just moved must not be in check
        undo(u);
    }
    return out;
}

std::string Board::status() {
    const bool in_check = attacked(king[side > 0 ? 0 : 1], -side);
    const bool none = legal().empty();
    return none ? (in_check ? "checkmate" : "stalemate") : in_check ? "check" : "ok";
}

i64 Board::perft(int depth) {
    const auto moves = legal();
    if (depth == 1) return static_cast<i64>(moves.size());  // bulk counting at the leaves
    i64 n = 0;
    for (const Move& m : moves) {
        const Undo u = execute(m);
        n += perft(depth - 1);
        undo(u);
    }
    return n;
}

u64 Board::hash() const {
    u64 h = static_cast<u64>(side * 31 + castling * 7 + ep);
    for (int s = 0; s < 64; ++s) h = mix64(h ^ static_cast<u64>((squares[static_cast<sz>(s)] + 7) * (s + 1)));
    return h;
}

/** Command history: undo pops a memento, redo re-executes the move. A new move clears the redo stack. */
struct Game {
    Board board = Board::fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    std::vector<Undo> done;
    std::vector<Move> undone;
    std::string play(const std::string& uci) {
        for (const Move& m : board.legal())
            if (m.uci() == uci) {
                done.push_back(board.execute(m));
                undone.clear();
                return board.status();
            }
        return "illegal";
    }
    bool undo() {
        if (done.empty()) return false;
        const Undo u = done.back();
        done.pop_back();
        board.undo(u);
        undone.push_back(u.move);
        return true;
    }
    bool redo() {
        if (undone.empty()) return false;
        done.push_back(board.execute(undone.back()));
        undone.pop_back();
        return true;
    }
};

// ---- snakes & ladders: the board is data; validation rejects boards that can't terminate

std::optional<std::string> validate(int size, const std::map<int, int>& jumps) {
    for (const auto& [from, to] : jumps) {
        if (from < 1 || from >= size) return std::format("jump from {}: only squares 1..{} may jump", from, size - 1);
        if (to < 1 || to > size || to == from) return std::format("jump {}->{} is out of range or a no-op", from, to);
    }
    for (const auto& [start, unused] : jumps) {  // chains are allowed; cycles never terminate
        std::set<int> seen;
        for (auto it = jumps.find(start); it != jumps.end(); it = jumps.find(it->second))
            if (!seen.insert(it->first).second) return std::format("jumps form a cycle through {}", it->first);
    }
    return std::nullopt;
}

int resolve(int pos, const std::map<int, int>& jumps) {
    for (auto it = jumps.find(pos); it != jumps.end(); it = jumps.find(pos)) pos = it->second;
    return pos;
}

// ---- harness

struct Rng {
    u64 s;
    int below(int n) { return static_cast<int>(mix64(s++) % static_cast<u64>(n)); }
};

constexpr std::string_view kStart = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
constexpr std::string_view kKiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";

/** A game behind a lock; a client submits a move for the ply it saw. */
class GameServer {
    std::mutex m_;
    Game game_;

public:
    int ply = 0;  // guarded by m_
    GameServer() { std::scoped_lock warm(m_); }
    bool validate(int expected_ply, const std::string& uci) {
        std::scoped_lock l(m_);
        if (ply != expected_ply) return false;
        const auto moves = game_.board.legal();
        return std::ranges::any_of(moves, [&](const Move& m) { return m.uci() == uci; });
    }
    void apply(const std::string& uci) {
        std::scoped_lock l(m_);
        game_.play(uci);
        ++ply;
    }
    std::string submit(int expected_ply, const std::string& uci) {  // check and act in ONE critical section
        std::scoped_lock l(m_);
        if (ply != expected_ply) return std::format("stale: ply is now {}", ply);
        const std::string s = game_.play(uci);
        if (s != "illegal") ++ply;
        return s;
    }
};

void gap() {  // ~1 us of work between the two critical sections
    for (int k = 0; k < 300; ++k) {
#if defined(__x86_64__) || defined(__i386__)
        __builtin_ia32_pause();
#endif
    }
}

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

i64 ms_since(std::chrono::steady_clock::time_point t0) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Perft: move generation + execute/undo checked against published node counts ==");
    const std::vector<i64> start_expected{20, 400, 8'902, 197'281}, kiwi_expected{48, 2'039, 97'862};
    bool perft_ok = true;
    for (int pos = 0; pos < 2; ++pos) {
        Board b = Board::fen(pos == 0 ? kStart : kKiwipete);
        const u64 before = b.hash();
        const auto& exp = pos == 0 ? start_expected : kiwi_expected;
        std::string line;
        for (sz d = 1; d <= exp.size(); ++d) {
            const i64 n = b.perft(static_cast<int>(d));
            perft_ok = perft_ok && n == exp[d - 1];
            line += std::format("d{} {}{}  ", d, n, n == exp[d - 1] ? "" : std::format(" (expected {})", exp[d - 1]));
        }
        perft_ok = perft_ok && b.hash() == before;
        std::println("  {:<9} {}| position restored after every undo: {}", pos == 0 ? "start:" : "kiwipete:", line, b.hash() == before);
    }

    std::println("== 2. A game: scholar's mate, undo, redo, illegal moves ==");
    Game g;
    std::vector<std::string> log;
    for (const char* mv : {"e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"}) log.push_back(std::string(mv) + " " + g.play(mv));
    std::string joined;
    for (const auto& s : log) joined += (joined.empty() ? "" : " | ") + s;
    std::println("  {}", joined);
    const bool undone = g.undo();
    const std::string after_undo = g.board.status();
    const std::string alt = g.play("h5f3");  // a different move clears the redo stack
    const bool redo_after_new_move = g.redo();
    g.undo();
    g.undone.clear();
    const std::string again = g.play("h5f7");
    const bool u2 = g.undo(), r2 = g.redo();
    const std::string after_redo = g.board.status();
    std::println("  undo Qxf7: {} -> {} | play h5f3 instead: {} | redo now: {} | back to Qxf7: {} | undo {} + redo {} -> {}", undone, after_undo, alt,
                 redo_after_new_move, again, u2, r2, after_redo);
    Game e;
    const std::string e1 = e.play("e2e5"), e2 = e.play("e1e2"), e3 = e.play("e7e5");
    std::println("  e2e5 -> {} | e1e2 (king into own pawn) -> {} | e7e5 (black on white's turn) -> {}", e1, e2, e3);
    Board stale = Board::fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1");
    const std::string stale_status = stale.status();
    std::println("  black to move, Kh8 vs Qf7 Kg6: {}", stale_status);

    std::println("== 3. Parallel perft(5) from the start: one board copy per root move (share nothing) ==");
    Board root = Board::fen(kStart);
    auto t0 = std::chrono::steady_clock::now();
    const i64 seq = root.perft(5);
    const i64 seq_ms = ms_since(t0);
    t0 = std::chrono::steady_clock::now();
    const auto roots = root.legal();
    std::atomic<sz> next{0};
    std::atomic<i64> par{0};
    {
        std::vector<std::jthread> pool;
        for (int t = 0; t < 8; ++t)
            pool.emplace_back([&] {
                for (sz i = next++; i < roots.size(); i = next++) {
                    Board copy = root;  // each task owns its board: execute/undo mutate it
                    copy.execute(roots[i]);
                    par += copy.perft(4);
                }
            });
    }
    const i64 par_ms = ms_since(t0);
    std::println("  sequential {} nodes in {} ms | 8 threads {} nodes in {} ms ({:.1f}x) | expected 4865609", seq, seq_ms, par.load(), par_ms,
                 static_cast<double>(seq_ms) / static_cast<double>(std::max<i64>(1, par_ms)));

    std::println("== 4. Two clients submit a white move for ply 0 at the same moment, 5,000 rounds ==");
    int naive_double = 0, safe_double = 0;
    for (int round = 0; round < 5'000; ++round) {
        GameServer s;
        race(
            [&] {
                if (s.validate(0, "e2e4")) {  // validate, release the lock...
                    gap();                    // ...write an audit row / call a rules service...
                    s.apply("e2e4");          // ...then apply
                }
            },
            [&] {
                if (s.validate(0, "d2d4")) {
                    gap();
                    s.apply("d2d4");
                }
            });
        naive_double += s.ply == 2;
        GameServer t;
        race([&] { t.submit(0, "e2e4"); }, [&] { t.submit(0, "d2d4"); });
        safe_double += t.ply == 2;
    }
    std::println("  validate, then apply (two critical sections): white moved twice in {} of 5000 rounds", naive_double);
    std::println("  submit(expectedPly, move) in one critical section: white moved twice in {} of 5000 rounds", safe_double);

    std::println("== 5. Snakes & ladders: validate the board, then 100,000 seeded 2-player games ==");
    const std::map<int, int> classic{{1, 38},  {4, 14},  {9, 31},  {21, 42}, {28, 84}, {36, 44}, {51, 67}, {71, 91}, {80, 100}, {16, 6},
                                     {47, 26}, {49, 11}, {56, 53}, {62, 19}, {64, 60}, {87, 24}, {93, 73}, {95, 75}, {98, 78}};
    std::println("  classic board: {}", validate(100, classic).value_or("valid"));
    std::println("  {{50->20, 20->50}}: {}", validate(100, {{50, 20}, {20, 50}}).value_or("valid"));
    std::println("  {{100->5}}: {}", validate(100, {{100, 5}}).value_or("valid"));
    const std::map<int, int> chain{{30, 40}, {40, 70}};
    std::println("  {{30->40, 40->70}} (a chain): {}, 30 resolves to {}", validate(100, chain).value_or("valid"), resolve(30, chain));
    Rng dice{19};
    i64 total_rounds = 0;
    int longest = 0, first_wins = 0;
    for (int game = 0; game < 100'000; ++game) {
        std::array<int, 2> pos{};
        int rounds = 0, winner = -1;
        while (winner < 0) {
            ++rounds;
            for (sz p = 0; p < 2 && winner < 0; ++p) {
                const int roll = 1 + dice.below(6);
                if (pos[p] + roll <= 100) pos[p] = resolve(pos[p] + roll, classic);  // exact finish: overshoot = stay
                if (pos[p] == 100) winner = static_cast<int>(p);
            }
        }
        total_rounds += rounds;
        longest = std::max(longest, rounds);
        first_wins += winner == 0;
    }
    std::println("  average rounds {:.3f} | longest {} | first player wins {:.2f}%", static_cast<double>(total_rounds) / 100'000.0, longest,
                 first_wins / 1'000.0);

    const bool ok = perft_ok && log.back().ends_with("checkmate") && undone && after_undo == "ok" && !redo_after_new_move && again == "checkmate" &&
                    after_redo == "checkmate" && stale_status == "stalemate" && seq == 4'865'609 && par.load() == seq && safe_double == 0 &&
                    !validate(100, classic) && validate(100, {{50, 20}, {20, 50}});
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Perft: move generation + execute/undo checked against published node counts ==
  start:    d1 20  d2 400  d3 8902  d4 197281  | position restored after every undo: true
  kiwipete: d1 48  d2 2039  d3 97862  | position restored after every undo: true
== 2. A game: scholar's mate, undo, redo, illegal moves ==
  e2e4 ok | e7e5 ok | f1c4 ok | b8c6 ok | d1h5 ok | g8f6 ok | h5f7 checkmate
  undo Qxf7: true -> ok | play h5f3 instead: ok | redo now: false | back to Qxf7: checkmate | undo true + redo true -> checkmate
  e2e5 -> illegal | e1e2 (king into own pawn) -> illegal | e7e5 (black on white's turn) -> illegal
  black to move, Kh8 vs Qf7 Kg6: stalemate
== 3. Parallel perft(5) from the start: one board copy per root move (share nothing) ==
  sequential 4865609 nodes in 358 ms | 8 threads 4865609 nodes in 95 ms (3.8x) | expected 4865609
== 4. Two clients submit a white move for ply 0 at the same moment, 5,000 rounds ==
  validate, then apply (two critical sections): white moved twice in 4963 of 5000 rounds
  submit(expectedPly, move) in one critical section: white moved twice in 0 of 5000 rounds
== 5. Snakes & ladders: validate the board, then 100,000 seeded 2-player games ==
  classic board: valid
  {50->20, 20->50}: jumps form a cycle through 20
  {100->5}: jump from 100: only squares 1..99 may jump
  {30->40, 40->70} (a chain): valid, 30 resolves to 70
  average rounds 26.342 | longest 170 | first player wins 50.81%
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Perft: move generation + execute/undo checked against published node counts ==
  start:    d1 20  d2 400  d3 8902  d4 197281  | position restored after every undo: true
  kiwipete: d1 48  d2 2039  d3 97862  | position restored after every undo: true
== 2. A game: scholar's mate, undo, redo, illegal moves ==
  e2e4 ok | e7e5 ok | f1c4 ok | b8c6 ok | d1h5 ok | g8f6 ok | h5f7 checkmate
  undo Qxf7: true -> ok | play h5f3 instead: ok | redo now: false | back to Qxf7: checkmate | undo true + redo true -> checkmate
  e2e5 -> illegal | e1e2 (king into own pawn) -> illegal | e7e5 (black on white's turn) -> illegal
  black to move, Kh8 vs Qf7 Kg6: stalemate
== 3. Parallel perft(5) from the start: one board copy per root move (share nothing) ==
  sequential 4865609 nodes in 382 ms | 8 threads 4865609 nodes in 108 ms (3.5x) | expected 4865609
== 4. Two clients submit a white move for ply 0 at the same moment, 5,000 rounds ==
  validate, then apply (two critical sections): white moved twice in 4963 of 5000 rounds
  submit(expectedPly, move) in one critical section: white moved twice in 0 of 5000 rounds
== 5. Snakes & ladders: validate the board, then 100,000 seeded 2-player games ==
  classic board: valid
  {50->20, 20->50}: jumps form a cycle through 20
  {100->5}: jump from 100: only squares 1..99 may jump
  {30->40, 40->70} (a chain): valid, 30 resolves to 70
  average rounds 26.342 | longest 170 | first player wins 50.81%
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Moves | `if (piece == "knight") …` inside one method | `Piece` subclasses with `canMove()` | Per-kind rule strategies for pseudo-legal moves + one central legality check; special moves as flags |
| Undo | Store the whole board per move | Command with `from`/`to` and the captured piece | Memento with everything the move doesn't encode (captured square, moved piece, castling rights, e.p.); **perft** proves it |
| Status | "King captured = game over" | Check detection | Check / checkmate / stalemate from the legal-move set; castling through check refused |
| Concurrency | Unsynchronized game objects | `synchronized` per method | One critical section per ply with an expected-ply token; share-nothing parallel search |
| Data-driven games | Hard-coded snakes and ladders | Map of jumps | Validation before play (cycles, ranges, finish square), chains resolved, seeded dice for reproducible simulation |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Threefold repetition" | A Zobrist hash per position, updated incrementally in `execute`/`undo` (XOR in/out), with a count map along the game line |
| "Time controls" | An injected `Clock`; each `submit` charges the mover; the flag falls in the same critical section as the move |
| "Spectators and replays" | The `done` stack *is* the game record; replay = execute from the start; spectators subscribe to the move events |
| "A new piece type" | Add one rule to the map. Legality, undo and perft are unchanged |
| "Snakes & ladders: roll three sixes and you go back to start" | Per-turn state (sixes in a row) in the player record; still a pure function of (state, roll) |
| "AI opponent" | Negamax over `legal()` with `execute`/`undo` (no copying); parallelize at the root with board copies as in §3.2 |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Your undo works in your demo game. How do you know it's right?"</b></summary>

**L5:** "I tested a few moves."

**Why it fails:** en passant, promotion and castling-rights bugs only appear in rare lines a demo never reaches.

**L7 defence:** "Perft: count leaf nodes with execute/undo and compare with published values, start position and Kiwipete. They match to depth 4 and 3, and the position hash is identical after every search. Any memento bug changes those numbers."
</details>

<details>
<summary><b>Q2 ⚡ "Two browser tabs submit a move at the same time."</b></summary>

**L5:** "We validate the move first."

**Why it fails:** validation and application are separate critical sections. Measured: White moved twice in about 4,960 of 5,000 rounds.

**L7 defence:** "Check and apply in one critical section, keyed by an expected ply number: optimistic concurrency, like an ETag. And note the C++ run first showed 1–2 failures, because mutex barging hid the race. The window must be tested deliberately."
</details>

<details>
<summary><b>Q3 ⚡ "Make move generation extensible for chess variants."</b></summary>

**L5:** "Add cases to the switch."

**Why it fails:** king-safety and special-move logic gets duplicated across every case.

**L7 defence:** "Per-kind strategies produce pseudo-legal moves; legality is one central execute/check/undo. A variant adds a rule; perft for the variant's known positions guards it."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Perft off by a few at depth 3–4 | Memento misses e.p. square, promotion piece or castling rights | Capture everything the move doesn't encode |
| Castling through check allowed | Only the destination checked | Check start and transit squares |
| Redo replays a stale line | Redo stack not cleared on a new move | Clear on every new command |
| Double move per ply | Check and act in separate locks | One critical section + expected ply |
| Snakes & ladders game never ends | Jump cycle | Validate acyclicity before play |
| Non-deterministic validation message | Iterating `Map.of` (randomized order per JVM) | Iterate a sorted copy |

- [ ] Pseudo-legal per-kind rules; one central legality check.
- [ ] Undo memento complete; perft matches published counts; position hash restored.
- [ ] Check, checkmate and stalemate from the legal-move set.
- [ ] One critical section per ply with an expected-ply token; share-nothing parallelism.
- [ ] Data-driven boards validated before play.

## 10. References

- Chess Programming Wiki, *Perft Results* (start position and Kiwipete counts). <https://www.chessprogramming.org/Perft_Results>
- Chess Programming Wiki, *Zobrist Hashing*. <https://www.chessprogramming.org/Zobrist_Hashing>
- Refactoring.Guru, *Command* and *Memento*. <https://refactoring.guru/design-patterns/command> · <https://refactoring.guru/design-patterns/memento>
- In this KB: [02.3 Command undo/redo](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/03-observer-event-bus-command-undo-redo-and-double-dispatch-visitor.md) · [P14 Commit-then-act transitions](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/04-problem-14-vending-machine-and-atm-dispense-chain-and-state-rollback.md)
