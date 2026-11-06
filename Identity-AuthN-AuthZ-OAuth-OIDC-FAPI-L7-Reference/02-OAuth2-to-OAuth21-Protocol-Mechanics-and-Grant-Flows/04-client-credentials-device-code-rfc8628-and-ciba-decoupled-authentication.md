# Client Credentials, the Device Authorization Grant (RFC 8628), and CIBA Decoupled Authentication

> Folder 02 · File 04 of 04 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [03 · Refresh tokens](03-refresh-token-rotation-reuse-detection-grace-periods-and-revocation-rfc7009.md) · First: [01 · Roles, threat model, OAuth 2.1](01-oauth2-roles-threat-model-and-what-oauth21-and-rfc9700-changed.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L19 `MachineFlowsLab.java` | `private_key_jwt` and the 2025 audience-injection vulnerability (CVE-2025-27370/27371): a malicious AS replays an assertion whose `aud` came from its metadata, and draft-ietf-oauth-rfc7523bis-11's `aud = issuer` plus `typ` stops it; jti replay. Device-grant user-code entropy vs live codes, polling and `slow_down`, device-code phishing (the Storm-2372 pattern). CIBA `auth_req_id` entropy and the `user_code` defence against unsolicited requests | RFC 8628 §3.5, §6.1; rfc7523bis-11 §4; CIBA Core §7.1, §7.3 |

**Verification.** Compiled with Folders 01–02 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The ES256 client assertions use L9 (`Jose`) from Folder 01. The gate re-runs the output and requires it byte-identical; demo identifiers use seeded generators. Normative text comes from RFC 7523, RFC 8628 and `draft-ietf-oauth-rfc7523bis-11` (dated 26 March 2026; its status was checked on the IETF Datatracker on 2026-11-03) in [`fixtures/`](fixtures/), and from OpenID CIBA Core 1.0. The CVE descriptions come from the OpenID Foundation notice.

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

Three grant families cover everything the redirect-based code flow cannot:
- **Client credentials:** a workload acting as itself.
- **The device authorization grant:** a user approving, on their phone, a device with no browser or keyboard.
- **CIBA:** a relying party asking the user to approve on their own authentication device, with no redirect at all.

Each removes the browser redirect, and with it the protections file 02 built into the redirect: exact redirect URIs, PKCE bound to the browser session, origin-bound WebAuthn on the same device. What remains has to be rebuilt as policy. This file shows where that rebuilding usually fails.

Results:
- **[M][D] Audience injection.** A malicious AS can publish metadata whose `token_endpoint` is the *honest* AS's token endpoint. A client that uses that endpoint as the `aud` of its `private_key_jwt` assertion and sends it to the malicious AS hands over an assertion the attacker replays at the honest AS. L19's L5 honest AS issues a token to `payments-batch`. rfc7523bis-11 requires `aud` = the AS's issuer identifier as the sole value, so the replay is rejected.
- **[M]** RFC 8628's recommended 8 base-20 characters give 20^8 ≈ 2.56 × 10^10, about 34.6 bits, *per code*. Brute force targets **any live code**: with 200,000 outstanding codes, 1,000,000 unthrottled guesses hit one with probability ≈ 99.96%. Rate limiting must be global, not per code.
- **[D] ⚠** Spring Security 7.1.2's `NimbusJwtClientAuthenticationParametersConverter` signs client assertions with `aud = [tokenUri]` by default, the endpoint form that rfc7523bis forbids. §6.2 shows the one-line customizer that sets the issuer.
- **[M][D] Device-code phishing,** as in Microsoft's Storm-2372 report (Feb 2025). The attacker starts the flow, the victim enters the code on the *legitimate* verification page (MFA included), and the attacker's poll receives the victim's tokens. Restricting the grant to device-class clients, and checking the initiator's network context, stops it in L19.
- **[M][D]** CIBA's optional `user_code` (a secret known only to the user and verifiable by the OP) stops unsolicited backchannel requests before they reach the user's phone. `auth_req_id` must carry at least 128 bits (160 recommended) [D: CIBA §7.3].

---

## 1. First principles: three flows without a redirect

```text
  CLIENT CREDENTIALS (RFC 6749 4.4)          DEVICE GRANT (RFC 8628)                      CIBA (OpenID, poll/ping/push)
  -------------------------------           ------------------------------------         -------------------------------------
  workload --assertion/mTLS--> AS            TV  --POST /device_authorization--> AS        RP  --POST /bc-authorize (login_hint,
  AS --access_token(aud, 5 min)--> workload  AS  --device_code, user_code, uri--> TV           binding_message, user_code)--> OP
  no user, no refresh token                  TV shows "go to example.com/device,         OP --push--> user's phone: "approve
  identity = the client itself                enter WDJB-MJHT"                               W4SCT at Example Bank?"
                                             user's PHONE: logs in, enters code,         RP polls /token with auth_req_id
                                               approves                                  (or OP pings / pushes the result)
                                             TV polls /token with device_code
  binding: client key                        binding: user_code typed by a human        binding: binding_message read by a human
  failure: aud injection, shared secrets     failure: code phishing, code brute force   failure: unsolicited prompts, fatigue
```

The common thread: in the device grant and CIBA, the **human is the binding**. The user code, or the binding message, is what ties the approval on one device to the session on another. Whatever the human can be talked into, an attacker can exploit. That is why these flows need context on the approval screen and restrictions on who may start them [E].

---

## 2. Client credentials and asymmetric client authentication

### 2.1 The request

```http
POST /oauth2/token HTTP/1.1
Host: idp.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=payments%3Abatch&resource=https%3A%2F%2Fpayments.example.com&client_assertion_type=urn%3Aietf%3Aparams%3Aoauth%3Aclient-assertion-type%3Ajwt-bearer&client_assertion=eyJhbGciOiJFUzI1NiIsImtpZCI6Ii4uLiIsInR5cCI6ImNsaWVudC1hdXRoZW50aWNhdGlvbitqd3QifQ.eyJpc3MiOiJwYXltZW50cy1iYXRjaCIsInN1YiI6InBheW1lbnRzLWJhdGNoIiwiYXVkIjoiaHR0cHM6Ly9pZHAuZXhhbXBsZS5jb20iLC4uLn0.<sig>
```

The decoded assertion header and claims:

```json
{"alg": "ES256", "kid": "<RFC 7638 thumbprint of the client key>", "typ": "client-authentication+jwt"}
```

```json
{"iss": "payments-batch", "sub": "payments-batch", "aud": "https://idp.example.com",
 "iat": 1767225600, "exp": 1767225660, "jti": "jti-ok"}
```

AS validation [D: RFC 7523 §3, rfc7523bis-11 §4]:
- signature with the client's *registered* key (from its `jwks_uri` or registration);
- `iss` = `sub` = `client_id`;
- **`aud` = this AS's issuer identifier, as the sole value**, compared with RFC 3986 simple string comparison;
- `exp` present and short (L19 rejects more than 300 s ahead);
- `jti` not seen before within `exp` (replay).

`typ: client-authentication+jwt` SHOULD be used. The draft says the primary security protection is the audience rule, and the explicit type is a signal distinguishing new-style tokens.

### 2.2 The audience-injection attack, step by step

```mermaid
sequenceDiagram
    autonumber
    participant C as Client (payments-batch)
    participant E as Evil AS (metadata issuer = evil, token_endpoint = HONEST)
    participant H as Honest AS
    C->>E: fetch metadata (issuer validated; endpoints cannot be)
    C->>E: POST /par (or any endpoint) + client_assertion aud = metadata.token_endpoint = honest token URL
    E->>H: POST /token client_credentials + the harvested client_assertion
    H-->>E: access_token for payments-batch (L5: aud matched its token endpoint)
    Note over C,H: rfc7523bis: client sets aud = issuer it is talking to (evil); honest AS requires aud == its own issuer
```

The OIDF notice credits University of Stuttgart researchers, found during formal analysis of OpenID Federation, and assigned CVE-2025-27370 (OpenID `private_key_jwt`) and CVE-2025-27371 (RFC 7521/7523 assertions). Corrective actions were made in the OpenID specifications and certification tests, and the OAuth fix is `draft-ietf-oauth-rfc7523bis` [D].

### 2.3 Token caching and audience per call

A client-credentials token is a credential for one audience. Cache it until `exp − skew`, per (audience, scope set), and request a new one per downstream API. Never reuse one broad token everywhere (Folder 05's token exchange). Many "rate limit exceeded at the AS" incidents are services requesting a token per request [E].

---

## 3. The device authorization grant (RFC 8628)

### 3.1 On the wire

```http
POST /oauth2/device_authorization HTTP/1.1
Host: idp.example.com
Content-Type: application/x-www-form-urlencoded

client_id=tv-app&scope=openid%20profile%20media%3Aplay
```

```json
{"device_code": "GmRhmhcxhwAzkoEqiMEg_DnyEysNkuNhszIySk9eS",
 "user_code": "WDJB-MJHT",
 "verification_uri": "https://example.com/device",
 "verification_uri_complete": "https://example.com/device?user_code=WDJB-MJHT",
 "expires_in": 1800, "interval": 5}
```

The device then polls `POST /oauth2/token` with `grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=…&client_id=tv-app`, receiving `authorization_pending`, `slow_down`, `access_denied`, `expired_token` or tokens. On `slow_down`, "the interval MUST be increased by 5 seconds for this and all subsequent requests" [D: RFC 8628 §3.5]. L19 shows the interval going from 5 to 10 s.

### 3.2 User-code entropy is a shared budget

RFC 8628 §6.1 recommends the base-20 alphabet `BCDFGHJKLMNPQRSTVWXZ` (case-insensitive, no vowels) with 8 significant characters, giving "an entropy of 20^8". §5.1 requires rate limiting [D]. The subtle part is that an attacker does not need *your* code, **any** pending approval will do: they enter a guessed code and, if it matches someone's pending TV login, they approve *their own* account onto the victim's TV, or deny it. And for a mirror-image variant, the attacker initiates and the victim approves. The success probability over *n* guesses with *L* live codes is `1 − (1 − L/20^8)^n` (L19's table) [M]:
- with one live code, a million guesses barely matter (0.004%);
- with 200,000 live codes during a streaming launch, they almost certainly hit one (99.96%).

Rate-limit verification attempts globally and per source, and keep `expires_in` short [E].

### 3.3 Device-code phishing

Microsoft reported Storm-2372 running device-code phishing since August 2024 [D: Microsoft Threat Intelligence, 2025-02-13]:
1. The attacker generates a legitimate device code and sends the victim a lure ("join the Teams meeting, enter code …").
2. The victim enters it on the **real** Microsoft sign-in page and completes MFA.
3. The attacker's poll receives the tokens.

Microsoft's follow-up noted the actor switching to the Microsoft Authentication Broker client ID, so it could obtain refresh tokens usable to register attacker-controlled devices in Entra ID. Microsoft's guidance is to block the device code flow wherever possible, restrict it with Conditional Access where it is needed, and revoke refresh tokens if phishing is suspected. Everything is legitimate except the *initiator*, which is why phishing-resistant MFA does not help here.

```text
  t=0     attacker (VPS)  --POST /device_authorization client_id=<trusted desktop client>-->  AS
          AS --> attacker: device_code=D, user_code=WDJB-MJHT, verification_uri=https://login.example.com/device
  t=1m    attacker --> victim (chat/email lure): "enter WDJB-MJHT at login.example.com/device to join the meeting"
  t=3m    victim browser --> REAL login.example.com/device : enters code, password + MFA (even a passkey!) -> "Approve"
  t=3m+5s attacker --POST /token grant_type=device_code&device_code=D--> AS --> access + refresh tokens (victim's)
          |                                                                    |
          what L7 changes:  client allow-list for the device grant      the approval page shows "a device in
                            (desktop clients may not start it)           <attacker VPS ASN / country> is asking";
                            short expires_in; Conditional Access         network mismatch -> step-up or block
```

L7 mitigations in L19, and in practice [E]:
- **Allow the device grant only for clients that are actually input-constrained devices** (`tv-app`, `cli`), never for desktop or office clients. L19's L7 AS blocks `office-desktop`.
- **Show the initiator's context on the verification page:** client name, initiating IP and geography, time. Step up or block when the initiator's network differs from the approver's (L19).
- **Keep `expires_in` short** (5–15 minutes rather than 30) and kill unused codes.
- **Detect:** device-code grants completed from networks never seen for the user; Conditional Access policies scoped to "device code flow".

---

## 4. CIBA: decoupled authentication

CIBA (OpenID Client-Initiated Backchannel Authentication Core 1.0) lets a client, such as a call-centre agent tool, a point-of-sale terminal or a smart speaker, ask the OP to authenticate a user identified by a hint, on the user's own device.

```http
POST /bc-authorize HTTP/1.1
Host: idp.example.com
Content-Type: application/x-www-form-urlencoded

scope=openid%20payments&client_assertion_type=urn%3Aietf%3Aparams%3Aoauth%3Aclient-assertion-type%3Ajwt-bearer&client_assertion=eyJ...&login_hint=alice%40example.com&binding_message=W4SCT&user_code=4711&requested_expiry=120
```

```json
{"auth_req_id": "1c266114-a1be-4252-8ad1-04986c5b9ac1", "expires_in": 120, "interval": 2}
```

Then, depending on `backchannel_token_delivery_mode`:
- **poll**: the client polls `/token` with `grant_type=urn:openid:params:grant-type:ciba&auth_req_id=…`;
- **ping**: the OP calls the client's notification endpoint, then the client fetches the token;
- **push**: the OP delivers the tokens to the client's endpoint.

FAPI-CIBA restricts to poll or ping, with signed requests [D].

Security properties, and what goes wrong:
- **`auth_req_id`** "MUST contain sufficient entropy (a minimum of 128 bits while 160 bits is recommended)", and is restricted to base64url characters [D: CIBA §7.3]. L19 generates 160 bits, which is 27 characters.
- **`binding_message`** is "intended to be displayed on both the consumption device and the authentication device to interlock them together for the transaction" [D]. It is only as good as the user's comparison, and users under prompt fatigue tap "approve". That is the CIBA version of push bombing (Folder 01 file 01's Uber case).
- **`user_code`** is "a secret code, such as a password or pin, that is known only to the user but verifiable by the OP. The code is used to authorize sending an authentication request to the user's authentication device" [D]. Requiring it (`backchannel_user_code_parameter`) means an attacker who knows only the user's email cannot trigger prompts at all. L19's L7 OP rejects before anything reaches the phone.
- **Rate limits per `login_hint`,** and signed authentication requests (`request` JWT) for high-value deployments [E].

---

## 5. L19: all three flows, measured

<!-- listing:MachineFlowsLab.java -->
```java
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.SplittableRandom;

/**
 * L19 - flows without a browser redirect: client credentials with private_key_jwt, the device authorization grant
 * (RFC 8628) and CIBA (OpenID Client-Initiated Backchannel Authentication), each as L5 vs L7 policy.
 *
 * <ul>
 *   <li>private_key_jwt and the 2025 audience-injection vulnerability (CVE-2025-27370/27371): a malicious AS whose
 *       metadata names the HONEST token endpoint harvests assertions it can replay; draft-ietf-oauth-rfc7523bis-11
 *       requires aud = the AS issuer identifier as the sole value, and typ client-authentication+jwt;</li>
 *   <li>device flow: user-code entropy vs the NUMBER OF LIVE CODES, polling/slow_down, and device-code phishing;</li>
 *   <li>CIBA: auth_req_id entropy, binding_message, and unsolicited-request ("approve bombing") defence via user_code.</li>
 * </ul>
 */
public final class MachineFlowsLab {
    static final long NOW = 1_767_225_600L;
    static final String HONEST = "https://idp.example.com";
    static final String EVIL = "https://evil-idp.example";

    record Metadata(String issuer, String tokenEndpoint, String parEndpoint) {
    }

    /** A confidential client that authenticates with a private key; L5 uses the endpoint as aud, L7 the issuer. */
    static String clientAssertion(Jose.Jwk key, Metadata md, boolean l7, String jti) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", "ES256");
        h.put("kid", key.kid());
        if (l7) {
            h.put("typ", "client-authentication+jwt");
        }
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("iss", "payments-batch");
        c.put("sub", "payments-batch");
        c.put("aud", l7 ? md.issuer() : md.tokenEndpoint());
        c.put("iat", NOW);
        c.put("exp", NOW + 60);
        c.put("jti", jti);
        return Jose.sign(h, MiniJson.write(c).getBytes(StandardCharsets.UTF_8), key);
    }

    /** The honest AS's token endpoint, verifying a client assertion. */
    static final class HonestTokenEndpoint {
        final boolean l7;
        final Jose.Jwk clientKey;
        final Set<String> seenJti = new HashSet<>();

        HonestTokenEndpoint(boolean l7, Jose.Jwk clientKey) {
            this.l7 = l7;
            this.clientKey = clientKey;
        }

        String authenticate(String assertion) {
            Jose.Parts p = Jose.parse(assertion);
            if (!Jose.rawVerify("ES256", clientKey, p.signingInput(), p.sig())) {
                return "invalid_client (signature)";
            }
            Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
            Object aud = c.get("aud");
            boolean audOk = l7 ? HONEST.equals(aud) // sole value, exactly the issuer identifier
                    : Set.of(HONEST, HONEST + "/oauth2/token").contains(aud) || aud instanceof List<?> l && l.contains(HONEST);
            if (!audOk) {
                return "invalid_client (aud " + aud + ")";
            }
            if (l7 && !"client-authentication+jwt".equals(p.header().get("typ"))) {
                return "invalid_client (typ)";
            }
            if (!(c.get("exp") instanceof Long exp) || exp < NOW || exp - NOW > 300) {
                return "invalid_client (exp)";
            }
            if (!seenJti.add((String) c.get("jti"))) {
                return "invalid_client (jti replay)";
            }
            return "access_token issued to " + c.get("sub");
        }
    }

    // ---------------------------------------------------------------- device authorization grant

    static final String BASE20 = "BCDFGHJKLMNPQRSTVWXZ";

    static String userCode(SplittableRandom r) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 8; i++) {
            if (i == 4) {
                sb.append('-');
            }
            sb.append(BASE20.charAt(r.nextInt(20)));
        }
        return sb.toString();
    }

    /** P(an attacker hits ANY live code) with `attempts` guesses while `live` codes are outstanding. */
    static double hitAny(long attempts, long live, double space) {
        return 1 - Math.exp(attempts * Math.log1p(-live / space));
    }

    record DeviceGrant(String deviceCode, String userCode, String clientId, String initiatorNet, long expiresAt, int[] interval,
                       String[] approvedBy) {
    }

    /** The device-flow AS. L7 shows initiator context, restricts the grant to allow-listed clients, and checks network. */
    static final class DeviceAs {
        final boolean l7;
        final Map<String, DeviceGrant> byUserCode = new LinkedHashMap<>();
        final Map<String, DeviceGrant> byDeviceCode = new LinkedHashMap<>();
        final Map<String, Long> lastPoll = new LinkedHashMap<>();
        final SplittableRandom r = new SplittableRandom(8628L);

        DeviceAs(boolean l7) {
            this.l7 = l7;
        }

        DeviceGrant start(String clientId, String net, long now) {
            DeviceGrant g = new DeviceGrant("dc-" + Long.toHexString(r.nextLong()), userCode(r), clientId, net, now + 900,
                    new int[] {5}, new String[1]);
            byUserCode.put(g.userCode(), g);
            byDeviceCode.put(g.deviceCode(), g);
            return g;
        }

        /** The verification page. Returns what happened when `user` on network `net` entered the code. */
        String approve(String code, String user, String net, long now) {
            DeviceGrant g = byUserCode.get(code);
            if (g == null || now > g.expiresAt()) {
                return "expired_token";
            }
            if (l7) {
                if (!Set.of("tv-app", "cli").contains(g.clientId())) {
                    return "blocked: device flow not enabled for client " + g.clientId();
                }
                if (!g.initiatorNet().equals(net)) { // the page also SHOWS: "a device in <network/geo> is asking..."
                    return "step-up: initiating device is on " + g.initiatorNet() + ", you are on " + net + " - confirm with passkey";
                }
            }
            g.approvedBy()[0] = user;
            return "approved";
        }

        String poll(String deviceCode, long now) {
            DeviceGrant g = byDeviceCode.get(deviceCode);
            Long last = lastPoll.put(deviceCode, now);
            if (last != null && now - last < g.interval()[0]) {
                g.interval()[0] += 5; // RFC 8628 3.5: slow_down increases the interval by 5 s
                return "slow_down (interval now " + g.interval()[0] + " s)";
            }
            return g.approvedBy()[0] == null ? "authorization_pending" : "access_token for " + g.approvedBy()[0];
        }
    }

    // ---------------------------------------------------------------- CIBA

    /** Backchannel authentication; L7 requires a user_code known only to the user and rate-limits per login_hint. */
    static final class CibaOp {
        final boolean l7;
        final Map<String, Integer> perHint = new LinkedHashMap<>();
        final Map<String, String> userCodes = Map.of("alice@example.com", "4711");

        CibaOp(boolean l7) {
            this.l7 = l7;
        }

        String backchannel(String loginHint, String bindingMessage, String userCode, boolean userTapsApprove) {
            if (l7) {
                int n = perHint.merge(loginHint, 1, Integer::sum);
                if (n > 3) {
                    return "slow_down (per-user request budget)";
                }
                if (!userCodes.get(loginHint).equals(userCode)) {
                    return "invalid_user_code (initiator does not know the user's code)";
                }
            }
            // the authentication device shows binding_message; a fatigued user taps "approve" anyway
            return userTapsApprove ? "approved (binding_message '" + bindingMessage + "')" : "access_denied";
        }
    }

    public static void main(String[] args) throws Exception {
        SecureRandom rng = new SecureRandom();
        Jose.Jwk clientKey = Jose.generate("ES256", rng);

        KbSupport.section("private_key_jwt audience injection (CVE-2025-27370/27371, draft-ietf-oauth-rfc7523bis-11)");
        Metadata evil = new Metadata(EVIL, HONEST + "/oauth2/token", EVIL + "/par"); // issuer validated; endpoints are not
        for (boolean l7 : new boolean[] {false, true}) {
            String harvested = clientAssertion(clientKey, evil, l7, "jti-" + l7); // sent by the client to EVIL's PAR endpoint
            Map<String, Object> claims = MiniJson.object(new String(Jose.parse(harvested).payload(), StandardCharsets.UTF_8));
            String replay = new HonestTokenEndpoint(l7, clientKey).authenticate(harvested); // evil replays at the honest AS
            KbSupport.info("%s client signs aud=%-38s -> honest AS: %s", l7 ? "L7" : "L5", claims.get("aud"), replay);
            KbSupport.check(l7 ? "L7: aud is the issuer the client is talking to, so the honest AS rejects the replay"
                    : "L5: aud taken from attacker-supplied metadata; the honest AS accepts the replayed assertion",
                    l7 == replay.startsWith("invalid_client"));
        }
        HonestTokenEndpoint te = new HonestTokenEndpoint(true, clientKey);
        Metadata honestMd = new Metadata(HONEST, HONEST + "/oauth2/token", HONEST + "/par");
        String good = clientAssertion(clientKey, honestMd, true, "jti-ok");
        KbSupport.check("legitimate L7 assertion: " + te.authenticate(good) + "; replayed within its 60 s: " + te.authenticate(good),
                te.seenJti.size() == 1);

        KbSupport.section("Device authorization grant: user-code entropy is shared by EVERY live code");
        double space = Math.pow(20, 8);
        KbSupport.info("8 base-20 characters (RFC 8628 6.1, e.g. WDJB-MJHT): 20^8 = %.3g = %.1f bits", space, Math.log(space) / Math.log(2));
        for (long live : new long[] {1, 10_000, 200_000}) {
            StringBuilder row = new StringBuilder();
            for (long attempts : new long[] {100, 10_000, 1_000_000}) {
                row.append(String.format(Locale.ROOT, "%,10d guesses: %7.3f%%   ", attempts, 100 * hitAny(attempts, live, space)));
            }
            KbSupport.info("%,8d live codes | %s", live, row.toString().trim());
        }
        KbSupport.check("with 200k live codes, 1M unthrottled guesses hijack a pending login with ~99.96% probability",
                hitAny(1_000_000, 200_000, space) > 0.999);

        DeviceAs dev = new DeviceAs(true);
        DeviceGrant tv = dev.start("tv-app", "home-isp", NOW);
        KbSupport.info("device authorization response: {\"device_code\":\"%s\",\"user_code\":\"%s\",\"interval\":5,\"expires_in\":900}",
                tv.deviceCode(), tv.userCode());
        String p1 = dev.poll(tv.deviceCode(), NOW + 5);
        String p2 = dev.poll(tv.deviceCode(), NOW + 7);
        KbSupport.check("polling: " + p1 + ", then 2 s later: " + p2, p1.equals("authorization_pending") && p2.startsWith("slow_down"));
        String a = dev.approve(tv.userCode(), "alice", "home-isp", NOW + 30);
        KbSupport.check("same-network approval: " + a + "; next poll: " + dev.poll(tv.deviceCode(), NOW + 60),
                a.equals("approved"));

        KbSupport.section("Device-code phishing (the Storm-2372 pattern): attacker starts the flow, victim finishes it");
        for (boolean l7 : new boolean[] {false, true}) {
            DeviceAs as = new DeviceAs(l7);
            DeviceGrant g = as.start("office-desktop", "attacker-vps", NOW);  // lure: "enter this code to join the meeting"
            String r = as.approve(g.userCode(), "victim", "victim-corp-net", NOW + 120);
            String tok = as.poll(g.deviceCode(), NOW + 125);
            KbSupport.info("%s: verification page -> %s; attacker's poll -> %s", l7 ? "L7" : "L5", r, tok);
            KbSupport.check(l7 ? "L7 never releases tokens to the attacker's device" : "L5 releases the victim's tokens to the attacker",
                    l7 != tok.startsWith("access_token"));
        }

        KbSupport.section("CIBA: unsolicited backchannel requests against a known login_hint");
        for (boolean l7 : new boolean[] {false, true}) {
            CibaOp op = new CibaOp(l7);
            String r = op.backchannel("alice@example.com", "W4SCT", null, true); // attacker does not know alice's user_code
            KbSupport.info("%s: %s", l7 ? "L7" : "L5", r);
            KbSupport.check(l7 ? "L7 rejects before anything reaches alice's phone" : "L5 pushes the prompt and a fatigued tap approves it",
                    l7 != r.startsWith("approved"));
        }
        byte[] authReqId = new byte[20];
        rng.nextBytes(authReqId);
        KbSupport.check("auth_req_id: 160 random bits as unpadded base64url (CIBA: >= 128, 160 recommended) = "
                + KbSupport.b64u(authReqId).length() + " chars", KbSupport.b64u(authReqId).length() == 27);
        KbSupport.verdict();
    }
}
```

<!-- output:MachineFlowsLab.java -->
```text

== private_key_jwt audience injection (CVE-2025-27370/27371, draft-ietf-oauth-rfc7523bis-11)
  L5 client signs aud=https://idp.example.com/oauth2/token   -> honest AS: access_token issued to payments-batch
  [PASS] L5: aud taken from attacker-supplied metadata; the honest AS accepts the replayed assertion
  L7 client signs aud=https://evil-idp.example               -> honest AS: invalid_client (aud https://evil-idp.example)
  [PASS] L7: aud is the issuer the client is talking to, so the honest AS rejects the replay
  [PASS] legitimate L7 assertion: access_token issued to payments-batch; replayed within its 60 s: invalid_client (jti replay)

== Device authorization grant: user-code entropy is shared by EVERY live code
  8 base-20 characters (RFC 8628 6.1, e.g. WDJB-MJHT): 20^8 = 2.56e+10 = 34.6 bits
         1 live codes | 100 guesses:   0.000%       10,000 guesses:   0.000%    1,000,000 guesses:   0.004%
    10,000 live codes | 100 guesses:   0.004%       10,000 guesses:   0.390%    1,000,000 guesses:  32.337%
   200,000 live codes | 100 guesses:   0.078%       10,000 guesses:   7.515%    1,000,000 guesses:  99.960%
  [PASS] with 200k live codes, 1M unthrottled guesses hijack a pending login with ~99.96% probability
  device authorization response: {"device_code":"dc-a11db3bac8137023","user_code":"LRZW-GWFP","interval":5,"expires_in":900}
  [PASS] polling: authorization_pending, then 2 s later: slow_down (interval now 10 s)
  [PASS] same-network approval: approved; next poll: access_token for alice

== Device-code phishing (the Storm-2372 pattern): attacker starts the flow, victim finishes it
  L5: verification page -> approved; attacker's poll -> access_token for victim
  [PASS] L5 releases the victim's tokens to the attacker
  L7: verification page -> blocked: device flow not enabled for client office-desktop; attacker's poll -> authorization_pending
  [PASS] L7 never releases tokens to the attacker's device

== CIBA: unsolicited backchannel requests against a known login_hint
  L5: approved (binding_message 'W4SCT')
  [PASS] L5 pushes the prompt and a fatigued tap approves it
  L7: invalid_user_code (initiator does not know the user's code)
  [PASS] L7 rejects before anything reaches alice's phone
  [PASS] auth_req_id: 160 random bits as unpadded base64url (CIBA: >= 128, 160 recommended) = 27 chars

verdict: OK (11 checks)
```

---

## 6. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

### 6.1 L5 workload authentication

```java
// L5 - DO NOT USE: client credentials with a shared secret and an endpoint-derived audience.
String token = http.post(metadata.tokenEndpoint(),                          // metadata from whichever AS answered
    form("grant_type", "client_credentials", "client_id", "payments-batch",
         "client_secret", System.getenv("CLIENT_SECRET")));                // secret in env, CI logs, heap dumps
// or, "upgraded" to private_key_jwt but with aud = metadata.tokenEndpoint() - the 2025 audience-injection shape
```

### 6.2 L7 on Spring Security 7.1.2

On the client side, Spring Security's OAuth2 client signs `private_key_jwt` assertions with `NimbusJwtClientAuthenticationParametersConverter`. ⚠ In 7.1.2 its default claims are `aud = [providerDetails.tokenUri]`, a random `jti` and a 60-second `exp` [D: lines 139–148]. That is the **pre-rfc7523bis endpoint audience**. It is harmless only while the token URI is static configuration that no attacker can influence. Override it with the issuer:

```java
@Bean
OAuth2AccessTokenResponseClient<OAuth2ClientCredentialsGrantRequest> clientCredentialsClient(JWK clientKey) {
    var converter = new NimbusJwtClientAuthenticationParametersConverter<OAuth2ClientCredentialsGrantRequest>(
            registration -> clientKey);                                              // ES256 key from KMS-backed keystore
    converter.setJwtClientAssertionCustomizer(ctx -> ctx.getClaims()
            .audience(List.of(ctx.getAuthorizationGrantRequest().getClientRegistration()
                    .getProviderDetails().getIssuerUri()))                            // rfc7523bis: aud = issuer, sole value
            .expiresAt(Instant.now().plusSeconds(60)));
    var client = new RestClientClientCredentialsTokenResponseClient();
    client.addParametersConverter(converter);
    return client;
}
```

On Spring Authorization Server, register the client with `ClientAuthenticationMethod.PRIVATE_KEY_JWT`, `ClientSettings.jwkSetUrl(...)` and `tokenEndpointAuthenticationSigningAlgorithm(SignatureAlgorithm.ES256)` (file 01 §6.2). Then verify on every upgrade that the AS enforces `aud` = issuer as the **sole** value; L19's honest-AS check is the test to port [E].

### 6.3 L5 vs L7 across the three flows

| Flow | L5 | L7 |
|---|---|---|
| Client credentials | shared secret, `aud` = token endpoint from metadata, long-lived token | `private_key_jwt` (`aud` = issuer, `typ`, 60 s `exp`, `jti` cache) or mTLS; 5–15 min tokens cached per audience; workload identity federation where possible (Folder 06) |
| Device grant | open to every client, 30-min codes, no context on the approval page, per-code rate limit | device-class clients only; 5–15 min codes; initiator client, network and geo shown; step-up or block on mismatch; global and per-source verification rate limits |
| CIBA | any client, any `login_hint`, prompt and pray | `user_code` required; per-hint budgets; signed requests; `binding_message` shown on both devices; FAPI-CIBA poll/ping |

---

## 7. Real-world attack vectors & mitigations

### A1 · Audience injection against JWT client authentication (CVE-2025-27370 / 27371)

**Attack.** A malicious AS, in a federation or multi-AS client, advertises the honest AS's token endpoint in its metadata. The client signs a `private_key_jwt` assertion with `aud` = that endpoint and sends it to the malicious AS, which replays it at the honest AS to obtain tokens as the client (L19).
**Wire signature.** The honest AS receives assertions whose `aud` is an endpoint URL rather than its issuer, or a multi-valued `aud`; the same `jti` patterns from unexpected networks.
**Root cause.** Endpoint values in metadata cannot be validated, yet were used as an audience.
**Mitigation.** Clients set `aud` = the issuer identifier of the AS they are talking to, as the sole value. ASes reject anything else (rfc7523bis-11 §4). Use explicit `typ: client-authentication+jwt`. Short `exp`, and a `jti` replay cache.
**Detection.** Log the `aud` form of every client assertion; alert on endpoint-URL or array audiences after migration.

### A2 · Shared client secrets in workloads

**Attack.** `client_secret` sits in environment variables, CI logs, Helm values and heap dumps. Anyone who reads it impersonates the workload, and the AS stores a verifiable copy too.
**Wire signature.** `client_secret_basic`/`_post` from many source IPs; the same client ID used from unexpected clusters.
**Root cause.** Symmetric credentials for machine identity.
**Mitigation.** `private_key_jwt` with a non-exportable key, or mTLS. Better still, workload identity federation (Kubernetes service account tokens exchanged under RFC 8693 or cloud STS, Folders 05–06) so no long-lived secret exists.
**Detection.** Secret scanning in repositories and CI; client-ID-to-network baselines.

### A3 · Device-code phishing

**Attack.** The attacker initiates the device flow for a broadly trusted client, lures the victim to the legitimate verification URI with the user code, and collects tokens, including MFA-backed refresh tokens, as the victim approves (Storm-2372; L19).
**Wire signature.** Device-code grants completed by users whose verification network differs from the initiating device's network; device-code flows for clients that are not devices.
**Root cause.** The binding between approver and device is a human-typed code, transferable by social engineering.
**Mitigation.**
- Restrict the device grant to device-class clients.
- Conditional Access blocking device code flow elsewhere.
- Initiator context and warnings on the verification page.
- Short code lifetimes.
- Refresh-token revocation on suspicion.

**Detection.** Alerts on device-code sign-ins for non-device clients, or from hosting-provider ASNs on the initiating side.

### A4 · User-code brute force across live codes

**Attack.** The attacker enters guessed codes at the verification page, aiming to hit any live pending authorization: to approve their own account onto someone's device, to deny or disrupt, or in a variant to pair a victim's approval with the attacker's device. The probability scales with the number of live codes (L19's table).
**Wire signature.** High rates of invalid user-code submissions from few sources.
**Root cause.** Per-code thinking about a shared code space; low entropy for usability.
**Mitigation.** Global and per-source rate limits on code verification, CAPTCHA after failures, 8 or more base-20 characters, short `expires_in`, and requiring the approver to be authenticated *before* entering a code.
**Detection.** Invalid-code rate dashboards by source.

### A5 · CIBA unsolicited requests and prompt fatigue

**Attack.** Knowing only a user's email or phone (`login_hint`), the attacker's client, or a compromised legitimate client, triggers backchannel authentication requests repeatedly until the user approves one (L19 L5).
**Wire signature.** Bursts of `/bc-authorize` for one hint; denied or ignored prompts followed by an approval.
**Root cause.** Initiating a prompt requires no knowledge the attacker lacks.
**Mitigation.** Require `user_code`. Per-hint budgets. `binding_message` with a short random code displayed on the consumption device. Signed requests and client allow-lists. Number matching on the authentication device.
**Detection.** Request-rate alerts per hint; ratio of denied to approved prompts.

### A6 · Polling abuse and device-code leakage

**Attack.** A leaked `device_code`, from a TV app debug log or crash report, lets an attacker poll for, and receive, the victim's tokens after approval. Aggressive polling also DoSes the token endpoint.
**Wire signature.** Polls for one device code from two sources; polling faster than `interval`.
**Root cause.** The device code is a bearer secret during the pending window; no per-device binding.
**Mitigation.** High-entropy device codes, stored hashed. Bind polls to the initiating client's authentication, or to a DPoP key generated by the device and presented at initiation [E]. Enforce `slow_down` (L19). Single delivery of tokens.
**Detection.** Multiple pollers per device code; ignored `slow_down`.

---

## 8. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · Explain the 2025 private_key_jwt vulnerability and what you change in client and server.</b></summary>

**Initial Prompt.** Your platform has 2,000 confidential clients using `private_key_jwt` against several authorization servers.

**L5 Textbook Answer.** "Assertions are signed with a private key that never leaves the client, so they can't be forged."

**How an Attacker Bypasses L5.** Nothing is forged. The *client* signs exactly what it is told:
1. A malicious or compromised AS, in a federation or multi-AS deployment, publishes metadata naming the honest AS's token endpoint.
2. The client uses that endpoint as `aud` and sends the assertion to the malicious AS.
3. The malicious AS replays it at the honest AS, which accepts audiences equal to its token endpoint (L19 L5 row: "access_token issued to payments-batch").

**L7 Principal Defense.** rfc7523bis-11 (CVE-2025-27370/27371):
- **Client:** `aud` = the issuer identifier of the AS it intends to authenticate to, taken from the *validated* issuer, never from endpoint metadata; a single value; `typ: client-authentication+jwt`; short `exp`; a unique `jti`.
- **Server:** require `aud` to equal its own issuer as the sole value (simple string comparison); keep a `jti` replay cache until `exp`; constrain `exp − iat`.
- **Migration:**
  1. the servers accept both forms while logging which one they see;
  2. clients switch;
  3. the servers then reject endpoint audiences.

  Track per-client progress.

</details>

<details><summary><b>Q2 · Why not just use client_secret_basic for internal services behind the mesh?</b></summary>

**Initial Prompt.** "It's all inside our VPC."

**L5 Textbook Answer.** "Network isolation makes secrets safe enough; rotate them yearly."

**How an Attacker Bypasses L5.**
- **Secrets travel.** They leak into CI logs, Terraform state, heap dumps and support tickets.
- **Bearer power.** Anyone who reads the secret is the workload, from anywhere the token endpoint is reachable.
- **The AS can mint.** The AS stores a verifiable copy, so an AS database leak yields every client's identity.

"Inside the VPC" fails at the first SSRF.

**L7 Principal Defense.**
- **Asymmetric client authentication** (RFC 9700 §2.5):
  - mTLS with SPIFFE-issued SVIDs from the mesh (Folder 05);
  - or `private_key_jwt` with keys in KMS.
- **Better still, workload identity federation:** the platform's own identity (Kubernetes projected service account token, cloud instance identity) is exchanged for an access token (RFC 8693, Folder 06). No static secret exists to leak.
- **Rotation then becomes certificate or key renewal,** handled automatically by the platform.

</details>

<details><summary><b>Q3 · Your TV app uses the device grant. A security researcher shows they can approve their own account onto random TVs. How?</b></summary>

**Initial Prompt.** Codes are 8 base-20 characters, as the RFC recommends.

**L5 Textbook Answer.** "20^8 is 25.6 billion; guessing a code is infeasible."

**How an Attacker Bypasses L5.** The attacker doesn't need a particular code, only *any* live one. During a launch with 200k pending activations, a million guesses find one with probability about 99.96% (L19). Per-code rate limits don't apply, because each guess hits a different code.

**L7 Principal Defense.**
- **Rate-limit code verification** globally and per source, add CAPTCHA after failures, and require the approver to be logged in *before* entering a code, so every guess is attributable.
- **Short `expires_in`,** so the live-code count stays small.
- **Display device context on approval:** "Living-room TV, model …, in Berlin".
- **Confirm on the TV:** "linked to alice@…".
- **Monitor** invalid-code rates.
- **Re-compute** the success probability with your real peak concurrency, not the single-code number.

</details>

<details><summary><b>Q4 · Should you allow the device authorization grant for the corporate desktop client?</b></summary>

**Initial Prompt.** IT says it helps users on shared machines.

**L5 Textbook Answer.** "Sure. It's a standard OAuth grant and MFA still applies."

**How an Attacker Bypasses L5.** That is exactly Storm-2372's playbook:
1. The attacker starts the flow for the trusted desktop client and sends the code in a meeting lure.
2. The victim completes MFA on the real sign-in page.
3. The attacker receives tokens, and via a broker client ID, refresh tokens that can register an attacker-controlled device (Microsoft, Feb 2025).

MFA was satisfied, by the victim.

**L7 Principal Defense.**
- **No.** Allow the device grant only for client IDs that are genuinely input-constrained.
- **Block it with Conditional Access everywhere else,** monitor device-code sign-ins, and revoke refresh tokens on suspicion.
- **For shared machines,** use proper flows: passkeys via cross-device hybrid (Folder 01 file 02) or kiosk-mode sessions.
- **L19's L7 AS blocks `office-desktop`** for exactly this reason.

</details>

<details><summary><b>Q5 · Design CIBA for a bank's call centre: the agent requests, the customer approves on their phone.</b></summary>

**Initial Prompt.** The agent tool sends the customer's phone number as `login_hint`.

**L5 Textbook Answer.** "CIBA push to the banking app; the customer taps approve."

**How an Attacker Bypasses L5.**
- **Prompt fatigue.** A social engineer calls the bank pretending to be the customer, or simply triggers prompts in a loop through a compromised agent tool. A tired customer taps approve.
- **No interlock.** Nothing ties the approval to *this* call.

**L7 Principal Defense.**
- **The agent's screen shows a random `binding_message`,** such as `W4SCT`. The customer's app shows the same code and asks "only approve if the agent read you this code".
- **Require a `user_code`** known only to the customer for agent-initiated requests, or have the customer's app generate the interlock.
- **Rate-limit per customer.**
- **Use signed requests** from the agent tool's client (FAPI-CIBA), with poll or ping only.
- **Scope the resulting token narrowly and briefly,** for example 10 minutes of `account:read`, with step-up for payments.
- **Record the binding message in the audit trail.**

</details>

<details><summary><b>Q6 · How do you cache client-credentials tokens across 300 pods?</b></summary>

**Initial Prompt.** The AS is rate-limiting the batch platform.

**L5 Textbook Answer.** "Get one token with every scope, put it in Redis, and share it across all pods and services."

**How an Attacker Bypasses L5.**
- **A skeleton key.** A shared, broad token valid at every API is exactly what an attacker wants, and Redis now holds it in plaintext for anyone with cache access.
- **No attribution.** You can no longer attribute calls to a workload.

**L7 Principal Defense.**
- **Each workload identity gets its own tokens:** per audience and per scope set.
- **Cache in-process** until `exp − 60 s`, with single-flight refresh.
- **Size the AS** for (workloads × audiences ÷ token lifetime) requests per second, which is usually tiny.
- **If you need a shared cache,** use one per workload identity, encrypted, with short lifetimes.
- **Prefer sender-constrained tokens (mTLS)** so a cached copy is useless elsewhere.

</details>

<details><summary><b>Q7 · A leaked device_code from a TV crash log. What's the blast radius?</b></summary>

**Initial Prompt.** Crash reports go to a third-party SaaS.

**L5 Textbook Answer.** "Device codes are useless without the user approving."

**How an Attacker Bypasses L5.** The user *will* approve, because they are trying to log in on their TV. The attacker polls with the leaked `device_code` alongside the TV, and whoever polls first after approval gets the tokens. Or both do, if the AS doesn't deliver once.

**L7 Principal Defense.**
- **Treat the device code as a secret:** never log it, store it hashed, and keep it high-entropy.
- **Deliver tokens exactly once.**
- **Bind polling to the initiator:** the TV authenticates as its client or with a key generated at initiation (DPoP-style).
- **Detect multiple pollers** per device code and fail the grant.
- **Scrub crash reports** for token- and code-shaped strings.

</details>

<details><summary><b>Q8 · When would you choose CIBA over the device grant, or over a redirect flow?</b></summary>

**Initial Prompt.** Product has a smart-speaker payments feature.

**L5 Textbook Answer.** "Device grant, because it's for devices."

**How an Attacker Bypasses L5.** The device grant asks the user to visit a URL and type a code. For a voice-only device that becomes "read the code aloud", which anyone in the room can hear and race. It also has no transaction binding for a payment.

**L7 Principal Defense.** Choose by where the user is and what is approved:
- **Redirect flows** when the user has a browser on the same device. Strongest, because they are origin-bound with WebAuthn.
- **The device grant** when the device can display a code and the user has a phone; for *login*.
- **CIBA** when the RP already knows who the user claims to be and needs approval of a *specific action* on the user's trusted device.

For speaker payments, use CIBA with a binding message read aloud by the speaker and shown on the phone, plus amount and payee in the authorization details (RAR, Folder 04), a FAPI-CIBA profile and a short-lived, narrowly scoped token.

</details>

<details><summary><b>Q9 · How do you test client authentication on your AS after the rfc7523bis change?</b></summary>

**Initial Prompt.** You must prove compliance for 2,000 clients.

**L5 Textbook Answer.** "Integration tests with our reference client pass."

**How an Attacker Bypasses L5.** The reference client sends the new audience. The *server* may still accept the old forms (token-endpoint audience, arrays, extra values), and those acceptances are the vulnerability.

**L7 Principal Defense.** Negative tests against the deployed AS, assertions with:
- `aud` = token endpoint;
- `aud` = `[issuer, evil]`;
- `aud` = issuer with a trailing slash;
- missing `typ` (decide your policy);
- a reused `jti`;
- `exp` far in the future;
- a valid signature from a key not registered for the client.

Each must fail except the canonical form (L19's honest-AS checks). Run them in CI and nightly, and keep a dashboard of assertion audience forms seen in production during the migration.

</details>

<details><summary><b>Q10 · Your platform team proposes one global OAuth client for all internal services "to simplify". Evaluate.</b></summary>

**Initial Prompt.** One `client_id`, one key, used by 80 services.

**L5 Textbook Answer.** "Fewer moving parts. We'll restrict it with network policy."

**How an Attacker Bypasses L5.** One compromised service yields a credential that *is* all 80 services. There is no least privilege, because scopes must be the union. Audit logs cannot say which service called, and key rotation is a fleet-wide event.

**L7 Principal Defense.**
- **One client identity per workload,** ideally derived automatically from platform identity (SPIFFE ID, Kubernetes service account, cloud role), so registration costs nothing.
- **Scopes and audiences per workload,** with token exchange for downstream calls (Folder 05).
- **mTLS or `private_key_jwt`** with platform-managed keys.
- **The simplification is automation, not sharing.**

</details>

---

## 9. Invariants checklist

- [ ] Workloads authenticate with mTLS or `private_key_jwt`, or use workload identity federation; no shared secrets.
- [ ] Client assertions: `aud` = the AS issuer as the sole value, `typ: client-authentication+jwt`, `exp` ≤ 60–300 s, unique `jti`; the AS enforces all of it.
- [ ] Client-credentials tokens are per audience and scope set, short-lived, cached in-process until `exp − skew`.
- [ ] The device grant is enabled only for input-constrained device clients; Conditional Access blocks it elsewhere.
- [ ] Device codes are high-entropy, hashed, never logged, delivered once; user codes have 8+ base-20 characters; `expires_in` is short.
- [ ] Code verification is rate-limited globally and per source; the approver is authenticated first; the initiator's context is shown.
- [ ] `slow_down` is enforced (+5 s each time); multiple pollers per device code fail the grant.
- [ ] CIBA: `user_code` or an equivalent initiation secret; per-hint budgets; `binding_message` shown on both devices; signed requests; poll/ping for FAPI.
- [ ] `auth_req_id` ≥ 128 bits (160 recommended), base64url charset.
- [ ] Negative tests for every client-authentication and decoupled-flow rule run against the deployed AS.

---

## 10. References

- RFC 6749 §4.4 *Client Credentials Grant* — <https://www.rfc-editor.org/rfc/rfc6749#section-4.4>
- RFC 7523 *JWT Profile for OAuth 2.0 Client Authentication and Authorization Grants* — <https://www.rfc-editor.org/rfc/rfc7523>
- draft-ietf-oauth-rfc7523bis (draft-11 of 26 March 2026; status checked on the Datatracker 2026-11-03) — <https://datatracker.ietf.org/doc/draft-ietf-oauth-rfc7523bis/>
- OpenID Foundation, *Notice of a Security Vulnerability* (private_key_jwt audience, CVE-2025-27370/27371) — <https://openid.net/notice-of-a-security-vulnerability/>
- RFC 8628 *OAuth 2.0 Device Authorization Grant* — <https://www.rfc-editor.org/rfc/rfc8628>
- Microsoft Threat Intelligence, *Storm-2372 conducts device code phishing campaign* (2025-02-13) — <https://www.microsoft.com/en-us/security/blog/2025/02/13/storm-2372-conducts-device-code-phishing-campaign/>
- OpenID Client-Initiated Backchannel Authentication Flow – Core 1.0 — <https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html>
- FAPI: Client Initiated Backchannel Authentication Profile — <https://openid.net/specs/openid-financial-api-ciba-ID1.html>
- Spring Security, `NimbusJwtClientAuthenticationParametersConverter` (client authentication with JWT) — <https://docs.spring.io/spring-security/reference/servlet/oauth2/client/client-authentication.html>
