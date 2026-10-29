# PR03 · Multi-Tenant Auth: Cache Stampede, IDOR and JWT Security Flaws

> **What this module is.** A "zero-trust" PR: internal traffic stops going through the API gateway, so the documents service verifies bearer tokens itself and caches permissions locally. Every line looks defensive: a JWT verifier, signature checks, an expiry check, a cache with a fallback. It hides **7 defects, 4 of them Sev-1 cross-tenant or authentication bypasses**, plus a timing-safety issue that is argued rather than measured. The central lesson is a context change: code that was safe *behind* a gateway (trusting `X-Tenant-Id`) becomes an IDOR when the gateway is removed, and the diff doesn't show the gateway.

| Artifact | What it is | Verified |
|---|---|---|
| `pr03-diff` | `DocumentApi` modified; `JwtVerifier`, `PermissionCache`, `InvalidTokenException` new; test class rewritten: 232 diff lines | `git diff --no-index` from compiled sources |
| `DocumentApiTest` (author's) | 5 tests: valid token, missing token, tampered payload, expired token, non-reader | **5/5 pass** on the PR (§4) |
| `Pr03Probes` | 7 attacker/outage probes: `alg=none`, tenant-header swap, cross-tenant cache hit, fail-open, stampede, no-`exp` token, wrong-audience token | each succeeds on the PR and is refused on the fix (§8) |
| Fixed code | Algorithm pinned by the verifier, constant-time check, required `exp`/`aud`/`iss`/`tid`, tenant from the token, `(tenant, user)` cache with single-flight and bounded stale, fail closed | fixed suite 6/6; PR's own tests against the fix 5/5 |

**Verification.** Plain Java 21 (`javax.crypto` HMAC-SHA256, no JOSE library), JDK 25.0.4.1 with `javac --release 21 -Xlint:all -Werror`, and JUnit Platform 1.13.4. Probe tokens are minted by a test helper with the same shared key. P5 is timing-dependent ("one measured run"). F8 (non-constant-time comparison) is argued from the code and RFC 8725, not measured; timing attacks need statistical measurement over a network, which this harness doesn't attempt.

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L6 Authentication | F1 unsigned tokens accepted, F6 no-`exp` tokens never expire, F7 any audience accepted, F8 timing-unsafe comparison | The verifier *has* a signature check and an expiry check; the bypasses are in the conditions around them |
| L6 Authorization / tenancy | F2 tenant from a caller header, F3 cache key without tenant | Both were correct assumptions *before* this PR |
| L3 Failure paths | F4 fail-open fallback during a permission-service outage | "Fail soft" sounds like resilience |
| L2/L7 | F5 cache stampede on expiry | Single-request tests can't see it |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "It checks the signature." | Only when the token's own header says `HS*`. |
| "It checks expiry." | Only when the token chooses to include `exp`. |
| "The tenant comes from the request, like before." | Before, the gateway set that header; now the caller does. |
| "User 42's permissions." | User ids are only unique within a tenant. |
| "Graceful degradation on outage." | Degrading *authorization* means allowing. |

---

## 1. First principles

1. **The verifier chooses the algorithm, never the token.** RFC 8725 §2.1: "The algorithm can be changed to "none" by an attacker," and some libraries then validate the JWT without checking any signature. §3.1: "Libraries MUST enable the caller to specify a supported set of algorithms and MUST NOT use any other algorithms."
2. **`exp` is optional in the standard; requiring it is your policy.** RFC 7519 §4.1.4 defines `exp` as the time "on or after which the JWT MUST NOT be accepted for processing," and also says "Use of this claim is OPTIONAL." A service that accepts tokens without `exp` accepts bearer credentials that never expire.
3. **One issuer, many audiences.** RFC 8725 §3.9: when one issuer issues tokens for several relying parties, the JWT "MUST contain an "aud" (audience) claim that can be used to determine whether the JWT is being used by an intended party." With one shared HMAC key across internal services, `aud` is the *only* thing distinguishing an analytics token from a documents token.
4. **Identity is a tuple.** When user ids are unique per tenant, the principal is `(tenant, user)` and must come entirely from the authenticated credential. Any part that comes from a header, path or body is attacker-chosen. This is OWASP API1:2023 "Broken Object Level Authorization" at the tenant level.
5. **Authorization fails closed.** If the decision can't be made, the answer is "no" (or "not now": 503), never a default grant. Serving *last-known* permissions for a bounded window is a defensible availability trade-off. Serving *default* permissions is not.
6. **A TTL cache without single-flight is a synchronized herd.** All concurrent misses for a key hit the backend at once, and entries created together expire together. Single-flight (one load per key) and expiry jitter are the two standard remedies.

---

## 2. The PR

> **AUTH-412 · Verify JWTs in docs-service (zero-trust for internal traffic)**
>
> Internal callers (other services, batch jobs) will reach docs-service directly instead of through the API gateway, which until now verified tokens and injected `X-User-Id`/`X-Tenant-Id`. docs-service must verify tokens itself. permission-service is getting hammered (one call per request), so permissions should be cached.
>
> **PR description, by the author:**
> - `JwtVerifier`: HS256 with the shared internal key. Hand-rolled because claims are flat and we don't want a JOSE dependency in every service.
> - RS256 tokens (the new auth server, Q3) are "still validated at the gateway," so only `HS*` tokens are verified here.
> - Expired tokens are rejected.
> - `PermissionCache`: per-user permissions cached for 5 minutes. On a permission-service outage it falls back to read-only, so reads keep working.
> - Tenant still comes from `X-Tenant-Id`, unchanged.
> - Tests: valid, missing, tampered, expired, non-reader. All green.
>
> **Context the reviewer can discover:** auth-service issues HS256 tokens for *all* internal services with one shared key, distinguished by `aud`. User ids are per-tenant sequences (`u1`, `u2`, …), so every id exists in many tenants. The API gateway is being removed for internal traffic. That's the point of the ticket, so nothing strips `X-Tenant-Id` any more. The support tooling mints long-lived tokens without `exp`. permission-service p50 is 20 ms, and it falls over above ~2,000 rps.

---

## 3. The diff

```diff
diff --git a/docs-service/src/main/java/com/acme/docs/DocumentApi.java b/docs-service/src/main/java/com/acme/docs/DocumentApi.java
index c0a507a..93654af 100644
--- a/docs-service/src/main/java/com/acme/docs/DocumentApi.java
+++ b/docs-service/src/main/java/com/acme/docs/DocumentApi.java
@@ -1,22 +1,36 @@
 package com.acme.docs;
 
-/** GET /v1/documents/{id}. Runs behind the API gateway, which verifies the JWT and sets X-User-Id / X-Tenant-Id. */
+import java.util.Map;
+
+/** GET /v1/documents/{id}. Verifies the bearer token itself: internal traffic no longer passes the API gateway. */
 public final class DocumentApi {
     public record Response(int status, String body) {}
 
-    private final PermissionClient permissions;
+    private final JwtVerifier jwt;
+    private final PermissionCache permissions;
     private final DocumentStore documents;
 
-    public DocumentApi(PermissionClient permissions, DocumentStore documents) {
+    public DocumentApi(JwtVerifier jwt, PermissionCache permissions, DocumentStore documents) {
+        this.jwt = jwt;
         this.permissions = permissions;
         this.documents = documents;
     }
 
-    public Response getDocument(String userHeader, String tenantHeader, String docId) {
-        if (!permissions.fetch(tenantHeader, userHeader).contains("doc:read")) {
+    public Response getDocument(String authorization, String tenantHeader, String docId) {
+        if (authorization == null || !authorization.startsWith("Bearer ")) {
+            return new Response(401, "missing bearer token");
+        }
+        Map<String, String> claims;
+        try {
+            claims = jwt.verify(authorization.substring("Bearer ".length()));
+        } catch (InvalidTokenException e) {
+            return new Response(401, e.getMessage());
+        }
+        String tenant = tenantHeader; // X-Tenant-Id, unchanged
+        if (!permissions.permissions(tenant, claims.get("sub")).contains("doc:read")) {
             return new Response(403, "forbidden");
         }
-        return documents.find(tenantHeader, docId)
+        return documents.find(tenant, docId)
                 .map(content -> new Response(200, content))
                 .orElse(new Response(404, "not found"));
     }
diff --git a/docs-service/src/main/java/com/acme/docs/InvalidTokenException.java b/docs-service/src/main/java/com/acme/docs/InvalidTokenException.java
new file mode 100644
index 0000000..ed0a59a
--- /dev/null
+++ b/docs-service/src/main/java/com/acme/docs/InvalidTokenException.java
@@ -0,0 +1,9 @@
+package com.acme.docs;
+
+public class InvalidTokenException extends RuntimeException {
+    private static final long serialVersionUID = 1L;
+
+    public InvalidTokenException(String message) {
+        super(message);
+    }
+}
diff --git a/docs-service/src/main/java/com/acme/docs/JwtVerifier.java b/docs-service/src/main/java/com/acme/docs/JwtVerifier.java
new file mode 100644
index 0000000..58015c5
--- /dev/null
+++ b/docs-service/src/main/java/com/acme/docs/JwtVerifier.java
@@ -0,0 +1,67 @@
+package com.acme.docs;
+
+import java.nio.charset.StandardCharsets;
+import java.security.GeneralSecurityException;
+import java.time.Instant;
+import java.util.Base64;
+import java.util.HashMap;
+import java.util.Map;
+import java.util.regex.Matcher;
+import java.util.regex.Pattern;
+import javax.crypto.Mac;
+import javax.crypto.spec.SecretKeySpec;
+
+/** Verifies auth-service JWTs. Hand-rolled to keep a JOSE library out of every service (claims are flat). */
+public final class JwtVerifier {
+    private static final Pattern FIELD = Pattern.compile("\"(\\w+)\"\\s*:\\s*(?:\"([^\"]*)\"|(-?\\d+))");
+    private final byte[] key;
+
+    public JwtVerifier(byte[] hmacKey) {
+        this.key = hmacKey.clone();
+    }
+
+    public Map<String, String> verify(String token) {
+        String[] parts = token.split("\\.", -1);
+        if (parts.length != 3) {
+            throw new InvalidTokenException("malformed token");
+        }
+        Map<String, String> header = parse(parts[0]);
+        Map<String, String> claims = parse(parts[1]);
+        if (header.getOrDefault("alg", "").startsWith("HS")) { // RS256 tokens are checked by the gateway until Q3
+            String expected = Base64.getUrlEncoder().withoutPadding().encodeToString(hmac(parts[0] + "." + parts[1]));
+            if (!expected.equals(parts[2])) {
+                throw new InvalidTokenException("bad signature");
+            }
+        }
+        String exp = claims.get("exp");
+        if (exp != null && Long.parseLong(exp) < Instant.now().getEpochSecond()) {
+            throw new InvalidTokenException("token expired");
+        }
+        return claims;
+    }
+
+    private static Map<String, String> parse(String part) {
+        String json;
+        try {
+            json = new String(Base64.getUrlDecoder().decode(part), StandardCharsets.UTF_8);
+        } catch (IllegalArgumentException e) {
+            throw new InvalidTokenException("malformed token");
+        }
+        Map<String, String> fields = new HashMap<>();
+        Matcher m = FIELD.matcher(json);
+        while (m.find()) {
+            fields.put(m.group(1), m.group(2) != null ? m.group(2) : m.group(3));
+        }
+        return fields;
+    }
+
+    private byte[] hmac(String signingInput) {
+        try {
+            Mac mac = Mac.getInstance("HmacSHA256");
+            mac.init(new SecretKeySpec(key, "HmacSHA256"));
+            return mac.doFinal(signingInput.getBytes(StandardCharsets.UTF_8));
+        } catch (GeneralSecurityException e) {
+            throw new IllegalStateException(e);
+        }
+    }
+}
diff --git a/docs-service/src/main/java/com/acme/docs/PermissionCache.java b/docs-service/src/main/java/com/acme/docs/PermissionCache.java
new file mode 100644
index 0000000..caa977e
--- /dev/null
+++ b/docs-service/src/main/java/com/acme/docs/PermissionCache.java
@@ -0,0 +1,34 @@
+package com.acme.docs;
+
+import java.util.Map;
+import java.util.Set;
+import java.util.concurrent.ConcurrentHashMap;
+
+/** Keeps permission-service off the hot path: each user's permissions are cached for a TTL. */
+public final class PermissionCache {
+    private record Entry(Set<String> permissions, long expiresAt) {}
+
+    private static final Set<String> FALLBACK = Set.of("doc:read"); // read-only while permission-service is down
+
+    private final PermissionClient client;
+    private final long ttlMillis;
+    private final Map<String, Entry> entries = new ConcurrentHashMap<>();
+
+    public PermissionCache(PermissionClient client, long ttlMillis) {
+        this.client = client;
+        this.ttlMillis = ttlMillis;
+    }
+
+    public Set<String> permissions(String tenantId, String userId) {
+        Entry e = entries.get(userId);
+        if (e == null || e.expiresAt() < System.currentTimeMillis()) {
+            try {
+                e = new Entry(client.fetch(tenantId, userId), System.currentTimeMillis() + ttlMillis);
+                entries.put(userId, e);
+            } catch (RuntimeException ex) {
+                return FALLBACK; // fail soft: an outage should not take reads down
+            }
+        }
+        return e.permissions();
+    }
+}
diff --git a/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java b/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java
index 3fb6910..241020b 100644
--- a/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java
+++ b/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java
@@ -3,22 +3,46 @@ package com.acme.docs;
 import static org.junit.jupiter.api.Assertions.assertEquals;
 
 import java.util.Set;
+import org.junit.jupiter.api.BeforeEach;
 import org.junit.jupiter.api.Test;
 
 class DocumentApiTest {
     private final DocumentStore docs = new DocumentStore();
     private final FakePermissions perms = new FakePermissions(0).grant("acme", "alice", Set.of("doc:read"));
-    private final DocumentApi api = new DocumentApi(perms, docs);
+    private final DocumentApi api = new DocumentApi(new JwtVerifier(Tokens.KEY), new PermissionCache(perms, 60_000), docs);
 
-    @Test
-    void readerGetsDocument() {
+    @BeforeEach
+    void seed() {
         docs.put("acme", "d1", "Q3 plan");
-        assertEquals(new DocumentApi.Response(200, "Q3 plan"), api.getDocument("alice", "acme", "d1"));
+    }
+
+    @Test
+    void validTokenReadsDocument() {
+        String token = Tokens.hs256(Tokens.claims("alice", "acme", Tokens.inOneHour()));
+        assertEquals(new DocumentApi.Response(200, "Q3 plan"), api.getDocument("Bearer " + token, "acme", "d1"));
+    }
+
+    @Test
+    void missingTokenIsUnauthorized() {
+        assertEquals(401, api.getDocument(null, "acme", "d1").status());
+    }
+
+    @Test
+    void tamperedTokenIsUnauthorized() {
+        String[] alice = Tokens.hs256(Tokens.claims("alice", "acme", Tokens.inOneHour())).split("\\.");
+        String[] admin = Tokens.hs256(Tokens.claims("admin", "acme", Tokens.inOneHour())).split("\\.");
+        assertEquals(401, api.getDocument("Bearer " + alice[0] + "." + admin[1] + "." + alice[2], "acme", "d1").status());
+    }
+
+    @Test
+    void expiredTokenIsUnauthorized() {
+        String token = Tokens.hs256(Tokens.claims("alice", "acme", 1_700_000_000L));
+        assertEquals(401, api.getDocument("Bearer " + token, "acme", "d1").status());
     }
 
     @Test
     void nonReaderIsForbidden() {
-        docs.put("acme", "d1", "Q3 plan");
-        assertEquals(403, api.getDocument("bob", "acme", "d1").status());
+        String token = Tokens.hs256(Tokens.claims("bob", "acme", Tokens.inOneHour()));
+        assertEquals(403, api.getDocument("Bearer " + token, "acme", "d1").status());
     }
 }
```

---

## 4. The author's tests: green

```text
├─ JUnit Jupiter ✔
│  └─ DocumentApiTest ✔
│     ├─ expiredTokenIsUnauthorized() ✔
│     ├─ tamperedTokenIsUnauthorized() ✔
│     ├─ nonReaderIsForbidden() ✔
│     ├─ missingTokenIsUnauthorized() ✔
│     └─ validTokenReadsDocument() ✔
[         5 tests found           ]
[         5 tests successful      ]
[         0 tests failed          ]
```

The tests cover the *intended* behavior of each check, and none tries to bypass one. The tampered-payload test passes because that token says `alg: HS256`. The expired-token test passes because that token has `exp`. Every test uses tenant `acme` in both the token and the header. No test calls with an unsigned token, a missing `exp`, a foreign `aud`, a mismatched tenant, a second tenant with the same user id, a permission-service outage, or concurrency.

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** the trust boundary moves *into* this service (gateway removed); callers now control every header. A new remote dependency is wrapped in a cache, and a new failure mode appears: permission-service down.
- **Hunk scores:** `JwtVerifier.verify` 8/8 (trust, contract); `PermissionCache.permissions` 8/8 (trust, state, I/O, failure); `DocumentApi.getDocument` 8/8.
- **Radar hits:** `startsWith("HS")` gating the signature check (JwtVerifier 30). `exp != null &&` (37). No `aud`/`iss` anywhere. `expected.equals(parts[2])` (32). `tenant = tenantHeader` (DocumentApi 29). `entries.get(userId)` (PermissionCache 23). `return FALLBACK` in a catch (29). Check-then-load on expiry without single-flight (23–27).

### Minute 10: one hop each

- Who verifies `alg: none` or `alg: RS256` tokens now that the gateway is gone? Nobody: F1.
- What does the support tool mint? Tokens without `exp`, valid forever: F6.
- Same HMAC key for all services, no `aud` check: any service's token works here, F7.
- Who sets `X-Tenant-Id` now? The caller. And user ids repeat across tenants: F2.
- Cache key `userId` with per-tenant ids: F3.
- `FALLBACK` grants `doc:read` to everyone during an outage: F4.
- 5-minute TTL, no single-flight, hot users: a herd every expiry, F5.

### Minute 20: prove, unify, fix

- **Unify:** F1, F2, F6 and F7 are one principle. *Every fact the authorization decision uses must come from the verified token, checked against what this service expects.* F3 and F4 are the cache's version of the same principle: key by the full principal, and never manufacture a grant. F5 is a scaling property of the same cache.
- **Fix shape:** pin `alg=HS256`. Verify the signature in constant time *before* parsing claims. Require `exp`, `aud`, `iss`, `sub` and `tid`. Take the tenant from `tid`. Key the cache by `(tid, sub)` with single-flight loads and jittered TTL. On outage, serve last-known permissions for ≤ 5 minutes, then return 503.

---

## 6. The L7 answer key, line by line

### F1 · L6 · Sev-1 · Unsigned tokens are accepted: the token chooses whether it is verified (JwtVerifier 30)

**Mechanism.** The signature is checked only `if (header.getOrDefault("alg", "").startsWith("HS"))`. A token whose header says `"alg":"none"`, or `"RS256"`, or omits `alg`, skips verification entirely, and its claims are returned as trusted. The comment ("RS256 tokens are checked by the gateway") was true until this ticket removed the gateway. Anyone can mint `{"sub":"admin","tid":"acme"}` with an empty signature.

**Evidence.** P1: `unsigned token (alg=none) claiming acme/admin -> 200 "acme: Q3 acquisition plan"`.

```comment-l7
issue (blocking): tokens whose header doesn't say HS* skip signature verification entirely

Line 30 lets the token's own `alg` decide whether we verify; `alg: none`, `RS256` or a missing alg returns unverified claims. The comment relies on the gateway, which this ticket removes for internal traffic, which means anyone who can reach the service can mint any identity: the P1 probe reads acme's documents with an unsigned token claiming acme/admin. Suggest pinning the algorithm in the verifier (accept HS256 only until RS256 verification lands here) and rejecting everything else, per RFC 8725 section 3.1.
```

**Fix.**
```java
        if (!"HS256".equals(parse(parts[0]).get("alg"))) { // the verifier picks the algorithm, never the token
            throw new InvalidTokenException("unsupported alg");
        }
        if (!MessageDigest.isEqual(hmac(parts[0] + "." + parts[1]), decode(parts[2]))) { // constant time
            throw new InvalidTokenException("bad signature");
        }
        Map<String, String> claims = parse(parts[1]); // trusted only from here on
```

### F2 · L6 · Sev-1 · Tenant taken from a caller-controlled header: impersonate the same-named user in any tenant (DocumentApi 29–30)

**Mechanism.** The principal is `(tenant, sub)`, but only `sub` comes from the verified token. The tenant comes from `X-Tenant-Id`, which the gateway used to overwrite and nobody now controls. User ids are per-tenant sequences, so `u42` exists in hundreds of tenants. A legitimate globex user `u42` who sends `X-Tenant-Id: acme` is authorized *as acme's `u42`* and reads acme's documents. Nothing is forged and every signature is valid, so token inspection alone won't show this in logs.

**Evidence.** P2: `valid token for globex/u42 with X-Tenant-Id: acme -> 200 "acme: Q3 acquisition plan"`. Fix: `404`, because the request is evaluated in globex, where `d1` doesn't exist.

```comment-l7
issue (blocking): the tenant comes from X-Tenant-Id, so a user can act as the same-named user in any other tenant

Line 29 keeps reading the header the gateway used to set; with the gateway gone the caller sets it. Because user ids are only unique per tenant, globex's u42 sending `X-Tenant-Id: acme` is authorized as acme's u42 (P2 probe: 200 with acme's document, all signatures valid). Suggest taking the tenant from the token's `tid` claim and ignoring the header, so the whole principal (tid, sub) comes from the credential.
```

**Fix.**
```java
        String tenant = claims.get("tid"); // identity is (tid, sub): user ids are only unique within a tenant
```

### F3 · L6 · Sev-1 · Permission cache keyed by user id alone: permissions leak across tenants (PermissionCache 23, 27)

**Mechanism.** `entries.get(userId)` and `entries.put(userId, …)` ignore the tenant. Whichever tenant's `u7` loads first, every other tenant's `u7` gets those permissions for the TTL. No attacker is needed. Two legitimate users with the same id in different tenants are enough, and the outcome changes with request order, so it is close to impossible to debug from reports.

**Evidence.** P3: `globex/u7 (no grants) after acme/u7 was cached -> 200 "globex: roadmap"`. Fix: `403`.

```comment-l7
issue (blocking): the cache key is the user id alone, so one tenant's grants are served to another tenant's same-numbered user

Lines 23 and 27 key entries by `userId`; since ids repeat across tenants, whichever tenant's u7 loads first determines what every other u7 can do for five minutes, which means grants leak between tenants with no attacker involved. For example, the P3 probe gives globex/u7, who has no grants, read access after acme/u7 was cached. Suggest a `(tenantId, userId)` key, and a test with the same user id in two tenants.
```

**Fix.**
```java
    private record Key(String tenantId, String userId) {}
```
```java
        Key key = new Key(tenantId, userId);
```

### F4 · L3/L6 · Sev-1 · Fail-open: during a permission-service outage everyone can read (PermissionCache 11, 28–29)

**Mechanism.** Any exception from permission-service returns `FALLBACK = {doc:read}`, regardless of who is asking. During an outage, interns, suspended users and users whose access was revoked an hour ago can read every document in their tenant (and, with F2, any tenant's). Attackers can *induce* the condition: permission-service falls over above ~2,000 rps, and F5 helps them get there.

**Evidence.** P4: `permission-service down, user with no grants -> 200`. Fix: `503`.

```comment-l7
issue (blocking): permission-service errors grant doc:read to everyone (fail-open)

Lines 28-29 turn any exception into the FALLBACK set, so during an outage a user with no grants (or with revoked access) can read every document; the P4 probe shows a no-grant user getting a 200. That also gives an attacker a reason to overload permission-service. Suggest failing closed: serve the user's last-known permissions for a bounded window (say 5 minutes), then return 503. Never a default grant.
```

**Fix.**
```java
        } catch (CompletionException e) {
            if (cached != null && now - cached.loadedAt() < MAX_STALE_MILLIS) {
                return cached.permissions(); // last known, bounded staleness
            }
            throw new PermissionServiceUnavailableException(e.getCause());
        }
```

### F5 · L2/L7 · Sev-2 · Stampede on expiry: every concurrent miss calls permission-service (PermissionCache 23–27)

**Mechanism.** Check-then-load with no coordination. When a hot key expires, every in-flight request sees "expired" and calls the backend. Entries loaded at startup also expire together, every 5 minutes. At 2,000 rps that is a 2,000-call spike per hot key, exactly the load that tips permission-service over, which (with F4) turns into an authorization bypass.

**Evidence.** P5: `100 concurrent requests right after expiry: permission-service calls = 100` (fix: 1). One measured run.

```comment-l7
issue (blocking): concurrent misses for the same key all call permission-service (stampede), and expiries are synchronized

Lines 23-27 check, then load, with no coordination; when a hot entry expires every in-flight request reloads it, which means a load spike on exactly the service we're protecting. The P5 probe sees 100 backend calls for 100 concurrent requests after expiry (1 with single-flight). Suggest one in-flight load per key (a map of CompletableFuture, as in the fix) plus TTL jitter so entries don't expire in lockstep.
```

**Fix.**
```java
        CompletableFuture<Entry> mine = new CompletableFuture<>();
        CompletableFuture<Entry> inFlight = loads.putIfAbsent(key, mine);
        if (inFlight == null) { // this caller loads; concurrent misses for the same key wait on it
```
```java
                long jitter = ThreadLocalRandom.current().nextLong(ttlMillis / 10 + 1); // spread expiries apart
```

### F6 · L6 · Sev-2 · Tokens without `exp` are accepted forever (JwtVerifier 36–37)

**Mechanism.** `if (exp != null && …)` rejects expired tokens but accepts tokens with no `exp` at all. RFC 7519 makes `exp` optional, so the *policy* has to require it. The support tool mints such tokens, so any one that leaks (a log line, a pasted curl command) is a permanent credential that only a key rotation revokes.

**Evidence.** P6: `correctly signed token with no exp claim -> 200`. Fix: `401`.

```comment-l7
issue (blocking): a token with no exp claim never expires here

Line 37 only rejects tokens whose exp is in the past; a token without exp passes, which means any leaked support-tool token is valid until we rotate the shared key (P6 probe: a correctly signed token without exp reads documents). RFC 7519 leaves exp optional, so the requirement has to live in our verifier. Suggest requiring exp (with a small clock-skew allowance) and capping lifetime by policy.
```

**Fix.**
```java
        if (claims.get("exp") == null || seconds(claims.get("exp")) + CLOCK_SKEW_SECONDS < now) {
            throw new InvalidTokenException("token expired or has no exp");
        }
```

### F7 · L6 · Sev-2 · Any audience accepted: one service's tokens work on every service (JwtVerifier 23–41)

**Mechanism.** All internal services share one HMAC key, and auth-service distinguishes them by `aud`. The verifier never checks `aud` (or `iss`), so a token minted for analytics-api (lower privilege, more widely distributed, logged by a third-party tool) is accepted by documents-api. A compromise of the weakest service's tokens becomes a compromise of this one.

**Evidence.** P7: `token minted for analytics-api presented to documents-api -> 200`. Fix: `401`.

```comment-l7
issue (blocking): the verifier never checks aud or iss, so tokens minted for other services are accepted

With one shared HMAC key across internal services, `aud` is the only thing separating an analytics-api token from a documents-api token; for example, the P7 probe reads documents with an analytics-api token. This means our exposure equals the least careful service's. Suggest requiring aud == "documents-api" and iss == the auth-service URL (RFC 8725 section 3.9), and (follow-up) per-service keys or asymmetric signing.
```

**Fix.**
```java
        if (!audience.equals(claims.get("aud")) || !issuer.equals(claims.get("iss"))) {
            throw new InvalidTokenException("token not issued for this service");
        }
```

### F8 · L6 · Sev-3 · Signature compared with `String.equals` (JwtVerifier 32): argued, not measured

**Mechanism.** `String.equals` returns at the first differing character, so the comparison time leaks how many leading characters of a forged signature are correct. Remote exploitation over a network is hard and noisy, but the fix is free: compare raw bytes with `MessageDigest.isEqual`, whose JDK 21 implementation note says: "The calculation time depends only on the length of `digesta`. It does not depend on the length of `digestb` or the contents of `digesta` and `digestb`." The fixed code also compares decoded bytes rather than base64 strings, which avoids non-canonical-encoding ambiguity.

```comment-l7
issue (non-blocking): the HMAC comparison on line 32 is not constant-time

`String.equals` stops at the first mismatch, so response timing can leak signature prefixes; hard to exploit remotely, but the fix costs nothing. Suggest decoding the signature and comparing bytes with MessageDigest.isEqual.
```

**Fix.** Shown under F1 (`MessageDigest.isEqual`).

### Not a defect, but worth a question: the hand-rolled JWT parser

A regex JSON parser accepts duplicate keys with last-one-wins semantics, and claims are parsed before the signature is checked. The fixed version rejects duplicate fields and parses claims only after verification. The durable answer is a vetted JOSE library (for example Nimbus JOSE + JWT) configured with an explicit algorithm allow-list. The author's dependency concern is real, but the cost of maintaining a security-critical parser is higher.

```comment-l7
thought (non-blocking): the hand-rolled parser is now security-critical code

Duplicate keys resolve last-one-wins and claims are parsed before the signature check; the fix tightens both, but a vetted JOSE library with an algorithm allow-list would remove the class. Worth a follow-up ticket rather than a blocker.
```

---

## 7. The refactored code

```java
// ===== docs-service/src/main/java/com/acme/docs/DocumentApi.java =====
package com.acme.docs;

import java.util.Map;
import java.util.Set;

/** GET /v1/documents/{id}. Verifies the bearer token itself: internal traffic no longer passes the API gateway. */
public final class DocumentApi {
    public record Response(int status, String body) {}

    private final JwtVerifier jwt;
    private final PermissionCache permissions;
    private final DocumentStore documents;

    public DocumentApi(JwtVerifier jwt, PermissionCache permissions, DocumentStore documents) {
        this.jwt = jwt;
        this.permissions = permissions;
        this.documents = documents;
    }

    /** {@code tenantHeader} (X-Tenant-Id) is caller-controlled and deliberately ignored: the tenant is in the token. */
    public Response getDocument(String authorization, String tenantHeader, String docId) {
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            return new Response(401, "missing bearer token");
        }
        Map<String, String> claims;
        try {
            claims = jwt.verify(authorization.substring("Bearer ".length()));
        } catch (InvalidTokenException e) {
            return new Response(401, e.getMessage());
        }
        String tenant = claims.get("tid"); // identity is (tid, sub): user ids are only unique within a tenant
        Set<String> granted;
        try {
            granted = permissions.permissions(tenant, claims.get("sub"));
        } catch (PermissionServiceUnavailableException e) {
            return new Response(503, "authorization temporarily unavailable");
        }
        if (!granted.contains("doc:read")) {
            return new Response(403, "forbidden");
        }
        return documents.find(tenant, docId)
                .map(content -> new Response(200, content))
                .orElse(new Response(404, "not found"));
    }
}

// ===== docs-service/src/main/java/com/acme/docs/InvalidTokenException.java =====
package com.acme.docs;

public class InvalidTokenException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    public InvalidTokenException(String message) {
        super(message);
    }
}

// ===== docs-service/src/main/java/com/acme/docs/JwtVerifier.java =====
package com.acme.docs;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Verifies auth-service JWTs (RFC 8725 practices): one allowed algorithm chosen by us, constant-time signature
 * check before reading claims, and exp, aud, iss, sub and tid all required. Follow-up: a vetted JOSE library.
 */
public final class JwtVerifier {
    private static final Pattern FIELD = Pattern.compile("\"(\\w+)\"\\s*:\\s*(?:\"([^\"]*)\"|(-?\\d+))");
    private static final long CLOCK_SKEW_SECONDS = 60;
    private final byte[] key;
    private final String audience;
    private final String issuer;

    public JwtVerifier(byte[] hmacKey) {
        this(hmacKey, "documents-api", "https://auth.acme.example");
    }

    public JwtVerifier(byte[] hmacKey, String audience, String issuer) {
        this.key = hmacKey.clone();
        this.audience = audience;
        this.issuer = issuer;
    }

    public Map<String, String> verify(String token) {
        String[] parts = token.split("\\.", -1);
        if (parts.length != 3) {
            throw new InvalidTokenException("malformed token");
        }
        if (!"HS256".equals(parse(parts[0]).get("alg"))) { // the verifier picks the algorithm, never the token
            throw new InvalidTokenException("unsupported alg");
        }
        if (!MessageDigest.isEqual(hmac(parts[0] + "." + parts[1]), decode(parts[2]))) { // constant time
            throw new InvalidTokenException("bad signature");
        }
        Map<String, String> claims = parse(parts[1]); // trusted only from here on
        long now = Instant.now().getEpochSecond();
        if (claims.get("exp") == null || seconds(claims.get("exp")) + CLOCK_SKEW_SECONDS < now) {
            throw new InvalidTokenException("token expired or has no exp");
        }
        if (!audience.equals(claims.get("aud")) || !issuer.equals(claims.get("iss"))) {
            throw new InvalidTokenException("token not issued for this service");
        }
        if (claims.get("sub") == null || claims.get("tid") == null) {
            throw new InvalidTokenException("token has no subject or tenant");
        }
        return claims;
    }

    private static long seconds(String value) {
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException e) {
            throw new InvalidTokenException("malformed exp");
        }
    }

    private static byte[] decode(String part) {
        try {
            return Base64.getUrlDecoder().decode(part);
        } catch (IllegalArgumentException e) {
            throw new InvalidTokenException("malformed token");
        }
    }

    private static Map<String, String> parse(String part) {
        String json = new String(decode(part), StandardCharsets.UTF_8);
        Map<String, String> fields = new HashMap<>();
        Matcher m = FIELD.matcher(json);
        while (m.find()) {
            if (fields.put(m.group(1), m.group(2) != null ? m.group(2) : m.group(3)) != null) {
                throw new InvalidTokenException("duplicate field " + m.group(1)); // no last-one-wins ambiguity
            }
        }
        return fields;
    }

    private byte[] hmac(String signingInput) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(signingInput.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }
}

// ===== docs-service/src/main/java/com/acme/docs/PermissionCache.java =====
package com.acme.docs;

import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Permission cache keyed by (tenant, user): one in-flight load per key, jittered expiry, and it never fails open.
 * During a permission-service outage it serves last-known permissions for a bounded time, then refuses (503).
 */
public final class PermissionCache {
    private record Key(String tenantId, String userId) {}

    private record Entry(Set<String> permissions, long loadedAt, long expiresAt) {}

    private static final long MAX_STALE_MILLIS = 5 * 60_000;

    private final PermissionClient client;
    private final long ttlMillis;
    private final Map<Key, Entry> entries = new ConcurrentHashMap<>();
    private final Map<Key, CompletableFuture<Entry>> loads = new ConcurrentHashMap<>();

    public PermissionCache(PermissionClient client, long ttlMillis) {
        this.client = client;
        this.ttlMillis = ttlMillis;
    }

    public Set<String> permissions(String tenantId, String userId) {
        Key key = new Key(tenantId, userId);
        long now = System.currentTimeMillis();
        Entry cached = entries.get(key);
        if (cached != null && now < cached.expiresAt()) {
            return cached.permissions();
        }
        CompletableFuture<Entry> mine = new CompletableFuture<>();
        CompletableFuture<Entry> inFlight = loads.putIfAbsent(key, mine);
        if (inFlight == null) { // this caller loads; concurrent misses for the same key wait on it
            inFlight = mine;
            try {
                long jitter = ThreadLocalRandom.current().nextLong(ttlMillis / 10 + 1); // spread expiries apart
                Entry fresh = new Entry(client.fetch(tenantId, userId), now, now + ttlMillis + jitter);
                entries.put(key, fresh);
                mine.complete(fresh);
            } catch (RuntimeException e) {
                mine.completeExceptionally(e);
            } finally {
                loads.remove(key);
            }
        }
        try {
            return inFlight.join().permissions();
        } catch (CompletionException e) {
            if (cached != null && now - cached.loadedAt() < MAX_STALE_MILLIS) {
                return cached.permissions(); // last known, bounded staleness
            }
            throw new PermissionServiceUnavailableException(e.getCause());
        }
    }
}

// ===== docs-service/src/main/java/com/acme/docs/PermissionServiceUnavailableException.java =====
package com.acme.docs;

/** Authorization could not be decided (maps to HTTP 503). Never treated as "allowed". */
public class PermissionServiceUnavailableException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    public PermissionServiceUnavailableException(Throwable cause) {
        super("permission-service unavailable", cause);
    }
}
```

**Fixed suite: 6/6 (output, verified).**

```text
├─ JUnit Jupiter ✔
│  └─ DocumentApiTest ✔
│     ├─ permissionOutageFailsClosed() ✔
│     ├─ unsignedTokenIsRejected() ✔
│     ├─ validTokenReadsDocument() ✔
│     ├─ cacheEntriesArePerTenant() ✔
│     ├─ tokenWithoutExpOrForAnotherAudienceIsRejected() ✔
│     └─ tenantComesFromTheTokenNotTheHeader() ✔
[         6 tests found           ]
[         6 tests successful      ]
[         0 tests failed          ]
```

**The PR's original tests against the fix (output, verified).** All five pass. They tested intended behavior, which the fix preserves:

```text
├─ JUnit Jupiter ✔
│  └─ DocumentApiTest ✔
│     ├─ expiredTokenIsUnauthorized() ✔
│     ├─ tamperedTokenIsUnauthorized() ✔
│     ├─ nonReaderIsForbidden() ✔
│     ├─ missingTokenIsUnauthorized() ✔
│     └─ validTokenReadsDocument() ✔
[         5 tests found           ]
[         5 tests successful      ]
[         0 tests failed          ]
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Algorithm | Chosen by the token's header | Pinned to HS256 by the verifier |
| Signature | Checked for `HS*` only; `String.equals` on base64 | Always checked; `MessageDigest.isEqual` on bytes; claims parsed only afterwards |
| Expiry | Checked only if present | Required, with 60 s skew |
| Audience / issuer | Ignored | Required to match this service |
| Tenant | `X-Tenant-Id` header | `tid` claim; header ignored |
| Cache key | `userId` | `(tenantId, userId)` |
| Concurrent misses | N loads | One in-flight load per key; jittered expiry |
| Outage | Default `doc:read` for everyone | Last-known permissions ≤ 5 min, then 503 |

---

## 8. Probe evidence

**Against the PR's code (output, verified; P5 is one measured run):**

```text
PR03 probes against the PR's docs-service
P1 F1 unsigned token (alg=none) claiming acme/admin -> 200 "acme: Q3 acquisition plan"
P2 F2 valid token for globex/u42 with X-Tenant-Id: acme -> 200 "acme: Q3 acquisition plan"
P3 F3 globex/u7 (no grants) after acme/u7 was cached -> 200 "globex: roadmap"
P4 F4 permission-service down, user with no grants -> 200 "acme: Q3 acquisition plan"
P5 F5 100 concurrent requests right after expiry: permission-service calls = 100, 200s = 100 (one measured run)
P6 F6 correctly signed token with no exp claim -> 200 "acme: Q3 acquisition plan"
P7 F7 token minted for analytics-api presented to documents-api -> 200 "acme: Q3 acquisition plan"
```

**Against the fixed code (output, verified; P5 is one measured run):**

```text
PR03 probes against the fixed docs-service
P1 F1 unsigned token (alg=none) claiming acme/admin -> 401
P2 F2 valid token for globex/u42 with X-Tenant-Id: acme -> 404
P3 F3 globex/u7 (no grants) after acme/u7 was cached -> 403
P4 F4 permission-service down, user with no grants -> 503
P5 F5 100 concurrent requests right after expiry: permission-service calls = 1, 200s = 100 (one measured run)
P6 F6 correctly signed token with no exp claim -> 401
P7 F7 token minted for analytics-api presented to documents-api -> 401
```

<details><summary><b>The probe harness (Pr03Probes.java)</b></summary>

```java
package com.acme.docs;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/** Pr03Probes - attacker- and outage-shaped probes for PR03. Compiled against the PR's code and the fix. */
public final class Pr03Probes {
    private static DocumentStore docs() {
        DocumentStore d = new DocumentStore();
        d.put("acme", "d1", "acme: Q3 acquisition plan");
        d.put("globex", "g1", "globex: roadmap");
        return d;
    }

    private static DocumentApi api(FakePermissions perms, long ttlMillis) {
        return new DocumentApi(new JwtVerifier(Tokens.KEY), new PermissionCache(perms, ttlMillis), docs());
    }

    private static String show(DocumentApi.Response r) {
        return r.status() + (r.status() == 200 ? " \"" + r.body() + "\"" : "");
    }

    private static String bearer(Map<String, Object> claims) {
        return "Bearer " + Tokens.hs256(claims);
    }

    public static void main(String[] args) throws Exception {
        System.out.println("PR03 probes against the " + args[0] + " docs-service");
        FakePermissions perms = new FakePermissions(0).grant("acme", "admin", Set.of("doc:read"));
        String forged = Tokens.unsigned(Tokens.claims("admin", "acme", Tokens.inOneHour()));
        System.out.println("P1 F1 unsigned token (alg=none) claiming acme/admin -> "
                + show(api(perms, 60_000).getDocument("Bearer " + forged, "acme", "d1")));

        perms = new FakePermissions(0).grant("acme", "u42", Set.of("doc:read")).grant("globex", "u42", Set.of("doc:read"));
        String globexU42 = bearer(Tokens.claims("u42", "globex", Tokens.inOneHour()));
        System.out.println("P2 F2 valid token for globex/u42 with X-Tenant-Id: acme -> "
                + show(new DocumentApi(new JwtVerifier(Tokens.KEY), new PermissionCache(perms, 60_000), docs())
                        .getDocument(globexU42, "acme", "d1")));

        perms = new FakePermissions(0).grant("acme", "u7", Set.of("doc:read")); // globex/u7 has no permissions
        DocumentApi shared = api(perms, 60_000);
        shared.getDocument(bearer(Tokens.claims("u7", "acme", Tokens.inOneHour())), "acme", "d1");
        System.out.println("P3 F3 globex/u7 (no grants) after acme/u7 was cached -> "
                + show(shared.getDocument(bearer(Tokens.claims("u7", "globex", Tokens.inOneHour())), "globex", "g1")));

        perms = new FakePermissions(0); // nobody has any permission
        perms.down = true;
        System.out.println("P4 F4 permission-service down, user with no grants -> "
                + show(api(perms, 60_000).getDocument(bearer(Tokens.claims("intern", "acme", Tokens.inOneHour())), "acme", "d1")));

        stampede();

        perms = new FakePermissions(0).grant("acme", "support-bot", Set.of("doc:read"));
        Map<String, Object> noExp = new HashMap<>(Tokens.claims("support-bot", "acme", Tokens.inOneHour()));
        noExp.remove("exp");
        System.out.println("P6 F6 correctly signed token with no exp claim -> "
                + show(api(perms, 60_000).getDocument(bearer(noExp), "acme", "d1")));

        perms = new FakePermissions(0).grant("acme", "alice", Set.of("doc:read"));
        Map<String, Object> analytics = new HashMap<>(Tokens.claims("alice", "acme", Tokens.inOneHour()));
        analytics.put("aud", "analytics-api");
        System.out.println("P7 F7 token minted for analytics-api presented to documents-api -> "
                + show(api(perms, 60_000).getDocument(bearer(analytics), "acme", "d1")));
    }

    static void stampede() throws Exception {
        FakePermissions perms = new FakePermissions(50).grant("acme", "alice", Set.of("doc:read"));
        DocumentApi api = api(perms, 100);
        String token = bearer(Tokens.claims("alice", "acme", Tokens.inOneHour()));
        api.getDocument(token, "acme", "d1"); // warm the cache
        Thread.sleep(150); // let the entry expire
        perms.calls.set(0);
        int n = 100;
        CyclicBarrier start = new CyclicBarrier(n);
        ExecutorService pool = Executors.newFixedThreadPool(n);
        List<Future<Integer>> fs = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            fs.add(pool.submit(() -> {
                start.await();
                return api.getDocument(token, "acme", "d1").status();
            }));
        }
        int ok = 0;
        for (Future<Integer> f : fs) {
            ok += f.get() == 200 ? 1 : 0;
        }
        pool.shutdown();
        System.out.println("P5 F5 100 concurrent requests right after expiry: permission-service calls = " + perms.calls.get()
                + ", 200s = " + ok + " (one measured run)");
    }
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/docs-service/src/main/java/com/acme/docs/DocumentApi.java b/docs-service/src/main/java/com/acme/docs/DocumentApi.java
index 93654af..b26b43b 100644
--- a/docs-service/src/main/java/com/acme/docs/DocumentApi.java
+++ b/docs-service/src/main/java/com/acme/docs/DocumentApi.java
@@ -1,6 +1,7 @@
 package com.acme.docs;
 
 import java.util.Map;
+import java.util.Set;
 
 /** GET /v1/documents/{id}. Verifies the bearer token itself: internal traffic no longer passes the API gateway. */
 public final class DocumentApi {
@@ -16,6 +17,7 @@ public final class DocumentApi {
         this.documents = documents;
     }
 
+    /** {@code tenantHeader} (X-Tenant-Id) is caller-controlled and deliberately ignored: the tenant is in the token. */
     public Response getDocument(String authorization, String tenantHeader, String docId) {
         if (authorization == null || !authorization.startsWith("Bearer ")) {
             return new Response(401, "missing bearer token");
@@ -26,8 +28,14 @@ public final class DocumentApi {
         } catch (InvalidTokenException e) {
             return new Response(401, e.getMessage());
         }
-        String tenant = tenantHeader; // X-Tenant-Id, unchanged
-        if (!permissions.permissions(tenant, claims.get("sub")).contains("doc:read")) {
+        String tenant = claims.get("tid"); // identity is (tid, sub): user ids are only unique within a tenant
+        Set<String> granted;
+        try {
+            granted = permissions.permissions(tenant, claims.get("sub"));
+        } catch (PermissionServiceUnavailableException e) {
+            return new Response(503, "authorization temporarily unavailable");
+        }
+        if (!granted.contains("doc:read")) {
             return new Response(403, "forbidden");
         }
         return documents.find(tenant, docId)
diff --git a/docs-service/src/main/java/com/acme/docs/JwtVerifier.java b/docs-service/src/main/java/com/acme/docs/JwtVerifier.java
index 58015c5..2f57fc2 100644
--- a/docs-service/src/main/java/com/acme/docs/JwtVerifier.java
+++ b/docs-service/src/main/java/com/acme/docs/JwtVerifier.java
@@ -2,6 +2,7 @@ package com.acme.docs;
 
 import java.nio.charset.StandardCharsets;
 import java.security.GeneralSecurityException;
+import java.security.MessageDigest;
 import java.time.Instant;
 import java.util.Base64;
 import java.util.HashMap;
@@ -11,13 +12,25 @@ import java.util.regex.Pattern;
 import javax.crypto.Mac;
 import javax.crypto.spec.SecretKeySpec;
 
-/** Verifies auth-service JWTs. Hand-rolled to keep a JOSE library out of every service (claims are flat). */
+/**
+ * Verifies auth-service JWTs (RFC 8725 practices): one allowed algorithm chosen by us, constant-time signature
+ * check before reading claims, and exp, aud, iss, sub and tid all required. Follow-up: a vetted JOSE library.
+ */
 public final class JwtVerifier {
     private static final Pattern FIELD = Pattern.compile("\"(\\w+)\"\\s*:\\s*(?:\"([^\"]*)\"|(-?\\d+))");
+    private static final long CLOCK_SKEW_SECONDS = 60;
     private final byte[] key;
+    private final String audience;
+    private final String issuer;
 
     public JwtVerifier(byte[] hmacKey) {
+        this(hmacKey, "documents-api", "https://auth.acme.example");
+    }
+
+    public JwtVerifier(byte[] hmacKey, String audience, String issuer) {
         this.key = hmacKey.clone();
+        this.audience = audience;
+        this.issuer = issuer;
     }
 
     public Map<String, String> verify(String token) {
@@ -25,32 +38,50 @@ public final class JwtVerifier {
         if (parts.length != 3) {
             throw new InvalidTokenException("malformed token");
         }
-        Map<String, String> header = parse(parts[0]);
-        Map<String, String> claims = parse(parts[1]);
-        if (header.getOrDefault("alg", "").startsWith("HS")) { // RS256 tokens are checked by the gateway until Q3
-            String expected = Base64.getUrlEncoder().withoutPadding().encodeToString(hmac(parts[0] + "." + parts[1]));
-            if (!expected.equals(parts[2])) {
-                throw new InvalidTokenException("bad signature");
-            }
+        if (!"HS256".equals(parse(parts[0]).get("alg"))) { // the verifier picks the algorithm, never the token
+            throw new InvalidTokenException("unsupported alg");
+        }
+        if (!MessageDigest.isEqual(hmac(parts[0] + "." + parts[1]), decode(parts[2]))) { // constant time
+            throw new InvalidTokenException("bad signature");
         }
-        String exp = claims.get("exp");
-        if (exp != null && Long.parseLong(exp) < Instant.now().getEpochSecond()) {
-            throw new InvalidTokenException("token expired");
+        Map<String, String> claims = parse(parts[1]); // trusted only from here on
+        long now = Instant.now().getEpochSecond();
+        if (claims.get("exp") == null || seconds(claims.get("exp")) + CLOCK_SKEW_SECONDS < now) {
+            throw new InvalidTokenException("token expired or has no exp");
+        }
+        if (!audience.equals(claims.get("aud")) || !issuer.equals(claims.get("iss"))) {
+            throw new InvalidTokenException("token not issued for this service");
+        }
+        if (claims.get("sub") == null || claims.get("tid") == null) {
+            throw new InvalidTokenException("token has no subject or tenant");
         }
         return claims;
     }
 
-    private static Map<String, String> parse(String part) {
-        String json;
+    private static long seconds(String value) {
         try {
-            json = new String(Base64.getUrlDecoder().decode(part), StandardCharsets.UTF_8);
+            return Long.parseLong(value);
+        } catch (NumberFormatException e) {
+            throw new InvalidTokenException("malformed exp");
+        }
+    }
+
+    private static byte[] decode(String part) {
+        try {
+            return Base64.getUrlDecoder().decode(part);
         } catch (IllegalArgumentException e) {
             throw new InvalidTokenException("malformed token");
         }
+    }
+
+    private static Map<String, String> parse(String part) {
+        String json = new String(decode(part), StandardCharsets.UTF_8);
         Map<String, String> fields = new HashMap<>();
         Matcher m = FIELD.matcher(json);
         while (m.find()) {
-            fields.put(m.group(1), m.group(2) != null ? m.group(2) : m.group(3));
+            if (fields.put(m.group(1), m.group(2) != null ? m.group(2) : m.group(3)) != null) {
+                throw new InvalidTokenException("duplicate field " + m.group(1)); // no last-one-wins ambiguity
+            }
         }
         return fields;
     }
diff --git a/docs-service/src/main/java/com/acme/docs/PermissionCache.java b/docs-service/src/main/java/com/acme/docs/PermissionCache.java
index caa977e..3fab6d4 100644
--- a/docs-service/src/main/java/com/acme/docs/PermissionCache.java
+++ b/docs-service/src/main/java/com/acme/docs/PermissionCache.java
@@ -2,17 +2,26 @@ package com.acme.docs;
 
 import java.util.Map;
 import java.util.Set;
+import java.util.concurrent.CompletableFuture;
+import java.util.concurrent.CompletionException;
 import java.util.concurrent.ConcurrentHashMap;
+import java.util.concurrent.ThreadLocalRandom;
 
-/** Keeps permission-service off the hot path: each user's permissions are cached for a TTL. */
+/**
+ * Permission cache keyed by (tenant, user): one in-flight load per key, jittered expiry, and it never fails open.
+ * During a permission-service outage it serves last-known permissions for a bounded time, then refuses (503).
+ */
 public final class PermissionCache {
-    private record Entry(Set<String> permissions, long expiresAt) {}
+    private record Key(String tenantId, String userId) {}
 
-    private static final Set<String> FALLBACK = Set.of("doc:read"); // read-only while permission-service is down
+    private record Entry(Set<String> permissions, long loadedAt, long expiresAt) {}
+
+    private static final long MAX_STALE_MILLIS = 5 * 60_000;
 
     private final PermissionClient client;
     private final long ttlMillis;
-    private final Map<String, Entry> entries = new ConcurrentHashMap<>();
+    private final Map<Key, Entry> entries = new ConcurrentHashMap<>();
+    private final Map<Key, CompletableFuture<Entry>> loads = new ConcurrentHashMap<>();
 
     public PermissionCache(PermissionClient client, long ttlMillis) {
         this.client = client;
@@ -20,15 +29,34 @@ public final class PermissionCache {
     }
 
     public Set<String> permissions(String tenantId, String userId) {
-        Entry e = entries.get(userId);
-        if (e == null || e.expiresAt() < System.currentTimeMillis()) {
+        Key key = new Key(tenantId, userId);
+        long now = System.currentTimeMillis();
+        Entry cached = entries.get(key);
+        if (cached != null && now < cached.expiresAt()) {
+            return cached.permissions();
+        }
+        CompletableFuture<Entry> mine = new CompletableFuture<>();
+        CompletableFuture<Entry> inFlight = loads.putIfAbsent(key, mine);
+        if (inFlight == null) { // this caller loads; concurrent misses for the same key wait on it
+            inFlight = mine;
             try {
-                e = new Entry(client.fetch(tenantId, userId), System.currentTimeMillis() + ttlMillis);
-                entries.put(userId, e);
-            } catch (RuntimeException ex) {
-                return FALLBACK; // fail soft: an outage should not take reads down
+                long jitter = ThreadLocalRandom.current().nextLong(ttlMillis / 10 + 1); // spread expiries apart
+                Entry fresh = new Entry(client.fetch(tenantId, userId), now, now + ttlMillis + jitter);
+                entries.put(key, fresh);
+                mine.complete(fresh);
+            } catch (RuntimeException e) {
+                mine.completeExceptionally(e);
+            } finally {
+                loads.remove(key);
+            }
+        }
+        try {
+            return inFlight.join().permissions();
+        } catch (CompletionException e) {
+            if (cached != null && now - cached.loadedAt() < MAX_STALE_MILLIS) {
+                return cached.permissions(); // last known, bounded staleness
             }
+            throw new PermissionServiceUnavailableException(e.getCause());
         }
-        return e.permissions();
     }
 }
diff --git a/docs-service/src/main/java/com/acme/docs/PermissionServiceUnavailableException.java b/docs-service/src/main/java/com/acme/docs/PermissionServiceUnavailableException.java
new file mode 100644
index 0000000..7cbcc2a
--- /dev/null
+++ b/docs-service/src/main/java/com/acme/docs/PermissionServiceUnavailableException.java
@@ -0,0 +1,10 @@
+package com.acme.docs;
+
+/** Authorization could not be decided (maps to HTTP 503). Never treated as "allowed". */
+public class PermissionServiceUnavailableException extends RuntimeException {
+    private static final long serialVersionUID = 1L;
+
+    public PermissionServiceUnavailableException(Throwable cause) {
+        super("permission-service unavailable", cause);
+    }
+}
diff --git a/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java b/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java
index 241020b..a77e79d 100644
--- a/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java
+++ b/docs-service/src/test/java/com/acme/docs/DocumentApiTest.java
@@ -2,47 +2,64 @@ package com.acme.docs;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
 
+import java.util.HashMap;
+import java.util.Map;
 import java.util.Set;
 import org.junit.jupiter.api.BeforeEach;
 import org.junit.jupiter.api.Test;
 
 class DocumentApiTest {
     private final DocumentStore docs = new DocumentStore();
-    private final FakePermissions perms = new FakePermissions(0).grant("acme", "alice", Set.of("doc:read"));
+    private final FakePermissions perms = new FakePermissions(0).grant("acme", "alice", Set.of("doc:read"))
+            .grant("acme", "u42", Set.of("doc:read"));
     private final DocumentApi api = new DocumentApi(new JwtVerifier(Tokens.KEY), new PermissionCache(perms, 60_000), docs);
 
     @BeforeEach
     void seed() {
         docs.put("acme", "d1", "Q3 plan");
+        docs.put("globex", "g1", "globex roadmap");
+    }
+
+    private String bearer(Map<String, Object> claims) {
+        return "Bearer " + Tokens.hs256(claims);
     }
 
     @Test
     void validTokenReadsDocument() {
-        String token = Tokens.hs256(Tokens.claims("alice", "acme", Tokens.inOneHour()));
-        assertEquals(new DocumentApi.Response(200, "Q3 plan"), api.getDocument("Bearer " + token, "acme", "d1"));
+        assertEquals(new DocumentApi.Response(200, "Q3 plan"),
+                api.getDocument(bearer(Tokens.claims("alice", "acme", Tokens.inOneHour())), "acme", "d1"));
+    }
+
+    @Test
+    void unsignedTokenIsRejected() {
+        String forged = Tokens.unsigned(Tokens.claims("alice", "acme", Tokens.inOneHour()));
+        assertEquals(401, api.getDocument("Bearer " + forged, "acme", "d1").status());
     }
 
     @Test
-    void missingTokenIsUnauthorized() {
-        assertEquals(401, api.getDocument(null, "acme", "d1").status());
+    void tenantComesFromTheTokenNotTheHeader() {
+        assertEquals(403, api.getDocument(bearer(Tokens.claims("u42", "globex", Tokens.inOneHour())), "acme", "d1").status());
     }
 
     @Test
-    void tamperedTokenIsUnauthorized() {
-        String[] alice = Tokens.hs256(Tokens.claims("alice", "acme", Tokens.inOneHour())).split("\\.");
-        String[] admin = Tokens.hs256(Tokens.claims("admin", "acme", Tokens.inOneHour())).split("\\.");
-        assertEquals(401, api.getDocument("Bearer " + alice[0] + "." + admin[1] + "." + alice[2], "acme", "d1").status());
+    void cacheEntriesArePerTenant() {
+        api.getDocument(bearer(Tokens.claims("u42", "acme", Tokens.inOneHour())), "acme", "d1");
+        assertEquals(403, api.getDocument(bearer(Tokens.claims("u42", "globex", Tokens.inOneHour())), "globex", "g1").status());
     }
 
     @Test
-    void expiredTokenIsUnauthorized() {
-        String token = Tokens.hs256(Tokens.claims("alice", "acme", 1_700_000_000L));
-        assertEquals(401, api.getDocument("Bearer " + token, "acme", "d1").status());
+    void permissionOutageFailsClosed() {
+        perms.down = true;
+        assertEquals(503, api.getDocument(bearer(Tokens.claims("alice", "acme", Tokens.inOneHour())), "acme", "d1").status());
     }
 
     @Test
-    void nonReaderIsForbidden() {
-        String token = Tokens.hs256(Tokens.claims("bob", "acme", Tokens.inOneHour()));
-        assertEquals(403, api.getDocument("Bearer " + token, "acme", "d1").status());
+    void tokenWithoutExpOrForAnotherAudienceIsRejected() {
+        Map<String, Object> noExp = new HashMap<>(Tokens.claims("alice", "acme", Tokens.inOneHour()));
+        noExp.remove("exp");
+        Map<String, Object> analytics = new HashMap<>(Tokens.claims("alice", "acme", Tokens.inOneHour()));
+        analytics.put("aud", "analytics");
+        assertEquals(401, api.getDocument(bearer(noExp), "acme", "d1").status());
+        assertEquals(401, api.getDocument(bearer(analytics), "acme", "d1").status());
     }
 }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F1 | Signature skipped unless `alg` starts with `HS` | Sev-1 (5) | 2 | L6+ (L5s see "signature check" and stop) |
| F2 | Tenant from header | Sev-1 (5) | 10 | L6+ (requires the gateway context) |
| F3 | Cache key without tenant | Sev-1 (5) | 10 | L6+ (requires knowing ids are per-tenant) |
| F4 | Fail-open fallback | Sev-1 (5) | 2 | L5+ |
| F5 | Stampede | Sev-2 (3) | 10 | L5+ |
| F6 | Missing `exp` accepted | Sev-2 (3) | 2 | L6+ |
| F7 | No `aud`/`iss` | Sev-2 (3) | 10 | L6+ |
| F8 | Timing-unsafe comparison | Sev-3 (1) | 2 | L5+ (often found first, which is the trap) |

Total **30**. A common L5 pattern is to lead with F8 (it's a famous rule), then F5, and miss F2 and F3 entirely. An L7 leads with the trust-boundary move ("the gateway is gone, so what did it do for us?"), which surfaces F1 and F2 in the first five minutes, and then asks what a user id *is* (F3).

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| Reviewing the verifier, not the boundary | Detailed comments on base64 handling | Misses that the gateway's guarantees disappeared (F1, F2) |
| Rule-first review | "Use constant-time compare" as the headline | Sev-3 first, Sev-1s later or never |
| Assuming global ids | "Cache by user id, good" | Ids repeat per tenant (F3) |
| Treating fail-open as resilience | "Nice, reads keep working in an outage" | Authorization degraded to "allow" (F4) |
| Fixing F2 by validating the header against the token | `if (!header.equals(tid)) 403` | Works, but leaves two sources of truth; simpler to ignore the header |
| "Just use a JWT library" as the whole review | One comment, no specifics | Libraries also need the algorithm allow-list, `aud`, `exp` policy and tenant source configured |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "The author says RS256 tokens are validated at the gateway. Why is F1 your top finding?"</b></summary>

**Initial Prompt.** Context change as the root cause.

**L5 Answer.** "Because alg none is a well-known JWT vulnerability."

**Why L5 Stalls.** True, but it doesn't explain why *this* code is exploitable. The author will reply that the gateway handles it.

**L7 Answer.** "The ticket's purpose is that internal traffic no longer passes the gateway. So the comment on line 30 describes the old architecture, and in the new one an RS256, `none` or alg-less token is returned unverified. I'd ask the author to pin HS256 now and add RS256 verification here *before* the gateway is removed for any caller, not after."

</details>

<details><summary><b>Q2 · "Isn't checking the X-Tenant-Id header against the token's tid enough for F2?"</b></summary>

**Initial Prompt.** Alternative fix.

**L5 Answer.** "Yes, reject the request if they differ."

**Why L5 Stalls.** It closes the hole but keeps a second source of truth that every future endpoint must remember to cross-check.

**L7 Answer.** "It closes the hole, but I'd rather the header not exist as an input at all. Take the tenant from `tid`, ignore the header, and later remove it from the client contract. A mismatch check is fine as a temporary *alarm* during migration, to find callers sending the wrong header, but the decision should come from the token alone."

</details>

<details><summary><b>Q3 · "Permission-service had a 20-minute outage last quarter. Isn't fail-open the business-friendly choice?"</b></summary>

**Initial Prompt.** Availability vs security trade-off.

**L5 Answer.** "Maybe. Read access is less dangerous than write access."

**Why L5 Stalls.** "Read" here means acquisition plans and HR documents, and the fallback ignores *who* is asking: revoked users included.

**L7 Answer.** "Fail-open on authorization turns every permission-service outage into a data-exposure incident, and it gives attackers a reason to cause one. The trade-off I'd offer: serve each user's *own* last-known permissions for a bounded window (5 minutes covers most blips), then 503. A 20-minute outage still degrades, but nobody gains access they didn't have. Product can pick the window; the default grant is not on the menu."

</details>

<details><summary><b>Q4 · "How would you prove the stampede before production?"</b></summary>

**Initial Prompt.** Evidence for a load property.

**L5 Answer.** "Load test permission-service."

**Why L5 Stalls.** A steady-state load test with warm caches never shows synchronized expiry.

**L7 Answer.** "A focused test: a slow fake backend, warm one key, let it expire, release 100 threads at once on a barrier, and count backend calls. The P5 probe does exactly that: 100 calls on the PR, 1 with single-flight. In production, graph backend QPS against cache-miss rate. A sawtooth every TTL interval is the signature of synchronized expiry, and jitter flattens it."

</details>

<details><summary><b>Q5 · "RFC 7519 says exp is optional. Why is F6 a defect?"</b></summary>

**Initial Prompt.** Standards vs policy.

**L5 Answer.** "Because tokens should expire."

**Why L5 Stalls.** Correct instinct, no argument. The author can cite the RFC back.

**L7 Answer.** "The RFC defines what a JWT *may* contain; our threat model defines what we accept. A bearer token without `exp` is a permanent credential revocable only by rotating a key shared by every internal service. Requiring `exp` (and a maximum lifetime) is a policy the verifier must enforce. The support tool should mint short-lived tokens, and that's a separate ticket I'd file."

</details>

<details><summary><b>Q6 · "Why does the shared HMAC key make F7 worse, and what's the long-term fix?"</b></summary>

**Initial Prompt.** Key management depth.

**L5 Answer.** "Because any service can forge tokens."

**Why L5 Stalls.** Partly right: with symmetric keys, every verifier can also *mint*. That's a bigger point than F7, and it needs a plan.

**L7 Answer.** "Two problems. Without an `aud` check, a token for any service works here (F7, which the fix closes). Deeper: with one shared HMAC key, every service that can verify can also mint tokens for every other service, so a compromise of analytics-api is a compromise of auth for everyone. Long term, auth-service signs with an asymmetric key (RS256/ES256) published via JWKS, and services hold only the public key. That's the Q3 migration, and this verifier should be built to switch to it."

</details>

<details><summary><b>Q7 · "Your fix serves stale permissions for 5 minutes. A user's access was revoked 2 minutes ago. Is that acceptable?"</b></summary>

**Initial Prompt.** Revocation latency.

**L5 Answer.** "It's only 5 minutes."

**Why L5 Stalls.** Treats revocation latency as negligible without asking the business. For some revocations (an employee termination) minutes matter.

**L7 Answer.** "Revocation latency is already up to the TTL in normal operation, since the cache serves 5-minute-old grants by design. The stale window only extends that during an outage, bounded. If security needs faster revocation, push it: permission-service publishes revocation events and the cache evicts the key immediately. I'd confirm the acceptable window with security rather than pick it myself."

</details>

<details><summary><b>Q8 · "Rank the findings for a security review board."</b></summary>

**Initial Prompt.** Prioritization by exploitability.

**L5 Answer.** "Alg none, then timing attack, then the rest."

**Why L5 Stalls.** Timing is the least exploitable. Cross-tenant impersonation with valid credentials is the stealthiest.

**L7 Answer.** "F1 (anyone, any identity, no credentials), then F2 (any tenant user can act as the same-numbered user in another tenant with a *valid* token, which leaves the quietest logs), then F4 (outage turns into exposure, inducible), then F3 (accidental cross-tenant grants), then F7 and F6 (credential scope and lifetime), then F5 (availability, feeds F4), then F8. The first four are Sev-1. Ship nothing behind 'gateway removal' until they're fixed."

</details>

---

## 12. Checklist

- [ ] When a PR moves a trust boundary (gateway, sidecar, proxy removed), list what that component guaranteed, and re-check each guarantee.
- [ ] JWT: algorithm pinned by the verifier; signature verified before claims are trusted; `exp`, `aud`, `iss` required; constant-time comparison.
- [ ] Every identity attribute used for authorization comes from the credential, not from headers, paths or bodies.
- [ ] Cache keys include every component of the principal (tenant + user).
- [ ] Authorization failure modes: stale-bounded or 503, never a default grant.
- [ ] Hot-key caches: single-flight loads, jittered TTL, and a test that releases N threads at once after expiry.
- [ ] Tests include adversarial cases: unsigned, wrong audience, no `exp`, mismatched tenant, same user id in two tenants, dependency outage.

---

## 13. References

- IETF RFC 8725: *JSON Web Token Best Current Practices* (§2.1 "none", §3.1 algorithm verification, §3.9 audience). https://www.rfc-editor.org/rfc/rfc8725.html
- IETF RFC 7519: *JSON Web Token (JWT)* (§4.1.4 `exp`, §2 NumericDate). https://www.rfc-editor.org/rfc/rfc7519.html
- OWASP API Security Top 10 (2023): *API1:2023 Broken Object Level Authorization*. https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
- OWASP Top 10:2025. https://owasp.org/Top10/2025/
- Java SE 21 API: `MessageDigest.isEqual` (implementation note on timing). https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/security/MessageDigest.html
- MITRE CWE-347: Improper Verification of Cryptographic Signature. https://cwe.mitre.org/data/definitions/347.html
- MITRE CWE-639: Authorization Bypass Through User-Controlled Key. https://cwe.mitre.org/data/definitions/639.html
- MITRE CWE-636: Not Failing Securely ("Failing Open"). https://cwe.mitre.org/data/definitions/636.html
- Within this KB: [PR01](01-pr01-fintech-wallet-transfer-transactional-proxy-and-deadlock-traps.md) · [PR02](02-pr02-high-throughput-order-api-n-plus-1-connection-exhaustion-and-virtual-threads.md) · [01-02 Layer 6](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#8-layer-6-security-and-trust-boundaries) · [PR11 Confused deputy](../05-AI-Engineering-RAG-and-MCP-Server-PR-Simulations/02-pr11-mcp-tool-server-confused-deputy-and-non-idempotent-agent-retries.md)
