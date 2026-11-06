# Spring Security Resource Server: Multi-Tenant JWKS, DPoP, and Method Security (Code)

> Folder 07 · File 03 of 04 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [02 · BFF and token relay](02-spring-cloud-gateway-bff-oauth2-client-redis-session-and-token-relay-code.md) · Next: [04 · OpenFGA and OPA in Java 21](04-openfga-zanzibar-and-opa-integration-in-java21-microservices.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L48 `MultiTenantRsLab.java` | Spring Security 7.1.2's real `JwtIssuerAuthenticationManagerResolver` against two tenants' issuers served in-process (OIDC discovery + JWKS):<br>• `fromTrustedIssuers(a, b)` authenticates both tenants and refuses a look-alike issuer **with no network call**;<br>• the **prefix predicate** `iss -> iss.startsWith(<tenant-a>)` lets an attacker issuer `…/tenant-a-evil` in: the resolver **fetches the attacker's discovery document and JWKS** and accepts the attacker's token;<br>• **method security** (`@PreAuthorize` through `AuthorizationManagerBeforeMethodInterceptor` on an AOP proxy) allows only the same-tenant caller with the scope, and denies cross-tenant and missing-scope calls;<br>• **the per-tenant validator composition**, in three variants:<br>&nbsp;&nbsp;A. `createAtJwtValidator()` alone **accepts an mTLS-bound token presented with no client certificate**, because it leaves out the `x5t#S256` check that `createDefaultWithValidators` inserts.<br>&nbsp;&nbsp;B. Nesting it as `createDefaultWithValidators([atJwt])` **rejects every RFC 9068 token**.<br>&nbsp;&nbsp;C. `createDefaultWithValidators([JwtTypeValidator("at+jwt"), atJwt])` enforces the binding and the required claims together | RFC 9068; RFC 8705 §3; spring-security 7.1.2 |

**Verification.** Compiled with Folders 01–07 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs the output and requires it byte-identical, with the port masked. The DPoP half of this blueprint was measured in Folder 04 (L27: the verifier's defaults and fixes) and is assembled here in code.

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

A multi-tenant API trusts several issuers: one per customer (enterprise IdPs) or per realm/tenant of your own CIAM. It must keep tenant A's tokens out of tenant B's data, always. Three layers decide that:
1. **Which issuers are trusted at all.** Tenant resolution is a trust decision.
2. **Per-issuer token validation:** `aud`, `typ`, algorithm, and DPoP binding.
3. **Authorization bound to the tenant at the method** where data is touched.

Results:
- **[M] Issuer trust must be an exact set (L48).**
  - `fromTrustedIssuers(a, b)` refuses `…/tenant-a-evil` before any HTTP call.
  - A `startsWith` predicate admits it, and the resolver then *fetches the attacker's own discovery document and JWKS*. That is SSRF plus key-injection by design.
  - For dynamic onboarding, use a predicate backed by an exact tenant registry, never string matching.
- **[M] Tenant binding belongs in method security (L48).** `@PreAuthorize("... and #tenantId == principal.getClaimAsString('tenant')")` denies a tenant-B user reading tenant-A data, even though B's token is perfectly valid.
- **[D] What the stock per-issuer decoders check.**
  - `fromTrustedIssuers(...)` builds each tenant's decoder with `JwtDecoders.fromIssuerLocation(issuer)`, which installs `JwtValidators.createDefaultWithIssuer(issuer)`.
  - That validator checks `iss`, timestamps, an mTLS `x5t#S256` binding if present, and `typ` = `JWT` or absent.
  - So the stock path **checks no `aud`** and **rejects RFC 9068 `at+jwt` tokens**.
  - The fix is the public constructor `new JwtIssuerAuthenticationManagerResolver(AuthenticationManagerResolver<String>)`, with your own per-tenant decoders (§3).
- **[M] The per-tenant validator has one correct composition (L48 §4).**
  - `createAtJwtValidator()` requires the RFC 9068 claims, but **drops the certificate-binding check**: an mTLS-bound token presented with no certificate is accepted.
  - Spring's `X509CertificateThumbprintValidator` is package-private, so you can't add it back by hand.
  - Wrapping the builder in `createDefaultWithValidators([atJwt])` restores the binding check, but also adds `typ` = `JWT`, which rejects every token.
  - `createDefaultWithValidators([new JwtTypeValidator("at+jwt"), atJwt])` gives all three: `at+jwt`, the RFC 9068 claims, and the binding.
- **[D] DPoP with a per-issuer resolver depends on `RequestContextHolder`.**
  - In 7.1.2, `DPoPConfigurer` resolves the token's `AuthenticationManager` through the resolver. It takes the current request from `RequestContextHolder`.
  - The default thumbprint validator reads the client certificate from there too.
  - A `RequestContextFilter` must therefore run before the security chain, or the DPoP path fails with a `NullPointerException` and the binding check fails closed.
  - Spring MVC applications normally register one. Prove it with an end-to-end DPoP test through the real filter chain [E].

---

## 1. First principles: three layers of tenant isolation

```text
   request with Bearer/DPoP token
        |
   (1) issuer trust      iss in exact registry? --no--> 401 (no network call)
        |  yes: per-tenant AuthenticationManager (cached)
   (2) token validation  signature (tenant JWKS) + alg pinned + typ at+jwt + aud == this API + exp
        |                + DPoP: proof checks, cnf.jkt (Folder 04 L27) or mTLS x5t#S256
        v
   JwtAuthenticationToken(principal = Jwt, authorities = scopes, tenant = claim or iss->tenant map)
        |
   (3) authorization     @PreAuthorize: scope AND #tenantId == caller tenant (AND resource-level PDP, file 04)
        v
   repository queries scoped by tenant id (row-level security as the last line)
```

---

## 2. L48: issuer resolution and method security, run for real

<!-- listing:MultiTenantRsLab.java -->
```java
import java.lang.reflect.Proxy;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.gen.RSAKeyGenerator;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.sun.net.httpserver.HttpServer;

import jakarta.servlet.http.HttpServletRequest;

import org.springframework.aop.framework.ProxyFactory;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authorization.AuthorizationDeniedException;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.parameters.P;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtTypeValidator;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.server.resource.authentication.BearerTokenAuthenticationToken;
import org.springframework.security.oauth2.server.resource.authentication.JwtIssuerAuthenticationManagerResolver;

/**
 * L48 - a multi-tenant Spring Security 7.1.2 resource server, on the real classes:
 * {@link JwtIssuerAuthenticationManagerResolver} with two tenants' issuers served in-process (OIDC discovery + JWKS),
 * the issuer predicate that turns "multi-tenant" into "any issuer that looks like ours" (the resolver then fetches
 * the attacker's discovery document and JWKS itself), and method security ({@code @PreAuthorize} through
 * {@link AuthorizationManagerBeforeMethodInterceptor} on an AOP proxy) binding every call to the caller's tenant.
 * Last, the per-tenant validator composition: {@code createAtJwtValidator()} alone drops the mTLS {@code x5t#S256}
 * check that {@code createDefaultWithValidators} inserts, and nesting it naively rejects every RFC 9068 token.
 */
public final class MultiTenantRsLab {
    static final AtomicInteger DISCOVERY_FETCHES = new AtomicInteger();

    public interface AccountApi {
        @PreAuthorize("hasAuthority('SCOPE_accounts:read') and #tenantId == principal.getClaimAsString('tenant')")
        String read(@P("tenantId") String tenantId, String accountId);
    }

    static final class AccountService implements AccountApi {
        @Override
        public String read(String tenantId, String accountId) {
            return "account " + tenantId + "/" + accountId;
        }
    }

    static String sign(RSAKey k, String iss, String tenant, String scope) throws Exception {
        Instant now = Instant.now();
        SignedJWT j = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).keyID(k.getKeyID()).type(JOSEObjectType.JWT).build(),
                new JWTClaimsSet.Builder().issuer(iss).subject("user@" + tenant).claim("tenant", tenant).claim("scope", scope)
                        .issueTime(Date.from(now)).expirationTime(Date.from(now.plusSeconds(300))).build());
        j.sign(new RSASSASigner(k));
        return j.serialize();
    }

    static String verdictOf(OAuth2TokenValidator<Jwt> v, Jwt jwt) {
        OAuth2TokenValidatorResult r = v.validate(jwt);
        return r.hasErrors() ? "rejected: " + r.getErrors().iterator().next().getDescription() : "accepted";
    }

    static Jwt accessToken(String iss, String aud, boolean bound, boolean withJti) {
        Instant now = Instant.now();
        Jwt.Builder j = Jwt.withTokenValue("opaque-in-this-test").header("alg", "ES256").header("typ", "at+jwt").issuer(iss)
                .audience(List.of(aud)).subject("user@tenant-a").claim("client_id", "partner-app").issuedAt(now).expiresAt(now.plusSeconds(300));
        if (withJti) {
            j.jti("jti-1");
        }
        if (bound) {
            j.claim("cnf", Map.of("x5t#S256", "bwcK0esc3ACC3DB2Y5_lESsXE8o9ltc05O89jdN-dg2")); // RFC 8705 example thumbprint
        }
        return j.build();
    }

    static HttpServletRequest anyRequest() {
        Map<String, Object> attrs = new HashMap<>();
        return (HttpServletRequest) Proxy.newProxyInstance(MultiTenantRsLab.class.getClassLoader(), new Class<?>[] {HttpServletRequest.class},
                (p, m, a) -> switch (m.getName()) {
                    case "getAttribute" -> attrs.get((String) a[0]);
                    case "setAttribute" -> attrs.put((String) a[0], a[1]);
                    case "getRequestURI" -> "/accounts";
                    case "getMethod" -> "GET";
                    case "hashCode" -> System.identityHashCode(p);
                    case "equals" -> p == a[0];
                    default -> null;
                });
    }

    static String authenticate(JwtIssuerAuthenticationManagerResolver resolver, String token) {
        AuthenticationManager m = resolver.resolve(anyRequest());
        try {
            Authentication a = m.authenticate(new BearerTokenAuthenticationToken(token));
            SecurityContextHolder.getContext().setAuthentication(a);
            return "authenticated (" + a.getName() + ")";
        } catch (AuthenticationException e) {
            SecurityContextHolder.clearContext();
            return "401 " + e.getMessage();
        }
    }

    public static void main(String[] args) throws Exception {
        HttpServer srv = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        String base = "http://127.0.0.1:" + srv.getAddress().getPort();
        Map<String, RSAKey> keys = new HashMap<>();
        for (String t : List.of("tenant-a", "tenant-b", "tenant-a-evil")) {
            RSAKey k = new RSAKeyGenerator(2048).keyID(t + "-k1").generate();
            keys.put(t, k);
            String iss = base + "/" + t;
            srv.createContext("/" + t + "/.well-known/openid-configuration", ex -> {
                DISCOVERY_FETCHES.incrementAndGet();
                byte[] b = ("{\"issuer\":\"" + iss + "\",\"jwks_uri\":\"" + iss + "/jwks\",\"subject_types_supported\":[\"public\"],"
                        + "\"id_token_signing_alg_values_supported\":[\"RS256\"]}").getBytes(StandardCharsets.UTF_8);
                ex.getResponseHeaders().add("Content-Type", "application/json");
                ex.sendResponseHeaders(200, b.length);
                ex.getResponseBody().write(b);
                ex.close();
            });
            srv.createContext("/" + t + "/jwks", ex -> {
                byte[] b = new JWKSet(k).toPublicJWKSet().toString().getBytes(StandardCharsets.UTF_8);
                ex.getResponseHeaders().add("Content-Type", "application/json");
                ex.sendResponseHeaders(200, b.length);
                ex.getResponseBody().write(b);
                ex.close();
            });
        }
        srv.start();
        try {
            String a = base + "/tenant-a";
            String b = base + "/tenant-b";
            String evil = base + "/tenant-a-evil";
            String tokA = sign(keys.get("tenant-a"), a, "tenant-a", "accounts:read");
            String tokB = sign(keys.get("tenant-b"), b, "tenant-b", "accounts:read");
            String tokEvil = sign(keys.get("tenant-a-evil"), evil, "tenant-a", "accounts:read"); // claims to be tenant-a

            KbSupport.section("JwtIssuerAuthenticationManagerResolver.fromTrustedIssuers(tenant-a, tenant-b)");
            JwtIssuerAuthenticationManagerResolver exact = JwtIssuerAuthenticationManagerResolver.fromTrustedIssuers(a, b);
            String ra = authenticate(exact, tokA);
            String rb = authenticate(exact, tokB);
            int before = DISCOVERY_FETCHES.get();
            String re = authenticate(exact, tokEvil);
            int fetchedForEvil = DISCOVERY_FETCHES.get() - before;
            KbSupport.info("tenant-a token -> %s | tenant-b token -> %s | issuer .../tenant-a-evil -> %s (discovery fetches for it: %d)",
                    ra, rb, re.replace(base, "<base>"), fetchedForEvil);
            KbSupport.check("exact trusted issuers: both tenants authenticate; the look-alike issuer is refused without any network call",
                    ra.startsWith("authenticated") && rb.startsWith("authenticated") && re.startsWith("401") && fetchedForEvil == 0);

            KbSupport.section("The L5 predicate: issuer -> issuer.startsWith(<base>/tenant-a)");
            JwtIssuerAuthenticationManagerResolver prefix = JwtIssuerAuthenticationManagerResolver.fromTrustedIssuers(iss -> iss.startsWith(a));
            int b2 = DISCOVERY_FETCHES.get();
            String rp = authenticate(prefix, tokEvil);
            KbSupport.info("issuer .../tenant-a-evil -> %s; the resolver fetched the attacker's discovery document %d time(s)", rp,
                    DISCOVERY_FETCHES.get() - b2);
            KbSupport.check("a prefix predicate lets an attacker-chosen issuer in: the resolver fetches ITS discovery + JWKS and accepts ITS token",
                    rp.startsWith("authenticated") && DISCOVERY_FETCHES.get() - b2 == 1);

            KbSupport.section("Method security: @PreAuthorize binds the call to the caller's tenant (real AuthorizationManagerBeforeMethodInterceptor)");
            ProxyFactory pf = new ProxyFactory(new AccountService());
            pf.addInterface(AccountApi.class);
            pf.addAdvice(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
            AccountApi api = (AccountApi) pf.getProxy();
            String[][] calls = {{tokA, "tenant-a", "tenant-a user reads tenant-a/acc-1"}, {tokB, "tenant-a", "tenant-b user reads tenant-a/acc-1"},
                {sign(keys.get("tenant-a"), a, "tenant-a", "profile"), "tenant-a", "tenant-a user without accounts:read"}};
            int allowed = 0;
            for (String[] c : calls) {
                authenticate(exact, c[0]);
                String r;
                try {
                    r = api.read(c[1], "acc-1");
                    allowed++;
                } catch (AuthorizationDeniedException e) {
                    r = "403 " + e.getMessage();
                }
                KbSupport.info("%-42s -> %s", c[2], r);
            }
            KbSupport.check("only the same-tenant caller with the scope is allowed; cross-tenant and missing-scope calls are denied", allowed == 1);

            KbSupport.section("Per-tenant validator composition (real JwtValidators; no client certificate on this request)");
            String aud = "https://accounts.api.example";
            OAuth2TokenValidator<Jwt> atJwt = JwtValidators.createAtJwtValidator().issuer(a).audience(aud).build();
            Map<String, OAuth2TokenValidator<Jwt>> compositions = new java.util.LinkedHashMap<>();
            compositions.put("A createAtJwtValidator() alone", atJwt);
            compositions.put("B createDefaultWithValidators([atJwt])", JwtValidators.createDefaultWithValidators(List.<OAuth2TokenValidator<Jwt>>of(atJwt)));
            compositions.put("C createDefaultWithValidators([typ at+jwt, atJwt])",
                    JwtValidators.createDefaultWithValidators(List.<OAuth2TokenValidator<Jwt>>of(new JwtTypeValidator("at+jwt"), atJwt)));
            Jwt unbound = accessToken(a, aud, false, true);
            Jwt bound = accessToken(a, aud, true, true);
            Jwt noJti = accessToken(a, aud, false, false);
            Map<String, String[]> rows = new java.util.LinkedHashMap<>();
            for (Map.Entry<String, OAuth2TokenValidator<Jwt>> c : compositions.entrySet()) {
                String[] r = {verdictOf(c.getValue(), unbound), verdictOf(c.getValue(), bound), verdictOf(c.getValue(), noJti)};
                rows.put(c.getKey().substring(0, 1), r);
                KbSupport.info("%s%n      unbound at+jwt -> %s%n      mTLS-bound (cnf x5t#S256), no client cert -> %s%n      no jti -> %s", c.getKey(), r[0], r[1], r[2]);
            }
            KbSupport.check("A accepts an mTLS-bound token with no certificate (binding unchecked); B rejects every RFC 9068 token; "
                    + "C accepts the unbound token and rejects both the unproven binding and the missing jti",
                    rows.get("A")[1].equals("accepted") && rows.get("B")[0].startsWith("rejected") && rows.get("C")[0].equals("accepted")
                            && rows.get("C")[1].startsWith("rejected") && rows.get("C")[2].startsWith("rejected"));
        } finally {
            srv.stop(0);
            SecurityContextHolder.clearContext();
        }
        KbSupport.verdict();
    }
}
```

<!-- output:MultiTenantRsLab.java -->
```text

== JwtIssuerAuthenticationManagerResolver.fromTrustedIssuers(tenant-a, tenant-b)
  tenant-a token -> authenticated (user@tenant-a) | tenant-b token -> authenticated (user@tenant-b) | issuer .../tenant-a-evil -> 401 Invalid issuer (discovery fetches for it: 0)
  [PASS] exact trusted issuers: both tenants authenticate; the look-alike issuer is refused without any network call

== The L5 predicate: issuer -> issuer.startsWith(<base>/tenant-a)
  issuer .../tenant-a-evil -> authenticated (user@tenant-a); the resolver fetched the attacker's discovery document 1 time(s)
  [PASS] a prefix predicate lets an attacker-chosen issuer in: the resolver fetches ITS discovery + JWKS and accepts ITS token

== Method security: @PreAuthorize binds the call to the caller's tenant (real AuthorizationManagerBeforeMethodInterceptor)
  tenant-a user reads tenant-a/acc-1         -> account tenant-a/acc-1
  tenant-b user reads tenant-a/acc-1         -> 403 Access Denied
  tenant-a user without accounts:read        -> 403 Access Denied
  [PASS] only the same-tenant caller with the scope is allowed; cross-tenant and missing-scope calls are denied

== Per-tenant validator composition (real JwtValidators; no client certificate on this request)
  A createAtJwtValidator() alone
      unbound at+jwt -> accepted
      mTLS-bound (cnf x5t#S256), no client cert -> accepted
      no jti -> rejected: jti must have a value
  B createDefaultWithValidators([atJwt])
      unbound at+jwt -> rejected: the given typ value needs to be one of [JWT]
      mTLS-bound (cnf x5t#S256), no client cert -> rejected: the given typ value needs to be one of [JWT]
      no jti -> rejected: the given typ value needs to be one of [JWT]
  C createDefaultWithValidators([typ at+jwt, atJwt])
      unbound at+jwt -> accepted
      mTLS-bound (cnf x5t#S256), no client cert -> rejected: Unable to obtain X509Certificate from current request.
      no jti -> rejected: jti must have a value
  [PASS] A accepts an mTLS-bound token with no certificate (binding unchecked); B rejects every RFC 9068 token; C accepts the unbound token and rejects both the unproven binding and the missing jti

verdict: OK (4 checks)
```

Reading the run:
- **"Discovery fetches for it: 0"** is the property to preserve. `fromTrustedIssuers(Collection)` checks the issuer *before* building a decoder. With a predicate, you own that check. L48 shows a one-line change, a prefix test in place of an exact match, turning it into "fetch any URL an attacker names" [M].
- **Tenant from the token, never from the request.** `#tenantId` is the *path or argument* the caller asks for. The authorization compares it with the *token's* tenant. Where tokens don't carry a tenant claim, derive it from `iss` through the registry.
- **Defense in depth:** queries are also scoped by tenant (`WHERE tenant_id = :callerTenant`), plus database row-level security. A missing `@PreAuthorize` on one method then still can't cross tenants [E].
- **The validator table is the subtle result.**
  - **Row A** is what a reader of the RFC 9068 builder's Javadoc would ship, and an mTLS-bound token presented with no certificate passes it.
  - **Row B** is the obvious repair, and it breaks every token. It repeats file 01's trap one level down: `createDefaultWithValidators` adds its `JWT` type check because it finds no `JwtTypeValidator` at the *top level*, and it doesn't look inside the nested validator.
  - **Row C** puts a top-level `JwtTypeValidator("at+jwt")` next to the builder, which suppresses the default. It keeps the binding check and RFC 9068's required `sub`, `iat`, `jti` and `client_id`.
  - Row C is stricter than file 01's composition (issuer, `at+jwt`, `aud`), which doesn't require those claims.

```text
 A  createAtJwtValidator().issuer(iss).audience(aud).build()
      typ at+jwt | exp | sub | iat | jti | client_id | iss | aud            (no x5t#S256 check)
      -> bound token, no client certificate: ACCEPTED

 B  createDefaultWithValidators([ atJwt ])
      + typ JWT          <- added: no JwtTypeValidator at the TOP level; conflicts with atJwt's at+jwt
      + timestamps + x5t#S256 (added)
      + atJwt
      -> every RFC 9068 token: REJECTED ("the given typ value needs to be one of [JWT]")

 C  createDefaultWithValidators([ JwtTypeValidator("at+jwt"), atJwt ])
      typ at+jwt         <- top level: the JWT default is not added
      + timestamps + x5t#S256 (added)
      + atJwt (RFC 9068 required claims, iss, aud)
      -> unbound: accepted | bound without certificate: rejected | missing jti: rejected
```

```mermaid
sequenceDiagram
    autonumber
    participant C as Client (tenant B user)
    participant R as Resource server
    participant RG as Tenant registry
    participant J as Tenant B JWKS
    participant S as AccountService (@PreAuthorize)
    C->>R: GET /tenants/tenant-a/accounts/acc-1 (token iss = tenant B)
    R->>RG: is iss trusted? (exact) -> yes, tenant B
    R->>J: (cached) keys; verify signature, alg, typ, aud, exp
    R->>S: read("tenant-a", "acc-1") as tenant-B principal
    S->>S: #tenantId (tenant-a) == principal tenant (tenant-b)? no
    S-->>C: 403 Access Denied
```

---

## 3. The production configuration

```java
@Configuration(proxyBeanMethods = false)
@EnableMethodSecurity
class ResourceServerConfig {

    @Bean
    SecurityFilterChain api(HttpSecurity http, TenantRegistry tenants) throws Exception {
        Map<String, AuthenticationManager> managers = new ConcurrentHashMap<>();
        AuthenticationManagerResolver<String> byIssuer = iss -> {
            Tenant t = tenants.byIssuer(iss);                             // EXACT lookup; null -> untrusted
            if (t == null) {
                return null;                                              // resolver answers "Invalid issuer", no fetch
            }
            return managers.computeIfAbsent(iss, k -> {
                NimbusJwtDecoder d = NimbusJwtDecoder.withIssuerLocation(iss).jwsAlgorithm(SignatureAlgorithm.ES256).build();
                d.setJwtValidator(JwtValidators.createDefaultWithValidators(List.of(   // L48 row C: keeps x5t#S256
                    new JwtTypeValidator("at+jwt"),                                       // top level: suppresses typ=JWT
                    JwtValidators.createAtJwtValidator().issuer(iss).audience(t.audience()).build())));
                JwtAuthenticationProvider p = new JwtAuthenticationProvider(d);
                p.setJwtAuthenticationConverter(TenantAwareConverter.forTenant(t));   // authorities + tenant claim
                return p::authenticate;
            });
        };
        http.authorizeHttpRequests(a -> a.requestMatchers("/tenants/*/accounts/**").authenticated().anyRequest().denyAll())
            .oauth2ResourceServer(o -> o
                .authenticationManagerResolver(new JwtIssuerAuthenticationManagerResolver(byIssuer))
                .dPoP(Customizer.withDefaults())                             // Folder 04: plus a FAPI verifier factory
                .withObjectPostProcessor(new ObjectPostProcessor<DPoPAuthenticationProvider>() {
                    @Override
                    public <O extends DPoPAuthenticationProvider> O postProcess(O provider) {
                        provider.setDPoPProofVerifierFactory(fapiDpopProofs());   // alg policy + shared jti cache (L27)
                        return provider;
                    }
                }));
        return http.build();
    }
}

public interface AccountApi {
    @PreAuthorize("hasAuthority('SCOPE_accounts:read') and #tenantId == principal.getClaimAsString('tenant')")
    Account read(@P("tenantId") String tenantId, String accountId);
}
```

[D] What the 7.1.2 sources confirm:
- `JwtIssuerAuthenticationManagerResolver` has a public constructor taking `AuthenticationManagerResolver<String>`, plus the static `fromTrustedIssuers(...)` factories used in L48.
  - When the inner resolver returns `null`, it throws `InvalidBearerTokenException("Invalid issuer")`, the 401 L48 prints. Its Javadoc says the supplied resolver "will need to verify that the issuer is trusted".
- `NimbusJwtDecoder.withIssuerLocation(..)` returns the JWK Set URI builder, so `jwsAlgorithm(..)` pins the algorithm per tenant.
- `authenticationManagerResolver(..)` excludes `jwt()` and `opaqueToken()`: configuring both fails with "If an authenticationManagerResolver() is configured, then it takes precedence over any jwt() or opaqueToken() configuration". `dPoP()` composes with it.
- `@P` names parameters for SpEL.
- `@EnableMethodSecurity` registers the same `AuthorizationManagerBeforeMethodInterceptor.preAuthorize()` that L48 runs directly.

`TenantRegistry`, `TenantAwareConverter` and `fapiDpopProofs()` are your classes (Folder 04 L27 for the last).

```yaml
# L7 - per-service settings: trusted tenants come from the registry, never from config wildcards
app:
  tenants:
    - id: tenant-a
      issuer: https://login.tenant-a.example/realms/a
      audience: https://accounts.api.example
    - id: tenant-b
      issuer: https://idp.tenant-b.example
      audience: https://accounts.api.example
```

---

## 4. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 - DO NOT USE: "multi-tenant" by prefix, tenant from the path, no audience.
JwtIssuerAuthenticationManagerResolver resolver =
    JwtIssuerAuthenticationManagerResolver.fromTrustedIssuers(iss -> iss.startsWith("https://login.example.com/"));  // L48
@GetMapping("/tenants/{tenant}/accounts/{id}")
Account read(@PathVariable String tenant, @PathVariable String id) {
    return repo.find(tenant, id);                                     // caller from tenant B reads tenant A by changing the path
}
```

| Concern | L5 | L7 |
|---|---|---|
| Issuer trust | prefix / regex predicate | exact registry; no network call for unknown issuers |
| Per-tenant validation | discovery defaults (`iss`, timestamps, `typ` JWT: no `aud`, rejects `at+jwt`), or `createAtJwtValidator()` alone (drops the mTLS binding) | `createDefaultWithValidators([JwtTypeValidator("at+jwt"), createAtJwtValidator()...])` (L48 row C), ES256 pinned, DPoP/mTLS |
| Tenant identity | from the path or a header | from the token (claim or iss → tenant map) |
| Authorization | route-level `authenticated()` | `@PreAuthorize` scope AND tenant match; PDP for resource-level rules |
| Data access | `find(tenant, id)` with caller-chosen tenant | queries scoped by the caller's tenant + row-level security |
| JWKS fetching | any discovered `jwks_uri` | only registered issuers; cached; refresh on unknown `kid`, rate-limited |

---

## 5. Real-world attack vectors & mitigations

### A1 · Issuer-predicate bypass (SSRF + key injection)

**Attack.** The attacker hosts `https://login.example.com.evil.test/...` or `…/tenant-a-evil`, which matches a prefix or regex predicate. The resolver fetches the attacker's discovery document and JWKS and accepts the attacker's tokens (L48).
**Wire signature.** Outbound discovery and JWKS fetches to unexpected hosts; tokens from new issuers.
**Root cause.** String matching on issuer URLs.
**Mitigation.** An exact registry (`fromTrustedIssuers(collection)` or a map lookup), egress allow-lists for JWKS fetches, and onboarding as an explicit admin action.
**Detection.** Alert on unknown-issuer rejections and on new outbound hosts.

### A2 · Cross-tenant data access with a valid token

**Attack.** A tenant-B user requests `/tenants/tenant-a/...`. The token is valid, and the code trusts the path (L48 method-security section).
**Wire signature.** Path tenant ≠ token tenant.
**Root cause.** Authentication treated as authorization.
**Mitigation.** `@PreAuthorize` tenant binding, tenant-scoped queries, and row-level security.
**Detection.** Log 403s with both tenants; alert on repeated attempts.

### A3 · Missing audience on tenant decoders

**Attack.** A token issued by tenant A's IdP for another application (`aud` = the CRM) is accepted by your API, because discovery-built decoders check only `iss`.
**Wire signature.** Tokens with foreign `aud` values.
**Root cause.** Default per-issuer decoders.
**Mitigation.** A per-tenant `aud` validator (§3), with the audience registered per tenant.
**Detection.** `aud`-mismatch counters per tenant.

### A4 · Algorithm and type confusion per tenant

**Attack.** One tenant's IdP emits RS256, another ES256. A shared decoder accepting both, or a broken `at+jwt` composition removed in frustration, lets ID tokens through (file 01).
**Wire signature.** Mixed `alg`/`typ` per issuer.
**Root cause.** One-size validation.
**Mitigation.** A per-tenant algorithm allow-list from the registry, and L48's row C composition.
**Detection.** Log `alg`/`typ` by tenant.

### A8 · A certificate-bound token replayed without the certificate

**Attack.**
- A partner's mTLS-bound access token (`cnf.x5t#S256`) leaks from its logs.
- The attacker calls an API host where client certificates are optional and presents no certificate.
- The API validates with `createAtJwtValidator()` alone, which doesn't check the binding, so the request succeeds (L48 row A).

**Wire signature.** Tokens carrying `cnf.x5t#S256` arriving on connections with no client certificate.
**Root cause.** The RFC 9068 builder is a separate validator chain that doesn't include Spring's package-private thumbprint validator. Swapping it in for the defaults silently drops RFC 8705 §3 enforcement.
**Mitigation.**
- L48 row C.
- An API-level rule: if a tenant is registered as mTLS-bound, a missing certificate is a 401 before validation.
- A contract test that presents a bound token with no certificate.

**Detection.** Count bound tokens seen without a certificate (it should be zero).

### A5 · Stolen tenant tokens replayed (no sender constraint)

**Attack.** A tenant's access tokens leak from a partner's logs and are replayed against your API.
**Wire signature.** Bearer tokens for DPoP- or mTLS-capable tenants.
**Root cause.** Bearer-only acceptance.
**Mitigation.** DPoP with the FAPI verifier factory and shared `jti` cache (Folder 04 L27), or certificate-bound tokens, required per tenant via the registry.
**Detection.** Bearer usage for tenants flagged as DPoP-required.

### A6 · JWKS fetch amplification

**Attack.** Tokens with random `kid`s force JWKS refetches for every request: DoS against your service and the tenant's IdP.
**Wire signature.** Many distinct unknown `kid`s.
**Root cause.** Refresh-on-unknown-`kid` without rate limits.
**Mitigation.** Rate-limited JWKS refresh per issuer (Nimbus `JWKSourceBuilder` with refresh-ahead and rate limiting, or Spring's cache), and rejecting unknown `kid`s after the limit.
**Detection.** JWKS fetch rate per issuer.

### A7 · Method-security gaps

**Attack.** A new endpoint or service method lacks `@PreAuthorize`, or the class isn't a Spring bean (self-invocation bypasses the proxy). Cross-tenant reads succeed.
**Wire signature.** Data access without decision logs.
**Root cause.** Opt-in annotations.
**Mitigation.** Deny-by-default at routes, tenant-scoped repositories, an ArchUnit test that every public service method in `..service..` has an authorization annotation, and avoiding self-invocation.
**Detection.** Audit logs without a decision id.

---

## 6. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · Design token validation for a B2B API with 500 enterprise tenants, each with its own IdP.</b></summary>

**Initial Prompt.** Tenants onboard weekly.

**L5 Textbook Answer.** "Accept any issuer under our domain pattern; discover keys dynamically."

**How an Attacker Bypasses L5.** Pattern matching admits attacker issuers, and the resolver fetches their keys (L48).

**L7 Principal Defense.**
- **A tenant registry** (issuer, audience, allowed algorithms, DPoP or mTLS requirement), populated by an onboarding workflow.
- **The resolver does an exact lookup:** no network call for unknowns.
- **Per-tenant decoders** validate `aud`, `at+jwt` and the algorithm, and are cached.
- **JWKS refresh is rate-limited.**
- **Tenant binding** in method security and data scoping.

</details>

<details><summary><b>Q2 · Where do you enforce tenant isolation?</b></summary>

**Initial Prompt.** The gateway already authenticates.

**L5 Textbook Answer.** "At the gateway; services trust it."

**How an Attacker Bypasses L5.** A valid tenant-B token passes the gateway. Any service that takes the tenant from the path leaks data (A2).

**L7 Principal Defense.** At three layers:
- **Gateway:** authentication.
- **Service method:** `@PreAuthorize` comparing the requested tenant with the token tenant (L48).
- **Data:** tenant-scoped queries and row-level security.

Tests try cross-tenant access for every endpoint.

</details>

<details><summary><b>Q3 · How do you add DPoP to a Spring resource server for FAPI?</b></summary>

**Initial Prompt.** Spring Security 7.1.2, servlet.

**L5 Textbook Answer.** "`.dPoP(Customizer.withDefaults())`."

**How an Attacker Bypasses L5.** The defaults (Folder 04 L27):
- **accept RS256** and reject EdDSA, against FAPI;
- **refuse a single key's 1,001st proof within 30 s**, which breaks heavy legitimate clients;
- **keep the replay cache per node**, so a captured proof replays once on every node;
- **compare `htu` without normalization**, which fails behind proxies.

**L7 Principal Defense.**
- **`dPoP()` plus `withObjectPostProcessor`** to install a `DPoPProofJwtDecoderFactory` with an algorithm policy and a shared, sized replay cache.
- **Forwarded headers** from trusted proxies only.
- **Bearer refused** for bound tokens (on by default in servlet).

</details>

<details><summary><b>Q4 · Your `@PreAuthorize` uses `#tenantId`. What can go wrong?</b></summary>

**Initial Prompt.** A code review.

**L5 Textbook Answer.** "Nothing; SpEL compares the values."

**How an Attacker Bypasses L5.**
- **Parameter names may not resolve** (compiled without `-parameters` and without `@P`), so `#tenantId` is null. The expression may then evaluate as you didn't intend.
- **Self-invocation** skips the proxy.
- **The token tenant claim may be missing,** so null == null passes.

**L7 Principal Defense.**
- **`@P("tenantId")`.**
- **Fail closed** when the token tenant is absent: `principal.getClaimAsString('tenant') != null`.
- **No self-invocation** of secured methods.
- **Tests** for missing-claim and cross-tenant cases.

</details>

<details><summary><b>Q5 · How do you handle a tenant's IdP rotating keys?</b></summary>

**Initial Prompt.** A tenant rotates without notice.

**L5 Textbook Answer.** "Restart the service to reload keys."

**How an Attacker Bypasses L5.** No attack, but an outage. Cached JWKS can't verify new tokens until a restart, and teams "fix" it by disabling caching, which brings A6.

**L7 Principal Defense.**
- **Per-issuer JWKS cache** with refresh on an unknown `kid`, rate-limited (for example once per 30 s per issuer), and refresh-ahead before the TTL.
- **Alerting** on unknown-`kid` spikes.
- **Contract:** tenants publish new keys before signing with them (Folder 01 file 03 protocol).

</details>

<details><summary><b>Q6 · Should tenant id be a token claim or derived from the issuer?</b></summary>

**Initial Prompt.** Some tenants share an IdP (your CIAM); others bring their own.

**L5 Textbook Answer.** "Always use a `tenant` claim."

**How an Attacker Bypasses L5.** For bring-your-own-IdP tenants, the `tenant` claim is set by *their* IdP. A malicious tenant can assert `tenant: other-tenant`.

**L7 Principal Defense.**
- **Bring-your-own IdP:** tenant = registry lookup by `iss`. Ignore any tenant claim.
- **Your shared CIAM:** a tenant claim minted by *your* AS (admin-managed, never user-writable; Folder 06 file 02).
- **The converter sets one canonical tenant attribute,** which method security reads.

</details>

<details><summary><b>Q7 · How do you test multi-tenant authorization?</b></summary>

**Initial Prompt.** No tests exist.

**L5 Textbook Answer.** "Log in as each tenant and click around."

**How an Attacker Bypasses L5.** Cross-tenant paths are never exercised.

**L7 Principal Defense.** Generated tests per endpoint covering:
- same tenant (allow) and other tenant (deny);
- missing tenant claim (deny);
- foreign `aud` (deny);
- unknown issuer (401 with no outbound call, as in L48);
- an ID token (deny);
- DPoP-required tenant with a bearer token (deny).

Use in-process issuers like L48.

</details>

<details><summary><b>Q8 · A tenant offboards. What has to happen?</b></summary>

**Initial Prompt.** Contract terminated.

**L5 Textbook Answer.** "Delete their data."

**How an Attacker Bypasses L5.** Their issuer remains trusted, so former users with valid tokens or refresh tokens keep calling the API until tokens expire, and the cached decoders stay alive.

**L7 Principal Defense.**
- **Remove from the registry.**
- **Evict the cached `AuthenticationManager`.**
- **Revoke client registrations and outstanding grants** at your AS.
- **Block the issuer at the gateway.**
- **Audit and alert** on any token from the removed issuer.
- **Then run data retention and deletion.**

</details>

<details><summary><b>Q9 · A reviewer replaces the default JWT validators with <code>createAtJwtValidator()</code> "for RFC 9068 compliance". Approve?</b></summary>

**Initial Prompt.** Some tenants use mTLS-bound tokens.

**L5 Textbook Answer.** "Yes: it requires `typ: at+jwt`, `iss`, `aud`, `sub`, `iat`, `jti` and `client_id`, which is stricter than the defaults."

**How an Attacker Bypasses L5.** It is stricter on claims and weaker on binding. The builder doesn't include the `x5t#S256` thumbprint check, so a stolen mTLS-bound token works with no certificate (L48 row A, A8). The obvious repair, wrapping it in `createDefaultWithValidators`, rejects every token (row B), and teams under pressure then revert to row A.

**L7 Principal Defense.**
- **Row C:** `createDefaultWithValidators(List.of(new JwtTypeValidator("at+jwt"), createAtJwtValidator().issuer(..).audience(..).build()))`.
- **Contract tests in CI** for all three behaviours: an unbound token is accepted, a bound token without a certificate is rejected, and a token missing `jti` is rejected.
- **Read the source:** `CollectionUtils.findValueOfType` looks only at top-level elements. That one detail decides which defaults are added.

</details>

---

## 7. Invariants checklist

- [ ] Trusted issuers come from an exact registry; unknown issuers are rejected without any network call.
- [ ] Per-tenant decoders: signature, algorithm allow-list, and the L48 row C validator (`at+jwt`, RFC 9068 claims, `aud` = this API, mTLS binding kept); never `createAtJwtValidator()` alone where bound tokens exist.
- [ ] A `RequestContextFilter` runs before the security chain when DPoP uses a per-issuer resolver (end-to-end DPoP test).
- [ ] DPoP/mTLS per tenant policy, with the FAPI verifier factory and shared replay cache.
- [ ] Tenant identity from the token (shared CIAM) or from `iss` via the registry (bring-your-own IdP), never from request data.
- [ ] `@PreAuthorize` binds every data-touching method to the caller's tenant (`@P` names, fail closed on missing claims); repositories scoped by tenant; row-level security.
- [ ] JWKS refresh rate-limited per issuer; refresh on unknown `kid`.
- [ ] Offboarding evicts decoders, revokes grants, blocks the issuer.

---

## 8. References

- Spring Security reference, *OAuth 2.0 Resource Server Multi-tenancy* — <https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/multitenancy.html>
- Spring Security reference, *Method Security* — <https://docs.spring.io/spring-security/reference/servlet/authorization/method-security.html>
- Spring Security reference, *DPoP-bound Access Tokens* — <https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/dpop-tokens.html>
- RFC 9068 *JWT Profile for OAuth 2.0 Access Tokens* — <https://www.rfc-editor.org/rfc/rfc9068>
- RFC 9449 *OAuth 2.0 DPoP* — <https://www.rfc-editor.org/rfc/rfc9449>
