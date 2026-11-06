# Sender-Constrained Tokens: mTLS (RFC 8705) vs DPoP (RFC 9449) Proof-of-Possession

> Folder 04 · File 01 of 03 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Next: [02 · FAPI 2.0, PAR, JAR, JARM, RAR](02-fapi-2-security-profile-par-rfc9126-jar-jarm-and-rich-authorization-requests-rar.md) · [03 · Browser SPA security and the BFF](03-browser-spa-security-rfc10017-why-localstorage-fails-and-the-bff-token-handler-pattern.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L26 `DpopLab.java` | RFC 9449's two signed example proofs verify under the key in their own header, and that key's RFC 7638 thumbprint and the access token's SHA-256 reproduce the RFC's `jkt` and `ath`. Three resource servers face 8 attacks: L5 (signature + `jkt`) accepts 7, L7 (all twelve §4.3 checks + a `jti` store) accepts only an XSS-pre-generated proof, and L7 + server nonces accepts none. The `use_dpop_nonce` round trip | RFC 9449 Figures 2, 13, 14 and §6.1 (fixture) |
| L27 `SpringDpopLab.java` | Spring Security 7.1.2's real `DPoPProofJwtDecoderFactory` verifies the RFC's proofs at the RFC's own clock and decides 14 variants. Three divergences: no `htu` normalization, RS256 accepted and EdDSA rejected (both against FAPI 2.0). The replay cache refuses the **1,001st** legitimate proof from one key within its 30 s window. Per-node caches allow cross-node replay. An algorithm-policy validator closes the FAPI gap | RFC 9449 §4.3; FAPI 2.0 §5.4.1; spring-security 7.1.2 |
| L28 `MtlsBindingLab.java` | Real mutual TLS 1.3 on 127.0.0.1 with a BouncyCastle-issued CA. A token bound to `x5t#S256` passes for its owner and fails for another client of the same CA, and with no certificate it fails closed, all through Spring's real `X509CertificateThumbprintValidator`. A forwarded-certificate header trusted from anyone is defeated by a copied **public** certificate; trusting it only on the load balancer's own mTLS connection is not. Measured: handshake vs DPoP proof cost | RFC 8705 §3; spring-security 7.1.2 |
| L29 `SasDpopRefreshLab.java` | Spring Authorization Server 7.1.2's real `OAuth2RefreshTokenAuthenticationProvider`. A public client's DPoP-bound refresh token presented **without any DPoP header** mints a plain **Bearer** token, so the binding RFC 9449 §5 says "MUST be validated" is skipped. A confidential client can likewise drop out of sender-constraining. A provider decorator fixes both | RFC 9449 §5; FAPI 2.0 §5.3.2.1 |

**Verification.** All four listings are compiled with Folders 01–04 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1, against SHA-1-verified jars:
- spring-security 7.1.2 (jose, resource-server, authorization-server, config);
- Nimbus 10.9.1;
- BouncyCastle bcprov/bcpkix/bcutil 1.86.

The gate re-runs L26, L27, L28 and L29 and requires the output byte-identical. The benchmark block is labelled measured and re-run in quick mode.

Spring behaviour marked [D] was read from the 7.1.2 `-sources.jar`s (`DPoPProofJwtDecoderFactory`, `DPoPProofReplayValidator`, `DPoPAuthenticationProvider`, `BearerTokenAuthenticationFilter`, `OAuth2ResourceServerConfigurer.DPoPConfigurer`, `X509CertificateThumbprintValidator`, `DPoPProofVerifier`, `OAuth2RefreshTokenAuthenticationProvider`, `DefaultOAuth2TokenCustomizers`). RFC 9449 and 8705 and the FAPI 2.0 Security Profile (Final, 22 Feb 2025) are in [`fixtures/`](fixtures/).

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

A bearer token is a password with an expiry date. Anyone who reads it, from a log, a proxy, a crash dump, a compromised CDN or XSS, can use it until it expires. **Sender-constraining** turns the token into half of a credential: the other half is a private key the client proves it holds on every use.
- **mTLS** proves the key in the TLS handshake (RFC 8705).
- **DPoP** proves it in a signed JWT per HTTP request (RFC 9449).

FAPI 2.0 makes one of the two mandatory: the AS "shall only issue sender-constrained access tokens" [D: FAPI 2.0 §5.3.2.1].

Results:
- **[M] DPoP's value is in the checks, not the signature (L26).** An RS that verifies the proof's signature and `jkt` but nothing else accepts 7 of 8 attacks:
  - replay;
  - method and URL swap;
  - Bearer downgrade;
  - token-endpoint proofs reused at the API;
  - stale proofs;
  - leaked private keys.
  
  All twelve RFC 9449 §4.3 checks plus a `jti` store stop all but one. **XSS pre-generation** (proofs signed now, dated an hour ahead) is stopped only by **server-provided nonces**.
- **[M] Spring Security 7.1.2's DPoP verifier is solid but has edges (L27):**
  - it rejects replay, `htm`/`htu`/`ath`/`jkt` mismatches, stale `iat`, wrong `typ` and private JWKs;
  - it does not normalize `htu`, which causes false rejections behind proxies and with port and case variants;
  - it accepts RS256 and rejects EdDSA, the opposite of FAPI 2.0 §5.4.1;
  - its default replay cache refuses a single client key's 1,001st proof within the 30-second window, about **33 requests/s per key**, with "jti claim is invalid or unable to cache";
  - per-node caches let a captured proof be replayed once per node.
  
  The verifier factory is replaceable, so all of this is fixable (§6).
- **[M] mTLS binding is only as good as the place the certificate is read from (L28).** Container-terminated mTLS fails closed. A forwarded `X-Client-Cert` header trusted from any source is beaten by a copy of the victim's *public* certificate.
- **[M] Spring Authorization Server 7.1.2 has a DPoP downgrade at the token endpoint (L29).** A copied DPoP-bound refresh token of a public client, sent with **no DPoP header**, returns `token_type=Bearer` with no `cnf`. The binding check runs only "if a proof is available". A 40-line provider decorator restores RFC 9449 §5 and FAPI 2.0's "only sender-constrained". [D] Related gaps in 7.1.2:
  - no `dpop_jkt` (RFC 9449 §10 authorization-code binding), which FAPI 2.0 requires when DPoP is used;
  - no per-client "require DPoP" setting;
  - no DPoP support in the reactive (WebFlux) resource server.
- **[M] Cost (L28 bench):** a full TLS 1.3 mutual handshake costs about 13 ms on loopback, and an ES256 DPoP proof about 0.7 ms to create and verify. With connection reuse, neither matters next to API latency [E].

---

## 1. First principles: what "sender-constrained" means

```text
  BEARER                          mTLS-BOUND (RFC 8705)                    DPoP-BOUND (RFC 9449)
  ------                          ---------------------                    ---------------------
  token = capability              token.cnf = { x5t#S256: SHA-256(cert) }  token.cnf = { jkt: SHA-256(JWK thumbprint) }
                                  proof   = TLS CertificateVerify          proof   = per-request JWS (DPoP header)
                                            (signs the handshake)                    signs htm, htu, iat, jti, ath[, nonce]
  who can use a leaked token?     only a party holding the cert's key,     only a party holding the JWK's private key,
  anyone, until exp               on a TLS connection it terminates        and only for that method+URL, within seconds
  binding checked where?          the TLS layer that saw the handshake     application layer, any hop that sees the request
  breaks when...                  TLS terminates before the RS             proofs are replayable (no jti store/nonce)
                                  (LB, CDN, service mesh)                  or the key is usable by attacker code (XSS)
```

Threat model, using the FAPI 2.0 attacker model [D: FAPI 2.0 Attacker Model §7]:
- **A1, the web attacker.** Sending a stolen token is its whole capability.
- **A3a**, who reads authorization requests.
- **A5, the attacker who "can read requests sent to the resource server after they have been processed … for example because the attacker can read TLS intercepting proxy logs"**: it holds the access token *and* every DPoP proof the client sent.

Sender-constraining defeats A1 and A5 for the access token. A5 is also why DPoP needs single-use proofs (`jti`) and short windows: A5 sees the proofs too.

What sender-constraining does **not** defeat [E]:
- an attacker running code *inside* the client: XSS in a SPA, or malware on a device. Such an attacker uses the key without extracting it, which is why §3.4's nonces and file 03's BFF exist;
- a compromised AS;
- an RS that never checks the binding. That is the most common failure, and it is the subject of most of this file.

---

## 2. mTLS: RFC 8705 in two parts

RFC 8705 defines two independent things:
- **Mutual-TLS client authentication** (§2):
  - `tls_client_auth`: a PKI-issued certificate, matched by subject DN or SAN registered for the client;
  - `self_signed_tls_client_auth`: a self-signed certificate whose key is in the client's registered JWK Set.
- **Certificate-bound access tokens** (§3). The AS puts `cnf.x5t#S256` = base64url(SHA-256(DER certificate)) into the token. The RS accepts it only on a TLS connection whose client certificate has that thumbprint.

```http
POST /token HTTP/1.1
Host: mtls.as.bank.example
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&code=SplxlOBeZQQYbYS6WxSbIA&client_id=fintech-a&redirect_uri=https%3A%2F%2Ffintech-a.example%2Fcb&code_verifier=bEaL42izcC-o-xBk0K2vuJ6U-y1p9r_wW2dFWIWgjz-
```

The client certificate travels in the TLS handshake, not in the HTTP message. That is why the request above looks like an unauthenticated one: the authentication happened a layer below.

```json
{"iss": "https://as.bank.example", "sub": "alice", "aud": "https://api.bank.example", "client_id": "fintech-a",
 "exp": 1767226200, "iat": 1767225900, "jti": "mtls-at-1", "scope": "accounts",
 "cnf": {"x5t#S256": "bwcK0esc3ACC3DB2Y5_lESsXE8o9ltc05O89jdN-dg2"}}
```

That `x5t#S256` value is the RFC 8705 §3.1 example thumbprint, which RFC 8705 gives without its certificate [D].
- **`mtls_endpoint_aliases`** (§5) lets an AS publish separate mTLS hostnames for its endpoints, so browser-facing endpoints never request a client certificate. FAPI 2.0 requires clients that use mTLS to honour them [D].
- **Certificate rotation** ⚠. Tokens bound to the old certificate stop working the moment the client switches. Clients must refresh, or obtain new tokens, after rotating, and must keep the old certificate available until outstanding tokens expire [E].

### 2.1 Where mTLS breaks: TLS termination

```text
   client --TLS(client cert A)--> [ LB / CDN / ingress ] --plain HTTP or new TLS--> app (RS)
                                     terminates TLS:            the app never sees cert A
                                     forwards "X-Client-Cert: <A>"   unless the LB tells it

   L5: app trusts X-Client-Cert from ANY request       -> attacker sends a copy of A's (public!) cert
   L7: app trusts it ONLY on the LB's own mTLS channel -> header is the LB's statement; LB strips inbound copies
       or: terminate client TLS at the app/sidecar (service mesh with SPIFFE, Folder 05)
```

Certificates are public. They are sent in clear in TLS 1.2 handshakes, appear in logs and are handed to partners. A header that carries "the client's certificate" is therefore an assertion, not a proof, and only an authenticated hop may make it. L28 cases 4–7 show both the L5 and the L7 behaviour.

---

## 3. DPoP: RFC 9449 on the wire

### 3.1 The proof

The proof is a JWS whose header carries the public key, and whose payload binds it to this one HTTP request [D: §4.2]. Figure 14 of the RFC shows the decoded proof that L26 verifies:

```json
{"typ": "dpop+jwt", "alg": "ES256",
 "jwk": {"kty": "EC", "x": "l8tFrhx-34tV3hRICRDY9zCkDlpBhF42UQUfWVAWBFs", "y": "9VE4jf_Ok_o64zbTTlcuNJajHmt6v9TDVrU0CdvGRDA", "crv": "P-256"}}
```

```json
{"jti": "e1j3V_bKic8-LAEB", "htm": "GET", "htu": "https://resource.example.org/protectedresource",
 "iat": 1562262618, "ath": "fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo"}
```

- `jti` must carry "at least 96 bits of pseudorandom data" or be a UUIDv4.
- `htm` and `htu` bind the method and the URI, ignoring query and fragment.
- `ath` = base64url(SHA-256(ASCII access token)), and is present whenever an access token is presented.
- `nonce` is present when the server demanded one.

### 3.2 Token request, response, and resource request

```http
POST /token HTTP/1.1
Host: server.example.com
Content-Type: application/x-www-form-urlencoded
DPoP: eyJ0eXAiOiJkcG9wK2p3dCIsImFsZyI6IkVTMjU2IiwiandrIjp7Imt0eSI6IkVDIiwieCI6Imw4dEZyaHgtMzR0VjNoUklDUkRZOXpDa0RscEJoRjQyVVFVZldWQVdCRnMiLCJ5IjoiOVZFNGpmX09rX282NHpiVFRsY3VOSmFqSG10NnY5VERWclUwQ2R2R1JEQSIsImNydiI6IlAtMjU2In19.eyJqdGkiOiItQndDM0VTYzZhY2MybFRjIiwiaHRtIjoiUE9TVCIsImh0dSI6Imh0dHBzOi8vc2VydmVyLmV4YW1wbGUuY29tL3Rva2VuIiwiaWF0IjoxNTYyMjYyNjE2fQ.2-GxA6T8lP4vfrg8v-FdWP0A0zdrj8igiMLvqRMUvwnQg4PtFLbdLXiOSsX0x7NVY-FNyJK70nfbV37xRZT3Lg

grant_type=authorization_code&client_id=s6BhdRkqt&code=SplxlOBeZQQYbYS6WxSbIA&redirect_uri=https%3A%2F%2Fclient%2Eexample%2Ecom%2Fcb&code_verifier=bEaL42izcC-o-xBk0K2vuJ6U-y1p9r_wW2dFWIWgjz-
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store

{"access_token": "Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU", "token_type": "DPoP", "expires_in": 2677, "refresh_token": "Q..Zkm29lexi8VnWg2zPW1x-tgGad0Ibc3s3EwM_Ni4-g"}
```

```http
GET /protectedresource HTTP/1.1
Host: resource.example.org
Authorization: DPoP Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU
DPoP: eyJ0eXAiOiJkcG9wK2p3dCIsImFsZyI6IkVTMjU2IiwiandrIjp7Imt0eSI6IkVDIiwieCI6Imw4dEZyaHgtMzR0VjNoUklDUkRZOXpDa0RscEJoRjQyVVFVZldWQVdCRnMiLCJ5IjoiOVZFNGpmX09rX282NHpiVFRsY3VOSmFqSG10NnY5VERWclUwQ2R2R1JEQSIsImNydiI6IlAtMjU2In19.eyJqdGkiOiJlMWozVl9iS2ljOC1MQUVCIiwiaHRtIjoiR0VUIiwiaHR1IjoiaHR0cHM6Ly9yZXNvdXJjZS5leGFtcGxlLm9yZy9wcm90ZWN0ZWRyZXNvdXJjZSIsImlhdCI6MTU2MjI2MjYxOCwiYXRoIjoiZlVIeU8ycjJaM0RaNTNFc05yV0JiMHhXWG9hTnk1OUlpS0NBcWtzbVFFbyJ9.2oW9RP35yRqzhrtNP86L-Ey71EOptxRimPPToA1plemAgR6pxHF8y6-yqyVnmcw6Fy1dqd-jfxSYoMxhAJpLjA
```

These are RFC 9449 Figures 5, 6 and 13, with the RFC 8792 line wrapping removed [D]. The access token's `cnf` is `{"jkt": "0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I"}` (§6.1), which is the RFC 7638 thumbprint of the proof's `jwk`, as L26 verifies.

### 3.3 The twelve checks (RFC 9449 §4.3)

1. exactly one `DPoP` header;
2. a single well-formed JWT;
3. all required claims present;
4. `typ` = `dpop+jwt`;
5. `alg` asymmetric, registered and allowed by policy (not `none`, not a MAC);
6. the signature verifies with the header `jwk`;
7. the `jwk` has no private key;
8. `htm` = the request method;
9. `htu` = the request URI, ignoring query and fragment, after RFC 3986 normalization (SHOULD);
10. `nonce` = the server-provided nonce, if one was provided;
11. `iat` (or the nonce's timestamp) within the window;
12. with an access token: `ath` = its hash, and the token's `cnf.jkt` = the proof key's thumbprint.

Not in the list but required in practice [E]: a **`jti` store**. Without one, check 11's window is a replay window. L26 case 1 replays a proof from a log inside the window.

### 3.4 Server nonces and the pre-generation attack

An attacker with code execution in the client (XSS) can't export a non-extractable WebCrypto key, but **can use it**. It signs proofs with `iat` in the future and exfiltrates them. L26 case 7 does this an hour ahead: every §4.3 check passes when the proof is finally used, from the attacker's machine. **Server-provided nonces** (§8 for the AS, §9 for the RS) make proofs depend on a value the attacker can't predict.

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: DPoP error="use_dpop_nonce", error_description="Resource server requires nonce in DPoP proof"
DPoP-Nonce: eyJ7S_zG.eyJH0-Z.HX4w-7v
```

That is the RFC's own example of the challenge [D: §9]. The client retries with `"nonce": "<value>"` in a fresh proof (L26 §3: one extra round trip). The nonce can be a MAC over a time slot, so the server keeps no state [E].

### 3.5 Binding more than the access token

- **Refresh tokens of public clients** "MUST be bound to the respective public key", and "such a client MUST present a DPoP proof for the same key … each time that refresh token is used" [D: §5]. Confidential clients' refresh tokens are bound to client authentication instead.
- **Authorization code binding** (`dpop_jkt`, §10). The client sends the thumbprint in the (pushed) authorization request, and the AS refuses to redeem the code with a different key. This stops an attacker who injects a stolen code from redeeming it under their own key. FAPI 2.0 requires ASs to support it when using DPoP [D: §5.3.2.1].
- **Bearer downgrade** (§7.2). An RS supporting both schemes must reject a DPoP-bound token presented as `Authorization: Bearer`. Otherwise the binding is optional for the attacker.

```mermaid
sequenceDiagram
    autonumber
    participant C as Client (key V)
    participant AS as Authorization server
    participant RS as Resource server
    C->>AS: PAR (dpop_jkt = thumb(V)) ... authorization code
    C->>AS: POST /token + DPoP proof(V, htm=POST, htu=/token)
    AS-->>C: 400 use_dpop_nonce, DPoP-Nonce: n1
    C->>AS: POST /token + DPoP proof(V, nonce=n1)
    AS->>AS: code bound to thumb(V)? yes -> issue AT with cnf.jkt = thumb(V), RT bound to V (public client)
    AS-->>C: token_type=DPoP
    C->>RS: Authorization: DPoP AT + proof(V, htm, htu, ath=hash(AT), nonce)
    RS->>RS: 12 checks + jti store; cnf.jkt == thumb(V)
    RS-->>C: 200
    Note over RS: Authorization: Bearer AT  -> 401 (token is DPoP-bound)
```

---

## 4. L26: DPoP from first principles

<!-- listing:DpopLab.java -->
```java
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * L26 - DPoP (RFC 9449) from first principles.
 *
 * <ul>
 *   <li>Oracles from the RFC text: the two signed ES256 proofs (Figures 2 and 13) verify under the JWK in their own
 *       header, that JWK's RFC 7638 thumbprint is the RFC's {@code jkt}, and SHA-256 of the example access token is
 *       the RFC's {@code ath};</li>
 *   <li>three resource servers - L5 (signature + jkt only), L7 (all twelve section 4.3 checks + a jti store) and
 *       L7 with server-provided nonces (section 8/9) - against eight attacks, on a fixed clock;</li>
 *   <li>the use_dpop_nonce challenge on the wire.</li>
 * </ul>
 */
public final class DpopLab {
    static final long NOW = 1_767_225_600L; // 2026-01-01T00:00:00Z, fixed so the run is reproducible
    static final Set<String> PRIVATE_MEMBERS = Set.of("d", "p", "q", "dp", "dq", "qi", "k", "oth");
    static int jtiCounter;

    // ------------------------------------------------------------------ RFC 8792 "\" unwrapping

    /** The DPoP header value printed (wrapped with "\") last before {@code caption}. */
    static String wrappedProofBefore(String rfc, String caption) {
        int cap = rfc.indexOf(caption);
        int at = rfc.lastIndexOf("DPoP: eyJ", cap);
        StringBuilder sb = new StringBuilder();
        for (String line : rfc.substring(at + "DPoP: ".length(), cap).split("\n")) {
            String t = line.trim();
            if (t.isEmpty()) {
                break;
            }
            sb.append(t.endsWith("\\") ? t.substring(0, t.length() - 1) : t);
        }
        return sb.toString();
    }

    // ------------------------------------------------------------------ proofs

    static Map<String, Object> publicJwk(Jose.Jwk k, boolean leakPrivate) {
        Map<String, Object> j = new LinkedHashMap<>();
        for (Map.Entry<String, Object> e : k.json().entrySet()) {
            if (!e.getKey().equals("kid") && (leakPrivate || !PRIVATE_MEMBERS.contains(e.getKey()))) {
                j.put(e.getKey(), e.getValue());
            }
        }
        return j;
    }

    static String proof(Jose.Jwk k, String htm, String htu, long iat, String ath, String nonce, boolean leakPrivate) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("typ", "dpop+jwt");
        h.put("alg", "ES256");
        h.put("jwk", publicJwk(k, leakPrivate));
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("jti", "jti-" + (++jtiCounter)); // production: >= 96 bits of randomness (RFC 9449 section 4.2)
        c.put("htm", htm);
        c.put("htu", htu);
        c.put("iat", iat);
        if (ath != null) {
            c.put("ath", ath);
        }
        if (nonce != null) {
            c.put("nonce", nonce);
        }
        return Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), k);
    }

    static String ath(String accessToken) {
        return KbSupport.b64u(Jose.sha256(accessToken.getBytes(StandardCharsets.US_ASCII)));
    }

    /** RFC 3986 syntax- and scheme-based normalization, query and fragment dropped (RFC 9449 section 4.3 step 9). */
    static String normalizeHtu(String u) {
        URI x = URI.create(u).normalize();
        String scheme = x.getScheme().toLowerCase(java.util.Locale.ROOT);
        int port = x.getPort();
        boolean defaultPort = port == -1 || scheme.equals("https") && port == 443 || scheme.equals("http") && port == 80;
        String path = x.getRawPath() == null || x.getRawPath().isEmpty() ? "/" : x.getRawPath();
        return scheme + "://" + x.getHost().toLowerCase(java.util.Locale.ROOT) + (defaultPort ? "" : ":" + port) + path;
    }

    // ------------------------------------------------------------------ resource servers

    record Req(String label, long at, String method, String uri, String scheme, String token, String proof, boolean attack) {
    }

    static final class Rs {
        final String name;
        final boolean l7;
        final boolean requireNonce;
        final Map<String, String> tokenJkt;              // what the RS learns from the JWT / introspection: cnf.jkt
        final Map<String, Long> seenJti = new HashMap<>(); // jkt|jti -> expiry
        static final long PAST = 60;                       // accept proofs up to 60 s old
        static final long FUTURE = 10;                     // ... and up to 10 s in the future (FAPI 2.0 section 5.3.2.1)

        Rs(String name, boolean l7, boolean requireNonce, Map<String, String> tokenJkt) {
            this.name = name;
            this.l7 = l7;
            this.requireNonce = requireNonce;
            this.tokenJkt = tokenJkt;
        }

        /** The nonce the RS hands out; rotates every 300 s and is a MAC of the epoch in a real server. */
        static String nonceAt(long t) {
            return "n-" + (t / 300);
        }

        String handle(Req r) {
            String jkt = tokenJkt.get(r.token());
            if (jkt == null) {
                return "401 invalid_token";
            }
            if (r.scheme().equals("Bearer")) {
                return l7 ? "401 invalid_token (DPoP-bound token presented as Bearer)" : "200 (bearer accepted)";
            }
            Jose.Parts p;
            try {
                p = Jose.parse(r.proof());
            } catch (RuntimeException e) {
                return "401 invalid_dpop_proof (malformed)";
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> jwkJson = (Map<String, Object>) p.header().get("jwk");
            Jose.Jwk jwk = Jose.Jwk.parse(jwkJson);
            String alg = String.valueOf(p.header().get("alg"));
            Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
            if (!jwk.fits(alg) || !Jose.rawVerify(alg, jwk, p.signingInput(), p.sig())) {
                return "401 invalid_dpop_proof (signature)";
            }
            if (!jwk.thumbprint().equals(jkt)) {
                return "401 invalid_token (proof key != cnf.jkt)";
            }
            if (!l7) {
                return "200";
            }
            if (!"dpop+jwt".equals(p.header().get("typ"))) {
                return "401 invalid_dpop_proof (typ)";
            }
            if (!List.of("ES256", "PS256", "Ed25519", "EdDSA").contains(alg)) {
                return "401 invalid_dpop_proof (alg not allowed by policy)";
            }
            if (jwkJson.keySet().stream().anyMatch(PRIVATE_MEMBERS::contains)) {
                return "401 invalid_dpop_proof (jwk contains a private key)";
            }
            if (!r.method().equals(c.get("htm"))) {
                return "401 invalid_dpop_proof (htm " + c.get("htm") + " != " + r.method() + ")";
            }
            if (!normalizeHtu(r.uri()).equals(normalizeHtu(String.valueOf(c.get("htu"))))) {
                return "401 invalid_dpop_proof (htu)";
            }
            if (!ath(r.token()).equals(c.get("ath"))) {
                return "401 invalid_dpop_proof (ath missing or wrong)";
            }
            long iat = ((Number) c.get("iat")).longValue();
            if (iat < r.at() - PAST || iat > r.at() + FUTURE) {
                return "401 invalid_dpop_proof (iat outside [-" + PAST + " s, +" + FUTURE + " s])";
            }
            if (requireNonce && !nonceAt(r.at()).equals(c.get("nonce"))) {
                return "401 WWW-Authenticate: DPoP error=\"use_dpop_nonce\"  DPoP-Nonce: " + nonceAt(r.at());
            }
            seenJti.values().removeIf(exp -> exp < r.at());
            if (seenJti.putIfAbsent(jkt + "|" + c.get("jti"), iat + PAST + FUTURE) != null) {
                return "401 invalid_dpop_proof (jti replayed)";
            }
            return "200";
        }
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String rfc = KbSupport.rfc(fx, "rfc9449.txt");

        KbSupport.section("RFC 9449 oracles (fixture)");
        String fig2 = wrappedProofBefore(rfc, "Figure 2: Example DPoP Header");
        String fig13 = wrappedProofBefore(rfc, "Figure 13: DPoP-Protected Resource Request");
        int verified = 0;
        String jkt = null;
        for (String compact : new String[] {fig2, fig13}) {
            Jose.Parts p = Jose.parse(compact);
            @SuppressWarnings("unchecked")
            Jose.Jwk k = Jose.Jwk.parse((Map<String, Object>) p.header().get("jwk"));
            boolean ok = Jose.rawVerify("ES256", k, p.signingInput(), p.sig());
            verified += ok ? 1 : 0;
            jkt = k.thumbprint();
            KbSupport.info("%s  typ=%s alg=%s  claims=%s  signature %s", compact == fig2 ? "Figure 2 " : "Figure 13",
                    p.header().get("typ"), p.header().get("alg"), new String(p.payload(), StandardCharsets.UTF_8), ok ? "VALID" : "INVALID");
        }
        KbSupport.check("both RFC proofs verify under the public key in their own jwk header", verified == 2);
        KbSupport.check("RFC 7638 thumbprint of that jwk = the RFC's cnf.jkt " + jkt, "0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I".equals(jkt));
        KbSupport.mustCite(rfc, "0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I", "section 6.1 jkt");
        String rfcToken = "Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU";
        KbSupport.mustCite(rfc, rfcToken, "section 7.1 access token");
        KbSupport.mustCite(rfc, "fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo", "Figure 14 ath");
        KbSupport.check("base64url(SHA-256(access token)) = Figure 14 ath " + ath(rfcToken),
                ath(rfcToken).equals("fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo")
                        && new String(Jose.parse(fig13).payload(), StandardCharsets.UTF_8).contains(ath(rfcToken)));

        KbSupport.section("Eight attacks on a DPoP-protected API (token T is bound to the victim's key V)");
        SecureRandom rng = new SecureRandom();
        Jose.Jwk victim = Jose.generate("ES256", rng);
        Jose.Jwk attacker = Jose.generate("ES256", rng);
        String token = "at-" + "Q2hlY2tpbmcgYWNjb3VudCBzY29wZQ"; // opaque; the RS learns cnf.jkt by introspection
        Map<String, String> binding = Map.of(token, victim.thumbprint());
        String api = "https://api.bank.example";
        String n0 = Rs.nonceAt(NOW);
        String legit = proof(victim, "GET", api + "/accounts", NOW, ath(token), n0, false);
        String tokenEndpointProof = proof(victim, "POST", "https://as.bank.example/token", NOW - 30, null, null, false);
        // XSS at NOW: the page's (non-extractable) key still signs for the attacker; proofs dated one hour ahead
        String pregenerated = proof(victim, "GET", api + "/accounts", NOW + 3_600, ath(token), n0, false);
        List<Req> reqs = List.of(
            new Req("0 legitimate GET /accounts", NOW, "GET", api + "/accounts", "DPoP", token, legit, false),
            new Req("1 the same proof replayed from a log", NOW + 5, "GET", api + "/accounts", "DPoP", token, legit, true),
            new Req("2 that proof replayed on POST /payments", NOW + 5, "POST", api + "/payments", "DPoP", token, legit, true),
            new Req("3 stolen T + a proof from the attacker's own key", NOW + 5, "GET", api + "/accounts", "DPoP", token,
                    proof(attacker, "GET", api + "/accounts", NOW + 5, ath(token), n0, false), true),
            new Req("4 stolen T sent as 'Authorization: Bearer'", NOW + 5, "GET", api + "/accounts", "Bearer", token, null, true),
            new Req("5 a token-endpoint proof (no ath) reused at the API", NOW + 5, "GET", api + "/accounts", "DPoP", token,
                    tokenEndpointProof, true),
            new Req("6 a captured proof replayed 10 min later", NOW + 600, "GET", api + "/accounts", "DPoP", token,
                    proof(victim, "GET", api + "/accounts", NOW, ath(token), n0, false), true),
            new Req("7 XSS-pre-generated proof used 1 h later", NOW + 3_600, "GET", api + "/accounts", "DPoP", token, pregenerated, true),
            new Req("8 htu https://API.bank.example:443/accounts, ?page=2", NOW + 6, "GET", api + "/accounts?page=2", "DPoP", token,
                    proof(victim, "GET", "https://API.bank.example:443/accounts", NOW + 6, ath(token), n0, false), false),
            new Req("9 client bug: private key 'd' inside the jwk header", NOW + 7, "GET", api + "/accounts", "DPoP", token,
                    proof(victim, "GET", api + "/accounts", NOW + 7, ath(token), n0, true), true));
        List<Rs> servers = List.of(new Rs("L5", false, false, binding), new Rs("L7", true, false, binding), new Rs("L7+nonce", true, true, binding));
        Map<String, Integer> accepted = new LinkedHashMap<>();
        Map<String, Boolean> legitOk = new LinkedHashMap<>();
        for (Rs s : servers) {
            accepted.put(s.name, 0);
            legitOk.put(s.name, true);
            KbSupport.info("--- %s", s.name);
            for (Req r : reqs) {
                String out = s.handle(r);
                boolean ok = out.startsWith("200");
                if (r.attack() && ok) {
                    accepted.merge(s.name, 1, Integer::sum);
                }
                if (!r.attack() && !ok) {
                    legitOk.put(s.name, false);
                }
                KbSupport.info("%-8s %-52s -> %s", s.name, r.label(), out);
            }
        }
        int attacks = (int) reqs.stream().filter(Req::attack).count();
        KbSupport.check("L5 (signature + jkt only) accepts " + accepted.get("L5") + " of " + attacks + " attacks; only the foreign key is stopped",
                accepted.get("L5") == attacks - 1);
        KbSupport.check("L7 (all section 4.3 checks + jti store) stops every attack except the pre-generated proof",
                accepted.get("L7") == 1 && legitOk.get("L7"));
        KbSupport.check("L7 + server nonces stops all " + attacks + " and still accepts the legitimate and the normalized-htu request",
                accepted.get("L7+nonce") == 0 && legitOk.get("L7+nonce"));

        KbSupport.section("The nonce challenge on the wire (RFC 9449 section 9)");
        Rs rs = new Rs("L7+nonce", true, true, binding);
        String stale = proof(victim, "GET", api + "/accounts", NOW + 900, ath(token), n0, false);
        KbSupport.info("GET /accounts  DPoP: <proof with nonce %s>  at t+900 s  ->  %s", n0,
                rs.handle(new Req("stale", NOW + 900, "GET", api + "/accounts", "DPoP", token, stale, false)));
        String fresh = proof(victim, "GET", api + "/accounts", NOW + 901, ath(token), Rs.nonceAt(NOW + 901), false);
        String retry = rs.handle(new Req("retry", NOW + 901, "GET", api + "/accounts", "DPoP", token, fresh, false));
        KbSupport.info("retry with nonce %s  ->  %s", Rs.nonceAt(NOW + 901), retry);
        KbSupport.check("a stale nonce costs one round trip and the retry succeeds", retry.equals("200"));
        KbSupport.verdict();
    }
}
```

<!-- output:DpopLab.java -->
```text

== RFC 9449 oracles (fixture)
  Figure 2   typ=dpop+jwt alg=ES256  claims={"jti":"-BwC3ESc6acc2lTc","htm":"POST","htu":"https://server.example.com/token","iat":1562262616}  signature VALID
  Figure 13  typ=dpop+jwt alg=ES256  claims={"jti":"e1j3V_bKic8-LAEB","htm":"GET","htu":"https://resource.example.org/protectedresource","iat":1562262618,"ath":"fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo"}  signature VALID
  [PASS] both RFC proofs verify under the public key in their own jwk header
  [PASS] RFC 7638 thumbprint of that jwk = the RFC's cnf.jkt 0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I
  [PASS] constant cited verbatim from fixture: section 6.1 jkt
  [PASS] constant cited verbatim from fixture: section 7.1 access token
  [PASS] constant cited verbatim from fixture: Figure 14 ath
  [PASS] base64url(SHA-256(access token)) = Figure 14 ath fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo

== Eight attacks on a DPoP-protected API (token T is bound to the victim's key V)
  --- L5
  L5       0 legitimate GET /accounts                           -> 200
  L5       1 the same proof replayed from a log                 -> 200
  L5       2 that proof replayed on POST /payments              -> 200
  L5       3 stolen T + a proof from the attacker's own key     -> 401 invalid_token (proof key != cnf.jkt)
  L5       4 stolen T sent as 'Authorization: Bearer'           -> 200 (bearer accepted)
  L5       5 a token-endpoint proof (no ath) reused at the API  -> 200
  L5       6 a captured proof replayed 10 min later             -> 200
  L5       7 XSS-pre-generated proof used 1 h later             -> 200
  L5       8 htu https://API.bank.example:443/accounts, ?page=2 -> 200
  L5       9 client bug: private key 'd' inside the jwk header  -> 200
  --- L7
  L7       0 legitimate GET /accounts                           -> 200
  L7       1 the same proof replayed from a log                 -> 401 invalid_dpop_proof (jti replayed)
  L7       2 that proof replayed on POST /payments              -> 401 invalid_dpop_proof (htm GET != POST)
  L7       3 stolen T + a proof from the attacker's own key     -> 401 invalid_token (proof key != cnf.jkt)
  L7       4 stolen T sent as 'Authorization: Bearer'           -> 401 invalid_token (DPoP-bound token presented as Bearer)
  L7       5 a token-endpoint proof (no ath) reused at the API  -> 401 invalid_dpop_proof (htm POST != GET)
  L7       6 a captured proof replayed 10 min later             -> 401 invalid_dpop_proof (iat outside [-60 s, +10 s])
  L7       7 XSS-pre-generated proof used 1 h later             -> 200
  L7       8 htu https://API.bank.example:443/accounts, ?page=2 -> 200
  L7       9 client bug: private key 'd' inside the jwk header  -> 401 invalid_dpop_proof (jwk contains a private key)
  --- L7+nonce
  L7+nonce 0 legitimate GET /accounts                           -> 200
  L7+nonce 1 the same proof replayed from a log                 -> 401 invalid_dpop_proof (jti replayed)
  L7+nonce 2 that proof replayed on POST /payments              -> 401 invalid_dpop_proof (htm GET != POST)
  L7+nonce 3 stolen T + a proof from the attacker's own key     -> 401 invalid_token (proof key != cnf.jkt)
  L7+nonce 4 stolen T sent as 'Authorization: Bearer'           -> 401 invalid_token (DPoP-bound token presented as Bearer)
  L7+nonce 5 a token-endpoint proof (no ath) reused at the API  -> 401 invalid_dpop_proof (htm POST != GET)
  L7+nonce 6 a captured proof replayed 10 min later             -> 401 invalid_dpop_proof (iat outside [-60 s, +10 s])
  L7+nonce 7 XSS-pre-generated proof used 1 h later             -> 401 WWW-Authenticate: DPoP error="use_dpop_nonce"  DPoP-Nonce: n-5890764
  L7+nonce 8 htu https://API.bank.example:443/accounts, ?page=2 -> 200
  L7+nonce 9 client bug: private key 'd' inside the jwk header  -> 401 invalid_dpop_proof (jwk contains a private key)
  [PASS] L5 (signature + jkt only) accepts 7 of 8 attacks; only the foreign key is stopped
  [PASS] L7 (all section 4.3 checks + jti store) stops every attack except the pre-generated proof
  [PASS] L7 + server nonces stops all 8 and still accepts the legitimate and the normalized-htu request

== The nonce challenge on the wire (RFC 9449 section 9)
  GET /accounts  DPoP: <proof with nonce n-5890752>  at t+900 s  ->  401 WWW-Authenticate: DPoP error="use_dpop_nonce"  DPoP-Nonce: n-5890755
  retry with nonce n-5890755  ->  200
  [PASS] a stale nonce costs one round trip and the retry succeeds

verdict: OK (10 checks)
```

Reading the run:
- **The foreign-key case (3) is the only one L5 stops.** That is what people think DPoP is for. Every other attack uses the *victim's own* proofs, or no proof at all, which is exactly A5's capability.
- **Case 5 matters for architects.** A proof from a token request (POST `/token`, no `ath`) carries the right key. Without `htm`/`htu`/`ath` checks, anyone who logs token-endpoint traffic can reuse it at the API.
- **Case 8 is a correctness test, not an attack.** `https://API.bank.example:443/accounts` and `https://api.bank.example/accounts?page=2` are the same `htu` after normalization, so an RS that compares strings rejects legitimate traffic (L27 case e).

---

## 5. L27: Spring Security 7.1.2's DPoP verifier, run for real

[D] How the pieces fit together:
- `oauth2ResourceServer(o -> o.jwt(...).dPoP(Customizer.withDefaults()))` installs a `DPoPAuthenticationProvider`.
  - The provider first authenticates the access token with the normal JWT or opaque-token manager, then decodes the proof with a `DPoPProofJwtDecoderFactory`.
  - The factory enforces `typ`, an RSA- or EC-family `alg`, a public `jwk` in the header, `htm` (case-insensitive), `htu` (exact `String.equals`), `iat` within ±30 s, `jkt` and `ath`, and `jti` uniqueness through `DPoPProofReplayValidator`.
  - It has **no nonce support**.
- `BearerTokenAuthenticationFilter` rejects a token whose attributes contain `cnf.jkt` when it arrives as `Bearer`: "Prevent downgraded usage of DPoP-bound access tokens". That check is always on in the servlet stack.
- The reactive stack has neither DPoP nor that check in 7.1.2. `ServerBearerTokenAuthenticationConverter` is the only converter.

<!-- listing:SpringDpopLab.java -->
```java
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.DPoPProofContext;
import org.springframework.security.oauth2.jwt.DPoPProofJwtDecoderFactory;
import org.springframework.security.oauth2.jwt.DPoPProofReplayValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoderFactory;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtIssuedAtValidator;

/**
 * L27 - Spring Security 7.1.2's DPoP proof verification, run on the real classes
 * ({@link DPoPProofJwtDecoderFactory}, {@link DPoPProofReplayValidator}, the validators the resource server's
 * {@code DPoPAuthenticationProvider} and the authorization server's token endpoint both use):
 * the RFC's own proofs at the RFC's own clock, fourteen proof variants, the per-key replay-cache cap, cross-node
 * replay with per-node caches, and an algorithm-policy validator for FAPI 2.0.
 */
public final class SpringDpopLab {
    static int jti;

    static String proof(Jose.Jwk k, String alg, String typ, String htm, String htu, Instant iat, String ath, boolean leakPrivate) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("typ", typ);
        h.put("alg", alg);
        h.put("jwk", DpopLab.publicJwk(k, leakPrivate));
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("jti", "spring-jti-" + (++jti));
        c.put("htm", htm);
        c.put("htu", htu);
        c.put("iat", iat.getEpochSecond());
        if (ath != null) {
            c.put("ath", ath);
        }
        return Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), k);
    }

    static Jwt accessToken(String value, String jkt) {
        Instant now = Instant.now();
        return Jwt.withTokenValue(value).header("alg", "ES256").subject("alice").issuedAt(now).expiresAt(now.plusSeconds(300))
                .claim("cnf", Map.of("jkt", jkt)).build();
    }

    static String run(JwtDecoderFactory<DPoPProofContext> f, String proof, String method, String uri, Jwt at) {
        DPoPProofContext ctx = DPoPProofContext.withDPoPProof(proof).method(method).targetUri(uri).accessToken(at).build();
        try {
            f.createDecoder(ctx).decode(proof);
            return "accepted";
        } catch (JwtException e) {
            return "rejected: " + e.getMessage().replace("An error occurred while attempting to decode the Jwt: ", "")
                    .replaceAll("[0-9]{4}-[0-9]{2}-[0-9T:.]+Z", "<t>");
        }
    }

    /** FAPI 2.0 section 5.4.1: PS256, ES256 or EdDSA only (Spring accepts any RSA or EC JWS algorithm). */
    record AlgPolicy(Set<String> allowed) implements OAuth2TokenValidator<Jwt> {
        @Override
        public OAuth2TokenValidatorResult validate(Jwt proof) {
            Object alg = proof.getHeaders().get("alg");
            return allowed.contains(String.valueOf(alg)) ? OAuth2TokenValidatorResult.success()
                    : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_dpop_proof", "alg " + alg + " not allowed by policy", null));
        }
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String rfc = KbSupport.rfc(fx, "rfc9449.txt");

        KbSupport.section("RFC 9449 Figures 2 and 13 through Spring's DPoPProofJwtDecoderFactory");
        String fig2 = DpopLab.wrappedProofBefore(rfc, "Figure 2: Example DPoP Header");
        String fig13 = DpopLab.wrappedProofBefore(rfc, "Figure 13: DPoP-Protected Resource Request");
        Jwt rfcToken = accessToken("Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU", "0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I");
        Clock rfcClock = Clock.fixed(Instant.ofEpochSecond(1_562_262_618L), ZoneOffset.UTC);
        JwtIssuedAtValidator iat2019 = new JwtIssuedAtValidator(true);
        iat2019.setClock(rfcClock);
        iat2019.setClockSkew(Duration.ofSeconds(30));
        DPoPProofReplayValidator replay2019 = new DPoPProofReplayValidator(new DPoPProofReplayValidator.InMemoryCache());
        replay2019.setClock(rfcClock);
        DPoPProofJwtDecoderFactory at2019 = new DPoPProofJwtDecoderFactory();
        at2019.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(List.of(iat2019, replay2019)));
        DPoPProofJwtDecoderFactory stock = new DPoPProofJwtDecoderFactory();
        String f2 = run(at2019, fig2, "POST", "https://server.example.com/token", null);
        String f13 = run(at2019, fig13, "GET", "https://resource.example.org/protectedresource", rfcToken);
        String f13now = run(stock, fig13, "GET", "https://resource.example.org/protectedresource", rfcToken);
        KbSupport.info("Figure 2  (token endpoint), clock = 2019-07-04T17:50:18Z -> %s", f2);
        KbSupport.info("Figure 13 (resource + ath + cnf.jkt), same clock      -> %s", f13);
        KbSupport.info("Figure 13 with the stock validators and today's clock -> %s", f13now);
        KbSupport.check("Spring verifies both RFC proofs (signature, typ, htm, htu, ath, jkt, jti) at the RFC's own time",
                f2.equals("accepted") && f13.equals("accepted"));
        KbSupport.check("...and the 30 s iat window rejects them today", f13now.equals("rejected: iat claim is invalid."));

        KbSupport.section("Fourteen proof variants against the stock factory (today's clock, token bound to key V)");
        SecureRandom rng = new SecureRandom();
        Jose.Jwk v = Jose.generate("ES256", rng);
        Jose.Jwk attacker = Jose.generate("ES256", rng);
        Jose.Jwk rsaPs = Jose.generate("PS256", rng);
        Jose.Jwk rsaRs = Jose.generate("RS256", rng);
        Jose.Jwk ed = Jose.generate("Ed25519", rng);
        String api = "https://api.bank.example/accounts";
        String tok = "opaque-token-value-1";
        String ath = DpopLab.ath(tok);
        Instant now = Instant.now();
        Jwt atV = accessToken(tok, v.thumbprint());
        String valid = proof(v, "ES256", "dpop+jwt", "GET", api, now, ath, false);
        Object[][] cases = {
            {"a valid ES256 proof", valid, "GET", api, atV, true},
            {"b the same proof again (replay)", valid, "GET", api, atV, false},
            {"c htm POST on a GET", proof(v, "ES256", "dpop+jwt", "POST", api, now, ath, false), "GET", api, atV, false},
            {"d htu of another endpoint", proof(v, "ES256", "dpop+jwt", "GET", "https://api.bank.example/payments", now, ath, false), "GET", api, atV, false},
            {"e htu https://API.bank.example:443/accounts", proof(v, "ES256", "dpop+jwt", "GET", "https://API.bank.example:443/accounts", now, ath, false),
                "GET", api, atV, true},
            {"f no ath", proof(v, "ES256", "dpop+jwt", "GET", api, now, null, false), "GET", api, atV, false},
            {"g attacker's key with the stolen token", proof(attacker, "ES256", "dpop+jwt", "GET", api, now, ath, false), "GET", api, atV, false},
            {"h iat 60 s ago", proof(v, "ES256", "dpop+jwt", "GET", api, now.minusSeconds(60), ath, false), "GET", api, atV, false},
            {"i iat 25 s in the future", proof(v, "ES256", "dpop+jwt", "GET", api, now.plusSeconds(25), ath, false), "GET", api, atV, true},
            {"j PS256 proof", proof(rsaPs, "PS256", "dpop+jwt", "GET", api, now, ath, false), "GET", api, accessToken(tok, rsaPs.thumbprint()), true},
            {"k RS256 proof (not allowed by FAPI 2.0)", proof(rsaRs, "RS256", "dpop+jwt", "GET", api, now, ath, false), "GET", api,
                accessToken(tok, rsaRs.thumbprint()), false},
            {"l Ed25519 proof (alg EdDSA, allowed by FAPI 2.0)", proof(ed, "EdDSA", "dpop+jwt", "GET", api, now, ath, false), "GET", api,
                accessToken(tok, ed.thumbprint()), true},
            {"m typ JWT", proof(v, "ES256", "JWT", "GET", api, now, ath, false), "GET", api, atV, false},
            {"n private key inside the jwk header", proof(v, "ES256", "dpop+jwt", "GET", api, now, ath, true), "GET", api, atV, false}};
        Map<String, String> results = new LinkedHashMap<>();
        for (Object[] c : cases) {
            String r = run(stock, (String) c[1], (String) c[2], (String) c[3], (Jwt) c[4]);
            results.put((String) c[0], r);
            boolean shouldAccept = (Boolean) c[5];
            String note = ((String) c[0]).startsWith("e") ? "RFC 9449 4.3: SHOULD normalize before comparing"
                    : ((String) c[0]).startsWith("k") ? "FAPI 2.0 5.4.1: PS256, ES256 or EdDSA only" : "FAPI 2.0 5.4.1 allows EdDSA";
            KbSupport.info("%-48s -> %s%s", c[0], r, r.equals("accepted") == shouldAccept ? "" : "   <-- " + note);
        }
        KbSupport.check("replay, htm, htu, ath, foreign key, stale iat, typ and private jwk are all rejected",
                List.of("b", "c", "d", "f", "g", "h", "m", "n").stream().allMatch(p -> results.entrySet().stream()
                        .anyMatch(e -> e.getKey().startsWith(p + " ") && e.getValue().startsWith("rejected"))));
        KbSupport.check("three divergences: no htu normalization (e), RS256 accepted (k), Ed25519 rejected (l)",
                results.get("e htu https://API.bank.example:443/accounts").startsWith("rejected")
                        && results.get("k RS256 proof (not allowed by FAPI 2.0)").equals("accepted")
                        && results.get("l Ed25519 proof (alg EdDSA, allowed by FAPI 2.0)").startsWith("rejected: Unsupported alg"));

        KbSupport.section("The replay cache's per-key cap (InMemoryCache: 1,000 live proofs per JWK thumbprint)");
        Jose.Jwk busy = Jose.generate("ES256", rng);
        Jwt atBusy = accessToken(tok, busy.thumbprint());
        int ok = 0;
        String firstFailure = null;
        Instant t0 = Instant.now();
        for (int i = 0; i < 1_001; i++) {
            String r = run(stock, proof(busy, "ES256", "dpop+jwt", "GET", api, Instant.now(), ath, false), "GET", api, atBusy);
            if (r.equals("accepted")) {
                ok++;
            } else if (firstFailure == null) {
                firstFailure = "request " + (i + 1) + ": " + r;
            }
        }
        boolean fast = Duration.between(t0, Instant.now()).toSeconds() < 30;
        KbSupport.info("1,001 distinct, valid proofs from one client key in under 30 s: %d accepted; first failure at %s", ok, firstFailure);
        KbSupport.check("the 1,001st legitimate request is refused (entries live iat + 30 s: about 33 requests/s per key)",
                fast && ok == 1_000 && firstFailure != null && firstFailure.startsWith("request 1001: rejected: jti claim is invalid or unable to cache."));
        DPoPProofReplayValidator.InMemoryCache roomy = new DPoPProofReplayValidator.InMemoryCache();
        roomy.setMaxRequestsPerKey(20_000);
        DPoPProofJwtDecoderFactory sized = new DPoPProofJwtDecoderFactory();
        sized.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(List.of(new DPoPProofReplayValidator(roomy))));
        int ok2 = 0;
        for (int i = 0; i < 1_001; i++) {
            ok2 += run(sized, proof(busy, "ES256", "dpop+jwt", "GET", api, Instant.now(), ath, false), "GET", api, atBusy).equals("accepted") ? 1 : 0;
        }
        KbSupport.check("an InMemoryCache sized for the client (setMaxRequestsPerKey) accepts all 1,001", ok2 == 1_001);

        KbSupport.section("Two resource-server nodes: per-node caches vs one shared cache");
        DPoPProofJwtDecoderFactory nodeA = new DPoPProofJwtDecoderFactory();
        DPoPProofJwtDecoderFactory nodeB = new DPoPProofJwtDecoderFactory();
        nodeA.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(List.of()));
        nodeB.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(List.of()));
        String p1 = proof(v, "ES256", "dpop+jwt", "GET", api, Instant.now(), ath, false);
        String a1 = run(nodeA, p1, "GET", api, atV);
        String b1 = run(nodeB, p1, "GET", api, atV);
        DPoPProofReplayValidator shared = new DPoPProofReplayValidator(new DPoPProofReplayValidator.InMemoryCache());
        DPoPProofJwtDecoderFactory nodeC = new DPoPProofJwtDecoderFactory();
        DPoPProofJwtDecoderFactory nodeD = new DPoPProofJwtDecoderFactory();
        nodeC.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(List.of(shared)));
        nodeD.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(List.of(shared)));
        String p2 = proof(v, "ES256", "dpop+jwt", "GET", api, Instant.now(), ath, false);
        String c2 = run(nodeC, p2, "GET", api, atV);
        String d2 = run(nodeD, p2, "GET", api, atV);
        KbSupport.info("per-node caches: node A %s, the same proof at node B %s", a1, b1);
        KbSupport.info("one shared cache: node C %s, the same proof at node D %s", c2, d2);
        KbSupport.check("per-node caches let a captured proof be replayed once per node; a shared cache stops it",
                a1.equals("accepted") && b1.equals("accepted") && c2.equals("accepted") && d2.startsWith("rejected: jti"));

        KbSupport.section("Closing the algorithm gap with a custom validator (FAPI 2.0 section 5.4.1)");
        DPoPProofJwtDecoderFactory fapi = new DPoPProofJwtDecoderFactory();
        fapi.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(List.of(new AlgPolicy(Set.of("ES256", "PS256")))));
        String rs = run(fapi, proof(rsaRs, "RS256", "dpop+jwt", "GET", api, Instant.now(), ath, false), "GET", api, accessToken(tok, rsaRs.thumbprint()));
        String es = run(fapi, proof(v, "ES256", "dpop+jwt", "GET", api, Instant.now(), ath, false), "GET", api, atV);
        KbSupport.info("RS256 -> %s;  ES256 -> %s", rs, es);
        KbSupport.check("the policy validator rejects RS256 and keeps ES256 (EdDSA still needs a custom decoder factory)",
                rs.equals("rejected: alg RS256 not allowed by policy") && es.equals("accepted"));
        KbSupport.verdict();
    }
}
```

<!-- output:SpringDpopLab.java -->
```text

== RFC 9449 Figures 2 and 13 through Spring's DPoPProofJwtDecoderFactory
  Figure 2  (token endpoint), clock = 2019-07-04T17:50:18Z -> accepted
  Figure 13 (resource + ath + cnf.jkt), same clock      -> accepted
  Figure 13 with the stock validators and today's clock -> rejected: iat claim is invalid.
  [PASS] Spring verifies both RFC proofs (signature, typ, htm, htu, ath, jkt, jti) at the RFC's own time
  [PASS] ...and the 30 s iat window rejects them today

== Fourteen proof variants against the stock factory (today's clock, token bound to key V)
  a valid ES256 proof                              -> accepted
  b the same proof again (replay)                  -> rejected: jti claim is invalid or unable to cache.
  c htm POST on a GET                              -> rejected: The htm claim is not valid
  d htu of another endpoint                        -> rejected: The htu claim is not valid
  e htu https://API.bank.example:443/accounts      -> rejected: The htu claim is not valid   <-- RFC 9449 4.3: SHOULD normalize before comparing
  f no ath                                         -> rejected: ath claim is required.
  g attacker's key with the stolen token           -> rejected: jkt claim is invalid.
  h iat 60 s ago                                   -> rejected: iat claim is invalid.
  i iat 25 s in the future                         -> accepted
  j PS256 proof                                    -> accepted
  k RS256 proof (not allowed by FAPI 2.0)          -> accepted   <-- FAPI 2.0 5.4.1: PS256, ES256 or EdDSA only
  l Ed25519 proof (alg EdDSA, allowed by FAPI 2.0) -> rejected: Unsupported alg parameter in JWS Header: EdDSA   <-- FAPI 2.0 5.4.1 allows EdDSA
  m typ JWT                                        -> rejected: JOSE header typ (type) JWT not allowed
  n private key inside the jwk header              -> rejected: Malformed token
  [PASS] replay, htm, htu, ath, foreign key, stale iat, typ and private jwk are all rejected
  [PASS] three divergences: no htu normalization (e), RS256 accepted (k), Ed25519 rejected (l)

== The replay cache's per-key cap (InMemoryCache: 1,000 live proofs per JWK thumbprint)
  1,001 distinct, valid proofs from one client key in under 30 s: 1000 accepted; first failure at request 1001: rejected: jti claim is invalid or unable to cache.
  [PASS] the 1,001st legitimate request is refused (entries live iat + 30 s: about 33 requests/s per key)
  [PASS] an InMemoryCache sized for the client (setMaxRequestsPerKey) accepts all 1,001

== Two resource-server nodes: per-node caches vs one shared cache
  per-node caches: node A accepted, the same proof at node B accepted
  one shared cache: node C accepted, the same proof at node D rejected: jti claim is invalid or unable to cache.
  [PASS] per-node caches let a captured proof be replayed once per node; a shared cache stops it

== Closing the algorithm gap with a custom validator (FAPI 2.0 section 5.4.1)
  RS256 -> rejected: alg RS256 not allowed by policy;  ES256 -> accepted
  [PASS] the policy validator rejects RS256 and keeps ES256 (EdDSA still needs a custom decoder factory)

verdict: OK (8 checks)
```

Reading the run:
- **The replay cache's per-key cap.** `DPoPProofReplayValidator.InMemoryCache` defaults to 100,000 entries and **1,000 requests per key**. Entries live `iat` + 30 s and are cleaned every 10 s. A single-key client sustaining more than roughly 33 requests/s gets "jti claim is invalid or unable to cache" on legitimate requests. That is fine for a mobile app and fatal for a server-to-server FAPI client or a batch job [E].
  - Size the cache per client class.
  - In a cluster, replace it with a shared `org.springframework.cache.Cache` whose `putIfAbsent` is atomic. Redis `SET NX` behind a `RedisCache` works, and node-local caches allow one replay per node (L27 §4).
- **`htu` is compared to the URL the servlet container reconstructs.** Behind a TLS-terminating proxy that is `http://app:8080/...` unless forwarded headers are honoured (`server.forward-headers-strategy=framework`, or the container's remote-IP valve), and only from trusted proxies [E]. Otherwise every DPoP request fails, and someone "fixes" it by disabling DPoP.
- **Algorithms.** FAPI 2.0 §5.4.1 allows PS256, ES256 or EdDSA. Spring accepts RS256 (fix: the `AlgPolicy` validator, L27 §5) and can't verify EdDSA proofs (fix: your own `JwtDecoderFactory<DPoPProofContext>` with an Ed25519-capable key selector, or require ES256 from clients).
- **Wiring the fixes.** The provider is built inside `DPoPConfigurer`, but it goes through `postProcess`. `oauth2ResourceServer(o -> o.withObjectPostProcessor(...))` can therefore call `DPoPAuthenticationProvider.setDPoPProofVerifierFactory(...)` (§8).

### 5.1 L29: the authorization server side

[D] In Spring Authorization Server 7.1.2, the token endpoint calls `DPoPProofVerifier.verifyIfAvailable(...)` for the `authorization_code`, `refresh_token`, `client_credentials`, device-code and token-exchange grants:
- DPoP is optional on every request;
- if a proof is present, `DefaultOAuth2TokenCustomizers` adds `cnf.jkt`, and the response says `token_type=DPoP`;
- for public clients refreshing *with* a proof, the proof key must match the current access token's `cnf.jkt`;
- there is no `dpop_jkt` anywhere in the 7.1.2 jars, and no per-client "DPoP required" setting.

<!-- listing:SasDpopRefreshLab.java -->
```java
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.security.Principal;
import java.security.SecureRandom;
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
import org.springframework.security.oauth2.core.OAuth2RefreshToken;
import org.springframework.security.oauth2.server.authorization.InMemoryOAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.OAuth2Authorization;
import org.springframework.security.oauth2.server.authorization.OAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.OAuth2TokenType;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2AccessTokenAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2ClientAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2RefreshTokenAuthenticationProvider;
import org.springframework.security.oauth2.server.authorization.authentication.OAuth2RefreshTokenAuthenticationToken;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.context.AuthorizationServerContext;
import org.springframework.security.oauth2.server.authorization.context.AuthorizationServerContextHolder;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.ClientSettings;
import org.springframework.security.oauth2.server.authorization.settings.OAuth2TokenFormat;
import org.springframework.security.oauth2.server.authorization.settings.TokenSettings;
import org.springframework.security.oauth2.server.authorization.token.DelegatingOAuth2TokenGenerator;
import org.springframework.security.oauth2.server.authorization.token.OAuth2AccessTokenGenerator;
import org.springframework.security.oauth2.server.authorization.token.OAuth2RefreshTokenGenerator;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenClaimsContext;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer;

/**
 * L29 - Spring Authorization Server 7.1.2's DPoP handling at the token endpoint, run on the real
 * {@link OAuth2RefreshTokenAuthenticationProvider}, with the access-token customizer that
 * {@code OAuth2AuthorizationServerConfigurer} installs (the package-private {@code DefaultOAuth2TokenCustomizers},
 * reached by reflection) so {@code cnf.jkt} is added exactly as in a real server.
 *
 * <p>RFC 9449 section 5: a refresh token issued to a PUBLIC client with DPoP "MUST be bound to the respective public
 * key. The binding MUST be validated when the refresh token is later presented". FAPI 2.0 section 5.3.2.1: the AS
 * "shall only issue sender-constrained access tokens". The run shows both, then a 40-line provider decorator that
 * restores them.
 */
public final class SasDpopRefreshLab {
    static final String ISSUER = "https://idp.example.com";
    static final String TOKEN_URI = ISSUER + "/oauth2/token";

    @SuppressWarnings("unchecked")
    static OAuth2TokenCustomizer<OAuth2TokenClaimsContext> springDefaultCustomizer() throws Exception {
        Class<?> c = Class.forName("org.springframework.security.config.annotation.web.configurers.oauth2.server.authorization.DefaultOAuth2TokenCustomizers");
        Method m = c.getDeclaredMethod("accessTokenCustomizer");
        m.setAccessible(true);
        return (OAuth2TokenCustomizer<OAuth2TokenClaimsContext>) m.invoke(null);
    }

    record Rig(RegisteredClient client, OAuth2AuthorizationService service, AuthenticationProvider provider) {
    }

    static Rig rig(boolean publicClient, String boundJkt, boolean decorated) throws Exception {
        RegisteredClient.Builder b = RegisteredClient.withId(publicClient ? "rc-tv" : "rc-bank").clientId(publicClient ? "tv-app" : "fintech-a")
                .authorizationGrantType(AuthorizationGrantType.DEVICE_CODE).authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
                .scope("accounts")
                .tokenSettings(TokenSettings.builder().accessTokenFormat(OAuth2TokenFormat.REFERENCE).build()) // opaque; cnf via the same customizer
                .clientSettings(ClientSettings.builder().setting("settings.client.require-dpop", true).build());
        b = publicClient ? b.clientAuthenticationMethod(ClientAuthenticationMethod.NONE)
                : b.clientAuthenticationMethod(ClientAuthenticationMethod.PRIVATE_KEY_JWT);
        RegisteredClient client = b.build();
        OAuth2AuthorizationService svc = new InMemoryOAuth2AuthorizationService();
        Instant now = Instant.now();
        Map<String, Object> claims = new HashMap<>();
        claims.put("sub", "alice");
        claims.put("cnf", Map.of("jkt", boundJkt)); // the grant was issued with a DPoP proof from key V
        svc.save(OAuth2Authorization.withRegisteredClient(client).id("grant-1").principalName("alice")
                .authorizationGrantType(AuthorizationGrantType.DEVICE_CODE).authorizedScopes(Set.of("accounts"))
                .attribute(Principal.class.getName(), UsernamePasswordAuthenticationToken.authenticated("alice", null, List.of()))
                .token(new OAuth2AccessToken(OAuth2AccessToken.TokenType.DPOP, "at-0", now, now.plusSeconds(300), Set.of("accounts")),
                        md -> md.put(OAuth2Authorization.Token.CLAIMS_METADATA_NAME, claims))
                .refreshToken(new OAuth2RefreshToken("rt-0", now, now.plusSeconds(86_400))).build());
        OAuth2AccessTokenGenerator at = new OAuth2AccessTokenGenerator();
        at.setAccessTokenCustomizer(springDefaultCustomizer());
        AuthenticationProvider p = new OAuth2RefreshTokenAuthenticationProvider(svc, new DelegatingOAuth2TokenGenerator(at, new OAuth2RefreshTokenGenerator()));
        return new Rig(client, svc, decorated ? new RequireDpopOnRefresh(p, svc) : p);
    }

    /**
     * The fix: if the grant's current access token is DPoP-bound, or the client is flagged
     * {@code settings.client.require-dpop}, a refresh without a DPoP proof is refused before Spring's provider runs.
     */
    record RequireDpopOnRefresh(AuthenticationProvider delegate, OAuth2AuthorizationService service) implements AuthenticationProvider {
        @Override
        public Authentication authenticate(Authentication a) {
            OAuth2RefreshTokenAuthenticationToken req = (OAuth2RefreshTokenAuthenticationToken) a;
            boolean hasProof = req.getAdditionalParameters().get("dpop_proof") != null;
            OAuth2Authorization grant = service.findByToken(req.getRefreshToken(), OAuth2TokenType.REFRESH_TOKEN);
            Map<String, Object> claims = grant == null || grant.getAccessToken() == null ? null : grant.getAccessToken().getClaims();
            boolean bound = claims != null && claims.get("cnf") instanceof Map<?, ?> cnf && cnf.containsKey("jkt");
            RegisteredClient client = ((OAuth2ClientAuthenticationToken) req.getPrincipal()).getRegisteredClient();
            boolean required = client != null && Boolean.TRUE.equals(client.getClientSettings().getSetting("settings.client.require-dpop"));
            if (!hasProof && (bound || required)) {
                throw new OAuth2AuthenticationException(new OAuth2Error("invalid_dpop_proof",
                        "a DPoP proof is required to refresh this grant", null));
            }
            return delegate.authenticate(a);
        }

        @Override
        public boolean supports(Class<?> c) {
            return delegate.supports(c);
        }
    }

    static String proof(Jose.Jwk k) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("typ", "dpop+jwt");
        h.put("alg", "ES256");
        h.put("jwk", DpopLab.publicJwk(k, false));
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("jti", java.util.UUID.randomUUID().toString());
        c.put("htm", "POST");
        c.put("htu", TOKEN_URI);
        c.put("iat", Instant.now().getEpochSecond());
        return Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), k);
    }

    static String refresh(Rig r, Jose.Jwk proofKey) {
        ClientAuthenticationMethod m = r.client().getClientAuthenticationMethods().iterator().next();
        OAuth2ClientAuthenticationToken principal = new OAuth2ClientAuthenticationToken(r.client(), m, null);
        Map<String, Object> params = new HashMap<>();
        if (proofKey != null) {
            params.put("dpop_proof", proof(proofKey));
            params.put("dpop_method", "POST");
            params.put("dpop_target_uri", TOKEN_URI);
        }
        try {
            OAuth2AccessTokenAuthenticationToken res = (OAuth2AccessTokenAuthenticationToken) r.provider()
                    .authenticate(new OAuth2RefreshTokenAuthenticationToken("rt-0", principal, null, params));
            OAuth2AccessToken t = res.getAccessToken();
            // what introspection would return for the new token: the claims the AS stored with it
            OAuth2Authorization stored = r.service().findByToken(t.getTokenValue(), OAuth2TokenType.ACCESS_TOKEN);
            Map<String, Object> claims = stored == null || stored.getAccessToken().getClaims() == null ? Map.of() : stored.getAccessToken().getClaims();
            Object cnf = claims.get("cnf");
            return "200 token_type=" + t.getTokenType().getValue() + (cnf == null ? ", no cnf: a plain bearer token" : ", cnf.jkt bound");
        } catch (OAuth2AuthenticationException e) {
            return "400 " + e.getError().getErrorCode() + (e.getError().getDescription() == null ? "" : " (" + e.getError().getDescription() + ")");
        }
    }

    public static void main(String[] args) throws Exception {
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
        SecureRandom rng = new SecureRandom();
        Jose.Jwk v = Jose.generate("ES256", rng);
        Jose.Jwk attacker = Jose.generate("ES256", rng);

        Map<String, String> out = new LinkedHashMap<>();
        for (boolean decorated : new boolean[] {false, true}) {
            String tag = decorated ? "L7" : "stock";
            KbSupport.section((decorated ? "With RequireDpopOnRefresh" : "Stock OAuth2RefreshTokenAuthenticationProvider")
                    + ": a public TV app's DPoP-bound device grant, refresh token rt-0 copied by malware");
            out.put(tag + "1", refresh(rig(true, v.thumbprint(), decorated), v));
            out.put(tag + "2", refresh(rig(true, v.thumbprint(), decorated), attacker));
            out.put(tag + "3", refresh(rig(true, v.thumbprint(), decorated), null));
            out.put(tag + "4", refresh(rig(false, v.thumbprint(), decorated), null));
            KbSupport.info("%-5s 1 the app refreshes with a proof from its key V             -> %s", tag, out.get(tag + "1"));
            KbSupport.info("%-5s 2 attacker: rt-0 + a proof from the attacker's key          -> %s", tag, out.get(tag + "2"));
            KbSupport.info("%-5s 3 attacker: rt-0 and NO DPoP header at all                  -> %s", tag, out.get(tag + "3"));
            KbSupport.info("%-5s 4 confidential FAPI client refreshes without a DPoP header  -> %s", tag, out.get(tag + "4"));
        }
        KbSupport.check("stock: the binding holds against a foreign key (case 2)",
                out.get("stock2").equals("400 invalid_dpop_proof (jwk header is invalid.)"));
        KbSupport.check("stock: omitting the DPoP header skips the check and mints a plain BEARER token from a bound refresh token (case 3)",
                out.get("stock1").contains("cnf.jkt bound") && out.get("stock3").equals("200 token_type=Bearer, no cnf: a plain bearer token"));
        KbSupport.check("stock: nothing forces a FAPI client to stay sender-constrained (case 4)",
                out.get("stock4").startsWith("200 token_type=Bearer"));
        KbSupport.check("decorated: the legitimate refresh still works; cases 2-4 are all refused",
                out.get("L71").contains("cnf.jkt bound") && out.get("L72").startsWith("400") && out.get("L73").startsWith("400 invalid_dpop_proof")
                        && out.get("L74").startsWith("400 invalid_dpop_proof"));
        KbSupport.verdict();
    }
}
```

<!-- output:SasDpopRefreshLab.java -->
```text

== Stock OAuth2RefreshTokenAuthenticationProvider: a public TV app's DPoP-bound device grant, refresh token rt-0 copied by malware
  stock 1 the app refreshes with a proof from its key V             -> 200 token_type=DPoP, cnf.jkt bound
  stock 2 attacker: rt-0 + a proof from the attacker's key          -> 400 invalid_dpop_proof (jwk header is invalid.)
  stock 3 attacker: rt-0 and NO DPoP header at all                  -> 200 token_type=Bearer, no cnf: a plain bearer token
  stock 4 confidential FAPI client refreshes without a DPoP header  -> 200 token_type=Bearer, no cnf: a plain bearer token

== With RequireDpopOnRefresh: a public TV app's DPoP-bound device grant, refresh token rt-0 copied by malware
  L7    1 the app refreshes with a proof from its key V             -> 200 token_type=DPoP, cnf.jkt bound
  L7    2 attacker: rt-0 + a proof from the attacker's key          -> 400 invalid_dpop_proof (jwk header is invalid.)
  L7    3 attacker: rt-0 and NO DPoP header at all                  -> 400 invalid_dpop_proof (a DPoP proof is required to refresh this grant)
  L7    4 confidential FAPI client refreshes without a DPoP header  -> 400 invalid_dpop_proof (a DPoP proof is required to refresh this grant)
  [PASS] stock: the binding holds against a foreign key (case 2)
  [PASS] stock: omitting the DPoP header skips the check and mints a plain BEARER token from a bound refresh token (case 3)
  [PASS] stock: nothing forces a FAPI client to stay sender-constrained (case 4)
  [PASS] decorated: the legitimate refresh still works; cases 2-4 are all refused

verdict: OK (4 checks)
```

Case 3 is the finding:
- **The attack.** Malware copies a public client's DPoP-bound refresh token, and the attacker never sends a DPoP header, so the binding check never runs.
- **What it yields.** A fresh **Bearer** access token with no `cnf`, which a Spring resource server accepts as an ordinary bearer token, because only `cnf.jkt` tokens are blocked from the Bearer scheme.
- **How long.** Indefinitely, since `reuseRefreshTokens(true)` is the default (Folder 02 file 03).

Case 4 is the FAPI gap: nothing forces a client to stay sender-constrained. `RequireDpopOnRefresh` refuses a proof-less refresh when the grant is DPoP-bound or the client is flagged, and is installed with `tokenEndpoint(t -> t.authenticationProviders(...))` (§8). No matching upstream report turned up in a search on 2026-11-06. This is the kind of finding to send through the project's security policy rather than a public issue [E].

---

## 6. L28: certificate-bound tokens over real mutual TLS

<!-- listing:MtlsBindingLab.java -->
```java
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.math.BigInteger;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.ECGenParameterSpec;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLPeerUnverifiedException;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManagerFactory;

import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.ExtendedKeyUsage;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.KeyPurposeId;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

/**
 * L28 - certificate-bound access tokens (RFC 8705) over real mutual TLS 1.3 on 127.0.0.1.
 *
 * <p>A private CA (BouncyCastle) issues client certificates A and B, a server certificate, and a load-balancer
 * certificate. The "token endpoint" binds a token to SHA-256(DER of the certificate presented in the TLS handshake);
 * the "resource server" checks it with Spring Security 7.1.2's own {@code X509CertificateThumbprintValidator}
 * (part of {@code JwtValidators.createDefault()}), fed the way a servlet container feeds it: the
 * {@code jakarta.servlet.request.X509Certificate} request attribute. Then the TLS-terminating proxy problem: what
 * goes wrong when that attribute is filled from a forwarded header. Run with {@code bench} for handshake vs DPoP
 * cost.
 */
public final class MtlsBindingLab {
    static final String ATTR = "jakarta.servlet.request.X509Certificate";

    record Party(KeyPair keys, X509Certificate cert) {
    }

    static KeyPair ec(SecureRandom rng) throws Exception {
        KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
        g.initialize(new ECGenParameterSpec("secp256r1"), rng);
        return g.generateKeyPair();
    }

    static X509Certificate issue(String cn, PublicKey subjectKey, PrivateKey caKey, String issuerDn, boolean ca, KeyPurposeId eku,
                                 long serial) throws Exception {
        Instant now = Instant.now();
        JcaX509v3CertificateBuilder b = new JcaX509v3CertificateBuilder(new X500Name(issuerDn), BigInteger.valueOf(serial),
                Date.from(now.minusSeconds(300)), Date.from(now.plusSeconds(86_400)), new X500Name("CN=" + cn), subjectKey);
        b.addExtension(Extension.basicConstraints, true, new BasicConstraints(ca));
        b.addExtension(Extension.keyUsage, true, new KeyUsage(ca ? KeyUsage.keyCertSign | KeyUsage.cRLSign : KeyUsage.digitalSignature));
        if (eku != null) {
            b.addExtension(Extension.extendedKeyUsage, false, new ExtendedKeyUsage(eku));
        }
        return new JcaX509CertificateConverter().getCertificate(b.build(new JcaContentSignerBuilder("SHA256withECDSA").build(caKey)));
    }

    static String x5tS256(X509Certificate c) throws Exception {
        return KbSupport.b64u(MessageDigest.getInstance("SHA-256").digest(c.getEncoded()));
    }

    static SSLContext tls(Party me, X509Certificate caCert, SecureRandom rng) throws Exception {
        char[] pw = "pw".toCharArray();
        KeyManagerFactory kmf = KeyManagerFactory.getInstance("PKIX");
        if (me != null) {
            KeyStore ks = KeyStore.getInstance("PKCS12");
            ks.load(null, null);
            ks.setKeyEntry("me", me.keys().getPrivate(), pw, new Certificate[] {me.cert(), caCert});
            kmf.init(ks, pw);
        }
        KeyStore ts = KeyStore.getInstance("PKCS12");
        ts.load(null, null);
        ts.setCertificateEntry("ca", caCert);
        TrustManagerFactory tmf = TrustManagerFactory.getInstance("PKIX");
        tmf.init(ts);
        SSLContext ctx = SSLContext.getInstance("TLSv1.3");
        ctx.init(me == null ? null : kmf.getKeyManagers(), tmf.getTrustManagers(), rng);
        return ctx;
    }

    /** What a servlet container exposes to Spring: the client chain as a request attribute. */
    static void exposeToSpring(X509Certificate[] chain) {
        RequestContextHolder.setRequestAttributes(new RequestAttributes() {
            @Override
            public Object getAttribute(String name, int scope) {
                return ATTR.equals(name) ? chain : null;
            }

            @Override
            public void setAttribute(String name, Object value, int scope) {
            }

            @Override
            public void removeAttribute(String name, int scope) {
            }

            @Override
            public String[] getAttributeNames(int scope) {
                return new String[0];
            }

            @Override
            public void registerDestructionCallback(String name, Runnable callback, int scope) {
            }

            @Override
            public Object resolveReference(String key) {
                return null;
            }

            @Override
            public String getSessionId() {
                return "none";
            }

            @Override
            public Object getSessionMutex() {
                return this;
            }
        });
    }

    static X509Certificate fromHeader(String b64) throws Exception {
        return (X509Certificate) CertificateFactory.getInstance("X.509")
                .generateCertificate(new java.io.ByteArrayInputStream(Base64.getDecoder().decode(b64)));
    }

    /** The server side of every connection: token endpoint ("issue") or resource server in one of three modes. */
    static final class Server {
        final Map<String, Jwt> tokens = new ConcurrentHashMap<>();
        final OAuth2TokenValidator<Jwt> spring = JwtValidators.createDefault();
        final String lbThumbprint;

        Server(String lbThumbprint) {
            this.lbThumbprint = lbThumbprint;
        }

        String handle(X509Certificate[] peer, String line) throws Exception {
            String[] f = line.split("\\|", -1); // mode | token id | forwarded client cert (base64 DER) or empty
            String mode = f[0];
            if (mode.equals("issue")) {
                Instant now = Instant.now();
                Jwt t = Jwt.withTokenValue(f[1]).header("alg", "PS256").subject(peer[0].getSubjectX500Principal().getName())
                        .issuedAt(now).expiresAt(now.plusSeconds(300)).claim("cnf", Map.of("x5t#S256", x5tS256(peer[0]))).build();
                tokens.put(f[1], t);
                return "token issued, cnf.x5t#S256 = SHA-256 of the handshake certificate (" + x5tS256(peer[0]).length() + " chars)";
            }
            X509Certificate[] chain;
            if (mode.equals("direct")) {
                chain = peer;                                  // container-terminated mTLS
            } else if (mode.equals("l5-header")) {
                chain = !f[2].isEmpty() ? new X509Certificate[] {fromHeader(f[2])} : peer; // trusts the header from anyone
            } else {                                           // l7-header: header only if the TLS peer IS the load balancer
                boolean fromLb = peer != null && x5tS256(peer[0]).equals(lbThumbprint);
                chain = fromLb && !f[2].isEmpty() ? new X509Certificate[] {fromHeader(f[2])} : fromLb ? null : peer;
            }
            exposeToSpring(chain);
            try {
                OAuth2TokenValidatorResult r = spring.validate(tokens.get(f[1]));
                return r.hasErrors() ? "401 " + r.getErrors().iterator().next().getDescription() : "200";
            } finally {
                RequestContextHolder.resetRequestAttributes();
            }
        }
    }

    static String call(SSLContext ctx, int port, String line) throws Exception {
        try (SSLSocket s = (SSLSocket) ctx.getSocketFactory().createSocket(InetAddress.getLoopbackAddress(), port)) {
            s.startHandshake();
            PrintWriter w = new PrintWriter(new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8), true);
            w.println(line);
            return new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8)).readLine();
        }
    }

    public static void main(String[] args) throws Exception {
        SecureRandom rng = new SecureRandom();
        KeyPair caKeys = ec(rng);
        String caDn = "CN=Bank Partner CA";
        X509Certificate caCert = issue("Bank Partner CA", caKeys.getPublic(), caKeys.getPrivate(), caDn, true, null, 1);
        KeyPair sk = ec(rng);
        Party server = new Party(sk, issue("api.bank.example", sk.getPublic(), caKeys.getPrivate(), caDn, false, KeyPurposeId.id_kp_serverAuth, 2));
        KeyPair ak = ec(rng);
        Party a = new Party(ak, issue("fintech-a", ak.getPublic(), caKeys.getPrivate(), caDn, false, KeyPurposeId.id_kp_clientAuth, 3));
        KeyPair bk = ec(rng);
        Party b = new Party(bk, issue("fintech-b", bk.getPublic(), caKeys.getPrivate(), caDn, false, KeyPurposeId.id_kp_clientAuth, 4));
        KeyPair lk = ec(rng);
        Party lb = new Party(lk, issue("edge-lb", lk.getPublic(), caKeys.getPrivate(), caDn, false, KeyPurposeId.id_kp_clientAuth, 5));

        Server logic = new Server(x5tS256(lb.cert()));
        SSLContext serverCtx = tls(server, caCert, rng);
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try (SSLServerSocket ss = (SSLServerSocket) serverCtx.getServerSocketFactory().createServerSocket(0, 50, InetAddress.getLoopbackAddress())) {
            ss.setWantClientAuth(true); // a certificate is optional at the TLS layer; the application decides
            pool.submit(() -> {
                while (!ss.isClosed()) {
                    try (SSLSocket s = (SSLSocket) ss.accept()) {
                        s.startHandshake();
                        X509Certificate[] peer;
                        try {
                            peer = Arrays.stream(s.getSession().getPeerCertificates()).map(X509Certificate.class::cast).toArray(X509Certificate[]::new);
                        } catch (SSLPeerUnverifiedException none) {
                            peer = null;
                        }
                        String line = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8)).readLine();
                        new PrintWriter(new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8), true).println(logic.handle(peer, line));
                    } catch (Exception e) {
                        if (!ss.isClosed()) {
                            KbSupport.info("server error %s", e);
                        }
                    }
                }
                return null;
            });
            int port = ss.getLocalPort();
            if (KbSupport.flag(args, "bench")) {
                bench(port, a, caCert, rng, KbSupport.flag(args, "--quick"));
                return;
            }
            SSLContext ctxA = tls(a, caCert, rng);
            SSLContext ctxB = tls(b, caCert, rng);
            SSLContext ctxLb = tls(lb, caCert, rng);
            SSLContext ctxNone = tls(null, caCert, rng);
            String certA = Base64.getEncoder().encodeToString(a.cert().getEncoded());

            KbSupport.section("Token endpoint: bind the access token to the handshake certificate (RFC 8705 section 3)");
            KbSupport.info("fintech-a over mTLS -> %s", call(ctxA, port, "issue|tokA|"));

            KbSupport.section("Resource server, container-terminated mTLS (Spring's X509CertificateThumbprintValidator)");
            List<String[]> rows = new ArrayList<>();
            rows.add(new String[] {"1 fintech-a presents its own token", call(ctxA, port, "direct|tokA|"), "200"});
            rows.add(new String[] {"2 fintech-b (same CA!) presents the stolen token", call(ctxB, port, "direct|tokA|"), "401"});
            rows.add(new String[] {"3 no client certificate on the connection", call(ctxNone, port, "direct|tokA|"), "401"});
            for (String[] r : rows) {
                KbSupport.info("%-64s -> %s", r[0], r[1]);
            }
            KbSupport.section("Behind a TLS-terminating proxy: the certificate arrives in a header");
            rows.add(new String[] {"4 L5: attacker, no cert, header = fintech-a's (public) cert", call(ctxNone, port, "l5-header|tokA|" + certA), "200!"});
            rows.add(new String[] {"5 L7: attacker with cert B + forged header = cert A", call(ctxB, port, "l7-header|tokA|" + certA), "401"});
            rows.add(new String[] {"6 L7: attacker, no cert, forged header = cert A", call(ctxNone, port, "l7-header|tokA|" + certA), "401"});
            rows.add(new String[] {"7 L7: real request via the LB (LB-to-RS mTLS, LB sets header)", call(ctxLb, port, "l7-header|tokA|" + certA), "200"});
            for (String[] r : rows.subList(3, rows.size())) {
                KbSupport.info("%-64s -> %s", r[0], r[1]);
            }
            KbSupport.check("container mTLS: the owner passes; a stolen token fails even with another CA-issued cert; no cert fails closed",
                    rows.get(0)[1].equals("200") && rows.get(1)[1].equals("401 Invalid SHA-256 Thumbprint for X509Certificate.")
                            && rows.get(2)[1].equals("401 Unable to obtain X509Certificate from current request."));
            KbSupport.check("L5 header trust: a copied PUBLIC certificate in a header defeats the binding",
                    rows.get(3)[1].equals("200"));
            KbSupport.check("L7: the header counts only on the load balancer's own mTLS connection",
                    rows.get(4)[1].startsWith("401") && rows.get(5)[1].startsWith("401") && rows.get(6)[1].equals("200"));
        } finally {
            pool.shutdownNow();
        }
        KbSupport.verdict();
    }

    /** measured: full TLS 1.3 handshakes with a client certificate vs ES256 DPoP proof sign + verify. */
    static void bench(int port, Party a, X509Certificate caCert, SecureRandom rng, boolean quick) throws Exception {
        int hs = quick ? 10 : 60;
        int dp = quick ? 100 : 600;
        Jose.Jwk k = Jose.generate("ES256", rng);
        double[] hsMed = new double[5];
        double[] dpMed = new double[5];
        for (int round = 0; round < 5; round++) {
            List<SSLContext> fresh = new ArrayList<>();
            for (int i = 0; i < hs; i++) {
                fresh.add(tls(a, caCert, rng)); // a new context per connection: no session resumption
            }
            long t = System.nanoTime();
            for (SSLContext c : fresh) {
                call(c, port, "issue|bench|");
            }
            hsMed[round] = (System.nanoTime() - t) / 1e6 / hs;
            long u = System.nanoTime();
            for (int i = 0; i < dp; i++) {
                String p = DpopLab.proof(k, "GET", "https://api.bank.example/accounts", 1_767_225_600L, "x", null, false);
                Jose.Parts parts = Jose.parse(p);
                if (!Jose.rawVerify("ES256", k, parts.signingInput(), parts.sig())) {
                    throw new IllegalStateException("verify");
                }
            }
            dpMed[round] = (System.nanoTime() - u) / 1e6 / dp;
        }
        Arrays.sort(hsMed);
        Arrays.sort(dpMed);
        KbSupport.info("full TLS 1.3 handshake + client cert (P-256, loopback, both ends in one JVM): %.2f ms median of 5 rounds", hsMed[2]);
        KbSupport.info("ES256 DPoP proof: create + verify:                                          %.3f ms median of 5 rounds", dpMed[2]);
        KbSupport.info("note: with connection reuse (HTTP keep-alive, HTTP/2) mTLS pays the handshake once per connection,");
        KbSupport.info("      DPoP pays the proof on every request; both are far below a typical API's own latency.");
        KbSupport.check("both timings measured (positive, finite)", hsMed[2] > 0 && dpMed[2] > 0 && hsMed[2] < 10_000);
        KbSupport.verdict();
    }
}
```

<!-- output:MtlsBindingLab.java -->
```text

== Token endpoint: bind the access token to the handshake certificate (RFC 8705 section 3)
  fintech-a over mTLS -> token issued, cnf.x5t#S256 = SHA-256 of the handshake certificate (43 chars)

== Resource server, container-terminated mTLS (Spring's X509CertificateThumbprintValidator)
  1 fintech-a presents its own token                               -> 200
  2 fintech-b (same CA!) presents the stolen token                 -> 401 Invalid SHA-256 Thumbprint for X509Certificate.
  3 no client certificate on the connection                        -> 401 Unable to obtain X509Certificate from current request.

== Behind a TLS-terminating proxy: the certificate arrives in a header
  4 L5: attacker, no cert, header = fintech-a's (public) cert      -> 200
  5 L7: attacker with cert B + forged header = cert A              -> 401 Invalid SHA-256 Thumbprint for X509Certificate.
  6 L7: attacker, no cert, forged header = cert A                  -> 401 Unable to obtain X509Certificate from current request.
  7 L7: real request via the LB (LB-to-RS mTLS, LB sets header)    -> 200
  [PASS] container mTLS: the owner passes; a stolen token fails even with another CA-issued cert; no cert fails closed
  [PASS] L5 header trust: a copied PUBLIC certificate in a header defeats the binding
  [PASS] L7: the header counts only on the load balancer's own mTLS connection

verdict: OK (3 checks)
```

<!-- measured-output:MtlsBindingLab.java bench -->
```text
  full TLS 1.3 handshake + client cert (P-256, loopback, both ends in one JVM): 14.08 ms median of 5 rounds
  ES256 DPoP proof: create + verify:                                          0.759 ms median of 5 rounds
  note: with connection reuse (HTTP keep-alive, HTTP/2) mTLS pays the handshake once per connection,
        DPoP pays the proof on every request; both are far below a typical API's own latency.
  [PASS] both timings measured (positive, finite)

verdict: OK (1 checks)
```

Reading the run:
- **Case 2 is the reason to bind tokens even with client authentication.** fintech-b is a legitimate partner with a certificate from the same CA. Client authentication would let it in; the binding stops it using fintech-a's token.
- **Case 3 is a fail-closed default worth keeping.** Spring's validator returns "Unable to obtain X509Certificate from current request." when the container saw no client certificate. That is also exactly what happens the day someone moves TLS termination to a load balancer.
- **Case 4 is the L5 deployment.** Tomcat's `SSLValve`, nginx `ssl_client_escaped_cert` → header, or an ingress annotation all fill `jakarta.servlet.request.X509Certificate` from a header [E]. If the app is reachable without passing the LB, or the LB forwards a client-supplied copy of that header, the binding is decorative.
- **Cost.** The handshake is paid once per connection. DPoP is paid on every request, but about 0.7 ms against tens of ms of API work [M, E]. Choose on deployment topology, not on CPU (§7).

---

## 7. mTLS vs DPoP: the decision

| Dimension | mTLS (RFC 8705) | DPoP (RFC 9449) |
|---|---|---|
| Proof location | TLS handshake (transport) | HTTP header per request (application) |
| Survives TLS termination at LB/CDN | ⚠ only with an authenticated LB→app channel or a mesh | ✓ end to end through any proxy |
| Browser/SPA clients | ✗ client certificates in browsers are unusable UX | ✓ WebCrypto non-extractable keys (but XSS can *use* them; see file 03) |
| Mobile/native | ⚠ possible; certificate provisioning is hard | ✓ key in Secure Enclave / StrongBox |
| Server-to-server (FAPI, open banking) | ✓ natural; often also the client authentication | ✓ fine; plus `private_key_jwt` client auth |
| Replay protection | inherent (TLS) | needs `jti` store + `iat` window (+ nonce for pre-generation) |
| Per-request cost | none after handshake | about 0.7 ms ES256 create + verify [M] |
| Key rotation | certificate re-issuance; old tokens break | new key = new tokens; refresh binds the new key (confidential) |
| Binds refresh tokens (public clients) | n/a | yes (§5), if the AS enforces it (L29) |
| Binds authorization codes | client auth at token endpoint | `dpop_jkt` (§10); not in SAS 7.1.2 |
| Spring Security 7.1.2 RS | ✓ `X509CertificateThumbprintValidator` in default JWT validators (servlet); ⚠ not in `createAtJwtValidator()` (Folder 07 file 03, L48) | ✓ servlet `dPoP()`; ✗ reactive |
| Spring Authorization Server 7.1.2 | ✓ `tls_client_auth`, `self_signed_tls_client_auth`, `x509CertificateBoundAccessTokens` | ⚠ optional per request; no `dpop_jkt`; refresh downgrade (L29) |

The L7 position [E]:
- **Server-to-server inside a regulated ecosystem** with its own PKI (open banking, payment networks): mTLS for both client authentication and binding. TLS terminates at the AS/RS, or at a sidecar that forwards over an authenticated channel.
- **Everything that crosses CDNs, browsers or mobile devices:** DPoP, with a shared `jti` store, server nonces, `dpop_jkt`, and an AS that *requires* proofs.
- **Never "sender-constrained in name only."** Measure the binding by sending a stolen-token test (L26 case 4, L28 case 2, L29 case 3) in CI against every RS.

---

## 8. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 - DO NOT USE: "we support DPoP" - in name only.
http.oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()));        // reactive gateway in front: no DPoP at all
// AS: DPoP optional per request; public-client refresh without proof -> Bearer (L29 case 3)
// mTLS: Tomcat SSLValve reads ssl_client_cert from ANY request header; app port reachable from the VPC
```

```java
// L7 - resource server (Spring Security 7.1.2, servlet): DPoP with FAPI algorithm policy and a cluster-wide replay cache.
@Bean
SecurityFilterChain api(HttpSecurity http, org.springframework.cache.Cache dpopJtiCache) throws Exception {
    DPoPProofReplayValidator replay = new DPoPProofReplayValidator(dpopJtiCache);   // Redis-backed: atomic putIfAbsent
    DPoPProofJwtDecoderFactory proofs = new DPoPProofJwtDecoderFactory();
    proofs.setJwtValidatorFactory(DPoPProofJwtDecoderFactory.createDefaultJwtValidatorFactory(
            List.of(replay, new SpringDpopLab.AlgPolicy(Set.of("ES256", "PS256")))));
    http.authorizeHttpRequests(a -> a.anyRequest().authenticated())
        .oauth2ResourceServer(o -> o
            .jwt(Customizer.withDefaults())
            .dPoP(Customizer.withDefaults())
            .withObjectPostProcessor(new ObjectPostProcessor<DPoPAuthenticationProvider>() {
                @Override
                public <O extends DPoPAuthenticationProvider> O postProcess(O provider) {
                    provider.setDPoPProofVerifierFactory(proofs);
                    return provider;
                }
            }));
    return http.build();
}
// + server.forward-headers-strategy=framework behind trusted proxies, so htu matches the public URL
// + a filter that requires the DPoP scheme for routes whose tokens must be bound (FAPI: no bearer at all)
```

```java
// L7 - authorization server: proofs required for bound grants and flagged clients (L29's decorator).
http.oauth2AuthorizationServer(as -> as                          // Spring Security 7.x: the merged SAS DSL
    .tokenEndpoint(t -> t.authenticationProviders(providers -> providers.replaceAll(p ->
        p instanceof OAuth2RefreshTokenAuthenticationProvider
            ? new SasDpopRefreshLab.RequireDpopOnRefresh(p, authorizationService) : p))));
// The same pattern for the authorization_code provider: require a proof when ClientSettings flags the client,
// and verify a dpop_jkt captured at PAR time (an authorization-request customizer) - not built into 7.1.2.
```

```yaml
# L7 - container-terminated mTLS for a certificate-bound resource server (Spring Boot)
server:
  ssl:
    bundle: api-tls
    client-auth: need
spring:
  ssl:
    bundle:
      pem:
        api-tls:
          keystore:
            certificate: classpath:tls/api.crt
            private-key: classpath:tls/api.key
          truststore:
            certificate: classpath:tls/partner-ca.crt
```

| Concern | L5 | L7 |
|---|---|---|
| Token type | bearer everywhere | DPoP or mTLS-bound; Bearer scheme refused for bound tokens |
| DPoP checks | signature + `jkt` | all 12 of §4.3 + `jti` store (shared) + nonce for browser clients |
| Proof algorithms | whatever the library accepts | ES256 / PS256 (/ EdDSA with a custom factory) |
| Replay cache | per node, default caps | shared, atomic `putIfAbsent`, sized per client class |
| `htu` behind proxies | broken, so "temporarily" disabled | forwarded headers from trusted proxies only |
| AS | DPoP optional; refresh downgrade | proofs required for bound grants and FAPI clients; `dpop_jkt` |
| mTLS behind LB | header from anyone | header only on LB's mTLS channel, inbound copies stripped, or termination at app/sidecar |
| Verification | trust the config | stolen-token tests in CI (L26-4, L28-2, L29-3) |

---

## 9. Real-world attack vectors & mitigations

### A1 · Bearer token replay from logs, proxies and caches

**Attack.** An A5-class attacker reads TLS-intercepting proxy logs, APM traces or crash dumps and replays the access token from anywhere.
**Wire signature.** The same token from new IPs, ASNs or TLS fingerprints within its lifetime.
**Root cause.** Bearer tokens.
**Mitigation.** Sender-constraining (mTLS or DPoP) and short lifetimes. Redact `Authorization` and `DPoP` headers in logs.
**Detection.** Token-use telemetry keyed by token hash × client fingerprint.

### A2 · DPoP proof replay and cross-node replay

**Attack.** The same attacker also has the proofs. It replays a proof within the `iat` window (L26 case 1), on another method or URL (case 2), or once on every RS node that keeps its own cache (L27 §4).
**Wire signature.** A repeated `jti` per `jkt`; proofs whose `htm`/`htu` don't match the request.
**Root cause.** No `jti` store, node-local stores, skipped `htm`/`htu`/`ath`.
**Mitigation.** A shared atomic `jti` store keyed by `jkt` + `jti`, retained until `iat` + window. All §4.3 checks. A short window.
**Detection.** Count rejected replays; alert on bursts per `jkt`.

### A3 · Proof pre-generation from XSS

**Attack.** Script injected into the SPA uses the non-extractable key to sign proofs dated hours ahead and exfiltrates them. They pass every §4.3 check when used later from the attacker's machine (L26 case 7).
**Wire signature.** Proofs whose `iat` sits at the edge of the window, from new networks; for an SPA, use after the tab has closed.
**Root cause.** Proof freshness is client-asserted.
**Mitigation.** Server-provided nonces (§8/§9) on RS and AS, which cost one round trip per rotation. For SPAs, a BFF (file 03), so no token or key lives in the browser at all.
**Detection.** `use_dpop_nonce` rates; proofs with valid signatures but stale nonces.

### A4 · Bearer downgrade at the resource server

**Attack.** The stolen DPoP-bound token is sent as `Authorization: Bearer`, with no proof (L26 case 4).
**Wire signature.** The Bearer scheme with a token that has `cnf.jkt`.
**Root cause.** An RS that accepts both schemes without checking the binding. ⚠ The Spring reactive stack in 7.1.2 has no DPoP support, so a WebFlux gateway in front of DPoP APIs accepts bound tokens as bearer [D].
**Mitigation.** Reject Bearer for bound tokens: servlet Spring does this in `BearerTokenAuthenticationFilter`. Put DPoP verification at every hop that authorizes, or terminate it at one hop and switch to an internal token (Folder 05).
**Detection.** Requests with the Bearer scheme whose introspection result carries `cnf`.

### A5 · Refresh-token DPoP downgrade at the authorization server

**Attack.** A public client's refresh token, bound by DPoP, is copied. The attacker refreshes without sending any DPoP header. Spring Authorization Server 7.1.2 skips the binding check and issues a Bearer token (L29 case 3).
**Wire signature.** `grant_type=refresh_token` without a `DPoP` header for a grant whose tokens were DPoP-bound.
**Root cause.** The binding check runs only `if (dPoPProof != null)`. RFC 9449 §5 says the binding "MUST be validated".
**Mitigation.** `RequireDpopOnRefresh` (L29) or an equivalent. Per-client "require DPoP". Refresh-token rotation with reuse detection for public clients (Folder 02).
**Detection.** Token responses with `token_type=Bearer` for clients and grants expected to be DPoP.

### A6 · Forwarded client-certificate header spoofing

**Attack.** Behind a TLS-terminating LB, the app accepts `X-Client-Cert` from any request. The attacker sends a copy of the victim's public certificate with the stolen token (L28 case 4).
**Wire signature.** Requests with the certificate header that did not traverse the LB, or that arrive with the header already set.
**Root cause.** A header treated as a proof.
**Mitigation.**
- The LB strips inbound copies and sets the header itself.
- The app accepts the header only on the LB's mTLS connection, pinning the LB's certificate (L28 case 7), or verifies a signature the LB adds.
- Alternatively, terminate at the app or a sidecar.

**Detection.** Network policy alerts on direct-to-app traffic; mismatches between the TLS peer and the claimed certificate.

### A7 · Self-inflicted denial of service from DPoP replay caches

**Attack.** No attacker is needed. A high-volume client's 1,001st proof in a 30-second window is refused (L27 §3), and the team switches DPoP off. Separately, an attacker holding many valid tokens can try to fill a 100,000-entry cache, after which every new proof is refused [D: `InMemoryCache`].
**Wire signature.** Bursts of `invalid_dpop_proof` "unable to cache" for legitimate clients.
**Root cause.** Default cache sizing.
**Mitigation.**
- A shared cache sized per client class.
- Per-key limits matched to contractual rates.
- Rate limits upstream of proof verification.
- Separate caches per tenant.

**Detection.** A cache-rejection metric split by reason (duplicate vs capacity).

---

## 10. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "We use JWTs with 5-minute expiry; why do we need sender-constrained tokens?"</b></summary>

**Initial Prompt.** A payments API team pushes back on DPoP.

**L5 Textbook Answer.** "Five minutes is short enough; the token is signed so it can't be forged."

**How an Attacker Bypasses L5.**
- **Signing stops forgery, not theft.** An A5 attacker reading proxy logs replays the token within seconds, and five minutes is enough to initiate payments.
- **Refresh tokens extend the window.** A stolen refresh token turns "five minutes" into "forever" (Folder 02).

**L7 Principal Defense.**
- **Bind the token** to a key: mTLS for partner server-to-server, DPoP across CDNs and mobile.
- **Verify the binding at every authorizing hop.**
- **Bind refresh tokens of public clients** (§3.5).
- **Keep expiry short anyway.**
- **Prove it with a stolen-token test in CI:** the same token from a different key or certificate must fail (L26 case 3, L28 case 2).

</details>

<details><summary><b>Q2 · Walk me through validating a DPoP proof at a resource server.</b></summary>

**Initial Prompt.** Whiteboard the RS-side checks.

**L5 Textbook Answer.** "Verify the JWT signature with the key in the header and check the thumbprint matches the token."

**How an Attacker Bypasses L5.** L26 shows this accepts 7 of 8 attacks: replay, method/URL swap, Bearer downgrade, token-endpoint proofs at the API, stale proofs, and leaked private keys.

**L7 Principal Defense.**
- **All twelve §4.3 checks:** one header, well-formed, required claims, `typ`, an asymmetric policy `alg`, signature, no private key, `htm`, a normalized `htu`, nonce, the `iat` window, and `ath` + `jkt`.
- **A shared atomic `jti` store.**
- **Bearer refused for bound tokens.**
- **Server nonces where clients may be compromised** (browsers).
- **`htu` computed from the public URL,** using forwarded headers from trusted proxies only.

</details>

<details><summary><b>Q3 · DPoP proofs are signed with a non-extractable WebCrypto key. Is XSS still a problem?</b></summary>

**Initial Prompt.** A SPA team says "the key can't be stolen, so DPoP makes XSS harmless".

**L5 Textbook Answer.** "Yes, non-extractable keys solve it."

**How an Attacker Bypasses L5.** The attacker doesn't need the key. Injected script calls `crypto.subtle.sign` with it, minting proofs dated in the future, exfiltrating them, and using them later from anywhere (L26 case 7). Or it simply makes API calls from inside the page.

**L7 Principal Defense.**
- **Server nonces** defeat pre-generation.
- **Nothing defeats in-page use while the XSS is live.**
- **So for SPAs the L7 answer is the BFF (file 03):** no access token or DPoP key in the browser, an HttpOnly session cookie, and the BFF holding DPoP-bound tokens server-side.
- **Plus CSP and Trusted Types** to make XSS rarer.

</details>

<details><summary><b>Q4 · mTLS-bound tokens work in staging and fail in production. Why?</b></summary>

**Initial Prompt.** Production has a cloud load balancer; staging doesn't.

**L5 Textbook Answer.** "Turn off certificate binding in production; mTLS at the LB is enough."

**How an Attacker Bypasses L5.** Without binding, a stolen token works from anywhere. With "fix #2" (trust `X-Client-Cert` from the LB), anyone who can reach the app directly, or send that header through the LB, presents a copy of a public certificate (L28 case 4).

**L7 Principal Defense.**
- **Diagnose:** Spring's validator says "Unable to obtain X509Certificate from current request" (L28 case 3), because the container no longer sees the handshake.
- **Fix options:**
  - TLS passthrough to the app or a sidecar;
  - the LB re-originates mTLS to the app, the app trusts the header only on that channel (pinned LB certificate, L28 case 7), and the LB strips inbound copies;
  - or switch to DPoP, which survives termination.
- **Network policy:** the app port is unreachable except from the LB.

</details>

<details><summary><b>Q5 · Your Spring resource server starts rejecting a partner's DPoP calls at peak. What happened?</b></summary>

**Initial Prompt.** The errors say `invalid_dpop_proof`, "jti claim is invalid or unable to cache".

**L5 Textbook Answer.** "Clock skew. Increase the window."

**How an Attacker Bypasses L5.** Widening the window widens the replay window and doesn't fix it, because the cause is capacity.

**L7 Principal Defense.**
- **Diagnose:** `DPoPProofReplayValidator.InMemoryCache` allows 1,000 live proofs per key, and entries live `iat` + 30 s (L27 §3: the 1,001st legitimate proof is refused). The partner runs about 40 requests/s on one key.
- **Fix:**
  - a shared cache (atomic `putIfAbsent`) sized per client class, with `setMaxRequestsPerKey` set to the contracted rate plus margin;
  - metrics that separate "duplicate" from "capacity";
  - rate limiting before verification.
- **Don't** widen `iat` beyond the FAPI bounds (accept up to 10 s future, reject more than 60 s future).

</details>

<details><summary><b>Q6 · A pentester says your AS "downgrades DPoP". Explain and fix.</b></summary>

**Initial Prompt.** Spring Authorization Server 7.1.2, public TV app, device grant with DPoP.

**L5 Textbook Answer.** "Not possible: refresh tokens are bound to the key; Spring checks it."

**How an Attacker Bypasses L5.** Spring checks the key *if a proof is present*. Send the refresh request with no `DPoP` header and you get `token_type=Bearer` with no `cnf` (L29 case 3), usable at every RS as a plain bearer token, indefinitely with refresh-token reuse.

**L7 Principal Defense.**
- **Require a proof** whenever the grant is bound (the current access token has `cnf.jkt`) or the client is flagged: the `RequireDpopOnRefresh` decorator, installed via `tokenEndpoint().authenticationProviders(...)`.
- **Turn on refresh-token rotation with reuse detection** for public clients.
- **Add a contract test.**
- **Report it** through the vendor's security policy.

</details>

<details><summary><b>Q7 · How does FAPI 2.0 change your sender-constraining design?</b></summary>

**Initial Prompt.** The regulator mandates FAPI 2.0 Security Profile.

**L5 Textbook Answer.** "Add DPoP to the API."

**How an Attacker Bypasses L5.** FAPI requires the AS to *only* issue sender-constrained tokens. An AS where DPoP is optional (L29 case 4) issues bearer tokens to anyone who omits the header. FAPI also requires `dpop_jkt` support, `iat` acceptance bounds, PS256/ES256/EdDSA only, and nonce support in clients.

**L7 Principal Defense.** A conformance matrix per component:
- **AS:** proofs required per client; `dpop_jkt` honoured from PAR; nonce optional; algorithm allow-list; authorization-code lifetime ≤ 60 s.
- **RS:** DPoP or mTLS only, Bearer refused, all §4.3 checks, shared `jti` store.
- **Client:** nonce support, `mtls_endpoint_aliases`.

Then run the OpenID Foundation FAPI 2.0 conformance suite in CI.

</details>

<details><summary><b>Q8 · Where should DPoP be verified in a microservice estate?</b></summary>

**Initial Prompt.** Gateway → 30 services.

**L5 Textbook Answer.** "At the gateway; then forward the token."

**How an Attacker Bypasses L5.**
- **Forwarding the bound token internally** means every service either re-verifies DPoP, which needs the client's proof for *its* `htu` (impossible), or accepts it as bearer.
- **Internally the token is a bearer token again,** so an A5 attacker inside the mesh (logs, a compromised service) replays it.

**L7 Principal Defense.**
- **Verify DPoP at the edge.**
- **Exchange the external token for an internal, audience-restricted, short-lived token** (RFC 8693 token exchange, Folder 05), bound to the calling workload's identity: mTLS/SPIFFE between services.
- **Never forward the external DPoP token past the edge.**

</details>

<details><summary><b>Q9 · Why does DPoP need `ath` if the token is already bound by `cnf.jkt`?</b></summary>

**Initial Prompt.** A reviewer wants to drop `ath` to simplify clients.

**L5 Textbook Answer.** "The `jkt` binding is enough."

**How an Attacker Bypasses L5.** Without `ath`, a proof isn't tied to a particular token. The attacker pairs any captured proof from the same key, including one from a token request (L26 case 5), with any token bound to that key, for example after the client obtained a broader-scoped token.

**L7 Principal Defense.**
- **Require `ath`** on every resource request (RFC 9449 §4.3 check 12).
- **Spring enforces it** when an access token is present ("ath claim is required.", L27 case f).
- **`htm`/`htu`** bind the proof to the request.
- **`ath`** binds it to the token.
- **`jti`** makes it single-use.

</details>

<details><summary><b>Q10 · How do you roll out DPoP to 200 existing clients without an outage?</b></summary>

**Initial Prompt.** All clients use bearer tokens today.

**L5 Textbook Answer.** "Flip the RS to DPoP-only on a date."

**How an Attacker Bypasses L5.** It doesn't. A flag day causes an outage, the rollback is "accept both forever", and attackers simply use Bearer.

**L7 Principal Defense.**
1. **Phase 1:** the AS issues DPoP-bound tokens to clients that send proofs. RSs accept both, but reject Bearer for bound tokens (§7.2).
2. **Phase 2:** per-client "require DPoP" at the AS (L29 decorator), client by client.
3. **Phase 3:** RSs refuse the Bearer scheme for scopes or clients past their deadline.

Throughout: dashboards of bound vs bearer usage per client; stolen-token tests; shared `jti` store and sizing before phase 1.

</details>

---

## 11. Invariants checklist

- [ ] The AS issues only sender-constrained tokens to FAPI clients; DPoP is **required** per client, not optional per request.
- [ ] Public-client refresh tokens are bound and a proof is **required** on every refresh (L29); refresh rotation with reuse detection.
- [ ] `dpop_jkt` captured at PAR and enforced at code redemption (custom in Spring Authorization Server 7.1.2).
- [ ] The RS performs all 12 §4.3 checks; `jti` store is shared, atomic and sized; Bearer refused for bound tokens.
- [ ] Proof algorithms restricted to ES256/PS256 (/EdDSA); `iat` accepted from −window to +10 s, never beyond +60 s.
- [ ] Server-provided nonces for browser-reachable clients; or, better, no tokens in the browser (BFF).
- [ ] `htu` computed from the public URL (forwarded headers from trusted proxies only).
- [ ] mTLS terminates where the binding is checked, or the forwarded certificate is trusted only on the LB's authenticated channel and stripped on ingress.
- [ ] Certificate rotation procedure re-binds tokens; old certificate kept until tokens expire.
- [ ] Stolen-token tests (other key, other certificate, no proof, Bearer scheme) run in CI against every RS and the AS.

---

## 12. References

- RFC 9449 *OAuth 2.0 Demonstrating Proof of Possession (DPoP)* — <https://www.rfc-editor.org/rfc/rfc9449>
- RFC 8705 *OAuth 2.0 Mutual-TLS Client Authentication and Certificate-Bound Access Tokens* — <https://www.rfc-editor.org/rfc/rfc8705>
- RFC 7638 *JSON Web Key (JWK) Thumbprint* — <https://www.rfc-editor.org/rfc/rfc7638>
- FAPI 2.0 Security Profile (Final, 22 Feb 2025) — <https://openid.net/specs/fapi-security-profile-2_0-final.html> · Attacker Model — <https://openid.net/specs/fapi-attacker-model-2_0-final.html>
- Spring Security reference, *OAuth 2.0 Resource Server: DPoP-bound Access Tokens* — <https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/dpop-tokens.html>
- Spring Authorization Server reference — <https://docs.spring.io/spring-authorization-server/reference/>
- OpenID Foundation conformance suite (FAPI 2.0 tests) — <https://openid.net/certification/>
- Spring Security security policy (reporting vulnerabilities) — <https://spring.io/security-policy>
