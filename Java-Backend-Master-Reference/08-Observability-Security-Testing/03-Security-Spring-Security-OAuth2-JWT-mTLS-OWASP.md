# 8.3 · Security — Spring Security Filter Chain, OAuth2/OIDC & JWT, mTLS, OWASP Top 10:2025 in Java

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Spring Security 7.1 reference (architecture, OAuth2 resource server, X.509, method security); RFC 6749/6750 (OAuth 2.0, bearer tokens), RFC 7519/8725 (JWT and JWT best practices), RFC 9068 (JWT access-token profile), RFC 9728 (OAuth 2.0 Protected Resource Metadata), RFC 8705 (mTLS-bound tokens), OAuth 2.1 draft; **OWASP Top 10:2025** (released 6 Nov 2025).
> **Verified stack:** Spring Boot 4.1.2, Spring Security **7.1.2**, Nimbus JOSE+JWT 10.9.1, JDK 25 (`keytool`, JSSE, `HttpClient`). The tokens, certificates and attacks below were generated and run locally against a real Tomcat server; the status codes and headers are captured output.

---

## 1. How a request crosses Spring Security 🔥

```
Tomcat → DelegatingFilterProxy("springSecurityFilterChain") → FilterChainProxy
           └─ first SecurityFilterChain whose matcher matches the request
                ├─ SecurityContextHolderFilter        (loads the SecurityContext: per request, stateless here)
                ├─ HeaderWriterFilter / CsrfFilter / LogoutFilter
                ├─ authentication filters             (BearerTokenAuthenticationFilter, X509AuthenticationFilter, …)
                │     └─ AuthenticationManager → ProviderManager → AuthenticationProvider (JwtAuthenticationProvider…)
                ├─ AnonymousAuthenticationFilter      (no credentials → anonymous token)
                ├─ ExceptionTranslationFilter         (AuthenticationException → 401 via AuthenticationEntryPoint,
                │                                      AccessDeniedException → 403 via AccessDeniedHandler)
                └─ AuthorizationFilter                (AuthorizationManager: URL rules)
           → DispatcherServlet → @PreAuthorize (method security = AOP proxy, see 6.1)
```

* The `SecurityContext` lives in a **`ThreadLocal`** (`SecurityContextHolder`). Async hand-offs need `DelegatingSecurityContextExecutor` or context propagation, the same problem as tracing ([8.2 §2](02-Observability-OpenTelemetry-Micrometer-Logging.md#2-context-propagation-in-process-and-across-kafka-)).
* **401 vs 403:** 401 = "who are you?" (no or invalid credentials, plus a `WWW-Authenticate` challenge); 403 = "I know who you are, and you can't do this".
* Multiple `SecurityFilterChain` beans are allowed. The order and the `securityMatcher` decide which one applies (e.g. `/api/**` with JWT, `/internal/**` with mTLS, `/actuator/**` with basic auth on a separate port).

---

## 2. A JWT resource server under attack 🔥

### 2.1 Runnable: real RS256 tokens against a Boot 4 resource server: valid, scoped, expired, forged, `alg=none`, IDOR

<!-- run: javac cp=@p8 timeout=200 -->
```java
package demo.security;

import com.nimbusds.jose.*;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.*;
import java.net.URI;
import java.net.http.*;
import java.security.*;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.annotation.*;
import org.springframework.http.HttpMethod;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.core.*;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.bind.annotation.*;

public class JwtResourceServer {
    static KeyPair trusted, attacker;

    @RestController
    public static class Api {
        final Map<String, String> orderOwners = Map.of("A-1", "alice", "B-7", "bob");
        @GetMapping("/api/orders/{id}")
        @PreAuthorize("hasAuthority('SCOPE_orders.read')")
        public String order(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
            if (!jwt.getSubject().equals(orderOwners.get(id)))                         // object-level check (OWASP A01)
                throw new org.springframework.security.access.AccessDeniedException("not your order");
            return "order " + id + " for " + jwt.getSubject();
        }
        @PostMapping("/api/refunds")
        public String refund() { return "refund queued"; }
    }

    @SpringBootConfiguration @EnableAutoConfiguration @EnableMethodSecurity @Import(Api.class)
    static class App {
        @Bean SecurityFilterChain api(HttpSecurity http) throws Exception {
            return http
                .authorizeHttpRequests(a -> a
                    .requestMatchers(HttpMethod.POST, "/api/refunds").hasAuthority("SCOPE_refunds.write")
                    .anyRequest().authenticated())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .oauth2ResourceServer(o -> o.jwt(j -> { }))
                .build();
        }
        @Bean JwtDecoder jwtDecoder() {
            NimbusJwtDecoder decoder = NimbusJwtDecoder.withPublicKey((RSAPublicKey) trusted.getPublic()).build();
            OAuth2TokenValidator<Jwt> audience = jwt -> jwt.getAudience().contains("orders-api")
                ? OAuth2TokenValidatorResult.success()
                : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "The required audience is missing", null));
            decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(JwtValidators.createDefaultWithIssuer("https://idp.example.com"), audience));
            return decoder;
        }
    }

    public static void main(String[] args) throws Exception {
        KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA");
        gen.initialize(2048);
        trusted = gen.generateKeyPair(); attacker = gen.generateKeyPair();
        SpringApplication sa = new SpringApplication(App.class);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        sa.setDefaultProperties(Map.of("server.port", "0", "logging.level.root", "OFF"));
        try (var ctx = sa.run(); HttpClient http = HttpClient.newHttpClient()) {
            var chain = ctx.getBean(FilterChainProxy.class).getFilterChains().getFirst().getFilters();
            System.out.println("filter chain (" + chain.size() + "): " + chain.stream().map(f -> f.getClass().getSimpleName()).toList());
            String base = "http://localhost:" + ((WebServerApplicationContext) ctx).getWebServer().getPort();
            Instant now = Instant.now();
            String good = token(trusted, "alice", "orders.read", "orders-api", now.plusSeconds(300));
            call(http, "no token", "GET", base + "/api/orders/A-1", null);
            call(http, "valid token, own order", "GET", base + "/api/orders/A-1", good);
            call(http, "valid token, someone else's order", "GET", base + "/api/orders/B-7", good);
            call(http, "missing scope for POST /api/refunds", "POST", base + "/api/refunds", good);
            call(http, "refunds.write scope, no CSRF token", "POST", base + "/api/refunds", token(trusted, "alice", "refunds.write", "orders-api", now.plusSeconds(300)));
            call(http, "expired 30 seconds ago", "GET", base + "/api/orders/A-1", token(trusted, "alice", "orders.read", "orders-api", now.minusSeconds(30)));
            call(http, "expired 2 minutes ago", "GET", base + "/api/orders/A-1", token(trusted, "alice", "orders.read", "orders-api", now.minusSeconds(120)));
            call(http, "wrong audience", "GET", base + "/api/orders/A-1", token(trusted, "alice", "orders.read", "billing-api", now.plusSeconds(300)));
            call(http, "signed by an untrusted key", "GET", base + "/api/orders/A-1", token(attacker, "alice", "orders.read", "orders-api", now.plusSeconds(300)));
            String header = Base64.getUrlEncoder().withoutPadding().encodeToString("{\"alg\":\"none\"}".getBytes());
            String unsignedPayload = good.split("\\.")[1];
            call(http, "alg=none, signature stripped", "GET", base + "/api/orders/A-1", header + "." + unsignedPayload + ".");
        }
    }

    static String token(KeyPair key, String sub, String scope, String aud, Instant exp) throws Exception {
        JWTClaimsSet claims = new JWTClaimsSet.Builder().issuer("https://idp.example.com").subject(sub).audience(aud)
            .claim("scope", scope).issueTime(Date.from(exp.minusSeconds(600))).expirationTime(Date.from(exp)).build();
        SignedJWT jwt = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).build(), claims);
        jwt.sign(new RSASSASigner(key.getPrivate()));
        return jwt.serialize();
    }

    static void call(HttpClient http, String label, String method, String url, String token) throws Exception {
        var b = HttpRequest.newBuilder(URI.create(url)).method(method, HttpRequest.BodyPublishers.noBody());
        if (token != null) b.header("Authorization", "Bearer " + token);
        HttpResponse<String> r = http.send(b.build(), HttpResponse.BodyHandlers.ofString());
        System.out.printf("%-38s → %d %s%n", label, r.statusCode(), r.statusCode() == 200 ? r.body()
            : r.headers().firstValue("WWW-Authenticate").orElse("(no WWW-Authenticate)")
                .replaceAll("localhost:\\d+", "localhost:<port>").replaceAll("expired at \\S+?Z", "expired at <time>")
                .replace(", error_uri=\"https://tools.ietf.org/html/rfc6750#section-3.1\"", ""));
    }
}
```

Output (verified):

```
filter chain (14): [DisableEncodeUrlFilter, WebAsyncManagerIntegrationFilter, SecurityContextHolderFilter, HeaderWriterFilter, CsrfFilter, LogoutFilter, OAuth2ProtectedResourceMetadataFilter, BearerTokenAuthenticationFilter, RequestCacheAwareFilter, SecurityContextHolderAwareRequestFilter, AnonymousAuthenticationFilter, SessionManagementFilter, ExceptionTranslationFilter, AuthorizationFilter]
no token                               → 401 Bearer resource_metadata="http://localhost:<port>/.well-known/oauth-protected-resource"
valid token, own order                 → 200 order A-1 for alice
valid token, someone else's order      → 403 Bearer error="insufficient_scope", error_description="The request requires higher privileges than provided by the access token."
missing scope for POST /api/refunds    → 403 Bearer error="insufficient_scope", error_description="The request requires higher privileges than provided by the access token."
refunds.write scope, no CSRF token     → 200 refund queued
expired 30 seconds ago                 → 200 order A-1 for alice
expired 2 minutes ago                  → 401 Bearer error="invalid_token", error_description="An error occurred while attempting to decode the Jwt: Jwt expired at <time>", resource_metadata="http://localhost:<port>/.well-known/oauth-protected-resource"
wrong audience                         → 401 Bearer error="invalid_token", error_description="An error occurred while attempting to decode the Jwt: The required audience is missing", resource_metadata="http://localhost:<port>/.well-known/oauth-protected-resource"
signed by an untrusted key             → 401 Bearer error="invalid_token", error_description="An error occurred while attempting to decode the Jwt: Signed JWT rejected: Invalid signature", resource_metadata="http://localhost:<port>/.well-known/oauth-protected-resource"
alg=none, signature stripped           → 401 Bearer error="invalid_token", error_description="Unsupported algorithm of none", resource_metadata="http://localhost:<port>/.well-known/oauth-protected-resource"
```

Reading the results:

* **The actual chain** (14 filters) includes **`OAuth2ProtectedResourceMetadataFilter`**: Spring Security 7.1 publishes RFC 9728 metadata at `/.well-known/oauth-protected-resource` and advertises it in every `WWW-Authenticate` challenge (`resource_metadata="…"`). Clients (including MCP clients, [7.3 §3](../07-AI-Engineering/03-MCP-Servers-and-Clients-in-Java.md#3-streamable-http-remote-servers-sessions-and-the-origin-check-)) use it to discover the authorization server.
* **Validation that held:** signature (an attacker's key → `Invalid signature`), `alg=none` (refused: the decoder only accepts the algorithm of the configured key), issuer, **audience** (a token minted for `billing-api` was rejected: without an audience check, any token from your IdP works on every API), and expiry.
* **Clock skew:** a token that expired **30 seconds ago was still accepted**; one expired 2 minutes ago was rejected. `JwtTimestampValidator` allows 60 s by default. Keep tokens short-lived (5–15 min) and account for the skew in revocation reasoning.
* **Scopes become authorities:** `scope: orders.read` → `SCOPE_orders.read`. A token without `refunds.write` got **403 `insufficient_scope`** on `POST /api/refunds`.
* **Object-level authorization is your code:** Alice's token had the right scope but requested Bob's order. The ownership check (OWASP **A01 Broken Access Control**, "IDOR") returned 403. Note the challenge still said `insufficient_scope`: the bearer-token access-denied handler uses that error for **every** 403, which misleads API clients. Return a problem-details body that says what actually failed.
* **CSRF:** a bearer-token `POST` passed without a CSRF token. Spring Security exempts requests authenticated by bearer tokens, because a browser doesn't attach them automatically. Cookie- or session-authenticated endpoints **must** keep CSRF protection (or `SameSite` cookies plus CSRF tokens).
* **Error detail leaks:** `error_description` told the caller exactly why validation failed ("Invalid signature", "expired at …"). That helps debugging, and it helps attackers too. Consider generic messages externally and detailed logs internally (A09/A10 in §5).

### 2.2 JWT and OAuth2/OIDC checklist ⚡

| Area | Do | Avoid |
|---|---|---|
| Signature | Asymmetric keys (RS256/ES256/EdDSA); fetch JWKS from the issuer (`spring.security.oauth2.resourceserver.jwt.issuer-uri` / `jwk-set-uri`); cache with rotation (by `kid`) | Shared HMAC secrets across services; accepting the token's own `alg`/`jku` |
| Claims | `iss`, `aud`, `exp`, `nbf`; `typ=at+jwt` (RFC 9068) where the IdP sets it | Using ID tokens as access tokens |
| Lifetime | 5–15 min access tokens; refresh tokens only at the client; revocation strategy (short TTL, or introspection for high-risk operations) | Long-lived JWTs that can't be revoked |
| Flows | Authorization code **+ PKCE** for user apps; client credentials for service-to-service; token exchange for delegation | Implicit flow; password grant (removed in OAuth 2.1) |
| SPAs | **BFF pattern**: tokens stay server-side, the browser gets an `HttpOnly; Secure; SameSite` session cookie | Tokens in `localStorage` (XSS = token theft) |
| Logging | Log `sub`, `client_id`, `jti`, decision | Logging raw tokens or Authorization headers |
| Opaque vs JWT | Opaque + introspection when instant revocation matters; JWT for scale | Pretending JWTs can be revoked without infrastructure |

---

## 3. Mutual TLS for service-to-service calls ⚡

### 3.1 Runnable: a throwaway CA, Spring Boot SSL bundles with `client-auth=need`, and X.509 authentication

<!-- run: javac cp=@p8 timeout=300 -->
```java
package demo.mtls;

import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.nio.file.*;
import java.security.KeyStore;
import java.util.*;
import javax.net.ssl.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.annotation.*;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.userdetails.*;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.bind.annotation.*;

public class MutualTls {
    static Path dir;
    static final String PW = "changeit";

    @RestController
    public static class Api {
        @GetMapping("/internal/settlements")
        public String settlements(Authentication auth) { return "settlements for " + auth.getName() + " " + auth.getAuthorities(); }
    }
    @SpringBootConfiguration @EnableAutoConfiguration @Import(Api.class)
    static class App {
        @Bean SecurityFilterChain mtls(HttpSecurity http) throws Exception {
            return http.x509(x -> x.subjectPrincipalRegex("CN=(.*?)(?:,|$)"))       // certificate CN → username
                .authorizeHttpRequests(a -> a.anyRequest().hasRole("SERVICE"))
                .build();
        }
        @Bean UserDetailsService services() {                                            // which client certs are allowed in
            return new InMemoryUserDetailsManager(User.withUsername("orders-batch-client").password("{noop}n/a").roles("SERVICE").build());
        }
    }

    public static void main(String[] args) throws Exception {
        dir = Files.createTempDirectory("mtls");
        keytool("-genkeypair", "-alias", "ca", "-keyalg", "RSA", "-keysize", "2048", "-dname", "CN=Demo Internal CA", "-ext", "bc:c", "-validity", "30", "-keystore", "ca.p12");
        keytool("-exportcert", "-alias", "ca", "-rfc", "-file", "ca.pem", "-keystore", "ca.p12");
        keytool("-importcert", "-noprompt", "-alias", "ca", "-file", "ca.pem", "-keystore", "trust.p12");
        issue("server", "CN=localhost", "san=dns:localhost,ip:127.0.0.1", "eku=serverAuth");
        issue("client", "CN=orders-batch-client", null, "eku=clientAuth");
        issue("stranger", "CN=unknown-client", null, "eku=clientAuth");                  // valid CA signature, unknown identity

        SpringApplication sa = new SpringApplication(App.class);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        Map<String, Object> props = new HashMap<>(Map.of("server.port", "0", "logging.level.root", "OFF",
            "server.ssl.bundle", "mtls", "server.ssl.client-auth", "need"));
        props.putAll(Map.of(
            "spring.ssl.bundle.jks.mtls.keystore.location", dir.resolve("server.p12").toUri().toString(),
            "spring.ssl.bundle.jks.mtls.keystore.password", PW, "spring.ssl.bundle.jks.mtls.keystore.type", "PKCS12",
            "spring.ssl.bundle.jks.mtls.truststore.location", dir.resolve("trust.p12").toUri().toString(),
            "spring.ssl.bundle.jks.mtls.truststore.password", PW, "spring.ssl.bundle.jks.mtls.truststore.type", "PKCS12"));
        sa.setDefaultProperties(props);
        try (var ctx = sa.run()) {
            URI uri = URI.create("https://localhost:" + ((WebServerApplicationContext) ctx).getWebServer().getPort() + "/internal/settlements");
            call("no client certificate", uri, null);
            call("client cert CN=orders-batch-client", uri, "client.p12");
            call("client cert CN=unknown-client", uri, "stranger.p12");
        }
    }

    static void call(String label, URI uri, String clientKeystore) {
        try (HttpClient http = HttpClient.newBuilder().sslContext(sslContext(clientKeystore)).build()) {
            HttpResponse<String> r = http.send(HttpRequest.newBuilder(uri).build(), HttpResponse.BodyHandlers.ofString());
            System.out.printf("%-36s → HTTP %d %s%n", label, r.statusCode(), r.statusCode() == 200 ? r.body() : "");
        } catch (Exception e) {
            Throwable root = e; while (root.getCause() != null) root = root.getCause();
            System.out.printf("%-36s → %s: %s%n", label, root.getClass().getSimpleName(), root.getMessage());
        }
    }

    static SSLContext sslContext(String clientKeystore) throws Exception {
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(load("trust.p12"));
        KeyManager[] kms = null;
        if (clientKeystore != null) {
            KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
            kmf.init(load(clientKeystore), PW.toCharArray());
            kms = kmf.getKeyManagers();
        }
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(kms, tmf.getTrustManagers(), null);
        return ctx;
    }
    static KeyStore load(String name) throws Exception {
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (InputStream in = Files.newInputStream(dir.resolve(name))) { ks.load(in, PW.toCharArray()); }
        return ks;
    }

    /** Key pair + CSR → certificate signed by the CA → chain imported back into <name>.p12 */
    static void issue(String name, String dn, String san, String eku) throws Exception {
        String ks = name + ".p12";
        keytool("-genkeypair", "-alias", name, "-keyalg", "RSA", "-keysize", "2048", "-dname", dn, "-validity", "30", "-keystore", ks);
        keytool("-certreq", "-alias", name, "-file", name + ".csr", "-keystore", ks);
        List<String> gen = new ArrayList<>(List.of("-gencert", "-alias", "ca", "-infile", name + ".csr", "-outfile", name + ".pem",
            "-rfc", "-validity", "30", "-ext", eku, "-keystore", "ca.p12"));
        if (san != null) gen.addAll(List.of("-ext", san));
        keytool(gen.toArray(String[]::new));
        keytool("-importcert", "-noprompt", "-alias", "ca", "-file", "ca.pem", "-keystore", ks);
        keytool("-importcert", "-alias", name, "-file", name + ".pem", "-keystore", ks);
    }
    static void keytool(String... args) throws Exception {
        List<String> cmd = new ArrayList<>(List.of(Path.of(System.getProperty("java.home"), "bin", "keytool").toString()));
        cmd.addAll(List.of(args));
        cmd.addAll(List.of("-storetype", "PKCS12", "-storepass", PW));
        Process p = new ProcessBuilder(cmd).directory(dir.toFile()).redirectErrorStream(true).start();
        String out = new String(p.getInputStream().readAllBytes());
        if (p.waitFor() != 0) throw new IllegalStateException("keytool " + args[0] + " failed: " + out);
    }
}
```

Output (verified):

```
no client certificate                → SSLHandshakeException: (certificate_required) Received fatal alert: certificate_required
client cert CN=orders-batch-client   → HTTP 200 settlements for orders-batch-client [ROLE_SERVICE, FACTOR_X509]
client cert CN=unknown-client        → HTTP 403
```

* **Without a client certificate the TLS handshake failed** (TLS 1.3 `certificate_required` alert) before any HTTP happened. **With the CA-issued client certificate** the request authenticated as `orders-batch-client`.
* **TLS authenticates, the application authorizes:** a certificate signed by the same CA but for an unknown CN completed the handshake and was then **refused with 403** by Spring Security (`x509()` maps the CN to a user that must exist). Trusting a CA means trusting everything it ever signs, so map identities explicitly.
* **`FACTOR_X509`** appeared among the authorities: Spring Security 7 records **which authentication factors** were used, which enables step-up and multi-factor rules (`hasAuthority('FACTOR_X509')`).
* Boot configuration used **SSL bundles**: `spring.ssl.bundle.jks.<name>.keystore.*`/`truststore.*` + `server.ssl.bundle=<name>` + `server.ssl.client-auth=need`. The same bundle names can configure outbound `RestClient`/`WebClient` clients. Bundles can also be PEM (`spring.ssl.bundle.pem.*`) and watched for reloads (`spring.ssl.bundle.watch.file.quiet-period`).
* In Kubernetes, a **service mesh** (Istio/Linkerd, SPIFFE identities) usually does mTLS transparently. Then authorize on the mesh identity (forwarded peer certificate or headers set by the sidecar), and never trust such headers from outside the mesh. RFC 8705 can bind access tokens to the client certificate, so a stolen token is useless elsewhere.

---

## 4. OWASP Top 10:2025, mapped to Java/Spring 🔥

| # | Category | What it looks like in a Spring service | Controls (where in this guide) |
|---|---|---|---|
| A01 | **Broken Access Control** (now incl. **SSRF**) | IDOR (§2.1), missing method security, admin endpoints exposed, URL fetchers reaching internal services | Deny by default; object-level checks; `@PreAuthorize`; SSRF guard (§4.1) |
| A02 | Security Misconfiguration | Actuator endpoints exposed, debug on, default credentials, permissive CORS, stack traces in responses | `management.endpoints.web.exposure.include` minimal; separate management port; hardened defaults per profile |
| A03 | **Software Supply Chain Failures** (new) | Vulnerable or malicious dependencies, unsigned artifacts, CI compromise | SBOM (CycloneDX), dependency scanning, pinned versions, a repository proxy, signed builds, Dependabot/Renovate with review |
| A04 | Cryptographic Failures | Weak TLS, home-made crypto, secrets in Git, unsalted password hashes | TLS 1.2+/1.3, `DelegatingPasswordEncoder` (bcrypt/argon2), a secrets manager, SSL bundles (§3) |
| A05 | Injection | SQL/JPQL concatenation, LDAP, OS commands, log injection, prompt injection | Bind parameters ([5.3 §5.2](../05-Persistence-JPA-Hibernate/03-Performance-NPlus1-Cartesian-Projections.md#52-other-levers)), validation, encoding, untrusted content treated as data ([7.4 §4](../07-AI-Engineering/04-RAG-Embeddings-Chunking-Vector-Stores.md#4-putting-retrieved-text-in-front-of-claude-)) |
| A06 | Insecure Design | No rate limits on expensive operations, business-logic abuse (refund loops) | Threat modelling, rate limiters and bulkheads ([6.4](../06-Spring-Microservices/04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md)), idempotency keys ([6.3 §5](../06-Spring-Microservices/03-Outbox-Saga-Idempotency.md#5-idempotency-keys-for-http-apis-)) |
| A07 | Authentication Failures | Long-lived tokens, no MFA, credential stuffing, weak session handling | OIDC with PKCE, MFA factors, short tokens, lockout and throttling |
| A08 | Software or Data Integrity Failures | Unsigned updates, Java deserialization of untrusted data | No native deserialization of untrusted input; JEP 290 filters ([4.3](../04-IO-NIO-Serialization/03-Serialization-Security-Protobuf-Avro-Jackson.md)); signed artifacts |
| A09 | Logging & Alerting Failures | No audit trail for authz decisions; tokens in logs; no alerting | Structured security events ([8.2 §4](02-Observability-OpenTelemetry-Micrometer-Logging.md#4-structured-json-logs-with-mdc-and-trace-correlation-)), alerts on auth failures, no secrets in logs |
| A10 | **Mishandling of Exceptional Conditions** (new) | Fail-open on errors, leaking exception details, inconsistent states after partial failure | Fail closed; problem-details without internals; transactional boundaries ([5.4](../05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md)) |

### 4.1 Runnable: an SSRF guard that resolves before it judges

<!-- run: timeout=60 -->
```java
import java.net.*;
import java.util.*;

public class SsrfGuard {
    /** The usual first attempt: a string blocklist. */
    static boolean naiveAllowed(String url) {
        String host = URI.create(url).getHost();
        return host != null && !List.of("localhost", "127.0.0.1", "169.254.169.254", "[::1]").contains(host);
    }

    /** Resolve first, then judge the ADDRESSES (and connect to exactly the address you checked). */
    static Optional<InetAddress> safeTarget(String url) {
        URI uri = URI.create(url);
        if (!Set.of("http", "https").contains(uri.getScheme())) return Optional.empty();
        String host = uri.getHost();
        if (host == null) return Optional.empty();                                   // unparseable authority: refuse
        try {
            InetAddress[] all = InetAddress.getAllByName(host);
            for (InetAddress a : all) if (internal(a)) return Optional.empty();       // every resolved address must be public
            return Optional.of(all[0]);                                                // pin it: connect to this IP, send Host header
        } catch (UnknownHostException e) {
            return Optional.empty();
        }
    }
    static boolean internal(InetAddress a) {
        return a.isLoopbackAddress() || a.isSiteLocalAddress() || a.isLinkLocalAddress() || a.isAnyLocalAddress()
            || a.isMulticastAddress() || (a instanceof Inet6Address && (a.getAddress()[0] & 0xfe) == 0xfc);   // fc00::/7 unique-local
    }

    public static void main(String[] args) {
        for (String url : List.of("http://127.0.0.1/admin", "http://2130706433/admin", "http://127.1/admin",
                "http://[::ffff:127.0.0.1]/admin", "http://169.254.169.254/latest/meta-data/", "http://0.0.0.0:8080/actuator",
                "http://10.0.0.5/internal", "http://[fd00::1]/", "file:///etc/passwd", "http://93.184.215.14/")) {
            System.out.printf("%-42s naive=%-7s guarded=%s%n", url, naiveAllowed(url) ? "ALLOW" : "block",
                safeTarget(url).map(a -> "ALLOW " + a.getHostAddress()).orElse("block"));
        }
    }
}
```

Output (verified):

```
http://127.0.0.1/admin                     naive=block   guarded=block
http://2130706433/admin                    naive=ALLOW   guarded=block
http://127.1/admin                         naive=block   guarded=block
http://[::ffff:127.0.0.1]/admin            naive=ALLOW   guarded=block
http://169.254.169.254/latest/meta-data/   naive=block   guarded=block
http://0.0.0.0:8080/actuator               naive=ALLOW   guarded=block
http://10.0.0.5/internal                   naive=ALLOW   guarded=block
http://[fd00::1]/                          naive=ALLOW   guarded=block
file:///etc/passwd                         naive=block   guarded=block
http://93.184.215.14/                      naive=ALLOW   guarded=ALLOW 93.184.215.14
```

* **String blocklists lose:** `2130706433` (decimal for 127.0.0.1), `[::ffff:127.0.0.1]` (IPv4-mapped IPv6), `0.0.0.0`, private ranges and IPv6 unique-local addresses all got through the naive check. They are classic routes to **cloud metadata endpoints** (`169.254.169.254`), admin ports and internal services.
* **Parser differentials matter:** `URI.create("http://127.1/").getHost()` is `null` in Java, while other parsers treat `127.1` as 127.0.0.1. Java reads `0177.0.0.1` as decimal 177.0.0.1, while libc-based tools read it as octal 127.0.0.1. Validate with the **same parser and resolver** that will make the connection, and refuse anything unparseable.
* **Resolve, check every address, then connect to the checked IP** (pinning). Otherwise a DNS-rebinding attacker answers your check with a public IP and your connection with `127.0.0.1`. Allow-list schemes and ports, disable redirects (or re-validate each hop), and for strong guarantees route outbound fetches through an egress proxy that enforces the policy at the network level.

---

## 5. Production failure modes & diagnostics

| Symptom | Cause | Fix |
|---|---|---|
| Every API call 401 after an IdP key rotation | JWKS cached without refresh, or a hard-coded public key | `issuer-uri`/`jwk-set-uri` with JWKS refresh by `kid` |
| Tokens from another app work on your API | No audience validation | Audience validator (§2.1) |
| Intermittent 401 "expired" on fresh tokens | Clock drift between IdP and service beyond the skew | NTP everywhere; reasonable skew |
| Users see others' data | Object-level authorization missing (IDOR) | Ownership checks in services or repositories; tests for horizontal access |
| `@PreAuthorize` ignored | Method security not enabled, self-invocation, or a non-Spring-bean call | `@EnableMethodSecurity`; call through the proxy ([6.1](../06-Spring-Microservices/01-Spring-Container-Internals-IoC-AOP.md)) |
| Security context missing in async tasks | `ThreadLocal` context not propagated | `DelegatingSecurityContextExecutor`, context propagation |
| mTLS handshake failures after a certificate renewal | Truststore lacks the new CA or intermediate; expired client cert | Monitor certificate expiry; bundle reloads; chain validation in CI |
| Cloud credentials stolen via a "fetch URL" feature | SSRF to the metadata service | SSRF guard; IMDSv2 / metadata hop limits; egress policy |
| Sensitive details in error responses | Default error handling exposing exception messages | Problem details with generic messages; log details server-side |

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 Walk through how Spring Security authenticates a bearer token and authorizes a request.</b></summary>

`FilterChainProxy` selects the matching `SecurityFilterChain`. `BearerTokenAuthenticationFilter` extracts the token and calls the `AuthenticationManager`, whose `JwtAuthenticationProvider` uses the `JwtDecoder` (signature, `iss`, `aud`, `exp`/`nbf` with 60 s skew), converts scopes to `SCOPE_*` authorities and stores the `Authentication` in the `SecurityContextHolder`. `AuthorizationFilter` evaluates URL rules, and method security (`@PreAuthorize`) adds checks on the proxy. Failures surface through `ExceptionTranslationFilter` as 401 (with a `WWW-Authenticate` challenge) or 403. All verified in §2.1, including `alg=none` and forged-signature rejection.
</details>

<details><summary><b>Q2. 🔥 Why is audience validation essential for JWT resource servers?</b></summary>

Your IdP issues tokens for many APIs. Without an `aud` check, a token minted for a low-privilege service (or a compromised one) is accepted by every other API that trusts the same issuer. The verified run rejected a correctly signed `billing-api` token. Also validate `iss`, use asymmetric keys, and never accept the algorithm the token claims.
</details>

<details><summary><b>Q3. ⚡ Does a stateless JWT API need CSRF protection?</b></summary>

Not for requests authenticated by an `Authorization: Bearer` header: browsers don't attach it automatically, so a cross-site form can't forge it (verified: Spring Security exempted the bearer POST). If the API also accepts cookies or sessions (e.g. a BFF), those endpoints need CSRF protection or strict `SameSite` cookies.
</details>

<details><summary><b>Q4. ⚡ mTLS proved the client has a certificate from our CA. Is that authorization?</b></summary>

No. It is authentication of a key holder. Every certificate the CA signs passes the handshake (verified: an unknown CN completed TLS and was then denied with 403). Map certificate identities (CN/SAN, or SPIFFE IDs) to known principals and authorize per operation. Monitor expiry and rotation, and consider binding tokens to certificates (RFC 8705).
</details>

<details><summary><b>Q5. 🔥 How do you defend a "fetch this URL" feature against SSRF?</b></summary>

Allow-list schemes, ports and ideally hosts. Parse with the same library that connects, resolve the host, reject loopback, private, link-local, any-local, multicast, IPv4-mapped and unique-local addresses, then connect to the checked IP (pinning, against DNS rebinding). Disable or re-validate redirects, set timeouts and size limits, and enforce egress rules at the network level. A string blocklist misses decimal, IPv6-mapped and `0.0.0.0` forms (verified).
</details>

<details><summary><b>Q6. ⚡ Name the OWASP Top 10:2025 categories that are new or changed compared with 2021.</b></summary>

New: **A03 Software Supply Chain Failures** and **A10 Mishandling of Exceptional Conditions**. SSRF was folded into **A01 Broken Access Control**. Security Misconfiguration rose to **A02**. Injection moved to **A05**. Logging is now **Logging & Alerting Failures** (A09), and Identification and Authentication Failures became **Authentication Failures** (A07).
</details>
