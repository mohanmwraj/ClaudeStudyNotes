# FAPI 2.0 Security Profile: PAR (RFC 9126), JAR, JARM and Rich Authorization Requests (RAR)

> Folder 04 · File 02 of 03 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [01 · mTLS vs DPoP](01-sender-constrained-tokens-mtls-rfc8705-vs-dpop-rfc9449-proof-of-possession.md) · Next: [03 · Browser SPA security and the BFF](03-browser-spa-security-rfc10017-why-localstorage-fails-and-the-bff-token-handler-pattern.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L30 `ParJarRarLab.java` | Oracles from the fixtures:<br>• RFC 9101's RS256 request object verifies under its JWK;<br>• RFC 9396 Figure 1 parses and its IBAN passes ISO 13616 mod-97;<br>• the RFC 9126 and FAPI 2.0 limits are cited verbatim.<br><br>A payment consent faces 8 attacks:<br>• **L5**, a front-channel request, shows "Pay EUR 123.50 to Merchant A" while the grant pays the **attacker's IBAN**;<br>• **L6**, PAR without discipline, loses 7 of 8;<br>• **L7**, FAPI 2.0 PAR, loses none.<br><br>The RS half of RAR: L5 executes a EUR 9,999 payment to another IBAN on the same token, and L7 does not. Also the JAR/JARM validation rules of FAPI 2.0 Message Signing | RFC 9101 §4, RFC 9396 §2, RFC 9126 §2.2; FAPI 2.0 §5.3.2.2; Message Signing §5.3.1 |
| L31 `SasParLab.java` | Spring Authorization Server 7.1.2's real PAR and authorization-code providers:<br>• request_uri lifetime about 300 s, one-time use and client binding all enforced, as is PKCE S256;<br>• a **non-PAR** request is still served.<br><br>`JwtClientAssertionDecoderFactory`, with the client JWK Set served over HTTP, **accepts** a replayed assertion, `aud` = token or PAR endpoint URL, and an `aud` array. A FAPI 2.0 conformance table of the defaults: **3 of 10** requirements met | FAPI 2.0 Security Profile (fixture); rfc7523bis §4; OIDC Core §9 |

**Verification.** Compiled with Folders 01–04 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs both outputs and requires them byte-identical. L31 runs spring-security 7.1.2's authorization-server classes and Nimbus 10.9.1, and serves the client's JWK Set from `com.sun.net.httpserver` on 127.0.0.1.

Normative text is quoted from the fixtures:
- RFC 9126, 9101 and 9396;
- the FAPI 2.0 Security Profile (Final, 22 Feb 2025) and FAPI 2.0 Message Signing (Final, 25 Sept 2025);
- JARM (Final, 9 Nov 2022).

The two FAPI texts and JARM are HTML-stripped copies under the OpenID Foundation licence. Spring facts marked [D] were read from the 7.1.2 sources: `OAuth2AuthorizationEndpointFilter.sendAuthorizationResponse`, `JwtClientAssertionDecoderFactory.getAudience`, `JwtGenerator` and `OAuth2PushedAuthorizationRequestUri`.

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

FAPI 2.0 is what OAuth looks like when the threat model is written down first. Its attacker model names who can read which messages (A3a reads authorization requests, A5 reads resource requests) [D: FAPI 2.0 Attacker Model §7]. Its Security Profile is the minimum set of mechanisms that a formal analysis showed sufficient against them. Most of the profile sits in this folder:
- sender-constrained tokens (file 01);
- PAR, so the browser never carries the request;
- PKCE S256, which replaces `state` for CSRF;
- RFC 9207 `iss`, against mix-up;
- confidential clients only, with `private_key_jwt` or mTLS client authentication;
- short-lived, single-use codes;
- a short algorithm list.

RAR (RFC 9396) is RECOMMENDED for anything `scope` can't express, which means every payment. Message Signing adds JAR and JARM when you need non-repudiation.

Results:
- **[M] The front channel is the weak link (L30).** With parameters in the browser, a man-in-the-browser rewrites the creditor IBAN. The consent screen still says "Pay EUR 123.50 to Merchant A", and the grant pays the attacker. PAR moves the request to an authenticated back channel, and the front channel carries only `client_id` and an opaque `request_uri`.
- **[M] PAR without discipline buys almost nothing (L30, L6 column).** Without client authentication, an attacker pushes its own request as the client. Without one-time use, expiry and client binding, `request_uri` values replay. Without RAR validation, a negative amount reaches the consent screen.
- **[M] RAR is enforced twice.** The AS validates `authorization_details` (`invalid_authorization_details`). The RS checks that each API call matches the granted details and consumes them. A scope-only RS executes a EUR 9,999 payment to another IBAN on a EUR 123.50 consent.
- **[M] Spring Authorization Server 7.1.2 defaults meet 3 of 10 FAPI 2.0 requirements tested (L31).**
  - **Met:** PAR lifetime under 600 s; PKCE S256 required; no refresh rotation.
  - **Not met, measured:**
    - authorization codes live **5 min** (FAPI: at most 60 s);
    - **non-PAR requests are served**;
    - client assertions are accepted with `aud` = token or PAR endpoint URL, as arrays, and **replayed**, against rfc7523bis's "MUST reject any JWT that does not contain its issuer identifier as its sole audience value" and OIDC Core §9's "MUST only be used once";
    - DPoP is optional (file 01);
    - JWTs are RS256.
  - **Not met, from source [D]:** no `iss` authorization-response parameter; no `dpop_jkt`; no RAR support at all.
  - **All fixable with public hooks** (§7).
- **[D] FAPI 2.0 forbids refresh-token rotation** "except in extraordinary circumstances". With confidential clients and sender-constrained tokens, rotation "does not provide security benefits" and causes outages when the client loses the new token [D: §5.3.2.1 Note 1]. That contrasts with Folder 02's public-client advice: the threat model changed, so the control changed.

---

## 1. First principles: why the authorization request must leave the browser

```text
  FAPI 2.0 authorization code flow (Security Profile §5.3)                      who can see / tamper?
  -------------------------------------------------------------------------------------------------
  client --POST /par (private_key_jwt | mTLS, all params, PKCE S256, RAR)--> AS     TLS back channel; client authenticated
  client <--201 {request_uri: urn:...:<256-bit random>, expires_in: 60}------- AS
  browser --GET /authorize?client_id=..&request_uri=..-----------------------> AS   A3a can READ this: it learns nothing
  browser <--consent: "Pay EUR 123.50 to Merchant A (IBAN DE02...)"--------- AS     useful, can change nothing
  browser --redirect: /cb?code=..&iss=https://as.bank.example----------------> client  code is single-use, 60 s, PKCE-bound
  client --POST /token (client auth, code_verifier, DPoP proof | mTLS)-------> AS
  client <--{access_token (DPoP-bound), authorization_details: [...]}-------- AS
  client --API call + DPoP proof---------------------------------------------> RS   RS checks binding AND authorization_details
```

| FAPI 1.0 Advanced | FAPI 2.0 | Why [D: FAPI 2.0 §5.5] |
|---|---|---|
| JAR (signed request object in the front channel) | PAR | integrity and confidentiality of the request, plus client authentication, without front-channel JWTs |
| JARM / hybrid flow (`code id_token`) | only `code` in the response | nothing left in the response that needs integrity protection; no ID token in the front channel (privacy) |
| `s_hash`, `state` for CSRF | PKCE | "PKCE cannot" be skipped by clients, unlike nonce/signature checks |
| pre-registered redirect URIs | redirect URIs in PAR | registration not required with client authentication + PAR |

---

## 2. PAR (RFC 9126) on the wire

```http
POST /as/par HTTP/1.1
Host: as.example.com
Content-Type: application/x-www-form-urlencoded

response_type=code&client_id=CLIENT1234&state=duk681S8n00GsJpe7n9boxdzen&redirect_uri=https%3A%2F%2Fclient.example.org%2Fcb&client_assertion_type=urn%3Aietf%3Aparams%3Aoauth%3Aclient-assertion-type%3Ajwt-bearer&client_assertion=eyJraWQiOiI0MiIsImFsZyI6IkVTMjU2In0.eyJpc3MiOiJDTElFTlQxMjM0Iiwic3ViIjoiQ0xJRU5UMTIzNCIsImF1ZCI6Imh0dHBzOi8vc2VydmVyLmV4YW1wbGUuY29tIiwiZXhwIjoxNjI1ODY4ODc4fQ.Igw8QrpAWRNPDGoWGRmJumLBMwbLjeIYwqWUu-ywgvvufl_0sQJftNs3bzjIrP0BV9rRG-3eI1Ksh0kQ1CwvzA&authorization_details=%5B%7B%22type%22%3A%22payment_initiation%22%2C...%7D%5D
```

That is RFC 9396 §2's PAR example (with the `authorization_details` value abbreviated) [D].

```http
HTTP/1.1 201 Created
Cache-Control: no-cache, no-store
Content-Type: application/json

{"request_uri": "urn:ietf:params:oauth:request_uri:6esc_11ACC5bwc014ltc14eY22c", "expires_in": 60}
```

That is RFC 9126 §2.2's response [D].

```http
GET /authorize?client_id=CLIENT1234&request_uri=urn%3Aietf%3Aparams%3Aoauth%3Arequest_uri%3A6esc_11ACC5bwc014ltc14eY22c HTTP/1.1
Host: as.example.com
```

What the front channel carries, with and without PAR:

```text
  WITHOUT PAR: the browser carries the request                WITH PAR: the browser carries a reference
  ----------------------------------------------              ----------------------------------------------
  GET /authorize?client_id=fintech-a                           GET /authorize?client_id=fintech-a
    &redirect_uri=https://fintech-a.example/cb                   &request_uri=urn:ietf:params:oauth:request_uri:Q2h...
    &code_challenge=E9Mel...&code_challenge_method=S256
    &authorization_details=[{"type":"payment_initiation",      A3a (reads requests) learns an opaque reference:
       "instructedAmount":{"amount":"123.50",...},               one-time, 60 s, bound to fintech-a
       "creditorAccount":{"iban":"DE02..."}}]                  MitB edits it      -> invalid_request_uri
  readable by extensions, proxy logs, Referer                  forged by others   -> PAR needs client auth
  editable by MitB: IBAN swap (L30 L5 row 1)
  sendable by anyone: no client authentication
```

The rules that matter [D unless marked]:
- **Client authentication at the PAR endpoint** ("shall reject pushed authorization requests without client authentication", FAPI 2.0 §5.3.2.2). This is what turns PAR from a transport trick into an integrity guarantee: the AS knows the request came from the client.
- **`request_uri` lifetime:** FAPI requires `expires_in` "less than 600 seconds". RFC 9126's example uses 60. Allow for slow devices: FAPI Note 2 says over 30 seconds is common.
- **One-time use, enforced "at the point of authorization, not at the point of loading an authorization page"**, because preloaders and link scanners fetch URLs (FAPI Note 3).
- **Bound to the client:** a `request_uri` presented with another `client_id` is rejected.
- **Unguessable:** FAPI requires 128 bits of entropy for credentials not handled by users. A random 256-bit `request_uri` is [E].
- **PAR required.** FAPI says "shall reject authorization requests sent without [RFC9126]". RFC 9126 defines `require_pushed_authorization_requests` in both AS and client metadata so clients can discover it.
- **Only `client_id` and `request_uri` in the front channel** (FAPI §5.3.3.2). Anything else is ignored or rejected.

---

## 3. Rich Authorization Requests (RFC 9396)

`scope=payments` says what kind of thing the client may do. `authorization_details` says *exactly* what: this amount, to this creditor, from this account, once [D: §2].

```json
{"type": "payment_initiation", "locations": ["https://example.com/payments"],
 "instructedAmount": {"currency": "EUR", "amount": "123.50"}, "creditorName": "Merchant A",
 "creditorAccount": {"bic": "ABCIDEFFXXX", "iban": "DE02100100109307118603"},
 "remittanceInformationUnstructured": "Ref Number Merchant"}
```

That is RFC 9396 Figure 1, which L30 parses from the fixture and whose IBAN passes mod-97. The common fields are `type` (REQUIRED, the schema selector), `locations`, `actions`, `datatypes`, `identifier` and `privileges`. Each `type` defines the rest.

AS duties:
- **Validate.** Return `invalid_authorization_details` for:
  - an unknown `type`;
  - missing or malformed fields;
  - values outside policy;
  - values the user may not authorize [D: §5].
- **Render the consent from the details.** Show the IBAN, not just a display name. In L30, L5 shows only "Merchant A", and that is the swap.
- **Return the granted details in the token response** ("the AS MUST also return the authorization_details as granted", §7) and in introspection or the JWT access token (§9).

RS duties [E]:
- **Compare each request against the granted details:** amount, currency, creditor and debtor account.
- **Consume single-use grants** (`identifier`, or the grant id).
- **Never trust the client's copy.**

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant C as Fintech (client)
    participant AS as Bank AS
    participant RS as Payments API
    C->>AS: POST /par (private_key_jwt, PKCE, authorization_details: EUR 123.50 to DE02...)
    AS->>AS: validate type, amount, currency, IBAN mod-97, creditor policy
    AS-->>C: 201 request_uri (60 s, single-use, bound to client)
    C->>U: redirect /authorize?client_id&request_uri
    U->>AS: approve "Pay EUR 123.50 to Merchant A (IBAN DE02...)"
    AS-->>C: code + iss  ->  token (DPoP) + authorization_details as granted
    C->>RS: POST /payments EUR 123.50 to DE02... (DPoP proof)
    RS->>RS: payment == granted details? grant unused? -> execute, mark consumed
    C->>RS: POST /payments EUR 9,999 to GB33... (same token)
    RS-->>C: 403 insufficient_scope (details do not match)
```

---

## 4. JAR (RFC 9101) and JARM: signing the request and the response

FAPI 2.0 baseline does not need them: PAR protects the request, and the response carries only `code` + `iss`. **FAPI 2.0 Message Signing** adds them when the ecosystem needs non-repudiation [D]. The AS:
- "shall support, require use of, and verify signed request objects";
- "shall require the aud claim in the request object to be, or to be an array containing, the authorization server's issuer identifier URL";
- requires `nbf` "no longer than 60 minutes in the past" and `exp` "no longer than 60 minutes after the nbf claim";
- "shall accept" `typ` `oauth-authz-req+jwt`.

```json
{"iss": "s6BhdRkqt3", "aud": "https://server.example.com", "response_type": "code id_token",
 "client_id": "s6BhdRkqt3", "redirect_uri": "https://client.example.org/cb", "scope": "openid",
 "state": "af0ifjsldkj", "nonce": "n-0S6_WzA2Mj", "max_age": 86400}
```

That is RFC 9101 §4's example request-object claims. L30 verifies the RFC's RS256 signature under JWK `k2bdc`. With PAR, the request object is POSTed as the `request` parameter to the PAR endpoint. Its parameters "MUST NOT" include `request` or `request_uri` [D: RFC 9101 §4].

**JARM** wraps the authorization response in a JWT signed by the AS (`iss`, `aud` = client_id, `exp`, plus the response parameters). It is delivered with `response_mode=query.jwt`, `fragment.jwt`, `form_post.jwt` or `jwt`. The client verifies the signature with the *expected* AS's key, then `iss`, `aud` and `exp` [D: JARM §2.4]. Message Signing notes that the signed values (code, state) are flow artefacts, so their non-repudiation value is limited (§6.6). Real non-repudiation of a payment comes from signing the *RAR details* and the API messages [E].

---

## 5. L30: PAR, RAR, JAR and JARM from first principles

<!-- listing:ParJarRarLab.java -->
```java
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * L30 - FAPI 2.0 authorization requests from first principles: PAR (RFC 9126), JAR (RFC 9101), JARM and Rich
 * Authorization Requests (RFC 9396).
 *
 * <ul>
 *   <li>Oracles: RFC 9101's RS256 request object verifies under its JWK; RFC 9396 Figure 1's authorization_details
 *       parse and its IBAN passes ISO 13616 mod-97; RFC 9126's request_uri and FAPI 2.0's limits are cited;</li>
 *   <li>three authorization servers - L5 (front-channel parameters), L6 (PAR without FAPI discipline) and L7
 *       (FAPI 2.0 PAR) - against eight attacks on a payment consent;</li>
 *   <li>the resource server's half of RAR: does the payment match what the user consented to?</li>
 *   <li>JAR and JARM validation rules of FAPI 2.0 Message Signing.</li>
 * </ul>
 */
public final class ParJarRarLab {
    static final String AS = "https://as.bank.example";
    static final long NOW = 1_767_225_600L;
    static final SecureRandom RNG = new SecureRandom();

    // ------------------------------------------------------------------ RAR

    /** ISO 13616: move the first four characters to the end, letters -> 10..35, the number mod 97 must be 1. */
    static boolean ibanOk(String iban) {
        String s = iban.replace(" ", "").toUpperCase(Locale.ROOT);
        if (!s.matches("[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}")) {
            return false;
        }
        StringBuilder digits = new StringBuilder();
        for (char c : (s.substring(4) + s.substring(0, 4)).toCharArray()) {
            digits.append(Character.isLetter(c) ? String.valueOf(c - 'A' + 10) : String.valueOf(c));
        }
        return new BigInteger(digits.toString()).mod(BigInteger.valueOf(97)).intValue() == 1;
    }

    /** The AS's authorization_details policy (RFC 9396 section 5: invalid_authorization_details on any violation). */
    @SuppressWarnings("unchecked")
    static String validateRar(List<Object> details) {
        for (Object o : details) {
            Map<String, Object> d = (Map<String, Object>) o;
            if (!"payment_initiation".equals(d.get("type"))) {
                return "unknown type " + d.get("type");
            }
            Map<String, Object> amt = (Map<String, Object>) d.get("instructedAmount");
            Map<String, Object> acct = (Map<String, Object>) d.get("creditorAccount");
            if (amt == null || acct == null || d.get("creditorName") == null) {
                return "missing instructedAmount / creditorAccount / creditorName";
            }
            if (!Set.of("EUR", "GBP").contains(amt.get("currency"))) {
                return "currency " + amt.get("currency");
            }
            String a = String.valueOf(amt.get("amount"));
            if (!a.matches("[0-9]{1,7}(\\.[0-9]{2})?") || new java.math.BigDecimal(a).signum() <= 0) {
                return "amount " + a;
            }
            if (!ibanOk(String.valueOf(acct.get("iban")))) {
                return "creditorAccount.iban fails mod-97";
            }
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    static String consentScreen(List<Object> details, boolean showIban) {
        Map<String, Object> d = (Map<String, Object>) details.get(0);
        Map<String, Object> amt = (Map<String, Object>) d.get("instructedAmount");
        Map<String, Object> acct = (Map<String, Object>) d.get("creditorAccount");
        return "Pay " + amt.get("currency") + " " + amt.get("amount") + " to " + d.get("creditorName")
                + (showIban ? " (IBAN " + acct.get("iban") + ")" : "");
    }

    // ------------------------------------------------------------------ authorization servers

    record Pushed(String clientId, String details, long expires, boolean[] used) {
    }

    static final class Server {
        final String kind;
        final Jose.Jwk clientKey;
        final Map<String, Pushed> pushed = new HashMap<>();
        final Set<String> assertionJti = new HashSet<>();
        int seq = 1000;

        Server(String kind, Jose.Jwk clientKey) {
            this.kind = kind;
            this.clientKey = clientKey;
        }

        boolean fapi() {
            return kind.equals("L7");
        }

        /** private_key_jwt per FAPI 2.0: iss = sub = client_id, aud = the issuer as a STRING, exp, single-use jti. */
        String authenticate(String clientId, String assertion) {
            if (assertion == null) {
                return "no client authentication";
            }
            Jose.Parts p = Jose.parse(assertion);
            Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
            if (!Jose.rawVerify("ES256", clientKey, p.signingInput(), p.sig())) {
                return "assertion signature";
            }
            if (!clientId.equals(c.get("iss")) || !clientId.equals(c.get("sub")) || !AS.equals(c.get("aud"))) {
                return "assertion iss/sub/aud";
            }
            if (((Number) c.get("exp")).longValue() < NOW || !assertionJti.add(String.valueOf(c.get("jti")))) {
                return "assertion expired or replayed";
            }
            return null;
        }

        /** POST /par (L6, L7). Returns the request_uri or "400 ...". */
        String par(String clientId, String assertion, String detailsJson) {
            if (fapi()) {
                String why = authenticate(clientId, assertion);
                if (why != null) {
                    return "401 invalid_client (" + why + ")";
                }
                @SuppressWarnings("unchecked")
                String bad = validateRar((List<Object>) MiniJson.parse(detailsJson));
                if (bad != null) {
                    return "400 invalid_authorization_details (" + bad + ")";
                }
            }
            byte[] r = new byte[32];
            RNG.nextBytes(r);
            String uri = fapi() ? "urn:ietf:params:oauth:request_uri:" + KbSupport.b64u(r) : "urn:example:par-" + (++seq);
            pushed.put(uri, new Pushed(clientId, detailsJson, fapi() ? NOW + 60 : Long.MAX_VALUE, new boolean[1]));
            return uri;
        }

        /** GET /authorize; returns what the user is asked to approve, or the error. */
        @SuppressWarnings("unchecked")
        String authorize(long at, String clientId, String requestUri, String frontChannelDetails) {
            String detailsJson;
            if (requestUri == null) {
                if (fapi()) {
                    return "400 invalid_request (FAPI 2.0: authorization requests without PAR are rejected)";
                }
                detailsJson = frontChannelDetails;
            } else {
                Pushed p = pushed.get(requestUri);
                if (p == null) {
                    return "400 invalid_request_uri";
                }
                if (fapi() && (!p.clientId().equals(clientId) || at > p.expires() || p.used()[0])) {
                    return "400 invalid_request_uri (" + (!p.clientId().equals(clientId) ? "other client" : at > p.expires() ? "expired" : "already used") + ")";
                }
                p.used()[0] = true;
                detailsJson = p.details();
            }
            List<Object> details = (List<Object>) MiniJson.parse(detailsJson);
            if (fapi()) {
                return "consent: " + consentScreen(details, true);
            }
            String grantIban = String.valueOf(((Map<String, Object>) ((Map<String, Object>) details.get(0)).get("creditorAccount")).get("iban"));
            return "consent: " + consentScreen(details, false) + "  | grant pays " + grantIban
                    + (validateRar(details) != null ? "  [unvalidated]" : "");
        }
    }

    static String assertion(Jose.Jwk k, String clientId, String aud, String jti) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", "ES256");
        h.put("typ", "client-authentication+jwt");
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("iss", clientId);
        c.put("sub", clientId);
        c.put("aud", aud);
        c.put("exp", NOW + 60);
        c.put("jti", jti);
        return Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), k);
    }

    static String details(String amount, String iban, String type) {
        return "[{\"type\":\"" + type + "\",\"locations\":[\"https://api.bank.example/payments\"],"
                + "\"instructedAmount\":{\"currency\":\"EUR\",\"amount\":\"" + amount + "\"},\"creditorName\":\"Merchant A\","
                + "\"creditorAccount\":{\"iban\":\"" + iban + "\"},\"remittanceInformationUnstructured\":\"Ref Number Merchant\"}]";
    }

    // ------------------------------------------------------------------ JAR / JARM (FAPI 2.0 Message Signing)

    static String requestObject(Jose.Jwk k, String alg, String aud, long nbf, long exp, String typ) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", alg);
        if (typ != null) {
            h.put("typ", typ);
        }
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("iss", "fintech-a");
        c.put("aud", aud);
        c.put("client_id", "fintech-a");
        c.put("response_type", "code");
        c.put("redirect_uri", "https://fintech-a.example/cb");
        c.put("nbf", nbf);
        c.put("exp", exp);
        String payload = MiniJson.write(c);
        if (alg.equals("none")) {
            return KbSupport.b64u(MiniJson.write(h).getBytes(StandardCharsets.UTF_8)) + "." + KbSupport.b64u(payload.getBytes(StandardCharsets.UTF_8)) + ".";
        }
        return Jose.sign(h, payload.getBytes(StandardCharsets.UTF_8), k);
    }

    /** FAPI 2.0 Message Signing section 5.3.1 (signed request objects) + RFC 9101 section 6. */
    static String checkRequestObject(String jwt, Jose.Jwk clientKey) {
        String[] seg = jwt.split("\\.", -1);
        Map<String, Object> h = MiniJson.object(new String(KbSupport.unb64u(seg[0]), StandardCharsets.UTF_8));
        if (!"ES256".equals(h.get("alg")) && !"PS256".equals(h.get("alg"))) {
            return "reject: alg " + h.get("alg");
        }
        Jose.Parts p = Jose.parse(jwt);
        if (!Jose.rawVerify(String.valueOf(h.get("alg")), clientKey, p.signingInput(), p.sig())) {
            return "reject: signature";
        }
        Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
        Object aud = c.get("aud");
        if (!(AS.equals(aud) || aud instanceof List<?> l && l.contains(AS))) {
            return "reject: aud " + aud;
        }
        long nbf = ((Number) c.get("nbf")).longValue();
        long exp = ((Number) c.get("exp")).longValue();
        if (nbf < NOW - 3_600 || exp - nbf > 3_600 || exp < NOW) {
            return "reject: nbf/exp outside the 60-minute rule";
        }
        return "accept";
    }

    static String jarm(Jose.Jwk asKey, String iss, String aud, long exp, String code) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", "ES256");
        h.put("kid", "as-2026");
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("iss", iss);
        c.put("aud", aud);
        c.put("exp", exp);
        c.put("code", code);
        c.put("state", "S8NJ7uqk5fY4EjNvP_G_FtyJu6pUsvH9jsYni9dMAJw");
        return Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), asKey);
    }

    /** JARM section 2.4: verify the signature with the expected AS's key, then iss, aud = client_id, exp. */
    static String checkJarm(String response, Jose.Jwk expectedAsKey) {
        Jose.Parts p = Jose.parse(response);
        if (!Jose.rawVerify("ES256", expectedAsKey, p.signingInput(), p.sig())) {
            return "reject: not signed by the expected AS";
        }
        Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
        if (!AS.equals(c.get("iss")) || !"fintech-a".equals(c.get("aud")) || ((Number) c.get("exp")).longValue() < NOW) {
            return "reject: iss/aud/exp";
        }
        return "accept: code " + c.get("code");
    }

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String r9101 = KbSupport.rfc(fx, "rfc9101.txt");
        String r9396 = KbSupport.rfc(fx, "rfc9396.txt");
        String r9126 = KbSupport.rfc(fx, "rfc9126.txt");
        String fapi = KbSupport.text(fx, "fapi-security-profile-2_0-final.txt");
        String fapiMs = KbSupport.text(fx, "fapi-message-signing-2_0-final.txt");

        KbSupport.section("Oracles (fixtures)");
        String ro = Jose.compactAfter(r9101, "Signing it with the \"RS256\" algorithm");
        Jose.Jwk k2bdc = Jose.Jwk.parse(Jose.jsonAfter(r9101, "can be used to validate the Request Object signature"));
        Jose.Parts rp = Jose.parse(ro);
        Map<String, Object> roClaims = MiniJson.object(new String(rp.payload(), StandardCharsets.UTF_8));
        KbSupport.check("RFC 9101 section 4: the RS256 request object verifies under JWK k2bdc; claims " + roClaims,
                Jose.rawVerify("RS256", k2bdc, rp.signingInput(), rp.sig()) && "s6BhdRkqt3".equals(roClaims.get("client_id"))
                        && "https://server.example.com".equals(roClaims.get("aud")));
        int fig = r9396.indexOf("Figure 1: Example of an Authorization Request for a Credit Transfer");
        int start = r9396.lastIndexOf("{", r9396.lastIndexOf("\"type\": \"payment_initiation\"", fig));
        Map<String, Object> fig1 = MiniJson.object(r9396.substring(start, r9396.lastIndexOf("}", fig) + 1));
        String iban = (String) ((Map<String, Object>) fig1.get("creditorAccount")).get("iban");
        KbSupport.check("RFC 9396 Figure 1 parses: " + consentScreen(List.of(fig1), true) + "; its IBAN passes mod-97",
                ibanOk(iban) && validateRar(List.of(fig1)) == null);
        KbSupport.mustCite(r9126, "urn:ietf:params:oauth:request_uri:6esc_11ACC5bwc014ltc14eY22c", "RFC 9126 section 2.2 request_uri");
        KbSupport.mustCite(fapi, "shall issue pushed authorization requests request_uri with expires_in values of less than 600 seconds",
                "FAPI 2.0 section 5.3.2.2");
        KbSupport.mustCite(fapi, "shall reject authorization requests sent without [RFC9126]", "FAPI 2.0 section 5.3.2.2");
        KbSupport.mustCite(fapiMs, "shall require the request object to contain an exp claim that has a lifetime of no longer than 60 minutes after the nbf claim",
                "FAPI 2.0 Message Signing section 5.3.1");

        KbSupport.section("Eight attacks on a EUR 123.50 payment consent (attacker IBAN GB33BUKB20201555555555)");
        Jose.Jwk client = Jose.generate("ES256", RNG);
        String good = details("123.50", iban, "payment_initiation");
        String evil = details("123.50", "GB33BUKB20201555555555", "payment_initiation");
        Map<String, Integer> wins = new LinkedHashMap<>();
        for (String kind : new String[] {"L5", "L6", "L7"}) {
            Server s = new Server(kind, client);
            List<String[]> rows = new ArrayList<>();
            boolean front = kind.equals("L5");
            String uri = front ? null : s.par("fintech-a", assertion(client, "fintech-a", AS, "j-1"), good);
            rows.add(new String[] {"0 legitimate flow", front ? s.authorize(NOW, "fintech-a", null, good) : s.authorize(NOW, "fintech-a", uri, null), "-"});
            String u1 = front ? null : s.par("fintech-a", assertion(client, "fintech-a", AS, "j-2"), good);
            rows.add(new String[] {"1 man-in-the-browser rewrites the IBAN in the front channel",
                front ? s.authorize(NOW, "fintech-a", null, evil) : s.authorize(NOW, "fintech-a", u1 + "x", null), "evil"});
            String forged = front ? null : s.par("fintech-a", null, evil);
            rows.add(new String[] {"2 attacker pushes its own request as fintech-a (no client auth)",
                front ? s.authorize(NOW, "fintech-a", null, evil) : forged.startsWith("urn") ? s.authorize(NOW, "fintech-a", forged, null) : forged, "evil"});
            rows.add(new String[] {"3 request_uri replayed (from history / referer)", front ? "n/a (no request_uri)" : s.authorize(NOW + 5, "fintech-a", uri, null), "reuse"});
            String u4 = front ? null : s.par("fintech-a", assertion(client, "fintech-a", AS, "j-4"), good);
            rows.add(new String[] {"4 request_uri redeemed 61 s later", front ? "n/a (no request_uri)" : s.authorize(NOW + 61, "fintech-a", u4, null), "reuse"});
            String u5 = front ? null : s.par("fintech-a", assertion(client, "fintech-a", AS, "j-5"), good);
            rows.add(new String[] {"5 request_uri used with another client_id", front ? "n/a (no request_uri)" : s.authorize(NOW, "rogue-app", u5, null), "reuse"});
            String bad = details("-5.00", "DE00100100109307118603", "payment_initiation");
            String u6 = front ? null : s.par("fintech-a", assertion(client, "fintech-a", AS, "j-6"), bad);
            rows.add(new String[] {"6 malformed details: amount -5.00, IBAN checksum wrong",
                front ? s.authorize(NOW, "fintech-a", null, bad) : u6.startsWith("urn") ? s.authorize(NOW, "fintech-a", u6, null) : u6, "bad"});
            rows.add(new String[] {"7 plain authorization request at a FAPI AS (no PAR)", s.authorize(NOW, "fintech-a", null, good), "nopar"});
            rows.add(new String[] {"8 PAR with a replayed client assertion", front ? "n/a (no PAR)"
                : s.par("fintech-a", assertion(client, "fintech-a", AS, "j-1"), good), "replay"});
            int w = 0;
            for (String[] r : rows) {
                boolean attackerWins = switch (r[2]) {
                    case "evil" -> r[1].contains("grant pays GB33");
                    case "reuse", "bad", "nopar" -> r[1].startsWith("consent");
                    case "replay" -> r[1].startsWith("urn");
                    default -> false;
                };
                if (!r[2].equals("-") && attackerWins) {
                    w++;
                }
                KbSupport.info("%s %-62s -> %s", kind, r[0], r[1]);
            }
            wins.put(kind, w);
        }
        KbSupport.check("L5 front channel: the IBAN swap and forgery succeed, unvalidated details get a consent screen (attacker wins " + wins.get("L5") + ")",
                wins.get("L5") >= 3);
        KbSupport.check("L6 PAR without discipline still loses to forgery, replay, expiry, client swap and replayed assertions (" + wins.get("L6") + ")",
                wins.get("L6") >= 5);
        KbSupport.check("L7 FAPI 2.0 PAR: the attacker wins none of the eight", wins.get("L7") == 0);

        KbSupport.section("The resource server's half: is this payment the one the user approved?");
        Map<String, Object> granted = (Map<String, Object>) ((List<Object>) MiniJson.parse(good)).get(0);
        String[][] payments = {{"123.50", "EUR", iban, "the consented payment"}, {"9999.00", "EUR", "GB33BUKB20201555555555", "same token, bigger payment, other IBAN"},
            {"123.50", "EUR", iban, "the consented payment, submitted twice"}};
        Set<String> consumed = new HashSet<>();
        int l5Bad = 0;
        int l7Bad = 0;
        for (String[] pay : payments) {
            boolean l5 = true; // L5: token has scope "payments"
            Map<String, Object> amt = (Map<String, Object>) granted.get("instructedAmount");
            boolean match = pay[0].equals(amt.get("amount")) && pay[1].equals(amt.get("currency"))
                    && pay[2].equals(((Map<String, Object>) granted.get("creditorAccount")).get("iban"));
            boolean l7 = match && consumed.add("grant-1");
            l5Bad += l5 && !pay[3].equals("the consented payment") ? 1 : 0;
            l7Bad += l7 && !pay[3].equals("the consented payment") ? 1 : 0;
            KbSupport.info("%-44s L5 (scope check) -> %-8s L7 (authorization_details + single use) -> %s", pay[3], l5 ? "EXECUTE" : "403", l7 ? "EXECUTE" : "403");
        }
        KbSupport.check("L5 executes both unauthorized payments; L7 executes only the consented one, once", l5Bad == 2 && l7Bad == 0);

        KbSupport.section("JAR and JARM checks (FAPI 2.0 Message Signing)");
        Jose.Jwk asKey = Jose.generate("ES256", RNG);
        Jose.Jwk rogueAs = Jose.generate("ES256", RNG);
        String[][] ros = {
            {"signed ES256, aud = issuer, nbf now, exp +30 min", requestObject(client, "ES256", AS, NOW, NOW + 1_800, "oauth-authz-req+jwt")},
            {"alg none", requestObject(client, "none", AS, NOW, NOW + 1_800, "oauth-authz-req+jwt")},
            {"aud = another AS", requestObject(client, "ES256", "https://as.other.example", NOW, NOW + 1_800, "oauth-authz-req+jwt")},
            {"exp 24 h after nbf", requestObject(client, "ES256", AS, NOW, NOW + 86_400, "oauth-authz-req+jwt")},
            {"no typ (accepted: FAPI says 'shall accept' typ, not require it)", requestObject(client, "ES256", AS, NOW, NOW + 600, null)}};
        int roOk = 0;
        for (String[] r : ros) {
            String res = checkRequestObject(r[1], client);
            roOk += res.equals("accept") ? 1 : 0;
            KbSupport.info("request object: %-66s -> %s", r[0], res);
        }
        String[][] responses = {
            {"JARM response from the honest AS", jarm(asKey, AS, "fintech-a", NOW + 60, "c-honest")},
            {"response injected by a rogue AS (its own key)", jarm(rogueAs, AS, "fintech-a", NOW + 60, "c-rogue")},
            {"honest AS, but issued for another client", jarm(asKey, AS, "other-client", NOW + 60, "c-other")},
            {"honest AS, expired", jarm(asKey, AS, "fintech-a", NOW - 1, "c-old")}};
        int jOk = 0;
        for (String[] r : responses) {
            String res = checkJarm(r[1], asKey);
            jOk += res.startsWith("accept") ? 1 : 0;
            KbSupport.info("JARM: %-50s -> %s", r[0], res);
        }
        KbSupport.check("request objects: 2 accepted (signed, short-lived, aud = issuer; typ optional), 3 rejected", roOk == 2);
        KbSupport.check("JARM: only the honest, unexpired response for this client is accepted", jOk == 1);
        KbSupport.verdict();
    }
}
```

<!-- output:ParJarRarLab.java -->
```text

== Oracles (fixtures)
  [PASS] RFC 9101 section 4: the RS256 request object verifies under JWK k2bdc; claims {iss=s6BhdRkqt3, aud=https://server.example.com, response_type=code id_token, client_id=s6BhdRkqt3, redirect_uri=https://client.example.org/cb, scope=openid, state=af0ifjsldkj, nonce=n-0S6_WzA2Mj, max_age=86400}
  [PASS] RFC 9396 Figure 1 parses: Pay EUR 123.50 to Merchant A (IBAN DE02100100109307118603); its IBAN passes mod-97
  [PASS] constant cited verbatim from fixture: RFC 9126 section 2.2 request_uri
  [PASS] constant cited verbatim from fixture: FAPI 2.0 section 5.3.2.2
  [PASS] constant cited verbatim from fixture: FAPI 2.0 section 5.3.2.2
  [PASS] constant cited verbatim from fixture: FAPI 2.0 Message Signing section 5.3.1

== Eight attacks on a EUR 123.50 payment consent (attacker IBAN GB33BUKB20201555555555)
  L5 0 legitimate flow                                              -> consent: Pay EUR 123.50 to Merchant A  | grant pays DE02100100109307118603
  L5 1 man-in-the-browser rewrites the IBAN in the front channel    -> consent: Pay EUR 123.50 to Merchant A  | grant pays GB33BUKB20201555555555
  L5 2 attacker pushes its own request as fintech-a (no client auth) -> consent: Pay EUR 123.50 to Merchant A  | grant pays GB33BUKB20201555555555
  L5 3 request_uri replayed (from history / referer)                -> n/a (no request_uri)
  L5 4 request_uri redeemed 61 s later                              -> n/a (no request_uri)
  L5 5 request_uri used with another client_id                      -> n/a (no request_uri)
  L5 6 malformed details: amount -5.00, IBAN checksum wrong         -> consent: Pay EUR -5.00 to Merchant A  | grant pays DE00100100109307118603  [unvalidated]
  L5 7 plain authorization request at a FAPI AS (no PAR)            -> consent: Pay EUR 123.50 to Merchant A  | grant pays DE02100100109307118603
  L5 8 PAR with a replayed client assertion                         -> n/a (no PAR)
  L6 0 legitimate flow                                              -> consent: Pay EUR 123.50 to Merchant A  | grant pays DE02100100109307118603
  L6 1 man-in-the-browser rewrites the IBAN in the front channel    -> 400 invalid_request_uri
  L6 2 attacker pushes its own request as fintech-a (no client auth) -> consent: Pay EUR 123.50 to Merchant A  | grant pays GB33BUKB20201555555555
  L6 3 request_uri replayed (from history / referer)                -> consent: Pay EUR 123.50 to Merchant A  | grant pays DE02100100109307118603
  L6 4 request_uri redeemed 61 s later                              -> consent: Pay EUR 123.50 to Merchant A  | grant pays DE02100100109307118603
  L6 5 request_uri used with another client_id                      -> consent: Pay EUR 123.50 to Merchant A  | grant pays DE02100100109307118603
  L6 6 malformed details: amount -5.00, IBAN checksum wrong         -> consent: Pay EUR -5.00 to Merchant A  | grant pays DE00100100109307118603  [unvalidated]
  L6 7 plain authorization request at a FAPI AS (no PAR)            -> consent: Pay EUR 123.50 to Merchant A  | grant pays DE02100100109307118603
  L6 8 PAR with a replayed client assertion                         -> urn:example:par-1007
  L7 0 legitimate flow                                              -> consent: Pay EUR 123.50 to Merchant A (IBAN DE02100100109307118603)
  L7 1 man-in-the-browser rewrites the IBAN in the front channel    -> 400 invalid_request_uri
  L7 2 attacker pushes its own request as fintech-a (no client auth) -> 401 invalid_client (no client authentication)
  L7 3 request_uri replayed (from history / referer)                -> 400 invalid_request_uri (already used)
  L7 4 request_uri redeemed 61 s later                              -> 400 invalid_request_uri (expired)
  L7 5 request_uri used with another client_id                      -> 400 invalid_request_uri (other client)
  L7 6 malformed details: amount -5.00, IBAN checksum wrong         -> 400 invalid_authorization_details (amount -5.00)
  L7 7 plain authorization request at a FAPI AS (no PAR)            -> 400 invalid_request (FAPI 2.0: authorization requests without PAR are rejected)
  L7 8 PAR with a replayed client assertion                         -> 401 invalid_client (assertion expired or replayed)
  [PASS] L5 front channel: the IBAN swap and forgery succeed, unvalidated details get a consent screen (attacker wins 4)
  [PASS] L6 PAR without discipline still loses to forgery, replay, expiry, client swap and replayed assertions (7)
  [PASS] L7 FAPI 2.0 PAR: the attacker wins none of the eight

== The resource server's half: is this payment the one the user approved?
  the consented payment                        L5 (scope check) -> EXECUTE  L7 (authorization_details + single use) -> EXECUTE
  same token, bigger payment, other IBAN       L5 (scope check) -> EXECUTE  L7 (authorization_details + single use) -> 403
  the consented payment, submitted twice       L5 (scope check) -> EXECUTE  L7 (authorization_details + single use) -> 403
  [PASS] L5 executes both unauthorized payments; L7 executes only the consented one, once

== JAR and JARM checks (FAPI 2.0 Message Signing)
  request object: signed ES256, aud = issuer, nbf now, exp +30 min                   -> accept
  request object: alg none                                                           -> reject: alg none
  request object: aud = another AS                                                   -> reject: aud https://as.other.example
  request object: exp 24 h after nbf                                                 -> reject: nbf/exp outside the 60-minute rule
  request object: no typ (accepted: FAPI says 'shall accept' typ, not require it)    -> accept
  JARM: JARM response from the honest AS                   -> accept: code c-honest
  JARM: response injected by a rogue AS (its own key)      -> reject: not signed by the expected AS
  JARM: honest AS, but issued for another client           -> reject: iss/aud/exp
  JARM: honest AS, expired                                 -> reject: iss/aud/exp
  [PASS] request objects: 2 accepted (signed, short-lived, aud = issuer; typ optional), 3 rejected
  [PASS] JARM: only the honest, unexpired response for this client is accepted

verdict: OK (12 checks)
```

Reading the run:
- **L5 rows 1–2 are the reason PAR exists.** The rewritten IBAN, or a request forged with the client's id, produces a consent screen identical to the legitimate one, because it renders `creditorName`. The grant pays `GB33…`.
- **L6 shows that PAR's value comes from what you enforce around it.** An unauthenticated PAR endpoint is an open request-injection service. Reusable, non-expiring, client-agnostic `request_uri`s are bearer credentials. A replayed client assertion (row 8) is accepted because L6 keeps no `jti` store.
- **The RS section is the one most teams skip.** RAR at the AS without enforcement at the RS is a consent screen, not an authorization.
- **JAR row 5:** FAPI says the AS "shall accept" `typ` `oauth-authz-req+jwt`, which is not "shall require". Rejecting untyped request objects breaks clients. Accept both and rely on the signature, `aud` and timing [D].

---

## 6. L31: Spring Authorization Server 7.1.2 against the FAPI 2.0 Security Profile

<!-- listing:SasParLab.java -->
```java
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jose.jwk.Curve;
import com.nimbusds.jose.jwk.ECKey;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.gen.ECKeyGenerator;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.sun.net.httpserver.HttpServer;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.server.authorization.InMemoryOAuth2AuthorizationConsentService;
import org.springframework.security.oauth2.server.authorization.InMemoryOAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.OAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.authentication.JwtClientAssertionDecoderFactory;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2AuthorizationCodeRequestAuthenticationProvider;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2AuthorizationCodeRequestAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2ClientAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2PushedAuthorizationRequestAuthenticationProvider;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2PushedAuthorizationRequestAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.client.InMemoryRegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.context.AuthorizationServerContext;
import org.springframework.security.oauth2.server.authorization.context.AuthorizationServerContextHolder;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.ClientSettings;
import org.springframework.security.oauth2.server.authorization.settings.TokenSettings;

/**
 * L31 - Spring Authorization Server 7.1.2 against the FAPI 2.0 Security Profile, on the real classes:
 * {@link OAuth2PushedAuthorizationRequestAuthenticationProvider} and
 * {@link OAuth2AuthorizationCodeRequestAuthenticationProvider} (PAR lifetime, one-time use, client binding, PKCE,
 * whether a plain authorization request is still accepted), {@link JwtClientAssertionDecoderFactory} with the
 * client's JWK Set served over HTTP (which {@code aud} values and replays a {@code private_key_jwt} assertion may
 * carry), and the shipped defaults - then a conformance table whose every requirement is quoted from the profile.
 */
public final class SasParLab {
    static final String ISSUER = "https://as.bank.example";
    static final String AUTHZ = ISSUER + "/oauth2/authorize";
    static final String VERIFIER_CHALLENGE = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"; // RFC 7636 Appendix B

    static String err(Exception e) {
        if (e instanceof OAuth2AuthenticationException o) {
            return "400 " + o.getError().getErrorCode() + (o.getError().getDescription() != null ? " (" + o.getError().getDescription() + ")" : "");
        }
        return e.getClass().getSimpleName() + ": " + e.getMessage();
    }

    static Map<String, Object> pkce(String method) {
        Map<String, Object> m = new HashMap<>();
        m.put("code_challenge", VERIFIER_CHALLENGE);
        m.put("code_challenge_method", method);
        return m;
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String fapi = KbSupport.text(fx, "fapi-security-profile-2_0-final.txt");
        AuthorizationServerSettings settings = AuthorizationServerSettings.builder().issuer(ISSUER).build();
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

        ECKey clientKey = new ECKeyGenerator(Curve.P_256).keyID("fintech-a-1").generate();
        HttpServer jwks = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        byte[] set = new JWKSet(clientKey).toPublicJWKSet().toString().getBytes(StandardCharsets.UTF_8);
        jwks.createContext("/jwks", ex -> {
            ex.getResponseHeaders().add("Content-Type", "application/jwk-set+json");
            ex.sendResponseHeaders(200, set.length);
            ex.getResponseBody().write(set);
            ex.close();
        });
        jwks.start();
        try {
            RegisteredClient client = RegisteredClient.withId("rc-fintech-a").clientId("fintech-a")
                    .clientAuthenticationMethod(ClientAuthenticationMethod.PRIVATE_KEY_JWT)
                    .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE).redirectUri("https://fintech-a.example/cb").scope("accounts")
                    .clientSettings(ClientSettings.builder().jwkSetUrl("http://127.0.0.1:" + jwks.getAddress().getPort() + "/jwks")
                            .tokenEndpointAuthenticationSigningAlgorithm(SignatureAlgorithm.ES256).build())
                    .build();
            run(fapi, client, clientKey);
        } finally {
            jwks.stop(0);
        }
    }

    static void run(String fapi, RegisteredClient client, ECKey clientKey) throws Exception {
        OAuth2AuthorizationService svc = new InMemoryOAuth2AuthorizationService();
        OAuth2PushedAuthorizationRequestAuthenticationProvider par = new OAuth2PushedAuthorizationRequestAuthenticationProvider(svc);
        OAuth2AuthorizationCodeRequestAuthenticationProvider authz = new OAuth2AuthorizationCodeRequestAuthenticationProvider(
                new InMemoryRegisteredClientRepository(client), svc, new InMemoryOAuth2AuthorizationConsentService());
        Authentication clientAuth = new OAuth2ClientAuthenticationToken(client, ClientAuthenticationMethod.PRIVATE_KEY_JWT, "assertion");
        Authentication alice = UsernamePasswordAuthenticationToken.authenticated("alice", null, List.of());

        KbSupport.section("PAR and the authorization endpoint (OAuth2PushedAuthorization... / OAuth2AuthorizationCodeRequest... providers)");
        Map<String, String> r = new HashMap<>();
        String uri = null;
        try {
            OAuth2PushedAuthorizationRequestAuthenticationToken pushed = (OAuth2PushedAuthorizationRequestAuthenticationToken) par.authenticate(
                    new OAuth2PushedAuthorizationRequestAuthenticationToken(AUTHZ, "fintech-a", clientAuth, "https://fintech-a.example/cb", "st-1",
                            Set.of("accounts"), pkce("S256")));
            uri = pushed.getRequestUri();
            long secs = Duration.between(Instant.now(), pushed.getRequestUriExpiresAt()).toSeconds();
            r.put("par", "201 request_uri=urn:ietf:params:oauth:request_uri:<" + (uri.length() - "urn:ietf:params:oauth:request_uri:".length())
                    + " chars>, expires_in~" + Math.round(secs / 10.0) * 10 + " s");
        } catch (Exception e) {
            r.put("par", err(e));
        }
        r.put("use1", authorize(authz, uri, "fintech-a", alice, null));
        r.put("use2", authorize(authz, uri, "fintech-a", alice, null));
        String uri2 = ((OAuth2PushedAuthorizationRequestAuthenticationToken) par.authenticate(new OAuth2PushedAuthorizationRequestAuthenticationToken(
                AUTHZ, "fintech-a", clientAuth, "https://fintech-a.example/cb", "st-2", Set.of("accounts"), pkce("S256")))).getRequestUri();
        r.put("other", authorize(authz, uri2, "rogue-app", alice, null));
        r.put("plain", authorize(authz, null, "fintech-a", alice, pkce("S256")));
        r.put("nopkce", authorize(authz, null, "fintech-a", alice, new HashMap<>()));
        r.put("pkceplain", authorize(authz, null, "fintech-a", alice, pkce("plain")));
        String[][] rows = {{"POST /par (client authenticated, PKCE S256)", r.get("par")},
            {"GET /authorize?request_uri=... (first use)", r.get("use1")}, {"the same request_uri again", r.get("use2")},
            {"a fresh request_uri presented with client_id=rogue-app", r.get("other")},
            {"plain authorization request, no PAR (PKCE S256)", r.get("plain")},
            {"plain request without PKCE", r.get("nopkce")}, {"plain request with code_challenge_method=plain", r.get("pkceplain")}};
        for (String[] row : rows) {
            KbSupport.info("%-58s -> %s", row[0], row[1]);
        }
        KbSupport.check("PAR: about 300 s lifetime, one-time use at authorization, bound to the client; PKCE S256 enforced",
                r.get("par").endsWith("expires_in~300 s") && r.get("use1").startsWith("code issued") && r.get("use2").startsWith("400 invalid_request")
                        && r.get("other").startsWith("400 invalid_request") && r.get("nopkce").startsWith("400") && r.get("pkceplain").startsWith("400"));
        KbSupport.check("but a plain (non-PAR) authorization request is still served: FAPI 2.0 requires it be rejected",
                r.get("plain").startsWith("code issued"));

        KbSupport.section("private_key_jwt assertions through JwtClientAssertionDecoderFactory (client JWK Set over HTTP)");
        JwtClientAssertionDecoderFactory factory = new JwtClientAssertionDecoderFactory();
        String once = assertion(clientKey, ISSUER, "jti-replayed");
        Object[][] auds = {{"aud = issuer (string)", once, true}, {"the same assertion again (same jti)", once, false},
            {"aud = token endpoint URL", assertion(clientKey, ISSUER + "/oauth2/token", "j2"), false},
            {"aud = PAR endpoint URL", assertion(clientKey, ISSUER + "/oauth2/par", "j3"), false},
            {"aud = [issuer, https://as.attacker.example]", assertion(clientKey, List.of(ISSUER, "https://as.attacker.example"), "j4"), false},
            {"aud = https://as.attacker.example", assertion(clientKey, "https://as.attacker.example", "j5"), false}};
        int deviations = 0;
        for (Object[] a : auds) {
            String res;
            try {
                factory.createDecoder(client).decode((String) a[1]);
                res = "accepted";
            } catch (JwtException e) {
                res = "rejected (" + e.getMessage().replace("An error occurred while attempting to decode the Jwt: ", "") + ")";
            }
            boolean fapiOk = (Boolean) a[2];
            if (res.equals("accepted") != fapiOk) {
                deviations++;
            }
            String why = ((String) a[0]).startsWith("the same") ? "OIDC Core 9: these tokens MUST only be used once"
                    : "rfc7523bis 4 / FAPI 2.0 5.3.2.1: the issuer as the sole, string aud";
            KbSupport.info("%-46s -> %s%s", a[0], res, res.equals("accepted") != fapiOk ? "   <-- " + why : "");
        }
        KbSupport.check("4 deviations: replayed jti, token-endpoint aud, PAR-endpoint aud and an array with the issuer are all accepted",
                deviations == 4);

        KbSupport.section("FAPI 2.0 Security Profile conformance of Spring Authorization Server 7.1.2 defaults");
        TokenSettings ts = TokenSettings.builder().build();
        ClientSettings cs = ClientSettings.builder().build();
        List<String[]> table = new ArrayList<>();
        table.add(row(fapi, "shall issue authorization codes with a maximum lifetime of 60 seconds", "authorizationCodeTimeToLive " + ts.getAuthorizationCodeTimeToLive(),
                ts.getAuthorizationCodeTimeToLive().toSeconds() <= 60, "M"));
        table.add(row(fapi, "shall issue pushed authorization requests request_uri with expires_in values of less than 600 seconds", r.get("par").replaceAll(".*expires_in", "expires_in"),
                r.get("par").endsWith("~300 s"), "M"));
        table.add(row(fapi, "shall reject authorization requests sent without [RFC9126]", "plain request -> " + r.get("plain").split(" ")[0] + " issued", false, "M"));
        table.add(row(fapi, "shall require PKCE [RFC7636] with S256 as the code challenge method", "requireProofKey " + cs.isRequireProofKey() + ", plain rejected",
                cs.isRequireProofKey() && r.get("pkceplain").startsWith("400"), "M"));
        table.add(row(fapi, "shall return an iss parameter in the authorization response according to [RFC9207]", "response carries code and state only", false, "D"));
        table.add(row(fapi, "shall only accept its issuer identifier value (as defined in [RFC8414]) as a string in the aud claim received in client authentication assertions",
                "issuer + 4 endpoint URLs, arrays", false, "M"));
        table.add(row(fapi, "shall only issue sender-constrained access tokens", "DPoP optional per request; x509CertificateBoundAccessTokens " + ts.isX509CertificateBoundAccessTokens(),
                false, "M (L29)"));
        table.add(row(fapi, "Authorization Code Binding to DPoP Key", "no dpop_jkt in 7.1.2", false, "D"));
        table.add(row(fapi, "shall not use refresh token rotation except in extraordinary circumstances", "reuseRefreshTokens " + ts.isReuseRefreshTokens(),
                ts.isReuseRefreshTokens(), "M"));
        table.add(row(fapi, "use PS256, ES256, or EdDSA (using the Ed25519 variant) algorithms", "idTokenSignatureAlgorithm " + ts.getIdTokenSignatureAlgorithm()
                + "; JwtGenerator signs access tokens RS256", false, "M + D"));
        int pass = 0;
        for (String[] t : table) {
            pass += t[2].equals("yes") ? 1 : 0;
            KbSupport.info("%-4s %-10s %-68s default: %s", t[2], "[" + t[3] + "]", t[0], t[1]);
        }
        KbSupport.check(pass + " of " + table.size() + " FAPI 2.0 requirements met by the defaults; every requirement text cited verbatim from the profile",
                pass == 3);
        KbSupport.verdict();
    }

    static String[] row(String fapi, String requirement, String actual, boolean ok, String evidence) {
        KbSupport.mustCite(fapi, requirement, requirement.length() > 60 ? requirement.substring(0, 60) + "..." : requirement);
        String shortReq = requirement.length() > 68 ? requirement.substring(0, 65) + "..." : requirement;
        return new String[] {shortReq, actual, ok ? "yes" : "NO", evidence};
    }

    static String authorize(OAuth2AuthorizationCodeRequestAuthenticationProvider authz, String requestUri, String clientId, Authentication user,
                            Map<String, Object> plainParams) {
        Map<String, Object> params = requestUri != null ? new HashMap<>(Map.of("request_uri", requestUri)) : plainParams;
        try {
            OAuth2AuthorizationCodeRequestAuthenticationToken res = (OAuth2AuthorizationCodeRequestAuthenticationToken) authz.authenticate(
                    new OAuth2AuthorizationCodeRequestAuthenticationToken(AUTHZ, clientId, user, requestUri != null ? null : "https://fintech-a.example/cb",
                            requestUri != null ? null : "st-plain", requestUri != null ? null : Set.of("accounts"), params));
            return res.getAuthorizationCode() != null ? "code issued" : "no code";
        } catch (Exception e) {
            return err(e);
        }
    }

    static String assertion(ECKey key, Object aud, String jti) throws Exception {
        Instant now = Instant.now();
        JWTClaimsSet.Builder c = new JWTClaimsSet.Builder().issuer("fintech-a").subject("fintech-a").jwtID(jti)
                .issueTime(Date.from(now)).expirationTime(Date.from(now.plusSeconds(60)));
        if (aud instanceof List<?> l) {
            c.audience(l.stream().map(String::valueOf).toList());
        } else {
            c.audience((String) aud);
        }
        SignedJWT jwt = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.ES256).keyID(key.getKeyID())
                .type(new JOSEObjectType("client-authentication+jwt")).build(), c.build());
        jwt.sign(new ECDSASigner(key));
        return jwt.serialize();
    }
}
```

<!-- output:SasParLab.java -->
```text

== PAR and the authorization endpoint (OAuth2PushedAuthorization... / OAuth2AuthorizationCodeRequest... providers)
  POST /par (client authenticated, PKCE S256)                -> 201 request_uri=urn:ietf:params:oauth:request_uri:<60 chars>, expires_in~300 s
  GET /authorize?request_uri=... (first use)                 -> code issued
  the same request_uri again                                 -> 400 invalid_request (OAuth 2.0 Parameter: request_uri)
  a fresh request_uri presented with client_id=rogue-app     -> 400 invalid_request (OAuth 2.0 Parameter: client_id)
  plain authorization request, no PAR (PKCE S256)            -> code issued
  plain request without PKCE                                 -> 400 invalid_request (OAuth 2.0 Parameter: code_challenge)
  plain request with code_challenge_method=plain             -> 400 invalid_request (OAuth 2.0 Parameter: code_challenge_method)
  [PASS] PAR: about 300 s lifetime, one-time use at authorization, bound to the client; PKCE S256 enforced
  [PASS] but a plain (non-PAR) authorization request is still served: FAPI 2.0 requires it be rejected

== private_key_jwt assertions through JwtClientAssertionDecoderFactory (client JWK Set over HTTP)
  aud = issuer (string)                          -> accepted
  the same assertion again (same jti)            -> accepted   <-- OIDC Core 9: these tokens MUST only be used once
  aud = token endpoint URL                       -> accepted   <-- rfc7523bis 4 / FAPI 2.0 5.3.2.1: the issuer as the sole, string aud
  aud = PAR endpoint URL                         -> accepted   <-- rfc7523bis 4 / FAPI 2.0 5.3.2.1: the issuer as the sole, string aud
  aud = [issuer, https://as.attacker.example]    -> accepted   <-- rfc7523bis 4 / FAPI 2.0 5.3.2.1: the issuer as the sole, string aud
  aud = https://as.attacker.example              -> rejected (The aud claim is not valid)
  [PASS] 4 deviations: replayed jti, token-endpoint aud, PAR-endpoint aud and an array with the issuer are all accepted

== FAPI 2.0 Security Profile conformance of Spring Authorization Server 7.1.2 defaults
  [PASS] constant cited verbatim from fixture: shall issue authorization codes with a maximum lifetime of 6...
  [PASS] constant cited verbatim from fixture: shall issue pushed authorization requests request_uri with e...
  [PASS] constant cited verbatim from fixture: shall reject authorization requests sent without [RFC9126]
  [PASS] constant cited verbatim from fixture: shall require PKCE [RFC7636] with S256 as the code challenge...
  [PASS] constant cited verbatim from fixture: shall return an iss parameter in the authorization response ...
  [PASS] constant cited verbatim from fixture: shall only accept its issuer identifier value (as defined in...
  [PASS] constant cited verbatim from fixture: shall only issue sender-constrained access tokens
  [PASS] constant cited verbatim from fixture: Authorization Code Binding to DPoP Key
  [PASS] constant cited verbatim from fixture: shall not use refresh token rotation except in extraordinary...
  [PASS] constant cited verbatim from fixture: use PS256, ES256, or EdDSA (using the Ed25519 variant) algor...
  NO   [M]        shall issue authorization codes with a maximum lifetime of 60 sec... default: authorizationCodeTimeToLive PT5M
  yes  [M]        shall issue pushed authorization requests request_uri with expire... default: expires_in~300 s
  NO   [M]        shall reject authorization requests sent without [RFC9126]           default: plain request -> code issued
  yes  [M]        shall require PKCE [RFC7636] with S256 as the code challenge method  default: requireProofKey true, plain rejected
  NO   [D]        shall return an iss parameter in the authorization response accor... default: response carries code and state only
  NO   [M]        shall only accept its issuer identifier value (as defined in [RFC... default: issuer + 4 endpoint URLs, arrays
  NO   [M (L29)]  shall only issue sender-constrained access tokens                    default: DPoP optional per request; x509CertificateBoundAccessTokens false
  NO   [D]        Authorization Code Binding to DPoP Key                               default: no dpop_jkt in 7.1.2
  yes  [M]        shall not use refresh token rotation except in extraordinary circ... default: reuseRefreshTokens true
  NO   [M + D]    use PS256, ES256, or EdDSA (using the Ed25519 variant) algorithms    default: idTokenSignatureAlgorithm RS256; JwtGenerator signs access tokens RS256
  [PASS] 3 of 10 FAPI 2.0 requirements met by the defaults; every requirement text cited verbatim from the profile

verdict: OK (14 checks)
```

Reading the run:
- **PAR itself is implemented well [M, D].**
  - `OAuth2PushedAuthorizationRequestUri` mints `urn:ietf:params:oauth:request_uri:<random>___<expiry millis>`, about 300 s ahead.
  - The lookup key includes the expiry, so tampering with it fails the lookup.
  - The pushed request is removed after the code (or consent) is issued, which is FAPI Note 3's "at the point of authorization".
  - `client_id` must match.
- **What's missing is the FAPI posture around it:**
  - **Codes.** `TokenSettings.authorizationCodeTimeToLive` defaults to 5 min; set it to ≤ 60 s.
  - **Non-PAR requests are served.** A filter, or an `authenticationValidator` together with a marker set by PAR, must reject them per client (§7).
  - **Client assertions.** `JwtClientAssertionDecoderFactory.getAudience()` accepts the issuer plus the token, introspection, revocation and PAR endpoint URLs. It also accepts arrays, and keeps no `jti` memory. That is exactly the audience-injection class rfc7523bis closes (Folder 02 file 04). Replace the validator factory (`setJwtValidatorFactory`) and plug the factory into `JwtClientAssertionAuthenticationProvider.setJwtDecoderFactory`.
  - **`iss`.** `OAuth2AuthorizationEndpointFilter.sendAuthorizationResponse` appends `code` and `state` only, so mix-up defence (RFC 9207, Folder 02) needs a custom `authorizationResponseHandler`.
  - **Algorithms.** `JwtGenerator` starts from `SignatureAlgorithm.RS256` for access tokens, and `idTokenSignatureAlgorithm` defaults to RS256. FAPI allows PS256, ES256 or EdDSA only.
  - **RAR.** There is no `authorization_details` support anywhere in 7.1.2. It arrives as an additional parameter at PAR, so you validate it, render it and copy it into tokens yourself.

---

## 7. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 - DO NOT USE: "FAPI" by marketing.
http.oauth2AuthorizationServer(Customizer.withDefaults());   // 5-min codes, non-PAR accepted, RS256, aud list, no iss
// consent page renders authorizationDetails.creditorName; payments API checks hasAuthority("SCOPE_payments")
```

```java
// L7 - Spring Authorization Server 7.1.2 hardened toward FAPI 2.0 (every hook below is public API;
//      RequireParFilter, IssAddingAuthorizationResponseHandler, JtiStore and RequireDpopOnRefresh are your classes).
@Bean
SecurityFilterChain as(HttpSecurity http, RegisteredClientRepository clients, OAuth2AuthorizationService authorizations,
                       JwtClientAssertionDecoderFactory fapiAssertions) throws Exception {
    http.oauth2AuthorizationServer(as -> as
        .pushedAuthorizationRequestEndpoint(Customizer.withDefaults())
        .authorizationEndpoint(a -> a
            .authorizationResponseHandler(new IssAddingAuthorizationResponseHandler(ISSUER)))   // RFC 9207 iss
        .clientAuthentication(c -> c.authenticationProviders(ps -> ps.forEach(p -> {
            if (p instanceof JwtClientAssertionAuthenticationProvider j) {
                j.setJwtDecoderFactory(fapiAssertions);                                         // aud == issuer, jti once
            }
        })))
        .tokenEndpoint(t -> t.authenticationProviders(ps -> ps.replaceAll(p ->
            p instanceof OAuth2RefreshTokenAuthenticationProvider ? new RequireDpopOnRefresh(p, authorizations) : p))));
    http.addFilterBefore(new RequireParFilter(clients), AbstractPreAuthenticatedProcessingFilter.class); // FAPI: no PAR -> 400
    return http.build();
}

@Bean
JwtClientAssertionDecoderFactory fapiAssertions(JtiStore jtiStore) {
    JwtClientAssertionDecoderFactory f = new JwtClientAssertionDecoderFactory();
    f.setJwtValidatorFactory(client -> new DelegatingOAuth2TokenValidator<>(
        new JwtClaimValidator<String>("iss", client.getClientId()::equals),
        new JwtClaimValidator<String>("sub", client.getClientId()::equals),
        new JwtClaimValidator<List<String>>("aud", aud -> aud.size() == 1 && aud.get(0).equals(ISSUER)), // rfc7523bis: sole value
        new JwtClaimValidator<Object>("exp", Objects::nonNull),
        new JwtTimestampValidator(Duration.ofSeconds(10)),
        jwt -> jtiStore.firstUse(jwt.getId(), jwt.getExpiresAt())                            // OIDC Core 9: used once
            ? OAuth2TokenValidatorResult.success()
            : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_client", "assertion replayed", null))));
    return f;
}
// ⚠ a JWT "aud" given as one string is parsed to a one-element list; check the raw claim type too if "as a string, not
// an array" (FAPI 2.0 §5.3.2.1) must be enforced literally.

@Bean
OAuth2TokenCustomizer<JwtEncodingContext> fapiJwts() {
    return ctx -> {
        ctx.getJwsHeader().algorithm(SignatureAlgorithm.ES256);                // FAPI: PS256 / ES256 / EdDSA only
        Object details = ctx.getAuthorization() == null ? null
            : ctx.getAuthorization().getAttribute("authorization_details");    // captured and validated at PAR
        if (details != null && OAuth2TokenType.ACCESS_TOKEN.equals(ctx.getTokenType())) {
            ctx.getClaims().claim("authorization_details", details);          // RFC 9396 section 9.1
        }
    };
}
// RegisteredClient: TokenSettings.builder().authorizationCodeTimeToLive(Duration.ofSeconds(60))
//                     .idTokenSignatureAlgorithm(SignatureAlgorithm.ES256).build()
//                   ClientSettings: requireProofKey(true), tokenEndpointAuthenticationSigningAlgorithm(ES256 | PS256)
```

```java
// L7 - payments resource server: the authorization is the granted details, consumed once.
@PostMapping("/payments")
ResponseEntity<?> pay(@AuthenticationPrincipal Jwt token, @RequestBody PaymentInstruction p) {
    PaymentDetails granted = PaymentDetails.from(token.getClaim("authorization_details"));   // type payment_initiation
    if (!granted.matches(p.amount(), p.currency(), p.creditorIban()) || !grants.consume(granted.identifier())) {
        return ResponseEntity.status(403).header("WWW-Authenticate",
            "DPoP error=\"insufficient_scope\"").build();                 // RFC 6750 section 3.1
    }
    return ResponseEntity.status(201).body(payments.execute(p));
}
```

| Concern | L5 | L7 |
|---|---|---|
| Request transport | browser query string | PAR, authenticated; front channel = `client_id` + `request_uri` |
| `request_uri` | reusable, guessable, unbound | 256-bit, ≤ 60–90 s, one-time at authorization, client-bound |
| Non-PAR requests | accepted | rejected (FAPI §5.3.2.2) |
| Client authentication | secret, or assertion with any `aud` | `private_key_jwt` with `aud` = issuer (sole), `jti` once, or mTLS |
| Consent | display names | rendered from validated `authorization_details`, including identifiers |
| Token | scope `payments` | DPoP-bound, `authorization_details` as granted |
| RS | `hasAuthority("SCOPE_payments")` | match + consume the granted details |
| Response | `code` + `state` | `code` + `iss` (+ JARM under Message Signing) |
| Codes | 5 min | ≤ 60 s, single use |
| Algorithms | RS256 | ES256 / PS256 |

---

## 8. Real-world attack vectors & mitigations

### A1 · Authorization request tampering in the front channel

**Attack.** A man-in-the-browser, malicious extension or compromised app rewrites the IBAN in the authorization URL. The consent screen shows the unchanged display name (L30 L5 row 1).
**Wire signature.** Authorization requests whose `authorization_details` differ from what the client recorded server-side. Only the client can see this, which is why PAR exists.
**Root cause.** Integrity-sensitive parameters in a channel the attacker controls.
**Mitigation.** PAR with client authentication. The consent screen renders the identifiers (IBAN), not just names.
**Detection.** Clients compare the granted `authorization_details` in the token response to what they pushed.

### A2 · Request injection through an unauthenticated PAR endpoint

**Attack.** The attacker pushes its own request with the victim client's `client_id` and its own creditor, then sends the user the resulting `request_uri` link (L30 L6 row 2).
**Wire signature.** PAR requests without client authentication, or from unexpected networks.
**Root cause.** PAR treated as a convenience, not as an authenticated endpoint.
**Mitigation.** Reject PAR without client authentication (FAPI §5.3.2.2). Bind `request_uri` to the authenticated client.
**Detection.** Monitor PAR auth failures, and consent abandonment spikes on specific clients.

### A3 · `request_uri` replay, expiry and swapping

**Attack.**
- A `request_uri` leaks through browser history, `Referer` or link scanners.
- It is reused (L30 L6 rows 3–5): later, with another client, or after the user has left.

**Wire signature.** The same `request_uri` presented twice, or after `expires_in`, or with a different `client_id`.
**Root cause.** Reference tokens without lifecycle rules.
**Mitigation.** One-time use at the point of authorization, `expires_in` under 600 s, client binding, 256-bit randomness. Spring Authorization Server 7.1.2 does all four (L31).
**Detection.** Count rejected `request_uri` values by reason.

### A4 · RAR without RS enforcement

**Attack.** A client, or an attacker with the client's sender-constrained token and key (malware), calls the payment API with a larger amount or another creditor. The RS checks only `scope` (L30 RS section).
**Wire signature.** API requests whose parameters differ from the token's `authorization_details`.
**Root cause.** Consent captured at the AS but not enforced where the money moves.
**Mitigation.** The RS matches every request against the granted details and consumes single-use grants. It returns 403 with `error="insufficient_scope"` (RFC 6750 §3.1) otherwise.
**Detection.** Mismatch counters per client; they should be zero.

### A5 · Client-assertion audience injection and replay

**Attack.** A malicious AS collects `private_key_jwt` assertions whose `aud` is the honest AS's token or PAR endpoint URL, and replays them at the honest AS. Alternatively, a captured assertion is replayed within its `exp`. Spring Authorization Server 7.1.2 accepts both (L31).
**Wire signature.** Assertions with endpoint-URL or array audiences, and repeated `jti` values.
**Root cause.** An AS-side audience list wider than the issuer, and no `jti` store (CVE-2025-27370/27371 class).
**Mitigation.**
- `aud` = issuer as the sole value (rfc7523bis §4; FAPI §5.3.2.1).
- A `jti` store until `exp`.
- A short `exp`.
- `typ` `client-authentication+jwt` from clients.

**Detection.** Log the `aud` form and `jti` reuse per client.

### A6 · Mix-up in the authorization response

**Attack.** A client using several ASs receives a code from the honest AS but is tricked into sending it to the attacker's token endpoint (Folder 02 file 02).
**Wire signature.** Authorization responses without `iss`, or with an unexpected `iss`.
**Root cause.** The response doesn't identify its issuer. Spring Authorization Server 7.1.2 sends only `code` and `state` [D].
**Mitigation.** The AS returns `iss` (RFC 9207, FAPI §5.3.2.2) through a custom `authorizationResponseHandler`. Clients check it, or use JARM under Message Signing.
**Detection.** Client-side `iss` mismatch errors.

### A7 · Long-lived and reusable authorization codes

**Attack.** A code leaked through logs or `Referer` is redeemed minutes later. With a 5-minute default (L31) the window is five times FAPI's.
**Wire signature.** Code redemption long after issuance; second redemption attempts.
**Root cause.** Default lifetimes.
**Mitigation.** `authorizationCodeTimeToLive` ≤ 60 s, single use (with token revocation on reuse), PKCE, and `dpop_jkt` where DPoP is used.
**Detection.** A histogram of issuance-to-redemption time; reuse alerts.

---

## 9. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · Why does FAPI 2.0 replace JAR with PAR?</b></summary>

**Initial Prompt.** Your bank already signs request objects (FAPI 1.0 Advanced).

**L5 Textbook Answer.** "They do the same thing; PAR is just newer."

**How an Attacker Bypasses L5.**
- **JAR in the front channel** gives integrity, but not client authentication at request time. Any party with a signed request object can replay it within its lifetime.
- **Confidentiality is lost:** the browser and every extension can read the payment details.
- **Size breaks:** large RAR objects exceed URL limits.

**L7 Principal Defense.**
- **PAR gives integrity and confidentiality** (TLS, back channel) **and client authentication**, and puts an opaque one-time reference in the front channel.
- **JAR inside PAR** only when non-repudiation of the request is required (Message Signing).
- **FAPI 2.0 §5.5 makes the trade explicit.**

</details>

<details><summary><b>Q2 · Design consent for a EUR 123.50 payment so the user can't be tricked.</b></summary>

**Initial Prompt.** Open-banking payment initiation.

**L5 Textbook Answer.** "Show 'Pay EUR 123.50 to Merchant A' and an Approve button."

**How an Attacker Bypasses L5.** The attacker changes the IBAN and leaves `creditorName`. The screen is identical, and the money goes elsewhere (L30 L5 row 1).

**L7 Principal Defense.**
- **PAR with client authentication,** so the browser can't change the request.
- **Consent rendered from validated `authorization_details`:** amount, currency, creditor name **and IBAN** (masked, e.g. DE02…8603), and the debtor account.
- **IBAN checksum and creditor policy** at PAR (`invalid_authorization_details`).
- **A token that carries the granted details,** an RS that matches and consumes them, and strong customer authentication bound to the details (dynamic linking).

</details>

<details><summary><b>Q3 · "We implemented PAR; are we FAPI 2.0 compliant?"</b></summary>

**Initial Prompt.** Spring Authorization Server, default configuration plus `pushedAuthorizationRequestEndpoint`.

**L5 Textbook Answer.** "Yes, PAR plus PKCE is FAPI 2.0."

**How an Attacker Bypasses L5.** L31 measures 3 of 10 requirements met by the defaults:
- **non-PAR requests are still served** (so A1 still works);
- codes live 5 min;
- assertions with endpoint audiences or replayed `jti` are accepted;
- there is no `iss`;
- DPoP is optional;
- JWTs are RS256.

**L7 Principal Defense.**
- **Build the conformance matrix from the profile text** (L31's table) and close every row with public hooks (§7).
- **Run the OpenID FAPI 2.0 conformance suite in CI.**
- **Certify.**

</details>

<details><summary><b>Q4 · Why does FAPI 2.0 prohibit refresh-token rotation when OAuth 2.1 recommends it?</b></summary>

**Initial Prompt.** A reviewer cites Folder 02's rotation advice.

**L5 Textbook Answer.** "Rotation is always safer."

**How an Attacker Bypasses L5.** Not an attack: an outage. A confidential client that fails to persist the rotated token, because of a crash or network loss, is locked out. Rotation adds nothing security-wise when the client authenticates and the tokens are sender-constrained, since a stolen refresh token is useless without the client's credentials and key.

**L7 Principal Defense.**
- **Context decides the control.**
  - **Public clients** (no client authentication): rotation with reuse detection, plus DPoP binding.
  - **Confidential FAPI clients:** no rotation (§5.3.2.1 Note 1). Use client authentication plus sender-constraining, revocation, and refresh-token lifetime policy.
- **If rotation is needed for a migration,** offer a time-limited retry with the old token, as the note requires.

</details>

<details><summary><b>Q5 · How do you validate `authorization_details` at the AS?</b></summary>

**Initial Prompt.** Multiple `type` values: payments, account access, standing orders.

**L5 Textbook Answer.** "Check the JSON parses and store it."

**How an Attacker Bypasses L5.** A negative amount, a wrong IBAN checksum, an unsupported currency or an unknown `type` reach the consent screen and the token (L30 row 6). Downstream systems interpret them differently, which leads to parser differentials and, at the extreme, payments in the wrong direction.

**L7 Principal Defense.**
- **A schema per `type`,** versioned, with strict types (decimal strings for amounts).
- **Policy:** limits per client and user, currency allow-list, IBAN mod-97, sanctioned-creditor screening.
- **Errors:** `invalid_authorization_details` with a precise description.
- **Echo back:** the validated, canonical form, which is what the token carries and the RS compares against.

</details>

<details><summary><b>Q6 · A pentest finds your AS accepts client assertions with `aud` = the token endpoint. Is that a problem?</b></summary>

**Initial Prompt.** "Our clients set `aud` to the token endpoint; it works."

**L5 Textbook Answer.** "RFC 7523 allows the token endpoint URL as audience."

**How an Attacker Bypasses L5.** That is the 2025 audience-injection class (CVE-2025-27370/27371). A malicious AS whose metadata names *your* endpoint as its token endpoint harvests assertions and replays them at you. Without a `jti` store, a captured assertion also replays (L31).

**L7 Principal Defense.**
- **Accept only the issuer as the sole `aud`** (rfc7523bis §4: "MUST reject any JWT that does not contain its issuer identifier as its sole audience value"; FAPI §5.3.2.1).
- **Keep a `jti` store until `exp`.**
- **Migrate clients first:** they send `aud` = issuer with `typ` `client-authentication+jwt`. Then tighten the AS.
- **In Spring:** `JwtClientAssertionDecoderFactory.setJwtValidatorFactory(...)` (§7).

</details>

<details><summary><b>Q7 · When do you need JARM or signed request objects in FAPI 2.0?</b></summary>

**Initial Prompt.** Legal asks for "non-repudiation of consents".

**L5 Textbook Answer.** "Turn on JARM; then everything is signed."

**How an Attacker Bypasses L5.** JARM signs the code and state. As Message Signing §6.6 notes, those are flow artefacts with limited non-repudiation value. A dispute about "did the user approve EUR 123.50 to this IBAN" isn't settled by a signed authorization code.

**L7 Principal Defense.**
- **Sign what the dispute is about:** the request object carrying `authorization_details` (JAR inside PAR), the AS's consent record, and signed API messages (HTTP message signatures).
- **Use JARM** when clients must verify the response origin beyond `iss`.
- **Keep the evidence:** signed artefacts plus the AS's audit log.

</details>

<details><summary><b>Q8 · The authorization page is preloaded by an email link scanner and PAR one-time use breaks the user's flow. Fix?</b></summary>

**Initial Prompt.** Users get "invalid request_uri" when they click a link.

**L5 Textbook Answer.** "Remove one-time use."

**How an Attacker Bypasses L5.** Without one-time use, `request_uri`s replay (L30 L6 row 3).

**L7 Principal Defense.**
- **Enforce one-time use "at the point of authorization, not at the point of loading an authorization page"** (FAPI Note 3). Spring Authorization Server 7.1.2 removes the pushed request only when it issues the code or consent (L31).
- **Keep `expires_in` long enough** for slow devices (60–300 s).
- **Use app-to-app and decoupled flows (CIBA)** where links are a poor fit.

</details>

<details><summary><b>Q9 · Where does the RS get `authorization_details` from, and what does it do with them?</b></summary>

**Initial Prompt.** The token is opaque.

**L5 Textbook Answer.** "The client sends the payment; the RS checks the token is valid."

**How an Attacker Bypasses L5.** A valid token for one payment executes any payment (L30 RS section: EUR 9,999 to another IBAN).

**L7 Principal Defense.**
- **Where the details come from:** introspection (RFC 9396 §9.2) or a JWT access token claim (§9.1).
- **Cache** keyed by token hash with a short TTL.
- **Match** every request field that the consent covered.
- **Consume** single-use details atomically with execution, using an idempotency key.
- **Return** 403 with `insufficient_scope` (RFC 6750 §3.1; RAR defines no RS error of its own).
- **Log** the details id with the payment for audit.

</details>

<details><summary><b>Q10 · Plan a FAPI 2.0 migration for an existing OAuth 2.0 bank API with 300 third parties.</b></summary>

**Initial Prompt.** Current state: front-channel requests, `client_secret_basic`, bearer tokens, scopes.

**L5 Textbook Answer.** "Announce a cut-over date."

**How an Attacker Bypasses L5.** A flag day fails, and exemptions become permanent. Every un-migrated client is a bearer-token, request-tampering hole.

**L7 Principal Defense.**
1. **AS first:** PAR plus `require_pushed_authorization_requests` per client; `private_key_jwt` with `aud` = issuer; `iss`; 60 s codes; ES256/PS256.
2. **Then sender-constraining:** DPoP or mTLS per client, required per client (file 01).
3. **Then RAR** for payments, with RS enforcement.

Throughout, a per-client conformance dashboard and the OIDF conformance suite as an onboarding gate. Old flows are retired client by client, with deadlines in contracts.

</details>

---

## 10. Invariants checklist

- [ ] PAR required per client (`require_pushed_authorization_requests`); non-PAR authorization requests rejected.
- [ ] PAR endpoint requires client authentication (`private_key_jwt` with `aud` = issuer as sole value, `jti` once; or mTLS).
- [ ] `request_uri`: ≥ 128 bits random, `expires_in` < 600 s (60–300 s), one-time at authorization, bound to client.
- [ ] Front channel carries only `client_id` and `request_uri`; authorization response carries `code` + `iss`.
- [ ] Authorization codes ≤ 60 s, single use; PKCE S256; `dpop_jkt` when DPoP is used.
- [ ] `authorization_details` validated per `type` (schema + policy), rendered with identifiers, returned as granted, carried in the token.
- [ ] The RS matches each request to the granted details and consumes single-use grants.
- [ ] Request objects (Message Signing): signed, `aud` contains the issuer, `nbf` ≤ 60 min old, `exp` ≤ `nbf` + 60 min; JARM verified with the expected AS key.
- [ ] JWT algorithms PS256 / ES256 / EdDSA only; RSA ≥ 2048, EC ≥ 224 bits.
- [ ] Refresh-token rotation off for confidential sender-constrained clients (FAPI Note 1), on with reuse detection for public clients.
- [ ] OIDF FAPI 2.0 conformance suite in CI.

---

## 11. References

- FAPI 2.0 Security Profile (Final, 22 Feb 2025) — <https://openid.net/specs/fapi-security-profile-2_0-final.html>
- FAPI 2.0 Message Signing (Final, 25 Sept 2025) — <https://openid.net/specs/fapi-message-signing-2_0-final.html>
- FAPI 2.0 Attacker Model (Final) — <https://openid.net/specs/fapi-attacker-model-2_0-final.html>
- JWT Secured Authorization Response Mode for OAuth 2.0 (JARM) (Final, 9 Nov 2022) — <https://openid.net/specs/oauth-v2-jarm-final.html>
- RFC 9126 *OAuth 2.0 Pushed Authorization Requests* — <https://www.rfc-editor.org/rfc/rfc9126>
- RFC 9101 *The OAuth 2.0 Authorization Framework: JWT-Secured Authorization Request (JAR)* — <https://www.rfc-editor.org/rfc/rfc9101>
- RFC 9396 *OAuth 2.0 Rich Authorization Requests* — <https://www.rfc-editor.org/rfc/rfc9396>
- RFC 9207 *OAuth 2.0 Authorization Server Issuer Identification* — <https://www.rfc-editor.org/rfc/rfc9207>
- draft-ietf-oauth-rfc7523bis (audience requirements) — <https://datatracker.ietf.org/doc/draft-ietf-oauth-rfc7523bis/>
- Spring Authorization Server, *Protocol Endpoints* — <https://docs.spring.io/spring-authorization-server/reference/protocol-endpoints.html>
