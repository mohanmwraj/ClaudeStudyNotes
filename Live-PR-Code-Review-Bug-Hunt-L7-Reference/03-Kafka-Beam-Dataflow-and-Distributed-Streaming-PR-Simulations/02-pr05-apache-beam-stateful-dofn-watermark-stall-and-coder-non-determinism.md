# PR05 · Apache Beam: Stateful DoFn, Watermark Stall and Coder Non-Determinism

> **What this module is.** A fraud-velocity pipeline PR on Apache Beam 2.77. It adds de-duplication with a stateful `DoFn`, switches to cheaper windows, and blocks cards automatically. It hides **7 defects** that only make sense in Beam's model of time and encoding. One delays every fraud alert by 24 hours without dropping anything. One only manifests on a *fusing* production runner. One is currently **masked by another**, so fixing the first exposes the second. This module also shows why "it passes on the DirectRunner" proves less than it seems.

| Artifact | What it is | Verified |
|---|---|---|
| `pr05-diff` | `VelocityPipeline` (dedup, windowing, blocking) and `Txn.parse` changed + the test rewritten: 235 diff lines | `git diff --no-index` from compiled sources |
| `VelocityPipelineTest` (author's) | 3 tests on the DirectRunner: alert and block on 4-in-5-minutes, 3 is not enough, identical retries counted once | **3/3 pass** on the PR (§4) |
| `Pr05Probes` | 8 probes: field-order retry (by-reference passing), card-testing burst, watermark hold (TestStream), boundary burst, late event (+ a Beam-semantics check), two cards blocked, missing timestamp | each shows the defect on the PR and its absence on the fix (§8) |
| Fixed code | Dedup on `txnId` (deterministic `StringUtf8Coder`), no timer output-timestamp hold, sliding windows with allowed lateness, idempotency key per card-hour, timestamp-less events rejected | fixed suite 6/6; PR's own tests against the fix 2/3 (the failing test asserts "exactly one alert," a property of fixed windows) |

**Verification.** Apache Beam Java SDK 2.77.0 with the DirectRunner and `TestStream`, JDK 25.0.4.1, `javac --release 21 -Xlint:all,-path,-classfile -Werror`. The two disabled lint categories only flag Class-Path manifest entries and a missing SpotBugs annotation *inside* Beam's own jars. The watermark-hold behavior was first confirmed with a standalone experiment (the same 24 h hold, with and without `withOutputTimestamp`) before it was built into the probe. Every probe line is deterministic.

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L1 Correctness | F2 dedup identity merges distinct transactions, F4 fixed windows miss boundary bursts | "Dedup" and "5-minute window" read as correct English |
| L5 Encoding | F1 a key coder that claims determinism it doesn't have | Invisible on the DirectRunner, which round-trips elements through coders |
| L4 Time | F3 timer output timestamp holds the watermark for 24 h, F5 allowed lateness deleted (masked by F3), F7 processing time used as event time | Event time is a second clock that the code never shows |
| L3/L6 Side effects | F6 a constant idempotency key on an external call | "It's idempotent" until every card shares one key |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "It passed on the DirectRunner." | The DirectRunner re-encodes between steps, so a fusing runner behaves differently. |
| "`verifyDeterministic()` is boilerplate." | It's a contract the runner relies on to group keys. |
| "A timer that emits nothing is harmless." | Its output timestamp still holds the watermark. |
| "Fixed windows are the cheap version of sliding." | They're a different question, with blind spots at every boundary. |
| "Missing timestamp? Use now()." | Replays and backfills become non-deterministic. |

---

## 1. First principles

1. **Coders define key identity.** Runners group by encoded bytes. Beam's `Coder.verifyDeterministic()` contract: "two values that compare as equal … have the same encoding" and "the Coder always produces a canonical encoding … even if produced on different computers at different times." A `Map` encoded in iteration order breaks both, because `LinkedHashMap`s with equal entries in different insertion orders are `equals()` but encode differently.
2. **The DirectRunner is not a production runner.** It deliberately round-trips elements through their coders between transforms (to catch encodability bugs), so an element's *object state*, such as a `LinkedHashMap`'s order, is normalized by the element coder. Production runners fuse steps and pass objects by reference. Bugs that depend on object state can pass locally and fail in production.
3. **Timers hold watermarks.** Beam's programming guide: "By default, event-time timers will hold the output watermark of the `ParDo` to the timestamp of the timer." `withOutputTimestamp(t)` moves that hold to `t`. Set it to the element's timestamp on a 24-hour timer, and the step's output watermark cannot pass that timestamp for 24 hours. Every downstream window waits.
4. **Lateness is a policy, and Beam's default is unforgiving.** Elements behind the watermark by more than the allowed lateness are dropped (the `Window` javadoc: they "will be dropped"). Restoring tolerance means `withAllowedLateness` plus a trigger that fires late panes, and accumulating panes when the consumer needs totals.
5. **Fixed vs sliding windows answer different questions.** "More than 3 in any 5-minute span" is a sliding question. Fixed windows only see spans aligned to :00/:05/:10, so a burst across a boundary is split in two.
6. **Bundles are retried; side effects must be idempotent.** Runners re-execute failed bundles, and overlapping windows and late firings emit the same alert more than once. An external action needs an idempotency key that identifies *this* action. A constant key makes every action after the first look like a replay.
7. **Event time must come from the event.** Stamping missing timestamps with processing time makes window assignment depend on *when* the pipeline ran, so reprocessing yesterday's data puts it in today's windows.

---

## 2. The PR

> **FRAUD-311 · De-duplicate gateway retries; auto-block cards; cut windowing cost**
>
> Velocity alerts fire for customers who did nothing wrong: the card gateway retries authorizations on timeout, and retries were counted. Also: blocking is currently manual (an analyst reads the alert topic), which takes too long; and the pipeline's cost doubled after Black Friday.
>
> **PR description, by the author:**
> - De-duplicate on the payload fingerprint (all attributes except `txnId`/`ts`), because "retries can't be trusted to keep their id." Remembered for 24 h with a stateful `DoFn` and an event-time timer; the timer keeps the event's timestamp.
> - `AttrsCoder` for the fingerprint key, declared deterministic (it's a flat map of strings).
> - Fixed 5-minute windows instead of sliding (5 minutes every 1 minute): 5× fewer window assignments.
> - Simplified the windowing (dropped the trigger/lateness boilerplate).
> - Cards over threshold are blocked through card-control-service (idempotent API).
> - The legacy POS gateway sends no `ts`, so processing time is used for those events.
> - Tests: alert and block, below threshold, identical retries de-duplicated. All green.
>
> **Context the reviewer can discover:** gateway contract v3 §4.2, *retries reuse `txnId`*. Different gateway versions serialize fields in different orders. Production runs on Dataflow (streaming, fused stages). Mobile authorizations routinely arrive minutes late. Card-testing attacks send bursts of identical small authorizations. card-control-service treats a repeated idempotency key as a replay for 24 h. The pipeline is replayed from the archive after incidents.

---

## 3. The diff

```diff
diff --git a/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java b/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java
index cd26e73..76f02b4 100644
--- a/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java
+++ b/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java
@@ -17,10 +17,8 @@ public record Txn(String txnId, String cardId, long amountMinor, long eventMilli
             f.put(m.group(1), m.group(2) != null ? m.group(2) : m.group(3));
         }
         String ts = f.remove("ts");
-        if (ts == null) {
-            throw new IllegalArgumentException("txn without ts: " + json);
-        }
+        long eventMillis = ts != null ? Long.parseLong(ts) : System.currentTimeMillis(); // legacy POS gateway omits ts
         String id = f.remove("txnId");
-        return new Txn(id, f.get("card"), Long.parseLong(f.get("amount")), Long.parseLong(ts), f);
+        return new Txn(id, f.get("card"), Long.parseLong(f.get("amount")), eventMillis, f);
     }
 }
diff --git a/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java b/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java
index 59695c9..a6b08b1 100644
--- a/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java
+++ b/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java
@@ -1,16 +1,31 @@
 package com.acme.fraud;
 
+import java.io.IOException;
+import java.io.InputStream;
+import java.io.OutputStream;
+import java.util.LinkedHashMap;
+import java.util.Map;
+import org.apache.beam.sdk.coders.BooleanCoder;
+import org.apache.beam.sdk.coders.CustomCoder;
+import org.apache.beam.sdk.coders.KvCoder;
 import org.apache.beam.sdk.coders.SerializableCoder;
+import org.apache.beam.sdk.coders.StringUtf8Coder;
+import org.apache.beam.sdk.coders.VarIntCoder;
+import org.apache.beam.sdk.state.StateSpec;
+import org.apache.beam.sdk.state.StateSpecs;
+import org.apache.beam.sdk.state.TimeDomain;
+import org.apache.beam.sdk.state.Timer;
+import org.apache.beam.sdk.state.TimerSpec;
+import org.apache.beam.sdk.state.TimerSpecs;
+import org.apache.beam.sdk.state.ValueState;
 import org.apache.beam.sdk.transforms.Count;
 import org.apache.beam.sdk.transforms.DoFn;
 import org.apache.beam.sdk.transforms.Filter;
 import org.apache.beam.sdk.transforms.MapElements;
 import org.apache.beam.sdk.transforms.ParDo;
 import org.apache.beam.sdk.transforms.WithTimestamps;
-import org.apache.beam.sdk.transforms.windowing.AfterPane;
-import org.apache.beam.sdk.transforms.windowing.AfterWatermark;
 import org.apache.beam.sdk.transforms.windowing.BoundedWindow;
-import org.apache.beam.sdk.transforms.windowing.SlidingWindows;
+import org.apache.beam.sdk.transforms.windowing.FixedWindows;
 import org.apache.beam.sdk.transforms.windowing.Window;
 import org.apache.beam.sdk.values.KV;
 import org.apache.beam.sdk.values.PCollection;
@@ -19,26 +34,86 @@ import org.apache.beam.sdk.values.TypeDescriptors;
 import org.joda.time.Duration;
 import org.joda.time.Instant;
 
-/** Card velocity: more than THRESHOLD authorizations on one card within 5 minutes raises an alert. */
+/** Card velocity: more than THRESHOLD authorizations on one card within 5 minutes blocks the card. */
 public final class VelocityPipeline {
     static final long THRESHOLD = 3;
 
     private VelocityPipeline() {
     }
 
-    public static PCollection<Alert> expand(PCollection<String> rawJson) {
-        return rawJson
+    public static PCollection<Alert> expand(PCollection<String> rawJson, CardControl cardControl) {
+        PCollection<Alert> alerts = rawJson
                 .apply("Parse", MapElements.into(TypeDescriptor.of(Txn.class)).via(Txn::parse)).setCoder(TxnCoder.of())
                 .apply("EventTime", WithTimestamps.of((Txn t) -> new Instant(t.eventMillis())))
-                .apply("Velocity", Window.<Txn>into(SlidingWindows.of(Duration.standardMinutes(5))
-                                .every(Duration.standardMinutes(1)))
-                        .triggering(AfterWatermark.pastEndOfWindow().withLateFirings(AfterPane.elementCountAtLeast(1)))
-                        .withAllowedLateness(Duration.standardMinutes(10))
-                        .accumulatingFiredPanes())
+                // gateway retries were double-counted: de-duplicate on the payload fingerprint
+                .apply("Fingerprint", MapElements.into(TypeDescriptors.kvs(new TypeDescriptor<Map<String, String>>() {
+                }, TypeDescriptor.of(Txn.class))).via((Txn t) -> KV.of(t.attrs(), t)))
+                .setCoder(KvCoder.of(new AttrsCoder(), TxnCoder.of()))
+                .apply("Dedup", ParDo.of(new DedupFn())).setCoder(TxnCoder.of())
+                .apply("Velocity", Window.into(FixedWindows.of(Duration.standardMinutes(5)))) // 5x cheaper than sliding
                 .apply("Card", MapElements.into(TypeDescriptors.strings()).via(Txn::cardId))
                 .apply("PerCard", Count.perElement())
                 .apply("OverThreshold", Filter.by((KV<String, Long> kv) -> kv.getValue() > THRESHOLD))
                 .apply("ToAlert", ParDo.of(new ToAlert())).setCoder(SerializableCoder.of(Alert.class));
+        alerts.apply("Block", ParDo.of(new BlockFn(cardControl)));
+        return alerts;
+    }
+
+    /** Emits the first occurrence of each fingerprint; forgets it after 24 hours. */
+    static final class DedupFn extends DoFn<KV<Map<String, String>, Txn>, Txn> {
+        private static final long serialVersionUID = 1L;
+
+        @StateId("seen")
+        private final StateSpec<ValueState<Boolean>> seen = StateSpecs.value(BooleanCoder.of());
+
+        @TimerId("expiry")
+        private final TimerSpec expiry = TimerSpecs.timer(TimeDomain.EVENT_TIME);
+
+        @ProcessElement
+        public void process(@Element KV<Map<String, String>, Txn> e, @Timestamp Instant ts,
+                            @StateId("seen") ValueState<Boolean> seen, @TimerId("expiry") Timer expiry,
+                            OutputReceiver<Txn> out) {
+            if (seen.read() != null) {
+                return;
+            }
+            seen.write(true);
+            expiry.withOutputTimestamp(ts).set(ts.plus(Duration.standardHours(24))); // keep the event's time
+            out.output(e.getValue());
+        }
+
+        @OnTimer("expiry")
+        public void onExpiry(@StateId("seen") ValueState<Boolean> seen) {
+            seen.clear();
+        }
+    }
+
+    /** Fingerprint coder: entry count, then key/value pairs. */
+    static final class AttrsCoder extends CustomCoder<Map<String, String>> {
+        private static final long serialVersionUID = 1L;
+
+        @Override
+        public void encode(Map<String, String> attrs, OutputStream out) throws IOException {
+            VarIntCoder.of().encode(attrs.size(), out);
+            for (Map.Entry<String, String> e : attrs.entrySet()) {
+                StringUtf8Coder.of().encode(e.getKey(), out);
+                StringUtf8Coder.of().encode(e.getValue(), out);
+            }
+        }
+
+        @Override
+        public Map<String, String> decode(InputStream in) throws IOException {
+            int n = VarIntCoder.of().decode(in);
+            Map<String, String> attrs = new LinkedHashMap<>();
+            for (int i = 0; i < n; i++) {
+                attrs.put(StringUtf8Coder.of().decode(in), StringUtf8Coder.of().decode(in));
+            }
+            return attrs;
+        }
+
+        @Override
+        public void verifyDeterministic() {
+            // a flat map of strings: deterministic
+        }
     }
 
     static final class ToAlert extends DoFn<KV<String, Long>, Alert> {
@@ -49,4 +124,18 @@ public final class VelocityPipeline {
             out.output(new Alert(kv.getKey(), window.maxTimestamp().getMillis() + 1, kv.getValue()));
         }
     }
+
+    static final class BlockFn extends DoFn<Alert, Void> {
+        private static final long serialVersionUID = 1L;
+        private final CardControl cardControl;
+
+        BlockFn(CardControl cardControl) {
+            this.cardControl = cardControl;
+        }
+
+        @ProcessElement
+        public void process(@Element Alert alert) {
+            cardControl.block(alert.cardId(), "velocity");
+        }
+    }
 }
diff --git a/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java b/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java
index 10edd9e..2b2097d 100644
--- a/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java
+++ b/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java
@@ -1,24 +1,51 @@
 package com.acme.fraud;
 
-import static org.junit.jupiter.api.Assertions.assertFalse;
+import static org.junit.jupiter.api.Assertions.assertEquals;
+import static org.junit.jupiter.api.Assertions.assertTrue;
 
+import java.util.ArrayList;
+import java.util.List;
 import org.apache.beam.sdk.Pipeline;
 import org.apache.beam.sdk.transforms.Create;
 import org.apache.beam.sdk.transforms.ParDo;
 import org.apache.beam.sdk.values.TimestampedValue;
+import org.joda.time.Instant;
 import org.junit.jupiter.api.Test;
 
 class VelocityPipelineTest {
-    @Test
-    void alertsOnFourInFiveMinutes() {
+    private static List<String> run(String... json) {
         Pipeline p = Beam.pipeline();
-        VelocityPipeline.expand(p.apply(Create.timestamped(
-                        TimestampedValue.of(Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false), Beam.at(1, 0)),
-                        TimestampedValue.of(Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false), Beam.at(2, 0)),
-                        TimestampedValue.of(Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false), Beam.at(3, 0)),
-                        TimestampedValue.of(Beam.txn("t4", "c1", 100, Beam.at(4, 0), "m4", false), Beam.at(4, 0)))))
+        List<TimestampedValue<String>> values = new ArrayList<>();
+        for (String j : json) {
+            values.add(TimestampedValue.of(j, new Instant(Txn.parse(j).eventMillis())));
+        }
+        VelocityPipeline.expand(p.apply(Create.timestamped(values)), new Beam.FakeCardControl())
                 .apply(ParDo.of(new Beam.Log<>("alert")));
         p.run().waitUntilFinish();
-        assertFalse(Beam.logged("alert:Alert[cardId=c1").isEmpty());
+        return Beam.logged("alert:");
+    }
+
+    @Test
+    void alertsAndBlocksOnFourInFiveMinutes() {
+        List<String> alerts = run(Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false),
+                Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
+                Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false),
+                Beam.txn("t4", "c1", 100, Beam.at(4, 0), "m4", false));
+        assertEquals(1, alerts.size());
+        assertEquals(List.of("c1"), Beam.FakeCardControl.blockedCards());
+    }
+
+    @Test
+    void threeIsNotEnough() {
+        assertTrue(run(Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false),
+                Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
+                Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false)).isEmpty());
+    }
+
+    @Test
+    void gatewayRetriesAreCountedOnce() {
+        String t1 = Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false);
+        assertTrue(run(t1, t1, Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
+                Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false)).isEmpty());
     }
 }
```

---

## 4. The author's tests: green

```text
├─ JUnit Jupiter ✔
│  └─ VelocityPipelineTest ✔
│     ├─ gatewayRetriesAreCountedOnce() ✔
│     ├─ alertsAndBlocksOnFourInFiveMinutes() ✔
│     └─ threeIsNotEnough() ✔
[         3 tests found           ]
[         3 tests successful      ]
[         0 tests failed          ]
```

All inputs are bounded (`Create`), so the watermark jumps to infinity at the end and every window fires. A 24-hour watermark hold is invisible. Retries in the test are byte-identical strings, and the DirectRunner normalizes attribute order anyway. Every alerting card uses distinct merchants, so fingerprint dedup never merges legitimate transactions. Only one card alerts, so a shared idempotency key never collides. `alertsAndBlocksOnFourInFiveMinutes` asserts *exactly one* alert, a property of fixed windows, and is the one test that fails against the fix (sliding windows emit one alert per overlapping window, and blocking is de-duplicated per card-hour instead).

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** event identity (dedup key), key encoding (a new coder), the time model (timer output timestamps, windows, lateness, timestamp source), and an external side effect (card blocking).
- **Hunk scores:** `expand` 8/8, `DedupFn` 8/8, `AttrsCoder` 6/8, `BlockFn` 6/8, `Txn.parse` 6/8.
- **Radar hits:** `verifyDeterministic() { }` on a `Map` coder (114). `attrs.entrySet()` in `encode` (97). `KV.of(t.attrs(), t)` as the dedup key (49–50). `withOutputTimestamp(ts)` on a 24 h timer (80). `FixedWindows` replacing `SlidingWindows`, with the trigger/lateness lines deleted (53). `"velocity"` as an idempotency key (138). `System.currentTimeMillis()` as event time (Txn 20).

### Minute 10: one hop each

- Gateway contract §4.2 says retries reuse `txnId`. So the fingerprint isn't needed, *and* it merges distinct identical-looking transactions: card-testing bursts are identical by construction. F2.
- Do equal fingerprint maps encode equally? Not if field order differs, and gateway versions differ in field order. F1.
- What does `withOutputTimestamp(ts)` on a 24 h timer do to the output watermark? It holds it at `ts` for 24 h. F3.
- Which bursts do fixed windows miss? Any that straddle a :05 boundary. F4.
- What happens to a 4-minute-late mobile authorization? With the lateness lines deleted, it would be dropped. Today F3's hold hides that, so this is F5.
- Two cards alert. What does card-control do with the second `"velocity"` key? It treats it as a replay. F6.
- Replaying an archive containing legacy POS events puts them at the replay time. F7.

### Minute 20: prove, unify, fix

- **Unify:** F1 and F2 are one decision (the dedup identity) failing in opposite directions: equal events split, distinct events merged. F3, F5 and F7 are one model (event time) violated three ways. F4 is a requirements mismatch. F6 is an idempotency-key design error.
- **Masking:** F3 masks F5. Fixing only F3 makes late data start disappearing, so the fix must restore lateness in the same change.
- **Fix shape:** key by `txnId` with `StringUtf8Coder`; no `withOutputTimestamp` on the cleanup timer; `SlidingWindows(5 min, every 1 min)` with 10 min allowed lateness, late firings and accumulating panes; idempotency key `velocity:<card>:<hour>`; reject events without `ts` (dead-letter in production).

---

## 6. The L7 answer key, line by line

Line numbers are within `VelocityPipeline.java` and `Txn.java` on the `+` side.

### F1 · L5 · Sev-2 · `AttrsCoder` claims determinism but encodes map iteration order (91–116; key at 49–51)

**Mechanism.** The fingerprint is the attribute `LinkedHashMap` in JSON field order, and `AttrsCoder.encode` writes entries in iteration order. Two gateway versions serialize the same retry with fields in different orders, giving equal maps (`equals()` is true) with different bytes. The runner groups state by encoded key bytes, so the retry lands in a different key and is counted again. The empty `verifyDeterministic()` silences exactly the check Beam would otherwise run. On the DirectRunner the bug hides, because elements are round-tripped through `TxnCoder` (which sorts attributes) between `Parse` and `Fingerprint`. On a fusing runner the original map flows through by reference.

**Evidence.** P1 runs with elements passed by reference between steps (`enforceEncodability=false`, as fused stages do): `3 real authorizations + 1 gateway retry … -> cards alerted: [c1] (expected [])`, a false fraud block. Fix: `[]`.

```comment-l7
issue (blocking): AttrsCoder declares itself deterministic but writes entries in map iteration order

Equal fingerprints from two gateway versions (same fields, different JSON order) encode to different bytes, and the runner groups state by those bytes, which means a retry is counted as a new authorization. The empty verifyDeterministic() on line 114 suppresses the check Beam would run. The DirectRunner hides it by re-encoding elements with TxnCoder (sorted) between steps; with by-reference passing, as on Dataflow's fused stages, the P1 probe raises a false alert. Suggest keying on txnId with StringUtf8Coder (see the next comment), or at minimum encoding entries in sorted key order and removing the override.
```

**Fix.**
```java
                .apply("ByTxnId", MapElements.into(TypeDescriptors.kvs(TypeDescriptors.strings(), TypeDescriptor.of(Txn.class)))
                        .via((Txn t) -> KV.of(t.txnId(), t))) // retries reuse txnId (gateway contract v3, 4.2)
                .setCoder(KvCoder.of(StringUtf8Coder.of(), TxnCoder.of()))
```

### F2 · L1 · Sev-1 · De-duplicating on content merges distinct transactions, including card-testing attacks (48–51)

**Mechanism.** The fingerprint is everything except `txnId` and `ts`: card, amount, merchant, terminal. Card-testing attacks send many *identical* small authorizations at one merchant to validate stolen cards. To this dedup they are one event, so the velocity rule built to catch them can never fire. The premise is also false: gateway contract v3 §4.2 says retries reuse `txnId`.

**Evidence.** P2: `card-testing burst: 6 distinct $1.00 authorizations, same merchant, 50 s -> cards alerted: [] (expected [c9])`. Fix: `[c9]`.

```comment-l7
issue (blocking): de-duplicating on the payload fingerprint collapses distinct identical-looking authorizations, so card-testing bursts never alert

Card testing is exactly N identical small authorizations; with the fingerprint key (lines 48-51) they become one event, which means velocity can't fire on the attack it exists to catch (P2 probe: 6 distinct $1.00 authorizations, no alert). The gateway contract (v3 section 4.2) says retries reuse txnId, so I'd suggest de-duplicating on txnId: that removes retries without merging real transactions. If some gateway truly re-mints ids, let's handle that gateway explicitly rather than weaken identity for all.
```

**Fix.** The same `ByTxnId` key as F1.

### F3 · L4 · Sev-1 · The cleanup timer's output timestamp holds the watermark for 24 hours: every alert fires a day late (80)

**Mechanism.** `expiry.withOutputTimestamp(ts).set(ts + 24h)` asks Beam to hold `DedupFn`'s output watermark at `ts`, the element's own timestamp, until the timer fires 24 hours of event time later. Downstream windows close only when the watermark passes their end, so no velocity window can fire for a day. Nothing is lost, and every alert is useless. Bounded tests jump the watermark to infinity at the end, which releases every hold at once and hides the delay.

**Evidence.** P3 (TestStream: a 4-authorization burst at 1:00–4:00, then the watermark advanced to 10:00, then the next input): `the alert fired only after the next input, when the watermark reached +infinity`. Fix: `fired at once (before the next input)`.

```comment-l7
issue (blocking): withOutputTimestamp(ts) on the 24 h cleanup timer holds the output watermark at the element's time for 24 hours

Per the Beam programming guide, a timer holds the ParDo's output watermark at its output timestamp, and line 80 sets that to the element's timestamp on a timer that fires a day later. This means no downstream window can close for 24 hours, so every velocity alert arrives a day late. In the P3 probe the watermark passes 10:00 and the 1:00-4:00 burst still doesn't alert until the watermark reaches infinity. The bounded tests can't see this because their watermark jumps to infinity at the end. Suggest dropping withOutputTimestamp: the timer only clears state and emits nothing.
```

**Fix.**
```java
            expiry.set(ts.plus(Duration.standardHours(24))); // no output timestamp: the timer emits nothing
```

### F4 · L1 · Sev-2 · Fixed windows miss bursts that straddle a boundary (53)

**Mechanism.** The rule is "more than 3 authorizations in any 5-minute span." `FixedWindows.of(5 min)` only checks [0:00–5:00), [5:00–10:00), …, so 5 authorizations between 4:00 and 5:40 split 3 + 2 and never alert. Fraudsters don't align to the clock. The 5× cost saving comes from answering a different question.

**Evidence.** P4: `5 authorizations in 1 min 40 s straddling the 5:00 boundary -> cards alerted: [] (expected [c2])`. Fix: `[c2]`.

```comment-l7
issue (blocking): FixedWindows only evaluates clock-aligned spans, so a burst across a boundary is split and missed

The rule is "more than 3 in any 5 minutes"; fixed windows split a 4:00-5:40 burst into 3 + 2, which means no alert (P4 probe: 5 authorizations in 1 min 40 s, no alert). Suggest keeping SlidingWindows(5 min, every 1 min). If the cost matters, a stateful per-card DoFn with a 5-minute ring of timestamps answers the same question with one state cell per card instead of five window assignments per event.
```

**Fix.**
```java
                .apply("Velocity", Window.<Txn>into(SlidingWindows.of(Duration.standardMinutes(5))
                                .every(Duration.standardMinutes(1))) // a burst straddling a boundary still fits one window
```

### F5 · L4 · Sev-2 · Allowed lateness deleted: late authorizations will be dropped, *once F3 is fixed* (53; removed lines)

**Mechanism.** The before-code had `withAllowedLateness(10 min)`, late firings and accumulating panes, because mobile authorizations arrive minutes late. The PR's `Window.into(FixedWindows…)` drops all three, so late elements beyond the watermark are discarded. *Today* that is invisible: F3's hold keeps the downstream watermark at the earliest pending dedup timer, so nothing is ever "late." Fix F3 alone and late authorizations start disappearing silently. A reviewer who fixes one finding and not the other ships a new bug.

**Evidence.** P5 on the PR: `-> cards alerted: [c6]`, masked by the hold. P5b runs the same windowing without the hold and shows Beam's default behavior: `counts [count:1] for [0:00, 5:00) -> the late element is dropped`. Fix: `[c6]` via a late firing.

```comment-l7
issue (blocking): the deleted withAllowedLateness/late-firing lines mean late authorizations get dropped, currently hidden by the watermark hold

Line 53 replaces the windowing with defaults, under which elements later than the watermark are discarded, which means late mobile authorizations will vanish; mobile authorizations routinely arrive minutes late. Today the 24 h hold (previous comment) means nothing is late downstream, so the P5 probe still alerts, but as soon as the hold is fixed the same input drops the late event (P5b shows Beam's default dropping it). Suggest restoring allowed lateness (10 min), late firings and accumulating panes in the same change as the hold fix.
```

**Fix.**
```java
                        .triggering(AfterWatermark.pastEndOfWindow().withLateFirings(AfterPane.elementCountAtLeast(1)))
                        .withAllowedLateness(Duration.standardMinutes(10)) // mobile authorizations arrive late
                        .accumulatingFiredPanes())
```

### F6 · L3/L6 · Sev-1 · A constant idempotency key: after the first block, card-control treats every other card's block as a replay (138)

**Mechanism.** card-control-service is idempotent *per key* for 24 h, which is the right design for retried bundles. But `BlockFn` sends the same key, `"velocity"`, for every card. The first block of the day succeeds, and every later card's block is a "replay" of it and does nothing. Fraud keeps flowing on cards the pipeline believes it blocked.

**Evidence.** P6: `cards c1 and c4 both over threshold -> cards actually blocked by card-control: 1 of 2`. Fix: `2 of 2`.

```comment-l7
issue (blocking): every block uses the idempotency key "velocity", so card-control drops all blocks after the first as replays

card-control treats a repeated key as a replay for 24 h, and line 138 sends the same key for every card, which means only the first card each day is actually blocked (P6 probe: 2 cards alerted, 1 blocked). Suggest a key that identifies the action: "velocity:<card>:<hour>" collapses the duplicates we do expect (bundle retries, overlapping sliding windows, late firings) without merging different cards.
```

**Fix.**
```java
            long hour = alert.windowEndMillis() / Duration.standardHours(1).getMillis();
            cardControl.block(alert.cardId(), "velocity:" + alert.cardId() + ":" + hour);
```

### F7 · L4 · Sev-2 · Processing time used as event time for events without `ts` (Txn 20)

**Mechanism.** `System.currentTimeMillis()` makes an event's window depend on *when the pipeline read it*. On a replay after an incident, the legacy POS events from yesterday land in today's windows, merge with today's traffic, and produce alerts that never happened, or miss real ones. Two runs over the same archive disagree. It also interacts with F3: those events carry "now" timestamps far ahead of the real stream.

**Evidence.** P7: `the same event without ts, parsed twice 50 ms apart -> event times differ by >= 50 ms`. Fix: `rejected`.

```comment-l7
issue (blocking): events without ts get the wall-clock time, so results depend on when the pipeline runs

Line 20 stamps processing time as event time, which means a replay from the archive assigns yesterday's POS events to today's windows (P7 probe: the same bytes get different event times 50 ms apart). Suggest rejecting them to a dead-letter output and asking the POS gateway team for ts; if we must accept them, use an upstream ingestion timestamp that is stored with the event, so replays are deterministic.
```

**Fix.**
```java
        if (ts == null) {
            throw new IllegalArgumentException("txn without ts: " + json);
        }
```
```java
            try {
                out.output(Txn.parse(json));
            } catch (IllegalArgumentException e) {
                rejected.inc();
            }
```

### T1 · Tests

`alertsAndBlocksOnFourInFiveMinutes` asserts exactly one alert, which encodes fixed-window semantics. The requirement is "the card is blocked once," and the fixed suite asserts that through the idempotency keys. More importantly, every author test uses bounded input. Beam watermark behavior needs `TestStream`: advance the watermark, assert what has fired, then add late data.

```comment-l7
todo (blocking): bounded-input tests cannot observe watermark behavior; the hold and the lateness change need TestStream tests

With Create, the watermark jumps to infinity at the end, which means a 24 h hold and dropped late data both look fine. Suggest a TestStream test that advances the watermark past a window and asserts the alert fired before the next input, plus one with a late element; and asserting "blocked once per card" rather than "exactly one alert".
```

---

## 7. The refactored code

```java
// ===== fraud-pipeline/src/main/java/com/acme/fraud/Txn.java =====
package com.acme.fraud;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** An authorization event from the card gateway. Gateway retries reuse txnId (gateway contract v3, section 4.2). */
public record Txn(String txnId, String cardId, long amountMinor, long eventMillis, Map<String, String> attrs) {
    private static final Pattern FIELD = Pattern.compile("\"(\\w+)\"\\s*:\\s*(?:\"([^\"]*)\"|(-?\\d+))");

    /** {"txnId":..,"card":..,"amount":..,"ts":epochMillis, ..gateway attributes}; attrs keep the JSON field order. */
    public static Txn parse(String json) {
        Map<String, String> f = new LinkedHashMap<>();
        Matcher m = FIELD.matcher(json);
        while (m.find()) {
            f.put(m.group(1), m.group(2) != null ? m.group(2) : m.group(3));
        }
        String ts = f.remove("ts");
        if (ts == null) {
            throw new IllegalArgumentException("txn without ts: " + json);
        }
        String id = f.remove("txnId");
        return new Txn(id, f.get("card"), Long.parseLong(f.get("amount")), Long.parseLong(ts), f);
    }
}

// ===== fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java =====
package com.acme.fraud;

import org.apache.beam.sdk.coders.BooleanCoder;
import org.apache.beam.sdk.coders.KvCoder;
import org.apache.beam.sdk.coders.SerializableCoder;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.metrics.Counter;
import org.apache.beam.sdk.metrics.Metrics;
import org.apache.beam.sdk.state.StateSpec;
import org.apache.beam.sdk.state.StateSpecs;
import org.apache.beam.sdk.state.TimeDomain;
import org.apache.beam.sdk.state.Timer;
import org.apache.beam.sdk.state.TimerSpec;
import org.apache.beam.sdk.state.TimerSpecs;
import org.apache.beam.sdk.state.ValueState;
import org.apache.beam.sdk.transforms.Count;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.Filter;
import org.apache.beam.sdk.transforms.MapElements;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.WithTimestamps;
import org.apache.beam.sdk.transforms.windowing.AfterPane;
import org.apache.beam.sdk.transforms.windowing.AfterWatermark;
import org.apache.beam.sdk.transforms.windowing.BoundedWindow;
import org.apache.beam.sdk.transforms.windowing.SlidingWindows;
import org.apache.beam.sdk.transforms.windowing.Window;
import org.apache.beam.sdk.values.KV;
import org.apache.beam.sdk.values.PCollection;
import org.apache.beam.sdk.values.TypeDescriptor;
import org.apache.beam.sdk.values.TypeDescriptors;
import org.joda.time.Duration;
import org.joda.time.Instant;

/** Card velocity: more than THRESHOLD authorizations on one card within any 5-minute span blocks the card. */
public final class VelocityPipeline {
    static final long THRESHOLD = 3;

    private VelocityPipeline() {
    }

    public static PCollection<Alert> expand(PCollection<String> rawJson, CardControl cardControl) {
        PCollection<Alert> alerts = rawJson
                .apply("Parse", ParDo.of(new ParseFn())).setCoder(TxnCoder.of())
                .apply("EventTime", WithTimestamps.of((Txn t) -> new Instant(t.eventMillis())))
                .apply("ByTxnId", MapElements.into(TypeDescriptors.kvs(TypeDescriptors.strings(), TypeDescriptor.of(Txn.class)))
                        .via((Txn t) -> KV.of(t.txnId(), t))) // retries reuse txnId (gateway contract v3, 4.2)
                .setCoder(KvCoder.of(StringUtf8Coder.of(), TxnCoder.of()))
                .apply("Dedup", ParDo.of(new DedupFn())).setCoder(TxnCoder.of())
                .apply("Velocity", Window.<Txn>into(SlidingWindows.of(Duration.standardMinutes(5))
                                .every(Duration.standardMinutes(1))) // a burst straddling a boundary still fits one window
                        .triggering(AfterWatermark.pastEndOfWindow().withLateFirings(AfterPane.elementCountAtLeast(1)))
                        .withAllowedLateness(Duration.standardMinutes(10)) // mobile authorizations arrive late
                        .accumulatingFiredPanes())
                .apply("Card", MapElements.into(TypeDescriptors.strings()).via(Txn::cardId))
                .apply("PerCard", Count.perElement())
                .apply("OverThreshold", Filter.by((KV<String, Long> kv) -> kv.getValue() > THRESHOLD))
                .apply("ToAlert", ParDo.of(new ToAlert())).setCoder(SerializableCoder.of(Alert.class));
        alerts.apply("Block", ParDo.of(new BlockFn(cardControl)));
        return alerts;
    }

    /** Events without an event time are rejected (production: a dead-letter output), never stamped with now(). */
    static final class ParseFn extends DoFn<String, Txn> {
        private static final long serialVersionUID = 1L;
        private final Counter rejected = Metrics.counter(VelocityPipeline.class, "rejected");

        @ProcessElement
        public void process(@Element String json, OutputReceiver<Txn> out) {
            try {
                out.output(Txn.parse(json));
            } catch (IllegalArgumentException e) {
                rejected.inc();
            }
        }
    }

    /** Emits the first occurrence of each txnId; forgets it 24 hours of event time later. */
    static final class DedupFn extends DoFn<KV<String, Txn>, Txn> {
        private static final long serialVersionUID = 1L;

        @StateId("seen")
        private final StateSpec<ValueState<Boolean>> seen = StateSpecs.value(BooleanCoder.of());

        @TimerId("expiry")
        private final TimerSpec expiry = TimerSpecs.timer(TimeDomain.EVENT_TIME);

        @ProcessElement
        public void process(@Element KV<String, Txn> e, @Timestamp Instant ts, @StateId("seen") ValueState<Boolean> seen,
                            @TimerId("expiry") Timer expiry, OutputReceiver<Txn> out) {
            if (seen.read() != null) {
                return;
            }
            seen.write(true);
            expiry.set(ts.plus(Duration.standardHours(24))); // no output timestamp: the timer emits nothing
            out.output(e.getValue());
        }

        @OnTimer("expiry")
        public void onExpiry(@StateId("seen") ValueState<Boolean> seen) {
            seen.clear();
        }
    }

    static final class ToAlert extends DoFn<KV<String, Long>, Alert> {
        private static final long serialVersionUID = 1L;

        @ProcessElement
        public void process(@Element KV<String, Long> kv, BoundedWindow window, OutputReceiver<Alert> out) {
            out.output(new Alert(kv.getKey(), window.maxTimestamp().getMillis() + 1, kv.getValue()));
        }
    }

    /** At most one block per card per hour: overlapping windows, late firings and bundle retries all collapse. */
    static final class BlockFn extends DoFn<Alert, Void> {
        private static final long serialVersionUID = 1L;
        private final CardControl cardControl;

        BlockFn(CardControl cardControl) {
            this.cardControl = cardControl;
        }

        @ProcessElement
        public void process(@Element Alert alert) {
            long hour = alert.windowEndMillis() / Duration.standardHours(1).getMillis();
            cardControl.block(alert.cardId(), "velocity:" + alert.cardId() + ":" + hour);
        }
    }
}
```

**Fixed suite: 6/6 (output, verified).**

```text
├─ JUnit Jupiter ✔
│  └─ VelocityPipelineTest ✔
│     ├─ retriesInAnyFieldOrderAreCountedOnce() ✔
│     ├─ blocksOnceOnFourInFiveMinutes() ✔
│     ├─ burstAcrossAWindowBoundaryAlerts() ✔
│     ├─ eventsWithoutTimestampAreRejected() ✔
│     ├─ threeIsNotEnough() ✔
│     └─ identicalLookingDistinctTransactionsAllCount() ✔
[         6 tests found           ]
[         6 tests successful      ]
[         0 tests failed          ]
```

**The PR's original tests against the fix (output, verified).** The "exactly one alert" test fails, because overlapping sliding windows each alert, while blocking stays once per card-hour:

```text
├─ JUnit Jupiter ✔
│  └─ VelocityPipelineTest ✔
│     ├─ gatewayRetriesAreCountedOnce() ✔
│     ├─ alertsAndBlocksOnFourInFiveMinutes() ✘ expected: <1> but was: <2>
│     └─ threeIsNotEnough() ✔
[         3 tests found           ]
[         2 tests successful      ]
[         1 tests failed          ]
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Dedup identity | Payload fingerprint (merges card testing) | `txnId` (the gateway's retry identity) |
| Key encoding | Map in iteration order, "deterministic" by fiat | `StringUtf8Coder` |
| Cleanup timer | Output timestamp = element time (24 h watermark hold) | Default (the timer emits nothing) |
| Windows | Fixed 5 min | Sliding 5 min every 1 min |
| Late data | Dropped (masked by the hold) | 10 min allowed lateness, late firings, accumulating panes |
| External action | Constant idempotency key | `velocity:<card>:<hour>` |
| Missing event time | Wall clock | Rejected (dead-letter in production) |

---

## 8. Probe evidence

**Against the PR's code (output, verified):**

```text
PR05 probes against the PR's VelocityPipeline (Beam 2.77 DirectRunner)
P1 F1 3 real authorizations + 1 gateway retry of t1 serialized in another field order, elements passed by reference between fused steps -> cards alerted: [c1] (expected [])
P2 F2 card-testing burst: 6 distinct $1.00 authorizations, same merchant, 50 s -> cards alerted: [] (expected [c9])
P3 F3 watermark advanced to 10:00 after a 4-authorization burst at 1:00-4:00 -> the alert fired only after the next input, when the watermark reached +infinity (held back 24 h by the dedup timer)
P4 F4 5 authorizations in 1 min 40 s straddling the 5:00 boundary -> cards alerted: [] (expected [c2])
P5 F5 4th authorization arrives 4 minutes after the watermark passed its window -> cards alerted: [c6] (expected [c6])
P5b   Beam check, no upstream hold: Window.into(FixedWindows.of(5 min)) with default allowed lateness counts [count:1] for [0:00, 5:00) -> the late element is dropped
P6 F6 cards c1 and c4 both over threshold -> cards actually blocked by card-control: 1 of 2
P7 F7 the same event without ts, parsed twice 50 ms apart -> event times differ by >= 50 ms between two parses of the same bytes
```

**Against the fixed code (output, verified):**

```text
PR05 probes against the fixed VelocityPipeline (Beam 2.77 DirectRunner)
P1 F1 3 real authorizations + 1 gateway retry of t1 serialized in another field order, elements passed by reference between fused steps -> cards alerted: [] (expected [])
P2 F2 card-testing burst: 6 distinct $1.00 authorizations, same merchant, 50 s -> cards alerted: [c9] (expected [c9])
P3 F3 watermark advanced to 10:00 after a 4-authorization burst at 1:00-4:00 -> the alert fired at once (before the next input)
P4 F4 5 authorizations in 1 min 40 s straddling the 5:00 boundary -> cards alerted: [c2] (expected [c2])
P5 F5 4th authorization arrives 4 minutes after the watermark passed its window -> cards alerted: [c6] (expected [c6])
P5b   Beam check, no upstream hold: Window.into(FixedWindows.of(5 min)) with default allowed lateness counts [count:1] for [0:00, 5:00) -> the late element is dropped
P6 F6 cards c1 and c4 both over threshold -> cards actually blocked by card-control: 2 of 2
P7 F7 the same event without ts, parsed twice 50 ms apart -> rejected (txn without ts)
```

<details><summary><b>The probe harness (Pr05Probes.java)</b></summary>

```java
package com.acme.fraud;

import java.util.ArrayList;
import java.util.List;
import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.testing.TestStream;
import org.apache.beam.sdk.transforms.Combine;
import org.apache.beam.sdk.transforms.Count;
import org.apache.beam.sdk.transforms.Create;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.windowing.FixedWindows;
import org.apache.beam.sdk.transforms.windowing.Window;
import org.apache.beam.sdk.values.PCollection;
import org.apache.beam.sdk.values.TimestampedValue;
import org.joda.time.Duration;
import org.joda.time.Instant;

/**
 * Pr05Probes - fraud-shaped probes for PR05 on Beam's DirectRunner. TestStream drives event time explicitly; the
 * DirectRunner processes each TestStream event to quiescence before the next, so the order of entries in the shared
 * log shows *when* (in watermark terms) a window fired.
 */
public final class Pr05Probes {
    private static TimestampedValue<String> tv(String json) {
        return TimestampedValue.of(json, new Instant(Txn.parse(json).eventMillis()));
    }

    /** Runs the pipeline over a bounded input and returns the cards that alerted. */
    private static List<String> alertedCards(String... json) {
        return alertedCards(true, json);
    }

    private static List<String> alertedCards(boolean encodingRoundTrips, String... json) {
        Pipeline p = Beam.pipeline(encodingRoundTrips);
        List<TimestampedValue<String>> values = new ArrayList<>();
        for (String j : json) {
            values.add(tv(j));
        }
        VelocityPipeline.expand(p.apply(Create.timestamped(values)), new Beam.FakeCardControl())
                .apply(ParDo.of(new Beam.Log<>("alert")));
        p.run().waitUntilFinish();
        return Beam.logged("alert:").stream().map(s -> s.replaceAll(".*cardId=(\\w+).*", "$1")).distinct().sorted().toList();
    }

    public static void main(String[] args) {
        System.out.println("PR05 probes against the " + args[0] + " VelocityPipeline (Beam 2.77 DirectRunner)");

        System.out.println("P1 F1 3 real authorizations + 1 gateway retry of t1 serialized in another field order, elements passed"
                + " by reference between fused steps -> cards alerted: "
                + alertedCards(false, Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false),
                Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", true),
                Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
                Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false)) + " (expected [])");

        List<String> burst = new ArrayList<>();
        for (int i = 0; i < 6; i++) {
            burst.add(Beam.txn("ct" + i, "c9", 100, Beam.at(1, 10 * i), "m1", false)); // card testing: identical $1 attempts
        }
        System.out.println("P2 F2 card-testing burst: 6 distinct $1.00 authorizations, same merchant, 50 s -> cards alerted: "
                + alertedCards(burst.toArray(String[]::new)) + " (expected [c9])");

        watermarkHold();

        System.out.println("P4 F4 5 authorizations in 1 min 40 s straddling the 5:00 boundary -> cards alerted: "
                + alertedCards(Beam.txn("b1", "c2", 100, Beam.at(4, 0), "m1", false),
                Beam.txn("b2", "c2", 100, Beam.at(4, 30), "m2", false),
                Beam.txn("b3", "c2", 100, Beam.at(4, 50), "m3", false),
                Beam.txn("b4", "c2", 100, Beam.at(5, 10), "m4", false),
                Beam.txn("b5", "c2", 100, Beam.at(5, 40), "m5", false)) + " (expected [c2])");

        lateData();

        alertedCards(Beam.txn("x1", "c1", 100, Beam.at(1, 0), "m1", false), Beam.txn("x2", "c1", 100, Beam.at(1, 5), "m2", false),
                Beam.txn("x3", "c1", 100, Beam.at(1, 9), "m3", false), Beam.txn("x4", "c1", 100, Beam.at(1, 13), "m4", false),
                Beam.txn("y1", "c4", 100, Beam.at(1, 0), "m1", false), Beam.txn("y2", "c4", 100, Beam.at(1, 5), "m2", false),
                Beam.txn("y3", "c4", 100, Beam.at(1, 9), "m3", false), Beam.txn("y4", "c4", 100, Beam.at(1, 13), "m4", false));
        System.out.println("P6 F6 cards c1 and c4 both over threshold -> cards actually blocked by card-control: "
                + Beam.FakeCardControl.blockedCards().size() + " of 2");

        String noTs = "{\"txnId\":\"p1\",\"card\":\"c5\",\"amount\":100,\"merchant\":\"m1\"}";
        String parsed;
        try {
            long a = Txn.parse(noTs).eventMillis();
            sleep(50);
            long b = Txn.parse(noTs).eventMillis();
            parsed = "event times differ by " + ((b - a) / 50 >= 1 ? ">= 50" : "< 50") + " ms between two parses of the same bytes";
        } catch (IllegalArgumentException e) {
            parsed = "rejected (" + e.getMessage().replaceAll(":.*", "") + ")";
        }
        System.out.println("P7 F7 the same event without ts, parsed twice 50 ms apart -> " + parsed);
    }

    static void watermarkHold() {
        Pipeline p = Beam.pipeline();
        TestStream<String> events = TestStream.create(StringUtf8Coder.of())
                .addElements(tv(Beam.txn("w1", "c3", 100, Beam.at(1, 0), "m1", false)),
                        tv(Beam.txn("w2", "c3", 100, Beam.at(2, 0), "m2", false)),
                        tv(Beam.txn("w3", "c3", 100, Beam.at(3, 0), "m3", false)),
                        tv(Beam.txn("w4", "c3", 100, Beam.at(4, 0), "m4", false)))
                .advanceWatermarkTo(Beam.at(10, 0)) // the window [0:00, 5:00) is complete
                .addElements(tv(Beam.txn("next", "zz", 100, Beam.at(11, 0), "m9", false)))
                .advanceWatermarkToInfinity();
        PCollection<String> raw = p.apply(events);
        raw.apply("TapInput", ParDo.of(new Beam.Log<>("in")));
        VelocityPipeline.expand(raw, new Beam.FakeCardControl()).apply(ParDo.of(new Beam.Log<>("alert")));
        p.run().waitUntilFinish();
        List<String> log = new ArrayList<>(Beam.LOG);
        int alertAt = indexOf(log, "alert:");
        int nextAt = indexOf(log, "in:{\"txnId\":\"next\"");
        System.out.println("P3 F3 watermark advanced to 10:00 after a 4-authorization burst at 1:00-4:00 -> the alert fired "
                + (alertAt >= 0 && alertAt < nextAt ? "at once (before the next input)"
                : "only after the next input, when the watermark reached +infinity (held back 24 h by the dedup timer)"));
    }

    static void lateData() {
        Pipeline p = Beam.pipeline();
        TestStream<String> events = TestStream.create(StringUtf8Coder.of())
                .addElements(tv(Beam.txn("l1", "c6", 100, Beam.at(1, 0), "m1", false)),
                        tv(Beam.txn("l2", "c6", 100, Beam.at(2, 0), "m2", false)),
                        tv(Beam.txn("l3", "c6", 100, Beam.at(3, 0), "m3", false)))
                .advanceWatermarkTo(Beam.at(8, 0))
                .addElements(tv(Beam.txn("l4", "c6", 100, Beam.at(4, 0), "m4", false))) // a mobile auth arriving 4 min late
                .advanceWatermarkToInfinity();
        VelocityPipeline.expand(p.apply(events), new Beam.FakeCardControl()).apply(ParDo.of(new Beam.Log<>("alert")));
        p.run().waitUntilFinish();
        System.out.println("P5 F5 4th authorization arrives 4 minutes after the watermark passed its window -> cards alerted: "
                + Beam.logged("alert:").stream().map(s -> s.replaceAll(".*cardId=(\\w+).*", "$1")).distinct().toList()
                + " (expected [c6])");
        // Beam semantics the PR relies on, without the PR's upstream hold: default allowed lateness drops late data.
        Pipeline q = Beam.pipeline();
        TestStream<String> s = TestStream.create(StringUtf8Coder.of())
                .addElements(TimestampedValue.of("on-time", Beam.at(1, 0)))
                .advanceWatermarkTo(Beam.at(8, 0))
                .addElements(TimestampedValue.of("late", Beam.at(4, 0)))
                .advanceWatermarkToInfinity();
        q.apply(s).apply(Window.into(FixedWindows.of(Duration.standardMinutes(5))))
                .apply(Combine.globally(Count.<String>combineFn()).withoutDefaults())
                .apply(ParDo.of(new Beam.Log<>("count")));
        q.run().waitUntilFinish();
        System.out.println("P5b   Beam check, no upstream hold: Window.into(FixedWindows.of(5 min)) with default allowed lateness"
                + " counts " + Beam.logged("count:") + " for [0:00, 5:00) -> the late element is dropped");
    }

    private static int indexOf(List<String> log, String prefix) {
        for (int i = 0; i < log.size(); i++) {
            if (log.get(i).startsWith(prefix)) {
                return i;
            }
        }
        return -1;
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java b/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java
index 76f02b4..cd26e73 100644
--- a/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java
+++ b/fraud-pipeline/src/main/java/com/acme/fraud/Txn.java
@@ -17,8 +17,10 @@ public record Txn(String txnId, String cardId, long amountMinor, long eventMilli
             f.put(m.group(1), m.group(2) != null ? m.group(2) : m.group(3));
         }
         String ts = f.remove("ts");
-        long eventMillis = ts != null ? Long.parseLong(ts) : System.currentTimeMillis(); // legacy POS gateway omits ts
+        if (ts == null) {
+            throw new IllegalArgumentException("txn without ts: " + json);
+        }
         String id = f.remove("txnId");
-        return new Txn(id, f.get("card"), Long.parseLong(f.get("amount")), eventMillis, f);
+        return new Txn(id, f.get("card"), Long.parseLong(f.get("amount")), Long.parseLong(ts), f);
     }
 }
diff --git a/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java b/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java
index a6b08b1..aff638d 100644
--- a/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java
+++ b/fraud-pipeline/src/main/java/com/acme/fraud/VelocityPipeline.java
@@ -1,16 +1,11 @@
 package com.acme.fraud;
 
-import java.io.IOException;
-import java.io.InputStream;
-import java.io.OutputStream;
-import java.util.LinkedHashMap;
-import java.util.Map;
 import org.apache.beam.sdk.coders.BooleanCoder;
-import org.apache.beam.sdk.coders.CustomCoder;
 import org.apache.beam.sdk.coders.KvCoder;
 import org.apache.beam.sdk.coders.SerializableCoder;
 import org.apache.beam.sdk.coders.StringUtf8Coder;
-import org.apache.beam.sdk.coders.VarIntCoder;
+import org.apache.beam.sdk.metrics.Counter;
+import org.apache.beam.sdk.metrics.Metrics;
 import org.apache.beam.sdk.state.StateSpec;
 import org.apache.beam.sdk.state.StateSpecs;
 import org.apache.beam.sdk.state.TimeDomain;
@@ -24,8 +19,10 @@ import org.apache.beam.sdk.transforms.Filter;
 import org.apache.beam.sdk.transforms.MapElements;
 import org.apache.beam.sdk.transforms.ParDo;
 import org.apache.beam.sdk.transforms.WithTimestamps;
+import org.apache.beam.sdk.transforms.windowing.AfterPane;
+import org.apache.beam.sdk.transforms.windowing.AfterWatermark;
 import org.apache.beam.sdk.transforms.windowing.BoundedWindow;
-import org.apache.beam.sdk.transforms.windowing.FixedWindows;
+import org.apache.beam.sdk.transforms.windowing.SlidingWindows;
 import org.apache.beam.sdk.transforms.windowing.Window;
 import org.apache.beam.sdk.values.KV;
 import org.apache.beam.sdk.values.PCollection;
@@ -34,7 +31,7 @@ import org.apache.beam.sdk.values.TypeDescriptors;
 import org.joda.time.Duration;
 import org.joda.time.Instant;
 
-/** Card velocity: more than THRESHOLD authorizations on one card within 5 minutes blocks the card. */
+/** Card velocity: more than THRESHOLD authorizations on one card within any 5-minute span blocks the card. */
 public final class VelocityPipeline {
     static final long THRESHOLD = 3;
 
@@ -43,14 +40,17 @@ public final class VelocityPipeline {
 
     public static PCollection<Alert> expand(PCollection<String> rawJson, CardControl cardControl) {
         PCollection<Alert> alerts = rawJson
-                .apply("Parse", MapElements.into(TypeDescriptor.of(Txn.class)).via(Txn::parse)).setCoder(TxnCoder.of())
+                .apply("Parse", ParDo.of(new ParseFn())).setCoder(TxnCoder.of())
                 .apply("EventTime", WithTimestamps.of((Txn t) -> new Instant(t.eventMillis())))
-                // gateway retries were double-counted: de-duplicate on the payload fingerprint
-                .apply("Fingerprint", MapElements.into(TypeDescriptors.kvs(new TypeDescriptor<Map<String, String>>() {
-                }, TypeDescriptor.of(Txn.class))).via((Txn t) -> KV.of(t.attrs(), t)))
-                .setCoder(KvCoder.of(new AttrsCoder(), TxnCoder.of()))
+                .apply("ByTxnId", MapElements.into(TypeDescriptors.kvs(TypeDescriptors.strings(), TypeDescriptor.of(Txn.class)))
+                        .via((Txn t) -> KV.of(t.txnId(), t))) // retries reuse txnId (gateway contract v3, 4.2)
+                .setCoder(KvCoder.of(StringUtf8Coder.of(), TxnCoder.of()))
                 .apply("Dedup", ParDo.of(new DedupFn())).setCoder(TxnCoder.of())
-                .apply("Velocity", Window.into(FixedWindows.of(Duration.standardMinutes(5)))) // 5x cheaper than sliding
+                .apply("Velocity", Window.<Txn>into(SlidingWindows.of(Duration.standardMinutes(5))
+                                .every(Duration.standardMinutes(1))) // a burst straddling a boundary still fits one window
+                        .triggering(AfterWatermark.pastEndOfWindow().withLateFirings(AfterPane.elementCountAtLeast(1)))
+                        .withAllowedLateness(Duration.standardMinutes(10)) // mobile authorizations arrive late
+                        .accumulatingFiredPanes())
                 .apply("Card", MapElements.into(TypeDescriptors.strings()).via(Txn::cardId))
                 .apply("PerCard", Count.perElement())
                 .apply("OverThreshold", Filter.by((KV<String, Long> kv) -> kv.getValue() > THRESHOLD))
@@ -59,8 +59,23 @@ public final class VelocityPipeline {
         return alerts;
     }
 
-    /** Emits the first occurrence of each fingerprint; forgets it after 24 hours. */
-    static final class DedupFn extends DoFn<KV<Map<String, String>, Txn>, Txn> {
+    /** Events without an event time are rejected (production: a dead-letter output), never stamped with now(). */
+    static final class ParseFn extends DoFn<String, Txn> {
+        private static final long serialVersionUID = 1L;
+        private final Counter rejected = Metrics.counter(VelocityPipeline.class, "rejected");
+
+        @ProcessElement
+        public void process(@Element String json, OutputReceiver<Txn> out) {
+            try {
+                out.output(Txn.parse(json));
+            } catch (IllegalArgumentException e) {
+                rejected.inc();
+            }
+        }
+    }
+
+    /** Emits the first occurrence of each txnId; forgets it 24 hours of event time later. */
+    static final class DedupFn extends DoFn<KV<String, Txn>, Txn> {
         private static final long serialVersionUID = 1L;
 
         @StateId("seen")
@@ -70,14 +85,13 @@ public final class VelocityPipeline {
         private final TimerSpec expiry = TimerSpecs.timer(TimeDomain.EVENT_TIME);
 
         @ProcessElement
-        public void process(@Element KV<Map<String, String>, Txn> e, @Timestamp Instant ts,
-                            @StateId("seen") ValueState<Boolean> seen, @TimerId("expiry") Timer expiry,
-                            OutputReceiver<Txn> out) {
+        public void process(@Element KV<String, Txn> e, @Timestamp Instant ts, @StateId("seen") ValueState<Boolean> seen,
+                            @TimerId("expiry") Timer expiry, OutputReceiver<Txn> out) {
             if (seen.read() != null) {
                 return;
             }
             seen.write(true);
-            expiry.withOutputTimestamp(ts).set(ts.plus(Duration.standardHours(24))); // keep the event's time
+            expiry.set(ts.plus(Duration.standardHours(24))); // no output timestamp: the timer emits nothing
             out.output(e.getValue());
         }
 
@@ -87,35 +101,6 @@ public final class VelocityPipeline {
         }
     }
 
-    /** Fingerprint coder: entry count, then key/value pairs. */
-    static final class AttrsCoder extends CustomCoder<Map<String, String>> {
-        private static final long serialVersionUID = 1L;
-
-        @Override
-        public void encode(Map<String, String> attrs, OutputStream out) throws IOException {
-            VarIntCoder.of().encode(attrs.size(), out);
-            for (Map.Entry<String, String> e : attrs.entrySet()) {
-                StringUtf8Coder.of().encode(e.getKey(), out);
-                StringUtf8Coder.of().encode(e.getValue(), out);
-            }
-        }
-
-        @Override
-        public Map<String, String> decode(InputStream in) throws IOException {
-            int n = VarIntCoder.of().decode(in);
-            Map<String, String> attrs = new LinkedHashMap<>();
-            for (int i = 0; i < n; i++) {
-                attrs.put(StringUtf8Coder.of().decode(in), StringUtf8Coder.of().decode(in));
-            }
-            return attrs;
-        }
-
-        @Override
-        public void verifyDeterministic() {
-            // a flat map of strings: deterministic
-        }
-    }
-
     static final class ToAlert extends DoFn<KV<String, Long>, Alert> {
         private static final long serialVersionUID = 1L;
 
@@ -125,6 +110,7 @@ public final class VelocityPipeline {
         }
     }
 
+    /** At most one block per card per hour: overlapping windows, late firings and bundle retries all collapse. */
     static final class BlockFn extends DoFn<Alert, Void> {
         private static final long serialVersionUID = 1L;
         private final CardControl cardControl;
@@ -135,7 +121,8 @@ public final class VelocityPipeline {
 
         @ProcessElement
         public void process(@Element Alert alert) {
-            cardControl.block(alert.cardId(), "velocity");
+            long hour = alert.windowEndMillis() / Duration.standardHours(1).getMillis();
+            cardControl.block(alert.cardId(), "velocity:" + alert.cardId() + ":" + hour);
         }
     }
 }
diff --git a/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java b/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java
index 2b2097d..7c54410 100644
--- a/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java
+++ b/fraud-pipeline/src/test/java/com/acme/fraud/VelocityPipelineTest.java
@@ -1,6 +1,7 @@
 package com.acme.fraud;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
+import static org.junit.jupiter.api.Assertions.assertThrows;
 import static org.junit.jupiter.api.Assertions.assertTrue;
 
 import java.util.ArrayList;
@@ -26,13 +27,11 @@ class VelocityPipelineTest {
     }
 
     @Test
-    void alertsAndBlocksOnFourInFiveMinutes() {
-        List<String> alerts = run(Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false),
-                Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
-                Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false),
-                Beam.txn("t4", "c1", 100, Beam.at(4, 0), "m4", false));
-        assertEquals(1, alerts.size());
+    void blocksOnceOnFourInFiveMinutes() {
+        run(Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false), Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
+                Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false), Beam.txn("t4", "c1", 100, Beam.at(4, 0), "m4", false));
         assertEquals(List.of("c1"), Beam.FakeCardControl.blockedCards());
+        assertEquals(1, Beam.FakeCardControl.BY_KEY.size());
     }
 
     @Test
@@ -43,9 +42,31 @@ class VelocityPipelineTest {
     }
 
     @Test
-    void gatewayRetriesAreCountedOnce() {
-        String t1 = Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false);
-        assertTrue(run(t1, t1, Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
+    void retriesInAnyFieldOrderAreCountedOnce() {
+        assertTrue(run(Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", false),
+                Beam.txn("t1", "c1", 100, Beam.at(1, 0), "m1", true),
+                Beam.txn("t2", "c1", 100, Beam.at(2, 0), "m2", false),
                 Beam.txn("t3", "c1", 100, Beam.at(3, 0), "m3", false)).isEmpty());
     }
+
+    @Test
+    void identicalLookingDistinctTransactionsAllCount() {
+        assertTrue(!run(Beam.txn("a1", "c9", 100, Beam.at(1, 0), "m1", false),
+                Beam.txn("a2", "c9", 100, Beam.at(1, 10), "m1", false),
+                Beam.txn("a3", "c9", 100, Beam.at(1, 20), "m1", false),
+                Beam.txn("a4", "c9", 100, Beam.at(1, 30), "m1", false)).isEmpty());
+    }
+
+    @Test
+    void burstAcrossAWindowBoundaryAlerts() {
+        assertTrue(!run(Beam.txn("b1", "c2", 100, Beam.at(4, 0), "m1", false),
+                Beam.txn("b2", "c2", 100, Beam.at(4, 30), "m2", false),
+                Beam.txn("b3", "c2", 100, Beam.at(5, 10), "m3", false),
+                Beam.txn("b4", "c2", 100, Beam.at(5, 40), "m4", false)).isEmpty());
+    }
+
+    @Test
+    void eventsWithoutTimestampAreRejected() {
+        assertThrows(IllegalArgumentException.class, () -> Txn.parse("{\"txnId\":\"x\",\"card\":\"c1\",\"amount\":1}"));
+    }
 }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F2 | Dedup merges card-testing bursts | Sev-1 (5) | 10 | L6+ with fraud-domain sense |
| F3 | 24 h watermark hold | Sev-1 (5) | 20 | L7 (requires the timer/watermark model) |
| F6 | Constant idempotency key | Sev-1 (5) | 10 | L6+ |
| F1 | Non-deterministic key coder | Sev-2 (3) | 10 | L6+ Beam users |
| F4 | Fixed vs sliding windows | Sev-2 (3) | 2 | L5+ |
| F5 | Lateness deleted (masked) | Sev-2 (3) | 20 | L7 (requires seeing the masking) |
| F7 | Processing time as event time | Sev-2 (3) | 2 | L5+ |

Total **27**. L5s typically find F4 and F7. L6s add F1, F2 and F6. The L7 signals are F3 (reasoning about watermark holds from one innocuous call) and naming F5 *as masked by F3*, which turns into the instruction "fix them together."

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| Trusting the DirectRunner | "Tests pass, so dedup works" | The DirectRunner normalizes object state through coders |
| Fixing F1 by sorting in the coder | Sorted `AttrsCoder`, keep the fingerprint | Fixes F1, keeps F2 (merging card testing) |
| Fixing F3 alone | Remove `withOutputTimestamp`, ship | Late data starts being dropped (F5) |
| "Use processing-time timers for cleanup" | Moves cleanup to wall clock | Replays and backlogs clear state at the wrong time |
| "Keep fixed windows, lower the threshold" | Threshold 2 | More false positives; boundary blind spots remain |
| Assuming idempotent means safe | "card-control is idempotent" | Idempotency is only as good as the key |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "The timer doesn't output anything. How can it delay alerts?"</b></summary>

**Initial Prompt.** The watermark-hold mechanism.

**L5 Answer.** "It can't; it only clears state."

**Why L5 Stalls.** Watermark holds don't depend on whether the callback emits. The *declared* output timestamp is enough.

**L7 Answer.** "A timer's output timestamp is a promise that the callback might emit at that time, so the runner holds the ParDo's output watermark there until the timer fires. Beam's guide says event-time timers hold the output watermark at their timestamp by default. Here the output timestamp is set to the element's time on a timer 24 h out, so the output watermark is pinned to the oldest pending element for a day. Remove `withOutputTimestamp` and the default hold sits at the firing time, ahead of the watermark, so it never blocks."

</details>

<details><summary><b>Q2 · "How would you prove F3 without a production deploy?"</b></summary>

**Initial Prompt.** Testing time behavior.

**L5 Answer.** "Run the pipeline and check the output."

**Why L5 Stalls.** With bounded input, the output is identical: the watermark goes to infinity at the end and releases every hold.

**L7 Answer.** "TestStream: add the burst, advance the watermark past the window end, add one more element, then finish. On the DirectRunner each TestStream event runs to quiescence, so if the alert appears before the next element's processing, the window fired on time. That's P3. The PR's alert appears only after the watermark reaches infinity. As a unit test, assert with `PAssert...inOnTimePane()` after an explicit watermark advance."

</details>

<details><summary><b>Q3 · "Why did F1 pass on the DirectRunner?"</b></summary>

**Initial Prompt.** Runner differences.

**L5 Answer.** "Maybe the test data had the same field order."

**Why L5 Stalls.** Partly true for the author's tests, but even with different orders, the DirectRunner still masks it.

**L7 Answer.** "The DirectRunner round-trips each element through its coder between transforms, to catch encodability bugs. `TxnCoder` writes attributes sorted, so after Parse every map comes back in sorted order and `AttrsCoder` sees equal orders. Dataflow fuses Parse → Fingerprint and passes the original LinkedHashMap. The probe reproduces that by disabling `enforceEncodability`, and the false alert appears. The lesson: a coder's determinism must hold for any object state, not just the state your test runner produces."

</details>

<details><summary><b>Q4 · "The author says some gateway versions *do* re-mint txnIds on retry. Now what?"</b></summary>

**Initial Prompt.** When the clean identity is unavailable.

**L5 Answer.** "Then the fingerprint is necessary."

**Why L5 Stalls.** It accepts merging card-testing bursts as the price. That's the worst trade for a fraud system.

**L7 Answer.** "Treat it as a property of *those* gateways, not of all traffic. Ask for the gateway's retry token (most send an attempt or request id). If none exists, de-duplicate those gateways' events on fingerprint *within a short event-time window* (seconds, matching their retry timeout), and keep txnId dedup for everyone else. Then measure: compare alert rates with and without the fingerprint rule on a replay. And make sure card-testing bursts, identical by design, aren't inside that window."

</details>

<details><summary><b>Q5 · "Sliding windows cost 5×. Defend the fix to the cost-conscious author."</b></summary>

**Initial Prompt.** Correctness vs cost.

**L5 Answer.** "Correctness matters more than cost."

**Why L5 Stalls.** True, but it's not an engineering argument, and cheaper correct designs exist.

**L7 Answer.** "Fixed windows don't implement the rule: they miss every burst across a boundary, so the saving buys a blind spot attackers can use. If cost matters, the stateful alternative is cheaper than both: one state cell per card holding the last few timestamps, pruned on each event, with an event-time timer for expiry. That's O(1) state per card instead of 5 window assignments per event. I'd measure both on a day of traffic before choosing."

</details>

<details><summary><b>Q6 · "Explain F5's masking to the author in two sentences."</b></summary>

**Initial Prompt.** Communicating interacting defects.

**L5 Answer.** "F5 is fine because nothing is dropped right now."

**Why L5 Stalls.** It reads today's behavior as correctness and misses that a required fix will change it.

**L7 Answer.** "Right now nothing is late, because the 24 h hold keeps the downstream watermark in the past. That's also why alerts are a day late. When we remove the hold, late mobile authorizations start being dropped unless the allowed-lateness lines come back in the same change."

</details>

<details><summary><b>Q7 · "Is the per-card-hour idempotency key correct? A card could be compromised twice in an hour."</b></summary>

**Initial Prompt.** Idempotency-key granularity.

**L5 Answer.** "Use the alert's window end as the key instead."

**Why L5 Stalls.** Sliding windows produce up to five windows per burst, which means five keys and five blocks and notifications for one event.

**L7 Answer.** "The key must identify the *action*, and 'block this card' is effectively idempotent: a blocked card stays blocked until someone unblocks it. So collapsing within an hour is right for blocks. The edge case is an unblock followed by a new burst within the same hour. card-control could include its block state in the decision, or the key could include an unblock epoch. I'd confirm the unblock flow with the card-ops team, not pick it alone."

</details>

<details><summary><b>Q8 · "Rank the findings."</b></summary>

**Initial Prompt.** Prioritization.

**L5 Answer.** "Coder determinism first; it's a Beam correctness rule."

**Why L5 Stalls.** Rule-first again. F1 causes false positives, while F2, F3 and F6 cause missed or delayed fraud response.

**L7 Answer.** "F3 (every alert a day late: the pipeline's whole purpose fails), F2 (blind to card testing, the most common attack this rule exists for), F6 (only the first card blocked each day), then F5 together with F3, then F1 (false blocks harm customers), F4 (boundary blind spots), F7 (replay determinism). None of the Sev-1s is visible in the author's tests. Each needs TestStream or a domain-shaped input."

</details>

---

## 12. Checklist

- [ ] Every custom coder used as a key: does `verifyDeterministic()` actually hold for *all* object states (maps, sets, floats)?
- [ ] Every dedup key: does it identify the event (retry identity), or merely its content?
- [ ] Every `withOutputTimestamp`: how far behind the watermark does it hold, and for how long?
- [ ] Windows: does the window type match the rule's wording ("any 5 minutes" means sliding or stateful)?
- [ ] Lateness: allowed lateness, late firings and accumulation mode all chosen deliberately, and deleted lines noticed.
- [ ] Event time always from the event; never `now()` in a parse step.
- [ ] External side effects: idempotency key identifies the action (not constant, not per-window).
- [ ] Tests: TestStream with explicit watermark advances for anything time-dependent; by-reference passing for object-state-sensitive code.

---

## 13. References

- Apache Beam programming guide: *Timer output timestamps* (§11.3.4), windowing, triggers and late data. https://beam.apache.org/documentation/programming-guide/
- Apache Beam javadoc: `Coder.verifyDeterministic()`. https://beam.apache.org/releases/javadoc/current/org/apache/beam/sdk/coders/Coder.html
- Apache Beam javadoc: `Window` (`withAllowedLateness`: later elements "will be dropped"). https://beam.apache.org/releases/javadoc/current/org/apache/beam/sdk/transforms/windowing/Window.html
- Apache Beam javadoc: `TestStream`. https://beam.apache.org/releases/javadoc/current/org/apache/beam/sdk/testing/TestStream.html
- Apache Beam: *DirectRunner* (encodability and immutability enforcement). https://beam.apache.org/documentation/runners/direct/
- Akidau, T. *The world beyond batch: Streaming 102* (watermarks, triggers, lateness). https://www.oreilly.com/radar/the-world-beyond-batch-streaming-102/
- Within this KB: [PR04 Kafka consumer](01-pr04-kafka-consumer-offset-commit-race-poison-pill-and-rebalance-storm.md) · [PR06 Outbox and fencing](03-pr06-transactional-outbox-and-redis-distributed-lock-fencing-bugs.md) · [01-02 Layer 4](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#6-layer-4-io-and-distributed-boundaries)
