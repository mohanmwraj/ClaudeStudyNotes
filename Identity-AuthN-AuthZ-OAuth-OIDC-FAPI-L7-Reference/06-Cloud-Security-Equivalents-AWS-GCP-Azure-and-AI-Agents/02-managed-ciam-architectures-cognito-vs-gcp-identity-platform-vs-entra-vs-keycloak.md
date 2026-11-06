# Managed CIAM Architectures: Amazon Cognito vs GCP Identity Platform vs Microsoft Entra vs Keycloak

> Folder 06 · File 02 of 03 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [01 · Cloud IAM internals](01-cloud-iam-internals-aws-sts-irsa-pod-identity-vs-gcp-workload-identity-federation.md) · Next: [03 · Securing AI agents and MCP servers](03-securing-ai-agents-and-mcp-servers-oauth21-dynamic-client-registration-and-obo.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L44 `CiamTokenLab.java` | Four platforms with four token conventions, using real ES256-signed tokens. A **generic** API validator (signature + issuer prefix + expiry) accepts **all 7** wrong tokens:<br>• a Cognito **ID token** used as an API token;<br>• a Cognito token from **another app client**;<br>• an Entra token for **Microsoft Graph**;<br>• an Entra token from **another tenant**;<br>• a Firebase token from the **attacker's own project**;<br>• a Keycloak token for **another client**;<br>• a Keycloak **ID token**.<br><br>Provider-aware validation (Cognito `token_use`/`client_id`; Entra `tid` allow-list + `iss` bound to `tid` + `aud` + `scp`; Firebase exact `iss`/`aud` = project; Keycloak `aud` via audience mapper + `azp` + `typ`) rejects all 7 and accepts the 4 legitimate tokens | provider token documentation [D] |

**Verification.** Compiled with Folders 01–06 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs the output and requires it byte-identical. Token claim conventions follow each provider's documentation (§9), and no live tenant is used. Platform features change quickly: the comparison tables reflect public documentation as of November 2026. Check the provider docs before committing to a design.

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

CIAM (customer identity) is where you buy most of your OAuth/OIDC stack: sign-up, login, MFA and passkeys, social and enterprise federation, account recovery, tokens. Every platform is a standards-compliant OpenID Provider, and every one has **its own conventions** for the claims your APIs must check. Most CIAM vulnerabilities are not in the provider. They are in an API that validates a token "generically" and misses the convention that distinguishes *your* client, *your* tenant, *your* project, or an *access* token from an *ID* token.

Results:
- **[M] Generic validation fails on every platform (L44).** Signature + issuer + expiry accepts the 7 tokens listed above.
- **[D] The conventions to check:**
  - **Cognito:** access tokens carry `token_use: access` and `client_id` but **no `aud`**. ID tokens carry `token_use: id` and `aud` = the app client id.
  - **Entra ID v2:** `aud` = your API's application ID URI (or client id), `iss` = `https://login.microsoftonline.com/{tid}/v2.0`, `tid` allow-listed for multi-tenant apps, `scp` (delegated) or `roles` (application).
  - **Firebase / GCP Identity Platform:** ID tokens with `iss` = `https://securetoken.google.com/<project>` and `aud` = `<project>`. Any Firebase project's tokens are signed by the same Google keys, so the project check is the security boundary.
  - **Keycloak:** `iss` = the realm URL, `azp` = the client. `aud` contains your API only if an **audience mapper** or client scope adds it, and the `typ` claim distinguishes `Bearer` from `ID`.
- **[E] Two platform pitfalls cause outsized damage:**
  - **user-writable attributes used for authorization**, for example a Cognito custom attribute the user can change through `UpdateUserAttributes`;
  - **unintended self-service sign-up** into a pool or realm meant to be internal.

---

## 1. First principles: what a CIAM platform owns and what you still own

```text
   Platform owns (managed)                                   You still own
   -------------------------                                 ---------------------------------------------
   sign-up / sign-in UI, password + passkeys + MFA           token validation conventions at EVERY API (L44)
   social + SAML/OIDC enterprise federation                  which attributes are trusted for authorization
   token issuance (ID / access / refresh), JWKS rotation      tenant isolation model (pool / tenant / realm per customer?)
   account recovery, lockout, bot / abuse protection          customization code (triggers, blocking functions, SPIs)
   compliance attestations, availability                      session + logout semantics in your apps (Folder 03)
                                                             sender-constraining, FAPI needs (Folder 04)
```

| Dimension | Amazon Cognito | GCP Identity Platform | Microsoft Entra (External ID) | Keycloak |
|---|---|---|---|---|
| Model | user pools (+ identity pools for AWS credentials) | Firebase Authentication + enterprise features | Entra tenant for customers (External ID) | self-hosted realms, clients, client scopes |
| Protocols | OIDC, OAuth 2.0, SAML/OIDC IdP federation | OIDC/SAML providers, Firebase SDK tokens | OIDC, OAuth 2.0, SAML, WS-Fed | OIDC, OAuth 2.0, SAML; token exchange; device flow |
| API token for your backend | access token (`token_use`, `client_id`, scopes) | Firebase ID token (project `aud`) | access token for your API (`aud`, `scp`/`roles`) | access token (`aud` via mappers, `azp`, roles) |
| Multi-tenancy | pool per tenant, or groups/attributes | built-in tenants | tenant per customer, or org-level | realm per tenant, or Organizations |
| Customization | Lambda triggers (pre sign-up, pre token generation, …) | blocking functions (before create / before sign-in) | custom authentication extensions, user flows | SPIs, authentication flows, protocol mappers |
| Operations | fully managed | fully managed | fully managed | you run it (HA, upgrades, DB, CVEs) |

[D] for the model and hook names; see the provider docs in §9. Feature details such as passkeys, tiers and limits change often [E].

---

## 2. Token conventions, platform by platform

```json
{"sub": "aaaa-bbbb", "iss": "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_EXAMPLE", "client_id": "web-bff-client",
 "token_use": "access", "scope": "payments/read", "auth_time": 1767225500, "exp": 1767229100, "iat": 1767225500, "jti": "x", "username": "alice"}
```

That is a Cognito **access token**: no `aud`, so the API must check `token_use` and `client_id` [D: Cognito "Verifying a JSON web token"].

```json
{"aud": "api://payments-api", "iss": "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/v2.0",
 "tid": "11111111-2222-3333-4444-555555555555", "azp": "web-bff-client-id", "scp": "payments.read", "ver": "2.0", "exp": 1767229100}
```

That is an Entra v2 **access token for your API**. For multi-tenant apps, allow-list `tid` and check that `iss` contains that `tid`. Never accept every issuer the `common` metadata template could produce [D: Microsoft identity platform access tokens; Folder 03 file 01's nOAuth discussion].

Where each platform carries the three signals an API must check:

```text
  platform      "this is an ACCESS token"        "for MY client / API"                 "from MY tenant / project"
  -----------   ------------------------------   -----------------------------------   ---------------------------------------
  Cognito       token_use = "access"             client_id ∈ allow-list (no aud!)       iss = .../<region>_<poolId> (exact)
  Entra v2      ver "2.0", scp or roles present  aud = api://payments-api              tid ∈ allow-list AND iss contains tid
  Firebase/GIP  (ID token used as API token)     aud = <project id>                     iss = securetoken.google.com/<project>
  Keycloak      typ = "Bearer" (not "ID")        aud ∋ payments-api (audience mapper)   iss = https://kc/realms/<realm>
                                                 azp ∈ allow-list
  generic L5    -- not checked --                -- not checked --                      iss prefix only   -> L44: 7 of 7 accepted
```

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant C as Client (BFF)
    participant P as CIAM platform
    participant A as Your API
    U->>C: sign in
    C->>P: authorization code + PKCE
    P-->>C: ID token (for the client) + access token (for the API) + refresh token
    C->>A: Authorization: Bearer <ACCESS token>
    A->>A: signature (platform JWKS) + platform-specific checks: token type, audience/client, tenant/project, scopes
    A-->>C: 200
    Note over A: an ID token here is a bug; so is a token minted for another client, tenant or project (L44)
```

---

## 3. L44: generic vs provider-aware validation

<!-- listing:CiamTokenLab.java -->
```java
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.BiFunction;

/**
 * L44 - four managed identity platforms, four token conventions. A generic API validator (signature from the
 * provider's JWKS + issuer prefix + expiry) against provider-aware validators that check what each platform
 * documents as the audience and token-type signals: Amazon Cognito (token_use, client_id; access tokens carry no
 * aud), Microsoft Entra ID v2 (aud = the API, iss bound to tid, tenant allow-list, scp), Firebase / GCP Identity
 * Platform (aud = project id, iss = securetoken.google.com/project), Keycloak (azp, aud via an audience mapper).
 */
public final class CiamTokenLab {
    static final long NOW = 1_767_225_600L;

    record Provider(String name, String issuerPrefix, Jose.Jwk key, BiFunction<Map<String, Object>, String, String> l7) {
    }

    record Case(String provider, String label, Map<String, Object> claims, boolean attack) {
    }

    static Map<String, Object> m(Object... kv) {
        Map<String, Object> x = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) {
            x.put((String) kv[i], kv[i + 1]);
        }
        x.putIfAbsent("exp", NOW + 600);
        return x;
    }

    static String jwt(Jose.Jwk k, Map<String, Object> c) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", "ES256");
        h.put("kid", "k1");
        return Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), k);
    }

    public static void main(String[] args) throws Exception {
        SecureRandom rng = new SecureRandom();
        String cognitoIss = "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_EXAMPLE";
        String acmeTid = "11111111-2222-3333-4444-555555555555";
        String evilTid = "99999999-8888-7777-6666-555555555555";
        List<Provider> providers = List.of(
            new Provider("Cognito", "https://cognito-idp.", Jose.generate("ES256", rng), (c, s) ->
                !cognitoIss.equals(c.get("iss")) ? "iss" : !"access".equals(c.get("token_use")) ? "token_use " + c.get("token_use")
                    : !Set.of("web-bff-client").contains(c.get("client_id")) ? "client_id " + c.get("client_id") : null),
            new Provider("Entra", "https://login.microsoftonline.com/", Jose.generate("ES256", rng), (c, s) ->
                !Set.of(acmeTid).contains(c.get("tid")) ? "tenant " + c.get("tid")
                    : !("https://login.microsoftonline.com/" + c.get("tid") + "/v2.0").equals(c.get("iss")) ? "iss not bound to tid"
                    : !"api://payments-api".equals(c.get("aud")) ? "aud " + c.get("aud")
                    : !String.valueOf(c.get("scp")).contains("payments.read") ? "scp" : null),
            new Provider("Firebase", "https://securetoken.google.com/", Jose.generate("ES256", rng), (c, s) ->
                !"https://securetoken.google.com/acme-prod".equals(c.get("iss")) ? "iss " + c.get("iss")
                    : !"acme-prod".equals(c.get("aud")) ? "aud " + c.get("aud") : null),
            new Provider("Keycloak", "https://kc.acme.example/realms/", Jose.generate("ES256", rng), (c, s) ->
                !"https://kc.acme.example/realms/acme".equals(c.get("iss")) ? "iss"
                    : !(c.get("aud") instanceof List<?> l && l.contains("payments-api")) ? "aud " + c.get("aud")
                    : !Set.of("web-bff").contains(c.get("azp")) ? "azp " + c.get("azp")
                    : !"Bearer".equals(c.get("typ")) ? "typ " + c.get("typ") : null));

        List<Case> cases = List.of(
            new Case("Cognito", "access token from the BFF's app client", m("iss", cognitoIss, "sub", "u-1", "token_use", "access", "client_id", "web-bff-client", "scope", "payments/read"), false),
            new Case("Cognito", "ID token presented as an API token", m("iss", cognitoIss, "sub", "u-1", "token_use", "id", "aud", "web-bff-client"), true),
            new Case("Cognito", "access token from another app client in the pool", m("iss", cognitoIss, "sub", "u-1", "token_use", "access", "client_id", "marketing-app", "scope", "payments/read"), true),
            new Case("Entra", "v2 token for api://payments-api in the acme tenant", m("iss", "https://login.microsoftonline.com/" + acmeTid + "/v2.0", "tid", acmeTid, "aud", "api://payments-api", "scp", "payments.read", "ver", "2.0"), false),
            new Case("Entra", "token issued for Microsoft Graph", m("iss", "https://login.microsoftonline.com/" + acmeTid + "/v2.0", "tid", acmeTid, "aud", "https://graph.microsoft.com", "scp", "User.Read", "ver", "2.0"), true),
            new Case("Entra", "multi-tenant app: token from ANOTHER tenant", m("iss", "https://login.microsoftonline.com/" + evilTid + "/v2.0", "tid", evilTid, "aud", "api://payments-api", "scp", "payments.read", "ver", "2.0"), true),
            new Case("Firebase", "ID token for project acme-prod", m("iss", "https://securetoken.google.com/acme-prod", "aud", "acme-prod", "sub", "uid-7", "auth_time", NOW - 60), false),
            new Case("Firebase", "ID token from the attacker's own Firebase project", m("iss", "https://securetoken.google.com/attacker-proj", "aud", "attacker-proj", "sub", "uid-7", "auth_time", NOW - 60), true),
            new Case("Keycloak", "access token for web-bff with payments-api audience", m("iss", "https://kc.acme.example/realms/acme", "azp", "web-bff", "aud", List.of("payments-api", "account"), "typ", "Bearer"), false),
            new Case("Keycloak", "token issued to another client (aud only 'account')", m("iss", "https://kc.acme.example/realms/acme", "azp", "admin-cli", "aud", List.of("account"), "typ", "Bearer"), true),
            new Case("Keycloak", "Keycloak ID token (typ ID) at the API", m("iss", "https://kc.acme.example/realms/acme", "azp", "web-bff", "aud", List.of("payments-api"), "typ", "ID"), true));

        KbSupport.section("Generic validator (signature + issuer prefix + exp) vs provider-aware validation");
        int l5 = 0;
        int l7 = 0;
        boolean legit = true;
        for (Case cs : cases) {
            Provider pr = providers.stream().filter(p -> p.name().equals(cs.provider())).findFirst().orElseThrow();
            // the attacker's Firebase project signs with Google's keys too: same key here, different project
            String token = jwt(pr.key(), cs.claims());
            Jose.Parts p = Jose.parse(token);
            Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
            boolean sig = Jose.rawVerify("ES256", pr.key(), p.signingInput(), p.sig());
            boolean generic = sig && String.valueOf(c.get("iss")).startsWith(pr.issuerPrefix()) && ((Number) c.get("exp")).longValue() > NOW;
            String why = sig ? pr.l7().apply(c, "payments-api") : "signature";
            boolean aware = why == null;
            if (cs.attack()) {
                l5 += generic ? 1 : 0;
                l7 += aware ? 1 : 0;
            } else {
                legit &= generic && aware;
            }
            KbSupport.info("%-9s %-52s generic -> %-7s provider-aware -> %s", cs.provider(), cs.label(), generic ? "ACCEPT" : "reject", aware ? "ACCEPT" : "reject (" + why + ")");
        }
        KbSupport.check("the generic validator accepts all 7 cross-client, cross-tenant, cross-project and wrong-type tokens", l5 == 7);
        KbSupport.check("provider-aware validation rejects all 7 and accepts the 4 legitimate tokens", l7 == 0 && legit);
        KbSupport.verdict();
    }
}
```

<!-- output:CiamTokenLab.java -->
```text

== Generic validator (signature + issuer prefix + exp) vs provider-aware validation
  Cognito   access token from the BFF's app client               generic -> ACCEPT  provider-aware -> ACCEPT
  Cognito   ID token presented as an API token                   generic -> ACCEPT  provider-aware -> reject (token_use id)
  Cognito   access token from another app client in the pool     generic -> ACCEPT  provider-aware -> reject (client_id marketing-app)
  Entra     v2 token for api://payments-api in the acme tenant   generic -> ACCEPT  provider-aware -> ACCEPT
  Entra     token issued for Microsoft Graph                     generic -> ACCEPT  provider-aware -> reject (aud https://graph.microsoft.com)
  Entra     multi-tenant app: token from ANOTHER tenant          generic -> ACCEPT  provider-aware -> reject (tenant 99999999-8888-7777-6666-555555555555)
  Firebase  ID token for project acme-prod                       generic -> ACCEPT  provider-aware -> ACCEPT
  Firebase  ID token from the attacker's own Firebase project    generic -> ACCEPT  provider-aware -> reject (iss https://securetoken.google.com/attacker-proj)
  Keycloak  access token for web-bff with payments-api audience  generic -> ACCEPT  provider-aware -> ACCEPT
  Keycloak  token issued to another client (aud only 'account')  generic -> ACCEPT  provider-aware -> reject (aud [account])
  Keycloak  Keycloak ID token (typ ID) at the API                generic -> ACCEPT  provider-aware -> reject (typ ID)
  [PASS] the generic validator accepts all 7 cross-client, cross-tenant, cross-project and wrong-type tokens
  [PASS] provider-aware validation rejects all 7 and accepts the 4 legitimate tokens

verdict: OK (2 checks)
```

Reading the run:
- **Firebase is the starkest case.** Every Firebase project's ID tokens are signed by the same Google service keys. An attacker creates a free project, signs in, and gets a validly signed token. Only the exact `iss` and `aud` (your project id) separate it from yours [D: Firebase "Verify ID tokens"].
- **Keycloak's default `aud`** often doesn't include your API. Teams then drop the audience check instead of adding an audience mapper, and every client's tokens work at every API.
- **Libraries help but need the right settings.** Use AWS's `aws-jwt-verify` (with `tokenUse` and `clientId`), Microsoft.Identity.Web or Spring with an explicit `aud`, Firebase Admin `verifyIdToken`, or Spring with `issuer-uri` + `audiences` [E].

---

## 4. Platform-specific pitfalls

| Pitfall | Platform | Why it bites [D/E] |
|---|---|---|
| Custom attributes writable by the user, used for authorization (`custom:role`, `custom:tenant`) | Cognito (also any CIAM with self-service profile edits) | users can update writable attributes with their own access token; make authorization attributes read-only for app clients, or keep them out of the CIAM |
| Self-service sign-up left enabled on an "internal" pool or realm | Cognito, Keycloak | anyone can create an account and obtain valid tokens for your audience |
| Accepting ID tokens at APIs | all | ID tokens are for the client (OIDC Core). APIs need access tokens with an audience |
| Multi-tenant issuer acceptance | Entra | `common`/`organizations` metadata issuer templates; validate `tid` + `iss` |
| Shared signing keys across projects | Firebase/GCP Identity Platform | the project id in `aud`/`iss` is the only boundary |
| Missing audience mapper | Keycloak | `aud` lacks the API, so teams skip the check |
| Customization code as a trust boundary | all (triggers, blocking functions, SPIs) | injection or logic bugs in pre-token hooks mint privileged claims; review and test them like auth code |
| Account recovery weaker than login | all | passkeys at login but email-OTP recovery means the attacker uses recovery (Folder 01 file 02) |

---

## 5. Choosing a platform

| If you need… | Lean toward [E] |
|---|---|
| deep AWS integration (identity pools → AWS credentials, API Gateway authorizers) | Cognito |
| Firebase SDKs, mobile-first, built-in tenants | GCP Identity Platform |
| Microsoft ecosystem, B2B + B2C under one directory, Conditional Access | Entra External ID |
| full control, on-prem or regulated hosting, protocol breadth (token exchange, FAPI), no per-MAU pricing | Keycloak, self-run or a managed Keycloak vendor |
| FAPI 2.0 (PAR, DPoP, `private_key_jwt`) | verify support per platform; Keycloak has FAPI client policies; managed CIAMs vary |

---

## 6. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 - DO NOT USE: one generic decoder for every CIAM, trusting any token that verifies.
@Bean
JwtDecoder decoder() {
    return NimbusJwtDecoder.withJwkSetUri(jwksUri).build();      // RS256 default; no iss, aud, token_use, tid, azp checks
}
// authorization: if (jwt.getClaimAsString("custom:role").equals("admin"))  // user-writable attribute
```

```java
// L7 - provider-aware validation (Cognito access tokens shown; Entra, Firebase and Keycloak analogues in L44).
@Bean
JwtDecoder cognitoAccessTokens() {
    NimbusJwtDecoder d = NimbusJwtDecoder.withIssuerLocation(COGNITO_ISSUER).build();   // exact issuer, its JWKS
    d.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
        JwtValidators.createDefaultWithIssuer(COGNITO_ISSUER),
        new JwtClaimValidator<String>("token_use", "access"::equals),                    // never ID tokens
        new JwtClaimValidator<String>("client_id", Set.of("web-bff-client")::contains)));  // Cognito access tokens carry no aud
    return d;
}
// authorization: roles from cognito:groups (admin-managed) or your own PDP - never from user-writable attributes
```

```yaml
# L7 - Keycloak resource server (Spring Boot): exact realm issuer and an audience the realm actually emits
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://kc.acme.example/realms/acme
          audiences: payments-api
          jws-algorithms: ES256
```

Add an **audience mapper** on the Keycloak client scope so access tokens carry `payments-api`, a validator that requires `azp` in the allow-list, and `typ` = `Bearer`.

| Concern | L5 | L7 |
|---|---|---|
| Token type | anything that verifies | access tokens only (`token_use`, `typ`) |
| Audience/client | unchecked | Cognito `client_id`; Entra `aud`; Firebase `aud` = project; Keycloak `aud` + `azp` |
| Tenant/project | issuer prefix | exact `iss`; Entra `tid` allow-list; Firebase project id |
| Authorization attributes | user-writable profile fields | admin-managed groups/roles or your PDP |
| Sign-up | defaults | explicitly enabled or disabled per pool/realm; bot protection |
| Customization hooks | untested code | reviewed, tested, least-privilege, monitored |

---

## 7. Real-world attack vectors & mitigations

### A1 · ID tokens accepted as API tokens

**Attack.** The SPA sends the ID token to the API, and a later attacker reuses any ID token, which are often logged and long-lived (L44 Cognito and Keycloak cases).
**Wire signature.** API requests carrying `token_use: id` or `typ: ID`.
**Root cause.** A generic validator.
**Mitigation.** Check the token type; access tokens only, with audience or client checks.
**Detection.** Count rejected token types at APIs.

### A2 · Cross-client tokens from a shared pool or realm

**Attack.** A token issued to another app in the same Cognito pool or Keycloak realm (marketing app, admin-cli) is accepted by your API.
**Wire signature.** `client_id`/`azp` values outside the allow-list.
**Root cause.** Issuer-only validation.
**Mitigation.** Allow-list `client_id`/`azp`, use audience mappers, and separate pools or realms for very different trust levels.
**Detection.** Metrics by client id.

### A3 · Multi-tenant issuer confusion (Entra)

**Attack.** An app accepts any `https://login.microsoftonline.com/{tid}/v2.0` issuer, so an attacker's tenant mints valid tokens (L44).
**Wire signature.** Unknown `tid` values.
**Root cause.** Issuer validation by pattern.
**Mitigation.** A `tid` allow-list, `iss` bound to `tid`, and an `aud` check.
**Detection.** Alerts on new tenants.

### A4 · Cross-project Firebase tokens

**Attack.** The attacker creates a Firebase project and presents its ID tokens. They are signed by the same Google keys (L44).
**Wire signature.** `aud`/`iss` with an unexpected project id.
**Root cause.** Signature-only validation.
**Mitigation.** Exact `iss` and `aud` = your project (Firebase Admin `verifyIdToken` does this).
**Detection.** Rejected-project counters.

### A5 · User-writable attributes used for authorization

**Attack.** A user updates their own `custom:role` or `custom:tenantId` through the platform's self-service attribute API, and the API trusts the claim.
**Wire signature.** Attribute-update calls followed by privileged requests.
**Root cause.** Profile data treated as authorization data.
**Mitigation.** Make authorization attributes read-only for app clients, or keep authorization in groups set by admins or in a PDP (Folder 05 file 03).
**Detection.** Audit attribute changes on authorization-relevant fields.

### A6 · Unintended self-service sign-up

**Attack.** The attacker signs up directly against the pool or realm's sign-up endpoint (not exposed in your UI), obtains valid tokens, and reaches APIs that assume "only employees have accounts".
**Wire signature.** Sign-ups bypassing your onboarding flow.
**Root cause.** Default sign-up settings.
**Mitigation.** Disable self-registration where it's not intended (admin-create-only), gate sign-up with invitations or domain checks, and use authorization that never assumes "has an account = trusted".
**Detection.** Sign-up events without matching invitations.

### A7 · Customization hooks minting privileged claims

**Attack.** A pre-token-generation hook copies a user-controlled field into `groups` or `roles`, or a blocking function trusts a header.
**Wire signature.** Privileged claims on users without admin-assigned roles.
**Root cause.** Hooks treated as glue code.
**Mitigation.** Code review, tests, input allow-lists and least-privilege execution roles for hooks; claims only from trusted sources.
**Detection.** Diff issued claims against the directory.

---

## 8. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · Your API accepts Cognito tokens. What exactly do you validate?</b></summary>

**Initial Prompt.** A Spring Boot API behind API Gateway.

**L5 Textbook Answer.** "Signature against the pool's JWKS, issuer and expiry."

**How an Attacker Bypasses L5.** That accepts ID tokens and tokens from every app client in the pool (L44).

**L7 Principal Defense.**
- **Check:** the exact issuer, `token_use == "access"`, `client_id` ∈ the allow-list, and the required scopes.
- **Then authorize** with admin-managed groups or a PDP, not writable attributes.
- **Use `aws-jwt-verify` or an equivalent Spring validator chain.**

</details>

<details><summary><b>Q2 · Multi-tenant SaaS on Entra: how do you validate tokens?</b></summary>

**Initial Prompt.** Customers sign in with their own Entra tenants.

**L5 Textbook Answer.** "Use the `common` endpoint and accept any Microsoft-issued token."

**How an Attacker Bypasses L5.** Any tenant, including one the attacker creates for free, can mint tokens (L44 cross-tenant case).

**L7 Principal Defense.**
- **Allow-list onboarded tenant ids,** and check `iss` == the tid-specific issuer.
- **`aud`** = your API.
- **`scp`/`roles`** for authorization.
- **Map `tid` to your internal tenant,** and enforce tenant isolation downstream.

</details>

<details><summary><b>Q3 · Why are Firebase ID tokens dangerous to validate generically?</b></summary>

**Initial Prompt.** A mobile backend verifies Firebase tokens.

**L5 Textbook Answer.** "They're signed by Google, so they're trustworthy."

**How an Attacker Bypasses L5.** Google signs *every* project's tokens with the same keys. The attacker's own project yields valid signatures (L44).

**L7 Principal Defense.**
- **Exact `aud` = your project id** and `iss` = `https://securetoken.google.com/<project>`.
- **Plus** `auth_time` freshness for sensitive actions, and revocation checks (`checkRevoked`) where needed.
- **Or use Firebase Admin `verifyIdToken`,** which does this.

</details>

<details><summary><b>Q4 · Keycloak tokens don't contain our API in `aud`. The team removed the audience check. Problem?</b></summary>

**Initial Prompt.** Keycloak 2x, several clients in one realm.

**L5 Textbook Answer.** "The issuer check is enough; it's our realm."

**How an Attacker Bypasses L5.** Every client in the realm (admin-cli, test apps, a partner's client) gets tokens your API accepts (L44).

**L7 Principal Defense.**
- **Add an audience mapper** (or a client scope) so tokens for your API carry `aud = payments-api`.
- **Require it,** allow-list `azp`, and require `typ` = `Bearer`.
- **Separate realms** for very different trust zones.

</details>

<details><summary><b>Q5 · Build vs buy for CIAM?</b></summary>

**Initial Prompt.** 20 million consumers, FAPI requirements later.

**L5 Textbook Answer.** "Build it; OAuth isn't that hard."

**How an Attacker Bypasses L5.** Home-grown login, recovery, MFA, bot protection and token issuance repeat a decade of CVEs (Folders 01–04).

**L7 Principal Defense.**
- **Buy or run a mature OP:** a managed CIAM, or Keycloak if you need control.
- **Own the integration conventions** (L44), the authorization model, tenancy and the threat model.
- **Check FAPI 2.0 support** (PAR, DPoP, `private_key_jwt`) before committing.
- **Plan exit:** standard protocols, and password-hash export where possible.

</details>

<details><summary><b>Q6 · One user pool for all customers or one per customer?</b></summary>

**Initial Prompt.** B2B SaaS on Cognito.

**L5 Textbook Answer.** "One pool; put the tenant in a custom attribute."

**How an Attacker Bypasses L5.** If the attribute is user-writable, users change tenants (A5). A shared pool shares settings (MFA, password policy, federation) across customers with different requirements.

**L7 Principal Defense.**
- **Small number of enterprise tenants with their own IdPs:** a pool or tenant per customer, with federation.
- **Many small tenants:** a shared pool with the tenant in an admin-only attribute or a group, and server-side tenant resolution.
- **Either way,** tenant isolation is enforced downstream with ABAC or ReBAC (Folder 05).

</details>

<details><summary><b>Q7 · How do you secure CIAM customization hooks?</b></summary>

**Initial Prompt.** A pre-token Lambda adds entitlements from a database.

**L5 Textbook Answer.** "It's internal code; standard review."

**How an Attacker Bypasses L5.** Injection or logic bugs in the hook mint privileged claims for everyone (A7). The hook's IAM role may also reach more data than needed.

**L7 Principal Defense.**
- **Treat hooks as part of the authorization server:** threat-model them, test claims for every role, use least-privilege roles, time-box them, and fail closed.
- **Avoid putting fast-changing entitlements in tokens** at all. Keep them in a PDP queried at request time.

</details>

<details><summary><b>Q8 · Your CIAM supports passkeys. What else must change?</b></summary>

**Initial Prompt.** A passkeys rollout.

**L5 Textbook Answer.** "Turn on passkeys in the console."

**How an Attacker Bypasses L5.** Recovery via email OTP or SMS remains phishable, so attackers use recovery instead of login (Folder 01).

**L7 Principal Defense.**
- **Make recovery as strong as login:** multiple passkeys, verified-identity recovery, and cool-down periods.
- **Step-up (`acr`) for sensitive actions,** with APIs checking `acr`/`amr`.
- **Monitor recovery abuse.**
- **For high assurance,** use device-bound passkeys and attestation policies.

</details>

---

## 9. Invariants checklist

- [ ] Every API validates the platform's conventions: token type, audience/client, exact issuer, tenant/project, scopes (L44).
- [ ] Only access tokens at APIs; ID tokens stay with the client.
- [ ] Multi-tenant: tenant allow-list, issuer bound to tenant, tenant mapped and enforced downstream.
- [ ] Authorization data never in user-writable attributes; admin-managed groups or a PDP.
- [ ] Self-service sign-up explicitly configured per pool/realm; bot protection on.
- [ ] Customization hooks reviewed, tested, least-privilege, fail-closed.
- [ ] Recovery as strong as login; step-up for sensitive actions.
- [ ] FAPI requirements (PAR, DPoP, `private_key_jwt`) verified on the chosen platform before commitment.

---

## 10. References

- Amazon Cognito, *Verifying a JSON web token* — <https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html>
- Microsoft identity platform, *Access tokens* — <https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens>
- Microsoft Entra External ID overview — <https://learn.microsoft.com/en-us/entra/external-id/external-identities-overview>
- Firebase, *Verify ID tokens* — <https://firebase.google.com/docs/auth/admin/verify-id-tokens>
- Google Cloud Identity Platform — <https://cloud.google.com/security/products/identity-platform>
- Keycloak documentation (server administration, audience support) — <https://www.keycloak.org/documentation>
