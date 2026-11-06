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
| 02 | [02-OAuth2-to-OAuth21-Protocol-Mechanics-and-Grant-Flows](02-OAuth2-to-OAuth21-Protocol-Mechanics-and-Grant-Flows/) | 4 | 29.3k | 5 | 40 | **done, gated incl. URLs** (2026-11-06) |
| 03 | [03-OpenID-Connect-OIDC-Identity-Federation-and-Lifecycle](03-OpenID-Connect-OIDC-Identity-Federation-and-Lifecycle/) | 3 | 25.5k | 6 | 30 | **done, gated incl. 34/34 URLs** (2026-11-06) |
| 04 | [04-High-Security-OAuth-FAPI2-DPoP-mTLS-and-PAR](04-High-Security-OAuth-FAPI2-DPoP-mTLS-and-PAR/) | 3 | 32.6k | 8 | 30 | **done, gated incl. 26/26 URLs** (2026-11-06) |
| 05 | [05-Microservices-Zero-Trust-Propagation-and-Authorization-Engines](05-Microservices-Zero-Trust-Propagation-and-Authorization-Engines/) | 4 | 25.9k | 8 | 36 | **done, gated incl. 21/21 URLs** (2026-11-06) |
| 06 | [06-Cloud-Security-Equivalents-AWS-GCP-Azure-and-AI-Agents](06-Cloud-Security-Equivalents-AWS-GCP-Azure-and-AI-Agents/) | 3 | 15.2k | 4 | 24 | **done, gated incl. 24/24 URLs** (2026-11-06) |
| 07 | [07-Production-Java21-Spring-Security-and-Keycloak-Blueprints](07-Production-Java21-Spring-Security-and-Keycloak-Blueprints/) | 4 | 19.3k | 4 | 34 | **done, gated incl. 25/25 URLs** (2026-11-06) |
| 08 | [08-Attack-Playbook-GitHub-References-and-L7-Bar-Raiser-QA](08-Attack-Playbook-GitHub-References-and-L7-Bar-Raiser-QA/) | 3 | 19.2k | 1 | 52 | **done, gated incl. 103/103 URLs** (2026-11-06) |
| | **Total** | **27** | **~224k** | **51** | **282** | **all 8 folders gated** |

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

## Folder 02: OAuth 2.0 → OAuth 2.1 protocol mechanics and grant flows

| File | Covers | Listings |
|---|---|---|
| [01 · Roles, threat model, what OAuth 2.1 and RFC 9700 changed](02-OAuth2-to-OAuth21-Protocol-Mechanics-and-Grant-Flows/01-oauth2-roles-threat-model-and-what-oauth21-and-rfc9700-changed.md) | Roles and channels; removed and hardened features (implicit, ROPC, `plain`, query bearer, `redirect_uri` in the token request); PKCE for confidential clients; exact redirect matching; client authentication ranking; Spring AS/client/Boot defaults and the PKCE interop trap | L15 `RedirectUriLab` |
| [02 · Authorization code + PKCE S256 and code-injection defense](02-OAuth2-to-OAuth21-Protocol-Mechanics-and-Grant-Flows/02-authorization-code-flow-with-pkce-s256-and-authorization-code-injection-defense.md) | The flow on the wire; what `state`, PKCE, `nonce` and `iss` each bind; RFC 9700 attacker models; 8 attacks (interception, injection, downgrade, `plain`, replay, login CSRF, mix-up, redirect traversal); Spring enforcement details | L16 `AuthCodePkceLab` |
| [03 · Refresh-token rotation, reuse detection, grace periods, RFC 7009](02-OAuth2-to-OAuth21-Protocol-Mechanics-and-Grant-Flows/03-refresh-token-rotation-reuse-detection-grace-periods-and-revocation-rfc7009.md) | Families, rotation and reuse detection, key-bound grace windows, DPoP-bound tokens, RFC 10017 lifetimes, revocation and introspection on the wire; Spring Authorization Server's real behaviour and a fix | L17 `RefreshRotationLab`, L18 `SasRefreshTokenLab` |
| [04 · Client credentials, device grant (RFC 8628), CIBA](02-OAuth2-to-OAuth21-Protocol-Mechanics-and-Grant-Flows/04-client-credentials-device-code-rfc8628-and-ciba-decoupled-authentication.md) | `private_key_jwt` and the 2025 audience-injection vulnerability (rfc7523bis); user-code entropy vs live codes; device-code phishing (Storm-2372); CIBA modes, `binding_message`, `user_code` | L19 `MachineFlowsLab` |

**Verified results:**
- **Redirect matching:** L5 matchers are wrong in 4–10 of 15 cases; exact match with the loopback-port exception is wrong in none.
- **Code flow:** L5 loses all 8 attacks and L7 blocks all 8. The PKCE downgrade succeeds against a PKCE-using client when the AS ignores verifiers for challenge-less codes.
- **Spring Authorization Server 7.1.2, run in-process:**
  - `reuseRefreshTokens(true)` by default, i.e. no rotation;
  - with rotation on, a rotated-out token is only `invalid_grant` and the family is not revoked, so an attacker who refreshes first keeps the grant;
  - a 60-line decorator adds family revocation.
- **Spring defaults (source):**
  - the AS requires S256 PKCE for every client, but the OAuth2 client sends PKCE for confidential clients only if `ClientSettings.requireProofKey(true)`, which Boot never sets;
  - `NimbusJwtClientAuthenticationParametersConverter` defaults `aud` to the token URI (pre-rfc7523bis).
- **Device grant:** 200k live codes + 1M unthrottled guesses → 99.96% hit.

## Folder 03: OpenID Connect, identity federation and lifecycle

| File | Covers | Listings |
|---|---|---|
| [01 · OIDC Core: ID token vs access token, UserInfo, Discovery, `at_hash`/`c_hash`](03-OpenID-Connect-OIDC-Identity-Federation-and-Lifecycle/01-oidc-core-id-token-vs-access-token-userinfo-discovery-and-at-hash-c-hash.md) | What each token is for and who may read it; Core §3.1.3.7 validation step by step; `nonce`, `at_hash`/`c_hash`, `auth_time`/`max_age`, `acr`, `azp`; nOAuth and multi-tenant issuer confusion; pairwise `sub`; Discovery and UserInfo trust; Spring's `OidcIdTokenValidator` defaults and three validators that close its gaps | L20 `OidcIdTokenLab`, L21 `SpringOidcLab` |
| [02 · Federation showdown: OIDC vs SAML 2.0 assertions, SCIM 2.0 provisioning](03-OpenID-Connect-OIDC-Identity-Federation-and-Lifecycle/02-federation-showdown-oidc-vs-saml2-assertions-and-scim2-Automated-provisioning.md) | Assertions in both worlds; XML-DSig, exclusive C14N and why comments vanish; signature wrapping, comment injection, XXE, parser differentials (ruby-saml 2025), Golden SAML; Spring SAML 2.0 SP on OpenSAML 5 and its Boot 4.1.2 properties; SCIM filters, PATCH, ETags and the leaver timeline | L22 `SamlXswLab`, L23 `ScimLab` |
| [03 · Distributed session termination: front- vs back-channel logout, CAEP](03-OpenID-Connect-OIDC-Identity-Federation-and-Lifecycle/03-distributed-session-termination-front-channel-vs-back-channel-logout-and-caep.md) | RP-initiated, front-channel and back-channel logout; logout-token rules (§2.4, §2.6, §4.1); third-party cookie blocking; SSF/CAEP/RISC 1.0 (Final, Sept 2025), SET (RFC 8417), push and poll delivery (RFC 8935/8936); Spring's back-channel logout run for real, and a hardened endpoint from public API | L24 `LogoutCaepLab`, L25 `SpringBackChannelLogoutLab` |

**Verified results:**
- **Oracles:** OIDC Core Appendix A (in [`fixtures/`](03-OpenID-Connect-OIDC-Identity-Federation-and-Lifecycle/fixtures/)). All 4 RS256 ID tokens verify under the A.7 key, and `at_hash` and `c_hash` reproduce exactly.
- **ID-token validation:**
  - across 9 attacks an L5 RP accepts 8; the L7 RP blocks all 9 (it rejects 8 and maps the nOAuth token to the attacker's own `iss|sub` account);
  - Spring's stock `OidcIdTokenValidator` accepts an untrusted extra audience (with `azp`), a stale `auth_time` and a weak `acr`; the hardened chain decides 8/8.
- **SAML on the JDK's XML-DSig:**
  - signature wrapping logs the L5 SP in as `admin`;
  - comment injection truncates `NameID` to `alice`;
  - JDK 25's default parser expands XXE;
  - the L7 SP rejects all three.
- **SCIM:**
  - string-built filters become SQL tautologies, while parse + bind keeps every value out of the SQL text;
  - without `If-Match`, a stale writer re-enables a leaver;
  - leaver exposure drops from 30 d to 40 min to 5 min 2 s.
- **Logout:**
  - a signature-only back-channel endpoint is logged out by 4 confused or replayed tokens, and the L7 endpoint by none;
  - front-channel logout works in 1 of 8 cookie/browser combinations.
- **Spring Security 7.1.2 `oidcLogout().backChannel()`, run on the real classes:**
  - it accepts untyped, `exp`-less and replayed logout tokens (a 2-hour-old `sub`-only token removes every session);
  - it rejects genuine ES256 logout tokens, because its decoder is RS256-only regardless of the ID-token algorithm;
  - it throws `AuthenticationServiceException`, rather than answering 400, for any signed OP JWT without `events`, because `LogoutTokenClaimAccessor.getEvents()` asserts;
  - none of this is configurable: the provider and its decoder-factory setter are package-private.
  
  A hardened endpoint from public API (`oidcSessionRegistry` + pinned decoder) gets all 7 cases right.

## Folder 04: High-security OAuth: FAPI 2.0, DPoP, mTLS and PAR

| File | Covers | Listings |
|---|---|---|
| [01 · Sender-constrained tokens: mTLS (RFC 8705) vs DPoP (RFC 9449)](04-High-Security-OAuth-FAPI2-DPoP-mTLS-and-PAR/01-sender-constrained-tokens-mtls-rfc8705-vs-dpop-rfc9449-proof-of-possession.md) | Bearer vs bound tokens under the FAPI attacker model; RFC 8705 client auth and `x5t#S256`; TLS termination; the DPoP proof, the twelve §4.3 checks, nonces and pre-generation, refresh and code binding (`dpop_jkt`), Bearer downgrade; Spring resource-server and authorization-server DPoP run for real; mTLS over real TLS 1.3; the decision table | L26 `DpopLab`, L27 `SpringDpopLab`, L28 `MtlsBindingLab`, L29 `SasDpopRefreshLab` |
| [02 · FAPI 2.0 Security Profile: PAR, JAR, JARM, RAR](04-High-Security-OAuth-FAPI2-DPoP-mTLS-and-PAR/02-fapi-2-security-profile-par-rfc9126-jar-jarm-and-rich-authorization-requests-rar.md) | Why the request leaves the browser; PAR rules; RAR at the AS and the RS; JAR and JARM under Message Signing; Spring Authorization Server 7.1.2 against FAPI 2.0, with a conformance table quoted from the profile; the hardening hooks | L30 `ParJarRarLab`, L31 `SasParLab` |
| [03 · Browser SPA security (RFC 10017) and the BFF](04-High-Security-OAuth-FAPI2-DPoP-mTLS-and-PAR/03-browser-spa-security-rfc10017-why-localstorage-fails-and-the-bff-token-handler-pattern.md) | XSS in RFC 10017's four scenarios; why storage choice and in-browser DPoP don't stop new-token acquisition; BFF vs token-mediating backend vs browser client; cookies, CSRF (including sibling subdomains), sealed sessions, proxy allow-lists; the Spring Security 7.1.2 servlet BFF | L32 `BrowserTokenLab`, L33 `BffTokenHandlerLab` |

**Verified results:**
- **Oracles:**
  - RFC 9449's two signed proofs verify, and `jkt` and `ath` reproduce byte for byte, both from scratch and through Spring's `DPoPProofJwtDecoderFactory` at the RFC's own clock;
  - RFC 9101's RS256 request object verifies under its JWK;
  - RFC 9396 Figure 1's IBAN passes mod-97.
- **DPoP:** across 8 attacks:
  - an RS that checks only signature + `jkt` accepts 7;
  - all twelve checks + a `jti` store accept 1 (XSS pre-generation);
  - with server nonces, 0.
- **Spring Security 7.1.2 resource-server DPoP, run for real:**
  - no `htu` normalization;
  - RS256 accepted and EdDSA rejected (against FAPI 2.0 §5.4.1);
  - the default replay cache refuses a single key's **1,001st** proof in its 30 s window (about 33 requests/s per key);
  - per-node caches allow cross-node replay;
  - no reactive DPoP.
  
  The verifier factory is replaceable.
- **Spring Authorization Server 7.1.2, run for real:**
  - a public client's DPoP-bound refresh token presented **without a DPoP header** returns a plain Bearer token (RFC 9449 §5 says the binding "MUST be validated"), and nothing forces a client to stay sender-constrained. A provider decorator fixes both;
  - its defaults meet **3 of 10** FAPI 2.0 requirements tested:
    - authorization codes last 5 min;
    - non-PAR requests are served;
    - client assertions are accepted with endpoint-URL or array `aud` and replayed `jti`;
    - there is no `iss` response parameter and no `dpop_jkt`;
    - JWTs are RS256;
    - there is no RAR.
  
  No upstream report for the refresh downgrade was found on 2026-11-06.
- **mTLS over real TLS 1.3:** a stolen token fails even with another certificate from the same CA. A forwarded certificate header trusted from anyone is beaten by a copied public certificate. Measured: about 13 ms per handshake vs about 0.7 ms per ES256 DPoP proof.
- **PAR/RAR:**
  - a front-channel IBAN swap leaves the consent screen unchanged;
  - PAR without client authentication, one-time use, expiry and binding loses 7 of 8 attacks;
  - FAPI 2.0 PAR loses 0;
  - a scope-only RS executes a EUR 9,999 payment on a EUR 123.50 consent.
- **Browser:**
  - every browser-only client, DPoP included, leaves the attacker **24 h** of access after an XSS is fixed (an independent token family);
  - a token-mediating backend leaves at most 5 min, and a BFF 0;
  - SameSite=Strict alone loses to a taken-over sibling subdomain;
  - three audience tokens in a sealed cookie need 4,150 B, over the 4,096 B floor.

## Folder 05: Microservices zero-trust propagation and authorization engines

| File | Covers | Listings |
|---|---|---|
| [01 · Gateway patterns: phantom token, introspection, caching](05-Microservices-Zero-Trust-Propagation-and-Authorization-Engines/01-gateway-patterns-phantom-token-pattern-opaque-to-jwt-introspection-and-caching.md) | Opaque outside and JWT inside; RFC 7662 and RFC 9701 on the wire; relay vs naive cache vs phantom token; cache design (hashed keys, TTL bounds, negative caching, revocation events, timeouts); Spring's opaque-token introspector run for real | L34 `PhantomTokenLab`, L35 `SpringIntrospectionLab` |
| [02 · Token relay vs RFC 8693 token exchange; SPIFFE/SPIRE](05-Microservices-Zero-Trust-Propagation-and-Authorization-Engines/02-east-west-propagation-token-relay-vs-rfc8693-token-exchange-and-spiffe-spire.md) | Two identities per call; exchange semantics (delegation, `act`, `may_act`, current-actor rule); Spring Authorization Server token exchange run for real and guarded; SPIFFE IDs, X.509- and JWT-SVIDs validated per the standards; propagation pattern choice | L36 `TokenExchangeLab`, L37 `SasTokenExchangeLab`, L38 `SpiffeSvidLab` |
| [03 · RBAC, ABAC, OPA, Cedar, PDP/PEP](05-Microservices-Zero-Trust-Propagation-and-Authorization-Engines/03-authorization-models-rbac-abac-policy-as-code-opa-cedar-and-pdp-pep-architecture.md) | PEP/PDP/PIP/PAP; model trade-offs; OPA vs Cedar semantics; one policy set under two engines; version-keyed decision caches; path confusion vs `StrictHttpFirewall`; PEP placement and AuthZEN | L39 `PolicyEngineLab`, L40 `SpringAuthzLab` |
| [04 · Zanzibar ReBAC internals](05-Microservices-Zero-Trust-Propagation-and-Authorization-Engines/04-google-zanzibar-rebac-internals-relation-tuples-usersets-leopard-index-and-new-enemy.md) | Tuples, usersets and rewrites; Check, Expand and Watch; the new-enemy problem and zookies; the Leopard index; modelling practice (OpenFGA DSL); consistency modes in OpenFGA and SpiceDB | L41 `ZanzibarLab` |

**Verified results:**
- **Phantom token:** relaying an opaque token costs 37,090 introspections and a raw-token 10-minute cache serves a revoked token for 499 s, while the L7 gateway (hashed key, min(exp, 60 s), eviction on events) makes 592 calls with zero exposure.
- **Spring's `SpringOpaqueTokenIntrospector`,** run for real, accepts tokens for another audience and expired tokens, caches nothing, and blocks for the full duration of an AS stall. A hardened wrapper fixes all three.
- **Token exchange:**
  - with relay, a compromised service wins 6 of 6 attacks; with exchange plus current-actor RS checks it wins 0;
  - Spring Authorization Server 7.1.2's token exchange, run for real:
    - grants scopes the user never had (it validates against the caller's registration);
    - ignores the requested audience;
    - lets any token-exchange client trade a subject token not issued to it;
    - allows silent impersonation.
  - A guarded provider and an `aud` customizer fix these.
- **SPIFFE:**
  - 11 of 11 X.509-SVID cases (real certificates, JDK PKIX per trust domain) and 6 of 6 JWT-SVID cases are decided correctly per the standards;
  - prefix matching on SPIFFE IDs over-authorizes 2 of 3 callers.
- **Policy engines:** first-match ordering, default allow, client-supplied attributes and prefix matching let 6 of 6 attacks through, and Cedar semantics with a PIP let 0. A version-blind decision cache keeps a revoked admin in for about 10 minutes.
- **Path confusion:** with no firewall, 4 path-confusion URIs bypass `/admin/**` after container normalization, and Spring's `StrictHttpFirewall` rejects all of them.
- **Zanzibar:** a mixed-snapshot check lets a removed user see content added after his removal, and a zookie-bounded snapshot denies him. Leopard replaces 22 tuple reads with 1 lookup.

## Folder 06: Cloud security equivalents (AWS, GCP, Azure) and AI agents

| File | Covers | Listings |
|---|---|---|
| [01 · Cloud IAM internals: AWS STS, IRSA, EKS Pod Identity vs GCP WIF (and Azure)](06-Cloud-Security-Equivalents-AWS-GCP-Azure-and-AI-Agents/01-cloud-iam-internals-aws-sts-irsa-pod-identity-vs-gcp-workload-identity-federation.md) | Keyless federation in three clouds; trust conditions as the authorization; Kubernetes workload identity compared; metadata services and SSRF; session lifetimes and down-scoping | L42 `CloudFederationLab`, L43 `ImdsSsrfLab` |
| [02 · Managed CIAM: Cognito vs GCP Identity Platform vs Entra vs Keycloak](06-Cloud-Security-Equivalents-AWS-GCP-Azure-and-AI-Agents/02-managed-ciam-architectures-cognito-vs-gcp-identity-platform-vs-entra-vs-keycloak.md) | What the platform owns vs what you own; each platform's token conventions; platform pitfalls (user-writable attributes, self-service sign-up, hooks); choosing a platform | L44 `CiamTokenLab` |
| [03 · Securing AI agents and MCP servers](06-Cloud-Security-Equivalents-AWS-GCP-Azure-and-AI-Agents/03-securing-ai-agents-and-mcp-servers-oauth21-dynamic-client-registration-and-obo.md) | The MCP 2026-07-28 authorization profile (RFC 9728 discovery, RFC 8707 audience, no token passthrough, CIMD over deprecated DCR, AS binding, RFC 9207, PKCE); the agent layer (per-tool scopes, step-up, approval, OBO with `act`); Spring's RFC 9728 support | L45 `McpAuthLab` |

**Verified results:**
- **Federation:**
  - an AWS OIDC trust on `aud` alone admits every GitHub repository;
  - `repo:acme/*` admits branches, sandboxes and a re-registered org;
  - name-based `sub` matching (AWS exact `sub`, Azure FIC, GCP name-based principalSet) admits a rename takeover;
  - only GCP conditions on immutable `repository_owner_id`/`repository_id` admit just the legitimate token;
  - IRSA on `aud` alone admits every service account.
- **Metadata services:** IMDSv1 leaks to 5 of 5 SSRF classes and IMDSv2 with hop limit 1 to 1 (host code only); hop limit 2 re-opens pods; GCP/Azure header gates stop URL-only SSRF only.
- **CIAM:** a generic validator accepts 7 of 7 cross-client, cross-tenant, cross-project and wrong-type tokens across Cognito, Entra, Firebase and Keycloak, while provider-aware validation accepts 0.
- **MCP:** L5 lets 10 of 10 spec violations through and L7 refuses all 10. A prompt-injected high-risk tool call is blocked without step-up and explicit approval.

## Folder 07: Production Java 21 / Spring Security blueprints

| File | Covers | Listings |
|---|---|---|
| [01 · Spring Authorization Server: custom JWT (RFC 9068), PKCE and key rotation](07-Production-Java21-Spring-Security-and-Keycloak-Blueprints/01-spring-authorization-server-custom-jwt-rfc9068-pkce-and-key-rotation-code.md) | The AS's per-token decisions; the RFC 9068 customizer (ES256, `at+jwt`, pinned `kid`, resource `aud`); a FAPI-grade `RegisteredClient`; the resource-server validator trap; publish → switch → retire rotation | L46 `SasJwtBlueprint` |
| [02 · Spring Cloud Gateway BFF: OAuth2 client, Redis session, token relay](07-Production-Java21-Spring-Security-and-Keycloak-Blueprints/02-spring-cloud-gateway-bff-oauth2-client-redis-session-and-token-relay-code.md) | The BFF as a confidential client; `__Host-` session cookies in Redis; `TokenRelay=`; refresh concurrency against a rotating AS; failure handlers that drop dead tokens | L47 `BffRelayLab` |
| [03 · Resource server: multi-tenant JWKS, DPoP, method security](07-Production-Java21-Spring-Security-and-Keycloak-Blueprints/03-spring-security-resource-server-multi-tenant-jwks-dpop-and-method-security-code.md) | Exact issuer registries vs predicates; per-tenant validator composition; DPoP with a per-issuer resolver; `@PreAuthorize` tenant binding; offboarding | L48 `MultiTenantRsLab` |
| [04 · OpenFGA (Zanzibar) and OPA in Java 21 microservices](07-Production-Java21-Spring-Security-and-Keycloak-Blueprints/04-openfga-zanzibar-and-opa-integration-in-java21-microservices.md) | PEP placement; OpenFGA consistency preferences and the check cache; fail-closed clients on virtual threads; OPA's undefined decision; signed bundles; batch checks | L49 `FgaOpaClientLab` |

**Verified results:**
- **SAS tokens (L46):**
  - the stock `JwtGenerator` can't sign with an EC-only key ring;
  - `createDefaultWithIssuer` plus a sibling `JwtTypeValidator("at+jwt")` rejects every RFC 9068 token;
  - `NimbusJwtEncoder` refuses to choose between two same-algorithm keys without a pinned `kid`.
- **BFF (L47):** concurrent requests against a rotating AS trigger refresh-token reuse detection and revoke the family. A single-flight manager keyed by registration and principal refreshes once.
- **Multi-tenant resource server (L48):**
  - `fromTrustedIssuers(a, b)` refuses a look-alike issuer with no network call;
  - a `startsWith` predicate fetches the attacker's discovery and JWKS and accepts its token;
  - `@PreAuthorize` denies cross-tenant and missing-scope calls.
- **Validator composition (L48 §4):**
  - **New:** `createAtJwtValidator()` alone accepts an mTLS-bound token presented with no client certificate. It omits the package-private `X509CertificateThumbprintValidator`.
  - `createDefaultWithValidators([atJwt])` rejects every RFC 9068 token.
  - `createDefaultWithValidators([JwtTypeValidator("at+jwt"), atJwt])` gets all three right.
- **Authorization engines (L49):**
  - with OpenFGA's check cache on, `MINIMIZE_LATENCY` allows a just-revoked user, and `HIGHER_CONSISTENCY` denies;
  - a stalled PDP gives a DENY within 1 s at 300 ms timeouts;
  - OPA's undefined decision (`200 {}`) is an ALLOW under `!= false` and a DENY under `== true`.

## Folder 08: Attack playbook, references and L7 bar-raiser Q&A

| File | Covers | Listings |
|---|---|---|
| [01 · 20 real-world OAuth, OIDC and JWT exploits and exact code defenses](08-Attack-Playbook-GitHub-References-and-L7-Bar-Raiser-QA/01-20-real-world-oauth-oidc-and-jwt-exploits-and-exact-code-defenses.md) | Twenty documented incidents and CVEs (2015–2025), from algorithm confusion and psychic signatures through Storm-0558, Entra actor tokens, nOAuth, BingBang, Booking.com, dirty dancing, Keycloak redirect bypasses, private_key_jwt audience injection, stolen integration tokens, Midnight Blizzard, HAR-file session theft, GitHub→AWS trust policies, `mcp-remote` and Spring's generic-annotation CVE. Each has incident facts from primary sources, the mechanism, the code defense and the regressing listing | L50 `ExploitRegressionLab` |
| [02 · 35 FAANG and FinTech L7 security-architecture bar-raiser chains](08-Attack-Playbook-GitHub-References-and-L7-Bar-Raiser-QA/02-35-faang-and-fintech-l7-security-architecture-bar-raiser-qna-chains.md) | Cross-cutting system-design chains in six groups (authentication, protocol, FAPI, authorization, cloud and agents, platform leadership), a leveling rubric, and the eight attack shapes behind them | earlier listings |
| [03 · Curated GitHub repositories, RFCs and security blogs: a study guide](08-Attack-Playbook-GitHub-References-and-L7-Bar-Raiser-QA/03-curated-github-repositories-rfcs-and-security-blogs-study-guide.md) | A 12-week plan mapped to the listings; what to read in each repository; the RFC dependency order; blogs, research and labs; the regression-test habit | earlier listings |

**Verified results:**
- **L50 replays six documented exploit payloads against the pinned stack,** each beside a passing control, and all are refused:
  - `alg: none` and HS256 keyed with the RSA public key;
  - an embedded `jwk`;
  - ECDSA r = s = 0, refused by JDK 25, Nimbus and Spring;
  - PBES2 `p2c` = 2×10⁹, against Nimbus's 1,000,000 cap;
  - 100,000-deep claims, refused as "Malformed payload" *before* signature verification, so it is a pre-authentication parse surface;
  - CVE-2025-41248's generic hierarchy, enforced on Spring Security 7.1.2 with JDK and CGLIB proxies.
- **Incident facts** were checked against primary sources on 2026-11-06. Where sources disagree, both are given, for example CVE-2025-41248's fixed versions on spring.io vs GitHub. Capital One 2019 was excluded, because no retrievable primary source states the SSRF/IMDS detail.

## How the code is verified

All listings in a folder compile as one unit with `javac --release 21 -Xlint:all -Werror` on Temurin JDK 25.0.4.1. The classpath is a set of jars SHA-1-checked against Maven Central:
- Spring Security 7.1.2;
- Spring Framework 7.0.10;
- BouncyCastle 1.86 (bcprov, plus bcpkix and bcutil for the X.509 certificates in Folder 04);
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
  - OAuth 2.1, still an Internet-Draft (draft-ietf-oauth-v2-1-17, 2026-10-31, per the IETF Datatracker);
  - OpenID Shared Signals Framework, CAEP and RISC 1.0 (Final Specifications, September 2025).
- Composite "L5" code samples are illustrations of review findings, not code from any one system.
