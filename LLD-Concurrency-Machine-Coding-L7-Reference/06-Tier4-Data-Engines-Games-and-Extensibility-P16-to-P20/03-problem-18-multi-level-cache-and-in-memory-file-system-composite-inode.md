# P18 · In-Memory File System and Multi-Level Cache: Composite Inodes, Hand-Over-Hand Locking, a Rename Lock, and Fills That Can't Go Stale

> **Folder 06 · Problem 18 of 20.** A tree of inodes is the textbook Composite pattern. At L7 the interesting parts are concurrency at three scales:
> - **path traversal** must lock each child *before* releasing its parent, or a create lands in a directory that was just unlinked;
> - **cross-directory moves** must serialize on a rename lock, or two individually valid moves form a cycle that detaches both directories from the root;
> - **a read-through cache** must refuse a fill that read the store *before* a concurrent write, or the stale value sticks.
>
> All three failures are reproduced, then removed.
>
> **Listing pair P18:** `FileSystemCache.java` / `file_system_cache.cpp`. Sections 1, 3 and 5 are deterministic and **byte-identical in Java, GCC and Clang**, including the cache's hit counts. Sections 2 and 4 are one measured run.

---

## 1. Problem and scope

**File system:**
- `mkdir`, `create`, `read`, `ls`, `rmdir -r`, and `mv` of directories across parents.
- POSIX-like semantics: operations already inside a moved directory complete there.

**Cache:** L1 (small, hottest) in front of L2 (larger) in front of the store, read-through, with invalidation on write.

**Out of scope:** hard links (a DAG, not a tree), permissions, persistence, and per-thread L1s (§7).

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Inode | `sealed interface Inode permits Dir, FileNode` | `using Node = std::variant<shared_ptr<Dir>, shared_ptr<FileNode>>` |
| Dir | `TreeMap` children + `ReentrantReadWriteLock` + `parent` + `unlinked` | `std::map` + `std::shared_mutex` (warmed: the P10 MinGW lesson) + `weak_ptr` parent |
| Walk | `lockDir(path, write)`: hand-over-hand, or the naive "gap" walk | the same; `shared_ptr` keeps an unlinked directory alive while a walker holds it |
| Moves | `move()` takes `renameLock`, then `moveLocked()` locks both parents ancestor-first (else by id) | the same |
| Cache | `TwoLevelCache(L1 LRU, L2 LRU, tombstones)`, `fill(k, Versioned)` | the same (`std::list` + `unordered_map` LRU) |

**Invariants:**
- **I1:** the directory graph is a tree. Every directory is reachable from `/` exactly once, with consistent parent links (`reachableDirs()`).
- **I2:** an acknowledged create is linked into a reachable directory at the moment it happens. No create lands in an unlinked directory.
- **I3:** a move never makes a directory its own ancestor.
- **I4:** after a write of version v is invalidated, the cache never serves a version older than v.

## 3. Concurrency and contention analysis

### 3.1 Hand-over-hand: why the overlap matters

The naive walk locks a directory, finds the child, **unlocks the directory, then locks the child**. Between those two steps, `rm -r` can unlink the child. The walker then "creates" a file in a directory nobody can reach. The create is acknowledged, and the file is lost.

**Measured:** one thread loops `rm -r /work; mkdir /work` while 3 threads create `/work/f…`:

| Walk | Java | GCC | Clang |
|---|---|---|---|
| Unlock parent, then lock child | **61** acknowledged creates into unlinked directories | **1,105** | **5,045** |
| Hand-over-hand: child before parent | 0 | 0 | 0 |

**Why coupling is enough, given how `rm -r` locks:**
1. `rm -r` takes the parent's **write** lock.
2. It then takes each victim directory's write lock top-down, marking it `unlinked`.

A walker holding the parent's read lock blocks step 1. A walker already inside the victim holds the victim's lock, so the deleter **waits for it**. The walker's create therefore happens while the directory is still linked. It's then legitimately removed with the subtree, which is ordered after the create.

**Lock order is top-down everywhere**, which is why traversal can't deadlock with deletion.

**C++ specifics:**
- The walker holds a `shared_ptr<Dir>`, so an unlinked directory can't be freed under it.
- Each `Dir` warms its `std::shared_mutex` in the constructor. This listing creates thousands of fresh RW locks under contention, exactly P10's winpthreads lazy-init hazard.

### 3.2 Moves: a cycle from two valid checks

`mv /a /b/a` checks "is `/b` under `/a`? No". `mv /b /a/b` checks "is `/a` under `/b`? No". **Both checks pass before either move acts.** Then both act:
- `a` now lives in `b`, and `b` in `a`;
- **neither is reachable from `/`** (1 of 3 directories reachable);
- the subtree is lost, and it leaks in C++ unless broken by hand.

**The rename lock fixes it:**
- Linux serializes cross-directory renames on a per-filesystem `s_vfs_rename_mutex`.
- With it held, **ancestry can't change**, so the cycle check stays true until the move completes. The second move is refused: "would create a cycle".
- It does **not** block reads, creates or same-directory renames, so it's not a global lock.
- Within a move, the two parents are locked **ancestor-first** (else by id), so moves agree with top-down traversals.

**Measured:** 4 threads × 5,000 random moves among 16 directories, plus 2 readers walking to files:
- ~15,300 moves done and ~4,700 refused (cycles or name clashes);
- **17 of 17 directories reachable** at the end, in every build;
- no deadlock.

### 3.3 The multi-level cache: hit ratios and the stale-fill race

**200,000 skewed reads over 1,000 files**, identical in all three builds:

| Level | Hits | Share |
|---|---|---|
| L1 (64 entries) | 52,142 | 26% |
| L2 (512 entries) | 93,971 | 47% |
| Store | 53,887 | 27% |

L2 earns its keep: L1 alone would send 74% of reads to the store.

**The cache-aside race:**
1. A reader misses and reads **v1** from the store.
2. A writer writes **v2** and invalidates the cache.
3. The slow reader now **fills v1**, and v1 is served from then on.

**The fix: invalidation leaves a version tombstone, and fills carry the version they read.** A fill older than the tombstone is refused, so the next reader misses and loads v2. Facebook's memcache *leases* solve the same problem with a token issued on miss. Either way, the cache must know which write a fill raced with.

## 4. Java 21 implementation

```java
// FileSystemCache.java - P18: composite inode tree, hand-over-hand locking, rename lock for moves, two-level cache with versioned fills
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public final class FileSystemCache {

    // ---- the composite: a directory holds named inodes; a file holds versioned content

    sealed interface Inode permits Dir, FileNode {}

    static final class Dir implements Inode {
        final long id;
        final TreeMap<String, Inode> children = new TreeMap<>();      // guarded by lock
        final ReentrantReadWriteLock lock = new ReentrantReadWriteLock();
        Dir parent;                                                    // changed only by moves, under the rename lock
        boolean unlinked;                                              // guarded by lock: set when removed from the tree

        Dir(long id, Dir parent) {
            this.id = id;
            this.parent = parent;
        }
    }

    static final class FileNode implements Inode {
        final ReentrantLock lock = new ReentrantLock();
        String content = "";                                           // guarded by lock
        long version;                                                  // guarded by lock

        FileNode() {}
    }

    static List<String> split(String path) {
        List<String> out = new ArrayList<>();
        for (String p : path.split("/"))
            if (!p.isEmpty()) out.add(p);
        return out;
    }

    static final class Fs {
        final AtomicLong ids = new AtomicLong();
        final Dir root = new Dir(ids.getAndIncrement(), null);
        final ReentrantLock renameLock = new ReentrantLock();          // serializes cross-directory moves (Linux: s_vfs_rename_mutex)
        final boolean coupled;                                         // false = the naive walk: unlock parent, THEN lock child
        final LongAdder orphanCreates = new LongAdder();              // acknowledged creates into an unlinked directory

        Fs(boolean coupled) {
            this.coupled = coupled;
        }

        /**
         * Walks to a directory and returns it with `write ? writeLock : readLock` held and nothing else. Hand-over-hand:
         * each child is locked BEFORE its parent is released, so nothing on the path can be unlinked or moved mid-walk.
         */
        Dir lockDir(List<String> path, boolean write) {
            Dir cur = root;
            Lock held = path.isEmpty() && write ? cur.lock.writeLock() : cur.lock.readLock();
            held.lock();
            for (int i = 0; i < path.size(); i++) {
                Inode next = cur.children.get(path.get(i));
                if (!(next instanceof Dir d)) {
                    held.unlock();
                    return null;
                }
                Lock nl = i == path.size() - 1 && write ? d.lock.writeLock() : d.lock.readLock();
                if (coupled) {
                    nl.lock();                                         // child first...
                    held.unlock();                                     // ...then the parent
                } else {
                    held.unlock();                                     // the gap: the child can be unlinked right here
                    Thread.onSpinWait();
                    nl.lock();
                }
                cur = d;
                held = nl;
            }
            return cur;
        }

        String mkdir(String path) {
            List<String> p = split(path);
            Dir parent = lockDir(p.subList(0, p.size() - 1), true);
            if (parent == null) return "no such directory";
            try {
                if (parent.unlinked) return "no such directory";
                if (parent.children.containsKey(p.getLast())) return "exists";
                parent.children.put(p.getLast(), new Dir(ids.getAndIncrement(), parent));
                return "ok";
            } finally {
                parent.lock.writeLock().unlock();
            }
        }

        String create(String path, String content) {
            List<String> p = split(path);
            Dir parent = lockDir(p.subList(0, p.size() - 1), true);
            if (parent == null) return "no such directory";
            try {
                if (parent.unlinked) {
                    if (!coupled) {                                    // the naive design never checks: it "found" the dir
                        orphanCreates.increment();
                        parent.children.put(p.getLast(), new FileNode());
                        return "ok";
                    }
                    orphanCreates.increment();                         // must stay 0 with coupling
                    return "no such directory";
                }
                FileNode f = new FileNode();
                f.content = content;
                f.version = 1;
                parent.children.put(p.getLast(), f);
                return "ok";
            } finally {
                parent.lock.writeLock().unlock();
            }
        }

        /** rm -r: unlink under the parent's write lock, then mark every directory below, top-down, under its own write lock. */
        String rmdir(String path) {
            List<String> p = split(path);
            Dir parent = lockDir(p.subList(0, p.size() - 1), true);
            if (parent == null) return "no such directory";
            try {
                if (!(parent.children.get(p.getLast()) instanceof Dir victim)) return "no such directory";
                ArrayDeque<Dir> todo = new ArrayDeque<>(List.of(victim));
                while (!todo.isEmpty()) {
                    Dir d = todo.pop();
                    d.lock.writeLock().lock();                         // waits for anyone still inside d
                    try {
                        d.unlinked = true;
                        for (Inode c : d.children.values())
                            if (c instanceof Dir cd) todo.push(cd);
                    } finally {
                        d.lock.writeLock().unlock();
                    }
                }
                parent.children.remove(p.getLast());
                return "ok";
            } finally {
                parent.lock.writeLock().unlock();
            }
        }

        String read(String path) {
            List<String> p = split(path);
            Dir parent = lockDir(p.subList(0, p.size() - 1), false);
            if (parent == null) return "no such directory";
            try {
                if (!(parent.children.get(p.getLast()) instanceof FileNode f)) return "no such file";
                f.lock.lock();
                try {
                    return f.content + " (v" + f.version + ")";
                } finally {
                    f.lock.unlock();
                }
            } finally {
                parent.lock.readLock().unlock();
            }
        }

        String ls(String path) {
            Dir d = lockDir(split(path), false);
            if (d == null) return "no such directory";
            try {
                List<String> names = new ArrayList<>();
                d.children.forEach((n, c) -> names.add(c instanceof Dir ? n + "/" : n));
                return String.join(" ", names);
            } finally {
                d.lock.readLock().unlock();
            }
        }

        static boolean isAncestor(Dir a, Dir d) {                      // is a == d or an ancestor of d? (stable under the rename lock)
            for (Dir x = d; x != null; x = x.parent)
                if (x == a) return true;
            return false;
        }

        /**
         * mv dir srcParent/name -> dstParent/name. Under the rename lock ancestry can't change, so the cycle check holds;
         * the two parents are locked ancestor-first (else by id) to agree with top-down traversals.
         */
        String move(Dir srcParent, String name, Dir dstParent) {
            renameLock.lock();
            try {
                return moveLocked(srcParent, name, dstParent);
            } finally {
                renameLock.unlock();
            }
        }

        String moveLocked(Dir srcParent, String name, Dir dstParent) {
            Dir first = isAncestor(srcParent, dstParent) ? srcParent : isAncestor(dstParent, srcParent) ? dstParent
                    : srcParent.id < dstParent.id ? srcParent : dstParent;
            Dir second = first == srcParent ? dstParent : srcParent;
            first.lock.writeLock().lock();
            if (second != first) second.lock.writeLock().lock();
            try {
                if (srcParent.unlinked || dstParent.unlinked) return "no such directory";
                if (!(srcParent.children.get(name) instanceof Dir moving)) return "no such directory";
                if (isAncestor(moving, dstParent)) return "would create a cycle";
                if (dstParent.children.containsKey(name)) return "exists";
                srcParent.children.remove(name);
                dstParent.children.put(name, moving);
                moving.parent = dstParent;
                return "ok";
            } finally {
                if (second != first) second.lock.writeLock().unlock();
                first.lock.writeLock().unlock();
            }
        }

        /** The naive mover, split in two: the check... */
        boolean checkMove(Dir srcParent, String name, Dir dstParent) {
            return srcParent.children.get(name) instanceof Dir moving && !isAncestor(moving, dstParent) && !dstParent.children.containsKey(name);
        }

        /** ...and the act, which trusts a check that may be stale by now. */
        void act(Dir srcParent, String name, Dir dstParent) {
            Dir moving = (Dir) srcParent.children.remove(name);
            dstParent.children.put(name, moving);
            moving.parent = dstParent;
        }

        /** Every directory reachable from the root exactly once, with consistent parent links. */
        int reachableDirs() {
            Set<Dir> seen = new HashSet<>();
            ArrayDeque<Dir> todo = new ArrayDeque<>(List.of(root));
            while (!todo.isEmpty()) {
                Dir d = todo.pop();
                if (!seen.add(d)) return -1;                           // reached twice: not a tree
                for (Inode c : d.children.values())
                    if (c instanceof Dir cd) {
                        if (cd.parent != d) return -2;
                        todo.push(cd);
                    }
            }
            return seen.size();
        }

        Dir dir(String path) {
            Dir d = lockDir(split(path), false);
            if (d != null) d.lock.readLock().unlock();
            return d;
        }
    }

    // ---- two-level read-through cache; fills carry the version they read, invalidations leave a version tombstone

    static final class Lru<V> {
        final LinkedHashMap<String, V> map;

        Lru(int capacity) {
            map = new LinkedHashMap<>(16, 0.75f, true) {
                private static final long serialVersionUID = 1L;

                @Override
                protected boolean removeEldestEntry(Map.Entry<String, V> e) {
                    return size() > capacity;
                }
            };
        }
    }

    record Versioned(String value, long version) {}

    static final class TwoLevelCache {
        final Lru<Versioned> l1, l2;
        final Map<String, Long> tombstones = new HashMap<>();          // key -> newest version invalidated
        final boolean guarded;
        long l1Hits, l2Hits, misses;

        TwoLevelCache(int l1, int l2, boolean guarded) {
            this.l1 = new Lru<>(l1);
            this.l2 = new Lru<>(l2);
            this.guarded = guarded;
        }

        synchronized Versioned get(String k) {
            Versioned v = l1.map.get(k);
            if (v != null) {
                l1Hits++;
                return v;
            }
            v = l2.map.get(k);
            if (v != null) {
                l2Hits++;
                l1.map.put(k, v);                                      // promote
                return v;
            }
            misses++;
            return null;
        }

        /** A fill from the backing store. Guarded: refused if a newer version was invalidated meanwhile (a stale read). */
        synchronized boolean fill(String k, Versioned v) {
            if (guarded && v.version() < tombstones.getOrDefault(k, 0L)) return false;
            l1.map.put(k, v);
            l2.map.put(k, v);
            return true;
        }

        synchronized void invalidate(String k, long newVersion) {
            l1.map.remove(k);
            l2.map.remove(k);
            tombstones.merge(k, newVersion, Math::max);
        }
    }

    /** The backing store: files with versions. */
    static final class Store {
        final Map<String, Versioned> files = new HashMap<>();

        synchronized Versioned read(String k) {
            return files.get(k);
        }

        synchronized long write(String k, String value) {
            long v = files.containsKey(k) ? files.get(k).version() + 1 : 1;
            files.put(k, new Versioned(value, v));
            return v;
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

    interface Body {
        void run(int thread) throws Exception;
    }

    static void parallel(int threads, Body body) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads + 1);
        CountDownLatch done = new CountDownLatch(threads);
        AtomicReference<Exception> failure = new AtomicReference<>();
        for (int t = 0; t < threads; t++) {
            final int id = t;
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    body.run(id);
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                } finally {
                    done.countDown();
                }
            });
        }
        start.await();
        done.await();
        if (failure.get() != null) throw new IllegalStateException(failure.get());
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. The composite tree ==");
        Fs fs = new Fs(true);
        String[][] steps = {{"mkdir /home", fs.mkdir("/home")}, {"mkdir /home/ann", fs.mkdir("/home/ann")},
                {"create /home/ann/notes.txt", fs.create("/home/ann/notes.txt", "hello")}, {"create /nope/x", fs.create("/nope/x", "x")},
                {"mkdir /home/ann", fs.mkdir("/home/ann")}, {"mkdir /tmp", fs.mkdir("/tmp")},
                {"mv /home/ann -> /tmp", fs.move(fs.dir("/home"), "ann", fs.dir("/tmp"))},
                {"read /tmp/ann/notes.txt", fs.read("/tmp/ann/notes.txt")}, {"mv /tmp -> /tmp/ann", fs.move(fs.root, "tmp", fs.dir("/tmp/ann"))},
                {"ls /", fs.ls("/")}, {"rmdir /tmp", fs.rmdir("/tmp")}, {"ls /", fs.ls("/")}};
        for (String[] s : steps) System.out.printf("  %-28s -> %s%n", s[0], s[1]);

        System.out.println("== 2. rm -r / mkdir /work in a loop while 3 threads create /work/f<i> (40,000 creates) ==");
        long[] orphans = new long[2], okCreates = new long[2];
        for (int mode = 0; mode < 2; mode++) {
            Fs f = new Fs(mode == 1);
            f.mkdir("/work");
            AtomicBoolean creating = new AtomicBoolean(true);
            LongAdder ok = new LongAdder();
            parallel(4, t -> {
                if (t == 3) {
                    while (creating.get()) {
                        f.rmdir("/work");
                        f.mkdir("/work");
                    }
                    return;
                }
                for (int i = 0; i < 13_334; i++)
                    if (f.create("/work/f" + t + "_" + i, "x").equals("ok")) ok.increment();
                if (t == 0) creating.set(false);
            });
            orphans[mode] = f.orphanCreates.sum();
            okCreates[mode] = ok.sum();
            System.out.printf("  %-38s acknowledged creates %d | of those, into an already-unlinked directory: %d%n",
                    mode == 0 ? "unlock parent, then lock child:" : "hand-over-hand (child before parent):", okCreates[mode], orphans[mode]);
        }

        System.out.println("== 3. Moves: two concurrent cross-directory moves without the rename lock ==");
        Fs race = new Fs(true);
        race.mkdir("/a");
        race.mkdir("/b");
        Dir a = race.dir("/a"), b = race.dir("/b");
        boolean aIntoB = race.checkMove(race.root, "a", b);            // thread 1 checks mv /a /b/a
        boolean bIntoA = race.checkMove(race.root, "b", a);            // thread 2 checks mv /b /a/b: nothing has moved yet
        if (aIntoB) race.act(race.root, "a", b);                       // thread 1 acts
        if (bIntoA) race.act(race.root, "b", a);                       // thread 2 acts on its stale check
        System.out.printf("  check(a->b) %b, check(b->a) %b, then both act -> dirs reachable from / : %d of 3 (a and b form a detached cycle)%n", aIntoB,
                bIntoA, race.reachableDirs());
        Fs safe = new Fs(true);
        safe.mkdir("/a");
        safe.mkdir("/b");
        String m1 = safe.move(safe.root, "a", safe.dir("/b")), m2 = safe.move(safe.root, "b", safe.dir("/b/a"));
        System.out.printf("  with the rename lock: mv /a /b -> %s | mv /b /b/a -> %s | reachable %d of 3%n", m1, m2, safe.reachableDirs());

        System.out.println("== 4. 4 threads x 5,000 random moves among 16 directories + 2 threads reading files ==");
        Fs tree = new Fs(true);
        List<Dir> dirs = new ArrayList<>();
        for (int i = 0; i < 16; i++) {
            tree.mkdir("/d" + i);
            tree.create("/d" + i + "/file", "data" + i);
            dirs.add(tree.dir("/d" + i));
        }
        LongAdder moved = new LongAdder(), refused = new LongAdder(), reads = new LongAdder();
        AtomicBoolean moving = new AtomicBoolean(true);
        CountDownLatch movers = new CountDownLatch(4);
        parallel(6, t -> {
            if (t >= 4) {                                              // readers: hand-over-hand from the root to some file
                Rng r = new Rng(900 + t);
                while (moving.get()) {
                    Dir d = dirs.get(r.below(16));
                    List<String> path = new ArrayList<>();
                    tree.renameLock.lock();                            // a consistent path for the demo
                    try {
                        for (Dir x = d; x.parent != null; x = x.parent)
                            for (var e : x.parent.children.entrySet())
                                if (e.getValue() == x) path.addFirst(e.getKey());
                    } finally {
                        tree.renameLock.unlock();
                    }
                    if (tree.read("/" + String.join("/", path) + "/file").startsWith("data")) reads.increment();
                }
                return;
            }
            Rng r = new Rng(700 + t);
            for (int i = 0; i < 5_000; i++) {
                Dir src = dirs.get(r.below(16)), dst = r.below(4) == 0 ? tree.root : dirs.get(r.below(16));
                String result;
                tree.renameLock.lock();
                try {
                    String name = null;
                    if (src.parent != null)
                        for (var e : src.parent.children.entrySet())
                            if (e.getValue() == src) name = e.getKey();
                    result = name == null ? "gone" : tree.moveLocked(src.parent, name, dst);
                } finally {
                    tree.renameLock.unlock();
                }
                (result.equals("ok") ? moved : refused).increment();
            }
            movers.countDown();
            movers.await();
            moving.set(false);
        });
        int reachable = tree.reachableDirs();
        System.out.printf("  moves done %d, refused %d (cycles / name clashes) | file reads during moves %d | reachable dirs %d of 17 (tree intact)%n",
                moved.sum(), refused.sum(), reads.sum(), reachable);

        System.out.println("== 5. Two-level cache (L1 64, L2 512) over 1,000 files, 200,000 skewed reads ==");
        Store store = new Store();
        for (int i = 0; i < 1_000; i++) store.write("f" + i, "content-" + i);
        TwoLevelCache cache = new TwoLevelCache(64, 512, true);
        Rng rr = new Rng(18);
        for (int i = 0; i < 200_000; i++) {
            double u = rr.below(1_000_000) / 1e6;
            String k = "f" + (int) (1_000 * u * u * u);                // heavy skew: a few files are very hot
            if (cache.get(k) == null) cache.fill(k, store.read(k));
        }
        System.out.printf("  L1 hits %d | L2 hits %d | backing reads %d%n", cache.l1Hits, cache.l2Hits, cache.misses);
        String[] served = new String[2];
        for (int mode = 0; mode < 2; mode++) {
            Store st = new Store();
            st.write("k", "v1");
            TwoLevelCache c = new TwoLevelCache(64, 512, mode == 1);
            Versioned readByReader = st.read("k");                     // 1. reader misses and reads v1 from the store
            long v2 = st.write("k", "v2");                             // 2. writer writes v2...
            c.invalidate("k", v2);                                     //    ...and invalidates the cache
            c.fill("k", readByReader);                                 // 3. the slow reader now fills with v1
            Versioned now = c.get("k");
            served[mode] = now == null ? "miss -> " + st.read("k").value() : now.value();
            System.out.printf("  %-34s after the write, the cache serves: %s%n", mode == 0 ? "cache-aside fill:" : "fill guarded by version tombstone:",
                    served[mode]);
        }

        boolean ok = steps[2][1].equals("ok") && steps[3][1].equals("no such directory") && steps[4][1].equals("exists")
                && steps[7][1].equals("hello (v1)") && steps[8][1].equals("would create a cycle") && steps[10][1].equals("ok")
                && orphans[1] == 0 && reachable == 17 && race.reachableDirs() == 1 && m2.equals("would create a cycle") && safe.reachableDirs() == 3
                && served[0].equals("v1") && served[1].equals("miss -> v2") && cache.l1Hits + cache.l2Hits + cache.misses == 200_000;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1, 3 and 5 deterministic; 2 and 4 one measured run):**

```text
== 1. The composite tree ==
  mkdir /home                  -> ok
  mkdir /home/ann              -> ok
  create /home/ann/notes.txt   -> ok
  create /nope/x               -> no such directory
  mkdir /home/ann              -> exists
  mkdir /tmp                   -> ok
  mv /home/ann -> /tmp         -> ok
  read /tmp/ann/notes.txt      -> hello (v1)
  mv /tmp -> /tmp/ann          -> would create a cycle
  ls /                         -> home/ tmp/
  rmdir /tmp                   -> ok
  ls /                         -> home/
== 2. rm -r / mkdir /work in a loop while 3 threads create /work/f<i> (40,000 creates) ==
  unlock parent, then lock child:        acknowledged creates 15657 | of those, into an already-unlinked directory: 110
  hand-over-hand (child before parent):  acknowledged creates 17810 | of those, into an already-unlinked directory: 0
== 3. Moves: two concurrent cross-directory moves without the rename lock ==
  check(a->b) true, check(b->a) true, then both act -> dirs reachable from / : 1 of 3 (a and b form a detached cycle)
  with the rename lock: mv /a /b -> ok | mv /b /b/a -> would create a cycle | reachable 3 of 3
== 4. 4 threads x 5,000 random moves among 16 directories + 2 threads reading files ==
  moves done 14655, refused 5345 (cycles / name clashes) | file reads during moves 2348 | reachable dirs 17 of 17 (tree intact)
== 5. Two-level cache (L1 64, L2 512) over 1,000 files, 200,000 skewed reads ==
  L1 hits 52142 | L2 hits 93971 | backing reads 53887
  cache-aside fill:                  after the write, the cache serves: v1
  fill guarded by version tombstone: after the write, the cache serves: miss -> v2
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// file_system_cache.cpp - P18: composite inode tree, hand-over-hand locking, rename lock for moves, two-level cache with versioned fills
#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <format>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <set>
#include <shared_mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;

// ---- the composite: a directory holds named inodes; a file holds versioned content (a closed set: a variant)

struct Dir;
struct FileNode {
    std::mutex m;
    std::string content;  // guarded by m
    i64 version = 0;      // guarded by m
    FileNode() { std::scoped_lock warm(m); }
};
using Node = std::variant<std::shared_ptr<Dir>, std::shared_ptr<FileNode>>;

struct Dir {
    const i64 id;
    std::map<std::string, Node> children;  // guarded by lock
    std::shared_mutex lock;
    std::weak_ptr<Dir> parent;  // changed only by moves, under the rename lock
    bool unlinked = false;      // guarded by lock: set when removed from the tree
    Dir(i64 i, std::weak_ptr<Dir> p) : id(i), parent(std::move(p)) {
        // MinGW/libstdc++: a fresh shared_mutex raced on first use can hang (measured in P10); warm it once here
        std::unique_lock warm(lock);
    }
};

std::shared_ptr<Dir> as_dir(const Node* n) {
    if (!n) return nullptr;
    const auto* d = std::get_if<std::shared_ptr<Dir>>(n);
    return d ? *d : nullptr;
}

std::vector<std::string> split(const std::string& path) {
    std::vector<std::string> out;
    std::string cur;
    for (const char c : path + "/") {
        if (c == '/') {
            if (!cur.empty()) out.push_back(cur);
            cur.clear();
        } else {
            cur += c;
        }
    }
    return out;
}

class Fs {
public:
    std::atomic<i64> ids{0};
    std::shared_ptr<Dir> root = std::make_shared<Dir>(ids++, std::weak_ptr<Dir>{});
    std::mutex rename_lock;  // serializes cross-directory moves (Linux: s_vfs_rename_mutex)
    const bool coupled;      // false = the naive walk: unlock parent, THEN lock child
    std::atomic<i64> orphan_creates{0};

    explicit Fs(bool c) : coupled(c) { std::scoped_lock warm(rename_lock); }

    /**
     * Walks to a directory and returns it with `write ? unique : shared` held and nothing else. Hand-over-hand:
     * each child is locked BEFORE its parent is released, so nothing on the path can be unlinked or moved mid-walk.
     */
    std::shared_ptr<Dir> lock_dir(const std::vector<std::string>& path, sz n, bool write) {
        std::shared_ptr<Dir> cur = root;  // shared_ptr: an unlinked directory stays alive while we hold it
        const auto lock = [](Dir& d, bool w) { w ? d.lock.lock() : d.lock.lock_shared(); };
        const auto unlock = [](Dir& d, bool w) { w ? d.lock.unlock() : d.lock.unlock_shared(); };
        bool cur_write = n == 0 && write;
        lock(*cur, cur_write);
        for (sz i = 0; i < n; ++i) {
            const auto it = cur->children.find(path[i]);
            const auto next = as_dir(it == cur->children.end() ? nullptr : &it->second);
            if (!next) {
                unlock(*cur, cur_write);
                return nullptr;
            }
            const bool next_write = i == n - 1 && write;
            if (coupled) {
                lock(*next, next_write);  // child first...
                unlock(*cur, cur_write);  // ...then the parent
            } else {
                unlock(*cur, cur_write);  // the gap: the child can be unlinked right here
                std::this_thread::yield();
                lock(*next, next_write);
            }
            cur = next;
            cur_write = next_write;
        }
        return cur;
    }

    std::string mkdir(const std::string& path) {
        const auto p = split(path);
        const auto parent = lock_dir(p, p.size() - 1, true);
        if (!parent) return "no such directory";
        std::unique_lock l(parent->lock, std::adopt_lock);
        if (parent->unlinked) return "no such directory";
        if (parent->children.contains(p.back())) return "exists";
        parent->children.emplace(p.back(), std::make_shared<Dir>(ids++, parent));
        return "ok";
    }

    std::string create(const std::string& path, const std::string& content) {
        const auto p = split(path);
        const auto parent = lock_dir(p, p.size() - 1, true);
        if (!parent) return "no such directory";
        std::unique_lock l(parent->lock, std::adopt_lock);
        if (parent->unlinked) {
            orphan_creates.fetch_add(1);
            if (!coupled) {  // the naive design never checks: it "found" the dir
                parent->children.insert_or_assign(p.back(), std::make_shared<FileNode>());
                return "ok";
            }
            return "no such directory";  // must stay 0 with coupling
        }
        auto f = std::make_shared<FileNode>();
        f->content = content;
        f->version = 1;
        parent->children.insert_or_assign(p.back(), f);
        return "ok";
    }

    /** rm -r: unlink under the parent's write lock, then mark every directory below, top-down, under its own write lock. */
    std::string rmdir(const std::string& path) {
        const auto p = split(path);
        const auto parent = lock_dir(p, p.size() - 1, true);
        if (!parent) return "no such directory";
        std::unique_lock l(parent->lock, std::adopt_lock);
        const auto it = parent->children.find(p.back());
        const auto victim = as_dir(it == parent->children.end() ? nullptr : &it->second);
        if (!victim) return "no such directory";
        std::vector<std::shared_ptr<Dir>> todo{victim};
        while (!todo.empty()) {
            const auto d = todo.back();
            todo.pop_back();
            std::unique_lock dl(d->lock);  // waits for anyone still inside d
            d->unlinked = true;
            for (const auto& [name, c] : d->children)
                if (const auto cd = as_dir(&c)) todo.push_back(cd);
        }
        parent->children.erase(it);
        return "ok";
    }

    std::string read(const std::string& path) {
        const auto p = split(path);
        const auto parent = lock_dir(p, p.size() - 1, false);
        if (!parent) return "no such directory";
        std::shared_lock l(parent->lock, std::adopt_lock);
        const auto it = parent->children.find(p.back());
        const auto* f = it == parent->children.end() ? nullptr : std::get_if<std::shared_ptr<FileNode>>(&it->second);
        if (!f) return "no such file";
        std::scoped_lock fl((*f)->m);
        return std::format("{} (v{})", (*f)->content, (*f)->version);
    }

    std::string ls(const std::string& path) {
        const auto p = split(path);
        const auto d = lock_dir(p, p.size(), false);
        if (!d) return "no such directory";
        std::shared_lock l(d->lock, std::adopt_lock);
        std::string s;
        for (const auto& [name, c] : d->children) s += (s.empty() ? "" : " ") + name + (as_dir(&c) ? "/" : "");
        return s;
    }

    static bool is_ancestor(const Dir* a, std::shared_ptr<Dir> d) {  // is a == d or an ancestor of d? (stable under the rename lock)
        for (auto x = std::move(d); x; x = x->parent.lock())
            if (x.get() == a) return true;
        return false;
    }

    /**
     * mv dir src_parent/name -> dst_parent/name. Under the rename lock ancestry can't change, so the cycle check holds;
     * the two parents are locked ancestor-first (else by id) to agree with top-down traversals.
     */
    std::string move(const std::shared_ptr<Dir>& src_parent, const std::string& name, const std::shared_ptr<Dir>& dst_parent) {
        std::scoped_lock l(rename_lock);
        return move_locked(src_parent, name, dst_parent);
    }

    std::string move_locked(const std::shared_ptr<Dir>& src, const std::string& name, const std::shared_ptr<Dir>& dst) {
        Dir* first = is_ancestor(src.get(), dst) ? src.get() : is_ancestor(dst.get(), src) ? dst.get() : src->id < dst->id ? src.get() : dst.get();
        Dir* second = first == src.get() ? dst.get() : src.get();
        first->lock.lock();
        if (second != first) second->lock.lock();
        struct Unlock {
            Dir *a, *b;
            ~Unlock() {
                if (b != a) b->lock.unlock();
                a->lock.unlock();
            }
        } guard{first, second};
        if (src->unlinked || dst->unlinked) return "no such directory";
        const auto it = src->children.find(name);
        const auto moving = as_dir(it == src->children.end() ? nullptr : &it->second);
        if (!moving) return "no such directory";
        if (is_ancestor(moving.get(), dst)) return "would create a cycle";
        if (dst->children.contains(name)) return "exists";
        src->children.erase(it);
        dst->children.emplace(name, moving);
        moving->parent = dst;
        return "ok";
    }

    /** The naive mover, split in two: the check... */
    bool check_move(const std::shared_ptr<Dir>& src, const std::string& name, const std::shared_ptr<Dir>& dst) {
        const auto it = src->children.find(name);
        const auto moving = as_dir(it == src->children.end() ? nullptr : &it->second);
        return moving && !is_ancestor(moving.get(), dst) && !dst->children.contains(name);
    }

    /** ...and the act, which trusts a check that may be stale by now. */
    void act(const std::shared_ptr<Dir>& src, const std::string& name, const std::shared_ptr<Dir>& dst) {
        const auto moving = as_dir(&src->children.at(name));
        src->children.erase(name);
        dst->children.emplace(name, moving);
        moving->parent = dst;
    }

    /** Every directory reachable from the root exactly once, with consistent parent links. */
    int reachable_dirs() {
        std::set<const Dir*> seen;
        std::vector<std::shared_ptr<Dir>> todo{root};
        while (!todo.empty()) {
            const auto d = todo.back();
            todo.pop_back();
            if (!seen.insert(d.get()).second) return -1;  // reached twice: not a tree
            for (const auto& [name, c] : d->children)
                if (const auto cd = as_dir(&c)) {
                    if (cd->parent.lock() != d) return -2;
                    todo.push_back(cd);
                }
        }
        return static_cast<int>(seen.size());
    }

    std::shared_ptr<Dir> dir(const std::string& path) {
        const auto p = split(path);
        auto d = lock_dir(p, p.size(), false);
        if (d) d->lock.unlock_shared();
        return d;
    }
};

// ---- two-level read-through cache; fills carry the version they read, invalidations leave a version tombstone

struct Versioned { std::string value; i64 version; };

class Lru {
    sz cap_;
    std::list<std::pair<std::string, Versioned>> order_;  // front = most recent
    std::unordered_map<std::string, std::list<std::pair<std::string, Versioned>>::iterator> index_;

public:
    explicit Lru(sz cap) : cap_(cap) {}
    const Versioned* get(const std::string& k) {
        const auto it = index_.find(k);
        if (it == index_.end()) return nullptr;
        order_.splice(order_.begin(), order_, it->second);  // access order, like LinkedHashMap(accessOrder = true)
        return &it->second->second;
    }
    void put(const std::string& k, Versioned v) {
        if (const auto it = index_.find(k); it != index_.end()) {
            it->second->second = std::move(v);
            order_.splice(order_.begin(), order_, it->second);
            return;
        }
        order_.emplace_front(k, std::move(v));
        index_[k] = order_.begin();
        if (order_.size() > cap_) {
            index_.erase(order_.back().first);
            order_.pop_back();
        }
    }
    void remove(const std::string& k) {
        if (const auto it = index_.find(k); it != index_.end()) {
            order_.erase(it->second);
            index_.erase(it);
        }
    }
};

class TwoLevelCache {
    std::mutex m_;
    Lru l1_, l2_;
    std::unordered_map<std::string, i64> tombstones_;  // key -> newest version invalidated
    bool guarded_;

public:
    i64 l1_hits = 0, l2_hits = 0, misses = 0;
    TwoLevelCache(sz l1, sz l2, bool guarded) : l1_(l1), l2_(l2), guarded_(guarded) { std::scoped_lock warm(m_); }

    std::optional<Versioned> get(const std::string& k) {
        std::scoped_lock l(m_);
        if (const auto* v = l1_.get(k)) {
            ++l1_hits;
            return *v;
        }
        if (const auto* v = l2_.get(k)) {
            ++l2_hits;
            Versioned copy = *v;
            l1_.put(k, copy);  // promote
            return copy;
        }
        ++misses;
        return std::nullopt;
    }
    /** A fill from the backing store. Guarded: refused if a newer version was invalidated meanwhile (a stale read). */
    bool fill(const std::string& k, const Versioned& v) {
        std::scoped_lock l(m_);
        if (guarded_ && v.version < tombstones_[k]) return false;
        l1_.put(k, v);
        l2_.put(k, v);
        return true;
    }
    void invalidate(const std::string& k, i64 new_version) {
        std::scoped_lock l(m_);
        l1_.remove(k);
        l2_.remove(k);
        tombstones_[k] = std::max(tombstones_[k], new_version);
    }
};

/** The backing store: files with versions. */
class Store {
    std::mutex m_;
    std::unordered_map<std::string, Versioned> files_;

public:
    Store() { std::scoped_lock warm(m_); }
    Versioned read(const std::string& k) {
        std::scoped_lock l(m_);
        return files_.at(k);
    }
    i64 write(const std::string& k, const std::string& value) {
        std::scoped_lock l(m_);
        const i64 v = files_.contains(k) ? files_[k].version + 1 : 1;
        files_[k] = {value, v};
        return v;
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

std::string name_in_parent(const std::shared_ptr<Dir>& d) {  // call under the rename lock
    const auto p = d->parent.lock();
    if (!p) return "";
    for (const auto& [name, c] : p->children)
        if (as_dir(&c) == d) return name;
    return "";
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. The composite tree ==");
    Fs fs(true);
    std::vector<std::pair<std::string, std::string>> steps;
    steps.emplace_back("mkdir /home", fs.mkdir("/home"));
    steps.emplace_back("mkdir /home/ann", fs.mkdir("/home/ann"));
    steps.emplace_back("create /home/ann/notes.txt", fs.create("/home/ann/notes.txt", "hello"));
    steps.emplace_back("create /nope/x", fs.create("/nope/x", "x"));
    steps.emplace_back("mkdir /home/ann", fs.mkdir("/home/ann"));
    steps.emplace_back("mkdir /tmp", fs.mkdir("/tmp"));
    steps.emplace_back("mv /home/ann -> /tmp", fs.move(fs.dir("/home"), "ann", fs.dir("/tmp")));
    steps.emplace_back("read /tmp/ann/notes.txt", fs.read("/tmp/ann/notes.txt"));
    steps.emplace_back("mv /tmp -> /tmp/ann", fs.move(fs.root, "tmp", fs.dir("/tmp/ann")));
    steps.emplace_back("ls /", fs.ls("/"));
    steps.emplace_back("rmdir /tmp", fs.rmdir("/tmp"));
    steps.emplace_back("ls /", fs.ls("/"));
    for (const auto& [label, out] : steps) std::println("  {:<28} -> {}", label, out);

    std::println("== 2. rm -r / mkdir /work in a loop while 3 threads create /work/f<i> (40,000 creates) ==");
    std::array<i64, 2> orphans{}, ok_creates{};
    for (sz mode = 0; mode < 2; ++mode) {
        Fs f(mode == 1);
        f.mkdir("/work");
        std::atomic<bool> creating{true};
        std::atomic<i64> ok{0};
        parallel(4, [&](int t) {
            if (t == 3) {
                while (creating.load()) {
                    f.rmdir("/work");
                    f.mkdir("/work");
                }
                return;
            }
            for (int i = 0; i < 13'334; ++i)
                if (f.create(std::format("/work/f{}_{}", t, i), "x") == "ok") ok.fetch_add(1);
            if (t == 0) creating.store(false);
        });
        orphans[mode] = f.orphan_creates.load();
        ok_creates[mode] = ok.load();
        std::println("  {:<38} acknowledged creates {} | of those, into an already-unlinked directory: {}",
                     mode == 0 ? "unlock parent, then lock child:" : "hand-over-hand (child before parent):", ok_creates[mode], orphans[mode]);
    }

    std::println("== 3. Moves: two concurrent cross-directory moves without the rename lock ==");
    Fs race(true);
    race.mkdir("/a");
    race.mkdir("/b");
    const auto a = race.dir("/a"), b = race.dir("/b");
    const bool a_into_b = race.check_move(race.root, "a", b);  // thread 1 checks mv /a /b/a
    const bool b_into_a = race.check_move(race.root, "b", a);  // thread 2 checks mv /b /a/b: nothing has moved yet
    if (a_into_b) race.act(race.root, "a", b);                 // thread 1 acts
    if (b_into_a) race.act(race.root, "b", a);                 // thread 2 acts on its stale check
    std::println("  check(a->b) {}, check(b->a) {}, then both act -> dirs reachable from / : {} of 3 (a and b form a detached cycle)", a_into_b, b_into_a,
                 race.reachable_dirs());
    Fs safe(true);
    safe.mkdir("/a");
    safe.mkdir("/b");
    const std::string m1 = safe.move(safe.root, "a", safe.dir("/b"));
    const std::string m2 = safe.move(safe.root, "b", safe.dir("/b/a"));
    std::println("  with the rename lock: mv /a /b -> {} | mv /b /b/a -> {} | reachable {} of 3", m1, m2, safe.reachable_dirs());
    a->children.clear();  // break the detached cycle so the shared_ptrs can be freed
    b->children.clear();

    std::println("== 4. 4 threads x 5,000 random moves among 16 directories + 2 threads reading files ==");
    Fs tree(true);
    std::vector<std::shared_ptr<Dir>> dirs;
    for (int i = 0; i < 16; ++i) {
        tree.mkdir(std::format("/d{}", i));
        tree.create(std::format("/d{}/file", i), std::format("data{}", i));
        dirs.push_back(tree.dir(std::format("/d{}", i)));
    }
    std::atomic<i64> moved{0}, refused{0}, reads{0};
    std::atomic<int> movers_left{4};
    parallel(6, [&](int t) {
        if (t >= 4) {  // readers: hand-over-hand from the root to some file
            Rng r{900 + static_cast<u64>(t)};
            while (movers_left.load() > 0) {
                const auto d = dirs[static_cast<sz>(r.below(16))];
                std::vector<std::string> path;
                {
                    std::scoped_lock l(tree.rename_lock);  // a consistent path for the demo
                    for (auto x = d; x->parent.lock(); x = x->parent.lock()) path.insert(path.begin(), name_in_parent(x));
                }
                std::string p;
                for (const auto& s : path) p += "/" + s;
                if (tree.read(p + "/file").starts_with("data")) reads.fetch_add(1);
            }
            return;
        }
        Rng r{700 + static_cast<u64>(t)};
        for (int i = 0; i < 5'000; ++i) {
            const auto src = dirs[static_cast<sz>(r.below(16))];
            const auto dst = r.below(4) == 0 ? tree.root : dirs[static_cast<sz>(r.below(16))];
            std::string result;
            {
                std::scoped_lock l(tree.rename_lock);
                const std::string name = name_in_parent(src);
                result = name.empty() ? "gone" : tree.move_locked(src->parent.lock(), name, dst);
            }
            (result == "ok" ? moved : refused).fetch_add(1);
        }
        movers_left.fetch_sub(1);
    });
    const int reachable = tree.reachable_dirs();
    std::println("  moves done {}, refused {} (cycles / name clashes) | file reads during moves {} | reachable dirs {} of 17 (tree intact)", moved.load(),
                 refused.load(), reads.load(), reachable);

    std::println("== 5. Two-level cache (L1 64, L2 512) over 1,000 files, 200,000 skewed reads ==");
    Store store;
    for (int i = 0; i < 1'000; ++i) store.write(std::format("f{}", i), std::format("content-{}", i));
    TwoLevelCache cache(64, 512, true);
    Rng rr{18};
    for (int i = 0; i < 200'000; ++i) {
        const double u = static_cast<double>(rr.below(1'000'000)) / 1e6;
        const std::string k = std::format("f{}", static_cast<int>(1'000 * u * u * u));  // heavy skew: a few files are very hot
        if (!cache.get(k)) cache.fill(k, store.read(k));
    }
    std::println("  L1 hits {} | L2 hits {} | backing reads {}", cache.l1_hits, cache.l2_hits, cache.misses);
    std::array<std::string, 2> served;
    for (sz mode = 0; mode < 2; ++mode) {
        Store st;
        st.write("k", "v1");
        TwoLevelCache c(64, 512, mode == 1);
        const Versioned read_by_reader = st.read("k");  // 1. reader misses and reads v1 from the store
        const i64 v2 = st.write("k", "v2");             // 2. writer writes v2...
        c.invalidate("k", v2);                          //    ...and invalidates the cache
        c.fill("k", read_by_reader);                    // 3. the slow reader now fills with v1
        const auto now = c.get("k");
        served[mode] = now ? now->value : "miss -> " + st.read("k").value;
        std::println("  {:<34} after the write, the cache serves: {}", mode == 0 ? "cache-aside fill:" : "fill guarded by version tombstone:", served[mode]);
    }

    const bool ok = steps[2].second == "ok" && steps[3].second == "no such directory" && steps[4].second == "exists" && steps[7].second == "hello (v1)" &&
                    steps[8].second == "would create a cycle" && steps[10].second == "ok" && orphans[1] == 0 && reachable == 17 && m2 == "would create a cycle" &&
                    safe.reachable_dirs() == 3 && served[0] == "v1" && served[1] == "miss -> v2" && cache.l1_hits + cache.l2_hits + cache.misses == 200'000;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. The composite tree ==
  mkdir /home                  -> ok
  mkdir /home/ann              -> ok
  create /home/ann/notes.txt   -> ok
  create /nope/x               -> no such directory
  mkdir /home/ann              -> exists
  mkdir /tmp                   -> ok
  mv /home/ann -> /tmp         -> ok
  read /tmp/ann/notes.txt      -> hello (v1)
  mv /tmp -> /tmp/ann          -> would create a cycle
  ls /                         -> home/ tmp/
  rmdir /tmp                   -> ok
  ls /                         -> home/
== 2. rm -r / mkdir /work in a loop while 3 threads create /work/f<i> (40,000 creates) ==
  unlock parent, then lock child:        acknowledged creates 14942 | of those, into an already-unlinked directory: 1105
  hand-over-hand (child before parent):  acknowledged creates 12775 | of those, into an already-unlinked directory: 0
== 3. Moves: two concurrent cross-directory moves without the rename lock ==
  check(a->b) true, check(b->a) true, then both act -> dirs reachable from / : 1 of 3 (a and b form a detached cycle)
  with the rename lock: mv /a /b -> ok | mv /b /b/a -> would create a cycle | reachable 3 of 3
== 4. 4 threads x 5,000 random moves among 16 directories + 2 threads reading files ==
  moves done 15331, refused 4669 (cycles / name clashes) | file reads during moves 436 | reachable dirs 17 of 17 (tree intact)
== 5. Two-level cache (L1 64, L2 512) over 1,000 files, 200,000 skewed reads ==
  L1 hits 52142 | L2 hits 93971 | backing reads 53887
  cache-aside fill:                  after the write, the cache serves: v1
  fill guarded by version tombstone: after the write, the cache serves: miss -> v2
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. The composite tree ==
  mkdir /home                  -> ok
  mkdir /home/ann              -> ok
  create /home/ann/notes.txt   -> ok
  create /nope/x               -> no such directory
  mkdir /home/ann              -> exists
  mkdir /tmp                   -> ok
  mv /home/ann -> /tmp         -> ok
  read /tmp/ann/notes.txt      -> hello (v1)
  mv /tmp -> /tmp/ann          -> would create a cycle
  ls /                         -> home/ tmp/
  rmdir /tmp                   -> ok
  ls /                         -> home/
== 2. rm -r / mkdir /work in a loop while 3 threads create /work/f<i> (40,000 creates) ==
  unlock parent, then lock child:        acknowledged creates 15286 | of those, into an already-unlinked directory: 5045
  hand-over-hand (child before parent):  acknowledged creates 13927 | of those, into an already-unlinked directory: 0
== 3. Moves: two concurrent cross-directory moves without the rename lock ==
  check(a->b) true, check(b->a) true, then both act -> dirs reachable from / : 1 of 3 (a and b form a detached cycle)
  with the rename lock: mv /a /b -> ok | mv /b /b/a -> would create a cycle | reachable 3 of 3
== 4. 4 threads x 5,000 random moves among 16 directories + 2 threads reading files ==
  moves done 15359, refused 4641 (cycles / name clashes) | file reads during moves 582 | reachable dirs 17 of 17 (tree intact)
== 5. Two-level cache (L1 64, L2 512) over 1,000 files, 200,000 skewed reads ==
  L1 hits 52142 | L2 hits 93971 | backing reads 53887
  cache-aside fill:                  after the write, the cache serves: v1
  fill guarded by version tombstone: after the write, the cache serves: miss -> v2
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Model | `Map<String, String>` of paths | Composite `Dir` / `File` classes | Sealed inode set; parent links maintained only by moves; tree invariant checkable |
| Locking | One global lock | Per-directory locks, taken one at a time | Hand-over-hand top-down; `rm -r` waits for walkers inside; failure measured for the gap variant |
| Moves | Path string rewrite | Lock both parents | Rename lock so ancestry is stable for the cycle check; parents ancestor-first; reads and creates unaffected |
| Cache | One `HashMap` | L1/L2 LRU, invalidate on write | Versioned fills + tombstones (or leases); hit ratios per level measured |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Rename within the same directory" | Only that directory's write lock; no rename lock needed (no ancestry change) |
| "Hard links" | The tree becomes a DAG: inodes get link counts; `rmdir` is replaced by unlink, with the inode freed at link count 0; the cycle check applies to directories only (POSIX forbids directory hard links) |
| "Per-thread L1" | `ThreadLocal<Lru>` (or `thread_local` in C++): L1 hits need no lock. Invalidation must then reach every thread's L1: broadcast a version epoch that L1 checks on hit |
| "Writes must be visible everywhere at once" | Write-through with versioned entries; readers compare their entry's version to the file's version (one atomic read) and drop stale L1 entries |
| "Huge directories" | Children in a concurrent skip list; per-name locking (or optimistic version checks) instead of one lock per directory |
| "Crash consistency" | Journal metadata operations (mkdir/mv/rm) in a WAL before applying; moves are one journal record |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Lock each directory while you look up the next name. Isn't that enough?"</b></summary>

**L5:** "Each step is locked."

**Why it fails:** between unlocking the parent and locking the child, the child can be unlinked. Measured: 61–5,045 acknowledged creates landed in unlinked directories.

**L7 defence:** "Hand-over-hand: lock the child before releasing the parent, always top-down. `rm -r` takes the parent's write lock and then each victim's write lock top-down, so it waits for any walker inside and the create is ordered before the delete. Zero lost creates in every build."
</details>

<details>
<summary><b>Q2 🔥 "Two `mv` commands, each checks it isn't creating a cycle. Safe?"</b></summary>

**L5:** "Yes, each one checks."

**Why it fails:** `mv /a /b/a` and `mv /b /a/b` both pass their checks before either acts. Afterwards a and b contain each other, and neither is reachable from `/`.

**L7 defence:** "Serialize cross-directory moves on a rename lock, as Linux's `s_vfs_rename_mutex` does. Ancestry can't change while I hold it, so the check stays valid until I act. Lock the two parents ancestor-first. Reads, creates and same-directory renames don't take it."
</details>

<details>
<summary><b>Q3 ⚡ "We invalidate on write. How can the cache still serve old data?"</b></summary>

**L5:** "It can't, we delete the key."

**Why it fails:** a reader that read v1 *before* the write fills the cache *after* the invalidation. The listing shows `v1` served after v2 was written.

**L7 defence:** "Fills carry the version they read; invalidation leaves a tombstone with the new version, and fills older than it are refused. Leases are the token-based equivalent. And measure what each level buys: L2 serves 47% of reads here."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Created files vanish | Gap between unlocking the parent and locking the child | Hand-over-hand |
| Subtree unreachable after moves | Concurrent moves with stale cycle checks | Rename lock |
| Deadlock between `mv` and a walk | Parents locked in request order | Ancestor-first, else by id |
| Old content after a write | Cache-aside stale fill | Versioned fills + tombstones / leases |
| Hang on MinGW with many new directories | Lazy init of fresh `shared_mutex` | Warm in the constructor (P10) |

- [ ] Sealed inode set; tree invariant checked after stress.
- [ ] Hand-over-hand traversal; `rm -r` locks top-down and marks unlinked.
- [ ] Cross-directory moves under a rename lock; parents ancestor-first.
- [ ] Cache fills versioned; per-level hit ratios measured.

## 10. References

- Linux kernel documentation, *Directory Locking* (rename lock, ancestor-first ordering). <https://docs.kernel.org/filesystems/directory-locking.html>
- Nishtala et al., *Scaling Memcache at Facebook* (leases against stale sets), NSDI 2013. <https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala>
- Herlihy and Shavit, *The Art of Multiprocessor Programming* (hand-over-hand locking).
- In this KB: [P1 Cache architecture](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/01-problem-01-thread-safe-lru-and-lfu-ttl-cache-caffeine-architecture.md) · [P10 The shared_mutex lazy-init bug](../04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10/05-problem-10-meeting-room-scheduler-interval-tree-and-conflict-locking.md) · [02.3 Composite and Visitor](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/03-observer-event-bus-command-undo-redo-and-double-dispatch-visitor.md)
