# 01 · Beam Stateful DoFn: Timers, `@OnWindowExpiration`, and Custom Coders

> **Folder:** `07-Production-Java-Code-Blueprints/` · **File 1 of 4**
> **Anchors:** Beam blog *Stateful processing with Apache Beam* and *Timely (and Stateful) Processing with Apache Beam*
> (K. Knowles) · Beam state and timer API Javadocs (`StateSpecs`, `OrderedListState`, `Timer`, `@OnWindowExpiration`,
> `@RequiresTimeSortedInput`) · Akidau et al., *MillWheel* (per-key state and timers) · Folder 01, file 02 (holds),
> Folder 02, file 03 (coders), Folder 03, file 01 (Windmill state costs).
> **Prev folder:** [06 · FinOps](../06-Lakehouse-Sinks-Backpressure-and-FinOps/03-cloud-finops-dataflow-vs-flink-k8s-vs-spark-structured-streaming.md)
> · **Next:** [02 · High-throughput I/O and async batch RPC](02-beam-high-throughput-io-wait-antipattern-async-batch-rpc-dofn.md)

---

## 0. What this file delivers

A complete, production-shaped **stateful and timely `DoFn`** for device telemetry, plus its tests. It exercises every
mechanism the curriculum calls for:

| Mechanism | Used for |
|-----------|----------|
| `OrderedListState` | event-time-ordered buffer with range reads and range deletes |
| `ValueState` / `CombiningState` | last emitted reading; per-window counters |
| Event-time timer (with **output timestamp hold**) | emit readings in order once the watermark guarantees completeness |
| Processing-time timer | **absence detection**: alert when a device goes silent |
| `@OnWindowExpiration` | final per-window summary at GC; state cleared afterward |
| `@RequiresTimeSortedInput` | the declarative alternative to manual buffering (runner-dependent) |
| **Custom versioned coder** | forward- and backward-compatible state encoding across pipeline updates |
| `TestStream` + `PAssert` | deterministic tests of event time, processing time, and lateness |

The design rules come from earlier folders. This file applies them all in one place.

---

## 1. Mechanics recap: the rules this code obeys

| Rule | Source | Consequence in code |
|------|--------|---------------------|
| State is per **(key, window)**; stateful `ParDo` needs **non-merging** windows | Folder 01, file 03 §2.1 | fixed hourly windows, not sessions |
| Every timer **holds the output watermark** at its output timestamp | Folder 01, file 02 §7.3 | the flush timer holds at the *earliest buffered* reading; the silence timer holds at the latest reading |
| A timer's output timestamp must be **≥ the current input's timestamp** | Folder 01, file 02 §7.3 | lower the hold only when the current element is the new minimum |
| Outputs from `@OnTimer` must be **≥ the timer's output timestamp** | same | flush emits readings with timestamps ≥ the hold |
| Event-time timers can't be set past the **window's expiry** | Beam validation | clamp flush targets to `window.maxTimestamp()` |
| Timer and state writes are part of each **commit** | Folder 03, file 01 §2.4 | batch flushes by rounding timer targets; don't rewrite big values |
| State values need coders, and **keys** need deterministic ones | Folder 02, file 03 | the value coder may contain doubles; the key is a `String` |
| Coders are part of **update compatibility** | file 04 | a version byte plus a length-prefixed extension block |

---

## 2. The naive version (and everything wrong with it)

```java
// ANTI-PATTERN: buffers in a ValueState<List>, emits on every element, no holds, no cleanup, Java serialization.
class NaiveTelemetryFn extends DoFn<KV<String, Reading>, KV<String, Long>> {
  @StateId("all")
  private final StateSpec<ValueState<List<Reading>>> allSpec =
      StateSpecs.value(SerializableCoder.of((Class<List<Reading>>) (Class<?>) ArrayList.class));   // (1) slow, fragile

  @ProcessElement
  public void process(@Element KV<String, Reading> e, @StateId("all") ValueState<List<Reading>> all,
                      OutputReceiver<KV<String, Long>> out) {
    List<Reading> list = Optional.ofNullable(all.read()).orElseGet(ArrayList::new);   // (2) full read per element
    list.add(e.getValue());
    list.sort(Comparator.comparingLong(Reading::tsMillis));                              // (3) O(n log n) per element
    all.write(list);                                                                     // (4) full rewrite per element
    Reading prev = list.size() > 1 ? list.get(list.size() - 2) : null;
    if (prev != null) {
      out.output(KV.of(e.getKey(), e.getValue().counter() - prev.counter()));            // (5) emitted before the
    }                                                                                    //     watermark: later
  }                                                                                      //     out-of-order data makes
}                                                                                        //     it wrong; no reset logic
// (6) No timers: a silent device is never detected. (7) No cleanup: the global window means state lives forever.
```

---

## 3. The production blueprint

### 3.1 Domain types and the versioned coder

```java
package dev.l7.blueprints.telemetry;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Objects;
import org.apache.beam.sdk.coders.Coder;
import org.apache.beam.sdk.coders.CustomCoder;
import org.apache.beam.sdk.coders.DoubleCoder;
import org.apache.beam.sdk.coders.NullableCoder;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.coders.VarIntCoder;
import org.apache.beam.sdk.coders.VarLongCoder;

/** A telemetry reading. `counter` is a monotonically increasing device counter that resets on reboot. */
public record Reading(long tsMillis, long counter, double temperatureC, String firmware /* nullable; added in v2 */) {

  /**
   * Wire format, designed for evolution FROM DAY ONE:
   *   [version: 1 byte] [core fields] [extension block: varint length + bytes]
   * - Core fields never change meaning or order.
   * - New optional fields go into the extension block, so OLDER decoders skip it (forward compatibility),
   *   and NEWER decoders treat a missing or short block as defaults (backward compatibility).
   * Doubles make this coder non-deterministic: fine for state values, never use it for keys.
   */
  public static final class ReadingCoder extends CustomCoder<Reading> {
    public static final ReadingCoder V1 = new ReadingCoder(1);
    public static final ReadingCoder V2 = new ReadingCoder(2);
    private static final int MAX_KNOWN_VERSION = 2;

    private static final Coder<Long> VARLONG = VarLongCoder.of();
    private static final Coder<Integer> VARINT = VarIntCoder.of();
    private static final Coder<Double> DOUBLE = DoubleCoder.of();
    private static final Coder<String> NULLABLE_STRING = NullableCoder.of(StringUtf8Coder.of());

    private final int writeVersion;

    private ReadingCoder(int writeVersion) {
      this.writeVersion = writeVersion;
    }

    @Override
    public void encode(Reading r, OutputStream out) throws IOException {
      out.write(writeVersion);
      VARLONG.encode(r.tsMillis(), out);
      VARLONG.encode(r.counter(), out);
      DOUBLE.encode(r.temperatureC(), out);
      ByteArrayOutputStream ext = new ByteArrayOutputStream();
      if (writeVersion >= 2) {
        NULLABLE_STRING.encode(r.firmware(), ext);
      }
      byte[] extBytes = ext.toByteArray();
      VARINT.encode(extBytes.length, out);
      out.write(extBytes);
    }

    @Override
    public Reading decode(InputStream in) throws IOException {
      int version = in.read();
      if (version < 0) {
        throw new EOFException();
      }
      long ts = VARLONG.decode(in);
      long counter = VARLONG.decode(in);
      double temp = DOUBLE.decode(in);
      int extLen = VARINT.decode(in);
      byte[] ext = in.readNBytes(extLen);                     // always consume the block, known or not
      if (ext.length != extLen) {
        throw new EOFException("truncated extension block");
      }
      String firmware = null;
      if (version >= 2 && extLen > 0) {
        firmware = NULLABLE_STRING.decode(new ByteArrayInputStream(ext));
      }
      // version > MAX_KNOWN_VERSION: decode core fields and ignore unknown extensions (forward compatible).
      return new Reading(ts, counter, temp, firmware);
    }

    @Override
    public boolean equals(Object o) {
      return o instanceof ReadingCoder c && c.writeVersion == writeVersion;
    }

    @Override
    public int hashCode() {
      return Objects.hash(ReadingCoder.class, writeVersion);
    }
  }
}
```

### 3.2 Output type: one sealed hierarchy, one coder

```java
package dev.l7.blueprints.telemetry;

import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import org.apache.beam.sdk.coders.BooleanCoder;
import org.apache.beam.sdk.coders.CustomCoder;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.coders.VarLongCoder;

public sealed interface DeviceOut permits DeviceOut.Delta, DeviceOut.Alert, DeviceOut.Summary {

  String deviceId();

  /** Counter delta between consecutive in-order readings; `reset` = counter went backwards (reboot). */
  record Delta(String deviceId, long tsMillis, long delta, boolean reset) implements DeviceOut {}

  /** No reading for the silence threshold (processing time). */
  record Alert(String deviceId, long lastSeenTsMillis, String reason) implements DeviceOut {}

  /** Emitted once per (device, window) at window expiry. */
  record Summary(String deviceId, long windowStartMillis, long windowEndMillis, long readings, long resets,
                 long unflushedAtExpiry) implements DeviceOut {}

  final class DeviceOutCoder extends CustomCoder<DeviceOut> {
    public static final DeviceOutCoder INSTANCE = new DeviceOutCoder();
    private static final int DELTA = 0;
    private static final int ALERT = 1;
    private static final int SUMMARY = 2;

    @Override
    public void encode(DeviceOut v, OutputStream out) throws IOException {
      switch (v) {
        case Delta d -> {
          out.write(DELTA);
          StringUtf8Coder.of().encode(d.deviceId(), out);
          VarLongCoder.of().encode(d.tsMillis(), out);
          VarLongCoder.of().encode(d.delta(), out);
          BooleanCoder.of().encode(d.reset(), out);
        }
        case Alert a -> {
          out.write(ALERT);
          StringUtf8Coder.of().encode(a.deviceId(), out);
          VarLongCoder.of().encode(a.lastSeenTsMillis(), out);
          StringUtf8Coder.of().encode(a.reason(), out);
        }
        case Summary s -> {
          out.write(SUMMARY);
          StringUtf8Coder.of().encode(s.deviceId(), out);
          VarLongCoder.of().encode(s.windowStartMillis(), out);
          VarLongCoder.of().encode(s.windowEndMillis(), out);
          VarLongCoder.of().encode(s.readings(), out);
          VarLongCoder.of().encode(s.resets(), out);
          VarLongCoder.of().encode(s.unflushedAtExpiry(), out);
        }
      }
    }

    @Override
    public DeviceOut decode(InputStream in) throws IOException {
      int tag = in.read();
      if (tag < 0) {
        throw new EOFException();
      }
      String id = StringUtf8Coder.of().decode(in);
      return switch (tag) {
        case DELTA -> new Delta(id, VarLongCoder.of().decode(in), VarLongCoder.of().decode(in), BooleanCoder.of().decode(in));
        case ALERT -> new Alert(id, VarLongCoder.of().decode(in), StringUtf8Coder.of().decode(in));
        case SUMMARY -> new Summary(id, VarLongCoder.of().decode(in), VarLongCoder.of().decode(in),
            VarLongCoder.of().decode(in), VarLongCoder.of().decode(in), VarLongCoder.of().decode(in));
        default -> throw new IOException("unknown DeviceOut tag " + tag);
      };
    }

    @Override
    public void verifyDeterministic() {}
  }
}
```

### 3.3 The stateful, timely `DoFn`

```java
package dev.l7.blueprints.telemetry;

import java.util.Iterator;
import org.apache.beam.sdk.coders.InstantCoder;
import org.apache.beam.sdk.metrics.Counter;
import org.apache.beam.sdk.metrics.Metrics;
import org.apache.beam.sdk.state.CombiningState;
import org.apache.beam.sdk.state.OrderedListState;
import org.apache.beam.sdk.state.StateSpec;
import org.apache.beam.sdk.state.StateSpecs;
import org.apache.beam.sdk.state.TimeDomain;
import org.apache.beam.sdk.state.Timer;
import org.apache.beam.sdk.state.TimerSpec;
import org.apache.beam.sdk.state.TimerSpecs;
import org.apache.beam.sdk.state.ValueState;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.Sum;
import org.apache.beam.sdk.transforms.windowing.BoundedWindow;
import org.apache.beam.sdk.transforms.windowing.IntervalWindow;
import org.apache.beam.sdk.values.KV;
import org.apache.beam.sdk.values.TimestampedValue;
import org.joda.time.Duration;
import org.joda.time.Instant;

/**
 * Per (device, hourly window):
 *  - buffer readings in event-time order; once the watermark passes them, emit counter deltas in order
 *    (correct under out-of-order arrival, with reset detection),
 *  - alert when a device is silent for SILENCE of processing time,
 *  - emit one Summary at window expiry; Beam then clears all state for the (device, window).
 */
public final class DeviceTelemetryFn extends DoFn<KV<String, Reading>, DeviceOut> {

  private static final Duration FLUSH_GRANULARITY = Duration.standardSeconds(10);   // batch emissions per key
  private static final Duration SILENCE = Duration.standardMinutes(5);

  private final Counter outOfOrderAfterFlush = Metrics.counter(DeviceTelemetryFn.class, "late_reading_after_flush");

  @StateId("buffer")
  private final StateSpec<OrderedListState<Reading>> bufferSpec = StateSpecs.orderedList(Reading.ReadingCoder.V2);

  @StateId("minBuffered")
  private final StateSpec<ValueState<Instant>> minBufferedSpec = StateSpecs.value(InstantCoder.of());

  @StateId("last")
  private final StateSpec<ValueState<Reading>> lastSpec = StateSpecs.value(Reading.ReadingCoder.V2);

  @StateId("readings")
  private final StateSpec<CombiningState<Long, long[], Long>> readingsSpec = StateSpecs.combining(Sum.ofLongs());

  @StateId("resets")
  private final StateSpec<CombiningState<Long, long[], Long>> resetsSpec = StateSpecs.combining(Sum.ofLongs());

  @TimerId("flush")
  private final TimerSpec flushSpec = TimerSpecs.timer(TimeDomain.EVENT_TIME);

  @TimerId("silence")
  private final TimerSpec silenceSpec = TimerSpecs.timer(TimeDomain.PROCESSING_TIME);

  @ProcessElement
  public void process(@Element KV<String, Reading> e, @Timestamp Instant ts, BoundedWindow window,
                      @StateId("buffer") OrderedListState<Reading> buffer,
                      @StateId("minBuffered") ValueState<Instant> minBuffered,
                      @TimerId("flush") Timer flush,
                      @TimerId("silence") Timer silence) {
    buffer.add(TimestampedValue.of(e.getValue(), ts));

    Instant min = minBuffered.read();
    if (min == null || ts.isBefore(min)) {
      // New earliest buffered reading: hold the output watermark here (legal: equals the current input timestamp),
      // and fire once the watermark passes the rounded-up target (clamped to the window's end).
      minBuffered.write(ts);
      flush.withOutputTimestamp(ts).set(clampToWindow(roundUp(ts), window));
    }

    // Absence detection: re-armed per reading (re-arm less often for chatty devices to save commit writes).
    // Holds the output watermark at this reading's timestamp until the timer fires or is re-armed.
    silence.withOutputTimestamp(ts).offset(SILENCE).setRelative();
  }

  @OnTimer("flush")
  public void onFlush(OnTimerContext c, @Key String deviceId, BoundedWindow window,
                      @StateId("buffer") OrderedListState<Reading> buffer,
                      @StateId("minBuffered") ValueState<Instant> minBuffered,
                      @StateId("last") ValueState<Reading> last,
                      @StateId("readings") CombiningState<Long, long[], Long> readings,
                      @StateId("resets") CombiningState<Long, long[], Long> resets,
                      @TimerId("flush") Timer flush,
                      OutputReceiver<DeviceOut> out) {
    Instant complete = c.fireTimestamp().plus(Duration.millis(1));   // watermark > fire time ⇒ readings < complete are final
    Reading prev = last.read();

    for (TimestampedValue<Reading> tv : buffer.readRange(BoundedWindow.TIMESTAMP_MIN_VALUE, complete)) {
      Reading r = tv.getValue();
      if (prev != null && r.tsMillis() <= prev.tsMillis()) {
        outOfOrderAfterFlush.inc();                                    // arrived after its successor was emitted
        continue;
      }
      readings.add(1L);
      if (prev != null) {
        boolean reset = r.counter() < prev.counter();
        if (reset) {
          resets.add(1L);
        }
        long delta = reset ? r.counter() : r.counter() - prev.counter();
        out.outputWithTimestamp(new DeviceOut.Delta(deviceId, r.tsMillis(), delta, reset), tv.getTimestamp());
      }
      prev = r;
    }
    if (prev != null) {
      last.write(prev);
    }
    buffer.clearRange(BoundedWindow.TIMESTAMP_MIN_VALUE, complete);

    Iterator<TimestampedValue<Reading>> rest = buffer.readRange(complete, BoundedWindow.TIMESTAMP_MAX_VALUE).iterator();
    if (rest.hasNext()) {
      Instant next = rest.next().getTimestamp();
      minBuffered.write(next);
      flush.withOutputTimestamp(next).set(clampToWindow(roundUp(next), window));   // next ≥ current hold: legal
    } else {
      minBuffered.clear();
    }
  }

  @OnTimer("silence")
  public void onSilence(@Key String deviceId, @StateId("last") ValueState<Reading> last, OutputReceiver<DeviceOut> out) {
    Reading r = last.read();
    out.output(new DeviceOut.Alert(deviceId, r == null ? -1L : r.tsMillis(), "silent for " + SILENCE));
  }

  @OnWindowExpiration
  public void onExpiry(@Key String deviceId, BoundedWindow window,
                       @StateId("buffer") OrderedListState<Reading> buffer,
                       @StateId("readings") CombiningState<Long, long[], Long> readings,
                       @StateId("resets") CombiningState<Long, long[], Long> resets,
                       OutputReceiver<DeviceOut> out) {
    long unflushed = 0;
    for (TimestampedValue<Reading> ignored : buffer.read()) {
      unflushed++;                                                     // normally 0: flush timers fire before GC
    }
    IntervalWindow w = (IntervalWindow) window;
    out.output(new DeviceOut.Summary(deviceId, w.start().getMillis(), w.end().getMillis(),
        readings.read(), resets.read(), unflushed));
    // After this callback, Beam clears all state for (device, window). There's no manual GC timer to forget.
  }

  private static Instant roundUp(Instant ts) {
    long g = FLUSH_GRANULARITY.getMillis();
    return new Instant(Math.floorDiv(ts.getMillis(), g) * g + g - 1);   // fires when watermark ≥ next boundary
  }

  private static Instant clampToWindow(Instant target, BoundedWindow window) {
    return target.isAfter(window.maxTimestamp()) ? window.maxTimestamp() : target;
  }
}
```

### 3.4 Wiring

```java
PCollection<DeviceOut> outputs = readings                      // PCollection<KV<String, Reading>>, event-time stamped
    .setCoder(KvCoder.of(StringUtf8Coder.of(), Reading.ReadingCoder.V2))
    .apply("Hourly", Window.<KV<String, Reading>>into(FixedWindows.of(Duration.standardHours(1)))
        .withAllowedLateness(Duration.standardMinutes(10)))
    .apply("Telemetry", ParDo.of(new DeviceTelemetryFn()))
    .setCoder(DeviceOut.DeviceOutCoder.INSTANCE);
```

### 3.5 The declarative alternative: `@RequiresTimeSortedInput`

```java
/**
 * The runner delivers each key's elements in TIMESTAMP ORDER (it buffers until the watermark passes them, and drops
 * elements later than allowed lateness). Much simpler code; latency ≈ watermark lag. Runner support varies
 * (DirectRunner and Flink support it; ⚠ verify Dataflow batch/streaming support for your version).
 */
public final class SortedDeltaFn extends DoFn<KV<String, Reading>, DeviceOut> {
  @StateId("last")
  private final StateSpec<ValueState<Reading>> lastSpec = StateSpecs.value(Reading.ReadingCoder.V2);

  @RequiresTimeSortedInput
  @ProcessElement
  public void process(@Element KV<String, Reading> e, @StateId("last") ValueState<Reading> last,
                      OutputReceiver<DeviceOut> out) {
    Reading r = e.getValue();
    Reading prev = last.read();
    if (prev != null) {
      boolean reset = r.counter() < prev.counter();
      out.output(new DeviceOut.Delta(e.getKey(), r.tsMillis(), reset ? r.counter() : r.counter() - prev.counter(), reset));
    }
    last.write(r);
  }
}
```

| | Manual `OrderedListState` + timers | `@RequiresTimeSortedInput` |
|---|---|---|
| Portability | any runner with `OrderedListState` | runner must support the annotation |
| Control | batching granularity, holds, custom late-data policy | runner policy |
| Code | more | minimal |
| Latency | tunable (granularity) | watermark-driven |

---

## 4. Tests: event time, processing time, lateness, and coder compatibility

```java
package dev.l7.blueprints.telemetry;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;
import org.apache.beam.sdk.coders.KvCoder;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.testing.PAssert;
import org.apache.beam.sdk.testing.TestPipeline;
import org.apache.beam.sdk.testing.TestStream;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.windowing.FixedWindows;
import org.apache.beam.sdk.transforms.windowing.Window;
import org.apache.beam.sdk.values.KV;
import org.apache.beam.sdk.values.PCollection;
import org.apache.beam.sdk.values.TimestampedValue;
import org.joda.time.Duration;
import org.joda.time.Instant;
import org.junit.Rule;
import org.junit.Test;

public class DeviceTelemetryFnTest {

  @Rule public final transient TestPipeline p = TestPipeline.create();

  private static final Instant T0 = new Instant(0L);

  private static TimestampedValue<KV<String, Reading>> reading(String id, long offsetSec, long counter) {
    Instant ts = T0.plus(Duration.standardSeconds(offsetSec));
    return TimestampedValue.of(KV.of(id, new Reading(ts.getMillis(), counter, 21.5, "fw-2")), ts);
  }

  @Test
  public void emitsInOrderDeltasDetectsResetAndSummarizes() {
    TestStream<KV<String, Reading>> input = TestStream.create(KvCoder.of(StringUtf8Coder.of(), Reading.ReadingCoder.V2))
        .advanceWatermarkTo(T0)
        .addElements(reading("d1", 30, 300), reading("d1", 10, 100))     // out of order
        .addElements(reading("d1", 20, 200))
        .advanceWatermarkTo(T0.plus(Duration.standardMinutes(1)))        // ⇒ flush 10s, 20s, 30s in order
        .addElements(reading("d1", 70, 5))                               // counter reset (reboot)
        .advanceWatermarkToInfinity();                                   // ⇒ final flush + window expiry

    PCollection<DeviceOut> out = p.apply(input)
        .apply(Window.<KV<String, Reading>>into(FixedWindows.of(Duration.standardHours(1)))
            .withAllowedLateness(Duration.standardMinutes(10)))
        .apply(ParDo.of(new DeviceTelemetryFn()))
        .setCoder(DeviceOut.DeviceOutCoder.INSTANCE);

    PAssert.that(out).satisfies(all -> {
      List<DeviceOut.Delta> deltas = new ArrayList<>();
      List<DeviceOut.Summary> summaries = new ArrayList<>();
      for (DeviceOut o : all) {
        switch (o) {
          case DeviceOut.Delta d -> deltas.add(d);
          case DeviceOut.Summary s -> summaries.add(s);
          case DeviceOut.Alert a -> { /* processing-time alerts tested separately */ }
        }
      }
      deltas.sort((a, b) -> Long.compare(a.tsMillis(), b.tsMillis()));
      assertEquals(3, deltas.size());
      assertEquals(100L, deltas.get(0).delta());                         // 200 - 100
      assertEquals(100L, deltas.get(1).delta());                         // 300 - 200
      assertTrue(deltas.get(2).reset());                                 // 5 < 300
      assertEquals(1, summaries.size());
      assertEquals(4L, summaries.get(0).readings());
      assertEquals(1L, summaries.get(0).resets());
      assertEquals(0L, summaries.get(0).unflushedAtExpiry());
      return null;
    });
    p.run().waitUntilFinish();
  }

  @Test
  public void alertsWhenDeviceGoesSilent() {
    TestStream<KV<String, Reading>> input = TestStream.create(KvCoder.of(StringUtf8Coder.of(), Reading.ReadingCoder.V2))
        .advanceWatermarkTo(T0)
        .addElements(reading("d2", 5, 1))
        .advanceProcessingTime(Duration.standardMinutes(6))              // > SILENCE ⇒ alert
        .advanceWatermarkToInfinity();

    PCollection<DeviceOut> out = p.apply(input)
        .apply(Window.<KV<String, Reading>>into(FixedWindows.of(Duration.standardHours(1))))
        .apply(ParDo.of(new DeviceTelemetryFn()))
        .setCoder(DeviceOut.DeviceOutCoder.INSTANCE);

    PAssert.that(out).satisfies(all -> {
      long alerts = 0;
      for (DeviceOut o : all) {
        if (o instanceof DeviceOut.Alert) {
          alerts++;
        }
      }
      assertEquals(1L, alerts);
      return null;
    });
    p.run().waitUntilFinish();
  }

  /** State written by the OLD pipeline (V1 coder) must decode in the NEW pipeline (V2), and vice versa. */
  @Test
  public void coderIsBackwardAndForwardCompatible() throws Exception {
    Reading original = new Reading(1_000L, 42L, 20.0, "fw-9");

    ByteArrayOutputStream v1Bytes = new ByteArrayOutputStream();
    Reading.ReadingCoder.V1.encode(original, v1Bytes);
    Reading readByV2 = Reading.ReadingCoder.V2.decode(new ByteArrayInputStream(v1Bytes.toByteArray()));
    assertEquals(42L, readByV2.counter());
    assertEquals(null, readByV2.firmware());                             // absent in v1: default

    ByteArrayOutputStream v2Bytes = new ByteArrayOutputStream();
    Reading.ReadingCoder.V2.encode(original, v2Bytes);
    Reading readByV1 = Reading.ReadingCoder.V1.decode(new ByteArrayInputStream(v2Bytes.toByteArray()));
    assertEquals(42L, readByV1.counter());                               // V1 skips the extension block
  }
}
```

Two notes on the tests. First, `ReadingCoder.V1.decode` *is* the same decoding logic: version is per write, and decoding
always skips unknown extensions. In a real migration, the "old" code is a previous release, and the property to test is
that **its** decoder skips extensions. That's why the extension block must exist from the very first version. Second,
`TestStream` processing-time advancement and timer semantics depend on the DirectRunner ⚠ verify on your Beam version.

---

## 5. Production failure modes and P99 debugging

| ID | Failure | Signature | Root cause | Fix |
|----|---------|-----------|------------|-----|
| S1 | **Watermark held for hours** | downstream windows don't close; per-stage watermark lags its input | a timer hold that never releases (perpetually re-armed silence timers on chatty keys; flush timer set far ahead) | re-arm sparingly; `withNoOutputTimestamp()` for timers that emit nothing; clamp targets |
| S2 | **"Cannot output with timestamp …"** | exceptions in `@OnTimer` | emitting elements earlier than the timer's output timestamp | hold at the earliest buffered element (§3.3) |
| S3 | **"Attempted to set event time timer … after the expiration of window"** | exceptions in `@ProcessElement` | timer target past `maxTimestamp + allowedLateness` | clamp to the window |
| S4 | **State growth in the global window** | per-key state never shrinks | no expiry (global window) and no cleanup timers | windows + `@OnWindowExpiration`, or explicit GC timers |
| S5 | **Timer storms** | huge timer firing rates after watermark jumps | per-distinct-timestamp timers | round targets to a granularity |
| S6 | **Commit-size errors** | `KeyCommitTooLargeException` (Dataflow) | big `ValueState<List>` rewrites | `OrderedListState`/`BagState`; bounded buffers |
| S7 | **Update rejected / state decode failure** | `--update` fails, or workers crash decoding state | coder changed incompatibly | versioned coders with an extension block; compatibility tests (§4) |
| S8 | **Stateful DoFn with merging windows** | pipeline construction error | state isn't supported with merging windows | fixed windows, or sessionize manually in the global window |

---

## 6. FAANG L7 bar-raiser Q&A chains

### Q1 · "Why buffer in `OrderedListState` and flush on an event-time timer instead of emitting deltas immediately?"

**L5 textbook answer.** To handle out-of-order data.

**Why L5 breaks.** Without the timer *and* the hold, the code is still wrong. Deltas emitted early are invalidated by
later-arriving earlier readings, and outputs emitted later with original timestamps arrive behind the downstream watermark
(late, so dropped by downstream windows).

**L7 principal defense.**

- **The event-time timer fires once the watermark guarantees completeness,** so the deltas are final.
- **The timer's output timestamp holds the watermark** at the earliest buffered reading, so emitted deltas stay on time
  downstream.
- **Rounding targets** batches flushes (fewer timer firings and commits).
- **`OrderedListState`** gives O(range) reads and deletes instead of whole-list rewrites.
- **The alternative** is `@RequiresTimeSortedInput` where the runner supports it.

### Q2 · "`@OnWindowExpiration` vs. a GC timer you set yourself: which and why?"

**L5 textbook answer.** They're equivalent.

**Why L5 breaks.** Hand-rolled GC timers are easy to get wrong:

- set past the window expiry (an exception);
- forgotten on code paths (state leaks);
- holding the watermark (a default output timestamp).

**L7 principal defense.** `@OnWindowExpiration` runs exactly at GC time (`maxTimestamp + allowedLateness`), lets you emit a
final output, and **guarantees state is cleared afterward**, with nothing to forget. Use custom timers only for
*business* timing (flushes, absence detection), and keep cleanup with the framework.

### Q3 · "How do you evolve a state coder without breaking `--update` or rollback?"

**L5 textbook answer.** Bump a version number in the coder.

**Why L5 breaks.** A version number alone gives backward compatibility (new reads old) but not **forward** compatibility
(old reads new), so rollback after the new version wrote state crashes the old workers.

**L7 principal defense.**

- **From day one:** a version byte, immutable core fields, and a **length-prefixed extension block** that every decoder
  skips if it doesn't understand it.
- **New fields** go into the extension with defaults.
- **Test** both directions with real previous-release decoders (§4).
- **Beam schemas** offer encoding positions for similar evolution (file 04).
- **Never** change a key coder's encoding for existing keys. That remaps state addresses.

---

## 7. Invariants checklist

1. **State is per (key, window).** Use non-merging windows for stateful `ParDo`.
2. **Hold at the earliest buffered element.** Lower the hold only to the current element's timestamp.
3. **Clamp event-time timers to the window. Round them for batching.**
4. **Cleanup belongs to `@OnWindowExpiration`** (windows) or explicit timers (global window).
5. **Prefer `OrderedListState`/`BagState` over `ValueState<List>`.**
6. **Version every state coder with an extension block from v1.** Test forward and backward.
7. **Test with `TestStream`:** out-of-order data, watermark advances, processing-time advances, expiry.

---

## 8. References

- K. Knowles. *Stateful processing with Apache Beam* (2017) and *Timely (and Stateful) Processing with Apache Beam*
  (2017). Apache Beam blog.
- Apache Beam Javadoc: `DoFn` (`@StateId`, `@TimerId`, `@OnTimer`, `@OnWindowExpiration`, `@RequiresTimeSortedInput`,
  `@Key`), `StateSpecs`, `OrderedListState`, `Timer`, `TestStream`, `PAssert`.
- Folder 01, file 02 (watermark holds); Folder 02, file 03 (coders); Folder 03, file 01 (state costs on Windmill).

**Next →** [02 · High-throughput I/O: the wait anti-pattern and the async batch RPC `DoFn`](02-beam-high-throughput-io-wait-antipattern-async-batch-rpc-dofn.md)
