# 2.6 · Values That Bite: `java.time`, Localization & Numerics (`BigDecimal`, Formatting)

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("Handling Date, Time, Text, Numeric and Boolean Values" ~11% and "Implementing Localization" ~7% on 1Z0-830/831)
> **Sources:** JSR 310 / `java.time` Javadoc, JEP 252 (CLDR locale data by default), JDK 20 release notes (CLDR 42), `java.text` Javadoc (`MessageFormat`, `NumberFormat`, `CompactNumberFormat` JDK 12, `ListFormat` JDK 22), `java.math.BigDecimal` Javadoc, IANA tz database.
> All outputs are verified on JDK 25 (CLDR locale data). Formatting output depends on the JDK's CLDR version, so pin and test it.

---

## 1. The `java.time` model 🔥🎓

| Type | Represents | Has zone/offset? | Typical use |
|---|---|---|---|
| `Instant` | A point on the UTC time-line (seconds + nanos since epoch) | Implicitly UTC | Event timestamps, persistence, logs |
| `LocalDate` / `LocalTime` / `LocalDateTime` | A wall-clock date/time **without** zone | ❌ | Birthdays, business dates, "store opens at 09:00" |
| `ZonedDateTime` | Local date-time + `ZoneId` with **DST rules** | ✅ region rules | Scheduling in a user's zone, calendar arithmetic |
| `OffsetDateTime` | Local date-time + fixed `ZoneOffset` | ✅ fixed offset | APIs (ISO-8601 with offset), DB `TIMESTAMP WITH TIME ZONE` |
| `Duration` | Time-based amount (seconds + nanos) | — | Timeouts, SLAs ("24 hours") |
| `Period` | Date-based amount (years, months, days) | — | "1 month later", ages |
| `ZoneId` vs `ZoneOffset` | `Europe/Paris` (rules, DST) vs `+01:00` (fixed) | — | Prefer region IDs for future times |
| `Clock` | Source of "now" | — | **Inject it** for testability (`Clock.fixed`, `Clock.offset`) |

All `java.time` types are **immutable and thread-safe** (value-based: don't use `==` or synchronize on them). `plus`/`with` return new instances, so forgetting to assign the result is a classic bug (and exam trap): `date.plusDays(1);` alone does nothing.

### 1.1 Runnable: DST gaps and overlaps, `Duration` vs `Period`, month arithmetic

<!-- run: -->
```java
import java.time.*;
import java.time.temporal.ChronoUnit;

public class DstAndArithmetic {
    public static void main(String[] args) {
        ZoneId ny = ZoneId.of("America/New_York");

        // Spring-forward GAP: 2026-03-08 02:30 does not exist in New York
        ZonedDateTime gap = ZonedDateTime.of(LocalDateTime.of(2026, 3, 8, 2, 30), ny);
        System.out.println("gap 02:30 resolves to " + gap);

        // Fall-back OVERLAP: 2026-11-01 01:30 happens twice
        ZonedDateTime overlap = ZonedDateTime.of(LocalDateTime.of(2026, 11, 1, 1, 30), ny);
        System.out.println("overlap default: " + overlap.getOffset() + ", later: " + overlap.withLaterOffsetAtOverlap().getOffset());

        // A "day" across DST: Period (calendar) vs Duration (exact)
        ZonedDateTime before = ZonedDateTime.of(2026, 3, 7, 12, 0, 0, 0, ny);
        System.out.println("plus(Period 1 day) = " + before.plus(Period.ofDays(1)).toLocalTime()
            + ", plus(Duration 24h) = " + before.plus(Duration.ofHours(24)).toLocalTime()
            + ", hours between noon→noon = " + ChronoUnit.HOURS.between(before, before.plusDays(1)));

        // Month arithmetic clamps to the last valid day
        LocalDate jan31 = LocalDate.of(2026, 1, 31);
        System.out.println(jan31.plusMonths(1) + " " + LocalDate.of(2028, 1, 31).plusMonths(1) + " " + jan31.plusMonths(1).plusMonths(1)
            + "  (not Mar 31: clamping loses information)");

        LocalDate d = LocalDate.of(2026, 10, 24);
        d.plusDays(1);                                                 // result discarded: immutable!
        System.out.println("immutable: " + d + ", period between = " + Period.between(LocalDate.of(1990, 5, 20), d));

        Instant now = Instant.parse("2026-10-24T10:15:30.123456789Z");
        System.out.println(now.atOffset(ZoneOffset.ofHours(5)) + " | " + now.truncatedTo(ChronoUnit.MICROS) + " | epochMilli=" + now.toEpochMilli());
        Clock fixed = Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC);
        System.out.println("testable now: " + LocalDateTime.now(fixed));
    }
}
```

Output (verified):

```
gap 02:30 resolves to 2026-03-08T03:30-04:00[America/New_York]
overlap default: -04:00, later: -05:00
plus(Period 1 day) = 12:00, plus(Duration 24h) = 13:00, hours between noon→noon = 23
2026-02-28 2028-02-29 2026-03-28  (not Mar 31: clamping loses information)
immutable: 2026-10-24, period between = P36Y5M4D
2026-10-24T15:15:30.123456789+05:00 | 2026-10-24T10:15:30.123456Z | epochMilli=1792836930123
testable now: 2026-01-01T00:00
```

**Rules distilled:**

* A local time in a **gap** is shifted **forward** by the gap length. In an **overlap**, the **earlier** offset is chosen by default (`withLaterOffsetAtOverlap()` to switch).
* `Period.ofDays(1)` keeps the wall-clock time (calendar day). `Duration.ofHours(24)` adds exact elapsed time, so across spring-forward you land at 13:00.
* Store **`Instant`/UTC** for events, and store the **user's `ZoneId`** separately when future local times matter (meetings, renewals). Recompute with the current tz rules, because governments change DST rules with short notice.
* Precision: `Instant.now()` has microsecond (or finer) resolution on modern JDKs and OSes. PostgreSQL stores microseconds, so `truncatedTo(MICROS)` before comparing round-tripped values, or tests will flake.

### 1.2 Formatting and parsing: the `YYYY` incident and friends 🔥🎓

<!-- run: -->
```java
import java.time.*;
import java.time.format.*;
import java.util.Locale;

public class FormatterTraps {
    public static void main(String[] args) {
        LocalDate dec29 = LocalDate.of(2025, 12, 29);
        System.out.println("yyyy-MM-dd → " + dec29.format(DateTimeFormatter.ofPattern("yyyy-MM-dd")));
        System.out.println("YYYY-MM-dd → " + dec29.format(DateTimeFormatter.ofPattern("YYYY-MM-dd", Locale.US)) + "   ← week-based year!");
        System.out.println("hh:mm vs HH:mm at 15:05 → " + LocalTime.of(15, 5).format(DateTimeFormatter.ofPattern("hh:mm"))
            + " vs " + LocalTime.of(15, 5).format(DateTimeFormatter.ofPattern("HH:mm")));

        DateTimeFormatter strict = DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT);
        try { LocalDate.parse("2026-02-30", strict); }
        catch (DateTimeParseException e) { System.out.println("STRICT rejects Feb 30: " + e.getMessage().replaceAll(": .*", "")); }
        System.out.println("SMART (default) clamps: " + LocalDate.parse("2026-02-30", DateTimeFormatter.ofPattern("uuuu-MM-dd")));
        try { LocalDate.parse("2026-02-28", DateTimeFormatter.ofPattern("yyyy-MM-dd").withResolverStyle(ResolverStyle.STRICT)); }
        catch (DateTimeParseException e) { System.out.println("STRICT with yyyy (year-of-era) fails without an era → use uuuu"); }

        String usTime = LocalTime.of(9, 30).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.US));
        System.out.printf("Locale.US short time = \"%s\" char before AM = U+%04X (NARROW NO-BREAK SPACE since JDK 20 / CLDR 42)%n",
            usTime, (int) usTime.charAt(usTime.indexOf('A') - 1));
        try { LocalTime.parse("9:30 AM", DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.US)); }
        catch (DateTimeParseException e) { System.out.println("parsing \"9:30 AM\" (normal space) fails → " + e.getClass().getSimpleName()); }

        System.out.println(OffsetDateTime.parse("2026-10-24T10:15:30+02:00").toInstant() + " | "
            + DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(0)) + " | "
            + ZonedDateTime.of(2026, 10, 24, 9, 0, 0, 0, ZoneId.of("Asia/Kolkata")).format(DateTimeFormatter.RFC_1123_DATE_TIME));
    }
}
```

Output (verified):

```
yyyy-MM-dd → 2025-12-29
YYYY-MM-dd → 2026-12-29   ← week-based year!
hh:mm vs HH:mm at 15:05 → 03:05 vs 15:05
STRICT rejects Feb 30: Text '2026-02-30' could not be parsed
SMART (default) clamps: 2026-02-28
STRICT with yyyy (year-of-era) fails without an era → use uuuu
Locale.US short time = "9:30 AM" char before AM = U+202F (NARROW NO-BREAK SPACE since JDK 20 / CLDR 42)
parsing "9:30 AM" (normal space) fails → DateTimeParseException
2026-10-24T08:15:30Z | 1970-01-01T00:00:00Z | Sat, 24 Oct 2026 09:00:00 +0530
```

**Three real incident classes in that output:**

1. **`YYYY` = week-based year.** Dates in the last days of December format with *next* year's number. This pattern has caused real outages: certificate and token expiries, booking systems, and app-store review rejections every late December. Use `yyyy`, or better `uuuu`.
2. **`hh` without `a`** gives a 12-hour clock with no AM/PM marker, so 15:05 is logged as 03:05.
3. **JDK 20+ (CLDR 42)** inserts **U+202F narrow no-break space** before AM/PM in `Locale.US` short times. Code that parses user- or legacy-produced "9:30 AM" with localized formatters broke on upgrade. Parse machine data with **fixed, explicit patterns** (`ofPattern("h:mm a", Locale.US)`) or ISO formats, never localized ones. (`-Djava.locale.providers=COMPAT` was a stopgap; the COMPAT provider was removed in JDK 23.)

**`SimpleDateFormat` is not thread-safe.** A shared `static SimpleDateFormat` used from several threads produces silently wrong dates or `NumberFormatException`s. `DateTimeFormatter` is immutable and safe to share as a `static final` constant.

### 1.3 Legacy interop and persistence ⚡

* `Date.from(instant)`, `date.toInstant()`, `GregorianCalendar.from(zdt)`, `TimeZone.toZoneId()`, `java.sql.Timestamp.from(instant)`, `rs.getObject(i, OffsetDateTime.class)` (JDBC 4.2).
* DB mapping: `TIMESTAMP WITH TIME ZONE` ↔ `OffsetDateTime`/`Instant`; `TIMESTAMP` (without zone) ↔ `LocalDateTime` (dangerous if the session time zone differs between writers); `DATE` ↔ `LocalDate`.
* Containers often run in UTC. Developer laptops don't. Code that relies on `ZoneId.systemDefault()` (`LocalDate.now()` without a clock or zone) behaves differently in prod and in tests. **Always pass a `Clock` or an explicit `ZoneId`.**
* The tz database ships inside the JDK. Rule changes need a JDK update (or Oracle's tzupdater), so keep JDKs patched.

---

## 2. Localization (i18n / l10n) 🎓

### 2.1 `Locale`

* Create with `Locale.of("fr", "CA")` (JDK 19+; the constructors are deprecated), `Locale.forLanguageTag("pt-BR")`, or constants (`Locale.US`, `Locale.FRANCE`). `Locale.ROOT` is neutral.
* Default locale: from the OS or `-Duser.language/-Duser.country`, with separate categories `Locale.Category.DISPLAY` and `FORMAT` (`Locale.setDefault(Category, locale)`).
* **Locale data:** CLDR is the default provider since JDK 9 (JEP 252). Formats change between JDK versions as CLDR updates (see the NNBSP case above). Treat formatted output as **human-facing, not machine-parseable**.

### 2.2 Resource bundles: the lookup algorithm 🎓

For `ResourceBundle.getBundle("Messages", Locale.of("fr", "CA"))` with default locale `en_US`, the **candidate list** is:

```
Messages_fr_CA → Messages_fr → (default locale fallback) Messages_en_US → Messages_en → Messages (base)
```

1. The first candidate found (as a `.class` `ListResourceBundle` or a `.properties` file; for the same name the class wins) becomes the result bundle.
2. Its **parent chain** is the remaining, more general candidates of the same locale branch (`Messages_fr_CA` → `Messages_fr` → `Messages`), used for keys missing in the child. The default-locale bundles are **not** parents of `fr` bundles.
3. No bundle at all gives `MissingResourceException`. A missing *key* gives `MissingResourceException` from `getString`.
4. `.properties` files are read as **UTF-8** since JDK 9 (previously ISO-8859-1 with `\uXXXX` escapes).
5. Bundles are cached. `ResourceBundle.clearCache()` exists. `ResourceBundle.Control` customizes formats, fallback and TTL.

<!-- run: -->
```java
import java.util.*;

public class L10n {
    public static class Messages extends ListResourceBundle {          // base bundle
        protected Object[][] getContents() { return new Object[][] {{"greeting", "Hello"}, {"farewell", "Goodbye"}, {"cart", "Cart"}}; }
    }
    public static class Messages_fr extends ListResourceBundle {
        protected Object[][] getContents() { return new Object[][] {{"greeting", "Bonjour"}, {"farewell", "Au revoir"}}; }
    }
    public static class Messages_fr_CA extends ListResourceBundle {
        protected Object[][] getContents() { return new Object[][] {{"greeting", "Allô"}}; }
    }

    public static void main(String[] args) {
        Locale.setDefault(Locale.US);
        for (Locale l : List.of(Locale.of("fr", "CA"), Locale.FRANCE, Locale.GERMANY)) {
            ResourceBundle rb = ResourceBundle.getBundle("L10n$Messages", l);
            System.out.printf("%-6s → bundle=%-14s greeting=%-8s farewell=%-10s cart=%s%n",
                l, rb.getClass().getSimpleName(), rb.getString("greeting"), rb.getString("farewell"), rb.getString("cart"));
        }
        try { ResourceBundle.getBundle("L10n$Messages", Locale.FRANCE).getString("missing"); }
        catch (MissingResourceException e) { System.out.println("missing key → " + e.getClass().getSimpleName()); }
    }
}
```

Output (verified):

```
fr_CA  → bundle=Messages_fr_CA greeting=Allô     farewell=Au revoir  cart=Cart
fr_FR  → bundle=Messages_fr    greeting=Bonjour  farewell=Au revoir  cart=Cart
de_DE  → bundle=Messages       greeting=Hello    farewell=Goodbye    cart=Cart
missing key → MissingResourceException
```

`fr_CA` gets `greeting` from `Messages_fr_CA` and inherits `farewell` from `Messages_fr` and `cart` from the base through the **parent chain**. `de_DE` has no German bundle, so the lookup falls back through the **default locale** (`en_US` → `en`, also absent) to the **base** bundle.

### 2.3 Formatting numbers, currency, messages and lists 🎓

<!-- run: -->
```java
import java.math.BigDecimal;
import java.text.*;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.FormatStyle;
import java.util.*;

public class LocalizedFormatting {
    public static void main(String[] args) throws Exception {
        double amount = 1234567.891;
        for (Locale l : List.of(Locale.US, Locale.GERMANY, Locale.FRANCE, Locale.of("en", "IN"), Locale.JAPAN))
            System.out.printf("%-6s number=%-15s currency=%-17s percent=%s%n", l,
                NumberFormat.getInstance(l).format(amount), NumberFormat.getCurrencyInstance(l).format(amount),
                NumberFormat.getPercentInstance(l).format(0.256));

        NumberFormat compactShort = NumberFormat.getCompactNumberInstance(Locale.US, NumberFormat.Style.SHORT);
        NumberFormat compactLong = NumberFormat.getCompactNumberInstance(Locale.US, NumberFormat.Style.LONG);
        System.out.println("compact: " + compactShort.format(1_250_000) + " / " + compactLong.format(1_250_000) + " / " + compactShort.format(999));

        System.out.println("parse de_DE \"1.234,5\" → " + NumberFormat.getInstance(Locale.GERMANY).parse("1.234,5"));
        DecimalFormat df = new DecimalFormat("#,##0.00");
        System.out.println("DecimalFormat HALF_EVEN default: 2.345 → " + df.format(2.345) + ", 2.355 → " + df.format(2.355)
            + ", BigDecimal 2.345 → " + df.format(new BigDecimal("2.345")));

        String pattern = "On {0,date,long}, {1} placed {2,number,integer} order{2,choice,1#|1<s} totalling {3,number,currency}. It''s done.";
        MessageFormat mf = new MessageFormat(pattern, Locale.US);
        Date date = new GregorianCalendar(2026, Calendar.OCTOBER, 24).getTime();
        System.out.println(mf.format(new Object[] {date, "Ann", 1, 49.5}));
        System.out.println(mf.format(new Object[] {date, "Bob", 3, 120}));

        System.out.println(String.format(Locale.FRANCE, "%,.2f | %e | %08.3f | %-6s| %b | %x", 1234567.891, 12345.678, 3.14159, "ab", null, 255));
        System.out.println(LocalDate.of(2026, 10, 24).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(Locale.GERMANY)));
        System.out.println(ListFormat.getInstance(Locale.US, ListFormat.Type.STANDARD, ListFormat.Style.FULL).format(List.of("Java", "Kotlin", "Scala"))
            + " | " + ListFormat.getInstance(Locale.US, ListFormat.Type.OR, ListFormat.Style.FULL).format(List.of("tea", "coffee")));
    }
}
```

Output (verified, JDK 25 / CLDR):

```
en_US  number=1,234,567.891   currency=$1,234,567.89     percent=26%
de_DE  number=1.234.567,891   currency=1.234.567,89 €    percent=26 %
fr_FR  number=1 234 567,891   currency=1 234 567,89 €    percent=26 %
en_IN  number=1,234,567.891   currency=₹1,234,567.89     percent=26%
ja_JP  number=1,234,567.891   currency=￥1,234,568        percent=26%
compact: 1M / 1 million / 999
parse de_DE "1.234,5" → 1234.5
DecimalFormat HALF_EVEN default: 2.345 → 2.35, 2.355 → 2.35, BigDecimal 2.345 → 2.34
On October 24, 2026, Ann placed 1 order totalling $49.50. It's done.
On October 24, 2026, Bob placed 3 orders totalling $120.00. It's done.
1 234 567,89 | 1,234568e+04 | 0003,142 | ab    | false | ff
Samstag, 24. Oktober 2026
Java, Kotlin, and Scala | tea or coffee
```

Notes and traps:

* French uses a **narrow no-break space (U+202F)** as its grouping separator, and German a **non-breaking space before `€`**. Formatted output isn't ASCII-safe, so never parse it back as data.
* `en_IN`: CLDR specifies **lakh grouping** (12,34,567), but `java.text.DecimalFormat` supports only a single grouping size, so the JDK prints `1,234,567`. That is a long-standing `java.text` limitation; use ICU4J if Indian-style grouping matters. Yen has **0 fraction digits** (rounded to ￥1,234,568).
* **`DecimalFormat` rounds `HALF_EVEN` by default** (banker's rounding). Note how the `double` 2.345 printed `2.35` but `BigDecimal("2.345")` printed `2.34`, and `2.355` printed `2.35`. The `double` literal 2.345 is actually 2.34500000000000019984…, slightly above the midpoint. Binary floating point plus formatting rounding is how cents go missing. Use `BigDecimal` with an explicit `RoundingMode` for money.
* `MessageFormat`: a single quote starts a quoted section, so write `''` for an apostrophe. `{2,choice,1#|1<s}` pluralizes. Date and number sub-formats use the formatter's locale.
* `ListFormat` (JDK 22) produces locale-correct "A, B, and C" and "A or B".

---

## 3. Numerics: `BigDecimal`, money and exactness 🔥🎓

<!-- run: -->
```java
import java.math.*;

public class MoneyMath {
    public static void main(String[] args) {
        System.out.println("new BigDecimal(0.1)     = " + new BigDecimal(0.1));
        System.out.println("BigDecimal.valueOf(0.1) = " + BigDecimal.valueOf(0.1) + "   (uses Double.toString)");
        System.out.println("new BigDecimal(\"0.10\")  = " + new BigDecimal("0.10"));

        BigDecimal a = new BigDecimal("2.0"), b = new BigDecimal("2.00");
        System.out.println("equals=" + a.equals(b) + " compareTo=" + a.compareTo(b) + " hash equal=" + (a.hashCode() == b.hashCode())
            + " stripTrailingZeros equal=" + a.stripTrailingZeros().equals(b.stripTrailingZeros()));

        try { BigDecimal.ONE.divide(BigDecimal.valueOf(3)); }
        catch (ArithmeticException e) { System.out.println("1/3 → " + e.getMessage()); }
        System.out.println("1/3 scale 4 HALF_UP = " + BigDecimal.ONE.divide(BigDecimal.valueOf(3), 4, RoundingMode.HALF_UP)
            + ", MathContext.DECIMAL64 = " + BigDecimal.ONE.divide(BigDecimal.valueOf(3), MathContext.DECIMAL64));

        BigDecimal price = new BigDecimal("19.99"), qty = BigDecimal.valueOf(3), taxRate = new BigDecimal("0.0825");
        BigDecimal subtotal = price.multiply(qty);                                    // scale 2 + 0 = 2
        BigDecimal tax = subtotal.multiply(taxRate).setScale(2, RoundingMode.HALF_EVEN);
        System.out.println("subtotal=" + subtotal + " tax=" + tax + " total=" + subtotal.add(tax) + " (scales add on multiply: "
            + subtotal.multiply(taxRate) + ")");

        for (RoundingMode m : new RoundingMode[] {RoundingMode.HALF_UP, RoundingMode.HALF_EVEN, RoundingMode.HALF_DOWN, RoundingMode.CEILING, RoundingMode.FLOOR, RoundingMode.DOWN})
            System.out.printf("%-9s 2.5→%s 3.5→%s -2.5→%s%n", m, new BigDecimal("2.5").setScale(0, m), new BigDecimal("3.5").setScale(0, m), new BigDecimal("-2.5").setScale(0, m));

        System.out.println("1E+3 toString=" + new BigDecimal("1E+3") + " toPlainString=" + new BigDecimal("1E+3").toPlainString());
        double sum = 0; for (int i = 0; i < 10; i++) sum += 0.1;
        System.out.println("double 0.1×10 = " + sum + " | long cents: " + (10 * 10L) + " cents = $" + BigDecimal.valueOf(10 * 10L, 2));
        System.out.println("Math.clamp(150, 0, 100) = " + Math.clamp(150, 0, 100) + " | unsigned: " + Integer.toUnsignedString(-1)
            + " | BigInteger 2^100 = " + BigInteger.TWO.pow(100));
    }
}
```

Output (verified):

```
new BigDecimal(0.1)     = 0.1000000000000000055511151231257827021181583404541015625
BigDecimal.valueOf(0.1) = 0.1   (uses Double.toString)
new BigDecimal("0.10")  = 0.10
equals=false compareTo=0 hash equal=false stripTrailingZeros equal=true
1/3 → Non-terminating decimal expansion; no exact representable decimal result.
1/3 scale 4 HALF_UP = 0.3333, MathContext.DECIMAL64 = 0.3333333333333333
subtotal=59.97 tax=4.95 total=64.92 (scales add on multiply: 4.947525)
HALF_UP   2.5→3 3.5→4 -2.5→-3
HALF_EVEN 2.5→2 3.5→4 -2.5→-2
HALF_DOWN 2.5→2 3.5→3 -2.5→-2
CEILING   2.5→3 3.5→4 -2.5→-2
FLOOR     2.5→2 3.5→3 -2.5→-3
DOWN      2.5→2 3.5→3 -2.5→-2
1E+3 toString=1E+3 toPlainString=1000
double 0.1×10 = 0.9999999999999999 | long cents: 100 cents = $1.00
Math.clamp(150, 0, 100) = 100 | unsigned: 4294967295 | BigInteger 2^100 = 1267650600228229401496703205376
```

`Math.clamp` (JDK 21) has `int`, `long`, `float` and `double` overloads. With `int` arguments the most specific is `clamp(long value, int min, int max)`, which returns an `int`.

**Money rules:**

1. **Never** use `double`/`float` for money. Use `long` minor units (cents) for storage and arithmetic, or `BigDecimal` with an explicit scale and `RoundingMode`.
2. **Never** `new BigDecimal(double)`. Use `BigDecimal.valueOf(double)` or the `String` constructor.
3. `equals` compares **value and scale**; `compareTo` compares value only. `BigDecimal` keys in `HashSet`/`HashMap` with mixed scales misbehave, so normalize with `stripTrailingZeros()` or `setScale`.
4. `divide` without a scale or `MathContext` throws on non-terminating results. Always specify rounding.
5. Choose and document the rounding policy: `HALF_EVEN` (banker's, statistically unbiased, common in finance) vs `HALF_UP` (commercial). Round **once, at defined points** (per line item or per invoice), as required by the business or tax rules.
6. Currencies: `java.util.Currency.getInstance("JPY").getDefaultFractionDigits() == 0`. Never assume 2 decimals.

---

## 4. Production failure modes & diagnostics

| Failure | Signature | Fix |
|---|---|---|
| Wrong year in late December | `YYYY` pattern (week-based year) | `uuuu`/`yyyy`; lint for `YYYY` (Error Prone `MisusedWeekYear`) |
| Off-by-one-hour bugs twice a year | `LocalDateTime` arithmetic on zone-dependent schedules; `Duration` vs `Period` confusion | `ZonedDateTime` with region IDs; tests on DST boundary dates |
| Tests pass locally, fail in CI or containers | `LocalDate.now()` with the system default zone; locale-dependent formatting | Inject a `Clock`; explicit `ZoneId`/`Locale` |
| Parse failures after a JDK upgrade | CLDR changes (NNBSP, month abbreviations, grouping separators) | Fixed patterns with explicit `Locale` for machine data; ISO-8601 on the wire |
| Garbled dates under concurrency | Shared `SimpleDateFormat` | `DateTimeFormatter` |
| Lost cents | `double` money; `new BigDecimal(double)`; unspecified rounding | `long` minor units or `BigDecimal` + `RoundingMode` |
| Duplicate keys in maps | `BigDecimal("2.0")` vs `("2.00")` | Normalize the scale |
| Translation shows the base language | Bundle missing for the locale; wrong base name; non-UTF-8 properties edited on Windows | Check the candidate chain; UTF-8 files; tests per supported locale |

---

## 5. Interview & certification Q&A

<details><summary><b>Q1. 🎓 `LocalDate d = LocalDate.of(2026, 1, 31); d.plusMonths(1); System.out.println(d);` prints?</b></summary>

`2026-01-31`. `java.time` objects are immutable and the result of `plusMonths` is discarded. If assigned, it would be `2026-02-28` (clamped to month end).
</details>

<details><summary><b>Q2. 🔥 What's the difference between `Duration.ofDays(1)` and `Period.ofDays(1)` when added to a `ZonedDateTime` on a DST change day?</b></summary>

`Period` adds a calendar day and preserves the local time (noon → noon, which is 23 or 25 real hours). `Duration` adds exactly 24 hours of elapsed time, so the local time shifts by an hour (noon → 13:00 across spring-forward).
</details>

<details><summary><b>Q3. 🔥 Why did a system print `2026-12-29` for December 29, 2025?</b></summary>

The pattern used `YYYY` (week-based year). Dec 29, 2025 belongs to week 1 of week-year 2026. The correct pattern is `yyyy` (year-of-era) or `uuuu` (proleptic year, preferred with `ResolverStyle.STRICT`).
</details>

<details><summary><b>Q4. 🎓 Describe the resource bundle candidate and fallback order for `getBundle("App", Locale.of("es","MX"))` with default locale `en_GB`.</b></summary>

`App_es_MX` → `App_es` → (only if no `es` bundle exists) `App_en_GB` → `App_en` → `App`. The first found is returned. Missing keys are looked up through its parent chain within the same branch (e.g. `App_es_MX` → `App_es` → `App`), not through the default-locale bundles. If nothing is found, `MissingResourceException` is thrown.
</details>

<details><summary><b>Q5. 🎓 What do `new BigDecimal("2.0").equals(new BigDecimal("2.00"))` and `compareTo` return?</b></summary>

`equals` returns `false` (the scales differ: 1 vs 2) and `compareTo` returns `0` (equal numeric value). So a `HashSet` keeps both and a `TreeSet` keeps one.
</details>

<details><summary><b>Q6. ⚡ Which rounding mode does `DecimalFormat` use by default, and why did `format(2.345)` print `2.35` but `format(new BigDecimal("2.345"))` print `2.34`?</b></summary>

`HALF_EVEN`. The `double` literal 2.345 is stored as 2.34500000000000019984…, slightly above the midpoint, so it rounds up. The exact `BigDecimal` 2.345 sits exactly on the midpoint, so `HALF_EVEN` rounds to the even neighbour 2.34. This is why money uses decimal types.
</details>

<details><summary><b>Q7. 🎓 What does `MessageFormat.format("It's {0}", "ok")` produce?</b></summary>

`Its {0}`. A single quote starts a quoted literal section, so `{0}` is printed literally and the apostrophe disappears. Use `''` for a literal apostrophe: `"It''s {0}"` → `It's ok`.
</details>

<details><summary><b>Q8. 🔥 How do you make time-dependent code testable?</b></summary>

Inject a `java.time.Clock` (Spring bean, constructor parameter) and call `Instant.now(clock)`/`LocalDate.now(clock)`. Use `Clock.fixed` or `Clock.offset` in tests. Never call `now()` without a clock in business logic.
</details>

---

## 6. Further reading

* `java.time` package summary and the JSR-310 user guide (Stephen Colebourne's blog posts).
* Unicode CLDR release notes. JDK 20 release note on CLDR 42 NNBSP formatting.
* `java.math.BigDecimal` Javadoc (scale, precision, `MathContext`, `RoundingMode`).
