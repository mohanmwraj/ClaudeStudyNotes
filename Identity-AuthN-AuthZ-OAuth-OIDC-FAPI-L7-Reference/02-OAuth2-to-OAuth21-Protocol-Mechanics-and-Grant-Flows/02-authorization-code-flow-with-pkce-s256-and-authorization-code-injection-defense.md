# The Authorization Code Flow with PKCE (S256), and Authorization Code Injection Defense

> Folder 02 · File 02 of 04 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [01 · Roles, threat model, OAuth 2.1](01-oauth2-roles-threat-model-and-what-oauth21-and-rfc9700-changed.md) · Next: [03 · Refresh tokens](03-refresh-token-rotation-reuse-detection-grace-periods-and-revocation-rfc7009.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L16 `AuthCodePkceLab.java` | An in-memory AS and client, each L5 or L7: the honest wire flow, then 8 attacks (interception, injection, PKCE downgrade, `plain` leakage, code replay, login CSRF, mix-up with RFC 9207 `iss`, redirect path traversal). L5 loses 8/8; L7 blocks 8/8, plus the token-endpoint downgrade rule | RFC 7636 App. B S256 vector, cited from `fixtures/rfc7636.txt` |

**Verification.** Compiled with Folders 01–02 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs the output and requires it byte-identical. Demo identifiers come from a seeded `SplittableRandom` so the printed wire messages are reproducible; this is documented in the listing, and production uses `SecureRandom`. Normative quotes are from RFC 6749, RFC 7636, RFC 9207, RFC 9700 and OAuth 2.1 draft-17 in [`fixtures/`](fixtures/). Spring behaviour marked [D] was read from the spring-security 7.1.2 sources.

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

The authorization code grant is the one OAuth flow you must be able to draw from memory and attack from memory. It is the only redirect-based grant left in OAuth 2.1, and every later profile (OIDC, FAPI 2.0, PAR, DPoP, BFF) is built on top of it. This file does three things: it puts the flow on the wire; it shows what each of the three binding parameters (`state`, PKCE, `iss`) actually binds; and it replays eight attacks against an L5 and an L7 implementation of both ends.

Results:
- **[M]** L16 reproduces the RFC 7636 Appendix B vector: `dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` → `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`.
- **[M]** Against an AS without enforcement and a client without state, PKCE or `iss` checks, **all 8 attacks succeed**. With L7 on both sides **all 8 fail**, each at a *different* control. No single parameter does all the work.
- **[M]** The PKCE downgrade succeeds even when the *client* always uses PKCE, if the AS issues challenge-less codes and ignores an unexpected `code_verifier`. RFC 9700 §4.8.2's rule ("a code_verifier for a code issued without a challenge MUST be rejected") is the defence, and L16 checks it directly.
- **[D]** Spring Authorization Server 7.1.2 accepts only `S256` (`OAuth2AuthorizationCodeRequestAuthenticationValidator`). It requires PKCE for every client by default, and on code reuse it invalidates the access *and* refresh tokens already issued for that code (`OAuth2AuthorizationCodeAuthenticationProvider`), as RFC 6749 §4.1.2 recommends.

---

## 1. First principles: the flow on the wire

### 1.1 Five messages

```text
 (1) client -> browser:  302 Location: https://idp.example.com/authorize?
                           response_type=code&client_id=web-app&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcb
                           &scope=openid+payments&state=<S>&code_challenge=<BASE64URL(SHA256(V))>&code_challenge_method=S256
       the client stores {state: S, verifier: V, as: https://idp.example.com} in the user's SERVER-SIDE session
 (2) browser -> AS:      GET /authorize?...      AS authenticates the user (file 01 of Folder 01), records consent
 (3) AS -> browser:      302 Location: https://app.example.com/cb?code=<C>&state=<S>&iss=https%3A%2F%2Fidp.example.com
                           C: random, single-use, short-lived, bound to {client_id, redirect_uri, challenge, user}
 (4) browser -> client:  GET /cb?code=C&state=S&iss=...
       client checks: state == session.state; iss == session.as   (CSRF, mix-up)
 (5) client -> AS:       POST /token  grant_type=authorization_code&code=C&code_verifier=V  + client authentication
       AS checks: code exists, unused, unexpired, same client; BASE64URL(SHA256(V)) == stored challenge
       AS -> client:     {"access_token":"...","token_type":"Bearer","expires_in":300,"refresh_token":"...","scope":"..."}
```

```http
POST /oauth2/token HTTP/1.1
Host: idp.example.com
Content-Type: application/x-www-form-urlencoded
Authorization: Basic d2ViLWFwcDo8b25seS1mb3ItbGVnYWN5LWNsaWVudHM+

grant_type=authorization_code&code=pPeUSjCRAMwbLBmIRuhHTpU01awmD6MoNSgL4bHLyFg&code_verifier=MZFm78-fgofDubAKPPXUGzMVZ5Xib7r83Wo7HwzzcTcAX6e4LNqfU4
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store

{"access_token":"eyJhbGciOiJFUzI1NiIsInR5cCI6ImF0K2p3dCJ9...","token_type":"Bearer","expires_in":300,"refresh_token":"rt...","scope":"openid payments"}
```

Note what is *absent* from the OAuth 2.1 token request: `redirect_uri`. Draft-17 drops it because exact redirect matching at step 2 plus PKCE at step 5 make the echo redundant (file 01 §2.1). The L7 client above authenticates with Basic only as a placeholder. For confidential clients, `private_key_jwt` is the recommended method (file 04).

### 1.2 PKCE in one equation

```text
   V  = 43..128 chars from [A-Z a-z 0-9 - . _ ~]      (RFC 7636 4.1; >= 256 bits of entropy: 32 random bytes, base64url)
   C  = BASE64URL-ENCODE(SHA256(ASCII(V)))            (S256; 'plain' (C = V) is prohibited in OAuth 2.1)
   step 1 sends C publicly;  step 5 proves knowledge of V.  SHA-256 preimage resistance: C reveals nothing about V.
```

PKCE converts "whoever holds the code can redeem it" into "whoever holds the code **and** the session secret V can redeem it". The code travels through the front channel and can leak. V never leaves the client's server-side session, or the native app's memory.

### 1.3 What each binding parameter binds

| Parameter | Binds | Stops | Does NOT stop |
|---|---|---|---|
| `state` (client-generated, session-stored) | the *callback* to the browser session that started the flow | login CSRF (L16 #6) if checked | code injection with a *matching* state (the attacker uses their own session's state, L16 #2) |
| PKCE (`code_challenge` / `code_verifier`) | the *code redemption* to the session that created the challenge | interception (#1), injection (#2), CSRF; `plain` leaks if the URL is logged (#4) | mix-up (#7): the client sends V to the wrong token endpoint itself |
| `nonce` (OIDC) | the *ID token* to the session | injection for OIDC clients that validate the ID token before using the code result | non-OIDC flows; clients that skip ID-token validation |
| `iss` (RFC 9207) | the *response* to the AS that produced it | mix-up (#7) | nothing else; it is not a secret |
| exact `redirect_uri` | the *delivery address* | path or subdomain code theft (#8) | anything after delivery |
| single-use code + revoke on reuse | the *code* to one redemption | replay (#5), and detection of a raced theft | the first redemption by a thief, without PKCE |

```mermaid
sequenceDiagram
    autonumber
    participant V as Victim browser
    participant A as Attacker browser
    participant C as Honest client
    participant AS as Authorization server
    V->>AS: authorize (challenge Cv from victim session)
    AS-->>V: 302 cb?code=K (leaks via Referer or log)
    A->>C: start login (attacker session: state Sa, verifier Va)
    A->>C: GET /cb?code=K&state=Sa (injected victim code)
    C->>AS: POST /token code=K, code_verifier=Va
    AS-->>C: invalid_grant (SHA256(Va) != Cv) - PKCE binds K to the victim session
```

---

## 2. The attacker models behind each attack

RFC 9700 §3 defines the attacker models that OAuth defences are designed against. The ones that matter here [D]:

- **(A1) Web attacker.** Controls web sites and can send victims links (CSRF, phishing to authorization URLs, mix-up via a malicious AS).
- **(A3) An attacker who can read the authorization response** but not change it. Sources: browser history, a malicious app with the same custom scheme, logs, `Referer` (interception, injection).
- **(A4) An attacker who can read the authorization request.** Sources: proxy logs, mobile OS logs (`plain` leakage).
- **(A5) An attacker who can read the access token.** For example a compromised RS (Folder 04's sender-constraining).

A useful habit: for each defence, name the attacker it is for. "State" is for (A1). PKCE is for (A3), and S256 specifically for (A4). `iss` is for (A1)-as-malicious-AS. Exact redirect matching limits who can become (A3).

---

## 3. L16: eight attacks against both ends

<!-- listing:AuthCodePkceLab.java -->
```java
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.SplittableRandom;

/**
 * L16 - the authorization code grant with PKCE, as a deterministic in-memory protocol run.
 *
 * <p>An authorization server ({@link As}) and a client ({@link Client}) are each configurable as L5 or L7. The
 * RFC 7636 Appendix B vector is checked from the fixture, the honest flow is printed on the wire, and eight attacks
 * are replayed: code interception, code injection, PKCE downgrade, 'plain' challenge leakage, code replay, login
 * CSRF, the mix-up attack (RFC 9207 'iss'), and redirect-based code theft.
 */
public final class AuthCodePkceLab {

    /** Demo identifiers come from a seeded generator so the printed run is reproducible. Production: SecureRandom. */
    static final SplittableRandom IDS = new SplittableRandom(20261106L);

    static String rnd() {
        byte[] b = new byte[32];
        for (int i = 0; i < b.length; i++) {
            b[i] = (byte) IDS.nextInt(256);
        }
        return KbSupport.b64u(b);
    }

    static String s256(String verifier) {
        return KbSupport.b64u(WebAuthnRp.sha256(verifier.getBytes(StandardCharsets.US_ASCII)));
    }

    record Grant(String clientId, String redirectUri, String user, String challenge, String method, boolean[] used, String[] issued) {
    }

    /** A minimal authorization server. Flags select L5 or L7 behaviour. */
    static final class As {
        final String issuer;
        final boolean l7;
        final Map<String, String> registeredRedirect = new HashMap<>();
        final Map<String, Grant> codes = new HashMap<>();
        final Map<String, String> tokens = new HashMap<>(); // access token -> user
        final StringBuilder log = new StringBuilder();

        As(String issuer, boolean l7) {
            this.issuer = issuer;
            this.l7 = l7;
        }

        /** Returns the redirect the user agent follows, or an error string. */
        String authorize(String clientId, String redirectUri, String state, String challenge, String method, String user) {
            String reg = registeredRedirect.get(clientId);
            boolean redirectOk = l7 ? redirectUri.equals(reg) : redirectUri.startsWith(reg);
            if (!redirectOk) {
                return "error=invalid_request (redirect_uri)";
            }
            if (l7 && (challenge == null || !"S256".equals(method))) {
                return "error=invalid_request (PKCE S256 required)";
            }
            String code = rnd();
            codes.put(code, new Grant(clientId, redirectUri, user, challenge, method, new boolean[1], new String[1]));
            return redirectUri + "?code=" + code + "&state=" + state + (l7 ? "&iss=" + enc(issuer) : "");
        }

        String token(String clientId, String code, String verifier) {
            Grant g = codes.get(code);
            if (g == null || !g.clientId().equals(clientId)) {
                return "error=invalid_grant";
            }
            if (g.used()[0]) {
                if (l7 && g.issued()[0] != null) { // RFC 6749 4.1.2: revoke tokens issued from a replayed code
                    tokens.remove(g.issued()[0]);
                    log.append("revoked tokens of replayed code;");
                }
                return l7 ? "error=invalid_grant (code reused)" : "access_token=" + issue(g);
            }
            if (g.challenge() != null) {
                String expect = "plain".equals(g.method()) ? verifier : verifier == null ? null : s256(verifier);
                if (!g.challenge().equals(expect)) {
                    return "error=invalid_grant (PKCE)";
                }
            } else if (l7 && verifier != null) { // RFC 9700 4.8.2: verifier without stored challenge = downgrade
                return "error=invalid_grant (code_verifier without code_challenge)";
            }
            g.used()[0] = true;
            String at = issue(g);
            g.issued()[0] = at;
            return "access_token=" + at;
        }

        private String issue(Grant g) {
            String at = "at." + rnd().substring(0, 10);
            tokens.put(at, g.user());
            return at;
        }
    }

    /** The relying client; one session per browser. */
    static final class Client {
        final String clientId;
        final String redirect;
        final boolean l7;
        final Map<String, Map<String, String>> sessions = new HashMap<>();

        Client(String clientId, String redirect, boolean l7) {
            this.clientId = clientId;
            this.redirect = redirect;
            this.l7 = l7;
        }

        /** Starts a login for a browser session; returns the authorization request parameters. */
        Map<String, String> start(String sessionId, As as) {
            Map<String, String> s = new HashMap<>();
            s.put("as", as.issuer);
            s.put("state", rnd());
            if (l7) {
                s.put("verifier", rnd() + rnd().substring(0, 11)); // 54 chars, within 43..128
            }
            sessions.put(sessionId, s);
            return s;
        }

        /** Handles the callback in a browser session; returns the user the session is now logged in as. */
        String callback(String sessionId, String query, Map<String, As> ases) {
            Map<String, String> q = parse(query);
            Map<String, String> s = sessions.getOrDefault(sessionId, Map.of());
            if (l7) {
                if (!q.getOrDefault("state", "").equals(s.get("state"))) {
                    return "REJECTED (state)";
                }
                if (!s.get("as").equals(q.get("iss"))) { // RFC 9207: who actually answered?
                    return "REJECTED (iss " + q.get("iss") + " != " + s.get("as") + ")";
                }
            }
            As as = ases.get(s.getOrDefault("as", ases.keySet().iterator().next()));
            String r = as.token(clientId, q.get("code"), s.get("verifier"));
            if (!r.startsWith("access_token=")) {
                return "REJECTED (" + r + ")";
            }
            return as.tokens.get(r.substring(13));
        }
    }

    static Map<String, String> parse(String url) {
        Map<String, String> m = new LinkedHashMap<>();
        String q = url.contains("?") ? url.substring(url.indexOf('?') + 1) : url;
        for (String kv : q.split("&")) {
            String[] p = kv.split("=", 2);
            m.put(p[0], p.length > 1 ? java.net.URLDecoder.decode(p[1], StandardCharsets.UTF_8) : "");
        }
        return m;
    }

    static String enc(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8);
    }

    record World(As honest, As evil, Client client, Map<String, As> ases) {
    }

    static World world(boolean l7) {
        As honest = new As("https://idp.example.com", l7);
        As evil = new As("https://evil-idp.example", l7);
        Client c = new Client("web-app", "https://app.example.com/cb", l7);
        honest.registeredRedirect.put("web-app", c.redirect);
        evil.registeredRedirect.put("web-app", c.redirect);
        Map<String, As> ases = new LinkedHashMap<>();
        ases.put(honest.issuer, honest);
        ases.put(evil.issuer, evil);
        return new World(honest, evil, c, ases);
    }

    interface Attack {
        String run(World w);
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String r7636 = KbSupport.rfc(fx, "rfc7636.txt");

        KbSupport.section("RFC 7636 Appendix B (S256), values cited from fixtures/rfc7636.txt");
        String verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        KbSupport.mustCite(r7636, verifier, "Appendix B code_verifier");
        KbSupport.mustCite(r7636, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "Appendix B code_challenge");
        KbSupport.check("BASE64URL(SHA256(ASCII(verifier))) = " + s256(verifier), s256(verifier).equals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"));

        KbSupport.section("The honest L7 flow on the wire");
        World w = world(true);
        Map<String, String> s = w.client().start("sid-alice", w.honest());
        String authz = "GET /authorize?response_type=code&client_id=web-app&redirect_uri=" + enc(w.client().redirect)
                + "&scope=openid+payments&state=" + s.get("state") + "&code_challenge=" + s256(s.get("verifier"))
                + "&code_challenge_method=S256";
        KbSupport.info("%s", authz);
        String cb = w.honest().authorize("web-app", w.client().redirect, s.get("state"), s256(s.get("verifier")), "S256", "alice");
        KbSupport.info("302 Location: %s", cb);
        KbSupport.info("POST /token  grant_type=authorization_code&code=%s&code_verifier=%s", parse(cb).get("code"), s.get("verifier"));
        String who1 = w.client().callback("sid-alice", cb, w.ases());
        String who2 = w.client().callback("sid-alice", cb, w.ases());
        KbSupport.check("alice's session is logged in as: " + who1, "alice".equals(who1));
        KbSupport.check("the same callback URL replayed: " + who2, who2.startsWith("REJECTED"));

        Map<String, Attack> attacks = new LinkedHashMap<>();
        attacks.put("1 code interception (malicious app owns the custom scheme)", x -> {
            Map<String, String> v = x.client().start("sid-victim", x.honest());
            String c = x.honest().authorize("web-app", x.client().redirect, v.get("state"), v.get("verifier") == null ? null
                    : s256(v.get("verifier")), v.get("verifier") == null ? null : "S256", "victim");
            String stolen = parse(c).get("code");
            String r = x.honest().token("web-app", stolen, null); // the thief has the code, not the verifier
            return r.startsWith("access_token=") ? "attacker holds victim tokens" : "blocked: " + r;
        });
        attacks.put("2 code injection into the attacker's own session", x -> {
            Map<String, String> v = x.client().start("sid-victim", x.honest());
            String vc = x.honest().authorize("web-app", x.client().redirect, v.get("state"), v.get("verifier") == null ? null
                    : s256(v.get("verifier")), v.get("verifier") == null ? null : "S256", "victim");
            String stolen = parse(vc).get("code");
            Map<String, String> a = x.client().start("sid-attacker", x.honest());
            String forged = x.client().redirect + "?code=" + stolen + "&state=" + a.get("state") + "&iss=" + enc(x.honest().issuer);
            String who = x.client().callback("sid-attacker", forged, x.ases());
            return "victim".equals(who) ? "attacker's browser is logged in as victim" : "blocked: " + who;
        });
        attacks.put("3 PKCE downgrade: challenge-less code injected into a PKCE-using client", x -> {
            // the CLIENT always uses PKCE here; only the AS differs (L5 AS ignores a verifier it has no challenge for)
            Client pkceClient = new Client("web-app", x.client().redirect, true);
            x = new World(x.honest(), x.evil(), pkceClient, x.ases());
            String c = x.honest().authorize("web-app", x.client().redirect, "s", null, null, "victim");
            if (c.startsWith("error")) {
                return "blocked: AS refused the challenge-less request (" + c + ")";
            }
            Map<String, String> a = x.client().start("sid-attacker", x.honest());
            String forged = x.client().redirect + "?code=" + parse(c).get("code") + "&state=" + a.get("state") + "&iss="
                    + enc(x.honest().issuer);
            String who = x.client().callback("sid-attacker", forged, x.ases());
            return "victim".equals(who) ? "attacker's browser is logged in as victim" : "blocked: " + who;
        });
        attacks.put("4 'plain' challenge read from a logged authorization URL", x -> {
            String v = rnd();
            String c = x.honest().authorize("web-app", x.client().redirect, "s", v, "plain", "victim");
            if (c.startsWith("error")) {
                return "blocked: " + c;
            }
            String r = x.honest().token("web-app", parse(c).get("code"), v); // challenge == verifier, both visible in logs
            return r.startsWith("access_token=") ? "attacker holds victim tokens" : "blocked: " + r;
        });
        attacks.put("5 code replay after the client already redeemed it", x -> {
            Map<String, String> v = x.client().start("sid-victim", x.honest());
            String c = x.honest().authorize("web-app", x.client().redirect, v.get("state"), v.get("verifier") == null ? null
                    : s256(v.get("verifier")), v.get("verifier") == null ? null : "S256", "victim");
            x.client().callback("sid-victim", c, x.ases());
            String r = x.honest().token("web-app", parse(c).get("code"), v.get("verifier"));
            return r.startsWith("access_token=") ? "second token set issued" : "blocked: " + r + " " + x.honest().log;
        });
        attacks.put("6 login CSRF: victim's browser completes the attacker's login", x -> {
            String ac = x.honest().authorize("web-app", x.client().redirect, "s", null, null, "attacker");
            if (ac.startsWith("error")) {
                Map<String, String> a = x.client().start("sid-attacker-own", x.honest());
                ac = x.honest().authorize("web-app", x.client().redirect, a.get("state"), s256(a.get("verifier")), "S256", "attacker");
            }
            x.client().start("sid-victim", x.honest());
            String who = x.client().callback("sid-victim", ac, x.ases());
            return "attacker".equals(who) ? "victim is silently logged into the attacker's account" : "blocked: " + who;
        });
        attacks.put("7 mix-up: user picks evil IdP, evil IdP bounces to the honest IdP", x -> {
            Map<String, String> v = x.client().start("sid-victim", x.evil());
            String c = x.honest().authorize("web-app", x.client().redirect, v.get("state"), v.get("verifier") == null ? null
                    : s256(v.get("verifier")), v.get("verifier") == null ? null : "S256", "victim");
            String who = x.client().callback("sid-victim", c, x.ases()); // client redeems at the AS it THINKS it used
            if (who.startsWith("REJECTED (iss")) {
                return "blocked: " + who;
            }
            String leaked = parse(c).get("code"); // the evil token endpoint received it
            String r = x.honest().token("web-app", leaked, v.get("verifier"));
            return r.startsWith("access_token=") ? "evil IdP replays the leaked code (+verifier) at the honest IdP" : "blocked: " + r;
        });
        attacks.put("8 redirect_uri=https://app.example.com/cb/../../attacker", x -> {
            String c = x.honest().authorize("web-app", x.client().redirect + "/../../attacker", "s", s256("v".repeat(43)), "S256", "victim");
            return c.startsWith("error") ? "blocked: " + c : "code delivered to attacker path: " + c.substring(0, 45) + "...";
        });

        KbSupport.section("Eight attacks: L5 (AS without enforcement + client without state/PKCE/iss) vs L7");
        int l5Bad = 0;
        int l7Blocked = 0;
        for (Map.Entry<String, Attack> e : attacks.entrySet()) {
            String l5 = e.getValue().run(world(false));
            String l7 = e.getValue().run(world(true));
            l5Bad += l5.startsWith("blocked") ? 0 : 1;
            l7Blocked += l7.startsWith("blocked") ? 1 : 0;
            KbSupport.info("%s", e.getKey());
            KbSupport.info("    L5: %s", l5);
            KbSupport.info("    L7: %s", l7);
        }
        KbSupport.check("L5 loses " + l5Bad + " of 8", l5Bad == 8);
        KbSupport.check("L7 blocks all 8", l7Blocked == 8);
        As legacy = world(true).honest();
        legacy.codes.put("legacy-code", new Grant("web-app", "https://app.example.com/cb", "victim", null, null, new boolean[1], new String[1]));
        String down = legacy.token("web-app", "legacy-code", "attacker-verifier-0123456789012345678901234567");
        KbSupport.check("L7 token endpoint: a code_verifier for a code with no stored challenge -> " + down, down.contains("without code_challenge"));
        KbSupport.verdict();
    }
}
```

<!-- output:AuthCodePkceLab.java -->
```text

== RFC 7636 Appendix B (S256), values cited from fixtures/rfc7636.txt
  [PASS] constant cited verbatim from fixture: Appendix B code_verifier
  [PASS] constant cited verbatim from fixture: Appendix B code_challenge
  [PASS] BASE64URL(SHA256(ASCII(verifier))) = E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM

== The honest L7 flow on the wire
  GET /authorize?response_type=code&client_id=web-app&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcb&scope=openid+payments&state=9Z2CYSLNDr5UUoYMK7EY3cQv1iOnhSkD7SR6-JEMyOM&code_challenge=tLLyN6VoVCCH3uKf5zRAcXiNlFn7LSvJiQQT6xCAt-Y&code_challenge_method=S256
  302 Location: https://app.example.com/cb?code=pPeUSjCRAMwbLBmIRuhHTpU01awmD6MoNSgL4bHLyFg&state=9Z2CYSLNDr5UUoYMK7EY3cQv1iOnhSkD7SR6-JEMyOM&iss=https%3A%2F%2Fidp.example.com
  POST /token  grant_type=authorization_code&code=pPeUSjCRAMwbLBmIRuhHTpU01awmD6MoNSgL4bHLyFg&code_verifier=MZFm78-fgofDubAKPPXUGzMVZ5Xib7r83Wo7HwzzcTcAX6e4LNqfU4
  [PASS] alice's session is logged in as: alice
  [PASS] the same callback URL replayed: REJECTED (error=invalid_grant (code reused))

== Eight attacks: L5 (AS without enforcement + client without state/PKCE/iss) vs L7
  1 code interception (malicious app owns the custom scheme)
      L5: attacker holds victim tokens
      L7: blocked: error=invalid_grant (PKCE)
  2 code injection into the attacker's own session
      L5: attacker's browser is logged in as victim
      L7: blocked: REJECTED (error=invalid_grant (PKCE))
  3 PKCE downgrade: challenge-less code injected into a PKCE-using client
      L5: attacker's browser is logged in as victim
      L7: blocked: AS refused the challenge-less request (error=invalid_request (PKCE S256 required))
  4 'plain' challenge read from a logged authorization URL
      L5: attacker holds victim tokens
      L7: blocked: error=invalid_request (PKCE S256 required)
  5 code replay after the client already redeemed it
      L5: second token set issued
      L7: blocked: error=invalid_grant (code reused) revoked tokens of replayed code;
  6 login CSRF: victim's browser completes the attacker's login
      L5: victim is silently logged into the attacker's account
      L7: blocked: REJECTED (state)
  7 mix-up: user picks evil IdP, evil IdP bounces to the honest IdP
      L5: evil IdP replays the leaked code (+verifier) at the honest IdP
      L7: blocked: REJECTED (iss https://idp.example.com != https://evil-idp.example)
  8 redirect_uri=https://app.example.com/cb/../../attacker
      L5: code delivered to attacker path: https://app.example.com/cb/../../attacker?cod...
      L7: blocked: error=invalid_request (redirect_uri)
  [PASS] L5 loses 8 of 8
  [PASS] L7 blocks all 8
  [PASS] L7 token endpoint: a code_verifier for a code with no stored challenge -> error=invalid_grant (code_verifier without code_challenge)

verdict: OK (8 checks)
```

Reading the run:

- **Attack 1, interception.** The thief has the code but not V. In L7, the AS's PKCE check rejects. In L5, any public client is fully compromised by a custom-scheme hijack.
- **Attack 2, injection.** This is the attack that justifies PKCE for **confidential** clients. The attacker's own session has a perfectly valid `state`, and the honest client authenticates perfectly at the token endpoint. Only PKCE notices that the code belongs to someone else's session.
- **Attack 3, downgrade.** The interesting case is mixed: an L7 client that always sends PKCE, talking to an AS that will mint a challenge-less code when asked. The attacker requests one (no challenge), injects it, and the client dutifully sends *its* verifier. An AS that ignores verifiers for challenge-less codes issues tokens. L7 closes it twice: the AS refuses challenge-less requests, and the token endpoint rejects verifier-without-challenge (the last check line).
- **Attack 4, `plain`.** With `plain` the challenge *is* the verifier, so anyone who sees the authorization URL (proxy log, mobile system log) can redeem a leaked code. S256's preimage resistance is the whole point.
- **Attack 5, replay.** RFC 6749 §4.1.2: the AS SHOULD revoke all tokens previously issued from a code that is presented twice, because a replay means the code leaked. L7 does, and so does Spring Authorization Server [D]. The legitimate client loses its tokens too, which is correct: you cannot tell who is who.
- **Attack 6, login CSRF.** The victim ends up logged into the *attacker's* account and then enters a card number or uploads documents into it. `state` (and PKCE) stop it. The impact is real: account linking, data capture.
- **Attack 7, mix-up.** In L5 the client redeems the honest AS's code at the evil AS's token endpoint, sending its PKCE verifier along, and the evil AS replays both at the honest AS. PKCE cannot help, because the client itself hands over V. RFC 9207's `iss` check catches the response before any token request is made.
- **Attack 8, redirect traversal.** Exact matching refuses `/cb/../../attacker` at the authorization endpoint, so no code is ever created for it (file 01, L15).

---

## 4. Implementation details that decide real incidents

### 4.1 Storing `state` and the verifier

- **Server-side session, keyed by the `__Host-` session cookie** (Folder 01 file 01). Not in a cookie of its own unless it is encrypted and integrity-protected and bound to the session, and never in `localStorage`.
- **One flow per session, or a map keyed by `state`.** Users open multiple tabs, and a single slot silently breaks concurrent logins, which teams "fix" by disabling the state check [E].
- **TTL of about 10 minutes**, and delete on use.

Spring stores the `OAuth2AuthorizationRequest`, including the PKCE `code_verifier` attribute and the OIDC nonce, in the session through `HttpSessionOAuth2AuthorizationRequestRepository` [D].

### 4.2 Spring Security client: turning PKCE on for confidential clients

```java
@Bean
ClientRegistrationRepository clientRegistrations() {
    ClientRegistration idp = ClientRegistration.withRegistrationId("idp")
        .clientId("web-portal")
        .clientAuthenticationMethod(ClientAuthenticationMethod.PRIVATE_KEY_JWT)
        .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
        .redirectUri("{baseUrl}/login/oauth2/code/{registrationId}")   // expands to ONE exact https URI per environment
        .scope("openid", "payments:read")
        .issuerUri("https://idp.example.com")
        .authorizationUri("https://idp.example.com/oauth2/authorize")
        .tokenUri("https://idp.example.com/oauth2/token")
        .jwkSetUri("https://idp.example.com/oauth2/jwks")
        .clientSettings(ClientRegistration.ClientSettings.builder().requireProofKey(true).build()) // not the default
        .build();
    return new InMemoryClientRegistrationRepository(idp);
}
```

`DefaultOAuth2AuthorizationRequestResolver` applies `OAuth2AuthorizationRequestCustomizers.withPkce()` when the client is public **or** `isRequireProofKey()` is true [D: lines 206–208]. For OIDC it also stores the nonce and sends its SHA-256 hash, so the raw nonce never appears in the front channel.

### 4.3 Spring Authorization Server: what it enforces

[D: 7.1.2 sources]
- **PKCE parameters.** `OAuth2AuthorizationCodeRequestAuthenticationValidator`: if `code_challenge` is present, `code_challenge_method` must be exactly `S256`. If it is absent and `requireProofKey` is true, the request is `invalid_request`.
- **Verifier check.** `CodeVerifierAuthenticator`: when the client requires PKCE, *or a `code_verifier` is present*, the verifier is checked against the stored challenge. A verifier with no stored challenge fails. That is the downgrade rule.
- **Code replay.** `OAuth2AuthorizationCodeAuthenticationProvider`: a reused code invalidates the refresh token (or the access token if there is no refresh token) already issued for that authorization, and logs a warning.
- **Code TTL.** 5 minutes (`TokenSettings.authorizationCodeTimeToLive`). Lower it to ≤ 1 minute for interactive flows [E].

### 4.4 The `iss` parameter

RFC 9207: the AS adds `iss=<issuer>` to every authorization response (including error responses) and advertises `authorization_response_iss_parameter_supported: true` in its metadata. The client compares `iss` with the issuer of the AS it sent the user to. If the AS advertises support and `iss` is missing, the client rejects the response [D]. Clients that talk to exactly one AS still benefit, because the check is cheap and it future-proofs adding a second AS.

---

## 5. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 client callback - DO NOT USE.
@GetMapping("/cb")
String callback(@RequestParam String code, HttpSession session) {          // no state check (CSRF), no iss check (mix-up)
    TokenResponse t = idp.exchange(code, null);                            // no code_verifier (injection, interception)
    session.setAttribute("user", t.idTokenClaims().get("email"));          // identity from an unvalidated claim
    return "redirect:" + session.getAttribute("returnTo");                 // returnTo came from a query parameter (open redirect)
}
```

```java
// L7 client callback - what Spring's OAuth2LoginAuthenticationFilter + this configuration already do, spelled out.
@GetMapping("/cb")
String callback(@RequestParam String code, @RequestParam String state, @RequestParam(required = false) String iss,
                HttpServletRequest req) {
    PendingFlow f = flows.removeByState(req.getSession(false), state);        // single use; absent -> 400
    if (f == null || !f.issuer().equals(iss)) throw new BadRequest("state/iss"); // CSRF + mix-up
    TokenSet t = f.as().exchange(code, f.codeVerifier(), clientAssertion(f.as().issuer())); // PKCE + aud=issuer
    IdToken id = idTokenValidator.validate(t.idToken(), f.as(), f.nonce());   // Folder 03: iss, aud, nonce, exp, at_hash
    req.changeSessionId();                                                    // Folder 01 file 01: rotate on login
    return "redirect:" + f.returnTo();                                        // server-side, same-origin path stored at start
}
```

| Control | L5 | L7 |
|---|---|---|
| CSRF on the callback | none | `state` from the server-side session, single use |
| Code binding | none | PKCE S256 with a 32-byte verifier |
| AS identity | assumed | RFC 9207 `iss` == stored issuer; distinct redirect URI per AS |
| Code lifetime and reuse | long, reusable | ≤ 60 s, single-use, reuse revokes issued tokens |
| Downgrade | AS mints challenge-less codes and ignores stray verifiers | AS requires S256; verifier-without-challenge → `invalid_grant` |
| Return URL | query parameter | stored server-side at flow start, same origin only |
| Session | unchanged | rotated after login |

---

## 6. Real-world attack vectors & mitigations

### A1 · Authorization code interception on mobile (custom URL schemes)

**Attack.** A malicious app registers the same custom scheme (`com.example.app:/cb`). The OS delivers the redirect, carrying the code, to the attacker's app. Without PKCE, the public client's code is immediately redeemable.
**Wire signature.** Token requests for codes from installation IDs or networks that never started the flow. Duplicate redemption attempts.
**Root cause.** Custom schemes are not owned. Public clients have no credential.
**Mitigation.** PKCE S256 (L16 #1). Claimed HTTPS redirects (Android App Links, iOS Universal Links) or loopback redirects (RFC 8252). The system browser, never embedded web views.
**Detection.** Redemption-source anomalies; code reuse events.

### A2 · Authorization code injection

**Attack.** The attacker obtains a victim's code (Referer leak, log, open redirector, malicious browser extension) and injects it into *their own* session with the honest client, which redeems it with valid client credentials. The attacker's browser is now logged in as the victim, or linked to the victim's resources (L16 #2).
**Wire signature.** A callback whose code was issued for a different browser session; with PKCE, an `invalid_grant` PKCE failure at the AS.
**Root cause.** Codes not bound to the initiating session.
**Mitigation.** PKCE for **all** clients (OAuth 2.1 §7.5.1.1), or OIDC nonce validation for confidential OIDC clients under the conditions of RFC 9700 §4.5.3.2. Short code TTL.
**Detection.** Alert on PKCE-mismatch rates per client. A sudden rise means someone is injecting codes.

### A3 · PKCE downgrade

**Attack.** The attacker causes a challenge-less authorization request: a crafted link to the AS without `code_challenge`, or a client feature flag. The AS mints a code without a challenge, which is then injected into a PKCE-using client session. If the AS ignores the verifier because no challenge was stored, injection works again (L16 #3).
**Wire signature.** Authorization requests without `code_challenge` for clients that normally send it; token requests with a `code_verifier` for challenge-less codes.
**Root cause.** PKCE optional at the AS; verifier presence not cross-checked.
**Mitigation.** Enforce PKCE per client. Reject `code_verifier` when no challenge was stored (RFC 9700 §4.8.2; SAS `CodeVerifierAuthenticator`).
**Detection.** Count challenge-less requests per client ID: it should be zero.

### A4 · `plain` challenge leakage

**Attack.** With `code_challenge_method=plain`, the authorization URL contains the verifier itself. Anyone who can read requests (A4: proxy logs, mobile system logs, browser sync) and also obtain the code can redeem it (L16 #4).
**Wire signature.** `code_challenge_method=plain`, or the method absent (RFC 7636 defaults to `plain` when the method is omitted).
**Root cause.** A mode added for clients that could not compute SHA-256 in 2015.
**Mitigation.** S256 only (OAuth 2.1 prohibits `plain`; Spring Authorization Server rejects anything but S256). Treat a missing method as an error, not as `plain`.
**Detection.** Any `plain` or missing method is a configuration incident.

### A5 · Code replay and racing thieves

**Attack.** A leaked code is redeemed twice, by the attacker racing the client or later through logs. Without single-use enforcement, both succeed (L16 #5).
**Wire signature.** The second redemption of a code.
**Root cause.** Codes stored as reusable lookups.
**Mitigation.** Single use with an atomic compare-and-set in the code store. On reuse, revoke the tokens already issued for that code (RFC 6749 §4.1.2; L7 and SAS both do this). TTL ≤ 60 s.
**Detection.** Code-reuse warnings (SAS logs "Invalidated authorization token(s) previously issued").

### A6 · Login CSRF and account linking

**Attack.** The attacker completes their *own* authorization in the victim's browser by sending the victim a callback URL with the attacker's code. The victim is now logged into the attacker's account, or the attacker's identity is linked to the victim's local account (L16 #6).
**Wire signature.** Callbacks arriving with no matching flow in the session; account-linking events immediately after a link click.
**Root cause.** The callback is not bound to a flow the browser started.
**Mitigation.** `state` checked against the server-side session, single use. PKCE also prevents it (RFC 9700 §4.7.1). Require re-authentication before linking accounts.
**Detection.** Rejected-state metrics; link events without a preceding login click.

### A7 · Mix-up attacks

**Attack.** In a multi-AS client, the attacker AS bounces the user to the honest AS while the client believes it is talking to the attacker AS. The client sends the honest code and verifier to the attacker's token endpoint (L16 #7). Variants target the authorization endpoint itself and dynamic registration.
**Wire signature.** `iss` mismatches; token requests to an AS for unknown codes.
**Root cause.** Responses that do not identify their issuer.
**Mitigation.** RFC 9207 `iss`, checked. Distinct redirect URIs per AS. PAR with signed request objects (Folder 04) for high-assurance ecosystems.
**Detection.** Alert on any `iss` mismatch.

### A8 · Redirect URI path confusion

**Attack.** A prefix-matched redirect URI sends the code to `/cb/../../attacker`, `/cb%2F..%2F…` or a path that an attacker can host on the same origin, such as a user profile page that logs referrers (L16 #8, L15).
**Wire signature.** `redirect_uri` values that differ from the registered string.
**Root cause.** Prefix or pattern matching.
**Mitigation.** Exact string matching. No open redirectors. `Referrer-Policy: no-referrer` on the callback.
**Detection.** Log mismatched `redirect_uri` attempts per client.

---

## 7. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · Draw the authorization code flow and point at every place a secret can leak.</b></summary>

**Initial Prompt.** Whiteboard it for a mobile app and a server-side web app.

**L5 Textbook Answer.** Five arrows: redirect, login, code back, code for token, API call. "The code can be intercepted, so we use HTTPS."

**How an Attacker Bypasses L5.** HTTPS protects the wire, not the *endpoints* of the front channel:
- the code lands in browser history, in the `Referer` of the next navigation, and in reverse-proxy access logs;
- on mobile it lands in whichever app owns the scheme.

The authorization URL itself leaks, and with `plain` that leaks the verifier too. The token response leaks if it is cached by an intermediary without `Cache-Control: no-store`.

**L7 Principal Defense.** Mark each artefact with who can see it:
- **The code** is front channel: short TTL, single use, bound by PKCE S256, delivered only to an exact redirect URI.
- **`state`** is front channel, which is fine because it is not a secret, only a session binding.
- **The verifier** never leaves the client.
- **The token response** is back channel, `no-store`.
- **The access token** is short-lived, audience-restricted, ideally DPoP-bound.

Then add `iss` for multi-AS clients and `Referrer-Policy: no-referrer` on the callback. For mobile: claimed HTTPS links or loopback, and the system browser.

</details>

<details><summary><b>Q2 · State vs PKCE vs nonce: why do we need all three?</b></summary>

**Initial Prompt.** A team wants to drop `state` "because PKCE covers CSRF".

**L5 Textbook Answer.** "They're all random values that do the same thing, so one is enough."

**How an Attacker Bypasses L5.** They bind different things:
- PKCE stops injection but not mix-up, because the client itself sends V to the wrong AS (L16 #7).
- `state` stops CSRF but not injection with the attacker's own state (#2).
- `nonce` only protects the ID token, and only if the client validates it before acting.

Dropping `state` also loses the place to carry the per-flow context: expected issuer, return URL, a multi-tab map.

**L7 Principal Defense.**
- **Keep `state`:** CSRF binding and the key to the server-side flow record holding issuer, verifier, nonce and return URL.
- **Keep PKCE:** the code-to-session binding at the AS.
- **Keep `nonce`:** the ID-token-to-session binding (Folder 03).
- **Add `iss` checking** for mix-up.

RFC 9700 says PKCE "prevents CSRF", but that is a property of the AS check, while `state` is the client's own check. Both together mean an AS bug or a client bug alone is not enough.

</details>

<details><summary><b>Q3 · A pentester reports "PKCE downgrade possible". Explain and fix.</b></summary>

**Initial Prompt.** Your clients always send PKCE. How can it be downgraded?

**L5 Textbook Answer.** "Not possible; our client library always adds `code_challenge`."

**How an Attacker Bypasses L5.** The attacker does not use your client to start the flow. They craft an authorization URL for your `client_id` *without* `code_challenge`, get a code minted for the victim, and inject it into a PKCE-using session. Your client sends a verifier, and an AS that ignores verifiers for challenge-less codes redeems it (L16 #3: an L7 client against an L5 AS still loses).

**L7 Principal Defense.** The fix is at the AS:
- **Per-client PKCE enforcement,** so challenge-less authorization requests return `invalid_request`.
- **The RFC 9700 §4.8.2 rule:** a `code_verifier` presented for a code issued without a challenge is `invalid_grant` (L16's final check; SAS's `CodeVerifierAuthenticator` checks whenever a verifier is present).
- **Only S256.**
- **Monitor** challenge-less requests per client.

The lesson is that a security property enforced only by the honest party is not enforced.

</details>

<details><summary><b>Q4 · Why does RFC 6749 say to revoke tokens when a code is reused? Isn't that punishing the legitimate client?</b></summary>

**Initial Prompt.** Your AS revoked a user's tokens after a "duplicate request". Support is angry.

**L5 Textbook Answer.** "Duplicate requests are retries. Make code redemption idempotent: return the same tokens."

**How an Attacker Bypasses L5.** An idempotent replay hands the *thief* the same tokens the client got. A code redeemed twice means it leaked, and the AS cannot know which redemption is the thief's.

**L7 Principal Defense.**
- **Reuse is evidence of compromise:**
  - fail the second redemption (`invalid_grant`);
  - revoke what the first produced (RFC 6749 §4.1.2; SAS invalidates the refresh or access token);
  - log a security event.
- **Fix retries on the client:**
  - redemption is a single back-channel POST, so time out generously and never retry automatically after the request may have reached the AS;
  - if uncertain, restart the flow.
- **Support playbook:** a revoked session after "duplicate redemption" is an alert to investigate. Check the second request's source network.

</details>

<details><summary><b>Q5 · Your client supports "Sign in with A" and "Sign in with B". Walk me through the mix-up attack and its defence.</b></summary>

**Initial Prompt.** One of the IdPs could be malicious or compromised.

**L5 Textbook Answer.** "Each IdP has a separate client ID and secret, so tokens can't be confused."

**How an Attacker Bypasses L5.**
1. The user chooses B (malicious). B redirects the user to A's authorization endpoint with the client's A `client_id` and the client's redirect URI.
2. The user logs in at A. A sends the code to the client.
3. The client's session says "B", so it posts A's code, and its PKCE verifier, to B's token endpoint.
4. B now holds a valid A code plus the verifier, and replays them at A (L16 #7, L5 row).

Separate credentials don't help, because the leaked artefact is the code and the verifier.

**L7 Principal Defense.**
- **RFC 9207:** A returns `iss=https://a…`, and the client compares it with the stored expected issuer (B), then aborts before any token request.
- **Additionally:** a distinct redirect URI per AS (`/cb/a`, `/cb/b`), where the client checks that the path matches the stored AS.
- **For high-assurance ecosystems:** PAR plus signed request objects (Folder 04) and issuer-specific client authentication (`aud = issuer`, file 04).

</details>

<details><summary><b>Q6 · How long should an authorization code live, and how do you store it?</b></summary>

**Initial Prompt.** Your AS issues 10-minute codes in a Redis cache.

**L5 Textbook Answer.** "10 minutes gives slow users time. Redis GET then DEL is fine."

**How an Attacker Bypasses L5.**
- **Too long.** A 10-minute code is a 10-minute theft window.
- **Not atomic.** GET then DEL is not atomic, so two concurrent redemptions both succeed (a race thief).
- **Plaintext keys.** Codes stored in plaintext leak through cache dumps.

**L7 Principal Defense.**
- **Lifetime:** RFC 6749 recommends a maximum of 10 minutes. Practice is ≤ 60 s, because the code is consumed by a machine milliseconds after the redirect [E]. SAS defaults to 5 minutes; lower it.
- **Storage:**
  - key = SHA-256(code);
  - atomic `GETDEL` or a Lua script, or a `DELETE … RETURNING` row;
  - the record binds client_id, redirect_uri, challenge, user, auth_time, acr and nonce;
  - reuse revokes issued tokens (Q4).
- **Contents:** codes are random 256-bit values, not JWTs carrying the grant, because self-contained codes cannot be made single-use without state anyway.

</details>

<details><summary><b>Q7 · A native desktop app uses an embedded browser control for login. What's wrong, and what's the L7 setup?</b></summary>

**Initial Prompt.** "It gives us a seamless UX."

**L5 Textbook Answer.** "It's our app, so the embedded web view is trusted."

**How an Attacker Bypasses L5.**
- **The app sees everything.** The host app can read keystrokes and cookies in an embedded view, so users learn to type IdP passwords into app chrome, which is indistinguishable from phishing.
- **Phishing-resistant MFA breaks.** WebAuthn in embedded views is restricted or unavailable, so users fall back to OTP.
- **No SSO.** There is no shared browser session.

**L7 Principal Defense.** RFC 8252:
- **The system browser** (ASWebAuthenticationSession, Custom Tabs, or the default browser).
- **Redirect** to a claimed HTTPS link or a loopback `http://127.0.0.1:{port}/cb`. The AS ignores the port for loopback only (file 01, L15).
- **Client:** PKCE S256, public client (`none`).
- **Refresh tokens:** DPoP-bound to a platform-keystore key, or rotated (file 03).
- **AS side:** treat user agents identifying as embedded web views as a risk signal.

</details>

<details><summary><b>Q8 · Is the authorization code flow safe for an SPA with no backend?</b></summary>

**Initial Prompt.** The team removed implicit and now runs code + PKCE in the browser.

**L5 Textbook Answer.** "Yes. That's exactly OAuth 2.1's recommendation for public clients."

**How an Attacker Bypasses L5.** The flow is safe against *front-channel* attackers. Against *script on the SPA's origin* it is not:
- the malicious script runs its own code + PKCE flow, piggybacking on the AS session cookie (silent `prompt=none` in an iframe or popup);
- it redeems the code with the public client ID;
- it exfiltrates tokens.

RFC 10017 calls this out as the core threat for browser apps.

**L7 Principal Defense.**
- **Sensitive data:** a BFF or token-handler. The confidential server-side client keeps the tokens, and the browser has only an `HttpOnly` cookie.
- **A pure SPA:**
  - strict CSP and Trusted Types;
  - DPoP with non-extractable keys;
  - refresh tokens rotated, with a maximum lifetime that rotation never extends (RFC 10017 §6.3.2.3);
  - short access tokens.
- Folder 04 file 03 builds both.

</details>

<details><summary><b>Q9 · How do you test that your AS really enforces PKCE, for every client, forever?</b></summary>

**Initial Prompt.** Prove it to the security review board.

**L5 Textbook Answer.** "There's a unit test for the PKCE validator."

**How an Attacker Bypasses L5.** The validator is correct, but a *configuration* bypasses it: a client registered with `requireProofKey(false)` "for a legacy partner", a new endpoint (PAR) wired without the validator, or an upgrade that changes a default.

**L7 Principal Defense.**
- **Black-box negative tests** against the deployed AS, for every client type, in CI and nightly:
  - an authorization request without a challenge;
  - `plain`;
  - a verifier mismatch;
  - a verifier for a challenge-less code;
  - code replay;
  - redirect variants (L15).
- **A registry audit** that fails the build if any client has `requireProofKey=false` without a documented exception and expiry.
- **Metrics:** challenge-less authorization requests per client (must be 0), PKCE failures per client.
- **Re-run the OpenID conformance suite** on upgrades.

L16 is the shape of those tests.

</details>

<details><summary><b>Q10 · The callback endpoint has `?returnTo=` for deep links. Review it.</b></summary>

**Initial Prompt.** After login, users land on the page they started from.

**L5 Textbook Answer.** "We check that `returnTo` starts with `/`."

**How an Attacker Bypasses L5.**
- **`//evil.example/x` starts with `/`** and is a scheme-relative URL to another host.
- **`/\evil.example` is normalized** by some browsers.
- **The code leaks.** If the callback redirects before consuming the code, the code travels in the `Referer` to the next page's third parties.

This is an open redirector on the OAuth callback, which RFC 9700 §4.11 calls out.

**L7 Principal Defense.**
- **Store the return target when the flow starts,** server-side in the flow record, validated as a same-origin path (`URI.create`, no scheme, no authority, no backslashes, allow-listed prefixes).
- **The callback consumes the code first**, then redirects to the stored target, with `Referrer-Policy: no-referrer` and `Cache-Control: no-store`.
- **Never read the target from the callback's query string.**
- **Add tests** for `//`, `/\`, encoded variants and `javascript:`.

</details>

---

## 8. Invariants checklist

- [ ] Authorization requests carry `state` (server-side, single use), `code_challenge` (S256, 32-byte verifier) and, for OIDC, `nonce`.
- [ ] The callback checks `state`, then `iss` (RFC 9207), consumes the code once, and only then redirects to a server-stored same-origin path.
- [ ] The AS enforces PKCE S256 per client, rejects `plain` and missing methods, and rejects a verifier for a challenge-less code.
- [ ] Codes: 256-bit random, ≤ 60 s, single-use through an atomic consume, stored hashed; reuse revokes tokens already issued.
- [ ] Redirect URIs matched exactly; no open redirectors near the OAuth endpoints; `Referrer-Policy: no-referrer` on callbacks.
- [ ] Token responses `Cache-Control: no-store`; the token request does not require `redirect_uri` for OAuth 2.1 clients.
- [ ] Spring client: `ClientSettings.requireProofKey(true)` for confidential registrations; Spring AS: default `requireProofKey(true)` kept; code TTL lowered.
- [ ] Multi-AS clients: a distinct redirect URI and expected issuer per AS.
- [ ] Native apps: system browser, claimed HTTPS or loopback redirects, public client with PKCE.
- [ ] Negative protocol tests (L16's eight) run against the deployed AS.

---

## 9. References

- RFC 6749 §4.1 *Authorization Code Grant* — <https://www.rfc-editor.org/rfc/rfc6749#section-4.1>
- RFC 7636 *Proof Key for Code Exchange* — <https://www.rfc-editor.org/rfc/rfc7636>
- RFC 9207 *OAuth 2.0 Authorization Server Issuer Identification* — <https://www.rfc-editor.org/rfc/rfc9207>
- RFC 9700 §4.4 mix-up, §4.5 code injection, §4.7 CSRF, §4.8 PKCE downgrade, §4.11 open redirection — <https://www.rfc-editor.org/rfc/rfc9700>
- OAuth 2.1 draft-17 §7.5 *Authorization Codes* — <https://www.ietf.org/archive/id/draft-ietf-oauth-v2-1-17.html>
- RFC 8252 *OAuth 2.0 for Native Apps* — <https://www.rfc-editor.org/rfc/rfc8252>
- Daniel Fett, Ralf Küsters, Guido Schmitz, *A Comprehensive Formal Security Analysis of OAuth 2.0* (2016, the origin of the mix-up analysis) — <https://arxiv.org/abs/1601.01229>
- Spring Security OAuth2 client, *Authorization Request* customization — <https://docs.spring.io/spring-security/reference/servlet/oauth2/client/authorization-grants.html>
