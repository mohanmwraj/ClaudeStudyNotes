# 1.1 · Class Loading, Linking, Initialization & the Module System (JPMS)

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 on the 1Z0-830/831 exam
> **Specs:** JVMS §5 (Loading, Linking, Initializing), JLS §12.4 (Initialization), JLS §7.7 (Module declarations), `java.lang.ClassLoader` Javadoc, JEP 261 (Module System), JEP 371 (Hidden Classes), JEP 483/514 (AOT cache), JEP 511 (Module import declarations).

---

## 1. Mental model 🔥

A class at run time is **not** identified by its name. It is identified by the pair **⟨binary name, defining class loader⟩**. Every class-loading problem you will debug in production follows from that one fact: `ClassCastException: X cannot be cast to X`, `LinkageError: loader constraint violation`, Metaspace leaks on redeploy, `NoSuchMethodError` after a dependency bump.

```
            .class bytes (jar / jimage / network / generated)
                         │
   ┌──────────── LOADING (JVMS §5.3) ────────────┐   find bytes, parse, create InstanceKlass in Metaspace,
   │  ClassLoader.loadClass → findClass →        │   create java.lang.Class "mirror" on the heap
   │  defineClass (native)                       │
   └─────────────────────────────────────────────┘
                         │
   ┌──────────── LINKING (JVMS §5.4) ────────────┐
   │ 1. Verification  – type-safety proof using  │   StackMapTable-based type checker (class file ≥ 50)
   │                    StackMapTable frames      │
   │ 2. Preparation   – allocate static fields,   │   default values (0/null/false), NOT initializers
   │                    set defaults              │
   │ 3. Resolution    – symbolic refs → direct    │   LAZY in HotSpot: on first execution of the
   │                    refs (constant pool)      │   bytecode that uses the constant-pool entry
   └─────────────────────────────────────────────┘
                         │
   ┌──────────── INITIALIZATION (JVMS §5.5) ─────┐   run <clinit>: static initializers + static field
   │  exactly once, under the class init lock    │   initializers in textual order; superclass first
   └─────────────────────────────────────────────┘
                         │
                  USE  →  UNLOADING (only when the defining loader is unreachable)
```

---

## 2. The built-in loaders (JDK 9+) 🔥🎓

| Loader | Implementation | Loads | Notes |
|---|---|---|---|
| **Bootstrap** | Native (C++), represented as `null` in Java | `java.base`, `java.logging`, … core modules from `lib/modules` (jimage) | `String.class.getClassLoader() == null` |
| **Platform** | `jdk.internal.loader.ClassLoaders$PlatformClassLoader` | Java SE and JDK modules not on bootstrap (e.g. `java.sql`, `java.net.http`) | Replaced the JDK 8 *extension* loader (`jre/lib/ext` is gone) |
| **Application (system)** | `ClassLoaders$AppClassLoader` | `--class-path` and `--module-path` application classes | `ClassLoader.getSystemClassLoader()` |

Real output from `jcmd <pid> VM.classloaders` on JDK 25:

```
+-- <bootstrap>
      |
      +-- "platform", jdk.internal.loader.ClassLoaders$PlatformClassLoader
            |
            +-- "app", jdk.internal.loader.ClassLoaders$AppClassLoader
```

### 2.1 Parent delegation — and how JPMS changed it ⚡

The classic `loadClass` algorithm, which you should still use for custom loaders:

```java
protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
    synchronized (getClassLoadingLock(name)) {           // per-name lock if parallel-capable
        Class<?> c = findLoadedClass(name);              // 1. already loaded by THIS loader (as initiating)?
        if (c == null) {
            try {
                c = (parent != null) ? parent.loadClass(name, false)  // 2. delegate up
                                     : findBootstrapClassOrNull(name);
            } catch (ClassNotFoundException ignored) { }
            if (c == null) c = findClass(name);           // 3. only then look yourself
        }
        if (resolve) resolveClass(c);
        return c;
    }
}
```

**JDK 9+ built-in loaders are module-aware.** When the app loader is asked for `java.sql.Connection`, it does *not* blindly ask its parent first. It looks up the **package → module → loader** map built during boot-layer resolution and delegates **directly** to the loader of the module that owns the package. Unnamed-module (class-path) classes still fall back to parent-first. Consequences:

* **Split packages are illegal** between named modules: one package may belong to exactly one module in a layer. On the class path it "works", which is how JAR hell hides.
* You cannot shadow a JDK package from the class path. A class-path `javax.annotation.*` *does* load, but only because `java.xml.ws.annotation` was removed from the JDK in 11.

### 2.2 Delegation, initiating vs defining loader 🧊

* **Defining loader:** the one that called `defineClass`. `Class.getClassLoader()` returns it.
* **Initiating loader:** any loader whose `loadClass` *returned* the class, possibly via delegation. The JVM records it, so a later `findLoadedClass` on that loader is fast.
* **Loader constraints** (JVMS §5.3.4): when class `A` (loader L1) calls a method on `B` (loader L2) that mentions type `T` in its signature, the JVM records "`T` as seen by L1 must equal `T` as seen by L2". If the constraint is violated you get `java.lang.LinkageError: loader constraint violation`, the classic failure when an app server and a webapp both ship different copies of the same API JAR.

---

## 3. Loading internals (HotSpot) ⚡

| Step | What HotSpot does | Memory |
|---|---|---|
| Parse | `ClassFileParser` validates magic `0xCAFEBABE`, version (JDK 21 = 65, **JDK 25 = 69**), constant pool, fields, methods, attributes | Temporary C-heap |
| Create metadata | `InstanceKlass`, `Method`, `ConstMethod`, `ConstantPool`, vtable/itable | **Metaspace** (non-class space). The `Klass` itself goes in **compressed class space** |
| Create mirror | `java.lang.Class` instance; **static fields live in the mirror** (since JDK 8) | **Java heap** |
| Register | Add to the defining loader's `ClassLoaderData` (CLD) dictionary | Metaspace |
| CDS shortcut | If the class is in the CDS/AOT archive, map the pre-parsed metadata instead of parsing | Shared, read-only mapped region |

`-Xlog:class+load=info` on JDK 25 (real lines). Note that most JDK classes come from CDS, and the lambda shows up as a **hidden class** defined by its host:

```
[0.026s][info][class,load] java.lang.Object source: shared objects file
[0.055s][info][class,load] Sleeper source: file:/app/
[0.061s][info][class,load] Sleeper$$Lambda/0x0000000013040210 source: Sleeper
```

> In that run, 605 of 611 classes came from the CDS archive. CDS (default archive since JDK 12, JEP 341) is why "hello world" starts in ~40 ms.

### 3.1 `Class.forName` vs `ClassLoader.loadClass` 🔥🎓

| Call | Initializes? | Loader used |
|---|---|---|
| `Class.forName("x.Y")` | **Yes** (runs `<clinit>`) | Caller's defining loader |
| `Class.forName("x.Y", false, loader)` | No | Given loader |
| `loader.loadClass("x.Y")` | No (and not even linked) | Given loader |
| `X.class` literal | No | Caller's loader |
| `MethodHandles.lookup().findClass("x.Y")` | No | Lookup class's loader + access check |
| `MethodHandles.Lookup.ensureInitialized(X.class)` | Yes | — |

This is why old JDBC code did `Class.forName("com.mysql.jdbc.Driver")`: the driver's static initializer registers itself with `DriverManager`. Since JDBC 4 (Java 6), `ServiceLoader` discovers drivers through `META-INF/services/java.sql.Driver`.

---

## 4. Linking 🧊

### 4.1 Verification

* **Type-checking verifier** (class files ≥ 50): the compiler emits `StackMapTable` frames at branch targets, and the verifier checks each basic block linearly. That is O(code) instead of the old O(n²) type-inference verifier.
* Verification is a security boundary *and* a correctness proof the JIT relies on (for example, "this slot always holds a `String`").
* `-Xverify:none` / `-XX:-BytecodeVerificationRemote` are **deprecated** (JDK 13). CDS/AOT archives store already-verified classes, which is part of the startup gain.
* Bytecode generators (ASM, ByteBuddy, the Class-File API) must compute stack maps. The Class-File API does it by default, and broken frames show up as `java.lang.VerifyError: Expecting a stackmap frame at branch target`.

### 4.2 Preparation vs initialization 🎓

Preparation sets statics to **default values**. Initialization runs the initializers in **textual order**. That produces this classic puzzle:

```java
class Puzzle {
    static Puzzle INSTANCE = new Puzzle();   // runs constructor while COUNT is still 0 (default)
    static int COUNT = 10;                   // then COUNT is set to 10
    final int seen;
    Puzzle() { seen = COUNT; }               // seen == 0
}
```

### 4.3 Resolution is lazy

HotSpot resolves constant-pool entries on **first execution** of the instruction that needs them (`invokevirtual #12` → resolve the method ref → cache the result in the CP cache). That is why a missing dependency method throws `NoSuchMethodError` **at the call site, the first time that line runs**, possibly days after deployment, and not at startup.

---

## 5. Initialization 🔥🎓

### 5.1 Triggers (JLS §12.4.1)

A class or interface `T` is initialized immediately before the first:

1. instance creation (`new T()`),
2. `static` method invocation declared in `T`,
3. assignment to a static field declared in `T`,
4. **use** of a static field declared in `T` **that is not a constant variable** (a `static final` primitive/String initialized with a compile-time constant is **inlined by javac** and never triggers initialization),
5. reflective call (`Class.forName(name)`, `Method.invoke` on a static method, …),
6. initialization of a subclass (superclass first; superinterfaces only if they declare `default` methods),
7. being the main class at startup.

**Not** triggers: `T[] arr = new T[10]`, `T.class`, accessing a *subclass's* inherited static field through `Sub.FIELD` (that initializes only the declaring class), compile-time constants.

<!-- run: show -->
```java
import java.util.ArrayList;
import java.util.List;

public class InitTriggers {
    static final List<String> log = new ArrayList<>();

    static class Parent {
        static { log.add("Parent.<clinit>"); }
        static int parentCounter = 1;                    // not a constant variable
    }
    static class Child extends Parent {
        static { log.add("Child.<clinit>"); }
        static final int CONSTANT = 42;                  // compile-time constant: inlined by javac
        static final Integer BOXED = 7;                  // NOT a constant variable (boxed)
    }

    public static void main(String[] args) throws Exception {
        int c = Child.CONSTANT;           // no init: value 42 was copied into this class's bytecode
        log.add("read Child.CONSTANT=" + c);
        Child[] arr = new Child[3];       // no init: array class creation only
        log.add("created Child[" + arr.length + "]");
        int p = Child.parentCounter;      // initializes ONLY Parent (field declared there)
        log.add("read Child.parentCounter=" + p);
        Class.forName("InitTriggers$Child", false, InitTriggers.class.getClassLoader()); // no init
        log.add("forName(init=false) done");
        Integer b = Child.BOXED;          // initializes Child
        log.add("read Child.BOXED=" + b);
        log.forEach(System.out::println);
    }
}
```

Output (verified on JDK 25):

```
read Child.CONSTANT=42
created Child[3]
Parent.<clinit>
read Child.parentCounter=1
forName(init=false) done
Child.<clinit>
read Child.BOXED=7
```

> **Production consequence of constant inlining:** if library `v2` changes `public static final int MAX = 10` to `20`, client code compiled against `v1` **keeps using 10** until it is recompiled. Expose tunables via static methods or non-constant fields, not `static final` primitives or Strings.

### 5.2 The initialization lock and the procedure (JVMS §5.5) 🧊

Each class has an **initialization lock (LC)** and a state: *verified-not-initialized → being-initialized (by thread T) → fully-initialized | erroneous*.

1. Acquire LC. If another thread is initializing, **wait** (this wait is uninterruptible from Java's point of view).
2. If the current thread is already initializing (recursive request), return immediately and **see partially initialized state**.
3. If erroneous, throw `NoClassDefFoundError`.
4. Mark "being initialized by me", release LC, initialize the superclass, run `<clinit>`.
5. On success: mark initialized and `notifyAll`. On exception: mark erroneous, wrap the exception in `ExceptionInInitializerError` (unless it is already an `Error`), and `notifyAll`.

This gives you **thread-safe lazy initialization for free**, which is the basis of the holder idiom:

```java
public final class Config {
    private Config() {}
    private static final class Holder {                  // not initialized until first getInstance()
        static final Config INSTANCE = loadExpensively();
    }
    public static Config getInstance() { return Holder.INSTANCE; }  // no volatile, no locks after init
    private static Config loadExpensively() { return new Config(); }
}
```

After initialization, JIT-compiled code reads `Holder.INSTANCE` as a plain load with no synchronization: the class-init barrier is removed once the class is fully initialized. Since JDK 25, **`StableValue`/lazy constants** (JEP 502 → 526 → 531, still preview in 27) aim to give the same constant-folding benefit without a holder class per lazy field.

### 5.3 Failure: `ExceptionInInitializerError` → `NoClassDefFoundError` 🔥

<!-- run: show -->
```java
public class InitFailure {
    static class Fragile {
        static final int VALUE = Integer.parseInt(System.getProperty("fragile.value", "not-a-number"));
    }

    public static void main(String[] args) {
        for (int attempt = 1; attempt <= 2; attempt++) {
            try {
                System.out.println(Fragile.VALUE);
            } catch (Throwable t) {
                System.out.println("attempt " + attempt + ": " + t);
                if (t.getCause() != null) System.out.println("   cause: " + t.getCause());
            }
        }
    }
}
```

Output (verified):

```
attempt 1: java.lang.ExceptionInInitializerError
   cause: java.lang.NumberFormatException: For input string: "not-a-number"
attempt 2: java.lang.NoClassDefFoundError: Could not initialize class InitFailure$Fragile
   cause: java.lang.ExceptionInInitializerError: Exception java.lang.NumberFormatException: For input string: "not-a-number" [in thread "main"]
```

**Diagnostic rule:** `NoClassDefFoundError: Could not initialize class X` means *X's static initializer failed earlier*. Search the logs for the **first** `ExceptionInInitializerError`. On current JDKs (verified on 25; JDK-8048190) the NCDFE carries the original failure as its cause, as shown above. Older JDK 8/11 builds did not, so you had to find the first error in the logs. A process stays broken for that class forever, because there is no retry.

### 5.4 Class-initialization deadlock 🔥

Two classes whose `<clinit>`s depend on each other, triggered from two threads at once:

<!-- run: show timeout=30 -->
```java
public class ClinitDeadlock {
    static class A { static final Object X; static { pause(); X = B.Y; } }
    static class B { static final Object Y; static { pause(); Y = A.X; } }
    static void pause() { try { Thread.sleep(200); } catch (InterruptedException e) { throw new RuntimeException(e); } }

    public static void main(String[] args) throws Exception {
        Thread t1 = Thread.ofPlatform().daemon().name("init-A").start(() -> System.out.println(A.X));
        Thread t2 = Thread.ofPlatform().daemon().name("init-B").start(() -> System.out.println(B.Y));
        t1.join(1500); t2.join(1500);
        System.out.println("t1 alive=" + t1.isAlive() + " state=" + t1.getState());
        System.out.println("t2 alive=" + t2.isAlive() + " state=" + t2.getState());
        System.out.println("findDeadlockedThreads() = "
            + java.util.Arrays.toString(java.lang.management.ManagementFactory.getThreadMXBean().findDeadlockedThreads()));
    }
}
```

Output (verified on JDK 25):

```
t1 alive=true state=RUNNABLE
t2 alive=true state=RUNNABLE
findDeadlockedThreads() = null
```

Two observations make this a nasty production failure:

* Threads waiting on another thread's class initialization show **`RUNNABLE`** in `Thread.getState()` and jstack. Waiting on the init lock is a VM-internal wait, not a Java monitor.
* `ThreadMXBean.findDeadlockedThreads()` **does not detect it** (it returns `null`), and neither does jstack's "Found one Java-level deadlock".

**What to look for in a thread dump:** two or more threads whose top frames are inside `<clinit>` of different classes, each referencing the other class. **Prevention:** no cross-class cycles in static initializers; keep `<clinit>` trivial; never start threads, do I/O, or block on futures inside `<clinit>`. That last one also pins virtual threads; see Pillar 3.

---

## 6. Custom class loaders 🔥

### 6.1 Why they exist

| Use case | Mechanism | Examples |
|---|---|---|
| Isolation of plugin/tenant dependencies | **Child-first** (parent-last) delegation | Tomcat webapp loader, OSGi bundles, Jenkins plugins, Flink user-code loader |
| Hot reload | Throw away the loader, create a new one | Spring Boot DevTools (restart loader), JRebel-style tools |
| Loading from non-file sources | Override `findClass` | DB, network, encrypted JARs |
| Bytecode generation | `defineClass` / `Lookup.defineClass` / `defineHiddenClass` | Proxies, ORMs, mocking libraries |

### 6.2 Runnable: class identity and child-first isolation

This sample generates two versions of `demo.Greeter` with the **Class-File API** (final in JDK 24, JEP 484), so it needs no JAR files. It then shows (a) the same name in two loaders gives two distinct classes, and (b) a child-first loader beats parent delegation.

<!-- run: show -->
```java
import java.lang.classfile.ClassFile;
import java.lang.constant.ClassDesc;
import java.lang.constant.MethodTypeDesc;
import static java.lang.constant.ConstantDescs.*;

public class LoaderIdentity {
    static byte[] greeter(String message) {
        return ClassFile.of().build(ClassDesc.of("demo.Greeter"), cb -> cb
            .withFlags(ClassFile.ACC_PUBLIC)
            .withMethodBody(INIT_NAME, MTD_void, ClassFile.ACC_PUBLIC, code -> code
                .aload(0).invokespecial(CD_Object, INIT_NAME, MTD_void).return_())
            .withMethodBody("toString", MethodTypeDesc.of(CD_String), ClassFile.ACC_PUBLIC, code -> code
                .ldc(message).areturn())
            // static Object castMe(Object o) { return (demo.Greeter) o; }  -> a real `checkcast` bytecode
            .withMethodBody("castMe", MethodTypeDesc.of(CD_Object, CD_Object),
                            ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC, code -> code
                .aload(0).checkcast(ClassDesc.of("demo.Greeter")).areturn()));
    }

    /** Parent-first loader that can define demo.Greeter from bytes. */
    static class BytesLoader extends ClassLoader {
        private final byte[] bytes;
        BytesLoader(String name, ClassLoader parent, byte[] bytes) { super(name, parent); this.bytes = bytes; }
        @Override protected Class<?> findClass(String n) throws ClassNotFoundException {
            if (!n.equals("demo.Greeter")) throw new ClassNotFoundException(n);
            return defineClass(n, bytes, 0, bytes.length);
        }
    }

    /** Child-first: try own classes before delegating (never for java.*). */
    static class ChildFirstLoader extends BytesLoader {
        ChildFirstLoader(String name, ClassLoader parent, byte[] bytes) { super(name, parent, bytes); }
        @Override protected Class<?> loadClass(String n, boolean resolve) throws ClassNotFoundException {
            synchronized (getClassLoadingLock(n)) {
                Class<?> c = findLoadedClass(n);
                if (c == null && !n.startsWith("java.")) {
                    try { c = findClass(n); } catch (ClassNotFoundException ignored) { }
                }
                if (c == null) c = super.loadClass(n, false);   // fall back to parent-first
                if (resolve) resolveClass(c);
                return c;
            }
        }
    }

    public static void main(String[] args) throws Exception {
        var l1 = new BytesLoader("L1", ClassLoader.getSystemClassLoader(), greeter("v1 from L1"));
        var l2 = new BytesLoader("L2", ClassLoader.getSystemClassLoader(), greeter("v1 from L2"));
        Class<?> c1 = l1.loadClass("demo.Greeter"), c2 = l2.loadClass("demo.Greeter");
        System.out.println("same name: " + c1.getName().equals(c2.getName()) + ", same class: " + (c1 == c2));
        Object o1 = c1.getDeclaredConstructor().newInstance();
        try {
            c2.cast(o1);                                         // reflective cast: short message
        } catch (ClassCastException e) {
            System.out.println("Class.cast CCE: " + e.getMessage());
        }
        try {
            c2.getMethod("castMe", Object.class).invoke(null, o1); // bytecode checkcast inside L2's class
        } catch (java.lang.reflect.InvocationTargetException e) {
            System.out.println("checkcast CCE: " + e.getCause().getMessage().replaceAll("@[0-9a-f]+", "@…"));
        }

        // Parent L1 already knows demo.Greeter (v1). A parent-first child would return the parent's class;
        // a child-first child defines its own v2.
        var parentFirst = new BytesLoader("PF", l1, greeter("v2 (never used)"));
        var childFirst  = new ChildFirstLoader("CF", l1, greeter("v2 from child-first"));
        System.out.println("parent-first sees: " + parentFirst.loadClass("demo.Greeter").getDeclaredConstructor().newInstance());
        System.out.println("child-first  sees: " + childFirst.loadClass("demo.Greeter").getDeclaredConstructor().newInstance());
        System.out.println("defining loader of child-first class: "
            + childFirst.loadClass("demo.Greeter").getClassLoader().getName());
    }
}
```

Output (verified):

```
same name: true, same class: false
Class.cast CCE: Cannot cast demo.Greeter to demo.Greeter
checkcast CCE: class demo.Greeter cannot be cast to class demo.Greeter (demo.Greeter is in unnamed module of loader 'L1' @…; demo.Greeter is in unnamed module of loader 'L2' @…)
parent-first sees: v1 from L1
child-first  sees: v2 from child-first
defining loader of child-first class: CF
```

> **A bytecode `checkcast` failure names both loaders; `Class.cast` does not.** So when you see `X cannot be cast to class X (... loader 'A' ...; ... loader 'B' ...)` in production, that usually means a library JAR is present both in the server/shared loader and inside the deployment, or a hot-reload restart loader holds a stale copy (classic in Spring Boot DevTools with libraries that cache classes).

### 6.3 Rules for writing a correct loader ⚡

1. Override **`findClass`**, not `loadClass`, unless you deliberately want child-first. Always delegate `java.*`; `defineClass` refuses `java.*` names with a `SecurityException`.
2. Call **`ClassLoader.registerAsParallelCapable()`** in a static initializer of your loader class. Otherwise `getClassLoadingLock(name)` returns `this`, and **all** loading through your loader serializes on one monitor, which is a startup bottleneck under parallel class loading.
3. Give loaders a **name** (`super(name, parent)`). It appears in exception messages, `jcmd VM.classloaders` and heap dumps.
4. Implement `findResource`/`findResources` if libraries will call `getResource` (Spring scanning, `ServiceLoader`).
5. Close `URLClassLoader` instances (they hold open JAR file handles, and on Windows you cannot delete the JAR until closed).

---

## 7. Class unloading and loader leaks 🔥

A class is unloadable only when **its defining loader is unreachable**. That requires *every* class of that loader, every instance of those classes, and the loader object itself to be unreachable. Classes from the bootstrap, platform and app loaders are **never** unloaded. Unloading happens during GC: a full GC, G1's concurrent mark/remark, or ZGC's major cycle. Metaspace chunks of the dead `ClassLoaderData` are then returned to the free lists, and since JDK 16's elastic Metaspace (JEP 387) they can be uncommitted to the OS.

### 7.1 Runnable: unloading works — until a `ThreadLocal` pins the loader

<!-- run: show jvm="-Xmx64m" -->
```java
import java.lang.classfile.ClassFile;
import java.lang.constant.ClassDesc;
import java.lang.ref.WeakReference;
import static java.lang.constant.ConstantDescs.*;

public class LoaderLeak {
    static final ThreadLocal<Object> CONTEXT = new ThreadLocal<>();   // lives as long as the main thread

    static byte[] pluginClass() {
        return ClassFile.of().build(ClassDesc.of("plugin.Handler"), cb -> cb
            .withFlags(ClassFile.ACC_PUBLIC)
            .withMethodBody(INIT_NAME, MTD_void, ClassFile.ACC_PUBLIC, code -> code
                .aload(0).invokespecial(CD_Object, INIT_NAME, MTD_void).return_()));
    }

    static class PluginLoader extends ClassLoader {
        final byte[] b = pluginClass();
        PluginLoader() { super("plugin", ClassLoader.getSystemClassLoader()); }
        @Override protected Class<?> findClass(String n) { return defineClass(n, b, 0, b.length); }
    }

    static WeakReference<ClassLoader> deployPlugin(boolean leakViaThreadLocal) throws Exception {
        var loader = new PluginLoader();
        Object handler = loader.loadClass("plugin.Handler").getDeclaredConstructor().newInstance();
        if (leakViaThreadLocal) CONTEXT.set(handler);          // e.g. a framework caching per-thread state
        return new WeakReference<>(loader);
    }

    static boolean collected(WeakReference<?> ref) throws InterruptedException {
        for (int i = 0; i < 10 && ref.get() != null; i++) { System.gc(); Thread.sleep(50); }
        return ref.get() == null;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("clean undeploy -> loader collected: " + collected(deployPlugin(false)));
        var leaked = deployPlugin(true);
        System.out.println("ThreadLocal holds instance -> loader collected: " + collected(leaked));
        CONTEXT.remove();                                       // the fix: always remove() in finally
        System.out.println("after ThreadLocal.remove() -> loader collected: " + collected(leaked));
    }
}
```

Output (verified):

```
clean undeploy -> loader collected: true
ThreadLocal holds instance -> loader collected: false
after ThreadLocal.remove() -> loader collected: true
```

The reference chain is: `Thread` → `ThreadLocalMap` → `Entry.value` → `plugin.Handler` instance → its `Class` → `PluginLoader` → **every class it ever defined** (Metaspace) plus all their static fields (heap).

### 7.2 The classic loader-leak catalogue (app servers, plugin systems, Groovy/script engines)

| Root that pins the loader | Typical culprit | Fix |
|---|---|---|
| `ThreadLocal` value on a pooled/long-lived thread | Frameworks, MDC, custom caches | `remove()` in `finally`; prefer `ScopedValue` |
| Thread started by the plugin (its context class loader = plugin loader) | Timers, executor services, `HttpClient` selector threads | Shut down executors on undeploy; set TCCL carefully |
| JDBC driver registered in `DriverManager` (system class) | Driver in WEB-INF/lib | Deregister on undeploy or put drivers in the server lib |
| JDK caches keyed by class | `java.beans.Introspector`, `ObjectStreamClass` cache, `ResourceBundle` cache | `Introspector.flushCaches()`, `ResourceBundle.clearCache(loader)` |
| Shutdown hooks, `java.util.logging` handlers, JMX MBeans registered by plugin code | Frameworks | Unregister on stop |
| Generated classes cached by a library loaded **above** the plugin loader | CGLIB/ByteBuddy caches, Jackson type caches, Groovy `ClassInfo` | Load such libraries per plugin, or clear caches |

**Symptom:** `java.lang.OutOfMemoryError: Metaspace` after N redeploys, or Metaspace usage that ratchets up step by step in your metrics (`jvm.memory.used{area=nonheap,id=Metaspace}`).

**Diagnosis:**

```bash
jcmd <pid> VM.classloader_stats          # one row per loader: #classes, chunk/block sizes
jcmd <pid> VM.metaspace show-loaders     # Metaspace usage per loader
jcmd <pid> GC.class_histogram | head -40 # count instances of your loader class (e.g. 12 × WebappClassLoader = leak)
jcmd <pid> GC.heap_dump /tmp/h.hprof     # Eclipse MAT: "Duplicate Classes" + "Path to GC Roots" on the loader
java -Xlog:class+unload=info ...         # confirm classes ever unload
```

Real `VM.classloader_stats` header on JDK 25:

```
ClassLoader         Parent              CLD*               Classes   ChunkSz   BlockSz  Type
0x00000000121da800  0x00000000121dad20  0x0000019fe08e2600       2      6144      3568  jdk.internal.loader.ClassLoaders$AppClassLoader
0x0000000000000000  0x0000000000000000  0x0000019fe08e2300     740   4456448    158968  <boot class loader>
```

---

## 8. Hidden classes, lambdas and generated code 🧊

* **Hidden classes** (JEP 371, JDK 15): defined via `MethodHandles.Lookup.defineHiddenClass(bytes, initialize, options…)`. They are **not discoverable by name** (`Class.forName` fails), cannot be referenced from other classes' constant pools, and get a name like `Host$$Lambda/0x0000000013040210` (the suffix is not a valid binary name).
* They can be **unloaded independently** of their defining loader unless created with `ClassOption.STRONG`. This is why lambda-heavy and proxy-heavy frameworks moved to hidden classes instead of `Unsafe.defineAnonymousClass`, which was removed in JDK 17.
* Lambdas: `invokedynamic` → `LambdaMetafactory` → a hidden class implementing the functional interface, nestmate of the host (so it can call the host's private `lambda$main$0`). See Pillar 2, file 03.
* Frameworks: Spring (CGLIB repackaged, plus AOT-generated classes), Hibernate (ByteBuddy), Mockito (ByteBuddy inline mock maker + instrumentation), Jackson Blackbird (`LambdaMetafactory`).

---

## 9. Class Data Sharing and the Leyden AOT cache ⚡

| Feature | JDK | Command | What's cached |
|---|---|---|---|
| Default CDS archive | 12+ (JEP 341) | automatic | ~1,300 core JDK classes, pre-parsed and verified |
| AppCDS | 10+ (JEP 310) | `-XX:SharedArchiveFile=app.jsa` | Application classes too |
| Dynamic CDS | 13+ (JEP 350) | `-XX:ArchiveClassesAtExit=app.jsa` | Classes loaded during a run |
| **AOT class loading & linking** | 24 (JEP 483) | `-XX:AOTMode=record -XX:AOTConfiguration=app.aotconf` then `-XX:AOTMode=create … -XX:AOTCache=app.aot` | Classes **loaded and linked** (resolved CP entries, lambdas/indy call sites) |
| **One-step AOT** | 25 (JEP 514) | `-XX:AOTCacheOutput=app.aot` | Same as above. `JDK_AOT_VM_OPTIONS` passes options to the cache-creation sub-run |
| **AOT method profiling** | 25 (JEP 515) | (automatic with the AOT cache) | Method execution profiles, so the JIT compiles hot code sooner |
| **AOT object caching, any GC** | 26 (JEP 516) | (automatic) | Heap objects in a GC-agnostic format, **including ZGC** (JEP 483 did not support ZGC) |

**Constraints (JEP 483):** same JDK release, OS and CPU architecture. The production class path must equal the training class path or extend it by appending (JARs only, no directories). `--module-path`, `--add-modules` and `--enable-native-access` must be identical, and `--add-opens`/`--patch-module`/… must not be used. Classes from **custom class loaders are not cached**. Agents that rewrite classes via `ClassFileLoadHook` disable it. On a mismatch HotSpot **warns and ignores the cache** (`-XX:AOTMode=on` turns that into a hard error, which is useful in CI). JEP 483's measurement: Spring PetClinic startup went from **4.486 s → 2.604 s (−42%)** with a 130 MB cache.

---

## 10. The Java Platform Module System (JPMS) internals 🔥🎓

### 10.1 Module descriptor

```java
// module-info.java  → compiled to module-info.class (Module attribute)
module com.acme.orders {
    requires java.sql;                          // readability edge
    requires transitive com.acme.money;         // implied readability for my consumers
    requires static com.github.spotbugs.annotations; // compile-time only (optional at run time)
    exports com.acme.orders.api;                // public types accessible at compile+run time
    exports com.acme.orders.spi to com.acme.plugins; // qualified export
    opens com.acme.orders.model to com.fasterxml.jackson.databind, org.hibernate.orm.core; // deep reflection at run time only
    uses com.acme.orders.spi.PricingRule;       // ServiceLoader consumer
    provides com.acme.orders.spi.PricingRule with com.acme.orders.internal.DefaultRule;
}
```

### 10.2 Readability vs accessibility (the two checks) 🎓

For code in module **M** to access a type `T` in package `p` of module **N**, all of the following must hold:

1. **M reads N**: `requires`, `requires transitive` closure, or `--add-reads`, or `Module.addReads` at run time.
2. **N exports `p`** to M (or to everyone): **compile-time and run-time** access to `public` members of public types.
3. The member is `public` (for normal access), **or** N **opens** `p` to M, which permits **deep reflection** (`setAccessible(true)` on private members) at run time only.

| Directive | Compile-time access to public | Run-time reflection on public | Deep reflection (private) |
|---|---|---|---|
| `exports p` | ✅ | ✅ | ❌ |
| `opens p` | ❌ | ✅ | ✅ |
| `exports p` + `opens p` (or `open module`) | ✅ | ✅ | ✅ |
| neither | ❌ | ❌ | ❌ → `InaccessibleObjectException` |

### 10.3 Kinds of modules 🎓

| Kind | How you get it | Reads | Exports/opens |
|---|---|---|---|
| Named (explicit) | JAR with `module-info.class` on the **module path** | Only what it `requires` | Only what it declares |
| **Automatic** | Plain JAR on the **module path** | **All** modules, including the unnamed module | **All** packages (exported and opened) |
| **Unnamed** | Everything on the **class path** | All modules | All packages, but named modules cannot `require` it |

* An automatic module's name comes from the manifest `Automatic-Module-Name`, or is derived from the JAR file name (`jackson-core-2.17.1.jar` → `jackson.core`). Library authors should set `Automatic-Module-Name` before modularizing.
* **Top-down migration:** move your app to modules first, with dependencies as automatic modules. **Bottom-up:** modularize the leaf libraries first.

### 10.4 Boot-layer resolution and layers 🧊

At startup, `java --module-path mods -m com.acme.orders/com.acme.Main`:

1. Finds root modules (`-m` target, plus `--add-modules`, plus default JDK roots when the main is on the class path).
2. **Resolves** the transitive `requires` graph (`java.lang.module.Configuration`) and fails fast on missing modules, duplicate modules, split packages or cycles (cycles are illegal among `requires`).
3. Maps modules to loaders (JDK modules → boot/platform, application modules → app loader) and creates the **boot `ModuleLayer`**.

`java --show-module-resolution -m …` prints the resolution. `java -Xlog:module=debug` shows more.

**Layers** let you load *different versions* of the same module side by side, which is the JPMS answer to plugin isolation:

<!-- run: compile -->
```java
import java.lang.module.Configuration;
import java.lang.module.ModuleFinder;
import java.nio.file.Path;
import java.util.ServiceLoader;
import java.util.Set;

public final class PluginHost {
    /** Loads plugin modules from a directory into a child layer with its own loader. */
    public static <S> ServiceLoader<S> loadPlugins(Path pluginDir, String rootModule, Class<S> service) {
        ModuleLayer parent = ModuleLayer.boot();
        Configuration cf = parent.configuration()
                .resolveAndBind(ModuleFinder.of(pluginDir), ModuleFinder.of(), Set.of(rootModule));
        ModuleLayer layer = parent.defineModulesWithOneLoader(cf, ClassLoader.getSystemClassLoader());
        return ServiceLoader.load(layer, service);       // finds providers declared with `provides`
    }
}
```

### 10.5 Strong encapsulation in practice (JEP 396 → 403) 🔥

Since JDK 17 there is no `--illegal-access` escape hatch. Deep reflection into JDK internals throws:

```
java.lang.reflect.InaccessibleObjectException: Unable to make field private final byte[] java.lang.String.value
accessible: module java.base does not "opens java.lang" to unnamed module @6d06d69c
```

Escape hatches, all of which should be documented as tech debt:

```bash
--add-opens java.base/java.lang=ALL-UNNAMED      # deep reflection
--add-exports java.base/sun.nio.ch=ALL-UNNAMED   # compile/run access to non-exported public types
--add-reads my.module=ALL-UNNAMED
--patch-module java.base=patch.jar               # replace/augment module contents (testing)
--enable-native-access=ALL-UNNAMED               # FFM restricted methods + JNI without warnings (JEP 472)
```

These can also be set in an executable JAR's manifest: `Add-Opens: java.base/java.lang`, `Add-Exports: …`, `Enable-Native-Access: ALL-UNNAMED`.

### 10.6 Services: `ServiceLoader` mechanics ⚡🎓

* **Module path:** providers are declared via `provides … with …`. The provider class may expose a `public static provider()` method instead of a no-arg constructor.
* **Class path:** `META-INF/services/<fully.qualified.Service>` files list implementation classes.
* `ServiceLoader` is **lazy** and **not thread-safe**. `stream()` gives `Provider` handles so you can filter by `type()` **without instantiating**. Cache the loader if you iterate often, because each iteration re-scans.

### 10.7 Packaging tools 🎓

```bash
jdeps --multi-release 25 --print-module-deps --ignore-missing-deps app.jar   # → java.base,java.sql,java.net.http
jdeps -s app.jar libs/*.jar                       # summary of dependencies between JARs/modules
jdeps --jdk-internals app.jar                     # find uses of JDK internals (pre-upgrade audit)

jlink --add-modules java.base,java.sql,java.net.http \
      --strip-debug --no-header-files --no-man-pages --compress zip-6 \
      --output build/runtime                      # custom runtime image (~40-60 MB instead of ~300 MB)
build/runtime/bin/java --list-modules

jar --create --file app.jar --main-class com.acme.Main -C classes .
jar --describe-module --file app.jar              # shows module descriptor or derived automatic module
java -p mods -m com.acme.orders/com.acme.Main     # run from module path
java --list-modules ; java --describe-module java.sql
jpackage --name orders --input lib --main-jar app.jar   # native installers
```

* JDK 24 (JEP 493) lets `jlink` build images **without JMOD files** when the JDK was built that way. Some vendor JDKs ship without `jmods/`.
* **Multi-release JARs** (`Multi-Release: true`, `META-INF/versions/21/…`) let a library ship JDK-version-specific classes.

### 10.8 Module import declarations (JDK 25, JEP 511) 🎓

```java
import module java.base;      // imports all packages exported by java.base (on-demand, like p.*)
import module java.sql;       // also imports packages of modules it `requires transitive` (java.xml, java.logging)

// Ambiguity: java.util.Date vs java.sql.Date → resolve with a single-type import, which shadows:
import java.sql.Date;
```

Single-type imports shadow on-demand imports, and on-demand package imports (`p.*`) shadow module imports. Compact source files (JEP 512) implicitly `import module java.base`.

---

## 11. Production failure modes & diagnostics (class loading)

| Symptom | Root cause | Diagnose | Fix |
|---|---|---|---|
| `ClassNotFoundException` | Dynamic load by name failed (`forName`, `loadClass`): JAR missing or wrong loader (TCCL) | `-Xlog:class+load`, `-verbose:class`, `jar tf`, check `Thread.getContextClassLoader()` | Fix the classpath; pass the right loader |
| `NoClassDefFoundError: x/Y` (no "Could not initialize") | Class present at compile time, absent at run time (resolution of a symbolic reference failed) | Stack trace shows the referencing class; `mvn dependency:tree` | Add the dependency; align versions |
| `NoClassDefFoundError: Could not initialize class X` | Earlier `<clinit>` failure | Find the first `ExceptionInInitializerError` | Fix the initializer; avoid fragile static init |
| `NoSuchMethodError` / `NoSuchFieldError` / `AbstractMethodError` / `IncompatibleClassChangeError` | Binary-incompatible library versions (compiled against v2, running v1) | `-Xlog:class+load` to see *which JAR* won; `mvn dependency:tree -Dverbose`, `gradle dependencyInsight` | Dependency convergence (enforcer plugin), BOMs |
| `LinkageError: loader constraint violation` | Same API class loaded by two loaders that interact | Message names both loaders | De-duplicate JARs (provided scope) |
| `LinkageError: duplicate class definition` | Two threads racing `defineClass` in a non-parallel-capable custom loader, or defining twice | Stack | Use `getClassLoadingLock`, `findLoadedClass` first |
| `OutOfMemoryError: Metaspace` | Loader leak or unbounded class generation (proxies per request, Groovy scripts compiled per call, unbounded `Lookup.defineClass`) | `VM.classloader_stats`, `VM.metaspace`, histogram of loader classes, MAT | Fix the leak; cache generated classes; set `-XX:MaxMetaspaceSize` so the leak fails loudly |
| `OutOfMemoryError: Compressed class space` | > ~1 GB of `Klass` structures (huge class counts) | `VM.metaspace` | `-XX:CompressedClassSpaceSize` (max 4 GB), or reduce class generation |
| Startup slow | Class loading/verification dominates; single-lock custom loader | `-Xlog:class+load` timestamps, `-Xlog:startuptime`, JFR `jdk.ClassLoad` (disabled by default; enable it) | AppCDS / AOT cache, `registerAsParallelCapable`, lazy init |
| Hang, threads RUNNABLE in `<clinit>` | Class-init deadlock | Thread dump: frames in `<clinit>` of mutually dependent classes | Break the static-init cycle |
| `InaccessibleObjectException` after JDK upgrade | Strong encapsulation | Message names module/package | Upgrade the library, or `--add-opens` (documented) |

---

## 12. Interview & certification Q&A

<details><summary><b>Q1. 🔥 What uniquely identifies a class at run time, and what production bug does that explain?</b></summary>

The pair ⟨fully qualified binary name, **defining** class loader⟩. Two loaders that each define `com.acme.User` produce two incompatible classes, which leads to `ClassCastException: com.acme.User cannot be cast to com.acme.User` (the message names both loaders), loader-constraint `LinkageError`s, and static singletons that exist "twice". This typically happens with duplicate JARs in an app-server's shared lib and the webapp, or with hot-reload restart loaders.
</details>

<details><summary><b>Q2. 🔥 Explain parent delegation. Why do Tomcat and OSGi violate it, and what changed with JPMS?</b></summary>

`loadClass` checks `findLoadedClass`, delegates to the parent, and only then calls its own `findClass`. This guarantees core classes come from trusted loaders and gives a single copy of shared types. Webapp/plugin containers use **child-first** for application classes so each deployment can bring its own library versions; they still delegate `java.*` and container APIs. JPMS made the built-in loaders **module-aware**: a package maps to exactly one module in a layer, and the loader delegates directly to the module's loader. Split packages across named modules are therefore illegal.
</details>

<details><summary><b>Q3. 🎓 Which of these initialize class `C`: `C[] a = new C[5]`, `C.class`, reading `static final int X = 3`, reading `static final Integer Y = 3`, calling a static method, `Class.forName("C")`?</b></summary>

Only reading `Y` (not a constant variable, because it is boxed), calling a static method, and `Class.forName("C")` (the 1-arg form initializes). Array creation, class literals and compile-time constants (inlined by javac) do not.
</details>

<details><summary><b>Q4. 🔥 You see `NoClassDefFoundError: Could not initialize class com.acme.Config` in logs. What happened and where do you look?</b></summary>

`Config`'s `<clinit>` threw earlier, which surfaced once as `ExceptionInInitializerError` (or as the original `Error`). The class is now permanently in the *erroneous* state for this loader, so every later use throws NCDFE. Find the **first** `ExceptionInInitializerError` in the logs; current JDKs also attach it as the NCDFE's cause. Typical root causes are missing configuration, failed static resource loading, or a failing `static` HTTP client creation.
</details>

<details><summary><b>Q5. ⚡ Why is the holder idiom thread-safe without `volatile`, and what does the JIT do with it?</b></summary>

JVMS §5.5 guarantees `<clinit>` runs exactly once, under the class's initialization lock, and that its writes **happen-before** any use by other threads that observe the class as initialized. After initialization the class-init check is a no-op, and C2 compiles `Holder.INSTANCE` as a plain (even constant-folded, because it is `static final`) load. So you get lazy, thread-safe initialization with zero steady-state cost.
</details>

<details><summary><b>Q6. ⚡ How do you detect a class-initialization deadlock? Why doesn't `findDeadlockedThreads` see it?</b></summary>

The threads wait on VM-internal class-init locks, not Java monitors or `j.u.c` locks, so they appear **RUNNABLE** and are not part of the monitor ownership graph that `findDeadlockedThreads` and jstack's deadlock detector inspect. In the dump, look for threads stuck with `<clinit>` frames of classes that reference each other. Fix by removing static-initialization cycles.
</details>

<details><summary><b>Q7. 🔥 When is a class unloaded? Give three ways a webapp leaks its class loader.</b></summary>

Only when its defining loader becomes unreachable, and only during a GC that does class unloading. Leaks: (1) a `ThreadLocal` value on a server thread referencing a webapp class; (2) a thread started by the webapp (its TCCL or its `Runnable` references the loader); (3) a JDBC driver registered in the system-level `DriverManager`. Others: JMX MBeans, shutdown hooks, logging handlers, library caches loaded by a parent loader.
</details>

<details><summary><b>Q8. 🧊 What are hidden classes and why did lambdas/proxies move to them?</b></summary>

Classes defined through `Lookup.defineHiddenClass` that have no discoverable name, cannot be linked to by other classes, can be nestmates of the lookup class (for private access), and can be unloaded independently of their loader (unless `STRONG`). They replaced `Unsafe.defineAnonymousClass` (removed in 17) and allow per-call-site generated code without polluting the loader's namespace or Metaspace forever.
</details>

<details><summary><b>Q9. 🎓 `exports` vs `opens`? What does an automatic module export?</b></summary>

`exports p` grants compile-time and run-time access to public types and members of `p`. `opens p` grants run-time **deep reflection** (including private members) but no compile-time access. An `open module` opens all packages. An automatic module (plain JAR on the module path) **exports and opens all** its packages and **reads all** modules, including the unnamed module.
</details>

<details><summary><b>Q10. 🎓 Name the jlink/jdeps commands to build a minimal runtime for an app.</b></summary>

`jdeps --print-module-deps --ignore-missing-deps --multi-release 25 app.jar` gives the module list. Then `jlink --add-modules <list> --strip-debug --no-header-files --no-man-pages --compress zip-6 --output runtime`. Run with `runtime/bin/java -jar app.jar` (class path) or `-p mods -m mod/main.Class` (module path).
</details>

<details><summary><b>Q11. ⚡ Leyden AOT cache vs CDS vs Native Image: what does each cache, and what are the AOT cache's constraints?</b></summary>

CDS caches parsed and verified class metadata. The AOT cache (JDK 24+) adds the *loaded and linked* state (resolved constant-pool entries, lambda call sites), method profiles (25) and heap objects (26, any GC). It requires the same JDK, OS and CPU architecture, a training class path that is a prefix of the production one, and identical module options. It does not cache classes from custom loaders, and on a mismatch it warns and ignores the cache. Native Image compiles a closed world ahead of time: fastest startup and smallest RSS, but no dynamic class loading and lower peak throughput without PGO.
</details>

<details><summary><b>Q12. 🔥 `NoSuchMethodError` appears in production only when one specific endpoint is hit. Why not at startup?</b></summary>

HotSpot resolves constant-pool method references **lazily**, the first time the invoking bytecode executes. The binary incompatibility (code compiled against library v2, running with v1 on the class path) stays dormant until that code path runs. Find which JAR provided the class with `-Xlog:class+load=info`, then enforce dependency convergence.
</details>

<details><summary><b>Q13. 🎓 Given `import module java.base; import module java.sql;`, why does `Date d;` fail and how do you fix it?</b></summary>

Both `java.util.Date` (via `java.base`) and `java.sql.Date` (via `java.sql`) are imported on demand, so the simple name is ambiguous and compilation fails. Add a single-type import (`import java.sql.Date;`), which shadows module and on-demand imports.
</details>

<details><summary><b>Q14. ⚡ Why should a custom class loader call `registerAsParallelCapable()`?</b></summary>

Without it, `getClassLoadingLock(name)` returns the loader itself, so all class loading through that loader serializes on one monitor. That causes startup contention and, historically, deadlocks with cyclic delegation (pre-JDK 7). Parallel-capable loaders lock per class name.
</details>

---

## 13. Further reading

* JVMS SE 25 Chapter 5: <https://docs.oracle.com/javase/specs/jvms/se25/html/jvms-5.html>
* JLS §12.4: <https://docs.oracle.com/javase/specs/jls/se25/html/jls-12.html#jls-12.4>
* JEP 261 Module System, JEP 371 Hidden Classes, JEP 483/514/515/516 (Leyden), JEP 484 Class-File API, JEP 511 Module Imports.
* Alex Buckley, "State of the Module System". Mark Reinhold's JPMS talks.
