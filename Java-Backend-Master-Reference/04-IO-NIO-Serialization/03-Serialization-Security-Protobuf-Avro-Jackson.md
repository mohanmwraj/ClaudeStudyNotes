# 4.3 · Serialization — Java Serialization Internals & Security, Protobuf, Avro, Jackson 2 vs 3

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("Serialization and deserialization")
> **Sources:** Java Object Serialization Specification (JDK 25), JEP 290 (filter incoming serialization data), JEP 415 (context-specific filters), OWASP Deserialization Cheat Sheet, Frohoff & Lawrence "Marshalling Pickles" (2015) / ysoserial, Protocol Buffers encoding guide, Apache Avro specification, Jackson 2.x and 3.x release notes and docs.
> **Verified:** JDK 25, **Jackson 3.2.4** (`tools.jackson.*`) and Jackson 2.22.4 (`com.fasterxml.jackson.*`) downloaded from Maven Central. Protobuf and Avro bytes are produced by hand-written encoders in this file and match the official specs' examples.

---

## 1. Java serialization: how it works 🎓

```java
try (var out = new ObjectOutputStream(stream)) { out.writeObject(obj); }        // graph → bytes
try (var in = new ObjectInputStream(stream))  { Object o = in.readObject(); }   // bytes → graph (ANY class on the classpath!)
```

| Rule | Detail |
|---|---|
| Opt-in | The class must implement `Serializable` (a marker interface). Otherwise `NotSerializableException` |
| What's written | Class descriptors (name, `serialVersionUID`, field names and types) plus **non-`static`, non-`transient`** field values, recursively, with back-references (object graphs and cycles are preserved) |
| `transient` | Not written; restored as the **default value** (null/0/false) |
| `static` | Not part of the object, so not written |
| Constructor on deserialization | **Not called** for serializable classes. For the **first non-serializable superclass**, its **no-arg constructor IS called** (and must be accessible, else `InvalidClassException`) |
| Records | Deserialized **through the canonical constructor**, so validation runs (see §2.2) |
| Enums | Written by **name**; `valueOf` on read, so singletons are preserved |
| `serialVersionUID` | If not declared, computed from the class structure (any change can alter it), and a mismatch gives `InvalidClassException`. **Declare it explicitly** for classes you serialize |
| Customization | `writeObject`/`readObject` (private), `readResolve`/`writeReplace` (substitution, singletons, proxies), `readObjectNoData`, `Externalizable` (`writeExternal`/`readExternal`; requires a public no-arg constructor, which *is* called) |

<!-- run: -->
```java
import java.io.*;

public class SerializationBasics {
    static class Base {                                      // NOT Serializable
        String baseField = "set-in-field-init";
        Base() { System.out.println("  Base() no-arg constructor ran"); }
    }
    static class Account extends Base implements Serializable {
        private static final long serialVersionUID = 1L;
        static int instances = 0;
        final String id;
        transient String password;
        int balance;
        Account(String id, String pw, int balance) { this.id = id; this.password = pw; this.balance = balance; instances++; }
    }

    public static void main(String[] args) throws Exception {
        Account a = new Account("acc-1", "s3cret", 100);
        a.baseField = "changed-before-serialization";
        var bytes = new ByteArrayOutputStream();
        try (var out = new ObjectOutputStream(bytes)) { out.writeObject(a); }
        System.out.println("serialized " + bytes.size() + " bytes; deserializing:");
        Account.instances = 42;
        Account copy;
        try (var in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()))) { copy = (Account) in.readObject(); }
        System.out.println("  id=" + copy.id + " balance=" + copy.balance + " password(transient)=" + copy.password
            + " instances(static)=" + Account.instances + " baseField=" + copy.baseField);
        System.out.println("  Account(...) constructor ran? " + (Account.instances != 42));
        System.out.println("  explicit serialVersionUID=" + ObjectStreamClass.lookup(Account.class).getSerialVersionUID());
        try (var out = new ObjectOutputStream(OutputStream.nullOutputStream())) { out.writeObject(new Object()); }
        catch (NotSerializableException e) { System.out.println("  writeObject(new Object()) → NotSerializableException: " + e.getMessage()); }
    }
}
```

Output (verified):

```
  Base() no-arg constructor ran
serialized 96 bytes; deserializing:
  Base() no-arg constructor ran
  id=acc-1 balance=100 password(transient)=null instances(static)=42 baseField=set-in-field-init
  Account(...) constructor ran? false
  explicit serialVersionUID=1
  writeObject(new Object()) → NotSerializableException: java.lang.Object
```

The first `Base()` line comes from the normal `new Account(...)`. The second is printed **during `readObject`**: the non-serializable superclass's no-arg constructor runs, while `Account`'s own constructor does not. `baseField` came back as its **field-initializer value**, not the serialized one: the non-serializable superclass's state isn't serialized, and its no-arg constructor (with field initializers) ran instead. This is a classic exam trap.

---

## 2. Why Java serialization is dangerous 🔥

### 2.1 The deserialization attack model

* `readObject()` instantiates **any serializable class on the classpath** named in the stream, and invokes its `readObject`/`readResolve`/`hashCode` (when rebuilding hash sets and maps)… **before your code ever sees or casts the result**.
* **Gadget chains** combine innocent classes whose deserialization callbacks invoke each other until something powerful runs. The classic is Apache Commons Collections' `InvokerTransformer` reaching `Runtime.exec`, published in 2015, with tools like ysoserial. It led to remote-code-execution CVEs across WebLogic, WebSphere, JBoss, Jenkins and many more. You don't need a vulnerable class *of your own*, only one on the classpath.
* **Denial of service** needs no gadget: deeply nested `HashSet`s ("SerialDOS", exponential `hashCode` work), giant array length prefixes (memory), or deep object graphs (stack).

<!-- run: -->
```java
import java.io.*;

public class SideEffectBeforeCast {
    static class Innocent implements Serializable {
        @Serial private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
            in.defaultReadObject();
            System.out.println("  Innocent.readObject() ran — imagine this were a gadget chain");
        }
    }

    public static void main(String[] args) throws Exception {
        var bytes = new ByteArrayOutputStream();
        try (var out = new ObjectOutputStream(bytes)) { out.writeObject(new Innocent()); }   // attacker-controlled bytes
        try (var in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()))) {
            String expected = (String) in.readObject();                                      // our code "expects" a String
        } catch (ClassCastException e) {
            System.out.println("ClassCastException came too late: the payload already executed");
        }
    }
}
```

Output (verified):

```
  Innocent.readObject() ran — imagine this were a gadget chain
ClassCastException came too late: the payload already executed
```

### 2.2 Constructor bypass: invariants don't survive deserialization (records do)

<!-- run: -->
```java
import java.io.*;

public class InvariantBypass {
    static final class RangeClass implements Serializable {
        final int lo, hi;
        RangeClass(int lo, int hi) { if (lo > hi) throw new IllegalArgumentException("lo > hi"); this.lo = lo; this.hi = hi; }
    }
    record RangeRecord(int lo, int hi) implements Serializable {
        RangeRecord { if (lo > hi) throw new IllegalArgumentException("lo > hi"); }
    }

    static byte[] serialize(Object o) throws IOException {
        var b = new ByteArrayOutputStream();
        try (var out = new ObjectOutputStream(b)) { out.writeObject(o); }
        return b.toByteArray();
    }
    static byte[] tamper(byte[] data) {                       // attacker flips lo=0x11111111 to 0x7FFFFFFF in the stream
        for (int i = 0; i + 3 < data.length; i++)
            if (data[i] == 0x11 && data[i + 1] == 0x11 && data[i + 2] == 0x11 && data[i + 3] == 0x11) {
                data[i] = 0x7F; data[i + 1] = data[i + 2] = data[i + 3] = (byte) 0xFF; return data;
            }
        throw new IllegalStateException("marker not found");
    }
    static Object deserialize(byte[] d) throws Exception {
        try (var in = new ObjectInputStream(new ByteArrayInputStream(d))) { return in.readObject(); }
    }

    public static void main(String[] args) throws Exception {
        RangeClass c = (RangeClass) deserialize(tamper(serialize(new RangeClass(0x11111111, 0x22222222))));
        System.out.println("class:  deserialized lo=" + c.lo + " hi=" + c.hi + " → invariant lo<=hi violated: " + (c.lo > c.hi));
        try { deserialize(tamper(serialize(new RangeRecord(0x11111111, 0x22222222)))); }
        catch (InvalidObjectException e) { System.out.println("record: rejected → " + e.getClass().getSimpleName() + " (cause: " + e.getCause().getMessage() + ")"); }
    }
}
```

Output (verified):

```
class:  deserialized lo=2147483647 hi=572662306 → invariant lo<=hi violated: true
record: rejected → InvalidObjectException (cause: lo > hi)
```

Ordinary classes are rebuilt **without running their constructors**, so tampered bytes produce objects your constructors would have rejected. You'd need a `readObject` that re-validates, or the **serialization proxy pattern** (*Effective Java* item 90). **Records** always go through the canonical constructor, which makes them the safest `Serializable` types.

### 2.3 Defences, in order of preference 🔥

1. **Don't deserialize untrusted data with Java serialization.** Not from HTTP, message queues, caches shared with other tenants, cookies, or files users upload. Use JSON, Protobuf or Avro with explicit schemas instead.
2. If you must, apply **deserialization filters** (JEP 290, JDK 9). Use an **allow-list** of expected classes plus limits on depth, references, array sizes and total bytes:

<!-- run: -->
```java
import java.io.*;
import java.util.*;

public class SerialFilters {
    record Order(String id, List<String> items) implements Serializable {}

    static Object read(byte[] data, ObjectInputFilter filter) throws Exception {
        try (var in = new ObjectInputStream(new ByteArrayInputStream(data))) {
            in.setObjectInputFilter(filter);
            return in.readObject();
        }
    }
    static byte[] write(Object o) throws IOException {
        var b = new ByteArrayOutputStream();
        try (var out = new ObjectOutputStream(b)) { out.writeObject(o); }
        return b.toByteArray();
    }

    public static void main(String[] args) throws Exception {
        // allow-list: our record, the collections it uses, java.base basics; reject everything else ("!*")
        ObjectInputFilter allowList = ObjectInputFilter.Config.createFilter(
            "maxdepth=10;maxrefs=1000;maxarray=10000;maxbytes=65536;SerialFilters$Order;java.util.ImmutableCollections$*;java.util.CollSer;java.lang.*;!*");

        System.out.println("allowed: " + read(write(new Order("o-1", List.of("a", "b"))), allowList));
        try { read(write(new java.util.Date()), allowList); }
        catch (InvalidClassException e) { System.out.println("unexpected class → " + e.getMessage()); }

        Object deep = null;
        for (int i = 0; i < 50; i++) deep = new Object[] {deep};          // nesting depth 50
        try { read(write(deep), ObjectInputFilter.Config.createFilter("maxdepth=20")); }
        catch (InvalidClassException e) { System.out.println("too deep → " + e.getMessage()); }
    }
}
```

Output (verified):

```
allowed: Order[id=o-1, items=[a, b]]
unexpected class → filter status: REJECTED
too deep → filter status: REJECTED
```

* JVM-wide filter: `-Djdk.serialFilter=…` (same pattern syntax), or `jdk.serialFilter` in `java.security`. JDK 17 (JEP 415) adds a **filter factory** (`-Djdk.serialFilterFactory`) to choose filters per context (per stream, per library).
* Patterns: `pkg.Class`, `pkg.*` (package), `pkg.**` (subpackages), `module/pkg.*`, `!` to reject, and limits `maxdepth`, `maxrefs`, `maxbytes`, `maxarray`. The first match wins, so end allow-lists with `!*`.
* Keep gadget libraries off the classpath, and keep them patched (Commons Collections 3.2.2+ disabled the dangerous transformers by default).
* Remember that **RMI, JMX (RMI connectors), some caching layers and old session-replication setups** use Java serialization under the hood. Lock down or disable those endpoints.

---

## 3. Binary schema formats: Protocol Buffers and Avro ⚡

### 3.1 Wire formats, by hand

Both formats are compact because they **don't send field names**. Protobuf sends a small **tag** (field number + wire type) per field. Avro sends **nothing per field**, because the reader must know the writer's schema.

<!-- run: -->
```java
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public class WireFormats {
    static void varint(ByteArrayOutputStream out, long v) {             // base-128 varint, little-endian groups
        while ((v & ~0x7FL) != 0) { out.write((int) ((v & 0x7F) | 0x80)); v >>>= 7; }
        out.write((int) v);
    }
    static long zigzag(long v) { return (v << 1) ^ (v >> 63); }         // maps -1→1, 1→2, -2→3 … (small negatives stay small)

    // Protobuf: message Item { int32 id = 1; string name = 2; }
    static byte[] protobuf(int id, String name) {
        var out = new ByteArrayOutputStream();
        varint(out, (1 << 3) | 0);                    // tag: field 1, wire type 0 (varint)
        varint(out, id);
        byte[] s = name.getBytes(StandardCharsets.UTF_8);
        varint(out, (2 << 3) | 2);                    // tag: field 2, wire type 2 (length-delimited)
        varint(out, s.length);
        out.writeBytes(s);
        return out.toByteArray();
    }

    // Avro: record Item { long id; string name; }  (no tags; zigzag longs; length-prefixed strings)
    static byte[] avro(long id, String name) {
        var out = new ByteArrayOutputStream();
        varint(out, zigzag(id));
        byte[] s = name.getBytes(StandardCharsets.UTF_8);
        varint(out, zigzag(s.length));
        out.writeBytes(s);
        return out.toByteArray();
    }

    public static void main(String[] args) {
        HexFormat hex = HexFormat.ofDelimiter(" ");
        byte[] pb = protobuf(150, "hi"), av = avro(150, "hi");
        String json = "{\"id\":150,\"name\":\"hi\"}";
        System.out.println("protobuf (" + pb.length + " B): " + hex.formatHex(pb));
        System.out.println("avro     (" + av.length + " B): " + hex.formatHex(av));
        System.out.println("json     (" + json.length() + " B): " + json);
        var neg = new ByteArrayOutputStream(); varint(neg, -1L);
        var zz = new ByteArrayOutputStream(); varint(zz, zigzag(-1));
        System.out.println("int64 -1 as plain varint: " + neg.size() + " bytes; with zigzag (sint64): " + zz.size() + " byte");
    }
}
```

Output (verified; `08 96 01` is the canonical example from the Protobuf encoding guide):

```
protobuf (7 B): 08 96 01 12 02 68 69
avro     (5 B): ac 02 04 68 69
json     (22 B): {"id":150,"name":"hi"}
int64 -1 as plain varint: 10 bytes; with zigzag (sint64): 1 byte
```

### 3.2 Schema evolution rules

| Rule | Protobuf (proto3) | Avro |
|---|---|---|
| Identify fields by | **Field number** (tag) | **Name**, matched between the writer's and reader's schema |
| Add a field | Safe (new number). Old readers skip unknown tags (and preserve them) | Safe **with a default** (reader fills it when the writer lacked it) |
| Remove a field | Safe; **`reserved`** its number and name so they're never reused | Safe if the reader has a default, or doesn't need it |
| Rename a field | Safe on the wire (the number matters); breaks JSON mapping | Use `aliases` |
| Change a type | Only compatible pairs (`int32`↔`int64`↔`uint32`↔`bool` share varint, with truncation caveats) | Promotions only (`int`→`long`→`float`→`double`, `string`↔`bytes`) |
| **Reuse a field number** | ☠️ **Never**: old data decodes into the wrong field | n/a |
| Presence of scalars | proto3 `optional` restores has-presence; otherwise defaults are indistinguishable from unset | Unions with `null` (`["null","string"]`) |
| Where the schema lives | Compiled-in generated classes on both sides | **Writer schema must be available to the reader**: embedded in container files, or by schema ID via a **schema registry** (Confluent/Apicurio) for Kafka messages |

### 3.3 Choosing a format

| Format | Size and speed | Schema | Evolution | Human-readable | Typical use |
|---|---|---|---|---|---|
| **JSON** (Jackson) | Largest, slowest to parse | Optional (JSON Schema/OpenAPI) | Loose (ignore unknowns) | ✅ | Public REST APIs, configs, logs |
| **Protobuf** | Small, fast; generated code | Required (`.proto`) | Strong rules via field numbers | ❌ | gRPC, internal RPC, mobile |
| **Avro** | Smallest (no tags), fast | Required; resolved at read time | Strongest (writer/reader resolution plus registry compatibility checks) | ❌ | Kafka event streams, data lakes (Avro/Parquet) |
| CBOR / MessagePack / Smile | Binary JSON-like | Optional | Like JSON | ❌ | IoT, caches |
| FlatBuffers / Cap'n Proto / SBE | **Zero-copy reads** (access fields in place) | Required | Moderate | ❌ | Low-latency trading (SBE), games |
| Java serialization | Large, slow, **dangerous** | Implicit (classes) | Fragile (`serialVersionUID`) | ❌ | Legacy only. Never across trust boundaries |
| Kryo | Fast | Registration | Weak | ❌ | Same-version clusters (Spark shuffle) |

---

## 4. Jackson in production (2.x and 3.x) 🔥

### 4.1 Jackson 3 vs 2: what changed (verified defaults)

Jackson 3.0 (2025) moved to `tools.jackson.*` packages (annotations stay in `com.fasterxml.jackson.annotation`), requires Java 17+, makes mappers **immutable and builder-configured**, and uses **unchecked exceptions**. Spring Boot 4 uses Jackson 3 by default (Pillar 6). Real defaults measured with both libraries:

| Default | Jackson **2.22.4** | Jackson **3.2.4** |
|---|---|---|
| Unknown JSON property | `UnrecognizedPropertyException` (`FAIL_ON_UNKNOWN_PROPERTIES=true`) | **Ignored** (`FAIL_ON_UNKNOWN_PROPERTIES=false`) |
| `null` into a primitive field | Coerced to 0/false (`FAIL_ON_NULL_FOR_PRIMITIVES=false`) | **Error** (`FAIL_ON_NULL_FOR_PRIMITIVES=true`) |
| `java.time.Instant` | `InvalidDefinitionException` without the JSR-310 module | **Built in**; written as ISO-8601 (`"2026-10-24T10:15:30Z"`) |
| Max nesting depth | 1,000 | **500** |
| Max string length | 20,000,000 chars | 100,000,000 chars |
| Max number length | 1,000 chars | 1,000 chars |
| Exception type | `JsonProcessingException` (**checked**) | `JacksonException` (**unchecked**, `RuntimeException`) |
| Mapper | `ObjectMapper` (mutable configuration, thread-safe after setup) | `JsonMapper.builder()...build()` (immutable); `rebuild()` to derive |

> **Upgrade trap:** services moving to Spring Boot 4 / Jackson 3 **stop rejecting unknown fields**. Typos in client payloads ("ammount") become silently ignored data. If strictness was a contract, re-enable `FAIL_ON_UNKNOWN_PROPERTIES` explicitly, or validate against a schema.

### 4.2 Runnable: Jackson 3 essentials, limits, and safe polymorphism

<!-- run: cp=jackson -->
```java
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import tools.jackson.core.JacksonException;
import tools.jackson.core.JsonParser;
import tools.jackson.core.JsonToken;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.ObjectReader;
import tools.jackson.databind.json.JsonMapper;

public class JacksonThree {
    record Order(String id, Instant createdAt, BigDecimal amount, List<String> tags) {}
    record Small(String id) {}

    @JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")          // logical names, NOT class names
    @JsonSubTypes({@JsonSubTypes.Type(value = Card.class, name = "card"), @JsonSubTypes.Type(value = Wire.class, name = "wire")})
    sealed interface Payment permits Card, Wire {}
    record Card(String last4) implements Payment {}
    record Wire(String iban) implements Payment {}

    static final JsonMapper MAPPER = JsonMapper.builder().build();                       // build once, share (thread-safe)
    static final JsonMapper STRICT = MAPPER.rebuild().enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES).build();
    static final ObjectReader ORDER_READER = MAPPER.readerFor(Order.class);              // pre-resolved, immutable, fastest

    public static void main(String[] args) {
        Order o = new Order("o-1", Instant.parse("2026-10-24T10:15:30Z"), new BigDecimal("19.90"), List.of("a", "b"));
        String json = MAPPER.writeValueAsString(o);
        System.out.println("records + java.time: " + json);
        System.out.println("roundtrip equals: " + ORDER_READER.readValue(json).equals(o));

        System.out.println("unknown property, default mapper: " + MAPPER.readValue("{\"id\":\"x\",\"ammount\":1}", Small.class));
        try { STRICT.readValue("{\"id\":\"x\",\"ammount\":1}", Small.class); }
        catch (JacksonException e) { System.out.println("unknown property, strict mapper → " + e.getClass().getSimpleName()); }

        String bomb = "[".repeat(2_000) + "]".repeat(2_000);
        try { MAPPER.readTree(bomb); }
        catch (JacksonException e) { System.out.println("nesting bomb → " + e.getOriginalMessage().replaceAll(", from.*", "")); }

        String payments = "[{\"type\":\"card\",\"last4\":\"4242\"},{\"type\":\"wire\",\"iban\":\"DE89\"}]";
        Payment[] ps = MAPPER.readValue(payments, Payment[].class);
        System.out.println("polymorphic (closed set of logical names): " + List.of(ps));
        try { MAPPER.readValue("{\"type\":\"java.lang.ProcessBuilder\"}", Payment.class); }
        catch (JacksonException e) { System.out.println("unknown type id rejected → " + e.getClass().getSimpleName()); }

        try (JsonParser p = MAPPER.createParser("{\"items\":[1,2,3,4],\"skip\":{\"huge\":\"…\"}}")) {   // streaming: O(1) memory
            long sum = 0;
            for (JsonToken t = p.nextToken(); t != null; t = p.nextToken())
                if (t == JsonToken.VALUE_NUMBER_INT) sum += p.getLongValue();
            System.out.println("streaming sum = " + sum);
        }
    }
}
```

Output (verified with jackson-core/databind 3.2.4 and jackson-annotations 2.22):

```
records + java.time: {"id":"o-1","createdAt":"2026-10-24T10:15:30Z","amount":19.90,"tags":["a","b"]}
roundtrip equals: true
unknown property, default mapper: Small[id=x]
unknown property, strict mapper → UnrecognizedPropertyException
nesting bomb → Document nesting depth (501) exceeds the maximum allowed (500
polymorphic (closed set of logical names): [Card[last4=4242], Wire[iban=DE89]]
unknown type id rejected → InvalidTypeIdException
streaming sum = 10
```

### 4.3 Jackson security rules 🔥

* **Polymorphic deserialization by class name is the Jackson equivalent of the Java-serialization gadget problem.** Dozens of jackson-databind CVEs (2017–2020) came from "default typing" with `Id.CLASS`, letting payloads name gadget classes. Rules:
  * Prefer `@JsonTypeInfo(use = Id.NAME)` with an explicit `@JsonSubTypes` list (a closed set, as above), or sealed hierarchies.
  * **Never** enable default typing for untrusted input. If unavoidable, use `activateDefaultTyping(ptv, …)` with a strict `BasicPolymorphicTypeValidator` allow-list. The old `enableDefaultTyping()` was removed in 3.0.
* Keep **`StreamReadConstraints`** (depth, string, number, name, document length) sized to your API. Lower them for public endpoints, and **raise them deliberately** (not globally) when an internal integration needs bigger documents.
* Limit request sizes at the HTTP layer too (Spring `spring.codec.max-in-memory-size`, Tomcat `maxPostSize`, gateway limits).

### 4.4 Jackson performance rules ⚡

| Rule | Why |
|---|---|
| Build **one** mapper per configuration and reuse it | Construction is expensive (introspection caches); mappers are thread-safe after configuration (2.x) or immutable (3.x) |
| Pre-build `ObjectReader`/`ObjectWriter` for hot types | Skips per-call type resolution |
| Read from `InputStream`/`byte[]`, not `String` | Avoids a char decode plus copy; Jackson detects the encoding |
| Stream large payloads (`JsonParser`/`JsonGenerator`, `MappingIterator`) | Constant memory; avoids humongous allocations ([1.6 Story 3](../01-JVM-Internals/06-Production-Failure-Modes-Diagnostics.md#-story-3--monday-morning-full-gc)) |
| Avoid `JsonNode` trees in hot paths | Trees allocate a node per value |
| Blackbird module (2.x) | Replaces reflection with `LambdaMetafactory` accessors (preferred over Afterburner on JDK 11+); much of this is built into 3.x |
| Buffer recycling with virtual threads | 2.16+ made the `BufferRecycler` pool pluggable (`JsonRecyclerPools`), because `ThreadLocal`-based recycling degenerates with millions of VTs. Pick a pool deliberately when you move to VTs |
| Don't `intern` field names from untrusted input | Bounded canonicalization only |

---

## 5. Production failure modes & diagnostics (serialization)

| Failure | Signature | Fix |
|---|---|---|
| Deserialization RCE | Security advisories for your stack; unexpected processes; WAF hits on `rO0AB` (base64 of `0xACED`, the Java serialization magic) | Remove Java deserialization of untrusted input; JEP 290 allow-lists; patch gadget libraries |
| `InvalidClassException: local class incompatible: stream classdesc serialVersionUID = …` | During a rolling deploy, caches or sessions written by version N fail to read in N+1 | Explicit `serialVersionUID`; better, a schema format; versioned cache keys |
| Silent data loss after the Jackson 3 upgrade | Misspelled fields ignored | Explicit `FAIL_ON_UNKNOWN_PROPERTIES` or schema validation |
| `StreamConstraintsException` after an upgrade | Large documents rejected (nesting > 500 in 3.x, strings > limit) | Raise limits per mapper deliberately; stream instead |
| `InvalidDefinitionException` for `java.time` on 2.x | Missing `jackson-datatype-jsr310` | Register `JavaTimeModule` (built in for 3.x) |
| Protobuf field-number reuse | Garbage values or wrong fields in old consumers | `reserved` numbers; Buf breaking-change checks in CI |
| Avro incompatible change | Schema registry rejects it, or consumers fail to deserialize | Compatibility mode (BACKWARD/FULL) checks in CI; defaults for new fields |
| GC pressure from JSON | Allocation profiles dominated by `char[]`/`String`/`JsonNode` | Bytes in, streaming, pre-built readers; avoid trees |

---

## 6. Interview & certification Q&A

<details><summary><b>Q1. 🎓 Which fields are restored, and how, when deserializing a `Serializable` class whose superclass is not `Serializable`?</b></summary>

The serializable class's own non-static, non-transient fields are restored from the stream. Transient fields get default values (static fields are untouched). The serializable class's constructor does **not** run. The first non-serializable superclass's **no-arg constructor runs** (it must be accessible), so its fields get their constructor or initializer values, not the serialized ones (they were never written).
</details>

<details><summary><b>Q2. 🔥 Why is Java deserialization of untrusted data dangerous even if your own classes are safe?</b></summary>

`readObject` instantiates whatever serializable classes the stream names, from anywhere on the classpath, and runs their deserialization callbacks (`readObject`, `readResolve`, `hashCode`/`equals` while rebuilding maps and sets) before your code casts the result. Chains of such callbacks in third-party libraries (gadget chains) can reach arbitrary code execution. Deeply nested collections cause DoS without any gadget.
</details>

<details><summary><b>Q3. ⚡ How do JEP 290 filters work? Write an allow-list filter.</b></summary>

An `ObjectInputFilter` is consulted for each class, array length, depth, reference count and byte count while reading. Patterns are evaluated in order, and the first match decides. Example: `"maxdepth=10;maxrefs=1000;maxbytes=65536;com.acme.dto.*;java.base/*;!*"`. Set it per stream (`setObjectInputFilter`), JVM-wide (`-Djdk.serialFilter`), or per context via a filter factory (JEP 415).
</details>

<details><summary><b>Q4. 🔥 Why are records safer to deserialize than ordinary classes?</b></summary>

Record deserialization reads the component values and then invokes the **canonical constructor**, so validation in the (compact) constructor runs and tampered streams can't create invalid instances. Ordinary classes are reconstructed without running constructors (demo: a tampered `RangeClass` came back with `lo > hi`).
</details>

<details><summary><b>Q5. ⚡ Protobuf vs Avro for Kafka events?</b></summary>

Avro sends no field tags (smaller), and resolves the writer schema against the reader schema at read time. With a schema registry you get centrally enforced compatibility rules (BACKWARD/FORWARD/FULL), which is the de facto standard in Kafka ecosystems. Protobuf identifies fields by number, so evolution is safe as long as numbers are never reused (`reserved`). It has excellent generated code and gRPC integration, and also works with schema registries. Choose by ecosystem: Avro for data-platform-centric pipelines, Protobuf when the same contracts serve gRPC services.
</details>

<details><summary><b>Q6. 🔥 What changed between Jackson 2 and 3 that could break a service silently?</b></summary>

Unknown properties are ignored by default in 3.x (they failed in 2.x), so client typos are no longer rejected. Null for primitives now fails (it was coerced to 0/false). Max nesting depth went from 1,000 to 500. Exceptions are unchecked, mappers are immutable and builder-configured, and the packages moved to `tools.jackson`. All of these were measured above.
</details>

<details><summary><b>Q7. ⚡ How do you safely deserialize polymorphic JSON?</b></summary>

Use logical type names with a closed list of subtypes (`@JsonTypeInfo(use = Id.NAME)` + `@JsonSubTypes`, or sealed types), never class names from the payload. Unknown type IDs are rejected (`InvalidTypeIdException`). If default typing is unavoidable, use a strict `PolymorphicTypeValidator` allow-list.
</details>

<details><summary><b>Q8. 🎓 What does `transient` do, and what about `static` fields?</b></summary>

`transient` fields are skipped during serialization and restored as defaults (null/0/false), unless custom `readObject` logic sets them. `static` fields belong to the class, not the instance, so they're never serialized. After deserialization they hold whatever the class currently has in the JVM.
</details>

---

## 7. Further reading

* OWASP Deserialization Cheat Sheet: <https://cheatsheetseries.owasp.org/cheatsheets/Deserialization_Cheat_Sheet.html>
* JEP 290, JEP 415; Java Object Serialization Specification ("Serialization Filtering").
* Protobuf encoding guide: <https://protobuf.dev/programming-guides/encoding/>. Avro spec: <https://avro.apache.org/docs/>
* Jackson 3.0 release notes and JSTEPs: <https://github.com/FasterXML/jackson/wiki>
