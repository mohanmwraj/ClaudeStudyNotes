# Identity & Security L7 Reference: AuthN, AuthZ, OAuth 2.1, OIDC, FAPI 2.0, Zero-Trust and Cloud IAM

A Principal/Staff-level (FAANG / FinTech L7) reference and interview playbook for authentication and authorization. It starts at the cryptography and wire formats and goes up through OAuth 2.1, OpenID Connect, FAPI 2.0 high-security profiles, zero-trust service identity, fine-grained authorization engines and cloud IAM.

Every file follows the same spine:
1. first-principles protocol and cryptographic mechanics (wire bytes, JOSE/CBOR structures, sequence diagrams, threat models);
2. the vulnerable L5 implementation vs the hardened L7 zero-trust implementation, with Java 21+ / Spring Security code;
3. real-world attack vectors, each with **Attack / Wire signature / Root cause / Mitigation / Detection**;
4. bar-raiser chains: **Initial Prompt → L5 Textbook Answer → How an Attacker Bypasses L5 → L7 Principal Defense**;
5. an invariants checklist;
6. references.

## Status

| # | Folder | Files | Words | Listings | Chains | State |
|---|---|---|---|---|---|---|
| 01 | [01-First-Principles-AuthN-Cryptography-and-Passkeys](01-First-Principles-AuthN-Cryptography-and-Passkeys/) | 3 | 56.6k | 15 | 36 | **done, gated incl. 58/58 URLs** (2026-11-05) |
| 02 | 02-OAuth2-to-OAuth21-Protocol-Mechanics-and-Grant-Flows | 4 | — | — | — | next |
| 03 | 03-OpenID-Connect-OIDC-Identity-Federation-and-Lifecycle | 3 | — | — | — | planned |
| 04 | 04-High-Security-OAuth-FAPI2-DPoP-mTLS-and-PAR | 3 | — | — | — | planned |
| 05 | 05-Microservices-Zero-Trust-Propagation-and-Authorization-Engines | 4 | — | — | — | planned |
| 06 | 06-Cloud-Security-Equivalents-AWS-GCP-Azure-and-AI-Agents | 3 | — | — | — | planned |
| 07 | 07-Production-Java21-Spring-Security-and-Keycloak-Blueprints | 4 | — | — | — | planned |
| 08 | 08-Attack-Playbook-GitHub-References-and-L7-Bar-Raiser-QA | 3 | — | — | — | planned |

Folder names follow the repository blueprint in the brief. The brief's role section abbreviates two of them, as `01-First-Principles-AuthN-Crypto-and-Sessions/` and `08-Curated-Codebases-and-L7-Bar-Raiser-Playbook/`; the blueprint names are used. The brief asked for `### FILE:` headers in chat so the files could be extracted. Here the files are written straight to disk instead.

## Folder 01: First principles, AuthN cryptography and passkeys

| File | Covers | Listings |
|---|---|---|
| [01 · AuthN physics: passwords, Argon2id, MFA/TOTP, session vs token state](01-First-Principles-AuthN-Cryptography-and-Passkeys/01-authn-physics-passwords-argon2id-mfa-totp-and-session-vs-token-state.md) | NIST SP 800-63B-4 vocabulary and AALs; Argon2 internals (H0, lanes and slices, BlaMka, indexing, Argon2id hybrid); attacker bandwidth model; Spring Security 7.1.2 password storage (defaults, strict rehash, pepper as encryption, bcrypt's 72-byte cliff, upgrade-on-login, enumeration timing); HOTP/TOTP math, replay vs relay, lockout; sessions vs JWTs, cookie prefixes, fixation, AAL timeouts, step-up, revocation latency, DBSC | L0 `KbSupport`, L1 `Argon2id`, L2 `PasswordStorageL7`, L3 `Totp`, L4 `SessionTokenState`, L5 `AuthnSecurityConfig` |
| [02 · WebAuthn / FIDO2 passkeys: challenges and origin binding](01-First-Principles-AuthN-Cryptography-and-Passkeys/02-webauthn-fido2-passkeys-public-key-challenges-and-origin-binding.md) | Why origin binding defeats phishing; authenticator data, COSE and CBOR byte layouts; the registration and authentication ceremonies step by step; attestation formats and policy; synced vs device-bound passkeys and NIST; RP ID scope and related origins; L3 signal APIs; Spring Security 7.1.2 passkeys and the two gaps found | L6 `MiniJson`, L7 `WebAuthnRp`, L8 `PasskeySecurityConfig` |
| [03 · JOSE and JWT internals: JWS, JWE, JWK, Ed25519 vs ES256 vs RS256, key rotation](01-First-Principles-AuthN-Cryptography-and-Passkeys/03-jose-and-jwt-internals-jws-jwe-jwk-ed25519-es256-rs256-and-key-rotation.md) | Compact serialization bytes; header and claim security; RFC 9068 `at+jwt`; HS vs RS vs PS vs ES vs EdDSA vs ML-DSA math and measured JVM cost; JWK, thumbprints, alg pinning; JWE modes and pitfalls; verification as policy (RFC 8725); the rotation protocol and JWKS caching; Spring/Nimbus defaults vs hardened | L9 `Jose`, L10 `JwtAttackLab`, L11 `JweLab`, L12 `JwksRotation`, L13 `SigBench`, L14 `JwtSecurityConfig` |

**Verified results worth reusing in later folders:**

- **Oracles reproduced** (from the RFC and W3C texts in [`fixtures/`](01-First-Principles-AuthN-Cryptography-and-Passkeys/fixtures/)):
  - RFC 9106 Argon2d/i/id (H0 and tags) and RFC 7693 BLAKE2b;
  - all RFC 4226/6238 HOTP/TOTP rows;
  - all 15 W3C WebAuthn L3 §16 vector pairs and all 168 HKDF derivations;
  - RFC 7515 HS256 and RS256 and RFC 8037 Ed25519 signatures reproduced exactly; RFC 7515 ES256/ES512 verified;
  - RFC 7638 and RFC 8037 thumbprints;
  - RFC 7516 A.1/A.3 decryption and the RFC 7518 App. C ECDH-ES key.
- **Spring Security 7.1.2 findings** (read in source, then exercised on the real classes):
  - `{argon2}` = m 4 MiB, t 3; the v5_8 defaults are m 16 MiB, t 2 (below OWASP's 19 MiB);
  - Argon2 `upgradeEncoding` ignores a variant downgrade;
  - bcrypt `matches()` accepts any suffix beyond 72 bytes;
  - MFA factor merge needs a *declared* `toBuilder()`;
  - WebAuthn UV defaults to `preferred`, yet `FACTOR_WEBAUTHN` is granted regardless;
  - **the WebAuthn clone check compares against the registration-time counter, and a cloned key's lower counter is accepted and stored** (also present in 7.2.0-RC1's source);
  - `NimbusJwtDecoder` builders default to RS256 only and a validator that rejects `at+jwt` and checks neither `iss` nor `aud`;
  - no EdDSA in `SignatureAlgorithm`.
- **Measured on JDK 25, one core:**
  - Argon2id at the OWASP floor ≈ 36 ms;
  - verifications/s: RS256 ≈ 21.7k, ES256 ≈ 1.5k, Ed25519 ≈ 0.9k, ML-DSA-44 ≈ 14.6k (a 3,710-character JWT).
- **Simulated:**
  - big-bang key rotation rejects 7.6% of requests, and still 3.4% with kid-miss refresh, while publish/switch/retire rejects none;
  - revocation latency runs from 0 s (session) and 2 s (pushed denylist) to 3,000 s (a 60-minute JWT).

## How the code is verified

All listings in a folder compile as one unit with `javac --release 21 -Xlint:all -Werror` on Temurin JDK 25.0.4.1. The classpath is a set of jars SHA-1-checked against Maven Central:
- Spring Security 7.1.2;
- Spring Framework 7.0.10;
- BouncyCastle 1.86;
- Nimbus JOSE+JWT 10.9.1;
- webauthn4j 0.31.10;
- Jackson 3.2.1.

Each listing ends with a `verdict: OK (n checks)` line. The folder gate:
1. re-extracts every listing from the Markdown, recompiles it and re-runs it, requiring byte-identical `output` blocks;
2. re-runs the benchmark `measured-output` blocks in quick mode;
3. checks the spine, the attack and chain formats, the JSON/YAML/HTTP blocks, the Mermaid headers, and every relative and external link.

To run a listing yourself (Windows paths shown; any JDK 21+ works for all but the ML-DSA rows):

```text
javac --release 21 -d out -cp "<jars>/*" 01-First-Principles-AuthN-Cryptography-and-Passkeys/*.java   (after extracting the listings)
java -cp "out;<jars>/*" WebAuthnRp 01-First-Principles-AuthN-Cryptography-and-Passkeys/02-webauthn-fido2-passkeys-public-key-challenges-and-origin-binding.md
```

## Conventions

- Labels: **[D]** documented in a spec, a shipped source file or NVD · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.
- Versions are pinned as of 2026-11-05:
  - Spring Security 7.1.2 / Boot 4.1.2 / Framework 7.0.10;
  - W3C WebAuthn Level 3 (Recommendation, 25 Aug 2026);
  - NIST SP 800-63B-4 (final);
  - RFC 9700 (OAuth 2.0 Security BCP);
  - RFC 10017 (Browser-Based Apps BCP 212, Aug 2026);
  - RFC 9864 (fully specified JOSE/COSE algorithms);
  - OAuth 2.1, still an Internet-Draft (draft-ietf-oauth-v2-1-17, 2026-10-31, per the IETF Datatracker).
- Composite "L5" code samples are illustrations of review findings, not code from any one system.
