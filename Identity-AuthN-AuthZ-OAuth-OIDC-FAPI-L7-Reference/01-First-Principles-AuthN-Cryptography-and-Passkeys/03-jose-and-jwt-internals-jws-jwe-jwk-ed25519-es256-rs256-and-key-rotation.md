# JOSE and JWT Internals: JWS, JWE, JWK, Ed25519 vs ES256 vs RS256, and Key Rotation

> Folder 01 · File 03 of 03 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [02 · WebAuthn / FIDO2 passkeys](02-webauthn-fido2-passkeys-public-key-challenges-and-origin-binding.md) · First: [01 · AuthN physics](01-authn-physics-passwords-argon2id-mfa-totp-and-session-vs-token-state.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L9 `Jose.java` | JWS compact serialization for HS*, RS*, PS*, ES* and Ed25519/Ed448 (under both `EdDSA` and the RFC 9864 ids); JWK import for oct/RSA/EC/OKP with an EC on-curve check; RFC 7638 thumbprints; strict parsing. Uses L6 `MiniJson` and L7's EC/Ed helpers | RFC 7515 A.1–A.5, RFC 8037 A.1–A.5, RFC 7638 §3.1, extracted from `fixtures/` |
| L10 `JwtAttackLab.java` | Verification as a policy. An L5 verifier written the way tutorials and old libraries did it, against an L7 verifier with alg pinned per key, `typ=at+jwt`, exact `iss`/`aud`, required `exp`/`iat` with bounded skew and lifetime, strict base64url and JSON, and a `jti` replay cache. 12 attacks, psychic signatures, an offline HS256 dictionary attack | L5: 12/12 accepted; L7: 12/12 rejected |
| L11 `JweLab.java` | JWE with RSA-OAEP + A256GCM, A128KW + A128CBC-HS256 (MAC before decrypt), ECDH-ES with the Concat KDF, a nested sign-then-encrypt JWT, and an invalid-curve check | RFC 7516 A.1 and A.3 decrypt to the RFC plaintexts; RFC 7518 App. C derived key |
| L12 `JwksRotation.java` | Deterministic simulation: big-bang rotation, publish/switch/retire, kid-miss refresh storm, emergency compromise vs cache TTL | Closed-form expectations asserted |
| L13 `SigBench.java` | Single-thread keygen, sign/s, verify/s, signature bytes and JWT length for HS256, RS256-2048/3072, PS256, ES256, ES384, Ed25519, Ed448, ML-DSA-44/65 on JDK 25 | Sizes (FIPS 204 for ML-DSA), RSA sign/verify asymmetry |
| L14 `JwtSecurityConfig.java` | Spring Security 7.1.2 resource server and `NimbusJwtEncoder` with a two-key JWK set; what the defaults accept and reject; the hardened decoder; interop in both directions with L9 | Real `NimbusJwtDecoder`/`NimbusJwtEncoder` (Nimbus 10.9.1) |

**Verification.** Compiled with the rest of Folder 01 by `javac --release 21 -Xlint:all -Werror` on Temurin JDK 25.0.4.1. The classpath adds Nimbus JOSE+JWT 10.9.1 and spring-security-oauth2-jose / -resource-server 7.1.2, SHA-1-checked against Maven Central on 2026-11-05. Every `output` block is re-run by the gate and must be byte-identical. The `measured-output` block (L13) is one run on a Windows 11 laptop with 12 logical CPUs. The gate re-runs it in `--quick` mode and checks only the size and asymmetry properties. Spring internals marked [D] were read from the 7.1.2 `-sources.jar`, and CVE descriptions from NVD (2026-11-05).

Labels: **[D]** documented in a spec, a shipped source file or NVD · **[M]** measured by a listing here · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

Files 01 and 02 established who the user is. Everything after that, the access token sent to an API, the ID token handed to a client, the assertion exchanged between services, is a **JOSE object**: a signed or encrypted JSON structure whose security depends entirely on byte-level rules that most teams delegate to a library and never read. This file reads them. It rebuilds JWS, JWE and JWK from the RFC examples, measures the algorithms on the JVM you will actually run, and shows what verification has to look like in order to be a security control.

What it establishes:

- **[M]** L9 reproduces RFC 7515's HS256 and RS256 example signatures **exactly** and RFC 8037's Ed25519 signature **exactly** (all three are deterministic). It verifies the RFC's ES256 and ES512 examples, which are randomized and therefore checked by verification only. It matches both RFC thumbprints. All keys and serializations are parsed out of the RFC text.
- **[M]** A tutorial-grade verifier accepts **12 of 12** attacks:
  - `alg:none` and `nOnE`;
  - RS256→HS256 key confusion;
  - an embedded `jwk`; `jku`;
  - `kid` path traversal;
  - a token with no `exp`;
  - a substring audience;
  - an ID token used as an access token;
  - alg/key mismatch;
  - replay through non-canonical base64url;
  - replay through ECDSA malleability.

  The L7 verifier rejects all 12. One captured HS256 token signed with jwt.io's default secret `your-256-bit-secret` gives up its key in 1,338 dictionary guesses.
- **[M] On JDK 25, the algorithm folklore is backwards for verification.** One core verifies about 21,700 RS256 tokens/s, about 14,600 ML-DSA-44, about 1,500 ES256 and only about 880 Ed25519 (L13). Across three full runs on this laptop, individual cells moved by up to ±40% (turbo and thermal effects), but these orderings never changed. ES256 and Ed25519 win on **size** (64-byte signatures, 569-character tokens vs 825 for RS256) and on signing and key-generation cost, not on JVM verify throughput.
- **[M][D] Spring Security 7.1.2's `NimbusJwtDecoder` builders default to RS256 only** and to `JwtValidators.createDefault()`. That validator requires `typ` to be `JWT` or absent, so a correct RFC 9068 `at+jwt` token is *rejected*, while an ID token with the wrong audience is *accepted*: there is no `iss` or `aud` check. `createAtJwtValidator().issuer(..).audience(..)` fixes both (L14). ⚠ Used alone, it drops the mTLS `x5t#S256` binding check that the default validators include. Where certificate-bound tokens exist, use Folder 07 file 03's composition (L48 row C). Spring's `SignatureAlgorithm` enum has no EdDSA.
- **[M]** Big-bang key rotation rejects 7.6% of traffic with TTL-only JWKS caches, and still 3.4% with kid-miss refresh. That remainder comes from *old*-key tokens still in flight. Publish → wait → switch → wait → retire gives **zero** rejections. A random-`kid` flood turns 1:1 into 300,000 JWKS fetches against a naive cache, and into 2 with single-flight rate limiting (L12).
- **[D]** RFC 9864 (October 2025) deprecates the polymorphic `EdDSA` JWS identifier in favour of `Ed25519` and `Ed448`. RFC 9068 defines the `at+jwt` access-token profile. RFC 8725 is the JWT security BCP whose rules L10 implements.

---

## 1. First principles: what a JWS actually signs

### 1.1 Compact serialization, byte by byte

```text
  BASE64URL(UTF8(protected header)) . BASE64URL(payload) . BASE64URL(signature)
  \_______________________________________________________/
                       JWS Signing Input  (ASCII bytes; this, and only this, is signed)

  eyJhbGciOiJFUzI1NiIsInR5cCI6ImF0K2p3dCIsImtpZCI6Ik56Yi4uLiJ9      <- {"alg":"ES256","typ":"at+jwt","kid":"NzbL..."}
  .
  eyJpc3MiOiJodHRwczovL2lkcC5leGFtcGxlLmNvbSIsInN1YiI6IjI0ODI4...   <- the JSON claims (RFC 7519 / RFC 9068)
  .
  <86 chars> (ES256: 64 raw bytes r||s -> 86 chars; RS256-2048: 256 bytes -> 342 chars; ML-DSA-44: 2420 -> 3227)

  base64url: RFC 4648 section 5 alphabet (- and _), NO padding; JSON: no canonical form is required --
  the verifier checks the bytes it received, so it must never re-serialize before verifying.
```

RFC 7515 A.1 makes the last point concrete. Its protected header contains a **CRLF and a leading space** (`{"typ":"JWT",\r\n "alg":"HS256"}`), and the HMAC covers those bytes. L9 checks this explicitly. Any implementation that parses the header and re-encodes it "canonically" before verifying breaks interoperability. Any implementation that verifies one representation and then *uses* another (a logger, a gateway, a policy engine with a different JSON parser) has a parser-differential vulnerability [D: RFC 7515 §5.2; E].

### 1.2 The header parameters that matter for security

| Header | Meaning | L7 rule |
|---|---|---|
| `alg` | signature or MAC algorithm | never trusted to *choose* the algorithm; must equal the alg **pinned to the key** |
| `kid` | key identifier | lookup key into a **local** JWKS only; never a file path, URL or SQL fragment |
| `typ` | media type of the whole JWS | `at+jwt` for access tokens (RFC 9068); distinct `typ` per token kind defeats cross-JWT confusion (RFC 8725 §3.11) |
| `cty` | content type of the payload | `JWT` for nested tokens (L11) |
| `crit` | extensions that MUST be understood | reject unless you implement every listed one |
| `jku`, `x5u` | URL to fetch keys or certificates from | ignore for key selection; following them is SSRF plus attacker-chosen keys |
| `jwk`, `x5c` | key or certificate embedded in the token | ignore for key selection (CVE-2018-0114); `x5c` only with full PKIX validation to a pinned root |
| `x5t#S256` | certificate thumbprint | binding for mTLS-bound tokens (RFC 8705, Folder 04) |

### 1.3 The claims, and the RFC 9068 access-token profile

```json
{
  "iss": "https://idp.example.com",
  "sub": "248289761001",
  "aud": "https://payments.example.com",
  "client_id": "s6BhdRkqt3",
  "scope": "payments:read payments:write",
  "iat": 1767225600,
  "exp": 1767225900,
  "auth_time": 1767225500,
  "acr": "urn:example:aal2",
  "jti": "dbe39bf3a3ba4238a513f51d6e1691c4"
}
```

This is L13's benchmark payload. RFC 9068 makes `iss`, `exp`, `aud`, `sub`, `client_id`, `iat` and `jti` REQUIRED for JWT access tokens, together with `typ: at+jwt`. Spring's `createAtJwtValidator()` requires exactly that set and makes you configure `iss` and `aud` [D: `JwtValidators.AtJwtBuilder`]. Note what is **not** in the token: no email, no name, no PII. A JWS is *signed*, not encrypted, and every proxy, log pipeline and browser extension that sees it can read it.

```http
GET /payments/v1/transfers/7731 HTTP/1.1
Host: payments.example.com
Authorization: Bearer eyJhbGciOiJFUzI1NiIsInR5cCI6ImF0K2p3dCIsImtpZCI6Ik56Yi4uLiJ9.eyJpc3MiOi...
Accept: application/json
```

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer error="invalid_token", error_description="The aud claim is not valid"
Cache-Control: no-store
```

### 1.4 Symmetric vs asymmetric: the trust-topology argument

```text
  HS256 across services                         ES256 / RS256 / Ed25519 / ML-DSA across services

  IdP --(shared secret K)--> API-1               IdP (private key in KMS/HSM) --- publishes JWKS (public)
     \--(shared secret K)--> API-2                   |                |               |
      \-(shared secret K)--> API-3                 API-1            API-2           API-3
                                                   (verify only)    (verify only)   (verify only)
  every verifier can also MINT tokens for
  every other verifier; compromise of the        compromise of any API yields no ability to mint;
  weakest API = compromise of all; rotation      rotation = publish a new public key; no secret
  = redeploy the secret everywhere at once       ever leaves the IdP
```

**HS256 is an anti-pattern across trust boundaries** because a MAC key is a *signing* key. Every resource server that can verify can also forge, so the blast radius is the union of all verifiers. The secret is also often a human-chosen string, which L10 cracks in 1,338 guesses: that is jwt.io's default `your-256-bit-secret`, and it appears in real deployments because people paste the example. HS256 is acceptable only when the issuer and the verifier are the *same* service, for example a server's own short-lived CSRF or state tokens, with a 256-bit random key [E].

---

## 2. Algorithms: the math that decides the failure modes

| alg | Primitive | Deterministic? | Signature | Failure mode that bites in practice |
|---|---|---|---|---|
| HS256 | HMAC-SHA-256 | yes | 32 B | shared secret = minting power; weak secrets crack offline (L10) |
| RS256 | RSASSA-PKCS1-v1_5, SHA-256 | **yes** | 256 B (2048-bit) | large tokens; slow signing; **fastest JVM verify** (L13) |
| PS256 | RSASSA-PSS, SHA-256, MGF1, 32-byte salt | no (salted) | 256 B | the same size as RS256; a provably secure padding; slower to adopt in older stacks |
| ES256 | ECDSA P-256, SHA-256 | **no** (random k) | 64 B raw r‖s | nonce reuse or bias leaks the private key; DER vs raw confusion; **malleable** (r, n−s) (L10 #12); CVE-2022-21449 on Java 15–18 |
| Ed25519 | EdDSA (RFC 8032) on edwards25519 | **yes** (nonce = H(prefix ‖ msg)) | 64 B | verification-strictness differences between libraries [E]; JOSE id migration `EdDSA` → `Ed25519` (RFC 9864) |
| ML-DSA-44 / -65 | FIPS 204 lattice signatures | hedged (randomized by default) | 2420 / 3309 B | token size: 3.7–4.9 kB JWTs collide with 8 kB header limits; JOSE registration still in progress [E] |

Three facts interviewers probe:

1. **Why ECDSA in JWS is raw r‖s, not DER.** RFC 7518 §3.4 specifies the fixed-length 64-byte (P-256) concatenation. JCA's `SHA256withECDSA` produces and expects DER, so L9 uses `SHA256withECDSAinP1363Format`. A verifier that accepts *both* encodings has two valid byte strings per signature, and so does one that is lax about DER. That breaks every cache, deduplicator or replay detector keyed on token bytes [E].
2. **Why randomized ECDSA is fragile.** The signature equation `s = k⁻¹(H(m) + r·d) mod n` means two signatures with the same `k` reveal `d` by simple algebra. Biased `k` leaks it through lattice attacks over many signatures. Ed25519 derives the nonce deterministically from the key and the message. RFC 6979 does the same for ECDSA. Keep ECDSA signing inside a KMS/HSM or a vetted library, never in a hand-rolled implementation [E].
3. **Why "the signature verifies" is not "this is the token I issued".** ECDSA is malleable: (r, n−s) verifies too, and L10 #12 replays a token that way past a replay cache keyed on the token string. Non-canonical base64url gives a different string for the same bytes (L10 #11). **Key replay and deduplication on `jti`, never on token bytes**, and decode base64url strictly.

### 2.1 Measured on the JVM you will run

<!-- listing:SigBench.java -->
```java
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.MGF1ParameterSpec;
import java.security.spec.PSSParameterSpec;
import java.util.Arrays;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * L13 - single-thread JWS signature benchmark on this JDK: key generation, sign/s, verify/s, signature size and
 * the resulting compact-JWT length for a realistic RFC 9068 access-token payload. Includes ML-DSA (FIPS 204,
 * JDK 24+) to show what post-quantum signatures do to token size. Timings are machine-specific (measured block);
 * the verdict asserts only robust properties (sizes, RSA's sign/verify asymmetry).
 */
public final class SigBench {

    static final String PAYLOAD = "{\"iss\":\"https://idp.example.com\",\"sub\":\"248289761001\",\"aud\":\"https://payments.example.com\","
            + "\"client_id\":\"s6BhdRkqt3\",\"scope\":\"payments:read payments:write\",\"iat\":1767225600,\"exp\":1767225900,"
            + "\"auth_time\":1767225500,\"acr\":\"urn:example:aal2\",\"jti\":\"dbe39bf3a3ba4238a513f51d6e1691c4\"}";

    record Alg(String jws, String jca, String keyAlg, Object spec, int bits) {
    }

    record Row(String name, double keygenMs, double signPerSec, double verifyPerSec, int sigBytes, int jwtChars) {
    }

    public static void main(String[] args) throws Exception {
        boolean quick = KbSupport.flag(args, "--quick");
        long warmNs = quick ? 20_000_000L : 600_000_000L;
        long measureNs = quick ? 50_000_000L : 1_500_000_000L;
        SecureRandom rng = new SecureRandom();
        Alg[] algs = {
            new Alg("HS256", "HmacSHA256", "HMAC", null, 256),
            new Alg("RS256", "SHA256withRSA", "RSA", null, 2048),
            new Alg("RS256", "SHA256withRSA", "RSA", null, 3072),
            new Alg("PS256", "RSASSA-PSS", "RSA", null, 2048),
            new Alg("ES256", "SHA256withECDSAinP1363Format", "EC", "secp256r1", 256),
            new Alg("ES384", "SHA384withECDSAinP1363Format", "EC", "secp384r1", 384),
            new Alg("Ed25519", "Ed25519", "Ed25519", null, 255),
            new Alg("Ed448", "Ed448", "Ed448", null, 448),
            new Alg("ML-DSA-44", "ML-DSA", "ML-DSA-44", null, 0),
            new Alg("ML-DSA-65", "ML-DSA", "ML-DSA-65", null, 0)};
        String header = KbSupport.b64u("{\"alg\":\"ES256\",\"typ\":\"at+jwt\",\"kid\":\"NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs\"}"
                .getBytes(StandardCharsets.UTF_8));
        byte[] input = (header + "." + KbSupport.b64u(PAYLOAD.getBytes(StandardCharsets.UTF_8))).getBytes(StandardCharsets.US_ASCII);

        KbSupport.section("JWS signature cost on " + System.getProperty("java.vm.name") + " " + System.getProperty("java.version")
                + " (" + System.getProperty("os.arch") + ", " + Runtime.getRuntime().availableProcessors() + " logical CPUs, single thread"
                + (quick ? ", QUICK mode" : "") + ")");
        KbSupport.info("%-16s %10s %12s %12s %8s %9s", "alg", "keygen ms", "sign/s", "verify/s", "sig B", "JWT chars");
        Row rsa2048 = null;
        Row ed = null;
        Row es = null;
        Row mldsa44 = null;
        for (Alg a : algs) {
            Row r;
            try {
                r = bench(a, input, rng, warmNs, measureNs, quick);
            } catch (java.security.GeneralSecurityException e) {
                KbSupport.info("%-16s not available on this JDK (%s)", a.jws(), e.getClass().getSimpleName());
                continue;
            }
            KbSupport.info("%-16s %10.2f %12.0f %12.0f %8d %9d", r.name(), r.keygenMs(), r.signPerSec(), r.verifyPerSec(), r.sigBytes(), r.jwtChars());
            if (r.name().equals("RS256-2048")) {
                rsa2048 = r;
            } else if (r.name().equals("Ed25519")) {
                ed = r;
            } else if (r.name().equals("ES256")) {
                es = r;
            } else if (r.name().equals("ML-DSA-44")) {
                mldsa44 = r;
            }
        }
        KbSupport.check("RSA-2048: verify is >= 5x faster than sign (e = 65537 vs CRT private exponent)",
                rsa2048 != null && rsa2048.verifyPerSec() > 5 * rsa2048.signPerSec());
        KbSupport.check("ES256 and Ed25519 signatures are 64 bytes; RS256-2048 is 256", es != null && ed != null && es.sigBytes() == 64
                && ed.sigBytes() == 64 && rsa2048.sigBytes() == 256);
        KbSupport.check("ML-DSA-44 signature is 2420 bytes (FIPS 204), a " + (mldsa44 == null ? "?" : mldsa44.jwtChars()) + "-char JWT",
                mldsa44 != null && mldsa44.sigBytes() == 2420);
        KbSupport.verdict();
    }

    static Row bench(Alg a, byte[] input, SecureRandom rng, long warmNs, long measureNs, boolean quick) throws java.security.GeneralSecurityException {
        String name = a.jws() + (a.keyAlg().equals("RSA") ? "-" + a.bits() : "");
        if (a.keyAlg().equals("HMAC")) {
            byte[] k = new byte[32];
            rng.nextBytes(k);
            Mac mac = Mac.getInstance(a.jca());
            mac.init(new SecretKeySpec(k, a.jca()));
            byte[] tag = mac.doFinal(input);
            double s = rate(() -> mac.doFinal(input), warmNs, measureNs);
            return new Row(name, 0, s, s, tag.length, jwtLen(input, tag.length));
        }
        int keygens = quick ? 1 : a.keyAlg().equals("RSA") ? 3 : 20;
        double[] kg = new double[keygens];
        KeyPair kp = null;
        for (int i = 0; i < keygens; i++) {
            KeyPairGenerator g = KeyPairGenerator.getInstance(a.keyAlg());
            if (a.keyAlg().equals("RSA")) {
                g.initialize(a.bits(), rng);
            } else if (a.spec() != null) {
                g.initialize(new ECGenParameterSpec((String) a.spec()), rng);
            }
            long t0 = System.nanoTime();
            kp = g.generateKeyPair();
            kg[i] = (System.nanoTime() - t0) / 1e6;
        }
        Arrays.sort(kg);
        Signature signer = Signature.getInstance(a.jca());
        Signature verifier = Signature.getInstance(a.jca());
        if (a.jws().startsWith("PS")) {
            PSSParameterSpec pss = new PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1);
            signer.setParameter(pss);
            verifier.setParameter(pss);
        }
        signer.initSign(kp.getPrivate(), rng);
        verifier.initVerify(kp.getPublic());
        signer.update(input);
        byte[] sig = signer.sign();
        final KeyPair fkp = kp;
        double s = rate(() -> {
            signer.update(input);
            return signer.sign();
        }, warmNs, measureNs);
        double v = rate(() -> {
            verifier.update(input);
            if (!verifier.verify(sig)) {
                throw new IllegalStateException("verify failed for " + fkp.getPublic().getAlgorithm());
            }
            return sig;
        }, warmNs, measureNs);
        return new Row(name, kg[keygens / 2], s, v, sig.length, jwtLen(input, sig.length));
    }

    interface Op {
        byte[] run() throws java.security.GeneralSecurityException;
    }

    /** Warm up, then the MEDIAN ops/s of 5 rounds of measureNs/5 each (laptop turbo/thermal noise is +-25%). */
    static double rate(Op op, long warmNs, long measureNs) throws java.security.GeneralSecurityException {
        long end = System.nanoTime() + warmNs;
        while (System.nanoTime() < end) {
            op.run();
        }
        double[] rounds = new double[5];
        for (int r = 0; r < rounds.length; r++) {
            long n = 0;
            long t0 = System.nanoTime();
            long stop = t0 + measureNs / rounds.length;
            long now;
            do {
                op.run();
                n++;
                now = System.nanoTime();
            } while (now < stop);
            rounds[r] = n / ((now - t0) / 1e9);
        }
        Arrays.sort(rounds);
        return rounds[rounds.length / 2];
    }

    static int jwtLen(byte[] input, int sigBytes) {
        return input.length + 1 + (int) Math.ceil(sigBytes * 4 / 3.0);
    }

}
```

<!-- measured-output:SigBench.java -->
```text

== JWS signature cost on OpenJDK 64-Bit Server VM 25.0.4.1 (amd64, 12 logical CPUs, single thread)
  alg               keygen ms       sign/s     verify/s    sig B JWT chars
  HS256                  0.00      1839237      1839237       32       526
  RS256-2048           117.64          615        21672      256       825
  RS256-3072           518.81          231         9147      384       995
  PS256-2048           223.68          540        18234      256       825
  ES256                  0.31         4844         1543       64       569
  ES384                  1.91          545          308       96       611
  Ed25519                0.99          868          879       64       569
  Ed448                  2.91          294          278      114       635
  ML-DSA-44              1.42         5469        14624     2420      3710
  ML-DSA-65              0.44         3038         7940     3309      4895
  [PASS] RSA-2048: verify is >= 5x faster than sign (e = 65537 vs CRT private exponent)
  [PASS] ES256 and Ed25519 signatures are 64 bytes; RS256-2048 is 256
  [PASS] ML-DSA-44 signature is 2420 bytes (FIPS 204), a 3710-char JWT

verdict: OK (3 checks)
```

How to read it [E, from the M numbers]:

- **RSA's asymmetry.** Verification uses e = 65537 (17 squarings), while signing does a full 2048-bit CRT exponentiation. Hence about 35× faster verification than signing at 2048 bits, and about 40× at 3072 bits. For a token minted once and verified at N services, RS256 has the cheapest *aggregate* CPU on the JVM.
- **The EC numbers are SunEC's pure-Java implementations.** P-256 has an optimized field implementation, which makes ES256 signing about 8× faster than RS256 signing. Verification needs two scalar multiplications and costs about 0.65 ms. Ed25519 in SunEC is slower still on this JDK (about 1.1 ms per verify). The "Ed25519 is the fastest" folklore comes from C implementations (libsodium, BoringSSL) and does not transfer to the JVM.
- **ML-DSA-44 verifies faster than ES256** on JDK 25 (about 14.6k vs 1.5k per second), but its signature is 2,420 bytes, a 3,710-character JWT. Many proxies and servers default to about 8 kB of total request headers. Plan post-quantum JWS around *size*, not CPU. The likely shape is short-lived tokens, reference tokens or token exchange at the edge [E].
- **Capacity:** at 1M verifications/s, ES256 on this JDK is about 650 cores and RS256 about 46. A gateway that verifies once and forwards a short-lived internal token, or a verified-token cache keyed by SHA-256(token) bounded by `exp`, changes the arithmetic more than the choice of curve does (Folder 05).
- **Choosing [E]:**
  - *ES256* is the pragmatic default for interoperability and size. It is FAPI 2.0's baseline together with PS256 (Folder 04), and it is supported by every KMS and by Spring's enum.
  - *RS256/PS256* when verification throughput dominates, or when an HSM or KMS policy is RSA-only.
  - *Ed25519* when every party supports the RFC 9864 identifier. Spring 7.1.2's `SignatureAlgorithm` enum has no EdDSA, and Nimbus needs Google Tink on the classpath for Ed25519 [D: the Nimbus manifest imports `com.google.crypto.tink.subtle` as optional].

---

## 3. JWK, JWKS and thumbprints

A JWK is a JSON representation of a key: `kty` plus type-specific members (RSA `n`/`e`; EC `crv`/`x`/`y`; OKP `crv`/`x`; oct `k`) and optional metadata (`kid`, `alg`, `use`, `key_ops`, `x5c`). A **JWKS** is `{"keys":[…]}` served by the issuer, usually discovered through `jwks_uri` in OIDC or OAuth metadata (Folder 03).

```json
{"keys": [
  {"kty": "EC", "crv": "P-256", "kid": "oKIywvGUpTVTyxMQ3bwIIeQUudfr_CkLMjCE19ECD-U", "alg": "ES256", "use": "sig",
   "x": "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU", "y": "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"},
  {"kty": "EC", "crv": "P-256", "kid": "cn-I_WNMClehiVp51i_0VpOENW1upEerA8sEam5hn-s", "alg": "ES256", "use": "sig",
   "x": "MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", "y": "4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"}
]}
```

The two keys are the current and the next signing key (the points are RFC 7517's P-256 examples; each `kid` is that key's RFC 7638 thumbprint). Rules L9 and L10 implement:

- **Pin `alg` to the key.** `alg` in the JWK, or in your own configuration, decides how the key may be used. The token header must *match* it, never select it. That single rule kills `none`, key confusion and alg/key mismatch (L10 #1–3, #10).
- **Key type must fit the algorithm family** (`Jwk.fits`). An RSA key is never an HMAC secret. That rule alone makes CVE-2015-9235-style confusion impossible.
- **Validate EC points.** The point must be on the curve, with coordinates below p. This matters for signatures and is critical for ECDH-ES (invalid-curve attacks, L11).
- **RFC 7638 thumbprint as `kid`.** It is SHA-256 over the *required* members only, sorted, with no whitespace, so `alg` and `kid` are not hashed. Thumbprint kids are self-certifying and stable across JWKS reformatting. Nimbus's `computeThumbprint()` and L9 agree (L14).

<!-- listing:Jose.java -->
```java
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.Key;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.interfaces.EdECPublicKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPrivateKeySpec;
import java.security.spec.ECPublicKeySpec;
import java.security.spec.EdECPrivateKeySpec;
import java.security.spec.EdECPublicKeySpec;
import java.security.spec.MGF1ParameterSpec;
import java.security.spec.NamedParameterSpec;
import java.security.spec.PSSParameterSpec;
import java.security.spec.RSAPrivateCrtKeySpec;
import java.security.spec.RSAPublicKeySpec;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * L9 - JOSE primitives from first principles on the JDK: JWS compact serialization for every JWA signature
 * algorithm the JDK can do (HS*, RS*, PS*, ES*, Ed25519/Ed448 under both "EdDSA" and the RFC 9864 ids), JWK
 * import for oct/RSA/EC/OKP and the RFC 7638 thumbprint. Oracles: RFC 7515 A.1-A.5, RFC 8037 A.1-A.5 and
 * RFC 7638 section 3.1, all extracted from the RFC texts in fixtures/. Reuses L6 (MiniJson) and L7's EC helpers.
 */
public final class Jose {

    /** JWA alg -> JCA algorithm. ECDSA uses the "inP1363Format" variants: JWS wants raw r||s, not DER. */
    static String jca(String alg) {
        return switch (alg) {
            case "HS256" -> "HmacSHA256";
            case "HS384" -> "HmacSHA384";
            case "HS512" -> "HmacSHA512";
            case "RS256" -> "SHA256withRSA";
            case "RS384" -> "SHA384withRSA";
            case "RS512" -> "SHA512withRSA";
            case "PS256", "PS384", "PS512" -> "RSASSA-PSS";
            case "ES256" -> "SHA256withECDSAinP1363Format";
            case "ES384" -> "SHA384withECDSAinP1363Format";
            case "ES512" -> "SHA512withECDSAinP1363Format";
            case "Ed25519", "Ed448", "EdDSA" -> alg;
            default -> throw new IllegalArgumentException("unsupported alg " + alg);
        };
    }

    private static PSSParameterSpec pss(String alg) {
        int bits = Integer.parseInt(alg.substring(2));
        String h = "SHA-" + bits;
        return new PSSParameterSpec(h, "MGF1", new MGF1ParameterSpec(h), bits / 8, 1);
    }

    /** A parsed JWK with the key material and its pinned algorithm (the "alg" member, if any). */
    record Jwk(String kty, String kid, String alg, String crv, Key verifyKey, PrivateKey privateKey, byte[] secret,
               Map<String, Object> json) {

        static Jwk parse(Map<String, Object> j) {
            try {
                String kty = (String) j.get("kty");
                String kid = (String) j.get("kid");
                String alg = (String) j.get("alg");
                switch (kty) {
                    case "oct": {
                        byte[] k = KbSupport.unb64u((String) j.get("k"));
                        return new Jwk(kty, kid, alg, null, null, null, k, j);
                    }
                    case "RSA": {
                        BigInteger n = big(j, "n");
                        BigInteger e = big(j, "e");
                        KeyFactory kf = KeyFactory.getInstance("RSA");
                        PublicKey pub = kf.generatePublic(new RSAPublicKeySpec(n, e));
                        PrivateKey priv = j.containsKey("d") ? kf.generatePrivate(new RSAPrivateCrtKeySpec(n, e, big(j, "d"),
                                big(j, "p"), big(j, "q"), big(j, "dp"), big(j, "dq"), big(j, "qi"))) : null;
                        return new Jwk(kty, kid, alg, null, pub, priv, null, j);
                    }
                    case "EC": {
                        String crv = (String) j.get("crv");
                        String curve = switch (crv) {
                            case "P-256" -> "secp256r1";
                            case "P-384" -> "secp384r1";
                            case "P-521" -> "secp521r1";
                            default -> throw new IllegalArgumentException("unsupported crv " + crv);
                        };
                        ECParameterSpec ps = WebAuthnRp.ecParams(curve);
                        BigInteger x = big(j, "x");
                        BigInteger y = big(j, "y");
                        WebAuthnRp.requireOnCurve(ps, x, y);
                        KeyFactory kf = KeyFactory.getInstance("EC");
                        PublicKey pub = kf.generatePublic(new ECPublicKeySpec(new ECPoint(x, y), ps));
                        PrivateKey priv = j.containsKey("d") ? kf.generatePrivate(new ECPrivateKeySpec(big(j, "d"), ps)) : null;
                        return new Jwk(kty, kid, alg, crv, pub, priv, null, j);
                    }
                    case "OKP": {
                        String crv = (String) j.get("crv");
                        NamedParameterSpec ps = switch (crv) {
                            case "Ed25519" -> NamedParameterSpec.ED25519;
                            case "Ed448" -> NamedParameterSpec.ED448;
                            default -> throw new IllegalArgumentException("unsupported OKP crv " + crv);
                        };
                        KeyFactory kf = KeyFactory.getInstance(crv);
                        PublicKey pub = kf.generatePublic(new EdECPublicKeySpec(ps, WebAuthnRp.edPoint(KbSupport.unb64u((String) j.get("x")))));
                        PrivateKey priv = j.containsKey("d") ? kf.generatePrivate(new EdECPrivateKeySpec(ps, KbSupport.unb64u((String) j.get("d")))) : null;
                        return new Jwk(kty, kid, alg, crv, pub, priv, null, j);
                    }
                    default:
                        throw new IllegalArgumentException("unsupported kty " + kty);
                }
            } catch (GeneralSecurityException e) {
                throw new IllegalArgumentException(e);
            }
        }

        private static BigInteger big(Map<String, Object> j, String m) {
            return new BigInteger(1, KbSupport.unb64u((String) j.get(m)));
        }

        /** RFC 7638: SHA-256 over the REQUIRED members only, lexicographically ordered, no whitespace. */
        String thumbprint() {
            String[] req = switch (kty) {
                case "RSA" -> new String[] {"e", "kty", "n"};
                case "EC" -> new String[] {"crv", "kty", "x", "y"};
                case "OKP" -> new String[] {"crv", "kty", "x"};
                case "oct" -> new String[] {"k", "kty"};
                default -> throw new IllegalStateException(kty);
            };
            Map<String, Object> m = new LinkedHashMap<>();
            for (String r : req) {
                m.put(r, json.get(r));
            }
            return KbSupport.b64u(sha256(MiniJson.canonical(m).getBytes(StandardCharsets.UTF_8)));
        }

        /** Does this key's TYPE fit the algorithm family? (the check whose absence is RS256->HS256 confusion) */
        boolean fits(String a) {
            return switch (kty) {
                case "oct" -> a.startsWith("HS");
                case "RSA" -> a.startsWith("RS") || a.startsWith("PS");
                case "EC" -> a.equals("ES256") && "P-256".equals(crv) || a.equals("ES384") && "P-384".equals(crv)
                        || a.equals("ES512") && "P-521".equals(crv);
                case "OKP" -> a.equals("EdDSA") || a.equals(crv);
                default -> false;
            };
        }
    }

    // ---------------------------------------------------------------- JWS compact

    static String sign(Map<String, Object> header, byte[] payload, Jwk key) {
        String input = KbSupport.b64u(MiniJson.write(header).getBytes(StandardCharsets.UTF_8)) + "." + KbSupport.b64u(payload);
        return input + "." + KbSupport.b64u(rawSign((String) header.get("alg"), key, input.getBytes(StandardCharsets.US_ASCII)));
    }

    static byte[] rawSign(String alg, Jwk key, byte[] input) {
        try {
            if (alg.startsWith("HS")) {
                Mac mac = Mac.getInstance(jca(alg));
                mac.init(new SecretKeySpec(key.secret(), jca(alg)));
                return mac.doFinal(input);
            }
            Signature s = Signature.getInstance(jca(alg));
            if (alg.startsWith("PS")) {
                s.setParameter(pss(alg));
            }
            s.initSign(key.privateKey());
            s.update(input);
            return s.sign();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Pure signature check; the CALLER decides which alg is acceptable for which key (see L10). */
    static boolean rawVerify(String alg, Jwk key, byte[] input, byte[] sig) {
        try {
            if (alg.startsWith("HS")) {
                return MessageDigest.isEqual(rawSign(alg, key, input), sig); // constant-time
            }
            Signature s = Signature.getInstance(jca(alg));
            if (alg.startsWith("PS")) {
                s.setParameter(pss(alg));
            }
            s.initVerify((PublicKey) key.verifyKey());
            s.update(input);
            return s.verify(sig);
        } catch (GeneralSecurityException | ClassCastException e) {
            return false;
        }
    }

    record Parts(String headerB64, String payloadB64, String sigB64, Map<String, Object> header, byte[] payload, byte[] sig) {
        byte[] signingInput() {
            return (headerB64 + "." + payloadB64).getBytes(StandardCharsets.US_ASCII);
        }
    }

    /** Strict compact parse: exactly 3 segments, canonical base64url, I-JSON header with no duplicates. */
    static Parts parse(String compact) {
        String[] p = compact.split("\\.", -1);
        if (p.length != 3) {
            throw new IllegalArgumentException("JWS compact serialization must have 3 segments, got " + p.length);
        }
        Map<String, Object> h = MiniJson.object(new String(KbSupport.unb64u(p[0]), StandardCharsets.UTF_8));
        return new Parts(p[0], p[1], p[2], h, KbSupport.unb64u(p[1]), KbSupport.unb64u(p[2]));
    }

    static byte[] sha256(byte[] in) {
        return WebAuthnRp.sha256(in);
    }

    // ---------------------------------------------------------------- RFC text extraction

    /** The first JWK object ('{' followed by "kty") after {@code anchor} (last occurrence: skips the ToC). */
    static Map<String, Object> jsonAfter(String text, String anchor) {
        int a = text.lastIndexOf(anchor);
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\{\\s*\"kty\"").matcher(text);
        if (a < 0 || !m.find(a)) {
            throw new IllegalStateException("no JWK after " + anchor);
        }
        int start = m.start();
        int depth = 0;
        int end = start;
        for (int k = start; k < text.length(); k++) {
            char c = text.charAt(k);
            depth += c == '{' ? 1 : c == '}' ? -1 : 0;
            if (depth == 0) {
                end = k + 1;
                break;
            }
        }
        return MiniJson.object(KbSupport.squash(text.substring(start, end)));
    }

    /** The compact serialization printed (with display line breaks) after {@code anchor}. */
    static String compactAfter(String text, String anchor) {
        int a = text.lastIndexOf(anchor);
        StringBuilder sb = new StringBuilder();
        boolean started = false;
        for (String line : text.substring(a).split("\n")) {
            String t = line.trim();
            if (!started) {
                if (t.startsWith("eyJ")) {
                    started = true;
                } else {
                    continue;
                }
            }
            if (t.isEmpty() || !t.matches("[A-Za-z0-9_.\\-]+")) {
                break;
            }
            sb.append(t);
        }
        return sb.toString();
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String r7515 = KbSupport.rfc(fx, "rfc7515.txt");
        String r8037 = KbSupport.rfc(fx, "rfc8037.txt");
        String r7638 = KbSupport.rfc(fx, "rfc7638.txt");

        KbSupport.section("RFC 7515 Appendix A (keys and serializations extracted from fixtures/rfc7515.txt)");
        Jwk hk = Jwk.parse(jsonAfter(r7515, "A.1.1.  Encoding"));
        String a1 = compactAfter(r7515.substring(0, r7515.lastIndexOf("A.1.2.  Validating")), "complete JWS");
        Parts p1 = parse(a1);
        KbSupport.check("A.1 HS256: recomputed HMAC == RFC signature " + p1.sigB64().substring(0, 16) + "...",
                KbSupport.b64u(rawSign("HS256", hk, p1.signingInput())).equals(p1.sigB64()));
        KbSupport.check("A.1 header bytes contain CRLF + space (never re-serialize what you verify)",
                new String(KbSupport.unb64u(p1.headerB64()), StandardCharsets.UTF_8).contains("\r\n "));

        Jwk rk = Jwk.parse(jsonAfter(r7515, "A.2.1.  Encoding"));
        Parts p2 = parse(compactAfter(r7515.substring(0, r7515.lastIndexOf("A.2.2.  Validating")), "complete JWS"));
        KbSupport.check("A.2 RS256 (deterministic PKCS#1 v1.5): our signature == RFC signature, 2048-bit key",
                KbSupport.b64u(rawSign("RS256", rk, p2.signingInput())).equals(p2.sigB64())
                        && ((RSAPublicKey) rk.verifyKey()).getModulus().bitLength() == 2048);

        Jwk ek = Jwk.parse(jsonAfter(r7515, "A.3.1.  Encoding"));
        Parts p3 = parse(compactAfter(r7515.substring(0, r7515.lastIndexOf("A.3.2.  Validating")), "complete JWS"));
        byte[] fresh = rawSign("ES256", ek, p3.signingInput());
        KbSupport.check("A.3 ES256: RFC signature verifies; it is 64 bytes raw r||s (not DER)", rawVerify("ES256", ek, p3.signingInput(), p3.sig())
                && p3.sig().length == 64);
        KbSupport.check("A.3 ES256: a fresh signature differs (random k) and also verifies",
                !Arrays.equals(fresh, p3.sig()) && rawVerify("ES256", ek, p3.signingInput(), fresh));

        Jwk ek512 = Jwk.parse(jsonAfter(r7515, "A.4.1.  Encoding"));
        Parts p4 = parse(compactAfter(r7515.substring(0, r7515.lastIndexOf("A.4.2.  Validating")), "complete JWS"));
        KbSupport.check("A.4 ES512 (P-521): RFC signature verifies, 132 bytes = 2 x 66", rawVerify("ES512", ek512, p4.signingInput(), p4.sig())
                && p4.sig().length == 132);

        String a5 = compactAfter(r7515.substring(0, r7515.lastIndexOf("A.6.  Example JWS Using General JWS JSON")), "complete JWS");
        KbSupport.check("A.5 unsecured JWS has alg 'none' and an EMPTY third segment", a5.endsWith(".")
                && "none".equals(MiniJson.object(new String(KbSupport.unb64u(a5.split("\\.")[0]), StandardCharsets.UTF_8)).get("alg")));

        KbSupport.section("RFC 8037 Appendix A: Ed25519 (deterministic: the signature must match exactly)");
        Jwk ed = Jwk.parse(jsonAfter(r8037, "A.1.  Ed25519 Private Key"));
        String a4 = compactAfter(r8037.substring(0, r8037.lastIndexOf("A.5.  Ed25519 Validation")), "So the compact serialization");
        Parts e4 = parse(a4);
        KbSupport.check("A.4 header is {\"alg\":\"EdDSA\"} (polymorphic; RFC 9864 replaces it with \"Ed25519\")", "EdDSA".equals(e4.header().get("alg")));
        KbSupport.check("A.4 our Ed25519 signature == RFC signature " + e4.sigB64().substring(0, 16) + "...",
                KbSupport.b64u(rawSign("Ed25519", ed, e4.signingInput())).equals(e4.sigB64()));
        KbSupport.check("A.5 verifies with the public key alone (x)", rawVerify("Ed25519",
                Jwk.parse(jsonAfter(r8037, "A.2.  Ed25519 Public Key")), e4.signingInput(), e4.sig()));
        KbSupport.check("A.3 thumbprint " + ed.thumbprint(), ed.thumbprint().equals("kPrK_qmxVWaYVA9wwBF6Iuo3vVzz7TxHCTwXBygrS4k"));
        KbSupport.mustCite(r8037, "kPrK_qmxVWaYVA9wwBF6Iuo3vVzz7TxHCTwXBygrS4k", "RFC 8037 A.3 thumbprint");

        KbSupport.section("RFC 7638 section 3.1: JWK thumbprint");
        Jwk tk = Jwk.parse(jsonAfter(r7638, "3.1.  Example JWK Thumbprint Computation"));
        KbSupport.check("thumbprint " + tk.thumbprint() + " (alg and kid are NOT hashed)", tk.thumbprint().equals("NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs"));
        KbSupport.mustCite(r7638, "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs", "RFC 7638 thumbprint");

        KbSupport.section("Round trips for every algorithm this JDK provides");
        java.security.SecureRandom rng = new java.security.SecureRandom();
        String[][] algs = {{"HS256"}, {"RS256"}, {"PS256"}, {"ES256"}, {"ES384"}, {"ES512"}, {"Ed25519"}, {"Ed448"}};
        StringBuilder ok = new StringBuilder();
        int n = 0;
        for (String[] a : algs) {
            Jwk k = generate(a[0], rng);
            Map<String, Object> h = new LinkedHashMap<>();
            h.put("alg", a[0]);
            h.put("typ", "at+jwt");
            h.put("kid", k.kid());
            String jws = sign(h, "{\"sub\":\"alice\"}".getBytes(StandardCharsets.UTF_8), k);
            Parts p = parse(jws);
            boolean good = rawVerify(a[0], k, p.signingInput(), p.sig());
            byte[] tampered = p.signingInput().clone();
            tampered[tampered.length - 2] ^= 1;
            boolean bad = rawVerify(a[0], k, tampered, p.sig());
            if (good && !bad && k.fits(a[0])) {
                ok.append(a[0]).append('(').append(p.sig().length).append("B) ");
                n++;
            }
        }
        KbSupport.check(n + "/8 sign, verify, reject-tampered: " + ok.toString().trim(), n == 8);
        KbSupport.verdict();
    }

    /** Fresh key for an algorithm, as a Jwk (kid = thumbprint). */
    static Jwk generate(String alg, java.security.SecureRandom rng) throws GeneralSecurityException {
        Map<String, Object> j = new LinkedHashMap<>();
        if (alg.startsWith("HS")) {
            byte[] k = new byte[Integer.parseInt(alg.substring(2)) / 8];
            rng.nextBytes(k);
            j.put("kty", "oct");
            j.put("k", KbSupport.b64u(k));
        } else if (alg.startsWith("RS") || alg.startsWith("PS")) {
            java.security.KeyPairGenerator g = java.security.KeyPairGenerator.getInstance("RSA");
            g.initialize(2048, rng);
            java.security.KeyPair kp = g.generateKeyPair();
            java.security.interfaces.RSAPrivateCrtKey pk = (java.security.interfaces.RSAPrivateCrtKey) kp.getPrivate();
            j.put("kty", "RSA");
            j.put("n", KbSupport.b64u(unsigned(pk.getModulus())));
            j.put("e", KbSupport.b64u(unsigned(pk.getPublicExponent())));
            j.put("d", KbSupport.b64u(unsigned(pk.getPrivateExponent())));
            j.put("p", KbSupport.b64u(unsigned(pk.getPrimeP())));
            j.put("q", KbSupport.b64u(unsigned(pk.getPrimeQ())));
            j.put("dp", KbSupport.b64u(unsigned(pk.getPrimeExponentP())));
            j.put("dq", KbSupport.b64u(unsigned(pk.getPrimeExponentQ())));
            j.put("qi", KbSupport.b64u(unsigned(pk.getCrtCoefficient())));
        } else if (alg.startsWith("ES")) {
            String[] c = switch (alg) {
                case "ES256" -> new String[] {"secp256r1", "P-256", "32"};
                case "ES384" -> new String[] {"secp384r1", "P-384", "48"};
                default -> new String[] {"secp521r1", "P-521", "66"};
            };
            java.security.KeyPairGenerator g = java.security.KeyPairGenerator.getInstance("EC");
            g.initialize(new java.security.spec.ECGenParameterSpec(c[0]), rng);
            java.security.KeyPair kp = g.generateKeyPair();
            ECPublicKey pub = (ECPublicKey) kp.getPublic();
            int len = Integer.parseInt(c[2]);
            j.put("kty", "EC");
            j.put("crv", c[1]);
            j.put("x", KbSupport.b64u(WebAuthnRp.fixed(pub.getW().getAffineX(), len)));
            j.put("y", KbSupport.b64u(WebAuthnRp.fixed(pub.getW().getAffineY(), len)));
            j.put("d", KbSupport.b64u(WebAuthnRp.fixed(((java.security.interfaces.ECPrivateKey) kp.getPrivate()).getS(), len)));
        } else {
            java.security.KeyPairGenerator g = java.security.KeyPairGenerator.getInstance(alg);
            java.security.KeyPair kp = g.generateKeyPair();
            j.put("kty", "OKP");
            j.put("crv", alg);
            j.put("x", KbSupport.b64u(edEncode((EdECPublicKey) kp.getPublic())));
            // PKCS#8 for EdDSA ends with the raw private key bytes (OCTET STRING inside OCTET STRING)
            byte[] p8 = kp.getPrivate().getEncoded();
            int len = alg.equals("Ed25519") ? 32 : 57;
            j.put("d", KbSupport.b64u(Arrays.copyOfRange(p8, p8.length - len, p8.length)));
        }
        Jwk tmp = Jwk.parse(j);
        j.put("kid", tmp.thumbprint());
        j.put("alg", alg);
        return Jwk.parse(j);
    }

    static byte[] unsigned(BigInteger v) {
        byte[] b = v.toByteArray();
        return b[0] == 0 && b.length > 1 ? Arrays.copyOfRange(b, 1, b.length) : b;
    }

    /** Inverse of WebAuthnRp.edPoint: little-endian y with the x parity in the top bit. */
    static byte[] edEncode(EdECPublicKey k) {
        int len = k.getParams().getName().equals("Ed25519") ? 32 : 57;
        byte[] be = WebAuthnRp.fixed(k.getPoint().getY(), len);
        byte[] le = new byte[len];
        for (int i = 0; i < len; i++) {
            le[i] = be[len - 1 - i];
        }
        if (k.getPoint().isXOdd()) {
            le[len - 1] |= (byte) 0x80;
        }
        return le;
    }
}
```

<!-- output:Jose.java -->
```text

== RFC 7515 Appendix A (keys and serializations extracted from fixtures/rfc7515.txt)
  [PASS] A.1 HS256: recomputed HMAC == RFC signature dBjftJeZ4CVP-mB9...
  [PASS] A.1 header bytes contain CRLF + space (never re-serialize what you verify)
  [PASS] A.2 RS256 (deterministic PKCS#1 v1.5): our signature == RFC signature, 2048-bit key
  [PASS] A.3 ES256: RFC signature verifies; it is 64 bytes raw r||s (not DER)
  [PASS] A.3 ES256: a fresh signature differs (random k) and also verifies
  [PASS] A.4 ES512 (P-521): RFC signature verifies, 132 bytes = 2 x 66
  [PASS] A.5 unsecured JWS has alg 'none' and an EMPTY third segment

== RFC 8037 Appendix A: Ed25519 (deterministic: the signature must match exactly)
  [PASS] A.4 header is {"alg":"EdDSA"} (polymorphic; RFC 9864 replaces it with "Ed25519")
  [PASS] A.4 our Ed25519 signature == RFC signature hgyY0il_MGCjP0Jz...
  [PASS] A.5 verifies with the public key alone (x)
  [PASS] A.3 thumbprint kPrK_qmxVWaYVA9wwBF6Iuo3vVzz7TxHCTwXBygrS4k
  [PASS] constant cited verbatim from fixture: RFC 8037 A.3 thumbprint

== RFC 7638 section 3.1: JWK thumbprint
  [PASS] thumbprint NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs (alg and kid are NOT hashed)
  [PASS] constant cited verbatim from fixture: RFC 7638 thumbprint

== Round trips for every algorithm this JDK provides
  [PASS] 8/8 sign, verify, reject-tampered: HS256(32B) RS256(256B) PS256(256B) ES256(64B) ES384(96B) ES512(132B) Ed25519(64B) Ed448(114B)

verdict: OK (15 checks)
```

---

## 4. JWE: when tokens must be confidential

Encrypt when the token carries data that intermediaries must not read: PII, account numbers, or claims for a partner that your own edge should not inspect. Encryption is not a substitute for the BFF pattern (tokens out of the browser, Folder 04) or for opaque tokens with introspection (Folder 05) [E].

```text
  JWE compact:  header . encrypted_key . iv . ciphertext . tag        (5 segments)
                \____/                                     AAD = ASCII(BASE64URL(protected header))

  "alg" = how the Content Encryption Key (CEK) reaches the recipient     "enc" = how the payload is encrypted
  -------------------------------------------------------------------   -----------------------------------
  RSA-OAEP / RSA-OAEP-256   CEK encrypted to the recipient's RSA key     A128GCM / A256GCM   AEAD, 96-bit IV
  A128KW / A256KW           CEK wrapped with a shared KEK (RFC 3394)     A128CBC-HS256 ...   AES-CBC + HMAC,
  dir                       the shared key IS the CEK                                         MAC checked FIRST
  ECDH-ES                   CEK = ConcatKDF(ECDH(epk, recipient))        (never "zip":"DEF" on attacker-
  ECDH-ES+A256KW            ECDH-derived key wraps a random CEK           influenced content: compression oracle)
  RSA1_5                    PKCS#1 v1.5 encryption: Bleichenbacher padding oracle -> do not accept
```

L11's points:

- **The protected header is the AAD.** Editing it breaks the GCM tag, so headers cannot be swapped between tokens.
- **AES-CBC-HMAC must verify the MAC before decrypting,** in constant time. Decrypting first and reporting "bad padding" vs "bad MAC" separately is a padding oracle. L11 tampers with the last block and gets the same "authentication tag mismatch" either way.
- **The ECDH-ES ephemeral key (`epk`) comes from the attacker.** Reject points not on the curve before any key agreement, or a small-subgroup point leaks bits of the recipient's private key over many queries (the invalid-curve attack).
- **Pin the key-management algorithm exactly as you pin `alg` for JWS.** A recipient that accepts `dir` when it expected `RSA-OAEP-256`, or `RSA1_5` at all, has handed the attacker a choice.
- **Nested JWT order is sign-then-encrypt** (`cty: JWT`). The signature attests to the claims, and encryption hides them. Encrypt-then-sign reveals who signed and lets the outer signature be stripped and replaced.

<!-- listing:JweLab.java -->
```java
import java.io.ByteArrayOutputStream;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.crypto.Cipher;
import javax.crypto.KeyAgreement;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * L11 - JWE (RFC 7516) from first principles on the JDK: RSA-OAEP + A256GCM, A128KW + A128CBC-HS256 (MAC-then-
 * decrypt, constant time), ECDH-ES with the NIST Concat KDF (RFC 7518 section 4.6) and a nested sign-then-encrypt
 * JWT. Oracles: RFC 7516 A.1 and A.3 decrypt to the RFC's plaintexts; RFC 7518 Appendix C's derived key.
 */
public final class JweLab {

    record Jwe(Map<String, Object> header, String headerB64, byte[] encryptedKey, byte[] iv, byte[] ciphertext, byte[] tag) {
        static Jwe parse(String compact) {
            String[] p = compact.split("\\.", -1);
            if (p.length != 5) {
                throw new IllegalArgumentException("JWE compact serialization must have 5 segments, got " + p.length);
            }
            return new Jwe(MiniJson.object(new String(KbSupport.unb64u(p[0]), StandardCharsets.UTF_8)), p[0],
                    KbSupport.unb64u(p[1]), KbSupport.unb64u(p[2]), KbSupport.unb64u(p[3]), KbSupport.unb64u(p[4]));
        }

        byte[] aad() {
            return headerB64.getBytes(StandardCharsets.US_ASCII); // AAD = ASCII(BASE64URL(UTF8(protected header)))
        }
    }

    /** The CEK, unwrapped according to "alg" -- with the accepted algs pinned by the caller. */
    static byte[] unwrapCek(Jwe j, Object key, String pinnedAlg) throws GeneralSecurityException {
        String alg = (String) j.header().get("alg");
        if (!alg.equals(pinnedAlg)) {
            throw new SecurityException("alg " + alg + " not the pinned " + pinnedAlg);
        }
        switch (alg) {
            case "RSA-OAEP": {
                Cipher c = Cipher.getInstance("RSA/ECB/OAEPWithSHA-1AndMGF1Padding");
                c.init(Cipher.DECRYPT_MODE, (PrivateKey) key);
                return c.doFinal(j.encryptedKey());
            }
            case "RSA-OAEP-256": {
                Cipher c = Cipher.getInstance("RSA/ECB/OAEPPadding");
                c.init(Cipher.DECRYPT_MODE, (PrivateKey) key, new javax.crypto.spec.OAEPParameterSpec("SHA-256", "MGF1",
                        java.security.spec.MGF1ParameterSpec.SHA256, javax.crypto.spec.PSource.PSpecified.DEFAULT));
                return c.doFinal(j.encryptedKey());
            }
            case "A128KW": {
                Cipher c = Cipher.getInstance("AESWrap");
                c.init(Cipher.UNWRAP_MODE, new SecretKeySpec((byte[]) key, "AES"));
                return c.unwrap(j.encryptedKey(), "AES", Cipher.SECRET_KEY).getEncoded();
            }
            default:
                throw new SecurityException("alg " + alg + " not supported");
        }
    }

    static byte[] decryptContent(Jwe j, byte[] cek) throws GeneralSecurityException {
        String enc = (String) j.header().get("enc");
        switch (enc) {
            case "A128GCM", "A256GCM": {
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(cek, "AES"), new GCMParameterSpec(128, j.iv()));
                c.updateAAD(j.aad());
                return c.doFinal(concat(j.ciphertext(), j.tag()));
            }
            case "A128CBC-HS256": {
                // RFC 7518 5.2.2.2: MAC_KEY = first 16 bytes, ENC_KEY = last 16; verify the tag BEFORE decrypting
                byte[] macKey = Arrays.copyOfRange(cek, 0, 16);
                byte[] encKey = Arrays.copyOfRange(cek, 16, 32);
                byte[] al = ByteBuffer.allocate(8).putLong((long) j.aad().length * 8).array();
                Mac mac = Mac.getInstance("HmacSHA256");
                mac.init(new SecretKeySpec(macKey, "HmacSHA256"));
                byte[] full = mac.doFinal(concat(j.aad(), j.iv(), j.ciphertext(), al));
                if (!MessageDigest.isEqual(Arrays.copyOf(full, 16), j.tag())) {
                    throw new SecurityException("authentication tag mismatch"); // no padding oracle: never decrypt first
                }
                Cipher c = Cipher.getInstance("AES/CBC/PKCS5Padding");
                c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(encKey, "AES"), new IvParameterSpec(j.iv()));
                return c.doFinal(j.ciphertext());
            }
            default:
                throw new SecurityException("enc " + enc + " not supported");
        }
    }

    /** NIST SP 800-56A Concat KDF as profiled by RFC 7518 4.6.2 (single SHA-256 round is enough for <= 256 bits). */
    static byte[] concatKdf(byte[] z, String algId, byte[] apu, byte[] apv, int keyBits) throws GeneralSecurityException {
        ByteArrayOutputStream other = new ByteArrayOutputStream();
        byte[] alg = algId.getBytes(StandardCharsets.US_ASCII);
        other.writeBytes(be32(alg.length));
        other.writeBytes(alg);
        other.writeBytes(be32(apu.length));
        other.writeBytes(apu);
        other.writeBytes(be32(apv.length));
        other.writeBytes(apv);
        other.writeBytes(be32(keyBits));
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        sha.update(be32(1));
        sha.update(z);
        sha.update(other.toByteArray());
        return Arrays.copyOf(sha.digest(), keyBits / 8);
    }

    static byte[] ecdh(PrivateKey mine, PublicKey theirs) throws GeneralSecurityException {
        KeyAgreement ka = KeyAgreement.getInstance("ECDH");
        ka.init(mine);
        ka.doPhase(theirs, true);
        return ka.generateSecret();
    }

    public static void main(String[] args) throws Exception {
        Path fx = KbSupport.fixtures(args);
        String r7516 = KbSupport.rfc(fx, "rfc7516.txt");
        String r7518 = KbSupport.rfc(fx, "rfc7518.txt");

        KbSupport.section("RFC 7516 A.1: RSA-OAEP + A256GCM (key and compact JWE extracted from the fixture)");
        Jose.Jwk rsa = Jose.Jwk.parse(Jose.jsonAfter(r7516.substring(0, r7516.lastIndexOf("A.1.4.")), "A.1.  Example JWE using RSAES-OAEP"));
        Jwe a1 = Jwe.parse(Jose.compactAfter(r7516.substring(0, r7516.lastIndexOf("A.1.8.  Validation")), "A.1.7.  Complete Representation"));
        KbSupport.check("header " + MiniJson.write(a1.header()), "RSA-OAEP".equals(a1.header().get("alg")) && "A256GCM".equals(a1.header().get("enc")));
        byte[] cek1 = unwrapCek(a1, rsa.privateKey(), "RSA-OAEP");
        String pt1 = new String(decryptContent(a1, cek1), StandardCharsets.UTF_8);
        KbSupport.check("CEK is 256 bits; plaintext: \"" + pt1 + "\"", cek1.length == 32);
        KbSupport.mustCite(r7516, pt1, "A.1 plaintext");
        byte[] badTag = a1.tag().clone();
        badTag[0] ^= 1;
        KbSupport.check("one flipped tag bit -> AEADBadTagException", throwsOn(() -> decryptContent(
                new Jwe(a1.header(), a1.headerB64(), a1.encryptedKey(), a1.iv(), a1.ciphertext(), badTag), cek1)));
        String swappedHeader = KbSupport.b64u("{\"alg\":\"RSA-OAEP\",\"enc\":\"A256GCM\",\"kid\":\"x\"}".getBytes(StandardCharsets.UTF_8));
        KbSupport.check("editing the protected header breaks GCM (the header is the AAD)", throwsOn(() -> decryptContent(
                new Jwe(a1.header(), swappedHeader, a1.encryptedKey(), a1.iv(), a1.ciphertext(), a1.tag()), cek1)));
        KbSupport.check("pinned alg: the same JWE presented to a verifier expecting RSA-OAEP-256 is refused",
                throwsOn(() -> unwrapCek(a1, rsa.privateKey(), "RSA-OAEP-256")));

        KbSupport.section("RFC 7516 A.3: A128KW + A128CBC-HS256");
        Map<String, Object> octJson = Jose.jsonAfter(r7516.substring(0, r7516.lastIndexOf("A.3.4.")), "A.3.  Example JWE Using AES Key Wrap");
        byte[] kek = KbSupport.unb64u((String) octJson.get("k"));
        Jwe a3 = Jwe.parse(Jose.compactAfter(r7516.substring(0, r7516.lastIndexOf("A.3.8.  Validation")), "A.3.7.  Complete Representation"));
        byte[] cek3 = unwrapCek(a3, kek, "A128KW");
        String pt3 = new String(decryptContent(a3, cek3), StandardCharsets.UTF_8);
        KbSupport.check("CEK 256 bits = 128 MAC + 128 AES; plaintext: \"" + pt3 + "\"", cek3.length == 32);
        KbSupport.mustCite(r7516, pt3, "A.3 plaintext");
        byte[] ct = a3.ciphertext().clone();
        ct[ct.length - 1] ^= 1; // the classic CBC padding-oracle probe
        String err = message(() -> decryptContent(new Jwe(a3.header(), a3.headerB64(), a3.encryptedKey(), a3.iv(), ct, a3.tag()), cek3));
        KbSupport.check("tampered last ciphertext block -> '" + err + "' (MAC checked first: no padding oracle)", "authentication tag mismatch".equals(err));

        KbSupport.section("RFC 7518 Appendix C: ECDH-ES + Concat KDF");
        Map<String, Object> alice = Jose.jsonAfter(r7518, "Appendix C.  Example ECDH-ES Key Agreement Computation");
        Map<String, Object> bob = Jose.jsonAfter(r7518, "The consumer's (Bob's) key");
        Jose.Jwk aliceKey = Jose.Jwk.parse(alice);
        Jose.Jwk bobKey = Jose.Jwk.parse(bob);
        byte[] zA = ecdh(aliceKey.privateKey(), (PublicKey) bobKey.verifyKey());
        byte[] zB = ecdh(bobKey.privateKey(), (PublicKey) aliceKey.verifyKey());
        KbSupport.check("Z computed by Alice == Z computed by Bob (32 bytes)", Arrays.equals(zA, zB) && zA.length == 32);
        byte[] derived = concatKdf(zA, "A128GCM", "Alice".getBytes(StandardCharsets.US_ASCII), "Bob".getBytes(StandardCharsets.US_ASCII), 128);
        KbSupport.check("derived key " + KbSupport.b64u(derived) + " == RFC 7518 C", KbSupport.b64u(derived).equals("VqqN6vgjbSBcIijNcacQGg"));
        KbSupport.mustCite(r7518, "VqqN6vgjbSBcIijNcacQGg", "Appendix C derived key");
        ECPublicKey bp = (ECPublicKey) bobKey.verifyKey();
        BigInteger offY = bp.getW().getAffineY().add(BigInteger.ONE);
        KbSupport.check("invalid-curve defense: an epk off P-256 is refused before any ECDH",
                throwsOn(() -> {
                    WebAuthnRp.requireOnCurve(bp.getParams(), bp.getW().getAffineX(), offY);
                    return null;
                }));

        KbSupport.section("Nested JWT: sign (Ed25519, typ at+jwt) then encrypt (ECDH-ES direct, A256GCM, cty JWT)");
        SecureRandom rng = new SecureRandom();
        Jose.Jwk signer = Jose.generate("Ed25519", rng);
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", "Ed25519");
        h.put("typ", "at+jwt");
        h.put("kid", signer.kid());
        String inner = Jose.sign(h, "{\"sub\":\"alice\",\"acct\":\"DE89 3704 0044 0532 0130 00\"}".getBytes(StandardCharsets.UTF_8), signer);
        KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
        g.initialize(new ECGenParameterSpec("secp256r1"), rng);
        KeyPair recipient = g.generateKeyPair();
        KeyPair eph = g.generateKeyPair();
        ECPublicKey ep = (ECPublicKey) eph.getPublic();
        Map<String, Object> epk = new LinkedHashMap<>();
        epk.put("kty", "EC");
        epk.put("crv", "P-256");
        epk.put("x", KbSupport.b64u(WebAuthnRp.fixed(ep.getW().getAffineX(), 32)));
        epk.put("y", KbSupport.b64u(WebAuthnRp.fixed(ep.getW().getAffineY(), 32)));
        Map<String, Object> eh = new LinkedHashMap<>();
        eh.put("alg", "ECDH-ES");
        eh.put("enc", "A256GCM");
        eh.put("cty", "JWT");
        eh.put("epk", epk);
        String ehB64 = KbSupport.b64u(MiniJson.write(eh).getBytes(StandardCharsets.UTF_8));
        byte[] cek = concatKdf(ecdh(eph.getPrivate(), recipient.getPublic()), "A256GCM", new byte[0], new byte[0], 256);
        byte[] iv = new byte[12];
        rng.nextBytes(iv);
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(cek, "AES"), new GCMParameterSpec(128, iv));
        c.updateAAD(ehB64.getBytes(StandardCharsets.US_ASCII));
        byte[] out = c.doFinal(inner.getBytes(StandardCharsets.US_ASCII));
        String jwe = ehB64 + ".." + KbSupport.b64u(iv) + "." + KbSupport.b64u(Arrays.copyOf(out, out.length - 16)) + "."
                + KbSupport.b64u(Arrays.copyOfRange(out, out.length - 16, out.length));
        KbSupport.check("outer JWE has 5 segments with an EMPTY encrypted key (direct key agreement)", jwe.split("\\.", -1).length == 5 && jwe.contains(".."));
        // recipient side: rebuild epk (with the on-curve check), derive, decrypt, then verify the inner JWS
        Jwe rx = Jwe.parse(jwe);
        @SuppressWarnings("unchecked")
        Map<String, Object> rxEpk = (Map<String, Object>) rx.header().get("epk");
        Jose.Jwk epkJwk = Jose.Jwk.parse(rxEpk);
        byte[] rxCek = concatKdf(ecdh(recipient.getPrivate(), (PublicKey) epkJwk.verifyKey()), "A256GCM", new byte[0], new byte[0], 256);
        String rxInner = new String(decryptContent(rx, rxCek), StandardCharsets.US_ASCII);
        Jose.Parts ip = Jose.parse(rxInner);
        KbSupport.check("decrypted inner JWS verifies with the signer's key; typ=" + ip.header().get("typ"),
                Jose.rawVerify("Ed25519", signer, ip.signingInput(), ip.sig()));
        KbSupport.check("the IBAN is not visible in the outer token", !jwe.contains("DE89") && !new String(Base64Url.decodeAll(jwe), StandardCharsets.ISO_8859_1).contains("DE89"));
        ECParameterSpec ps = ((ECPublicKey) recipient.getPublic()).getParams();
        PublicKey rebuilt = KeyFactory.getInstance("EC").generatePublic(new ECPublicKeySpec(new ECPoint(ep.getW().getAffineX(), ep.getW().getAffineY()), ps));
        KbSupport.check("epk round-trips through JWK form", rebuilt.equals(epkJwk.verifyKey()));
        KbSupport.verdict();
    }

    /** Decodes every segment, ignoring empty ones, so we can grep the raw bytes. */
    static final class Base64Url {
        static byte[] decodeAll(String compact) {
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            for (String s : compact.split("\\.")) {
                if (!s.isEmpty()) {
                    o.writeBytes(KbSupport.unb64u(s));
                }
            }
            return o.toByteArray();
        }
    }

    interface Action {
        Object run() throws Exception;
    }

    static boolean throwsOn(Action a) {
        return message(a) != null;
    }

    static String message(Action a) {
        try {
            a.run();
            return null;
        } catch (Exception e) {
            return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
        }
    }

    static byte[] be32(int v) {
        return ByteBuffer.allocate(4).putInt(v).array();
    }

    static byte[] concat(byte[]... parts) {
        return WebAuthnRp.concat(parts);
    }
}
```

<!-- output:JweLab.java -->
```text

== RFC 7516 A.1: RSA-OAEP + A256GCM (key and compact JWE extracted from the fixture)
  [PASS] header {"alg":"RSA-OAEP","enc":"A256GCM"}
  [PASS] CEK is 256 bits; plaintext: "The true sign of intelligence is not knowledge but imagination."
  [PASS] constant cited verbatim from fixture: A.1 plaintext
  [PASS] one flipped tag bit -> AEADBadTagException
  [PASS] editing the protected header breaks GCM (the header is the AAD)
  [PASS] pinned alg: the same JWE presented to a verifier expecting RSA-OAEP-256 is refused

== RFC 7516 A.3: A128KW + A128CBC-HS256
  [PASS] CEK 256 bits = 128 MAC + 128 AES; plaintext: "Live long and prosper."
  [PASS] constant cited verbatim from fixture: A.3 plaintext
  [PASS] tampered last ciphertext block -> 'authentication tag mismatch' (MAC checked first: no padding oracle)

== RFC 7518 Appendix C: ECDH-ES + Concat KDF
  [PASS] Z computed by Alice == Z computed by Bob (32 bytes)
  [PASS] derived key VqqN6vgjbSBcIijNcacQGg == RFC 7518 C
  [PASS] constant cited verbatim from fixture: Appendix C derived key
  [PASS] invalid-curve defense: an epk off P-256 is refused before any ECDH

== Nested JWT: sign (Ed25519, typ at+jwt) then encrypt (ECDH-ES direct, A256GCM, cty JWT)
  [PASS] outer JWE has 5 segments with an EMPTY encrypted key (direct key agreement)
  [PASS] decrypted inner JWS verifies with the signer's key; typ=at+jwt
  [PASS] the IBAN is not visible in the outer token
  [PASS] epk round-trips through JWK form

verdict: OK (17 checks)
```

---

## 5. Verification as a policy (RFC 8725 in code)

The L7 verifier in L10 applies these steps in order. Each step names the attack it stops:

1. **Size cap** (8 KiB) before any parsing. This bounds JSON, base64 and PS-signature work.
2. **Exactly three segments; strict, canonical base64url; I-JSON header with no duplicate members** (#11, parser differentials).
3. **Reject `jwk`, `jku`, `x5u` and `x5c` for key selection** (#4, #5), and reject `crit` that you do not implement.
4. **`typ` equals the expected token type**: `at+jwt` for access tokens (#9, ID token used as an access token).
5. **`kid` → key from the local, pinned set** (#3, #6). An unknown kid triggers a *rate-limited* JWKS refresh (§6), never a filesystem or database lookup with attacker input.
6. **`alg` equals the key's pinned alg, and the key type fits** (#1, #2, #10).
7. **Verify the signature** (constant time for MACs).
8. **Claims:** `iss` exactly; `aud` contains this resource's identifier as an *element*, never a substring (#8); `exp` and `iat` required (#7); `now < exp + skew`; `iat ≤ now + skew`; `exp − iat ≤ max lifetime`; `nbf` honoured.
9. **`jti` replay cache** for one-time tokens, and wherever replay matters, retained until `exp` (#11, #12).
10. **Only then** map scopes and claims to authorities, and authorize (Folder 05).

<!-- listing:JwtAttackLab.java -->
```java
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.security.interfaces.ECPublicKey;
import java.util.Base64;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * L10 - JWT verification as a policy, not a function call. An L5 verifier written the way JWT tutorials and
 * old libraries did it (header-chosen alg, header-supplied keys, kid as a file name, substring audience, optional
 * exp, replay cache keyed on the token string) against an L7 verifier (alg pinned per key, typ=at+jwt per RFC 9068,
 * exact iss/aud, required exp with bounded skew and lifetime, strict base64url and JSON, jti replay cache).
 * Twelve attacks are run against both; then an offline dictionary attack on a weak HS256 secret.
 */
public final class JwtAttackLab {
    static final long NOW = 1_767_225_600L; // 2026-01-01T00:00:00Z, fixed so output is reproducible
    static final String ISS = "https://idp.example.com";
    static final String AUD = "https://payments.example.com";

    // ---------------------------------------------------------------- the L5 verifier

    static final class L5Verifier {
        final Jose.Jwk rsa;              // "the" verification key
        final String rsaPem;             // the same key as PEM text - what naive HMAC code ends up using
        final Path keyDir;               // kid -> file name (for HS keys)
        final Map<String, String> fakeInternet; // jku URL -> JWKS JSON the attacker hosts
        final Set<String> seenTokens = new HashSet<>();

        L5Verifier(Jose.Jwk rsa, Path keyDir, Map<String, String> internet) {
            this.rsa = rsa;
            this.rsaPem = pem((java.security.PublicKey) rsa.verifyKey());
            this.keyDir = keyDir;
            this.fakeInternet = internet;
        }

        @SuppressWarnings("unchecked")
        boolean accept(String token) {
            try {
                String[] p = token.split("\\.", -1);
                Map<String, Object> h = (Map<String, Object>) MiniJson.parse(
                        new String(Base64.getUrlDecoder().decode(p[0]), StandardCharsets.UTF_8), true); // last-wins
                byte[] input = (p[0] + "." + p[1]).getBytes(StandardCharsets.US_ASCII);
                byte[] sig = p.length > 2 ? Base64.getUrlDecoder().decode(p[2]) : new byte[0]; // lenient decoder
                String alg = (String) h.get("alg");
                boolean ok;
                if (alg.equalsIgnoreCase("none")) {
                    ok = true;                                            // "unsecured JWS is part of the spec"
                } else if (h.containsKey("jwk")) {
                    ok = Jose.rawVerify(alg, Jose.Jwk.parse((Map<String, Object>) h.get("jwk")), input, sig); // CVE-2018-0114 class
                } else if (h.containsKey("jku")) {
                    Map<String, Object> set = MiniJson.object(fakeInternet.get((String) h.get("jku")));
                    Jose.Jwk k = Jose.Jwk.parse(((List<Map<String, Object>>) set.get("keys")).get(0));
                    ok = Jose.rawVerify(alg, k, input, sig);              // SSRF + attacker-chosen key
                } else if (alg.startsWith("HS")) {
                    byte[] secret = h.containsKey("kid")
                            ? Files.readAllBytes(keyDir.resolve((String) h.get("kid")))      // path traversal
                            : rsaPem.getBytes(StandardCharsets.US_ASCII);                     // key confusion
                    ok = Jose.rawVerify(alg, new Jose.Jwk("oct", null, null, null, null, null, secret, Map.of()), input, sig);
                } else {
                    ok = Jose.rawVerify(alg, rsa, input, sig);
                }
                if (!ok) {
                    return false;
                }
                Map<String, Object> c = (Map<String, Object>) MiniJson.parse(new String(Base64.getUrlDecoder().decode(p[1]),
                        StandardCharsets.UTF_8), true);
                if (c.containsKey("exp") && ((Long) c.get("exp")) < NOW) {
                    return false;                                         // exp optional
                }
                if (!String.valueOf(c.get("aud")).contains("payments")) {
                    return false;                                         // substring audience
                }
                return seenTokens.add(sha(token));                        // replay cache keyed on token bytes
            } catch (Exception e) {
                return false;
            }
        }
    }

    // ---------------------------------------------------------------- the L7 verifier

    record Policy(String issuer, String audience, String typ, long skew, long maxLifetime, int maxTokenBytes) {
    }

    static final class L7Verifier {
        private final Policy policy;
        private final Map<String, Jose.Jwk> keysByKid = new HashMap<>(); // local, pinned trust anchors
        private final Map<String, Long> seenJti = new HashMap<>();

        L7Verifier(Policy policy, Jose.Jwk... keys) {
            this.policy = policy;
            for (Jose.Jwk k : keys) {
                if (k.kid() == null || k.alg() == null) {
                    throw new IllegalArgumentException("every trusted key needs a kid and a pinned alg");
                }
                keysByKid.put(k.kid(), k);
            }
        }

        /** Returns the subject, or throws with the first violated rule. */
        String verify(String token) {
            if (token.length() > policy.maxTokenBytes()) {
                throw new SecurityException("token larger than " + policy.maxTokenBytes() + " bytes");
            }
            Jose.Parts p;
            try {
                p = Jose.parse(token); // 3 segments, canonical base64url, strict JSON header
            } catch (IllegalArgumentException e) {
                throw new SecurityException("malformed: " + e.getMessage());
            }
            Map<String, Object> h = p.header();
            for (String forbidden : List.of("jwk", "jku", "x5u", "x5c")) {
                if (h.containsKey(forbidden)) {
                    throw new SecurityException("header '" + forbidden + "' must never select the verification key");
                }
            }
            if (h.containsKey("crit")) {
                throw new SecurityException("unsupported crit header");
            }
            if (!(h.get("typ") instanceof String t) || !t.equalsIgnoreCase(policy.typ())) {
                throw new SecurityException("typ " + h.get("typ") + " != " + policy.typ());
            }
            Jose.Jwk key = keysByKid.get(String.valueOf(h.get("kid")));
            if (key == null) {
                throw new SecurityException("unknown kid");
            }
            if (!key.alg().equals(h.get("alg")) || !key.fits(key.alg())) {
                throw new SecurityException("alg " + h.get("alg") + " not the alg pinned to kid (" + key.alg() + ")");
            }
            if (!Jose.rawVerify(key.alg(), key, p.signingInput(), p.sig())) {
                throw new SecurityException("bad signature");
            }
            Map<String, Object> c = MiniJson.object(new String(p.payload(), StandardCharsets.UTF_8));
            if (!policy.issuer().equals(c.get("iss"))) {
                throw new SecurityException("iss " + c.get("iss"));
            }
            Object aud = c.get("aud");
            boolean audOk = aud instanceof String s ? s.equals(policy.audience())
                    : aud instanceof List<?> l && l.contains(policy.audience());
            if (!audOk) {
                throw new SecurityException("aud " + aud + " does not contain " + policy.audience());
            }
            if (!(c.get("exp") instanceof Long exp) || !(c.get("iat") instanceof Long iat)) {
                throw new SecurityException("exp and iat are required");
            }
            if (NOW >= exp + policy.skew()) {
                throw new SecurityException("expired");
            }
            if (iat > NOW + policy.skew() || exp - iat > policy.maxLifetime()) {
                throw new SecurityException("iat in the future or lifetime above " + policy.maxLifetime() + " s");
            }
            if (c.get("nbf") instanceof Long nbf && NOW + policy.skew() < nbf) {
                throw new SecurityException("not yet valid");
            }
            if (!(c.get("jti") instanceof String jti) || seenJti.putIfAbsent(jti, exp) != null) {
                throw new SecurityException("jti missing or replayed");
            }
            return (String) c.get("sub");
        }
    }

    // ---------------------------------------------------------------- token minting helpers

    static Map<String, Object> claims(String aud, Long exp, String jti) {
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("iss", ISS);
        c.put("sub", "alice");
        c.put("aud", aud);
        c.put("client_id", "mobile-app");
        c.put("scope", "payments:write");
        c.put("iat", NOW - 60);
        if (exp != null) {
            c.put("exp", exp);
        }
        c.put("jti", jti);
        return c;
    }

    static String mint(Map<String, Object> header, Map<String, Object> claims, Jose.Jwk key) {
        return Jose.sign(header, MiniJson.write(claims).getBytes(StandardCharsets.UTF_8), key);
    }

    static Map<String, Object> hdr(String alg, String typ, String kid) {
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", alg);
        if (typ != null) {
            h.put("typ", typ);
        }
        if (kid != null) {
            h.put("kid", kid);
        }
        return h;
    }

    static String unsigned(Map<String, Object> header, Map<String, Object> claims) {
        return KbSupport.b64u(MiniJson.write(header).getBytes(StandardCharsets.UTF_8)) + "."
                + KbSupport.b64u(MiniJson.write(claims).getBytes(StandardCharsets.UTF_8)) + ".";
    }

    static String hmacWith(byte[] secret, Map<String, Object> header, Map<String, Object> claims) {
        return Jose.sign(header, MiniJson.write(claims).getBytes(StandardCharsets.UTF_8),
                new Jose.Jwk("oct", null, "HS256", null, null, null, secret, Map.of()));
    }

    static String pem(java.security.PublicKey k) {
        return "-----BEGIN PUBLIC KEY-----\n" + Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
                .encodeToString(k.getEncoded()) + "\n-----END PUBLIC KEY-----\n";
    }

    static String sha(String s) {
        return KbSupport.hex(WebAuthnRp.sha256(s.getBytes(StandardCharsets.US_ASCII)));
    }

    /** Same bytes, different base64url text: flip the unused low bits of the last character. */
    static String nonCanonical(String token) {
        int dot = token.lastIndexOf('.');
        String sig = token.substring(dot + 1);
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        int v = alphabet.indexOf(sig.charAt(sig.length() - 1));
        int unused = sig.length() % 4 == 2 ? 4 : sig.length() % 4 == 3 ? 2 : 0;
        char c = alphabet.charAt(v | ((1 << unused) - 1));
        return token.substring(0, dot + 1) + sig.substring(0, sig.length() - 1) + c;
    }

    /** ECDSA malleability: (r, s) and (r, n - s) are both valid signatures of the same message. */
    static String malleate(String token, ECPublicKey pub) {
        int dot = token.lastIndexOf('.');
        byte[] sig = KbSupport.unb64u(token.substring(dot + 1));
        int half = sig.length / 2;
        BigInteger n = pub.getParams().getOrder();
        BigInteger s = new BigInteger(1, java.util.Arrays.copyOfRange(sig, half, sig.length));
        byte[] s2 = WebAuthnRp.fixed(n.subtract(s), half);
        System.arraycopy(s2, 0, sig, half, half);
        return token.substring(0, dot + 1) + KbSupport.b64u(sig);
    }

    // ---------------------------------------------------------------- main

    public static void main(String[] args) throws Exception {
        SecureRandom rng = new SecureRandom();
        Jose.Jwk rs = Jose.generate("RS256", rng);
        Jose.Jwk es = Jose.generate("ES256", rng);
        Jose.Jwk attacker = Jose.generate("RS256", rng);
        Path dir = Files.createTempDirectory("jwtlab");
        Path keys = Files.createDirectories(dir.resolve("keys"));
        Files.writeString(Files.createDirectories(dir.resolve("public")).resolve("robots.txt"), "User-agent: *\nDisallow:\n");
        Files.write(keys.resolve("hs-2026"), new byte[32]);
        Map<String, Object> attackerSet = new LinkedHashMap<>();
        attackerSet.put("keys", List.of(publicOnly(attacker)));
        Map<String, String> internet = Map.of("https://evil.example/jwks.json", MiniJson.write(attackerSet));

        L5Verifier l5 = new L5Verifier(rs, keys, internet);
        Policy pol = new Policy(ISS, AUD, "at+jwt", 60, 3_600, 8_192);
        L7Verifier l7 = new L7Verifier(pol, rs, es);

        KbSupport.section("Baseline: a legitimate RFC 9068 access token");
        String good = mint(hdr("RS256", "at+jwt", rs.kid()), claims(AUD, NOW + 300, "jti-0"), rs);
        KbSupport.check("L5 accepts it", l5.accept(good));
        KbSupport.check("L7 accepts it: sub=" + l7.verify(good), true);
        String goodEs = mint(hdr("ES256", "at+jwt", es.kid()), claims(AUD, NOW + 300, "jti-es"), es);
        KbSupport.check("L7 accepts an ES256 token under the ES256-pinned kid: sub=" + l7.verify(goodEs), true);

        KbSupport.section("Twelve attacks (attacker holds NO private key of the issuer)");
        int[] tally = new int[2];
        Map<String, Object> evil = claims(AUD, NOW + 300, "jti-1");
        evil.put("sub", "admin");
        run(tally, "1  alg=none, empty signature", l5, l7, unsigned(hdr("none", "at+jwt", rs.kid()), evil));
        run(tally, "2  alg=nOnE (case games around a blocklist)", l5, l7, unsigned(hdr("nOnE", "at+jwt", rs.kid()), claims(AUD, NOW + 300, "jti-2")));
        run(tally, "3  RS256->HS256: HMAC keyed with the issuer's PUBLIC key PEM", l5, l7,
                hmacWith(l5.rsaPem.getBytes(StandardCharsets.US_ASCII), hdr("HS256", "at+jwt", null), claims(AUD, NOW + 300, "jti-3")));
        Map<String, Object> hj = hdr("RS256", "at+jwt", rs.kid());
        hj.put("jwk", publicOnly(attacker));
        run(tally, "4  embedded 'jwk' header with the attacker's own key", l5, l7, mint(hj, claims(AUD, NOW + 300, "jti-4"), attacker));
        Map<String, Object> hk = hdr("RS256", "at+jwt", rs.kid());
        hk.put("jku", "https://evil.example/jwks.json");
        run(tally, "5  'jku' pointing at an attacker-hosted JWKS", l5, l7, mint(hk, claims(AUD, NOW + 300, "jti-5"), attacker));
        run(tally, "6  kid=../public/robots.txt (HMAC with a world-readable file)", l5, l7,
                hmacWith(Files.readAllBytes(dir.resolve("public/robots.txt")), hdr("HS256", "at+jwt", "../public/robots.txt"),
                        claims(AUD, NOW + 300, "jti-6")));
        run(tally, "7  token with no exp at all (stolen = valid forever)", l5, l7,
                mint(hdr("RS256", "at+jwt", rs.kid()), claims(AUD, null, "jti-7"), rs));
        run(tally, "8  aud=https://payments-sandbox.example.com (substring match)", l5, l7,
                mint(hdr("RS256", "at+jwt", rs.kid()), claims("https://payments-sandbox.example.com", NOW + 300, "jti-8"), rs));
        Map<String, Object> idToken = claims("mobile-app", NOW + 300, "jti-9");
        idToken.put("aud", List.of("mobile-app", "payments-ui"));
        run(tally, "9  OIDC ID token (typ JWT, aud=client) replayed at the API", l5, l7, mint(hdr("RS256", "JWT", rs.kid()), idToken, rs));
        run(tally, "10 RS256 token under the ES256-pinned kid (alg/key mismatch)", l5, l7,
                mint(hdr("RS256", "at+jwt", es.kid()), claims(AUD, NOW + 300, "jti-10"), rs));
        String once = mint(hdr("RS256", "at+jwt", rs.kid()), claims(AUD, NOW + 300, "jti-11"), rs);
        l5.accept(once);
        l7.verify(once);
        run(tally, "11 replay with a non-canonical base64url signature", l5, l7, nonCanonical(once));
        String esOnce = mint(hdr("ES256", "at+jwt", es.kid()), claims(AUD, NOW + 300, "jti-12"), es);
        l7.verify(esOnce);
        String flipped = malleate(esOnce, (ECPublicKey) es.verifyKey());
        KbSupport.check("ECDSA (r, n-s) is a second valid signature for the same token",
                Jose.rawVerify("ES256", es, Jose.parse(flipped).signingInput(), Jose.parse(flipped).sig()) && !flipped.equals(esOnce));
        L5Verifier l5es = new L5Verifier(es, keys, internet); // the same L5 code, configured with the ES256 key
        KbSupport.check("L5(ES256) accepted the original token once", l5es.accept(esOnce));
        run(tally, "12 replay via ECDSA malleability (s -> n-s)", l5es, l7, flipped);
        KbSupport.info("summary: L5 accepted %d of 12, L7 rejected %d of 12", tally[0], tally[1]);
        KbSupport.check("L7 rejects all 12", tally[1] == 12);
        KbSupport.check("L5 accepts all 12", tally[0] == 12);

        KbSupport.section("Psychic signatures (CVE-2022-21449): r = s = 0 for ES256");
        String psychic = goodEs.substring(0, goodEs.lastIndexOf('.') + 1) + KbSupport.b64u(new byte[64]);
        KbSupport.check("this JDK (" + System.getProperty("java.version") + ") rejects the all-zero ECDSA signature",
                !Jose.rawVerify("ES256", es, Jose.parse(psychic).signingInput(), Jose.parse(psychic).sig()));

        KbSupport.section("Offline dictionary attack on a weak HS256 secret (hashcat mode 16500 does this on GPUs)");
        String[] wordlist = new String[2_000];
        for (int i = 0; i < wordlist.length; i++) {
            wordlist[i] = "secret" + i;
        }
        wordlist[1_337] = "your-256-bit-secret";
        String weak = hmacWith("your-256-bit-secret".getBytes(StandardCharsets.US_ASCII), hdr("HS256", "JWT", null), claims(AUD, NOW + 300, "w"));
        Jose.Parts wp = Jose.parse(weak);
        String found = null;
        int tries = 0;
        for (String w : wordlist) {
            tries++;
            if (Jose.rawVerify("HS256", new Jose.Jwk("oct", null, null, null, null, null, w.getBytes(StandardCharsets.US_ASCII), Map.of()),
                    wp.signingInput(), wp.sig())) {
                found = w;
                break;
            }
        }
        KbSupport.check("secret recovered after " + tries + " guesses from ONE captured token: '" + found + "'", "your-256-bit-secret".equals(found));
        KbSupport.check("a 256-bit random HS key is not in any wordlist (L7: asymmetric across trust boundaries anyway)",
                Jose.generate("HS256", rng).secret().length == 32);
        try (java.util.stream.Stream<Path> walk = Files.walk(dir)) { // remove the scratch key directory
            walk.sorted(java.util.Comparator.reverseOrder()).forEach(f -> f.toFile().delete());
        }
        KbSupport.verdict();
    }

    private static void run(int[] tally, String name, L5Verifier l5, L7Verifier l7, String token) {
        boolean l5ok = l5.accept(token);
        String why;
        try {
            l7.verify(token);
            why = null;
        } catch (RuntimeException e) {
            why = e.getMessage();
        }
        tally[0] += l5ok ? 1 : 0;
        tally[1] += why != null ? 1 : 0;
        KbSupport.info("%-62s L5 %-7s | L7 %s", name, l5ok ? "ACCEPTS" : "rejects", why == null ? "ACCEPTS" : "rejects: " + why);
    }

    static Map<String, Object> publicOnly(Jose.Jwk k) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (String f : List.of("kty", "crv", "n", "e", "x", "y", "kid", "alg")) {
            if (k.json().containsKey(f)) {
                m.put(f, k.json().get(f));
            }
        }
        return m;
    }
}
```

<!-- output:JwtAttackLab.java -->
```text

== Baseline: a legitimate RFC 9068 access token
  [PASS] L5 accepts it
  [PASS] L7 accepts it: sub=alice
  [PASS] L7 accepts an ES256 token under the ES256-pinned kid: sub=alice

== Twelve attacks (attacker holds NO private key of the issuer)
  1  alg=none, empty signature                                   L5 ACCEPTS | L7 rejects: alg none not the alg pinned to kid (RS256)
  2  alg=nOnE (case games around a blocklist)                    L5 ACCEPTS | L7 rejects: alg nOnE not the alg pinned to kid (RS256)
  3  RS256->HS256: HMAC keyed with the issuer's PUBLIC key PEM   L5 ACCEPTS | L7 rejects: unknown kid
  4  embedded 'jwk' header with the attacker's own key           L5 ACCEPTS | L7 rejects: header 'jwk' must never select the verification key
  5  'jku' pointing at an attacker-hosted JWKS                   L5 ACCEPTS | L7 rejects: header 'jku' must never select the verification key
  6  kid=../public/robots.txt (HMAC with a world-readable file)  L5 ACCEPTS | L7 rejects: unknown kid
  7  token with no exp at all (stolen = valid forever)           L5 ACCEPTS | L7 rejects: exp and iat are required
  8  aud=https://payments-sandbox.example.com (substring match)  L5 ACCEPTS | L7 rejects: aud https://payments-sandbox.example.com does not contain https://payments.example.com
  9  OIDC ID token (typ JWT, aud=client) replayed at the API     L5 ACCEPTS | L7 rejects: typ JWT != at+jwt
  10 RS256 token under the ES256-pinned kid (alg/key mismatch)   L5 ACCEPTS | L7 rejects: alg RS256 not the alg pinned to kid (ES256)
  11 replay with a non-canonical base64url signature             L5 ACCEPTS | L7 rejects: malformed: non-canonical base64url
  [PASS] ECDSA (r, n-s) is a second valid signature for the same token
  [PASS] L5(ES256) accepted the original token once
  12 replay via ECDSA malleability (s -> n-s)                    L5 ACCEPTS | L7 rejects: jti missing or replayed
  summary: L5 accepted 12 of 12, L7 rejected 12 of 12
  [PASS] L7 rejects all 12
  [PASS] L5 accepts all 12

== Psychic signatures (CVE-2022-21449): r = s = 0 for ES256
  [PASS] this JDK (25.0.4.1) rejects the all-zero ECDSA signature

== Offline dictionary attack on a weak HS256 secret (hashcat mode 16500 does this on GPUs)
  [PASS] secret recovered after 1338 guesses from ONE captured token: 'your-256-bit-secret'
  [PASS] a 256-bit random HS key is not in any wordlist (L7: asymmetric across trust boundaries anyway)

verdict: OK (10 checks)
```

---

## 6. Key rotation and JWKS caching

```mermaid
sequenceDiagram
    autonumber
    participant KMS as KMS / HSM
    participant IdP as Issuer
    participant J as JWKS endpoint
    participant RS as Resource servers (cache TTL T)
    KMS->>IdP: create K2 (non-exportable, sign-only)
    IdP->>J: publish {K1, K2}, still signing with K1
    Note over RS: wait >= T + skew so every cache holds K2
    IdP->>IdP: switch signing to K2 (kid = thumbprint(K2))
    Note over RS: tokens signed by K1 still valid for <= token TTL
    IdP->>J: retire K1 after token TTL + skew
    RS->>J: kid miss -> at most one refresh per 30 s (single flight), stale-if-error
```

The protocol follows from two inequalities [E, verified by L12]:

- **Switch** signing only after `t_publish + max cache TTL + skew`. Before then, some verifier has not seen K2.
- **Retire** K1 only after `t_switch + max token TTL + skew`. Before then, some valid token is still signed by K1.

Kid-miss refresh is an *optimisation* for the first inequality: it helps verifiers learn K2 early. It can never fix the second, because the *old* key is the one missing. That is why big-bang rotation still fails 3.4% of requests in L12 even with refresh. Without rate limiting, kid-miss refresh is also a denial-of-service amplifier: attacker-chosen kids become JWKS fetches 1:1 (L12 scenario C).

**Emergency rotation** (key compromise) inverts the trade-off. You *want* K1 gone everywhere now, and you accept that in-flight legitimate tokens fail. Exposure is bounded by the verifiers' cache TTL (L12: up to TTL − 1 s), so the levers are:
- a short JWKS cache TTL (minutes);
- a pushed invalidation event that makes every replica refetch;
- short access-token lifetimes;
- sender-constrained tokens (DPoP or mTLS, Folder 04), so a forged token is also useless without the client key.

**Key custody** [E]: generate signing keys inside a KMS or HSM as non-exportable, sign-only keys. The issuer calls `Sign` and never holds private-key bytes. Rotation is then a key-version change plus the JWKS protocol above. Log every `Sign` call and alert on any `Sign` from outside the issuer's identity.

<!-- listing:JwksRotation.java -->
```java
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * L12 - signing-key rotation and JWKS caching as a deterministic discrete-time simulation (1 s ticks).
 * One issuer, three resource-server replicas whose JWKS caches were filled at different moments, tokens with a
 * 300 s lifetime presented at 10 req/s per replica (ages 0..270 s). Scenarios: big-bang rotation (L5) with and
 * without kid-miss refresh, the publish/switch/retire protocol (L7), a random-kid refresh storm, and an emergency
 * key compromise with TTL-only caches vs pushed invalidation.
 */
public final class JwksRotation {
    static final int TOKEN_TTL = 300;
    static final int SKEW = 60;

    /** What the issuer publishes and which key it signs with, as a function of time. */
    interface Issuer {
        Set<String> published(int t);

        String signingKid(int t);
    }

    static final class Replica {
        final int cacheTtl;
        final boolean refreshOnKidMiss;
        final int minRefreshInterval;
        Set<String> cached;
        int fetchedAt;
        int lastAttempt = Integer.MIN_VALUE / 2;
        long fetches;

        Replica(int cacheTtl, boolean refreshOnKidMiss, int minRefreshInterval, int phase, Issuer iss) {
            this.cacheTtl = cacheTtl;
            this.refreshOnKidMiss = refreshOnKidMiss;
            this.minRefreshInterval = minRefreshInterval;
            this.fetchedAt = -phase;
            this.cached = iss.published(-phase);
        }

        void fetch(int t, Issuer iss) {
            cached = iss.published(t);
            fetchedAt = t;
            lastAttempt = t;
            fetches++;
        }

        boolean accepts(int t, String kid, Issuer iss) {
            if (t - fetchedAt >= cacheTtl) {
                fetch(t, iss);
            }
            if (cached.contains(kid)) {
                return true;
            }
            if (refreshOnKidMiss && t - lastAttempt >= minRefreshInterval) { // single-flight, rate-limited
                fetch(t, iss);
                return cached.contains(kid);
            }
            return false;
        }
    }

    record Result(long requests, long rejected, long fetches) {
    }

    /** Legitimate traffic: each second, each replica sees tokens of ages 0, 30, ..., 270 s. */
    static Result traffic(Issuer iss, int cacheTtl, boolean kidMiss, int minInterval, int from, int to) {
        List<Replica> rs = new ArrayList<>();
        for (int phase : new int[] {0, 300, 600}) {
            rs.add(new Replica(cacheTtl, kidMiss, minInterval, phase, iss));
        }
        long req = 0;
        long rej = 0;
        for (int t = from; t < to; t++) {
            for (Replica r : rs) {
                for (int age = 0; age < TOKEN_TTL; age += 30) {
                    req++;
                    if (!r.accepts(t, iss.signingKid(t - age), iss)) {
                        rej++;
                    }
                }
            }
        }
        return new Result(req, rej, rs.stream().mapToLong(r -> r.fetches).sum());
    }

    public static void main(String[] args) {
        final int rotateAt = 2_000;
        final int cacheTtl = 900; // e.g. Cache-Control: max-age=900 on the JWKS response

        KbSupport.section("A. Big-bang rotation (L5): at t=2000 the JWKS becomes {K2} and signing switches to K2");
        Issuer bigBang = new Issuer() {
            public Set<String> published(int t) {
                return t < rotateAt ? Set.of("K1") : Set.of("K2");
            }

            public String signingKid(int t) {
                return t < rotateAt ? "K1" : "K2";
            }
        };
        Result a = traffic(bigBang, cacheTtl, false, 0, 0, 4_000);
        KbSupport.info("TTL-only caches:            %,7d of %,d requests rejected (%.2f%%), %d JWKS fetches", a.rejected(), a.requests(),
                100.0 * a.rejected() / a.requests(), a.fetches());
        Result b = traffic(bigBang, cacheTtl, true, 30, 0, 4_000);
        KbSupport.info("plus kid-miss refresh:      %,7d of %,d requests rejected (%.2f%%), %d JWKS fetches", b.rejected(), b.requests(),
                100.0 * b.rejected() / b.requests(), b.fetches());
        KbSupport.check("kid-miss refresh fixes NEW-key tokens but not in-flight OLD-key tokens: still " + b.rejected() + " rejections",
                b.rejected() > 0 && b.rejected() < a.rejected());

        KbSupport.section("B. Publish -> wait -> switch -> wait -> retire (L7)");
        final int publishAt = rotateAt;
        final int switchAt = publishAt + cacheTtl + SKEW;            // every cache has seen K2
        final int retireAt = switchAt + TOKEN_TTL + SKEW;            // every K1 token has expired
        Issuer protocol = new Issuer() {
            public Set<String> published(int t) {
                Set<String> s = new LinkedHashSet<>();
                if (t < retireAt) {
                    s.add("K1");
                }
                if (t >= publishAt) {
                    s.add("K2");
                }
                return s;
            }

            public String signingKid(int t) {
                return t < switchAt ? "K1" : "K2";
            }
        };
        Result c = traffic(protocol, cacheTtl, false, 0, 0, 6_000);
        KbSupport.info("publish K2 at t=%d, sign with K2 at t=%d (+cacheTtl+skew), retire K1 at t=%d (+tokenTtl+skew)", publishAt, switchAt, retireAt);
        KbSupport.check("zero rejections even with TTL-only caches: " + c.rejected() + " of " + c.requests(), c.rejected() == 0);

        KbSupport.section("C. Refresh storm: attacker sends 5,000 req/s with random kids for 60 s at one replica");
        Issuer stable = new Issuer() {
            public Set<String> published(int t) {
                return Set.of("K1");
            }

            public String signingKid(int t) {
                return "K1";
            }
        };
        Replica naive = new Replica(cacheTtl, true, 0, 0, stable);    // refresh on EVERY unknown kid
        Replica guarded = new Replica(cacheTtl, true, 30, 0, stable); // at most one refresh per 30 s
        long naiveBefore = naive.fetches;
        long guardedBefore = guarded.fetches;
        for (int t = 100; t < 160; t++) {
            for (int k = 0; k < 5_000; k++) {
                String kid = "rand-" + t + "-" + k;
                naive.accepts(t, kid, stable);
                guarded.accepts(t, kid, stable);
            }
        }
        long nf = naive.fetches - naiveBefore;
        long gf = guarded.fetches - guardedBefore;
        KbSupport.info("JWKS fetches caused: naive %,d  vs  rate-limited single-flight %d", nf, gf);
        KbSupport.check("the naive replica turns the attacker's traffic 1:1 into load on the IdP", nf == 300_000);
        KbSupport.check("the guarded replica makes at most 2 extra fetches in 60 s", gf <= 2);

        KbSupport.section("D. Emergency: K1's private key leaks at t=3000; IdP drops K1 from the JWKS immediately");
        final int leak = 3_000;
        Issuer emergency = new Issuer() {
            public Set<String> published(int t) {
                return t < leak ? Set.of("K1", "K2") : Set.of("K2");
            }

            public String signingKid(int t) {
                return t < leak ? "K1" : "K2";
            }
        };
        for (int ttl : new int[] {86_400, 900, 300}) {
            int worst = 0;
            for (int off = 0; off < ttl; off += Math.max(1, ttl / 60)) { // cache filled 'off + 1' s before the leak
                Replica r = new Replica(ttl, false, 0, off + 1 - leak, emergency);
                int t = leak;
                while (r.accepts(t, "K1", emergency) && t < leak + 2 * 86_400) { // attacker's forged K1 token
                    t++;
                }
                worst = Math.max(worst, t - leak);
            }
            KbSupport.info("cache TTL %6d s: forged K1 tokens accepted for up to %6d s after the revocation", ttl, worst);
            if (ttl == 300) {
                KbSupport.check("TTL alone bounds exposure by the TTL itself (" + worst + " s at TTL 300)", worst <= 300 && worst >= 290);
            }
        }
        KbSupport.info("pushed invalidation (revocation event -> every replica refetches): exposure = propagation delay (~seconds)");
        Result e = traffic(emergency, 300, true, 30, 0, 4_000);
        KbSupport.check("legitimate in-flight K1 tokens are rejected too (" + e.rejected() + " requests): the price of an emergency rotation",
                e.rejected() > 0);
        KbSupport.verdict();
    }
}
```

<!-- output:JwksRotation.java -->
```text

== A. Big-bang rotation (L5): at t=2000 the JWKS becomes {K2} and signing switches to K2
  TTL-only caches:              9,090 of 120,000 requests rejected (7.58%), 13 JWKS fetches
  plus kid-miss refresh:        4,050 of 120,000 requests rejected (3.38%), 36 JWKS fetches
  [PASS] kid-miss refresh fixes NEW-key tokens but not in-flight OLD-key tokens: still 4050 rejections

== B. Publish -> wait -> switch -> wait -> retire (L7)
  publish K2 at t=2000, sign with K2 at t=2960 (+cacheTtl+skew), retire K1 at t=3320 (+tokenTtl+skew)
  [PASS] zero rejections even with TTL-only caches: 0 of 180000

== C. Refresh storm: attacker sends 5,000 req/s with random kids for 60 s at one replica
  JWKS fetches caused: naive 300,000  vs  rate-limited single-flight 2
  [PASS] the naive replica turns the attacker's traffic 1:1 into load on the IdP
  [PASS] the guarded replica makes at most 2 extra fetches in 60 s

== D. Emergency: K1's private key leaks at t=3000; IdP drops K1 from the JWKS immediately
  cache TTL  86400 s: forged K1 tokens accepted for up to  86399 s after the revocation
  cache TTL    900 s: forged K1 tokens accepted for up to    899 s after the revocation
  cache TTL    300 s: forged K1 tokens accepted for up to    299 s after the revocation
  [PASS] TTL alone bounds exposure by the TTL itself (299 s at TTL 300)
  pushed invalidation (revocation event -> every replica refetches): exposure = propagation delay (~seconds)
  [PASS] legitimate in-flight K1 tokens are rejected too (4050 requests): the price of an emergency rotation

verdict: OK (6 checks)
```

---

## 7. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

### 7.1 L5, in the two common shapes

```java
// L5 (a) - hand-rolled, from a tutorial. DO NOT USE.
DecodedJWT jwt = JWT.decode(token);                       // parse first, trust later
Algorithm alg = switch (jwt.getAlgorithm()) {             // the TOKEN chooses the algorithm (#1-#3)
    case "HS256" -> Algorithm.HMAC256(publicKeyPem);       // RSA public key as HMAC secret (#3)
    case "RS256" -> Algorithm.RSA256(publicKey, null);
    default -> Algorithm.none();                           // "be lenient" (#1)
};
alg.verify(jwt);
if (!jwt.getAudience().toString().contains("payments")) throw ...;   // substring aud (#8)

// L5 (b) - Spring, "it's just one line".
@Bean JwtDecoder jwtDecoder() {                              // RS256 only; createDefault(): typ JWT/absent,
    return NimbusJwtDecoder.withJwkSetUri(jwks).build();     // timestamps - NO iss, NO aud (L14 shows both)
}
```

### 7.2 L7 on Spring Security 7.1.2

Property-only configuration (Boot 4.1.2 metadata keys, verified in `spring-boot-security-oauth2-resource-server-4.1.2.jar`):

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://idp.example.com          # discovery + iss validation
          jwk-set-uri: https://idp.example.com/.well-known/jwks.json
          jws-algorithms: [ES256]                       # never leave it at the RS256-only default by accident
          audiences: [https://payments.example.com]     # adds the aud validator
```

Properties alone do not switch `typ` validation to `at+jwt`. For RFC 9068 tokens, define the decoder bean as L14 does:

<!-- listing:JwtSecurityConfig.java -->
```java
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.ECPrivateKey;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import com.nimbusds.jose.jwk.Curve;
import com.nimbusds.jose.jwk.ECKey;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.SecurityContext;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtValidationException;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.security.web.SecurityFilterChain;

/**
 * L14 - JWT issuing and validation on Spring Security 7.1.2 + Nimbus JOSE+JWT 10.9.1, hardened.
 *
 * <ul>
 *   <li>decoder: ES256 only (the builder default is RS256 only), RFC 9068 at+jwt validator with exact iss and aud;</li>
 *   <li>encoder: a JWK set holding the current and the next key; the kid in the header selects the signer;</li>
 *   <li>resource server: stateless, scope-based authorization.</li>
 * </ul>
 * main() runs the real Spring/Nimbus classes: what the defaults accept and reject, the hardened decoder, and
 * interop in both directions with the from-scratch L9 implementation.
 */
@Configuration(proxyBeanMethods = false)
@EnableWebSecurity
public class JwtSecurityConfig {

    static final String ISS = "https://idp.example.com";
    static final String AUD = "https://payments.example.com";

    /** Production wiring: JWKS fetched (and cached by Nimbus) from the issuer; nothing else is trusted. */
    @Bean
    JwtDecoder jwtDecoder() {
        NimbusJwtDecoder d = NimbusJwtDecoder.withJwkSetUri(ISS + "/.well-known/jwks.json")
                .jwsAlgorithm(SignatureAlgorithm.ES256)
                .build();
        d.setJwtValidator(JwtValidators.createAtJwtValidator().issuer(ISS).audience(AUD).build());
        return d;
    }

    @Bean
    SecurityFilterChain api(HttpSecurity http, JwtDecoder decoder) throws Exception {
        http
            .authorizeHttpRequests(a -> a
                .requestMatchers("/payments/**").hasAuthority("SCOPE_payments:write")
                .anyRequest().authenticated())
            .oauth2ResourceServer(o -> o.jwt(j -> j.decoder(decoder)))
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .csrf(c -> c.disable()); // bearer-token API: no ambient cookie credentials to forge
        return http.build();
    }

    /** Decoder over an in-memory JWK source (what withJwkSetUri does after fetching), hardened. */
    static NimbusJwtDecoder hardened(JWKSource<SecurityContext> src) {
        NimbusJwtDecoder d = NimbusJwtDecoder.withJwkSource(src).jwsAlgorithm(SignatureAlgorithm.ES256).build();
        d.setJwtValidator(JwtValidators.createAtJwtValidator().issuer(ISS).audience(AUD).build());
        return d;
    }

    static String mint(NimbusJwtEncoder enc, String kid, String typ, String iss, String aud, Instant iat, Duration ttl) {
        JwsHeader h = JwsHeader.with(SignatureAlgorithm.ES256).type(typ).keyId(kid).build();
        JwtClaimsSet c = JwtClaimsSet.builder().issuer(iss).subject("alice").audience(List.of(aud)).issuedAt(iat)
                .expiresAt(iat.plus(ttl)).id("jti-" + iat.toEpochMilli() + "-" + typ + "-" + aud.length())
                .claim("client_id", "mobile-app").claim("scope", "payments:write").build();
        return enc.encode(JwtEncoderParameters.from(h, c)).getTokenValue();
    }

    static String outcome(JwtDecoder d, String token) {
        try {
            Jwt jwt = d.decode(token);
            return "accepted (sub=" + jwt.getSubject() + ")";
        } catch (JwtValidationException e) {
            // mask the wall-clock instant in "Jwt expired at ..." so the captured output is reproducible
            return "rejected by validator: " + e.getErrors().iterator().next().getDescription()
                    .replaceAll("\\d{4}-\\d{2}-\\d{2}T[0-9:.]+Z", "<instant>");
        } catch (JwtException e) {
            return "rejected: " + e.getClass().getSimpleName();
        }
    }

    static ECKey ecKey(KeyPair kp) throws Exception {
        ECKey k = new ECKey.Builder(Curve.P_256, (ECPublicKey) kp.getPublic()).privateKey((ECPrivateKey) kp.getPrivate()).build();
        return new ECKey.Builder(k).keyID(k.computeThumbprint().toString()).algorithm(com.nimbusds.jose.JWSAlgorithm.ES256).build();
    }

    public static void main(String[] args) throws Exception {
        KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
        g.initialize(new ECGenParameterSpec("secp256r1"));
        ECKey current = ecKey(g.generateKeyPair());
        ECKey next = ecKey(g.generateKeyPair());
        JWKSource<SecurityContext> signing = new ImmutableJWKSet<>(new JWKSet(List.of(current, next)));
        JWKSource<SecurityContext> published = new ImmutableJWKSet<>(new JWKSet(List.of(current.toPublicJWK(), next.toPublicJWK())));
        NimbusJwtEncoder enc = new NimbusJwtEncoder(signing);
        Instant now = Instant.now();

        String at = mint(enc, current.getKeyID(), "at+jwt", ISS, AUD, now, Duration.ofMinutes(5));
        String idTok = mint(enc, current.getKeyID(), "JWT", ISS, "mobile-app", now, Duration.ofMinutes(5));
        String wrongAud = mint(enc, current.getKeyID(), "at+jwt", ISS, "https://payments-sandbox.example.com", now, Duration.ofMinutes(5));
        String wrongIss = mint(enc, current.getKeyID(), "at+jwt", "https://evil-idp.example", AUD, now, Duration.ofMinutes(5));
        String expired = mint(enc, current.getKeyID(), "at+jwt", ISS, AUD, now.minus(Duration.ofMinutes(20)), Duration.ofMinutes(5));
        String byNext = mint(enc, next.getKeyID(), "at+jwt", ISS, AUD, now, Duration.ofMinutes(5));

        KbSupport.section("Spring Security 7.1.2 defaults: NimbusJwtDecoder.withJwkSource(src).build()");
        NimbusJwtDecoder stock = NimbusJwtDecoder.withJwkSource(published).build();
        KbSupport.check("ES256 access token -> " + outcome(stock, at) + "  (builder default alg set is {RS256})",
                outcome(stock, at).startsWith("rejected"));
        NimbusJwtDecoder es256Only = NimbusJwtDecoder.withJwkSource(published).jwsAlgorithm(SignatureAlgorithm.ES256).build();
        KbSupport.check("with jwsAlgorithm(ES256) but default validators, the RFC 9068 token -> " + outcome(es256Only, at),
                outcome(es256Only, at).contains("typ"));
        KbSupport.check("... while an ID token (typ JWT, aud=mobile-app) -> " + outcome(es256Only, idTok) + ": no iss/aud check by default",
                outcome(es256Only, idTok).startsWith("accepted"));
        KbSupport.check("... and a wrong-audience at+jwt is rejected only by typ, never by aud: " + outcome(es256Only, wrongAud),
                outcome(es256Only, wrongAud).contains("typ"));

        KbSupport.section("Hardened: jwsAlgorithm(ES256) + JwtValidators.createAtJwtValidator().issuer(ISS).audience(AUD)");
        NimbusJwtDecoder hard = hardened(published);
        String[][] cases = {{"RFC 9068 access token", at}, {"same token, signed by the NEXT key (rotation)", byNext},
            {"OIDC ID token (typ JWT)", idTok}, {"aud=payments-sandbox", wrongAud}, {"iss=evil-idp", wrongIss},
            {"expired 15 min ago", expired}};
        int accepted = 0;
        for (String[] c : cases) {
            String o = outcome(hard, c[1]);
            accepted += o.startsWith("accepted") ? 1 : 0;
            KbSupport.info("%-46s -> %s", c[0], o);
        }
        KbSupport.check("exactly the two legitimate tokens pass (current key and next key)", accepted == 2
                && outcome(hard, at).startsWith("accepted") && outcome(hard, byNext).startsWith("accepted"));

        KbSupport.section("Interop with the from-scratch L9 implementation");
        Map<String, Object> pubJwk = new LinkedHashMap<>(current.toPublicJWK().toJSONObject());
        Jose.Jwk mine = Jose.Jwk.parse(pubJwk);
        Jose.Parts p = Jose.parse(at);
        KbSupport.check("L9 verifies the Spring/Nimbus-minted token (header " + MiniJson.write(p.header()).replace(current.getKeyID(), "<thumbprint>") + ")",
                Jose.rawVerify("ES256", mine, p.signingInput(), p.sig()));
        KbSupport.check("Nimbus's kid (RFC 7638 thumbprint) == L9's thumbprint of the same key", mine.thumbprint().equals(current.getKeyID()));
        Map<String, Object> privJwk = new LinkedHashMap<>(current.toJSONObject());
        privJwk.put("alg", "ES256");
        Jose.Jwk minePriv = Jose.Jwk.parse(privJwk);
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("alg", "ES256");
        h.put("typ", "at+jwt");
        h.put("kid", current.getKeyID());
        Map<String, Object> claims = new LinkedHashMap<>();
        claims.put("iss", ISS);
        claims.put("sub", "bob");
        claims.put("aud", AUD);
        claims.put("iat", now.getEpochSecond());
        claims.put("exp", now.getEpochSecond() + 300);
        claims.put("jti", "l9-minted");
        claims.put("client_id", "mobile-app"); // createAtJwtValidator requires sub, iat, jti and client_id
        String l9Token = Jose.sign(h, MiniJson.write(claims).getBytes(StandardCharsets.UTF_8), minePriv);
        KbSupport.check("Spring's hardened decoder accepts the L9-minted token: " + outcome(hard, l9Token), outcome(hard, l9Token).startsWith("accepted"));

        KbSupport.section("Algorithm coverage of org.springframework.security.oauth2.jose.jws.SignatureAlgorithm");
        String names = Arrays.stream(SignatureAlgorithm.values()).map(SignatureAlgorithm::getName).collect(Collectors.joining(" "));
        KbSupport.check("enum = " + names + "  (no EdDSA/Ed25519: needs a custom JWSKeySelector + Tink in Nimbus)",
                !names.contains("EdDSA") && !names.contains("Ed25519"));
        KbSupport.verdict();
    }
}
```

<!-- output:JwtSecurityConfig.java -->
```text

== Spring Security 7.1.2 defaults: NimbusJwtDecoder.withJwkSource(src).build()
  [PASS] ES256 access token -> rejected: BadJwtException  (builder default alg set is {RS256})
  [PASS] with jwsAlgorithm(ES256) but default validators, the RFC 9068 token -> rejected by validator: the given typ value needs to be one of [JWT]
  [PASS] ... while an ID token (typ JWT, aud=mobile-app) -> accepted (sub=alice): no iss/aud check by default
  [PASS] ... and a wrong-audience at+jwt is rejected only by typ, never by aud: rejected by validator: the given typ value needs to be one of [JWT]

== Hardened: jwsAlgorithm(ES256) + JwtValidators.createAtJwtValidator().issuer(ISS).audience(AUD)
  RFC 9068 access token                          -> accepted (sub=alice)
  same token, signed by the NEXT key (rotation)  -> accepted (sub=alice)
  OIDC ID token (typ JWT)                        -> rejected by validator: the given typ value needs to be one of [at+jwt, application/at+jwt]
  aud=payments-sandbox                           -> rejected by validator: The aud claim is not valid
  iss=evil-idp                                   -> rejected by validator: The iss claim is not valid
  expired 15 min ago                             -> rejected by validator: Jwt expired at <instant>
  [PASS] exactly the two legitimate tokens pass (current key and next key)

== Interop with the from-scratch L9 implementation
  [PASS] L9 verifies the Spring/Nimbus-minted token (header {"kid":"<thumbprint>","typ":"at+jwt","alg":"ES256"})
  [PASS] Nimbus's kid (RFC 7638 thumbprint) == L9's thumbprint of the same key
  [PASS] Spring's hardened decoder accepts the L9-minted token: accepted (sub=bob)

== Algorithm coverage of org.springframework.security.oauth2.jose.jws.SignatureAlgorithm
  [PASS] enum = RS256 RS384 RS512 ES256 ES384 ES512 PS256 PS384 PS512  (no EdDSA/Ed25519: needs a custom JWSKeySelector + Tink in Nimbus)

verdict: OK (9 checks)
```

### 7.3 L5 vs L7

| Concern | L5 | L7 |
|---|---|---|
| Algorithm choice | from the token header | pinned per key (`alg` in the JWK or in configuration); type fits family |
| Key source | header `jwk`/`jku`/`x5u`, `kid` as path, or one global key | local JWKS fetched from the configured issuer, rate-limited single-flight refresh |
| Token type | any JWT | `typ=at+jwt` (RFC 9068); ID tokens and logout tokens rejected at APIs |
| Claims | `exp` optional, `aud` substring, no `iss` | `iss` exact; `aud` element match; `exp`/`iat`/`sub`/`client_id`/`jti` required; skew ≤ 60 s; lifetime cap |
| Encoding | lenient base64, last-wins JSON | strict canonical base64url, I-JSON, size cap |
| Replay | none, or cache keyed on token bytes | `jti` cache until `exp` where replay matters; sender-constraining (Folder 04) |
| Signing keys | HS256 shared secret in config | ES256 (or PS256/RS256) in KMS/HSM, non-exportable; RFC 7638 kids; publish/switch/retire rotation |
| Confidentiality | PII in signed tokens | minimal claims; JWE (sign-then-encrypt) only where needed; MAC-first for CBC; `epk` on-curve check |

---

## 8. Real-world attack vectors & mitigations

### A1 · `alg: none` and algorithm downgrade

**Attack.** The attacker sets `{"alg":"none"}` (or `None`, `nOnE`) and an empty signature, editing claims at will. Libraries that let the header choose the algorithm accept it. This was the 2015 class of disclosures across many JWT libraries.
**Wire signature.** A token whose third segment is empty, or whose `alg` differs from what the issuer uses.
**Root cause.** Verification is dispatched on attacker-controlled input.
**Mitigation.** Pin the algorithm per key. Unsecured JWS is never acceptable for authorization (L10 #1–2).
**Detection.** Count tokens by header `alg` at the gateway. Anything outside the issuer's set is an attack.

### A2 · RS256 → HS256 key confusion (CVE-2015-9235 class)

**Attack.** The attacker signs an HS256 token using the issuer's **public** RSA key, in PEM or DER form, as the HMAC secret. A verifier that maps "the key" to whatever the header says verifies it [D: NVD CVE-2015-9235, jsonwebtoken < 4.2.2].
**Wire signature.** `alg: HS256` on an issuer that only signs asymmetrically.
**Root cause.** One "key" object usable for both MAC and signature verification, chosen by the header.
**Mitigation.** Key type must fit the algorithm family (`Jwk.fits`). Typed key objects. Never pass PEM text as a MAC key (L10 #3).
**Detection.** As A1. Also keep HMAC code paths absent from asymmetric-only services.

### A3 · Header-supplied keys: `jwk`, `jku`, `x5u`, `x5c` (CVE-2018-0114 class)

**Attack.** The attacker embeds their own public key in the `jwk` header, or points `jku` or `x5u` at a JWKS or certificate they host, and signs with the matching private key [D: NVD CVE-2018-0114, node-jose < 0.11.0]. A `jku` follower is also an SSRF primitive into your network.
**Wire signature.** Tokens carrying `jwk`/`jku`/`x5u`; outbound fetches from resource servers to unknown hosts.
**Root cause.** The token is allowed to say which key verifies it.
**Mitigation.** Keys come only from the configured issuer's JWKS. Reject those headers (L10 #4–5). Use egress allow-lists on verifiers.
**Detection.** Alert on any token carrying those headers. Egress logs from API pods.

### A4 · `kid` injection: path traversal, SQL injection, command injection

**Attack.** `kid` values such as `../../public/robots.txt`, `x' UNION SELECT 'secret`, or `/dev/null` steer the key lookup to a value the attacker knows, then HMAC-sign with it (L10 #6).
**Wire signature.** `kid` values containing `/`, `..`, quotes or shell metacharacters, or that are very long.
**Root cause.** `kid` is used as a file name or a query fragment.
**Mitigation.** `kid` is only a key into an in-memory map built from the JWKS. Validate its format (base64url thumbprint). Never use it for I/O.
**Detection.** WAF and gateway rules on the `kid` character set. Counts of unknown-kid rejections.

### A5 · Claim confusion: missing `exp`, substring `aud`, cross-JWT substitution

**Attack.**
- A token without `exp` is valid forever once stolen.
- `aud: payments-sandbox` passes `contains("payments")`.
- An OIDC **ID token**, whose audience is the client, is replayed as a bearer **access token** at an API that checks only the signature (L10 #7–9).

**Wire signature.** Tokens without `exp`; `typ: JWT` at APIs; unexpected `aud` values.
**Root cause.** The token's purpose and audience are not checked.
**Mitigation.** Required `exp`/`iat` and a lifetime cap. Exact `aud` element match against the resource indicator (RFC 8707, Folder 02). Distinct `typ` per token kind (RFC 8725 §3.11) with `at+jwt` enforced. In Spring, `createAtJwtValidator().issuer(..).audience(..)` (L14).
**Detection.** Rejection reasons by type; the rate of ID tokens presented at APIs.

### A6 · Psychic signatures and verifier implementation bugs (CVE-2022-21449)

**Attack.** An ECDSA signature with r = s = 0 verified as valid for **any** message and key on affected Java versions. Every ES256 JWT, WebAuthn assertion and TLS signature check was forgeable [D: NVD lists Java SE 17.0.2 and 18 as affected supported versions; the discoverer's write-up traces the bug to the Java 15 ECDSA rewrite].
**Wire signature.** ES256 signatures that are all zeros (64 bytes of 0x00), or with r or s outside [1, n−1].
**Root cause.** The verifier did not check the range of r and s.
**Mitigation.** Patch the JDK, and track JDK CPUs as security dependencies. Defence in depth: range-check r and s, and run conformance vectors (L9, L10) in CI so a regression in the crypto provider fails a build. L10 confirms that JDK 25.0.4.1 rejects the all-zero signature.
**Detection.** Alert on signatures with zero or out-of-range components. Keep a JDK version inventory.

### A7 · Weak HMAC secrets and offline cracking

**Attack.** One captured HS256 token is an offline oracle. GPU tools (hashcat mode 16500) test secret candidates at enormous rates. L10 finds jwt.io's default secret in 1,338 guesses on one CPU thread.
**Wire signature.** None: the attack is offline. Afterwards, attackers mint validly signed tokens with arbitrary claims.
**Root cause.** Human-chosen MAC keys, and MACs used across trust boundaries.
**Mitigation.** Asymmetric signatures across services. HS keys (same-service use only) of 256 random bits from a CSPRNG, stored in a secret manager and rotated.
**Detection.** Scan repositories, configuration and images for known example secrets. Monitor for tokens with unusual claim combinations.

### A8 · Replay and malleability

**Attack.** A bearer token is replayed. One-time tokens (magic links, DPoP proofs, step-up assertions) are replayed with a *different byte string* that still verifies: non-canonical base64url (L10 #11) or ECDSA (r, n−s) (#12). That defeats caches keyed on token bytes.
**Wire signature.** The same `jti` arriving twice; tokens differing only in the last base64 character or in the s value.
**Root cause.** Identity was derived from encoding rather than from the signed content.
**Mitigation.** Strict canonical base64url. `jti` replay caches until `exp`. Sender-constrained tokens (DPoP or mTLS, Folder 04) so replayed bearer tokens are useless without the key.
**Detection.** `jti` reuse metrics. Repeated `jti` from different client addresses.

### A9 · JWE pitfalls: RSA1_5, padding oracles, invalid curves, compression

**Attack.**
- **RSA1_5 key transport** gives a Bleichenbacher oracle when errors are distinguishable.
- **AES-CBC decrypt-before-MAC** is a padding oracle.
- **ECDH-ES `epk` points off the curve** leak the private key through small-subgroup confinement.
- **`zip: DEF` on attacker-influenced plaintext** creates a compression side channel and decompression bombs.

**Wire signature.** `alg: RSA1_5`; bursts of decryption errors with varying ciphertexts; `epk` coordinates not on P-256.
**Root cause.** Legacy algorithms are accepted, and validation order and error surfaces are wrong.
**Mitigation.** Pin `alg`/`enc` (RSA-OAEP-256 or ECDH-ES+A256KW with A256GCM). Check the MAC first and keep errors uniform (L11). Check `epk` is on the curve (L11). No compression. Cap `p2c` if PBES2 is ever accepted.
**Detection.** Rejection counts by `alg`/`enc`. Decryption-error rate per client.

### A10 · JWKS refresh storms and rotation outages

**Attack.**
- **Refresh storm:** a flood of tokens with random `kid`s makes every verifier refetch the JWKS, a DoS on the IdP amplified by your own fleet (L12 C: 300,000 fetches in 60 s from one replica).
- **Rotation outage:** a big-bang rotation by the operator, with no attacker involved, causes a 401 storm (7.6% of requests in L12 A).

**Wire signature.** JWKS endpoint QPS correlated with unknown-kid rejections; 401 spikes at rotation time.
**Root cause.** Unbounded kid-miss refresh. Rotation without the publish/switch/retire protocol.
**Mitigation.** Single-flight, rate-limited refresh (≤1 per 30 s) with stale-if-error and negative caching of unknown kids. The rotation protocol of §6, automated. A short TTL plus pushed invalidation for emergencies.
**Detection.** Dashboards for JWKS fetch rate, unknown-kid rate and 401 rate by `kid`. A rotation runbook with a canary verifier.

---

## 9. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · Ed25519, ES256 or RS256 for access tokens at 2M verifications per second on the JVM?</b></summary>

**Initial Prompt.** The platform team wants Ed25519 "because it's the fastest and most modern". You run Java 21/25 resource servers.

**L5 Textbook Answer.** "Ed25519: fastest signatures, small keys, deterministic, no nonce problems."

**How an Attacker Bypasses L5.** Not an attacker this time, but the outage and the bill:
- **Cost.** On JDK 25, SunEC verifies about 880 Ed25519 tokens per core per second (L13). At 2M/s that is about 2,300 cores of pure verification, versus about 90 cores for RS256.
- **Support.** Spring 7.1.2's `SignatureAlgorithm` enum has no EdDSA, so the team writes a custom `JWSKeySelector`, adds Tink to the classpath, and half the partner integrations still send `alg: EdDSA` while new libraries emit `Ed25519` (RFC 9864). The migration stalls, and someone "temporarily" accepts any of `{EdDSA, Ed25519, RS256}` without pinning per key.

**L7 Principal Defense.**
- **Decide on measured numbers for the runtime you operate** (L13: RS256 ≈21.7k/s, ES256 ≈1.5k/s, Ed25519 ≈0.9k/s verifies per core), not on C-library folklore.
- **Reduce the verification count architecturally:**
  - the gateway verifies the external token once and mints a short-lived internal token, or uses token exchange (Folder 05);
  - a bounded verified-token cache keyed by SHA-256(token) until `exp` serves repeats.
- **Then choose:**
  - ES256 for interop, size (569-character tokens vs 825) and FAPI 2.0 alignment, with the gateway absorbing verification cost;
  - RS256/PS256 if the hot path is verify-bound and token size is irrelevant;
  - Ed25519 only with RFC 9864 identifiers end to end and the library support verified.
- **In every case,** pin alg per key, and keep keys in KMS.

</details>

<details><summary><b>Q2 · Why is HS256 a bad idea for microservices, if HMAC-SHA-256 is cryptographically strong?</b></summary>

**Initial Prompt.** Twelve services validate tokens with a shared HS256 secret from the config server. Defend or replace it.

**L5 Textbook Answer.** "HMAC-SHA-256 is secure and fast. We rotate the secret yearly and keep it in Vault."

**How an Attacker Bypasses L5.**
- **Forgery from any compromise.** Compromising any one of the twelve services (an SSRF that reads its environment, a heap dump, a debug endpoint) yields the secret, and with it the ability to mint tokens for *all twelve*, with any `sub`, scope and role.
- **Rotation is hard.** It needs a synchronized redeploy, so it happens yearly.
- **Offline cracking.** If the secret was ever a human-chosen string, one captured token is an offline cracking oracle (L10: 1,338 guesses for jwt.io's default).

**L7 Principal Defense.**
- **A MAC key is a signing key.** HS256 collapses "can verify" into "can mint". Use asymmetric signatures: the issuer's private key lives in KMS/HSM as non-exportable, and services get only the public JWKS. A compromised service can then verify but not forge.
- **Rotation becomes publish/switch/retire** with no secret distribution (L12).
- **Keep HS256 only for same-service artefacts** (state, CSRF), with 256-bit CSPRNG keys.
- **Migration:** dual-verify during the switch window, pinned per kid. Never accept both algorithms for the same kid.

</details>

<details><summary><b>Q3 · Walk through RS256→HS256 key confusion and design the API that makes it impossible.</b></summary>

**Initial Prompt.** Explain the attack from the bytes up, then design the verifier interface.

**L5 Textbook Answer.** "Check that `alg` isn't HS256 if you expect RS256."

**How an Attacker Bypasses L5.** Blocklists lose. The attacker uses `HS384`, `HS512`, or casing games (L10 #2's `nOnE`). Or the check runs on one parse of the header while the library re-parses with last-wins JSON and sees a different `alg`. Then the "public" RSA key, serialized as PEM, becomes the HMAC key, and the attacker knows it because it is public (L10 #3).

**L7 Principal Defense.**
- **Make the dangerous state unrepresentable:**
  - typed keys (`RSAPublicKey` cannot be passed where a MAC secret is expected);
  - a verifier constructed with `{kid → (key, alg)}`;
  - an algorithm taken *from the key*, never from the header, with the header `alg` merely required to equal it.
- **Strict I-JSON** so there is one parse.
- **Spring:** `jwsAlgorithm(SignatureAlgorithm.ES256)` gives Nimbus's `JWSVerificationKeySelector` a fixed algorithm set, so a header saying HS256 finds no key.
- **CI:** test vectors for `none`, HS-with-public-key, alg/kid mismatch and duplicate-`alg` headers (L10).

</details>

<details><summary><b>Q4 · Our access tokens contain email and phone number. Should we use JWE?</b></summary>

**Initial Prompt.** Privacy review flagged PII in access tokens. Encrypt them?

**L5 Textbook Answer.** "Yes. Switch to JWE with RSA1_5 since our library supports it, and keep everything else the same."

**How an Attacker Bypasses L5.**
- **RSA1_5 gives a decryption oracle.** It invites Bleichenbacher-style attacks wherever error behaviour differs.
- **Encrypt-then-sign leaks and can be stripped.** It reveals who signed, and the signature can be replaced.
- **The data still leaks elsewhere.** Every resource server now holds the decryption key, so PII is still exposed wherever any API is compromised, and logs that capture decrypted claims leak it anyway.

**L7 Principal Defense.**
- **First, data minimization:** access tokens need `sub`, `client_id`, `scope`, `aud`, `exp` and `jti`. PII belongs behind the userinfo or profile API under its own authorization, not in a bearer artefact.
- **Second, token architecture:**
  - browsers never hold tokens (BFF, RFC 10017);
  - external clients get opaque tokens and the gateway introspects them (phantom token, Folder 05).
- **If a claim truly must travel confidentially to a specific recipient:**
  - nested sign-then-encrypt (`cty: JWT`);
  - `RSA-OAEP-256` or `ECDH-ES+A256KW` with `A256GCM`, pinned;
  - `epk` on-curve checks; MAC-first for CBC; no `zip` (L11);
  - encrypted to *that* recipient's key only.

</details>

<details><summary><b>Q5 · Design signing-key rotation for an IdP with 4,000 relying services, without a single 401.</b></summary>

**Initial Prompt.** Compliance requires 90-day rotation. Last time it caused a 20-minute outage.

**L5 Textbook Answer.** "Rotate at 2 a.m. when traffic is low; services refetch the JWKS on kid miss."

**How an Attacker Bypasses L5.** No attacker is needed: L12 shows big-bang rotation fails 7.6% of requests with TTL caches and still 3.4% with kid-miss refresh. In-flight tokens signed by the *old* key fail at verifiers that refreshed and no longer see it. Unbounded kid-miss refresh then becomes the DoS vector the attacker uses next quarter (L12 C).

**L7 Principal Defense.**
- **Make rotation a protocol, not an event:**
  1. publish K2 next to K1;
  2. wait for max JWKS cache TTL plus skew;
  3. switch signing;
  4. wait for max token TTL plus skew;
  5. retire K1.

  L12: zero rejections with TTL-only caches.
- **Automate the steps** from KMS key versions. Use thumbprint kids.
- **Publish the JWKS with an explicit `Cache-Control: max-age`,** so the wait is known.
- **Verifiers:** single-flight, rate-limited refresh with stale-if-error and negative caching.
- **Canary:** a synthetic verifier that validates new-key tokens before the switch.
- **Separate emergency rotation:** pushed invalidation plus a short TTL, accepting the in-flight failures L12 D counts.

</details>

<details><summary><b>Q6 · A token passes signature verification. List everything else you check, and why each matters.</b></summary>

**Initial Prompt.** Whiteboard the resource server's validation.

**L5 Textbook Answer.** "Signature, expiry, and maybe the issuer."

**How an Attacker Bypasses L5.** L10 lists the ways around a check of signature and expiry alone:
- an ID token for the client works as an access token (#9);
- a token for `payments-sandbox` works on production through substring audience matching (#8);
- a token with no `exp` never expires (#7);
- replays succeed (#11, #12).

**L7 Principal Defense.** The ordered policy of §5:
1. size cap;
2. strict segments, base64url and I-JSON;
3. no header-supplied keys;
4. `crit`;
5. `typ = at+jwt`;
6. kid from the local set;
7. alg pinned to the key and its type;
8. the signature;
9. `iss` exact;
10. `aud` element match against this resource's identifier;
11. `exp`/`iat` required, skew ≤ 60 s, lifetime cap, `nbf`;
12. `jti` replay where relevant;
13. then scope-to-authority mapping and authorization.

In Spring 7.1.2: `jwsAlgorithm(ES256)` plus `createAtJwtValidator().issuer(..).audience(..)`. It requires `exp`, `sub`, `iat`, `jti` and `client_id`, and `build()` insists that `iss` and `aud` are configured (L14 shows the default validator rejecting RFC 9068 tokens and accepting a wrong-audience ID token).

</details>

<details><summary><b>Q7 · How would you implement JWT verification for a payments API so that a JDK crypto bug can't take you down?</b></summary>

**Initial Prompt.** After CVE-2022-21449, the CISO asks what you changed.

**L5 Textbook Answer.** "We upgraded the JDK."

**How an Attacker Bypasses L5.** The next provider regression, or a backport that misses a check, silently re-opens forgery. Nothing in the pipeline would notice, because the tests only feed valid tokens.

**L7 Principal Defense.**
- **Treat the crypto provider as a dependency with its own conformance suite in CI:**
  - positive RFC vectors (L9: RFC 7515, RFC 8037, RFC 7638);
  - negative vectors: all-zero ECDSA, out-of-range r and s, wrong-curve points, `none`, key confusion (L10);
  - run against the *production* JDK image, so a provider change fails the build.
- **Range-check ECDSA r and s,** and reject non-canonical encodings, before calling the provider.
- **Defence in depth:**
  - sender-constrained tokens (DPoP or mTLS), so a forged bearer token is not enough;
  - short lifetimes;
  - anomaly detection on token claims.
- **Patch SLA for JDK CPUs** as security releases, and keep an inventory of JDK builds by service.

</details>

<details><summary><b>Q8 · A partner sends `jku` in their tokens and insists we honour it. What do you do?</b></summary>

**Initial Prompt.** The partner rotates keys often and says `jku` is "in the standard".

**L5 Textbook Answer.** "It's standard, so fetch the keys from the URL in the header and cache them."

**How an Attacker Bypasses L5.** Anyone can mint a token whose `jku` points to their own JWKS, so the attacker picks the key (L10 #5). The fetch is also SSRF from your API tier into internal metadata endpoints. An allow-list of URL prefixes is bypassed by open redirects on the partner's domain or by parser quirks in URL matching.

**L7 Principal Defense.**
- **Bind the trust at onboarding, not at runtime:** each partner issuer gets a registered, fixed JWKS URI (or OIDC/OAuth metadata discovery from a registered issuer identifier) in your configuration.
- **Ignore `jku` and `x5u` for key selection** (L10).
- **Fetch from the registered URI** through an egress proxy with an exact allow-list, a TLS-pinned or validated chain, size limits, rate-limited single-flight refresh and stale-if-error.
- **Accept the partner's frequent rotation** through kid-miss refresh against *their registered* JWKS.
- **Contract:** the partner follows publish/switch/retire (§6).

</details>

<details><summary><b>Q9 · Post-quantum: what changes for JWTs, and what do you do now?</b></summary>

**Initial Prompt.** The board asks about "harvest now, decrypt later" and quantum risk to tokens.

**L5 Textbook Answer.** "Switch JWT signing to ML-DSA once libraries support it."

**How an Attacker Bypasses L5.**
- **Signatures don't need urgency.** Harvest-now-decrypt-later threatens *encrypted* data, such as JWE and TLS-protected payloads, while a signature only has to resist forgery during the token's validity window. Short-lived tokens make signature migration far less urgent than confidentiality.
- **Size breaks plumbing.** ML-DSA-44 produces 3,710-character JWTs (L13). Many gateways and servers cap total request headers near 8 kB, and cookies carrying such tokens break.
- **Mixed algorithms invite confusion.** A "hybrid" rollout that accepts any algorithm opens the confusion attacks of §8.

**L7 Principal Defense.**
- **Prioritize by data lifetime:**
  - confidentiality first: TLS with hybrid ML-KEM key exchange, and JWE key agreement for long-lived secrets;
  - signatures later, starting with long-lived artefacts (CA roots, software signing, long-validity assertions).
- **For access tokens:**
  - keep lifetimes short;
  - keep the verify path pluggable, with alg pinned per key so a new alg is a new key, not a new code path;
  - measure (ML-DSA-44 verifies at about 14.6k/s per core on JDK 25, faster than ES256, but its signatures are 38× bigger);
  - plan reference or opaque tokens at the edge, where size matters;
  - track the IETF JOSE/COSE ML-DSA registrations and use only fully specified identifiers (the RFC 9864 principle).

</details>

<details><summary><b>Q10 · Two teams' JSON parsers disagree on a token. Why is that a vulnerability, and how do you fix the class?</b></summary>

**Initial Prompt.** A gateway (Go) and the API (Java) parse the same JWT claims differently in a pentest.

**L5 Textbook Answer.** "JSON is a standard; both parsers are fine; ignore it."

**How an Attacker Bypasses L5.** Duplicate members: `{"sub":"alice","sub":"admin"}` or `{"alg":"RS256","alg":"none"}`. If the gateway authorizes on the first value and the API acts on the last (or vice versa), the attacker gets authorization from one and identity from the other. The same holds for big-number precision, Unicode escapes, lone surrogates and comment handling.

**L7 Principal Defense.**
- **One parse, one meaning.**
  - Verify the signature over the *received bytes*.
  - Parse with a strict I-JSON parser that rejects duplicates, lone surrogates and trailing data (L6), with depth and size caps.
  - Pass the *parsed, validated* claims downstream, or a freshly minted internal token, never the raw string to be parsed again.
- **Test the class:** fuzz the gateway and the API with differential corpora (duplicate keys, number edge cases) and assert identical verdicts.
- **Same discipline elsewhere:** WebAuthn's `clientDataJSON` (file 02, L7's duplicate-`origin` test).

</details>

<details><summary><b>Q11 · We need to revoke a compromised signing key now. Walk me through the first 15 minutes.</b></summary>

**Initial Prompt.** The KMS audit shows `Sign` calls on the token key from an unknown principal.

**L5 Textbook Answer.** "Rotate to a new key and remove the old one from the JWKS."

**How an Attacker Bypasses L5.** Removing K1 from the JWKS does nothing for verifiers whose caches still hold it. With a 24 h `max-age`, forged tokens are accepted for up to a day (L12 D: 86,399 s). The attacker's tokens carry admin scopes and long `exp` values. Nobody revoked the attacker's KMS access, so they sign with K2 next.

**L7 Principal Defense.**
- **Minute 0–5, contain the signer:** revoke the principal's KMS grant, disable K1's key version, and confirm through the KMS audit log that `Sign` calls stop.
- **Minute 5–10, push invalidation:**
  - emit a key-revocation event that makes every verifier drop K1 and refetch;
  - deploy a temporary verifier rule rejecting `kid=K1` and any token with `iat` before the incident window;
  - publish a JWKS without K1.
- **Minute 10–15, restore issuance:** switch to K2, which already exists if you follow §6's always-two-keys policy, and force re-issuance by revoking refresh tokens for affected clients (Folder 02).
- **Afterwards:**
  - forensics on tokens minted by the rogue principal (KMS logs give message digests);
  - shorten the JWKS TTL;
  - add sender-constraining so stolen *tokens* are also useless.

</details>

<details><summary><b>Q12 · Explain DER vs raw ECDSA signatures in JOSE, and the production bug it causes.</b></summary>

**Initial Prompt.** Tokens signed by a KMS-backed signer fail verification in one of three services.

**L5 Textbook Answer.** "Probably clock skew. Increase the leeway."

**How an Attacker Bypasses L5.** A cloud KMS `Sign` API typically returns ECDSA signatures DER-encoded [E]. JWS requires a fixed-length raw r‖s (RFC 7518 §3.4). Teams fix one service by making it "accept both encodings", and so create two valid byte representations per token, which defeats byte-keyed replay caches and deduplication (the same class as L10 #11–12). Lax DER parsers that accept non-minimal encodings add more variants.

**L7 Principal Defense.**
- **Convert DER to fixed-length raw at the issuer,** left-padding r and s to the curve size: 32 bytes each for P-256, 66 for P-521 (L9 checks 64 and 132 bytes).
- **Verifiers accept only raw** (`SHA256withECDSAinP1363Format`) with exact length checks.
- **Key replay and dedup on `jti`.**
- **Add an interop test in CI:** mint through the real KMS path and verify with an independent implementation (L14 does Spring/Nimbus ↔ L9 in both directions).
- **Never tune clock skew to explain away signature failures:** those are separate failure classes with separate metrics.

</details>

---

## 10. Invariants checklist

- [ ] Asymmetric signatures (ES256 default; PS256/RS256 where verify-bound; Ed25519 only with RFC 9864 ids end to end); no HS256 across services.
- [ ] Signing keys generated non-exportable in KMS/HSM; RFC 7638 thumbprint kids; every `Sign` call logged and alerted on unknown principals.
- [ ] Verifier key set built only from the configured issuer's JWKS; `jwk`/`jku`/`x5u`/`x5c` never select keys; egress allow-listed.
- [ ] `alg` pinned per key and key type checked against the algorithm family; the header `alg` must equal the pinned value.
- [ ] Strict parsing: size cap, exactly 3 (JWS) or 5 (JWE) segments, canonical base64url, I-JSON with duplicate rejection.
- [ ] `typ=at+jwt` for access tokens; distinct `typ` per token kind; ID tokens rejected at APIs.
- [ ] `iss` exact; `aud` element match against this resource; `exp`, `iat`, `sub`, `client_id`, `jti` required; skew ≤ 60 s; lifetime cap.
- [ ] In Spring 7.1.2: `jwsAlgorithm(...)` set explicitly, and `createAtJwtValidator().issuer(..).audience(..)` on the decoder. With mTLS-bound tokens, wrap it as `createDefaultWithValidators([JwtTypeValidator("at+jwt"), atJwt])` (Folder 07 file 03).
- [ ] Replay and dedup keyed on `jti`, never on token bytes; sender-constraining for high-value APIs.
- [ ] ECDSA signatures raw r‖s with exact length; r and s range-checked; DER conversion only at the issuer.
- [ ] JWE only for real confidentiality needs: sign-then-encrypt, pinned `alg`/`enc`, no RSA1_5, MAC-first CBC, `epk` on-curve check, no `zip`.
- [ ] Rotation = publish → wait (cache TTL + skew) → switch → wait (token TTL + skew) → retire, automated, two keys always published.
- [ ] JWKS refresh: single-flight, ≤ 1 per 30 s per verifier, stale-if-error, negative caching; JWKS served with an explicit `max-age`.
- [ ] Emergency path: pushed key invalidation reaching all verifiers in seconds; runbook rehearsed.
- [ ] CI conformance: RFC vectors and negative attack vectors run against the production JDK image and wiring.

---

## 11. References

Specifications (RFC texts in [`fixtures/`](fixtures/), fetched 2026-11-05):
- RFC 7515 *JWS* — <https://www.rfc-editor.org/rfc/rfc7515> · RFC 7516 *JWE* — <https://www.rfc-editor.org/rfc/rfc7516> · RFC 7517 *JWK* — <https://www.rfc-editor.org/rfc/rfc7517>
- RFC 7518 *JWA* — <https://www.rfc-editor.org/rfc/rfc7518> · RFC 7519 *JWT* — <https://www.rfc-editor.org/rfc/rfc7519> · RFC 7638 *JWK Thumbprint* — <https://www.rfc-editor.org/rfc/rfc7638>
- RFC 8037 *CFRG curves in JOSE* — <https://www.rfc-editor.org/rfc/rfc8037> · RFC 9864 *Fully-Specified Algorithms for JOSE and COSE* — <https://www.rfc-editor.org/rfc/rfc9864>
- RFC 8725 *JSON Web Token Best Current Practices* — <https://www.rfc-editor.org/rfc/rfc8725> · RFC 9068 *JWT Profile for OAuth 2.0 Access Tokens* — <https://www.rfc-editor.org/rfc/rfc9068>
- RFC 8032 *EdDSA* — <https://www.rfc-editor.org/rfc/rfc8032> · RFC 6979 *Deterministic ECDSA* — <https://www.rfc-editor.org/rfc/rfc6979> · RFC 8707 *Resource Indicators* — <https://www.rfc-editor.org/rfc/rfc8707>
- NIST FIPS 204 *ML-DSA* — <https://csrc.nist.gov/pubs/fips/204/final>
- IANA JOSE registry — <https://www.iana.org/assignments/jose/jose.xhtml>

Vulnerabilities (NVD, read 2026-11-05) and write-ups:
- CVE-2015-9235 — <https://nvd.nist.gov/vuln/detail/CVE-2015-9235> · CVE-2018-0114 — <https://nvd.nist.gov/vuln/detail/CVE-2018-0114> · CVE-2022-21449 — <https://nvd.nist.gov/vuln/detail/CVE-2022-21449>
- Tim McLean, *Critical vulnerabilities in JSON Web Token libraries* (2015) — <https://auth0.com/blog/critical-vulnerabilities-in-json-web-token-libraries/>
- Neil Madden, *Psychic Signatures in Java* (2022) — <https://neilmadden.blog/2022/04/19/psychic-signatures-in-java/>
- PortSwigger Web Security Academy, *JWT attacks* — <https://portswigger.net/web-security/jwt>

Libraries:
- Spring Security resource server, JWT — <https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html>
- Nimbus JOSE+JWT — <https://connect2id.com/products/nimbus-jose-jwt>
- JDK 25 security algorithm names (`SHA256withECDSAinP1363Format`, `ML-DSA`) — <https://docs.oracle.com/en/java/javase/25/docs/specs/security/standard-names.html>
