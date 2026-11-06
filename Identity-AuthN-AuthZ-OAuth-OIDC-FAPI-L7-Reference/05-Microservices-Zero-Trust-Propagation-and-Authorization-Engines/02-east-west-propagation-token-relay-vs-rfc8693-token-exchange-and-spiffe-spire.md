# East-West Propagation: Token Relay vs RFC 8693 Token Exchange, and SPIFFE/SPIRE Workload Identity

> Folder 05 · File 02 of 04 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [01 · Phantom token and introspection](01-gateway-patterns-phantom-token-pattern-opaque-to-jwt-introspection-and-caching.md) · Next: [03 · RBAC, ABAC, OPA, Cedar, PDP/PEP](03-authorization-models-rbac-abac-policy-as-code-opa-cedar-and-pdp-pep-architecture.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L36 `TokenExchangeLab.java` | RFC 8693 Figure 6's nested `act` parses from the fixture: the current actor is service16 and the prior actor service77. Its "informational only" rule for prior actors is cited.<br><br>A call chain edge → orders → payments → ledger (+ admin-api) and a compromised `orders`:<br>• with **relay + L5** resource servers it wins **6 of 6** attacks (lateral replay, skipping a hop, scope escalation, trusting a prior actor, delegation loops, impersonation);<br>• with **exchange + L7** resource servers it wins **0**: `aud` = self, AS exchange policy, current-actor allow-list, depth ≤ 3, `act` required | RFC 8693 §4.1 (fixture) |
| L37 `SasTokenExchangeLab.java` | Spring Authorization Server 7.1.2's real `OAuth2TokenExchangeAuthenticationProvider`, with the configurer's `act`-building customizer:<br>• it **grants a scope the user never had** if the *caller* is registered for it;<br>• it **ignores the requested `audience`** (`aud` = the caller's client_id);<br>• it lets **any** token-exchange client trade a subject token **not issued to it**;<br>• it allows impersonation (no `act`) when no actor token is sent;<br>• it enforces `may_act` only when present.<br><br>A guarded provider and an `aud` customizer fix all four | RFC 8693 §2.1, §4.4; spring-security 7.1.2 |
| L38 `SpiffeSvidLab.java` | SPIFFE X.509-SVIDs (BouncyCastle certificates, JDK PKIX path validation against a per-trust-domain bundle) and JWT-SVIDs, validated as the SPIFFE standards require. The rules are cited verbatim. **11/11** X.509 cases are decided correctly (two URI SANs, `cA=true` leaf, `keyCertSign`, root ID, uppercase, `..`, `%`, trailing slash, wrong-domain signer, cross-domain), as are **6/6** JWT-SVID cases. **Prefix matching** on SPIFFE IDs authorizes 2 workloads it should not | SPIFFE-ID, X509-SVID, JWT-SVID (fixtures, commit 03e916d8) |

**Verification.** Compiled with Folders 01–05 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs all three outputs and requires them byte-identical. L37 runs spring-security 7.1.2's authorization-server classes; Spring behaviour marked [D] was read from `OAuth2TokenExchangeAuthenticationProvider` and `DefaultOAuth2TokenCustomizers`. L38 uses BouncyCastle 1.86 (bcpkix) and the JDK `CertPathValidator`.

Fixtures:
- RFC 8693;
- the SPIFFE standards (`SPIFFE-ID.md`, `X509-SVID.md`, `JWT-SVID.md`, `SPIFFE_Trust_Domain_and_Bundle.md`) at github.com/spiffe/spiffe commit 03e916d8 (2026-10-29), Apache-2.0.

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

Inside the mesh, two questions travel with every call:
- **Which workload is calling?** That is workload identity: SPIFFE/SPIRE, mTLS.
- **On whose behalf, with what authority?** That is delegated user authority: token exchange.

The common anti-pattern answers both with one artefact, the user's token relayed everywhere. Every service can then act as the user at every other service, and a single compromised service owns the user's whole authority.

Results:
- **[M] Token relay turns one compromise into all of the user's authority (L36).** A compromised `orders` wins 6 of 6: it can replay at admin-api, skip a hop, escalate scope, abuse a chain, loop, and impersonate.
- **[M] Exchange plus RS discipline wins 0 of 6 (L36).** Each exchange is bound to one audience, narrowed by AS policy, records the caller in `act`, and the RS authorizes on `aud` = self and the **current** actor only, as RFC 8693 §4.1 requires: prior actors "are informational only".
- **[M] Spring Authorization Server 7.1.2's token exchange needs guarding (L37).**
  - **Scope.** Requested scopes are validated against the *exchanging client's* registered scopes, not the subject token's. `orders` obtains `payments:refund` for alice.
  - **Audience.** The `audience` and `resource` parameters don't reach the issued token; `aud` = the caller's client_id.
  - **Subject token.** Its own audience is never compared with the caller, so `reporting` exchanges a token issued to the BFF for `orders`.
  - **Impersonation.** It works silently without an actor token.
  
  [D] It does build the `act` chain, enforce `may_act` when present, and accept only tokens it issued itself.
- **[M] SPIFFE gets workload authentication right if you validate exactly what the standard says (L38).** That means one URI SAN, a leaf with `cA=false` and no `keyCertSign`, a well-formed ID, and the bundle for *the ID's* trust domain. The authorization layer above it is where systems still fail: prefix matching `…/ns/payments` lets `…/ns/payments-sandbox/…` in.

---

## 1. First principles: two identities per call

```text
  edge ---> orders ---> payments ---> ledger
           |            |             |
           | mTLS: X.509-SVID spiffe://prod.bank.example/ns/orders/sa/api   (WHO is calling: the workload)
           | token: sub=alice, aud=payments, scope=payments:charge, act={sub: orders}   (FOR WHOM, with WHAT authority)

  RELAY (L5):   the same user token (aud = every API, scope = everything alice has) at every hop
  EXCHANGE (L7): at each hop, POST /token grant_type=urn:ietf:params:oauth:grant-type:token-exchange
                 subject_token=<incoming token>  actor_token=<caller's workload token / SVID>
                 audience=<next hop>  scope=<subset policy allows>   ->  60 s token, aud = next hop, act nests
```

RFC 8693 defines two semantics [D: §1.1]:
- **Delegation:** the issued token says "orders acting for alice" (`sub`=alice, `act.sub`=orders).
- **Impersonation:** the issued token is indistinguishable from alice's own.

L7 systems use delegation for service-originated calls, so authorization and audit can see the actor [E]. `may_act` (§4.4) lets the subject token name who may act for it.

---

## 2. Token exchange on the wire (RFC 8693)

```http
POST /oauth2/token HTTP/1.1
Host: as.bank.example
Content-Type: application/x-www-form-urlencoded
Authorization: Basic b3JkZXJzOnNlY3JldA==

grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange&subject_token=eyJ...alice&subject_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token&actor_token=eyJ...orders&actor_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token&audience=https%3A%2F%2Fpayments.internal&scope=payments%3Acharge
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store

{"access_token": "eyJ...", "issued_token_type": "urn:ietf:params:oauth:token-type:access_token", "token_type": "Bearer", "expires_in": 60, "scope": "payments:charge"}
```

```json
{"aud": "https://service26.example.com", "iss": "https://issuer.example.com", "exp": 1443904100, "nbf": 1443904000,
 "sub": "user@example.com", "act": {"sub": "https://service16.example.com", "act": {"sub": "https://service77.example.com"}}}
```

That is RFC 8693 Figure 6. L36 parses it from the fixture: service16 is the current actor, and service77 is a prior one. "For the purpose of applying access control policy, the consumer of a token MUST only consider the token's top-level claims and the party identified as the current actor by the 'act' claim" [D: §4.1].

The AS's duties are not optional just because the RFC leaves policy to you [E]:
- authenticate the caller;
- check that the subject token was issued to (or for) the caller;
- intersect the requested scope with the subject token's scope **and** with the policy for caller → audience;
- set `aud` to the single requested audience;
- record `act`;
- bound the chain depth;
- keep lifetimes short.

```mermaid
sequenceDiagram
    autonumber
    participant O as orders (SVID orders)
    participant AS as Authorization server
    participant P as payments (SVID payments)
    participant L as ledger
    O->>AS: token-exchange: subject=alice's token, actor=orders, audience=payments, scope=payments:charge
    AS->>AS: subject issued to orders? scope within subject and policy(orders->payments)? -> aud=payments, act={orders}, 60 s
    AS-->>O: token T1
    O->>P: mTLS (SVID orders) + Bearer T1
    P->>P: SVID ID == orders? T1.aud == payments? current actor orders allowed? scope?
    P->>AS: token-exchange: subject=T1, actor=payments, audience=ledger, scope=ledger:post
    AS-->>P: token T2 (aud=ledger, act={payments, act={orders}})
    P->>L: mTLS (SVID payments) + Bearer T2
    L->>L: current actor payments allowed; prior actors are informational only
```

---

## 3. L36: relay vs exchange, from first principles

<!-- listing:TokenExchangeLab.java -->
```java
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * L36 - east-west propagation: token relay vs RFC 8693 token exchange, from first principles.
 *
 * <ul>
 *   <li>Oracle: RFC 8693 Figure 6's nested act claim parses from the fixture; the current actor is the outermost act,
 *       and the RFC's rule that prior actors are "informational only" is cited;</li>
 *   <li>a call chain edge -> orders -> payments -> ledger, plus admin-api; RELAY forwards the user's broad token, EXCHANGE
 *       asks the AS at every hop for a token with aud = next hop, scope narrowed by policy, and the caller as act;</li>
 *   <li>six attacks by a compromised orders service (and one misbehaving RS), against L5 resource servers (signature +
 *       scope) and L7 resource servers (aud = self, current actor allow-listed, scope, chain depth).</li>
 * </ul>
 */
public final class TokenExchangeLab {
    static final String AS = "https://as.bank.example";
    static final long NOW = 1_767_225_600L;
    static Jose.Jwk asKey;

    static String mint(Map<String, Object> claims) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("typ", "at+jwt");
        h.put("alg", "ES256");
        return Jose.sign(h, MiniJson.write(claims).getBytes(StandardCharsets.UTF_8), asKey);
    }

    static Map<String, Object> claims(String jwt) {
        Jose.Parts p = Jose.parse(jwt);
        if (!Jose.rawVerify("ES256", asKey, p.signingInput(), p.sig())) {
            throw new IllegalArgumentException("signature");
        }
        return MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
    }

    /** AS exchange policy: which caller may obtain which audience, with which scopes at most. */
    static final Map<String, Map<String, Set<String>>> POLICY = Map.of(
            "orders", Map.of("https://payments.internal", Set.of("payments:charge")),
            "payments", Map.of("https://ledger.internal", Set.of("ledger:post")));

    /** RFC 8693 token exchange at the AS: subject_token + the caller's own identity (actor) -> narrowed token. */
    @SuppressWarnings("unchecked")
    static String exchange(String subjectToken, String caller, String audience, Set<String> scope) {
        Map<String, Object> s = claims(subjectToken);
        Map<String, Set<String>> allowed = POLICY.getOrDefault(caller, Map.of());
        if (!allowed.containsKey(audience)) {
            return "400 invalid_target (" + caller + " may not call " + audience + ")";
        }
        if (!allowed.get(audience).containsAll(scope)) {
            return "400 invalid_scope (" + scope + " exceeds policy " + allowed.get(audience) + ")";
        }
        Map<String, Object> act = new LinkedHashMap<>();
        act.put("sub", caller);
        if (s.containsKey("act")) {
            act.put("act", s.get("act"));                          // prior actors nest inside the new current actor
        }
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("iss", AS);
        c.put("sub", s.get("sub"));
        c.put("aud", audience);
        c.put("scope", String.join(" ", scope));
        c.put("exp", NOW + 60);
        c.put("act", act);
        return mint(c);
    }

    static int depth(Object act) {
        int d = 0;
        while (act instanceof Map<?, ?> m) {
            d++;
            act = m.get("act");
        }
        return d;
    }

    @SuppressWarnings("unchecked")
    static String currentActor(Map<String, Object> c) {
        return c.get("act") instanceof Map<?, ?> m ? (String) m.get("sub") : null;
    }

    /** The resource server's decision. L5: signature + scope. L7: aud = me, current actor allow-listed, scope, depth <= 3. */
    @SuppressWarnings("unchecked")
    static String rs(String me, String token, String needScope, Set<String> allowedActors, boolean l7) {
        Map<String, Object> c;
        try {
            c = claims(token);
        } catch (RuntimeException e) {
            return "401";
        }
        if (!List.of(String.valueOf(c.get("scope")).split(" ")).contains(needScope)) {
            return "403 scope";
        }
        if (!l7) {
            return "200";
        }
        Object aud = c.get("aud");
        if (!(me.equals(aud) || aud instanceof List<?> l && l.contains(me))) {
            return "401 aud " + aud;
        }
        String actor = currentActor(c);
        if (actor == null || !allowedActors.contains(actor)) {
            return "403 current actor " + actor + " not allowed";
        }
        if (depth(c.get("act")) > 3) {
            return "403 delegation chain too deep";
        }
        return "200";
    }

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String r8693 = KbSupport.rfc(fx, "rfc8693.txt");
        KbSupport.section("RFC 8693 Figure 6: nested act (fixture)");
        int cap = r8693.indexOf("Figure 6: Nested Actor Claim");
        int st = r8693.lastIndexOf("\"aud\":\"https://service26.example.com\"", cap);
        int open = r8693.lastIndexOf("{", st);
        int close = r8693.lastIndexOf("}", cap);
        Map<String, Object> fig6 = MiniJson.object(r8693.substring(open, close + 1));
        String current = currentActor(fig6);
        String prior = (String) ((Map<String, Object>) ((Map<String, Object>) fig6.get("act")).get("act")).get("sub");
        KbSupport.check("current actor = " + current + ", prior actor = " + prior + ", depth " + depth(fig6.get("act")),
                "https://service16.example.com".equals(current) && "https://service77.example.com".equals(prior) && depth(fig6.get("act")) == 2);
        KbSupport.mustCite(r8693, "Prior actors identified by any nested \"act\" claims are informational only and are not to be considered in access control decisions",
                "RFC 8693 section 4.1");

        asKey = Jose.generate("ES256", new SecureRandom());
        Map<String, Object> user = new LinkedHashMap<>();
        user.put("iss", AS);
        user.put("sub", "alice");
        user.put("aud", List.of("https://orders.internal", "https://payments.internal", "https://ledger.internal", "https://admin.internal"));
        user.put("scope", "orders:read payments:charge ledger:post admin:users");
        user.put("exp", NOW + 3_600);
        String userToken = mint(user); // the broad token a relay architecture forwards

        KbSupport.section("Six attacks from a compromised orders service (relay vs exchange; L5 vs L7 resource servers)");
        String ordersToPayments = exchange(userToken, "orders", "https://payments.internal", Set.of("payments:charge"));
        String paymentsToLedger = exchange(ordersToPayments, "payments", "https://ledger.internal", Set.of("ledger:post"));
        // a token whose CURRENT actor is batch-tools but which carries payments as a prior actor
        Map<String, Object> laundered = new LinkedHashMap<>(claims(paymentsToLedger));
        laundered.put("act", Map.of("sub", "batch-tools", "act", laundered.get("act")));
        String launderedToken = mint(laundered);
        Map<String, Object> deep = new LinkedHashMap<>(claims(paymentsToLedger));
        deep.put("act", Map.of("sub", "payments", "act", Map.of("sub", "orders", "act", Map.of("sub", "payments", "act", deep.get("act")))));
        String deepToken = mint(deep);
        Map<String, Object> noAct = new LinkedHashMap<>(claims(paymentsToLedger));
        noAct.remove("act");
        String impersonation = mint(noAct);
        List<String[]> rows = new ArrayList<>();
        rows.add(new String[] {"0 legitimate: payments posts to ledger (exchanged token)",
            rs("https://ledger.internal", userToken, "ledger:post", Set.of("payments"), false), rs("https://ledger.internal", paymentsToLedger, "ledger:post", Set.of("payments"), true), "ok"});
        rows.add(new String[] {"1 orders replays the user's token at admin-api",
            rs("https://admin.internal", userToken, "admin:users", Set.of("ops-console"), false),
            exchange(userToken, "orders", "https://admin.internal", Set.of("admin:users")), "attack"});
        rows.add(new String[] {"2 orders skips payments and posts to ledger directly",
            rs("https://ledger.internal", userToken, "ledger:post", Set.of("payments"), false), rs("https://ledger.internal", ordersToPayments, "ledger:post", Set.of("payments"), true), "attack"});
        rows.add(new String[] {"3 orders asks the AS for payments:refund",
            rs("https://payments.internal", userToken, "payments:charge", Set.of("orders"), false),
            exchange(userToken, "orders", "https://payments.internal", Set.of("payments:refund")), "attack"});
        rows.add(new String[] {"4 RS trusts ANY actor in the chain (batch-tools current, payments prior)",
            "200 (chain contains payments)", rs("https://ledger.internal", launderedToken, "ledger:post", Set.of("payments"), true), "attack"});
        rows.add(new String[] {"5 delegation loop payments->orders->payments->... depth 5",
            rs("https://ledger.internal", deepToken, "ledger:post", Set.of("payments"), false), rs("https://ledger.internal", deepToken, "ledger:post", Set.of("payments"), true), "attack"});
        rows.add(new String[] {"6 exchanged token without act (impersonation: looks like alice herself)",
            rs("https://ledger.internal", impersonation, "ledger:post", Set.of("payments"), false), rs("https://ledger.internal", impersonation, "ledger:post", Set.of("payments"), true), "attack"});
        KbSupport.info("%-72s %-34s %s", "case", "RELAY + L5 resource server", "EXCHANGE + L7 resource server");
        int relayWins = 0;
        int exchangeWins = 0;
        for (String[] r : rows) {
            KbSupport.info("%-72s %-34s %s", r[0], r[1], r[2].startsWith("eyJ") ? "200 (token issued)" : r[2]);
            if (r[3].equals("attack")) {
                relayWins += r[1].startsWith("200") ? 1 : 0;
                exchangeWins += r[2].startsWith("200") || r[2].startsWith("eyJ") ? 1 : 0;
            }
        }
        KbSupport.check("relay + L5: the compromised service wins all 6 (every hop accepts the user's broad token)", relayWins == 6);
        KbSupport.check("exchange + L7: it wins none - aud, exchange policy, current-actor rule, depth limit and required act", exchangeWins == 0);
        Map<String, Object> issued = claims(paymentsToLedger);
        KbSupport.check("the exchanged ledger token: aud " + issued.get("aud") + ", scope " + issued.get("scope") + ", act " + issued.get("act") + ", 60 s",
                "https://ledger.internal".equals(issued.get("aud")) && "payments".equals(currentActor(issued)) && depth(issued.get("act")) == 2);
        KbSupport.verdict();
    }
}
```

<!-- output:TokenExchangeLab.java -->
```text

== RFC 8693 Figure 6: nested act (fixture)
  [PASS] current actor = https://service16.example.com, prior actor = https://service77.example.com, depth 2
  [PASS] constant cited verbatim from fixture: RFC 8693 section 4.1

== Six attacks from a compromised orders service (relay vs exchange; L5 vs L7 resource servers)
  case                                                                     RELAY + L5 resource server         EXCHANGE + L7 resource server
  0 legitimate: payments posts to ledger (exchanged token)                 200                                200
  1 orders replays the user's token at admin-api                           200                                400 invalid_target (orders may not call https://admin.internal)
  2 orders skips payments and posts to ledger directly                     200                                403 scope
  3 orders asks the AS for payments:refund                                 200                                400 invalid_scope ([payments:refund] exceeds policy [payments:charge])
  4 RS trusts ANY actor in the chain (batch-tools current, payments prior) 200 (chain contains payments)      403 current actor batch-tools not allowed
  5 delegation loop payments->orders->payments->... depth 5                200                                403 delegation chain too deep
  6 exchanged token without act (impersonation: looks like alice herself)  200                                403 current actor null not allowed
  [PASS] relay + L5: the compromised service wins all 6 (every hop accepts the user's broad token)
  [PASS] exchange + L7: it wins none - aud, exchange policy, current-actor rule, depth limit and required act
  [PASS] the exchanged ledger token: aud https://ledger.internal, scope ledger:post, act {sub=payments, act={sub=orders}}, 60 s

verdict: OK (5 checks)
```

Reading the run:
- **Case 4 is the subtle one.** An RS that "trusts the chain if `payments` appears anywhere in it" accepts a token whose *current* actor is `batch-tools`. RFC 8693 says to ignore prior actors for access control, so the L7 RS checks only the outermost `act.sub`.
- **Case 6:** an exchanged token without `act` is impersonation. The L7 RS requires a current actor on service-originated routes. Impersonation, if needed at all, belongs to narrowly allow-listed break-glass tooling [E].
- **Bind the two identities.** The current actor in the token should equal the SPIFFE ID authenticated by mTLS on the same connection. Otherwise a stolen exchanged token can be replayed by any workload [E].

---

## 4. L37: Spring Authorization Server 7.1.2's token exchange, run for real

<!-- listing:SasTokenExchangeLab.java -->
```java
import java.security.Principal;
import java.time.Instant;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.security.authentication.AuthenticationProvider;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.server.authorization.InMemoryOAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.OAuth2Authorization;
import org.springframework.security.oauth2.server.authorization.OAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.OAuth2TokenType;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2AccessTokenAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2ClientAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2TokenExchangeAuthenticationProvider;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2TokenExchangeAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.context.AuthorizationServerContext;
import org.springframework.security.oauth2.server.authorization.context.AuthorizationServerContextHolder;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.OAuth2TokenFormat;
import org.springframework.security.oauth2.server.authorization.settings.TokenSettings;
import org.springframework.security.oauth2.server.authorization.token.DelegatingOAuth2TokenGenerator;
import org.springframework.security.oauth2.server.authorization.token.OAuth2AccessTokenGenerator;

/**
 * L37 - RFC 8693 token exchange in Spring Authorization Server 7.1.2, run on the real
 * {@link OAuth2TokenExchangeAuthenticationProvider} with the access-token customizer the configurer installs (the
 * package-private {@code DefaultOAuth2TokenCustomizers}, via reflection, which builds the {@code act} chain).
 * What does the AS check before it mints a token for a service acting for a user? Then a decorator that adds the
 * missing checks: requested scope within the subject token's scope, the exchanging client within the subject
 * token's audience, an actor token for delegation, and a requested audience that becomes the new token's aud.
 */
public final class SasTokenExchangeLab {
    static final String ACCESS = "urn:ietf:params:oauth:token-type:access_token";

    static RegisteredClient client(String id, String... scopes) {
        return RegisteredClient.withId("rc-" + id).clientId(id).clientSecret("{noop}x").clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.TOKEN_EXCHANGE).authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .scopes(s -> s.addAll(List.of(scopes)))
                .tokenSettings(TokenSettings.builder().accessTokenFormat(OAuth2TokenFormat.REFERENCE).build()).build();
    }

    static void save(OAuth2AuthorizationService svc, RegisteredClient owner, String principal, String tokenValue, Set<String> scopes,
                     Map<String, Object> claims, boolean user) {
        Instant now = Instant.now();
        Authentication p = user ? UsernamePasswordAuthenticationToken.authenticated(principal, null, List.of())
                : new OAuth2ClientAuthenticationToken(owner, ClientAuthenticationMethod.CLIENT_SECRET_BASIC, null);
        svc.save(OAuth2Authorization.withRegisteredClient(owner).id("auth-" + tokenValue).principalName(principal)
                .authorizationGrantType(user ? AuthorizationGrantType.AUTHORIZATION_CODE : AuthorizationGrantType.CLIENT_CREDENTIALS)
                .authorizedScopes(scopes).attribute(Principal.class.getName(), p)
                .token(new OAuth2AccessToken(OAuth2AccessToken.TokenType.BEARER, tokenValue, now, now.plusSeconds(300), scopes),
                        md -> md.put(OAuth2Authorization.Token.CLAIMS_METADATA_NAME, claims)).build());
    }

    /** The missing checks, in front of Spring's provider. */
    record GuardedExchange(AuthenticationProvider delegate, OAuth2AuthorizationService svc, Map<String, Set<String>> audienceAllowList)
            implements AuthenticationProvider {
        @Override
        public Authentication authenticate(Authentication a) {
            OAuth2TokenExchangeAuthenticationToken req = (OAuth2TokenExchangeAuthenticationToken) a;
            String clientId = ((OAuth2ClientAuthenticationToken) req.getPrincipal()).getRegisteredClient().getClientId();
            OAuth2Authorization subject = svc.findByToken(req.getSubjectToken(), OAuth2TokenType.ACCESS_TOKEN);
            if (subject == null) {
                return delegate.authenticate(a); // Spring answers invalid_grant
            }
            Map<String, Object> claims = subject.getAccessToken().getClaims();
            Object aud = claims == null ? null : claims.get("aud");
            if (!(aud instanceof List<?> l && l.contains(clientId))) {
                throw fail("invalid_grant", "subject token was not issued to " + clientId);
            }
            if (req.getScopes() != null && !subject.getAuthorizedScopes().containsAll(req.getScopes())) {
                throw fail("invalid_scope", "requested scope exceeds the subject token's scope " + subject.getAuthorizedScopes());
            }
            if (req.getActorToken() == null) {
                throw fail("invalid_request", "delegation requires an actor_token (no impersonation)");
            }
            if (req.getAudiences() == null || req.getAudiences().size() != 1
                    || !audienceAllowList.getOrDefault(clientId, Set.of()).containsAll(req.getAudiences())) {
                throw fail("invalid_target", "audience " + req.getAudiences() + " not allowed for " + clientId);
            }
            return delegate.authenticate(a); // the guarded generator's customizer sets aud = the requested audience
        }

        static OAuth2AuthenticationException fail(String code, String description) {
            return new OAuth2AuthenticationException(new OAuth2Error(code, description, null));
        }

        @Override
        public boolean supports(Class<?> c) {
            return delegate.supports(c);
        }
    }

    static String exchange(AuthenticationProvider p, OAuth2AuthorizationService svc, RegisteredClient caller, String subjectToken, String actorToken,
                           Set<String> scopes, Set<String> audiences) {
        OAuth2ClientAuthenticationToken principal = new OAuth2ClientAuthenticationToken(caller, ClientAuthenticationMethod.CLIENT_SECRET_BASIC, null);
        try {
            OAuth2AccessTokenAuthenticationToken r = (OAuth2AccessTokenAuthenticationToken) p.authenticate(new OAuth2TokenExchangeAuthenticationToken(
                    ACCESS, subjectToken, ACCESS, principal, actorToken, actorToken == null ? null : ACCESS, null, audiences, scopes, new HashMap<>()));
            OAuth2Authorization issued = svc.findByToken(r.getAccessToken().getTokenValue(), OAuth2TokenType.ACCESS_TOKEN);
            Map<String, Object> c = issued.getAccessToken().getClaims();
            return "issued: scope=" + r.getAccessToken().getScopes() + " aud=" + c.get("aud") + " sub=" + c.get("sub") + (c.containsKey("act") ? " act=" + c.get("act") : " (no act)");
        } catch (OAuth2AuthenticationException e) {
            return "400 " + e.getError().getErrorCode() + (e.getError().getDescription() != null ? " (" + e.getError().getDescription() + ")" : "");
        }
    }

    public static void main(String[] args) throws Exception {
        AuthorizationServerSettings settings = AuthorizationServerSettings.builder().issuer("https://as.bank.example").build();
        AuthorizationServerContextHolder.setContext(new AuthorizationServerContext() {
            @Override
            public String getIssuer() {
                return settings.getIssuer();
            }

            @Override
            public AuthorizationServerSettings getAuthorizationServerSettings() {
                return settings;
            }
        });
        RegisteredClient bff = client("web-bff", "orders:read");
        RegisteredClient orders = client("orders", "orders:read", "payments:refund");
        RegisteredClient reporting = client("reporting", "orders:read", "reports:read");
        OAuth2AuthorizationService svc = new InMemoryOAuth2AuthorizationService();
        // alice's token, issued to the BFF, for the orders API
        save(svc, bff, "alice", "user-at", Set.of("orders:read"),
                new LinkedHashMap<>(Map.of("iss", "https://as.bank.example", "sub", "alice", "aud", List.of("orders"), "scope", List.of("orders:read"))), true);
        // alice's token that names who may act for her
        save(svc, bff, "alice", "user-at-mayact", Set.of("orders:read"), new LinkedHashMap<>(Map.of("iss", "https://as.bank.example", "sub", "alice",
                "aud", List.of("orders"), "may_act", Map.of("iss", "https://as.bank.example", "sub", "orders"))), true);
        // workload tokens (client credentials) used as actor tokens
        save(svc, orders, "orders", "orders-at", Set.of(), new LinkedHashMap<>(Map.of("iss", "https://as.bank.example", "sub", "orders")), false);
        save(svc, reporting, "reporting", "reporting-at", Set.of(), new LinkedHashMap<>(Map.of("iss", "https://as.bank.example", "sub", "reporting")), false);

        java.lang.reflect.Method m = Class.forName("org.springframework.security.config.annotation.web.configurers.oauth2.server.authorization.DefaultOAuth2TokenCustomizers")
                .getDeclaredMethod("accessTokenCustomizer");
        m.setAccessible(true);
        OAuth2AccessTokenGenerator gen = new OAuth2AccessTokenGenerator();
        @SuppressWarnings("unchecked")
        org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer<org.springframework.security.oauth2.server.authorization.token.OAuth2TokenClaimsContext> cust =
                (org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer<org.springframework.security.oauth2.server.authorization.token.OAuth2TokenClaimsContext>) m.invoke(null);
        gen.setAccessTokenCustomizer(cust);
        AuthenticationProvider stock = new OAuth2TokenExchangeAuthenticationProvider(svc, new DelegatingOAuth2TokenGenerator(gen));
        OAuth2AccessTokenGenerator gen2 = new OAuth2AccessTokenGenerator();
        gen2.setAccessTokenCustomizer(ctx -> {             // Spring's act/cnf customizer, then aud = the requested audience
            cust.customize(ctx);
            if (ctx.getAuthorizationGrant() instanceof OAuth2TokenExchangeAuthenticationToken t && t.getAudiences() != null && !t.getAudiences().isEmpty()) {
                ctx.getClaims().audience(List.copyOf(t.getAudiences()));
            }
        });
        AuthenticationProvider guarded = new GuardedExchange(new OAuth2TokenExchangeAuthenticationProvider(svc, new DelegatingOAuth2TokenGenerator(gen2)),
                svc, Map.of("orders", Set.of("https://payments.internal")));

        Object[][] cases = {
            {"a orders acts for alice (actor_token), scope orders:read", orders, "user-at", "orders-at", Set.of("orders:read"), Set.of("https://payments.internal")},
            {"b orders asks for payments:refund (not in alice's token)", orders, "user-at", "orders-at", Set.of("payments:refund"), Set.of("https://payments.internal")},
            {"c audience=https://payments.internal requested", orders, "user-at", "orders-at", Set.of("orders:read"), Set.of("https://payments.internal")},
            {"d reporting (aud of alice's token is orders) exchanges it", reporting, "user-at", "reporting-at", Set.of("orders:read"), Set.of("https://payments.internal")},
            {"e no actor_token: impersonation of alice", orders, "user-at", null, Set.of("orders:read"), Set.of("https://payments.internal")},
            {"f may_act names orders; reporting tries", reporting, "user-at-mayact", "reporting-at", Set.of("orders:read"), Set.of("https://payments.internal")},
            {"g a token this AS never issued", orders, "forged-at", "orders-at", Set.of("orders:read"), Set.of("https://payments.internal")}};
        Map<String, String> st = new LinkedHashMap<>();
        Map<String, String> gd = new LinkedHashMap<>();
        KbSupport.section("Stock OAuth2TokenExchangeAuthenticationProvider vs the guarded provider");
        for (Object[] c : cases) {
            String k = ((String) c[0]).substring(0, 1);
            @SuppressWarnings("unchecked")
            Set<String> sc = (Set<String>) c[4];
            @SuppressWarnings("unchecked")
            Set<String> au = (Set<String>) c[5];
            st.put(k, exchange(stock, svc, (RegisteredClient) c[1], (String) c[2], (String) c[3], sc, au));
            gd.put(k, exchange(guarded, svc, (RegisteredClient) c[1], (String) c[2], (String) c[3], sc, au));
            KbSupport.info("%-58s stock   -> %s", c[0], st.get(k));
            KbSupport.info("%-58s guarded -> %s", "", gd.get(k));
        }
        KbSupport.check("stock builds the act chain for delegation (case a)", st.get("a").contains("act={iss=https://as.bank.example, sub=orders}"));
        KbSupport.check("stock grants a scope the user never granted, if the CALLER is registered for it (case b)", st.get("b").startsWith("issued: scope=[payments:refund]"));
        KbSupport.check("stock ignores the requested audience: aud = the caller's client_id (case c)", st.get("c").contains("aud=[orders]"));
        KbSupport.check("stock lets any token-exchange client trade a token that was not issued to it (case d) and impersonate without act (case e)",
                st.get("d").startsWith("issued") && st.get("e").contains("(no act)"));
        KbSupport.check("stock enforces may_act when present (f) and rejects foreign tokens (g)", st.get("f").startsWith("400") && st.get("g").startsWith("400 invalid_grant"));
        KbSupport.check("guarded: a and c are issued with aud = the requested audience; b, d and e are refused with precise errors",
                gd.get("a").contains("aud=[https://payments.internal]") && gd.get("c").contains("aud=[https://payments.internal]") && gd.get("b").startsWith("400 invalid_scope") && gd.get("d").startsWith("400 invalid_grant (subject token was not issued")
                        && gd.get("e").startsWith("400 invalid_request"));
        KbSupport.verdict();
    }
}
```

<!-- output:SasTokenExchangeLab.java -->
```text

== Stock OAuth2TokenExchangeAuthenticationProvider vs the guarded provider
  a orders acts for alice (actor_token), scope orders:read   stock   -> issued: scope=[orders:read] aud=[orders] sub=alice act={iss=https://as.bank.example, sub=orders}
                                                             guarded -> issued: scope=[orders:read] aud=[https://payments.internal] sub=alice act={iss=https://as.bank.example, sub=orders}
  b orders asks for payments:refund (not in alice's token)   stock   -> issued: scope=[payments:refund] aud=[orders] sub=alice act={iss=https://as.bank.example, sub=orders}
                                                             guarded -> 400 invalid_scope (requested scope exceeds the subject token's scope [orders:read])
  c audience=https://payments.internal requested             stock   -> issued: scope=[orders:read] aud=[orders] sub=alice act={iss=https://as.bank.example, sub=orders}
                                                             guarded -> issued: scope=[orders:read] aud=[https://payments.internal] sub=alice act={iss=https://as.bank.example, sub=orders}
  d reporting (aud of alice's token is orders) exchanges it  stock   -> issued: scope=[orders:read] aud=[reporting] sub=alice act={iss=https://as.bank.example, sub=reporting}
                                                             guarded -> 400 invalid_grant (subject token was not issued to reporting)
  e no actor_token: impersonation of alice                   stock   -> issued: scope=[orders:read] aud=[orders] sub=alice (no act)
                                                             guarded -> 400 invalid_request (delegation requires an actor_token (no impersonation))
  f may_act names orders; reporting tries                    stock   -> 400 invalid_grant
                                                             guarded -> 400 invalid_grant (subject token was not issued to reporting)
  g a token this AS never issued                             stock   -> 400 invalid_grant
                                                             guarded -> 400 invalid_grant
  [PASS] stock builds the act chain for delegation (case a)
  [PASS] stock grants a scope the user never granted, if the CALLER is registered for it (case b)
  [PASS] stock ignores the requested audience: aud = the caller's client_id (case c)
  [PASS] stock lets any token-exchange client trade a token that was not issued to it (case d) and impersonate without act (case e)
  [PASS] stock enforces may_act when present (f) and rejects foreign tokens (g)
  [PASS] guarded: a and c are issued with aud = the requested audience; b, d and e are refused with precise errors

verdict: OK (6 checks)
```

Reading the run (the source facts behind it are [D]):
- **Scope.** `validateRequestedScopes(registeredClient, requestedScopes)` compares the request against the *exchanging client's* scopes. If the request has no scopes, the subject's scopes are copied, but they are still validated only against the client. Case b is the consequence: the user consented to `orders:read`, and `orders` walks away with `payments:refund` in alice's name.
- **Audience.** `audiences` and `resources` are parsed into the authentication token, but the generators set `aud` to the client_id. Case c shows the `audience=https://payments.internal` request ignored.
- **The subject token's own audience** is never compared with the caller (case d). Any service that receives, logs or steals a user token and holds the token-exchange grant can trade it.
- **Impersonation** is silent: with no `actor_token`, no `act` claim is added (case e).
- **What is done right:** `may_act` is enforced when present (case f), subject and actor tokens must be active tokens from this AS (case g), and `DefaultOAuth2TokenCustomizers` nests `act` correctly (case a).
- **The fix is two pieces of public API:**
  - an `AuthenticationProvider` decorator, `GuardedExchange`, that checks subject `aud` ∋ caller, scope ⊆ subject scope, actor token required, and audience allow-list per caller;
  - an access-token customizer that sets `aud` = the requested audience.
  
  Install both via `tokenEndpoint(t -> t.authenticationProviders(...))` and the token customizer bean (§7).

---

## 5. SPIFFE and SPIRE: workload identity without shared secrets

SPIFFE defines the identity format and the documents:
- the **SPIFFE ID** is a URI `spiffe://<trust-domain>/<path>`;
- the **X.509-SVID** carries the ID as the single URI SAN of a short-lived certificate, used for mTLS;
- the **JWT-SVID** carries the ID as `sub`, with a mandatory `aud`, for L7 hops where mTLS terminates;
- the **trust bundle** is per trust domain.

**SPIRE** is the reference implementation. A server is the CA per trust domain. Agents run on nodes and *attest* workloads by kernel or orchestrator facts (Kubernetes service account, pod UID, AWS instance identity, process UID) before issuing SVIDs through the Workload API. There are no secrets to bootstrap: the workload proves *where* it runs, not something it knows [D: SPIFFE overview; E].

```text
  X.509-SVID (leaf: the workload's identity)                 signing certificate (the trust domain's CA)
  ------------------------------------------------           ------------------------------------------
  SAN URI: spiffe://prod.bank.example/ns/payments/sa/api      SAN URI (optional): spiffe://prod.bank.example
           exactly ONE URI SAN; non-root path                            no path component
  BasicConstraints: cA = false                                BasicConstraints: cA = true
  KeyUsage (critical): digitalSignature                       KeyUsage (critical): keyCertSign [, cRLSign]
           never keyCertSign / cRLSign                        never used for authentication
  EKU: serverAuth + clientAuth (if present)
  validity: minutes to hours (SPIRE rotates via the Workload API)
  validated with: RFC 5280 path validation against the bundle of trust domain "prod.bank.example" ONLY
```

The validation rules L38 enforces, verbatim from the standards:
- "An X.509 SVID MUST contain exactly one URI SAN".
- "Signing certificates MUST set the `cA` field to `true`, and leaf certificates MUST set the `cA` field to `false`."
- "Leaf SVIDs MUST NOT set `keyCertSign` or `cRLSign`."
- The trust domain "MUST be lowercase" and contain only `[a-z0-9.-_]`. The path "MUST NOT include segments that are empty or are relative path modifiers", percent-encoding, or a trailing `/`.
- JWT-SVID: "Validators MUST reject tokens without an `aud` claim set". `exp` is required. `typ`, if set, is `JWT` or `JOSE`. No other headers, so no `jku` or `x5u`.

<!-- listing:SpiffeSvidLab.java -->
```java
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.SecureRandom;
import java.security.cert.CertPathValidator;
import java.security.cert.CertificateFactory;
import java.security.cert.PKIXParameters;
import java.security.cert.TrustAnchor;
import java.security.cert.X509Certificate;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.ExtendedKeyUsage;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.GeneralName;
import org.bouncycastle.asn1.x509.GeneralNames;
import org.bouncycastle.asn1.x509.KeyPurposeId;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

/**
 * L38 - SPIFFE workload identity: X.509-SVIDs and JWT-SVIDs validated exactly as the SPIFFE standards require
 * (rules cited verbatim from the fixtures), with real certificates (BouncyCastle) and real RFC 5280 path validation
 * (the JDK's PKIX CertPathValidator) against a per-trust-domain bundle. Eleven X.509 cases, six JWT cases, and the
 * authorization bug that survives perfect authentication: prefix matching on SPIFFE IDs.
 */
public final class SpiffeSvidLab {
    static final SecureRandom RNG = new SecureRandom();
    static long serial = 100;

    static KeyPair ec() throws Exception {
        java.security.KeyPairGenerator g = java.security.KeyPairGenerator.getInstance("EC");
        g.initialize(new java.security.spec.ECGenParameterSpec("secp256r1"), RNG);
        return g.generateKeyPair();
    }

    /** Build a certificate with any mix of SPIFFE-relevant properties (for valid and deliberately broken SVIDs). */
    static X509Certificate cert(java.security.PublicKey subjectKey, KeyPair issuer, String issuerDn, List<String> uris, boolean ca, int keyUsage) throws Exception {
        Instant now = Instant.now();
        JcaX509v3CertificateBuilder b = new JcaX509v3CertificateBuilder(new X500Name(issuerDn), BigInteger.valueOf(serial++),
                Date.from(now.minusSeconds(60)), Date.from(now.plusSeconds(3_600)), new X500Name(ca ? issuerDn : "O=SPIFFE"), subjectKey);
        b.addExtension(Extension.basicConstraints, true, new BasicConstraints(ca));
        b.addExtension(Extension.keyUsage, true, new KeyUsage(keyUsage));
        if (!uris.isEmpty()) {
            GeneralName[] names = uris.stream().map(u -> new GeneralName(GeneralName.uniformResourceIdentifier, u)).toArray(GeneralName[]::new);
            b.addExtension(Extension.subjectAlternativeName, false, new GeneralNames(names));
        }
        if (!ca) {
            b.addExtension(Extension.extendedKeyUsage, false, new ExtendedKeyUsage(new KeyPurposeId[] {KeyPurposeId.id_kp_serverAuth, KeyPurposeId.id_kp_clientAuth}));
        }
        return new JcaX509CertificateConverter().getCertificate(b.build(new JcaContentSignerBuilder("SHA256withECDSA").build(issuer.getPrivate())));
    }

    /** SPIFFE-ID.md section 2: scheme, trust domain and path rules. Returns null when valid. */
    static String spiffeIdProblem(String id) {
        if (!id.startsWith("spiffe://")) {
            return "scheme must be spiffe";
        }
        String rest = id.substring("spiffe://".length());
        int slash = rest.indexOf('/');
        String td = slash < 0 ? rest : rest.substring(0, slash);
        String path = slash < 0 ? "" : rest.substring(slash);
        if (td.isEmpty() || !td.matches("[a-z0-9._-]+")) {
            return "trust domain must be non-empty [a-z0-9.-_] (lowercase, no port, userinfo or %-encoding)";
        }
        if (path.contains("%") || path.contains("?") || path.contains("#")) {
            return "no percent-encoding, query or fragment";
        }
        if (path.endsWith("/")) {
            return "no trailing /";
        }
        for (String seg : path.isEmpty() ? new String[0] : path.substring(1).split("/", -1)) {
            if (seg.isEmpty() || seg.equals(".") || seg.equals("..") || !seg.matches("[a-zA-Z0-9._-]+")) {
                return "bad path segment '" + seg + "'";
            }
        }
        return null;
    }

    static String trustDomain(String id) {
        String rest = id.substring("spiffe://".length());
        return rest.contains("/") ? rest.substring(0, rest.indexOf('/')) : rest;
    }

    /** X509-SVID.md section 5 + RFC 5280 path validation against the bundle of the ID's trust domain. */
    static String validateX509Svid(X509Certificate leaf, Map<String, X509Certificate> bundles) {
        try {
            Collection<List<?>> sans = leaf.getSubjectAlternativeNames();
            List<String> uris = new ArrayList<>();
            if (sans != null) {
                for (List<?> s : sans) {
                    if (((Integer) s.get(0)) == 6) {
                        uris.add((String) s.get(1));
                    }
                }
            }
            if (uris.size() != 1) {
                return "reject: " + uris.size() + " URI SANs (exactly one required)";
            }
            String id = uris.get(0);
            String p = spiffeIdProblem(id);
            if (p != null) {
                return "reject: SPIFFE ID " + p;
            }
            if (!id.substring("spiffe://".length()).contains("/")) {
                return "reject: leaf SPIFFE ID must have a non-root path";
            }
            if (leaf.getBasicConstraints() != -1) {
                return "reject: cA=true (a signing certificate is not an identity)";
            }
            boolean[] ku = leaf.getKeyUsage();
            if (ku == null || !ku[0] || ku[5] || ku[6]) {
                return "reject: key usage must have digitalSignature and no keyCertSign/cRLSign";
            }
            X509Certificate anchor = bundles.get(trustDomain(id));
            if (anchor == null) {
                return "reject: no bundle for trust domain " + trustDomain(id);
            }
            PKIXParameters params = new PKIXParameters(Set.of(new TrustAnchor(anchor, null)));
            params.setRevocationEnabled(false);
            CertPathValidator.getInstance("PKIX").validate(CertificateFactory.getInstance("X.509").generateCertPath(List.of(leaf)), params);
            return "accept " + id;
        } catch (Exception e) {
            return "reject: path validation (" + e.getClass().getSimpleName() + ")";
        }
    }

    /** JWT-SVID.md sections 2-3: allowed alg families, typ JWT/JOSE only, no other headers, sub, aud (must contain me), exp. */
    static String validateJwtSvid(String jwt, Jose.Jwk key, String me, long now) {
        Jose.Parts p = Jose.parse(jwt);
        Map<String, Object> h = p.header();
        String alg = String.valueOf(h.get("alg"));
        if (!alg.matches("(RS|ES|PS)(256|384|512)")) {
            return "reject: alg " + alg;
        }
        for (String k : h.keySet()) {
            if (!Set.of("alg", "kid", "typ").contains(k)) {
                return "reject: header " + k + " not permitted";
            }
        }
        if (h.containsKey("typ") && !Set.of("JWT", "JOSE").contains(h.get("typ"))) {
            return "reject: typ " + h.get("typ");
        }
        if (!Jose.rawVerify(alg, key, p.signingInput(), p.sig())) {
            return "reject: signature";
        }
        Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
        Object aud = c.get("aud");
        if (aud == null || !(aud instanceof List<?> l ? l.contains(me) : me.equals(aud))) {
            return "reject: aud " + aud;
        }
        if (!(c.get("exp") instanceof Number exp) || exp.longValue() < now) {
            return "reject: exp missing or past";
        }
        if (spiffeIdProblem(String.valueOf(c.get("sub"))) != null) {
            return "reject: sub is not a SPIFFE ID";
        }
        return "accept sub=" + c.get("sub");
    }

    static String jwt(Jose.Jwk k, String alg, Map<String, Object> extraHeader, Map<String, Object> claims) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", alg);
        h.put("kid", "jwt-svid-1");
        h.putAll(extraHeader);
        return Jose.sign(h, MiniJson.write(claims).getBytes(StandardCharsets.UTF_8), k);
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String x509 = KbSupport.text(fx, "X509-SVID.md");
        String sid = KbSupport.text(fx, "SPIFFE-ID.md");
        String jwtSpec = KbSupport.text(fx, "JWT-SVID.md");
        KbSupport.section("Rules (cited verbatim from the SPIFFE standards in fixtures/)");
        KbSupport.mustCite(x509, "An X.509 SVID MUST contain exactly one URI SAN", "X509-SVID 2");
        KbSupport.mustCite(x509, "Signing certificates MUST set the `cA` field to `true`, and leaf certificates MUST set the `cA` field to `false`.", "X509-SVID 4.1");
        KbSupport.mustCite(x509, "Leaf SVIDs MUST NOT set `keyCertSign` or `cRLSign`.", "X509-SVID 4.3");
        KbSupport.mustCite(sid, "The `host` part of the authority MUST be lowercase.", "SPIFFE-ID 2.1");
        KbSupport.mustCite(sid, "The path component MUST NOT include segments that are empty or are relative path modifiers", "SPIFFE-ID 2.2");
        KbSupport.mustCite(jwtSpec, "Validators MUST reject tokens without an `aud` claim set", "JWT-SVID 3.2");

        KbSupport.section("X.509-SVIDs presented to a prod workload (bundles: prod.bank.example, staging.bank.example)");
        KeyPair prodCa = ec();
        KeyPair stagingCa = ec();
        X509Certificate prodRoot = cert(prodCa.getPublic(), prodCa, "CN=prod.bank.example", List.of("spiffe://prod.bank.example"), true, KeyUsage.keyCertSign | KeyUsage.cRLSign);
        X509Certificate stagingRoot = cert(stagingCa.getPublic(), stagingCa, "CN=staging.bank.example", List.of("spiffe://staging.bank.example"), true,
                KeyUsage.keyCertSign | KeyUsage.cRLSign);
        Map<String, X509Certificate> bundles = Map.of("prod.bank.example", prodRoot, "staging.bank.example", stagingRoot);
        KeyPair w = ec();
        String good = "spiffe://prod.bank.example/ns/payments/sa/api";
        int leafDs = KeyUsage.digitalSignature;
        Object[][] x = {
            {"valid leaf from the prod CA", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of(good), false, leafDs), true},
            {"two URI SANs (payments + admin)", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of(good, "spiffe://prod.bank.example/ns/admin/sa/root"), false, leafDs), false},
            {"cA=true leaf (an intermediate used as identity)", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of(good), true, KeyUsage.keyCertSign | leafDs), false},
            {"keyCertSign set on a leaf", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of(good), false, leafDs | KeyUsage.keyCertSign), false},
            {"root SPIFFE ID (no path) on a leaf", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of("spiffe://prod.bank.example"), false, leafDs), false},
            {"uppercase trust domain", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of("spiffe://Prod.bank.example/ns/payments/sa/api"), false, leafDs), false},
            {"'..' path segment", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of("spiffe://prod.bank.example/ns/payments/../admin"), false, leafDs), false},
            {"percent-encoded path", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of("spiffe://prod.bank.example/ns/pay%6Dents/sa/api"), false, leafDs), false},
            {"trailing slash", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of(good + "/"), false, leafDs), false},
            {"prod ID, but signed by the staging CA", cert(w.getPublic(), stagingCa, "CN=staging.bank.example", List.of(good), false, leafDs), false},
            {"staging ID signed by the prod CA (cross-domain)", cert(w.getPublic(), prodCa, "CN=prod.bank.example", List.of("spiffe://staging.bank.example/ns/payments/sa/api"), false, leafDs), false}};
        int right = 0;
        for (Object[] c : x) {
            String r = validateX509Svid((X509Certificate) c[1], bundles);
            right += r.startsWith("accept") == (Boolean) c[2] ? 1 : 0;
            KbSupport.info("%-50s -> %s", c[0], r);
        }
        KbSupport.check("all 11 X.509 cases decided as the standard requires (1 accepted, 10 rejected)", right == 11);

        KbSupport.section("Authorization after authentication: which caller may POST /refunds?");
        String allowed = "spiffe://prod.bank.example/ns/payments/sa/api";
        String[] callers = {allowed, "spiffe://prod.bank.example/ns/payments-sandbox/sa/fuzzer", "spiffe://prod.bank.example/ns/payments/sa/api-canary"};
        int prefixWrong = 0;
        for (String caller : callers) {
            boolean prefix = caller.startsWith("spiffe://prod.bank.example/ns/payments");
            boolean exact = caller.equals(allowed);
            prefixWrong += prefix != exact ? 1 : 0;
            KbSupport.info("%-62s L5 startsWith(.../ns/payments) -> %-5s L7 exact allow-list -> %s", caller, prefix, exact);
        }
        KbSupport.check("prefix matching authorizes 2 workloads it should not; exact (or segment-aware) matching authorizes only the intended one", prefixWrong == 2);

        KbSupport.section("JWT-SVIDs presented to spiffe://prod.bank.example/ns/ledger/sa/api");
        Jose.Jwk k = Jose.generate("ES256", RNG);
        String ledger = "spiffe://prod.bank.example/ns/ledger/sa/api";
        long now = 1_767_225_600L;
        Map<String, Object> base = new LinkedHashMap<>(Map.of("sub", good, "aud", List.of(ledger), "exp", now + 300));
        Map<String, Object> noAud = new LinkedHashMap<>(Map.of("sub", good, "exp", now + 300));
        Map<String, Object> otherAud = new LinkedHashMap<>(Map.of("sub", good, "aud", List.of("spiffe://prod.bank.example/ns/hr/sa/api"), "exp", now + 300));
        Map<String, Object> noExp = new LinkedHashMap<>(Map.of("sub", good, "aud", List.of(ledger)));
        Object[][] j = {
            {"valid ES256, aud = ledger", jwt(k, "ES256", Map.of(), base), true},
            {"no aud", jwt(k, "ES256", Map.of(), noAud), false},
            {"aud = hr (replayed to ledger)", jwt(k, "ES256", Map.of(), otherAud), false},
            {"no exp", jwt(k, "ES256", Map.of(), noExp), false},
            {"typ at+jwt", jwt(k, "ES256", Map.of("typ", "at+jwt"), base), false},
            {"extra jku header", jwt(k, "ES256", Map.of("jku", "https://evil.example/jwks"), base), false}};
        int jr = 0;
        for (Object[] c : j) {
            String r = validateJwtSvid((String) c[1], k, ledger, now);
            jr += r.startsWith("accept") == (Boolean) c[2] ? 1 : 0;
            KbSupport.info("%-34s -> %s", c[0], r);
        }
        KbSupport.check("all 6 JWT-SVID cases decided as the standard requires", jr == 6);
        KbSupport.verdict();
    }
}
```

<!-- output:SpiffeSvidLab.java -->
```text

== Rules (cited verbatim from the SPIFFE standards in fixtures/)
  [PASS] constant cited verbatim from fixture: X509-SVID 2
  [PASS] constant cited verbatim from fixture: X509-SVID 4.1
  [PASS] constant cited verbatim from fixture: X509-SVID 4.3
  [PASS] constant cited verbatim from fixture: SPIFFE-ID 2.1
  [PASS] constant cited verbatim from fixture: SPIFFE-ID 2.2
  [PASS] constant cited verbatim from fixture: JWT-SVID 3.2

== X.509-SVIDs presented to a prod workload (bundles: prod.bank.example, staging.bank.example)
  valid leaf from the prod CA                        -> accept spiffe://prod.bank.example/ns/payments/sa/api
  two URI SANs (payments + admin)                    -> reject: 2 URI SANs (exactly one required)
  cA=true leaf (an intermediate used as identity)    -> reject: cA=true (a signing certificate is not an identity)
  keyCertSign set on a leaf                          -> reject: key usage must have digitalSignature and no keyCertSign/cRLSign
  root SPIFFE ID (no path) on a leaf                 -> reject: leaf SPIFFE ID must have a non-root path
  uppercase trust domain                             -> reject: SPIFFE ID trust domain must be non-empty [a-z0-9.-_] (lowercase, no port, userinfo or %-encoding)
  '..' path segment                                  -> reject: SPIFFE ID bad path segment '..'
  percent-encoded path                               -> reject: SPIFFE ID no percent-encoding, query or fragment
  trailing slash                                     -> reject: SPIFFE ID no trailing /
  prod ID, but signed by the staging CA              -> reject: path validation (CertPathValidatorException)
  staging ID signed by the prod CA (cross-domain)    -> reject: path validation (CertPathValidatorException)
  [PASS] all 11 X.509 cases decided as the standard requires (1 accepted, 10 rejected)

== Authorization after authentication: which caller may POST /refunds?
  spiffe://prod.bank.example/ns/payments/sa/api                  L5 startsWith(.../ns/payments) -> true  L7 exact allow-list -> true
  spiffe://prod.bank.example/ns/payments-sandbox/sa/fuzzer       L5 startsWith(.../ns/payments) -> true  L7 exact allow-list -> false
  spiffe://prod.bank.example/ns/payments/sa/api-canary           L5 startsWith(.../ns/payments) -> true  L7 exact allow-list -> false
  [PASS] prefix matching authorizes 2 workloads it should not; exact (or segment-aware) matching authorizes only the intended one

== JWT-SVIDs presented to spiffe://prod.bank.example/ns/ledger/sa/api
  valid ES256, aud = ledger          -> accept sub=spiffe://prod.bank.example/ns/payments/sa/api
  no aud                             -> reject: aud null
  aud = hr (replayed to ledger)      -> reject: aud [spiffe://prod.bank.example/ns/hr/sa/api]
  no exp                             -> reject: exp missing or past
  typ at+jwt                         -> reject: typ at+jwt
  extra jku header                   -> reject: header jku not permitted
  [PASS] all 6 JWT-SVID cases decided as the standard requires

verdict: OK (9 checks)
```

Reading the run:
- **Path validation must use the bundle of the SPIFFE ID's trust domain.** A prod-looking ID signed by the staging CA, or a staging ID signed by the prod CA, must fail. Federation (§5 of the bundle spec) is an explicit, per-trust-domain bundle exchange, not "trust everything we know".
- **Authentication ≠ authorization.** The perfect SVID check is followed by a `startsWith` in the policy. SPIFFE IDs are paths, so compare exactly, or by path segments, and never by string prefix [E].
- **JWT-SVIDs are bearer tokens.** Keep `aud` single-valued, keep lifetimes short (minutes), and prefer X.509-SVIDs (mTLS) whenever the connection is end-to-end.

---

## 6. Choosing the propagation pattern

| Pattern | What crosses the hop | Blast radius of one compromised service | Use when [E] |
|---|---|---|---|
| Relay the user's token | the user's broad token | everything the user can do, everywhere | never across trust boundaries; maybe inside one service's own components |
| Phantom token per audience (file 01) | gateway-minted, aud = first hop | first hop only | edge → first service |
| Token exchange per hop (RFC 8693) | aud = next hop, narrowed scope, `act` | the next hop, the narrowed scope, 60 s | multi-hop user-on-behalf-of calls |
| Workload identity only (SPIFFE mTLS) | no user token; the caller's SVID | the caller's own permissions | system-to-system jobs with no user context |
| SVID + exchanged token, bound | both, with current actor = mTLS peer ID | the next hop, only from the right workload | the L7 default for user-on-behalf-of in a mesh |

---

## 7. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 - DO NOT USE: relay the incoming token to every downstream call.
RestClient downstream = RestClient.builder()
    .requestInterceptor((req, body, exec) -> {
        req.getHeaders().setBearerAuth(currentUserToken());   // aud = everything, scope = everything
        return exec.execute(req, body);
    }).build();
// downstream services: oauth2ResourceServer(jwt()) with no audience check; authorize on scope only
```

```java
// L7 - each hop exchanges for the next audience, carrying the workload as actor; mTLS with SPIFFE between pods.
final class ExchangingInterceptor implements ClientHttpRequestInterceptor {
    private final TokenExchangeClient exchange;   // POST /oauth2/token grant_type=token-exchange (cached per subject x audience)
    private final String audience;                // fixed per RestClient: https://payments.internal
    private final Supplier<String> actorToken;    // the workload's own token (client credentials / JWT-SVID)

    @Override
    public ClientHttpResponse intercept(HttpRequest req, byte[] body, ClientHttpRequestExecution exec) throws IOException {
        String subject = ((AbstractOAuth2TokenAuthenticationToken<?>) SecurityContextHolder.getContext().getAuthentication())
            .getToken().getTokenValue();
        req.getHeaders().setBearerAuth(exchange.exchange(subject, actorToken.get(), audience, Set.of("payments:charge")));
        return exec.execute(req, body);
    }
}

// resource server: aud == me, current actor allow-listed, actor == mTLS peer SPIFFE ID, depth <= 3
@Bean
JwtDecoder jwtDecoder() {
    NimbusJwtDecoder d = NimbusJwtDecoder.withIssuerLocation("https://as.bank.example").jwsAlgorithm(SignatureAlgorithm.ES256).build();
    d.setJwtValidator(new DelegatingOAuth2TokenValidator<>(JwtValidators.createDefaultWithIssuer("https://as.bank.example"),
        new JwtClaimValidator<List<String>>("aud", aud -> aud != null && aud.equals(List.of("https://payments.internal"))),
        new CurrentActorValidator(Set.of("spiffe://prod.bank.example/ns/orders/sa/api"), 3)));  // your class: outermost act only
    return d;
}
```

```java
// L7 - authorization server: guard token exchange (L37) and set aud from the request.
http.oauth2AuthorizationServer(as -> as.tokenEndpoint(t -> t.authenticationProviders(ps -> ps.replaceAll(p ->
    p instanceof OAuth2TokenExchangeAuthenticationProvider
        ? new SasTokenExchangeLab.GuardedExchange(p, authorizationService, exchangePolicy) : p))));

@Bean
OAuth2TokenCustomizer<JwtEncodingContext> exchangeAudience() {
    return ctx -> {
        if (ctx.getAuthorizationGrant() instanceof OAuth2TokenExchangeAuthenticationToken t
                && t.getAudiences() != null && t.getAudiences().size() == 1) {
            ctx.getClaims().audience(List.copyOf(t.getAudiences()));
            ctx.getClaims().expiresAt(Instant.now().plusSeconds(60));
        }
    };
}
```

| Concern | L5 | L7 |
|---|---|---|
| What crosses a hop | the user's broad token | an exchanged token: aud = next hop, narrowed scope, `act`, 60 s |
| AS exchange checks | caller registered for the scope | subject issued to caller; scope ⊆ subject ∩ policy; one audience; actor required; depth bound |
| RS checks | signature + scope | `aud` = self; current actor allow-listed and equal to the mTLS SPIFFE ID; depth; scope |
| Workload authentication | network location, shared secrets | SPIFFE X.509-SVID mTLS (SPIRE attestation); JWT-SVID with single `aud` where mTLS ends |
| SPIFFE authorization | `startsWith` | exact IDs, or segment-aware patterns in policy |
| Trust domains | one bundle trusted for everything | the bundle of the ID's trust domain; explicit federation |

---

## 8. Real-world attack vectors & mitigations

### A1 · Lateral movement with a relayed user token

**Attack.** A compromised service replays the user's relayed token at an API it never needed, such as admin (L36 case 1).
**Wire signature.** Calls from a workload to an API outside its dependency graph, carrying user tokens.
**Root cause.** Broad `aud`; relay.
**Mitigation.** Exchange per hop with aud = next hop. RSs check `aud`. An AS policy of caller → audience.
**Detection.** Service-graph anomaly detection; `invalid_target` exchange errors.

### A2 · Scope escalation through token exchange

**Attack.** The exchanging service requests scopes the user never granted, and the AS checks only the caller's registration. Spring Authorization Server 7.1.2 does exactly that (L37 case b).
**Wire signature.** Exchanged tokens with scopes absent from the subject token.
**Root cause.** Scope validation against the client, not the subject.
**Mitigation.** Scope ⊆ subject scope ∩ policy (L37 `GuardedExchange`).
**Detection.** Audit exchanged-token scopes against subject-token scopes.

### A3 · Exchanging someone else's token

**Attack.** A service that logged or stole a user token for another client exchanges it for itself (L37 case d).
**Wire signature.** Exchange requests whose subject token's `aud`/`client_id` isn't the caller.
**Root cause.** No subject-audience check.
**Mitigation.** Subject `aud` ∋ caller, or an explicit trust relationship. Use sender-constrained subject tokens (Folder 04).
**Detection.** Mismatch counters at the AS.

### A4 · Actor-chain laundering

**Attack.** A token whose current actor is an unauthorized service carries an authorized service as a *prior* actor. A naive RS accepts if "payments is in the chain" (L36 case 4).
**Wire signature.** Tokens whose outermost `act.sub` isn't in the RS's allow-list.
**Root cause.** Authorizing on prior actors, against RFC 8693 §4.1.
**Mitigation.** Authorize on the current actor only, bind it to the mTLS peer SPIFFE ID, and limit depth.
**Detection.** Log the current actor vs the peer ID.

### A5 · SVID validation shortcuts

**Attack.** The attacker presents a certificate with two URI SANs, a CA certificate used as a leaf, a malformed ID (`..`, `%`, uppercase), or a cert from another trust domain's CA (L38).
**Wire signature.** TLS client certificates that fail the SVID profile.
**Root cause.** Generic X.509 validation without the SPIFFE profile, or one trust store for all domains.
**Mitigation.** Use the SPIFFE libraries (go-spiffe, java-spiffe) or L38's rules: one URI SAN, leaf profile, ID grammar, and the per-trust-domain bundle.
**Detection.** Rejected-handshake telemetry by reason.

### A6 · Prefix-matched workload authorization

**Attack.** The `…/ns/payments-sandbox/sa/fuzzer` workload passes `startsWith("…/ns/payments")` (L38).
**Wire signature.** Allowed calls from IDs not in the explicit allow-list.
**Root cause.** String-prefix policy on hierarchical IDs.
**Mitigation.** Exact IDs, or segment-aware matching (`/ns/payments/` + `sa/*`) in the policy engine (file 03).
**Detection.** Policy tests with near-miss IDs in CI.

### A7 · Long-lived JWT-SVIDs replayed across audiences

**Attack.** A JWT-SVID with several `aud` values, or hours of lifetime, is captured from logs and replayed to another service.
**Wire signature.** JWT-SVIDs with multi-valued `aud`; reuse from different peers.
**Root cause.** Treating JWT-SVIDs like long-lived API keys.
**Mitigation.** A single `aud` ("strongly recommended that the number of values be limited to one", JWT-SVID §3.2), minutes of lifetime, and X.509-SVID mTLS where possible.
**Detection.** JWT-SVID presentation from peers whose mTLS ID differs from `sub`.

---

## 9. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "We forward the user's JWT to every downstream service." Defend or redesign.</b></summary>

**Initial Prompt.** 40 microservices; Spring Cloud Gateway `TokenRelay`.

**L5 Textbook Answer.** "It's the standard pattern and every service knows the user."

**How an Attacker Bypasses L5.** One compromised service holds a token valid everywhere with all of the user's scopes. L36's compromised `orders` wins 6 of 6 attacks: lateral calls, skipping hops, escalation and more.

**L7 Principal Defense.**
- **Edge:** a phantom token for the first hop (file 01).
- **Further hops:** RFC 8693 exchange per hop, with aud = next hop, narrowed scope, `act` = caller and 60 s lifetime.
- **Resource servers:** `aud` = self, authorize on the current actor, bound to the mTLS SPIFFE ID.
- **Relay is acceptable only inside a single deployable unit.**

</details>

<details><summary><b>Q2 · Delegation or impersonation for service-to-service calls on behalf of a user?</b></summary>

**Initial Prompt.** A support tool must act as the customer.

**L5 Textbook Answer.** "Impersonation: downstream services don't need to change."

**How an Attacker Bypasses L5.** An impersonated token is indistinguishable from the customer's own (L36 case 6), so no RS can apply "support may read but not pay", and the audit log blames the customer.

**L7 Principal Defense.**
- **Delegation everywhere** (`act` present).
- **RS policies that consider the current actor,** for example deny payments when the actor is support-tool.
- **Impersonation only for break-glass:** allow-listed, `may_act`-gated, short-lived, and alerting.

</details>

<details><summary><b>Q3 · What must the AS check on a token-exchange request?</b></summary>

**Initial Prompt.** You're reviewing a Spring Authorization Server config.

**L5 Textbook Answer.** "That the client is allowed the token-exchange grant and the subject token is valid."

**How an Attacker Bypasses L5.** L37 on 7.1.2 shows the gaps: a scope the user never had, an ignored audience, a token not issued to the caller exchanged anyway, and silent impersonation.

**L7 Principal Defense.** The AS must check that:
- the caller is authenticated (mTLS/SVID or `private_key_jwt`);
- the subject token is active, from this AS (or a trusted federated issuer), and its `aud` includes the caller;
- `may_act` is honoured when present;
- an actor token is required for delegation;
- scope ⊆ subject ∩ policy(caller → audience);
- there is exactly one audience, which becomes `aud`;
- the lifetime is ≤ 60 s and the depth ≤ N.

On Spring, implement this with `GuardedExchange` plus an `aud` customizer.

</details>

<details><summary><b>Q4 · How does a service know who is calling it in a zero-trust mesh?</b></summary>

**Initial Prompt.** Kubernetes, Istio or Linkerd, or plain pods.

**L5 Textbook Answer.** "NetworkPolicy plus the `X-Service-Name` header."

**How an Attacker Bypasses L5.** Headers are forgeable by any process that reaches the pod, and NetworkPolicy is IP-based and coarse. A compromised pod in an allowed namespace is "the payments service".

**L7 Principal Defense.**
- **SPIFFE X.509-SVIDs** issued by SPIRE after workload attestation (service account, pod UID), rotated hourly or less, with mTLS on every hop.
- **Validation per the SVID profile** (L38).
- **Authorization on exact SPIFFE IDs** in a policy engine (file 03).
- **Where mTLS terminates at L7 proxies,** a JWT-SVID with a single `aud`.

</details>

<details><summary><b>Q5 · Your policy says `startsWith("spiffe://prod.bank.example/ns/payments")`. Problem?</b></summary>

**Initial Prompt.** Code review of a mesh authorization policy.

**L5 Textbook Answer.** "It allows all payments workloads, as intended."

**How an Attacker Bypasses L5.** It also allows `…/ns/payments-sandbox/…` and `…/sa/api-canary` (L38). An attacker who can deploy to a namespace whose name *starts with* "payments" passes.

**L7 Principal Defense.**
- **Exact IDs,** or segment-aware patterns (`ns == "payments" && sa in {...}`) in the PDP.
- **Namespaces as a security boundary:** admission control on namespace creation.
- **Near-miss test cases** in CI.

</details>

<details><summary><b>Q6 · Two trust domains (prod, partner) must talk. How do you federate SPIFFE safely?</b></summary>

**Initial Prompt.** A B2B integration over mTLS.

**L5 Textbook Answer.** "Add the partner's CA to our trust store."

**How an Attacker Bypasses L5.** A single trust store trusts the partner CA for *any* SPIFFE ID, including `spiffe://prod.bank.example/...`. The partner (or its compromise) can mint your identities (L38: cross-domain case).

**L7 Principal Defense.**
- **Per-trust-domain bundles:** validate the chain against the bundle for *the ID's* trust domain only.
- **Bundle exchange** via the SPIFFE bundle endpoint, with rotation.
- **Name constraints** on intermediates where possible.
- **Policy** that names partner IDs explicitly.

</details>

<details><summary><b>Q7 · Why bind the token's actor to the mTLS identity?</b></summary>

**Initial Prompt.** "We have both mTLS and tokens; isn't that enough?"

**L5 Textbook Answer.** "Two layers are better than one."

**How an Attacker Bypasses L5.** If they're not bound, a stolen exchanged token (`act` = orders) replays from *any* authenticated workload, and the two layers are independent bypasses.

**L7 Principal Defense.**
- **Require `act.sub` (current actor) == the peer SPIFFE ID** on the connection, or bind the exchanged token to the workload's certificate (`cnf.x5t#S256`, RFC 8705, Folder 04).
- **Keep exchanged tokens ≤ 60 s.**

</details>

<details><summary><b>Q8 · Token exchange adds an AS round trip per hop. How do you keep latency acceptable?</b></summary>

**Initial Prompt.** p99 budget of 50 ms end to end.

**L5 Textbook Answer.** "Skip exchange internally."

**How an Attacker Bypasses L5.** Skipping exchange means relay, with the A1–A4 blast radius.

**L7 Principal Defense.**
- **Cache exchanged tokens** per (subject `jti`, audience, scope) until 60 s or the subject's `exp`.
- **Co-locate the token service** (a sidecar or node-local STS) as a regional, horizontally scaled read path.
- **Pre-exchange at the edge** for known fan-out.
- **For no-user system calls,** use SVIDs only.

Measure: a cached exchange is one hash lookup.

</details>

<details><summary><b>Q9 · How deep can a delegation chain go, and why limit it?</b></summary>

**Initial Prompt.** An event-driven saga with 6 services.

**L5 Textbook Answer.** "No limit; `act` nests."

**How an Attacker Bypasses L5.** Loops and long chains launder authority. Each hop may add or reinterpret context, and loops (payments → orders → payments) make the token grow without bound (L36 case 5).

**L7 Principal Defense.**
- **A depth limit** (3 in L36) at the AS and the RS.
- **Policy keyed on the current actor only.**
- **For sagas,** carry the *original* user authorization as a signed, immutable command or RAR object, not ever-deeper delegation.
- **Audit the chain,** which is informational per RFC 8693.

</details>

<details><summary><b>Q10 · A partner service presents a JWT-SVID with `aud` = [our-api, their-other-api] and a 24 h lifetime. Accept?</b></summary>

**Initial Prompt.** Integration test passes.

**L5 Textbook Answer.** "Yes: our API is in `aud`, and the signature is valid."

**How an Attacker Bypasses L5.** Any service in that `aud` list can replay it to us, for 24 hours. JWT-SVIDs are bearer tokens.

**L7 Principal Defense.**
- **Require a single `aud`** (JWT-SVID §3.2's strong recommendation) and **a lifetime of minutes.**
- **Prefer X.509-SVID mTLS.**
- **If JWT-SVIDs are required,** check that the peer's mTLS identity equals `sub` where available.
- **Monitor `aud` cardinality.**

</details>

---

## 10. Invariants checklist

- [ ] No user-token relay across services; phantom token at the edge (file 01) and RFC 8693 exchange per further hop.
- [ ] Exchange policy at the AS: caller authenticated; subject `aud` ∋ caller; scope ⊆ subject ∩ policy; one audience → `aud`; actor required; depth ≤ N; ≤ 60 s.
- [ ] On Spring Authorization Server 7.1.2: `GuardedExchange` decorator + `aud` customizer (L37), until upstream provides these checks.
- [ ] RS: `aud` == self; authorize on top-level claims + current actor only; actor == mTLS peer SPIFFE ID; depth check.
- [ ] Workloads authenticate with SPIFFE X.509-SVIDs (SPIRE attestation, short TTL); validation per the SVID profile; per-trust-domain bundles; explicit federation.
- [ ] SPIFFE authorization uses exact IDs or segment-aware patterns, never string prefixes.
- [ ] JWT-SVIDs: single `aud`, minutes of lifetime, `exp` required, no extra JOSE headers.

---

## 11. References

- RFC 8693 *OAuth 2.0 Token Exchange* — <https://www.rfc-editor.org/rfc/rfc8693>
- RFC 8707 *Resource Indicators for OAuth 2.0* — <https://www.rfc-editor.org/rfc/rfc8707>
- SPIFFE standards (SPIFFE ID, X.509-SVID, JWT-SVID, Trust Domain and Bundle) — <https://github.com/spiffe/spiffe/tree/main/standards>
- SPIRE documentation — <https://spiffe.io/docs/latest/spire-about/>
- Spring Authorization Server reference (token exchange grant, `OAuth2TokenExchangeAuthenticationProvider`) — <https://docs.spring.io/spring-authorization-server/reference/>
- NIST SP 800-207 *Zero Trust Architecture* — <https://csrc.nist.gov/pubs/sp/800/207/final>
