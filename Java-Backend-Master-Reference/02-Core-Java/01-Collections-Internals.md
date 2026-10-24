# 2.1 · Collections Framework Internals — HashMap, ConcurrentHashMap, Lists, Deques, Trees, Immutables, Sequenced

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam (1Z0-830/831 "Using Arrays and Collections")
> **Sources:** OpenJDK `java.util` sources (JDK 25), JEP 269 (collection factories), JEP 431 (Sequenced Collections), Doug Lea's `ConcurrentHashMap` design notes (in the class's implementation comment), Joshua Bloch's *Effective Java* (3rd ed.).
> Several demos peek at private fields to *show* the internals. They need `--add-opens java.base/java.util=ALL-UNNAMED`, which is fine for learning and never appropriate in production code.

---

## 1. Complexity & footprint cheat sheet 🔥🎓

| Collection | get/contains | add/put | remove | Iteration order | Nulls | Per-element memory (Integer payload, legacy headers)* |
|---|---|---|---|---|---|---|
| `ArrayList` | O(1) index / O(n) contains | amortized O(1) at end, O(n) middle | O(n) | Insertion | ✅ | ~20 B (4 B slot + 16 B Integer) |
| `LinkedList` | O(n) | O(1) at ends | O(1) at ends, O(n) search | Insertion | ✅ | ~40 B (24 B node + 16 B Integer) |
| `ArrayDeque` | — | amortized O(1) both ends | O(1) ends | Insertion | ❌ | ~20 B |
| `PriorityQueue` | O(1) peek, O(n) contains | O(log n) | O(log n) poll, O(n) remove(Object) | **Not sorted** when iterated | ❌ | ~20 B |
| `HashMap` / `HashSet` | O(1) avg, O(log n) worst (treeified) | O(1) avg | O(1) avg | Unspecified | ✅ (one null key) | ~58 B / entry |
| `LinkedHashMap` | O(1) | O(1) | O(1) | Insertion or access | ✅ | ~66 B |
| `TreeMap` / `TreeSet` | O(log n) | O(log n) | O(log n) | Sorted | Keys ❌ (with natural ordering) | ~56 B |
| `EnumMap` / `EnumSet` | O(1) | O(1) | O(1) | Ordinal | Keys ❌ | Array slot / 1 bit |
| `IdentityHashMap` | O(1) avg | O(1) | O(1) | Unspecified | ✅ | Open addressing, two slots |
| `ConcurrentHashMap` | O(1), lock-free reads | O(1), CAS or bin lock | O(1) | Unspecified (weakly consistent) | ❌ | ~58 B |
| `CopyOnWriteArrayList` | O(1) / O(n) | **O(n)** (copies the array) | O(n) | Insertion (snapshot) | ✅ | ~20 B |
| `List.of` / `Set.of` / `Map.of` | O(1) / O(n) (List contains) | Immutable | Immutable | List: given; Set/Map: **randomized per JVM** | ❌ | Compact (no Node objects for Set/Map) |

\* Measured with JOL in [Pillar 1.3 §5](../01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md#5-what-collections-really-cost-jol-graphlayout-100k-entries-).

---

## 2. `HashMap` internals 🔥

### 2.1 Structure

```
HashMap
 ├─ Node<K,V>[] table        lazily allocated on first put; length = power of two (16 by default)
 ├─ int size, modCount        modCount drives fail-fast iterators
 ├─ int threshold             = capacity × loadFactor (0.75) → resize when ++size > threshold
 └─ float loadFactor

 bin i:  null | Node → Node → Node (singly linked, appended at the TAIL since JDK 8)
               | TreeNode (red-black tree, when the bin is long AND the table ≥ 64)

 Node { final int hash; final K key; V value; Node next; }          32 bytes (legacy headers)
 TreeNode extends LinkedHashMap.Entry { parent, left, right, prev; boolean red; }   ~2× a Node
```

### 2.2 Hashing, step by step

```java
static final int hash(Object key) {               // "spread"
    int h;
    return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
}
index = (table.length - 1) & hash;                // power-of-two mask instead of modulo
```

* **Why XOR the high bits down?** With a 16-slot table only the low 4 bits pick the bucket. Many `hashCode`s (`Float`, `Long` objects of small ranges, addresses-like values) differ mainly in the high bits. Folding them in is cheap insurance.
* **Why power-of-two tables?** `&` is a single instruction, much cheaper than integer division. The price is that bad low bits hurt, hence the spread.
* **`null` key** hashes to 0 and goes into bucket 0. `ConcurrentHashMap`, `TreeMap` (natural ordering) and `Map.of` reject nulls.

### 2.3 Resizing (doubling) without rehashing

When `++size > threshold`, the table doubles. Each node either stays at index `j` or moves to `j + oldCap`, decided by **one bit**: `(hash & oldCap) == 0`. JDK 8 splits each bin into a "lo" and a "hi" list **preserving order**. JDK 7 reversed lists during transfer (head insertion), which under concurrent misuse could create a **cycle**, giving the famous 100%-CPU infinite loop in `get()`. JDK 8+ can't loop that way, but concurrent writes to a `HashMap` still **lose entries or corrupt size**. Never share a mutable `HashMap` across threads without synchronization.

### 2.4 Treeification 🔥

| Constant | Value | Meaning |
|---|---|---|
| `TREEIFY_THRESHOLD` | 8 | A bin is converted to a tree when adding a node to a bin that already has 8 |
| `UNTREEIFY_THRESHOLD` | 6 | A tree bin with ≤ 6 nodes after a resize split is turned back into a list |
| `MIN_TREEIFY_CAPACITY` | 64 | If the table is smaller, **resize instead** of treeifying |

Tree ordering inside a bin: by `hash`, then by `compareTo` **if the keys are mutually `Comparable` of the same class**, then by `tieBreakOrder` (class name, then `System.identityHashCode`). **Lookup** in a tree bin is O(log n) only if keys are Comparable. Otherwise `find()` may have to search **both** subtrees, which degrades to O(n).

### 2.5 Runnable: watch the table grow, treeify, and pre-size correctly

<!-- run: jvm="--add-opens java.base/java.util=ALL-UNNAMED" -->
```java
import java.lang.reflect.Field;
import java.util.HashMap;

public class HashMapInternals {
    static final Field TABLE;
    static { try { TABLE = HashMap.class.getDeclaredField("table"); TABLE.setAccessible(true); } catch (Exception e) { throw new RuntimeException(e); } }

    static Object[] table(HashMap<?, ?> m) throws Exception { return (Object[]) TABLE.get(m); }
    static int capacity(HashMap<?, ?> m) throws Exception { Object[] t = table(m); return t == null ? 0 : t.length; }

    record Collider(int id) { @Override public int hashCode() { return 42; } }  // every key → same bin

    public static void main(String[] args) throws Exception {
        // 1. Lazy allocation and doubling at size > 0.75 × capacity
        var m = new HashMap<Integer, Integer>();
        StringBuilder sb = new StringBuilder("size→capacity: 0→" + capacity(m));
        for (int i = 1; i <= 49; i++) {
            m.put(i, i);
            if (i == 1 || i == 12 || i == 13 || i == 24 || i == 25 || i == 48 || i == 49) sb.append(", ").append(i).append("→").append(capacity(m));
        }
        System.out.println(sb);

        // 2. Treeification: 9th colliding node resizes (table < 64), 11th treeifies
        var c = new HashMap<Collider, Integer>();
        for (int i = 1; i <= 11; i++) {
            c.put(new Collider(i), i);
            if (i >= 8) {
                Object bin = table(c)[42 & (capacity(c) - 1)];
                System.out.printf("colliding keys=%2d capacity=%3d bin=%s%n", i, capacity(c), bin.getClass().getSimpleName());
            }
        }

        // 3. Pre-sizing for 1,000 entries: count the resizes
        for (String how : new String[] {"new HashMap<>()", "new HashMap<>(1000)", "HashMap.newHashMap(1000)"}) {
            HashMap<Integer, Integer> h = switch (how) {
                case "new HashMap<>()" -> new HashMap<>();
                case "new HashMap<>(1000)" -> new HashMap<>(1000);
                default -> HashMap.newHashMap(1000);
            };
            int resizes = 0, last = capacity(h);
            for (int i = 0; i < 1000; i++) {
                h.put(i, i);
                int now = capacity(h);
                if (now != last && last != 0) resizes++;
                last = now;
            }
            System.out.printf("%-26s final capacity=%4d resizes=%d%n", how, capacity(h), resizes);
        }
    }
}
```

Output (verified, JDK 25):

```
size→capacity: 0→0, 1→16, 12→16, 13→32, 24→32, 25→64, 48→64, 49→128
colliding keys= 8 capacity= 16 bin=Node
colliding keys= 9 capacity= 32 bin=Node
colliding keys=10 capacity= 64 bin=Node
colliding keys=11 capacity= 64 bin=TreeNode
new HashMap<>()            final capacity=2048 resizes=7
new HashMap<>(1000)        final capacity=2048 resizes=1
HashMap.newHashMap(1000)   final capacity=2048 resizes=0
```

> **🎓/🔥 `new HashMap<>(n)` is a capacity, not an expected size.** `new HashMap<>(1000)` allocates 1024 slots with a threshold of 768, so inserting 1,000 entries still resizes. Use **`HashMap.newHashMap(int expectedSize)`** (JDK 19+; also `HashSet.newHashSet`, `LinkedHashMap.newLinkedHashMap`), which computes `ceil(n / 0.75)`.

### 2.6 Collision attacks and why `Comparable` keys matter

<!-- run: -->
```java
import java.util.HashMap;
import java.util.Map;

public class CollisionCost {
    record PlainKey(int id) { @Override public int hashCode() { return 7; } }                 // not Comparable
    record CmpKey(int id) implements Comparable<CmpKey> {
        @Override public int hashCode() { return 7; }
        @Override public int compareTo(CmpKey o) { return Integer.compare(id, o.id); }
    }

    static <K> long timeLookups(Map<K, Integer> map, K[] keys) {
        long start = System.nanoTime(); long sink = 0;
        for (K k : keys) sink += map.get(k);
        if (sink == 42) System.out.print("");
        return (System.nanoTime() - start) / 1_000_000;
    }

    public static void main(String[] args) {
        int n = 10_000;
        var plain = new HashMap<PlainKey, Integer>(); var cmp = new HashMap<CmpKey, Integer>();
        PlainKey[] pk = new PlainKey[n]; CmpKey[] ck = new CmpKey[n];
        for (int i = 0; i < n; i++) {
            pk[i] = new PlainKey(i); ck[i] = new CmpKey(i);
            plain.put(pk[i], i); cmp.put(ck[i], i);
        }
        timeLookups(cmp, ck); timeLookups(plain, pk);               // warm-up
        System.out.println("10k lookups, all keys in ONE bin:");
        System.out.println("  Comparable keys     : " + timeLookups(cmp, ck) + " ms   (tree ordered by compareTo → O(log n))");
        System.out.println("  non-Comparable keys : " + timeLookups(plain, pk) + " ms   (tree can't order them → O(n) search)");
        System.out.println("\"Aa\".hashCode()==\"BB\".hashCode(): " + ("Aa".hashCode() == "BB".hashCode())
            + "  → 2^k colliding Strings like AaAa, AaBB, BBAa, BBBB");
    }
}
```

Output (measured; times vary by machine):

```
10k lookups, all keys in ONE bin:
  Comparable keys     : 1 ms   (tree ordered by compareTo → O(log n))
  non-Comparable keys : 247 ms   (tree can't order them → O(n) search)
"Aa".hashCode()=="BB".hashCode(): true  → 2^k colliding Strings like AaAa, AaBB, BBAa, BBBB
```

**Hash-flooding DoS:** an attacker who controls keys (HTTP parameters, JSON field names, headers) can craft colliding `String`s. Because `String` is `Comparable`, treeification limits the damage to O(log n) per operation. That is the reason JDK 8 removed JDK 7's alternative String hashing. **Custom key types** used for untrusted input should implement `Comparable` *consistently with equals*, and frameworks still cap parameter and field counts (Tomcat `maxParameterCount`, Jackson `StreamReadConstraints`).

### 2.7 Iteration cost is O(capacity + size)

Iterating a `HashMap` walks the **whole table**. A map that once held 1M entries and now holds 10 still iterates 1M+ slots, because `HashMap` never shrinks. For long-lived maps that spike, re-create them (`new HashMap<>(old)` sizes to the current content), or use `LinkedHashMap`, whose iteration follows the linked list (O(size)).

### 2.8 `equals`/`hashCode` contract failures 🔥🎓

<!-- run: -->
```java
import java.math.BigDecimal;
import java.util.*;

public class KeyContracts {
    static final class MutableKey {
        String name;
        MutableKey(String n) { name = n; }
        @Override public boolean equals(Object o) { return o instanceof MutableKey k && k.name.equals(name); }
        @Override public int hashCode() { return name.hashCode(); }
    }

    public static void main(String[] args) {
        // 1. Mutating a key after insertion: the entry becomes unreachable through lookups
        Map<MutableKey, String> m = new HashMap<>();
        MutableKey k = new MutableKey("alice");
        m.put(k, "admin");
        k.name = "bob";
        System.out.println("get(bob)=" + m.get(new MutableKey("bob")) + ", get(alice)=" + m.get(new MutableKey("alice"))
            + ", size=" + m.size() + ", containsValue(admin)=" + m.containsValue("admin"));

        // 2. HashSet uses equals(); TreeSet uses compareTo() — BigDecimal disagrees
        var hs = new HashSet<BigDecimal>(List.of(new BigDecimal("1.0"), new BigDecimal("1.00")));
        var ts = new TreeSet<BigDecimal>(List.of(new BigDecimal("1.0"), new BigDecimal("1.00")));
        System.out.println("HashSet size=" + hs.size() + " (equals compares scale), TreeSet size=" + ts.size() + " (compareTo ignores scale)");

        // 3. A comparator inconsistent with equals silently drops "duplicates"
        var byLength = new TreeSet<String>(Comparator.comparingInt(String::length));
        byLength.addAll(List.of("pear", "plum", "fig", "kiwi"));
        System.out.println("TreeSet by length: " + byLength + "  (plum and kiwi vanished)");
    }
}
```

Output (verified):

```
get(bob)=null, get(alice)=null, size=1, containsValue(admin)=true
HashSet size=2 (equals compares scale), TreeSet size=1 (compareTo ignores scale)
TreeSet by length: [fig, pear]  (plum and kiwi vanished)
```

**Rules:** keys must be **effectively immutable** (records are ideal). `hashCode` must be consistent with `equals`. Sorted collections use **only** the comparator, never `equals`. Enum `hashCode()` is identity-based, so it differs between JVM runs: never persist hash codes or rely on `HashMap` iteration order across runs.

---

## 3. `LinkedHashMap`, LRU caches, `TreeMap` ⚡🎓

* `LinkedHashMap` = `HashMap` + a doubly linked list (`before`/`after`) through all entries. `accessOrder=true` moves an entry to the tail on `get`. Overriding `removeEldestEntry` gives a simple **LRU cache**. It is not thread-safe; in production use Caffeine (W-TinyLFU, concurrent, size- or weight-bounded).
* `TreeMap` is a **red-black tree**: O(log n), sorted, with `NavigableMap` operations (`floorKey`, `ceilingEntry`, `headMap`/`tailMap`/`subMap` **live views**, `descendingMap`, `pollFirstEntry`). It is ideal for range queries, time-bucketed data and order books.

<!-- run: -->
```java
import java.util.*;

public class LruAndNavigable {
    static <K, V> Map<K, V> lru(int max) {
        return new LinkedHashMap<>(16, 0.75f, true) {                      // accessOrder = true
            @Override protected boolean removeEldestEntry(Map.Entry<K, V> eldest) { return size() > max; }
        };
    }

    public static void main(String[] args) {
        Map<String, Integer> cache = lru(3);
        cache.put("a", 1); cache.put("b", 2); cache.put("c", 3);
        cache.get("a");                        // a becomes most-recently used
        cache.put("d", 4);                     // evicts b (least recently used)
        System.out.println("LRU: " + cache.keySet());

        TreeMap<Integer, String> slaTiers = new TreeMap<>(Map.of(0, "bronze", 100, "silver", 1000, "gold"));
        System.out.println("tier for 250 = " + slaTiers.floorEntry(250).getValue()
            + ", next threshold = " + slaTiers.higherKey(250)
            + ", headMap(1000) = " + slaTiers.headMap(1000));
    }
}
```

Output (verified):

```
LRU: [c, a, d]
tier for 250 = silver, next threshold = 1000, headMap(1000) = {0=bronze, 100=silver}
```

---

## 4. Lists, deques and queues ⚡🎓

### 4.1 `ArrayList` growth

* The backing array is allocated **lazily**: a `new ArrayList<>()` starts with a shared empty array and allocates 10 slots on the first `add`.
* Growth: `newCapacity = old + max(needed, old >> 1)` (via `ArraysSupport.newLength`), i.e. **×1.5**: 10 → 15 → 22 → 33 → 49 → 73 → …
* Every growth copies the array (`Arrays.copyOf`). Pre-size with `new ArrayList<>(n)` or `ensureCapacity(n)` when n is known. `trimToSize()` releases slack.
* `remove(int index)` vs `remove(Object o)`: `list.remove(1)` on a `List<Integer>` removes **index 1**. Use `remove(Integer.valueOf(1))` to remove the value. This is an exam favourite.
* `subList` is a **view**. Structural changes to the parent invalidate it, and the next access throws `ConcurrentModificationException`.
* `Arrays.asList(array)` is **fixed-size and backed by the array**: `set` writes through, `add`/`remove` throw `UnsupportedOperationException`.

<!-- run: jvm="--add-opens java.base/java.util=ALL-UNNAMED" -->
```java
import java.lang.reflect.Field;
import java.util.*;

public class ListTraps {
    public static void main(String[] args) throws Exception {
        Field data = ArrayList.class.getDeclaredField("elementData"); data.setAccessible(true);
        var list = new ArrayList<Integer>();
        StringBuilder caps = new StringBuilder("capacities: " + ((Object[]) data.get(list)).length);
        int last = -1;
        for (int i = 0; i < 100; i++) {
            list.add(i);
            int cap = ((Object[]) data.get(list)).length;
            if (cap != last) { caps.append(" → ").append(cap); last = cap; }
        }
        System.out.println(caps);

        List<Integer> nums = new ArrayList<>(List.of(10, 20, 30));
        nums.remove(1);                                // index!
        System.out.println("after remove(1): " + nums);
        nums.remove(Integer.valueOf(10));              // value
        System.out.println("after remove(Integer.valueOf(10)): " + nums);

        String[] backing = {"x", "y"};
        List<String> fixed = Arrays.asList(backing);
        fixed.set(0, "X");
        System.out.println("Arrays.asList writes through: " + Arrays.toString(backing));
        try { fixed.add("z"); } catch (UnsupportedOperationException e) { System.out.println("Arrays.asList add → UnsupportedOperationException"); }

        List<Integer> parent = new ArrayList<>(List.of(1, 2, 3, 4));
        List<Integer> view = parent.subList(1, 3);
        parent.add(5);
        try { view.size(); } catch (ConcurrentModificationException e) { System.out.println("subList after parent change → ConcurrentModificationException"); }

        PriorityQueue<Integer> pq = new PriorityQueue<>(List.of(5, 1, 4, 2, 3));
        System.out.print("PriorityQueue toString (heap order, NOT sorted): " + pq + " | poll order: ");
        while (!pq.isEmpty()) System.out.print(pq.poll() + " ");
        System.out.println();
    }
}
```

Output (verified):

```
capacities: 0 → 10 → 15 → 22 → 33 → 49 → 73 → 109
after remove(1): [10, 30]
after remove(Integer.valueOf(10)): [30]
Arrays.asList writes through: [X, y]
Arrays.asList add → UnsupportedOperationException
subList after parent change → ConcurrentModificationException
PriorityQueue toString (heap order, NOT sorted): [1, 2, 4, 5, 3] | poll order: 1 2 3 4 5
```

### 4.2 `ArrayDeque` vs `LinkedList` vs `Stack`

* `ArrayDeque` is a **circular array** with head and tail indices, no per-element node, and is cache-friendly. It is the right choice for stacks (`push`/`pop`) and FIFO queues on a single thread. **It rejects `null`** (null is the "empty" signal of `poll()`).
* `LinkedList` costs ~24 B per node plus pointer chasing. Its only real advantage is O(1) removal at a known position through a `ListIterator`. Prefer `ArrayDeque`/`ArrayList` almost always.
* `Stack` extends `Vector`, so every method is synchronized, and it is legacy. Use `ArrayDeque`.
* `PriorityQueue` is a binary heap in an array. Its iterator and `toString` show **heap order, not sorted order** (see the output above).

---

## 5. Specialized maps and sets ⚡

| Type | Internals | When |
|---|---|---|
| `EnumMap<K,V>` | `Object[]` indexed by `ordinal()` | Any map keyed by an enum: faster and smaller than `HashMap` |
| `EnumSet` | `RegularEnumSet`: a single `long` bit vector (≤ 64 constants); `JumboEnumSet`: `long[]` | Flags and permissions: bit operations, no boxing |
| `IdentityHashMap` | Open addressing with linear probing; keys and values interleaved in one `Object[]`; uses `==` and `identityHashCode` | Graph traversal (visited sets), serialization, proxies. **Breaks the `Map` contract on purpose** |
| `WeakHashMap` | `Entry extends WeakReference<K>` + `ReferenceQueue`; stale entries expunged on access | Metadata attached to objects you don't own. **Leak:** a value referencing its key keeps the key strongly reachable |
| `BitSet` | `long[]` words | Dense integer sets: bloom-ish flags, sieves |

---

## 6. Immutable and unmodifiable collections 🔥🎓

| API | Copy or view? | Nulls | Mutation | Notes |
|---|---|---|---|---|
| `List.of(…)`, `Set.of(…)`, `Map.of(…)`, `Map.ofEntries` | Immutable **copy** | ❌ NPE (even `contains(null)` throws NPE) | `UnsupportedOperationException` | `Set.of`/`Map.of` reject duplicates (`IllegalArgumentException`) and iterate in a **randomized order per JVM run** (salted) |
| `List.copyOf(c)` etc. | Immutable copy (returns the **same instance** if `c` is already immutable) | ❌ | UOE | Defensive copies in records/constructors |
| `Collections.unmodifiableList(l)` | **View** | ✅ | UOE through the view | **Changes to `l` show through.** Not immutable |
| `Stream.toList()` (16+) | Unmodifiable list | ✅ allows null | UOE | `collect(Collectors.toList())` returns a mutable `ArrayList` (unspecified, in practice) |
| `Arrays.asList` | Fixed-size view over the array | ✅ | `set` OK; add/remove UOE | Writes through |

<!-- run: -->
```java
import java.util.*;
import java.util.stream.Stream;

public class ImmutableTraps {
    static void attempt(String label, Runnable r) {
        try { r.run(); System.out.println(label + " → ok"); }
        catch (RuntimeException e) { System.out.println(label + " → " + e.getClass().getSimpleName()); }
    }

    public static void main(String[] args) {
        List<String> lst = List.of("a", "b");
        attempt("List.of(...).add", () -> lst.add("c"));
        attempt("List.of(...).contains(null)", () -> lst.contains(null));
        attempt("List.of(\"a\", null)", () -> List.of("a", null));
        attempt("Set.of(\"a\",\"a\")", () -> Set.of("a", "a"));
        attempt("Map.of(\"k\",1,\"k\",2)", () -> Map.of("k", 1, "k", 2));

        List<String> backing = new ArrayList<>(List.of("x"));
        List<String> view = Collections.unmodifiableList(backing);
        List<String> copy = List.copyOf(backing);
        backing.add("y");
        System.out.println("unmodifiable view sees change: " + view + ", copyOf does not: " + copy);
        System.out.println("List.copyOf(immutable) returns same instance: " + (List.copyOf(lst) == lst));

        List<String> withNull = Stream.of("p", null).toList();
        System.out.println("Stream.toList() allows null: " + withNull);
        attempt("Stream.toList().add", () -> withNull.add("q"));
    }
}
```

Output (verified):

```
List.of(...).add → UnsupportedOperationException
List.of(...).contains(null) → NullPointerException
List.of("a", null) → NullPointerException
Set.of("a","a") → IllegalArgumentException
Map.of("k",1,"k",2) → IllegalArgumentException
unmodifiable view sees change: [x, y], copyOf does not: [x]
List.copyOf(immutable) returns same instance: true
Stream.toList() allows null: [p, null]
Stream.toList().add → UnsupportedOperationException
```

**Internals:** `ImmutableCollections.List12`/`ListN`, `Set12`/`SetN`, `Map1`/`MapN`. `SetN` and `MapN` use **open addressing** over a flat array with a probe start derived from `hashCode` XOR a per-JVM `SALT`. That gives no `Node` objects (less memory than `HashMap`) and deliberately unstable iteration order, so code can't depend on it.

---

## 7. Sequenced Collections (JDK 21, JEP 431) 🔥🎓

New interfaces retrofit a uniform "first/last/reversed" API:

```
SequencedCollection<E>  : addFirst, addLast, getFirst, getLast, removeFirst, removeLast, reversed()
  ├─ List<E>, Deque<E>
  └─ SequencedSet<E> : reversed() returns SequencedSet  ← LinkedHashSet, SortedSet/NavigableSet
SequencedMap<K,V>        : firstEntry, lastEntry, pollFirstEntry, pollLastEntry, putFirst, putLast,
                           reversed(), sequencedKeySet(), sequencedValues(), sequencedEntrySet()
                           ← LinkedHashMap, SortedMap/NavigableMap
```

<!-- run: -->
```java
import java.util.*;

public class SequencedDemo {
    public static void main(String[] args) {
        List<Integer> list = new ArrayList<>(List.of(1, 2, 3));
        list.addFirst(0);                                   // ArrayList: O(n) shift
        System.out.println(list.getFirst() + " " + list.getLast() + " " + list.reversed());

        var lhs = new LinkedHashSet<>(List.of("b", "c"));
        lhs.addFirst("a");                                  // moves/inserts at the front
        lhs.addLast("b");                                   // existing element is MOVED to the end
        System.out.println(lhs + " reversed=" + lhs.reversed());

        var lhm = new LinkedHashMap<String, Integer>();
        lhm.put("x", 1); lhm.put("y", 2);
        lhm.putFirst("w", 0);
        System.out.println(lhm + " first=" + lhm.firstEntry() + " pollLast=" + lhm.pollLastEntry() + " now=" + lhm);

        List<Integer> rev = list.reversed();                // a VIEW, not a copy
        list.add(99);
        System.out.println("reversed view: " + rev);
        try { new ArrayList<Integer>().getFirst(); }
        catch (NoSuchElementException e) { System.out.println("getFirst on empty → NoSuchElementException"); }
        try { List.of(1, 2).reversed().addFirst(0); }
        catch (UnsupportedOperationException e) { System.out.println("reversed() of immutable list is unmodifiable"); }
    }
}
```

Output (verified):

```
0 3 [3, 2, 1, 0]
[a, c, b] reversed=[b, c, a]
{w=0, x=1, y=2} first=w=0 pollLast=y=2 now={w=0, x=1}
reversed view: [99, 3, 2, 1, 0]
getFirst on empty → NoSuchElementException
reversed() of immutable list is unmodifiable
```

---

## 8. Iterators: fail-fast vs snapshot vs weakly consistent 🔥🎓

| Kind | Collections | Behaviour on concurrent modification | `iterator.remove()` |
|---|---|---|---|
| **Fail-fast** | `ArrayList`, `HashMap`, `HashSet`, `TreeMap`, `LinkedList`, … | Best-effort `ConcurrentModificationException`, triggered by a `modCount` mismatch, **even single-threaded** | ✅ (the only safe way to remove during iteration) |
| **Snapshot** ("fail-safe") | `CopyOnWriteArrayList`, `CopyOnWriteArraySet` | Iterates the array as of iterator creation; never throws; doesn't see later changes | ❌ UOE |
| **Weakly consistent** | `ConcurrentHashMap`, `ConcurrentLinkedQueue`, `ConcurrentSkipListMap`, `LinkedBlockingQueue` | Never throws; reflects some, all or none of the changes made after creation; each element at most once | ✅ |

<!-- run: -->
```java
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

public class IteratorSemantics {
    public static void main(String[] args) {
        List<String> a = new ArrayList<>(List.of("a", "b", "c", "d"));
        try { for (String s : a) if (s.equals("b")) a.remove(s); }
        catch (ConcurrentModificationException e) { System.out.println("remove 'b' in for-each → CME"); }

        List<String> b = new ArrayList<>(List.of("a", "b", "c", "d"));
        for (String s : b) if (s.equals("c")) b.remove(s);   // removing the SECOND-TO-LAST element...
        System.out.println("remove 'c' (second-to-last) in for-each → no CME, list=" + b + "  (hasNext() saw size==cursor)");

        List<String> c = new ArrayList<>(List.of("a", "b", "c", "d"));
        c.removeIf(s -> s.compareTo("b") <= 0);               // correct bulk removal (one pass)
        for (Iterator<String> it = c.iterator(); it.hasNext(); ) if (it.next().equals("d")) it.remove();
        System.out.println("removeIf + iterator.remove → " + c);

        List<String> cow = new CopyOnWriteArrayList<>(List.of("x", "y"));
        for (String s : cow) cow.add(s + "!");                // iterates the snapshot: no CME, no infinite loop
        System.out.println("CopyOnWriteArrayList after add-in-loop: " + cow);

        Map<String, Integer> chm = new ConcurrentHashMap<>(Map.of("k1", 1, "k2", 2));
        for (String k : chm.keySet()) chm.put(k + "x", 0);    // weakly consistent: legal, may or may not see new keys
        System.out.println("ConcurrentHashMap size after put-in-loop ≥ 4: " + (chm.size() >= 4));
    }
}
```

Output (verified):

```
remove 'b' in for-each → CME
remove 'c' (second-to-last) in for-each → no CME, list=[a, b, d]  (hasNext() saw size==cursor)
removeIf + iterator.remove → [c]
CopyOnWriteArrayList after add-in-loop: [x, y, x!, y!]
ConcurrentHashMap size after put-in-loop ≥ 4: true
```

> **Exam trap explained:** after removing `"c"` the size drops to 3, and the iterator's cursor is 3, so `hasNext()` (`cursor != size`) returns false. The loop ends **before** `next()` performs the `modCount` check. Fail-fast behaviour is *best-effort*; never rely on CME for correctness.

---

## 9. `ConcurrentHashMap` internals (JDK 8+) 🔥

### 9.1 Design

```
ConcurrentHashMap
 ├─ volatile Node<K,V>[] table            power of two; lazily initialized (CAS on sizeCtl)
 ├─ volatile Node<K,V>[] nextTable        non-null only during resize
 ├─ volatile int sizeCtl                   >0: next resize threshold; -1: initializing;
 │                                         other negatives: resize in progress (encodes a resize stamp + #helpers)
 ├─ volatile long baseCount + CounterCell[] counterCells   ← LongAdder-style striped size counter (@Contended cells)
 └─ volatile int transferIndex             next bin range to hand to a resize helper

 Bin head kinds (by hash field):
   hash ≥ 0     Node          ordinary linked list (val and next are volatile)
   MOVED  (-1)  ForwardingNode   bin already transferred → readers/writers go to nextTable
   TREEBIN(-2)  TreeBin       red-black tree of TreeNodes + a tiny read/write lock (lockState)
   RESERVED(-3) ReservationNode   placeholder while computeIfAbsent/compute runs on an empty bin
```

* JDK 7's segments (16 `ReentrantLock` stripes) are gone. Concurrency is now **per bin**.

### 9.2 Operations

| Operation | Mechanism |
|---|---|
| `get(k)` | **No locks.** Volatile read of the bin head (`tabAt` = acquire load), compare the head; if `hash < 0`, delegate to `find` (forwarding node → `nextTable`; tree bin → read lock or a linear walk if a writer holds it); otherwise walk the list. Values are volatile, so readers see completed writes |
| `put` on an **empty** bin | **CAS** the new node into the slot. No lock |
| `put` on a non-empty bin | `synchronized (headNode)`, re-check that the head is unchanged, append or update, treeify at 8 nodes (table ≥ 64) |
| `put` with `putIfAbsent` and a matching head key (JDK 9+) | Returns without locking (fast path) |
| Size update | `addCount`: CAS `baseCount`; under contention, CAS a randomly chosen `CounterCell` (by `ThreadLocalRandom` probe) |
| **Resize** | Triggered when the count exceeds `sizeCtl` (0.75 × n). **Multiple threads cooperate**: each claims a range of bins (stride ≥ 16) by CASing `transferIndex` downward, locks each bin, splits it into lo/hi lists in `nextTable`, then installs a `ForwardingNode`. Writers that hit a `ForwardingNode` call `helpTransfer` |
| `size()` | `sumCount()` = `baseCount` + Σ cells, a **moment-in-time estimate** under concurrent updates. Prefer `mappingCount()` (long) |
| Bulk ops | `forEach/search/reduce(parallelismThreshold, …)` run on `ForkJoinPool.commonPool()` above the threshold |

### 9.3 `compute*`/`merge` semantics and the recursion trap 🔥

`computeIfAbsent`, `compute`, `computeIfPresent` and `merge` run the function **while holding the bin's lock** (or a `ReservationNode` for an empty bin). They are atomic per key, but:

* **Keep functions short.** Every other writer to that bin (and a resizer) waits. Never do I/O or remote calls in them; use a cache library with async loading instead.
* **Never modify the same map inside the function.** If it touches the same bin, JDK 9+ detects it and throws `IllegalStateException: Recursive update`. If it touches another bin, you can deadlock under contention or corrupt invariants.

<!-- run: -->
```java
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class ChmRecursion {
    static final Map<Integer, Long> memo = new ConcurrentHashMap<>();

    static long fibBroken(int n) {                       // classic memoized recursion — WRONG with CHM
        if (n < 2) return n;
        return memo.computeIfAbsent(n, k -> fibBroken(k - 1) + fibBroken(k - 2));
    }

    static long fibCorrect(int n) {                      // compute outside, then putIfAbsent
        if (n < 2) return n;
        Long cached = memo.get(n);
        if (cached != null) return cached;
        long v = fibCorrect(n - 1) + fibCorrect(n - 2);
        Long prev = memo.putIfAbsent(n, v);
        return prev != null ? prev : v;
    }

    public static void main(String[] args) {
        try { System.out.println(fibBroken(30)); }
        catch (IllegalStateException e) { System.out.println("computeIfAbsent recursion → " + e); }
        memo.clear();
        System.out.println("fibCorrect(80) = " + fibCorrect(80));
    }
}
```

Output (verified):

```
computeIfAbsent recursion → java.lang.IllegalStateException: Recursive update
fibCorrect(80) = 23416728348467685
```

### 9.4 Why no `null`s?

In a concurrent map, `get(k) == null` must unambiguously mean "absent". With `HashMap` you'd call `containsKey` to disambiguate, but between the two calls another thread may change the map. Banning `null` removes the race. Model "known absent" with `Optional` or a sentinel value.

### 9.5 `ConcurrentHashMap` vs alternatives

| | `Hashtable` / `Collections.synchronizedMap` | `ConcurrentHashMap` | `ConcurrentSkipListMap` |
|---|---|---|---|
| Locking | One lock for everything | Lock-free reads; CAS or per-bin locks for writes | Lock-free (CAS) |
| Compound atomic ops | Must lock the map externally (`synchronized(map) { if (!containsKey) put }`) | Built-in: `putIfAbsent`, `compute*`, `merge`, `replace(k, old, new)` | Same, plus sorted navigation |
| Iteration | Must hold the lock while iterating, or risk CME | Weakly consistent, no lock | Weakly consistent, sorted |
| Ordering | — | — | **Sorted** (O(log n)) |
| Nulls | `synchronizedMap` allows them (if the backing map does) | ❌ | ❌ |

---

## 10. Production failure modes & diagnostics (collections)

| Failure | Signature | Fix |
|---|---|---|
| Shared `HashMap` written by multiple threads | Lost updates, wrong `size()`, rarely corrupted structures; on JDK 7, a 100% CPU loop in `get()` | `ConcurrentHashMap`, or confine/synchronize |
| `computeIfAbsent` doing remote calls | Thread dumps show many threads `BLOCKED` on the same CHM bin monitor | Caffeine `AsyncLoadingCache`; compute outside the map |
| `IllegalStateException: Recursive update` | Memoization via nested `computeIfAbsent` | Compute outside, then `putIfAbsent` |
| Memory blow-up | `HashMap$Node`, `Integer` dominate `GC.class_histogram` | Primitive maps (fastutil/Eclipse Collections), arrays, `EnumMap`/`BitSet` |
| Slow iteration of a near-empty map | Map spiked once and never shrinks | Re-create the map; `LinkedHashMap` |
| Hash-flooding CPU spike | Many requests with many parameters/fields; hot `HashMap.find`/`TreeNode.find` | Request limits; Comparable keys; framework caps |
| Entries "disappear" | Mutable keys; comparator inconsistent with equals | Immutable keys (records); consistent comparators |
| `UnsupportedOperationException` in prod | Mutating `List.of`/`Stream.toList()`/`Arrays.asList` results returned by a library | Copy into a mutable collection at the boundary |
| Flaky tests depending on `Set.of`/`Map.of`/`HashMap` order | Order varies per JVM (salted) or per capacity | Use `LinkedHashMap`/sorted collections, or assert order-insensitively |
| `ConcurrentModificationException` in a single thread | Removal inside for-each; parent modified under a `subList` | `removeIf`, `iterator.remove()`, copy before iterating |

**Commands:** `jcmd <pid> GC.class_histogram | head -30` (count `HashMap$Node`, `TreeNode`); a heap dump in MAT ("Collections" → "Hash Entries", "Collection Fill Ratio", "Map Collision Ratio" queries); async-profiler CPU flame graphs for `HashMap.getNode`/`TreeNode.find` hot spots.

---

## 11. Interview & certification Q&A

<details><summary><b>Q1. 🔥 Walk through `HashMap.put` from `hashCode()` to storage, including resize and treeify.</b></summary>

Compute `h ^ (h >>> 16)` of the key's `hashCode` (0 for null), and index with `(n-1) & hash`. If the table is null, allocate it (16 by default). If the bin is empty, store a new `Node`. Otherwise walk the bin: if a node with equal hash and `equals` key exists, replace its value; else append at the tail. If the bin reaches 8+ nodes, treeify (if the table has fewer than 64 slots, resize instead). Increment `modCount` and `size`; if `size > threshold` (0.75 × capacity), double the table, splitting each bin into lo/hi lists by `hash & oldCap`, preserving order.
</details>

<details><summary><b>Q2. 🔥 How does `ConcurrentHashMap` achieve thread safety without locking reads?</b></summary>

The table and node `val`/`next` fields are volatile (or accessed with acquire/release semantics), so a reader that sees a node sees its fully constructed state. Insertions into empty bins use CAS, while updates to non-empty bins lock only the bin's head node. Resize installs `ForwardingNode`s so readers can follow moved bins. Tree bins carry a small read/write lock. Counting uses striped `CounterCell`s. The result is lock-free `get`, fine-grained writes and cooperative resizing.
</details>

<details><summary><b>Q3. 🎓 What does this print?<br><code>List&lt;Integer&gt; l = new ArrayList&lt;&gt;(List.of(1,2,3)); l.remove(1); l.remove(Integer.valueOf(1)); System.out.println(l);</code></b></summary>

`[3]`. `remove(1)` removes the element at index 1 (the value 2), giving `[1, 3]`. `remove(Integer.valueOf(1))` removes the value 1, giving `[3]`.
</details>

<details><summary><b>Q4. 🔥 Why is `new HashMap<>(1000)` not enough to avoid a resize when inserting 1000 entries? What should you use?</b></summary>

The argument is the initial capacity, rounded up to 1024, with a threshold of 1024 × 0.75 = 768, so the 769th insert resizes. Use `HashMap.newHashMap(1000)` (JDK 19+), which sizes for 1000 entries at the default load factor, or `new HashMap<>((int) Math.ceil(1000 / 0.75))`.
</details>

<details><summary><b>Q5. ⚡ Why does a tree bin with non-`Comparable` keys still perform poorly?</b></summary>

The red-black tree orders by hash first. With identical hashes and no `Comparable` ordering, `tieBreakOrder` fixes an *insertion* position, but lookups can't use it (it depends on identity hashes of other instances). `find` must then explore both subtrees, giving O(n) lookups (measured: 1 ms vs 247 ms for 10k lookups).
</details>

<details><summary><b>Q6. 🎓 Which collections allow `null`? `HashMap` key, `TreeMap` key, `ArrayDeque` element, `List.of` element, `ConcurrentHashMap` value, `ArrayList` element?</b></summary>

Allowed: `HashMap` key (one) and `ArrayList` elements. Rejected: `TreeMap` keys with natural ordering (NPE on compare; a custom null-tolerant comparator can allow them), `ArrayDeque` elements, `List.of` elements, and `ConcurrentHashMap` keys and values.
</details>

<details><summary><b>Q7. 🔥 Explain fail-fast vs weakly consistent iterators and how CME can occur in a single thread.</b></summary>

Fail-fast iterators record `modCount` at creation and throw `ConcurrentModificationException` when they detect a structural modification not made through the iterator. That happens even in one thread, e.g. `list.remove` inside a for-each. Weakly consistent iterators (concurrent collections) never throw, traverse a state that may or may not include concurrent changes, and return each element at most once. Snapshot iterators (`CopyOnWriteArrayList`) iterate an immutable array copy.
</details>

<details><summary><b>Q8. 🎓 `Set.of("a","b","c")` iteration order — what is guaranteed?</b></summary>

Nothing. The order is unspecified and deliberately randomized per JVM instance (salted probing), so it can differ between runs. Use `LinkedHashSet` or sorted sets when order matters.
</details>

<details><summary><b>Q9. ⚡ When would you choose `TreeMap` over `HashMap`, and `ConcurrentSkipListMap` over `ConcurrentHashMap`?</b></summary>

When you need ordering or range queries: floor/ceiling lookups, sub-maps, first/last, descending iteration (pricing tiers, time series, leaderboards). `ConcurrentSkipListMap` gives the same in a concurrent, lock-free form (at O(log n) cost, with more memory per entry than CHM).
</details>

<details><summary><b>Q10. 🔥 What's wrong with `computeIfAbsent(key, k -> remoteService.load(k))` on a `ConcurrentHashMap` in a web service?</b></summary>

The remote call runs while holding the bin lock. Every other thread writing to keys in the same bin, and any resize, blocks for the call's duration, causing thread pile-ups (BLOCKED threads in dumps). Recursive map access inside it can also throw `Recursive update` or deadlock. Use an async cache (Caffeine `AsyncLoadingCache`, which holds a future per key) or load outside the map.
</details>

<details><summary><b>Q11. 🎓 What does `Collections.unmodifiableList(list)` guarantee vs `List.copyOf(list)`?</b></summary>

`unmodifiableList` returns a read-only **view**: callers can't modify through it, but changes to the underlying list are visible. `List.copyOf` returns an immutable **copy** (rejecting nulls) that never changes. It returns the argument itself if that is already an immutable list.
</details>

<details><summary><b>Q12. ⚡ Sequenced collections: what does `LinkedHashSet.addLast(e)` do if `e` is already present?</b></summary>

It moves the existing element to the end. (Plain `add` of an existing element does nothing.) `addFirst` similarly moves it to the front. `reversed()` returns a live reversed view.
</details>

---

## 12. Further reading

* `java.util.HashMap` and `java.util.concurrent.ConcurrentHashMap` source comments (JDK 25): the "Implementation notes" are the best documentation.
* JEP 431 Sequenced Collections: <https://openjdk.org/jeps/431>
* Caffeine design (W-TinyLFU): <https://github.com/ben-manes/caffeine/wiki/Design>
* fastutil / Eclipse Collections / Agrona for primitive collections.
