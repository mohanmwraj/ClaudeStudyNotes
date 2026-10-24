# 4.6 · Pillar 4 — Interview & Certification Question Bank (I/O, NIO, Networking, Serialization)

> **Use:** A = flashcards, B = senior scenarios, C = 1Z0-830/831-style code questions for "Console and file I/O", "Serialization and deserialization", and "Path objects and the java.nio.file API" (original practice items). **Every program in C was run on JDK 25.** Paths are printed with `/` separators via a helper so the answers are OS-independent.

---

## A. Rapid-fire

<details><summary><b>A1–A15</b></summary>

1. **Default charset since JDK 18?** UTF-8 (JEP 400). The OS encoding is in `native.encoding`.
2. **Do `Path` methods touch the file system?** No (except `toRealPath`, and `toAbsolutePath` uses the working directory).
3. **`Path.of("a").resolve("/b")`?** Returns `/b` (an absolute argument wins).
4. **`Files.lines` must be…?** Closed (it holds an open file handle).
5. **`Files.copy` onto an existing file?** `FileAlreadyExistsException`, unless `REPLACE_EXISTING`. Onto itself it's a no-op.
6. **`Files.delete` on a non-empty directory?** `DirectoryNotEmptyException`.
7. **`ByteBuffer.flip()`?** limit = position; position = 0.
8. **Java's Selector on Linux / macOS / Windows?** epoll / kqueue / wepoll.
9. **What does `SO_TIMEOUT=0` mean?** Reads block forever.
10. **`HttpClient` defaults?** HTTP/2 preferred, no connect timeout, no request timeout, no redirects.
11. **Netty 4.2 default allocator?** `AdaptiveByteBufAllocator`.
12. **Who releases a Netty `ByteBuf`?** Its last consumer (`SimpleChannelInboundHandler` auto-releases).
13. **Is a serializable class's constructor called on deserialization?** No; only the first non-serializable superclass's no-arg constructor.
14. **Records and deserialization?** The canonical constructor runs, so validation applies.
15. **JEP 290 filter to reject everything except your DTO package?** `"com.acme.dto.*;java.base/*;!*"`.
</details>

<details><summary><b>A16–A25</b></summary>

16. **Protobuf identifies fields by…?** Field number (tag). Never reuse a number.
17. **Avro sends field names or tags?** Neither: the reader resolves by schema.
18. **Jackson 3 default for unknown properties?** Ignored (Jackson 2: error).
19. **Jackson 3 default max nesting depth?** 500 (Jackson 2: 1,000).
20. **What does `CLOSE_WAIT` piling up mean?** Your application doesn't close sockets the peer closed.
21. **What causes ephemeral port exhaustion?** A new connection per request (`TIME_WAIT`).
22. **Why does `transferTo` need a loop?** It may transfer fewer bytes than requested.
23. **Can `MappedByteBuffer` be unmapped explicitly?** No (only by GC). An FFM `MemorySegment` from an arena can.
24. **JVM DNS cache TTL default (no security manager)?** 30 s positive, 10 s negative.
25. **What does `System.console()` return when output is piped (JDK 25)?** `null` (verified).
</details>

---

## B. Senior scenarios

<details><summary><b>B1. 🔥 Design the outbound HTTP layer for a service calling 12 partners with different SLAs.</b></summary>

One `HttpClient` (or pooled client) per partner configuration, with connect timeouts, per-request timeouts and an overall deadline per user request. Per-partner bulkheads (semaphores sized to the partner's limits), circuit breakers, retries only for idempotent calls with jittered back-off, and pool idle timeouts shorter than the partner's load-balancer idle timeout. Metrics per host (latency histograms, timeouts, pool waits), TLS session reuse, and DNS TTL ≤ 30 s. Run the calls on virtual threads, with structured concurrency for fan-out (Pillar 6 adds Resilience4j specifics).
</details>

<details><summary><b>B2. 🔥 How would you migrate a legacy system that exchanges Java-serialized objects over JMS?</b></summary>

Immediately: add a JEP 290 allow-list filter (JVM-wide plus per stream), remove gadget libraries, and authenticate the broker. Then introduce a schema format (JSON with explicit DTOs, or Protobuf/Avro with a registry), have producers dual-write both formats behind a version header, migrate consumers to read the new format, stop writing Java serialization, and finally remove `ObjectInputStream` usage and verify no endpoints remain (search for `0xACED`/`rO0AB` in traffic).
</details>

<details><summary><b>B3. ⚡ A file-processing batch job reads 50 GB CSVs and runs out of memory. Approach?</b></summary>

Stream instead of loading: `Files.newBufferedReader` (or `lines()` in try-with-resources) with incremental parsing; bounded batch sizes for DB writes; avoid `readAllLines`/`readString`. For random access to huge files, use FFM-mapped segments (no 2 GB limit) or positional `FileChannel` reads. Parallelize by splitting byte ranges on line boundaries, and watch page-cache effects plus `-Xmx` vs container memory.
</details>

<details><summary><b>B4. ⚡ When is Netty the right tool over Spring MVC on virtual threads?</b></summary>

Custom binary protocols, proxies and gateways (byte-level control, zero-copy forwarding, pooled buffers), very high connection counts with mostly idle long-lived connections (WebSocket push), and fine-grained backpressure (writability). For typical REST/JSON business services, MVC + VTs is simpler, with comparable scalability.
</details>

---

## C. Certification-style code questions (verified on JDK 25)

### C1 — Path normalization and resolution

<!-- run: -->
```java
import java.nio.file.Path;

public class IO01 {
    static String u(Object p) { return String.valueOf(p).replace('\\', '/'); }
    public static void main(String[] args) {
        Path base = Path.of("/data/app");
        System.out.println(u(base.resolve("../logs/./a.log").normalize()) + " | "
            + u(Path.of("x/y/z").subpath(0, 2)) + " | " + Path.of("x/y/z").getNameCount() + " | "
            + u(Path.of("a/b").relativize(Path.of("a/b/c/d"))) + " | " + u(Path.of("a/b/c").getParent().getFileName()));
    }
}
```

<details><summary>Answer</summary>

`/data/logs/a.log | x/y | 3 | c/d | b`. `resolve` appends, then `normalize` removes `app/..` and `.`. `subpath(0, 2)` is end-exclusive. The parent of `a/b/c` is `a/b`, whose file name is `b`.
</details>

### C2 — `Files` read/write facts

<!-- run: -->
```java
import java.nio.file.*;
import java.util.stream.Stream;

public class IO02 {
    public static void main(String[] args) throws Exception {
        Path p = Files.createTempFile("q", ".txt");
        try {
            Files.writeString(p, "a\nb\n\nc");
            long lines;
            try (Stream<String> s = Files.lines(p)) { lines = s.count(); }
            System.out.println(Files.readAllLines(p).size() + " " + lines + " " + Files.size(p) + " " + Files.readString(p).lines().filter(String::isBlank).count());
            Files.writeString(p, "z", StandardOpenOption.APPEND);
            System.out.println(Files.readString(p).endsWith("cz") + " " + Files.deleteIfExists(p) + " " + Files.deleteIfExists(p));
        } finally { Files.deleteIfExists(p); }
    }
}
```

<details><summary>Answer</summary>

`4 4 6 1` then `true true false`. The content `a\nb\n\nc` has 4 lines (one empty) and 6 bytes (`a`, `\n`, `b`, `\n`, `\n`, `c`), with no trailing newline after `c`. `APPEND` adds to the end. `deleteIfExists` returns `true` the first time and `false` the second.
</details>

### C3 — Buffered writer without close

<!-- run: -->
```java
import java.io.BufferedWriter;
import java.nio.file.*;

public class IO03 {
    public static void main(String[] args) throws Exception {
        Path p = Files.createTempFile("w", ".txt");
        try {
            BufferedWriter w = Files.newBufferedWriter(p);
            w.write("hello");
            System.out.print(Files.size(p) + " ");      // nothing flushed yet
            w.flush();
            System.out.print(Files.size(p) + " ");
            w.write("!");
            w.close();
            System.out.println(Files.size(p));
        } finally { Files.deleteIfExists(p); }
    }
}
```

<details><summary>Answer</summary>

`0 5 6`. Buffered data reaches the file only on `flush()` or `close()`. Forgetting to close (or flush) a writer loses the tail of the output, which is why try-with-resources matters.
</details>

### C4 — `read` return values

<!-- run: -->
```java
import java.io.*;
import java.nio.charset.StandardCharsets;

public class IO04 {
    public static void main(String[] args) throws Exception {
        InputStream in = new ByteArrayInputStream("abc".getBytes(StandardCharsets.US_ASCII));
        byte[] buf = new byte[2];
        System.out.print(in.read(buf) + " " + in.read(buf) + " " + in.read(buf) + " " + in.read() + " | ");
        BufferedReader r = new BufferedReader(new StringReader("x\ny"));
        System.out.println(r.readLine() + " " + r.readLine() + " " + r.readLine());
    }
}
```

<details><summary>Answer</summary>

`2 1 -1 -1 | x y null`. `read(byte[])` returns the number of bytes read (possibly fewer than the array length) or −1 at end of stream. `readLine()` strips line terminators and returns `null` at end.
</details>

### C5 — Serialization: what survives?

<!-- run: -->
```java
import java.io.*;

public class IO05 {
    static class Parent { int p = 1; Parent() { p = 2; } }                     // not Serializable
    static class Child extends Parent implements Serializable {
        int c = 10; transient int t = 20; static int s = 30;
        Child() { c = 11; t = 21; }
    }
    public static void main(String[] args) throws Exception {
        Child ch = new Child();
        ch.p = 5; ch.c = 15; ch.t = 25;
        var bytes = new ByteArrayOutputStream();
        try (var out = new ObjectOutputStream(bytes)) { out.writeObject(ch); }
        Child.s = 99;
        try (var in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()))) {
            Child r = (Child) in.readObject();
            System.out.println(r.p + " " + r.c + " " + r.t + " " + Child.s);
        }
    }
}
```

<details><summary>Answer</summary>

`2 15 0 99`. `p` comes from re-running `Parent()` (the non-serializable superclass's no-arg constructor), so the serialized 5 is lost. `c` is restored from the stream (15), and `Child()` doesn't run. The transient `t` gets the default 0 (not 20 or 21, since no constructor or initializer runs for `Child`). The static `s` is whatever the class currently holds (99).
</details>

### C6 — *Which exception?* Non-serializable field

<!-- run: -->
```java
import java.io.*;

public class IO06 {
    static class Engine { }                                                   // not Serializable
    static class Car implements Serializable { Engine engine = new Engine(); }
    public static void main(String[] args) {
        try (var out = new ObjectOutputStream(OutputStream.nullOutputStream())) { out.writeObject(new Car()); }
        catch (IOException e) { System.out.println(e.getClass().getSimpleName() + ": " + e.getMessage()); }
    }
}
```

<details><summary>Answer</summary>

`NotSerializableException: IO06$Engine`. Every non-transient field's object must also be serializable. Mark it `transient`, make it `Serializable`, or customize with `writeObject`/`writeReplace`.
</details>

### C7 — `Files.walk` depth and `DirectoryStream` globs

<!-- run: -->
```java
import java.nio.file.*;
import java.util.*;
import java.util.stream.Stream;

public class IO07 {
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("walk");
        try {
            Files.createDirectories(root.resolve("a/b"));
            for (String f : List.of("x.log", "y.txt", "a/z.log", "a/b/w.log")) Files.writeString(root.resolve(f), f);
            try (Stream<Path> s = Files.walk(root, 1)) { System.out.print(s.count() + " "); }
            try (Stream<Path> s = Files.walk(root)) { System.out.print(s.count() + " "); }
            List<String> logs = new ArrayList<>();
            try (DirectoryStream<Path> ds = Files.newDirectoryStream(root, "*.log")) { ds.forEach(p -> logs.add(p.getFileName().toString())); }
            System.out.println(logs);
        } finally {
            try (Stream<Path> s = Files.walk(root)) { for (Path p : s.sorted(Comparator.reverseOrder()).toList()) Files.delete(p); }
        }
    }
}
```

<details><summary>Answer</summary>

`4 7 [x.log]`. `walk(root, 1)` includes the root itself plus its direct children (`a`, `x.log`, `y.txt`): 4 entries. A full walk adds `a/b`, `a/z.log` and `a/b/w.log`: 7. `newDirectoryStream` is not recursive, so the glob matches only `x.log` in the root.
</details>

### C8 — NIO buffer arithmetic

<!-- run: -->
```java
import java.nio.CharBuffer;

public class IO08 {
    public static void main(String[] args) {
        CharBuffer b = CharBuffer.allocate(10);
        b.put("hello");
        b.flip();
        b.get(); b.get();
        b.mark();
        b.get();
        b.reset();
        System.out.print(b.position() + " " + b.limit() + " " + b.remaining() + " ");
        b.compact();
        System.out.println(b.position() + " " + b.limit());
    }
}
```

<details><summary>Answer</summary>

`2 5 3 3 10`. After `flip`: position 0, limit 5. Two gets give position 2. `mark` at 2, a get moves to 3, and `reset` returns to 2, so 3 remain. `compact` copies the 3 unread chars to the front: position 3, limit = capacity 10.
</details>

### C9 — Console in non-interactive environments

<!-- run: -->
```java
public class IO09 {
    public static void main(String[] args) {
        java.io.Console c = System.console();
        System.out.println(c == null ? "no console: fall back to System.in/out" : "console available");
    }
}
```

<details><summary>Answer</summary>

When run with output piped (CI, IDE runners, containers, or this guide's harness), JDK 25 printed `no console: fall back to System.in/out`. `System.console()` can be `null`, so always null-check it. (`Console.readPassword` returns a `char[]` so secrets can be wiped.)
</details>

---

## D. Study map

| 1Z0-831 objective | Files | Practise |
|---|---|---|
| Console and file I/O streams | [4.1 §2](01-IO-Models-Blocking-NIO-AIO.md#2-classic-javaio-and-what-the-exam-asks-) | C3, C4, C9 |
| Serialization and deserialization | [4.3 §1–2](03-Serialization-Security-Protobuf-Avro-Jackson.md) | C5, C6 |
| Path objects and the `java.nio.file` API | [4.1 §2.2–2.3](01-IO-Models-Blocking-NIO-AIO.md#22-javaniofile-nio2-path-semantics-) | C1, C2, C7 |
| (Beyond the exam) NIO buffers and channels | [4.1 §3–4](01-IO-Models-Blocking-NIO-AIO.md#3-nio-buffers-the-state-machine-) | C8 |
