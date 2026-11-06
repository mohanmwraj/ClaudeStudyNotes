# Browser SPA Security (RFC 10017): Why localStorage Fails, and the BFF / Token-Handler Pattern

> Folder 04 · File 03 of 03 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [02 · FAPI 2.0, PAR, JAR, JARM, RAR](02-fapi-2-security-profile-par-rfc9126-jar-jarm-and-rich-authorization-requests-rar.md) · First: [01 · mTLS vs DPoP](01-sender-constrained-tokens-mtls-rfc8705-vs-dpop-rfc9449-proof-of-possession.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L32 `BrowserTokenLab.java` | Six browser architectures, modelled as a few properties: localStorage, memory, Web Worker, DPoP, a token-mediating backend, and a BFF. The four RFC 10017 attack scenarios are functions of those properties, and the derived matrix reproduces the RFC's eight cited conclusions:<br>• every browser-only client, **DPoP included**, loses to the silent-flow acquisition of new tokens, so the attacker keeps **24 h** of access after the XSS is fixed;<br>• the token-mediating backend leaks access tokens (at most 5 min);<br>• the BFF leaves only live proxying | RFC 10017 §5.1, §6.1.4, §6.2.4, §6.3.4, §8 (fixture) |
| L33 `BffTokenHandlerLab.java` | The BFF from its parts:<br>• five session cookies against §6.1.3.2, where only `__Host-Http-` + Secure + HttpOnly + SameSite=Strict + Path=/ passes;<br>• a browser model (SameSite + CORS preflight) in which SameSite=Lax loses 2 CSRF attempts and Strict alone loses 1 (a taken-over sibling subdomain), while Strict + required custom header + CORS loses none;<br>• AES-256-GCM sealed sessions with the cookie name in the AAD and key rotation, where one token set fits in 2,009 B and three audience tokens need 4,150 B, over the 4,096 B floor;<br>• the token handler shows the page no token;<br>• a path-driven proxy sends the token to an attacker host, and an allow-list doesn't | RFC 10017 §6.1.3.2, §6.1.3.3, §6.1.3.6 (fixture) |

**Verification.** Compiled with Folders 01–04 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs both outputs and requires them byte-identical. All sizes are deterministic: fixed claims, a 64-byte ES256 signature, and a fixed GCM overhead. Normative text is quoted from RFC 10017 (BCP 212, August 2026) in [`fixtures/`](fixtures/).

Spring facts marked [D] were read from 7.1.2 sources:
- `CsrfConfigurer.spa()`, since 7.0;
- `OAuth2ClientHttpRequestInterceptor` and `RequestAttributeClientRegistrationIdResolver`;
- the absence of any DPoP support in `spring-security-oauth2-client`.

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

Every argument about "where should the SPA keep its tokens" is really about one fact: **XSS is attacker code running in the application's origin.** That code can do anything the app can:
- read any storage the app can read;
- call any API the app can call;
- start a new OAuth flow that is "indistinguishable from a legitimate Authorization Code flow" [D: RFC 10017 §5.1.3].

RFC 10017 (Browser-Based Apps BCP 212, August 2026) turned a decade of debate into a threat analysis with a conclusion. The BFF is "strongly recommended for business applications, sensitive applications, and applications that handle personal data". A browser-only OAuth client "is not recommended" for them [D: §6.1.4.3, §6.3.4.3].

Results:
- **[M] Storage choice doesn't decide the outcome (L32).**
  - localStorage, memory, a Web Worker that isolates the refresh token, and even DPoP with a non-extractable key differ in what an XSS can *steal*.
  - All of them lose to **acquisition of new tokens**: a hidden-iframe silent flow whose code the attacker redeems as the same public client. Even with DPoP, "the attacker can bind the fresh set of tokens to a key pair under their control" [D: §6.3.4.2.2].
  - That family is independent of the app's tokens, so refresh rotation and reuse detection never see it: **24 h** of attacker access after the XSS is fixed.
- **[M] Only a confidential backend stops new-token acquisition.** The attacker can get a code but can't redeem it without the client credentials. With a token-mediating backend, the access tokens in the browser still leak, at most 5 min after the fix. With a BFF, the attacker can only proxy requests while the XSS runs.
- **[M] A BFF is a cookie-authenticated proxy, so its security is cookies, CSRF and routing (L33).**
  - **Cookies:** `__Host-Http-` + Secure + HttpOnly + SameSite=Strict + Path=/ (§6.1.3.2).
  - **CSRF:** SameSite=Strict alone is not enough when a sibling subdomain can be taken over, because it is the same *site* (§6.1.3.3.1). Require a custom header so cross-origin calls need a CORS preflight (§6.1.3.3.2).
  - **Routing:** an exact allow-list of upstreams. The BFF "MUST enforce strict outbound request controls" (§6.1.3.6), and a path-driven proxy forwards the user's token to an attacker host.
- **[M] Client-side sealed sessions work but don't scale.** One token set (access token, ID token, refresh token) seals to 2,009 B. One access token per audience (RFC 8707) pushes it to 4,150 B, past the 4,096-byte floor browsers guarantee. Prefer server-side sessions. If you seal, use AEAD with the cookie name in the AAD and a key ring [E].
- **[D] Spring Security 7.1.2 covers the BFF well.**
  - It provides `oauth2Login` as a confidential client, `oauth2Client`, `OAuth2ClientHttpRequestInterceptor` for token relay with `RestClient`, `csrf(c -> c.spa())` (double-submit cookie, since 7.0), CORS and the Boot session-cookie properties.
  - It has **no client-side DPoP**, so a Spring BFF's tokens are bearer tokens unless you add binding. Bind with mTLS to the RS, or add DPoP with a custom request interceptor.
  - Spring Cloud Gateway's `TokenRelay` version is in Folder 07.

---

## 1. First principles: what XSS can do, in RFC 10017's terms

```text
  Attacker code runs in https://app.example.com (stored XSS, compromised npm package, injected CDN script)

  5.1.1 single-execution token theft   read tokens the app holds right now  -> exfiltrate AT/RT once
  5.1.2 persistent token theft         keep a hook, steal every new token   -> long-term RT abuse
  5.1.3 acquisition of NEW tokens      hidden iframe: /authorize?prompt=none on the user's AS session
                                       -> code lands on a same-origin redirect URI the attacker can read
                                       -> attacker redeems it as the same PUBLIC client -> fresh AT + RT
  5.1.4 proxying via the browser       call APIs from inside the page with whatever the app uses
                                       (tokens or cookies): works against EVERY architecture while XSS lives

  consequences: 5.2.1 stolen RT abuse · 5.2.2 stolen AT abuse · 5.2.3 client hijacking
```

The architecture determines which scenarios are possible [D: §6]:

```text
  where do tokens live?                          JS can read AT?  JS can read RT?  client type   5.1.3 possible?
  ------------------------------------------------------------------------------------------------------------
  Browser OAuth client (localStorage/memory)     yes              yes              public        YES
  Browser client + Web Worker RT isolation       yes (AT given)   no               public        YES
  Browser client + DPoP (non-extractable key)    yes, but bound   yes, but bound   public        YES (own key)
  Token-mediating backend (RT on server)         yes              no               confidential  no
  BFF (all tokens on server, cookie session)     no               no               confidential  no
```

The key line is 5.1.3. "Even if the application finds a token storage mechanism that is able to completely isolate the stored tokens from the attacker, the attacker will still be able to request a new set of tokens" [D: §5.1.3]. Short lifetimes and rotation are "ineffective, since the attacker has a fresh, independent set of tokens". DPoP is "equally ineffective".

---

## 2. Why localStorage fails, and why the alternatives don't save a browser-only client

[D: RFC 10017 §8]:
- **localStorage.** It "does not protect against unauthorized access from malicious JavaScript". It is shared across tabs, persistent, and on disk unencrypted (§8.6: browser storage has no encryption-at-rest guarantee, and infostealer malware harvests browser profiles).
- **sessionStorage.** The same, scoped to one tab.
- **IndexedDB.** The same, and also shared with service workers.
- **JS-set cookies.** Holding tokens there is "NOT RECOMMENDED" (§8.1). The browser also sends them to the server on every request, so you get the worst of both.
- **Memory (closures).** These limit exposure to the running page. However, "using prototype poisoning, an attacker can substitute these functions" that the closure relies on, such as `fetch` or `toString`, and read the token as it passes [§8.4].
- **Web Worker / Service Worker.** These really isolate tokens from the page, but "the use of a Service Worker does not prevent an attacker from obtaining a new set of tokens" (§8.2). A service worker also has no isolated persistent storage.
- **DPoP with a non-extractable key.** Stolen tokens become useless off-device (§6.3.4.2.2), which is real value. But the attacker gets new tokens bound to their own key (5.1.3), or uses the page's key in place (file 01, L26 case 7).

⚠ The L5 conversation is "localStorage vs memory vs cookies". The L7 conversation is "public vs confidential client". For anything sensitive, the answer is a backend that holds the tokens [E].

---

## 3. The architectures RFC 10017 describes

### 3.1 BFF (§6.1)

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser (SPA)
    participant F as BFF (confidential client)
    participant AS as Authorization server
    participant RS as Resource server
    B->>F: GET /bff/session (cookie?)
    F-->>B: 401 not logged in
    B->>F: navigate /oauth2/authorization/bank
    F-->>B: 302 to AS /authorize (PAR, PKCE S256)
    B->>AS: authenticate (passkey) and consent
    AS-->>B: 302 /login/oauth2/code/bank?code&iss
    B->>F: code
    F->>AS: POST /token (private_key_jwt, code_verifier[, DPoP])
    AS-->>F: AT (+ RT, ID token): kept server-side
    F-->>B: Set-Cookie __Host-Http-bff=<session id>; Secure; HttpOnly; SameSite=Strict; Path=/
    B->>F: POST /api/payments (cookie + X-BFF-CSRF: 1)
    F->>F: session -> AT; refresh if expired; route allow-list
    F->>RS: POST /payments Authorization: DPoP AT (+ proof)
    RS-->>F: 201
    F-->>B: 201 (body only; no tokens, no upstream auth headers)
```

The BFF's endpoints [D: §6.1.2.1]:
- a "check session" API;
- a login endpoint, reached by navigation, that starts the code flow;
- the redirect endpoint;
- logout.

Its refresh tokens stay server-side, are used with client authentication, and the session lifetime should equal the refresh token's maximum lifetime (§6.1.2.2). The pattern is "significantly more complicated" to operate, and "the only viable attack pattern is hijacking the client application in the user's browser -- a problem inherent to web applications" [D: §6.1.4.3].

### 3.2 Token-mediating backend (§6.2) and browser-only client (§6.3)

- **The token-mediating backend** runs the OAuth flow as a confidential client, keeps the refresh token, and hands access tokens to the browser. It stops 5.1.3 and refresh-token theft, but "the attacker still has the ability to gain direct access to resource servers" with stolen access tokens. RFC 10017 says to consider it "only when the use cases or system requirements would prevent the use of a proxying BFF" [D: §6.2.4.4].
- **The browser-only client** is acceptable for low-risk apps with public data. It uses PKCE, exact redirect URIs, refresh rotation or short sessions, and DPoP. It is "not recommended for business applications" [D: §6.3.4.3].
- **Deprecated** [D: §7]:
  - the implicit grant;
  - ROPC;
  - handling the OAuth flow in a service worker;
  - single-domain apps that skip OAuth when they need delegated access.

---

## 4. L32: the RFC 10017 threat matrix, derived

<!-- listing:BrowserTokenLab.java -->
```java
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * L32 - what an XSS attacker gets from six browser architectures, derived from first principles and checked against
 * RFC 10017 (OAuth 2.0 for Browser-Based Applications, BCP 212).
 *
 * <p>Each architecture is a handful of properties (can the page's JavaScript read the access token / refresh token?
 * are tokens bound to a browser key? is the OAuth client public?). RFC 10017's four attack scenarios (section 5.1)
 * are functions of those properties. The derived matrix must reproduce the RFC's own threat-analysis conclusions,
 * which are cited verbatim. Then: how long does the attacker keep access after the XSS is fixed?
 */
public final class BrowserTokenLab {

    record Arch(String name, boolean atReadable, boolean rtReadable, boolean bound, boolean publicClient, boolean rotationWithReuseDetection) {
    }

    record Outcome(boolean stealAt, boolean stealRt, boolean newTokens, boolean proxy, String afterFix) {
    }

    /** RFC 10017 section 5.1, as functions of the architecture. XSS live from t=0 to t=10 min; AT 5 min; RT 24 h. */
    static Outcome attack(Arch a) {
        boolean stealAt = a.atReadable() && !a.bound();          // 5.1.1 / 5.1.2: exfiltrated AT usable from the attacker's machine
        boolean stealRt = a.rtReadable() && !a.bound();          // ... and the refresh token
        boolean newTokens = a.publicClient();                    // 5.1.3: silent flow in a hidden iframe; code exchanged by the attacker
        boolean proxy = true;                                    // 5.1.4: always, while the XSS runs
        String afterFix;
        if (newTokens) {
            afterFix = "24 h (an independent token family: rotation and reuse detection never see it)";
        } else if (stealRt) {
            afterFix = a.rotationWithReuseDetection() ? "until the app's next refresh (<= 5 min), then the family is revoked" : "24 h";
        } else if (stealAt) {
            afterFix = "<= 5 min (the stolen access token's remaining lifetime)";
        } else {
            afterFix = "0 (only proxying, which ends with the XSS)";
        }
        return new Outcome(stealAt, stealRt, newTokens, proxy, afterFix);
    }

    static String yn(boolean b) {
        return b ? "YES" : "no";
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String rfc = KbSupport.rfc(fx, "rfc10017.txt");

        KbSupport.section("RFC 10017's conclusions (fixture)");
        String[][] cites = {
            {"The only viable attack pattern is hijacking the client application in the user's browser", "BFF, 6.1.4.3"},
            {"This architecture is strongly recommended for business applications, sensitive applications, and applications that handle personal data", "BFF, 6.1.4.3"},
            {"Single-Execution Token Theft (Section 5.1.1) for refresh tokens", "token-mediating backend, 6.2.4.2"},
            {"the attacker still has the ability to gain direct access to resource servers", "token-mediating backend, 6.2.4.4"},
            {"This architecture is not recommended for business applications, sensitive applications, and applications that handle personal data", "browser client, 6.3.4.3"},
            {"Even when DPoP is mandatory, the attacker can bind the fresh set of tokens to a key pair under their control", "6.3.4.2.2"},
            {"localStorage does not protect against unauthorized access from malicious JavaScript", "8.5"},
            {"even a token storage mechanism that completely isolates the tokens from the attacker does not prevent the attacker from running a new flow", "6.3.4.2.1"}};
        for (String[] c : cites) {
            KbSupport.mustCite(rfc, c[0], c[1]);
        }

        KbSupport.section("Six architectures under an XSS that runs from t=0 to t=10 min (AT 5 min, RT 24 h)");
        List<Arch> archs = List.of(
            new Arch("SPA, tokens in localStorage", true, true, false, true, false),
            new Arch("SPA, tokens in memory (closure)", true, true, false, true, true),
            new Arch("SPA, refresh token isolated in a Web Worker", true, false, false, true, true),
            new Arch("SPA + DPoP (non-extractable key in IndexedDB)", true, true, true, true, true),
            new Arch("token-mediating backend (AT to browser)", true, false, false, false, true),
            new Arch("BFF (no tokens in the browser)", false, false, false, false, true));
        Map<String, Outcome> out = new LinkedHashMap<>();
        KbSupport.info("%-48s %-9s %-9s %-11s %-8s %s", "architecture", "steal AT", "steal RT", "new tokens", "proxy", "attacker access after the XSS is fixed");
        for (Arch a : archs) {
            Outcome o = attack(a);
            out.put(a.name(), o);
            KbSupport.info("%-48s %-9s %-9s %-11s %-8s %s", a.name(), yn(o.stealAt()), yn(o.stealRt()), yn(o.newTokens()), yn(o.proxy()), o.afterFix());
        }
        Outcome bff = out.get("BFF (no tokens in the browser)");
        Outcome tmb = out.get("token-mediating backend (AT to browser)");
        Outcome dpop = out.get("SPA + DPoP (non-extractable key in IndexedDB)");
        Outcome worker = out.get("SPA, refresh token isolated in a Web Worker");
        KbSupport.check("BFF: nothing to steal and no silent flow; only proxying remains (RFC 10017 6.1.4.2-6.1.4.3)",
                !bff.stealAt() && !bff.stealRt() && !bff.newTokens() && bff.proxy());
        KbSupport.check("token-mediating backend: refresh tokens safe, access tokens still stolen (6.2.4.2, 6.2.4.4)",
                !tmb.stealRt() && !tmb.newTokens() && tmb.stealAt());
        KbSupport.check("every browser-only client loses to the silent-flow acquisition of NEW tokens, storage isolation or not (6.3.4.1, 6.3.4.2.1)",
                archs.stream().filter(Arch::publicClient).allMatch(a -> out.get(a.name()).newTokens()) && !worker.stealRt());
        KbSupport.check("DPoP stops exfiltration of the app's tokens but not new tokens bound to the attacker's key (6.3.4.2.2)",
                !dpop.stealAt() && !dpop.stealRt() && dpop.newTokens());
        KbSupport.check("only the confidential-client architectures end the attacker's access within minutes of the fix",
                bff.afterFix().startsWith("0") && tmb.afterFix().startsWith("<= 5 min")
                        && archs.stream().filter(Arch::publicClient).allMatch(a -> out.get(a.name()).afterFix().startsWith("24 h")));
        KbSupport.verdict();
    }
}
```

<!-- output:BrowserTokenLab.java -->
```text

== RFC 10017's conclusions (fixture)
  [PASS] constant cited verbatim from fixture: BFF, 6.1.4.3
  [PASS] constant cited verbatim from fixture: BFF, 6.1.4.3
  [PASS] constant cited verbatim from fixture: token-mediating backend, 6.2.4.2
  [PASS] constant cited verbatim from fixture: token-mediating backend, 6.2.4.4
  [PASS] constant cited verbatim from fixture: browser client, 6.3.4.3
  [PASS] constant cited verbatim from fixture: 6.3.4.2.2
  [PASS] constant cited verbatim from fixture: 8.5
  [PASS] constant cited verbatim from fixture: 6.3.4.2.1

== Six architectures under an XSS that runs from t=0 to t=10 min (AT 5 min, RT 24 h)
  architecture                                     steal AT  steal RT  new tokens  proxy    attacker access after the XSS is fixed
  SPA, tokens in localStorage                      YES       YES       YES         YES      24 h (an independent token family: rotation and reuse detection never see it)
  SPA, tokens in memory (closure)                  YES       YES       YES         YES      24 h (an independent token family: rotation and reuse detection never see it)
  SPA, refresh token isolated in a Web Worker      YES       no        YES         YES      24 h (an independent token family: rotation and reuse detection never see it)
  SPA + DPoP (non-extractable key in IndexedDB)    no        no        YES         YES      24 h (an independent token family: rotation and reuse detection never see it)
  token-mediating backend (AT to browser)          YES       no        no          YES      <= 5 min (the stolen access token's remaining lifetime)
  BFF (no tokens in the browser)                   no        no        no          YES      0 (only proxying, which ends with the XSS)
  [PASS] BFF: nothing to steal and no silent flow; only proxying remains (RFC 10017 6.1.4.2-6.1.4.3)
  [PASS] token-mediating backend: refresh tokens safe, access tokens still stolen (6.2.4.2, 6.2.4.4)
  [PASS] every browser-only client loses to the silent-flow acquisition of NEW tokens, storage isolation or not (6.3.4.1, 6.3.4.2.1)
  [PASS] DPoP stops exfiltration of the app's tokens but not new tokens bound to the attacker's key (6.3.4.2.2)
  [PASS] only the confidential-client architectures end the attacker's access within minutes of the fix

verdict: OK (13 checks)
```

Reading the run:
- **The "new tokens" column is the decision.** Every architecture with a public client says YES, and no amount of storage engineering flips it.
- **The last column turns the matrix into a number a risk committee understands.** It shows how long the attacker keeps access after the incident is closed.
  - **Public clients: 24 h**, the refresh-token lifetime of the attacker's own family.
  - **Token-mediating backend: minutes**, the remaining access-token lifetime.
  - **BFF: zero.**
- **Proxying (5.1.4) is YES everywhere.** A BFF doesn't make XSS harmless. It makes XSS *bounded in time*. CSP, Trusted Types and dependency hygiene still matter [E].

---

## 5. The BFF in detail: cookies, CSRF, session state, routing (L33)

<!-- listing:BffTokenHandlerLab.java -->
```java
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * L33 - the Backend-for-Frontend (RFC 10017 section 6.1) built from its parts: the session cookie rules of section
 * 6.1.3.2 applied to five real-world Set-Cookie headers; a browser model (SameSite, CORS preflight) against the CSRF
 * defences of section 6.1.3.3, including the same-site sibling-subdomain case; AES-256-GCM sealed client-side
 * sessions with key rotation, and whether tokens even fit in a cookie; and the token-handler proxy that keeps every
 * token out of the browser.
 */
public final class BffTokenHandlerLab {
    static final String APP = "https://app.example.com";
    static final SecureRandom RNG = new SecureRandom();

    // ------------------------------------------------------------------ 1. cookie rules

    static Map<String, String> attrs(String setCookie) {
        Map<String, String> m = new LinkedHashMap<>();
        String[] parts = setCookie.split(";");
        m.put("$name", parts[0].substring(0, parts[0].indexOf('=')).trim());
        for (int i = 1; i < parts.length; i++) {
            String p = parts[i].trim();
            int eq = p.indexOf('=');
            m.put((eq < 0 ? p : p.substring(0, eq)).toLowerCase(Locale.ROOT), eq < 0 ? "" : p.substring(eq + 1));
        }
        return m;
    }

    /** RFC 10017 section 6.1.3.2 (MUST / SHOULD), plus the cookie-prefix rule browsers enforce for __Host-. */
    static List<String> violations(String setCookie) {
        Map<String, String> a = attrs(setCookie);
        String name = a.get("$name");
        List<String> v = new ArrayList<>();
        if (!a.containsKey("secure")) {
            v.add("MUST Secure");
        }
        if (!a.containsKey("httponly")) {
            v.add("MUST HttpOnly");
        }
        if (!"strict".equalsIgnoreCase(a.getOrDefault("samesite", ""))) {
            v.add("SHOULD SameSite=Strict (has " + a.getOrDefault("samesite", "none set") + ")");
        }
        if (!"/".equals(a.get("path"))) {
            v.add("SHOULD Path=/");
        }
        if (a.containsKey("domain")) {
            v.add("SHOULD NOT Domain");
        }
        if (!name.startsWith("__Host-Http-")) {
            v.add("SHOULD __Host-Http- prefix");
        }
        if (name.startsWith("__Host-") && (a.containsKey("domain") || !a.containsKey("secure") || !"/".equals(a.get("path")))) {
            v.add("browser REJECTS it: __Host- needs Secure, Path=/ and no Domain");
        }
        return v;
    }

    // ------------------------------------------------------------------ 2. browser model for CSRF

    static String site(String origin) {
        String host = origin.replaceFirst("https?://", "");
        String[] l = host.split("\\.");
        return l[l.length - 2] + "." + l[l.length - 1]; // eTLD+1 for these example hosts
    }

    record Req(String label, String from, String method, boolean topLevelNav, boolean customHeader, boolean attack) {
    }

    record Policy(String name, String sameSite, boolean requireHeader, Set<String> corsAllow) {
    }

    /** Does the state-changing request reach the BFF with the session cookie, and does the BFF act on it? */
    static String deliver(Req r, Policy p) {
        boolean sameOrigin = r.from().equals(APP);
        boolean sameSite = site(r.from()).equals(site(APP));
        boolean cookie = sameSite || p.sameSite().equals("None") || p.sameSite().equals("Lax") && r.topLevelNav() && r.method().equals("GET");
        boolean simple = !r.customHeader() && (r.method().equals("GET") || r.method().equals("POST"));
        if (!sameOrigin && !simple && !p.corsAllow().contains(r.from())) {
            return "blocked by the browser (CORS preflight refused)";
        }
        if (!cookie) {
            return "no session cookie sent (SameSite=" + p.sameSite() + ") -> 401";
        }
        if (p.requireHeader() && !r.customHeader()) {
            return "BFF: missing X-BFF-CSRF header -> 403";
        }
        return "EXECUTED with the user's session";
    }

    // ------------------------------------------------------------------ 3. sealed client-side sessions

    static final class KeyRing {
        final Map<String, byte[]> keys = new LinkedHashMap<>();
        String current;

        void add(String kid) {
            byte[] k = new byte[32];
            RNG.nextBytes(k);
            keys.put(kid, k);
            current = kid;
        }

        String seal(String cookieName, String plaintext) throws Exception {
            byte[] iv = new byte[12];
            RNG.nextBytes(iv);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(keys.get(current), "AES"), new GCMParameterSpec(128, iv));
            c.updateAAD((cookieName + "|" + current).getBytes(StandardCharsets.UTF_8)); // bound to the cookie name and key id
            byte[] ct = c.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            return current + "." + KbSupport.b64u(ByteBuffer.allocate(iv.length + ct.length).put(iv).put(ct).array());
        }

        String open(String cookieName, String value) {
            try {
                String kid = value.substring(0, value.indexOf('.'));
                byte[] k = keys.get(kid);
                if (k == null) {
                    return "REJECT (key " + kid + " retired)";
                }
                byte[] blob = KbSupport.unb64u(value.substring(value.indexOf('.') + 1));
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(k, "AES"), new GCMParameterSpec(128, blob, 0, 12));
                c.updateAAD((cookieName + "|" + kid).getBytes(StandardCharsets.UTF_8));
                return "OK " + new String(c.doFinal(blob, 12, blob.length - 12), StandardCharsets.UTF_8).length() + " bytes";
            } catch (Exception e) {
                return "REJECT (" + e.getClass().getSimpleName() + ")";
            }
        }
    }

    static String jwt(Jose.Jwk k, Map<String, Object> claims, String typ) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", "ES256");
        h.put("typ", typ);
        h.put("kid", "as-2026-11");
        return Jose.sign(h, MiniJson.write(claims).getBytes(StandardCharsets.UTF_8), k);
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String rfc = KbSupport.rfc(fx, "rfc10017.txt");
        KbSupport.mustCite(rfc, "The BFF MUST enable the Secure flag for its cookies.", "6.1.3.2");
        KbSupport.mustCite(rfc, "The BFF MUST enable the HttpOnly flag for its cookies.", "6.1.3.2");
        KbSupport.mustCite(rfc, "the BFF SHOULD require that the browser-based application includes a custom request header", "6.1.3.3.2");
        KbSupport.mustCite(rfc, "a subdomain-takeover attack against b.example.com can enable CSRF attacks against the BFF of a.example.com", "6.1.3.3.1");
        KbSupport.mustCite(rfc, "the BFF SHOULD encrypt its cookie contents", "6.1.3.2");

        KbSupport.section("1. Five session cookies against RFC 10017 section 6.1.3.2");
        String[] cookies = {
            "JSESSIONID=8F2C1A; Path=/; HttpOnly",
            "SESSION=YTg4ZmM; Path=/; Secure; HttpOnly; SameSite=Lax",
            "token=eyJhbGciOiJFUzI1NiJ9.e30.sig; Path=/; Secure; SameSite=Strict",
            "__Host-bff=Zm9v; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=Strict",
            "__Host-Http-bff=Zm9v; Path=/; Secure; HttpOnly; SameSite=Strict"};
        int clean = 0;
        for (String c : cookies) {
            List<String> v = violations(c);
            clean += v.isEmpty() ? 1 : 0;
            KbSupport.info("%-80s -> %s", c, v.isEmpty() ? "compliant" : String.join("; ", v));
        }
        KbSupport.check("only __Host-Http-bff with Secure, HttpOnly, SameSite=Strict, Path=/ and no Domain is compliant", clean == 1
                && violations(cookies[4]).isEmpty());

        KbSupport.section("2. CSRF against the BFF's POST /api/transfer (browser model: SameSite + CORS preflight)");
        List<Req> reqs = List.of(
            new Req("the app itself: fetch POST + X-BFF-CSRF header", APP, "POST", false, true, false),
            new Req("evil.example: auto-submitted form POST", "https://evil.example", "POST", false, false, true),
            new Req("evil.example: fetch POST + custom header", "https://evil.example", "POST", false, true, true),
            new Req("evil.example: link to GET /api/transfer?to=...", "https://evil.example", "GET", true, false, true),
            new Req("blog.example.com (taken over): form POST", "https://blog.example.com", "POST", false, false, true),
            new Req("blog.example.com (taken over): fetch + custom header", "https://blog.example.com", "POST", false, true, true));
        List<Policy> policies = List.of(new Policy("L5 SameSite=Lax only", "Lax", false, Set.of()),
            new Policy("L6 SameSite=Strict only", "Strict", false, Set.of()),
            new Policy("L7 Strict + custom header + CORS allow-list", "Strict", true, Set.of(APP)));
        Map<String, Integer> csrf = new LinkedHashMap<>();
        Map<String, Boolean> appWorks = new HashMap<>();
        for (Policy p : policies) {
            int wins = 0;
            for (Req r : reqs) {
                String res = deliver(r, p);
                if (r.attack() && res.startsWith("EXECUTED")) {
                    wins++;
                }
                if (!r.attack()) {
                    appWorks.put(p.name(), res.startsWith("EXECUTED"));
                }
                KbSupport.info("%-44s %-54s -> %s", p.name(), r.label(), res);
            }
            csrf.put(p.name(), wins);
        }
        KbSupport.check("Lax: the state-changing GET link and the sibling subdomain's form both succeed", csrf.get("L5 SameSite=Lax only") == 2);
        KbSupport.check("Strict alone still loses to the taken-over sibling subdomain (same site, cross origin)", csrf.get("L6 SameSite=Strict only") == 1);
        KbSupport.check("Strict + required custom header + CORS allow-list: no CSRF, and the app still works",
                csrf.get("L7 Strict + custom header + CORS allow-list") == 0 && appWorks.get("L7 Strict + custom header + CORS allow-list"));

        KbSupport.section("3. Client-side session state: AES-256-GCM sealed cookie, key rotation, and size");
        Jose.Jwk as = Jose.generate("ES256", RNG);
        Map<String, Object> at = new LinkedHashMap<>();
        at.put("iss", "https://as.bank.example");
        at.put("sub", "248289761001");
        at.put("aud", "https://api.bank.example");
        at.put("client_id", "bff-web");
        at.put("exp", 1_767_226_200L);
        at.put("iat", 1_767_225_900L);
        at.put("jti", "8f14e45fceea167a5a36dedd4bea2543");
        at.put("scope", "openid accounts payments");
        at.put("cnf", Map.of("jkt", "0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I"));
        at.put("authorization_details", List.of(Map.of("type", "payment_initiation", "instructedAmount", Map.of("currency", "EUR", "amount", "123.50"),
                "creditorName", "Merchant A", "creditorAccount", Map.of("iban", "DE02100100109307118603"))));
        Map<String, Object> idt = new LinkedHashMap<>(at);
        idt.remove("authorization_details");
        idt.remove("cnf");
        idt.put("aud", "bff-web");
        idt.put("nonce", "n-0S6_WzA2Mj");
        idt.put("auth_time", 1_767_225_890L);
        idt.put("acr", "urn:example:aal2");
        idt.put("sid", "08a5019c-17e1-4977-8f42-65a12843ea02");
        String accessToken = jwt(as, at, "at+jwt");
        String idToken = jwt(as, idt, "JWT");
        String refreshToken = "Q..Zkm29lexi8VnWg2zPW1x-tgGad0Ibc3s3EwM_Ni4-g"; // RFC 9449 Figure 6's refresh token
        Map<String, Object> sess = new LinkedHashMap<>();
        sess.put("at", accessToken);
        sess.put("rt", refreshToken);
        sess.put("id_token", idToken);
        String session = MiniJson.write(sess);
        KeyRing ring = new KeyRing();
        ring.add("k1");
        String sealed = ring.seal("__Host-Http-bff", session);
        String cookieLine = "__Host-Http-bff=" + sealed + "; Path=/; Secure; HttpOnly; SameSite=Strict";
        KbSupport.info("access token %d B, ID token %d B, refresh token %d B -> session JSON %d B -> sealed Set-Cookie line %d B",
                accessToken.length(), idToken.length(), refreshToken.length(), session.length(), cookieLine.length());
        byte[] raw = sealed.getBytes(StandardCharsets.US_ASCII);
        raw[raw.length - 5] = (byte) (raw[raw.length - 5] == 'A' ? 'B' : 'A');
        String tampered = new String(raw, StandardCharsets.US_ASCII);
        KbSupport.info("open as issued: %s | one character changed: %s | replayed under another cookie name: %s",
                ring.open("__Host-Http-bff", sealed), ring.open("__Host-Http-bff", tampered), ring.open("__Host-Http-other", sealed));
        ring.add("k2");
        String newer = ring.seal("__Host-Http-bff", session);
        String during = ring.open("__Host-Http-bff", sealed);
        ring.keys.remove("k1");
        KbSupport.info("rotation: k2 seals new cookies (%s); a k1 cookie opens while k1 is kept (%s), and after k1 is retired: %s",
                ring.open("__Host-Http-bff", newer).startsWith("OK") ? "OK" : "FAIL", during, ring.open("__Host-Http-bff", sealed));
        KbSupport.check("GCM with the cookie name in the AAD: tampering and cookie swapping fail; retired keys end their sessions",
                ring.open("__Host-Http-bff", tampered).startsWith("REJECT") && ring.open("__Host-Http-other", newer).startsWith("REJECT")
                        && during.startsWith("OK") && ring.open("__Host-Http-bff", sealed).startsWith("REJECT (key k1 retired)"));
        Map<String, Object> multi = new LinkedHashMap<>(sess);
        multi.put("at_payments_api", accessToken);
        multi.put("at_accounts_api", accessToken); // one access token per audience, as RFC 8707 resource indicators encourage
        String bigLine = "__Host-Http-bff=" + ring.seal("__Host-Http-bff", MiniJson.write(multi)) + "; Path=/; Secure; HttpOnly; SameSite=Strict";
        KbSupport.info("with one access token per API audience (3 tokens): sealed Set-Cookie line %d B", bigLine.length());
        KbSupport.check("one token set fits the 4,096-byte cookie floor (RFC 6265 6.1); three audience-specific access tokens do not",
                cookieLine.length() < 4_096 && bigLine.length() > 4_096);

        KbSupport.section("4. The token handler: what the page sees, and where the BFF may forward");
        Map<String, String> serverSessions = new HashMap<>();
        serverSessions.put("sid-7f3a", accessToken);
        String browserResponse = proxy(serverSessions, "sid-7f3a", "/api/accounts");
        KbSupport.info("browser -> BFF GET /api/accounts (cookie __Host-Http-bff=sid-7f3a) -> %s", browserResponse);
        KbSupport.check("the response to the page contains no token, no DPoP proof and no Authorization header",
                !browserResponse.contains(accessToken) && !browserResponse.contains("eyJ") && !browserResponse.toLowerCase(Locale.ROOT).contains("authorization"));
        KbSupport.mustCite(rfc, "the BFF MUST enforce strict outbound request controls by validating destination hosts before forwarding requests", "6.1.3.6");
        String[] paths = {"/api/accounts", "/api/https://evil.example/collect", "/api/..%2f..%2fadmin/keys"};
        int leaks = 0;
        for (String path : paths) {
            String l5 = route(path, false);
            String l7 = route(path, true);
            boolean l5Leak = l5 != null && !l5.startsWith("https://api.bank.example/");
            leaks += l5Leak ? 1 : 0;
            KbSupport.info("%-36s L5 dynamic proxy -> %-46s L7 allow-list -> %s", path, l5 + (l5Leak ? "  (token sent!)" : ""), l7 == null ? "404" : l7);
        }
        KbSupport.check("a path-driven proxy forwards the user's token to an attacker host; the allow-list maps exact routes only",
                leaks == 1 && route(paths[1], true) == null && route(paths[2], true) == null);
        KbSupport.verdict();
    }

    /** RFC 10017 6.1.3.6: L5 derives the upstream from the path; L7 maps exact routes to fixed upstream URLs. */
    static String route(String path, boolean l7) {
        Map<String, String> routes = Map.of("/api/accounts", "https://api.bank.example/accounts", "/api/payments", "https://api.bank.example/payments");
        if (l7) {
            return routes.get(path);
        }
        String rest = path.substring("/api/".length());
        return rest.startsWith("https://") ? rest : "https://api.bank.example/" + rest;
    }

    /** BFF: look up the server-side session, call the RS with the token (and, in production, a DPoP proof), strip it. */
    static String proxy(Map<String, String> sessions, String sid, String path) {
        String token = sessions.get(sid);
        if (token == null) {
            return "401";
        }
        KbSupport.info("BFF -> RS: GET %s  Authorization: DPoP <%d-byte token from the server-side session>  DPoP: <proof, BFF's key>", path, token.length());
        return "200 {\"accounts\":[{\"iban\":\"DE02...8603\",\"balance\":\"1234.56\"}]}"; // upstream headers are not forwarded
    }
}
```

<!-- output:BffTokenHandlerLab.java -->
```text
  [PASS] constant cited verbatim from fixture: 6.1.3.2
  [PASS] constant cited verbatim from fixture: 6.1.3.2
  [PASS] constant cited verbatim from fixture: 6.1.3.3.2
  [PASS] constant cited verbatim from fixture: 6.1.3.3.1
  [PASS] constant cited verbatim from fixture: 6.1.3.2

== 1. Five session cookies against RFC 10017 section 6.1.3.2
  JSESSIONID=8F2C1A; Path=/; HttpOnly                                              -> MUST Secure; SHOULD SameSite=Strict (has none set); SHOULD __Host-Http- prefix
  SESSION=YTg4ZmM; Path=/; Secure; HttpOnly; SameSite=Lax                          -> SHOULD SameSite=Strict (has Lax); SHOULD __Host-Http- prefix
  token=eyJhbGciOiJFUzI1NiJ9.e30.sig; Path=/; Secure; SameSite=Strict              -> MUST HttpOnly; SHOULD __Host-Http- prefix
  __Host-bff=Zm9v; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=Strict   -> SHOULD NOT Domain; SHOULD __Host-Http- prefix; browser REJECTS it: __Host- needs Secure, Path=/ and no Domain
  __Host-Http-bff=Zm9v; Path=/; Secure; HttpOnly; SameSite=Strict                  -> compliant
  [PASS] only __Host-Http-bff with Secure, HttpOnly, SameSite=Strict, Path=/ and no Domain is compliant

== 2. CSRF against the BFF's POST /api/transfer (browser model: SameSite + CORS preflight)
  L5 SameSite=Lax only                         the app itself: fetch POST + X-BFF-CSRF header         -> EXECUTED with the user's session
  L5 SameSite=Lax only                         evil.example: auto-submitted form POST                 -> no session cookie sent (SameSite=Lax) -> 401
  L5 SameSite=Lax only                         evil.example: fetch POST + custom header               -> blocked by the browser (CORS preflight refused)
  L5 SameSite=Lax only                         evil.example: link to GET /api/transfer?to=...         -> EXECUTED with the user's session
  L5 SameSite=Lax only                         blog.example.com (taken over): form POST               -> EXECUTED with the user's session
  L5 SameSite=Lax only                         blog.example.com (taken over): fetch + custom header   -> blocked by the browser (CORS preflight refused)
  L6 SameSite=Strict only                      the app itself: fetch POST + X-BFF-CSRF header         -> EXECUTED with the user's session
  L6 SameSite=Strict only                      evil.example: auto-submitted form POST                 -> no session cookie sent (SameSite=Strict) -> 401
  L6 SameSite=Strict only                      evil.example: fetch POST + custom header               -> blocked by the browser (CORS preflight refused)
  L6 SameSite=Strict only                      evil.example: link to GET /api/transfer?to=...         -> no session cookie sent (SameSite=Strict) -> 401
  L6 SameSite=Strict only                      blog.example.com (taken over): form POST               -> EXECUTED with the user's session
  L6 SameSite=Strict only                      blog.example.com (taken over): fetch + custom header   -> blocked by the browser (CORS preflight refused)
  L7 Strict + custom header + CORS allow-list  the app itself: fetch POST + X-BFF-CSRF header         -> EXECUTED with the user's session
  L7 Strict + custom header + CORS allow-list  evil.example: auto-submitted form POST                 -> no session cookie sent (SameSite=Strict) -> 401
  L7 Strict + custom header + CORS allow-list  evil.example: fetch POST + custom header               -> blocked by the browser (CORS preflight refused)
  L7 Strict + custom header + CORS allow-list  evil.example: link to GET /api/transfer?to=...         -> no session cookie sent (SameSite=Strict) -> 401
  L7 Strict + custom header + CORS allow-list  blog.example.com (taken over): form POST               -> BFF: missing X-BFF-CSRF header -> 403
  L7 Strict + custom header + CORS allow-list  blog.example.com (taken over): fetch + custom header   -> blocked by the browser (CORS preflight refused)
  [PASS] Lax: the state-changing GET link and the sibling subdomain's form both succeed
  [PASS] Strict alone still loses to the taken-over sibling subdomain (same site, cross origin)
  [PASS] Strict + required custom header + CORS allow-list: no CSRF, and the app still works

== 3. Client-side session state: AES-256-GCM sealed cookie, key rotation, and size
  access token 782 B, ID token 574 B, refresh token 45 B -> session JSON 1432 B -> sealed Set-Cookie line 2009 B
  open as issued: OK 1432 bytes | one character changed: REJECT (AEADBadTagException) | replayed under another cookie name: REJECT (AEADBadTagException)
  rotation: k2 seals new cookies (OK); a k1 cookie opens while k1 is kept (OK 1432 bytes), and after k1 is retired: REJECT (key k1 retired)
  [PASS] GCM with the cookie name in the AAD: tampering and cookie swapping fail; retired keys end their sessions
  with one access token per API audience (3 tokens): sealed Set-Cookie line 4150 B
  [PASS] one token set fits the 4,096-byte cookie floor (RFC 6265 6.1); three audience-specific access tokens do not

== 4. The token handler: what the page sees, and where the BFF may forward
  BFF -> RS: GET /api/accounts  Authorization: DPoP <782-byte token from the server-side session>  DPoP: <proof, BFF's key>
  browser -> BFF GET /api/accounts (cookie __Host-Http-bff=sid-7f3a) -> 200 {"accounts":[{"iban":"DE02...8603","balance":"1234.56"}]}
  [PASS] the response to the page contains no token, no DPoP proof and no Authorization header
  [PASS] constant cited verbatim from fixture: 6.1.3.6
  /api/accounts                        L5 dynamic proxy -> https://api.bank.example/accounts              L7 allow-list -> https://api.bank.example/accounts
  /api/https://evil.example/collect    L5 dynamic proxy -> https://evil.example/collect  (token sent!)    L7 allow-list -> 404
  /api/..%2f..%2fadmin/keys            L5 dynamic proxy -> https://api.bank.example/..%2f..%2fadmin/keys  L7 allow-list -> 404
  [PASS] a path-driven proxy forwards the user's token to an attacker host; the allow-list maps exact routes only

verdict: OK (14 checks)
```

### 5.1 Cookies

RFC 10017 §6.1.3.2 requires:
- `Secure` and `HttpOnly` (MUST);
- `SameSite=Strict`, `Path=/`, no `Domain`, and the `__Host-Http-` prefix (SHOULD).

The prefix tells the browser the cookie was set over HTTP and is host-only. A sibling subdomain therefore can't plant or overwrite it, which blocks session fixation from a compromised subdomain. L33 §1 shows two failures:
- the common container default (`JSESSIONID … HttpOnly`) fails the Secure MUST;
- a `__Host-` cookie with `Domain=example.com` is **rejected by the browser**, the classic failed attempt to share a session across subdomains.

### 5.2 CSRF

The BFF authenticates by cookie, so CSRF is back. RFC 10017 §6.1.3.3 offers three defences.

**SameSite=Strict** is "adequate if the BFF is never considered to be same site with any other applications". But `blog.example.com` and `app.example.com` are the same site, so "a subdomain-takeover attack against b.example.com can enable CSRF attacks against the BFF of a.example.com". L33 L6 measures exactly that: a form POST from the sibling executes.

**A required custom header + CORS.** "Cross-origin requests with a custom request header always require a preflight". The preflight fails for any origin not on the BFF's allow-list, and the BFF "MUST ensure that every incoming request carries this static header". L33 L7 loses no attempts.

**Double-submit cookie** (framework CSRF tokens). This is acceptable, and is what Spring's `csrf(c -> c.spa())` sets up [D]:
- a JavaScript-readable `XSRF-TOKEN` cookie;
- a `SpaCsrfTokenRequestHandler` that reads the header.

The XSRF cookie being readable by JS is fine: an XSS can already make requests. What matters is that an *other-origin* page cannot read it.

⚠ Never let state change on GET. SameSite=Lax sends cookies on top-level GET navigations, so `GET /api/transfer?to=…` from a link executes (L33 L5).

### 5.3 Session state

- **Server-side sessions** (Redis, JDBC) keep tokens off the client entirely. The cookie carries an opaque id. Size doesn't matter, revocation is a delete, and back-channel logout (Folder 03 file 03) maps `sid` to sessions.
- **Client-side sealed sessions** "SHOULD encrypt its cookie contents" (§6.1.3.2). Use AEAD (AES-256-GCM) with the cookie name and key id in the AAD, so a sealed value can't be moved into another cookie, and a key ring for rotation (L33 §3). Two limits:
  - **Size:** three audience-specific access tokens overflow 4,096 B.
  - **Revocation:** a stolen sealed cookie works until expiry, unless the BFF also keeps a server-side denylist. Encryption protects the tokens *inside* the cookie, not the cookie [D: "still allows the attacker to use the encrypted cookie in a session hijacking attack"].

### 5.4 Routing

The BFF is "an application-layer reverse proxy". An attacker who controls the upstream host or path gets the user's access token sent to them. Map exact routes to fixed upstream URLs, restrict methods per route, and never derive the host from the request [D: §6.1.3.6; L33 §4].

---

## 6. Spring Security 7.1.2 as the BFF (servlet)

[D] What exists:
- `oauth2Login()` (confidential client; PKCE when `ClientSettings.requireProofKey(true)` or the provider demands it, as Folder 02 file 01 explains);
- `oauth2Client()`;
- `OAuth2AuthorizedClientManager` (refresh handled inline);
- `OAuth2ClientHttpRequestInterceptor(OAuth2AuthorizedClientManager)` with `RequestAttributeClientRegistrationIdResolver.clientRegistrationId("bank")` for `RestClient` relay;
- `csrf(c -> c.spa())`;
- CORS;
- `oidcLogout()` (with Folder 03 file 03's caveats).

What's missing: client-side DPoP, so tokens the BFF obtains are bearer tokens. The BFF is server-side, so the RFC's §6.1.3.7 "advanced security" is open to you: `private_key_jwt` and mTLS to the RS, or a DPoP proof added by your own `ClientHttpRequestInterceptor` with the token request customized to send a proof [E].

---

## 7. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```javascript
// L5 - DO NOT USE: public SPA client, tokens in localStorage, refresh in the page.
const tokens = await exchangeCode(code, verifier);                 // public client: anyone with a code can do this
localStorage.setItem("access_token", tokens.access_token);         // readable by every script on the origin
localStorage.setItem("refresh_token", tokens.refresh_token);       // 24 h of attacker access after one XSS
fetch("https://api.bank.example/payments", {method: "POST", headers: {Authorization: "Bearer " + localStorage.access_token}});
```

```java
// L7 - Spring Security 7.1.2 servlet BFF: confidential client, tokens server-side, cookie session, CSRF, exact routes.
@Bean
SecurityFilterChain bff(HttpSecurity http) throws Exception {
    http.authorizeHttpRequests(a -> a
            .requestMatchers("/bff/session", "/oauth2/**", "/login/**").permitAll()
            .anyRequest().authenticated())
        .oauth2Login(Customizer.withDefaults())                       // confidential client (private_key_jwt), PKCE
        .oauth2Client(Customizer.withDefaults())
        .csrf(c -> c.spa())                                           // double-submit: XSRF-TOKEN cookie + X-XSRF-TOKEN header
        .cors(c -> c.configurationSource(request -> {
            CorsConfiguration cfg = new CorsConfiguration();
            cfg.setAllowedOrigins(List.of("https://app.example.com")); // exact origin, never "*" with credentials
            cfg.setAllowCredentials(true);
            cfg.setAllowedMethods(List.of("GET", "POST"));
            cfg.setAllowedHeaders(List.of("X-XSRF-TOKEN", "Content-Type"));
            return cfg;
        }))
        .exceptionHandling(e -> e.defaultAuthenticationEntryPointFor(
            new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED), request -> request.getRequestURI().startsWith("/api/")));
    return http.build();
}

@RestController
final class PaymentsRoute {                                           // one class per upstream: exact routes, fixed hosts
    private final RestClient payments;

    PaymentsRoute(RestClient.Builder builder, OAuth2AuthorizedClientManager clients) {
        this.payments = builder.baseUrl("https://api.bank.example")
            .requestInterceptor(new OAuth2ClientHttpRequestInterceptor(clients))   // attaches the session's token; refreshes
            .build();
    }

    @PostMapping("/api/payments")
    ResponseEntity<String> create(@RequestBody String instruction) {
        String body = payments.post().uri("/payments")
            .attributes(RequestAttributeClientRegistrationIdResolver.clientRegistrationId("bank"))
            .contentType(MediaType.APPLICATION_JSON).body(instruction)
            .retrieve().body(String.class);
        return ResponseEntity.status(HttpStatus.CREATED).body(body);  // body only: no upstream headers, never a token
    }
}
```

```yaml
# L7 - session cookie per RFC 10017 6.1.3.2 (Spring Boot), server-side session store, confidential client
server:
  servlet:
    session:
      timeout: 8h
      cookie:
        name: __Host-Http-bff
        secure: true
        http-only: true
        same-site: strict
        path: /
spring:
  security:
    oauth2:
      client:
        registration:
          bank:
            provider: bank
            client-id: bff-web
            client-authentication-method: private_key_jwt
            authorization-grant-type: authorization_code
            scope: openid, accounts, payments
        provider:
          bank:
            issuer-uri: https://as.bank.example
```

| Concern | L5 | L7 |
|---|---|---|
| OAuth client | public, in the page | confidential BFF (`private_key_jwt`) |
| Tokens | localStorage / memory | server-side session store; never sent to the browser |
| Session cookie | `JSESSIONID; HttpOnly` | `__Host-Http-bff; Secure; HttpOnly; SameSite=Strict; Path=/` |
| CSRF | SameSite=Lax | Strict + custom header / double-submit + CORS allow-list; no state change on GET |
| Proxy | `/api/{host}/{path}` | exact routes → fixed upstreams, methods restricted |
| Response to page | upstream headers forwarded | body only |
| Logout | delete cookie | session delete + refresh-token revocation + back-channel logout (Folder 03) |
| Binding | bearer | mTLS or DPoP from the BFF to the RS |
| XSS | tokens stolen; 24 h of access | proxying only while it lives; CSP + Trusted Types to make it rare |

---

## 8. Real-world attack vectors & mitigations

### A1 · Token exfiltration from browser storage

**Attack.** An injected script reads `localStorage` (or hooks `fetch`, defeating a closure) and sends the access and refresh tokens to the attacker (RFC 10017 §5.1.1/5.1.2).
**Wire signature.** Token use from new IPs or devices; refreshes from two places.
**Root cause.** Tokens readable by the page.
**Mitigation.** BFF: no tokens in the browser. If browser-only, DPoP-bound tokens plus refresh rotation with reuse detection.
**Detection.** Token-use telemetry by client fingerprint; reuse-detection alerts.

### A2 · Silent-flow acquisition of new tokens

**Attack.** The script opens a hidden iframe at `/authorize?prompt=none`, reads the code from the same-origin redirect, and redeems it as the public client. It gets an independent token family that outlives the fix (L32: 24 h).
**Wire signature.** Authorization requests with `prompt=none` from unusual contexts; code redemptions from IPs that never loaded the app.
**Root cause.** A public client: possession of a code is sufficient.
**Mitigation.** A confidential client (BFF or token-mediating backend). RFC 10017 §6.3.4.2.3 finds AS-side restrictions (blocking iframes, forcing consent) "ineffective or impractical".
**Detection.** Correlate the code-redemption IP with the IP that started the flow.

### A3 · CSRF against the BFF from a sibling subdomain

**Attack.** A taken-over `blog.example.com`, which is the same site, auto-submits a form to `app.example.com/api/transfer`. SameSite=Strict still sends the cookie (L33 L6).
**Wire signature.** State-changing requests with `Origin`/`Sec-Fetch-Site: same-site` from a non-app origin, lacking the custom header.
**Root cause.** Treating SameSite as origin isolation.
**Mitigation.** A required custom header or double-submit token, a CORS allow-list of exact origins, `Origin` checks, and no state-changing GETs.
**Detection.** 403s for missing CSRF headers, by `Origin`.

### A4 · The BFF as an open proxy

**Attack.** `/api/https://evil.example/collect`, or a header-controlled upstream, makes the BFF attach the user's access token to a request to the attacker (L33 §4).
**Wire signature.** Upstream requests to hosts outside the RS list.
**Root cause.** Routing derived from request input.
**Mitigation.** Exact route-to-upstream maps, per-route methods, and egress allow-lists at the network layer (§6.1.3.6 MUST).
**Detection.** Egress firewall logs; unknown-route 404 counts.

### A5 · Session-cookie theft by infostealer malware

**Attack.** Malware copies the browser profile, including the HttpOnly BFF cookie, and replays the session elsewhere. Encryption of the cookie's *contents* doesn't help [D: §6.1.3.2].
**Wire signature.** The same session id from a new IP, ASN or TLS fingerprint; impossible travel.
**Root cause.** Bearer session cookies.
**Mitigation.**
- Short idle timeouts.
- Step-up for sensitive actions.
- Device-bound sessions (DBSC, Folder 01 file 01) where available.
- Binding the session to a client fingerprint as a risk signal (not a hard lock).
- CAEP-driven revocation (Folder 03 file 03).

**Detection.** Session-anomaly scoring at the BFF.

### A6 · Tokens leaking through the BFF itself

**Attack.** The BFF forwards upstream response headers (`Authorization` echoes, `Set-Cookie` from the RS, debugging headers), returns tokens from a "/me" endpoint for convenience, or logs them. The XSS then reads them, or log readers do.
**Wire signature.** Responses to the browser containing `eyJ` strings or `Authorization`; tokens in BFF logs.
**Root cause.** A generic pass-through proxy.
**Mitigation.** Return bodies only (L33 §4). An explicit response-header allow-list. No token-returning endpoints. Log redaction.
**Detection.** DLP rules on responses and logs for JWT patterns.

### A7 · Third-party scripts and supply chain

**Attack.** An analytics, chat or A/B-testing script, or a compromised npm dependency, runs with full origin privileges. That is XSS by contract.
**Wire signature.** New script sources; CSP violation reports.
**Root cause.** Executing code you don't control in the origin that holds the session.
**Mitigation.** A strict CSP (nonces, `strict-dynamic`), Trusted Types, Subresource Integrity, minimal third-party code on authenticated pages, and isolated origins for third-party widgets. With a BFF, the damage is limited to live proxying (L32).
**Detection.** CSP `report-to`, SRI failures, a script-inventory diff in CI.

---

## 9. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Where should our React app store the access token?"</b></summary>

**Initial Prompt.** A banking SPA, OAuth 2.1 with PKCE.

**L5 Textbook Answer.** "In memory, not localStorage, because XSS can read localStorage."

**How an Attacker Bypasses L5.**
- **Memory is still readable:** hook `fetch` or poison prototypes and the token passes through attacker code (§8.4).
- **More fundamentally, a silent iframe flow mints new tokens:** the attacker redeems the code as the public client (§5.1.3), giving 24 h of independent access (L32).

**L7 Principal Defense.**
- **Reframe:** the question isn't storage, it's client type.
- **For a bank, use a BFF** (RFC 10017 §6.1: "strongly recommended … for applications that handle personal data"):
  - a confidential client;
  - tokens server-side;
  - a `__Host-Http-` cookie;
  - CSRF with a custom header and CORS;
  - exact routes;
  - DPoP or mTLS from the BFF to the APIs.
- **Plus CSP and Trusted Types** to make XSS rare.

</details>

<details><summary><b>Q2 · "We'll use DPoP in the SPA with a non-extractable key; that fixes XSS."</b></summary>

**Initial Prompt.** The team wants to avoid running a backend.

**L5 Textbook Answer.** "Yes: tokens are useless without the key, and the key can't be exported."

**How an Attacker Bypasses L5.**
- **The attacker doesn't need the app's tokens.** A silent flow gives them tokens bound to *their own* key (§6.3.4.2.2: "the attacker can bind the fresh set of tokens to a key pair under their control").
- **Or they use the page's key** to pre-generate proofs (file 01 L26 case 7).

**L7 Principal Defense.**
- **DPoP in the browser is defence in depth against exfiltration**, worth having for browser-only apps.
- **It isn't an XSS answer.** For sensitive apps, a BFF.
- **If a backend is truly impossible:**
  - a token-mediating backend (stops 5.1.3);
  - short access-token lifetimes;
  - DPoP;
  - server nonces;
  - strict CSP.

</details>

<details><summary><b>Q3 · SameSite=Strict cookies, so we don't need CSRF tokens. Agree?</b></summary>

**Initial Prompt.** BFF on `app.example.com`; the company also runs `blog.example.com` on a SaaS CMS.

**L5 Textbook Answer.** "Agree: SameSite=Strict blocks cross-site requests."

**How an Attacker Bypasses L5.** Take over `blog.example.com` (a dangling CNAME, a CMS plugin vulnerability). It is *same site*, so Strict cookies flow, and a form POST executes (L33 L6; RFC 10017 §6.1.3.3.1).

**L7 Principal Defense.**
- **Add an origin-level defence:**
  - a required custom header, so a CORS preflight is needed and an exact-origin allow-list applies;
  - or double-submit (`csrf.spa()`);
  - plus `Origin`/`Sec-Fetch-Site` checks.
- **Never change state on GET.**
- **Inventory and monitor subdomains** (takeover is an attack surface).
- **Consider hosting the BFF on its own registrable domain** for strong isolation.

</details>

<details><summary><b>Q4 · Server-side sessions or encrypted cookie sessions for the BFF?</b></summary>

**Initial Prompt.** The platform team wants a stateless BFF.

**L5 Textbook Answer.** "Encrypted cookies: stateless scales better."

**How an Attacker Bypasses L5.**
- **Revocation:** the sealed cookie is valid until it expires. Logout, back-channel logout and CAEP can't kill it without server state anyway.
- **Size:** one token per audience overflows 4,096 B (L33: 4,150 B), so cookies get chunked, then truncated, and users get logged out at random.
- **Theft:** a stolen sealed cookie is a stolen session.

**L7 Principal Defense.**
- **Server-side sessions** (Redis) with an opaque `__Host-Http-` id. They give revocation by delete and `sid` mapping for back-channel logout, and size is irrelevant.
- **If stateless is mandatory:**
  - AES-256-GCM;
  - AAD = cookie name + key id;
  - a key ring;
  - short lifetime;
  - a server-side denylist for revocation (which is state again).

</details>

<details><summary><b>Q5 · Design the BFF's proxy so it can't be abused.</b></summary>

**Initial Prompt.** 40 microservices behind the BFF.

**L5 Textbook Answer.** "Generic `/api/**` passthrough to the gateway."

**How an Attacker Bypasses L5.** Path tricks, header-controlled upstreams or open redirects send the user's token to the attacker (L33 §4). A generic passthrough also forwards upstream headers back to the page (A6).

**L7 Principal Defense.**
- **Explicit route table:** route → upstream URL, method set, audience-specific token.
- **No host derived from input.**
- **A response-header allow-list,** with bodies only.
- **Egress network policy.**
- **Per-route token exchange** (RFC 8693, Folder 05), so each upstream gets an audience-restricted token, not the user's broad one.

</details>

<details><summary><b>Q6 · How does logout work end to end with a BFF?</b></summary>

**Initial Prompt.** "Clicking logout just deletes the cookie."

**L5 Textbook Answer.** "Delete the session cookie and redirect to the login page."

**How an Attacker Bypasses L5.** The session store entry, the refresh token at the AS, and the AS's SSO session all survive. A stolen cookie copy still works if the store wasn't cleared, and other apps stay logged in (Folder 03 file 03).

**L7 Principal Defense.** BFF logout:
1. Delete the server-side session.
2. Revoke the refresh token (RFC 7009).
3. Redirect to the OP's `end_session_endpoint` with `id_token_hint` (RP-initiated logout).
4. Accept back-channel logout tokens and CAEP `session-revoked`, mapping `sid` to BFF sessions. Spring's built-in back-channel support needs Folder 03's hardened endpoint.

</details>

<details><summary><b>Q7 · Token-mediating backend or full BFF?</b></summary>

**Initial Prompt.** The frontend team wants to call APIs directly for latency.

**L5 Textbook Answer.** "Token-mediating backend: it keeps the refresh token safe and avoids the proxy hop."

**How an Attacker Bypasses L5.** Access tokens in the browser are stolen by XSS and used directly against the APIs (§6.2.4.4: "the attacker still has the ability to gain direct access to resource servers"), for up to 5 min after the fix (L32).

**L7 Principal Defense.**
- **The full BFF is the default** (§6.2.4.4 says to consider a token-mediating backend only when a proxying BFF is impossible).
- **If a token-mediating backend is chosen:**
  - DPoP-bound access tokens with the key in the browser (stolen tokens become useless off-device);
  - short lifetimes;
  - narrow audiences;
  - CSP.
- **Measure the proxy latency** before rejecting the BFF. It's usually one in-region hop.

</details>

<details><summary><b>Q8 · A third-party chat widget must run on authenticated pages. What's your stance?</b></summary>

**Initial Prompt.** Marketing insists.

**L5 Textbook Answer.** "It's from a reputable vendor; add its domain to CSP."

**How an Attacker Bypasses L5.** A compromise of the vendor's CDN is XSS on your origin (A7). In a browser-only client that means token theft and new-token acquisition, so 24 h of access.

**L7 Principal Defense.**
- **Run third-party widgets in a separate origin.** A sandboxed iframe on a different registrable domain communicates via `postMessage` with origin checks.
- **Or use SRI-pinned versions.**
- **With a BFF,** the residual risk is live proxying only.
- **Document the accepted risk** with the CSP reports and the script inventory as controls.

</details>

<details><summary><b>Q9 · How do you implement CSRF protection in a Spring BFF serving a React app?</b></summary>

**Initial Prompt.** Spring Security 7.1.2.

**L5 Textbook Answer.** "`csrf.disable()`, since it's an API."

**How an Attacker Bypasses L5.** The BFF authenticates by cookie, so it's *not* a token API. Disabling CSRF re-opens every form-POST attack (L33 L5).

**L7 Principal Defense.**
- **`csrf(c -> c.spa())`** (since 7.0). The React app reads `XSRF-TOKEN` and sends `X-XSRF-TOKEN`, which is double-submit per RFC 10017 §6.1.3.3.3.
- **Plus:**
  - CORS with exact origins and credentials;
  - the `__Host-Http-` SameSite=Strict session cookie;
  - no state-changing GETs.
- **Test it:** cross-site and same-site-sibling form POSTs must fail in CI.

</details>

<details><summary><b>Q10 · Where do DPoP and mTLS fit in a BFF architecture?</b></summary>

**Initial Prompt.** The APIs require sender-constrained tokens (FAPI).

**L5 Textbook Answer.** "Put DPoP in the browser."

**How an Attacker Bypasses L5.** That brings tokens back into the browser, along with 5.1.3.

**L7 Principal Defense.**
- **The BFF is the OAuth client,** so the binding lives there:
  - mTLS from the BFF to the AS and RS (`tls_client_auth` / certificate-bound tokens);
  - or DPoP with a key in the BFF's KMS/HSM.
- **Spring's oauth2-client has no DPoP in 7.1.2.** Use mTLS, or add a proof-signing `ClientHttpRequestInterceptor` and customize token requests.
- **The browser holds only the session cookie** (RFC 10017 §6.1.3.7: advanced security is easier server-side).

</details>

---

## 10. Invariants checklist

- [ ] Sensitive and business apps use a BFF (confidential client); no access or refresh tokens in browser storage or JS-set cookies.
- [ ] Session cookie: `__Host-Http-` prefix, `Secure`, `HttpOnly`, `SameSite=Strict`, `Path=/`, no `Domain`.
- [ ] CSRF: required custom header (CORS preflight) or double-submit (`csrf.spa()`), exact-origin CORS with credentials, `Origin` checks, no state-changing GET.
- [ ] Server-side session store; if sealed cookies, AEAD with name + kid in AAD, key ring, size budget < 4 KB, denylist for revocation.
- [ ] Proxy: explicit route → upstream map, per-route methods, egress allow-list; responses return bodies only.
- [ ] Session lifetime ≤ refresh-token max lifetime; logout deletes session, revokes RT, ends the OP session; back-channel logout / CAEP mapped to sessions.
- [ ] BFF → RS sender-constrained (mTLS or DPoP from the BFF); audience-specific tokens per upstream.
- [ ] Browser-only clients (low-risk apps only): PKCE, exact redirects, DPoP, short ATs, RT rotation with reuse detection, strict CSP.
- [ ] CSP with nonces and `strict-dynamic`, Trusted Types, SRI; third-party widgets isolated on another origin.

---

## 11. References

- RFC 10017 *OAuth 2.0 for Browser-Based Applications* (BCP 212) — <https://www.rfc-editor.org/rfc/rfc10017>
- RFC 9700 *Best Current Practice for OAuth 2.0 Security* — <https://www.rfc-editor.org/rfc/rfc9700>
- RFC 6265 *HTTP State Management Mechanism* (cookie size floor, §6.1) — <https://www.rfc-editor.org/rfc/rfc6265>
- RFC 8707 *Resource Indicators for OAuth 2.0* — <https://www.rfc-editor.org/rfc/rfc8707>
- Spring Security reference, *OAuth 2.0 Client* — <https://docs.spring.io/spring-security/reference/servlet/oauth2/client/index.html> · *CSRF for single-page applications* — <https://docs.spring.io/spring-security/reference/servlet/exploits/csrf.html>
- OWASP Cheat Sheet Series, *Session Management* — <https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html>
- W3C *Content Security Policy Level 3* — <https://www.w3.org/TR/CSP3/> · *Trusted Types* — <https://www.w3.org/TR/trusted-types/>
