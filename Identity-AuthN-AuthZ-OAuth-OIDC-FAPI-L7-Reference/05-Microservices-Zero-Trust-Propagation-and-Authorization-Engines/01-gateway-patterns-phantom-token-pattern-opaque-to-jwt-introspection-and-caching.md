# Gateway Patterns: the Phantom Token, Opaque-to-JWT Introspection, and Caching

> Folder 05 · File 01 of 04 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Next: [02 · Token relay vs RFC 8693 token exchange, SPIFFE/SPIRE](02-east-west-propagation-token-relay-vs-rfc8693-token-exchange-and-spiffe-spire.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L34 `PhantomTokenLab.java` | RFC 7662's example introspection response parses from the fixture. Three gateways handle the same deterministic traffic: 10,000 requests, 50 tokens, one token revoked at t=100 s, and 3 internal services per request.<br>• **L5**, opaque-token relay: **37,090** introspection calls, since every hop introspects.<br>• **L6**, a raw-token cache with a 10-minute TTL: 50 calls, but the revoked token is still served **499 s** after revocation (970 requests).<br>• **L7**, hashed key, TTL = min(exp, 60 s), eviction on revocation events, 60-second phantom JWT per audience: **592** calls and **zero** exposure.<br><br>Internal services accept only the gateway-signed `at+jwt` for their own audience | RFC 7662 §2.2 (fixture); RFC 9068; RFC 9701 |
| L35 `SpringIntrospectionLab.java` | Spring Security 7.1.2's real `SpringOpaqueTokenIntrospector` against an RFC 7662 endpoint on 127.0.0.1. It checks only `active`, so it **accepts a token for another audience** and **an expired token**. It makes 3 calls for 3 requests (no cache), and a 2-second AS stall blocks the request thread for 2 s (no client timeout). A hardened wrapper on `RestClientOpaqueTokenIntrospector` validates `aud`/`exp`/`iss`, caches by hash, and fails within 1 s | spring-security 7.1.2; RFC 7662 §4 |

**Verification.** Compiled with Folders 01–05 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs both outputs and requires them byte-identical. L34's traffic uses a seeded `SplittableRandom(20261106)` on a fixed clock. L35's timing checks print booleans only. Spring behaviour marked [D] was read from `SpringOpaqueTokenIntrospector`: its comment says "relying solely on the authorization server to validate this token (not checking 'exp', for example)", and both builders use a default `RestTemplate`/`RestClient`. RFC 7662, 9068, 9701, 8693 and 8707 are in [`fixtures/`](fixtures/).

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

North-south and east-west traffic need different tokens:
- **At the edge:** the client's token should be opaque, revocable, meaningless if leaked, and small.
- **Inside:** services want a self-contained, signed, short-lived token they can verify locally, scoped to *them*.

The **phantom-token pattern** does the conversion at the gateway. The gateway introspects the opaque token once, caches the result for a bounded time, and mints a short-lived JWT per internal audience (RFC 9068 `at+jwt`). The external token never travels inside.

Results:
- **[M] Relaying an opaque token makes every hop an introspection client (L34 L5).** The cost is 4 calls per request and 37,090 for the run. It also leaves every service with a token that is valid at *every other* service.
- **[M] Caching is where revocation goes to die (L34 L6).** A cache keyed by the raw token, with a fixed 10-minute TTL that ignores `exp`, keeps serving a revoked token for 499 s. The raw token also sits in heap dumps as a cache key.
- **[M] The L7 gateway cuts calls 63× (592 vs 37,090) with zero revocation exposure (L34 L7):**
  - SHA-256 cache key;
  - TTL = min(exp, 60 s);
  - 5-second negative cache;
  - eviction on back-channel logout or CAEP `session-revoked` (Folder 03 file 03).
- **[M] Spring's stock introspector trusts the AS completely (L35).**
  - It validates only `active` (and treats the string `"true"` as true).
  - An `aud` of another API, or an `exp` an hour in the past, is accepted.
  - RFC 7662 says the AS "MAY respond differently to different protected resources". If your AS doesn't, any RS accepts any token the AS issued: the cross-API confused deputy.
  - No cache, and no client timeout by default. A stalled AS stalls every request thread.

---

## 1. First principles: one token outside, many tokens inside

```text
   Internet                       Edge                                  Mesh (east-west)
   --------                       ----                                  ----------------
   client --Authorization: Bearer opaque-7f..--> GATEWAY ------------->  orders    (aud=https://orders.internal,   exp 60 s)
                                                   |  introspect once     payments  (aud=https://payments.internal, exp 60 s)
                                                   |  (cached <= 60 s)    ledger    (aud=https://ledger.internal,   exp 60 s)
                                                   v
                                            AS /introspect (RFC 7662)     each service verifies the gateway's at+jwt locally
                                                                         (JWKS), checks aud == itself, never sees opaque-7f..

   leaked outside: opaque, revocable, introspection-only        leaked inside: one audience, <= 60 s, no refresh
```

Why opaque outside [E]:
- A JWT is readable by anyone who holds it: claims, PII, scope.
- It can't be revoked before `exp` without the RS calling home anyway.
- It grows with every claim, which matters for cookies and headers (file 03 of Folder 04).

Why JWT inside [E]: local verification at every hop, no AS dependency per call, and per-audience restriction.

The gateway is the single place that holds the external token. That makes it the right place for sender-constraint verification (DPoP or mTLS, Folder 04 file 01).

---

## 2. Introspection on the wire (RFC 7662), and its JWT form (RFC 9701)

```http
POST /introspect HTTP/1.1
Host: server.example.com
Accept: application/json
Content-Type: application/x-www-form-urlencoded
Authorization: Basic czZCaGRSa3F0MzpnWDFmQmF0M2JW

token=mF_9.B5f-4.1JqM&token_type_hint=access_token
```

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"active": true, "client_id": "l238j323ds-23ij4", "username": "jdoe", "scope": "read write dolphin", "sub": "Z5O3upPC88QrAjx00dis", "aud": "https://protected.example.net/resource", "iss": "https://server.example.com/", "exp": 1419356238, "iat": 1419350238, "extension_field": "twenty-seven"}
```

That is RFC 7662 §2.1–2.2's example. L34 parses the response from the fixture. The rules that matter [D unless marked]:
- **The caller must be authorized** to introspect (§2.1). An unauthenticated introspection endpoint is a token-scanning oracle.
- **`active: false` says nothing else.** The AS must not reveal why.
- **"The authorization server MAY respond differently to different protected resources making the same request"** (§2.2). Use this to answer `active: false` when the token's audience doesn't include the caller, so the AS enforces audience for you [E].
- **Caching** (§4): "A less aggressive cache with a short timeout will provide the protected resource with more up-to-date information … A more aggressive cache with a longer duration will minimize network traffic and load on the introspection endpoint, but at the risk of stale information about the token." The RFC's own example is the revoked token.
- **RFC 9701.** The response becomes a signed (optionally encrypted) JWT, `application/token-introspection+jwt`, when the RS must prove what the AS said (liability, audit) or when the answer passes through intermediaries.

```mermaid
sequenceDiagram
    autonumber
    participant C as Client / BFF
    participant G as Gateway
    participant AS as Authorization server
    participant S as payments service
    C->>G: POST /payments  Authorization: DPoP opaque-7f.. (+ proof)
    G->>G: verify DPoP proof (Folder 04); cache lookup by SHA-256(token)
    G->>AS: POST /introspect token=opaque-7f.. (client-authenticated)  [cache miss only]
    AS-->>G: {active: true, sub, scope, client_id, exp, cnf}
    G->>G: cache until min(exp, now+60 s); mint at+jwt aud=payments, exp 60 s
    G->>S: POST /payments  Authorization: Bearer <phantom at+jwt>
    S->>S: verify gateway signature (JWKS), typ at+jwt, aud == payments, exp
    S-->>G: 201
    G-->>C: 201
    Note over AS,G: revocation / CAEP session-revoked -> gateway evicts the cache entry immediately
```

---

## 3. L34: relay vs naive cache vs phantom token

<!-- listing:PhantomTokenLab.java -->
```java
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.SplittableRandom;

/**
 * L34 - the phantom-token pattern: opaque tokens outside, short-lived audience-bound JWTs inside.
 *
 * <ul>
 *   <li>Oracle: RFC 7662 section 2.2's introspection response parses from the fixture; RFC 9701's JWT response type
 *       and RFC 9068's at+jwt are cited;</li>
 *   <li>three gateways over the same deterministic traffic (10,000 requests, 50 tokens, one revoked at t=100 s,
 *       each request fanning out to 3 internal services): L5 relays the opaque token (every hop introspects), L6
 *       caches introspection by raw token for 10 min, L7 caches by SHA-256 with TTL = min(exp, 60 s), evicts on
 *       revocation events, caches negatives briefly, and mints a 60-second phantom JWT per audience;</li>
 *   <li>what internal services accept: only the gateway's at+jwt for their own audience.</li>
 * </ul>
 */
public final class PhantomTokenLab {
    static final long T0 = 1_767_225_600L;
    static final List<String> SERVICES = List.of("orders", "payments", "ledger");

    record Grant(String sub, String clientId, String scope, long exp, boolean[] revoked) {
    }

    static final class AuthorizationServer {
        final Map<String, Grant> grants = new HashMap<>();
        int introspections;

        /** RFC 7662 section 2.2 response for the token at time t. */
        Map<String, Object> introspect(String token, long t) {
            introspections++;
            Grant g = grants.get(token);
            Map<String, Object> r = new LinkedHashMap<>();
            if (g == null || g.revoked()[0] || g.exp() <= t) {
                r.put("active", false);
                return r;
            }
            r.put("active", true);
            r.put("client_id", g.clientId());
            r.put("scope", g.scope());
            r.put("sub", g.sub());
            r.put("aud", "https://api.bank.example");
            r.put("iss", "https://as.bank.example");
            r.put("exp", g.exp());
            return r;
        }
    }

    record CacheEntry(Map<String, Object> result, long until) {
    }

    static final class Gateway {
        final String kind;
        final AuthorizationServer as;
        final Jose.Jwk signer;
        final Map<String, CacheEntry> cache = new HashMap<>();
        int revokedAccepted;
        long lastRevokedAcceptedAt = -1;

        Gateway(String kind, AuthorizationServer as, Jose.Jwk signer) {
            this.kind = kind;
            this.as = as;
            this.signer = signer;
        }

        Map<String, Object> lookup(String token, long t) {
            String key = kind.equals("L7") ? KbSupport.b64u(Jose.sha256(token.getBytes(StandardCharsets.US_ASCII))) : token;
            CacheEntry e = cache.get(key);
            if (e != null && e.until() > t) {
                return e.result();
            }
            Map<String, Object> r = as.introspect(token, t);
            boolean active = Boolean.TRUE.equals(r.get("active"));
            long ttl = switch (kind) {
                case "L6" -> 600;                                                        // fixed 10 min, ignores exp
                case "L7" -> active ? Math.min(((Number) r.get("exp")).longValue() - t, 60) : 5; // bounded; short negative
                default -> 0;
            };
            if (ttl > 0) {
                cache.put(key, new CacheEntry(r, t + ttl));
            }
            return r;
        }

        /** A revocation event (back-channel logout, CAEP session-revoked, RFC 7009 webhook) reaching the gateway. */
        void onRevoked(String token) {
            if (kind.equals("L7")) {
                cache.remove(KbSupport.b64u(Jose.sha256(token.getBytes(StandardCharsets.US_ASCII))));
            }
        }

        /** Handle one external request; returns what reaches each internal service. */
        List<String> handle(String token, long t, boolean tokenIsRevoked) {
            List<String> forwarded = new ArrayList<>();
            if (kind.equals("L5")) { // relay: gateway and every service introspect the same opaque token
                for (int hop = 0; hop <= SERVICES.size(); hop++) {
                    if (!Boolean.TRUE.equals(as.introspect(token, t).get("active"))) {
                        return List.of();
                    }
                }
                SERVICES.forEach(s -> forwarded.add(token));
                return forwarded;
            }
            Map<String, Object> r = lookup(token, t);
            if (!Boolean.TRUE.equals(r.get("active"))) {
                return List.of();
            }
            if (tokenIsRevoked) {
                revokedAccepted++;
                lastRevokedAcceptedAt = t;
            }
            for (String s : SERVICES) { // phantom token: one per audience, 60 s, signed by the gateway
                Map<String, Object> h = new LinkedHashMap<>();
                h.put("typ", "at+jwt");
                h.put("alg", "ES256");
                h.put("kid", "gw-1");
                Map<String, Object> c = new LinkedHashMap<>();
                c.put("iss", "https://gateway.internal");
                c.put("sub", r.get("sub"));
                c.put("aud", "https://" + s + ".internal");
                c.put("client_id", r.get("client_id"));
                c.put("scope", r.get("scope"));
                c.put("iat", t);
                c.put("exp", t + 60);
                c.put("jti", "p-" + t + "-" + s);
                forwarded.add(Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), signer));
            }
            return forwarded;
        }
    }

    /** What an internal service accepts: the gateway's at+jwt, for ITS audience, unexpired. */
    static String internalAccepts(String service, String presented, Jose.Jwk gatewayKey, long t) {
        if (!presented.startsWith("eyJ")) {
            return "reject: not a gateway-issued JWT";
        }
        Jose.Parts p = Jose.parse(presented);
        if (!"at+jwt".equals(p.header().get("typ")) || !Jose.rawVerify("ES256", gatewayKey, p.signingInput(), p.sig())) {
            return "reject: typ or signature";
        }
        Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
        if (!("https://" + service + ".internal").equals(c.get("aud"))) {
            return "reject: aud " + c.get("aud");
        }
        if (((Number) c.get("exp")).longValue() < t) {
            return "reject: expired";
        }
        return "accept";
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String r7662 = KbSupport.rfc(fx, "rfc7662.txt");
        String r9701 = KbSupport.rfc(fx, "rfc9701.txt");
        String r9068 = KbSupport.rfc(fx, "rfc9068.txt");

        KbSupport.section("Oracles (fixtures)");
        int a = r7662.indexOf("\"active\": true");
        int s0 = r7662.lastIndexOf("{", a);
        int depth = 0;
        int end = s0;
        for (int k = s0; k < r7662.length(); k++) {
            depth += r7662.charAt(k) == '{' ? 1 : r7662.charAt(k) == '}' ? -1 : 0;
            if (depth == 0) {
                end = k + 1;
                break;
            }
        }
        Map<String, Object> example = MiniJson.object(r7662.substring(s0, end));
        KbSupport.check("RFC 7662 section 2.2 example response parses: " + example, Boolean.TRUE.equals(example.get("active"))
                && "l238j323ds-23ij4".equals(example.get("client_id")) && ((Number) example.get("exp")).longValue() == 1_419_356_238L);
        KbSupport.mustCite(r9701, "application/token-introspection+jwt", "RFC 9701 section 4");
        KbSupport.mustCite(r9068, "at+jwt", "RFC 9068 section 2.1");
        KbSupport.mustCite(r7662, "The authorization server MAY respond differently to different protected resources", "RFC 7662 section 2.2");

        KbSupport.section("Same traffic, three gateways: 10,000 requests over 600 s, 50 tokens, token #7 revoked at t=100 s");
        SecureRandom rng = new SecureRandom();
        Jose.Jwk gwKey = Jose.generate("ES256", rng);
        Map<String, int[]> calls = new LinkedHashMap<>();
        Map<String, Long> exposure = new LinkedHashMap<>();
        int revokedRequests = 0;
        for (String kind : new String[] {"L5", "L6", "L7"}) {
            AuthorizationServer as = new AuthorizationServer();
            List<String> tokens = new ArrayList<>();
            for (int i = 0; i < 50; i++) {
                String tok = "opaque-" + i;
                tokens.add(tok);
                as.grants.put(tok, new Grant("user-" + i, "web-bff", "accounts payments", T0 + 3_600, new boolean[1]));
            }
            Gateway gw = new Gateway(kind, as, gwKey);
            SplittableRandom traffic = new SplittableRandom(20_261_106L);
            for (int n = 0; n < 10_000; n++) {
                long t = T0 + (long) n * 600 / 10_000;
                if (t == T0 + 100 && !as.grants.get("opaque-7").revoked()[0]) {
                    as.grants.get("opaque-7").revoked()[0] = true;
                    gw.onRevoked("opaque-7");
                }
                int idx = n % 10 == 0 ? 7 : traffic.nextInt(50);
                if (kind.equals("L5") && idx == 7 && t >= T0 + 100) {
                    revokedRequests++;
                }
                gw.handle(tokens.get(idx), t, idx == 7 && t >= T0 + 100);
            }
            calls.put(kind, new int[] {as.introspections});
            exposure.put(kind, gw.lastRevokedAcceptedAt < 0 ? 0 : gw.lastRevokedAcceptedAt - (T0 + 100));
            KbSupport.info("%-3s introspection calls %6d | requests with the revoked token still served: %4d (last at revocation + %d s)",
                    kind, as.introspections, gw.revokedAccepted, exposure.get(kind));
        }
        KbSupport.check("L5 relay: gateway + 3 services introspect every live request (4 calls); the " + revokedRequests
                + " revoked-token requests stop at the gateway (1 call)", calls.get("L5")[0] == (10_000 - revokedRequests) * 4 + revokedRequests);
        KbSupport.check("L6 (raw-token key, 10-min TTL) cuts calls to 50 but serves the revoked token for the rest of the run",
                calls.get("L6")[0] == 50 && exposure.get("L6") >= 490);
        KbSupport.check("L7 (hashed key, min(exp, 60 s), eviction on revocation): a few hundred calls and zero exposure",
                calls.get("L7")[0] < 1_000 && exposure.get("L7") == 0);

        KbSupport.section("What the internal services accept (phantom tokens issued by the L7 gateway)");
        Gateway gw7 = new Gateway("L7", new AuthorizationServer(), gwKey);
        gw7.as.grants.put("opaque-x", new Grant("alice", "web-bff", "accounts", T0 + 3_600, new boolean[1]));
        List<String> minted = gw7.handle("opaque-x", T0, false);
        Jose.Jwk forger = Jose.generate("ES256", rng);
        Map<String, Object> fh = new LinkedHashMap<>();
        fh.put("typ", "at+jwt");
        fh.put("alg", "ES256");
        String forged = Jose.sign(fh, MiniJson.write(Map.of("aud", "https://payments.internal", "sub", "alice", "exp", T0 + 60)).getBytes(StandardCharsets.UTF_8), forger);
        String[][] rows = {
            {"payments receives ITS phantom token", internalAccepts("payments", minted.get(1), gwKey, T0 + 5)},
            {"orders' phantom token replayed at payments", internalAccepts("payments", minted.get(0), gwKey, T0 + 5)},
            {"payments' phantom token 61 s later", internalAccepts("payments", minted.get(1), gwKey, T0 + 61)},
            {"the external opaque token sent straight to payments", internalAccepts("payments", "opaque-x", gwKey, T0 + 5)},
            {"a JWT signed by someone else (typ at+jwt, right aud)", internalAccepts("payments", forged, gwKey, T0 + 5)}};
        int accepted = 0;
        for (String[] r : rows) {
            accepted += r[1].equals("accept") ? 1 : 0;
            KbSupport.info("%-56s -> %s", r[0], r[1]);
        }
        KbSupport.check("only the gateway-signed, audience-matched, unexpired token is accepted", accepted == 1 && rows[0][1].equals("accept"));
        KbSupport.verdict();
    }
}
```

<!-- output:PhantomTokenLab.java -->
```text

== Oracles (fixtures)
  [PASS] RFC 7662 section 2.2 example response parses: {active=true, client_id=l238j323ds-23ij4, username=jdoe, scope=read write dolphin, sub=Z5O3upPC88QrAjx00dis, aud=https://protected.example.net/resource, iss=https://server.example.com/, exp=1419356238, iat=1419350238, extension_field=twenty-seven}
  [PASS] constant cited verbatim from fixture: RFC 9701 section 4
  [PASS] constant cited verbatim from fixture: RFC 9068 section 2.1
  [PASS] constant cited verbatim from fixture: RFC 7662 section 2.2

== Same traffic, three gateways: 10,000 requests over 600 s, 50 tokens, token #7 revoked at t=100 s
  L5  introspection calls  37090 | requests with the revoked token still served:    0 (last at revocation + 0 s)
  L6  introspection calls     50 | requests with the revoked token still served:  970 (last at revocation + 499 s)
  L7  introspection calls    592 | requests with the revoked token still served:    0 (last at revocation + 0 s)
  [PASS] L5 relay: gateway + 3 services introspect every live request (4 calls); the 970 revoked-token requests stop at the gateway (1 call)
  [PASS] L6 (raw-token key, 10-min TTL) cuts calls to 50 but serves the revoked token for the rest of the run
  [PASS] L7 (hashed key, min(exp, 60 s), eviction on revocation): a few hundred calls and zero exposure

== What the internal services accept (phantom tokens issued by the L7 gateway)
  payments receives ITS phantom token                      -> accept
  orders' phantom token replayed at payments               -> reject: aud https://orders.internal
  payments' phantom token 61 s later                       -> reject: expired
  the external opaque token sent straight to payments      -> reject: not a gateway-issued JWT
  a JWT signed by someone else (typ at+jwt, right aud)     -> reject: typ or signature
  [PASS] only the gateway-signed, audience-matched, unexpired token is accepted

verdict: OK (8 checks)
```

The revocation timelines L34 measured:

```text
  t=0 s             t=100 s: token #7 revoked             t=160 s                              t=600 s
  |-----------------|-------------------------------------|------------------------------------|
  L5 relay          denied at the next request (every hop introspects; 37,090 calls for the run)
  L6 raw cache      [====== cached "active: true" keeps serving token #7: 970 requests ========] last at +499 s
  L7 + events       evicted by the revocation event -> next request introspects -> active:false (0 requests)
  L7, no events     [== at most the 60 s TTL ==]  (the bound you promise in the revocation SLO)
```

Reading the run:
- **The L6 failure is the common one.** "We added a cache and latency dropped" ships with a TTL chosen for hit rate, not for revocation. The bound must be **min(exp, your revocation SLO)**, and a revocation *event* must evict the entry.
- **Negative caching (5 s)** stops a stream of junk tokens from becoming an introspection flood against the AS [E].
- **The phantom token's `aud` is the control internal services actually enforce.** It is why a compromised `orders` can't replay its token at `payments` (L34's last section). File 02 builds the east-west half of this with token exchange and workload identity.

---

## 4. L35: Spring Security 7.1.2's introspector, run for real

<!-- listing:SpringIntrospectionLab.java -->
```java
import java.io.ByteArrayOutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import com.sun.net.httpserver.HttpServer;

import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2AuthenticatedPrincipal;
import org.springframework.security.oauth2.server.resource.introspection.BadOpaqueTokenException;
import org.springframework.security.oauth2.server.resource.introspection.OAuth2IntrospectionException;
import org.springframework.security.oauth2.server.resource.introspection.OpaqueTokenIntrospector;
import org.springframework.security.oauth2.server.resource.introspection.RestClientOpaqueTokenIntrospector;
import org.springframework.security.oauth2.server.resource.introspection.SpringOpaqueTokenIntrospector;
import org.springframework.web.client.RestClient;

/**
 * L35 - Spring Security 7.1.2's opaque-token introspection, run for real against an RFC 7662 endpoint served by
 * {@code com.sun.net.httpserver} on 127.0.0.1: what {@link SpringOpaqueTokenIntrospector} validates (only
 * {@code active}), how often it calls the AS (every request), what happens when the AS stalls (the default client
 * waits), and a hardened decorator (audience, expiry, issuer, bounded hashed cache, client timeouts) built on
 * {@link RestClientOpaqueTokenIntrospector}.
 */
public final class SpringIntrospectionLab {
    static final String SELF = "https://payments.internal";
    static final AtomicInteger CALLS = new AtomicInteger();

    static String respond(String token) throws InterruptedException {
        long now = Instant.now().getEpochSecond();
        return switch (token) {
            case "ok" -> "{\"active\":true,\"sub\":\"alice\",\"client_id\":\"web-bff\",\"scope\":\"payments\",\"aud\":\"" + SELF
                    + "\",\"iss\":\"https://as.bank.example\",\"exp\":" + (now + 300) + "}";
            case "other-aud" -> "{\"active\":true,\"sub\":\"alice\",\"scope\":\"payments\",\"aud\":\"https://hr.internal\",\"iss\":\"https://as.bank.example\",\"exp\":"
                    + (now + 300) + "}";
            case "expired" -> "{\"active\":true,\"sub\":\"alice\",\"scope\":\"payments\",\"aud\":\"" + SELF + "\",\"iss\":\"https://as.bank.example\",\"exp\":"
                    + (now - 3_600) + "}";
            case "string-true" -> "{\"active\":\"true\",\"sub\":\"alice\",\"aud\":\"" + SELF + "\",\"iss\":\"https://as.bank.example\",\"exp\":" + (now + 300) + "}";
            case "slow" -> {
                Thread.sleep(2_000);
                yield "{\"active\":true,\"sub\":\"alice\",\"aud\":\"" + SELF + "\",\"iss\":\"https://as.bank.example\",\"exp\":" + (now + 300) + "}";
            }
            default -> "{\"active\":false}";
        };
    }

    /** The L7 wrapper: validate what Spring leaves to the AS, cache by hash with a bounded TTL. */
    static final class HardenedIntrospector implements OpaqueTokenIntrospector {
        record Entry(OAuth2AuthenticatedPrincipal principal, Instant until) {
        }

        final OpaqueTokenIntrospector delegate;
        final Map<String, Entry> cache = new ConcurrentHashMap<>();

        HardenedIntrospector(OpaqueTokenIntrospector delegate) {
            this.delegate = delegate;
        }

        @Override
        public OAuth2AuthenticatedPrincipal introspect(String token) {
            String key = KbSupport.b64u(Jose.sha256(token.getBytes(StandardCharsets.US_ASCII)));
            Instant now = Instant.now();
            Entry e = cache.get(key);
            if (e != null && e.until().isAfter(now)) {
                return e.principal();
            }
            OAuth2AuthenticatedPrincipal p = delegate.introspect(token);
            Object aud = p.getAttribute("aud");
            Instant exp = p.getAttribute("exp");
            if (!(aud instanceof List<?> l && l.contains(SELF))) {
                throw new BadOpaqueTokenException("audience " + aud + " does not include " + SELF);
            }
            if (exp == null || !exp.isAfter(now)) {
                throw new BadOpaqueTokenException("token expired at " + exp);
            }
            Object iss = p.getAttribute("iss"); // bind to Object first: String.valueOf(<A> A) would pick valueOf(char[])
            if (!"https://as.bank.example".equals(String.valueOf(iss))) {
                throw new BadOpaqueTokenException("issuer");
            }
            Instant until = now.plusSeconds(60).isBefore(exp) ? now.plusSeconds(60) : exp;
            cache.put(key, new Entry(p, until));
            return p;
        }
    }

    static String run(OpaqueTokenIntrospector i, String token) {
        try {
            OAuth2AuthenticatedPrincipal p = i.introspect(token);
            return "accepted (sub=" + p.getName() + ", aud=" + p.getAttribute("aud") + ")";
        } catch (BadOpaqueTokenException e) {
            return "rejected: " + e.getMessage().replaceAll("[0-9]{4}-[0-9]{2}-[0-9T:.]+Z", "<t>");
        } catch (OAuth2IntrospectionException e) {
            return "error: " + e.getClass().getSimpleName();
        } catch (AuthenticationException e) {
            return "auth error: " + e.getMessage();
        }
    }

    public static void main(String[] args) throws Exception {
        HttpServer as = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        as.setExecutor(java.util.concurrent.Executors.newFixedThreadPool(4));
        as.createContext("/introspect", ex -> {
            CALLS.incrementAndGet();
            ByteArrayOutputStream body = new ByteArrayOutputStream();
            ex.getRequestBody().transferTo(body);
            String form = body.toString(StandardCharsets.UTF_8);
            String token = URLDecoder.decode(form.replaceAll(".*token=([^&]*).*", "$1"), StandardCharsets.UTF_8);
            byte[] out;
            try {
                out = respond(token).getBytes(StandardCharsets.UTF_8);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                out = new byte[0];
            }
            ex.getResponseHeaders().add("Content-Type", "application/json");
            ex.sendResponseHeaders(200, out.length);
            ex.getResponseBody().write(out);
            ex.close();
        });
        as.start();
        String uri = "http://127.0.0.1:" + as.getAddress().getPort() + "/introspect";
        try {
            KbSupport.section("Stock SpringOpaqueTokenIntrospector (builder: RestTemplate + basic auth, default request factory)");
            OpaqueTokenIntrospector stock = SpringOpaqueTokenIntrospector.withIntrospectionUri(uri).clientId("payments-rs").clientSecret("s3cr3t").build();
            String[][] rows = {{"active, aud = this resource server", run(stock, "ok")}, {"active, aud = https://hr.internal", run(stock, "other-aud")},
                {"active, but exp one hour ago", run(stock, "expired")}, {"\"active\": \"true\" (a string)", run(stock, "string-true")},
                {"\"active\": false", run(stock, "revoked")}};
            for (String[] r : rows) {
                KbSupport.info("%-40s -> %s", r[0], r[1]);
            }
            int before = CALLS.get();
            for (int i = 0; i < 3; i++) {
                stock.introspect("ok");
            }
            int stockCalls = CALLS.get() - before;
            long t0 = System.nanoTime();
            String slow = run(stock, "slow");
            boolean waited = Duration.ofNanos(System.nanoTime() - t0).toMillis() >= 1_900;
            KbSupport.info("the same token 3 times -> %d introspection calls; AS stalls 2 s -> request thread waits the full 2 s: %s (%s)",
                    stockCalls, waited, slow);
            KbSupport.check("stock checks only 'active': another audience and an expired token are both accepted",
                    rows[1][1].startsWith("accepted") && rows[2][1].startsWith("accepted") && rows[4][1].startsWith("rejected"));
            KbSupport.check("stock has no cache (3 requests = 3 calls) and no client timeout (a 2 s stall blocks 2 s)", stockCalls == 3 && waited);

            KbSupport.section("Hardened: RestClientOpaqueTokenIntrospector with 500 ms timeouts, wrapped with aud/exp/iss checks and a hashed 60 s cache");
            JdkClientHttpRequestFactory rf = new JdkClientHttpRequestFactory();
            rf.setReadTimeout(Duration.ofMillis(500));
            RestClient client = RestClient.builder().requestFactory(rf).defaultHeaders(h -> h.setBasicAuth("payments-rs", "s3cr3t")).build();
            HardenedIntrospector hard = new HardenedIntrospector(new RestClientOpaqueTokenIntrospector(uri, client));
            String[][] hrows = {{"active, aud = this resource server", run(hard, "ok")}, {"active, aud = https://hr.internal", run(hard, "other-aud")},
                {"active, but exp one hour ago", run(hard, "expired")}, {"\"active\": false", run(hard, "revoked")}};
            for (String[] r : hrows) {
                KbSupport.info("%-40s -> %s", r[0], r[1]);
            }
            int b2 = CALLS.get();
            for (int i = 0; i < 3; i++) {
                hard.introspect("ok");
            }
            int hardCalls = CALLS.get() - b2;
            long t1 = System.nanoTime();
            String slow2 = run(hard, "slow");
            long ms = Duration.ofNanos(System.nanoTime() - t1).toMillis();
            KbSupport.info("the same token 3 more times -> %d calls (cached); AS stalls 2 s -> %s within 1 s: %s", hardCalls, slow2, ms < 1_000);
            KbSupport.check("hardened rejects the foreign audience and the expired token, caches, and fails fast on a stalled AS",
                    hrows[1][1].startsWith("rejected: audience") && hrows[2][1].startsWith("rejected: token expired") && hardCalls == 0
                            && slow2.startsWith("error") && ms < 1_000);
        } finally {
            as.stop(0);
            ((java.util.concurrent.ExecutorService) as.getExecutor()).shutdownNow();
        }
        KbSupport.verdict();
    }
}
```

<!-- output:SpringIntrospectionLab.java -->
```text

== Stock SpringOpaqueTokenIntrospector (builder: RestTemplate + basic auth, default request factory)
  active, aud = this resource server       -> accepted (sub=alice, aud=[https://payments.internal])
  active, aud = https://hr.internal        -> accepted (sub=alice, aud=[https://hr.internal])
  active, but exp one hour ago             -> accepted (sub=alice, aud=[https://payments.internal])
  "active": "true" (a string)              -> accepted (sub=alice, aud=[https://payments.internal])
  "active": false                          -> rejected: Provided token isn't active
  the same token 3 times -> 3 introspection calls; AS stalls 2 s -> request thread waits the full 2 s: true (accepted (sub=alice, aud=[https://payments.internal]))
  [PASS] stock checks only 'active': another audience and an expired token are both accepted
  [PASS] stock has no cache (3 requests = 3 calls) and no client timeout (a 2 s stall blocks 2 s)

== Hardened: RestClientOpaqueTokenIntrospector with 500 ms timeouts, wrapped with aud/exp/iss checks and a hashed 60 s cache
  active, aud = this resource server       -> accepted (sub=alice, aud=[https://payments.internal])
  active, aud = https://hr.internal        -> rejected: audience [https://hr.internal] does not include https://payments.internal
  active, but exp one hour ago             -> rejected: token expired at <t>
  "active": false                          -> rejected: Provided token isn't active
  the same token 3 more times -> 0 calls (cached); AS stalls 2 s -> error: OAuth2IntrospectionException within 1 s: true
  [PASS] hardened rejects the foreign audience and the expired token, caches, and fails fast on a stalled AS

verdict: OK (3 checks)
```

Reading the run:
- **"Relying solely on the authorization server"** is a deliberate design comment in the source [D]. It is right only if your AS answers `active: false` for tokens not meant for the calling RS, and never returns `active: true` for an expired token. Most ASes do the latter correctly, and few do the former. Wrap the introspector (L35 `HardenedIntrospector`) and register it with `oauth2ResourceServer(o -> o.opaqueToken(t -> t.introspector(hardened)))`.
- **Timeouts.** `SpringOpaqueTokenIntrospector.withIntrospectionUri(...).build()` and `RestClientOpaqueTokenIntrospector.withIntrospectionUri(...).build()` use default clients. Build your own `RestClient` with a `JdkClientHttpRequestFactory` read timeout (500 ms in L35) and a circuit breaker [E]. Choose explicitly between failing closed (401/503) and serving a cached decision for a bounded grace period.
- **`"active": "true"` is accepted** (the string is parsed). That is harmless, but it shows the parser is lenient: validate the claims you rely on yourself.

---

## 5. Cache design for introspection and phantom tokens

| Decision | L5 | L7 [E] |
|---|---|---|
| Cache key | the raw token | SHA-256(token): no secrets in heap dumps or metrics labels |
| Positive TTL | fixed (minutes) | min(`exp` − now, revocation SLO such as 60 s) |
| Negative TTL | none, or the same as positive | a few seconds, plus rate limits per client IP/ASN |
| Revocation | wait for TTL | evict on RFC 7009 webhooks / back-channel logout / CAEP `session-revoked` |
| Stampede | N concurrent misses = N introspections | single-flight per key |
| AS outage | threads block | client timeouts + breaker; fail closed, or stale-if-error ≤ N s by policy |
| Phantom token | long-lived, broad `aud` | ≤ 60 s, one `aud` per service, `jti`, signed by a gateway key with JWKS rotation (Folder 01 file 03) |
| Claims inside | everything the AS returned | data-minimized: sub, client_id, scope, cnf, acr; no PII unless the service needs it |

---

## 6. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 - DO NOT USE: relay the external token; trust introspection blindly; no timeouts.
http.oauth2ResourceServer(o -> o.opaqueToken(t -> t.introspectionUri(uri).introspectionClientCredentials(id, secret)));
// services call each other with the same bearer token; each one introspects (L34 L5: 4 calls per request)
```

```java
// L7 - gateway: introspect once (hardened, cached), mint per-audience phantom tokens, strip the external token.
@Bean
OpaqueTokenIntrospector introspector() {
    JdkClientHttpRequestFactory rf = new JdkClientHttpRequestFactory();
    rf.setReadTimeout(Duration.ofMillis(500));
    RestClient client = RestClient.builder().requestFactory(rf)
        .defaultHeaders(h -> h.setBasicAuth("gateway", gatewaySecret)).build();   // or private_key_jwt / mTLS
    return new HardenedIntrospector(new RestClientOpaqueTokenIntrospector(INTROSPECT_URI, client)); // L35
}

@Component
final class PhantomTokenFilter extends OncePerRequestFilter {                 // runs after authentication
    private final PhantomTokenMinter minter;                                   // ES256 key from KMS, kid rotated
    private final Map<String, String> routeAudience;                           // /payments/** -> https://payments.internal

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        BearerTokenAuthentication auth = (BearerTokenAuthentication) SecurityContextHolder.getContext().getAuthentication();
        String aud = routeAudience.get(routeOf(req));                          // exact route table; 404 otherwise
        String phantom = minter.mint(auth.getTokenAttributes(), aud, Duration.ofSeconds(60));
        chain.doFilter(new ReplaceAuthorizationHeader(req, "Bearer " + phantom), res);   // the external token stops here
    }
}
```

```yaml
# L7 - internal service: accept only the gateway's phantom tokens for its own audience
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jwk-set-uri: https://gateway.internal/.well-known/jwks.json
          issuer-uri: https://gateway.internal
          audiences: https://payments.internal
          jws-algorithms: ES256
```

Also add `JwtTypeValidator("at+jwt")` to the decoder's validators (Folder 01 file 03). Add a network policy so services accept traffic only from the gateway and from mesh peers (file 02).

---

## 7. Real-world attack vectors & mitigations

### A1 · Revoked tokens served from cache

**Attack.** A user is offboarded or a session is hijacked and revoked. The gateway keeps accepting the token from a cache with a 10-minute TTL (L34 L6: 499 s, 970 requests).
**Wire signature.** Requests with a token after its revocation timestamp.
**Root cause.** TTL chosen for hit rate; no revocation events.
**Mitigation.** TTL = min(exp, revocation SLO). Evict on RFC 7009 / back-channel logout / CAEP. Keep tokens short-lived.
**Detection.** Compare gateway accept logs against AS revocation logs; the result should be zero after the SLO.

### A2 · Introspection flood and token guessing

**Attack.** Random or replayed junk tokens force a cache miss per request. The AS melts, or becomes a token-validity oracle.
**Wire signature.** High introspection rate with `active: false`; many distinct tokens per source.
**Root cause.** No negative caching, no rate limits, a public introspection path.
**Mitigation.** Short negative cache, per-source rate limits, introspection only from authenticated gateways, and opaque tokens with ≥128 bits of entropy.
**Detection.** `active: false` ratio per caller.

### A3 · Cross-API token use (confused deputy at the RS)

**Attack.** A token issued for `https://hr.internal` is presented to `payments`. The AS says `active: true` and the RS doesn't check `aud` (L35 stock case 2).
**Wire signature.** Introspection results whose `aud` lacks the caller.
**Root cause.** "Relying solely on the authorization server" while the AS doesn't scope answers per RS.
**Mitigation.** Check `aud` at the RS (L35 wrapper). Have the AS return `active: false` to non-audience callers (RFC 7662 §2.2). Use resource indicators (RFC 8707) at issuance.
**Detection.** `aud`-mismatch rejections.

### A4 · Bypassing the gateway

**Attack.** An internal service is reachable directly (a misconfigured ingress, an exposed node port, SSRF from a neighbour). The attacker presents an external token or a forged JWT straight to it.
**Wire signature.** Requests to services without the gateway's phantom token, or from outside the mesh.
**Root cause.** Services that accept external tokens or unsigned headers ("X-User-Id").
**Mitigation.** Services accept only gateway-signed `at+jwt` for their own `aud` (L34). Use network policy and mTLS (SPIFFE, file 02). Never trust identity headers without a signature.
**Detection.** Mesh telemetry showing non-gateway callers on north-south routes.

### A5 · Phantom-token replay across services

**Attack.** A compromised service replays the phantom token it received at another service (L34: orders' token replayed at payments).
**Wire signature.** Tokens with `aud` ≠ the receiving service.
**Root cause.** Broad `aud` lists, or none.
**Mitigation.** One `aud` per service per token, ≤ 60 s, and a `jti` where replay matters. Use token exchange for further hops (file 02).
**Detection.** `aud` rejections internally.

### A6 · AS outage cascades into a total outage

**Attack.** No attacker is needed. The AS slows down, every gateway thread waits on introspection with no timeout (L35 stock: the full 2 s), and the platform falls over. Alternatively, a DoS on the AS takes down every API.
**Wire signature.** Introspection latency spikes followed by thread-pool exhaustion.
**Root cause.** Default clients with no timeouts or breakers.
**Mitigation.** A client timeout of a few hundred ms, a circuit breaker, single-flight, and explicit policy on fail-closed vs bounded stale-if-error. Use JWT access tokens at the edge for low-risk traffic if the AS can't meet the SLO.
**Detection.** p99 introspection latency, breaker-open events.

### A7 · Oversharing claims to every service

**Attack.** The phantom token copies every introspection field (email, phone, national id) into tokens that 30 services log.
**Wire signature.** PII in internal tokens and logs.
**Root cause.** Pass-through claim mapping.
**Mitigation.** Data minimization: map only the claims each audience needs; keep PII lookups behind an authorized API.
**Detection.** DLP scans of logs for token payloads.

---

## 8. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · Opaque or JWT access tokens for a public API?</b></summary>

**Initial Prompt.** 50 million users; the AS team prefers JWT for "scalability".

**L5 Textbook Answer.** "JWT: resource servers validate locally, so there's no AS bottleneck."

**How an Attacker Bypasses L5.** A leaked JWT is readable, carrying PII and scope, and valid until `exp`, everywhere it's accepted. Revocation needs the very introspection you avoided. Big claims bloat headers and cookies.

**L7 Principal Defense.**
- **Opaque at the edge, introspected once by the gateway** with a bounded cache (L34: 63× fewer calls than relay).
- **Phantom JWTs inside,** per audience and ≤ 60 s.
- **Revocation events evict the cache.**
- **Internal services verify locally** against the gateway's JWKS.

You get the scalability argument for JWTs where it matters (east-west) and revocability where it matters (north-south).

</details>

<details><summary><b>Q2 · Your introspection cache TTL is 15 minutes. Defend it or change it.</b></summary>

**Initial Prompt.** The SRE team set it for hit rate.

**L5 Textbook Answer.** "Tokens last an hour; 15 minutes is a reasonable fraction."

**How an Attacker Bypasses L5.** A revoked token keeps working for up to 15 minutes, which is your effective revocation latency (L34 L6: 499 s with a 10-minute TTL). A stolen-session incident can't be stopped faster than the cache.

**L7 Principal Defense.**
- **TTL = min(exp − now, revocation SLO).**
- **Subscribe to revocation events** (CAEP/back-channel logout) to evict immediately.
- **Use a short negative TTL.**
- **Hash keys.**
- **Measure the hit rate:** L34 L7 at 60 s still makes only 592 calls for 10,000 requests.
- **State the SLO in the threat model:** "revocation effective within 60 s at every gateway".

</details>

<details><summary><b>Q3 · Spring's opaque-token support "just works". What would you add before production?</b></summary>

**Initial Prompt.** `oauth2ResourceServer().opaqueToken()` with defaults.

**L5 Textbook Answer.** "Nothing; Spring validates the token with the AS."

**How an Attacker Bypasses L5.** It validates only `active` (L35). Tokens for other audiences and stale `exp` are accepted. There is no cache, so every request costs an AS round trip, and no timeout, so an AS stall stalls you.

**L7 Principal Defense.**
- **A wrapper** that checks `aud` ∋ self, `exp` > now and `iss`, with a hashed, bounded cache and single-flight.
- **A `RestClient`** with read and connect timeouts and a breaker.
- **Client authentication** with `private_key_jwt` or mTLS to the introspection endpoint.
- **Metrics** for call rate, latency and `active: false` ratio.

</details>

<details><summary><b>Q4 · Why not just forward the user's token to all downstream services?</b></summary>

**Initial Prompt.** "It's simpler and every service knows who the user is."

**L5 Textbook Answer.** "Token relay is the standard pattern; Spring Cloud Gateway has `TokenRelay`."

**How an Attacker Bypasses L5.** Every service now holds a token valid at every other service. One compromised service replays it laterally (confused deputy). With opaque tokens, every hop introspects (L34: 4×). The external token, possibly long-lived, now sits in 30 services' memory and logs.

**L7 Principal Defense.**
- **Terminate the external token at the gateway.**
- **Per-audience phantom tokens** for the first hop.
- **RFC 8693 token exchange** for further hops, with `act` and narrowed scope (file 02).
- **Workload identity** (SPIFFE mTLS) for service-to-service authentication.
- **Relay only within a single trust zone,** and with audience-restricted tokens.

</details>

<details><summary><b>Q5 · The AS is down. Do APIs fail closed or open?</b></summary>

**Initial Prompt.** Payments vs product catalog.

**L5 Textbook Answer.** "Fail open for availability."

**How an Attacker Bypasses L5.** Fail-open means "no authentication while the AS is down". An attacker who can degrade the AS (DoS) turns off your authentication.

**L7 Principal Defense.** Decide per route:
- **Payments:** fail closed, but keep the cache so recent tokens keep working until their cached TTL ends.
- **Read-only catalog:** a bounded stale-if-error (for example, cached positives up to 5 min past TTL).

Mechanics: client timeouts plus breakers (L35), never unbounded. Alert on breaker-open. Run game days for AS outages.

</details>

<details><summary><b>Q6 · Should the phantom token be signed by the gateway or by the AS?</b></summary>

**Initial Prompt.** Security architecture review.

**L5 Textbook Answer.** "The gateway, since it's simpler."

**How an Attacker Bypasses L5.** A gateway signing key becomes a skeleton key for the mesh. If it lives in the gateway's filesystem, gateway compromise means minting tokens for any user and any service.

**L7 Principal Defense.** Either works with discipline [E].
- **Gateway-signed:** the key in KMS/HSM with sign-only permission and a rotating `kid`; the gateway can mint only for audiences in its route table; short TTL.
- **AS-signed:** the gateway performs RFC 8693 token exchange per audience, so the AS remains the only issuer. This costs more AS calls (cacheable per token × audience), and the AS logs the exchange.

Choose AS-signed when compliance demands a single issuer.

</details>

<details><summary><b>Q7 · How does revocation reach a JWT-only internal mesh?</b></summary>

**Initial Prompt.** Services verify phantom JWTs locally.

**L5 Textbook Answer.** "It doesn't need to; phantom tokens expire in 60 s."

**How an Attacker Bypasses L5.** 60 seconds is fine for phantom tokens, but only if the gateway stops minting new ones. Without cache eviction (A1), the gateway re-mints for a revoked token every 60 s.

**L7 Principal Defense.**
- **Revocation stops at the gateway.** Evict on events, and bound the TTL.
- **Phantom tokens are ≤ 60 s**, so the mesh drains within a minute.
- **For high-risk actions,** services can additionally check a `sid`/`sub` denylist pushed over pub/sub (Folder 03 file 03, Q5).

</details>

<details><summary><b>Q8 · Introspection returns PII. What's your data-minimization design?</b></summary>

**Initial Prompt.** GDPR review.

**L5 Textbook Answer.** "Services are internal; it's fine."

**How an Attacker Bypasses L5.** Internal tokens are logged, traced and dumped. PII in 30 services' logs is a breach waiting to be counted (A7).

**L7 Principal Defense.**
- **Per-audience claim maps:** `payments` gets sub, client_id, scope, cnf and acr, not email or name.
- **PII behind an authorized profile API.**
- **Pairwise subject identifiers per audience** where linkage isn't needed (Folder 03 file 01).
- **Log redaction of `Authorization`.**
- **RFC 9701 JWT responses** where the AS must attest exactly what it disclosed.

</details>

<details><summary><b>Q9 · How do you make introspection resilient at 100k RPS?</b></summary>

**Initial Prompt.** A Black Friday plan.

**L5 Textbook Answer.** "Scale the AS horizontally."

**How an Attacker Bypasses L5.** A thundering herd: a cache flush or deploy triggers N concurrent misses per token. Random-token floods bypass the cache entirely.

**L7 Principal Defense.**
- **Single-flight per key,** a negative cache, and per-source rate limits.
- **Pre-warm:** keep the cache across deploys with a shared Redis tier holding hashed keys and bounded TTLs.
- **Capacity:** introspection is a plain read on the token store, so scale it independently of login.
- **Shed load:** a breaker at the gateway with route-level fail-closed vs bounded-stale policy (Q5).

</details>

<details><summary><b>Q10 · A partner insists on sending JWTs, not opaque tokens, to your gateway. Changes?</b></summary>

**Initial Prompt.** B2B API, partner's own AS (federation).

**L5 Textbook Answer.** "Validate the JWT and forward it."

**How an Attacker Bypasses L5.** The partner's token lands on your internal services, which now trust an external issuer. Its claims and `aud` were designed for the partner's world.

**L7 Principal Defense.**
- **The gateway validates** the partner JWT against its pinned issuer and JWKS, with `typ` and `aud` = your API, and binds it with DPoP or mTLS (Folder 04).
- **Translate** it to your own phantom token or a token-exchanged token, carrying the partner identity as `act` or a mapped `sub`.
- **Internal services only ever see your issuer.**

</details>

---

## 9. Invariants checklist

- [ ] External tokens terminate at the gateway; internal services never receive them.
- [ ] Introspection callers authenticate (`private_key_jwt`/mTLS); AS scopes `active` to the caller's audience where possible.
- [ ] The RS or gateway checks `aud` ∋ self, `exp`, `iss` itself; the introspector is not trusted blindly.
- [ ] Cache: SHA-256 keys, TTL = min(exp, revocation SLO), short negative TTL, single-flight, eviction on revocation events.
- [ ] Introspection client has connect/read timeouts and a breaker; fail-closed vs bounded-stale decided per route.
- [ ] Phantom tokens: `typ at+jwt`, one `aud` per service, ≤ 60 s, signed with a KMS-held rotating key, data-minimized claims.
- [ ] Internal services: issuer = gateway (or AS via exchange), `aud` = self, ES256 only; network policy blocks non-gateway north-south traffic.
- [ ] Metrics: introspection rate, hit ratio, `active:false` ratio, breaker state, revoked-token accepts (should be 0 after SLO).

---

## 10. References

- RFC 7662 *OAuth 2.0 Token Introspection* — <https://www.rfc-editor.org/rfc/rfc7662>
- RFC 9701 *JWT Response for OAuth Token Introspection* — <https://www.rfc-editor.org/rfc/rfc9701>
- RFC 9068 *JWT Profile for OAuth 2.0 Access Tokens* — <https://www.rfc-editor.org/rfc/rfc9068>
- RFC 8707 *Resource Indicators for OAuth 2.0* — <https://www.rfc-editor.org/rfc/rfc8707>
- Curity, *The Phantom Token Pattern* — <https://curity.io/resources/learn/phantom-token-pattern/>
- Spring Security reference, *OAuth 2.0 Resource Server Opaque Token* — <https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/opaque-token.html>
