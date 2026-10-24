# 4.1 · I/O Models — Blocking I/O, NIO (Buffers, Channels, Selectors), AIO, and Virtual Threads

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("Console and file I/O streams", "Path objects and the java.nio.file API")
> **Sources:** `java.io`, `java.nio`, `java.nio.channels`, `java.nio.file` Javadoc (JDK 25); JEP 353/373 (reimplemented legacy sockets), JEP 380 (Unix-domain sockets), JEP 400 (UTF-8 by default, JDK 18); Linux `epoll(7)`, BSD `kqueue(2)`, Windows IOCP and AFD/wepoll; Stevens, *UNIX Network Programming*, vol. 1, ch. 6 (I/O models).
> All demos ran on JDK 25 on Windows. Paths are printed with `/` separators (a helper normalizes `\`) so outputs read the same on every OS.

---

## 1. The operating-system view 🔥

```
 user space   ┌───────────────────────────────┐
              │ your thread: read(fd, buf, n) │
              └──────────────┬────────────────┘
                     syscall │ (mode switch; ~100 ns–1 µs)
 kernel       ┌──────────────▼────────────────┐
              │ socket receive buffer / file   │──► data ready?  ── no ──► blocking fd: sleep the THREAD
              │ page cache                     │                          non-blocking fd: return EAGAIN
              └────────────────────────────────┘
```

| Model | Who waits | How readiness/completion is learned | Java API |
|---|---|---|---|
| **Blocking** | The calling thread sleeps in the kernel | — | `java.io` streams, `Socket`, blocking channels |
| **Non-blocking + readiness multiplexing** (reactor) | One thread waits for **many** fds | `select`/`poll` (O(n) per call), **`epoll`** (Linux, O(ready)), **`kqueue`** (BSD/macOS), **wepoll** (Windows, AFD-based epoll emulation) | NIO `Selector` + non-blocking channels |
| **Completion-based** (proactor) | The kernel performs the I/O, then notifies | **IOCP** (Windows), **io_uring** (Linux 5.1+) | AIO (`AsynchronousSocketChannel`); on Linux the JDK *emulates* it with epoll + a thread pool. Netty 4.2 has an io_uring transport |
| **Virtual threads + blocking API** | The virtual thread parks; a **poller** (epoll/kqueue/wepoll) watches the fd | Readiness via the JDK's internal poller | Plain `Socket`/`InputStream` code on a VT |

What this JDK picks (real output, JDK 25 on Windows):

```
selector=sun.nio.ch.WEPollSelectorImpl
asyncProvider=sun.nio.ch.WindowsAsynchronousChannelProvider
```

On Linux you get `EPollSelectorImpl`, and on macOS `KQueueSelectorImpl`.

**epoll in two sentences:** `epoll_ctl` registers interest per fd **once** (in-kernel red-black tree), and `epoll_wait` returns **only ready** fds from a ready list, so the cost scales with activity rather than with connection count. Java's selector uses **level-triggered** mode: a ready fd keeps being reported until you drain it. Netty's native epoll transport can use **edge-triggered** mode (report on change only, so you must drain fully).

---

## 2. Classic `java.io` (and what the exam asks) 🎓

### 2.1 The decorator hierarchy

```
Byte streams    InputStream ← FileInputStream, ByteArrayInputStream, SocketInputStream…
                  └ FilterInputStream ← BufferedInputStream, DataInputStream, PushbackInputStream
                ObjectInputStream (serialization, see 4.3)
Char streams    Reader ← InputStreamReader(InputStream, Charset) ← FileReader
                  └ BufferedReader (readLine, lines)
Writers         Writer ← OutputStreamWriter, FileWriter, StringWriter, BufferedWriter, PrintWriter
Print           PrintStream (System.out/err): never throws IOException; use checkError()
```

* **Buffering:** the `Buffered*` classes default to 8,192 bytes/chars. An unbuffered `FileInputStream.read()` is a syscall **per byte**, often a 1000× slowdown.
* **Charsets:** bytes become chars only via a `Charset`. Since **JDK 18 (JEP 400) the default charset is UTF-8 on all platforms**. The OS charset is still visible as `native.encoding`. Real values on this Windows machine: `defaultCharset=UTF-8 … native.encoding=Cp1252 stdout.encoding=Cp1252`. Always pass `StandardCharsets.UTF_8` explicitly in code that crosses process boundaries.
* `InputStream.transferTo(out)` (JDK 9), `readAllBytes()`, `readNBytes(n)`, `skipNBytes(n)` (JDK 12), `InputStream.nullInputStream()`, `Reader.of(CharSequence)` (JDK 24).
* `PrintStream`/`PrintWriter` **swallow `IOException`s**; check `checkError()`. `System.out.println` is synchronized, so heavy console logging from many threads serializes them.
* `Console` (`System.console()`) may be `null` when there's no terminal (IDEs, pipes, containers). `readPassword()` returns a `char[]` so you can wipe it.

### 2.2 `java.nio.file` (NIO.2): `Path` semantics 🎓

<!-- run: -->
```java
import java.nio.file.Path;

public class PathOps {
    static String u(Object p) { return String.valueOf(p).replace('\\', '/'); }   // print with '/' on every OS

    public static void main(String[] args) {
        Path p = Path.of("a", "b", "..", "c", ".", "d.txt");
        System.out.println(u(p) + " | normalize=" + u(p.normalize()) + " | getName(0)=" + p.getName(0) + " | count=" + p.getNameCount());
        System.out.println("resolve:      " + u(Path.of("x/y").resolve("z")) + " | resolveSibling: " + u(Path.of("x/y").resolveSibling("w")));
        System.out.println("resolve(abs): returns the absolute argument unchanged → " + (Path.of("x/y").resolve(Path.of("/abs").toAbsolutePath()).isAbsolute()));
        System.out.println("relativize:   " + u(Path.of("a/b").relativize(Path.of("a/c/d"))) + " | subpath(1,3): " + u(Path.of("a/b/c").subpath(1, 3)));
        System.out.println("startsWith(\"a/b\")=" + Path.of("a/b/c").startsWith("a/b") + " startsWith(\"a/b/c/\")=" + Path.of("a/b/c").startsWith("a/b/c/")
            + " startsWith(\"a/bc\")=" + Path.of("a/bc").startsWith("a/b") + " endsWith(\"b/c\")=" + Path.of("a/b/c").endsWith("b/c"));
        System.out.println("getParent(\"a.txt\")=" + Path.of("a.txt").getParent() + " | getFileName=" + Path.of("dir/file.log").getFileName()
            + " | relative isAbsolute=" + Path.of("a").isAbsolute());
    }
}
```

Output (verified):

```
a/b/../c/./d.txt | normalize=a/c/d.txt | getName(0)=a | count=6
resolve:      x/y/z | resolveSibling: x/w
resolve(abs): returns the absolute argument unchanged → true
relativize:   ../c/d | subpath(1,3): b/c
startsWith("a/b")=true startsWith("a/b/c/")=true startsWith("a/bc")=false endsWith("b/c")=true
getParent("a.txt")=null | getFileName=file.log | relative isAbsolute=false
```

Exam-grade rules: `Path` operations are **purely syntactic**. They don't touch the file system, except `toRealPath()` (resolves symlinks, requires existence) and `toAbsolutePath()` (prepends the working directory). `startsWith`/`endsWith` compare **name elements**, not strings: `a/bc` does not start with `a/b`. `normalize()` removes `.` and `name/..` pairs. `relativize` needs both paths to be relative, or both absolute.

### 2.3 `Files`: the operations and their traps 🎓

<!-- run: -->
```java
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.List;
import java.util.stream.Stream;

public class FilesTour {
    static String u(Object p) { return String.valueOf(p).replace('\\', '/'); }

    public static void main(String[] args) throws IOException {
        Path root = Files.createTempDirectory("files-tour");
        try {
            Path logs = Files.createDirectories(root.resolve("app/logs"));          // creates parents; no error if present
            Path f = Files.writeString(logs.resolve("a.log"), "line1\nline2\nline3\n", StandardCharsets.UTF_8);
            System.out.println("size=" + Files.size(f) + " lines=" + Files.readAllLines(f).size() + " exists=" + Files.exists(f));

            Files.copy(f, f);                                                         // same file: a silent no-op
            System.out.println("copy(f, f) → no exception (source and target are the same file)");
            Path b = Files.copy(f, logs.resolve("b.log"));
            try { Files.copy(f, b); }
            catch (FileAlreadyExistsException e) { System.out.println("copy onto another existing file → FileAlreadyExistsException"); }
            Files.move(b, logs.resolve("c.log"), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            System.out.println("mismatch(a,c)=" + Files.mismatch(f, logs.resolve("c.log")) + " (-1 = identical)");

            try (Stream<String> lines = Files.lines(f)) {                            // LAZY: must be closed
                System.out.println("lines with '2': " + lines.filter(l -> l.contains("2")).toList());
            }
            try (Stream<Path> walk = Files.walk(root)) {                              // depth-first, also must be closed
                System.out.println("walk: " + walk.map(p -> u(root.relativize(p))).sorted().toList());
            }
            try (Stream<Path> found = Files.find(root, 5, (p, attrs) -> attrs.isRegularFile() && p.toString().endsWith(".log"))) {
                System.out.println("find *.log: " + found.map(p -> p.getFileName().toString()).sorted().toList());
            }
            BasicFileAttributes attrs = Files.readAttributes(f, BasicFileAttributes.class);
            System.out.println("isRegularFile=" + attrs.isRegularFile() + " isDirectory=" + attrs.isDirectory() + " size=" + attrs.size());

            try { Files.delete(logs); } catch (DirectoryNotEmptyException e) { System.out.println("delete non-empty dir → DirectoryNotEmptyException"); }
            System.out.println("deleteIfExists(missing)=" + Files.deleteIfExists(logs.resolve("nope.log")));
            try { Files.delete(logs.resolve("nope.log")); } catch (NoSuchFileException e) { System.out.println("delete(missing) → NoSuchFileException"); }
        } finally {
            try (Stream<Path> walk = Files.walk(root)) {                              // recursive cleanup: children first
                for (Path p : walk.sorted((x, y) -> y.getNameCount() - x.getNameCount()).toList()) Files.delete(p);
            }
        }
        System.out.println("cleaned up: " + !Files.exists(root));
    }
}
```

Output (verified):

```
size=18 lines=3 exists=true
copy(f, f) → no exception (source and target are the same file)
copy onto another existing file → FileAlreadyExistsException
mismatch(a,c)=-1 (-1 = identical)
lines with '2': [line2]
walk: [, app, app/logs, app/logs/a.log, app/logs/c.log]
find *.log: [a.log, c.log]
isRegularFile=true isDirectory=false size=18
delete non-empty dir → DirectoryNotEmptyException
deleteIfExists(missing)=false
delete(missing) → NoSuchFileException
cleaned up: true
```

| Trap | Detail |
|---|---|
| `Files.lines/list/walk/find` | Return **lazy streams holding open file handles**. Not closing them leaks file descriptors (`Too many open files`) |
| `readAllLines`/`readString` | Load everything into memory. Fine for small files, an OOM for big ones |
| `copy`/`move` | Fail with `FileAlreadyExistsException` if the target exists, unless `REPLACE_EXISTING`. **Copying a file onto itself is a no-op.** `ATOMIC_MOVE` may throw `AtomicMoveNotSupportedException` across file systems. `copy` of a directory copies only the directory entry, not its contents |
| `delete` vs `deleteIfExists` | `NoSuchFileException` vs `false`. Neither deletes non-empty directories |
| `exists` and `notExists` | Can **both** be false (no permission to check) |
| `walk` order | Depth-first, pre-order (parent before children), so delete in reverse |
| `Files.newBufferedReader` | UTF-8 by default; malformed input throws `MalformedInputException` (unlike `InputStreamReader`, which replaces it) |

---

## 3. NIO buffers: the state machine 🔥

```
 0 <= mark <= position <= limit <= capacity

 after allocate(8):     [ . . . . . . . . ]  pos=0 lim=8 cap=8          (write mode)
 after put 3 bytes:     [ a b c . . . . . ]  pos=3 lim=8
 flip():                [ a b c . . . . . ]  pos=0 lim=3                (read mode: limit = old position)
 get 2 bytes:           [ a b c . . . . . ]  pos=2 lim=3
 compact():             [ c . . . . . . . ]  pos=1 lim=8                (unread bytes moved to the front, ready to write)
 clear():               pos=0 lim=8   (data NOT erased — just forgotten)
 rewind():              pos=0, limit unchanged (re-read)
```

<!-- run: -->
```java
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

public class BufferStates {
    static String s(ByteBuffer b) { return "pos=" + b.position() + " lim=" + b.limit() + " cap=" + b.capacity() + " rem=" + b.remaining(); }

    public static void main(String[] args) {
        ByteBuffer b = ByteBuffer.allocate(8);
        b.put("abc".getBytes(StandardCharsets.US_ASCII));     System.out.println("after put   : " + s(b));
        b.flip();                                              System.out.println("after flip  : " + s(b));
        byte first = b.get(), second = b.get();                System.out.println("after 2 gets: " + s(b) + " read=" + (char) first + (char) second);
        b.compact();                                           System.out.println("after compact: " + s(b) + " byte0=" + (char) b.get(0));
        b.clear();                                             System.out.println("after clear : " + s(b));

        ByteBuffer ints = ByteBuffer.allocate(4).putInt(1);
        System.out.println("default order " + ints.order() + " bytes=" + java.util.Arrays.toString(ints.array())
            + " | LE: " + java.util.Arrays.toString(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(1).array()));

        ByteBuffer src = ByteBuffer.wrap("hello".getBytes(StandardCharsets.US_ASCII));
        ByteBuffer slice = src.slice(1, 3);                   // shares content: "ell"
        slice.put(0, (byte) 'E');
        System.out.println("slice shares content: " + new String(src.array(), StandardCharsets.US_ASCII)
            + " | readOnly put → " + tryPut(src.asReadOnlyBuffer()) + " | direct? heap=" + src.isDirect() + " direct=" + ByteBuffer.allocateDirect(4).isDirect());
    }
    static String tryPut(ByteBuffer ro) { try { ro.put((byte) 1); return "ok"; } catch (java.nio.ReadOnlyBufferException e) { return "ReadOnlyBufferException"; } }
}
```

Output (verified):

```
after put   : pos=3 lim=8 cap=8 rem=5
after flip  : pos=0 lim=3 cap=8 rem=3
after 2 gets: pos=2 lim=3 cap=8 rem=1 read=ab
after compact: pos=1 lim=8 cap=8 rem=7 byte0=c
after clear : pos=0 lim=8 cap=8 rem=8
default order BIG_ENDIAN bytes=[0, 0, 0, 1] | LE: [1, 0, 0, 0]
slice shares content: hEllo | readOnly put → ReadOnlyBufferException | direct? heap=false direct=true
```

**The #1 NIO bug:** forgetting `flip()` after filling a buffer, so you then write zero bytes (position == limit), or writing garbage after `clear()` because data isn't erased. The #2 bug: assuming `channel.write(buf)` writes everything. It can write **partially** on non-blocking channels, so loop or keep `OP_WRITE` interest until `!buf.hasRemaining()`.

Heap vs direct buffers ([1.2 §7](../01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md#7-direct-bytebuffers--off-heap-the-old-way-)): a channel can do I/O from a direct buffer without an extra copy. Heap buffers are copied through a temporary direct buffer per I/O call.

---

## 4. Selectors: a single-threaded reactor 🔥

```
          ┌────────────── Selector (epoll/kqueue/wepoll) ──────────────┐
          │  SelectionKey(serverChannel, OP_ACCEPT)                    │
          │  SelectionKey(clientA, OP_READ, attachment=bufferA)        │
          │  SelectionKey(clientB, OP_READ|OP_WRITE, attachment=…)     │
          └────────────────────────────────────────────────────────────┘
 loop:  n = selector.select()            ← blocks until ≥1 channel is ready (or wakeup())
        for key in selector.selectedKeys(): remove it from the set (!), then dispatch:
            isAcceptable → accept, configureBlocking(false), register(OP_READ)
            isReadable   → read into the attachment buffer; -1 = peer closed → key.cancel(); channel.close()
            isWritable   → flush pending bytes; when done, interestOps(OP_READ) (else a busy loop on always-writable sockets)
```

### 4.1 Runnable: NIO echo server and clients, one selector thread

<!-- run: timeout=60 -->
```java
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

public class NioEchoServer {
    public static void main(String[] args) throws Exception {
        Selector selector = Selector.open();
        ServerSocketChannel server = ServerSocketChannel.open();
        server.bind(new InetSocketAddress("127.0.0.1", 0));             // ephemeral port
        server.configureBlocking(false);
        server.register(selector, SelectionKey.OP_ACCEPT);
        int port = ((InetSocketAddress) server.getLocalAddress()).getPort();

        Thread loop = Thread.ofPlatform().name("nio-event-loop").start(() -> {
            try {
                while (!Thread.currentThread().isInterrupted()) {
                    selector.select(200);
                    Iterator<SelectionKey> it = selector.selectedKeys().iterator();
                    while (it.hasNext()) {
                        SelectionKey key = it.next();
                        it.remove();                                        // MUST remove, or the key is reprocessed
                        if (!key.isValid()) continue;
                        if (key.isAcceptable()) {
                            SocketChannel ch = ((ServerSocketChannel) key.channel()).accept();
                            ch.configureBlocking(false);
                            ch.register(selector, SelectionKey.OP_READ, ByteBuffer.allocate(256));
                        } else if (key.isReadable()) {
                            SocketChannel ch = (SocketChannel) key.channel();
                            ByteBuffer buf = (ByteBuffer) key.attachment();
                            int n = ch.read(buf);
                            if (n == -1) { key.cancel(); ch.close(); continue; }    // peer closed
                            buf.flip();
                            ch.write(buf);                                  // may be partial in general…
                            if (buf.hasRemaining()) key.interestOps(SelectionKey.OP_READ | SelectionKey.OP_WRITE);
                            buf.compact();
                        } else if (key.isWritable()) {
                            SocketChannel ch = (SocketChannel) key.channel();
                            ByteBuffer buf = (ByteBuffer) key.attachment();
                            buf.flip(); ch.write(buf); buf.compact();
                            if (buf.position() == 0) key.interestOps(SelectionKey.OP_READ);   // drop OP_WRITE when drained
                        }
                    }
                }
            } catch (IOException e) { throw new RuntimeException(e); }
        });

        // 5 concurrent blocking clients (each on a virtual thread)
        List<String> replies = Collections.synchronizedList(new ArrayList<>());
        try (var clients = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < 5; i++) {
                int id = i;
                clients.submit(() -> {
                    try (SocketChannel c = SocketChannel.open(new InetSocketAddress("127.0.0.1", port))) {
                        String msg = "hello-" + id;
                        c.write(ByteBuffer.wrap(msg.getBytes(StandardCharsets.UTF_8)));
                        ByteBuffer in = ByteBuffer.allocate(64);
                        while (in.position() < msg.length()) c.read(in);
                        replies.add(new String(in.array(), 0, in.position(), StandardCharsets.UTF_8));
                    }
                    return null;
                });
            }
        }
        loop.interrupt(); loop.join(); server.close(); selector.close();
        Collections.sort(replies);
        System.out.println("one selector thread served " + replies.size() + " clients: " + replies);
    }
}
```

Output (verified):

```
one selector thread served 5 clients: [hello-0, hello-1, hello-2, hello-3, hello-4]
```

**Reactor rules (the same ones Netty enforces):**

1. **Never block in the event loop.** One slow handler stalls every connection on that selector.
2. Always **remove** processed keys from `selectedKeys()`.
3. Register `OP_WRITE` only while you have pending output. Sockets are almost always writable, so permanent `OP_WRITE` interest spins the loop at 100% CPU.
4. Handle partial reads (framing: length prefixes or delimiters) and partial writes.
5. `selector.wakeup()` lets other threads interrupt `select()`, for example to register channels or submit tasks (Netty's task queue + wakeup).
6. Historical: the JDK 6/7 **epoll spin bug** (`select()` returning 0 repeatedly at 100% CPU) is why Netty rebuilds its selector when it detects empty spins.

---

## 5. Virtual threads + blocking sockets = NIO scalability, blocking code 🔥

Since JDK 13/15 (JEP 353/373) `Socket`/`ServerSocket`/`DatagramSocket` are implemented on NIO internals. On a **virtual thread** a blocking `read` parks the VT and registers the socket with the JDK's internal **poller**, and the carrier keeps working.

<!-- run: timeout=120 -->
```java
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class VirtualThreadEchoServer {
    public static void main(String[] args) throws Exception {
        ServerSocket server = new ServerSocket(0, 1024, InetAddress.getLoopbackAddress());
        int port = server.getLocalPort();
        Thread acceptor = Thread.ofPlatform().start(() -> {
            try (var handlers = Executors.newVirtualThreadPerTaskExecutor()) {
                while (!server.isClosed()) {
                    Socket s = server.accept();                               // classic blocking accept
                    handlers.submit(() -> {                                   // one VIRTUAL thread per connection
                        try (s; var in = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
                             var out = new PrintWriter(new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8), true)) {
                            String line;
                            while ((line = in.readLine()) != null) { Thread.sleep(50); out.println("echo:" + line); }   // simulated slow backend
                        }
                        return null;
                    });
                }
            } catch (IOException closed) { }
        });

        int clients = 1_000;
        AtomicInteger ok = new AtomicInteger(), failed = new AtomicInteger();
        long t0 = System.nanoTime();
        try (var cs = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < clients; i++) {
                int id = i;
                cs.submit(() -> {
                    try (Socket c = connectWithRetry(port);                   // 1,000 simultaneous SYNs can overflow the accept backlog
                         var in = new BufferedReader(new InputStreamReader(c.getInputStream(), StandardCharsets.UTF_8));
                         var out = new PrintWriter(new OutputStreamWriter(c.getOutputStream(), StandardCharsets.UTF_8), true)) {
                        c.setSoTimeout(5_000);
                        out.println("msg-" + id);
                        if (("echo:msg-" + id).equals(in.readLine())) ok.incrementAndGet(); else failed.incrementAndGet();
                    } catch (IOException | InterruptedException e) {
                        failed.incrementAndGet();                             // never let submit() swallow failures silently
                    }
                });
            }
        }
        long ms = (System.nanoTime() - t0) / 1_000_000;
        server.close(); acceptor.join();
        System.out.println(ok.get() + "/" + clients + " concurrent connections echoed correctly (" + failed.get() + " failed); each handler blocked 50 ms; total "
            + (ms < 5_000 ? "well under the 50 s a single thread would need" : ms + " ms"));
    }

    static Socket connectWithRetry(int port) throws IOException, InterruptedException {
        for (int attempt = 1; ; attempt++) {
            try { return new Socket(InetAddress.getLoopbackAddress(), port); }
            catch (ConnectException refused) {                                // backlog full: back off and retry, like real clients
                if (attempt == 10) throw refused;
                Thread.sleep(20L * attempt);
            }
        }
    }
}
```

Output (verified):

```
1000/1000 concurrent connections echoed correctly (0 failed); each handler blocked 50 ms; total well under the 50 s a single thread would need
```

That is 1,000 concurrent connections, each with a blocked handler, served by plain blocking code. Measured total time on this laptop was about 1 s, dominated by connection setup on Windows loopback.

> **A lesson the verification itself taught:** the first version of this demo had no retry and no failure counting. One of several runs reported `832/1000`: 1,000 simultaneous connects overflowed the OS **accept backlog** (the OS may cap the requested 1,024), so some connects were refused, and because the client tasks ran through `submit()`, their `ConnectException`s were **silently swallowed** ([3.4 §3.1](../03-Concurrency-Loom/04-Executors-ForkJoin-CompletableFuture.md#31-runnable-where-do-exceptions-go)). In production that pattern hides connection storms. Count failures explicitly, retry refused connects with back-off, and size the backlog (and the OS's `somaxconn`) for burst arrivals.

---

## 6. Asynchronous channels (AIO / NIO.2) 🧊

<!-- run: -->
```java
import java.nio.ByteBuffer;
import java.nio.channels.AsynchronousFileChannel;
import java.nio.channels.CompletionHandler;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.concurrent.*;

public class AioFileRead {
    public static void main(String[] args) throws Exception {
        Path f = Files.writeString(Files.createTempFile("aio", ".txt"), "asynchronous file channel demo");
        try (AsynchronousFileChannel ch = AsynchronousFileChannel.open(f, StandardOpenOption.READ)) {
            // Future style
            ByteBuffer buf1 = ByteBuffer.allocate(64);
            int n = ch.read(buf1, 0).get(1, TimeUnit.SECONDS);
            System.out.println("future: " + n + " bytes → " + new String(buf1.array(), 0, n, StandardCharsets.UTF_8));

            // CompletionHandler style (callback on a JDK-managed pool thread)
            CompletableFuture<String> done = new CompletableFuture<>();
            ByteBuffer buf2 = ByteBuffer.allocate(4);
            ch.read(buf2, 0, "attachment-ctx", new CompletionHandler<Integer, String>() {
                public void completed(Integer bytes, String ctx) { done.complete(ctx + " read " + bytes + " bytes: " + new String(buf2.array(), StandardCharsets.UTF_8)); }
                public void failed(Throwable ex, String ctx) { done.completeExceptionally(ex); }
            });
            System.out.println("handler: " + done.get(1, TimeUnit.SECONDS));
        } finally { Files.delete(f); }
    }
}
```

Output (verified):

```
future: 30 bytes → asynchronous file channel demo
handler: attachment-ctx read 4 bytes: asyn
```

* `AsynchronousSocketChannel`, `AsynchronousServerSocketChannel` and `AsynchronousFileChannel` offer `Future`- or `CompletionHandler`-based APIs. Handlers run on an `AsynchronousChannelGroup`'s thread pool.
* On Windows they map to **IOCP** (true completion I/O). On Linux the JDK **emulates** them with epoll plus a thread pool (for files, a thread pool doing blocking I/O). So "async" doesn't mean "no threads blocked".
* Rarely used in production: Netty removed its AIO transport (no benefit over its epoll and NIO transports), and on JDK 21+ virtual threads give a simpler model. `AsynchronousFileChannel` remains useful for positional concurrent file reads without blocking a request thread.

---

## 7. Choosing an I/O model (2026)

| Model | Concurrency per thread | Code style | CPU efficiency | Best for |
|---|---|---|---|---|
| Blocking I/O, platform thread per connection | 1 | Simple | Context-switch heavy beyond ~thousands of threads | Low-concurrency tools, admin endpoints |
| **Blocking I/O, virtual thread per connection** | 1 VT, many per carrier | Simple | Very good | **Default for request/response servers and clients on JDK 21+** |
| NIO selector (hand-written reactor) | Thousands | Complex (state machines, framing) | Excellent | Learning; very specialized protocol servers |
| **Netty** (NIO/epoll/kqueue/io_uring event loops) | Thousands | Pipeline of handlers | Excellent; zero-copy, pooled buffers | Proxies, gateways, custom protocols, the foundation of gRPC-Java, Reactor Netty, Vert.x, Kafka-adjacent tools ([4.2](02-Zero-Copy-MMAP-Netty.md)) |
| AIO (IOCP/emulated) | Many | Callbacks | Good on Windows | Rare |

---

## 8. Production failure modes & diagnostics (I/O models)

| Failure | Signature | Fix |
|---|---|---|
| `Too many open files` | `IOException: Too many open files`; `lsof -p <pid> \| wc -l` near `ulimit -n` | Close streams (`Files.lines/walk/list`), sockets and responses; raise `nofile` limits for servers |
| Event-loop stall | All connections on one loop slow; loop thread in blocking frames (JDBC, `Thread.sleep`, DNS) | Offload blocking work; Netty's `BlockHound` in tests |
| Selector busy loop | 100% CPU in `select()` with no traffic | Clear `OP_WRITE` when drained; remove selected keys; (JDK 6/7 bug: rebuild selector) |
| Partial write data loss | Truncated responses under load | Loop until `!hasRemaining()` / `OP_WRITE` handling |
| Mojibake | `Ã©` instead of `é` | Explicit charsets end to end; `native.encoding` ≠ default on Windows |
| Unbuffered streams | High CPU in `read`/`write` syscalls; strace shows 1-byte reads | `Buffered*`, `transferTo`, larger buffers |
| `System.out` contention | Threads BLOCKED on `PrintStream` | A real logger with an async appender |
| Blocking file I/O on VTs at scale | Carrier count grows (compensation) | A dedicated pool for heavy file I/O |

**Diagnostic commands:** `lsof -p <pid>`, `ls /proc/<pid>/fd | wc -l`, `ss -tanp | grep <pid>` (socket states), `strace -f -e trace=read,write,epoll_wait -p <pid>` (Linux), JFR events `jdk.FileRead/FileWrite/SocketRead/SocketWrite` (JDK 25 `default.jfc`: threshold 1 ms, throttled to 100 events/s, with stack traces).

---

## 9. Interview & certification Q&A

<details><summary><b>Q1. 🔥 Explain the difference between blocking, non-blocking + multiplexing, and asynchronous (completion) I/O.</b></summary>

Blocking: the calling thread sleeps in the kernel until data arrives. Non-blocking + multiplexing (reactor): sockets return immediately (`EAGAIN`), and one thread asks the kernel (epoll/kqueue) which of many sockets are ready, then performs non-blocking reads and writes on those. Completion-based (proactor): the application submits operations and the kernel completes the I/O into its buffers and signals completion (IOCP, io_uring). Java: `java.io`, NIO `Selector`, and AIO respectively. On Linux, AIO is emulated.
</details>

<details><summary><b>Q2. 🎓 What do `flip()`, `clear()`, `compact()` and `rewind()` do to a buffer?</b></summary>

`flip`: limit = position, position = 0 (switch from writing to reading). `clear`: position = 0, limit = capacity (data isn't erased). `compact`: copy the unread bytes to the start, position = number of unread bytes, limit = capacity (resume writing without losing unread data). `rewind`: position = 0, keep the limit (re-read).
</details>

<details><summary><b>Q3. 🎓 What does `Path.of("a/b").relativize(Path.of("a/c/d"))` return? And `Path.of("x").resolve("/abs")`?</b></summary>

`../c/d`. Resolving an absolute path returns the absolute argument (`/abs`, or `C:\abs` on Windows when resolved from an absolute input). Path operations are syntactic; they don't access the file system.
</details>

<details><summary><b>Q4. 🔥 Why must `Files.lines()` be used in try-with-resources?</b></summary>

It returns a lazily populated `Stream` backed by an open file handle that is closed only when the stream is closed. Without closing, file descriptors leak until GC (and with no finalization, possibly never), eventually causing `Too many open files`. The same applies to `Files.list`, `walk` and `find`.
</details>

<details><summary><b>Q5. ⚡ Why does registering a channel permanently for `OP_WRITE` cause 100% CPU?</b></summary>

A connected socket's send buffer usually has space, so it is always "writable" (level-triggered). `select()` returns immediately on every iteration even with nothing to write. Register `OP_WRITE` only when a write was partial, and remove it once the pending data is flushed.
</details>

<details><summary><b>Q6. 🔥 How do virtual threads achieve NIO-like scalability with blocking socket APIs?</b></summary>

The socket implementation (`NioSocketImpl`) uses non-blocking file descriptors internally. When a read or write would block on a virtual thread, the VT registers the fd with a JDK poller (epoll/kqueue/wepoll) and parks, freeing its carrier. When the poller reports readiness, the VT is unparked and rescheduled. Your code stays blocking and simple, while carriers multiplex thousands of connections.
</details>

<details><summary><b>Q7. 🎓 What is the default charset in JDK 18+, and where can you still find the platform encoding?</b></summary>

UTF-8 (JEP 400), regardless of OS locale. The OS encoding is reported by `System.getProperty("native.encoding")` (e.g. `Cp1252` on this Windows machine), and console streams use `stdout.encoding`.
</details>

<details><summary><b>Q8. 🎓 `Files.delete` vs `Files.deleteIfExists` on a missing file, and on a non-empty directory?</b></summary>

Missing file: `delete` throws `NoSuchFileException`, and `deleteIfExists` returns `false`. Non-empty directory: both throw `DirectoryNotEmptyException`.
</details>

---

## 10. Further reading

* `java.nio.channels.Selector` and `SelectionKey` Javadoc; `java.nio.file.Files` Javadoc.
* Linux `epoll(7)`; Stevens, *UNIX Network Programming* vol. 1, ch. 6.
* JEP 353, 373 (socket reimplementation), JEP 400 (UTF-8 default), JEP 380 (Unix-domain sockets).
